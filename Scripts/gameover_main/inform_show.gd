extends Node
class_name InformShow

## 游戏结束信息展示器
## 负责显示游戏结束时的统计数据

# 节点引用（根据实际场景结构调整路径）
@export var game_over_label: Label  # 游戏结束标题
@export var height_label: Label     # 最终高度
@export var stats_container: Control  # 统计数据容器

# 统计数据显示标签（根据实际场景结构调整）
@export var time_label: Label      # 游戏时间
@export var pieces_label: Label    # 放置方块数
@export var pps_label: Label       # PPS
@export var apm_label: Label       # APM
@export var rpm_label: Label       # RPM
@export var max_combo_label: Label # 最大连击
@export var max_btb_label: Label   # 最大BTB
@export var lines_cleared_label: Label  # 总消行数
@export var spins_label: Label     # 总Spin次数
@export var attacks_label: Label   # 总攻击数
@export var kill_count_label: Label      # 击杀数
@export var tower_avg_speed_label: Label # ACPS（平均速度）
@export var stage_label: Label           # 当前阶段

# 已选取的 buff 列表（右侧）
@export var buff_list_container: VBoxContainer  # 已选取 buff 列表容器
@export var buff_list_title: Label              # buff 列表标题（保留，不删除）

func _ready():
	# 显示游戏结束数据
	_display_game_over_data()

## 显示游戏结束数据
func _display_game_over_data():
	# 从全局数据获取统计信息
	var stats = GlobalData.get_stats()
	
	# 设置标题和原因
	if game_over_label:
		game_over_label.text = "GAME OVER"
	
	# 显示最终高度
	if height_label:
		var height = stats.get("tower_height", 0.0)
		height_label.text = "最终高度: %.2fm" % height
	
	# 格式化时间（秒 → MM:SS）
	var time_str = _format_time(stats["game_time"])
	
	# 更新各个标签
	if time_label:
		time_label.text = "游戏时间: %s" % time_str
	
	if pieces_label:
		pieces_label.text = "放置方块: %d" % stats["total_pieces"]
	
	if pps_label:
		pps_label.text = "PPS: %.2f" % stats["pps"]
	
	if apm_label:
		apm_label.text = "APM: %.2f" % stats["apm"]
	
	if rpm_label:
		rpm_label.text = "RPM: %.2f" % stats["rpm"]
	
	if max_combo_label:
		max_combo_label.text = "最大连击: %d" % stats["max_combo"]
	
	if max_btb_label:
		max_btb_label.text = "最大BTB: %d" % stats["max_btb"]
	
	if lines_cleared_label:
		lines_cleared_label.text = "总消行: %d" % stats["total_lines_cleared"]
	
	if spins_label:
		spins_label.text = "总Spin: %d" % stats["total_spins"]
	
	if attacks_label:
		attacks_label.text = "总攻击: %d" % stats["total_attacks"]
	
	if kill_count_label:
		kill_count_label.text = "击杀数: %d" % stats.get("kill_count", 0)
	
	if tower_avg_speed_label:
		var total_dist = stats.get("tower_height", 0.0)
		var total_time = maxf(stats.get("game_time", 1.0), 0.001)
		var avg_speed = total_dist / total_time
		tower_avg_speed_label.text = "ACS: %.2f" % avg_speed
	
	if stage_label:
		stage_label.text = "当前阶段: %d" % (stats.get("current_stage", 0) + 1)
	
	# 显示已选取的 buff 列表
	_populate_buff_list()

## 在右侧列表显示本次已选取的 buff
func _populate_buff_list() -> void:
	if not buff_list_container:
		return
	# 清除旧的动态标签（保留标题节点）
	for child in buff_list_container.get_children():
		if child != buff_list_title:
			child.queue_free()
	
	var buffs: Array = GlobalData.selected_buffs
	if buffs.is_empty():
		var empty := Label.new()
		empty.text = "无"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		buff_list_container.add_child(empty)
		return
	
	for buff in buffs:
		var buff_name: String = _get_buff_name(buff)
		var label := Label.new()
		label.text = buff_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1))
		buff_list_container.add_child(label)

## 提取 buff 名称（描述中冒号前的部分，如 "高压I：apm总量增加20%" → "高压I"）
## 若无冒号则使用描述本身；描述为空时退回 box_id
func _get_buff_name(buff: Dictionary) -> String:
	var text: String = str(buff.get("text", ""))
	for sep: String in ["：", ":", "－", "-"]:
		var idx: int = text.find(sep)
		if idx > 0:
			return text.substr(0, idx).strip_edges()
	if not text.is_empty():
		return text
	return str(buff.get("id", ""))

## 格式化时间
func _format_time(seconds: float) -> String:
	var minutes = int(seconds / 60)
	var secs = int(seconds) % 60
	return "%02d:%02d" % [minutes, secs]

## 重玩按钮回调（可选）
func _on_restart_button_pressed():
	# 重置全局数据
	GlobalData.reset_stats()
	# 切换到游戏场景
	get_tree().change_scene_to_file("res://Tscns/tetris.tscn")

## EXIT 按钮回调：返回主菜单
func _on_exit_button_pressed():
	# 重置全局数据
	GlobalData.reset_stats()
	# 切换到主菜单场景
	get_tree().change_scene_to_file("res://Tscns/main_menu.tscn")


## BACK 按钮回调：返回 buff 选择界面，并带回已选取的 buff 进行预勾选
func _on_back_button_pressed():
	# 标记：返回 buff_chose_area 时需要恢复上次勾选
	GlobalData.restore_buffs = true
	# 不重置 stats，保留 selected_buffs 供 buff_chose_area 读取
	get_tree().change_scene_to_file("res://Tscns/buff_chose_area.tscn")
