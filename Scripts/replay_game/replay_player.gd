extends Node
class_name ReplayPlayer

## 回放播放器
## 基于游戏经过时间驱动的回放播放器。
## 录制器以游戏经过秒数记录输入事件时间，
## 播放器按真实时间推进并匹配事件。

@export var replay_file_path: String = ""
@export var tetris_controller: TetrisController
@export var garbage_line_controller: TetrisGarbageLineController
@export var bag_controller: TetrisBagController
@export var replay_record: ReplayRecord

# 回放数据
var replay_data: ReplayData = null

# 播放状态
var is_playing: bool = false
var is_prepared: bool = false
var is_loaded: bool = false
var is_paused: bool = false
var is_finished: bool = false

# 游戏经过时间跟踪
var _elapsed_time: float = 0.0
var _next_event_index: int = 0
var _event_counter: int = 0

# 活跃按键状态（用于停止时释放）
var _active_actions: Dictionary = {}

# 播放速度倍率
var play_speed: float = 1.0

# 信号
signal replay_started()
signal replay_paused()
signal replay_resumed()
signal replay_finished()
signal replay_progress_changed(progress: float, elapsed: float, total_time: float)
signal replay_event_applied(elapsed: float, action: String, pressed: bool)

func _ready():
	_auto_find_references()
	set_process(true)

	if replay_file_path != "":
		call_deferred("_delayed_load")

func _delayed_load():
	if not is_loaded and replay_file_path != "":
		load_and_prepare(replay_file_path)

func _auto_find_references():
	if not replay_record:
		replay_record = get_node_or_null("../../ReplayRecord")
	if not tetris_controller:
		tetris_controller = get_node_or_null("../../MainBoard/TetrisController")
	if not garbage_line_controller:
		garbage_line_controller = get_node_or_null("../../MainBoard/GarbageLineController")
	if not bag_controller:
		bag_controller = get_node_or_null("../../MainBoard/TetrisBagController")

	if not tetris_controller:
		tetris_controller = _find_controller(get_tree().root)
	if not garbage_line_controller:
		garbage_line_controller = _find_garbage_controller(get_tree().root)

func _find_controller(node: Node) -> TetrisController:
	if node is TetrisController:
		return node
	for child in node.get_children():
		var found = _find_controller(child)
		if found:
			return found
	return null

func _find_garbage_controller(node: Node) -> TetrisGarbageLineController:
	if node is TetrisGarbageLineController:
		return node
	for child in node.get_children():
		var found = _find_garbage_controller(child)
		if found:
			return found
	return null

# ========== 加载与准备 ==========

## 加载回放文件并准备播放环境
func load_and_prepare(path: String) -> bool:
	if is_loaded:
		return true

	print("加载回放文件: ", path)
	var data = ReplayData.load_from_file(path)
	if not data:
		push_error("无法加载回放文件: " + path)
		return false

	replay_data = data
	is_prepared = true
	is_loaded = true

	# 初始化随机数管理器（确保与录制时一致的方块序列）
	RandomManager.initialize(replay_data.random_seed)

	# 设置 Bag 回放模式——使用录制时生成的方块序列
	if bag_controller and replay_data.bag_sequence.size() > 0:
		bag_controller.enable_replay_mode(replay_data.bag_sequence)
		print("Bag序列已加载，长度: ", replay_data.bag_sequence.size())

	# 应用录制时的设置
	if tetris_controller:
		tetris_controller.move_das = replay_data.move_das
		tetris_controller.move_arr = replay_data.move_arr
		tetris_controller.softdrop_delay = replay_data.softdrop_delay

	# 重置播放状态
	_elapsed_time = 0.0
	_next_event_index = 0
	_active_actions.clear()
	_event_counter = 0
	is_finished = false
	is_paused = false

	print("回放加载成功，种子: ", replay_data.random_seed)
	print("输入事件数: ", replay_data.input_events.size())
	print("总时间: ", replay_data.total_time, " 秒")

	return true

## 开始播放
func play():
	if not is_prepared or not replay_data:
		push_error("无可播放的回放数据")
		return

	if is_playing:
		print("回放已在播放中")
		return

	print("开始回放播放")

	# 重置
	_elapsed_time = 0.0
	_next_event_index = 0
	_active_actions.clear()
	_event_counter = 0
	is_finished = false
	is_paused = false

	# 开启回放输入覆盖模式
	if tetris_controller:
		tetris_controller.set_replay_input_override(true)
		print("已开启回放输入覆盖模式")

	# 禁止录制器在回放时录制
	if replay_record:
		replay_record.auto_record = false
		if replay_record.is_recording_active():
			replay_record.stop_recording()
		replay_record.has_recorded_this_game = true

	is_playing = true
	replay_started.emit()
	print("回放播放已启动，将处理 ", replay_data.input_events.size(), " 个输入事件，总时长 ", replay_data.total_time, " 秒")

## 停止播放
func stop():
	if not is_playing and not is_paused:
		return

	is_playing = false
	is_paused = false

	# 释放所有活跃按键
	for action in _active_actions:
		if tetris_controller:
			tetris_controller.set_replay_input(action, false)
	_active_actions.clear()

	# 关闭回放输入覆盖
	if tetris_controller:
		tetris_controller.set_replay_input_override(false)

	is_finished = true
	replay_finished.emit()
	print("回放播放已停止，共处理 ", _event_counter, " 个事件")

## 暂停播放
func pause():
	if not is_playing:
		return
	is_paused = true
	replay_paused.emit()
	print("回放已暂停")

## 恢复播放
func resume():
	if not is_paused:
		return
	is_paused = false
	replay_resumed.emit()
	print("回放已恢复")

