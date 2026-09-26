use libtetris::*;
use serde::{Deserialize, Serialize};

use super::*;

#[derive(Clone, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(default)]
pub struct Standard {
    pub back_to_back: i32,
    pub bumpiness: i32,
    pub bumpiness_sq: i32,
    pub row_transitions: i32,
    pub height: i32,
    pub top_half: i32,
    pub top_quarter: i32,
    pub jeopardy: i32,
    pub cavity_cells: i32,
    pub cavity_cells_sq: i32,
    pub overhang_cells: i32,
    pub overhang_cells_sq: i32,
    pub covered_cells: i32,
    pub covered_cells_sq: i32,
    pub tslot: [i32; 4],
    pub well_depth: i32,
    pub max_well_depth: i32,
    pub well_column: [i32; 10],

    pub b2b_clear: i32,
    pub clear1: i32,
    pub clear2: i32,
    pub clear3: i32,
    pub clear4: i32,
    pub tspin1: i32,
    pub tspin2: i32,
    pub tspin3: i32,
    pub mini_tspin1: i32,
    pub mini_tspin2: i32,
    pub allspin1: i32,
    pub allspin2: i32,
    pub allspin3: i32,
    pub allspin3plus: i32,
    pub perfect_clear: i32,
    pub combo_garbage: i32,
    pub move_time: i32,
    pub wasted_t: i32,

    pub use_bag: bool,
    pub timed_jeopardy: bool,
    pub stack_pc_damage: bool,
    pub sub_name: Option<String>,

    // ---- 实际游戏伤害模型（tower-tetris 规则） ----
    // 开启后，evaluate 会额外按“实际游戏”的伤害公式计算本次落块产生的攻击，
    // 并乘以 damage_eval_mult 叠加到评估分，使 bot 优先做出能实际造成伤害的落块。
    // 这些值是 buff 界面可调整的（由 bridge 通过 worker 的 S 命令下发覆盖）。
    pub game_damage_enabled: bool,
    /// 基础伤害表，按下标=消行数(0..=4)：游戏【0,0,1,2,4】
    pub base_damage: [i32; 5],
    /// T-Spin 伤害表，按下标=消行数(1..=3)：游戏【0,2,4,6】(下标0不用)
    pub tspin_damage: [i32; 4],
    /// Allspin 伤害表（下标=消行数 1..=3）。
    /// 注意：现在 allspin 的伤害不再使用本表——board 已按 allspin_enabled 把非T卡住判为
    /// Mini*（allmini 模式，走 base_damage，与 T mini 一致）或 Tspin*（allspin 模式，走
    /// tspin_damage，与 T-Spin 一致）。本字段仅保留以兼容 C-API/S 命令协议，不再参与计算。
    pub allspin_damage: [i32; 4],
    /// 连击伤害表，按下标=连击数(0..=31)：游戏 combo_damage_list
    pub combo_damage: [i32; 32],
    /// 连击计算方式：0=旧连击表（combo_damage 表），1=新公式（默认）：
    ///   combo_damage = floor(max(ln(1+1.25*combo), ((b2b_active?1:0)+attack)*(1+0.25*combo)))
    ///   其中 attack = 本次消行的 base+spin（不含BTB加成）
    pub combo_formula: i32,
    /// 连续 BTB 加成（游戏：btb_count>1 时 spin/quad 各 +1）
    pub b2b_bonus: i32,
    /// Perfect Clear 附加伤害（游戏 pc_damage = 10）
    pub pc_damage: i32,
    /// 攻击倍率（buff send_mult_attack），存为千分比（1000 = 1.0）
    pub send_mult_attack: i32,
    /// 防御倍率（buff mult_defend），存为千分比（1000 = 1.0）
    pub mult_defend: i32,
    /// 把伤害值换算成评估分的系数（伤害 * 该值 加入 acc_eval）
    pub damage_eval_mult: i32,
    /// 攻击效率权重：攻击效率 = 本次攻击伤害 / 本次消除行数。
    /// 该值 e 作为评估权重，efficiency 项 = (伤害/行数) * 该权重 加入 acc_eval，
    /// 使 bot 优先选择“每消一行伤害更高”（更高效）的攻击。
    pub attack_efficiency_weight: i32,
    /// allspin 规则模式（int）：
    ///   0 = allmini：非T方块卡住 → 判定为 mini spin（效果/伤害与 T mini 一致，走基础伤害表）
    ///   1 = allspin ：非T方块卡住 → 判定为 full spin（效果/伤害与 T-Spin 一致，走 T-Spin 伤害表）
    ///   其他值 = 保留，供未来开发。
    pub allspin_enabled: i32,
    /// allspin_1 重复惩罚的评估扣分（负值=降低该决策的选取值）。
    /// 触发“与上次消行完全一致”的重复惩罚时，从评估分中扣除此值。
    pub allspin_repeat_penalty: i32,
}

