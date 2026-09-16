using Godot;

/// <summary>
/// 设置场景控制器
/// 负责键位配置、速度调整和设置保存
/// </summary>
public partial class SettingArea : Control
{
    // ========== 节点引用 ==========
    // 键位按钮
    [Export]
    public Button key_left_button;
    [Export]
    public Button key_right_button;
    [Export]
    public Button key_soft_drop_button;
    [Export]
    public Button key_hard_drop_button;
    [Export]
    public Button key_left_spin_button;
    [Export]
    public Button key_right_spin_button;
    [Export]
    public Button key_swap_spin_button;
    [Export]
    public Button key_hold_button;

    // 速度控制
    [Export]
    public HSlider das_slider;
    [Export]
    public Label das_value_label;
    [Export]
    public HSlider arr_slider;
    [Export]
    public Label arr_value_label;
    [Export]
    public HSlider softdrop_slider;
    [Export]
    public Label softdrop_value_label;

    // 按钮
    [Export]
    public Button save_button;
    [Export]
    public Button reset_button;
    [Export]
    public Button back_button;

    // 提示标签
    [Export]
    public Label hint_label;

    // ========== 状态变量 ==========
    public Godot.Collections.Dictionary current_settings = new Godot.Collections.Dictionary();
    public bool waiting_for_key = false;
    public string waiting_key_action = "";
    public Button waiting_button = null;

    // 键位动作列表
    public Godot.Collections.Array action_list = new Godot.Collections.Array()
    {
        "LeftMove", "RightMove", "SoftDrop", "HardDrop",
        "LeftSpin", "RightSpin", "SwapSpin", "HoldBlock",
    };

    // 动作名 → 按钮映射
    public Godot.Collections.Dictionary action_to_button = new Godot.Collections.Dictionary();

    // 动作名 → 设置键名映射
    public Godot.Collections.Dictionary action_to_setting_key = new Godot.Collections.Dictionary()
    {
        { "LeftMove", "key_left" },
        { "RightMove", "key_right" },
        { "SoftDrop", "key_soft_drop" },
        { "HardDrop", "key_hard_drop" },
        { "LeftSpin", "key_left_spin" },
        { "RightSpin", "key_right_spin" },
        { "SwapSpin", "key_swap_spin" },
        { "HoldBlock", "key_hold" },
    };

    public override void _Ready()
    {
        // 构建按钮映射
        action_to_button = new Godot.Collections.Dictionary()
        {
            { "LeftMove", key_left_button },
            { "RightMove", key_right_button },
            { "SoftDrop", key_soft_drop_button },
            { "HardDrop", key_hard_drop_button },
            { "LeftSpin", key_left_spin_button },
            { "RightSpin", key_right_spin_button },
            { "SwapSpin", key_swap_spin_button },
            { "HoldBlock", key_hold_button },
        };

        // 加载设置
        _load_settings();

        // 连接信号
        _connect_signals();

        // 更新UI
        _update_ui();

        // 设置滑块样式
        _setup_slider_styles();
    }

    /// <summary>加载设置</summary>
    public void _load_settings()
    {
        if (UserSetting.setting_file_exists())
        {
            current_settings = UserSetting.load_settings();
            // 应用键位到InputMap
            UserSetting.apply_key_bindings_from_dict(current_settings);
            // 已注释（调试噪音）：print("已加载用户设置")
        }
        else
        {
            current_settings = UserSetting.get_default_settings();
            UserSetting.apply_default_key_bindings();
            // 已注释（调试噪音）：print("未找到配置文件，使用默认设置")
        }
    }

    /// <summary>连接信号</summary>
    public void _connect_signals()
    {
        // 键位按钮
        if (key_left_button != null)
            key_left_button.Pressed += () => _on_key_button_pressed("LeftMove", key_left_button);
        if (key_right_button != null)
            key_right_button.Pressed += () => _on_key_button_pressed("RightMove", key_right_button);
        if (key_soft_drop_button != null)
            key_soft_drop_button.Pressed += () => _on_key_button_pressed("SoftDrop", key_soft_drop_button);
        if (key_hard_drop_button != null)
            key_hard_drop_button.Pressed += () => _on_key_button_pressed("HardDrop", key_hard_drop_button);
        if (key_left_spin_button != null)
            key_left_spin_button.Pressed += () => _on_key_button_pressed("LeftSpin", key_left_spin_button);
        if (key_right_spin_button != null)
            key_right_spin_button.Pressed += () => _on_key_button_pressed("RightSpin", key_right_spin_button);
        if (key_swap_spin_button != null)
            key_swap_spin_button.Pressed += () => _on_key_button_pressed("SwapSpin", key_swap_spin_button);
        if (key_hold_button != null)
            key_hold_button.Pressed += () => _on_key_button_pressed("HoldBlock", key_hold_button);

        // 速度滑条
        if (das_slider != null)
            das_slider.ValueChanged += _on_das_changed;
        if (arr_slider != null)
            arr_slider.ValueChanged += _on_arr_changed;
        if (softdrop_slider != null)
            softdrop_slider.ValueChanged += _on_softdrop_changed;

        // 按钮
        if (save_button != null)
            save_button.Pressed += _on_save_pressed;
        if (reset_button != null)
            reset_button.Pressed += _on_reset_pressed;
        if (back_button != null)
            back_button.Pressed += _on_back_pressed;
    }

