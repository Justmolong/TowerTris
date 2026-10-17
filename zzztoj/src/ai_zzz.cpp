
//by ZouZhiZhang

#include "tetris_core.h"
#include "integer_utils.h"
#include "ai_zzz.h"
#include "ai_setting.h"
#include <cmath>
#include <cstdint>

using namespace m_tetris;
using namespace zzz;

namespace
{
    enum ItemType
    {
        a3, a2, a1, m3, m2, m1, sf, ss
    };
    struct Item
    {
        int16_t col, type;
    };
    const Item ItemTable[20][7] =
    {
#define I(a,b) {0x##a-1,b}
        //LLLLLLL   JJJJJJJ   TTTTTTT   OOOOOOO   IIIIIII   ZZZZZZZ   SSSSSSS//
        {I(A, a2), I(B, a3), I(C, sf), I(1, a1), I(2, a2), I(3, a3), I(4, m1)},
        {I(4, a1), I(3, a2), I(2, a3), I(1, sf), I(C, a1), I(B, a2), I(A, a3)},
        {I(8, ss), I(9, a1), I(A, a2), I(B, a3), I(C, sf), I(1, a1), I(2, a2)},
        {I(6, m3), I(5, m2), I(4, a1), I(3, a2), I(2, a3), I(1, sf), I(C, a1)},
        {I(6, m2), I(7, m3), I(8, ss), I(9, a1), I(A, a2), I(B, a3), I(C, sf)},
        {I(8, a1), I(7, m1), I(6, m1), I(5, m1), I(4, a1), I(3, a2), I(2, a3)},
        {I(4, sf), I(5, a1), I(6, m3), I(7, m2), I(8, m1), I(9, a1), I(A, a2)},
        {I(A, a3), I(9, sf), I(8, a1), I(7, m3), I(6, m1), I(5, ss), I(4, a1)},
        {I(2, a2), I(3, a3), I(4, sf), I(5, a1), I(6, m1), I(7, m3), I(8, m2)},
        {I(C, a1), I(B, a2), I(A, a3), I(9, sf), I(8, a1), I(7, m2), I(6, m3)},
        {I(C, sf), I(1, a1), I(2, a2), I(3, a3), I(4, sf), I(5, a1), I(6, m1)},
        {I(2, a3), I(1, sf), I(C, a1), I(B, a2), I(A, a3), I(9, sf), I(8, a1)},
        {I(A, ss), I(B, a3), I(C, sf), I(1, a1), I(2, a2), I(3, a3), I(4, sf)},
        {I(4, m3), I(3, m2), I(2, a3), I(1, sf), I(C, a1), I(B, a2), I(A, a3)},
        {I(8, m2), I(9, m3), I(A, ss), I(B, a3), I(C, sf), I(1, a1), I(2, a2)},
        {I(6, a3), I(5, m1), I(4, m1), I(3, m1), I(2, a3), I(1, sf), I(C, a1)},
        {I(6, a2), I(7, a3), I(8, m3), I(9, m2), I(A, m1), I(B, a3), I(C, sf)},
        {I(8, a1), I(7, a2), I(6, a3), I(5, m3), I(4, m1), I(3, ss), I(2, a3)},
        {I(4, sf), I(5, a1), I(6, a2), I(7, a3), I(8, m1), I(9, m3), I(A, m2)},
        {I(A, a3), I(9, sf), I(8, a1), I(7, a2), I(6, a3), I(5, m2), I(4, m3)},
        //LLLLLLL   JJJJJJJ   TTTTTTT   OOOOOOO   IIIIIII   ZZZZZZZ   SSSSSSS//
#undef I
    };

}

namespace ai_zzz
{
    // TowerTris 诊断计数：NoSpin4 下被判为「T 的 Spin0」并施加死亡惩罚的候选次数
    //（由 worker 的 WEIGHTS 命令读取，用于确认该分支真的在跑）
    // TowerTris 诊断计数：NoSpin4 下被判为「T 的 Spin0」并施加死亡惩罚的候选次数
    //（由 worker 的 WEIGHTS 命令读取，用于确认该分支真的在跑）
    // ⚠ 用原子：这些计数器在**搜索期间**自增，多线程并行扩展节点时不能是裸 int。
    static std::atomic<int> g_spin0_penalty_count{0};
    // TowerTris 诊断计数：Allspin 重复惩罚触发次数 / 其中「void 接 void」的次数。
    // void 重复（-1 == -1）是 Allspin_2 特有的判定，单独计数便于核对是否真的对齐。
    static std::atomic<int> g_repeat_penalty_count{0};
    static std::atomic<int> g_void_repeat_count{0};

    int spin0_penalty_count()
    {
        return g_spin0_penalty_count.load();
    }

    // TowerTris 诊断计数：Allspin 重复惩罚触发次数，以及其中「void 接 void」的次数。
    // 定义在 worker（zzztoj_worker.cpp）里，这里只提供只读访问。
    int repeat_penalty_count()
    {
        return g_repeat_penalty_count.load();
    }

    int void_repeat_count()
    {
        return g_void_repeat_count.load();
    }

    namespace qq
    {

        bool Attack::Status::operator < (Status const& other) const
        {
            return value < other.value;
        }


        void Attack::init(m_tetris::TetrisContext const* context, Config const* config)
        {
            context_ = context;
            config_ = config;
            check_line_1_end_ = check_line_1_;
            check_line_2_end_ = check_line_2_;
            const int full = context->full();
            for (int x = 0; x < context->width(); ++x)
            {
                *check_line_1_end_++ = full & ~(1 << x);
            }
            for (int x = 0; x < context->width() - 1; ++x)
            {
                *check_line_2_end_++ = full & ~(3 << x);
            }
            std::sort(check_line_1_, check_line_1_end_);
            std::sort(check_line_2_, check_line_2_end_);
            map_danger_data_.resize(context->type_max());
            for (size_t i = 0; i < context->type_max(); ++i)
            {
                TetrisMap map(context->width(), context->height());
                TetrisNode const* node = context->generate(i);
                node->attach(context, map);
                std::memcpy(map_danger_data_[i].data, &map.row[map.height - 4], sizeof map_danger_data_[i].data);
                for (int y = 0; y < 3; ++y)
                {
                    map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
                }
            }
            col_mask_ = context->full() & ~1;
            row_mask_ = context->full();
        }

        std::string Attack::ai_name() const
        {
            return "AX Attack v0.1";
        }

        Attack::Result Attack::eval(TetrisNode const* node, TetrisMap const& map, TetrisMap const& src_map, size_t clear) const
        {
            double LandHeight = node->row + node->height;
            double Middle = std::fabs((node->status.x + 1) * 2 - map.width);
            double EraseCount = clear;
            double DeadZone = node->row + node->height == map.height ? 500000. : 0;
            double BoardDeadZone = map_in_danger_(map);
            if (map.roof == map.height)
            {
                BoardDeadZone += 70;
            }

            const int width_m1 = map.width - 1;
            int ColTrans = 2 * (map.height - map.roof);
            int RowTrans = map.roof == map.height ? 0 : map.width;
            for (int y = 0; y < map.roof; ++y)
            {
                ColTrans += !map.full(0, y) + !map.full(width_m1, y) + ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
                if (y != 0)
                {
                    RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
                }
            }
            RowTrans += ZZZ_BitCount(row_mask_ & ~map.row[0]);
            RowTrans += ZZZ_BitCount(map.roof == map.height ? row_mask_ & ~map.row[map.roof - 1] : map.row[map.roof - 1]);
            struct
            {
                int HoleCount;
                int HoleLine;
                int HolePosy;
                int HolePiece;

                int HoleDepth;
                int WellDepth;

                int HoleNum[32];
                int WellNum[32];

                double AttackDepth;

                int Danger;
                int LineCoverBits;
                int TopHoleBits;
            } v;
            std::memset(&v, 0, sizeof v);

            for (int y = map.roof - 1; y >= 0; --y)
            {
                v.LineCoverBits |= map.row[y];
                int LineHole = v.LineCoverBits ^ map.row[y];
                if (LineHole != 0)
                {
                    v.HoleCount += ZZZ_BitCount(LineHole);
                    v.HoleLine++;
                    if (v.HolePosy == 0)
                    {
                        v.HolePosy = y + 1;
                        v.TopHoleBits = LineHole;
                    }
                }
                for (int x = 1; x < width_m1; ++x)
                {
                    if ((LineHole >> x) & 1)
                    {
                        v.HoleDepth += ++v.HoleNum[x];
                    }
                    else
                    {
                        v.HoleNum[x] = 0;
                    }
                    if (((v.LineCoverBits >> (x - 1)) & 7) == 5)
                    {
                        v.WellDepth += ++v.WellNum[x];
                    }
                }
                if (LineHole & 1)
                {
                    v.HoleDepth += ++v.HoleNum[0];
                }
                else
                {
                    v.HoleNum[0] = 0;
                }
                if ((v.LineCoverBits & 3) == 2)
                {
                    v.WellDepth += ++v.WellNum[0];
                }
                if ((LineHole >> width_m1) & 1)
                {
                    v.HoleDepth += ++v.HoleNum[width_m1];
                }
                else
                {
                    v.HoleNum[width_m1] = 0;
                }
                if (((v.LineCoverBits >> (width_m1 - 1)) & 3) == 1)
                {
                    v.WellDepth += ++v.WellNum[width_m1];
                }
            }
            if (v.HolePosy != 0)
            {
                for (int y = v.HolePosy; y < map.roof; ++y)
                {
                    int CheckLine = v.TopHoleBits & map.row[y];
                    if (CheckLine == 0)
                    {
                        break;
                    }
                    v.HolePiece += (y + 1) * ZZZ_BitCount(CheckLine);
                }
            }
            int low_x;
            if ((config_->mode & 1) == 0)
            {
                low_x = 1;
                for (int x = 2; x < width_m1; ++x)
                {
                    if (map.top[x] < map.top[low_x])
                    {
                        low_x = x;
                    }
                }
                if (map.top[0] < map.top[low_x])
                {
                    low_x = 0;
                }
                if (map.top[width_m1] < map.top[low_x])
                {
                    low_x = width_m1;
                }
            }
            else
            {
                low_x = (map.top[width_m1 - 3] <= map.top[width_m1 - 4]) ? width_m1 - 3 : width_m1 - 4;
                if (map.top[width_m1 - 2] <= map.top[low_x])
                {
                    low_x = width_m1 - 2;
                }
            }
            int low_y = map.top[low_x];
            for (int y = map.roof - 1; y >= low_y; --y)
            {
                if (std::binary_search<uint32_t const*>(check_line_1_, check_line_1_end_, map.row[y]))
                {
                    if (y + 1 < map.height && std::binary_search<uint32_t const*>(check_line_2_, check_line_2_end_, map.row[y + 1]))
                    {
                        v.AttackDepth += 20;
                    }
                    else
                    {
                        v.AttackDepth += 16;
                    }
                    for (--y; y >= low_y; --y)
                    {
                        if (std::binary_search<uint32_t const*>(check_line_1_, check_line_1_end_, map.row[y]))
                        {
                            v.AttackDepth += 3;
                        }
                        else
                        {
                            v.AttackDepth -= 5;
                        }
                    }
                    break;
                }
                else
                {
                    v.AttackDepth -= 2;
                }
            }
            v.Danger = 5 - std::min(map.height - low_y, 5);
            if (v.Danger > 0 && v.AttackDepth < 20)
            {
                v.AttackDepth = 0;
            }

            Result result;
            result.land_point = (0.
                - LandHeight * 16
                + Middle * 0.2
                + EraseCount * 6
                - DeadZone
                - BoardDeadZone * 500000
                );
            result.map = (0.
                - ColTrans * 32
                - RowTrans * 32
                - v.HoleCount * 400
                - v.HoleLine * 38
                - v.WellDepth * 16
                - v.HoleDepth * 4
                - v.HolePiece * 2
                + v.AttackDepth * 100
                );
            result.clear = clear;
            result.danger = v.Danger;
            return result;
        }

