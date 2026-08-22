extends Node2D
class_name TetrisBoardDrawer

## 俄罗斯方块版面绘制器
## 提供网格绘制功能，支持自定义基准点、格子大小、网格尺寸

@export var clear_line_controller: TetrisClearLine
@export var garbage_line_controller: TetrisGarbageLineController
@export var tetris_controller: TetrisController
@export var tower_controller: TowerController      # 塔控制器引用（用于读取高度/速度）

# 网格配置
@export var grid_width: int = 10        # 网格宽度（列数）
@export var grid_height: int = 20       # 网格高度（行数）- 实际可见高度
@export var above_visible_rows: int = 70 # 可见区域上方预留行数（用于垃圾槽扩展，不绘制背景和网格线）
@export var grid_max_height: int = 100   # 网格最大高度（行数）- 用于垃圾槽和扩展
@export var cell_size: int = 24         # 格子边长（像素）
@export var offset_x: int = 0           # 基准点X偏移（左上角X坐标）- 通常由自动居中覆盖
@export var offset_y: int = 0           # 基准点Y偏移（左上角Y坐标）- 通常由自动居中覆盖

# 显示配置
@export var auto_center: bool = true    # 是否自动居中版面
@export var auto_resize: bool = true    # 是否自动适应窗口大小
@export var margin_percentage: float = 0.1  # 边距百分比（相对窗口较小边）

# 颜色配置
@export var background_color: Color = Color(0, 0, 0, 1.0)     # 背景色
@export var grid_line_color: Color = Color(0.399, 0.399, 0.399, 1.0)      # 网格线颜色
@export var grid_line_width: float = 1.0              # 网格线宽度
@export var board_border_color: Color = Color.WHITE   # 版面左右边缘边框颜色
@export var board_border_width: float = 2.0           # 版面左右边缘边框宽度

# 影子方块配置
@export var shadow_enabled: bool = true               # 是否启用影子显示
@export var shadow_opacity: float = 0.55               # 影子透明度（0-1）
@export var shadow_border_opacity: float = 0.75        # 影子边框透明度（0-1）

# 垃圾槽配置
@export var garbage_slot_enabled: bool = true         # 是否启用垃圾槽
@export var garbage_slot_width: int = 1               # 垃圾槽宽度（格子数）
@export var garbage_slot_border_color: Color = Color.WHITE  # 垃圾槽边框颜色
@export var garbage_slot_border_width: float = 2.0    # 垃圾槽边框宽度（与版面边框一致，保证左右两侧粗细相同）
var garbage_cap : int
@export var garbage_cap_line_color: Color = Color.WHITE  # 垃圾槽横线颜色
@export var garbage_bar_color: Color = Color.RED      # 垃圾行矩形颜色
@export var garbage_bar_separator_color: Color = Color.BLACK  # 垃圾行分割线颜色
@export var garbage_bar_separator_width: float = 1.0  # 分割线宽度
@export var garbage_bar_padding: float = 0.1          # 垃圾矩形内边距（相对于格子大小的比例）

# 统计信息配置
@export var stats_display_enabled: bool = true        # 是否启用统计信息显示
@export var stats_text_color: Color = Color.WHITE     # 统计信息文字颜色
@export var stats_text_outline_color: Color = Color.BLACK  # 统计信息文字描边颜色
@export var stats_font_size_ratio: float = 0.7        # 统计信息字体大小比例（相对于cell_size）
@export var stats_spacing_cells: float = 1          # 统计信息行间距（格子数）
@export var stats_offset_x_cells: float = -5      # 统计信息相对垃圾槽左侧的X偏移（格子数，负值向左）
@export var stats_offset_y_cells: float = 0         # 统计信息相对版面底部的Y偏移（格子数，正值向上）

# 高度显示配置
@export var height_display_enabled: bool = true       # 是否启用高度显示
@export var height_text_color: Color = Color.WHITE    # 高度文字颜色
@export var height_text_outline_color: Color = Color.BLACK  # 高度文字描边颜色
@export var height_font_size_ratio: float = 0.5       # 高度字体大小比例（相对于cell_size）
@export var height_display_offset_y_cells: float = 0.5   # 高度显示相对版面的Y偏移（格子数，正值向下）

# 阶段进度条配置
@export var stage_progress_bar_enabled: bool = true       # 是否启用阶段进度条
@export var stage_progress_bar_width_cells: float = 8.0   # 进度条宽度（格子数）
@export var stage_progress_bar_height_cells: float = 0.4  # 进度条高度（格子数）
@export var stage_progress_bar_border_color: Color = Color.WHITE     # 进度条边框颜色
@export var stage_progress_bar_fill_color: Color = Color(0.2, 0.6, 1.0, 1.0)  # 进度条填充颜色（蓝色）
@export var stage_progress_bar_bg_color: Color = Color(0.2, 0.2, 0.2, 0.6)    # 进度条背景颜色

# Hold方块显示配置
@export var hold_display_enabled: bool = true         # 是否启用Hold显示
var no_hold: bool = false                             # NoHold模式：关闭Hold显示（由TowerController转发）
@export var hold_display_offset_cells: int = -5       # Hold框相对版面的X偏移（以格子数为单位，负值在左侧）
@export var hold_display_offset_y_cells: int = 0      # Hold框相对版面的Y偏移（以格子数为单位）
@export var hold_display_width: int = 4               # Hold显示区域的格子宽度
@export var hold_display_height: int = 4              # Hold显示区域的格子高度
@export var hold_background_color: Color = Color(0.1, 0.1, 0.1, 1.0)  # Hold框背景色
@export var hold_border_color: Color = Color.WHITE    # Hold框边框颜色
@export var hold_border_width: float = 2.0            # Hold框边框宽度
@export var hold_padding: float = 0.2                 # Hold框内边距（相对于格子大小的比例）

