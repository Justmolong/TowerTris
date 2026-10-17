extends Node
class_name TetrisController

## 俄罗斯方块控制器
## 负责方块移动、碰撞检测、触底锁定等逻辑
## 需要其它节点时一律通过公共数据区 TetrisGlobalData 取用（见 tetris_global_data.gd）。

# @export var replay_record: ReplayRecord
# @export var replay_player: ReplayPlayer

var _game_started_emitted: bool = false
# var _replay_seed_override: int = 0

# 方块配置
var current_color: Color = Color.WHITE  # 当前方块颜色
var current_original_shape: Array = []  # 当前方块的原始形状（用于Hold）
## 最近一次锁定的方块类型：消行时写进 TetrisClearLine 的「上次消行方块类型」，供 Allspin 重复惩罚预警比对
## 手上方块是否会触发 Allspin_1 重复惩罚（1=会，则 next/手上用「原本颜色+灰色」显示）。
## 由 TetrisClearLine.is_allspin_penalty_piece() 判定，每次重绘手上方块时刷新。
var current_piece_penalty: bool = false

# 暂存系统
var hold_piece: Array = []         # 暂存的方块矩阵
var hold_color: Color = Color.WHITE  # 暂存的方块颜色
var hold_original_shape: Array = []  # 暂存方块的原始形状（用于Hold）
# NoHold 模式：读写公共数据区的公共开关（TetrisGlobalData.no_hold），不再各存一份

# 运动延迟系统
var move_das: float = 0.1
var move_arr: float = 0
var softdrop_delay: float = 0.02

var keep_press_move: bool = false
var direction_press: int = 0
var double_press: bool = false

var move_start_timer: Timer
var move_keep_timer: Timer
var softdrop_timer: Timer

var press_key: Dictionary = {
	"LeftMove" : 0,
	"RightMove" : 0,
	"SoftDrop" : 0,
	"HardDrop" : 0,
	"LeftSpin" : 0,
	"RightSpin" : 0,
	"SwapSpin" : 0,
	"HoldBlock" : 0
}

var check_for_single_press: Dictionary = {
	"HardDrop" : 0,
	"SoftDrop" : 0,
	"LeftSpin" : 0,
	"RightSpin" : 0,
	"SwapSpin" : 0,
	"HoldBlock" : 0
}

# 触底锁定计时
var lock_timer: Timer
var lock_times_limit_max: int = 10
var lock_times_limit: int = 0
var lock_delay: float = 1  # 触底后锁定延迟（秒）

#重力下落
var gravity_drop_time: float = 5
var gravity_timer: Timer

# 方块锁定后通往下一块的最小间隔（秒）：buff「落块延迟」经 tower_controller 的 BlockDelay 键设置。
# 计时从「锁定」时刻起算（set_spawn_delay 只存值，实际结算见 _try_spawn_after_delays）。
# 0 表示锁定后立刻出下一块；与消行延迟同时存在时取两者较长者。
var spawn_delay_time: float = 0
var spawn_delay_timer: Timer
# 已锁定但下一块还没出现的窗口（防止两个计时器都到点时出块两次）
var locked: bool = false
# 最近一次锁定的时间戳（毫秒，落块延迟以它为基准）
var lock_time_ms: int = 0
# 本次锁定是否消了行（由 TetrisClearLine 记录）→ 出块时用它决定 clutch
var _last_clear_did_clear: bool = false

# ========== 统计系统 ==========
# 全局计时

# 回放输入覆盖模式：开启后，按键状态由 replay_player 直接驱动，而不是实时读取 Input（已注释 - 回放系统禁用）
# var replay_input_override: bool = false
var game_timer: Timer               # 游戏计时器

# PPS (Pieces Per Second)
var total_pieces: int = 0           # 总放置方块数
var pps_value: float = 0.0          # 每秒方块数

# APM (Attack Per Minute)
var total_attacks: int = 0          # 总攻击数（造成的伤害总量）
var apm_value: float = 0.0          # 每分钟攻击数

## 全局指标（整局累计平均）—— 游戏内左侧 PPS / APM 文本显示的就是上面这两个值，
## 口径是「累计总量 ÷ 游戏时长」，会随整局时间缓慢平滑，不要改成窗口值：
##   pps_value = total_pieces / game_time
##   apm_value = total_attacks / game_time × 60

## 短期指标（最近 60s 滚动窗口）—— 与上面的全局 pps/apm 相互独立，只给 RPM 行与左侧速条用：
##   rpm_value        每分钟【接收】攻击数（RPM 行）
##   ppm_value        每分钟落块数（速条：蓝色）
##   apm_window_value 每分钟【打出】攻击数（速条：橙色）
var rpm_value: float = 0.0          # 每分钟接收攻击数（仅最近1分钟）
var ppm_value: float = 0.0          # 每分钟落块数（仅最近1分钟）
var apm_window_value: float = 0.0   # 每分钟打出攻击数（仅最近1分钟）

## 存储 {time: 游戏时间秒数, damage: 伤害量} 事件，用于滑动窗口统计最近60秒的 RPM
var _rpm_events: Array[Dictionary] = []
## 落块事件 {time, count}，用于 PPM 滚动窗口
var _ppm_events: Array[Dictionary] = []
## 打出攻击事件 {time, damage}，用于短期 APM 滚动窗口
var _apm_events: Array[Dictionary] = []
const RPM_WINDOW_SECONDS: float = 60.0  # 滚动窗口大小（秒），RPM / PPM / 短期 APM 共用

# 上次更新统计的时间
var last_stats_update_time: float = 0.0

# 上次统计更新时的引擎时间戳（毫秒）。game_time 按「真实经过时间」累计，
# 不再用固定 +0.1（Timer 抖动/掉帧会让固定步进与实际时间产生累积漂移）。
var _last_stats_ticks: int = 0

# ---- 游戏时钟（秒）：只累计「游戏内真正流逝」的时间 ----
# _process 收到的 delta 已含 Engine.time_scale；快速模拟等决策期间把缩放压到近乎 0，
# 于是这段等待**一点游戏时间都不算**，bot 的 pps 才能保持与正常对局一致（否则 20 倍速下
# 一次 107ms 的决策会吃掉 2.1 秒游戏时间，每块 2.1s → PPS 掉到 0.5）。
# 统计/落块延迟/bot 节奏归属全部改用这个时钟，不再用「真实时间戳 × 缩放倍数」估算。
var _game_clock: float = 0.0
var _stats_accum: float = 0.0      # 距上次 _update_stats() 累计的游戏时间

# 单次统计间隔的累计上限（秒）：窗口拖动/系统卡顿造成的超长间隔不计入游戏时长，
# 否则会把「没在操作」的时间也算进 APM / PPS 的分母。
const STATS_MAX_DELTA: float = 1.0

#结束数据
var max_combo: int = 0  # 最大连击数
var max_btb: int = 0    # 最大BTB数
var total_lines_cleared: int = 0  # 总消行数
var total_spins: int = 0  # 总Spin次数

# ========== Bot 参数（控制文件见下方注释） ==========
# ---------------------------------------------------------------------------
# 【bot 参数的来源/控制文件】
#  1) bot_mode 由关卡配置控制：配置里带 "BotMode":true 时，
#     TetrisGlobalData.apply_init_data() 会把 tetris_controller.bot_mode 置 true。
#     "BotMode" 键来自 buff_chose_area.gd 写入 TetrisGlobalData.tower_init_data 的 buff 配置。
#  2) 其余3个 @export 参数（bot_target_pps / bot_native_action_interval /
#     bot_debug_log）直接在 tetris_controller.gd 的 Inspector 里调整。
# ---------------------------------------------------------------------------
var bot_mode: bool = false
# 目标方块/秒（PPS）。控制 bot 落块的节奏上限：
#   每块最小间隔 = 1/bot_target_pps（_get_bot_piece_interval）
#   每步动作间隔 = 1/(bot_target_pps*4)（_get_bot_action_interval）
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_target_pps: float = 3.0

# ---------------------------------------------------------------------------
# bot 动态变速（可选）：以 bot_target_pps 为基准，按「版面高度 / 缓冲垃圾 / 本手是否消行」调整
#   ⚠ 总开关 bot_dynamic_pps = false 时，下面这些参数全部不生效，
#     bot 始终使用固定的 bot_target_pps（节奏与旧版一致）。
#   高度定义：版面上没有任何方块 = 0 行（只统计已锁定方块，不含当前活动方块）
#     高度 = bot_pps_height_ref（默认 5）时就是基础 pps（不增不减）
#     每高 1 行 → +bot_pps_height_step（默认 0.05）；每低 1 行 → −0.05
#   缓冲垃圾加成：只要有垃圾处于缓冲，且「版面高度 + 缓冲垃圾行数」> bot_pps_garbage_threshold
#     （默认 10），则每多出 1 高 → +bot_pps_garbage_step（默认 0.1）
#   堆叠侧（最后乘）：本手决策不消行 → ×bot_pps_noclear_mul（默认 1.1）
#                     本手决策消行   → ×bot_pps_clear_mul（默认 0.8）
#   下限 bot_pps_min，避免出现 0 或负速度（bot_target_pps <= 0 仍表示不限制）
# ---------------------------------------------------------------------------
## 动态变速总开关：true = 按高度/缓冲垃圾/消行调整 pps；false = 恒定使用 bot_target_pps
@export var bot_dynamic_pps: bool = true
## 每偏离参考高度 1 行调整的 pps
@export var bot_pps_height_step: float = 0.05
## 高度参考行数：等于它时使用基础 pps
@export var bot_pps_height_ref: int = 5
## 「版面高度 + 缓冲垃圾行数」超过该值后按垃圾加成提速
@export var bot_pps_garbage_threshold: int = 10
## 垃圾加成：超出阈值的每 1 高增加的 pps
@export var bot_pps_garbage_step: float = 0.05
## 本手不消行（堆叠）时 pps 的乘数
@export var bot_pps_noclear_mul: float = 1.1
## 本手消行时 pps 的乘数
@export var bot_pps_clear_mul: float = 0.7
## 动态 pps 下限
@export var bot_pps_min: float = 0.1

# bot 每步“原生动作”的最小间隔（秒）。越小执行越快，但过小可能因物理/程序竞争出问题。
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_native_action_interval: float = 0.005

# bot 调试日志开关（默认关闭，避免刷屏）。
# 打开后会打印：[BotSpawn] 出生位置、[BotPlan] 决策耗时/决策落点、[BotStep] 每步动作、
# [BotLock] 实际落点与决策落点对照、[BotLoop] 一次性参数、[BotIdle] 无方块空转，
# 以及 zzz worker 的启动日志。
# ⚠ 排查「bot 落点/节奏不对」时把它打开即可，正常游玩建议保持关闭。
# 在 tetris_controller.gd 的 Inspector 中调整（@export）。
@export var bot_debug_log: bool = false

# ---------------------------------------------------------------------------
# 【快速模拟】（buff「快速模拟」，必须与 Bot 模式同时开启）
#   做法就是「帧数换算」：把 Engine.time_scale 放大 fast_simulate_speed 倍。
#   每一帧照常跑一遍**完整逻辑**（出块/消行/垃圾/爬塔/统计全都照原样走），
#   只是这一帧被记作 fast_simulate_speed 帧的游戏时间 → bot 的全过程被原样跑完，
#   而不是另写一套简化模型；因此结果与正常游玩一致，只是快 N 倍出结果。
#   同时解除 vsync / 帧率上限，避免被垂直同步卡在 60fps（那会把上限压回 60 倍）。
#   ⚠ 真正的瓶颈是 zzz worker 的思考时间（实测每块约 107ms 真实），
#     所以 fast_simulate_speed 调到 30 以上真实收益会迅速饱和；
#     想再快只能调低 fast_simulate_think_budget（用棋力换速度）。
#   ⚠ 游戏时长一律用 _game_clock（累计的、含缩放的 delta）来算，
#     不要用「真实时间戳 × 缩放倍数」估算 —— 冻结等决策期间那个估算会把等待也算成游戏时间。
#   ⚠ 等 worker 决策期间**默认冻结游戏时钟**（fast_simulate_freeze_wait=true）：
#     等决策不计入游戏时间，每块游戏时长才回到 bot 自己的 pps 节奏（约 0.33~0.48s），
#     界面 PPS 才能保持与正常对局一致（约 3）。关掉它会退化成每块 2.1 秒游戏时间、PPS 掉到 0.5。
#   ⚠ bot 的落块节奏走「理想时刻网格」：基准是上一块的**理想**锁定时刻而不是实际时刻，
#     否则「实际总比理想晚半帧」的量化误差会逐块累积，每块变成 间隔+半帧，PPS 被稀释到 2.5。
#     配合冻结等待后，快速模拟的每块游戏时长与正常对局同量级（约 0.35s，实测差 3% 以内）。
#   ⚠ 动态变速（bot_dynamic_pps）在快速模拟下**照常生效**（所以 PPS 会随高度/消行在 2.6~2.9 浮动，
#     与正常对局一致，不强行贴 3.0）。想让 PPS 恒定贴住 bot_target_pps 才打开 fast_simulate_fixed_pps。
# ---------------------------------------------------------------------------
var fast_simulate: bool = false
@export var fast_simulate_speed: float = 20.0
## 等 worker 决策期间**是否冻结游戏时钟**（true = 把时间缩放压到 0.001，等决策不计入游戏时间）。
## ⚠ 默认已改为 **false：等决策期间游戏照常实时运行**，不再冻结。
##   true 的代价：等决策时整个画面（重力/消行动画/计时器）都停住，看上去就是"一顿"；
##   假期的停顿长度 = 决策耗时，所以 bot 越慢卡顿越明显。
##   false 的代价：等决策这段时间算进游戏时间，快速模拟下 PPS 会被稀释
##   （20 倍速下一次 100ms 决策 ≈ 2 秒游戏时间）；同时方块会在计划到手前继续受重力下落。
##   —— 控制器里有对应的保护：等决策期间 _process() 会跳过 gravity_drop()，方块不会掉。
@export var fast_simulate_freeze_wait: bool = false
## 冻结时使用的极小时间缩放（等价于暂停；不用 0 是为了避开引擎内部除零）
const DECISION_WAIT_TIME_SCALE: float = 0.001
## 快速模拟下 bot 把「本手计划的剩余动作」在**同一帧**内跑完（不走每帧一步的节奏等待）。
## 与逐步执行共用 _apply_bot_action()，所以落点、踢墙、消行、**spin 判定**
## （spin 看的是「最后一次旋转发生的位置」）都与正常对局一致 —— 快而不失真，默认开启。
@export var fast_simulate_whole_plan: bool = true
## 快速模拟下 bot 走「直接放置」＝按决策给的落点/朝向把方块瞬移到位后锁定，
## 不再执行「左移/右移/旋转/软降」。
## ⚠ 默认关闭：它会把旋转记录写在**落点**上，而正常对局写的是「最后一次旋转真正发生的位置」，
##   本作 spin 判定读的正是后者（四方向不可移动才判 Spin）→ 会造成 spin 误判（偏多：能平移/上抬的
##   位置在正常对局不判 Spin，瞬移放置却会判）。只在「位置精确优先、可容忍 spin 记录偏差」时开启。
##   瞬移本身比整段计划同帧执行只快约 6%（真正的瓶颈是 worker 思考时间），所以默认不用它。
## 思考预算（逐 REQ 下发到 bridge.think_budget_now）：预算 = 本块间隔 × ratio，夹在 [min, max] ms。
## ⚠ 现在默认**固定 100ms**（ratio=1.0 但被 max 夹住，且 min/max 都是 100）：
##   先前是 20~300ms 的动态预算，实测会让"等决策的停顿"在 107~180ms 之间浮动，
##   危险局面还会顶到 300ms → 每块节奏出现 300ms/450ms 的双峰，观感就是"一顿一顿"。
##   改回恒定 100ms 后停顿可预测，节奏才稳。
##   想恢复动态预算：把 ratio 调回 0.35、max 调回 300（min 保持 20）。
@export var bot_think_budget_ratio: float = 1.0
@export var bot_think_budget_min: int = 100
@export var bot_think_budget_max: int = 100

@export var fast_simulate_direct_place: bool = false## 快速模拟时把 zzz worker 的思考预算调低（0 = 不干预，沿用 zzz_bridge.think_budget）。
## ⚠ 这会改变 bot 的决策质量（思考越少越弱），所以默认 0；只在「只想尽快拿到结果」时打开。
## 实测：预算 100（当前默认）时每块决策约 107ms，是极速模拟真正的瓶颈（约 9 块/秒真实）。
@export var fast_simulate_think_budget: int = 0
## 快速模拟时是否改用固定 pps（忽略 bot_dynamic_pps 的高度/消行/垃圾变速）：
## 默认 **false = 保留动态变速**，与正常对局同一套节奏（此时 PPS 显示会随变速在 2.6~2.9 浮动，不贴 3.0）。
## 打开后忽略动态变速，界面 PPS 严格贴住 bot_target_pps（3.000）——只在需要「恒定 3pps 基准」时用。
@export var fast_simulate_fixed_pps: bool = false
var _fast_simulate_vsync_off: bool = false  # 记录是否是我们关掉的 vsync（退出时好还原）
var _fast_simulate_prev_max_fps: int = 0    # 加速前的帧率上限（退出时还原）

