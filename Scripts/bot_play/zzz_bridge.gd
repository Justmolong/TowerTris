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
## 送给 AI 的 next 数量上限（＝ bot 的搜索深度：当前块之后还能预判几个块）。
## 块序队列已扩到 35（tetris_bag_controller.QUEUE_MIN_SIZE），所以这里能安全提到 25；
## 实测：深度 14 与 25 的决策一致率仅 ~63%（以 35 为基准），提到 25 能拿到大部分深度收益，
## 内存代价约 +25MB（167MB → 192MB），耗时不变（think 是真实时间闸门）。
## ⚠ 唯一来源：控制器不要再写死 14，统一用 ZzzBridge.bot_next_max()。
const NEXT_MAX := 25
## 运行期覆盖搜索深度（0 = 用 NEXT_MAX）。给诊断/调参用：
## 实测把深度从 14 提到 25 会明显改变决策，但对胜率没有可证实的提升，
## 所以留一个可回退的旋钮，方便对比"深度 14 / 25"的实战表现。
var next_max_override: int = 0
## 每步思考预算（传给 worker 的 think_limit，越大越强越慢）
@export var think_budget: int = 100
## 逐 REQ 的思考预算（ms，0 = 沿用 think_budget）。
## 控制器写入（tetris_controller._bot_note_plan_request）：现行默认是**恒定 100ms**，
## 与 think_budget 一致；参数化的动态预算仍可用（把 bot_think_budget_ratio/max 调回去）。
## ⚠ 它不进 CFG、不进决策参数签名，只随 REQ 尾部下发，所以变化不会作废已有计划。
var think_budget_now: int = 0
## 是否允许 worker 使用 hold（NoHold 模式会覆盖为 0）
@export var allow_hold: bool = true
## 是否允许 180 度旋转
@export var allow_180: bool = true
## Allspin 重复性惩罚扣分（>0 = 生效；本游戏 Allspin_1 下「与上一手同类型 spin + 同行数」会立刻涨一行垃圾）
@export var repeat_penalty: float = 500.0
## 单条命令等待回复的上限（毫秒）：超时按「worker 无响应」处理并打日志
@export var reply_timeout_ms: int = 2000
## 打印每次 REQ 的收发内容（排查「已启动但无决策」时打开）
@export var log_protocol: bool = false
## 启动/常规信息日志（默认关闭，避免刷屏；由 tetris_controller.bot_debug_log 同步过来）
@export var verbose: bool = false

var _pool = null                 # BotWorkerPool（worker 进程池；1 个 worker 时行为等价于旧的单进程实现）
var _pool_script = null          # 池脚本（按路径加载，避免依赖 class_name 缓存）
var _waiting: bool = false       # 是否有在途 REQ（对外语义与旧实现完全一致）
var _last_error: String = ""
## 本轮请求的"代号"：每次 request_plan 递增，回包必须带同一代号才被采纳。
## ⚠ 这是多 worker 并行的安全前提 —— 迟到的旧回包会被丢弃，不会张冠李戴到新局面上。
var _generation: int = 0
## 在途作业代号 → job_id（用于把池的回包对回本轮）
var _inflight: Dictionary = {}
## 本轮已收到的候选回包 [{job_id, worker_id, tag, reply}]，凑齐 _inflight.size() 条后选优
var _candidate_replies: Array = []
## 本回合的兜底截止时刻（ms）：worker 中途崩掉时避免"等回包"永远卡住
var _round_deadline_ms: int = 0
## 本回合的"局面身份"（REQ 去掉尾部预算后的部分），用于识别重复请求
var _round_key: String = ""
## 被忽略的重复请求次数（诊断：这个值一直涨说明控制器在等决策期间反复请求）
var _dup_requests: int = 0
## 本回合提交时刻与上一回合实际耗时（诊断用）
var _round_submit_ms: int = 0
var last_round_ms: int = 0
## 本回合实际下发的预算（诊断用）
var _round_budget_ms: int = 0
var _round_base_budget_ms: int = 0
## 待下发的 buff 参数覆盖（PARAM 行），随下一条作业一起发给对应 worker
var _pending_params: Array = []

var _plan: Array = []          # Array[BotAction]
var _plan_index: int = 0
var _plan_wants_hold: bool = false
var _cfg_sent: String = ""
## worker 进程存活标记：进程退出后置 false，bot 退化为「每块硬降」，避免主循环被「等待决策」冻住
var _alive: bool = true
var _death_logged: bool = false
var _warn_budget: int = 10
## 最近一次下发的 REQ（出错时一起打印，便于复现问题局面）
var _last_req: String = ""
## 最近一次决策的目标落点（本游戏坐标）——用于和实际锁定位置对照
var _plan_target_valid: bool = false
var _plan_target_piece: String = ""
var _plan_target_x: int = 0
var _plan_target_y: int = 0
var _plan_target_rot: int = 0
## worker 意外退出后的自动重启（次数上限 + 延迟）由 BotWorkerPool 内部处理
## 并行 worker 进程数：1 = 单进程单候选（**默认**，与改造前行为一致，最稳）；
## >1 = 同时跑多套搜索配置再选优（实验性，见 parallel_beams 的说明）。
## ⚠ 实测结论（16 核机器）：多进程并行本身几乎零代价（1→16 进程单次耗时不变），
##   但**并行候选并没有换来更强的决策**（独立裁判打分与单候选无显著差异），
##   却引入了"回合必须等最慢那条候选"的抖动 → 手感变差。
##   所以默认关掉；想试就把 parallel_workers 调到 4（同时把 parallel_beams 配够 4 条）。
@export var parallel_workers: int = 1
## 并行候选用的 beam 宽度倍数：beam 越宽搜得越广（worker 的 PARAM beam_scale，100 = 原始）。
## ⚠ 候选数 = min(parallel_workers, parallel_beams.size())，且要求
##   **候选数 ≤ 存活 worker 数**；候选数多于 worker 数时，多出来的候选会和前面的候选
##   挤在同一个 worker 上串行执行，单轮墙钟直接翻倍（实测 115ms → 230ms）。
## 第 1 个候选应为 100（它是基准候选）。
@export var parallel_beams: Array[int] = [100]
## 并行候选的预算倍率：每个候选分到 think_budget_now * 本值。
## 取 1.0 表示 N 个候选同时跑，墙钟仍约等于单候选的预算（而不是 N 倍）。
@export var parallel_budget_scale: float = 1.0
## 选优时的保护阈值：候选得分必须比基准候选好这么多才被采纳。
## 取正值是为了防止搜索本身的随机性（同一局面两次得分略有不同）导致行为来回漂移。
@export var parallel_accept_margin: float = 1.0


