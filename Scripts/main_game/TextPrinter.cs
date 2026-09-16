using System.Collections.Generic;
using Godot;

/// <summary>
/// 文本打印器
/// 供其他节点在指定位置显示文本，并支持透明淡出后消失。
/// 特性：
///   - 同时管理多个文本（以 key 区分）
///   - 同一 key 可叠加多条文本（非持久文本每次显示都会新生成一条，不会覆盖之前正在淡出的文本）
///   - 每个文本可独立控制透明度、颜色、字号、对齐方式
///   - persistent=true 的文本为常驻显示，由调用方负责移除（同 key 只保留最新一条，用于 btb/damage）
///   - persistent=false 的文本显示一段时间后向左漂移并自然淡出消失（每次调用都会新增一条，多条在原位叠加、各自独立淡出）
/// </summary>
public partial class TextPrinter : Node2D
{
    public class TextEntry
    {
        public string key = "";
        public string text = "";
        public Vector2 position = Vector2.Zero;
        public Color color = Colors.White;
        public Color outline_color = Colors.Black;
        public float font_size = 20.0f;
        public bool persistent = false;       // 常驻显示，不自动淡出
        public float base_opacity = 1.0f;      // 显示起始透明度（半透明可用 0.x）
        public float opacity = 1.0f;           // 当前透明度（淡出时递减）
        public float display_duration = 1.0f;  // 保持显示的时间（秒）
        public float fade_duration = 0.8f;     // 淡出时长（秒）
        public float elapsed = 0.0f;           // 已显示时间
        public float fade_elapsed = 0.0f;      // 已淡出时间
        public Vector2 drift = Vector2.Zero;  // 漂移速度（像素/秒，向左为负X）
        public HorizontalAlignment alignment = HorizontalAlignment.Right;
    }

    /// <summary>key -> List[TextEntry]</summary>
    public Dictionary<string, List<TextEntry>> _entries = new Dictionary<string, List<TextEntry>>();

    /// <summary>漂移减速速率（/秒）：初始速度快，随时间指数衰减，最终停下</summary>
    public const float DRIFT_DECEL_PER_SEC = 0.9f;

    public static readonly Vector2[] OUTLINE_OFFSETS = new Vector2[]
    {
        new Vector2(-1, 0), new Vector2(1, 0), new Vector2(0, -1), new Vector2(0, 1),
        new Vector2(-1, -1), new Vector2(1, -1), new Vector2(-1, 1), new Vector2(1, 1),
    };

    /// <summary>
    /// 显示一个文本。
    /// 非持久文本（persistent=false）：每次调用都会新增一条并在原位叠加，不会覆盖正在淡出的文本。
    /// 持久文本（persistent=true）：同 key 只保留最新一条并更新其内容。
    /// 参数：
    ///   key            标识（用于之后指定该文本让其消失）
    ///   text           显示的文本内容
    ///   position       显示位置（Node2D 世界坐标）
    ///   color          文本颜色（缺省白）
    ///   outline_color  描边颜色（缺省黑）
    ///   font_size      字号（缺省 20）
    ///   persistent     为 true 时常驻显示，不会自动淡出
    ///   opacity        显示时的透明度（0-1，半透明用 0.5~0.8）
    ///   display_duration 保持显示的时间（秒），之后开始淡出
    ///   fade_duration  淡出时长（秒）
    ///   drift          漂移速度（像素/秒）
    ///   alignment      文本对齐方式（相对 position 的锚点）
    /// </summary>
    public void show_text(string key, string text, Vector2 pos,
        Color color = default(Color), Color outline_color = default(Color), float font_size = 20.0f,
        bool persistent = false, float opacity = 1.0f, float display_duration = 1.0f,
        float fade_duration = 0.8f, Vector2 drift = default(Vector2),
        HorizontalAlignment alignment = HorizontalAlignment.Right)
    {
        Color c = (color == default(Color)) ? Colors.White : color;
        Color oc = (outline_color == default(Color)) ? Colors.Black : outline_color;
        Vector2 dr = (drift == default(Vector2)) ? Vector2.Zero : drift;

        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            list = null;
        TextEntry entry;
        if (persistent && list != null && list.Count > 0)
        {
            // 持久文本：更新已有的最新一条，不叠加
            entry = list[0];
            _fill_entry(entry, key, text, pos, c, oc, font_size,
                persistent, opacity, display_duration, fade_duration, dr, alignment);
        }
        else
        {
            entry = new TextEntry();
            _fill_entry(entry, key, text, pos, c, oc, font_size,
                persistent, opacity, display_duration, fade_duration, dr, alignment);
            // 叠加：多条非持久文本在原位叠加显示（不向下错开，各自独立淡出）
            if (list == null)
            {
                list = new List<TextEntry>();
                _entries[key] = list;
            }
            list.Add(entry);
        }
        QueueRedraw();
    }

    public void _fill_entry(TextEntry entry, string key, string text, Vector2 pos,
        Color color, Color outline_color, float font_size,
        bool persistent, float opacity, float display_duration, float fade_duration,
        Vector2 drift, HorizontalAlignment alignment)
    {
        entry.key = key;
        entry.text = text;
        entry.position = pos;
        entry.color = color;
        entry.outline_color = outline_color;
        entry.font_size = font_size;
        entry.persistent = persistent;
        entry.base_opacity = Mathf.Clamp(opacity, 0.0f, 1.0f);
        entry.opacity = Mathf.Clamp(opacity, 0.0f, 1.0f);
        entry.display_duration = display_duration;
        entry.fade_duration = Mathf.Max(fade_duration, 0.0f);
        entry.drift = drift;
        entry.alignment = alignment;
        entry.elapsed = 0.0f;
        entry.fade_elapsed = 0.0f;
    }

