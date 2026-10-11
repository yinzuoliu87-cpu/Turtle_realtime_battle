extends Node
## verify_item8_batch.gd —— 全项目通读第八条(五个小项)逐项量(2026-10-11)
##   ① 074 魔法胸甲的魔伤公式是自抄的一份, 漏了水晶龟「受魔法 ×0.8」⇒ 打水晶龟多 25%
##   其余小项各自一节, 每节先在原代码上量出红再修。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _unit(id: String, side: String, off: Vector2 = Vector2.ZERO) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 通读第八条 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false

	# ── ① 074: 魔伤打水晶龟要吃 ×0.8 ──
	_s._units.clear()
	var a := _unit("basic", "left")
	var cr := _unit("crystal", "right", Vector2(60, 0))
	cr["mr"] = 0.0
	cr["damage_reduction"] = 0.0
	a["damage_amp"] = 0.0
	var got: int = _s._equip_sys._bow_sys._magic_after_mr(a, 100.0, cr)
	var want: int = _s._magic_after_mr(a, 100.0, cr)
	_ok("★★① 074 魔伤打水晶龟 = 主公式(含水晶 ×%.2f)" % CrystalSystem.MAGIC_DR_MULT, got == want,
		"074 那份 %d / 主公式 %d" % [got, want])
	_ok("★① 分母: 主公式对水晶龟确实打了折(<100)", want < 100, "%d" % want)

	# ── ② 财神梭哈金币的真伤段: 物理段打死目标后不许再打尸体(进统计/给吸血) ──
	##   中央伤害函数不拦死人(打尸体照样记统计、给吸血) ⇒ 守卫必须在调用点。先量「打尸体会不会记账」(分母),
	##   再扫源码: 弹道命中那段 `coin_true` 必须带 alive 判断(同处 ms_onhit / star_true 都带)。
	_s._units.clear()
	var g := _unit("gambler", "left")
	var corpse := _unit("basic", "right", Vector2(60, 0))
	corpse["alive"] = false
	corpse["hp"] = 0.0
	var st0: float = float(g.get("_st_dealt", 0.0))
	_s._damage._apply_damage_from(g, corpse, 50, Color.WHITE, 0.0, true)
	_ok("★② 分母: 中央伤害函数确实不拦死人(打尸体会记进输出统计) ⇒ 守卫只能放在调用点",
		float(g.get("_st_dealt", 0.0)) > st0, "_st_dealt %.0f → %.0f" % [st0, float(g.get("_st_dealt", 0.0))])
	var bsrc := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_ballistics.gd")
	var coin_line := ""
	for line in bsrc.split(String.chr(10)):
		if line.contains("pr.get(\"coin_true\", 0) > 0"):
			coin_line = line
	_ok("★★② 金币真伤段带 alive 守卫(物理段打死后不再打尸体)", coin_line.contains("alive"), coin_line.strip_edges())

	# ── ③ 全息斧法阵 +30% 攻速: 不许覆盖/缩短友军身上更强的加速(天使祝福 +50% 5 秒) ──
	_s._units.clear()
	var ax := _unit("basic", "left")
	ax["_axe_final"] = "holo"
	var ally := _unit("basic", "left", Vector2(40, 0))
	ally["haste_mult"] = 1.5
	ally["haste_until"] = _s._t + 5.0
	var fin = _s._equip_sys._axe._fin
	var hit: int = fin.holo_aura_tick(ax)
	_ok("★③ 分母: 法阵这一跳确实覆盖到了友军", hit >= 1, "覆盖 %d 只" % hit)
	_ok("★★③ 友军身上更强的 +50%% 加速不被改成 +30%%", absf(float(ally["haste_mult"]) - 1.5) < 1e-4,
		"haste_mult %.2f" % float(ally["haste_mult"]))
	_ok("★★③ 也不被缩短(还剩约 5 秒)", float(ally["haste_until"]) - _s._t > 4.9,
		"剩 %.2f 秒" % (float(ally["haste_until"]) - _s._t))
	var plain := _unit("basic", "left", Vector2(-40, 0))
	fin.holo_aura_tick(ax)
	_ok("★③ 对照: 没有加速的友军照常吃到 +30%%", absf(float(plain.get("haste_mult", 1.0)) - (1.0 + AxeFinalStats.HOLO_AURA_ASPD)) < 1e-4,
		"haste_mult %.2f" % float(plain.get("haste_mult", 1.0)))

	# ── ④ 060 磷光水母伞: 伞张开时携带者阵亡 ⇒ 伞下队友的减伤/闪避必须撤掉 ──
	_s._units.clear()
	var car := _unit("basic", "left")
	var mate := _unit("basic", "left", Vector2(50, 0))
	car["equips"] = [{"id": "p2eq_060", "star": 1}]
	car["eq_state"] = {"p2eq_060": {}}
	var dr0: float = float(mate.get("damage_reduction", 0.0))
	var stt060: Dictionary = car["eq_state"]["p2eq_060"]
	_s._equip_sys._spirit_sys._parasol_open(car, 0, stt060)
	stt060["pa_open"] = true
	car["eq_state"]["p2eq_060"] = stt060
	_ok("★④ 分母: 伞张开后队友确实拿到减伤", float(mate.get("damage_reduction", 0.0)) > dr0 + 0.05,
		"%.2f → %.2f" % [dr0, float(mate.get("damage_reduction", 0.0))])
	car["alive"] = false
	car["hp"] = 0.0
	_s._equip_sys._eq_on_death(car, null)
	_ok("★★④ 携带者阵亡 ⇒ 队友减伤撤回原值", absf(float(mate.get("damage_reduction", 0.0)) - dr0) < 1e-4,
		"damage_reduction %.2f(原 %.2f)" % [float(mate.get("damage_reduction", 0.0)), dr0])
	var has_pb := false
	for b in mate.get("buffs", []):
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == "p2eq_060":
			has_pb = true
	_ok("★★④ 携带者阵亡 ⇒ 伞的闪避 buff 也摘掉", not has_pb)

	# ── ⑤ 远古之力跨路存档: 存的是「全队已累积量」, 不许被最后一个(新来的召唤物/封顶跳过的)单位拉低 ──
	_s._units.clear()
	var r1 := _unit("basic", "left")
	var r2 := _unit("basic", "left", Vector2(40, 0))
	_s._synergy._by_side = {"left": {"遗物": 2}, "right": {}}
	var cap2: float = float(RelicSynergySystem.ANCIENT_CAP[1])
	r1["_ancient"] = cap2               # 已封顶(这一跳会被 continue 跳过)
	r2["_ancient"] = 0.0                # 刚登场的(比如召唤物)
	_s._relic_syn._t_acc = RelicSynergySystem.PERIOD
	_s._relic_syn.tick(0.0)
	var stored: float = float(_s._relic_syn._ancient_total.get("left", 0.0))
	_ok("★★⑤ 跨路存档 = 全队里已累积到的量(%.3f), 不被刚登场的那只拉低" % cap2, absf(stored - cap2) < 1e-4,
		"存档 %.3f(r1 %.3f / r2 %.3f)" % [stored, float(r1["_ancient"]), float(r2["_ancient"])])
	_s._synergy._by_side = {"left": {}, "right": {}}

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
