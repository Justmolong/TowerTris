#include "rule_asc.h"
#include "rule_srs.h"

using namespace m_tetris;
using namespace m_tetris_rule_tools;

// ============================================================================================
// 本游戏（TowerTris）使用的 ASC 踢墙表
//   游戏内数据：Scripts/main_game/tetris_controller.gd :: kick_table["all"]（y 向下）
//     [0,0],[-1,0],[0,1],[-1,1],[0,2],[-1,2],[-2,0],[-2,1],[-2,2],[1,0],[1,1],
//     [0,-1],[-1,-1],[-2,-1],[1,2],[2,0],[0,-2],[-1,-2],[-2,-2],[2,1],[2,2]
//   下表为其后 20 组（首项 (0,0) 由引擎隐式先试），且 dy 取反成 zzz 的 y 向上坐标。
// ============================================================================================
namespace rule_asc
{
    int g_kick_mode = 0;   // 0=ASC（默认） 1=SRS 2=ARS

    static TetrisWallKickOpertion const &asc_cw()
    {
        static TetrisWallKickOpertion const op =
        {
            20,
            {
                {-1, 0}, {0, -1}, {-1, -1}, {0, -2}, {-1, -2},
                {-2, 0}, {-2, -1}, {-2, -2}, {1, 0}, {1, -1},
                {0, 1}, {-1, 1}, {-2, 1}, {1, -2}, {2, 0},
                {0, 2}, {-1, 2}, {-2, 2}, {2, -1}, {2, -2},
            }
        };
        return op;
    }

    // 逆时针：与游戏一致，仅 X 取反（顺序不变）
    static TetrisWallKickOpertion const &asc_ccw()
    {
        static TetrisWallKickOpertion const op =
        {
            20,
            {
                {1, 0}, {0, -1}, {1, -1}, {0, -2}, {1, -2},
                {2, 0}, {2, -1}, {2, -2}, {-1, 0}, {-1, -1},
                {0, 1}, {1, 1}, {2, 1}, {-1, -2}, {-2, 0},
                {0, 2}, {1, 2}, {2, 2}, {-2, -1}, {-2, -2},
            }
        };
        return op;
    }

    // 180：游戏复用同一张表且不取反
    static TetrisWallKickOpertion const &asc_opposite()
    {
        return asc_cw();
    }

    // ----------------------------------------------------------------------------------------
    // ARS（Arika Rotation System，TGM1/TGM2 基准，与游戏侧 get_kick_offsets_for 的 ARS 分支一致）
    //   只测三个位置：默认位置 → 右 1 → 左 1（优先向右）。该表 y 分量恒为 0，故 zzz 的 y 向上
    //   坐标无需取反；CW 与 CCW 用同一张表（ARS 的踢墙顺序不随旋转方向变化）。
    // ----------------------------------------------------------------------------------------
    static TetrisWallKickOpertion const &ars_kick()
    {
        static TetrisWallKickOpertion const op =
        {
            2,
            {
                {1, 0}, {-1, 0},
            }
        };
        return op;
    }

    // 无踢墙：只允许原地旋转（基础版 ARS 的 I、以及 ARS 的 180°）
    static TetrisWallKickOpertion const &no_kick()
    {
        static TetrisWallKickOpertion const op = {0, {}};
        return op;
    }

    // 每个旋转态各自的「转 180°」目标态（state -> (state + 2) % 4）
    typedef bool (*RotateFunc)(TetrisNode &, TetrisContext const *);
    static RotateFunc opposite_template(uint8_t r)
    {
        switch ((r + 2) % 4)
        {
        case 0: return rotate_template<0>;
        case 1: return rotate_template<1>;
        case 2: return rotate_template<2>;
        default: return rotate_template<3>;
        }
    }

    bool TetrisRule::init(int w, int h)
    {
        return w == 10 && h == 40;
    }

    std::map<char, TetrisBlockStatus(*)(TetrisContext const *)> TetrisRule::get_generate()
    {
        // 出生点与 SRS 一致（x=3, y=21, r=0）；实际查询用外部传入的当前方块状态，此表用于后续块
        return rule_srs::TetrisRule::get_generate();
    }

    std::map<std::pair<char, uint8_t>, TetrisOpertion> TetrisRule::get_opertion()
    {
        // 先取 SRS 的节点几何 + 转向模板（与本游戏旋转状态一致），再按 g_kick_mode 替换踢墙表
        std::map<std::pair<char, uint8_t>, TetrisOpertion> info = rule_srs::TetrisRule::get_opertion();
        for (auto &kv : info)
        {
            if (kv.first.first == 'O')
            {
                // O 旋转是几何空操作，且本游戏 O 不判 spin：保持 SRS 的空表/空转向
                continue;
            }
            if (g_kick_mode == 2)
            {
                // ARS：JLSTZ 三位置；基础版 ARS 中 I 没有踢墙；180° 无踢墙（只能原地转）
                bool is_i = (kv.first.first == 'I');
                kv.second.wall_kick_clockwise = is_i ? no_kick() : ars_kick();
                kv.second.wall_kick_counterclockwise = is_i ? no_kick() : ars_kick();
                kv.second.rotate_opposite = opposite_template(kv.first.second);
                kv.second.wall_kick_opposite = no_kick();
            }
            else if (g_kick_mode == 1)
            {
                // 标准 SRS：CW/CCW 保留 rule_srs 的表；180° 与游戏 SRS 分支一致沿用 ASC 表
                kv.second.rotate_opposite = opposite_template(kv.first.second);
                kv.second.wall_kick_opposite = asc_opposite();
            }
            else
            {
                kv.second.wall_kick_clockwise = asc_cw();
                kv.second.wall_kick_counterclockwise = asc_ccw();
                // 本游戏支持 180 度旋转（SwapSpin 键），踢墙同样用 ASC 表
                kv.second.rotate_opposite = opposite_template(kv.first.second);
                kv.second.wall_kick_opposite = asc_opposite();
            }
        }
        return info;
    }
}
