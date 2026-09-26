extends Node
class_name TetrisClearLine

## 俄罗斯方块消行控制器
## 负责检测和消除完整行，并显示消行动画/文本

# 节点引用
@export var board_drawer: TetrisBoardDrawer  # 版面绘制器节点
@export var tetris_controller: TetrisController  # 方块控制器引用
@export var garbage_line_controller: TetrisGarbageLineController
@export var tower_controller: TowerController
@export var text_printer: TextPrinter  # 文本打印器节点（用于显示消行/Spin/连击/BTB文本）

# 消行配置
@export var clear_animation_duration: float = 0.3  # 消行动画持续时间（秒）
@export var clear_text_display_duration: float = 2.0  # 消行文本显示持续时间（秒）

# 消行延迟时间（秒）：>0 时先播放消行动画（持续 clear_line_delay_time），动画结束后才生成新方块；0 表示无延迟
@export var clear_line_delay_time: float = 0.0

# 消行延迟状态
var clear_line_delay_timer: Timer  # 消行延迟计时器
var _pending_clear_lines: Array = []  # 待清除的行（延迟期间仍物理存在，延迟结束后才位移清除）
var _is_clear_animating: bool = false  # 是否正在播放消行动画（延迟中）

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
@export var clear_text_offset_y_cells: float = 2  # 消行文本相对于Hold框底部的偏移（格子数）

# Spin类型判定配置
@export var spin_detection_enabled: bool = true  # 是否启用Spin检测
@export var spin_text_color: Color = Color.YELLOW  # Spin文本颜色
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

# PC（Perfect Clear）配置
@export var pc_text_color: Color = Color.GOLD  # PC文本颜色
@export var pc_text_outline_color: Color = Color.BLACK  # PC文本描边颜色
@export var pc_text_offset_y_cells: float = 3.5  # PC文本相对于Hold框底部的偏移（格子数，正值向下）
@export var pc_damage: int = 10  # PC附加伤害值

# 伤害显示配置
@export var damage_text_color: Color = Color.ORANGE  # 伤害文本颜色
@export var damage_text_outline_color: Color = Color.BLACK  # 伤害文本描边颜色
@export var damage_text_offset_y_cells: float = 5.5  # 伤害文本相对于Hold框底部的偏移（格子数，正值向下）
@export var damage_display_duration: float = 1.5  # 伤害显示持续时间（秒）

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

# Spin伤害加成
var spin_damage_multiplier: Dictionary = {
	"t_spin": 2,
	"mini_t_spin": 1,
	"other_spin": 1
}

# 状态变量
var lines_to_clear: Array = []
var is_animating: bool = false
var clear_text_position: Vector2 = Vector2.ZERO
var spin_text_position: Vector2 = Vector2.ZERO
var combo_text_position: Vector2 = Vector2.ZERO
var btb_text_position: Vector2 = Vector2.ZERO
var damage_text_position: Vector2 = Vector2.ZERO

# 连击和BTB状态
var combo_count: int = 0
var btb_count: int = 0
var is_btb_active: bool = false
var spin0_btb_enabled: bool = false  # Spin0是否触发BTB（由buff控制）
var tetris_allspin: int = 0          # 0=关闭, 1=启用Allspin

# ---- bot 评估权重（可由 buff 界面调整，经 bridge 的 S 命令下发到 ColdClear）----
# 维持 BTB 的评估权重（越大 bot 越倾向于维持 back-to-back）
var bot_b2b_clear: int = 200
# 放块后的堆叠最高点权重（bot 评估：height × 最高点，负值=压高）
var bot_height: int = -39
# 四消（Tetris）的评估权重（越小 bot 越不倾向做四消）
var bot_clear4: int = 260
# allspin_1 重复惩罚的评估扣分（负值=降低选取值，可 buff 调整）
var bot_allspin_repeat_penalty: int = -120
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
var no_spin: int = 0                 # Spin规则模式：0=正常Spin判定；1=所有Spin降级为MiniSpin（用mini伤害表）；2=NoSpin（不判定Spin）
# 记录 buff 显式传参的权重键（仅这些键会被 bridge 采用，覆盖 bridge 默认权重）
# 由 tower_controller._extra_data_deal 填入；get_damage_tables 只返回这些键的权重。
var bot_weight_override_keys: Dictionary = {}

