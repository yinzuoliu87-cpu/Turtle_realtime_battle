extends Node
func _ready() -> void:
	print("has_feature VIRTUAL_KEYBOARD = ", DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD))
	print("window_get_size = ", DisplayServer.window_get_size())
	print("screen_get_scale = ", DisplayServer.screen_get_scale())
	print("vp size = ", get_viewport().get_visible_rect().size)
	get_tree().quit(0)
