using Godot;

/// <summary>
/// 回放录制器
/// 使用游戏经过时间（秒）记录输入事件，确保帧率无关的精确回放
/// </summary>
public partial class ReplayRecord : Node
{
    // ========== 节点引用 ==========
    public TetrisController tetris_controller;
    public TetrisClearLine clear_line_controller;
    public TetrisBagController bag_controller;

    // ========== 配置 ==========
    public string player_name = "Player";
    public bool auto_save = true;
    public string save_directory = "user://Replays/";
    public bool auto_record = true;

    // ========== 状态变量 ==========
    public ReplayData replay_data = null;
    public bool is_recording = false;
    public double _elapsed_time = 0.0;      // 游戏内经过秒数

    // 输入事件队列
    public Godot.Collections.Array _input_event_queue = new Godot.Collections.Array();

    // 录制状态
    public bool is_game_active = false;
    public bool has_recorded_this_game = false;

    // ========== 信号 ==========
    [Signal]
    public delegate void RecordingStartedEventHandler();
    [Signal]
    public delegate void RecordingStoppedEventHandler(ReplayData replay_data);
    [Signal]
    public delegate void EventRecordedEventHandler(double time, string action, bool pressed);

    public override void _Ready()
    {
        _auto_find_references();
        SetProcessInput(true);
        SetProcess(true);
    }

    public void _auto_find_references()
    {
        if (tetris_controller == null)
            tetris_controller = GetNodeOrNull<TetrisController>("../../MainBoard/TetrisController");
        if (clear_line_controller == null)
            clear_line_controller = GetNodeOrNull<TetrisClearLine>("../../MainBoard/TetrisClearLine");
        if (bag_controller == null)
            bag_controller = GetNodeOrNull<TetrisBagController>("../../MainBoard/TetrisBagController");

        if (tetris_controller == null)
            tetris_controller = _find_controller(GetTree().Root);

        // 连接Bag控制器的方块生成信号以记录方块序列
        // （C# 事件无法查询 is_connected，用先断开再连接保证最多连接一次，与 GD 守卫等效）
        if (bag_controller != null)
        {
            bag_controller.PieceSpawned -= _on_piece_spawned;
            bag_controller.PieceSpawned += _on_piece_spawned;
        }
    }

    public TetrisController _find_controller(Node node)
    {
        if (node is TetrisController)
            return (TetrisController)node;
        foreach (Node child in node.GetChildren())
        {
            var found = _find_controller(child);
            if (found != null)
                return found;
        }
        return null;
    }

    // ========== 输入事件捕获 ==========

    public override void _Input(InputEvent @event)
    {
        if (!is_recording)
            return;

        if (@event is InputEventKey key_event && !key_event.Echo)
        {
            string action = _get_action_from_keycode((int)key_event.Keycode);
            if (action != "")
            {
                bool pressed = key_event.Pressed;

                _input_event_queue.Add(new Godot.Collections.Dictionary()
                {
                    { "time", _elapsed_time },
                    { "action", action },
                    { "pressed", pressed }
                });

                if (_input_event_queue.Count >= 10)
                    _flush_input_events();
            }
        }
    }

    public string _get_action_from_keycode(int keycode)
    {
        var actions = new[] { "LeftMove", "RightMove", "SoftDrop", "HardDrop", "LeftSpin", "RightSpin", "SwapSpin", "HoldBlock" };

        foreach (string action in actions)
        {
            var events = InputMap.ActionGetEvents(action);
            foreach (InputEvent ev in events)
            {
                if (ev is InputEventKey key_ev && (int)key_ev.Keycode == keycode)
                    return action;
            }
        }
        return "";
    }

    // ========== 事件刷新 ==========

    public void _flush_input_events()
    {
        if (_input_event_queue.Count == 0)
            return;

        foreach (Variant entryVariant in _input_event_queue)
        {
            var entry = entryVariant.AsGodotDictionary();
            double time = entry["time"].AsDouble();
            string action = entry["action"].AsString();
            bool pressed = entry["pressed"].AsBool();
            replay_data.add_input_event((float)time, action, pressed);
            EmitSignal(nameof(EventRecorded), time, action, pressed);
        }

        _input_event_queue.Clear();
    }

    // ========== 主循环（累计游戏时间） ==========

    public override void _Process(double delta)
    {
        if (!is_recording)
            return;

        _elapsed_time += delta;
        _flush_input_events();
    }

    // ========== 录制控制 ==========

    public void _on_piece_spawned(string piece_type, Godot.Collections.Array _shape, Color _color)
    {
        if (!is_recording || replay_data == null)
            return;
        // 记录生成的每个方块类型（用于回放时重建准确的方块序列）
        replay_data.bag_sequence.Add(piece_type);
    }

    public void _on_game_started()
    {
        if (auto_record && !has_recorded_this_game)
        {
            start_recording(player_name);
            is_game_active = true;
        }
    }

    public void _on_game_ended()
    {
        if (is_recording)
            stop_and_save_recording();
        is_game_active = false;
    }