impl Default for Standard {
    fn default() -> Self {
        Standard {
            back_to_back: 52,
            // ---- 堆叠质量优化（tetris-tower 策略）----
            // 强化凹凸/洞/悬空/覆盖惩罚，并大幅提高 T 槽与井的价值：让 bot 在连续 spin
            // （tspin1/allspin1 攒 BTB、tspin2 修补）时保持堆叠平整、少封闭洞、积极保留
            // T-Spin 位与下挖井道。这样 spin 后地形不易崩，BTB 链（含 combo）得以延续，
            // 避免“贪 spin1 破坏地形到被迫断开 BTB”和“堆叠导致无法下挖”。
            bumpiness: -105,
            bumpiness_sq: -24,
            row_transitions: -18,
            height: -39,
            top_half: -150,
            top_quarter: -511,
            jeopardy: -11,
            // 注意：被封死的洞（covered）比开放洞（cavity）更难挖掘——开放洞还能直接填，
            // 封死洞只能靠消行/精确方块，因此 covered 惩罚应接近甚至不低于 cavity。
            // 旧值 covered=-55 相对 cavity=-320 明显偏低，导致 bot 决策时对“会封死洞”的
            // 放置惩罚不足，易留下无法挖掘的死洞。这里提高 covered 与 overhang 惩罚。
            cavity_cells: -320,
            cavity_cells_sq: -12,
            overhang_cells: -140,
            overhang_cells_sq: -8,
            covered_cells: -100,
            covered_cells_sq: -8,
            tslot: [80, 330, 500, 720],
            well_depth: 120,
            max_well_depth: 26,
            well_column: [20, 23, 20, 50, 59, 21, 59, 10, -10, 24],

            move_time: -3,
            wasted_t: -152,
            b2b_clear: 200,
            clear1: -143,
            clear2: -100,
            clear3: -58,
            clear4: 260,
            tspin1: 121,
            tspin2: 410,
            tspin3: 602,
            mini_tspin1: -158,
            mini_tspin2: -93,
            allspin1: 121,
            allspin2: 410,
            allspin3: 602,
            allspin3plus: 602,
            perfect_clear: 999,
            combo_garbage: 150,

            use_bag: true,
            timed_jeopardy: true,
            stack_pc_damage: false,
            sub_name: None,

            // 默认启用实际游戏伤害模型，默认值 = 游戏标准规则（tower-tetris 消行伤害）
            game_damage_enabled: true,
            base_damage: [0, 0, 1, 2, 4],
            tspin_damage: [0, 2, 4, 6],
            allspin_damage: [0, 4, 6, 8],
            combo_damage: [
                0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
                5, 5, 5, 5,
            ],
            combo_formula: 1,
            b2b_bonus: 1,
            pc_damage: 10,
            send_mult_attack: 1000,
            mult_defend: 1000,
            damage_eval_mult: 100,
            attack_efficiency_weight: 100,
            allspin_enabled: 0,
            allspin_repeat_penalty: -120,
        }
    }
}

