extends Control
class_name SettingArea

## 设置场景控制器
## 负责键位配置、速度调整和设置保存

# ========== 节点引用 ==========
# 键位按钮
@export var key_left_button: Button
@export var key_right_button: Button
@export var key_soft_drop_button: Button
@export var key_hard_drop_button: Button
@export var key_left_spin_button: Button
@export var key_right_spin_button: Button
@export var key_swap_spin_button: Button
@export var key_hold_button: Button

# 速度控制
@export var das_slider: HSlider
@export var das_value_label: Label
@export var arr_slider: HSlider
@export var arr_value_label: Label
@export var softdrop_slider: HSlider
@export var softdrop_value_label: Label

# 按钮
@export var save_button: Button
@export var reset_button: Button
@export var back_button: Button

# 提示标签
@export var hint_label: Label

# ========== 状态变量 ==========
var current_settings: Dictionary = {}
var waiting_for_key: bool = false
var waiting_key_action: String = ""
var waiting_button: Button = null

# 键位动作列表
var action_list: Array = [
	"LeftMove", "RightMove", "SoftDrop", "HardDrop",
	"LeftSpin", "RightSpin", "SwapSpin", "HoldBlock"
]

# 动作名 → 按钮映射
var action_to_button: Dictionary = {}

# 动作名 → 设置键名映射
var action_to_setting_key: Dictionary = {
	"LeftMove": "key_left",
	"RightMove": "key_right",
	"SoftDrop": "key_soft_drop",
	"HardDrop": "key_hard_drop",
	"LeftSpin": "key_left_spin",
	"RightSpin": "key_right_spin",
	"SwapSpin": "key_swap_spin",
	"HoldBlock": "key_hold"
}

func _ready():
	# 构建按钮映射
	action_to_button = {
		"LeftMove": key_left_button,
		"RightMove": key_right_button,
		"SoftDrop": key_soft_drop_button,
		"HardDrop": key_hard_drop_button,
		"LeftSpin": key_left_spin_button,
		"RightSpin": key_right_spin_button,
		"SwapSpin": key_swap_spin_button,
		"HoldBlock": key_hold_button
	}
	
	# 加载设置
	_load_settings()
	
	# 连接信号
	_connect_signals()
	
	# 更新UI
	_update_ui()
	
	# 设置滑块样式
	_setup_slider_styles()

## 加载设置
func _load_settings():
	if UserSetting.setting_file_exists():
		current_settings = UserSetting.load_settings()
		# 应用键位到InputMap
		UserSetting.apply_key_bindings_from_dict(current_settings)
		# 已注释（调试噪音）：print("已加载用户设置")
	else:
		current_settings = UserSetting.get_default_settings()
		UserSetting.apply_default_key_bindings()
		# 已注释（调试噪音）：print("未找到配置文件，使用默认设置")

