using Godot;

/// <summary>
/// 回放播放器
/// 基于游戏经过时间驱动的回放播放器。
/// 录制器以游戏经过秒数记录输入事件时间，
/// 播放器按真实时间推进并匹配事件。
/// </summary>
public partial class ReplayPlayer : Node
{
    public string replay_file_path = "";
    public TetrisController tetris_controller;
    public TetrisGarbageLineController garbage_line_controller;
    public TetrisBagController bag_controller;
    public ReplayRecord replay_record;

    // 回放数据
    public ReplayData replay_data = null;

    // 播放状态
    public bool is_playing = false;
    public bool is_prepared = false;
    public bool is_loaded = false;
    public bool is_paused = false;
    public bool is_finished = false;

    // 游戏经过时间跟踪
    public double _elapsed_time = 0.0;
    public int _next_event_index = 0;
    public int _event_counter = 0;

    // 活跃按键状态（用于停止时释放）
    public Godot.Collections.Dictionary _active_actions = new Godot.Collections.Dictionary();

    // 播放速度倍率
    public double play_speed = 1.0;

    // 信号
    [Signal]
    public delegate void ReplayStartedEventHandler();
    [Signal]
    public delegate void ReplayPausedEventHandler();
    [Signal]
    public delegate void ReplayResumedEventHandler();
    [Signal]
    public delegate void ReplayFinishedEventHandler();
    [Signal]
    public delegate void ReplayProgressChangedEventHandler(double progress, double elapsed, double total_time);
    [Signal]
    public delegate void ReplayEventAppliedEventHandler(double elapsed, string action, bool pressed);

    public override void _Ready()
    {
        _auto_find_references();
        SetProcess(true);

        if (replay_file_path != "")
            CallDeferred("_delayed_load");
    }

    public void _delayed_load()
    {
        if (!is_loaded && replay_file_path != "")
            load_and_prepare(replay_file_path);
    }

