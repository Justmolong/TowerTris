extends Node
class_name ReplayRecord

## 回放录制器
## 使用游戏经过时间（秒）记录输入事件，确保帧率无关的精确回放

# ========== 节点引用 ==========
@export var tetris_controller: TetrisController
@export var clear_line_controller: TetrisClearLine
@export var bag_controller: TetrisBagController

# ========== 配置 ==========
@export var player_name: String = "Player"
@export var auto_save: bool = true
@export var save_directory: String = "user://Replays/"
@export var auto_record: bool = true

# ========== 状态变量 ==========
var replay_data: ReplayData = null
var is_recording: bool = false
var _elapsed_time: float = 0.0      # 游戏内经过秒数

# 输入事件队列
var _input_event_queue: Array = []

# 录制状态
var is_game_active: bool = false
var has_recorded_this_game: bool = false

# ========== 信号 ==========
signal recording_started()
signal recording_stopped(replay_data: ReplayData)
signal event_recorded(time: float, action: String, pressed: bool)

func _ready():
	_auto_find_references()
	set_process_input(true)
	set_process(true)

func _auto_find_references():
	if not tetris_controller:
		tetris_controller = get_node_or_null("../../MainBoard/TetrisController")
	if not clear_line_controller:
		clear_line_controller = get_node_or_null("../../MainBoard/TetrisClearLine")
	if not bag_controller:
		bag_controller = get_node_or_null("../../MainBoard/TetrisBagController")
	
	if not tetris_controller:
		tetris_controller = _find_controller(get_tree().root)
	
	# 连接Bag控制器的方块生成信号以记录方块序列
	if bag_controller and not bag_controller.piece_spawned.is_connected(_on_piece_spawned):
		bag_controller.piece_spawned.connect(_on_piece_spawned)

func _find_controller(node: Node) -> TetrisController:
	if node is TetrisController:
		return node
	for child in node.get_children():
		var found = _find_controller(child)
		if found:
			return found
	return null

# ========== 输入事件捕获 ==========

func _input(event: InputEvent):
	if not is_recording:
		return
	
	if event is InputEventKey and not event.echo:
		var action = _get_action_from_keycode(event.keycode)
		if action != "":
			var pressed = event.pressed
			
			_input_event_queue.append({
				"time": _elapsed_time,
				"action": action,
				"pressed": pressed
			})
			
			if _input_event_queue.size() >= 10:
				_flush_input_events()

func _get_action_from_keycode(keycode: int) -> String:
	var actions = ["LeftMove", "RightMove", "SoftDrop", "HardDrop", "LeftSpin", "RightSpin", "SwapSpin", "HoldBlock"]
	
	for action in actions:
		var events = InputMap.action_get_events(action)
		for ev in events:
			if ev is InputEventKey and ev.keycode == keycode:
				return action
	return ""

# ========== 事件刷新 ==========

func _flush_input_events():
	if _input_event_queue.is_empty():
		return
	
	for entry in _input_event_queue:
		replay_data.add_input_event(entry["time"], entry["action"], entry["pressed"])
		event_recorded.emit(entry["time"], entry["action"], entry["pressed"])
	
	_input_event_queue.clear()

# ========== 主循环（累计游戏时间） ==========

func _process(delta: float):
	if not is_recording:
		return
	
	_elapsed_time += delta
	_flush_input_events()

# ========== 录制控制 ==========

func _on_piece_spawned(piece_type: String, _shape: Array, _color: Color):
	if not is_recording or not replay_data:
		return
	# 记录生成的每个方块类型（用于回放时重建准确的方块序列）
	replay_data.bag_sequence.append(piece_type)

func _on_game_started():
	if auto_record and not has_recorded_this_game:
		start_recording(player_name)
		is_game_active = true

func _on_game_ended():
	if is_recording:
		stop_and_save_recording()
	is_game_active = false

