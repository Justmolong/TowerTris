extends Node2D
class_name TowerController

static var FLOOR_HIGHER : Array = [0,50,150,300,450,650,850,1100,1350,1650,2550,3000,3500,4500,5500,6500,8000,9500,11000]

## 需要其它节点（方块控制器 / 垃圾行 / 版面 / 消行 / 文本打印器）时，
## 一律通过公共数据区 TetrisGlobalData 取用（见 tetris_global_data.gd）。

@onready var tower_rng = RandomManager.get_random("TOWER_CLIMB")

var total_apm : float = 100.0
var stage_percent_apm : Array = [0.01,0.02,0.05,0.1,0.25,0.4,0.5,0.6,0.75,0.8,1]
var extra_percent_apm : float = 0

var publish_time_array : Array = [0,60*7,60*8,60*9,60*10,60*11]
var publish_stage : int = 0
var publish_make_finish : int = 0
var publish_mult_attack : float = 1.0

var stage_garbage_time : Array = [5,5,4,4,4,3,3,3,2,2,2,1,1,1,0.75,0.75,0.5]
var garbage_collect_percent : float = 0.1
var garbage_collect_percent_array: Array = [0.4,0.3,0.2,0.1,0.1,0.2,0.2,0.3,0.4,0.5]
var garbage_sent_time : float = 0
var garbage_divide_percent : float = 0
var garbage_divide_percent_array: Array = [0.8,0.6,0.4,0.2,0.2,0.1,0.1,0,0.1,0.2,0.3]
var garbage_hole_change_percent_array: Array = [0.1,0.1,0.1,0.2,0.2,0.3,0.3,0.4,0.4,0.5]
var collected_count : int = 0
var collected_garbage : Array = []
var pressure_mult_array: Array = [1,1,1,1,1,1,1,1,1,1,1.25,1.5,1.75,2,2.25,2.5,2.75,3,3.5]
var pressure_mult : float = 1.0
var extra_pressure_mult : float = 1.0
var send_mult_attack: float = 1.0

# ---- 出招「小数余量」----
# apm 的定义是 attack per minute（每分钟固定总量），而每次出招的间隔不定，
# 所以每拍应出的行数 = apm/60 × 这一拍实际经过的时间；行数必须是整数，零头不能丢也不能多给，
# 于是用两个余量累加器把零头留到下一拍 —— 保证长期总量恰为 apm × 倍率（不再被 ceil 放大）。
var attack_remainder : float = 0.0    # 「每拍按 apm 应出行数」的零头
var send_remainder : float = 0.0      # 「乘完倍率待发送行数」的零头
var _send_elapsed : float = 0.0       # 本拍已累计的经过时间（发招时用来还原这段时间的攻击量）

var gravity_drop_time_array: Array = [5,5,5,5,5,4.8,4.6,4.4,4.2,4]
var lock_delay_array: Array = [1]

var tower_speed_meter: float = 0.0      
var tower_lowest_speed: float = 0.0     # 爬塔速度下限（0 = 不限下限，速度可以降到 0 m/s）

# ---- 真实爬塔速度（右下角速度表用）：与 PPM/RPM 同口径的「最近一分钟米数增量 ÷ 秒数」 ----
## 统计窗口（秒）：与 TetrisController 的 RPM_WINDOW_SECONDS 保持一致
@export var meter_window_span: float = 60.0
## 采样间隔（秒）：每帧记一个点太浪费，按这个间隔记录一次米数位置
@export var meter_window_sample_interval: float = 0.5
var _meter_clock: float = 0.0                  # 内部计时（累加 delta，窗口跨度用）
var _meter_samples: Array[Dictionary] = []     # [{ "time": 采样时刻, "meter": 当时米数 }]
var _meter_sample_timer: float = 0.0
var tower_dropped_mult: Array = [0.8,0.9,1,1,1,1.1,1.2,1.3,1.4,1.5,1.7,1.9,2]
var tower_current_dropped_mult: float = 1.0
var attack_to_meter_mult: float = 0.2
var attack_to_speed_mult: float = 0.1

var warning_count : int = 4
var segment_line : int = 4
var big_attack_enter_array : Array = []
var big_attack_delay : float = 4.0

var base_killer_spike: int = 10
var base_kill_possible_percent: float = 0.2
var kill_reward: Array = [30,2]