func _ready() -> void:
	start()


func _exit_tree() -> void:
	stop()


## 启动 worker 进程池（幂等）。
## ⚠ 只同步启动**第 1 个** worker：每个 worker 都要 prepare 一次搜索上下文（约 0.4s），
##   4 个一起启动会给场景初始化带来约 1.5s 的卡顿。其余 worker 延迟到第一次
##   request_plan 时再补齐（那时主线程本来就要等决策，用户感知不到额外停顿）。
func start() -> bool:
	if _pool != null:
		return true
	if _pool_script == null:
		_pool_script = load("res://Scripts/bot_play/bot_worker_pool.gd")
	if _pool_script == null:
		_last_error = "无法加载 bot_worker_pool.gd"
		push_error("[ZzzBridge] " + _last_error)
		return false
	_pool = _pool_script.new(1)
	_pool.reply_timeout_ms = reply_timeout_ms
	_pool.log_protocol = log_protocol
	_pool.verbose = verbose
	var n: int = _pool.start()
	if n <= 0:
		_last_error = _pool.start_failed_reason()
		push_error("[ZzzBridge] " + _last_error
			+ "（编辑器请在项目根运行 zzztoj/build_worker.ps1 构建 worker；导出请在 exe 同目录放 zzztoj/zzztoj_worker.exe）")
		return false
	_alive = true
	_death_logged = false
	if verbose or log_protocol:
		print("[ZzzBridge] 已启动 ", n, " 个 zzztoj worker: ", _pool.resolve_worker_path())
	return true


## 把 worker 数补齐到 parallel_workers（延迟到第一次请求时调用）
func _ensure_pool_size() -> void:
	if _pool == null:
		return
	var want: int = clampi(parallel_workers, 1, 8)
	if int(_pool.worker_count) == want:
		return
	_pool.set_worker_count(want)
	# ⚠ 候选数多于存活 worker 数时，多出来的候选会和前面的候选挤在同一个 worker 上串行执行，
	#   单轮墙钟翻倍 —— 这是实机"一顿一顿"的一个直接原因，所以在这里显式告警。
	var alive: int = _pool.alive_count()
	var cand: int = mini(want, parallel_beams.size())
	if cand > alive:
		push_warning("[ZzzBridge] 候选数 %d 多于存活 worker 数 %d：多出的候选会串行执行，单轮耗时会翻倍。请减少 parallel_beams 或检查 worker 是否启动失败。" % [cand, alive])
	if verbose or log_protocol:
		print("[ZzzBridge] worker 池补齐到 ", _pool.worker_count, " 个（请求的 ", want,
			" 个，实际成功 ", alive, " 个）")


## 重设并行度（会重启整个池）。worker_count 需 >0。
func set_parallel_workers(n: int) -> void:
	var want: int = maxi(1, n)
	if _pool != null and int(_pool.worker_count) == want:
		return
	parallel_workers = want
	stop()
	start()


## 停止 worker 池
func stop() -> void:
	if _pool != null:
		_pool.stop()
		_pool = null
	_waiting = false
	_inflight.clear()


func using_native_cc() -> bool:
	return _pool != null and _pool.is_ready()


func is_native_available() -> bool:
	if _pool != null:
		return not _pool.resolve_worker_path().is_empty()
	var s = load("res://Scripts/bot_play/bot_worker_pool.gd")
	if s == null:
		return false
	return not s.new().resolve_worker_path().is_empty()


func get_native_cc_info() -> Dictionary:
	var info := {
		"engine": "zzztoj",
		"started": _pool != null,
		"error": _last_error,
		"plan_len": _plan.size(),
		"plan_index": _plan_index,
	}
	if _pool != null:
		info.merge(_pool.get_info(), true)
	return info


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


## 决策目标落点（本游戏坐标）：{piece, x, y, rot, valid}
func get_plan_target() -> Dictionary:
	return {
		"valid": _plan_target_valid,
		"piece": _plan_target_piece,
		"x": _plan_target_x,
		"y": _plan_target_y,
		"rot": _plan_target_rot,
	}


## bot 是否正在执行一份未走完的计划（控制器用它冻结重力/锁延）
func is_plan_active() -> bool:
	return has_plan()


## 计划里剩余的旋转动作方向序列（1=顺时针 / -1=逆时针 / 2=180°），**不消费**计划。
## 快速模拟的「直接放置」用它把当前形状按同一套旋转推到目标朝向 ——
## 与逐步执行旋转的结果一致（踢墙只影响位置，不影响形状本身）。
func plan_rotation_directions() -> Array:
	var out: Array = []
	for i in range(_plan_index, _plan.size()):
		var a: BotAction = _plan[i]
		if a == null:
			continue
		match String(a.move):
			"rotate_right":
				out.append(1)
			"rotate_left":
				out.append(-1)
			"rotate_180":
				out.append(2)
	return out


