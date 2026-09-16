using Godot;

public partial class FPSDisplay : Label
{
    public TowerController tower_controller;

    public override void _Ready()
    {
        tower_controller = GetNode<TowerController>("%TowerController");
        // 设置文字样式
        HorizontalAlignment = HorizontalAlignment.Left;
        VerticalAlignment = VerticalAlignment.Top;
        AddThemeColorOverride("font_color", Colors.White);
        AddThemeColorOverride("font_outline_color", Colors.Black);
        AddThemeConstantOverride("outline_size", 2);
        AddThemeFontSizeOverride("font_size", 16);
    }

    public override void _Process(double _delta)
    {
        int fps = (int)Engine.GetFramesPerSecond();
        Text = string.Format("FPS: {0}\nStage: {1}  APM: {2:F1}", fps, tower_controller.current_stage, tower_controller.current_apm);
    }
}