# ---- 米数增长飘字（attack_increase_tower / 击杀奖励 触发，显示在「爬塔米数」文字位置）----
# 表现：朝上浮现、幅度小、衰减快，位置在版面下侧（米数文字处），不会遮挡版面。
## 飘字类型：只决定颜色（数值与运动表现一致）
##   NORMAL        普通攻击奖励 → 绿色
##   OFFSET_REWARD 抵消垃圾行的防御奖励 → 红色
##   KILL_REWARD   击杀奖励 → 金色
enum MeterPopupType { NORMAL, OFFSET_REWARD, KILL_REWARD }

var attack_popup_enabled : bool = true
var attack_popup_key : String = "tower_gain"        # TextPrinter 中区分文本用的 key
var attack_popup_font_size_ratio : float = 0.4      # 基础字号（相对 cell_size，略小于米数文字）
var attack_popup_font_grow : float = 1.1           # 增幅越大字号越大（对数函数 → 增长逐渐变缓）
var attack_popup_grow_ref : float = 1.0             # 字号增长函数的参考增幅（米）
var attack_popup_max_font_scale : float = 2.4       # 字号增长上限倍数（避免大字压住版面）
var attack_popup_color : Color = Color(0.55, 1.0, 0.6)
var attack_popup_outline_color : Color = Color(0.04, 0.1, 0.05, 1.0)
# 抵消垃圾行得到的「防御奖励」飘字：用红色与普通攻击奖励（上面的绿色）区分
var attack_popup_offset_color : Color = Color(1.0, 0.42, 0.38)
var attack_popup_offset_outline_color : Color = Color(0.16, 0.03, 0.03, 1.0)
# 击杀奖励（try_give_kill_reward）飘字：金色
var attack_popup_kill_color : Color = Color(1.0, 0.84, 0.25)
var attack_popup_kill_outline_color : Color = Color(0.22, 0.13, 0.0, 1.0)
var attack_popup_display_time : float = 0.1        # 保持时间（几乎立刻开始淡出）
var attack_popup_fade_time : float = 0.8          # 淡出时长（衰减快）
var attack_popup_rise_speed : float = 80.0         # 上浮初速度（像素/秒）——起步最快，随后迅速变慢
var attack_popup_drift_x : float = 30.0             # 横向初速度（像素/秒，方向随机；与X偏移、旋转同向）
var attack_popup_drift_decay : float = 6.0          # 速度衰减速率（/秒，越大越快停）→ 加速度由快变慢
var attack_popup_spread : float = 40.0              # 起始 X 轴偏移量（像素，范围 -x ~ +x，方向随机）
var attack_popup_rotate_deg : float = 10.0          # 旋转角度偏移量上限（±度）
# 去重叠：一次消行常常同时给「普通攻击奖励」和「抵消奖励」（甚至多条击杀奖励），
# 它们会在同一瞬间、同一位置弹出，随机横向偏移又可能撞在一起，导致两个字完全重叠、谁都看不清。
# 处理方式：每条飘字出场前按「实际文字宽度」检查与在场飘字（anti_overlap_time 秒内）的横向重叠量，
# 超过 max_overlap_ratio 就往旁边让位 —— 允许部分重叠，但不会两个完全叠在一起。
var attack_popup_max_overlap_ratio : float = 0.25  # 允许的最大横向重叠比例（相对较窄那条字宽）；0=完全不重叠
var attack_popup_anti_overlap_time : float = 0.6   # 视为「同时在场」的时间窗（秒），窗内互相避让

var _popup_boxes : Array = []                       # 在场飘字的横向占位：[{x, half_w, until_msec}]

## 说明：!!!! 大招警示的开始/结束不再用本节点的信号，而是走公共数据区的公共事件
## （TetrisGlobalData.big_attack_warning_started / _ended），
## 这样版面绘制器与塔之间不需要互相持有引用。伤害结算同理：
## 消行控制器/方块控制器只 emit TetrisGlobalData.tower_damage_dealt，由塔自己连接处理。
## （原先的 stage_changed 信号无人连接，已删除）

var _previous_stage: int = 0  # 用于检测阶段变化

var garbage_sent_timer : Timer
var big_attack_delay_timer : Timer

var self_game_time : float

func _enter_tree() -> void:
	# 自注册到公共数据区（整棵场景树的 _enter_tree 都先于任何 _ready 完成，
	# 因此第一个 _ready 跑起来时，所有节点的引用都已就位）
	TetrisGlobalData.register_node(self)

func _exit_tree() -> void:
	TetrisGlobalData.unregister_node(self)

