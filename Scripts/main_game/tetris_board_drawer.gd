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
@export var garbage_bar_buffer_color: Color = Color(0.5, 0.0, 0.0, 0.35)  # 缓冲中垃圾的底色（半透明）
@export var garbage_bar_buffer_fill_color: Color = Color.RED               # 缓冲进度填充色（不透明，自下上涨满=缓冲结束）
@export var garbage_bar_buffer_border_color: Color = Color(0.7, 0.0, 0.0, 0.8)  # 缓冲中垃圾的边框色
@export var garbage_bar_separator_color: Color = Color.BLACK  # 垃圾行分割线颜色
@export var garbage_bar_separator_width: float = 1.0  # 分割线宽度
@export var garbage_bar_padding: float = 0.1          # 垃圾矩形内边距（相对于格子大小的比例）

# 统计信息配置
@export var stats_display_enabled: bool = true        # 是否启用统计信息显示
@export var stats_text_color: Color = Color.WHITE     # 统计信息文字颜色
@export var stats_text_outline_color: Color = Color.BLACK  # 统计信息文字描边颜色
@export var stats_font_size_ratio: float = 0.7        # 统计信息字体大小比例（相对于cell_size）
@export var stats_spacing_cells: float = 1          # 统计信息行间距（格子数）

# 速条（PPM / APM 短期计速）配置 —— 预留功能，默认不显示
# 位置在统计文本块最上面一行（TIME）的上方：蓝色 = PPM，橙色 = 短期 APM，
# 数值与 RPM 同口径（最近 60s 滚动窗口）；超过上限显示满格（不溢出），低于下限显示为空。
@export var speed_bars_enabled: bool = false        # 是否显示（默认关闭，预留）
@export var speed_bar_width_ratio: float = 0.32     # 条宽（相对 cell_size，较细）
@export var speed_bar_height_cells: float = 3.5     # 条最大高度（格子数，较短）
@export var speed_bar_gap_ratio: float = 0.35       # 两条之间的基础间距（相对 cell_size）
@export var speed_bar_gap_px: float = 10.0          # 两条之间额外增加的间距（像素）
@export var speed_bars_offset_y_cells: float = 0.5  # 条底边与 TIME 行之间的额外间距（格子数）
@export var speed_bars_offset_x_px: float = 75.0    # 在右对齐基础上再右移的像素（正=右）
@export var speed_bars_offset_y_px: float = 10.0    # 在 offset_y_cells 基础上再上移的像素（正=上）
@export var speed_bar_show_value: bool = true       # 条顶是否写当前数值（四舍五入取整）
@export var speed_bar_value_font_ratio: float = 0.5 # 条顶数字字号（相对 cell_size）
@export var speed_bar_value_gap_px: float = 4.0     # 条顶数字与条顶部之间的间距（像素）
@export var speed_bar_bg_color: Color = Color(0.0, 0.0, 0.0, 0.85)   # 黑底（显示 0~上限的整个范围）
@export var speed_bar_border_color: Color = Color.WHITE              # 白边框（满格时也能看清边界）
@export var speed_bar_border_width: float = 1.0     # 白边框线宽
@export var speed_bar_ppm_color: Color = Color(0.25, 0.6, 1.0)   # 蓝色：PPM
@export var speed_bar_apm_color: Color = Color(1.0, 0.55, 0.15)  # 橙色：APM
@export var speed_bar_ppm_min: float = 0.0          # 蓝条下限（低于=空）
@export var speed_bar_ppm_max: float = 300.0        # 蓝条上限（超过=满格，不溢出）
@export var speed_bar_apm_min: float = 0.0          # 橙条下限（低于=空）
@export var speed_bar_apm_max: float = 500.0        # 橙条上限（超过=满格，不溢出）
@export var stats_offset_x_cells: float = -5      # 统计信息相对垃圾槽左侧的X偏移（格子数，负值向左）
@export var stats_offset_y_cells: float = 0         # 统计信息相对版面底部的Y偏移（格子数，正值向上）

