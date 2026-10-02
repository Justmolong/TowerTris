//============================================================================================
// zzztoj_worker —— 用 zzztoj(paback2/zzztoj) 给 TowerTris 做决策的独立进程
//
// 架构与 zzztoj/src/io_dll.cpp 相同：
//   m_tetris::TetrisEngine<rule_asc::TetrisRule, ai_zzz::IO, search_amini::Search>
// 差别：由「DLL 被游戏加载」改为「独立进程 + 行协议」，便于 Godot 侧 spawn 子进程。
//
// 协议（stdin 一行一条命令，stdout 一行一条回复）：
//   PING                                            -> OK
//   CFG <think> <gcap> <mult> <lockout> <hold> <a180> <amini> <aspin> <tspin> <immobileT>
//       [<rotMode> [<btbSystem> [<pcDamage>]]]     -> OK
//       第 12 个字段 rotMode：0=ASC 1=SRS 2=ARS 3=NONE（无旋转系统）
//       第 13 个字段 btbSystem：1=surge break 系统 / 2=累加奖励系统（对应游戏 btb_system_use）
//       第 14 个字段 pcDamage：PC 附加伤害（对应游戏 pc_damage）
//   REQ <40 行位掩码(底行在前,十进制)> <active> <hold|-> <canHoldNow> <next串> <b2b> <combo>
//       <预告垃圾合计> <格数> <x1> <y1> ...               -> OK <path> | ERR
//   QUIT                                            -> 退出
//   其中 <active>/<hold>/<next> 用字符 ITLJZSO；x/y 为本游戏坐标（y 向下、底行 = 89），
//   由本进程换算到 zzz 坐标（y 向上、底行 = 0）后**按格子集合匹配节点**，因此不依赖旋转编号约定。
//   path 字符集与 io_dll 一致：l/r/d 一格、L/R 到头、D 落到底、z 逆时针、c 顺时针，
//   末尾 'V' = 落地(硬降)，开头 'v' = 建议先 Hold。
//
// ⚠ <hold> 的「空」写作 '-'（本游戏约定），进引擎前必须换成空格（zzz 约定）；
//   绝不能把非方块字符交给引擎：TetrisContext::convert() 对未知字符会读到未初始化的表项，
//   get_block() 里就成了野指针，实测直接把进程打成 0xC0000005（见 sanitize_piece_char）。
//   <active> 必须是 ITLJZSO 之一，否则本函数返回 ERR（并写 stderr）。
//============================================================================================
#include <algorithm>
#include <climits>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <iostream>
#include <string>
#include <vector>

#include "ai_zzz.h"
#include "random.h"
#include "rule_asc.h"
#include "search_amini.h"
#include "tetris_core.h"

using namespace m_tetris;

static m_tetris::TetrisEngine<rule_asc::TetrisRule, ai_zzz::IO, search_amini::Search> g_ai;
static bool g_prepared = false;
static int g_prepared_kick_mode = -1;
// 踢墙模式（与游戏 RotationSystemType 对应）：0=ASC 1=SRS 2=ARS 3=NONE（无旋转系统），由 CFG 第 11 个字段下发
static int g_kick_mode = 0;
// 最近一次 CFG 参数（reprepare 后需要重新应用）
static int g_last_think = 100, g_last_gcap = 8, g_last_mult = 1;
static bool g_last_lockout = false, g_last_can_hold = true, g_last_allow180 = true;
static bool g_last_amini = true, g_last_aspin = false, g_last_tspin = true, g_last_immobile_t = true;
// 游戏的 Spin 规则模式（TetrisClearLine.no_spin）：0=正常 1=只判T 2=全降级Mini 3=不判 4=判但Spin必死
static int g_no_spin = 0;
// no_spin==4 时游戏每次触发 Spin 上涨的实心行数（用于换算惩罚力度）
static int g_no_spin4_rows = 20;
// BTB 加成系统（1=surge break / 2=累加奖励）与 PC 伤害：与游戏侧 btb_system_use / pc_damage 对应
static int g_last_btb_system = 1, g_last_pc_damage = 6;

// 本游戏可玩区域：10 宽 × 90 行(y 向下)，底行 y = 89
static const int GAME_W = 10;
static const int GAME_BOTTOM_Y = 89;

// 与游戏一致的默认参数
static int g_think = 100;      // 思考预算（传给 run 的 think_limit，越大越强越慢）
static int g_gcap = 8;
static int g_mult = 1;
static bool g_lockout = false;
static bool g_can_hold_global = true;
static int g_level = 8;
static int g_last_level_applied = -1;

static void node_cells(TetrisNode const *n, std::vector<std::pair<int, int>> &out)
{
    out.clear();
    if (n == nullptr)
        return;
    for (int i = 0; i < n->width; ++i)
        for (int y = n->bottom[i]; y < n->top[i]; ++y)
            out.push_back(std::make_pair(n->col + i, y));
}

// 决策落点描述："<方块> <最小x> <最小y> <旋转>"（zzz 坐标，y 向上）。
// 附在回复末尾，游戏侧可以拿它和实际锁定位置对照，验证「决策 ↔ 落点」是否一致。
static std::string g_last_target;

