extends Node
class_name TetrisClearLine

## 俄罗斯方块消行控制器
## 负责检测和消除完整行，并显示消行动画/文本
## 需要其它节点时一律通过公共数据区 TetrisGlobalData 取用（见 tetris_global_data.gd）。

# 消行配置（注：原先的 clear_animation_duration 无人读取，已删除）
@export var clear_text_display_duration: float = 2.0  # 消行文本显示持续时间（秒）

# 消行延迟时间（秒）：>0 时先播放消行动画（持续 clear_line_delay_time），动画结束后才生成新方块；0 表示无延迟
@export var clear_line_delay_time: float = 0.0

# 消行延迟状态
var clear_line_delay_timer: Timer  # 消行延迟计时器
var _pending_clear_lines: Array = []  # 待清除的行（延迟期间仍物理存在，延迟结束后才位移清除）
# 是否正在播放消行动画（延迟中）→ 已提到公共数据区 TetrisGlobalData.clear_animating_active，
## 供方块控制器（还不能出块）与垃圾行控制器（上涨要暂缓）读
var _pending_clear_count: int = 0     # 延迟期间记下本次要消的行数（计时器回调发布结果时用）
var _pending_spin_type: String = ""   # 延迟期间记下本次 Spin 类型（同上）

# 文本打印器配置（非BTB文本：半透明、向左漂移、自然淡出消失）
@export var text_base_opacity: float = 0.8          # 文本显示时的透明度（半透明，0-1）
@export var text_fade_duration: float = 1.0         # 文本淡出时长（秒）
@export var text_drift_cells_per_sec: float = 1.5   # 文本向左漂移速度（格子/秒）
@export var text_gap_cells: float = 1.8             # 文本与版面左边框的间距（格子数）

# 消行/Spin 文本的漂移与淡出倍率（相对默认值的修正：移动略快、淡出更快）
@export var clear_spin_drift_scale: float = 3.0     # 消行/Spin 漂移速度倍率（>1 为更快）
@export var clear_spin_fade_scale: float = 0.2      # 消行/Spin 淡出时长倍率（<1 为淡出更快/更短）
@export var clear_spin_hold_scale: float = 0.15     # 消行/Spin 淡出触发前的保持时间倍率（越小淡出越早、与移动并行）

# 消行文本配置
@export var clear_text_color: Color = Color.WHITE  # 消行文本颜色
@export var clear_text_outline_color: Color = Color.BLACK  # 消行文本描边颜色
## Allspin_2 的 VOID 文本颜色（用灰色与普通消行文本区分开）
@export var void_text_color: Color = Color(0.6, 0.6, 0.6)
@export var clear_text_offset_y_cells: float = 2  # 消行文本相对于Hold框底部的偏移（格子数）

# Spin类型判定配置
@export var spin_detection_enabled: bool = true  # 是否启用Spin检测
@export var spin_text_outline_color: Color = Color.BLACK  # Spin文本描边颜色
@export var spin_text_offset_y_cells: float = 1  # Spin文本相对于消行文本的偏移（格子数，负值向上）

# 连击配置
@export var combo_text_color: Color = Color.CYAN  # 连击文本颜色
@export var combo_text_outline_color: Color = Color.BLACK  # 连击文本描边颜色
@export var combo_text_offset_y_cells: float = 1  # 连击文本相对于消行文本的偏移（格子数，正值向下）

# BTB配置
@export var btb_text_color: Color = Color.MAGENTA  # BTB文本颜色
@export var btb_text_outline_color: Color = Color.BLACK  # BTB文本描边颜色
@export var btb_text_offset_y_cells: float = 4.5  # BTB文本相对于Hold框底部的偏移（格子数，正值向下）

# BTB 系统选择（仅影响 BTB 加成数值，具体见 _get_btb_bonus()）
# 可由 buff 切换：extra_data_dict["BtbBonus"]（buff「Btb奖励」BtbBonus_1 → 2），
# 由 TetrisGlobalData.apply_init_data() 填入。
#   1 = surge break 系统（现有系统）：连续 4消/Spin 从第 2 手起 +1（与界面显示的 "1 x BTB" 对齐），
#       btb_count >= 4 时 +2（**该 +2 档需开启 Allspin_2，否则最高 +1**）；长链被普通消行打断时另结算 surge break 伤害
#   2 = 累加奖励系统（tetr.io S1 的 BTB 伤害系统）：BTB=btb_count，BTB=1 → +1；
#       BTB>=2 → 1+ln(0.8*BTB+1) 取整后小数部分折算为 (1+b)/3；
#       无 surge break 兑现（断链不额外结算伤害）

# PC（Perfect Clear）配置
@export var pc_text_color: Color = Color.GOLD  # PC文本颜色
@export var pc_text_outline_color: Color = Color.BLACK  # PC文本描边颜色
@export var pc_text_offset_y_cells: float = 3.5  # PC文本相对于Hold框底部的偏移（格子数，正值向下）

# 伤害累积配置（累积伤害只用于击杀奖励结算与 Spike 数字的重置窗口，不再有独立文本显示）
@export var damage_display_duration: float = 1.0  # 伤害累积窗口（秒）：击杀奖励结算与 Spike 数字重置都按它

# 消行文本映射
var clear_texts: Dictionary = {
	1: "SINGLE",
	2: "DOUBLE",
	3: "TRIPLE",
	4: "QUAD"
}

# 基础伤害表（按消行数）
var base_damage_table: Dictionary = {
	0: 0,
	1: 0,
	2: 1,
	3: 2,
	4: 4
}

# Spin伤害表（优先于基础伤害表）
var spin_damage_table: Dictionary = {
	"T-Spin": {
		1: 2,
		2: 4,
		3: 6
	},
	"Mini T-Spin": {
		1: 1
	}
}

# All-Spin 伤害表
# 默认规则不使用该表
var allspin_damage_table: Dictionary = {
	1: 4,
	2: 6,
	3: 8
}

# 连击表（默认使用公式而不使用该表）
var combo_damage_list: Array = [
	0,  #无连击
	0,  # 1连击
	0,  # 2连击
	1,  # 3连击
	1,  # 4连击
	1,  # 5连击
	2,  # 6连击
	2,  # 7连击
	3,  # 8连击
	3,  # 9连击
	4,  # 10连击
	4   # 11连击及以上
]

# 连击计算方式：0=旧连击表（combo_damage_list），1=新公式（默认）：
#   combo_damage = floor(max(ln(1+1.25*combo), ((is_btb_active?1:0)+attack)*(1+0.25*combo)))
#   其中 attack = 本次消行的 base+spin（不含BTB加成）
var combo_formula: int = 1

# Spin伤害加成（注：原先的 spin_damage_multiplier 字典无人读取，已删除）

# 状态变量
var lines_to_clear: Array = []
var clear_text_position: Vector2 = Vector2.ZERO
var spin_text_position: Vector2 = Vector2.ZERO
var combo_text_position: Vector2 = Vector2.ZERO
var btb_text_position: Vector2 = Vector2.ZERO

# 连击和BTB状态
var is_btb_active: bool = false
var spin0_btb_enabled: bool = false  # Spin0是否触发BTB（由buff控制；Allspin_2 也会强制启用）
## Allspin 模式：0 = 关闭；1 = Allspin_1（同类型同行数 → 上涨 1 行普通垃圾）；
## 2 = Allspin_2（非 spin 消行记 void：无攻击且断 BTB；Spin0 判伤害并使 BTB+1；
##     有效行数与上次相同 → 上涨 allspin2_solid_rows 行实心垃圾）
## 3 = Allspin_3（在 2 的基础上再禁止「消行类型重复」：本手落块件类型与上次相同也算重复，
##     惩罚行数与 2 一致）
## 4 = Allspin_4（类型规则改成「六块每轮各消一遍」：Z/S/T/I/J/L 各消过一次才会解锁该轮，
##     轮内再消同一块 → 重复（罚 allspin_round_solid_rows = 42 行实心 ≈ 判死）；
##     同时保留「与上一手重复」惩罚：有效行数相同（Allspin_2 同款，含 void/-1 与 Spin0/0）
##     或落块件类型相同（Allspin_3 同款）→ 20 行实心；
##     surge 的 +2 档提升为 +3）
## 5 = Allspin_5（在 4 的基础上，把有效行数也纳入同样的「轮」：0/1/2 行各一遍、集齐即解禁；
##     3 行单独成组（等于不参与轮约束），与 4 行及以上一样只参与「与上一手重复」；
##     spin 伤害改为「行数 × 3」）
var allspin_round_solid_rows: int = 42
## Allspin_4/5 的「轮」成员：六个可 spin 的方块（O 不判 Spin，不参与）
const ALLSPIN_ROUND_TYPES: Array = ["Z", "S", "T", "I", "J", "L"]
## Allspin_5 的「行数轮」：**0/1/2/3 行**各一遍（集齐即解禁）。
## 4 行及以上不参与行数轮，只参与「与上一手重复」判断。
const ALLSPIN_ROUND_COUNTS: Array = [0, 1, 2, 3]
## 当前这一轮里已经消过的成员（类型轮 / 行数轮各一份，互相独立）
var _allspin_round_used_types: Array = []
var _allspin_round_used_counts: Array = []
## Void（非 spin 普通消行）的名字：消行文本显示 VOID 用它。
## Allspin_2/3/4 下 Void 记 type="void"、行数 -1，**正常参与重复判定**（连续两次 Void 同样吃惩罚）；
## Allspin_5 下 Void 完全不参与重复判定（不触发惩罚、不写记录、不进任何轮）。
const ALLSPIN2_VOID_TYPE: String = "void"
## Allspin_2/3 的「行数重复」判定：本次**有效行数**是否与上一次记录相同。
##   · 普通消行 = 消掉的行数；Spin0 = 0；
##   · Void 不参与（调用方在 is_void 时直接返回不重复）；
##   · 只有「完全没有上一次记录」（开局，_last_clear_type 为空）时才不算重复。
func _is_allspin2_repeat(effective_count: int) -> bool:
	if TetrisGlobalData.clear_allspin < 2:
		return false
	if _last_clear_type.is_empty():
		return false
	return effective_count == _last_clear_count


