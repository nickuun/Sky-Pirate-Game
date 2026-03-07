extends Node3D
class_name WorldScene

@export var player_scene: PackedScene = preload("res://src/player/player.tscn")
@export var cargo_scene: PackedScene = preload("res://src/cargo/cargo.tscn")

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Spawner

func _ready() -> void:
	spawner.spawn_function = _spawn_player_data
	spawner.add_spawnable_scene(player_scene.resource_path)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.server_started.connect(_on_session_started)
	Network.connected_to_server.connect(_on_session_started)
	Network.disconnected.connect(_on_session_disconnected)

	# In case the world starts after a multiplayer session already exists.
	_on_session_started()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	# Clean up player node named with their peer id.
	var node_name: String = str(id)
	if players_root.has_node(node_name):
		var p: Node = players_root.get_node(node_name)
		p.queue_free()

func _spawn_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	if multiplayer.is_server():
		spawner.spawn(id)

func _on_session_started() -> void:
	if not Network.session_active:
		return
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_unique_id())

func _on_session_disconnected() -> void:
	for child: Node in players_root.get_children():
		child.queue_free()

func restart_world() -> void:
	if not multiplayer.is_server():
		return

	for n: Node in get_tree().get_nodes_in_group("sky_ship"):
		var ship: SkyShip = n as SkyShip
		if ship != null:
			ship.request_respawn_ship()

	for n: Node in get_tree().get_nodes_in_group("player_controller"):
		var p: PlayerController = n as PlayerController
		if p != null:
			p.force_respawn_from_server.rpc()

	for n: Node in get_tree().get_nodes_in_group("cargo_crate"):
		var c: CargoCrate = n as CargoCrate
		if c != null:
			c.respawn_cargo_from_server.rpc()

func spawn_cargo_at_host_spawn() -> void:
	if not multiplayer.is_server():
		return
	var host_id: int = 1
	var spawn_position: Vector3 = _get_player_spawn_global(host_id) + Vector3(0.0, 1.0, 0.0)
	var spawn_transform := Transform3D(Basis.IDENTITY, spawn_position)
	spawn_cargo_for_all.rpc(spawn_transform)

@rpc("any_peer", "reliable", "call_local")
func spawn_cargo_for_all(spawn_transform: Transform3D) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if cargo_scene == null:
		return
	var cargo: CargoCrate = cargo_scene.instantiate() as CargoCrate
	if cargo == null:
		return
	cargo.global_transform = spawn_transform
	add_child(cargo)
	cargo.owner = get_tree().current_scene

func _spawn_player_data(data: Variant) -> Node:
	var id: int = int(data)
	var p: Node3D = player_scene.instantiate() as Node3D
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.position = _get_player_spawn_local(id)
	return p

func _get_player_spawn_local(id: int) -> Vector3:
	return Vector3(float(id % 4) * 2.5, 1.0, 0.0)

func _get_player_spawn_global(id: int) -> Vector3:
	return players_root.to_global(_get_player_spawn_local(id))
