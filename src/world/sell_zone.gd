extends Area3D
class_name CargoSellZone

@export var check_interval: float = 0.1

var _check_timer: float = 0.0

func _ready() -> void:
	monitoring = true
	monitorable = true

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = check_interval

	var world: WorldScene = get_tree().current_scene as WorldScene
	if world == null:
		return

	for body: Node3D in get_overlapping_bodies():
		var cargo: CargoCrate = body as CargoCrate
		if cargo == null:
			continue
		if not cargo.holder_paths.is_empty():
			continue
		world.sell_cargo(cargo)
