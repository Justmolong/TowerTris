using Godot;

/// <summary>
/// ColdClear 决策桥（自包含版本）
///
/// 本桥自己启动 coldclear_worker.exe 子进程（通过 OS.execute_with_pipe），
/// 并在后台线程执行阻塞的 GO 命令，把 ColdClear 的真实决策（移动路径）
/// 逐步转为 BotAction 供 TetrisController 消费。
/// 不再依赖外部 /root/ColdClearNative autoload（已删除）。
/// </summary>
public partial class ColdClearBridge : Node
{
    public const string WORKER_FILENAME = "coldclear_worker.exe";
    public const string DLL_FILENAME = "cold_clear.dll";
    // 开发/编辑器模式下 native 目录（res:// 直接映射项目磁盘目录）。
    public const string NATIVE_RES_DIR = "res://rust/cold_clear_engine/native";
    // 导出运行模式下 native 松散文件所在目录（exe 旁，由导出脚本复制）。
    public const string NATIVE_EXE_SUBDIR = "native";
    // ===== 冷Clear（ColdClear）搜索参数 · 控制文件：Scripts/bot_play/coldclear_bridge.gd（本文件） =====
    // 发送给 ColdClear 时，可见窗口上方额外多带的行数（堆叠余量）。仅影响决策输入窗口，不影响棋盘。
    public const int EXTRA_TOP_ROWS = 4;
    // 单次决策允许搜索的最大节点数（max_nodes）。越大越接近最优解，但耗时越久。
    public const long MAX_NODES = 40000000000L;
    // 单次决策「初始/最低」节点数（min_nodes 下限）。决策质量随节点数提升而提升。
    public const int MIN_NODES = 100000;
    // 单次决策实际下发的 min_nodes：默认用常量，若 adaptive_min_nodes 开启则按实测决策耗时
    // 自动在 [min_nodes_floor, min_nodes_cap] 内调节 —— pps 目标越低（周期越长）节点数越顶得越高，
    // pps 目标越高则自动回落以跟上节奏。
    public int _current_min_nodes = MIN_NODES;
    // 是否启用 min_nodes 自适应（按实测决策耗时贴近单块周期预算调节点数）。
    [Export]
    public bool adaptive_min_nodes = true;
    // 自适应调节器参数：
    [Export]
    public int min_nodes_floor = 30000;       // 节点数下限（保住基本决策质量）
    [Export]
    public int min_nodes_cap = 3000000;       // 节点数上限（防单次决策过度拉长/内存）
    [Export]
    public float min_nodes_target_ratio = 0.8f; // 目标：决策耗时占单块周期的比例（预留动作/调度/消行开销）
    // 自适应状态：
    public float _decision_ms_ema = -1f;      // 单次决策耗时滑动均值（毫秒）
    public int _adaptive_adjust_counter = 0;  // 每 N 次决策调整一次，避免抖动
    public float _last_decision_ms = 0f;
    // 本次请求发出时刻（毫秒）与期望单块周期（毫秒），用于实测决策耗时并调节 min_nodes
    public ulong _request_sent_ms = 0;
    public float _target_piece_interval_ms = 250f;
    public float _adapt_log_last = 0f;
    // 决策失败后的冷却时间（毫秒），避免每块都阻塞等待超时。
    public const int FAIL_COOLDOWN_MS = 100;
    // 读取 worker 回复的超时（毫秒）。worker 卡住时回退默认 bot。
    public const int READ_TIMEOUT_MS = 30000;
    public static readonly string[] PIECE_ORDER = { "I", "O", "T", "L", "J", "S", "Z" };

    // ===== 各类型消行/旋转与惩罚的决策权重（inspector 可调，随 S 命令下发，对应 Rust Standard 评估器）=====
    // 伤害表/倍率/规则开关等由 buff（get_damage_tables / get_send_mult_attack / get_mult_defend）提供，
    // 本桥不再持有这些；仅保留「各类型消行等的决策权重」与「惩罚权重」。
    // 伤害评估倍率（影响 bot 对攻击伤害的重视程度）
    [Export]
    public int eval_mult = 100;
    // 攻击效率权重（攻击效率 = 本次攻击伤害 / 本次消除行数；越大 bot 越倾向高效攻击）
    // 游戏内 T-Spin 单消 = 2伤害/1行（效率2.0）极高，开启后 bot 会按“每行伤害”排序，
    // 让 tspin1/allspin1 这类高效率攻击优先于普通四消（4/4=1.0）与双消（1/2=0.5）。
    [Export]
    public int attack_efficiency_weight = 100;
    // bot 评估权重：维持 Back-to-Back（越大越倾向维持 BTB）
    // 游戏 btb_count>1 时连续 spin/quad 每发 +1，btb_count>=4 时 +2（4BTB 以上续 BTB 收益极高），
    // 且 btb>=4 时普通消行会释放 surge_break。故把维持 BTB 权重提得很高，让 bot 尽量把
    // BTB 链延长到 4 及以上（连续 spin 也天然维持 combo，构造 BTB combo）。
    [Export]
    public int b2b_clear = 950;
    // bot 评估权重：放块后的堆叠最高点（负值=压高，越大越不压高）
    [Export]
    public int height = -90;
    // bot 评估权重：重复惩罚扣分（负值=降低该决策的选取值）
    [Export]
    public int allspin_repeat_penalty = 0;
    // 单消（1行）评估权重（负值=不倾向；普通单消会断 BTB → 参照风格下尽量不做，用 spin 替代）
    [Export]
    public int clear1 = -240;
    // 双消（2行）评估权重（普通双消断 BTB、效率低 → 深压）
    [Export]
    public int clear2 = -380;
    // 三消（3行）评估权重
    [Export]
    public int clear3 = -480;
    // bot 评估权重：四消（Tetris）。参照 bot"消4非必要则不做"：仅在垃圾/挖掘被迫时用，
    // 故保留为正但明显低于 tspin2/tspin1（I 挖掘解放能力保留）。
    [Export]
    public int clear4 = 60;
    // T-Spin 单消评估权重（伤害 2/行。参照风格下 t1 用得过多会反复扰动地形 → 权重压到
    // tspin2 之下，让 bot 在能打 t2 时优先 t2，t1 仅作为无 t2 槽时的次级选择；t1:t2 更均衡）
    [Export]
    public int tspin1 = 640;
    // T-Spin 双消评估权重（维持/修补地形时效率极高（伤害 4/行2.0）且消行更干净的选项 →
    // 提升到显著高于 tspin1，鼓励优先做 t2）
    [Export]
    public int tspin2 = 1000;
    // T-Spin 三消评估权重（伤害 6/行效率 2.0 极高，但需要深井地形；维持负向压制地形破坏）
    [Export]
    public int tspin3 = -200;
    // Mini T-Spin 单消评估权重。Mini T-Spin 单消与 allspin1（非T卡住单消）同属基础伤害级
    // （游戏里都是低/无伤害的"续链+处理地形"手段）——用宝贵的 T 去做 mini 等于浪费 T：
    // T 本该留给 full T-Spin。权重压到接近 wasted_t 的深度，使 bot 宁可 hold T 等 full 槽
    // 也不用 T 打 mini。
    [Export]
    public int mini_tspin1 = -650;
    // Mini T-Spin 双消评估权重（加深惩罚）
    [Export]
    public int mini_tspin2 = -900;
    // 非T旋转（allspinmini / 全旋）单消评估权重（参照 bot 用它大量消行/处理地形并续 B2B →
    // 上调接近 tspin1；地形干净度由 cavity/covered 惩罚兜底）
    [Export]
    public int allspin1 = 560;
    // 非T旋转（allspin）双消评估权重（参照 bot"少量 allmini2 平衡"→ 明显为正、可被选用，
    // 但远低于 tspin2 与 allspin1，避免为它破坏堆叠）
    [Export]
    public int allspin2 = 260;
    // 非T旋转（allspin）三消评估权重（压制）
    [Export]
    public int allspin3 = -380;
    // 非T旋转（allspin）消3+行（4行及以上）评估权重
    [Export]
    public int allspin3plus = -420;
    // 全消（Perfect Clear）评估权重
    [Export]
    public int perfect_clear = 0;
    // 连击（Combo）评估权重（参照 bot 靠频繁连续 spin 滚高 combo 增伤 → 上调激励连续消行）
    [Export]
    public int combo_garbage = 520;
    // 浪费 T 块（wasted T）评估权重（参照 bot T 利用率 ~100%：T 不平放、必做成 spin →
    // 大幅加深，配合 DIRECT_SPIN_BOOST 让"找 T 槽/等 T 槽"远优于平放 T）
    [Export]
    public int wasted_t = -700;
    // 移动时间评估权重
    [Export]
    public int move_time = -3;
    // ColdClear 搜索并行线程数（0 = 自动按 CPU 核数-2，最大8；>0 固定线程数）。
    // 多线程并行检索可显著加速搜索（尤其 MIN_NODES 较大时），但会占用更高 CPU。
    [Export]
    public int cc_threads = 8;