func _ready() -> void:
	_set_timer()
	# 伤害结算走公共区域的公共事件：谁打出攻击谁 emit，本节点自己连接处理
	# （消行控制器 / 方块控制器因此都不需要认识塔节点）
	TetrisGlobalData.tower_damage_dealt.connect(attack_increase_tower)
	TetrisGlobalData.kill_reward_requested.connect(try_give_kill_reward)
	_previous_stage = TetrisGlobalData.current_stage
	# 真实速度窗口的起始参照点（t=0、当前米数）：未满一分钟时就是拿它当分子起点做放缩
	_meter_clock = 0.0
	_meter_sample_timer = 0.0
	_meter_samples.clear()
	_meter_samples.append({"time": 0.0, "meter": TetrisGlobalData.tower_meter})
	TetrisGlobalData.tower_real_speed_meter = 0.0
	# 上报就绪：当场景内所有节点都就绪后，公共数据区会通知各节点读走自己的 buff 参数
	TetrisGlobalData.notify_node_ready(self)

## 读取公共区域里属于本节点的关卡 / buff 参数（谁用谁读：公共区域不认这些键名）。
## 与自身成员同名的参数（total_apm / extra_pressure_mult / send_mult_attack /
## gravity_drop_time_array…）由公共区域泛化写回本节点；键名不同的在这里显式对应。
func apply_init_params() -> void:
	TetrisGlobalData.apply_matching_members(self)
	# 高压 buff（Pressure1/2/3 → pressure_apm_mult）：**一次性**把倍率乘进 total_apm。
	#   · 对应界面文案「apm总量增加X%」→ current_apm（HUD 显示的 APM）同步体现；
	#   · 攻击行数由 current_apm 产出（_try_sent_garbage），所以攻击量自动跟着放大；
	#   · 它是一次性需求，所以不为它保留成员变量（用 buff 参数键名直接取用），
	#     也不经过架构预留的 extra_pressure_mult。
	var pressure_apm_mult: float = TetrisGlobalData.get_init_float("pressure_apm_mult", 1.0)
	if not is_equal_approx(pressure_apm_mult, 1.0):
		total_apm *= pressure_apm_mult
	TetrisGlobalData.current_stage = 0

## !!!! 大招警示进度（0→1）：按警示计时器算出后写进公共数据区（版面绘制器读它画渐变，
## 不需要拿到本节点的 Timer 对象）。每帧调用一次，见 _process。
func _publish_big_attack_warning_progress() -> void:
	# 警示计时器没在跑 = 当前没有大招警示 → 进度归零
	if big_attack_delay_timer == null or big_attack_delay_timer.is_stopped() \
			or big_attack_delay_timer.wait_time <= 0.0:
		TetrisGlobalData.tower_big_attack_progress = 0.0
		return
	TetrisGlobalData.tower_big_attack_progress = clampf(
		1.0 - big_attack_delay_timer.time_left / big_attack_delay_timer.wait_time, 0.0, 1.0)

## 当前发送攻击的总倍率（统一入口）= 关卡自带 pressure_mult（按层数取表）
##   × 架构预留的 extra_pressure_mult（默认 1.0，目前无 buff 使用）
##   × 力量类 buff send_mult_attack × 阶段惩罚 publish_mult_attack。
## 塔的普通攻击与 !!!! 大招都只用这个函数。
## 注意：高压 buff 的倍率不在这里 —— 它在 apply_init_params() 里一次性乘进了 total_apm
## （因此已反映到 current_apm 与产出行数上），放进来会重复计算。
func get_pressure_mult() -> float:
	return pressure_mult * extra_pressure_mult * send_mult_attack * publish_mult_attack

func _set_timer():
	garbage_sent_timer = Timer.new()
	garbage_sent_timer.one_shot = true
	garbage_sent_timer.timeout.connect(_try_sent_garbage)
	add_child(garbage_sent_timer)
	
	big_attack_delay_timer = Timer.new()
	big_attack_delay_timer.wait_time = big_attack_delay
	big_attack_delay_timer.one_shot = true
	big_attack_delay_timer.timeout.connect(_warning_big_collected_enter)
	add_child(big_attack_delay_timer)