    public void _auto_find_references()
    {
        if (replay_record == null)
            replay_record = GetNodeOrNull<ReplayRecord>("../../ReplayRecord");
        if (tetris_controller == null)
            tetris_controller = GetNodeOrNull<TetrisController>("../../MainBoard/TetrisController");
        if (garbage_line_controller == null)
            garbage_line_controller = GetNodeOrNull<TetrisGarbageLineController>("../../MainBoard/GarbageLineController");
        if (bag_controller == null)
            bag_controller = GetNodeOrNull<TetrisBagController>("../../MainBoard/TetrisBagController");

        if (tetris_controller == null)
            tetris_controller = _find_controller(GetTree().Root);
        if (garbage_line_controller == null)
            garbage_line_controller = _find_garbage_controller(GetTree().Root);
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

    public TetrisGarbageLineController _find_garbage_controller(Node node)
    {
        if (node is TetrisGarbageLineController)
            return (TetrisGarbageLineController)node;
        foreach (Node child in node.GetChildren())
        {
            var found = _find_garbage_controller(child);
            if (found != null)
                return found;
        }
        return null;
    }

    // ========== 加载与准备 ==========

    /// <summary>加载回放文件并准备播放环境</summary>
    public bool load_and_prepare(string path)
    {
        if (is_loaded)
            return true;

        GD.Print("加载回放文件: ", path);
        var data = ReplayData.load_from_file(path);
        if (data == null)
        {
            GD.PushError("无法加载回放文件: " + path);
            return false;
        }

        replay_data = data;
        is_prepared = true;
        is_loaded = true;

        // 初始化随机数管理器（确保与录制时一致的方块序列）
        RandomManager.initialize(replay_data.random_seed);

        // 设置 Bag 回放模式——使用录制时生成的方块序列
        if (bag_controller != null && replay_data.bag_sequence.Count > 0)
        {
            bag_controller.enable_replay_mode(replay_data.bag_sequence);
            GD.Print("Bag序列已加载，长度: ", replay_data.bag_sequence.Count);
        }

        // 应用录制时的设置
        if (tetris_controller != null)
        {
            tetris_controller.move_das = replay_data.move_das;
            tetris_controller.move_arr = replay_data.move_arr;
            tetris_controller.softdrop_delay = replay_data.softdrop_delay;
        }

        // 重置播放状态
        _elapsed_time = 0.0;
        _next_event_index = 0;
        _active_actions.Clear();
        _event_counter = 0;
        is_finished = false;
        is_paused = false;

        GD.Print("回放加载成功，种子: ", replay_data.random_seed);
        GD.Print("输入事件数: ", replay_data.input_events.Count);
        GD.Print("总时间: ", replay_data.total_time, " 秒");

        return true;
    }

    /// <summary>开始播放</summary>
    public void play()
    {
        if (!is_prepared || replay_data == null)
        {
            GD.PushError("无可播放的回放数据");
            return;
        }

        if (is_playing)
        {
            GD.Print("回放已在播放中");
            return;
        }

        GD.Print("开始回放播放");

        // 重置
        _elapsed_time = 0.0;
        _next_event_index = 0;
        _active_actions.Clear();
        _event_counter = 0;
        is_finished = false;
        is_paused = false;

        // 开启回放输入覆盖模式
        if (tetris_controller != null)
        {
            tetris_controller.set_replay_input_override(true);
            GD.Print("已开启回放输入覆盖模式");
        }

        // 禁止录制器在回放时录制
        if (replay_record != null)
        {
            replay_record.auto_record = false;
            if (replay_record.is_recording_active())
                replay_record.stop_recording();
            replay_record.has_recorded_this_game = true;
        }

        is_playing = true;
        EmitSignal(nameof(ReplayStarted));
        GD.Print("回放播放已启动，将处理 ", replay_data.input_events.Count, " 个输入事件，总时长 ", replay_data.total_time, " 秒");
    }

    /// <summary>停止播放</summary>
    public void stop()
    {
        if (!is_playing && !is_paused)
            return;

        is_playing = false;
        is_paused = false;

        // 释放所有活跃按键
        foreach (Variant actionVariant in _active_actions.Keys)
        {
            if (tetris_controller != null)
                tetris_controller.set_replay_input(actionVariant.AsString(), false);
        }
        _active_actions.Clear();

        // 关闭回放输入覆盖
        if (tetris_controller != null)
            tetris_controller.set_replay_input_override(false);

        is_finished = true;
        EmitSignal(nameof(ReplayFinished));
        GD.Print("回放播放已停止，共处理 ", _event_counter, " 个事件");
    }

    /// <summary>暂停播放</summary>
    public void pause()
    {
        if (!is_playing)
            return;
        is_paused = true;
        EmitSignal(nameof(ReplayPaused));
        GD.Print("回放已暂停");
    }

    /// <summary>恢复播放</summary>
    public void resume()
    {
        if (!is_paused)
            return;
        is_paused = false;
        EmitSignal(nameof(ReplayResumed));
        GD.Print("回放已恢复");
    }

    /// <summary>切换暂停状态</summary>
    public void toggle_pause()
    {
        if (is_paused)
            resume();
        else
            pause();
    }

    // ========== 主循环 ==========

    public override void _Process(double delta)
    {
        if (!is_playing || is_paused || is_finished || replay_data == null)
            return;

        double total = replay_data.total_time;
        if (total <= 0.0)
            total = (double)replay_data.total_frames / 60.0;
        if (total <= 0.0)
        {
            _handle_replay_end();
            return;
        }

        // 累加游戏时间
        double step = delta * play_speed;
        _elapsed_time += step;

        // 处理当前时间点的输入事件
        _process_events_for_time(_elapsed_time);

        // 发射进度信号
        double progress = Mathf.Clamp(_elapsed_time / total, 0.0, 1.0);
        EmitSignal(nameof(ReplayProgressChanged), progress, _elapsed_time, total);

        // 检查回放是否结束
        if (_elapsed_time >= total && _next_event_index >= replay_data.input_events.Count)
        {
            _handle_replay_end();
            return;
        }
    }

    /// <summary>处理指定时间点的所有输入事件</summary>
    public void _process_events_for_time(double elapsed)
    {
        while (_next_event_index < replay_data.input_events.Count)
        {
            var evt = replay_data.input_events[_next_event_index].AsGodotDictionary();
            double event_time = evt.ContainsKey("time") ? evt["time"].AsDouble() : 0.0;

            if (event_time <= elapsed)
            {
                _apply_input_event(evt, event_time);
                _next_event_index += 1;
                _event_counter += 1;
            }
            else
            {
                break;
            }
        }
    }

    /// <summary>应用输入事件到游戏控制器</summary>
    public void _apply_input_event(Godot.Collections.Dictionary evt, double event_time)
    {
        string action = evt.ContainsKey("action") ? evt["action"].AsString() : "";
        bool pressed = evt.ContainsKey("pressed") ? evt["pressed"].AsBool() : false;

        if (string.IsNullOrEmpty(action))
            return;

        if (tetris_controller != null)
        {
            tetris_controller.set_replay_input(action, pressed);
            if (pressed)
            {
                _active_actions[action] = true;
            }
            else
            {
                if (_active_actions.ContainsKey(action))
                    _active_actions.Remove(action);
            }

            EmitSignal(nameof(ReplayEventApplied), event_time, action, pressed);
        }
    }

    /// <summary>处理回放结束</summary>
    private async void _handle_replay_end()
    {
        // 释放所有按键
        foreach (Variant actionVariant in _active_actions.Keys)
        {
            if (tetris_controller != null)
                tetris_controller.set_replay_input(actionVariant.AsString(), false);
        }
        _active_actions.Clear();

        // 关闭回放覆盖模式
        if (tetris_controller != null)
            tetris_controller.set_replay_input_override(false);

        is_playing = false;
        is_finished = true;
        is_paused = false;

        EmitSignal(nameof(ReplayFinished));

        GD.Print("回放播放完成，共处理 ", _event_counter, " 个事件，播放 ", _elapsed_time, " 秒");

        // 回放结束后触发游戏结束，跳转到结算界面
        // 仅在游戏尚未自然结束时（game_timer还在跑）才触发
        if (tetris_controller != null && tetris_controller.IsInsideTree())
        {
            await ToSignal(GetTree().CreateTimer(0.3), SceneTreeTimer.SignalName.Timeout);
            if (tetris_controller.IsInsideTree())
            {
                // 检查游戏是否已经自然结束（game_timer被_game_over停止了）
                var game_timer = tetris_controller.GetNodeOrNull<Timer>("game_timer");
                if (game_timer == null || !game_timer.IsStopped())
                    tetris_controller.EmitSignal("GameEnded");
                else
                    GD.Print("回放结束但游戏已自然结束，跳过重复触发");
            }
        }
    }

    // ========== 跳转控制 ==========

    /// <summary>跳转到指定进度 (0.0 ~ 1.0)</summary>
    public void seek(double progress)
    {
        if (replay_data == null)
            return;

        double total = replay_data.total_time;
        if (total <= 0.0)
            total = (double)replay_data.total_frames / 60.0;
        if (total <= 0.0)
            return;

        double target_time = progress * total;
        seek_to_time(target_time);
    }

    /// <summary>跳转到指定时间</summary>
    public void seek_to_time(double target_time)
    {
        if (replay_data == null)
            return;

        double total = replay_data.total_time;
        if (total <= 0.0)
            total = (double)replay_data.total_frames / 60.0;

        target_time = Mathf.Clamp(target_time, 0.0, Mathf.Max(total - 0.001, 0.0));

        // 先释放所有当前按键
        foreach (Variant actionVariant in _active_actions.Keys)
        {
            if (tetris_controller != null)
                tetris_controller.set_replay_input(actionVariant.AsString(), false);
        }
        _active_actions.Clear();

        // 重置并重放到目标时间
        _elapsed_time = 0.0;
        _next_event_index = 0;
        _event_counter = 0;

        // 快速重放之前的事件（只恢复按键状态，不发送给控制器）
        var last_press_state = new Godot.Collections.Dictionary();
        while (_next_event_index < replay_data.input_events.Count)
        {
            var evt = replay_data.input_events[_next_event_index].AsGodotDictionary();
            double event_time = evt.ContainsKey("time") ? evt["time"].AsDouble() : 0.0;
            if (event_time <= target_time)
            {
                last_press_state[evt["action"]] = evt.ContainsKey("pressed") ? evt["pressed"].AsBool() : false;
                _next_event_index += 1;
                _event_counter += 1;
            }
            else
            {
                break;
            }
        }

        // 应用最终的按键状态
        foreach (Variant actionVariant in last_press_state.Keys)
        {
            if (last_press_state[actionVariant].AsBool() && tetris_controller != null)
            {
                tetris_controller.set_replay_input(actionVariant.AsString(), true);
                _active_actions[actionVariant] = true;
            }
        }

        _elapsed_time = target_time;

        double new_progress = total > 0 ? _elapsed_time / total : 0.0;
        EmitSignal(nameof(ReplayProgressChanged), new_progress, _elapsed_time, total);
    }

    // ========== 查询方法 ==========

    public bool is_playing_active()
    {
        return is_playing;
    }

    public bool is_paused_active()
    {
        return is_paused;
    }

    public bool is_finished_active()
    {
        return is_finished;
    }

    public double get_current_time()
    {
        return _elapsed_time;
    }

    public double get_total_time()
    {
        if (replay_data != null)
        {
            if (replay_data.total_time > 0)
                return replay_data.total_time;
            return (double)replay_data.total_frames / 60.0;
        }
        return 0.0;
    }

    public double get_play_progress()
    {
        double total = get_total_time();
        if (total <= 0)
            return 0.0;
        return Mathf.Clamp(_elapsed_time / total, 0.0, 1.0);
    }

    public ReplayData get_replay_data()
    {
        return replay_data;
    }

    public void reset_loaded_state()
    {
        is_loaded = false;
        is_prepared = false;
        is_playing = false;
        is_paused = false;
        is_finished = false;
        replay_data = null;
        _elapsed_time = 0.0;
        _next_event_index = 0;
        _event_counter = 0;
        _active_actions.Clear();
    }
}
