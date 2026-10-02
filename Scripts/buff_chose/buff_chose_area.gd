extends Node
class_name BuffChoseArea

## Buff选择区域控制器
## 负责Back返回主菜单和Start开始游戏的功能
## 管理 ToggleBox 列表，支持批量读取切换状态
## 所有 buff 都通过参数传递（界面对任何键都不做特判）：
##   buff 参数的键名是 TowerController 成员变量 → 写进顶层（数值相乘、数组等直接替换）
##   buff 参数的键名不是 → 进 extra_data_dict，由 tower_controller._extra_data_deal() 处理
## 界面只显示「勾了什么 buff」的介绍文本，不显示任何参数/倍率变化。


# ========== 节点引用 ==========

@export var back_button: Button
@export var start_button: Button

# 滚动容器
@export var top_scroll_container: ScrollContainer
@export var middle_scroll_container: ScrollContainer

# 中部 buff 列表容器
@export var buff_list: VBoxContainer

# Buff配置数据文件路径（读取互斥组/显示文本/倍率配置）
const BUFF_DATA_PATH: String = "res://GameSaveData/BuffChoseData.json"

# 已勾选框对应的 Label 字典（box_id -> Label）
var _label_by_id: Dictionary = {}

## 互斥选框组配置：同一组内的选框互斥，选中一个则其他自动取消
## 组名 -> [box_id1, box_id2, ...]
var _mutually_exclusive_groups: Dictionary = {}

# box_id 到显示文本的映射
var _display_text_map: Dictionary = {}

# 挑战组合配置（从BuffChoseData.json的BuffCombination读取）
# 组合名 -> {"Info": 显示文本, "Group": [组名列表], "Color": [r,g,b](可选)}
var _combination_map: Dictionary = {}
## ExtraBotChange：{box_id: {zzz AI 参数名: 值}}，勾选对应 buff 时覆盖 zzztoj 的 AI 参数
var _extra_bot_change_map: Dictionary = {}

# 组合分组（从BuffChoseData.json的BuffGroup读取）：组名 -> [box_id, ...]
var _buff_group_map: Dictionary = {}

# 挑战组合 Label（显示在buff列表末尾）
var _combination_label: Label = null

# ========== Buff/Debuff 倍率配置 ==========

## 关卡初始数据：**已清空**，留空即代表「数值/数组一律以 TowerController 的默认值为准」。
##
## 为什么留空：这份字典只是 TowerController 默认值的副本，唯一的用途是「点 START 时覆盖对应变量」。
## 两边各存一份时，改关卡数值必须同时改两处，且键名写错只会在运行时 push_warning（例如
## killer_spike → base_killer_spike 的重命名就漏改过这里）。留空后：
##   · TowerController 直接用自身默认值（在 tower_controller.gd 里改，改一处即生效）
##   · 想由 buff 覆盖某个参数时，仍照常写进 BuffChoseData.json 的 BuffChange：
##       键在 TowerController 里存在 → 由 get_buffed_tower_data 写进这里（顶层键）后覆盖；
##       键不存在（NoSpin/BagType/RotateSystem/BtbBonus…）→ 进 extra_data_dict 由 _extra_data_deal 处理。
## 注意：本轮及以后都走「buff 参数 → 顶层键 / extra_data_dict」通道，本字典不需要预留任何键。
@export var tower_init_data: Dictionary = {}

## Buff/Debuff 配置（从 BuffChoseData.json 的 BuffChange 读入）
## 值即「要传给 TowerController 的参数」：数值与控制器当前值相乘，数组等直接替换
## 键名对不上 TowerController 成员时，整个键值对进 extra_data_dict
var _buff_config_map: Dictionary = {}

# ToggleBox 节点引用（可在编辑器中拖入或由代码动态添加）
@export var toggle_boxes: Array[ToggleBox] = []


# ========== 场景路径 ==========

@export var main_menu_scene_path: String = "res://Tscns/main_menu.tscn"
@export var game_scene_path: String = "res://Tscns/tetris.tscn"


# ========== 返回时恢复勾选 ==========

