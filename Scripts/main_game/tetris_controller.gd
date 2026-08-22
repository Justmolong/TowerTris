extends Node
class_name TetrisController

## 俄罗斯方块控制器
## 负责方块移动、碰撞检测、触底锁定等逻辑

# 节点引用
@export var board_drawer: TetrisBoardDrawer  # 版面绘制器节点
@export var bag_controller: TetrisBagController  # Bag生成器节点
@export var garbage_line_controller: TetrisGarbageLineController
# @export var replay_record: ReplayRecord
@export var clear_line_controller: TetrisClearLine
@export var tower_controller: TowerController
# @export var replay_player: ReplayPlayer

var _game_started_emitted: bool = false
# var _replay_seed_override: int = 0

# 方块配置
var current_piece: Array = []      # 当前方块的形状矩阵
var current_color: Color = Color.WHITE  # 当前方块颜色
var current_position: Vector2i = Vector2i.ZERO  # 当前方块位置（格子坐标）
var current_piece_type: String = "I"  # 当前方块类型（用于踢墙表）
var current_original_shape: Array = []  # 当前方块的原始形状（用于Hold）

# 暂存系统
var hold_piece: Array = []         # 暂存的方块矩阵
var hold_color: Color = Color.WHITE  # 暂存的方块颜色
var hold_piece_type: String = ""   # 暂存的方块类型
var hold_original_shape: Array = []  # 暂存方块的原始形状（用于Hold）
var can_hold: bool = true          # 是否可以使用暂存（每回合只能使用一次）
var no_hold: bool = false          # NoHold模式：禁用暂存（不读取Hold输入，也不执行交换）

# 运动延迟系统
var move_das: float = 0.1
var move_arr: float = 0
var softdrop_delay: float = 0.02

var allow_press_move: bool = true
var keep_press_move: bool = false
var direction_press: int = 0
var double_press: bool = false

var move_start_timer: Timer
var move_keep_timer: Timer
var softdrop_timer: Timer

var press_key: Dictionary = {
	"LeftMove" : 0,
	"RightMove" : 0,
	"SoftDrop" : 0,
	"HardDrop" : 0,
	"LeftSpin" : 0,
	"RightSpin" : 0,
	"SwapSpin" : 0,
	"HoldBlock" : 0
}

var check_for_single_press: Dictionary = {
	"HardDrop" : 0,
	"SoftDrop" : 0,
	"LeftSpin" : 0,
	"RightSpin" : 0,
	"SwapSpin" : 0,
	"HoldBlock" : 0
}

# 触底锁定计时
var lock_timer: Timer
var lock_times_limit_max: int = 10
var lock_times_limit: int = 0
var lock_delay: float = 1  # 触底后锁定延迟（秒）

#重力下落
var gravity_drop_time: float = 5
var gravity_timer: Timer

# 方块锁定后的生成延迟（秒）：>0 时先等待该延迟再开始消行判定；0 表示不等待
var spawn_delay_time: float = 0
var spawn_delay_timer: Timer

# ========== 统计系统 ==========
# 全局计时
var game_time: float = 0.0          # 游戏总时间（秒）

# 回放输入覆盖模式：开启后，按键状态由 replay_player 直接驱动，而不是实时读取 Input（已注释 - 回放系统禁用）
# var replay_input_override: bool = false
var game_timer: Timer               # 游戏计时器

# PPS (Pieces Per Second)
var total_pieces: int = 0           # 总放置方块数
var pps_value: float = 0.0          # 每秒方块数

# APM (Attack Per Minute)
var total_attacks: int = 0          # 总攻击数（造成的伤害总量）
var apm_value: float = 0.0          # 每分钟攻击数

# RPM — 基于最近1分钟滚动窗口的接收攻击数
var rpm_value: float = 0.0          # 每分钟接收攻击数（仅最近1分钟）

## 存储 {time: 游戏时间秒数, damage: 伤害量} 事件，用于滑动窗口统计最近60秒的 RPM
var _rpm_events: Array[Dictionary] = []
const RPM_WINDOW_SECONDS: float = 60.0  # 滚动窗口大小（秒）

# 上次更新统计的时间
var last_stats_update_time: float = 0.0

#结束数据
var max_combo: int = 0  # 最大连击数
var max_btb: int = 0    # 最大BTB数
var total_lines_cleared: int = 0  # 总消行数
var total_spins: int = 0  # 总Spin次数

# ========== Bot 参数（控制文件见下方注释） ==========
# ---------------------------------------------------------------------------
# 【bot 参数的来源/控制文件】
#  1) bot_mode 由 tower_controller.gd 控制：关卡配置里带 "BotMode":true 时，
#     tower_controller._extra_data_deal() 会把 tetris_controller.bot_mode 置 true。
#     "BotMode" 键来自 buff_chose_area.gd 的 tower_init_data（关卡 buff 配置）。
#  2) 其余3个 @export 参数（bot_target_pps / bot_native_action_interval /
#     bot_debug_log）直接在 tetris_controller.gd 的 Inspector 里调整。
# ---------------------------------------------------------------------------
var bot_mode: bool = false
# 目标方块/秒（PPS）。控制 bot 落块的节奏上限：
#   每块最小间隔 = 1/bot_target_pps（_get_bot_piece_interval）
#   每步动作间隔 = 1/(bot_target_pps*4)（_get_bot_action_interval）
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_target_pps: float = 10

# bot 每步“原生动作”的最小间隔（秒）。越小执行越快，但过小可能因物理/程序竞争出问题。
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_native_action_interval: float = 0.005

# 是否打印 bot 调试日志（例如 ColdClear 决策路径、启用提示）。
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_debug_log: bool = true

# --- 以下为 bot 内部状态（运行期维护，勿手改） ---
var _coldclear_bridge: ColdClearBridge = null
var _bot_piece_serial: int = 0
var _bot_tracking_piece_serial: int = -1
var _bot_tracking_board_version: int = 0
var _bot_next_action_time: float = 0.0
var _bot_piece_cooldown: float = 0.0

