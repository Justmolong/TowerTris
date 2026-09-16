using Godot;
using System;

/// <summary>
/// 俄罗斯方块版面绘制器
/// 提供网格绘制功能，支持自定义基准点、格子大小、网格尺寸
/// </summary>
public partial class TetrisBoardDrawer : Node2D
{
    [Export]
    public TetrisClearLine clear_line_controller;
    [Export]
    public TetrisGarbageLineController garbage_line_controller;
    [Export]
    public TetrisController tetris_controller;
    [Export]
    public TowerController tower_controller;      // 塔控制器引用（用于读取高度/速度）

    // 网格配置
    [Export]
    public int grid_width = 10;        // 网格宽度（列数）
    [Export]
    public int grid_height = 20;       // 网格高度（行数）- 实际可见高度
    [Export]
    public int above_visible_rows = 70; // 可见区域上方预留行数（用于垃圾槽扩展，不绘制背景和网格线）
    [Export]
    public int grid_max_height = 100;   // 网格最大高度（行数）- 用于垃圾槽和扩展
    [Export]
    public int cell_size = 24;         // 格子边长（像素）
    [Export]
    public int offset_x = 0;           // 基准点X偏移（左上角X坐标）- 通常由自动居中覆盖
    [Export]
    public int offset_y = 0;           // 基准点Y偏移（左上角Y坐标）- 通常由自动居中覆盖

    // 显示配置
    [Export]
    public bool auto_center = true;    // 是否自动居中版面
    [Export]
    public bool auto_resize = true;    // 是否自动适应窗口大小
    [Export]
    public float margin_percentage = 0.1f;  // 边距百分比（相对窗口较小边）

    // 颜色配置
    [Export]
    public Color background_color = new Color(0, 0, 0, 1.0f);     // 背景色
    [Export]
    public Color grid_line_color = new Color(0.399f, 0.399f, 0.399f, 1.0f);      // 网格线颜色
    [Export]
    public float grid_line_width = 1.0f;              // 网格线宽度
    [Export]
    public Color board_border_color = Colors.White;   // 版面左右边缘边框颜色
    [Export]
    public float board_border_width = 2.0f;           // 版面左右边缘边框宽度

    // 影子方块配置
    [Export]
    public bool shadow_enabled = true;               // 是否启用影子显示
    [Export]
    public float shadow_opacity = 0.55f;               // 影子透明度（0-1）
    [Export]
    public float shadow_border_opacity = 0.75f;        // 影子边框透明度（0-1）

    // 垃圾槽配置
    [Export]
    public bool garbage_slot_enabled = true;         // 是否启用垃圾槽
    [Export]
    public int garbage_slot_width = 1;               // 垃圾槽宽度（格子数）
    [Export]
    public Color garbage_slot_border_color = Colors.White;  // 垃圾槽边框颜色
    [Export]
    public float garbage_slot_border_width = 2.0f;    // 垃圾槽边框宽度（与版面边框一致，保证左右两侧粗细相同）
    public int garbage_cap;
    [Export]
    public Color garbage_cap_line_color = Colors.White;  // 垃圾槽横线颜色
    [Export]
    public Color garbage_bar_color = new Color(1.0f, 0.0f, 0.0f, 1.0f);      // 垃圾行矩形颜色
    [Export]
    public Color garbage_bar_separator_color = Colors.Black;  // 垃圾行分割线颜色
    [Export]
    public float garbage_bar_separator_width = 1.0f;  // 分割线宽度
    [Export]
    public float garbage_bar_padding = 0.1f;          // 垃圾矩形内边距（相对于格子大小的比例）

    // 统计信息配置
    [Export]
    public bool stats_display_enabled = true;        // 是否启用统计信息显示
    [Export]
    public Color stats_text_color = Colors.White;     // 统计信息文字颜色
    [Export]
    public Color stats_text_outline_color = Colors.Black;  // 统计信息文字描边颜色
    [Export]
    public float stats_font_size_ratio = 0.7f;        // 统计信息字体大小比例（相对于cell_size）
    [Export]
    public float stats_spacing_cells = 1;          // 统计信息行间距（格子数）
    [Export]
    public float stats_offset_x_cells = -5;      // 统计信息相对垃圾槽左侧的X偏移（格子数，负值向左）
    [Export]
    public float stats_offset_y_cells = 0;         // 统计信息相对版面底部的Y偏移（格子数，正值向上）

    // 高度显示配置
    [Export]
    public bool height_display_enabled = true;       // 是否启用高度显示
    [Export]
    public Color height_text_color = Colors.White;    // 高度文字颜色
    [Export]
    public Color height_text_outline_color = Colors.Black;  // 高度文字描边颜色
    [Export]
    public float height_font_size_ratio = 0.5f;       // 高度字体大小比例（相对于cell_size）
    [Export]
    public float height_display_offset_y_cells = 0.5f;   // 高度显示相对版面的Y偏移（格子数，正值向下）

    // 阶段进度条配置
    [Export]
    public bool stage_progress_bar_enabled = true;       // 是否启用阶段进度条
    [Export]
    public float stage_progress_bar_width_cells = 8.0f;   // 进度条宽度（格子数）
    [Export]
    public float stage_progress_bar_height_cells = 0.4f;  // 进度条高度（格子数）
    [Export]
    public Color stage_progress_bar_border_color = Colors.White;     // 进度条边框颜色
    [Export]
    public Color stage_progress_bar_fill_color = new Color(0.2f, 0.6f, 1.0f, 1.0f);  // 进度条填充颜色（蓝色）
    [Export]
    public Color stage_progress_bar_bg_color = new Color(0.2f, 0.2f, 0.2f, 0.6f);    // 进度条背景颜色

    // Hold方块显示配置
    [Export]
    public bool hold_display_enabled = true;         // 是否启用Hold显示
    public bool no_hold = false;                             // NoHold模式：关闭Hold显示（由TowerController转发）
    [Export]
    public int hold_display_offset_cells = -5;       // Hold框相对版面的X偏移（以格子数为单位，负值在左侧）
    [Export]
    public int hold_display_offset_y_cells = 0;      // Hold框相对版面的Y偏移（以格子数为单位）
    [Export]
    public int hold_display_width = 4;               // Hold显示区域的格子宽度
    [Export]
    public int hold_display_height = 4;              // Hold显示区域的格子高度
    [Export]
    public Color hold_background_color = new Color(0.1f, 0.1f, 0.1f, 1.0f);  // Hold框背景色
    [Export]
    public Color hold_border_color = Colors.White;    // Hold框边框颜色
    [Export]
    public float hold_border_width = 2.0f;            // Hold框边框宽度
    [Export]
    public float hold_padding = 0.2f;                 // Hold框内边距（相对于格子大小的比例）

    // Next方块显示配置
    [Export]
    public bool next_display_enabled = true;         // 是否启用Next显示
    [Export]
    public int next_display_offset_cells = 10;       // Next框相对版面的X偏移（以格子数为单位，正值在右侧）
    [Export]
    public int next_display_offset_y_cells = 0;      // Next框相对版面的Y偏移（以格子数为单位）
    [Export]
    public int next_display_width = 4;               // 每个Next显示区域的格子宽度
    [Export]
    public int next_display_height = 3;              // 每个Next显示区域的格子高度
    [Export(PropertyHint.Range, "1,7")]
    public int next_count = 6;          // 显示Next方块的数量（1-7）
    [Export]
    public int next_spacing_cells = 0;               // Next方块之间的间距（以格子数为单位）
    [Export]
    public Color next_background_color = new Color(0.1f, 0.1f, 0.1f, 1.0f);  // Next框背景色
    [Export]
    public Color next_border_color = Colors.White;    // Next框边框颜色
    [Export]
    public float next_border_width = 1.0f;            // Next框边框宽度
    [Export]
    public float next_padding = 0.15f;                // Next框内边距（相对于格子大小的比例）
    [Export]
    public string next_label_text = "NEXT";          // Next标签文字
    [Export]
    public Color next_label_color = Colors.White;     // Next标签颜色

