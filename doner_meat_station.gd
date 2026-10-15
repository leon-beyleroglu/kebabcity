class_name DonerMeatStation
extends Area3D

var display_name := "Dönerfleisch"

func _ready() -> void:
	collision_layer = 1 << 7
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta("doner_meat_station", true)