signal game_started()
signal game_ended()

# ========== 踢墙表配置 ==========
# 现代踢墙表
var kick_table: Dictionary = {
	"all": [
		[0,0], [-1,0], [0,1], [-1,1], [0,2], [-1,2], [-2,0], [-2,1], [-2,2], [1,0], [1,1],
		[0,-1], [-1,-1], [-2,-1], [1,2], [2,0], [0,-2], [-1,-2], [-2,-2], [2,1], [2,2]
	]
}

# 返回游戏 asc 踢墙表（供 ColdClear bridge 传入 bot，使 bot 的踢墙与游戏一致）
func get_kick_table() -> Array:
	var all: Array = kick_table.get("all", [])
	return all

func _ready():
	_game_started_emitted = false
	# _replay_seed_override = 0
	
	_auto_finding()
	# _prepare_replay_if_pending()  # 回放系统已禁用
	
	# 将消行控制器引用传递给board_drawer
	if board_drawer:
		board_drawer.set_clear_line_controller(clear_line_controller)
	
	#初始化随机数管理器
	_initialize_random()
	
	_set_timer()
	
	_load_user_settings()
	
	# 初始化统计系统
	_init_stats()

	if bot_mode:
		_ensure_coldclear_bridge()
		if bot_debug_log:
			pass  # 已注释：print("[ColdClearBridge] 使用原生ColdClear决策（rust cold_clear.dll）")
	
	# 生成第一个方块
	spawn_new_piece()

func _auto_finding():
	# 自动查找board_drawer（如果未设置）
	if not board_drawer:
		board_drawer = get_node_or_null("../TetrisBoardDrawer")
		if not board_drawer:
			push_error("TetrisController: 未找到TetrisBoardDrawer节点！")
			return
	
	# 自动查找bag_controller（如果未设置）
	if not bag_controller:
		bag_controller = get_node_or_null("../TetrisBagController")
		if not bag_controller:
			push_error("TetrisController: 未找到TetrisBagController节点！")
			return
	
	# 自动查找clear_line_controller（如果未设置）
	if not clear_line_controller:
		clear_line_controller = get_node_or_null("../TetrisClearLine")
		if not clear_line_controller:
			push_error("TetrisController: 未找到TetrisClearLine节点！")
			return
	
	# 自动查找garbage_line_controller（如果未设置）
	if not garbage_line_controller:
		garbage_line_controller = get_node_or_null("../TetrisGarbageLineController")
		if not garbage_line_controller:
			push_error("TetrisController: 未找到TetrisGarbageLineController节点！")
			return
	
	# 自动查找tower_controller（如果未设置）
	if not tower_controller:
		tower_controller = get_node_or_null("../../TowerController")
		if not tower_controller:
			push_error("TetrisController: 未找到TowerController节点！")
			return
	
	# ====== 回放系统相关（已禁用） ======
	# if not replay_record:
	# 	replay_record = get_node_or_null("../ReplayRecord")
	# 
	# if not replay_player:
	# 	replay_player = get_node_or_null("../../ReplayPlayer")
	# 	if not replay_player:
	# 		replay_player = _find_replay_player(get_tree().root)

# ====== 回放系统相关函数（已禁用） ======
# func _find_replay_player(node: Node) -> ReplayPlayer:
# 	if node is ReplayPlayer:
# 		return node
# 	for child in node.get_children():
# 		var found = _find_replay_player(child)
# 		if found:
# 			return found
# 	return null
# 
# func _prepare_replay_if_pending() -> void:
# 	var replay_path = GlobalData.get_pending_replay_path()
# 	if replay_path.is_empty():
# 		return
# 	
# 	var replay_data = ReplayData.load_from_file(replay_path)
# 	if replay_data == null:
# 		push_error("无法加载回放文件用于初始化: " + replay_path)
# 		return
# 	
# 	_replay_seed_override = replay_data.random_seed
# 	print("已读取回放种子: ", _replay_seed_override)
# 	
# 	if replay_record:
# 		replay_record.auto_record = false
# 		if replay_record.is_recording_active():
# 			replay_record.stop_recording()
# 	
# 	var player = replay_player
# 	if not player:
# 		player = get_node_or_null("../../ReplayPlayer")
# 	
# 	if player and player.has_method("load_and_prepare") and player.has_method("play"):
# 		player.replay_file_path = replay_path
# 		player.tetris_controller = self
# 		player.garbage_line_controller = garbage_line_controller
# 		player.bag_controller = bag_controller
# 		player.replay_record = replay_record
# 		
# 		if not player.is_loaded:
# 			var loaded = player.load_and_prepare(replay_path)
# 			if loaded:
# 				player.call_deferred("play")
# 				print("已启动回放播放: ", replay_path)
# 			else:
# 				push_error("回放加载失败")
# 		else:
# 			print("回放已加载，直接播放")
# 			player.call_deferred("play")
# 	else:
# 		push_error("未找到 ReplayPlayer 节点")
# 	
# 	GlobalData.clear_pending_replay_path()

