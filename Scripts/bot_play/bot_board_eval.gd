extends RefCounted
class_name BotBoardEval

## 纯函数工具：局面快照 → zzz 行协议请求，以及落点模拟与版面打分。
##
## 为什么单独拆出来：
##   1. **线程安全**。多 worker 并行时，请求字符串必须在主线程用快照拼好，
##      后台线程只允许碰字符串和管道，绝不能读 TetrisGlobalData / 场景树。
##      这里全部是"输入快照 → 输出字符串"的纯函数，可以安全地在任何线程调用。
##   2. **可独立测试**。不依赖任何节点、自动加载或引擎 API（只用 String/Array/Dictionary 数学），
##      所以能脱离游戏进程单独跑单元测试。
##
## 快照（snapshot）是普通 Dictionary，字段与 zzz REQ 一一对应：
##   rows           : Array[int]  40 行位掩码，index 0 = 本游戏底行 y=89（**不含**当前活动方块）
##   active         : String      当前方块类型（I/J/L/S/T/Z/O）
##   hold           : String      暂存块类型，无则 "-"
##   can_hold_now   : bool        当前是否还能暂存
##   queue          : Array       后续块类型序列（字符串）
##   b2b            : int
##   combo          : int
##   upcome         : int         预告垃圾行数
##   self_cells     : Array       [[x, y], ...] 当前方块的格子（本游戏坐标，y 向下）
##   rotation_index : int         本游戏 current_rotation_index（0..3）
##   last_spin_type : int         None=0 / TSpin=1 / AllSpin=2 / TSpinMini=3 / ASpinMini=4 / -1=无记录
##   last_clear_count : int
##   repeat_penalty : float       重复性惩罚扣分（正数 = 扣分）
##   last_piece_code : int        Z/S/T/I/J/L → 0..5，其它 -1
##   round_types_mask / round_counts_mask / round_counts03_mask : int
##   pressure_mult_code : int     extra_pressure_mult × 1000
##   next_visible   : int         bot 可见 next 数（= 搜索深度上限）

const GAME_WIDTH := 10
const GAME_BOTTOM_Y := 89
const MAX_ROWS := 40
## 版面打分的洞惩罚权重（一个洞比一行高度严重得多，取经验值）
const HOLE_WEIGHT := 5.0
## 崎岖度权重
const BUMP_WEIGHT := 0.5


## ============================ REQ 构造 ============================

## 由快照拼出完整的 REQ 行（不含换行）。
## budget_ms <= 0 时尾部下发 0，worker 会沿用 CFG 的 think。
static func build_request(snap: Dictionary, budget_ms: int) -> String:
	var rows: Array = snap.get("rows", [])
	var self_cells: Dictionary = {}
	for c in snap.get("self_cells", []):
		self_cells[Vector2i(int(c[0]), int(c[1]))] = true

	var parts: Array = ["REQ"]
	for h in range(MAX_ROWS):
		var gy: int = GAME_BOTTOM_Y - h
		var mask: int = 0
		if gy >= 0 and h < rows.size():
			mask = int(rows[h])
		# 当前方块自身的格子要从版面里排除（REQ 的 rows 语义：只描述已锁定的堆叠）
		if gy >= 0 and not self_cells.is_empty():
			for x in range(GAME_WIDTH):
				if self_cells.has(Vector2i(x, gy)):
					mask &= ~(1 << x)
		parts.append(str(mask))

	var active: String = str(snap.get("active", "I"))
	if active.is_empty():
		active = "I"
	var hold: String = str(snap.get("hold", "-"))
	if hold.is_empty():
		hold = "-"
	parts.append(active)
	parts.append(hold)
	parts.append("1" if bool(snap.get("can_hold_now", true)) else "0")
	parts.append(_build_next(snap))

	parts.append(str(int(snap.get("b2b", 0))))
	parts.append(str(int(snap.get("combo", 0))))
	parts.append(str(int(snap.get("upcome", 0))))
	var cells: Array = snap.get("self_cells", [])
	parts.append(str(cells.size()))
	for c in cells:
		parts.append(str(int(c[0])))
		parts.append(str(int(c[1])))

	# ---- 尾部 10 项（顺序必须与 zzztoj_worker.handle_request 的解析一一对应）----
	parts.append(str(int(snap.get("last_spin_type", 0))))                    # 1
	parts.append(str(int(snap.get("last_clear_count", 0))))                  # 2
	parts.append(str(float(snap.get("repeat_penalty", 0.0))))                # 3
	parts.append(str(int(snap.get("rotation_index", 0))))                    # 4
	parts.append(str(int(snap.get("last_piece_code", -1))))                  # 5
	parts.append(str(int(snap.get("round_types_mask", 0))))                  # 6
	parts.append(str(int(snap.get("round_counts_mask", 0))))                 # 7
	parts.append(str(int(snap.get("round_counts03_mask", 0))))               # 8
	parts.append(str(int(snap.get("pressure_mult_code", 1000))))             # 9
	parts.append(str(max(0, budget_ms)))                                     # 10
	return " ".join(parts)


