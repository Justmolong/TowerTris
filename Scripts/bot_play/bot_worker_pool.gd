extends RefCounted
class_name BotWorkerPool

## zzztoj worker 进程池：N 个**常驻子进程**，每个进程配一条**专属后台线程**。
##
## 为什么是"多进程 + 每进程一线程"而不是"单进程多线程"：
##   zzztoj_worker.cpp 用的是全局 static TetrisEngine 加一堆全局配置，且 ai.cpp 里还有全局锁，
##   整套按单实例设计 —— 在同一个进程里跑多个搜索会互相踩。所以并行度靠**开多个进程**拿到。
##   实测（16 核 / 32 线程）：1→16 个并发进程，单次调用耗时完全不变（303ms），总 CPU 线性增长。
##
## 线程模型与安全边界（重要）：
##   · 主线程：构造**作业**（作业里只有字符串和纯数据，绝不含节点/场景树引用）、
##     投递到 _pending、在 drain_replies() 里消费回包。
##   · 工作线程：只做两件事 —— 往自己那条管道写字符串、轮询读回一行。
##     绝不碰 TetrisGlobalData、场景树、也不碰别的 worker 的 FileAccess。
##   · 每条线程独占自己那个进程的 stdio FileAccess（每个线程读写自己的句柄 → 天然线程安全）。
##   · 回包经 _reply_mutex 保护的队列交回主线程，由主线程解析成 BotAction。
##     解析放主线程是刻意的：BotAction 是 Godot 对象，跨线程持有引用没有意义且容易出错。
##
## 协议：每条命令一收一回（PING/CFG/PARAM/REQ 都是）。一个 worker 同一时刻只跑一个作业。

const WORKER_FILENAME := "zzztoj_worker.exe"
## 开发/编辑器模式：res:// 直接映射项目磁盘目录（worker 由 zzztoj/build_worker.ps1 输出到此）
const WORKER_RES_DIR := "res://zzztoj/worker"
## 导出模式：exe 同目录下的子目录（由导出脚本把 worker 复制过去）
const WORKER_EXE_SUBDIR := "zzztoj"
## 单条命令等待回复的上限（毫秒）默认值，可被 pool.reply_timeout_ms 覆盖
const DEFAULT_REPLY_TIMEOUT_MS := 2000
## worker 意外退出后的自动重启上限与延迟
const MAX_RESTARTS := 3
const RESTART_DELAY := 1.0

var worker_count: int = 1
var reply_timeout_ms: int = DEFAULT_REPLY_TIMEOUT_MS
var log_protocol: bool = false
var verbose: bool = false

## 每个 worker 一个上下文（Dictionary，避免为内部结构再开一个 class）
##   id/thread/stdio/stderr/pid/running/started/alive/queue/sem
##   restarts/restart_delay/should_restart/dead_checks/death_logged/cfg_sent
var _workers: Array = []

## 主线程 → 工作线程：待发作业全部放在各 worker 的私有队列里
## （不再有全局队列：那会让"哪个线程拿到哪个作业"不可控，代号路由也就失去意义）
## 工作线程 → 主线程：回包 [{job_id, worker_id, reply}]
var _replies: Array = []
var _reply_mutex := Mutex.new()
## 工作线程 → 主线程：错误/日志（主线程打印，避免在线程里 push_error）
var _errors: Array = []
var _last_error: String = ""

var _next_job_id: int = 1
var _resolved_exe: String = ""
var _start_failed_reason: String = ""


func _init(count: int = 1) -> void:
	worker_count = maxi(1, count)


func reply_timeout_ms_of(cmd: String) -> int:
	return maxi(200, reply_timeout_ms)


# ========== 生命周期 ==========

## 启动全部 worker（幂等）。返回成功启动的个数。
func start() -> int:
	var exe := resolve_worker_path()
	if exe.is_empty():
		_start_failed_reason = _last_error
		return 0
	_resolved_exe = exe
	var ok := 0
	for i in range(worker_count):
		if _start_one(i, exe):
			ok += 1
	return ok


