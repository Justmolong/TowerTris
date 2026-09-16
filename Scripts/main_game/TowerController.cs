using Godot;

public partial class TowerController : Node2D
{
    public static string ATTACK_DATA_PATH = "user://Savedatas/attack_setting.json";
    public static Godot.Collections.Array FLOOR_HIGHER = new Godot.Collections.Array()
    {
        (long)0, (long)50, (long)150, (long)300, (long)450, (long)650, (long)850,
        (long)1100, (long)1350, (long)1650, (long)2550, (long)3000, (long)3500,
        (long)4500, (long)5500, (long)6500, (long)8000, (long)9500, (long)11000,
    };

    [Export]
    public TetrisController tetris_controller;
    [Export]
    public TetrisGarbageLineController garbage_line_controller;
    [Export]
    public TetrisBoardDrawer board_drawer;
    [Export]
    public TetrisClearLine clear_line_controller;

    public RandomNumberGenerator tower_rng;

    public float total_apm = 100.0f;
    public Godot.Collections.Array stage_percent_apm = new Godot.Collections.Array() { 0.01, 0.02, 0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.8, 1 };
    public int current_stage = 0;
    public float current_apm = 0;
    public float extra_percent_apm = 0;

    public Godot.Collections.Array publish_time_array = new Godot.Collections.Array() { 0, 60 * 7, 60 * 8, 60 * 9, 60 * 10, 60 * 11 };
    public int publish_stage = 0;
    public int publish_make_finish = 0;
    public float publish_mult_attack = 1.0f;

    public Godot.Collections.Array stage_garbage_time = new Godot.Collections.Array() { 10, 8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 2, 2, 1, 1, 1, 0.5 };
    public Godot.Collections.Array stage_garbage_divide = new Godot.Collections.Array();
    public float garbage_collect_percent = 0.1f;
    public Godot.Collections.Array garbage_collect_percent_array = new Godot.Collections.Array() { 0.4, 0.3, 0.2, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.2 };
    public float garbage_sent_time = 0;
    public float garbage_divide_percent = 0;
    public Godot.Collections.Array garbage_divide_percent_array = new Godot.Collections.Array() { 0.8, 0.6, 0.4, 0.2, 0.2, 0.1, 0.1, 0, 0.1, 0.2, 0.3 };
    public Godot.Collections.Array garbage_hole_change_percent_array = new Godot.Collections.Array() { 0.1, 0.1, 0.1, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 };
    public int collected_count = 0;
    public Godot.Collections.Array collected_garbage = new Godot.Collections.Array();
    public Godot.Collections.Array pressure_mult_array = new Godot.Collections.Array() { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 7 };
    public float pressure_mult = 1.0f;
    public float send_mult_attack = 1.0f;

    public Godot.Collections.Array gravity_drop_time_array = new Godot.Collections.Array() { 5 };
    public Godot.Collections.Array lock_delay_array = new Godot.Collections.Array() { 1 };

    public float tower_meter = 0.0f;
    public float tower_speed_meter = 0.0f;
    public float tower_lowest_speed = 0.1f;
    public float tower_dropped_speed = 0.01f;
    public Godot.Collections.Array tower_dropped_mult = new Godot.Collections.Array() { 0.8, 0.9, 1, 1, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.7, 1.9, 2 };
    public float tower_current_dropped_mult = 1.0f;
    public float attack_to_meter_mult = 0.2f;
    public float attack_to_speed_mult = 0.1f;

    public int warning_count = 4;
    public int segment_line = 4;
    public Godot.Collections.Array big_attack_enter_array = new Godot.Collections.Array();
    public float big_attack_delay = 4.0f;

    public int kill_count = 0;
    public int killer_spike = 10;
    public float kill_possible_percent = 0.15f;
    public Godot.Collections.Array kill_reward = new Godot.Collections.Array() { 10, 4 };

    [Signal]
    public delegate void BigAttackWarningStartedEventHandler();
    [Signal]
    public delegate void BigAttackWarningEndedEventHandler();
    [Signal]
    public delegate void StageChangedEventHandler(int previous_stage, int new_stage);

    public int _previous_stage = 0;  // 用于检测阶段变化

    public Godot.Collections.Dictionary extra_data_dict = new Godot.Collections.Dictionary();

    public Timer garbage_sent_timer;
    public Timer big_attack_delay_timer;