func _process(delta: float) -> void:
	for i in range(0,FLOOR_HIGHER.size()):
		if TetrisGlobalData.tower_meter > FLOOR_HIGHER[i]:
			TetrisGlobalData.current_stage = i
	
	#阶段变化检测
	if TetrisGlobalData.current_stage != _previous_stage:
		_previous_stage = TetrisGlobalData.current_stage
	
	# !!!! 警示进度写进公共数据区（版面绘制器每帧读它画渐变）
	_publish_big_attack_warning_progress()
	
	total_get_data()
	
	publish_make()
	
	if garbage_sent_time != 0 and garbage_sent_timer.is_stopped():
		# 新的一拍：本拍计时归零，并安排下一次出招（间隔带 ±50% 抖动）
		_send_elapsed = 0.0
		garbage_sent_timer.wait_time = garbage_sent_time + tower_rng.randf_range(-garbage_sent_time/2.0,garbage_sent_time/2.0)
		garbage_sent_timer.start()
	elif garbage_sent_time != 0:
		# 本拍进行中：累计实际经过时间，发招时用它还原「这段间隔内按 apm 应出的攻击量」
		_send_elapsed += delta
	
	_tower_climb(delta)


func total_get_data():
	# 游戏时长取自公共数据区（不再直接读 TetrisController 的字段）
	self_game_time = TetrisGlobalData.game_time
	
	garbage_sent_time = default_get_oneD_array_things(TetrisGlobalData.current_stage,stage_garbage_time)
	tower_current_dropped_mult = default_get_oneD_array_things(TetrisGlobalData.current_stage,tower_dropped_mult)
	pressure_mult = default_get_oneD_array_things(TetrisGlobalData.current_stage,pressure_mult_array)
	var max_percent = default_get_oneD_array_things(TetrisGlobalData.current_stage,stage_percent_apm) + extra_percent_apm
	if max_percent > 1:
		max_percent = 1
	TetrisGlobalData.current_apm = total_apm * max_percent
	garbage_collect_percent = default_get_oneD_array_things(TetrisGlobalData.current_stage,garbage_collect_percent_array)
	garbage_divide_percent = default_get_oneD_array_things(TetrisGlobalData.current_stage,garbage_divide_percent_array)
	TetrisGlobalData.garbage_messy = default_get_oneD_array_things(TetrisGlobalData.current_stage,garbage_hole_change_percent_array)
	# 重力/锁延：走 TetrisController 的 setter，除字段外还要同步对应计时器的 wait_time
	# （只改字段的话，关卡/Buff 设置的重力与锁延不会真正生效）
	TetrisGlobalData.tetris_controller.set_gravity_drop_time(default_get_oneD_array_things(TetrisGlobalData.current_stage,gravity_drop_time_array))
	TetrisGlobalData.tetris_controller.set_lock_delay(default_get_oneD_array_things(TetrisGlobalData.current_stage,lock_delay_array))

##惩罚处理
func publish_make():
	for i in range(0,publish_time_array.size()):
		if self_game_time > publish_time_array[i]:
			publish_stage = i
	
	if publish_make_finish != publish_stage:
		if publish_stage == 1:
			TetrisGlobalData.garbage_line_controller.add_solid_garbage(2)
		if publish_stage == 2:
			publish_mult_attack = 1.2
		if publish_stage == 3:
			TetrisGlobalData.garbage_line_controller.add_solid_garbage(3)
		if publish_stage == 4:
			publish_mult_attack = 1.5
		if publish_stage == 5:
			TetrisGlobalData.garbage_line_controller.add_solid_garbage(5)
	
		publish_make_finish = publish_stage

##爬塔米数主要处理
func _tower_climb(delta: float):
	if tower_speed_meter < tower_lowest_speed:
		tower_speed_meter = tower_lowest_speed
	elif tower_speed_meter > tower_lowest_speed:
		var x = tower_speed_meter
		#降速公式计算
		#这是第一版
		#tower_speed_meter -= ((x*log(x) + x)/120.0) * delta * tower_current_dropped_mult
		#这是第二版
		tower_speed_meter -= min((ceil(0.4*pow(x,1.5)*log(x))/75.0),1) * delta * tower_current_dropped_mult
	else:
		pass
	
	#TODO::制作一个特殊的分界线，在分界线下无速度加成，在上有微弱加成，突破界限后加成幅度突变上涨并且触发特殊特效，持续到回落界限下位置
	
	TetrisGlobalData.tower_meter += tower_speed_meter * delta
	
	# 维护「最近一分钟爬升米数」窗口 → 真实速度（m/s）
	_update_meter_window(delta)

