extends Node3D
class_name WorldScene

@export var player_scene: PackedScene = preload("res://src/player/player.tscn")
@export var cargo_scene: PackedScene = preload("res://src/cargo/cargo.tscn")

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var ui_root: CanvasLayer = $UI

var _physics_debug_enabled: bool = false
var _physics_debug_timer: float = 0.0
const _PHYSICS_DEBUG_INTERVAL: float = 0.25
var _physics_debug_toggle_latch: bool = false
var _physics_debug_label: Label = null
var _sold_count_label: Label = null
var _sold_cargo_count: int = 0

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
	_setup_physics_debug_label()
	_setup_sell_count_label()
	_update_sell_count_label()

func _process(delta: float) -> void:
	var toggle_pressed: bool = Input.is_key_pressed(KEY_F6)
	if toggle_pressed and not _physics_debug_toggle_latch:
		_physics_debug_enabled = not _physics_debug_enabled
		_physics_debug_timer = 0.0
		print("[PHYSDBG] enabled=", _physics_debug_enabled)
		if _physics_debug_label != null:
			_physics_debug_label.visible = _physics_debug_enabled
	_physics_debug_toggle_latch = toggle_pressed

	if not _physics_debug_enabled:
		return
	_physics_debug_timer += delta
	if _physics_debug_timer < _PHYSICS_DEBUG_INTERVAL:
		return
	_physics_debug_timer = 0.0
	_print_ship_physics_debug()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
		sync_sold_cargo_count.rpc_id(id, _sold_cargo_count)

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
	_sold_cargo_count = 0
	_update_sell_count_label()

func restart_world() -> void:
	if not multiplayer.is_server():
		return

	sync_sold_cargo_count.rpc(0)

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

func sell_cargo(cargo: CargoCrate) -> void:
	if not multiplayer.is_server():
		return
	if cargo == null or not is_instance_valid(cargo):
		return
	if cargo.is_queued_for_deletion():
		return
	if not cargo.holder_paths.is_empty():
		return

	_sold_cargo_count += 1
	sync_sold_cargo_count.rpc(_sold_cargo_count)
	cargo.consume_from_server.rpc()

@rpc("any_peer", "reliable", "call_local")
func sync_sold_cargo_count(next_count: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	_sold_cargo_count = max(0, next_count)
	_update_sell_count_label()

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

func _print_ship_physics_debug() -> void:
	var ship: SkyShip = _get_primary_ship()
	if ship == null:
		print("[PHYSDBG] no_ship")
		if _physics_debug_label != null:
			_physics_debug_label.text = "[PHYSDBG] no_ship"
		return

	var driver_id: int = ship.driver_peer_id
	var passenger_lines: Array[String] = []
	for n: Node in get_tree().get_nodes_in_group("player_controller"):
		var p: PlayerController = n as PlayerController
		if p == null:
			continue
		var pid: int = p.get_multiplayer_authority()
		if pid == driver_id:
			continue
		var rel: Vector3 = ship.to_local(p.global_position)
		passenger_lines.append("P%d rel=(%.2f,%.2f,%.2f) vel=%.2f" % [pid, rel.x, rel.y, rel.z, p.velocity.length()])

	var cargo_lines: Array[String] = []
	for n: Node in get_tree().get_nodes_in_group("cargo_crate"):
		var c: CargoCrate = n as CargoCrate
		if c == null:
			continue
		if c.holder_peer_id != 0:
			continue
		var rel_c: Vector3 = ship.to_local(c.global_position)
		cargo_lines.append("C rel=(%.2f,%.2f,%.2f) vel=%.2f" % [rel_c.x, rel_c.y, rel_c.z, c.linear_velocity.length()])

	var line: String = "[PHYSDBG] thr=%.2f turn=%.2f ship_ang=(%.2f,%.2f,%.2f) | %s | %s" % [
		ship.get_throttle(),
		ship.get_turn_input(),
		ship.angular_velocity.x, ship.angular_velocity.y, ship.angular_velocity.z,
		", ".join(passenger_lines),
		", ".join(cargo_lines)
	]
	print(line)
	if _physics_debug_label != null:
		_physics_debug_label.text = line

func _get_primary_ship() -> SkyShip:
	var ships: Array[Node] = get_tree().get_nodes_in_group("sky_ship")
	for node: Node in ships:
		var ship: SkyShip = node as SkyShip
		if ship != null:
			return ship
	return null

func _setup_physics_debug_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	var label := Label.new()
	label.position = Vector2(12.0, 72.0)
	label.size = Vector2(1500.0, 64.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.modulate = Color(1.0, 0.95, 0.7, 0.95)
	label.text = ""
	label.visible = false
	canvas.add_child(label)
	_physics_debug_label = label

func _setup_sell_count_label() -> void:
	if ui_root == null:
		return

	var label := Label.new()
	label.name = "SellCount"
	label.position = Vector2(14.0, 42.0)
	label.size = Vector2(280.0, 30.0)
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color(1.0, 0.95, 0.7, 0.98)
	label.text = ""
	ui_root.add_child(label)
	_sold_count_label = label

func _update_sell_count_label() -> void:
	if _sold_count_label == null:
		return
	_sold_count_label.text = "Sold: %d" % _sold_cargo_count
