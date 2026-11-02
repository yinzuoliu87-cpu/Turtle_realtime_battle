extends Node
## _probe_worm_atk.gd — 033 海螺虫的攻击力/暴击到底是多少(探针, 不进门禁)
## 由来: verify_conch_worm_033 的 ④ 在并行门禁里偶发红, 三个伤害数逐次不同(290/21/290 vs 405/60/810)。
## 小虫 3★ 的 atk 常量是 200, 而实测基础伤害 290~405 ⇒ 属性被谁改了, 或者伤害路径里有随机。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

func _mk(s, px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0; u["maxHp"] = 90000.0; u["atk"] = 100.0; u["alive"] = true
	u["crit"] = 0.0; u["critDmg"] = 1.0; u["atk_interval"] = 9999.0; u["atk_cd"] = 9999.0
	return u

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var s = RB.new()
	add_child(s)
	for _i in range(30):
		await get_tree().process_frame
	s._units.clear()
	var d4: Dictionary = _mk(s, 640.0, 380.0, "left")
	d4["equips"] = [{"id": "p2eq_033", "star": 3}]
	d4["eq_state"] = {}
	s._units.append(d4)
	var soft: Dictionary = _mk(s, 900.0, 380.0, "right")
	soft["def"] = 0.0; soft["mr"] = 0.0
	s._units.append(soft)
	s._equip_sys._eq_on_death(d4, null)
	var ws: Array = []
	for o in s._units:
		if str(o.get("summon_kind", "")) == "worm" and o.get("alive", false) and str(o.get("side", "")) == "left":
			ws.append(o)
	print("── 小虫属性 ──")
	print("  场上小虫数 = %d (分母)" % ws.size())
	for w in ws:
		var _eqs: Array = w.get("equips", []) if w.get("equips", null) is Array else []
		var _ids: Array = []
		for e in _eqs:
			if e is Dictionary:
				_ids.append("%s★%d" % [str(e.get("id", "?")), int(e.get("star", 1))])
		print("  ★小虫身上的装备(%d 件) = %s" % [_eqs.size(), str(_ids)])
		print("  atk=%.2f base_atk=%.2f crit=%.3f crit_dmg=%.2f damage_amp=%.3f buffs=%d"
			% [float(w.get("atk", -1)), float(w.get("base_atk", -1)), float(w.get("crit", -1)),
			float(w.get("crit_dmg", -1)), float(w.get("damage_amp", 0.0)), (w.get("buffs", []) as Array).size()])
	if not ws.is_empty():
		var w4: Dictionary = ws[0]
		print("── 同一只小虫连打 soft 八次(def=0, 所以数字就是结算后的伤害) ──")
		for i in range(8):
			var dmg: int = s._resolve_dmg(w4, float(w4["atk"]), soft, false)
			print("    第%d次 = %d   (_last_atk_crit=%s)" % [i + 1, dmg, str(s._last_atk_crit)])
	print("── 直接调 _spawn_summon(atk=200) 看返回值 ──")
	var raw = s._spawn._spawn_summon(d4, "worm", 10000.0, 200.0, {"label": "对照", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
	if raw != null:
		print("  直接生成的小虫 atk=%.2f base_atk=%.2f" % [float(raw.get("atk", -1)), float(raw.get("base_atk", -1))])
	print("  携带者 d4: atk=%.2f base_atk=%.2f level=%s" % [float(d4.get("atk", -1)), float(d4.get("base_atk", -1)), str(d4.get("level", "?"))])
	print("  GameState.season_level=%s" % str(gs.season_level))
	print("PROBE_DONE")
	get_tree().quit(0)