## 维护「窗口内爬升米数」并算出真实涨米速度（m/s），与 TetrisController 的 PPM / RPM / 短期 APM 同口径：
##   · 开局未满 meter_window_span 秒：分母用「已运行时间」放缩 —— 也就是把这段时间爬升的米数
##     折算成每秒多少米（例如 5 秒爬了 10m → 2.0 m/s），避免开局因为窗口没满而读数为 0 或偏小；
##   · 满 meter_window_span 秒之后：分母固定为窗口长度 —— 即「最近一分钟爬升的米数 ÷ 60」。
## 因为直接读 tower_meter 的位置差，所以「持续爬升」和「消行/抵消/击杀一次性奖励米数」都会自然计入。
func _update_meter_window(delta: float) -> void:
	_meter_clock += delta
	_meter_sample_timer += delta
	# 采样：开局立刻记一个点，之后每 meter_window_sample_interval 秒记一个点
	if _meter_samples.is_empty() or _meter_sample_timer >= meter_window_sample_interval:
		_meter_sample_timer = 0.0
		_meter_samples.append({"time": _meter_clock, "meter": TetrisGlobalData.tower_meter})
	
	# 分母：未满一个窗口时用已运行时间放缩，满了之后用窗口长度
	var span: float = minf(meter_window_span, _meter_clock)
	if span <= 0.0:
		TetrisGlobalData.tower_real_speed_meter = 0.0
		return
	
	# 丢掉窗口外的采样点（保留最新的一个作参照）
	var cutoff: float = _meter_clock - span
	while _meter_samples.size() > 1 and float(_meter_samples[0]["time"]) < cutoff:
		_meter_samples.pop_front()
	
	# 分子：窗口内实际爬升的米数（参照点是最早的采样点；未满窗口时它就是开局那个点）
	var oldest: Dictionary = _meter_samples[0]
	TetrisGlobalData.tower_real_speed_meter = (TetrisGlobalData.tower_meter - float(oldest["meter"])) / span

## 奖励米数入账（消行/抵消奖励与击杀奖励都走这里）。
## 真实速度是按 tower_meter 的窗口增量算的，所以这里只要加进总米数，速度表就会自动反映出来。
func _add_reward_meter(amount: float) -> void:
	if amount <= 0.0:
		return
	TetrisGlobalData.tower_meter += amount

## 爬塔速度表用的「真实速度」：最近一分钟实际爬升的米数 ÷ 秒数（m/s）。
## 与名义速度 tower_speed_meter 的区别：名义速度只看持续爬升，不含消行/击杀一次性给的奖励米数。
func get_real_speed_meter() -> float:
	return TetrisGlobalData.tower_real_speed_meter

##塔的模拟伤害攻击
func _try_sent_garbage():
	# 这段间隔内按 apm 应出的行数 = apm / 60 × 实际间隔（apm 是每分钟的固定量，间隔不定，用它还原这一拍的攻击量）。
	# 行数只能取整，零头累加到下一拍，保证长期总量恰好是 apm（用 ceil 会把每拍的零头都补成 1 行，凭空放大总量）。
	var interval : float = _send_elapsed
	if interval <= 0.0:
		interval = garbage_sent_time                     # 兜底：直接调用/首拍
	interval = clampf(interval, 0.0, maxf(garbage_sent_time, 0.001) * 2.0)  # 卡顿/暂停后不补发一整段
	_send_elapsed = 0.0
	attack_remainder += TetrisGlobalData.current_apm / 60.0 * interval
	var decided_attack : int = int(floor(attack_remainder))
	attack_remainder -= float(decided_attack)
	var i = 0
	while decided_attack > 0:
		var j = tower_rng.randf()
		decided_attack -= 1
		i += 1
		if j < garbage_divide_percent:
			collected_garbage.append(i)
			i = 0
		if decided_attack == 0:
			if i != 0:
				collected_garbage.append(i)
			break
	# 这一拍不足 1 行（零头已留到下一拍）：不做「攒大招 / 收集计数 / 发送」判定，
	# 否则会在空批次上凑满 collected_count 触发一次没有攻击的 !!!! 警示
	if collected_garbage.is_empty():
		return
	if tower_rng.randf() > garbage_collect_percent:
		if collected_count >= warning_count and big_attack_enter_array.size() == 0:
			big_attack_enter_array = collected_garbage.duplicate()
			collected_garbage.clear()
			_quick_big_attack_clear(4)
			big_attack_delay_timer.start()
			TetrisGlobalData.big_attack_warning_started.emit()
		else:
			_tower_garbage_sent(collected_garbage)
			collected_garbage.clear()
		collected_count = 0
	else:
		i = floor(collected_garbage.size() / 2.0)
		var temp_sent_garbage : Array
		while i > 0:
			i -= 1
			temp_sent_garbage.append(collected_garbage[0])
			collected_garbage.remove_at(0)
		_tower_garbage_sent(temp_sent_garbage)
		collected_count += 1

