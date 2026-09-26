extends Node
class_name TetrisGarbageLineController

## 俄罗斯方块垃圾行控制器
## 负责垃圾行的生成、管理和增长逻辑

# 节点引用
@export var board_drawer: TetrisBoardDrawer  # 版面绘制器节点
@export var tetris_controller: TetrisController  # 方块控制器引用（用于清除当前方块）
@export var clear_line_controller: TetrisClearLine  # 消行控制器引用（用于检测消行延迟）

# 垃圾行配置
@export var garbage_cap: int = 3                      # 每次锁定最多增长的垃圾行数量（也用于版面garbage_cap线）
@export var garbage_messy: float = 0.9               # 垃圾行更换洞口的概率（0-1）
@export var garbage_color: Color = Color(0.5, 0.5, 0.5, 1.0)  # 垃圾行颜色（浅灰色）
@export var solid_garbage_color: Color = Color(0.3, 0.3, 0.3, 1.0)  # 实心垃圾行颜色（深灰色）
@export var garbage_empty_color: Color = Color(0.08, 0.08, 0.08, 1.0)  # 垃圾行洞口颜色（与版面背景一致）

# 垃圾缓冲配置
@export var buffer_duration: float = 3.0             # 垃圾缓冲时间（秒）

# 抵消倍率：每 1 行攻击可抵消 mult_defend 行垃圾
@export var mult_defend: float = 1.0                 # 抵消倍率（默认 1.0）

## 供 bot 读取当前关卡 buff 调整后的防御倍率（mult_defend）。
func get_mult_defend() -> float:
	return mult_defend

# ====== 瞬间/逐行上涨模式 ======
## true = 旧逻辑：锁定方块时一次性上涨所有垃圾行
## false = 逐行上涨：垃圾行加入依次上涨队列，每 garbage_rise_time_delay 秒上涨一行
@export var suddenly_death_mode: bool = false

## false = 传统逻辑：方块锁定后才触发垃圾行上涨
## true = 取消锁定限制：缓冲计时结束即刻上涨垃圾行
@export var drop_limit_cancel: bool = false

## 逐行上涨模式下的行间隔时间（秒）
@export var garbage_rise_time_delay: float = 0.5

## 依次上涨队列：存储 {holes, is_buffered, color, empty_color} 等行数据
var _pending_rise_queue: Array[Dictionary] = []

## 消行延迟期间暂存的一次性直接上涨（延迟结束后统一上涨，避免消行动画期间改动版面）
## 元素结构 {all_holes: Array, row_count: int}
var _deferred_direct_raises: Array = []

## 消行延迟期间暂存的实心垃圾行上涨数量（延迟结束后统一上涨，避免消行动画期间
## 改动版面，导致待消行位移、实心行被意外消除或填充）
var _deferred_solid_raises: Array = []

## 逐行上涨计时器
var _rise_timer: Timer = null

@export var buffered_garbage_color: Color = Color(0.5, 0.0, 0.0, 0.7)  # 缓冲垃圾颜色（半透明暗红色）
@export var buffered_garbage_empty_color: Color = Color(0.2, 0.0, 0.0, 0.5)  # 缓冲垃圾洞口颜色

# 垃圾行数据
var garbage_enter_array: Array = []                  # 储存打入的攻击 [{count: int, extra_hole_count: int}, ...]
var garbage_output_array: Array = []                 # 储存垃圾行洞口位置 [[X], [Y], [Z], ...]

# 垃圾缓冲数据
var garbage_buffer: Array = []                       # 缓冲中的垃圾数据 [{count: int, holes: Array, timer: float, is_buffered: bool}]

# 实心垃圾行数据（不可消除）
var solid_garbage_rows: Dictionary = {}              # 记录实心垃圾行的行索引 {row_index: true}

# 内部状态
var pending_garbage_data: Array = []                # 待处理的垃圾行数据 [{count: int, holes: Array}, ...]
var is_garbage_locked: bool = false                 # 是否正在处理垃圾行锁定
var garbage_rows_data: Dictionary = {}              # 记录每行垃圾行的洞口位置 {row_index: [hole_x]}
var current_active_hole: Array = []                 # 当前活跃的洞口位置（用于溢出保留）
var has_overflow: bool = false                      # 是否有溢出的垃圾行

func _ready():
	# 自动查找board_drawer（如果未设置）
	if not board_drawer:
		board_drawer = get_node_or_null("../TetrisBoardDrawer")
		if not board_drawer:
			push_error("TetrisGarbageLineController: 未找到TetrisBoardDrawer节点！")
			return
	
	# 自动查找tetris_controller（如果未设置）
	if not tetris_controller:
		tetris_controller = get_node_or_null("../TetrisController")
		if not tetris_controller:
			push_error("TetrisGarbageLineController: 未找到TetrisController节点！")
			# 不是致命错误，继续运行
	
	# 自动查找clear_line_controller（如果未设置）
	if not clear_line_controller:
		clear_line_controller = get_node_or_null("../TetrisClearLine")
	
	# 初始化逐行上涨计时器
	_rise_timer = Timer.new()
	_rise_timer.one_shot = false
	_rise_timer.timeout.connect(_on_rise_timer_timeout)
	add_child(_rise_timer)
	
	# 初始化垃圾行输出队列
	_refill_garbage_output()

