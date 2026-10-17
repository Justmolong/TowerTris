
#include "tetris_core.h"
#include "search_tspin.h"
#include "search_amini.h"
#include <array>

namespace ai_zzz
{
    namespace qq
    {
        class Attack
        {
        public:
            struct Config
            {
                size_t level;
                int mode;
            };
            struct Result
            {
                double land_point, map;
                size_t clear;
                int danger;
            };
            struct Status
            {
                double land_point;
                double attack;
                double rubbish;
                double value;
                bool operator<(Status const &) const;
            };

        public:
            void init(m_tetris::TetrisContext const *context, Config const *config);
            std::string ai_name() const;
            Result eval(m_tetris::TetrisNode const *node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
            Status get(m_tetris::TetrisNode const *node, Result const &eval_result, size_t depth, Status const &status) const;

        private:
            uint32_t check_line_1_[32];
            uint32_t check_line_2_[32];
            uint32_t *check_line_1_end_;
            uint32_t *check_line_2_end_;
            Config const *config_;
            m_tetris::TetrisContext const *context_;
            int col_mask_, row_mask_;
            struct MapInDangerData
            {
                uint32_t data[4];
            };
            std::vector<MapInDangerData> map_danger_data_;
            size_t map_in_danger_(m_tetris::TetrisMap const &map) const;
        };
    }

    class Dig
    {
    public:
        struct Config
        {
            std::array<double, 100> p =
                {
                    0,
                    1,
                    0,
                    1,
                    0,
                    1,
                    0,
                    96,
                    0,
                    160,
                    0,
                    128,
                    0,
                    60,
                    0,
                    380,
                    0,
                    100,
                    0,
                    40,
                    0,
                    50000,
                    32,
                    0.25,
            };
        };
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        double eval(m_tetris::TetrisNode const *node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        double get(m_tetris::TetrisNode const *node, double const &eval_result) const;

    private:
        struct MapInDangerData
        {
            int data[4];
        };
        std::vector<MapInDangerData> map_danger_data_;
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        size_t map_in_danger_(m_tetris::TetrisMap const &map) const;
        int col_mask_, row_mask_;
    };

    class TOJ_PC
    {
    public:
        typedef search_tspin::Search::TSpinType TSpinType;
        typedef search_tspin::Search::TetrisNodeWithTSpinType TetrisNodeEx;
        struct Config
        {
            int const *table;
            int table_max;
        };
        struct Result
        {
            double value;
            int clear;
            int roof;
        };
        struct Status
        {
            int under_attack;
            int recv_attack;
            int attack;
            int like;
            int combo;
            bool b2b;
            bool pc;
            double value;
            bool operator<(Status const &) const;
        };

    public:
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        double ratio() const
        {
            return 0.5;
        }
        Result eval(TetrisNodeEx const &node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        Status get(TetrisNodeEx &node, Result const &eval_result, size_t depth, Status const &status) const;

    private:
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        int col_mask_, row_mask_;
    };

    class TOJ_v08
    {
    public:
        typedef search_tspin::Search::TSpinType TSpinType;
        typedef search_tspin::Search::TetrisNodeWithTSpinType TetrisNodeEx;
        struct Param
        {
            double roof = 160;
            double col_trans = 160;
            double row_trans = 160;
            double hole_count = 160;
            double hole_line = 160;
            double well_depth = 160;
            double hole_depth = 160;
            double b2b = 160;
            double attack = 256;
            double max_attack = 40;
            double hold_t = 4;
            double hold_i = 2;
            double waste_t = -0;
            double waste_i = -0;
            double clear_1 = -0;
            double clear_2 = -0;
            double clear_3 = -0;
            double clear_4 = 0;
            double t2_slot = 1.5;
            double t3_slot = 1;
            double tspin_mini = -0;
            double tspin_1 = 0;
            double tspin_2 = 8;
            double tspin_3 = 12;
            double combo = 40;
            double ratio = 1.5;
        };
        struct Config
        {
            Param param;
            int const *table;
            int table_max;
        };
        struct Result
        {
            double value;
            int clear;
            int count;
            int t2_value;
            int t3_value;
            m_tetris::TetrisMap const *map;
        };
        struct Status
        {
            int max_combo;
            int max_attack;
            int death;
            int combo;
            int attack;
            int combo_attack;
            int under_attack;
            int map_rise;
            bool b2b;
            double like;
            double value;
            bool operator<(Status const &) const;
        };

