extends Node2D
class_name TowerController

static var ATTACK_DATA_PATH : String = "user://Savedatas/attack_setting.json"
static var FLOOR_HIGHER : Array = [0,50,150,300,450,650,850,1100,1350,1650,2550,3000,3500,4500,5500,6500,8000,9500,11000]

@export var tetris_controller: TetrisController
@export var garbage_line_controller: TetrisGarbageLineController
@export var board_drawer: TetrisBoardDrawer
@export var clear_line_controller: TetrisClearLine
@export var text_printer: TextPrinter      # 文本打印器（米数增长飘字用；MainBoard/TextPrinter）

@onready var tower_rng = RandomManager.get_random("TOWER_CLIMB")

var total_apm : float = 100.0
var stage_percent_apm : Array = [0.01,0.02,0.05,0.1,0.25,0.4,0.5,0.6,0.75,0.8,1]
var current_stage : int = 0
var current_apm : float = 0
var extra_percent_apm : float = 0

var publish_time_array : Array = [0,60*7,60*8,60*9,60*10,60*11]
var publish_stage : int = 0
var publish_make_finish : int = 0
var publish_mult_attack : float = 1.0

var stage_garbage_time : Array = [5,5,4,4,4,3,3,3,2,2,2,1,1,1,0.75,0.75,0.5]
var stage_garbage_divide : Array = []
var garbage_collect_percent : float = 0.1
var garbage_collect_percent_array: Array = [0.4,0.3,0.2,0.1,0.1,0.2,0.2,0.3,0.4,0.5]
var garbage_sent_time : float = 0
var garbage_divide_percent : float = 0
var garbage_divide_percent_array: Array = [0.8,0.6,0.4,0.2,0.2,0.1,0.1,0,0.1,0.2,0.3]
var garbage_hole_change_percent_array: Array = [0.1,0.1,0.1,0.2,0.2,0.3,0.3,0.4,0.4,0.5]
var collected_count : int = 0
var collected_garbage : Array = []
var pressure_mult_array: Array = [1,1,1,1,1,1,1,1,1,1,1.25,1.5,1.75,2,2.25,2.5,2.75,3,3.5]
var pressure_mult : float = 1.0
## 压力（高压 buff）附加倍率：由 buff 参数直接传入（Pressure1/2/3 → 1.2/1.3/1.5），
## 与关卡自带的 pressure_mult（由 pressure_mult_array 按层数取值）相乘后，只作用于
## 塔的「发送攻击」，不改变 total_apm / current_apm 本身（界面上也不再显示 APM 变化）。
## 走通用的 buff 参数通道（get_buffed_tower_data 的「数值相乘」），不再是界面特判。
var extra_pressure_mult : float = 1.0
var send_mult_attack: float = 1.0

# ---- 出招「小数余量」----
# apm 的定义是 attack per minute（每分钟固定总量），而每次出招的间隔不定，
# 所以每拍应出的行数 = apm/60 × 这一拍实际经过的时间；行数必须是整数，零头不能丢也不能多给，
# 于是用两个余量累加器把零头留到下一拍 —— 保证长期总量恰为 apm × 倍率（不再被 ceil 放大）。
var attack_remainder : float = 0.0    # 「每拍按 apm 应出行数」的零头
var send_remainder : float = 0.0      # 「乘完倍率待发送行数」的零头
var _send_elapsed : float = 0.0       # 本拍已累计的经过时间（发招时用来还原这段时间的攻击量）

var gravity_drop_time_array: Array = [5,5,5,5,5,4.8,4.6,4.4,4.2,4]
var lock_delay_array: Array = [1]

var tower_meter: float = 0.0            
var tower_speed_meter: float = 0.0      
var tower_lowest_speed: float = 0.1
var tower_dropped_mult: Array = [0.8,0.9,1,1,1,1.1,1.2,1.3,1.4,1.5,1.7,1.9,2]
var tower_current_dropped_mult: float = 1.0
var attack_to_meter_mult: float = 0.2
var attack_to_speed_mult: float = 0.1

var warning_count : int = 4
var segment_line : int = 4
var big_attack_enter_array : Array = []
var big_attack_delay : float = 4.0

var kill_count: int = 0
var base_killer_spike: int = 10
var base_kill_possible_percent: float = 0.2
var kill_reward: Array = [30,2]

# ---- 米数增长飘字（attack_increase_tower / 击杀奖励 触发，显示在「爬塔米数」文字位置）----
# 表现：朝上浮现、幅度小、衰减快，位置在版面下侧（米数文字处），不会遮挡版面。
## 飘字类型：只决定颜色（数值与运动表现一致）
##   NORMAL        普通攻击奖励 → 绿色
##   OFFSET_REWARD 抵消垃圾行的防御奖励 → 红色
##   KILL_REWARD   击杀奖励 → 金色
enum MeterPopupType { NORMAL, OFFSET_REWARD, KILL_REWARD }

