class_name MoneyHUD
extends CanvasLayer

@onready var armour_bar: ProgressBar = %ArmourBar
@onready var health_bar: ProgressBar = %HealthBar
@onready var money_label: Label = %MoneyLabel
@onready var order_feedback_label: Label = %OrderFeedbackLabel

var _money_tween: Tween
var _feedback_tween: Tween


func _ready() -> void:
	add_to_group("money_hud")
	update_health(100.0, 100.0)
	update_shield(0.0, 100.0)
	update_money(0)
	call_deferred("_connect_player_stats")


func update_health(current: float, max_val: float) -> void:
	health_bar.max_value = maxf(max_val, 1.0)
	health_bar.value = clampf(current, 0.0, health_bar.max_value)


func update_shield(current: float, max_val: float) -> void:
	armour_bar.max_value = maxf(max_val, 1.0)
	armour_bar.value = clampf(current, 0.0, armour_bar.max_value)


func update_money(amount: int) -> void:
	_set_money_display(amount, true)


func set_money(amount: int, animate := true) -> void:
	_set_money_display(amount, animate)


func _set_money_display(amount: int, animate: bool) -> void:
	money_label.text = "$%08d" % maxi(amount, 0)
	if not animate:
		money_label.scale = Vector2.ONE
		return
	if is_instance_valid(_money_tween):
		_money_tween.kill()
	money_label.pivot_offset = Vector2(money_label.size.x, money_label.size.y * 0.5)
	money_label.scale = Vector2(1.12, 1.12)
	_money_tween = create_tween()
	_money_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_money_tween.tween_property(money_label, "scale", Vector2.ONE, 0.2)


func _connect_player_stats() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	if player.has_signal("health_changed") and not player.health_changed.is_connected(update_health):
		player.health_changed.connect(update_health)
	if player.has_signal("shield_changed") and not player.shield_changed.is_connected(update_shield):
		player.shield_changed.connect(update_shield)
	update_health(float(player.health), float(player.max_health))
	update_shield(float(player.shield), float(player.max_shield))


func show_order_feedback(message: String, success := false) -> void:
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	order_feedback_label.text = message
	order_feedback_label.add_theme_color_override(
		"font_color",
		Color(0.2, 0.9, 0.3) if success else Color(1.0, 0.25, 0.2)
	)
	order_feedback_label.modulate = Color.WHITE
	order_feedback_label.visible = true
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(2.0)
	_feedback_tween.tween_property(order_feedback_label, "modulate", Color(1, 1, 1, 0), 0.35)
	_feedback_tween.tween_callback(_hide_order_feedback)


func _hide_order_feedback() -> void:
	order_feedback_label.visible = false