impl Standard {
    pub fn fast_config() -> Self {
        Standard {
            back_to_back: 10,
            bumpiness: -7,
            bumpiness_sq: -28,
            row_transitions: -5,
            height: -46,
            top_half: -126,
            top_quarter: -493,
            jeopardy: -11,
            cavity_cells: -176,
            cavity_cells_sq: -6,
            overhang_cells: -47,
            overhang_cells_sq: -9,
            covered_cells: -25,
            covered_cells_sq: 1,
            tslot: [0, 150, 296, 207],
            well_depth: 158,
            max_well_depth: -2,
            well_column: [31, 16, -41, 37, 49, 30, 56, 48, -27, 22],
            b2b_clear: 160,
            clear1: -122,
            clear2: -174,
            clear3: 11,
            clear4: 280,
            tspin1: 131,
            tspin2: 392,
            tspin3: 628,
            mini_tspin1: -188,
            mini_tspin2: -682,
            allspin1: 131,
            allspin2: 392,
            allspin3: 628,
            allspin3plus: 628,
            perfect_clear: 991,
            combo_garbage: 272,
            move_time: -1,
            wasted_t: -147,
            use_bag: true,
            timed_jeopardy: false,
            stack_pc_damage: false,
            sub_name: None,

            game_damage_enabled: true,
            base_damage: [0, 0, 1, 2, 4],
            tspin_damage: [0, 2, 4, 6],
            allspin_damage: [0, 4, 6, 8],
            combo_damage: [
                0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
                5, 5, 5, 5,
            ],
            combo_formula: 1,
            b2b_bonus: 1,
            pc_damage: 10,
            send_mult_attack: 1000,
            mult_defend: 1000,
            damage_eval_mult: 100,
            attack_efficiency_weight: 100,
            allspin_enabled: 0,
            allspin_repeat_penalty: -120,
        }
    }

    /// 计算本次落块按“实际游戏规则”产生的攻击（垃圾行）数。
    ///
    /// 复刻游戏 tetris_clear_line.gd 的 _calculate_damage：
    ///   base = base_damage[消行数]（非 spin）
    ///   spin = tspin_damage[消行数]（T-Spin/其他全旋；mini 用基础伤害表）
    ///   + b2b_bonus（lock.b2b 为真 = 连续 BTB 的 spin/quad）
    ///   + combo_damage[连击数]（game 的 combo_damage_list）
    ///   + pc_damage（Perfect Clear）
    /// 最后乘 send_mult_attack / mult_defend（buff 倍率）。
    ///
    /// 注意：游戏 _calculate_damage 中 `surge_break`（btb 中断时释放 btb_count 的
    /// 攻击）被有意排除——该伤害不进入 bot 的决策评估，避免 bot 因“故意中断 BTB
    /// 以释放积蓄伤害”而做出错误决策。此处不添加 surge_break。
    pub fn game_damage(&self, lock: &LockResult, b2b_active: bool) -> f32 {
        self.game_damage_with_btb(lock, b2b_active, lock.btb_count)
    }

    /// 计算本次落块按“实际游戏规则”产生的攻击（垃圾行）数。
    /// `btb_count_before` 为本次落块前的 BTB 计数（对应游戏 _calculate_damage 时的 btb_count）。
    pub fn game_damage_with_btb(&self, lock: &LockResult, b2b_active: bool, btb_count_before: u32) -> f32 {
        let clear_count = lock.cleared_lines.len().min(4) as usize;
        let is_spin = matches!(
            lock.placement_kind,
            PlacementKind::Tspin
                | PlacementKind::Tspin1
                | PlacementKind::Tspin2
                | PlacementKind::Tspin3
        );
        let is_mini = matches!(
            lock.placement_kind,
            PlacementKind::MiniTspin | PlacementKind::MiniTspin1 | PlacementKind::MiniTspin2
        );

        // 基础伤害：mini 用基础伤害表；T-Spin/全旋用 tspin 表；普通消行用基础表。
        // allspin 规则：board 已按 allspin_enabled 把非T卡住判为 Mini*（allmini 模式）或
        // Tspin*（allspin 模式），这里直接按 placement_kind 走对应表即可：
        //   allmini 模式 → is_mini → base_damage（与 T mini 一致）
        //   allspin 模式 → is_spin → tspin_damage（与 T-Spin 一致）
        let mut dmg: i32 = if is_mini {
            self.base_damage[clear_count]
        } else if is_spin {
            self.tspin_damage[clear_count.min(3)]
        } else {
            self.base_damage[clear_count]
        };

        // 记录本次消行的攻击值（base+spin，不含BTB加成），供连击公式使用
        let attack_value: i32 = dmg;

        // 连续 BTB 加成，复刻游戏 _calculate_damage：
//   游戏：if btb_count > 1: boost = (btb_count >= 4) ? 2 : 1
//   即连续第 3 次起 spin/quad 才有 +1 加成；连续第 5 次（btb_count>=4）额外 +1（+2 而非 +1）。
//   例：连续第 5 次 spin/quad 的消4 = 4+2 而不是 4+1。
// 对照：btb_count_before = 本次落块前的 btb_count；btb_count_before > 1 等同游戏的加成才生效。
if btb_count_before > 1 {
    let boost: i32 = self.b2b_bonus + if btb_count_before >= 4 { 1 } else { 0 };
    dmg += boost;
}
        // 连击伤害（lock.combo = 本次落块前的连击数，与游戏 combo_count 一致）。
        // 游戏仅当 combo_count > 0 时计算连击伤害（首次消行 combo=0 无连击伤害）。
        if let Some(combo) = lock.combo {
            if combo > 0 {
                if self.combo_formula == 1 {
                    // 新公式（默认）：
                    //   combo_damage = floor(max(ln(1+1.25*combo), ((b2b_active?1:0)+attack)*(1+0.25*combo)))
                    //   其中 attack = base+spin（不含BTB加成）
                    let c = combo.min(31) as f32;
                    let b2b_flag: f32 = if b2b_active { 1.0 } else { 0.0 };
                    let combined: f32 = (b2b_flag + attack_value as f32) * (1.0 + 0.25 * c);
                    let log_term: f32 = (1.0 + 1.25 * c).ln();
                    dmg += log_term.max(combined).floor() as i32;
                } else {
                    let idx = (combo as usize).min(self.combo_damage.len() - 1);
                    dmg += self.combo_damage[idx];
                }
            }
        }
        // Perfect Clear 附加伤害
        if lock.perfect_clear {
            dmg += self.pc_damage;
        }

        // 攻击/防御倍率（千分比）：effective = send_mult_attack / mult_defend
        let mult = if self.mult_defend > 0 {
            self.send_mult_attack as f32 / self.mult_defend as f32
        } else {
            self.send_mult_attack as f32
        };
        dmg as f32 * mult
    }
}

