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

## 说明：与「本局 buff / 关卡初始化数据」相关的内容（tower_init_data / selected_buffs /
## restore_buffs）已全部迁到游戏内公共数据区 TetrisGlobalData，本文件只保留跨场景的统计数据。
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
