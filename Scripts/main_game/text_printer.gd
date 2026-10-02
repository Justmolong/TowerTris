extends Node2D
class_name TextPrinter

## 文本打印器
## 供其他节点在指定位置显示文本，并支持透明淡出后消失。
## 特性：
##   - 同时管理多个文本（以 key 区分）
##   - 同一 key 可叠加多条文本（非持久文本每次显示都会新生成一条，不会覆盖之前正在淡出的文本）
##   - 每个文本可独立控制透明度、颜色、字号、对齐方式
##   - persistent=true 的文本为常驻显示，由调用方负责移除（同 key 只保留最新一条，用于 btb/damage）
##   - persistent=false 的文本显示一段时间后向左漂移并自然淡出消失（每次调用都会新增一条，多条在原位叠加、各自独立淡出）

class TextEntry:
	var key: String = ""
	var text: String = ""
	var position: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var outline_color: Color = Color.BLACK
	var font_size: float = 20.0
	var persistent: bool = false       # 常驻显示，不自动淡出
	var base_opacity: float = 1.0      # 显示起始透明度（半透明可用 0.x）
	var opacity: float = 1.0           # 当前透明度（淡出时递减）
	var display_duration: float = 1.0  # 保持显示的时间（秒）
	var fade_duration: float = 0.8     # 淡出时长（秒）
	var elapsed: float = 0.0           # 已显示时间
	var fade_elapsed: float = 0.0      # 已淡出时间
	var drift: Vector2 = Vector2.ZERO  # 漂移速度（像素/秒，向左为负X）
	var alignment: int = HORIZONTAL_ALIGNMENT_RIGHT


## key -> Array[TextEntry]
var _entries: Dictionary = {}

## 漂移减速速率（/秒）：初始速度快，随时间指数衰减，最终停下
const DRIFT_DECEL_PER_SEC: float = 0.9

const OUTLINE_OFFSETS: Array = [
	Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
]


## 显示一个文本。
## 非持久文本（persistent=false）：每次调用都会新增一条并在原位叠加，不会覆盖正在淡出的文本。
## 持久文本（persistent=true）：同 key 只保留最新一条并更新其内容。
## 参数：
##   key            标识（用于之后指定该文本让其消失）
##   text           显示的文本内容
##   position       显示位置（Node2D 世界坐标）
##   color          文本颜色
##   outline_color  描边颜色
##   font_size      字号
##   persistent     为 true 时常驻显示，不会自动淡出
##   opacity        显示时的透明度（0-1，半透明用 0.5~0.8）
##   display_duration 保持显示的时间（秒），之后开始淡出
##   fade_duration  淡出时长（秒）
##   drift          漂移速度（像素/秒）
##   alignment      文本对齐方式（相对 position 的锚点）
func show_text(
	key: String,
	text: String,
	pos: Vector2,
	color: Color = Color.WHITE,
	outline_color: Color = Color.BLACK,
	font_size: float = 20.0,
	persistent: bool = false,
	opacity: float = 1.0,
	display_duration: float = 1.0,
	fade_duration: float = 0.8,
	drift: Vector2 = Vector2.ZERO,
	alignment: int = HORIZONTAL_ALIGNMENT_RIGHT
) -> void:
	var list = _entries.get(key)
	var entry: TextEntry
	if persistent and list != null and not list.is_empty():
		# 持久文本：更新已有的最新一条，不叠加
		entry = list[0]
		_fill_entry(entry, key, text, pos, color, outline_color, font_size,
			persistent, opacity, display_duration, fade_duration, drift, alignment)
	else:
		entry = TextEntry.new()
		_fill_entry(entry, key, text, pos, color, outline_color, font_size,
			persistent, opacity, display_duration, fade_duration, drift, alignment)
		# 叠加：多条非持久文本在原位叠加显示（不向下错开，各自独立淡出）
		if list == null:
			list = []
			_entries[key] = list
		list.append(entry)
	queue_redraw()


func _fill_entry(
	entry: TextEntry,
	key: String,
	text: String,
	pos: Vector2,
	color: Color,
	outline_color: Color,
	font_size: float,
	persistent: bool,
	opacity: float,
	display_duration: float,
	fade_duration: float,
	drift: Vector2,
	alignment: int
) -> void:
	entry.key = key
	entry.text = text
	entry.position = pos
	entry.color = color
	entry.outline_color = outline_color
	entry.font_size = font_size
	entry.persistent = persistent
	entry.base_opacity = clampf(opacity, 0.0, 1.0)
	entry.opacity = clampf(opacity, 0.0, 1.0)
	entry.display_duration = display_duration
	entry.fade_duration = maxf(fade_duration, 0.0)
	entry.drift = drift
	entry.alignment = alignment
	entry.elapsed = 0.0
	entry.fade_elapsed = 0.0


