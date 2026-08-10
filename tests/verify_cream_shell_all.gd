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

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 071 全队奶油护盾" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
