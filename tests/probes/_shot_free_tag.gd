extends Node
## 截图(2026-11-23): 选龟页「本周免费」角标 + 右栏说明, 看四个字放不放得下。开窗口跑, 存 .out/shots/free_tag_<宽>.png。

const ACCT := "6f1c2b3a-9d4e-4f50-8a61-7b2c3d4e5f60"
const WEEK := 1762732800


func _ready() -> void:
	await get_tree().process_frame
	GameState.account_id = ACCT
	GameState.week_anchor_ts = WEEK
	GameState.pet_lv = {}
	PetLevelsNet.override = {"linked": true, "owned": ["stone", "lava"], "levels": {"stone": {"lv": 4, "xp": 300}}}
	var ts: Node = (load("res://scenes/TeamSelect.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(ts)
	get_tree().current_scene = ts
	for _i in range(90):
		await get_tree().process_frame
	## 右栏切到一只本周免费的龟(说明那行「本周免费的龟不获得经验」)
	var fr := WeeklyFree.free_ids(ACCT, WEEK, ["stone", "lava"])
	if ts.has_method("_show_detail"):
		ts.call("_show_detail", fr[0])
	elif ts.get("detail_pet_id") != null:
		ts.set("detail_pet_id", fr[0])
	for _i in range(60):
		await get_tree().process_frame
	var w := get_viewport().get_visible_rect().size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.out/shots"))
	var p := "res://.out/shots/free_tag_%d.png" % int(w.x)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT ", ProjectSettings.globalize_path(p))
	get_tree().quit(0)
