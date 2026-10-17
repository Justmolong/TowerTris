extends Node

## 游戏内公共数据区（Autoload：TetrisGlobalData）
##
## ============ 为什么要有这个文件 ============
## tetris.tscn 里的各节点（版面绘制 / 方块控制 / Bag / 垃圾行 / 消行 / 塔 / 文本 / Spike）
## 过去彼此通过 @export NodePath 连线、并直接读写对方的成员变量：
##   · 连线一多，改节点名或把节点挪进别的场景就会静默失效（所以每个文件都散落着 auto_find 兜底）；
##   · 任意两个节点都能互访，改动 A 的字段不知道会影响谁。
##
## 现在统一改成「一切经由公共数据区」：
##   1) 节点注册表（见「一」）：节点在 _enter_tree() 里 register_node(self) 自注册，
##      公共数据区按类型登记引用；其它节点只认公共数据区，不再认具体节点，
##      场景文件里也不再需要任何 NodePath 连线。
##   2) 共享状态（见「二」）：**变量本身住在这里**（不是转发属性、不存副本）。
##      节点只是这些数据的读写者 —— 例如版面绘制器读 board_grid_*/board_cell_size 来画，
##      塔读/写 tower_meter、current_stage…，垃圾行控制器读/写 garbage_*。
##      因此「谁拥有」不再重要，也不会出现「节点 A 缓存一份、节点 B 再存一份」的不同步问题。
##   3) buff / 关卡初始化数据（见「三」）：buff_chose_area 写入这里，**由各节点自己读走**需要的键；
##      公共区域只存数据 + 给取值入口，不认识任何键名。
##   4) 公共事件（见「四」）：一对多的事件型回调走这里的信号，
##      发射方不需要认识接收方，接收方通过公共区域连接。
##
## ============ 生命周期 ============
## 整棵 tetris.tscn 的 _enter_tree 全部先于任何 _ready 完成，所以「第一个 _ready 跑起来时注册表
## 已经完整」。当所有注册节点都 _ready 之后，这里自动且同步地执行一次 apply_init_data()，
## 时机与过去「TowerController._ready 里做分发」完全等价（都在本帧 _process 之前）。
## 另外：
##   · 安全网：万一有节点忘了 notify_node_ready()，初始化数据最迟在本帧末补上（并 push_warning）；
##   · 共享状态复位：共享变量住在 Autoload 里，不会随场景销毁而重置，
##     所以每进入一个新场景都会用「启动时记下的默认值」复位一次（见 _reset_shared_state），
##     避免上一局的米数/版面/方块状态被带进下一局。


# ============================================================
# 一、节点注册表
# ============================================================

## 场景内各节点的引用（由节点自身在 _enter_tree 时注册，场景切换时自动清空）
var board_drawer: TetrisBoardDrawer = null
var tetris_controller: TetrisController = null
var bag_controller: TetrisBagController = null
var garbage_line_controller: TetrisGarbageLineController = null
var clear_line_controller: TetrisClearLine = null
var tower_controller: TowerController = null
var text_printer: TextPrinter = null
var spike_display: SpikeDisplay = null

## 本轮场景已注册的节点（用于判断「是否全部就绪」）
var _registered_nodes: Array[Node] = []
## 本轮场景已上报 _ready 的节点数
var _ready_count: int = 0
## 本轮场景的 buff 初始化数据是否已分发（保证只分发一次）
var _init_applied: bool = false


