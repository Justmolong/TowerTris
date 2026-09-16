using Godot;

/// <summary>
/// 选框连接线绘制器
/// 在选框行上方绘制水平连接线（穿过选框中心，但跳过选框内部线段）
/// </summary>
public partial class ToggleConnector : Control
{
    // ========== 导出属性 ==========

    /// <summary>连接线颜色</summary>
    [Export]
    public Color line_color = new Color(0.7f, 0.7f, 0.7f, 0.8f);

    /// <summary>连接线粗细（像素）</summary>
    [Export]
    public float line_width = 5.0f;

    // ========== 生命周期 ==========

    public override void _Ready()
    {
        // 在第一帧布局完成后，同步尺寸为父容器（ToggleRow）大小
        _resize_to_parent();
        QueueRedraw();
    }

    public override void _Process(double _delta)
    {
        // 持续同步尺寸（应对容器大小变化）
        if (GetParent() is HBoxContainer parent)
        {
            if (Size != parent.Size)
            {
                Size = parent.Size;
                QueueRedraw();
            }
        }
    }

    public void _resize_to_parent()
    {
        if (GetParent() is HBoxContainer parent)
            Size = parent.Size;
    }

    public override void _Draw()
    {
        if (GetParent() is not HBoxContainer toggle_row || toggle_row.Size.X <= 0)
            return;

        // ConnectorLine 自身在行内的偏移（行内前面有 ChoseType Label 等节点时不为 0）
        // 选框坐标是相对于 toggle_row 的，而 draw_line 使用的是 ConnectorLine 本地坐标，
        // 因此所有坐标都要减去 ConnectorLine 的位置偏移，否则提示线会整体偏移。
        Vector2 offset = Position;

        // 收集所有 ToggleBox 的中心 X 坐标（相对于 toggle_row）
        var centers = new Godot.Collections.Array<float>();
        foreach (Node child in toggle_row.GetChildren())
        {
            if (child is ToggleBox tb)
            {
                float cx = tb.Position.X + tb.Size.X * 0.5f;
                centers.Add(cx);
            }
        }

        if (centers.Count < 2)
            return;

        // 中心 Y（相对于 toggle_row 的坐标空间）
        float center_y = toggle_row.Size.Y * 0.5f;

        // 画出相邻选框之间的线段（跳过选框内部）
        float half_box = 16.0f;  // 选框宽 32px 的一半
        for (int i = 0; i < centers.Count - 1; i++)
        {
            float x1 = centers[i] + half_box - offset.X;       // 左侧选框右边缘
            float x2 = centers[i + 1] - half_box - offset.X;   // 右侧选框左边缘
            if (x2 > x1)
                DrawLine(new Vector2(x1, center_y - offset.Y), new Vector2(x2, center_y - offset.Y), line_color, line_width);
        }
    }
}
