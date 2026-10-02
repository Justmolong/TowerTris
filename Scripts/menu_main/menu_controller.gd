extends Node
class_name MenuController

## 主菜单控制器
## 负责主菜单的按钮交互和场景切换
## 注：界面自适应（居中 + 随窗口尺寸重排）由场景中的
## Panel(全屏锚点) → CenterContainer → VBoxContainer 完成，脚本无需参与布局

# 节点引用
@export var start_button: Button
@export var setting_button: Button
# @export var replay_button: Button  # 回放系统已禁用
@export var quit_button: Button

# 场景路径
@export var game_scene_path: String = "res://Tscns/buff_chose_area.tscn"
@export var setting_scene_path: String = "res://Tscns/setting_area.tscn"
# @export var replay_scene_path: String = "res://Tscns/tetris.tscn"  # 回放系统已禁用

# FileDialog 引用（回放系统已禁用）
# var _file_dialog: FileDialog = null
# var _is_dialog_open: bool = false

func _ready():
	_connect_signals()
	GlobalData.reset_stats()

func _connect_signals():
	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)
	if setting_button:
		setting_button.pressed.connect(_on_setting_button_pressed)
	# if replay_button:  # 回放系统已禁用
		# replay_button.pressed.connect(_on_replay_button_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)

func _on_start_button_pressed():
	# 已注释（调试噪音）：print("开始游戏")
	GlobalData.reset_stats()
	get_tree().change_scene_to_file(game_scene_path)

func _on_setting_button_pressed():
	# 已注释（调试噪音）：print("设置按钮被点击")
	get_tree().change_scene_to_file(setting_scene_path)

# ====== 回放按钮相关（已禁用） ======
# func _on_replay_button_pressed():
# 	print("选择回放文件")
# 	if _is_dialog_open:
# 		return
# 	_open_replay_file_dialog()
# 
# func _open_replay_file_dialog():
# 	if _file_dialog and is_instance_valid(_file_dialog):
# 		_file_dialog.queue_free()
# 		_file_dialog = null
# 	
# 	_file_dialog = FileDialog.new()
# 	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
# 	_file_dialog.access = FileDialog.ACCESS_USERDATA
# 	_file_dialog.filters = PackedStringArray(["*.json ; Replay files"])
# 	_file_dialog.title = "选择回放文件"
# 	_file_dialog.min_size = Vector2(600, 400)
# 	
# 	var replay_dir = "user://Replays/"
# 	DirAccess.make_dir_recursive_absolute(replay_dir)
# 	_file_dialog.current_dir = replay_dir
# 	
# 	add_child(_file_dialog)
# 	_is_dialog_open = true
# 	
# 	_file_dialog.file_selected.connect(_on_replay_file_selected)
# 	_file_dialog.canceled.connect(_on_replay_file_canceled)
# 	_file_dialog.popup_centered_ratio(0.7)
# 
# func _on_replay_file_selected(path: String):
# 	_is_dialog_open = false
# 	print("已选择回放文件: ", path)
# 	_cleanup_dialog()
# 	if path.is_empty():
# 		return
# 	GlobalData.set_pending_replay(path)
# 	get_tree().change_scene_to_file(replay_scene_path)
# 
# func _on_replay_file_canceled():
# 	_is_dialog_open = false
# 	print("取消选择回放文件")
# 	_cleanup_dialog()
# 
# func _cleanup_dialog():
# 	if _file_dialog and is_instance_valid(_file_dialog):
# 		_file_dialog.queue_free()
# 		_file_dialog = null

func _on_quit_button_pressed():
	# 已注释（调试噪音）：print("退出游戏")
	get_tree().quit()

func _exit_tree():
	# 清理对话框（回放系统已禁用）
	# _cleanup_dialog()
	# _is_dialog_open = false
	pass