    // 外部数据引用
    public Godot.Collections.Array board_data = new Godot.Collections.Array();               // 版面数据（用于存储每个格子的颜色/类型）
    public bool show_grid_lines = true;         // 是否显示网格线

    // 正在播放消行动画的行（行号，用于闪烁高亮提示）
    public Godot.Collections.Array clearing_lines = new Godot.Collections.Array();

    // Hold方块数据
    public Godot.Collections.Array hold_piece_data = new Godot.Collections.Array();          // 暂存的方块矩阵
    public Color hold_piece_color = Colors.White;  // 暂存的方块颜色

    // Next方块数据
    public Godot.Collections.Array next_pieces_data = new Godot.Collections.Array();         // Next方块数据列表 [{shape: Array, color: Color}]

    // 影子方块数据（由TetrisController计算后提供）
    public Godot.Collections.Array shadow_piece = new Godot.Collections.Array();             // 影子的形状矩阵
    public Vector2I shadow_position = Vector2I.Zero;  // 影子的位置（已经计算好的硬降位置）
    public Color current_piece_color = Colors.White;  // 当前方块颜色（用于影子颜色）

    // Bot 决策预览（已转换为游戏棋盘坐标）：[{ "cells": [[gx,gy]x4], "color": Color }, ...]
    // 由 TetrisController 每帧从 ColdClearBridge.cc_plan_placements 转换后同步写入，
    // 以约 30% 透明度的对应方块颜色叠加绘制，展示 bot 的落块决策。
    public Godot.Collections.Array bot_plan_placements = new Godot.Collections.Array();

    // 统计数据（由外部更新）
    public float pps_value = 0.0f;               // 每秒方块数
    public float apm_value = 0.0f;               // 每分钟攻击数
    public float rpm_value = 0.0f;               // 每分钟接收攻击数

    // 大攻击警告状态
    public bool big_attack_warning_active = false;
    public float big_attack_warning_progress = 0.0f;  // 0→1 渐变进度

    // 游戏结束状态
    public bool is_game_over = false;

    // 窗口尺寸追踪
    public Vector2 last_viewport_size = Vector2.Zero;

    public int tetris_invisible = 0;                       // 0=关闭, 1=开启（放置的方块隐藏，垃圾行正常显示）
    public float visible_time_between = 10;                 // 隐藏间隔时间（秒），每隔多久显示一次方块
    public float visible_show_time = 1;                    // 显示持续时间（秒），方块显示多久后再次隐藏
    public float drop_visible_time = 1;                    // 方块落下后渐变透明的耗时（秒），0=立即隐形

    // 隐藏模式状态
    public bool _is_visible_mode = true;                   // true=正在显示方块, false=方块隐藏
    public Timer _invisible_timer = null;                  // 隐藏模式计时器

    // 每个格子锁定的时间戳（用于drop_visible_time渐隐），0表示未锁定
    public Godot.Collections.Array _cell_lock_times = new Godot.Collections.Array();                    // 与board_data同维度，存储Time.get_ticks_msec()

    public override void _Ready()
    {
        _get_find_controller();
        _init_board_data();
        _update_board_position();

        // 连接窗口大小变化信号
        GetTree().Root.SizeChanged += _on_window_resized;

        // 连接大攻击警告信号
        if (tower_controller != null)
        {
            tower_controller.BigAttackWarningStarted += _on_big_attack_warning_started;
            tower_controller.BigAttackWarningEnded += _on_big_attack_warning_ended;
        }

        // 初始化隐藏模式
        _init_invisible_mode();
    }

    public override void _Process(double _delta)
    {
        // 检查窗口是否被拉伸
        if (auto_resize && GetViewportRect().Size != last_viewport_size)
        {
            _on_window_resized();
        }

        // 更新大攻击警告渐变进度
        if (big_attack_warning_active && tower_controller != null)
        {
            Timer timer = tower_controller.big_attack_delay_timer;
            if (timer != null && timer.WaitTime > 0)
            {
                big_attack_warning_progress = 1.0f - (float)(timer.TimeLeft / timer.WaitTime);
                QueueRedraw();
            }
        }
    }

    /// <summary>初始化隐藏模式（tetris_invisible）</summary>
    public void _init_invisible_mode()
    {
        if (tetris_invisible == 0)
        {
            _is_visible_mode = true;
            // 如果已有计时器则停止并移除
            if (_invisible_timer != null)
            {
                _invisible_timer.Stop();
                _invisible_timer.QueueFree();
                _invisible_timer = null;
            }
            return;
        }

        // tetris_invisible == 1：初始为隐藏状态
        _is_visible_mode = false;

        // 如果计时器已存在，直接重置
        if (_invisible_timer != null)
        {
            _invisible_timer.Stop();
            _invisible_timer.WaitTime = visible_time_between;
            _invisible_timer.Start();
            return;
        }

        // 创建并启动计时器
        _invisible_timer = new Timer();
        _invisible_timer.OneShot = true;
        _invisible_timer.Timeout += _on_invisible_timer_timeout;
        AddChild(_invisible_timer);
        _invisible_timer.WaitTime = visible_time_between;
        _invisible_timer.Start();
    }

    /// <summary>隐藏模式计时器回调：切换显示/隐藏状态</summary>
    public void _on_invisible_timer_timeout()
    {
        if (tetris_invisible == 0)
        {
            return;
        }

        if (_is_visible_mode)
        {
            // 当前在显示阶段 → 切换到隐藏，等待 visible_time_between 秒后再次显示
            _is_visible_mode = false;
            _invisible_timer.WaitTime = visible_time_between;
        }
        else
        {
            // 当前在隐藏阶段 → 切换到显示，持续 visible_show_time 秒后隐藏
            _is_visible_mode = true;
            _invisible_timer.WaitTime = visible_show_time;
        }

        _invisible_timer.Start();
        QueueRedraw();
    }

    public void _get_find_controller()
    {
        // 自动查找tetris_controller（如果未设置）
        if (tetris_controller == null)
        {
            tetris_controller = GetNodeOrNull<TetrisController>("../TetrisController");
        }

        // 自动查找tower_controller（如果未设置）
        if (tower_controller == null)
        {
            tower_controller = GetNodeOrNull<TowerController>("../../TowerController");
        }
    }

    /// <summary>初始化版面数据</summary>
    public void _init_board_data()
    {
        if (garbage_line_controller != null)
        {
            garbage_cap = garbage_line_controller.garbage_cap;
        }

        board_data.Clear();
        _cell_lock_times.Clear();
        for (int y = 0; y < grid_max_height; y++)
        {
            Godot.Collections.Array row = new Godot.Collections.Array();
            Godot.Collections.Array time_row = new Godot.Collections.Array();
            for (int x = 0; x < grid_width; x++)
            {
                row.Add(new Variant());  // null 表示空格子
                time_row.Add(0);  // 0 表示未锁定
            }
            board_data.Add(row);
            _cell_lock_times.Add(time_row);
        }
    }

    /// <summary>更新版面位置和大小（自动居中）</summary>
    public void _update_board_position()
    {
        if (!auto_center)
        {
            return;
        }

        Vector2 viewport_size = GetViewportRect().Size;
        int board_width = grid_width * cell_size;
        int board_height = grid_height * cell_size;  // 使用可见高度计算显示尺寸

        // 计算居中位置
        offset_x = (int)((viewport_size.X - board_width) / 2);
        offset_y = (int)((viewport_size.Y - board_height) / 2);

        // 应用边距（如果需要）
        if (auto_resize)
        {
            float margin = Mathf.Min(viewport_size.X, viewport_size.Y) * margin_percentage;
            offset_x = (int)Mathf.Max((float)offset_x, margin);
            offset_y = (int)Mathf.Max((float)offset_y, margin);
        }

        QueueRedraw();
    }

