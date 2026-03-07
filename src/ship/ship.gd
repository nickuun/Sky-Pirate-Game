extends RigidBody3D
class_name SkyShip

@export var cruise_speed: float = 5.2
@export var turn_speed_degrees: float = 24.0
@export var pitch_speed_degrees: float = 18.0
@export var max_pitch_degrees: float = 28.0
@export var throttle_ramp_seconds: float = 2.0
@export var min_flight_altitude: float = -2.0
@export var idle_sink_speed: float = 0.45
@export var idle_gravity_scale: float = 0.15
@export var sync_lerp_speed: float = 16.0
@export var sync_position_deadzone: float = 0.035
@export var sync_correction_gain: float = 3.5
@export var max_sync_correction_speed: float = 1.2

@onready var wheel: ShipWheel = $Wheel
@onready var deck_area: Area3D = $DeckArea

var driver_peer_id: int = 0
var _sync_transform: Transform3D
var _sync_linear_velocity: Vector3 = Vector3.ZERO
var _sync_angular_velocity: Vector3 = Vector3.ZERO
var _spawn_transform: Transform3D
var _drive_yaw: float = 0.0
var _drive_pitch: float = 0.0
var _drive_throttle: float = 0.0
var _driver_turn_input: float = 0.0
var _driver_pitch_input: float = 0.0
var _driver_accelerating: bool = false
var _driver_decelerating: bool = false

func _ready() -> void:
	_sync_transform = global_transform
	_spawn_transform = global_transform
	var euler: Vector3 = global_basis.get_euler()
	_drive_yaw = euler.y
	_drive_pitch = euler.x
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