# Next方块显示配置
@export var next_display_enabled: bool = true         # 是否启用Next显示
@export var next_display_offset_cells: int = 10       # Next框相对版面的X偏移（以格子数为单位，正值在右侧）
@export var next_display_offset_y_cells: int = 0      # Next框相对版面的Y偏移（以格子数为单位）
@export var next_display_width: int = 4               # 每个Next显示区域的格子宽度
@export var next_display_height: int = 3              # 每个Next显示区域的格子高度
@export_range(1, 7) var next_count: int = 6          # 显示Next方块的数量（1-7）
@export var next_spacing_cells: int = 0               # Next方块之间的间距（以格子数为单位）
@export var next_background_color: Color = Color(0.1, 0.1, 0.1, 1.0)  # Next框背景色
@export var next_border_color: Color = Color.WHITE    # Next框边框颜色
@export var next_border_width: float = 1.0            # Next框边框宽度
@export var next_padding: float = 0.15                # Next框内边距（相对于格子大小的比例）
@export var next_label_text: String = "NEXT"          # Next标签文字
@export var next_label_color: Color = Color.WHITE     # Next标签颜色

# 外部数据引用
var board_data: Array = []               # 版面数据（用于存储每个格子的颜色/类型）
var show_grid_lines: bool = true         # 是否显示网格线

# 正在播放消行动画的行（行号，用于闪烁高亮提示）
var clearing_lines: Array = []

# Hold方块数据
var hold_piece_data: Array = []          # 暂存的方块矩阵
var hold_piece_color: Color = Color.WHITE  # 暂存的方块颜色

# Next方块数据
var next_pieces_data: Array = []         # Next方块数据列表 [{shape: Array, color: Color}]

# 影子方块数据（由TetrisController计算后提供）
var shadow_piece: Array = []             # 影子的形状矩阵
var shadow_position: Vector2i = Vector2i.ZERO  # 影子的位置（已经计算好的硬降位置）
var current_piece_color: Color = Color.WHITE  # 当前方块颜色（用于影子颜色）

# 统计数据（由外部更新）
var pps_value: float = 0.0               # 每秒方块数
var apm_value: float = 0.0               # 每分钟攻击数
var rpm_value: float = 0.0               # 每分钟接收攻击数

# 大攻击警告状态
var big_attack_warning_active: bool = false
var big_attack_warning_progress: float = 0.0  # 0→1 渐变进度

# 游戏结束状态
var is_game_over: bool = false

# 窗口尺寸追踪
var last_viewport_size: Vector2 = Vector2.ZERO

var tetris_invisible: int = 0                       # 0=关闭, 1=开启（放置的方块隐藏，垃圾行正常显示）
var visible_time_between: float = 10                 # 隐藏间隔时间（秒），每隔多久显示一次方块
var visible_show_time: float = 1                    # 显示持续时间（秒），方块显示多久后再次隐藏
var drop_visible_time: float = 1                    # 方块落下后渐变透明的耗时（秒），0=立即隐形

# 隐藏模式状态
var _is_visible_mode: bool = true                   # true=正在显示方块, false=方块隐藏
var _invisible_timer: Timer = null                  # 隐藏模式计时器

# 每个格子锁定的时间戳（用于drop_visible_time渐隐），0表示未锁定
var _cell_lock_times: Array = []                    # 与board_data同维度，存储Time.get_ticks_msec()

func _ready():
	_get_find_controller()
	_init_board_data()
	_update_board_position()
	
	# 连接窗口大小变化信号
	get_tree().root.size_changed.connect(_on_window_resized)
	
	# 连接大攻击警告信号
	if tower_controller:
		tower_controller.big_attack_warning_started.connect(_on_big_attack_warning_started)
		tower_controller.big_attack_warning_ended.connect(_on_big_attack_warning_ended)
	
	# 初始化隐藏模式
	_init_invisible_mode()

func _process(_delta):
	# 检查窗口是否被拉伸
	if auto_resize and get_viewport_rect().size != last_viewport_size:
		_on_window_resized()
	
	# 更新大攻击警告渐变进度
	if big_attack_warning_active and tower_controller:
		var timer = tower_controller.big_attack_delay_timer
		if timer and timer.wait_time > 0:
			big_attack_warning_progress = 1.0 - (timer.time_left / timer.wait_time)
			queue_redraw()

## 初始化隐藏模式（tetris_invisible）
func _init_invisible_mode():
	if tetris_invisible == 0:
		_is_visible_mode = true
		# 如果已有计时器则停止并移除
		if _invisible_timer:
			_invisible_timer.stop()
			_invisible_timer.queue_free()
			_invisible_timer = null
		return
	
	# tetris_invisible == 1：初始为隐藏状态
	_is_visible_mode = false
	
	# 如果计时器已存在，直接重置
	if _invisible_timer:
		_invisible_timer.stop()
		_invisible_timer.wait_time = visible_time_between
		_invisible_timer.start()
		return
	
	# 创建并启动计时器
	_invisible_timer = Timer.new()
	_invisible_timer.one_shot = true
	_invisible_timer.timeout.connect(_on_invisible_timer_timeout)
	add_child(_invisible_timer)
	_invisible_timer.wait_time = visible_time_between
	_invisible_timer.start()

## 隐藏模式计时器回调：切换显示/隐藏状态
func _on_invisible_timer_timeout():
	if tetris_invisible == 0:
		return
	
	if _is_visible_mode:
		# 当前在显示阶段 → 切换到隐藏，等待 visible_time_between 秒后再次显示
		_is_visible_mode = false
		_invisible_timer.wait_time = visible_time_between
	else:
		# 当前在隐藏阶段 → 切换到显示，持续 visible_show_time 秒后隐藏
		_is_visible_mode = true
		_invisible_timer.wait_time = visible_show_time
	
	_invisible_timer.start()
	queue_redraw()

func _get_find_controller():
	# 自动查找tetris_controller（如果未设置）
	if not tetris_controller:
		tetris_controller = get_node_or_null("../TetrisController")
	
	# 自动查找tower_controller（如果未设置）
	if not tower_controller:
		tower_controller = get_node_or_null("../../TowerController")

