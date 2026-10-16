extends Node
## verify_ice_vs_fire_basic.gd — 寒冰龟【普攻】对熔岩 / 凤凰也吃寒域 +20%(2026-10-16 用户「寒冰龟的攻击和技能会」)
##   原来只有技能路(_atk_dmg)乘, 普攻(_do_basic)没乘: 探针实测冰锥打熔岩 41、技能 49。
##   走真入口: 真 sim 跑到第一下普攻落地, 比「同一只寒冰打忍者龟」与「打熔岩龟」的第一下伤害。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _res := {}

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	for tid in ["ninja", "lava"]:
		var s = RB.new(); add_child(s)
		await get_tree().process_frame; await get_tree().process_frame
		s._units.clear(); s._over = false; s._edit_mode = false; s._deterministic = true
		var ice: Dictionary = s._spawn._make_unit("ice", "left", Vector2(300, 400))
		ice["crit"] = 0.0; ice["_vs_fire_bonus"] = 0.2
		var t: Dictionary = s._spawn._make_unit(tid, "right", Vector2(420, 400))
		for k in ["def", "mr", "damage_reduction", "dodge_bonus", "shield", "atk"]: t[k] = 0.0
		t["maxHp"] = 1000000.0; t["hp"] = 1000000.0; t["_burnImmune"] = true
		ice["skill_cd"] = {}
		s._units.append(ice); s._units.append(t)
		var h0: float = t["hp"]; var first := 0.0
		for i in 400:
			await get_tree().process_frame
			if t["hp"] < h0:
				first = h0 - float(t["hp"]); break
		_res[tid] = first
		print("  ", tid, " 第一下普攻伤害=", first)
		s.queue_free()
		await get_tree().process_frame
	var fail := 0
	var n: float = _res.get("ninja", 0.0)
	var l: float = _res.get("lava", 0.0)
	if not (n > 0.0):
		fail += 1; print("  [FAIL] 分母: 打忍者龟的普攻没落地")
	else:
		print("  [PASS] 分母: 普攻落地 ", n)
	if absf(l - roundf(n * (1.0 + IceSystem.AURA_VS_FIRE))) <= 1.0:
		print("  [PASS] 普攻打熔岩龟 = 打忍者龟 × (1 + AURA_VS_FIRE)  ", l)
	else:
		fail += 1; print("  [FAIL] 普攻打熔岩龟没吃寒域增伤  lava=%s ninja=%s" % [l, n])
	print("ALL PASS — 寒冰普攻对火系增伤" if fail == 0 else "FAIL x%d" % fail)
	get_tree().quit(1 if fail > 0 else 0)
