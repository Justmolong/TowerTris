#pragma once

#include "tetris_core.h"
#include <map>

// 本游戏的踢墙规则（ASC 单表）：
//   节点几何/转向模板沿用 rule_srs（已验证与本游戏 3x3/4x4 矩阵旋转状态一致），
//   只把踢墙表整体换成游戏内 kick_table["all"] 的 21 组 ASC 偏移：
//     CW  = 全表原样（y 取反为 zzz 的 y 向上），CCW = 全表 X 取反，180 = 全表原样。
//   这与游戏 _apply_rotation_with_kick 的「单表 + 逆时针 X 镜像 + 180 复用同表」等价。
namespace rule_asc
{
    struct TetrisRule
    {
        static bool init(int w, int h);
        static std::map<std::pair<char, uint8_t>, m_tetris::TetrisOpertion> get_opertion();
        static std::map<char, m_tetris::TetrisBlockStatus(*)(m_tetris::TetrisContext const *)> get_generate();
    };
}
