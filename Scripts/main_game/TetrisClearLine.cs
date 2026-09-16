using Godot;

/// <summary>
/// 俄罗斯方块消行控制器
/// 负责检测和消除完整行，并显示消行动画/文本
/// </summary>
public partial class TetrisClearLine : Node
{
    // 节点引用
    [Export]
    public TetrisBoardDrawer board_drawer;  // 版面绘制器节点
    [Export]
    public TetrisController tetris_controller;  // 方块控制器引用
    [Export]
    public TetrisGarbageLineController garbage_line_controller;
    [Export]
    public TowerController tower_controller;
    [Export]
    public TextPrinter text_printer;  // 文本打印器节点（用于显示消行/Spin/连击/BTB文本）

    // 消行配置
    [Export]
    public float clear_animation_duration = 0.3f;  // 消行动画持续时间（秒）
    [Export]
    public float clear_text_display_duration = 2.0f;  // 消行文本显示持续时间（秒）

    // 消行延迟时间（秒）：>0 时先播放消行动画（持续 clear_line_delay_time），动画结束后才生成新方块；0 表示无延迟
    [Export]
    public float clear_line_delay_time = 0.0f;

    // 消行延迟状态
    public Timer clear_line_delay_timer;  // 消行延迟计时器
    public Godot.Collections.Array _pending_clear_lines = new Godot.Collections.Array();  // 待清除的行（延迟期间仍物理存在，延迟结束后才位移清除）
    public bool _is_clear_animating = false;  // 是否正在播放消行动画（延迟中）

    // 文本打印器配置（非BTB文本：半透明、向左漂移、自然淡出消失）
    [Export]
    public float text_base_opacity = 0.8f;          // 文本显示时的透明度（半透明，0-1）
    [Export]
    public float text_fade_duration = 1.0f;         // 文本淡出时长（秒）
    [Export]
    public float text_drift_cells_per_sec = 1.5f;   // 文本向左漂移速度（格子/秒）
    [Export]
    public float text_gap_cells = 1.8f;             // 文本与版面左边框的间距（格子数）

    // 消行/Spin 文本的漂移与淡出倍率（相对默认值的修正：移动略快、淡出更快）
    [Export]
    public float clear_spin_drift_scale = 3.0f;     // 消行/Spin 漂移速度倍率（>1 为更快）
    [Export]
    public float clear_spin_fade_scale = 0.2f;      // 消行/Spin 淡出时长倍率（<1 为淡出更快/更短）
    [Export]
    public float clear_spin_hold_scale = 0.15f;     // 消行/Spin 淡出触发前的保持时间倍率（越小淡出越早、与移动并行）

    // 消行文本配置
    [Export]
    public Color clear_text_color = Colors.White;  // 消行文本颜色
    [Export]
    public Color clear_text_outline_color = Colors.Black;  // 消行文本描边颜色
    [Export]
    public float clear_text_offset_y_cells = 2f;  // 消行文本相对于Hold框底部的偏移（格子数）

    // Spin类型判定配置
    [Export]
    public bool spin_detection_enabled = true;  // 是否启用Spin检测
    [Export]
    public Color spin_text_color = Colors.Yellow;  // Spin文本颜色
    [Export]
    public Color spin_text_outline_color = Colors.Black;  // Spin文本描边颜色
    [Export]
    public float spin_text_offset_y_cells = 1f;  // Spin文本相对于消行文本的偏移（格子数，负值向上）

    // 连击配置
    [Export]
    public Color combo_text_color = Colors.Cyan;  // 连击文本颜色
    [Export]
    public Color combo_text_outline_color = Colors.Black;  // 连击文本描边颜色
    [Export]
    public float combo_text_offset_y_cells = 1f;  // 连击文本相对于消行文本的偏移（格子数，正值向下）

    // BTB配置
    [Export]
    public Color btb_text_color = Colors.Magenta;  // BTB文本颜色
    [Export]
    public Color btb_text_outline_color = Colors.Black;  // BTB文本描边颜色
    [Export]
    public float btb_text_offset_y_cells = 4.5f;  // BTB文本相对于Hold框底部的偏移（格子数，正值向下）

    // PC（Perfect Clear）配置
    [Export]
    public Color pc_text_color = Colors.Gold;  // PC文本颜色
    [Export]
    public Color pc_text_outline_color = Colors.Black;  // PC文本描边颜色
    [Export]
    public float pc_text_offset_y_cells = 3.5f;  // PC文本相对于Hold框底部的偏移（格子数，正值向下）
    [Export]
    public int pc_damage = 10;  // PC附加伤害值

    // 伤害显示配置
    [Export]
    public Color damage_text_color = Colors.Orange;  // 伤害文本颜色
    [Export]
    public Color damage_text_outline_color = Colors.Black;  // 伤害文本描边颜色
    [Export]
    public float damage_text_offset_y_cells = 5.5f;  // 伤害文本相对于Hold框底部的偏移（格子数，正值向下）
    [Export]
    public float damage_display_duration = 1.5f;  // 伤害显示持续时间（秒）

    // 消行文本映射
    public Godot.Collections.Dictionary clear_texts = new Godot.Collections.Dictionary()
    {
        { (long)1, "SINGLE" },
        { (long)2, "DOUBLE" },
        { (long)3, "TRIPLE" },
        { (long)4, "QUAD" }
    };

    // 基础伤害表（按消行数）
    public Godot.Collections.Dictionary base_damage_table = new Godot.Collections.Dictionary()
    {
        { (long)0, (long)0 },
        { (long)1, (long)0 },
        { (long)2, (long)1 },
        { (long)3, (long)2 },
        { (long)4, (long)4 }
    };

    // Spin伤害表（优先于基础伤害表）
    public Godot.Collections.Dictionary spin_damage_table = new Godot.Collections.Dictionary()
    {
        { "T-Spin", new Godot.Collections.Dictionary()
            {
                { (long)1, (long)2 },
                { (long)2, (long)4 },
                { (long)3, (long)6 }
            }
        },
        { "Mini T-Spin", new Godot.Collections.Dictionary()
            {
                { (long)1, (long)1 }
            }
        }
    };

