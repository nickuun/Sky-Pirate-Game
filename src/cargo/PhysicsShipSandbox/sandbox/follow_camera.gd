extends Node3D

@export var target_path: NodePath = ^"../Ship"
@export var distance: float = 13.0
@export var height: float = 5.5
@export var look_height: float = 1.6
@export var position_lerp_speed: float = 5.0
@export var look_lerp_speed: float = 6.0
@export var mouse_sensitivity: float = 0.004
@export var min_pitch_degrees: float = -35.0
@export var max_pitch_degrees: float = 20.0
@export var require_right_mouse_hold: bool = true
@export var zoom_step: float = 1.0
@export var min_distance: float = 7.0
@export var max_distance: float = 22.0

var _target: Node3D
var _look_at_point: Vector3
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = deg_to_rad(-12.0)

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target:
		_look_at_point = _target.global_position

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = get_node_or_null(target_path) as Node3D
		if not _target:
			return

	var ship_basis: Basis = _target.global_basis
	var ship_forward: Vector3 = -ship_basis.z.normalized()
	var pivot: Vector3 = _target.global_position + Vector3.UP * height
	var offset_dir: Vector3 = (-ship_forward).rotated(Vector3.UP, _orbit_yaw)
	var right_axis: Vector3 = Vector3.UP.cross(offset_dir).normalized()
	offset_dir = offset_dir.rotated(right_axis, _orbit_pitch).normalized()
	var target_position: Vector3 = pivot + offset_dir * distance
	var pos_t: float = 1.0 - exp(-position_lerp_speed * delta)
	global_position = global_position.lerp(target_position, pos_t)

	var desired_look: Vector3 = _target.global_position + Vector3.UP * look_height
	var look_t: float = 1.0 - exp(-look_lerp_speed * delta)
	_look_at_point = _look_at_point.lerp(desired_look, look_t)
	look_at(_look_at_point, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if require_right_mouse_hold and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			return
		_orbit_yaw -= event.relative.x * mouse_sensitivity
		_orbit_pitch = clamp(
			_orbit_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + zoom_step)
