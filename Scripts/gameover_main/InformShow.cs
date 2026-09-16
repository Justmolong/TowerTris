using Godot;

/// <summary>
/// 游戏结束信息展示器
/// 负责显示游戏结束时的统计数据
/// </summary>
public partial class InformShow : Node
{
    // 节点引用（根据实际场景结构调整路径）
    [Export]
    public Label game_over_label;  // 游戏结束标题
    [Export]
    public Label height_label;     // 最终高度
    [Export]
    public Control stats_container;  // 统计数据容器

    // 统计数据显示标签（根据实际场景结构调整）
    [Export]
    public Label time_label;      // 游戏时间
    [Export]
    public Label pieces_label;    // 放置方块数
    [Export]
    public Label pps_label;       // PPS
    [Export]
    public Label apm_label;       // APM
    [Export]
    public Label rpm_label;       // RPM
    [Export]
    public Label max_combo_label; // 最大连击
    [Export]
    public Label max_btb_label;   // 最大BTB
    [Export]
    public Label lines_cleared_label;  // 总消行数
    [Export]
    public Label spins_label;     // 总Spin次数
    [Export]
    public Label attacks_label;   // 总攻击数
    [Export]
    public Label kill_count_label;      // 击杀数
    [Export]
    public Label tower_avg_speed_label; // ACPS（平均速度）
    [Export]
    public Label stage_label;           // 当前阶段

    // 已选取的 buff 列表（右侧）
    [Export]
    public VBoxContainer buff_list_container;  // 已选取 buff 列表容器
    [Export]
    public Label buff_list_title;              // buff 列表标题（保留，不删除）

    public override void _Ready()
    {
        // 显示游戏结束数据
        _display_game_over_data();
    }

    /// <summary>显示游戏结束数据</summary>
    public void _display_game_over_data()
    {
        // 从全局数据获取统计信息
        var stats = GlobalData.get_stats();

        // 设置标题和原因
        if (game_over_label != null)
            game_over_label.Text = "GAME OVER";

        // 显示最终高度
        if (height_label != null)
        {
            double height = stats.ContainsKey("tower_height") ? stats["tower_height"].AsDouble() : 0.0;
            height_label.Text = string.Format("最终高度: {0:F2}m", height);
        }

        // 格式化时间（秒 → MM:SS）
        string time_str = _format_time(stats.ContainsKey("game_time") ? stats["game_time"].AsSingle() : 0.0f);

        // 更新各个标签
        if (time_label != null)
            time_label.Text = string.Format("游戏时间: {0}", time_str);

        if (pieces_label != null)
            pieces_label.Text = string.Format("放置方块: {0}", stats.ContainsKey("total_pieces") ? stats["total_pieces"].AsInt32() : 0);

        if (pps_label != null)
            pps_label.Text = string.Format("PPS: {0:F2}", stats.ContainsKey("pps") ? stats["pps"].AsDouble() : 0.0);

        if (apm_label != null)
            apm_label.Text = string.Format("APM: {0:F2}", stats.ContainsKey("apm") ? stats["apm"].AsDouble() : 0.0);

        if (rpm_label != null)
            rpm_label.Text = string.Format("RPM: {0:F2}", stats.ContainsKey("rpm") ? stats["rpm"].AsDouble() : 0.0);

        if (max_combo_label != null)
            max_combo_label.Text = string.Format("最大连击: {0}", stats.ContainsKey("max_combo") ? stats["max_combo"].AsInt32() : 0);

        if (max_btb_label != null)
            max_btb_label.Text = string.Format("最大BTB: {0}", stats.ContainsKey("max_btb") ? stats["max_btb"].AsInt32() : 0);

        if (lines_cleared_label != null)
            lines_cleared_label.Text = string.Format("总消行: {0}", stats.ContainsKey("total_lines_cleared") ? stats["total_lines_cleared"].AsInt32() : 0);

        if (spins_label != null)
            spins_label.Text = string.Format("总Spin: {0}", stats.ContainsKey("total_spins") ? stats["total_spins"].AsInt32() : 0);

        if (attacks_label != null)
            attacks_label.Text = string.Format("总攻击: {0}", stats.ContainsKey("total_attacks") ? stats["total_attacks"].AsInt32() : 0);

        if (kill_count_label != null)
            kill_count_label.Text = string.Format("击杀数: {0}", stats.ContainsKey("kill_count") ? stats["kill_count"].AsInt32() : 0);

        if (tower_avg_speed_label != null)
        {
            double total_dist = stats.ContainsKey("tower_height") ? stats["tower_height"].AsDouble() : 0.0;
            double total_time = Mathf.Max(stats.ContainsKey("game_time") ? stats["game_time"].AsDouble() : 1.0, 0.001);
            double avg_speed = total_dist / total_time;
            tower_avg_speed_label.Text = string.Format("ACS: {0:F2}", avg_speed);
        }

        if (stage_label != null)
            stage_label.Text = string.Format("当前阶段: {0}", (stats.ContainsKey("current_stage") ? stats["current_stage"].AsInt32() : 0) + 1);

        // 显示已选取的 buff 列表
        _populate_buff_list();
    }

