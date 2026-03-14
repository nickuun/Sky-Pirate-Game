extends Control
class_name UINet

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBlock/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/TitleBlock/Subtitle
@onready var landing_menu: VBoxContainer = $Panel/Margin/VBox/LandingMenu
@onready var singleplayer_button: Button = $Panel/Margin/VBox/LandingMenu/SingleplayerButton
@onready var multiplayer_button: Button = $Panel/Margin/VBox/LandingMenu/MultiplayerButton
@onready var quit_button: Button = $Panel/Margin/VBox/LandingMenu/QuitButton
@onready var multiplayer_menu: VBoxContainer = $Panel/Margin/VBox/MultiplayerMenu
@onready var back_button: Button = $Panel/Margin/VBox/MultiplayerMenu/TopRow/BackButton
@onready var host_button: Button = $Panel/Margin/VBox/MultiplayerMenu/ActionsRow/HostButton
@onready var refresh_button: Button = $Panel/Margin/VBox/MultiplayerMenu/ActionsRow/RefreshButton
@onready var hosts_list: ItemList = $Panel/Margin/VBox/MultiplayerMenu/HostsList
@onready var join_button: Button = $Panel/Margin/VBox/MultiplayerMenu/JoinRow/JoinButton
@onready var ip_input: LineEdit = $Panel/Margin/VBox/MultiplayerMenu/JoinRow/IPInput
@onready var status_label: Label = $Panel/Margin/VBox/MultiplayerMenu/Status

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_on_back_pressed)
	host_button.pressed.connect(_on_host_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	hosts_list.item_selected.connect(_on_host_selected)

	Network.server_started.connect(_on_session_entered.bind("Session started"))
	Network.connected_to_server.connect(_on_session_entered.bind("Connected"))
	Network.connection_failed.connect(_on_connection_failed)
	Network.disconnected.connect(_on_disconnected)
	Network.discovery_updated.connect(_on_discovery_updated)

	_show_landing_menu()
	if Network.session_active:
		panel.visible = false

func _on_singleplayer_pressed() -> void:
	_show_multiplayer_status("Starting singleplayer...")
	Network.start_singleplayer()

func _on_multiplayer_pressed() -> void:
	_show_multiplayer_menu(true)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_back_pressed() -> void:
	_show_landing_menu()

func _on_host_pressed() -> void:
	_show_multiplayer_status("Hosting LAN session...")
	Network.host(Network.DEFAULT_PORT)

func _on_refresh_pressed() -> void:
	_show_multiplayer_status("Refreshing LAN hosts...")
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
		_show_multiplayer_status("Select a host or type an IP.")
		return

	_show_multiplayer_status("Connecting to %s:%d..." % [target_ip, target_port])
	Network.join(target_ip, target_port)

func _on_discovery_updated(hosts: Array) -> void:
	hosts_list.clear()
	for host_info: Dictionary in hosts:
		var label: String = "%s  %s:%d" % [
			str(host_info.get("name", "Host")),
			str(host_info.get("ip", "")),
			int(host_info.get("port", Network.DEFAULT_PORT))
		]
		var idx: int = hosts_list.add_item(label)
		hosts_list.set_item_metadata(idx, host_info)

	if hosts.is_empty():
		_show_multiplayer_status("No LAN hosts found.")
	else:
		_show_multiplayer_status("Select a host or type an IP.")

func _on_host_selected(index: int) -> void:
	var info: Dictionary = hosts_list.get_item_metadata(index) as Dictionary
	ip_input.text = str(info.get("ip", ""))

func _on_session_entered(message: String) -> void:
	_show_multiplayer_status(message)
	panel.visible = false

func _on_connection_failed() -> void:
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_multiplayer_menu(false)
	_show_multiplayer_status("Connection failed")

func _on_disconnected() -> void:
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_landing_menu()

func _show_landing_menu() -> void:
	panel.visible = true
	landing_menu.visible = true
	multiplayer_menu.visible = false
	title_label.text = "Sky Pirate"
	subtitle_label.text = "Choose how you want to set sail."

func _show_multiplayer_menu(refresh_hosts: bool) -> void:
	panel.visible = true
	landing_menu.visible = false
	multiplayer_menu.visible = true
	title_label.text = "Multiplayer"
	subtitle_label.text = "Host a LAN game or join a crew."
	if refresh_hosts:
		_on_refresh_pressed()
	elif status_label.text.is_empty():
		_show_multiplayer_status("Select a host or type an IP.")

func _show_multiplayer_status(message: String) -> void:
	status_label.text = message
