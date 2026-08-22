extends Node
class_name ColdClearBridge
## ColdClear 决策桥（自包含版本）
##
## 本桥自己启动 coldclear_worker.exe 子进程（通过 OS.execute_with_pipe），
## 并在后台线程执行阻塞的 GO 命令，把 ColdClear 的真实决策（移动路径）
## 逐步转为 BotAction 供 TetrisController 消费。
## 不再依赖外部 /root/ColdClearNative autoload（已删除）。

const WORKER_FILENAME := "coldclear_worker.exe"
const DLL_FILENAME := "cold_clear.dll"
## 开发/编辑器模式下 native 目录（res:// 直接映射项目磁盘目录）。
const NATIVE_RES_DIR := "res://rust/cold_clear_engine/native"
## 导出运行模式下 native 松散文件所在目录（exe 旁，由导出脚本复制）。
const NATIVE_EXE_SUBDIR := "native"
# ===== 冷Clear（ColdClear）搜索参数 · 控制文件：Scripts/bot_play/coldclear_bridge.gd（本文件） =====
## 发送给 ColdClear 时，可见窗口上方额外多带的行数（堆叠余量）。仅影响决策输入窗口，不影响棋盘。
const EXTRA_TOP_ROWS := 4
## 单次决策允许搜索的最大节点数（max_nodes）。越大越接近最优解，但耗时越久。
const MAX_NODES := 4000000000
## 单次决策至少搜索的节点数（min_nodes）。过小会提前停止、决策质量下降。
## 提高最低思考节点 → 每次决策至少搜索这么多节点，保证决策质量与稳定性。
const MIN_NODES := 100000
## 决策失败后的冷却时间（毫秒），避免每块都阻塞等待超时。
const FAIL_COOLDOWN_MS := 100
## 读取 worker 回复的超时（毫秒）。worker 卡住时回退默认 bot。
const READ_TIMEOUT_MS := 30000
const PIECE_ORDER := ["I", "O", "T", "L", "J", "S", "Z"]

# ===== 各类型消行/旋转与惩罚的决策权重（inspector 可调，随 S 命令下发，对应 Rust Standard 评估器）=====
# 伤害表/倍率/规则开关等由 buff（get_damage_tables / get_send_mult_attack / get_mult_defend）提供，
# 本桥不再持有这些；仅保留「各类型消行等的决策权重」与「惩罚权重」。
## 伤害评估倍率（影响 bot 对攻击伤害的重视程度）
@export var eval_mult: int = 100
## 攻击效率权重（攻击效率 = 本次攻击伤害 / 本次消除行数；越大 bot 越倾向高效攻击）
## 游戏内 T-Spin 单消 = 2伤害/1行（效率2.0）极高，开启后 bot 会按“每行伤害”排序，
## 让 tspin1/allspin1 这类高效率攻击优先于普通四消（4/4=1.0）与双消（1/2=0.5）。
@export var attack_efficiency_weight: int = 100
## bot 评估权重：维持 Back-to-Back（越大越倾向维持 BTB）
## 游戏 btb_count>1 时连续 spin/quad 每发 +1，btb_count>=4 时 +2（4BTB 以上续 BTB 收益极高），
## 且 btb>=4 时普通消行会释放 surge_break。故把维持 BTB 权重提得很高，让 bot 尽量把
## BTB 链延长到 4 及以上（连续 spin 也天然维持 combo，构造 BTB combo）。
@export var b2b_clear: int = 950
## bot 评估权重：放块后的堆叠最高点（负值=压高，越大越不压高）
@export var height: int = -90
## bot 评估权重：重复惩罚扣分（负值=降低该决策的选取值）
@export var allspin_repeat_penalty: int = 0
## 单消（1行）评估权重（负值=不倾向）
@export var clear1: int = -93
## 双消（2行）评估权重
@export var clear2: int = -260
## 三消（3行）评估权重
@export var clear3: int = -388
## bot 评估权重：四消（Tetris）
@export var clear4: int = 100
## T-Spin 单消评估权重（效率极高：2伤害/1行，攒 BTB 快；但单消后地形易乱，
## 故略低于 tspin2，让 bot 不盲目贪 spin1，乱地形时优先用 tspin2 修补并续 BTB）
@export var tspin1: int = 700
## T-Spin 双消评估权重（效率高：4伤害/2行；可修补 spin1 造成的地形混乱并续 BTB）
@export var tspin2: int = 700
## T-Spin 三消评估权重
@export var tspin3: int = -302
## Mini T-Spin 单消评估权重
@export var mini_tspin1: int = -18
## Mini T-Spin 双消评估权重
@export var mini_tspin2: int = -493
## 非T旋转（allspinmini / 全旋）单消评估权重（效率不错：2伤害/1行，可攒 BTB）
@export var allspin1: int = 520
## 非T旋转（allspin）双消评估权重
@export var allspin2: int = 185
## 非T旋转（allspin）三消评估权重
@export var allspin3: int = -202
## 非T旋转（allspin）消3+行（4行及以上）评估权重
@export var allspin3plus: int = -452
## 全消（Perfect Clear）评估权重
@export var perfect_clear: int = 0
## 连击（Combo）评估权重（带 BTB 的 combo 效率高；提高以激励 bot 连续消行构造 BTB combo）
@export var combo_garbage: int = 280
## 浪费 T 块（wasted T）评估权重（促使 T 必做成 spin，不浪费）
@export var wasted_t: int = -130
## 移动时间评估权重
@export var move_time: int = -3
## ColdClear 搜索并行线程数（0 = 自动按 CPU 核数-2，最大8；>0 固定线程数）。
## 多线程并行检索可显著加速搜索（尤其 MIN_NODES 较大时），但会占用更高 CPU。
@export var cc_threads: int = 8

