using Godot;

/// <summary>
/// 俄罗斯方块Bag生成器
/// 负责方块序列生成，支持多种出块策略（ChangeBag buff 通过 GlobalData 传入 BagType）：
///   bag_type = -1 : 默认 7-Bag（每7个方块一个随机排列的完整bag）
///   bag_type =  1 : 14-Bag（一次生成14个方块，每种方块2个，随机排列）
///   bag_type =  2 : 概率出块（每次随机生成1个，出现越少的方块下次出现概率越高）
///   bag_type =  3 : 完全随机出块（每次均匀随机生成1个）
/// </summary>
public partial class TetrisBagController : Node
{
    // 方块数据文件路径（方块类型/形状/颜色均从此文件读取）
    public const string BLOCK_DATA_PATH = "res://GameSaveData/BlockData.json";

    // 方块数据字典（从BlockData.json加载）
    // 结构: { "I": {"shape": [[...]], "color": Color}, ... }
    // 所有方块类型/形状/颜色均以BlockData.json为准
    public Godot.Collections.Dictionary piece_data = new Godot.Collections.Dictionary();

    // 方块类型列表（用于生成，由BlockData.json的键生成）
    public Godot.Collections.Array piece_types = new Godot.Collections.Array();

    // 方块序列
    public Godot.Collections.Array piece_queue = new Godot.Collections.Array();  // 存储方块类型名称的队列

    // 出块策略类型（-1=默认7-Bag）。ChangeBag buff 通过 GlobalData 传入 1/2/3
    public int bag_type = -1;

    // 概率出块（BagType=2）用到的出现次数统计：piece_type -> 已出现次数
    private Godot.Collections.Dictionary _spawn_count = new Godot.Collections.Dictionary();

    // ========== 数据加载 ==========

    public override void _Ready()
    {
        // 从BlockData.json读取方块数据（类型/形状/颜色），此为唯一数据来源
        _load_block_data_from_json();
    }

    /// <summary>确保方块数据已从BlockData.json加载（懒加载）</summary>
    /// <summary>场景树中TetrisController的_ready会先于本节点执行，可能在本节点_ready前请求方块，</summary>
    /// <summary>因此所有访问方块数据的入口都需要先调用本函数</summary>
    public void _ensure_data_loaded()
    {
        if (piece_data.Count == 0)
            _load_block_data_from_json();
    }

    /// <summary>从BlockData.json读取所有方块数据，存储进 piece_data 字典</summary>
    /// <summary>后续访问方块时先根据名称从 piece_data 获取 shape 和 color 再使用</summary>
    public void _load_block_data_from_json()
    {
        if (!FileAccess.FileExists(BLOCK_DATA_PATH))
        {
            GD.PushError("BlockData.json 不存在: ", BLOCK_DATA_PATH);
            return;
        }

        using var file = FileAccess.Open(BLOCK_DATA_PATH, FileAccess.ModeFlags.Read);
        if (file == null)
        {
            GD.PushError("无法打开 BlockData.json: ", BLOCK_DATA_PATH);
            return;
        }

        string json_string = file.GetAsText();

        var json = new Json();
        Error error = json.Parse(json_string);
        if (error != Error.Ok)
        {
            GD.PushError("解析 BlockData.json 失败: ", json.GetErrorMessage());
            return;
        }

        var data = json.Data;
        if (data.VariantType != Variant.Type.Dictionary)
        {
            GD.PushError("BlockData.json 格式错误");
            return;
        }

        var dict = data.AsGodotDictionary();

        var new_piece_data = new Godot.Collections.Dictionary();
        var new_piece_types = new Godot.Collections.Array();
        foreach (var key in dict.Keys)
        {
            string piece_type = key.AsString();
            Variant entry = dict[key];
            if (entry.VariantType != Variant.Type.Dictionary)
            {
                GD.PushWarning("BlockData.json 中方块数据格式错误，已跳过: ", piece_type);
                continue;
            }
            var entryDict = entry.AsGodotDictionary();
            if (!entryDict.ContainsKey("Shape") || !entryDict.ContainsKey("Color"))
            {
                GD.PushWarning("BlockData.json 中方块数据格式错误，已跳过: ", piece_type);
                continue;
            }

            // Shape：矩阵数组 → 整型二维数组
            var shape = new Godot.Collections.Array();
            foreach (var rowVariant in entryDict["Shape"].AsGodotArray())
            {
                var int_row = new Godot.Collections.Array();
                var rowArr = rowVariant.AsGodotArray();
                foreach (var cell in rowArr)
                    int_row.Add((int)(long)cell);
                shape.Add(int_row);
            }

            // Color：数组 → Color（支持RGB三元素或RGBA四元素）
            var color_arr = entryDict["Color"].AsGodotArray();
            Color color;
            if (color_arr.Count >= 4)
                color = new Color((float)(double)color_arr[0], (float)(double)color_arr[1], (float)(double)color_arr[2], (float)(double)color_arr[3]);
            else
                color = new Color((float)(double)color_arr[0], (float)(double)color_arr[1], (float)(double)color_arr[2]);

            new_piece_data[piece_type] = new Godot.Collections.Dictionary()
            {
                { "shape", shape },
                { "color", color },
            };
            new_piece_types.Add(piece_type);
        }

        if (new_piece_data.Count == 0)
        {
            GD.PushError("BlockData.json 中无有效方块数据");
            return;
        }

        piece_data = new_piece_data;
        piece_types = new_piece_types;
        // 已注释（调试噪音）：print("BlockData.json 已加载，方块类型: ", piece_types)
    }