var attack_popup_enabled : bool = true
var attack_popup_key : String = "tower_gain"        # TextPrinter 中区分文本用的 key
var attack_popup_font_size_ratio : float = 0.4      # 基础字号（相对 cell_size，略小于米数文字）
var attack_popup_font_grow : float = 1.1           # 增幅越大字号越大（对数函数 → 增长逐渐变缓）
var attack_popup_grow_ref : float = 1.0             # 字号增长函数的参考增幅（米）
var attack_popup_max_font_scale : float = 2.4       # 字号增长上限倍数（避免大字压住版面）
var attack_popup_color : Color = Color(0.55, 1.0, 0.6)
var attack_popup_outline_color : Color = Color(0.04, 0.1, 0.05, 1.0)
# 抵消垃圾行得到的「防御奖励」飘字：用红色与普通攻击奖励（上面的绿色）区分
var attack_popup_offset_color : Color = Color(1.0, 0.42, 0.38)
var attack_popup_offset_outline_color : Color = Color(0.16, 0.03, 0.03, 1.0)
# 击杀奖励（try_give_kill_reward）飘字：金色
var attack_popup_kill_color : Color = Color(1.0, 0.84, 0.25)
var attack_popup_kill_outline_color : Color = Color(0.22, 0.13, 0.0, 1.0)
var attack_popup_display_time : float = 0.1        # 保持时间（几乎立刻开始淡出）
var attack_popup_fade_time : float = 0.8          # 淡出时长（衰减快）
var attack_popup_rise_speed : float = 80.0         # 上浮初速度（像素/秒）——起步最快，随后迅速变慢
var attack_popup_drift_x : float = 30.0             # 横向初速度（像素/秒，方向随机；与X偏移、旋转同向）
var attack_popup_drift_decay : float = 6.0          # 速度衰减速率（/秒，越大越快停）→ 加速度由快变慢
var attack_popup_spread : float = 40.0              # 起始 X 轴偏移量（像素，范围 -x ~ +x，方向随机）
var attack_popup_rotate_deg : float = 10.0          # 旋转角度偏移量上限（±度）
# 去重叠：一次消行常常同时给「普通攻击奖励」和「抵消奖励」（甚至多条击杀奖励），
# 它们会在同一瞬间、同一位置弹出，随机横向偏移又可能撞在一起，导致两个字完全重叠、谁都看不清。
# 处理方式：每条飘字出场前按「实际文字宽度」检查与在场飘字（anti_overlap_time 秒内）的横向重叠量，
# 超过 max_overlap_ratio 就往旁边让位 —— 允许部分重叠，但不会两个完全叠在一起。
var attack_popup_max_overlap_ratio : float = 0.25  # 允许的最大横向重叠比例（相对较窄那条字宽）；0=完全不重叠
var attack_popup_anti_overlap_time : float = 0.6   # 视为「同时在场」的时间窗（秒），窗内互相避让

var _popup_boxes : Array = []                       # 在场飘字的横向占位：[{x, half_w, until_msec}]

signal big_attack_warning_started()
signal big_attack_warning_ended()
signal stage_changed(previous_stage: int, new_stage: int)

var _previous_stage: int = 0  # 用于检测阶段变化

var extra_data_dict: Dictionary = {}

var garbage_sent_timer : Timer
var big_attack_delay_timer : Timer

var self_game_time : float

func _ready() -> void:
	_auto_finding()
	_set_game_var()
	_extra_data_deal()
	_set_timer()
	_previous_stage = current_stage

func _auto_finding():
	# 飘字用的文本打印器：MainBoard 下的 TextPrinter（与版面、消行文本同层，坐标系一致）
	if not text_printer:
		text_printer = get_node_or_null("../MainBoard/TextPrinter")
		if not text_printer:
			push_warning("TowerController: 未找到TextPrinter节点，米数增长飘字将不可用")
	
	if not tetris_controller:
		tetris_controller = get_node_or_null("../TetrisBoardDrawer")
		if not tetris_controller:
			push_error("TetrisController: 未找到TetrisBoardDrawer节点！")
			return
			
	if not garbage_line_controller:
		garbage_line_controller = get_node_or_null("../TetrisBoardDrawer")
		if not garbage_line_controller:
			push_error("TetrisController: 未找到TetrisBoardDrawer节点！")
			return
			
	if not board_drawer:
		board_drawer = get_node_or_null("../TetrisBoardDrawer")
		if not board_drawer:
			board_drawer = get_node_or_null("../../MainBoard/TetrisBoardDrawer")
	

func _set_game_var():
	# 从 GlobalData 读取 buff_chose_area 配置的初始数据，覆盖本地默认值
	var init_data: Dictionary = GlobalData.tower_init_data
	if not init_data.is_empty():
		for key: String in init_data:
			if key in self:
				self[key] = init_data[key]
			else:
				push_warning("TowerController 未知变量: ", key)
	
	current_stage = 0

