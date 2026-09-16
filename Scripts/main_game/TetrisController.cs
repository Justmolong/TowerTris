using Godot;

/// <summary>
/// 俄罗斯方块控制器
/// 负责方块移动、碰撞检测、触底锁定等逻辑
/// </summary>
public partial class TetrisController : Node
{
    public const string EXIT_PATH = "res://Tscns/buff_chose_area.tscn";

    // 节点引用
    [Export]
    public TetrisBoardDrawer board_drawer;  // 版面绘制器节点
    [Export]
    public TetrisBagController bag_controller;  // Bag生成器节点
    [Export]
    public TetrisGarbageLineController garbage_line_controller;
    // @export var replay_record: ReplayRecord
    [Export]
    public TetrisClearLine clear_line_controller;
    [Export]
    public TowerController tower_controller;
    // @export var replay_player: ReplayPlayer

    public bool _game_started_emitted = false;
    // var _replay_seed_override: int = 0

    // 方块配置
    public Godot.Collections.Array current_piece = new Godot.Collections.Array();      // 当前方块的形状矩阵
    public Color current_color = Colors.White;  // 当前方块颜色
    public Vector2I current_position = Vector2I.Zero;  // 当前方块位置（格子坐标）
    public string current_piece_type = "I";  // 当前方块类型（用于踢墙表）
    public Godot.Collections.Array current_original_shape = new Godot.Collections.Array();  // 当前方块的原始形状（用于Hold）

    // 暂存系统
    public Godot.Collections.Array hold_piece = new Godot.Collections.Array();         // 暂存的方块矩阵
    public Color hold_color = Colors.White;  // 暂存的方块颜色
    public string hold_piece_type = "";   // 暂存的方块类型
    public Godot.Collections.Array hold_original_shape = new Godot.Collections.Array();  // 暂存方块的原始形状（用于Hold）
    public bool can_hold = true;          // 是否可以使用暂存（每回合只能使用一次）
    public bool no_hold = false;          // NoHold模式：禁用暂存（不读取Hold输入，也不执行交换）

    // 运动延迟系统
    public float move_das = 0.1f;
    public float move_arr = 0;
    public float softdrop_delay = 0.02f;

    public bool allow_press_move = true;
    public bool keep_press_move = false;
    public int direction_press = 0;
    public bool double_press = false;

    public Timer move_start_timer;
    public Timer move_keep_timer;
    public Timer softdrop_timer;

    public Godot.Collections.Dictionary press_key = new Godot.Collections.Dictionary()
    {
        { "LeftMove", (long)0 },
        { "RightMove", (long)0 },
        { "SoftDrop", (long)0 },
        { "HardDrop", (long)0 },
        { "LeftSpin", (long)0 },
        { "RightSpin", (long)0 },
        { "SwapSpin", (long)0 },
        { "HoldBlock", (long)0 },
    };

    public Godot.Collections.Dictionary check_for_single_press = new Godot.Collections.Dictionary()
    {
        { "HardDrop", (long)0 },
        { "SoftDrop", (long)0 },
        { "LeftSpin", (long)0 },
        { "RightSpin", (long)0 },
        { "SwapSpin", (long)0 },
        { "HoldBlock", (long)0 },
    };

    // 触底锁定计时
    public Timer lock_timer;
    public int lock_times_limit_max = 10;
    public int lock_times_limit = 0;
    public float lock_delay = 1;  // 触底后锁定延迟（秒）

    // 重力下落
    public float gravity_drop_time = 5;
    public Timer gravity_timer;

    // 方块锁定后的生成延迟（秒）：>0 时先等待该延迟再开始消行判定；0 表示不等待
    public float spawn_delay_time = 0;
    public Timer spawn_delay_timer;

    // ========== 统计系统 ==========
    // 全局计时
    public float game_time = 0.0f;          // 游戏总时间（秒）

    // 回放输入覆盖模式：开启后，按键状态由 replay_player 直接驱动，而不是实时读取 Input（已注释 - 回放系统禁用）
    // var replay_input_override: bool = false
    public Timer game_timer;               // 游戏计时器

    // PPS (Pieces Per Second)
    public int total_pieces = 0;           // 总放置方块数
    public float pps_value = 0.0f;          // 每秒方块数

    // APM (Attack Per Minute)
    public int total_attacks = 0;          // 总攻击数（造成的伤害总量）
    public float apm_value = 0.0f;          // 每分钟攻击数

    // RPM — 基于最近1分钟滚动窗口的接收攻击数
    public float rpm_value = 0.0f;          // 每分钟接收攻击数（仅最近1分钟）

    /// <summary>存储 {time: 游戏时间秒数, damage: 伤害量} 事件，用于滑动窗口统计最近60秒的 RPM</summary>
    public Godot.Collections.Array _rpm_events = new Godot.Collections.Array();
    public const float RPM_WINDOW_SECONDS = 60.0f;  // 滚动窗口大小（秒）

    // 上次更新统计的时间
    public float last_stats_update_time = 0.0f;

    // 结束数据
    public int max_combo = 0;  // 最大连击数
    public int max_btb = 0;    // 最大BTB数
    public int total_lines_cleared = 0;  // 总消行数
    public int total_spins = 0;  // 总Spin次数

    // ========== Bot 参数（控制文件见下方注释） ==========
    // ---------------------------------------------------------------------------
    // 【bot 参数的来源/控制文件】
    //  1) bot_mode 由 tower_controller.gd 控制：关卡配置里带 "BotMode":true 时，
    //     tower_controller._extra_data_deal() 会把 tetris_controller.bot_mode 置 true。
    //     "BotMode" 键来自 buff_chose_area.gd 的 tower_init_data（关卡 buff 配置）。
    //  2) 其余3个 @export 参数（bot_target_pps / bot_native_action_interval /
    //     bot_debug_log）直接在 tetris_controller.gd 的 Inspector 里调整。
    // ---------------------------------------------------------------------------
    public bool bot_mode = false;
    // 目标方块/秒（PPS）。控制 bot 落块的节奏上限：
    //   每块最小间隔 = 1/bot_target_pps（_get_bot_piece_interval）
    //   每步动作间隔 = 1/(bot_target_pps*4)（_get_bot_action_interval）
    // 在 tetris_controller.gd 的 Inspector 中调整（@export）。
    [Export]
    public float bot_target_pps = 4;

    // bot 每步"原生动作"的最小间隔（秒）。越小执行越快，但过小可能因物理/程序竞争出问题。
    // 在 tetris_controller.gd 的 Inspector 中调整（@export）。
    [Export]
    public float bot_native_action_interval = 0.001f;

    // 是否打印 bot 调试日志（例如 ColdClear 决策路径、启用提示）。
    // 在 tetris_controller.gd 的 Inspector 中调整（@export）。
    [Export]
    public bool bot_debug_log = true;

    // Bot 决策预览：最多读取/绘制的规划块数。0 = 读取全部（默认 7 块）。
    [Export]
    public int bot_plan_max_pieces = 7;

    // 【可选】bot 直接放置：不做逐帧移动，一次调用内快速执行整条路径并锁定，避免途中
    // 移动耗时，大幅提升落块速度（实际速率仅受 bot_target_pps 与生成/消行延迟限制）。
    // 关闭则回到逐帧执行移动序列（更"拟人"但较慢）。
    [Export]
    public bool bot_instant_place = true;

    /// <summary>
    /// 窒息/卡住保护（秒）：同一方块在手超过该时长仍未落子（如原生决策超时、无解停滞、
    /// worker 卡住等），bot 会强制硬降放下当前方块。保证极端高堆叠下 bot 仍持续落块，
    /// 从而正常触发「顶出/方块堆积到顶部」的窒息死亡判定，而不是停在半空。
    /// 可在 Inspector 中调整。
    /// </summary>
    [Export]
    public float bot_stall_drop_time = 2.0f;

    // --- 以下为 bot 内部状态（运行期维护，勿手改） ---
    public ColdClearBridge _coldclear_bridge = null;
    public int _bot_piece_serial = 0;
    public int _bot_tracking_piece_serial = -1;
    public int _bot_tracking_board_version = 0;
    public float _bot_next_action_time = 0.0f;
    public float _bot_piece_cooldown = 0.0f;
    // 卡住保护内部状态：当前方块序列号 + 已等待时长（秒）
    public int _bot_stall_serial = -1;
    public float _bot_stall_timer = 0.0f;
    // PPS 校准内部状态：上一块落子时刻（真实毫秒）与周期超出滑动均值
    public ulong _bot_last_drop_ms = 0;
    public float _bot_cycle_overshoot_ema = 0.0f;
    // Bot 预览缓存：异步等待新决策期间沿用上一帧已算好的预览，避免出现空档。
    public Godot.Collections.Array _last_bot_plan_cache = new Godot.Collections.Array();
    public int _last_bot_plan_serial = -1;