func _process(delta):
	# 更新缓冲垃圾计时器
	_update_buffer_timers(delta)

## 更新缓冲垃圾计时器
func _update_buffer_timers(delta: float):
	if garbage_buffer.is_empty():
		return
	
	var i = 0
	while i < garbage_buffer.size():
		var buffer_entry = garbage_buffer[i]
		buffer_entry["timer"] -= delta
		
		# 计时归零，将缓冲垃圾转为正常垃圾
		if buffer_entry["timer"] <= 0:
			# 从缓冲移除并添加到正常队列
			var converted_count = buffer_entry["count"]
			var converted_extra_hole_count: int = buffer_entry.get("extra_hole_count", 0)
			
			# 添加到正常队列末尾（先缓冲完的在底部，先出）
			garbage_enter_array.append({"count": converted_count, "extra_hole_count": converted_extra_hole_count})
			
			# 从缓冲中移除
			garbage_buffer.remove_at(i)
			
			# drop_limit_cancel = true 时：缓冲结束即刻上涨，不再等待方块锁定
			if drop_limit_cancel:
				if not garbage_enter_array.is_empty():
					# 消行延迟期间不立即上涨（保留在 enter_array 中不丢弃，延迟结束后随下次触发上涨）
					if is_clear_delay_active():
						continue
					var success = process_garbage_after_lock()
					if success <= 0 and tetris_controller:
						tetris_controller._game_over("垃圾上涨失败")
			
			##print("缓冲垃圾已就绪: ", converted_count, " 行，当前队列: ", garbage_enter_array)
		else:
			i += 1

## 补充垃圾行输出队列（默认生成garbage_cap大小）
func _refill_garbage_output():
	while garbage_output_array.size() < garbage_cap:
		var new_hole = _generate_single_hole()
		garbage_output_array.append(new_hole)

## 为单个垃圾行生成所有洞口位置（基于基础洞口 + 随机额外挖洞）
## @param base_hole: [int] 基础洞口x坐标（所有行共享）
## @param extra_hole_count: 额外随机挖洞数（每行独立）
func _generate_row_holes(base_hole: Array, extra_hole_count: int) -> Array:
	var garbage_rng = RandomManager.get_random("GARBAGE")
	var result: Array = base_hole.duplicate()
	for _i in range(extra_hole_count):
		var hole_x = _get_random_hole_position(garbage_rng, -1)
		# 确保不重复
		var attempts = 0
		while hole_x in result and attempts < 100:
			hole_x = _get_random_hole_position(garbage_rng, -1)
			attempts += 1
		if hole_x not in result:
			result.append(hole_x)
	return result

## 生成单个垃圾行的洞口位置
func _generate_single_hole() -> Array:
	var garbage_rng = RandomManager.get_random("GARBAGE")
	
	# 获取上一个洞口的X位置（用于避免相邻相同）
	var last_hole_x = -1
	if not garbage_output_array.is_empty():
		var last_entry = garbage_output_array[garbage_output_array.size() - 1]
		if not last_entry.is_empty():
			last_hole_x = last_entry[0]
	
	# 生成随机洞口位置（0 到 board_drawer.grid_width - 1）
	var new_hole_x = _get_random_hole_position(garbage_rng, last_hole_x)
	return [new_hole_x]

## 获取随机洞口位置（确保与上一个不同）
func _get_random_hole_position(rng: RandomNumberGenerator, exclude_x: int) -> int:
	var max_attempts = 100
	for _i in range(max_attempts):
		var hole_x = rng.randi_range(0, board_drawer.grid_width - 1)
		if hole_x != exclude_x:
			return hole_x
	# 如果无法生成不同的位置，返回默认值
	return (exclude_x + 1) % board_drawer.grid_width

## 添加攻击到进入队列（不限制单次攻击量）
## @param attack_count: 攻击行数
## @param add_extra_hole: 额外挖洞数，在1个基础洞口基础上再额外挖 add_extra_hole 个洞
##   基础洞口在函数内直接随机生成，额外洞口在每行上涨时独立随机生成
func add_attack(attack_count: int, add_extra_hole: int = 0):
	if attack_count <= 0:
		return
	
	var extra_rng = RandomManager.get_random("GARBAGE")
	
	# 只生成1个基础洞口（所有行共享相同的base_hole）
	var base_hole_x = _get_random_hole_position(extra_rng, -1)
	var base_hole: Array = [base_hole_x]
	
	# 添加到缓冲队列（带计时器）
	var buffer_entry = {
		"count": attack_count,
		"holes": base_hole,
		"base_hole": base_hole,
		"extra_hole_count": add_extra_hole,
		"timer": buffer_duration,
		"is_buffered": true
	}
	garbage_buffer.append(buffer_entry)
	
	# 关联到TetrisController的RPM统计
	if tetris_controller:
		# 使用record_received_damage方法记录接收攻击
		tetris_controller._record_received_damage(attack_count)
	
	###print("添加攻击: ", attack_count, " 行，额外挖洞: ", add_extra_hole, "，洞口: ", holes, "（缓冲中），当前缓冲: ", garbage_buffer)

## 获取缓冲中的垃圾数据（用于显示）
func get_buffered_garbage() -> Array:
	return garbage_buffer.duplicate()