## Allspin_4/5 的「轮」推进：key 已在本轮出现过 → 判重复（并把该轮重置为「只剩本手」）；
## 否则记入本轮，集满 key_total 个成员后自动开启新一轮（即「各消一遍就能重新开始重复」）。
func _allspin_round_step(used: Array, key: int, key_total: int) -> bool:
	if used.has(key):
		used.clear()
		used.append(key)
		return true
	used.append(key)
	if used.size() >= key_total:
		used.clear()
	return false


## 清空 Allspin_4/5 的轮记录（重开局 / 换关卡时调用）
func reset_allspin_rounds() -> void:
	_allspin_round_used_types.clear()
	_allspin_round_used_counts.clear()


## Allspin_5 的 Void 补偿：每次 Void 让塔的发送倍率槽 extra_pressure_mult +0.01
## （该槽由 get_pressure_mult() 计入发送攻击；默认 1.0，加满与否只影响塔打出去的量）。
const VOID_PRESSURE_BONUS: float = 0.01
func _add_void_pressure_bonus() -> void:
	var tower = TetrisGlobalData.tower_controller
	if tower == null:
		return
	tower.extra_pressure_mult += VOID_PRESSURE_BONUS


## 对外：当前旋转记录判定出的 Spin 类型（"" = 不是 Spin）。供闪光反馈等只读场景使用。
func get_current_spin_type() -> String:
	return _detect_spin_type()


## 预测：这一手（给定 spin 类型 / 消行数 / 落块件）**是否会触发重复惩罚**。
## 与 _allspin_repeat_result 用同一套判据，但**只查询、不推进任何轮状态**
## （_allspin_round_step 会改轮，这里不能用）。
## 供 TetrisController 在「旋转后判定到 Spin」时决定闪白光还是红光。
func would_allspin_penalize(spin_type: String, clear_count: int, piece_type: String) -> bool:
	var mode: int = TetrisGlobalData.clear_allspin
	if mode < 1 or spin_type.is_empty():
		return false
	# Allspin_2/3/4/5：与上一手重复（有效行数相同；3 及以上还看落块件是否与上一手相同）
	if mode >= 2:
		if _is_allspin2_repeat(clear_count):
			return true
		if mode >= 3 and not piece_type.is_empty() and piece_type == _last_clear_piece_type:
			return true
		# Allspin_4/5：类型轮 / 行数轮里已经出现过 → 再消就是轮内重复
		if mode >= 4:
			var ti: int = ALLSPIN_ROUND_TYPES.find(piece_type)
			if ti >= 0 and _allspin_round_used_types.has(ti):
				return true
			if mode >= 5 and ALLSPIN_ROUND_COUNTS.has(clear_count) and _allspin_round_used_counts.has(clear_count):
				return true
		return false
	# Allspin_1：类型 + 行数都与上一手完全一致
	return clear_count == _last_clear_count and spin_type == _last_clear_type


## Allspin_5 顶部行数指示（N/S/D/T）：该「有效行数」现在做 Spin 消行是否会被判重复惩罚。
## 只查询、不改轮状态；非 Allspin_5 恒为 false（指示不启用）。
func allspin5_count_penalized(clear_count: int) -> bool:
	if TetrisGlobalData.clear_allspin != 5:
		return false
	# 行数轮里已经出现过 → 轮内重复（42 行）
	if ALLSPIN_ROUND_COUNTS.has(clear_count) and _allspin_round_used_counts.has(clear_count):
		return true
	# 与上一手有效行数相同 → 上一次重复（20 行）
	return _is_allspin2_repeat(clear_count)


## Allspin 重复判定统一入口（2/3/4/5；Allspin_1 另有规则，不在这里）。
## 返回值：[是否重复, 惩罚行数]
##   · spin_type 为空 = 非 spin 消行（2 及以上记 Void）：
##     **Allspin_2/3/4 的 Void 正常参与重复惩罚**（行数记 -1，连续两次 Void 也算重复）；
##     **只有 Allspin_5 的 Void 完全不参与**（不触发惩罚、不写记录、不进任何轮）
##   · clear_count == 0 且 spin_type 非空 = Spin0（有效行数 0）：
##     Allspin_5 下属于行数轮（0/1/2/3 组），同时在「与上一手重复」里也按 0 比较
func _allspin_repeat_result(spin_type: String, clear_count: int, piece_type: String) -> Array:
	var mode: int = TetrisGlobalData.clear_allspin
	var is_spin: bool = not spin_type.is_empty()
	var is_void: bool = (mode >= 2 and not is_spin)
	# Allspin_5 的 Void：不参与重复判定（既不算重复，也不推进任何轮）
	if is_void and mode >= 5:
		return [false, 0]
	var eff: int = -1 if is_void else clear_count
	if mode >= 4:
		var repeated: bool = false
		var rows: int = allspin_round_solid_rows
		# 类型轮：只有 spin 消行参与（void 不属于六块之一）
		if is_spin:
			var ti: int = ALLSPIN_ROUND_TYPES.find(piece_type)
			if ti >= 0 and _allspin_round_step(_allspin_round_used_types, ti, ALLSPIN_ROUND_TYPES.size()):
				repeated = true
		# 行数轮（仅 Allspin_5）：0/1/2/3 行各一遍，集齐即解禁。
		# 4 行及以上不参与行数轮，只走上一次重复。
		if mode >= 5 and ALLSPIN_ROUND_COUNTS.has(eff):
			if _allspin_round_step(_allspin_round_used_counts, eff, ALLSPIN_ROUND_COUNTS.size()):
				repeated = true
		# Allspin_4/5 还保留「与上一手重复」这一档（Allspin_2/3 同款）：
		#   · 有效行数与上一手相同（Spin0 记 0 → 连续两次 Spin0 也算）；
		#   · 落块件类型与上一手相同（例：…-Z-S-S，第二个 S 就是重复）。
		# 力度按 Allspin_2 的 allspin2_solid_rows（默认 20 行）；轮违规更重（42 行），
		# 所以两类同时命中时取轮的那一档。
		if not repeated:
			var same_as_last: bool = _is_allspin2_repeat(eff)
			if not same_as_last and not piece_type.is_empty() and piece_type == _last_clear_piece_type:
				same_as_last = true
			if same_as_last:
				repeated = true
				rows = TetrisGlobalData.clear_allspin2_solid_rows
		return [repeated, rows]
	if mode == 3:
		var rep3: bool = _is_allspin2_repeat(eff)
		# 类型重复：本手落块件与上一手相同（void 与 void 也会命中，但惩罚只结算一次）
		if not rep3 and not piece_type.is_empty() and piece_type == _last_clear_piece_type:
			rep3 = true
		return [rep3, TetrisGlobalData.clear_allspin2_solid_rows]
	if mode == 2:
		return [_is_allspin2_repeat(eff), TetrisGlobalData.clear_allspin2_solid_rows]
	return [false, 0]


## Allspin 重复惩罚触发时的调试输出：说明这次是「哪一种重复」。
##   Allspin_1：同「消行类型 + 行数」→ 涨 1 行普通垃圾
##   Allspin_2：同「有效行数」（普通=N / Spin0=0 / void=-1，不比类型）→ 涨 allspin2_solid_rows 行实心垃圾
func _debug_log_allspin_repeat(cur_spin: String, cur_clear: int, is_void: bool) -> void:
	var cur_eff: int = -1 if is_void else cur_clear
	var prev_kind: String = _last_clear_type
	if _last_clear_type == "":
		prev_kind = "（无记录）"
	if _last_clear_count == -1:
		prev_kind += "(void)"
	elif _last_clear_count == 0:
		prev_kind += "(Spin0)"
	# 档位名按实际模式输出（原来 3/4/5 档会被误标成 Allspin_1/2）
	var _am: int = TetrisGlobalData.clear_allspin
	var mode: String = "Allspin_1 类型+行数重复"
	if _am == 2:
		mode = "Allspin_2 行数重复"
	elif _am == 3:
		mode = "Allspin_3 行数重复 或 同块重复"
	elif _am >= 4:
		mode = "Allspin_%d 轮内重复(42) 或 与上一手重复(20)" % _am
	var tgt := "?"
	if TetrisGlobalData.tetris_controller != null:
		var bridge = TetrisGlobalData.tetris_controller.get("_zzz_bridge")
		if bridge != null and bridge.has_method("get_plan_target"):
			var t: Dictionary = bridge.get_plan_target()
			if not t.is_empty() and bool(t.get("valid", false)):
				tgt = "%s(%d,%d) rot=%d" % [t.get("piece", "?"), int(t["x"]), int(t["y"]), int(t["rot"])]
			else:
				tgt = "invalid"
	push_warning("[AllspinRepeat] %s → 触发惩罚 | 本手: piece=%s spin=%s clear=%d 有效行数=%d | 上一手记录: %s 行数=%d 落块件=%s | 旋转系统=%d 旋转件=%s 有旋转=%s 卡住=%s | bot决策落点=%s" % [
		mode, _current_locked_piece_type(), cur_spin, cur_clear, cur_eff,
		prev_kind, _last_clear_count, _last_clear_piece_type,
		int(TetrisGlobalData.piece_rotation_system) if TetrisGlobalData.tetris_controller != null else -1,
		last_rotation_piece_type, str(last_rotation_occurred),
		str(_is_piece_stuck(last_rotation_piece_shape, last_rotation_position)), tgt])


## Allspin 重复惩罚：上涨 rows 行实心垃圾（不可消除）。
## Allspin_2/3 是 allspin2_solid_rows（默认 20）；Allspin_4/5 是 allspin_round_solid_rows（默认 42 ≈ 直接判死）。
func _apply_allspin_repeat_penalty(rows: int) -> void:
	if TetrisGlobalData.garbage_line_controller == null or rows <= 0:
		return
	TetrisGlobalData.solid_garbage_requested.emit(rows, true)

