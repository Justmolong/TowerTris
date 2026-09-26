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
//                                                   -> OK
//   REQ <40 行位掩码(底行在前,十进制)> <active> <hold|-> <canHoldNow> <next串> <b2b> <combo>
//       <预告垃圾合计> <格数> <x1> <y1> ...               -> OK <path> | ERR
//   QUIT                                            -> 退出
//   其中 <active>/<hold>/<next> 用字符 ITLJZSO；x/y 为本游戏坐标（y 向下、底行 = 89），
//   由本进程换算到 zzz 坐标（y 向上、底行 = 0）后**按格子集合匹配节点**，因此不依赖旋转编号约定。
//   path 字符集与 io_dll 一致：l/r/d 一格、L/R 到头、D 落到底、z 逆时针、c 顺时针，
//   末尾 'V' = 落地(硬降)，开头 'v' = 建议先 Hold。
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

// 由「本游戏的方块格子」找到 zzz 的节点（遍历 4 个旋转态按格子集合精确匹配）
static TetrisNode const *find_node(char piece, std::vector<std::pair<int, int>> const &zzz_cells, std::string *dbg)
{
    int tgtMinX = INT_MAX, tgtMinY = INT_MAX;
    for (size_t i = 0; i < zzz_cells.size(); ++i)
    {
        tgtMinX = std::min(tgtMinX, zzz_cells[i].first);
        tgtMinY = std::min(tgtMinY, zzz_cells[i].second);
    }
    for (uint8_t r = 0; r < 4; ++r)
    {
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
static void apply_config(int level, int gcap, int mult, bool lockout, bool can_hold,
                         bool allow180, bool amini, bool aspin, bool tspin, bool immobile_t)
{
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

    ai_zzz::IO::Config *ac = g_ai.ai_config();
    ac->is_margin = false;
    ac->season_2 = immobile_t;   // 与 io_dll 一致：season_2 对应「不可移动即 T-Spin」档
    ac->lockout = lockout;
    ac->multiplier = mult;
    ac->garbage_cap = gcap;

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

    g_level = level;
    g_gcap = gcap;
    g_mult = mult;
    g_lockout = lockout;
    g_can_hold_global = can_hold;
    if (g_last_level_applied != level)
    {
        g_last_level_applied = level;
        g_ai.update();
    }
}

static bool prepare_ai()
{
    if (g_prepared)
        return true;
    if (!g_ai.prepare(GAME_W, 40))
        return false;
    g_ai.memory_limit(512ull << 20);
    apply_config(8, 8, 1, false, true, true, true, false, true, true);
    g_prepared = true;
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

    char active = tok[i++][0];
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
    if (i + 3 <= tok.size())
    {
        last_spin_type = std::atoi(tok[i].c_str());
        last_clear_count = std::atoi(tok[i + 1].c_str());
        repeat_penalty = std::atof(tok[i + 2].c_str());
    }

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
    TetrisNode const *node = find_node(active, zzzCells, &dbg);
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
    char holdChar = holdTok.empty() ? ' ' : holdTok[0];

    if (g_can_hold_global)
    {
        auto rr = g_ai.run_hold(map, node, holdChar, canHoldNow, nextStr.c_str(), maxDepth, g_think);
        if (rr.target != nullptr)
        {
            TetrisNode const *from = rr.change_hold ? g_ai.context()->generate(rr.target->status.t) : node;
            std::vector<char> path = g_ai.make_path(from, rr.target, map);
            result.assign(path.begin(), path.end());
        }
        if (rr.change_hold)
            result.insert(result.begin(), 'v');
    }
    else
    {
        auto rr = g_ai.run(map, node, nextStr.c_str(), maxDepth, g_think);
        if (rr.target != nullptr)
        {
            std::vector<char> path = g_ai.make_path(node, rr.target, map);
            result.assign(path.begin(), path.end());
        }
    }

    if (result.empty())
        return result;
    result.push_back('V');   // 末尾 = 落地
    return result;
}

int main(int argc, char **argv)
{
    ege::mtsrand((unsigned int)std::time(nullptr));

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
            apply_config(std::atoi(tok[1].c_str()), std::atoi(tok[2].c_str()), std::atoi(tok[3].c_str()),
                         tok[4] == "1", tok[5] == "1", tok[6] == "1", tok[7] == "1",
                         tok[8] == "1", tok[9] == "1", tok[10] == "1");
            std::printf("OK\n");
        }
        else if (tok[0] == "REQ")
        {
            std::string path = handle_request(tok);
            if (path.empty())
                std::printf("ERR\n");
            else
                std::printf("OK %s\n", path.c_str());
        }
        else
        {
            std::printf("ERR\n");
        }
        std::fflush(stdout);
    }
    return 0;
}