    public void start_recording(string record_name = "")
    {
        if (is_recording)
            stop_recording();

        replay_data = ReplayData.create_default();
        replay_data.player_name = !string.IsNullOrEmpty(player_name) ? player_name : record_name;
        replay_data.random_seed = RandomManager.get_current_seed();

        if (tetris_controller != null)
        {
            replay_data.move_das = tetris_controller.move_das;
            replay_data.move_arr = tetris_controller.move_arr;
            replay_data.softdrop_delay = tetris_controller.softdrop_delay;

            // 记录游戏开始时第一个在场景中的方块（piece_spawned信号时机早于录制）
            if (replay_data.bag_sequence.Count != 0)
                replay_data.bag_sequence.Clear();
            replay_data.bag_sequence.Add(tetris_controller.current_piece_type);
        }

        // 连接Bag控制器的方块生成信号以记录方块序列
        if (bag_controller != null)
        {
            bag_controller.PieceSpawned -= _on_piece_spawned;
            bag_controller.PieceSpawned += _on_piece_spawned;
        }

        _elapsed_time = 0.0;
        _input_event_queue.Clear();

        is_recording = true;
        has_recorded_this_game = true;
        EmitSignal(nameof(RecordingStarted));

        GD.Print("回放录制已开始，种子: ", replay_data.random_seed);
        GD.Print("首个方块: ", tetris_controller != null ? tetris_controller.current_piece_type : "unknown");
    }

    public ReplayData stop_recording()
    {
        if (!is_recording)
            return null;

        replay_data.total_time = _elapsed_time;
        replay_data.total_frames = (long)(_elapsed_time * 60.0);
        _flush_input_events();
        _collect_final_stats();

        is_recording = false;
        EmitSignal(nameof(RecordingStopped), replay_data);

        GD.Print("回放录制已停止，总时间: ", _elapsed_time, " 秒");
        GD.Print("输入事件数: ", replay_data.input_events.Count);

        return replay_data;
    }

    public string stop_and_save_recording()
    {
        if (!is_recording)
            return "";

        stop_recording();

        if (auto_save && replay_data != null)
            return save_replay();

        return "";
    }

    public string save_replay()
    {
        if (replay_data == null)
            return "";

        var dir = DirAccess.Open(save_directory);
        if (dir == null)
            DirAccess.MakeDirRecursiveAbsolute(save_directory);

        string timestamp_str = Time.GetDatetimeStringFromUnixTime((long)Time.GetUnixTimeFromSystem(), true);
        timestamp_str = timestamp_str.Replace(":", "").Replace("-", "");
        string file_name = string.Format("replay_{0}_{1}.json", replay_data.player_name, timestamp_str);
        string file_path = save_directory + file_name;

        if (replay_data.save_to_file(file_path))
        {
            GD.Print("回放已保存: ", file_path);
            return file_path;
        }
        else
        {
            GD.Print("回放保存失败");
            return "";
        }
    }

    public void _collect_final_stats()
    {
        if (replay_data == null)
            return;

        if (tetris_controller != null)
        {
            var stats = tetris_controller.get_stats();
            replay_data.final_stats["pps"] = stats.ContainsKey("pps") ? stats["pps"].AsDouble() : 0.0;
            replay_data.final_stats["apm"] = stats.ContainsKey("apm") ? stats["apm"].AsDouble() : 0.0;
            replay_data.final_stats["rpm"] = stats.ContainsKey("rpm") ? stats["rpm"].AsDouble() : 0.0;
            replay_data.final_stats["total_pieces"] = stats.ContainsKey("total_pieces") ? stats["total_pieces"] : (long)0;
            replay_data.final_stats["total_attacks"] = stats.ContainsKey("total_attacks") ? stats["total_attacks"] : (long)0;
        }

        if (clear_line_controller != null)
        {
            replay_data.final_stats["max_combo"] = (long)clear_line_controller.get_combo_count();
            replay_data.final_stats["max_btb"] = (long)clear_line_controller.get_btb_count();
        }
    }

    // ========== 公共方法 ==========

    public void record_event(string _event_type, Godot.Collections.Dictionary _event_data = null)
    {
        if (!is_recording || replay_data == null)
            return;
        // 此方法后续可扩展为记录非输入类事件，暂保留框架
    }

    public bool is_recording_active()
    {
        return is_recording;
    }

    public double get_current_time()
    {
        return _elapsed_time;
    }

    public string get_current_time_string()
    {
        return string.Format("{0:F2}s", _elapsed_time);
    }

    public ReplayData get_replay_data()
    {
        return replay_data;
    }

    public int get_recorded_event_count()
    {
        if (replay_data == null)
            return 0;
        return replay_data.input_events.Count;
    }

    public void set_player_name(string record_name)
    {
        player_name = record_name;
        if (replay_data != null && is_recording)
            replay_data.player_name = player_name;
    }

    public void reset()
    {
        if (is_recording)
            stop_recording();

        replay_data = null;
        _elapsed_time = 0.0;
        _input_event_queue.Clear();
        is_recording = false;
        has_recorded_this_game = false;
        is_game_active = false;
    }

    public void trigger_game_start()
    {
        _on_game_started();
    }

    public void trigger_game_end()
    {
        _on_game_ended();
    }

    public override void _ExitTree()
    {
        if (is_recording)
            stop_and_save_recording();
    }
}
