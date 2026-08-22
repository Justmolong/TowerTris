extends Node

## 全局数据管理器
## 用于在场景之间传递游戏数据

var game_stats: Dictionary = {
	"game_time": 0.0,
	"total_pieces": 0,
	"total_attacks": 0,
	"pps": 0.0,
	"apm": 0.0,
	"rpm": 0.0,
	"max_combo": 0,
	"max_btb": 0,
	"total_lines_cleared": 0,
	"total_spins": 0,
	"tower_height": 0.0,
	"kill_count": 0,
	"tower_average_speed": 0.0,
	"current_stage": 0
}

var game_over_reason: String = "Game Over"

## 塔控制器初始数据（由 buff_chose_area 配置，tower_controller 读取）
var tower_init_data: Dictionary = {}

## 已选取的 buff 列表（由 buff_chose_area 开始游戏时记录，供结束界面右侧列表展示）
## 元素形如 {"id": "Pressure1", "text": "高压I：apm总量增加20%"}
var selected_buffs: Array = []

## 标识：从结束界面返回 buff_chose_area 时是否恢复上次勾选
## 由 game_over 的 BACK 按钮置 true，buff_chose_area 读取后立刻复位为 false
var restore_buffs: bool = false
# var pending_replay_path: String = ""  # 回放系统已禁用

func reset_stats():
	game_stats = {
		"game_time": 0.0,
		"total_pieces": 0,
		"total_attacks": 0,
		"pps": 0.0,
		"apm": 0.0,
		"rpm": 0.0,
		"max_combo": 0,
		"max_btb": 0,
		"total_lines_cleared": 0,
		"total_spins": 0,
		"tower_height": 0.0,
		"kill_count": 0,
		"tower_average_speed": 0.0,
		"current_stage": 0
	}
	game_over_reason = "Game Over"

func update_stats(stats: Dictionary):
	if stats.has("game_time"):
		game_stats["game_time"] = stats["game_time"]
	if stats.has("total_pieces"):
		game_stats["total_pieces"] = stats["total_pieces"]
	if stats.has("total_attacks"):
		game_stats["total_attacks"] = stats["total_attacks"]
	if stats.has("pps"):
		game_stats["pps"] = stats["pps"]
	if stats.has("apm"):
		game_stats["apm"] = stats["apm"]
	if stats.has("rpm"):
		game_stats["rpm"] = stats["rpm"]
	if stats.has("max_combo"):
		game_stats["max_combo"] = stats["max_combo"]
	if stats.has("max_btb"):
		game_stats["max_btb"] = stats["max_btb"]
	if stats.has("total_lines_cleared"):
		game_stats["total_lines_cleared"] = stats["total_lines_cleared"]
	if stats.has("total_spins"):
		game_stats["total_spins"] = stats["total_spins"]
	if stats.has("tower_height"):
		game_stats["tower_height"] = stats["tower_height"]
	if stats.has("kill_count"):
		game_stats["kill_count"] = stats["kill_count"]
	if stats.has("tower_average_speed"):
		game_stats["tower_average_speed"] = stats["tower_average_speed"]
	if stats.has("current_stage"):
		game_stats["current_stage"] = stats["current_stage"]

func set_game_over_reason(reason: String):
	game_over_reason = reason

func get_game_over_reason() -> String:
	return game_over_reason

func get_stats() -> Dictionary:
	return game_stats

# ========== Replay 相关（已禁用） ==========
# func set_pending_replay(path: String):
# 	pending_replay_path = path
# 	print("设置待播放回放: ", path)
# 
# func get_pending_replay_path() -> String:
# 	return pending_replay_path
# 
# func clear_pending_replay_path():
# 	pending_replay_path = ""