    /// <summary>自动调整格子大小以适配窗口</summary>
    public void _auto_adjust_cell_size()
    {
        if (!auto_resize)
        {
            return;
        }

        Vector2 viewport_size = GetViewportRect().Size;

        // 预留边距空间
        float margin = Mathf.Min(viewport_size.X, viewport_size.Y) * margin_percentage;
        float available_width = viewport_size.X - margin * 2;
        float available_height = viewport_size.Y - margin * 2;

        // 计算理论格子大小（使用可见高度）
        float cell_size_by_width = available_width / grid_width;
        float cell_size_by_height = available_height / grid_height;

        // 取最小值以保证完整显示
        float new_cell_size = Mathf.Min(cell_size_by_width, cell_size_by_height);

        // 限制最小和最大格子大小（可选）
        new_cell_size = Mathf.Clamp(new_cell_size, 16.0f, 64.0f);

        // 只有变化时才更新
        if (Mathf.Abs(new_cell_size - cell_size) > 0.1f)
        {
            cell_size = (int)new_cell_size;
            _update_board_position();
            QueueRedraw();
        }
    }

    /// <summary>窗口大小改变时的回调</summary>
    public void _on_window_resized()
    {
        last_viewport_size = GetViewportRect().Size;

        if (auto_resize)
        {
            _auto_adjust_cell_size();
        }
        else if (auto_center)
        {
            _update_board_position();
        }

        QueueRedraw();
    }

    /// <summary>设置某个格子的颜色</summary>
    public void set_cell_color(int x, int y, Variant color)
    {
        // 如果颜色为null，设置为null表示空格
        if (color.VariantType == Variant.Type.Nil)
        {
            // 已经是 null（空格），保持不变
        }
        else if (color.VariantType == Variant.Type.Color && color.AsColor() == Colors.Black)
        {
            color = new Variant();  // 黑色视为空格
        }
        else if (color.VariantType != Variant.Type.Color)
        {
            color = new Variant();  // 非颜色类型视为空格
        }

        if (_is_valid_position(x, y))
        {
            board_data[y].AsGodotArray()[x] = color;
            // 记录锁定时间（非空格、非垃圾行）
            if (color.VariantType != Variant.Type.Nil && !_is_garbage_color(color.AsColor()))
            {
                _cell_lock_times[y].AsGodotArray()[x] = (long)Time.GetTicksMsec();
            }
            else if (color.VariantType == Variant.Type.Nil)
            {
                _cell_lock_times[y].AsGodotArray()[x] = 0;
            }
            QueueRedraw();  // 请求重绘
        }
    }

    /// <summary>获取某个格子的颜色</summary>
    public Variant get_cell_color(int x, int y)
    {
        if (_is_valid_position(x, y))
        {
            return board_data[y].AsGodotArray()[x];
        }
        return new Variant();
    }

    /// <summary>清除所有格子</summary>
    public void clear_board()
    {
        _init_board_data();
        QueueRedraw();
    }

    /// <summary>检查坐标是否有效（使用最大高度）</summary>
    public bool _is_valid_position(int x, int y)
    {
        return x >= 0 && x < grid_width && y >= 0 && y < grid_max_height;
    }

    /// <summary>获取完整可玩行数（含上方出块区域）</summary>
    public int get_playable_height()
    {
        return grid_height + above_visible_rows;
    }

    /// <summary>将网格坐标转换为世界坐标（格子左上角）
    /// y为数据行索引，减去above_visible_rows后映射到可见区域</summary>
    public Vector2 cell_to_world(int x, int y)
    {
        return new Vector2(offset_x + x * cell_size, offset_y + (y - above_visible_rows) * cell_size);
    }

    /// <summary>将世界坐标转换为网格坐标（返回数据行索引）</summary>
    public Vector2I world_to_cell(Vector2 world_pos)
    {
        float local_x = world_pos.X - offset_x;
        float local_y = world_pos.Y - offset_y;
        float cell_x = Mathf.Floor(local_x / cell_size);
        float cell_y = Mathf.Floor(local_y / cell_size) + above_visible_rows;
        return new Vector2I((int)cell_x, (int)cell_y);
    }

    // ========== 影子方块系统 ==========

    /// <summary>更新影子方块数据（由TetrisController调用）</summary>
    public void update_shadow(Godot.Collections.Array piece, Vector2I piece_position)
    {
        update_shadow(piece, piece_position, Colors.White);
    }

    public void update_shadow(Godot.Collections.Array piece, Vector2I piece_position, Color piece_color)
    {
        if (piece.Count == 0)
        {
            shadow_piece = new Godot.Collections.Array();
            shadow_position = Vector2I.Zero;
        }
        else
        {
            shadow_piece = piece;
            shadow_position = piece_position;
            current_piece_color = piece_color;
        }
        QueueRedraw();
    }

    /// <summary>清除影子</summary>
    public void clear_shadow()
    {
        shadow_piece = new Godot.Collections.Array();
        shadow_position = Vector2I.Zero;
        QueueRedraw();
    }

