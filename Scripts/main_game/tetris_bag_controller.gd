extends Node
class_name TetrisBagController

## 俄罗斯方块Bag生成器
## 负责方块序列生成，支持多种出块策略（ChangeBag buff 通过 GlobalData 传入 BagType）：
##   bag_type = -1 : 默认 7-Bag（每7个方块一个随机排列的完整bag）
##   bag_type =  1 : 14-Bag（一次生成14个方块，每种方块2个，随机排列）
##   bag_type =  2 : 概率出块（每次随机生成1个，出现越少的方块下次出现概率越高）
##   bag_type =  3 : 完全随机出块（每次均匀随机生成1个）

# 方块数据文件路径（方块类型/形状/颜色均从此文件读取）
const BLOCK_DATA_PATH: String = "res://GameSaveData/BlockData.json"

# 方块数据字典（从BlockData.json加载）
# 结构: { "I": {"shape": [[...]], "color": Color}, ... }
# 所有方块类型/形状/颜色均以BlockData.json为准
var piece_data: Dictionary = {}

# 方块类型列表（用于生成，由BlockData.json的键生成）
var piece_types: Array = []

# 方块序列
var piece_queue: Array = []  # 存储方块类型名称的队列

# 出块策略类型（-1=默认7-Bag）。ChangeBag buff 通过 GlobalData 传入 1/2/3
var bag_type: int = -1

# 概率出块（BagType=2）用到的出现次数统计：piece_type -> 已出现次数
var _spawn_count: Dictionary = {}

# ========== 数据加载 ==========

func _ready():
	# 从BlockData.json读取方块数据（类型/形状/颜色），此为唯一数据来源
	_load_block_data_from_json()

## 确保方块数据已从BlockData.json加载（懒加载）
## 场景树中TetrisController的_ready会先于本节点执行，可能在本节点_ready前请求方块，
## 因此所有访问方块数据的入口都需要先调用本函数
func _ensure_data_loaded() -> void:
	if piece_data.is_empty():
		_load_block_data_from_json()

## 从BlockData.json读取所有方块数据，存储进 piece_data 字典
## 后续访问方块时先根据名称从 piece_data 获取 shape 和 color 再使用
func _load_block_data_from_json() -> void:
	if not FileAccess.file_exists(BLOCK_DATA_PATH):
		push_error("BlockData.json 不存在: ", BLOCK_DATA_PATH)
		return
	
	var file = FileAccess.open(BLOCK_DATA_PATH, FileAccess.READ)
	if not file:
		push_error("无法打开 BlockData.json: ", BLOCK_DATA_PATH)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("解析 BlockData.json 失败: ", json.get_error_message())
		return
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BlockData.json 格式错误")
		return
	
	var new_piece_data: Dictionary = {}
	var new_piece_types: Array = []
	for piece_type: String in data:
		var entry: Variant = data[piece_type]
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("Shape") or not entry.has("Color"):
			push_warning("BlockData.json 中方块数据格式错误，已跳过: ", piece_type)
			continue
		
		# Shape：矩阵数组 → 整型二维数组
		var shape: Array = []
		for row in entry["Shape"]:
			var int_row: Array = []
			for cell in row:
				int_row.append(int(cell))
			shape.append(int_row)
		
		# Color：数组 → Color（支持RGB三元素或RGBA四元素）
		var color_arr: Array = entry["Color"]
		var color: Color
		if color_arr.size() >= 4:
			color = Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3])
		else:
			color = Color(color_arr[0], color_arr[1], color_arr[2])
		
		new_piece_data[piece_type] = {"shape": shape, "color": color}
		new_piece_types.append(piece_type)
	
	if new_piece_data.is_empty():
		push_error("BlockData.json 中无有效方块数据")
		return
	
	piece_data = new_piece_data
	piece_types = new_piece_types
	# 已注释（调试噪音）：print("BlockData.json 已加载，方块类型: ", piece_types)

# 信号
signal piece_spawned(piece_type: String, shape: Array, color: Color)

## 生成单个7-Bag（7个不同方块的随机排列）
func _generate_7bag_type_bag() -> Array:
	var new_bag = piece_types.duplicate()
	var bag_rng = RandomManager.get_random("BAG")
	for i in range(new_bag.size() - 1, 0, -1):
		var j = bag_rng.randi_range(0, i)
		var temp = new_bag[i]
		new_bag[i] = new_bag[j]
		new_bag[j] = temp
	return new_bag

## 生成单个14-Bag（每种方块2个，共14个，随机排列）
func _generate_14bag_type_bag() -> Array:
	var bag: Array = piece_types.duplicate() + piece_types.duplicate()
	var bag_rng = RandomManager.get_random("BAG")
	for i in range(bag.size() - 1, 0, -1):
		var j = bag_rng.randi_range(0, i)
		var temp = bag[i]
		bag[i] = bag[j]
		bag[j] = temp
	return bag

## 概率出块（BagType=2）：按出现次数加权随机选1个方块。
## 权重 = 1/(出现次数+1)，出现越少的方块权重越高 → 下次出现概率越高。
func _generate_probability_piece() -> String:
	var total_weight := 0.0
	for pt: String in piece_types:
		var c: int = int(_spawn_count.get(pt, 0))
		total_weight += 1.0 / (c + 1.0)
	var bag_rng = RandomManager.get_random("BAG")
	var r: float = bag_rng.randf() * total_weight
	for pt: String in piece_types:
		var c: int = int(_spawn_count.get(pt, 0))
		r -= 1.0 / (c + 1.0)
		if r <= 0.0:
			_spawn_count[pt] = c + 1
			return pt
	# 兜底（浮点误差导致未命中时取最后一个）
	var last: String = piece_types[piece_types.size() - 1]
	_spawn_count[last] = int(_spawn_count.get(last, 0)) + 1
	return last