    // All-Spin 伤害表
    // 默认规则不使用该表
    public Godot.Collections.Dictionary allspin_damage_table = new Godot.Collections.Dictionary()
    {
        { (long)1, (long)4 },
        { (long)2, (long)6 },
        { (long)3, (long)8 }
    };

    // 连击表（默认使用公式而不使用该表）
    public Godot.Collections.Array combo_damage_list = new Godot.Collections.Array()
    {
        (long)0,  // 无连击
        (long)0,  // 1连击
        (long)0,  // 2连击
        (long)1,  // 3连击
        (long)1,  // 4连击
        (long)1,  // 5连击
        (long)2,  // 6连击
        (long)2,  // 7连击
        (long)3,  // 8连击
        (long)3,  // 9连击
        (long)4,  // 10连击
        (long)4   // 11连击及以上
    };

    // 连击计算方式：0=旧连击表（combo_damage_list），1=新公式（默认）：
    //   combo_damage = floor(max(ln(1+1.25*combo), ((is_btb_active?1:0)+attack)*(1+0.25*combo)))
    //   其中 attack = 本次消行的 base+spin（不含BTB加成）
    public int combo_formula = 1;

    // Spin伤害加成
    public Godot.Collections.Dictionary spin_damage_multiplier = new Godot.Collections.Dictionary()
    {
        { "t_spin", (long)2 },
        { "mini_t_spin", (long)1 },
        { "other_spin", (long)1 }
    };

    // 状态变量
    public Godot.Collections.Array lines_to_clear = new Godot.Collections.Array();
    public bool is_animating = false;
    public Vector2 clear_text_position = Vector2.Zero;
    public Vector2 spin_text_position = Vector2.Zero;
    public Vector2 combo_text_position = Vector2.Zero;
    public Vector2 btb_text_position = Vector2.Zero;
    public Vector2 damage_text_position = Vector2.Zero;

    // 连击和BTB状态
    public int combo_count = 0;
    public int btb_count = 0;
    public bool is_btb_active = false;
    public bool spin0_btb_enabled = false;  // Spin0是否触发BTB（由buff控制）
    public int tetris_allspin = 0;          // 0=关闭, 1=启用Allspin

    // ---- bot 评估权重（可由 buff 界面调整，经 bridge 的 S 命令下发到 ColdClear）----
    // 维持 BTB 的评估权重（越大 bot 越倾向于维持 back-to-back）
    public int bot_b2b_clear = 200;
    // 放块后的堆叠最高点权重（bot 评估：height × 最高点，负值=压高）
    public int bot_height = -39;
    // 四消（Tetris）的评估权重（越小 bot 越不倾向做四消）
    public int bot_clear4 = 260;
    // allspin_1 重复惩罚的评估扣分（负值=降低选取值，可 buff 调整）
    public int bot_allspin_repeat_penalty = -120;
    // 各类型消行/旋转的评估权重（默认=bridge 导出值，可由 buff 传参覆盖，经 bridge 下发）
    public int bot_eval_mult = 100;
    public int bot_attack_efficiency_weight = 100;
    public int bot_clear1 = -163;
    public int bot_clear2 = -130;
    public int bot_clear3 = -78;
    public int bot_tspin1 = 221;
    public int bot_tspin2 = 410;
    public int bot_tspin3 = 202;
    public int bot_mini_tspin1 = -158;
    public int bot_mini_tspin2 = -393;
    public int bot_allspin1 = 221;
    public int bot_allspin2 = 410;
    public int bot_allspin3 = 202;
    public int bot_allspin3plus = 202;
    public int bot_perfect_clear = 199;
    public int bot_combo_garbage = 170;
    public int bot_wasted_t = -102;
    public int bot_move_time = -3;
    // bot 并行搜索线程数（buff 可调；0 = 由 bridge 自动决定）
    public int bot_threads = 0;
    // 提供给 bot 的 Next 预览深度（当前块之后跟多少个后续块）。默认 14（原行为）。
    // 勾选 ShortNext（短见）后由 tower_controller 按 next_count / next_display_enabled 覆盖；
    // 最终值由 coldclear_bridge 按 hold 状态抬升安全下限（hold 可用 → ≥2；hold 禁用 → ≥0）。
    public int bot_next_preview = 14;
    public int no_spin = 0;            // Spin规则模式（原bool升级为int）：0=默认（正常Spin判定）；1=所有Spin判定为MiniSpin（采用mini伤害表）；2=NoSpin（不判定Spin）
    // 记录 buff 显式传参的权重键（仅这些键会被 bridge 采用，覆盖 bridge 默认权重）
    // 由 tower_controller._extra_data_deal 填入；get_damage_tables 只返回这些键的权重。
    public Godot.Collections.Dictionary bot_weight_override_keys = new Godot.Collections.Dictionary();

    // Allspin：记录上次消行类型和行数（用于下一次消行时比对）
    public string _last_clear_type = "";    // 上次消行类型（如"T-Spin"、"Mini T-Spin"、"I-Spin"、""等）
    public int _last_clear_count = 0;       // 上次消行行数

    // PC状态
    public Vector2 pc_text_position = Vector2.Zero;

    // 伤害累积系统
    public int accumulated_damage = 0;          // 累积的伤害值
    public Timer damage_timer;                  // 伤害计时器
    public bool damage_pending = false;         // 是否有待显示的伤害

    // 旋转记录
    public bool last_rotation_occurred = false;
    public string last_rotation_piece_type = "";
    public Godot.Collections.Array last_rotation_piece_shape = new Godot.Collections.Array();
    public Vector2I last_rotation_position = Vector2I.Zero;

    // Spin颜色系统
    public Color display_spin_color = Colors.Yellow;
    public Color pending_spin_color = Colors.White;
    public bool spin_color_ready = false;

    // 当前消行的伤害值
    public int current_damage = 0;
    public bool has_cleared_lines = false;

