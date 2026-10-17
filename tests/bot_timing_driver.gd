extends Node2D

## 【实机卡顿测量工具】跑真实 tetris 场景 + bot 模式，报告节奏与卡顿。
##
## 用法（需要一个把本脚本挂在 Driver 节点上的临时场景）：
##   1) 把 Tscns/tetris_verify.tscn 的 Driver 节点临时加上：
##        script = ExtResource("<指向 res://tests/bot_timing_driver.gd>")
##      （该 .tscn 是 git 跟踪的，测完请 `git checkout -- Tscns/tetris_verify.tscn` 还原）
##   2) 运行：
##        godot --headless res://Tscns/tetris_verify.tscn -- <秒数> [worker数] [单候选1/0] [NEXT_MAX覆盖]
##      例：... -- 14 1 1 14   → 单 worker、单候选、搜索深度 14
##   3) 参数说明：
##        <秒数>     测量时长（默认 10）
##        [worker数] 并行 worker 数（-1 = 不改）
##        [单候选]   1 = 把 parallel_beams 缩成 [100]（真正的单候选基线）
##        [NEXT_MAX] >0 = 覆盖搜索深度（0 = 用桥的默认 25）
##
## 输出：帧间隔分布、顿帧计数、每块间隔的 50ms 分桶（成簇的 2 倍值是"一顿一顿"的特征）。
## 注意：`--script` 模式下没有自动加载，所以本脚本**必须**通过场景运行，不能用 --script。