func reset_for_stall() -> void:
	# 本轮的迟到回包不能再被采纳 → 直接把代号作废
	_generation += 1
	_inflight.clear()
	_candidate_replies = []
	_waiting = false
	_round_key = ""   # 允许同一局面重新提交（否则 stall 重试会被去重挡住）
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


## 下发尚未发送过的参数覆盖（只记录"待下发"，真正发送随下一条作业一起走）
func _push_params() -> void:
	if _pool == null:
		return
	for k in _param_overrides.keys():
		var pname := str(k)
		if pname == "repeat_penalty":
			continue   # 该值随 REQ 尾部发送（游戏侧每块都会判断 allspin 是否开启）
		if _sent_params.has(pname):
			continue
		_sent_params[pname] = true
		_pending_params.append("PARAM %s %s" % [pname, str(_param_overrides[k])])


# ========== 请求决策 ==========

## 请求一次决策（每块一次；异步，结果在 _process 里落地）。
## 单 worker（parallel_workers == 1）时：与旧实现逐位等价，只是收发挪进了线程池。
## 多 worker 时：同一局面用多套搜索配置并行搜，主线程按版面打分选优。
func request_plan(game_controller) -> void:
	if _pool == null:
		return
	if game_controller == null:
		return
	_ensure_pool_size()   # 首次请求时把并行 worker 补齐（避免开局卡顿）
	var cfg := _build_cfg(game_controller)
	if cfg != _cfg_sent:
		_cfg_sent = cfg
		_sent_params.clear()   # CFG 会把参数重置为 worker 默认，需重新下发 buff 覆盖
		_pending_params.clear()
	_push_params()
	var line := _build_request(game_controller)
	if line.is_empty():
		return
	# ── 同一局面只允许一轮在途 ────────────────────────────────────────────────
	# ⚠ 这是「一顿一顿」的根因所在：控制器在**等待期间**还会多次调用 request_plan
	#   （新块、垃圾抬升、参数签名变化、stall 重试…）。旧实现是单 worker 单在途，
	#   多发几条也只是排在同一条管道后面；但多候选并行时若每次都"_inflight.clear() 再提交"，
	#   就会把在途的那一轮作废、又塞进 N 条新作业 → worker 队列里堆起好几轮的作业，
	#   每轮都要排在前面几轮后面 → 单块等待从 ~115ms 涨到 400~800ms（实测 803ms）。
	#   这里改成：局面没变就不重复提交，老老实实等这一轮回来。
	var round_key := _round_key_of(line)
	if _waiting and round_key == _round_key:
		_dup_requests += 1
		if log_protocol:
			print("[ZzzBridge] 同一局面已有在途决策，忽略重复请求（第 ", _dup_requests, " 次）")
		return
	_last_req = line
	if log_protocol:
		print("[ZzzBridge] REQ <- '", line, "'")
	_generation += 1
	_inflight.clear()
	_candidate_replies = []
	_waiting = true
	_round_key = round_key

	# 组装本轮候选：候选 i 对应一个 worker、一套 beam、一份预算
	var beams: Array = parallel_beams
	if beams.is_empty():
		beams = [100]
	# ⚠ 候选数按**池里实际可用的 worker 数**取，不能按 parallel_workers：
	#   池是延迟补齐的，若某个 worker 启动/重启失败，请求数多于 worker 数会让某些候选
	#   排在队尾迟迟不返回，而本回合要等"全部到齐"才结算（尽管有下面的兜底超时）。
	var n_cand: int = clampi(mini(_pool.alive_count(), beams.size()), 1, 8)
	var base_budget: int = think_budget_now if think_budget_now > 0 else think_budget
	_round_budget_ms = int(round(float(base_budget) * maxf(0.1, parallel_budget_scale)))
	_round_base_budget_ms = base_budget
	var jobs: Array = []
	for i in range(n_cand):
		var beam: int = maxi(1, int(beams[i]))
		var budget: int = _round_budget_ms
		var params: Array = []
		if beam != 100:
			params.append("PARAM beam_scale %d" % beam)
		params.append_array(_pending_params)
		var tag := "%d:%d:%d" % [_generation, i, beam]
		# ⚠ 候选 i 钉到 worker i：一轮里 N 条候选必须落在 N 个不同的 worker 上，
		#   否则会出现"2 条挤在同一个 worker 串行执行、还有 worker 空转"，
		#   单轮墙钟直接翻倍（实测 115ms → 230ms），在游戏里就是一顿一顿。
		var job = _pool.make_job(cfg, params, line, tag, i)
		jobs.append(job)
		_inflight[int(job["id"])] = tag
	_pending_params.clear()
	# 兜底：即使某个候选的 worker 中途崩了，本回合也不会无限等下去
	_round_deadline_ms = Time.get_ticks_msec() + reply_timeout_ms + 500
	_round_submit_ms = Time.get_ticks_msec()
	if log_protocol:
		print("[ZzzBridge] 并行候选 ", jobs.size(), " 条，beam=", beams.slice(0, n_cand))
	_pool.submit_all(jobs)