static std::string node_target_desc(TetrisNode const *n)
{
    if (n == nullptr)
        return std::string();
    std::vector<std::pair<int, int>> cells;
    node_cells(n, cells);
    if (cells.empty())
        return std::string();
    int minX = INT_MAX, minY = INT_MAX;
    for (size_t i = 0; i < cells.size(); ++i)
    {
        minX = std::min(minX, cells[i].first);
        minY = std::min(minY, cells[i].second);
    }
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%c %d %d %d", n->status.t, minX, minY, (int)n->status.r);
    return std::string(buf);
}

// 由「本游戏的方块格子」找到 zzz 的节点。// rot_hint = 本游戏的 current_rotation_index（0..3），-1 = 未知。
// 两边旋转下标语义已核对一致（都以「从 spawn 顺时针转几次」编号，见 nodes 诊断命令），
// 因此优先按 rot_hint 匹配：必须优先，否则 I/S/Z 这种「r0 与 r2 格子集合相同」的方块会被
// 匹配成错误旋转态（旋转下标差 2 → 后续 'c'/'z' 转出不同形状 → 实际落点和决策不一致）。
static TetrisNode const *find_node(char piece, std::vector<std::pair<int, int>> const &zzz_cells,
                                   int rot_hint, std::string *dbg)
{
    int tgtMinX = INT_MAX, tgtMinY = INT_MAX;
    for (size_t i = 0; i < zzz_cells.size(); ++i)
    {
        tgtMinX = std::min(tgtMinX, zzz_cells[i].first);
        tgtMinY = std::min(tgtMinY, zzz_cells[i].second);
    }
    int order[4] = {0, 1, 2, 3};
    if (rot_hint >= 0 && rot_hint < 4)
    {
        // 把提示的旋转态排到最前面，其余按原顺序兜底
        order[0] = rot_hint;
        int k = 1;
        for (int r = 0; r < 4; ++r)
            if (r != rot_hint)
                order[k++] = r;
    }
    for (int oi = 0; oi < 4; ++oi)
    {
        uint8_t r = (uint8_t)order[oi];
        TetrisNode const *ref = g_ai.get(TetrisBlockStatus(piece, 3, 20, r));
        if (ref == nullptr)
            continue;
        std::vector<std::pair<int, int>> refc;
        node_cells(ref, refc);
        if (refc.empty())
            continue;
        int refMinX = INT_MAX, refMinY = INT_MAX;
        for (size_t i = 0; i < refc.size(); ++i)
        {
            refMinX = std::min(refMinX, refc[i].first);
            refMinY = std::min(refMinY, refc[i].second);
        }
        int x = 3 + (tgtMinX - refMinX);
        int y = 20 + (tgtMinY - refMinY);
        TetrisNode const *cand = g_ai.get(TetrisBlockStatus(piece, (int8_t)x, (int8_t)y, r));
        if (cand == nullptr)
            continue;
        std::vector<std::pair<int, int>> cc;
        node_cells(cand, cc);
        std::vector<std::pair<int, int>> want = zzz_cells;
        std::sort(cc.begin(), cc.end());
        std::sort(want.begin(), want.end());
        if (cc == want)
        {
            if (dbg != nullptr)
            {
                char buf[128];
                std::snprintf(buf, sizeof(buf), "matched rot=%d x=%d y=%d", (int)r, x, y);
                *dbg = buf;
            }
            return cand;
        }
    }
    return nullptr;
}

