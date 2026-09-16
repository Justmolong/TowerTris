using Godot;

/// <summary>
/// UI 缩放管理器（已废弃）
/// 此文件仅用于满足 autoload 引用，实际缩放已由各控制器内部硬编码为 1.0
/// </summary>
public partial class UiScaler : Node
{
    [Signal]
    public delegate void ScaleChangedEventHandler(float new_scale);

    public const string SENTINEL_TTRIS = "sentinel_marker_42";
    public static float GetScale()
    {
        return 1.0f;
    }

    public override void _Ready()
    {
        EmitSignal(nameof(ScaleChanged), 1.0f);
    }
}
