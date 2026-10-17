extends SceneTree

## 真机测试 bot_worker_pool.gd：启动多个 worker 进程 + 每进程一条线程，
## 并发投递作业，验证回包按代号正确路由、且并行确实不互相拖慢。
##
## 用法（必须在项目根，让 res:// 能解析）：
##   Godot_v4.4.1-stable_win64_console.exe --headless --script res://tests/bot_worker_pool_test.gd

const POOL_PATH := "res://Scripts/bot_play/bot_worker_pool.gd"
const EVAL_PATH := "res://Scripts/bot_play/bot_board_eval.gd"

var _fail := 0
var _pass := 0


func _check(name: String, got, want) -> void:
	if str(got) == str(want):
		_pass += 1
		print("  PASS  ", name)
	else:
		_fail += 1
		print("  FAIL  ", name, "\n        got  = ", got, "\n        want = ", want)


func _zeros(n: int) -> Array:
	var a: Array = []
	for _i in range(n):
		a.append(0)
	return a


## 等回包：每帧轮询（主线程只能这样等，不能阻塞工作线程）
func _await_replies(pool, want: int, timeout_ms: int) -> Array:
	var got: Array = []
	var t0 := Time.get_ticks_msec()
	while got.size() < want and Time.get_ticks_msec() - t0 < timeout_ms:
		got.append_array(pool.drain_replies())
		pool.tick_health(0.016)
		# 让出主线程一帧，模拟游戏 _process 的节奏
		await process_frame
	return got