## 检查是否有缓冲中的垃圾
func has_buffered_garbage() -> bool:
	return not garbage_buffer.is_empty()

## ========== 强制上涨系统（核心功能） ==========

## 强制上涨行数（通用功能，支持自定义行数据生成器）
## 版面版本号：每次垃圾行成功上涨（force_raise_rows 真正上移了行）时 +1。
## 用于让 bot 感知“垃圾行抬升期间版面已变化”，从而重新请求决策，避免执行过期计划。
var board_version: int = 0

## 计算新垃圾行应插入的起始行索引：紧贴底部实心块上方；无实心块时为版面底部。
## 与 force_raise_rows 的版面构建逻辑保持一致，供各调用方记录新行洞口位置。
func _get_new_rows_start(row_count: int) -> int:
	var H: int = board_drawer.get_playable_height()
	var bottom_solid: int = 0
	for y in range(H - 1, -1, -1):
		if is_solid_garbage_row(y):
			bottom_solid += 1
		else:
			break
	return (H - bottom_solid) - row_count

func force_raise_rows(row_count: int, row_generator: Callable, skip_piece_handling: bool = false) -> bool:
	if row_count <= 0:
		return false
	
	# 限制单次上涨数量
	row_count = min(row_count, garbage_cap)
	
	# 如果tetris_controller存在，先清除当前方块并记录其位置
	var current_pos = null
	if tetris_controller and not skip_piece_handling:
		# 保存当前方块位置
		current_pos = tetris_controller.current_position
		# 清除当前方块（从版面上移除）
		tetris_controller._clear_current_piece()
	
	# 收集当前版面所有数据
	var board_data = []
	for y in range(board_drawer.get_playable_height()):
		var row = []
		for x in range(board_drawer.grid_width):
			row.append(board_drawer.get_cell_color(x, y))
		board_data.append(row)
	
	# 计算需要上移的行数
	var shift_amount = row_count
	var H: int = board_drawer.get_playable_height()
	
	# 计算底部实心垃圾行块的高度（实心行必定处于最底层，不可被顶起）
	var bottom_solid: int = 0
	for y in range(H - 1, -1, -1):
		if is_solid_garbage_row(y):
			bottom_solid += 1
		else:
			break
	# 实心行块的起始行（实心块上方的内容行索引小于该值）
	var solid_start: int = H - bottom_solid
	# 新垃圾行插入的起始行：紧贴实心块上方（无实心块时即为版面底部）
	var new_row_start: int = max(0, solid_start - shift_amount)
	
	# 创建新版面数据
	var new_board_data = []
	
	# 上移实心块上方的非实心内容（顶部被挤出）
	for y in range(new_row_start):
		var row_data = []
		var source_y = y + shift_amount
		if source_y < board_data.size():
			for x in range(board_drawer.grid_width):
				row_data.append(board_data[source_y][x])
		else:
			for x in range(board_drawer.grid_width):
				row_data.append(null)
		new_board_data.append(row_data)
	
	# 添加新行到实心块上方（紧贴实心块）
	for i in range(shift_amount):
		var row_data = row_generator.call(i, shift_amount)
		new_board_data.append(row_data)
	
	# 保留底部实心块（位置不变）
	for y in range(solid_start, H):
		var row_data = []
		for x in range(board_drawer.grid_width):
			row_data.append(board_data[y][x])
		new_board_data.append(row_data)
	
	# 清空版面
	for y in range(board_drawer.get_playable_height()):
		for x in range(board_drawer.grid_width):
			board_drawer.set_cell_color(x, y, null)
	
	# 写入新数据
	for y in range(min(new_board_data.size(), board_drawer.get_playable_height())):
		for x in range(board_drawer.grid_width):
			if y < new_board_data.size() and x < new_board_data[y].size():
				var color = new_board_data[y][x]
				if color != null:
					board_drawer.set_cell_color(x, y, color)
	
	# 检查是否有任何非空方块超过第50行（y < 50，高于第50行即触发游戏结束）
	# 隐藏区域共70行（0-69），第0-49行为禁止区，第50-69行为安全缓冲
	var has_block_above_50: bool = false
	for y in range(0, min(50, board_drawer.grid_max_height)):
		for x in range(board_drawer.grid_width):
			if board_drawer.get_cell_color(x, y) != null:
				has_block_above_50 = true
				break
		if has_block_above_50:
			break
	if has_block_above_50:
		if tetris_controller:
			tetris_controller._game_over("方块堆积过高")
		return false
	
	# 如果tetris_controller存在且需要处理当前方块，恢复当前方块（位置向上移动row_count行）
	if tetris_controller and not skip_piece_handling and current_pos != null:
		# 计算新位置：Y坐标向上移动row_count行（减小）
		var new_pos = Vector2i(current_pos.x, current_pos.y - row_count)
		
		# 确保位置不超出顶部
		if new_pos.y < 0:
			new_pos.y = 0
		
		# 更新方块位置
		tetris_controller.current_position = new_pos
		
		# 检查新位置是否碰撞（如果碰撞，说明方块被卡死，可能需要游戏结束处理）
		if tetris_controller._check_collision(new_pos):
			# 如果碰撞，尝试逐步上移直到找到有效位置
			var test_pos = new_pos
			while test_pos.y > 0 and tetris_controller._check_collision(test_pos):
				test_pos.y -= 1
			if test_pos.y >= 0 and not tetris_controller._check_collision(test_pos):
				tetris_controller.current_position = test_pos
			else:
				# 无法找到有效位置，游戏结束
				push_error("方块被卡死，游戏结束")
				if tetris_controller:
					tetris_controller._game_over("方块被卡死")
				return false
		
		# 重新绘制当前方块
		tetris_controller._draw_current_piece()
		
		# 更新影子
		tetris_controller._update_shadow()
	
	# 请求重绘
	board_drawer.queue_redraw()
	
	# 垃圾行洞口记录随版面上移：整版上移 row_count 行后，已有垃圾行的实际行索引
	# 减小 row_count（y=0 为顶部），被挤出顶部的记录应删除；底部新增行的洞口由调用方
	# （_on_rise_timer_timeout / apply_garbage_to_board）另行记录。
	# 若不同步，逐行上涨时 garbage_rows_data 索引错位，会导致 is_garbage_hole /
	# _is_hole_position 判定丢失/错乱（洞口“消失”或出现在错误行）。
	if row_count > 0 and not garbage_rows_data.is_empty():
		var shifted: Dictionary = {}
		for row_y in garbage_rows_data:
			var new_y: int = int(row_y) - row_count
			if new_y >= 0:
				shifted[new_y] = garbage_rows_data[row_y]
		garbage_rows_data = shifted
	
	# 实心垃圾行记录无需随版面上移：实心行必定处于最底层且被固定，普通垃圾上涨时
	# 实心块位置不变（见上方版面构建逻辑），因此 solid_garbage_rows 保持原索引。
	# （若新增行本身是实心行，add_solid_garbage 会重新扫描整个版面重建该记录。）
	
	# 版面已因垃圾行上涨而改变：递增版本号，通知 bot 重新决策
	board_version += 1
	
	##print("强制上涨了 ", row_count, " 行")
	return true