    // 信号
    [Signal]
    public delegate void PieceSpawnedEventHandler(string piece_type, Godot.Collections.Array shape, Color color);

    /// <summary>生成单个7-Bag（7个不同方块的随机排列）</summary>
    public Godot.Collections.Array _generate_7bag_type_bag()
    {
        var new_bag = (Godot.Collections.Array)piece_types.Duplicate();
        var bag_rng = RandomManager.get_random("BAG");
        for (int i = new_bag.Count - 1; i > 0; i--)
        {
            int j = bag_rng.RandiRange(0, i);
            Variant temp = new_bag[i];
            new_bag[i] = new_bag[j];
            new_bag[j] = temp;
        }
        return new_bag;
    }

    /// <summary>生成单个14-Bag（每种方块2个，共14个，随机排列）</summary>
    public Godot.Collections.Array _generate_14bag_type_bag()
    {
        var bag = (Godot.Collections.Array)piece_types.Duplicate();
        foreach (var t in piece_types)
            bag.Add(t);
        var bag_rng = RandomManager.get_random("BAG");
        for (int i = bag.Count - 1; i > 0; i--)
        {
            int j = bag_rng.RandiRange(0, i);
            Variant temp = bag[i];
            bag[i] = bag[j];
            bag[j] = temp;
        }
        return bag;
    }

    /// <summary>概率出块（BagType=2）：按出现次数加权随机选1个方块。</summary>
    /// <summary>权重 = 1/(出现次数+1)，出现越少的方块权重越高 → 下次出现概率越高。</summary>
    public string _generate_probability_piece()
    {
        double total_weight = 0.0;
        foreach (var ptObj in piece_types)
        {
            string pt = ptObj.AsString();
            int c = _get_spawn_count(pt);
            total_weight += 1.0 / (c + 1.0);
        }
        var bag_rng = RandomManager.get_random("BAG");
        double r = bag_rng.Randf() * total_weight;
        foreach (var ptObj in piece_types)
        {
            string pt = ptObj.AsString();
            int c = _get_spawn_count(pt);
            r -= 1.0 / (c + 1.0);
            if (r <= 0.0)
            {
                _spawn_count[pt] = (long)(c + 1);
                return pt;
            }
        }
        // 兜底（浮点误差导致未命中时取最后一个）
        string last = piece_types[piece_types.Count - 1].AsString();
        _spawn_count[last] = (long)(_get_spawn_count(last) + 1);
        return last;
    }

    private int _get_spawn_count(string pt)
    {
        if (_spawn_count.ContainsKey(pt))
            return (int)(long)_spawn_count[pt];
        return 0;
    }