func _extra_data_deal():
	if extra_data_dict.has("send_mult_attack"):
		send_mult_attack = extra_data_dict["send_mult_attack"]
	
	if extra_data_dict.has("mult_defend"):
		if garbage_line_controller:
			garbage_line_controller.mult_defend = extra_data_dict["mult_defend"]
	if extra_data_dict.has("garbage_rise_time_delay"):
		garbage_line_controller.garbage_rise_time_delay = extra_data_dict["garbage_rise_time_delay"]
	if extra_data_dict.has("garbage_cap"):
		garbage_line_controller.garbage_cap = extra_data_dict["garbage_cap"]
	if extra_data_dict.has("buffer_duration"):
		garbage_line_controller.buffer_duration = extra_data_dict["buffer_duration"]
	if extra_data_dict.has("suddenly_death_mode"):
		garbage_line_controller.suddenly_death_mode = extra_data_dict["suddenly_death_mode"]
	if extra_data_dict.has("drop_limit_cancel"):
		garbage_line_controller.drop_limit_cancel = extra_data_dict["drop_limit_cancel"]
	
	if extra_data_dict.has("tetris_invisible"):
		if board_drawer:
			board_drawer.tetris_invisible = extra_data_dict["tetris_invisible"]
			board_drawer.call_deferred("_init_invisible_mode")
	if extra_data_dict.has("visible_time_between"):
		if board_drawer:
			board_drawer.visible_time_between = extra_data_dict["visible_time_between"]
	if extra_data_dict.has("visible_show_time"):
		if board_drawer:
			board_drawer.visible_show_time = extra_data_dict["visible_show_time"]
	if extra_data_dict.has("drop_visible_time"):
		if board_drawer:
			board_drawer.drop_visible_time = extra_data_dict["drop_visible_time"]
	
	if extra_data_dict.has("spin0_btb_enabled"):
		if clear_line_controller:
			clear_line_controller.spin0_btb_enabled = extra_data_dict["spin0_btb_enabled"]
	
	# BtbBonus（Btb奖励）：切换 TetrisClearLine 的 BTB 加成系统
	#   1 = surge break 系统（默认）
	#   2 = 累加奖励系统（tetr.io S1 的 BTB 伤害系统，走 _get_btb_bonus() 的 btb_system_use==2 分支）
	# 该值还会经 zzz_bridge 的 CFG 第 12 个字段下发给 worker，使 bot 的伤害模拟与游戏结算一致。
	if extra_data_dict.has("BtbBonus"):
		if clear_line_controller:
			clear_line_controller.btb_system_use = int(extra_data_dict["BtbBonus"])
	
	if extra_data_dict.has("tetris_allspin"):
		clear_line_controller.tetris_allspin = extra_data_dict["tetris_allspin"]

	# bot 参数覆盖（ExtraBotChange）：勾选的 buff → zzztoj AI 参数（键名 = ai_zzz::IO::Param 字段名，
	# 另支持 repeat_penalty）。未列出的参数保持 worker 默认（zzz 自带 io-DLL 调参）。
	if extra_data_dict.has("ExtraBotChange"):
		var extra_bot = extra_data_dict["ExtraBotChange"]
		if typeof(extra_bot) == TYPE_DICTIONARY and tetris_controller != null:
			tetris_controller.set_bot_param_overrides(extra_bot)

	# bot 并行搜索线程数（buff 可调，0 = 由 bridge 自动决定）
	if extra_data_dict.has("bot_threads"):
		clear_line_controller.bot_threads = int(extra_data_dict["bot_threads"])

	# Talentless（无才能）/ NoSpin（Spin判定）：NoSpin 为 int
	#   0=正常Spin判定（含Allspin）；1=只判定T-Spin（不判Allspin）；2=全部Spin降级为MiniSpin；3=不判定Spin
	if extra_data_dict.has("NoSpin"):
		if clear_line_controller:
			clear_line_controller.no_spin = int(extra_data_dict["NoSpin"])
	
	# ShortNext（短见）：限制 Next 显示数量 / 是否显示 Next 区
	#   next_display_enabled=false（短见V）→ 不显示 next
	#   next_count=N（短见I-IV）→ 显示 N 个 next
	var next_changed: bool = false
	if extra_data_dict.has("next_display_enabled"):
		if board_drawer:
			board_drawer.next_display_enabled = bool(extra_data_dict["next_display_enabled"])
			next_changed = true
	if extra_data_dict.has("next_count"):
		if board_drawer:
			board_drawer.next_count = clampi(int(extra_data_dict["next_count"]), 1, 7)
			next_changed = true
	# 首块可能在 TowerController._ready 之前已生成（此时用的是默认 next_count），
	# 立即刷新一次 Next 显示，使 buff 立刻生效、next_pieces_data 与 next_count 一致。
	if next_changed and tetris_controller and tetris_controller.has_method("_update_next_display"):
		tetris_controller._update_next_display()
	
	# DoubleHole：垃圾行洞口形态
	# garbage_hole_wide_count = X宽（每行一组紧邻连续洞口）；garbage_hole_count = 每行洞口数量。
	# 两者互斥且默认 1（一个洞且 1 宽）；若同时被覆盖（均 > 1）则报错并不应用。
	if extra_data_dict.has("garbage_hole_wide_count") or extra_data_dict.has("garbage_hole_count"):
		var dh_wide: int = int(extra_data_dict.get("garbage_hole_wide_count", 1))
		var dh_holes: int = int(extra_data_dict.get("garbage_hole_count", 1))
		if dh_wide > 1 and dh_holes > 1:
			push_error("DoubleHole参数冲突：garbage_hole_wide_count 与 garbage_hole_count 互斥，不能同时大于1")
		elif garbage_line_controller:
			garbage_line_controller.garbage_hole_wide_count = dh_wide
			garbage_line_controller.garbage_hole_count = dh_holes
	
	# NoHold模式：关闭Hold显示并禁用Hold输入（JSON中键名为"NoHold"）
	if extra_data_dict.has("NoHold") or extra_data_dict.has("no_hold"):
		var no_hold_value: bool = extra_data_dict.get("NoHold", extra_data_dict.get("no_hold", false))
		if tetris_controller:
			tetris_controller.no_hold = no_hold_value
		if board_drawer:
			board_drawer.no_hold = no_hold_value
	
	if extra_data_dict.has("BotMode"):
		tetris_controller.bot_mode = true

	# 旋转系统：关卡/Buff 可覆盖（0=ASC / 1=SRS / 2=ARS / 3=NONE 无旋转系统，
	# 也接受 "ASC"/"SRS"/"ARS"/"NONE"）
	#   rotation_system / RotationSystem —— 既有键名
	#   RotateSystem                     —— buff「旋转系统」写入的键名（RotateSystem_1/2/3）
	if extra_data_dict.has("rotation_system") or extra_data_dict.has("RotationSystem") \
			or extra_data_dict.has("RotateSystem"):
		var rs = extra_data_dict.get(
			"rotation_system",
			extra_data_dict.get("RotationSystem", extra_data_dict.get("RotateSystem")))
		if tetris_controller:
			tetris_controller.set_rotation_system(rs)
		if tetris_controller and tetris_controller.bot_debug_log:
			print("[旋转系统] 由关卡/Buff 切换为 ", tetris_controller.get_rotation_system_name())

	# StartBoard：按参数直接印刷自定义初始版面（从下往上）。
	# 版面由 BuffChoseData 的 StartBoard 参数（二维数组）指定，第 0 行为最底层（最大 y）。
	# 宽度与版面不一致或行数超出可玩高度时 push_error。
	# 印刷通过 set_cell_color 直接写入 board_data；bot 在请求决策时实时读取 board_data
	# （coldclear_bridge._build_board_rows），因此无需额外同步，bot 会自动看到该改写的初始版面。
	if extra_data_dict.has("StartBoard"):
		_print_start_board(extra_data_dict["StartBoard"])