# Allspin：记录上次消行类型和行数（用于下一次消行时比对）
var _last_clear_type: String = ""    # 上次消行类型（如"T-Spin"、"Mini T-Spin"、"I-Spin"、""等）
var _last_clear_count: int = 0       # 上次消行行数

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

func _ready():
	if not board_drawer:
		board_drawer = get_node_or_null("../TetrisBoardDrawer")
		if not board_drawer:
			push_error("TetrisClearLine: 未找到TetrisBoardDrawer节点！")
			return
	
	if not tetris_controller:
		tetris_controller = get_node_or_null("../TetrisController")
		if not tetris_controller:
			push_error("TetrisClearLine: 未找到TetrisController节点！")
	
	# 自动查找tower_controller（如果未设置）
	if not tower_controller:
		tower_controller = get_node_or_null("../../TowerController")
		if not tetris_controller:
			push_error("TowerController: 未找到TowerController节点！")
	
	# 自动查找text_printer（如果未设置）
	if not text_printer:
		text_printer = get_node_or_null("../TextPrinter")
	
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
	# 计时归零，清除伤害显示
	tower_controller.try_give_kill_reward(accumulated_damage)
	accumulated_damage = 0
	damage_pending = false
	if text_printer:
		text_printer.remove_text("damage")

## 添加伤害到累积显示
func _add_damage_to_display(damage: int):
	if damage <= 0:
		return
	
	# 累加伤害
	accumulated_damage += damage
	damage_pending = true
	
	# 计算显示位置（在BTB下方，版面外侧距边框一小段距离）
	var hold_pos = board_drawer._get_hold_position()
	var hold_height = board_drawer.hold_display_height * board_drawer.cell_size
	var bottom_y = hold_pos.y + hold_height
	var offset_y = damage_text_offset_y_cells * board_drawer.cell_size
	damage_text_position = Vector2(_get_text_anchor_x(), bottom_y + offset_y)
	
	if text_printer:
		# damage 文本固定显示：不漂移、不淡出，常驻直到计时器结束再移除
		text_printer.show_text("damage", "%d Attack" % accumulated_damage, damage_text_position,
			damage_text_color, damage_text_outline_color, board_drawer.cell_size * 0.9,
			true, 1.0)
	
	# 重置计时器（如果正在运行则停止并重新开始）
	if damage_timer.is_stopped():
		damage_timer.start()
	else:
		damage_timer.stop()
		damage_timer.start()
	
	board_drawer.queue_redraw()

