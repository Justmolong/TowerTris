use std::collections::VecDeque;
use std::iter::DoubleEndedIterator;

use arrayvec::ArrayVec;
use enumset::EnumSet;
use serde::{Deserialize, Serialize};

use crate::*;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Board<R = u16> {
    cells: ArrayVec<[R; 40]>,
    column_heights: [i32; 10],
    pub combo: u32,
    pub b2b_bonus: bool,
    /// 连续 BTB 计数（对应游戏 btb_count）。首次 spin/quad 为 1，连续递增。
    /// 用于复刻游戏《_calculate_damage 的 btb>=4 时 btb 加成额外 +1》规则。
    pub btb_count: u32,
    pub hold_piece: Option<Piece>,
    next_pieces: VecDeque<Piece>,
    pub bag: EnumSet<Piece>,
    /// Row at which new pieces spawn (default 19, standard tetris).
    pub spawn_y: u32,
    /// Lockout threshold: a piece whose cells are all at `y >= lockout_y` is
    /// considered locked out. Default 20 (standard tetris).
    pub lockout_y: u32,
    /// allspin 规则模式（int）：
    ///   0 = allmini：非T方块卡住 → 判定为 mini spin（效果/伤害与 T mini 一致）
    ///   1 = allspin ：非T方块卡住 → 判定为 full spin（效果/伤害与 T-Spin 一致）
    ///   其他值 = 保留，供未来开发（暂不判定 spin）。
    pub allspin_enabled: i32,
    /// 自定义踢墙表（游戏 asc 踢墙表），空 = 使用标准 SRS rotation_points。
    /// 每个元素为 `(dx, dy)`，CW 乘 1、CCW 乘 -1、180° 乘 1（与游戏一致）。
    pub kick_table: Vec<(i32, i32)>,
    /// 实心垃圾行位掩码：bit i = 行 i 是实心垃圾行（不可消除）。
    /// 行号 = 本棋盘行号（0 = 底部）。实心行即使整行填满也不会被消行，
    /// 但会随上方消行而整体下移（保持相对位置），与游戏 `_clear_single_line` 一致。
    pub solid_rows: u64,
    /// 旋转时最后一个非空 kick 下标（用于 T-Spin mini 判定，等同 SRS 的 i==4）
    pub kick_is_last: bool,
    /// 是否启用游戏自定义规则。由 S 命令设置；false 时保持标准 ColdClear 行为。
    /// 注意：非T方块卡住的 spin 判定已改由 allspin_enabled 单独决定（0=allmini / 1=allspin），
    /// 本字段不再参与该判定，仅保留用于其它游戏自定义规则与序列化/传递兼容。
    pub game_rules_enabled: bool,
    /// 上次消行的 spin 类型键（供 allspin_1 重复惩罚比对）。0=无 spin。
    pub last_clear_kind: i32,
    /// 上次消行的行数。
    pub last_clear_count: i32,
    /// NoSpin 规则模式（int）：0=默认；1=所有Spin视为Mini（评估层处理）；2=不判定任何Spin。
    /// no_spin=2 时 lock_piece 把 spin 归一化为普通消行（不触发 b2b、伤害走基础表），
    /// 使 bot 评估与游戏 NoSpinII（无天赋II）完全一致。由 S 命令经 c-api 设置。
    #[serde(default)]
    pub no_spin: i32,
}

pub trait Row: Copy + Clone + 'static {
    fn set(&mut self, x: usize, color: CellColor);
    fn get(&self, x: usize) -> bool;
    fn is_full(&self) -> bool;
    fn is_empty(&self) -> bool;
    fn cell_color(&self, x: usize) -> CellColor;

    const EMPTY: &'static Self;
    const SOLID: &'static Self;
}

