using Godot;

/// <summary>
/// 回放数据类
/// 存储游戏回放所需的所有数据
/// </summary>
public partial class ReplayData : Resource
{
    // ========== 元数据 ==========
    public string version = "1.0";
    public long timestamp = 0;
    public string player_name = "Player";
    public double game_duration = 0.0;
    public long random_seed = 0;
    public long total_frames = 0;
    public double total_time = 0.0;

    // ========== 设置数据 ==========
    public float move_das = 0.1f;
    public float move_arr = 0.0f;
    public float softdrop_delay = 0.1f;

    // ========== 游戏数据 ==========
    public Godot.Collections.Array bag_sequence = new Godot.Collections.Array();
    public Godot.Collections.Array input_events = new Godot.Collections.Array();
    public double game_start_time = 0.0;

    // ========== 统计数据 ==========
    public Godot.Collections.Dictionary final_stats = new Godot.Collections.Dictionary()
    {
        { "pps", 0.0 },
        { "apm", 0.0 },
        { "rpm", 0.0 },
        { "max_combo", (long)0 },
        { "max_btb", (long)0 },
        { "total_lines", (long)0 },
        { "total_pieces", (long)0 },
        { "total_attacks", (long)0 },
        { "total_spins", (long)0 }
    };

    /// <summary>创建默认回放数据</summary>
    public static ReplayData create_default()
    {
        var data = new ReplayData();
        data.version = "1.0";
        data.timestamp = (long)Time.GetUnixTimeFromSystem();
        data.player_name = "Player";
        data.game_duration = 0.0;
        data.random_seed = 0;
        data.total_time = 0.0;
        data.move_das = 0.1f;
        data.move_arr = 0.0f;
        data.softdrop_delay = 0.1f;
        data.bag_sequence = new Godot.Collections.Array();
        data.input_events = new Godot.Collections.Array();
        data.game_start_time = 0.0;
        data.final_stats = new Godot.Collections.Dictionary()
        {
            { "pps", 0.0 },
            { "apm", 0.0 },
            { "rpm", 0.0 },
            { "max_combo", (long)0 },
            { "max_btb", (long)0 },
            { "total_lines", (long)0 },
            { "total_pieces", (long)0 },
            { "total_attacks", (long)0 },
            { "total_spins", (long)0 }
        };
        return data;
    }

    /// <summary>添加输入事件</summary>
    public void add_input_event(float time, string action, bool pressed)
    {
        input_events.Add(new Godot.Collections.Dictionary()
        {
            { "time", time },
            { "action", action },
            { "pressed", pressed }
        });
    }

    /// <summary>设置完整的Bag序列</summary>
    public void set_bag_sequence(Godot.Collections.Array sequence)
    {
        bag_sequence = (Godot.Collections.Array)sequence.Duplicate();
    }

    /// <summary>获取当前Bag序列的副本</summary>
    public Godot.Collections.Array get_bag_sequence_copy()
    {
        return (Godot.Collections.Array)bag_sequence.Duplicate();
    }

    /// <summary>保存到JSON文件</summary>
    public bool save_to_file(string file_path)
    {
        var data_dict = _to_dict();
        string json_string = Json.Stringify(data_dict, "\t");
        using var file = FileAccess.Open(file_path, FileAccess.ModeFlags.Write);
        if (file != null)
        {
            file.StoreString(json_string);
            GD.Print("回放数据已保存: ", file_path);
            return true;
        }
        else
        {
            GD.PushError("保存回放数据失败: ", file_path);
            return false;
        }
    }

    /// <summary>从JSON文件加载</summary>
    public static ReplayData load_from_file(string file_path)
    {
        if (!FileAccess.FileExists(file_path))
        {
            GD.PushError("回放文件不存在: ", file_path);
            return null;
        }

        using var file = FileAccess.Open(file_path, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError("无法打开回放文件: ", file_path);
            return null;
        }

        string json_string = file.GetAsText();

        var json = new Json();
        Error error = json.Parse(json_string);
        if (error != Error.Ok)
        {
            GD.PushError("解析回放文件失败: ", json.GetErrorMessage());
            return null;
        }

        var data = json.Data;
        if (data.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError("回放文件格式错误");
            return null;
        }

        return _from_dict(data.AsGodotDictionary());
    }