## 节点自注册（在各节点的 _enter_tree() 里调用）。
## 注意：整棵场景树的 _enter_tree 都先于任何 _ready 完成，因此第一个 _ready 时注册表已完整。
func register_node(node: Node) -> void:
	if node == null:
		return
	# 场景切换时旧节点会自行注销；这里再兜一次底，避免持有已释放节点
	_prune_registered_nodes()
	var is_new_scene: bool = _registered_nodes.is_empty()
	if is_new_scene:
		_ready_count = 0
		_init_applied = false
		_used_init_keys.clear()
		# 共享状态住在本 Autoload 里，不会随场景销毁自动归零 → 新的一局开始前复位
		_reset_shared_state()
	# 按类型登记（未登记的节点类型不进入注册表，也不参与「全部就绪」计数）
	if node is TetrisBoardDrawer:
		board_drawer = node
	elif node is TetrisController:
		tetris_controller = node
	elif node is TowerController:
		tower_controller = node
	elif node is TetrisBagController:
		bag_controller = node
	elif node is TetrisGarbageLineController:
		garbage_line_controller = node
	elif node is TetrisClearLine:
		clear_line_controller = node
	elif node is TextPrinter:
		text_printer = node
	elif node is SpikeDisplay:
		spike_display = node
	else:
		return
	if not _registered_nodes.has(node):
		_registered_nodes.append(node)
	if is_new_scene:
		# 安全网：正常情况下 apply_init_data() 会由最后一个节点的 notify_node_ready() 同步触发
		_apply_init_data_safety.call_deferred()


## 节点就绪上报（在各节点的 _ready() 末尾调用）。最后一个上报的节点会触发 buff 初始化数据分发。
func notify_node_ready(node: Node) -> void:
	if not _registered_nodes.has(node):
		return
	_ready_count += 1
	if _init_applied:
		return
	if _ready_count >= _registered_nodes.size():
		apply_init_data()


## 节点注销（在各节点的 _exit_tree() 里调用）：清空引用，避免公共数据区持有已释放的节点
func unregister_node(node: Node) -> void:
	_registered_nodes.erase(node)
	if board_drawer == node:
		board_drawer = null
	if tetris_controller == node:
		tetris_controller = null
	if bag_controller == node:
		bag_controller = null
	if garbage_line_controller == node:
		garbage_line_controller = null
	if clear_line_controller == node:
		clear_line_controller = null
	if tower_controller == node:
		tower_controller = null
	if text_printer == node:
		text_printer = null
	if spike_display == node:
		spike_display = null


## 丢弃已被释放的注册项（正常情况下 _exit_tree 已注销，这里只作兜底）
func _prune_registered_nodes() -> void:
	if _registered_nodes.is_empty():
		return
	var kept: Array[Node] = []
	for n: Node in _registered_nodes:
		if is_instance_valid(n):
			kept.append(n)
	_registered_nodes = kept


## 安全网：若还有节点没上报就绪，就在本帧末补一次初始化（正常路径不会走到这里）
func _apply_init_data_safety() -> void:
	if _init_applied:
		return
	push_warning("TetrisGlobalData: 仍有节点未上报 _ready（缺少 notify_node_ready 调用），"
		+ "buff 初始化数据延后到本帧末应用")
	apply_init_data()


# ============================================================
# 二、共享状态（变量住在这里；各节点只读写这些变量）
# ============================================================
# 说明：
#   · 这些变量是**唯一的存储**（不是转发到某个节点），节点不再各存一份；
#   · 只有「被两个以上节点读写」的状态才放在这里 —— 纯内部状态（计时器、动画参数、
#     飘字样式、随机窗口采样…）仍然留在各自节点里；
#   · 命名约定：按归属加前缀 tower_ / board_ / piece_ / garbage_ / spike_，
#     以及 current_stage / current_apm / game_time / no_hold 这几个全局量。

# ---------- 2.1 塔（TowerController 每帧写入，版面绘制器 / 结算读） ----------

## 当前爬塔米数（m）
var tower_meter: float = 0.0

## 真实爬塔速度（m/s）：最近一个统计窗口内的米数增量 ÷ 秒数
var tower_real_speed_meter: float = 0.0

## 当前层数（阶段）
var current_stage: int = 0

## 当前 APM（含关卡倍率与 buff 成长）
var current_apm: float = 0.0

## 累计击杀数
var tower_kill_count: int = 0

## !!!! 大招警示进度（0→1）：塔每帧按警示计时器写入，版面绘制器读它画渐变
var tower_big_attack_progress: float = 0.0

# ---------- 2.2 版面几何（TetrisBoardDrawer 计算/写入，所有节点读来换算坐标） ----------

## 网格宽度（列数）
var board_grid_width: int = 10

## 网格可见高度（行数）
var board_grid_height: int = 20

## 网格最大高度（含上方预留区，行数）
var board_grid_max_height: int = 100