impl<R: Row> Board<R> {
    /// Creates a blank board with an empty queue.
    pub fn new() -> Self {
        Board {
            cells: [*R::EMPTY; 40].into(),
            column_heights: [0; 10],
            combo: 0,
            b2b_bonus: false,
            btb_count: 0,
            hold_piece: None,
            next_pieces: VecDeque::new(),
            bag: EnumSet::all(),
            spawn_y: 19,
            lockout_y: 20,
            allspin_enabled: 0,
            kick_table: Vec::new(),
            kick_is_last: false,
            game_rules_enabled: false,
            last_clear_kind: 0,
            last_clear_count: 0,
            solid_rows: 0,
            no_spin: 0,
        }
    }

    /// Creates a board with existing field, remain pieces in the bag, hold piece, back-to-back status and combo count.
    /// `solid_rows` 为实心垃圾行位掩码（bit = CC 行号，0 = 底部）。
    pub fn new_with_state(
        field: [[bool; 10]; 40],
        bag_remain: EnumSet<Piece>,
        hold: Option<Piece>,
        b2b: bool,
        combo: u32,
        solid_rows: u64,
    ) -> Self {
        let mut board = Board {
            cells: [*R::EMPTY; 40].into(),
            column_heights: [0; 10],
            combo: combo,
            b2b_bonus: b2b,
            btb_count: if b2b { 1 } else { 0 },
            hold_piece: hold,
            next_pieces: VecDeque::new(),
            bag: if bag_remain.is_empty() {
                EnumSet::all()
            } else {
                bag_remain
            },
            spawn_y: 19,
            lockout_y: 20,
            allspin_enabled: 0,
            kick_table: Vec::new(),
            kick_is_last: false,
            game_rules_enabled: false,
            last_clear_kind: 0,
            last_clear_count: 0,
            solid_rows: solid_rows,
            no_spin: 0,
        };
        board.set_field(field);
        board
    }

    /// Randomly selects a piece from the bag.
    ///
    /// This function does not remove the generated piece from the bag.
    /// Use add_next_piece() to add it to the queue.
    pub fn generate_next_piece(&self, rng: &mut impl rand::Rng) -> Piece {
        use rand::prelude::*;
        let choices: ArrayVec<[_; 7]> = self.bag.iter().collect();
        *choices.choose(rng).unwrap()
    }

    /// Retrieves the next piece in the queue.
    ///
    /// If the queue is empty, returns the set of possible next pieces.
    pub fn get_next_piece(&self) -> Result<Piece, EnumSet<Piece>> {
        self.next_pieces.front().copied().ok_or(self.bag)
    }

    /// Retrieves the piece after the next piece in the queue if it is known.
    pub fn get_next_next_piece(&self) -> Option<Piece> {
        self.next_pieces.get(1).copied()
    }

    /// Adds the piece to the next queue and removes it from the bag.
    ///
    /// If the bag becomes empty, the bag is refilled.
    pub fn add_next_piece(&mut self, piece: Piece) {
        self.bag.remove(piece);
        if self.bag.is_empty() {
            self.bag = EnumSet::all();
        }
        self.next_pieces.push_back(piece);
    }

    fn remove_cleared_lines(&mut self) -> ArrayVec<[i32; 4]> {
        let mut cleared = ArrayVec::new();
        let mut new_cells: ArrayVec<[R; 40]> = ArrayVec::new();
        let mut new_solid: u64 = 0;
        let mut new_idx = 0;
        for (i, r) in self.cells.iter().enumerate() {
            let solid = ((self.solid_rows >> i as u32) & 1) != 0;
            let full = r.is_full();
            if full && !solid {
                // 满行且非实心 → 消行
                cleared.push(i as i32);
            } else {
                // 保留（含实心行，即使满也不消）；实心行随保留顺序下移
                new_cells.push(*r);
                if solid {
                    new_solid |= 1u64 << new_idx;
                }
                new_idx += 1;
            }
        }
        let cleared_count = cleared.len();
        while new_cells.len() < 40 {
            new_cells.push(*R::EMPTY);
        }
        self.cells = new_cells;
        self.solid_rows = new_solid;
        for x in 0..10 {
            self.column_heights[x] -= cleared_count as i32;
            while self.column_heights[x] > 0
                && !self.cells[self.column_heights[x] as usize - 1].get(x)
            {
                self.column_heights[x] -= 1;
            }
        }
        cleared
    }