## 定位 worker 可执行文件（按顺序尝试多种可能位置，便于编辑器/导出/自定义放置）
func resolve_worker_path() -> String:
	var tried: Array = []
	var exe_dir := OS.get_executable_path().get_base_dir()
	for cand in [
		exe_dir.path_join(WORKER_EXE_SUBDIR).path_join(WORKER_FILENAME),
		exe_dir.path_join(WORKER_FILENAME),
	]:
		tried.append(cand)
		if FileAccess.file_exists(cand):
			return cand
	for rel in [WORKER_RES_DIR, "res://zzztoj"]:
		var dev: String = ProjectSettings.globalize_path(rel).path_join(WORKER_FILENAME)
		tried.append(dev)
		if FileAccess.file_exists(dev):
			return dev
	_last_error = "未找到 %s，已尝试：%s" % [WORKER_FILENAME, str(tried)]
	return ""


func start_failed_reason() -> String:
	return _start_failed_reason


## 运行期把池扩到 n 个 worker（只增不减；减容要整池重启，代价大且游戏里用不上）。
## 用于「开局只启 1 个，首次请求时补齐并行度」——避免场景初始化时同时 prepare 多次搜索上下文。
func set_worker_count(n: int) -> void:
	var want: int = maxi(1, n)
	worker_count = maxi(worker_count, want)
	if _resolved_exe.is_empty():
		_resolved_exe = resolve_worker_path()
	if _resolved_exe.is_empty():
		_start_failed_reason = _last_error
		return
	while _workers.size() < want:
		var id := _workers.size()
		if not _start_one(id, _resolved_exe):
			break   # 起不来就保持现状，调用方按 alive_count() 决定实际用几个候选


## 停掉并清空超出 want 的 worker（一般不用；给测试和极端调参留口子）
func shrink_to(n: int) -> void:
	var want: int = maxi(1, n)
	while _workers.size() > want:
		var ctx: Dictionary = _workers.pop_back()
		ctx["should_restart"] = false
		ctx["running"] = false
		if ctx["stdio"] != null:
			ctx["stdio"].store_string("QUIT\n")
			ctx["stdio"].flush()
		ctx["sem"].post()
		var t = ctx["thread"]
		if t != null and t.is_started():
			t.wait_to_finish()
	worker_count = _workers.size()


func _start_one(id: int, exe: String) -> bool:
	var res: Dictionary = OS.execute_with_pipe(exe, [], false)
	if res.is_empty() or not res.has("stdio"):
		_last_error = "无法启动 %s（%s）" % [WORKER_FILENAME, exe]
		return false
	# 复用已存在的槽位（重启场景）时先清掉旧现场
	if _workers.size() > id:
		_workers[id] = _make_ctx(id, res)
	else:
		_workers.append(_make_ctx(id, res))
	var ctx: Dictionary = _workers[id]
	ctx["thread"] = Thread.new()
	ctx["thread"].start(_worker_loop.bind(ctx))
	if verbose or log_protocol:
		print("[BotPool] worker#", id, " 已启动 pid=", ctx["pid"])
	# 握手：线程自己去发 PING 并丢弃回包（避免主线程/工作线程争抢同一条管道）
	_enqueue_raw(ctx, "PING")
	return true


func _make_ctx(id: int, res: Dictionary) -> Dictionary:
	return {
		"id": id,
		"stdio": res.get("stdio"),
		"stderr": res.get("stderr"),
		"pid": int(res.get("pid", -1)),
		"thread": null,
		"running": true,
		"started": true,
		"alive": true,
		"queue": [],
		"queue_mutex": Mutex.new(),
		"sem": Semaphore.new(),
		"in_job": false,
		"restarts": 0,
		"restart_delay": 0.0,
		"should_restart": false,
		"dead_checks": 0,
		"death_logged": false,
		"cfg_sent": "",
	}