impl Evaluator for Standard {
    type Value = Value;
    type Reward = Reward;

    fn name(&self) -> String {
        let mut info = "Standard".to_owned();
        if let Some(extra) = &self.sub_name {
            info.push('\n');
            info.push_str(extra);
        }
        info
    }

    fn pick_move(
        &self,
        candidates: Vec<MoveCandidate<Value>>,
        incoming: u32,
    ) -> MoveCandidate<Value> {
        let mut backup = None;
        for mv in candidates.into_iter() {
            if incoming == 0
                || mv.board.column_heights()[3..6]
                    .iter()
                    .all(|h| incoming as i32 - mv.lock.garbage_sent as i32 + h <= 20)
            {
                return mv;
            }

            match backup {
                None => backup = Some(mv),
                Some(c) if c.evaluation.spike < mv.evaluation.spike => backup = Some(mv),
                _ => {}
            }
        }

        return backup.unwrap();
    }

    fn evaluate(
        &self,
        lock: &LockResult,
        board: &Board,
        move_time: u32,
        placed: Piece,
    ) -> (Value, Reward) {
        let mut transient_eval = 0;
        let mut acc_eval = 0;

        if lock.perfect_clear {
            acc_eval += self.perfect_clear;
        }
        if self.stack_pc_damage || !lock.perfect_clear {
            if lock.b2b {
                acc_eval += self.b2b_clear;
            }
            if let Some(combo) = lock.combo {
                let combo = combo.min(11) as usize;
                acc_eval += self.combo_garbage * libtetris::COMBO_GARBAGE[combo] as i32;
            }
            // 非T旋转（allspin，不论 mini/full）统一用独立的 allspin 权重（只按消行数 1/2/3/3+ 区分）。
            // board 已把非T卡住判为 Tspin*（allspin 模式）或 MiniTspin*（allmini 模式），
            // 且 lock.allspin 对一切非T spin 为 true，故这里按 lock.allspin 分支即可。
            if lock.allspin {
                match lock.cleared_lines.len() {
                    1 => acc_eval += self.allspin1,
                    2 => acc_eval += self.allspin2,
                    3 => acc_eval += self.allspin3,
                    n if n >= 4 => acc_eval += self.allspin3plus,
                    _ => {}
                }
            } else {
                match lock.placement_kind {
                    PlacementKind::Clear1 => {
                        acc_eval += self.clear1;
                    }
                    PlacementKind::Clear2 => {
                        acc_eval += self.clear2;
                    }
                    PlacementKind::Clear3 => {
                        acc_eval += self.clear3;
                    }
                    PlacementKind::Clear4 => {
                        acc_eval += self.clear4;
                    }
                    PlacementKind::Tspin1 => {
                        acc_eval += self.tspin1;
                    }
                    PlacementKind::Tspin2 => {
                        acc_eval += self.tspin2;
                    }
                    PlacementKind::Tspin3 => {
                        acc_eval += self.tspin3;
                    }
                    PlacementKind::MiniTspin1 => {
                        acc_eval += self.mini_tspin1;
                    }
                    PlacementKind::MiniTspin2 => {
                        acc_eval += self.mini_tspin2;
                    }
                    _ => {}
                }
            }
        }

        // 实际游戏伤害模拟：按游戏规则计算本次落块造成的攻击并计入评估。
        // 使 bot 的”清行/连击/spin/PC“决策与游戏真实伤害一致（并受 buff 倍率影响）。
        if self.game_damage_enabled {
            // board.b2b_bonus = 本次落块前的 BTB 状态（对应游戏 is_btb_active）
            let dmg: f32 = self.game_damage(lock, board.b2b_bonus);
            acc_eval += (dmg * self.damage_eval_mult as f32) as i32;
            // 攻击效率决策：效率 = 本次攻击伤害 / 本次消除行数。
            // 用 attack_efficiency_weight 权重将效率换算成评估分，使 bot 优先选择
            // “每消一行伤害更高”的高效攻击。无消行时效率为 0，不产生贡献。
            let lines: f32 = lock.cleared_lines.len().max(1) as f32;
            acc_eval += ((dmg / lines) * self.attack_efficiency_weight as f32) as i32;
        }

        // 规则惩罚：本次决策触发 allspin_1 重复惩罚 → 额外降低选取值。
        if lock.allspin_repeat {
            acc_eval += self.allspin_repeat_penalty;
        }

        if placed == Piece::T {
            match lock.placement_kind {
                PlacementKind::Tspin1 | PlacementKind::Tspin2 | PlacementKind::Tspin3 => {}
                _ => acc_eval += self.wasted_t,
            }
        }

        // magic approximation of line clear delay
        let move_time = if lock.placement_kind.is_clear() {
            move_time as i32 + 40
        } else {
            move_time as i32
        };
        acc_eval += self.move_time * move_time;

        if board.b2b_bonus {
            transient_eval += self.back_to_back;
        }

        let highest_point = *board.column_heights().iter().max().unwrap() as i32;
        transient_eval += self.top_quarter * (highest_point - 15).max(0);
        transient_eval += self.top_half * (highest_point - 10).max(0);

        acc_eval += self.jeopardy
            * (highest_point - 10).max(0)
            * if self.timed_jeopardy { move_time } else { 10 }
            / 10;

        let ts = if self.use_bag {
            board.next_bag().contains(Piece::T) as usize
                + (board.next_bag().len() <= 3) as usize
                + (board.hold_piece == Some(Piece::T)) as usize
        } else {
            1 + (board.hold_piece == Some(Piece::T)) as usize
        };

        let mut board = board.clone();
        for _ in 0..ts {
            let cutout_location = sky_tslot_left(&board)
                .or_else(|| sky_tslot_right(&board))
                .or_else(|| {
                    let tst = tst_twist_left(&board).or_else(|| tst_twist_right(&board))?;
                    cave_tslot(&board, tst).or_else(|| {
                        let corners = board.occupied(tst.x - 1, tst.y - 1) as usize
                            + board.occupied(tst.x + 1, tst.y - 1) as usize
                            + board.occupied(tst.x - 1, tst.y + 1) as usize
                            + board.occupied(tst.x + 1, tst.y + 1) as usize;
                        if corners >= 3 && board.on_stack(&tst) {
                            Some(tst)
                        } else {
                            None
                        }
                    })
                })
                .or_else(|| fin_left(&board))
                .or_else(|| fin_right(&board));
            let result = match cutout_location {
                Some(location) => cutout_tslot(board.clone(), location),
                None => break,
            };
            transient_eval += self.tslot[result.lines];
            if let Some(b) = result.result {
                board = b;
            } else {
                break;
            }
        }

        let highest_point = *board.column_heights().iter().max().unwrap() as i32;
        transient_eval += self.height * highest_point;

        let mut well = 0;
        for x in 1..10 {
            if board.column_heights()[x] <= board.column_heights()[well] {
                well = x;
            }
        }

        let mut depth = 0;
        'yloop: for y in board.column_heights()[well]..20 {
            for x in 0..10 {
                if x as usize != well && !board.occupied(x, y) {
                    break 'yloop;
                }
            }
            depth += 1;
        }
        let depth = depth.min(self.max_well_depth);
        transient_eval += self.well_depth * depth;
        if depth != 0 {
            transient_eval += self.well_column[well];
        }