    /// 设置实心垃圾行位掩码（bit = 本棋盘行号，0 = 底部）。
    pub fn set_solid_rows(&mut self, mask: u64) {
        self.solid_rows = mask;
    }

    pub fn occupied(&self, x: i32, y: i32) -> bool {
        x < 0 || y < 0 || x >= 10 || y >= 40 || (self.cells[y as usize].get(x as usize))
    }

    pub fn get_row(&self, y: i32) -> &R {
        if y < 0 {
            R::SOLID
        } else if y >= 40 {
            R::EMPTY
        } else {
            &self.cells[y as usize]
        }
    }

    pub fn set_cell_color(&mut self, x: i32, y: i32, color: CellColor) {
        self.cells[y as usize].set(x as usize, color);
        let h = &mut self.column_heights[x as usize];
        if color != CellColor::Empty {
            *h = (*h).max(y + 1);
        } else if *h == y + 1 {
            while *h > 0 && !self.cells[*h as usize - 1].get(x as usize) {
                *h -= 1;
            }
        }
    }

    pub fn obstructed(&self, piece: &FallingPiece) -> bool {
        piece.cells().iter().any(|&(x, y)| self.occupied(x, y))
    }

    pub fn above_stack(&self, piece: &FallingPiece) -> bool {
        piece
            .cells()
            .iter()
            .all(|&(x, y)| y >= self.column_heights[x as usize])
    }

    pub fn on_stack(&self, piece: &FallingPiece) -> bool {
        piece.cells().iter().any(|&(x, y)| self.occupied(x, y - 1))
    }

