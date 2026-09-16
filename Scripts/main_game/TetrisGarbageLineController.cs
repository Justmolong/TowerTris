using Godot;

/// <summary>
/// 俄罗斯方块垃圾行控制器
/// 负责垃圾行的生成、管理和增长逻辑
/// </summary>
public partial class TetrisGarbageLineController : Node
{
    // 节点引用
    [Export]
    public TetrisBoardDrawer board_drawer;  // 版面绘制器节点
    [Export]
    public TetrisController tetris_controller;  // 方块控制器引用（用于清除当前方块）
    [Export]
    public TetrisClearLine clear_line_controller;  // 消行控制器引用（用于检测消行延迟）

    // 垃圾行配置
    [Export]
    public int garbage_cap = 3;                      // 每次锁定最多增长的垃圾行数量（也用于版面garbage_cap线）
    [Export]
    public float garbage_messy = 0.9f;               // 垃圾行更换洞口的概率（0-1）
    [Export]
    public Color garbage_color = new Color(0.5f, 0.5f, 0.5f, 1.0f);  // 垃圾行颜色（浅灰色）
    [Export]
    public Color solid_garbage_color = new Color(0.3f, 0.3f, 0.3f, 1.0f);  // 实心垃圾行颜色（深灰色）
    [Export]
    public Color garbage_empty_color = new Color(0.08f, 0.08f, 0.08f, 1.0f);  // 垃圾行洞口颜色（与版面背景一致）

    // DoubleHole buff：垃圾行洞口形态
    // garbage_hole_wide_count：X宽（每行生成一组紧邻连续洞口），>1 时生效；与 garbage_hole_count 互斥
    // garbage_hole_count：每行洞口数量（在基础洞上补足），>1 时生效；与 garbage_hole_wide_count 互斥
    // 两者均默认 1（一个洞且 1 宽，即普通单洞垃圾行）
    [Export]
    public int garbage_hole_wide_count = 1;
    [Export]
    public int garbage_hole_count = 1;

    // 垃圾缓冲配置
    [Export]
    public float buffer_duration = 3.0f;             // 垃圾缓冲时间（秒）

    // 抵消倍率：每 1 行攻击可抵消 mult_defend 行垃圾
    [Export]
    public float mult_defend = 1.0f;                 // 抵消倍率（默认 1.0）

    /// <summary>供 bot 读取当前关卡 buff 调整后的防御倍率（mult_defend）。</summary>
    public float get_mult_defend()
    {
        return mult_defend;
    }

    // ====== 瞬间/逐行上涨模式 ======
    /// <summary>
    /// true = 旧逻辑：锁定方块时一次性上涨所有垃圾行
    /// false = 逐行上涨：垃圾行加入依次上涨队列，每 garbage_rise_time_delay 秒上涨一行
    /// </summary>
    [Export]
    public bool suddenly_death_mode = false;

    /// <summary>
    /// false = 传统逻辑：方块锁定后才触发垃圾行上涨
    /// true = 取消锁定限制：缓冲计时结束即刻上涨垃圾行
    /// </summary>
    [Export]
    public bool drop_limit_cancel = false;

    /// <summary>逐行上涨模式下的行间隔时间（秒）</summary>
    [Export]
    public float garbage_rise_time_delay = 0.5f;

    /// <summary>依次上涨队列：存储 {holes, is_buffered, color, empty_color} 等行数据</summary>
    public Godot.Collections.Array _pending_rise_queue = new Godot.Collections.Array();

    /// <summary>
    /// 消行延迟期间暂存的一次性直接上涨（延迟结束后统一上涨，避免消行动画期间改动版面）
    /// 元素结构 {all_holes: Array, row_count: int}
    /// </summary>
    public Godot.Collections.Array _deferred_direct_raises = new Godot.Collections.Array();

    /// <summary>
    /// 消行延迟期间暂存的实心垃圾行上涨数量（延迟结束后统一上涨，避免消行动画期间
    /// 改动版面，导致待消行位移、实心行被意外消除或填充）
    /// </summary>
    public Godot.Collections.Array _deferred_solid_raises = new Godot.Collections.Array();

    /// <summary>逐行上涨计时器</summary>
    public Timer _rise_timer;

    [Export]
    public Color buffered_garbage_color = new Color(0.5f, 0.0f, 0.0f, 0.7f);  // 缓冲垃圾颜色（半透明暗红色）
    [Export]
    public Color buffered_garbage_empty_color = new Color(0.2f, 0.0f, 0.0f, 0.5f);  // 缓冲垃圾洞口颜色

    // 垃圾行数据
    public Godot.Collections.Array garbage_enter_array = new Godot.Collections.Array();                  // 储存打入的攻击 [{count: int, extra_hole_count: int}, ...]
    public Godot.Collections.Array garbage_output_array = new Godot.Collections.Array();                 // 储存垃圾行洞口位置 [[X], [Y], [Z], ...]

    // 垃圾缓冲数据
    public Godot.Collections.Array garbage_buffer = new Godot.Collections.Array();                       // 缓冲中的垃圾数据 [{count: int, holes: Array, timer: float, is_buffered: bool}]

    // 实心垃圾行数据（不可消除）
    public Godot.Collections.Dictionary solid_garbage_rows = new Godot.Collections.Dictionary();              // 记录实心垃圾行的行索引 {row_index: true}

    // 内部状态
    public Godot.Collections.Array pending_garbage_data = new Godot.Collections.Array();                // 待处理的垃圾行数据 [{count: int, holes: Array}, ...]
    public bool is_garbage_locked = false;                 // 是否正在处理垃圾行锁定
    public Godot.Collections.Dictionary garbage_rows_data = new Godot.Collections.Dictionary();              // 记录每行垃圾行的洞口位置 {row_index: [hole_x]}
    public Godot.Collections.Array current_active_hole = new Godot.Collections.Array();                 // 当前活跃的洞口位置（用于溢出保留）
    public bool has_overflow = false;                      // 是否有溢出的垃圾行

    public override void _Ready()
    {
        // 自动查找board_drawer（如果未设置）
        if (board_drawer == null)
        {
            board_drawer = GetNodeOrNull<TetrisBoardDrawer>("../TetrisBoardDrawer");
            if (board_drawer == null)
            {
                GD.PushError("TetrisGarbageLineController: 未找到TetrisBoardDrawer节点！");
                return;
            }
        }

        // 自动查找tetris_controller（如果未设置）
        if (tetris_controller == null)
        {
            tetris_controller = GetNodeOrNull<TetrisController>("../TetrisController");
            if (tetris_controller == null)
            {
                GD.PushError("TetrisGarbageLineController: 未找到TetrisController节点！");
                // 不是致命错误，继续运行
            }
        }

        // 自动查找clear_line_controller（如果未设置）
        if (clear_line_controller == null)
        {
            clear_line_controller = GetNodeOrNull<TetrisClearLine>("../TetrisClearLine");
        }

        // 初始化逐行上涨计时器
        _rise_timer = new Timer();
        _rise_timer.OneShot = false;
        _rise_timer.Timeout += _on_rise_timer_timeout;
        AddChild(_rise_timer);

        // 初始化垃圾行输出队列
        _refill_garbage_output();
    }