## 当从游戏结束界面（BACK 按钮）返回时，读取 GlobalData.selected_buffs 并预勾选对应的 ToggleBox
## 读取后立刻复位 restore_buffs 标志，避免从主菜单进入时误恢复
func _restore_previous_selection() -> void:
	if not GlobalData.restore_buffs:
		return
	GlobalData.restore_buffs = false
	
	var buffs: Array = GlobalData.selected_buffs
	for buff in buffs:
		var bid: String = str(buff.get("id", ""))
		if bid.is_empty():
			continue
		set_toggle_checked(bid, true)
	# 显式强制互斥：每个互斥组只保留一个勾选，确保返回后状态一致
	_enforce_mutual_exclusivity()


## 对每个互斥组强制只保留一个勾选（其余取消并移除标签）
## 即使 toggled 信号未触发，也能保证互斥逻辑生效
func _enforce_mutual_exclusivity() -> void:
	for group_name: String in _mutually_exclusive_groups:
		var group: Array = _mutually_exclusive_groups[group_name]
		var kept_one := false
		for other_id: String in group:
			var tb := _find_toggle_box(other_id)
			if tb and tb.is_checked_state():
				if kept_one:
					tb.set_checked(false)
					_remove_label_for_box(other_id)
				else:
					kept_one = true


## 按 box_id 查找 ToggleBox 节点
func _find_toggle_box(box_id: String) -> ToggleBox:
	for tb in toggle_boxes:
		if tb and tb.box_id == box_id:
			return tb
	return null


# ========== UI 缩放相关 ==========

# Panel 引用（CanvasLayer 下全屏面板，用于居中缩放）
var _panel: Panel = null


# ========== 数据加载 ==========

## 从BuffChoseData.json读取互斥组/显示文本/倍率配置，覆盖默认值
## 文件不存在或解析失败时保留代码中的默认配置
func _load_buff_data_from_json() -> void:
	if not FileAccess.file_exists(BUFF_DATA_PATH):
		# 已注释（调试噪音）：print("BuffChoseData.json 不存在，使用默认配置: ", BUFF_DATA_PATH)
		return
	
	var file = FileAccess.open(BUFF_DATA_PATH, FileAccess.READ)
	if not file:
		push_error("无法打开 BuffChoseData.json: ", BUFF_DATA_PATH)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("解析 BuffChoseData.json 失败: ", json.get_error_message())
		return
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BuffChoseData.json 格式错误")
		return
	
	# BuffConflick → 互斥选框组
	if data.has("BuffConflick") and typeof(data["BuffConflick"]) == TYPE_DICTIONARY:
		_mutually_exclusive_groups = data["BuffConflick"]
	
	# BuffInfo → 显示文本
	if data.has("BuffInfo") and typeof(data["BuffInfo"]) == TYPE_DICTIONARY:
		_display_text_map = data["BuffInfo"]
	
	# BuffChange → 倍率配置
	if data.has("BuffChange") and typeof(data["BuffChange"]) == TYPE_DICTIONARY:
		_buff_config_map = data["BuffChange"]
	
	# ExtraBotChange → 勾选 buff 时覆盖的 zzztoj AI 参数（键名 = ai_zzz::IO::Param 字段名）
	if data.has("ExtraBotChange") and typeof(data["ExtraBotChange"]) == TYPE_DICTIONARY:
		_extra_bot_change_map = data["ExtraBotChange"]
	
	# BuffCombination → 挑战组合配置
	if data.has("BuffCombination") and typeof(data["BuffCombination"]) == TYPE_DICTIONARY:
		_combination_map = data["BuffCombination"]
	
	# BuffGroup → 组合分组（组名 -> box_id列表）
	if data.has("BuffGroup") and typeof(data["BuffGroup"]) == TYPE_DICTIONARY:
		_buff_group_map = data["BuffGroup"]


## 内置兜底配置：某些buff不依赖JSON配置，代码内置默认值
## Talentless（无才能）：勾选后传递 NoSpin=3，禁用整个Spin判定
func _apply_builtin_fallbacks() -> void:
	if not _display_text_map.has("Talentless"):
		_display_text_map["Talentless"] = "无才能：禁用Spin判定"
	if not _buff_config_map.has("Talentless"):
		_buff_config_map["Talentless"] = {"NoSpin": 3}


# ========== 生命周期 ==========