    public:
        int8_t get_safe(m_tetris::TetrisMap const &m, char t) const;
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        double ratio() const
        {
            return config_->param.ratio;
        }
        Result eval(TetrisNodeEx const &node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        Status get(TetrisNodeEx &node, Result const &eval_result, size_t depth, Status const &status, m_tetris::TetrisContext::Env const &env) const;

    private:
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        int col_mask_, row_mask_;
        int full_count_;
        struct MapInDangerData
        {
            int data[4];
        };
        std::vector<MapInDangerData> map_danger_data_;
        size_t map_in_danger_(m_tetris::TetrisMap const &map, size_t t, size_t up) const;
    };

    // TowerTris 诊断：NoSpin4 下「Spin0 候选被死亡惩罚」的累计次数
    //（供 worker 的 WEIGHTS 命令输出，用来确认该分支确实生效而不是死代码）
    int spin0_penalty_count();
    // TowerTris 诊断：Allspin 重复惩罚触发次数 / 其中 void 接 void 的次数
    //（void 重复是 Allspin_2 特有判定，单独计数用于核对对齐情况）
    int repeat_penalty_count();
    int void_repeat_count();

    class IO
    {
    public:
        typedef search_amini::Search::ASpinType ASpinType;
        typedef search_amini::Search::TetrisNodeWithASpinType TetrisNodeEx;        struct Param
        {
            double roof = 128;
            double col_trans = 160;
            double row_trans = 160;
            double hole_count = 80;
            double hole_line = 380;
            double well_depth = 100;
            double hole_depth = 40;
            double b2b = 128;
            double attack = 1;
            double hold_t = 4;
            double hold_i = 2;
            double waste_t = 0;
            double waste_i = 0;
            double clear_1 = 0;
            double clear_2 = 0;
            double clear_3 = 0;
            double clear_4 = 1;
            double t2_slot = 1.5;
            double t3_slot = 1;
            double tspin_mini = 0;
            double tspin_1 = 0;
            double tspin_2 = 8;
            double tspin_3 = 12;
            double combo = 30;
            double ratio = 1.5;
        };
        struct Config
        {
            bool is_margin;
            bool season_2;
            bool lockout;
            int multiplier;
            int garbage_cap;
            clock_t start_count;
            Param param;
            // ==== TowerTris 追加：BTB 加成系统与 PC 伤害 ====
            // btb_system 与游戏的 TetrisClearLine.btb_system_use 对应，由 CFG 下发：
            //   1 = surge break 系统：连续 4消/Spin 从第 2 手起 +1（pre_b2b >= 4 时 +2）；
            //       长链（pre_b2b >= 4）被普通消行打断时按 pre_b2b 兑现 surge break 伤害
            //   2 = 累加奖励系统：BTB=1 → +1；BTB>=2 → 1+ln(0.8*BTB+1) 取整数部分 a、
            //       小数部分 b，加成 = a+(1+b)/3（本手伤害取整）；无 surge break 兑现
            // 注意：不要再用 season_2 选伤害模型（那是「不可移动即 T-Spin」档的规则开关）。
            int btb_system = 1;
            // PC（Perfect Clear）附加伤害，游戏侧 pc_damage 原样下发（默认 6）
            int pc_damage = 6;
            // ==== TowerTris 追加：Allspin 重复性惩罚 ====
            // 本游戏 Allspin_1 规则（见 BuffChoseData 描述）：本次「消行类型 + 行数」与上一手完全一致时
            // 立刻上涨一行垃圾。注意「类型」是字符串比较，非 Spin 消行的类型是 ""，
            // 因此 NoSpin 模式（spin_type 恒为 ""）下只要连续两次消行行数相同就会触发。
            // repeat_penalty > 0 时，eval 对「类型与行数都与上一手一致」的候选扣该分数。
            double repeat_penalty = 0;
            int last_spin_type = 0;      // 上一手 ASpinType（0=None/1=TSpin/2=AllSpin/3=TSpinMini/4=ASpinMini）
                                         // -1 = 「无有效记录」（还没消过行，或上次是 Allspin_2 的 void 消行）→ 不参与重复比较
            int last_clear_count = 0;    // 上一手的消行数（void 消行在游戏侧为 -1）
            // ==== TowerTris 追加：NoSpin 模式对齐 ====
            // no_spin==2（无天赋II：所有 Spin 降级为 Mini）：T-Spin 也一律按 Mini 上报，
            // 与游戏的 "Mini T-Spin" 类型与 mini 伤害表口径一致（否则重复性惩罚会因类型不等而漏判）。
            bool spin_force_mini = false;
            // no_spin==4（无天赋IV）：触发 Spin（含 Spin0）立刻上涨实心行 = 必死，
            // 因此对任何被判为 Spin 的候选扣该分数（取极大值），使 bot 绝不选择 Spin。
            // 注意：NoSpin4 下**不能**关掉引擎的 Spin 判定开关，否则 node.type 恒为 None、本惩罚永不触发。
            double spin_death_penalty = 0;
            // ==== TowerTris 追加：Allspin_2（全旋II）====
            // 游戏 TetrisClearLine 的规则（BuffChoseData 描述 + 代码）：
            //   · 非 Spin 消行记 void：**不产生任何攻击**，并且**断开 BTB 链**（哪怕它是四消）
            //   · Spin0（有 Spin 判定、无消行）：判伤害，并使 BTB +1（等于强制 spin0_btb_enabled）
            //   · 重复惩罚只比「消行行数」（不比类型）→ 行情相同就上涨 allspin2_solid_rows 行实心垃圾
            // 打开后 eval 会：void 消行攻击归零并断 BTB、Spin0 续 BTB、重复惩罚改为只比行数。
            bool allspin2_mode = false;
            // 惩罚的「版面」折算：把惩罚上涨的实心垃圾行数也算进预测版面/垃圾抬升，
            // 而不只是扣评估分 —— 评估分只作用于本手候选，搜索往下一层就衰减；
            // 写成版面填充与垃圾抬升后，整棵搜索子树都会把这次惩罚当成既成事实。
            int allspin2_solid_rows = 20;   // Allspin_2 重复惩罚行数（游戏 allspin2_solid_rows）
            int no_spin4_rows = 20;         // no_spin==4 触发 Spin 的行数（游戏 no_spin4_solid_rows）
            // surge break 系统下「btb_count >= 4」那一档的加成值（游戏 _get_btb_bonus()：
            // 默认 +1；Allspin>=2 → +2；Allspin>=4 → +3）。由桥按当前 allspin 档位下发。
            int btb_bonus_high = 1;
            // Allspin 档位数字（0~5，游戏 TetrisGlobalData.clear_allspin）：
            //   2/3 → 行数重复（3 还叠加「与上一手同块类型」）；4/5 → 六块轮（4 取消行数重复）；
            //   5 → 再把有效行数 0/1/2/3 也做成一轮。spin_damage_mul 为 Spin 伤害倍率（5 起 ×3）。
            int allspin_mode = 0;
            int spin_damage_mul = 2;
            // Allspin_4/5「轮内重复」的实心行数（游戏 allspin_round_solid_rows，默认 42）。
            // 与 allspin2_solid_rows(20) 区分：4/5 档里「与上一手重复」仍罚 20，只有轮违规才罚 42。
            int allspin_round_solid_rows = 42;
            // 非 T 的 Spin 消行（AllSpin / ASpinMini）额外加权（按消行数 1/2/3/3+）。
            // 数值由游戏侧 bot_allspin1/2/3/3plus 通过 PARAM allspin1/allspin2/allspin3/allspin3plus 下发；
            // 全旋II 下非 Spin 消行没有任何收益，所以这几个权重直接决定 bot 是否愿意做全旋。
            double allspin_like_1 = 0;
            double allspin_like_2 = 0;
            double allspin_like_3 = 0;
            double allspin_like_3plus = 0;
        };
        struct Result
        {
            double value;
            int clear;
            int count;
            int t2_value;
            int t3_value;
            bool lockout;
            m_tetris::TetrisMap const *map;
        };
        struct Status
        {
            int max_combo;
            int death;
            int combo;
            int attack;
            int under_attack;
            int map_rise;
            int b2bcnt;
            bool pc;
            int board_fill;
            int board_fill_prev;
            int board_fill_diff;
            double like;
            double value;
            // ==== TowerTris：搜索内的「上一手消行」历史 ====
            // 游戏的重复惩罚比较的是「本手 vs 上一手」。在搜索里「上一手」必须随模拟推进，
            // 否则深度 >= 2 的候选永远只跟**真实上一手**比较 —— bot 就会规划出
            // 「这块消 1 行、下一块再消 1 行」这种在游戏里会被罚 20 行实心垃圾的路线。
            //   hist_clear_count：普通消行 = 行数；Spin0 = 0；Allspin_2 的 void = -1
            //   hist_spin_type：与桥的编码一致（0=None/1=TSpin/2=AllSpin/3=TSpinMini/4=ASpinMini），
            //                   -1 = 还没有任何有效记录（Allspin_2 开局；其它模式下非 Spin 消行记 0）
            // 无消行且非 Spin0 的放置不更新这两项（与游戏一致：那种情况不写记录）。
            int hist_spin_type;
            int hist_clear_count;
            // 上一手消行所用方块编号（Z/S/T/I/J/L → 0..5，-1 = 无记录）——Allspin_3 的「同块重复」
            int hist_piece_code;
            // Allspin_4/5 的「轮」已用成员掩码：类型轮 6 bit（Z/S/T/I/J/L）、行数轮 4 bit（0/1/2/3）。
            // 与游戏 _allspin_round_step 同一套推进规则（命中→只剩本手；集满→清空开启新一轮）。
            int round_types_mask;
            int round_counts_mask;
            // Allspin_5 的行数轮是**两轮独立**（游戏 ALLSPIN_ROUND_COUNTS_12 / _03）：
            //   · {1,2} 一轮 → round_counts_mask
            //   · {0,3} 一轮 → round_counts03_mask
            int round_counts03_mask;
            // Allspin_5 的 Void 补偿：塔的发送倍率 extra_pressure_mult（默认 1.0，每次 Void +0.01）。
            // 它是**乘法**作用于自己发出去的攻击（tower_controller: pressure*extra_pressure*...），
            // 所以引擎要在搜索里携带并作用于 attack，而不是给 Void 加奖励分。
            double pressure_mult;
            bool operator<(Status const &) const;
        };