    /// <summary>请求完成信号（在主线程序发）
    /// reply 形如 "OK 0 3 L L L" / "DEAD" / "ERR &lt;msg&gt;" / "TIMEOUT"</summary>
    [Signal]
    public delegate void MoveReadyEventHandler(int request_id, string reply);

    public bool _native_available = false;
    public ulong _native_cooldown_until = 0;       // Time.get_ticks_msec() 时间戳

    public Godot.Collections.Dictionary _plan = new Godot.Collections.Dictionary();                // { hold:bool, movements:Array[String] }
    // 整条最优计划（可绘制）：每块一个元素 { "type": "I/O/T/L/J/S/Z", "cells": [[x,y] x4], "cleared_lines": [c0..c3] }
    // type 用于绘制颜色；cells 为方块最终落定的 4 格绝对坐标（CC：x 0..9，y 向上，y=0 底部；
    // 游戏 y 向下，绘制时需按 playable_height-1-y 翻转）；cleared_lines 为该落块消去的行号
    // （CC 绝对行号，-1=该槽位无消行）。plan[0] = 当前块，其后为未来各块。
    public Godot.Collections.Array cc_plan_placements = new Godot.Collections.Array();
    public int _plan_index = 0;
    public bool _plan_hold_done = false;
    public int _pending_request_id = -1;
    public int _request_id_counter = 0;
    public bool _waiting_native = false;

    // 最近一次请求时 bot 面对的当前方块 / 暂存（hold）方块（用于决策日志输出，便于排查误旋转）
    public string _last_current_piece = "-";
    public string _last_hold_piece = "-";

    // ---- worker 子进程管理 ----
    public FileAccess _stdio = null;
    public FileAccess _stderr = null;
    public bool _started = false;
    public bool _running = false;
    public Godot.GodotThread _thread = null;
    public Godot.Mutex _mutex = new Godot.Mutex();
    public Godot.Collections.Array _queue = new Godot.Collections.Array();

    /// <summary>是否正在等待原生 ColdClear 的异步决策（期间应暂停本地 bot 动作）</summary>
    public bool is_waiting_decision()
    {
        return _waiting_native;
    }

    public override void _Ready()
    {
        _native_available = start();
        if (_native_available)
        {
            MoveReady += _on_move_ready;
            GD.Print("ColdClearBridge: 已启动原生ColdClear（dll + worker），将使用ColdClear决策");
        }
        else
        {
            GD.Print("ColdClearBridge: 未检测到完整原生ColdClear，使用默认bot链");
        }
    }

    public override void _ExitTree()
    {
        stop();
    }

    /// <summary>当前是否应使用原生 ColdClear 决策（可用且未处于失败冷却）</summary>
    public bool using_native_cc()
    {
        return _native_available && Time.GetTicksMsec() >= _native_cooldown_until;
    }

    public bool is_native_available()
    {
        return _native_available;
    }

    public Godot.Collections.Dictionary get_native_cc_info()
    {
        string native_dir = _resolve_native_dir();
        return new Godot.Collections.Dictionary()
        {
            { "enabled", _native_available },
            { "dll", native_dir.Length > 0 ? _path_join(native_dir, DLL_FILENAME) : "" },
            { "worker", native_dir.Length > 0 ? _path_join(native_dir, WORKER_FILENAME) : "" },
            { "native_dir", native_dir },
            { "cooling_down", Time.GetTicksMsec() < _native_cooldown_until },
        };
    }

    /// <summary>是否还有待执行的路径动作（含仅 Hold 的计划）
    /// 注意：若计划只要求 Hold（movements 为空），也必须视为“有计划”，否则
    /// 调用方会因 has_plan()==false 而直接 hard_drop，导致跳过 Hold、误硬降。</summary>
    public bool has_plan()
    {
        if (_plan.Count == 0)
            return false;
        // 有待执行的 Hold 动作时也算有计划
        if (!_plan_hold_done && _plan_bool(_plan, "hold", false))
            return true;
        return _plan_index < _plan_arr(_plan, "movements").Count;
    }

    /// <summary>计划是否已（被）消费完毕（存在计划但全部动作已取出）</summary>
    public bool plan_consumed()
    {
        return _plan.Count > 0 && _plan_index >= _plan_arr(_plan, "movements").Count;
    }

    /// <summary>当前是否完全没有计划（本块从未获得过有效决策结果）。
    /// 用于垃圾行抬升时判断能否安全重新请求：垃圾上涨是整版（含当前方块）同步上移，
    /// 当前方块相对堆叠的落点/形状不变，因此只要本块已有（或曾有）计划就应继续执行旧计划，
    /// 而不是重规划——否则新计划按“方块在 spawn 位”生成，而方块实际已移动，会造成 missdrop。</summary>
    public bool is_plan_empty()
    {
        return _plan.Count == 0;
    }

    public int remaining_movements()
    {
        if (_plan.Count == 0)
            return 0;
        return _plan_arr(_plan, "movements").Count - _plan_index;
    }

    public bool plan_wants_hold()
    {
        return _plan_bool(_plan, "hold", false);
    }