func _ready():
	# 先读取BuffChoseData.json覆盖默认配置
	_load_buff_data_from_json()
	# 内置兜底配置（Talentless无才能，不依赖JSON）
	_apply_builtin_fallbacks()
	
	_panel = get_node_or_null("../Panel") as Panel
	# 若未在编辑器中配置toggle_boxes，则自动发现场景中的ToggleBox节点
	_discover_toggle_boxes()
	_connect_signals()
	_connect_toggle_boxes()
	
	# 应用 UI 缩放（UIScaler 已移除，固定 scale=1.0）
	_apply_ui_scale()
	
	# 更新已有标签显示（如 default_checked 为 true 的选框）
	_update_all_labels()
	_update_combination_label()
	
	# 从游戏结束界面返回时，恢复上次勾选的 buff
	# 必须延迟到所有 ToggleBox 的 _ready 执行完之后（本节点是 CanvasLayer 的第一个兄弟，
	# 其 _ready 会在 ToggleBox._ready 之前运行，导致勾选状态被 default_checked 覆盖）
	_restore_previous_selection.call_deferred()
	
	# Demo: 打印初始状态
	#print("ToggleBox 数量: ", toggle_boxes.size())
	for tb in toggle_boxes:
		pass
		#print("  [%s] checked=%s value=%s" % [tb.box_id, tb.is_checked_state(), tb.value])


## 应用 UI 缩放：Panel 居中缩放，子区域内容自适应
func _apply_ui_scale(_new_scale: float = -1.0) -> void:
	var s: float = 1.0
	
	# 缩放 Panel 并居中（3 个 ColorRect 作为子节点自动继承缩放）
	if _panel:
		_panel.scale = Vector2(s, s)
		_panel.pivot_offset = _panel.size / 2.0
		var vp: Vector2 = get_tree().root.size
		_panel.position = (vp - _panel.size * s) / 2.0
	
	# 调整 BackButton 和 StartButton 的位置和字体（不 scale——那会导致重叠）
	if back_button:
		back_button.add_theme_font_size_override("font_size", max(12, int(16 * s)))
		# BottomRightArea 内相对位置按比例调整
		back_button.offset_left = 40 * s
		back_button.offset_top = 80 * s
		back_button.offset_right = 40 * s + 140 * s
		back_button.offset_bottom = 80 * s + 50 * s
	if start_button:
		start_button.add_theme_font_size_override("font_size", max(12, int(16 * s)))
		start_button.offset_left = 40 * s
		start_button.offset_top = 150 * s
		start_button.offset_right = 40 * s + 140 * s
		start_button.offset_bottom = 150 * s + 50 * s
	
	# 调整 ToggleBox 的大小
	for tb in toggle_boxes:
		if tb:
			tb.box_size = max(16, int(32 * s))
			tb.custom_minimum_size = Vector2(tb.box_size, tb.box_size)
			tb.size = Vector2(tb.box_size, tb.box_size)
			tb.queue_redraw()
	
	# 调整标签字体大小
	for _box_id: String in _label_by_id:
		var label: Label = _label_by_id[_box_id] as Label
		if label:
			label.add_theme_font_size_override("font_size", max(12, int(20 * s)))
	
	# 调整挑战组合标签字体
	if _combination_label:
		_combination_label.add_theme_font_size_override("font_size", max(12, int(20 * s)))


# ========== 信号连接 ==========

func _connect_signals():
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)


## 自动发现场景中的ToggleBox节点（当toggle_boxes未在编辑器中配置时）
## 递归遍历本节点的父级（CanvasLayer）下所有子节点，按树顺序收集
func _discover_toggle_boxes() -> void:
	if not toggle_boxes.is_empty():
		return
	var found: Array[ToggleBox] = []
	var root_node: Node = get_parent()
	if root_node:
		_find_toggle_boxes_recursive(root_node, found)
	if not found.is_empty():
		toggle_boxes = found
		# 已注释（调试噪音）：print("自动发现 ToggleBox 节点: ", toggle_boxes.size())

func _find_toggle_boxes_recursive(node: Node, found: Array[ToggleBox]) -> void:
	if node is ToggleBox:
		found.append(node)
	for child in node.get_children():
		_find_toggle_boxes_recursive(child, found)


## 连接所有 ToggleBox 的状态切换信号
func _connect_toggle_boxes():
	for tb in toggle_boxes:
		if tb and not tb.toggled.is_connected(_on_toggle_box_toggled):
			tb.toggled.connect(_on_toggle_box_toggled)


