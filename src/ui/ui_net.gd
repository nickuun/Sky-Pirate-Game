extends Control
class_name UINet

@onready var panel: PanelContainer = $Panel
@onready var singleplayer_button: Button = $Panel/Margin/VBox/Buttons/SingleplayerButton
@onready var host_button: Button = $Panel/Margin/VBox/Buttons/HostButton
@onready var refresh_button: Button = $Panel/Margin/VBox/Buttons/RefreshButton
@onready var hosts_list: ItemList = $Panel/Margin/VBox/HostsList
@onready var join_button: Button = $Panel/Margin/VBox/JoinRow/JoinButton
@onready var ip_input: LineEdit = $Panel/Margin/VBox/JoinRow/IPInput
@onready var status_label: Label = $Panel/Margin/VBox/Status

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	host_button.pressed.connect(_on_host_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	hosts_list.item_selected.connect(_on_host_selected)

	Network.server_started.connect(func() -> void:
		status_label.text = "Session started"
		panel.visible = false
	)

	Network.connected_to_server.connect(func() -> void:
		status_label.text = "Connected"
		panel.visible = false
	)

	Network.connection_failed.connect(func() -> void:
		status_label.text = "Connection failed"
		panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	)

	Network.disconnected.connect(func() -> void:
		status_label.text = "Disconnected"
		panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	)

	Network.discovery_updated.connect(_on_discovery_updated)
	_on_refresh_pressed()

func _on_singleplayer_pressed() -> void:
	status_label.text = "Starting singleplayer..."
	Network.start_singleplayer()

func _on_host_pressed() -> void:
	status_label.text = "Hosting LAN session..."
	Network.host(Network.DEFAULT_PORT)

func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing LAN hosts..."
	Network.refresh_hosts()

func _on_join_pressed() -> void:
	var target_ip: String = ip_input.text.strip_edges()
	var target_port: int = Network.DEFAULT_PORT

	var selected: PackedInt32Array = hosts_list.get_selected_items()
	if not selected.is_empty():
		var info: Dictionary = hosts_list.get_item_metadata(selected[0]) as Dictionary
		target_ip = str(info.get("ip", target_ip))
		target_port = int(info.get("port", target_port))

	if target_ip.is_empty():
		status_label.text = "Select a host or type an IP."
		return

	status_label.text = "Connecting to %s:%d..." % [target_ip, target_port]
	Network.join(target_ip, target_port)

func _on_discovery_updated(hosts: Array) -> void:
	hosts_list.clear()
	for host_info: Dictionary in hosts:
		var label: String = "%s - %s:%d" % [
			str(host_info.get("name", "Host")),
			str(host_info.get("ip", "")),
			int(host_info.get("port", Network.DEFAULT_PORT))
		]
		var idx: int = hosts_list.add_item(label)
		hosts_list.set_item_metadata(idx, host_info)

	if hosts.is_empty():
		status_label.text = "No LAN hosts found."

func _on_host_selected(index: int) -> void:
	var info: Dictionary = hosts_list.get_item_metadata(index) as Dictionary
	ip_input.text = str(info.get("ip", ""))
