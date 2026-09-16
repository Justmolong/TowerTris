using Godot;

public partial class BotAction : RefCounted
{
    public string name = "idle";
    public Godot.Collections.Array sequence = new Godot.Collections.Array();
    public string move = "";
    public float score = 0.0f;
    public Godot.Collections.Dictionary metadata = new Godot.Collections.Dictionary();

    public BotAction(string action_name = "idle", Godot.Collections.Array action_sequence = null,
        string action_move = "", float action_score = 0.0f)
    {
        name = action_name;
        sequence = (action_sequence ?? new Godot.Collections.Array()).Duplicate();
        move = action_move;
        score = action_score;
    }

    public BotAction clone()
    {
        var copy = new BotAction(name, sequence, move, score);
        copy.metadata = metadata.Duplicate(true);
        return copy;
    }

    public Godot.Collections.Dictionary to_dict()
    {
        return new Godot.Collections.Dictionary()
        {
            { "name", name },
            { "sequence", sequence },
            { "move", move },
            { "score", score },
            { "metadata", metadata },
        };
    }
}
