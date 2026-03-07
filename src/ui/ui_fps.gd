extends Label
class_name UIFPS

@export var visible_by_default: bool = true
@export var update_rate_hz: float = 5.0

var _time_until_update: float = 0.0

func _ready() -> void:
	visible = visible_by_default
	_update_text()

func _process(delta: float) -> void:
	_time_until_update -= delta
	if _time_until_update > 0.0:
		return
	_time_until_update = 1.0 / max(1.0, update_rate_hz)
	_update_text()

func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_F9:
		return
	visible = not visible
	get_viewport().set_input_as_handled()

func _update_text() -> void:
	text = "FPS: %d" % Engine.get_frames_per_second()
