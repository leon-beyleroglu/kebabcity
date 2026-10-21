class_name MoneyHUD
extends CanvasLayer

@onready var money_label: Label = %MoneyLabel
@onready var order_feedback_label: Label = %OrderFeedbackLabel

var _money_tween: Tween
var _feedback_tween: Tween


func _ready() -> void:
	add_to_group("money_hud")


func set_money(amount: int, animate := true) -> void:
	money_label.text = "%d €" % amount
	if not animate:
		money_label.scale = Vector2.ONE
		return
	if is_instance_valid(_money_tween):
		_money_tween.kill()
	money_label.pivot_offset = money_label.size * 0.5
	money_label.scale = Vector2(1.2, 1.2)
	_money_tween = create_tween()
	_money_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_money_tween.tween_property(money_label, "scale", Vector2.ONE, 0.2)


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
