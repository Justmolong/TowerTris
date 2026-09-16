using Godot;

/// <summary>
/// 可复用的切换方框组件
/// 核心功能：显示带 ✓/✗ 标记的方框，点击在两个状态间切换
/// 预留 id/value 支持外部数据绑定和读取
/// </summary>
public partial class ToggleBox : Control
{
    // ========== 信号 ==========

    /// <summary>状态切换时触发</summary>
    [Signal]
    public delegate void ToggledEventHandler(string box_id, bool is_checked, Variant value);

    // ========== 导出属性 ==========

    /// <summary>唯一标识（用于外部区分不同的 ToggleBox）</summary>
    [Export]
    public string box_id = "toggle_default";

    /// <summary>关联值（预留，用于后续绑定 buff/debuff 数据）</summary>
    [Export]
    public Variant value;

    /// <summary>方框大小（像素）</summary>
    [Export]
    public int box_size = 28;

    /// <summary>默认状态（true = ✓，false = ✗）</summary>
    [Export]
    public bool default_checked = true;

    /// <summary>边框颜色</summary>
    [Export]
    public Color border_color = new Color(1, 1, 1, 0.8f);

    /// <summary>选中时标记颜色</summary>
    [Export]
    public Color checked_color = new Color(0.3f, 1, 0.3f, 1);

    /// <summary>未选中时标记颜色</summary>
    [Export]
    public Color unchecked_color = new Color(1, 0.3f, 0.3f, 1);

    // ========== 运行时状态 ==========

    public bool is_checked = false;

    // ========== 生命周期 ==========

    public override void _Ready()
    {
        is_checked = default_checked;
        CustomMinimumSize = new Vector2(box_size, box_size);
        Size = new Vector2(box_size, box_size);
        MouseEntered += _on_mouse_entered;
        MouseExited += _on_mouse_exited;
    }

    // ========== 绘制 ==========

    public override void _Draw()
    {
        var rect = new Rect2(Vector2.Zero, Size);

        // 绘制背景
        DrawRect(rect, new Color(0.15f, 0.15f, 0.15f, 0.9f), true);

        // 绘制边框
        DrawRect(rect, border_color, false, 1.5f);

        // 绘制 ✓ 或 ✗
        Font font = ThemeDB.FallbackFont;
        int font_size = box_size - 6;
        string text = is_checked ? "✓" : "✗";
        Color text_color = is_checked ? checked_color : unchecked_color;

        Vector2 text_size = font.GetStringSize(text, HorizontalAlignment.Center, -1, font_size);
        var text_pos = new Vector2(
            (Size.X - text_size.X) / 2.0f,
            (Size.Y + text_size.Y) / 2.0f - 8
        );

        DrawString(font, text_pos, text, HorizontalAlignment.Center, -1, font_size, text_color);
    }

    // ========== 输入处理 ==========

    public override void _GuiInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex == MouseButton.Left)
            _toggle();
    }

    public void _on_mouse_entered()
    {
        border_color = new Color(1, 1, 1, 1);
        QueueRedraw();
    }

    public void _on_mouse_exited()
    {
        border_color = new Color(1, 1, 1, 0.8f);
        QueueRedraw();
    }

    // ========== 公开方法 ==========

    /// <summary>切换状态</summary>
    public void toggle()
    {
        _toggle();
    }

    /// <summary>设置选中状态（true = ✓，false = ✗）</summary>
    public void set_checked(bool checked_value)
    {
        is_checked = checked_value;
        QueueRedraw();
        EmitSignal(nameof(Toggled), box_id, is_checked, value);
    }

    /// <summary>获取当前状态</summary>
    public bool is_checked_state()
    {
        return is_checked;
    }

    /// <summary>设置关联值</summary>
    public void set_box_value(Variant val)
    {
        value = val;
    }

    /// <summary>设置唯一标识</summary>
    public void set_box_id(string new_id)
    {
        box_id = new_id;
    }

    /// <summary>获取完整状态字典（供外部批量读取）</summary>
    public Godot.Collections.Dictionary get_state()
    {
        return new Godot.Collections.Dictionary()
        {
            { "id", box_id },
            { "checked", is_checked },
            { "value", value },
        };
    }

    /// <summary>重置为默认状态</summary>
    public void reset()
    {
        set_checked(default_checked);
    }

    // ========== 内部方法 ==========

    public void _toggle()
    {
        is_checked = !is_checked;
        QueueRedraw();
        EmitSignal(nameof(Toggled), box_id, is_checked, value);
    }
}