    public override void _Process(double delta)
    {
        // 更新缓冲垃圾计时器
        _update_buffer_timers((float)delta);
    }

    /// <summary>更新缓冲垃圾计时器</summary>
    public void _update_buffer_timers(float delta)
    {
        if (garbage_buffer.Count == 0)
            return;

        int i = 0;
        while (i < garbage_buffer.Count)
        {
            var buffer_entry = garbage_buffer[i].AsGodotDictionary();
            buffer_entry["timer"] = buffer_entry["timer"].AsSingle() - delta;

            // 计时归零，将缓冲垃圾转为正常垃圾
            if (buffer_entry["timer"].AsSingle() <= 0)
            {
                // 从缓冲移除并添加到正常队列
                int converted_count = buffer_entry["count"].AsInt32();
                int converted_extra_hole_count = buffer_entry.ContainsKey("extra_hole_count") ? buffer_entry["extra_hole_count"].AsInt32() : 0;

                // 添加到正常队列末尾（先缓冲完的在底部，先出）
                garbage_enter_array.Add(new Godot.Collections.Dictionary()
                {
                    { "count", converted_count },
                    { "extra_hole_count", converted_extra_hole_count },
                });

                // 从缓冲中移除
                garbage_buffer.RemoveAt(i);

                // drop_limit_cancel = true 时：缓冲结束即刻上涨，不再等待方块锁定
                if (drop_limit_cancel)
                {
                    if (garbage_enter_array.Count > 0)
                    {
                        // 消行延迟期间不立即上涨（保留在 enter_array 中不丢弃，延迟结束后随下次触发上涨）
                        if (is_clear_delay_active())
                            continue;
                        int success = process_garbage_after_lock();
                        if (success <= 0 && tetris_controller != null)
                            tetris_controller._game_over("垃圾上涨失败");
                    }
                }

                //print("缓冲垃圾已就绪: ", converted_count, " 行，当前队列: ", garbage_enter_array)
            }
            else
            {
                i += 1;
            }
        }
    }

    /// <summary>补充垃圾行输出队列（默认生成garbage_cap大小）</summary>
    public void _refill_garbage_output()
    {
        while (garbage_output_array.Count < garbage_cap)
        {
            var new_hole = _generate_single_hole();
            garbage_output_array.Add(new_hole);
        }
    }

    /// <summary>
    /// 为单个垃圾行生成所有洞口位置（基于基础洞口 + 随机额外挖洞）
    /// 参数 base_hole: [int] 基础洞口x坐标（所有行共享）
    /// 参数 extra_hole_count: 额外随机挖洞数（每行独立）
    /// DoubleHole buff 生效时优先覆盖本函数结果：
    ///  - garbage_hole_wide_count > 1：忽略 extra_hole_count，将基础洞作为锚点生成一组紧邻连续洞口（X宽）。
    ///    由于 base_hole 在同一批次（同一组 add_attack）内保持不变，同组各行共享同一紧邻洞口位置；
    ///    批次间经 garbage_messy / _should_change_hole 更换基础洞时才变化。
    ///  - garbage_hole_count > 1：在基础洞上至少补足到 garbage_hole_count 个随机洞口
    /// </summary>
    public Godot.Collections.Array _generate_row_holes(Godot.Collections.Array base_hole, int extra_hole_count)
    {
        var garbage_rng = RandomManager.get_random("GARBAGE");
        // X宽：以基础洞为锚点，生成一组紧邻连续洞口（同组各行位置一致）
        if (garbage_hole_wide_count > 1)
        {
            int grid_w = board_drawer.grid_width;
            int w = Mathf.Min(garbage_hole_wide_count, grid_w);
            int anchor = base_hole.Count > 0 ? base_hole[0].AsInt32() : 0;
            int start_x = Mathf.Clamp(anchor, 0, grid_w - w);
            var wide_holes = new Godot.Collections.Array();
            for (int x = start_x; x < start_x + w; x++)
                wide_holes.Add(x);
            return wide_holes;
        }
        // 每行洞口数量：在基础洞上至少补足到 garbage_hole_count 个
        if (garbage_hole_count > 1)
        {
            extra_hole_count = Mathf.Max(extra_hole_count, garbage_hole_count - 1);
        }
        var result = (Godot.Collections.Array)base_hole.Duplicate();
        for (int _i = 0; _i < extra_hole_count; _i++)
        {
            int hole_x = _get_random_hole_position(garbage_rng, -1);
            // 确保不重复
            int attempts = 0;
            while (result.Contains(hole_x) && attempts < 100)
            {
                hole_x = _get_random_hole_position(garbage_rng, -1);
                attempts += 1;
            }
            if (!result.Contains(hole_x))
                result.Add(hole_x);
        }
        return result;
    }

    /// <summary>生成单个垃圾行的洞口位置</summary>
    public Godot.Collections.Array _generate_single_hole()
    {
        var garbage_rng = RandomManager.get_random("GARBAGE");

        // 获取上一个洞口的X位置（用于避免相邻相同）
        int last_hole_x = -1;
        if (garbage_output_array.Count > 0)
        {
            var last_entry = garbage_output_array[garbage_output_array.Count - 1].AsGodotArray();
            if (last_entry.Count > 0)
                last_hole_x = last_entry[0].AsInt32();
        }

        // 生成随机洞口位置（0 到 board_drawer.grid_width - 1）
        int new_hole_x = _get_random_hole_position(garbage_rng, last_hole_x);
        var res = new Godot.Collections.Array();
        res.Add(new_hole_x);
        return res;
    }

    /// <summary>获取随机洞口位置（确保与上一个不同）</summary>
    public int _get_random_hole_position(RandomNumberGenerator rng, int exclude_x)
    {
        const int max_attempts = 100;
        for (int _i = 0; _i < max_attempts; _i++)
        {
            int hole_x = rng.RandiRange(0, board_drawer.grid_width - 1);
            if (hole_x != exclude_x)
                return hole_x;
        }
        // 如果无法生成不同的位置，返回默认值
        return (exclude_x + 1) % board_drawer.grid_width;
    }

    /// <summary>
    /// 添加攻击到进入队列（不限制单次攻击量）
    /// 参数 attack_count: 攻击行数
    /// 参数 add_extra_hole: 额外挖洞数，在1个基础洞口基础上再额外挖 add_extra_hole 个洞
    ///   基础洞口在函数内直接随机生成，额外洞口在每行上涨时独立随机生成
    /// </summary>
    public void add_attack(int attack_count, int add_extra_hole = 0)
    {
        if (attack_count <= 0)
            return;

        var extra_rng = RandomManager.get_random("GARBAGE");

        // 只生成1个基础洞口（所有行共享相同的base_hole）
        int base_hole_x = _get_random_hole_position(extra_rng, -1);
        var base_hole = new Godot.Collections.Array();
        base_hole.Add(base_hole_x);

        // 添加到缓冲队列（带计时器）
        var buffer_entry = new Godot.Collections.Dictionary()
        {
            { "count", attack_count },
            { "holes", base_hole },
            { "base_hole", base_hole },
            { "extra_hole_count", add_extra_hole },
            { "timer", buffer_duration },
            { "is_buffered", true },
        };
        garbage_buffer.Add(buffer_entry);

        // 关联到TetrisController的RPM统计
        if (tetris_controller != null)
        {
            // 使用record_received_damage方法记录接收攻击
            tetris_controller._record_received_damage(attack_count);
        }

        //print("添加攻击: ", attack_count, " 行，额外挖洞: ", add_extra_hole, "，洞口: ", holes, "（缓冲中），当前缓冲: ", garbage_buffer)
    }

