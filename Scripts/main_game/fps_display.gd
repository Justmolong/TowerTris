extends Label
class_name FPSDisplay

# 阶段 / APM 取自公共数据区（TetrisGlobalData），不再用 %TowerController 直接抓节点

func _ready() -> void:
	# 设置文字样式
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 2)
	add_theme_font_size_override("font_size", 16)

func _process(_delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	text = "FPS: %d\nStage: %d  APM: %.1f" % [fps, TetrisGlobalData.current_stage, TetrisGlobalData.current_apm]
