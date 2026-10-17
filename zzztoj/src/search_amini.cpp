#include "search_amini.h"
#include "integer_utils.h"

using namespace m_tetris;

namespace search_amini
{
    void Search::init(TetrisContext const *context, Config const *config)
    {
        context_ = context;
        config_ = config;
        node_mark_.init(context->node_max());
        node_mark_filtered_.init(context->node_max());
        block_data_ = block_data_buffer_ + 10;
        std::memset(block_data_buffer_, 0, sizeof block_data_buffer_);
        TetrisNode const *node = context->generate('T');
        if (node != nullptr)
        {
            int bottom = node->row, top = node->row + node->height, left = node->col, right = node->col + node->width;
            TetrisNode const *rotate = node->rotate_clockwise != nullptr ? node->rotate_clockwise : node->rotate_counterclockwise;
            if (rotate != nullptr)
            {
                bottom = std::min<int>(bottom, rotate->row);
                top = std::max<int>(top, rotate->row + rotate->height);
                left = std::min<int>(left, rotate->col);
                right = std::max<int>(right, rotate->col + rotate->width);
                x_diff_ = (right + left) / 2 - node->status.x;
                y_diff_ = (top + bottom) / 2 - node->status.y;
                for (int x = 1; x < context->width() - 1; ++x)
                {
                    block_data_[x - x_diff_] = (1 << (x - 1)) | (1 << (x + 1));
                }
                block_data_[0 - x_diff_] = (1 << 1);
                block_data_[context->width() - 1 - x_diff_] = (1 << (context->width() - 2));
            }
        }
    }

