extends RigidBody3D
class_name CargoCrate

@export var follow_lerp_speed: float = 18.0
@export var sync_lerp_speed: float = 22.0
@export var control_request_range: float = 6.0
@export var max_linear_speed: float = 16.0
@export var max_angular_speed: float = 10.0
@export var sync_position_deadzone: float = 0.03
@export var ship_deck_area_mask: int = 16
@export var ship_carry_lerp_speed: float = 18.0
@export var ship_latch_duration: float = 0.25
@export var ship_turn_drift_compensation: float = -5
@export var ship_turn_drift_compensation_right_scale: float = 3

var holder_path: NodePath = NodePath("")
var holder_peer_id: int = 0
var sim_peer_id: int = 1
var _default_collision_layer: int = 0
var _default_collision_mask: int = 0
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _target_transform: Transform3D
var _target_linear_velocity: Vector3 = Vector3.ZERO
var _target_angular_velocity: Vector3 = Vector3.ZERO
var _target_on_ship: bool = false
var _target_ship_relative_transform: Transform3D = Transform3D.IDENTITY
var _latched_ship: SkyShip = null
var _latched_ship_transform: Transform3D = Transform3D.IDENTITY
var _ship_latch_time_remaining: float = 0.0

func _ready() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_target_transform = global_transform
	contact_monitor = true
	max_contacts_reported = 8
	set_sim_authority(1)
	_apply_hold_collision_state()

func is_held_by(peer_id: int) -> bool:
	return holder_peer_id == peer_id and not holder_path.is_empty()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_run_authoritative_physics(delta)
		var support_ship: SkyShip = _find_support_ship()
		var on_ship: bool = support_ship != null and holder_path.is_empty()
		var relative_transform: Transform3D = Transform3D.IDENTITY
		if on_ship:
			relative_transform = support_ship.global_transform.affine_inverse() * global_transform
			relative_transform.basis = relative_transform.basis.orthonormalized()
		sync_state.rpc(global_transform, linear_velocity, angular_velocity, on_ship, relative_transform)
	else:
		apply_remote_state(delta)

func _run_authoritative_physics(delta: float) -> void:
	if holder_path.is_empty() or not has_node(holder_path):
		freeze = false
		_update_ship_latch_state(delta)
		_apply_ship_carry(delta)
		_limit_motion()
		return

	var holder: Node3D = get_node(holder_path) as Node3D
	if holder == null:
		freeze = false
		_clear_ship_latch()
		return

	freeze = true
	_clear_ship_latch()
	global_basis = global_basis.orthonormalized().slerp(holder.global_basis.orthonormalized(), min(1.0, delta * 12.0))
	_move_held_towards(holder.global_position, delta)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _limit_motion() -> void:
	if linear_velocity.length() > max_linear_speed:
		linear_velocity = linear_velocity.normalized() * max_linear_speed
	if angular_velocity.length() > max_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_angular_speed

func _apply_ship_carry(delta: float) -> void:
	if _latched_ship == null or not is_instance_valid(_latched_ship):
		_clear_ship_latch()
		return
	if _ship_latch_time_remaining <= 0.0:
		_clear_ship_latch()
		return

	var current_ship_transform: Transform3D = _latched_ship.global_transform
	var ship_delta: Transform3D = current_ship_transform * _latched_ship_transform.affine_inverse()
	var target_position: Vector3 = ship_delta * global_position
	var carry_velocity: Vector3 = (target_position - global_position) / max(0.0001, delta)
	var alpha: float = min(1.0, delta * ship_carry_lerp_speed)
	linear_velocity = linear_velocity.lerp(carry_velocity, alpha)
	_apply_turn_drift_compensation(delta)
	_latched_ship_transform = current_ship_transform