## 更新指定 key 的文本内容（影响该 key 的所有条目，不影响位置与生命周期）
func update_text(key: String, new_text: String) -> void:
	var list = _entries.get(key)
	if list == null:
		return
	for e: TextEntry in list:
		e.text = new_text
	queue_redraw()


## 移动指定 key 的所有文本到新位置
func set_text_position(key: String, new_position: Vector2) -> void:
	var list = _entries.get(key)
	if list == null:
		return
	for e: TextEntry in list:
		e.position = new_position
	queue_redraw()


## 指定 key 的所有文本透明度控制（0-1）
func set_text_opacity(key: String, opacity: float) -> void:
	var list = _entries.get(key)
	if list == null:
		return
	var alpha: float = clampf(opacity, 0.0, 1.0)
	for e: TextEntry in list:
		e.base_opacity = alpha
		e.opacity = alpha
	queue_redraw()


## 指定 key 的所有文本颜色控制
func set_text_color(key: String, color: Color) -> void:
	var list = _entries.get(key)
	if list == null:
		return
	for e: TextEntry in list:
		e.color = color
	queue_redraw()


## 让指定文本立即消失
func remove_text(key: String) -> void:
	_entries.erase(key)
	queue_redraw()


## 让指定 key 的所有文本淡出后消失（对常驻文本也可用）
func fade_out_text(key: String, fade_duration: float = 0.5) -> void:
	var list = _entries.get(key)
	if list == null:
		return
	for e: TextEntry in list:
		e.persistent = false
		e.display_duration = 0.0
		e.fade_duration = maxf(fade_duration, 0.0)
		e.elapsed = 0.0
		e.fade_elapsed = 0.0
	queue_redraw()


## 清空所有文本（含常驻文本）
func clear_all() -> void:
	_entries.clear()
	queue_redraw()


## 是否存在指定 key 的文本
func has_text(key: String) -> bool:
	var list = _entries.get(key)
	return list != null and not list.is_empty()


## 获取指定 key 的文本内容（取最新一条）
func get_text(key: String) -> String:
	var list = _entries.get(key)
	if list == null or list.is_empty():
		return ""
	return list[list.size() - 1].text


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var to_delete: Array[String] = []
	for key: String in _entries:
		var list: Array = _entries[key]
		var remaining: Array = []
		for entry: TextEntry in list:
			if entry.persistent:
				remaining.append(entry)
				continue
			entry.elapsed += delta
			# 加速度移动：初始速度快，随时间指数衰减减速
			entry.position += entry.drift * delta
			entry.drift *= maxf(0.0, 1.0 - DRIFT_DECEL_PER_SEC * delta)
			# 淡出与移动并行：显示初期即开始淡出（与漂移同时进行），fade_duration 为淡出总时长
			var t: float = 1.0
			if entry.fade_duration > 0.0:
				t = clampf((entry.elapsed - entry.display_duration) / entry.fade_duration, 0.0, 1.0)
			entry.opacity = entry.base_opacity * (1.0 - t)
			if t >= 1.0:
				continue  # 淡出完成，丢弃这条
			remaining.append(entry)
		if remaining.is_empty():
			to_delete.append(key)
		else:
			_entries[key] = remaining
	for key: String in to_delete:
		_entries.erase(key)
	queue_redraw()


func _draw() -> void:
	if _entries.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	for key: String in _entries:
		var list: Array = _entries[key]
		for entry: TextEntry in list:
			if entry.text.is_empty() or entry.opacity <= 0.0:
				continue
			var font_size_int: int = maxi(1, roundi(entry.font_size))
			var draw_pos: Vector2 = entry.position
			if entry.alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				var text_size: Vector2 = font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int)
				draw_pos.x -= text_size.x
			var color: Color = entry.color
			color.a *= entry.opacity
			var outline: Color = entry.outline_color
			outline.a *= entry.opacity
			for offset: Vector2 in OUTLINE_OFFSETS:
				draw_string(font, draw_pos + offset, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int, outline)
			draw_string(font, draw_pos, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int, color)
