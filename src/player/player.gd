extends CharacterBody3D
class_name PlayerController

const ANIM_IDLE: StringName = &"standing"
const ANIM_RUN: StringName = &"run"
const ANIM_CARRY_IDLE: StringName = &"carry"
const ANIM_CARRY_RUN: StringName = &"run_with_arms"
const ANIM_RAGDOLL: StringName = &"disagree"

@export var move_speed: float = 6.0
@export var acceleration: float = 18.0
@export var deceleration: float = 22.0
@export var jump_velocity: float = 5.0
@export var gravity: float = 12.0
@export var carry_mass_speed_penalty: float = 0.08
@export var carry_mass_jump_penalty: float = 0.1
@export var throw_charge_duration: float = 0.9
@export var throw_speed_min: float = 6.0
@export var throw_speed_max: float = 24.0
@export var hold_swing_velocity_gain: float = 1.25
@export var max_hold_swing_velocity: float = 22.0
@export var cargo_push_base_force: float = 1.0
@export var cargo_push_impulse_scale: float = 1.2
@export var cargo_push_max_impulse: float = 4.8
@export var ragdoll_fall_height: float = 4.5
@export var ragdoll_fall_impulse_scale: float = 1.1
@export var ragdoll_duration: float = 1.1
@export var ragdoll_spin_speed: float = 6.0
@export var ragdoll_max_duration: float = 3.0
@export var ragdoll_recover_speed_threshold: float = 0.55
@export var ragdoll_floor_settle_time: float = 0.4
@export var ragdoll_ground_friction: float = 8.5
@export var ragdoll_air_drag: float = 0.8
@export var ragdoll_onset_tilt_degrees: float = 78.0
@export var ragdoll_onset_spin_boost: float = 1.8

@export var waddle_tilt_degrees: float = 8.0
@export var waddle_bob_amount: float = 0.06
@export var waddle_bob_speed: float = 10.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_degrees: float = -85.0
@export var max_pitch_degrees: float = 80.0
@export var pickup_range: float = 7.0
@export var cargo_control_range: float = 2.0
@export var floor_max_angle_degrees: float = 42.0
@export var floor_snap_distance: float = 0.45
@export var ship_latch_duration: float = 0.35
@export var ship_air_latch_duration: float = 0.75
@export var ship_probe_distance: float = 1.35
@export var ship_deck_area_mask: int = 16
@export var ship_climb_speed: float = 4.2
@export var wheel_lock_lerp_speed: float = 12.0
@export var wheel_lock_blend_duration: float = 0.18
@export var drive_collision_grace_duration: float = 0.2
@export var remote_pos_smooth_speed: float = 22.0
@export var remote_rot_smooth_speed: float = 24.0
@export var remote_pos_deadzone: float = 0.015
@export var aim_screen_offset: Vector2 = Vector2.ZERO

@onready var visual: Node3D = $Visual
@onready var body_collision: CollisionShape3D = $CapsuleShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var hold_point: Marker3D = $CameraPivot/HoldPoint
@onready var avatar: Node3D = $Visual/Avatar
@onready var avatar_animation_player: AnimationPlayer = $Visual/Avatar/AnimationPlayer

var _move_input: Vector2 = Vector2.ZERO
var _waddle_time: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _held_cargo: CargoCrate = null
var _spawn_position: Vector3 = Vector3.ZERO
var _cargo_control_cooldown: float = 0.0
var _driving_wheel: ShipWheel = null
var _drive_collision_disabled: bool = false
var _was_driving: bool = false
var _wheel_lock_blend_time_remaining: float = 0.0
var _drive_collision_grace_remaining: float = 0.0
var _latched_ship: SkyShip = null
var _latched_ship_transform: Transform3D = Transform3D.IDENTITY
var _ship_latch_time_remaining: float = 0.0
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_basis: Basis = Basis.IDENTITY
var _remote_target_velocity: Vector3 = Vector3.ZERO
var _remote_target_visual_position: Vector3 = Vector3.ZERO
var _remote_target_visual_basis: Basis = Basis.IDENTITY
var _remote_target_on_ship: bool = false
var _remote_target_ship_rel_position: Vector3 = Vector3.ZERO
var _remote_target_ship_rel_basis: Basis = Basis.IDENTITY
var _throw_charging: bool = false
var _throw_charge_time: float = 0.0
var _hull_contact_ship: SkyShip = null
var _hull_contact_normal: Vector3 = Vector3.ZERO
var _is_ragdolled: bool = false
var _ragdoll_time_remaining: float = 0.0
var _ragdoll_spin_velocity: Vector3 = Vector3.ZERO
var _ragdoll_floor_time: float = 0.0
var _fall_tracking_active: bool = false
var _fall_start_height: float = 0.0
var _hold_point_prev_global: Vector3 = Vector3.ZERO
var _hold_point_velocity: Vector3 = Vector3.ZERO
var _hold_point_tracking_ready: bool = false
var _default_body_collision_transform: Transform3D = Transform3D.IDENTITY
var _current_avatar_animation: StringName = &""
var _avatar_death_played: bool = false