    private static bool _plan_bool(Godot.Collections.Dictionary d, string key, bool def)
    {
        return d.ContainsKey(key) ? d[key].AsBool() : def;
    }

    private static Godot.Collections.Array _plan_arr(Godot.Collections.Dictionary d, string key)
    {
        return d.ContainsKey(key) ? d[key].AsGodotArray() : new Godot.Collections.Array();
    }

    /// <summary>清空当前计划（让调用方回退默认 bot）。例如 Hold 动作实际执行失败时使用。</summary>
    public void clear_plan()
    {
        _plan = new Godot.Collections.Dictionary();
        _plan_index = 0;
        _plan_hold_done = false;
    }

    /// <summary>
    /// 窒息/卡住保护专用：立即取消在途决策并清空计划（TetrisController 卡住保护触发时调用，
    /// 随后会强制硬降当前方块）。worker 线程对该在途请求迟到的回复会因 request_id 与
    /// _pending_request_id（-1）不匹配而被 _on_move_ready 忽略，不会污染下一块的计划。
    /// </summary>
    public void reset_for_stall()
    {
        _pending_request_id = -1;
        _waiting_native = false;
        _plan = new Godot.Collections.Dictionary();
        _plan_index = 0;
        _plan_hold_done = false;
        cc_plan_placements = new Godot.Collections.Array();
    }

    /// <summary>
    /// min_nodes 自适应调节（在每次真实决策回复后调用）：
    /// 把单次决策耗时（EMA 平滑）顶到「单块周期 × target_ratio」附近——
    ///   · 决策比目标快得多 → 说明还能多搜，乘性上调 min_nodes（更快节奏下自动回落）；
    ///   · 决策接近/超过目标 → 乘性下调，保证实际 PPS 不落后于 bot_target_pps。
    /// 每 ADAPT_EVERY 次采样才实际调整一次，防止逐块抖动造成 worker 反复 relaunch。
    /// </summary>
    private const int ADAPT_EVERY = 40;
    private const float ADAPT_UP = 1.2f;     // 还有余量时的乘性上调
    private const float ADAPT_DOWN = 0.8f;   // 逼近/超过预算时的乘性下调
    private const float EMA_ALPHA = 0.15f;

    private void _update_adaptive_min_nodes(float elapsed_ms)
    {
        // EMA 平滑
        if (_decision_ms_ema < 0f)
            _decision_ms_ema = elapsed_ms;
        else
            _decision_ms_ema = EMA_ALPHA * elapsed_ms + (1f - EMA_ALPHA) * _decision_ms_ema;

        _adaptive_adjust_counter += 1;
        if (_adaptive_adjust_counter < ADAPT_EVERY)
            return;
        _adaptive_adjust_counter = 0;

        // 目标耗时 = 单块周期 × 比例（预留动作执行/调度/消行开销；period 来自目标 pps）
        float period_ms = _target_piece_interval_ms;
        if (period_ms <= 1f)
            period_ms = 250f;
        float target_ms = period_ms * min_nodes_target_ratio;
        float ema = _decision_ms_ema;

        // 决策本身接近或超过整块周期 → 即使 ratio<1 也已经严重超时（理论上不该发生，
        // 说明卡住/极小周期），直接大幅下调兜底。
        if (ema >= period_ms)
        {
            _current_min_nodes = (int)(_current_min_nodes * 0.5f);
        }
        else if (ema > target_ms * 1.2f)
        {
            _current_min_nodes = (int)(_current_min_nodes * ADAPT_DOWN);
        }
        else if (ema < target_ms * 0.85f)
        {
            // 仍有较多余量 → 上调（封顶防失控）
            _current_min_nodes = (int)(_current_min_nodes * ADAPT_UP);
        }
        // 落在 [0.85, 1.2]×target 区间内 → 保持

        _current_min_nodes = Mathf.Clamp(_current_min_nodes, min_nodes_floor, min_nodes_cap);

        // 周期性地把当前决策节奏打日志，便于 headless 观察收敛情况（可留作低噪调试输出）
        ulong now_ms = Time.GetTicksMsec();
        if (now_ms - _adapt_log_last > 3000)
        {
            _adapt_log_last = now_ms;
            GD.Print(string.Format(
                "[CCAdapt] min_nodes={0} ema={1:F0}ms target={2:F0}ms period={3:F0}ms ratio={4:F2}",
                _current_min_nodes, ema, target_ms, period_ms, ema / period_ms));
        }
    }

    /// <summary>请求一次新的 ColdClear 决策计划（在每块开始时调用）。
    /// 结果存入 _plan；失败则清空计划（调用方回退默认 bot）。</summary>
    public void request_plan(TetrisController game_controller)
    {
        _plan = new Godot.Collections.Dictionary();
        _plan_index = 0;
        _plan_hold_done = false;
        // 立即丢弃旧决策的预览落点：新决策是异步到达的，若此处不清空，等待期间
        // _sync_bot_plan_display 会把「旧块」的计划重新堆叠到「已含刚锁定块」的新版面上，
        // 导致预览显示与当前块不匹配的错乱方块（时不时出现混乱）。
        cc_plan_placements = new Godot.Collections.Array();
        if (!using_native_cc())
            return;
        if (game_controller == null)
            return;

        Godot.Collections.Array board_rows = _build_board_rows(game_controller);
        if (board_rows.Count == 0)
            return;

        string hold = game_controller.hold_piece_type;
        // 记录当前方块与暂存方块，供决策日志输出（排查 bot 误旋转时对照所用方块）
        _last_current_piece = game_controller.current_piece_type;
        _last_hold_piece = hold;
        Godot.Collections.Array queue = new Godot.Collections.Array() { game_controller.current_piece_type };
        // 提供给 bot 的 Next 预览深度：默认当前块 + 14 个后续块（worker 的 queue[32]
        // 上限 32，14+1=15 远在范围内）。
        // 勾选 ShortNext（短见）后，bot 预览深度与玩家所见一致（由 tower_controller
        // 写入 clear_line_controller.bot_next_preview）。
        // 安全下限（避免卡死）：hold 可用时预览下限=2，hold 禁用时下限=0（只给当前块 qn=1）。
        // 原因：ColdClear 在「hold 空 + 队列已知块 ≤1」下会卡死——init_generations 需先
        // 消耗当前块，队列不足时根代变 Speculated，get_next_candidates 永远取不到 Known
        // 候选，block_next 永久阻塞（短见IV/V 配 hold 实测复现）。预览=2 保证每次落块后
        // 队列仍 ≥2 已知块，消耗当前块后根代仍为 Known。
        // NoHold 禁用 hold 时 init_generations 不消耗当前块，qn=1 也安全，故下限允许到 0。
        bool bot_hold_enabled = !game_controller.no_hold;
        int min_preview = bot_hold_enabled ? 2 : 0;
        int bot_preview = 14;
        if (game_controller.clear_line_controller != null)
            bot_preview = game_controller.clear_line_controller.bot_next_preview;
        if (bot_preview < min_preview)
            bot_preview = min_preview;
        if (game_controller.bag_controller != null)
        {
            foreach (Variant q in game_controller.bag_controller.peek_next_pieces(bot_preview))
                queue.Add(q);
        }

        // bot 是否使用 hold：跟随游戏设置（NoHold 禁用时 hold 关闭）。
        // 预览限制不再强制禁用 hold，而是保证预览数量足够避免卡死。
        bool use_hold = bot_hold_enabled && game_controller.can_hold;
        bool b2b = false;
        int combo = 0;
        int incoming = 0;
        if (game_controller.clear_line_controller != null)
        {
            b2b = game_controller.clear_line_controller.is_btb_active;
            combo = game_controller.clear_line_controller.combo_count;
        }
        if (game_controller.garbage_line_controller != null)
            incoming = game_controller.garbage_line_controller.get_enter_queue_size();
        int bag_remain = _compute_bag_remain(queue);

        string batch = _build_command_batch(
            board_rows, hold, queue, use_hold, b2b, combo, incoming, bag_remain, game_controller);
        if (batch.Length == 0)
            return;

        if (_pending_request_id != -1)
            return;
        _request_id_counter += 1;
        _pending_request_id = _request_id_counter;
        _waiting_native = true;
        // 自适应 min_nodes：记录本次请求的期望节奏（来自 controller 的 bot_target_pps）
        _target_piece_interval_ms = 1000.0f / Mathf.Max(game_controller.bot_target_pps, 0.1f);
        _request_sent_ms = Time.GetTicksMsec();
        if (!_request_move(batch, _pending_request_id))
        {
            _pending_request_id = -1;
            _waiting_native = false;
            _native_cooldown_until = Time.GetTicksMsec() + (ulong)FAIL_COOLDOWN_MS;
            GD.PushWarning("ColdClearBridge: 原生决策入队失败，本块起回退默认bot（冷却10s）");
        }
    }

