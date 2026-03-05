extends Area3D
class_name ShipWheel

@onready var ship: SkyShip = get_parent() as SkyShip
@onready var driver_anchor: Marker3D = $DriverAnchor

func _ready() -> void:
	add_to_group("ship_wheel")

func interact(player: PlayerController) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	ship.request_toggle_drive()

func get_interaction_prompt(local_peer_id: int) -> String:
	if ship == null:
		return ""
	if ship.is_driver(local_peer_id):
		return "E: Leave Wheel"
	if ship.driver_peer_id == 0:
		return "E: Drive Wheel"
	return "Wheel in use"

func get_driver_anchor() -> Marker3D:
	return driver_anchor