## 可见区域上方预留行数（垃圾槽扩展用，不绘制背景/网格线）
var board_above_visible_rows: int = 70

## 可玩高度（行）= 可见高度 + 上方预留行数（派生值，不存储；与版面绘制器的绘制口径一致）
var board_playable_height: int:
	get:
		return board_grid_height + board_above_visible_rows

## 格子边长（像素；窗口缩放后由版面绘制器重算）
var board_cell_size: int = 24

## 版面基准点（左上角像素坐标；自动居中后由版面绘制器重算）
var board_offset_x: int = 0
var board_offset_y: int = 0

## Hold 框高度（格子数；消行/连击文本定位用）
var board_hold_display_height: int = 4

# ---------- 2.3 版面内容（任何模块都可读写；版面绘制器只读它来绘制） ----------
# 语义要点：**手上方块的格子也写在这里**（出块/移动时写入、锁定后自然保留），
# 所以 board_data = 「已锁定的堆叠 + 当前方块」的完整画面；
# 要区分哪些格子属于手上方块，用 piece_shape + piece_position 自己算。
# 行方向：y=0 是版面最上方（含上方预留区），y 越大越靠下；可玩区底行 = board_playable_height - 1。

## 版面格子内容：[y][x] = null（空）或 Color
var board_data: Array = []

## 每格的锁定时间戳（毫秒；0 = 空/无记录），与 board_data 同维度；隐形模式的渐隐判定用
var board_cell_lock_times: Array = []


## 按当前几何重建空版面（等价于旧 board_drawer._init_board_data / clear_board）
func board_reset() -> void:
	board_data.clear()
	board_cell_lock_times.clear()
	for _y in range(board_grid_max_height):
		var row: Array = []
		var lock_row: Array = []
		for _x in range(board_grid_width):
			row.append(null)     # null = 空格子
			lock_row.append(0)   # 0 = 未锁定
		board_data.append(row)
		board_cell_lock_times.append(lock_row)


## 坐标是否在版面缓冲范围内
func board_is_inside(x: int, y: int) -> bool:
	if x < 0 or y < 0 or y >= board_data.size():
		return false
	var row: Array = board_data[y]
	return x < row.size()


## 取某格颜色（null = 空）
func board_get_cell(x: int, y: int) -> Variant:
	if not board_is_inside(x, y):
		return null
	return board_data[y][x]


## 取某格的锁定时间戳（毫秒；0 = 空/无记录）
func board_get_cell_lock_time(x: int, y: int) -> int:
	if not board_is_inside(x, y):
		return 0
	return int(board_cell_lock_times[y][x])


## 写某格颜色（等价于旧 board_drawer.set_cell_color）：
## 非空格且不是垃圾色 → 时间戳记成「刚刚落下」；写成空格 → 时间戳清零。
func board_set_cell(x: int, y: int, color: Variant) -> void:
	if not board_is_inside(x, y):
		return
	var c: Variant = board_normalize_cell_color(color)
	board_data[y][x] = c
	if c != null and not board_is_garbage_color(c):
		board_cell_lock_times[y][x] = Time.get_ticks_msec()
	elif c == null:
		board_cell_lock_times[y][x] = 0


## 写某格颜色并显式指定锁定时间戳（整版位移类操作用：消行下移 / 垃圾上涨 / Allspin 惩罚）。
## 这些操作只是把已有格子搬到新行，若走 board_set_cell()，时间戳会被刷成「刚刚落下」，
## 隐形模式（tetris_invisible == 1）下整片版面会突然显形 —— 按规则只有「刚放下不久的方块」
## 和「到点重新现形的方块」才应该可见。
func board_set_cell_with_lock_time(x: int, y: int, color: Variant, lock_time: int) -> void:
	if not board_is_inside(x, y):
		return
	var c: Variant = board_normalize_cell_color(color)
	board_data[y][x] = c
	board_cell_lock_times[y][x] = lock_time if c != null else 0


## 规范化格子颜色：null / 非颜色 / 黑色 都视为空格
func board_normalize_cell_color(color: Variant) -> Variant:
	if color == null:
		return null
	if typeof(color) != TYPE_COLOR:
		return null
	if color == Color.BLACK:
		return null
	return color