    /// <summary>设置滑块样式</summary>
    public void _setup_slider_styles()
    {
        var sliders = new Godot.Collections.Array() { das_slider, arr_slider, softdrop_slider };
        foreach (var sliderVariant in sliders)
        {
            var slider = sliderVariant.As<Slider>();
            if (slider != null)
                slider.CustomMinimumSize = new Vector2(200, 0);
        }
    }

    /// <summary>更新UI</summary>
    public void _update_ui()
    {
        // 更新键位按钮文本 - 从InputMap读取实际按键
        foreach (var actionObj in action_list)
        {
            string action = actionObj.AsString();
            var button = action_to_button[action].As<Button>();
            if (button != null)
            {
                string key_name = UserSetting.get_key_name_for_action(action);
                if (key_name.Length == 0)
                    key_name = "未绑定";
                button.Text = key_name;
            }
        }

        // 更新速度值
        if (das_slider != null)
            das_slider.Value = _get_setting_double("move_das", 0.1) * 100;
        if (das_value_label != null)
            das_value_label.Text = string.Format("{0:F3}s", _get_setting_double("move_das", 0.1));

        if (arr_slider != null)
            arr_slider.Value = _get_setting_double("move_arr", 0.0) * 100;
        if (arr_value_label != null)
            arr_value_label.Text = string.Format("{0:F3}s", _get_setting_double("move_arr", 0.0));

        if (softdrop_slider != null)
            softdrop_slider.Value = _get_setting_double("softdrop_delay", 0.1) * 100;
        if (softdrop_value_label != null)
            softdrop_value_label.Text = string.Format("{0:F3}s", _get_setting_double("softdrop_delay", 0.1));
    }

    private double _get_setting_double(string key, double default_value)
    {
        if (current_settings.ContainsKey(key))
            return current_settings[key].AsDouble();
        return default_value;
    }

    /// <summary>更新单个键位按钮</summary>
    public void _update_key_button(Button button, string action)
    {
        if (button != null)
        {
            string key_name = UserSetting.get_key_name_for_action(action);
            if (key_name.Length == 0)
                key_name = "未绑定";
            button.Text = key_name;
        }
    }

    // ========== 键位设置 ==========

    /// <summary>键位按钮按下</summary>
    public void _on_key_button_pressed(string action, Button button)
    {
        if (waiting_for_key)
            _cancel_waiting();

        waiting_for_key = true;
        waiting_key_action = action;
        waiting_button = button;
        button.Text = "按下按键...";

        if (hint_label != null)
            hint_label.Text = "请按下要绑定的按键...";
    }

    /// <summary>取消等待</summary>
    public void _cancel_waiting()
    {
        waiting_for_key = false;
        waiting_key_action = "";
        if (waiting_button != null)
        {
            _update_key_button(waiting_button, waiting_key_action);
            waiting_button = null;
        }
        if (hint_label != null)
            hint_label.Text = "";
    }

    /// <summary>处理按键输入</summary>
    public override void _Input(InputEvent @event)
    {
        if (!waiting_for_key)
            return;

        if (@event is InputEventKey keyEvent && keyEvent.Pressed && !keyEvent.Echo)
        {
            var keycode = keyEvent.Keycode;
            string key_name = OS.GetKeycodeString(keycode);

            // 清除其他动作中相同的按键（覆盖模式）
            _clear_conflicting_keys((long)keycode);

            // 更新设置
            _set_key_for_action(waiting_key_action, (long)keycode);

            // 更新按钮显示
            if (waiting_button != null)
                waiting_button.Text = key_name;

            // 重置等待状态
            waiting_for_key = false;
            waiting_key_action = "";
            waiting_button = null;

            if (hint_label != null)
                hint_label.Text = string.Format("按键已绑定: {0}", key_name);
        }
    }

