extends Node
## 探针: 训龟大师 7 技【逐技目视】特效 —— 补上审核报告 §4 里明确标"还没做"的那块。
##
## ★静态检查(演出函数存在 + 素材在磁盘)≠ 屏幕上看得见。
##   memory project-vfx-library-rich 的教训: 美术断言要查素材真的显示进 _world。
##   这里更进一步 —— 真施放一次, 连拍几帧存图, 人眼看。
##
## 跑法: TR_SKILL=hook SHOT_OUT=<路径前缀> godot --path . res://tests/probe_trainer_vfx.tscn
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RTScene.new()
	get_tree().root.add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	# 找我方大师, 换上指定技能
	var sid := OS.get_environment("TR_SKILL")
	if sid == "": sid = "hook"
	var tr = null
	for u in s._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			tr = u; break
	if tr == null:
		print("★没找到我方训龟大师 —— NO_TRAINER/DEBUG_EDIT 会跳过 spawn")
		get_tree().quit(1); return
	tr["_tr_active"] = sid
	tr["_active_cd"] = 0.0
	if sid == "magic_stone":
		tr["_tr_passive"] = "magic_stone"
	# 朝最近敌人施放
	var tgt = s._targeting._nearest_enemy_for_trainer(tr)
	var aim: Vector2 = (tgt["pos"] - tr["pos"]) if tgt != null else Vector2(600, 0)
	var ok: bool = s._trainer_sys._cast_active(tr, aim)
	print("★施放 %s → 返回 %s ; 目标 %s" % [sid, str(ok), str(tgt.get("name", "?")) if tgt != null else "无"])
	# 连拍: 覆盖前摇→飞行→命中
	var base := OS.get_environment("SHOT_OUT")
	var n_world0 := s._world.get_child_count()
	for i in range(5):
		var el := 0.0
		while el < 0.34:
			await get_tree().process_frame
			el += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [base, i])
	print("★_world 子节点 %d → %d (演出真的加了 %d 个节点)"
		% [n_world0, s._world.get_child_count(), s._world.get_child_count() - n_world0])
	get_tree().quit(0)