## 请求完成信号（在主线程序发）
## reply 形如 "OK 0 3 L L L" / "DEAD" / "ERR <msg>" / "TIMEOUT"
signal move_ready(request_id: int, reply: String)

var _native_available: bool = false
var _native_cooldown_until: int = 0       # Time.get_ticks_msec() 时间戳

var _plan: Dictionary = {}                # { hold:bool, movements:Array[String] }
var _plan_index: int = 0
var _plan_hold_done: bool = false
var _pending_request_id: int = -1
var _request_id_counter: int = 0
var _waiting_native: bool = false

# 最近一次请求时 bot 面对的当前方块 / 暂存（hold）方块（用于决策日志输出，便于排查误旋转）
var _last_current_piece: String = "-"
var _last_hold_piece: String = "-"

# ---- worker 子进程管理 ----
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _started: bool = false
var _running: bool = false
var _thread: Thread = null
var _mutex: Mutex = Mutex.new()
var _queue: Array = []

## 是否正在等待原生 ColdClear 的异步决策（期间应暂停本地 bot 动作）
func is_waiting_decision() -> bool:
	return _waiting_native

func _ready():
	_native_available = start()
	if _native_available:
		move_ready.connect(_on_move_ready)
		print("ColdClearBridge: 已启动原生ColdClear（dll + worker），将使用ColdClear决策")
	else:
		print("ColdClearBridge: 未检测到完整原生ColdClear，使用默认bot链")

func _exit_tree() -> void:
	stop()

## 当前是否应使用原生 ColdClear 决策（可用且未处于失败冷却）
func using_native_cc() -> bool:
	return _native_available and Time.get_ticks_msec() >= _native_cooldown_until

func is_native_available() -> bool:
	return _native_available

func get_native_cc_info() -> Dictionary:
	var native_dir: String = _resolve_native_dir()
	return {
		"enabled": _native_available,
		"dll": native_dir.path_join(DLL_FILENAME) if not native_dir.is_empty() else "",
		"worker": native_dir.path_join(WORKER_FILENAME) if not native_dir.is_empty() else "",
		"native_dir": native_dir,
		"cooling_down": Time.get_ticks_msec() < _native_cooldown_until,
	}

## 是否还有待执行的路径动作（含仅 Hold 的计划）
## 注意：若计划只要求 Hold（movements 为空），也必须视为“有计划”，否则
## 调用方会因 has_plan()==false 而直接 hard_drop，导致跳过 Hold、误硬降。
func has_plan() -> bool:
	if _plan.is_empty():
		return false
	# 有待执行的 Hold 动作时也算有计划
	if not _plan_hold_done and _plan.get("hold", false):
		return true
	return _plan_index < (_plan.get("movements", []) as Array).size()

## 计划是否已（被）消费完毕（存在计划但全部动作已取出）
func plan_consumed() -> bool:
	return not _plan.is_empty() and _plan_index >= (_plan.get("movements", []) as Array).size()