        if self.row_transitions != 0 {
            transient_eval += self.row_transitions
                * (0..40)
                    .map(|y| *board.get_row(y))
                    .map(|r| (r | 0b1_00000_00000) ^ (1 | r << 1))
                    .map(|d| d.count_ones() as i32)
                    .sum::<i32>();
        }

        if self.bumpiness | self.bumpiness_sq != 0 {
            let (bump, bump_sq) = bumpiness(&board, well);
            transient_eval += bump * self.bumpiness;
            transient_eval += bump_sq * self.bumpiness_sq;
        }

        if self.cavity_cells | self.cavity_cells_sq | self.overhang_cells | self.overhang_cells_sq
            != 0
        {
            let (cavity_cells, overhang_cells) = cavities_and_overhangs(&board);
            transient_eval += self.cavity_cells * cavity_cells;
            transient_eval += self.cavity_cells_sq * cavity_cells * cavity_cells;
            transient_eval += self.overhang_cells * overhang_cells;
            transient_eval += self.overhang_cells_sq * overhang_cells * overhang_cells;
        }

        if self.covered_cells | self.covered_cells_sq != 0 {
            let (covered_cells, covered_cells_sq) = covered_cells(&board);
            transient_eval += self.covered_cells * covered_cells;
            transient_eval += self.covered_cells_sq * covered_cells_sq;
        }

