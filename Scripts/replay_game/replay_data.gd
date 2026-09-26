extends Resource
class_name ReplayData

## 回放数据类
## 存储游戏回放所需的所有数据

# ========== 元数据 ==========
@export var version: String = "1.0"
@export var timestamp: int = 0
@export var player_name: String = "Player"
@export var game_duration: float = 0.0
@export var random_seed: int = 0
@export var total_frames: int = 0
@export var total_time: float = 0.0

# ========== 设置数据 ==========
@export var move_das: float = 0.1
@export var move_arr: float = 0.0
@export var softdrop_delay: float = 0.1

# ========== 游戏数据 ==========
@export var bag_sequence: Array = []
@export var input_events: Array = []
@export var game_start_time: float = 0.0

# ========== 统计数据 ==========
@export var final_stats: Dictionary = {
	"pps": 0.0,
	"apm": 0.0,
	"rpm": 0.0,
	"max_combo": 0,
	"max_btb": 0,
	"total_lines": 0,
	"total_pieces": 0,
	"total_attacks": 0,
	"total_spins": 0
}

## 创建默认回放数据
static func create_default() -> ReplayData:
	var data = ReplayData.new()
	data.version = "1.0"
	data.timestamp = int(Time.get_unix_time_from_system())
	data.player_name = "Player"
	data.game_duration = 0.0
	data.random_seed = 0
	data.total_time = 0.0
	data.move_das = 0.1
	data.move_arr = 0.0
	data.softdrop_delay = 0.1
	data.bag_sequence = []
	data.input_events = []
	data.game_start_time = 0.0
	data.final_stats = {
		"pps": 0.0,
		"apm": 0.0,
		"rpm": 0.0,
		"max_combo": 0,
		"max_btb": 0,
		"total_lines": 0,
		"total_pieces": 0,
		"total_attacks": 0,
		"total_spins": 0
	}
	return data

## 添加输入事件
func add_input_event(time: float, action: String, pressed: bool):
	input_events.append({
		"time": time,
		"action": action,
		"pressed": pressed
	})

## 设置完整的Bag序列
func set_bag_sequence(sequence: Array):
	bag_sequence = sequence.duplicate()

## 获取当前Bag序列的副本
func get_bag_sequence_copy() -> Array:
	return bag_sequence.duplicate()

## 保存到JSON文件
func save_to_file(file_path: String) -> bool:
	var data_dict = _to_dict()
	var json_string = JSON.stringify(data_dict, "\t")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("回放数据已保存: ", file_path)
		return true
	else:
		push_error("保存回放数据失败: ", file_path)
		return false

## 从JSON文件加载
static func load_from_file(file_path: String) -> ReplayData:
	if not FileAccess.file_exists(file_path):
		push_error("回放文件不存在: ", file_path)
		return null
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("无法打开回放文件: ", file_path)
		return null
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("解析回放文件失败: ", json.get_error_message())
		return null
	
	var data_dict = json.data
	if typeof(data_dict) != TYPE_DICTIONARY:
		push_error("回放文件格式错误")
		return null
	
	return _from_dict(data_dict)

## 转换为字典
func _to_dict() -> Dictionary:
	return {
		"version": version,
		"timestamp": timestamp,
		"player_name": player_name,
		"game_duration": game_duration,
		"random_seed": random_seed,
		"total_frames": total_frames,
		"total_time": total_time,
		"move_das": move_das,
		"move_arr": move_arr,
		"softdrop_delay": softdrop_delay,
		"bag_sequence": bag_sequence.duplicate(),
		"input_events": input_events.duplicate(),
		"game_start_time": game_start_time,
		"final_stats": final_stats.duplicate()
	}

## 从字典创建
static func _from_dict(data: Dictionary) -> ReplayData:
	var replay = ReplayData.new()
	replay.version = data.get("version", "1.0")
	replay.timestamp = data.get("timestamp", 0)
	replay.player_name = data.get("player_name", "Player")
	replay.game_duration = data.get("game_duration", 0.0)
	replay.random_seed = data.get("random_seed", 0)
	replay.total_frames = data.get("total_frames", 0)
	
	# 检测是否为旧格式（只有 total_frames，没有 total_time）
	var is_old_format: bool = not data.has("total_time")
	var fallback_duration = data.get("game_duration", 0.0)
	if fallback_duration <= 0.0 and replay.total_frames > 0:
		fallback_duration = float(replay.total_frames) / 60.0
	replay.total_time = data.get("total_time", fallback_duration)
	
	replay.move_das = data.get("move_das", 0.1)
	replay.move_arr = data.get("move_arr", 0.0)
	replay.softdrop_delay = data.get("softdrop_delay", 0.1)
	replay.bag_sequence = data.get("bag_sequence", []).duplicate()
	replay.game_start_time = data.get("game_start_time", 0.0)
	
	# 兼容旧格式：input_frames → input_events
	if data.has("input_frames") and data["input_frames"].size() > 0 and not data.has("input_events"):
		replay.input_events = _convert_frames_to_events(data["input_frames"])
	else:
		var raw_events = data.get("input_events", []).duplicate()
		# 旧格式 time 存的是帧编号（非秒数），需要转换为秒
		if is_old_format and raw_events.size() > 0:
			var first_time = raw_events[0].get("time", 0.0)
			# 如果时间值较大（>60），说明是用帧编号存储的旧格式
			if first_time > 10.0 or replay.total_frames > 100:
				for event in raw_events:
					if event.has("time"):
						event["time"] = event["time"] / 60.0
		replay.input_events = raw_events
	
	replay.final_stats = data.get("final_stats", {}).duplicate()
	
	# 确保事件按时间排序
	replay.input_events.sort_custom(func(a, b):
		return a.get("time", 0.0) < b.get("time", 0.0)
	)
	
	return replay

## 兼容旧格式：将 input_frames 转换为 input_events
static func _convert_frames_to_events(frames: Array) -> Array:
	var events = []
	for frame in frames:
		var frame_time = float(frame.get("time", 0.0))
		# 旧格式的 time 可能是帧编号或秒数，保守以 60fps 转换
		if frame_time > 0 and frame_time < 10000:
			frame_time = frame_time / 60.0
		for action in frame.get("actions", []):
			events.append({"time": frame_time, "action": action, "pressed": true})
		for action in frame.get("released", []):
			events.append({"time": frame_time, "action": action, "pressed": false})
	
	events.sort_custom(func(a, b):
		return a["time"] < b["time"]
	)
	
	return events

## 获取总事件数
func get_total_events() -> int:
	return input_events.size()

## 验证数据完整性
func validate() -> bool:
	if version.is_empty():
		return false
	if player_name.is_empty():
		return false
	return true

## 获取统计摘要
func get_stats_summary() -> String:
	return "PPS: %.2f | APM: %.2f | RPM: %.2f | 最大连击: %d | 消行: %d" % [
		final_stats.get("pps", 0.0),
		final_stats.get("apm", 0.0),
		final_stats.get("rpm", 0.0),
		final_stats.get("max_combo", 0),
		final_stats.get("total_lines", 0)
	]

## 清空所有数据
func clear():
	input_events.clear()
	bag_sequence.clear()
	game_duration = 0.0
	game_start_time = 0.0
