extends Resource
class_name UserSetting

## 用户设置数据类
## 使用JSON格式保存和加载用户自定义设置

const SAVEFILE_PATH = "user://Savedatas/user_setting.json"

## 默认键位映射（动作名称 → 按键代码）
static func get_default_key_bindings() -> Dictionary:
	return {
		"LeftMove": KEY_LEFT,
		"RightMove": KEY_RIGHT,
		"SoftDrop": KEY_DOWN,
		"HardDrop": KEY_SPACE,
		"LeftSpin": KEY_Z,
		"RightSpin": KEY_X,
		"SwapSpin": KEY_A,
		"HoldBlock": KEY_C
	}

## 默认键位名称映射（动作名称 → 按键名称字符串）
static func get_default_key_names() -> Dictionary:
	return {
		"LeftMove": "Left",
		"RightMove": "Right",
		"SoftDrop": "Down",
		"HardDrop": "Space",
		"LeftSpin": "Z",
		"RightSpin": "X",
		"SwapSpin": "A",
		"HoldBlock": "C"
	}

## 获取默认设置字典
static func get_default_settings() -> Dictionary:
	return {
		# 键位设置（存储按键名称字符串，如 "Z", "X", "Left" 等）
		"key_left": "Left",
		"key_right": "Right",
		"key_soft_drop": "Down",
		"key_hard_drop": "Space",
		"key_left_spin": "Z",
		"key_right_spin": "X",
		"key_swap_spin": "A",
		"key_hold": "C",
		# 速度设置
		"move_das": 0.1,
		"move_arr": 0.0,
		"softdrop_delay": 0.1
	}

## 动作名称列表
static func get_action_list() -> Array:
	return ["LeftMove", "RightMove", "SoftDrop", "HardDrop", "LeftSpin", "RightSpin", "SwapSpin", "HoldBlock"]

## 动作名称 → 设置键名映射
static func get_action_to_setting_key() -> Dictionary:
	return {
		"LeftMove": "key_left",
		"RightMove": "key_right",
		"SoftDrop": "key_soft_drop",
		"HardDrop": "key_hard_drop",
		"LeftSpin": "key_left_spin",
		"RightSpin": "key_right_spin",
		"SwapSpin": "key_swap_spin",
		"HoldBlock": "key_hold"
	}

## 从按键名称获取按键代码
static func get_keycode_from_name(key_name: String) -> int:
	# 处理特殊按键名称
	match key_name:
		"Left": return KEY_LEFT
		"Right": return KEY_RIGHT
		"Up": return KEY_UP
		"Down": return KEY_DOWN
		"Space": return KEY_SPACE
		"Enter": return KEY_ENTER
		"Escape": return KEY_ESCAPE
		"Tab": return KEY_TAB
		"Shift": return KEY_SHIFT
		"Ctrl": return KEY_CTRL
		"Alt": return KEY_ALT
		_:
			# 尝试直接查找
			var keycode = OS.find_keycode_from_string(key_name)
			if keycode != 0:
				return keycode
			return -1

## 从按键代码获取按键名称
static func get_key_name_from_keycode(keycode: int) -> String:
	return OS.get_keycode_string(keycode)

## 获取动作对应的按键名称（从InputMap读取）
static func get_key_name_for_action(action: String) -> String:
	var events = InputMap.action_get_events(action)
	if events.is_empty():
		return ""
	var event = events[0]
	if event is InputEventKey:
		return OS.get_keycode_string(event.keycode)
	return ""

## 应用默认键位到InputMap
static func apply_default_key_bindings():
	var defaults = get_default_key_bindings()
	for action in defaults:
		var keycode = defaults[action]
		InputMap.action_erase_events(action)
		var key_event = InputEventKey.new()
		key_event.keycode = keycode
		InputMap.action_add_event(action, key_event)

## 从设置字典应用键位到InputMap
static func apply_key_bindings_from_dict(settings: Dictionary):
	var action_list = get_action_list()
	var action_to_key = get_action_to_setting_key()
	
	for action in action_list:
		var setting_key = action_to_key[action]
		if settings.has(setting_key):
			var key_name = settings[setting_key]
			var keycode = get_keycode_from_name(key_name)
			if keycode != -1:
				# 清除原有按键
				InputMap.action_erase_events(action)
				# 创建新按键事件
				var key_event = InputEventKey.new()
				key_event.keycode = keycode
				InputMap.action_add_event(action, key_event)
			else:
				pass
				# 已注释（调试噪音）：print("警告: 未知按键名称 ", key_name, " 用于动作 ", action)

## 获取当前所有动作的按键名称（用于保存）
static func get_current_key_names() -> Dictionary:
	var result = {}
	var action_list = get_action_list()
	var action_to_key = get_action_to_setting_key()
	
	for action in action_list:
		var key_name = get_key_name_for_action(action)
		if key_name.is_empty():
			# 如果未绑定，使用默认值
			var default_names = get_default_key_names()
			key_name = default_names.get(action, "")
		var setting_key = action_to_key[action]
		result[setting_key] = key_name
	
	return result

## 保存设置到JSON文件
static func save_settings(settings: Dictionary) -> bool:
	var dir = DirAccess.open("user://Savedatas")
	if not dir:
		DirAccess.make_dir_recursive_absolute("user://Savedatas")
	
	var json_string = JSON.stringify(settings, "\t")
	var file = FileAccess.open(SAVEFILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		# 已注释（调试噪音）：print("设置已保存到: ", SAVEFILE_PATH)
		return true
	else:
		push_error("保存设置失败: ", SAVEFILE_PATH)
		return false

## 从JSON文件加载设置
static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SAVEFILE_PATH):
		# 已注释（调试噪音）：print("配置文件不存在，使用默认设置")
		return get_default_settings()
	
	var file = FileAccess.open(SAVEFILE_PATH, FileAccess.READ)
	if not file:
		push_error("无法打开配置文件: ", SAVEFILE_PATH)
		return get_default_settings()
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("解析配置文件失败: ", json.get_error_message())
		return get_default_settings()
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("配置文件格式错误")
		return get_default_settings()
	
	# 合并默认值（确保所有字段都存在）
	var default_settings = get_default_settings()
	for key in default_settings:
		if not data.has(key):
			data[key] = default_settings[key]
	
	# 已注释（调试噪音）：print("设置已加载: ", SAVEFILE_PATH)
	return data

## 检查配置文件是否存在
static func setting_file_exists() -> bool:
	return FileAccess.file_exists(SAVEFILE_PATH)

## 初始化设置（游戏启动时调用）
static func initialize_settings():
	if setting_file_exists():
		var settings = load_settings()
		apply_key_bindings_from_dict(settings)
		# 已注释（调试噪音）：print("已加载用户设置")
	else:
		var default_settings = get_default_settings()
		save_settings(default_settings)
		apply_default_key_bindings()
		# 已注释（调试噪音）：print("未找到配置文件，已创建默认设置")
