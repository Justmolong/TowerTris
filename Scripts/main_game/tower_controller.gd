extends Node2D
class_name TowerController

static var ATTACK_DATA_PATH : String = "user://Savedatas/attack_setting.json"
static var FLOOR_HIGHER : Array = [0,50,150,300,450,650,850,1100,1350,1650,2550,3000,3500,4500,5500,6500,8000,9500,11000]

@export var tetris_controller: TetrisController
@export var garbage_line_controller: TetrisGarbageLineController
@export var board_drawer: TetrisBoardDrawer
@export var clear_line_controller: TetrisClearLine

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

var stage_garbage_time : Array = [10,8,7,7,6,6,5,5,4,3,2,2,2,1,1,1,0.5]
var stage_garbage_divide : Array = []
var garbage_collect_percent : float = 0.1
var garbage_collect_percent_array: Array = [0.4,0.3,0.2,0.1,0.1,0.2,0.2,0.3,0.3,0.2]
var garbage_sent_time : float = 0
var garbage_divide_percent : float = 0
var garbage_divide_percent_array: Array = [0.8,0.6,0.4,0.2,0.2,0.1,0.1,0,0.1,0.2,0.3]
var garbage_hole_change_percent_array: Array = [0.1,0.1,0.1,0.2,0.4,0.5,0.6,0.7,0.8,0.9]
var collected_count : int = 0
var collected_garbage : Array = []
var pressure_mult_array: Array = [1,1,1,1,1,1,1,1,1,1,1.25,1.5,2,2.5,3,4,5,6,7]
var pressure_mult : float = 1.0
var send_mult_attack: float = 1.0

var gravity_drop_time_array: Array = [5]
var lock_delay_array: Array = [1]

var tower_meter: float = 0.0            
var tower_speed_meter: float = 0.0      
var tower_lowest_speed: float = 0.1
var tower_dropped_speed: float = 0.01
var tower_dropped_mult: Array = [0.8,0.9,1,1,1,1.1,1.2,1.3,1.4,1.5,1.7,1.9,2]
var tower_current_dropped_mult: float = 1.0
var attack_to_meter_mult: float = 0.2
var attack_to_speed_mult: float = 0.1

var warning_count : int = 4
var segment_line : int = 4
var big_attack_enter_array : Array = []
var big_attack_delay : float = 4.0

var kill_count: int = 0
var killer_spike: int = 10
var kill_possible_percent: float = 0.15
var kill_reward: Array = [10,4]

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
		clear_line_controller.spin0_btb_enabled = extra_data_dict["spin0_btb_enabled"]
	
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

	# Talentless（无才能）：NoSpin 为 int（0=正常Spin判定；1=所有Spin降级为MiniSpin；2=不判定Spin）
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
		garbage_sent_timer.wait_time = garbage_sent_time + tower_rng.randf_range(-garbage_sent_time/2.0,garbage_sent_time/2.0)
		garbage_sent_timer.start()
	
	_tower_climb(delta)


func total_get_data():
	self_game_time = tetris_controller.game_time
	
	garbage_sent_time = default_get_oneD_array_things(current_stage,stage_garbage_time)
	tower_current_dropped_mult = default_get_oneD_array_things(current_stage,tower_dropped_mult)
	pressure_mult = default_get_oneD_array_things(current_stage,pressure_mult_array)
	var max_percent = default_get_oneD_array_things(current_stage,stage_percent_apm) + extra_percent_apm
	if max_percent > 1:
		max_percent = 1
	current_apm = total_apm * pressure_mult * max_percent
	garbage_collect_percent = default_get_oneD_array_things(current_stage,garbage_collect_percent_array)
	garbage_divide_percent = default_get_oneD_array_things(current_stage,garbage_divide_percent_array)
	garbage_line_controller.garbage_messy = default_get_oneD_array_things(current_stage,garbage_hole_change_percent_array)
	# 重力/锁延：走 TetrisController 的 setter，除字段外还要同步对应计时器的 wait_time
	# （只改字段的话，关卡/Buff 设置的重力与锁延不会真正生效）
	tetris_controller.set_gravity_drop_time(default_get_oneD_array_things(current_stage,gravity_drop_time_array))
	tetris_controller.set_lock_delay(default_get_oneD_array_things(current_stage,lock_delay_array))

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

func _tower_climb(delta: float):
	if tower_speed_meter < tower_lowest_speed:
		tower_speed_meter = tower_lowest_speed
	elif tower_speed_meter > tower_lowest_speed:
		var x = tower_speed_meter
		tower_speed_meter -= ((x*log(x) + x)/120.0) * delta * tower_current_dropped_mult
	else:
		pass
	
	tower_meter += tower_speed_meter * delta

##塔的模拟伤害攻击
func _try_sent_garbage():
	var decided_attack : int = ceil(current_apm/60*garbage_sent_time)
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
	for i in attack:
		garbage_line_controller.add_attack(ceil(i * send_mult_attack * publish_mult_attack))

##快速重新分割攻击储存列表并形成!!!!攻击
func _quick_big_attack_clear(segment: int):
	var total_attack: int = 0
	for i in big_attack_enter_array:
		total_attack += i
	big_attack_enter_array.clear()
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

func attack_increase_tower(attack:float, is_defence:bool = false):
	if is_defence:
		pass
	tower_meter += attack * attack_to_meter_mult
	tower_speed_meter += attack * attack_to_speed_mult

##尝试给予击杀奖励，通过输入攻击后进行随机击杀计算
func try_give_kill_reward(attack:int):
	var try_times : int = floor(1.0 * attack / killer_spike)
	var last_attack : int = attack - try_times * killer_spike
	if try_times > 0:
		for i in range(0,try_times):
			extra_percent_apm += 0.03
			if tower_rng.randf() <= kill_possible_percent:
				tower_meter += kill_reward[0]
				tower_speed_meter += kill_reward[1]
				kill_count += 1
				extra_percent_apm += 0.1
	if tower_rng.randf() <= kill_possible_percent * last_attack / killer_spike / 5:
		tower_meter += kill_reward[0]
		tower_speed_meter += kill_reward[1]
		kill_count += 1