## 切换暂停状态
func toggle_pause():
	if is_paused:
		resume()
	else:
		pause()

# ========== 主循环 ==========

func _process(delta: float) -> void:
	if not is_playing or is_paused or is_finished or not replay_data:
		return

	var total = replay_data.total_time
	if total <= 0.0:
		total = float(replay_data.total_frames) / 60.0
	if total <= 0.0:
		_handle_replay_end()
		return

	# 累加游戏时间
	var step = delta * play_speed
	_elapsed_time += step

	# 处理当前时间点的输入事件
	_process_events_for_time(_elapsed_time)

	# 发射进度信号
	var progress = clamp(_elapsed_time / total, 0.0, 1.0)
	replay_progress_changed.emit(progress, _elapsed_time, total)

	# 检查回放是否结束
	if _elapsed_time >= total and _next_event_index >= replay_data.input_events.size():
		_handle_replay_end()
		return

## 处理指定时间点的所有输入事件
func _process_events_for_time(elapsed: float):
	while _next_event_index < replay_data.input_events.size():
		var event = replay_data.input_events[_next_event_index]
		var event_time = event.get("time", 0.0)

		if event_time <= elapsed:
			_apply_input_event(event, event_time)
			_next_event_index += 1
			_event_counter += 1
		else:
			break

## 应用输入事件到游戏控制器
func _apply_input_event(event: Dictionary, event_time: float) -> void:
	var action = event.get("action", "")
	var pressed = event.get("pressed", false)

	if action.is_empty():
		return

	if tetris_controller:
		tetris_controller.set_replay_input(action, pressed)
		if pressed:
			_active_actions[action] = true
		else:
			if _active_actions.has(action):
				_active_actions.erase(action)

		replay_event_applied.emit(event_time, action, pressed)

## 处理回放结束
func _handle_replay_end():
	# 释放所有按键
	for action in _active_actions:
		if tetris_controller:
			tetris_controller.set_replay_input(action, false)
	_active_actions.clear()

	# 关闭回放覆盖模式
	if tetris_controller:
		tetris_controller.set_replay_input_override(false)

	is_playing = false
	is_finished = true
	is_paused = false

	replay_finished.emit()

	print("回放播放完成，共处理 ", _event_counter, " 个事件，播放 ", _elapsed_time, " 秒")

	# 回放结束后触发游戏结束，跳转到结算界面
	# 仅在游戏尚未自然结束时（game_timer还在跑）才触发
	if tetris_controller and tetris_controller.is_inside_tree():
		await get_tree().create_timer(0.3).timeout
		if tetris_controller.is_inside_tree():
			# 检查游戏是否已经自然结束（game_timer被_game_over停止了）
			var game_timer = tetris_controller.get_node_or_null("game_timer")
			if not game_timer or not game_timer.is_stopped():
				tetris_controller.game_ended.emit()
			else:
				print("回放结束但游戏已自然结束，跳过重复触发")

# ========== 跳转控制 ==========

## 跳转到指定进度 (0.0 ~ 1.0)
func seek(progress: float):
	if not replay_data:
		return

	var total = replay_data.total_time
	if total <= 0.0:
		total = float(replay_data.total_frames) / 60.0
	if total <= 0.0:
		return

	var target_time = progress * total
	seek_to_time(target_time)

## 跳转到指定时间
func seek_to_time(target_time: float):
	if not replay_data:
		return

	var total = replay_data.total_time
	if total <= 0.0:
		total = float(replay_data.total_frames) / 60.0

	target_time = clamp(target_time, 0.0, max(total - 0.001, 0.0))

	# 先释放所有当前按键
	for action in _active_actions:
		if tetris_controller:
			tetris_controller.set_replay_input(action, false)
	_active_actions.clear()

	# 重置并重放到目标时间
	_elapsed_time = 0.0
	_next_event_index = 0
	_event_counter = 0

	# 快速重放之前的事件（只恢复按键状态，不发送给控制器）
	var last_press_state: Dictionary = {}
	while _next_event_index < replay_data.input_events.size():
		var event = replay_data.input_events[_next_event_index]
		var event_time = event.get("time", 0.0)
		if event_time <= target_time:
			last_press_state[event["action"]] = event.get("pressed", false)
			_next_event_index += 1
			_event_counter += 1
		else:
			break

	# 应用最终的按键状态
	for action in last_press_state:
		if last_press_state[action] and tetris_controller:
			tetris_controller.set_replay_input(action, true)
			_active_actions[action] = true

	_elapsed_time = target_time

	var new_progress = _elapsed_time / total if total > 0 else 0.0
	replay_progress_changed.emit(new_progress, _elapsed_time, total)

# ========== 查询方法 ==========

func is_playing_active() -> bool:
	return is_playing

func is_paused_active() -> bool:
	return is_paused

func is_finished_active() -> bool:
	return is_finished

func get_current_time() -> float:
	return _elapsed_time

func get_total_time() -> float:
	if replay_data:
		if replay_data.total_time > 0:
			return replay_data.total_time
		return float(replay_data.total_frames) / 60.0
	return 0.0

func get_play_progress() -> float:
	var total = get_total_time()
	if total <= 0:
		return 0.0
	return clamp(_elapsed_time / total, 0.0, 1.0)

func get_replay_data() -> ReplayData:
	return replay_data

func reset_loaded_state():
	is_loaded = false
	is_prepared = false
	is_playing = false
	is_paused = false
	is_finished = false
	replay_data = null
	_elapsed_time = 0.0
	_next_event_index = 0
	_event_counter = 0
	_active_actions.clear()