// 按当前等级/规则设置 search 与 ai 配置（等级变化时才 update）
// 按当前等级/规则设置 search 与 ai 配置
// 参数 think = 协议里 CFG 的第一个字段，语义为「搜索时间上限（毫秒）」。
// 注意：上游 io_dll 把该字段当作等级并用 pow 换算 think_limit（等级 100 会变成几乎无限的耗时），
// 本工程按协议注释直接当毫秒用，并做上限保护。
static void apply_config(int think, int gcap, int mult, bool lockout, bool can_hold,
                         bool allow180, bool amini, bool aspin, bool tspin, bool immobile_t,
                         int btb_system, int pc_damage)
{
    g_think = think > 2000 ? 2000 : (think < 1 ? 1 : think);
    search_amini::Search::Config *sc = g_ai.search_config();
    sc->allow_rotate_move = false;
    sc->allow_180 = allow180;
    sc->allow_d = true;
    sc->allow_D = true;
    sc->allow_LR = true;
    sc->is_20g = false;
    sc->last_rotate = true;
    sc->is_amini = amini;
    sc->is_aspin = aspin;
    sc->is_tspin = tspin;
    sc->allow_immobile_t = immobile_t;
    // NoSpin 模式对齐：no_spin==2（所有 Spin 降级为 Mini）时，引擎判出的全旋也标成 Mini
    sc->spin_force_mini = (g_no_spin == 2);

    ai_zzz::IO::Config *ac = g_ai.ai_config();
    ac->is_margin = false;
    ac->season_2 = immobile_t;   // 与 io_dll 一致：season_2 对应「不可移动即 T-Spin」档
    ac->btb_system = btb_system; // BTB 加成模型（与游戏 btb_system_use 一致，不再借用 season_2）
    ac->pc_damage = pc_damage;   // PC 附加伤害（与游戏 pc_damage 一致）
    ac->lockout = lockout;
    ac->multiplier = mult;
    ac->garbage_cap = gcap;
    // NoSpin 模式对齐：
    //   no_spin==2 → T-Spin 也按 Mini 上报（与游戏的 "Mini T-Spin" 及 mini 伤害表一致）
    //   no_spin==4 → 任何 Spin（含 Spin0）都是必死，用极大权重惩罚让 bot 绝不选择 Spin
    ac->spin_force_mini = (g_no_spin == 2);
    ac->spin_death_penalty = (g_no_spin == 4)
        ? (g_no_spin4_rows > 0 ? g_no_spin4_rows * 5000.0 : 100000.0)
        : 0.0;

    // 权重：直接采用 zzztoj 自带 io-DLL 的调参（src/io_dll.cpp 里的 init_21 候选，25 项按 Param 字段顺序）
    ai_zzz::IO::Param &pp = ac->param;
    pp.roof = 128.848632018967038;
    pp.col_trans = 159.486229165944053;
    pp.row_trans = 161.917442316092604;
    pp.hole_count = 81.770591639349178;
    pp.hole_line = 381.778776257560935;
    pp.well_depth = 98.094088345045122;
    pp.hole_depth = 34.677952239613163;
    pp.b2b = 129.220619858914347;
    pp.attack = 0.911925860653483;
    pp.hold_t = 3.743571313305299;
    pp.hold_i = 3.153364454826400;
    pp.waste_t = 0.007065131195186;
    pp.waste_i = -0.081683675915618;
    pp.clear_1 = -0.954530616937391;
    pp.clear_2 = 1.612455139641956;
    pp.clear_3 = 0.570015487183247;
    pp.clear_4 = 1.093367709554965;
    pp.t2_slot = 1.511144844202827;
    pp.t3_slot = 1.007928243238620;
    pp.tspin_mini = -0.740554584228066;
    pp.tspin_1 = 0.104364933113540;
    pp.tspin_2 = 8.660904648990943;
    pp.tspin_3 = 12.172353417045528;
    pp.combo = 30.511480066561280;
    pp.ratio = 1.585887060974325;

    // ============================================================================
    // NoSpin 模式下的 Spin 权重对齐
    // io-DLL 的默认权重建立在「Spin 有额外攻击与分数」之上；游戏换了 Spin 规则后必须跟着改，
    // 否则 bot 依旧会为 Spin 布局（T 槽、留 T、路径以旋转收尾），即「开了 NoSpin 还在找 Spin」。
    // Spin 的价值链：模式2 低分（=普通消行） → 模式3 没分 → 模式4 判死。
    //   模式2（无天赋II，全部降级 Mini）：游戏 _calculate_damage 对 Mini 用**基础伤害表**，
    //        即「Spin 与同消行数的普通消行等价」→ spin 权重对齐到对应 clear 权重，T 槽价值清零。
    //   模式3（无天赋III，完全不判 Spin）：Spin 没有任何收益 → spin 权重与 T 槽/留 T 权重归零，
    //        并关闭「路径以旋转收尾」偏好（last_rotate=false），不再为 Spin 而转。
    //   模式4（无天赋IV，判但必死）：收益同样为 0，另由 spin_death_penalty 施加极大惩罚；
    //        但**保留** last_rotate 与判定开关，让引擎能认出 Spin 从而主动躲开（关掉反而会踩雷）。
    // ============================================================================
    if (g_no_spin == 2)
    {
        pp.tspin_mini = pp.clear_1;
        pp.tspin_1 = pp.clear_1;
        pp.tspin_2 = pp.clear_2;
        pp.tspin_3 = pp.clear_3;
        pp.t2_slot = 0;
        pp.t3_slot = 0;
        sc->last_rotate = true;
    }
    else if (g_no_spin == 3)
    {
        pp.tspin_mini = 0;
        pp.tspin_1 = 0;
        pp.tspin_2 = 0;
        pp.tspin_3 = 0;
        pp.t2_slot = 0;
        pp.t3_slot = 0;
        pp.hold_t = 0;          // 留 T 的主要意义就是做 Spin
        sc->last_rotate = false;
    }
    else if (g_no_spin == 4)
    {
        pp.tspin_mini = 0;
        pp.tspin_1 = 0;
        pp.tspin_2 = 0;
        pp.tspin_3 = 0;
        pp.t2_slot = 0;
        pp.t3_slot = 0;
        pp.hold_t = 0;
        sc->last_rotate = true; // 保留旋转收尾判定，让 Spin 能被认出来并吃惩罚
    }

    // 引擎等级固定为 io-DLL 默认 8：本工程只把 CFG 首字段当搜索时间预算，不用它当等级
    // （上游用 pow(100^(1/8), level) 换算，等级被填成 100 时会变成几乎无限耗时）。
    const int level = 8;
    g_level = level;
    g_gcap = gcap;
    g_mult = mult;
    g_lockout = lockout;
    g_can_hold_global = can_hold;
    // 记录最近一次 CFG，供 reprepare（切换踢墙模式）之后重新应用
    g_last_think = think;
    g_last_gcap = gcap;
    g_last_mult = mult;
    g_last_lockout = lockout;
    g_last_can_hold = can_hold;
    g_last_allow180 = allow180;
    g_last_amini = amini;
    g_last_aspin = aspin;
    g_last_tspin = tspin;
    g_last_immobile_t = immobile_t;
    g_last_btb_system = btb_system;
    g_last_pc_damage = pc_damage;
    if (g_last_level_applied != level)
    {
        g_last_level_applied = level;
        g_ai.update();
    }

    // 诊断：仅在环境变量 ZZZ_LOG_PARAMS=1 时，把本次 CFG 生效后的关键决策参数打到 stderr。
    // 桥会把 worker 的 stderr 转成 push_warning，因此游戏日志里能直接看到
    // 「参数在什么时候、被哪次 CFG 改成了什么」——用于排查参数异常变化。
    if (std::getenv("ZZZ_LOG_PARAMS") != nullptr)
    {
        std::fprintf(stderr,
            "[params] think=%d gcap=%d mult=%d kick=%d no_spin=%d force_mini=%d death=%.0f "
            "amini=%d aspin=%d tspin=%d immobile=%d last_rotate=%d btb=%d pc=%d | "
            "tspin_mini=%.3f t_1=%.3f t_2=%.3f t_3=%.3f t2=%.3f t3=%.3f hold_t=%.3f hold_i=%.3f "
            "clear1=%.3f clear2=%.3f clear3=%.3f clear4=%.3f b2b=%.3f attack=%.3f ratio=%.3f\n",
            g_think, gcap, mult, g_kick_mode, g_no_spin, (int)ac->spin_force_mini, ac->spin_death_penalty,
            (int)sc->is_amini, (int)sc->is_aspin, (int)sc->is_tspin, (int)sc->allow_immobile_t,
            (int)sc->last_rotate, btb_system, pc_damage,
            pp.tspin_mini, pp.tspin_1, pp.tspin_2, pp.tspin_3, pp.t2_slot, pp.t3_slot, pp.hold_t, pp.hold_i,
            pp.clear_1, pp.clear_2, pp.clear_3, pp.clear_4, pp.b2b, pp.attack, pp.ratio);
        std::fflush(stderr);
    }
}