func _print_tree(node: Node, indent: int):
	var spaces = "  ".repeat(indent)
	print(spaces + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		_print_tree(child, indent + 1)

func _initialize_random():
	# 优先使用回放提供的种子（已禁用 - 回放系统禁用）
	# if _replay_seed_override != 0:
	# 	RandomManager.initialize(_replay_seed_override)
	# else:
	# 从设置中读取种子（如果有）
	var saved_seed = _load_saved_seed()
	if saved_seed != 0:
		RandomManager.initialize(saved_seed)
	else:
		# 使用当前时间作为种子
		RandomManager.initialize_default()
	
	# 已注释（调试噪音）：print("随机数管理器已初始化，种子: ", RandomManager.get_current_seed())

func _load_saved_seed() -> int:
	# 可以从设置文件中读取保存的种子
	# 默认返回0表示使用时间种子
	return 0

## 获取当前种子（用于Replay录制）（已禁用）
# func get_current_seed() -> int:
# 	return RandomManager.get_current_seed()

## 加载用户设置
func _load_user_settings():
	var settings = UserSetting.load_settings()
	if settings:
		move_das = settings.get("move_das", 0.1)
		move_arr = settings.get("move_arr", 0.0)
		softdrop_delay = settings.get("softdrop_delay", 0.1)
		
		# 更新计时器
		if move_start_timer and move_das != 0:
			move_start_timer.wait_time = move_das
		if move_keep_timer and move_arr != 0:
			move_keep_timer.wait_time = move_arr
		if softdrop_timer and softdrop_delay != 0:
			softdrop_timer.wait_time = softdrop_delay
		
		# 应用键位设置
		UserSetting.apply_key_bindings_from_dict(settings)

func _set_timer():
	move_start_timer = Timer.new()
	if move_das != 0:
		move_start_timer.wait_time = move_das
	move_start_timer.one_shot = true
	add_child(move_start_timer)
	
	move_keep_timer = Timer.new()
	if move_arr != 0:
		move_keep_timer.wait_time = move_arr
	move_keep_timer.one_shot = true
	add_child(move_keep_timer)
	
	softdrop_timer = Timer.new()
	softdrop_timer.wait_time = softdrop_delay
	softdrop_timer.one_shot = true
	add_child(softdrop_timer)
	
	lock_timer = Timer.new()
	lock_timer.wait_time = lock_delay
	lock_timer.one_shot = true
	lock_timer.timeout.connect(_lock_piece)
	add_child(lock_timer)
	
	# 生成延迟计时器：方块锁定后先等待 spawn_delay_time，再开始消行判定
	spawn_delay_timer = Timer.new()
	spawn_delay_timer.one_shot = true
	spawn_delay_timer.timeout.connect(_process_after_spawn_delay)
	add_child(spawn_delay_timer)
	
	gravity_timer = Timer.new()
	if gravity_drop_time != 0:
		gravity_timer.wait_time = gravity_drop_time
	gravity_timer.one_shot = true
	add_child(gravity_timer)
	
	# 游戏计时器（每0.1秒更新一次统计）
	game_timer = Timer.new()
	game_timer.wait_time = 0.1
	game_timer.one_shot = false
	game_timer.timeout.connect(_update_stats)
	add_child(game_timer)
	game_timer.start()

## 初始化统计系统
func _init_stats():
	game_time = 0.0
	total_pieces = 0
	total_attacks = 0
	pps_value = 0.0
	apm_value = 0.0
	rpm_value = 0.0
	last_stats_update_time = 0.0
	# 重置 RPM 滚动窗口
	_rpm_events.clear()

## 更新统计信息（每0.1秒调用）
func _update_stats():
	# 更新游戏时间
	game_time += 0.1
	
	# 计算PPS
	if game_time > 0:
		pps_value = total_pieces / game_time
	
	# 计算APM
	if game_time > 0:
		apm_value = (total_attacks / game_time) * 60.0
	
	# 计算RPM（滚动最近1分钟窗口）
	_prune_rpm_events()
	rpm_value = _compute_rpm_from_window()
	
	# 更新显示
	if board_drawer:
		board_drawer.update_stats(pps_value, apm_value, rpm_value)

## 记录放置方块（PPS统计）
func _record_piece_placed():
	total_pieces += 1

## 记录造成攻击（APM统计）
func _record_attack_damage(damage: int):
	if damage > 0:
		total_attacks += damage

## 记录接收攻击（RPM统计 — 基于最近1分钟滚动窗口）
func _record_received_damage(damage: int):
	if damage > 0:
		# 向滚动窗口添加事件（带当前游戏时间戳）
		_rpm_events.append({"time": game_time, "damage": damage})

# ========== RPM 滚动窗口辅助 ==========

## 清理超出窗口的过期事件
func _prune_rpm_events() -> void:
	var cutoff: float = game_time - RPM_WINDOW_SECONDS
	var i: int = 0
	while i < _rpm_events.size():
		if _rpm_events[i]["time"] < cutoff:
			i += 1
		else:
			break
	if i > 0:
		_rpm_events = _rpm_events.slice(i)

## 从滚动窗口计算 RPM（最近 RPM_WINDOW_SECONDS 秒内的每分钟接收攻击数）
func _compute_rpm_from_window() -> float:
	if _rpm_events.is_empty():
		return 0.0
	
	# 窗口内的实际时间跨度（取窗口大小与游戏时间中的较小值）
	var window_span: float = min(RPM_WINDOW_SECONDS, game_time)
	if window_span <= 0.0:
		return 0.0
	
	var total: int = 0
	for event: Dictionary in _rpm_events:
		total += event["damage"]
	
	return (total / window_span) * 60.0

## 获取当前统计信息
func get_stats() -> Dictionary:
	return {
		"game_time": game_time,
		"total_pieces": total_pieces,
		"total_attacks": total_attacks,
		"pps": pps_value,
		"apm": apm_value,
		"rpm": rpm_value
	}

## 重置统计信息
func reset_stats():
	_init_stats()
	if board_drawer:
		board_drawer.update_stats(pps_value, apm_value, rpm_value)

## 生成新方块（从Bag中获取）
func spawn_new_piece():
	# 从Bag控制器获取下一个方块
	var piece_data = bag_controller.get_next_piece()
	var spawn_x = int((board_drawer.grid_width - piece_data["shape"][0].size()) / 2)
	# 生成Y坐标：从下往上数第22行
	var spawn_y = max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22)
	
	# 检查生成时是否碰撞（游戏结束判定）
	if _check_collision(Vector2i(spawn_x, spawn_y), piece_data["shape"], false):
		push_error("游戏结束！无法生成新方块")
		_game_over("方块堆积到顶部")
		return false
	
	current_piece = piece_data["shape"]
	current_color = piece_data["color"]
	current_piece_type = piece_data["type"]
	current_original_shape = bag_controller.get_original_shape(current_piece_type)
	current_position = Vector2i(spawn_x, spawn_y)
	_bot_piece_serial += 1
	# 调试：记录方块 spawn 位置（矩阵左上角），用于对照 CC 决策与执行
	if bot_debug_log:
		print("[BotSpawn] piece=", current_piece_type, " spawn=(", current_position.x, ",", current_position.y, ")")
	
	_draw_current_piece()
	
	if gravity_drop_time != 0:
		gravity_timer.start()
	lock_timer.stop()
	lock_times_limit = lock_times_limit_max
	
	can_hold = true
	
	_update_next_display()
	_update_shadow()
	
	_record_piece_placed()
	
	# 触发游戏开始信号（首次生成方块时）
	if not _game_started_emitted:
		_game_started_emitted = true
		game_started.emit()
	
	return true

