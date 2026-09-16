using Godot;

/// <summary>
/// 全局数据管理器
/// 用于在场景之间传递游戏数据
/// 说明：Godot autoload 单例（节点为 GlobalData）；为便于 C# 直接以类名访问，
/// 所有成员实现为 static（autoload 仅实例化一个空节点，状态全部存于静态字段）。
/// </summary>
public partial class GlobalData : Node
{
    public static Godot.Collections.Dictionary game_stats = new Godot.Collections.Dictionary()
    {
        { "game_time", 0.0 },
        { "total_pieces", 0 },
        { "total_attacks", 0 },
        { "pps", 0.0 },
        { "apm", 0.0 },
        { "rpm", 0.0 },
        { "max_combo", 0 },
        { "max_btb", 0 },
        { "total_lines_cleared", 0 },
        { "total_spins", 0 },
        { "tower_height", 0.0 },
        { "kill_count", 0 },
        { "tower_average_speed", 0.0 },
        { "current_stage", 0 },
    };

    public static string game_over_reason = "Game Over";

    /// <summary>塔控制器初始数据（由 buff_chose_area 配置，tower_controller 读取）</summary>
    public static Godot.Collections.Dictionary tower_init_data = new Godot.Collections.Dictionary();

    /// <summary>已选取的 buff 列表（由 buff_chose_area 开始游戏时记录，供结束界面右侧列表展示）</summary>
    /// <summary>元素形如 {"id": "Pressure1", "text": "高压I：apm总量增加20%"}</summary>
    public static Godot.Collections.Array selected_buffs = new Godot.Collections.Array();

    /// <summary>标识：从结束界面返回 buff_chose_area 时是否恢复上次勾选</summary>
    /// <summary>由 game_over 的 BACK 按钮置 true，buff_chose_area 读取后立刻复位为 false</summary>
    public static bool restore_buffs = false;
    // var pending_replay_path: String = ""  # 回放系统已禁用

    public static void reset_stats()
    {
        game_stats = new Godot.Collections.Dictionary()
        {
            { "game_time", 0.0 },
            { "total_pieces", 0 },
            { "total_attacks", 0 },
            { "pps", 0.0 },
            { "apm", 0.0 },
            { "rpm", 0.0 },
            { "max_combo", 0 },
            { "max_btb", 0 },
            { "total_lines_cleared", 0 },
            { "total_spins", 0 },
            { "tower_height", 0.0 },
            { "kill_count", 0 },
            { "tower_average_speed", 0.0 },
            { "current_stage", 0 },
        };
        game_over_reason = "Game Over";
    }

    public static void update_stats(Godot.Collections.Dictionary stats)
    {
        if (stats.ContainsKey("game_time"))
            game_stats["game_time"] = stats["game_time"];
        if (stats.ContainsKey("total_pieces"))
            game_stats["total_pieces"] = stats["total_pieces"];
        if (stats.ContainsKey("total_attacks"))
            game_stats["total_attacks"] = stats["total_attacks"];
        if (stats.ContainsKey("pps"))
            game_stats["pps"] = stats["pps"];
        if (stats.ContainsKey("apm"))
            game_stats["apm"] = stats["apm"];
        if (stats.ContainsKey("rpm"))
            game_stats["rpm"] = stats["rpm"];
        if (stats.ContainsKey("max_combo"))
            game_stats["max_combo"] = stats["max_combo"];
        if (stats.ContainsKey("max_btb"))
            game_stats["max_btb"] = stats["max_btb"];
        if (stats.ContainsKey("total_lines_cleared"))
            game_stats["total_lines_cleared"] = stats["total_lines_cleared"];
        if (stats.ContainsKey("total_spins"))
            game_stats["total_spins"] = stats["total_spins"];
        if (stats.ContainsKey("tower_height"))
            game_stats["tower_height"] = stats["tower_height"];
        if (stats.ContainsKey("kill_count"))
            game_stats["kill_count"] = stats["kill_count"];
        if (stats.ContainsKey("tower_average_speed"))
            game_stats["tower_average_speed"] = stats["tower_average_speed"];
        if (stats.ContainsKey("current_stage"))
            game_stats["current_stage"] = stats["current_stage"];
    }

    public static void set_game_over_reason(string reason)
    {
        game_over_reason = reason;
    }

    public static string get_game_over_reason()
    {
        return game_over_reason;
    }

    public static Godot.Collections.Dictionary get_stats()
    {
        return game_stats;
    }

    // ========== Replay 相关（已禁用） ==========
    // func set_pending_replay(path: String):
    // 	pending_replay_path = path
    // 	print("设置待播放回放: ", path)
    // 
    // func get_pending_replay_path() -> String:
    // 	return pending_replay_path
    // 
    // func clear_pending_replay_path():
    // 	pending_replay_path = ""
}