func _apply_turn_drift_compensation(delta: float) -> void:
	if _latched_ship == null or not is_instance_valid(_latched_ship):
		return

	var turn_input: float = _latched_ship.get_turn_input()
	if abs(turn_input) <= 0.001:
		return

	# Direct steering-based counter-push.
	# A (-1) pushes cargo forward on ship, D (+1) pushes it backward.
	var compensation: float = ship_turn_drift_compensation
	if turn_input > 0.0:
		compensation *= ship_turn_drift_compensation_right_scale
	linear_velocity += (_latched_ship.global_basis.z * turn_input) * compensation * delta

func apply_remote_state(delta: float) -> void:
	freeze = true
	if _target_on_ship:
		var ship: SkyShip = _get_primary_ship()
		if ship != null:
			_target_transform = ship.global_transform * _target_ship_relative_transform
			_target_transform.basis = _target_transform.basis.orthonormalized()

	var alpha: float = min(1.0, delta * sync_lerp_speed)
	var next_transform: Transform3D = global_transform.interpolate_with(_target_transform, alpha)
	var pos_error: Vector3 = _target_transform.origin - global_position
	if pos_error.length() <= sync_position_deadzone:
		next_transform.origin = global_position
	global_transform = next_transform
	linear_velocity = _target_linear_velocity
	angular_velocity = _target_angular_velocity

@rpc("any_peer", "reliable")
func request_control() -> void:
	if not multiplayer.is_server():
		return
	# Cargo simulation stays server-authoritative to avoid authority thrash/desync.
	return