        Attack::Status Attack::get(m_tetris::TetrisNode const* node, Result const& eval_result, size_t depth, Status const& status) const
        {

            Status result = status;
            result.land_point += eval_result.land_point;
            double length_rate = 10. / (depth + 1);
            switch (eval_result.clear)
            {
            case 0:
                break;
            case 1:
            case 2:
                result.rubbish += eval_result.clear;
                break;
            case 3:
                if (config_->mode != 0)
                {
                    result.attack += 12;
                    break;
                }
            default:
                result.attack += (eval_result.clear * 10 * length_rate);
                break;
            }
            result.value = (0.
                + result.land_point / (depth + 1)
                + eval_result.map
                - result.rubbish * (eval_result.danger > 0 ? -100 : 640)
                + result.attack * 100
                );
            return result;
        }

        size_t Attack::map_in_danger_(m_tetris::TetrisMap const& map) const
        {
            size_t danger = 0;
            for (size_t i = 0; i < context_->type_max(); ++i)
            {
                if (map_danger_data_[i].data[0] & map.row[map.height - 4] || map_danger_data_[i].data[1] & map.row[map.height - 3] || map_danger_data_[i].data[2] & map.row[map.height - 2] || map_danger_data_[i].data[3] & map.row[map.height - 1])
                {
                    ++danger;
                }
            }
            return danger;
        }
    }

    void Dig::init(m_tetris::TetrisContext const* context, Config const* config)
    {
        context_ = context;
        map_danger_data_.resize(context->type_max());
        for (size_t i = 0; i < context->type_max(); ++i)
        {
            TetrisMap map(context->width(), context->height());
            TetrisNode const* node = context->generate(i);
            node->attach(context, map);
            std::memcpy(map_danger_data_[i].data, &map.row[map.height - 4], sizeof map_danger_data_[i].data);
            for (int y = 0; y < 3; ++y)
            {
                map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
            }
        }
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
        config_ = config;
    }

    std::string Dig::ai_name() const
    {
        return "ZZZ Dig v0.2";
    }

    double Dig::eval(m_tetris::TetrisNode const* node, m_tetris::TetrisMap const& map, m_tetris::TetrisMap const& src_map, size_t clear) const
    {
        const int width_m1 = map.width - 1;
        size_t ColTrans = 2 * (map.height - map.roof);
        size_t RowTrans = ZZZ_BitCount(row_mask_ ^ map.row[0]) + ZZZ_BitCount(map.roof == map.height ? ~row_mask_ & map.row[map.roof - 1] : map.row[map.roof - 1]);
        for (int y = 0; y < map.roof; ++y)
        {
            ColTrans += !map.full(0, y) + !map.full(width_m1, y) + ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
            }
        }
        struct
        {
            int HoleCount;
            int HoleLine;

            double HoleDepth;
            double WellDepth;

            int HoleNum[32];
            int WellNum[32];

            int LineCoverBits;
            int HolePosyIndex;
        } v;
        std::memset(&v, 0, sizeof v);
        struct
        {
            double ClearWidth;
        } a[40];

        for (int y = map.roof - 1; y >= 0; --y)
        {
            v.LineCoverBits |= map.row[y];
            int LineHole = v.LineCoverBits ^ map.row[y];
            if (LineHole != 0)
            {
                v.HoleCount += ZZZ_BitCount(LineHole);
                ++v.HoleLine;
                a[v.HolePosyIndex].ClearWidth = 0;
                for (int hy = y + 1; hy < map.roof; ++hy)
                {
                    uint32_t CheckLine = LineHole & map.row[hy];
                    if (CheckLine == 0)
                    {
                        break;
                    }
                    a[v.HolePosyIndex].ClearWidth += (hy + 1 + config_->p[0]) * config_->p[1] * ZZZ_BitCount(CheckLine);
                }
                ++v.HolePosyIndex;
            }
            for (int x = 1; x < width_m1; ++x)
            {
                if ((LineHole >> x) & 1)
                {
                    v.HoleDepth += (++v.HoleNum[x] + config_->p[4]) * config_->p[5];
                }
                else
                {
                    v.HoleNum[x] = 0;
                }
                if (((v.LineCoverBits >> (x - 1)) & 7) == 5)
                {
                    v.WellDepth += (++v.WellNum[x] + config_->p[2]) * config_->p[3];
                }
            }
            if (LineHole & 1)
            {
                v.HoleDepth += (++v.HoleNum[0] + config_->p[4]) * config_->p[5];
            }
            else
            {
                v.HoleNum[0] = 0;
            }
            if ((v.LineCoverBits & 3) == 2)
            {
                v.WellDepth += (++v.WellNum[0] + config_->p[2]) * config_->p[3];
            }
            if ((LineHole >> width_m1) & 1)
            {
                v.HoleDepth += (++v.HoleNum[width_m1] + config_->p[4]) * config_->p[5];
            }
            else
            {
                v.HoleNum[width_m1] = 0;
            }
            if (((v.LineCoverBits >> (width_m1 - 1)) & 3) == 1)
            {
                v.WellDepth += (++v.WellNum[width_m1] + config_->p[2]) * config_->p[3];
            }
        }

        size_t BoardDeadZone = map_in_danger_(map);