# 高度显示配置
@export var height_display_enabled: bool = true       # 是否启用高度显示
@export var height_text_color: Color = Color.WHITE    # 高度文字颜色
@export var height_text_outline_color: Color = Color.BLACK  # 高度文字描边颜色
@export var height_font_size_ratio: float = 0.8       # 高度字体大小比例（相对于cell_size）
@export var height_display_offset_y_cells: float = 1.1   # 高度显示整体（米数→进度条→速度）相对版面底部的Y偏移（格子数，正值向下；字体放大后同步下移，避免压住版面最后一行）

# 阶段进度条配置
@export var stage_progress_bar_enabled: bool = true       # 是否启用阶段进度条
@export var stage_progress_bar_width_cells: float = 8.0   # 进度条宽度（格子数）
@export var stage_progress_bar_height_cells: float = 0.4  # 进度条高度（格子数）
@export var stage_progress_bar_border_color: Color = Color.WHITE     # 进度条边框颜色
@export var stage_progress_bar_fill_color: Color = Color(0.2, 0.6, 1.0, 1.0)  # 进度条填充颜色（蓝色）
@export var stage_progress_bar_bg_color: Color = Color(0.2, 0.2, 0.2, 0.6)    # 进度条背景颜色

# 右下角「塔速度表」（同心圆 + 白色指针 + 圆心写速度数字）配置
@export var speed_gauge_enabled: bool = true          # 是否显示速度表
@export var speed_gauge_radius_cells: float = 1.0     # 外圆半径（格子数）
@export var speed_gauge_margin_cells: float = 1.0     # 与 Next 列底部之间的间距（格子数）
@export var speed_gauge_border_color: Color = Color.WHITE   # 圆边框颜色（白）
@export var speed_gauge_border_width: float = 2.0     # 外圆线宽
@export var speed_gauge_inner_ratio: float = 0.78     # 内圈半径比例（同心圆；0=不画内圈）
@export var speed_gauge_inner_width: float = 1.0      # 内圈线宽
@export var speed_gauge_needle_color: Color = Color.WHITE   # 指针颜色（白）
@export var speed_gauge_needle_width: float = 2.0     # 指针线宽
@export var speed_gauge_needle_length_ratio: float = 0.86   # 指针长度（相对半径）
@export var speed_gauge_min: float = 0.0              # 指针量程下限（起点：下偏右 30°）
@export var speed_gauge_max: float = 20.0             # 指针量程上限（终点：下偏左 30°；超过只数字继续涨，指针到极限）
@export var speed_gauge_start_deg: float = -30.0      # 指针起点角度：相对「正下方」的偏角，负=偏右（-30 = 下偏右 30°）
@export var speed_gauge_sweep_deg: float = -300.0     # 指针扫过总角度：负 = 逆时针（默认 -300°：右下→右上→正上→左上→左下）
@export var speed_gauge_text_format: String = "%.1f"        # 圆心数字格式（保留一位小数）
@export var speed_gauge_text_font_ratio: float = 0.55 # 圆心字号（相对半径）
@export var speed_gauge_text_offset_ratio: float = 0.24  # 数字相对圆心向上偏移（相对半径；0=正中心）
@export var speed_gauge_smooth_rate: float = 6.0      # 指针缓动速率（/秒）：越大越快追上；0=不平滑直接跟随
@export var speed_gauge_text_color: Color = Color.WHITE       # 圆心数字颜色
@export var speed_gauge_text_outline_color: Color = Color.BLACK  # 圆心数字描边

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

