class_name ToggleBox
extends Control

## 可复用的切换方框组件
## 核心功能：显示带 ✓/✗ 标记的方框，点击在两个状态间切换
## 预留 id/value 支持外部数据绑定和读取


# ========== 信号 ==========

## 状态切换时触发
signal toggled(box_id: String, is_checked: bool, value: Variant)


# ========== 导出属性 ==========

## 唯一标识（用于外部区分不同的 ToggleBox）
@export var box_id: String = "toggle_default"

## 关联值（预留，用于后续绑定 buff/debuff 数据）
@export var value: Variant = null

## 方框大小（像素）
@export var box_size: int = 28

## 默认状态（true = ✓，false = ✗）
@export var default_checked: bool = true

## 边框颜色
@export var border_color: Color = Color(1, 1, 1, 0.8)

## 选中时标记颜色
@export var checked_color: Color = Color(0.3, 1, 0.3, 1)

## 未选中时标记颜色
@export var unchecked_color: Color = Color(1, 0.3, 0.3, 1)


# ========== 运行时状态 ==========

var is_checked: bool = false


# ========== 生命周期 ==========

func _ready() -> void:
	is_checked = default_checked
	custom_minimum_size = Vector2(box_size, box_size)
	size = Vector2(box_size, box_size)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# ========== 绘制 ==========

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	
	# 绘制背景
	draw_rect(rect, Color(0.15, 0.15, 0.15, 0.9), true)
	
	# 绘制边框
	draw_rect(rect, border_color, false, 1.5)
	
	# 绘制 ✓ 或 ✗
	var font: Font = ThemeDB.fallback_font
	var font_size: int = box_size - 6
	var text: String = "✓" if is_checked else "✗"
	var text_color: Color = checked_color if is_checked else unchecked_color
	
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2(
		(size.x - text_size.x) / 2.0,
		(size.y + text_size.y) / 2.0 - 8
	)
	
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)


# ========== 输入处理 ==========

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle()


func _on_mouse_entered() -> void:
	border_color = Color(1, 1, 1, 1)
	queue_redraw()


func _on_mouse_exited() -> void:
	border_color = Color(1, 1, 1, 0.8)
	queue_redraw()


# ========== 公开方法 ==========

## 切换状态
func toggle() -> void:
	_toggle()


## 设置选中状态（true = ✓，false = ✗）
func set_checked(checked: bool) -> void:
	is_checked = checked
	queue_redraw()
	toggled.emit(box_id, is_checked, value)


## 获取当前状态
func is_checked_state() -> bool:
	return is_checked


## 设置关联值
func set_box_value(val: Variant) -> void:
	value = val


## 设置唯一标识
func set_box_id(new_id: String) -> void:
	box_id = new_id


## 获取完整状态字典（供外部批量读取）
func get_state() -> Dictionary:
	return {
		"id": box_id,
		"checked": is_checked,
		"value": value
	}


## 重置为默认状态
func reset() -> void:
	set_checked(default_checked)


# ========== 内部方法 ==========

func _toggle() -> void:
	is_checked = not is_checked
	queue_redraw()
	toggled.emit(box_id, is_checked, value)
