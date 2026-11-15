extends "res://tests/verify_stream_parity.gd"
## 探针(不是门禁, 2026-11-15): 钻石斧被动 6(治疗 → 4 秒梯形蓄力 → 猛砸)录成直播流, 在手机端重放画不画得出来。
## 用户 11-15「小木斧的钻石技能…整个技能特效都没出现」。本机直跑演出全在(tests/probes/_probe_diamond_axe.gd);
## 怀疑: 梯形场 / 砸下爆光是 SurfaceTool 现拼的网格, 没挂出处键(VfxTex.tag / snap) ⇒ 手机只拿到「一份网格」占位。

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	## 可选: AXE_STAGE(0~4, 默认 4)· AXE_FINAL(undead / seraph / holo / ember, 默认空)· AXE_FRAMES(默认 960)
	var stg: int = int(OS.get_environment("AXE_STAGE")) if OS.has_environment("AXE_STAGE") else 4
	var fin: String = OS.get_environment("AXE_FINAL") if OS.has_environment("AXE_FINAL") else ""
	gs.set("axe_stage", stg)
	gs.set("axe_exp_total", 480 + (400 if fin != "" else 0))
	gs.set("axe_final", fin)
	var frames: int = int(OS.get_environment("AXE_FRAMES")) if OS.has_environment("AXE_FRAMES") else 960
	var sc := {"tag": "斧 档%d %s" % [stg, fin], "frames": frames, "seed": "424242", "loadouts": {}, "pairs": [
		["basic", "left", 420.0, 360.0, ["p2eq_096"]],
		["stone", "right", 680.0, 360.0, []]]}
	var nat: Dictionary = await _record_det(sc)
	await _play_and_compare("det " + str(sc["tag"]), nat["chunks"], nat["meta"], nat)
	_finish()