        (
            Value {
                value: transient_eval,
                spike: 0,
            },
            Reward {
                value: acc_eval,
                attack: if lock.placement_kind.is_clear() {
                    lock.garbage_sent as i32
                } else {
                    -1
                },
            },
        )
    }
}

/// Evaluates the bumpiness of the playfield.
///
/// The first returned value is the total amount of height change outside of an apparent well. The
/// second returned value is the sum of the squares of the height changes outside of an apparent
/// well.
fn bumpiness(board: &Board, well: usize) -> (i32, i32) {
    let mut bumpiness = -1;
    let mut bumpiness_sq = -1;

    let mut prev = if well == 0 { 1 } else { 0 };
    for i in 1..10 {
        if i == well {
            continue;
        }
        let dh = (board.column_heights()[prev] - board.column_heights()[i]).abs();
        bumpiness += dh;
        bumpiness_sq += dh * dh;
        prev = i;
    }

    (bumpiness.abs() as i32, bumpiness_sq.abs() as i32)
}

/// Evaluates the holes in the playfield.
///
/// The first returned value is the number of cells that make up fully enclosed spaces (cavities).
/// The second is the number of cells that make up partially enclosed spaces (overhangs).
fn cavities_and_overhangs(board: &Board) -> (i32, i32) {
    let mut cavities = 0;
    let mut overhangs = 0;

    for y in 0..*board.column_heights().iter().max().unwrap() {
        for x in 0..10 {
            if board.occupied(x as i32, y) || y >= board.column_heights()[x] {
                continue;
            }

            if x > 1 {
                if board.column_heights()[x - 1] <= y - 1 && board.column_heights()[x - 2] <= y {
                    overhangs += 1;
                    continue;
                }
            }

            if x < 8 {
                if board.column_heights()[x + 1] <= y - 1 && board.column_heights()[x + 2] <= y {
                    overhangs += 1;
                    continue;
                }
            }

            cavities += 1;
        }
    }

    (cavities, overhangs)
}

/// Evaluates how covered holes in the playfield are.
///
/// The first returned value is the number of filled cells cover the topmost hole in the columns.
/// The second value is the sum of the squares of those values.
fn covered_cells(board: &Board) -> (i32, i32) {
    let mut covered = 0;
    let mut covered_sq = 0;

    for x in 0..10 {
        for y in (0..board.column_heights()[x] - 2).rev() {
            if !board.occupied(x as i32, y) {
                let cells = 6.min(board.column_heights()[x] - y - 1);
                covered += cells;
                covered_sq += cells * cells;
            }
        }
    }

    (covered, covered_sq)
}