# ---- bot 评估权重（可由 buff 界面调整，经 bridge 的 S 命令下发到 ColdClear）----
# 维持 BTB 的评估权重（越大 bot 越倾向于维持 back-to-back）
var bot_b2b_clear: int = 200
# 放块后的堆叠最高点权重（bot 评估：height × 最高点，负值=压高）
var bot_height: int = -39
# 四消（Tetris）的评估权重（越小 bot 越不倾向做四消）
var bot_clear4: int = 260
# allspin_1 重复惩罚的评估扣分（负值=降低选取值，可 buff 调整）
var bot_allspin_repeat_penalty: int = -120
## allspin_2 重复惩罚的评估扣分：惩罚是「行数相同 → 20 行实心垃圾」，后果远重于 allspin_1，
## 所以默认给一个更大的负值，让 bot 也主动避免重复行数。
# 各类型消行/旋转的评估权重（默认=bridge 导出值，可由 buff 传参覆盖，经 bridge 下发）
var bot_eval_mult: int = 100
var bot_attack_efficiency_weight: int = 100
var bot_clear1: int = -163
var bot_clear2: int = -130
var bot_clear3: int = -78
var bot_tspin1: int = 221
var bot_tspin2: int = 410
var bot_tspin3: int = 202
var bot_mini_tspin1: int = -158
var bot_mini_tspin2: int = -393
var bot_allspin1: int = 221
var bot_allspin2: int = 410
var bot_allspin3: int = 202
var bot_allspin3plus: int = 202
var bot_perfect_clear: int = 199
var bot_combo_garbage: int = 170
var bot_wasted_t: int = -102
var bot_move_time: int = -3
# bot 并行搜索线程数（buff 可调；0 = 由 bridge 自动决定）
var bot_threads: int = 0

# Allspin：记录上次消行类型和行数（用于下一次消行时比对）
var _last_clear_type: String = ""    # 上次消行类型（如"T-Spin"、"Mini T-Spin"、"I-Spin"、""等）
var _last_clear_count: int = 0       # 上次消行行数
## 上次消行所用的方块类型（T/S/Z/J/L/I/O）。Allspin 重复惩罚的预警要用它：
## spin 类型字符串里其实已经带了方块类型（"S-Spin"/"Mini S-Spin"…），但非 spin 消行（""）不带，
## 所以这里单独记一份，让「同类型的这一块可能复现上次消行」的预警对普通消行也成立。
var _last_clear_piece_type: String = ""

# PC状态
var pc_text_position: Vector2 = Vector2.ZERO

# 伤害累积系统
var accumulated_damage: int = 0          # 累积的伤害值
var damage_timer: Timer                  # 伤害计时器
var damage_pending: bool = false         # 是否有待显示的伤害

# 旋转记录
var last_rotation_occurred: bool = false
var last_rotation_piece_type: String = ""
var last_rotation_piece_shape: Array = []
var last_rotation_position: Vector2i = Vector2i.ZERO

# Spin颜色系统
var display_spin_color: Color = Color.YELLOW
var pending_spin_color: Color = Color.WHITE
var spin_color_ready: bool = false

# 当前消行的伤害值
var current_damage: int = 0
var has_cleared_lines: bool = false

func _enter_tree() -> void:
	# 自注册到公共数据区（整棵场景树的 _enter_tree 都先于任何 _ready 完成）
	TetrisGlobalData.register_node(self)

func _exit_tree() -> void:
	TetrisGlobalData.unregister_node(self)

func _ready():
	# Spike 的累加窗口必须与「Attack 累积伤害」同一口径（damage_display_duration）：
	# 两者窗口不同时（例如 Spike 1.0s / Attack 1.5s），间隔落在两者之间的攻击会让
	# 「N Attack」继续累加而 Spike 数字已重置，导致显示的数字对不上。
	if TetrisGlobalData.spike_display:
		TetrisGlobalData.spike_reset_time = damage_display_duration
	
	# 创建伤害计时器
	damage_timer = Timer.new()
	damage_timer.wait_time = damage_display_duration
	damage_timer.one_shot = true
	damage_timer.timeout.connect(_on_damage_timer_timeout)
	add_child(damage_timer)
	
	# 创建消行延迟计时器（wait_time 在启动时按 clear_line_delay_time 设置）
	clear_line_delay_timer = Timer.new()
	clear_line_delay_timer.one_shot = true
	clear_line_delay_timer.timeout.connect(_on_clear_line_delay_timeout)
	add_child(clear_line_delay_timer)
	
	# 落块 → 判定的通知：方块控制器锁定方块后 emit，本节点订阅并做消行判定。
	# （落块信息从公共区读：piece_last_locked_cells / piece_last_locked_type / 旋转记录是本节点自己的）
	TetrisGlobalData.piece_locked.connect(check_and_clear_lines)
	
	# 上报就绪：当场景内所有节点都就绪后，公共数据区会通知各节点读走自己的 buff 参数
	TetrisGlobalData.notify_node_ready(self)

## 读取公共区域里属于消行控制器的关卡 / buff 参数（谁用谁读：公共区域不认这些键名）。
func apply_init_params() -> void:
	# Spin0 是否触发 BTB（buff 可切；Allspin_2 也会强制启用）
	if TetrisGlobalData.init_has("spin0_btb_enabled"):
		spin0_btb_enabled = TetrisGlobalData.get_init_bool("spin0_btb_enabled", spin0_btb_enabled)
	# BtbBonus（Btb奖励）：1 = surge break 系统（默认）/ 2 = 累加奖励系统（tetr.io S1 的 BTB 伤害系统）
	if TetrisGlobalData.init_has("BtbBonus"):
		TetrisGlobalData.clear_btb_system_use = TetrisGlobalData.get_init_int("BtbBonus", TetrisGlobalData.clear_btb_system_use)
	# ClearDelay（掉落延迟 buff 的「消行延迟」）：>0 时先播放消行动画，动画结束才生成新方块
	if TetrisGlobalData.init_has("ClearDelay"):
		clear_line_delay_time = TetrisGlobalData.get_init_float("ClearDelay", clear_line_delay_time)
	# Allspin 规则（Allspin_1 / Allspin_2）
	if TetrisGlobalData.init_has("tetris_allspin"):
		TetrisGlobalData.clear_allspin = TetrisGlobalData.get_init_int("tetris_allspin", TetrisGlobalData.clear_allspin)
	# bot 并行搜索线程数（0 = 由 bridge 自动决定）
	if TetrisGlobalData.init_has("bot_threads"):
		bot_threads = TetrisGlobalData.get_init_int("bot_threads", bot_threads)
	# NoSpin（Spin判定）：0=正常（含Allspin）；1=只判T-Spin；2=全部降级为MiniSpin；3=不判定Spin；4=…
	if TetrisGlobalData.init_has("NoSpin"):
		TetrisGlobalData.clear_no_spin = TetrisGlobalData.get_init_int("NoSpin", TetrisGlobalData.clear_no_spin)

## 记录旋转事件
## 注意：这里记录的 shape/position 是「旋转成功那一刻」的方块状态。
## 该记录只在判定时（锁定后）使用，而任何一次成功的移动/下落/换块都会调用
## reset_rotation_record() 使记录失效，因此记录仍然有效时方块必然没有移动过，
## 记录的 position 就等于锁定位置（spin 判定与 mini 角块判定都依赖这一点）。
func record_rotation(piece_type: String, shape: Array, position: Vector2i, piece_color: Color = Color.WHITE):
	last_rotation_occurred = true
	last_rotation_piece_type = piece_type
	last_rotation_piece_shape = shape
	last_rotation_position = position
	
	if piece_color != Color.WHITE:
		pending_spin_color = piece_color
		spin_color_ready = true

## 版面整体位移（垃圾行上涨）后同步旋转记录中的位置：
## 方块被整版上移时相对堆叠的位置不变，只需把记录坐标改成方块的实际坐标，
## 否则 spin 判定会拿陈旧坐标去探测（判定位置整体偏下行数）。
func sync_rotation_record_position(piece_position: Vector2i):
	if not last_rotation_occurred:
		return
	last_rotation_position = piece_position

## 重置旋转记录（方块发生任何位移/换块/生成时调用）。
## 该函数在移动热路径里会被频繁调用（如 ARR=0 滑墙、硬降），已是干净状态时直接返回，
## 避免反复分配数组。
func reset_rotation_record():
	if not last_rotation_occurred and last_rotation_piece_shape.is_empty():
		return
	last_rotation_occurred = false
	last_rotation_piece_type = ""
	last_rotation_piece_shape = []
	last_rotation_position = Vector2i.ZERO

## 清除Spin颜色
func clear_spin_color():
	pending_spin_color = Color.WHITE
	spin_color_ready = false
	display_spin_color = Color.YELLOW

## 伤害计时器超时
func _on_damage_timer_timeout():
	# 计时归零：结算击杀奖励并清空累积
	# （原先画在版面左侧的 "N Attack" 文本已移除：累积伤害只用于击杀结算与窗口计时，
	#   数字显示交给落块位置的 SpikeDisplay）
	TetrisGlobalData.kill_reward_requested.emit(accumulated_damage)
	accumulated_damage = 0
	damage_pending = false

## 累积伤害（窗口 = damage_display_duration，与 Spike 数字的重置窗口同口径）
func _accumulate_damage(damage: int):
	if damage <= 0:
		return
	
	# 累加伤害
	accumulated_damage += damage
	damage_pending = true
	
	# 重置计时器（如果正在运行则停止并重新开始）
	if damage_timer.is_stopped():
		damage_timer.start()
	else:
		damage_timer.stop()
		damage_timer.start()

## 触发一次 Spike 数字（本次消行打出的攻击）。显示逻辑（1s 内累加、1.5s 淡出）在 SpikeDisplay 内。
func _emit_spike(damage: int) -> void:
	if TetrisGlobalData.spike_display == null or damage <= 0:
		return
	TetrisGlobalData.spike_display.add_spike(damage, _get_spike_anchor_position())