        double value = (0.
            - (map.roof + config_->p[6]) * config_->p[7]
            - (ColTrans + config_->p[8]) * config_->p[9]
            - (RowTrans + config_->p[10]) * config_->p[11]
            - (v.HoleCount + config_->p[12]) * config_->p[13]
            - (v.HoleLine + config_->p[14]) * config_->p[15]
            - (v.WellDepth + config_->p[16]) * config_->p[17]
            - (v.HoleDepth + config_->p[18]) * config_->p[19]
            - (BoardDeadZone + config_->p[20]) * config_->p[21]
            );
        double rate = config_->p[22], mul = config_->p[23];
        for (int i = 0; i < v.HolePosyIndex; ++i, rate *= mul)
        {
            value -= a[i].ClearWidth * rate;
        }
        return value;
    }

    double Dig::get(m_tetris::TetrisNode const* node, double const& eval_result) const
    {
        return eval_result;
    }

    size_t Dig::map_in_danger_(m_tetris::TetrisMap const& map) const
    {
        size_t danger = 0;
        for (size_t i = 0; i < context_->type_max(); ++i)
        {
            if (map_danger_data_[i].data[0] & map.row[map.height - 4] || map_danger_data_[i].data[1] & map.row[map.height - 3] || map_danger_data_[i].data[2] & map.row[map.height - 2] || map_danger_data_[i].data[3] & map.row[map.height - 1])
            {
                ++danger;
            }
        }
        return danger;
    }

    bool TOJ::Status::operator < (Status const& other) const
    {
        return value < other.value;
    }

    int8_t TOJ::get_safe(m_tetris::TetrisMap const& m, char t) const {
        int safe = 0;
        while (map_in_danger_(m, context_->convert(t), safe + 1) == 0)
        {
            ++safe;
        }
        return safe;
    }

    void TOJ::init(m_tetris::TetrisContext const* context, Config const* config)
    {
        context_ = context;
        config_ = config;
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
        map_danger_data_.resize(context->type_max());
        for (size_t i = 0; i < context->type_max(); ++i)
        {
            TetrisMap map(context->width(), context->height());
            TetrisNode const* node = context->generate(i);
            node->attach(context, map);
            std::memcpy(map_danger_data_[i].data, &map.row[18], sizeof map_danger_data_[i].data);
            for (int y = 0; y < 3; ++y)
            {
                map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
            }
        }
    }

    std::string TOJ::ai_name() const
    {
        return "ZZZ TOJ v0.12";
    }

    void TOJ::Status::init_t_value(TetrisMap const& map, int16_t& t2_value_ref, int16_t& t3_value_ref, TetrisMap* out_map)
    {
        int row_bit_count_global[40];
        for (int y = 0; y < map.roof; ++y)
        {
            row_bit_count_global[y] = ZZZ_BitCount(map.row[y]);
        }
        memset(row_bit_count_global + map.roof, 0, sizeof(int) * (40 - map.roof));
        t2_value_ref = 0;
        t3_value_ref = 0;
        for (int y = 0, ey = std::min(20, map.roof - 2); y < ey; ++y)
        {
            int new_y = y;
            int row0 = map.row[y];
            int row1 = map.row[y + 1];
            int row2 = map.row[y + 2];
            int row3 = map.row[y + 3];
            int row4 = map.row[y + 4];
            int row5 = map.row[y + 5];
            int row6 = map.row[y + 6];
            int* row_bit_count = row_bit_count_global + y;
            for (int x = 1, ex = map.width - 2; x < ex; ++x)
            {
                if (((~row0 >> x) & 1) & (((~row1 >> x) & 3) == 3) & ((~row2 >> x) & 1) & !((row3 >> x) & 7) & (((~row4 >> x) & 6) == 6))
                {
                    int t3_count = 0;
                    if (row_bit_count[0] == map.width - 1)
                    {
                        t3_count += 1;
                    }
                    if (row_bit_count[1] == map.width - 2)
                    {
                        t3_count += 1;
                    }
                    if (row_bit_count[2] == map.width - 1)
                    {
                        t3_count += 1;
                    }
                    else
                    {
                        continue;
                    }
                    int t3_bit_count = row_bit_count[0] + row_bit_count[1] + row_bit_count[2];
                    if (t3_count >= 2 && t3_bit_count > map.width * 2)
                    {
                        int t3_value = t3_bit_count * t3_count;
                        if ((row4 >> x) & 1)
                        {
                            t3_value += t3_bit_count + row_bit_count[3];
                        }
                        else if (((row4 >> x) & 7) == 1 && ((row5 >> x) & 7) == 1 && ((row6 >> x) & 7) == 1)
                        {
                            t3_value = 0;
                        }
                        else
                        {
                            t3_value /= 2;
                        }
                        if (((row3 >> x) & 8) != ((row4 >> x) & 8))
                        {
                            t3_value = 0;
                        }
                        if (t3_value > 0 && out_map != nullptr)
                        {
                            out_map->row[y + 0] |= 1 << x;
                            out_map->row[y + 1] |= 3 << x;
                            out_map->row[y + 2] |= 1 << x;
                            out_map->row[y + 3] |= 1 << x;
                        }
                        t3_value_ref += t3_value;
                        new_y += 2;
                        break;
                    }
                }
            }
            if (new_y != y)
            {
                y = new_y;
                continue;
            }
            for (int x = 0, ex = map.width - 3; x < ex; ++x)
            {
                if (((~row0 >> x) & 4) & (((~row1 >> x) & 6) == 6) & ((~row2 >> x) & 4) & !((row3 >> x) & 7) & (((~row4 >> x) & 3) == 3))
                {
                    int t3_count = 0;
                    if (row_bit_count[0] == map.width - 1)
                    {
                        t3_count += 1;
                    }
                    if (row_bit_count[1] == map.width - 2)
                    {
                        t3_count += 1;
                    }
                    if (row_bit_count[2] == map.width - 1)
                    {
                        t3_count += 1;
                    }
                    else
                    {
                        continue;
                    }
                    int t3_bit_count = row_bit_count[0] + row_bit_count[1] + row_bit_count[2];
                    if (t3_count >= 2 && t3_bit_count > map.width * 2)
                    {
                        int t3_value = t3_bit_count * t3_count;
                        if ((row2 >> x) & 2)
                        {
                            t3_value += t3_bit_count;
                        }
                        else if (((row4 >> x) & 7) == 4 && ((row5 >> x) & 7) == 4 && ((row6 >> x) & 7) == 4)
                        {
                            t3_value = 0;
                        }
                        else
                        {
                            t3_value /= 4;
                        }
                        if (((row3 >> x) & 1) != ((row4 >> x) & 1))
                        {
                            t3_value = 0;
                        }
                        if (t3_value > 0 && out_map != nullptr)
                        {
                            out_map->row[y + 0] |= 4 << x;
                            out_map->row[y + 1] |= 6 << x;
                            out_map->row[y + 2] |= 4 << x;
                            out_map->row[y + 3] |= 4 << x;
                        }
                        t3_value_ref += t3_value;
                        new_y += 2;
                        break;
                    }
                }
            }
            if (new_y != y)
            {
                y = new_y;
                continue;
            }
            for (int x = 0, ex = map.width - 2; x < ex; ++x)
            {
                if ((((row0 >> x) & 7) == 5) & !((row1 >> x) & 7))
                {
                    int row01_count = row_bit_count[0] + row_bit_count[1];
                    int t2_value = row01_count;
                    if (row01_count > map.width)
                    {
                        if (row_bit_count[0] == map.width - 1)
                        {
                            t2_value += row01_count;
                        }
                        if (row_bit_count[1] == map.width - 3)
                        {
                            t2_value += row01_count;
                        }
                        int row2_check = (row2 >> x) & 7;
                        switch (row2_check)
                        {
                        case 1: case 4:
                            t2_value += row01_count * 3;
                            break;
                        case 2: case 3: case 5: case 6: case 7:
                            t2_value = 0;
                            break;
                        default:
                            t2_value = t2_value / 2;
                            break;
                        }
                        if (t2_value > 0 && out_map != nullptr)
                        {
                            out_map->row[y + 0] |= 2 << x;
                            out_map->row[y + 1] |= 7 << x;
                        }
                        t2_value_ref += t2_value;
                        ++new_y;
                        break;
                    }
                    t2_value_ref += t2_value;
                }
            }
            y = new_y;
        }
    };

    TOJ::Result TOJ::eval(TetrisNodeEx const& node, TetrisMap const& map, TetrisMap const& src_map, size_t clear) const
    {
        const int width_m1 = map.width - 1;

        Result result;
        memset(&result, 0, sizeof result);

        TetrisMap t_map = map;
        Status::init_t_value(t_map, result.t2_value, result.t3_value, &t_map);

        size_t ColTrans = 2 * (t_map.height - t_map.roof);
        size_t RowTrans = t_map.roof == t_map.height ? 0 : t_map.width;
        for (int y = 0; y < t_map.roof; ++y)
        {
            ColTrans += !t_map.full(0, y) + !t_map.full(width_m1, y) + ZZZ_BitCount((t_map.row[y] ^ (t_map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(t_map.row[y - 1] ^ t_map.row[y]);
            }
        }
        RowTrans += ZZZ_BitCount(row_mask_ & ~t_map.row[0]);
        RowTrans += ZZZ_BitCount(t_map.roof == t_map.height ? row_mask_ & ~t_map.row[t_map.roof - 1] : t_map.row[t_map.roof - 1]);
        struct
        {
            int HoleCount;
            int HoleLine;

            int Wide[31];

            int LineCoverBits;
            int ClearWidth;
        } v;
        std::memset(&v, 0, sizeof v);
        int WideCount = t_map.width - 1;

        for (int y = t_map.roof - 1; y >= 0; --y)
        {
            v.LineCoverBits |= t_map.row[y];
            int LineHole = v.LineCoverBits ^ t_map.row[y];
            if (LineHole != 0)
            {
                v.HoleCount += ZZZ_BitCount(LineHole);
                ++v.HoleLine;
                for (int hy = y + 1, hy_max = std::min(t_map.roof, hy + 8); hy < hy_max; ++hy)
                {
                    uint32_t CheckLine = LineHole & t_map.row[hy];
                    if (CheckLine > 0)
                    {
                        v.ClearWidth += (t_map.width - ZZZ_BitCount(t_map.row[hy])) * hy;
                    }
                }
            }
            WideCount = std::min<int>(WideCount, t_map.width - ZZZ_BitCount(v.LineCoverBits));
            if (v.HoleLine == 0)
            {
                ++v.Wide[WideCount];
            }
        }
        int side_roof = std::max({ map.top[0], map.top[1], map.top[2], map.top[width_m1], map.top[width_m1 - 1], map.top[width_m1 - 2] });
        auto& p = config_->param;
        result.value = (0.
            - side_roof * p.roof
            - ColTrans * p.col_trans
            - RowTrans * p.row_trans
            - v.HoleCount * p.hole_count
            - v.HoleLine * p.hole_line
            - v.ClearWidth * p.clear_width
            + v.Wide[2] * p.wide_2
            + v.Wide[3] * p.wide_3
            + v.Wide[4] * p.wide_4
            );
        result.count = t_map.count;
        result.clear = int8_t(clear);
        result.top_out = node->row >= 20;
        result.map = &map;
        return result;
    }

    TOJ::Status TOJ::get(TetrisNodeEx& node, Result const& eval_result, size_t depth, Status const& status, TetrisContext::Env const& env) const
    {
        if (eval_result.clear > 0 && node.is_check && node.is_last_rotate)
        {
            if (eval_result.clear == 1 && node.is_mini_ready)
            {
                node.type = TSpinType::TSpinMini;
            }
            else if (node.is_ready)
            {
                node.type = TSpinType::TSpin;
            }
            else
            {
                node.type = TSpinType::None;
            }
        }
        Status result;
        memcpy(&result, &status, sizeof status);
        int attack = 0;
        int t_attack = 0;
        double like = 0;
        double dislike = 0;
        auto get_combo_attack = [&](int c)
        {
            return config_->table[std::min<int>(config_->table_max - 1, c + 1)];
        };
        auto update_like = [&](double v)
        {
            v > 0 ? like += v : dislike -= v;
        };
        int safe = node->row >= 20 ? -1 : env.length > 0 ? get_safe(*eval_result.map, *env.next) : eval_result.map->roof;
        auto& p = config_->param;
        switch (eval_result.clear)
        {
        case 0:
            result.combo = 0;
            if (status.under_attack > 0)
            {
                result.map_rise = status.under_attack;
                if (result.map_rise > safe)
                {
                    result.death = 1;
                }
                result.under_attack = 0;
            }
            update_like((node->status.t == 'I') * p.waste_i);
            update_like((node->status.t == 'T') * p.waste_t);
            break;
        case 1:
            if (node.type == TSpinType::TSpinMini)
            {
                attack = 1 + status.b2b;
                update_like(p.tspin_mini);
            }
            else if (node.type == TSpinType::TSpin)
            {
                attack = 2 + status.b2b;
                update_like(p.tspin_1);
                t_attack = 1;
            }
            else
            {
                update_like((node->status.t == 'I') * p.waste_i);
                update_like((node->status.t == 'T') * p.waste_t);
                update_like(p.clear_1);
            }
            attack += get_combo_attack(++result.combo);
            result.b2b = node.type != TSpinType::None;
            break;
        case 2:
            if (node.type != TSpinType::None)
            {
                attack += 4 + status.b2b;
                result.b2b = true;
                update_like(p.tspin_2);
                t_attack = 1;
            }
            else
            {
                ++attack;
                result.b2b = false;
                update_like((node->status.t == 'I') * p.waste_i);
                update_like((node->status.t == 'T') * p.waste_t);
                update_like(p.clear_2);
            }
            attack += get_combo_attack(++result.combo);
            break;
        case 3:
            if (node.type != TSpinType::None)
            {
                attack = 6 + status.b2b * 2;
                result.b2b = true;
                update_like(p.tspin_3);
                t_attack = 1;
            }
            else
            {
                attack += 2;
                result.b2b = false;
                update_like((node->status.t == 'I') * p.waste_i);
                update_like(p.clear_3);
            }
            attack += get_combo_attack(++result.combo);
            break;
        case 4:
            result.b2b = true;
            attack = get_combo_attack(++result.combo) + 4 + status.b2b;
            update_like(p.clear_4);
            break;
        }
        int upcomeAtt = result.under_attack;
        result.under_attack = std::max(0, result.under_attack - attack);
        attack -= std::max(0, attack - upcomeAtt);
        int config_safe = std::max(0, config_->safe - result.under_attack - result.map_rise);
        int t_expect = [=]()->int
        {
            if (env.hold == 'T')
            {
                return 0;
            }
            for (size_t i = 0; i < env.length; ++i)
            {
                if (env.next[i] == 'T')
                {
                    return i;
                }
            }
            return 13;
        }();
        switch (env.hold)
        {
        case 'T':
            if (node.type == TSpinType::None)
            {
                update_like(double(20 + config_safe) * p.hold_t);
            }
            break;
        case 'I':
            if (eval_result.clear != 4)
            {
                update_like(double(40 - config_safe) * p.hold_i);
            }
            break;
        }
        safe -= result.map_rise + eval_result.clear;
        if (safe < 0 || eval_result.top_out)
        {
            result.death = 1;
            safe = 0;
        }
        if (eval_result.count == 0 && result.map_rise == 0)
        {
            like += 999;
            attack += 6;
        }
        double field = eval_result.value * double(40 - config_safe) / 20;
        double t_like = 0;
        double t_dislike = 0;
        if (t_attack == 0)
        {
            double t2_safe = std::max(0, config_safe - 4);
            double t3_safe = std::max(0, config_safe - 10);
            if (eval_result.t2_value > status.t2_value)
            {
                t_like += (eval_result.t2_value - status.t2_value) * t2_safe * std::max(10 - t_expect, 5) * p.t2_slot;
            }
            else
            {
                t_dislike += (status.t2_value - eval_result.t2_value) * t2_safe * 3 * p.t2_slot;
            }
            if (eval_result.t3_value > status.t3_value)
            {
                t_like += (eval_result.t3_value - status.t3_value) * t3_safe * std::max(10 - t_expect, 4) * (3 + result.b2b) * p.t3_slot;
            }
            else
            {
                t_dislike += (status.t3_value - eval_result.t3_value) * t3_safe * 4 * p.t3_slot;
            }
        }
        result.t2_value = eval_result.t2_value;
        result.t3_value = eval_result.t3_value;
        result.acc_value += (0
            + attack * (config_safe + 16) * p.attack
            + get_combo_attack(result.combo) * result.combo * (100 - config_safe) * p.combo
            + (result.b2b - status.b2b) * (config_safe + 16) * p.b2b
            - t_dislike
            - dislike * config_safe * (config_safe + 4) * 4
            - result.death * 999999999.0
            );
        result.like = (status.like * 1.3
            + safe * (40 - config_safe) * p.safe
            + like * config_safe * (config_safe + 4) * 4
            + t_like
            );
        result.value = (result.acc_value
            - result.map_rise * (40 - config_safe) * p.safe
            + result.like
            + field * p.base
            );
        return result;
    }

    size_t TOJ::map_in_danger_(m_tetris::TetrisMap const& map, size_t t, size_t up) const
    {
        if (up >= 20)
        {
            return 1;
        }
        size_t height = 22 - up;
        return map_danger_data_[t].data[0] & map.row[height - 4] | map_danger_data_[t].data[1] & map.row[height - 3] | map_danger_data_[t].data[2] & map.row[height - 2] | map_danger_data_[t].data[3] & map.row[height - 1];
    }

    bool TOJ_PC::Status::operator < (Status const& other) const
    {
        return value < other.value;
    }

    std::string TOJ_PC::ai_name() const
    {
        return "ZZZ TOJ_PC v0.1";
    }

    void TOJ_PC::init(m_tetris::TetrisContext const* context, Config const* config) {
        context_ = context;
        config_ = config;
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
    }

    TOJ_PC::Result TOJ_PC::eval(TetrisNodeEx const& node, m_tetris::TetrisMap const& map, m_tetris::TetrisMap const&, size_t clear) const
    {
        const int width_m1 = map.width - 1;
        int ColTrans = 2 * (map.height - map.roof);
        int RowTrans = map.roof == map.height ? 0 : map.width;
        for (int y = 0; y < map.roof; ++y)
        {
            if (!map.full(0, y))
            {
                ++ColTrans;
            }
            if (!map.full(width_m1, y))
            {
                ++ColTrans;
            }
            ColTrans += ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
            }
        }
        RowTrans += ZZZ_BitCount(row_mask_ & ~map.row[0]);
        RowTrans += ZZZ_BitCount(map.roof == map.height ? row_mask_ & ~map.row[map.roof - 1] : map.row[map.roof - 1]);

        Result result;
        result.value = (map.roof > 4 ? 0 : 10000) - ColTrans * 3 - RowTrans * 2;
        result.clear = clear;
        result.roof = map.roof;
        return result;
    }

    TOJ_PC::Status TOJ_PC::get(TetrisNodeEx& node, Result const& eval_result, size_t depth, Status const& status) const {

        Status result = status;
        if (eval_result.clear > 0 && node.is_check && node.is_last_rotate)
        {
            if (eval_result.clear == 1 && node.is_mini_ready)
            {
                node.type = TSpinType::TSpinMini;
            }
            else if (node.is_ready)
            {
                node.type = TSpinType::TSpin;
            }
            else
            {
                node.type = TSpinType::None;
            }
        }

        switch (eval_result.clear)
        {
        case 0:
            result.combo = 0;
            if (status.under_attack > 0)
            {
                result.recv_attack += std::max(0, int(status.under_attack) - status.attack);
                result.under_attack = 0;
            }
            break;
        case 1:
            if (node.type == TSpinType::TSpinMini)
            {
                result.attack += status.b2b ? 2 : 1;
            }
            else if (node.type == TSpinType::TSpin)
            {
                result.attack += status.b2b ? 3 : 2;
            }
            result.attack += config_->table[std::min(config_->table_max - 1, ++result.combo)];
            result.b2b = node.type != TSpinType::None;
            break;
        case 2:
            if (node.type != TSpinType::None)
            {
                result.attack += status.b2b ? 5 : 4;
            }
            result.attack += config_->table[std::min(config_->table_max - 1, ++result.combo)] + 1;
            result.b2b = node.type != TSpinType::None;
            break;
        case 3:
            if (node.type != TSpinType::None)
            {
                result.attack += status.b2b ? 8 : 6;
            }
            result.attack += config_->table[std::min(config_->table_max - 1, ++result.combo)] + 2;
            result.b2b = node.type != TSpinType::None;
            break;
        case 4:
            result.attack += config_->table[std::min(config_->table_max - 1, ++result.combo)] + (status.b2b ? 5 : 4);
            result.b2b = true;
            break;
        }
        if (eval_result.roof == 0 && result.recv_attack == 0) {
            result.like += 100;
            result.pc = true;
        }
        if (eval_result.roof > 4) {
            result.like -= 1;
        }
        result.value = eval_result.value + result.like * 1e9;
        return result;
    }

    bool TOJ_v08::Status::operator < (Status const& other) const
    {
        return value < other.value;
    }

    int8_t TOJ_v08::get_safe(m_tetris::TetrisMap const& m, char t) const {
        int safe = 0;
        while (map_in_danger_(m, context_->convert(t), safe + 1) == 0)
        {
            ++safe;
        }
        return safe;
    }

    void TOJ_v08::init(m_tetris::TetrisContext const* context, Config const* config)
    {
        context_ = context;
        config_ = config;
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
        full_count_ = context->width() * 24;
        map_danger_data_.resize(context->type_max());
        for (size_t i = 0; i < context->type_max(); ++i)
        {
            TetrisMap map(context->width(), context->height());
            TetrisNode const* node = context->generate(i);
            node->attach(context, map);
            std::memcpy(map_danger_data_[i].data, &map.row[18], sizeof map_danger_data_[i].data);
            for (int y = 0; y < 3; ++y)
            {
                map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
            }
        }
    }

    std::string TOJ_v08::ai_name() const
    {
        return "ZZZ TOJ v0.8";
    }

    TOJ_v08::Result TOJ_v08::eval(TetrisNodeEx const& node, m_tetris::TetrisMap const& map, m_tetris::TetrisMap const& src_map, size_t clear) const
    {
        const int width_m1 = map.width - 1;
        int ColTrans = 2 * (map.height - map.roof);
        int RowTrans = map.roof == map.height ? 0 : map.width;
        for (int y = 0; y < map.roof; ++y)
        {
            if (!map.full(0, y))
            {
                ++ColTrans;
            }
            if (!map.full(width_m1, y))
            {
                ++ColTrans;
            }
            ColTrans += ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
            }
        }
        RowTrans += ZZZ_BitCount(row_mask_ & ~map.row[0]);
        RowTrans += ZZZ_BitCount(map.roof == map.height ? row_mask_ & ~map.row[map.roof - 1] : map.row[map.roof - 1]);
        struct
        {
            int HoleCount;
            int HoleLine;

            int HoleDepth;
            int WellDepth;

            int HoleNum[32];
            int WellNum[32];

            int LineCoverBits;
            int HolePosyIndex;
        } v;
        std::memset(&v, 0, sizeof v);
        struct
        {
            int ClearWidth;
        } a[40];

        for (int y = map.roof - 1; y >= 0; --y)
        {
            v.LineCoverBits |= map.row[y];
            int LineHole = v.LineCoverBits ^ map.row[y];
            if (LineHole != 0)
            {
                ++v.HoleLine;
                a[v.HolePosyIndex].ClearWidth = 0;
                v.HoleCount += ZZZ_BitCount(LineHole);
                for (int hy = y + 1; hy < map.roof; ++hy)
                {
                    uint32_t CheckLine = LineHole & map.row[hy];
                    if (CheckLine == 0)
                    {
                        break;
                    }
                    a[v.HolePosyIndex].ClearWidth += (hy + 1) * ZZZ_BitCount(CheckLine);
                }
                ++v.HolePosyIndex;
            }
            for (int x = 1; x < width_m1; ++x)
            {
                if ((LineHole >> x) & 1)
                {
                    v.HoleDepth += ++v.HoleNum[x];
                }
                else
                {
                    v.HoleNum[x] = 0;
                }
                if (((v.LineCoverBits >> (x - 1)) & 7) == 5)
                {
                    v.WellDepth += ++v.WellNum[x];
                }
            }
            if (LineHole & 1)
            {
                v.HoleDepth += ++v.HoleNum[0];
            }
            else
            {
                v.HoleNum[0] = 0;
            }
            if ((v.LineCoverBits & 3) == 2)
            {
                v.WellDepth += ++v.WellNum[0];
            }
            if ((LineHole >> width_m1) & 1)
            {
                v.HoleDepth += ++v.HoleNum[width_m1];
            }
            else
            {
                v.HoleNum[width_m1] = 0;
            }
            if (((v.LineCoverBits >> (width_m1 - 1)) & 3) == 1)
            {
                v.WellDepth += ++v.WellNum[width_m1];
            }
        }
        auto& p = config_->param;
        Result result;
        result.value = (0.
            - map.roof * p.roof
            - ColTrans * p.col_trans
            - RowTrans * p.row_trans
            - v.HoleCount * p.hole_count
            - v.HoleLine * p.hole_line
            - v.WellDepth * p.well_depth
            - v.HoleDepth * p.hole_depth
            );
        double rate = 32, mul = 1.0 / 4;
        for (int i = 0; i < v.HolePosyIndex; ++i, rate *= mul)
        {
            result.value -= a[i].ClearWidth * rate;
        }
        result.count = map.count;
        result.clear = clear;
        result.t2_value = 0;
        result.t3_value = 0;
        result.map = &map;
        bool finding2 = true;
        bool finding3 = true;
        for (int y = 0; (finding2 || finding3) && y < map.roof - 2; ++y)
        {
            int row0 = map.row[y];
            int row1 = map.row[y + 1];
            int row2 = y + 2 < map.height ? map.row[y + 2] : 0;
            int row3 = y + 3 < map.height ? map.row[y + 3] : 0;
            int row4 = y + 4 < map.height ? map.row[y + 4] : 0;
            for (int x = 0; finding2 && x < map.width - 2; ++x)
            {
                if (((row0 >> x) & 7) == 5 && ((row1 >> x) & 7) == 0)
                {
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        result.t2_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 3)
                        {
                            result.t2_value += 2;
                            int row2_check = (row2 >> x) & 7;
                            if (row2_check == 1 || row2_check == 4)
                            {
                                result.t2_value += 2;
                            }
                            finding2 = false;
                        }
                    }
                }
            }
            for (int x = 0; finding3 && x < map.width - 3; ++x)
            {
                if (((row0 >> x) & 15) == 11 && ((row1 >> x) & 15) == 9)
                {
                    int t3_value = 0;
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        t3_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 2)
                        {
                            t3_value += 1;
                            if (((row2 >> x) & 15) == 11)
                            {
                                t3_value += 2;
                                if (ZZZ_BitCount(row2) == map.width - 1)
                                {
                                    t3_value += 2;
                                }
                            }
                            int row3_check = ((row3 >> x) & 15);
                            if (row3_check == 8 || row3_check == 0)
                            {
                                t3_value += !!row3_check;
                                int row4_check = ((row4 >> x) & 15);
                                if (row4_check == 4 || row4_check == 12)
                                {
                                    t3_value += 1;
                                }
                                else
                                {
                                    t3_value -= 2;
                                }
                            }
                            else
                            {
                                t3_value = 0;
                            }
                        }
                    }
                    result.t3_value += t3_value;
                    if (t3_value > 3)
                    {
                        finding3 = false;
                    }
                }
                if (((row0 >> x) & 15) == 13 && ((row1 >> x) & 15) == 9)
                {
                    int t3_value = 0;
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        t3_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 2)
                        {
                            t3_value += 1;
                            if (((row2 >> x) & 15) == 13)
                            {
                                t3_value += 2;
                                if (ZZZ_BitCount(row2) == map.width - 1)
                                {
                                    t3_value += 2;
                                }
                            }
                            int row3_check = ((row3 >> x) & 15);
                            if (row3_check == 1 || row3_check == 0)
                            {
                                t3_value += !!row3_check;
                                int row4_check = ((row4 >> x) & 15);
                                if (row4_check == 3 || row4_check == 1)
                                {
                                    t3_value += 1;
                                }
                                else
                                {
                                    t3_value -= 2;
                                }
                            }
                            else
                            {
                                t3_value = 0;
                            }
                        }
                    }
                    result.t3_value += t3_value;
                    if (t3_value > 3)
                    {
                        finding3 = false;
                    }
                }
            }
        }
        return result;
    }

    TOJ_v08::Status TOJ_v08::get(TetrisNodeEx& node, Result const& eval_result, size_t depth, Status const& status, TetrisContext::Env const& env) const
    {
        Status result = status;
        if (eval_result.clear > 0 && node.is_check && node.is_last_rotate)
        {
            if (eval_result.clear == 1 && node.is_mini_ready)
            {
                node.type = TSpinType::TSpinMini;
            }
            else if (node.is_ready)
            {
                node.type = TSpinType::TSpin;
            }
            else
            {
                node.type = TSpinType::None;
            }
        }
        auto& p = config_->param;
        result.value = eval_result.value;
        int safe = node->row >= 20 ? -1 : env.length > 0 ? get_safe(*eval_result.map, *env.next) : eval_result.map->roof;
        switch (eval_result.clear)
        {
        case 0:
            result.combo = 0;
            if (status.under_attack > 0)
            {
                result.map_rise += std::max(0, int(status.under_attack) - status.attack);
                result.under_attack = 0;
            }
            result.like += (node->status.t == 'I') * p.waste_i;
            result.like += (node->status.t == 'T') * p.waste_t;
            break;
        case 1:
            if (node.type == TSpinType::TSpinMini)
            {
                result.like += p.tspin_mini;
                result.attack += status.b2b ? 2 : 1;
            }
            else if (node.type == TSpinType::TSpin)
            {
                result.like += p.tspin_1;
                result.attack += status.b2b ? 3 : 2;
            }
            else
            {
                result.like += (node->status.t == 'I') * p.waste_i;
                result.like += (node->status.t == 'T') * p.waste_t;
                result.like += p.clear_1;
            }
            ++result.combo;
            result.b2b = node.type != TSpinType::None;
            break;
        case 2:
            if (node.type != TSpinType::None)
            {
                result.like += p.tspin_2;
                result.attack += status.b2b ? 5 : 4;
            }
            else
            {
                ++result.attack;
                result.like += p.clear_2;
            }
            ++result.combo;
            result.b2b = node.type != TSpinType::None;
            break;
        case 3:
            if (node.type != TSpinType::None)
            {
                result.like += p.tspin_3;
                result.attack += status.b2b ? 8 : 6;
            }
            else
            {
                result.attack += 2;
                result.like += p.clear_3;
            }
            ++result.combo;
            result.b2b = node.type != TSpinType::None;
            break;
        case 4:
            result.like += p.clear_4;
            result.attack += status.b2b ? 5 : 4;
            ++result.combo;
            result.b2b = true;
            break;
        }
        safe += eval_result.clear - result.map_rise;
        if (safe <= 0)
        {
            result.death = 1;
        }
        if (eval_result.count == 0 && result.map_rise == 0)
        {
            result.like += 999;
            result.attack += 6;
        }
        size_t t_expect = [=]()->int
        {
            if (env.hold == 'T')
            {
                return 0;
            }
            for (size_t i = 0; i < env.length; ++i)
            {
                if (env.next[i] == 'T')
                {
                    return i;
                }
            }
            return 14;
        }();
        switch (env.hold)
        {
        case 'T':
            if (node.type == TSpinType::None)
            {
                result.like += p.hold_t;
            }
            break;
        case 'I':
            if (eval_result.clear != 4)
            {
                result.like += p.hold_i;
            }
            break;
        }
        double rate = (1. / (depth + 1)) + 3;
        result.combo_attack += config_->table[std::min<int>(config_->table_max - 1, result.combo)];
        result.max_combo = std::max(result.combo, result.max_combo);
        result.max_attack = std::max(result.attack, result.max_attack);
        result.value += ((0.
            + result.max_attack * p.max_attack
            + result.attack * p.attack * rate
            + eval_result.t2_value * (t_expect < 8 ? 512 : 320) * p.t2_slot
            + (safe >= 12 ? static_cast<double>(eval_result.t3_value) * (t_expect < 4 ? 10 : 8) * (result.b2b ? 512 : 256) / (6 + result.under_attack) : 0) * p.t3_slot
            + result.b2b * p.b2b
            + result.like * 64
            ) * std::max<double>(0.05, (full_count_ - eval_result.count - result.map_rise * (context_->width() - 1)) / double(full_count_))
            + result.max_combo * (result.max_combo - 1) * result.combo_attack * p.combo
            - result.death * 999999999.0
            );
        return result;
    }

    size_t TOJ_v08::map_in_danger_(m_tetris::TetrisMap const& map, size_t t, size_t up) const
    {
        if (up >= 20)
        {
            return 1;
        }
        size_t height = 22 - up;
        return map_danger_data_[t].data[0] & map.row[height - 4] | map_danger_data_[t].data[1] & map.row[height - 3] | map_danger_data_[t].data[2] & map.row[height - 2] | map_danger_data_[t].data[3] & map.row[height - 1];
    }

    bool IO::Status::operator<(Status const &other) const
    {
        return value < other.value;
    }

    int8_t IO::get_safe(m_tetris::TetrisMap const &m, char t) const
    {
        int safe = 0;
        while (map_in_danger_(m, context_->convert(t), safe + 1) == 0)
        {
            ++safe;
        }
        return safe;
    }

    std::string IO::ai_name() const
    {
        return "ZZZ TETR.IO v0.8";
    }

    void IO::init(m_tetris::TetrisContext const *context, Config const *config)
    {
        context_ = context;
        config_ = config;
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
        full_count_ = context->width() * 24;
        map_danger_data_.resize(context->type_max());
        for (size_t i = 0; i < context->type_max(); ++i)
        {
            TetrisMap map(context->width(), context->height());
            TetrisNode const *node = context->generate(i);
            node->attach(context, map);
            std::memcpy(map_danger_data_[i].data, &map.row[18], sizeof map_danger_data_[i].data);
            for (int y = 0; y < 3; ++y)
            {
                map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
            }
        }
    }
    IO::Result IO::eval(TetrisNodeEx const &node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const
    {
        const int width_m1 = map.width - 1;
        int ColTrans = 2 * (map.height - map.roof);
        int RowTrans = map.roof == map.height ? 0 : map.width;
        for (int y = 0; y < map.roof; ++y)
        {
            if (!map.full(0, y))
            {
                ++ColTrans;
            }
            if (!map.full(width_m1, y))
            {
                ++ColTrans;
            }
            ColTrans += ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
            }
        }
        RowTrans += ZZZ_BitCount(row_mask_ & ~map.row[0]);
        RowTrans += ZZZ_BitCount(map.roof == map.height ? row_mask_ & ~map.row[map.roof - 1] : map.row[map.roof - 1]);
        struct
        {
            int HoleCount;
            int HoleLine;

            int HoleDepth;
            int WellDepth;

            int HoleNum[32];
            int WellNum[32];

            int LineCoverBits;
            int HolePosyIndex;
        } v;
        std::memset(&v, 0, sizeof v);
        struct
        {
            int ClearWidth;
        } a[40];

        for (int y = map.roof - 1; y >= 0; --y)
        {
            v.LineCoverBits |= map.row[y];
            int LineHole = v.LineCoverBits ^ map.row[y];
            if (LineHole != 0)
            {
                ++v.HoleLine;
                a[v.HolePosyIndex].ClearWidth = 0;
                for (int hy = y + 1; hy < map.roof; ++hy)
                {
                    uint32_t CheckLine = LineHole & map.row[hy];
                    if (CheckLine == 0)
                    {
                        break;
                    }
                    a[v.HolePosyIndex].ClearWidth += (hy + 1) * ZZZ_BitCount(CheckLine);
                }
                ++v.HolePosyIndex;
            }
            for (int x = 1; x < width_m1; ++x)
            {
                if ((LineHole >> x) & 1)
                {
                    v.HoleDepth += ++v.HoleNum[x];
                }
                else
                {
                    v.HoleNum[x] = 0;
                }
                if (((v.LineCoverBits >> (x - 1)) & 7) == 5)
                {
                    v.WellDepth += ++v.WellNum[x];
                }
            }
            if (LineHole & 1)
            {
                v.HoleDepth += ++v.HoleNum[0];
            }
            else
            {
                v.HoleNum[0] = 0;
            }
            if ((v.LineCoverBits & 3) == 2)
            {
                v.WellDepth += ++v.WellNum[0];
            }
            if ((LineHole >> width_m1) & 1)
            {
                v.HoleDepth += ++v.HoleNum[width_m1];
            }
            else
            {
                v.HoleNum[width_m1] = 0;
            }
            if (((v.LineCoverBits >> (width_m1 - 1)) & 3) == 1)
            {
                v.WellDepth += ++v.WellNum[width_m1];
            }
        }
        auto &p = config_->param;
        Result result;
        result.value = (0. - map.roof * p.roof - ColTrans * p.col_trans - RowTrans * p.row_trans - v.HoleCount * p.hole_count - v.HoleLine * p.hole_line - v.WellDepth * p.well_depth - v.HoleDepth * p.hole_depth);
        double rate = 32, mul = 1.0 / 4;
        for (int i = 0; i < v.HolePosyIndex; ++i, rate *= mul)
        {
            result.value -= a[i].ClearWidth * rate;
        }
        result.count = map.count + v.HoleCount;
        result.clear = clear;
        result.t2_value = 0;
        result.t3_value = 0;
        result.map = &map;
        bool finding2 = true;
        bool finding3 = true;
        for (int y = 0; (finding2 || finding3) && y < map.roof - 2; ++y)
        {
            int row0 = map.row[y];
            int row1 = map.row[y + 1];
            int row2 = y + 2 < map.height ? map.row[y + 2] : 0;
            int row3 = y + 3 < map.height ? map.row[y + 3] : 0;
            int row4 = y + 4 < map.height ? map.row[y + 4] : 0;
            for (int x = 0; finding2 && x < map.width - 2; ++x)
            {
                if (((row0 >> x) & 7) == 5 && ((row1 >> x) & 7) == 0)
                {
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        result.t2_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 3)
                        {
                            result.t2_value += 2;
                            int row2_check = (row2 >> x) & 7;
                            if (row2_check == 1 || row2_check == 4)
                            {
                                result.t2_value += 2;
                            }
                            finding2 = false;
                        }
                    }
                }
            }
            for (int x = 0; finding3 && x < map.width - 3; ++x)
            {
                if (((row0 >> x) & 15) == 11 && ((row1 >> x) & 15) == 9)
                {
                    int t3_value = 0;
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        t3_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 2)
                        {
                            t3_value += 1;
                            if (((row2 >> x) & 15) == 11)
                            {
                                t3_value += 2;
                                if (ZZZ_BitCount(row2) == map.width - 1)
                                {
                                    t3_value += 2;
                                }
                            }
                            int row3_check = ((row3 >> x) & 15);
                            if (row3_check == 8 || row3_check == 0)
                            {
                                t3_value += !!row3_check;
                                int row4_check = ((row4 >> x) & 15);
                                if (row4_check == 4 || row4_check == 12)
                                {
                                    t3_value += 1;
                                }
                                else
                                {
                                    t3_value -= 2;
                                }
                            }
                            else
                            {
                                t3_value = 0;
                            }
                        }
                    }
                    result.t3_value += t3_value;
                    if (t3_value > 3)
                    {
                        finding3 = false;
                    }
                }
                if (((row0 >> x) & 15) == 13 && ((row1 >> x) & 15) == 9)
                {
                    int t3_value = 0;
                    if (ZZZ_BitCount(row0) == map.width - 1)
                    {
                        t3_value += 1;
                        if (ZZZ_BitCount(row1) == map.width - 2)
                        {
                            t3_value += 1;
                            if (((row2 >> x) & 15) == 13)
                            {
                                t3_value += 2;
                                if (ZZZ_BitCount(row2) == map.width - 1)
                                {
                                    t3_value += 2;
                                }
                            }
                            int row3_check = ((row3 >> x) & 15);
                            if (row3_check == 1 || row3_check == 0)
                            {
                                t3_value += !!row3_check;
                                int row4_check = ((row4 >> x) & 15);
                                if (row4_check == 3 || row4_check == 1)
                                {
                                    t3_value += 1;
                                }
                                else
                                {
                                    t3_value -= 2;
                                }
                            }
                            else
                            {
                                t3_value = 0;
                            }
                        }
                    }
                    result.t3_value += t3_value;
                    if (t3_value > 3)
                    {
                        finding3 = false;
                    }
                }
            }
        }
        result.lockout = node->row >= 20;
        return result;
    }

    // TowerTris：满 Spin（非 Mini）的攻击值。
    //   默认：Spin 伤害走表 = 行数 × 2（与游戏 spin_damage_table 的满 Spin 档一致）
    //   Allspin_5：游戏把非 Mini 的 Spin 伤害**替换**成 行数 × 3（_calculate_damage 812 行），
    //              而最终攻击 = base_damage_table[行数] + spin_damage，所以这里连基础伤害一起算。
    static int spin_attack_of(int clear, ai_zzz::IO::Config const *config)
    {
        const int base = (clear >= 4) ? 4 : (clear == 3) ? 2 : (clear == 2) ? 1 : 0;
        if (config != nullptr && config->allspin_mode >= 5)
            return base + clear * 3;
        return clear * ((config != nullptr) ? config->spin_damage_mul : 2);
    }

    IO::Status IO::get(TetrisNodeEx &node, Result const &eval_result, size_t depth, Status const &status, TetrisContext::Env const &env) const
    {
        if (eval_result.clear > 0 && node.is_check && node.is_last_rotate)
        {
            // TowerTris：no_spin==2 时游戏把所有 Spin 降级为 Mini（含 T-Spin），
            // 这里同步降级，保证类型上报与 mini 伤害口径一致。
            if (node.is_mini_ready || (config_->spin_force_mini && node.is_ready))
            {
                node.type = ASpinType::TSpinMini;
            }
            else if (node.is_ready)
            {
                node.type = ASpinType::TSpin;
            }
        }
        Status result = status;
        result.value = eval_result.value;
        auto &p = config_->param;
        // T 的 Spin0（只转不消）：上面给 T-Spin 赋类型的前提是 clear > 0，
        // 所以 Spin0 的 T 需要在这里单独判一次（is_ready 由 search 保证「角就位且四向不可移动」）。
        // 用途：NoSpin4 的死亡惩罚、Allspin_2 的 Spin0 续 BTB。
        const bool t_spin0 = (eval_result.clear == 0 && node.is_check && node.is_last_rotate
                              && (node.is_ready || node.is_mini_ready));
        int safe = node->row >= 20 ? -1 : env.length > 0 ? get_safe(*eval_result.map, *env.next)
                                                         : eval_result.map->roof;
        int curAtk = 0;
        int baseAtk = 0;
        // no_spin==2（无天赋II）：游戏把全部 Spin 降级为 Mini，并按**基础伤害表**结算
        //（TetrisClearLine._calculate_damage 的 Mini 分支把 base_damage 置 0、spin_damage 取 base 表），
        // 即「Spin 与同消行数的普通消行完全等价」。因此本手下 Spin 的攻击也按普通消行算；
        // 类型仍保留 Mini 上报，供 Allspin 重复性惩罚的类型比较使用。
        const bool spin_as_clear = config_->spin_force_mini;

        // 本手是否「4消/Spin」：对应游戏 _calculate_damage() 里 BTB 加成的门控（只有 spin 或四消才吃加成）。
        // Spin0（有旋转、无消行）不续 BTB —— 与游戏 spin0_btb_enabled 默认 false 的规则一致，
        // 故这里不再拼接 season_2 的 Spin0 分支（season_2 是「不可移动即 T-Spin」的规则开关，与 BTB 无关）。
        bool is_b2b_move = eval_result.clear == 4 || (eval_result.clear && node.type != ASpinType::None);
        // Allspin_2（全旋II）：
        //   · 非 Spin 消行记 void → 不给任何伤害、且断开 BTB 链（连四消也算 void）
        //   · Spin0（有 Spin 判定、无消行）→ 使 BTB +1（游戏里 Allspin_2 强制 spin0_btb_enabled）
        // is_void_clear 就是「消行了但没判成 Spin」——与游戏 is_void_clear = (is_allspin2 and not is_spin) 一致。
        const bool allspin2 = config_->allspin2_mode;
        const bool spin0_like = (eval_result.clear == 0) && (node.type != ASpinType::None || t_spin0);
        const bool is_void_clear = allspin2 && eval_result.clear > 0 && node.type == ASpinType::None;
        if (is_void_clear)
        {
            is_b2b_move = false;   // void 消行断 BTB：既不触发加成也不续链（游戏 _update_btb(false)）
        }
        else if (allspin2 && spin0_like)
        {
            is_b2b_move = true;    // 全旋II：Spin0 使 BTB+1
        }

        auto get_attack = [&](const int &base_atk, int &combo, int &b2b)
        {
            ++combo;
            double atk = base_atk;
            int surge_atk = 0;
            // todo: detect garbage line
            // pre_b2b = 本手之前的连续 BTB 计数，对应游戏侧 _calculate_damage() 里的 btb_count
            // （游戏用「本手之前」的计数判定加成，故这里必须在 ++b2b 之前取值）。
            const int pre_b2b = b2b;
            if (is_b2b_move)
            {
                ++b2b;
            }
            else
            {
                // surge break 兑现：仅 surge break 系统，且断链前已连续 >= 4 手（与游戏一致：+pre_b2b）
                if (config_->btb_system == 1 && pre_b2b >= 4)
                {
                    surge_atk += pre_b2b;
                }
                b2b = 0;
            }
            // BTB 加成：只在「本手是 4消/Spin（is_b2b_move）」且「上一手也是 4消/Spin（pre_b2b >= 1）」时生效，
            // 与游戏 _get_btb_bonus() 的门控一致（普通消行即使链还在也不吃加成）。
            if (is_b2b_move && pre_b2b >= 1)
            {
                if (config_->btb_system == 2)
                {
                    // 累加奖励系统：BTB=1 → 1；BTB>=2 → raw = 1+ln(0.8*BTB+1)，
                    // a = floor(raw)、b = raw - a，加成 = a+(1+b)/3（游戏侧本手伤害取整）
                    if (pre_b2b == 1)
                    {
                        atk += 1;
                    }
                    else
                    {
                        const double raw = 1.0 + std::log1p(0.8 * pre_b2b);
                        const int integral = static_cast<int>(std::floor(raw));
                        const double frac = raw - integral;
                        atk += std::floor(integral + (1.0 + frac) / 3.0);
                    }
                }
                else
                {
                    // surge break 系统：第 2 手起 +1；btb_count >= 4 时按游戏档位加成：
                    //   默认 +1（修复：原先写死 +2，无 buff 时会高估伤害）；
                    //   Allspin>=2 → +2；Allspin>=4 → +3（数值由桥按 _get_btb_bonus() 规则下发）。
                    atk += (pre_b2b >= 4) ? config_->btb_bonus_high : 1;
                }
            }
            int combo_copy = combo - 1;
            atk *= (1 + 0.25 * combo_copy);
            // 塔的发送倍率：Allspin_5 里 Void 会把它累加（每次 +0.01），乘法作用于攻击
            atk *= (status.pressure_mult > 0.0 ? status.pressure_mult : 1.0);
            if (combo_copy > 1)
            {
                atk = std::max(log1p(1.25 * combo_copy), atk);
            }
            return static_cast<int>(floor((atk + surge_atk) * config_->multiplier));
        };
        switch (eval_result.clear)
        {
        case 0:
            result.board_fill += 4;
            result.combo = 0;
            if (status.under_attack > 0)
            {
                result.map_rise = status.under_attack > config_->garbage_cap ? config_->garbage_cap : status.under_attack;
                result.board_fill += status.under_attack > config_->garbage_cap ? 72 : status.under_attack * 9;
                result.like += (node->status.t == 'I') * p.waste_i;
                result.like += (node->status.t == 'T') * p.waste_t;
                result.under_attack = status.under_attack > config_->garbage_cap ? status.under_attack - config_->garbage_cap : 0;
            }
            break;
        case 1:
            if (!spin_as_clear && (node.type == ASpinType::ASpinMini || node.type == ASpinType::TSpinMini))
            {
                result.like += p.tspin_mini;
                baseAtk = 0;
            }
            else if (!spin_as_clear && node.type != ASpinType::None)
            {
                result.like += p.tspin_1;
                // 满 Spin 攻击 = 基础伤害 + Spin 伤害
                //   默认：Spin 伤害走表（引擎口径 行数×2）
                //   Allspin_5：非 Mini 的 Spin 伤害**替换**为 行数×3（游戏 _calculate_damage 812 行）
                baseAtk = spin_attack_of((int)eval_result.clear, config_);
            }
            else
            {
                result.like += (node->status.t == 'I') * p.waste_i;
                result.like += (node->status.t == 'T') * p.waste_t;
                result.like += p.clear_1;
                baseAtk = 0;
            }
            result.attack += curAtk = get_attack(baseAtk, result.combo, result.b2bcnt);
            break;
        case 2:
            if (!spin_as_clear && (node.type == ASpinType::ASpinMini || node.type == ASpinType::TSpinMini))
            {
                result.like += p.tspin_mini;
                baseAtk = 1;   // Mini 走基础伤害表：基础双消 = 1
            }
            else if (!spin_as_clear && node.type != ASpinType::None)
            {
                result.like += p.tspin_2;
                // 满 Spin 攻击同 case 1：Allspin_5 起改「基础 + 行数×3」
                baseAtk = spin_attack_of((int)eval_result.clear, config_);
            }
            else
            {
                result.like += (node->status.t == 'I') * p.waste_i;
                result.like += (node->status.t == 'T') * p.waste_t;
                result.like += p.clear_2;
                baseAtk = 1;
            }
            result.attack += curAtk = get_attack(baseAtk, result.combo, result.b2bcnt);
            break;
        case 3:
            if (!spin_as_clear && (node.type == ASpinType::ASpinMini || node.type == ASpinType::TSpinMini))
            {
                result.like += p.tspin_mini;
                baseAtk = 2;
            }
            else if (!spin_as_clear && node.type != ASpinType::None)
            {
                result.like += p.tspin_3;
                baseAtk = spin_attack_of((int)eval_result.clear, config_);
            }
            else
            {
                result.like += p.clear_3;
                baseAtk = 2;
            }
            result.attack += curAtk = get_attack(baseAtk, result.combo, result.b2bcnt);
            break;
        case 4:
            baseAtk = 4;
            result.attack += curAtk = get_attack(baseAtk, result.combo, result.b2bcnt);
            result.like += (result.combo + result.b2bcnt) * (1 + result.attack) * p.clear_4;
            break;
        }
        // TowerTris：Allspin_2（全旋II）——非 Spin 消行是 void：不产生任何攻击。
        // 游戏在 _calculate_damage() 之后再 damage = 0（连四消的 void 也一样），
        // 所以这里把本手攻击整个回滚（同时上面已把 is_b2b_move 置 false → BTB 断链）。
        if (is_void_clear && curAtk != 0)
        {
            result.attack -= curAtk;
            curAtk = 0;
        }
        // Allspin_5：Void 自己无攻击，但会给塔的发送倍率 +0.01（游戏 _add_void_pressure_bonus）。
        //   该倍率**乘法**作用于之后所有发出去的攻击，所以在搜索里携带给后续节点，
        //   由 get_attack 里 `atk *= status.pressure_mult` 体现（而不是给 Void 加奖励分）。
        if (is_void_clear && allspin2 && config_->allspin_mode >= 5)
        {
            result.pressure_mult = status.pressure_mult + 0.01;
        }
        // TowerTris：全旋加成（Allspin_2 下非 Spin 消行零收益，所以全旋价值由这里决定）。
        // 只对「非 T 的 Spin」生效（AllSpin / ASpinMini），数值由游戏 bot_allspin1/2/3/3plus 下发。
        if (allspin2 && eval_result.clear > 0
            && (node.type == ASpinType::AllSpin || node.type == ASpinType::ASpinMini))
        {
            if (eval_result.clear >= 4)
                result.like += config_->allspin_like_3plus;
            else if (eval_result.clear == 3)
                result.like += config_->allspin_like_3;
            else if (eval_result.clear == 2)
                result.like += config_->allspin_like_2;
            else
                result.like += config_->allspin_like_1;
        }
        // TowerTris：NoSpin4 的 Spin0 判定。
        // 游戏 TetrisClearLine 在两个地方调用 _apply_no_spin4_penalty()：
        //   (1) clear_count==0 且有 spin_type（即 Spin0，只转不消）
        //   (2) 消行的 Spin
        // 而上面的 T-Spin 类型赋值带 eval_result.clear > 0 条件，Spin0 的 node.type 恒为 None，
        // 只靠 node.type 会漏掉「T 的 Spin0」→ bot 可能选到它，被涨 20 行实心行直接判死。
        // 非 T 的全旋由 search 的 check_immobile 标记（不受 clear 影响），无需在这里补。
        // （t_spin0 已在函数开头算好：NoSpin4 与 Allspin_2 共用。）
        // TowerTris：NoSpin4（无天赋IV）惩罚——触发 Spin（**含 Spin0**）会立刻上涨实心行 = 必死，
        // 因此对任何被判为 Spin 的候选施加极大权重惩罚。放在 clear 分支之外，
        // 保证 case 0（只转不消）同样被覆盖。
        if (config_->spin_death_penalty > 0 && ((int)node.type != 0 || t_spin0))
        {
            if (t_spin0)
                ++g_spin0_penalty_count;
            result.like -= config_->spin_death_penalty;
            // 版面折算：NoSpin4 这一手会立刻上涨**实心**垃圾行（游戏 _apply_no_spin4_penalty
            // → add_solid_garbage(no_spin4_solid_rows, true)，不可消除、无视 cap）。
            // 同样是「无解」，所以走 death 而不是 map_rise（map_rise 会被当成以后能消掉的来垃圾）。
            const int n4_rows = config_->no_spin4_rows;
            if (n4_rows > 0)
            {
                result.board_fill += n4_rows * 9;
                result.death = 1;
            }
        }
        // TowerTris：Allspin 重复性惩罚 —— 与游戏 _allspin_repeat_result() 逐档对齐。
        //   mode 0/1：只看「行数 + 消行类型」（Allspin_1；0=未开时桥不发惩罚）
        //   mode 2  ：只看有效行数（普通=N / Spin0=0 / void=-1）
        //   mode 3  ：有效行数重复 **或** 与上一手消行同块类型
        //   mode 4/5：六块轮（Z/S/T/I/J/L 各一遍）内再消同一块 = 重复；4 取消行数重复；
        //             5 再把有效行数 0/1/2/3 做成独立一轮
        //   比较对象是**搜索内的历史** status.*（含轮掩码），随模拟推进 —— 否则深度>=2 时
        //   「上一手」永远停在真实上一手，搜索会规划出必被罚的连续重复。
        //   只在这两种情况下参与判定（与游戏调用点一致）：消了行、或 Spin0。
        const bool is_spin_move = (node.type != ASpinType::None) || t_spin0;
        const bool is_spin0_move = (eval_result.clear == 0) && is_spin_move;
        const int cfg_allspin_mode = config_->allspin_mode;
        // 游戏 _allspin_repeat_result 开头：**只有 Allspin_5** 的 Void 直接返回"不重复"
        //   （既不算重复、也不推进任何轮）；Allspin_2/3/4 的 Void 照常参与重复判定
        //   （有效行数记 -1，所以「void 接 void」(-1 == -1) 会命中）。
        //   伤害侧：void 一律归零（is_void_clear 分支已处理 → "void 不造成任何伤害"）。
        const bool repeat_check_applies = ((eval_result.clear > 0) || is_spin0_move)
            && !(is_void_clear && cfg_allspin_mode >= 5);
        const int cur_effective = is_void_clear ? -1 : (int)eval_result.clear;
        // 本手方块编号（Z/S/T/I/J/L → 0..5），用于 mode 3 / 4 / 5
        int cur_piece_code = -1;
        switch (node->status.t)
        {
        case 'Z': cur_piece_code = 0; break;
        case 'S': cur_piece_code = 1; break;
        case 'T': cur_piece_code = 2; break;
        case 'I': cur_piece_code = 3; break;
        case 'J': cur_piece_code = 4; break;
        case 'L': cur_piece_code = 5; break;
        default: break;
        }
        bool repeat_hit = false;
        int punish_rows = config_->allspin2_solid_rows;   // 默认 = 「与上一手重复」档（20 行实心）
        int punish_mode_solid = (cfg_allspin_mode >= 2) ? 1 : 0;   // 1 = 实心不可消（2/3/4/5 档）
        if (repeat_check_applies)
        {
            if (cfg_allspin_mode >= 4)
            {
                // (1) 类型轮：只有 spin 消行参与（void 不属于六块之一）→ 轮违规罚 allspin_round_solid_rows(42)
                if (is_spin_move && cur_piece_code >= 0
                    && ((status.round_types_mask >> cur_piece_code) & 1))
                {
                    repeat_hit = true;
                    punish_rows = config_->allspin_round_solid_rows;
                }
                // (2) 行数轮（仅 mode >= 5）：单轮 {0,1,2,3}（key_total = 4）——
                //     与游戏 ALLSPIN_ROUND_COUNTS = [0,1,2,3] 一致；4 行及以上不参与。
                if (!repeat_hit && cfg_allspin_mode >= 5
                    && cur_effective >= 0 && cur_effective <= 3
                    && ((status.round_counts_mask >> cur_effective) & 1) != 0)
                {
                    repeat_hit = true;
                    punish_rows = config_->allspin_round_solid_rows;
                }
                // (3) 4/5 档仍保留「与上一手重复」兜底档（行数相同 或 同块类型），罚 20
                if (!repeat_hit)
                {
                    const bool by_count = (status.hist_spin_type >= 0)
                        && (cur_effective == status.hist_clear_count);
                    const bool by_piece = (cur_piece_code >= 0)
                        && (cur_piece_code == status.hist_piece_code);
                    repeat_hit = by_count || by_piece;
                }
            }
            else if (cfg_allspin_mode == 3)
            {
                const bool by_count = (status.hist_spin_type >= 0)
                    && (cur_effective == status.hist_clear_count);
                const bool by_piece = (cur_piece_code >= 0)
                    && (cur_piece_code == status.hist_piece_code);
                repeat_hit = by_count || by_piece;
            }
            else
            {
                // mode 0/1/2：沿用有效行数比较；非 ≥2 档还要同类型
                const bool has_last_record = (status.hist_spin_type >= 0);
                repeat_hit = has_last_record && (cur_effective == status.hist_clear_count)
                    && (cfg_allspin_mode >= 2 || (int)node.type == status.hist_spin_type);
            }
        }
        if (config_->repeat_penalty > 0 && repeat_hit)
        {
            ++g_repeat_penalty_count;
            if (is_void_clear && status.hist_clear_count == -1)
                ++g_void_repeat_count;   // void 接 void（Allspin_2 特有）
            result.like -= config_->repeat_penalty;
            // 版面折算：这笔重复惩罚在游戏里是**立刻上涨垃圾**，预测版面必须跟着变，
            // 否则 bot 只在「本手」看到扣分，搜索后一层就当成没发生过。
            // ⚠ 结算方式分两类：
            //   Allspin_1：涨 1 行**普通**垃圾（可消）→ 用 map_rise（后续会被当作待消垃圾）
            //   2/3/4/5 ：涨 punish_rows 行**实心**垃圾（add_solid_garbage(rows, true)，
            //              不可消除、无视 garbage_cap）→ 只加版面填充 + 标记 death，绝不走 map_rise
            //              （走 map_rise 会被搜索当成「以后能消掉的来垃圾」，bot 会误以为有解）。
            //              行数按触发档位：轮违规 allspin_round_solid_rows(42)，「与上一手重复」20。
            if (punish_mode_solid)
            {
                if (punish_rows > 0)
                {
                    result.board_fill += punish_rows * 9;
                    result.death = 1;   // 不可消除的实心行 → 等同于死
                }
            }
            else
            {
                result.board_fill += 9;
                result.map_rise += 1;
            }
        }
        // 推进搜索内的「上一手消行」历史，供下一层使用（与游戏的记录规则一一对应）：
        //   · 消了行：Allspin_2 的 void 记（类型 void→0、行数 -1），其余记（节点 Spin 类型、行数）
        //   · Spin0：记（Spin 类型、0 行）
        //   · 其它（无消行且非 Spin0）：不动（游戏也不写记录）
        if (eval_result.clear > 0)
        {
            result.hist_spin_type = is_void_clear ? 0 : (int)node.type;
            result.hist_clear_count = is_void_clear ? -1 : (int)eval_result.clear;
            // void 消行在游戏里把落块件记成空串（对应 -1），其余记本次落块件
            result.hist_piece_code = is_void_clear ? -1 : cur_piece_code;
        }
        else if (is_spin0_move)
        {
            // T 的 Spin0 在引擎里 node.type 是 None（类型赋值带 clear > 0 条件），这里补回真实类型
            result.hist_spin_type = (node.type != ASpinType::None)
                ? (int)node.type
                : (node.is_mini_ready ? (int)ASpinType::TSpinMini : (int)ASpinType::TSpin);
            result.hist_clear_count = 0;
            result.hist_piece_code = cur_piece_code;
        }
        // Allspin_4/5 的「轮」推进：与游戏 _allspin_round_step 同一语义
        //   （命中 → 本轮重置为「只剩本手」；未命中 → 记入本轮；集满 key_total 个 → 清空开新一轮）
        if (cfg_allspin_mode >= 4 && repeat_check_applies)
        {
            auto round_step = [](int &mask, int key, int key_total) -> bool {
                if (((mask >> key) & 1) != 0)
                {
                    mask = 1 << key;
                    return true;
                }
                mask |= 1 << key;
                // 计数只看有效位（类型轮 0..5、行数轮 1..3），故直接统计所有已置位
                int used = 0;
                for (int m = mask; m != 0; m &= (m - 1))
                    ++used;
                if (used >= key_total)
                    mask = 0;
                return false;
            };
            if (is_spin_move && cur_piece_code >= 0)
                round_step(result.round_types_mask, cur_piece_code, 6);
            // Allspin_5 行数轮：单轮 {0,1,2,3}（key_total = 4），与游戏 ALLSPIN_ROUND_COUNTS 一致
            if (cfg_allspin_mode >= 5 && cur_effective >= 0 && cur_effective <= 3)
                round_step(result.round_counts_mask, cur_effective, 4);
        }
        result.board_fill -= (eval_result.clear * 10) - 4;
        if (eval_result.count == 0 && result.map_rise == 0)
        {
            if (!result.pc)
            {
                result.death = 1;
            }
            result.attack += curAtk += config_->pc_damage;
        }
        if (config_->is_margin)
            result.attack += (int)std::floor((((clock() - config_->start_count) / 1000.0) * GARBAGE_INCREASE) * curAtk);
        size_t t_expect = [=]() -> int
        {
            if (env.hold == 'T')
            {
                return 0;
            }
            for (size_t i = 0; i < env.length; ++i)
            {
                if (env.next[i] == 'T')
                {
                    return i;
                }
            }
            return 13;
        }();
        switch (env.hold)
        {
        case 'T':
            if (node.type == ASpinType::None)
            {
                result.like += p.hold_t;
            }
            break;
        case 'I':
            if (eval_result.clear != 4)
            {
                result.like += p.hold_i;
            }
            break;
        }
        safe -= result.map_rise;
        if (safe <= 0 || (config_->lockout && eval_result.lockout))
            result.death = 1;
        while (result.under_attack && result.attack) {
            --result.under_attack;
            --result.attack;
        }
        result.board_fill_diff = int(std::max(0, result.board_fill - result.board_fill_prev));
        double rate = (1. / (depth + 1)) + 3;
        int mul = config_->season_2 + 1;
        result.like += result.attack;
        result.max_combo = std::max(result.combo, result.max_combo);
        result.value += ((0.
            + ((result.attack * 256 * rate * p.attack)
                + eval_result.t2_value * (t_expect < 4 ? (3 - t_expect) * 256 : 128) * p.t2_slot
                + eval_result.t3_value * (t_expect < 2 ? 64 : 32) * p.t3_slot)
            + (is_b2b_move * curAtk * 8 * mul  * (22 - eval_result.map->roof))
            + (p.b2b * std::min(5, result.b2bcnt) * 8 * mul)
            + (result.like * 32))
            * std::max<double>(0.05, (full_count_ - eval_result.count - (result.map_rise * (context_->width() - 1))) / double(full_count_))
            + (result.max_combo * (result.max_combo - 1) * (curAtk * (status.b2bcnt <= result.b2bcnt)) *p.combo)
            - result.death * 999999999.0);
        result.board_fill_prev = result.board_fill;
        return result;
    }

    size_t IO::map_in_danger_(m_tetris::TetrisMap const& map, size_t t, size_t up) const
    {
        if (up >= 20)
        {
            return 1;
        }
        size_t height = 22 - up;
        return map_danger_data_[t].data[0] & map.row[height - 4] | map_danger_data_[t].data[1] & map.row[height - 3] | map_danger_data_[t].data[2] & map.row[height - 2] | map_danger_data_[t].data[3] & map.row[height - 1];
    }

    bool C2::Status::operator < (Status const& other) const
    {
        return value < other.value;
    }


    void C2::init(m_tetris::TetrisContext const* context, Config const* config)
    {
        context_ = context;
        config_ = config;
        map_danger_data_.resize(context->type_max());
        for (size_t i = 0; i < context->type_max(); ++i)
        {
            TetrisMap map(context->width(), context->height());
            TetrisNode const* node = context->generate(i);
            node->move_down->attach(context, map);
            std::memcpy(map_danger_data_[i].data, &map.row[map.height - 4], sizeof map_danger_data_[i].data);
            for (int y = 0; y < 3; ++y)
            {
                map_danger_data_[i].data[y + 1] |= map_danger_data_[i].data[y];
            }
        }
        col_mask_ = context->full() & ~1;
        row_mask_ = context->full();
    }

    std::string C2::ai_name() const
    {
        return "C2 v0.1";
    }

    C2::Result C2::eval(TetrisNode const* node, TetrisMap const& map, TetrisMap const& src_map, size_t clear) const
    {
        const int width_m1 = map.width - 1;
        size_t ColTrans = 2 * (map.height - map.roof);
        size_t RowTrans = map.roof == map.height ? 0 : map.width;
        for (int y = 0; y < map.roof; ++y)
        {
            ColTrans += !map.full(0, y) + !map.full(width_m1, y) + ZZZ_BitCount((map.row[y] ^ (map.row[y] << 1)) & col_mask_);
            if (y != 0)
            {
                RowTrans += ZZZ_BitCount(map.row[y - 1] ^ map.row[y]);
            }
        }
        RowTrans += ZZZ_BitCount(row_mask_ & ~map.row[0]);
        RowTrans += ZZZ_BitCount(map.roof == map.height ? row_mask_ & ~map.row[map.roof - 1] : map.row[map.roof - 1]);
        struct
        {
            int HoleCountSrc;
            int HoleCount;
            int HoleLine;

            int WideWellDepth[6];
            double HoleDepth;
            double WellDepth;

            int HoleNum[32];
            int WellNum[32];

            int LineCoverBits;
            int HolePosyIndex;
        } v;
        std::memset(&v, 0, sizeof v);
        struct
        {
            double ClearWidth;
        } a[40];

        for (int y = map.roof - 1; y >= 0; --y)
        {
            v.LineCoverBits |= map.row[y];
            int LineHole = v.LineCoverBits ^ map.row[y];
            if (LineHole != 0)
            {
                ++v.HoleLine;
                a[v.HolePosyIndex].ClearWidth = 0;
                for (int hy = y + 1; hy < map.roof; ++hy)
                {
                    uint32_t CheckLine = LineHole & map.row[hy];
                    if (CheckLine == 0)
                    {
                        break;
                    }
                    a[v.HolePosyIndex].ClearWidth += (hy + 1 + config_->p[0]) * config_->p[1] * ZZZ_BitCount(CheckLine);
                }
                ++v.HolePosyIndex;
            }
            for (int x = 1; x < width_m1; ++x)
            {
                if ((LineHole >> x) & 1)
                {
                    v.HoleDepth += (++v.HoleNum[x] + config_->p[4]) * config_->p[5];
                }
                else
                {
                    v.HoleNum[x] = 0;
                }
                if (((v.LineCoverBits >> (x - 1)) & 7) == 5)
                {
                    v.WellDepth += (++v.WellNum[x] + config_->p[2]) * config_->p[3];
                }
            }
            if (LineHole & 1)
            {
                v.HoleDepth += (++v.HoleNum[0] + config_->p[4]) * config_->p[5];
            }
            else
            {
                v.HoleNum[0] = 0;
            }
            if ((v.LineCoverBits & 3) == 2)
            {
                v.WellDepth += (++v.WellNum[0] + config_->p[2]) * config_->p[3];
            }
            if ((LineHole >> width_m1) & 1)
            {
                v.HoleDepth += (++v.HoleNum[width_m1] + config_->p[4]) * config_->p[5];
            }
            else
            {
                v.HoleNum[width_m1] = 0;
            }
            if (((v.LineCoverBits >> (width_m1 - 1)) & 3) == 1)
            {
                v.WellDepth += (++v.WellNum[width_m1] + config_->p[2]) * config_->p[3];
            }
            int WellWidth = 0;
            int MaxWellWidth = 0;
            for (int x = 0; x < map.width; ++x)
            {
                if ((v.LineCoverBits >> x) & 1)
                {
                    if (WellWidth > MaxWellWidth)
                    {
                        MaxWellWidth = WellWidth;
                    }
                    WellWidth = 0;
                }
                else
                {
                    ++WellWidth;
                }
            }
            if (WellWidth > MaxWellWidth)
            {
                MaxWellWidth = WellWidth;
            }
            if (MaxWellWidth >= 1 && MaxWellWidth <= 6)
            {
                if (ZZZ_BitCount(map.row[y]) + MaxWellWidth == map.width)
                {
                    v.WideWellDepth[MaxWellWidth - 1] += 2;
                }
                else
                {
                    v.WideWellDepth[MaxWellWidth - 1] -= 1;
                }
            }
        }
        for (int x = 0; x < map.width; ++x)
        {
            v.HoleCountSrc += src_map.top[x];
            v.HoleCount += map.top[x];
        }
        v.HoleCountSrc -= src_map.count;
        v.HoleCount -= map.count;

        double BoardDeadZone = map_in_danger_(map);
        if (map.roof == map.height)
        {
            BoardDeadZone += 70;
        }

        Result result;
        result.map = (0.
            - (map.roof + config_->p[6]) * config_->p[7]
            - (ColTrans + config_->p[8]) * config_->p[9]
            - (RowTrans + config_->p[10]) * config_->p[11]
            - (v.HoleCount + config_->p[12]) * config_->p[13]
            - (v.HoleLine + config_->p[14]) * config_->p[15]
            - (v.WellDepth + config_->p[16]) * config_->p[17]
            - (v.HoleDepth + config_->p[18]) * config_->p[19]
            - (BoardDeadZone + config_->p[20]) * config_->p[21]
            );
        double rate = config_->p[22], mul = config_->p[23];
        for (int i = 0; i < v.HolePosyIndex; ++i, rate *= mul)
        {
            result.map -= a[i].ClearWidth * rate;
        }
        result.map *= config_->p_rate;
        if (config_->mode == 0)
        {
            int attack_well = std::min(4, v.WideWellDepth[0]);
            result.attack = (0.
                + v.WideWellDepth[5] * 2.4
                + v.WideWellDepth[4] * 3.6
                + v.WideWellDepth[3] * 7.2
                + v.WideWellDepth[2] * 9.6
                + v.WideWellDepth[1] * -20
                + ((attack_well * attack_well) + config_->p[16]) * config_->p[17] * config_->p_rate
                );
        }
        result.clear = clear;
        result.fill = float(map.count) / (map.width * (map.height - config_->safe));
        result.hole = float(v.HoleCountSrc) / (map.height - config_->safe);
        result.new_hole = v.HoleCount > v.HoleCountSrc ? float(v.HoleCount - v.HoleCountSrc) / map.height : 0;
        result.soft_drop = !node->open(src_map);
        return result;
    }

    C2::Status C2::get(m_tetris::TetrisNode const* node, Result const& eval_result, size_t depth, Status const& status, TetrisContext::Env const& env) const
    {
        Status result;
        result.attack = 0;
        result.combo = status.combo;
        result.combo_limit = status.combo_limit > 0 ? status.combo_limit - 1 : 0;
        result.value = eval_result.map;
        if (config_->mode == 0)
        {
            if (result.combo_limit == 0)
            {
                result.combo = 0;
            }
            if (result.combo_limit < 6 && result.combo < 3)
            {
                result.combo = 0;
            }
            static const float table[][5] =
            {
                //{     0,  3656,  4875,  6094,  7313},
                //{   400,  1728,  2338,  2947,  3556},
                //{   800,   707,  1009,  1312,  1614},
                //{  1600,   238,   417,   596,   775},
                //{  3200,   -41,    78,   198,   318},
                //{  6400,  -241,  -155,   -69,    17},
                //{ 12800,  -403,  -338,  -272,  -206},
                //{ 25600,  -544,  -493,  -441,  -389},
                //{ 51200,  -673,  -631,  -589,  -547},
                //{102400,  -794,  -759,  -724,  -689},
                //{204800,  -910,  -881,  -851,  -821},
                //{409600, -1023,  -997,  -971,  -946},
                //{819200, -1133, -1110, -1088, -1065},
                //{819200, -1241, -1221, -1201, -1181},
                //{819200, -1347, -1330, -1312, -1294},
                //{819200, -1453, -1437, -1421, -1405},
                //{819200, -1557, -1543, -1529, -1514},
                //{819200, -1661, -1648, -1635, -1622},
                //{819200, -1764, -1753, -1741, -1729},
                //{819200, -1867, -1857, -1846, -1835},
                {    0, -3000, 3000, 4000, 5000},
                {  500,   500, 1000, 1000, 2000},
                { 1000,  1000,  500,  500,  500},
                { 2000,  2000, 1000, 1000, 1000},
                { 4000,  4000, 2000, 2000, 2000},
                { 6000,  6000, 3000, 3000, 2500},
                { 8000,  8000, 4000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
                {10000, 10000, 5000, 3333, 2500},
            };
            double fill = eval_result.fill + (config_->danger ? 0.32 : 0);
            double hole = eval_result.hole + (config_->danger ? 0.16 : 0);
            double upstack = std::max<double>(0, 1 - hole * 3.3) * std::max<double>(0, 1 - (fill < 0.4 ? 0 : fill - 0.4) * 4);
            double downstack;
            double length_ratio = (1 << ((env.node != ' ') + env.length)) * 0.5;
            if (status.combo == 0)
            {
                downstack = std::max<double>(0.2, 1 - hole * 3.3) * std::max<double>(0.2, 1 - std::abs(fill - 0.48) * 5);
                result.attack -= 32000 * eval_result.new_hole;
                result.attack += eval_result.attack * upstack;
            }
            else
            {
                downstack = std::max<double>(0.2, 1 - hole * 3.3) * std::max<double>(0.2, 1 - fill * 1.2);
            }
            if (eval_result.clear > 0)
            {
                if (status.combo == 0)
                {
                    result.attack -= 8000 * upstack;
                    result.attack += table[status.combo][eval_result.clear] * downstack;
                }
                else
                {
                    result.attack += table[status.combo][eval_result.clear] * downstack * length_ratio;
                }
                result.combo = std::min<size_t>(16, result.combo + 1);
            }
            else if (status.combo > 0)
            {
                result.attack -= table[status.combo][0] * downstack * length_ratio;
            }
            result.attack += status.attack;
        }
        result.map = status.map + eval_result.map;
        if (eval_result.soft_drop && !config_->soft_drop)
        {
            result.map -= 9999999999;
        }
        result.value = result.attack + result.map;
        return result;
    }

    C2::Status C2::iterate(Status const** status, size_t status_length) const
    {
        Status result;
        result.combo = 0;
        result.value = 0;
        result.combo_limit = 0;
        static constexpr double max_val = 1e20;
        double
            lower1 = +max_val,
            lower2 = +max_val,
            lower3 = +max_val;
        for (size_t i = 0; i < status_length; ++i)
        {
            double v = status[i] == nullptr ? -max_val : status[i]->value;
            result.value += v;
            if (v < lower1)
            {
                if (lower1 < lower2)
                {
                    if (lower2 < lower3)
                    {
                        lower3 = lower2;
                    }
                    lower2 = lower1;
                }
                lower1 = v;
            }
            else if (v < lower2)
            {
                if (lower2 < lower3)
                {
                    lower3 = lower2;
                }
                lower2 = v;
            }
            else if (v < lower3)
            {
                lower3 = v;
            }
        }
        result.value = (result.value - lower1 - lower2 - lower3) / 4;
        //double
        //    upper1 = -max_val,
        //    upper2 = -max_val,
        //    upper3 = -max_val;
        //for (size_t i = 0; i < status_length; ++i)
        //{
        //    double v = status[i] == nullptr ? -max_val : status[i]->value;
        //    result.value += v;
        //    if (v > upper1)
        //    {
        //        if (upper1 > upper2)
        //        {
        //            if (upper2 > upper3)
        //            {
        //                upper3 = upper2;
        //            }
        //            upper2 = upper1;
        //        }
        //        upper1 = v;
        //    }
        //    else if (v > upper2)
        //    {
        //        if (upper2 > upper3)
        //        {
        //            upper3 = upper2;
        //        }
        //        upper2 = v;
        //    }
        //    else if (v > upper3)
        //    {
        //        upper3 = v;
        //    }
        //}
        //result.value = (upper1 + upper2 + upper3) / 3;
        return result;
    }

    size_t C2::map_in_danger_(m_tetris::TetrisMap const& map) const
    {
        size_t danger = 0;
        for (size_t i = 0; i < context_->type_max(); ++i)
        {
            if (map_danger_data_[i].data[0] & map.row[map.height - 4] || map_danger_data_[i].data[1] & map.row[map.height - 3] || map_danger_data_[i].data[2] & map.row[map.height - 2] || map_danger_data_[i].data[3] & map.row[map.height - 1])
            {
                ++danger;
            }
        }
        if (map.row[17] != 0)
        {
            ++danger;
        }
        return danger;
    }
}
