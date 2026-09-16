using Godot;

/// <summary>
/// Buff选择区域控制器
/// 负责Back返回主菜单和Start开始游戏的功能
/// 管理 ToggleBox 列表，支持批量读取切换状态
/// 支持 buff/debuff 倍率累加（additive stacking）：勾选后自动计算并显示实际数值变化
/// 多个选框影响同一 key 时，倍率按累加方式叠加：1.0 + (m₁-1.0) + (m₂-1.0) + ...
/// </summary>
public partial class BuffChoseArea : Node
{
    // ========== 节点引用 ==========

    [Export]
    public Button back_button;
    [Export]
    public Button start_button;

    // 滚动容器
    [Export]
    public ScrollContainer top_scroll_container;
    [Export]
    public ScrollContainer middle_scroll_container;

    // 中部 buff 列表容器
    [Export]
    public VBoxContainer buff_list;

    // Buff配置数据文件路径（读取互斥组/显示文本/倍率配置）
    public const string BUFF_DATA_PATH = "res://GameSaveData/BuffChoseData.json";

    // 已勾选框对应的 Label 字典（box_id -> Label）
    public Godot.Collections.Dictionary _label_by_id = new Godot.Collections.Dictionary();

    // 合并效果汇总 Label（显示所有唯一 key 的累加倍率，去重合并）
    public Label _summary_label = null;

    /// <summary>互斥选框组配置：同一组内的选框互斥，选中一个则其他自动取消</summary>
    /// <summary>组名 -> [box_id1, box_id2, ...]</summary>
    public Godot.Collections.Dictionary _mutually_exclusive_groups = new Godot.Collections.Dictionary();

    // box_id 到显示文本的映射
    public Godot.Collections.Dictionary _display_text_map = new Godot.Collections.Dictionary();

    // 挑战组合配置（从BuffChoseData.json的BuffCombination读取）
    // 组合名 -> {"Info": 显示文本, "Group": [组名列表], "Color": [r,g,b](可选)}
    public Godot.Collections.Dictionary _combination_map = new Godot.Collections.Dictionary();

    // 组合分组（从BuffChoseData.json的BuffGroup读取）：组名 -> [box_id, ...]
    public Godot.Collections.Dictionary _buff_group_map = new Godot.Collections.Dictionary();

    // 挑战组合 Label（显示在buff列表末尾）
    public Label _combination_label = null;

    // 组合勾选框（"组合buff"列）：box_id -> 组合名
    public Godot.Collections.Dictionary _combination_box_ids = new Godot.Collections.Dictionary();

    // 组合勾选框的解析结果：box_id -> [实际指向的buff box_id列表]（每组取编号最低的buff）
    public Godot.Collections.Dictionary _combination_box_map = new Godot.Collections.Dictionary();

    // 组合批量更新防递归标记：程序化批量设置buff/组合勾选框时为 true，避免重复触发组合逻辑
    public bool _updating_combo = false;

    // ========== Buff/Debuff 倍率配置 ==========

    /// <summary>TowerController 初始数据字典（可在编辑器中修改，点击 START 时自动存入 GlobalData）</summary>
    [Export]
    public Godot.Collections.Dictionary tower_init_data = new Godot.Collections.Dictionary()
    {
        // ---- APM / Stage ----
        { "total_apm", 70.0 },
        { "stage_percent_apm", new Godot.Collections.Array() { 0.01, 0.02, 0.05, 0.1, 0.25, 0.4, 0.55, 0.7, 0.8, 0.9, 1.0 } },
        { "extra_percent_apm", 0.0 },

        // ---- Garbage ----
        { "stage_garbage_time", new Godot.Collections.Array() { 10, 8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 2, 2, 1, 1, 1, 0.5 } },
        { "garbage_collect_percent_array", new Godot.Collections.Array() { 0.4, 0.3, 0.2, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.4 } },
        { "garbage_divide_percent_array", new Godot.Collections.Array() { 0.8, 0.6, 0.4, 0.2, 0.2, 0.1, 0.1, 0, 0.1, 0.2, 0.3 } },
        { "pressure_mult_array", new Godot.Collections.Array() { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 7 } },
        { "garbage_hole_change_percent_array", new Godot.Collections.Array() { 0.1, 0.1, 0.1, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 } },
        { "send_mult_attack", 1.0 },

        // Gravity
        { "gravity_drop_time_array", new Godot.Collections.Array() { 5 } },

        // ---- Tower Climb ----
        { "tower_lowest_speed", 0.1 },
        { "tower_dropped_speed", 0.01 },
        { "tower_dropped_mult", new Godot.Collections.Array() { 1, 1, 1, 1, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.7, 1.9, 2 } },
        { "attack_to_meter_mult", 0.2 },
        { "attack_to_speed_mult", 0.1 },

        // ---- Big Attack / Warning ----
        { "warning_count", 4 },
        { "segment_line", 4 },
        { "big_attack_delay", 4.0 },

        // ---- Kill Reward ----
        { "killer_spike", 10 },
        { "kill_possible_percent", 0.15 },
        { "kill_reward", new Godot.Collections.Array() { 10, 4 } },

        // 额外数据
        { "extra_data_dict", new Godot.Collections.Dictionary() },
    };

    /// <summary>Buff/Debuff 配置（直接赋值倍率，不再引用 tower_init_data）</summary>
    /// <summary>值直接写倍率/原始值，float 类型的值会与 tower_init_data 对应键相乘累加</summary>
    /// <summary>键不在 tower_init_data 中时，整个值键对会存入 extra_data_dict</summary>
    public Godot.Collections.Dictionary _buff_config_map = new Godot.Collections.Dictionary();