func _tower_garbage_sent(attack: Array):
	# 倍率统一由 get_pressure_mult() 给出（pressure_mult × send_mult_attack × publish_mult_attack）
	var mult : float = get_pressure_mult()
	for i in attack:
		# 乘倍率后的行数同样只取整数、零头累加，保证总量恰为「攻击行数 × 倍率」（ceil 会按段放大）
		send_remainder += float(i) * mult
		var rows : int = int(floor(send_remainder))
		if rows > 0:
			send_remainder -= float(rows)
			TetrisGlobalData.garbage_line_controller.add_attack(rows)

##快速重新分割攻击储存列表并形成!!!!攻击
func _quick_big_attack_clear(segment: int):
	var total_attack: int = 0
	for i in big_attack_enter_array:
		total_attack += i
	big_attack_enter_array.clear()
	# 乘倍率时也用零头累加（而不是 ceil），避免大招总量被向上取整放大；
	# 倍率同样只用 get_pressure_mult()
	send_remainder += float(total_attack) * get_pressure_mult()
	total_attack = int(floor(send_remainder))
	send_remainder -= float(total_attack)
	for i in range(0,segment):
		if total_attack <= segment_line:
			big_attack_enter_array.append(total_attack)
			total_attack = 0
			break
		big_attack_enter_array.append(segment_line)
		total_attack -= segment_line
	if total_attack != 0:
		big_attack_enter_array.append(total_attack)

##!!!!攻击警示器
func _warning_big_collected_enter():
	TetrisGlobalData.big_attack_warning_ended.emit()
	TetrisGlobalData.garbage_line_controller.add_attack(big_attack_enter_array[0])
	if big_attack_enter_array.size() > 1:
		big_attack_delay_timer.wait_time = 0.5
		big_attack_enter_array.remove_at(0)
		big_attack_delay_timer.start()
	else:
		big_attack_delay_timer.wait_time = big_attack_delay
		big_attack_enter_array.clear()

##内置的检索，默认超出列表范围时返回列表最后一项，仅能用于一维列表
func default_get_oneD_array_things(id:int,array:Array):
	if id >= array.size():
		return array[array.size()-1]
	else:
		return array[id]

## 米数/速度增长。
## is_defence=true 表示「抵消垃圾行」得到的防御奖励（由 garbage_line_controller.offset_garbage()
## 的结果经 TetrisController 传入）：米数与速度的计算与普通攻击奖励完全一致，
## 只是飘字用红色，以便和普通攻击奖励（绿色）区分开。
func attack_increase_tower(attack:float, is_defence:bool = false):
	var meter_gain : float = attack * attack_to_meter_mult
	# 走奖励米数入账：总米数 + 真实速度池（速度表要反映这部分米数）
	_add_reward_meter(meter_gain)
	
	tower_speed_meter += attack * attack_to_speed_mult
	
	#在米数位置朝上弹出 "+X.XXm" 字样（幅度小、衰减快，避免遮挡版面）
	if attack > 0.0:
		_popup_meter_gain(meter_gain, MeterPopupType.OFFSET_REWARD if is_defence else MeterPopupType.NORMAL)

## 在「爬塔米数」文字位置弹出一条 "+X.XXm" 飘字。
## 位置由 board_drawer.get_tower_meter_text_position() 给出（版面下侧居中，与米数文字同点，
## 因此不会遮挡版面）；
## 运动：把 drift 交给 TextPrinter，由其按 attack_popup_drift_decay 做指数减速
##（加速度由快变慢：初速 80px/s 起步，随即迅速变慢），加上随机横向速度与 ±10° 倾斜，
## 在淡出结束前总位移约 18px（不到 1 格），随后淡出消失。
## popup_type 只决定颜色：NORMAL=绿色 / OFFSET_REWARD=红色 / KILL_REWARD=金色。
## 横向位置由 _resolve_popup_offset_x() 按实际文字宽度避让（见上方说明），不会与在场飘字完全重叠。
func _popup_meter_gain(gain: float, popup_type: MeterPopupType = MeterPopupType.NORMAL) -> void:
	if not attack_popup_enabled or TetrisGlobalData.text_printer == null or gain <= 0.0:
		return
	if TetrisGlobalData.board_drawer == null:
		return
	_spawn_meter_popup(gain, int(popup_type))

