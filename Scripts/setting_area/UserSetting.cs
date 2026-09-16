using Godot;

/// <summary>
/// 用户设置数据类
/// 使用JSON格式保存和加载用户自定义设置
/// </summary>
public partial class UserSetting : Resource
{
    public const string SAVEFILE_PATH = "user://Savedatas/user_setting.json";

    /// <summary>默认键位映射（动作名称 → 按键代码）</summary>
    public static Godot.Collections.Dictionary get_default_key_bindings()
    {
        return new Godot.Collections.Dictionary()
        {
            { "LeftMove", (long)Godot.Key.Left },
            { "RightMove", (long)Godot.Key.Right },
            { "SoftDrop", (long)Godot.Key.Down },
            { "HardDrop", (long)Godot.Key.Space },
            { "LeftSpin", (long)Godot.Key.Z },
            { "RightSpin", (long)Godot.Key.X },
            { "SwapSpin", (long)Godot.Key.A },
            { "HoldBlock", (long)Godot.Key.C },
        };
    }

    /// <summary>默认键位名称映射（动作名称 → 按键名称字符串）</summary>
    public static Godot.Collections.Dictionary get_default_key_names()
    {
        return new Godot.Collections.Dictionary()
        {
            { "LeftMove", "Left" },
            { "RightMove", "Right" },
            { "SoftDrop", "Down" },
            { "HardDrop", "Space" },
            { "LeftSpin", "Z" },
            { "RightSpin", "X" },
            { "SwapSpin", "A" },
            { "HoldBlock", "C" },
        };
    }

    /// <summary>获取默认设置字典</summary>
    public static Godot.Collections.Dictionary get_default_settings()
    {
        return new Godot.Collections.Dictionary()
        {
            // 键位设置（存储按键名称字符串，如 "Z", "X", "Left" 等）
            { "key_left", "Left" },
            { "key_right", "Right" },
            { "key_soft_drop", "Down" },
            { "key_hard_drop", "Space" },
            { "key_left_spin", "Z" },
            { "key_right_spin", "X" },
            { "key_swap_spin", "A" },
            { "key_hold", "C" },
            // 速度设置
            { "move_das", 0.1 },
            { "move_arr", 0.0 },
            { "softdrop_delay", 0.1 },
        };
    }

    /// <summary>动作名称列表</summary>
    public static Godot.Collections.Array get_action_list()
    {
        return new Godot.Collections.Array()
        {
            "LeftMove", "RightMove", "SoftDrop", "HardDrop",
            "LeftSpin", "RightSpin", "SwapSpin", "HoldBlock",
        };
    }

    /// <summary>动作名称 → 设置键名映射</summary>
    public static Godot.Collections.Dictionary get_action_to_setting_key()
    {
        return new Godot.Collections.Dictionary()
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
    }

    /// <summary>从按键名称获取按键代码</summary>
    public static long get_keycode_from_name(string key_name)
    {
        // 处理特殊按键名称
        switch (key_name)
        {
            case "Left": return (long)Godot.Key.Left;
            case "Right": return (long)Godot.Key.Right;
            case "Up": return (long)Godot.Key.Up;
            case "Down": return (long)Godot.Key.Down;
            case "Space": return (long)Godot.Key.Space;
            case "Enter": return (long)Godot.Key.Enter;
            case "Escape": return (long)Godot.Key.Escape;
            case "Tab": return (long)Godot.Key.Tab;
            case "Shift": return (long)Godot.Key.Shift;
            case "Ctrl": return (long)Godot.Key.Ctrl;
            case "Alt": return (long)Godot.Key.Alt;
            default:
                // 尝试直接查找
                long keycode = (long)OS.FindKeycodeFromString(key_name);
                if (keycode != 0)
                    return keycode;
                return -1;
        }
    }

    /// <summary>从按键代码获取按键名称</summary>
    public static string get_key_name_from_keycode(long keycode)
    {
        return OS.GetKeycodeString((Godot.Key)keycode);
    }

    /// <summary>获取动作对应的按键名称（从InputMap读取）</summary>
    public static string get_key_name_for_action(string action)
    {
        var events = InputMap.ActionGetEvents(action);
        if (events.Count == 0)
            return "";
        var ev = events[0];
        if (ev is InputEventKey keyEvent)
            return OS.GetKeycodeString(keyEvent.Keycode);
        return "";
    }

    /// <summary>应用默认键位到InputMap</summary>
    public static void apply_default_key_bindings()
    {
        var defaults = get_default_key_bindings();
        foreach (var entry in defaults)
        {
            string action = entry.Key.ToString();
            long keycode = (long)entry.Value;
            InputMap.ActionEraseEvents(action);
            var key_event = new InputEventKey();
            key_event.Keycode = (Godot.Key)keycode;
            InputMap.ActionAddEvent(action, key_event);
        }
    }

