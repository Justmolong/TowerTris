using Godot;

/// <summary>
/// 主菜单控制器
/// 负责主菜单的按钮交互和场景切换，支持 UI 缩放适配
/// </summary>
public partial class MenuController : Node
{
    // 节点引用
    [Export]
    public Button start_button;
    [Export]
    public Button setting_button;
    // @export var replay_button: Button  # 回放系统已禁用
    [Export]
    public Button quit_button;

    // 场景路径
    [Export]
    public string game_scene_path = "res://Tscns/buff_chose_area.tscn";
    [Export]
    public string setting_scene_path = "res://Tscns/setting_area.tscn";
    // @export var replay_scene_path: String = "res://Tscns/tetris.tscn"  # 回放系统已禁用

    // FileDialog 引用（回放系统已禁用）
    // var _file_dialog: FileDialog = null
    // var _is_dialog_open: bool = false

    // UI 缩放（已禁用 UIScaler，固定为 1.0）
    public Panel _panel;

    public override void _Ready()
    {
        _panel = GetNodeOrNull<Panel>("../Panel");
        _connect_signals();
        GlobalData.reset_stats();

        // 连接 UI 缩放更新（UIScaler 已移除，固定 scale=1.0）
        _apply_ui_scale();
    }

    /// <summary>将 Panel 及其中的菜单内容居中到屏幕中央</summary>
    public void _apply_ui_scale(float _new_scale = -1.0f)
    {
        if (_panel == null)
            return;

        // 内容在 Panel 中的大致中心偏移（基于子节点布局计算）
        var content_center = new Vector2(484.5f, 176.0f);
        // 面板尺寸应至少覆盖内容区域
        _panel.Size = new Vector2(600, 450);
        // 将内容中心对齐到视口中心
        Vector2 vp = GetTree().Root.Size;
        _panel.Position = vp / 2.0f - content_center;
    }

    public void _connect_signals()
    {
        if (start_button != null)
            start_button.Pressed += _on_start_button_pressed;
        if (setting_button != null)
            setting_button.Pressed += _on_setting_button_pressed;
        // if replay_button:  # 回放系统已禁用
        // 	replay_button.pressed.connect(_on_replay_button_pressed)
        if (quit_button != null)
            quit_button.Pressed += _on_quit_button_pressed;
    }

    public void _on_start_button_pressed()
    {
        // 已注释（调试噪音）：print("开始游戏")
        GlobalData.reset_stats();
        GetTree().ChangeSceneToFile(game_scene_path);
    }

    public void _on_setting_button_pressed()
    {
        // 已注释（调试噪音）：print("设置按钮被点击")
        GetTree().ChangeSceneToFile(setting_scene_path);
    }

    // ====== 回放按钮相关（已禁用） ======
    // func _on_replay_button_pressed():
    // 	print("选择回放文件")
    // 	if _is_dialog_open:
    // 		return
    // 	_open_replay_file_dialog()
    // 
    // func _open_replay_file_dialog():
    // 	...
    // func _on_replay_file_selected(path: String):
    // 	...
    // func _on_replay_file_canceled():
    // 	...
    // func _cleanup_dialog():
    // 	...

    public void _on_quit_button_pressed()
    {
        // 已注释（调试噪音）：print("退出游戏")
        GetTree().Quit();
    }

    public override void _ExitTree()
    {
        // 清理对话框（回放系统已禁用）
        // _cleanup_dialog()
        // _is_dialog_open = false
        // pass
    }
}