    /// Does all logic associated with locking a piece.
    ///
    /// Clears lines, detects clear kind, calculates garbage, maintains combo and back-to-back
    /// state, detects perfect clears, detects lockout.
    pub fn lock_piece(&mut self, piece: FallingPiece) -> LockResult {
        let mut locked_out = true;
        // allspin 规则：非T方块卡住（全向封堵）→ 根据 allspin_enabled 模式判定：
        //   0 = allmini：判为 mini spin（效果/伤害与 T mini 一致）
        //   1 = allspin ：判为 full spin（效果/伤害与 T-Spin 一致）
        //   其他 = 未来扩展，暂不判定
        // 必须在放置前检查（此时方块尚未写入棋盘，避免自重叠误判）。
        let non_t_stuck = piece.kind.0 != Piece::T
            && piece.tspin == TspinStatus::None
            && self.piece_is_stuck(&piece);
        for &(x, y) in &piece.cells() {
            self.cells[y as usize].set(x as usize, piece.kind.0.color());
            if self.column_heights[x as usize] < y + 1 {
                self.column_heights[x as usize] = y + 1;
            }
            if y < self.lockout_y as i32 {
                locked_out = false;
            }
        }
        let cleared = self.remove_cleared_lines();

        let mut placement_kind = if non_t_stuck {
            match self.allspin_enabled {
                0 => PlacementKind::get(cleared.len(), TspinStatus::Mini),
                1 => PlacementKind::get(cleared.len(), TspinStatus::Full),
                _ => PlacementKind::get(cleared.len(), piece.tspin),
            }
        } else {
            PlacementKind::get(cleared.len(), piece.tspin)
        };
        // no_spin=2（Talentless 无天赋II）：不判定任何 spin，所有 spin 归一化为普通消行。
        // 由此 b2b（仅 4 行四消维持）、伤害表（基础表）、allspin 标志等与游戏 NoSpinII 完全一致。
        if self.no_spin == 2 {
            placement_kind = PlacementKind::get(cleared.len(), TspinStatus::None);
        }

        let mut garbage_sent = placement_kind.garbage();

        // 记录本次落块前的 BTB 计数（对应游戏 _calculate_damage 时的 btb_count，
        // 用于“btb>=4 时 btb 加成额外 +1”）。
        let btb_count_before: u32 = self.btb_count;

        let mut did_b2b = false;
        if placement_kind.is_clear() {
            if placement_kind.is_hard() {
                if self.b2b_bonus {
                    garbage_sent += 1;
                    did_b2b = true;
                    self.btb_count += 1;  // 连续 spin/quad：BTB 计数递增
                } else {
                    self.btb_count = 1;   // 首次 spin/quad：开始计数
                }
                self.b2b_bonus = true;
            } else {
                self.b2b_bonus = false;
                self.btb_count = 0;
            }

            if self.combo as usize >= COMBO_GARBAGE.len() {
                garbage_sent += COMBO_GARBAGE.last().unwrap();
            } else {
                garbage_sent += COMBO_GARBAGE[self.combo as usize];
            }

            self.combo += 1;
        } else {
            self.combo = 0;
        }

        let perfect_clear = self.column_heights == [0; 10];
        if perfect_clear {
            garbage_sent = 10;
        }

        // allspin 判定：所有非T方块做出的 spin（不论 mini 还是 full）都标记为 allspin。
        // 评估器据此统一使用 allspin 权重（只按消行数区分），不区分是否 mini。
        let allspin = piece.kind.0 != Piece::T
            && matches!(
                placement_kind,
                PlacementKind::Tspin
                    | PlacementKind::Tspin1
                    | PlacementKind::Tspin2
                    | PlacementKind::Tspin3
                    | PlacementKind::MiniTspin
                    | PlacementKind::MiniTspin1
                    | PlacementKind::MiniTspin2
            );

        // allspin 重复惩罚：本次消行与上次完全一致（同 spin 类型 + 同行数）→ 触发规则惩罚。
        // 完全参与计算（不依赖 allspin_enabled 开关），复刻游戏 check_and_clear_lines 的 is_allspin_repeat。
        let clear_count = cleared.len();
        let is_allspin_repeat = clear_count > 0
            && clear_count as i32 == self.last_clear_count
            && Self::spin_type_key(placement_kind, piece.kind.0) == self.last_clear_kind;

        // 更新“上次消行”信息（供下次重复惩罚比对）
        self.last_clear_kind = if clear_count > 0 {
            Self::spin_type_key(placement_kind, piece.kind.0)
        } else {
            0
        };
        self.last_clear_count = clear_count as i32;

        let l = LockResult {
            placement_kind,
            garbage_sent,
            perfect_clear,
            locked_out,
            combo: if self.combo == 0 {
                None
            } else {
                Some(self.combo - 1)
            },
            b2b: did_b2b,
            btb_count: btb_count_before,
            cleared_lines: cleared,
            allspin,
            allspin_repeat: is_allspin_repeat,
        };

        l
    }

    /// 计算游戏 _detect_spin_type 的 spin 类型键（供 allspin 重复惩罚比对）。
    /// 0=无 spin；1=T-Spin；2=Mini T-Spin；3..=8=全旋(I/O/L/J/S/Z)；13..=18=Mini非T(I/O/L/J/S/Z)。
    fn spin_type_key(placement_kind: PlacementKind, piece: Piece) -> i32 {
        match placement_kind {
            PlacementKind::Tspin | PlacementKind::Tspin1 | PlacementKind::Tspin2 | PlacementKind::Tspin3 => {
                if piece == Piece::T {
                    1
                } else {
                    // 非T全旋：按方块类型区分（I/O/L/J/S/Z）
                    3 + Self::spin_piece_index(piece)
                }
            }
            PlacementKind::MiniTspin | PlacementKind::MiniTspin1 | PlacementKind::MiniTspin2 => {
                if piece == Piece::T {
                    2
                } else {
                    13 + Self::spin_piece_index(piece)
                }
            }
            _ => 0,
        }
    }

