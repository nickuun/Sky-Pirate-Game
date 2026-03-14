extends RigidBody3D
class_name SkyShip

@export_category("Drive")
@export var thrust_force: float = 180.0
@export var reverse_force: float = 110.0
@export var linear_drag: float = 0.8
@export var max_speed: float = 7.5
@export var throttle_ramp_seconds: float = 2.0
@export var forward_velocity_gain: float = 0.9
@export var side_slip_damp: float = 3.2
@export var vertical_velocity_gain: float = 3.8
@export var pitch_speed_to_climb: float = 1.0

@export_category("Rotation")
@export var yaw_torque: float = 14.0
@export var pitch_input_rate_degrees: float = 14.0
@export var max_pitch_tilt_degrees: float = 45.0
@export var angular_drag: float = 2.4
@export var max_angular_speed: float = 2.2
@export var yaw_stabilize_damp: float = 22.0
@export var max_yaw_angular_speed: float = 1.35
@export var idle_yaw_kill_damp: float = 1.1
@export var max_turn_rate: float = 1.1
@export var turn_speed_for_full_yaw: float = 22.0
@export var min_turn_factor_when_throttling: float = 0.12
@export var pitch_speed_for_full_authority: float = 9.0
@export var min_pitch_factor_when_throttling: float = 0.7
@export var min_pitch_control_factor: float = 0.25

@export_category("Stability")
@export var pitch_hold_torque: float = 280.0
@export var pitch_stabilize_torque: float = 170.0
@export var pitch_input_torque_boost: float = 55.0
@export var max_pitch_correction_torque: float = 12000.0
@export var roll_hold_torque: float = 55.0
@export var roll_stabilize_torque: float = 68.0
@export var max_roll_tilt_degrees: float = 1.5
@export var roll_deadzone_degrees: float = 0.8
@export var pitch_limit_torque: float = 5200.0
@export var max_pitch_angular_speed: float = 0.5
@export var pitch_limit_rate_damp: float = 1.2
@export var roll_limit_torque: float = 1200.0
@export var roll_limit_softness_degrees: float = 1.0
@export var roll_velocity_damp: float = 0.6
@export var min_roll_return_torque: float = 9.0
@export var max_roll_correction_torque: float = 4200.0
@export var upright_recovery_torque: float = 520.0
@export var max_roll_angular_speed: float = 0.45
@export var max_total_angular_speed: float = 1.8

@export_category("Deck Assist")
@export var deck_assist_enabled: bool = true
@export var deck_assist_force: float = 5.5
@export var deck_assist_force_max: float = 85.0
@export var deck_spin_damp: float = 0.35
@export var deck_assist_velocity_deadzone: float = 0.22

@export_category("Buoyancy")
@export var neutral_buoyancy: bool = true
@export var vertical_velocity_damp: float = 1.1
@export var climb_from_pitch_factor: float = 0.16
@export var max_climb_rate: float = 10.0
@export var altitude_hold_stiffness: float = 28.0
@export var altitude_hold_damping: float = 8.0
@export var idle_pitch_return_speed: float = 1.8

@export_category("Networking")
@export var sync_lerp_speed: float = 16.0
@export var sync_position_deadzone: float = 0.035

@onready var wheel: ShipWheel = $Wheel
@onready var deck_area: Area3D = $DeckArea

var driver_peer_id: int = 0

var _sync_transform: Transform3D
var _sync_linear_velocity: Vector3 = Vector3.ZERO
var _sync_angular_velocity: Vector3 = Vector3.ZERO
var _spawn_transform: Transform3D

var _driver_turn_input: float = 0.0
var _driver_pitch_input: float = 0.0
var _driver_accelerating: bool = false
var _driver_decelerating: bool = false
var _drive_throttle: float = 0.0
var _desired_pitch_radians: float = 0.0
var _altitude_target: float = 0.0
var _deck_bodies: Dictionary = {}

func _ready() -> void:
	_sync_transform = global_transform
	_spawn_transform = global_transform
	_desired_pitch_radians = _get_current_pitch_angle()
	_altitude_target = global_position.y
	set_multiplayer_authority(1)
	can_sleep = false
	add_to_group("sky_ship")
	if neutral_buoyancy:
		gravity_scale = 0.0
	if deck_area != null:
		deck_area.body_entered.connect(_on_deck_body_entered)
		deck_area.body_exited.connect(_on_deck_body_exited)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		sleeping = false
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