## 生成普通垃圾行数据（带洞口）
func _generate_garbage_row_generator(holes: Array, is_buffered: bool = false) -> Callable:
	return func(_i: int, _total: int) -> Array:
		var row_data = []
		for x in range(board_drawer.grid_width):
			var is_hole = false
			for hole_x in holes:
				if x == hole_x:
					is_hole = true
					break
			
			if is_hole:
				if is_buffered:
					row_data.append(buffered_garbage_empty_color)
				else:
					row_data.append(null)
			else:
				if is_buffered:
					row_data.append(buffered_garbage_color)
				else:
					row_data.append(garbage_color)
		return row_data

## 生成实心垃圾行数据（全深灰色）
func _generate_solid_row_generator() -> Callable:
	return func(_i: int, _total: int) -> Array:
		var row_data = []
		for x in range(board_drawer.grid_width):
			row_data.append(solid_garbage_color)
		return row_data

## 上涨X行实心垃圾行（无法消除）
func add_solid_garbage(row_count: int):
	if row_count <= 0:
		return
	
	# 消行延迟期间：暂存起来，延迟结束后统一上涨（不丢弃行，避免在消行动画期间改动
	# 版面，造成待消行位移、实心行被意外消除/填充）
	if is_clear_delay_active():
		_deferred_solid_raises.append(row_count)
		return
	
	# 使用强制上涨 + 实心行生成器
	var success = force_raise_rows(row_count, _generate_solid_row_generator())
	if success:
		# 清除旧的实心垃圾行记录（因为行索引已经变化）
		solid_garbage_rows.clear()
		
		# 重新记录所有实心垃圾行的行索引
		# 遍历版面，找到所有实心垃圾行
		for y in range(board_drawer.get_playable_height()):
			var is_solid = true
			for x in range(board_drawer.grid_width):
				var color = board_drawer.get_cell_color(x, y)
				if color != solid_garbage_color:
					is_solid = false
					break
			if is_solid:
				solid_garbage_rows[y] = true
		
		##print("上涨了 ", row_count, " 行实心垃圾行，当前实心行: ", solid_garbage_rows.keys())

## ========== 垃圾行抵消系统 ==========