    public override void _Ready()
    {
        if (board_drawer == null)
        {
            board_drawer = GetNodeOrNull<TetrisBoardDrawer>("../TetrisBoardDrawer");
            if (board_drawer == null)
            {
                GD.PushError("TetrisClearLine: 未找到TetrisBoardDrawer节点！");
                return;
            }
        }

        if (tetris_controller == null)
        {
            tetris_controller = GetNodeOrNull<TetrisController>("../TetrisController");
            if (tetris_controller == null)
            {
                GD.PushError("TetrisClearLine: 未找到TetrisController节点！");
            }
        }

        // 自动查找tower_controller（如果未设置）
        if (tower_controller == null)
        {
            tower_controller = GetNodeOrNull<TowerController>("../../TowerController");
            if (tetris_controller == null)
            {
                GD.PushError("TowerController: 未找到TowerController节点！");
            }
        }

        // 自动查找text_printer（如果未设置）
        if (text_printer == null)
        {
            text_printer = GetNodeOrNull<TextPrinter>("../TextPrinter");
        }

        // 创建伤害计时器
        damage_timer = new Timer();
        damage_timer.WaitTime = damage_display_duration;
        damage_timer.OneShot = true;
        damage_timer.Timeout += _on_damage_timer_timeout;
        AddChild(damage_timer);

        // 创建消行延迟计时器（wait_time 在启动时按 clear_line_delay_time 设置）
        clear_line_delay_timer = new Timer();
        clear_line_delay_timer.OneShot = true;
        clear_line_delay_timer.Timeout += _on_clear_line_delay_timeout;
        AddChild(clear_line_delay_timer);
    }

    /// <summary>
    /// 记录旋转事件
    /// </summary>
    public void record_rotation(string piece_type, Godot.Collections.Array shape, Vector2I position)
    {
        record_rotation(piece_type, shape, position, Colors.White);
    }

    /// <summary>
    /// 记录旋转事件
    /// </summary>
    public void record_rotation(string piece_type, Godot.Collections.Array shape, Vector2I position, Color piece_color)
    {
        last_rotation_occurred = true;
        last_rotation_piece_type = piece_type;
        last_rotation_piece_shape = shape;
        last_rotation_position = position;

        if (piece_color != Colors.White)
        {
            pending_spin_color = piece_color;
            spin_color_ready = true;
        }
    }

    /// <summary>
    /// 重置旋转记录
    /// </summary>
    public void reset_rotation_record()
    {
        last_rotation_occurred = false;
        last_rotation_piece_type = "";
        last_rotation_piece_shape = new Godot.Collections.Array();
        last_rotation_position = Vector2I.Zero;
    }

    /// <summary>
    /// 清除Spin颜色
    /// </summary>
    public void clear_spin_color()
    {
        pending_spin_color = Colors.White;
        spin_color_ready = false;
        display_spin_color = Colors.Yellow;
    }

    /// <summary>
    /// 伤害计时器超时
    /// </summary>
    public void _on_damage_timer_timeout()
    {
        // 计时归零，清除伤害显示
        tower_controller.try_give_kill_reward(accumulated_damage);
        accumulated_damage = 0;
        damage_pending = false;
        if (text_printer != null)
        {
            text_printer.remove_text("damage");
        }
    }

    /// <summary>
    /// 添加伤害到累积显示
    /// </summary>
    public void _add_damage_to_display(int damage)
    {
        if (damage <= 0)
        {
            return;
        }

        // 累加伤害
        accumulated_damage += damage;
        damage_pending = true;

        // 计算显示位置（在BTB下方，版面外侧距边框一小段距离）
        var hold_pos = board_drawer._get_hold_position();
        var hold_height = board_drawer.hold_display_height * board_drawer.cell_size;
        var bottom_y = hold_pos.Y + hold_height;
        var offset_y = damage_text_offset_y_cells * board_drawer.cell_size;
        damage_text_position = new Vector2(_get_text_anchor_x(), bottom_y + offset_y);

        if (text_printer != null)
        {
            // damage 文本固定显示：不漂移、不淡出，常驻直到计时器结束再移除
            text_printer.show_text("damage", string.Format("{0} Attack", accumulated_damage), damage_text_position,
                damage_text_color, damage_text_outline_color, board_drawer.cell_size * 0.9f,
                true, 1.0f);
        }

        // 重置计时器（如果正在运行则停止并重新开始）
        if (damage_timer.IsStopped())
        {
            damage_timer.Start();
        }
        else
        {
            damage_timer.Stop();
            damage_timer.Start();
        }

        board_drawer.QueueRedraw();
    }

    /// <summary>
    /// 检查并消除完整的行
    /// </summary>
    public int check_and_clear_lines()
    {
        if (is_animating || _is_clear_animating)
        {
            return 0;
        }

        lines_to_clear = _find_complete_lines();
        // NoSpin模式（int）：0=正常Spin判定；2=跳过整个Spin判定；1=把所有Spin降级为MiniSpin
        string spin_type = no_spin == 2 ? "" : _detect_spin_type();
        if (no_spin == 1 && spin_type.Length > 0)
        {
            spin_type = _force_mini_spin(spin_type);
        }
        int clear_count = lines_to_clear.Count;

        if (clear_count == 0)
        {
            if (spin_type.Length > 0)
            {
                // Spin0：显示spin文本，不显示消行文本
                _show_spin_text_only(spin_type);

                if (spin0_btb_enabled)
                {
                    // 特殊情况：spin0触发BTB
                    _update_btb(true);
                }
                // 正常情况下spin0不触发BTB也不断开BTB

                reset_rotation_record();
                // 记录Spin0消行信息
                _last_clear_type = spin_type;
                _last_clear_count = 0;
            }
            else
            {
                // 不去重置其他消行/Spin/连击文本，让它们自然淡出消失
                combo_count = 0;
                reset_rotation_record();
                current_damage = 0;
                has_cleared_lines = false;
            }
            // 没有可消除的行：消行处理结束，直接生成新方块
            _spawn_next_piece_after_clear();
            return 0;
        }

        // Allspin判定：落块时判定此消行是否与上次完全一致
        bool is_allspin_repeat = (tetris_allspin == 1 && clear_count > 0
            && clear_count == _last_clear_count && spin_type == _last_clear_type);

        has_cleared_lines = true;
        bool is_spin = spin_type.Length > 0;
        // 单独判断is_quad
        bool is_quad = false;
        if (clear_count >= 4)
        {
            is_quad = true;
        }
        // 判断是否触发BTB
        bool is_spin_or_quad = false;
        if (is_quad)
        {
            is_spin_or_quad = true;
        }
        if (is_spin)
        {
            is_spin_or_quad = true;
        }

        // 清除可消除的行（带可选消行动画延迟；动画结束后生成新方块）
        _clear_lines_animated(lines_to_clear);

        int damage = _calculate_damage(clear_count, spin_type);

        // PC判定：消行后场上没有任何方块
        bool is_perfect_clear = _check_perfect_clear();
        if (is_perfect_clear)
        {
            damage += pc_damage;  // PC额外伤害叠加
            _show_pc_text();
        }
        else if (text_printer != null)
        {
            text_printer.remove_text("pc");
        }

        current_damage = damage;
        tower_controller.attack_increase_tower(damage);

        _update_btb(is_spin_or_quad);

        // 添加到伤害累积显示
        _add_damage_to_display(damage);

        if (is_spin && spin_color_ready)
        {
            display_spin_color = pending_spin_color;
        }
        else
        {
            display_spin_color = Colors.Yellow;
        }

        _show_clear_and_spin_text(clear_count, spin_type, damage);

        reset_rotation_record();
        combo_count += 1;

        // Allspin延续：消行计算完成后直接上涨一行垃圾行（不走延迟队列，类似突然死亡VIII）
        if (is_allspin_repeat && garbage_line_controller != null)
        {
            garbage_line_controller.insert_allspin_garbage_directly();
        }

        // 记录本次消行信息（供下次Allspin比对）
        _last_clear_type = spin_type;
        _last_clear_count = clear_count;

        return clear_count;
    }

