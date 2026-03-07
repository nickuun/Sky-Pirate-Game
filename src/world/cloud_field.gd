extends Node3D
class_name CloudField

@export var cloud_count: int = 28
@export var area_extent: float = 110.0
@export var min_height: float = -2.0
@export var max_height: float = 52.0
@export var drift_speed: float = 0.2
@export var noise_seed: int = 1337
@export var noise_scale: float = 0.17
@export var sync_interval: float = 0.75
@export var min_boxes_per_cloud: int = 4
@export var max_boxes_per_cloud: int = 8
@export var cloud_spread: float = 4.2
@export var fade_edge_fraction: float = 0.24

var _noise: FastNoiseLite
var _cloud_nodes: Array[Node3D] = []
var _cloud_base_positions: Array[Vector3] = []
var _cloud_dirs: Array[Vector3] = []
var _cloud_speed_scales: Array[float] = []
var _cloud_fade_rates: Array[float] = []
var _cloud_fade_offsets: Array[float] = []
var _cloud_fade_duty: Array[float] = []
var _cloud_parts: Array[Array] = []
var _cloud_time: float = 0.0
var _target_cloud_time: float = 0.0
var _sync_timer: float = 0.0

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.frequency = noise_scale
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_clouds()

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_cloud_time += delta
		_sync_timer += delta
		if _sync_timer >= sync_interval:
			_sync_timer = 0.0
			sync_cloud_time.rpc(_cloud_time)
	else:
		_cloud_time = lerpf(_cloud_time, _target_cloud_time, min(1.0, delta * 2.0))

	_update_cloud_positions()

@rpc("any_peer", "unreliable", "call_remote")
func sync_cloud_time(server_cloud_time: float) -> void:
	if multiplayer.is_server():
		return
	_target_cloud_time = server_cloud_time

func _build_clouds() -> void:
	for i: int in range(cloud_count):
		var cloud: Node3D = _make_cloud_visual(i)
		add_child(cloud)
		_cloud_nodes.append(cloud)

		var x_noise: float = _noise.get_noise_2d(float(i) * 4.13, 9.7)
		var z_noise: float = _noise.get_noise_2d(7.1, float(i) * 3.77)
		var y_noise: float = _noise.get_noise_2d(float(i) * 2.17, 2.3)
		var base_position := Vector3(
			x_noise * area_extent,
			lerpf(min_height, max_height, (y_noise * 0.5) + 0.5),
			z_noise * area_extent
		)
		_cloud_base_positions.append(base_position)

		var dir_angle_noise: float = _noise.get_noise_2d(float(i) * 6.11, 4.2)
		var angle: float = ((dir_angle_noise * 0.5) + 0.5) * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		_cloud_dirs.append(direction)
		_cloud_speed_scales.append(lerpf(0.8, 1.35, _norm_noise(float(i) * 8.3, 1.7)))
		# Longer cloud life cycles, less frequent pop in/out.
		_cloud_fade_rates.append(lerpf(0.01, 0.03, _norm_noise(float(i) * 5.6, 11.1)))
		_cloud_fade_offsets.append(_norm_noise(float(i) * 2.9, 31.4))
		_cloud_fade_duty.append(lerpf(0.78, 0.95, _norm_noise(float(i) * 7.7, 18.0)))

func _update_cloud_positions() -> void:
	var span: float = area_extent * 2.0
	for i: int in range(_cloud_nodes.size()):
		var cloud: Node3D = _cloud_nodes[i]
		var base_position: Vector3 = _cloud_base_positions[i]
		var direction: Vector3 = _cloud_dirs[i]
		var moved: Vector3 = base_position + (direction * drift_speed * _cloud_speed_scales[i] * _cloud_time)
		moved.x = _wrap(moved.x, -area_extent, area_extent, span)
		moved.z = _wrap(moved.z, -area_extent, area_extent, span)
		cloud.global_position = global_position + moved
		_update_cloud_fade(i)

func _make_cloud_visual(i: int) -> Node3D:
	var cloud_root := Node3D.new()
	cloud_root.name = "Cloud_%d" % i
	var parts: Array = []

	var part_count: int = int(round(lerpf(float(min_boxes_per_cloud), float(max_boxes_per_cloud), _norm_noise(float(i) * 3.1, 0.3))))
	part_count = clamp(part_count, min_boxes_per_cloud, max_boxes_per_cloud)
	for part_idx: int in range(part_count):
		var cube := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		cube.mesh = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.985, 0.975, 0.94, 0.9)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 1.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cube.material_override = material

		var px: float = (_norm_noise(float(i * 13 + part_idx * 3), 4.7) * 2.0 - 1.0) * cloud_spread
		var pz: float = (_norm_noise(float(i * 9 + part_idx * 5), 13.9) * 2.0 - 1.0) * cloud_spread
		var py: float = lerpf(-0.5, 0.5, _norm_noise(float(i * 7 + part_idx * 2), 2.2))
		cube.position = Vector3(px, py, pz)

		var sx: float = lerpf(1.6, 4.8, _norm_noise(float(i * 5 + part_idx), 8.4))
		var sy: float = lerpf(0.6, 1.35, _norm_noise(float(i * 11 + part_idx * 2), 16.2))
		var sz: float = lerpf(1.4, 4.4, _norm_noise(float(i * 3 + part_idx * 4), 6.6))
		cube.scale = Vector3(sx, sy, sz)
		cloud_root.add_child(cube)
		parts.append(cube)

	_cloud_parts.append(parts)

	return cloud_root

func _update_cloud_fade(i: int) -> void:
	if i >= _cloud_parts.size():
		return
	var parts: Array = _cloud_parts[i]
	var phase: float = fposmod((_cloud_time * _cloud_fade_rates[i]) + _cloud_fade_offsets[i], 1.0)
	var duty: float = _cloud_fade_duty[i]
	var fade: float = _pulse_visibility(phase, duty)
	for node: MeshInstance3D in parts:
		if node == null:
			continue
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color.a = lerpf(0.0, 0.9, fade)

func _pulse_visibility(phase: float, duty: float) -> float:
	if phase > duty:
		return 0.0

	var edge: float = clamp(fade_edge_fraction, 0.02, 0.45)
	var entry: float = phase / max(0.001, edge)
	var exit: float = (duty - phase) / max(0.001, edge)
	var in_alpha: float = smoothstep(0.0, 1.0, entry)
	var out_alpha: float = smoothstep(0.0, 1.0, exit)
	return min(in_alpha, out_alpha)

func _norm_noise(x: float, y: float) -> float:
	return (_noise.get_noise_2d(x, y) * 0.5) + 0.5

func _wrap(value: float, min_value: float, max_value: float, span: float) -> float:
	if value < min_value:
		return value + span
	if value > max_value:
		return value - span
	return value