# Hold / Next 预览里「方块格子」的统一大小基准（所有方块共用同一套，避免 O 特别大、I 特别小）
#   参考占位范围 4×2 = 所有俄罗斯方块的最大占位（I 长 4，其余最高 2）
#   格子大小 = min(可用宽 / 4, 可用高 / 2)，再按各自实际占位包围盒居中
@export var preview_ref_width: int = 4                # 预览统一格子大小的参考宽度（格数）
@export var preview_ref_height: int = 2               # 预览统一格子大小的参考高度（格数）
@export var hold_preview_scale: float = 1.4           # Hold 预览放大倍数（Hold 框富余大，画大一点；仍不会出框）
@export var next_preview_scale: float = 1.0           # Next 预览放大倍数
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

## 全局指标（整局累计平均）—— 左侧 PPS / APM 两行文本用的就是这两个，保持原样不要改成窗口值：
##   pps_value：总落块数 ÷ 游戏时长（pieces per second，全局均值）
##   apm_value：总攻击量 ÷ 游戏时长 × 60（attack per minute，全局均值）
var pps_value: float = 0.0               # 每秒方块数（全局）
var apm_value: float = 0.0               # 每分钟攻击数（全局）

## 短期指标（最近 60s 滚动窗口）—— 与全局的 pps/apm 相互独立：
##   rpm_value        每分钟【接收】攻击数（左侧 RPM 行）
##   ppm_value        每分钟落块数（速条：蓝色）
##   apm_window_value 每分钟【打出】攻击数（速条：橙色）
var rpm_value: float = 0.0               # 每分钟接收攻击数（最近 60s 滚动窗口）
var ppm_value: float = 0.0               # 每分钟落块数（最近 60s 滚动窗口）
var apm_window_value: float = 0.0        # 每分钟攻击数（最近 60s 滚动窗口）

# 速度表显示值（缓动后的塔速度；指针与中心数字都用它，保证两者一致）
var _speed_gauge_displayed: float = 0.0
var _speed_gauge_initialized: bool = false

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
	
	# 速度表指针缓动（塔速度是「每次消行瞬间加一截」的离散变化，直接画会一跳一跳）
	_update_speed_gauge(_delta)

## 速度表显示值的缓动：指数逼近目标值 —— 起步快、越接近目标越慢（帧率无关）
## speed_gauge_smooth_rate <= 0 时不平滑，直接用真实速度。
func _update_speed_gauge(delta: float) -> void:
	if not speed_gauge_enabled or not tower_controller:
		return
	var target: float = tower_controller.tower_speed_meter
	if not _speed_gauge_initialized:
		# 首帧直接对齐，避免开局指针从 0 甩过去
		_speed_gauge_initialized = true
		_speed_gauge_displayed = target
		return
	if speed_gauge_smooth_rate <= 0.0:
		_speed_gauge_displayed = target
		return
	if is_equal_approx(_speed_gauge_displayed, target):
		return
	# 1 - exp(-rate*delta)：等效于「每帧把剩余差距按固定比例缩小」，delta 变化也不影响手感
	_speed_gauge_displayed = lerpf(_speed_gauge_displayed, target,
		1.0 - exp(-speed_gauge_smooth_rate * delta))
	if absf(_speed_gauge_displayed - target) < 0.001:
		_speed_gauge_displayed = target
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

## 规范化格子颜色：null / 非颜色 / 黑色 都视为空格
func _normalize_cell_color(color) -> Variant:
	if color == null:
		return null
	if typeof(color) == TYPE_COLOR and color == Color.BLACK:
		return null
	if typeof(color) != TYPE_COLOR:
		return null
	return color

## 设置某个格子的颜色
func set_cell_color(x: int, y: int, color):
	var c = _normalize_cell_color(color)
	
	if _is_valid_position(x, y):
		board_data[y][x] = c
		# 记录锁定时间（非空格、非垃圾行）
		if c != null and not _is_garbage_color(c):
			_cell_lock_times[y][x] = Time.get_ticks_msec()
		elif c == null:
			_cell_lock_times[y][x] = 0
		queue_redraw()  # 请求重绘

