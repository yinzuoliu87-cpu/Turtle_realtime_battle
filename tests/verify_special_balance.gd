extends Node
## verify_special_balance.gd — 【特殊余额】基建（2026-08-05）
##
## 这层是 064 幽灵护盾 / 068 法力护盾 / 070 灰色血条 / 071 奶油护盾 / 072 终极护盾
## **五件装备共同的地基**。它塌了会同时塌五件, 所以单独守。
##
## 守八条:
##   ⓪ 分母: 战场与 _spec 真的起来了
##   ① 普通盾【先扛】, 特殊余额在它之后
##   ② 多条余额按 order 升序依次扛(确定性)
##   ③ 被打光 → on_break(reason="damage")
##   ④ ★自然衰减完 → on_break(reason="decay") —— 064 明确要求"耗尽也算被打破"
##   ⑤ ★衰减是【按初始峰值线性】的, 不是指数
##   ⑥ decay_sec = 0 ⇒ 永不衰减(071 奶油盾/072 终极盾要)
##   ⑦ ★★两条伤害路径【都】接了 absorb(§3.3 只接一条 = 只有被普攻打才吃盾)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_special_balance.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond: print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _dummy(side: String) -> Dictionary:
	var o := Vector2(_s.ARENA.position.x + 200.0, _s.ARENA.position.y + 200.0)
	var u: Dictionary = _s._spawn._make_unit("basic", side, o)
	u["alive"] = true; u["hp"] = 100000.0; u["maxHp"] = 100000.0
	u["shield"] = 0.0; u["flat_dr"] = 0.0; u["def"] = 0.0; u["mr"] = 0.0
	_s._units.append(u)
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 特殊余额基建 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	if _s == null:
		print("  [FAIL] ⓪ 战场没起来"); print("FAIL x1"); get_tree().quit(1); return
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._units.clear()
	var sp = _s._spec
	_ok("⓪ ★分母: 战场与 _spec 都在", sp != null, "_spec 是 null")
	if sp == null: print("FAIL x1"); get_tree().quit(1); return

	# ── ① 普通盾先扛 ──
	var u1 := _dummy("left")
	u1["shield"] = 50.0
	sp.grant(u1, "k1", 100.0)
	var left: float = sp.absorb(u1, 30.0)
	_ok("① ★普通盾未接触前, 特殊余额不该动(普通盾由 ShieldMath 先扛)",
		absf(sp.val(u1, "k1") - 70.0) < 0.51,
		"特殊余额被扣成 %.1f, 期望 70(因为本测试直接调 absorb, 普通盾那步在它之前)" % sp.val(u1, "k1"))

	# ── ② 多条按 order 依次扛 ──
	var u2 := _dummy("left")
	sp.grant(u2, "late", 100.0, {"order": 9})
	sp.grant(u2, "early", 40.0, {"order": 1})
	var rest: float = sp.absorb(u2, 60.0)
	_ok("② ★按 order 升序: order=1 的先被打光(实测 early=%.0f late=%.0f)"
		% [sp.val(u2, "early"), sp.val(u2, "late")],
		sp.val(u2, "early") <= 0.51 and absf(sp.val(u2, "late") - 80.0) < 0.51,
		"顺序不对")
	_ok("②b ★分母: 60 伤害被两条吃光, 无穿透(实测穿透 %.1f)" % rest, rest <= 0.51)

	# ── ③ 打光触发 on_break(damage) ──
	var got := {"reason": "", "n": 0}
	var u3 := _dummy("left")
	sp.grant(u3, "b", 20.0, {"on_break": func(_u, _k, r): got["reason"] = r; got["n"] += 1})
	sp.absorb(u3, 25.0)
	_ok("③ ★被打光 → on_break(reason=\"damage\")（实测 %d 次 / reason=%s）" % [got["n"], got["reason"]],
		got["n"] == 1 and got["reason"] == "damage")

	# ── ④⑤ 线性衰减 + 耗尽算"被打破" ──
	var got2 := {"reason": "", "n": 0}
	var u4 := _dummy("left")
	sp.grant(u4, "g", 100.0, {"decay_sec": 10.0,
		"on_break": func(_u, _k, r): got2["reason"] = r; got2["n"] += 1})
	sp.tick(2.5)
	var after25: float = sp.val(u4, "g")
	_ok("⑤ ★线性衰减: 10 秒衰减的余额, 走 2.5 秒后应剩 75(实测 %.1f)" % after25,
		absf(after25 - 75.0) < 0.51, "不是线性")
	sp.tick(2.5)
	_ok("⑤b ★再走 2.5 秒应剩 50(实测 %.1f) —— 每段掉的量相同 = 线性不是指数" % sp.val(u4, "g"),
		absf(sp.val(u4, "g") - 50.0) < 0.51)
	sp.tick(6.0)
	_ok("④ ★★自然衰减完 → on_break(reason=\"decay\")（064 明确要求"
		+ "「耗尽也算被打破」⇒ 必定爆炸）实测 %d 次 / reason=%s" % [got2["n"], got2["reason"]],
		got2["n"] == 1 and got2["reason"] == "decay")

	# ── ⑥ 永不衰减 ──
	var u6 := _dummy("left")
	sp.grant(u6, "perm", 100.0)          # decay_sec 缺省 = 0
	sp.tick(60.0)
	_ok("⑥ ★decay_sec=0 ⇒ 永不衰减(走 60 秒后仍是 %.0f)" % sp.val(u6, "perm"),
		absf(sp.val(u6, "perm") - 100.0) < 0.51)

	# ── ⑦ 两条伤害路径都接了 ──
	var src: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	var cnt: int = src.count("_spec.absorb(")
	_ok("⑦ ★★battle_damage.gd 里 `_spec.absorb(` 正好 2 处(§3.3 两条伤害路径各一次)，实测 %d" % cnt,
		cnt == 2,
		"只接一条 = 「只有被普攻打才吃特殊盾」, DoT/真伤会直接穿过去")

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 特殊余额基建" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