## 局面的"身份"：只看**当前方块本身**（类型 + 四格坐标 + 朝向提示），**刻意不看版面**。
##
## 为什么不比整个 REQ：
##   垃圾抬升会改版面（board_version 变），控制器据此会重新请求一次；但游戏侧自己的注释
##   说明「垃圾上涨是整版含当前方块一起上移，方块相对堆叠的落点不变」——也就是说
##   **同一方块在同一个坐标上，就是对同一个问题的重复提问**。若把它当新问题，
##   我们就会作废在途的那一轮、再提交一轮新作业，而作废的作业仍在各 worker 上跑，
##   把 worker 占满 → 新的一轮只能排队 → 单块等待从 ~115ms 变成 ~230ms。
##   实测就是"每 5 块出现一次 ~2 倍间隔（471~506ms）"的周期性一顿。
##
## 位置也必须是 key 的一部分：方块已经移动过之后再问，位置不同 → 允许重算。
func _round_key_of(req_line: String) -> String:
	# REQ 的 token 布局：REQ + 40 个掩码 + active + hold + canHold + next + b2b + combo
	#                    + upcome + 格数 + (x y)* + 尾部 10 项
	var tok := req_line.split(" ")
	if tok.size() < 49:
		return req_line
	var active := tok[41]
	var hold := tok[42]
	var n_cells := int(tok[48])
	if n_cells <= 0 or 49 + n_cells * 2 > tok.size():
		return req_line
	var parts: Array = [active, hold]
	for i in range(n_cells):
		parts.append(tok[49 + i * 2])
		parts.append(tok[50 + i * 2])
	return "|".join(parts)


func _process(_delta: float) -> void:
	if _pool == null:
		return
	_pool.tick_health(_delta)
	for e in _pool.drain_errors():
		if _warn_budget > 0:
			_warn_budget -= 1
			push_warning("[ZzzBridge] " + str(e))
	# 收集本轮回包，全部到齐后再选优（未到齐就继续等，另有兜底超时与控制器看门狗）
	for r in _pool.drain_replies():
		var jid := int(r.get("job_id", -1))
		if not _inflight.has(jid):
			continue   # 上一轮/已作废的迟到回包 → 丢弃（多 worker 并行的安全前提）
		_candidate_replies.append(r)
	if _candidate_replies.size() < _inflight.size():
		# 兜底：worker 中途崩掉时，本回合不能永远卡在"等回包"
		if not _inflight.is_empty() and Time.get_ticks_msec() >= _round_deadline_ms:
			_note_error("本轮 %d 条候选只回来 %d 条（超时兜底）→ 按已收到的选优" % [
				_inflight.size(), _candidate_replies.size()])
		else:
			return
	# 本轮结束：凑齐或兜底超时
	last_round_ms = Time.get_ticks_msec() - _round_submit_ms
	var replies: Array = _candidate_replies
	_candidate_replies = []
	_inflight.clear()
	_waiting = false
	if replies.is_empty():
		_note_error("REQ 无回复（worker 无响应或已退出）→ 本块直接硬降 | REQ='" + _last_req + "'")
		return
	var best_reply := _pick_best_reply(replies)
	if log_protocol:
		print("[ZzzBridge] REQ -> '", best_reply.substr(0, 80), "' (len=", best_reply.length(),
			", 候选=", replies.size(), ")")
		# 逐回合诊断：预算 vs 实际墙钟。用来定位"偶发 2 倍"是预算变大还是别的开销。
		print("[ZzzBridge][round] gen=", _generation, " 候选=", replies.size(),
			" 预算=", _round_budget_ms, "ms  基线预算=", _round_base_budget_ms,
			"ms  实际=", last_round_ms, "ms")
	_parse_reply(best_reply)


## 多候选选优：按「落点盖到当前版面后的打分」挑最好的一条，并用 margin 防噪声抖动。
## 返回选中的回复字符串。第 0 条（主候选 / beam=100）是基准。
func _pick_best_reply(replies: Array) -> String:
	if replies.size() == 1:
		return str(replies[0].get("reply", ""))
	# 按候选序号排序，保证基准稳定（与提交顺序一致）
	replies.sort_custom(func(a, b): return _tag_index(str(a.get("tag", ""))) < _tag_index(str(b.get("tag", ""))))
	var primary := str(replies[0].get("reply", ""))
	var primary_score := _score_reply(primary)
	if primary_score == INF:
		# 主候选不可用，退而求其次：取第一个能解析出落点的
		for r in replies:
			var rep := str(r.get("reply", ""))
			if _score_reply(rep) != INF:
				return rep
		return primary
	var best := primary
	var best_score := primary_score
	for i in range(1, replies.size()):
		var rep := str(replies[i].get("reply", ""))
		var s := _score_reply(rep)
		if s == INF:
			continue
		if s < best_score - parallel_accept_margin:
			best = rep
			best_score = s
	return best


## 候选序号（tag 形如 "<generation>:<index>:<beam>"）
func _tag_index(tag: String) -> int:
	var parts := tag.split(":")
	if parts.size() >= 2:
		return int(parts[1])
	return 999


## 把一条回复的落点盖到「本次请求的版面」上并打分；越小越好，不可用返回 INF。
## 打分是纯函数（BotBoardEval），不依赖 zzz 自己的评估函数 —— 独立裁判。
func _score_reply(reply: String) -> float:
	var p := _parse_reply_dict(reply)
	if not bool(p.get("ok", false)):
		return INF
	var piece := str(p.get("piece", ""))
	if piece.is_empty():
		return INF
	if TetrisGlobalData.bag_controller == null:
		return INF
	var shape: Array = TetrisGlobalData.bag_controller.get_original_shape(piece)
	if shape.is_empty():
		return INF
	var eval_script = load("res://Scripts/bot_play/bot_board_eval.gd")
	if eval_script == null:
		return INF
	var cells: Array = eval_script.cells_from_shape(shape, int(p.get("rot", 0)))
	if cells.is_empty():
		return INF
	# ⚠ 必须用「已扣掉当前活动方块」的版面：否则落点会和方块自己所在的格子重叠，
	#   BotBoardEval.stamp() 会判定放不下 → 每条候选都返回 INF → 选优静默退化成"永远用主候选"。
	var board := _board_rows_zzz_without_active()
	var stamped: Array = eval_script.stamp(board, cells, int(p.get("x", 0)), int(p.get("y", 0)))
	if stamped.is_empty():
		return INF
	return float(eval_script.score(stamped))