## 设置格子颜色，并显式指定锁定时间戳（不按「刚刚落下」刷新）。
## 专供「整版位移」类操作使用（消行下移、垃圾行/Allspin 上涨）：
## 这些操作只是把已有格子搬到新行，若走 set_cell_color()，时间戳会被刷成「刚刚落下」，
## 隐形模式（tetris_invisible == 1）下整片版面就会突然显形 —— 而按规则只有
## 「刚放下不久的方块」和「到点重新现形的方块」才应该可见。
func set_cell_color_with_lock_time(x: int, y: int, color, lock_time: int):
	var c = _normalize_cell_color(color)
	
	if _is_valid_position(x, y):
		board_data[y][x] = c
		_cell_lock_times[y][x] = lock_time if c != null else 0
		queue_redraw()

## 获取某个格子的锁定时间戳（毫秒；0 = 空/无记录）。隐形的渐隐判定用得到。
func get_cell_lock_time(x: int, y: int) -> int:
	if _is_valid_position(x, y):
		return int(_cell_lock_times[y][x])
	return 0

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

## 绘制版面四边白线（只覆盖可见区域）
## 网格线只画内部（x/y 都跳过边界），所以四条边都必须在这里补白线：
## 之前只画了左右，上下两侧没有任何白线，看起来就是网格/格子描边的灰线。
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
	
	# 上边缘白线
	draw_line(Vector2(board_left, board_top), Vector2(board_right, board_top), board_border_color, board_border_width)
	
	# 下边缘白线
	draw_line(Vector2(board_left, board_bottom), Vector2(board_right, board_bottom), board_border_color, board_border_width)

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
	# ⚠ 必须读控制器的实时值：本节点 _ready 里 _init_board_data() 拷贝的那份 garbage_cap 是
	#   在 TowerController._extra_data_deal()（关卡/buff 设置 garbage_cap）之前取的，
	#   只读缓存的话横线高度会永远停在默认值上（buff 把 cap 改成 5/8/12 都不动）。
	var cap_now: int = garbage_line_controller.garbage_cap if garbage_line_controller else garbage_cap
	if cap_now > 0 and cap_now < grid_height:
		var gap_y = slot_rect.position.y + (grid_height - cap_now) * cell_size
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
		
		# 缓冲中：整条先画半透明底色，再用不透明红色自左往右填充
		# 填充宽度 = 已缓冲时间 / 缓冲总时长，填满（整条变红）时正好缓冲结束、转入正常队列
		draw_rect(bar_rect, garbage_bar_buffer_color, true)
		var timer: float = float(entry.get("timer", 0.0))
		var timer_total: float = float(entry.get("timer_total", garbage_line_controller.buffer_duration))
		var progress: float = 1.0
		if timer_total > 0.0:
			progress = clampf(1.0 - timer / timer_total, 0.0, 1.0)
		if progress > 0.0:
			var fill_width: float = bar_width * progress
			var fill_rect := Rect2(bar_rect.position.x, bar_rect.position.y, fill_width, bar_height)
			draw_rect(fill_rect, garbage_bar_buffer_fill_color, true)
		draw_rect(bar_rect, garbage_bar_buffer_border_color, false, 1.0)
		
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

## 更新短期（滚动 60s 窗口）统计：PPM（落块/分钟）与短期 APM（攻击/分钟），供左侧速条显示
func update_window_stats(ppm: float, apm_window: float):
	ppm_value = ppm
	apm_window_value = apm_window
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
	
	# 文本行（自上而下：TIME / PPS / APM / RPM）
	# TIME：游戏时长 MM:SS（分钟补足两位），取自 TetrisController.game_time（与结算统计同源）
	var total_seconds: int = 0
	if tetris_controller:
		total_seconds = int(tetris_controller.game_time)
	var stats_lines = [
		"TIME %02d:%02d" % [int(total_seconds / 60.0), total_seconds % 60],  # TIME 分:秒
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

# ========== 速条（PPM / APM 短期计速）==========
# 预留功能：位置在统计块最上面一行（TIME）的上方，两条竖条，蓝色 = PPM、橙色 = 短期 APM。
# 数值与 RPM 同口径（最近 60s 滚动窗口）；超过上限显示满格（不溢出），低于下限显示为空。

## 统计文本块的行数（TIME / PPS / APM / RPM），速条定位要用它算 TIME 行的位置
const STATS_LINE_COUNT: int = 4

## 把数值折算成 0~1 的条高：≥上限 = 1（满格不溢出），≤下限 = 0（空）
func _speed_bar_fraction(value: float, min_value: float, max_value: float) -> float:
	if max_value <= min_value:
		return 0.0
	return clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)