    /// <summary>在右侧列表显示本次已选取的 buff</summary>
    public void _populate_buff_list()
    {
        if (buff_list_container == null)
            return;
        // 清除旧的动态标签（保留标题节点）
        foreach (Node child in buff_list_container.GetChildren())
        {
            if (child != buff_list_title)
                child.QueueFree();
        }

        var buffs = GlobalData.selected_buffs;
        if (buffs.Count == 0)
        {
            var empty = new Label();
            empty.Text = "无";
            empty.AddThemeFontSizeOverride("font_size", 18);
            empty.AddThemeColorOverride("font_color", new Color(0.6f, 0.6f, 0.6f, 1));
            buff_list_container.AddChild(empty);
            return;
        }

        foreach (var buffVariant in buffs)
        {
            var buff = buffVariant.AsGodotDictionary();
            string buff_name = _get_buff_name(buff);
            var label = new Label();
            label.Text = buff_name;
            label.AutowrapMode = TextServer.AutowrapMode.WordSmart;
            label.AddThemeFontSizeOverride("font_size", 18);
            label.AddThemeColorOverride("font_color", new Color(0.7f, 0.9f, 0.7f, 1));
            buff_list_container.AddChild(label);
        }
    }

    /// <summary>提取 buff 名称（描述中冒号前的部分，如 "高压I：apm总量增加20%" → "高压I"）</summary>
    /// <summary>若无冒号则使用描述本身；描述为空时退回 box_id</summary>
    public string _get_buff_name(Godot.Collections.Dictionary buff)
    {
        string text = buff.ContainsKey("text") ? buff["text"].AsString() : "";
        foreach (string sep in new string[] { "：", ":", "－", "-" })
        {
            int idx = text.Find(sep);
            if (idx > 0)
                return text.Substr(0, idx).StripEdges();
        }
        if (text.Length > 0)
            return text;
        return buff.ContainsKey("id") ? buff["id"].AsString() : "";
    }

    /// <summary>格式化时间</summary>
    public string _format_time(float seconds)
    {
        int minutes = (int)(seconds / 60.0f);
        int secs = (int)seconds % 60;
        return string.Format("{0:D2}:{1:D2}", minutes, secs);
    }

    /// <summary>重玩按钮回调（可选）</summary>
    public void _on_restart_button_pressed()
    {
        // 重置全局数据
        GlobalData.reset_stats();
        // 切换到游戏场景
        GetTree().ChangeSceneToFile("res://Tscns/tetris.tscn");
    }

    /// <summary>EXIT 按钮回调：返回主菜单</summary>
    public void _on_exit_button_pressed()
    {
        // 重置全局数据
        GlobalData.reset_stats();
        // 切换到主菜单场景
        GetTree().ChangeSceneToFile("res://Tscns/main_menu.tscn");
    }

    /// <summary>BACK 按钮回调：返回 buff 选择界面，并带回已选取的 buff 进行预勾选</summary>
    public void _on_back_button_pressed()
    {
        // 标记：返回 buff_chose_area 时需要恢复上次勾选
        GlobalData.restore_buffs = true;
        // 不重置 stats，保留 selected_buffs 供 buff_chose_area 读取
        GetTree().ChangeSceneToFile("res://Tscns/buff_chose_area.tscn");
    }
}