    public float self_game_time;

    public override void _Ready()
    {
        _auto_finding();
        _set_game_var();
        _extra_data_deal();
        _set_timer();
        tower_rng = RandomManager.get_random("TOWER_CLIMB");
        _previous_stage = current_stage;
    }

    public void _auto_finding()
    {
        if (tetris_controller == null)
        {
            tetris_controller = GetNodeOrNull<TetrisController>("../TetrisBoardDrawer");
            if (tetris_controller == null)
            {
                GD.PushError("TetrisController: 未找到TetrisBoardDrawer节点！");
                return;
            }
        }

        if (garbage_line_controller == null)
        {
            garbage_line_controller = GetNodeOrNull<TetrisGarbageLineController>("../TetrisBoardDrawer");
            if (garbage_line_controller == null)
            {
                GD.PushError("TetrisController: 未找到TetrisBoardDrawer节点！");
                return;
            }
        }

        if (board_drawer == null)
        {
            board_drawer = GetNodeOrNull<TetrisBoardDrawer>("../TetrisBoardDrawer");
            if (board_drawer == null)
                board_drawer = GetNodeOrNull<TetrisBoardDrawer>("../../MainBoard/TetrisBoardDrawer");
        }
    }

    public void _set_game_var()
    {
        // 从 GlobalData 读取 buff_chose_area 配置的初始数据，覆盖本地默认值
        var init_data = GlobalData.tower_init_data;
        if (init_data.Count > 0)
        {
            foreach (var keyObj in init_data.Keys)
            {
                string key = keyObj.AsString();
                if (_field_exists(key))
                    _set_field_from_variant(key, init_data[keyObj]);
                else
                    GD.PushWarning("TowerController 未知变量: ", key);
            }
        }

        current_stage = 0;
    }