## 该颜色是否属于垃圾行（普通 / 缓冲中 / 实心）—— 垃圾行不参与「刚刚落下」的渐隐计时
func board_is_garbage_color(color: Variant) -> bool:
	if typeof(color) != TYPE_COLOR:
		return false
	return color == garbage_color \
		or color == garbage_buffered_color \
		or color == garbage_solid_color

# ---------- 2.4 方块状态（TetrisController 读写；消行 / 垃圾行 / 版面 / bot 桥接读） ----------

## 当前方块的形状矩阵
var piece_shape: Array = []

## 当前方块在版面坐标里的位置
var piece_position: Vector2i = Vector2i.ZERO

## 当前方块类型（"I"/"T"/…）
var piece_type: String = "I"

## 暂存区方块类型（空 = 暂存区为空）
var piece_hold_type: String = ""

## 本回合还能不能用暂存
var piece_can_hold: bool = true

## 当前旋转系统（0=ASC / 1=SRS / 2=ARS / 3=NONE）
var piece_rotation_system: int = 0

## 当前方块所处的旋转档位（踢墙 / Spin 判定 / bot 复现用）
var piece_rotation_index: int = 0

## 最近一次落块占据的格子（供 Spike 数字定位）
var piece_last_locked_cells: Array = []

## 最近一次落块的方块类型（Allspin 重复惩罚预警用）
var piece_last_locked_type: String = ""

# ---------- 2.5 垃圾行（TetrisGarbageLineController 读写；版面 / 消行 / bot 桥接读） ----------

## 垃圾行颜色（浅灰）
var garbage_color: Color = Color(0.5, 0.5, 0.5, 1.0)

## 实心垃圾行颜色（深灰，不可消除）
var garbage_solid_color: Color = Color(0.3, 0.3, 0.3, 1.0)

## 缓冲中垃圾行的底色（半透明暗红）
var garbage_buffered_color: Color = Color(0.5, 0.0, 0.0, 0.7)

## 每次锁定最多上涨的垃圾行数（也决定版面上 garbage_cap 横线的位置）
var garbage_cap: int = 3

## 垃圾行更换洞口的概率（0-1）
var garbage_messy: float = 0.9

## 实心垃圾行的行索引集合 {row_index: true}（垃圾行控制器维护；消行判定用「实心行不可消」）
var garbage_solid_rows: Dictionary = {}

## 垃圾缓冲时长（秒）
var garbage_buffer_duration: float = 3.0

## 版面版本号：垃圾行控制器每次改动版面都会 +1，供缓存/重算判断
var garbage_board_version: int = 0

# ---------- 2.6 版面显示状态（TetrisBoardDrawer 画；方块控制器写入其中几项） ----------

## Next 显示数量
var board_next_count: int = 6

## 是否显示 Next 区
var board_next_display_enabled: bool = true

## Next 区当前显示的方块数据（方块控制器写、版面绘制器画）
var board_next_pieces_data: Array = []

## 暂存区方块是否触发 Allspin_1 重复惩罚（预警显示用）
var board_hold_piece_penalty: bool = false

## 本局是否已结束（版面变暗的死亡遮罩由它驱动）
var board_is_game_over: bool = false

## Spike 数字的累加窗口（秒）：消行控制器启动时与自己的 Attack 累积窗口对齐
var spike_reset_time: float = 1.0

# ---------- 2.7 消行规则与状态（TetrisClearLine 读写；方块控制器与 bot 桥接读） ----------

## Spin 规则模式：0=正常（含Allspin）/1=只判T-Spin/2=全部降级为MiniSpin/3=不判定Spin/
## 4=正常判定，但触发 Spin（含Spin0）立刻上涨 clear_no_spin4_solid_rows 行实心行
var clear_no_spin: int = 0

## clear_no_spin==4 的惩罚量（实心垃圾行数，不受 garbage_cap 限制）
var clear_no_spin4_solid_rows: int = 20

## Allspin 规则：0=关 / 1=Allspin_1（同类型同行数→涨 1 行）/ 2=Allspin_2（同类型同行数→涨实心行）
var clear_allspin: int = 0

