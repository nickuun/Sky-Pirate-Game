extends Node3D
class_name WorldScene

@export var player_scene: PackedScene = preload("res://src/player/player.tscn")

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

func _spawn_player_data(data: Variant) -> Node:
	var id: int = int(data)
	var p: Node3D = player_scene.instantiate() as Node3D
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.position = Vector3(float(id % 4) * 2.5, 1.0, 0.0)
	return p