## 生成新方块但不重置hold权限（用于hold交换后的生成）
func spawn_new_piece_keep_hold():
	# 从Bag控制器获取下一个方块
	var piece_data = bag_controller.get_next_piece()
	var spawn_x = int((board_drawer.grid_width - piece_data["shape"][0].size()) / 2)
	# 生成Y坐标：从下往上数第22行
	var spawn_y = max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22)
	
	# 检查生成时是否碰撞（游戏结束判定）
	if _check_collision(Vector2i(spawn_x, spawn_y), piece_data["shape"], false):
		push_error("游戏结束！无法生成新方块")
		_game_over("方块堆积到顶部")
		return false
	
	current_piece = piece_data["shape"]
	current_color = piece_data["color"]
	current_piece_type = piece_data["type"]
	current_original_shape = bag_controller.get_original_shape(current_piece_type)
	current_position = Vector2i(spawn_x, spawn_y)
	_bot_piece_serial += 1
	
	# 绘制方块到版面
	_draw_current_piece()
	
	# 重置锁定状态
	if gravity_drop_time != 0:
		gravity_timer.start()
	lock_timer.stop()
	lock_times_limit = lock_times_limit_max
	
	_update_next_display()
	_update_shadow()
	
	# 记录放置方块（PPS）
	_record_piece_placed()
	
	return true

## 游戏结束方法
func _game_over(reason: String = "Game Over"):
	# 停止所有计时器
	game_timer.stop()
	gravity_timer.stop()
	lock_timer.stop()
	move_start_timer.stop()
	move_keep_timer.stop()
	softdrop_timer.stop()
	
	# 停止接受输入
	set_process(false)
	
	# 收集最终统计数据
	var stats = get_stats()
	
	if clear_line_controller:
		stats["max_combo"] = max_combo
		stats["max_btb"] = max_btb
		stats["total_lines_cleared"] = total_lines_cleared
		stats["total_spins"] = total_spins
	
	# 获取塔控制器数据
	var tower = get_node_or_null("../../TowerController")
	if tower:
		stats["tower_height"] = tower.tower_meter
		stats["kill_count"] = tower.kill_count
		stats["tower_average_speed"] = tower.tower_meter / maxf(game_time, 0.001)
		stats["current_stage"] = tower.current_stage
	
	GlobalData.update_stats(stats)
	GlobalData.set_game_over_reason(reason)
	
	# 触发游戏结束信号
	game_ended.emit()
	
	# 通知版面变黑
	if board_drawer:
		board_drawer.is_game_over = true
		board_drawer.queue_redraw()
	
	# 延迟切换到游戏结束场景
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Tscns/game_over.tscn")

## 更新Next显示
func _update_next_display():
	if board_drawer and bag_controller:
		var next_pieces = []
		# 从board_drawer读取配置的next_count
		var next_count = board_drawer.next_count
		var piece_types = bag_controller.peek_next_pieces(next_count)
		
		for piece_type in piece_types:
			var shape = bag_controller.get_original_shape(piece_type)
			var color = bag_controller.get_piece_color(piece_type)
			next_pieces.append({
				"shape": shape,
				"color": color
			})
		
		board_drawer.set_next_pieces(next_pieces)

## 绘制当前方块到版面
func _draw_current_piece():
	# 清除当前方块（重新绘制时会覆盖，但为了安全先清除）
	_clear_current_piece()
	
	# 绘制新位置的方块
	for y in range(current_piece.size()):
		for x in range(current_piece[y].size()):
			if current_piece[y][x] == 1:
				var board_x = current_position.x + x
				var board_y = current_position.y + y
				board_drawer.set_cell_color(board_x, board_y, current_color)

## 清除当前方块
func _clear_current_piece():
	for y in range(current_piece.size()):
		for x in range(current_piece[y].size()):
			if current_piece[y][x] == 1:
				var board_x = current_position.x + x
				var board_y = current_position.y + y
				board_drawer.set_cell_color(board_x, board_y, null)

## 检查碰撞
func _check_collision(pos: Vector2i, piece: Array = current_piece, ignore_current_piece: bool = true) -> bool:
	if ignore_current_piece:
		_clear_current_piece()
	
	var is_not_allow : bool = false
	
	for y in range(piece.size()):
		for x in range(piece[y].size()):
			if piece[y][x] == 1:
				var board_x = pos.x + x
				var board_y = pos.y + y
				
				# 边界检查
				if board_x < 0 or board_x >= board_drawer.grid_width:
					is_not_allow = true
				if board_y >= board_drawer.grid_height + board_drawer.above_visible_rows:
					is_not_allow = true
				
				# 检查与其他格子的碰撞（只检查非空格子）
				if board_y >= 0 and board_drawer.get_cell_color(board_x, board_y) != null:
					is_not_allow = true
		if is_not_allow:
			break
	
	if ignore_current_piece:
		_draw_current_piece()
	return is_not_allow