    // ExtraBotChange：BuffChoseData 中针对已勾选 buff 的 bot 参数（box_id -> {bot参数名: 值}）
    public Godot.Collections.Dictionary _extra_bot_change_map = new Godot.Collections.Dictionary();

    // ToggleBox 节点引用（可在编辑器中拖入或由代码动态添加）
    [Export]
    public Godot.Collections.Array toggle_boxes = new Godot.Collections.Array();

    // ========== 场景路径 ==========

    [Export]
    public string main_menu_scene_path = "res://Tscns/main_menu.tscn";
    [Export]
    public string game_scene_path = "res://Tscns/tetris.tscn";

    // ========== 返回时恢复勾选 ==========

    /// <summary>当从游戏结束界面（BACK 按钮）返回时，读取 GlobalData.selected_buffs 并预勾选对应的 ToggleBox</summary>
    /// <summary>读取后立刻复位 restore_buffs 标志，避免从主菜单进入时误恢复</summary>
    public void _restore_previous_selection()
    {
        if (!GlobalData.restore_buffs)
            return;
        GlobalData.restore_buffs = false;

        var buffs = GlobalData.selected_buffs;
        foreach (var buffVariant in buffs)
        {
            var buff = buffVariant.AsGodotDictionary();
            string bid = buff.ContainsKey("id") ? buff["id"].AsString() : "";
            if (bid.Length == 0)
                continue;
            set_toggle_checked(bid, true);
        }
        // 显式强制互斥：每个互斥组只保留一个勾选，确保返回后状态一致
        _enforce_mutual_exclusivity();
        // 恢复后同步组合勾选框（若恢复出的buff恰好形成某组合则勾选对应组合框）
        _reconcile_combo_boxes();
    }

    /// <summary>对每个互斥组强制只保留一个勾选（其余取消并移除标签）</summary>
    /// <summary>即使 toggled 信号未触发，也能保证互斥逻辑生效</summary>
    public void _enforce_mutual_exclusivity()
    {
        foreach (var groupVariant in _mutually_exclusive_groups.Keys)
        {
            string group_name = groupVariant.AsString();
            var group = _mutually_exclusive_groups[groupVariant].AsGodotArray();
            bool kept_one = false;
            foreach (var otherIdVariant in group)
            {
                string other_id = otherIdVariant.AsString();
                var tb = _find_toggle_box(other_id);
                if (tb != null && tb.is_checked_state())
                {
                    if (kept_one)
                    {
                        tb.set_checked(false);
                        _remove_label_for_box(other_id);
                    }
                    else
                    {
                        kept_one = true;
                    }
                }
            }
        }
    }

    /// <summary>按 box_id 查找 ToggleBox 节点</summary>
    public ToggleBox _find_toggle_box(string box_id)
    {
        foreach (var tbVariant in toggle_boxes)
        {
            if (tbVariant.VariantType == Variant.Type.Object)
            {
                var tb = tbVariant.AsGodotObject() as ToggleBox;
                if (tb != null && tb.box_id == box_id)
                    return tb;
            }
        }
        return null;
    }

    // ========== UI 缩放相关 ==========

    // Panel 引用（CanvasLayer 下全屏面板，用于居中缩放）
    public Panel _panel = null;

    // ========== 数据加载 ==========

    /// <summary>从BuffChoseData.json读取互斥组/显示文本/倍率配置，覆盖默认值</summary>
    /// <summary>文件不存在或解析失败时保留代码中的默认配置</summary>
    public void _load_buff_data_from_json()
    {
        if (!FileAccess.FileExists(BUFF_DATA_PATH))
        {
            // 已注释（调试噪音）：print("BuffChoseData.json 不存在，使用默认配置: ", BUFF_DATA_PATH)
            return;
        }

        using var file = FileAccess.Open(BUFF_DATA_PATH, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError("无法打开 BuffChoseData.json: ", BUFF_DATA_PATH);
            return;
        }

        string json_string = file.GetAsText();

        var json = new Json();
        Error error = json.Parse(json_string);
        if (error != Error.Ok)
        {
            GD.PushError("解析 BuffChoseData.json 失败: ", json.GetErrorMessage());
            return;
        }

        var data = json.Data;
        if (data.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError("BuffChoseData.json 格式错误");
            return;
        }

        var dict = data.AsGodotDictionary();

        // BuffConflick → 互斥选框组
        if (dict.ContainsKey("BuffConflick") && dict["BuffConflick"].VariantType == Variant.Type.Dictionary)
            _mutually_exclusive_groups = dict["BuffConflick"].AsGodotDictionary();

        // BuffInfo → 显示文本
        if (dict.ContainsKey("BuffInfo") && dict["BuffInfo"].VariantType == Variant.Type.Dictionary)
            _display_text_map = dict["BuffInfo"].AsGodotDictionary();

        // BuffChange → 倍率配置
        if (dict.ContainsKey("BuffChange") && dict["BuffChange"].VariantType == Variant.Type.Dictionary)
            _buff_config_map = dict["BuffChange"].AsGodotDictionary();

        // BuffCombination → 挑战组合配置
        if (dict.ContainsKey("BuffCombination") && dict["BuffCombination"].VariantType == Variant.Type.Dictionary)
            _combination_map = dict["BuffCombination"].AsGodotDictionary();

        // BuffGroup → 组合分组（组名 -> box_id列表）
        if (dict.ContainsKey("BuffGroup") && dict["BuffGroup"].VariantType == Variant.Type.Dictionary)
            _buff_group_map = dict["BuffGroup"].AsGodotDictionary();

        // ExtraBotChange → 针对已勾选 buff 的 bot 参数（box_id -> {bot参数名: 值}）
        if (dict.ContainsKey("ExtraBotChange") && dict["ExtraBotChange"].VariantType == Variant.Type.Dictionary)
            _extra_bot_change_map = dict["ExtraBotChange"].AsGodotDictionary();
    }