## 抵消垃圾行（优先抵消列表第一项，包括缓冲垃圾）
## 实际抵消能力 = attack_damage * mult_defend
func offset_garbage(attack_damage: int) -> int:
	if attack_damage <= 0:
		return 0
	
	# 无垃圾可抵消时直接返回
	if _pending_rise_queue.is_empty() and garbage_enter_array.is_empty() and garbage_buffer.is_empty():
		##print("垃圾槽为空，无需抵消")
		return 0
	
	# 实际可抵消的行数 = 攻击行数 × mult_defend
	var effective_damage: int = max(1, roundi(attack_damage * mult_defend))
	
	##print("抵消前依次上涨队列: ", _pending_rise_queue.size(), " 行")
	##print("抵消前垃圾槽: ", garbage_enter_array)
	##print("抵消前缓冲: ", garbage_buffer)
	##print("抵消倍率: ", mult_defend, "，攻击: ", attack_damage, " → 实际抵消能力: ", effective_damage)
	
	var remaining_damage = effective_damage
	var offset_count: int = 0
	
	# 优先抵消依次上涨队列中的行（逐行模式）
	var rise_offset: int = offset_rise_queue(remaining_damage)
	offset_count += rise_offset
	remaining_damage -= rise_offset
	
	# 再抵消正常队列（优先抵消最先进来的）
	while remaining_damage > 0 and not garbage_enter_array.is_empty():
		var entry = garbage_enter_array[0]
		var current = entry["count"]
		
		if current <= remaining_damage:
			# 完全抵消当前项
			remaining_damage -= current
			offset_count += current
			garbage_enter_array.remove_at(0)
			##print("完全抵消正常项: ", current, "，剩余伤害: ", remaining_damage)
		else:
			# 部分抵消当前项
			entry["count"] = current - remaining_damage
			offset_count += remaining_damage
			remaining_damage = 0
			##print("部分抵消正常项: ", current, " -> ", entry["count"])
	
	# 如果还有剩余伤害，抵消缓冲垃圾（从最早的开始）
	while remaining_damage > 0 and not garbage_buffer.is_empty():
		var buffer_entry = garbage_buffer[0]
		var current = buffer_entry["count"]
		
		if current <= remaining_damage:
			# 完全抵消当前缓冲项
			remaining_damage -= current
			offset_count += current
			garbage_buffer.remove_at(0)
			##print("完全抵消缓冲项: ", current, "，剩余伤害: ", remaining_damage)
		else:
			# 部分抵消当前缓冲项
			buffer_entry["count"] = current - remaining_damage
			offset_count += remaining_damage
			remaining_damage = 0
			##print("部分抵消缓冲项: ", current, " -> ", buffer_entry["count"])
	
	##print("抵消后垃圾槽: ", garbage_enter_array)
	##print("抵消后缓冲: ", garbage_buffer)
	##print("总共抵消: ", offset_count, " 行，剩余伤害: ", remaining_damage)
	
	# 返回实际抵消的行数
	return offset_count

## 获取下一个垃圾行的洞口位置（从输出队列取出）
func _get_next_hole_position() -> Array:
	# 确保输出队列有足够的元素
	_refill_garbage_output()
	
	# 从输出队列取出第一个
	var hole = garbage_output_array.pop_front()
	
	# 生成新的洞口补充到队列末尾（确保与最后一个不同）
	var last_hole_x = -1
	if not garbage_output_array.is_empty():
		var last_entry = garbage_output_array[garbage_output_array.size() - 1]
		if not last_entry.is_empty():
			last_hole_x = last_entry[0]
	
	var garbage_rng = RandomManager.get_random("GARBAGE")
	var new_hole_x = _get_random_hole_position(garbage_rng, last_hole_x)
	garbage_output_array.append([new_hole_x])
	
	return hole


## 检查是否应该更换洞口（基于garbage_messy概率）
func _should_change_hole() -> bool:
	var garbage_rng = RandomManager.get_random("GARBAGE")
	return garbage_rng.randf() < garbage_messy

## 准备增长的垃圾行数据（方块锁定且无消行时调用）
func prepare_garbage_for_lock() -> int:
	# 检查是否有正常的垃圾行（不包括缓冲中的）
	if garbage_enter_array.is_empty():
		return 0
	
	# 计算本次要增长的垃圾行数量（最多garbage_cap行）
	var total_available = 0
	for entry in garbage_enter_array:
		total_available += entry["count"]
	
	var total_to_process = min(total_available, garbage_cap)
	
	if total_to_process <= 0:
		return 0
	
	# 清空待处理数据
	pending_garbage_data = []
	garbage_rows_data = {}
	
	var remaining_to_process = total_to_process
	var enter_index = 0
	var current_hole = []
	var has_current_hole = false
	
	# 如果有溢出的洞口，先使用
	if has_overflow and not current_active_hole.is_empty():
		current_hole = current_active_hole.duplicate()
		has_current_hole = true
		has_overflow = false
	else:
		# 获取新的洞口
		current_hole = _get_next_hole_position()
		has_current_hole = true
	
	# 按garbage_enter_array的顺序处理
	while remaining_to_process > 0 and enter_index < garbage_enter_array.size():
		var entry = garbage_enter_array[enter_index]
		var batch_count = entry["count"]
		var extra_hole_count: int = entry.get("extra_hole_count", 0)
		
		# 计算这一批次实际要处理的数量
		var process_count = min(batch_count, remaining_to_process)
		
		if process_count > 0:
			# 基础洞口（批次内所有行共享），每行额外挖洞独立随机生成
			var all_row_holes: Array = []
			var all_is_buffered: Array = []
			for _i in range(process_count):
				var row_holes = _generate_row_holes(current_hole, extra_hole_count)
				all_row_holes.append(row_holes)
				all_is_buffered.append(false)
			
			# 记录这一批次的数据（每个单行的洞口单独存储）
			pending_garbage_data.append({
				"count": process_count,
				"holes": all_row_holes,
				"is_buffered": false,
				"_per_row_holes": true    # 标记：holes 是 Array[Array]
			})
			
			# 更新剩余处理数量
			remaining_to_process -= process_count
			batch_count -= process_count
		
		# 如果这一批次还有剩余，更新garbage_enter_array
		if batch_count > 0:
			entry["count"] = batch_count
		else:
			# 这一批次已完全处理，移除
			garbage_enter_array.remove_at(enter_index)
			enter_index -= 1
		
		# 如果还有剩余要处理，判定是否换洞
		if remaining_to_process > 0 and _should_change_hole():
			current_hole = _get_next_hole_position()
		elif remaining_to_process > 0:
			# 不换洞，保持当前洞口
			pass
		
		enter_index += 1
	
	# 如果还有溢出的行（超过了garbage_cap），保存当前洞口用于下次
	if total_available > total_to_process and has_current_hole:
		has_overflow = true
		current_active_hole = current_hole.duplicate()
		##print("有溢出行，保留洞口: ", current_active_hole)
	
	# 如果garbage_enter_array为空，重置溢出状态
	if garbage_enter_array.is_empty():
		has_overflow = false
		current_active_hole = []
	
	is_garbage_locked = true
	
	# ##print("准备垃圾行: ", total_to_process, " 行，批次数据: ", pending_garbage_data)
	
	return total_to_process