# ========== Buff/Debuff 计算核心 ==========

## 获取应用了所有已勾选框参数后的数据字典（交给 GlobalData.tower_init_data）。
## 所有 buff 走同一条通用通道，界面对任何键都不做特判：
##   键名是 TowerController 的成员变量 → 写进顶层，数值相乘、数组/布尔等直接替换；
##   其它键 → 整个键值对进 extra_data_dict，由 tower_controller._extra_data_deal() 处理。
## 由于本文件的 tower_init_data 已清空，数值相乘时需要在**选中时**重算：
## 例：默认 extra_pressure_mult=1.0，勾 Pressure3 得 1.5；若同时勾 Pressure1 与 Pressure3
## （互斥组会拦掉，这里仅示语义），则按 1.0×1.2×1.5 叠加。
func get_buffed_tower_data() -> Dictionary:
	var result: Dictionary = tower_init_data.duplicate(true)
	# extra_data_dict 必须存在（即使空），TowerController 与 TetrisBagController 都会读它
	if not result.has("extra_data_dict"):
		result["extra_data_dict"] = {}
	
	# 本次已累加过的顶层数值键 → 其「进入循环前」的基准值
	var base_number: Dictionary = {}
	
	# Step 1: 把已勾选 buff 的参数写回数据
	for tb in toggle_boxes:
		if tb and tb.is_checked_state() and _buff_config_map.has(tb.box_id):
			var config: Dictionary = _buff_config_map[tb.box_id]
			for key: String in config:
				var buff_value = config[key]
				if result.has(key):
					if _is_numeric_value(result[key]) and _is_numeric_value(buff_value):
						# 数值：在基准值上累乘（清空 tower_init_data 后不能按已覆盖过的值连乘）
						if not base_number.has(key):
							base_number[key] = result[key]
						result[key] = float(base_number[key]) * float(buff_value)
					else:
						result[key] = buff_value                          # 其它（数组等）：直接替换
					continue
				# 键不在顶层（即 TowerController 没这个成员）→ 交给 _extra_data_deal 处理
				result["extra_data_dict"][key] = buff_value
	
	# Step 2: 勾选的 buff → ExtraBotChange（zzztoj AI 参数覆盖：Param 字段名 → 值）
	# 多个 buff 影响同一参数时后者覆盖前者
	var extra_bot: Dictionary = {}
	for tb in toggle_boxes:
		if tb and tb.is_checked_state() and _extra_bot_change_map.has(tb.box_id):
			var params = _extra_bot_change_map[tb.box_id]
			if typeof(params) == TYPE_DICTIONARY:
				for pk in params.keys():
					extra_bot[pk] = params[pk]
	if not extra_bot.is_empty():
		result["extra_data_dict"]["ExtraBotChange"] = extra_bot

	return result


