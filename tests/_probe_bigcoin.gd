extends Node
func _ready() -> void:
	var gs = get_node("/root/GameState"); gs.test_mode = true
	gs.coins = int(OS.get_environment("PC_COINS")); gs.meta_deepsea_coins = int(OS.get_environment("PC_DSEA"))
	var m = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(m)