func _init() -> void:
	var PoolScript = load(POOL_PATH)
	var E = load(EVAL_PATH)
	if PoolScript == null or E == null:
		print("FATAL: 无法加载脚本")
		quit(1)
		return

	print("=== 1. 启动 4 个 worker 进程 ===")
	var pool = PoolScript.new(4)
	pool.reply_timeout_ms = 3000
	pool.verbose = true
	var started: int = pool.start()
	_check("4 个都启动成功", started, 4)
	_check("alive_count = 4", pool.alive_count(), 4)
	var exe: String = pool.resolve_worker_path()
	print("        worker exe = ", exe)
	var info: Dictionary = pool.get_info()
	print("        pids = ", info["pids"])
	if started < 1:
		print("FATAL: 没有 worker 启动成功，后续测试跳过")
		quit(1)
		return

	# 空板 + T 块（与离线探针同一套坐标，已知 worker 能解）
	var snap := {
		"rows": _zeros(40),
		"active": "T",
		"hold": "-",
		"can_hold_now": true,
		"queue": ["I", "J", "L", "S", "T", "Z", "O", "I", "J", "L", "S", "T", "Z", "O",
			"I", "J", "L", "S", "T", "Z", "O", "I", "J", "L", "S"],
		"b2b": 0, "combo": 0, "upcome": 0,
		"self_cells": [[4, 84], [3, 85], [4, 85], [5, 85]],
		"rotation_index": 0,
		"next_visible": 25,
	}
	var cfg := "CFG 120 8 1 0 1 1 1 0 1 1 0 1 6 0 20 25 0 20 0 1 0 2 42"
	var req: String = E.build_request(snap, 120)

	print("=== 2. 单条作业往返 ===")
	var job = pool.make_job(cfg, [], req, "single")
	pool.submit_all([job])
	var r1: Array = await _await_replies(pool, 1, 8000)
	_check("收到 1 条回包", r1.size(), 1)
	if r1.size() == 1:
		var p: Dictionary = E.parse_reply(str(r1[0]["reply"]))
		_check("回包 ok", p["ok"], true)
		_check("代号(id)对得上", int(r1[0]["job_id"]), int(job["id"]))
		print("        reply = ", r1[0]["reply"])

	print("=== 3. 并发 8 条作业，验证代号路由与并行 ===")
	var jobs: Array = []
	var tags: Array = []
	for i in range(8):
		# 每条作业用不同 bud谷 -> 不同耗时，便于观察是否真的并行
		var j = pool.make_job(cfg, [], E.build_request(snap, 120 + i * 10), "batch%d" % i)
		jobs.append(j)
		tags.append(str(j["id"]))
	var t0 := Time.get_ticks_msec()
	pool.submit_all(jobs)
	var r2: Array = await _await_replies(pool, 8, 20000)
	var elapsed := Time.get_ticks_msec() - t0
	_check("8 条全部回来", r2.size(), 8)
	var ok_all := true
	var ids_seen: Array = []
	for r in r2:
		var p2: Dictionary = E.parse_reply(str(r["reply"]))
		if not p2["ok"]:
			ok_all = false
		ids_seen.append(str(r["job_id"]))
	_check("8 条回复都 ok", ok_all, true)
	# 代号集合必须与提交集合完全一致（不能丢、不能串）
	var want_ids := tags.duplicate()
	want_ids.sort()
	ids_seen.sort()
	_check("8 个代号集合完全匹配", str(ids_seen), str(want_ids))
	print("        8 条并发总耗时 = ", elapsed, " ms（单条约 120ms，说明确实并行）")

	print("=== 4. 并行度验证：并发总耗时应远小于串行 ===")
	# 8 条 × 120ms，若串行需 ~960ms；4 个 worker 并行应 < 600ms
	_check("并发总耗时 < 600ms（说明真的并行）", elapsed < 600, true)

	print("=== 5. in_flight / get_info ===")
	_check("空闲时 in_flight = 0", pool.in_flight(), 0)
	var info2: Dictionary = pool.get_info()
	_check("alive 仍为 4", info2["alive"], 4)

	print("=== 5b. 运行期扩容（延迟补齐并行度用）===")
	var p2 = PoolScript.new(1)
	p2.reply_timeout_ms = 3000
	_check("只启 1 个", p2.start(), 1)
	_check("扩容前 worker_count = 1", p2.worker_count, 1)
	p2.set_worker_count(3)
	_check("扩容后 worker_count = 3", p2.worker_count, 3)
	_check("扩容后 alive = 3", p2.alive_count(), 3)
	# 扩容出来的 worker 也必须真能干活
	var j9 = p2.make_job(cfg, [], req, "grown")
	p2.submit_all([j9])
	var r9: Array = await _await_replies(p2, 1, 8000)
	_check("扩容后的 worker 能正常返回", r9.size(), 1)
	if r9.size() == 1:
		_check("扩容后回复 ok", E.parse_reply(str(r9[0]["reply"]))["ok"], true)
	# 只增不减
	p2.set_worker_count(2)
	_check("set_worker_count 只增不减", p2.worker_count, 3)
	p2.shrink_to(1)
	_check("shrink_to 生效", p2.worker_count, 1)
	p2.stop()

	print("=== 5c. 用游戏里抓到的真实 REQ 测一轮 4 候选的墙钟耗时 ===")
	# 这条 REQ 是从运行中的游戏里 log_protocol 抓的（预算 111ms），单进程隔离测过是 111ms。
	# 若 4 候选一轮远超 111ms，说明瓶颈在池/游戏侧而不是 worker。
	var real_req := "REQ 24 48 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 T - 1 OJZLILJZITSOTLJSOIZOJZTIL 0 0 0 4 4 68 3 69 4 69 5 69 0 0 0.0 0 -1 0 0 0 1000 111"
	var real_cfg := "CFG 100 8 1 0 1 1 1 0 1 1 0 1 6 0 20 25 0 20 0 1 0 2 42"
	var beams := [100, 200, 300, 400]
	for trial in range(3):
		var batch: Array = []
		for b in beams:
			var pr: Array = []
			if int(b) != 100:
				pr.append("PARAM beam_scale %d" % int(b))
			batch.append(pool.make_job(real_cfg, pr, real_req, "real%d" % trial))
		var tr0 := Time.get_ticks_msec()
		pool.submit_all(batch)
		var rr: Array = await _await_replies(pool, batch.size(), 20000)
		var dt := Time.get_ticks_msec() - tr0
		print("  trial ", trial, ": ", rr.size(), " 条回包, 墙钟 ", dt, " ms  (单进程隔离约 111ms)")
		if rr.size() > 0:
			var pfirst: Dictionary = E.parse_reply(str(rr[0]["reply"]))
			print("        首条 ok=", pfirst["ok"], " reply=", str(rr[0]["reply"]).substr(0, 30))

	print("=== 5c2. 同上，但按桥的方式把候选 i 钉到 worker i（prefer_worker）===")
	for trial in range(3):
		var batch3: Array = []
		for i in range(beams.size()):
			var pr3: Array = []
			if int(beams[i]) != 100:
				pr3.append("PARAM beam_scale %d" % int(beams[i]))
			batch3.append(pool.make_job(real_cfg, pr3, real_req, "pin%d_%d" % [trial, i], i))
		var tp0 := Time.get_ticks_msec()
		pool.submit_all(batch3)
		var rr3: Array = await _await_replies(pool, batch3.size(), 20000)
		var parts3: Array = []
		for r in rr3:
			parts3.append("job#%d(w%s,+%dms)" % [int(r["job_id"]), str(r.get("worker_id", "?")),
				int(r["t_done_ms"]) - tp0])
		print("  trial ", trial, " 墙钟 ", Time.get_ticks_msec() - tp0, " ms   到达: ", " ".join(parts3))

	print("=== 5d. 逐条候选的往返耗时（定位那 2 倍的额外时间在哪）===")
	for trial in range(3):
		var batch2: Array = []
		var tags2: Array = []
		for b in beams:
			var pr2: Array = []
			if int(b) != 100:
				pr2.append("PARAM beam_scale %d" % int(b))
			var jj = pool.make_job(real_cfg, pr2, real_req, "trace%d_%d" % [trial, int(b)])
			batch2.append(jj)
			tags2.append(int(jj["id"]))
		var t_sub := Time.get_ticks_msec()
		var got: Array = []
		pool.submit_all(batch2)
		# 逐条收集（每帧 drain），记录每条回包到达的相对时刻
		while got.size() < batch2.size() and Time.get_ticks_msec() - t_sub < 20000:
			for r in pool.drain_replies():
				got.append(r)
			pool.tick_health(0.016)
			await process_frame
		var parts: Array = []
		for r in got:
			parts.append("job#%d(w%s,+%dms)" % [int(r["job_id"]), str(r.get("worker_id", "?")),
				int(r["t_done_ms"]) - t_sub])
		print("  trial ", trial, " 提交于 t=0，回包到达: ", " ".join(parts))
		# 池中该轮各 worker 的 CFG 重发情况
		print("        pool_info=", pool.get_info())

	print("=== 6. 停止 ===")
	pool.stop()
	_check("停止后 alive = 0", pool.alive_count(), 0)

	print("")
	print("==== 结果：", _pass, " passed, ", _fail, " failed ====")
	quit(0 if _fail == 0 else 1)