    /// <summary>更新指定 key 的文本内容（影响该 key 的所有条目，不影响位置与生命周期）</summary>
    public void update_text(string key, string new_text)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return;
        foreach (TextEntry e in list)
            e.text = new_text;
        QueueRedraw();
    }

    /// <summary>移动指定 key 的所有文本到新位置</summary>
    public void set_text_position(string key, Vector2 new_position)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return;
        foreach (TextEntry e in list)
            e.position = new_position;
        QueueRedraw();
    }

    /// <summary>指定 key 的所有文本透明度控制（0-1）</summary>
    public void set_text_opacity(string key, float opacity)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return;
        float alpha = Mathf.Clamp(opacity, 0.0f, 1.0f);
        foreach (TextEntry e in list)
        {
            e.base_opacity = alpha;
            e.opacity = alpha;
        }
        QueueRedraw();
    }

    /// <summary>指定 key 的所有文本颜色控制</summary>
    public void set_text_color(string key, Color color)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return;
        foreach (TextEntry e in list)
            e.color = color;
        QueueRedraw();
    }

    /// <summary>让指定文本立即消失</summary>
    public void remove_text(string key)
    {
        _entries.Remove(key);
        QueueRedraw();
    }

    /// <summary>让指定 key 的所有文本淡出后消失（对常驻文本也可用）</summary>
    public void fade_out_text(string key, float fade_duration = 0.5f)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return;
        foreach (TextEntry e in list)
        {
            e.persistent = false;
            e.display_duration = 0.0f;
            e.fade_duration = Mathf.Max(fade_duration, 0.0f);
            e.elapsed = 0.0f;
            e.fade_elapsed = 0.0f;
        }
        QueueRedraw();
    }

    /// <summary>清空所有文本（含常驻文本）</summary>
    public void clear_all()
    {
        _entries.Clear();
        QueueRedraw();
    }

    /// <summary>是否存在指定 key 的文本</summary>
    public bool has_text(string key)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list))
            return false;
        return list.Count > 0;
    }

    /// <summary>获取指定 key 的文本内容（取最新一条）</summary>
    public string get_text(string key)
    {
        List<TextEntry> list;
        if (!_entries.TryGetValue(key, out list) || list.Count == 0)
            return "";
        return list[list.Count - 1].text;
    }

    public override void _Process(double delta)
    {
        if (_entries.Count == 0)
            return;
        var to_delete = new System.Collections.Generic.List<string>();
        foreach (var pair in _entries)
        {
            string key = pair.Key;
            var list = pair.Value;
            var remaining = new List<TextEntry>();
            foreach (TextEntry entry in list)
            {
                if (entry.persistent)
                {
                    remaining.Add(entry);
                    continue;
                }
                entry.elapsed += (float)delta;
                // 加速度移动：初始速度快，随时间指数衰减减速
                entry.position += entry.drift * (float)delta;
                entry.drift *= Mathf.Max(0.0f, 1.0f - DRIFT_DECEL_PER_SEC * (float)delta);
                // 淡出与移动并行：显示初期即开始淡出（与漂移同时进行），fade_duration 为淡出总时长
                float t = 1.0f;
                if (entry.fade_duration > 0.0f)
                    t = Mathf.Clamp((entry.elapsed - entry.display_duration) / entry.fade_duration, 0.0f, 1.0f);
                entry.opacity = entry.base_opacity * (1.0f - t);
                if (t >= 1.0f)
                    continue;  // 淡出完成，丢弃这条
                remaining.Add(entry);
            }
            if (remaining.Count == 0)
                to_delete.Add(key);
            else
                _entries[key] = remaining;
        }
        foreach (string key in to_delete)
            _entries.Remove(key);
        QueueRedraw();
    }

    public override void _Draw()
    {
        if (_entries.Count == 0)
            return;
        Font font = ThemeDB.FallbackFont;
        foreach (var pair in _entries)
        {
            foreach (TextEntry entry in pair.Value)
            {
                if (entry.text.Length == 0 || entry.opacity <= 0.0f)
                    continue;
                int font_size_int = Mathf.Max(1, Mathf.RoundToInt(entry.font_size));
                Vector2 draw_pos = entry.position;
                if (entry.alignment == HorizontalAlignment.Right)
                {
                    Vector2 text_size = font.GetStringSize(entry.text, HorizontalAlignment.Left, -1, font_size_int);
                    draw_pos.X -= text_size.X;
                }
                Color color = entry.color;
                color.A *= entry.opacity;
                Color outline = entry.outline_color;
                outline.A *= entry.opacity;
                foreach (Vector2 offset in OUTLINE_OFFSETS)
                    DrawString(font, draw_pos + offset, entry.text, HorizontalAlignment.Left, -1, font_size_int, outline);
                DrawString(font, draw_pos, entry.text, HorizontalAlignment.Left, -1, font_size_int, color);
            }
        }
    }
}