## Allspin_2 重复惩罚上涨的实心行数
var clear_allspin2_solid_rows: int = 20

## Allspin_2 重复惩罚的 bot 评估扣分（存的是负数，下发给 worker 前取绝对值）
var clear_allspin2_repeat_penalty: int = -1500

## BTB 加成系统：1=surge break（默认）/ 2=累加奖励（tetr.io S1 的 BTB 伤害系统）
var clear_btb_system_use: int = 1

## Perfect Clear 附加伤害
var clear_pc_damage: int = 6

## 当前连击数
var clear_combo_count: int = 0

## 当前 BTB 数
var clear_btb_count: int = 0

## 是否正处于消行延迟/消行动画中（消行控制器写；方块控制器与垃圾行控制器读）。
## 方块控制器用它判断「还不能出块」，垃圾行控制器用它判断「上涨要暂缓」。
var clear_animating_active: bool = false

# ---------- 2.8 其它全局量 ----------

## 本局游戏时长（秒，TetrisController 累计）
var game_time: float = 0.0

## NoHold 模式：禁用暂存（方块控制器不读 Hold 输入），同时不显示 Hold 框（版面绘制器）
var no_hold: bool = false

# ---------- 2.9 共享状态的复位 ----------
# 共享变量住在 Autoload 里，不会随场景销毁而回到默认值，所以每进入新场景要复位一次。
# 默认值不手写第二遍：Autoload 首次就绪时把「本文件声明的所有共享字段」的当前值记下来，
# 复位就是把这些值写回去 —— 以后新增共享字段只要照上面那样声明即可，不用改复位逻辑。

## 不属于共享状态、**不能**在换场景时复位的字段（节点引用由注册表管理；下面三个是跨场景传递的数据）
const _PERSISTENT_FIELDS: Array[String] = [
	"board_drawer", "tetris_controller", "bag_controller", "garbage_line_controller",
	"clear_line_controller", "tower_controller", "text_printer", "spike_display",
	"tower_init_data", "selected_buffs", "restore_buffs",
]

## 只读派生值，不进默认值表
const _DERIVED_FIELDS: Array[String] = ["board_playable_height"]

var _shared_defaults: Dictionary = {}


func _ready() -> void:
	# Autoload 的 _ready 先于主场景加载 → 此时记下的就是「出厂默认值」
	_capture_shared_defaults()


func _capture_shared_defaults() -> void:
	_shared_defaults.clear()
	for prop: Dictionary in get_property_list():
		if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var field: String = String(prop.get("name", ""))
		if field.begins_with("_") or _PERSISTENT_FIELDS.has(field) or _DERIVED_FIELDS.has(field):
			continue
		_shared_defaults[field] = get(field)


func _reset_shared_state() -> void:
	for field: String in _shared_defaults:
		var value: Variant = _shared_defaults[field]
		# 数组/字典要深拷贝，否则复用同一份默认值容器会被后续写入污染
		if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
			set(field, value.duplicate(true))
		else:
			set(field, value)


# ============================================================
# 三、buff / 关卡初始化数据（节点自己来读）
# ============================================================
# 数据由 buff_chose_area 在点 START 时写入；进入游戏后由**各节点自己**读走需要的键（谁用谁读）。
# 本文件只存数据 + 提供取值入口，**不认识任何键名、也不碰任何节点的成员变量**：
#   · 新增 / 重命名一个 buff 参数 → 只需改 BuffChoseData.json 和「用它的那个节点」，不用改本文件；
#   · 旧的「公共区域逐字段 push 给各节点」写法每加一个参数都要在这里同步改一处，
#     而且节点成员改名后容易漏改（参数就静默失效）—— 已废弃。
#
# 取值入口（读取成功会记录「该键被用过」，没人用过的键会在分发结束后报警，用来抓键名写错）：
#   init_has(key) / get_init_value(key, default) / get_init_float / get_init_int /
#   get_init_bool / get_init_array / get_init_dict / get_init_value_any(keys, default) / get_init_keys()
# 查找顺序：tower_init_data 顶层键 → extra_data_dict（键名对不上任何节点成员时 buff_chose_area 放这里），
# 所以节点只管按自己要的键名取值，不需要关心它存在哪一层。