## Spike 数字的落点：本次锁定方块中「被消掉的那些格子」的中心（即落块/消行位置）。
## 取不到落块格子时退回「消行行的中心」，再退回版面中心。
func _get_spike_anchor_position() -> Vector2:
	var cell_size: float = float(TetrisGlobalData.board_cell_size)
	var locked_cells: Array = TetrisGlobalData.piece_last_locked_cells if TetrisGlobalData.tetris_controller else []
	var cleared_cells: Array = []
	for cell in locked_cells:
		if lines_to_clear.has(cell.y):
			cleared_cells.append(cell)
	var use_cells: Array = cleared_cells if not cleared_cells.is_empty() else locked_cells
	if not use_cells.is_empty():
		var sum := Vector2.ZERO
		for cell in use_cells:
			sum += TetrisGlobalData.board_drawer.cell_to_world(cell.x, cell.y)
		# cell_to_world 给的是格子左上角，+半格取格子中心
		return sum / float(use_cells.size()) + Vector2(cell_size, cell_size) * 0.5
	# 兜底：消行行的中心（X 取版面中心）
	var center_x: float = TetrisGlobalData.board_offset_x + TetrisGlobalData.board_grid_width * cell_size * 0.5
	var center_y: float = TetrisGlobalData.board_offset_y + TetrisGlobalData.board_grid_height * cell_size * 0.5
	if not lines_to_clear.is_empty():
		center_y = 0.0
		for row in lines_to_clear:
			center_y += TetrisGlobalData.board_drawer.cell_to_world(0, row).y
		center_y = center_y / float(lines_to_clear.size()) + cell_size * 0.5
	return Vector2(center_x, center_y)

## 检查并消除完整的行（本函数由 TetrisGlobalData.piece_locked 事件驱动，见 _ready 的连接）
func check_and_clear_lines() -> int:
	if TetrisGlobalData.clear_animating_active:
		# 正在消行延迟/动画中又锁定了一块（正常流程不会发生：延迟期间不出块，所以没有活动方块）。
		# 兜底：本次不做判定，但仍要照旧发布「没消行 + 请求出块」，
		# 否则这一块永远等不到出块请求，会卡住不出下一块。
		_publish_judged_result(0, false, "")
		return 0
	
	lines_to_clear = _find_complete_lines()
	# Spin规则模式（int）：
	#   0=正常判定；1=只判定T-Spin（非T块一律不算Spin，即不判Allspin）；
	#   2=全部Spin降级为MiniSpin（用mini伤害表）；3=不判定Spin；
	#   4=正常判定，但触发Spin（含Spin0）立刻上涨 no_spin4_solid_rows 行实心垃圾行
	var spin_type: String = "" if TetrisGlobalData.clear_no_spin == 3 else _detect_spin_type()
	if TetrisGlobalData.clear_no_spin == 2 and not spin_type.is_empty():
		spin_type = _force_mini_spin(spin_type)
	var clear_count = lines_to_clear.size()
	
	if clear_count == 0:
		if not spin_type.is_empty():
			# no_spin==4：Spin0 也属于「触发 Spin」→ 先上涨实心行（此时版面无需位移，安全）
			_apply_no_spin4_penalty()
			# Spin0：显示spin文本，不显示消行文本
			_show_spin_text_only(spin_type)
			
			# Spin0 触发 BTB：
			#   spin0_btb_enabled（既有 buff 开关）或 Allspin 2 及以上（全旋II 起明确要求 Spin0 使 BTB+1）
			if spin0_btb_enabled or TetrisGlobalData.clear_allspin >= 2:
				# 特殊情况：spin0触发BTB
				_update_btb(true)
			# 正常情况下spin0不触发BTB也不断开BTB
			
			# Allspin 2 及以上：Spin0 也要判定伤害与类型 —— 伤害按现有伤害表口径
			# （表里没有 0 行条目 → 基础/Spin 伤害为 0，实际只有 BTB 加成与连击加成；
			#   Allspin_5 起 spin 伤害按「行数 × 3」，0 行仍是 0）。
			if TetrisGlobalData.clear_allspin >= 2:
				var spin0_damage: int = _calculate_damage(0, spin_type)
				current_damage = spin0_damage
				has_cleared_lines = true
				if spin0_damage > 0:
					TetrisGlobalData.tower_damage_dealt.emit(spin0_damage, false)
					_emit_spike(spin0_damage)
					_accumulate_damage(spin0_damage)
					_show_clear_and_spin_text(0, spin_type, spin0_damage)
				# Spin0 记作「消 0 行」，所以它同样参与重复判定：
				#   2/3：上一次也是 Spin0（记录行数 0）→ 吃 20 行实心；
				#   4/5：Spin0 参与「类型轮」与「行数轮（0）」→ 轮内重复 → 42 行实心。
				# ⚠ 必须在下面写入本次记录之前判定，否则会拿本次记录和自己比。
				var spin0_rep: Array = _allspin_repeat_result(spin_type, 0, _current_locked_piece_type())
				if bool(spin0_rep[0]):
					_debug_log_allspin_repeat(spin_type, 0, false)
					_apply_allspin_repeat_penalty(int(spin0_rep[1]))
			
			# 连击：Spin0 与普通无消行放置一样清空连击（bot 侧 case 0 也是无条件清空，
			# 两边口径一致；连击文本不主动移除，按原样自然淡出）
			TetrisGlobalData.clear_combo_count = 0
			reset_rotation_record()
			# 记录Spin0消行信息（行数记 0：供下一次 Spin0 做重复判定）
			_last_clear_type = spin_type
			_last_clear_count = 0
			_last_clear_piece_type = _current_locked_piece_type()
		else:
			# 不去重置其他消行/Spin/连击文本，让它们自然淡出消失
			TetrisGlobalData.clear_combo_count = 0
			reset_rotation_record()
			current_damage = 0
			has_cleared_lines = false
		# 没有可消除的行：本次没消行 → 先发布判定结果（方块控制器会先让垃圾行上涨），再请求出块
		# （落块延迟可能还在计时，实际出块时刻 = 锁定时刻 + max(落块延迟, 0)）
		_publish_judged_result(0, false, spin_type)
		return 0
	
	has_cleared_lines = true
	var is_spin = not spin_type.is_empty()
	# Allspin 2 及以上：所有非 spin 消行都是 void —— 不产生任何攻击，并且断开 BTB 链。
	# void 的「行数」视作 **-1**（不属于 0/1/2/3 的行数轮），在 Allspin_2/3 里仍参与「行数重复」判定：
	#   连续两次 void → -1 == -1 → 同样上涨实心垃圾。
	var allspin_mode: int = TetrisGlobalData.clear_allspin
	var is_void_clear: bool = (allspin_mode >= 2 and not is_spin)
	var locked_piece_type: String = _current_locked_piece_type()
	
	# Allspin 重复判定（规则见 _allspin_repeat_result）：
	#   1：消行类型 + 行数都与上次完全一致 → 上涨 1 行普通垃圾
	#   2：只看「有效行数」与上次相同 → 20 行实心
	#   3：2 的规则 + 再禁止「消行类型（落块件）」重复 → 20 行实心
	#   4：改用「六块每轮各消一遍」的类型轮（取消行数轮）→ 42 行实心
	#   5：类型轮 + 行数轮（0/1/2/3）双轮独立 → 42 行实心
	var is_allspin_repeat: bool = false
	var allspin_repeat_rows: int = 0
	if clear_count > 0:
		if allspin_mode >= 2:
			var rep: Array = _allspin_repeat_result(spin_type, clear_count, locked_piece_type)
			is_allspin_repeat = bool(rep[0])
			allspin_repeat_rows = int(rep[1])
		elif allspin_mode == 1:
			is_allspin_repeat = (clear_count == _last_clear_count and spin_type == _last_clear_type)
	
	# 单独判断is_quad
	var is_quad = false
	if clear_count >= 4:
		is_quad = true
	# 判断是否触发BTB（void 消行不算 spin/quad：它要断开 BTB 链）
	var is_spin_or_quad = false
	if is_quad:
		is_spin_or_quad = true
	if is_spin:
		is_spin_or_quad = true
	
	# 清除可消除的行（带可选消行动画延迟）。
	# 返回值 deferred = true 表示部署了消行延迟：真正的消行位移与「判定结果发布」都推到计时器回调里。
	var deferred: bool = _clear_lines_animated(lines_to_clear, spin_type)
	
	var damage = _calculate_damage(clear_count, spin_type)
	
	# PC判定：消行后场上没有任何方块
	var is_perfect_clear = _check_perfect_clear()
	if is_perfect_clear and not is_void_clear:
		damage += TetrisGlobalData.clear_pc_damage  # PC额外伤害叠加
		_show_pc_text()
	elif is_perfect_clear:
		_show_pc_text()      # void 消行也照常显示 PC 文本，但不给 PC 伤害
	elif TetrisGlobalData.text_printer:
		TetrisGlobalData.text_printer.remove_text("pc")
	
	# Allspin_2：非 spin 消行不产生任何攻击
	if is_void_clear:
		damage = 0
	
	current_damage = damage
	if damage > 0:
		# 伤害 → 爬塔奖励：走公共区域的公共事件（本节点不需要认识塔节点）
		TetrisGlobalData.tower_damage_dealt.emit(damage, false)
	
	# Spike 数字显示：在落块（被消掉的方块）位置弹出白底黑字的累加攻击数字
	if damage > 0:
		_emit_spike(damage)
	
	if is_void_clear:
		# Allspin_2 的 void 消行：断开 BTB 链（不触发 BTB、也不续链）
		_update_btb(false)
	else:
		_update_btb_pc_aware(is_spin_or_quad, is_perfect_clear)
	
	# 累加伤害（用于击杀奖励结算与 Spike 重置窗口；显示由 SpikeDisplay 负责）
	if damage > 0:
		_accumulate_damage(damage)
	
	if is_spin and spin_color_ready:
		display_spin_color = pending_spin_color
	else:
		display_spin_color = Color.YELLOW
	
	_show_clear_and_spin_text(clear_count, spin_type, damage, is_void_clear)
	
	reset_rotation_record()
	TetrisGlobalData.clear_combo_count += 1
	
	# no_spin==4：本手是 Spin 消行 → 上涨实心垃圾行。
	# 必须放在消行位移之后：若在消行前上涨，lines_to_clear 记录的行号会随版面上移而整体失效。
	if TetrisGlobalData.clear_no_spin == 4 and is_spin:
		_apply_no_spin4_penalty()
	
	# Allspin延续（消行位移之后结算，避免行号随版面上移失效）：
	#   Allspin_1：上涨 1 行普通垃圾行（不走延迟队列，类似突然死亡VIII）
	#   Allspin_2/3：重复 → 上涨 allspin2_solid_rows（默认 20）行实心垃圾
	#   Allspin_4/5：轮内重复 → 上涨 allspin_round_solid_rows（默认 42）行实心垃圾（≈ 直接判死）
	if is_allspin_repeat:
		_debug_log_allspin_repeat(spin_type, clear_count, is_void_clear)
		if allspin_mode >= 2:
			_apply_allspin_repeat_penalty(allspin_repeat_rows)
		elif TetrisGlobalData.garbage_line_controller:
			TetrisGlobalData.allspin_garbage_requested.emit()
	
	# Allspin_5：每次 Void（非 spin 普通消行）给塔的发送倍率槽 extra_pressure_mult +0.01。
	#   —— Void 不吃惩罚、也没有攻击，这是它的"补偿"：叠得越多，塔发出去的攻击越强。
	#   用架构预留的公开槽位（tower_controller.extra_pressure_mult），不额外建变量。
	if is_void_clear and allspin_mode >= 5:
		_add_void_pressure_bonus()
	
	# 记录本次消行信息（供下次 Allspin 比对）
	# Void（非 spin 普通消行）同样是「一个消行类型 + 一个行数」→ 照常记 type="void"、行数 -1，
	# 所以它会把「上一手」的记忆清掉：Void 之后再来同样的行数/类型，不算「与上一手重复」。
	# （区别只在**惩罚**：Allspin_5 的 Void 自己不参与重复判定，见 _allspin_repeat_result。）
	if is_void_clear:
		_last_clear_type = ALLSPIN2_VOID_TYPE
		_last_clear_count = -1
		_last_clear_piece_type = ""
	else:
		_last_clear_type = spin_type
		_last_clear_count = clear_count
		_last_clear_piece_type = locked_piece_type
	# 立刻刷新 Allspin 惩罚预警（next / 手上 / 暂存 的灰化显示）：消行动画有延迟，
	# 若等下一块出块才刷新，玩家看到的预警会比实际状态晚一手。
	# ⚠ 这是本节点唯一保留的直接调用：它必须发生在「判定当下」而不是延迟结束之后。
	if TetrisGlobalData.clear_allspin >= 1 and TetrisGlobalData.tetris_controller != null:
		TetrisGlobalData.tetris_controller.refresh_penalty_warning()
	
	# 发布判定结果 + 请求出块（方块控制器据此结算统计/抵消，然后才出块）。
	# 有消行延迟时不在这一步发：那时版面还没位移，结果与出块都等计时器回调
	# （见 _on_clear_line_delay_timeout），保证两条路径都是「版面变化 → 结算 → 出块」。
	if not deferred:
		_publish_judged_result(clear_count, true, spin_type)
	
	return clear_count