## 应用垃圾行到版面（在方块锁定且无消行后调用）
func apply_garbage_to_board() -> bool:
	if not is_garbage_locked or pending_garbage_data.is_empty():
		return false
	
	# 使用强制上涨来应用垃圾行
	var total_garbage_rows = 0
	for batch in pending_garbage_data:
		total_garbage_rows += batch["count"]
	
	# 限制总垃圾行数
	total_garbage_rows = min(total_garbage_rows, garbage_cap)
	
	if total_garbage_rows <= 0:
		is_garbage_locked = false
		return false
	
	# 收集所有批次的洞口数据和缓冲状态
	var all_holes = []
	var all_buffered = []
	for batch in pending_garbage_data:
		var count = batch["count"]
		var holes = batch["holes"]
		var is_per_row: bool = batch.get("_per_row_holes", false)
		var is_buffered = batch.get("is_buffered", false)
		for i in range(count):
			if is_per_row:
				all_holes.append(holes[i])
			else:
				all_holes.append(holes)
			all_buffered.append(is_buffered)
	
	# 使用强制上涨 + 垃圾行生成器（根据是否为缓冲决定颜色）
	var generator = func(i: int, _total: int) -> Array:
		var holes = all_holes[i] if i < all_holes.size() else [0]
		var is_buffered = all_buffered[i] if i < all_buffered.size() else false
		var row_data = []
		for x in range(board_drawer.grid_width):
			var is_hole = false
			for hole_x in holes:
				if x == hole_x:
					is_hole = true
					break
			
			if is_hole:
				if is_buffered:
					row_data.append(buffered_garbage_empty_color)
				else:
					row_data.append(null)
			else:
				if is_buffered:
					row_data.append(buffered_garbage_color)
				else:
					row_data.append(garbage_color)
		return row_data
	
	# 执行强制上涨（会处理方块Y坐标同步）
	var success = force_raise_rows(total_garbage_rows, generator)
	
	# 如果强制上涨成功，记录垃圾行数据
	if success:
		# 记录每行的洞口位置（从实心块上方开始数）
		var start_y = _get_new_rows_start(total_garbage_rows)
		for i in range(total_garbage_rows):
			if i < all_holes.size():
				garbage_rows_data[start_y + i] = all_holes[i].duplicate()
	
	# 重置状态
	is_garbage_locked = false
	pending_garbage_data = []
	
	##print("垃圾行已应用，共 ", total_garbage_rows, " 行")
	return success

## 检查某个格子是否为垃圾行
func is_garbage_cell(x: int, y: int) -> bool:
	var color = board_drawer.get_cell_color(x, y)
	return color == garbage_color or color == buffered_garbage_color

## 检查某个格子是否为垃圾行洞口
func is_garbage_hole(x: int, y: int) -> bool:
	var color = board_drawer.get_cell_color(x, y)
	return (color == null or color == buffered_garbage_empty_color) and _is_hole_position(x, y)

## 检查某个位置是否为洞口
func _is_hole_position(x: int, y: int) -> bool:
	if not garbage_rows_data.has(y):
		return false
	for hole_x in garbage_rows_data[y]:
		if hole_x == x:
			return true
	return false

## 获取某行垃圾行的洞口位置
func get_garbage_holes_for_row(y: int) -> Array:
	if garbage_rows_data.has(y):
		return garbage_rows_data[y]
	return []

## 检查某行是否为实心垃圾行
func is_solid_garbage_row(row_index: int) -> bool:
	return solid_garbage_rows.has(row_index)

## 检查某个格子是否为实心垃圾行
func is_solid_garbage_cell(x: int, y: int) -> bool:
	if not solid_garbage_rows.has(y):
		return false
	var color = board_drawer.get_cell_color(x, y)
	return color == solid_garbage_color

## 清除所有实心垃圾行
func clear_solid_garbage():
	# 从版面中清除实心垃圾行
	for y in range(board_drawer.get_playable_height()):
		if solid_garbage_rows.has(y):
			for x in range(board_drawer.grid_width):
				var color = board_drawer.get_cell_color(x, y)
				if color == solid_garbage_color:
					board_drawer.set_cell_color(x, y, null)
	solid_garbage_rows.clear()
	board_drawer.queue_redraw()