    std::vector<char> Search::make_path(TetrisNode const *node, TetrisNodeWithASpinType const &land_point, TetrisMap const &map)
    {
        // if (land_point.type != None)
        //{
        //     printf("T-SPIN %d\n", land_point.type);
        // }
        if (config_->is_20g)
        {
            return make_path_20g(node, land_point, map);
        }
        if (land_point.type == None && node->index_filtered == land_point->index_filtered)
        {
            return std::vector<char>();
        }
        bool allow_180 = config_->allow_180;
        bool allow_LR = config_->allow_LR;
        bool allow_D = config_->allow_D;
        const size_t index = land_point.type == None || land_point.last == nullptr ? land_point->index_filtered : land_point.last->index_filtered;
        auto build_path = [&land_point, &map, allow_180, this](TetrisNode const *node, decltype(node_mark_) &node_mark) -> std::vector<char>
        {
            size_t node_index = node->index_filtered;
            std::vector<char> path;
            while (true)
            {
                auto result = node_mark.get(node);
                node = result.first;
                if (node == nullptr)
                {
                    break;
                }
                path.push_back(result.second);
            }
            std::reverse(path.begin(), path.end());
            if (node_index != land_point->index_filtered)
            {
                TetrisNode const *last = land_point.last;
                node = land_point.node;
                if (allow_180)
                {
                    // x
                    for (TetrisNode const *wall_kick_node : last->wall_kick_opposite)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                if (wall_kick_node == node)
                                {
                                    path.push_back('x');
                                    return path;
                                }
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                // z
                for (TetrisNode const *wall_kick_node : last->wall_kick_counterclockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            if (wall_kick_node == node)
                            {
                                path.push_back('z');
                                return path;
                            }
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // c
                for (TetrisNode const *wall_kick_node : last->wall_kick_clockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            if (wall_kick_node == node)
                            {
                                path.push_back('c');
                                return path;
                            }
                        }
                    }
                    else
                    {
                        break;
                    }
                }
            }
            return path;
        };
        bool disable_d = land_point.type == None && node->land_point != nullptr && node->low >= map.roof && land_point->open(map);
        while (true)
        {
            node_mark_.clear();
            node_search_.clear();
            node_search_.push_back(node);
            node_mark_.set(node, nullptr, '\0');
            if (node->index_filtered == index || (land_point.type != None && node->index_filtered == land_point->index_filtered && config_->last_rotate))
            {
                return build_path(node, node_mark_);
            }
            size_t cache_index = 0;
            do
            {
                for (size_t max_index = node_search_.size(); cache_index < max_index; ++cache_index)
                {
                    TetrisNode const *node = node_search_[cache_index];
                    // l
                    if (node->move_left && node_mark_.set(node->move_left, node, 'l') && node->move_left->check(map))
                    {
                        if (node->move_left->index_filtered == index)
                        {
                            return build_path(node->move_left, node_mark_);
                        }
                        else
                        {
                            node_search_.push_back(node->move_left);
                        }
                        if (config_->allow_rotate_move)
                        {
                            TetrisNode const *node_left = node->move_left;
                            // X
                            if (allow_180 && node_left->rotate_opposite && node_mark_.set(node_left->rotate_opposite, node_left, 'X') && node_left->rotate_opposite->check(map))
                            {
                                if (node_left->rotate_opposite->index_filtered == index)
                                {
                                    return build_path(node_left->rotate_opposite, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_left->rotate_opposite);
                                }
                            }
                            // Z
                            if (node_left->rotate_counterclockwise && node_mark_.set(node_left->rotate_counterclockwise, node_left, 'Z') && node_left->rotate_counterclockwise->check(map))
                            {
                                if (node_left->rotate_counterclockwise->index_filtered == index)
                                {
                                    return build_path(node_left->rotate_counterclockwise, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_left->rotate_counterclockwise);
                                }
                            }
                            // C
                            if (node_left->rotate_clockwise && node_mark_.set(node_left->rotate_clockwise, node_left, 'C') && node_left->rotate_clockwise->check(map))
                            {
                                if (node_left->rotate_clockwise->index_filtered == index)
                                {
                                    return build_path(node_left->rotate_clockwise, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_left->rotate_clockwise);
                                }
                            }
                        }
                    }
                    // r
                    if (node->move_right && node_mark_.set(node->move_right, node, 'r') && node->move_right->check(map))
                    {
                        if (node->move_right->index_filtered == index)
                        {
                            return build_path(node->move_right, node_mark_);
                        }
                        else
                        {
                            node_search_.push_back(node->move_right);
                        }
                        if (config_->allow_rotate_move)
                        {
                            TetrisNode const *node_right = node->move_right;
                            // X
                            if (allow_180 && node_right->rotate_opposite && node_mark_.set(node_right->rotate_opposite, node_right, 'X') && node_right->rotate_opposite->check(map))
                            {
                                if (node_right->rotate_opposite->index_filtered == index)
                                {
                                    return build_path(node_right->rotate_opposite, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_right->rotate_opposite);
                                }
                            }
                            // Z
                            if (node_right->rotate_counterclockwise && node_mark_.set(node_right->rotate_counterclockwise, node_right, 'Z') && node_right->rotate_counterclockwise->check(map))
                            {
                                if (node_right->rotate_counterclockwise->index_filtered == index)
                                {
                                    return build_path(node_right->rotate_counterclockwise, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_right->rotate_counterclockwise);
                                }
                            }
                            // C
                            if (node_right->rotate_clockwise && node_mark_.set(node_right->rotate_clockwise, node_right, 'C') && node_right->rotate_clockwise->check(map))
                            {
                                if (node_right->rotate_clockwise->index_filtered == index)
                                {
                                    return build_path(node_right->rotate_clockwise, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node_right->rotate_clockwise);
                                }
                            }
                        }
                    }
                    // L
                    if (allow_LR && node->move_left && node->move_left->check(map))
                    {
                        TetrisNode const *node_L = node->move_left;
                        while (node_L->move_left && node_L->move_left->check(map))
                        {
                            node_L = node_L->move_left;
                        }
                        if (node_mark_.set(node_L, node, 'L'))
                        {
                            if (node_L->index_filtered == index)
                            {
                                return build_path(node_L, node_mark_);
                            }
                            else
                            {
                                node_search_.push_back(node_L);
                            }
                        }
                    }
                    // R
                    if (allow_LR && node->move_right && node->move_right->check(map))
                    {
                        TetrisNode const *node_R = node->move_right;
                        while (node_R->move_right && node_R->move_right->check(map))
                        {
                            node_R = node_R->move_right;
                        }
                        if (node_mark_.set(node_R, node, 'R'))
                        {
                            if (node_R->index_filtered == index)
                            {
                                return build_path(node_R, node_mark_);
                            }
                            else
                            {
                                node_search_.push_back(node_R);
                            }
                        }
                    }
                    if (disable_d)
                    {
                        // D
                        TetrisNode const *node_D = node->drop(map);
                        if (node_mark_.set(node_D, node, 'D') && node_D->index_filtered == index)
                        {
                            return build_path(node_D, node_mark_);
                        }
                    }
                    // x
                    if (allow_180)
                    {
                        for (TetrisNode const *wall_kick_node : node->wall_kick_opposite)
                        {
                            if (wall_kick_node)
                            {
                                if (wall_kick_node->check(map))
                                {
                                    if (node_mark_.set(wall_kick_node, node, 'x'))
                                    {
                                        if (wall_kick_node->index_filtered == index)
                                        {
                                            return build_path(wall_kick_node, node_mark_);
                                        }
                                        else
                                        {
                                            node_search_.push_back(wall_kick_node);
                                        }
                                    }
                                    break;
                                }
                            }
                            else
                            {
                                break;
                            }
                        }
                    }
                    // z
                    for (TetrisNode const *wall_kick_node : node->wall_kick_counterclockwise)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                if (node_mark_.set(wall_kick_node, node, 'z'))
                                {
                                    if (wall_kick_node->index_filtered == index)
                                    {
                                        return build_path(wall_kick_node, node_mark_);
                                    }
                                    else
                                    {
                                        node_search_.push_back(wall_kick_node);
                                    }
                                }
                                break;
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                    // c
                    for (TetrisNode const *wall_kick_node : node->wall_kick_clockwise)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                if (node_mark_.set(wall_kick_node, node, 'c'))
                                {
                                    if (wall_kick_node->index_filtered == index)
                                    {
                                        return build_path(wall_kick_node, node_mark_);
                                    }
                                    else
                                    {
                                        node_search_.push_back(wall_kick_node);
                                    }
                                }
                                break;
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                    if (!disable_d)
                    {
                        if (config_->allow_d)
                        {
                            // d
                            if (node->move_down && node_mark_.set(node->move_down, node, 'd') && node->move_down->check(map))
                            {
                                if (node->move_down->index_filtered == index)
                                {
                                    return build_path(node->move_down, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(node->move_down);
                                }
                                // D
                                if (allow_D)
                                {
                                    TetrisNode const *node_D = node->drop(map);
                                    if (node_mark_.set(node_D, node, 'D'))
                                    {
                                        if (node_D->index_filtered == index)
                                        {
                                            return build_path(node_D, node_mark_);
                                        }
                                        else
                                        {
                                            node_search_.push_back(node_D);
                                        }
                                    }
                                }
                            }
                        }
                        else
                        {
                            // D
                            if (allow_D)
                            {
                                TetrisNode const *node_D = node->drop(map);
                                if (node_mark_.set(node_D, node, 'D'))
                                {
                                    if (node_D->index_filtered == index)
                                    {
                                        return build_path(node_D, node_mark_);
                                    }
                                    else
                                    {
                                        node_search_.push_back(node_D);
                                    }
                                }
                            }
                        }
                    }
                }
            } while (node_search_.size() > cache_index);
            if (disable_d)
            {
                disable_d = false;
            }
            else
            {
                break;
            }
        }
        return std::vector<char>();
    }

    std::vector<Search::TetrisNodeWithASpinType> const *Search::search(TetrisMap const &map, TetrisNode const *node, size_t depth)
    {
        land_point_cache_.clear();
        if (!node->check(map))
        {
            return &land_point_cache_;
        }
        bool allow_180 = config_->allow_180;
        bool is_20g = config_->is_20g;
        bool allow_LR = config_->allow_LR;
        bool allow_d = config_->allow_d;
        TetrisMapSnap snap;
        node->build_snap(map, context_, snap);
        node_mark_.clear();
        node_mark_filtered_.clear();
        node_search_.clear();
        if (is_20g)
        {
            node = node->drop(map);
        }
        else
        {
            while (node->low >= map.roof && node->move_down && node->move_down->check(snap))
            {
                node_mark_.set(node->move_down, node, 'd');
                node = node->move_down;
            }
        }
        node_search_.push_back(node);
        if (node->status.t == 'T' && config_->is_tspin)
        {
            return search_t(map, node, depth);
        }
        size_t cache_index = 0;
        do
        {
            for (size_t max_index = node_search_.size(); cache_index < max_index; ++cache_index)
            {
                node = node_search_[cache_index];
                if (!node->move_down || !node->move_down->check(map))
                {
                    if (node_mark_filtered_.mark(node))
                    {
                        TetrisNodeWithASpinType node_ex(node);
                        // 与游戏 TetrisClearLine._detect_spin_type 严格对齐（非 T 分支）：
                        //   · `if not last_rotation_occurred: return ""`
                        //     → 必须有「最后一次动作是旋转」的记录。直接平移/硬降到位、四向卡住
                        //       但没转过的情况，游戏**不判 Spin**；此前这里只查 check_immobile，
                        //       会把大量「卡住但没转」的落点误标成 AllSpin/ASpinMini，
                        //       于是 bot 的消行记录与游戏不一致 → 之后的行数重复判定错位
                        //       （表现就是"莫名触发惩罚"）。node_mark_ 里 ' ' = 平移/下落，其它 = 旋转。
                        //   · `if last_rotation_piece_type == "O": return ""`
                        //     → O 块旋转是几何空操作，游戏明确排除（不产生 O-Spin）。
                        if ((config_->is_amini || config_->is_aspin) && node->status.t != 'O')
                        {
                            if ((config_->direct_place_rotate || node_mark_.get(node).second != ' ')
                                && check_immobile(node, snap))
                            {
                                node_ex.type = (config_->spin_force_mini || config_->is_amini) ? ASpinMini : AllSpin;
                            }
                        }
                        land_point_cache_.push_back(node_ex);
                    }
                }
                // l
                if (node->move_left && node_mark_.mark(node->move_left) && node->move_left->check(map))
                {
                    node_search_.push_back(node->move_left);
                }
                // r
                if (node->move_right && node_mark_.mark(node->move_right) && node->move_right->check(map))
                {
                    node_search_.push_back(node->move_right);
                }
                // d
                if (allow_d)
                {
                    if (node->move_down && node_mark_.mark(node->move_down) && node->move_down->check(map))
                    {
                        node_search_.push_back(node->move_down);
                    }
                }
                else
                {
                    const TetrisNode *node_down = node->drop(map);
                    if (node_mark_.mark(node_down))
                    {
                        node_search_.push_back(node_down);
                    }
                }
                if (allow_180)
                {
                    // x
                    for (TetrisNode const *wall_kick_node : node->wall_kick_opposite)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                if (node_mark_.mark(wall_kick_node))
                                {
                                    node_search_.push_back(wall_kick_node);
                                }
                                break;
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                // z
                for (TetrisNode const *wall_kick_node : node->wall_kick_counterclockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            if (node_mark_.mark(wall_kick_node))
                            {
                                node_search_.push_back(wall_kick_node);
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // c
                for (TetrisNode const *wall_kick_node : node->wall_kick_clockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            if (node_mark_.mark(wall_kick_node))
                            {
                                node_search_.push_back(wall_kick_node);
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
            }
            } while (node_search_.size() > cache_index);
        return &land_point_cache_;
    }

    std::vector<char> Search::make_path_20g(TetrisNode const *node, TetrisNodeWithASpinType const &land_point, TetrisMap const &map)
    {
        node = node->drop(map);
        if (land_point.type == None && node->index_filtered == land_point->index_filtered)
        {
            return std::vector<char>();
        }
        bool allow_180 = config_->allow_180;
        bool allow_LR = config_->allow_LR;
        bool allow_D = config_->allow_D;
        const size_t index = land_point.type == None || land_point.last == nullptr ? land_point->index_filtered : land_point.last->index_filtered;
        auto build_path = [&land_point, &map, allow_180, this](TetrisNode const *node, decltype(node_mark_) &node_mark) -> std::vector<char>
        {
            size_t node_index = node->index_filtered;
            std::vector<char> path;
            while (true)
            {
                auto result = node_mark.get(node);
                node = result.first;
                if (node == nullptr)
                {
                    break;
                }
                path.push_back(result.second);
            }
            std::reverse(path.begin(), path.end());
            if (node_index != land_point->index_filtered)
            {
                TetrisNode const *last = land_point.last;
                node = land_point.node;
                if (allow_180)
                {
                    // x
                    for (TetrisNode const *wall_kick_node : last->wall_kick_opposite)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                wall_kick_node = wall_kick_node->drop(map);
                                if (wall_kick_node == node)
                                {
                                    path.push_back('x');
                                    return path;
                                }
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                // z
                for (TetrisNode const *wall_kick_node : last->wall_kick_counterclockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            wall_kick_node = wall_kick_node->drop(map);
                            if (wall_kick_node == node)
                            {
                                path.push_back('z');
                                return path;
                            }
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // c
                for (TetrisNode const *wall_kick_node : last->wall_kick_clockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            wall_kick_node = wall_kick_node->drop(map);
                            if (wall_kick_node == node)
                            {
                                path.push_back('c');
                                return path;
                            }
                        }
                    }
                    else
                    {
                        break;
                    }
                }
            }
            return path;
        };
        node_mark_.clear();
        node_search_.clear();
        node_search_.push_back(node);
        node_mark_.set(node, nullptr, '\0');
        if (node->index_filtered == index || (land_point.type != None && node->index_filtered == land_point->index_filtered && config_->last_rotate))
        {
            return build_path(node, node_mark_);
        }
        size_t cache_index = 0;
        do
        {
            for (size_t max_index = node_search_.size(); cache_index < max_index; ++cache_index)
            {
                TetrisNode const *node = node_search_[cache_index];
                TetrisNode const *node_test;
                assert(node == node->drop(map));
                // x
                if (allow_180)
                {
                    for (TetrisNode const *wall_kick_node : node->wall_kick_opposite)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(map))
                            {
                                wall_kick_node = wall_kick_node->drop(map);
                                if (node_mark_.set(wall_kick_node, node, 'x'))
                                {
                                    if (wall_kick_node->index_filtered == index)
                                    {
                                        return build_path(wall_kick_node, node_mark_);
                                    }
                                    else
                                    {
                                        node_search_.push_back(wall_kick_node);
                                    }
                                }
                                break;
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                // z
                for (TetrisNode const *wall_kick_node : node->wall_kick_counterclockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            wall_kick_node = wall_kick_node->drop(map);
                            if (node_mark_.set(wall_kick_node, node, 'z'))
                            {
                                if (wall_kick_node->index_filtered == index)
                                {
                                    return build_path(wall_kick_node, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(wall_kick_node);
                                }
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // c
                for (TetrisNode const *wall_kick_node : node->wall_kick_clockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(map))
                        {
                            wall_kick_node = wall_kick_node->drop(map);
                            if (node_mark_.set(wall_kick_node, node, 'c'))
                            {
                                if (wall_kick_node->index_filtered == index)
                                {
                                    return build_path(wall_kick_node, node_mark_);
                                }
                                else
                                {
                                    node_search_.push_back(wall_kick_node);
                                }
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // l
                if ((node_test = node->move_left) && node_test->check(map) && (node_test = node_test->drop(map), node_mark_.set(node_test, node, 'l')))
                {
                    if (node_test->index_filtered == index)
                    {
                        return build_path(node_test, node_mark_);
                    }
                    else
                    {
                        node_search_.push_back(node_test);
                    }
                }
                // r
                if ((node_test = node->move_right) && node_test->check(map) && (node_test = node_test->drop(map), node_mark_.set(node_test, node, 'r')))
                {
                    TetrisNode const *move_right = node->move_right->drop(map);
                    if (move_right->index_filtered == index)
                    {
                        return build_path(move_right, node_mark_);
                    }
                    else
                    {
                        node_search_.push_back(move_right);
                    }
                }
                // L
                if (allow_LR && node->move_left && node->move_left->check(map))
                {
                    node_test = node->move_left->drop(map);
                    while (node_test->move_left && node_test->move_left->check(map))
                    {
                        node_test = node_test->move_left->drop(map);
                    }
                    if (node_mark_.set(node_test, node, 'L'))
                    {
                        if (node_test->index_filtered == index)
                        {
                            return build_path(node_test, node_mark_);
                        }
                        else
                        {
                            node_search_.push_back(node_test);
                        }
                    }
                }
                // R
                if (allow_LR && node->move_right && node->move_right->check(map))
                {
                    node_test = node->move_right->drop(map);
                    while (node_test->move_right && node_test->move_right->check(map))
                    {
                        node_test = node_test->move_right->drop(map);
                    }
                    if (node_mark_.set(node_test, node, 'R'))
                    {
                        if (node_test->index_filtered == index)
                        {
                            return build_path(node_test, node_mark_);
                        }
                        else
                        {
                            node_search_.push_back(node_test);
                        }
                    }
                }
            }
        } while (node_search_.size() > cache_index);
        return std::vector<char>();
    }

    std::vector<Search::TetrisNodeWithASpinType> const *Search::search_t(TetrisMap const &map, TetrisNode const *node, size_t depth)
    {
        TetrisMapSnap snap;
        node->build_snap(map, context_, snap);
        bool allow_180 = config_->allow_180;
        bool allow_d = config_->allow_d;
        bool is_20g = config_->is_20g;
        if (is_20g)
        {
            node = node->drop(map);
        }
        node_search_.push_back(node);
        node_mark_.mark(node);
        node_incomplete_.clear();
        size_t cache_index = 0;
        do
        {
            for (size_t max_index = node_search_.size(); cache_index < max_index; ++cache_index)
            {
                node = node_search_[cache_index];
                if (is_20g)
                {
                    node = node->drop(map);
                }
                if (!node->move_down || !node->move_down->check(snap))
                {
                    if (node_mark_filtered_.mark(node))
                    {
                        node_incomplete_.push_back(node);
                    }
                }
                // d
                if (allow_d)
                {
                    if (node->move_down && node_mark_.set(node->move_down, node, ' ') && node->move_down->check(snap))
                    {
                        node_search_.push_back(node->move_down);
                    }
                }
                else
                {
                    const TetrisNode *node_down = node->drop(map);
                    if (node_mark_.set(node_down, node, ' '))
                    {
                        node_search_.push_back(node_down);
                    }
                }
                // l
                if (node->move_left && node_mark_.set(node->move_left, node, ' ') && node->move_left->check(snap))
                {
                    node_search_.push_back(node->move_left);
                }
                // r
                if (node->move_right && node_mark_.set(node->move_right, node, ' ') && node->move_right->check(snap))
                {
                    node_search_.push_back(node->move_right);
                }
                if (allow_180)
                {
                    // x
                    for (TetrisNode const *wall_kick_node : node->wall_kick_opposite)
                    {
                        if (wall_kick_node)
                        {
                            if (wall_kick_node->check(snap))
                            {
                                if (node_mark_.cover_if(wall_kick_node, node, ' ', 'x'))
                                {
                                    node_search_.push_back(wall_kick_node);
                                }
                                break;
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }
                // z
                for (TetrisNode const *wall_kick_node : node->wall_kick_counterclockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(snap))
                        {
                            if (node_mark_.cover_if(wall_kick_node, node, ' ', 'z'))
                            {
                                node_search_.push_back(wall_kick_node);
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                // c
                for (TetrisNode const *wall_kick_node : node->wall_kick_clockwise)
                {
                    if (wall_kick_node)
                    {
                        if (wall_kick_node->check(snap))
                        {
                            if (node_mark_.cover_if(wall_kick_node, node, ' ', 'c'))
                            {
                                node_search_.push_back(wall_kick_node);
                            }
                            break;
                        }
                    }
                    else
                    {
                        break;
                    }
                }
            }
        } while (node_search_.size() > cache_index);
        for (auto const &node : node_incomplete_)
        {
            auto last = node_mark_.get(node);
            TetrisNodeWithASpinType node_ex(node);
            node_ex.last = last.first;
            node_ex.is_check = true;
            node_ex.is_last_rotate = last.second != ' ' || (node_ex.last == nullptr && depth == 0 && config_->last_rotate)
                                    || config_->direct_place_rotate;
            node_ex.is_ready = check_ready(map, node);
            node_ex.is_mini_ready = check_mini_ready(node_ex, map);
            // 卡住判定算一次并复用（原来在下面重复调用）
            const bool immobile = check_immobile(node_ex, snap);
            if (config_->mini_t_when_not_immobile && node_ex.is_ready)
            {
                // 本游戏（TowerTris）的 T 块口径（TetrisClearLine._detect_spin_type）：
                //   卡住（四向不可移动）→ "T-Spin"（全）
                //   没卡住 → 走 _detect_t_spin_mini()：3x3 包围盒**下两角都封堵** 且
                //             **上两角至少一个封堵** → "Mini T-Spin"，否则什么都不判。
                // 而 zzz 原生 / TETR.IO 口径是「没卡住就不算 Spin」。两者都不同，必须显式对齐：
                //   · 若照原生把 is_ready/is_mini_ready/is_last_rotate 全清掉，引擎会**完全看不到**
                //     这个 Mini T-Spin0 → Allspin_2 下当成普通放置 → 「连续两次 Spin0」的重复惩罚
                //     在预测里消失，实战却被游戏罚 20 行实心垃圾（就是「莫名触发」的来源）。
                //   · 也不能沿用 is_ready（那是「4 角占 3」的通用角型），游戏要求必须含下两角 →
                //     否则会把「上两角 + 下角一个」这种游戏不认的局面误报成 Spin0。
                if (immobile)
                {
                    node_ex.is_mini_ready = false;   // 卡住 → 全 T-Spin（游戏不看角型细分）
                }
                else
                {
                    // 精确复刻游戏 _detect_t_spin_mini 的角型。
                    // 坐标：引擎 y 向上（move_down 递减 y），行 0 = 游戏底行；
                    // 3x3 包围盒的行区间是 [tYc-1, tYc+1]（tYc = status.y - 1，与上面的
                    // check_ready / check_mini_ready 完全同一套口径），列区间是 [tXc-1, tXc+1]。
                    // 游戏里的「下两角」= 屏幕坐标 y 更大的一侧 = 引擎里 y **更小**的一侧 → tYc-1。
                    const int tXc = (int)node->status.x + 1;
                    const int tYc = (int)node->status.y - 1;
                    auto corner_blocked = [&map](int x, int y) -> bool {
                        if (x < 0 || x >= (int)map.width) return true;   // 左右墙
                        if (y < 0) return true;                          // 地板（y<0 = 游戏底行以下）
                        if (y >= (int)map.height) return false;          // 顶部以上 = 空
                        return map.full((size_t)x, (size_t)y);
                    };
                    const bool bl = corner_blocked(tXc - 1, tYc - 1);
                    const bool br = corner_blocked(tXc + 1, tYc - 1);
                    const bool tl = corner_blocked(tXc - 1, tYc + 1);
                    const bool tr = corner_blocked(tXc + 1, tYc + 1);
                    if (bl && br && (tl || tr))
                    {
                        node_ex.is_ready = false;       // 游戏判 Mini T-Spin（角型成立但没卡住）
                        node_ex.is_mini_ready = true;   // is_last_rotate 保留（Spin0 判定依赖它）
                    }
                    else
                    {
                        // 角型不成立：游戏什么都不判 → 也不能留下任何 spin 标记
                        node_ex.is_ready = false;
                        node_ex.is_mini_ready = false;
                        node_ex.is_last_rotate = false;
                    }
                }
            }
            if (!node_ex.is_ready && config_->allow_immobile_t && (config_->is_amini || config_->is_aspin))
            {
                if (immobile)
                {
                    if (config_->mini_t_when_not_immobile && node->status.t == 'T')
                    {
                        // 游戏：T 块「卡住 + 最后一次是旋转」→ "T-Spin"（全），不看角型。
                        // 这里不能落进下面的 AllSpin 分支，否则 T 会被标成全旋（类型与伤害都不对）。
                        if (node_ex.is_last_rotate)
                            node_ex.type = ASpinType::TSpin;
                    }
                    else
                    {
                        node_ex.type = (config_->spin_force_mini || config_->is_amini) ? ASpinMini : AllSpin;
                    }
                }
            }
            land_point_cache_.push_back(node_ex);
            if (node_ex.is_ready && !immobile) {
                // zzz 原生口径（mini_t_when_not_immobile = false 时才会走到这里）：
                // 角型成立但没卡住 → 不作 spin，三个 flag 一起清掉
                node_ex.is_ready = false;
                node_ex.is_mini_ready = false;
                node_ex.is_last_rotate = false;
                land_point_cache_.push_back(node_ex);
            }
        }
        return &land_point_cache_;
    }

    bool Search::check_ready(TetrisMap const &map, TetrisNode const *node)
    {
        int count;
        int y = node->status.y + y_diff_;
        int row = block_data_[node->status.x];
        if (y == 0)
        {
            return ZZZ_BitCount(map.row[1] & row) + 2 >= 3;
        }
        else
        {
            int x = node->status.x + x_diff_;
            if (x == 0 || x == map.width - 1)
            {
                count = 2;
            }
            else
            {
                count = 0;
            }
            return ZZZ_BitCount(map.row[y - 1] & row) + ZZZ_BitCount(map.row[y + 1] & row) + count >= 3;
        }
    }

    bool Search::check_mini_ready(TetrisNodeWithASpinType const &node, m_tetris::TetrisMap const &map)
    {
        const size_t tX = node.node->status.x + 1;
        const size_t tY = node.node->status.y - 1;
        const size_t tRotation = node.node->status.r;

        if (node.is_ready && tRotation != 2)
        {
            if (tRotation == 0)
            {
                return true;
            }
            else if (tRotation == 1)
            {
                if (map.full(tX - 1, tY + 1) && map.full(tX - 1, tY - 1))
                {
                    return true;
                }
                else if (tX == 0)
                    return true;
            }
            else if (tRotation == 3)
            {
                if (map.full(tX + 1, tY + 1) && map.full(tX + 1, tY - 1))
                {
                    return true;
                }
                else if (tX == map.width - 1)
                    return true;
            }
        }
        return false;
    }

    bool Search::check_immobile(TetrisNodeWithASpinType const &node, m_tetris::TetrisMapSnap const &snap)
    {
        return (!node->move_down || !node->move_down->check(snap)) && (!node->move_up || !node->move_up->check(snap)) && (!node->move_left || !node->move_left->check(snap)) && (!node->move_right || !node->move_right->check(snap));
    }
}