    /// <summary>获取缓冲中的垃圾数据（用于显示）</summary>
    public Godot.Collections.Array get_buffered_garbage()
    {
        return (Godot.Collections.Array)garbage_buffer.Duplicate();
    }

    /// <summary>检查是否有缓冲中的垃圾</summary>
    public bool has_buffered_garbage()
    {
        return garbage_buffer.Count > 0;
    }

    // ========== 强制上涨系统（核心功能） ==========

    /// <summary>
    /// 强制上涨行数（通用功能，支持自定义行数据生成器）
    /// 版面版本号：每次垃圾行成功上涨（force_raise_rows 真正上移了行）时 +1。
    /// 用于让 bot 感知“垃圾行抬升期间版面已变化”，从而重新请求决策，避免执行过期计划。
    /// </summary>
    public int board_version = 0;

    /// <summary>
    /// 计算新垃圾行应插入的起始行索引：紧贴底部实心块上方；无实心块时为版面底部。
    /// 与 force_raise_rows 的版面构建逻辑保持一致，供各调用方记录新行洞口位置。
    /// </summary>
    public int _get_new_rows_start(int row_count)
    {
        int H = board_drawer.get_playable_height();
        int bottom_solid = 0;
        for (int y = H - 1; y >= 0; y--)
        {
            if (is_solid_garbage_row(y))
                bottom_solid += 1;
            else
                break;
        }
        return (H - bottom_solid) - row_count;
    }

    /// <summary>强制上涨单行生成器委托：i = 行序号（0起），total = 本次上涨总行数；返回该行的单元格颜色数组（空格为 nil）</summary>
    public delegate Godot.Collections.Array RowGeneratorDelegate(int i, int total);

    public bool force_raise_rows(int row_count, RowGeneratorDelegate row_generator, bool skip_piece_handling = false)
    {
        if (row_count <= 0)
            return false;

        // 限制单次上涨数量
        row_count = Mathf.Min(row_count, garbage_cap);

        // 如果tetris_controller存在，先清除当前方块并记录其位置
        Vector2I? current_pos = null;
        if (tetris_controller != null && !skip_piece_handling)
        {
            // 保存当前方块位置
            current_pos = tetris_controller.current_position;
            // 清除当前方块（从版面上移除）
            tetris_controller._clear_current_piece();
        }

        // 收集当前版面所有数据
        var board_data = new Godot.Collections.Array();
        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            var row = new Godot.Collections.Array();
            for (int x = 0; x < board_drawer.grid_width; x++)
                row.Add(board_drawer.get_cell_color(x, y));
            board_data.Add(row);
        }

        // 计算需要上移的行数
        int shift_amount = row_count;
        int H = board_drawer.get_playable_height();

        // 计算底部实心垃圾行块的高度（实心行必定处于最底层，不可被顶起）
        int bottom_solid = 0;
        for (int y = H - 1; y >= 0; y--)
        {
            if (is_solid_garbage_row(y))
                bottom_solid += 1;
            else
                break;
        }
        // 实心行块的起始行（实心块上方的内容行索引小于该值）
        int solid_start = H - bottom_solid;
        // 新垃圾行插入的起始行：紧贴实心块上方（无实心块时即为版面底部）
        int new_row_start = Mathf.Max(0, solid_start - shift_amount);

        // 创建新版面数据
        var new_board_data = new Godot.Collections.Array();

        // 上移实心块上方的非实心内容（顶部被挤出）
        for (int y = 0; y < new_row_start; y++)
        {
            var row_data = new Godot.Collections.Array();
            int source_y = y + shift_amount;
            if (source_y < board_data.Count)
            {
                var source_row = board_data[source_y].AsGodotArray();
                for (int x = 0; x < board_drawer.grid_width; x++)
                    row_data.Add(source_row[x]);
            }
            else
            {
                for (int x = 0; x < board_drawer.grid_width; x++)
                    row_data.Add(new Variant());
            }
            new_board_data.Add(row_data);
        }

        // 添加新行到实心块上方（紧贴实心块）
        for (int i = 0; i < shift_amount; i++)
        {
            var row_data = row_generator(i, shift_amount);
            new_board_data.Add(row_data);
        }

        // 保留底部实心块（位置不变）
        for (int y = solid_start; y < H; y++)
        {
            var row_data = new Godot.Collections.Array();
            var source_row = board_data[y].AsGodotArray();
            for (int x = 0; x < board_drawer.grid_width; x++)
                row_data.Add(source_row[x]);
            new_board_data.Add(row_data);
        }