static func _build_next(snap: Dictionary) -> String:
	var vis: int = int(snap.get("next_visible", 0))
	var q: Array = snap.get("queue", [])
	var out := ""
	var n: int = min(vis, q.size())
	for i in range(n):
		var t := str(q[i])
		if not t.is_empty():
			out += t.substr(0, 1)
	return out if not out.is_empty() else "I"


## ============================ 回复解析 ============================

## 解析一行回复 → {ok, path, piece, x, y(zzz, y 向上), rot}
## 与 zzz_bridge._parse_reply 的落点口径一致：x = 最左列，y = 最低行（zzz 坐标）。
static func parse_reply(reply: String) -> Dictionary:
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


## ============================ 落点模拟与打分 ============================

## 把方块按 (piece, x, y, rot) 盖到 rows 上，返回新的 rows；放不下返回空数组。
## 坐标系：rows 与 y 都用 zzz 口径（index 0 = 底行，y 向上）。
static func stamp(rows: Array, shape: Array, piece_x: int, piece_y: int) -> Array:
	var out: Array = []
	for r in rows:
		out.append(int(r))
	for c in shape:
		var x: int = piece_x + int(c[0])
		var y: int = piece_y + int(c[1])
		if x < 0 or x >= GAME_WIDTH or y < 0 or y >= MAX_ROWS:
			return []
		if (int(out[y]) >> x) & 1:
			return []
		out[y] = int(out[y]) | (1 << x)
	return out


## 把「形状相对坐标」按顺时针旋转 rot 次（与游戏 _get_rotated_matrix 同向）。
static func rotate_cells(cells: Array, times: int) -> Array:
	var cur := cells.duplicate()
	var t: int = ((times % 4) + 4) % 4
	for _i in range(t):
		var nxt: Array = []
		# (x, y) 顺时针 → (maxY - y, x)；用相对最小角归一化，避免负坐标
		var max_y := 0
		for c in cur:
			max_y = maxi(max_y, int(c[1]))
		for c in cur:
			nxt.append([max_y - int(c[1]), int(c[0])])
		# 归一化回最小角 = (0,0)
		var min_x := 1 << 30
		var min_y := 1 << 30
		for c in nxt:
			min_x = mini(min_x, int(c[0]))
			min_y = mini(min_y, int(c[1]))
		for c in nxt:
			c[0] = int(c[0]) - min_x
			c[1] = int(c[1]) - min_y
		cur = nxt
	return cur


## 由「原始形状矩阵」（Array[Array[int]]，游戏 piece_shape 口径）与旋转次数得到相对格子。
static func cells_from_shape(shape: Array, rot_times: int) -> Array:
	var cells: Array = []
	for y in range(shape.size()):
		var row: Array = shape[y]
		for x in range(row.size()):
			if int(row[x]) == 1:
				cells.append([x, y])
	if cells.is_empty():
		return []
	return rotate_cells(cells, rot_times)


## 版面打分：**越小越好**。高度是主要项，洞（被盖住的空格）重罚，崎岖度轻罚。
## 这是独立的"裁判"，不依赖 zzz 自己的评估函数——用于在多个并行候选里选优。
static func score(rows: Array) -> float:
	var heights: Array = []
	var holes := 0
	for x in range(GAME_WIDTH):
		var top := -1
		for y in range(MAX_ROWS - 1, -1, -1):
			if (int(rows[y]) >> x) & 1:
				top = y
				break
		heights.append(top + 1)
		if top >= 0:
			for y in range(top):
				if not ((int(rows[y]) >> x) & 1):
					holes += 1
	var max_h := 0
	var sum_h := 0
	for h in heights:
		max_h = maxi(max_h, int(h))
		sum_h += int(h)
	var bump := 0
	for x in range(GAME_WIDTH - 1):
		bump += absi(int(heights[x]) - int(heights[x + 1]))
	return float(max_h) * 2.0 + float(sum_h) * 0.5 + float(holes) * HOLE_WEIGHT + float(bump) * BUMP_WEIGHT


## 统计消行数（用于把"能消行"作为选优的加分项）。
static func cleared_rows(rows: Array) -> int:
	var n := 0
	var full := (1 << GAME_WIDTH) - 1
	for y in range(MAX_ROWS):
		if (int(rows[y]) & full) == full:
			n += 1
	return n
