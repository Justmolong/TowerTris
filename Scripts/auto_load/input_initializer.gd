extends Node

## 输入初始化器
## 游戏启动时加载键位设置

func _ready():
	# 初始化设置
	UserSetting.initialize_settings()
	# 已注释（调试噪音）：print("输入系统初始化完成")