macro_rules! detect_shape {
    (
        $name:ident
        heights [$($heights:pat)*]
        require (|$b:pat, $xarg:pat| $req:expr)
        start_y ($starty:expr)
        success ($x:expr, $y:expr, $piece:ident, $facing:ident)
        $([$($rowspec:tt)*])*
    ) => {
        fn $name(board: &Board) -> Option<FallingPiece> {
            for (x, s) in board.column_heights().windows(
                detect_shape!(@len [$($heights)*])
            ).enumerate() {
                let x = x as i32;
                if let [$($heights),*] = *s {
                    if !(|$b: &Board, $xarg: i32| $req)(board, x) { continue }
                    let y = $starty;
                    $(
                        {
                            $(
                                if !detect_shape!(@rowspec $rowspec board x y) {
                                    continue
                                }
                                #[allow(unused)]
                                let x = x + 1;
                            )*
                        }
                        #[allow(unused)]
                        let y = y-1;
                    )*
                    return Some(FallingPiece {
                        kind: PieceState(Piece::$piece, RotationState::$facing),
                        x: x + $x,
                        y: $y,
                        tspin: TspinStatus::None
                    })
                }
            }
            None
        }
    };
    (@rowspec ? $board:ident $x:ident $y:ident) => { true };
    (@rowspec # $board:ident $x:ident $y:ident) => { $board.occupied($x, $y) };
    (@rowspec _ $board:ident $x:ident $y:ident) => { !$board.occupied($x, $y) };
    (@len []) => { 0 };
    (@len [$_:tt $($rest:tt)*]) => { 1 + detect_shape!(@len [$($rest)*]) }
}

detect_shape! {
    sky_tslot_right
    heights [_ h1 h2]
    require (|_, _| h1 <= h2-1)
    start_y(h2+1)
    success(1, h2, T, South)
    [# ? ?]
    [_ ? ?]
    [# ? ?]
}

detect_shape! {
    sky_tslot_left
    heights [h1 h2 _]
    require(|_, _| h2 <= h1-1)
    start_y(h1+1)
    success(1, h1, T, South)
    [? ? #]
    [? ? _]
    [? ? #]
}

detect_shape! {
    tst_twist_left
    heights [h1 h2 _]
    require (|board, x| h1 <= h2 && board.occupied(x-1, h2) == board.occupied(x-1, h2+1))
    start_y (h2 + 1)
    success (2, h2-2, T, West)
    [? ? #]
    [? ? _]
    [? ? _]
    [? _ _]
    [? ? _]
}

detect_shape! {
    tst_twist_right
    heights [_ h1 h2]
    require (|board, x| h2 <= h1 && board.occupied(x+3, h1) == board.occupied(x+3, h1+1))
    start_y (h1 + 1)
    success (0, h1-2, T, East)
    [# ? ?]
    [_ ? ?]
    [_ ? ?]
    [_ _ ?]
    [_ ? ?]
}

detect_shape! {
    fin_left
    heights [h1 h2 _ _]
    require (|_, _| h1 <= h2+1)
    start_y(h2 + 2)
    success (3, h2-1, T, West)
    [? ? # # ?]
    [? ? _ _ ?]
    [? ? _ _ #]
    [? ? _ _ ?]
    [? ? # _ #]
}

detect_shape! {
    fin_right
    heights [_ _ h1 h2]
    require (|board, x| h2 <= h1+1 && board.occupied(x-1, h1) && board.occupied(x-1, h1-2))
    start_y (h1 + 2)
    success (0, h1-1, T, East)
    [# # ? ?]
    [_ _ ? ?]
    [_ _ ? ?]
    [_ _ ? ?]
    [_ # ? ?]
}

fn cave_tslot(board: &Board, mut starting_point: FallingPiece) -> Option<FallingPiece> {
    starting_point.sonic_drop(board);
    let x = starting_point.x;
    let y = starting_point.y;
    match starting_point.kind.1 {
        RotationState::East => {
            // Check:
            // []<>      <>
            // ..<><>  []<><>[]
            // []<>[]    <>....
            //           []..[]
            if !board.occupied(x - 1, y)
                && board.occupied(x - 1, y - 1)
                && board.occupied(x + 1, y - 1)
                && board.occupied(x - 1, y + 1)
            {
                Some(FallingPiece {
                    x,
                    y,
                    kind: PieceState(Piece::T, RotationState::South),
                    tspin: TspinStatus::None,
                })
            } else if !board.occupied(x + 1, y - 1)
                && !board.occupied(x + 2, y - 1)
                && !board.occupied(x + 1, y - 2)
                && board.occupied(x - 1, y)
                && board.occupied(x + 2, y)
                && board.occupied(x, y - 2)
                && board.occupied(x + 2, y - 2)
            {
                Some(FallingPiece {
                    x: x + 1,
                    y: y - 1,
                    kind: PieceState(Piece::T, RotationState::South),
                    tspin: TspinStatus::None,
                })
            } else {
                None
            }
        }
        RotationState::West => {
            // Check:
            //   <>[]      <>
            // <><>..  []<><>[]
            // []<>[]  ....<>
            //         []..[]
            if !board.occupied(x + 1, y)
                && board.occupied(x + 1, y + 1)
                && board.occupied(x + 1, y - 1)
                && board.occupied(x - 1, y - 1)
            {
                Some(FallingPiece {
                    x,
                    y,
                    kind: PieceState(Piece::T, RotationState::South),
                    tspin: TspinStatus::None,
                })
            } else if !board.occupied(x - 1, y - 1)
                && !board.occupied(x - 2, y - 1)
                && !board.occupied(x - 1, y - 2)
                && board.occupied(x + 1, y)
                && board.occupied(x - 2, y)
                && board.occupied(x - 2, y - 2)
                && board.occupied(x, y - 2)
            {
                Some(FallingPiece {
                    x: x - 1,
                    y: y - 1,
                    kind: PieceState(Piece::T, RotationState::South),
                    tspin: TspinStatus::None,
                })
            } else {
                None
            }
        }
        _ => None,
    }
}

struct Cutout {
    lines: usize,
    result: Option<Board>,
}

fn cutout_tslot(mut board: Board, mut piece: FallingPiece) -> Cutout {
    piece.tspin = TspinStatus::Full;
    let result = board.lock_piece(piece);

    match result.placement_kind {
        PlacementKind::Tspin => Cutout {
            lines: 0,
            result: None,
        },
        PlacementKind::Tspin1 => Cutout {
            lines: 1,
            result: None,
        },
        PlacementKind::Tspin2 => Cutout {
            lines: 2,
            result: Some(board),
        },
        PlacementKind::Tspin3 => Cutout {
            lines: 3,
            result: Some(board),
        },
        _ => unreachable!(),
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, Default, Serialize, Deserialize)]
pub struct Reward {
    value: i32,
    attack: i32,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Default, Serialize, Deserialize)]
pub struct Value {
    value: i32,
    spike: i32,
}

impl std::ops::Add for Value {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Value {
            value: self.value + rhs.value,
            spike: self.spike + rhs.spike,
        }
    }
}

impl std::ops::Add<Reward> for Value {
    type Output = Self;
    fn add(self, rhs: Reward) -> Self {
        Value {
            value: self.value + rhs.value,
            spike: if rhs.attack == -1 {
                0
            } else {
                self.spike + rhs.attack
            },
        }
    }
}

impl std::ops::Div<usize> for Value {
    type Output = Self;
    fn div(self, rhs: usize) -> Self {
        Value {
            value: self.value / rhs as i32,
            spike: self.spike / rhs as i32,
        }
    }
}

impl std::ops::Mul<usize> for Value {
    type Output = Self;
    fn mul(self, rhs: usize) -> Self {
        Value {
            value: self.value * rhs as i32,
            spike: self.spike * rhs as i32,
        }
    }
}

impl Evaluation<Reward> for Value {
    fn modify_death(self) -> Self {
        Value {
            value: self.value - 1000,
            spike: 0,
        }
    }

    fn weight(self, min: &Value, rank: usize) -> i64 {
        let e = (self.value - min.value) as i64 + 10;
        e * e / (rank * rank + 1) as i64
    }

    fn improve(&mut self, new_result: Self) {
        self.value = self.value.max(new_result.value);
        self.spike = self.spike.max(new_result.spike);
    }
}
