extends Node
class_name ZzzBridge

## zzztoj 桥：启动 zzztoj_worker.exe 子进程（OS.execute_with_pipe 管道），
## 用行协议把局面喂给 zzztoj，并把返回的操作串转成本游戏的 BotAction 计划。
## 取代原 coldclear_bridge.gd（ColdClear）。
##
## 协议（详见 zzztoj/src/zzztoj_worker.cpp）：
##   PING -> OK
##   CFG <think> <gcap> <mult> <lockout> <hold> <a180> <amini> <aspin> <tspin> <immobileT> -> OK
##   REQ <40行位掩码(底行在前)> <active> <hold|-> <canHoldNow> <next串> <b2b> <combo> <预告垃圾> <格数> <x y ...> -> OK <path>
## path 字符：l/r/d 一格、L/R 到头、D 落到底、z 逆时针、c 顺时针、开头 v=先暂存、末尾 V=落地

const WORKER_FILENAME := "zzztoj_worker.exe"
## 开发/编辑器模式：res:// 直接映射项目磁盘目录（worker 由 zzztoj/build_worker.ps1 输出到此）
const WORKER_RES_DIR := "res://zzztoj/worker"
## 导出模式：exe 同目录下的子目录（由导出脚本把 worker 复制过去）
const WORKER_EXE_SUBDIR := "zzztoj"

## 本游戏可玩区域：10 宽 × 90 行（y 向下），底行 y = 89
const GAME_WIDTH := 10
const GAME_BOTTOM_Y := 89
## 送给 AI 的 next 数量上限
const NEXT_MAX := 14
## 每步思考预算（传给 worker 的 think_limit，越大越强越慢）
@export var think_budget: int = 100
## 是否允许 worker 使用 hold（NoHold 模式会覆盖为 0）
@export var allow_hold: bool = true
## 是否允许 180 度旋转
@export var allow_180: bool = true
## Allspin 重复性惩罚扣分（>0 = 生效；本游戏 Allspin_1 下「与上一手同类型 spin + 同行数」会立刻涨一行垃圾）
@export var repeat_penalty: float = 500.0

var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _pid: int = -1
var _started: bool = false
var _running: bool = false
var _thread: Thread = null
var _mutex := Mutex.new()
var _sem := Semaphore.new()

var _queue: Array = []          # 待发送命令队列 [[cmd, kind], ...]（kind: PING/CFG/PARAM/REQ）
var _reply: String = ""
var _reply_ready: bool = false
var _waiting: bool = false
var _last_error: String = ""

var _plan: Array = []          # Array[BotAction]
var _plan_index: int = 0
var _plan_wants_hold: bool = false
var _request_id: int = 0
var _cfg_sent: String = ""


func _ready() -> void:
	start()


func _exit_tree() -> void:
	stop()


## 启动 worker 子进程（幂等）
func start() -> bool:
	if _started:
		return true
	var exe := _resolve_worker_path()
	if exe.is_empty():
		_last_error = "%s 不存在（编辑器：res://zzztoj/；导出：exe 同目录 zzztoj/）" % WORKER_FILENAME
		push_error("[ZzzBridge] " + _last_error)
		return false
	var res: Dictionary = OS.execute_with_pipe(exe, [], false)
	if res.is_empty() or not res.has("stdio"):
		_last_error = "无法启动 " + WORKER_FILENAME
		push_error("[ZzzBridge] " + _last_error)
		return false
	_stdio = res.get("stdio")
	_stderr = res.get("stderr")
	_pid = int(res.get("pid", -1))
	_started = true
	_running = true
	_thread = Thread.new()
	_thread.start(_loop)
	# 握手（异步；回复由子线程消费，不阻塞主线程）
	_send_async("PING", "PING")
	return true


## 停止 worker
func stop() -> void:
	_running = false
	if _started and _stdio != null:
		_stdio.store_string("QUIT\n")
		_stdio.flush()
	_sem.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_stdio = null
	_stderr = null
	_started = false
	_pid = -1