func _ready() -> void:
	add_to_group("player_controller")
	# We apply ship follow manually to avoid double platform velocity + correction jitter.
	platform_floor_layers = 0
	platform_wall_layers = 0
	floor_snap_length = floor_snap_distance
	floor_stop_on_slope = false
	floor_max_angle = deg_to_rad(floor_max_angle_degrees)
	_spawn_position = global_position
	_yaw = rotation.y
	_pitch = camera_pivot.rotation.x
	_remote_target_position = global_position
	_remote_target_basis = basis
	_remote_target_velocity = velocity
	_remote_target_visual_position = visual.position
	_remote_target_visual_basis = visual.basis
	if body_collision != null:
		_default_body_collision_transform = body_collision.transform
	Network.server_started.connect(_on_session_started)
	Network.connected_to_server.connect(_on_session_started)
	Network.disconnected.connect(_on_session_ended)
	_configure_avatar_animations()
	_update_camera_state()
	_on_session_started()
	_update_avatar_animation()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_apply_remote_state(delta)
		_update_avatar_animation()
		return

	_update_driving_wheel_reference()
	var driving_now: bool = _is_driving()
	if driving_now != _was_driving:
		_wheel_lock_blend_time_remaining = wheel_lock_blend_duration
		_drive_collision_grace_remaining = drive_collision_grace_duration
	_was_driving = driving_now
	_drive_collision_grace_remaining = max(0.0, _drive_collision_grace_remaining - delta)
	_update_drive_collision_state(driving_now)
	_update_hold_point_kinematics(delta)
	_read_input()
	_update_throw_charge(delta)
	_update_fall_tracking()
	if _is_ragdolled:
		_apply_ragdoll_sim(delta)
		_update_drive_collision_state(false)
		_update_avatar_animation()
		sync_state.rpc(global_position, basis, velocity, visual.position, visual.basis, false, Vector3.ZERO, Basis.IDENTITY, true)
		return
	_update_ship_latch_state(delta)
	_apply_latched_ship_follow(delta)
	if driving_now:
		_apply_drive_control()
	else:
		_apply_gravity(delta)
		_apply_movement(delta)
	_apply_waddle(delta)
	_update_cargo_control_request(delta)
	_try_interact()
	if driving_now:
		_clear_ship_latch()
		_lock_to_wheel(delta)
	else:
		move_and_slide()
		_apply_cargo_push_contacts()
		_refresh_ship_hull_contact()
		_update_ship_latch_state(0.0)
		_restore_upright_body(delta)
		_restore_body_collision_transform(delta)

	_update_avatar_animation()

	var support_ship: SkyShip = _get_sync_support_ship()
	var on_ship: bool = support_ship != null
	var rel_position: Vector3 = Vector3.ZERO
	var rel_basis: Basis = Basis.IDENTITY
	if on_ship:
		rel_position = support_ship.to_local(global_position)
		rel_basis = (support_ship.global_basis.inverse() * basis).orthonormalized()
	sync_state.rpc(global_position, basis, velocity, visual.position, visual.basis, on_ship, rel_position, rel_basis, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PATH_RENAMED:
		_update_camera_state()

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_session_active():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _can_start_throw():
			_throw_charging = true
			_throw_charge_time = 0.0
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _throw_charging:
			_release_throw()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		rotation.y = _yaw
		camera_pivot.rotation.x = _pitch

func _read_input() -> void:
	if _is_driving():
		_move_input = Vector2.ZERO
		return
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

func _apply_gravity(delta: float) -> void:
	if _is_ship_hull_climbing():
		velocity.y = move_toward(velocity.y, 0.0, gravity * delta)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _get_effective_jump_velocity()

func _apply_movement(delta: float) -> void:
	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized()

	var forward_input: float = -_move_input.y
	var input_dir: Vector3 = (right * _move_input.x) + (forward * forward_input)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var target_vel: Vector3 = input_dir * _get_effective_move_speed()
	target_vel.y = velocity.y

	var horiz_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var target_horiz: Vector3 = Vector3(target_vel.x, 0.0, target_vel.z)

	if _is_ship_hull_climbing():
		target_horiz *= 0.45
		var climb_input: float = 0.0
		if Input.is_action_pressed("jump"):
			climb_input = 1.0
		elif Input.is_action_pressed("move_back"):
			climb_input = -1.0
		if abs(climb_input) > 0.05:
			var climb_target: float = clamp(climb_input, -1.0, 1.0) * ship_climb_speed
			velocity.y = lerp(velocity.y, climb_target, 1.0 - exp(-10.0 * delta))
		else:
			velocity.y = move_toward(velocity.y, 0.0, gravity * delta)

	var rate: float = acceleration if input_dir.length() > 0.0 else deceleration
	var new_horiz: Vector3 = horiz_vel.lerp(target_horiz, 1.0 - exp(-rate * delta))

	velocity.x = new_horiz.x
	velocity.z = new_horiz.z

func _apply_waddle(delta: float) -> void:
	var horiz_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var moving: bool = horiz_speed > 0.1

	if moving:
		_waddle_time += delta
	else:
		_waddle_time = 0.0

	# Visual bob
	var bob: float = 0.0
	if moving:
		bob = sin(_waddle_time * waddle_bob_speed) * waddle_bob_amount

	var pos: Vector3 = visual.position
	pos.y = bob
	visual.position = pos

	# Visual tilt (Fall Guys vibe but controllable)
	var tilt_x: float = 0.0
	var tilt_z: float = 0.0
	if moving:
		tilt_x = _move_input.y * deg_to_rad(waddle_tilt_degrees)
		tilt_z = _move_input.x * deg_to_rad(waddle_tilt_degrees)

	var target_basis: Basis = Basis.from_euler(Vector3(tilt_x, 0.0, tilt_z))
	visual.basis = visual.basis.slerp(target_basis, 1.0 - exp(-14.0 * delta))

func _try_interact() -> void:
	if _is_ragdolled:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	if _is_driving():
		if _driving_wheel != null:
			_driving_wheel.interact(self)
		return

	if _held_cargo != null and _held_cargo.is_held_by(multiplayer.get_unique_id()):
		_request_drop(_held_cargo)
		_held_cargo = null
		return

	var target: Object = _get_interaction_target()
	if target == null:
		return

	var wheel: ShipWheel = target as ShipWheel
	if wheel != null:
		wheel.interact(self)
		_update_driving_wheel_reference()
		return

	var cargo: CargoCrate = target as CargoCrate
	if cargo == null:
		return

	_request_pickup(cargo)
	_held_cargo = cargo

func _update_cargo_control_request(delta: float) -> void:
	# Cargo is server-authoritative; no client authority handoff requests.
	return

func _request_pickup(cargo: CargoCrate) -> void:
	if multiplayer.is_server():
		cargo.request_pickup(hold_point.get_path())
	else:
		cargo.request_pickup.rpc_id(1, hold_point.get_path())

func _request_drop(cargo: CargoCrate) -> void:
	var release_transform: Transform3D = cargo.global_transform
	var release_linear_velocity: Vector3 = _compose_cargo_release_velocity()
	var release_angular_velocity: Vector3 = cargo.angular_velocity
	if multiplayer.is_server():
		cargo.request_drop(release_transform, release_linear_velocity, release_angular_velocity)
	else:
		cargo.request_drop.rpc_id(1, release_transform, release_linear_velocity, release_angular_velocity)

func request_respawn() -> void:
	if not is_multiplayer_authority():
		return
	_respawn()

@rpc("any_peer", "reliable", "call_local")
func force_respawn_from_server() -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_respawn()

func get_interaction_prompt() -> String:
	if not is_multiplayer_authority() or not _is_session_active():
		return ""
	if _is_driving():
		return "E: Leave Wheel"
	if _held_cargo != null and _held_cargo.is_held_by(multiplayer.get_unique_id()):
		return "E: Drop Cargo"

	var target: Object = _get_interaction_target()
	if target == null:
		return ""

	var wheel: ShipWheel = target as ShipWheel
	if wheel != null:
		return wheel.get_interaction_prompt(multiplayer.get_unique_id())

	var cargo: CargoCrate = target as CargoCrate
	if cargo != null:
		return "E: Pick up Cargo"

	return ""

func _respawn() -> void:
	_driving_wheel = null
	_was_driving = false
	_wheel_lock_blend_time_remaining = 0.0
	_drive_collision_grace_remaining = 0.0
	_clear_ship_latch()
	_exit_ragdoll()
	_throw_charging = false
	_throw_charge_time = 0.0
	_remote_target_on_ship = false
	_hold_point_tracking_ready = false
	_hold_point_velocity = Vector3.ZERO
	if body_collision != null:
		body_collision.transform = _default_body_collision_transform
	global_position = _spawn_position + Vector3(0.0, 1.0, 0.0)
	velocity = Vector3.ZERO

@rpc("any_peer", "reliable", "call_local")
func force_ragdoll_from_server(impulse: Vector3) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_enter_ragdoll(impulse)

@rpc("any_peer", "reliable")
func request_ragdoll_from_hit(impulse: Vector3) -> void:
	if not multiplayer.is_server():
		return
	force_ragdoll_from_server.rpc(impulse)

@rpc("any_peer", "unreliable", "call_remote")
func sync_state(pos: Vector3, body_basis: Basis, body_velocity: Vector3, visual_pos: Vector3, visual_basis: Basis, on_ship: bool, ship_rel_pos: Vector3, ship_rel_basis: Basis, ragdolled: bool) -> void:
	if is_multiplayer_authority():
		return

	_remote_target_position = pos
	_remote_target_basis = body_basis
	_remote_target_velocity = body_velocity
	_remote_target_visual_position = visual_pos
	_remote_target_visual_basis = visual_basis
	_remote_target_on_ship = on_ship
	_remote_target_ship_rel_position = ship_rel_pos
	_remote_target_ship_rel_basis = ship_rel_basis
	if ragdolled:
		if not _is_ragdolled:
			_is_ragdolled = true
			_avatar_death_played = false
	else:
		if _is_ragdolled:
			_exit_ragdoll()

func _update_camera_state() -> void:
	if camera == null:
		return
	camera.current = is_multiplayer_authority()

func _on_session_started() -> void:
	if camera.current and _is_session_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_driving_wheel_reference()

func _on_session_ended() -> void:
	if camera.current:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_driving_wheel = null
	_was_driving = false
	_wheel_lock_blend_time_remaining = 0.0
	_drive_collision_grace_remaining = 0.0
	_throw_charging = false
	_throw_charge_time = 0.0
	_exit_ragdoll()
	_clear_ship_latch()
	_remote_target_on_ship = false
	_hold_point_tracking_ready = false
	_hold_point_velocity = Vector3.ZERO
	if body_collision != null:
		body_collision.transform = _default_body_collision_transform

func _is_session_active() -> bool:
	return Network.session_active

func _get_interaction_target() -> Object:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null

	var aim_pos: Vector2 = get_aim_screen_position()
	var from: Vector3 = camera.project_ray_origin(aim_pos)
	var to: Vector3 = from + (camera.project_ray_normal(aim_pos) * pickup_range)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 11
	query.exclude = [get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.get("collider")

func get_aim_screen_position() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var size: Vector2 = viewport.get_visible_rect().size
	return (size * 0.5) + aim_screen_offset

func _is_driving() -> bool:
	if _driving_wheel == null:
		return false
	var ship: SkyShip = _driving_wheel.ship
	if ship == null:
		return false
	return ship.is_driver(multiplayer.get_unique_id())

func _update_driving_wheel_reference() -> void:
	_driving_wheel = null
	var wheels: Array[Node] = get_tree().get_nodes_in_group("ship_wheel")
	for node: Node in wheels:
		var wheel: ShipWheel = node as ShipWheel
		if wheel != null and wheel.ship.is_driver(multiplayer.get_unique_id()):
			_driving_wheel = wheel
			return

func _apply_drive_control() -> void:
	if _driving_wheel == null:
		return
	var ship: SkyShip = _driving_wheel.ship
	if ship == null:
		return

	# A/D steer trim latch. W/S pitch nose. Shift/Ctrl adjust throttle.
	var turn_input: float = Input.get_axis("move_left", "move_right")
	var pitch_input: float = Input.get_axis("move_back", "move_forward")
	var accelerating: bool = Input.is_action_pressed("ship_accelerate")
	var decelerating: bool = Input.is_action_pressed("ship_decelerate")
	ship.submit_driver_input(turn_input, pitch_input, accelerating, decelerating)

func _update_throw_charge(delta: float) -> void:
	if not _throw_charging:
		return
	if not _can_start_throw():
		_throw_charging = false
		_throw_charge_time = 0.0
		return
	_throw_charge_time = min(throw_charge_duration, _throw_charge_time + delta)

func _release_throw() -> void:
	_throw_charging = false
	if not _can_start_throw():
		_throw_charge_time = 0.0
		return
	var cargo: CargoCrate = _held_cargo
	var charge_ratio: float = clamp(_throw_charge_time / max(0.01, throw_charge_duration), 0.0, 1.0)
	_throw_charge_time = 0.0
	var throw_dir: Vector3 = camera.project_ray_normal(get_aim_screen_position()).normalized()
	var throw_speed: float = lerp(throw_speed_min, throw_speed_max, charge_ratio)
	_request_throw(cargo, throw_dir * throw_speed)
	_held_cargo = null

func _can_start_throw() -> bool:
	return _held_cargo != null and _held_cargo.is_held_by(multiplayer.get_unique_id()) and not _is_driving() and not _is_ragdolled

func _request_throw(cargo: CargoCrate, throw_velocity: Vector3) -> void:
	if cargo == null:
		return
	var release_transform: Transform3D = cargo.global_transform
	var release_linear_velocity: Vector3 = _compose_cargo_release_velocity()
	var release_angular_velocity: Vector3 = cargo.angular_velocity
	if multiplayer.is_server():
		cargo.request_throw(release_transform, release_linear_velocity, release_angular_velocity, throw_velocity)
	else:
		cargo.request_throw.rpc_id(1, release_transform, release_linear_velocity, release_angular_velocity, throw_velocity)

func _lock_to_wheel(delta: float) -> void:
	if _driving_wheel == null:
		return
	var anchor: Marker3D = _driving_wheel.get_driver_anchor()
	if anchor == null:
		return
	var target_basis: Basis = Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	global_basis = global_basis.orthonormalized().slerp(target_basis, min(1.0, delta * wheel_lock_lerp_speed))
	if _wheel_lock_blend_time_remaining > 0.0:
		var alpha: float = min(1.0, delta * wheel_lock_lerp_speed)
		global_position = global_position.lerp(anchor.global_position, alpha)
		_wheel_lock_blend_time_remaining = max(0.0, _wheel_lock_blend_time_remaining - delta)
	else:
		global_position = anchor.global_position
	velocity = Vector3.ZERO

func _get_effective_move_speed() -> float:
	return move_speed

func _get_effective_jump_velocity() -> float:
	return jump_velocity

func _configure_avatar_animations() -> void:
	if avatar_animation_player == null:
		return

	for anim_name: StringName in [ANIM_IDLE, ANIM_RUN, ANIM_CARRY_IDLE, ANIM_CARRY_RUN]:
		var anim: Animation = avatar_animation_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR

	var ragdoll_anim: Animation = avatar_animation_player.get_animation(ANIM_RAGDOLL)
	if ragdoll_anim != null:
		ragdoll_anim.loop_mode = Animation.LOOP_LINEAR

func _update_avatar_animation() -> void:
	if avatar_animation_player == null:
		return

	if _is_ragdolled:
		if not _avatar_death_played:
			_avatar_death_played = true
			_play_avatar_animation(ANIM_RAGDOLL, true)
		return

	_avatar_death_played = false
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.15
	var carrying: bool = _has_visible_held_cargo()
	var target_animation: StringName = ANIM_IDLE
	if carrying:
		target_animation = ANIM_CARRY_RUN if moving else ANIM_CARRY_IDLE
	elif moving:
		target_animation = ANIM_RUN
	_play_avatar_animation(target_animation)

func _play_avatar_animation(anim_name: StringName, restart: bool = false) -> void:
	if avatar_animation_player == null:
		return
	if not restart and _current_avatar_animation == anim_name and avatar_animation_player.is_playing():
		return
	if not avatar_animation_player.has_animation(anim_name):
		return
	avatar_animation_player.play(anim_name, 0.15)
	_current_avatar_animation = anim_name


func _has_visible_held_cargo() -> bool:
	if _held_cargo != null and is_instance_valid(_held_cargo):
		return _held_cargo.is_held_by(get_multiplayer_authority())

	var cargo_nodes: Array[Node] = get_tree().get_nodes_in_group("cargo")
	for node: Node in cargo_nodes:
		var cargo: CargoCrate = node as CargoCrate
		if cargo != null and cargo.is_held_by(get_multiplayer_authority()):
			return true
	return false

func _compose_cargo_release_velocity() -> Vector3:
	var swing_velocity: Vector3 = _hold_point_velocity * hold_swing_velocity_gain
	swing_velocity = swing_velocity.limit_length(max_hold_swing_velocity)
	return velocity + swing_velocity

func _update_hold_point_kinematics(delta: float) -> void:
	if hold_point == null:
		return
	var current_hold_point: Vector3 = hold_point.global_position
	if not _hold_point_tracking_ready:
		_hold_point_prev_global = current_hold_point
		_hold_point_velocity = Vector3.ZERO
		_hold_point_tracking_ready = true
		return
	_hold_point_velocity = (current_hold_point - _hold_point_prev_global) / max(0.0001, delta)
	_hold_point_prev_global = current_hold_point

func _apply_cargo_push_contacts() -> void:
	var collision_count: int = get_slide_collision_count()
	for i: int in range(collision_count):
		var collision: KinematicCollision3D = get_slide_collision(i)
		if collision == null:
			continue
		var cargo: CargoCrate = collision.get_collider() as CargoCrate
		if cargo == null:
			continue
		if not cargo.holder_paths.is_empty():
			continue
		var push_dir: Vector3 = Vector3(-collision.get_normal().x, 0.0, -collision.get_normal().z)
		if push_dir.length_squared() <= 0.0001:
			push_dir = cargo.global_position - global_position
			push_dir.y = 0.0
		if push_dir.length_squared() <= 0.0001:
			continue
		push_dir = push_dir.normalized()
		var speed_into: float = max(0.0, Vector3(velocity.x, 0.0, velocity.z).dot(push_dir))
		var impulse_mag: float = clamp((cargo_push_base_force + speed_into) * cargo_push_impulse_scale, 0.0, cargo_push_max_impulse)
		if impulse_mag <= 0.01:
			continue
		var impulse: Vector3 = push_dir * impulse_mag
		var contact_point: Vector3 = collision.get_position()
		if multiplayer.is_server():
			cargo.request_player_push(impulse, contact_point)
		else:
			cargo.request_player_push.rpc_id(1, impulse, contact_point)


func _update_fall_tracking() -> void:
	if _is_ragdolled:
		_fall_tracking_active = false
		return
	if not is_on_floor():
		if not _fall_tracking_active:
			_fall_tracking_active = true
			_fall_start_height = global_position.y
		return
	if not _fall_tracking_active:
		return
	var fall_distance: float = _fall_start_height - global_position.y
	_fall_tracking_active = false
	if fall_distance >= ragdoll_fall_height:
		var impact_strength: float = clamp(fall_distance * ragdoll_fall_impulse_scale, 2.5, 9.0)
		var lateral_dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		if lateral_dir.length_squared() <= 0.0001:
			lateral_dir = -basis.z
		lateral_dir = lateral_dir.normalized()
		var impact_impulse: Vector3 = (lateral_dir * impact_strength) + Vector3.UP * min(2.0, impact_strength * 0.18)
		_enter_ragdoll(impact_impulse)

func _apply_ragdoll_sim(delta: float) -> void:
	_ragdoll_time_remaining = max(0.0, _ragdoll_time_remaining - delta)
	velocity.y -= gravity * 1.95 * delta
	if is_on_floor():
		_ragdoll_floor_time += delta
		var horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		horiz = horiz.lerp(Vector3.ZERO, min(1.0, ragdoll_ground_friction * delta))
		velocity.x = horiz.x
		velocity.z = horiz.z
	else:
		_ragdoll_floor_time = 0.0
		velocity.x *= 1.0 / (1.0 + (ragdoll_air_drag * delta * 0.55))
		velocity.z *= 1.0 / (1.0 + (ragdoll_air_drag * delta * 0.55))
	move_and_slide()
	var speed_ratio: float = clamp(velocity.length() / 7.0, 0.85, 1.9)
	var rot_alpha: float = min(1.0, delta * 17.0 * speed_ratio)
	var tumble_basis: Basis = Basis.from_euler(_ragdoll_spin_velocity * delta)
	visual.basis = visual.basis.orthonormalized().slerp((tumble_basis * visual.basis).orthonormalized(), rot_alpha)
	_sync_ragdoll_collision_to_visual(delta)
	var can_recover: bool = _ragdoll_time_remaining <= 0.0 and is_on_floor() and _ragdoll_floor_time >= ragdoll_floor_settle_time and velocity.length() <= ragdoll_recover_speed_threshold
	if can_recover:
		_exit_ragdoll()

func _enter_ragdoll(impulse: Vector3) -> void:
	if _is_ragdolled:
		return
	if _is_driving():
		return
	_is_ragdolled = true
	var impact_ratio: float = clamp(impulse.length() / 9.0, 0.0, 1.0)
	_ragdoll_time_remaining = lerp(ragdoll_duration, ragdoll_max_duration, impact_ratio)
	_ragdoll_floor_time = 0.0
	_throw_charging = false
	_throw_charge_time = 0.0
	var tumble_bias: Vector3 = impulse.normalized() if impulse.length() > 0.001 else Vector3.ZERO
	_ragdoll_spin_velocity = Vector3(
		randf_range(-ragdoll_spin_speed, ragdoll_spin_speed) + (tumble_bias.z * ragdoll_spin_speed * 0.65),
		randf_range(-ragdoll_spin_speed, ragdoll_spin_speed),
		randf_range(-ragdoll_spin_speed, ragdoll_spin_speed) + (-tumble_bias.x * ragdoll_spin_speed * 0.65)
	) * lerpf(1.0, ragdoll_onset_spin_boost, impact_ratio)
	var onset_axis: Vector3 = Vector3(tumble_bias.z, 0.0, -tumble_bias.x)
	if onset_axis.length_squared() <= 0.0001:
		onset_axis = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	onset_axis = onset_axis.normalized()
	var onset_tilt: float = deg_to_rad(ragdoll_onset_tilt_degrees) * lerpf(0.7, 1.0, impact_ratio)
	visual.basis = Basis(onset_axis, onset_tilt) * visual.basis
	velocity += impulse
	if impulse.length() > 3.0:
		velocity.y += min(2.3, impulse.length() * 0.2)

func _exit_ragdoll() -> void:
	_is_ragdolled = false
	_ragdoll_time_remaining = 0.0
	_ragdoll_floor_time = 0.0
	if body_collision != null:
		body_collision.transform = _default_body_collision_transform

func _sync_ragdoll_collision_to_visual(delta: float) -> void:
	if body_collision == null:
		return
	var target_transform: Transform3D = body_collision.transform
	target_transform.origin = _default_body_collision_transform.origin + (visual.position * 0.6)
	target_transform.basis = visual.basis.orthonormalized()
	body_collision.transform = body_collision.transform.interpolate_with(target_transform, min(1.0, delta * 12.0))

func _restore_body_collision_transform(delta: float) -> void:
	if body_collision == null:
		return
	body_collision.transform = body_collision.transform.interpolate_with(_default_body_collision_transform, min(1.0, delta * 14.0))

func _restore_upright_body(delta: float) -> void:
	if _latched_ship != null and is_instance_valid(_latched_ship):
		return
	if _is_ship_hull_climbing():
		return
	var target_basis: Basis = Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	basis = basis.orthonormalized().slerp(target_basis, min(1.0, delta * 10.0))

func _update_drive_collision_state(driving_now: bool) -> void:
	var should_disable: bool = driving_now or _drive_collision_grace_remaining > 0.0
	if should_disable == _drive_collision_disabled:
		return

	# Toggle collision against ship layer while driving to avoid feedback explosion.
	set_collision_mask_value(4, not should_disable)
	_drive_collision_disabled = should_disable

func _apply_remote_state(delta: float) -> void:
	if _remote_target_on_ship:
		var ship: SkyShip = _get_primary_ship()
		if ship != null:
			_remote_target_position = ship.to_global(_remote_target_ship_rel_position)
			_remote_target_basis = (ship.global_basis * _remote_target_ship_rel_basis).orthonormalized()

	var pos_alpha: float = min(1.0, delta * remote_pos_smooth_speed)
	var rot_alpha: float = min(1.0, delta * remote_rot_smooth_speed)

	var pos_error: Vector3 = _remote_target_position - global_position
	if pos_error.length() > remote_pos_deadzone:
		global_position = global_position.lerp(_remote_target_position, pos_alpha)

	basis = basis.orthonormalized().slerp(_remote_target_basis.orthonormalized(), rot_alpha)
	velocity = _remote_target_velocity
	visual.position = visual.position.lerp(_remote_target_visual_position, pos_alpha)
	visual.basis = visual.basis.orthonormalized().slerp(_remote_target_visual_basis.orthonormalized(), rot_alpha)
	if _is_ragdolled:
		_sync_ragdoll_collision_to_visual(delta)
	else:
		_restore_body_collision_transform(delta)

func _apply_latched_ship_follow(delta: float) -> void:
	if _is_driving():
		_clear_ship_latch()
		return
	if _latched_ship == null or not is_instance_valid(_latched_ship):
		_clear_ship_latch()
		return
	if _ship_latch_time_remaining <= 0.0:
		_clear_ship_latch()
		return

	var current_ship_transform: Transform3D = _latched_ship.global_transform
	var ship_delta: Transform3D = current_ship_transform * _latched_ship_transform.affine_inverse()
	global_position = ship_delta * global_position
	var previous_yaw: float = _latched_ship_transform.basis.get_euler().y
	var current_yaw: float = current_ship_transform.basis.get_euler().y
	var yaw_delta: float = wrapf(current_yaw - previous_yaw, -PI, PI)
	basis = (Basis.from_euler(Vector3(0.0, yaw_delta, 0.0)) * basis).orthonormalized()

	_latched_ship_transform = current_ship_transform

func _update_ship_latch_state(delta: float) -> void:
	if _is_driving():
		_clear_ship_latch()
		return

	if _is_ship_hull_climbing() and _hull_contact_ship != null:
		_latched_ship = _hull_contact_ship
		_latched_ship_transform = _hull_contact_ship.global_transform
		_ship_latch_time_remaining = ship_air_latch_duration
		return

	var ship: SkyShip = _probe_ship_below()
	if ship == null:
		if _latched_ship == null:
			return
		if is_on_floor():
			_clear_ship_latch()
			return
		_ship_latch_time_remaining = max(0.0, _ship_latch_time_remaining - delta)
		if _ship_latch_time_remaining <= 0.0:
			_clear_ship_latch()
		return

	if _latched_ship == null or _latched_ship != ship:
		_latched_ship = ship
		_latched_ship_transform = ship.global_transform
	_latched_ship = ship
	_ship_latch_time_remaining = ship_latch_duration if is_on_floor() else ship_air_latch_duration

func _clear_ship_latch() -> void:
	_latched_ship = null
	_ship_latch_time_remaining = 0.0

func _probe_ship_below() -> SkyShip:
	var ship_from_area: SkyShip = _probe_ship_deck_area_at(global_position)
	if ship_from_area != null:
		return ship_from_area

	var from: Vector3 = global_position + Vector3.UP * 0.2
	var to: Vector3 = from + (Vector3.DOWN * ship_probe_distance)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	var ship: SkyShip = collider as SkyShip
	if ship != null:
		return ship
	var cargo: CargoCrate = collider as CargoCrate
	if cargo != null:
		return cargo.get_latched_ship()
	return null

func _probe_ship_below_at(sample_position: Vector3) -> SkyShip:
	var ship_from_area: SkyShip = _probe_ship_deck_area_at(sample_position)
	if ship_from_area != null:
		return ship_from_area

	var from: Vector3 = sample_position + Vector3.UP * 0.2
	var to: Vector3 = from + (Vector3.DOWN * ship_probe_distance)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	var ship: SkyShip = collider as SkyShip
	if ship != null:
		return ship
	var cargo: CargoCrate = collider as CargoCrate
	if cargo != null:
		return cargo.get_latched_ship()
	return null

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

func _get_sync_support_ship() -> SkyShip:
	if _latched_ship != null and is_instance_valid(_latched_ship):
		return _latched_ship
	return _probe_ship_below()

func _get_primary_ship() -> SkyShip:
	var ships: Array[Node] = get_tree().get_nodes_in_group("sky_ship")
	for node: Node in ships:
		var ship: SkyShip = node as SkyShip
		if ship != null:
			return ship
	return null

func _refresh_ship_hull_contact() -> void:
	_hull_contact_ship = null
	_hull_contact_normal = Vector3.ZERO
	var collision_count: int = get_slide_collision_count()
	for i: int in range(collision_count):
		var collision: KinematicCollision3D = get_slide_collision(i)
		if collision == null:
			continue
		var collider: Object = collision.get_collider()
		var ship: SkyShip = _find_ship_in_hierarchy(collider)
		if ship == null:
			continue
		_hull_contact_ship = ship
		_hull_contact_normal = collision.get_normal()
		return

func _find_ship_in_hierarchy(obj: Object) -> SkyShip:
	var node: Node = obj as Node
	while node != null:
		var ship: SkyShip = node as SkyShip
		if ship != null:
			return ship
		node = node.get_parent()
	return null

func _is_ship_hull_climbing() -> bool:
	return _hull_contact_ship != null and _hull_contact_normal.y < 0.7 and not _is_ragdolled and not _is_driving()