## 当前已锁定堆叠 → zzz 口径的 40 行位掩码（index 0 = 底行 y=89，**包含**活动方块所占格）
func _board_rows_zzz() -> Array:
	var rows: Array = []
	for h in range(40):
		var gy: int = GAME_BOTTOM_Y - h
		var mask := 0
		if gy >= 0:
			for x in range(GAME_WIDTH):
				if TetrisGlobalData.board_get_cell(x, gy) != null:
					mask |= 1 << x
		rows.append(mask)
	return rows


## 同上，但扣掉当前活动方块自己的格子（口径与 _build_request 送给 worker 的版面一致）
func _board_rows_zzz_without_active() -> Array:
	var rows := _board_rows_zzz()
	var shape: Array = TetrisGlobalData.piece_shape
	if shape.is_empty():
		return rows
	var pos: Vector2i = TetrisGlobalData.piece_position
	for y in range(shape.size()):
		var row: Array = shape[y]
		for x in range(row.size()):
			if int(row[x]) != 1:
				continue
			var gy: int = pos.y + y
			var h: int = GAME_BOTTOM_Y - gy
			if h < 0 or h >= 40:
				continue
			var gx: int = pos.x + x
			if gx < 0 or gx >= GAME_WIDTH:
				continue
			rows[h] = int(rows[h]) & ~(1 << gx)
	return rows


## 轻量解析（只取落点字段），与 _parse_reply 的口径一致
func _parse_reply_dict(reply: String) -> Dictionary:
	var out := {"ok": false, "path": "", "piece": "", "x": 0, "y": 0, "rot": 0}
	var text := reply.strip_edges()
	if not text.begins_with("OK"):
		return out
	var body := text.substr(2).strip_edges()
	var parts := body.split(" ", false)
	if parts.is_empty():
		return out
	out["ok"] = true
	out["path"] = String(parts[0])
	if parts.size() >= 5:
		out["piece"] = String(parts[1])
		out["x"] = int(parts[2])
		out["y"] = int(parts[3])
		out["rot"] = int(parts[4])
	return out


# ========== 协议构造 ==========