    public:
        int8_t get_safe(m_tetris::TetrisMap const &m, char t) const;
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        double ratio() const
        {
            return config_->param.ratio;
        }
        Result eval(TetrisNodeEx const &node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        Status get(TetrisNodeEx &node, Result const &eval_result, size_t depth, Status const &status, m_tetris::TetrisContext::Env const &env) const;

    private:
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        int col_mask_, row_mask_;
        int full_count_;
        struct MapInDangerData
        {
            int data[4];
        };
        std::vector<MapInDangerData> map_danger_data_;
        size_t map_in_danger_(m_tetris::TetrisMap const &map, size_t t, size_t up) const;
    };
    class TOJ
    {
    public:
        typedef search_tspin::Search::TSpinType TSpinType;
        typedef search_tspin::Search::TetrisNodeWithTSpinType TetrisNodeEx;
        struct Param
        {
            double base = 40;
            double roof = 160;
            double col_trans = 160;
            double row_trans = 160;
            double hole_count = 256;
            double hole_line = 256;
            double clear_width = 24;
            double wide_2 = -64;
            double wide_3 = -64;
            double wide_4 = 8;
            double safe = 16;
            double b2b = 128;
            double attack = 128;
            double hold_t = 0.25;
            double hold_i = 0.25;
            double waste_t = -16;
            double waste_i = -8;
            double clear_1 = -64;
            double clear_2 = -64;
            double clear_3 = -64;
            double clear_4 = 0;
            double t2_slot = 0.75;
            double t3_slot = 0.75;
            double tspin_mini = -2;
            double tspin_1 = 0;
            double tspin_2 = 4;
            double tspin_3 = 4;
            double combo = 80;
            double ratio = 0;
        };
        struct Config
        {
            int const *table;
            int table_max;
            int safe;
            Param param;
        };
        struct Result
        {
            double value;
            int8_t clear;
            int8_t top_out;
            int16_t count;
            int16_t t2_value;
            int16_t t3_value;
            TSpinType t_spin;
            m_tetris::TetrisMap const *map;
        };
        struct Status
        {
            int8_t death;
            int8_t combo;
            int8_t under_attack;
            int8_t map_rise;
            int8_t b2b;
            int16_t t2_value;
            int16_t t3_value;
            double acc_value;
            double like;
            double value;
            bool operator<(Status const &) const;

