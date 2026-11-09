"""龟壳复制 60% 第二批(2026-11-09): copy_ctx_1109.py 之后整类探针还剩 12 个技能, 结算点各自不同。
调用栈探针(COPYTRACE)查实的结算点: 协程 await 之后(小龟重击 / 熔岩涌动 / 人体浪板 / 火箭)、施法者每帧状态(钻石滚球 /
闪电打击)、地面区域每跳(熔岩地震)、装备批次的波(十字斩)、追踪箭分支(猎人弹幕)、盾到期爆裂(泡泡盾 / 水晶壁垒)、召唤物(海盗船)。
做法统一: 状态建立那一刻(仍在复制窗口里)ctx_capture 记下, 结算那一刻 ctx_enter_opt / ctx_exit_opt。
多出口的结算函数用「改名 + 同名包装」, 原函数名不动(图鉴 status_sources 的正则按名字核对调用关系)。
"""
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"


def edit(rel, pairs):
    p = ROOT + rel
    b = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in b
    s = b.replace("\r\n", "\n")
    for a, c in pairs:
        assert s.count(a) == 1, (rel, a[:100], s.count(a))
        s = s.replace(a, c)
    open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))


SH = "battle._shell_sys"

edit("scripts/systems/skills/shell_system.gd", [
    ("""	battle._copy_fx_mult = float(prev[0])
	battle._copy_src = prev[1]
	(tag[1] as Dictionary)["dmg_out_mult"] = float(prev[2])
""", """	battle._copy_fx_mult = float(prev[0])
	battle._copy_src = prev[1]
	(tag[1] as Dictionary)["dmg_out_mult"] = float(prev[2])


## 技能自己的状态 / 区域 / 协程用: tag 可以是 null(不在复制期建的 ⇒ 什么都不做)。
func ctx_enter_opt(tag) -> Array:
	return ctx_enter(tag) if tag is Array else []


func ctx_exit_opt(tag, prev: Array) -> void:
	if tag is Array and not prev.is_empty():
		ctx_exit(tag, prev)
"""),
])

edit("scripts/systems/skills/basic_slam_system.gd", [
    ("""	last_phase = "dash"
""", """	var _ct = %s.ctx_capture()   # 龟壳复制期放的: 落地结算(await 之后)照样按 60%%
	last_phase = "dash"
""" % SH),
    ("""	_apply_damage(u, tgt, tmax, t_land)
""", """	var _cp1: Array = %s.ctx_enter_opt(_ct)
	_apply_damage(u, tgt, tmax, t_land)
	%s.ctx_exit_opt(_ct, _cp1)
""" % (SH, SH)),
    ("""	_apply_damage(u, tgt, tmax, c)
""", """	var _cp2: Array = %s.ctx_enter_opt(_ct)
	_apply_damage(u, tgt, tmax, c)
	%s.ctx_exit_opt(_ct, _cp2)
""" % (SH, SH)),
])

edit("scripts/systems/skills/diamond_system.gd", [
    ("""	u["roll_active"] = true
""", """	u["roll_active"] = true
	u["_roll_copy"] = %s.ctx_capture()   # 龟壳复制期滚的: 撞击结算(每帧状态推进到撞上那一刻)照样按 60%%
""" % SH),
    ("""func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
""", """func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
	var _ct = u.get("_roll_copy")
	u.erase("_roll_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_diamond_roll_impact_body(u, cp, sf)
	%s.ctx_exit_opt(_ct, _cp)


func _diamond_roll_impact_body(u: Dictionary, cp: Vector2, sf: float) -> void:
""" % (SH, SH)),
])

edit("scripts/systems/skills/dice_system.gd", [
    ("""	u["dice_dash_active"] = true                    # 进入真冲刺连突态""",
     """	u["_dash_copy"] = %s.ctx_capture()   # 龟壳复制期放的: 每段穿刺斩(每帧状态推进)照样按 60%%; 每次开冲都重写, 不留旧值
	u["dice_dash_active"] = true                    # 进入真冲刺连突态""" % SH),
    ("""func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
""", """func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
	var _ct = u.get("_dash_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_dice_dash_hit_body(u, tgt, dir)
	%s.ctx_exit_opt(_ct, _cp)


func _dice_dash_hit_body(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
""" % (SH, SH)),
])