## 定位 worker 可执行文件
func _resolve_worker_path() -> String:
	# 1) 导出运行：exe 同目录下 zzztoj/
	var exe_dir := OS.get_executable_path().get_base_dir()
	var loose := exe_dir.path_join(WORKER_EXE_SUBDIR).path_join(WORKER_FILENAME)
	if FileAccess.file_exists(loose):
		return loose
	# 2) 编辑器/开发：res:// 映射项目目录
	var res_dir: String = ProjectSettings.globalize_path(WORKER_RES_DIR)
	var dev := res_dir.path_join(WORKER_FILENAME)
	if FileAccess.file_exists(dev):
		return dev
	return ""


func using_native_cc() -> bool:
	return _started


func is_native_available() -> bool:
	return not _resolve_worker_path().is_empty()


func get_native_cc_info() -> Dictionary:
	return {
		"engine": "zzztoj",
		"started": _started,
		"pid": _pid,
		"error": _last_error,
		"plan_len": _plan.size(),
		"plan_index": _plan_index,
	}


# ========== 计划状态（供 TetrisController 查询） ==========

func has_plan() -> bool:
	return _plan_index < _plan.size()


func is_plan_empty() -> bool:
	return _plan.is_empty()


func plan_consumed() -> bool:
	return _plan_index >= _plan.size()


func remaining_movements() -> int:
	return max(0, _plan.size() - _plan_index)


func plan_wants_hold() -> bool:
	return _plan_wants_hold


func clear_plan() -> void:
	_plan = []
	_plan_index = 0
	_plan_wants_hold = false


func is_waiting_decision() -> bool:
	return _waiting


func reset_for_stall() -> void:
	_mutex.lock()
	_queue.clear()
	_reply = ""
	_reply_ready = false
	_waiting = false
	_mutex.unlock()
	clear_plan()


## 取出计划中的下一个动作
func next_plan_action() -> BotAction:
	if _plan_index >= _plan.size():
		return BotAction.new("hard_drop", ["hard_drop"], "hard_drop")
	var a: BotAction = _plan[_plan_index]
	_plan_index += 1
	return a


# ========== buff 参数覆盖（ExtraBotChange） ==========

## buff 覆盖的 zzz AI 参数：{Param 字段名: 数值}（repeat_penalty 单独走 REQ 尾部）
var _param_overrides: Dictionary = {}
var _sent_params: Dictionary = {}


## 由关卡/ buff 下发参数覆盖（键名 = ai_zzz::IO::Param 字段名）
func set_param_overrides(d: Dictionary) -> void:
	_param_overrides = d.duplicate()
	_sent_params.clear()   # 重新下发
	_push_params()


## 下发尚未发送过的参数覆盖
func _push_params() -> void:
	if not _started:
		return
	for k in _param_overrides.keys():
		var name := str(k)
		if name == "repeat_penalty":
			continue   # 该值随 REQ 尾部发送（游戏侧每块都会判断 allspin 是否开启）
		if _sent_params.has(name):
			continue
		_sent_params[name] = true
		_send_async("PARAM %s %s" % [name, str(_param_overrides[k])], "PARAM")


# ========== 请求决策 ==========

## 请求一次决策（每块一次；异步，结果在 _process 里落地）
func request_plan(game_controller) -> void:
	if not _started:
		return
	if game_controller == null:
		return
	var cfg := _build_cfg(game_controller)
	if cfg != _cfg_sent:
		_cfg_sent = cfg
		_send_async(cfg, "CFG")
		_sent_params.clear()   # CFG 会把参数重置为 worker 默认，需重新下发 buff 覆盖
	_push_params()
	var line := _build_request(game_controller)
	if line.is_empty():
		return
	_waiting = true
	_send_async(line, "REQ")