## 按 StartBoard 参数印刷初始版面（从下往上印刷）。
## 第 0 行为最底层（最大 y），后续行依次向上。
## 宽度与版面不一致（行宽 != grid_width）或行数超出可玩高度 → push_error。
## 通过 set_cell_color 写入 board_data，bot 实时读取 board_data，因此自动同步给 bot。
func _print_start_board(start_board: Variant) -> void:
	if board_drawer == null:
		push_error("StartBoard: 未找到 board_drawer，无法印刷初始版面")
		return
	# board_data 需已初始化（grid_width × grid_max_height）；若尚未初始化则延迟到所有节点 _ready 完成后印刷
	if board_drawer.board_data.is_empty():
		_print_start_board.call_deferred(start_board)
		return
	if typeof(start_board) != TYPE_ARRAY or start_board.is_empty():
		push_error("StartBoard: 参数必须是非空二维数组（从下往上）")
		return
	var grid_w: int = board_drawer.grid_width
	var playable_h: int = board_drawer.get_playable_height()
	var rows: int = start_board.size()
	if rows > playable_h:
		push_error("StartBoard: 高度超出，行数 %d > 可玩高度 %d" % [rows, playable_h])
		return
	for i in range(rows):
		var row: Variant = start_board[i]
		if typeof(row) != TYPE_ARRAY:
			push_error("StartBoard: 第 %d 行不是数组，格式错误" % i)
			return
		if row.size() != grid_w:
			push_error("StartBoard: 宽度不匹配，第 %d 行宽度 %d != 版面宽度 %d" % [i, row.size(), grid_w])
			return
		var y: int = playable_h - 1 - i  # 从下往上：第 0 行印在最底层（最大 y）
		for x in range(grid_w):
			var color: Variant = _start_board_cell_to_color(row[x], i, x)
			board_drawer.set_cell_color(x, y, color)
	board_drawer.queue_redraw()

