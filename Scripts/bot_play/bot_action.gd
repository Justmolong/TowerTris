extends RefCounted
class_name BotAction

var name: String = "idle"
var sequence: Array = []
var move: String = ""
var score: float = 0.0
var metadata: Dictionary = {}

func _init(action_name: String = "idle", action_sequence: Array = [], action_move: String = "", action_score: float = 0.0):
	name = action_name
	sequence = action_sequence.duplicate()
	move = action_move
	score = action_score

func clone() -> BotAction:
	var copy := BotAction.new(name, sequence, move, score)
	copy.metadata = metadata.duplicate(true)
	return copy

func to_dict() -> Dictionary:
	return {
		"name": name,
		"sequence": sequence,
		"move": move,
		"score": score,
		"metadata": metadata,
	}