    /// <summary>转换为字典</summary>
    public Godot.Collections.Dictionary _to_dict()
    {
        return new Godot.Collections.Dictionary()
        {
            { "version", version },
            { "timestamp", timestamp },
            { "player_name", player_name },
            { "game_duration", game_duration },
            { "random_seed", random_seed },
            { "total_frames", total_frames },
            { "total_time", total_time },
            { "move_das", move_das },
            { "move_arr", move_arr },
            { "softdrop_delay", softdrop_delay },
            { "bag_sequence", (Godot.Collections.Array)bag_sequence.Duplicate() },
            { "input_events", (Godot.Collections.Array)input_events.Duplicate() },
            { "game_start_time", game_start_time },
            { "final_stats", (Godot.Collections.Dictionary)final_stats.Duplicate() }
        };
    }

    /// <summary>从字典创建</summary>
    public static ReplayData _from_dict(Godot.Collections.Dictionary data)
    {
        var replay = new ReplayData();
        replay.version = data.ContainsKey("version") ? data["version"].AsString() : "1.0";
        replay.timestamp = data.ContainsKey("timestamp") ? data["timestamp"].AsInt64() : 0;
        replay.player_name = data.ContainsKey("player_name") ? data["player_name"].AsString() : "Player";
        replay.game_duration = data.ContainsKey("game_duration") ? data["game_duration"].AsDouble() : 0.0;
        replay.random_seed = data.ContainsKey("random_seed") ? data["random_seed"].AsInt64() : 0;
        replay.total_frames = data.ContainsKey("total_frames") ? data["total_frames"].AsInt64() : 0;

        // 检测是否为旧格式（只有 total_frames，没有 total_time）
        bool is_old_format = !data.ContainsKey("total_time");
        double fallback_duration = data.ContainsKey("game_duration") ? data["game_duration"].AsDouble() : 0.0;
        if (fallback_duration <= 0.0 && replay.total_frames > 0)
            fallback_duration = (double)replay.total_frames / 60.0;
        replay.total_time = data.ContainsKey("total_time") ? data["total_time"].AsDouble() : fallback_duration;

        replay.move_das = data.ContainsKey("move_das") ? data["move_das"].AsSingle() : 0.1f;
        replay.move_arr = data.ContainsKey("move_arr") ? data["move_arr"].AsSingle() : 0.0f;
        replay.softdrop_delay = data.ContainsKey("softdrop_delay") ? data["softdrop_delay"].AsSingle() : 0.1f;
        replay.bag_sequence = data.ContainsKey("bag_sequence") ? (Godot.Collections.Array)data["bag_sequence"].AsGodotArray().Duplicate() : new Godot.Collections.Array();
        replay.game_start_time = data.ContainsKey("game_start_time") ? data["game_start_time"].AsDouble() : 0.0;

        // 兼容旧格式：input_frames → input_events
        if (data.ContainsKey("input_frames") && data["input_frames"].AsGodotArray().Count > 0 && !data.ContainsKey("input_events"))
        {
            replay.input_events = _convert_frames_to_events(data["input_frames"].AsGodotArray());
        }
        else
        {
            var raw_events = data.ContainsKey("input_events") ? data["input_events"].AsGodotArray() : new Godot.Collections.Array();
            // 旧格式 time 存的是帧编号（非秒数），需要转换为秒
            if (is_old_format && raw_events.Count > 0)
            {
                var first_dict = raw_events[0].AsGodotDictionary();
                double first_time = first_dict.ContainsKey("time") ? first_dict["time"].AsDouble() : 0.0;
                // 如果时间值较大（>60），说明是用帧编号存储的旧格式
                if (first_time > 10.0 || replay.total_frames > 100)
                {
                    foreach (Variant evtVariant in raw_events)
                    {
                        var evt = evtVariant.AsGodotDictionary();
                        if (evt.ContainsKey("time"))
                            evt["time"] = evt["time"].AsDouble() / 60.0;
                    }
                }
            }
            replay.input_events = raw_events;
        }

        replay.final_stats = data.ContainsKey("final_stats") ? (Godot.Collections.Dictionary)data["final_stats"].AsGodotDictionary().Duplicate() : new Godot.Collections.Dictionary();

        // 确保事件按时间排序
        // （Godot.Collections.Array 无 sort_custom，转 List 排序后重建 Array）
        var sorted_events = new System.Collections.Generic.List<Godot.Collections.Dictionary>();
        foreach (Variant evtVariant in replay.input_events)
            sorted_events.Add(evtVariant.AsGodotDictionary());
        sorted_events.Sort((a, b) =>
        {
            double ta = a.ContainsKey("time") ? a["time"].AsDouble() : 0.0;
            double tb = b.ContainsKey("time") ? b["time"].AsDouble() : 0.0;
            return ta.CompareTo(tb);
        });
        replay.input_events = new Godot.Collections.Array();
        foreach (var evt in sorted_events)
            replay.input_events.Add(evt);

        return replay;
    }