    /// <summary>完全随机出块（BagType=3）：均匀随机选1个方块</summary>
    public string _generate_random_piece()
    {
        var bag_rng = RandomManager.get_random("BAG");
        return piece_types[bag_rng.RandiRange(0, piece_types.Count - 1)].AsString();
    }

    /// <summary>获取当前生效的出块策略类型</summary>
    /// <summary>优先返回外部通过 set_bag_type 设置的 bag_type；否则读取 ChangeBag buff 写入 GlobalData 的 BagType</summary>
    public int _get_active_bag_type()
    {
        if (bag_type != -1)
            return bag_type;
        var init = GlobalData.tower_init_data;
        if (init.ContainsKey("extra_data_dict"))
        {
            var extra = init["extra_data_dict"].AsGodotDictionary();
            if (extra.ContainsKey("BagType"))
                return (int)(long)extra["BagType"];
        }
        return -1;
    }

    /// <summary>外部设置出块策略类型（ChangeBag buff 或其它系统调用）。-1 表示使用默认7-Bag</summary>
    public void set_bag_type(int value)
    {
        bag_type = value;
    }

    /// <summary>补充方块序列（当队列少于14个时补充）</summary>
    /// <summary>根据当前出块策略选择对应的生成方式，未识别时回退到7-Bag</summary>
    public void _refill_queue()
    {
        _ensure_data_loaded();
        if (piece_types.Count == 0)
        {
            GD.PushError("BlockData.json 未加载成功，无法生成方块序列");
            return;
        }
        int bt = _get_active_bag_type();
        while (piece_queue.Count < 14)
        {
            switch (bt)
            {
                case 1:
                    foreach (var p in _generate_14bag_type_bag())
                        piece_queue.Add(p);
                    break;
                case 2:
                    piece_queue.Add(_generate_probability_piece());
                    break;
                case 3:
                    piece_queue.Add(_generate_random_piece());
                    break;
                default:
                    foreach (var p in _generate_7bag_type_bag())
                        piece_queue.Add(p);
                    break;
            }
            // print("当前序列：",piece_queue)
        }
    }

    /// <summary>获取下一个方块（从队列头部取出）</summary>
    public Godot.Collections.Dictionary get_next_piece()
    {
        _ensure_data_loaded();
        // 检查是否需要补充（队列少于14个时补充）
        if (piece_queue.Count < 14)
            _refill_queue();

        // 取出第一个方块
        string piece_type = piece_queue[0].AsString();
        piece_queue.RemoveAt(0);

        // 按名称从piece_data获取方块数据（深拷贝形状矩阵，防止引用污染）
        Godot.Collections.Dictionary data = new Godot.Collections.Dictionary();
        if (piece_data.ContainsKey(piece_type))
            data = piece_data[piece_type].AsGodotDictionary();
        if (data.Count == 0)
        {
            GD.PushError("get_next_piece: 未知方块类型或BlockData未加载: ", piece_type);
            return new Godot.Collections.Dictionary()
            {
                { "type", piece_type },
                { "shape", new Godot.Collections.Array() },
                { "color", Colors.White },
            };
        }
        var shape = _deep_copy_matrix(data["shape"].AsGodotArray());
        Color color = data["color"].AsColor();

        // 发射信号
        EmitSignal(nameof(PieceSpawned), piece_type, shape, color);

        return new Godot.Collections.Dictionary()
        {
            { "type", piece_type },
            { "shape", shape },
            { "color", color },
        };
    }

    /// <summary>获取下一个方块的类型（用于预览）</summary>
    public string peek_next_piece()
    {
        if (piece_queue.Count == 0)
            return "I";
        return piece_queue[0].AsString();
    }

    /// <summary>获取接下来N个方块的类型（用于Next显示）</summary>
    public Godot.Collections.Array peek_next_pieces(int count = 4)
    {
        var result = new Godot.Collections.Array();

        // 确保队列有足够的方块
        while (piece_queue.Count < count)
            _refill_queue();

        for (int i = 0; i < count; i++)
            result.Add(piece_queue[i]);

        return result;
    }