func start_recording(record_name: String = ""):
	if is_recording:
		stop_recording()
	
	replay_data = ReplayData.create_default()
	replay_data.player_name = player_name if not player_name.is_empty() else record_name
	replay_data.random_seed = RandomManager.get_current_seed()
	
	if tetris_controller:
		replay_data.move_das = tetris_controller.move_das
		replay_data.move_arr = tetris_controller.move_arr
		replay_data.softdrop_delay = tetris_controller.softdrop_delay
		
		# 记录游戏开始时第一个在场景中的方块（piece_spawned信号时机早于录制）
		if not replay_data.bag_sequence.is_empty():
			replay_data.bag_sequence.clear()
		replay_data.bag_sequence.append(tetris_controller.current_piece_type)
	
	# 连接Bag控制器的方块生成信号以记录方块序列
	if bag_controller and not bag_controller.piece_spawned.is_connected(_on_piece_spawned):
		bag_controller.piece_spawned.connect(_on_piece_spawned)
	
	_elapsed_time = 0.0
	_input_event_queue.clear()
	
	is_recording = true
	has_recorded_this_game = true
	recording_started.emit()
	
	print("回放录制已开始，种子: ", replay_data.random_seed)
	print("首个方块: ", tetris_controller.current_piece_type if tetris_controller else "unknown")

func stop_recording() -> ReplayData:
	if not is_recording:
		return null
	
	replay_data.total_time = _elapsed_time
	replay_data.total_frames = int(_elapsed_time * 60.0)
	_flush_input_events()
	_collect_final_stats()
	
	is_recording = false
	recording_stopped.emit(replay_data)
	
	print("回放录制已停止，总时间: ", _elapsed_time, " 秒")
	print("输入事件数: ", replay_data.input_events.size())
	
	return replay_data

func stop_and_save_recording() -> String:
	if not is_recording:
		return ""
	
	stop_recording()
	
	if auto_save and replay_data:
		return save_replay()
	
	return ""

func save_replay() -> String:
	if not replay_data:
		return ""
	
	var dir = DirAccess.open(save_directory)
	if not dir:
		DirAccess.make_dir_recursive_absolute(save_directory)
	
	var timestamp_str = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()), true)
	timestamp_str = timestamp_str.replace(":", "").replace("-", "")
	var file_name = "replay_%s_%s.json" % [replay_data.player_name, timestamp_str]
	var file_path = save_directory + file_name
	
	if replay_data.save_to_file(file_path):
		print("回放已保存: ", file_path)
		return file_path
	else:
		print("回放保存失败")
		return ""

func _collect_final_stats():
	if not replay_data:
		return
	
	if tetris_controller:
		var stats = tetris_controller.get_stats()
		replay_data.final_stats["pps"] = stats.get("pps", 0.0)
		replay_data.final_stats["apm"] = stats.get("apm", 0.0)
		replay_data.final_stats["rpm"] = stats.get("rpm", 0.0)
		replay_data.final_stats["total_pieces"] = stats.get("total_pieces", 0)
		replay_data.final_stats["total_attacks"] = stats.get("total_attacks", 0)
	
	if clear_line_controller:
		replay_data.final_stats["max_combo"] = clear_line_controller.get_combo_count()
		replay_data.final_stats["max_btb"] = clear_line_controller.get_btb_count()

# ========== 公共方法 ==========

func record_event(_event_type: String, _event_data: Dictionary = {}):
	if not is_recording or not replay_data:
		return
	# 此方法后续可扩展为记录非输入类事件，暂保留框架
	pass

func is_recording_active() -> bool:
	return is_recording

func get_current_time() -> float:
	return _elapsed_time

func get_current_time_string() -> String:
	return "%.2fs" % _elapsed_time

func get_replay_data() -> ReplayData:
	return replay_data

func get_recorded_event_count() -> int:
	if not replay_data:
		return 0
	return replay_data.input_events.size()

func set_player_name(record_name: String):
	player_name = record_name
	if replay_data and is_recording:
		replay_data.player_name = player_name

func reset():
	if is_recording:
		stop_recording()
	
	replay_data = null
	_elapsed_time = 0.0
	_input_event_queue.clear()
	is_recording = false
	has_recorded_this_game = false
	is_game_active = false

func trigger_game_start():
	_on_game_started()

func trigger_game_end():
	_on_game_ended()

func _exit_tree():
	if is_recording:
		stop_and_save_recording()
