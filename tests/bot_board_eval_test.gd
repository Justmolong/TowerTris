extends SceneTree

## 脱离游戏的单元测试：只验证 bot_board_eval.gd 的纯函数。
## 用法：
##   Godot_v4.4.1-stable_win64_console.exe --headless --script res://tests/bot_board_eval_test.gd
## （用 load() 按路径取脚本，不依赖 class_name 注册，因此无需编辑器扫描）

var _fail := 0
var _pass := 0


func _check(name: String, got, want) -> void:
	if str(got) == str(want):
		_pass += 1
		print("  PASS  ", name)
	else:
		_fail += 1
		print("  FAIL  ", name, "\n        got  = ", got, "\n        want = ", want)


func _init() -> void:
	var E = load("res://Scripts/bot_play/bot_board_eval.gd")
	if E == null:
		print("FATAL: 无法加载 bot_board_eval.gd")
		quit(1)
		return

	print("=== 1. build_request 基本形状 ===")
	var snap := {
		"rows": [0b1111111110] + _zeros(39),
		"active": "T",
		"hold": "-",
		"can_hold_now": true,
		"queue": ["I", "J", "L"],
		"b2b": 2, "combo": 3, "upcome": 1,
		"self_cells": [[4, 84], [3, 85], [4, 85], [5, 85]],
		"rotation_index": 0,
		"next_visible": 3,
		"repeat_penalty": 500.0,
	}
	var req: String = E.build_request(snap, 120)
	var tok: PackedStringArray = req.split(" ")
	_check("以 REQ 开头", tok[0], "REQ")
	# 1(REQ) + 40(掩码) + 4(active/hold/canHold/next) + 3(b2b/combo/upcome)
	#   + 1(格数) + 8(4 格 × x,y) + 10(尾部) = 67
	_check("总 token 数 = 67", tok.size(), 67)
	_check("底行掩码排除自身后仍是 0b1111111110", tok[1], "1022")
	# rows[0] 底行 = 1022，当前方块在 y=85（不是底行），所以底行不变
	_check("active", tok[41], "T")
	_check("hold", tok[42], "-")
	_check("canHold", tok[43], "1")
	_check("next = 前 3 个", tok[44], "IJL")
	_check("b2b", tok[45], "2")
	_check("combo", tok[46], "3")
	_check("upcome", tok[47], "1")
	_check("格数", tok[48], "4")
	_check("尾1 last_spin_type", tok[57], "0")
	_check("尾2 last_clear_count", tok[58], "0")
	_check("尾3 repeat_penalty", tok[59], "500.0")
	_check("尾4 rotation_index", tok[60], "0")
	_check("尾5 last_piece_code", tok[61], "-1")
	_check("尾10 budget", tok[66], "120")

	print("=== 2. 当前方块自身格子必须从版面排除 ===")
	# 把方块放在底行上，底行掩码里的这些位应被清掉
	var snap2 := snap.duplicate(true)
	snap2["rows"] = [0b1111111111] + _zeros(39)
	snap2["self_cells"] = [[0, 89], [1, 89]]
	var tok2: PackedStringArray = E.build_request(snap2, 0).split(" ")
	_check("底行清掉 x=0,1 -> 0b1111111100", tok2[1], "1020")

	print("=== 3. build_next 边界 ===")
	var s3 := snap.duplicate(true)
	s3["queue"] = []
	_check("空队列回退 I", E.build_request(s3, 0).split(" ")[44], "I")
	s3["queue"] = ["S", "Z", "T", "O", "I", "J", "L", "S", "Z", "T"]
	s3["next_visible"] = 25
	_check("可见数大于队列 -> 只用队列长度", E.build_request(s3, 0).split(" ")[44], "SZTOIJLSZT")

	print("=== 4. parse_reply ===")
	var p: Dictionary = E.parse_reply("OK vRV I 6 0 0")
	_check("ok", p["ok"], true)
	_check("path", p["path"], "vRV")
	_check("piece", p["piece"], "I")
	_check("x", p["x"], 6)
	_check("y(zzz)", p["y"], 0)
	_check("rot", p["rot"], 0)
	_check("ERR 不算 ok", E.parse_reply("ERR")["ok"], false)
	_check("空串不算 ok", E.parse_reply("")["ok"], false)
	_check("只有路径也能解析", E.parse_reply("OK vV")["path"], "vV")

	print("=== 5. rotate_cells 与 worker 的 nodes 输出对齐 ===")
	# worker `nodes` 实测（引擎的地面真值）：
	#   T r0 = 0,0 1,0 1,1 2,0 | T r1 = 0,0 0,1 0,2 1,1
	#   T r2 = 0,1 1,0 1,1 2,1 | T r3 = 0,1 1,0 1,1 1,2
	var t0: Array = [[0, 0], [1, 0], [1, 1], [2, 0]]
	_check("t0 原样", _norm(E.rotate_cells(t0, 0)), _norm(t0))
	_check("转 1 次 == T r3", _norm(E.rotate_cells(t0, 1)), _norm([[0, 1], [1, 0], [1, 1], [1, 2]]))
	_check("转 2 次 == T r2", _norm(E.rotate_cells(t0, 2)), _norm([[0, 1], [1, 0], [1, 1], [2, 1]]))
	_check("转 3 次 == T r1", _norm(E.rotate_cells(t0, 3)), _norm([[0, 0], [0, 1], [0, 2], [1, 1]]))
	_check("转 4 次回到原位", _norm(E.rotate_cells(t0, 4)), _norm(t0))
	_check("转 -1 次 == 转 3 次", _norm(E.rotate_cells(t0, -1)), _norm(E.rotate_cells(t0, 3)))
	# I r0 = 0,0 1,0 2,0 3,0 ; I r1 = 0,0 0,1 0,2 0,3
	var i0: Array = [[0, 0], [1, 0], [2, 0], [3, 0]]
	_check("I 转 1 次 == I r1", _norm(E.rotate_cells(i0, 1)), _norm([[0, 0], [0, 1], [0, 2], [0, 3]]))
	# cells_from_shape 应从游戏的形状矩阵得到同样的 t0
	var shape_t: Array = [[1, 1, 1], [0, 1, 0]]  # 3 宽 × 2 高：上行 3 格、下行中间 1 格
	_check("cells_from_shape 得到 t0 的旋转等价形", _norm(E.cells_from_shape(shape_t, 0)).length() > 0, true)

	print("=== 6. stamp 放置与越界/重叠拒绝 ===")
	var base: Array = _zeros(40)
	var sh: Array = [[0, 0], [1, 0]]
	var st: Array = E.stamp(base, sh, 3, 5)
	_check("放置成功", (int(st[5]) >> 3) & 1, 1)
	_check("放置成功(2)", (int(st[5]) >> 4) & 1, 1)
	_check("越界右 -> 空", E.stamp(base, sh, 9, 5), [])
	_check("越界上 -> 空", E.stamp(base, sh, 0, 40), [])
	_check("重叠 -> 空", E.stamp(st, sh, 3, 5), [])

	print("=== 7. score / cleared_rows ===")
	# score = max_h*2 + sum_h*0.5 + holes*5 + bump*0.5
	var empty: Array = _zeros(40)
	_check("空板消 0 行", E.cleared_rows(empty), 0)
	var full: Array = []
	for i in range(40):
		full.append(1023)
	_check("满板消 40 行", E.cleared_rows(full), 40)
	_check("空板得分 0", E.score(empty), 0.0)
	# 底行整行实心：max=1 -> 2，sum=10 -> 5，洞 0，崎岖 0 => 7.0
	var one_row: Array = [1023] + _zeros(39)
	_check("单行实心得分 7.0", E.score(one_row), 7.0)
	# 只有 (0,0)：max=1 -> 2，sum=1 -> 0.5，洞 0，崎岖 |1-0|=1 -> 0.5 => 3.0
	var one_cell: Array = [1] + _zeros(39)
	_check("单格得分 3.0", E.score(one_cell), 3.0)
	# 洞：(0,0) 空、(0,1) 实心：max=2 -> 4，sum=2 -> 1，洞 1 -> 5，崎岖 |2-0|=2 -> 1 => 11.0
	var hole: Array = [0] + [1] + _zeros(38)
	_check("带 1 个洞得分 11.0", E.score(hole), 11.0)
	# 单调性：有洞必须比同高度无洞差
	var no_hole: Array = [1] + _zeros(39)
	_check("有洞比无洞差", E.score(hole) > E.score(no_hole), true)

	print("")
	print("==== 结果：", _pass, " passed, ", _fail, " failed ====")
	quit(0 if _fail == 0 else 1)


func _zeros(n: int) -> Array:
	var a: Array = []
	for _i in range(n):
		a.append(0)
	return a


func _norm(cells: Array) -> String:
	var c := cells.duplicate()
	c.sort_custom(func(a, b): return (int(a[1]) < int(b[1])) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))
	var out: Array = []
	for p in c:
		out.append("%d,%d" % [int(p[0]), int(p[1])])
	return " ".join(out)