## 初始化版面数据
func _init_board_data():
	if garbage_line_controller:
		garbage_cap = garbage_line_controller.garbage_cap
	
	board_data.clear()
	_cell_lock_times.clear()
	for y in range(grid_max_height):
		var row: Array = []
		var time_row: Array = []
		for x in range(grid_width):
			row.append(null)  # null 表示空格子
			time_row.append(0)  # 0 表示未锁定
		board_data.append(row)
		_cell_lock_times.append(time_row)

## 更新版面位置和大小（自动居中）
func _update_board_position():
	if not auto_center:
		return
	
	var viewport_size = get_viewport_rect().size
	var board_width = grid_width * cell_size
	var board_height = grid_height * cell_size  # 使用可见高度计算显示尺寸
	
	# 计算居中位置
	offset_x = int((viewport_size.x - board_width) / 2)
	offset_y = int((viewport_size.y - board_height) / 2)
	
	# 应用边距（如果需要）
	if auto_resize:
		var margin = min(viewport_size.x, viewport_size.y) * margin_percentage
		offset_x = max(offset_x, margin)
		offset_y = max(offset_y, margin)
	
	queue_redraw()

## 自动调整格子大小以适配窗口
func _auto_adjust_cell_size():
	if not auto_resize:
		return
	
	var viewport_size = get_viewport_rect().size
	
	# 预留边距空间
	var margin = min(viewport_size.x, viewport_size.y) * margin_percentage
	var available_width = viewport_size.x - margin * 2
	var available_height = viewport_size.y - margin * 2
	
	# 计算理论格子大小（使用可见高度）
	var cell_size_by_width = available_width / grid_width
	var cell_size_by_height = available_height / grid_height
	
	# 取最小值以保证完整显示
	var new_cell_size = min(cell_size_by_width, cell_size_by_height)
	
	# 限制最小和最大格子大小（可选）
	new_cell_size = clamp(new_cell_size, 16, 64)
	
	# 只有变化时才更新
	if abs(new_cell_size - cell_size) > 0.1:
		cell_size = int(new_cell_size)
		_update_board_position()
		queue_redraw()

## 窗口大小改变时的回调
func _on_window_resized():
	last_viewport_size = get_viewport_rect().size
	
	if auto_resize:
		_auto_adjust_cell_size()
	elif auto_center:
		_update_board_position()
	
	queue_redraw()

## 设置某个格子的颜色
func set_cell_color(x: int, y: int, color):
	# 如果颜色为null，设置为null表示空格
	if color == null:
		color = null
	elif typeof(color) == TYPE_COLOR and color == Color.BLACK:
		color = null
	elif typeof(color) != TYPE_COLOR:
		color = null
	
	if _is_valid_position(x, y):
		board_data[y][x] = color
		# 记录锁定时间（非空格、非垃圾行）
		if color != null and not _is_garbage_color(color):
			_cell_lock_times[y][x] = Time.get_ticks_msec()
		elif color == null:
			_cell_lock_times[y][x] = 0
		queue_redraw()  # 请求重绘

## 获取某个格子的颜色
func get_cell_color(x: int, y: int) -> Variant:
	if _is_valid_position(x, y):
		return board_data[y][x]
	return null

## 清除所有格子
func clear_board():
	_init_board_data()
	queue_redraw()

## 检查坐标是否有效（使用最大高度）
func _is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_max_height

## 获取完整可玩行数（含上方出块区域）
func get_playable_height() -> int:
	return grid_height + above_visible_rows

## 将网格坐标转换为世界坐标（格子左上角）
## y为数据行索引，减去above_visible_rows后映射到可见区域
func cell_to_world(x: int, y: int) -> Vector2:
	return Vector2(offset_x + x * cell_size, offset_y + (y - above_visible_rows) * cell_size)

## 将世界坐标转换为网格坐标（返回数据行索引）
func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local_x = world_pos.x - offset_x
	var local_y = world_pos.y - offset_y
	var cell_x = floor(local_x / cell_size)
	var cell_y = floor(local_y / cell_size) + above_visible_rows
	return Vector2i(cell_x, cell_y)

## ========== 影子方块系统 ==========

## 更新影子方块数据（由TetrisController调用）
func update_shadow(piece: Array, piece_position: Vector2i, piece_color: Color = Color.WHITE):
	if piece.is_empty():
		shadow_piece = []
		shadow_position = Vector2i.ZERO
	else:
		shadow_piece = piece
		shadow_position = piece_position
		current_piece_color = piece_color
	queue_redraw()

## 清除影子
func clear_shadow():
	shadow_piece = []
	shadow_position = Vector2i.ZERO
	queue_redraw()

## 检查某个位置是否被当前方块占据
func _is_occupied_by_current_piece(board_x: int, board_y: int) -> bool:
	if not tetris_controller:
		return false
	
	var current_piece = tetris_controller.current_piece
	var current_pos = tetris_controller.current_position
	
	if current_piece.is_empty():
		return false
	
	for y in range(current_piece.size()):
		for x in range(current_piece[y].size()):
			if current_piece[y][x] == 1:
				var px = current_pos.x + x
				var py = current_pos.y + y
				if px == board_x and py == board_y:
					return true
	return false

## 获取影子颜色（当前方块颜色叠加透明度）
func _get_shadow_color() -> Color:
	if current_piece_color == Color.WHITE:
		# 如果没有当前方块颜色，使用默认深灰色
		return Color(0.3, 0.3, 0.3, shadow_opacity)
	
	var shadow_color = current_piece_color
	shadow_color.a = shadow_opacity
	return shadow_color

## 获取影子边框颜色
func _get_shadow_border_color() -> Color:
	if current_piece_color == Color.WHITE:
		return Color(0.5, 0.5, 0.5, shadow_border_opacity)
	
	var border_color = current_piece_color
	border_color.a = shadow_border_opacity
	return border_color