    /// 非T方块在 spin_type 键中的序号（I=0, O=1, L=2, J=3, S=4, Z=5）。
    fn spin_piece_index(piece: Piece) -> i32 {
        match piece {
            Piece::I => 0,
            Piece::O => 1,
            Piece::L => 2,
            Piece::J => 3,
            Piece::S => 4,
            Piece::Z => 5,
            Piece::T => 0,
        }
    }

    /// 判断方块是否被“卡住”：四个方向（上/下/左/右）均被占位或边界。
    /// 用于 allspin 规则的非T全旋判定（复刻游戏 _is_piece_stuck）。
    pub(crate) fn piece_is_stuck(&self, piece: &FallingPiece) -> bool {
        let dirs = [(-1i32, 0i32), (1, 0), (0, 1), (0, -1)];
        for (dx, dy) in dirs {
            let mut probe = *piece;
            probe.x += dx;
            probe.y += dy;
            if !self.obstructed(&probe) {
                return false;
            }
        }
        true
    }

    /// Holds the passed piece, returning the previous hold piece.
    ///
    /// If there is a piece in hold, it is returned.
    pub fn hold(&mut self, piece: Piece) -> Option<Piece> {
        let hold = self.hold_piece;
        self.hold_piece = Some(piece);
        hold
    }

    pub fn next_queue<'a>(&'a self) -> impl DoubleEndedIterator<Item = Piece> + 'a {
        self.next_pieces.iter().copied()
    }

    /// Returns the piece that should be spawned, or None if the queue is empty.
    pub fn advance_queue(&mut self) -> Option<Piece> {
        self.next_pieces.pop_front()
    }

    pub fn column_heights(&self) -> &[i32; 10] {
        &self.column_heights
    }

    pub fn add_garbage(&mut self, col: usize) -> bool {
        let mut row = *R::EMPTY;
        for x in 0..10 {
            if x == col {
                if self.column_heights[x] != 0 {
                    self.column_heights[x] += 1;
                }
            } else {
                row.set(x, CellColor::Garbage);
                self.column_heights[x] += 1;
            }
        }
        let dead = self.cells.pop().map_or(false, |r| !r.is_empty());
        self.cells.insert(0, row);
        dead
    }

    pub fn to_compressed(&self) -> Board {
        Board {
            cells: self
                .cells
                .iter()
                .map(|r| {
                    let mut row = 0;
                    for x in 0..10 {
                        row.set(x, r.cell_color(x));
                    }
                    row
                })
                .collect(),
            b2b_bonus: self.b2b_bonus,
            combo: self.combo,
            btb_count: self.btb_count,
            column_heights: self.column_heights,
            next_pieces: self.next_pieces.clone(),
            hold_piece: self.hold_piece,
            bag: self.bag,
            spawn_y: self.spawn_y,
            lockout_y: self.lockout_y,
            allspin_enabled: self.allspin_enabled,
            kick_table: self.kick_table.clone(),
            kick_is_last: self.kick_is_last,
            game_rules_enabled: self.game_rules_enabled,
            last_clear_kind: self.last_clear_kind,
            last_clear_count: self.last_clear_count,
            solid_rows: self.solid_rows,
            no_spin: self.no_spin,
        }
    }

    pub fn set_field(&mut self, field: [[bool; 10]; 40]) {
        self.cells.clear();
        self.column_heights = [0; 10];
        for y in 0..40 {
            let mut r = *R::EMPTY;
            for x in 0..10 {
                if field[y][x] {
                    r.set(x, CellColor::Garbage);
                    self.column_heights[x] = y as i32 + 1;
                }
            }
            self.cells.push(r)
        }
    }

    pub fn get_field(&self) -> [[bool; 10]; 40] {
        let mut field = [[false; 10]; 40];
        for y in 0..40 {
            for x in 0..10 {
                field[y][x] = self.occupied(x as i32, y as i32)
            }
        }
        field
    }

    pub fn next_bag(&self) -> EnumSet<Piece> {
        let mut bag = self.bag;
        for p in self.next_queue().rev() {
            if bag == EnumSet::all() {
                bag = EnumSet::empty();
            }
            bag.insert(p);
        }
        bag
    }
}