    /// <summary>
    /// 更新BTB状态
    /// </summary>
    public void _update_btb(bool is_spin_or_quad)
    {
        if (is_spin_or_quad)
        {
            if (is_btb_active)
            {
                // 第二次及之后连续四消/spin → BTB计数递增
                btb_count += 1;
            }
            else
            {
                // 第一次四消/spin → 开始计数（btb_count=1），但不显示BTB文本
                is_btb_active = true;
                btb_count = 1;
            }
            _update_btb_text();
        }
        else
        {
            btb_count = 0;
            is_btb_active = false;
            if (text_printer != null)
            {
                text_printer.remove_text("btb");
            }
            board_drawer.QueueRedraw();
        }
    }

    /// <summary>
    /// 更新BTB文本（常驻显示，不随消行淡出）
    /// </summary>
    public void _update_btb_text()
    {
        string btb_text = _get_btb_text();
        if (text_printer == null)
        {
            return;
        }
        if (btb_text.Length > 0)
        {
            var hold_pos = board_drawer._get_hold_position();
            var hold_height = board_drawer.hold_display_height * board_drawer.cell_size;
            var bottom_y = hold_pos.Y + hold_height;
            var btb_offset_y = btb_text_offset_y_cells * board_drawer.cell_size;
            btb_text_position = new Vector2(_get_text_anchor_x(), bottom_y + btb_offset_y);
            // BTB常驻显示（persistent=true），直到断开BTB时才移除
            text_printer.show_text("btb", btb_text, btb_text_position,
                btb_text_color, btb_text_outline_color, board_drawer.cell_size * 1.0f,
                true, 1.0f);
        }
        else
        {
            text_printer.remove_text("btb");
        }
    }

