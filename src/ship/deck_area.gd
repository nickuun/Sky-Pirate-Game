extends Area3D
class_name ShipDeckArea

@onready var ship: SkyShip = get_parent() as SkyShip

func _ready() -> void:
	add_to_group("ship_deck_area")

func get_ship() -> SkyShip:
	return ship
