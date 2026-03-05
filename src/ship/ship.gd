extends RigidBody3D
class_name SkyShip

@export var cruise_speed: float = 5.2
@export var turn_speed_degrees: float = 24.0
@export var climb_speed: float = 2.4
@export var min_flight_altitude: float = -2.0
@export var idle_gravity_scale: float = 0.15
@export var sync_lerp_speed: float = 16.0
@export var sync_position_deadzone: float = 0.035
@export var sync_correction_gain: float = 3.5
@export var max_sync_correction_speed: float = 1.2

@onready var wheel: ShipWheel = $Wheel

var driver_peer_id: int = 0
var _sync_transform: Transform3D
var _sync_linear_velocity: Vector3 = Vector3.ZERO
var _sync_angular_velocity: Vector3 = Vector3.ZERO
var _spawn_transform: Transform3D
var _drive_altitude: float = 0.0
var _drive_yaw: float = 0.0
var _driver_turn_input: float = 0.0
var _driver_pitch_input: float = 0.0

func _ready() -> void:
	_sync_transform = global_transform
	_spawn_transform = global_transform
	_drive_altitude = global_position.y
	_drive_yaw = global_basis.get_euler().y
	set_multiplayer_authority(1)
	can_sleep = false
	add_to_group("sky_ship")

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_run_authoritative_sim(delta)
		sync_state.rpc(global_transform, linear_velocity, angular_velocity, driver_peer_id)
	else:
		_run_remote_sim(delta)

func request_toggle_drive() -> void:
	if multiplayer.is_server():
		_server_toggle_drive(multiplayer.get_unique_id())
	else:
		request_toggle_drive_server.rpc_id(1)

func request_respawn_ship() -> void:
	if multiplayer.is_server():
		_respawn_ship()
	else:
		request_respawn_ship_server.rpc_id(1)

func submit_driver_input(_turn_input: float, _pitch_input: float) -> void:
	if multiplayer.is_server():
		_apply_driver_input(multiplayer.get_unique_id(), _turn_input, _pitch_input)
	else:
		submit_driver_input_server.rpc_id(1, _turn_input, _pitch_input)

func is_driver(peer_id: int) -> bool:
	return driver_peer_id == peer_id

@rpc("any_peer", "reliable")
func request_toggle_drive_server() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	_server_toggle_drive(sender_id)

@rpc("any_peer", "reliable")
func request_respawn_ship_server() -> void:
	if not multiplayer.is_server():
		return
	_respawn_ship()

@rpc("any_peer", "unreliable")
func submit_driver_input_server(_turn_input: float, _pitch_input: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_apply_driver_input(sender_id, _turn_input, _pitch_input)

@rpc("any_peer", "reliable", "call_local")
func set_driver_peer(peer_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return

	var had_driver: bool = driver_peer_id != 0
	driver_peer_id = peer_id
	if driver_peer_id != 0 and not had_driver:
		_drive_altitude = global_position.y
		_drive_yaw = global_basis.get_euler().y
		_driver_turn_input = 0.0
		_driver_pitch_input = 0.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
	elif driver_peer_id == 0 and had_driver:
		_driver_turn_input = 0.0
		_driver_pitch_input = 0.0
		freeze = false

func _server_toggle_drive(sender_id: int) -> void:
	if driver_peer_id == sender_id:
		set_driver_peer.rpc(0)
		return

	if driver_peer_id != 0:
		return

	if not _is_peer_close_to_wheel(sender_id):
		return

	set_driver_peer.rpc(sender_id)

func _run_authoritative_sim(delta: float) -> void:
	if driver_peer_id != 0:
		gravity_scale = 0.0
		freeze = true
		_drive_yaw += deg_to_rad(turn_speed_degrees) * _driver_turn_input * delta
		_drive_altitude += climb_speed * _driver_pitch_input * delta
		_drive_altitude = max(_drive_altitude, min_flight_altitude)

		var previous_position: Vector3 = global_position
		var yaw_basis: Basis = Basis.from_euler(Vector3(0.0, _drive_yaw, 0.0))
		global_basis = yaw_basis

		var fwd: Vector3 = -yaw_basis.z
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		var next_position: Vector3 = previous_position + (fwd * cruise_speed * delta)
		next_position.y = _drive_altitude
		global_position = next_position
		linear_velocity = (global_position - previous_position) / max(0.0001, delta)
		var yaw_rate: float = deg_to_rad(turn_speed_degrees) * _driver_turn_input
		angular_velocity = Vector3.UP * yaw_rate
	else:
		freeze = false
		gravity_scale = idle_gravity_scale
		angular_velocity *= 0.92
		linear_velocity *= 0.9

func _run_remote_sim(delta: float) -> void:
	freeze = true
	gravity_scale = 0.0
	sleeping = false

	var alpha: float = min(1.0, delta * sync_lerp_speed)
	global_transform = global_transform.interpolate_with(_sync_transform, alpha)
	linear_velocity = _sync_linear_velocity
	angular_velocity = _sync_angular_velocity

func _is_peer_close_to_wheel(peer_id: int) -> bool:
	var p: Node3D = get_tree().current_scene.get_node_or_null("Players/%d" % peer_id) as Node3D
	if p == null:
		return false
	return p.global_position.distance_to(wheel.get_driver_anchor().global_position) <= 3.2

@rpc("authority", "unreliable", "call_remote")
func sync_state(next_transform: Transform3D, next_linear_velocity: Vector3, next_angular_velocity: Vector3, next_driver_peer: int) -> void:
	if is_multiplayer_authority():
		return
	_sync_transform = next_transform
	_sync_linear_velocity = next_linear_velocity
	_sync_angular_velocity = next_angular_velocity
	driver_peer_id = next_driver_peer

func _respawn_ship() -> void:
	global_transform = _spawn_transform
	_drive_altitude = global_position.y
	_drive_yaw = global_basis.get_euler().y
	_driver_turn_input = 0.0
	_driver_pitch_input = 0.0
	freeze = false
	gravity_scale = idle_gravity_scale
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_driver_peer.rpc(0)

func _apply_driver_input(sender_id: int, turn_input: float, pitch_input: float) -> void:
	if sender_id != driver_peer_id:
		return
	_driver_turn_input = clamp(turn_input, -1.0, 1.0)
	_driver_pitch_input = clamp(pitch_input, -1.0, 1.0)