## 真正生成一条飘字：算字号/颜色 → 找一个不与在场飘字完全重叠的横向位置 → 交给 TextPrinter
func _spawn_meter_popup(gain: float, popup_type: int) -> void:
	var base_size: float = attack_popup_font_size_ratio * float(TetrisGlobalData.board_cell_size)
	var font_size: float = base_size * _popup_font_scale(gain)
	var text: String = "+%.2fm" % gain
	var popup_color: Color = attack_popup_color
	var popup_outline: Color = attack_popup_outline_color
	match popup_type:
		MeterPopupType.OFFSET_REWARD:
			popup_color = attack_popup_offset_color
			popup_outline = attack_popup_offset_outline_color
		MeterPopupType.KILL_REWARD:
			popup_color = attack_popup_kill_color
			popup_outline = attack_popup_kill_outline_color
	
	# 横向位置：先按随机方向意愿，再按实际文字宽度避让在场飘字（普通奖励 + 抵消奖励同时出现时不会压在一起）
	var half_w: float = _popup_text_width(text, font_size) * 0.5
	var desired_dir: float = tower_rng.randf_range(-1.0, 1.0) if tower_rng else 0.0
	var x_off: float = _resolve_popup_offset_x(desired_dir * attack_popup_spread, half_w)
	_register_popup_box(x_off, half_w)
	
	# 「往哪边偏 → 就往哪边飞、往哪边倾」：方向取最终落点的符号，幅度按 spread 归一（避让到很外侧时封顶）
	var fly_dir: float = clampf(x_off / maxf(attack_popup_spread, 1.0), -1.0, 1.0)
	var center: Vector2 = TetrisGlobalData.board_drawer.get_tower_meter_text_position()
	var popup_pos: Vector2 = Vector2(center.x + x_off, center.y)
	var drift: Vector2 = Vector2(fly_dir * attack_popup_drift_x, -attack_popup_rise_speed)
	var rotation_deg: float = fly_dir * attack_popup_rotate_deg  # 角度偏移量：±attack_popup_rotate_deg
	
	# persistent=false → 每次调用新增一条并各自淡出，连续消行时自然叠成一小簇
	# alignment=CENTER → position 即文本中心，旋转也绕该中心进行
	# 同一个 key 下每条各自持有颜色，所以红/绿可以混在一起同时飘
	TetrisGlobalData.text_printer.show_text(attack_popup_key, text, popup_pos,
		popup_color, popup_outline, font_size,
		false, 1.0, attack_popup_display_time, attack_popup_fade_time,
		drift, HORIZONTAL_ALIGNMENT_CENTER,
		attack_popup_drift_decay, rotation_deg)

## 飘字字号换算：随单次米数增幅变大而变大，但趋势逐渐变缓（对数），并受上限约束。
func _popup_font_scale(gain: float) -> float:
	var ref: float = maxf(attack_popup_grow_ref, 0.001)
	var t: float = log(1.0 + maxf(gain, 0.0) / ref)
	return clampf(1.0 + attack_popup_font_grow * t, 1.0, maxf(attack_popup_max_font_scale, 1.0))

## 量出飘字字符串的像素宽度（用实际绘制的那套字号取整规则，保证避让算得准）
func _popup_text_width(text: String, font_size: float) -> float:
	var font_size_int: int = maxi(1, roundi(font_size))
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_int).x

## 记下一条飘字的横向占位，供后续飘字避让；到点自动过期（不再阻塞别人）
func _register_popup_box(x_off: float, half_w: float) -> void:
	_prune_popup_boxes()
	_popup_boxes.append({
		"x": x_off,
		"half_w": half_w,
		"until_msec": Time.get_ticks_msec() + int(maxf(attack_popup_anti_overlap_time, 0.0) * 1000.0),
	})

## 清掉已经淡出完毕的占位记录
func _prune_popup_boxes() -> void:
	if _popup_boxes.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var kept: Array = []
	for box: Dictionary in _popup_boxes:
		if int(box["until_msec"]) > now:
			kept.append(box)
	_popup_boxes = kept