            static void init_t_value(m_tetris::TetrisMap const &m, int16_t &t2_value_ref, int16_t &t3_value_ref, m_tetris::TetrisMap *out_map = nullptr);
        };

    public:
        int8_t get_safe(m_tetris::TetrisMap const &m, char t) const;
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        double ratio() const
        {
            return config_->param.ratio;
        }
        Result eval(TetrisNodeEx const &node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        Status get(TetrisNodeEx &node, Result const &eval_result, size_t depth, Status const &status, m_tetris::TetrisContext::Env const &env) const;

    private:
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        int col_mask_, row_mask_;
        struct MapInDangerData
        {
            int data[4];
        };
        std::vector<MapInDangerData> map_danger_data_;
        size_t map_in_danger_(m_tetris::TetrisMap const &map, size_t t, size_t up) const;
    };

    class C2
    {
    public:
        struct Config
        {
            std::array<double, 100> p;
            double p_rate;
            int safe;
            int mode;
            int danger;
            int soft_drop;
        };
        struct Status
        {
            double attack;
            double map;
            size_t combo;
            size_t combo_limit;
            double value;
            bool operator<(Status const &) const;
        };
        struct Result
        {
            double attack;
            double map;
            size_t clear;
            double fill;
            double hole;
            double new_hole;
            bool soft_drop;
        };

    public:
        void init(m_tetris::TetrisContext const *context, Config const *config);
        std::string ai_name() const;
        Result eval(m_tetris::TetrisNode const *node, m_tetris::TetrisMap const &map, m_tetris::TetrisMap const &src_map, size_t clear) const;
        Status get(m_tetris::TetrisNode const *node, Result const &eval_result, size_t depth, Status const &status, m_tetris::TetrisContext::Env const &env) const;
        Status iterate(Status const **status, size_t status_length) const;

    private:
        m_tetris::TetrisContext const *context_;
        Config const *config_;
        int col_mask_, row_mask_;
        struct MapInDangerData
        {
            int data[4];
        };
        std::vector<MapInDangerData> map_danger_data_;
        size_t map_in_danger_(m_tetris::TetrisMap const &map) const;
    };

}