edit("scripts/systems/skills/bubble_system.gd", [
    ("""	ally["bubble_shield_src"] = u
""", """	ally["bubble_shield_src"] = u
	ally["bubble_shield_copy"] = %s.ctx_capture()   # 龟壳复制期套的盾: 到期 / 被打破的爆裂照样按 60%%
""" % SH),
    ("""func _bubble_shield_burst(ally: Dictionary) -> void:
""", """func _bubble_shield_burst(ally: Dictionary) -> void:
	var _ct = ally.get("bubble_shield_copy")
	ally.erase("bubble_shield_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_bubble_shield_burst_body(ally)
	%s.ctx_exit_opt(_ct, _cp)


func _bubble_shield_burst_body(ally: Dictionary) -> void:
""" % (SH, SH)),
])

edit("scripts/systems/skills/crystal_system.gd", [
    ("""	u["bulwark_until"] = battle._t + BULWARK_SEC
""", """	u["bulwark_until"] = battle._t + BULWARK_SEC
	u["_bulwark_copy"] = %s.ctx_capture()   # 龟壳复制期开的壁垒: 盾破 / 到期放的水晶刺照样按 60%%
""" % SH),
    ("""func _crystal_spike_line(u: Dictionary) -> void:   # 照小菊R第三击""",
     """func _crystal_spike_line(u: Dictionary) -> void:
	var _ct = u.get("_bulwark_copy")
	u.erase("_bulwark_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_crystal_spike_line_body(u)
	%s.ctx_exit_opt(_ct, _cp)   # 刺的延后段(_pending_shots)在这里带上 tag


func _crystal_spike_line_body(u: Dictionary) -> void:   # 照小菊R第三击""" % (SH, SH)),
])

edit("scripts/systems/skills/lava_system.gd", [
    ("""		"next_tick": battle._t + 0.5, "src": u, "disc": disc,
""", """		"next_tick": battle._t + 0.5, "src": u, "disc": disc,
		"_copy": %s.ctx_capture(),   # 龟壳复制期放的地裂: 每跳照样按 60%%
""" % SH),
    ("""					battle._damage._apply_damage_from(src, o, _quake_tick_dmg(src, o), Color("#ff7a33"))
""", """					var _zcp: Array = %s.ctx_enter_opt(z.get("_copy"))
					battle._damage._apply_damage_from(src, o, _quake_tick_dmg(src, o), Color("#ff7a33"))
					%s.ctx_exit_opt(z.get("_copy"), _zcp)
""" % (SH, SH)),
    ("""func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 蓄力 → 目标脚下岩浆柱击飞 (1.5ATK魔 + 0.8ATK永久护盾)
""", """func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 蓄力 → 目标脚下岩浆柱击飞 (1.5ATK魔 + 0.8ATK永久护盾)
	var _ct = %s.ctx_capture()   # 龟壳复制期放的: 蓄力(await)之后的伤害与护盾照样按 60%%
""" % SH),
    ("""	if tgt != null and tgt.get("alive", false):
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, SURGE_ATK_COEF, tgt, true), Color("#ff9d5c"))
	battle._damage._grant_shield(u, u["atk"] * SURGE_SHIELD_COEF)
""", """	var _cp: Array = %s.ctx_enter_opt(_ct)
	if tgt != null and tgt.get("alive", false):
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, SURGE_ATK_COEF, tgt, true), Color("#ff9d5c"))
	battle._damage._grant_shield(u, u["atk"] * SURGE_SHIELD_COEF)
	%s.ctx_exit_opt(_ct, _cp)
""" % (SH, SH)),
])

edit("scripts/systems/skills/hiding_system.gd", [
    ("""func _minion_rocket_fly(u: Dictionary, tref: Dictionary, from: Vector2) -> void:   # 定向慢速追踪导弹""",
     """func _minion_rocket_fly(u: Dictionary, tref: Dictionary, from: Vector2) -> void:   # 定向慢速追踪导弹""".replace(
         "# 定向慢速追踪导弹", "# 定向慢速追踪导弹")),
    ("""	_minion_rocket_nuke(u, boom)
""", """	var _cp: Array = %s.ctx_enter_opt(_ct)
	_minion_rocket_nuke(u, boom)
	%s.ctx_exit_opt(_ct, _cp)
""" % (SH, SH)),
    ("""	battle._damage._apply_damage_from(u, tref, battle._phys_after_armor(u, float(tref["maxHp"]) * SURF_CONTACT_MAXHP_PCT, tref), Color("#ff4444"))""",
     """	var _cp0: Array = %s.ctx_enter_opt(_ct)
	battle._damage._apply_damage_from(u, tref, battle._phys_after_armor(u, float(tref["maxHp"]) * SURF_CONTACT_MAXHP_PCT, tref), Color("#ff4444"))""" % SH),
    ("""			battle._damage._apply_damage_from(u, tref, battle._atk_dmg(u, SURF_RIDE_ATK_COEF * 0.1 / slide_dur, tref, false), Color("#ff4444"))
""", """			var _cp1: Array = %s.ctx_enter_opt(_ct)
			battle._damage._apply_damage_from(u, tref, battle._atk_dmg(u, SURF_RIDE_ATK_COEF * 0.1 / slide_dur, tref, false), Color("#ff4444"))
			%s.ctx_exit_opt(_ct, _cp1)
""" % (SH, SH)),
    ("""				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, SURF_PASS_ATK_COEF, o, false), Color("#ff4444"))
""", """				var _cp2: Array = %s.ctx_enter_opt(_ct)
				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, SURF_PASS_ATK_COEF, o, false), Color("#ff4444"))
				%s.ctx_exit_opt(_ct, _cp2)
""" % (SH, SH)),
])