    /// <summary>从设置字典应用键位到InputMap</summary>
    public static void apply_key_bindings_from_dict(Godot.Collections.Dictionary settings)
    {
        var action_list = get_action_list();
        var action_to_key = get_action_to_setting_key();

        foreach (var actionObj in action_list)
        {
            string action = actionObj.ToString();
            string setting_key = (string)action_to_key[action];
            if (settings.ContainsKey(setting_key))
            {
                string key_name = settings[setting_key].ToString();
                long keycode = get_keycode_from_name(key_name);
                if (keycode != -1)
                {
                    // 清除原有按键
                    InputMap.ActionEraseEvents(action);
                    // 创建新按键事件
                    var key_event = new InputEventKey();
                    key_event.Keycode = (Godot.Key)keycode;
                    InputMap.ActionAddEvent(action, key_event);
                }
                else
                {
                    // 已注释（调试噪音）：print("警告: 未知按键名称 ", key_name, " 用于动作 ", action)
                }
            }
        }
    }

    /// <summary>获取当前所有动作的按键名称（用于保存）</summary>
    public static Godot.Collections.Dictionary get_current_key_names()
    {
        var result = new Godot.Collections.Dictionary();
        var action_list = get_action_list();
        var action_to_key = get_action_to_setting_key();

        foreach (var actionObj in action_list)
        {
            string action = actionObj.ToString();
            string key_name = get_key_name_for_action(action);
            if (key_name.Length == 0)
            {
                // 如果未绑定，使用默认值
                var default_names = get_default_key_names();
                key_name = default_names.ContainsKey(action) ? default_names[action].ToString() : "";
            }
            string setting_key = (string)action_to_key[action];
            result[setting_key] = key_name;
        }

        return result;
    }

    /// <summary>保存设置到JSON文件</summary>
    public static bool save_settings(Godot.Collections.Dictionary settings)
    {
        var dir = DirAccess.Open("user://Savedatas");
        if (dir == null)
            DirAccess.MakeDirRecursiveAbsolute("user://Savedatas");

        string json_string = Json.Stringify(settings, "\t");
        using var file = FileAccess.Open(SAVEFILE_PATH, FileAccess.ModeFlags.Write);
        if (file != null)
        {
            file.StoreString(json_string);
            // 已注释（调试噪音）：print("设置已保存到: ", SAVEFILE_PATH)
            return true;
        }
        else
        {
            GD.PushError("保存设置失败: ", SAVEFILE_PATH);
            return false;
        }
    }

    /// <summary>从JSON文件加载设置</summary>
    public static Godot.Collections.Dictionary load_settings()
    {
        if (!FileAccess.FileExists(SAVEFILE_PATH))
        {
            // 已注释（调试噪音）：print("配置文件不存在，使用默认设置")
            return get_default_settings();
        }

        using var file = FileAccess.Open(SAVEFILE_PATH, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError("无法打开配置文件: ", SAVEFILE_PATH);
            return get_default_settings();
        }

        string json_string = file.GetAsText();

        var json = new Json();
        Error error = json.Parse(json_string);
        if (error != Error.Ok)
        {
            GD.PushError("解析配置文件失败: ", json.GetErrorMessage());
            return get_default_settings();
        }

        var data = json.Data;
        if (data.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError("配置文件格式错误");
            return get_default_settings();
        }

        var dict = data.AsGodotDictionary();
        // 合并默认值（确保所有字段都存在）
        var default_settings = get_default_settings();
        foreach (var key in default_settings.Keys)
        {
            if (!dict.ContainsKey(key))
                dict[key] = default_settings[key];
        }

        // 已注释（调试噪音）：print("设置已加载: ", SAVEFILE_PATH)
        return dict;
    }

    /// <summary>检查配置文件是否存在</summary>
    public static bool setting_file_exists()
    {
        return FileAccess.FileExists(SAVEFILE_PATH);
    }

    /// <summary>初始化设置（游戏启动时调用）</summary>
    public static void initialize_settings()
    {
        if (setting_file_exists())
        {
            var settings = load_settings();
            apply_key_bindings_from_dict(settings);
            // 已注释（调试噪音）：print("已加载用户设置")
        }
        else
        {
            var default_settings = get_default_settings();
            save_settings(default_settings);
            apply_default_key_bindings();
            // 已注释（调试噪音）：print("未找到配置文件，已创建默认设置")
        }
    }
}