## 方块锁定后的垃圾行处理入口（供 tetris_controller 调用）
## 根据 suddenly_death_mode 选择模式：
##   true  → 立即 prepare + apply（旧逻辑）
##   false → 加入依次上涨队列，逐行上涨
func process_garbage_after_lock() -> int:
	if garbage_enter_array.is_empty():
		return 0
	
	if suddenly_death_mode:
		# 旧模式：立即上涨
		var count = prepare_garbage_for_lock()
		if count > 0:
			var success = apply_garbage_to_board()
			if not success:
				return 0
		return count
	else:
		# 逐行模式：加入依次上涨队列
		_move_enter_to_rise_queue()
		# 不返回 0 表示有数据进入队列
		return _pending_rise_queue.size()

## Allspin：上涨 x 行标准垃圾行（直接插入版面，不走延迟队列，消行完成后调用）
func insert_allspin_garbage_directly(row_count: int = 1) -> void:
	if row_count <= 0:
		return
	var all_holes = []
	for i in range(row_count):
		var hole = _get_next_hole_position()
		if hole.is_empty():
			return
		all_holes.append(hole)
	# 消行延迟期间：暂存起来，延迟结束后统一上涨（不丢弃行，避免在消行动画期间改动版面）
	if is_clear_delay_active():
		_deferred_direct_raises.append({"all_holes": all_holes, "row_count": row_count})
		return
	# 创建行生成器
	var gen = _generate_garbage_row_generator(all_holes[0], false)
	force_raise_rows(row_count, gen, true)

## Allspin：上涨 x 行标准垃圾行（直接推到上升队列最前面）
func add_allspin_garbage(row_count: int = 1) -> void:
	if row_count <= 0:
		return
	for i in range(row_count):
		var hole = _get_next_hole_position()
		if hole.is_empty():
			return
		_pending_rise_queue.push_front({
			"holes": hole,
			"is_buffered": false,
			"color": garbage_color,
			"empty_color": null,
		})
	_start_rise_timer()

## 检查当前是否有待处理的垃圾行
func has_pending_garbage() -> bool:
	return is_garbage_locked or not pending_garbage_data.is_empty()

## 获取待处理的垃圾行数量
func get_pending_garbage_count() -> int:
	var total = 0
	for batch in pending_garbage_data:
		total += batch["count"]
	return total

## ========== 逐行上涨系统 ==========

## 将垃圾行数据拆分为单行，加入依次上涨队列
## 在 suddenly_death_mode=false 时由 process_garbage_after_lock 调用
func _move_enter_to_rise_queue() -> int:
	if garbage_enter_array.is_empty():
		return 0
	
	var total_available = 0
	for entry in garbage_enter_array:
		total_available += entry["count"]
	
	# 限流（每次锁定最多新增 garbage_cap 行，保留尚未上涨完的旧行，避免丢失）
	var total_rows = min(total_available, garbage_cap)
	
	var remaining = total_rows
	var enter_index = 0
	var current_hole = []
	var has_current_hole = false
	
	# 如果有溢出的洞口，先使用
	if has_overflow and not current_active_hole.is_empty():
		current_hole = current_active_hole.duplicate()
		has_current_hole = true
		has_overflow = false
	else:
		current_hole = _get_next_hole_position()
		has_current_hole = true
	
	while remaining > 0 and enter_index < garbage_enter_array.size():
		var entry = garbage_enter_array[enter_index]
		var batch_count = entry["count"]
		var extra_hole_count: int = entry.get("extra_hole_count", 0)
		var process_count = min(batch_count, remaining)
		
		for _i in range(process_count):
			# 每行独立生成额外挖洞
			var row_holes = _generate_row_holes(current_hole, extra_hole_count)
			_pending_rise_queue.append({
				"holes": row_holes,
				"is_buffered": false,
				"color": garbage_color,
				"empty_color": null,
			})
		
		remaining -= process_count
		batch_count -= process_count
		
		if batch_count > 0:
			entry["count"] = batch_count
		else:
			garbage_enter_array.remove_at(enter_index)
			enter_index -= 1
		
		if remaining > 0 and _should_change_hole():
			current_hole = _get_next_hole_position()
		
		enter_index += 1
	
	if total_available > total_rows and has_current_hole:
		has_overflow = true
		current_active_hole = current_hole.duplicate()
	if garbage_enter_array.is_empty():
		has_overflow = false
		current_active_hole = []
	
	##print("逐行上涨队列已填充: %d 行" % _pending_rise_queue.size())
	_start_rise_timer()
	return _pending_rise_queue.size()

## 是否正处于消行延迟中（消行动画期间不得改动版面：待消行仍物理存在，
## 此时上涨垃圾会使待消行上移，导致延迟结束后 _pending_clear_lines 索引错位等 bug）
func is_clear_delay_active() -> bool:
	if clear_line_controller:
		return clear_line_controller.is_clear_animating_active()
	return false

## 启动逐行上涨计时器
## 仅当计时器未运行时才启动：Godot 的 Timer.start() 在已运行时调用会重置剩余时间，
## 若上涨队列已有行正在逐行上涨，新垃圾入队（_move_enter_to_rise_queue /
## add_allspin_garbage）会反复重置计时，导致已排队行的上涨被打断/无限推迟。
func _start_rise_timer() -> void:
	if not _rise_timer:
		return
	if _pending_rise_queue.is_empty():
		return
	if _rise_timer.is_stopped():
		_rise_timer.wait_time = garbage_rise_time_delay
		_rise_timer.start()

