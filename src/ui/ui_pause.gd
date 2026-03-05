extends Control
class_name UIPause

@onready var panel: PanelContainer = $Panel
@onready var resume_button: Button = $Panel/Margin/VBox/ResumeButton
@onready var respawn_button: Button = $Panel/Margin/VBox/RespawnButton
@onready var respawn_ship_button: Button = $Panel/Margin/VBox/RespawnShipButton

func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	respawn_button.pressed.connect(_on_respawn_pressed)
	respawn_ship_button.pressed.connect(_on_respawn_ship_pressed)
	Network.session_active_changed.connect(_on_session_active_changed)
	_on_session_active_changed(Network.session_active)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_session_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _is_session_active() and not visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_menu() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed() -> void:
	_close_menu()

func _on_respawn_pressed() -> void:
	var p: PlayerController = _find_local_player()
	if p != null:
		p.request_respawn()
	_close_menu()

func _on_respawn_ship_pressed() -> void:
	if not multiplayer.is_server():
		return
	for n: Node in get_tree().get_nodes_in_group("sky_ship"):
		var ship: SkyShip = n as SkyShip
		if ship != null:
			ship.request_respawn_ship()
	_close_menu()

func _find_local_player() -> PlayerController:
	for node: Node in get_tree().get_nodes_in_group("player_controller"):
		var p: PlayerController = node as PlayerController
		if p != null and p.is_multiplayer_authority():
			return p
	return null

func _is_session_active() -> bool:
	return Network.session_active

func _on_session_active_changed(_active: bool) -> void:
	respawn_ship_button.visible = multiplayer.is_server()