## 绘制一条速条：黑底（看清条内部与上下限）+ 彩色填充（自底向上）+ 白边框（画在最上层）
## fraction ≤ 0 时只留空的黑底白框（=低于下限为空）
func _draw_one_speed_bar(x: float, bottom_y: float, width: float, max_height: float,
		fraction: float, color: Color) -> void:
	var frame := Rect2(x, bottom_y - max_height, width, max_height)
	# 黑底：把 0~上限的整个范围显示出来（方便对照上下限）
	draw_rect(frame, speed_bar_bg_color, true)
	# 彩色填充：超过上限也只到这里（满格不溢出）
	if fraction > 0.0:
		var height: float = max_height * fraction
		draw_rect(Rect2(x, bottom_y - height, width, height), color, true)
	# 白边框最后画，保证满格时边框仍然可见
	draw_rect(frame, speed_bar_border_color, false, speed_bar_border_width)

## 绘制两条速条（蓝 PPM / 橙 APM）：位于 TIME 行上方，默认右对齐到统计文本右边缘，
## 再由 speed_bars_offset_x_px / speed_bars_offset_y_px 做微调（正 x = 右移，正 y = 上移）
func _draw_speed_bars():
	if not speed_bars_enabled:
		return
	
	var slot_rect = _get_garbage_slot_position()
	var font_size: float = cell_size * stats_font_size_ratio
	var text_x: float = slot_rect.position.x + stats_offset_x_cells * cell_size
	var text_y_base: float = slot_rect.position.y + slot_rect.size.y - stats_offset_y_cells * cell_size
	# 与 _draw_stats 同一套算式：TIME 是自上而下第一行
	var time_line_y: float = text_y_base - (STATS_LINE_COUNT - 1) * (cell_size * stats_spacing_cells) - font_size * 0.5
	var bottom_y: float = time_line_y - speed_bars_offset_y_cells * cell_size - speed_bars_offset_y_px
	
	var bar_width: float = cell_size * speed_bar_width_ratio
	var gap: float = cell_size * speed_bar_gap_ratio + speed_bar_gap_px
	var max_height: float = cell_size * speed_bar_height_cells
	# 右对齐后再整体右移：橙条最右，蓝条在它左侧
	var orange_x: float = text_x - bar_width + speed_bars_offset_x_px
	var blue_x: float = orange_x - gap - bar_width
	
	_draw_one_speed_bar(blue_x, bottom_y, bar_width, max_height,
		_speed_bar_fraction(ppm_value, speed_bar_ppm_min, speed_bar_ppm_max), speed_bar_ppm_color)
	_draw_one_speed_bar(orange_x, bottom_y, bar_width, max_height,
		_speed_bar_fraction(apm_window_value, speed_bar_apm_min, speed_bar_apm_max), speed_bar_apm_color)
	
	# 条顶写当前数值（四舍五入为整数）
	if speed_bar_show_value:
		var value_font_size: float = cell_size * speed_bar_value_font_ratio
		var value_y: float = bottom_y - max_height - speed_bar_value_gap_px
		_draw_text_centered(Vector2(blue_x + bar_width * 0.5, value_y),
			"%d" % roundi(ppm_value), stats_text_color, stats_text_outline_color, value_font_size)
		_draw_text_centered(Vector2(orange_x + bar_width * 0.5, value_y),
			"%d" % roundi(apm_window_value), stats_text_color, stats_text_outline_color, value_font_size)