## 值是否为数值（int/float，可参与 buff 倍率相乘）
static func _is_numeric_value(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## 生成指定 box 的显示文本（只有介绍文本，不含任何参数/倍率数据）
func _get_enhanced_label_text(box_id: String) -> String:
	var text: String = _display_text_map.get(box_id, "")
	if text.is_empty():
		return "[%s]" % box_id
	return text


## 刷新所有已勾选框 Label 的显示文本
func _update_all_labels() -> void:
	for box_id: String in _label_by_id:
		var label: Label = _label_by_id[box_id] as Label
		if label:
			label.text = _get_enhanced_label_text(box_id)


# ========== 挑战组合 ==========

## 根据组名获取对应的box_id列表（精确匹配优先，失败时尝试大小写不敏感匹配）
## 兼容JSON中组名大小写差异（如 "Nohold" vs "NoHold"）
## 若都不是组名，则把该名字当作单个 buff 名（box_id）直接返回——
## 组合的 Group 里允许直接写具体 buff（如 "ChangeBag_3"），无需为它单独建组。
func _get_group_box_ids(group_name: String) -> Array:
	if _buff_group_map.has(group_name):
		return _buff_group_map[group_name]
	var lower_name: String = group_name.to_lower()
	for key: String in _buff_group_map:
		if key.to_lower() == lower_name:
			return _buff_group_map[key]
	# 组不存在 → 退化为直接按 buff 名（box_id）查询
	if _is_known_box_id(group_name):
		return [group_name]
	return []

## 该名字是否为已存在的 buff 选框（box_id）
func _is_known_box_id(box_id: String) -> bool:
	if _buff_config_map.has(box_id):
		return true
	for tb in toggle_boxes:
		if tb and tb.box_id == box_id:
			return true
	return false

## 解析颜色字段（支持 [r,g,b]/[r,g,b,a] 数组或 "#rrggbb" 字符串），失败返回 null
func _parse_color(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			var a: float = 1.0
			if arr.size() >= 4:
				a = float(arr[3])
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	elif typeof(value) == TYPE_STRING:
		var s: String = str(value)
		if Color.html_is_valid(s):
			return Color(s)
	return null

## 更新挑战组合显示：当已选框恰好（且仅）等于某组合Group内的全部box时，
## 在buff列表末尾显示 "挑战组合：XXXX"（XXXX为该组合的Info内容）
## Color字段为预留颜色读取字段，未读取到（或格式错误）时使用文本默认颜色
func _update_combination_label() -> void:
	if not buff_list:
		return
	
	# 当前已选框集合
	var selected: Array[String] = get_checked_toggle_ids()
	selected.sort()
	
	var matched_texts: Array[String] = []
	var matched_color: Color = Color.WHITE
	var has_color: bool = false
	
	for comb_name: String in _combination_map:
		var comb: Variant = _combination_map[comb_name]
		if typeof(comb) != TYPE_DICTIONARY or not comb.has("Group"):
			continue
		
		# 汇总该组合Group内所有组对应的box_id
		var expected: Array = []
		var group_valid: bool = true
		for group_name: Variant in comb["Group"]:
			var ids: Array = _get_group_box_ids(str(group_name))
			if ids.is_empty():
				group_valid = false
				push_warning("挑战组合 %s 引用的组不存在: %s" % [comb_name, group_name])
				break
			expected += ids
		if not group_valid:
			continue
		expected.sort()
		
		# 且仅满足：已选框集合与组合期望集合完全一致才显示
		if selected != expected:
			continue
		
		var info_text: String = str(comb.get("Info", ""))
		if info_text.is_empty():
			info_text = comb_name
		matched_texts.append(info_text)
		
		# 预留color读取字段：存在且可解析时使用，否则保持文本默认颜色
		if not has_color and comb.has("Color"):
			var c: Variant = _parse_color(comb["Color"])
			if c != null:
				matched_color = c
				has_color = true
	
	if matched_texts.is_empty():
		if _combination_label:
			_combination_label.hide()
		return
	
	if not _combination_label:
		_combination_label = Label.new()
		_combination_label.add_theme_font_size_override("font_size", max(12, int(20 * 1.0)))
		buff_list.add_child(_combination_label)
	
	_combination_label.text = "挑战组合：" + "\n".join(matched_texts)
	if has_color:
		_combination_label.add_theme_color_override("font_color", matched_color)
	else:
		_combination_label.remove_theme_color_override("font_color")
	_combination_label.show()
	# 确保显示在buff列表最后
	buff_list.move_child(_combination_label, buff_list.get_child_count() - 1)


# ========== ToggleBox 回调 ==========

## 任意 ToggleBox 切换时触发
func _on_toggle_box_toggled(box_id: String, is_checked: bool, _value: Variant) -> void:
	
	if is_checked:
		_add_label_for_box(box_id)
		# 互斥逻辑：如果此选框属于某个互斥组，取消同组其他选框
		_uncheck_mutually_exclusive(box_id)
	else:
		_remove_label_for_box(box_id)
	
	# 添加/移除后重新排序，确保按 toggle_boxes 顺序从上到下排列
	_refresh_label_order()
	
	# 刷新所有标签显示
	_update_all_labels()
	# 更新挑战组合显示
	_update_combination_label()


## 互斥逻辑：取消同组内其他选框的选中状态
func _uncheck_mutually_exclusive(checked_box_id: String) -> void:
	for _group_name: String in _mutually_exclusive_groups:
		var group: Array = _mutually_exclusive_groups[_group_name]
		if not checked_box_id in group:
			continue
		# 此选框属于该组，取消同组内其他选框
		for other_id: String in group:
			if other_id == checked_box_id:
				continue
			# 查找对应的 ToggleBox 节点并取消选中
			for tb in toggle_boxes:
				if tb and tb.box_id == other_id and tb.is_checked_state():
					tb.set_checked(false)
					_remove_label_for_box(other_id)

## 为指定 box 添加 Label（如果尚未添加）
func _add_label_for_box(box_id: String) -> void:
	if not buff_list:
		return
	
	# 已存在则不重复添加
	if _label_by_id.has(box_id):
		return
	
	var label := Label.new()
	label.text = _get_enhanced_label_text(box_id)
	label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))   # 统一绿色调
	
	label.add_theme_font_size_override("font_size", max(12, int(20 * 1.0)))
	
	_label_by_id[box_id] = label
	buff_list.add_child(label)


