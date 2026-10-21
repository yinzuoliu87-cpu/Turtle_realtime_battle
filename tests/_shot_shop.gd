extends Node
## 商店截图台(不是门禁): 用 App Store 那份存档(打过一周)开店, 交给 ShopScene 自带的 SHOP_SHOT 截图。
## 跑法(窗口只开右屏): SHOP_SHOT=2 SHOT_OUT=<png> [SHOT_SEL=N] TURTLE_SUPABASE=" " TURTLE_BACKEND=" " \
##   <godot> --audio-driver Dummy --position 1960,60 --resolution 1560x720 --path . res://tests/_shot_shop.tscn


func _ready() -> void:
	GameState.test_mode = true
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	load("res://tests/_setup_appstore.gd").run()
	GameState.season_total_battles = maxi(1, int(GameState.season_total_battles))
	if OS.get_environment("SHOT_SEQ") != "":
		var rec := SeqRec.new(); rec.dir = OS.get_environment("SHOT_SEQ")
		if OS.get_environment("SHOT_N").is_valid_int():
			rec.n = int(OS.get_environment("SHOT_N"))
		get_tree().root.add_child.call_deferred(rec)
	get_tree().change_scene_to_file.call_deferred("res://scenes/Shop.tscn")



## SHOT_SEQ=<目录>: 开店后每 2 帧存一张视口截图(共 SHOT_N 张, 默认 240), 存完退出 —— 拼视频看动态用。
##   (--write-movie 在非 16:9 窗口上会裁偏, 实拍过; 这里直接存真实视口。录像节点挂在 root 上, 换场景不丢。)
class SeqRec extends Node:
	var dir := ""
	var n := 240
	var i := 0
	var f := 0
	func _process(_dt: float) -> void:
		f += 1
		if f < 60 or f % 2 != 0:
			return
		get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [dir, i])
		i += 1
		if i >= n:
			get_tree().quit()