func submit_driver_input(turn_input: float, pitch_input: float, accelerating: bool, decelerating: bool) -> void:
	if multiplayer.is_server():
		_apply_driver_input(multiplayer.get_unique_id(), turn_input, pitch_input, accelerating, decelerating)
	else:
		submit_driver_input_server.rpc_id(1, turn_input, pitch_input, accelerating, decelerating)

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
func submit_driver_input_server(turn_input: float, pitch_input: float, accelerating: bool, decelerating: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_apply_driver_input(sender_id, turn_input, pitch_input, accelerating, decelerating)

@rpc("any_peer", "reliable", "call_local")
func set_driver_peer(peer_id: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return

	var had_driver: bool = driver_peer_id != 0
	driver_peer_id = peer_id
	if driver_peer_id != 0 and not had_driver:
		_desired_pitch_radians = _get_current_pitch_angle()
		_altitude_target = global_position.y
	if driver_peer_id == 0:
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
	if neutral_buoyancy:
		gravity_scale = 0.0
	freeze = false

	var throttle_step: float = delta / max(0.05, throttle_ramp_seconds)
	if driver_peer_id != 0:
		if _driver_accelerating and not _driver_decelerating:
			_drive_throttle = move_toward(_drive_throttle, 1.0, throttle_step)
		elif _driver_decelerating and not _driver_accelerating:
			_drive_throttle = move_toward(_drive_throttle, 0.0, throttle_step)
	elif abs(_drive_throttle) <= 0.001:
		_desired_pitch_radians = lerpf(_desired_pitch_radians, 0.0, min(1.0, delta * idle_pitch_return_speed))

	_apply_ship_drive(delta)
	_apply_stability_torque()
	if deck_assist_enabled:
		_apply_deck_assist()

func _apply_ship_drive(delta: float) -> void:
	var forward: Vector3 = -global_basis.z
	var throttle: float = _drive_throttle
	var current_forward_speed: float = linear_velocity.dot(forward)
	var desired_forward_speed: float = throttle * max_speed
	var thrust: float = thrust_force if throttle >= 0.0 else reverse_force
	apply_central_force(forward * throttle * thrust)
	apply_central_force(forward * (desired_forward_speed - current_forward_speed) * forward_velocity_gain * mass)

	var world_vertical_velocity: Vector3 = Vector3.UP * linear_velocity.dot(Vector3.UP)
	var side_slip_velocity: Vector3 = linear_velocity - (forward * current_forward_speed) - world_vertical_velocity
	apply_central_force(-side_slip_velocity * side_slip_damp * mass)

	if neutral_buoyancy:
		var current_pitch: float = _get_current_pitch_angle()
		var desired_vertical_speed: float = clamp(
			sin(current_pitch) * abs(desired_forward_speed) * pitch_speed_to_climb * climb_from_pitch_factor,
			-max_climb_rate,
			max_climb_rate
		)
		if abs(throttle) <= 0.01:
			var hover_error: float = _altitude_target - global_position.y
			desired_vertical_speed = clamp(hover_error * 1.6, -max_climb_rate, max_climb_rate)
		else:
			_altitude_target = global_position.y
		var vertical_speed_error: float = desired_vertical_speed - linear_velocity.dot(Vector3.UP)
		apply_central_force(Vector3.UP * vertical_speed_error * vertical_velocity_gain * mass)
		apply_central_force(Vector3.UP * (-linear_velocity.dot(Vector3.UP)) * vertical_velocity_damp * mass)

	apply_central_force(-linear_velocity * linear_drag * mass)
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	var yaw_input: float = _driver_turn_input if driver_peer_id != 0 else 0.0
	var pitch_input: float = _driver_pitch_input if driver_peer_id != 0 else 0.0
	var steering_speed: float = max(abs(desired_forward_speed), max(0.0, current_forward_speed))

	var pitch_control_speed: float = max(0.0, current_forward_speed)
	var pitch_factor: float = clamp(pitch_control_speed / pitch_speed_for_full_authority, 0.0, 1.0)
	_desired_pitch_radians += pitch_input * deg_to_rad(pitch_input_rate_degrees) * pitch_factor * delta
	_desired_pitch_radians = clamp(
		_desired_pitch_radians,
		-deg_to_rad(max_pitch_tilt_degrees),
		deg_to_rad(max_pitch_tilt_degrees)
	)

	var turn_factor: float = clamp(steering_speed / turn_speed_for_full_yaw, 0.0, 1.0)
	if throttle > 0.0:
		turn_factor = max(turn_factor, min_turn_factor_when_throttling)
	var yaw_axis: Vector3 = global_basis.y.normalized()
	var desired_yaw_rate: float = yaw_input * max_turn_rate * turn_factor
	var current_yaw_rate: float = angular_velocity.dot(yaw_axis)
	var yaw_rate_error: float = desired_yaw_rate - current_yaw_rate
	apply_torque(yaw_axis * yaw_rate_error * yaw_torque * mass)

	apply_torque(global_basis.x * pitch_input * pitch_input_torque_boost * pitch_factor * mass)
	apply_torque(-angular_velocity * angular_drag * mass)

	if angular_velocity.length() > max_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_angular_speed

func _apply_stability_torque() -> void:
	var current_pitch: float = _get_current_pitch_angle()
	var pitch_error: float = _desired_pitch_radians - current_pitch
	var pitch_rate: float = angular_velocity.dot(global_basis.x)
	var pitch_torque_cmd: float = (pitch_error * pitch_hold_torque - pitch_rate * pitch_stabilize_torque) * mass

	var max_pitch_radians: float = deg_to_rad(max_pitch_tilt_degrees)
	var pitch_over_limit: float = abs(current_pitch) - max_pitch_radians
	if pitch_over_limit > 0.0:
		var pitch_sign: float = sign(current_pitch)
		var pitch_limit_boost: float = 1.0 + min(pitch_over_limit / deg_to_rad(8.0), 2.0)
		pitch_torque_cmd += (-pitch_sign) * pitch_limit_torque * pitch_limit_boost * mass
		angular_velocity -= global_basis.x * pitch_rate * pitch_limit_rate_damp
	var clamped_pitch_rate: float = clamp(pitch_rate, -max_pitch_angular_speed, max_pitch_angular_speed)
	var pitch_rate_delta: float = clamped_pitch_rate - pitch_rate
	if abs(pitch_rate_delta) > 0.01:
		angular_velocity += global_basis.x * pitch_rate_delta
	pitch_torque_cmd = clamp(pitch_torque_cmd, -max_pitch_correction_torque, max_pitch_correction_torque)
	apply_torque(global_basis.x * pitch_torque_cmd)

	var forward_axis: Vector3 = (-global_basis.z).normalized()
	var current_roll: float = _get_current_roll_angle()
	var roll_rate: float = angular_velocity.dot(forward_axis)

	angular_velocity -= forward_axis * roll_rate * roll_velocity_damp
	var roll_deadzone: float = deg_to_rad(roll_deadzone_degrees)
	var roll_torque_cmd: float = 0.0
	if abs(current_roll) < roll_deadzone and abs(roll_rate) < 0.2:
		var settle_sign: float = -sign(current_roll)
		roll_torque_cmd = (-roll_rate * roll_stabilize_torque * 0.6 + settle_sign * min_roll_return_torque) * mass
	else:
		var roll_error: float = -current_roll
		roll_torque_cmd = (roll_error * roll_hold_torque - roll_rate * roll_stabilize_torque) * mass

	var max_roll_radians: float = deg_to_rad(max_roll_tilt_degrees)
	var softness_radians: float = max(deg_to_rad(roll_limit_softness_degrees), 0.001)
	var abs_roll: float = abs(current_roll)
	var over_limit: float = abs_roll - max_roll_radians
	if over_limit > 0.0:
		var t: float = over_limit / softness_radians
		var correction_strength: float = min(1.0 + t, 2.2)
		var correction_sign: float = -sign(current_roll)
		roll_torque_cmd += correction_sign * roll_limit_torque * correction_strength * mass

	roll_torque_cmd = clamp(roll_torque_cmd, -max_roll_correction_torque, max_roll_correction_torque)
	apply_torque(forward_axis * roll_torque_cmd)

	var yaw_axis: Vector3 = global_basis.y.normalized()
	var yaw_rate: float = angular_velocity.dot(yaw_axis)
	var yaw_control_factor: float = 1.0 - min(abs(_driver_turn_input), 1.0)
	apply_torque(yaw_axis * (-yaw_rate * yaw_stabilize_damp * yaw_control_factor) * mass)
	if abs(_driver_turn_input) < 0.05:
		angular_velocity -= yaw_axis * yaw_rate * idle_yaw_kill_damp
	var clamped_yaw_rate: float = clamp(yaw_rate, -max_yaw_angular_speed, max_yaw_angular_speed)
	var yaw_rate_delta: float = clamped_yaw_rate - yaw_rate
	if abs(yaw_rate_delta) > 0.01:
		angular_velocity += yaw_axis * yaw_rate_delta

	var roll_axis: Vector3 = (-global_basis.z).normalized()
	var roll_rate_now: float = angular_velocity.dot(roll_axis)
	var clamped_roll_rate: float = clamp(roll_rate_now, -max_roll_angular_speed, max_roll_angular_speed)
	var roll_rate_delta: float = clamped_roll_rate - roll_rate_now
	if abs(roll_rate_delta) > 0.01:
		angular_velocity += roll_axis * roll_rate_delta

	var up_alignment: float = global_basis.y.normalized().dot(Vector3.UP)
	if up_alignment < 0.2:
		var recover_axis: Vector3 = global_basis.y.cross(Vector3.UP)
		if recover_axis.length_squared() < 0.0001:
			recover_axis = global_basis.x
		recover_axis = recover_axis.normalized()
		var recover_strength: float = (0.2 - up_alignment) / 1.2
		apply_torque(recover_axis * upright_recovery_torque * recover_strength * mass)

	if angular_velocity.length() > max_total_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_total_angular_speed

func _apply_deck_assist() -> void:
	if _deck_bodies.is_empty():
		return

	var ship_up: Vector3 = global_basis.y.normalized()
	var dead_ids: Array[int] = []
	for id_key in _deck_bodies.keys():
		var body: RigidBody3D = _deck_bodies[id_key]
		if not is_instance_valid(body):
			dead_ids.append(id_key)
			continue
		var cargo: CargoCrate = body as CargoCrate
		if cargo != null and not cargo.holder_paths.is_empty():
			continue

		var offset: Vector3 = body.global_position - global_position
		var deck_point_velocity: Vector3 = linear_velocity + angular_velocity.cross(offset)
		var velocity_delta: Vector3 = deck_point_velocity - body.linear_velocity
		var planar_delta: Vector3 = velocity_delta - ship_up * velocity_delta.dot(ship_up)
		if planar_delta.length() < deck_assist_velocity_deadzone:
			continue
		var assist_force: Vector3 = planar_delta * deck_assist_force * body.mass
		var force_len: float = assist_force.length()
		if force_len > deck_assist_force_max:
			assist_force = assist_force / force_len * deck_assist_force_max

		body.apply_central_force(assist_force)
		body.apply_torque(-body.angular_velocity * deck_spin_damp * body.mass)

	for dead_id: int in dead_ids:
		_deck_bodies.erase(dead_id)

func _get_current_pitch_angle() -> float:
	var right_axis: Vector3 = global_basis.x.normalized()
	var ship_forward: Vector3 = (-global_basis.z).normalized()
	var flat_forward: Vector3 = ship_forward - Vector3.UP * ship_forward.dot(Vector3.UP)
	if flat_forward.length_squared() < 0.0001:
		flat_forward = Vector3.FORWARD - right_axis * Vector3.FORWARD.dot(right_axis)
		if flat_forward.length_squared() < 0.0001:
			flat_forward = Vector3.RIGHT.cross(right_axis)
	flat_forward = flat_forward.normalized()
	return flat_forward.signed_angle_to(ship_forward, right_axis)

func _get_current_roll_angle() -> float:
	var forward_axis: Vector3 = (-global_basis.z).normalized()
	var world_up_proj: Vector3 = (Vector3.UP - forward_axis * Vector3.UP.dot(forward_axis)).normalized()
	var ship_up_proj: Vector3 = (global_basis.y.normalized() - forward_axis * global_basis.y.normalized().dot(forward_axis)).normalized()
	return world_up_proj.signed_angle_to(ship_up_proj, forward_axis)

func _run_remote_sim(delta: float) -> void:
	freeze = true
	gravity_scale = 0.0
	sleeping = false

	var alpha: float = min(1.0, delta * sync_lerp_speed)
	var next_transform: Transform3D = global_transform.interpolate_with(_sync_transform, alpha)
	if global_position.distance_to(_sync_transform.origin) <= sync_position_deadzone:
		next_transform.origin = global_position
	global_transform = next_transform
	linear_velocity = _sync_linear_velocity
	angular_velocity = _sync_angular_velocity

func _is_peer_close_to_wheel(peer_id: int) -> bool:
	var player: Node3D = get_tree().current_scene.get_node_or_null("Players/%d" % peer_id) as Node3D
	if player == null:
		return false
	return player.global_position.distance_to(wheel.get_driver_anchor().global_position) <= 3.2

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
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_drive_throttle = 0.0
	_driver_turn_input = 0.0
	_driver_pitch_input = 0.0
	_driver_accelerating = false
	_driver_decelerating = false
	_desired_pitch_radians = _get_current_pitch_angle()
	_altitude_target = global_position.y
	freeze = not is_multiplayer_authority()
	gravity_scale = 0.0 if neutral_buoyancy else gravity_scale
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

func _on_deck_body_entered(body: Node) -> void:
	var rigid_body: RigidBody3D = body as RigidBody3D
	if rigid_body == null or rigid_body == self:
		return
	if rigid_body is CargoCrate or rigid_body.is_in_group("cargo"):
		_deck_bodies[rigid_body.get_instance_id()] = rigid_body

func _on_deck_body_exited(body: Node) -> void:
	var rigid_body: RigidBody3D = body as RigidBody3D
	if rigid_body == null:
		return
	_deck_bodies.erase(rigid_body.get_instance_id())

func get_carry_origin() -> Vector3:
	if deck_area != null:
		return deck_area.global_position
	return global_position

func get_turn_input() -> float:
	return _driver_turn_input

func get_throttle() -> float:
	return _drive_throttle