const EXTRA_DATA_KEY: String = "extra_data_dict"

## 关卡初始数据：顶层键与 extra_data_dict 里的键都是「参数」，
## 具体哪个节点消费哪些键，由各节点的 apply_init_params() 自己声明。
var tower_init_data: Dictionary = {}

## 已选取的 buff 列表（供结算界面右侧列表展示）
## 元素形如 {"id": "Pressure1", "text": "高压I：apm总量增加20%"}
var selected_buffs: Array = []

## 标识：从结束界面返回 buff_chose_area 时是否恢复上次勾选
## 由 game_over / bot 退出时置 true，buff_chose_area 读取后立刻复位为 false
var restore_buffs: bool = false

## 本轮已被任何节点读过的初始化参数键（用于「没人读的参数」报警）
var _used_init_keys: Dictionary = {}


## extra_data_dict：键名对不上任何节点成员的那些参数（buff_chose_area 归类用；节点侧不必关心）
func get_extra_data_dict() -> Dictionary:
	var extra: Variant = tower_init_data.get(EXTRA_DATA_KEY, {})
	if typeof(extra) == TYPE_DICTIONARY:
		return extra
	return {}


## 本轮所有可用的初始化参数键（顶层 + extra_data_dict，去重；不含 extra_data_dict 容器本身）
func get_init_keys() -> Array[String]:
	var keys: Array[String] = []
	var seen: Dictionary = {}
	var sources: Array[Dictionary] = [tower_init_data, get_extra_data_dict()]
	for source: Dictionary in sources:
		for k: Variant in source:
			var key: String = String(k)
			if key == EXTRA_DATA_KEY or seen.has(key):
				continue
			seen[key] = true
			keys.append(key)
	return keys


## 该键是否存在（顶层或 extra_data_dict）。
## 注意：「问过这个键」也算读过——不少节点是 init_has() 判存在后直接置标志（不取数值），
## 若不在这里记使用，_warn_unused_init_keys() 会把这些键误报成「没人读」。
func init_has(key: String) -> bool:
	_used_init_keys[key] = true
	if tower_init_data.has(key):
		return true
	return get_extra_data_dict().has(key)


## 取初始化参数（不存在时返回 default_value）。节点侧统一走这个入口，不用关心参数在哪一层。
func get_init_value(key: String, default_value: Variant = null) -> Variant:
	if tower_init_data.has(key):
		_mark_init_key_used(key)
		return tower_init_data[key]
	var extra: Dictionary = get_extra_data_dict()
	if extra.has(key):
		_mark_init_key_used(key)
		return extra[key]
	return default_value


func get_init_float(key: String, default_value: float = 0.0) -> float:
	var v: Variant = get_init_value(key, null)
	return default_value if v == null else float(v)


func get_init_int(key: String, default_value: int = 0) -> int:
	var v: Variant = get_init_value(key, null)
	return default_value if v == null else int(v)


func get_init_bool(key: String, default_value: bool = false) -> bool:
	var v: Variant = get_init_value(key, null)
	return default_value if v == null else bool(v)


func get_init_array(key: String, default_value: Array = []) -> Array:
	var v: Variant = get_init_value(key, null)
	return v if typeof(v) == TYPE_ARRAY else default_value


func get_init_dict(key: String, default_value: Dictionary = {}) -> Dictionary:
	var v: Variant = get_init_value(key, null)
	return v if typeof(v) == TYPE_DICTIONARY else default_value


## 同一个参数有多个键名别名时，按顺序取第一个存在的
## （例：NoHold / no_hold、rotation_system / RotationSystem / RotateSystem）
func get_init_value_any(keys: Array, default_value: Variant = null) -> Variant:
	for k: Variant in keys:
		var key: String = String(k)
		if init_has(key):
			return get_init_value(key)
	return default_value


## 把「与该节点成员同名」的初始化参数一键写回该节点（节点自我覆盖用，例：TowerController.total_apm）。
## 纯自我反射：本函数不认识任何键名，也不会写该节点没有的成员。
## 注意：这里写的是**节点自己的**成员（塔的关卡数值等），共享状态不在此列。
func apply_matching_members(node: Node) -> void:
	if node == null:
		return
	var members: Dictionary = {}
	for prop: Dictionary in node.get_property_list():
		if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			members[String(prop.get("name", ""))] = true
	for key: String in get_init_keys():
		if members.has(key):
			node.set(key, get_init_value(key))