## 将 StartBoard 单元格值转换为颜色。
## null / 空字符串 / 0 → 空；字符串支持颜色名与十六进制（如 "#RRGGBB"）；
## 特殊标记 "solid"/"实心" → 实心垃圾深灰，"garbage"/"垃圾" → 普通垃圾灰。
func _start_board_cell_to_color(cell: Variant, row_i: int, col_i: int) -> Variant:
	if cell == null:
		return null
	var t := typeof(cell)
	if t == TYPE_STRING:
		var s: String = str(cell).strip_edges().to_lower()
		if s.is_empty() or s == "0" or s == "null" or s == "empty" or s == "空":
			return null
		if s == "solid" or s == "实心":
			return garbage_line_controller.solid_garbage_color if garbage_line_controller else Color(0.3, 0.3, 0.3)
		if s == "garbage" or s == "垃圾":
			return garbage_line_controller.garbage_color if garbage_line_controller else Color(0.5, 0.5, 0.5)
		var c: Color = Color.from_string(s, Color(-999, -999, -999))
		if c.r < -100 or c.g < -100 or c.b < -100:
			push_error("StartBoard: 无法解析颜色 '%s'（第 %d 行第 %d 列）" % [str(cell), row_i, col_i])
			return null
		return c
	if t == TYPE_FLOAT or t == TYPE_INT:
		var v: float = cell
		if is_zero_approx(v):
			return null
		push_error("StartBoard: 不支持的数值单元格 %s（第 %d 行第 %d 列）" % [str(cell), row_i, col_i])
		return null
	push_error("StartBoard: 未知单元格类型 %s（第 %d 行第 %d 列）" % [str(cell), row_i, col_i])
	return null

## 供 bot 读取当前关卡 buff 调整后的攻击倍率（send_mult_attack）。
func get_send_mult_attack() -> float:
	return send_mult_attack

## 当前实际生效的压力倍率 = 关卡自带 pressure_mult（按层数取表）× 压力 buff 传入的 extra_pressure_mult。
## 塔的发送攻击（普通攻击与 !!!! 大招）都用它，攻击总量与「倍率直接乘在 APM 上」等价。
func get_pressure_mult() -> float:
	return pressure_mult * extra_pressure_mult

func _set_timer():
	garbage_sent_timer = Timer.new()
	garbage_sent_timer.one_shot = true
	garbage_sent_timer.timeout.connect(_try_sent_garbage)
	add_child(garbage_sent_timer)
	
	big_attack_delay_timer = Timer.new()
	big_attack_delay_timer.wait_time = big_attack_delay
	big_attack_delay_timer.one_shot = true
	big_attack_delay_timer.timeout.connect(_warning_big_collected_enter)
	add_child(big_attack_delay_timer)

func _process(delta: float) -> void:
	for i in range(0,FLOOR_HIGHER.size()):
		if tower_meter > FLOOR_HIGHER[i]:
			current_stage = i
	
	#阶段变化检测
	if current_stage != _previous_stage:
		stage_changed.emit(_previous_stage, current_stage)
		_previous_stage = current_stage
	
	total_get_data()
	
	publish_make()
	
	if garbage_sent_time != 0 and garbage_sent_timer.is_stopped():
		# 新的一拍：本拍计时归零，并安排下一次出招（间隔带 ±50% 抖动）
		_send_elapsed = 0.0
		garbage_sent_timer.wait_time = garbage_sent_time + tower_rng.randf_range(-garbage_sent_time/2.0,garbage_sent_time/2.0)
		garbage_sent_timer.start()
	elif garbage_sent_time != 0:
		# 本拍进行中：累计实际经过时间，发招时用它还原「这段间隔内按 apm 应出的攻击量」
		_send_elapsed += delta
	
	_tower_climb(delta)


func total_get_data():
	self_game_time = tetris_controller.game_time
	
	garbage_sent_time = default_get_oneD_array_things(current_stage,stage_garbage_time)
	tower_current_dropped_mult = default_get_oneD_array_things(current_stage,tower_dropped_mult)
	pressure_mult = default_get_oneD_array_things(current_stage,pressure_mult_array)
	var max_percent = default_get_oneD_array_things(current_stage,stage_percent_apm) + extra_percent_apm
	if max_percent > 1:
		max_percent = 1
	current_apm = total_apm * max_percent
	garbage_collect_percent = default_get_oneD_array_things(current_stage,garbage_collect_percent_array)
	garbage_divide_percent = default_get_oneD_array_things(current_stage,garbage_divide_percent_array)
	garbage_line_controller.garbage_messy = default_get_oneD_array_things(current_stage,garbage_hole_change_percent_array)
	# 重力/锁延：走 TetrisController 的 setter，除字段外还要同步对应计时器的 wait_time
	# （只改字段的话，关卡/Buff 设置的重力与锁延不会真正生效）
	tetris_controller.set_gravity_drop_time(default_get_oneD_array_things(current_stage,gravity_drop_time_array))
	tetris_controller.set_lock_delay(default_get_oneD_array_things(current_stage,lock_delay_array))

##惩罚处理
func publish_make():
	for i in range(0,publish_time_array.size()):
		if self_game_time > publish_time_array[i]:
			publish_stage = i
	
	if publish_make_finish != publish_stage:
		if publish_stage == 1:
			garbage_line_controller.add_solid_garbage(2)
		if publish_stage == 2:
			publish_mult_attack = 1.2
		if publish_stage == 3:
			garbage_line_controller.add_solid_garbage(3)
		if publish_stage == 4:
			publish_mult_attack = 1.5
		if publish_stage == 5:
			garbage_line_controller.add_solid_garbage(5)
	
		publish_make_finish = publish_stage