## 返回与 (x_off, half_w) 重叠过多的第一条在场飘字；没有则返回空字典。
## 允许的重叠量 = attack_popup_max_overlap_ratio × 较窄那条字的宽度（所以允许部分重叠，只是不许完全叠住）
func _first_overlapping_box(x_off: float, half_w: float) -> Dictionary:
	for box: Dictionary in _popup_boxes:
		var other_half: float = float(box["half_w"])
		var overlap: float = (half_w + other_half) - absf(x_off - float(box["x"]))
		if overlap > _popup_allowed_overlap(half_w, other_half):
			return box
	return {}

## 两条飘字之间允许的横向重叠量（像素）
func _popup_allowed_overlap(half_a: float, half_b: float) -> float:
	return attack_popup_max_overlap_ratio * 2.0 * minf(half_a, half_b)

## 给新飘字选横向偏移（相对米数文字中心，像素）：
## 先用随机意愿位置；若与在场飘字重叠过多，就贴着那条往旁边让，优先选「不超额重叠且离中心最近」的位置。
## 不设偏移上限：宁可让远一点，也不让两条字完全叠在一起（允许部分重叠）。
func _resolve_popup_offset_x(desired_x: float, half_w: float) -> float:
	_prune_popup_boxes()
	var x_off: float = desired_x
	for _i in range(8):
		var hit: Dictionary = _first_overlapping_box(x_off, half_w)
		if hit.is_empty():
			return x_off
		var other_half: float = float(hit["half_w"])
		var push: float = half_w + other_half - _popup_allowed_overlap(half_w, other_half)
		var left_x: float = float(hit["x"]) - push
		var right_x: float = float(hit["x"]) + push
		# 左右两个候选里，挑真正不超额重叠的那个（离中心更近者优先）；都还压着就挑离中心近的继续让
		var best_dist: float = INF
		var best_x: float = INF
		for cand: float in [left_x, right_x]:
			if _first_overlapping_box(cand, half_w).is_empty() and absf(cand) < best_dist:
				best_dist = absf(cand)
				best_x = cand
		if best_x < INF:
			x_off = best_x
		else:
			x_off = left_x if absf(left_x) <= absf(right_x) else right_x
	return x_off

##尝试给予击杀奖励，通过输入攻击后进行随机击杀计算
##每次击杀命中都会在米数位置弹出金色 "+X.XXm"，数值为这一次实际加到的米数
##（= kill_reward[0] 减去随米数增长的随机衰减，再 snapped 到 0.1，不是 kill_reward[0] 原值）
func try_give_kill_reward(attack:int):
	# TODO::使击杀奖励跟随高度进行适当的变化和击杀变难
	var killer_spike : int = base_killer_spike + round(TetrisGlobalData.tower_meter / 2000.0)
	var kill_possible_percent : float = base_kill_possible_percent - TetrisGlobalData.tower_meter / 1000.0 / 100.0
	
	var try_times : int = floor(1.0 * attack / killer_spike)
	var last_attack : int = attack - try_times * killer_spike
	if try_times > 0:
		for i in range(0,try_times):
			extra_percent_apm += 0.03
			if tower_rng.randf() <= kill_possible_percent:
				_give_kill_reward_meter()
	if tower_rng.randf() <= kill_possible_percent * last_attack / killer_spike / 5:
		_give_kill_reward_meter(false)

## 结算一次击杀命中：加米数与速度、计数 +1，并弹出金色飘字。
## grant_apm_bonus=true 时额外给 APM 成长（满 killer_spike 的整数次命中给，余数命中原实现不给）。
## 注意：飘字用的是「本次实际加到的米数」（随机衰减 + snapped 之后的值），
## 与上面的随机数调用顺序保持一致（先米数、后速度），以免影响 TOWER_CLIMB 随机流的复现。
func _give_kill_reward_meter(grant_apm_bonus: bool = true):
	var meter_gain: float = snapped(kill_reward[0] - tower_rng.randf_range(0,min(TetrisGlobalData.tower_meter / 500.0,8)),0.1)
	# 走奖励米数入账：总米数 + 真实速度池（速度表要反映这部分米数）
	_add_reward_meter(meter_gain)
	tower_speed_meter += snapped(kill_reward[1] - tower_rng.randf_range(0,min(tower_speed_meter / 10.0,8)),0.1)
	TetrisGlobalData.tower_kill_count += 1
	if grant_apm_bonus:
		extra_percent_apm += 0.1
	_popup_meter_gain(meter_gain, MeterPopupType.KILL_REWARD)