# ========== 高度显示系统 ==========

## 高度显示整块（米数 → 进度条）相对版面底部的实际下移像素。
## 正常情况下就是 height_display_offset_y_cells * cell_size；
## 窗口过小、按配置下移会把整块挤出视口底部时，这里自动回缩到刚好放得下。
## （爬塔速度文字已移到右下角速度计圆心，这里不再为它预留高度）
func _get_height_display_offset_px() -> float:
	var font_size: float = cell_size * height_font_size_ratio
	# 整块高度：米数下方 0.4 字高 + 进度条 + 0.2 字高下沿余量
	var block_height: float = font_size * 0.4 + stage_progress_bar_height_cells * cell_size \
		+ font_size * 0.2
	var board_bottom_y: float = offset_y + grid_height * cell_size
	var max_offset: float = get_viewport_rect().size.y - board_bottom_y - block_height
	return clampf(height_display_offset_y_cells * cell_size, 0.0, maxf(max_offset, 0.0))

## 获取「爬塔米数」文字的居中基准位置（版面下侧居中，与 _draw_height_display 第一行完全一致）。
## 供 TowerController 在米数位置弹出 "+X.XXm" 字样使用：两处共用同一套布局数学，
## 改动 height_display_offset_y_cells / cell_size / 版面偏移后不会错位。
func get_tower_meter_text_position() -> Vector2:
	var board_center_x: float = offset_x + grid_width * cell_size * 0.5
	var board_bottom_y: float = offset_y + grid_height * cell_size
	return Vector2(board_center_x, board_bottom_y + _get_height_display_offset_px())

## 绘制高度显示（在版面下侧居中，自上而下：爬塔高度 → 层进度条 → 爬塔速度）
func _draw_height_display():
	if not height_display_enabled:
		return
	if not tower_controller:
		return
	
	var font_size = cell_size * height_font_size_ratio
	
	# 第一行：爬塔高度（版面底部中央，位置与 get_tower_meter_text_position 同源）
	var height_pos: Vector2 = get_tower_meter_text_position()
	var board_center_x: float = height_pos.x
	var height_text = "%.2fm" % tower_controller.tower_meter
	_draw_text_centered(height_pos, height_text, height_text_color,
		height_text_outline_color, font_size)
	
	# 第二行：阶段（层）进度条（在高度文字下方，版面居中）
	var bar_top_y = height_pos.y + font_size * 0.4
	_draw_stage_progress_bar(board_center_x, bar_top_y)
	
	# 爬塔速度文字已移到右下角速度计的圆心（见 _draw_speed_gauge）

