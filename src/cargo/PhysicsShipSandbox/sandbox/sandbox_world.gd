extends Node3D

@export_category("Scene Links")
@export var ship_path: NodePath = ^"Ship"
@export var cargo_container_path: NodePath = ^"CargoContainer"
@export var deck_spawn_anchor_path: NodePath = ^"Ship/CargoSpawnMarker"
@export var cargo_scene: PackedScene = preload("res://src/cargo/PhysicsShipSandbox/cargo/cargo_cube.tscn")

@export_category("Spawn")
@export var initial_cargo_count: int = 8
@export var deck_spawn_half_extents: Vector3 = Vector3(2.1, 0.4, 3.2)
@export var spawn_height_offset: float = 1.6

@export_category("Throw")
@export var throw_speed: float = 17.0
@export var throw_upward_bias: float = 1.5
@export var throw_ship_velocity_inherit: float = 0.75
@export var click_place_offset: float = 0.55

var _ship: RigidBody3D
var _cargo_container: Node3D
var _deck_spawn_anchor: Node3D

func _ready() -> void:
	randomize()
	_ship = get_node_or_null(ship_path) as RigidBody3D
	_cargo_container = get_node_or_null(cargo_container_path) as Node3D
	_deck_spawn_anchor = get_node_or_null(deck_spawn_anchor_path) as Node3D
	if _cargo_container == null:
		_cargo_container = self
	if _ship and _ship.has_method("set_controls_enabled"):
		_ship.call("set_controls_enabled", true)
	_spawn_initial_cargo()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				spawn_cargo_on_deck(1)
			KEY_V:
				throw_cargo_at_ship()
			KEY_R:
				reset_sandbox()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_C):
			_spawn_cargo_at_ship_click()

func spawn_cargo_on_deck(count: int = 1) -> void:
	if cargo_scene == null or _ship == null:
		return

	for _i in count:
		var cargo: RigidBody3D = cargo_scene.instantiate() as RigidBody3D
		if cargo == null:
			continue
		var spawn_pos: Vector3 = _random_deck_spawn_position()
		_cargo_container.add_child(cargo)
		cargo.global_position = spawn_pos
		if cargo.has_method("mark_spawn_from_current"):
			cargo.call("mark_spawn_from_current")

func throw_cargo_at_ship() -> void:
	if cargo_scene == null or _ship == null:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var cargo: RigidBody3D = cargo_scene.instantiate() as RigidBody3D
	if cargo == null:
		return

	var spawn_pos: Vector3 = camera.global_position + (-camera.global_basis.z * 2.2) + (camera.global_basis.y * 0.4)
	var target_pos: Vector3 = _ship.global_position + (_ship.global_basis.y * 1.4)
	var throw_dir: Vector3 = (target_pos - spawn_pos).normalized()

	_cargo_container.add_child(cargo)
	cargo.global_position = spawn_pos
	cargo.linear_velocity = throw_dir * throw_speed + _ship.linear_velocity * throw_ship_velocity_inherit + Vector3.UP * throw_upward_bias
	cargo.angular_velocity = Vector3(
		randf_range(-2.0, 2.0),
		randf_range(-2.0, 2.0),
		randf_range(-2.0, 2.0)
	)

func reset_sandbox() -> void:
	if _ship and _ship.has_method("reset_ship"):
		_ship.call("reset_ship")

	for child in _cargo_container.get_children():
		if child is RigidBody3D and child.is_in_group("cargo"):
			child.queue_free()

	await get_tree().process_frame
	_spawn_initial_cargo()

func _spawn_initial_cargo() -> void:
	spawn_cargo_on_deck(initial_cargo_count)

func _random_deck_spawn_position() -> Vector3:
	var anchor: Node3D = _deck_spawn_anchor if is_instance_valid(_deck_spawn_anchor) else _ship
	var local_offset := Vector3(
		randf_range(-deck_spawn_half_extents.x, deck_spawn_half_extents.x),
		spawn_height_offset + randf_range(0.0, deck_spawn_half_extents.y),
		randf_range(-deck_spawn_half_extents.z, deck_spawn_half_extents.z)
	)
	return anchor.to_global(local_offset)

func _spawn_cargo_at_ship_click() -> void:
	if cargo_scene == null or _ship == null:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_to: Vector3 = ray_from + camera.project_ray_normal(mouse_pos) * 300.0
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: Object = result.get("collider")
	var hit_ship: bool = collider == _ship
	if not hit_ship and collider is Node and is_instance_valid(_ship):
		hit_ship = _ship.is_ancestor_of(collider as Node)
	if not hit_ship:
		return

	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var cargo: RigidBody3D = cargo_scene.instantiate() as RigidBody3D
	if cargo == null:
		return

	_cargo_container.add_child(cargo)
	cargo.global_position = hit_pos + hit_normal * click_place_offset
	if cargo.has_method("mark_spawn_from_current"):
		cargo.call("mark_spawn_from_current")