## 规则/配置行：与本游戏 spin 规则对应
func _build_cfg(gc) -> String:
	var amini := 1
	var aspin := 0
	var tspin := 1
	var immobile_t := 1
	var cl = TetrisGlobalData.clear_line_controller
	if cl != null:
		if TetrisGlobalData.clear_no_spin == 3:
			# 不判定 Spin：bot 也完全不认 spin
			amini = 0
			aspin = 0
			tspin = 0
			immobile_t = 0
		elif TetrisGlobalData.clear_no_spin == 4:
			# 无天赋IV（正常判定 Spin，但每次触发 Spin 上涨 20 行实心行）：
			# Spin 判定本身与默认一致，这里显式走默认值，且不受 Allspin 开关影响
			# （Allspin 会把非 T 卡住也算 full spin，与该 buff 本意不符）。
			amini = 1
			aspin = 0
			tspin = 1
			immobile_t = 1
		elif TetrisGlobalData.clear_no_spin == 1:
			# 只判定 T-Spin（不判 Allspin）：关掉全旋，T-Spin 保持正常判定
			amini = 0
			aspin = 0
		elif TetrisGlobalData.clear_allspin >= 1:
			# Allspin（含全旋II）：非 T 卡住也算 full spin
			amini = 0
			aspin = 1
	# 本游戏规则是「四方向不可移动 → spin」，故 allow_immobile_t = 1
	var hold_flag := 1 if (allow_hold and not TetrisGlobalData.no_hold) else 0
	var gcap := 8
	if TetrisGlobalData.garbage_line_controller != null:
		gcap = TetrisGlobalData.garbage_cap
	# 最后一个字段：游戏当前的旋转系统（0=ASC 1=SRS 2=ARS）。
	# worker 据此选用对应踢墙表，保证 bot 规划的踢墙与游戏实际执行的一致。
	var rot_mode := TetrisGlobalData.piece_rotation_system
	# 第 12/13 个字段：BTB 加成系统（1=surge break / 2=累加奖励）与 PC 附加伤害。
	# 游戏侧是规则的唯一来源，这里原样下发，bot 的伤害模拟才能与实际结算一致。
	# 参考 TetrisClearLine.btb_system_use / pc_damage；pc_damage 是 @export，buff 可在 Inspector 改。
	var btb_system := 1
	var pc_damage := 6
	if cl != null:
		btb_system = int(TetrisGlobalData.clear_btb_system_use)
		pc_damage = int(TetrisGlobalData.clear_pc_damage)
	# 末尾两个字段：游戏的 no_spin 模式与 no_spin4 的实心行惩罚量。
	#   no_spin==2 → worker 把所有 Spin 降级为 Mini（类型与伤害表都要和游戏一致，
	#                否则 Allspin 重复性惩罚会因「游戏记 Mini、引擎记 T-Spin」而漏判）
	#   no_spin==4 → worker 用极大权重惩罚任何 Spin（含 Spin0），使 bot 绝不走 Spin（必死）
	var no_spin_mode := 0
	var no_spin4_rows := 20
	if cl != null:
		no_spin_mode = int(TetrisGlobalData.clear_no_spin)
		no_spin4_rows = int(TetrisGlobalData.clear_no_spin4_solid_rows)
	# 末尾第 16 个字段：玩家可见的 next 个数（ShortNext 系列）。
	# worker 用它把搜索深度（maxDepth）截断到可见数：0 → 完全不做后续块预判，
	# 这样 bot 在「短见」规则下和玩家掌握同样的信息，不会知道完整块序。
	var next_visible := visible_next_count(gc)
	# 末尾第 17 个字段：Allspin_2 模式（全旋II）。
	#   · 非 Spin 消行记 void → 不产生任何攻击，并断开 BTB 链（引擎评估要跟着归零/断链）
	#   · Spin0 判伤害并使 BTB+1（等于强制 spin0_btb_enabled）
	#   · 重复惩罚只比「消行行数」（不比类型），且罚 allspin2_solid_rows(20) 行实心垃圾
	var allspin2_flag := 0
	# 末尾第 18 个字段：Allspin_2 重复惩罚上涨的**实心**行数（Allspin_1 固定 1 行）。
	# 下发它是为了让 worker 把这笔惩罚算进**预测版面**里，而不是只扣评估分：
	# 评估分只作用于本手候选、往下一层就衰减；写成版面填充/垃圾抬升才会影响整棵搜索子树。
	var allspin2_rows := 20
	# Allspin 档位（权威值在 TetrisGlobalData.clear_allspin）：
	#   2/3：行数重复规则生效（引擎的 allspin2 模式就是这套口径）
	#   4/5：类型规则变成「六块每轮各消一遍」、且取消行数重复；惩罚行数改为 allspin_round_solid_rows(42)。
	#        引擎暂时无法表达「轮」，所以这两档**仍按行数重复（更保守的一侧）**处理：
	#        宁可多避开一次，也不能漏判让实战吃 42 行实心垃圾。
	var allspin_mode := int(TetrisGlobalData.clear_allspin)
	if allspin_mode >= 2:
		allspin2_flag = 1
	# 两档惩罚行数要分开下发（游戏 _allspin_repeat_result）：
	#   allspin2_rows      = 「与上一手重复」档（2/3 用；4/5 作为兜底档也用）= clear_allspin2_solid_rows(20)
	#   allspin_round_rows = 「轮内重复」档（4/5 的六块轮 / 行数轮）= allspin_round_solid_rows(42)
	allspin2_rows = int(TetrisGlobalData.clear_allspin2_solid_rows)
	var allspin_round_rows := 0
	if allspin_mode >= 4:
		allspin_round_rows = int(cl.allspin_round_solid_rows) if cl != null else 42
	# 末尾第 20 个字段：surge break 系统下「btb_count >= 4」那一档的加成值。
	# 游戏 _get_btb_bonus()：btb 1~3 → +1；btb >= 4 → 默认 +1，Allspin>=2 → +2，Allspin>=4 → +3。
	# 引擎原先写死 +2，无 buff 时会高估伤害（就是你提到的那个修复）。
	var btb_bonus_high := 1
	if allspin_mode >= 4:
		btb_bonus_high = 3
	elif allspin_mode >= 2:
		btb_bonus_high = 2
	# 末尾第 21/22 字段：Allspin 档位数字（0~5）+ Spin 伤害倍率。
	# 档位数字让引擎能区分 2/3/4/5 各自的重复规则（原来只有布尔，只能表达"是不是 2"）。
	# Spin 伤害倍率：游戏 Allspin_5 起「行数×2」提升为「行数×3」，其余档位是 2。
	var spin_damage_mul := 3 if allspin_mode >= 5 else 2
	# 末尾第 19 个字段：是否处于「快速模拟 + 直接放置」。
	# ⚠ 必须按**实际走的那条路**判断：tetris_controller 里 fast_simulate_whole_plan 优先于
	#   fast_simulate_direct_place（整段计划同帧执行会先 return）。两者语义完全不同：
	#     · whole_plan（现默认）：用同一套 _apply_bot_action 逐步执行，旋转发生位置与正常对局一致
	#       → spin 判定忠实，引擎按自己的 is_last_rotate 判即可，本字段必须为 0。
	#     · direct_place：把方块瞬移到落点后**在落点补记旋转**，游戏对每个落点都满足
	#       last_rotation_occurred，spin 判定退化成纯几何 → 引擎必须同样按"已旋转"处理。
	var direct_place_rotate := 0
	if gc != null and bool(gc.fast_simulate) \
			and not bool(gc.fast_simulate_whole_plan) \
			and bool(gc.fast_simulate_direct_place):
		direct_place_rotate = 1
	return "CFG %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d" % [
		think_budget, gcap, 1, 0, hold_flag,
		1 if allow_180 else 0, amini, aspin, tspin, immobile_t, rot_mode,
		btb_system, pc_damage, no_spin_mode, no_spin4_rows, next_visible, allspin2_flag, allspin2_rows,
		direct_place_rotate, btb_bonus_high, allspin_mode, spin_damage_mul, allspin_round_rows,
	]