## 尝试移动方块
func _try_move(delta_x: int, delta_y: int) -> bool:
	# 手上无方块（生成/消行延迟期间）：不移动，避免空方块在 while 循环里无限下落导致卡死
	if current_piece.is_empty():
		return false
	var new_pos = Vector2i(current_position.x + delta_x, current_position.y + delta_y)
	_check_underground_touch()
	
	if not _check_collision(new_pos):
		# 移动成功
		_clear_current_piece()
		current_position = new_pos
		_draw_current_piece()
		
		_check_underground_touch()
		# 移动后重置锁延
		if lock_times_limit > 0 and not lock_timer.is_stopped():
			lock_timer.start()
			lock_times_limit -= 1
		
		_update_shadow()
		return true
	else:
		
		return false

func _check_underground_touch():
	var new_pos = Vector2i(current_position.x, current_position.y + 1)
	if not _check_collision(new_pos):
		lock_timer.stop()
	elif lock_timer.is_stopped():
		lock_timer.start()

## 锁定当前方块。
## 逻辑上清除 current_piece（board_data 中已锁定的格子保持不变），
## 先触发 spawn_delay_time 延迟（为 0 时无需等待），延迟结束后再开始消行判定。
## 生成新方块由 TetrisClearLine 在消行结束后调用 spawn_new_piece() 完成。
func _lock_piece():
	# 已在等待生成新方块时避免重复触发
	if current_piece.is_empty():
		return
	# 逻辑上清除当前方块（保留 board_data 中已锁定的格子）
	current_piece = []
	# 触发生成延迟；为 0 时直接处理消行
	if spawn_delay_time > 0:
		spawn_delay_timer.wait_time = spawn_delay_time
		spawn_delay_timer.start()
	else:
		_process_after_spawn_delay()

## 生成延迟结束：开始处理消行判定（消行 + 统计 + 垃圾处理）
func _process_after_spawn_delay():
	# 先检测是否有消行
	var cleared = _check_and_clear_lines()
	
	# 只有在没有消行的情况下才触发垃圾行增长
	if cleared == 0 and garbage_line_controller:
		garbage_line_controller.process_garbage_after_lock()

## 检测并消除完整的行，并处理垃圾行抵消
func _check_and_clear_lines() -> int:
	if clear_line_controller:
		var cleared = clear_line_controller.check_and_clear_lines()
		if cleared > 0:
			#print("消除了 ", cleared, " 行")
			
			# 更新总消行数
			total_lines_cleared += cleared
			
			# 更新最大连击
			var combo = clear_line_controller.get_combo_count()
			if combo > max_combo:
				max_combo = combo
			
			# 更新最大BTB
			var btb = clear_line_controller.get_btb_count()
			if btb > max_btb:
				max_btb = btb
			
			# 检测是否有Spin
			var spin_text = clear_line_controller.get_current_spin_text()
			if not spin_text.is_empty():
				total_spins += 1
			
			# 获取攻击伤害值
			var damage = clear_line_controller.get_current_damage()
			
			# 记录消行事件
				# 回放系统仅保留用户输入和垃圾行输入，派生事件不再记录
			
			# 记录造成攻击（APM）
			if damage > 0:
				_record_attack_damage(damage)
			
			# 如果有伤害且垃圾槽不为空，执行抵消
			if damage > 0 and garbage_line_controller and garbage_line_controller.get_enter_queue_size() > 0:
				var offset_count: int = garbage_line_controller.offset_garbage(damage)
				# 抵消的部分作为奖励也输入给塔
				if offset_count > 0 and tower_controller:
					tower_controller.attack_increase_tower(offset_count)
		
		return cleared
	return 0

## 添加攻击（由外部调用）
func add_garbage_attack(attack_count: int):
	if garbage_line_controller:
		garbage_line_controller.add_attack(attack_count)
		# 记录接收攻击（RPM）
		_record_received_damage(attack_count)

# ========== 旋转系统 ==========

## 左旋（逆时针旋转90度）
func rotate_left():
	_rotate_piece(-1)

## 右旋（顺时针旋转90度）
func rotate_right():
	_rotate_piece(1)

## 180度旋转
func rotate_180():
	_rotate_piece(2)

## 旋转方块核心逻辑
func _rotate_piece(direction: int):
	if current_piece.is_empty():
		return false  # 手上无方块（延迟期间）：不旋转
	var rotated_piece
	
	match direction:
		1:  # 顺时针旋转 90度
			rotated_piece = _get_rotated_matrix(current_piece, 1)
			_apply_rotation_with_kick(rotated_piece, 1)
		-1:  # 逆时针旋转 90度
			rotated_piece = _get_rotated_matrix(current_piece, -1)
			_apply_rotation_with_kick(rotated_piece, -1)
		2:  # 180度旋转
			rotated_piece = _get_rotated_matrix(current_piece, 2)
			_apply_rotation_with_kick(rotated_piece, 2)
		_:
			return false

## 应用旋转并尝试踢墙
func _apply_rotation_with_kick(rotated_piece: Array, direction: int):
	# 获取踢墙表偏移
	var kicks = kick_table["all"]
	var kick_multiplier = 1
	
	# 根据旋转方向确定踢墙偏移乘数
	match direction:
		1:  # 右旋：使用原始偏移
			kick_multiplier = 1
		-1:  # 左旋：X方向取反
			kick_multiplier = -1
		2:  # 180度旋转：使用原始偏移（对称）
			kick_multiplier = 1
	
	for kick in kicks:
		var kick_x = kick[0] * kick_multiplier
		var kick_y = kick[1]
		var new_pos = Vector2i(current_position.x + kick_x, current_position.y + kick_y)
		
		if not _check_collision(new_pos, rotated_piece):
			# 旋转成功
			_clear_current_piece()
			current_piece = rotated_piece
			current_position = new_pos
			_draw_current_piece()
			
			# 记录旋转事件（用于Spin检测），传递方块颜色
			if clear_line_controller:
				clear_line_controller.record_rotation(current_piece_type, current_piece, current_position, current_color)
			
			_check_underground_touch()
			
			# 旋转后重置锁延
			if lock_times_limit > 0 and not lock_timer.is_stopped():
				lock_timer.stop()
				lock_timer.start()
				lock_times_limit -= 1
			
			_update_shadow()
			return true
	
	# 所有踢墙尝试都失败
	return false