func stop() -> void:
	for ctx in _workers:
		ctx["should_restart"] = false
		ctx["running"] = false
		var stdio = ctx["stdio"]
		if stdio != null:
			stdio.store_string("QUIT\n")
			stdio.flush()
		ctx["sem"].post()
	for ctx in _workers:
		var t = ctx["thread"]
		if t != null and t.is_started():
			t.wait_to_finish()
		ctx["thread"] = null
		ctx["stdio"] = null
		ctx["stderr"] = null
		ctx["started"] = false
	_workers.clear()


func is_ready() -> bool:
	for ctx in _workers:
		if bool(ctx["started"]) and bool(ctx["alive"]):
			return true
	return false


func alive_count() -> int:
	var n := 0
	for ctx in _workers:
		if bool(ctx["started"]) and bool(ctx["alive"]):
			n += 1
	return n


func get_info() -> Dictionary:
	var pids: Array = []
	var queued: Array = []
	for ctx in _workers:
		pids.append(int(ctx["pid"]))
		queued.append(queue_len(ctx) + (1 if bool(ctx["in_job"]) else 0))
	return {
		"engine": "zzztoj",
		"worker_count": _workers.size(),
		"alive": alive_count(),
		"pids": pids,
		"queued": queued,
		"inflight": in_flight(),
		"error": _last_error,
	}


# ========== 作业投递（主线程调用） ==========

## 建立一条作业（纯数据，可安全交给工作线程）。
## prefer_worker：建议落到的 worker 下标（-1 = 让池自己挑）。
## ⚠ 一轮并行候选**必须**把第 i 个候选钉到第 i 个 worker：
##   曾经只按"当前排队长度最短"挑，而轮内所有队列都是 0（并列）→ 每次都会挑回 worker 0，
##   于是 4 条候选里 2 条落在同一个 worker 上串行执行，另外还有 worker 空转，
##   单轮墙钟从 ~115ms 变成 ~230ms（实测 3 次里中 2 次），在游戏里表现就是一顿一顿。
func make_job(cfg_line: String, params: Array, req_line: String, tag: String = "",
		prefer_worker: int = -1) -> Dictionary:
	var id := _next_job_id
	_next_job_id += 1
	return {
		"id": id,
		"cfg": cfg_line,
		"params": params,      # Array[String]，每条是完整 "PARAM x y" 行
		"req": req_line,
		"tag": tag,
		"prefer_worker": prefer_worker,
		"t_submit_ms": Time.get_ticks_msec(),
	}


## 投递一批作业：一轮并行搜索用这个。每个作业落到一个（尽量空闲的）worker。
## 作业数可以多于 worker 数 —— 多出来的会在各 worker 队列里排队，量力而行。
func submit_all(jobs: Array) -> void:
	for j in jobs:
		dispatch_auto(j)


# ========== 回包消费（主线程调用） ==========

## 取出本轮所有已完成回包（不清空前会一直保留）。
func drain_replies() -> Array:
	_reply_mutex.lock()
	var out: Array = _replies
	_replies = []
	_reply_mutex.unlock()
	return out


## 取出并打印工作线程攒下的错误（主线程调用 → 保证 push_warning 在主线程）
func drain_errors() -> Array:
	_reply_mutex.lock()
	var out: Array = _errors
	_errors = []
	var err := _last_error
	_last_error = ""
	_reply_mutex.unlock()
	if not err.is_empty():
		out.append(err)
	return out


## 当前仍在途的作业数（各 worker 队列 + 执行中）
func in_flight() -> int:
	var n := 0
	for ctx in _workers:
		n += queue_len(ctx)
		if bool(ctx["in_job"]):
			n += 1
	return n


# ========== 工作线程 ==========