        // 清空版面
        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            for (int x = 0; x < board_drawer.grid_width; x++)
                board_drawer.set_cell_color(x, y, new Variant());
        }

        // 写入新数据
        int write_rows = Mathf.Min(new_board_data.Count, board_drawer.get_playable_height());
        for (int y = 0; y < write_rows; y++)
        {
            var new_row = new_board_data[y].AsGodotArray();
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                if (x < new_row.Count)
                {
                    Variant color = new_row[x];
                    if (color.VariantType != Variant.Type.Nil)
                        board_drawer.set_cell_color(x, y, color);
                }
            }
        }

        // 检查是否有任何非空方块超过第50行（y < 50，高于第50行即触发游戏结束）
        // 隐藏区域共70行（0-69），第0-49行为禁止区，第50-69行为安全缓冲
        bool has_block_above_50 = false;
        int check_h = Mathf.Min(50, board_drawer.grid_max_height);
        for (int y = 0; y < check_h; y++)
        {
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                if (board_drawer.get_cell_color(x, y).VariantType != Variant.Type.Nil)
                {
                    has_block_above_50 = true;
                    break;
                }
            }
            if (has_block_above_50)
                break;
        }
        if (has_block_above_50)
        {
            if (tetris_controller != null)
                tetris_controller._game_over("方块堆积过高");
            return false;
        }

        // 如果tetris_controller存在且需要处理当前方块，恢复当前方块（位置向上移动row_count行）
        if (tetris_controller != null && !skip_piece_handling && current_pos.HasValue)
        {
            Vector2I cur_pos = current_pos.Value;
            // 计算新位置：Y坐标向上移动row_count行（减小）
            var new_pos = new Vector2I(cur_pos.X, cur_pos.Y - row_count);

            // 确保位置不超出顶部
            if (new_pos.Y < 0)
                new_pos.Y = 0;

            // 更新方块位置
            tetris_controller.current_position = new_pos;

            // 检查新位置是否碰撞（如果碰撞，说明方块被卡死，可能需要游戏结束处理）
            if (tetris_controller._check_collision(new_pos))
            {
                // 如果碰撞，尝试逐步上移直到找到有效位置
                var test_pos = new_pos;
                while (test_pos.Y > 0 && tetris_controller._check_collision(test_pos))
                    test_pos.Y -= 1;
                if (test_pos.Y >= 0 && !tetris_controller._check_collision(test_pos))
                {
                    tetris_controller.current_position = test_pos;
                }
                else
                {
                    // 无法找到有效位置，游戏结束
                    GD.PushError("方块被卡死，游戏结束");
                    if (tetris_controller != null)
                        tetris_controller._game_over("方块被卡死");
                    return false;
                }
            }

            // 重新绘制当前方块
            tetris_controller._draw_current_piece();

            // 更新影子
            tetris_controller._update_shadow();
        }

        // 请求重绘
        board_drawer.QueueRedraw();

        // 垃圾行洞口记录随版面上移：整版上移 row_count 行后，已有垃圾行的实际行索引
        // 减小 row_count（y=0 为顶部），被挤出顶部的记录应删除；底部新增行的洞口由调用方
        // （_on_rise_timer_timeout / apply_garbage_to_board）另行记录。
        // 若不同步，逐行上涨时 garbage_rows_data 索引错位，会导致 is_garbage_hole /
        // _is_hole_position 判定丢失/错乱（洞口“消失”或出现在错误行）。
        if (row_count > 0 && garbage_rows_data.Count > 0)
        {
            var shifted = new Godot.Collections.Dictionary();
            foreach (Variant row_y in garbage_rows_data.Keys)
            {
                int new_y = row_y.AsInt32() - row_count;
                if (new_y >= 0)
                    shifted[new_y] = garbage_rows_data[row_y];
            }
            garbage_rows_data = shifted;
        }

        // 实心垃圾行记录无需随版面上移：实心行必定处于最底层且被固定，普通垃圾上涨时
        // 实心块位置不变（见上方版面构建逻辑），因此 solid_garbage_rows 保持原索引。
        // （若新增行本身是实心行，add_solid_garbage 会重新扫描整个版面重建该记录。）

        // 版面已因垃圾行上涨而改变：递增版本号，通知 bot 重新决策
        board_version += 1;

        //print("强制上涨了 ", row_count, " 行")
        return true;
    }

    /// <summary>生成普通垃圾行数据（带洞口）</summary>
    public RowGeneratorDelegate _generate_garbage_row_generator(Godot.Collections.Array holes, bool is_buffered = false)
    {
        return (int _i, int _total) =>
        {
            var row_data = new Godot.Collections.Array();
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                bool is_hole = false;
                foreach (Variant hole_x in holes)
                {
                    if (x == hole_x.AsInt32())
                    {
                        is_hole = true;
                        break;
                    }
                }

                if (is_hole)
                {
                    if (is_buffered)
                        row_data.Add(buffered_garbage_empty_color);
                    else
                        row_data.Add(new Variant());
                }
                else
                {
                    if (is_buffered)
                        row_data.Add(buffered_garbage_color);
                    else
                        row_data.Add(garbage_color);
                }
            }
            return row_data;
        };
    }

    /// <summary>生成实心垃圾行数据（全深灰色）</summary>
    public RowGeneratorDelegate _generate_solid_row_generator()
    {
        return (int _i, int _total) =>
        {
            var row_data = new Godot.Collections.Array();
            for (int x = 0; x < board_drawer.grid_width; x++)
                row_data.Add(solid_garbage_color);
            return row_data;
        };
    }

    /// <summary>上涨X行实心垃圾行（无法消除）</summary>
    public void add_solid_garbage(int row_count)
    {
        if (row_count <= 0)
            return;

        // 消行延迟期间：暂存起来，延迟结束后统一上涨（不丢弃行，避免在消行动画期间改动
        // 版面，造成待消行位移、实心行被意外消除/填充）
        if (is_clear_delay_active())
        {
            _deferred_solid_raises.Add(row_count);
            return;
        }

        // 使用强制上涨 + 实心行生成器
        bool success = force_raise_rows(row_count, _generate_solid_row_generator());
        if (success)
        {
            // 清除旧的实心垃圾行记录（因为行索引已经变化）
            solid_garbage_rows.Clear();

            // 重新记录所有实心垃圾行的行索引
            // 遍历版面，找到所有实心垃圾行
            for (int y = 0; y < board_drawer.get_playable_height(); y++)
            {
                bool is_solid = true;
                for (int x = 0; x < board_drawer.grid_width; x++)
                {
                    Variant color = board_drawer.get_cell_color(x, y);
                    if (!_cell_equals(color, solid_garbage_color))
                    {
                        is_solid = false;
                        break;
                    }
                }
                if (is_solid)
                    solid_garbage_rows[y] = true;
            }

            //print("上涨了 ", row_count, " 行实心垃圾行，当前实心行: ", solid_garbage_rows.keys())
        }
    }

    // ========== 垃圾行抵消系统 ==========

    /// <summary>
    /// 抵消垃圾行（优先抵消列表第一项，包括缓冲垃圾）
    /// 实际抵消能力 = attack_damage * mult_defend
    /// </summary>
    public int offset_garbage(int attack_damage)
    {
        if (attack_damage <= 0)
            return 0;

        // 无垃圾可抵消时直接返回
        if (_pending_rise_queue.Count == 0 && garbage_enter_array.Count == 0 && garbage_buffer.Count == 0)
        {
            //print("垃圾槽为空，无需抵消")
            return 0;
        }

        // 实际可抵消的行数 = 攻击行数 × mult_defend
        int effective_damage = Mathf.Max(1, Mathf.RoundToInt(attack_damage * mult_defend));

        //print("抵消前依次上涨队列: ", _pending_rise_queue.size(), " 行")
        //print("抵消前垃圾槽: ", garbage_enter_array)
        //print("抵消前缓冲: ", garbage_buffer)
        //print("抵消倍率: ", mult_defend, "，攻击: ", attack_damage, " → 实际抵消能力: ", effective_damage)

        int remaining_damage = effective_damage;
        int offset_count = 0;

        // 优先抵消依次上涨队列中的行（逐行模式）
        int rise_offset = offset_rise_queue(remaining_damage);
        offset_count += rise_offset;
        remaining_damage -= rise_offset;

        // 再抵消正常队列（优先抵消最先进来的）
        while (remaining_damage > 0 && garbage_enter_array.Count > 0)
        {
            var entry = garbage_enter_array[0].AsGodotDictionary();
            int current = entry["count"].AsInt32();

            if (current <= remaining_damage)
            {
                // 完全抵消当前项
                remaining_damage -= current;
                offset_count += current;
                garbage_enter_array.RemoveAt(0);
                //print("完全抵消正常项: ", current, "，剩余伤害: ", remaining_damage)
            }
            else
            {
                // 部分抵消当前项
                entry["count"] = current - remaining_damage;
                offset_count += remaining_damage;
                remaining_damage = 0;
                //print("部分抵消正常项: ", current, " -> ", entry["count"])
            }
        }

        // 如果还有剩余伤害，抵消缓冲垃圾（从最早的开始）
        while (remaining_damage > 0 && garbage_buffer.Count > 0)
        {
            var buffer_entry = garbage_buffer[0].AsGodotDictionary();
            int current = buffer_entry["count"].AsInt32();

            if (current <= remaining_damage)
            {
                // 完全抵消当前缓冲项
                remaining_damage -= current;
                offset_count += current;
                garbage_buffer.RemoveAt(0);
                //print("完全抵消缓冲项: ", current, "，剩余伤害: ", remaining_damage)
            }
            else
            {
                // 部分抵消当前缓冲项
                buffer_entry["count"] = current - remaining_damage;
                offset_count += remaining_damage;
                remaining_damage = 0;
                //print("部分抵消缓冲项: ", current, " -> ", buffer_entry["count"])
            }
        }

        //print("抵消后垃圾槽: ", garbage_enter_array)
        //print("抵消后缓冲: ", garbage_buffer)
        //print("总共抵消: ", offset_count, " 行，剩余伤害: ", remaining_damage)

        // 返回实际抵消的行数
        return offset_count;
    }

    /// <summary>获取下一个垃圾行的洞口位置（从输出队列取出）</summary>
    public Godot.Collections.Array _get_next_hole_position()
    {
        // 确保输出队列有足够的元素
        _refill_garbage_output();

        // 从输出队列取出第一个
        var hole = garbage_output_array[0];
        garbage_output_array.RemoveAt(0);

        // 生成新的洞口补充到队列末尾（确保与最后一个不同）
        int last_hole_x = -1;
        if (garbage_output_array.Count > 0)
        {
            var last_entry = garbage_output_array[garbage_output_array.Count - 1].AsGodotArray();
            if (last_entry.Count > 0)
                last_hole_x = last_entry[0].AsInt32();
        }

        var garbage_rng = RandomManager.get_random("GARBAGE");
        int new_hole_x = _get_random_hole_position(garbage_rng, last_hole_x);
        var new_hole = new Godot.Collections.Array();
        new_hole.Add(new_hole_x);
        garbage_output_array.Add(new_hole);

        return hole.AsGodotArray();
    }

    /// <summary>检查是否应该更换洞口（基于garbage_messy概率）</summary>
    public bool _should_change_hole()
    {
        var garbage_rng = RandomManager.get_random("GARBAGE");
        return garbage_rng.Randf() < garbage_messy;
    }

    /// <summary>准备增长的垃圾行数据（方块锁定且无消行时调用）</summary>
    public int prepare_garbage_for_lock()
    {
        // 检查是否有正常的垃圾行（不包括缓冲中的）
        if (garbage_enter_array.Count == 0)
            return 0;

        // 计算本次要增长的垃圾行数量（最多garbage_cap行）
        int total_available = 0;
        foreach (Variant entry_v in garbage_enter_array)
            total_available += entry_v.AsGodotDictionary()["count"].AsInt32();

        int total_to_process = Mathf.Min(total_available, garbage_cap);

        if (total_to_process <= 0)
            return 0;

        // 清空待处理数据
        pending_garbage_data = new Godot.Collections.Array();
        garbage_rows_data = new Godot.Collections.Dictionary();

        int remaining_to_process = total_to_process;
        int enter_index = 0;
        var current_hole = new Godot.Collections.Array();
        bool has_current_hole = false;

        // 如果有溢出的洞口，先使用
        if (has_overflow && current_active_hole.Count > 0)
        {
            current_hole = (Godot.Collections.Array)current_active_hole.Duplicate();
            has_current_hole = true;
            has_overflow = false;
        }
        else
        {
            // 获取新的洞口
            current_hole = _get_next_hole_position();
            has_current_hole = true;
        }

        // 按garbage_enter_array的顺序处理
        while (remaining_to_process > 0 && enter_index < garbage_enter_array.Count)
        {
            var entry = garbage_enter_array[enter_index].AsGodotDictionary();
            int batch_count = entry["count"].AsInt32();
            int extra_hole_count = entry.ContainsKey("extra_hole_count") ? entry["extra_hole_count"].AsInt32() : 0;

            // 计算这一批次实际要处理的数量
            int process_count = Mathf.Min(batch_count, remaining_to_process);

            if (process_count > 0)
            {
                // 基础洞口（批次内所有行共享），每行额外挖洞独立随机生成
                var all_row_holes = new Godot.Collections.Array();
                var all_is_buffered = new Godot.Collections.Array();
                for (int _i = 0; _i < process_count; _i++)
                {
                    var row_holes = _generate_row_holes(current_hole, extra_hole_count);
                    all_row_holes.Add(row_holes);
                    all_is_buffered.Add(false);
                }

                // 记录这一批次的数据（每个单行的洞口单独存储）
                pending_garbage_data.Add(new Godot.Collections.Dictionary()
                {
                    { "count", process_count },
                    { "holes", all_row_holes },
                    { "is_buffered", false },
                    { "_per_row_holes", true },    // 标记：holes 是 Array[Array]
                });

                // 更新剩余处理数量
                remaining_to_process -= process_count;
                batch_count -= process_count;
            }

            // 如果这一批次还有剩余，更新garbage_enter_array
            if (batch_count > 0)
            {
                entry["count"] = batch_count;
            }
            else
            {
                // 这一批次已完全处理，移除
                garbage_enter_array.RemoveAt(enter_index);
                enter_index -= 1;
            }

            // 如果还有剩余要处理，判定是否换洞
            if (remaining_to_process > 0 && _should_change_hole())
            {
                current_hole = _get_next_hole_position();
            }
            else if (remaining_to_process > 0)
            {
                // 不换洞，保持当前洞口
            }

            enter_index += 1;
        }

        // 如果还有溢出的行（超过了garbage_cap），保存当前洞口用于下次
        if (total_available > total_to_process && has_current_hole)
        {
            has_overflow = true;
            current_active_hole = (Godot.Collections.Array)current_hole.Duplicate();
            //print("有溢出行，保留洞口: ", current_active_hole)
        }

        // 如果garbage_enter_array为空，重置溢出状态
        if (garbage_enter_array.Count == 0)
        {
            has_overflow = false;
            current_active_hole = new Godot.Collections.Array();
        }

        is_garbage_locked = true;

        // ##print("准备垃圾行: ", total_to_process, " 行，批次数据: ", pending_garbage_data)

        return total_to_process;
    }

    /// <summary>应用垃圾行到版面（在方块锁定且无消行后调用）</summary>
    public bool apply_garbage_to_board()
    {
        if (!is_garbage_locked || pending_garbage_data.Count == 0)
            return false;

        // 使用强制上涨来应用垃圾行
        int total_garbage_rows = 0;
        foreach (Variant batch_v in pending_garbage_data)
            total_garbage_rows += batch_v.AsGodotDictionary()["count"].AsInt32();

        // 限制总垃圾行数
        total_garbage_rows = Mathf.Min(total_garbage_rows, garbage_cap);

        if (total_garbage_rows <= 0)
        {
            is_garbage_locked = false;
            return false;
        }

        // 收集所有批次的洞口数据和缓冲状态
        var all_holes = new Godot.Collections.Array();
        var all_buffered = new Godot.Collections.Array();
        foreach (Variant batch_v in pending_garbage_data)
        {
            var batch = batch_v.AsGodotDictionary();
            int count = batch["count"].AsInt32();
            Variant holes_v = batch["holes"];
            bool is_per_row = batch.ContainsKey("_per_row_holes") && batch["_per_row_holes"].AsBool();
            bool is_buffered = batch.ContainsKey("is_buffered") && batch["is_buffered"].AsBool();
            for (int i = 0; i < count; i++)
            {
                if (is_per_row)
                    all_holes.Add(holes_v.AsGodotArray()[i]);
                else
                    all_holes.Add(holes_v);
                all_buffered.Add(is_buffered);
            }
        }

        // 使用强制上涨 + 垃圾行生成器（根据是否为缓冲决定颜色）
        RowGeneratorDelegate generator = (int i, int _total) =>
        {
            Godot.Collections.Array holes;
            if (i < all_holes.Count)
                holes = all_holes[i].AsGodotArray();
            else
            {
                holes = new Godot.Collections.Array();
                holes.Add(0);
            }
            bool is_buffered = i < all_buffered.Count && all_buffered[i].AsBool();
            var row_data = new Godot.Collections.Array();
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                bool is_hole = false;
                foreach (Variant hole_x in holes)
                {
                    if (x == hole_x.AsInt32())
                    {
                        is_hole = true;
                        break;
                    }
                }

                if (is_hole)
                {
                    if (is_buffered)
                        row_data.Add(buffered_garbage_empty_color);
                    else
                        row_data.Add(new Variant());
                }
                else
                {
                    if (is_buffered)
                        row_data.Add(buffered_garbage_color);
                    else
                        row_data.Add(garbage_color);
                }
            }
            return row_data;
        };

        // 执行强制上涨（会处理方块Y坐标同步）
        bool success = force_raise_rows(total_garbage_rows, generator);

        // 如果强制上涨成功，记录垃圾行数据
        if (success)
        {
            // 记录每行的洞口位置（从实心块上方开始数）
            int start_y = _get_new_rows_start(total_garbage_rows);
            for (int i = 0; i < total_garbage_rows; i++)
            {
                if (i < all_holes.Count)
                    garbage_rows_data[start_y + i] = all_holes[i].AsGodotArray().Duplicate();
            }
        }

        // 重置状态
        is_garbage_locked = false;
        pending_garbage_data = new Godot.Collections.Array();

        //print("垃圾行已应用，共 ", total_garbage_rows, " 行")
        return success;
    }

    /// <summary>检查某个格子是否为垃圾行</summary>
    public bool is_garbage_cell(int x, int y)
    {
        Variant color = board_drawer.get_cell_color(x, y);
        return _cell_equals(color, garbage_color) || _cell_equals(color, buffered_garbage_color);
    }

    /// <summary>检查某个格子是否为垃圾行洞口</summary>
    public bool is_garbage_hole(int x, int y)
    {
        Variant color = board_drawer.get_cell_color(x, y);
        bool is_empty_cell = color.VariantType == Variant.Type.Nil || _cell_equals(color, buffered_garbage_empty_color);
        return is_empty_cell && _is_hole_position(x, y);
    }

    /// <summary>检查某个位置是否为洞口</summary>
    public bool _is_hole_position(int x, int y)
    {
        if (!garbage_rows_data.ContainsKey(y))
            return false;
        var holes = garbage_rows_data[y].AsGodotArray();
        foreach (Variant hole_x in holes)
        {
            if (hole_x.AsInt32() == x)
                return true;
        }
        return false;
    }

    /// <summary>获取某行垃圾行的洞口位置</summary>
    public Godot.Collections.Array get_garbage_holes_for_row(int y)
    {
        if (garbage_rows_data.ContainsKey(y))
            return garbage_rows_data[y].AsGodotArray();
        return new Godot.Collections.Array();
    }

    /// <summary>检查某行是否为实心垃圾行</summary>
    public bool is_solid_garbage_row(int row_index)
    {
        return solid_garbage_rows.ContainsKey(row_index);
    }

    /// <summary>检查某个格子是否为实心垃圾行</summary>
    public bool is_solid_garbage_cell(int x, int y)
    {
        if (!solid_garbage_rows.ContainsKey(y))
            return false;
        Variant color = board_drawer.get_cell_color(x, y);
        return _cell_equals(color, solid_garbage_color);
    }

    /// <summary>清除所有实心垃圾行</summary>
    public void clear_solid_garbage()
    {
        // 从版面中清除实心垃圾行
        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            if (solid_garbage_rows.ContainsKey(y))
            {
                for (int x = 0; x < board_drawer.grid_width; x++)
                {
                    Variant color = board_drawer.get_cell_color(x, y);
                    if (_cell_equals(color, solid_garbage_color))
                        board_drawer.set_cell_color(x, y, new Variant());
                }
            }
        }
        solid_garbage_rows.Clear();
        board_drawer.QueueRedraw();
    }

    /// <summary>
    /// 方块锁定后的垃圾行处理入口（供 tetris_controller 调用）
    /// 根据 suddenly_death_mode 选择模式：
    ///   true  → 立即 prepare + apply（旧逻辑）
    ///   false → 加入依次上涨队列，逐行上涨
    /// </summary>
    public int process_garbage_after_lock()
    {
        if (garbage_enter_array.Count == 0)
            return 0;

        if (suddenly_death_mode)
        {
            // 旧模式：立即上涨
            int count = prepare_garbage_for_lock();
            if (count > 0)
            {
                bool success = apply_garbage_to_board();
                if (!success)
                    return 0;
            }
            return count;
        }
        else
        {
            // 逐行模式：加入依次上涨队列
            _move_enter_to_rise_queue();
            // 不返回 0 表示有数据进入队列
            return _pending_rise_queue.Count;
        }
    }

    /// <summary>Allspin：上涨 x 行标准垃圾行（直接插入版面，不走延迟队列，消行完成后调用）</summary>
    public void insert_allspin_garbage_directly(int row_count = 1)
    {
        if (row_count <= 0)
            return;
        var all_holes = new Godot.Collections.Array();
        for (int i = 0; i < row_count; i++)
        {
            var hole = _get_next_hole_position();
            if (hole.Count == 0)
                return;
            all_holes.Add(hole);
        }
        // 消行延迟期间：暂存起来，延迟结束后统一上涨（不丢弃行，避免在消行动画期间改动版面）
        if (is_clear_delay_active())
        {
            _deferred_direct_raises.Add(new Godot.Collections.Dictionary()
            {
                { "all_holes", all_holes },
                { "row_count", row_count },
            });
            return;
        }
        // 创建行生成器
        var gen = _generate_garbage_row_generator(all_holes[0].AsGodotArray(), false);
        // 注意：这里必须 skip_piece_handling=false（与普通垃圾上涨一致），让当前活动方块随版面同步上移。
        // 消行无延迟（clear_line_delay_time==0，默认）时，新方块已在 insert_allspin 之前生成；
        // 若用 skip=true，版面抬高但活动方块不动，方块会被“埋”在出块口，硬降/锁定即判游戏结束。
        force_raise_rows(row_count, gen, false);
    }

    /// <summary>Allspin：上涨 x 行标准垃圾行（直接推到上升队列最前面）</summary>
    public void add_allspin_garbage(int row_count = 1)
    {
        if (row_count <= 0)
            return;
        for (int i = 0; i < row_count; i++)
        {
            var hole = _get_next_hole_position();
            if (hole.Count == 0)
                return;
            _pending_rise_queue.Insert(0, new Godot.Collections.Dictionary()
            {
                { "holes", hole },
                { "is_buffered", false },
                { "color", garbage_color },
                { "empty_color", new Variant() },
            });
        }
        _start_rise_timer();
    }

    /// <summary>
    /// X宽洞口垃圾行上涨：一段连续垃圾行共享同一组【紧邻】洞口，形成 X 宽的竖直通道。
    /// 与普通“X洞”（每行独立、随机散布）不同：本函数让 row_count 行全部采用同一个
    /// 连续洞口块 [start_x, start_x+1, ..., start_x+width-1]（紧邻），位置完全相同，
    /// 上涨后呈“X宽竖直洞柱”。行加入逐行上涨队列，随 garbage_rise_time_delay 逐行上涨，
    /// 可被 offset_garbage 抵消，消行延迟期间自动暂停（复用逐行上涨机制）。
    /// 参数 width: 洞口宽度 X（连续空格列数，1 &lt;= width &lt;= grid_width）
    /// 参数 row_count: 本段垃圾行的行数（&gt;0）
    /// </summary>
    public void add_wide_hole_garbage(int width, int row_count)
    {
        if (width <= 0 || row_count <= 0)
            return;
        int grid_w = board_drawer.grid_width;
        width = Mathf.Min(width, grid_w);
        var rng = RandomManager.get_random("GARBAGE");
        // 随机选起始列，保证 X 宽洞口块完整落在版面内
        int start_x = rng.RandiRange(0, grid_w - width);
        var holes = new Godot.Collections.Array();
        for (int x = start_x; x < start_x + width; x++)
            holes.Add(x);
        // 整段行共享同一组紧邻洞口（位置完全相同）
        for (int _i = 0; _i < row_count; _i++)
        {
            _pending_rise_queue.Add(new Godot.Collections.Dictionary()
            {
                { "holes", holes.Duplicate() },
                { "is_buffered", false },
                { "color", garbage_color },
                { "empty_color", new Variant() },
            });
        }
        _start_rise_timer();
    }

    /// <summary>检查当前是否有待处理的垃圾行</summary>
    public bool has_pending_garbage()
    {
        return is_garbage_locked || pending_garbage_data.Count > 0;
    }

    /// <summary>获取待处理的垃圾行数量</summary>
    public int get_pending_garbage_count()
    {
        int total = 0;
        foreach (Variant batch_v in pending_garbage_data)
            total += batch_v.AsGodotDictionary()["count"].AsInt32();
        return total;
    }

    // ========== 逐行上涨系统 ==========

    /// <summary>
    /// 将垃圾行数据拆分为单行，加入依次上涨队列
    /// 在 suddenly_death_mode=false 时由 process_garbage_after_lock 调用
    /// </summary>
    public int _move_enter_to_rise_queue()
    {
        if (garbage_enter_array.Count == 0)
            return 0;

        int total_available = 0;
        foreach (Variant entry_v in garbage_enter_array)
            total_available += entry_v.AsGodotDictionary()["count"].AsInt32();

        // 限流（每次锁定最多新增 garbage_cap 行，保留尚未上涨完的旧行，避免丢失）
        int total_rows = Mathf.Min(total_available, garbage_cap);

        int remaining = total_rows;
        int enter_index = 0;
        var current_hole = new Godot.Collections.Array();
        bool has_current_hole = false;

        // 如果有溢出的洞口，先使用
        if (has_overflow && current_active_hole.Count > 0)
        {
            current_hole = (Godot.Collections.Array)current_active_hole.Duplicate();
            has_current_hole = true;
            has_overflow = false;
        }
        else
        {
            current_hole = _get_next_hole_position();
            has_current_hole = true;
        }

        while (remaining > 0 && enter_index < garbage_enter_array.Count)
        {
            var entry = garbage_enter_array[enter_index].AsGodotDictionary();
            int batch_count = entry["count"].AsInt32();
            int extra_hole_count = entry.ContainsKey("extra_hole_count") ? entry["extra_hole_count"].AsInt32() : 0;
            int process_count = Mathf.Min(batch_count, remaining);

            for (int _i = 0; _i < process_count; _i++)
            {
                // 每行独立生成额外挖洞
                var row_holes = _generate_row_holes(current_hole, extra_hole_count);
                _pending_rise_queue.Add(new Godot.Collections.Dictionary()
                {
                    { "holes", row_holes },
                    { "is_buffered", false },
                    { "color", garbage_color },
                    { "empty_color", new Variant() },
                });
            }

            remaining -= process_count;
            batch_count -= process_count;

            if (batch_count > 0)
            {
                entry["count"] = batch_count;
            }
            else
            {
                garbage_enter_array.RemoveAt(enter_index);
                enter_index -= 1;
            }

            if (remaining > 0 && _should_change_hole())
                current_hole = _get_next_hole_position();

            enter_index += 1;
        }

        if (total_available > total_rows && has_current_hole)
        {
            has_overflow = true;
            current_active_hole = (Godot.Collections.Array)current_hole.Duplicate();
        }
        if (garbage_enter_array.Count == 0)
        {
            has_overflow = false;
            current_active_hole = new Godot.Collections.Array();
        }

        //print("逐行上涨队列已填充: %d 行" % _pending_rise_queue.size())
        _start_rise_timer();
        return _pending_rise_queue.Count;
    }

    /// <summary>
    /// 是否正处于消行延迟中（消行动画期间不得改动版面：待消行仍物理存在，
    /// 此时上涨垃圾会使待消行上移，导致延迟结束后 _pending_clear_lines 索引错位等 bug）
    /// </summary>
    public bool is_clear_delay_active()
    {
        if (clear_line_controller != null)
            return clear_line_controller.is_clear_animating_active();
        return false;
    }

    /// <summary>
    /// 启动逐行上涨计时器
    /// 仅当计时器未运行时才启动：Godot 的 Timer.start() 在已运行时调用会重置剩余时间，
    /// 若上涨队列已有行正在逐行上涨，新垃圾入队（_move_enter_to_rise_queue /
    /// add_allspin_garbage）会反复重置计时，导致已排队行的上涨被打断/无限推迟。
    /// </summary>
    public void _start_rise_timer()
    {
        if (_rise_timer == null)
            return;
        if (_pending_rise_queue.Count == 0)
            return;
        if (_rise_timer.IsStopped())
        {
            _rise_timer.WaitTime = garbage_rise_time_delay;
            _rise_timer.Start();
        }
    }

    /// <summary>停止逐行上涨计时器</summary>
    public void _stop_rise_timer()
    {
        if (_rise_timer != null)
            _rise_timer.Stop();
    }

    /// <summary>计时器触发：上涨一行</summary>
    public void _on_rise_timer_timeout()
    {
        if (_pending_rise_queue.Count == 0)
        {
            _stop_rise_timer();
            return;
        }

        // 消行延迟期间暂停逐行上涨：不清除队列、不丢弃行，延迟结束后恢复继续上涨
        if (is_clear_delay_active())
        {
            _stop_rise_timer();
            return;
        }

        // 取出队列最前面的一行
        var row_entry = _pending_rise_queue[0].AsGodotDictionary();
        _pending_rise_queue.RemoveAt(0);
        var holes = row_entry["holes"].AsGodotArray();
        bool _is_buffered = row_entry.ContainsKey("is_buffered") && row_entry["is_buffered"].AsBool();

        // 生成单行垃圾
        RowGeneratorDelegate generator = (int _i, int _total) =>
        {
            var row_data = new Godot.Collections.Array();
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                bool is_hole = false;
                foreach (Variant hx in holes)
                {
                    if (x == hx.AsInt32())
                    {
                        is_hole = true;
                        break;
                    }
                }
                if (is_hole)
                    row_data.Add(new Variant());
                else
                    row_data.Add(garbage_color);
            }
            return row_data;
        };

        bool success = force_raise_rows(1, generator);
        if (!success)
        {
            _stop_rise_timer();
            _pending_rise_queue.Clear();
            return;
        }

        int start_y = _get_new_rows_start(1);
        garbage_rows_data[start_y] = holes.Duplicate();

        // 继续计时
        if (_pending_rise_queue.Count > 0)
            _rise_timer.Start();
        else
            _stop_rise_timer();
    }

    /// <summary>
    /// 消行延迟结束后恢复待上涨的垃圾行（由 TetrisClearLine 在消行延迟计时结束时调用）。
    /// 先执行延迟期间暂存的一次性直接上涨，再恢复逐行上涨计时器。
    /// </summary>
    public void resume_rise_if_pending()
    {
        // 执行延迟期间暂存的实心垃圾行上涨（不丢弃行）
        if (_deferred_solid_raises.Count > 0)
        {
            foreach (Variant count_v in _deferred_solid_raises)
                add_solid_garbage(count_v.AsInt32());
            _deferred_solid_raises.Clear();
        }
        // 执行延迟期间暂存的一次性直接上涨（如 Allspin 直接上涨）
        if (_deferred_direct_raises.Count > 0)
        {
            foreach (Variant deferred_v in _deferred_direct_raises)
            {
                var deferred = deferred_v.AsGodotDictionary();
                var holes = deferred["all_holes"].AsGodotArray();
                int count = deferred["row_count"].AsInt32();
                if (holes.Count == 0)
                    continue;
                var gen = _generate_garbage_row_generator(holes[0].AsGodotArray(), false);
                force_raise_rows(count, gen, true);
            }
            _deferred_direct_raises.Clear();
        }
        // 恢复逐行上涨
        if (_pending_rise_queue.Count > 0 && _rise_timer != null && _rise_timer.IsStopped())
        {
            _rise_timer.WaitTime = garbage_rise_time_delay;
            _rise_timer.Start();
        }
    }

    /// <summary>抵消依次上涨队列中的行（优先于 enter_array 和 buffer）</summary>
    /// <returns>被抵消的行数</returns>
    public int offset_rise_queue(int remaining_damage)
    {
        if (remaining_damage <= 0 || _pending_rise_queue.Count == 0)
            return 0;

        int offset_count = 0;
        while (remaining_damage > 0 && _pending_rise_queue.Count > 0)
        {
            _pending_rise_queue.RemoveAt(0);
            offset_count += 1;
            remaining_damage -= 1;
        }

        // 如果队列空了就停止计时
        if (_pending_rise_queue.Count == 0)
            _stop_rise_timer();

        return offset_count;
    }

    /// <summary>获取进入队列的大小（总行数，包括缓冲和逐行上涨队列）</summary>
    public int get_enter_queue_size()
    {
        int total = 0;
        foreach (Variant entry_v in garbage_enter_array)
            total += entry_v.AsGodotDictionary()["count"].AsInt32();
        foreach (Variant entry_v in garbage_buffer)
            total += entry_v.AsGodotDictionary()["count"].AsInt32();
        // 逐行模式下上涨队列中的行也是待处理垃圾行，必须计入
        total += _pending_rise_queue.Count;
        return total;
    }

    /// <summary>
    /// 获取进入队列的原始数据（只返回正常队列）
    /// 返回 [{count: int, extra_hole_count: int}, ...]
    /// </summary>
    public Godot.Collections.Array get_enter_queue()
    {
        return (Godot.Collections.Array)garbage_enter_array.Duplicate();
    }

    /// <summary>获取缓冲队列的原始数据</summary>
    public Godot.Collections.Array get_buffer_queue()
    {
        return (Godot.Collections.Array)garbage_buffer.Duplicate();
    }

    /// <summary>清除所有垃圾行数据</summary>
    public void clear_all()
    {
        garbage_enter_array.Clear();
        garbage_output_array.Clear();
        garbage_buffer.Clear();
        pending_garbage_data = new Godot.Collections.Array();
        is_garbage_locked = false;
        garbage_rows_data.Clear();
        solid_garbage_rows.Clear();
        has_overflow = false;
        current_active_hole = new Godot.Collections.Array();
        _pending_rise_queue.Clear();
        _deferred_direct_raises.Clear();
        _deferred_solid_raises.Clear();
        _stop_rise_timer();
        _refill_garbage_output();
    }

    /// <summary>清空版面中的垃圾行</summary>
    public void clear_garbage_from_board()
    {
        for (int y = 0; y < board_drawer.get_playable_height(); y++)
        {
            for (int x = 0; x < board_drawer.grid_width; x++)
            {
                Variant color = board_drawer.get_cell_color(x, y);
                if (_cell_equals(color, garbage_color) || _cell_equals(color, garbage_empty_color)
                    || _cell_equals(color, solid_garbage_color) || _cell_equals(color, buffered_garbage_color)
                    || _cell_equals(color, buffered_garbage_empty_color))
                {
                    board_drawer.set_cell_color(x, y, new Variant());
                }
            }
        }
        garbage_rows_data.Clear();
        solid_garbage_rows.Clear();
        board_drawer.QueueRedraw();
    }

    /// <summary>重置整个垃圾行系统</summary>
    public void reset_system()
    {
        clear_all();
        clear_garbage_from_board();
    }

    /// <summary>
    /// 判断版面格子颜色 Variant 是否等于指定 Color。
    /// 对应 GDScript 中 `cell_color == color` 的判定：空格子（Nil）或非 Color 值一律不等。
    /// </summary>
    private static bool _cell_equals(Variant cell, Color color)
    {
        return cell.VariantType == Variant.Type.Color && cell.AsColor() == color;
    }

    // ---- 调试辅助（确定性测试用；不影响玩法逻辑）----

    /// <summary>清空垃圾行输出队列并按垃圾配置重新填充（配合固定种子做确定性对比）</summary>
    public void debug_reset_garbage()
    {
        garbage_output_array.Clear();
        _refill_garbage_output();
    }
}