## 获取旋转后的矩阵
func _get_rotated_matrix(piece: Array, direction: int) -> Array:
	var rows = piece.size()
	var cols = piece[0].size()
	var rotated = []
	
	match direction:
		1:  # 顺时针旋转 90度
			rotated.resize(cols)
			for i in range(cols):
				rotated[i] = []
				rotated[i].resize(rows)
				for j in range(rows):
					rotated[i][j] = piece[rows - 1 - j][i]
		-1:  # 逆时针旋转 90度
			rotated.resize(cols)
			for i in range(cols):
				rotated[i] = []
				rotated[i].resize(rows)
				for j in range(rows):
					rotated[i][j] = piece[j][cols - 1 - i]
		2:  # 180度旋转
			rotated.resize(rows)
			for i in range(rows):
				rotated[i] = []
				rotated[i].resize(cols)
				for j in range(cols):
					rotated[i][j] = piece[rows - 1 - i][cols - 1 - j]
	
	return rotated

# ========== 暂存系统 ==========

## 暂存当前方块
func hold_current_piece():
	if current_piece.is_empty():
		return false  # 手上无方块（延迟期间）：不可暂存
	if no_hold:
		return false  # NoHold模式：禁用暂存
	if not can_hold:
		return false  # 本回合已使用过暂存
	
	# 清除当前方块
	_clear_current_piece()
	
	# 如果暂存区为空，将当前方块存入暂存，然后生成新方块
	if hold_piece.is_empty():
		# 保存当前方块的原始形状（未旋转状态）
		hold_piece = bag_controller.get_original_shape(current_piece_type)
		hold_color = current_color
		hold_piece_type = current_piece_type
		hold_original_shape = bag_controller.get_original_shape(current_piece_type)
		
		# 更新Hold显示
		board_drawer.set_hold_piece(hold_piece, hold_color)
		
		# 生成新方块（保持hold状态）
		spawn_new_piece_keep_hold()
	else:
		# 暂存区有方块时，进行交换
		# 先保存当前方块的完整信息
		var temp_piece = current_piece
		var temp_color = current_color
		var temp_type = current_piece_type
		var temp_original = current_original_shape
		
		# 从暂存区取出方块
		current_piece = bag_controller.get_original_shape(hold_piece_type)
		current_color = hold_color
		current_piece_type = hold_piece_type
		current_original_shape = hold_original_shape
		
		# 将当前方块存入暂存区
		hold_piece = bag_controller.get_original_shape(temp_type)
		hold_color = temp_color
		hold_piece_type = temp_type
		hold_original_shape = temp_original
		
		# 更新Hold显示
		board_drawer.set_hold_piece(hold_piece, hold_color)
		
		# 重置位置（从下往上数第22行）
		var spawn_x = int((board_drawer.grid_width - current_piece[0].size()) / 2)
		var spawn_y = max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22)
		current_position = Vector2i(spawn_x, spawn_y)
		
		# 检查生成时是否碰撞（游戏结束判定）
		if _check_collision(current_position):
			push_error("游戏结束！无法生成方块")
			# 如果交换后发生碰撞，恢复原状
			current_piece = temp_piece
			current_color = temp_color
			current_piece_type = temp_type
			current_original_shape = temp_original
			hold_piece = bag_controller.get_original_shape(hold_piece_type)
			hold_color = temp_color  # 恢复hold颜色
			board_drawer.set_hold_piece(hold_piece, hold_color)
			_draw_current_piece()
			return false
		
		# 绘制方块到版面
		_draw_current_piece()
		_update_shadow()
		
		# 重置锁定状态
		lock_timer.stop()
		lock_times_limit = lock_times_limit_max
	
	# 标记暂存已使用
	can_hold = false
	return true

## 获取当前暂存的方块（用于显示）
func get_hold_piece() -> Array:
	return hold_piece

## 获取暂存方块的颜色
func get_hold_color() -> Color:
	return hold_color

## 清空暂存
func clear_hold():
	hold_piece = []
	hold_color = Color.WHITE
	hold_piece_type = ""
	hold_original_shape = []

# ========== 公共控制方法 ==========
## 计算影子位置（硬降到底的位置）
func _calculate_shadow_position() -> Vector2i:
	if current_piece.is_empty():
		return Vector2i.ZERO
	
	var shadow_pos = current_position
	
	# 一直向下移动直到碰撞
	while true:
		var test_pos = Vector2i(shadow_pos.x, shadow_pos.y + 1)
		if _check_collision(test_pos, current_piece):
			break
		shadow_pos = test_pos
	
	return shadow_pos

## 更新影子显示
func _update_shadow():
	if board_drawer:
		if current_piece.is_empty():
			board_drawer.clear_shadow()
		else:
			var shadow_pos = _calculate_shadow_position()
			board_drawer.update_shadow(current_piece, shadow_pos, current_color)

## 左移
func move_left():
	_try_move(-1, 0)

## 右移
func move_right():
	_try_move(1, 0)

## 软降（单步向下）
func soft_drop():
	_try_move(0, 1)

## 软降到底（不锁定）：bot 路径中的 "soft_drop" 动作（ColdClear SonicDrop）使用本方法，
## 对应将当前方块一直下落到触底位置，但不像 hard_drop 那样立即锁定，等待后续 hard_drop 锁定。
func soft_drop_to_bottom():
	if current_piece.is_empty():
		return  # 手上无方块（延迟期间）：不下落
	while _try_move(0, 1):
		pass

