extends Node
## verify_cream_shell_all.gd — 071 炼乳罐【全队奶油护盾必须每人一个壳】(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-10「还有很多特效残留问题」→ 实拍发现 071「全队奶油护盾完全没表达」
## ══════════════════════════════════════════════════════════════════
## 根因: `_cream_grant_all()` 把护盾值发给了**全队**(`_allies_of(u, true)` 逐个 `grant`)，
## 但壳只建了一个、而且建在**携带者**身上:
##
##     if not (stt.get("shell", null) is Dictionary):
##         stt["shell"] = _vfx.cream_shell_make(u)      # ← u = 携带者, 不是受益的那一位
##
## ⇒ 友军拿到了盾、身上却什么都没有。**这一类比"颜色不对"严重**:
##   玩家无从得知效果生效了没有。
##
## 染色法实测(2026-08-11, 把壳染成品红再数像素):
##   改前 693 个品红像素(1 个壳) → 改后 2005~2249(约 3 倍) = 携带者 + 2 友军。
##
## ★这条门禁**数真实节点**, 不数记账字段 —— "写了没人读"正是这个 bug 的形状。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_cream_shell_all.tscn --quit-after 2000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CREAM_KEY := "p2eq_071_cream"

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _mk(side: String, p: Vector2, eq: Array = []) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, p)
	u["alive"] = true
	u["pos"] = p
	u["hp"] = 3000.0
	u["maxHp"] = 3000.0
	u["equips"] = eq
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 071 炼乳罐: 全队奶油护盾每人一个壳 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var carrier := _mk("left", c + Vector2(-160.0, 0.0), [{"id": "p2eq_071", "star": 3}])
	var a1 := _mk("left", c + Vector2(-80.0, -60.0))
	var a2 := _mk("left", c + Vector2(-80.0, 60.0))
	_mk("right", c + Vector2(200.0, 0.0))          # 敌人(不该拿到盾)

	var allies: Array = [carrier, a1, a2]
	_ok("★分母: 造出 %d 只友军(含携带者)" % allies.size(), allies.size() == 3)

	# 走真入口: 装备的每帧 tick
	var fb = _s._equip_sys._food_sys
	_ok("★分母: 拿到食物批系统", fb != null)
	if fb == null:
		print("FAIL x1"); get_tree().quit(1); return
	## ★走真入口 `tick_unit(u, delta)` —— 它就是主循环逐单位调的那个
	for _i in range(6):
		fb.tick_unit(carrier, 0.2)
		await get_tree().process_frame

	# ── ① 每个友军都拿到了盾 ────────────────────────────────────
	var got := 0
	for u in allies:
		if _s._spec.val(u, CREAM_KEY) > 0.0:
			got += 1
	_ok("① 全队都拿到了奶油护盾(%d/%d)" % [got, allies.size()], got == allies.size(),
		"只有 %d 只拿到" % got)

	# ── ② ★★每个拿到盾的都必须有壳(数【真实节点】) ─────────────
	var shells := 0
	var missing: Array = []
	for u in allies:
		if _s._spec.val(u, CREAM_KEY) <= 0.0:
			continue
		var h = u.get("_cream_shell", null)
		var spr = (h as Dictionary).get("spr", null) if h is Dictionary else null
		if is_instance_valid(spr):
			shells += 1
		else:
			missing.append(str(u.get("id", "?")))
	_ok("② ★★每个拿到盾的友军身上都有壳(%d 个壳 / %d 个盾)" % [shells, got],
		shells == got and shells > 1,
		"缺壳的: %s —— 改之前只有携带者有壳, 友军拿到盾却什么都没有" % str(missing))

	# ── ③ 敌人不该拿到 ────────────────────────────────────────
	var foe_got := 0
	for u in _s._units:
		if str(u.get("side", "")) == "right" and _s._spec.val(u, CREAM_KEY) > 0.0:
			foe_got += 1
	_ok("③ 敌人一个都没拿到(不然是发错阵营)", foe_got == 0, "敌人拿到 %d" % foe_got)

	# ── ⑤ 两条伤害路径都先扣奶油盾、不碰血(用户 11-11「出手拍击的时候, 他直接是血条掉了, 这个护盾没动」):
	##   触手拍击 = 无出手者的 _apply_damage(11-11 起独立出手方); 普攻 / 技能 = _apply_damage_from。
	var foe: Dictionary = {}
	for u in _s._units:
		if str(u.get("side", "")) == "right":
			foe = u
	var c5: float = _s._spec.val(a2, CREAM_KEY)
	var hp5: float = float(a2["hp"])
	_s._damage._apply_damage(a2, 200, Color.WHITE, null, "phy")
	var c5b: float = _s._spec.val(a2, CREAM_KEY)
	_ok("⑤ ★无出手者那条(触手拍击走的)先扣奶油盾、血不掉(盾 %.0f → %.0f · 血 %.0f → %.0f)" % [c5, c5b, hp5, float(a2["hp"])],
		c5 > 200.0 and c5b < c5 and absf(float(a2["hp"]) - hp5) < 0.01)
	_s._damage._apply_damage_from(foe, a2, 150, Color.WHITE, 0.0, false, true)
	var c5c: float = _s._spec.val(a2, CREAM_KEY)
	_ok("⑤ ★有出手者那条(普攻 / 技能)先扣奶油盾、血不掉(盾 %.0f → %.0f · 血 %.0f)" % [c5b, c5c, float(a2["hp"])],
		not foe.is_empty() and c5c < c5b and absf(float(a2["hp"]) - hp5) < 0.01)
	fb.tick_global(0.05)
	_ok("⑤ 携带者活着时血条奶油段跟着掉(镜像 %.0f = 余额 %.0f)" % [float(a2.get("_creamShieldVal", -1.0)), c5c],
		absf(float(a2.get("_creamShieldVal", -1.0)) - c5c) < 0.5)

	# ── ④ ★携带者阵亡后, 友军的血条奶油段 / 壳仍跟着真实余额走(用户 11-11「护盾没有格挡到任何伤害…伤害只是通过这个护盾打到人」)
	##   原来镜像只在携带者的 tick 里写 ⇒ 携带者死了就停在死前那一刻: 盾在扛、血条上的盾不掉; 盾打破了壳还亮着、血在掉。
	##   走真入口 `tick_global`(EquipSystem 每步调的那个), 伤害走 SpecialBalance.absorb(两条伤害路径共用的那一步)。
	carrier["alive"] = false
	var v0: float = _s._spec.val(a1, CREAM_KEY)
	var left_over: float = _s._spec.absorb(a1, v0 * 0.5)
	fb.tick_global(0.05)
	var v1: float = _s._spec.val(a1, CREAM_KEY)
	_ok("④ 分母: 挨了一半盾量的伤害, 全被盾扛下(余额 %.0f → %.0f, 漏到血上 %.0f)" % [v0, v1, left_over],
		v0 > 0.0 and absf(v1 - v0 * 0.5) < 0.5 and left_over <= 0.0)
	_ok("④ ★携带者已阵亡, 友军血条上的奶油段跟着掉(镜像 %.0f = 余额 %.0f)" % [float(a1.get("_creamShieldVal", -1.0)), v1],
		absf(float(a1.get("_creamShieldVal", -1.0)) - v1) < 0.5)
	_s._spec.absorb(a1, v1 + 10.0)
	fb.tick_global(0.05)
	var sh_left = a1.get("_cream_shell", null)
	_ok("④ ★盾打破后血条奶油段归零、壳收掉(携带者已阵亡)",
		float(a1.get("_creamShieldVal", -1.0)) <= 0.0 and not (sh_left is Dictionary),
		"镜像 %.0f 壳 %s" % [float(a1.get("_creamShieldVal", -1.0)), str(sh_left is Dictionary)])

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 071 全队奶油护盾" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