## 当前是否完全没有计划（本块从未获得过有效决策结果）。
## 用于垃圾行抬升时判断能否安全重新请求：垃圾上涨是整版（含当前方块）同步上移，
## 当前方块相对堆叠的落点/形状不变，因此只要本块已有（或曾有）计划就应继续执行旧计划，
## 而不是重规划——否则新计划按“方块在 spawn 位”生成，而方块实际已移动，会造成 missdrop。
func is_plan_empty() -> bool:
	return _plan.is_empty()

func remaining_movements() -> int:
	if _plan.is_empty():
		return 0
	return (_plan.get("movements", []) as Array).size() - _plan_index

func plan_wants_hold() -> bool:
	return bool(_plan.get("hold", false))

## 清空当前计划（让调用方回退默认 bot）。例如 Hold 动作实际执行失败时使用。
func clear_plan() -> void:
	_plan = {}
	_plan_index = 0
	_plan_hold_done = false

## 请求一次新的 ColdClear 决策计划（在每块开始时调用）。
## 结果存入 _plan；失败则清空计划（调用方回退默认 bot）。
func request_plan(game_controller) -> void:
	_plan = {}
	_plan_index = 0
	_plan_hold_done = false
	if not using_native_cc():
		return
	if game_controller == null:
		return

	var board_rows: Array = _build_board_rows(game_controller)
	if board_rows.is_empty():
		return

	var hold: String = game_controller.hold_piece_type
	# 记录当前方块与暂存方块，供决策日志输出（排查 bot 误旋转时对照所用方块）
	_last_current_piece = str(game_controller.current_piece_type)
	_last_hold_piece = str(hold)
	var queue: Array = [game_controller.current_piece_type]
	if game_controller.bag_controller != null:
		# 提供给 bot 的 Next 预览深度：当前块 + 14 个后续块。
		# worker 的 queue[32] 上限 32，14+1=15 远在范围内。
		for q in game_controller.bag_controller.peek_next_pieces(14):
			queue.append(q)

	var use_hold: bool = not game_controller.no_hold and game_controller.can_hold
	var b2b: bool = false
	var combo: int = 0
	var incoming: int = 0
	if game_controller.clear_line_controller != null:
		b2b = game_controller.clear_line_controller.is_btb_active
		combo = game_controller.clear_line_controller.combo_count
	if game_controller.garbage_line_controller != null:
		incoming = game_controller.garbage_line_controller.get_enter_queue_size()
	var bag_remain: int = _compute_bag_remain(queue)

	var batch: String = _build_command_batch(
		board_rows, hold, queue, use_hold, b2b, combo, incoming, bag_remain, game_controller)
	if batch.is_empty():
		return

	if _pending_request_id != -1:
		return
	_request_id_counter += 1
	_pending_request_id = _request_id_counter
	_waiting_native = true
	if not _request_move(batch, _pending_request_id):
		_pending_request_id = -1
		_waiting_native = false
		_native_cooldown_until = Time.get_ticks_msec() + FAIL_COOLDOWN_MS
		push_warning("ColdClearBridge: 原生决策入队失败，本块起回退默认bot（冷却10s）")

## 取出下一个待执行动作；计划已结束时返回 hard_drop（锁定当前块）。
## 若计划要求 Hold，第一个动作先返回 hold。
func next_plan_action() -> BotAction:
	if _plan.is_empty():
		return BotAction.new("hard_drop", ["hard_drop"], "hard_drop")
	if not _plan_hold_done and _plan.get("hold", false):
		_plan_hold_done = true
		return BotAction.new("hold", ["hold"], "hold")
	var mv: Array = _plan.get("movements", [])
	if _plan_index >= mv.size():
		return BotAction.new("hard_drop", ["hard_drop"], "hard_drop")
	var m: String = mv[_plan_index]
	_plan_index += 1
	return BotAction.new(m, [m], m)