## 连接信号
func _connect_signals():
	# 键位按钮
	if key_left_button:
		key_left_button.pressed.connect(_on_key_button_pressed.bind("LeftMove", key_left_button))
	if key_right_button:
		key_right_button.pressed.connect(_on_key_button_pressed.bind("RightMove", key_right_button))
	if key_soft_drop_button:
		key_soft_drop_button.pressed.connect(_on_key_button_pressed.bind("SoftDrop", key_soft_drop_button))
	if key_hard_drop_button:
		key_hard_drop_button.pressed.connect(_on_key_button_pressed.bind("HardDrop", key_hard_drop_button))
	if key_left_spin_button:
		key_left_spin_button.pressed.connect(_on_key_button_pressed.bind("LeftSpin", key_left_spin_button))
	if key_right_spin_button:
		key_right_spin_button.pressed.connect(_on_key_button_pressed.bind("RightSpin", key_right_spin_button))
	if key_swap_spin_button:
		key_swap_spin_button.pressed.connect(_on_key_button_pressed.bind("SwapSpin", key_swap_spin_button))
	if key_hold_button:
		key_hold_button.pressed.connect(_on_key_button_pressed.bind("HoldBlock", key_hold_button))
	
	# 速度滑条
	if das_slider:
		das_slider.value_changed.connect(_on_das_changed)
	if arr_slider:
		arr_slider.value_changed.connect(_on_arr_changed)
	if softdrop_slider:
		softdrop_slider.value_changed.connect(_on_softdrop_changed)
	
	# 按钮
	if save_button:
		save_button.pressed.connect(_on_save_pressed)
	if reset_button:
		reset_button.pressed.connect(_on_reset_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

## 设置滑块样式
func _setup_slider_styles():
	var sliders = [das_slider, arr_slider, softdrop_slider]
	for slider in sliders:
		if slider:
			slider.custom_minimum_size.x = 200

## 更新UI
func _update_ui():
	# 更新键位按钮文本 - 从InputMap读取实际按键
	for action in action_list:
		var button = action_to_button[action]
		if button:
			var key_name = UserSetting.get_key_name_for_action(action)
			if key_name.is_empty():
				key_name = "未绑定"
			button.text = key_name
	
	# 更新速度值
	if das_slider:
		das_slider.value = current_settings.get("move_das", 0.1) * 100
	if das_value_label:
		das_value_label.text = "%.3fs" % current_settings.get("move_das", 0.1)
	
	if arr_slider:
		arr_slider.value = current_settings.get("move_arr", 0.0) * 100
	if arr_value_label:
		arr_value_label.text = "%.3fs" % current_settings.get("move_arr", 0.0)
	
	if softdrop_slider:
		softdrop_slider.value = current_settings.get("softdrop_delay", 0.1) * 100
	if softdrop_value_label:
		softdrop_value_label.text = "%.3fs" % current_settings.get("softdrop_delay", 0.1)

## 更新单个键位按钮
func _update_key_button(button: Button, action: String):
	if button:
		var key_name = UserSetting.get_key_name_for_action(action)
		if key_name.is_empty():
			key_name = "未绑定"
		button.text = key_name

# ========== 键位设置 ==========

## 键位按钮按下
func _on_key_button_pressed(action: String, button: Button):
	if waiting_for_key:
		_cancel_waiting()
	
	waiting_for_key = true
	waiting_key_action = action
	waiting_button = button
	button.text = "按下按键..."
	
	if hint_label:
		hint_label.text = "请按下要绑定的按键..."

## 取消等待
func _cancel_waiting():
	waiting_for_key = false
	waiting_key_action = ""
	if waiting_button:
		_update_key_button(waiting_button, waiting_key_action)
		waiting_button = null
	if hint_label:
		hint_label.text = ""

## 处理按键输入
func _input(event):
	if not waiting_for_key:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		var key_name = OS.get_keycode_string(keycode)
		
		# 清除其他动作中相同的按键（覆盖模式）
		_clear_conflicting_keys(keycode)
		
		# 更新设置
		_set_key_for_action(waiting_key_action, keycode)
		
		# 更新按钮显示
		if waiting_button:
			waiting_button.text = key_name
		
		# 重置等待状态
		waiting_for_key = false
		waiting_key_action = ""
		waiting_button = null
		
		if hint_label:
			hint_label.text = "按键已绑定: %s" % key_name

## 清除其他动作中指定的按键（覆盖模式）
## 当新绑定的按键已被其他动作使用时，清除其他动作中的该按键
func _clear_conflicting_keys(keycode: int) -> void:
	var key_name := OS.get_keycode_string(keycode)
	for action in action_list:
		if action == waiting_key_action:
			continue
		
		var events := InputMap.action_get_events(action)
		var has_conflict := false
		for ev in events:
			if ev is InputEventKey and ev.keycode == keycode:
				has_conflict = true
				break
		
		if has_conflict:
			# 清除该动作的按键
			InputMap.action_erase_events(action)
			
			# 更新对应的按钮显示为"未绑定"
			var button: Button = action_to_button.get(action) as Button
			if button:
				button.text = "未绑定"
			
			# 已注释（调试噪音）：print("按键覆盖：动作 \"%s\" 的按键 \"%s\" 已被动作 \"%s\" 覆盖" % [action, key_name, waiting_key_action])

## 设置按键到动作
func _set_key_for_action(action: String, keycode: int):
	# 清除原有按键
	InputMap.action_erase_events(action)
	
	# 创建新按键事件
	var key_event = InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)
	
	# 获取按键名称
	var key_name = OS.get_keycode_string(keycode)
	
	# 更新设置字典中的按键名称
	var setting_key = action_to_setting_key[action]
	current_settings[setting_key] = key_name

# ========== 速度调整 ==========

func _on_das_changed(value: float):
	current_settings["move_das"] = value / 100.0
	if das_value_label:
		das_value_label.text = "%.3fs" % current_settings["move_das"]

func _on_arr_changed(value: float):
	current_settings["move_arr"] = value / 100.0
	if arr_value_label:
		arr_value_label.text = "%.3fs" % current_settings["move_arr"]

func _on_softdrop_changed(value: float):
	current_settings["softdrop_delay"] = value / 100.0
	if softdrop_value_label:
		softdrop_value_label.text = "%.3fs" % current_settings["softdrop_delay"]

# ========== 按钮功能 ==========

## 保存设置
func _on_save_pressed():
	if UserSetting.save_settings(current_settings):
		if hint_label:
			hint_label.text = "设置已保存！"
			await get_tree().create_timer(2.0).timeout
			if hint_label and hint_label.text == "设置已保存！":
				hint_label.text = ""
	else:
		if hint_label:
			hint_label.text = "保存失败！"
			await get_tree().create_timer(2.0).timeout
			if hint_label and hint_label.text == "保存失败！":
				hint_label.text = ""

## 重置为默认设置
func _on_reset_pressed():
	# 获取默认设置
	current_settings = UserSetting.get_default_settings()
	
	# 应用默认键位到InputMap
	UserSetting.apply_default_key_bindings()
	
	# 更新UI
	_update_ui()
	
	if hint_label:
		hint_label.text = "已重置为默认设置！"
		await get_tree().create_timer(2.0).timeout
		if hint_label and hint_label.text == "已重置为默认设置！":
			hint_label.text = ""

## 返回主菜单
func _on_back_pressed():
	# 保存设置
	UserSetting.save_settings(current_settings)
	get_tree().change_scene_to_file("res://Tscns/main_menu.tscn")

## 获取设置（供其他场景使用）
func get_settings() -> Dictionary:
	return current_settings