# --- 以下为 bot 内部状态（运行期维护，勿手改） ---
var _zzz_bridge: ZzzBridge = null
var _bot_piece_serial: int = 0
var _bot_tracking_piece_serial: int = -1
var _bot_tracking_board_version: int = 0
var _bot_next_action_time: float = 0.0
var _bot_piece_cooldown: float = 0.0
# 上一块锁定时刻（ms）。用于把「每块最小间隔」按**本手自己的 pps** 算在本手身上：
# 否则间隔是在 lock 时用「刚锁定那一手」的 pps armed 的，减速会落到下一块
# （实测表现就是"消行之后下一块才卡一下"）。
var _bot_last_lock_ms: float = 0.0
## 上一块锁定时的游戏时钟（秒）：bot 节奏归属用它算「本手已用掉多少游戏时间」
var _bot_last_lock_game: float = 0.0
## bot 落块节奏的「理想时刻网格」（游戏时钟，秒）：
##   _bot_lock_base_game   = 上一块理想的锁定时刻（不跟随实际锁定时刻，避免量化误差累积）
##   _bot_lock_target_game = 本手理想的锁定时刻（= base + 本手自己的 pps 间隔），-1 = 本手尚未定出
var _bot_lock_base_game: float = -1.0
var _bot_lock_target_game: float = -1.0
## 最近一次锁定的游戏时钟（秒）：落块延迟用它算已过时间
var _lock_game_time: float = 0.0
# 决策参数签名：旋转系统 / 垃圾上限 / BTB / PC / NoSpin / hold / 180 等。
# 关卡与 buff 可能在这些字段生效前 bot 就已经发出了第一份请求（实测：RotateSystem_3 关卡里
# 第一次 CFG 是 kick=0(ASC)，第二次才是 kick=3(NONE)）——那样这份计划是按旧参数搜出来的，
# 里面可能含游戏做不出的踢墙。这里检测到签名变化就把旧计划作废并重算。
var _bot_cfg_signature: String = ""
var _bot_cfg_stale: bool = false
# 落块自检用：计划确认那一刻的版面高度，以及到锁定前累计被垃圾抬高的行数。
# 垃圾上涨是「整版含当前方块一起上移」，所以实际落点 y 会比计划 y 小 _bot_check_rise。
var _bot_check_plan_height: int = -1
var _bot_check_rise: int = 0
# 动态 PPS 用：本手决策是否消行（由计划落点预测），以及已按哪个方块序号算过
var _bot_pps_plan_clears: bool = false
var _bot_pps_plan_serial: int = -1
# 版面高度缓存（随「方块序号 + board_version」失效）
var _bot_height_cache: int = -1
var _bot_height_cache_ver: int = -1
var _bot_height_cache_serial: int = -1

signal game_started()
signal game_ended()

# ==================================================================================
# ============================ 旋转系统开关（改这里即可切换） ============================
# ==================================================================================
## 旋转系统类型：
##   ASC = 0（默认，历史行为）：单张 21 组踢墙表对全部方块/全部转换生效，
##          逆时针由该表 X 取反镜像得到，180° 复用同一张表。
##   SRS = 1（标准 SRS）：JLSTZ 与 I 两套踢墙表，按「旋转前状态 → 旋转后状态」成对选取，
##          O 无踢墙（仅 (0,0)）；SRS 规范只定义 8 组 90° 转换，**180° 无官方踢墙表**，
##          本工程的 180° 采用自定义扩展 SRS_180_KICKS（原地 + 周围 8 格，
##          最多让开 1 格，含斜向；不再像以前借用 ASC 的 21 组候选那样一次跳 2 格穿墙）。
##   ARS = 2（Arika Rotation System，TGM1/TGM2 基准）：
##          踢墙只测三个位置，顺序为「默认位置 → 向右 1 格 → 向左 1 格」（优先向右，
##          俗称「三原的阴谋」）；**基础版 ARS 中 I 没有踢墙**，O 亦无；
##          ARS 没有 180° 旋转，本模式下 180° 只允许原地旋转（候选仅 (0,0)）。
##          参考：Arika Rotation System（Tetris Wiki / 俄罗斯方块中文维基）。
##          ⚠ 已知偏差：本游戏方块几何/入场朝向是 SRS 风格（矩阵旋转），
##          未实现 ARS 的「T/L/J 最长边朝上入场」「S/Z 竖向居中」「I 旋转中心偏右一格」
##          以及 J/L/T「居中阻挡」判定，仅实现了 ARS 的踢墙候选与顺序。
##   NONE = 3（无旋转系统，buff「旋转系统III」）：旋转本身正常，但没有任何踢墙——
##          只有「原地旋转」（偏移 (0,0)）成功时旋转才生效，任何需要被踢开一格才能
##          完成的旋转都会失败（方块朝向保持不变）。
enum RotationSystemType { ASC = 0, SRS = 1, ARS = 2, NONE = 3 }

## 当前使用的旋转系统。可在 Inspector 里直接切换，也可由关卡/Buff 的
## extra_data_dict["rotation_system"]（0/1/2/3 或 "ASC"/"SRS"/"ARS"/"NONE"）覆盖。

## 当前方块的旋转状态索引：0=初始(North) 1=顺时针90°(East) 2=180°(South) 3=逆时针90°(West)。
## 由 spawn / hold / 每次旋转成功时维护，用于 SRS 的 from→to 踢墙表选择。

# ========== 踢墙表配置 ==========
# 现代踢墙表（ASC）
var kick_table: Dictionary = {
	"all": [
		[0,0], [-1,0], [0,1], [-1,1], [0,2], [-1,2], [-2,0], [-2,1], [-2,2], [1,0], [1,1],
		[0,-1], [-1,-1], [-2,-1], [1,2], [2,0], [0,-2], [-1,-2], [-2,-2], [2,1], [2,2]
	]
}

# 返回游戏 asc 踢墙表（供 ColdClear bridge 传入 bot，使 bot 的踢墙与游戏一致）
func get_kick_table() -> Array:
	var all: Array = kick_table.get("all", [])
	return all

# ---------------------------------------------------------------------------------
# 标准 SRS 踢墙表（仅在 rotation_system == SRS 时使用）
# 数据为 SRS 规范值（规范以 y 轴向上给出），下表已把 dy 取反为游戏坐标系（y 轴向下）。
# 每行 = 一次「旋转前状态 → 旋转后状态」的 5 个候选（顺序即测试顺序，第 1 个恒为 (0,0)）。
# 状态编号：0=North(初始) 1=East(顺时针90°) 2=South(180°) 3=West(逆时针90°)
# ---------------------------------------------------------------------------------
const SRS_TRANSITION_KEYS: Array = [[0,1],[1,0],[1,2],[2,1],[2,3],[3,2],[3,0],[0,3]]

## SRS：J L S T Z（3x3 包围盒），每行 5 组 (dx,dy)
const SRS_JLSTZ_FLAT: Array = [
	[0,0, -1,0, -1,-1, 0,2, -1,2],   # 0→1
	[0,0,  1,0,  1,1,  0,-2, 1,-2],  # 1→0
	[0,0,  1,0,  1,1,  0,-2, 1,-2],  # 1→2
	[0,0, -1,0, -1,-1, 0,2, -1,2],   # 2→1
	[0,0,  1,0,  1,-1, 0,2,  1,2],   # 2→3
	[0,0, -1,0, -1,1,  0,-2, -1,-2], # 3→2
	[0,0, -1,0, -1,1,  0,-2, -1,-2], # 3→0
	[0,0,  1,0,  1,-1, 0,2,  1,2],   # 0→3
]

## SRS：I（4x4 包围盒），每行 5 组 (dx,dy)
const SRS_I_FLAT: Array = [
	[0,0, -2,0,  1,0, -2,1,  1,-2],  # 0→1
	[0,0,  2,0, -1,0,  2,-1, -1,2],  # 1→0
	[0,0, -1,0,  2,0, -1,-2, 2,1],   # 1→2
	[0,0,  1,0, -2,0,  1,2, -2,-1],  # 2→1
	[0,0,  2,0, -1,0,  2,-1, -1,2],  # 2→3
	[0,0, -2,0,  1,0, -2,1,  1,-2],  # 3→2
	[0,0,  1,0, -2,0,  1,2, -2,-1],  # 3→0
	[0,0, -1,0,  2,0, -1,-2, 2,1],   # 0→3
]

## SRS 表缓存（from*4+to → [[dx,dy],...]），避免每次旋转都重建数组
var _srs_kick_cache: Dictionary = {}

## SRS 模式的 180° 踢墙（SRS 规范只定义 90°，180 属扩展，本实现自定）：
##   只测试 9 个位置：原地 + 周围 8 格各让开 1 格（含斜向），一律只让开 1 格。
##   顺序：原地 → 上 → 下 → 左 → 右 → 左上 → 右下 → 右上 → 左下（y 轴向下，(0,-1) 即向上）。
##   为什么必须带斜向：S/Z 做 180° 时形状在包围盒内会平移 (1,1)，想在原地「视觉不变」地转过去
##   就得用 (-1,-1) 这类斜向让位；只给上下左右 4 个候选时，贴堆叠/贴墙处会整手 180° 失败，
##   于是旋转态与 bot 决策不一致（实测 SRS 下 2 次 180° 全部失败）。
##   SRS 自身 90° 表里也有 (±1,±1) 斜向项，故斜向让位与 SRS 风格一致。
##   相比原先借用 ASC 的 21 组候选（可跳 2 格、可穿墙），这里仍严格限制为「最多让开 1 格」。
##   J L S T Z 与 I 共用本表；O 的 180 是几何空操作，只留原地。
const SRS_180_KICKS: Array = [
	[0, 0], [0, -1], [0, 1], [-1, 0], [1, 0],
	[-1, -1], [1, 1], [1, -1], [-1, 1],
]

# ---------------------------------------------------------------------------------
# ARS（Arika Rotation System，TGM1/TGM2 基准）踢墙表
#   ARS 只测试三个位置，顺序固定为「默认 → 右 1 → 左 1」，优先向右踢（「三原的阴谋」）。
#   基础版 ARS 中 I 没有踢墙；O 也不用踢墙；ARS 本身没有 180° 旋转。
#   来源：Arika Rotation System（tetris.wiki / 俄罗斯方块中文维基）。
# ---------------------------------------------------------------------------------
const ARS_KICK_ORDER: Array = [[0, 0], [1, 0], [-1, 0]]
## ARS 下没有任何踢墙候选的方块（基础版 I 无踢墙）
const ARS_NO_KICK_PIECES: Array = ["I", "O"]
## 原地候选（O / 180° / 无踢墙方块用）
const KICK_NONE: Array = [[0, 0]]

## 由「旋转前状态 + 方向」推算「旋转后状态」索引（0..3）
func _calc_rotation_index(from_index: int, direction: int) -> int:
	var step: int = 2 if direction == 2 else (-1 if direction < 0 else 1)
	return ((from_index + step) % 4 + 4) % 4

## 取本次旋转使用的踢墙候选表：
##   ASC 模式：返回 ASC 单表（含 180）；逆时针由调用方按 X 取反镜像。
##   SRS 模式：按方块类型（JLSTZ / I / O）与 from→to 状态对选取 SRS 表；
##             180° 规范未定义，使用 SRS_180_KICKS（原地 + 周围 8 格，最多让开 1 格）。
##   ARS 模式：JLSTZ = 默认/右/左；I、O = 无踢墙；180° = 只允许原地旋转。
##   NONE 模式（无旋转系统）：旋转照常进行，但只有原地候选——不踢墙。
func get_kick_offsets_for(piece_type: String, from_index: int, to_index: int, direction: int) -> Array:
	# 无旋转系统：不做任何踢墙，只允许原地旋转（新朝向在当前位置放得下才成功）
	if TetrisGlobalData.piece_rotation_system == RotationSystemType.NONE:
		return KICK_NONE

	if TetrisGlobalData.piece_rotation_system == RotationSystemType.ARS:
		if direction == 2:
			return KICK_NONE                      # ARS 没有 180°：只允许原地转
		if ARS_NO_KICK_PIECES.has(piece_type):
			return KICK_NONE                      # 基础版 ARS：I 不踢墙
		return ARS_KICK_ORDER

	# ASC / 其它模式：单表通吃（180 也用同一张表，保持历史手感）
	if TetrisGlobalData.piece_rotation_system != RotationSystemType.SRS:
		return get_kick_table()

	# SRS 的 180°：规范无官方表，用本工程的 5 候选扩展（最多让开一格）
	if direction == 2:
		return KICK_NONE if piece_type == "O" else SRS_180_KICKS

	if piece_type == "O":
		return KICK_NONE

	var flat: Array = SRS_I_FLAT if piece_type == "I" else SRS_JLSTZ_FLAT
	var row: int = SRS_TRANSITION_KEYS.find([from_index, to_index])
	if row < 0:
		return get_kick_table()  # 兜底：状态对缺表时退回 ASC，避免旋转直接失效

	var cache_key: int = (1 if piece_type == "I" else 0) * 100 + row
	if _srs_kick_cache.has(cache_key):
		return _srs_kick_cache[cache_key]

	var values: Array = flat[row]
	var pairs: Array = []
	var i: int = 0
	while i + 1 < values.size():
		pairs.append([values[i], values[i + 1]])
		i += 2
	_srs_kick_cache[cache_key] = pairs
	return pairs

## 切换旋转系统（供关卡配置/调试调用）。
## 接受 0/1/2/3 或 "ASC"/"SRS"/"ARS"/"NONE"（大小写不敏感）。非法值保持原样不变。
func set_rotation_system(system) -> void:
	if system is String or system is StringName:
		match str(system).to_upper():
			"ASC": TetrisGlobalData.piece_rotation_system = RotationSystemType.ASC
			"SRS": TetrisGlobalData.piece_rotation_system = RotationSystemType.SRS
			"ARS": TetrisGlobalData.piece_rotation_system = RotationSystemType.ARS
			"NONE": TetrisGlobalData.piece_rotation_system = RotationSystemType.NONE
			_: push_warning("[旋转系统] 未知名称 \"%s\"，忽略（可用 ASC / SRS / ARS / NONE）" % str(system))
		return
	var value: int = int(system)
	if value < RotationSystemType.ASC or value > RotationSystemType.NONE:
		push_warning("[旋转系统] 未知编号 %d，忽略（0=ASC / 1=SRS / 2=ARS / 3=NONE）" % value)
		return
	TetrisGlobalData.piece_rotation_system = value

## 当前旋转系统名（日志/调试用）
func get_rotation_system_name() -> String:
	match TetrisGlobalData.piece_rotation_system:
		RotationSystemType.SRS: return "SRS"
		RotationSystemType.ARS: return "ARS"
		RotationSystemType.NONE: return "NONE"
		_: return "ASC"

func _enter_tree() -> void:
	# 自注册到公共数据区（整棵场景树的 _enter_tree 都先于任何 _ready 完成）
	TetrisGlobalData.register_node(self)

func _ready():
	_game_started_emitted = false
	# _replay_seed_override = 0
	
	# _prepare_replay_if_pending()  # 回放系统已禁用
	
	#初始化随机数管理器
	_initialize_random()
	
	_set_timer()
	
	_load_user_settings()
	
	# 初始化统计系统
	_init_stats()

	if bot_mode:
		_ensure_zzz_bridge()
		if bot_debug_log:
			pass  # 已注释：print("[ColdClearBridge] 使用原生ColdClear决策（rust cold_clear.dll）")
	
	# 版面内容被改写（关卡/Buff 的初始版面印刷）→ 走公共事件，由本节点自己重算方块位置与影子
	TetrisGlobalData.board_layout_changed.connect(refresh_after_board_change)
	# 落块 → 消行判定 → 出块 的主链路：本节点只负责「锁定后发通知」与「收到结果/请求后结算」
	#   1) 锁定后 emit piece_locked（消行控制器订阅；见 _lock_piece）
	#   2) 消行控制器判定完成 → lines_judged（本节点做统计/抵消/涨垃圾）
	#   3) 消行控制器请求出块 → spawn_requested（本节点统一结算出块时机）
	TetrisGlobalData.lines_judged.connect(_on_lines_judged)
	TetrisGlobalData.spawn_requested.connect(_on_spawn_requested)
	# 垃圾行控制器的事件：整版上移的前后处理（方块跟着上移）、收到攻击、请求结束本局
	TetrisGlobalData.board_shift_starting.connect(_on_board_shift_starting)
	TetrisGlobalData.board_shifted_up.connect(_on_board_shifted_up)
	TetrisGlobalData.garbage_attack_received.connect(record_received_damage)
	TetrisGlobalData.game_over_requested.connect(_on_game_over_requested)
	
	# 生成第一个方块
	spawn_new_piece()
	
	# 上报就绪：当场景内所有节点都就绪后，公共数据区会通知各节点读走自己的 buff 参数
	TetrisGlobalData.notify_node_ready(self)