## 速度表：同心圆（白边框）+ 白色指针 + 中心写速度数字。
## 位置：版面右下角、Next 列正下方（Next 列中心 X，Next 框堆叠底部往下留一个间距）。
## 指针：量程下限（默认 0）→ 指向「下偏左 30°」，量程上限（默认 20）→ 逆时针扫到「下偏右 30°」（经过正下方）；
##       超过上限时数字继续涨，指针停在极限位置（不溢出）。
func _draw_speed_gauge():
	if not speed_gauge_enabled:
		return
	if not tower_controller:
		return
	
	var viewport_size: Vector2 = get_viewport_rect().size
	var radius: float = cell_size * speed_gauge_radius_cells
	var margin: float = cell_size * speed_gauge_margin_cells
	# 位置：Next 列正下方居中（Next 列 = offset_x + next_display_offset_cells 起、宽 next_display_width 格）
	var next_center_x: float = offset_x + (next_display_offset_cells + next_display_width * 0.5) * cell_size
	var next_stack_bottom: float = offset_y \
		+ next_count * (next_display_height + next_spacing_cells) * cell_size
	var center := Vector2(next_center_x, next_stack_bottom + margin + radius)
	# 保险：整圆不超出视口底部（空间不够时整体上移）
	center.y = minf(center.y, viewport_size.y - margin - radius)
	
	# 同心圆：外圈 + 内圈（都用白边框）
	draw_arc(center, radius, 0.0, TAU, 64, speed_gauge_border_color, speed_gauge_border_width, true)
	if speed_gauge_inner_ratio > 0.0:
		draw_arc(center, radius * speed_gauge_inner_ratio, 0.0, TAU, 48,
			speed_gauge_border_color, speed_gauge_inner_width, true)
	
	# 指针：用缓动后的显示值（见 _update_speed_gauge），折算到 0~1 再映射成「起点角 + 总扫角 × t」
	# 默认起点 -30°（下偏右 30°），总扫角 -300°（逆时针）→ 依次经过 右上 → 正上 → 左上，
	# 到极限 -330°（下偏左 30°）；超过上限时停在极限位置。
	var speed: float = _speed_gauge_displayed
	var t: float = 0.0
	if speed_gauge_max > speed_gauge_min:
		t = clampf((speed - speed_gauge_min) / (speed_gauge_max - speed_gauge_min), 0.0, 1.0)
	var angle: float = deg_to_rad(speed_gauge_start_deg + speed_gauge_sweep_deg * t)
	var needle_dir: Vector2 = Vector2.DOWN.rotated(angle)
	var needle_len: float = radius * speed_gauge_needle_length_ratio
	draw_line(center, center + needle_dir * needle_len,
		speed_gauge_needle_color, speed_gauge_needle_width, true)
	# 圆心小圆点（指针轴心）
	draw_arc(center, maxf(speed_gauge_needle_width, 1.0), 0.0, TAU, 16,
		speed_gauge_needle_color, speed_gauge_needle_width, true)
	
	# 中心数字（塔速度；超过上限也只影响指针，不影响数字）
	# 数字最后画并带黑色描边：指针从圆心出发会从数字下方穿过，描边保证数字依然清晰
	var font: Font = ThemeDB.fallback_font
	var font_size_int: int = maxi(1, roundi(radius * speed_gauge_text_font_ratio))
	var text: String = speed_gauge_text_format % speed
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int)
	var text_center := Vector2(center.x, center.y - radius * speed_gauge_text_offset_ratio)
	var text_pos := Vector2(text_center.x - text_size.x * 0.5,
		text_center.y + font.get_ascent(font_size_int) - text_size.y * 0.5)
	_draw_text_with_outline(text_pos, text, speed_gauge_text_color,
		speed_gauge_text_outline_color, float(font_size_int), HORIZONTAL_ALIGNMENT_LEFT)

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
	
	# 如果有方块数据，绘制方块（框 + 内边距 + 放大倍数都交给绘制函数统一处理）
	if not hold_piece_data.is_empty():
		_draw_piece_in_area(hold_piece_data, hold_piece_color,
			hold_x, hold_y, hold_width, hold_height, hold_padding, hold_preview_scale)

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
		
		# 绘制方块（如果有）（框 + 内边距 + 放大倍数都交给绘制函数统一处理）
		if not shape.is_empty():
			_draw_piece_in_area(shape, color,
				next_x, next_y, next_width, next_height, next_padding, next_preview_scale)

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