    /// <summary>内置兜底配置：某些buff不依赖JSON配置，代码内置默认值</summary>
    /// <summary>旧的 "Talentless" 单选框已废弃：Talentless 已拆分为 Talentless_1（NoSpin=1 全Mini）/ Talentless_2（NoSpin=2 禁Spin），</summary>
    /// <summary>均由 BuffChoseData.json 的 BuffChange 提供，故此处不再需要兜底。</summary>
    public void _apply_builtin_fallbacks()
    {
        // pass
    }

    // ========== 生命周期 ==========

    public override void _Ready()
    {
        // 先读取BuffChoseData.json覆盖默认配置
        _load_buff_data_from_json();
        // 内置兜底配置（Talentless无才能，不依赖JSON）
        _apply_builtin_fallbacks();

        _panel = GetNodeOrNull<Panel>("../Panel");
        // 若未在编辑器中配置toggle_boxes，则自动发现场景中的ToggleBox节点
        _discover_toggle_boxes();
        // 动态构建"组合buff"列（List14），把每个组合勾选框注册进 toggle_boxes
        _build_combination_ui();
        _connect_signals();
        _connect_toggle_boxes();

        // 应用 UI 缩放（UIScaler 已移除，固定 scale=1.0）
        _apply_ui_scale();

        // 更新已有标签显示（如 default_checked 为 true 的选框）
        _update_all_labels();
        _update_summary_label();
        _update_combination_label();
        // 根据当前已勾选的buff同步组合勾选框状态
        _reconcile_combo_boxes();

        // 从游戏结束界面返回时，恢复上次勾选的 buff
        // 必须延迟到所有 ToggleBox 的 _ready 执行完之后（本节点是 CanvasLayer 的第一个兄弟，
        // 其 _ready 会在 ToggleBox._ready 之前运行，导致勾选状态被 default_checked 覆盖）
        CallDeferred("_restore_previous_selection");

        // Demo: 打印初始状态
        //print("ToggleBox 数量: ", toggle_boxes.size())
        foreach (var tbVariant in toggle_boxes)
        {
            // pass
            //print("  [%s] checked=%s value=%s" % [tb.box_id, tb.is_checked_state(), tb.value])
        }
    }