    /// <summary>取出下一个待执行动作；计划已结束时返回 hard_drop（锁定当前块）。
    /// 若计划要求 Hold，第一个动作先返回 hold。</summary>
    public BotAction next_plan_action()
    {
        if (_plan.Count == 0)
            return new BotAction("hard_drop", new Godot.Collections.Array() { "hard_drop" }, "hard_drop");
        if (!_plan_hold_done && _plan_bool(_plan, "hold", false))
        {
            _plan_hold_done = true;
            return new BotAction("hold", new Godot.Collections.Array() { "hold" }, "hold");
        }
        Godot.Collections.Array mv = _plan_arr(_plan, "movements");
        if (_plan_index >= mv.Count)
            return new BotAction("hard_drop", new Godot.Collections.Array() { "hard_drop" }, "hard_drop");
        string m = mv[_plan_index].AsString();
        _plan_index += 1;
        return new BotAction(m, new Godot.Collections.Array() { m }, m);
    }

    /// <summary>构建发送给 ColdClear 的棋盘行（String 数组，行0=顶部，'1'=有块）。
    /// 发送窗口 = 可见区 + 上方 EXTRA_TOP_ROWS 行；先擦除活动方块。</summary>
    public Godot.Collections.Array _build_board_rows(TetrisController game_controller)
    {
        TetrisBoardDrawer drawer = game_controller.board_drawer;
        if (drawer == null || drawer.board_data.Count == 0)
            return new Godot.Collections.Array();
        Godot.Collections.Array board_data = drawer.board_data;
        int grid_w = drawer.grid_width;
        int visible_h = drawer.grid_height;
        int above = drawer.above_visible_rows;
        int start_y = Mathf.Max(0, above - EXTRA_TOP_ROWS);
        int end_y = above + visible_h;
        int h = end_y - start_y;

        Godot.Collections.Array rows = new Godot.Collections.Array();
        for (int i = 0; i < h; i++)
        {
            Godot.Collections.Array row = board_data[start_y + i].AsGodotArray();
            var s = new System.Text.StringBuilder();
            foreach (Variant c in row)
                s.Append(_cell_occupied(c) ? '1' : '0');
            rows.Add(s.ToString());
        }

        Godot.Collections.Array shape = game_controller.current_piece;
        Vector2I pos = game_controller.current_position;
        for (int y = 0; y < shape.Count; y++)
        {
            Godot.Collections.Array shape_row = shape[y].AsGodotArray();
            for (int x = 0; x < shape_row.Count; x++)
            {
                if (!_cell_is_one(shape_row[x]))
                    continue;
                int by = pos.Y + y;
                int bx = pos.X + x;
                if (by < start_y || by >= end_y)
                    continue;
                if (bx < 0 || bx >= grid_w)
                    continue;
                string row_s = rows[by - start_y].AsString();
                rows[by - start_y] = row_s.Substring(0, bx) + "0" + row_s.Substring(bx + 1);
            }
        }
        return rows;
    }

    public bool _cell_occupied(Variant cell)
    {
        if (cell.VariantType == Variant.Type.Nil)
            return false;
        if (cell.VariantType == Variant.Type.Bool)
            return cell.AsBool();
        return true;
    }

    /// <summary>格子值是否等于 1（镜像 GDScript `shape[y][x] != 1` 判断中的“=1”语义，
    /// 含 bool true 与 float 1.0 与 int 1）。</summary>
    public bool _cell_is_one(Variant cell)
    {
        switch (cell.VariantType)
        {
            case Variant.Type.Int:
                return cell.AsInt64() == 1;
            case Variant.Type.Float:
                return cell.AsDouble() == 1.0;
            case Variant.Type.Bool:
                return cell.AsBool();
            default:
                return false;
        }
    }

    /// <summary>计算 bag 中剩余方块位掩码（bit0=I, bit1=O, bit2=T, bit3=L, bit4=J, bit5=S, bit6=Z）</summary>
    public int _compute_bag_remain(Godot.Collections.Array queue)
    {
        var seen = new System.Collections.Generic.HashSet<string>();
        foreach (Variant q in queue)
            seen.Add(q.AsString());
        int mask = 0x7F;
        for (int i = 0; i < PIECE_ORDER.Length; i++)
        {
            if (seen.Contains(PIECE_ORDER[i]))
                mask &= ~(1 << i);
        }
        return mask;
    }