## 局面行：40 行位掩码（index 0 = 本游戏 y=89 的底行），排除当前活动方块自身
## 说明：游戏侧状态一律从公共数据区 TetrisGlobalData 取，不再从传入的控制器上摸节点引用。
func _build_request(gc) -> String:
	var drawer = TetrisGlobalData.board_drawer
	if drawer == null:
		return ""
	# 当前方块占用的格子（本游戏坐标），需要在板面里排除
	var self_cells := {}
	var shape: Array = TetrisGlobalData.piece_shape
	var pos: Vector2i = TetrisGlobalData.piece_position
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
				if TetrisGlobalData.board_get_cell(x, gy) != null:
					mask |= 1 << x
		masks.append(str(mask))

	var active: String = TetrisGlobalData.piece_type
	if active.is_empty():
		active = "I"
	var hold_type: String = TetrisGlobalData.piece_hold_type if not TetrisGlobalData.piece_hold_type.is_empty() else "-"
	var can_hold_now := 1 if TetrisGlobalData.piece_can_hold else 0
	var next_str := _build_next(gc)
	var b2b := 0
	var combo := 0
	var cl = TetrisGlobalData.clear_line_controller
	if cl != null:
		b2b = int(TetrisGlobalData.clear_btb_count)
		combo = int(TetrisGlobalData.clear_combo_count)
	var upcome := 0
	if TetrisGlobalData.garbage_line_controller != null \
			and TetrisGlobalData.garbage_line_controller.has_method("get_enter_queue_size"):
		upcome = int(TetrisGlobalData.garbage_line_controller.get_enter_queue_size())

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
	parts.append(str(int(cl.get_last_clear_count()) if cl != null else 0))
	# 重复性惩罚：buff 覆盖优先，其次 @export 默认；仅 allspin 开启时下发。
	#   Allspin_1：与上一手同类型同行数 → 上涨 1 行垃圾，用 repeat_penalty 评估即可。
	#   Allspin_2：只看行数相同 → 上涨 allspin2_solid_rows(默认 20) 行**实心**垃圾（不可消除），
	#              实际等同于判死，因此按「行数 × 5000」折算成与 NoSpin4 同量级的扣分，
	#              并且取游戏值与该折算值的较大者（游戏想调更狠可以直接调大）。
	# ⚠ 下发值必须是为正的「扣分大小」：worker 里是 result.like -= repeat_penalty。
	#   游戏侧 bot_allspin2_repeat_penalty 存的是负数(-1500)，直接下发会变成"奖励重复"，
	#   所以这里统一取绝对值。
	var rp: float = float(_param_overrides.get("repeat_penalty", repeat_penalty))
	if cl != null and TetrisGlobalData.clear_allspin == 2:
		var rows_scale: float = maxf(1.0, float(TetrisGlobalData.clear_allspin2_solid_rows)) * 5000.0
		rp = maxf(absf(float(TetrisGlobalData.clear_allspin2_repeat_penalty)), rows_scale)
	rp = absf(rp)
	parts.append(str(rp if (cl != null and TetrisGlobalData.clear_allspin >= 1) else 0.0))
	# 第 4 个尾参：本游戏 current_rotation_index。
	# 必须下发：worker 里 I/S/Z 的 r0 与 r2、r1 与 r3 格子集合相同，只靠格子匹配会认错旋转态，
	# 于是后续 'c'/'z' 转出的形状与游戏实际不符 → 实际落点偏离决策。
	parts.append(str(int(TetrisGlobalData.piece_rotation_index)))
	# 额外尾部三项（引擎用固定下标解析，追加在末尾向后兼容）：
	#   上一手消行所用方块编号 / Allspin_4/5「类型轮」已用掩码 / Allspin_5「行数轮」已用掩码。
	# 对应游戏 _allspin_repeat_result() 里 mode==3 的「同块类型重复」与 mode>=4 的「六块轮」。
	parts.append(str(_last_clear_piece_code(cl)))
	parts.append(str(_allspin_round_mask(cl, "_allspin_round_used_types", 6)))
	# Allspin_5 的「行数轮」现在是**两轮独立**：{0,3} 一轮、{1,2} 一轮（游戏 ALLSPIN_ROUND_COUNTS_03/_12）
	parts.append(str(_allspin_round_mask(cl, "_allspin_round_used_counts", 4)))
	parts.append(str(_allspin_round_mask(cl, "_allspin_round_used_counts_03", 4)))
	# 追加第 4 项：塔发送倍率 extra_pressure_mult ×1000（Allspin_5 每次 Void +0.01 累加）。
	# 引擎把它当乘法作用于自己发出去的攻击，从而正确评估「用 Void 换倍率」的取舍。
	var _press := 1000
	if TetrisGlobalData.tower_controller != null:
		_press = int(round(float(TetrisGlobalData.tower_controller.extra_pressure_mult) * 1000.0))
	parts.append(str(_press))
	# 追加第 5 项：本手思考预算（ms，0 = 沿用 CFG 的 think）。
	# 由控制器按当前动态 PPS 规划后写入 think_budget_now —— 逐 REQ 下发；
	# 它与 CFG 的 think 分开，因此"预算变化"不会进入决策参数签名、不会作废旧计划。
	parts.append(str(int(think_budget_now)))
	return " ".join(parts)


## 上一手消行所用方块的编号（Z/S/T/I/J/L → 0..5，其它/无记录 → -1）
func _last_clear_piece_code(cl) -> int:
	if cl == null:
		return -1
	var t := str(cl.get("_last_clear_piece_type"))
	if t.is_empty():
		return -1
	return "ZSTIJL".find(t[0])


## Allspin_4/5 的「轮」已用成员掩码（读游戏侧数组；字段不存在时返回 0）
func _allspin_round_mask(cl, field: String, key_total: int) -> int:
	if cl == null:
		return 0
	var used = cl.get(field)
	if used == null or not (used is Array):
		return 0
	var mask := 0
	for k in used:
		var idx := int(k)
		if idx >= 0 and idx < key_total:
			mask |= 1 << idx
	return mask