    /// <summary>清除其他动作中指定的按键（覆盖模式）</summary>
    /// <summary>当新绑定的按键已被其他动作使用时，清除其他动作中的该按键</summary>
    public void _clear_conflicting_keys(long keycode)
    {
        string key_name = OS.GetKeycodeString((Godot.Key)keycode);
        foreach (var actionObj in action_list)
        {
            string action = actionObj.AsString();
            if (action == waiting_key_action)
                continue;

            var events = InputMap.ActionGetEvents(action);
            bool has_conflict = false;
            foreach (var ev in events)
            {
                if (ev is InputEventKey k && (long)k.Keycode == keycode)
                {
                    has_conflict = true;
                    break;
                }
            }

            if (has_conflict)
            {
                // 清除该动作的按键
                InputMap.ActionEraseEvents(action);

                // 更新对应的按钮显示为"未绑定"
                if (action_to_button.ContainsKey(action))
                {
                    var button = action_to_button[action].As<Button>();
                    if (button != null)
                        button.Text = "未绑定";
                }

                // 已注释（调试噪音）：print("按键覆盖：动作 \"%s\" 的按键 \"%s\" 已被动作 \"%s\" 覆盖" % [action, key_name, waiting_key_action])
            }
        }
    }

    /// <summary>设置按键到动作</summary>
    public void _set_key_for_action(string action, long keycode)
    {
        // 清除原有按键
        InputMap.ActionEraseEvents(action);

        // 创建新按键事件
        var key_event = new InputEventKey();
        key_event.Keycode = (Godot.Key)keycode;
        InputMap.ActionAddEvent(action, key_event);

        // 获取按键名称
        string key_name = OS.GetKeycodeString((Godot.Key)keycode);

        // 更新设置字典中的按键名称
        string setting_key = action_to_setting_key[action].AsString();
        current_settings[setting_key] = key_name;
    }

    // ========== 速度调整 ==========

    public void _on_das_changed(double value)
    {
        current_settings["move_das"] = value / 100.0;
        if (das_value_label != null)
            das_value_label.Text = string.Format("{0:F3}s", (double)current_settings["move_das"]);
    }

    public void _on_arr_changed(double value)
    {
        current_settings["move_arr"] = value / 100.0;
        if (arr_value_label != null)
            arr_value_label.Text = string.Format("{0:F3}s", (double)current_settings["move_arr"]);
    }

    public void _on_softdrop_changed(double value)
    {
        current_settings["softdrop_delay"] = value / 100.0;
        if (softdrop_value_label != null)
            softdrop_value_label.Text = string.Format("{0:F3}s", (double)current_settings["softdrop_delay"]);
    }

    // ========== 按钮功能 ==========

    /// <summary>保存设置</summary>
    public async void _on_save_pressed()
    {
        if (UserSetting.save_settings(current_settings))
        {
            if (hint_label != null)
            {
                hint_label.Text = "设置已保存！";
                await ToSignal(GetTree().CreateTimer(2.0), SceneTreeTimer.SignalName.Timeout);
                if (hint_label != null && hint_label.Text == "设置已保存！")
                    hint_label.Text = "";
            }
        }
        else
        {
            if (hint_label != null)
            {
                hint_label.Text = "保存失败！";
                await ToSignal(GetTree().CreateTimer(2.0), SceneTreeTimer.SignalName.Timeout);
                if (hint_label != null && hint_label.Text == "保存失败！")
                    hint_label.Text = "";
            }
        }
    }

    /// <summary>重置为默认设置</summary>
    public async void _on_reset_pressed()
    {
        // 获取默认设置
        current_settings = UserSetting.get_default_settings();

        // 应用默认键位到InputMap
        UserSetting.apply_default_key_bindings();

        // 更新UI
        _update_ui();

        if (hint_label != null)
        {
            hint_label.Text = "已重置为默认设置！";
            await ToSignal(GetTree().CreateTimer(2.0), SceneTreeTimer.SignalName.Timeout);
            if (hint_label != null && hint_label.Text == "已重置为默认设置！")
                hint_label.Text = "";
        }
    }

    /// <summary>返回主菜单</summary>
    public void _on_back_pressed()
    {
        // 保存设置
        UserSetting.save_settings(current_settings);
        GetTree().ChangeSceneToFile("res://Tscns/main_menu.tscn");
    }

    /// <summary>获取设置（供其他场景使用）</summary>
    public Godot.Collections.Dictionary get_settings()
    {
        return current_settings;
    }
}
