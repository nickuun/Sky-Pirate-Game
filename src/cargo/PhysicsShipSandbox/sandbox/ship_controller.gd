extends RigidBody3D

@export_category("Drive")
@export var thrust_force: float = 180.0
@export var reverse_force: float = 110.0
@export var strafe_force: float = 20.0
@export var vertical_force: float = 55.0
@export var linear_drag: float = 0.8
@export var max_speed: float = 7.5

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
@export var deck_area_path: NodePath = ^"Deck/DeckArea"

@export_category("Buoyancy")
@export var neutral_buoyancy: bool = true
@export var vertical_velocity_damp: float = 0.7
@export var climb_from_pitch_factor: float = 0.16
@export var max_climb_rate: float = 10.0
@export var altitude_hold_stiffness: float = 28.0
@export var altitude_hold_damping: float = 8.0

var _spawn_transform: Transform3D
var _deck_area: Area3D
var _deck_bodies: Dictionary = {}
var _desired_pitch_radians: float = 0.0
var _altitude_target: float = 0.0
var _yaw_input_current: float = 0.0
var _controls_enabled: bool = true

func _ready() -> void:
	_spawn_transform = global_transform
	_desired_pitch_radians = _get_current_pitch_angle()
	_altitude_target = global_position.y
	if neutral_buoyancy:
		gravity_scale = 0.0
	_deck_area = get_node_or_null(deck_area_path) as Area3D
	if _deck_area:
		_deck_area.body_entered.connect(_on_deck_body_entered)
		_deck_area.body_exited.connect(_on_deck_body_exited)

func _physics_process(delta: float) -> void:
	_apply_ship_drive(delta)
	_apply_stability_torque()
	if deck_assist_enabled:
		_apply_deck_assist()

func reset_ship() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn_transform
	_desired_pitch_radians = _get_current_pitch_angle()
	_altitude_target = global_position.y

func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled

func _apply_ship_drive(delta: float) -> void:
	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	var throttle: float = 0.0
	var strafe: float = 0.0
	if _controls_enabled:
		throttle = float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
		strafe = float(Input.is_key_pressed(KEY_L)) - float(Input.is_key_pressed(KEY_J))

	var thrust: float = thrust_force if throttle >= 0.0 else reverse_force
	apply_central_force(forward * throttle * thrust)
	apply_central_force(right * strafe * strafe_force)

	if neutral_buoyancy:
		# Hard-disable gravity effect so the ship always floats.
		gravity_scale = 0.0
		var current_pitch: float = _get_current_pitch_angle()
		var forward_speed: float = linear_velocity.dot(forward)
		var desired_climb_rate: float = clamp(forward_speed * sin(current_pitch) * climb_from_pitch_factor, -max_climb_rate, max_climb_rate)
		_altitude_target += desired_climb_rate * delta
		var altitude_error: float = _altitude_target - global_position.y
		var float_force_y: float = altitude_error * altitude_hold_stiffness - linear_velocity.y * altitude_hold_damping
		apply_central_force(Vector3.UP * float_force_y * mass)
		apply_central_force(Vector3.UP * (-linear_velocity.y) * vertical_velocity_damp * mass)

	# Cheap drag control keeps the ship responsive without hard-clamping motion.
	apply_central_force(-linear_velocity * linear_drag * mass)
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	var yaw_input: float = 0.0
	if _controls_enabled:
		yaw_input = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
		if yaw_input == 0.0:
			yaw_input = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		if yaw_input == 0.0:
			yaw_input = float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	_yaw_input_current = yaw_input
	# Keep throttle on W/S. Pitch is dedicated to arrows or I/K.
	var pitch_input_arrows: float = 0.0
	var pitch_input_ik: float = 0.0
	if _controls_enabled:
		pitch_input_arrows = float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
		pitch_input_ik = float(Input.is_key_pressed(KEY_K)) - float(Input.is_key_pressed(KEY_I))
	var pitch_input: float = pitch_input_arrows
	if pitch_input == 0.0:
		pitch_input = pitch_input_ik
	var max_pitch_radians: float = deg_to_rad(max_pitch_tilt_degrees)
	var forward_speed: float = max(0.0, linear_velocity.dot(forward))
	var pitch_factor: float = clamp(forward_speed / pitch_speed_for_full_authority, 0.0, 1.0)
	pitch_factor = max(pitch_factor, min_pitch_control_factor)
	if throttle > 0.0:
		pitch_factor = max(pitch_factor, min_pitch_factor_when_throttling)
	# Momentum-scaled pitch control like turning.
	_desired_pitch_radians += pitch_input * deg_to_rad(pitch_input_rate_degrees) * pitch_factor * delta
	_desired_pitch_radians = clamp(_desired_pitch_radians, -max_pitch_radians, max_pitch_radians)

	var turn_factor: float = clamp(forward_speed / turn_speed_for_full_yaw, 0.0, 1.0)
	if throttle > 0.0:
		turn_factor = max(turn_factor, min_turn_factor_when_throttling)
	var yaw_axis: Vector3 = global_basis.y.normalized()
	var desired_yaw_rate: float = yaw_input * max_turn_rate * turn_factor
	var current_yaw_rate: float = angular_velocity.dot(yaw_axis)
	var yaw_rate_error: float = desired_yaw_rate - current_yaw_rate
	apply_torque(yaw_axis * yaw_rate_error * yaw_torque * mass)
	# Optional feed-forward pitch torque (set low/zero for smoother target tracking).
	apply_torque(global_basis.x * pitch_input * pitch_input_torque_boost * mass)
	apply_torque(-angular_velocity * angular_drag * mass)

	if angular_velocity.length() > max_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_angular_speed