func _mark_init_key_used(key: String) -> void:
	_used_init_keys[key] = true


## 把 buff / 关卡初始化数据交给各节点（数据由节点自己读，这里不认任何键名）。
## 由 notify_node_ready() 在「场景内所有节点都就绪」时自动调用（幂等）。
## 节点按需实现下面两个方法（公共区域只用 has_method 泛化调用）：
##   apply_init_params()     阶段 1：读走属于自己的参数
##   finalize_init_params()  阶段 2：所有节点的参数都就位后的收尾（跨参数动作，如印刷初始版面）
func apply_init_data() -> void:
	if _init_applied:
		return
	_init_applied = true
	for node: Node in _registered_nodes:
		if is_instance_valid(node) and node.has_method("apply_init_params"):
			node.apply_init_params()
	for node: Node in _registered_nodes:
		if is_instance_valid(node) and node.has_method("finalize_init_params"):
			node.finalize_init_params()
	_warn_unused_init_keys()


## 报警：有参数没有任何节点读过（多半是 BuffChoseData.json 里键名写错，或参数已废弃）。
## 这条检查就是为了避免「buff 勾了却毫无效果、还不报错」这类问题。
func _warn_unused_init_keys() -> void:
	var unused: Array[String] = []
	for key: String in get_init_keys():
		if not _used_init_keys.has(key):
			unused.append(key)
	if unused.is_empty():
		return
	push_warning("TetrisGlobalData: 以下关卡/buff 初始化参数没有任何节点读取"
		+ "（键名写错？或参数已废弃）：" + ", ".join(unused))


# ============================================================
# 四、公共事件（信号）
# ============================================================
# 事件型的一对多回调放在这里：发射方只管 emit，不需要认识谁在听；接收方通过公共区域 connect。
# 这样「消行控制器 → 塔」「版面绘制器 → 方块控制器」「塔 → 版面绘制器」之间都不再互相持有引用。
#
# ⚠ 关于下面每个信号上的 @warning_ignore("unused_signal")：
#   GDScript 的 UNUSED_SIGNAL 判定**只看当前文件**——它要求信号在本文件里被 emit 或 connect。
#   而本节的信号按设计就是「定义在公共区域、由**别的节点** emit / connect」，分析器看不到，
#   于是会把 18 个信号全部误报为「定义了但没使用」。这是 Godot 对「自动加载事件总线」的已知误报，
#   官方给出的处理方式就是逐条标注 @warning_ignore("unused_signal")。
#   若将来某个信号确实没人 emit 了，请直接删掉信号本身（标注只屏蔽误报，不掩盖真死代码）。

## 打出了攻击 / 抵消了垃圾行，需要结算爬塔米数与速度
## （消行控制器与方块控制器都可能触发；is_defence=true 表示抵消垃圾行的防御奖励）
@warning_ignore("unused_signal")
signal tower_damage_dealt(amount: float, is_defence: bool)

## 攻击累积窗口结束，请求结算一次击杀奖励（amount = 窗口内累积的攻击点数）
@warning_ignore("unused_signal")
signal kill_reward_requested(amount: int)

## 版面内容被改写（关卡/Buff 的初始版面印刷完），需要重算方块位置与影子
@warning_ignore("unused_signal")
signal board_layout_changed()

## ---- 落块 → 消行判定 → 出块 这条主链路的三个通知 ----
# 统一顺序（有无「消行延迟」完全一致）：
#   1) 方块控制器锁定方块 → emit piece_locked
#   2) 消行控制器在订阅回调里完成判定与**全部版面变化**（消行位移 / 垃圾上涨 / Allspin 惩罚）
#      → emit lines_judged（方块控制器在此结算统计与抵消）
#   3) 消行控制器 → emit spawn_requested（方块控制器据此结算出块）
# 即：**判定 → 版面变化 → 结算 → 出块**，出块永远是最后一步。