func submit_driver_input(_turn_input: float, _pitch_input: float, _accelerating: bool, _decelerating: bool) -> void:
	if multiplayer.is_server():
		_apply_driver_input(multiplayer.get_unique_id(), _turn_input, _pitch_input, _accelerating, _decelerating)
	else:
		submit_driver_input_server.rpc_id(1, _turn_input, _pitch_input, _accelerating, _decelerating)

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
func submit_driver_input_server(_turn_input: float, _pitch_input: float, _accelerating: bool, _decelerating: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_apply_driver_input(sender_id, _turn_input, _pitch_input, _accelerating, _decelerating)

@rpc("any_peer", "reliable", "call_local")
func set_driver_peer(peer_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return

	var had_driver: bool = driver_peer_id != 0
	driver_peer_id = peer_id
	if driver_peer_id != 0 and not had_driver:
		var euler: Vector3 = global_basis.get_euler()
		_drive_yaw = euler.y
		_drive_pitch = euler.x
		_driver_turn_input = 0.0
		_driver_pitch_input = 0.0
	elif driver_peer_id == 0 and had_driver:
		_driver_turn_input = 0.0
		_driver_pitch_input = 0.0
		_driver_accelerating = false
		_driver_decelerating = false

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
		var throttle_step: float = delta / max(0.05, throttle_ramp_seconds)
		if _driver_accelerating and not _driver_decelerating:
			_drive_throttle = min(1.0, _drive_throttle + throttle_step)
		elif _driver_decelerating and not _driver_accelerating:
			_drive_throttle = max(0.0, _drive_throttle - throttle_step)

	if driver_peer_id != 0 or _drive_throttle > 0.001:
		gravity_scale = 0.0
		freeze = true
		var previous_pitch: float = _drive_pitch
		var previous_yaw: float = _drive_yaw
		var motion_ratio: float = clamp(_drive_throttle, 0.0, 1.0)
		if driver_peer_id != 0:
			_drive_yaw += deg_to_rad(turn_speed_degrees) * _driver_turn_input * motion_ratio * delta
		# W (+1) pitches nose down. S (-1) pitches nose up.
		if driver_peer_id != 0:
			_drive_pitch -= deg_to_rad(pitch_speed_degrees) * _driver_pitch_input * motion_ratio * delta
		_drive_pitch = clamp(_drive_pitch, deg_to_rad(-max_pitch_degrees), deg_to_rad(max_pitch_degrees))

		var previous_position: Vector3 = global_position
		var drive_basis: Basis = Basis.from_euler(Vector3(_drive_pitch, _drive_yaw, 0.0))
		global_basis = drive_basis

		var fwd: Vector3 = -drive_basis.z
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		var drive_speed: float = cruise_speed * _drive_throttle
		var requested_motion: Vector3 = fwd * drive_speed * delta
		requested_motion = _clip_motion_with_collision(requested_motion)
		var next_position: Vector3 = previous_position + requested_motion
		next_position.y = max(next_position.y, min_flight_altitude)
		global_position = next_position
		if requested_motion.length() <= 0.0001 and drive_speed > 0.01:
			# Hit something while flying; stop throttle so crashes feel deterministic.
			_drive_throttle = 0.0
		linear_velocity = (global_position - previous_position) / max(0.0001, delta)
		var pitch_delta: float = wrapf(_drive_pitch - previous_pitch, -PI, PI)
		var yaw_delta: float = wrapf(_drive_yaw - previous_yaw, -PI, PI)
		var pitch_rate: float = pitch_delta / max(0.0001, delta)
		var yaw_rate: float = yaw_delta / max(0.0001, delta)
		angular_velocity = (global_basis.x * pitch_rate) + (Vector3.UP * yaw_rate)
	else:
		# Hover-stable idle: no gravity drop and no physics push jitter from players.
		freeze = true
		gravity_scale = 0.0
		var previous_position: Vector3 = global_position
		if _drive_throttle <= 0.001:
			var sink_motion: Vector3 = Vector3.DOWN * idle_sink_speed * delta
			sink_motion = _clip_motion_with_collision(sink_motion)
			global_position += sink_motion
			global_position.y = max(min_flight_altitude, global_position.y)
		linear_velocity = (global_position - previous_position) / max(0.0001, delta)
		angular_velocity = Vector3.ZERO

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

@rpc("any_peer", "reliable", "call_local")
func force_respawn_state(respawn_transform: Transform3D) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	global_transform = respawn_transform
	var euler: Vector3 = global_basis.get_euler()
	_drive_yaw = euler.y
	_drive_pitch = euler.x
	_drive_throttle = 0.0
	_driver_turn_input = 0.0
	_driver_pitch_input = 0.0
	_driver_accelerating = false
	_driver_decelerating = false
	freeze = true
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_sync_transform = global_transform
	_sync_linear_velocity = linear_velocity
	_sync_angular_velocity = angular_velocity

func _respawn_ship() -> void:
	force_respawn_state.rpc(_spawn_transform)
	set_driver_peer.rpc(0)

func _apply_driver_input(sender_id: int, turn_input: float, pitch_input: float, accelerating: bool, decelerating: bool) -> void:
	if sender_id != driver_peer_id:
		return
	_driver_turn_input = clamp(turn_input, -1.0, 1.0)
	_driver_pitch_input = clamp(pitch_input, -1.0, 1.0)
	_driver_accelerating = accelerating
	_driver_decelerating = decelerating

func _clip_motion_with_collision(requested_motion: Vector3) -> Vector3:
	if requested_motion.length() <= 0.000001:
		return Vector3.ZERO

	var from: Transform3D = global_transform
	if not test_move(from, requested_motion):
		return requested_motion

	var low: float = 0.0
	var high: float = 1.0
	for _i: int in range(7):
		var mid: float = (low + high) * 0.5
		if test_move(from, requested_motion * mid):
			high = mid
		else:
			low = mid
	return requested_motion * low

func get_carry_origin() -> Vector3:
	if deck_area != null:
		return deck_area.global_position
	return global_position

func get_turn_input() -> float:
	return _driver_turn_input

func get_throttle() -> float:
	return _drive_throttle