    /// <summary>判断是否存在与 key 同名的 C# 字段（含从 Resource/Object 继承的属性不处理，仅本类字段）</summary>
    private bool _field_exists(string key)
    {
        var f = GetType().GetField(key, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (f != null)
            return true;
        var p = GetType().GetProperty(key, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        return p != null;
    }

    /// <summary>按字段目标类型把 Variant 值写入（等价于 GDScript self[key] = value 的隐式类型转换）</summary>
    private void _set_field_from_variant(string key, Variant value)
    {
        var f = GetType().GetField(key, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (f != null)
        {
            object converted = _convert_variant_for_type(value, f.FieldType);
            f.SetValue(this, converted);
            return;
        }
        var p = GetType().GetProperty(key, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (p != null && p.SetMethod != null)
        {
            object converted = _convert_variant_for_type(value, p.PropertyType);
            p.SetValue(this, converted);
        }
    }

    private static object _convert_variant_for_type(Variant value, System.Type targetType)
    {
        if (targetType == typeof(float))
            return value.AsSingle();
        if (targetType == typeof(double))
            return value.AsDouble();
        if (targetType == typeof(long))
            return value.AsInt64();
        if (targetType == typeof(int))
            return value.AsInt32();
        if (targetType == typeof(bool))
            return value.AsBool();
        if (targetType == typeof(string))
            return value.AsString();
        if (typeof(Godot.Collections.Array).IsAssignableFrom(targetType))
            return value.AsGodotArray();
        if (typeof(Godot.Collections.Dictionary).IsAssignableFrom(targetType))
            return value.AsGodotDictionary();
        if (targetType == typeof(Color))
            return value.AsColor();
        return value.Obj;
    }

    /// <summary>按字段名反射设置 GodotObject 派生对象上的 C# 公共字段（模拟 GDScript self[key]= / obj.set()）</summary>
    private static void _set_field_by_name(GodotObject target, string name, Variant value)
    {
        var f = target.GetType().GetField(name, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);
        if (f == null)
        {
            GD.PushError(string.Format("TowerController: 无法按名称设置字段 {0}（{1} 上不存在）", name, target.GetType().Name));
            return;
        }
        f.SetValue(target, _convert_variant_for_type(value, f.FieldType));
    }

    public void _extra_data_deal()
    {
        if (extra_data_dict.ContainsKey("send_mult_attack"))
            send_mult_attack = extra_data_dict["send_mult_attack"].AsSingle();

        if (extra_data_dict.ContainsKey("mult_defend"))
        {
            if (garbage_line_controller != null)
                garbage_line_controller.mult_defend = extra_data_dict["mult_defend"].AsSingle();
        }
        if (extra_data_dict.ContainsKey("garbage_rise_time_delay"))
            garbage_line_controller.garbage_rise_time_delay = extra_data_dict["garbage_rise_time_delay"].AsSingle();
        if (extra_data_dict.ContainsKey("garbage_cap"))
        {
            garbage_line_controller.garbage_cap = extra_data_dict["garbage_cap"].AsInt32();
            // 同步版面绘制的 garbage_cap 横线：board_drawer 在 _init_board_data 启动时已读取旧值，
            // 若不在此覆盖，垃圾槽横线会停留在默认 garbage_cap 位置
            if (board_drawer != null)
            {
                board_drawer.garbage_cap = garbage_line_controller.garbage_cap;
                board_drawer.QueueRedraw();
            }
        }
        if (extra_data_dict.ContainsKey("buffer_duration"))
            garbage_line_controller.buffer_duration = extra_data_dict["buffer_duration"].AsSingle();
        if (extra_data_dict.ContainsKey("suddenly_death_mode"))
            garbage_line_controller.suddenly_death_mode = extra_data_dict["suddenly_death_mode"].AsBool();
        if (extra_data_dict.ContainsKey("drop_limit_cancel"))
            garbage_line_controller.drop_limit_cancel = extra_data_dict["drop_limit_cancel"].AsBool();

        if (extra_data_dict.ContainsKey("tetris_invisible"))
        {
            if (board_drawer != null)
            {
                board_drawer.tetris_invisible = extra_data_dict["tetris_invisible"].AsInt32();
                board_drawer.CallDeferred("_init_invisible_mode");
            }
        }
        if (extra_data_dict.ContainsKey("visible_time_between"))
        {
            if (board_drawer != null)
                board_drawer.visible_time_between = extra_data_dict["visible_time_between"].AsSingle();
        }
        if (extra_data_dict.ContainsKey("visible_show_time"))
        {
            if (board_drawer != null)
                board_drawer.visible_show_time = extra_data_dict["visible_show_time"].AsSingle();
        }
        if (extra_data_dict.ContainsKey("drop_visible_time"))
        {
            if (board_drawer != null)
                board_drawer.drop_visible_time = extra_data_dict["drop_visible_time"].AsSingle();
        }

        // ShortNext（短见）：限制 Next 显示数量/是否显示，并同步限制 bot 的 Next 预览深度：
        //   next_display_enabled=false（短见V）→ 不显示 next；bot 预览 0（无 next，只给当前块）
        //   next_count=N（短见I-IV）→ 显示 N 个 next，bot 预览 N
        // bot 预览的最终值由 coldclear_bridge 再按 hold 状态抬升安全下限：
        //   hold 可用 → 预览 ≥2；hold 禁用 → 预览 ≥0（避免「hold 空 + 队列过短」卡死）
        // 未勾选 ShortNext 时不覆盖，bot 预览保持默认 14。
        if (extra_data_dict.ContainsKey("next_display_enabled"))
        {
            bool show_next = extra_data_dict["next_display_enabled"].AsBool();
            if (board_drawer != null)
                board_drawer.next_display_enabled = show_next;
            if (clear_line_controller != null && !show_next)
                clear_line_controller.bot_next_preview = 0;
        }
        if (extra_data_dict.ContainsKey("next_count"))
        {
            int next_n = extra_data_dict["next_count"].AsInt32();
            if (board_drawer != null)
                board_drawer.next_count = next_n;
            if (clear_line_controller != null)
                clear_line_controller.bot_next_preview = Mathf.Max(1, next_n);
        }

        if (extra_data_dict.ContainsKey("spin0_btb_enabled"))
            clear_line_controller.spin0_btb_enabled = extra_data_dict["spin0_btb_enabled"].AsBool();

        if (extra_data_dict.ContainsKey("tetris_allspin"))
            clear_line_controller.tetris_allspin = extra_data_dict["tetris_allspin"].AsInt32();

        // bot 评估权重（可由 buff 界面调整，经 bridge 的 S 命令下发到 ColdClear）。
        // 原则：bridge 导出权重为主，仅当 buff 显式传参对应键时才覆盖 bridge。
        // 这里把显式传参的键记入 clear_line_controller.bot_weight_override_keys，
        // get_damage_tables 只返回这些键，bridge 才会覆盖默认权重。
        clear_line_controller.bot_weight_override_keys = new Godot.Collections.Dictionary();
        var bot_key_to_var = new System.Collections.Generic.Dictionary<string, string>()
        {
            { "bot_eval_mult", "eval_mult" },
            { "bot_attack_efficiency_weight", "attack_efficiency_weight" },
            { "bot_b2b_clear", "b2b_clear" },
            { "bot_height", "height" },
            { "bot_clear4", "clear4" },
            { "bot_clear1", "clear1" },
            { "bot_clear2", "clear2" },
            { "bot_clear3", "clear3" },
            { "bot_tspin1", "tspin1" },
            { "bot_tspin2", "tspin2" },
            { "bot_tspin3", "tspin3" },
            { "bot_mini_tspin1", "mini_tspin1" },
            { "bot_mini_tspin2", "mini_tspin2" },
            { "bot_allspin1", "allspin1" },
            { "bot_allspin2", "allspin2" },
            { "bot_allspin3", "allspin3" },
            { "bot_allspin3plus", "allspin3plus" },
            { "bot_perfect_clear", "perfect_clear" },
            { "bot_combo_garbage", "combo_garbage" },
            { "bot_wasted_t", "wasted_t" },
            { "bot_move_time", "move_time" },
            { "bot_allspin_repeat_penalty", "allspin_repeat_penalty" },
        };
        foreach (var pair in bot_key_to_var)
        {
            string extra_key = pair.Key;
            if (extra_data_dict.ContainsKey(extra_key))
            {
                string weight_key = pair.Value;
                // 命名：clear_line_controller.bot_<weight_key>
                _set_field_by_name(clear_line_controller, "bot_" + weight_key, extra_data_dict[extra_key]);
                clear_line_controller.bot_weight_override_keys[weight_key] = true;
            }
        }

        // bot 并行搜索线程数（buff 可调，0 = 由 bridge 自动决定）
        if (extra_data_dict.ContainsKey("bot_threads"))
            clear_line_controller.bot_threads = extra_data_dict["bot_threads"].AsInt32();

        // Talentless（无才能）：NoSpin 为 int（0=默认/1=全MiniSpin/2=NoSpin不判定Spin）
        if (extra_data_dict.ContainsKey("NoSpin"))
        {
            if (clear_line_controller != null)
                clear_line_controller.no_spin = extra_data_dict["NoSpin"].AsInt32();
        }

        // NoHold模式：关闭Hold显示并禁用Hold输入（JSON中键名为"NoHold"）
        if (extra_data_dict.ContainsKey("NoHold") || extra_data_dict.ContainsKey("no_hold"))
        {
            bool no_hold_value = false;
            if (extra_data_dict.ContainsKey("NoHold"))
                no_hold_value = extra_data_dict["NoHold"].AsBool();
            else if (extra_data_dict.ContainsKey("no_hold"))
                no_hold_value = extra_data_dict["no_hold"].AsBool();
            if (tetris_controller != null)
                tetris_controller.no_hold = no_hold_value;
            if (board_drawer != null)
                board_drawer.no_hold = no_hold_value;
        }

        // ShortNext（短见）：调整 Next 预览显示数量 / 是否显示 Next
        // next_count：int（1-7），显示多少个 next；next_display_enabled：bool，是否显示 Next 区
        bool next_changed = false;
        if (extra_data_dict.ContainsKey("next_count"))
        {
            if (board_drawer != null)
            {
                board_drawer.next_count = Mathf.Clamp(extra_data_dict["next_count"].AsInt32(), 1, 7);
                next_changed = true;
            }
        }
        if (extra_data_dict.ContainsKey("next_display_enabled"))
        {
            if (board_drawer != null)
            {
                board_drawer.next_display_enabled = extra_data_dict["next_display_enabled"].AsBool();
                next_changed = true;
            }
        }
        // 首块可能在 TowerController._ready 之前已由子节点生成（此时用的是默认 next_count），
        // 强制立即刷新一次 Next 显示，使 buff 立刻生效、next_pieces_data 与 next_count 一致。
        if (next_changed && tetris_controller != null && tetris_controller.HasMethod("_update_next_display"))
            tetris_controller._update_next_display();

        // DoubleHole：垃圾行洞口形态
        // garbage_hole_wide_count = X宽（每行一组紧邻连续洞口）；garbage_hole_count = 每行洞口数量。
        // 两者互斥且默认 1（一个洞且 1 宽）；若同时被覆盖（均 > 1）则 push_error 并不应用。
        if (extra_data_dict.ContainsKey("garbage_hole_wide_count") || extra_data_dict.ContainsKey("garbage_hole_count"))
        {
            int dh_wide = extra_data_dict.ContainsKey("garbage_hole_wide_count") ? extra_data_dict["garbage_hole_wide_count"].AsInt32() : 1;
            int dh_holes = extra_data_dict.ContainsKey("garbage_hole_count") ? extra_data_dict["garbage_hole_count"].AsInt32() : 1;
            if (dh_wide > 1 && dh_holes > 1)
                GD.PushError("DoubleHole参数冲突：garbage_hole_wide_count 与 garbage_hole_count 互斥，不能同时大于1");
            else if (garbage_line_controller != null)
            {
                garbage_line_controller.garbage_hole_wide_count = dh_wide;
                garbage_line_controller.garbage_hole_count = dh_holes;
            }
        }

        if (extra_data_dict.ContainsKey("BotMode"))
            tetris_controller.bot_mode = true;

        // StartBoard：按参数直接印刷自定义初始版面（从下往上）。
        // 版面由 BuffChoseData 的 StartBoard 参数（二维数组）指定，第 0 行为最底层（最大 y）。
        // 宽度与版面不一致或行数超出可玩高度时 push_error。
        // 印刷通过 set_cell_color 直接写入 board_data；bot 在请求决策时实时读取 board_data
        // （coldclear_bridge._build_board_rows），因此无需额外同步，bot 会自动看到该改写的初始版面。
        if (extra_data_dict.ContainsKey("StartBoard"))
            _print_start_board(extra_data_dict["StartBoard"]);

        // ExtraBotChange：把 BuffChoseData 中针对已勾选 buff 的 bot 参数直接传给 bot。
        // 覆盖对应的 bot 参数；若参数名无对应（非法名）→ push_error（不覆盖）。
        if (extra_data_dict.ContainsKey("ExtraBotChange"))
            _apply_extra_bot_change(extra_data_dict["ExtraBotChange"]);
    }

    /// <summary>
    /// 按 StartBoard 参数印刷初始版面（从下往上印刷）。
    /// 第 0 行为最底层（最大 y），后续行依次向上。
    /// 宽度与版面不一致（行宽 != grid_width）或行数超出可玩高度 → push_error。
    /// 通过 set_cell_color 写入 board_data，bot 实时读取 board_data，因此自动同步给 bot。
    /// </summary>
    public void _print_start_board(Variant start_board)
    {
        if (board_drawer == null)
        {
            GD.PushError("StartBoard: 未找到 board_drawer，无法印刷初始版面");
            return;
        }
        // board_data 需已初始化（grid_width × grid_max_height）；若尚未初始化则延迟到所有节点 _ready 完成后印刷
        if (board_drawer.board_data.Count == 0)
        {
            CallDeferred("_print_start_board", start_board);
            return;
        }
        if (start_board.VariantType != Variant.Type.Array || start_board.AsGodotArray().Count == 0)
        {
            GD.PushError("StartBoard: 参数必须是非空二维数组（从下往上）");
            return;
        }
        int grid_w = board_drawer.grid_width;
        int playable_h = board_drawer.get_playable_height();
        var rows = start_board.AsGodotArray();
        int rowCount = rows.Count;
        if (rowCount > playable_h)
        {
            GD.PushError(string.Format("StartBoard: 高度超出，行数 {0} > 可玩高度 {1}", rowCount, playable_h));
            return;
        }
        for (int i = 0; i < rowCount; i++)
        {
            Variant row = rows[i];
            if (row.VariantType != Variant.Type.Array)
            {
                GD.PushError(string.Format("StartBoard: 第 {0} 行不是数组，格式错误", i));
                return;
            }
            var rowArr = row.AsGodotArray();
            if (rowArr.Count != grid_w)
            {
                GD.PushError(string.Format("StartBoard: 宽度不匹配，第 {0} 行宽度 {1} != 版面宽度 {2}", i, rowArr.Count, grid_w));
                return;
            }
            int y = playable_h - 1 - i;  // 从下往上：第 0 行印在最底层（最大 y）
            for (int x = 0; x < grid_w; x++)
            {
                Variant color = _start_board_cell_to_color(rowArr[x], i, x);
                board_drawer.set_cell_color(x, y, color);
            }
        }
        board_drawer.QueueRedraw();
    }

    /// <summary>
    /// 将 StartBoard 单元格值转换为颜色。
    /// null / 空字符串 / 0 → 空；字符串支持颜色名与十六进制（如 "#RRGGBB"）；
    /// 特殊标记 "solid"/"实心" → 实心垃圾深灰，"garbage"/"垃圾" → 普通垃圾灰。
    /// </summary>
    public Variant _start_board_cell_to_color(Variant cell, int row_i, int col_i)
    {
        if (cell.VariantType == Variant.Type.Nil)
            return new Variant();
        if (cell.VariantType == Variant.Type.String)
        {
            string s = cell.AsString().StripEdges().ToLower();
            if (s.Length == 0 || s == "0" || s == "null" || s == "empty" || s == "空")
                return new Variant();
            if (s == "solid" || s == "实心")
                return garbage_line_controller != null ? garbage_line_controller.solid_garbage_color : new Color(0.3f, 0.3f, 0.3f);
            if (s == "garbage" || s == "垃圾")
                return garbage_line_controller != null ? garbage_line_controller.garbage_color : new Color(0.5f, 0.5f, 0.5f);
            Color c = Color.FromString(s, new Color(-999, -999, -999));
            if (c.R < -100 || c.G < -100 || c.B < -100)
            {
                GD.PushError(string.Format("StartBoard: 无法解析颜色 '{0}'（第 {1} 行第 {2} 列）", cell.AsString(), row_i, col_i));
                return new Variant();
            }
            return c;
        }
        if (cell.VariantType == Variant.Type.Float || cell.VariantType == Variant.Type.Int)
        {
            double v = cell.VariantType == Variant.Type.Int ? cell.AsInt64() : cell.AsDouble();
            if (Mathf.IsZeroApprox((float)v))
                return new Variant();
            GD.PushError(string.Format("StartBoard: 不支持的数值单元格 {0}（第 {1} 行第 {2} 列）", cell, row_i, col_i));
            return new Variant();
        }
        GD.PushError(string.Format("StartBoard: 未知单元格类型 {0}（第 {1} 行第 {2} 列）", cell, row_i, col_i));
        return new Variant();
    }

    /// <summary>供 bot 读取当前关卡 buff 调整后的攻击倍率（send_mult_attack）。</summary>
    public float get_send_mult_attack()
    {
        return send_mult_attack;
    }

    /// <summary>
    /// 应用 ExtraBotChange：把 BuffChoseData 中针对已勾选 buff 的 bot 参数直接写到 bot 参数位置。
    /// 每个 {bot参数名: 值}：若为合法 bot 参数名则覆盖 clear_line_controller.bot_<名> 并标记覆盖；
    /// 若参数名无对应（非法名）→ push_error，不覆盖。
    /// </summary>
    public void _apply_extra_bot_change(Variant extra_bot)
    {
        if (extra_bot.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError("ExtraBotChange: 参数必须为字典（{bot参数名: 值}）");
            return;
        }
        if (clear_line_controller == null)
        {
            GD.PushError("ExtraBotChange: clear_line_controller 未找到");
            return;
        }
        // 合法的 bot 参数名（对应 clear_line_controller.bot_<名>）
        var valid_names = new System.Collections.Generic.List<string>()
        {
            "eval_mult", "attack_efficiency_weight", "b2b_clear", "height",
            "clear4", "clear1", "clear2", "clear3",
            "tspin1", "tspin2", "tspin3", "mini_tspin1", "mini_tspin2",
            "allspin1", "allspin2", "allspin3", "allspin3plus",
            "perfect_clear", "combo_garbage", "wasted_t", "move_time",
            "allspin_repeat_penalty",
        };
        var dict = extra_bot.AsGodotDictionary();
        foreach (var kv in dict)
        {
            string pn = kv.Key.AsString();
            if (!valid_names.Contains(pn))
            {
                GD.PushError(string.Format("ExtraBotChange: 未知的 bot 参数名 '{0}'（无对应，不覆盖）", pn));
                continue;
            }
            _set_field_by_name(clear_line_controller, "bot_" + pn, kv.Value);
            clear_line_controller.bot_weight_override_keys[pn] = true;
        }
    }

    public void _set_timer()
    {
        garbage_sent_timer = new Timer();
        garbage_sent_timer.OneShot = true;
        garbage_sent_timer.Timeout += _try_sent_garbage;
        AddChild(garbage_sent_timer);

        big_attack_delay_timer = new Timer();
        big_attack_delay_timer.WaitTime = big_attack_delay;
        big_attack_delay_timer.OneShot = true;
        big_attack_delay_timer.Timeout += _warning_big_collected_enter;
        AddChild(big_attack_delay_timer);
    }

    public override void _Process(double delta)
    {
        for (int i = 0; i < FLOOR_HIGHER.Count; i++)
        {
            if (tower_meter > (float)(long)FLOOR_HIGHER[i])
                current_stage = i;
        }

        // 阶段变化检测
        if (current_stage != _previous_stage)
        {
            EmitSignal(nameof(StageChanged), _previous_stage, current_stage);
            _previous_stage = current_stage;
        }

        total_get_data();

        publish_make();

        if (garbage_sent_time != 0 && garbage_sent_timer.IsStopped())
        {
            garbage_sent_timer.WaitTime = garbage_sent_time + tower_rng.RandfRange(-garbage_sent_time / 2.0f, garbage_sent_time / 2.0f);
            garbage_sent_timer.Start();
        }

        _tower_climb(delta);
    }

    public void total_get_data()
    {
        self_game_time = tetris_controller.game_time;

        garbage_sent_time = default_get_oneD_array_things(current_stage, stage_garbage_time).AsSingle();
        tower_current_dropped_mult = default_get_oneD_array_things(current_stage, tower_dropped_mult).AsSingle();
        pressure_mult = default_get_oneD_array_things(current_stage, pressure_mult_array).AsSingle();
        float max_percent = default_get_oneD_array_things(current_stage, stage_percent_apm).AsSingle() + extra_percent_apm;
        if (max_percent > 1)
            max_percent = 1;
        current_apm = total_apm * pressure_mult * max_percent;
        garbage_collect_percent = default_get_oneD_array_things(current_stage, garbage_collect_percent_array).AsSingle();
        garbage_divide_percent = default_get_oneD_array_things(current_stage, garbage_divide_percent_array).AsSingle();
        garbage_line_controller.garbage_messy = default_get_oneD_array_things(current_stage, garbage_hole_change_percent_array).AsSingle();
        tetris_controller.gravity_drop_time = default_get_oneD_array_things(current_stage, gravity_drop_time_array).AsSingle();
        tetris_controller.lock_delay = default_get_oneD_array_things(current_stage, lock_delay_array).AsSingle();
    }

    public void publish_make()
    {
        for (int i = 0; i < publish_time_array.Count; i++)
        {
            if (self_game_time > (long)publish_time_array[i])
                publish_stage = i;
        }

        if (publish_make_finish != publish_stage)
        {
            if (publish_stage == 1)
                garbage_line_controller.add_solid_garbage(2);
            if (publish_stage == 2)
                publish_mult_attack = 1.2f;
            if (publish_stage == 3)
                garbage_line_controller.add_solid_garbage(3);
            if (publish_stage == 4)
                publish_mult_attack = 1.5f;
            if (publish_stage == 5)
                garbage_line_controller.add_solid_garbage(5);

            publish_make_finish = publish_stage;
        }
    }

    public void _tower_climb(double delta)
    {
        if (tower_speed_meter < tower_lowest_speed)
        {
            tower_speed_meter = tower_lowest_speed;
        }
        else if (tower_speed_meter > tower_lowest_speed)
        {
            float x = tower_speed_meter;
            tower_speed_meter -= ((x * Mathf.Log(x) + x) / 110.0f) * (float)delta * tower_current_dropped_mult;
        }
        else
        {
            // pass
        }

        tower_meter += tower_speed_meter * (float)delta;
    }

    /// <summary>塔的模拟伤害攻击</summary>
    public void _try_sent_garbage()
    {
        int decided_attack = (int)Mathf.Ceil(current_apm / 60.0f * garbage_sent_time);
        int i = 0;
        while (decided_attack > 0)
        {
            float j = tower_rng.Randf();
            decided_attack -= 1;
            i += 1;
            if (j < garbage_divide_percent)
            {
                collected_garbage.Add(i);
                i = 0;
            }
            if (decided_attack == 0)
            {
                if (i != 0)
                {
                    collected_garbage.Add(i);
                }
                break;
            }
        }
        if (tower_rng.Randf() > garbage_collect_percent)
        {
            if (collected_count >= warning_count && big_attack_enter_array.Count == 0)
            {
                big_attack_enter_array = (Godot.Collections.Array)collected_garbage.Duplicate();
                collected_garbage.Clear();
                _quick_big_attack_clear(4);
                big_attack_delay_timer.Start();
                EmitSignal(nameof(BigAttackWarningStarted));
            }
            else
            {
                _tower_garbage_sent(collected_garbage);
                collected_garbage.Clear();
            }
            collected_count = 0;
        }
        else
        {
            i = (int)Mathf.Floor(collected_garbage.Count / 2.0f);
            var temp_sent_garbage = new Godot.Collections.Array();
            while (i > 0)
            {
                i -= 1;
                temp_sent_garbage.Add(collected_garbage[0]);
                collected_garbage.RemoveAt(0);
            }
            _tower_garbage_sent(temp_sent_garbage);
            collected_count += 1;
        }
    }

    public void _tower_garbage_sent(Godot.Collections.Array attack)
    {
        foreach (var a in attack)
        {
            int lineCount = a.AsInt32();
            garbage_line_controller.add_attack((int)Mathf.Ceil(lineCount * send_mult_attack * publish_mult_attack));
        }
    }

    /// <summary>快速重新分割攻击储存列表并形成!!!!攻击</summary>
    public void _quick_big_attack_clear(int segment)
    {
        int total_attack = 0;
        foreach (var entry in big_attack_enter_array)
            total_attack += entry.AsInt32();
        big_attack_enter_array.Clear();
        for (int i = 0; i < segment; i++)
        {
            if (total_attack <= segment_line)
            {
                big_attack_enter_array.Add(total_attack);
                total_attack = 0;
                break;
            }
            big_attack_enter_array.Add(segment_line);
            total_attack -= segment_line;
        }
        if (total_attack != 0)
            big_attack_enter_array.Add(total_attack);
    }

    /// <summary>!!!!攻击警示器</summary>
    public void _warning_big_collected_enter()
    {
        EmitSignal(nameof(BigAttackWarningEnded));
        garbage_line_controller.add_attack(big_attack_enter_array[0].AsInt32());
        if (big_attack_enter_array.Count > 1)
        {
            big_attack_delay_timer.WaitTime = 0.5f;
            big_attack_enter_array.RemoveAt(0);
            big_attack_delay_timer.Start();
        }
        else
        {
            big_attack_delay_timer.WaitTime = big_attack_delay;
            big_attack_enter_array.Clear();
        }
    }

    /// <summary>内置的检索，默认超出列表范围时返回列表最后一项，仅能用于一维列表</summary>
    public Variant default_get_oneD_array_things(int id, Godot.Collections.Array array)
    {
        if (id >= array.Count)
            return array[array.Count - 1];
        else
            return array[id];
    }

    public void attack_increase_tower(float attack, bool is_defence = false)
    {
        if (is_defence)
        {
            // pass
        }
        tower_meter += attack * attack_to_meter_mult;
        tower_speed_meter += attack * attack_to_speed_mult;
    }

    /// <summary>尝试给予击杀奖励，通过输入攻击后进行随机击杀计算</summary>
    public void try_give_kill_reward(int attack)
    {
        int try_times = (int)Mathf.Floor(1.0f * attack / killer_spike);
        int last_attack = attack - try_times * killer_spike;
        if (try_times > 0)
        {
            for (int i = 0; i < try_times; i++)
            {
                extra_percent_apm += 0.03f;
                if (tower_rng.Randf() <= kill_possible_percent)
                {
                    tower_meter += (float)(long)kill_reward[0];
                    tower_speed_meter += (float)(long)kill_reward[1];
                    kill_count += 1;
                    extra_percent_apm += 0.1f;
                }
            }
        }
        if (tower_rng.Randf() <= kill_possible_percent * last_attack / killer_spike / 5)
        {
            tower_meter += (float)(long)kill_reward[0];
            tower_speed_meter += (float)(long)kill_reward[1];
            kill_count += 1;
        }
    }
}