## 游戏的消行类型字符串 → zzz 的 ASpinType 数值
## （None=0 / TSpin=1 / AllSpin=2 / TSpinMini=3 / ASpinMini=4 / -1=「无有效记录」）
## ⚠「_last_clear_type 为空」的语义**随模式不同**，这里必须分开处理：
##   · Allspin_2：只有「还没消过行」才会是空（任何消行都会记成 spin 类型或 "void"），
##     且游戏 _is_allspin2_repeat 明确有 is_empty() → 不算重复 → 所以返回 -1。
##   · 其它模式（Allspin_1 / NoSpin 系列 / 无 buff）：非 Spin 消行记录的就是空串，
##     游戏那边是字符串相等比较（"" == "" → **算重复**），因此必须返回 0，
##     否则「连续两次同行数非 Spin 消行」会被漏判（NoSpin3 + Allspin_1 的典型场景）。
## "void" 是 Allspin_2 的有效记录（行数 -1 承担语义），返回 0 而不是 -1。
func _last_spin_type(cl) -> int:
	if cl == null:
		return 0
	var t := str(cl.get_last_clear_type())
	if t.is_empty():
		return -1 if int(TetrisGlobalData.clear_allspin) == 2 else 0
	if t == "void":
		return 0
	var is_mini := t.find("Mini") != -1
	if t.find("T-Spin") != -1:
		return 3 if is_mini else 1
	return 4 if is_mini else 2


## bot 允许使用的 next 个数。
## ⚠ 现行策略：**不再随 ShortNext 限制** —— 无论短见怎么开，bot 一律使用自身全部可知的块序
##   （NEXT_MAX 个）。短见系列只是「玩家侧显示」的规则，不再作为 bot 的信息上限。
##   （原先按 ShortNext_1~4 → next_count、ShortNext_5 → 0 截断搜索深度；已取消。）
## 保留成函数是因为 CFG 的 next_visible 字段与「决策参数签名」都还引用它。
func visible_next_count(_gc) -> int:
	if next_max_override > 0:
		return next_max_override
	return NEXT_MAX


## 搜索深度上限的**单一来源**（与 NEXT_MAX 同一个值，不需要实例）。
## tetris_controller._bot_cfg_signature_now() 用它，避免再写死一个字面量 14
## —— 否则改上限时「决策参数签名」会和实际下发的值不一致，签名就失去意义。
static func bot_next_max() -> int:
	return NEXT_MAX


func _build_next(gc) -> String:
	var out := ""
	var vis: int = visible_next_count(gc)
	if TetrisGlobalData.bag_controller == null:
		return "I"
	var q: Array = TetrisGlobalData.bag_controller.get_queue_copy()
	# vis 已夹在 [0, NEXT_MAX] 内，这里只需再按队列实际长度收敛
	for i in range(min(vis, q.size())):
		var t := str(q[i])
		if t.length() > 0:
			out += t.substr(0, 1)
	return out if not out.is_empty() else "I"


# ========== 回复解析 ==========

func _parse_reply(reply: String) -> void:
	clear_plan()
	if reply.is_empty():
		_note_error("REQ 无回复（worker 无响应或已退出）→ 本块直接硬降 | REQ='" + _last_req + "'")
		return
	if not reply.begins_with("OK"):
		_note_error("REQ 返回非 OK：'" + reply.substr(0, 60) + "' → 本块直接硬降 | REQ='" + _last_req + "'")
		return
	var body := reply.substr(2).strip_edges()
	var parts := body.split(" ", false)
	if parts.is_empty():
		_note_error("REQ 返回空路径（worker 没搜到方案）→ 本块直接硬降 | REQ='" + _last_req + "'")
		return
	var path := String(parts[0])
	# 可选尾随的决策落点："<方块> <最小x> <最小y(zzz,y向上)> <旋转>" → 换算成本游戏坐标
	_plan_target_valid = false
	if parts.size() >= 5:
		_plan_target_valid = true
		_plan_target_piece = String(parts[1])
		_plan_target_x = int(parts[2])
		_plan_target_y = GAME_BOTTOM_Y - int(parts[3])
		_plan_target_rot = int(parts[4])
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
			"Z":
				_plan.append(BotAction.new("rotate_left", ["rotate_left"], "rotate_left"))
			"c":
				_plan.append(BotAction.new("rotate_right", ["rotate_right"], "rotate_right"))
			"C":
				_plan.append(BotAction.new("rotate_right", ["rotate_right"], "rotate_right"))
			"x":
				# zzz 的 'x' = wall_kick_opposite，即一次 180° 旋转（游戏有 rotate_180，踢墙用同一张 ASC 表）
				_plan.append(BotAction.new("rotate_180", ["rotate_180"], "rotate_180"))
			"X":
				_plan.append(BotAction.new("rotate_180", ["rotate_180"], "rotate_180"))
			" ":
				# zzz 路径里表示「下移一格」的占位（重力步），对应游戏的 down_one
				_plan.append(BotAction.new("down_one", ["down_one"], "down_one"))
			"V":
				_plan.append(BotAction.new("hard_drop", ["hard_drop"], "hard_drop"))
			_:
				# 未知字符会让这一步被静默丢掉 → 实际落点和决策不一致，必须报出来
				_note_error("worker 路径里出现未知操作字符 '%s'（已忽略该步，落点可能与决策不符）" % c)


# 说明：管道 I/O 与后台线程已全部搬到 BotWorkerPool（见 bot_worker_pool.gd）：
#   · 每个 worker 进程一条专属线程，只做「写字符串 + 轮询读一行」，不碰任何游戏状态；
#   · 本文件只在主线程调用 _build_cfg / _build_request / _parse_reply，因此天然线程安全；
#   · 回包带作业代号，迟到/作废的回包会被丢弃（多 worker 并行的安全前提）。


## 记录一条错误（主线程调用；工作线程的错误由池的 drain_errors 带回主线程再打印）
func _note_error(msg: String) -> void:
	_last_error = msg