##爬塔米数主要处理
func _tower_climb(delta: float):
	if tower_speed_meter < tower_lowest_speed:
		tower_speed_meter = tower_lowest_speed
	elif tower_speed_meter > tower_lowest_speed:
		var x = tower_speed_meter
		#降速公式计算
		#这是第一版
		#tower_speed_meter -= ((x*log(x) + x)/120.0) * delta * tower_current_dropped_mult
		#这是第二版
		tower_speed_meter -= (ceil(0.4*pow(x,1.5)*log(x))/75.0) * delta * tower_current_dropped_mult
	else:
		pass
	
	#TODO::制作一个特殊的分界线，在分界线下无速度加成，在上有微弱加成，突破界限后加成幅度突变上涨并且触发特殊特效，持续到回落界限下位置
	
	tower_meter += tower_speed_meter * delta

##塔的模拟伤害攻击
func _try_sent_garbage():
	# 这段间隔内按 apm 应出的行数 = apm / 60 × 实际间隔（apm 是每分钟的固定量，间隔不定，用它还原这一拍的攻击量）。
	# 行数只能取整，零头累加到下一拍，保证长期总量恰好是 apm（用 ceil 会把每拍的零头都补成 1 行，凭空放大总量）。
	var interval : float = _send_elapsed
	if interval <= 0.0:
		interval = garbage_sent_time                     # 兜底：直接调用/首拍
	interval = clampf(interval, 0.0, maxf(garbage_sent_time, 0.001) * 2.0)  # 卡顿/暂停后不补发一整段
	_send_elapsed = 0.0
	attack_remainder += current_apm / 60.0 * interval
	var decided_attack : int = int(floor(attack_remainder))
	attack_remainder -= float(decided_attack)
	var i = 0
	while decided_attack > 0:
		var j = tower_rng.randf()
		decided_attack -= 1
		i += 1
		if j < garbage_divide_percent:
			collected_garbage.append(i)
			i = 0
		if decided_attack == 0:
			if i != 0:
				collected_garbage.append(i)
			break
	# 这一拍不足 1 行（零头已留到下一拍）：不做「攒大招 / 收集计数 / 发送」判定，
	# 否则会在空批次上凑满 collected_count 触发一次没有攻击的 !!!! 警示
	if collected_garbage.is_empty():
		return
	if tower_rng.randf() > garbage_collect_percent:
		if collected_count >= warning_count and big_attack_enter_array.size() == 0:
			big_attack_enter_array = collected_garbage.duplicate()
			collected_garbage.clear()
			_quick_big_attack_clear(4)
			big_attack_delay_timer.start()
			big_attack_warning_started.emit()
		else:
			_tower_garbage_sent(collected_garbage)
			collected_garbage.clear()
		collected_count = 0
	else:
		i = floor(collected_garbage.size() / 2.0)
		var temp_sent_garbage : Array
		while i > 0:
			i -= 1
			temp_sent_garbage.append(collected_garbage[0])
			collected_garbage.remove_at(0)
		_tower_garbage_sent(temp_sent_garbage)
		collected_count += 1

func _tower_garbage_sent(attack: Array):
	var mult : float = send_mult_attack * publish_mult_attack * get_pressure_mult()
	for i in attack:
		# 乘倍率后的行数同样只取整数、零头累加，保证总量恰为「攻击行数 × 倍率」（ceil 会按段放大）
		send_remainder += float(i) * mult
		var rows : int = int(floor(send_remainder))
		if rows > 0:
			send_remainder -= float(rows)
			garbage_line_controller.add_attack(rows)

##快速重新分割攻击储存列表并形成!!!!攻击
func _quick_big_attack_clear(segment: int):
	var total_attack: int = 0
	for i in big_attack_enter_array:
		total_attack += i
	big_attack_enter_array.clear()
	# 乘倍率时也用零头累加（而不是 ceil），避免大招总量被向上取整放大
	send_remainder += float(total_attack) * send_mult_attack * publish_mult_attack * get_pressure_mult()
	total_attack = int(floor(send_remainder))
	send_remainder -= float(total_attack)
	for i in range(0,segment):
		if total_attack <= segment_line:
			big_attack_enter_array.append(total_attack)
			total_attack = 0
			break
		big_attack_enter_array.append(segment_line)
		total_attack -= segment_line
	if total_attack != 0:
		big_attack_enter_array.append(total_attack)

##!!!!攻击警示器
func _warning_big_collected_enter():
	big_attack_warning_ended.emit()
	garbage_line_controller.add_attack(big_attack_enter_array[0])
	if big_attack_enter_array.size() > 1:
		big_attack_delay_timer.wait_time = 0.5
		big_attack_enter_array.remove_at(0)
		big_attack_delay_timer.start()
	else:
		big_attack_delay_timer.wait_time = big_attack_delay
		big_attack_enter_array.clear()

##内置的检索，默认超出列表范围时返回列表最后一项，仅能用于一维列表
func default_get_oneD_array_things(id:int,array:Array):
	if id >= array.size():
		return array[array.size()-1]
	else:
		return array[id]

