
#pragma once

#include "tetris_core.h"
#include <vector>
#include <cstddef>

namespace search_amini
{
    class Search
    {
    public:
        enum ASpinType
        {
            None,
            TSpin,
            AllSpin,
            TSpinMini,
            ASpinMini,
        };
        struct Config
        {
            bool allow_rotate_move = false;
            bool allow_180 = true;
            bool allow_d = false;
            bool allow_D = true;
            bool allow_LR = true;
            bool is_20g = false;
            bool last_rotate = false;
            bool is_amini = true;
            bool is_aspin = false;
            bool is_tspin = true;
            bool allow_immobile_t = true;
            // TowerTris：游戏 no_spin==2（无天赋II：所有 Spin 一律降级为 Mini）时置 true。
            // 打开后，本 search 判定出的全旋（AllSpin / ASpinMini）一律标成 ASpinMini，
            // 与游戏上报的类型（"Mini ..."）以及 mini 伤害表口径一致。
            bool spin_force_mini = false;
            // TowerTris：本游戏（TetrisClearLine._detect_spin_type）的 T 块口径是
            //   · 卡住（四向不可移动）→ "T-Spin"（全）
            //   · 没卡住、但角型成立（下两角 + 上至少一角，等价引擎的 is_ready）→ **"Mini T-Spin"**
            // zzz 原生 / TETR.IO 口径则是「没卡住就不算 Spin」，会在下面把
            // is_ready / is_mini_ready / is_last_rotate 全部清掉；照原生走的话引擎完全看不到
            // 这个 Mini T-Spin0，Allspin_2 下就把它当成普通放置，于是「连续两次 Spin0」
            // 的重复惩罚在预测里消失，实战却被游戏罚 20 行实心垃圾。
            // 打开本开关后：没卡住但角型成立 → 保留 is_last_rotate，并标记为 Mini T-Spin。
            bool mini_t_when_not_immobile = false;
            // TowerTris：快速模拟的「直接放置」路径（tetris_controller._fast_sim_try_direct_place）
            // 会把方块瞬移到落点后**补记一次旋转事件**（见该函数注释：spin 判定看的是最后一次旋转的位置，
            // 直接放置等价于在落点处完成最后一次旋转）。也就是说该模式下游戏对**每个落点**都满足
            // `last_rotation_occurred`，Spin 判定退化为纯几何判定（卡住 / T 的角型）。
            // 引擎原来是按自己搜索序列的最后动作判 is_last_rotate —— 计划里最后一步若不是旋转，
            // 引擎就当普通放置，游戏却判成 Spin0 → 消行/Spin 历史错位 → 「莫名触发」重复惩罚。
            // 该开关为 true 时，把每个落点都按「最后动作是旋转」处理，与直接放置一致。
            bool direct_place_rotate = false;
        };
        struct TetrisNodeWithASpinType
        {
            TetrisNodeWithASpinType()
            {
                std::memset(this, 0, sizeof(*this));
            }
            TetrisNodeWithASpinType(m_tetris::TetrisNode const *_node) : node(_node), last(), type(None), flags()
            {
            }
            m_tetris::TetrisNode const *node;
            m_tetris::TetrisNode const *last;
            ASpinType type;
            union
            {
                struct
                {
                    bool is_check;
                    bool is_last_rotate;
                    bool is_ready;
                    bool is_mini_ready;
                };
                uint32_t flags;
            };
            operator m_tetris::TetrisNode const *() const
            {
                return node;
            }
            m_tetris::TetrisNode const *operator->() const
            {
                return node;
            }
            bool operator==(TetrisNodeWithASpinType const &other)
            {
                return node == other.node && last == other.last && type == other.type && flags == other.flags;
            }
            bool operator==(std::nullptr_t)
            {
                return node == nullptr;
            }
            bool operator!=(std::nullptr_t)
            {
                return node != nullptr;
            }
        };
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::vector<char> make_path(m_tetris::TetrisNode const *node, TetrisNodeWithASpinType const &land_point, m_tetris::TetrisMap const &map);
        std::vector<TetrisNodeWithASpinType> const *search(m_tetris::TetrisMap const &map, m_tetris::TetrisNode const *node, size_t depth);

    private:
        std::vector<char> make_path_20g(m_tetris::TetrisNode const *node, TetrisNodeWithASpinType const &land_point, m_tetris::TetrisMap const &map);
        std::vector<TetrisNodeWithASpinType> const *search_t(m_tetris::TetrisMap const &map, m_tetris::TetrisNode const *node, size_t depth);
        bool check_ready(m_tetris::TetrisMap const &map, m_tetris::TetrisNode const *node);
        bool check_mini_ready(TetrisNodeWithASpinType const& node, m_tetris::TetrisMap const& map);
        bool check_immobile(TetrisNodeWithASpinType const &node, m_tetris::TetrisMapSnap const &snap);
        std::vector<TetrisNodeWithASpinType> land_point_cache_;
        std::vector<m_tetris::TetrisNode const *> node_incomplete_;
        std::vector<m_tetris::TetrisNode const *> node_search_;
        m_tetris::TetrisNodeMark node_mark_;
        m_tetris::TetrisNodeMarkFiltered node_mark_filtered_;
        uint32_t *block_data_;
        uint32_t block_data_buffer_[52];
        int x_diff_, y_diff_;
        Config const *config_;
        m_tetris::TetrisContext const *context_;
    };
}