## 每条线程独占一个 worker 进程：抢作业 → 写管道 → 轮询读回复。
## 队列：主线程 append + post，本线程在这里 pop —— 全部在 queue_mutex 下进行。
func _worker_loop(ctx: Dictionary) -> void:
	while bool(ctx["running"]):
		ctx["sem"].wait()
		if not bool(ctx["running"]):
			break
		# 一次唤醒把队列排空（主线程可能连续投了多个作业）
		while bool(ctx["running"]):
			var job: Dictionary = {}
			ctx["queue_mutex"].lock()
			if not ctx["queue"].is_empty():
				job = ctx["queue"].pop_front()
			ctx["queue_mutex"].unlock()
			if job.is_empty():
				break
			ctx["in_job"] = true
			if str(job.get("tag", "")) == "internal":
				# 内部命令（握手等）：只收不投回包
				_transact(ctx, str(job.get("req", "")))
			else:
				_run_job(ctx, job)
			ctx["in_job"] = false


## 真正的一次收发：CFG（变化时）→ PARAM → REQ
func _run_job(ctx: Dictionary, job: Dictionary) -> void:
	var stdio = ctx["stdio"]
	if stdio == null:
		_note_error("worker#%d 管道不可用" % int(ctx["id"]))
		_push_reply(int(ctx["id"]), job, "")
		return
	# CFG 变了才重发（与旧实现的 _cfg_sent 语义一致）
	var cfg := str(job.get("cfg", ""))
	if cfg != ctx["cfg_sent"]:
		ctx["cfg_sent"] = cfg
		if not cfg.is_empty():
			_transact(ctx, cfg)
	for p in job.get("params", []):
		_transact(ctx, str(p))
	var req := str(job.get("req", ""))
	var reply := _transact(ctx, req) if not req.is_empty() else ""
	_push_reply(int(ctx["id"]), job, reply)


## 写一条命令并轮询等待其回复（每 1ms 轮询，最多 reply_timeout_ms 毫秒）
func _transact(ctx: Dictionary, cmd: String) -> String:
	var stdio = ctx["stdio"]
	if stdio == null:
		return ""
	stdio.store_string(cmd + "\n")
	stdio.flush()
	var waited := 0
	var timeout: int = maxi(200, reply_timeout_ms)
	while waited < timeout and bool(ctx["running"]):
		var line: String = stdio.get_line()
		if line.is_empty():
			OS.delay_msec(1)
			waited += 1
			continue
		return line.strip_edges()
	_note_error("worker#%d 命令等待 %.1fs 无回复：%s" % [
		int(ctx["id"]), timeout / 1000.0, cmd.substr(0, 24)])
	return ""


## 主线程投递作业到某个 worker 的私有队列（全部在 queue_mutex 下）
func dispatch(ctx: Dictionary, job: Dictionary) -> void:
	ctx["queue_mutex"].lock()
	ctx["queue"].append(job)
	ctx["queue_mutex"].unlock()
	ctx["sem"].post()


## 把作业塞进池里（主线程调用）。
## 优先用作业自带的 prefer_worker；只有它不可用时才退化为"挑排队最短的"。
func dispatch_auto(job: Dictionary) -> void:
	if _workers.is_empty():
		return
	var idx := int(job.get("prefer_worker", -1))
	if idx >= 0 and idx < _workers.size():
		var ctx0: Dictionary = _workers[idx]
		if bool(ctx0["started"]) and bool(ctx0["alive"]):
			dispatch(ctx0, job)
			return
	var best: Dictionary = _workers[0]
	for ctx in _workers:
		if queue_len(ctx) < queue_len(best):
			best = ctx
	dispatch(best, job)


## 某 worker 私有队列里的待发作业数（线程安全）
func queue_len(ctx: Dictionary) -> int:
	ctx["queue_mutex"].lock()
	var n: int = ctx["queue"].size()
	ctx["queue_mutex"].unlock()
	return n