    /// <summary>构建“实际游戏规则/伤害模型”的命令行（S 命令）。
    /// 协议：S &lt;enabled&gt; &lt;base0..4&gt; &lt;tspin0..3&gt; &lt;allspin0..3&gt; &lt;b2b&gt; &lt;pc&gt; &lt;sendMult&gt; &lt;defendMult&gt; &lt;evalMult&gt;
    ///       &lt;attack_efficiency_weight&gt;
    ///       &lt;b2b_clear&gt; &lt;height&gt; &lt;clear4&gt; &lt;allspin_enabled&gt; &lt;allspin_repeat_penalty&gt;
    ///       &lt;clear1&gt; &lt;clear2&gt; &lt;clear3&gt; &lt;tspin1&gt; &lt;tspin2&gt; &lt;tspin3&gt; &lt;mini_tspin1&gt; &lt;mini_tspin2&gt;
    ///       &lt;allspin1&gt; &lt;allspin2&gt; &lt;allspin3&gt; &lt;allspin3plus&gt;
    ///       &lt;perfect_clear&gt; &lt;combo_garbage&gt; &lt;wasted_t&gt; &lt;move_time&gt;
    ///       &lt;kickLen&gt; &lt;kick dx,dy pairs: 2*kickLen&gt; &lt;combo0..31&gt; &lt;combo_formula&gt; &lt;no_spin&gt;
    /// allspin_enabled 为 int：0=allmini（非T卡住→minispin，效果同T mini），1=allspin（非T卡住→fullspin，效果同T-Spin），其余保留。
    /// no_spin 为 int：0=正常Spin判定；1=所有Spin视为Mini；2=不判定任何Spin（Talentless，bot 评估与伤害归一化）。
    /// 伤害表/倍率/规则开关等来自 buff（clear_line_controller.get_damage_tables、
    /// tower_controller.get_send_mult_attack、garbage_line_controller.get_mult_defend）。
    /// 各类型消行/旋转/惩罚的决策权重以本桥导出变量为主（inspector 界面调整）。
    /// 仅当 buff 显式传参（get_damage_tables 只返回 buff 显式设置的键）时才覆盖本桥默认权重。
    /// 踢墙表来自 tetris_controller.kick_table["all"]（游戏 asc 踢墙表），空/缺失时 worker 用标准 SRS。</summary>
    public string _build_game_rules_command(TetrisController game_controller)
    {
        int enabled = 1;
        // 各类型消行/旋转/惩罚的决策权重：来自本桥导出变量（inspector 调整）
        // 用 w_ 前缀避免与类成员（导出变量）同名产生的 shadowing 警告
        int w_eval_mult = eval_mult;
        int w_attack_efficiency_weight = attack_efficiency_weight;
        int w_b2b_clear = b2b_clear;
        int w_height = height;
        int w_clear4 = clear4;
        int w_clear1 = clear1;
        int w_clear2 = clear2;
        int w_clear3 = clear3;
        int w_tspin1 = tspin1;
        int w_tspin2 = tspin2;
        int w_tspin3 = tspin3;
        int w_mini_tspin1 = mini_tspin1;
        int w_mini_tspin2 = mini_tspin2;
        int w_allspin1 = allspin1;
        int w_allspin2 = allspin2;
        int w_allspin3 = allspin3;
        int w_allspin3plus = allspin3plus;
        int w_perfect_clear = perfect_clear;
        int w_combo_garbage = combo_garbage;
        int w_wasted_t = wasted_t;
        int w_move_time = move_time;
        int w_allspin_repeat_penalty = allspin_repeat_penalty;
        // 伤害表/倍率/规则开关等由 buff 提供（get_damage_tables / get_send_mult_attack / get_mult_defend）
        Godot.Collections.Array base_damage = new Godot.Collections.Array() { 0, 0, 1, 2, 4 };
        Godot.Collections.Array tspin_damage = new Godot.Collections.Array() { 0, 2, 4, 6 };
        Godot.Collections.Array allspin_damage = new Godot.Collections.Array() { 0, 4, 6, 8 };
        Godot.Collections.Array combo_damage = new Godot.Collections.Array() { 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 };
        int combo_formula = 1;  // 连击计算方式：0=旧连击表，1=新公式（默认）
        int b2b_bonus = 1;
        int pc_damage = 10;
        float send_mult_attack = 1.0f;
        float mult_defend = 1.0f;
        int allspin_enabled_i = 0;
        int no_spin_i = 0;  // NoSpin 规则：0=正常Spin判定；1=所有Spin视为Mini；2=不判定任何Spin
        Godot.Collections.Array kick_table = new Godot.Collections.Array();

        // 伤害表/倍率/规则开关来自 buff（clear_line_controller.get_damage_tables 等）。
        // 各类型消行/旋转/惩罚权重以本桥导出变量为主；仅当 buff 显式传参了对应键
        // （get_damage_tables 只返回 buff 显式设置的键）时才覆盖本桥默认权重。
        TetrisClearLine clc = game_controller != null ? game_controller.clear_line_controller : null;
        if (clc != null)
        {
            Godot.Collections.Dictionary d = clc.get_damage_tables();
            enabled = d.ContainsKey("enabled") ? (d["enabled"].AsBool() ? 1 : 0) : 1;
            if (d.ContainsKey("base_damage")) base_damage = d["base_damage"].AsGodotArray();
            if (d.ContainsKey("tspin_damage")) tspin_damage = d["tspin_damage"].AsGodotArray();
            if (d.ContainsKey("allspin_damage")) allspin_damage = d["allspin_damage"].AsGodotArray();
            if (d.ContainsKey("combo_damage")) combo_damage = d["combo_damage"].AsGodotArray();
            if (d.ContainsKey("combo_formula")) combo_formula = _to_int(d["combo_formula"]); // 0=旧连击表, 1=新公式
            if (d.ContainsKey("b2b_bonus")) b2b_bonus = _to_int(d["b2b_bonus"]);
            if (d.ContainsKey("pc_damage")) pc_damage = _to_int(d["pc_damage"]);
            if (d.ContainsKey("allspin_enabled")) allspin_enabled_i = _to_int(d["allspin_enabled"]);  // 0=allmini, 1=allspin
            if (d.ContainsKey("no_spin")) no_spin_i = _to_int(d["no_spin"]);  // 0=正常；1=全Mini；2=NoSpin
            // buff 可覆盖各类型消行/旋转/惩罚权重（默认以本桥导出变量为准）
            if (d.ContainsKey("eval_mult")) w_eval_mult = _to_int(d["eval_mult"]);
            if (d.ContainsKey("attack_efficiency_weight")) w_attack_efficiency_weight = _to_int(d["attack_efficiency_weight"]);
            if (d.ContainsKey("b2b_clear")) w_b2b_clear = _to_int(d["b2b_clear"]);
            if (d.ContainsKey("height")) w_height = _to_int(d["height"]);
            if (d.ContainsKey("clear4")) w_clear4 = _to_int(d["clear4"]);
            if (d.ContainsKey("clear1")) w_clear1 = _to_int(d["clear1"]);
            if (d.ContainsKey("clear2")) w_clear2 = _to_int(d["clear2"]);
            if (d.ContainsKey("clear3")) w_clear3 = _to_int(d["clear3"]);
            if (d.ContainsKey("tspin1")) w_tspin1 = _to_int(d["tspin1"]);
            if (d.ContainsKey("tspin2")) w_tspin2 = _to_int(d["tspin2"]);
            if (d.ContainsKey("tspin3")) w_tspin3 = _to_int(d["tspin3"]);
            if (d.ContainsKey("mini_tspin1")) w_mini_tspin1 = _to_int(d["mini_tspin1"]);
            if (d.ContainsKey("mini_tspin2")) w_mini_tspin2 = _to_int(d["mini_tspin2"]);
            if (d.ContainsKey("allspin1")) w_allspin1 = _to_int(d["allspin1"]);
            if (d.ContainsKey("allspin2")) w_allspin2 = _to_int(d["allspin2"]);
            if (d.ContainsKey("allspin3")) w_allspin3 = _to_int(d["allspin3"]);
            if (d.ContainsKey("allspin3plus")) w_allspin3plus = _to_int(d["allspin3plus"]);
            if (d.ContainsKey("perfect_clear")) w_perfect_clear = _to_int(d["perfect_clear"]);
            if (d.ContainsKey("combo_garbage")) w_combo_garbage = _to_int(d["combo_garbage"]);
            if (d.ContainsKey("wasted_t")) w_wasted_t = _to_int(d["wasted_t"]);
            if (d.ContainsKey("move_time")) w_move_time = _to_int(d["move_time"]);
            if (d.ContainsKey("allspin_repeat_penalty")) w_allspin_repeat_penalty = _to_int(d["allspin_repeat_penalty"]);
        }
        // 攻击/防御倍率来自 buff（tower_controller / garbage_line_controller）
        TowerController tower = game_controller != null ? game_controller.tower_controller : null;
        if (tower != null)
            send_mult_attack = tower.get_send_mult_attack();
        TetrisGarbageLineController garbage = game_controller != null ? game_controller.garbage_line_controller : null;
        if (garbage != null)
            mult_defend = garbage.get_mult_defend();

        // 读取游戏 asc 踢墙表（tetris_controller.kick_table["all"]，元素为 [dx,dy]）
        if (game_controller != null)
        {
            Godot.Collections.Array kt = game_controller.get_kick_table();
            if (kt.Count > 0)
                kick_table = kt;
        }

        var parts = new System.Collections.Generic.List<string>();
        parts.Add("S");
        parts.Add(enabled.ToString());
        foreach (Variant v in base_damage) parts.Add(_to_int(v).ToString());
        foreach (Variant v in tspin_damage) parts.Add(_to_int(v).ToString());
        foreach (Variant v in allspin_damage) parts.Add(_to_int(v).ToString());
        parts.Add(b2b_bonus.ToString());
        parts.Add(pc_damage.ToString());
        // 倍率以千分比发送（1000 = 1.0），与 Rust/C 侧一致
        parts.Add(_round_to_int(send_mult_attack * 1000.0).ToString());
        parts.Add(_round_to_int(mult_defend * 1000.0).ToString());
        parts.Add(w_eval_mult.ToString());
        // bot 评估权重：攻击效率（导出变量，inspector 调整）
        parts.Add(w_attack_efficiency_weight.ToString());
        // bot 评估权重：维持BTB / 放块后堆叠高度 / 四消（导出变量，inspector 调整）
        parts.Add(w_b2b_clear.ToString());
        parts.Add(w_height.ToString());
        parts.Add(w_clear4.ToString());
        parts.Add(allspin_enabled_i.ToString());
        // allspin_1 重复惩罚扣分（bot 评估权重，负值=降低选取值，导出变量）
        parts.Add(w_allspin_repeat_penalty.ToString());
        // 各类型消行/旋转的决策权重（导出变量，inspector 调整）
        parts.Add(w_clear1.ToString());
        parts.Add(w_clear2.ToString());
        parts.Add(w_clear3.ToString());
        parts.Add(w_tspin1.ToString());
        parts.Add(w_tspin2.ToString());
        parts.Add(w_tspin3.ToString());
        parts.Add(w_mini_tspin1.ToString());
        parts.Add(w_mini_tspin2.ToString());
        // 非T旋转（allspin）权重：消1/2/3/3+
        parts.Add(w_allspin1.ToString());
        parts.Add(w_allspin2.ToString());
        parts.Add(w_allspin3.ToString());
        parts.Add(w_allspin3plus.ToString());
        parts.Add(w_perfect_clear.ToString());
        parts.Add(w_combo_garbage.ToString());
        parts.Add(w_wasted_t.ToString());
        parts.Add(w_move_time.ToString());
        // 踢墙表：先发对数，再发 [dx,dy,dx,dy,...]
        // 注意：游戏 y 向下为正、ColdClear y 向上为正，发送时把 dy 取反，
        // 使 CC 端踢墙位移方向与游戏完全一致；否则落地后旋转等“多候选可行”
        // 的板面上，两端穷举踢墙的候选优先级相反，偶发导致 CC 预想落点与
        // 游戏实际落块错位（尤其 I 方块瞬降后旋转）。
        parts.Add(kick_table.Count.ToString());
        foreach (Variant kick in kick_table)
        {
            if (kick.VariantType == Variant.Type.Array)
            {
                Godot.Collections.Array kick_pair = kick.AsGodotArray();
                if (kick_pair.Count >= 2)
                {
                    parts.Add(_to_int(kick_pair[0]).ToString());
                    parts.Add((-_to_int(kick_pair[1])).ToString());
                }
            }
        }
        foreach (Variant v in combo_damage) parts.Add(_to_int(v).ToString());
        // 连击计算方式：0=旧连击表，1=新公式（默认）
        parts.Add(combo_formula.ToString());
        // NoSpin 规则：0=正常Spin判定；1=所有Spin视为Mini；2=不判定任何Spin（bot 评估与伤害归一化）
        parts.Add(no_spin_i.ToString());
        return string.Join(" ", parts) + "\n";
    }