## 米数/速度增长。
## is_defence=true 表示「抵消垃圾行」得到的防御奖励（由 garbage_line_controller.offset_garbage()
## 的结果经 TetrisController 传入）：米数与速度的计算与普通攻击奖励完全一致，
## 只是飘字用红色，以便和普通攻击奖励（绿色）区分开。
func attack_increase_tower(attack:float, is_defence:bool = false):
	var meter_gain : float = attack * attack_to_meter_mult
	tower_meter += meter_gain
	
	tower_speed_meter += attack * attack_to_speed_mult
	
	#在米数位置朝上弹出 "+X.XXm" 字样（幅度小、衰减快，避免遮挡版面）
	if attack > 0.0:
		_popup_meter_gain(meter_gain, MeterPopupType.OFFSET_REWARD if is_defence else MeterPopupType.NORMAL)

## 在「爬塔米数」文字位置弹出一条 "+X.XXm" 飘字。
## 位置由 board_drawer.get_tower_meter_text_position() 给出（版面下侧居中，与米数文字同点，
## 因此不会遮挡版面）；
## 运动：把 drift 交给 TextPrinter，由其按 attack_popup_drift_decay 做指数减速
##（加速度由快变慢：初速 80px/s 起步，随即迅速变慢），加上随机横向速度与 ±10° 倾斜，
## 在淡出结束前总位移约 18px（不到 1 格），随后淡出消失。
## popup_type 只决定颜色：NORMAL=绿色 / OFFSET_REWARD=红色 / KILL_REWARD=金色。
## 横向位置由 _resolve_popup_offset_x() 按实际文字宽度避让（见上方说明），不会与在场飘字完全重叠。
func _popup_meter_gain(gain: float, popup_type: MeterPopupType = MeterPopupType.NORMAL) -> void:
	if not attack_popup_enabled or text_printer == null or gain <= 0.0:
		return
	if board_drawer == null:
		return
	_spawn_meter_popup(gain, int(popup_type))

## 真正生成一条飘字：算字号/颜色 → 找一个不与在场飘字完全重叠的横向位置 → 交给 TextPrinter
func _spawn_meter_popup(gain: float, popup_type: int) -> void:
	var base_size: float = attack_popup_font_size_ratio * float(board_drawer.cell_size)
	var font_size: float = base_size * _popup_font_scale(gain)
	var text: String = "+%.2fm" % gain
	var popup_color: Color = attack_popup_color
	var popup_outline: Color = attack_popup_outline_color
	match popup_type:
		MeterPopupType.OFFSET_REWARD:
			popup_color = attack_popup_offset_color
			popup_outline = attack_popup_offset_outline_color
		MeterPopupType.KILL_REWARD:
			popup_color = attack_popup_kill_color
			popup_outline = attack_popup_kill_outline_color
	
	# 横向位置：先按随机方向意愿，再按实际文字宽度避让在场飘字（普通奖励 + 抵消奖励同时出现时不会压在一起）
	var half_w: float = _popup_text_width(text, font_size) * 0.5
	var desired_dir: float = tower_rng.randf_range(-1.0, 1.0) if tower_rng else 0.0
	var x_off: float = _resolve_popup_offset_x(desired_dir * attack_popup_spread, half_w)
	_register_popup_box(x_off, half_w)
	
	# 「往哪边偏 → 就往哪边飞、往哪边倾」：方向取最终落点的符号，幅度按 spread 归一（避让到很外侧时封顶）
	var fly_dir: float = clampf(x_off / maxf(attack_popup_spread, 1.0), -1.0, 1.0)
	var center: Vector2 = board_drawer.get_tower_meter_text_position()
	var popup_pos: Vector2 = Vector2(center.x + x_off, center.y)
	var drift: Vector2 = Vector2(fly_dir * attack_popup_drift_x, -attack_popup_rise_speed)
	var rotation_deg: float = fly_dir * attack_popup_rotate_deg  # 角度偏移量：±attack_popup_rotate_deg
	
	# persistent=false → 每次调用新增一条并各自淡出，连续消行时自然叠成一小簇
	# alignment=CENTER → position 即文本中心，旋转也绕该中心进行
	# 同一个 key 下每条各自持有颜色，所以红/绿可以混在一起同时飘
	text_printer.show_text(attack_popup_key, text, popup_pos,
		popup_color, popup_outline, font_size,
		false, 1.0, attack_popup_display_time, attack_popup_fade_time,
		drift, HORIZONTAL_ALIGNMENT_CENTER,
		attack_popup_drift_decay, rotation_deg)

## 飘字字号换算：随单次米数增幅变大而变大，但趋势逐渐变缓（对数），并受上限约束。
func _popup_font_scale(gain: float) -> float:
	var ref: float = maxf(attack_popup_grow_ref, 0.001)
	var t: float = log(1.0 + maxf(gain, 0.0) / ref)
	return clampf(1.0 + attack_popup_font_grow * t, 1.0, maxf(attack_popup_max_font_scale, 1.0))

## 量出飘字字符串的像素宽度（用实际绘制的那套字号取整规则，保证避让算得准）
func _popup_text_width(text: String, font_size: float) -> float:
	var font_size_int: int = maxi(1, roundi(font_size))
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int).x