    /// <summary>检查某个位置是否被当前方块占据</summary>
    public bool _is_occupied_by_current_piece(int board_x, int board_y)
    {
        if (tetris_controller == null)
        {
            return false;
        }

        Godot.Collections.Array current_piece = tetris_controller.current_piece;
        Vector2I current_pos = tetris_controller.current_position;

        if (current_piece.Count == 0)
        {
            return false;
        }

        for (int y = 0; y < current_piece.Count; y++)
        {
            Godot.Collections.Array piece_row = current_piece[y].AsGodotArray();
            for (int x = 0; x < piece_row.Count; x++)
            {
                if ((long)piece_row[x] == 1L)
                {
                    int px = current_pos.X + x;
                    int py = current_pos.Y + y;
                    if (px == board_x && py == board_y)
                    {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// <summary>获取影子颜色（当前方块颜色叠加透明度）</summary>
    public Color _get_shadow_color()
    {
        if (current_piece_color == Colors.White)
        {
            // 如果没有当前方块颜色，使用默认深灰色
            return new Color(0.3f, 0.3f, 0.3f, shadow_opacity);
        }

        Color shadow_color = current_piece_color;
        shadow_color.A = shadow_opacity;
        return shadow_color;
    }

    /// <summary>获取影子边框颜色</summary>
    public Color _get_shadow_border_color()
    {
        if (current_piece_color == Colors.White)
        {
            return new Color(0.5f, 0.5f, 0.5f, shadow_border_opacity);
        }

        Color border_color = current_piece_color;
        border_color.A = shadow_border_opacity;
        return border_color;
    }

    /// <summary>绘制影子方块（不绘制与当前方块重叠的部分）
    /// bot 模式且计划预览活动时跳过：预览的 plan[0] 已经显示当前块的落点，影子会与其
    /// 重叠造成干扰（且 bot 不需要玩家用的影子提示）。</summary>
    public void _draw_shadow()
    {
        if (!shadow_enabled)
        {
            return;
        }

        if (bot_plan_placements.Count != 0)
        {
            return;
        }

        if (shadow_piece.Count == 0)
        {
            return;
        }

        Color shadow_color = _get_shadow_color();
        Color shadow_border_color = _get_shadow_border_color();

        // 遍历影子的每个格子
        for (int y = 0; y < shadow_piece.Count; y++)
        {
            Godot.Collections.Array piece_row = shadow_piece[y].AsGodotArray();
            for (int x = 0; x < piece_row.Count; x++)
            {
                if ((long)piece_row[x] == 1L)
                {
                    int board_x = shadow_position.X + x;
                    int board_y = shadow_position.Y + y;

                    // 只绘制在可见区域（含上方出块区域）内的影子
                    if (board_x < 0 || board_x >= grid_width || board_y < 0 || board_y >= grid_height + above_visible_rows)
                    {
                        continue;
                    }

                    // 检查该位置是否被当前方块占据（本体与影子重叠）
                    if (_is_occupied_by_current_piece(board_x, board_y))
                    {
                        continue;
                    }

                    // 检查该位置是否被其他已锁定的方块占据
                    if (board_data[board_y].AsGodotArray()[board_x].VariantType != Variant.Type.Nil)
                    {
                        continue;
                    }

                    // 绘制影子格子
                    Rect2 cell_rect = new Rect2(cell_to_world(board_x, board_y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, shadow_color, true);
                    // 绘制影子边框
                    DrawRect(cell_rect, shadow_border_color, false, 1.0f);
                }
            }
        }
    }

    // ========== Bot 决策预览 ==========

    /// <summary>bot 决策预览：当前块（plan[0]）的填充不透明度（0..1）。50% 起。</summary>
    [Export]
    public float bot_plan_opacity_start = 0.5f;
    /// <summary>bot 决策预览：每个下一块的不透明度递减量（0..1）。暂设为 0 = 无渐变，所有块同不透明度。</summary>
    [Export]
    public float bot_plan_opacity_step = 0.0f;
    /// <summary>bot 决策预览：不透明度下限（避免后续块完全不可见）。</summary>
    [Export]
    public float bot_plan_opacity_min = 0.08f;

    /// <summary>设置 bot 落块决策预览（placements 已转换为游戏棋盘坐标，cells 为 [x,y] 对，y 向下）</summary>
    public void set_bot_plan(Godot.Collections.Array placements)
    {
        if (_arrays_equal(bot_plan_placements, placements))
        {
            return;
        }
        bot_plan_placements = placements;
        QueueRedraw();
    }

    /// <summary>清除 bot 落块决策预览</summary>
    public void clear_bot_plan()
    {
        if (bot_plan_placements.Count == 0)
        {
            return;
        }
        bot_plan_placements = new Godot.Collections.Array();
        QueueRedraw();
    }

    /// <summary>绘制 bot 决策预览：对规划中每个落块，用其方块颜色按索引递减不透明度填充格子
    /// （plan[0]=当前块 最实，其后每块递减 bot_plan_opacity_step），
    /// 再用略高透明度的同色描边勾出轮廓，直观展示 bot 的落点规划序列。</summary>
    public void _draw_bot_plan()
    {
        if (bot_plan_placements.Count == 0)
        {
            return;
        }
        int playable = grid_height + above_visible_rows;
        int idx = 0;
        foreach (Variant pl in bot_plan_placements)
        {
            if (pl.VariantType != Variant.Type.Dictionary)
            {
                idx += 1;
                continue;
            }
            // 当前块(plan[0])用 bot_plan_opacity_start，之后每块递减 step，且不低于下限
            float alpha = Mathf.Max(bot_plan_opacity_start - idx * bot_plan_opacity_step, bot_plan_opacity_min);
            Godot.Collections.Dictionary plDict = pl.AsGodotDictionary();
            Color color = plDict.ContainsKey("color") ? plDict["color"].AsColor() : Colors.White;
            Color fill = new Color(color.R, color.G, color.B, alpha);
            Color border = new Color(color.R, color.G, color.B, Mathf.Min(alpha + 0.2f, 1.0f));
            Godot.Collections.Array cells = plDict.ContainsKey("cells") ? plDict["cells"].AsGodotArray() : new Godot.Collections.Array();
            foreach (Variant c in cells)
            {
                if (c.VariantType != Variant.Type.Array || c.AsGodotArray().Count < 2)
                {
                    continue;
                }
                Godot.Collections.Array cArr = c.AsGodotArray();
                int bx = cArr[0].AsInt32();
                int by = cArr[1].AsInt32();
                // 只绘制棋盘范围内（含上方出块区域）的格子
                if (bx < 0 || bx >= grid_width || by < 0 || by >= playable)
                {
                    continue;
                }
                Rect2 cell_rect = new Rect2(cell_to_world(bx, by), new Vector2(cell_size, cell_size));
                DrawRect(cell_rect, fill, true);
                DrawRect(cell_rect, border, false, 1.0f);
            }
            idx += 1;
        }
    }

    // ========== 网格绘制系统 ==========

    /// <summary>绘制网格线（只绘制可见区域）</summary>
    public void _draw_grid_lines()
    {
        if (!show_grid_lines)
        {
            return;
        }

        int width = grid_width * cell_size;
        int height = grid_height * cell_size;  // 只绘制可见高度

        // 绘制垂直线（跳过x=0和x=grid_width，由白色版边边框覆盖）
        for (int x = 1; x < grid_width; x++)
        {
            Vector2 start_pos = new Vector2(offset_x + x * cell_size, offset_y);
            Vector2 end_pos = new Vector2(offset_x + x * cell_size, offset_y + height);
            DrawLine(start_pos, end_pos, grid_line_color, grid_line_width);
        }

        // 绘制水平线（只绘制可见高度，跳过y=0和y=grid_height）
        for (int y = 1; y < grid_height; y++)
        {
            Vector2 start_pos = new Vector2(offset_x, offset_y + y * cell_size);
            Vector2 end_pos = new Vector2(offset_x + width, offset_y + y * cell_size);
            DrawLine(start_pos, end_pos, grid_line_color, grid_line_width);
        }
    }

    /// <summary>绘制所有格子（含可见区域上方的出块区域）</summary>
    public void _draw_cells()
    {
        // 优先判断：不处于隐形模式 → 全部正常绘制
        if (tetris_invisible != 1)
        {
            for (int y = 0; y < grid_height + above_visible_rows; y++)
            {
                Godot.Collections.Array board_row = board_data[y].AsGodotArray();
                for (int x = 0; x < grid_width; x++)
                {
                    Variant cell_color = board_row[x];
                    if (cell_color.VariantType == Variant.Type.Nil)
                    {
                        continue;
                    }
                    Rect2 cell_rect = new Rect2(cell_to_world(x, y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, cell_color.AsColor(), true);
                    DrawRect(cell_rect, grid_line_color, false, 1.0f);
                }
            }
            return;
        }

        // 隐形模式（tetris_invisible == 1）
        long now = (long)Time.GetTicksMsec();

        for (int y = 0; y < grid_height + above_visible_rows; y++)
        {
            Godot.Collections.Array board_row = board_data[y].AsGodotArray();
            for (int x = 0; x < grid_width; x++)
            {
                Variant cell_color = board_row[x];
                if (cell_color.VariantType == Variant.Type.Nil)
                {
                    continue;
                }

                // 处于显示阶段 → 所有方块正常绘制
                if (_is_visible_mode)
                {
                    Rect2 cell_rect = new Rect2(cell_to_world(x, y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, cell_color.AsColor(), true);
                    DrawRect(cell_rect, grid_line_color, false, 1.0f);
                    continue;
                }

                // 隐藏阶段：手上控制的方块始终显示
                if (_is_occupied_by_current_piece(x, y))
                {
                    Rect2 cell_rect = new Rect2(cell_to_world(x, y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, cell_color.AsColor(), true);
                    DrawRect(cell_rect, grid_line_color, false, 1.0f);
                    continue;
                }

                // 隐藏阶段：垃圾行始终显示
                if (_is_garbage_color(cell_color.AsColor()))
                {
                    Rect2 cell_rect = new Rect2(cell_to_world(x, y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, cell_color.AsColor(), true);
                    DrawRect(cell_rect, grid_line_color, false, 1.0f);
                    continue;
                }

                // 普通已锁定方块 → 渐隐逻辑（落块后的短暂现形）
                if (drop_visible_time > 0.0f)
                {
                    float elapsed = (float)((now - (long)_cell_lock_times[y].AsGodotArray()[x]) / 1000.0);
                    float alpha = 1.0f - (elapsed / drop_visible_time);
                    alpha = Mathf.Clamp(alpha, 0.0f, 1.0f);
                    if (alpha <= 0.0f)
                    {
                        continue;  // 完全消失
                    }
                    Color draw_color = cell_color.AsColor();
                    draw_color.A = alpha;
                    Rect2 cell_rect = new Rect2(cell_to_world(x, y), new Vector2(cell_size, cell_size));
                    DrawRect(cell_rect, draw_color, true);
                    DrawRect(cell_rect, grid_line_color, false, 1.0f);
                }
                else
                {
                    // drop_visible_time == 0：落下即隐形
                    continue;
                }
            }
        }
    }

    /// <summary>绘制消行动画高亮：对正在清除的行做白色闪烁提示</summary>
    public void _draw_clearing_lines()
    {
        if (clearing_lines.Count == 0)
        {
            return;
        }
        long now = (long)Time.GetTicksMsec();
        double alpha = 0.45 + 0.35 * (0.5 + 0.5 * System.Math.Sin(now / 90.0));
        foreach (Variant yVar in clearing_lines)
        {
            int y = yVar.AsInt32();
            Rect2 rect = new Rect2(cell_to_world(0, y), new Vector2(grid_width * cell_size, cell_size));
            DrawRect(rect, new Color(1.0f, 1.0f, 1.0f, (float)alpha), true);
        }
    }

    /// <summary>判断颜色是否为垃圾行颜色（垃圾行需要始终绘制）</summary>
    public bool _is_garbage_color(Color color)
    {
        if (garbage_line_controller == null)
        {
            return false;
        }
        return (color == garbage_line_controller.garbage_color
                || color == garbage_line_controller.buffered_garbage_color
                || color == garbage_line_controller.solid_garbage_color);
    }

    /// <summary>绘制背景（只绘制可见区域）</summary>
    public void _draw_background()
    {
        Rect2 background_rect = new Rect2(offset_x, offset_y,
            grid_width * cell_size, grid_height * cell_size);

        DrawRect(background_rect, background_color, true);
    }

    /// <summary>绘制版面左右边缘白线（只覆盖可见区域）</summary>
    public void _draw_board_border()
    {
        int board_width_px = grid_width * cell_size;
        int board_height_px = grid_height * cell_size;
        int board_left = offset_x;
        int board_right = offset_x + board_width_px;
        int board_top = offset_y;
        int board_bottom = offset_y + board_height_px;

        // 左边缘白线
        DrawLine(new Vector2(board_left, board_top), new Vector2(board_left, board_bottom), board_border_color, board_border_width);

        // 右边缘白线
        DrawLine(new Vector2(board_right, board_top), new Vector2(board_right, board_bottom), board_border_color, board_border_width);
    }

    // ========== 垃圾槽显示系统 ==========

    /// <summary>获取垃圾槽的位置（在Hold框和版面之间）</summary>
    public Rect2 _get_garbage_slot_position()
    {
        int slot_x = offset_x + hold_display_offset_cells * cell_size + hold_display_width * cell_size;
        int slot_width = garbage_slot_width * cell_size;
        int slot_height = grid_height * cell_size;  // 与可见版面同高
        int slot_y = offset_y;  // 与版面顶部对齐

        return new Rect2(slot_x, slot_y, slot_width, slot_height);
    }

    /// <summary>绘制垃圾槽</summary>
    public void _draw_garbage_slot()
    {
        if (!garbage_slot_enabled)
        {
            return;
        }

        Rect2 slot_rect = _get_garbage_slot_position();

        // 绘制黑色背景
        DrawRect(slot_rect, Colors.Black, true);

        // 绘制边框（白色边框）
        DrawRect(slot_rect, garbage_slot_border_color, false, garbage_slot_border_width);

        // 绘制垃圾行矩形（从garbage_line_controller获取数据）
        _draw_garbage_bars(slot_rect);

        // 绘制 garbage_cap 横线（从下往上数第 garbage_cap 行）
        if (garbage_cap > 0 && garbage_cap < grid_height)
        {
            float gap_y = slot_rect.Position.Y + (grid_height - garbage_cap) * cell_size;
            Vector2 line_start = new Vector2(slot_rect.Position.X, gap_y);
            Vector2 line_end = new Vector2(slot_rect.Position.X + slot_rect.Size.X, gap_y);
            DrawLine(line_start, line_end, garbage_cap_line_color, 1.0f);
        }
    }

    /// <summary>绘制垃圾行矩形（包括正常和缓冲）</summary>
    public void _draw_garbage_bars(Rect2 slot_rect)
    {
        if (garbage_line_controller == null)
        {
            return;
        }

        // 获取正常队列和缓冲队列数据
        Godot.Collections.Array enter_queue = garbage_line_controller.get_enter_queue();
        Godot.Collections.Array buffer_queue = garbage_line_controller.get_buffer_queue();

        if (enter_queue.Count == 0 && buffer_queue.Count == 0)
        {
            return;
        }

        // 计算绘制参数
        float bar_width = slot_rect.Size.X - garbage_bar_padding * cell_size * 2;
        float padding_x = slot_rect.Position.X + garbage_bar_padding * cell_size;

        // 从底部开始绘制
        float current_bottom = slot_rect.Position.Y + slot_rect.Size.Y;

        // 先绘制正常队列（索引 0 在底部，最先出）
        for (int i = 0; i < enter_queue.Count; i++)
        {
            Variant entry = enter_queue[i];
            long row_count = entry.VariantType == Variant.Type.Dictionary ? (long)entry.AsGodotDictionary()["count"] : (long)entry;
            float bar_height = (float)(row_count * cell_size) - garbage_bar_padding * cell_size * 1;

            if (bar_height <= 0)
            {
                bar_height = cell_size * 0.5f;
            }

            float bar_y = current_bottom - bar_height - garbage_bar_padding * cell_size;
            Rect2 bar_rect = new Rect2(padding_x, bar_y, bar_width, bar_height);

            // 正常垃圾使用红色
            DrawRect(bar_rect, garbage_bar_color, true);
            Color border_color = new Color(1.0f, 0.3f, 0.3f, 1.0f);
            DrawRect(bar_rect, border_color, false, 1.0f);

            if (i > 0)
            {
                float separator_y = bar_y - garbage_bar_padding * cell_size;
                Vector2 line_start = new Vector2(slot_rect.Position.X + garbage_bar_padding * cell_size, separator_y);
                Vector2 line_end = new Vector2(slot_rect.Position.X + slot_rect.Size.X - garbage_bar_padding * cell_size, separator_y);
                DrawLine(line_start, line_end, garbage_bar_separator_color, garbage_bar_separator_width);
            }

            current_bottom = bar_y;
        }

        // 再绘制缓冲队列（在正常队列上方）
        // 正向遍历：索引 0（最早加入、计时最短）在底部，索引末尾（最新加入）在上方
        for (int i = 0; i < buffer_queue.Count; i++)
        {
            Variant entry = buffer_queue[i];
            Godot.Collections.Dictionary entryDict = entry.AsGodotDictionary();
            long row_count = (long)entryDict["count"];
            float bar_height = (float)(row_count * cell_size) - garbage_bar_padding * cell_size * 1;

            if (bar_height <= 0)
            {
                bar_height = cell_size * 0.5f;
            }

            float bar_y = current_bottom - bar_height - garbage_bar_padding * cell_size;
            Rect2 bar_rect = new Rect2(padding_x, bar_y, bar_width, bar_height);

            // 缓冲垃圾使用半透明暗红色
            Color buffered_color = new Color(0.5f, 0.0f, 0.0f, 0.7f);
            DrawRect(bar_rect, buffered_color, true);
            Color border_color = new Color(0.7f, 0.0f, 0.0f, 0.8f);
            DrawRect(bar_rect, border_color, false, 1.0f);

            // 显示缓冲倒计时（可选）
            float timer = entryDict.ContainsKey("timer") ? entryDict["timer"].AsSingle() : 0.0f;
            string timer_text = string.Format("{0:F1}s", timer);
            float font_size = cell_size * 0.3f;
            Vector2 text_pos = new Vector2(
                slot_rect.Position.X + slot_rect.Size.X * 0.5f,
                bar_y + bar_height * 0.5f - font_size * 0.5f
            );
            _draw_label(text_pos.X, text_pos.Y, timer_text, Colors.White, font_size);

            if (i > 0)
            {
                float separator_y = bar_y - garbage_bar_padding * cell_size;
                Vector2 line_start = new Vector2(slot_rect.Position.X + garbage_bar_padding * cell_size, separator_y);
                Vector2 line_end = new Vector2(slot_rect.Position.X + slot_rect.Size.X - garbage_bar_padding * cell_size, separator_y);
                DrawLine(line_start, line_end, garbage_bar_separator_color, garbage_bar_separator_width);
            }

            current_bottom = bar_y;
        }
    }

    // ========== 统计信息显示系统 ==========

    /// <summary>更新统计数据</summary>
    public void update_stats(float pps, float apm, float rpm)
    {
        pps_value = pps;
        apm_value = apm;
        rpm_value = rpm;
        QueueRedraw();
    }

    /// <summary>绘制统计信息（在垃圾槽左侧）</summary>
    public void _draw_stats()
    {
        if (!stats_display_enabled)
        {
            return;
        }

        Rect2 slot_rect = _get_garbage_slot_position();
        float font_size = cell_size * stats_font_size_ratio;
        Font _font = ThemeDB.FallbackFont;

        // 计算文字位置（在垃圾槽左侧，右对齐）
        float text_x = slot_rect.Position.X + stats_offset_x_cells * cell_size;
        float text_y_base = slot_rect.Position.Y + slot_rect.Size.Y - stats_offset_y_cells * cell_size;  // 从底部向上偏移

        // 三行文字
        Godot.Collections.Array stats_lines = new Godot.Collections.Array()
        {
            string.Format("PPS {0:F2}/s", pps_value),  // PPS X.XX/s
            string.Format("APM {0:F2}/m", apm_value),  // APM X.XX/m
            string.Format("RPM {0:F2}/m", rpm_value)   // RPM X.XX/m
        };

        float line_spacing = cell_size * stats_spacing_cells;

        // 从底部向上绘制
        for (int i = stats_lines.Count - 1; i >= 0; i--)
        {
            float line_y = text_y_base - (stats_lines.Count - 1 - i) * line_spacing - font_size * 0.5f;
            Vector2 text_position = new Vector2(text_x, line_y);
            _draw_text_with_outline(text_position, stats_lines[i].AsString(), stats_text_color,
                stats_text_outline_color, font_size, HorizontalAlignment.Right);
        }
    }

    // ========== 高度显示系统 ==========

    /// <summary>绘制高度显示（在版面下侧居中）</summary>
    public void _draw_height_display()
    {
        if (!height_display_enabled)
        {
            return;
        }
        if (tower_controller == null)
        {
            return;
        }

        float font_size = cell_size * height_font_size_ratio;

        // 计算位置（版面底部中央）
        float board_center_x = offset_x + grid_width * cell_size * 0.5f;
        float board_bottom_y = offset_y + grid_height * cell_size;

        float offset_y_pixels = height_display_offset_y_cells * cell_size;

        // 第一行：高度（居中）
        Vector2 text_pos = new Vector2(board_center_x, board_bottom_y + offset_y_pixels);
        string height_text = string.Format("{0:F2}m", tower_controller.tower_meter);
        _draw_text_with_outline(text_pos, height_text, height_text_color,
            height_text_outline_color, font_size, HorizontalAlignment.Center);

        // 第二行：速度（在高度文字下方，居中）
        string speed_text = string.Format("{0:F2}/s", tower_controller.tower_speed_meter);
        Vector2 speed_pos = new Vector2(board_center_x, text_pos.Y + font_size * 1.2f);
        _draw_text_with_outline(speed_pos, speed_text, height_text_color,
            height_text_outline_color, font_size * 0.8f, HorizontalAlignment.Center);

        // 第三行：阶段进度条（在速度文字下方，居中）
        _draw_stage_progress_bar(board_center_x, speed_pos.Y + font_size * 0.8f);
    }

    /// <summary>绘制阶段进度条</summary>
    public void _draw_stage_progress_bar(float center_x, float top_y)
    {
        if (!stage_progress_bar_enabled)
        {
            return;
        }
        if (tower_controller == null)
        {
            return;
        }

        // 计算进度（当前米数在当前阶段门槛到下一阶段门槛之间的百分比）
        Godot.Collections.Array floor_array = TowerController.FLOOR_HIGHER;
        int stage = tower_controller.current_stage;
        float current_floor = stage < floor_array.Count ? (float)(long)floor_array[stage] : (float)(long)floor_array[floor_array.Count - 1];
        float next_floor = stage + 1 < floor_array.Count ? (float)(long)floor_array[stage + 1] : current_floor;

        float progress = 1.0f;
        if (next_floor > current_floor)
        {
            progress = (tower_controller.tower_meter - current_floor) / (next_floor - current_floor);
            progress = Mathf.Clamp(progress, 0.0f, 1.0f);
        }

        float bar_width = stage_progress_bar_width_cells * cell_size;
        float bar_height = stage_progress_bar_height_cells * cell_size;

        Vector2 bar_top_left = new Vector2(center_x - bar_width * 0.5f, top_y);
        Rect2 bar_rect = new Rect2(bar_top_left, new Vector2(bar_width, bar_height));

        // 背景
        DrawRect(bar_rect, stage_progress_bar_bg_color, true);

        // 填充部分
        if (progress > 0.0f)
        {
            float fill_width = bar_width * progress;
            Rect2 fill_rect = new Rect2(bar_top_left, new Vector2(fill_width, bar_height));
            DrawRect(fill_rect, stage_progress_bar_fill_color, true);
        }

        // 边框
        DrawRect(bar_rect, stage_progress_bar_border_color, false, 1.0f);
    }

    // ========== 大攻击警告信号响应 ==========

    public void _on_big_attack_warning_started()
    {
        big_attack_warning_active = true;
        big_attack_warning_progress = 0.0f;
    }

    public void _on_big_attack_warning_ended()
    {
        big_attack_warning_active = false;
        big_attack_warning_progress = 0.0f;
        QueueRedraw();
    }

    // ========== Hold方块显示系统 ==========

    /// <summary>设置Hold显示的方块</summary>
    public void set_hold_piece(Godot.Collections.Array piece, Color color)
    {
        hold_piece_data = piece;
        hold_piece_color = color;
        QueueRedraw();
    }

    /// <summary>清除Hold显示</summary>
    public void clear_hold_piece()
    {
        hold_piece_data = new Godot.Collections.Array();
        hold_piece_color = Colors.White;
        QueueRedraw();
    }

    /// <summary>计算Hold框的位置（基于当前cell_size）</summary>
    public Vector2 _get_hold_position()
    {
        int hold_offset_x = hold_display_offset_cells * cell_size;
        int hold_offset_y = hold_display_offset_y_cells * cell_size;
        return new Vector2(offset_x + hold_offset_x, offset_y + hold_offset_y);
    }

    /// <summary>绘制Hold方块区域</summary>
    public void _draw_hold_display()
    {
        if (!hold_display_enabled)
        {
            return;
        }
        // NoHold模式：关闭Hold显示
        if (no_hold)
        {
            return;
        }

        // 计算Hold框的位置（基于当前cell_size）
        Vector2 hold_pos = _get_hold_position();
        float hold_x = hold_pos.X;
        float hold_y = hold_pos.Y;

        // 计算Hold框的大小（使用当前cell_size）
        int hold_width = hold_display_width * cell_size;
        int hold_height = hold_display_height * cell_size;

        // 绘制背景
        Rect2 hold_rect = new Rect2(hold_x, hold_y, hold_width, hold_height);
        DrawRect(hold_rect, hold_background_color, true);

        // 绘制边框
        DrawRect(hold_rect, hold_border_color, false, hold_border_width);

        // 绘制"HOLD"标签
        _draw_label(hold_x, hold_y - cell_size * 0.5f, "HOLD", hold_border_color, cell_size * 0.4f);

        // 如果有方块数据，绘制方块
        if (hold_piece_data.Count != 0)
        {
            // 计算内边距
            float padding_x = hold_width * hold_padding;
            float padding_y = hold_height * hold_padding;

            // 计算实际绘制区域（去掉内边距）
            float draw_area_x = hold_x + padding_x;
            float draw_area_y = hold_y + padding_y;
            float draw_area_width = hold_width - padding_x * 2;
            float draw_area_height = hold_height - padding_y * 2;

            _draw_piece_in_area(hold_piece_data, hold_piece_color,
                draw_area_x, draw_area_y, draw_area_width, draw_area_height);
        }
    }

    // ========== Next方块显示系统 ==========

    /// <summary>设置Next显示的方块列表</summary>
    public void set_next_pieces(Godot.Collections.Array pieces)
    {
        // pieces: [{shape: Array, color: Color}, ...]
        next_pieces_data = pieces;
        QueueRedraw();
    }

    /// <summary>清除Next显示</summary>
    public void clear_next_pieces()
    {
        next_pieces_data = new Godot.Collections.Array();
        QueueRedraw();
    }

    /// <summary>计算Next框的位置（基于当前cell_size）</summary>
    public Vector2 _get_next_position(int index)
    {
        int next_offset_x = next_display_offset_cells * cell_size;
        int next_offset_y = next_display_offset_y_cells * cell_size + index * (next_display_height + next_spacing_cells) * cell_size;
        return new Vector2(offset_x + next_offset_x, offset_y + next_offset_y);
    }

    /// <summary>绘制Next方块区域</summary>
    public void _draw_next_display()
    {
        if (!next_display_enabled)
        {
            return;
        }

        if (next_pieces_data.Count == 0)
        {
            return;
        }

        // 限制显示的Next数量
        int display_count = Mathf.Min(next_count, next_pieces_data.Count);

        for (int i = 0; i < display_count; i++)
        {
            Variant piece_data = next_pieces_data[i];
            Godot.Collections.Dictionary pieceDict = piece_data.AsGodotDictionary();
            Godot.Collections.Array shape = pieceDict["shape"].AsGodotArray();
            Color color = pieceDict["color"].AsColor();

            // 计算Next框的位置
            Vector2 next_pos = _get_next_position(i);
            float next_x = next_pos.X;
            float next_y = next_pos.Y;

            // 计算Next框的大小
            int next_width = next_display_width * cell_size;
            int next_height = next_display_height * cell_size;

            // 绘制背景
            Rect2 next_rect = new Rect2(next_x, next_y, next_width, next_height);
            DrawRect(next_rect, next_background_color, true);

            // 绘制边框
            DrawRect(next_rect, next_border_color, false, next_border_width);

            // 绘制"NEXT"标签（只对第一个显示）
            if (i == 0)
            {
                _draw_label(next_x, next_y - cell_size * 0.5f, next_label_text, next_label_color, cell_size * 0.4f);
            }

            // 绘制方块（如果有）
            if (shape.Count != 0)
            {
                // 计算内边距
                float padding_x = next_width * next_padding;
                float padding_y = next_height * next_padding;

                // 计算实际绘制区域（去掉内边距）
                float draw_area_x = next_x + padding_x;
                float draw_area_y = next_y + padding_y;
                float draw_area_width = next_width - padding_x * 2;
                float draw_area_height = next_height - padding_y * 2;

                _draw_piece_in_area(shape, color,
                    draw_area_x, draw_area_y, draw_area_width, draw_area_height);
            }
        }
    }

    /// <summary>查找版面中最高（y最小）的非空方块（排除正在控制的方块）</summary>
    public int _get_highest_block_y()
    {
        // 获取当前控制方块所占格子集合
        Godot.Collections.Dictionary current_cells = new Godot.Collections.Dictionary();
        if (tetris_controller != null)
        {
            Godot.Collections.Array piece = tetris_controller.current_piece;
            Vector2I pos = tetris_controller.current_position;
            if (piece.Count != 0 && (pos.X != 0 || pos.Y != 0))
            {
                for (int py = 0; py < piece.Count; py++)
                {
                    Godot.Collections.Array piece_row = piece[py].AsGodotArray();
                    for (int px = 0; px < piece_row.Count; px++)
                    {
                        if ((long)piece_row[px] == 1L)
                        {
                            int bx = pos.X + px;
                            int by = pos.Y + py;
                            current_cells[new Vector2I(bx, by)] = true;
                        }
                    }
                }
            }
        }

        int playable_height = Mathf.Min(grid_height + above_visible_rows, board_data.Count);
        for (int y = 0; y < playable_height; y++)
        {
            Godot.Collections.Array board_row = board_data[y].AsGodotArray();
            for (int x = 0; x < grid_width; x++)
            {
                if (board_row[x].VariantType != Variant.Type.Nil && !current_cells.ContainsKey(new Vector2I(x, y)))
                {
                    return y;
                }
            }
        }
        return -1;  // 没有方块
    }

    /// <summary>绘制大攻击警告：在最高方块上侧边缘划横线+朝上箭头</summary>
    public void _draw_big_attack_warning()
    {
        if (!big_attack_warning_active || big_attack_warning_progress <= 0.0f)
        {
            return;
        }

        int highest_y = _get_highest_block_y();
        if (highest_y < 0)
        {
            return;
        }

        // warning_alpha 随进度从 0.3 渐变到 1.0
        float warning_alpha = 0.3f + 0.7f * big_attack_warning_progress;
        Color warning_color = new Color(1.0f, 0.0f, 0.0f, warning_alpha * 0.6f);

        float board_left = offset_x;
        float board_right = offset_x + grid_width * cell_size;
        float board_width_px = board_right - board_left;

        // 计算最高方块上侧边缘的世界坐标
        float line_y = cell_to_world(0, highest_y).Y;  // 该行格子顶部

        // 绘制半透明横线（与版面同样宽）
        DrawLine(new Vector2(board_left, line_y), new Vector2(board_right, line_y), warning_color, 2.0f);

        // 在上方绘制4个朝上半透明箭头
        int arrow_count = 4;
        float arrow_width = cell_size * 0.5f;          // 箭头底部宽度
        float arrow_height = cell_size * 0.6f;         // 箭头高度
        float arrow_spacing = 1.0f * board_width_px / (arrow_count + 1);  // 等间距
        float arrow_alpha = 0.4f + 0.6f * big_attack_warning_progress;
        Color arrow_color = new Color(1.0f, 0.0f, 0.0f, arrow_alpha * 0.7f);

        for (int i = 0; i < arrow_count; i++)
        {
            float center_x = board_left + arrow_spacing * (i + 1);
            float arrow_top_y = line_y - arrow_height;  // 箭头尖端（在上方）
            float arrow_bottom_y = line_y;               // 箭头底部（在横线上）

            // 三角箭头：尖端在上，底部两个点等分
            Vector2 tip = new Vector2(center_x, arrow_top_y);
            Vector2 left_bottom = new Vector2(center_x - arrow_width * 0.5f, arrow_bottom_y);
            Vector2 right_bottom = new Vector2(center_x + arrow_width * 0.5f, arrow_bottom_y);

            DrawPolygon(new Vector2[] { tip, left_bottom, right_bottom }, new Color[] { arrow_color });
        }
    }

    /// <summary>绘制游戏结束暗幕（半透明黑色覆盖版面区域）</summary>
    public void _draw_death_overlay()
    {
        if (!is_game_over)
        {
            return;
        }

        // 覆盖版面区域 + 垃圾槽 + Hold/Next区域
        int board_left = offset_x + hold_display_offset_cells * cell_size;
        int board_top = offset_y;
        int board_right = offset_x + (grid_width + next_display_offset_cells + next_display_width) * cell_size;
        int board_bottom = offset_y + grid_height * cell_size;

        Rect2 overlay_rect = new Rect2(board_left, board_top, board_right - board_left, board_bottom - board_top);
        Color overlay_color = new Color(0, 0, 0, 0.7f);
        DrawRect(overlay_rect, overlay_color, true);
    }

    // ========== 通用绘制工具 ==========

    /// <summary>在指定区域绘制方块（自动缩放）</summary>
    public void _draw_piece_in_area(Godot.Collections.Array piece, Color color, float area_x, float area_y,
        float area_width, float area_height)
    {
        // 计算方块的实际尺寸
        int piece_width = piece[0].AsGodotArray().Count;
        int piece_height = piece.Count;

        // 计算适合区域的最大格子大小
        float cell_size_x = area_width / piece_width;
        float cell_size_y = area_height / piece_height;
        float draw_cell_size = Mathf.Min(cell_size_x, cell_size_y);

        // 计算居中偏移
        float total_width = piece_width * draw_cell_size;
        float total_height = piece_height * draw_cell_size;
        float start_x = area_x + (area_width - total_width) / 2;
        float start_y = area_y + (area_height - total_height) / 2;

        // 绘制每个方块
        for (int y = 0; y < piece_height; y++)
        {
            Godot.Collections.Array piece_row = piece[y].AsGodotArray();
            for (int x = 0; x < piece_width; x++)
            {
                if ((long)piece_row[x] == 1L)
                {
                    Rect2 rect = new Rect2(
                        start_x + x * draw_cell_size,
                        start_y + y * draw_cell_size,
                        draw_cell_size,
                        draw_cell_size
                    );
                    DrawRect(rect, color, true);
                    // 添加边框
                    DrawRect(rect, Colors.White, false, 1.0f);
                }
            }
        }
    }

    /// <summary>绘制文本标签</summary>
    public void _draw_label(float x, float y, string text, Color color, float font_size)
    {
        Vector2 label_pos = new Vector2(x, y);
        // 使用draw_string绘制文本
        Font font = ThemeDB.FallbackFont;
        int font_size_int = Mathf.Max(1, (int)font_size);
        DrawString(font, label_pos, text, HorizontalAlignment.Left, -1, font_size_int, color);
    }

    /// <summary>绘制带描边的文本（支持对齐方式）</summary>
    public void _draw_text_with_outline(Vector2 text_position, string text, Color color, Color outline_color, float font_size)
    {
        _draw_text_with_outline(text_position, text, color, outline_color, font_size, HorizontalAlignment.Center);
    }

    public void _draw_text_with_outline(Vector2 text_position, string text, Color color, Color outline_color, float font_size, HorizontalAlignment alignment)
    {
        Font font = ThemeDB.FallbackFont;
        int font_size_int = Mathf.Max(1, (int)font_size);

        // 绘制描边（偏移4个方向）
        Vector2[] outline_offsets = {
            new Vector2(-1, 0), new Vector2(1, 0), new Vector2(0, -1), new Vector2(0, 1),
            new Vector2(-1, -1), new Vector2(1, -1), new Vector2(-1, 1), new Vector2(1, 1)
        };

        foreach (Vector2 offset in outline_offsets)
        {
            Vector2 outline_pos = text_position + offset;
            DrawString(font, outline_pos, text, alignment, -1, font_size_int, outline_color);
        }

        // 绘制主文本
        DrawString(font, text_position, text, alignment, -1, font_size_int, color);
    }

    public override void _Draw()
    {
        // 1. 绘制背景
        _draw_background();

        // 2. 绘制所有格子
        _draw_cells();

        // 2.5 绘制消行动画高亮（正在清除的行闪烁提示）
        _draw_clearing_lines();

        // 3. 绘制影子方块
        _draw_shadow();

        // 3.5 绘制 bot 决策预览（约30%透明度的落块规划）
        _draw_bot_plan();

        // 4. 绘制垃圾槽
        _draw_garbage_slot();

        // 5. 绘制Hold方块区域
        _draw_hold_display();

        // 6. 绘制Next方块区域
        _draw_next_display();

        // 7. 绘制大攻击警告条（在最高方块上侧边缘）
        _draw_big_attack_warning();

        // 8. 绘制统计信息
        _draw_stats();

        // 9. 绘制高度显示
        _draw_height_display();

        // 10. 绘制网格线
        _draw_grid_lines();

        // 12. 绘制版面左右边缘白线（最上层，确保不被网格线或格子描边覆盖）
        _draw_board_border();

        // 13. 游戏结束暗幕（最上层）
        _draw_death_overlay();
    }

    /// <summary>获取消行控制器的引用</summary>
    public void set_clear_line_controller(TetrisClearLine controller)
    {
        clear_line_controller = controller;
    }

    /// <summary>设置正在播放消行动画的行（行号），用于闪烁高亮提示</summary>
    public void set_clearing_lines(Godot.Collections.Array lines)
    {
        clearing_lines = lines.Duplicate();
        QueueRedraw();
    }

    /// <summary>清除消行动画高亮</summary>
    public void clear_clearing_lines()
    {
        clearing_lines.Clear();
        QueueRedraw();
    }

    /// <summary>更新网格尺寸（动态调整）</summary>
    public void resize_grid(int new_width, int new_height)
    {
        resize_grid(new_width, new_height, -1);
    }

    public void resize_grid(int new_width, int new_height, int new_max_height)
    {
        grid_width = new_width;
        grid_height = new_height;
        if (new_max_height > 0)
        {
            grid_max_height = new_max_height;
        }
        _init_board_data();

        if (auto_resize)
        {
            _auto_adjust_cell_size();
        }
        else if (auto_center)
        {
            _update_board_position();
        }

        QueueRedraw();
    }

    /// <summary>手动设置格子大小（会覆盖自动调整）</summary>
    public void set_cell_size(int new_size)
    {
        set_cell_size(new_size, true);
    }

    public void set_cell_size(int new_size, bool preserve_center)
    {
        cell_size = new_size;

        if (preserve_center && auto_center)
        {
            _update_board_position();
        }

        QueueRedraw();
    }

    /// <summary>设置基准点（手动模式）</summary>
    public void set_offset(int new_x, int new_y)
    {
        offset_x = new_x;
        offset_y = new_y;
        auto_center = false;  // 手动设置后禁用自动居中
        QueueRedraw();
    }

    /// <summary>启用/禁用自动居中</summary>
    public void set_auto_center(bool enabled)
    {
        auto_center = enabled;
        if (enabled)
        {
            _update_board_position();
            QueueRedraw();
        }
    }

    /// <summary>获取版面的实际边界矩形</summary>
    public Rect2 get_board_rect()
    {
        return new Rect2(offset_x, offset_y,
            grid_width * cell_size, grid_height * cell_size);
    }

    // ====== C# 专用辅助（新增私有工具，不参与 Godot 方法表） ======
    // set_bot_plan 的去重比较：等效于 GDScript 容器 == 的内容比较（递归）

    private static bool _arrays_equal(Godot.Collections.Array a, Godot.Collections.Array b)
    {
        if (a == b)
        {
            return true;
        }
        if (a == null || b == null || a.Count != b.Count)
        {
            return false;
        }
        for (int i = 0; i < a.Count; i++)
        {
            if (!_variant_equal(a[i], b[i]))
            {
                return false;
            }
        }
        return true;
    }

    private static bool _variant_equal(Variant a, Variant b)
    {
        if (a.VariantType == Variant.Type.Nil || b.VariantType == Variant.Type.Nil)
        {
            return a.VariantType == Variant.Type.Nil && b.VariantType == Variant.Type.Nil;
        }
        if (a.VariantType == Variant.Type.Array && b.VariantType == Variant.Type.Array)
        {
            return _arrays_equal(a.AsGodotArray(), b.AsGodotArray());
        }
        if (a.VariantType == Variant.Type.Dictionary && b.VariantType == Variant.Type.Dictionary)
        {
            Godot.Collections.Dictionary da = a.AsGodotDictionary();
            Godot.Collections.Dictionary db = b.AsGodotDictionary();
            if (da.Count != db.Count)
            {
                return false;
            }
            foreach (Variant key in da.Keys)
            {
                if (!db.ContainsKey(key) || !_variant_equal(da[key], db[key]))
                {
                    return false;
                }
            }
            return true;
        }
        if (a.VariantType == Variant.Type.Color && b.VariantType == Variant.Type.Color)
        {
            return a.AsColor() == b.AsColor();
        }
        if (a.VariantType == Variant.Type.String && b.VariantType == Variant.Type.String)
        {
            return a.AsString() == b.AsString();
        }
        if (a.VariantType == Variant.Type.Bool && b.VariantType == Variant.Type.Bool)
        {
            return a.AsBool() == b.AsBool();
        }
        if ((a.VariantType == Variant.Type.Int || a.VariantType == Variant.Type.Float)
            && (b.VariantType == Variant.Type.Int || b.VariantType == Variant.Type.Float))
        {
            return a.AsDouble() == b.AsDouble();
        }
        return false;
    }
}