    /// <summary>构建发送给 worker 的完整命令批（S/W/R/H/GO 行）。
    /// worker 以 W 的 height 决定 spawn_y=height-3、lockout_y=height-2（适应塔式棋盘窗口）。
    /// S 行在每次请求前发送，确保 bot 使用当前关卡的“实际游戏规则/伤害模型”。</summary>
    public string _build_command_batch(
        Godot.Collections.Array board_rows, string hold, Godot.Collections.Array queue,
        bool use_hold, bool b2b, int combo, int incoming, int bag_remain,
        TetrisController game_controller = null)
    {
        int h = board_rows.Count;
        if (h <= 0)
            return "";
        var lines = new System.Collections.Generic.List<string>();
        string s_line = _build_game_rules_command(game_controller);
        if (s_line.Length > 0)
            lines.Add(s_line.StripEdges());
        lines.Add(string.Format("W 10 {0}", h));
        for (int i = 0; i < h; i++)
            lines.Add(string.Format("R {0} {1}", i, board_rows[i].AsString()));
        // 实心垃圾行掩码：G <mask>，位 i = 窗口行 i 是实心行（0=窗口顶部，与 R 命令一致）。
        // worker 会转成 CC 行号掩码并传给 Board，使 CC 知道这些行即使填满也不消行。
        // 否则 CC 会把全满的实心行当作可消行，预测消行与实际不符 → 对账失败/报错。
        TetrisBoardDrawer br_drawer = game_controller != null ? game_controller.board_drawer : null;
        int br_above = br_drawer != null ? br_drawer.above_visible_rows : 0;
        int br_start_y = Mathf.Max(0, br_above - EXTRA_TOP_ROWS);
        TetrisGarbageLineController br_glc = game_controller != null ? game_controller.garbage_line_controller : null;
        int solid_mask = 0;
        if (br_glc != null)
        {
            for (int i = 0; i < h; i++)
            {
                if (br_glc.is_solid_garbage_row(br_start_y + i))
                    solid_mask |= 1 << i;
            }
        }
        lines.Add(string.Format("G {0}", solid_mask));
        string hold_str = "-";
        if (hold != null && hold != "" && hold != "-")
            hold_str = hold;
        lines.Add(string.Format("H {0}", hold_str));
        var qs = new System.Collections.Generic.List<string>();
        foreach (Variant q in queue)
        {
            string qs_str = q.AsString();
            if (qs_str != "" && qs_str != "-")
                qs.Add(qs_str);
        }
        // 并行搜索线程数优先级：buff 显式设置(bot_threads) > 本桥导出 cc_threads > 自动按 CPU 核数-2
        int buff_threads = 0;
        TetrisClearLine clc = game_controller != null ? game_controller.clear_line_controller : null;
        if (clc != null)
            buff_threads = clc.get_bot_threads();
        int threads_used = buff_threads;
        if (threads_used <= 0)
            threads_used = cc_threads;
        if (threads_used <= 0)
            threads_used = Mathf.Clamp(OS.GetProcessorCount() - 2, 1, 8);
        string go_line = string.Format("GO {0} {1} {2} {3} {4} {5} {6} {7} {8}",
            use_hold ? 1 : 0, MAX_NODES, _current_min_nodes, threads_used,
            b2b ? 1 : 0, combo, incoming, bag_remain, qs.Count);
        if (qs.Count > 0)
            go_line += " " + string.Join(" ", qs);
        lines.Add(go_line);
        return string.Join("\n", lines) + "\n";
    }

