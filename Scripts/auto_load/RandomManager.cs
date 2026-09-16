using Godot;

/// <summary>
/// 随机数管理器
/// 负责统一管理所有系统的随机数生成，确保确定性
/// 说明：Godot autoload 单例（节点为 RandomManager）；为便于 C# 直接以类名访问，
/// 所有成员实现为 static（autoload 仅实例化一个空节点，状态全部存于静态字段）。
/// </summary>
public partial class RandomManager : Node
{
    // 主随机数生成器
    private static RandomNumberGenerator _rng;

    // 各系统的独立随机数流（字典：系统名称 -> RNG）
    private static Godot.Collections.Dictionary _sub_rngs = new Godot.Collections.Dictionary();

    // ====== 种子字典 ======
    // 存储每个子系统的种子值，系统名称 -> 种子值
    private static Godot.Collections.Dictionary _sub_seeds = new Godot.Collections.Dictionary();

    // 当前使用的种子值
    public static long current_seed_value = 0;

    // 是否已初始化
    private static bool _is_initialized = false;

    /// <summary>
    /// 复刻 GDScript String.hash()（djb2，uint32），保证 GD/C# 生成完全一致的子种子。
    /// Godot 4 String::hash() 实现：hash=5381；对每个字符 hash=((hash<<5)+hash)+c（uint32 环绕）。
    /// 系统名称为 ASCII，逐 char 与逐字节结果一致。
    /// </summary>
    private static long _godot_string_hash(string s)
    {
        uint hash = 5381;
        foreach (char c in s)
        {
            uint cc = (uint)c;
            hash = (hash << 5) + hash + cc;
        }
        return (long)hash;
    }

    /// <summary>初始化随机数管理器</summary>
    public static void initialize(long seed_value)
    {
        current_seed_value = seed_value;

        // 创建主RNG
        _rng = new RandomNumberGenerator();
        _rng.Seed = (ulong)seed_value;

        // 清空并重建字典
        _sub_rngs.Clear();
        _sub_seeds.Clear();

        // 为每个系统创建独立的RNG，使用不同的种子派生方式
        _create_sub_rng(seed_value, "BAG");
        _create_sub_rng(seed_value, "GARBAGE");
        _create_sub_rng(seed_value, "ATTACK");
        _create_sub_rng(seed_value, "TOWER_CLIMB");
        _create_sub_rng(seed_value, "MISC");

        _is_initialized = true;
        // 已注释（调试噪音）：print("随机数管理器已初始化，主种子: ", seed_value)
    }

    /// <summary>使用默认种子初始化（基于时间）</summary>
    public static void initialize_default()
    {
        long seed_value = (long)(Time.GetUnixTimeFromSystem() * 1000.0);
        initialize(seed_value);
    }

    /// <summary>创建子RNG，同时存入种子字典</summary>
    private static RandomNumberGenerator _create_sub_rng(long base_seed, string system_name)
    {
        var sub_rng = new RandomNumberGenerator();
        // 使用字符串哈希生成子种子，确保不同系统获得不同的随机序列
        long sub_seed = base_seed ^ _godot_string_hash(system_name);
        sub_rng.Seed = (ulong)sub_seed;

        // 存入字典
        _sub_rngs[system_name] = sub_rng;
        _sub_seeds[system_name] = sub_seed;  // 种子字典记录

        return sub_rng;
    }

    /// <summary>检查是否已初始化</summary>
    public static bool is_initialized()
    {
        return _is_initialized;
    }

    /// <summary>获取当前种子值</summary>
    public static long get_current_seed()
    {
        return current_seed_value;
    }

    // ========== 通用随机数获取（字符串参数） ==========

    /// <summary>
    /// 通过系统名称获取对应的随机数生成器
    /// 参数 system_name: 系统名称，如 "BAG"、"GARBAGE"、"ATTACK"、"TOWER_CLIMB"、"MISC"
    /// </summary>
    public static RandomNumberGenerator get_random(string system_name)
    {
        if (!_is_initialized)
            initialize_default();
        if (!_sub_rngs.ContainsKey(system_name))
        {
            GD.PushError("RandomManager: 未知的随机数系统 \"", system_name, "\"");
            // 返回杂项RNG作为兜底
            if (_sub_rngs.ContainsKey("MISC"))
                return (RandomNumberGenerator)_sub_rngs["MISC"];
            return _rng;
        }
        return (RandomNumberGenerator)_sub_rngs[system_name];
    }

    /// <summary>
    /// 通过系统名称获取对应的种子值
    /// 参数 system_name: 系统名称，如 "BAG"、"GARBAGE"、"ATTACK"、"TOWER_CLIMB"、"MISC"
    /// </summary>
    public static long get_seed(string system_name)
    {
        if (!_sub_seeds.ContainsKey(system_name))
        {
            GD.PushError("RandomManager: 未知的种子系统 \"", system_name, "\"");
            return 0;
        }
        return (long)_sub_seeds[system_name];
    }

    // ========== 便捷方法（基于通用函数） ==========

    /// <summary>获取一个随机浮点数 (0.0 ~ 1.0) - 使用Bag RNG</summary>
    public static float bag_randf()
    {
        return get_random("BAG").Randf();
    }

    /// <summary>获取一个随机整数 - 使用Bag RNG</summary>
    public static int bag_randi()
    {
        return (int)get_random("BAG").Randi();
    }

    /// <summary>获取一个随机浮点数 (0.0 ~ 1.0) - 使用垃圾行RNG</summary>
    public static float garbage_randf()
    {
        return get_random("GARBAGE").Randf();
    }

    /// <summary>获取一个随机整数 - 使用垃圾行RNG</summary>
    public static int garbage_randi()
    {
        return (int)get_random("GARBAGE").Randi();
    }

    /// <summary>获取一个随机浮点数 (0.0 ~ 1.0) - 使用攻击RNG</summary>
    public static float attack_randf()
    {
        return get_random("ATTACK").Randf();
    }

    /// <summary>获取一个随机整数 - 使用攻击RNG</summary>
    public static int attack_randi()
    {
        return (int)get_random("ATTACK").Randi();
    }

    /// <summary>获取一个随机浮点数 (0.0 ~ 1.0) - 使用杂项RNG</summary>
    public static float misc_randf()
    {
        return get_random("MISC").Randf();
    }

    /// <summary>获取一个随机整数 - 使用杂项RNG</summary>
    public static int misc_randi()
    {
        return (int)get_random("MISC").Randi();
    }

    /// <summary>重置所有RNG（用于Replay）</summary>
    public static void reset_all(long seed_value)
    {
        initialize(seed_value);
    }

    /// <summary>获取所有子种子的字典（用于调试/Replay记录）</summary>
    public static Godot.Collections.Dictionary get_sub_seeds()
    {
        return _sub_seeds.Duplicate();
    }
}