## 火箭 / 浪板: 函数第一行记 tag(这两个函数都是从已带 tag 的延后子弹 / 补间里同步调起的, 第一行仍在复制上下文里)
p = ROOT + "scripts/systems/skills/hiding_system.gd"
b = open(p, "rb").read().decode("utf-8")
crlf = "\r\n" in b
s = b.replace("\r\n", "\n")
lines = s.split("\n")
out = []
for i, l in enumerate(lines):
    out.append(l)
    if l.startswith("func _minion_rocket_fly(") or l.startswith("func _minion_bodysurf_ride("):
        out.append("\tvar _ct = %s.ctx_capture()   # 龟壳复制期放的: await 之后的结算照样按 60%%" % SH)
s2 = "\n".join(out)
assert s2.count("var _ct = %s.ctx_capture()" % SH) == 2
## 浪板接触那一段: 进了上下文要出来(接触伤害那一行后面紧跟的就是滑行演出)
a = """SURF_CONTACT_MAXHP_PCT, tref), Color("#ff4444"))"""
i = s2.index(a)
j = s2.index("\n", i)
s2 = s2[:j + 1] + "\t%s.ctx_exit_opt(_ct, _cp0)\n" % SH + s2[j + 1:]
open(p, "wb").write((s2.replace("\n", "\r\n") if crlf else s2).encode("utf-8"))

edit("scripts/systems/equip/eq_blade_batch.gd", [
    ("""		_waves.append({
			"u": u, "from": u["pos"], "dir": dir, "si": sx,
""", """		_waves.append({
			"u": u, "from": u["pos"], "dir": dir, "si": sx,
			"_copy": %s.ctx_capture(),   # 龟壳复制期放的十字斩: 波扫到谁照样按 60%%
""" % SH),
    ("""				battle._damage._apply_damage_from(u, o, d, Color("#bcd8ff"), 0.0, false, true)
""", """				var _wcp: Array = %s.ctx_enter_opt(w.get("_copy"))
				battle._damage._apply_damage_from(u, o, d, Color("#bcd8ff"), 0.0, false, true)
				%s.ctx_exit_opt(w.get("_copy"), _wcp)
""" % (SH, SH)),
])

edit("scripts/scenes/battle/battle_ballistics.gd", [
    ("""			if _step_homing_arrow(pr, node, delta):
				keep.append(pr)
			continue
""", """			## 龟壳复制期射出的追踪箭(猎人弹幕): 命中在这条分支里结算, 不走下面 frac >= 1 那段 ⇒ 这里单独还原
			var _hcp: Array = battle._shell_sys.ctx_enter(pr["_copy"]) if pr.get("_copy") is Array else []
			var _hkeep: bool = _step_homing_arrow(pr, node, delta)
			if not _hcp.is_empty():
				battle._shell_sys.ctx_exit(pr["_copy"], _hcp)
			if _hkeep:
				keep.append(pr)
			continue
"""),
])

edit("scripts/scenes/battle/battle_spawn.gd", [
    ("""	battle._units.append(su)
	return su
""", """	## 龟壳复制期召出的召唤物(海盗船…): 它之后造成的伤害一律按 60%(召唤物的伤害 src 是它自己, 不是龟壳)
	if battle._copy_fx_mult != 1.0:
		var _ct = battle._shell_sys.ctx_capture()
		if _ct != null:
			su["dmg_out_mult"] = float(_ct[0])
	battle._units.append(su)
	return su
"""),
])
print("ok")
