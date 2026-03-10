extends RigidBody3D

@export var random_spin_impulse: float = 1.2

var spawn_transform: Transform3D

func _ready() -> void:
	add_to_group("cargo")
	spawn_transform = global_transform
	if random_spin_impulse > 0.0:
		var spin: Vector3 = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized() * random_spin_impulse
		apply_torque_impulse(spin)

func mark_spawn_from_current() -> void:
	spawn_transform = global_transform

func reset_to_spawn() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = spawn_transform
