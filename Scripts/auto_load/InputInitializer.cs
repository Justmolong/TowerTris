using Godot;

/// <summary>
/// 输入初始化器
/// 游戏启动时加载键位设置
/// </summary>
public partial class InputInitializer : Node
{
    public override void _Ready()
    {
        // 初始化设置
        UserSetting.initialize_settings();
        // 已注释（调试噪音）：print("输入系统初始化完成")
    }
}