## 硬降（直接落底）
func hard_drop():
	if current_piece.is_empty():
		return  # 手上无方块（延迟期间）：不硬降
	# 一直向下移动直到碰撞
	while _try_move(0, 1):
		pass  # 继续移动
	
	# 调试：打印锁定前的最终位置（对比 CC 决策期望落点）
	if bot_debug_log:
		print("[BotLock] piece=", current_piece_type, " final=(", current_position.x, ",", current_position.y, ")")
	
	# 触底后立即锁定
	_lock_piece()

# ========== 更新循环 ==========

func _process(delta):
	if bot_mode:
		_process_bot_control(delta)
		# 等原生 ColdClear 决策期间暂停当前方块下落：
		# bot 的移动序列（含旋转踢墙）是基于“当前方块仍在 spawn 位”规划的相对移动，
		# 若决策等待期间方块持续下落，执行计划时旋转踢墙会在错误高度触发，
		# 导致旋转/落点错乱（表现为“移动错乱 / missdrop”）。
		if _coldclear_bridge == null or not _coldclear_bridge.is_waiting_decision():
			gravity_drop()
		return
	
	# if not replay_input_override:  # 回放系统已禁用
	change_key_press_to_var()
	#TODO::回放系统模拟按键输入
	replay_set_keyvar_input()
	_process_input()
	check_for_var_single_press()
	gravity_drop()

func _ensure_coldclear_bridge() -> void:
	if _coldclear_bridge != null:
		return
	_coldclear_bridge = ColdClearBridge.new()
	add_child(_coldclear_bridge)

func _process_bot_control(delta: float) -> void:
	_ensure_coldclear_bridge()
	if _coldclear_bridge == null:
		return
	if current_piece.is_empty():
		return

	if _bot_piece_cooldown > 0.0:
		_bot_piece_cooldown = max(0.0, _bot_piece_cooldown - delta)

	if _bot_next_action_time > 0.0:
		_bot_next_action_time = max(0.0, _bot_next_action_time - delta)
		return

	# 新块开始：请求新的原生 ColdClear 决策
	if _bot_tracking_piece_serial != _bot_piece_serial:
		_bot_tracking_piece_serial = _bot_piece_serial
		if _coldclear_bridge.using_native_cc():
			_coldclear_bridge.request_plan(self)

	# 垃圾行抬升期间版面已变化（force_raise_rows 已递增 board_version）。
	# 注意：垃圾上涨是整版（含当前方块）同步上移（force_raise_rows 会把当前方块一并上移），
	# 因此当前方块相对堆叠的落点与形状不变，其正在执行的旧计划（相对移动序列）依然有效。
	# 若在此打断并重新规划，新计划按“方块在 spawn 位”生成，而方块实际已移动/已按旧计划走了
	# 若干步，会导致当前块 missdrop。所以仅当本块完全没有计划（如首次请求失败）时，才基于
	# 新版面重试；否则继续执行旧计划，待本块锁定后由“新块开始”逻辑按新版面请求。
	if garbage_line_controller != null and _bot_tracking_board_version != garbage_line_controller.board_version:
		_bot_tracking_board_version = garbage_line_controller.board_version
		# 避免请求堆积：若已有在途决策（正在等待），交给其完成后自然对账；否则才重新请求。
		if _coldclear_bridge.using_native_cc() and not _coldclear_bridge.is_waiting_decision():
			if _coldclear_bridge.is_plan_empty():
				_coldclear_bridge.request_plan(self)

	# 等待原生 ColdClear 异步决策期间，暂停动作
	if _coldclear_bridge.using_native_cc() and _coldclear_bridge.is_waiting_decision():
		return

	# 无可用原生计划（原生不可用/决策失败/计划已消费）时，直接硬降锁定当前块
	if not _coldclear_bridge.using_native_cc() or not _coldclear_bridge.has_plan():
		if _bot_piece_cooldown > 0.0:
			_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
			return
		hard_drop()
		_bot_piece_cooldown = _get_bot_piece_interval()
		return

	# 执行计划中的下一个动作
	var decided_action: BotAction = _coldclear_bridge.next_plan_action()
	if decided_action == null or String(decided_action.move).is_empty():
		decided_action = BotAction.new("hard_drop", ["hard_drop"], "hard_drop")

	# PPS限制核心：未到每块最小间隔前，阻止hard_drop锁定新块。
	if _bot_piece_cooldown > 0.0 and decided_action.move == "hard_drop":
		_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
		return

	_apply_bot_action(decided_action)

	if decided_action.move == "hard_drop":
		_bot_piece_cooldown = _get_bot_piece_interval()

	var action_interval: float = _get_bot_action_interval()
	if action_interval > 0.0:
		_bot_next_action_time = min(action_interval, bot_native_action_interval) if action_interval > 0.0 else bot_native_action_interval

## 把 CC 决策出的动作（BotAction）映射到游戏内直接调用
func _apply_bot_action(action: BotAction) -> void:
	if action == null:
		return
	# 调试：打印每步动作执行前的方块位置，用于对照 CC 决策 movements
	if bot_debug_log:
		print("[BotStep] ", String(action.move), " before=(", current_position.x, ",", current_position.y, ")")
	match String(action.move):
		"left":
			move_left()
		"right":
			move_right()
		"rotate_left":
			rotate_left()
		"rotate_right":
			rotate_right()
		"rotate_180":
			rotate_180()
		"soft_drop":
			# ColdClear 的 'D'(CC_DROP) 在引擎里是 PieceMovement::SonicDrop（直接下落到触底），
			# 本游戏软降默认也是直接触底（softdrop_delay==0 → 一路 drop 到底），所以用
			# soft_drop_to_bottom() 完全对应。CC 的 'D' 通常出现在路径末尾（或由最后 hard_drop
			# 兜底触底），因此这样映射不会造成误放置；若计划中段出现 'D'，会先触底再继续横移，
			# 此时需保证已落在堆叠上（CC 搜索不会生成触底后还需横移的路径）。
			soft_drop_to_bottom()
		"hold":
			hold_current_piece()
		"hard_drop":
			hard_drop()