    /// <summary>
    /// 检查是否 Perfect Clear（场上没有任何方块）
    /// </summary>
    public bool _check_perfect_clear()
    {
        // 忽略当前活动方块（尚未锁定的下落方块不计入 PC 判定）。
        // 无消行延迟（clear_line_delay_time==0，默认）时，新方块在消行后、本判定前
        // 就已生成并绘制进版面（spawn_y 位于 get_playable_height 范围内）；若不忽略，
        // 活动方块会被当成版面非空，导致 PC 永远判定失败。消行延迟路径无活动方块，为无害空操作。
        bool had_piece = false;
        if (tetris_controller != null && tetris_controller.current_piece.Count != 0)
        {
            had_piece = true;
            tetris_controller._clear_current_piece();
        }

        bool result = true;
        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            // 待清除的行（消行延迟期间仍物理存在）视为已清除
            if (_pending_clear_lines.Contains((long)y))
            {
                continue;
            }
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                if (board_drawer.get_cell_color(x, y).VariantType != Variant.Type.Nil)
                {
                    result = false;
                    break;
                }
            }
            if (!result)
            {
                break;
            }
        }

        if (had_piece)
        {
            tetris_controller._draw_current_piece();
        }
        return result;
    }

    /// <summary>
    /// 显示 PC 文本
    /// </summary>
    public void _show_pc_text()
    {
        if (text_printer == null)
        {
            return;
        }
        var hold_pos = board_drawer._get_hold_position();
        var hold_height = board_drawer.hold_display_height * board_drawer.cell_size;
        var bottom_y = hold_pos.Y + hold_height;
        var pc_offset_y = pc_text_offset_y_cells * board_drawer.cell_size;
        pc_text_position = new Vector2(_get_text_anchor_x(), bottom_y + pc_offset_y);
        text_printer.show_text("pc", "PERFECT CLEAR", pc_text_position,
            pc_text_color, pc_text_outline_color, board_drawer.cell_size * 1.2f,
            false, text_base_opacity, clear_text_display_duration, text_fade_duration, _get_text_drift());
    }

    /// <summary>
    /// 计算攻击伤害
    /// </summary>
    public int _calculate_damage(int clear_count, string spin_type)
    {
        int base_damage = 0;
        int spin_damage = 0;
        int surge_break = 0;

        if (spin_type.Length > 0)
        {
            string spin_key = _get_spin_key(spin_type);

            // Mini Spin：使用基础伤害表，无额外 Spin 伤害加成（消行相当于正常消行）
            if (spin_type.IndexOf("Mini") != -1)
            {
                spin_damage = base_damage_table.ContainsKey((long)clear_count) ? base_damage_table[(long)clear_count].AsInt32() : 0;
            }
            else if (spin_damage_table.ContainsKey(spin_key))
            {
                var spin_damage_by_count = spin_damage_table[spin_key].AsGodotDictionary();
                if (spin_damage_by_count.ContainsKey((long)clear_count))
                {
                    spin_damage = spin_damage_by_count[(long)clear_count].AsInt32();
                }
                else
                {
                    spin_damage = base_damage_table.ContainsKey((long)clear_count) ? base_damage_table[(long)clear_count].AsInt32() : 0;
                }
            }
            else
            {
                // 非Mini非T-Spin的全旋（如"I-Spin"、"L-Spin"等）→ 使用T-Spin伤害表作为通用全旋伤害
                Godot.Collections.Dictionary full_spin_data = spin_damage_table.ContainsKey("T-Spin")
                    ? spin_damage_table["T-Spin"].AsGodotDictionary()
                    : new Godot.Collections.Dictionary();
                spin_damage = full_spin_data.ContainsKey((long)clear_count)
                    ? full_spin_data[(long)clear_count].AsInt32()
                    : (base_damage_table.ContainsKey((long)clear_count) ? base_damage_table[(long)clear_count].AsInt32() : 0);
            }

            base_damage = 0;
        }
        else
        {
            base_damage = base_damage_table.ContainsKey((long)clear_count) ? base_damage_table[(long)clear_count].AsInt32() : 0;
        }

        // 记录本次消行的攻击值（base+spin，不含BTB加成），供连击公式使用
        int attack_value = base_damage + spin_damage;

        // BTB 加成（从第二次连续BTB开始；btb>=4 时额外+1，即 +2）- 适用于 spin 和 quad
        if (btb_count > 1)
        {
            int btb_boost = btb_count >= 4 ? 2 : 1;
            if (spin_type.Length > 0)
            {
                spin_damage += btb_boost;
            }
            else if (clear_count >= 4)
            {
                base_damage += btb_boost;
            }
        }

        if (btb_count >= 4 && spin_type.Length == 0 && clear_count < 4)
        {
            surge_break = btb_count;
        }
        else
        {
            surge_break = 0;
        }

        int combo_damage = 0;
        if (combo_count > 0)
        {
            if (combo_formula == 1)
            {
                // 新公式（默认）：
                //   combo_damage = floor(max(ln(1+1.25*combo), ((is_btb_active?1:0)+attack)*(1+0.25*combo)))
                //   其中 attack = base+spin（不含BTB加成）
                float b2b_flag = is_btb_active ? 1.0f : 0.0f;
                float combined = (b2b_flag + attack_value) * (1.0f + 0.25f * combo_count);
                float log_term = Mathf.Log(1.0f + 1.25f * combo_count);
                combo_damage = Mathf.FloorToInt(Mathf.Max(log_term, combined));
            }
            else
            {
                // 旧连击表（备选项）
                bool is_mini = spin_type.IndexOf("Mini") != -1;
                bool is_quad = clear_count >= 4;
                if (!is_mini && is_quad)
                {
                    // 非mini spin且quad：伤害 +combo_count（x）
                    combo_damage = combo_count;
                }
                else if (is_mini)
                {
                    // mini spin：伤害 +floor(ln((x²/2)+1))
                    combo_damage = Mathf.FloorToInt(Mathf.Log(combo_count * combo_count / 3.0f + 1.0f));
                }
                else
                {
                    // 其他情况：使用连击表
                    int index = combo_count;
                    if (index < combo_damage_list.Count)
                    {
                        combo_damage = combo_damage_list[index].AsInt32();
                    }
                    else
                    {
                        float extra = (combo_count - combo_damage_list.Count) / 2.0f;
                        combo_damage = (int)Mathf.Min(5, combo_damage_list[combo_damage_list.Count - 1].AsInt32() + extra);
                    }
                }
            }
        }

        return base_damage + spin_damage + combo_damage + surge_break;
    }

    /// <summary>
    /// 获取Spin的键名
    /// </summary>
    public string _get_spin_key(string spin_type)
    {
        if (spin_type.IndexOf("T-Spin") != -1)
        {
            if (spin_type.IndexOf("Mini") != -1)
            {
                return "Mini T-Spin";
            }
            return "T-Spin";
        }
        return spin_type;
    }

    /// <summary>
    /// 获取当前消行的伤害值
    /// </summary>
    public int get_current_damage()
    {
        return current_damage;
    }

    /// <summary>
    /// 供 bot 读取当前 buff 调整后的并行搜索线程数（0 = 由 bridge 自动决定）。
    /// </summary>
    public int get_bot_threads()
    {
        return bot_threads;
    }

    /// <summary>
    /// 供 bot 读取"实际游戏规则/伤害模型"的伤害表（lt→bot 桥接）。
    /// 返回当前生效的基础伤害表、T-Spin 伤害表、连击伤害表、BTB 加成、PC 伤害。
    /// 这些表可由 buff 界面（extra_data）调整后读取，bot 据此模拟真实伤害。
    /// </summary>
    public Godot.Collections.Dictionary get_damage_tables()
    {
        var tbl = new Godot.Collections.Dictionary();
        tbl["enabled"] = true;
        // 基础伤害表（按下标=消行数 0..4）
        var @base = new Godot.Collections.Array();
        for (int i = 0; i < 5; i++)
        {
            @base.Add(base_damage_table.ContainsKey((long)i) ? base_damage_table[(long)i] : (long)0);
        }
        tbl["base_damage"] = @base;
        // T-Spin 伤害表（按下标=消行数 0..3，下标0为0）
        var tspin = new Godot.Collections.Array() { (long)0, (long)0, (long)0, (long)0 };
        var ts_data = spin_damage_table.ContainsKey("T-Spin")
            ? spin_damage_table["T-Spin"].AsGodotDictionary()
            : new Godot.Collections.Dictionary();
        for (int i = 1; i < 4; i++)
        {
            tspin[i] = ts_data.ContainsKey((long)i) ? ts_data[(long)i] : (long)0;
        }
        tbl["tspin_damage"] = tspin;
        // 连击伤害表（按下标=连击数 0..31）
        var combo = new Godot.Collections.Array();
        for (int i = 0; i < 32; i++)
        {
            if (i < combo_damage_list.Count)
            {
                combo.Add(combo_damage_list[i]);
            }
            else
            {
                // 超出表长：min(5, list[-1] + (i - size)/2)，与 _calculate_damage 一致
                float extra = (i - combo_damage_list.Count) / 2.0f;
                combo.Add(Mathf.Min(5, combo_damage_list[combo_damage_list.Count - 1].AsInt32() + (int)extra));
            }
        }
        tbl["combo_damage"] = combo;
        // 连击计算方式：0=旧连击表，1=新公式（默认）——同步给 CC 的 combo 处理
        tbl["combo_formula"] = combo_formula;
        tbl["b2b_bonus"] = 1;
        tbl["pc_damage"] = pc_damage;
        // All-Spin 伤害表（独立表，默认同 T-Spin 值，可由 buff 调整）
        var allspin = new Godot.Collections.Array() { (long)0, (long)0, (long)0, (long)0 };
        for (int i = 1; i < 4; i++)
        {
            allspin[i] = allspin_damage_table.ContainsKey((long)i) ? allspin_damage_table[(long)i] : (long)0;
        }
        tbl["allspin_damage"] = allspin;
        // allspin_1 规则是否启用（tetris_allspin==1）
        tbl["allspin_enabled"] = (tetris_allspin == 1);
        // NoSpin 规则（Talentless）：0=默认；1=所有Spin视为Mini；2=不判定任何Spin（同步给 bot 评估）
        tbl["no_spin"] = no_spin;
        // bot 评估权重：仅返回 buff 显式传参的键（bot_weight_override_keys 由
        // tower_controller._extra_data_deal 填充）。这样 bridge 默认权重为主，
        // 只有 buff 真正传了参的键才会覆盖 bridge。
        var bot_weights = new Godot.Collections.Dictionary()
        {
            { "eval_mult", bot_eval_mult },
            { "attack_efficiency_weight", bot_attack_efficiency_weight },
            { "b2b_clear", bot_b2b_clear },
            { "height", bot_height },
            { "clear4", bot_clear4 },
            { "clear1", bot_clear1 },
            { "clear2", bot_clear2 },
            { "clear3", bot_clear3 },
            { "tspin1", bot_tspin1 },
            { "tspin2", bot_tspin2 },
            { "tspin3", bot_tspin3 },
            { "mini_tspin1", bot_mini_tspin1 },
            { "mini_tspin2", bot_mini_tspin2 },
            { "allspin1", bot_allspin1 },
            { "allspin2", bot_allspin2 },
            { "allspin3", bot_allspin3 },
            { "allspin3plus", bot_allspin3plus },
            { "perfect_clear", bot_perfect_clear },
            { "combo_garbage", bot_combo_garbage },
            { "wasted_t", bot_wasted_t },
            { "move_time", bot_move_time },
            { "allspin_repeat_penalty", bot_allspin_repeat_penalty },
        };
        foreach (Variant key in bot_weights.Keys)
        {
            if (bot_weight_override_keys.ContainsKey(key))
            {
                tbl[key] = bot_weights[key];
            }
        }
        return tbl;
    }

    /// <summary>
    /// 获取连击文本
    /// </summary>
    public string _get_combo_text()
    {
        if (combo_count > 0)
        {
            return string.Format("{0} Combo", combo_count);
        }
        return "";
    }

    /// <summary>
    /// 获取BTB文本
    /// </summary>
    public string _get_btb_text()
    {
        if (is_btb_active && btb_count > 1)
        {
            return string.Format("{0} x BTB", btb_count - 1);
        }
        return "";
    }

    // ========== 查找完整行 ==========

    public Godot.Collections.Array _find_complete_lines()
    {
        var complete_lines = new Godot.Collections.Array();

        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            if (garbage_line_controller != null && garbage_line_controller.is_solid_garbage_row(y))
            {
                continue;
            }

            bool is_complete = true;
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                if (board_drawer.get_cell_color(x, y).VariantType == Variant.Type.Nil)
                {
                    is_complete = false;
                    break;
                }
            }

            if (is_complete)
            {
                complete_lines.Add((long)y);
            }
        }

        return complete_lines;
    }

    public void _clear_lines(Godot.Collections.Array lines)
    {
        if (lines.Count == 0)
        {
            return;
        }

        lines.Sort();

        foreach (Variant y_variant in lines)
        {
            _clear_single_line(y_variant.AsInt32());
        }

        board_drawer.QueueRedraw();
    }

    public void _clear_single_line(int line_y)
    {
        for (int y = line_y; y > 0; y--)
        {
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                Variant color = board_drawer.get_cell_color(x, y - 1);
                board_drawer.set_cell_color(x, y, color);
            }
        }

        for (int x = 0; x < board_drawer.grid_width; x++)
        {
            board_drawer.set_cell_color(x, 0, new Variant());
        }
    }

    /// <summary>
    /// 单个函数：清除可消除的行。
    /// 导入 clear_line_delay_time 变量：当 clear_line_delay_time > 0 时播放消行动画
    /// （对已清除的行区域进行闪烁提示，持续 clear_line_delay_time 秒），消行延迟计时结束
    /// （clear_line_delay_timer 超时）后才调用 spawn_new_piece 生成新方块；
    /// clear_line_delay_time == 0 时直接清除并立即生成新方块。
    /// </summary>
    public void _clear_lines_animated(Godot.Collections.Array lines)
    {
        if (lines.Count == 0)
        {
            // 没有可消除的行：无需等待，直接生成新方块
            _spawn_next_piece_after_clear();
            return;
        }
        lines.Sort();
        if (clear_line_delay_time > 0)
        {
            // 消行延迟期间：仅播放消行动画（完整行仍保留、不位移），
            // 延迟结束后才执行正式消行（位移）并生成新方块。
            _pending_clear_lines = lines;
            if (board_drawer != null)
            {
                board_drawer.set_clearing_lines(lines);
            }
            _is_clear_animating = true;
            clear_line_delay_timer.WaitTime = clear_line_delay_time;
            clear_line_delay_timer.Start();
        }
        else
        {
            // 无延迟：立即执行正式消行（位移）并生成新方块
            _pending_clear_lines = new Godot.Collections.Array();
            _clear_lines(lines);
            _spawn_next_piece_after_clear();
        }
    }

    /// <summary>
    /// 消行延迟计时结束：结束动画，执行正式消行（位移）并生成新方块
    /// </summary>
    public void _on_clear_line_delay_timeout()
    {
        _is_clear_animating = false;
        if (board_drawer != null)
        {
            board_drawer.clear_clearing_lines();
        }
        // 消行延迟结束：此时才执行正式消行（把行进行位移清除）
        if (_pending_clear_lines.Count != 0)
        {
            _clear_lines(_pending_clear_lines);
            _pending_clear_lines = new Godot.Collections.Array();
        }
        // 消行延迟结束：恢复消行延迟期间被暂缓的垃圾行上涨（不丢弃行）
        if (garbage_line_controller != null)
        {
            garbage_line_controller.resume_rise_if_pending();
        }
        // 消行延迟结束：生成新方块
        _spawn_next_piece_after_clear();
    }

    /// <summary>
    /// 是否正处于消行动画/消行延迟中（供垃圾行控制器判断是否需暂缓上涨）
    /// </summary>
    public bool is_clear_animating_active()
    {
        return _is_clear_animating;
    }

    /// <summary>
    /// 消行结束后生成新方块
    /// </summary>
    public void _spawn_next_piece_after_clear()
    {
        if (tetris_controller != null)
        {
            tetris_controller.spawn_new_piece();
        }
    }

    // ========== Spin检测系统 ==========

    /// <summary>
    /// NoSpin==1：把所有 Spin 类型强制降级为 MiniSpin（"T-Spin"→"Mini T-Spin"，已是 Mini 保持不变）。
    /// 这样 _calculate_damage 会命中 "Mini" 分支，采用 mini（基础）伤害表。
    /// </summary>
    public string _force_mini_spin(string spin_type)
    {
        if (spin_type.Length == 0)
        {
            return "";
        }
        if (spin_type.IndexOf("Mini") != -1)
        {
            return spin_type;
        }
        return "Mini " + spin_type;
    }

    public string _detect_spin_type()
    {
        if (no_spin == 2)
        {
            return "";
        }
        if (!spin_detection_enabled)
        {
            return "";
        }

        if (!last_rotation_occurred)
        {
            return "";
        }

        if (!_is_piece_stuck(last_rotation_piece_shape, last_rotation_position))
        {
            // 未卡住 → T块额外检测 Mini T-Spin
            if (last_rotation_piece_type == "T")
            {
                return _detect_t_spin_mini();
            }
            return "";
        }

        // 卡住了
        if (last_rotation_piece_type == "T")
        {
            // T块卡住 → 全 T-Spin
            return "T-Spin";
        }

        if (tetris_allspin == 1)
        {
            // Allspin模式：非T块卡住 → 全 Spin（不加 Mini 前缀）
            return last_rotation_piece_type + "-Spin";
        }

        // 非T块卡住 → 视作 Mini Spin
        return "Mini " + last_rotation_piece_type + "-Spin";
    }

    public bool _is_piece_stuck(Godot.Collections.Array shape, Vector2I piece_position)
    {
        if (tetris_controller == null)
        {
            return false;
        }

        var directions = new Godot.Collections.Array
        {
            new Vector2I(-1, 0),
            new Vector2I(1, 0),
            new Vector2I(0, 1),
            new Vector2I(0, -1)
        };

        foreach (Variant dir_variant in directions)
        {
            Vector2I dir = dir_variant.AsVector2I();
            var new_pos = new Vector2I(piece_position.X + dir.X, piece_position.Y + dir.Y);
            if (!tetris_controller._check_collision(new_pos, shape))
            {
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// 检测T块专用 Mini T-Spin
    /// 条件：左下和右下都被方块或墙占据，且左上或右上有一个被方块或墙占据
    /// 返回 "Mini T-Spin" 或 ""
    /// </summary>
    public string _detect_t_spin_mini()
    {
        int pos_x = last_rotation_position.X;
        int pos_y = last_rotation_position.Y;

        // T块 3x3 包围盒的四个角
        bool bl_blocked = _is_corner_blocked(pos_x, pos_y + 2);       // 左下
        bool br_blocked = _is_corner_blocked(pos_x + 2, pos_y + 2);   // 右下
        bool tl_blocked = _is_corner_blocked(pos_x, pos_y);           // 左上
        bool tr_blocked = _is_corner_blocked(pos_x + 2, pos_y);       // 右上

        // 左下和右下都要被封堵
        if (!(bl_blocked && br_blocked))
        {
            return "";
        }

        // 左上或右上至少有一个被封堵
        if (!(tl_blocked || tr_blocked))
        {
            return "";
        }

        return "Mini T-Spin";
    }

    /// <summary>
    /// 检查一个角落位置是否被封堵（超出边界 或 该位置有方块）
    /// </summary>
    public bool _is_corner_blocked(int x, int y)
    {
        // 左右超出边界 → 被墙壁封堵
        if (x < 0 || x >= board_drawer.grid_width)
        {
            return true;
        }
        // 底部超出边界 → 被地板封堵
        if (y >= board_drawer.get_playable_height())
        {
            return true;
        }
        // 上方超出边界 → 不算封堵（可在出块区域之上）
        if (y < 0)
        {
            return false;
        }
        // 检查该位置是否有方块
        if (board_drawer.get_cell_color(x, y).VariantType != Variant.Type.Nil)
        {
            return true;
        }
        return false;
    }

    // ========== 显示系统 ==========

    public string _get_clear_text(int count)
    {
        if (clear_texts.ContainsKey((long)count))
        {
            return clear_texts[(long)count].AsString();
        }
        return "";
    }

    /// <summary>
    /// 文本锚点X坐标：版面外侧，距离左边框一小段距离
    /// </summary>
    public float _get_text_anchor_x()
    {
        return board_drawer.offset_x - text_gap_cells * board_drawer.cell_size;
    }

    /// <summary>
    /// 非BTB文本的漂移速度（向左慢慢移动）
    /// </summary>
    public Vector2 _get_text_drift()
    {
        return new Vector2(-text_drift_cells_per_sec * board_drawer.cell_size, 0);
    }

    /// <summary>
    /// 消行文本基准Y（Hold框底部）
    /// </summary>
    public float _get_text_base_y()
    {
        var hold_pos = board_drawer._get_hold_position();
        var hold_height = board_drawer.hold_display_height * board_drawer.cell_size;
        return hold_pos.Y + hold_height;
    }

    public void _show_clear_and_spin_text(int clear_count, string spin_type, int _damage)
    {
        if (clear_count <= 0 || text_printer == null)
        {
            return;
        }

        string clear_text = _get_clear_text(clear_count);
        if (clear_text.Length == 0)
        {
            return;
        }

        int cell = board_drawer.cell_size;
        float bottom_y = _get_text_base_y();
        float anchor_x = _get_text_anchor_x();

        Vector2 clear_spin_drift = _get_text_drift() * clear_spin_drift_scale;
        float clear_spin_fade = text_fade_duration * clear_spin_fade_scale;
        // 淡出与移动并行：这里把保持期缩短，让淡出在文本仍在移动时就开始
        float clear_spin_hold = clear_text_display_duration * clear_spin_hold_scale;

        float offset_y = clear_text_offset_y_cells * cell;
        clear_text_position = new Vector2(anchor_x, bottom_y + offset_y);
        text_printer.show_text("clear", clear_text, clear_text_position,
            clear_text_color, clear_text_outline_color, cell * 1.0f,
            false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift);

        if (spin_type.Length > 0)
        {
            float spin_offset_y = (clear_text_offset_y_cells - spin_text_offset_y_cells) * cell;
            spin_text_position = new Vector2(anchor_x, bottom_y + spin_offset_y);
            text_printer.show_text("spin", spin_type, spin_text_position,
                display_spin_color, spin_text_outline_color, cell * 0.8f,
                false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift);
        }
        else
        {
            text_printer.remove_text("spin");
        }

        string combo_text = _get_combo_text();
        if (combo_text.Length > 0)
        {
            float combo_offset_y = (clear_text_offset_y_cells + combo_text_offset_y_cells) * cell;
            combo_text_position = new Vector2(anchor_x, bottom_y + combo_offset_y);
            // combo 特例：有新 combo 时立即重置，移除旧文本后再显示新的，不做叠加
            text_printer.remove_text("combo");
            text_printer.show_text("combo", combo_text, combo_text_position,
                combo_text_color, combo_text_outline_color, cell * 0.8f,
                false, text_base_opacity, clear_text_display_duration, text_fade_duration, _get_text_drift());
        }
        else
        {
            text_printer.remove_text("combo");
        }

        // BTB常驻显示（persistent=true）
        string btb_text = _get_btb_text();
        if (btb_text.Length > 0)
        {
            float btb_offset_y = btb_text_offset_y_cells * cell;
            btb_text_position = new Vector2(anchor_x, bottom_y + btb_offset_y);
            text_printer.show_text("btb", btb_text, btb_text_position,
                btb_text_color, btb_text_outline_color, cell * 1.0f,
                true, 1.0f);
        }
        else
        {
            text_printer.remove_text("btb");
        }

        //print("消行: ", clear_count, "，Spin: ", spin_type, "，伤害: ", damage, "，Spin颜色: ", display_spin_color)
    }

    /// <summary>
    /// 仅显示Spin文本（无消行，Spin0）
    /// </summary>
    public void _show_spin_text_only(string spin_type)
    {
        if (spin_type.Length == 0 || text_printer == null)
        {
            return;
        }

        if (spin_color_ready)
        {
            display_spin_color = pending_spin_color;
        }
        else
        {
            display_spin_color = Colors.Yellow;
        }

        int cell = board_drawer.cell_size;
        // 计算spin文本位置
        spin_text_position = new Vector2(_get_text_anchor_x(), _get_text_base_y() + spin_text_offset_y_cells * cell);
        Vector2 clear_spin_drift = _get_text_drift() * clear_spin_drift_scale;
        float clear_spin_fade = text_fade_duration * clear_spin_fade_scale;
        float clear_spin_hold = clear_text_display_duration * clear_spin_hold_scale;
        text_printer.show_text("spin", spin_type, spin_text_position,
            display_spin_color, spin_text_outline_color, cell * 0.8f,
            false, text_base_opacity, clear_spin_hold, clear_spin_fade, clear_spin_drift);
        // 不重置其他文本，让它们自然淡出
    }

    /// <summary>
    /// 获取当前显示的Spin文本颜色
    /// </summary>
    public Color get_spin_trigger_color()
    {
        return display_spin_color;
    }

    /// <summary>
    /// 检查是否有消行文本正在显示
    /// </summary>
    public bool is_text_displaying()
    {
        return text_printer != null && text_printer.has_text("clear");
    }

    /// <summary>
    /// 获取当前显示的Spin文本（供TetrisController统计用）
    /// </summary>
    public string get_current_spin_text()
    {
        if (text_printer != null)
        {
            return text_printer.get_text("spin");
        }
        return "";
    }

    /// <summary>
    /// 重置消行状态
    /// </summary>
    public void reset()
    {
        lines_to_clear.Clear();
        is_animating = false;
        if (text_printer != null)
        {
            text_printer.clear_all();
        }
        damage_timer.Stop();
        reset_rotation_record();
        combo_count = 0;
        btb_count = 0;
        is_btb_active = false;
        current_damage = 0;
        accumulated_damage = 0;
        damage_pending = false;
        clear_spin_color();
        has_cleared_lines = false;
    }

    /// <summary>
    /// 获取当前连击数
    /// </summary>
    public int get_combo_count()
    {
        return combo_count;
    }

    /// <summary>
    /// 获取当前BTB数
    /// </summary>
    public int get_btb_count()
    {
        return btb_count;
    }

    /// <summary>
    /// 手动设置连击（用于调试）
    /// </summary>
    public void set_combo(int count)
    {
        combo_count = count;
    }

    /// <summary>
    /// 手动设置BTB（用于调试）
    /// </summary>
    public void set_btb(int count)
    {
        btb_count = count;
        is_btb_active = count > 0;
    }
}
