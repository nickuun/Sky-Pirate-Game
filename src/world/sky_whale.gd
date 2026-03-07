extends Node3D
class_name SkyWhaleOrbit

@export var orbit_radius: float = 75.0
@export var orbit_speed_degrees: float = 7.0
@export var bob_height: float = 3.0
@export var bob_speed: float = 0.6
@export var auto_face_tangent: bool = true
@export var sync_interval: float = 0.2

var _center: Vector3 = Vector3.ZERO
var _angle: float = 0.0
var _time: float = 0.0
var _sync_accum: float = 0.0
var _sync_transform: Transform3D

func _ready() -> void:
	set_multiplayer_authority(1)
	_center = global_position
	_angle = 0.0
	_play_idle_once()
	

func _process(delta: float) -> void:
	_play_idle_once()

	if is_multiplayer_authority():
		_time += delta
		_angle += deg_to_rad(orbit_speed_degrees) * delta
		_apply_orbit_state()
		_sync_accum += delta
		if _sync_accum >= sync_interval:
			_sync_accum = 0.0
			sync_state.rpc(global_transform, _angle, _time)
	else:
		# Smoothly follow the latest server transform.
		if _sync_transform:
			global_transform = global_transform.interpolate_with(_sync_transform, min(1.0, delta * 8.0))
		# Advance locally to keep motion fluid between syncs.
		_time += delta
		_angle += deg_to_rad(orbit_speed_degrees) * delta
		_apply_orbit_state()

func _play_idle_animation_if_present() -> void:
	var players: Array[AnimationPlayer] = []
	_collect_animation_players(self, players)
	for ap: AnimationPlayer in players:
		if ap == null:
			continue
		if ap.has_animation("idle"):
			ap.play("idle")
			return

func _collect_animation_players(node: Node, out_players: Array[AnimationPlayer]) -> void:
	for child: Node in node.get_children():
		var ap: AnimationPlayer = child as AnimationPlayer
		if ap != null:
			out_players.append(ap)
		_collect_animation_players(child, out_players)

func _apply_orbit_state() -> void:
	var orbit_offset: Vector3 = Vector3(cos(_angle), 0.0, sin(_angle)) * orbit_radius
	var bob_offset: float = sin(_time * bob_speed) * bob_height
	var next_position: Vector3 = _center + orbit_offset + Vector3(0.0, bob_offset, 0.0)
	global_position = next_position
	if auto_face_tangent:
		var tangent: Vector3 = Vector3(-sin(_angle), 0.0, cos(_angle))
		var look_target: Vector3 = next_position + tangent
		look_at(look_target, Vector3.UP)

func _play_idle_once() -> void:
	var ap: AnimationPlayer = $AnimationPlayer
	if ap != null and not ap.is_playing():
		ap.play("Idle")

@rpc("authority", "unreliable", "call_remote")
func sync_state(next_transform: Transform3D, angle: float, time_val: float) -> void:
	if is_multiplayer_authority():
		return
	_sync_transform = next_transform
	_angle = angle
	_time = time_val