## 绘制影子方块（不绘制与当前方块重叠的部分）
func _draw_shadow():
	if not shadow_enabled:
		return
	
	if shadow_piece.is_empty():
		return
	
	var shadow_color = _get_shadow_color()
	var shadow_border_color = _get_shadow_border_color()
	
	# 遍历影子的每个格子
	for y in range(shadow_piece.size()):
		for x in range(shadow_piece[y].size()):
			if shadow_piece[y][x] == 1:
				var board_x = shadow_position.x + x
				var board_y = shadow_position.y + y
				
				# 只绘制在可见区域（含上方出块区域）内的影子
				if board_x < 0 or board_x >= grid_width or board_y < 0 or board_y >= grid_height + above_visible_rows:
					continue
				
				# 检查该位置是否被当前方块占据（本体与影子重叠）
				if _is_occupied_by_current_piece(board_x, board_y):
					continue
				
				# 检查该位置是否被其他已锁定的方块占据
				if board_data[board_y][board_x] != null:
					continue
				
				# 绘制影子格子
				var cell_rect = Rect2(cell_to_world(board_x, board_y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, shadow_color, true)
				# 绘制影子边框
				draw_rect(cell_rect, shadow_border_color, false, 1.0)

# ========== 网格绘制系统 ==========

## 绘制网格线（只绘制可见区域）
func _draw_grid_lines():
	if not show_grid_lines:
		return
	
	var width = grid_width * cell_size
	var height = grid_height * cell_size  # 只绘制可见高度
	
	# 绘制垂直线（跳过x=0和x=grid_width，由白色版边边框覆盖）
	for x in range(1, grid_width):
		var start_pos = Vector2(offset_x + x * cell_size, offset_y)
		var end_pos = Vector2(offset_x + x * cell_size, offset_y + height)
		draw_line(start_pos, end_pos, grid_line_color, grid_line_width)
	
	# 绘制水平线（只绘制可见高度，跳过y=0和y=grid_height）
	for y in range(1, grid_height):
		var start_pos = Vector2(offset_x, offset_y + y * cell_size)
		var end_pos = Vector2(offset_x + width, offset_y + y * cell_size)
		draw_line(start_pos, end_pos, grid_line_color, grid_line_width)

## 绘制所有格子（含可见区域上方的出块区域）
func _draw_cells():
	# 优先判断：不处于隐形模式 → 全部正常绘制
	if tetris_invisible != 1:
		for y in range(grid_height + above_visible_rows):
			for x in range(grid_width):
				var cell_color: Variant = board_data[y][x]
				if cell_color == null:
					continue
				var cell_rect := Rect2(cell_to_world(x, y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, cell_color as Color, true)
				draw_rect(cell_rect, grid_line_color, false, 1.0)
		return
	
	# 隐形模式（tetris_invisible == 1）
	var now := Time.get_ticks_msec()
	
	for y in range(grid_height + above_visible_rows):
		for x in range(grid_width):
			var cell_color: Variant = board_data[y][x]
			if cell_color == null:
				continue
			
			# 处于显示阶段 → 所有方块正常绘制
			if _is_visible_mode:
				var cell_rect := Rect2(cell_to_world(x, y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, cell_color as Color, true)
				draw_rect(cell_rect, grid_line_color, false, 1.0)
				continue
			
			# 隐藏阶段：手上控制的方块始终显示
			if _is_occupied_by_current_piece(x, y):
				var cell_rect := Rect2(cell_to_world(x, y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, cell_color as Color, true)
				draw_rect(cell_rect, grid_line_color, false, 1.0)
				continue
			
			# 隐藏阶段：垃圾行始终显示
			if _is_garbage_color(cell_color as Color):
				var cell_rect := Rect2(cell_to_world(x, y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, cell_color as Color, true)
				draw_rect(cell_rect, grid_line_color, false, 1.0)
				continue
			
			# 普通已锁定方块 → 渐隐逻辑（落块后的短暂现形）
			if drop_visible_time > 0.0:
				var elapsed: float = (now - int(_cell_lock_times[y][x])) / 1000.0
				var alpha: float = 1.0 - (elapsed / drop_visible_time)
				alpha = clamp(alpha, 0.0, 1.0)
				if alpha <= 0.0:
					continue  # 完全消失
				var draw_color: Color = cell_color as Color
				draw_color.a = alpha
				var cell_rect := Rect2(cell_to_world(x, y), Vector2(cell_size, cell_size))
				draw_rect(cell_rect, draw_color, true)
				draw_rect(cell_rect, grid_line_color, false, 1.0)
			else:
				# drop_visible_time == 0：落下即隐形
				continue

## 绘制消行动画高亮：对正在清除的行做白色闪烁提示
func _draw_clearing_lines():
	if clearing_lines.is_empty():
		return
	var now := Time.get_ticks_msec()
	var alpha := 0.45 + 0.35 * (0.5 + 0.5 * sin(now / 90.0))
	for y in clearing_lines:
		var rect := Rect2(cell_to_world(0, y), Vector2(grid_width * cell_size, cell_size))
		draw_rect(rect, Color(1, 1, 1, alpha), true)

## 判断颜色是否为垃圾行颜色（垃圾行需要始终绘制）
func _is_garbage_color(color: Color) -> bool:
	if not garbage_line_controller:
		return false
	return (color == garbage_line_controller.garbage_color or 
			color == garbage_line_controller.buffered_garbage_color or 
			color == garbage_line_controller.solid_garbage_color)

## 绘制背景（只绘制可见区域）
func _draw_background():
	var background_rect = Rect2(offset_x, offset_y, 
		grid_width * cell_size, grid_height * cell_size)
	
	draw_rect(background_rect, background_color, true)

## 绘制版面左右边缘白线（只覆盖可见区域）
func _draw_board_border():
	var board_width_px = grid_width * cell_size
	var board_height_px = grid_height * cell_size
	var board_left = offset_x
	var board_right = offset_x + board_width_px
	var board_top = offset_y
	var board_bottom = offset_y + board_height_px
	
	# 左边缘白线
	draw_line(Vector2(board_left, board_top), Vector2(board_left, board_bottom), board_border_color, board_border_width)
	
	# 右边缘白线
	draw_line(Vector2(board_right, board_top), Vector2(board_right, board_bottom), board_border_color, board_border_width)

# ========== 垃圾槽显示系统 ==========

## 获取垃圾槽的位置（在Hold框和版面之间）
func _get_garbage_slot_position() -> Rect2:
	var slot_x = offset_x + hold_display_offset_cells * cell_size + hold_display_width * cell_size
	var slot_width = garbage_slot_width * cell_size
	var slot_height = grid_height * cell_size  # 与可见版面同高
	var slot_y = offset_y  # 与版面顶部对齐
	
	return Rect2(slot_x, slot_y, slot_width, slot_height)

## 绘制垃圾槽
func _draw_garbage_slot():
	if not garbage_slot_enabled:
		return
	
	var slot_rect = _get_garbage_slot_position()
	
	# 绘制黑色背景
	draw_rect(slot_rect, Color.BLACK, true)
	
	# 绘制边框（白色边框）
	draw_rect(slot_rect, garbage_slot_border_color, false, garbage_slot_border_width)
	
	# 绘制垃圾行矩形（从garbage_line_controller获取数据）
	_draw_garbage_bars(slot_rect)
	
	# 绘制 garbage_cap 横线（从下往上数第 garbage_cap 行）
	if garbage_cap > 0 and garbage_cap < grid_height:
		var gap_y = slot_rect.position.y + (grid_height - garbage_cap) * cell_size
		var line_start = Vector2(slot_rect.position.x, gap_y)
		var line_end = Vector2(slot_rect.position.x + slot_rect.size.x, gap_y)
		draw_line(line_start, line_end, garbage_cap_line_color, 1.0)

## 绘制垃圾行矩形（包括正常和缓冲）
func _draw_garbage_bars(slot_rect: Rect2):
	if not garbage_line_controller:
		return
	
	# 获取正常队列和缓冲队列数据
	var enter_queue = garbage_line_controller.get_enter_queue()
	var buffer_queue = garbage_line_controller.get_buffer_queue()
	
	if enter_queue.is_empty() and buffer_queue.is_empty():
		return
	
	# 计算绘制参数
	var bar_width = slot_rect.size.x - garbage_bar_padding * cell_size * 2
	var padding_x = slot_rect.position.x + garbage_bar_padding * cell_size
	
	# 从底部开始绘制
	var current_bottom = slot_rect.position.y + slot_rect.size.y
	
	# 先绘制正常队列（索引 0 在底部，最先出）
	for i in range(enter_queue.size()):
		var entry = enter_queue[i]
		var row_count = entry["count"] if typeof(entry) == TYPE_DICTIONARY else entry
		var bar_height = row_count * cell_size - garbage_bar_padding * cell_size * 1
		
		if bar_height <= 0:
			bar_height = cell_size * 0.5
		
		var bar_y = current_bottom - bar_height - garbage_bar_padding * cell_size
		var bar_rect = Rect2(padding_x, bar_y, bar_width, bar_height)
		
		# 正常垃圾使用红色
		draw_rect(bar_rect, garbage_bar_color, true)
		var border_color = Color(1.0, 0.3, 0.3, 1.0)
		draw_rect(bar_rect, border_color, false, 1.0)
		
		if i > 0:
			var separator_y = bar_y - garbage_bar_padding * cell_size
			var line_start = Vector2(slot_rect.position.x + garbage_bar_padding * cell_size, separator_y)
			var line_end = Vector2(slot_rect.position.x + slot_rect.size.x - garbage_bar_padding * cell_size, separator_y)
			draw_line(line_start, line_end, garbage_bar_separator_color, garbage_bar_separator_width)
		
		current_bottom = bar_y
	
	# 再绘制缓冲队列（在正常队列上方）
	# 正向遍历：索引 0（最早加入、计时最短）在底部，索引末尾（最新加入）在上方
	for i in range(buffer_queue.size()):
		var entry = buffer_queue[i]
		var row_count = entry["count"]
		var bar_height = row_count * cell_size - garbage_bar_padding * cell_size * 1
		
		if bar_height <= 0:
			bar_height = cell_size * 0.5
		
		var bar_y = current_bottom - bar_height - garbage_bar_padding * cell_size
		var bar_rect = Rect2(padding_x, bar_y, bar_width, bar_height)
		
		# 缓冲垃圾使用半透明暗红色
		var buffered_color = Color(0.5, 0.0, 0.0, 0.7)
		draw_rect(bar_rect, buffered_color, true)
		var border_color = Color(0.7, 0.0, 0.0, 0.8)
		draw_rect(bar_rect, border_color, false, 1.0)
		
		# 显示缓冲倒计时（可选）
		var timer = entry.get("timer", 0.0)
		var timer_text = "%.1fs" % timer
		var font_size = cell_size * 0.3
		var text_pos = Vector2(
			slot_rect.position.x + slot_rect.size.x * 0.5,
			bar_y + bar_height * 0.5 - font_size * 0.5
		)
		_draw_label(text_pos.x, text_pos.y, timer_text, Color.WHITE, font_size)
		
		if i > 0:
			var separator_y = bar_y - garbage_bar_padding * cell_size
			var line_start = Vector2(slot_rect.position.x + garbage_bar_padding * cell_size, separator_y)
			var line_end = Vector2(slot_rect.position.x + slot_rect.size.x - garbage_bar_padding * cell_size, separator_y)
			draw_line(line_start, line_end, garbage_bar_separator_color, garbage_bar_separator_width)
		
		current_bottom = bar_y

# ========== 统计信息显示系统 ==========

## 更新统计数据
func update_stats(pps: float, apm: float, rpm: float):
	pps_value = pps
	apm_value = apm
	rpm_value = rpm
	queue_redraw()

## 绘制统计信息（在垃圾槽左侧）
func _draw_stats():
	if not stats_display_enabled:
		return
	
	var slot_rect = _get_garbage_slot_position()
	var font_size = cell_size * stats_font_size_ratio
	var _font = ThemeDB.fallback_font
	
	# 计算文字位置（在垃圾槽左侧，右对齐）
	var text_x = slot_rect.position.x + stats_offset_x_cells * cell_size
	var text_y_base = slot_rect.position.y + slot_rect.size.y - stats_offset_y_cells * cell_size  # 从底部向上偏移
	
	# 三行文字
	var stats_lines = [
		"PPS %.2f/s" % [pps_value],  # PPS X.XX/s
		"APM %.2f/m" % [apm_value],  # APM X.XX/m
		"RPM %.2f/m" % [rpm_value]   # RPM X.XX/m
	]
	
	var line_spacing = cell_size * stats_spacing_cells
	
	# 从底部向上绘制
	for i in range(stats_lines.size() - 1, -1, -1):
		var line_y = text_y_base - (stats_lines.size() - 1 - i) * line_spacing - font_size * 0.5
		var text_position = Vector2(text_x, line_y)
		_draw_text_with_outline(text_position, stats_lines[i], stats_text_color, 
			stats_text_outline_color, font_size, HORIZONTAL_ALIGNMENT_RIGHT)

# ========== 高度显示系统 ==========

## 绘制高度显示（在版面下侧居中）
func _draw_height_display():
	if not height_display_enabled:
		return
	if not tower_controller:
		return
	
	var font_size = cell_size * height_font_size_ratio
	
	# 计算位置（版面底部中央）
	var board_center_x = offset_x + grid_width * cell_size * 0.5
	var board_bottom_y = offset_y + grid_height * cell_size
	
	var offset_y_pixels = height_display_offset_y_cells * cell_size
	
	# 第一行：高度（居中）
	var text_pos = Vector2(board_center_x, board_bottom_y + offset_y_pixels)
	var height_text = "%.2fm" % tower_controller.tower_meter
	_draw_text_with_outline(text_pos, height_text, height_text_color, 
		height_text_outline_color, font_size, HORIZONTAL_ALIGNMENT_CENTER)
	
	# 第二行：速度（在高度文字下方，居中）
	var speed_text = "%.2f/s" % tower_controller.tower_speed_meter
	var speed_pos = Vector2(board_center_x, text_pos.y + font_size * 1.2)
	_draw_text_with_outline(speed_pos, speed_text, height_text_color, 
		height_text_outline_color, font_size * 0.8, HORIZONTAL_ALIGNMENT_CENTER)
	
	# 第三行：阶段进度条（在速度文字下方，居中）
	_draw_stage_progress_bar(board_center_x, speed_pos.y + font_size * 0.8)

## 绘制阶段进度条
func _draw_stage_progress_bar(center_x: float, top_y: float):
	if not stage_progress_bar_enabled:
		return
	if not tower_controller:
		return
	
	# 计算进度（当前米数在当前阶段门槛到下一阶段门槛之间的百分比）
	var floor_array = TowerController.FLOOR_HIGHER
	var stage = tower_controller.current_stage
	var current_floor = floor_array[stage] if stage < floor_array.size() else floor_array[-1]
	var next_floor = floor_array[stage + 1] if stage + 1 < floor_array.size() else current_floor
	
	var progress: float = 1.0
	if next_floor > current_floor:
		progress = (tower_controller.tower_meter - current_floor) / (next_floor - current_floor)
		progress = clampf(progress, 0.0, 1.0)
	
	var bar_width = stage_progress_bar_width_cells * cell_size
	var bar_height = stage_progress_bar_height_cells * cell_size
	
	var bar_top_left = Vector2(center_x - bar_width * 0.5, top_y)
	var bar_rect = Rect2(bar_top_left, Vector2(bar_width, bar_height))
	
	# 背景
	draw_rect(bar_rect, stage_progress_bar_bg_color, true)
	
	# 填充部分
	if progress > 0.0:
		var fill_width = bar_width * progress
		var fill_rect = Rect2(bar_top_left, Vector2(fill_width, bar_height))
		draw_rect(fill_rect, stage_progress_bar_fill_color, true)
	
	# 边框
	draw_rect(bar_rect, stage_progress_bar_border_color, false, 1.0)

# ========== 大攻击警告信号响应 ==========

func _on_big_attack_warning_started():
	big_attack_warning_active = true
	big_attack_warning_progress = 0.0

func _on_big_attack_warning_ended():
	big_attack_warning_active = false
	big_attack_warning_progress = 0.0
	queue_redraw()

# ========== Hold方块显示系统 ==========

## 设置Hold显示的方块
func set_hold_piece(piece: Array, color: Color):
	hold_piece_data = piece
	hold_piece_color = color
	queue_redraw()

## 清除Hold显示
func clear_hold_piece():
	hold_piece_data = []
	hold_piece_color = Color.WHITE
	queue_redraw()

## 计算Hold框的位置（基于当前cell_size）
func _get_hold_position() -> Vector2:
	var hold_offset_x = hold_display_offset_cells * cell_size
	var hold_offset_y = hold_display_offset_y_cells * cell_size
	return Vector2(offset_x + hold_offset_x, offset_y + hold_offset_y)

## 绘制Hold方块区域
func _draw_hold_display():
	if not hold_display_enabled:
		return
	# NoHold模式：关闭Hold显示
	if no_hold:
		return
	
	# 计算Hold框的位置（基于当前cell_size）
	var hold_pos = _get_hold_position()
	var hold_x = hold_pos.x
	var hold_y = hold_pos.y
	
	# 计算Hold框的大小（使用当前cell_size）
	var hold_width = hold_display_width * cell_size
	var hold_height = hold_display_height * cell_size
	
	# 绘制背景
	var hold_rect = Rect2(hold_x, hold_y, hold_width, hold_height)
	draw_rect(hold_rect, hold_background_color, true)
	
	# 绘制边框
	draw_rect(hold_rect, hold_border_color, false, hold_border_width)
	
	# 绘制"HOLD"标签
	_draw_label(hold_x, hold_y - cell_size * 0.5, "HOLD", hold_border_color, cell_size * 0.4)
	
	# 如果有方块数据，绘制方块
	if not hold_piece_data.is_empty():
		# 计算内边距
		var padding_x = hold_width * hold_padding
		var padding_y = hold_height * hold_padding
		
		# 计算实际绘制区域（去掉内边距）
		var draw_area_x = hold_x + padding_x
		var draw_area_y = hold_y + padding_y
		var draw_area_width = hold_width - padding_x * 2
		var draw_area_height = hold_height - padding_y * 2
		
		_draw_piece_in_area(hold_piece_data, hold_piece_color, 
			draw_area_x, draw_area_y, draw_area_width, draw_area_height)

# ========== Next方块显示系统 ==========

## 设置Next显示的方块列表
func set_next_pieces(pieces: Array):
	# pieces: [{shape: Array, color: Color}, ...]
	next_pieces_data = pieces
	queue_redraw()

## 清除Next显示
func clear_next_pieces():
	next_pieces_data = []
	queue_redraw()

## 计算Next框的位置（基于当前cell_size）
func _get_next_position(index: int) -> Vector2:
	var next_offset_x = next_display_offset_cells * cell_size
	var next_offset_y = next_display_offset_y_cells * cell_size + index * (next_display_height + next_spacing_cells) * cell_size
	return Vector2(offset_x + next_offset_x, offset_y + next_offset_y)

## 绘制Next方块区域
func _draw_next_display():
	if not next_display_enabled:
		return
	
	if next_pieces_data.is_empty():
		return
	
	# 限制显示的Next数量
	var display_count = min(next_count, next_pieces_data.size())
	
	for i in range(display_count):
		var piece_data = next_pieces_data[i]
		var shape = piece_data["shape"]
		var color = piece_data["color"]
		
		# 计算Next框的位置
		var next_pos = _get_next_position(i)
		var next_x = next_pos.x
		var next_y = next_pos.y
		
		# 计算Next框的大小
		var next_width = next_display_width * cell_size
		var next_height = next_display_height * cell_size
		
		# 绘制背景
		var next_rect = Rect2(next_x, next_y, next_width, next_height)
		draw_rect(next_rect, next_background_color, true)
		
		# 绘制边框
		draw_rect(next_rect, next_border_color, false, next_border_width)
		
		# 绘制"NEXT"标签（只对第一个显示）
		if i == 0:
			_draw_label(next_x, next_y - cell_size * 0.5, next_label_text, next_label_color, cell_size * 0.4)
		
		# 绘制方块（如果有）
		if not shape.is_empty():
			# 计算内边距
			var padding_x = next_width * next_padding
			var padding_y = next_height * next_padding
			
			# 计算实际绘制区域（去掉内边距）
			var draw_area_x = next_x + padding_x
			var draw_area_y = next_y + padding_y
			var draw_area_width = next_width - padding_x * 2
			var draw_area_height = next_height - padding_y * 2
			
			_draw_piece_in_area(shape, color, 
				draw_area_x, draw_area_y, draw_area_width, draw_area_height)

## 查找版面中最高（y最小）的非空方块（排除正在控制的方块）
func _get_highest_block_y() -> int:
	# 获取当前控制方块所占格子集合
	var current_cells := {}
	if tetris_controller:
		var piece = tetris_controller.current_piece
		var pos = tetris_controller.current_position
		if piece and pos:
			for py in range(piece.size()):
				for px in range(piece[py].size()):
					if piece[py][px] == 1:
						var bx = pos.x + px
						var by = pos.y + py
						current_cells[Vector2i(bx, by)] = true
	
	var playable_height = min(grid_height + above_visible_rows, board_data.size())
	for y in range(playable_height):
		for x in range(grid_width):
			if board_data[y][x] != null and not current_cells.has(Vector2i(x, y)):
				return y
	return -1  # 没有方块

## 绘制大攻击警告：在最高方块上侧边缘划横线+朝上箭头
func _draw_big_attack_warning():
	if not big_attack_warning_active or big_attack_warning_progress <= 0.0:
		return
	
	var highest_y = _get_highest_block_y()
	if highest_y < 0:
		return
	
	# warning_alpha 随进度从 0.3 渐变到 1.0
	var warning_alpha: float = 0.3 + 0.7 * big_attack_warning_progress
	var warning_color: Color = Color(1.0, 0.0, 0.0, warning_alpha * 0.6)
	
	var board_left = offset_x
	var board_right = offset_x + grid_width * cell_size
	var board_width_px = board_right - board_left
	
	# 计算最高方块上侧边缘的世界坐标
	var line_y = cell_to_world(0, highest_y).y  # 该行格子顶部
	
	# 绘制半透明横线（与版面同样宽）
	draw_line(Vector2(board_left, line_y), Vector2(board_right, line_y), warning_color, 2.0)
	
	# 在上方绘制4个朝上半透明箭头
	var arrow_count = 4
	var arrow_width = cell_size * 0.5          # 箭头底部宽度
	var arrow_height = cell_size * 0.6         # 箭头高度
	var arrow_spacing = 1.0 * board_width_px / (arrow_count + 1)  # 等间距
	var arrow_alpha: float = 0.4 + 0.6 * big_attack_warning_progress
	var arrow_color: Color = Color(1.0, 0.0, 0.0, arrow_alpha * 0.7)
	
	for i in range(arrow_count):
		var center_x = board_left + arrow_spacing * (i + 1)
		var arrow_top_y = line_y - arrow_height  # 箭头尖端（在上方）
		var arrow_bottom_y = line_y               # 箭头底部（在横线上）
		
		# 三角箭头：尖端在上，底部两个点等分
		var tip = Vector2(center_x, arrow_top_y)
		var left_bottom = Vector2(center_x - arrow_width * 0.5, arrow_bottom_y)
		var right_bottom = Vector2(center_x + arrow_width * 0.5, arrow_bottom_y)
		
		draw_polygon([tip, left_bottom, right_bottom], [arrow_color])

## 绘制游戏结束暗幕（半透明黑色覆盖版面区域）
func _draw_death_overlay():
	if not is_game_over:
		return
	
	# 覆盖版面区域 + 垃圾槽 + Hold/Next区域
	var board_left = offset_x + hold_display_offset_cells * cell_size
	var board_top = offset_y
	var board_right = offset_x + (grid_width + next_display_offset_cells + next_display_width) * cell_size
	var board_bottom = offset_y + grid_height * cell_size
	
	var overlay_rect = Rect2(board_left, board_top, board_right - board_left, board_bottom - board_top)
	var overlay_color = Color(0, 0, 0, 0.7)
	draw_rect(overlay_rect, overlay_color, true)

# ========== 通用绘制工具 ==========

## 在指定区域绘制方块（自动缩放）
func _draw_piece_in_area(piece: Array, color: Color, area_x: float, area_y: float, 
	area_width: float, area_height: float):
	
	# 计算方块的实际尺寸
	var piece_width = piece[0].size()
	var piece_height = piece.size()
	
	# 计算适合区域的最大格子大小
	var cell_size_x = area_width / piece_width
	var cell_size_y = area_height / piece_height
	var draw_cell_size = min(cell_size_x, cell_size_y)
	
	# 计算居中偏移
	var total_width = piece_width * draw_cell_size
	var total_height = piece_height * draw_cell_size
	var start_x = area_x + (area_width - total_width) / 2
	var start_y = area_y + (area_height - total_height) / 2
	
	# 绘制每个方块
	for y in range(piece_height):
		for x in range(piece_width):
			if piece[y][x] == 1:
				var rect = Rect2(
					start_x + x * draw_cell_size,
					start_y + y * draw_cell_size,
					draw_cell_size,
					draw_cell_size
				)
				draw_rect(rect, color, true)
				# 添加边框
				draw_rect(rect, Color.WHITE, false, 1.0)

## 绘制文本标签
func _draw_label(x: float, y: float, text: String, color: Color, font_size: float):
	var label_pos = Vector2(x, y)
	# 使用draw_string绘制文本
	var font = ThemeDB.fallback_font
	var font_size_int = max(1, int(font_size))
	draw_string(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int, color)

## 绘制带描边的文本（支持对齐方式）
func _draw_text_with_outline(text_position: Vector2, text: String, color: Color, outline_color: Color, font_size: float, alignment: int = HORIZONTAL_ALIGNMENT_CENTER):
	var font = ThemeDB.fallback_font
	var font_size_int = max(1, int(font_size))
	
	# 绘制描边（偏移4个方向）
	var outline_offsets = [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
	]
	
	for offset in outline_offsets:
		var outline_pos = text_position + offset
		draw_string(font, outline_pos, text, alignment, -1, font_size_int, outline_color)
	
	# 绘制主文本
	draw_string(font, text_position, text, alignment, -1, font_size_int, color)

func _draw():
	# 1. 绘制背景
	_draw_background()
	
	# 2. 绘制所有格子
	_draw_cells()
	
	# 2.5 绘制消行动画高亮（正在清除的行闪烁提示）
	_draw_clearing_lines()
	
	# 3. 绘制影子方块
	_draw_shadow()
	
	# 4. 绘制垃圾槽
	_draw_garbage_slot()
	
	# 5. 绘制Hold方块区域
	_draw_hold_display()
	
	# 6. 绘制Next方块区域
	_draw_next_display()
	
	# 7. 绘制大攻击警告条（在最高方块上侧边缘）
	_draw_big_attack_warning()
	
	# 8. 绘制统计信息
	_draw_stats()
	
	# 9. 绘制高度显示
	_draw_height_display()
	
	# 10. 绘制网格线
	_draw_grid_lines()
	
	# 12. 绘制版面左右边缘白线（最上层，确保不被网格线或格子描边覆盖）
	_draw_board_border()
	
	# 13. 游戏结束暗幕（最上层）
	_draw_death_overlay()

## 获取消行控制器的引用
func set_clear_line_controller(controller: TetrisClearLine):
	clear_line_controller = controller

## 设置正在播放消行动画的行（行号），用于闪烁高亮提示
func set_clearing_lines(lines: Array) -> void:
	clearing_lines = lines.duplicate()
	queue_redraw()

## 清除消行动画高亮
func clear_clearing_lines() -> void:
	clearing_lines.clear()
	queue_redraw()

## 更新网格尺寸（动态调整）
func resize_grid(new_width: int, new_height: int, new_max_height: int = -1):
	grid_width = new_width
	grid_height = new_height
	if new_max_height > 0:
		grid_max_height = new_max_height
	_init_board_data()
	
	if auto_resize:
		_auto_adjust_cell_size()
	elif auto_center:
		_update_board_position()
	
	queue_redraw()

## 手动设置格子大小（会覆盖自动调整）
func set_cell_size(new_size: int, preserve_center: bool = true):
	cell_size = new_size
	
	if preserve_center and auto_center:
		_update_board_position()
	
	queue_redraw()

## 设置基准点（手动模式）
func set_offset(new_x: int, new_y: int):
	offset_x = new_x
	offset_y = new_y
	auto_center = false  # 手动设置后禁用自动居中
	queue_redraw()

## 启用/禁用自动居中
func set_auto_center(enabled: bool):
	auto_center = enabled
	if enabled:
		_update_board_position()
		queue_redraw()

## 获取版面的实际边界矩形
func get_board_rect() -> Rect2:
	return Rect2(offset_x, offset_y, 
		grid_width * cell_size, grid_height * cell_size)
