extends Node3D
class_name SkyWhaleOrbit

@export var orbit_radius: float = 75.0
@export var orbit_speed_degrees: float = 7.0
@export var bob_height: float = 3.0
@export var bob_speed: float = 0.6
@export var auto_face_tangent: bool = true

var _center: Vector3 = Vector3.ZERO
var _angle: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	_center = global_position
	_angle = 0.0
	$AnimationPlayer.play("Idle")
	

func _process(delta: float) -> void:
	$AnimationPlayer.play("Idle")
	
	_time += delta
	_angle += deg_to_rad(orbit_speed_degrees) * delta

	var orbit_offset: Vector3 = Vector3(cos(_angle), 0.0, sin(_angle)) * orbit_radius
	var bob_offset: float = sin(_time * bob_speed) * bob_height
	var next_position: Vector3 = _center + orbit_offset + Vector3(0.0, bob_offset, 0.0)
	global_position = next_position

	if auto_face_tangent:
		var tangent: Vector3 = Vector3(-sin(_angle), 0.0, cos(_angle))
		var look_target: Vector3 = next_position + tangent
		look_at(look_target, Vector3.UP)

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