impl Row for u16 {
    fn set(&mut self, x: usize, color: CellColor) {
        if color == CellColor::Empty {
            *self &= !(1 << x);
        } else {
            *self |= 1 << x;
        }
    }

    #[inline]
    fn get(&self, x: usize) -> bool {
        *self & (1 << x) != 0
    }

    fn is_full(&self) -> bool {
        self == Self::SOLID
    }

    fn is_empty(&self) -> bool {
        self == Self::EMPTY
    }

    fn cell_color(&self, x: usize) -> CellColor {
        if self.get(x) {
            CellColor::Garbage
        } else {
            CellColor::Empty
        }
    }

    const SOLID: &'static u16 = &0b11111_11111;
    const EMPTY: &'static u16 = &0;
}

#[derive(Copy, Clone, Debug)]
pub struct ColoredRow([CellColor; 10]);

impl Default for ColoredRow {
    fn default() -> Self {
        ColoredRow([CellColor::Empty; 10])
    }
}

impl Row for ColoredRow {
    fn set(&mut self, x: usize, color: CellColor) {
        self.0[x] = color;
    }

    fn get(&self, x: usize) -> bool {
        self.0[x] != CellColor::Empty
    }

    fn is_full(&self) -> bool {
        self.0.iter().all(|&c| c != CellColor::Empty)
    }

    fn cell_color(&self, x: usize) -> CellColor {
        self.0[x]
    }

    fn is_empty(&self) -> bool {
        self.0.iter().all(|&c| c == CellColor::Empty)
    }

    const SOLID: &'static Self = &ColoredRow([CellColor::Unclearable; 10]);
    const EMPTY: &'static Self = &ColoredRow([CellColor::Empty; 10]);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fill_row(board: &mut Board<u16>, y: i32) {
        for x in 0..10 {
            board.set_cell_color(x, y, CellColor::Garbage);
        }
    }

    #[test]
    fn solid_row_full_is_not_cleared() {
        // 行 0 标记实心且填满：即使整行填满也不消行。
        let mut board = Board::<u16>::new();
        board.set_solid_rows(1); // bit 0 = 行 0 实心
        fill_row(&mut board, 0);
        // 行 1 也填满（普通可消行）
        fill_row(&mut board, 1);
        let cleared = board.remove_cleared_lines();
        // 只消行 1，实心行 0 保留
        assert_eq!(cleared.len(), 1);
        assert_eq!(cleared[0], 1);
        assert!(board.occupied(0, 0), "实心行应保留（即使填满）");
        assert_eq!(board.solid_rows, 1);
    }

    #[test]
    fn solid_row_shifts_down_when_above_line_cleared() {
        // 行 1 实心；行 0（上方普通行）填满可消 → 实心行随之下移到行 0。
        let mut board = Board::<u16>::new();
        board.set_solid_rows(1 << 1); // bit 1 = 行 1 实心
        fill_row(&mut board, 0); // 行 0 满（可消）
        fill_row(&mut board, 1); // 行 1 实心满（不可消）
        let cleared = board.remove_cleared_lines();
        assert_eq!(cleared.len(), 1);
        assert_eq!(cleared[0], 0);
        // 实心行从行 1 下移到行 0，掩码同步
        assert_eq!(board.solid_rows, 1);
        assert!(board.occupied(0, 0), "实心行应下移到行 0");
    }
}
