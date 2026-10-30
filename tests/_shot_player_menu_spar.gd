extends Node
## _shot_player_menu_spar.gd — 实拍排行榜上点别人弹出的菜单(带「切磋」)(给人看, 不是门禁)
## 由来: 2026-10-30 用户「排行榜里面…点击这个玩家之后，除了加好友选项，那还应该有这个切磋选项」(方案书 docs/plans/20261030-排行榜切磋.md)。
## 跑法: SHOT_OUT=<目录> WINDOW=1 bash godot-quiet.sh --position 2000,80 --resolution 1560x720 res://tests/_shot_player_menu_spar.tscn

const PM := preload("res://scripts/scenes/social/player_menu.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const OTHER := "22222222-2222-4222-8222-222222222222"


func _ready() -> void:
	var out := OS.get_environment("SHOT_OUT")
	if out == "":
		out = "C:/tmp/pm_spar"
	DirAccess.make_dir_recursive_absolute(out)
	GameState.test_mode = true
	var lb = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(lb)
	for _i in range(20):
		await get_tree().process_frame
	lb._render([
		{"rank": 1, "name": "我自己", "tag": PM.my_tag(), "wins": 5, "hearts": 7, "sweeps": 1, "battles": 6, "is_self": true, "lead": "basic"},
		{"rank": 2, "name": "海风", "tag": P2C.player_tag(OTHER), "wins": 4, "hearts": 6, "sweeps": 0, "battles": 6,
			"account_id": OTHER, "lead": "lava"},
	], lb.SRC_SERVER, 2)
	for _i in range(10):
		await get_tree().process_frame
	var es: Array = lb.find_children(PM.ENTRY, "Button", true, false)
	if not es.is_empty():
		(es[0] as Button).pressed.emit()
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var vs := get_viewport().get_visible_rect().size
	get_viewport().get_texture().get_image().save_png("%s/menu_%dx%d.png" % [out, int(vs.x), int(vs.y)])
	print("SHOT DONE")
	get_tree().quit(0)