## 在指定框内绘制方块（自动缩放）。
## 统一格子大小：所有方块都按「最大占位范围 4 宽 × 2 高」算一次格子大小再画，
## 不再让每个方块各自贴合区域 —— 于是：
##   - O（占位 2×2）不会比别人大一格
##   - I（占位 4×1）的单格与其他方块一样大
## 并且按「实际占位包围盒」（忽略形状矩阵里的空行空列，如 I 是 4×4、T 是 3×3）在框内居中。
## 参数：
##   box_*          整个框（含内边距）
##   padding_ratio  内边距比例（相对框宽/高）
##   preview_scale  放大倍数：在「按内区算出的统一大小」上再乘（Hold 用得上，框大可以画大一点），
##                  但仍受整框限制，不会画出框外，也不会让不同方块大小不一致
##                  （注意参数不能叫 scale —— Node2D 自带 scale 属性，会触发 SHADOWED_VARIABLE_BASE_CLASS 警告）
func _draw_piece_in_area(piece: Array, color: Color, box_x: float, box_y: float,
	box_width: float, box_height: float, padding_ratio: float = 0.15, preview_scale: float = 1.0):
	if piece.is_empty():
		return
	
	var bounds: Dictionary = _get_piece_bounds(piece)
	var bounds_w: int = bounds["w"]
	var bounds_h: int = bounds["h"]
	if bounds_w <= 0 or bounds_h <= 0:
		return
	
	# 统一格子大小：以参考占位范围（默认 4×2）为准 → 所有方块格子一样大
	var ref_w: int = maxi(preview_ref_width, 1)
	var ref_h: int = maxi(preview_ref_height, 1)
	var inner_w: float = box_width * (1.0 - padding_ratio * 2.0)
	var inner_h: float = box_height * (1.0 - padding_ratio * 2.0)
	var draw_cell_size: float = minf(inner_w / float(ref_w), inner_h / float(ref_h)) * maxf(preview_scale, 0.0)
	# 上限：不能超出整个框（保证所有方块仍用同一大小，且 I 这类长条也不会出框）
	draw_cell_size = minf(draw_cell_size, box_width / float(ref_w))
	draw_cell_size = minf(draw_cell_size, box_height / float(ref_h))
	
	# 居中：按实际占位包围盒居中（矩阵的空行空列不再影响位置）
	var start_x: float = box_x + (box_width - bounds_w * draw_cell_size) * 0.5 \
		- bounds["x"] * draw_cell_size
	var start_y: float = box_y + (box_height - bounds_h * draw_cell_size) * 0.5 \
		- bounds["y"] * draw_cell_size
	
	# 绘制每个方块
	for y in range(piece.size()):
		for x in range(piece[y].size()):
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

## 取形状矩阵中「实际占用格子」的包围盒：{x, y, w, h}
## 形状矩阵带空行空列（I 是 4×4、T/S/Z/J/L 是 3×3），只看填了格子的范围才能正确定大小与居中。
func _get_piece_bounds(piece: Array) -> Dictionary:
	var min_x: int = 1 << 30
	var min_y: int = 1 << 30
	var max_x: int = -1
	var max_y: int = -1
	for y in range(piece.size()):
		var row: Array = piece[y]
		for x in range(row.size()):
			if row[x] == 1:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return {"x": 0, "y": 0, "w": 0, "h": 0}
	return {"x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1}

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

## 居中绘制文本：按字符串实际宽度手动换算起点 X，再以左对齐绘制。
## 原因：draw_string 在 width=-1 时 alignment 不保证生效（本项目的 text_printer / toggle_box
## 也是同一套「先量宽再手动定位」的写法），手动定位可保证「以版面中心为中心」。
func _draw_text_centered(center_pos: Vector2, text: String, color: Color, outline_color: Color, font_size: float):
	var font = ThemeDB.fallback_font
	var font_size_int: int = maxi(1, int(font_size))
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int).x
	var text_position = Vector2(center_pos.x - text_width * 0.5, center_pos.y)
	_draw_text_with_outline(text_position, text, color, outline_color, font_size, HORIZONTAL_ALIGNMENT_LEFT)

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
	
	# 8.5 绘制速条（PPM / 短期 APM，预留在统计块上方，默认关闭）
	_draw_speed_bars()
	
	# 9. 绘制高度显示
	_draw_height_display()
	
	# 9.5 绘制右下角塔速度表（同心圆 + 白指针 + 圆心速度数字）
	_draw_speed_gauge()
	
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