## 读取公共区域里属于方块控制器的关卡 / buff 参数（谁用谁读：公共区域不认这些键名）。
func apply_init_params() -> void:
	# ---- 落块延迟（BlockDelay）：锁定后到「下一块出现 / 消行判定开始」的间隔 ----
	# 与消行控制器的 ClearDelay 同时存在时无需特殊处理：spawn_delay_time 让消行判定整体推迟，
	# 而 clear_line_delay_time 只在真正判出消行时才启动，实际等待 = max(两者)，不会相加。
	if TetrisGlobalData.init_has("BlockDelay"):
		set_spawn_delay(TetrisGlobalData.get_init_float("BlockDelay", 0.0))
	
	# ---- bot 参数覆盖（ExtraBotChange）：勾选的 buff → zzztoj AI 参数 ----
	# 键名 = ai_zzz::IO::Param 字段名（另支持 repeat_penalty）。未列出的参数保持 worker 默认。
	if TetrisGlobalData.init_has("ExtraBotChange"):
		var extra_bot: Variant = TetrisGlobalData.get_init_value("ExtraBotChange")
		if typeof(extra_bot) == TYPE_DICTIONARY:
			set_bot_param_overrides(extra_bot)
	
	# ---- NoHold（NoHold_1）：禁用暂存 ----
	# 该类参数由本节点统一读取并写进公共数据区的公共开关（版面绘制器直接读它，不再各存一份）
	var no_hold_value: Variant = TetrisGlobalData.get_init_value_any(["NoHold", "no_hold"], null)
	if no_hold_value != null:
		TetrisGlobalData.no_hold = bool(no_hold_value)
	
	# ---- Bot 模式（BotMode）：必须排在快速模拟之前（快速模拟要求同时开着 Bot）----
	if TetrisGlobalData.init_has("BotMode"):
		bot_mode = true
	
	# ---- 快速模拟（FastSimulate）：帧数换算式加速 ----
	#   开了 Bot → 直接开快速模拟（全过程照跑，只是快 N 倍出结果）；
	#   没开 Bot → 按需求直接返回 buff 选择界面，不实际运行。
	if TetrisGlobalData.init_has("FastSimulate"):
		if not bot_mode:
			push_warning("快速模拟需要同时开启 Bot 模式 → 返回 buff 选择界面（不实际运行）")
			return_to_buff_scene()
		else:
			enable_fast_simulate()
	
	# ---- 旋转系统：关卡/Buff 可覆盖（0=ASC / 1=SRS / 2=ARS / 3=NONE 无旋转系统，
	#      也接受 "ASC"/"SRS"/"ARS"/"NONE"）----
	#   rotation_system / RotationSystem —— 既有键名；RotateSystem —— buff「旋转系统」的键名
	var rs: Variant = TetrisGlobalData.get_init_value_any(
		["rotation_system", "RotationSystem", "RotateSystem"], null)
	if rs != null:
		set_rotation_system(rs)
		if bot_debug_log:
			print("[旋转系统] 由关卡/Buff 切换为 ", get_rotation_system_name())

## 阶段 2：所有节点的参数都就位后收尾。
## 首块已在本节点 _ready 里生成（当时用的是默认 next_count），而「短见」buff 会改
## 版面绘制器的 next_count / next_display_enabled → 这里按最终设置重建一次 Next 显示数据。
func finalize_init_params() -> void:
	_update_next_display()

# ====== 回放系统相关函数（已禁用） ======
# func _find_replay_player(node: Node) -> ReplayPlayer:
# 	if node is ReplayPlayer:
# 		return node
# 	for child in node.get_children():
# 		var found = _find_replay_player(child)
# 		if found:
# 			return found
# 	return null
# 
# func _prepare_replay_if_pending() -> void:
# 	var replay_path = GlobalData.get_pending_replay_path()
# 	if replay_path.is_empty():
# 		return
# 	
# 	var replay_data = ReplayData.load_from_file(replay_path)
# 	if replay_data == null:
# 		push_error("无法加载回放文件用于初始化: " + replay_path)
# 		return
# 	
# 	_replay_seed_override = replay_data.random_seed
# 	print("已读取回放种子: ", _replay_seed_override)
# 	
# 	if replay_record:
# 		replay_record.auto_record = false
# 		if replay_record.is_recording_active():
# 			replay_record.stop_recording()
# 	
# 	var player = replay_player
# 	if not player:
# 		player = get_node_or_null("../../ReplayPlayer")
# 	
# 	if player and player.has_method("load_and_prepare") and player.has_method("play"):
# 		player.replay_file_path = replay_path
# 		player.tetris_controller = self
# 		player.garbage_line_controller = garbage_line_controller
# 		player.bag_controller = bag_controller
# 		player.replay_record = replay_record
# 		
# 		if not player.is_loaded:
# 			var loaded = player.load_and_prepare(replay_path)
# 			if loaded:
# 				player.call_deferred("play")
# 				print("已启动回放播放: ", replay_path)
# 			else:
# 				push_error("回放加载失败")
# 		else:
# 			print("回放已加载，直接播放")
# 			player.call_deferred("play")
# 	else:
# 		push_error("未找到 ReplayPlayer 节点")
# 	
# 	GlobalData.clear_pending_replay_path()

func _initialize_random():
	# 优先使用回放提供的种子（已禁用 - 回放系统禁用）
	# if _replay_seed_override != 0:
	# 	RandomManager.initialize(_replay_seed_override)
	# else:
	# 从设置中读取种子（如果有）
	var saved_seed = _load_saved_seed()
	if saved_seed != 0:
		RandomManager.initialize(saved_seed)
	else:
		# 使用当前时间作为种子
		RandomManager.initialize_default()
	
	# 已注释（调试噪音）：print("随机数管理器已初始化，种子: ", RandomManager.get_current_seed())

func _load_saved_seed() -> int:
	# 可以从设置文件中读取保存的种子
	# 默认返回0表示使用时间种子
	return 0

## 获取当前种子（用于Replay录制）（已禁用）
# func get_current_seed() -> int:
# 	return RandomManager.get_current_seed()

## 加载用户设置
func _load_user_settings():
	var settings = UserSetting.load_settings()
	if settings:
		move_das = settings.get("move_das", 0.1)
		move_arr = settings.get("move_arr", 0.0)
		softdrop_delay = settings.get("softdrop_delay", 0.1)
		
		# 更新计时器
		if move_start_timer and move_das != 0:
			move_start_timer.wait_time = move_das
		if move_keep_timer and move_arr != 0:
			move_keep_timer.wait_time = move_arr
		if softdrop_timer and softdrop_delay != 0:
			softdrop_timer.wait_time = softdrop_delay
		
		# 应用键位设置
		UserSetting.apply_key_bindings_from_dict(settings)

func _set_timer():
	move_start_timer = Timer.new()
	if move_das != 0:
		move_start_timer.wait_time = move_das
	move_start_timer.one_shot = true
	add_child(move_start_timer)
	
	move_keep_timer = Timer.new()
	if move_arr != 0:
		move_keep_timer.wait_time = move_arr
	move_keep_timer.one_shot = true
	add_child(move_keep_timer)
	
	softdrop_timer = Timer.new()
	softdrop_timer.wait_time = softdrop_delay
	softdrop_timer.one_shot = true
	add_child(softdrop_timer)
	
	lock_timer = Timer.new()
	lock_timer.wait_time = lock_delay
	lock_timer.one_shot = true
	lock_timer.timeout.connect(_lock_piece)
	add_child(lock_timer)
	
	# 落块延迟计时器：从「锁定」时刻起算，到点后再结算出块（见 _try_spawn_after_delays）
	spawn_delay_timer = Timer.new()
	spawn_delay_timer.one_shot = true
	spawn_delay_timer.timeout.connect(_on_spawn_delay_timeout)
	add_child(spawn_delay_timer)
	
	gravity_timer = Timer.new()
	if gravity_drop_time != 0:
		gravity_timer.wait_time = gravity_drop_time
	gravity_timer.one_shot = true
	add_child(gravity_timer)
	
	# 游戏计时器（每0.1秒更新一次统计）
	game_timer = Timer.new()
	game_timer.wait_time = 0.1
	game_timer.one_shot = false
	game_timer.timeout.connect(_update_stats)
	add_child(game_timer)
	game_timer.start()

## 设置重力下落间隔（秒/行；0 = 瞬间到底）。
## 必须同时同步重力计时器的 wait_time：该计时器的 wait_time 只在 _set_timer() 里按字段默认值设过一次，
## 只改字段而不改计时器的话，关卡/Buff（如 Gravity_1 的 gravity_drop_time_array）设置的重力不会生效。
## TowerController.total_get_data() 每帧按当前阶段调用本方法。
func set_gravity_drop_time(value: float) -> void:
	gravity_drop_time = value
	if gravity_timer == null:
		return
	if value > 0:
		if gravity_timer.wait_time != value:
			gravity_timer.wait_time = value
	elif not gravity_timer.is_stopped():
		# 0 = 瞬降模式（gravity_drop() 内走「一路落到底」分支），计时器不再需要
		gravity_timer.stop()

## 设置触底锁定延迟（秒）。同样必须同步锁定计时器的 wait_time（原因见 set_gravity_drop_time）。
## 计时器要求 wait_time > 0，非法值忽略（保持原值）。
func set_lock_delay(value: float) -> void:
	lock_delay = value
	if lock_timer != null and value > 0 and lock_timer.wait_time != value:
		lock_timer.wait_time = value

## 设置「落块延迟」（秒）：从方块锁定那一刻起算，到下一块出现为止的最小间隔。
## 供 buff「落块延迟」经 tower_controller 的 BlockDelay 键调用；<=0 表示锁定后立即出下一块。
## 与消行延迟同时存在时取较长者（消行延迟 = TetrisClearLine.clear_line_delay_time，
## 由 tower_controller 的 ClearDelay 键设置），不会互相叠加。
func set_spawn_delay(value: float) -> void:
	spawn_delay_time = maxf(value, 0.0)

## 初始化统计系统
func _init_stats():
	TetrisGlobalData.game_time = 0.0
	total_pieces = 0
	total_attacks = 0
	pps_value = 0.0
	apm_value = 0.0
	rpm_value = 0.0
	ppm_value = 0.0
	apm_window_value = 0.0
	last_stats_update_time = 0.0
	# 记录统计基准时间戳（game_time 由真实经过时间累加而来）
	_last_stats_ticks = Time.get_ticks_msec()
	# 重置滚动窗口
	_rpm_events.clear()
	_ppm_events.clear()
	_apm_events.clear()

## 更新统计信息（每0.1秒调用）
func _update_stats():
	# 游戏时长按「游戏时钟」累计：_process 里的 delta 已含 Engine.time_scale，
	# 快速模拟等决策期间缩放被压到近乎 0 → 那段等待不计入分母，PPS/APM 与正常对局同口径。
	# 单次增量上限 STATS_MAX_DELTA：超长间隔视为「非游戏时间」，不计入分母。
	TetrisGlobalData.game_time += clampf(_stats_accum, 0.0, STATS_MAX_DELTA)
	_stats_accum = 0.0
	
	# 计算PPS
	if TetrisGlobalData.game_time > 0:
		pps_value = total_pieces / TetrisGlobalData.game_time
	
	# 计算APM
	if TetrisGlobalData.game_time > 0:
		apm_value = (total_attacks / TetrisGlobalData.game_time) * 60.0
	
	# 计算RPM / PPM / 短期APM（同一个滚动最近1分钟窗口）
	_prune_window_events(_rpm_events)
	_prune_window_events(_ppm_events)
	_prune_window_events(_apm_events)
	rpm_value = _window_rate(_rpm_events, "damage")
	ppm_value = _window_rate(_ppm_events, "count")
	apm_window_value = _window_rate(_apm_events, "damage")
	
	# 更新显示
	if TetrisGlobalData.board_drawer:
		TetrisGlobalData.board_drawer.update_stats(pps_value, apm_value, rpm_value)
		TetrisGlobalData.board_drawer.update_window_stats(ppm_value, apm_window_value)

## 记录放置方块（PPS统计 + PPM 滚动窗口）
func _record_piece_placed():
	total_pieces += 1
	_ppm_events.append({"time": TetrisGlobalData.game_time, "count": 1})

## 记录造成攻击（APM统计 + APM 滚动窗口）
func _record_attack_damage(damage: int):
	if damage > 0:
		total_attacks += damage
		_apm_events.append({"time": TetrisGlobalData.game_time, "damage": damage})

## 记录接收攻击（RPM统计 — 基于最近1分钟滚动窗口）
func record_received_damage(damage: int):
	if damage > 0:
		# 向滚动窗口添加事件（带当前游戏时间戳）
		_rpm_events.append({"time": TetrisGlobalData.game_time, "damage": damage})

# ========== 短期（滚动 60s 窗口）统计辅助 ==========
# RPM（接收攻击）/ PPM（落块）/ APM（打出攻击）三者同口径：
# 「窗口内事件求和 ÷ 窗口跨度 × 60」，跨度取 min(60, 游戏时长)

## 清理窗口中过期的早期事件（原地修改传入的数组）
func _prune_window_events(events: Array) -> void:
	var cutoff: float = TetrisGlobalData.game_time - RPM_WINDOW_SECONDS
	var drop: int = 0
	while drop < events.size() and float(events[drop]["time"]) < cutoff:
		drop += 1
	for _i in range(drop):
		events.pop_front()

## 窗口内事件按 key 求和后折算成每分钟
func _window_rate(events: Array, key: String) -> float:
	if events.is_empty():
		return 0.0
	
	# 窗口内的实际时间跨度（取窗口大小与游戏时间中的较小值）
	var window_span: float = min(RPM_WINDOW_SECONDS, TetrisGlobalData.game_time)
	if window_span <= 0.0:
		return 0.0
	
	var total: float = 0.0
	for event: Dictionary in events:
		total += float(event[key])
	
	return (total / window_span) * 60.0

## 获取当前统计信息
func get_stats() -> Dictionary:
	return {
		"game_time": TetrisGlobalData.game_time,
		"total_pieces": total_pieces,
		"total_attacks": total_attacks,
		"pps": pps_value,
		"apm": apm_value,
		"rpm": rpm_value
	}

## 重置统计信息
func reset_stats():
	_init_stats()
	if TetrisGlobalData.board_drawer:
		TetrisGlobalData.board_drawer.update_stats(pps_value, apm_value, rpm_value)
		TetrisGlobalData.board_drawer.update_window_stats(ppm_value, apm_window_value)

## 计算可用的出块 Y。
## allow_up_shift = true（clutch / 暂存换块）：出生点被占时向上寻找第一个不重叠位置。
## 返回可用的 y；返回 -1 表示从 base_y 一路到版面顶部（y = 0）都放不下 → 完全致死。
## ⚠ 一律用 collides_at() 做纯查询：绝不能走 _check_collision() 的默认参数
##   （ignore_current_piece=true 会先「清空候选位置」再检测，把那里的版面方块擦掉，
##   检测反而变成空位 → 方块直接覆盖原有版面出块）。
func _resolve_spawn_y(spawn_x: int, shape: Array, base_y: int, allow_up_shift: bool) -> int:
	if not collides_at(Vector2i(spawn_x, base_y), shape):
		return base_y
	if not allow_up_shift:
		return -1
	var test_y: int = base_y
	while test_y > 0 and collides_at(Vector2i(spawn_x, test_y), shape):
		test_y -= 1
	if collides_at(Vector2i(spawn_x, test_y), shape):
		return -1
	return test_y

## 生成新方块（从Bag中获取）
## clutch = true（本次出块紧跟在「本次锁定消掉了行」之后）：
##   出生点被占时不直接判死，而是把出块位置向上移，直到不重叠为止再出块；
##   只有从出生点一路到版面顶部（y = 0）都放不下时才判死。
##   —— 即 clutch 机制：玩家做出了消行行为，不到完全致死高度就不判死亡。
## clutch = false（默认，含开局首块、非消行锁定后的出块）：保持原行为，出生点被占即判死。
func spawn_new_piece(clutch: bool = false):
	# 任何出块路径（含开局/重开/消行后）都结束「已锁定但未出下一块」的窗口
	locked = false
	# 从Bag控制器获取下一个方块
	var piece_data = TetrisGlobalData.bag_controller.get_next_piece()
	var spawn_x = int((TetrisGlobalData.board_grid_width - piece_data["shape"][0].size()) / 2)
	# 生成Y坐标：从下往上数第22行
	var spawn_y = max(0, TetrisGlobalData.board_grid_height + TetrisGlobalData.board_above_visible_rows - 22)
	
	# 出块位置（clutch 时允许向上寻找空位）；放不下才是完全致死
	var resolved_y: int = _resolve_spawn_y(spawn_x, piece_data["shape"], spawn_y, clutch)
	if resolved_y < 0:
		# 这是正常的游戏结束情形（方块堆到顶），不是程序错误 → 用 print 而不是 push_error，
		# 避免在控制台/编辑器的 Errors 面板里刷红字干扰排查真正的问题。
		if clutch:
			print("[Spawn] 游戏结束：无法生成新方块（已上移至版面顶部仍重叠）")
		else:
			print("[Spawn] 游戏结束：无法生成新方块（出生点重叠）")
		trigger_game_over("方块堆积到顶部")
		return false
	if resolved_y != spawn_y:
		print("[ClutchSpawn] 出块位置重叠 → 上移至 y=", resolved_y, "（原出生点 y=", spawn_y, "）")
		spawn_y = resolved_y
	
	TetrisGlobalData.piece_shape = piece_data["shape"]
	current_color = piece_data["color"]
	TetrisGlobalData.piece_type = piece_data["type"]
	current_original_shape = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_type)
	TetrisGlobalData.piece_position = Vector2i(spawn_x, spawn_y)
	TetrisGlobalData.piece_rotation_index = 0
	# 新方块必然是未旋转状态：清掉上一块的旋转判定记录
	_invalidate_rotation_record()
	_bot_piece_serial += 1
	
	redraw_current_piece()
	
	if gravity_drop_time != 0:
		gravity_timer.start()
	lock_timer.stop()
	lock_times_limit = lock_times_limit_max
	
	TetrisGlobalData.piece_can_hold = true
	
	_update_next_display()
	refresh_shadow()
	
	_record_piece_placed()
	
	# 触发游戏开始信号（首次生成方块时）
	if not _game_started_emitted:
		_game_started_emitted = true
		game_started.emit()
	
	return true

