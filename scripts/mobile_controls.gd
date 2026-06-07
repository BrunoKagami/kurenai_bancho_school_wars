extends Control

const JOYSTICK_RADIUS := 68.0
const KNOB_RADIUS := 29.0
const BUTTON_RADIUS := 48.0
const INPUT_DEADZONE := 0.22

var joystick_touch := -1
var jump_touch := -1
var punch_touch := -1
var joystick_value := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = _should_show_mobile_controls()
	set_process_input(visible)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		visible = _should_show_mobile_controls()
		set_process_input(visible)
		queue_redraw()


func _should_show_mobile_controls() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	return OS.has_feature("web") and DisplayServer.window_get_size().x <= 980


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_pressed(event.index, event.position)
		else:
			_handle_touch_released(event.index)
	elif event is InputEventScreenDrag and event.index == joystick_touch:
		_update_joystick(event.position)


func _handle_touch_pressed(touch_index: int, touch_position: Vector2) -> void:
	if joystick_touch == -1 and touch_position.x < size.x * 0.48:
		joystick_touch = touch_index
		_update_joystick(touch_position)
		get_viewport().set_input_as_handled()
		return

	if jump_touch == -1 and touch_position.distance_to(_jump_center()) <= BUTTON_RADIUS * 1.35:
		jump_touch = touch_index
		Input.action_press("jump")
		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if punch_touch == -1 and touch_position.distance_to(_punch_center()) <= BUTTON_RADIUS * 1.35:
		punch_touch = touch_index
		Input.action_press("punch")
		queue_redraw()
		get_viewport().set_input_as_handled()


func _handle_touch_released(touch_index: int) -> void:
	if touch_index == joystick_touch:
		joystick_touch = -1
		joystick_value = Vector2.ZERO
		_apply_joystick_actions()
	elif touch_index == jump_touch:
		jump_touch = -1
		Input.action_release("jump")
	elif touch_index == punch_touch:
		punch_touch = -1
		Input.action_release("punch")
	queue_redraw()


func _update_joystick(touch_position: Vector2) -> void:
	joystick_value = (touch_position - _joystick_center()).limit_length(JOYSTICK_RADIUS) / JOYSTICK_RADIUS
	if joystick_value.length() < INPUT_DEADZONE:
		joystick_value = Vector2.ZERO
	_apply_joystick_actions()
	queue_redraw()


func _apply_joystick_actions() -> void:
	_set_action_strength("move_left", maxf(-joystick_value.x, 0.0))
	_set_action_strength("move_right", maxf(joystick_value.x, 0.0))
	_set_action_strength("move_up", maxf(-joystick_value.y, 0.0))
	_set_action_strength("move_down", maxf(joystick_value.y, 0.0))


func _set_action_strength(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _joystick_center() -> Vector2:
	return Vector2(105.0, size.y - 105.0)


func _jump_center() -> Vector2:
	return Vector2(size.x - 155.0, size.y - 82.0)


func _punch_center() -> Vector2:
	return Vector2(size.x - 70.0, size.y - 145.0)


func _draw() -> void:
	if not visible:
		return

	var base_center := _joystick_center()
	var knob_center := base_center + joystick_value * JOYSTICK_RADIUS
	draw_circle(base_center, JOYSTICK_RADIUS, Color(0.03, 0.035, 0.05, 0.48))
	draw_arc(base_center, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(0.85, 0.86, 0.9, 0.55), 3.0)
	draw_circle(knob_center, KNOB_RADIUS, Color(0.72, 0.08, 0.12, 0.72))
	draw_arc(knob_center, KNOB_RADIUS, 0.0, TAU, 32, Color(1.0, 0.78, 0.55, 0.8), 3.0)

	_draw_action_button(_jump_center(), "PULO", jump_touch != -1, Color(0.92, 0.56, 0.05, 0.72))
	_draw_action_button(_punch_center(), "SOCO", punch_touch != -1, Color(0.72, 0.04, 0.08, 0.76))


func _draw_action_button(center: Vector2, label: String, pressed: bool, color: Color) -> void:
	var button_color := color.lightened(0.18) if pressed else color
	draw_circle(center, BUTTON_RADIUS, Color(0.02, 0.02, 0.025, 0.54))
	draw_circle(center, BUTTON_RADIUS - 5.0, button_color)
	draw_arc(center, BUTTON_RADIUS, 0.0, TAU, 40, Color(1.0, 0.86, 0.68, 0.8), 3.0)

	var font := ThemeDB.fallback_font
	var font_size := 17
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, center - text_size * 0.5 + Vector2(0.0, text_size.y * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
