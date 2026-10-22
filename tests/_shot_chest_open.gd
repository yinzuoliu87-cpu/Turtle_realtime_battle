extends Node
## DEV 工具(不是门禁): 拍宝箱龟【开箱那一刻】—— 头顶弹出战利品图标 + 金字飘字(2026-10-22 用户「对局内你怎么展示战利品」「发给我看啊」)。
## 走真实开箱函数 ChestSystem._chest_treasure_tick; 演出 tween 由 _step_sim_tweens 按 sim 步推(对局里也是这么推的)。
## 跑法(窗口只开右屏, 不能 --headless —— 无头拿不到视口纹理):
##   SHOT_OUT=<png> SHOT_STEP_SEC=0.3 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> \
##   WINDOW=1 bash godot-quiet.sh --position 1960,60 --resolution 1560x720 res://tests/_shot_chest_open.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("chest", "left", c)
	s._units.clear()
	s._units.append(u)
	s._edit_mode = false
	s._over = false
	s.set_process(false)
	## 宝箱账: 已开 1 件、财宝值差 10 到第 2 箱阈值 ⇒ 一下伤害过线 ⇒ 开第 2 箱
	var lg: Dictionary = s._chest_sys._ledger_of("left")
	lg["base_won"] = ["rum"]
	lg["base_value"] = float(ChestLoot.THRESH[1]) - 10.0
	for t in s._chest_sys.spawn_loot(u):
		s._chest_sys._chest_apply_treasure(u, str(t))
	s._chest_sys.note_damage(u, 50)
	s._chest_sys._chest_treasure_tick(u)
	var sec: float = float(OS.get_environment("SHOT_STEP_SEC")) if OS.get_environment("SHOT_STEP_SEC").is_valid_float() else 0.3
	var steps: int = maxi(1, roundi(sec * 60.0))
	for _i in range(steps):
		s._step_sim_tweens(1.0 / 60.0)
		await get_tree().process_frame
	print("[SHOT] 开出: ", str(lg["won"]))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_OUT")
	img.save_png(out)
	print("[SHOT] → ", out)
	get_tree().quit()