## 生成新方块但不重置hold权限（用于hold交换后的生成）
## hold 时也允许向上寻找出块位置：clutch 出块后出生点常常被占（那正是 clutch 触发的原因），
## 若这里按老规则直接判死/卡住，玩家一按暂存就死，clutch 机制等于白给。
func spawn_new_piece_keep_hold():
	# 从Bag控制器获取下一个方块
	var piece_data = TetrisGlobalData.bag_controller.get_next_piece()
	var spawn_x = int((TetrisGlobalData.board_grid_width - piece_data["shape"][0].size()) / 2)
	# 生成Y坐标：从下往上数第22行
	var spawn_y = max(0, TetrisGlobalData.board_grid_height + TetrisGlobalData.board_above_visible_rows - 22)
	
	# 出块位置：出生点被占则向上寻找（最多到版面顶部 y = 0）
	var resolved_y: int = _resolve_spawn_y(spawn_x, piece_data["shape"], spawn_y, true)
	if resolved_y < 0:
		# 正常游戏结束情形，用 print 而不是 push_error（避免误导性的红字报错）
		print("[Spawn] 游戏结束：无法生成新方块（已上移至版面顶部仍重叠）")
		trigger_game_over("方块堆积到顶部")
		return false
	spawn_y = resolved_y
	
	TetrisGlobalData.piece_shape = piece_data["shape"]
	current_color = piece_data["color"]
	TetrisGlobalData.piece_type = piece_data["type"]
	current_original_shape = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_type)
	TetrisGlobalData.piece_position = Vector2i(spawn_x, spawn_y)
	TetrisGlobalData.piece_rotation_index = 0
	# 新方块必然是未旋转状态：清掉上一块的旋转判定记录
	_invalidate_rotation_record()
	_bot_piece_serial += 1
	
	# 绘制方块到版面
	redraw_current_piece()
	
	# 重置锁定状态
	if gravity_drop_time != 0:
		gravity_timer.start()
	lock_timer.stop()
	lock_times_limit = lock_times_limit_max
	
	_update_next_display()
	refresh_shadow()
	
	# 记录放置方块（PPS）
	_record_piece_placed()
	
	return true

## 游戏结束方法
func trigger_game_over(reason: String = "Game Over"):
	# 停止所有计时器
	game_timer.stop()
	gravity_timer.stop()
	lock_timer.stop()
	move_start_timer.stop()
	move_keep_timer.stop()
	softdrop_timer.stop()
	# 落块延迟不再需要（同时清掉「等待出块」窗口标记，避免残留状态）
	locked = false
	if spawn_delay_timer:
		spawn_delay_timer.stop()
	
	# 停止接受输入
	set_process(false)
	
	# 收集最终统计数据
	var stats = get_stats()
	
	if TetrisGlobalData.clear_line_controller:
		stats["max_combo"] = max_combo
		stats["max_btb"] = max_btb
		stats["total_lines_cleared"] = total_lines_cleared
		stats["total_spins"] = total_spins
	
	# 获取塔数据（统一走公共数据区，不再自己按路径找 TowerController 节点）
	if TetrisGlobalData.tower_controller != null:
		stats["tower_height"] = TetrisGlobalData.tower_meter
		stats["kill_count"] = TetrisGlobalData.tower_kill_count
		stats["tower_average_speed"] = TetrisGlobalData.tower_meter / maxf(TetrisGlobalData.game_time, 0.001)
		stats["current_stage"] = TetrisGlobalData.current_stage
	
	GlobalData.update_stats(stats)
	GlobalData.set_game_over_reason(reason)
	
	# 触发游戏结束信号
	game_ended.emit()
	
	# 通知版面变黑
	if TetrisGlobalData.board_drawer:
		TetrisGlobalData.board_is_game_over = true
		TetrisGlobalData.board_drawer.queue_redraw()
	
	# 延迟切换到游戏结束场景
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Tscns/game_over.tscn")

## 更新Next显示
func _update_next_display():
	if TetrisGlobalData.board_drawer and TetrisGlobalData.bag_controller:
		var next_pieces = []
		# 从board_drawer读取配置的next_count
		var next_count = TetrisGlobalData.board_next_count
		var piece_types = TetrisGlobalData.bag_controller.peek_next_pieces(next_count)
		
		for piece_type in piece_types:
			var shape = TetrisGlobalData.bag_controller.get_original_shape(piece_type)
			var color = TetrisGlobalData.bag_controller.get_piece_color(piece_type)
			next_pieces.append({
				"shape": shape,
				"color": color,
				"type": String(piece_type),
				# Allspin_1 重复惩罚预警：这块会触发惩罚时用「原本颜色+灰色」显示
				"penalty": _is_penalty_piece(String(piece_type))
			})
		
		TetrisGlobalData.board_drawer.set_next_pieces(next_pieces)
		# 顺手刷新手上 / 暂存块的惩罚预警标记：出块、暂存交换、消行后都走这里，保证三者同步
		_refresh_penalty_flags()


## 刷新「手上 / 暂存」两个惩罚预警标记（next 列表在 _update_next_display 里逐项带标记）
func _refresh_penalty_flags() -> void:
	if TetrisGlobalData.board_drawer == null:
		return
	current_piece_penalty = _is_penalty_piece(TetrisGlobalData.piece_type)
	TetrisGlobalData.board_hold_piece_penalty = _is_penalty_piece(TetrisGlobalData.piece_hold_type)
	# 手上方块要按新标记重画（颜色变了）
	if not TetrisGlobalData.piece_shape.is_empty():
		redraw_current_piece()


## 供 TetrisClearLine 在消行结算后立刻调用：不等下一块出块就刷新惩罚预警显示。
## （消行动画有延迟，若只在出块时刷新，玩家会看到「预警比实际状态晚一手」）
func refresh_penalty_warning() -> void:
	_refresh_penalty_flags()
	if TetrisGlobalData.board_drawer == null:
		return
	# 只更新 next 列表里每一项的 penalty 字段（不重建列表，避免影响 bag 读取顺序）
	for entry: Dictionary in TetrisGlobalData.board_next_pieces_data:
		entry["penalty"] = _is_penalty_piece(String(entry.get("type", "")))
	TetrisGlobalData.board_drawer.queue_redraw()


## 这块方块是否会触发 Allspin_1 的重复惩罚（由 TetrisClearLine 判定；未开 Allspin 时恒为 false）
func _is_penalty_piece(piece_type: String) -> bool:
	if TetrisGlobalData.clear_line_controller == null or piece_type.is_empty():
		return false
	return TetrisGlobalData.clear_line_controller.is_allspin_penalty_piece(piece_type)


## 手上方块（当前活动块）的实际显示色：触发惩罚预警时 = 原本颜色 + 灰色
func get_current_piece_display_color() -> Color:
	if TetrisGlobalData.board_drawer == null:
		return current_color
	if not TetrisGlobalData.board_drawer.should_tint(current_piece_penalty):
		return current_color
	return TetrisGlobalData.board_drawer.penalty_display_color(current_color)

## 绘制当前方块到版面
## use_penalty_color=false 时强制用原本颜色（锁定那一刻调，避免锁进版面的格子被灰化留在场上）
func redraw_current_piece(use_penalty_color: bool = true):
	# 清除当前方块（重新绘制时会覆盖，但为了安全先清除）
	clear_current_piece()
	
	# 每次重绘顺手刷新惩罚预警标记（只依赖「上一手消行信息 + 本块类型」，开销极小）
	current_piece_penalty = use_penalty_color and _is_penalty_piece(TetrisGlobalData.piece_type)
	var draw_color: Color = get_current_piece_display_color() if use_penalty_color else current_color
	
	# 绘制新位置的方块
	for y in range(TetrisGlobalData.piece_shape.size()):
		for x in range(TetrisGlobalData.piece_shape[y].size()):
			if TetrisGlobalData.piece_shape[y][x] == 1:
				var board_x = TetrisGlobalData.piece_position.x + x
				var board_y = TetrisGlobalData.piece_position.y + y
				TetrisGlobalData.board_set_cell(board_x, board_y, draw_color)

## 清除当前方块
func clear_current_piece():
	for y in range(TetrisGlobalData.piece_shape.size()):
		for x in range(TetrisGlobalData.piece_shape[y].size()):
			if TetrisGlobalData.piece_shape[y][x] == 1:
				var board_x = TetrisGlobalData.piece_position.x + x
				var board_y = TetrisGlobalData.piece_position.y + y
				TetrisGlobalData.board_set_cell(board_x, board_y, null)

## 检查碰撞
func _check_collision(pos: Vector2i, piece: Array = TetrisGlobalData.piece_shape, ignore_current_piece: bool = true) -> bool:
	if ignore_current_piece:
		clear_current_piece()
	
	var is_not_allow : bool = false
	
	for y in range(piece.size()):
		for x in range(piece[y].size()):
			if piece[y][x] == 1:
				var board_x = pos.x + x
				var board_y = pos.y + y
				
				# 边界检查
				if board_x < 0 or board_x >= TetrisGlobalData.board_grid_width:
					is_not_allow = true
				if board_y >= TetrisGlobalData.board_grid_height + TetrisGlobalData.board_above_visible_rows:
					is_not_allow = true
				
				# 检查与其他格子的碰撞（只检查非空格子）
				if board_y >= 0 and TetrisGlobalData.board_get_cell(board_x, board_y) != null:
					is_not_allow = true
		if is_not_allow:
			break
	
	if ignore_current_piece:
		redraw_current_piece()
	return is_not_allow

## 取某个形状在指定位置上占据的版面格子坐标（用于碰撞查询时排除自身）
func get_piece_cells(piece: Array, pos: Vector2i) -> Array:
	var cells: Array = []
	if piece == null or piece.is_empty():
		return cells
	for y in range(piece.size()):
		for x in range(piece[y].size()):
			if piece[y][x] == 1:
				cells.append(Vector2i(pos.x + x, pos.y + y))
	return cells

## 纯查询碰撞检测（返回 true = **会碰撞/越界**，不是「能放下」）：不修改版面数据、不触发重绘。
## ignore_cells 中的格子（通常是自身方块占据的格子）视为空，用于排除自身（避免与自己重叠误判）。
## 语义与 _check_collision 完全一致：左右不可越界、下方不可越界、顶部之上不算碰撞、已占用格子为碰撞。
func collides_at(pos: Vector2i, piece: Array, ignore_cells: Array = []) -> bool:
	if piece == null or piece.is_empty():
		return false
	for y in range(piece.size()):
		for x in range(piece[y].size()):
			if piece[y][x] != 1:
				continue
			var board_x: int = pos.x + x
			var board_y: int = pos.y + y
			if board_x < 0 or board_x >= TetrisGlobalData.board_grid_width:
				return true
			if board_y >= TetrisGlobalData.board_grid_height + TetrisGlobalData.board_above_visible_rows:
				return true
			if board_y < 0:
				continue
			if ignore_cells.has(Vector2i(board_x, board_y)):
				continue
			if TetrisGlobalData.board_get_cell(board_x, board_y) != null:
				return true
	return false

## 纯查询：当前方块能否向 (dx,dy) 移动（自身格子视为空，无副作用）
func _can_move(dx: int, dy: int) -> bool:
	if TetrisGlobalData.piece_shape.is_empty():
		return false
	var ignore_cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
	var new_pos = Vector2i(TetrisGlobalData.piece_position.x + dx, TetrisGlobalData.piece_position.y + dy)
	return not collides_at(new_pos, TetrisGlobalData.piece_shape, ignore_cells)

## 方块位置发生任何改变（移动/下落/暂存/换块/版面整体上移）后调用：
## 使旋转判定记录失效——spin 的前提是「最后一次成功动作是旋转」，移动过就不该再判 spin。
func _invalidate_rotation_record() -> void:
	if TetrisGlobalData.clear_line_controller:
		TetrisGlobalData.clear_line_controller.reset_rotation_record()

## 版面整体位移（垃圾行上涨）后，方块与旋转记录一起位移：
## 此时方块相对堆叠的位置未变，仅需把记录里的位置同步到方块的实际位置，避免 spin 判定用陈旧坐标。
func sync_rotation_record_position() -> void:
	if TetrisGlobalData.clear_line_controller:
		TetrisGlobalData.clear_line_controller.sync_rotation_record_position(TetrisGlobalData.piece_position)

## 尝试移动方块
func _try_move(delta_x: int, delta_y: int) -> bool:
	# 手上无方块（生成/消行延迟期间）：不移动，避免空方块在 while 循环里无限下落导致卡死
	if TetrisGlobalData.piece_shape.is_empty():
		return false
	var new_pos = Vector2i(TetrisGlobalData.piece_position.x + delta_x, TetrisGlobalData.piece_position.y + delta_y)
	_check_underground_touch()
	
	if _can_move(delta_x, delta_y):
		# 移动成功
		clear_current_piece()
		TetrisGlobalData.piece_position = new_pos
		redraw_current_piece()
		
		# 位置发生改变 → 旋转判定记录失效（spin 要求「最后一次成功动作为旋转」）
		_invalidate_rotation_record()
		
		_check_underground_touch()
		# 移动后重置锁延
		if lock_times_limit > 0 and not lock_timer.is_stopped():
			lock_timer.start()
			lock_times_limit -= 1
		
		refresh_shadow()
		return true
	else:
		
		return false

func _check_underground_touch():
	# bot 计划执行期间禁止「触底锁延」自动锁定：方块必须等计划执行完、由 bot 的 hard_drop 锁定。
	# 否则方块会在计划走到一半时被锁死（旋转踢墙还没做完）→ 实际落点与决策不一致；
	# 而且这种锁定不经过 hard_drop，会绕过 PPS 限制（实测 PPS 会飙到 7 以上）。
	if bot_mode and _zzz_bridge != null and _zzz_bridge.is_plan_active():
		lock_timer.stop()
		return
	var new_pos = Vector2i(TetrisGlobalData.piece_position.x, TetrisGlobalData.piece_position.y + 1)
	if not collides_at(new_pos, TetrisGlobalData.piece_shape, get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)):
		lock_timer.stop()
	elif lock_timer.is_stopped():
		lock_timer.start()

## 锁定当前方块。
## 逻辑上清除 current_piece（board_data 中已锁定的格子保持不变），然后立刻开始消行判定；
## 「落块延迟」（spawn_delay_time，buff「落块延迟」）是**锁定后**通往下一块的最小间隔，
## 由 _try_spawn_after_delays() 在出块前结算（见下方说明），不在锁定前计时。
func _lock_piece():
	# 已在等待生成新方块时避免重复触发
	if TetrisGlobalData.piece_shape.is_empty():
		return
	# PPS 兜底：任何锁定（不止 bot 的 hard_drop）都要保证「每块最小间隔」生效，
	# 否则重力/锁延造成的锁定会让 PPS 超过 bot_target_pps。
	# 注意：这里 armed 的间隔用的是「刚锁定这一手」的 pps，只作为兜底；
	# 下一手自己的计划到手后会用「下一手自己的 pps」按 _bot_last_lock_ms 重算（见 _process_bot_control），
	# 这样减速才归属到会消行的那一手，而不是被推迟到它后面那块。
	if bot_mode:
		# 理想时刻链：本手锁定后，基准推进到「本手的理想锁定时刻」（而不是实际锁定时刻）。
		# 实际锁定总会比理想晚最多一帧的游戏时长（量化误差），若基准跟着实际走，这个误差会逐块累积
		# → 每块实际占用变成「间隔 + 半帧」→ PPS 被稀释（快速模拟下 20 倍速时实测掉到 2.5）。
		# 让基准保持在理想网格上，长期平均就严格等于 bot 自己的 pps 间隔（与攻击余数处理的思路一致）。
		if _bot_lock_target_game >= 0.0:
			_bot_lock_base_game = _bot_lock_target_game
		else:
			_bot_lock_base_game = _game_clock
		_bot_lock_target_game = -1.0
		_bot_piece_cooldown = max(_bot_piece_cooldown, _get_bot_piece_interval())
		_bot_last_lock_ms = float(Time.get_ticks_msec())   # 仅用于 [BotLock] 日志的「上块间隔」真实耗时
		_bot_last_lock_game = _game_clock                  # 节奏归属按游戏时钟算
	# 锁定瞬间刷新落块渐隐时间戳（隐形模式下按该时间戳做淡出）。
	# 碰撞检测已改为无副作用的纯查询，不再顺带刷新，故在此显式刷新一次。
	# use_penalty_color=false：惩罚预警只影响「手上」的显示，锁进版面的格子仍用原本颜色。
	redraw_current_piece(false)
	# 记录本次落块占据的版面格子（消行时的 Spike 数字要显示在落块位置；current_piece 下面就会被清空）
	TetrisGlobalData.piece_last_locked_cells = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
	# 记录本块类型：消行时写进 TetrisClearLine 的「上次消行方块类型」，供 Allspin 重复惩罚预警比对
	TetrisGlobalData.piece_last_locked_type = TetrisGlobalData.piece_type
	# 逻辑上清除当前方块（保留 board_data 中已锁定的格子）
	TetrisGlobalData.piece_shape = []
	# 落块延迟从「锁定」这一刻起算；已锁定、尚未出下一块
	locked = true
	lock_time_ms = Time.get_ticks_msec()
	_lock_game_time = _game_clock        # 落块延迟按游戏时钟算（快速模拟下不受真实耗时干扰）
	# 落块结束 → 发通知，由消行控制器订阅后做判定（判定结果与出块请求会以事件回来）
	TetrisGlobalData.piece_locked.emit()