## 检查并消除完整的行
func check_and_clear_lines() -> int:
	if is_animating or _is_clear_animating:
		return 0
	
	lines_to_clear = _find_complete_lines()
	# NoSpin模式（int）：0=正常Spin判定；2=跳过整个Spin判定；1=把所有Spin降级为MiniSpin
	var spin_type: String = "" if no_spin == 2 else _detect_spin_type()
	if no_spin == 1 and not spin_type.is_empty():
		spin_type = _force_mini_spin(spin_type)
	var clear_count = lines_to_clear.size()
	
	if clear_count == 0:
		if not spin_type.is_empty():
			# Spin0：显示spin文本，不显示消行文本
			_show_spin_text_only(spin_type)
			
			if spin0_btb_enabled:
				# 特殊情况：spin0触发BTB
				_update_btb(true)
			# 正常情况下spin0不触发BTB也不断开BTB
			
			reset_rotation_record()
			# 记录Spin0消行信息
			_last_clear_type = spin_type
			_last_clear_count = 0
		else:
			# 不去重置其他消行/Spin/连击文本，让它们自然淡出消失
			combo_count = 0
			reset_rotation_record()
			current_damage = 0
			has_cleared_lines = false
		# 没有可消除的行：消行处理结束，直接生成新方块
		_spawn_next_piece_after_clear()
		return 0
	
	# Allspin判定：落块时判定此消行是否与上次完全一致
	var is_allspin_repeat: bool = (tetris_allspin == 1 and clear_count > 0
		and clear_count == _last_clear_count and spin_type == _last_clear_type)
	
	has_cleared_lines = true
	var is_spin = not spin_type.is_empty()
	# 单独判断is_quad
	var is_quad = false
	if clear_count >= 4:
		is_quad = true
	# 判断是否触发BTB
	var is_spin_or_quad = false
	if is_quad:
		is_spin_or_quad = true
	if is_spin:
		is_spin_or_quad = true
	
	# 清除可消除的行（带可选消行动画延迟；动画结束后生成新方块）
	_clear_lines_animated(lines_to_clear)
	
	var damage = _calculate_damage(clear_count, spin_type)
	
	# PC判定：消行后场上没有任何方块
	var is_perfect_clear = _check_perfect_clear()
	if is_perfect_clear:
		damage += pc_damage  # PC额外伤害叠加
		_show_pc_text()
	elif text_printer:
		text_printer.remove_text("pc")
	
	current_damage = damage
	tower_controller.attack_increase_tower(damage)
	
	_update_btb_pc_aware(is_spin_or_quad, is_perfect_clear)
	
	# 添加到伤害累积显示
	_add_damage_to_display(damage)
	
	if is_spin and spin_color_ready:
		display_spin_color = pending_spin_color
	else:
		display_spin_color = Color.YELLOW
	
	_show_clear_and_spin_text(clear_count, spin_type, damage)
	
	reset_rotation_record()
	combo_count += 1
	
	# Allspin延续：消行计算完成后直接上涨一行垃圾行（不走延迟队列，类似突然死亡VIII）
	if is_allspin_repeat and garbage_line_controller:
		garbage_line_controller.insert_allspin_garbage_directly()
	
	# 记录本次消行信息（供下次Allspin比对）
	_last_clear_type = spin_type
	_last_clear_count = clear_count
	
	return clear_count

## 更新BTB状态
func _update_btb(is_spin_or_quad: bool):
	if is_spin_or_quad:
		if is_btb_active:
			# 第二次及之后连续四消/spin → BTB计数递增
			btb_count += 1
		else:
			# 第一次四消/spin → 开始计数（btb_count=1），但不显示BTB文本
			is_btb_active = true
			btb_count = 1
		_update_btb_text()
	else:
		btb_count = 0
		is_btb_active = false
		if text_printer:
			text_printer.remove_text("btb")
		board_drawer.queue_redraw()

## BTB 更新（带 PC 规则）：PC（Perfect Clear）时 BTB 链**不断开**，且计数 **+2**。
## 例：已有 BTB 链 3 → 5；此前没有 BTB → 直接 2（视作一次延续 + 额外一次）。
## 注意 _calculate_damage() 在本函数之前执行，所以本手 PC 的伤害仍按「本手之前的 BTB 状态」加成，
## 与原有「本次消行不计入自身加成」的口径一致。
func _update_btb_pc_aware(is_spin_or_quad: bool, is_perfect_clear: bool):
	if is_perfect_clear:
		if is_btb_active:
			btb_count += 2
		else:
			is_btb_active = true
			btb_count = 2
		_update_btb_text()
		return
	_update_btb(is_spin_or_quad)

## 更新BTB文本（常驻显示，不随消行淡出）
func _update_btb_text():
	var btb_text = _get_btb_text()
	if not text_printer:
		return
	if not btb_text.is_empty():
		var hold_pos = board_drawer._get_hold_position()
		var hold_height = board_drawer.hold_display_height * board_drawer.cell_size
		var bottom_y = hold_pos.y + hold_height
		var btb_offset_y = btb_text_offset_y_cells * board_drawer.cell_size
		btb_text_position = Vector2(_get_text_anchor_x(), bottom_y + btb_offset_y)
		# BTB常驻显示（persistent=true），直到断开BTB时才移除
		text_printer.show_text("btb", btb_text, btb_text_position,
			btb_text_color, btb_text_outline_color, board_drawer.cell_size * 1.0,
			true, 1.0)
	else:
		text_printer.remove_text("btb")