    /// <summary>获取当前队列的副本（用于调试）</summary>
    public Godot.Collections.Array get_queue_copy()
    {
        return (Godot.Collections.Array)piece_queue.Duplicate();
    }

    /// <summary>深拷贝矩阵</summary>
    public Godot.Collections.Array _deep_copy_matrix(Godot.Collections.Array matrix)
    {
        var copy = new Godot.Collections.Array();
        foreach (var row in matrix)
            copy.Add(row.AsGodotArray().Duplicate());
        return copy;
    }

    /// <summary>根据名称获取方块数据（shape + color），不存在时返回空字典</summary>
    public Godot.Collections.Dictionary get_piece_data(string piece_type)
    {
        _ensure_data_loaded();
        if (piece_data.ContainsKey(piece_type))
            return piece_data[piece_type].AsGodotDictionary();
        return new Godot.Collections.Dictionary();
    }

    /// <summary>获取方块的原始形状（未旋转状态），按名称从piece_data获取</summary>
    public Godot.Collections.Array get_original_shape(string piece_type)
    {
        _ensure_data_loaded();
        Godot.Collections.Dictionary data = new Godot.Collections.Dictionary();
        if (piece_data.ContainsKey(piece_type))
            data = piece_data[piece_type].AsGodotDictionary();
        if (data.Count == 0)
        {
            GD.PushError("未知方块类型: ", piece_type);
            return new Godot.Collections.Array();
        }
        return _deep_copy_matrix(data["shape"].AsGodotArray());
    }

    /// <summary>获取方块的颜色，按名称从piece_data获取</summary>
    public Color get_piece_color(string piece_type)
    {
        _ensure_data_loaded();
        Godot.Collections.Dictionary data = new Godot.Collections.Dictionary();
        if (piece_data.ContainsKey(piece_type))
            data = piece_data[piece_type].AsGodotDictionary();
        if (data.Count == 0)
        {
            GD.PushError("未知方块类型: ", piece_type);
            return Colors.White;
        }
        return data["color"].AsColor();
    }

    /// <summary>获取方块类型名称</summary>
    public string get_piece_type_name(string piece_type)
    {
        return piece_type;
    }

    // ========== 回放模式（已禁用） ==========
    // 回放系统整体已禁用：以下接口仅为保证 replay_game 各脚本可编译而保留的空实现，
    // 游戏流程不会调用它们（tetris_controller 内的相关调用已注释）。
    private bool _replay_mode = false;
    private Godot.Collections.Array _replay_sequence = new Godot.Collections.Array();
    private int _replay_index = 0;

    /// <summary>启用回放模式（已禁用空实现，不生效）</summary>
    public void enable_replay_mode(Godot.Collections.Array sequence)
    {
        _replay_mode = true;
        _replay_sequence = (Godot.Collections.Array)sequence.Duplicate();
        _replay_index = 0;
        piece_queue.Clear();
        piece_queue = (Godot.Collections.Array)sequence.Duplicate();
    }

    /// <summary>关闭回放模式（已禁用空实现，不生效）</summary>
    public void disable_replay_mode()
    {
        _replay_mode = false;
        _replay_sequence.Clear();
        _replay_index = 0;
        piece_queue.Clear();
        _refill_queue();
    }

    /// <summary>是否处于回放模式（已禁用，恒为 false）</summary>
    public bool is_replay_mode()
    {
        return _replay_mode;
    }

    /// <summary>重置生成器（用于Replay，已禁用空实现，不生效）</summary>
    public void reset()
    {
        piece_queue.Clear();
        if (_replay_mode)
        {
            piece_queue = (Godot.Collections.Array)_replay_sequence.Duplicate();
            _replay_index = 0;
        }
        else
        {
            _refill_queue();
        }
    }

    // ---- 调试辅助（确定性测试用；不影响玩法逻辑）----

    /// <summary>清空队列并按当前出块策略重新填充（配合固定种子做确定性对比）</summary>
    public void debug_reset_bag()
    {
        piece_queue.Clear();
        _refill_queue();
    }
}