## 落块延迟还剩多少秒（已过时返回 0）。内部使用：出块结算时判断要不要再等。
func _block_delay_remaining() -> float:
	if spawn_delay_time <= 0.0 or not locked:
		return 0.0
	var elapsed: float = maxf(_game_clock - _lock_game_time, 0.0)
	return maxf(spawn_delay_time - elapsed, 0.0)

## 出块前的延迟结算：锁定后的实际出块时刻 = 锁定时刻 + max(落块延迟, 消行延迟)。
## 三个调用点都收敛到本函数，保证只出块一次：
##   1) 收到 spawn_requested（消行控制器在「判定 + 全部版面变化」完成后发来，见 _on_lines_judged）
##   2) 落块延迟计时到点（_on_spawn_delay_timeout）
##   3) spawn_requested 到得比落块延迟早时，先起计时器等 2)
## 规则：
##   · 消行延迟/动画还没结束（TetrisGlobalData.clear_animating_active）→ 不出块，等消行控制器再请求
##   · 距锁定还差一段落块延迟 → 起计时器等
##   · 两者都已满足 → 出块（clutch 取本次是否消行）
func _try_spawn_after_delays() -> void:
	if not locked:
		return
	if TetrisGlobalData.clear_animating_active:
		return
	var remaining: float = _block_delay_remaining()
	if remaining > 0.0:
		if spawn_delay_timer.is_stopped():
			spawn_delay_timer.wait_time = remaining
			spawn_delay_timer.start()
		return
	# 落块延迟已满足 → 出块
	locked = false
	spawn_new_piece(_last_clear_did_clear)

## 落块延迟到点：再做一次结算
func _on_spawn_delay_timeout() -> void:
	_try_spawn_after_delays()

## 收到「请求出块」（TetrisClearLine 在判定 + 全部版面变化完成后发出）：
## 这里只是**请求**，实际出块时机仍由 _try_spawn_after_delays() 统一结算
## （locked 门 + 实际出块时刻 = 锁定时刻 + max(落块延迟, 消行延迟)）。
func _on_spawn_requested() -> void:
	_try_spawn_after_delays()

## 收到「消行判定结果」（TetrisClearLine 发出，语义：本次判定的版面变化已全部完成）。
## 这里做原先 _check_and_clear_lines() 里的统计与抵消，以及「没消行才涨垃圾」的决策。
## ⚠ cleared == 0 时不计入任何统计（与旧口径一致：Spin0 的伤害不进 APM/总消行）。
func _on_lines_judged(cleared: int, did_clear: bool, damage: int, spin_text: String,
		btb: int, combo: int) -> void:
	# 本次是否消了行 → 出块时的 clutch 容错（spawn_new_piece(clutch)）
	_last_clear_did_clear = did_clear
	if cleared <= 0:
		# 没有消行 → 请求垃圾行上涨（本节点不再直接调用垃圾行控制器）。
		# 放在这里 = 版面变化先于出块（有/无消行延迟两条路径顺序统一）。
		TetrisGlobalData.garbage_rise_requested.emit()
		return
	
	# 更新总消行数
	total_lines_cleared += cleared
	
	# 更新最大连击 / 最大 BTB
	if combo > max_combo:
		max_combo = combo
	if btb > max_btb:
		max_btb = btb
	
	# 检测是否有 Spin
	if not spin_text.is_empty():
		total_spins += 1
	
	# 记录造成攻击（APM）
	if damage > 0:
		_record_attack_damage(damage)
		# 请求用本次伤害抵消垃圾行（队列是否为空的判断与「防御奖励」都由垃圾行控制器负责）
		TetrisGlobalData.garbage_offset_requested.emit(damage)

## 收到「整版上移即将开始」（垃圾/实心行上涨）：先把手上方块从版面缓冲里清掉，
## 否则它会被一起搬进新行（新行数据里会带上旧方块格子）。
func _on_board_shift_starting(sync_piece: bool) -> void:
	if not sync_piece or TetrisGlobalData.piece_shape.is_empty():
		return
	clear_current_piece()

## 收到「整版上移已完成」：把手上方块按新位置重画。
## 规则与旧实现一致（原先这段写在垃圾行控制器里）：
##   1) 位置 = 原位置 - rows，且不低于顶部（y >= 0）
##   2) 若与新版面碰撞 → 逐格向上找第一个合法位置
##   3) 都找不到 → 方块被卡死，结束本局
##   4) 重画方块 → 同步旋转记录位置（spin 判定不能用陈旧坐标）→ 刷新影子
## ⚠ 位置计算用纯查询 collides_at()：_check_collision() 默认会先擦掉候选位置的版面方块，
##   会让检测误判为空位，随后重绘就把方块画在那里覆盖原有版面。
func _on_board_shifted_up(rows: int, sync_piece: bool) -> void:
	if not sync_piece or TetrisGlobalData.piece_shape.is_empty():
		return
	var new_pos := Vector2i(TetrisGlobalData.piece_position.x,
		maxi(TetrisGlobalData.piece_position.y - rows, 0))
	TetrisGlobalData.piece_position = new_pos
	if collides_at(new_pos, TetrisGlobalData.piece_shape):
		var test_pos: Vector2i = new_pos
		while test_pos.y > 0 and collides_at(test_pos, TetrisGlobalData.piece_shape):
			test_pos.y -= 1
		if test_pos.y >= 0 and not collides_at(test_pos, TetrisGlobalData.piece_shape):
			TetrisGlobalData.piece_position = test_pos
		else:
			push_error("方块被卡死，游戏结束")
			trigger_game_over("方块被卡死")
			return
	redraw_current_piece()
	# 整版上移时方块被一并上移：旋转记录里的位置要同步到方块实际位置，
	# 否则 spin 判定会拿陈旧坐标探测（位置整体偏下 rows 行）
	sync_rotation_record_position()
	refresh_shadow()

## 收到「本局应结束」的请求（垃圾上涨失败 / 方块堆积过高 / 方块被卡死等）
func _on_game_over_requested(reason: String) -> void:
	trigger_game_over(reason)

## 添加攻击（由外部调用；实际入队与 RPM 记录由垃圾行控制器处理）
func add_garbage_attack(attack_count: int):
	TetrisGlobalData.garbage_attack_requested.emit(attack_count)

# ========== 旋转系统 ==========

## 左旋（逆时针旋转90度）
func rotate_left():
	@warning_ignore("return_value_discarded")
	_rotate_piece(-1)

## 右旋（顺时针旋转90度）
func rotate_right():
	@warning_ignore("return_value_discarded")
	_rotate_piece(1)

## 180度旋转
func rotate_180():
	@warning_ignore("return_value_discarded")
	_rotate_piece(2)

## 旋转方块核心逻辑（返回是否旋转成功；失败时方块状态不变）
## 无旋转系统（NONE）：旋转照常判定，但请踢墙表只给原地候选（见 get_kick_offsets_for），
## 因此需要被踢开才能放下的旋转会失败。
func _rotate_piece(direction: int) -> bool:
	if TetrisGlobalData.piece_shape.is_empty():
		return false  # 手上无方块（延迟期间）：不旋转
	
	match direction:
		1:  # 顺时针旋转 90度
			return _apply_rotation_with_kick(_get_rotated_matrix(TetrisGlobalData.piece_shape, 1), 1)
		-1:  # 逆时针旋转 90度
			return _apply_rotation_with_kick(_get_rotated_matrix(TetrisGlobalData.piece_shape, -1), -1)
		2:  # 180度旋转
			return _apply_rotation_with_kick(_get_rotated_matrix(TetrisGlobalData.piece_shape, 2), 2)
		_:
			return false

## 应用旋转并尝试踢墙（返回是否旋转成功）
func _apply_rotation_with_kick(rotated_piece: Array, direction: int) -> bool:
	if direction != 1 and direction != -1 and direction != 2:
		return false
	
	var from_index: int = TetrisGlobalData.piece_rotation_index
	var to_index: int = _calc_rotation_index(from_index, direction)
	
	# 踢墙候选：ASC = 单表（CCW 由 X 取反镜像）；SRS = 按方块类型与 from→to 状态对取表
	var kicks: Array = get_kick_offsets_for(TetrisGlobalData.piece_type, from_index, to_index, direction)
	
	# ASC 的「单表 + 逆时针 X 取反」约定；SRS 表内已含方向信息，乘数恒为 1
	var kick_multiplier: int = -1 if (TetrisGlobalData.piece_rotation_system == RotationSystemType.ASC and direction == -1) else 1
	
	# 自身格子（旋转前位置）：踢墙查询时视为空，避免与自己重叠
	var self_cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
	
	for kick in kicks:
		var new_pos = Vector2i(TetrisGlobalData.piece_position.x + kick[0] * kick_multiplier, TetrisGlobalData.piece_position.y + kick[1])
		
		if not collides_at(new_pos, rotated_piece, self_cells):
			# 旋转成功
			clear_current_piece()
			TetrisGlobalData.piece_shape = rotated_piece
			TetrisGlobalData.piece_position = new_pos
			TetrisGlobalData.piece_rotation_index = to_index
			redraw_current_piece()
			
			# 记录旋转事件（用于Spin检测），传递方块颜色
			# 注意：O 块旋转是几何空操作，其旋转记录不参与 spin 判定（见 TetrisClearLine._detect_spin_type）
			if TetrisGlobalData.clear_line_controller:
				TetrisGlobalData.clear_line_controller.record_rotation(TetrisGlobalData.piece_type, TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position, current_color)
			
			# Spin 达成反馈：旋转后判定到 Spin（不可移动条件成立）→ 操控中的方块闪一下光；
			# 若本局是惩罚模式且这次 Spin「直接消行」会触发重复惩罚 → 闪红光
			_trigger_spin_flash()
			
			_check_underground_touch()
			
			# 旋转后重置锁延
			if lock_times_limit > 0 and not lock_timer.is_stopped():
				lock_timer.stop()
				lock_timer.start()
				lock_times_limit -= 1
			
			refresh_shadow()
			return true
	
	# 所有踢墙尝试都失败
	return false

## 获取旋转后的矩阵
func _get_rotated_matrix(piece: Array, direction: int) -> Array:
	var rows = piece.size()
	var cols = piece[0].size()
	var rotated = []
	
	match direction:
		1:  # 顺时针旋转 90度
			rotated.resize(cols)
			for i in range(cols):
				rotated[i] = []
				rotated[i].resize(rows)
				for j in range(rows):
					rotated[i][j] = piece[rows - 1 - j][i]
		-1:  # 逆时针旋转 90度
			rotated.resize(cols)
			for i in range(cols):
				rotated[i] = []
				rotated[i].resize(rows)
				for j in range(rows):
					rotated[i][j] = piece[j][cols - 1 - i]
		2:  # 180度旋转
			rotated.resize(rows)
			for i in range(rows):
				rotated[i] = []
				rotated[i].resize(cols)
				for j in range(cols):
					rotated[i][j] = piece[rows - 1 - i][cols - 1 - j]
	
	return rotated

# ========== 暂存系统 ==========

## 暂存当前方块
func hold_current_piece():
	if TetrisGlobalData.piece_shape.is_empty():
		return false  # 手上无方块（延迟期间）：不可暂存
	if TetrisGlobalData.no_hold:
		return false  # NoHold模式：禁用暂存
	if not TetrisGlobalData.piece_can_hold:
		return false  # 本回合已使用过暂存
	
	# 清除当前方块
	clear_current_piece()
	
	# 如果暂存区为空，将当前方块存入暂存，然后生成新方块
	if hold_piece.is_empty():
		# 保存当前方块的原始形状（未旋转状态）
		hold_piece = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_type)
		hold_color = current_color
		TetrisGlobalData.piece_hold_type = TetrisGlobalData.piece_type
		hold_original_shape = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_type)
		
		# 更新Hold显示（penalty：暂存块会触发 Allspin 重复惩罚时用「原色+灰」显示）
		TetrisGlobalData.board_drawer.set_hold_piece(hold_piece, hold_color, _is_penalty_piece(TetrisGlobalData.piece_hold_type))
		
		# 生成新方块（保持hold状态）
		spawn_new_piece_keep_hold()
	else:
		# 暂存区有方块时，进行交换
		# 先保存当前方块的完整信息（位置也要存：失败恢复时要放回原处，否则方块会瞬移并压住版面）
		var temp_piece = TetrisGlobalData.piece_shape
		var temp_color = current_color
		var temp_type = TetrisGlobalData.piece_type
		var temp_original = current_original_shape
		var temp_rotation_index: int = TetrisGlobalData.piece_rotation_index
		var temp_position: Vector2i = TetrisGlobalData.piece_position
		
		# 从暂存区取出方块
		TetrisGlobalData.piece_shape = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_hold_type)
		current_color = hold_color
		TetrisGlobalData.piece_type = TetrisGlobalData.piece_hold_type
		current_original_shape = hold_original_shape
		TetrisGlobalData.piece_rotation_index = 0  # 取出的方块是原始形状（未旋转）
		
		# 将当前方块存入暂存区
		hold_piece = TetrisGlobalData.bag_controller.get_original_shape(temp_type)
		hold_color = temp_color
		TetrisGlobalData.piece_hold_type = temp_type
		hold_original_shape = temp_original
		
		# 更新Hold显示（penalty：暂存块会触发 Allspin 重复惩罚时用「原色+灰」显示）
		TetrisGlobalData.board_drawer.set_hold_piece(hold_piece, hold_color, _is_penalty_piece(TetrisGlobalData.piece_hold_type))
		
		# 出块位置（从下往上数第22行）；出生点被占时与 clutch 一样向上寻找空位。
		# ⚠ 必须用 _resolve_spawn_y()/collides_at()：
		#   旧写法 _check_collision(current_position) 默认 ignore_current_piece=true，
		#   会先把候选位置清空再检测 → 把那里的版面方块擦掉且检测不出碰撞，
		#   接着 redraw_current_piece() 就把方块画上去 → 「直接覆盖原有版面出块」。
		var spawn_x = int((TetrisGlobalData.board_grid_width - TetrisGlobalData.piece_shape[0].size()) / 2)
		var spawn_y = max(0, TetrisGlobalData.board_grid_height + TetrisGlobalData.board_above_visible_rows - 22)
		var resolved_y: int = _resolve_spawn_y(spawn_x, TetrisGlobalData.piece_shape, spawn_y, true)
		if resolved_y < 0:
			# 连版面顶部都放不下：本次暂存交换作废，整体恢复原状（含位置）
			# 属于正常可发生的情形（版面已满），用 print 而不是 push_error
			print("[Hold] 暂存交换失败：版面已满，无法生成方块（已恢复原状）")
			TetrisGlobalData.piece_shape = temp_piece
			current_color = temp_color
			TetrisGlobalData.piece_type = temp_type
			current_original_shape = temp_original
			TetrisGlobalData.piece_rotation_index = temp_rotation_index
			TetrisGlobalData.piece_position = temp_position
			hold_piece = TetrisGlobalData.bag_controller.get_original_shape(TetrisGlobalData.piece_hold_type)
			hold_color = temp_color  # 恢复hold颜色
			TetrisGlobalData.board_drawer.set_hold_piece(hold_piece, hold_color, _is_penalty_piece(TetrisGlobalData.piece_hold_type))
			redraw_current_piece()
			return false
		TetrisGlobalData.piece_position = Vector2i(spawn_x, resolved_y)
		
		# 绘制方块到版面
		redraw_current_piece()
		refresh_shadow()
		
		# 重置锁定状态
		lock_timer.stop()
		lock_times_limit = lock_times_limit_max
	
	# 换块后手上是一个未旋转的新块：旋转判定记录必须失效
	_invalidate_rotation_record()
	
	# 标记暂存已使用
	TetrisGlobalData.piece_can_hold = false
	return true