## 移除指定 box 的 Label
func _remove_label_for_box(box_id: String) -> void:
	if not buff_list:
		return
	
	var label: Label = _label_by_id.get(box_id)
	if not label:
		return
	
	buff_list.remove_child(label)
	label.queue_free()
	_label_by_id.erase(box_id)


## 将所有 Label 按 toggle_boxes 顺序重新排列（从上到下 = box_id 顺序）
func _refresh_label_order() -> void:
	if not buff_list:
		return
	
	# 按照 toggle_boxes 的顺序，收集所有已勾选的 box_id
	var checked_order: Array[String] = []
	for tb in toggle_boxes:
		if tb and _label_by_id.has(tb.box_id):
			checked_order.append(tb.box_id)
	
	# 将 buff_list 的子节点按 checked_order 重排
	for i in checked_order.size():
		var label: Label = _label_by_id[checked_order[i]]
		# 如果该 Label 不在正确的位置，则移到最后再插入到正确位置
		if buff_list.get_child(i) != label:
			buff_list.move_child(label, i)


# ========== 公开方法 ==========

## 获取所有 ToggleBox 的状态列表（供外部批量读取）
func get_all_toggle_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tb in toggle_boxes:
		if tb:
			result.append(tb.get_state())
	return result


## 根据 id 获取指定 ToggleBox 的状态
func get_toggle_state_by_id(box_id: String) -> Dictionary:
	for tb in toggle_boxes:
		if tb and tb.box_id == box_id:
			return tb.get_state()
	return {}


## 根据 id 设置指定 ToggleBox 的选中状态
func set_toggle_checked(box_id: String, checked: bool) -> bool:
	for tb in toggle_boxes:
		if tb and tb.box_id == box_id:
			tb.set_checked(checked)
			return true
	return false


## 动态添加 ToggleBox
func add_toggle_box(tb: ToggleBox) -> void:
	if tb and not tb in toggle_boxes:
		toggle_boxes.append(tb)
		if not tb.toggled.is_connected(_on_toggle_box_toggled):
			tb.toggled.connect(_on_toggle_box_toggled)


## 获取所有 ToggleBox 中处于选中（✓）状态的列表
func get_checked_toggle_ids() -> Array[String]:
	var ids: Array[String] = []
	for tb in toggle_boxes:
		if tb and tb.is_checked_state():
			ids.append(tb.box_id)
	return ids


# ========== 按钮回调 ==========

func _on_back_button_pressed():
	#print("返回主菜单")
	get_tree().change_scene_to_file(main_menu_scene_path)


func _on_start_button_pressed():
	#print("开始游戏 - 进入俄罗斯方块")
	
	# 将应用了所有 buff/debuff 倍率的数据存入 GlobalData
	var buffed_data: Dictionary = get_buffed_tower_data()
	GlobalData.tower_init_data = buffed_data
	#print("TowerController 数据（含 buff/debuff 倍率累加）已存入 GlobalData: ", GlobalData.tower_init_data)
	
	# 记录已选取的 buff（供结束界面右侧列表展示）
	var checked_ids: Array[String] = get_checked_toggle_ids()
	var buff_display: Array = []
	for bid: String in checked_ids:
		buff_display.append({
			"id": bid,
			"text": _get_enhanced_label_text(bid),
		})
	GlobalData.selected_buffs = buff_display
	
	GlobalData.reset_stats()
	get_tree().change_scene_to_file(game_scene_path)