## 落块结束：方块已写进版面、落块信息已记录、piece_shape 已清空。
## 消行控制器订阅它来做判定；本次落块的信息从共享区读：
##   piece_last_locked_cells / piece_last_locked_type / piece_rotation_index / board_data
@warning_ignore("unused_signal")
signal piece_locked()

## 消行判定结果包（消行控制器 → 方块控制器）。
## ⚠ 语义：发出时本次判定的**所有版面变化都已完成**。
##   cleared    本次消除的行数（0 = 没消行）
##   did_clear  是否真的执行了消行位移（出块 clutch 容错用）
##   damage     本次打出的攻击点数（cleared==0 时方块控制器不计入统计，与旧口径一致）
##   spin_text  本次 Spin 类型（空 = 非 Spin）
##   btb/combo  判定结束时的 BTB / 连击数
@warning_ignore("unused_signal")
signal lines_judged(cleared: int, did_clear: bool, damage: int, spin_text: String, btb: int, combo: int)

## 请求出块（消行控制器 → 方块控制器）：这只是「请求」，出块时机仍由方块控制器统一结算
## （locked 门 + 实际出块时刻 = 锁定时刻 + max(落块延迟, 消行延迟)）。
@warning_ignore("unused_signal")
signal spawn_requested()

## !!!! 大招警示开始 / 结束（版面绘制器负责画警示效果）
@warning_ignore("unused_signal")
signal big_attack_warning_started()
@warning_ignore("unused_signal")
signal big_attack_warning_ended()

## ---- 方块控制器 ⇄ 垃圾行控制器 ----
# 方向：垃圾行控制器只「发通知/发请求」，方块控制器「订阅并处理」，双方都不再直接调用对方。
# 需要返回值的查询（例如缓冲垃圾行数）仍保留为垃圾行控制器的公开查询方法。

## 整版上移**即将**发生（垃圾/实心行上涨、Allspin 惩罚；行数已按 garbage_cap 截断）：
## 方块控制器订阅后先把手上方块从版面缓冲里清掉，避免它被一起搬进新行。
## sync_piece=false 表示本次不需要同步方块（无活动方块，或调用方已自行处理）。
@warning_ignore("unused_signal")
signal board_shift_starting(sync_piece: bool)

## 整版上移**已完成**：方块控制器订阅后把手上方块按新位置重画
## （位置 = 原位置 - rows，含碰撞修正 / 重画 / 影子刷新 / 旋转记录同步）。
@warning_ignore("unused_signal")
signal board_shifted_up(rows: int, sync_piece: bool)

## 收到攻击（垃圾已进入缓冲队列）：方块控制器订阅后记入 RPM 统计
@warning_ignore("unused_signal")
signal garbage_attack_received(rows: int)

## 请求结束本局（垃圾上涨失败 / 方块堆积过高 / 方块被卡死等致命状况）
@warning_ignore("unused_signal")
signal game_over_requested(reason: String)

## 请求把本次攻击伤害用于抵消垃圾行：垃圾行控制器自己判断队列是否为空并结算；
## 抵消成功后由它直接发 tower_damage_dealt（防御奖励）
@warning_ignore("unused_signal")
signal garbage_offset_requested(damage: int)

## 请求在本次锁定后上涨垃圾行（方块控制器在「本次没消行」时发出；顺序在抵消之后）
@warning_ignore("unused_signal")
signal garbage_rise_requested()

## 请求给垃圾行队列追加攻击（方块控制器对外的 add_garbage_attack 入口用）
@warning_ignore("unused_signal")
signal garbage_attack_requested(rows: int)

## ---- 消行控制器 ⇄ 垃圾行控制器 ----

## 请求上涨实心垃圾行（Allspin_2 重复惩罚 / NoSpin4 惩罚；ignore_cap=true 时不受 garbage_cap 限制）
@warning_ignore("unused_signal")
signal solid_garbage_requested(rows: int, ignore_cap: bool)

## 请求直接插入 Allspin 惩罚垃圾行（不走缓冲队列）
@warning_ignore("unused_signal")
signal allspin_garbage_requested()

## 请求恢复「消行延迟期间被暂缓」的垃圾上涨
@warning_ignore("unused_signal")
signal garbage_rise_resume_requested()