    /// <summary>worker 回复 OK &lt;hold&gt; &lt;n&gt; &lt;mv...&gt;，转为 _plan。</summary>
    public void _on_move_ready(int request_id, string reply)
    {
        if (request_id != _pending_request_id)
            return;
        _pending_request_id = -1;
        _waiting_native = false;
        // 自适应 min_nodes：测量本次决策真实耗时（请求发出 → 收到回复），
        // 在 DEAD/OK（真做了搜索）上采样；ERR（启动/入队失败，非搜索耗时）不采。
        if (adaptive_min_nodes && _request_sent_ms != 0 && !reply.StartsWith("ERR"))
        {
            ulong now = Time.GetTicksMsec();
            float elapsed = (float)((long)(now - _request_sent_ms));
            _request_sent_ms = 0;
            _last_decision_ms = elapsed;
            _update_adaptive_min_nodes(elapsed);
        }
        if (reply == "DEAD")
        {
            _native_cooldown_until = Time.GetTicksMsec() + (ulong)FAIL_COOLDOWN_MS;
            _plan = new Godot.Collections.Dictionary();
            return;
        }
        if (reply.StartsWith("ERR"))
        {
            _native_cooldown_until = Time.GetTicksMsec() + (ulong)FAIL_COOLDOWN_MS;
            _plan = new Godot.Collections.Dictionary();
            GD.PushWarning("ColdClearBridge: 原生决策失败（" + reply + "），本块起回退默认bot（冷却10s）");
            return;
        }
        if (reply.StartsWith("OK"))
        {
            string[] parts = reply.Split(" ");
            bool hold = parts.Length > 1 && parts[1] == "1";
            int n = (parts.Length > 2 && _is_valid_int(parts[2])) ? _parse_int(parts[2]) : 0;
            // 解析 CC 期望落点 cells 坐标（worker 以 " E <ex0> <ey0> ... <ex3> <ey3>" 附带，位于 movements 之前）
            var expected_cells = new Godot.Collections.Array();
            int mv_start = 3;
            if (parts.Length > 3 && parts[3] == "E")
            {
                for (int e = 0; e < 4; e++)
                {
                    if (4 + e * 2 + 1 < parts.Length)
                    {
                        var cell = new Godot.Collections.Array() { _parse_int(parts[4 + e * 2]), _parse_int(parts[5 + e * 2]) };
                        expected_cells.Add(cell);
                    }
                }
                mv_start = 12;
            }
            var movements = new Godot.Collections.Array();
            for (int i = 0; i < n; i++)
            {
                if (mv_start + i < parts.Length)
                    movements.Add(_move_to_action(parts[mv_start + i]));
            }
            // 解析整条最优计划（worker 在动作后追加 " P <count> <piece> <x0> <y0> ... <x3> <y3> <c0> <c1> <c2> <c3>"）：
            // 每个元素含方块类型（type，绘制颜色）、4 个 cells（x,y，绘制位置，CC 坐标 y 向上）、
            // 以及该落块消去的行号 cleared_lines（CC 绝对行号，-1=无消行）。
            int plan_start = mv_start + n;
            var plan_placements = new Godot.Collections.Array();
            if (parts.Length > plan_start + 1 && parts[plan_start] == "P")
            {
                int pcount = _parse_int(parts[plan_start + 1]);
                int idx = plan_start + 2;
                for (int p = 0; p < pcount; p++)
                {
                    if (idx + 12 >= parts.Length)
                        break;
                    var pcells = new Godot.Collections.Array();
                    for (int e = 0; e < 4; e++)
                    {
                        var cell = new Godot.Collections.Array() { _parse_int(parts[idx + 1 + e * 2]), _parse_int(parts[idx + 2 + e * 2]) };
                        pcells.Add(cell);
                    }
                    var cleared = new Godot.Collections.Array();
                    for (int c = 0; c < 4; c++)
                        cleared.Add(_parse_int(parts[idx + 9 + c]));
                    var placement = new Godot.Collections.Dictionary()
                    {
                        { "type", parts[idx] },
                        { "cells", pcells },
                        { "cleared_lines", cleared },
                    };
                    plan_placements.Add(placement);
                    idx += 13;
                }
            }
            cc_plan_placements = plan_placements;
            _plan = new Godot.Collections.Dictionary()
            {
                { "ok", true },
                { "hold", hold },
                { "movements", movements },
            };
            _plan_index = 0;
            _plan_hold_done = false;
            // 输出当前方块与暂存方块（bot 当前持有的方块），便于排查误旋转
            string held_desc = _last_hold_piece;
            if (held_desc == "" || held_desc == "-")
                held_desc = "无";
            // 已注释（bot 测试信息）：print(
            // 	"ColdClear决策 OK:",
            // 	" | 当前方块=", _last_current_piece,
            // 	" | 暂存(bot持有)=", held_desc,
            // 	" | hold=", hold,
            // 	" | 期望落点(cells)=", expected_cells,
            // 	" | 路径(", movements.size(), "步)=", movements,
            // 	" | 剩余待执行=", remaining_movements()
            // )
            return;
        }
        // TIMEOUT / 未知回复
        _native_cooldown_until = Time.GetTicksMsec() + (ulong)FAIL_COOLDOWN_MS;
        _plan = new Godot.Collections.Dictionary();
        GD.PushWarning("ColdClearBridge: 原生决策超时/未知（" + reply + "），本块起回退默认bot（冷却10s）");
    }