static bool prepare_ai()
{
    // 踢墙表在 prepare 时被烘焙进节点：踢墙模式变化必须重建 context
    // （prepare() 在尺寸不变时会直接 return true，不会重新读取 get_opertion()）
    if (g_prepared && g_prepared_kick_mode == g_kick_mode)
        return true;
    rule_asc::g_kick_mode = g_kick_mode;
    bool ok = true;
    if (g_prepared)
    {
        ok = g_ai.reprepare(GAME_W, 40);
        if (ok)
            apply_config(g_last_think, g_last_gcap, g_last_mult, g_last_lockout, g_last_can_hold,
                         g_last_allow180, g_last_amini, g_last_aspin, g_last_tspin, g_last_immobile_t,
                         g_last_btb_system, g_last_pc_damage);
    }
    else if (!g_ai.prepare(GAME_W, 40))
    {
        return false;
    }
    if (!ok)
        return false;
    g_ai.memory_limit(512ull << 20);
    if (!g_prepared)
        apply_config(100, 8, 1, false, true, true, true, false, true, true, g_last_btb_system, g_last_pc_damage);
    g_prepared = true;
    g_prepared_kick_mode = g_kick_mode;
    return true;
}

// 按名字覆盖 ai_zzz::IO::Param 的某一项（供 buff 的 ExtraBotChange 下发）
static bool set_param_by_name(std::string const &name, double v)
{
    if (!prepare_ai())
        return false;
    ai_zzz::IO::Param &p = g_ai.ai_config()->param;
    if (name == "roof") p.roof = v;
    else if (name == "col_trans") p.col_trans = v;
    else if (name == "row_trans") p.row_trans = v;
    else if (name == "hole_count") p.hole_count = v;
    else if (name == "hole_line") p.hole_line = v;
    else if (name == "well_depth") p.well_depth = v;
    else if (name == "hole_depth") p.hole_depth = v;
    else if (name == "b2b") p.b2b = v;
    else if (name == "attack") p.attack = v;
    else if (name == "hold_t") p.hold_t = v;
    else if (name == "hold_i") p.hold_i = v;
    else if (name == "waste_t") p.waste_t = v;
    else if (name == "waste_i") p.waste_i = v;
    else if (name == "clear_1") p.clear_1 = v;
    else if (name == "clear_2") p.clear_2 = v;
    else if (name == "clear_3") p.clear_3 = v;
    else if (name == "clear_4") p.clear_4 = v;
    else if (name == "t2_slot") p.t2_slot = v;
    else if (name == "t3_slot") p.t3_slot = v;
    else if (name == "tspin_mini") p.tspin_mini = v;
    else if (name == "tspin_1") p.tspin_1 = v;
    else if (name == "tspin_2") p.tspin_2 = v;
    else if (name == "tspin_3") p.tspin_3 = v;
    else if (name == "combo") p.combo = v;
    else if (name == "ratio") p.ratio = v;
    else return false;
    return true;
}