var _frames: Array = []
var _last_frame_usec := 0
var _last_lock_ms := 0
var _locks := 0
var _stall: Array = []
var _controller = null
var _bridge = null
var _deadline_ms := 0
var _started_ms := 0
var _diag_timer := 0.0
var _reported := false
var _idle_frames := 0
var _warmup_frames := 8
var _ready_done := false
var _want_workers := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 10.0
	_want_workers = int(args[1]) if args.size() > 1 else -1
	_deadline_ms = 0
	_started_ms = Time.get_ticks_msec()
	var scene = load("res://Tscns/tetris.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_controller = scene.find_child("TetrisController", true, false)
	if _controller == null:
		print("[probe] FATAL 找不到 TetrisController")
		get_tree().quit(1)
		return
	_controller.bot_mode = true
	await get_tree().process_frame
	await get_tree().process_frame
	_bridge = _controller.get("_zzz_bridge")
	# ⚠ 不要在这里用 set_parallel_workers()：它会 stop()+start() 重启整个池，
	#   而池的重启是在游戏运行中发生的（可能有在途作业），实测会导致卡死。
	#   测量用「直接改字段 + 补齐池」这条路：只增不减，且不重启已有 worker。
	if _bridge != null and _want_workers > 0:
		_bridge.parallel_workers = _want_workers
		_bridge._ensure_pool_size()
	print("[probe] 配置: bot_mode=true 并行度请求=", _want_workers,
		" bridge.parallel_workers=", (_bridge.get("parallel_workers") if _bridge != null else -1),
		" 池worker数=", (_bridge._pool.worker_count if (_bridge != null and _bridge._pool != null) else -1),
		" 存活=", (_bridge._pool.alive_count() if (_bridge != null and _bridge._pool != null) else -1))
	if _bridge != null:
		print("[probe] 桥: think_budget=", _bridge.think_budget,
			" think_budget_now=", _bridge.think_budget_now,
			" parallel_beams=", _bridge.parallel_beams)
		# 关掉逐条协议日志（太吵）；只看回合级诊断
		_bridge.log_protocol = false
		# 第 5 个参数传 1 = 打开回合级诊断（预算 vs 实际墙钟）
		if args.size() > 4 and int(args[4]) == 1:
			_bridge.log_protocol = true
			print("[probe] 已打开回合级诊断 [round]")
		# 允许用第 3 个参数把 parallel_beams 缩到 1 个候选（真正的单候选基线）
		if args.size() > 2 and int(args[2]) == 1:
			var single: Array[int] = [100]
			_bridge.parallel_beams = single
			print("[probe] parallel_beams 已缩为 [100]（单候选基线）")
	TetrisGlobalData.piece_locked.connect(_on_locked)
	# 第 4 个参数：NEXT_MAX 覆盖（0 = 不改，用 25）
	if args.size() > 3 and int(args[3]) > 0:
		_bridge.next_max_override = int(args[3])
		print("[probe] next_max_override = ", _bridge.next_max_override)
	# 游戏结束时至少把报告打出来，别让探测一直等到超时。
	# ⚠ game_ended 是 **tetris_controller** 上的 signal（不是 TetrisGlobalData 的），
	#   写成 TetrisGlobalData.game_ended 会报 "Invalid access to property or key 'game_ended'"。
	if _controller.has_signal("game_ended"):
		_controller.game_ended.connect(_on_game_ended)
	else:
		print("[probe] 警告：控制器上没有 game_ended 信号，改由 _process 轮询方块状态")
	_deadline_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_last_frame_usec = Time.get_ticks_usec()
	_last_lock_ms = Time.get_ticks_msec()
	_ready_done = true


func _on_game_ended() -> void:
	if not _reported:
		print("[probe] 收到 game_ended → 提前出报告")
		_reported = true
		_report()
		get_tree().quit(0)


func _on_locked() -> void:
	var now := Time.get_ticks_msec()
	_locks += 1
	_stall.append(now - _last_lock_ms)
	_last_lock_ms = now


func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	var dt := (now_usec - _last_frame_usec) / 1000.0
	_last_frame_usec = now_usec
	if not _ready_done:
		return
	if _warmup_frames > 0:
		_warmup_frames -= 1
		return
	_frames.append(dt)
	# 顶死兜底：游戏结束后不再有锁块，靠这个把报告打出来（否则要等到超时）
	# ⚠ 判据用 "连续很多帧没有活动方块"，而不是依赖某个信号名（信号在控制器上，名字易变）。
	if TetrisGlobalData.piece_shape.is_empty() and _locks > 0:
		_idle_frames += 1
		if _idle_frames > 120:
			if not _reported:
				_reported = true
				print("[probe] 连续 120 帧无活动方块（顶死）→ 出报告")
				_report()
			get_tree().quit(0)
			return
	else:
		_idle_frames = 0
	# 周期性打印桥/控制器的内部状态：一旦卡住，最后一行就说明卡在哪
	_diag_timer += dt
	if _diag_timer >= 1000.0:
		_diag_timer = 0.0
		_dump_state()
	if Time.get_ticks_msec() >= _deadline_ms:
		if not _reported:
			_reported = true
			_report()
		get_tree().quit(0)


func _dump_state() -> void:
	if _bridge == null:
		print("[diag] 桥为空")
		return
	var pool = _bridge._pool
	print("[diag] t=%dms 帧=%d 锁=%d waiting=%s inflight=%d candidates=%d gen=%d 上回合耗时=%dms 重复请求=%d 池alive=%d 池inflight=%d" % [
		Time.get_ticks_msec() - _started_ms, _frames.size(), _locks,
		str(_bridge.is_waiting_decision()),
		_bridge._inflight.size(), _bridge._candidate_replies.size(), _bridge._generation,
		_bridge.last_round_ms, _bridge._dup_requests,
		(pool.alive_count() if pool != null else -1),
		(pool.in_flight() if pool != null else -1)])
	# 每条候选作业的真实往返耗时（池在回包里带了 t_submit_ms / t_done_ms）
	for r in _bridge._candidate_replies:
		print("         job#%d tag=%s 往返=%dms 回复=%s" % [
			int(r.get("job_id", -1)), str(r.get("tag", "")),
			int(r.get("t_done_ms", 0)) - int(r.get("t_submit_ms", 0)),
			str(r.get("reply", "")).substr(0, 40)])
	if pool != null:
		print("         pool_info=", pool.get_info())
		print("         控制器 has_plan=", _controller.has_method("_process_bot_control"),
			" plan=", (not _bridge.is_plan_empty()), " 方块=", TetrisGlobalData.piece_type,
			" shape空=", TetrisGlobalData.piece_shape.is_empty())


func _report() -> void:
	print("")
	print("===== 实机测量 =====")
	print("时长 ", Time.get_ticks_msec() - _started_ms, " ms  帧数 ", _frames.size(), "  锁块 ", _locks)
	var f := _frames.duplicate()
	f.sort()
	var over16 := 0
	var over33 := 0
	var over50 := 0
	var over100 := 0
	for v in _frames:
		if v > 16.7:
			over16 += 1
		if v > 33.3:
			over33 += 1
		if v > 50.0:
			over50 += 1
		if v > 100.0:
			over100 += 1
	if f.size() > 0:
		print("帧间隔 中位 %.2f  90%% %.2f  99%% %.2f  最大 %.1f ms" % [
			_pct(f, 50), _pct(f, 90), _pct(f, 99), f[f.size() - 1]])
	print("顿帧 >16.7ms=", over16, "  >33.3ms=", over33, "  >50ms=", over50, "  >100ms=", over100)
	# 关键指标：块间隔的"簇"。正常应按 PPS 稳定在 ~333ms；若出现成簇的 ~2 倍值，
	# 说明又发生了"作废在途回合 → 重新提交 → worker 被占满"的老问题。
	var buckets := {}
	for v in _stall.slice(1, _stall.size()):
		var b := int(float(v) / 50.0) * 50
		buckets[b] = int(buckets.get(b, 0)) + 1
	var keys := buckets.keys()
	keys.sort()
	var bk: Array = []
	for k in keys:
		bk.append("%dms×%d" % [int(k), int(buckets[k])])
	print("块间隔分布(50ms 分桶): ", " ".join(bk))
	if _stall.size() > 1:
		var s := _stall.slice(1, _stall.size())   # 首块间隔不计（含初始化）
		var sum := 0.0
		var mx := 0.0
		for v in s:
			sum += float(v)
			mx = maxf(mx, float(v))
		s.sort()
		print("每块间隔 均 %.1f ms (PPS %.2f)  中位 %.0f  最大 %.0f" % [
			sum / s.size(), 1000.0 * s.size() / maxf(1.0, sum), _pct(s, 50), mx])
		print("各块明细(ms): ", _fmt(s))
	print("====================")


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	return float(a[int(clampf(p / 100.0 * a.size(), 0, a.size() - 1))])


func _fmt(a: Array) -> String:
	var o: Array = []
	for v in a:
		o.append("%.0f" % float(v))
	return " ".join(o)