    /// <summary>把 worker 的移动码（L/R/C/K/Z/D）映射为游戏动作名</summary>
    public string _move_to_action(string code)
    {
        switch (code)
        {
            case "L":
                return "left";
            case "R":
                return "right";
            case "C":
                return "rotate_right";
            case "K":
                return "rotate_left";
            case "Z":
                return "rotate_180";
            case "D":
                return "soft_drop";
        }
        return "hard_drop";
    }

    // ========== worker 子进程管理（自包含，原 coldclear_native_stub 逻辑） ==========

    /// <summary>定位 native 目录（worker/dll 所在目录）。
    /// 导出运行：优先使用 exe 同目录下的 native/ 松散文件（由导出脚本复制到 exe 旁）。
    /// 编辑器/开发：res:// 直接映射项目目录，回退到项目内的 native/。
    /// 返回真实磁盘路径；找不到返回空串。</summary>
    public string _resolve_native_dir()
    {
        // 1) 导出运行：exe 同目录下应有 native/ 松散文件
        string exe_dir = OS.GetExecutablePath().GetBaseDir();
        string loose = _path_join(exe_dir, NATIVE_EXE_SUBDIR);
        if (FileAccess.FileExists(_path_join(loose, WORKER_FILENAME)))
            return loose;
        // 2) 编辑器/开发模式：res:// 映射项目目录
        string res_dir = ProjectSettings.GlobalizePath(NATIVE_RES_DIR);
        if (FileAccess.FileExists(_path_join(res_dir, WORKER_FILENAME)))
            return res_dir;
        return "";
    }

    /// <summary>启动 worker 子进程（幂等）。失败时返回 false。</summary>
    public bool start()
    {
        if (_started)
            return true;
        string native_dir = _resolve_native_dir();
        if (native_dir.Length == 0)
        {
            GD.PushError("coldclear_worker.exe 不存在（未找到 native 目录，请确认已把 native 文件夹放到 exe 旁）");
            return false;
        }
        string exe = _path_join(native_dir, WORKER_FILENAME);
        if (!FileAccess.FileExists(exe))
        {
            GD.PushError("coldclear_worker.exe 不存在: " + exe);
            return false;
        }
        Godot.Collections.Dictionary res = OS.ExecuteWithPipe(exe, new string[] { }, false);
        if (!res.ContainsKey("stdio"))
        {
            GD.PushError("无法启动 coldclear_worker.exe");
            return false;
        }
        _stdio = res["stdio"].AsGodotObject() as FileAccess;
        if (res.ContainsKey("stderr"))
            _stderr = res["stderr"].AsGodotObject() as FileAccess;
        _started = true;
        _running = true;
        _thread = new Godot.GodotThread();
        _thread.Start(Callable.From(_loop));
        return true;
    }

    /// <summary>停止 worker：发送 QUIT 并等待线程退出</summary>
    public void stop()
    {
        if (!_started)
            return;
        _running = false;
        if (_thread != null)
        {
            _thread.WaitToFinish();
            _thread = null;
        }
        if (_stdio != null)
        {
            _stdio.StoreString("QUIT\n");
            _stdio.Flush();
            _stdio.Close();
        }
        _stdio = null;
        _started = false;
    }

    /// <summary>主线程调用：入队一个 GO 请求。
    /// 传入完整命令批（含 W/H/R/GO），后台线程执行后回传结果。
    /// request_id 由调用方决定（用于匹配）。返回是否成功入队。</summary>
    public bool _request_move(string command_batch, int request_id)
    {
        if (!_started)
        {
            if (!start())
                return false;
        }
        _mutex.Lock();
        _queue.Add(new Godot.Collections.Dictionary()
        {
            { "id", request_id },
            { "cmd", command_batch },
        });
        _mutex.Unlock();
        return true;
    }

    /// <summary>后台线程循环：从队列取请求、写入 worker、读取回复、回传主线程</summary>
    public void _loop()
    {
        while (_running)
        {
            _mutex.Lock();
            Variant req = _queue.Count > 0 ? _queue[0] : new Variant();
            if (_queue.Count > 0)
                _queue.RemoveAt(0);
            _mutex.Unlock();
            if (req.VariantType == Variant.Type.Nil)
            {
                System.Threading.Thread.Sleep(5);
                continue;
            }
            Godot.Collections.Dictionary req_dict = req.AsGodotDictionary();
            string cmd = req_dict["cmd"].AsString();
            int rid = req_dict["id"].AsInt32();
            if (_stdio == null)
            {
                CallDeferred(nameof(_emit_move_ready), rid, "ERR no_worker");
                continue;
            }
            _stdio.StoreString(cmd);
            _stdio.Flush();
            string reply = _read_line();
            CallDeferred(nameof(_emit_move_ready), rid, reply);
        }
    }

    public void _emit_move_ready(int rid, string reply)
    {
        EmitSignal(nameof(MoveReady), rid, reply);
    }

    /// <summary>阻塞读取一行回复（带超时）</summary>
    public string _read_line()
    {
        ulong deadline = Time.GetTicksMsec() + (ulong)READ_TIMEOUT_MS;
        while (_running && Time.GetTicksMsec() < deadline)
        {
            if (_stdio != null && _stdio.GetLength() > 0)
                return _stdio.GetLine().StripEdges();
            System.Threading.Thread.Sleep(10);
        }
        return "TIMEOUT";
    }

    // ========== 原生 ColdClear 决策入口 ==========

    // ---- 小工具（C# 移植辅助，语义镜像 GDScript int()/round() 与 path_join） ----

    /// <summary>镜像 GDScript int(v)：截断为整数（String 解析失败返回 0）。</summary>
    public int _to_int(Variant v)
    {
        switch (v.VariantType)
        {
            case Variant.Type.Int:
                return (int)v.AsInt64();
            case Variant.Type.Float:
                return (int)v.AsDouble();
            case Variant.Type.Bool:
                return v.AsBool() ? 1 : 0;
            case Variant.Type.String:
                return _parse_int(v.AsString());
            default:
                return 0;
        }
    }

    /// <summary>镜像 GDScript round()（.5 远离零取整）后转 int。</summary>
    public int _round_to_int(double value)
    {
        return (int)System.Math.Round(value, System.MidpointRounding.AwayFromZero);
    }

    /// <summary>int 字符串解析（失败返回 0，镜像 GDScript int("abc")==0）。</summary>
    public int _parse_int(string s)
    {
        return int.TryParse(s, System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.InvariantCulture, out int value) ? value : 0;
    }

    /// <summary>镜像 GDScript is_valid_int()。</summary>
    public bool _is_valid_int(string s)
    {
        return int.TryParse(s, System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.InvariantCulture, out _);
    }

    /// <summary>镜像 GDScript String.path_join()：以 '/' 连接两段路径。</summary>
    public string _path_join(string dir, string file)
    {
        if (dir.Length == 0)
            return file;
        if (dir.EndsWith("/"))
            return dir + file;
        return dir + "/" + file;
    }
}