// 方块字符合法性校验：zzz 只认识 I/J/L/O/S/T/Z（大小写）。
// ⚠ 绝不能把其它字符（尤其是本游戏「空 hold」用的 '-'）传进引擎：
// TetrisContext::convert() 查的是一张只填了 7 种方块的 256 项表，未初始化的表项会让
// get_block() 里 &node_block_[垃圾下标*4+r] 变成野指针，实测直接把 worker 打成 0xC0000005。
static bool is_valid_piece_char(char c)
{
    switch (::toupper((unsigned char)c))
    {
    case 'I': case 'J': case 'L': case 'O': case 'S': case 'T': case 'Z':
        return true;
    default:
        return false;
    }
}

// 把协议里的方块 token 变成引擎能安全接受的字；非法字符退回 fallback（hold 用空格）
static char sanitize_piece_char(std::string const &tok, char fallback)
{
    if (tok.empty())
        return fallback;
    char c = tok[0];
    if (is_valid_piece_char(c))
        return c;
    if (c != '-')   // '-' 就是「空」的正常写法，不当异常；其它字符才是异常
        std::fprintf(stderr, "[zzztoj_worker] 非法方块字符 '%c' -> 按空处理\n", c);
    return fallback;
}

// 处理一条 REQ：返回 path 字符集；失败返回空串
static std::string handle_request(std::vector<std::string> const &tok)
{
    // 位置定义（见文件头协议）
    const size_t kRows = 40;
    size_t i = 1;
    if (tok.size() < kRows + 9)
        return std::string();

    uint32_t rows[kRows];
    for (size_t d = 0; d < kRows; ++d)
        rows[d] = (uint32_t)std::strtoul(tok[i++].c_str(), nullptr, 10);

    std::string activeTok = tok[i++];
    char active = sanitize_piece_char(activeTok, '\0');
    if (active == '\0')
    {
        std::fprintf(stderr, "[zzztoj_worker] active 方块非法: '%s'\n", activeTok.c_str());
        return std::string();
    }
    std::string holdTok = tok[i++];
    bool canHoldNow = tok[i++] == "1";
    std::string nextStr = tok[i++];
    int b2b = std::atoi(tok[i++].c_str());
    int combo = std::atoi(tok[i++].c_str());
    int upcome = std::atoi(tok[i++].c_str());
    int nCells = std::atoi(tok[i++].c_str());
    if (i + (size_t)nCells * 2 > tok.size())
        return std::string();

    std::vector<std::pair<int, int>> zzzCells;   // zzz 坐标：y 向上、底行 0
    for (int k = 0; k < nCells; ++k)
    {
        int gx = std::atoi(tok[i++].c_str());
        int gy = std::atoi(tok[i++].c_str());
        zzzCells.push_back(std::make_pair(gx, GAME_BOTTOM_Y - gy));
    }

    // 可选尾部三项：上一手 spin 类型 / 上一手消行数 / Allspin 重复惩罚扣分（0 = 关闭）
    int last_spin_type = 0;
    int last_clear_count = 0;
    double repeat_penalty = 0.0;
    int rot_hint = -1;   // 可选第 4 项：本游戏 current_rotation_index（0..3）
    if (i + 3 <= tok.size())
    {
        last_spin_type = std::atoi(tok[i].c_str());
        last_clear_count = std::atoi(tok[i + 1].c_str());
        repeat_penalty = std::atof(tok[i + 2].c_str());
    }
    if (i + 4 <= tok.size())
        rot_hint = std::atoi(tok[i + 3].c_str());

    if (!prepare_ai())
        return std::string();

    TetrisMap map(GAME_W, 40);
    for (size_t d = 0; d < kRows; ++d)
        map.row[d] = rows[d];
    for (int my = 0; my < map.height; ++my)
    {
        for (int mx = 0; mx < map.width; ++mx)
        {
            if (map.full(mx, my))
            {
                map.top[mx] = map.roof = my + 1;
                map.row[my] |= 1 << mx;
                ++map.count;
            }
        }
    }

    std::string dbg;
    TetrisNode const *node = find_node(active, zzzCells, rot_hint, &dbg);
    if (node == nullptr)
    {
        std::fprintf(stderr, "[zzztoj_worker] 未能匹配当前方块节点\n");
        return std::string();
    }

    auto *st = g_ai.status();
    st->max_combo = 0;
    st->attack = 0;
    st->b2bcnt = b2b;
    st->board_fill = map.count;
    st->death = 0;
    st->combo = combo;
    st->map_rise = 0;
    st->like = 0;
    st->value = 0;
    st->pc = true;
    if (st->under_attack != upcome)
        g_ai.update();
    st->under_attack = upcome;

    // Allspin 重复性惩罚（本游戏 Allspin_1：与上一手同类型 spin + 同行数 → 立刻涨一行垃圾）
    g_ai.ai_config()->repeat_penalty = repeat_penalty;
    g_ai.ai_config()->last_spin_type = last_spin_type;
    g_ai.ai_config()->last_clear_count = last_clear_count;

    int maxDepth = (int)nextStr.size();
    std::string result;
    bool got_target = false;
    char holdChar = sanitize_piece_char(holdTok, ' ');   // 本游戏的空 hold 哨兵是 '-'，zzz 约定是空格
    g_last_target.clear();

    if (g_can_hold_global)
    {
        auto rr = g_ai.run_hold(map, node, holdChar, canHoldNow, nextStr.c_str(), maxDepth, g_think);
        if (rr.target != nullptr)
        {
            TetrisNode const *from = rr.change_hold ? g_ai.context()->generate(rr.target->status.t) : node;
            std::vector<char> path = g_ai.make_path(from, rr.target, map);
            result.assign(path.begin(), path.end());
            got_target = true;
            g_last_target = node_target_desc(rr.target);
        }
        if (rr.change_hold)
            result.insert(result.begin(), 'v');
        // hold 路径搜不到落点（实测：hold 槽已被占用 + 版面非空时 zzz 的 run_hold 会返回空结果，
        // 上游 io_dll 此时只给「就地落地」，会白扔一手）→ 回退到不带 hold 的搜索，尽量给出真实方案。
        if (!got_target && !rr.change_hold)
        {
            auto fb = g_ai.run(map, node, nextStr.c_str(), maxDepth, g_think);
            if (fb.target != nullptr)
            {
                std::vector<char> path = g_ai.make_path(node, fb.target, map);
                result.assign(path.begin(), path.end());
                got_target = true;
                g_last_target = node_target_desc(fb.target);
            }
        }
    }
    else
    {
        auto rr = g_ai.run(map, node, nextStr.c_str(), maxDepth, g_think);
        if (rr.target != nullptr)
        {
            std::vector<char> path = g_ai.make_path(node, rr.target, map);
            result.assign(path.begin(), path.end());
            got_target = true;
            g_last_target = node_target_desc(rr.target);
        }
    }

    // 与 zzz 官方 io_dll 一致：即使没搜到落点也返回「就地落地(V)」，绝不返回空串。
    // 空串会被游戏当成 ERR → 该块直接硬降（表现为 bot 完全不动），而 V 至少语义明确。
    result.push_back('V');
    return result;
}