    /// <summary>应用 UI 缩放：Panel 居中缩放，子区域内容自适应</summary>
    public void _apply_ui_scale(float _new_scale = -1.0f)
    {
        float s = 1.0f;

        // 缩放 Panel 并居中（3 个 ColorRect 作为子节点自动继承缩放）
        if (_panel != null)
        {
            _panel.Scale = new Vector2(s, s);
            _panel.PivotOffset = _panel.Size / 2.0f;
            Vector2 vp = GetTree().Root.Size;
            _panel.Position = (vp - _panel.Size * s) / 2.0f;
        }

        // 调整 BackButton 和 StartButton 的位置和字体（不 scale——那会导致重叠）
        if (back_button != null)
        {
            back_button.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(16 * s)));
            // BottomRightArea 内相对位置按比例调整
            back_button.OffsetLeft = 40 * s;
            back_button.OffsetTop = 80 * s;
            back_button.OffsetRight = 40 * s + 140 * s;
            back_button.OffsetBottom = 80 * s + 50 * s;
        }
        if (start_button != null)
        {
            start_button.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(16 * s)));
            start_button.OffsetLeft = 40 * s;
            start_button.OffsetTop = 150 * s;
            start_button.OffsetRight = 40 * s + 140 * s;
            start_button.OffsetBottom = 150 * s + 50 * s;
        }

        // 调整 ToggleBox 的大小
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null)
            {
                tb.box_size = Mathf.Max(16, (int)(32 * s));
                tb.CustomMinimumSize = new Vector2(tb.box_size, tb.box_size);
                tb.Size = new Vector2(tb.box_size, tb.box_size);
                tb.QueueRedraw();
            }
        }

        // 调整标签字体大小
        foreach (var boxIdVariant in _label_by_id.Keys)
        {
            string _box_id = boxIdVariant.AsString();
            var label = _label_by_id[boxIdVariant].AsGodotObject() as Label;
            if (label != null)
                label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(20 * s)));
        }

        // 调整汇总标签字体
        if (_summary_label != null)
            _summary_label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(18 * s)));

        // 调整挑战组合标签字体
        if (_combination_label != null)
            _combination_label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(20 * s)));
    }

    // ========== 信号连接 ==========

    public void _connect_signals()
    {
        if (back_button != null)
            back_button.Pressed += _on_back_button_pressed;
        if (start_button != null)
            start_button.Pressed += _on_start_button_pressed;
    }

    /// <summary>自动发现场景中的ToggleBox节点（当toggle_boxes未在编辑器中配置时）</summary>
    /// <summary>递归遍历本节点的父级（CanvasLayer）下所有子节点，按树顺序收集</summary>
    public void _discover_toggle_boxes()
    {
        if (toggle_boxes.Count > 0)
            return;
        var found = new Godot.Collections.Array();
        Node root_node = GetParent();
        if (root_node != null)
        {
            _find_toggle_boxes_recursive(root_node, found);
        }
        if (found.Count > 0)
        {
            toggle_boxes = found;
            // 已注释（调试噪音）：print("自动发现 ToggleBox 节点: ", toggle_boxes.size())
        }
    }

    public void _find_toggle_boxes_recursive(Node node, Godot.Collections.Array found)
    {
        if (node is ToggleBox)
            found.Add(node);
        foreach (Node child in node.GetChildren())
            _find_toggle_boxes_recursive(child, found);
    }

    /// <summary>连接所有 ToggleBox 的状态切换信号</summary>
    public void _connect_toggle_boxes()
    {
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null)
                tb.Toggled += _on_toggle_box_toggled;
        }
    }

    // ========== Buff/Debuff 计算核心 ==========

    /// <summary>计算所有已勾选框的 APM 总倍率累加</summary>
    /// <summary>只关注 total_apm_buff_mult 键（累加 stacking: 1.0 + (m₁-1.0) + (m₂-1.0) + ...）</summary>
    /// <summary>其他键由 get_buffed_tower_data 直接放入 extra_data_dict</summary>
    public Godot.Collections.Dictionary _calculate_accumulated_multipliers()
    {
        var multipliers = new Godot.Collections.Dictionary();
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.is_checked_state() && _buff_config_map.ContainsKey(tb.box_id))
            {
                var config = _buff_config_map[tb.box_id].AsGodotDictionary();
                if (config.ContainsKey("total_apm_buff_mult"))
                {
                    float mult = config["total_apm_buff_mult"].AsSingle();
                    if (multipliers.ContainsKey("total_apm_buff_mult"))
                        multipliers["total_apm_buff_mult"] = multipliers["total_apm_buff_mult"].AsSingle() + (mult - 1.0f);
                    else
                        multipliers["total_apm_buff_mult"] = mult;
                }
            }
        }
        return multipliers;
    }

    /// <summary>获取应用了所有已勾选框倍率（累加叠加）后的完整数据字典</summary>
    /// <summary>total_apm_buff_mult 倍率应用于 total_apm</summary>
    /// <summary>不在 tower_init_data 中的键值对整个添加入 extra_data_dict（排除 total_apm_buff_mult）</summary>
    public Godot.Collections.Dictionary get_buffed_tower_data()
    {
        var result = tower_init_data.Duplicate(true);
        var multipliers = _calculate_accumulated_multipliers();

        // Step 1: 将 total_apm_buff_mult 倍率应用于 total_apm
        if (multipliers.ContainsKey("total_apm_buff_mult"))
            result["total_apm"] = result["total_apm"].AsDouble() * multipliers["total_apm_buff_mult"].AsDouble();

        // Step 2: 处理不在 tower_init_data 中的键 → 直接存入 extra_data_dict
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.is_checked_state() && _buff_config_map.ContainsKey(tb.box_id))
            {
                var config = _buff_config_map[tb.box_id].AsGodotDictionary();
                foreach (var keyVariant in config.Keys)
                {
                    string key = keyVariant.AsString();
                    if (key == "total_apm_buff_mult")
                        continue;  // 倍率键，不存入数据
                    var extra = result["extra_data_dict"].AsGodotDictionary();
                    if (!extra.ContainsKey(key))
                    {
                        // 键不在 tower_init_data 中 → 整个值键对加入 extra_data_dict
                        extra[key] = config[keyVariant];
                    }
                }
            }
        }

        // Step 3: 处理 ExtraBotChange（bot 参数直接覆盖）——把已勾选 buff 对应的 bot 参数
        // 合并为一个 {bot参数名: 值} 字典，存入 extra_data_dict["ExtraBotChange"] 交由 TowerController
        // 传给 bot（TowerController 负责校验名称、覆盖对应参数、非法名报错）。
        var extra_bot = new Godot.Collections.Dictionary();
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.is_checked_state() && _extra_bot_change_map.ContainsKey(tb.box_id))
            {
                var paramsVariant = _extra_bot_change_map[tb.box_id];
                if (paramsVariant.VariantType == Variant.Type.Dictionary)
                {
                    var paramDict = paramsVariant.AsGodotDictionary();
                    foreach (var pkv in paramDict)
                        extra_bot[pkv.Key] = pkv.Value;
                }
            }
        }
        if (extra_bot.Count > 0)
            result["extra_data_dict"].AsGodotDictionary()["ExtraBotChange"] = extra_bot;

        return result;
    }

    /// <summary>生成指定 box 的显示文本（仅描述，不含倍率数据——倍率数据由 _update_summary_label 合并显示）</summary>
    public string _get_enhanced_label_text(string box_id)
    {
        string text = _display_text_map.ContainsKey(box_id) ? _display_text_map[box_id].AsString() : "";
        if (text.Length == 0)
            return "[" + box_id + "]";
        return text;
    }

    /// <summary>刷新所有已勾选框 Label 的显示文本</summary>
    public void _update_all_labels()
    {
        foreach (var boxIdVariant in _label_by_id.Keys)
        {
            string box_id = boxIdVariant.AsString();
            var label = _label_by_id[boxIdVariant].AsGodotObject() as Label;
            if (label != null)
                label.Text = _get_enhanced_label_text(box_id);
        }
    }

    /// <summary>更新合并效果汇总 Label（显示所有唯一 key 的累加倍率，去重合并）</summary>
    /// <summary>多个选框影响同一 key 时只显示一行，避免重复</summary>
    public void _update_summary_label()
    {
        var accumulated = _calculate_accumulated_multipliers();

        // 没有任何选框被勾选 → 隐藏汇总
        if (accumulated.Count == 0)
        {
            if (_summary_label != null)
                _summary_label.Hide();
            return;
        }

        var parts = new System.Collections.Generic.List<string>();
        foreach (var keyVariant in accumulated.Keys)
        {
            string key = keyVariant.AsString();
            if (key == "total_apm_buff_mult")
            {
                // 显示 APM 总倍率：显示原始 total_apm 和 buffed 后的值
                double mult = accumulated[keyVariant].AsDouble();
                double base_apm = tower_init_data.ContainsKey("total_apm") ? tower_init_data["total_apm"].AsDouble() : 70.0;
                double buffed_apm = base_apm * mult;
                double percent_change = (mult - 1.0) * 100.0;
                string sign_str = percent_change >= 0.0 ? "+" : "";
                parts.Add(string.Format("APM总量: {0:F1} → {1:F1} ({2}{3:F0}%)", base_apm, buffed_apm, sign_str, percent_change));
            }
        }

        // 仅当有重复 key 时才显示"合并效果"标题；只有一个 key 时直接显示
        bool has_duplicate = false;
        if (parts.Count > 1)
        {
            // 检查是否有一个 key 被多个选框影响（即 accumulated 中有不同的来源）
            // 简单判断：如果 parts 数量 < 已选框数量，说明有重复
            int checked_count = 0;
            foreach (var tbVariant in toggle_boxes)
            {
                var tb = _as_toggle(tbVariant);
                if (tb != null && tb.is_checked_state())
                    checked_count += 1;
            }
            if (checked_count > accumulated.Count)
                has_duplicate = true;
        }

        if (_summary_label == null)
        {
            _summary_label = new Label();
            _summary_label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(18 * 1.0f)));
            _summary_label.AddThemeColorOverride("font_color", new Color(0.8f, 0.8f, 1.0f, 1));
            buff_list.AddChild(_summary_label);
        }

        if (has_duplicate)
            _summary_label.Text = "━━ 合并效果 ━━\n" + string.Join("\n", parts);
        else
            _summary_label.Text = string.Join("\n", parts);
        _summary_label.Show();
    }

    // ========== 挑战组合 ==========

    /// <summary>根据组名获取对应的box_id列表（精确匹配优先，失败时尝试大小写不敏感匹配）</summary>
    /// <summary>兼容JSON中组名大小写差异（如 "Nohold" vs "NoHold"）</summary>
    public Godot.Collections.Array _get_group_box_ids(string group_name)
    {
        if (_buff_group_map.ContainsKey(group_name))
            return _buff_group_map[group_name].AsGodotArray();
        string lower_name = group_name.ToLower();
        foreach (var keyVariant in _buff_group_map.Keys)
        {
            string key = keyVariant.AsString();
            if (key.ToLower() == lower_name)
                return _buff_group_map[keyVariant].AsGodotArray();
        }
        return new Godot.Collections.Array();
    }

    /// <summary>判断某名称是否为有效的单个buff（存在对应ToggleBox，或在BuffChange/BuffInfo数据中已定义）</summary>
    /// <summary>供挑战组合在buffGroup内找不到时回退到单个buff查找使用</summary>
    public bool _is_valid_buff(string box_id)
    {
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.box_id == box_id)
                return true;
        }
        return _buff_config_map.ContainsKey(box_id) || _display_text_map.ContainsKey(box_id);
    }

    /// <summary>解析颜色字段（支持 [r,g,b]/[r,g,b,a] 数组或 "#rrggbb" 字符串），失败返回 null</summary>
    public Variant _parse_color(Variant value)
    {
        if (value.VariantType == Variant.Type.Array)
        {
            var arr = value.AsGodotArray();
            if (arr.Count >= 3)
            {
                float a = 1.0f;
                if (arr.Count >= 4)
                    a = arr[3].AsSingle();
                return new Color(arr[0].AsSingle(), arr[1].AsSingle(), arr[2].AsSingle(), a);
            }
        }
        else if (value.VariantType == Variant.Type.String)
        {
            string s = value.AsString();
            if (Color.HtmlIsValid(s))
                return Color.FromHtml(s);
        }
        return new Variant();
    }

    /// <summary>更新挑战组合显示：当已选框恰好（且仅）等于某组合Group内的全部box时，</summary>
    /// <summary>在buff列表末尾显示 "挑战组合：XXXX"（XXXX为该组合的Info内容）</summary>
    /// <summary>Color字段为预留颜色读取字段，未读取到（或格式错误）时使用文本默认颜色</summary>
    public void _update_combination_label()
    {
        if (buff_list == null)
            return;

        // 当前已选框集合
        var selected = _str_list(get_checked_toggle_ids());
        selected.Sort();

        var matched_texts = new System.Collections.Generic.List<string>();
        Color matched_color = Colors.White;
        bool has_color = false;

        foreach (var combNameVariant in _combination_map.Keys)
        {
            string comb_name = combNameVariant.AsString();
            Variant combVariant = _combination_map[combNameVariant];
            if (combVariant.VariantType != Variant.Type.Dictionary)
                continue;
            var comb = combVariant.AsGodotDictionary();
            if (!comb.ContainsKey("Group"))
                continue;

            // 汇总该组合Group内所有组对应的box_id
            var expected = new System.Collections.Generic.List<string>();
            bool group_valid = true;
            foreach (var groupNameVariant in comb["Group"].AsGodotArray())
            {
                string gname = groupNameVariant.AsString();
                var ids = new System.Collections.Generic.List<string>();
                foreach (var idVariant in _get_group_box_ids(gname))
                    ids.Add(idVariant.AsString());
                if (ids.Count == 0)
                {
                    // buffGroup内找不到：回退为单个buff（box_id）查找
                    if (_is_valid_buff(gname))
                        ids.Add(gname);
                    else
                    {
                        group_valid = false;
                        GD.PushError(string.Format("挑战组合 {0} 引用的组或单个buff不存在: {1}", comb_name, gname));
                        break;
                    }
                }
                expected.AddRange(ids);
            }
            if (!group_valid)
                continue;
            expected.Sort();

            // 且仅满足：已选框集合与组合期望集合完全一致才显示
            if (!ListsEqual(selected, expected))
                continue;

            string info_text = comb.ContainsKey("Info") ? comb["Info"].AsString() : "";
            if (info_text.Length == 0)
                info_text = comb_name;
            matched_texts.Add(info_text);

            // 预留color读取字段：存在且可解析时使用，否则保持文本默认颜色
            if (!has_color && comb.ContainsKey("Color"))
            {
                Variant c = _parse_color(comb["Color"]);
                if (c.VariantType != Variant.Type.Nil)
                {
                    matched_color = c.AsColor();
                    has_color = true;
                }
            }
        }

        if (matched_texts.Count == 0)
        {
            if (_combination_label != null)
                _combination_label.Hide();
            return;
        }

        if (_combination_label == null)
        {
            _combination_label = new Label();
            _combination_label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(20 * 1.0f)));
            buff_list.AddChild(_combination_label);
        }

        _combination_label.Text = "挑战组合：" + string.Join("\n", matched_texts);
        if (has_color)
            _combination_label.AddThemeColorOverride("font_color", matched_color);
        else
            _combination_label.RemoveThemeColorOverride("font_color");
        _combination_label.Show();
        // 确保显示在buff列表最后（位于汇总标签之后）
        buff_list.MoveChild(_combination_label, buff_list.GetChildCount() - 1);
    }

    private static bool ListsEqual(System.Collections.Generic.List<string> a, System.Collections.Generic.List<string> b)
    {
        if (a.Count != b.Count)
            return false;
        for (int i = 0; i < a.Count; i++)
        {
            if (a[i] != b[i])
                return false;
        }
        return true;
    }

    // ========== 组合勾选框（组合buff列） ==========

    /// <summary>判断某 box_id 是否为组合勾选框</summary>
    public bool _is_combo_box_id(string box_id)
    {
        return _combination_box_ids.ContainsKey(box_id);
    }

    /// <summary>提取 box_id 末尾的数字（如 "Talentless_2" -> 2，"ChangeBag_3" -> 3，无下划线数字则返回 0）</summary>
    public int _extract_trailing_number(string id_str)
    {
        int idx = id_str.RFind("_");
        if (idx == -1)
            return 0;
        string tail = id_str.Substring(idx + 1);
        if (tail.IsValidInt())
            return tail.ToInt();
        return 0;
    }

    /// <summary>从一组buff box_id中选出编号最低的一个（一般为I级，如 Talentless_1）</summary>
    public string _get_lowest_buff_id(Godot.Collections.Array ids)
    {
        if (ids.Count == 0)
            return "";
        string best = ids[0].AsString();
        int best_num = _extract_trailing_number(best);
        foreach (var idVariant in ids)
        {
            string s = idVariant.AsString();
            int n = _extract_trailing_number(s);
            if (n < best_num)
            {
                best = s;
                best_num = n;
            }
        }
        return best;
    }

    /// <summary>解析组合指向的buff集合：对Group内每一项，若是buff组则取编号最低的buff，</summary>
    /// <summary>若是单个buff则直接用该buff；返回去重后的box_id数组</summary>
    public Godot.Collections.Array _resolve_combination_buffs(string comb_name)
    {
        var result = new Godot.Collections.Array();
        if (!_combination_map.ContainsKey(comb_name))
            return result;
        var combVariant = _combination_map[comb_name];
        if (combVariant.VariantType != Variant.Type.Dictionary)
            return result;
        var comb = combVariant.AsGodotDictionary();
        if (!comb.ContainsKey("Group"))
            return result;
        foreach (var groupNameVariant in comb["Group"].AsGodotArray())
        {
            string gname = groupNameVariant.AsString();
            var ids = _get_group_box_ids(gname);
            if (ids.Count == 0)
            {
                // buffGroup内找不到：回退为单个buff（box_id）
                if (_is_valid_buff(gname))
                    ids = new Godot.Collections.Array() { gname };
                else
                    continue;
            }
            string chosen = _get_lowest_buff_id(ids);
            if (chosen.Length > 0 && !result.Contains(chosen))
                result.Add(chosen);
        }
        return result;
    }

    /// <summary>动态构建"组合buff"列（List14）：在ToggleGrid末尾新增一行，</summary>
    /// <summary>每个组合对应一个组合勾选框（box_id="Comb_组合名"）</summary>
    public void _build_combination_ui()
    {
        if (_combination_map.Count == 0)
            return;
        var grid = GetNodeOrNull<Control>("../TopArea/TopScrollContainer/ToggleGrid");
        if (grid == null)
            return;
        // 幂等：若已构建则跳过
        if (grid.GetNodeOrNull("List14") != null)
            return;

        var list = new HBoxContainer();
        list.Name = "List14";
        grid.AddChild(list);

        var lab = new Label();
        lab.Text = "组合buff：";
        lab.AddThemeFontSizeOverride("font_size", 20);
        list.AddChild(lab);

        // 连接线（可视分隔线，自动跟随行大小）
        var conn = new ToggleConnector();
        list.AddChild(conn);

        bool first = true;
        foreach (var combNameVariant in _combination_map.Keys)
        {
            string comb_name = combNameVariant.AsString();
            if (!first)
            {
                var sp = new Control();
                sp.CustomMinimumSize = new Vector2(16, 32);
                list.AddChild(sp);
            }
            first = false;

            var tb = new ToggleBox();
            tb.Name = comb_name;
            tb.box_id = "Comb_" + comb_name;
            tb.box_size = 32;
            tb.default_checked = false;
            tb.CustomMinimumSize = new Vector2(32, 32);
            tb.Size = new Vector2(32, 32);
            list.AddChild(tb);

            toggle_boxes.Add(tb);
            _combination_box_ids[tb.box_id] = comb_name;
            _combination_box_map[tb.box_id] = _resolve_combination_buffs(comb_name);
        }
    }

    /// <summary>组合勾选框状态切换处理</summary>
    /// <summary>勾选：先取消其他已勾选组合的buff及组合框，再勾选本组合指向的buff，最后勾选本组合框</summary>
    /// <summary>取消：仅取消本组合框，不影响已勾选的buff（buff仍可单独存在）</summary>
    public void _on_combo_box_toggled(string combo_box_id, bool is_checked)
    {
        if (_updating_combo)
            return;
        var tb = _find_toggle_box(combo_box_id);
        if (tb == null)
            return;
        if (!is_checked)
        {
            // 取消组合：只取消组合框，不取消其指向的buff
            return;
        }

        _updating_combo = true;
        // 1) 取消其它已勾选组合：先取消其buff，再取消其组合框
        foreach (var otherCbVariant in _combination_box_ids.Keys)
        {
            string other_cb = otherCbVariant.AsString();
            if (other_cb == combo_box_id)
                continue;
            var other_box = _find_toggle_box(other_cb);
            if (other_box != null && other_box.is_checked_state())
            {
                if (_combination_box_map.ContainsKey(other_cb))
                {
                    foreach (var bidVariant in _combination_box_map[other_cb].AsGodotArray())
                    {
                        string bid = bidVariant.AsString();
                        var btb = _find_toggle_box(bid);
                        if (btb != null && btb.is_checked_state())
                            btb.set_checked(false);
                    }
                }
                other_box.set_checked(false);
            }
        }
        // 2) 勾选本组合指向的buff
        if (_combination_box_map.ContainsKey(combo_box_id))
        {
            foreach (var bidVariant in _combination_box_map[combo_box_id].AsGodotArray())
            {
                string bid = bidVariant.AsString();
                var btb = _find_toggle_box(bid);
                if (btb != null && !btb.is_checked_state())
                    btb.set_checked(true);
            }
        }
        // 3) 勾选本组合框
        tb.set_checked(true);
        _updating_combo = false;

        // 刷新汇总/组合标签/组合勾选框
        _update_summary_label();
        _update_combination_label();
        _reconcile_combo_boxes();
    }

    /// <summary>根据当前已勾选的buff（排除组合框），若恰好形成某组合则勾选对应组合框，否则取消</summary>
    public void _reconcile_combo_boxes()
    {
        if (_updating_combo)
            return;
        var selected = _str_list(get_checked_toggle_ids());
        selected.Sort();
        foreach (var comboBoxIdVariant in _combination_box_map.Keys)
        {
            string combo_box_id = comboBoxIdVariant.AsString();
            var expected = new System.Collections.Generic.List<string>();
            foreach (var idVariant in _combination_box_map[comboBoxIdVariant].AsGodotArray())
                expected.Add(idVariant.AsString());
            expected.Sort();
            var cbtb = _find_toggle_box(combo_box_id);
            if (cbtb == null)
                continue;
            bool should_check = ListsEqual(selected, expected);
            if (cbtb.is_checked_state() != should_check)
            {
                _updating_combo = true;
                cbtb.set_checked(should_check);
                _updating_combo = false;
            }
        }
    }

    // ========== ToggleBox 回调 ==========

    /// <summary>任意 ToggleBox 切换时触发</summary>
    public void _on_toggle_box_toggled(string box_id, bool is_checked, Variant _value)
    {
        // 组合勾选框：走独立组合逻辑（勾选→勾选指向buff；取消→仅取消组合框）
        if (_is_combo_box_id(box_id))
        {
            _on_combo_box_toggled(box_id, is_checked);
            return;
        }

        if (is_checked)
        {
            _add_label_for_box(box_id);
            // 互斥逻辑：如果此选框属于某个互斥组，取消同组其他选框
            _uncheck_mutually_exclusive(box_id);
        }
        else
        {
            _remove_label_for_box(box_id);
        }

        // 添加/移除后重新排序，确保按 toggle_boxes 顺序从上到下排列
        _refresh_label_order();

        // 刷新所有标签显示（因为累积倍率可能变化）
        _update_all_labels();
        // 更新合并汇总（去重显示）
        _update_summary_label();
        // 更新挑战组合显示
        _update_combination_label();
        // 勾选/取消普通buff后，根据当前勾选是否恰好形成某组合来同步组合勾选框
        if (!_updating_combo)
            _reconcile_combo_boxes();
    }

    /// <summary>互斥逻辑：取消同组内其他选框的选中状态</summary>
    public void _uncheck_mutually_exclusive(string checked_box_id)
    {
        foreach (var groupNameVariant in _mutually_exclusive_groups.Keys)
        {
            var group = _mutually_exclusive_groups[groupNameVariant].AsGodotArray();
            bool belongs = false;
            foreach (var idVariant in group)
            {
                if (idVariant.AsString() == checked_box_id)
                {
                    belongs = true;
                    break;
                }
            }
            if (!belongs)
                continue;
            // 此选框属于该组，取消同组内其他选框
            foreach (var otherIdVariant in group)
            {
                string other_id = otherIdVariant.AsString();
                if (other_id == checked_box_id)
                    continue;
                // 查找对应的 ToggleBox 节点并取消选中
                foreach (var tbVariant in toggle_boxes)
                {
                    var tb = _as_toggle(tbVariant);
                    if (tb != null && tb.box_id == other_id && tb.is_checked_state())
                    {
                        tb.set_checked(false);
                        _remove_label_for_box(other_id);
                    }
                }
            }
        }
    }

    /// <summary>为指定 box 添加 Label（如果尚未添加）</summary>
    public void _add_label_for_box(string box_id)
    {
        if (buff_list == null)
            return;

        // 已存在则不重复添加
        if (_label_by_id.ContainsKey(box_id))
            return;

        var label = new Label();
        label.Text = _get_enhanced_label_text(box_id);
        label.AddThemeColorOverride("font_color", new Color(0.7f, 0.9f, 0.7f, 1));   // 统一绿色调

        label.AddThemeFontSizeOverride("font_size", Mathf.Max(12, (int)(20 * 1.0f)));

        _label_by_id[box_id] = label;
        buff_list.AddChild(label);
    }

    /// <summary>移除指定 box 的 Label</summary>
    public void _remove_label_for_box(string box_id)
    {
        if (buff_list == null)
            return;
        if (!_label_by_id.ContainsKey(box_id))
            return;

        var label = _label_by_id[box_id].AsGodotObject() as Label;
        if (label == null)
            return;

        buff_list.RemoveChild(label);
        label.QueueFree();
        _label_by_id.Remove(box_id);
    }

    /// <summary>将所有 Label 按 toggle_boxes 顺序重新排列（从上到下 = box_id 顺序）</summary>
    public void _refresh_label_order()
    {
        if (buff_list == null)
            return;

        // 按照 toggle_boxes 的顺序，收集所有已勾选的 box_id
        var checked_order = new System.Collections.Generic.List<string>();
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && _label_by_id.ContainsKey(tb.box_id))
                checked_order.Add(tb.box_id);
        }

        // 将 buff_list 的子节点按 checked_order 重排
        for (int i = 0; i < checked_order.Count; i++)
        {
            var label = _label_by_id[checked_order[i]].AsGodotObject() as Label;
            if (label == null)
                continue;
            // 如果该 Label 不在正确的位置，则移到最后再插入到正确位置
            if (buff_list.GetChild(i) != label)
                buff_list.MoveChild(label, i);
        }
    }

    // ========== 公开方法 ==========

    /// <summary>获取所有 ToggleBox 的状态列表（供外部批量读取）</summary>
    public Godot.Collections.Array get_all_toggle_states()
    {
        var result = new Godot.Collections.Array();
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null)
                result.Add(tb.get_state());
        }
        return result;
    }

    /// <summary>根据 id 获取指定 ToggleBox 的状态</summary>
    public Godot.Collections.Dictionary get_toggle_state_by_id(string box_id)
    {
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.box_id == box_id)
                return tb.get_state();
        }
        return new Godot.Collections.Dictionary();
    }

    /// <summary>根据 id 设置指定 ToggleBox 的选中状态</summary>
    public bool set_toggle_checked(string box_id, bool checked_value)
    {
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.box_id == box_id)
            {
                tb.set_checked(checked_value);
                return true;
            }
        }
        return false;
    }

    /// <summary>动态添加 ToggleBox</summary>
    public void add_toggle_box(ToggleBox tb)
    {
        if (tb != null && !toggle_boxes.Contains(tb))
        {
            toggle_boxes.Add(tb);
            tb.Toggled += _on_toggle_box_toggled;
        }
    }

    /// <summary>获取所有 ToggleBox 中处于选中（✓）状态的列表</summary>
    /// <summary>排除"组合buff"列的组合勾选框（它们不是真正的buff，不应参与buff生效/列表展示）</summary>
    public Godot.Collections.Array get_checked_toggle_ids()
    {
        var ids = new Godot.Collections.Array();
        foreach (var tbVariant in toggle_boxes)
        {
            var tb = _as_toggle(tbVariant);
            if (tb != null && tb.is_checked_state() && !_is_combo_box_id(tb.box_id))
                ids.Add(tb.box_id);
        }
        return ids;
    }

    // ========== 按钮回调 ==========

    public void _on_back_button_pressed()
    {
        //print("返回主菜单")
        GetTree().ChangeSceneToFile(main_menu_scene_path);
    }

    public void _on_start_button_pressed()
    {
        //print("开始游戏 - 进入俄罗斯方块")

        // 将应用了所有 buff/debuff 倍率的数据存入 GlobalData
        var buffed_data = get_buffed_tower_data();
        GlobalData.tower_init_data = buffed_data;
        //print("TowerController 数据（含 buff/debuff 倍率累加）已存入 GlobalData: ", GlobalData.tower_init_data)

        // 记录已选取的 buff（供结束界面右侧列表展示）
        var checked_ids = get_checked_toggle_ids();
        var buff_display = new Godot.Collections.Array();
        foreach (var bidVariant in checked_ids)
        {
            string bid = bidVariant.AsString();
            buff_display.Add(new Godot.Collections.Dictionary()
            {
                { "id", bid },
                { "text", _get_enhanced_label_text(bid) },
            });
        }
        GlobalData.selected_buffs = buff_display;

        GlobalData.reset_stats();
        GetTree().ChangeSceneToFile(game_scene_path);
    }

    private static System.Collections.Generic.List<string> _str_list(Godot.Collections.Array arr)
    {
        var l = new System.Collections.Generic.List<string>();
        foreach (var v in arr)
            l.Add(v.AsString());
        return l;
    }

    private ToggleBox _as_toggle(Variant v)
    {
        if (v.VariantType == Variant.Type.Object)
            return v.AsGodotObject() as ToggleBox;
        return null;
    }
}