## 更新BTB状态
func _update_btb(is_spin_or_quad: bool):
	if is_spin_or_quad:
		if is_btb_active:
			# 第二次及之后连续四消/spin → BTB计数递增
			TetrisGlobalData.clear_btb_count += 1
		else:
			# 第一次四消/spin → 开始计数（btb_count=1），但不显示BTB文本
			is_btb_active = true
			TetrisGlobalData.clear_btb_count = 1
		_update_btb_text()
	else:
		TetrisGlobalData.clear_btb_count = 0
		is_btb_active = false
		if TetrisGlobalData.text_printer:
			TetrisGlobalData.text_printer.remove_text("btb")
		TetrisGlobalData.board_drawer.queue_redraw()

## BTB 更新（带 PC 规则）：PC（Perfect Clear）时 BTB 链**不断开**，且计数 **+2**。
## 例：已有 BTB 链 3 → 5；此前没有 BTB → 直接 2（视作一次延续 + 额外一次）。
## 注意 _calculate_damage() 在本函数之前执行，所以本手 PC 的伤害仍按「本手之前的 BTB 状态」加成，
## 与原有「本次消行不计入自身加成」的口径一致。
func _update_btb_pc_aware(is_spin_or_quad: bool, is_perfect_clear: bool):
	if is_perfect_clear:
		if is_btb_active:
			TetrisGlobalData.clear_btb_count += 2
		else:
			is_btb_active = true
			TetrisGlobalData.clear_btb_count = 2
		_update_btb_text()
		return
	_update_btb(is_spin_or_quad)

## 更新BTB文本（常驻显示，不随消行淡出）
func _update_btb_text():
	var btb_text = _get_btb_text()
	if not TetrisGlobalData.text_printer:
		return
	if not btb_text.is_empty():
		var hold_pos = TetrisGlobalData.board_drawer.get_hold_position()
		var hold_height = TetrisGlobalData.board_hold_display_height * TetrisGlobalData.board_cell_size
		var bottom_y = hold_pos.y + hold_height
		var btb_offset_y = btb_text_offset_y_cells * TetrisGlobalData.board_cell_size
		btb_text_position = Vector2(_get_text_anchor_x(), bottom_y + btb_offset_y)
		# BTB常驻显示（persistent=true），直到断开BTB时才移除
		TetrisGlobalData.text_printer.show_text("btb", btb_text, btb_text_position,
			btb_text_color, btb_text_outline_color, TetrisGlobalData.board_cell_size * 1.0,
			true, 1.0)
	else:
		TetrisGlobalData.text_printer.remove_text("btb")

