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

var publish_time_array : Array = [0,10,20,30,40,50]#[0,60*7,60*8,60*9,60*10,60*11]
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

	# bot 评估权重（可由 buff 界面调整，经 bridge 的 S 命令下发到 ColdClear）。
	# 原则：bridge 导出权重为主，仅当 buff 显式传参对应键时才覆盖 bridge。
	# 这里把显式传参的键记入 clear_line_controller.bot_weight_override_keys，
	# get_damage_tables 只返回这些键，bridge 才会覆盖默认权重。
	clear_line_controller.bot_weight_override_keys = {}
	var bot_key_to_var := {
		"bot_eval_mult": "eval_mult",
		"bot_attack_efficiency_weight": "attack_efficiency_weight",
		"bot_b2b_clear": "b2b_clear",
		"bot_height": "height",
		"bot_clear4": "clear4",
		"bot_clear1": "clear1",
		"bot_clear2": "clear2",
		"bot_clear3": "clear3",
		"bot_tspin1": "tspin1",
		"bot_tspin2": "tspin2",
		"bot_tspin3": "tspin3",
		"bot_mini_tspin1": "mini_tspin1",
		"bot_mini_tspin2": "mini_tspin2",
		"bot_allspin1": "allspin1",
		"bot_allspin2": "allspin2",
		"bot_allspin3": "allspin3",
		"bot_allspin3plus": "allspin3plus",
		"bot_perfect_clear": "perfect_clear",
		"bot_combo_garbage": "combo_garbage",
		"bot_wasted_t": "wasted_t",
		"bot_move_time": "move_time",
		"bot_allspin_repeat_penalty": "allspin_repeat_penalty",
	}
	for extra_key in bot_key_to_var:
		if extra_data_dict.has(extra_key):
			var weight_key: String = bot_key_to_var[extra_key]
			clear_line_controller.set("bot_" + weight_key, int(extra_data_dict[extra_key]))
			clear_line_controller.bot_weight_override_keys[weight_key] = true

	# bot 并行搜索线程数（buff 可调，0 = 由 bridge 自动决定）
	if extra_data_dict.has("bot_threads"):
		clear_line_controller.bot_threads = int(extra_data_dict["bot_threads"])

	# Talentless（无才能）：为true时跳过整个Spin判定
	if extra_data_dict.has("NoSpin"):
		if clear_line_controller:
			clear_line_controller.no_spin = bool(extra_data_dict["NoSpin"])
	
	# NoHold模式：关闭Hold显示并禁用Hold输入（JSON中键名为"NoHold"）
	if extra_data_dict.has("NoHold") or extra_data_dict.has("no_hold"):
		var no_hold_value: bool = extra_data_dict.get("NoHold", extra_data_dict.get("no_hold", false))
		if tetris_controller:
			tetris_controller.no_hold = no_hold_value
		if board_drawer:
			board_drawer.no_hold = no_hold_value
	
	if extra_data_dict.has("BotMode"):
		tetris_controller.bot_mode = true

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
	tetris_controller.gravity_drop_time = default_get_oneD_array_things(current_stage,gravity_drop_time_array)
	tetris_controller.lock_delay = default_get_oneD_array_things(current_stage,lock_delay_array)

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