@rpc("any_peer", "reliable")
func request_pickup(target_holder_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if holder_peer_id != 0 and holder_peer_id != sender_id:
		return

	# While held, make the holder peer authoritative for responsive local carry.
	set_sim_authority.rpc(sender_id)
	set_holder.rpc(target_holder_path, sender_id)

@rpc("any_peer", "reliable")
func request_drop() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if holder_peer_id != sender_id:
		return

	# Neutral drop by default to prevent impulse spikes after hold.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_holder.rpc(NodePath(""), 0)
	# Return cargo simulation authority to server once released.
	set_sim_authority.rpc(1)

@rpc("any_peer", "reliable", "call_local")
func set_holder(target_holder_path: NodePath, target_peer_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	holder_path = target_holder_path
	holder_peer_id = target_peer_id
	_apply_hold_collision_state()

@rpc("any_peer", "reliable", "call_local")
func set_sim_authority(target_peer_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	sim_peer_id = max(1, target_peer_id)
	set_multiplayer_authority(sim_peer_id)
	sleeping = false

@rpc("authority", "unreliable", "call_remote")
func sync_state(next_transform: Transform3D, next_linear_velocity: Vector3, next_angular_velocity: Vector3, next_on_ship: bool, next_ship_relative_transform: Transform3D) -> void:
	if is_multiplayer_authority():
		return
	_target_transform = next_transform
	_target_linear_velocity = next_linear_velocity
	_target_angular_velocity = next_angular_velocity
	_target_on_ship = next_on_ship
	_target_ship_relative_transform = next_ship_relative_transform

func _apply_hold_collision_state() -> void:
	var is_held: bool = not holder_path.is_empty() and holder_peer_id != 0
	if is_held:
		collision_layer = 0
		collision_mask = 0
		return
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask

func _move_held_towards(target_position: Vector3, delta: float) -> void:
	var alpha: float = min(1.0, delta * follow_lerp_speed)
	var start_position: Vector3 = global_position
	var desired_position: Vector3 = start_position.lerp(target_position, alpha)
	var start_blocked: bool = _is_held_position_blocked(start_position)

	if start_blocked:
		var unblocked_position: Vector3 = _find_first_unblocked_on_path(start_position, desired_position)
		if unblocked_position.distance_to(start_position) > 0.0001:
			global_position = unblocked_position
			return

	if not _is_held_position_blocked(desired_position):
		global_position = desired_position
		return

	# Try component-wise movement first so held cargo can slide along walls/rails.
	var slid_position: Vector3 = _move_held_with_axis_slide(start_position, desired_position)
	if slid_position.distance_to(start_position) > 0.0001:
		global_position = slid_position
		return

	var low: float = 0.0
	var high: float = 1.0
	for _i: int in range(6):
		var mid: float = (low + high) * 0.5
		var probe_position: Vector3 = start_position.lerp(desired_position, mid)
		if _is_held_position_blocked(probe_position):
			high = mid
		else:
			low = mid

	global_position = start_position.lerp(desired_position, low)

func _move_held_with_axis_slide(start_position: Vector3, desired_position: Vector3) -> Vector3:
	var delta: Vector3 = desired_position - start_position
	var components: Array[Vector3] = [
		Vector3(delta.x, 0.0, 0.0),
		Vector3(0.0, delta.y, 0.0),
		Vector3(0.0, 0.0, delta.z)
	]

	# Largest movement first gives a more natural "slide then settle" feel.
	components.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.length_squared() > b.length_squared()
	)

	var current: Vector3 = start_position
	for component: Vector3 in components:
		if component.length_squared() <= 0.0000001:
			continue
		var candidate: Vector3 = current + component
		if not _is_held_position_blocked(candidate):
			current = candidate

	return current

func _find_first_unblocked_on_path(start_position: Vector3, desired_position: Vector3) -> Vector3:
	var samples: int = 10
	for i: int in range(1, samples + 1):
		var t: float = float(i) / float(samples)
		var probe_position: Vector3 = start_position.lerp(desired_position, t)
		if not _is_held_position_blocked(probe_position):
			return probe_position
	return start_position

func _is_held_position_blocked(candidate_position: Vector3) -> bool:
	if _collision_shape == null or _collision_shape.shape == null:
		return false

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _collision_shape.shape
	params.transform = Transform3D(global_basis, candidate_position)
	params.exclude = [get_rid()]
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(params, 16)
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		if collider == null:
			continue
		if collider is PlayerController:
			continue
		if collider is CargoCrate:
			continue
		if collider is ShipWheel:
			continue
		if collider is SkyShip:
			return true
		if collider is StaticBody3D:
			return true
	return false

func _update_ship_latch_state(delta: float) -> void:
	var ship: SkyShip = _find_support_ship()
	if ship == null:
		if _latched_ship == null:
			return
		_ship_latch_time_remaining = max(0.0, _ship_latch_time_remaining - delta)
		if _ship_latch_time_remaining <= 0.0:
			_clear_ship_latch()
		return

	if _latched_ship == null or _latched_ship != ship:
		_latched_ship = ship
		_latched_ship_transform = ship.global_transform
	_latched_ship = ship
	_ship_latch_time_remaining = ship_latch_duration

func _clear_ship_latch() -> void:
	_latched_ship = null
	_ship_latch_time_remaining = 0.0

func _find_contact_ship() -> SkyShip:
	var bodies: Array[Node3D] = get_colliding_bodies()
	for body: Node3D in bodies:
		var ship: SkyShip = body as SkyShip
		if ship != null:
			return ship
	return null

func _find_support_ship() -> SkyShip:
	return _find_contact_ship()

func _probe_ship_deck_area_at(sample_position: Vector3) -> SkyShip:
	var params := PhysicsPointQueryParameters3D.new()
	params.position = sample_position + Vector3(0.0, -0.2, 0.0)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = ship_deck_area_mask
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_point(params, 8)
	for hit: Dictionary in hits:
		var area: ShipDeckArea = hit.get("collider") as ShipDeckArea
		if area == null:
			continue
		var ship: SkyShip = area.get_ship()
		if ship != null:
			return ship
	return null

func _get_primary_ship() -> SkyShip:
	var ships: Array[Node] = get_tree().get_nodes_in_group("sky_ship")
	for node: Node in ships:
		var ship: SkyShip = node as SkyShip
		if ship != null:
			return ship
	return null
