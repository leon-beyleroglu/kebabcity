extends CanvasLayer

@onready var menu_control: Control = $Control
@onready var status_label: Label = $Control/CenterContainer/VBoxContainer/StatusLabel

var _status_tween: Tween


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			on_resume_pressed()
		else:
			get_tree().paused = true
			menu_control.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_viewport().set_input_as_handled()


func on_resume_pressed() -> void:
	get_tree().paused = false
	menu_control.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func on_save_pressed() -> void:
	GameState.save_game()
	status_label.text = "Spiel gespeichert!"
	status_label.modulate.a = 1.0
	if is_instance_valid(_status_tween):
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(1.5)
	_status_tween.tween_property(status_label, "modulate:a", 0.0, 0.35)
	_status_tween.tween_callback(status_label.set_text.bind(""))


func on_quit_pressed() -> void:
	GameState.save_game()
	get_tree().quit()
