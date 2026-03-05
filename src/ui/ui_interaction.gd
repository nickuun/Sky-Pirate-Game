extends Control
class_name UIInteraction

@onready var prompt_label: Label = $Prompt
@onready var crosshair_label: Label = $Crosshair

func _process(_delta: float) -> void:
	if not Network.session_active:
		visible = false
		return

	visible = true
	var p: PlayerController = _find_local_player()
	if p == null:
		prompt_label.text = ""
		return

	var aim_pos: Vector2 = p.get_aim_screen_position()
	var crosshair_size: Vector2 = crosshair_label.get_combined_minimum_size()
	crosshair_label.position = aim_pos - (crosshair_size * 0.5)
	prompt_label.position = aim_pos + Vector2(-140.0, 20.0)
	prompt_label.text = p.get_interaction_prompt()

func _find_local_player() -> PlayerController:
	for node: Node in get_tree().get_nodes_in_group("player_controller"):
		var p: PlayerController = node as PlayerController
		if p != null and p.is_multiplayer_authority():
			return p
	return null
