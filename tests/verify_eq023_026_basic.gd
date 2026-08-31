extends Node
## verify_eq023_026_basic.gd — 023 火珊瑚 / 026 雷电法杖: 只跟普攻走 (2026-08-31)
##
## ★需求原文(用户 2026-08-31):
##   「炽热火珊瑚改为每段普攻施加灼烧和获得法力而不是每段伤害，雷电法杖也是改为普攻获得法力」
##   拍板: 023 的【灼烧与法力两个都收】· 强度【不要补】。
##
## ★核心是【反面断言】: 非普攻命中不许再给。只验"普攻能给"守不住 —— 改前普攻本来就能给。
##
## ★★这条门禁**不**断言"技能不涨法力" —— 那是错的。法器法力还有另外三路
##   (每 2.5 秒回充 / 造成伤害 ×0.1 / 受伤 ×0.1), 其中"造成伤害"那一路不分普攻技能。
##   本次收掉的只是 023/026 的【定额】, 所以判据必须**只量这份定额**:
##   直接调 `_eq_on_hit`(不走伤害管线) ⇒ "造成伤害×0.1"那一路不会掺进来。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _mk(side: String, off: Vector2) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", side, c + off)
	for k in ["shield", "def", "mr", "base_def", "base_mr", "dodge_bonus", "damage_amp", "crit"]:
		u[k] = 0.0
	u["maxHp"] = 1.0e6
	u["hp"] = 1.0e6
	u["dots"] = []
	_s._units.append(u)
	return u


func _burn(o: Dictionary) -> int:
	return int((o.get("dot_stacks", {}) as Dictionary).get("burn", 0))


func _mana(u: Dictionary, iid: String) -> float:
	var st: Dictionary = (u.get("eq_state", {}) as Dictionary).get(iid, {})
	return float(st.get("mana", 0.0))


## 装一件、打 n 下、回报 [灼烧层数, 法力]
func _run(iid: String, star: int, basic: bool, n: int) -> Array:
	_s._units.clear()
	var a: Dictionary = _mk("left", Vector2(-120.0, 0.0))
	var d: Dictionary = _mk("right", Vector2(-40.0, 0.0))
	a["equips"] = [{"id": iid, "star": star}]
	a["eq_state"] = {iid: {}}
	_s._equip_sys._stats._eq_apply_all_stats()
	a["atk"] = 100.0
	for _k in range(n):
		_s._equip_sys._eq_on_hit(a, d, 100, basic)
	return [_burn(d), _mana(a, iid)]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 023 / 026: 只跟普攻走 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	# ── 023 火珊瑚: 灼烧 + 法力 两个都收 ──
	var b1: Array = _run("p2eq_023", 3, true, 1)
	_ok("023 ★★普攻 1 下 → 叠灼烧", int(b1[0]) > 0, "%d 层" % int(b1[0]))
	_ok("023 ★★普攻 1 下 → 涨法力", float(b1[1]) > 0.0, "%.0f 点" % float(b1[1]))
	var b0: Array = _run("p2eq_023", 3, false, 10)
	_ok("023 ★★非普攻 10 下 → 一层灼烧都不许有", int(b0[0]) == 0, "%d 层" % int(b0[0]))
	_ok("023 ★★非普攻 10 下 → 一点法力都不许给(这份定额)",
		is_zero_approx(float(b0[1])), "%.1f 点" % float(b0[1]))

	# ── 026 雷电法杖: 法力 ──
	var t1: Array = _run("p2eq_026", 3, true, 1)
	_ok("026 ★★普攻 1 下 → 涨法力", float(t1[1]) > 0.0, "%.0f 点" % float(t1[1]))
	var t0: Array = _run("p2eq_026", 3, false, 10)
	_ok("026 ★★非普攻 10 下 → 一点法力都不许给", is_zero_approx(float(t0[1])),
		"%.1f 点" % float(t0[1]))

	# ── 数值没被顺手改(用户「不要补」) ──
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var code := ""
	for ln in src.split("\n"):
		if not str(ln).strip_edges().begins_with("#"):
			code += str(ln) + "\n"
	_ok("★分母: 剔注释后代码仍占大头", float(code.length()) > float(src.length()) * 0.4,
		"%d / %d" % [code.length(), src.length()])
	_ok("数值没被补 · 023 灼烧公式仍是 [2.0, 5.0, 8.0] + [0.07, 0.11, 0.15]×ATK",
		code.contains("[2.0, 5.0, 8.0][si] + [0.07, 0.11, 0.15][si] * src[\"atk\"]"))
	_ok("数值没被补 · 两件的每击定额仍走原常量",
		code.contains("add_mana(src, CORAL_MANA_PER_HIT)")
		and code.contains("add_mana(src, THUNDER_MANA_PER_HIT)"))

	# ── 069 改名 ──
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_069", {})
	_ok("069 名字 = 草莓蛋糕", str(eq.get("name", "")) == "草莓蛋糕", str(eq.get("name", "")))
	_ok("069 ★图标【不动】(用户明确说不改图) —— 仍是 equip/p2eq_069.png",
		str(eq.get("img", "")) == "equip/p2eq_069.png", str(eq.get("img", "")))
	_ok("069 文案里不再出现旧词「糖糕」(改名的连带, 否则玩家看到「草莓蛋糕…吃一块糖糕」)",
		not str(eq.get("effectDesc1", "")).contains("糖糕")
		and not str(eq.get("effectBrief", "")).contains("糖糕"))

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12)" % _n)
		_fail += 1
	print("ALL PASS — 023/026 只跟普攻走" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