func _process(_delta: float) -> void:
	_mutex.lock()
	var ready := _reply_ready
	var reply := _reply
	if ready:
		_reply_ready = false
		_reply = ""
	_mutex.unlock()
	if not ready:
		return
	_waiting = false
	_parse_reply(reply)


# ========== 协议构造 ==========

## 规则/配置行：与本游戏 spin 规则对应
func _build_cfg(gc) -> String:
	var amini := 1
	var aspin := 0
	var tspin := 1
	var immobile_t := 1
	var cl = gc.clear_line_controller
	if cl != null:
		if cl.no_spin == 2:
			# NoSpin：不判任何 spin
			amini = 0
			aspin = 0
			tspin = 0
			immobile_t = 0
		elif cl.tetris_allspin == 1:
			# Allspin：非 T 卡住也算 full spin
			amini = 0
			aspin = 1
	# 本游戏规则是「四方向不可移动 → spin」，故 allow_immobile_t = 1
	var hold_flag := 1 if (allow_hold and not gc.no_hold) else 0
	var gcap := 8
	if gc.garbage_line_controller != null:
		gcap = int(gc.garbage_line_controller.garbage_cap)
	return "CFG %d %d %d %d %d %d %d %d %d %d" % [
		think_budget, gcap, 1, 0, hold_flag,
		1 if allow_180 else 0, amini, aspin, tspin, immobile_t,
	]


## 局面行：40 行位掩码（index 0 = 本游戏 y=89 的底行），排除当前活动方块自身
func _build_request(gc) -> String:
	var drawer = gc.board_drawer
	if drawer == null:
		return ""
	# 当前方块占用的格子（本游戏坐标），需要在板面里排除
	var self_cells := {}
	var shape: Array = gc.current_piece
	var pos: Vector2i = gc.current_position
	for y in range(shape.size()):
		for x in range(shape[y].size()):
			if shape[y][x] == 1:
				self_cells[Vector2i(pos.x + x, pos.y + y)] = true

	var masks: Array = []
	for h in range(40):
		var gy: int = GAME_BOTTOM_Y - h
		var mask: int = 0
		if gy >= 0:
			for x in range(GAME_WIDTH):
				if self_cells.has(Vector2i(x, gy)):
					continue
				if drawer.get_cell_color(x, gy) != null:
					mask |= 1 << x
		masks.append(str(mask))

	var active: String = gc.current_piece_type
	if active.is_empty():
		active = "I"
	var hold_type: String = gc.hold_piece_type if not gc.hold_piece_type.is_empty() else "-"
	var can_hold_now := 1 if gc.can_hold else 0
	var next_str := _build_next(gc)
	var b2b := 0
	var combo := 0
	var cl = gc.clear_line_controller
	if cl != null:
		b2b = int(cl.btb_count)
		combo = int(cl.combo_count)
	var upcome := 0
	if gc.garbage_line_controller != null and gc.garbage_line_controller.has_method("get_enter_queue_size"):
		upcome = int(gc.garbage_line_controller.get_enter_queue_size())

	var parts: Array = ["REQ"]
	parts.append_array(masks)
	parts.append(active)
	parts.append(hold_type)
	parts.append(str(can_hold_now))
	parts.append(next_str)
	parts.append(str(b2b))
	parts.append(str(combo))
	parts.append(str(upcome))
	parts.append(str(self_cells.size()))
	for cell in self_cells.keys():
		parts.append(str(cell.x))
		parts.append(str(cell.y))
	# 尾部三项：上一手 spin 类型 / 上一手消行数 / 重复性惩罚扣分（0 = 关闭）
	parts.append(str(_last_spin_type(cl)))
	parts.append(str(int(cl._last_clear_count) if cl != null else 0))
	# 重复性惩罚：buff 覆盖优先，其次 @export 默认；仅 allspin 开启时下发
	var rp: float = float(_param_overrides.get("repeat_penalty", repeat_penalty))
	parts.append(str(rp if (cl != null and cl.tetris_allspin == 1) else 0.0))
	return " ".join(parts)