## 构建发送给 ColdClear 的棋盘行（String 数组，行0=顶部，'1'=有块）。
## 发送窗口 = 可见区 + 上方 EXTRA_TOP_ROWS 行；先擦除活动方块。
func _build_board_rows(game_controller) -> Array:
	var drawer = game_controller.board_drawer
	if drawer == null or drawer.board_data.is_empty():
		return []
	var board_data: Array = drawer.board_data
	var grid_w: int = drawer.grid_width
	var visible_h: int = drawer.grid_height
	var above: int = drawer.above_visible_rows
	var start_y: int = max(0, above - EXTRA_TOP_ROWS)
	var end_y: int = above + visible_h
	var h: int = end_y - start_y

	var rows: Array = []
	for i in range(h):
		var row: Array = board_data[start_y + i]
		var s := ""
		for c in row:
			s += "1" if _cell_occupied(c) else "0"
		rows.append(s)

	var shape: Array = game_controller.current_piece
	var pos: Vector2i = game_controller.current_position
	for y in range(shape.size()):
		for x in range(shape[y].size()):
			if shape[y][x] != 1:
				continue
			var by: int = pos.y + y
			var bx: int = pos.x + x
			if by < start_y or by >= end_y:
				continue
			if bx < 0 or bx >= grid_w:
				continue
			var row_s: String = rows[by - start_y]
			rows[by - start_y] = row_s.substr(0, bx) + "0" + row_s.substr(bx + 1)
	return rows

func _cell_occupied(cell: Variant) -> bool:
	if cell == null:
		return false
	if typeof(cell) == TYPE_BOOL:
		return cell
	return true

## 计算 bag 中剩余方块位掩码（bit0=I, bit1=O, bit2=T, bit3=L, bit4=J, bit5=S, bit6=Z）
func _compute_bag_remain(queue: Array) -> int:
	var seen := {}
	for q in queue:
		seen[str(q)] = true
	var mask := 0x7F
	for i in range(PIECE_ORDER.size()):
		if seen.has(PIECE_ORDER[i]):
			mask &= ~(1 << i)
	return mask