    [Signal]
    public delegate void GameStartedEventHandler();
    [Signal]
    public delegate void GameEndedEventHandler();

    // ========== 踢墙表配置 ==========
    // 现代踢墙表
    private static readonly int[,] KICK_OFFSETS = new int[,]
    {
        { 0, 0 }, { -1, 0 }, { 0, 1 }, { -1, 1 }, { 0, 2 }, { -1, 2 }, { -2, 0 }, { -2, 1 },
        { -2, 2 }, { 1, 0 }, { 1, 1 }, { 0, -1 }, { -1, -1 }, { -2, -1 }, { 1, 2 }, { 2, 0 },
        { 0, -2 }, { -1, -2 }, { -2, -2 }, { 2, 1 }, { 2, 2 },
    };

    private static Godot.Collections.Dictionary MakeKickTable()
    {
        var list = new Godot.Collections.Array();
        for (int i = 0; i < KICK_OFFSETS.GetLength(0); i++)
        {
            var pair = new Godot.Collections.Array();
            pair.Add((long)KICK_OFFSETS[i, 0]);
            pair.Add((long)KICK_OFFSETS[i, 1]);
            list.Add(pair);
        }
        return new Godot.Collections.Dictionary() { { "all", list } };
    }

    public Godot.Collections.Dictionary kick_table = MakeKickTable();

    // 返回游戏 asc 踢墙表（供 ColdClear bridge 传入 bot，使 bot 的踢墙与游戏一致）
    public Godot.Collections.Array get_kick_table()
    {
        if (kick_table.ContainsKey("all"))
            return kick_table["all"].AsGodotArray();
        return new Godot.Collections.Array();
    }

    public override void _Ready()
    {
        _game_started_emitted = false;
        // _replay_seed_override = 0

        _auto_finding();
        // _prepare_replay_if_pending()  # 回放系统已禁用

        // 将消行控制器引用传递给board_drawer
        if (board_drawer != null)
            board_drawer.set_clear_line_controller(clear_line_controller);

        // 初始化随机数管理器
        _initialize_random();

        _set_timer();

        _load_user_settings();

        // 初始化统计系统
        _init_stats();

        if (bot_mode)
        {
            _ensure_coldclear_bridge();
            if (bot_debug_log)
            {
                // pass  # 已注释：print("[ColdClearBridge] 使用原生ColdClear决策（rust cold_clear.dll）")
            }
        }

        // 生成第一个方块
        spawn_new_piece();
    }

    public void _auto_finding()
    {
        // 自动查找board_drawer（如果未设置）
        if (board_drawer == null)
        {
            board_drawer = GetNodeOrNull<TetrisBoardDrawer>("../TetrisBoardDrawer");
            if (board_drawer == null)
            {
                GD.PushError("TetrisController: 未找到TetrisBoardDrawer节点！");
                return;
            }
        }

        // 自动查找bag_controller（如果未设置）
        if (bag_controller == null)
        {
            bag_controller = GetNodeOrNull<TetrisBagController>("../TetrisBagController");
            if (bag_controller == null)
            {
                GD.PushError("TetrisController: 未找到TetrisBagController节点！");
                return;
            }
        }

        // 自动查找clear_line_controller（如果未设置）
        if (clear_line_controller == null)
        {
            clear_line_controller = GetNodeOrNull<TetrisClearLine>("../TetrisClearLine");
            if (clear_line_controller == null)
            {
                GD.PushError("TetrisController: 未找到TetrisClearLine节点！");
                return;
            }
        }

        // 自动查找garbage_line_controller（如果未设置）
        if (garbage_line_controller == null)
        {
            garbage_line_controller = GetNodeOrNull<TetrisGarbageLineController>("../TetrisGarbageLineController");
            if (garbage_line_controller == null)
            {
                GD.PushError("TetrisController: 未找到TetrisGarbageLineController节点！");
                return;
            }
        }

        // 自动查找tower_controller（如果未设置）
        if (tower_controller == null)
        {
            tower_controller = GetNodeOrNull<TowerController>("../../TowerController");
            if (tower_controller == null)
            {
                GD.PushError("TetrisController: 未找到TowerController节点！");
                return;
            }
        }

        // ====== 回放系统相关（已禁用） ======
        // if not replay_record:
        // 	replay_record = get_node_or_null("../ReplayRecord")
        // 
        // if not replay_player:
        // 	replay_player = get_node_or_null("../../ReplayPlayer")
        // 	if not replay_player:
        // 		replay_player = _find_replay_player(get_tree().root)
    }

    // ====== 回放系统相关函数（已禁用） ======
    // func _find_replay_player(node: Node) -> ReplayPlayer:
    // ...
    // func _prepare_replay_if_pending() -> void:
    // ...

    public void _initialize_random()
    {
        // 优先使用回放提供的种子（已禁用 - 回放系统禁用）
        // if _replay_seed_override != 0:
        // 	RandomManager.initialize(_replay_seed_override)
        // else:
        // 从设置中读取种子（如果有）
        long saved_seed = _load_saved_seed();
        if (saved_seed != 0)
            RandomManager.initialize(saved_seed);
        else
            // 使用当前时间作为种子
            RandomManager.initialize_default();

        // 已注释（调试噪音）：print("随机数管理器已初始化，种子: ", RandomManager.get_current_seed())
    }

    public long _load_saved_seed()
    {
        // 可以从设置文件中读取保存的种子
        // 默认返回0表示使用时间种子
        return 0;
    }

    /// <summary>加载用户设置</summary>
    public void _load_user_settings()
    {
        var settings = UserSetting.load_settings();
        if (settings.Count > 0)
        {
            if (settings.ContainsKey("move_das"))
                move_das = settings["move_das"].AsSingle();
            else
                move_das = 0.1f;
            if (settings.ContainsKey("move_arr"))
                move_arr = settings["move_arr"].AsSingle();
            else
                move_arr = 0.0f;
            if (settings.ContainsKey("softdrop_delay"))
                softdrop_delay = settings["softdrop_delay"].AsSingle();
            else
                softdrop_delay = 0.1f;

            // 更新计时器
            if (move_start_timer != null && move_das != 0)
                move_start_timer.WaitTime = move_das;
            if (move_keep_timer != null && move_arr != 0)
                move_keep_timer.WaitTime = move_arr;
            if (softdrop_timer != null && softdrop_delay != 0)
                softdrop_timer.WaitTime = softdrop_delay;

            // 应用键位设置
            UserSetting.apply_key_bindings_from_dict(settings);
        }
    }

    public void _set_timer()
    {
        move_start_timer = new Timer();
        if (move_das != 0)
            move_start_timer.WaitTime = move_das;
        move_start_timer.OneShot = true;
        AddChild(move_start_timer);

        move_keep_timer = new Timer();
        if (move_arr != 0)
            move_keep_timer.WaitTime = move_arr;
        move_keep_timer.OneShot = true;
        AddChild(move_keep_timer);

        softdrop_timer = new Timer();
        softdrop_timer.WaitTime = softdrop_delay;
        softdrop_timer.OneShot = true;
        AddChild(softdrop_timer);

        lock_timer = new Timer();
        lock_timer.WaitTime = lock_delay;
        lock_timer.OneShot = true;
        lock_timer.Timeout += _lock_piece;
        AddChild(lock_timer);

        // 生成延迟计时器：方块锁定后先等待 spawn_delay_time，再开始消行判定
        spawn_delay_timer = new Timer();
        spawn_delay_timer.OneShot = true;
        spawn_delay_timer.Timeout += _process_after_spawn_delay;
        AddChild(spawn_delay_timer);

        gravity_timer = new Timer();
        if (gravity_drop_time != 0)
            gravity_timer.WaitTime = gravity_drop_time;
        gravity_timer.OneShot = true;
        AddChild(gravity_timer);

        // 游戏计时器（每0.1秒更新一次统计）
        game_timer = new Timer();
        game_timer.WaitTime = 0.1f;
        game_timer.OneShot = false;
        game_timer.Timeout += _update_stats;
        AddChild(game_timer);
        game_timer.Start();
    }

    /// <summary>初始化统计系统</summary>
    public void _init_stats()
    {
        game_time = 0.0f;
        total_pieces = 0;
        total_attacks = 0;
        pps_value = 0.0f;
        apm_value = 0.0f;
        rpm_value = 0.0f;
        last_stats_update_time = 0.0f;
        // 重置 RPM 滚动窗口
        _rpm_events.Clear();
    }