    /// <summary>兼容旧格式：将 input_frames 转换为 input_events</summary>
    public static Godot.Collections.Array _convert_frames_to_events(Godot.Collections.Array frames)
    {
        var events = new Godot.Collections.Array();
        foreach (Variant frameVariant in frames)
        {
            var frame = frameVariant.AsGodotDictionary();
            double frame_time = frame.ContainsKey("time") ? frame["time"].AsDouble() : 0.0;
            // 旧格式的 time 可能是帧编号或秒数，保守以 60fps 转换
            if (frame_time > 0 && frame_time < 10000)
                frame_time = frame_time / 60.0;

            var actions = frame.ContainsKey("actions") ? frame["actions"].AsGodotArray() : new Godot.Collections.Array();
            foreach (Variant actionVariant in actions)
            {
                events.Add(new Godot.Collections.Dictionary()
                {
                    { "time", frame_time },
                    { "action", actionVariant.AsString() },
                    { "pressed", true }
                });
            }

            var released = frame.ContainsKey("released") ? frame["released"].AsGodotArray() : new Godot.Collections.Array();
            foreach (Variant actionVariant in released)
            {
                events.Add(new Godot.Collections.Dictionary()
                {
                    { "time", frame_time },
                    { "action", actionVariant.AsString() },
                    { "pressed", false }
                });
            }
        }

        // （Godot.Collections.Array 无 sort_custom，转 List 排序后重建 Array）
        var sorted = new System.Collections.Generic.List<Godot.Collections.Dictionary>();
        foreach (Variant evtVariant in events)
            sorted.Add(evtVariant.AsGodotDictionary());
        sorted.Sort((a, b) =>
        {
            double ta = a.ContainsKey("time") ? a["time"].AsDouble() : 0.0;
            double tb = b.ContainsKey("time") ? b["time"].AsDouble() : 0.0;
            return ta.CompareTo(tb);
        });
        events = new Godot.Collections.Array();
        foreach (var evt in sorted)
            events.Add(evt);

        return events;
    }

    /// <summary>获取总事件数</summary>
    public int get_total_events()
    {
        return input_events.Count;
    }

    /// <summary>验证数据完整性</summary>
    public bool validate()
    {
        if (string.IsNullOrEmpty(version))
            return false;
        if (string.IsNullOrEmpty(player_name))
            return false;
        return true;
    }

    /// <summary>获取统计摘要</summary>
    public string get_stats_summary()
    {
        return string.Format("PPS: {0:F2} | APM: {1:F2} | RPM: {2:F2} | 最大连击: {3} | 消行: {4}",
            final_stats.ContainsKey("pps") ? final_stats["pps"].AsDouble() : 0.0,
            final_stats.ContainsKey("apm") ? final_stats["apm"].AsDouble() : 0.0,
            final_stats.ContainsKey("rpm") ? final_stats["rpm"].AsDouble() : 0.0,
            final_stats.ContainsKey("max_combo") ? final_stats["max_combo"].AsInt64() : 0,
            final_stats.ContainsKey("total_lines") ? final_stats["total_lines"].AsInt64() : 0);
    }

    /// <summary>清空所有数据</summary>
    public void clear()
    {
        input_events.Clear();
        bag_sequence.Clear();
        game_duration = 0.0;
        game_start_time = 0.0;
    }
}