## 获取当前暂存的方块（用于显示）
func get_hold_piece() -> Array:
	return hold_piece

## 获取暂存方块的颜色
func get_hold_color() -> Color:
	return hold_color

## 清空暂存
func clear_hold():
	hold_piece = []
	hold_color = Color.WHITE
	TetrisGlobalData.piece_hold_type = ""
	hold_original_shape = []

# ========== 公共控制方法 ==========
## 计算影子位置（硬降到底的位置）
func _calculate_shadow_position() -> Vector2i:
	if TetrisGlobalData.piece_shape.is_empty():
		return Vector2i.ZERO
	
	var shadow_pos = TetrisGlobalData.piece_position
	# 用纯查询逐格下探：自身格子视为空，且不产生清绘/重绘副作用
	# （原实现每个候选位置都会清空+重绘当前方块，一块从高处落下要跑几十次）
	var self_cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
	
	# 一直向下移动直到碰撞
	while true:
		var test_pos = Vector2i(shadow_pos.x, shadow_pos.y + 1)
		if collides_at(test_pos, TetrisGlobalData.piece_shape, self_cells):
			break
		shadow_pos = test_pos
	
	return shadow_pos

## 更新影子显示
func refresh_shadow():
	if TetrisGlobalData.board_drawer:
		if TetrisGlobalData.piece_shape.is_empty():
			TetrisGlobalData.board_drawer.clear_shadow()
		else:
			var shadow_pos = _calculate_shadow_position()
			TetrisGlobalData.board_drawer.update_shadow(TetrisGlobalData.piece_shape, shadow_pos, current_color)

# ========== Spin 闪光反馈 ==========

## 旋转成功后调用：判定到 Spin 就给操控中的方块闪一下光。
##   白光 = 达成 Spin；
##   红光 = 本局处于惩罚模式（Allspin_1~5），且这一手会触发重复惩罚。
## 判定口径（与真实结算同一套判据，只查询、不推进轮状态）：
##   · 按**硬降落点**预测会消几行（真正的消行数要等落块才知道）；
##   · 会消行 → 按该行数判：行数轮内重复 / 与上一手有效行数相同 / 落块件与上一手相同 都算；
##   · **消 0 行（Spin0）同样要判**：Spin0 的有效行数是 0、也属于行数轮成员，
##     所以「0 已在轮内」或「上一手也是 0 行」时同样闪红光；类型相关的惩罚也一起判。
## bot 操作时同样闪光（保留反馈；想关掉把 spin_flash_enabled 设为 false）。
func _trigger_spin_flash() -> void:
	var cl = TetrisGlobalData.clear_line_controller
	var bd = TetrisGlobalData.board_drawer
	if cl == null or bd == null or TetrisGlobalData.piece_shape.is_empty():
		return
	var spin_type: String = cl.get_current_spin_type()
	if spin_type.is_empty():
		return
	var penalized: bool = false
	if TetrisGlobalData.clear_allspin >= 1:
		# rows == 0 表示这一手是 Spin0（有 Spin 但消 0 行）—— 同样参与重复判定，不能跳过
		var land: Vector2i = _calculate_shadow_position()
		var rows: int = _count_lines_if_locked_at(land)
		penalized = cl.would_allspin_penalize(spin_type, rows, TetrisGlobalData.piece_type)
	bd.flash_spin(penalized)


## 预测：把当前方块放到 land_pos（硬降落点）时会消掉几行。
## 当前方块自身的格子已经写进 board_data（画面上那块），所以先把自身视为空、再把落点格子叠上去。
func _count_lines_if_locked_at(land_pos: Vector2i) -> int:
	var shape: Array = TetrisGlobalData.piece_shape
	if shape.is_empty():
		return 0
	var self_cells: Array = get_piece_cells(shape, TetrisGlobalData.piece_position)
	var landing: Array = get_piece_cells(shape, land_pos)
	var land_set := {}
	for c: Vector2i in landing:
		land_set[c] = true
	var rows: int = 0
	for y in range(TetrisGlobalData.board_data.size()):
		var full: bool = true
		for x in range(TetrisGlobalData.board_grid_width):
			var cell := Vector2i(x, y)
			if land_set.has(cell):
				continue
			if self_cells.has(cell):
				continue
			if TetrisGlobalData.board_get_cell(x, y) == null:
				full = false
				break
		if full:
			rows += 1
	return rows

## 版面被外部改写（关卡/Buff 的初始版面 StartBoard / StartGarbage 印刷）后调用。
## 出块与影子是在节点 _ready 时按「当时的空版面」算好的，而初始版面是在所有节点就绪之后
## 才由 TetrisGlobalData.apply_init_data() 印上去的 —— 不刷新的话开局影子会停在按空版面算出的最底层，
## 方块也可能正好压在刚印出来的初始版面上。这里按当前版面重算一次：
##   1) 当前方块若与新版面重叠 → 用与出块相同的纯查询向上找第一个不重叠位置；
##   2) 刷新影子。
func refresh_after_board_change() -> void:
	if TetrisGlobalData.board_drawer == null:
		return
	if not TetrisGlobalData.piece_shape.is_empty():
		# ⚠ 当前方块自身的格子此刻就在 board_data 里（出块/移动都会写进去），
		#   所以纯查询必须把「自身格子」作为 ignore 传入；否则会把自己判成碰撞、把方块一路往上顶。
		var self_cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
		var fixed_y: int = TetrisGlobalData.piece_position.y
		while fixed_y > 0 and collides_at(
				Vector2i(TetrisGlobalData.piece_position.x, fixed_y), TetrisGlobalData.piece_shape, self_cells):
			fixed_y -= 1
		if fixed_y != TetrisGlobalData.piece_position.y:
			clear_current_piece()
			TetrisGlobalData.piece_position = Vector2i(TetrisGlobalData.piece_position.x, fixed_y)
			redraw_current_piece()
	refresh_shadow()
	TetrisGlobalData.board_drawer.queue_redraw()

## 左移
func move_left():
	@warning_ignore("return_value_discarded")
	_try_move(-1, 0)

## 右移
func move_right():
	@warning_ignore("return_value_discarded")
	_try_move(1, 0)

## 软降（单步向下）
func soft_drop():
	@warning_ignore("return_value_discarded")
	_try_move(0, 1)

## 软降到底（不锁定）：bot 路径中的 "soft_drop" 动作（ColdClear SonicDrop）使用本方法，
## 对应将当前方块一直下落到触底位置，但不像 hard_drop 那样立即锁定，等待后续 hard_drop 锁定。
func soft_drop_to_bottom():
	if TetrisGlobalData.piece_shape.is_empty():
		return  # 手上无方块（延迟期间）：不下落
	while _try_move(0, 1):
		pass

## 硬降（直接落底）
func hard_drop():
	if TetrisGlobalData.piece_shape.is_empty():
		return  # 手上无方块（延迟期间）：不硬降
	# 一直向下移动直到碰撞
	while _try_move(0, 1):
		pass  # 继续移动
	
	# 落块自检：实际落点 vs bot 决策落点。
	# 坐标口径：x = 最左格，y = 最低格（与 worker 返回的落点口径一致）。
	# ⚠ 必须补偿垃圾上涨：上涨会把整个版面（连同当前方块）一起上移 k 行，
	#   所以「计划确认后版面被抬高了多少」就是实际 y 合法偏移量（记在 _bot_check_rise）。
	#   旋转态故意不比较：worker 与游戏对 I/S/Z 这类对称块的旋转编号存在 ±2 的等价标签差异。
	if bot_mode and _zzz_bridge != null and not TetrisGlobalData.piece_shape.is_empty():
		var cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
		var minx := 99
		var maxy := -99
		for c in cells:
			minx = mini(minx, c.x)
			maxy = maxi(maxy, c.y)
		var tgt: Dictionary = _zzz_bridge.get_plan_target()
		if not tgt.is_empty() and bool(tgt.get("valid", false)):
			var plan_x: int = int(tgt["x"])
			var plan_y: int = int(tgt["y"]) - _bot_check_rise
			# ⚠ 抬升补偿只有在"方块确实随整版一起上移"时才成立；实测存在抬升已发生、
			#   但本手方块并未位移的情形（例如抬升落在这块锁定之后），此时比 y 就是误报。
			#   所以：x 始终比较；y 只在没有抬升的那一手比较（有抬升时只记录信息）。
			if minx != plan_x or (_bot_check_rise == 0 and maxy != plan_y):
				push_warning("[BotCheck] 落点与决策不一致：piece=%s 实际=(%d,%d) 决策=(%d,%d)（垃圾抬升补偿 %d 行）rot 实际=%d 决策=%d" % [
					TetrisGlobalData.piece_type, minx, maxy, plan_x, int(tgt["y"]), _bot_check_rise,
					TetrisGlobalData.piece_rotation_index, int(tgt["rot"])])
		_bot_t_lock_ms = Time.get_ticks_msec()
	
	# 触底后立即锁定
	_lock_piece()

# ========== 更新循环 ==========

## 返回 buff 选择界面的按键映射名（project.godot → 输入映射 里的动作名）
## 默认 "ExitPress"（绑定 ESC，physical_keycode=4194305）。改成别的键只需改这个映射。
const BOT_EXIT_ACTION := "ExitPress"
## 游戏内按该映射返回 buff 选择界面（可在 Inspector 改路径）
@export var buff_scene_path: String = "res://Tscns/buff_chose_area.tscn"
## 防止一帧内重复触发返回
var _leaving_to_buff: bool = false
## 映射缺失时只警告一次
var _exit_action_warned: bool = false


## 按 ExitPress 映射返回 buff 选择界面。
## 用 _unhandled_input 而不是 _process 轮询：一旦以后游戏里加了 UI（暂停菜单等），
## 被 UI 消费掉的按键不会再触发返回。
func _unhandled_input(event: InputEvent) -> void:
	if _leaving_to_buff:
		return
	if not InputMap.has_action(BOT_EXIT_ACTION):
		if not _exit_action_warned:
			_exit_action_warned = true
			push_warning("[退出] 项目设置里没有输入映射 \"%s\"，返回 buff 界面功能不可用（请到 项目设置 → 输入映射 添加）"
				% BOT_EXIT_ACTION)
		return
	if not event.is_action_pressed(BOT_EXIT_ACTION):
		return
	get_viewport().set_input_as_handled()
	return_to_buff_scene()


## 返回 buff 选择界面：与结算界面 BACK 按钮同一套语义
## （标记恢复上次勾选、不重置 stats），并先停掉 bot 子进程。
func return_to_buff_scene() -> void:
	if _leaving_to_buff:
		return
	_leaving_to_buff = true
	# 先把时间缩放还原，避免把 20 倍速带到 buff 界面/主菜单
	_restore_time_scale()
	# 显式停掉 zzz worker：场景销毁时也会停，这里保证返回瞬间就释放子进程
	if _zzz_bridge != null:
		_zzz_bridge.stop()
		_zzz_bridge = null
	TetrisGlobalData.restore_buffs = true
	get_tree().change_scene_to_file(buff_scene_path)


## 开启快速模拟：帧数换算式加速（Engine.time_scale），并把 vsync/帧率上限解除。
## 由 TetrisGlobalData.apply_init_data() 在「FastSimulate 且 BotMode」时调用。
func enable_fast_simulate() -> void:
	fast_simulate = true
	# 桥可能在本函数之前就已经建好了（bot 在 apply_init_data 里就开始跑）→ 这里补一次思考预算
	if fast_simulate_think_budget > 0 and _zzz_bridge != null:
		_zzz_bridge.think_budget = fast_simulate_think_budget
	Engine.time_scale = maxf(fast_simulate_speed, 0.01)
	# 垂直同步会把实际帧率钉在 60，进而把加速倍数压回 60 → 关掉并放开帧率上限
	_fast_simulate_prev_max_fps = Engine.max_fps
	Engine.max_fps = 0
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_fast_simulate_vsync_off = true
	print("[FastSim] 快速模拟开启：time_scale=%.1f（一帧 = %.1f 帧游戏时间），vsync=%s"
		% [Engine.time_scale, Engine.time_scale,
		"关闭" if _fast_simulate_vsync_off else "原本已关闭"])


## 还原时间缩放与垂直同步（退出场景 / 返回 buff 界面 / 结算时都要调）
func _restore_time_scale() -> void:
	if not fast_simulate:
		return
	fast_simulate = false
	Engine.time_scale = 1.0
	Engine.max_fps = _fast_simulate_prev_max_fps
	if _fast_simulate_vsync_off:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		_fast_simulate_vsync_off = false


## 等决策期间的时间缩放：
##   fast_simulate_freeze_wait = true  → 0.001（冻结，等决策不计入游戏时间）
##   fast_simulate_freeze_wait = false → 1.0（**实时**，游戏照常跑，等决策计入游戏时间）
## 注意这里刻意**不用 fast_simulate_speed**：实时模式下我们没有"在等"，不该把时间加速，
## 否则等决策的 100ms 会被放大成 2 秒游戏时间，方块会在计划到手前就冲到底。
func _decision_wait_time_scale() -> float:
	if fast_simulate_freeze_wait:
		return DECISION_WAIT_TIME_SCALE
	return 1.0


## 快速模拟下，等待外部 zzz worker 决策期间调整时间缩放。
## 默认（fast_simulate_freeze_wait=false）改为**实时运行**：不再冻结，避免"一顿一顿"。
## 打开 fast_simulate_freeze_wait 才退回冻结行为（快速模拟下能贴住 3pps，但会有可见停顿）。
func _set_decision_wait_scale(waiting: bool) -> void:
	if not fast_simulate:
		return
	# 用很小的正数而不是 0：Engine.time_scale = 0 容易在某些内部除法里出问题，
	# 0.001 已等价于冻结（一帧只推进千分之一帧的游戏时间）。
	var want: float = _decision_wait_time_scale() if waiting else maxf(fast_simulate_speed, 0.01)
	if not is_equal_approx(Engine.time_scale, want):
		Engine.time_scale = want


func _exit_tree() -> void:
	# 切场景（结算 / 返回 buff / 退出）时务必还原，否则会把 20 倍速带到别的界面
	_restore_time_scale()
	# 从公共数据区注销，避免它继续持有本节点（场景切换后引用必须清空）
	TetrisGlobalData.unregister_node(self)


func _process(delta):
	# 游戏时钟：只累计「游戏内真正流逝」的时间（delta 已含 Engine.time_scale；
	# 快速模拟等决策期间缩放被压到 0.001 → 那段等待不计入，PPS 才能保持 3pps）。
	_game_clock += delta
	_stats_accum += delta
	if bot_mode:
		_process_bot_control(delta)
		# 原生决策等待期间 **以及计划执行期间** 都暂停重力下落：
		# bot 的移动序列（含旋转踢墙）是按「方块仍在原高度」规划的相对移动，若执行途中方块持续下落，
		# 旋转踢墙会在错误高度触发、还可能提前触底被锁死 → 实际落点与决策不一致（missdrop）。
		# 只有「既没在等决策、也没有待执行计划」时才让重力接管（worker 不可用时的兜底）。
		if _zzz_bridge == null or (not _zzz_bridge.is_waiting_decision() and not _zzz_bridge.is_plan_active()):
			gravity_drop()
		return
	
	# if not replay_input_override:  # 回放系统已禁用
	change_key_press_to_var()
	#TODO::回放系统模拟按键输入
	replay_set_keyvar_input()
	_process_input()
	check_for_var_single_press()
	gravity_drop()

## 由 buff 下发的 zzz AI 参数覆盖（ExtraBotChange：Param 字段名 → 值）
var bot_param_overrides: Dictionary = {}
## 等待 worker 决策的起始真实时间戳（ms），0 = 当前没在等；看门狗用它判断超时
var _bot_wait_start_ms: int = 0
const BOT_WAIT_TIMEOUT := 3.0
## bot 决策日志次数上限
## （原先按步打印计划时会用这个预算限流；现在改成「每块只打印一次计划」，预算已无用，故删除）
## 进入 bot 循环的一次性日志标记 / 无方块空转计时
var _bot_loop_logged: bool = false
var _bot_idle_log_time: float = 0.0
## 诊断计时：最近一次请求决策的时刻 / 最近一次锁定的时刻（毫秒）
var _bot_t_req_ms: int = 0
var _bot_t_lock_ms: int = 0
## zzz 桥脚本路径（按路径加载而不是依赖 class_name，避免编辑器类名缓存未刷新时找不到 ZzzBridge）
const ZZZ_BRIDGE_SCRIPT := "res://Scripts/bot_play/zzz_bridge.gd"
var _zzz_bridge_error_logged := false

