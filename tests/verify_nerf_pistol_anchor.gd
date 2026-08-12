extends Node
## verify_nerf_pistol_anchor.gd — 两处削弱的数值门禁（用户 2026-08-12）
##
## 用户原话：
##   「小手枪在拥有护盾时将不再有将伤害降低到1这个被动」
##   「巨沉之锚的每0.25回血削弱为0.1/0.2/3%最大生命值」
##
## ★为什么要单独立一条：这两处此前**一条数值门禁都没有** ——
##   077 的伤害封顶走的是主场景 `_mitigate_incoming()` 末尾那道共用闸（改一行就影响
##   两条伤害路径），017 的回血还兼着**沉锚充能的攒速**（累积治疗满 250 → +1 充能），
##   削回血等于连带削充能。这种"改一个数牵动两处"的地方，没有门禁就等于没人看着。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_nerf_pistol_anchor.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TickSys := preload("res://scripts/systems/equip/equip_tick_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 削弱: 小手枪伤害封顶 / 不沉之锚回血 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	# ══ ① 小手枪: 有护盾 ⇒ 不封顶 ════════════════════════════════════════
	var p: Dictionary = s._spawn._make_unit("basic", "left", c)
	p["maxHp"] = 100.0
	p["hp"] = 100.0
	p["shield"] = 0.0
	p["_dmg_cap_val"] = 2.0                     # 077 给小手枪写的就是这个值
	var no_shield: float = s._mitigate_incoming(p, 100.0, true)
	_ok("① 没护盾时仍然封顶到 2(这条被动本身还在)",
		absf(no_shield - 2.0) < 0.01, "实得 %.2f" % no_shield)
	p["shield"] = 50.0
	var with_shield: float = s._mitigate_incoming(p, 100.0, true)
	_ok("① ★有护盾时【不再封顶】(用户削弱: 护盾期间按原样吃伤害)",
		with_shield > 90.0, "实得 %.2f(应≈100)" % with_shield)
	p["shield"] = 0.0
	var back: float = s._mitigate_incoming(p, 100.0, true)
	_ok("① ★盾破之后封顶【重新生效】(不是一次性永久失效)",
		absf(back - 2.0) < 0.01, "实得 %.2f" % back)
	# 携带者阵亡后的 5 点档同样吃这条规则(它走的是同一个字段)
	p["_dmg_cap_val"] = 5.0
	p["shield"] = 30.0
	_ok("① 携带者死后的 5 点档也一样(同一个字段, 别只堵一半)",
		s._mitigate_incoming(p, 100.0, true) > 90.0)

	# ══ ② 不沉之锚: 每 0.25 秒回 0.1/0.2/3% 最大生命 ═══════════════════════
	#   ★同时验【充能攒速】: 这条回血兼着沉锚充能的来源(累积满 250 → +1 充能),
	#     削回血 = 连带削充能。只验治疗量会漏掉一半影响面。
	var want := [0.001, 0.002, 0.03]
	var checked := 0
	for star in [1, 2, 3]:
		var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-100, 0))
		u["maxHp"] = 10000.0
		u["hp"] = 10000.0
		u["equips"] = [{"id": "p2eq_017", "star": star}]
		u["eq_state"] = {"p2eq_017": {"anchor_accum": 0.0, "anchor_charges": 0}}
		var ally: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-160, 0))
		ally["maxHp"] = 100000.0
		ally["hp"] = 1000.0                     # 血量百分比最低 ⇒ 它是受益者
		s._units.clear()
		s._units.append_array([u, ally])
		var hp0: float = float(ally["hp"])
		s._equip_tick_sys._tick_anchor(u, TickSys.ANCHOR_IV + 0.001)
		var healed: float = float(ally["hp"]) - hp0
		var expect: float = 10000.0 * want[star - 1]
		_ok("② ★%d 每 0.25 秒回 %.1f%% 最大生命 = %.0f" % [star, want[star - 1] * 100.0, expect],
			absf(healed - expect) < 0.51, "实得 %.1f" % healed)
		## ★算【总账】不算条上余额: 一次回血超过 250 会当场兑成充能(★3 回 300 ⇒ 兑 1 次, 条上剩 50)。
		##   第一版只比条上余额, ★3 当场 FAIL —— 判据漏了兑换这一步。
		var st17: Dictionary = u["eq_state"]["p2eq_017"]
		var acc: float = float(st17.get("anchor_accum", 0.0))
		var chg: int = int(st17.get("anchor_charges", 0))
		var total: float = acc + float(chg) * TickSys.ANCHOR_ACC_PER_CHARGE
		_ok("② ★%d 的沉锚充能按【削弱后的】治疗量攒(削回血=连带削充能)" % star,
			absf(total - healed) < 0.51,
			"条 %.1f + 充能 %d×%.0f = %.1f / 实际治疗 %.1f"
				% [acc, chg, TickSys.ANCHOR_ACC_PER_CHARGE, total, healed])
		checked += 1
	_ok("② ★分母: 三个星级都验过了", checked == 3, "实得 %d" % checked)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 小手枪/不沉之锚 削弱" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