## 记下一条飘字的横向占位，供后续飘字避让；到点自动过期（不再阻塞别人）
func _register_popup_box(x_off: float, half_w: float) -> void:
	_prune_popup_boxes()
	_popup_boxes.append({
		"x": x_off,
		"half_w": half_w,
		"until_msec": Time.get_ticks_msec() + int(maxf(attack_popup_anti_overlap_time, 0.0) * 1000.0),
	})

## 清掉已经淡出完毕的占位记录
func _prune_popup_boxes() -> void:
	if _popup_boxes.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var kept: Array = []
	for box: Dictionary in _popup_boxes:
		if int(box["until_msec"]) > now:
			kept.append(box)
	_popup_boxes = kept

## 返回与 (x_off, half_w) 重叠过多的第一条在场飘字；没有则返回空字典。
## 允许的重叠量 = attack_popup_max_overlap_ratio × 较窄那条字的宽度（所以允许部分重叠，只是不许完全叠住）
func _first_overlapping_box(x_off: float, half_w: float) -> Dictionary:
	for box: Dictionary in _popup_boxes:
		var other_half: float = float(box["half_w"])
		var overlap: float = (half_w + other_half) - absf(x_off - float(box["x"]))
		if overlap > _popup_allowed_overlap(half_w, other_half):
			return box
	return {}

## 两条飘字之间允许的横向重叠量（像素）
func _popup_allowed_overlap(half_a: float, half_b: float) -> float:
	return attack_popup_max_overlap_ratio * 2.0 * minf(half_a, half_b)

## 给新飘字选横向偏移（相对米数文字中心，像素）：
## 先用随机意愿位置；若与在场飘字重叠过多，就贴着那条往旁边让，优先选「不超额重叠且离中心最近」的位置。
## 不设偏移上限：宁可让远一点，也不让两条字完全叠在一起（允许部分重叠）。
func _resolve_popup_offset_x(desired_x: float, half_w: float) -> float:
	_prune_popup_boxes()
	var x_off: float = desired_x
	for _i in range(8):
		var hit: Dictionary = _first_overlapping_box(x_off, half_w)
		if hit.is_empty():
			return x_off
		var other_half: float = float(hit["half_w"])
		var push: float = half_w + other_half - _popup_allowed_overlap(half_w, other_half)
		var left_x: float = float(hit["x"]) - push
		var right_x: float = float(hit["x"]) + push
		# 左右两个候选里，挑真正不超额重叠的那个（离中心更近者优先）；都还压着就挑离中心近的继续让
		var best_dist: float = INF
		var best_x: float = INF
		for cand: float in [left_x, right_x]:
			if _first_overlapping_box(cand, half_w).is_empty() and absf(cand) < best_dist:
				best_dist = absf(cand)
				best_x = cand
		if best_x < INF:
			x_off = best_x
		else:
			x_off = left_x if absf(left_x) <= absf(right_x) else right_x
	return x_off

##尝试给予击杀奖励，通过输入攻击后进行随机击杀计算
##每次击杀命中都会在米数位置弹出金色 "+X.XXm"，数值为这一次实际加到的米数
##（= kill_reward[0] 减去随米数增长的随机衰减，再 snapped 到 0.1，不是 kill_reward[0] 原值）
func try_give_kill_reward(attack:int):
	# TODO::使击杀奖励跟随高度进行适当的变化和击杀变难
	var killer_spike : int = base_killer_spike + round(tower_meter / 2000.0)
	var kill_possible_percent : float = base_kill_possible_percent - tower_meter / 1000.0 / 100.0
	
	var try_times : int = floor(1.0 * attack / killer_spike)
	var last_attack : int = attack - try_times * killer_spike
	if try_times > 0:
		for i in range(0,try_times):
			extra_percent_apm += 0.03
			if tower_rng.randf() <= kill_possible_percent:
				_give_kill_reward_meter()
	if tower_rng.randf() <= kill_possible_percent * last_attack / killer_spike / 5:
		_give_kill_reward_meter(false)

## 结算一次击杀命中：加米数与速度、计数 +1，并弹出金色飘字。
## grant_apm_bonus=true 时额外给 APM 成长（满 killer_spike 的整数次命中给，余数命中原实现不给）。
## 注意：飘字用的是「本次实际加到的米数」（随机衰减 + snapped 之后的值），
## 与上面的随机数调用顺序保持一致（先米数、后速度），以免影响 TOWER_CLIMB 随机流的复现。
func _give_kill_reward_meter(grant_apm_bonus: bool = true):
	var meter_gain: float = snapped(kill_reward[0] - tower_rng.randf_range(0,min(tower_meter / 500.0,8)),0.1)
	tower_meter += meter_gain
	tower_speed_meter += snapped(kill_reward[1] - tower_rng.randf_range(0,min(tower_speed_meter / 10.0,8)),0.1)
	kill_count += 1
	if grant_apm_bonus:
		extra_percent_apm += 0.1
	_popup_meter_gain(meter_gain, MeterPopupType.KILL_REWARD)