func _ensure_zzz_bridge() -> void:
	if _zzz_bridge != null:
		return
	var script: GDScript = load(ZZZ_BRIDGE_SCRIPT)
	if script == null:
		if not _zzz_bridge_error_logged:
			_zzz_bridge_error_logged = true
			push_error("[ZzzBridge] 无法加载 " + ZZZ_BRIDGE_SCRIPT)
		return
	_zzz_bridge = script.new()
	# 桥的「启动/信息」日志跟随本节点的 bot_debug_log（默认关闭，避免刷屏）
	_zzz_bridge.verbose = bot_debug_log
	# 快速模拟：可把 worker 思考预算调低（0 = 不干预）。
	# CFG 在每次 request_plan() 里重建并比对，所以这里改完下一块就会带上新的预算。
	if fast_simulate and fast_simulate_think_budget > 0:
		_zzz_bridge.think_budget = fast_simulate_think_budget
	add_child(_zzz_bridge)
	# 把已收集的参数覆盖补发给新桥（buff 可能在本节点之前就已处理）
	if not bot_param_overrides.is_empty():
		_zzz_bridge.set_param_overrides(bot_param_overrides)

## 设置 zzz AI 参数覆盖（由 TowerController 依据 ExtraBotChange 调用）
func set_bot_param_overrides(d: Dictionary) -> void:
	bot_param_overrides = d.duplicate()
	if _zzz_bridge != null:
		_zzz_bridge.set_param_overrides(bot_param_overrides)

func _process_bot_control(delta: float) -> void:
	_ensure_zzz_bridge()
	if _zzz_bridge == null:
		return
	if not _zzz_bridge.using_native_cc() and not _zzz_bridge_error_logged:
		_zzz_bridge_error_logged = true
		push_error("[ZzzBridge] zzztoj worker 未就绪 → bot 会退化为「每块直接硬降」（请看上面的 ZzzBridge 报错定位 worker 路径）")
	if bot_debug_log and not _bot_loop_logged:
		_bot_loop_logged = true
		# 规则摘要：排查「同一套 bot 在不同模式表现差异很大」时，先看这一行确认当时生效的规则。
		var _cl_sum = TetrisGlobalData.clear_line_controller
		var _gc_sum = TetrisGlobalData.garbage_line_controller
		print("[BotLoop] bot_mode=", bot_mode, " native=", _zzz_bridge.using_native_cc(),
			" 变速=", bot_dynamic_pps, " pps=", bot_target_pps, "(基础) 高度=", _bot_board_height(),
			" 缓冲垃圾=", _bot_buffered_garbage_rows(),
			" 当前pps=", _bot_current_pps(),
			" 每块间隔=", _get_bot_piece_interval(),
			" 每步间隔=", _get_bot_action_interval(), " 原生每步间隔=", bot_native_action_interval)
		print("[BotRule] 旋转系统=", int(TetrisGlobalData.piece_rotation_system), " no_spin=", (int(TetrisGlobalData.clear_no_spin) if _cl_sum else -1),
			" tetris_allspin=", (int(TetrisGlobalData.clear_allspin) if _cl_sum else -1),
			" btb_system=", (int(TetrisGlobalData.clear_btb_system_use) if _cl_sum else -1),
			" pc_damage=", (int(TetrisGlobalData.clear_pc_damage) if _cl_sum else -1),
			" gcap=", (int(TetrisGlobalData.garbage_cap) if _gc_sum else -1),
			" 可见next=", (_zzz_bridge.visible_next_count(self) if _zzz_bridge else -1),
			" think=", (_zzz_bridge.think_budget if _zzz_bridge else -1),
			" hold=", (_zzz_bridge.allow_hold if _zzz_bridge else true),
			" 快速模拟=", fast_simulate, " 整段计划同帧=", fast_simulate_whole_plan,
			" 直接放置=", fast_simulate_direct_place,
			" 时间缩放=", Engine.time_scale)
	if TetrisGlobalData.piece_shape.is_empty():
		# 无活动方块时 bot 不会请求决策
		_bot_idle_log_time += delta
		return
	_bot_idle_log_time = 0.0

	if _bot_piece_cooldown > 0.0:
		_bot_piece_cooldown = max(0.0, _bot_piece_cooldown - delta)

	if _bot_next_action_time > 0.0:
		_bot_next_action_time = max(0.0, _bot_next_action_time - delta)
		return

	# 新块开始：请求新的原生 ColdClear 决策
	if _bot_tracking_piece_serial != _bot_piece_serial:
		_bot_tracking_piece_serial = _bot_piece_serial
		if _zzz_bridge.using_native_cc():
			_bot_t_req_ms = Time.get_ticks_msec()
			_bot_note_plan_request()
			_zzz_bridge.request_plan(self)

	# 垃圾行抬升期间版面已变化（force_raise_rows 已递增 board_version）。
	# 注意：垃圾上涨是整版（含当前方块）同步上移（force_raise_rows 会把当前方块一并上移），
	# 因此当前方块相对堆叠的落点与形状不变，其正在执行的旧计划（相对移动序列）依然有效。
	# 若在此打断并重新规划，新计划按“方块在 spawn 位”生成，而方块实际已移动/已按旧计划走了
	# 若干步，会导致当前块 missdrop。所以仅当本块完全没有计划（如首次请求失败）时，才基于
	# 新版面重试；否则继续执行旧计划，待本块锁定后由“新块开始”逻辑按新版面请求。
	if TetrisGlobalData.garbage_line_controller != null and _bot_tracking_board_version != TetrisGlobalData.garbage_board_version:
		_bot_tracking_board_version = TetrisGlobalData.garbage_board_version
		# 避免请求堆积：若已有在途决策（正在等待），交给其完成后自然对账；否则才重新请求。
		if _zzz_bridge.using_native_cc() and not _zzz_bridge.is_waiting_decision():
			if _zzz_bridge.is_plan_empty():
				_bot_note_plan_request()
				_zzz_bridge.request_plan(self)

	# 等待原生 zzz 异步决策期间，暂停动作（带看门狗：worker 卡死时复位，避免整局冻结）
	if _zzz_bridge.using_native_cc() and _zzz_bridge.is_waiting_decision():
		# 时间缩放按 fast_simulate_freeze_wait 决定：false（默认）= 实时运行不冻结，
		# true = 压到 0.001，等决策不计入游戏时间。
		# ⚠ 这里不能再用 fast_simulate_freeze_wait 做外层守卫：关掉冻结时也需要把缩放从
		#   fast_simulate_speed 拉回 1.0，否则等决策的 100ms 会被放大成 2 秒游戏时间。
		_set_decision_wait_scale(true)
		# 看门狗等的是**外部进程**，所以直接用真实时间戳判断：
		# 不受 Engine.time_scale / delta 语义影响（时钟冻结时 delta≈0，拿 delta 计时会失真）。
		if _bot_wait_start_ms == 0:
			_bot_wait_start_ms = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _bot_wait_start_ms >= int(BOT_WAIT_TIMEOUT * 1000.0):
			_bot_wait_start_ms = 0
			_zzz_bridge.reset_for_stall()
			push_warning("[ZzzBridge] 等待决策超过 %.1fs → 复位桥状态（本块直接硬降）" % BOT_WAIT_TIMEOUT)
		return
	_bot_wait_start_ms = 0
	_set_decision_wait_scale(false)

	# 落块自检用：垃圾抬升补偿量 = 计划确认后版面高度增加的行数。
	# 抬升会把整版（含当前方块）一起上移，所以高度差就等于「实际 y 应比计划 y 小多少」。
	# 只在本块有计划时统计（_bot_check_plan_height >= 0），避免把上一块的消行算进来。
	if _bot_check_plan_height >= 0:
		var h_now: int = _bot_board_height()
		if h_now > _bot_check_plan_height:
			_bot_check_rise += h_now - _bot_check_plan_height
		_bot_check_plan_height = h_now

	# 决策参数签名变化（旋转系统 / 垃圾上限 / BTB / PC / NoSpin / hold / 180…）：
	# 关卡或 buff 的字段可能在 bot 已发出第一份请求之后才生效，那份计划是按旧参数搜的，
	# 里面可能含游戏做不出的踢墙（实测 RotateSystem_3 关卡：首次 CFG kick=0，随后才是 kick=3）。
	# 检测到变化就作废旧计划，并对**当前方块**重新请求（REQ 带的是当前方块实际格子与朝向，重算安全）。
	var cfg_sig: String = _bot_cfg_signature_now()
	if cfg_sig != _bot_cfg_signature:
		var is_first: bool = _bot_cfg_signature.is_empty()
		_bot_cfg_signature = cfg_sig
		if not is_first:
			_bot_cfg_stale = true
			_zzz_bridge.clear_plan()
	if _bot_cfg_stale:
		# 若还有在途决策，等它回来后再重算（此时不能并发发第二条 REQ，否则回复会错位）
		if not _zzz_bridge.is_waiting_decision():
			_bot_cfg_stale = false
			_zzz_bridge.clear_plan()
			if _zzz_bridge.using_native_cc():
				_bot_t_req_ms = Time.get_ticks_msec()
				_bot_note_plan_request()
				_zzz_bridge.request_plan(self)
				return

	# 无可用原生计划（原生不可用/决策失败/计划已消费）时，直接硬降锁定当前块
	if not _zzz_bridge.using_native_cc() or not _zzz_bridge.has_plan():
		if _bot_piece_cooldown > 0.0:
			_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
			return
		hard_drop()
		_bot_piece_cooldown = _get_bot_piece_interval()
		return

	# 新计划到手：按落点预测本手是否消行（动态 PPS 的乘数用），每块只算一次
	if _bot_pps_plan_serial != _bot_piece_serial:
		_bot_pps_plan_serial = _bot_piece_serial
		_bot_pps_plan_clears = _plan_target_will_clear(_zzz_bridge.get_plan_target())
		# 节奏归属：用**本手自己的 pps** 定出本手的「理想锁定时刻」。
		# 基准取「上一块的理想锁定时刻」（_bot_lock_base_game），不取实际锁定时刻：
		# 实际锁定比理想晚最多一帧的游戏时长，若按实际时刻往后排，误差会逐块累积 → PPS 被稀释。
		# 落在理想网格上后，长期平均严格等于 bot_target_pps（快速模拟下也能贴住 3pps）。
		var base: float = _bot_lock_base_game if _bot_lock_base_game >= 0.0 else _game_clock
		_bot_lock_target_game = base + _get_bot_piece_interval()
		_bot_piece_cooldown = maxf(0.0, _bot_lock_target_game - _game_clock)

	# 快速模拟专用：把「本手剩下的全部动作」在一帧内跑完（不走每帧一步的节奏等待）。
	# 与逐步执行走的是同一套 _apply_bot_action()，所以位置/朝向/旋转记录与正常对局完全一致
	# （spin 判定看的是「最后一次旋转的位置」，逐步操作是每帧转一次、这里是同帧连续转，
	#   两者的旋转发生位置相同 → 判定结果相同）。
	if fast_simulate and fast_simulate_whole_plan:
		_fast_sim_run_whole_plan()
		return

	# 快速模拟专用：拿到计划后直接按决策落点放置（不走逐步操作）。
	# ⚠ 默认关闭：它把旋转记录写在**落点**上，而正常对局写的是「最后一次旋转真正发生的位置」，
	#   本作 spin 判定读的正是后者（四方向不可移动才判 Spin）→ 会造成 spin 误判（偏多）。
	#   需要「位置精确但能容忍 spin 记录偏差」的极速场景才打开它。
	if fast_simulate and fast_simulate_direct_place and _fast_sim_try_direct_place():
		return

	# 执行计划中的下一个动作
	var decided_action: BotAction = _zzz_bridge.next_plan_action()
	if decided_action == null or String(decided_action.move).is_empty():
		decided_action = BotAction.new("hard_drop", ["hard_drop"], "hard_drop")

	# PPS限制核心：未到每块最小间隔前，阻止hard_drop锁定新块。
	if _bot_piece_cooldown > 0.0 and decided_action.move == "hard_drop":
		_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
		return

	_apply_bot_action(decided_action)

	if decided_action.move == "hard_drop":
		_bot_piece_cooldown = _get_bot_piece_interval()

	var action_interval: float = _get_bot_action_interval()
	if action_interval > 0.0:
		_bot_next_action_time = min(action_interval, bot_native_action_interval) if action_interval > 0.0 else bot_native_action_interval


## 快速模拟：把当前计划的剩余动作在**同一帧**里全部执行完（含最后的硬降）。
## · 与逐步执行共用 _apply_bot_action()，因此踢墙、消行、spin 记录（最后一次旋转的位置）
##   都与正常对局一致 —— 这也是它比「直接放置」更还原的原因；
## · 仍然遵守 PPS 节奏：未到本手的理想锁定时刻时，先只做「移动/旋转」不硬降，
##   到点了才硬降锁定（移动/旋转不产生新块，不影响 pps）。
func _fast_sim_run_whole_plan() -> void:
	if _zzz_bridge == null:
		return
	# 每块最多执行的动作数（防御：计划异常时不要在一帧里死循环）
	var guard: int = 0
	while _zzz_bridge.has_plan() and guard < 200:
		guard += 1
		var action: BotAction = _zzz_bridge.next_plan_action()
		if action == null or String(action.move).is_empty():
			break
		if String(action.move) == "hard_drop":
			# 硬降受 pps 节奏约束：没到点就把这一步留着（计划已消费，改为直接等待）
			if _bot_piece_cooldown > 0.0:
				_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
				return
			hard_drop()
			_bot_piece_cooldown = _get_bot_piece_interval()
			return
		_apply_bot_action(action)
	# 计划走完但没有 hard_drop：按 pps 节奏收尾（等冷却结束再硬降）
	if _bot_piece_cooldown > 0.0:
		_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
		return
	hard_drop()
	_bot_piece_cooldown = _get_bot_piece_interval()

## 快速模拟专用落块：直接把当前方块放到决策给的落点/朝向，然后立刻锁定，返回 true。
## 落点口径与 worker 回复一致（见 zzz_bridge._parse_reply）：
##   x = 方块占用格的最左列，y = 最低行，rot = 本游戏旋转系统下的旋转索引。
## 返回 false = 这次不能用直接放置（目标无效 / 块不符 / 目标处放不下），交回原有逐步流程。
func _fast_sim_try_direct_place() -> bool:
	if _zzz_bridge == null or TetrisGlobalData.piece_shape.is_empty():
		return false
	var tgt: Dictionary = _zzz_bridge.get_plan_target()
	if tgt.is_empty() or not bool(tgt.get("valid", false)):
		return false
	var tgt_piece: String = String(tgt.get("piece", ""))
	# 目标块不是手上这块（典型是计划带 hold）：先按原流程把 hold 这一步做掉，
	# 下一帧手上就是目标块了，再走直接放置。
	if not tgt_piece.is_empty() and tgt_piece != TetrisGlobalData.piece_type:
		if _zzz_bridge.plan_wants_hold() and TetrisGlobalData.piece_can_hold and not TetrisGlobalData.no_hold:
			hold_current_piece()
			return true
		return false
	# PPS 节奏：与逐步流程里的 hard_drop 一致，未到每块最小间隔就先等
	if _bot_piece_cooldown > 0.0:
		_bot_next_action_time = min(_bot_piece_cooldown, 0.05)
		return true
	# 1) 按计划的旋转序列推出目标朝向（踢墙只改位置、不改形状，所以与逐步执行的朝向一致）。
	#    旋转索引也按游戏自己的 _calc_rotation_index 推 —— worker 回报的 rot 编号与游戏不一致
	#    （实测同一落点会出现 0 vs 2 这种 ±2 偏差），所以绝不能拿它直接覆盖 current_rotation_index。
	var rots: Array = _zzz_bridge.plan_rotation_directions()
	var shape: Array = TetrisGlobalData.piece_shape.duplicate(true)
	var rot_index: int = TetrisGlobalData.piece_rotation_index
	for dir: int in rots:
		shape = _get_rotated_matrix(shape, dir)
		rot_index = _calc_rotation_index(rot_index, dir)
	var cells: Array = get_piece_cells(shape, Vector2i.ZERO)
	if cells.is_empty():
		return false
	var min_x: int = 999
	var max_y: int = -999
	for c: Vector2i in cells:
		min_x = mini(min_x, c.x)
		max_y = maxi(max_y, c.y)
	var new_pos := Vector2i(int(tgt["x"]) - min_x, int(tgt["y"]) - max_y)
	# 2) 目标处必须放得下（自身旧格子视为空）——放不下说明口径对不上，交回逐步流程，避免直接放置出非法局面
	var self_cells: Array = get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position)
	if collides_at(new_pos, shape, self_cells):
		return false
	# 3) 瞬移到目标朝向/位置，并补记一次旋转事件：
	#    spin 判定看的是「最后一次旋转的位置」，直接放置等价于「在落点处完成最后一次旋转」；
	#    不补记的话 T-spin 之类判定会全部丢失（这部分是直接放置与逐步执行唯一的语义差异）。
	clear_current_piece()
	TetrisGlobalData.piece_shape = shape
	TetrisGlobalData.piece_position = new_pos
	TetrisGlobalData.piece_rotation_index = rot_index
	redraw_current_piece()
	if not rots.is_empty() and TetrisGlobalData.clear_line_controller:
		TetrisGlobalData.clear_line_controller.record_rotation(TetrisGlobalData.piece_type, TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position, current_color)
	_check_underground_touch()
	refresh_shadow()
	# 4) 触底锁定：复用原有锁定 / 消行 / 统计 / 垃圾 / 出块流程
	hard_drop()
	_bot_piece_cooldown = _get_bot_piece_interval()
	return true


