extends Node

signal connected_to_server()
signal server_started()
signal connection_failed()
signal disconnected()
signal discovery_updated(hosts: Array)
signal session_active_changed(active: bool)

const DEFAULT_PORT: int = 8910
const DISCOVERY_PORT: int = 8911
const DISCOVERY_INTERVAL: float = 1.0
const DISCOVERY_STALE_TIME: float = 4.0

var peer: MultiplayerPeer = null
var is_host: bool = false
var discovered_hosts: Array = []
var session_active: bool = false
var _host_port: int = DEFAULT_PORT

var _listener: PacketPeerUDP = PacketPeerUDP.new()
var _sender: PacketPeerUDP = PacketPeerUDP.new()
var _broadcast_timer: float = 0.0
var _listener_port: int = DISCOVERY_PORT

func _ready() -> void:
	var bind_result: Error = _listener.bind(DISCOVERY_PORT)
	if bind_result != OK:
		# Allows running multiple local instances: second instance binds any free port.
		bind_result = _listener.bind(0)
		if bind_result != OK:
			push_warning("Discovery listener failed to bind.")
		else:
			_listener_port = _listener.get_local_port()
	_listener.set_broadcast_enabled(true)
	_sender.set_broadcast_enabled(true)

	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
	if not multiplayer.connection_failed.is_connected(_on_connected_fail):
		multiplayer.connection_failed.connect(_on_connected_fail)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	set_process(true)

func _process(delta: float) -> void:
	_poll_discovery()
	_prune_stale_hosts()

	if is_host:
		_broadcast_timer += delta
		if _broadcast_timer >= DISCOVERY_INTERVAL:
			_broadcast_timer = 0.0
			_broadcast_presence()

func host(port: int = DEFAULT_PORT, host_name: String = "") -> void:
	_reset_session()
	is_host = true
	_host_port = port
	peer = ENetMultiplayerPeer.new()

	var err: Error = peer.create_server(port)
	if err != OK:
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	_set_session_active(true)
	server_started.emit()
	_register_discovered_host("127.0.0.1", _resolve_host_name(host_name), port)
	_broadcast_presence(port, host_name)

func join(address: String, port: int = DEFAULT_PORT) -> void:
	_reset_session()
	is_host = false
	peer = ENetMultiplayerPeer.new()

	var err: Error = peer.create_client(address, port)
	if err != OK:
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	_set_session_active(true)

func start_singleplayer() -> void:
	_reset_session()
	is_host = false
	peer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	_set_session_active(true)
	server_started.emit()

func stop() -> void:
	_reset_session()
	disconnected.emit()

func refresh_hosts() -> void:
	discovered_hosts.clear()
	discovery_updated.emit(discovered_hosts.duplicate(true))
	_send_discovery_query()

func _on_connected_ok() -> void:
	connected_to_server.emit()

func _on_connected_fail() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	disconnected.emit()

func _reset_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	peer = null
	is_host = false
	_host_port = DEFAULT_PORT
	_broadcast_timer = 0.0
	_set_session_active(false)

func _poll_discovery() -> void:
	while _listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _listener.get_packet()
		var sender_ip: String = _listener.get_packet_ip()
		var data: String = packet.get_string_from_utf8()
		var fields: PackedStringArray = data.split("|")
		if fields.is_empty():
			continue

		match fields[0]:
			"SP_QUERY":
				if is_host:
					var target_port: int = DISCOVERY_PORT
					if fields.size() >= 2:
						target_port = int(fields[1])
					_send_presence_to(sender_ip, target_port)
			"SP_HOST":
				if fields.size() >= 3:
					var host_name: String = fields[1]
					var port: int = int(fields[2])
					_register_discovered_host(sender_ip, host_name, port)

func _send_discovery_query() -> void:
	_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_sender.put_packet(("SP_QUERY|%d" % _listener_port).to_utf8_buffer())

func _broadcast_presence(port: int = DEFAULT_PORT, host_name: String = "") -> void:
	var msg: String = "SP_HOST|%s|%d" % [_resolve_host_name(host_name), port]
	_sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_sender.put_packet(msg.to_utf8_buffer())

func _send_presence_to(target_ip: String, target_port: int) -> void:
	var msg: String = "SP_HOST|%s|%d" % [_resolve_host_name(""), _host_port]
	_sender.set_dest_address(target_ip, target_port)
	_sender.put_packet(msg.to_utf8_buffer())

func _resolve_host_name(host_name: String) -> String:
	var resolved: String = host_name.strip_edges()
	if resolved.is_empty():
		resolved = OS.get_environment("COMPUTERNAME")
	if resolved.is_empty():
		resolved = "Sky Pirate Host"
	return resolved

func _register_discovered_host(ip: String, host_name: String, port: int) -> void:
	for i: int in range(discovered_hosts.size()):
		var existing: Dictionary = discovered_hosts[i]
		if existing.get("ip", "") == ip and int(existing.get("port", 0)) == port:
			existing["name"] = host_name
			existing["last_seen"] = Time.get_unix_time_from_system()
			discovered_hosts[i] = existing
			discovery_updated.emit(discovered_hosts.duplicate(true))
			return

	discovered_hosts.append({
		"name": host_name,
		"ip": ip,
		"port": port,
		"last_seen": Time.get_unix_time_from_system()
	})
	discovery_updated.emit(discovered_hosts.duplicate(true))

func _prune_stale_hosts() -> void:
	if discovered_hosts.is_empty():
		return

	var now: float = Time.get_unix_time_from_system()
	var changed: bool = false
	for i: int in range(discovered_hosts.size() - 1, -1, -1):
		var age: float = now - float(discovered_hosts[i].get("last_seen", now))
		if age > DISCOVERY_STALE_TIME:
			discovered_hosts.remove_at(i)
			changed = true

	if changed:
		discovery_updated.emit(discovered_hosts.duplicate(true))

func _set_session_active(active: bool) -> void:
	if session_active == active:
		return
	session_active = active
	session_active_changed.emit(session_active)
