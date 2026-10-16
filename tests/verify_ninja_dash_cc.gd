extends Node
## verify_ninja_dash_cc.gd — 忍者被动冲刺(2026-10-16 用户「被控住还能冲刺吗，以及冲刺的时候为啥还能攻击」)
##   ① 被击飞 / 施法定身中不开始冲刺(原来只排除眩晕; 探针实测各照冲)
##   ② 冲刺滑行中不普攻、不放技能(原来只置 no_basic, 放技能那支不看; 探针实测滑行中普攻 2 / 技能 1)
##   走真入口: 真 sim 跑 1200 帧, 1 只忍者 vs 4 个不还手的石头龟; 每帧采样。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var s = RB.new(); add_child(s)
	await get_tree().process_frame; await get_tree().process_frame
	s._units.clear(); s._over = false; s._edit_mode = false; s._deterministic = true
	var n: Dictionary = s._spawn._make_unit("ninja", "left", Vector2(300, 400))
	s._units.append(n)
	var es := []
	for i in 4:
		var e: Dictionary = s._spawn._make_unit("stone", "right", Vector2(520 + i * 60, 380 + i * 20))
		e["maxHp"] = 1e7; e["hp"] = 1e7; e["atk"] = 0.0
		s._units.append(e); es.append(e)
	var glide_frames := 0; var basic_in_glide := 0; var skill_in_glide := 0; var dash_in_stun := 0
	var last_cd: float = float(n.get("atk_cd", 0.0))
	var last_sk: Dictionary = (n.get("skill_cd", {}) as Dictionary).duplicate()
	for f in 1200:
		if f == 600:
			for e in es: e["_ninja_dash_until"] = 0.0
			n["_ninja_gliding"] = false; n["_ninja_last_dash"] = -99.0
			n["airborne"] = true; n["height"] = 6.0; n["vy"] = 4.0   # 击飞中
		if f == 900:
			for e in es: e["_ninja_dash_until"] = 0.0
			n["_ninja_gliding"] = false; n["_ninja_last_dash"] = -99.0
			n["channel_until"] = s._t + 3.0   # 施法定身
		var was_dash: float = float(n.get("_ninja_last_dash", -99.0))
		await get_tree().process_frame
		var g: bool = bool(n.get("_ninja_gliding", false))
		var cd: float = float(n.get("atk_cd", 0.0))
		if g:
			glide_frames += 1
			if cd > last_cd + 0.05: basic_in_glide += 1
			for k in (n.get("skill_cd", {}) as Dictionary):
				if last_sk.has(k) and float(n["skill_cd"][k]) > float(last_sk[k]) + 0.5: skill_in_glide += 1   # 只认冷却被重置(放了技能); 第 0 帧冷却从无到有不算
		if (bool(n.get("airborne", false)) or s._t < float(n.get("channel_until", 0.0))) and float(n.get("_ninja_last_dash", -99.0)) != was_dash: dash_in_stun += 1
		last_cd = cd; last_sk = (n.get("skill_cd", {}) as Dictionary).duplicate()
	var fail := 0
	for c in [["分母: 真的冲刺滑行过(帧数)", glide_frames > 30, glide_frames],
			["① 被击飞 / 定身中不开始冲刺", dash_in_stun == 0, dash_in_stun],
			["② 滑行中不普攻", basic_in_glide == 0, basic_in_glide],
			["② 滑行中不放技能", skill_in_glide == 0, skill_in_glide]]:
		print("  [%s] %s  %s" % ["PASS" if c[1] else "FAIL", c[0], str(c[2])])
		if not c[1]: fail += 1
	print("ALL PASS — 忍者冲刺与控制" if fail == 0 else "FAIL x%d" % fail)
	get_tree().quit(1 if fail > 0 else 0)
