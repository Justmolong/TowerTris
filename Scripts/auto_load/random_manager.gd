extends Node

## 随机数管理器
## 负责统一管理所有系统的随机数生成，确保确定性

# 主随机数生成器
var _rng: RandomNumberGenerator

# 各系统的独立随机数流（字典：系统名称 -> RNG）
var _sub_rngs: Dictionary = {}

# ====== 种子字典 ======
# 存储每个子系统的种子值，系统名称 -> 种子值
var _sub_seeds: Dictionary = {}

# 当前使用的种子值
var current_seed_value: int = 0

# 是否已初始化
var _is_initialized: bool = false


## 初始化随机数管理器
func initialize(seed_value: int):
	current_seed_value = seed_value
	
	# 创建主RNG
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	
	# 清空并重建字典
	_sub_rngs.clear()
	_sub_seeds.clear()
	
	# 为每个系统创建独立的RNG，使用不同的种子派生方式
	_create_sub_rng(seed_value, "BAG")
	_create_sub_rng(seed_value, "GARBAGE")
	_create_sub_rng(seed_value, "ATTACK")
	_create_sub_rng(seed_value, "TOWER_CLIMB")
	_create_sub_rng(seed_value, "MISC")
	
	_is_initialized = true
	# 已注释（调试噪音）：print("随机数管理器已初始化，主种子: ", seed_value)


## 使用默认种子初始化（基于时间）
func initialize_default():
	var seed_value = Time.get_unix_time_from_system() * 1000
	initialize(seed_value)


## 创建子RNG，同时存入种子字典
func _create_sub_rng(base_seed: int, system_name: String) -> RandomNumberGenerator:
	var sub_rng = RandomNumberGenerator.new()
	# 使用字符串哈希生成子种子，确保不同系统获得不同的随机序列
	var sub_seed = base_seed ^ system_name.hash()
	sub_rng.seed = sub_seed
	
	# 存入字典
	_sub_rngs[system_name] = sub_rng
	_sub_seeds[system_name] = sub_seed  # 种子字典记录
	
	return sub_rng


## 检查是否已初始化
func is_initialized() -> bool:
	return _is_initialized


## 获取当前种子值
func get_current_seed() -> int:
	return current_seed_value


## ========== 通用随机数获取（字符串参数） ==========

## 通过系统名称获取对应的随机数生成器
## 参数 system_name: 系统名称，如 "BAG"、"GARBAGE"、"ATTACK"、"TOWER_CLIMB"、"MISC"
func get_random(system_name: String) -> RandomNumberGenerator:
	if not _is_initialized:
		initialize_default()
	if not _sub_rngs.has(system_name):
		push_error("RandomManager: 未知的随机数系统 \"", system_name, "\"")
		# 返回杂项RNG作为兜底
		if _sub_rngs.has("MISC"):
			return _sub_rngs["MISC"]
		return _rng
	return _sub_rngs[system_name]


## 通过系统名称获取对应的种子值
## 参数 system_name: 系统名称，如 "BAG"、"GARBAGE"、"ATTACK"、"TOWER_CLIMB"、"MISC"
func get_seed(system_name: String) -> int:
	if not _sub_seeds.has(system_name):
		push_error("RandomManager: 未知的种子系统 \"", system_name, "\"")
		return 0
	return _sub_seeds[system_name]


## ========== 便捷方法（基于通用函数） ==========

## 获取一个随机浮点数 (0.0 ~ 1.0) - 使用Bag RNG
func bag_randf() -> float:
	return get_random("BAG").randf()

## 获取一个随机整数 - 使用Bag RNG
func bag_randi() -> int:
	return get_random("BAG").randi()

## 获取一个随机浮点数 (0.0 ~ 1.0) - 使用垃圾行RNG
func garbage_randf() -> float:
	return get_random("GARBAGE").randf()

## 获取一个随机整数 - 使用垃圾行RNG
func garbage_randi() -> int:
	return get_random("GARBAGE").randi()

## 获取一个随机浮点数 (0.0 ~ 1.0) - 使用攻击RNG
func attack_randf() -> float:
	return get_random("ATTACK").randf()

## 获取一个随机整数 - 使用攻击RNG
func attack_randi() -> int:
	return get_random("ATTACK").randi()

## 获取一个随机浮点数 (0.0 ~ 1.0) - 使用杂项RNG
func misc_randf() -> float:
	return get_random("MISC").randf()

## 获取一个随机整数 - 使用杂项RNG
func misc_randi() -> int:
	return get_random("MISC").randi()


## 重置所有RNG（用于Replay）
func reset_all(seed_value: int):
	initialize(seed_value)


## 获取所有子种子的字典（用于调试/Replay记录）
func get_sub_seeds() -> Dictionary:
	return _sub_seeds.duplicate()