## 把 CC 决策出的动作（BotAction）映射到游戏内直接调用
func _apply_bot_action(action: BotAction) -> void:
	if action == null:
		return
	match String(action.move):
		"left":
			move_left()
		"right":
			move_right()
		"left_wall":
			# zzztoj 的 'L'：一直左移到墙（本游戏 ARR=0 也是滑到墙）
			while _try_move(-1, 0):
				pass
		"right_wall":
			while _try_move(1, 0):
				pass
		"down_one":
			# zzztoj 的 'd'：下移一格
			@warning_ignore("return_value_discarded")
			_try_move(0, 1)
		"rotate_left":
			rotate_left()
		"rotate_right":
			rotate_right()
		"rotate_180":
			rotate_180()
		"soft_drop":
			# ColdClear 的 'D'(CC_DROP) 在引擎里是 PieceMovement::SonicDrop（直接下落到触底），
			# 本游戏软降默认也是直接触底（softdrop_delay==0 → 一路 drop 到底），所以用
			# soft_drop_to_bottom() 完全对应。CC 的 'D' 通常出现在路径末尾（或由最后 hard_drop
			# 兜底触底），因此这样映射不会造成误放置；若计划中段出现 'D'，会先触底再继续横移，
			# 此时需保证已落在堆叠上（CC 搜索不会生成触底后还需横移的路径）。
			soft_drop_to_bottom()
		"hold":
			hold_current_piece()
		"hard_drop":
			hard_drop()

func _get_bot_action_interval() -> float:
	if bot_target_pps <= 0.0:
		return 0.0
	# 目标为每秒可完成的方块数，简单换算为每步动作节奏上限
	return 1.0 / max(_bot_current_pps() * 4.0, 0.001)

func _get_bot_piece_interval() -> float:
	if bot_target_pps <= 0.0:
		return 0.0
	return 1.0 / max(_bot_current_pps(), 0.001)

# ---------------------------------------------------------------------------
# 动态 PPS
# ---------------------------------------------------------------------------
## 当前版面高度（行）：空版面 = 0；只统计已锁定方块，排除当前活动方块。
## 缓存键 = （当前方块序号, board_version）：方块序号在每个新块（含锁定/消行后）递增，
## 而 board_version 只在垃圾抬升时递增 —— 两者一起覆盖「堆叠发生变化」的所有时机；
## 活动方块自身的移动/旋转不改变堆叠高度，无需失效。
func _bot_board_height() -> int:
	var ver: int = int(TetrisGlobalData.garbage_board_version) if TetrisGlobalData.garbage_line_controller != null else 0
	if _bot_height_cache >= 0 and _bot_height_cache_ver == ver and _bot_height_cache_serial == _bot_piece_serial:
		return _bot_height_cache
	var play_h: int = int(TetrisGlobalData.board_playable_height)
	var self_cells := {}
	if not TetrisGlobalData.piece_shape.is_empty():
		for c in get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position):
			self_cells[c] = true
	var height := 0
	for y in range(play_h):
		for x in range(int(TetrisGlobalData.board_grid_width)):
			if self_cells.has(Vector2i(x, y)):
				continue
			if TetrisGlobalData.board_get_cell(x, y) != null:
				height = play_h - y          # 行 89 → 高度 1，空版面 → 0
				break
		if height > 0:
			break
	_bot_height_cache = height
	_bot_height_cache_ver = ver
	_bot_height_cache_serial = _bot_piece_serial
	return height

## 缓冲中的垃圾行数（动态 PPS 用）；没有垃圾控制器时为 0
func _bot_buffered_garbage_rows() -> int:
	if TetrisGlobalData.garbage_line_controller == null:
		return 0
	return int(TetrisGlobalData.garbage_line_controller.get_buffered_garbage_rows())

## 发出一次决策请求前调用：记录落块自检的基准。
## 基准必须是「请求那一刻」的版面高度 —— worker 思考期间垃圾可能已经上涨，
## 那段抬升发生在请求之后，计划落点自然不含它，锁定自检时要补偿掉
## （垃圾上涨是整版含当前方块一起上移，所以实际落点 y 会正好小这么多）。
func _bot_note_plan_request() -> void:
	_bot_check_plan_height = _bot_board_height()
	_bot_check_rise = 0
	# 思考预算逐 REQ 下发到 bridge.think_budget_now。
	# 默认已经固定成 100ms（ratio=1.0、min=max=100），所以这里的计算事实上是恒等的；
	# 保留计算逻辑是为了还能用 ratio/max 切回动态预算（见上面 @export 的说明）。
	if _zzz_bridge != null:
		var interval_ms: float = 1000.0 / maxf(0.1, _bot_current_pps())
		_zzz_bridge.think_budget_now = clampi(
			int(interval_ms * bot_think_budget_ratio), bot_think_budget_min, bot_think_budget_max)


## 影响 worker 决策的参数签名（与 zzz_bridge._build_cfg 下发的字段一一对应）。
## 只要这份签名变了，之前算出的计划就必须作废：踢墙表/伤害模型/Spin 规则都可能已经不同。
## 注意：allow_hold / allow_180 / think_budget 是**桥**的 @export（CFG 用它们拼字段），
## 控制器本身只有 no_hold，别在这里直接写 allow_hold / allow_180。
func _bot_cfg_signature_now() -> String:
	var gcap := 0
	if TetrisGlobalData.garbage_line_controller != null:
		gcap = int(TetrisGlobalData.garbage_cap)
	var btb := 0
	var pc := 0
	var nospin := 0
	var nospin_rows := 0
	if TetrisGlobalData.clear_line_controller != null:
		btb = int(TetrisGlobalData.clear_btb_system_use)
		pc = int(TetrisGlobalData.clear_pc_damage)
		nospin = int(TetrisGlobalData.clear_no_spin)
		nospin_rows = int(TetrisGlobalData.clear_no_spin4_solid_rows)
	var hold_flag := 1
	var allow180_flag := 1
	var think := 0
	if _zzz_bridge != null:
		hold_flag = 1 if (_zzz_bridge.allow_hold and not TetrisGlobalData.no_hold) else 0
		allow180_flag = 1 if _zzz_bridge.allow_180 else 0
		think = int(_zzz_bridge.think_budget)
	# bot 可用的 next 个数：现行策略是**恒定全部可知**，不再随短见收敛。
	# ⚠ 单一来源是 ZzzBridge.bot_next_max()（常量本体在 bot_play/zzz_bridge.gd 的 NEXT_MAX）：
	#   以前这里写死字面量 14，一旦桥的上限被调整，签名就会和实际下发的 next_visible 不一致，
	#   而签名的作用正是「参数一变就作废旧计划」——不一致等于签名失效。
	#   这里优先问实例，实例还没建时退回静态方法（bot_next_max 是 static，不需要实例）。
	var next_vis := 0
	if _zzz_bridge != null:
		next_vis = int(_zzz_bridge.visible_next_count(self))
	else:
		next_vis = ZzzBridge.bot_next_max()
	# ⚠ think 不再进入签名：思考预算现在按 PPS 逐 REQ 动态规划（bridge.think_budget_now），
	#   若留在签名里，每块预算一变就会作废旧计划、陷入"重算循环"。
	think = 0
	# Allspin 模式（0/1/2）与 Allspin_2 的实心行数：都会改变评估口径
	# （void 断 BTB、Spin0 续 BTB、重复惩罚只比行数、罚多少行实心垃圾）→ 变了要重算
	var allspin_mode := 0
	var allspin2_rows := 20
	if TetrisGlobalData.clear_line_controller != null:
		allspin_mode = int(TetrisGlobalData.clear_allspin)
		allspin2_rows = int(TetrisGlobalData.clear_allspin2_solid_rows)
	# 快速模拟的执行路径也影响 worker 口径（直接放置会在落点补记旋转）→ 变了要重算。
	# 用「实际生效的路径」编码：0=非直接放置（含整段计划同帧 / 非快速模拟），1=直接放置。
	var place_mode := 0
	if fast_simulate and not fast_simulate_whole_plan and fast_simulate_direct_place:
		place_mode = 1
	return "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
		int(TetrisGlobalData.piece_rotation_system), gcap, btb, pc, nospin, nospin_rows,
		hold_flag, allow180_flag, think, next_vis, allspin_mode, allspin2_rows, place_mode,
	]

## 当前生效的 bot PPS
##   = （基础 pps + 高度偏移 + 缓冲垃圾加成） × 堆叠侧乘数，且不低于 bot_pps_min
##   bot_dynamic_pps = false 时不做任何变速，直接返回基础 bot_target_pps。
func _bot_current_pps() -> float:
	if not bot_dynamic_pps:
		return bot_target_pps
	# 快速模拟：默认保留动态变速（与正常对局同一套节奏）。
	# 只有显式打开 fast_simulate_fixed_pps 时才忽略变速、走固定 bot_target_pps。
	if fast_simulate and fast_simulate_fixed_pps:
		return bot_target_pps
	var h: int = _bot_board_height()
	var pps: float = bot_target_pps + float(h - bot_pps_height_ref) * bot_pps_height_step
	# 缓冲垃圾加成：有垃圾处于缓冲，且「版面高度 + 缓冲垃圾高度」超过阈值时，每多 1 高 +0.1
	var buf: int = _bot_buffered_garbage_rows()
	if buf > 0 and h + buf > bot_pps_garbage_threshold:
		pps += float(h + buf - bot_pps_garbage_threshold) * bot_pps_garbage_step
	# 堆叠侧：不消行（继续堆叠）加速赶节奏，消行则降速稳一手
	pps *= bot_pps_noclear_mul if not _bot_pps_plan_clears else bot_pps_clear_mul
	return maxf(pps, bot_pps_min)

## 判断「按给定落点落块后是否会消行」。
## 落点口径与 worker 返回一致：x = 最左格，y = 最低格，rot = 出生态起顺时针次数。
func _plan_target_will_clear(tgt: Dictionary) -> bool:
	if tgt.is_empty() or not tgt.get("valid", false):
		return false
	var ptype: String = str(tgt.get("piece", ""))
	if ptype.is_empty() or TetrisGlobalData.bag_controller == null:
		return false
	var m: Array = TetrisGlobalData.bag_controller.get_original_shape(ptype)
	if m.is_empty():
		return false
	for _i in range(int(tgt.get("rot", 0)) % 4):
		m = _get_rotated_matrix(m, 1)
	# 取占位格并平移到目标落点（最左格 = x，最低格 = y）
	var cells: Array = []
	var minx := 99
	var maxy := -99
	for yy in range(m.size()):
		for xx in range(m[yy].size()):
			if m[yy][xx] == 1:
				cells.append(Vector2i(xx, yy))
				minx = mini(minx, xx)
				maxy = maxi(maxy, yy)
	if cells.is_empty():
		return false
	var dx: int = int(tgt.get("x", 0)) - minx
	var dy: int = int(tgt.get("y", 0)) - maxy
	var placed := {}
	var rows := {}
	for c in cells:
		var p := Vector2i(c.x + dx, c.y + dy)
		placed[p] = true
		rows[p.y] = true
	# 当前活动方块所在格视为空（与 _check_perfect_clear 的口径一致）
	var self_cells := {}
	if not TetrisGlobalData.piece_shape.is_empty():
		for c in get_piece_cells(TetrisGlobalData.piece_shape, TetrisGlobalData.piece_position):
			self_cells[c] = true
	for ry in rows.keys():
		var full := true
		for x in range(int(TetrisGlobalData.board_grid_width)):
			var p := Vector2i(x, ry)
			if placed.has(p) or self_cells.has(p):
				continue
			if TetrisGlobalData.board_get_cell(x, ry) == null:
				full = false
				break
		if full:
			return true
	return false

## 处理键盘输入
func _process_input():
	# 手上无方块（生成/消行延迟期间）：不处理输入，避免对空方块执行旋转/暂存/硬降
	if TetrisGlobalData.piece_shape.is_empty():
		return
	#arr和das判定
	if press_key["LeftMove"] == 1 and press_key["RightMove"] == 1:
		if not double_press:
			direction_press *= -1
			move_start_timer.paused = true
			move_keep_timer.stop()
			keep_press_move = false
		double_press = true
	else:
		double_press = false
		if press_key["LeftMove"] == 1:
			if direction_press == 1:
				move_start_timer.paused = true
				move_keep_timer.stop()
				keep_press_move = false
			direction_press = -1
		if press_key["RightMove"] == 1:
			if direction_press == -1:
				move_start_timer.paused = true
				move_keep_timer.stop()
				keep_press_move = false
			direction_press = 1
		if not (press_key["LeftMove"] == 1 or press_key["RightMove"] == 1):
			direction_press = 0
	# 左右移动
	if direction_press != 0:
		if move_arr != 0:
			if move_start_timer.is_stopped() and move_keep_timer.is_stopped():
				@warning_ignore("return_value_discarded")
				_try_move(direction_press, 0)
				move_keep_timer.start()
		else:
				if move_start_timer.is_stopped() and not keep_press_move:
					@warning_ignore("return_value_discarded")
					_try_move(direction_press, 0)
				elif move_start_timer.is_stopped() and keep_press_move and _can_move(direction_press, 0):
					var one_drop : bool = true
					while _try_move(direction_press, 0):
						if _can_move(0, 1) and one_drop and press_key["SoftDrop"] == 1:
							while _try_move(0,1) and one_drop:
								if softdrop_delay != 0:
									one_drop = false
						if gravity_drop_time == 0 and _can_move(0, 1):
							while _try_move(0,1):
								pass
				else:
					pass
	if direction_press != 0 and not keep_press_move:
		move_start_timer.paused = false
		move_start_timer.start()
		keep_press_move = true
	elif direction_press == 0:
		move_start_timer.stop()
		move_keep_timer.stop()
		keep_press_move = false
	else:
		pass
	
	# 软降
	if press_key["SoftDrop"] == 1 and softdrop_timer.is_stopped():
		if softdrop_delay != 0:
			soft_drop()
			softdrop_timer.start()
		elif softdrop_delay == 0:
			if _can_move(0, 1):
				while _try_move(0,1):
					pass
		else:
			push_error("发生意料之外的错误！")
	
	# 旋转
	if press_key["LeftSpin"] == 1 and check_for_single_press["LeftSpin"] != 1:
		rotate_left()
	
	if press_key["RightSpin"] == 1 and check_for_single_press["RightSpin"] != 1:
		rotate_right()
	
	# 180度旋转
	if press_key["SwapSpin"] == 1 and check_for_single_press["SwapSpin"] != 1:
		rotate_180()
	
	# 暂存（NoHold模式下不读取Hold输入）
	if press_key["HoldBlock"] == 1 and check_for_single_press["HoldBlock"] != 1 and not TetrisGlobalData.no_hold:
		hold_current_piece()
	
	# 硬降
	if press_key["HardDrop"] == 1 and check_for_single_press["HardDrop"] != 1:
		hard_drop()

func change_key_press_to_var():
	for i in press_key:
		if Input.is_action_pressed(i):
			press_key[i] = 1
		else:
			press_key[i] = 0

func check_for_var_single_press():
	for i in check_for_single_press:
		if press_key[i] == 1 and check_for_single_press[i] == 0:
			check_for_single_press[i] = 1
		elif press_key[i] == 0:
			check_for_single_press[i] = 0
		else:
			pass

#TODO::回放系统模拟按键输入
func replay_set_keyvar_input():
	pass

## 开启/关闭回放输入覆盖（已禁用）
# func set_replay_input_override(enabled: bool):
# 	replay_input_override = enabled
# 	change_key_press_to_var()

## 用于回放系统模拟真实按键输入（已禁用）
# func set_replay_input(action: String, pressed: bool):
# 	if not press_key.has(action):
# 		return
# 	
# 	press_key[action] = 1 if pressed else 0
# 	
# 	_process_input()
# 	
# 	if pressed and check_for_single_press.has(action):
# 		check_for_single_press[action] = 1
# 	elif not pressed and check_for_single_press.has(action):
# 		check_for_single_press[action] = 0

func gravity_drop():
	# 手上无方块（生成/消行延迟期间）：跳过下落逻辑
	if TetrisGlobalData.piece_shape.is_empty():
		return
	if gravity_timer.is_stopped() and gravity_drop_time != 0:
		@warning_ignore("return_value_discarded")
		_try_move(0,1)
		#garbage_line_controller.add_attack(5)
		gravity_timer.start()
	if gravity_drop_time == 0:
		if _can_move(0, 1):
			while _try_move(0,1):
				pass

# ========== 辅助方法 ==========

## 获取当前方块的宽度
func get_current_piece_width() -> int:
	if TetrisGlobalData.piece_shape.is_empty():
		return 0
	return TetrisGlobalData.piece_shape[0].size()

## 获取当前方块的高度
func get_current_piece_height() -> int:
	return TetrisGlobalData.piece_shape.size()

## 手动设置方块（用于扩展）
func set_piece(piece: Array, color: Color, piece_type: String = "I"):
	TetrisGlobalData.piece_shape = piece
	current_color = color
	TetrisGlobalData.piece_type = piece_type
	current_original_shape = TetrisGlobalData.bag_controller.get_original_shape(piece_type)
	spawn_new_piece()
