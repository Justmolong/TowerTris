extends Node2D
class_name SpikeDisplay

## Spike 数字显示
## 在落块（消行）位置弹出「黑字 + 白色描边」的累加攻击数字，用来直观显示连续攻击形成的 spike。
##
## 规则：
##   - 每次消行打出攻击 → TetrisClearLine 调 add_spike(damage, 落块中心)
##   - 数字在条目出现后的 reset_time（默认 1s）内可以续接：续上时「立刻」变成累加后的数字，
##     并刷新透明度、淡出计时、落点与漂移速度（elapsed 归零 → 回到 100% 不透明、fade_duration 淡出重新开始；
##     位置/旋转/漂移方向重新随机，并按 drift_speed 重新起速）
##   - 淡出总时长 fade_duration（默认 2s），全程持续渐出，淡完即消失
##   - 淡出进度到达 reset_time 即「spike 重置」：之后新打出的攻击不会与这条累加，而是另起一条；
##     被重置的这条仍然按原样淡出消失
##   - 位置：初始 XY 偏移随机；运动方向随机（XY 任意）；旋转 ±rotate_deg；
##     速度按 drift_decay 指数衰减 —— 先快后慢的加速度效果
##   - 字号随 spike 数值变大而变大，增长趋势逐渐变缓（对数），并有上限

class SpikeEntry:
	var value: int = 0
	var text: String = ""
	var position: Vector2 = Vector2.ZERO
	var drift: Vector2 = Vector2.ZERO        # 漂移初速度（像素/秒，方向随机）
	var rotation_deg: float = 0.0            # 旋转角度（度）
	var font_size: float = 24.0
	var elapsed: float = 0.0                 # 已存在时间（同时用于淡出与 spike 重置判定）

@export var board_drawer: TetrisBoardDrawer      # 用于取 cell_size（未连时自动查找 ../TetrisBoardDrawer）
@export var enabled: bool = true
@export var text_format: String = "%d"           # 数字文本格式
@export var font_size_ratio: float = 0.9         # 基础字号（相对 cell_size）
@export var font_grow: float = 1.1               # 随 spike 增大而变大（对数，增长逐渐变缓）
@export var grow_ref: float = 10.0               # 字号增长的参考值（spike 点数）
@export var max_font_scale: float = 2.4          # 字号增长上限倍数
@export var text_color: Color = Color.BLACK
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.95)  # 字体边缘的白边
@export var outline_size_ratio: float = 0.18     # 白边厚度（相对字号）
@export var outline_size_min: int = 2            # 白边最小像素厚度
@export var fade_duration: float = 2.0           # 淡出总时长（秒），全程持续渐出
@export var reset_time: float = 1.0              # 累加窗口（秒）：淡出进行到此即 spike 重置（TetrisClearLine 会把它同步成自己的 Attack 累积窗口 damage_display_duration，两者默认都是 1s）
@export var drift_speed: float = 60.0            # 漂移初速度（像素/秒）
@export var drift_decay: float = 5.5             # 速度衰减速率（/秒）：越大越快停 → 先快后慢
@export var spread: float = 18.0                 # 初始位置随机偏移（像素）
@export var rotate_deg: float = 10.0             # 旋转角度上限（±度）

var _entries: Array = []                         # 在场条目（含正在累加的那条）
var _active: SpikeEntry = null                   # 仍在 reset_time 窗口内、可续接的条目

@onready var _rng: RandomNumberGenerator = RandomManager.get_random("SPIKE")


func _ready() -> void:
	if not board_drawer:
		board_drawer = get_node_or_null("../TetrisBoardDrawer")


## 新增一次 spike（本次消行打出的攻击）。amount <= 0 时忽略。
## anchor_pos：落块（被消掉的方块）中心的世界坐标
func add_spike(amount: int, anchor_pos: Vector2) -> void:
	if not enabled or amount <= 0:
		return
	_prune_expired()
	# reset_time 内续上 → 立刻变成累加后的数字，并整体刷新：
	#   - 数字 / 字号：按累加后的值重算
	#   - 透明度与淡出计时：elapsed 归零 → 回到 100% 不透明、fade_duration 淡出重新开始（1s 累加窗口随之续上）
	#   - 位置 / 旋转 / 漂移初速度：重新落到这次攻击的落块点，并按 drift_speed 重新起速
	#     （否则会沿用已经衰减到接近 0 的旧速度，续接时看起来弹出去却不动）
	if _active != null and _active.elapsed < reset_time:
		_active.value += amount
		_active.elapsed = 0.0
		_randomize_placement(_active, anchor_pos)
		_update_entry_text(_active)
		queue_redraw()
		return
	# 否则另起一条；上一条若还在淡出，就让它继续自然消失（不与新攻击累加）
	var entry := SpikeEntry.new()
	entry.value = amount
	_randomize_placement(entry, anchor_pos)
	_update_entry_text(entry)
	_entries.append(entry)
	_active = entry
	queue_redraw()