## 完全随机出块（BagType=3）：均匀随机选1个方块
func _generate_random_piece() -> String:
	var bag_rng = RandomManager.get_random("BAG")
	return piece_types[bag_rng.randi_range(0, piece_types.size() - 1)]

## 获取当前生效的出块策略类型
## 优先返回外部通过 set_bag_type 设置的 bag_type；否则读取 ChangeBag buff 写入 GlobalData 的 BagType
func _get_active_bag_type() -> int:
	if bag_type != -1:
		return bag_type
	var init: Dictionary = GlobalData.tower_init_data
	var extra: Dictionary = init.get("extra_data_dict", {})
	if extra.has("BagType"):
		return int(extra["BagType"])
	return -1

## 外部设置出块策略类型（ChangeBag buff 或其它系统调用）。-1 表示使用默认7-Bag
func set_bag_type(value: int) -> void:
	bag_type = value

## 补充方块序列（当队列少于14个时补充）
## 根据当前出块策略选择对应的生成方式，未识别时回退到7-Bag
func _refill_queue():
	_ensure_data_loaded()
	if piece_types.is_empty():
		push_error("BlockData.json 未加载成功，无法生成方块序列")
		return
	var bt: int = _get_active_bag_type()
	while piece_queue.size() < 14:
		match bt:
			1:
				piece_queue += _generate_14bag_type_bag()
			2:
				piece_queue.append(_generate_probability_piece())
			3:
				piece_queue.append(_generate_random_piece())
			_:
				piece_queue += _generate_7bag_type_bag()
		# print("当前序列：",piece_queue)

## 获取下一个方块（从队列头部取出）
func get_next_piece() -> Dictionary:
	_ensure_data_loaded()
	# 检查是否需要补充（队列少于14个时补充）
	if piece_queue.size() < 14:
		_refill_queue()
	
	# 取出第一个方块
	var piece_type: String = piece_queue.pop_front()
	
	# 按名称从piece_data获取方块数据（深拷贝形状矩阵，防止引用污染）
	var data: Dictionary = piece_data.get(piece_type, {})
	if data.is_empty():
		push_error("get_next_piece: 未知方块类型或BlockData未加载: ", piece_type)
		return {"type": piece_type, "shape": [], "color": Color.WHITE}
	var shape: Array = _deep_copy_matrix(data["shape"])
	var color: Color = data["color"]
	
	# 发射信号
	piece_spawned.emit(piece_type, shape, color)
	
	return {
		"type": piece_type,
		"shape": shape,
		"color": color
	}

## 获取下一个方块的类型（用于预览）
func peek_next_piece() -> String:
	if piece_queue.is_empty():
		return "I"
	return piece_queue[0]

## 获取接下来N个方块的类型（用于Next显示）
func peek_next_pieces(count: int = 4) -> Array:
	var result = []
	
	# 确保队列有足够的方块
	while piece_queue.size() < count:
		_refill_queue()
	
	for i in range(count):
		result.append(piece_queue[i])
	
	return result

## 获取当前队列的副本（用于调试）
func get_queue_copy() -> Array:
	return piece_queue.duplicate()

## 深拷贝矩阵
func _deep_copy_matrix(matrix: Array) -> Array:
	var copy = []
	for row in matrix:
		copy.append(row.duplicate())
	return copy

## 根据名称获取方块数据（shape + color），不存在时返回空字典
func get_piece_data(piece_type: String) -> Dictionary:
	_ensure_data_loaded()
	return piece_data.get(piece_type, {})

## 获取方块的原始形状（未旋转状态），按名称从piece_data获取
func get_original_shape(piece_type: String) -> Array:
	_ensure_data_loaded()
	var data: Dictionary = piece_data.get(piece_type, {})
	if data.is_empty():
		push_error("未知方块类型: ", piece_type)
		return []
	return _deep_copy_matrix(data["shape"])

## 获取方块的颜色，按名称从piece_data获取
func get_piece_color(piece_type: String) -> Color:
	_ensure_data_loaded()
	var data: Dictionary = piece_data.get(piece_type, {})
	if data.is_empty():
		push_error("未知方块类型: ", piece_type)
		return Color.WHITE
	return data["color"]

## 获取方块类型名称
func get_piece_type_name(piece_type: String) -> String:
	return piece_type

# ========== 回放模式（已禁用） ==========
# var _replay_mode: bool = false
# var _replay_sequence: Array = []
# var _replay_index: int = 0
# 
# ## 启用回放模式，使用预先生成的方块序列
# func enable_replay_mode(sequence: Array):
# 	_replay_mode = true
# 	_replay_sequence = sequence.duplicate()
# 	_replay_index = 0
# 	piece_queue.clear()
# 	piece_queue = sequence.duplicate()
# 	print("回放模式已启用，序列长度: ", piece_queue.size())
# 
# ## 关闭回放模式
# func disable_replay_mode():
# 	_replay_mode = false
# 	_replay_sequence.clear()
# 	_replay_index = 0
# 	piece_queue.clear()
# 	_refill_queue()
# 
# func is_replay_mode() -> bool:
# 	return _replay_mode
# 
# ## 重置生成器（用于Replay）
# func reset():
# 	piece_queue.clear()
# 	if _replay_mode:
# 		piece_queue = _replay_sequence.duplicate()
# 		_replay_index = 0
# 	else:
# 		_refill_queue()
