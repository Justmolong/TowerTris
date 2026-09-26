extends Node

## UI 缩放管理器（已废弃）
## 此文件仅用于满足 autoload 引用，实际缩放已由各控制器内部硬编码为 1.0

signal scale_changed(new_scale: float)

static func get_scale() -> float:
	return 1.0

func _ready():
	scale_changed.emit(1.0)