## 检查是否 Perfect Clear（场上没有任何方块）
func _check_perfect_clear() -> bool:
	# ⚠ 必须排除「当前方块自身」的格子：
	# clear_line_delay_time == 0（默认）时，_clear_lines_animated() 会在清行之后、本判定之前
	# 立刻调用 _spawn_next_piece_after_clear() → spawn_new_piece() → _draw_current_piece()，
	# 新方块的 4 格已经被写进 board_data。若不排除，board_data 永远非空 → PC 永远判不出来。
	var active_cells: Dictionary = {}
	if tetris_controller != null and not tetris_controller.current_piece.is_empty():
		var self_cells: Array = tetris_controller._get_piece_cells(
			tetris_controller.current_piece, tetris_controller.current_position)
		for c in self_cells:
			active_cells[c] = true
	for y in range(board_drawer.get_playable_height()):
		# 待清除的行（消行延迟期间仍物理存在）视为已清除
		if _pending_clear_lines.has(y):
			continue
		for x in range(board_drawer.grid_width):
			if active_cells.has(Vector2i(x, y)):
				continue
			if board_drawer.get_cell_color(x, y) != null:
				return false
	return true

## 显示 PC 文本
func _show_pc_text():
	if not text_printer:
		return
	var hold_pos = board_drawer._get_hold_position()
	var hold_height = board_drawer.hold_display_height * board_drawer.cell_size
	var bottom_y = hold_pos.y + hold_height
	var pc_offset_y = pc_text_offset_y_cells * board_drawer.cell_size
	pc_text_position = Vector2(_get_text_anchor_x(), bottom_y + pc_offset_y)
	text_printer.show_text("pc", "PERFECT CLEAR", pc_text_position,
		pc_text_color, pc_text_outline_color, board_drawer.cell_size * 1.2,
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
	
	# 记录本次消行的攻击值（base+spin，不含BTB加成），供连击公式使用
	var attack_value: int = base_damage + spin_damage
	
	# BTB 加成（从第二次连续BTB开始；btb>=4 时额外+1，即 +2）- 适用于 spin 和 quad
	if btb_count > 1:
		var btb_boost: int = 2 if btb_count >= 4 else 1
		if not spin_type.is_empty():
			spin_damage += btb_boost
		elif clear_count >= 4:
			base_damage += btb_boost
	
	if btb_count >= 4 and spin_type.is_empty() and clear_count < 4:
		surge_break = btb_count
	else:
		surge_break = 0
	
	var combo_damage = 0
	if combo_count > 0:
		if combo_formula == 1:
			# 新公式（默认）：
			#   combo_damage = floor(max(ln(1+1.25*combo), ((is_btb_active?1:0)+attack)*(1+0.25*combo)))
			#   其中 attack = base+spin（不含BTB加成）
			var b2b_flag: float = 1.0 if is_btb_active else 0.0
			var combined: float = (b2b_flag + float(attack_value)) * (1.0 + 0.25 * float(combo_count))
			var log_term: float = log(1.0 + 1.25 * float(combo_count))
			combo_damage = floori(max(log_term, combined))
		else:
			# 旧连击表（备选项）
			var is_mini: bool = spin_type.find("Mini") != -1
			var is_quad: bool = clear_count >= 4
			if not is_mini and is_quad:
				# 非mini spin且quad：伤害 +combo_count（x）
				combo_damage = combo_count
			elif is_mini:
				# mini spin：伤害 +floor(ln((x²/2)+1))
				combo_damage = floori(log(combo_count * combo_count / 3.0 + 1.0))
			else:
				# 其他情况：使用连击表
				var index = combo_count
				if index < combo_damage_list.size():
					combo_damage = combo_damage_list[index]
				else:
					var extra = (combo_count - combo_damage_list.size()) / 2.0
					combo_damage = min(5, combo_damage_list[-1] + extra)
	
	return base_damage + spin_damage + combo_damage + surge_break

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
	tbl["pc_damage"] = pc_damage
	# All-Spin 伤害表（独立表，默认同 T-Spin 值，可由 buff 调整）
	var allspin: Array = [0, 0, 0, 0]
	for i in range(1, 4):
		allspin[i] = allspin_damage_table.get(i, 0)
	tbl["allspin_damage"] = allspin
	# allspin_1 规则是否启用（tetris_allspin==1）
	tbl["allspin_enabled"] = (tetris_allspin == 1)
	# bot 评估权重：仅返回 buff 显式传参的键（bot_weight_override_keys 由
	# tower_controller._extra_data_deal 填充）。这样 bridge 默认权重为主，
	# 只有 buff 真正传了参的键才会覆盖 bridge。
	var bot_weights := {
		"eval_mult": bot_eval_mult,
		"attack_efficiency_weight": bot_attack_efficiency_weight,
		"b2b_clear": bot_b2b_clear,
		"height": bot_height,
		"clear4": bot_clear4,
		"clear1": bot_clear1,
		"clear2": bot_clear2,
		"clear3": bot_clear3,
		"tspin1": bot_tspin1,
		"tspin2": bot_tspin2,
		"tspin3": bot_tspin3,
		"mini_tspin1": bot_mini_tspin1,
		"mini_tspin2": bot_mini_tspin2,
		"allspin1": bot_allspin1,
		"allspin2": bot_allspin2,
		"allspin3": bot_allspin3,
		"allspin3plus": bot_allspin3plus,
		"perfect_clear": bot_perfect_clear,
		"combo_garbage": bot_combo_garbage,
		"wasted_t": bot_wasted_t,
		"move_time": bot_move_time,
		"allspin_repeat_penalty": bot_allspin_repeat_penalty,
	}
	for key in bot_weights:
		if bot_weight_override_keys.has(key):
			tbl[key] = bot_weights[key]
	return tbl

## 获取连击文本
func _get_combo_text() -> String:
	if combo_count > 0:
		return "%d Combo" % combo_count
	return ""

## 获取BTB文本
func _get_btb_text() -> String:
	if is_btb_active and btb_count > 1:
		return "%d x BTB" % (btb_count - 1)
	return ""

# ========== 查找完整行 ==========

func _find_complete_lines() -> Array:
	var complete_lines = []
	
	for y in range(board_drawer.get_playable_height()):
		if garbage_line_controller and garbage_line_controller.is_solid_garbage_row(y):
			continue
		
		var is_complete = true
		for x in range(board_drawer.grid_width):
			if board_drawer.get_cell_color(x, y) == null:
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
	
	board_drawer.queue_redraw()

func _clear_single_line(line_y: int):
	for y in range(line_y, 0, -1):
		for x in range(board_drawer.grid_width):
			var color = board_drawer.get_cell_color(x, y - 1)
			board_drawer.set_cell_color(x, y, color)
	
	for x in range(board_drawer.grid_width):
		board_drawer.set_cell_color(x, 0, null)

## 单个函数：清除可消除的行。
## 导入 clear_line_delay_time 变量：当 clear_line_delay_time > 0 时播放消行动画
## （对已清除的行区域进行闪烁提示，持续 clear_line_delay_time 秒），消行延迟计时结束
## （clear_line_delay_timer 超时）后才调用 spawn_new_piece 生成新方块；
## clear_line_delay_time == 0 时直接清除并立即生成新方块。
func _clear_lines_animated(lines: Array) -> void:
	if lines.is_empty():
		# 没有可消除的行：无需等待，直接生成新方块
		_spawn_next_piece_after_clear()
		return
	lines.sort()
	if clear_line_delay_time > 0:
		# 消行延迟期间：仅播放消行动画（完整行仍保留、不位移），
		# 延迟结束后才执行正式消行（位移）并生成新方块。
		_pending_clear_lines = lines
		if board_drawer:
			board_drawer.set_clearing_lines(lines)
		_is_clear_animating = true
		clear_line_delay_timer.wait_time = clear_line_delay_time
		clear_line_delay_timer.start()
	else:
		# 无延迟：立即执行正式消行（位移）并生成新方块
		_pending_clear_lines = []
		_clear_lines(lines)
		_spawn_next_piece_after_clear()

## 消行延迟计时结束：结束动画，执行正式消行（位移）并生成新方块
func _on_clear_line_delay_timeout():
	_is_clear_animating = false
	if board_drawer:
		board_drawer.clear_clearing_lines()
	# 消行延迟结束：此时才执行正式消行（把行进行位移清除）
	if not _pending_clear_lines.is_empty():
		_clear_lines(_pending_clear_lines)
		_pending_clear_lines = []
	# 消行延迟结束：恢复消行延迟期间被暂缓的垃圾行上涨（不丢弃行）
	if garbage_line_controller:
		garbage_line_controller.resume_rise_if_pending()
	# 消行延迟结束：生成新方块
	_spawn_next_piece_after_clear()

## 是否正处于消行动画/消行延迟中（供垃圾行控制器判断是否需暂缓上涨）
func is_clear_animating_active() -> bool:
	return _is_clear_animating

## 消行结束后生成新方块
func _spawn_next_piece_after_clear():
	if tetris_controller:
		tetris_controller.spawn_new_piece()

# ========== Spin检测系统 ==========

## NoSpin==1：把所有 Spin 类型强制降级为 MiniSpin（"T-Spin"→"Mini T-Spin"，已是 Mini 保持不变）。
## 这样 _calculate_damage 会命中 "Mini" 分支，采用 mini（基础）伤害表。
func _force_mini_spin(spin_type: String) -> String:
	if spin_type.is_empty():
		return ""
	if spin_type.find("Mini") != -1:
		return spin_type
	return "Mini " + spin_type

func _detect_spin_type() -> String:
	if no_spin == 2:
		return ""
	if not spin_detection_enabled:
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
	
	if tetris_allspin == 1:
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
	if not tetris_controller or not board_drawer:
		return false
	
	var directions = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	# 自身占据的格子（判定位置上的 shape）：碰撞查询时视为空 → 排除自身
	var self_cells: Array = tetris_controller._get_piece_cells(shape, piece_position)
	
	for dir in directions:
		var new_pos = Vector2i(piece_position.x + dir.x, piece_position.y + dir.y)
		# 纯查询（无清绘副作用），把自身格子视为空
		if not tetris_controller._check_collision_pure(new_pos, shape, self_cells):
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
	if x < 0 or x >= board_drawer.grid_width:
		return true
	# 底部超出边界 → 被地板封堵
	if y >= board_drawer.get_playable_height():
		return true
	# 上方超出边界 → 不算封堵（可在出块区域之上）
	if y < 0:
		return false
	# 检查该位置是否有方块
	if board_drawer.get_cell_color(x, y) != null:
		return true
	return false


# ========== 显示系统 ==========

func _get_clear_text(count: int) -> String:
	if clear_texts.has(count):
		return clear_texts[count]
	return ""

## 文本锚点X坐标：版面外侧，距离左边框一小段距离
func _get_text_anchor_x() -> float:
	return board_drawer.offset_x - text_gap_cells * board_drawer.cell_size

## 非BTB文本的漂移速度（向左慢慢移动）
func _get_text_drift() -> Vector2:
	return Vector2(-text_drift_cells_per_sec * board_drawer.cell_size, 0)

## 消行文本基准Y（Hold框底部）
func _get_text_base_y() -> float:
	var hold_pos = board_drawer._get_hold_position()
	var hold_height = board_drawer.hold_display_height * board_drawer.cell_size
	return hold_pos.y + hold_height

func _show_clear_and_spin_text(clear_count: int, spin_type: String, _damage: int):
	if clear_count <= 0 or not text_printer:
		return
	
	var clear_text = _get_clear_text(clear_count)
	if clear_text.is_empty():
		return
	
	var cell = board_drawer.cell_size
	var bottom_y = _get_text_base_y()
	var anchor_x = _get_text_anchor_x()
	
	var clear_spin_drift: Vector2 = _get_text_drift() * clear_spin_drift_scale
	var clear_spin_fade: float = text_fade_duration * clear_spin_fade_scale
	# 淡出与移动并行：这里把保持期缩短，让淡出在文本仍在移动时就开始
	var clear_spin_hold: float = clear_text_display_duration * clear_spin_hold_scale
	
	var offset_y = clear_text_offset_y_cells * cell
	clear_text_position = Vector2(anchor_x, bottom_y + offset_y)
	text_printer.show_text("clear", clear_text, clear_text_position,
		clear_text_color, clear_text_outline_color, cell * 1.0,
		false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	
	if not spin_type.is_empty():
		var spin_offset_y = (clear_text_offset_y_cells - spin_text_offset_y_cells) * cell
		spin_text_position = Vector2(anchor_x, bottom_y + spin_offset_y)
		text_printer.show_text("spin", spin_type, spin_text_position,
			display_spin_color, spin_text_outline_color, cell * 0.8,
			false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	else:
		text_printer.remove_text("spin")
	
	var combo_text = _get_combo_text()
	if not combo_text.is_empty():
		var combo_offset_y = (clear_text_offset_y_cells + combo_text_offset_y_cells) * cell
		combo_text_position = Vector2(anchor_x, bottom_y + combo_offset_y)
		# combo 特例：有新 combo 时立即重置，移除旧文本后再显示新的，不做叠加
		text_printer.remove_text("combo")
		text_printer.show_text("combo", combo_text, combo_text_position,
			combo_text_color, combo_text_outline_color, cell * 0.8,
			false, text_base_opacity, clear_text_display_duration, text_fade_duration, _get_text_drift())
	else:
		text_printer.remove_text("combo")
	
	# BTB常驻显示（persistent=true）
	var btb_text = _get_btb_text()
	if not btb_text.is_empty():
		var btb_offset_y = btb_text_offset_y_cells * cell
		btb_text_position = Vector2(anchor_x, bottom_y + btb_offset_y)
		text_printer.show_text("btb", btb_text, btb_text_position,
			btb_text_color, btb_text_outline_color, cell * 1.0,
			true, 1.0)
	else:
		text_printer.remove_text("btb")
	
	##print("消行: ", clear_count, "，Spin: ", spin_type, "，伤害: ", damage, "，Spin颜色: ", display_spin_color)

## 仅显示Spin文本（无消行，Spin0）
func _show_spin_text_only(spin_type: String):
	if spin_type.is_empty() or not text_printer:
		return
	
	if spin_color_ready:
		display_spin_color = pending_spin_color
	else:
		display_spin_color = Color.YELLOW
	
	var cell = board_drawer.cell_size
	# 计算spin文本位置
	spin_text_position = Vector2(_get_text_anchor_x(), _get_text_base_y() + spin_text_offset_y_cells * cell)
	var clear_spin_drift: Vector2 = _get_text_drift() * clear_spin_drift_scale
	var clear_spin_fade: float = text_fade_duration * clear_spin_fade_scale
	var clear_spin_hold: float = clear_text_display_duration * clear_spin_hold_scale
	text_printer.show_text("spin", spin_type, spin_text_position,
		display_spin_color, spin_text_outline_color, cell * 0.8,
		false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift)
	# 不重置其他文本，让它们自然淡出

## 获取当前显示的Spin文本颜色
func get_spin_trigger_color() -> Color:
	return display_spin_color

## 检查是否有消行文本正在显示
func is_text_displaying() -> bool:
	return text_printer != null and text_printer.has_text("clear")

## 获取当前显示的Spin文本（供TetrisController统计用）
func get_current_spin_text() -> String:
	if text_printer:
		return text_printer.get_text("spin")
	return ""

## 重置消行状态
func reset():
	lines_to_clear.clear()
	is_animating = false
	if text_printer:
		text_printer.clear_all()
	damage_timer.stop()
	reset_rotation_record()
	combo_count = 0
	btb_count = 0
	is_btb_active = false
	current_damage = 0
	accumulated_damage = 0
	damage_pending = false
	clear_spin_color()
	has_cleared_lines = false

## 获取当前连击数
func get_combo_count() -> int:
	return combo_count

## 获取当前BTB数
func get_btb_count() -> int:
	return btb_count

## 手动设置连击（用于调试）
func set_combo(count: int):
	combo_count = count

## 手动设置BTB（用于调试）
func set_btb(count: int):
	btb_count = count
	is_btb_active = count > 0