## 给条目随机「漂移初速度 + 初始 XY 偏移 + 旋转角」（新建、累加续接时共用）
func _randomize_placement(entry: SpikeEntry, anchor_pos: Vector2) -> void:
	var angle: float = _rng.randf_range(0.0, TAU)        # XY 移动方向随机
	entry.drift = Vector2(cos(angle), sin(angle)) * drift_speed   # 按 drift_speed 重新起速（先快后慢）
	entry.position = anchor_pos + Vector2(_rng.randf_range(-spread, spread),
		_rng.randf_range(-spread, spread))               # 初始 XY 偏移随机
	entry.rotation_deg = _rng.randf_range(-rotate_deg, rotate_deg)


## 清空全部显示（重开/切场景时可用）
func clear_all() -> void:
	_entries.clear()
	_active = null
	queue_redraw()


## 当前仍在累加窗口内的数字（无则 0），供调试/外部查询
func get_active_value() -> int:
	if _active != null and _active.elapsed < reset_time:
		return _active.value
	return 0


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	for entry: SpikeEntry in _entries:
		entry.elapsed += delta
		entry.position += entry.drift * delta
		if drift_decay > 0.0:
			entry.drift *= exp(-drift_decay * delta)     # 指数衰减：先快后慢
	# 淡出进度到达 reset_time → spike 重置（这条之后只能自然淡出，不再接受累加）
	if _active != null and _active.elapsed >= reset_time:
		_active = null
	_prune_expired()
	queue_redraw()


## 丢弃已经淡出完毕的条目
func _prune_expired() -> void:
	if _entries.is_empty():
		return
	var kept: Array = []
	for entry: SpikeEntry in _entries:
		if entry.elapsed < fade_duration:
			kept.append(entry)
	if kept.size() != _entries.size():
		_entries = kept
		if _active != null and not _entries.has(_active):
			_active = null


## 刷新条目的文本与字号（数值变化时调用）
func _update_entry_text(entry: SpikeEntry) -> void:
	entry.text = text_format % entry.value
	entry.font_size = _font_size_for(entry.value)


## 字号：随 spike 数值变大而变大，但增长逐渐变缓（对数），并有上限
func _font_size_for(value: int) -> float:
	var cell: float = float(board_drawer.cell_size) if board_drawer else 24.0
	var ref: float = maxf(grow_ref, 0.001)
	var t: float = log(1.0 + maxf(float(value), 0.0) / ref)
	return cell * font_size_ratio * clampf(1.0 + font_grow * t, 1.0, maxf(max_font_scale, 1.0))


func _draw() -> void:
	if _entries.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	for entry: SpikeEntry in _entries:
		if entry.text.is_empty():
			continue
		# 全程持续渐出：透明度随时间线性降到 0
		var alpha: float = clampf(1.0 - entry.elapsed / maxf(fade_duration, 0.001), 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var font_size_int: int = maxi(1, roundi(entry.font_size))
		var text_size: Vector2 = font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int)
		var fg: Color = text_color
		fg.a *= alpha
		var edge: Color = outline_color
		edge.a *= alpha
		# 白边厚度随字号一起变大（有最小像素值，避免小字号时看不见）
		var outline_size: int = maxi(outline_size_min, roundi(entry.font_size * outline_size_ratio))
		# 文本以 position 为中心（draw_string 的 y 是基线），旋转也绕该中心
		var text_pos := Vector2(-text_size.x * 0.5, font.get_ascent(font_size_int) - text_size.y * 0.5)
		draw_set_transform(entry.position, deg_to_rad(entry.rotation_deg), Vector2.ONE)
		# 先画白色描边（字体轮廓向外扩 outline_size 像素），再画黑字覆盖上去
		draw_string_outline(font, text_pos, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int,
			outline_size, edge)
		draw_string(font, text_pos, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int, fg)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