    /// <summary>更新统计信息（每0.1秒调用）</summary>
    public void _update_stats()
    {
        // 更新游戏时间
        game_time += 0.1f;

        // 计算PPS
        if (game_time > 0)
            pps_value = total_pieces / game_time;

        // 计算APM
        if (game_time > 0)
            apm_value = (total_attacks / game_time) * 60.0f;

        // 计算RPM（滚动最近1分钟窗口）
        _prune_rpm_events();
        rpm_value = _compute_rpm_from_window();

        // 更新显示
        if (board_drawer != null)
            board_drawer.update_stats(pps_value, apm_value, rpm_value);
    }

    /// <summary>记录放置方块（PPS统计）</summary>
    public void _record_piece_placed()
    {
        total_pieces += 1;
    }

    /// <summary>记录造成攻击（APM统计）</summary>
    public void _record_attack_damage(int damage)
    {
        if (damage > 0)
            total_attacks += damage;
    }

    /// <summary>记录接收攻击（RPM统计 — 基于最近1分钟滚动窗口）</summary>
    public void _record_received_damage(int damage)
    {
        if (damage > 0)
        {
            // 向滚动窗口添加事件（带当前游戏时间戳）
            _rpm_events.Add(new Godot.Collections.Dictionary()
            {
                { "time", game_time },
                { "damage", (long)damage },
            });
        }
    }

    // ========== RPM 滚动窗口辅助 ==========

    /// <summary>清理超出窗口的过期事件</summary>
    public void _prune_rpm_events()
    {
        float cutoff = game_time - RPM_WINDOW_SECONDS;
        int i = 0;
        while (i < _rpm_events.Count)
        {
            var ev = _rpm_events[i].AsGodotDictionary();
            if (ev["time"].AsSingle() < cutoff)
                i += 1;
            else
                break;
        }
        for (int drop = 0; drop < i; drop++)
            _rpm_events.RemoveAt(0);
    }

    /// <summary>从滚动窗口计算 RPM（最近 RPM_WINDOW_SECONDS 秒内的每分钟接收攻击数）</summary>
    public float _compute_rpm_from_window()
    {
        if (_rpm_events.Count == 0)
            return 0.0f;

        // 窗口内的实际时间跨度（取窗口大小与游戏时间中的较小值）
        float window_span = Mathf.Min(RPM_WINDOW_SECONDS, game_time);
        if (window_span <= 0.0f)
            return 0.0f;

        int total = 0;
        foreach (var eventVariant in _rpm_events)
        {
            var ev = eventVariant.AsGodotDictionary();
            total += ev["damage"].AsInt32();
        }

        return (total / window_span) * 60.0f;
    }

    /// <summary>获取当前统计信息</summary>
    public Godot.Collections.Dictionary get_stats()
    {
        return new Godot.Collections.Dictionary()
        {
            { "game_time", game_time },
            { "total_pieces", total_pieces },
            { "total_attacks", total_attacks },
            { "pps", pps_value },
            { "apm", apm_value },
            { "rpm", rpm_value },
        };
    }

    /// <summary>重置统计信息</summary>
    public void reset_stats()
    {
        _init_stats();
        if (board_drawer != null)
            board_drawer.update_stats(pps_value, apm_value, rpm_value);
    }

    /// <summary>生成新方块（从Bag中获取）</summary>
    public bool spawn_new_piece()
    {
        // 从Bag控制器获取下一个方块
        var piece_data = bag_controller.get_next_piece();
        int spawn_x = (int)((board_drawer.grid_width - piece_data["shape"].AsGodotArray()[0].AsGodotArray().Count) / 2);
        // 生成Y坐标：从下往上数第22行
        int spawn_y = Mathf.Max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22);

        // 检查生成时是否碰撞（游戏结束判定）
        if (_check_collision(new Vector2I(spawn_x, spawn_y), piece_data["shape"].AsGodotArray(), false))
        {
            GD.Print("游戏结束！无法生成新方块（窒息/顶出）");
            _game_over("方块堆积到顶部");
            return false;
        }

        current_piece = piece_data["shape"].AsGodotArray();
        current_color = piece_data["color"].AsColor();
        current_piece_type = piece_data["type"].AsString();
        current_original_shape = bag_controller.get_original_shape(current_piece_type);
        current_position = new Vector2I(spawn_x, spawn_y);
        _bot_piece_serial += 1;
        // 调试：记录方块 spawn 位置（矩阵左上角），用于对照 CC 决策与执行
        // if bot_debug_log:
        // 	print("[BotSpawn] piece=", current_piece_type, " spawn=(", current_position.x, ",", current_position.y, ")")

        _draw_current_piece();

        if (gravity_drop_time != 0)
            gravity_timer.Start();
        lock_timer.Stop();
        lock_times_limit = lock_times_limit_max;

        can_hold = true;

        _update_next_display();
        _update_shadow();

        _record_piece_placed();

        // 触发游戏开始信号（首次生成方块时）
        if (!_game_started_emitted)
        {
            _game_started_emitted = true;
            EmitSignal(nameof(GameStarted));
        }