## 检查是否 Perfect Clear（场上没有任何方块）
func _check_perfect_clear() -> bool:
	# 排除「当前方块自身」的格子（保险）：
	# 出块已经统一挪到判定与版面变化之后（见 _publish_judged_result），因此本判定执行时
	# 通常还没有新方块；但消行延迟路径下版面仍可能残留上一次的方块记录，所以照旧排除一遍。
	var active_cells: Dictionary = {}
	if TetrisGlobalData.tetris_controller != null and not TetrisGlobalData.piece_shape.is_empty():
		var self_cells: Array = TetrisGlobalData.tetris_controller.get_piece_cells(
			TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
		for c in self_cells:
			active_cells[c] = true
	for y in range(TetrisGlobalData.board_playable_height):
		# 待清除的行（消行延迟期间仍物理存在）视为已清除
		if _pending_clear_lines.has(y):
			continue
		for x in range(TetrisGlobalData.board_grid_width):
			if active_cells.has(Vector2i(x, y)):
				continue
			if TetrisGlobalData.board_get_cell(x, y) != null:
				return false
	return true

## 显示 PC 文本
func _show_pc_text():
	if not TetrisGlobalData.text_printer:
		return
	var hold_pos = TetrisGlobalData.board_drawer.get_hold_position()
	var hold_height = TetrisGlobalData.board_hold_display_height * TetrisGlobalData.board_cell_size
	var bottom_y = hold_pos.y + hold_height
	var pc_offset_y = pc_text_offset_y_cells * TetrisGlobalData.board_cell_size
	pc_text_position = Vector2(_get_text_anchor_x(), bottom_y + pc_offset_y)
	TetrisGlobalData.text_printer.show_text("pc", "PERFECT CLEAR", pc_text_position,
		pc_text_color, pc_text_outline_color, TetrisGlobalData.board_cell_size * 1.2,
		false, text_base_opacity, clear_text_display_duration, text_fade_duration, _get_text_drift())

## 计算攻击伤害
func _calculate_damage(clear_count: int, spin_type: String) -> int:
	var base_damage = 0
	var spin_damage = 0
	var surge_break = 0
	
	if not spin_type.is_empty():
		var spin_key = _get_spin_key(spin_type)
		
		# Mini Spin：使用基础伤害表，无额外 Spin 伤害加成（消行相当于正常消行）
		if spin_type.find("Mini") != -1:
			spin_damage = base_damage_table.get(clear_count, 0)
		elif spin_damage_table.has(spin_key):
			var spin_damage_by_count = spin_damage_table[spin_key]
			if spin_damage_by_count.has(clear_count):
				spin_damage = spin_damage_by_count[clear_count]
			else:
				spin_damage = base_damage_table.get(clear_count, 0)
		else:
			# 非Mini非T-Spin的全旋（如"I-Spin"、"L-Spin"等）→ 使用T-Spin伤害表作为通用全旋伤害
			var full_spin_data: Dictionary = spin_damage_table.get("T-Spin", {})
			spin_damage = full_spin_data.get(clear_count, base_damage_table.get(clear_count, 0))
		
		base_damage = 0
	else:
		base_damage = base_damage_table.get(clear_count, 0)
	
	# Allspin_5：spin 伤害改为「行数 × 3」（spin1 = 3、spin2 = 6、spin3 = 9；Spin0 = 0）。
	# 只改非 Mini 的 Spin（Mini 仍走基础伤害表），且在 BTB 加成之前覆盖，加成照常叠加。
	if TetrisGlobalData.clear_allspin >= 5 and not spin_type.is_empty() and spin_type.find("Mini") == -1:
		spin_damage = clear_count * 3
	
	# 记录本次消行的攻击值（base+spin，不含BTB加成），供连击公式使用
	var attack_value: int = base_damage + spin_damage
	
	# BTB 加成（数值由 btb_system_use 选择，见 _get_btb_bonus()）- 仅适用于 spin 和 quad
	var btb_bonus: int = _get_btb_bonus()
	if btb_bonus > 0:
		if not spin_type.is_empty():
			spin_damage += btb_bonus
		elif clear_count >= 4:
			base_damage += btb_bonus
	
	# surge break 兑现：长链（btb_count >= 4）被普通消行（非 Spin、非四消）打断时结算。
	# 只有 surge break 系统（btb_system_use == 1）有这个机制；
	# 累加奖励系统（btb_system_use == 2）的收益全部体现在链内的 _get_btb_bonus() 上，断链不额外兑现。
	if TetrisGlobalData.clear_btb_system_use == 1 and TetrisGlobalData.clear_btb_count >= 4 and spin_type.is_empty() and clear_count < 4:
		surge_break = TetrisGlobalData.clear_btb_count
	else:
		surge_break = 0
	
	var combo_damage = 0
	if TetrisGlobalData.clear_combo_count > 0:
		if combo_formula == 1:
			# 新公式（默认）：
			#   combo_damage = floor(max(ln(1+1.25*combo), ((is_btb_active?1:0)+attack)*(1+0.25*combo)))
			#   其中 attack = base+spin（不含BTB加成）
			var b2b_flag: float = 1.0 if is_btb_active else 0.0
			var combined: float = (b2b_flag + float(attack_value)) * (1.0 + 0.25 * float(TetrisGlobalData.clear_combo_count))
			var log_term: float = log(1.0 + 1.25 * float(TetrisGlobalData.clear_combo_count))
			combo_damage = floori(max(log_term, combined))
		else:
			# 旧连击表（备选项）
			var is_mini: bool = spin_type.find("Mini") != -1
			var is_quad: bool = clear_count >= 4
			if not is_mini and is_quad:
				# 非mini spin且quad：伤害 +combo_count（x）
				combo_damage = TetrisGlobalData.clear_combo_count
			elif is_mini:
				# mini spin：伤害 +floor(ln((x²/2)+1))
				combo_damage = floori(log(TetrisGlobalData.clear_combo_count * TetrisGlobalData.clear_combo_count / 3.0 + 1.0))
			else:
				# 其他情况：使用连击表
				var index = TetrisGlobalData.clear_combo_count
				if index < combo_damage_list.size():
					combo_damage = combo_damage_list[index]
				else:
					var extra = (TetrisGlobalData.clear_combo_count - combo_damage_list.size()) / 2.0
					combo_damage = min(5, combo_damage_list[-1] + extra)
	
	return base_damage + spin_damage + combo_damage + surge_break

## 计算本次消行的 BTB 加成值（是否作用于 spin/quad 由调用方 _calculate_damage 门控）。
## btb_system_use == 1（surge break 系统）：
##   btb_count <= 0 → 0；btb_count == 1~3 → +1；
##   btb_count >= 4 → +2，但**必须开启 Allspin_2（tetris_allspin == 2）**，否则仍是 +1
##   btb_count == 1 表示「上一手已经是 4消/Spin」，本手即第 2 手连续 BTB，
##   应吃到 +1；该手的 btb_count 结算为 2，界面正好显示 "1 x BTB"，两者对齐。
## btb_system_use == 2（累加奖励系统，tetr.io S1 的 BTB 伤害系统；由 buff「Btb奖励」开启）：令 BTB = btb_count
##   BTB <= 0 → 0
##   BTB == 1 → 1（规则直接给定）
##   BTB >= 2 → 原始值 raw = 1 + ln(0.8*BTB + 1)，
##              取整数部分 a = floor(raw)、小数部分 b = raw - a，
##              加成 = a + (1+b)/3
## 注意：本手伤害最终按整数伤害结算（floor），因此 (1+b)/3 的小数部分不足 1 时
## 不会产生实际伤害点数（公式保留在此，便于日后改为保留小数伤害）。
func _get_btb_bonus() -> int:
	if TetrisGlobalData.clear_btb_system_use == 2:
		if TetrisGlobalData.clear_btb_count < 1:
			return 0
		if TetrisGlobalData.clear_btb_count == 1:
			return 1
		var raw: float = 1.0 + log(0.8 * float(TetrisGlobalData.clear_btb_count) + 1.0)
		var int_part: int = floori(raw)
		var frac_part: float = raw - float(int_part)
		return floori(float(int_part) + (1.0 + frac_part) / 3.0)
	
	# surge break 系统：第 2 手连续 BTB（btb_count == 1）起 +1。
	# 高段加成按 Allspin 档位开放（阈值都是 btb_count >= 4，即界面显示「3 x BTB」）：
	#   Allspin_2 / Allspin_3 → +2；Allspin_4 / Allspin_5 → +3；未开 Allspin（或只开 1）→ 最高 +1
	if TetrisGlobalData.clear_btb_count >= 1:
		if TetrisGlobalData.clear_btb_count >= 4:
			if TetrisGlobalData.clear_allspin >= 4:
				return 3
			if TetrisGlobalData.clear_allspin >= 2:
				return 2
		return 1
	return 0

## 获取Spin的键名
func _get_spin_key(spin_type: String) -> String:
	if spin_type.find("T-Spin") != -1:
		if spin_type.find("Mini") != -1:
			return "Mini T-Spin"
		return "T-Spin"
	return spin_type

## 获取当前消行的伤害值
func get_current_damage() -> int:
	return current_damage

## 供 bot 读取当前 buff 调整后的并行搜索线程数（0 = 由 bridge 自动决定）。
func get_bot_threads() -> int:
	return bot_threads

## 供 bot 读取“实际游戏规则/伤害模型”的伤害表（lt→bot 桥接）。
## 返回当前生效的基础伤害表、T-Spin 伤害表、连击伤害表、BTB 加成、PC 伤害。
## 这些表可由 buff 界面（extra_data）调整后读取，bot 据此模拟真实伤害。
## ⚠ 现状说明：本函数目前**没有任何调用方**（bot 桥接是从公共数据区读规则字段、按自己的伤害模型算），
##   保留它是为了将来真要下发伤害表时有现成入口；若确认不再需要，可直接删除本函数。
func get_damage_tables() -> Dictionary:
	var tbl := {}
	tbl["enabled"] = true
	# 基础伤害表（按下标=消行数 0..4）
	var base: Array = []
	for i in range(5):
		base.append(base_damage_table.get(i, 0))
	tbl["base_damage"] = base
	# T-Spin 伤害表（按下标=消行数 0..3，下标0为0）
	var tspin: Array = [0, 0, 0, 0]
	var ts_data: Dictionary = spin_damage_table.get("T-Spin", {})
	for i in range(1, 4):
		tspin[i] = ts_data.get(i, 0)
	tbl["tspin_damage"] = tspin
	# 连击伤害表（按下标=连击数 0..31）
	var combo: Array = []
	for i in range(32):
		if i < combo_damage_list.size():
			combo.append(combo_damage_list[i])
		else:
			# 超出表长：min(5, list[-1] + (i - size)/2)，与 _calculate_damage 一致
			var extra: float = (i - combo_damage_list.size()) / 2.0
			combo.append(min(5, combo_damage_list[-1] + int(extra)))
	tbl["combo_damage"] = combo
	# 连击计算方式：0=旧连击表，1=新公式（默认）——同步给 CC 的 combo 处理
	tbl["combo_formula"] = combo_formula
	tbl["b2b_bonus"] = 1
	tbl["pc_damage"] = TetrisGlobalData.clear_pc_damage
	# All-Spin 伤害表（独立表，默认同 T-Spin 值，可由 buff 调整）
	var allspin: Array = [0, 0, 0, 0]
	for i in range(1, 4):
		allspin[i] = allspin_damage_table.get(i, 0)
	tbl["allspin_damage"] = allspin
	# allspin_1 规则是否启用（tetris_allspin==1）
	tbl["allspin_enabled"] = (TetrisGlobalData.clear_allspin == 1)
	# bot 评估权重字段（bot_eval_mult 等）目前没有任何调用方消费：
	# 原先这里按 bot_weight_override_keys 过滤下发，但那个字典从未被写入过（死链路，已删除），
	# 因此这里不再输出任何权重键 —— 若将来要接 bot 权重覆盖，请先补上「谁写入 override 键」。
	return tbl

## 获取连击文本
func _get_combo_text() -> String:
	if TetrisGlobalData.clear_combo_count > 0:
		return "%d Combo" % TetrisGlobalData.clear_combo_count
	return ""

## 获取BTB文本
func _get_btb_text() -> String:
	if is_btb_active and TetrisGlobalData.clear_btb_count > 1:
		return "%d x BTB" % (TetrisGlobalData.clear_btb_count - 1)
	return ""

# ========== 查找完整行 ==========

func _find_complete_lines() -> Array:
	var complete_lines = []
	
	for y in range(TetrisGlobalData.board_playable_height):
		if TetrisGlobalData.garbage_solid_rows.has(y):
			continue
		
		var is_complete = true
		for x in range(TetrisGlobalData.board_grid_width):
			if TetrisGlobalData.board_get_cell(x, y) == null:
				is_complete = false
				break
		
		if is_complete:
			complete_lines.append(y)
	
	return complete_lines

func _clear_lines(lines: Array):
	if lines.is_empty():
		return
	
	lines.sort()
	
	for y in lines:
		_clear_single_line(y)
	
	TetrisGlobalData.board_drawer.queue_redraw()

func _clear_single_line(line_y: int):
	# 整行下移：颜色与锁定时间戳必须一起搬。
	# 若走 set_cell_color()，时间戳会被刷成「刚刚落下」，隐形模式下消行后
	# 上侧原本已经隐形的方块会整片显形（只有刚落下的方块才该现形）。
	for y in range(line_y, 0, -1):
		for x in range(TetrisGlobalData.board_grid_width):
			var color = TetrisGlobalData.board_get_cell(x, y - 1)
			var lock_time: int = TetrisGlobalData.board_get_cell_lock_time(x, y - 1)
			TetrisGlobalData.board_set_cell_with_lock_time(x, y, color, lock_time)
	
	for x in range(TetrisGlobalData.board_grid_width):
		TetrisGlobalData.board_set_cell(x, 0, null)

## 单个函数：清除可消除的行。
## clear_line_delay_time（buff「落块延迟」的 ClearDelay）> 0 时播放消行动画
## （对已清除的行区域进行闪烁提示，持续该时长），计时结束后才执行正式消行。
## 返回值：true = 本次走了延迟路径 —— 真正的消行位移与「判定结果发布」都在
## _on_clear_line_delay_timeout() 里完成。
## ⚠ 出块不再由本函数负责：无论哪条路径，都由调用方在**全部判定与版面变化完成之后**
##    统一发布 lines_judged → spawn_requested（见 _publish_judged_result）。
func _clear_lines_animated(lines: Array, spin_type: String) -> bool:
	if lines.is_empty():
		return false
	lines.sort()
	if clear_line_delay_time > 0:
		# 消行延迟期间：仅播放消行动画（完整行仍保留、不位移），延迟结束后才正式消行并发布结果
		_pending_clear_lines = lines
		_pending_clear_count = lines.size()
		_pending_spin_type = spin_type
		if TetrisGlobalData.board_drawer:
			TetrisGlobalData.board_drawer.set_clearing_lines(lines)
		TetrisGlobalData.clear_animating_active = true
		clear_line_delay_timer.wait_time = clear_line_delay_time
		clear_line_delay_timer.start()
		return true
	# 无消行延迟：立即执行正式消行（位移）；结果发布与出块请求交给调用方统一做
	_pending_clear_lines = []
	_clear_lines(lines)
	return false

## 消行延迟计时结束：结束动画，执行正式消行（位移）并发布结果 + 请求出块
func _on_clear_line_delay_timeout():
	TetrisGlobalData.clear_animating_active = false
	if TetrisGlobalData.board_drawer:
		TetrisGlobalData.board_drawer.clear_clearing_lines()
	# 消行延迟结束：此时才执行正式消行（把行进行位移清除）
	var did_clear: bool = not _pending_clear_lines.is_empty()
	var cleared_count: int = _pending_clear_count if did_clear else 0
	if did_clear:
		_clear_lines(_pending_clear_lines)
		_pending_clear_lines = []
	# 消行延迟结束：恢复消行延迟期间被暂缓的垃圾行上涨（不丢弃行）
	if TetrisGlobalData.garbage_line_controller:
		TetrisGlobalData.garbage_rise_resume_requested.emit()
	# 至此版面变化全部完成 → 发布判定结果（方块控制器结算统计/抵消），再请求出块
	_publish_judged_result(cleared_count, did_clear, _pending_spin_type)

## 统一的「判定收尾」：先发布判定结果，再请求出块（固定顺序：结算 → 出块）。
## 于是「有无消行延迟」两条路径的顺序完全一致：
##   判定（含全部版面变化：消行位移 / 垃圾上涨 / Allspin 惩罚）
##     → lines_judged（方块控制器：统计 / 抵消 / 无消行时涨垃圾）
##     → spawn_requested（方块控制器：locked 门 + 落块延迟结算 → 出块）
## cleared / did_clear / spin_type 由各判定路径给出；damage / btb / combo 取当前共享状态。
func _publish_judged_result(cleared: int, did_clear: bool, spin_type: String) -> void:
	TetrisGlobalData.lines_judged.emit(cleared, did_clear, current_damage, spin_type,
		TetrisGlobalData.clear_btb_count, TetrisGlobalData.clear_combo_count)
	TetrisGlobalData.spawn_requested.emit()

# ========== Spin检测系统 ==========

## no_spin==2：把所有 Spin 类型强制降级为 MiniSpin（"T-Spin"→"Mini T-Spin"，已是 Mini 保持不变）。
## 这样 _calculate_damage 会命中 "Mini" 分支，采用 mini（基础）伤害表。
func _force_mini_spin(spin_type: String) -> String:
	if spin_type.is_empty():
		return ""
	if spin_type.find("Mini") != -1:
		return spin_type
	return "Mini " + spin_type

## no_spin==4（无天赋IV）的惩罚：触发 Spin（含 Spin0）时上涨 no_spin4_solid_rows 行实心垃圾行（不可消除）。
## 必须用 ignore_row_cap=true：一次要涨 20 行，走常规上涨会被 garbage_cap（默认 3）截断。
## 消行延迟期间 GarbageLineController 会把它暂存，延迟结束后统一上涨（不动正在播放动画的版面）。
func _apply_no_spin4_penalty() -> void:
	if TetrisGlobalData.clear_no_spin != 4 or TetrisGlobalData.clear_no_spin4_solid_rows <= 0 or not TetrisGlobalData.garbage_line_controller:
		return
	TetrisGlobalData.solid_garbage_requested.emit(TetrisGlobalData.clear_no_spin4_solid_rows, true)

## 上一次锁定的方块类型（T/S/Z/J/L/I/O）——由 TetrisController 在锁定瞬间记录。
## 消行时用它写入 _last_clear_piece_type，供 Allspin 重复惩罚预警判断「同类型」。
func _current_locked_piece_type() -> String:
	if TetrisGlobalData.tetris_controller == null:
		return ""
	return TetrisGlobalData.piece_last_locked_type


## Allspin 重复惩罚预警：给定方块类型，是否会触发重复惩罚（next / 手上用「原色+灰」提示）。
## 各档的判据（都只能看「类型」这一半，行数/落点出块前无法确定）：
##   Allspin_1：上次消过行 且 本块类型与上次消行所用方块相同（类型相同才可能复现同一消行）
##   Allspin_2：与类型无关（只看行数）→ 不预警
##   Allspin_3：本块类型与上次消行所用方块相同即可（类型重复本身就罚）
##   Allspin_4/5：本块类型已经在本轮的「六块」里消过（再消就是轮内重复），
##                或本块类型就是上一手消行的那块（「与上一手重复」也要罚）
##   Allspin_5 的行数轮无法从「是哪一块」推断，故不参与预警。
func is_allspin_penalty_piece(piece_type: String) -> bool:
	var mode: int = TetrisGlobalData.clear_allspin
	if mode < 1 or piece_type.is_empty():
		return false
	if mode == 1:
		if _last_clear_count <= 0 or _last_clear_piece_type.is_empty():
			return false
		return piece_type == _last_clear_piece_type
	if mode == 3:
		return piece_type == _last_clear_piece_type
	if mode >= 4:
		if piece_type == _last_clear_piece_type:
			return true
		var ti: int = ALLSPIN_ROUND_TYPES.find(piece_type)
		return ti >= 0 and _allspin_round_used_types.has(ti)
	return false


func _detect_spin_type() -> String:
	if TetrisGlobalData.clear_no_spin == 3:
		return ""
	if not spin_detection_enabled:
		return ""
	
	# no_spin==1（buff「NoSpin_1」）：只判定 T-Spin，任何非 T 方块都不判 Spin
	# （因此也不会产生 Allspin；该模式与 tetris_allspin 的开关无关）
	if TetrisGlobalData.clear_no_spin == 1 and last_rotation_piece_type != "T":
		return ""
	
	if not last_rotation_occurred:
		return ""
	
	# O 块旋转是几何空操作（2x2 矩阵旋转前后完全一样），不参与 spin 判定。
	# 注意：O 的旋转仍算一次「成功旋转」（会重置锁延），该行为保持不变，
	# 只是不产生 O-Spin / Mini O-Spin 文本与伤害。
	if last_rotation_piece_type == "O":
		return ""
	
	if not _is_piece_stuck(last_rotation_piece_shape, last_rotation_position):
		# 未卡住 → T块额外检测 Mini T-Spin
		if last_rotation_piece_type == "T":
			return _detect_t_spin_mini()
		return ""
	
	# 卡住了
	if last_rotation_piece_type == "T":
		# T块卡住 → 全 T-Spin
		return "T-Spin"
	
	if TetrisGlobalData.clear_allspin >= 1:
		# Allspin模式：非T块卡住 → 全 Spin（不加 Mini 前缀）
		return last_rotation_piece_type + "-Spin"
	
	# 非T块卡住 → 视作 Mini Spin
	return "Mini " + last_rotation_piece_type + "-Spin"

## 判定方块是否「卡住」（不可移动）：上下左右四个方向都无法移动即为卡住。
## 本游戏的 spin 规则是「不可移动 → spin」，T 块再额外用「下2角 + 上1角」判 mini。
##
## 关键点：判定发生在方块锁定之后，此时方块自身的格子已写进版面
## （_lock_piece 只清空 current_piece 矩阵，不清版面格子）。若不排除自身，
## 把方块整体平移 1 格必然与自己重叠 → 四个方向恒为「堵」→ 任何转过一次的方块都会判 spin。
func _is_piece_stuck(shape: Array, piece_position: Vector2i) -> bool:
	if not TetrisGlobalData.tetris_controller or not TetrisGlobalData.board_drawer:
		return false
	
	var directions = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	# 自身占据的格子（判定位置上的 shape）：碰撞查询时视为空 → 排除自身
	var self_cells: Array = TetrisGlobalData.tetris_controller.get_piece_cells(shape, piece_position)
	
	for dir in directions:
		var new_pos = Vector2i(piece_position.x + dir.x, piece_position.y + dir.y)
		# 纯查询（无清绘副作用），把自身格子视为空
		if not TetrisGlobalData.tetris_controller.collides_at(new_pos, shape, self_cells):
			return false
	
	return true


## 检测T块专用 Mini T-Spin
## 条件：左下和右下都被方块或墙占据，且左上或右上有一个被方块或墙占据
## 返回 "Mini T-Spin" 或 ""
func _detect_t_spin_mini() -> String:
	var pos_x: int = last_rotation_position.x
	var pos_y: int = last_rotation_position.y
	
	# T块 3x3 包围盒的四个角
	var bl_blocked: bool = _is_corner_blocked(pos_x, pos_y + 2)       # 左下
	var br_blocked: bool = _is_corner_blocked(pos_x + 2, pos_y + 2)   # 右下
	var tl_blocked: bool = _is_corner_blocked(pos_x, pos_y)           # 左上
	var tr_blocked: bool = _is_corner_blocked(pos_x + 2, pos_y)       # 右上
	
	# 左下和右下都要被封堵
	if not (bl_blocked and br_blocked):
		return ""
	
	# 左上或右上至少有一个被封堵
	if not (tl_blocked or tr_blocked):
		return ""
	
	return "Mini T-Spin"


## 检查一个角落位置是否被封堵（超出边界 或 该位置有方块）
func _is_corner_blocked(x: int, y: int) -> bool:
	# 左右超出边界 → 被墙壁封堵
	if x < 0 or x >= TetrisGlobalData.board_grid_width:
		return true
	# 底部超出边界 → 被地板封堵
	if y >= TetrisGlobalData.board_playable_height:
		return true
	# 上方超出边界 → 不算封堵（可在出块区域之上）
	if y < 0:
		return false
	# 检查该位置是否有方块
	if TetrisGlobalData.board_get_cell(x, y) != null:
		return true
	return false


# ========== 显示系统 ==========

func _get_clear_text(count: int) -> String:
	if clear_texts.has(count):
		return clear_texts[count]
	return ""

## 文本锚点X坐标：版面外侧，距离左边框一小段距离
func _get_text_anchor_x() -> float:
	return TetrisGlobalData.board_offset_x - text_gap_cells * TetrisGlobalData.board_cell_size

## 非BTB文本的漂移速度（向左慢慢移动）
func _get_text_drift() -> Vector2:
	return Vector2(-text_drift_cells_per_sec * TetrisGlobalData.board_cell_size, 0)

## 消行文本基准Y（Hold框底部）
func _get_text_base_y() -> float:
	var hold_pos = TetrisGlobalData.board_drawer.get_hold_position()
	var hold_height = TetrisGlobalData.board_hold_display_height * TetrisGlobalData.board_cell_size
	return hold_pos.y + hold_height

func _show_clear_and_spin_text(clear_count: int, spin_type: String, _damage: int, is_void: bool = false):
	if clear_count <= 0 or not TetrisGlobalData.text_printer:
		return
	
	# Allspin_2 的 void 消行（非 spin 普通消行）：文本显示 VOID 而不是 Single/Double/Triple/Tetris，
	# 让玩家一眼看出这一手被判为无效（无攻击、断 BTB）。
	var clear_text: String = ALLSPIN2_VOID_TYPE.to_upper() if is_void else _get_clear_text(clear_count)
	if clear_text.is_empty():
		return
	
	var cell = TetrisGlobalData.board_cell_size
	var bottom_y = _get_text_base_y()
	var anchor_x = _get_text_anchor_x()
	
	# Allspin 类（Allspin_1 / Allspin_2）开启时：消行文字与 spin 文字**常驻**在左侧不动 ——
	# 不漂移、不淡出，一直显示到下一次消行把它们替换掉。
	# 原因：Allspin 的重复惩罚要看「上一手的消行类型（含 spin 类型）/行数」，文字留在屏幕上玩家才对照得出来。
	var keep_left: bool = TetrisGlobalData.clear_allspin >= 1
	var clear_spin_drift: Vector2 = Vector2.ZERO if keep_left else _get_text_drift() * clear_spin_drift_scale
	var clear_spin_fade: float = text_fade_duration * clear_spin_fade_scale
	# 淡出与移动并行：这里把保持期缩短，让淡出在文本仍在移动时就开始
	var clear_spin_hold: float = clear_text_display_duration * clear_spin_hold_scale
	if keep_left:
		clear_spin_fade = 0.0
		clear_spin_hold = 0.0
	
	var offset_y = clear_text_offset_y_cells * cell
	clear_text_position = Vector2(anchor_x, bottom_y + offset_y)
	# void 消行（Allspin_2 的非 spin 普通消行）用灰色文本，与普通消行区分开
	var draw_clear_color: Color = void_text_color if is_void else clear_text_color
	TetrisGlobalData.text_printer.show_text("clear", clear_text, clear_text_position,
		draw_clear_color, clear_text_outline_color, cell * 1.0,
		keep_left, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	
	if not spin_type.is_empty():
		var spin_offset_y = (clear_text_offset_y_cells - spin_text_offset_y_cells) * cell
		spin_text_position = Vector2(anchor_x, bottom_y + spin_offset_y)
		# spin 文字与消行文字同进退：Allspin 类开启时一起常驻（Allspin_1 的重复判定要同时看
		# 「类型（含 spin 类型）+ 行数」，两行都留在屏幕上玩家才对照得出来）
		TetrisGlobalData.text_printer.show_text("spin", spin_type, spin_text_position,
			display_spin_color, spin_text_outline_color, cell * 0.8,
			keep_left, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	else:
		TetrisGlobalData.text_printer.remove_text("spin")
	
	var combo_text = _get_combo_text()
	if not combo_text.is_empty():
		var combo_offset_y = (clear_text_offset_y_cells + combo_text_offset_y_cells) * cell
		combo_text_position = Vector2(anchor_x, bottom_y + combo_offset_y)
		# combo 特例：有新 combo 时立即重置，移除旧文本后再显示新的，不做叠加
		TetrisGlobalData.text_printer.remove_text("combo")
		TetrisGlobalData.text_printer.show_text("combo", combo_text, combo_text_position,
			combo_text_color, combo_text_outline_color, cell * 0.8,
			false, text_base_opacity, clear_text_display_duration, text_fade_duration, _get_text_drift())
	else:
		TetrisGlobalData.text_printer.remove_text("combo")
	
	# BTB常驻显示（persistent=true）
	var btb_text = _get_btb_text()
	if not btb_text.is_empty():
		var btb_offset_y = btb_text_offset_y_cells * cell
		btb_text_position = Vector2(anchor_x, bottom_y + btb_offset_y)
		TetrisGlobalData.text_printer.show_text("btb", btb_text, btb_text_position,
			btb_text_color, btb_text_outline_color, cell * 1.0,
			true, 1.0)
	else:
		TetrisGlobalData.text_printer.remove_text("btb")
	
	##print("消行: ", clear_count, "，Spin: ", spin_type, "，伤害: ", damage, "，Spin颜色: ", display_spin_color)

## 仅显示Spin文本（无消行，Spin0）
func _show_spin_text_only(spin_type: String):
	if spin_type.is_empty() or not TetrisGlobalData.text_printer:
		return
	
	if spin_color_ready:
		display_spin_color = pending_spin_color
	else:
		display_spin_color = Color.YELLOW
	
	var cell = TetrisGlobalData.board_cell_size
	# 计算spin文本位置
	spin_text_position = Vector2(_get_text_anchor_x(), _get_text_base_y() + spin_text_offset_y_cells * cell)
	# Allspin 类开启时 spin 文本同样常驻（与 _show_clear_and_spin_text 保持一致）：
	# 否则 Spin0 这条路会写一条「会淡出」的 spin 文本，且与之前常驻的那条叠在一起
	# → 表现为「有时停留、有时消失」。
	var keep_left: bool = TetrisGlobalData.clear_allspin >= 1
	var clear_spin_drift: Vector2 = Vector2.ZERO if keep_left else _get_text_drift() * clear_spin_drift_scale
	var clear_spin_fade: float = text_fade_duration * clear_spin_fade_scale
	var clear_spin_hold: float = clear_text_display_duration * clear_spin_hold_scale
	if keep_left:
		clear_spin_fade = 0.0
		clear_spin_hold = 0.0
	TetrisGlobalData.text_printer.show_text("spin", spin_type, spin_text_position,
		display_spin_color, spin_text_outline_color, cell * 0.8,
		keep_left, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	# 不重置其他文本，让它们自然淡出

## 获取当前显示的Spin文本颜色
func get_spin_trigger_color() -> Color:
	return display_spin_color

## 检查是否有消行文本正在显示
func is_text_displaying() -> bool:
	return TetrisGlobalData.text_printer != null and TetrisGlobalData.text_printer.has_text("clear")

## 获取当前显示的Spin文本（供TetrisController统计用）
func get_current_spin_text() -> String:
	if TetrisGlobalData.text_printer:
		return TetrisGlobalData.text_printer.get_text("spin")
	return ""

## 重置消行状态
func reset():
	lines_to_clear.clear()
	if TetrisGlobalData.text_printer:
		TetrisGlobalData.text_printer.clear_all()
	damage_timer.stop()
	reset_rotation_record()
	TetrisGlobalData.clear_combo_count = 0
	TetrisGlobalData.clear_btb_count = 0
	# Allspin_4/5 的「轮」也要随开局清零，否则上一局的轮记录会带到本局
	reset_allspin_rounds()
	# Allspin_5 的 Void 补偿（extra_pressure_mult 累加）也随开局归位（同场景重开局时不会残留）
	if TetrisGlobalData.tower_controller != null and TetrisGlobalData.clear_allspin >= 5:
		TetrisGlobalData.tower_controller.extra_pressure_mult = 1.0
	is_btb_active = false
	current_damage = 0
	accumulated_damage = 0
	damage_pending = false
	clear_spin_color()
	has_cleared_lines = false

## 获取当前连击数
func get_combo_count() -> int:
	return TetrisGlobalData.clear_combo_count

## 获取当前BTB数
func get_btb_count() -> int:
	return TetrisGlobalData.clear_btb_count

## 上一次消行的类型 / 行数（bot 复现 Allspin 重复惩罚要用；原先 bot 桥接直接读私有字段）
func get_last_clear_type() -> String:
	return _last_clear_type

func get_last_clear_count() -> int:
	return _last_clear_count

## 手动设置连击（用于调试）
func set_combo(count: int):
	TetrisGlobalData.clear_combo_count = count

## 手动设置BTB（用于调试）
func set_btb(count: int):
	TetrisGlobalData.clear_btb_count = count
	is_btb_active = count > 0