## 停止逐行上涨计时器
func _stop_rise_timer() -> void:
	if _rise_timer:
		_rise_timer.stop()

## 计时器触发：上涨一行
func _on_rise_timer_timeout() -> void:
	if _pending_rise_queue.is_empty():
		_stop_rise_timer()
		return
	
	# 消行延迟期间暂停逐行上涨：不清除队列、不丢弃行，延迟结束后恢复继续上涨
	if is_clear_delay_active():
		_stop_rise_timer()
		return
	
	# 取出队列最前面的一行
	var row_entry = _pending_rise_queue.pop_front()
	var holes: Array = row_entry["holes"]
	var _is_buffered: bool = row_entry.get("is_buffered", false)
	
	# 生成单行垃圾
	var generator = func(_i: int, _total: int) -> Array:
		var row_data = []
		for x in range(board_drawer.grid_width):
			var is_hole = false
			for hx in holes:
				if x == hx:
					is_hole = true
					break
			if is_hole:
				row_data.append(null)
			else:
				row_data.append(garbage_color)
		return row_data
	
	var success = force_raise_rows(1, generator)
	if not success:
		_stop_rise_timer()
		_pending_rise_queue.clear()
		return
	
	var start_y = _get_new_rows_start(1)
	garbage_rows_data[start_y] = holes.duplicate()
	
	# 继续计时
	if not _pending_rise_queue.is_empty():
		_rise_timer.start()
	else:
		_stop_rise_timer()

## 消行延迟结束后恢复待上涨的垃圾行（由 TetrisClearLine 在消行延迟计时结束时调用）。
## 先执行延迟期间暂存的一次性直接上涨，再恢复逐行上涨计时器。
func resume_rise_if_pending() -> void:
	# 执行延迟期间暂存的实心垃圾行上涨（不丢弃行）
	if not _deferred_solid_raises.is_empty():
		for count in _deferred_solid_raises:
			add_solid_garbage(count)
		_deferred_solid_raises.clear()
	# 执行延迟期间暂存的一次性直接上涨（如 Allspin 直接上涨）
	if not _deferred_direct_raises.is_empty():
		for deferred in _deferred_direct_raises:
			var holes: Array = deferred["all_holes"]
			var count: int = deferred["row_count"]
			if holes.is_empty():
				continue
			var gen = _generate_garbage_row_generator(holes[0], false)
			force_raise_rows(count, gen, true)
		_deferred_direct_raises.clear()
	# 恢复逐行上涨
	if not _pending_rise_queue.is_empty() and _rise_timer and _rise_timer.is_stopped():
		_rise_timer.wait_time = garbage_rise_time_delay
		_rise_timer.start()

## 抵消依次上涨队列中的行（优先于 enter_array 和 buffer）
## 返回被抵消的行数
func offset_rise_queue(remaining_damage: int) -> int:
	if remaining_damage <= 0 or _pending_rise_queue.is_empty():
		return 0
	
	var offset_count = 0
	while remaining_damage > 0 and not _pending_rise_queue.is_empty():
		_pending_rise_queue.pop_front()
		offset_count += 1
		remaining_damage -= 1
	
	# 如果队列空了就停止计时
	if _pending_rise_queue.is_empty():
		_stop_rise_timer()
	
	return offset_count

## 获取进入队列的大小（总行数，包括缓冲和逐行上涨队列）
func get_enter_queue_size() -> int:
	var total = 0
	for entry in garbage_enter_array:
		total += entry["count"]
	for entry in garbage_buffer:
		total += entry["count"]
	# 逐行模式下上涨队列中的行也是待处理垃圾行，必须计入
	total += _pending_rise_queue.size()
	return total

## 获取进入队列的原始数据（只返回正常队列）
## 返回 [{count: int, extra_hole_count: int}, ...]
func get_enter_queue() -> Array:
	return garbage_enter_array.duplicate()

## 获取缓冲队列的原始数据
func get_buffer_queue() -> Array:
	return garbage_buffer.duplicate()

## 清除所有垃圾行数据
func clear_all():
	garbage_enter_array.clear()
	garbage_output_array.clear()
	garbage_buffer.clear()
	pending_garbage_data = []
	is_garbage_locked = false
	garbage_rows_data.clear()
	solid_garbage_rows.clear()
	has_overflow = false
	current_active_hole = []
	_pending_rise_queue.clear()
	_deferred_direct_raises.clear()
	_deferred_solid_raises.clear()
	_stop_rise_timer()
	_refill_garbage_output()

## 清空版面中的垃圾行
func clear_garbage_from_board():
	for y in range(board_drawer.get_playable_height()):
		for x in range(board_drawer.grid_width):
			var color = board_drawer.get_cell_color(x, y)
			if color == garbage_color or color == garbage_empty_color or color == solid_garbage_color or color == buffered_garbage_color or color == buffered_garbage_empty_color:
				board_drawer.set_cell_color(x, y, null)
	garbage_rows_data.clear()
	solid_garbage_rows.clear()
	board_drawer.queue_redraw()

## 重置整个垃圾行系统
func reset_system():
	clear_all()
	clear_garbage_from_board()