func _apply_stability_torque() -> void:
	# Keep pitch player-authored through a target pitch, while roll self-rights strongly.
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
		# Damp pitch rate hard once outside allowed range to prevent runaway inversion.
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

	# Direct velocity damping removes persistent roll oscillation without fighting impacts too hard.
	angular_velocity -= forward_axis * roll_rate * roll_velocity_damp
	var roll_deadzone: float = deg_to_rad(roll_deadzone_degrees)
	var roll_torque_cmd: float = 0.0
	if abs(current_roll) < roll_deadzone and abs(roll_rate) < 0.2:
		# Near upright, prioritize damping but keep a small restoring bias to always settle to level.
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

	# Prevent recovery "donuts": damp and clamp yaw rate when player is not actively yawing.
	var yaw_axis: Vector3 = global_basis.y.normalized()
	var yaw_rate: float = angular_velocity.dot(yaw_axis)
	var yaw_control_factor: float = 1.0 - min(abs(_yaw_input_current), 1.0)
	apply_torque(yaw_axis * (-yaw_rate * yaw_stabilize_damp * yaw_control_factor) * mass)
	if abs(_yaw_input_current) < 0.05:
		# Strongly kill residual spin when player is not asking to turn.
		angular_velocity -= yaw_axis * yaw_rate * idle_yaw_kill_damp
	var clamped_yaw_rate: float = clamp(yaw_rate, -max_yaw_angular_speed, max_yaw_angular_speed)
	var yaw_rate_delta: float = clamped_yaw_rate - yaw_rate
	if abs(yaw_rate_delta) > 0.01:
		angular_velocity += yaw_axis * yaw_rate_delta

	# Hard cap roll rate so momentum cannot cascade into cargo-shedding roll.
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

	# Global angular speed cap as final safety against runaway momentum feedback.
	if angular_velocity.length() > max_total_angular_speed:
		angular_velocity = angular_velocity.normalized() * max_total_angular_speed

func _get_current_pitch_angle() -> float:
	var right_axis: Vector3 = global_basis.x.normalized()
	var ship_forward: Vector3 = (-global_basis.z).normalized()
	var flat_forward: Vector3 = ship_forward - Vector3.UP * ship_forward.dot(Vector3.UP)
	if flat_forward.length_squared() < 0.0001:
		# Fallback when near-vertical to keep angle continuous.
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

		var offset: Vector3 = body.global_position - global_position
		var deck_point_velocity: Vector3 = linear_velocity + angular_velocity.cross(offset)
		var velocity_delta: Vector3 = deck_point_velocity - body.linear_velocity

		# Keep assist mostly planar so strong heave still causes bounce/spill.
		var planar_delta: Vector3 = velocity_delta - ship_up * velocity_delta.dot(ship_up)
		if planar_delta.length() < deck_assist_velocity_deadzone:
			continue
		var assist_force: Vector3 = planar_delta * deck_assist_force * body.mass
		var force_len: float = assist_force.length()
		if force_len > deck_assist_force_max:
			assist_force = assist_force / force_len * deck_assist_force_max

		body.apply_central_force(assist_force)
		body.apply_torque(-body.angular_velocity * deck_spin_damp * body.mass)

	for dead_id in dead_ids:
		_deck_bodies.erase(dead_id)

func _on_deck_body_entered(body: Node) -> void:
	if body == self:
		return
	if body is RigidBody3D and body.is_in_group("cargo"):
		_deck_bodies[body.get_instance_id()] = body

func _on_deck_body_exited(body: Node) -> void:
	if body is RigidBody3D:
		_deck_bodies.erase(body.get_instance_id())
