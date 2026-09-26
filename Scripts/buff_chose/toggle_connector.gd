extends Control
class_name ToggleConnector

## 选框连接线绘制器
## 在选框行上方绘制水平连接线（穿过选框中心，但跳过选框内部线段）


# ========== 导出属性 ==========

## 连接线颜色
@export var line_color: Color = Color(0.7, 0.7, 0.7, 0.8)

## 连接线粗细（像素）
@export var line_width: float = 5.0


# ========== 生命周期 ==========

func _ready() -> void:
	# 在第一帧布局完成后，同步尺寸为父容器（ToggleRow）大小
	_resize_to_parent()
	queue_redraw()


func _process(_delta: float) -> void:
	# 持续同步尺寸（应对容器大小变化）
	if get_parent() is HBoxContainer:
		var parent := get_parent() as HBoxContainer
		if size != parent.size:
			size = parent.size
			queue_redraw()


func _resize_to_parent() -> void:
	var parent := get_parent() as HBoxContainer
	if parent:
		size = parent.size


func _draw() -> void:
	var toggle_row := get_parent() as HBoxContainer
	if not toggle_row or toggle_row.size.x <= 0:
		return
	
	# ConnectorLine 自身在行内的偏移（行内前面有 ChoseType Label 等节点时不为 0）
	# 选框坐标是相对于 toggle_row 的，而 draw_line 使用的是 ConnectorLine 本地坐标，
	# 因此所有坐标都要减去 ConnectorLine 的位置偏移，否则提示线会整体偏移。
	var offset := position
	
	# 收集所有 ToggleBox 的中心 X 坐标（相对于 toggle_row）
	var centers: Array[float] = []
	for child in toggle_row.get_children():
		var tb := child as ToggleBox
		if tb:
			var cx := tb.position.x + tb.size.x * 0.5
			centers.append(cx)
	
	if centers.size() < 2:
		return
	
	# 中心 Y（相对于 toggle_row 的坐标空间）
	var center_y := toggle_row.size.y * 0.5
	
	# 画出相邻选框之间的线段（跳过选框内部）
	var half_box := 16.0  # 选框宽 32px 的一半
	for i in range(centers.size() - 1):
		var x1 := centers[i] + half_box - offset.x     # 左侧选框右边缘
		var x2 := centers[i + 1] - half_box - offset.x # 右侧选框左边缘
		if x2 > x1:
			draw_line(Vector2(x1, center_y - offset.y), Vector2(x2, center_y - offset.y), line_color, line_width)