func _get_bot_action_interval() -> float:
	if bot_target_pps <= 0.0:
		return 0.0
	# 目标为每秒可完成的方块数，简单换算为每步动作节奏上限
	return 1.0 / max(bot_target_pps * 4.0, 0.001)

func _get_bot_piece_interval() -> float:
	if bot_target_pps <= 0.0:
		return 0.0
	return 1.0 / max(bot_target_pps, 0.001)

## 处理键盘输入
func _process_input():
	# 手上无方块（生成/消行延迟期间）：不处理输入，避免对空方块执行旋转/暂存/硬降
	if current_piece.is_empty():
		return
	#arr和das判定
	if press_key["LeftMove"] == 1 and press_key["RightMove"] == 1:
		if not double_press:
			direction_press *= -1
			move_start_timer.paused = true
			move_keep_timer.stop()
			keep_press_move = false
		double_press = true
	else:
		double_press = false
		if press_key["LeftMove"] == 1:
			if direction_press == 1:
				move_start_timer.paused = true
				move_keep_timer.stop()
				keep_press_move = false
			direction_press = -1
		if press_key["RightMove"] == 1:
			if direction_press == -1:
				move_start_timer.paused = true
				move_keep_timer.stop()
				keep_press_move = false
			direction_press = 1
		if not (press_key["LeftMove"] == 1 or press_key["RightMove"] == 1):
			direction_press = 0
	# 左右移动
	if direction_press != 0:
		if move_arr != 0:
			if move_start_timer.is_stopped() and move_keep_timer.is_stopped():
				_try_move(direction_press, 0)
				move_keep_timer.start()
		else:
				if move_start_timer.is_stopped() and not keep_press_move:
					_try_move(direction_press, 0)
				elif move_start_timer.is_stopped() and keep_press_move and not _check_collision(current_position + Vector2i(direction_press,0)):
					var one_drop : bool = true
					while _try_move(direction_press, 0):
						if not _check_collision(current_position + Vector2i(0,1)) and one_drop and press_key["SoftDrop"] == 1:
							while _try_move(0,1) and one_drop:
								if softdrop_delay != 0:
									one_drop = false
						if gravity_drop_time == 0 and not _check_collision(current_position + Vector2i(0,1)):
							while _try_move(0,1):
								pass
				else:
					pass
	if direction_press != 0 and not keep_press_move:
		move_start_timer.paused = false
		move_start_timer.start()
		keep_press_move = true
	elif direction_press == 0:
		move_start_timer.stop()
		move_keep_timer.stop()
		keep_press_move = false
	else:
		pass
	
	# 软降
	if press_key["SoftDrop"] == 1 and softdrop_timer.is_stopped():
		if softdrop_delay != 0:
			soft_drop()
			softdrop_timer.start()
		elif softdrop_delay == 0:
			if not _check_collision(current_position + Vector2i(0,1)):
				while _try_move(0,1):
					pass
		else:
			push_error("发生意料之外的错误！")
	
	# 旋转
	if press_key["LeftSpin"] == 1 and check_for_single_press["LeftSpin"] != 1:
		rotate_left()
	
	if press_key["RightSpin"] == 1 and check_for_single_press["RightSpin"] != 1:
		rotate_right()
	
	# 180度旋转
	if press_key["SwapSpin"] == 1 and check_for_single_press["SwapSpin"] != 1:
		rotate_180()
	
	# 暂存（NoHold模式下不读取Hold输入）
	if press_key["HoldBlock"] == 1 and check_for_single_press["HoldBlock"] != 1 and not no_hold:
		hold_current_piece()
	
	# 硬降
	if press_key["HardDrop"] == 1 and check_for_single_press["HardDrop"] != 1:
		hard_drop()

func change_key_press_to_var():
	for i in press_key:
		if Input.is_action_pressed(i):
			press_key[i] = 1
		else:
			press_key[i] = 0

func check_for_var_single_press():
	for i in check_for_single_press:
		if press_key[i] == 1 and check_for_single_press[i] == 0:
			check_for_single_press[i] = 1
		elif press_key[i] == 0:
			check_for_single_press[i] = 0
		else:
			pass

#TODO::回放系统模拟按键输入
func replay_set_keyvar_input():
	pass

## 开启/关闭回放输入覆盖（已禁用）
# func set_replay_input_override(enabled: bool):
# 	replay_input_override = enabled
# 	change_key_press_to_var()

## 用于回放系统模拟真实按键输入（已禁用）
# func set_replay_input(action: String, pressed: bool):
# 	if not press_key.has(action):
# 		return
# 	
# 	press_key[action] = 1 if pressed else 0
# 	
# 	_process_input()
# 	
# 	if pressed and check_for_single_press.has(action):
# 		check_for_single_press[action] = 1
# 	elif not pressed and check_for_single_press.has(action):
# 		check_for_single_press[action] = 0

func gravity_drop():
	# 手上无方块（生成/消行延迟期间）：跳过下落逻辑
	if current_piece.is_empty():
		return
	if gravity_timer.is_stopped() and gravity_drop_time != 0:
		_try_move(0,1)
		#garbage_line_controller.add_attack(5)
		gravity_timer.start()
	if gravity_drop_time == 0:
		if not _check_collision(current_position + Vector2i(0,1)):
			while _try_move(0,1):
				pass

# ========== 辅助方法 ==========

## 获取当前方块的宽度
func get_current_piece_width() -> int:
	if current_piece.is_empty():
		return 0
	return current_piece[0].size()

## 获取当前方块的高度
func get_current_piece_height() -> int:
	return current_piece.size()

## 手动设置方块（用于扩展）
func set_piece(piece: Array, color: Color, piece_type: String = "I"):
	current_piece = piece
	current_color = color
	current_piece_type = piece_type
	current_original_shape = bag_controller.get_original_shape(piece_type)
	spawn_new_piece()