## 构建“实际游戏规则/伤害模型”的命令行（S 命令）。
## 协议：S <enabled> <base0..4> <tspin0..3> <allspin0..3> <b2b> <pc> <sendMult> <defendMult> <evalMult>
##       <attack_efficiency_weight>
##       <b2b_clear> <height> <clear4> <allspin_enabled> <allspin_repeat_penalty>
##       <clear1> <clear2> <clear3> <tspin1> <tspin2> <tspin3> <mini_tspin1> <mini_tspin2>
##       <allspin1> <allspin2> <allspin3> <allspin3plus>
##       <perfect_clear> <combo_garbage> <wasted_t> <move_time>
##       <kickLen> <kick dx,dy pairs: 2*kickLen> <combo0..31> <combo_formula>
## allspin_enabled 为 int：0=allmini（非T卡住→minispin，效果同T mini），1=allspin（非T卡住→fullspin，效果同T-Spin），其余保留。
## 伤害表/倍率/规则开关等来自 buff（clear_line_controller.get_damage_tables、
## tower_controller.get_send_mult_attack、garbage_line_controller.get_mult_defend）。
## 各类型消行/旋转/惩罚的决策权重以本桥导出变量为主（inspector 界面调整）。
## 仅当 buff 显式传参（get_damage_tables 只返回 buff 显式设置的键）时才覆盖本桥默认权重。
## 踢墙表来自 tetris_controller.kick_table["all"]（游戏 asc 踢墙表），空/缺失时 worker 用标准 SRS。
func _build_game_rules_command(game_controller) -> String:
	var enabled := 1
	# 各类型消行/旋转/惩罚的决策权重：来自本桥导出变量（inspector 调整）
	# 用 w_ 前缀避免与类成员（导出变量）同名产生的 shadowing 警告
	var w_eval_mult := self.eval_mult
	var w_attack_efficiency_weight := self.attack_efficiency_weight
	var w_b2b_clear := self.b2b_clear
	var w_height := self.height
	var w_clear4 := self.clear4
	var w_clear1 := self.clear1
	var w_clear2 := self.clear2
	var w_clear3 := self.clear3
	var w_tspin1 := self.tspin1
	var w_tspin2 := self.tspin2
	var w_tspin3 := self.tspin3
	var w_mini_tspin1 := self.mini_tspin1
	var w_mini_tspin2 := self.mini_tspin2
	var w_allspin1 := self.allspin1
	var w_allspin2 := self.allspin2
	var w_allspin3 := self.allspin3
	var w_allspin3plus := self.allspin3plus
	var w_perfect_clear := self.perfect_clear
	var w_combo_garbage := self.combo_garbage
	var w_wasted_t := self.wasted_t
	var w_move_time := self.move_time
	var w_allspin_repeat_penalty := self.allspin_repeat_penalty
	# 伤害表/倍率/规则开关等由 buff 提供（get_damage_tables / get_send_mult_attack / get_mult_defend）
	var base_damage: Array = [0, 0, 1, 2, 4]
	var tspin_damage: Array = [0, 2, 4, 6]
	var allspin_damage: Array = [0, 4, 6, 8]
	var combo_damage: Array = [0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
	var combo_formula := 1  # 连击计算方式：0=旧连击表，1=新公式（默认）
	var b2b_bonus := 1
	var pc_damage := 10
	var send_mult_attack := 1.0
	var mult_defend := 1.0
	var allspin_enabled_i := 0
	var kick_table: Array = []

	# 伤害表/倍率/规则开关来自 buff（clear_line_controller.get_damage_tables 等）。
	# 各类型消行/旋转/惩罚权重以本桥导出变量为主；仅当 buff 显式传参了对应键
	# （get_damage_tables 只返回 buff 显式设置的键）时才覆盖本桥默认权重。
	var clc = game_controller.get("clear_line_controller") if game_controller != null else null
	if clc != null and clc.has_method("get_damage_tables"):
		var d: Dictionary = clc.get_damage_tables()
		enabled = 1 if d.get("enabled", true) else 0
		if d.has("base_damage"): base_damage = d.base_damage
		if d.has("tspin_damage"): tspin_damage = d.tspin_damage
		if d.has("allspin_damage"): allspin_damage = d.allspin_damage
		if d.has("combo_damage"): combo_damage = d.combo_damage
		if d.has("combo_formula"): combo_formula = int(d.combo_formula)
		if d.has("b2b_bonus"): b2b_bonus = int(d.b2b_bonus)
		if d.has("pc_damage"): pc_damage = int(d.pc_damage)
		if d.has("allspin_enabled"): allspin_enabled_i = int(d.allspin_enabled)  # 0=allmini, 1=allspin
		# buff 可覆盖各类型消行/旋转/惩罚权重（默认以本桥导出变量为准）
		if d.has("eval_mult"): w_eval_mult = int(d.eval_mult)
		if d.has("attack_efficiency_weight"): w_attack_efficiency_weight = int(d.attack_efficiency_weight)
		if d.has("b2b_clear"): w_b2b_clear = int(d.b2b_clear)
		if d.has("height"): w_height = int(d.height)
		if d.has("clear4"): w_clear4 = int(d.clear4)
		if d.has("clear1"): w_clear1 = int(d.clear1)
		if d.has("clear2"): w_clear2 = int(d.clear2)
		if d.has("clear3"): w_clear3 = int(d.clear3)
		if d.has("tspin1"): w_tspin1 = int(d.tspin1)
		if d.has("tspin2"): w_tspin2 = int(d.tspin2)
		if d.has("tspin3"): w_tspin3 = int(d.tspin3)
		if d.has("mini_tspin1"): w_mini_tspin1 = int(d.mini_tspin1)
		if d.has("mini_tspin2"): w_mini_tspin2 = int(d.mini_tspin2)
		if d.has("allspin1"): w_allspin1 = int(d.allspin1)
		if d.has("allspin2"): w_allspin2 = int(d.allspin2)
		if d.has("allspin3"): w_allspin3 = int(d.allspin3)
		if d.has("allspin3plus"): w_allspin3plus = int(d.allspin3plus)
		if d.has("perfect_clear"): w_perfect_clear = int(d.perfect_clear)
		if d.has("combo_garbage"): w_combo_garbage = int(d.combo_garbage)
		if d.has("wasted_t"): w_wasted_t = int(d.wasted_t)
		if d.has("move_time"): w_move_time = int(d.move_time)
		if d.has("allspin_repeat_penalty"): w_allspin_repeat_penalty = int(d.allspin_repeat_penalty)
	# 攻击/防御倍率来自 buff（tower_controller / garbage_line_controller）
	var tower = game_controller.get("tower_controller") if game_controller != null else null
	if tower != null and tower.has_method("get_send_mult_attack"):
		send_mult_attack = float(tower.get_send_mult_attack())
	var garbage = game_controller.get("garbage_line_controller") if game_controller != null else null
	if garbage != null and garbage.has_method("get_mult_defend"):
		mult_defend = float(garbage.get_mult_defend())

	# 读取游戏 asc 踢墙表（tetris_controller.kick_table["all"]，元素为 [dx,dy]）
	if game_controller != null and game_controller.has_method("get_kick_table"):
		var kt: Array = game_controller.get_kick_table()
		if kt is Array and kt.size() > 0:
			kick_table = kt

	var parts: Array = ["S", str(enabled)]
	for v in base_damage: parts.append(str(int(v)))
	for v in tspin_damage: parts.append(str(int(v)))
	for v in allspin_damage: parts.append(str(int(v)))
	parts.append(str(int(b2b_bonus)))
	parts.append(str(int(pc_damage)))
	# 倍率以千分比发送（1000 = 1.0），与 Rust/C 侧一致
	parts.append(str(int(round(float(send_mult_attack) * 1000.0))))
	parts.append(str(int(round(float(mult_defend) * 1000.0))))
	parts.append(str(int(w_eval_mult)))
	# bot 评估权重：攻击效率（导出变量，inspector 调整）
	parts.append(str(int(w_attack_efficiency_weight)))
	# bot 评估权重：维持BTB / 放块后堆叠高度 / 四消（导出变量，inspector 调整）
	parts.append(str(int(w_b2b_clear)))
	parts.append(str(int(w_height)))
	parts.append(str(int(w_clear4)))
	parts.append(str(int(allspin_enabled_i)))
	# allspin_1 重复惩罚扣分（bot 评估权重，负值=降低选取值，导出变量）
	parts.append(str(int(w_allspin_repeat_penalty)))
	# 各类型消行/旋转的决策权重（导出变量，inspector 调整）
	parts.append(str(int(w_clear1)))
	parts.append(str(int(w_clear2)))
	parts.append(str(int(w_clear3)))
	parts.append(str(int(w_tspin1)))
	parts.append(str(int(w_tspin2)))
	parts.append(str(int(w_tspin3)))
	parts.append(str(int(w_mini_tspin1)))
	parts.append(str(int(w_mini_tspin2)))
	# 非T旋转（allspin）权重：消1/2/3/3+
	parts.append(str(int(w_allspin1)))
	parts.append(str(int(w_allspin2)))
	parts.append(str(int(w_allspin3)))
	parts.append(str(int(w_allspin3plus)))
	parts.append(str(int(w_perfect_clear)))
	parts.append(str(int(w_combo_garbage)))
	parts.append(str(int(w_wasted_t)))
	parts.append(str(int(w_move_time)))
	# 踢墙表：先发对数，再发 [dx,dy,dx,dy,...]
	# 注意：游戏 y 向下为正、ColdClear y 向上为正，发送时把 dy 取反，
	# 使 CC 端踢墙位移方向与游戏完全一致；否则落地后旋转等“多候选可行”
	# 的板面上，两端穷举踢墙的候选优先级相反，偶发导致 CC 预想落点与
	# 游戏实际落块错位（尤其 I 方块瞬降后旋转）。
	parts.append(str(int(kick_table.size())))
	for kick in kick_table:
		if kick is Array and kick.size() >= 2:
			parts.append(str(int(kick[0])))
			parts.append(str(int(-kick[1])))
	for v in combo_damage: parts.append(str(int(v)))
	# 连击计算方式：0=旧连击表，1=新公式（默认）
	parts.append(str(int(combo_formula)))
	return " ".join(parts) + "\n"

## 构建发送给 worker 的完整命令批（S/W/R/H/GO 行）。
## worker 以 W 的 height 决定 spawn_y=height-3、lockout_y=height-2（适应塔式棋盘窗口）。
## S 行在每次请求前发送，确保 bot 使用当前关卡的“实际游戏规则/伤害模型”。
func _build_command_batch(
		board_rows: Array, hold: String, queue: Array,
		use_hold: bool, b2b: bool, combo: int, incoming: int, bag_remain: int,
		game_controller = null) -> String:
	var h: int = board_rows.size()
	if h <= 0:
		return ""
	var lines: Array = []
	var s_line: String = _build_game_rules_command(game_controller)
	if not s_line.is_empty():
		lines.append(s_line.strip_edges())
	lines.append("W 10 %d" % h)
	for i in range(h):
		lines.append("R %d %s" % [i, str(board_rows[i])])
	# 实心垃圾行掩码：G <mask>，位 i = 窗口行 i 是实心行（0=窗口顶部，与 R 命令一致）。
	# worker 会转成 CC 行号掩码并传给 Board，使 CC 知道这些行即使填满也不消行。
	# 否则 CC 会把全满的实心行当作可消行，预测消行与实际不符 → 对账失败/报错。
	var br_drawer = game_controller.board_drawer if game_controller != null else null
	var br_above: int = br_drawer.above_visible_rows if br_drawer != null else 0
	var br_start_y: int = max(0, br_above - EXTRA_TOP_ROWS)
	var br_glc = game_controller.get("garbage_line_controller") if game_controller != null else null
	var solid_mask: int = 0
	if br_glc != null and br_glc.has_method("is_solid_garbage_row"):
		for i in range(h):
			if br_glc.is_solid_garbage_row(br_start_y + i):
				solid_mask |= 1 << i
	lines.append("G %d" % solid_mask)
	var hold_str: String = "-"
	if hold != null and str(hold) != "" and str(hold) != "-":
		hold_str = str(hold)
	lines.append("H %s" % hold_str)
	var qs: Array = []
	for q in queue:
		var qs_str: String = str(q)
		if qs_str != "" and qs_str != "-":
			qs.append(qs_str)
	# 并行搜索线程数优先级：buff 显式设置(bot_threads) > 本桥导出 cc_threads > 自动按 CPU 核数-2
	var buff_threads: int = 0
	var clc = game_controller.get("clear_line_controller") if game_controller != null else null
	if clc != null and clc.has_method("get_bot_threads"):
		buff_threads = int(clc.get_bot_threads())
	var threads_used: int = buff_threads
	if threads_used <= 0:
		threads_used = cc_threads
	if threads_used <= 0:
		threads_used = clampi(OS.get_processor_count() - 2, 1, 8)
	var go_line: String = "GO %d %d %d %d %d %d %d %d %d" % [
		1 if use_hold else 0, MAX_NODES, MIN_NODES, threads_used,
		1 if b2b else 0, combo, incoming, bag_remain, qs.size()]
	if not qs.is_empty():
		go_line += " " + " ".join(qs)
	lines.append(go_line)
	return "\n".join(lines) + "\n"

## worker 回复 OK <hold> <n> <mv...>，转为 _plan。
func _on_move_ready(request_id: int, reply: String) -> void:
	if request_id != _pending_request_id:
		return
	_pending_request_id = -1
	_waiting_native = false
	if reply == "DEAD":
		_native_cooldown_until = Time.get_ticks_msec() + FAIL_COOLDOWN_MS
		_plan = {}
		return
	if reply.begins_with("ERR"):
		_native_cooldown_until = Time.get_ticks_msec() + FAIL_COOLDOWN_MS
		_plan = {}
		push_warning("ColdClearBridge: 原生决策失败（", reply, "），本块起回退默认bot（冷却10s）")
		return
	if reply.begins_with("OK"):
		var parts: PackedStringArray = reply.split(" ")
		var hold: bool = parts.size() > 1 and parts[1] == "1"
		var n: int = int(parts[2]) if parts.size() > 2 and parts[2].is_valid_int() else 0
		# 解析 CC 期望落点 cells 坐标（worker 以 " E <ex0> <ey0> ... <ex3> <ey3>" 附带，位于 movements 之前）
		var expected_cells: Array = []
		var mv_start: int = 3
		if parts.size() > 3 and parts[3] == "E":
			for e in range(4):
				if 4 + e * 2 + 1 < parts.size():
					expected_cells.append([int(parts[4 + e * 2]), int(parts[5 + e * 2])])
			mv_start = 12
		var movements: Array = []
		for i in range(n):
			if mv_start + i < parts.size():
				movements.append(_move_to_action(parts[mv_start + i]))
		_plan = {"ok": true, "hold": hold, "movements": movements}
		_plan_index = 0
		_plan_hold_done = false
		# 输出当前方块与暂存方块（bot 当前持有的方块），便于排查误旋转
		var held_desc: String = _last_hold_piece
		if held_desc.is_empty() or held_desc == "-":
			held_desc = "无"
		print(
			"ColdClear决策 OK:",
			" | 当前方块=", _last_current_piece,
			" | 暂存(bot持有)=", held_desc,
			" | hold=", hold,
			" | 期望落点(cells)=", expected_cells,
			" | 路径(", movements.size(), "步)=", movements,
			" | 剩余待执行=", remaining_movements()
		)
		return
	# TIMEOUT / 未知回复
	_native_cooldown_until = Time.get_ticks_msec() + FAIL_COOLDOWN_MS
	_plan = {}
	push_warning("ColdClearBridge: 原生决策超时/未知（", reply, "），本块起回退默认bot（冷却10s）")

## 把 worker 的移动码（L/R/C/K/Z/D）映射为游戏动作名
func _move_to_action(code: String) -> String:
	match code:
		"L":
			return "left"
		"R":
			return "right"
		"C":
			return "rotate_right"
		"K":
			return "rotate_left"
		"Z":
			return "rotate_180"
		"D":
			return "soft_drop"
	return "hard_drop"

# ========== worker 子进程管理（自包含，原 coldclear_native_stub 逻辑） ==========

## 定位 native 目录（worker/dll 所在目录）。
## 导出运行：优先使用 exe 同目录下的 native/ 松散文件（由导出脚本复制到 exe 旁）。
## 编辑器/开发：res:// 直接映射项目目录，回退到项目内的 native/。
## 返回真实磁盘路径；找不到返回空串。
func _resolve_native_dir() -> String:
	# 1) 导出运行：exe 同目录下应有 native/ 松散文件
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var loose: String = exe_dir.path_join(NATIVE_EXE_SUBDIR)
	if FileAccess.file_exists(loose.path_join(WORKER_FILENAME)):
		return loose
	# 2) 编辑器/开发模式：res:// 映射项目目录
	var res_dir: String = ProjectSettings.globalize_path(NATIVE_RES_DIR)
	if FileAccess.file_exists(res_dir.path_join(WORKER_FILENAME)):
		return res_dir
	return ""

## 启动 worker 子进程（幂等）。失败时返回 false。
func start() -> bool:
	if _started:
		return true
	var native_dir: String = _resolve_native_dir()
	if native_dir.is_empty():
		push_error("coldclear_worker.exe 不存在（未找到 native 目录，请确认已把 native 文件夹放到 exe 旁）")
		return false
	var exe: String = native_dir.path_join(WORKER_FILENAME)
	if not FileAccess.file_exists(exe):
		push_error("coldclear_worker.exe 不存在: " + exe)
		return false
	var res: Dictionary = OS.execute_with_pipe(exe, [], false)
	if not res.has("stdio"):
		push_error("无法启动 coldclear_worker.exe")
		return false
	_stdio = res["stdio"]
	if res.has("stderr"):
		_stderr = res["stderr"]
	_started = true
	_running = true
	_thread = Thread.new()
	_thread.start(_loop)
	return true

## 停止 worker：发送 QUIT 并等待线程退出
func stop() -> void:
	if not _started:
		return
	_running = false
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	if _stdio:
		_stdio.store_string("QUIT\n")
		_stdio.flush()
		_stdio.close()
	_stdio = null
	_started = false

## 主线程调用：入队一个 GO 请求。
## 传入完整命令批（含 W/H/R/GO），后台线程执行后回传结果。
## request_id 由调用方决定（用于匹配）。返回是否成功入队。
func _request_move(command_batch: String, request_id: int) -> bool:
	if not _started:
		if not start():
			return false
	_mutex.lock()
	_queue.append({"id": request_id, "cmd": command_batch})
	_mutex.unlock()
	return true

## 后台线程循环：从队列取请求、写入 worker、读取回复、回传主线程
func _loop() -> void:
	while _running:
		_mutex.lock()
		var req: Variant = _queue.pop_front() if not _queue.is_empty() else null
		_mutex.unlock()
		if req == null:
			OS.delay_msec(5)
			continue
		var cmd: String = req["cmd"]
		var rid: int = req["id"]
		if _stdio == null:
			call_deferred("_emit_move_ready", rid, "ERR no_worker")
			continue
		_stdio.store_string(cmd)
		_stdio.flush()
		var reply: String = _read_line()
		call_deferred("_emit_move_ready", rid, reply)

func _emit_move_ready(rid: int, reply: String) -> void:
	move_ready.emit(rid, reply)

## 阻塞读取一行回复（带超时）
func _read_line() -> String:
	var deadline: int = Time.get_ticks_msec() + READ_TIMEOUT_MS
	while _running and Time.get_ticks_msec() < deadline:
		if _stdio != null and _stdio.get_length() > 0:
			return _stdio.get_line().strip_edges()
		OS.delay_msec(10)
	return "TIMEOUT"

# ========== 原生 ColdClear 决策入口 ==========