## 游戏的消行类型字符串 → zzz 的 ASpinType 数值
## （None=0 / TSpin=1 / AllSpin=2 / TSpinMini=3 / ASpinMini=4）
func _last_spin_type(cl) -> int:
	if cl == null:
		return 0
	var t := str(cl._last_clear_type)
	if t.is_empty():
		return 0
	var is_mini := t.find("Mini") != -1
	if t.find("T-Spin") != -1:
		return 3 if is_mini else 1
	return 4 if is_mini else 2


## next 串：取 bag 队列前 NEXT_MAX 个方块类型字符
func _build_next(gc) -> String:
	var out := ""
	if gc.bag_controller == null:
		return "I"
	var q: Array = gc.bag_controller.piece_queue
	for i in range(min(NEXT_MAX, q.size())):
		var t := str(q[i])
		if t.length() > 0:
			out += t.substr(0, 1)
	return out if not out.is_empty() else "I"


# ========== 回复解析 ==========

func _parse_reply(reply: String) -> void:
	clear_plan()
	if reply.is_empty() or not reply.begins_with("OK"):
		return
	var path := reply.substr(2).strip_edges()
	if path.is_empty():
		return
	for i in range(path.length()):
		var c := path[i]
		match c:
			"v":
				_plan_wants_hold = true
				_plan.append(BotAction.new("hold", ["hold"], "hold"))
			"l":
				_plan.append(BotAction.new("left", ["left"], "left"))
			"r":
				_plan.append(BotAction.new("right", ["right"], "right"))
			"L":
				_plan.append(BotAction.new("left_wall", ["left_wall"], "left_wall"))
			"R":
				_plan.append(BotAction.new("right_wall", ["right_wall"], "right_wall"))
			"d":
				_plan.append(BotAction.new("down_one", ["down_one"], "down_one"))
			"D":
				_plan.append(BotAction.new("soft_drop", ["soft_drop"], "soft_drop"))
			"z":
				_plan.append(BotAction.new("rotate_left", ["rotate_left"], "rotate_left"))
			"c":
				_plan.append(BotAction.new("rotate_right", ["rotate_right"], "rotate_right"))
			"V":
				_plan.append(BotAction.new("hard_drop", ["hard_drop"], "hard_drop"))
			_:
				pass


# ========== 管道 I/O（子线程） ==========
# 注意：Godot 的管道 FileAccess.get_line() 不会阻塞——没数据时返回空串，
# 因此这里必须轮询等待整行，否则回复会错位（PING/CFG/PARAM 的回复被当成 REQ 的回复）。

func _loop() -> void:
	while _running:
		_sem.wait()
		if not _running:
			break
		var item: Array = []
		_mutex.lock()
		if not _queue.is_empty():
			item = _queue.pop_front()
		_mutex.unlock()
		if item.is_empty():
			continue
		var cmd := str(item[0])
		var kind := str(item[1]) if item.size() > 1 else "CMD"
		var reply := _transact(cmd)
		if kind == "REQ":
			_mutex.lock()
			_reply = reply
			_reply_ready = true
			_mutex.unlock()


## 写一条命令并轮询等待其回复（每 1ms 轮询，最多 5 秒）
func _transact(cmd: String) -> String:
	if _stdio == null:
		return ""
	_stdio.store_string(cmd + "\n")
	_stdio.flush()
	var waited := 0
	while waited < 5000 and _running:
		var line: String = _stdio.get_line()
		if line.is_empty():
			OS.delay_msec(1)
			waited += 1
			continue
		return line.strip_edges()
	return ""


func _send_async(cmd: String, kind: String = "CMD") -> void:
	_mutex.lock()
	_queue.append([cmd, kind])
	_mutex.unlock()
	_sem.post()
