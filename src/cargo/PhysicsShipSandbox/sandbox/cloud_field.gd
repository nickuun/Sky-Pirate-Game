extends Node3D

@export var target_path: NodePath = ^"../Ship"
@export var cloud_count: int = 70
@export var cloud_radius: float = 180.0
@export var cloud_min_height: float = 10.0
@export var cloud_max_height: float = 64.0
@export var cloud_min_size: Vector3 = Vector3(6.0, 1.6, 3.5)
@export var cloud_max_size: Vector3 = Vector3(18.0, 3.8, 9.0)
@export var wrap_margin: float = 18.0
@export var low_layer_height: float = 12.0
@export var mid_layer_height: float = 28.0
@export var high_layer_height: float = 48.0
@export var layer_jitter: float = 3.0

var _target: Node3D
var _cloud_nodes: Array[Node3D] = []

func _ready() -> void:
	randomize()
	_target = get_node_or_null(target_path) as Node3D
	_generate_clouds()

func _process(_delta: float) -> void:
	if not is_instance_valid(_target):
		_target = get_node_or_null(target_path) as Node3D
		if not _target:
			return
	_wrap_clouds_around_target()

func _generate_clouds() -> void:
	for child in _cloud_nodes:
		if is_instance_valid(child):
			child.queue_free()
	_cloud_nodes.clear()

	for _i in cloud_count:
		var cloud_root := Node3D.new()
		add_child(cloud_root)
		_cloud_nodes.append(cloud_root)

		var layer_index: int = randi_range(0, 2)
		var base_height: float = mid_layer_height
		if layer_index == 0:
			base_height = low_layer_height
		elif layer_index == 2:
			base_height = high_layer_height
		var base_pos := Vector3(
			randf_range(-cloud_radius, cloud_radius),
			clamp(base_height + randf_range(-layer_jitter, layer_jitter), cloud_min_height, cloud_max_height),
			randf_range(-cloud_radius, cloud_radius)
		)
		cloud_root.position = base_pos

		var puff_count: int = randi_range(2, 4)
		for _j in puff_count:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(
				randf_range(cloud_min_size.x, cloud_max_size.x),
				randf_range(cloud_min_size.y, cloud_max_size.y),
				randf_range(cloud_min_size.z, cloud_max_size.z)
			)
			mesh.mesh = box
			mesh.position = Vector3(
				randf_range(-4.0, 4.0),
				randf_range(-0.7, 0.7),
				randf_range(-4.0, 4.0)
			)

			var mat := StandardMaterial3D.new()
			if layer_index == 0:
				mat.albedo_color = Color(1.0, 0.95, 0.84, 1.0)
			elif layer_index == 1:
				mat.albedo_color = Color(0.96, 0.98, 1.0, 1.0)
			else:
				mat.albedo_color = Color(0.84, 0.94, 1.0, 1.0)
			mat.roughness = 1.0
			mesh.material_override = mat
			cloud_root.add_child(mesh)

func _wrap_clouds_around_target() -> void:
	var ship_pos: Vector3 = _target.global_position
	var wrap_size: float = (cloud_radius + wrap_margin) * 2.0
	var max_dist: float = cloud_radius + wrap_margin

	for cloud in _cloud_nodes:
		if not is_instance_valid(cloud):
			continue
		var p: Vector3 = cloud.position
		var dx: float = p.x - ship_pos.x
		var dz: float = p.z - ship_pos.z
		if dx > max_dist:
			p.x -= wrap_size
		elif dx < -max_dist:
			p.x += wrap_size
		if dz > max_dist:
			p.z -= wrap_size
		elif dz < -max_dist:
			p.z += wrap_size
		cloud.position = p