        return true;
    }

    /// <summary>生成新方块但不重置hold权限（用于hold交换后的生成）</summary>
    public bool spawn_new_piece_keep_hold()
    {
        // 从Bag控制器获取下一个方块
        var piece_data = bag_controller.get_next_piece();
        int spawn_x = (int)((board_drawer.grid_width - piece_data["shape"].AsGodotArray()[0].AsGodotArray().Count) / 2);
        // 生成Y坐标：从下往上数第22行
        int spawn_y = Mathf.Max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22);

        // 检查生成时是否碰撞（游戏结束判定）
        if (_check_collision(new Vector2I(spawn_x, spawn_y), piece_data["shape"].AsGodotArray(), false))
        {
            GD.Print("游戏结束！无法生成新方块（窒息/顶出）");
            _game_over("方块堆积到顶部");
            return false;
        }

        current_piece = piece_data["shape"].AsGodotArray();
        current_color = piece_data["color"].AsColor();
        current_piece_type = piece_data["type"].AsString();
        current_original_shape = bag_controller.get_original_shape(current_piece_type);
        current_position = new Vector2I(spawn_x, spawn_y);
        _bot_piece_serial += 1;

        // 绘制方块到版面
        _draw_current_piece();

        // 重置锁定状态
        if (gravity_drop_time != 0)
            gravity_timer.Start();
        lock_timer.Stop();
        lock_times_limit = lock_times_limit_max;

        _update_next_display();
        _update_shadow();

        // 记录放置方块（PPS）
        _record_piece_placed();

        return true;
    }

    /// <summary>游戏结束方法</summary>
    public async void _game_over(string reason = "Game Over")
    {
        // 停止所有计时器
        game_timer.Stop();
        gravity_timer.Stop();
        lock_timer.Stop();
        move_start_timer.Stop();
        move_keep_timer.Stop();
        softdrop_timer.Stop();

        // 停止接受输入
        SetProcess(false);

        // 收集最终统计数据
        var stats = get_stats();

        if (clear_line_controller != null)
        {
            stats["max_combo"] = max_combo;
            stats["max_btb"] = max_btb;
            stats["total_lines_cleared"] = total_lines_cleared;
            stats["total_spins"] = total_spins;
        }

        // 获取塔控制器数据
        var tower = GetNodeOrNull<TowerController>("../../TowerController");
        if (tower != null)
        {
            stats["tower_height"] = tower.tower_meter;
            stats["kill_count"] = tower.kill_count;
            stats["tower_average_speed"] = tower.tower_meter / Mathf.Max(game_time, 0.001f);
            stats["current_stage"] = tower.current_stage;
        }

        GlobalData.update_stats(stats);
        GlobalData.set_game_over_reason(reason);

        // 触发游戏结束信号
        EmitSignal(nameof(GameEnded));

        // 通知版面变黑
        if (board_drawer != null)
        {
            board_drawer.is_game_over = true;
            board_drawer.QueueRedraw();
        }

        // 延迟切换到游戏结束场景
        await ToSignal(GetTree().CreateTimer(0.5), SceneTreeTimer.SignalName.Timeout);
        GetTree().ChangeSceneToFile("res://Tscns/game_over.tscn");
    }

    /// <summary>更新Next显示</summary>
    public void _update_next_display()
    {
        if (board_drawer != null && bag_controller != null)
        {
            var next_pieces = new Godot.Collections.Array();
            // 从board_drawer读取配置的next_count
            int next_count = board_drawer.next_count;
            var piece_types = bag_controller.peek_next_pieces(next_count);

            foreach (var piece_type in piece_types)
            {
                string pt = piece_type.AsString();
                var shape = bag_controller.get_original_shape(pt);
                var color = bag_controller.get_piece_color(pt);
                next_pieces.Add(new Godot.Collections.Dictionary()
                {
                    { "shape", shape },
                    { "color", color },
                });
            }

            board_drawer.set_next_pieces(next_pieces);
        }
    }

    /// <summary>绘制当前方块到版面</summary>
    public void _draw_current_piece()
    {
        // 清除当前方块（重新绘制时会覆盖，但为了安全先清除）
        _clear_current_piece();

        // 绘制新位置的方块
        for (int y = 0; y < current_piece.Count; y++)
        {
            var row = current_piece[y].AsGodotArray();
            for (int x = 0; x < row.Count; x++)
            {
                if (row[x].AsInt64() == 1)
                {
                    int board_x = current_position.X + x;
                    int board_y = current_position.Y + y;
                    board_drawer.set_cell_color(board_x, board_y, current_color);
                }
            }
        }
    }

    /// <summary>清除当前方块</summary>
    public void _clear_current_piece()
    {
        for (int y = 0; y < current_piece.Count; y++)
        {
            var row = current_piece[y].AsGodotArray();
            for (int x = 0; x < row.Count; x++)
            {
                if (row[x].AsInt64() == 1)
                {
                    int board_x = current_position.X + x;
                    int board_y = current_position.Y + y;
                    board_drawer.set_cell_color(board_x, board_y, new Variant());
                }
            }
        }
    }

    /// <summary>检查碰撞</summary>
    public bool _check_collision(Vector2I pos, Godot.Collections.Array piece = null, bool ignore_current_piece = true)
    {
        if (piece == null)
            piece = current_piece;
        if (ignore_current_piece)
            _clear_current_piece();

        bool is_not_allow = false;

        for (int y = 0; y < piece.Count; y++)
        {
            var row = piece[y].AsGodotArray();
            for (int x = 0; x < row.Count; x++)
            {
                if (row[x].AsInt64() == 1)
                {
                    int board_x = pos.X + x;
                    int board_y = pos.Y + y;

                    // 边界检查
                    if (board_x < 0 || board_x >= board_drawer.grid_width)
                        is_not_allow = true;
                    if (board_y >= board_drawer.grid_height + board_drawer.above_visible_rows)
                        is_not_allow = true;

                    // 检查与其他格子的碰撞（只检查非空格子）
                    if (board_y >= 0 && board_drawer.get_cell_color(board_x, board_y).VariantType != Variant.Type.Nil)
                        is_not_allow = true;
                }
                if (is_not_allow)
                    break;
            }
            if (is_not_allow)
                break;
        }

        if (ignore_current_piece)
            _draw_current_piece();
        return is_not_allow;
    }

    /// <summary>尝试移动方块</summary>
    public bool _try_move(int delta_x, int delta_y)
    {
        // 手上无方块（生成/消行延迟期间）：不移动，避免空方块在 while 循环里无限下落导致卡死
        if (current_piece.Count == 0)
            return false;
        var new_pos = new Vector2I(current_position.X + delta_x, current_position.Y + delta_y);
        _check_underground_touch();

        if (!_check_collision(new_pos))
        {
            // 移动成功
            _clear_current_piece();
            current_position = new_pos;
            _draw_current_piece();

            _check_underground_touch();
            // 移动后重置锁延
            if (lock_times_limit > 0 && !lock_timer.IsStopped())
            {
                lock_timer.Start();
                lock_times_limit -= 1;
            }

            _update_shadow();
            return true;
        }
        else
        {
            return false;
        }
    }

    public void _check_underground_touch()
    {
        var new_pos = new Vector2I(current_position.X, current_position.Y + 1);
        if (!_check_collision(new_pos))
            lock_timer.Stop();
        else if (lock_timer.IsStopped())
            lock_timer.Start();
    }

    /// <summary>
    /// 锁定当前方块。
    /// 逻辑上清除 current_piece（board_data 中已锁定的格子保持不变），
    /// 先触发 spawn_delay_time 延迟（为 0 时无需等待），延迟结束后再开始消行判定。
    /// 生成新方块由 TetrisClearLine 在消行结束后调用 spawn_new_piece() 完成。
    /// </summary>
    public void _lock_piece()
    {
        // 已在等待生成新方块时避免重复触发
        if (current_piece.Count == 0)
            return;
        // 逻辑上清除当前方块（保留 board_data 中已锁定的格子）
        current_piece = new Godot.Collections.Array();
        // 触发生成延迟；为 0 时直接处理消行
        if (spawn_delay_time > 0)
        {
            spawn_delay_timer.WaitTime = spawn_delay_time;
            spawn_delay_timer.Start();
        }
        else
        {
            _process_after_spawn_delay();
        }
    }

    /// <summary>生成延迟结束：开始处理消行判定（消行 + 统计 + 垃圾处理）</summary>
    public void _process_after_spawn_delay()
    {
        // 先检测是否有消行
        int cleared = _check_and_clear_lines();

        // 只有在没有消行的情况下才触发垃圾行增长
        if (cleared == 0 && garbage_line_controller != null)
            garbage_line_controller.process_garbage_after_lock();
    }

    /// <summary>检测并消除完整的行，并处理垃圾行抵消</summary>
    public int _check_and_clear_lines()
    {
        if (clear_line_controller != null)
        {
            int cleared = clear_line_controller.check_and_clear_lines();
            if (cleared > 0)
            {
                // 更新总消行数
                total_lines_cleared += cleared;

                // 更新最大连击
                int combo = clear_line_controller.get_combo_count();
                if (combo > max_combo)
                    max_combo = combo;

                // 更新最大BTB
                int btb = clear_line_controller.get_btb_count();
                if (btb > max_btb)
                    max_btb = btb;

                // 检测是否有Spin
                string spin_text = clear_line_controller.get_current_spin_text();
                if (spin_text.Length != 0)
                    total_spins += 1;

                // 获取攻击伤害值
                int damage = clear_line_controller.get_current_damage();

                // 记录消行事件
                // 回放系统仅保留用户输入和垃圾行输入，派生事件不再记录

                // 记录造成攻击（APM）
                if (damage > 0)
                    _record_attack_damage(damage);

                // 如果有伤害且垃圾槽不为空，执行抵消
                if (damage > 0 && garbage_line_controller != null && garbage_line_controller.get_enter_queue_size() > 0)
                {
                    int offset_count = garbage_line_controller.offset_garbage(damage);
                    // 抵消的部分作为奖励也输入给塔
                    if (offset_count > 0 && tower_controller != null)
                        tower_controller.attack_increase_tower(offset_count);
                }
            }
            return cleared;
        }
        return 0;
    }

    /// <summary>添加攻击（由外部调用）</summary>
    public void add_garbage_attack(int attack_count)
    {
        if (garbage_line_controller != null)
        {
            garbage_line_controller.add_attack(attack_count);
            // 记录接收攻击（RPM）
            _record_received_damage(attack_count);
        }
    }

    // ========== 旋转系统 ==========

    /// <summary>左旋（逆时针旋转90度）</summary>
    public void rotate_left()
    {
        _rotate_piece(-1);
    }

    /// <summary>右旋（顺时针旋转90度）</summary>
    public void rotate_right()
    {
        _rotate_piece(1);
    }

    /// <summary>180度旋转</summary>
    public void rotate_180()
    {
        _rotate_piece(2);
    }

    /// <summary>旋转方块核心逻辑</summary>
    public bool _rotate_piece(int direction)
    {
        if (current_piece.Count == 0)
            return false;  // 手上无方块（延迟期间）：不旋转
        switch (direction)
        {
            case 1:  // 顺时针旋转 90度
                _apply_rotation_with_kick(_get_rotated_matrix(current_piece, 1), 1);
                break;
            case -1:  // 逆时针旋转 90度
                _apply_rotation_with_kick(_get_rotated_matrix(current_piece, -1), -1);
                break;
            case 2:  // 180度旋转
                _apply_rotation_with_kick(_get_rotated_matrix(current_piece, 2), 2);
                break;
            default:
                return false;
        }
        return true;
    }

    /// <summary>应用旋转并尝试踢墙</summary>
    public bool _apply_rotation_with_kick(Godot.Collections.Array rotated_piece, int direction)
    {
        // 获取踢墙表偏移
        var kicks = get_kick_table();
        int kick_multiplier = 1;

        // 根据旋转方向确定踢墙偏移乘数
        switch (direction)
        {
            case 1:  // 右旋：使用原始偏移
                kick_multiplier = 1;
                break;
            case -1:  // 左旋：X方向取反
                kick_multiplier = -1;
                break;
            case 2:  // 180度旋转：使用原始偏移（对称）
                kick_multiplier = 1;
                break;
        }

        foreach (var kickVariant in kicks)
        {
            var kick = kickVariant.AsGodotArray();
            int kick_x = (int)(long)kick[0] * kick_multiplier;
            int kick_y = (int)(long)kick[1];
            var new_pos = new Vector2I(current_position.X + kick_x, current_position.Y + kick_y);

            if (!_check_collision(new_pos, rotated_piece))
            {
                // 旋转成功
                _clear_current_piece();
                current_piece = rotated_piece;
                current_position = new_pos;
                _draw_current_piece();

                // 记录旋转事件（用于Spin检测），传递方块颜色
                if (clear_line_controller != null)
                    clear_line_controller.record_rotation(current_piece_type, current_piece, current_position, current_color);

                _check_underground_touch();

                // 旋转后重置锁延
                if (lock_times_limit > 0 && !lock_timer.IsStopped())
                {
                    lock_timer.Stop();
                    lock_timer.Start();
                    lock_times_limit -= 1;
                }

                _update_shadow();
                return true;
            }
        }

        // 所有踢墙尝试都失败
        return false;
    }

    /// <summary>获取旋转后的矩阵</summary>
    public Godot.Collections.Array _get_rotated_matrix(Godot.Collections.Array piece, int direction)
    {
        int rows = piece.Count;
        var firstRow = piece[0].AsGodotArray();
        int cols = firstRow.Count;
        var rotated = new Godot.Collections.Array();

        switch (direction)
        {
            case 1:  // 顺时针旋转 90度
                for (int i = 0; i < cols; i++)
                {
                    var newRow = new Godot.Collections.Array();
                    for (int j = 0; j < rows; j++)
                    {
                        var row = piece[rows - 1 - j].AsGodotArray();
                        newRow.Add(row[i]);
                    }
                    rotated.Add(newRow);
                }
                break;
            case -1:  // 逆时针旋转 90度
                for (int i = 0; i < cols; i++)
                {
                    var newRow = new Godot.Collections.Array();
                    for (int j = 0; j < rows; j++)
                    {
                        var row = piece[j].AsGodotArray();
                        newRow.Add(row[cols - 1 - i]);
                    }
                    rotated.Add(newRow);
                }
                break;
            case 2:  // 180度旋转
                for (int i = 0; i < rows; i++)
                {
                    var newRow = new Godot.Collections.Array();
                    var row = piece[rows - 1 - i].AsGodotArray();
                    for (int j = 0; j < cols; j++)
                        newRow.Add(row[cols - 1 - j]);
                    rotated.Add(newRow);
                }
                break;
        }

        return rotated;
    }

    // ========== 暂存系统 ==========

    /// <summary>暂存当前方块</summary>
    public bool hold_current_piece()
    {
        if (current_piece.Count == 0)
            return false;  // 手上无方块（延迟期间）：不可暂存
        if (no_hold)
            return false;  // NoHold模式：禁用暂存
        if (!can_hold)
            return false;  // 本回合已使用过暂存

        // 清除当前方块
        _clear_current_piece();

        // 如果暂存区为空，将当前方块存入暂存，然后生成新方块
        if (hold_piece.Count == 0)
        {
            // 保存当前方块的原始形状（未旋转状态）
            hold_piece = bag_controller.get_original_shape(current_piece_type);
            hold_color = current_color;
            hold_piece_type = current_piece_type;
            hold_original_shape = bag_controller.get_original_shape(current_piece_type);

            // 更新Hold显示
            board_drawer.set_hold_piece(hold_piece, hold_color);

            // 生成新方块（保持hold状态）
            spawn_new_piece_keep_hold();
        }
        else
        {
            // 暂存区有方块时，进行交换
            // 先保存当前方块的完整信息
            var temp_piece = current_piece;
            Color temp_color = current_color;
            string temp_type = current_piece_type;
            var temp_original = current_original_shape;

            // 从暂存区取出方块
            current_piece = bag_controller.get_original_shape(hold_piece_type);
            current_color = hold_color;
            current_piece_type = hold_piece_type;
            current_original_shape = hold_original_shape;

            // 将当前方块存入暂存区
            hold_piece = bag_controller.get_original_shape(temp_type);
            hold_color = temp_color;
            hold_piece_type = temp_type;
            hold_original_shape = temp_original;

            // 更新Hold显示
            board_drawer.set_hold_piece(hold_piece, hold_color);

            // 重置位置（从下往上数第22行）
            int spawn_x = (int)((board_drawer.grid_width - current_piece[0].AsGodotArray().Count) / 2);
            int spawn_y = Mathf.Max(0, board_drawer.grid_height + board_drawer.above_visible_rows - 22);
            current_position = new Vector2I(spawn_x, spawn_y);

            // 检查生成时是否碰撞（游戏结束判定）
            if (_check_collision(current_position))
            {
                GD.PushError("游戏结束！无法生成方块");
                // 如果交换后发生碰撞，恢复原状
                current_piece = temp_piece;
                current_color = temp_color;
                current_piece_type = temp_type;
                current_original_shape = temp_original;
                hold_piece = bag_controller.get_original_shape(hold_piece_type);
                hold_color = temp_color;  // 恢复hold颜色
                board_drawer.set_hold_piece(hold_piece, hold_color);
                _draw_current_piece();
                return false;
            }

            // 绘制方块到版面
            _draw_current_piece();
            _update_shadow();

            // 重置锁定状态
            lock_timer.Stop();
            lock_times_limit = lock_times_limit_max;
        }

        // 标记暂存已使用
        can_hold = false;
        return true;
    }

    /// <summary>获取当前暂存的方块（用于显示）</summary>
    public Godot.Collections.Array get_hold_piece()
    {
        return hold_piece;
    }

    /// <summary>获取暂存方块的颜色</summary>
    public Color get_hold_color()
    {
        return hold_color;
    }

    /// <summary>清空暂存</summary>
    public void clear_hold()
    {
        hold_piece = new Godot.Collections.Array();
        hold_color = Colors.White;
        hold_piece_type = "";
        hold_original_shape = new Godot.Collections.Array();
    }

    // ========== 公共控制方法 ==========

    /// <summary>计算影子位置（硬降到底的位置）</summary>
    public Vector2I _calculate_shadow_position()
    {
        if (current_piece.Count == 0)
            return Vector2I.Zero;

        var shadow_pos = current_position;

        // 一直向下移动直到碰撞
        while (true)
        {
            var test_pos = new Vector2I(shadow_pos.X, shadow_pos.Y + 1);
            if (_check_collision(test_pos, current_piece))
                break;
            shadow_pos = test_pos;
        }

        return shadow_pos;
    }

    /// <summary>更新影子显示</summary>
    public void _update_shadow()
    {
        if (board_drawer != null)
        {
            if (current_piece.Count == 0)
                board_drawer.clear_shadow();
            else
            {
                var shadow_pos = _calculate_shadow_position();
                board_drawer.update_shadow(current_piece, shadow_pos, current_color);
            }
        }
    }

    /// <summary>左移</summary>
    public void move_left()
    {
        _try_move(-1, 0);
    }

    /// <summary>右移</summary>
    public void move_right()
    {
        _try_move(1, 0);
    }

    /// <summary>软降（单步向下）</summary>
    public void soft_drop()
    {
        _try_move(0, 1);
    }

    /// <summary>
    /// 软降到底（不锁定）：bot 路径中的 "soft_drop" 动作（ColdClear SonicDrop）使用本方法，
    /// 对应将当前方块一直下落到触底位置，但不像 hard_drop 那样立即锁定，等待后续 hard_drop 锁定。
    /// </summary>
    public void soft_drop_to_bottom()
    {
        if (current_piece.Count == 0)
            return;  // 手上无方块（延迟期间）：不下落
        while (_try_move(0, 1))
        {
            // pass
        }
    }

    /// <summary>硬降（直接落底）</summary>
    public void hard_drop()
    {
        if (current_piece.Count == 0)
            return;  // 手上无方块（延迟期间）：不硬降
        // 一直向下移动直到碰撞
        while (_try_move(0, 1))
        {
            // pass  // 继续移动
        }

        // 调试：打印锁定前的最终位置（对比 CC 决策期望落点）
        // if bot_debug_log:
        // 	print("[BotLock] piece=", current_piece_type, " final=(", current_position.x, ",", current_position.y, ")")

        // 触底后立即锁定
        _lock_piece();
    }

    // ========== 更新循环 ==========

    public override void _Process(double delta)
    {
        // 检测 ExitGame 映射（Esc）：按下则退出当前关卡到 EXIT_PATH（buff选择）界面
        // 与游戏结束界面 BACK 按钮一致：置位 restore_buffs，返回 buff 界面时预勾选本次已选 buff
        if (Input.IsActionJustPressed("ExitGame"))
        {
            GlobalData.restore_buffs = true;
            GetTree().ChangeSceneToFile(EXIT_PATH);
            return;
        }

        if (bot_mode)
        {
            _process_bot_control((float)delta);
            // 【暂时注释】bot 决策预览：同步 bridge 的 cc_plan_placements 转棋盘坐标绘制格子。
            // 因预览块与实际放置仍有重叠/观感问题，先临时禁用；恢复时取消下面这行注释即可。
            // _sync_bot_plan_display()
            // bot 模式下方块的下落/落点完全由 ColdClear 决策路径驱动（软降/硬降），
            // 因此不再调用 gravity_drop：若在等待决策或冷却期间让方块自发下滑，
            // 会破坏基于「方块仍在 spawn 位」规划的移动/踢墙序列（表现为 missdrop/错乱）。
            return;
        }

        // if not replay_input_override:  # 回放系统已禁用
        change_key_press_to_var();
        //TODO::回放系统模拟按键输入
        replay_set_keyvar_input();
        _game_process_input();
        check_for_var_single_press();
        gravity_drop();
    }

    public void _ensure_coldclear_bridge()
    {
        if (_coldclear_bridge != null)
            return;
        _coldclear_bridge = new ColdClearBridge();
        AddChild(_coldclear_bridge);
    }

    public void _process_bot_control(float delta)
    {
        _ensure_coldclear_bridge();
        if (_coldclear_bridge == null)
            return;
        if (current_piece.Count == 0)
            return;

        // —— 窒息/卡住保护：同一方块在手超过阈值仍未落子 → 强制硬降，保证触发顶出判定 ——
        if (_bot_stall_serial != _bot_piece_serial)
        {
            _bot_stall_serial = _bot_piece_serial;
            _bot_stall_timer = 0.0f;
        }
        else
        {
            _bot_stall_timer += delta;
        }
        if (_bot_stall_timer >= bot_stall_drop_time)
        {
            // 放弃在途决策/旧计划并强制放下当前方块（后续回复因 request_id 不匹配会被忽略）
            if (_coldclear_bridge != null)
                _coldclear_bridge.reset_for_stall();
            hard_drop();
            _schedule_next_bot_drop();
            _bot_stall_timer = 0.0f;
            return;
        }

        // 新块开始：立即请求原生决策，与落块冷却并行进行，
        // 避免「决策耗时」累积到每块周期之上导致实际 PPS 低于 bot_target_pps。
        if (_bot_tracking_piece_serial != _bot_piece_serial)
        {
            _bot_tracking_piece_serial = _bot_piece_serial;
            if (_coldclear_bridge.using_native_cc())
                _coldclear_bridge.request_plan(this);
        }

        if (_bot_piece_cooldown > 0.0f)
            _bot_piece_cooldown = Mathf.Max(0.0f, _bot_piece_cooldown - delta);

        if (_bot_next_action_time > 0.0f)
        {
            _bot_next_action_time = Mathf.Max(0.0f, _bot_next_action_time - delta);
            return;
        }

        // 垃圾行抬升期间版面已变化（force_raise_rows 已递增 board_version）。
        // 注意：垃圾上涨是整版（含当前方块）同步上移（force_raise_rows 会把当前方块一并上移），
        // 因此当前方块相对堆叠的落点与形状不变，其正在执行的旧计划（相对移动序列）依然有效。
        // 若在此打断并重新规划，新计划按"方块在 spawn 位"生成，而方块实际已移动/已按旧计划走了
        // 若干步，会导致当前块 missdrop。所以仅当本块完全没有计划（如首次请求失败）时，才基于
        // 新版面重试；否则继续执行旧计划，待本块锁定后由"新块开始"逻辑按新版面请求。
        if (garbage_line_controller != null && _bot_tracking_board_version != garbage_line_controller.board_version)
        {
            _bot_tracking_board_version = garbage_line_controller.board_version;
            // 避免请求堆积：若已有在途决策（正在等待），交给其完成后自然对账；否则才重新请求。
            if (_coldclear_bridge.using_native_cc() && !_coldclear_bridge.is_waiting_decision())
            {
                if (_coldclear_bridge.is_plan_empty())
                    _coldclear_bridge.request_plan(this);
            }
        }

        // 等待原生 ColdClear 异步决策期间，暂停动作
        if (_coldclear_bridge.using_native_cc() && _coldclear_bridge.is_waiting_decision())
            return;

        // 无可用原生计划（原生不可用/决策失败/计划已消费）时，直接硬降锁定当前块
        if (!_coldclear_bridge.using_native_cc() || !_coldclear_bridge.has_plan())
        {
            if (_bot_piece_cooldown > 0.0f)
            {
                _bot_next_action_time = Mathf.Min(_bot_piece_cooldown, 0.05f);
                return;
            }
            hard_drop();
            _schedule_next_bot_drop();
            return;
        }

        // 【可选】直接放置：不做逐帧移动节奏限制，一次调用内把整条路径的所有动作（横移/
        // 旋转/软降）连续执行到位，最后硬降锁定——避免途中移动耗时。hold 会短暂清空当前块
        // （交换/生成新块），故本帧停在 hold 后，下一帧继续该块剩余移动。
        if (bot_instant_place)
        {
            // PPS 限制：未到每块最小间隔前，等待
            if (_bot_piece_cooldown > 0.0f)
            {
                _bot_next_action_time = Mathf.Min(_bot_piece_cooldown, 0.05f);
                return;
            }
            int guard = 0;
            bool did_drop = false;
            while (_coldclear_bridge.has_plan() && guard < 300)
            {
                guard += 1;
                var inst_action = _coldclear_bridge.next_plan_action();
                if (inst_action == null || inst_action.move.Length == 0)
                    break;
                _apply_bot_action(inst_action);
                string mv = inst_action.move;
                if (mv == "hard_drop")
                {
                    did_drop = true;
                    break;
                }
                if (mv == "hold")
                    break;
            }
            if (did_drop)
            {
                _schedule_next_bot_drop();
            }
            return;
        }

        // 执行计划中的下一个动作
        var decided_action = _coldclear_bridge.next_plan_action();
        if (decided_action == null || decided_action.move.Length == 0)
            decided_action = new BotAction("hard_drop", new Godot.Collections.Array { "hard_drop" }, "hard_drop");

        // PPS限制核心：未到每块最小间隔前，阻止hard_drop锁定新块。
        if (_bot_piece_cooldown > 0.0f && decided_action.move == "hard_drop")
        {
            _bot_next_action_time = Mathf.Min(_bot_piece_cooldown, 0.05f);
            return;
        }

        _apply_bot_action(decided_action);

        if (decided_action.move == "hard_drop")
            _bot_piece_cooldown = _get_bot_piece_interval();

        float action_interval = _get_bot_action_interval();
        if (action_interval > 0.0f)
            _bot_next_action_time = Mathf.Min(action_interval, bot_native_action_interval);
    }

    /// <summary>把 CC 决策出的动作（BotAction）映射到游戏内直接调用</summary>
    public void _apply_bot_action(BotAction action)
    {
        if (action == null)
            return;
        // 调试：打印每步动作执行前的方块位置，用于对照 CC 决策 movements
        // if bot_debug_log:
        // 	print("[BotStep] ", String(action.move), " before=(", current_position.x, ",", current_position.y, ")")
        switch (action.move)
        {
            case "left":
                move_left();
                break;
            case "right":
                move_right();
                break;
            case "rotate_left":
                rotate_left();
                break;
            case "rotate_right":
                rotate_right();
                break;
            case "rotate_180":
                rotate_180();
                break;
            case "soft_drop":
                // ColdClear 的 'D'(CC_DROP) 在引擎里是 PieceMovement::SonicDrop（直接下落到触底），
                // 本游戏软降默认也是直接触底（softdrop_delay==0 → 一路 drop 到底），所以用
                // soft_drop_to_bottom() 完全对应。CC 的 'D' 通常出现在路径末尾（或由最后 hard_drop
                // 兜底触底），因此这样映射不会造成误放置；若计划中段出现 'D'，会先触底再继续横移，
                // 此时需保证已落在堆叠上（CC 搜索不会生成触底后还需横移的路径）。
                soft_drop_to_bottom();
                break;
            case "hold":
                hold_current_piece();
                break;
            case "hard_drop":
                hard_drop();
                break;
        }
    }

    public float _get_bot_action_interval()
    {
        if (bot_target_pps <= 0.0f)
            return 0.0f;
        // 目标为每秒可完成的方块数，简单换算为每步动作节奏上限
        return 1.0f / Mathf.Max(bot_target_pps * 4.0f, 0.001f);
    }

    public float _get_bot_piece_interval()
    {
        if (bot_target_pps <= 0.0f)
            return 0.0f;
        return 1.0f / Mathf.Max(bot_target_pps, 0.001f);
    }

    /// <summary>
    /// 计算并设置下一块落子的冷却时间（PPS 校准）：
    /// 目标周期 = 1/bot_target_pps；实际周期 = 冷却 + 帧/调度等固定开销。
    /// 用真实毫秒记录上一块「实际周期 - 目标周期」的超出量（滑动均值），从本块冷却里扣掉，
    /// 使落块间距收敛到目标周期，让游戏内 PPS 显示贴合 bot_target_pps。
    /// 冷却下限 0.02s，避免过度补偿导致失控；决策本身慢于目标周期时无法再压缩（属正常）。
    /// </summary>
    public void _schedule_next_bot_drop()
    {
        float interval = _get_bot_piece_interval();
        ulong now = Time.GetTicksMsec();
        if (_bot_last_drop_ms != 0)
        {
            long diff = (long)(now - _bot_last_drop_ms);
            float overshoot = (diff / 1000.0f) - interval;
            if (overshoot > 0.0005f)
                _bot_cycle_overshoot_ema = 0.7f * _bot_cycle_overshoot_ema + 0.3f * overshoot;
            else
                _bot_cycle_overshoot_ema = Mathf.Max(0.0f, 0.7f * _bot_cycle_overshoot_ema + 0.3f * overshoot);
        }
        _bot_last_drop_ms = now;

        float cooldown = interval;
        if (_bot_cycle_overshoot_ema > 0.0005f)
            cooldown = Mathf.Max(interval - _bot_cycle_overshoot_ema, 0.02f);
        // 额外扣除约一帧的调度/量化开销（60fps ≈ 0.0167s），让实测间距进一步贴近目标周期
        cooldown = Mathf.Max(cooldown - 0.008f, 0.015f);
        _bot_piece_cooldown = cooldown;
    }

    /// <summary>
    /// 同步 bot 落块决策预览（当前调用方已临时禁用，见 _process；保留实现）。
    /// </summary>
    public void _sync_bot_plan_display()
    {
        if (board_drawer == null)
            return;
        if (!bot_mode || _coldclear_bridge == null || !_coldclear_bridge.using_native_cc())
        {
            board_drawer.clear_bot_plan();
            _last_bot_plan_cache = new Godot.Collections.Array();
            _last_bot_plan_serial = -1;
            return;
        }
        // 正在等待新的异步决策：尚无新计划，直接沿用上一帧已算好的缓存预览，保证预览
        // 不出现空档。若期间已进入新块（_bot_piece_serial 变化），则缓存预览的 plan[0]
        // 对应的正是刚锁定的那一块——把它丢弃（避免把已锁定块再当幽灵重复显示），
        // 其余未来块继续保留，直到新计划到达后整体替换。
        if (_coldclear_bridge.is_waiting_decision())
        {
            var frozen = _last_bot_plan_cache;
            if (_last_bot_plan_serial != _bot_piece_serial && frozen.Count > 1)
            {
                var newFrozen = new Godot.Collections.Array();
                for (int fi = 1; fi < frozen.Count; fi++)
                    newFrozen.Add(frozen[fi]);
                frozen = newFrozen;
            }
            board_drawer.set_bot_plan(frozen);
            return;
        }
        // CC 窗口的底行对应游戏棋盘最后一行（可见顶above行的起点 + 可见高度 - 1）
        int grid_w = board_drawer.grid_width;
        int playable = board_drawer.grid_height + board_drawer.above_visible_rows;
        int bottom_game_y = playable - 1;
        // 基础堆栈 = 当前已锁定棋盘（排除正在下落的当前方块，与 CC 收到的版面一致）。
        var occ = _build_plan_stack_occupancy(grid_w, playable);
        var placed = new Godot.Collections.Array();
        int plan_max = Mathf.Max(0, bot_plan_max_pieces);
        int plan_count = 0;
        foreach (var plVariant in _coldclear_bridge.cc_plan_placements)
        {
            if (plan_max > 0 && plan_count >= plan_max)
                break;
            if (plVariant.VariantType != Variant.Type.Dictionary)
                continue;
            plan_count += 1;
            var pl = plVariant.AsGodotDictionary();
            var cells = pl["cells"].AsGodotArray();
            var gcells = new Godot.Collections.Array();
            foreach (var cVariant in cells)
            {
                var c = cVariant.AsGodotArray();
                if (c.Count < 2)
                    continue;
                // CC y 向上（0=底）→ 游戏 y 向下：gy = bottom_game_y - cc_y
                gcells.Add(new Godot.Collections.Array()
                {
                    (long)(int)c[0],
                    (long)(bottom_game_y - (int)c[1]),
                });
            }
            if (gcells.Count < 4)
                continue;
            var rest = _place_plan_piece_solid(gcells, occ, grid_w, playable);
            if (rest.Count == 0)
                continue;
            foreach (var cc in rest)
            {
                var coord = cc.AsGodotArray();
                occ[new Vector2I((int)coord[0], (int)coord[1])] = true;
            }
            placed.Add(new Godot.Collections.Dictionary()
            {
                { "cells", rest },
                { "color", _get_plan_piece_color(pl.ContainsKey("type") ? pl["type"].AsString() : "I") },
            });
        }
        // 缓存本次算好的预览及其对应的方块序号，供异步等待期间沿用（避免空档）
        _last_bot_plan_cache = placed.Duplicate(true);
        _last_bot_plan_serial = _bot_piece_serial;
        board_drawer.set_bot_plan(placed);
    }

    /// <summary>
    /// 构建 bot 规划堆叠的基础占用表：把当前锁定棋盘（board_data）视为实心，
    /// 但剔除当前正在下落的方块（其会随垃圾抬升/锁定变化，不计入静态底）。
    /// 返回 Dictionary，key 为 Vector2I(x,y)（游戏坐标，y 向下），value=true 表示占用。
    /// </summary>
    public Godot.Collections.Dictionary _build_plan_stack_occupancy(int grid_w, int playable)
    {
        var occ = new Godot.Collections.Dictionary();
        var bd = board_drawer.board_data;
        var cur_cells = new Godot.Collections.Dictionary();
        if (current_piece.Count != 0)
        {
            for (int yy = 0; yy < current_piece.Count; yy++)
            {
                var row = current_piece[yy].AsGodotArray();
                for (int xx = 0; xx < row.Count; xx++)
                {
                    if (row[xx].AsInt64() == 1)
                        cur_cells[new Vector2I(current_position.X + xx, current_position.Y + yy)] = true;
                }
            }
        }
        for (int y = 0; y < Mathf.Min(playable, bd.Count); y++)
        {
            var row = bd[y].AsGodotArray();
            for (int x = 0; x < Mathf.Min(grid_w, row.Count); x++)
            {
                if (row[x].VariantType == Variant.Type.Nil)
                    continue;
                var key = new Vector2I(x, y);
                if (cur_cells.ContainsKey(key))
                    continue;
                occ[key] = true;
            }
        }
        return occ;
    }

    /// <summary>
    /// 把单个落块放置到实心堆栈 occ 上（满行永不消除），使用 CC 真实落点（含踢墙/旋转
    /// 结果的横向与形状）。**严格不重叠**：预览的每一格都必须落在空位，绝不允许与实心块
    /// 重合。若真实落点（CC 消行后的坐标）与保留的实心满行冲突，则把整块上移一行重试，
    /// 直到完全无冲突——块就叠在实心堆栈之上（砖墙式）。返回 4 格 [x,y]；整块移出棋盘顶部仍冲突返回空数组。
    /// </summary>
    public Godot.Collections.Array _place_plan_piece_solid(Godot.Collections.Array cells, Godot.Collections.Dictionary occ, int grid_w, int playable)
    {
        if (cells.Count < 4)
            return new Godot.Collections.Array();
        var placed_cells = new Godot.Collections.Array();
        foreach (var c in cells)
        {
            var coord = c.AsGodotArray();
            placed_cells.Add(new Godot.Collections.Array()
            {
                (long)(int)coord[0],
                (long)(int)coord[1],
            });
        }
        while (true)
        {
            bool valid = true;
            foreach (var cVariant in placed_cells)
            {
                var c = cVariant.AsGodotArray();
                var key = new Vector2I((int)c[0], (int)c[1]);
                if (key.X < 0 || key.X >= grid_w || key.Y < 0 || key.Y >= playable)
                {
                    valid = false;
                    break;
                }
                if (occ.ContainsKey(key))
                {
                    valid = false;
                    break;
                }
            }
            if (valid)
                break;
            foreach (var cVariant in placed_cells)
            {
                var c = cVariant.AsGodotArray();
                c[1] = (long)((int)c[1] - 1);
            }
            bool all_above = true;
            foreach (var cVariant in placed_cells)
            {
                var c = cVariant.AsGodotArray();
                if ((int)c[1] >= 0)
                {
                    all_above = false;
                    break;
                }
            }
            if (all_above)
                return new Godot.Collections.Array();
        }
        return placed_cells;
    }

    /// <summary>获取方块类型对应的绘制颜色（与游戏实体方块一致，来自 BlockData.json）</summary>
    public Color _get_plan_piece_color(string piece_type)
    {
        if (bag_controller != null && bag_controller.piece_data.ContainsKey(piece_type))
        {
            var data = bag_controller.piece_data[piece_type];
            if (data.VariantType == Variant.Type.Dictionary)
            {
                var d = data.AsGodotDictionary();
                if (d.ContainsKey("color"))
                    return d["color"].AsColor();
            }
        }
        return Colors.White;
    }

    /// <summary>处理键盘输入</summary>
    public void _game_process_input()
    {
        // 手上无方块（生成/消行延迟期间）：不处理输入，避免对空方块执行旋转/暂存/硬降
        if (current_piece.Count == 0)
            return;
        // arr和das判定
        if ((long)press_key["LeftMove"] == 1 && (long)press_key["RightMove"] == 1)
        {
            if (!double_press)
            {
                direction_press *= -1;
                move_start_timer.Paused = true;
                move_keep_timer.Stop();
                keep_press_move = false;
            }
            double_press = true;
        }
        else
        {
            double_press = false;
            if ((long)press_key["LeftMove"] == 1)
            {
                if (direction_press == 1)
                {
                    move_start_timer.Paused = true;
                    move_keep_timer.Stop();
                    keep_press_move = false;
                }
                direction_press = -1;
            }
            if ((long)press_key["RightMove"] == 1)
            {
                if (direction_press == -1)
                {
                    move_start_timer.Paused = true;
                    move_keep_timer.Stop();
                    keep_press_move = false;
                }
                direction_press = 1;
            }
            if (!((long)press_key["LeftMove"] == 1 || (long)press_key["RightMove"] == 1))
                direction_press = 0;
        }
        // 左右移动
        if (direction_press != 0)
        {
            if (move_arr != 0)
            {
                if (move_start_timer.IsStopped() && move_keep_timer.IsStopped())
                {
                    _try_move(direction_press, 0);
                    move_keep_timer.Start();
                }
            }
            else
            {
                if (move_start_timer.IsStopped() && !keep_press_move)
                {
                    _try_move(direction_press, 0);
                }
                else if (move_start_timer.IsStopped() && keep_press_move && !_check_collision(current_position + new Vector2I(direction_press, 0)))
                {
                    bool one_drop = true;
                    while (_try_move(direction_press, 0))
                    {
                        if (!_check_collision(current_position + new Vector2I(0, 1)) && one_drop && (long)press_key["SoftDrop"] == 1)
                        {
                            while (_try_move(0, 1) && one_drop)
                            {
                                if (softdrop_delay != 0)
                                    one_drop = false;
                            }
                        }
                        if (gravity_drop_time == 0 && !_check_collision(current_position + new Vector2I(0, 1)))
                        {
                            while (_try_move(0, 1))
                            {
                                // pass
                            }
                        }
                    }
                }
                else
                {
                    // pass
                }
            }
        }
        if (direction_press != 0 && !keep_press_move)
        {
            move_start_timer.Paused = false;
            move_start_timer.Start();
            keep_press_move = true;
        }
        else if (direction_press == 0)
        {
            move_start_timer.Stop();
            move_keep_timer.Stop();
            keep_press_move = false;
        }
        else
        {
            // pass
        }

        // 软降
        if ((long)press_key["SoftDrop"] == 1 && softdrop_timer.IsStopped())
        {
            if (softdrop_delay != 0)
            {
                soft_drop();
                softdrop_timer.Start();
            }
            else if (softdrop_delay == 0)
            {
                if (!_check_collision(current_position + new Vector2I(0, 1)))
                {
                    while (_try_move(0, 1))
                    {
                        // pass
                    }
                }
            }
            else
            {
                GD.PushError("发生意料之外的错误！");
            }
        }

        // 旋转
        if ((long)press_key["LeftSpin"] == 1 && (long)check_for_single_press["LeftSpin"] != 1)
            rotate_left();

        if ((long)press_key["RightSpin"] == 1 && (long)check_for_single_press["RightSpin"] != 1)
            rotate_right();

        // 180度旋转
        if ((long)press_key["SwapSpin"] == 1 && (long)check_for_single_press["SwapSpin"] != 1)
            rotate_180();

        // 暂存（NoHold模式下不读取Hold输入）
        if ((long)press_key["HoldBlock"] == 1 && (long)check_for_single_press["HoldBlock"] != 1 && !no_hold)
            hold_current_piece();

        // 硬降
        if ((long)press_key["HardDrop"] == 1 && (long)check_for_single_press["HardDrop"] != 1)
            hard_drop();
    }

    public void change_key_press_to_var()
    {
        foreach (var keyVariant in press_key.Keys)
        {
            string key = keyVariant.AsString();
            if (Input.IsActionPressed(key))
                press_key[key] = (long)1;
            else
                press_key[key] = (long)0;
        }
    }

    public void check_for_var_single_press()
    {
        foreach (var keyVariant in check_for_single_press.Keys)
        {
            string key = keyVariant.AsString();
            if ((long)press_key[key] == 1 && (long)check_for_single_press[key] == 0)
                check_for_single_press[key] = (long)1;
            else if ((long)press_key[key] == 0)
                check_for_single_press[key] = (long)0;
            else
            {
                // pass
            }
        }
    }

    // TODO::回放系统模拟按键输入
    public void replay_set_keyvar_input()
    {
        // pass
    }

    public void gravity_drop()
    {
        // 手上无方块（生成/消行延迟期间）：跳过下落逻辑
        if (current_piece.Count == 0)
            return;
        if (gravity_timer.IsStopped() && gravity_drop_time != 0)
        {
            _try_move(0, 1);
            // garbage_line_controller.add_attack(5)
            gravity_timer.Start();
        }
        if (gravity_drop_time == 0)
        {
            if (!_check_collision(current_position + new Vector2I(0, 1)))
            {
                while (_try_move(0, 1))
                {
                    // pass
                }
            }
        }
    }

    // ========== 辅助方法 ==========

    /// <summary>获取当前方块的宽度</summary>
    public int get_current_piece_width()
    {
        if (current_piece.Count == 0)
            return 0;
        return current_piece[0].AsGodotArray().Count;
    }

    /// <summary>获取当前方块的高度</summary>
    public int get_current_piece_height()
    {
        return current_piece.Count;
    }

    /// <summary>手动设置方块（用于扩展）</summary>
    public void set_piece(Godot.Collections.Array piece, Color color, string piece_type = "I")
    {
        current_piece = piece;
        current_color = color;
        current_piece_type = piece_type;
        current_original_shape = bag_controller.get_original_shape(piece_type);
        spawn_new_piece();
    }

    // ========== 回放输入覆盖（已禁用空接口，仅保证 replay_player 可编译） ==========

    /// <summary>开启/关闭回放输入覆盖（已禁用，不生效）</summary>
    public void set_replay_input_override(bool enabled)
    {
        // replay_input_override = enabled
        // change_key_press_to_var()
        // pass（已禁用）
    }

    /// <summary>用于回放系统模拟真实按键输入（已禁用，不生效）</summary>
    public void set_replay_input(string action, bool pressed)
    {
        // press_key[action] = 1 if pressed else 0
        // _game_process_input()
        // if pressed and check_for_single_press.has(action):
        // 	check_for_single_press[action] = 1
        // elif not pressed and check_for_single_press.has(action):
        // 	check_for_single_press[action] = 0
        // pass（已禁用）
    }

    /// <summary>获取当前种子（用于Replay录制）（已禁用，保留访问器）</summary>
    public long get_current_seed()
    {
        return RandomManager.get_current_seed();
    }

    // ---- 调试辅助（确定性测试用；不影响玩法逻辑）----

    /// <summary>以固定种子重置 RandomManager（确定性测试用）</summary>
    public void debug_seed(long seed)
    {
        RandomManager.initialize(seed);
    }
}