int main(int argc, char **argv)
{
    ege::mtsrand((unsigned int)std::time(nullptr));

    // Diagnostic: dump the baked rotation rule per kick mode.
    //   ops   = number of (piece, rotation) entries in the rule table
    //   kicks = total number of wall-kick offsets across those entries (0 => no kicks)
    //   rcw   = clockwise rotate template of the T piece (must stay non-null in mode 3:
    //           "no rotation system" still rotates, it just cannot kick)
    // Usage: zzztoj_worker.exe kickcount
    if (argc > 1 && std::strcmp(argv[1], "kickcount") == 0)
    {
        for (int mode = 0; mode <= 3; ++mode)
        {
            rule_asc::g_kick_mode = mode;
            auto ops = rule_asc::TetrisRule::get_opertion();
            size_t kicks = 0;
            void *rcw = nullptr;
            for (auto &kv : ops)
            {
                kicks += kv.second.wall_kick_clockwise.length;
                kicks += kv.second.wall_kick_counterclockwise.length;
                kicks += kv.second.wall_kick_opposite.length;
                if (kv.first.first == 'T' && kv.first.second == 1)
                    rcw = (void *)kv.second.rotate_clockwise;
            }
            std::printf("mode %d: ops=%d kicks=%d rotate_clockwise(T,r1)=%s\n",
                        mode, (int)ops.size(), (int)kicks, rcw != nullptr ? "set" : "NULL");
        }
        return 0;
    }

    // Diagnostic: dump the baked kick tables per (piece, rotation) so they can be compared
    // 1:1 with the game's get_kick_offsets_for(). Offsets are in zzz's frame (y upwards);
    // the game's tables are y-down, so the game's dy = -(dy here).
    // Usage: zzztoj_worker.exe kickdump <kick_mode 0..3>
    if (argc > 1 && std::strcmp(argv[1], "kickdump") == 0)
    {
        rule_asc::g_kick_mode = (argc > 2) ? std::atoi(argv[2]) : 0;
        auto ops = rule_asc::TetrisRule::get_opertion();
        std::printf("KICKS mode=%d\n", rule_asc::g_kick_mode);
        for (auto &kv : ops)
        {
            char const *kind[3] = {"cw", "ccw", "opp"};
            m_tetris::TetrisWallKickOpertion const *lst[3] =
            {
                &kv.second.wall_kick_clockwise,
                &kv.second.wall_kick_counterclockwise,
                &kv.second.wall_kick_opposite,
            };
            std::printf("K %c %d", kv.first.first, (int)kv.first.second);
            for (int i = 0; i < 3; ++i)
            {
                std::printf(" %s %u", kind[i], lst[i]->length);
                for (uint32_t k = 0; k < lst[i]->length && k < 24; ++k)
                    std::printf(" %d,%d", (int)lst[i]->data[k].x, (int)lst[i]->data[k].y);
            }
            std::printf("\n");
        }
        return 0;
    }

    if (argc > 1 && std::strcmp(argv[1], "selftest") == 0)
    {
        // 自检：40 行空板 + 底行留一个洞的“地面”，把 T 块放在板中央上方
        if (!prepare_ai())
        {
            std::printf("SELFTEST_FAIL prepare\n");
            return 1;
        }
        std::string line = "REQ";
        for (int d = 0; d < 40; ++d)
        {
            uint32_t mask = 0;
            if (d == 0)   // 底行：除 x=0 外全实心（留洞避免消行）
                for (int x = 1; x < GAME_W; ++x)
                    mask |= 1u << x;
            line += " " + std::to_string(mask);
        }
        line += " T";          // active = T
        line += " -";          // hold 空
        line += " 1";          // canHoldNow
        line += " IJLSTZO";    // next
        line += " 0 0 0";      // b2b combo upcome
        line += " 4 4 84 3 85 4 85 5 85";   // T（nub 朝上）在本游戏坐标下的四格
        std::vector<std::string> tok;
        {
            std::string cur;
            for (size_t k = 0; k < line.size(); ++k)
            {
                if (line[k] == ' ')
                {
                    if (!cur.empty())
                        tok.push_back(cur);
                    cur.clear();
                }
                else
                    cur.push_back(line[k]);
            }
            if (!cur.empty())
                tok.push_back(cur);
        }
        std::string path = handle_request(tok);
        std::printf("SELFTEST path='%s' (len=%d)\n", path.c_str(), (int)path.size());
        return path.empty() ? 2 : 0;
    }

    // 诊断用：打印 zzz 侧每种方块 4 个旋转态的格子（相对最小角的偏移，便于和游戏侧对照）
    // 用法：zzztoj_worker.exe nodes
    if (argc > 1 && std::strcmp(argv[1], "nodes") == 0)
    {
        if (!prepare_ai())
        {
            std::printf("NODES_FAIL prepare\n");
            return 1;
        }
        char const *pieces = "IJLOSTZ";
        for (int pi = 0; pi < 7; ++pi)
        {
            for (int r = 0; r < 4; ++r)
            {
                TetrisNode const *n = g_ai.get(TetrisBlockStatus(pieces[pi], 3, 20, (uint8_t)r));
                std::vector<std::pair<int, int>> cells;
                node_cells(n, cells);
                if (cells.empty())
                {
                    std::printf("%c r%d: <none>\n", pieces[pi], r);
                    continue;
                }
                int minX = INT_MAX, minY = INT_MAX;
                for (size_t k = 0; k < cells.size(); ++k)
                {
                    minX = std::min(minX, cells[k].first);
                    minY = std::min(minY, cells[k].second);
                }
                std::sort(cells.begin(), cells.end());
                std::string out;
                char buf[32];
                for (size_t k = 0; k < cells.size(); ++k)
                {
                    std::snprintf(buf, sizeof(buf), "%s%d,%d", k ? " " : "",
                                  cells[k].first - minX, cells[k].second - minY);
                    out += buf;
                }
                std::printf("%c r%d: %s\n", pieces[pi], r, out.c_str());
            }
        }
        return 0;
    }

    std::string line;
    while (std::getline(std::cin, line))
    {
        // 容忍调用方（如 PowerShell 管道/部分写入方式）带上的 UTF-8 BOM
        if (line.size() >= 3 && (unsigned char)line[0] == 0xEF && (unsigned char)line[1] == 0xBB
            && (unsigned char)line[2] == 0xBF)
            line.erase(0, 3);
        if (line.empty())
            continue;
        std::vector<std::string> tok;
        std::string cur;
        for (size_t k = 0; k < line.size(); ++k)
        {
            if (line[k] == ' ' || line[k] == '\t' || line[k] == '\r')
            {
                if (!cur.empty())
                    tok.push_back(cur);
                cur.clear();
            }
            else
                cur.push_back(line[k]);
        }
        if (!cur.empty())
            tok.push_back(cur);
        if (tok.empty())
            continue;

        if (tok[0] == "QUIT")
            break;
        if (tok[0] == "PING")
        {
            if (prepare_ai())
                std::printf("OK\n");
            else
                std::printf("ERR\n");
        }
        else if (tok[0] == "PARAM" && tok.size() >= 3)
        {
            // 按名字覆盖 AI 参数：PARAM <Param字段名> <值>（供 buff 的 ExtraBotChange 使用）
            std::printf(set_param_by_name(tok[1], std::atof(tok[2].c_str())) ? "OK\n" : "ERR\n");
        }
        else if (tok[0] == "CFG" && tok.size() >= 11)
        {
            // 可选第 13/14 个字段：BTB 加成系统（1=surge break / 2=累加奖励）与 PC 伤害。
            // 缺省时沿用当前值：只发 11 个字段的老调用方不会把它们重置。
            const int btb_system = (tok.size() >= 13) ? std::atoi(tok[12].c_str()) : g_last_btb_system;
            const int pc_damage = (tok.size() >= 14) ? std::atoi(tok[13].c_str()) : g_last_pc_damage;
            // 可选第 11 个字段：踢墙/旋转系统（0=ASC 1=SRS 2=ARS 3=NONE 无旋转系统）。
            // 变更会在下一次 REQ 的 prepare_ai() 里触发 context 重建（踢墙表在 prepare 时烘焙）。
            if (tok.size() >= 12)
                g_kick_mode = std::atoi(tok[11].c_str());
            // 可选追加的两个字段：游戏的 no_spin 模式与 no_spin4 的实心行惩罚量。
            // 缺省时沿用当前值（老调用方只发到 BTB/PC 字段也不会被重置）。
            //   no_spin==2 → 引擎把所有 Spin 降级为 Mini（与游戏类型/伤害表一致）
            //   no_spin==4 → 任何 Spin（含 Spin0）都是必死，用极大权重惩罚让 bot 绝不走 Spin
            g_no_spin = (tok.size() >= 15) ? std::atoi(tok[14].c_str()) : g_no_spin;
            g_no_spin4_rows = (tok.size() >= 16) ? std::atoi(tok[15].c_str()) : g_no_spin4_rows;
            apply_config(std::atoi(tok[1].c_str()), std::atoi(tok[2].c_str()), std::atoi(tok[3].c_str()),
                         tok[4] == "1", tok[5] == "1", tok[6] == "1", tok[7] == "1",
                         tok[8] == "1", tok[9] == "1", tok[10] == "1",
                         btb_system, pc_damage);
            std::printf("OK\n");
        }
        else if (tok[0] == "WEIGHTS")
        {
            // 诊断：打印当前生效的 Spin 相关配置与权重（单行，保持一命令一回复的协议）
            // 用法：先发 CFG 设置 no_spin 模式，再发 WEIGHTS。
            if (!prepare_ai())
            {
                std::printf("ERR\n");
            }
            else
            {
                search_amini::Search::Config *wsc = g_ai.search_config();
                ai_zzz::IO::Config *wac = g_ai.ai_config();
                ai_zzz::IO::Param const &wp = wac->param;
                std::printf("WEIGHTS no_spin=%d kick=%d amini=%d aspin=%d tspin=%d immobile=%d last_rotate=%d "
                            "force_mini=%d death_penalty=%.0f spin0_penalized=%d tspin_mini=%.3f tspin_1=%.3f tspin_2=%.3f tspin_3=%.3f "
                            "t2_slot=%.3f t3_slot=%.3f hold_t=%.3f hold_i=%.3f clear_1=%.3f clear_2=%.3f clear_3=%.3f clear_4=%.3f\n",
                            g_no_spin, g_kick_mode, (int)wsc->is_amini, (int)wsc->is_aspin, (int)wsc->is_tspin,
                            (int)wsc->allow_immobile_t, (int)wsc->last_rotate, (int)wac->spin_force_mini,
                            wac->spin_death_penalty, ai_zzz::spin0_penalty_count(),
                            wp.tspin_mini, wp.tspin_1, wp.tspin_2, wp.tspin_3, wp.t2_slot, wp.t3_slot,
                            wp.hold_t, wp.hold_i, wp.clear_1, wp.clear_2, wp.clear_3, wp.clear_4);
                // 180° 踢墙候选：按当前踢墙模式重新生成一份，核对 bot 的 180 表与游戏是否一致
                {
                    std::map<std::pair<char, uint8_t>, m_tetris::TetrisOpertion> rm = rule_asc::TetrisRule::get_opertion();
                    m_tetris::TetrisWallKickOpertion const &oT = rm[std::make_pair('T', (uint8_t)0)].wall_kick_opposite;
                    m_tetris::TetrisWallKickOpertion const &oI = rm[std::make_pair('I', (uint8_t)0)].wall_kick_opposite;
                    std::string ops;
                    for (uint32_t k = 0; k < oT.length && k < 8; ++k)
                    {
                        ops += " (";
                        ops += std::to_string((int)oT.data[k].x);
                        ops += ",";
                        ops += std::to_string((int)oT.data[k].y);
                        ops += ")";
                    }
                    std::printf("OPP180 T_len=%u I_len=%u T%s\n", oT.length, oI.length, ops.c_str());
                }
            }
        }
        else if (tok[0] == "REQ")
        {
            std::string path = handle_request(tok);
            if (path.empty())
                std::printf("ERR\n");
            else if (g_last_target.empty())
                std::printf("OK %s\n", path.c_str());
            else
                // 末尾附加决策落点（"<方块> <最小x> <最小y(zzz, y向上)> <旋转>"），游戏侧用于核对
                std::printf("OK %s %s\n", path.c_str(), g_last_target.c_str());
        }
        else
        {
            std::printf("ERR\n");
        }
        std::fflush(stdout);
    }
    return 0;
}