## 投递一条内部命令（握手等，不回包）
func _enqueue_raw(ctx: Dictionary, cmd: String) -> void:
	dispatch(ctx, {"id": -1, "cfg": "", "params": [], "req": cmd, "tag": "internal"})


func _push_reply(worker_id: int, job: Dictionary, reply: String) -> void:
	_reply_mutex.lock()
	_replies.append({
		"job_id": int(job.get("id", -1)),
		"worker_id": worker_id,
		"tag": str(job.get("tag", "")),
		"reply": reply,
		"t_done_ms": Time.get_ticks_msec(),
	})
	_reply_mutex.unlock()


func _note_error(msg: String) -> void:
	_reply_mutex.lock()
	_last_error = msg
	_reply_mutex.unlock()


## 从主线程直接给某个 worker 发一条命令并等回复（心跳/退出等；会在主线程阻塞）
func send_sync(worker_index: int, cmd: String, timeout_ms: int = 500) -> String:
	if worker_index < 0 or worker_index >= _workers.size():
		return ""
	var ctx: Dictionary = _workers[worker_index]
	var stdio = ctx["stdio"]
	if stdio == null:
		return ""
	stdio.store_string(cmd + "\n")
	stdio.flush()
	var waited := 0
	while waited < timeout_ms:
		var line: String = stdio.get_line()
		if line.is_empty():
			OS.delay_msec(1)
			waited += 1
			continue
		return line.strip_edges()
	return ""


## 主线程侧的存活检查与重启（旧 zzz_bridge 的 _check_worker_alive / _tick_restart 搬进来）
func tick_health(delta: float) -> void:
	for ctx in _workers:
		_check_alive(ctx)
		_tick_restart(ctx, delta)


func _check_alive(ctx: Dictionary) -> void:
	if not bool(ctx["started"]) or int(ctx["pid"]) <= 0:
		return
	if OS.is_process_running(int(ctx["pid"])):
		ctx["dead_checks"] = 0
		return
	# 退出码 259 (STILL_ACTIVE) 说明进程其实还在（查询失败/句柄受限），不要误判成崩溃
	var code := OS.get_process_exit_code(int(ctx["pid"]))
	if code == 259:
		ctx["dead_checks"] = 0
		return
	ctx["dead_checks"] = int(ctx["dead_checks"]) + 1
	if int(ctx["dead_checks"]) < 3:
		return
	ctx["dead_checks"] = 0
	ctx["alive"] = false
	ctx["started"] = false
	if not bool(ctx["death_logged"]):
		ctx["death_logged"] = true
		_note_error("worker#%d 进程已退出（pid=%d, exit_code=%d）" % [int(ctx["id"]), int(ctx["pid"]), code])
	ctx["restart_delay"] = RESTART_DELAY
	ctx["should_restart"] = true


func _tick_restart(ctx: Dictionary, delta: float) -> void:
	if not bool(ctx["should_restart"]) or bool(ctx["started"]):
		return
	if int(ctx["restarts"]) >= MAX_RESTARTS:
		if float(ctx["restart_delay"]) > 0.0:
			ctx["restart_delay"] = 0.0
			_note_error("worker#%d 已连续退出 %d 次，停止重启（并行度下降但仍可用）" % [
				int(ctx["id"]), int(ctx["restarts"])])
		return
	if float(ctx["restart_delay"]) > 0.0:
		ctx["restart_delay"] = maxf(0.0, float(ctx["restart_delay"]) - delta)
		return
	if _resolved_exe.is_empty():
		ctx["should_restart"] = false
		return
	ctx["restarts"] = int(ctx["restarts"]) + 1
	ctx["cfg_sent"] = ""       # 新 worker 需要重新下发 CFG
	ctx["in_job"] = false
	_note_error("worker#%d 尝试重启（第 %d/%d 次）" % [
		int(ctx["id"]), int(ctx["restarts"]), MAX_RESTARTS])
	_start_one(int(ctx["id"]), _resolved_exe)
