extends Node
## verify_skeleton_032.gd — 032 唤灵骨符【亡灵骷髅】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「开战时召唤一只亡灵骷髅(最大生命值 **16/31/55** · 攻击力 **3/5/8** · 护甲魔抗为 0,
##   但**受到的任何攻击(含真实伤害)都降为 1 点**; 死亡或存活 **13/17/23 秒**后爆炸,
##   对周围 **200 码**内敌人造成 **8/13/20% 其最大生命值的真实伤害**)。」
##
## ★这一件**原来既没有台子也没有门禁** —— 从没被逐件体检过。
## ★结算层查下来是健康的: 召唤是同步的(`_spawn_summon`), 到期自灭走 `summon_life` 每帧递减,
##   爆炸挂在死亡路径上, 全在 sim 时钟上 —— **不在** 024~029 那条「延时挂 tween」的病上。
##   tween 只用在骷髅立绘的出场缩放(纯观感)。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const HP := [16.0, 31.0, 55.0]
const ATK := [3.0, 5.0, 8.0]
const LIFE := [13.0, 17.0, 23.0]
const BOOM := [0.08, 0.13, 0.20]

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	return u


func _skel_of(carrier: Dictionary) -> Dictionary:
	for o in _s._units:
		if str(o.get("summon_kind", "")) == "skeleton" and o.get("alive", false):
			return o
	return {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 032 唤灵骨符: 亡灵骷髅 16/31/55 血 · 受任何伤害恒 1 点 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ── ① ★★召唤出来的骷髅: 血/攻吃星级, 双抗为 0 ────────────────────
	for si in [0, 1, 2]:
		_s._units.clear()
		var c: Dictionary = _mk(500.0, 400.0, "left")
		_s._units.append(c)
		_s._equip_sys._eq_summon_skeleton(c, si)
		var sk: Dictionary = _skel_of(c)
		if sk.is_empty():
			_ok("① ★★★%d 星召唤出骷髅" % [si + 1], false, "一只都没召出来")
			continue
		_ok("① ★★★%d 星: 血 %.0f(应 %.0f) / 攻 %.0f(应 %.0f) / 双抗 %.0f+%.0f(应 0+0)"
			% [si + 1, float(sk["maxHp"]), HP[si], float(sk["atk"]), ATK[si],
			   float(sk["def"]), float(sk["mr"])],
			absf(float(sk["maxHp"]) - HP[si]) < 0.5 and absf(float(sk["atk"]) - ATK[si]) < 0.5
				and absf(float(sk["def"])) < 0.01 and absf(float(sk["mr"])) < 0.01,
			"★血【不乘 HP_MULT】—— 文案给的 16/31/55 就是游戏里看得见的最终值(CLAUDE.md §3.1)")
		_ok("① ★★%d 星存活 %.0f 秒(应 %.0f)" % [si + 1, float(sk.get("summon_life", -1.0)), LIFE[si]],
			absf(float(sk.get("summon_life", -1.0)) - LIFE[si]) < 0.01)

	# ── ② ★★★受到【任何】攻击(含真实伤害)都降为 1 点 ─────────────────
	## 这是这一件的命门: 双抗是 0, 免伤靠 `_dmg_cap_one` 在 `_mitigate_incoming` 末尾收口。
	## 用双抗堆到 20000 的老办法**拦不住真伤**, 所以判据必须**两条伤害路径都验**。
	_s._units.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c2)
	_s._equip_sys._eq_summon_skeleton(c2, 2)
	var sk2: Dictionary = _skel_of(c2)
	_ok("② ★分母: 骷髅在场且带着 _dmg_cap_one 标记",
		not sk2.is_empty() and bool(sk2.get("_dmg_cap_one", false)))
	if not sk2.is_empty():
		var foe: Dictionary = _mk(700.0, 400.0, "right")
		foe["atk"] = 5000.0
		_s._units.append(foe)
		## a) 普攻/技能那条路 (_apply_damage_from) —— 物理
		var h0: float = float(sk2["hp"])
		_s._damage._apply_damage_from(foe, sk2, _s._resolve_dmg(foe, 5000.0, sk2, false), Color.WHITE, 0.0, false, true)
		var d_phys: float = h0 - float(sk2["hp"])
		_ok("② ★★★物理 5000 点也只掉 %.0f 点(应 1)" % d_phys, absf(d_phys - 1.0) < 0.01)
		## b) 魔法
		var h1: float = float(sk2["hp"])
		_s._damage._apply_damage_from(foe, sk2, _s._resolve_dmg(foe, 5000.0, sk2, true), Color.WHITE, 0.0, false, true)
		var d_mag: float = h1 - float(sk2["hp"])
		_ok("② ★★★魔法 5000 点也只掉 %.0f 点(应 1)" % d_mag, absf(d_mag - 1.0) < 0.01)
		## c) ★★真实伤害那条路 (_apply_damage, raw=true) —— 老办法(堆双抗)在这里会漏
		var h2: float = float(sk2["hp"])
		_s._damage._apply_damage(sk2, 5000, Color.WHITE, null, "tru", true)
		var d_true: float = h2 - float(sk2["hp"])
		_ok("② ★★★**真实伤害** 5000 点也只掉 %.0f 点(应 1)" % d_true, absf(d_true - 1.0) < 0.01,
			"文案明写「含真实伤害」; 堆双抗的老办法拦不住这一条")

	# ── ③ ★★★到期自灭 + 爆炸: 200 码内 8/13/20% 最大生命【真实伤害】────
	for si in [0, 2]:
		_s._units.clear()
		var c3: Dictionary = _mk(500.0, 400.0, "left")
		_s._units.append(c3)
		_s._equip_sys._eq_summon_skeleton(c3, si)
		var sk3: Dictionary = _skel_of(c3)
		if sk3.is_empty():
			_ok("③ %d 星骷髅在场" % [si + 1], false); continue
		## 圈内一个、圈外一个: 「挡多了也是错」
		var inside: Dictionary = _mk(float(sk3["pos"].x) + 150.0, float(sk3["pos"].y), "right")
		var outside: Dictionary = _mk(float(sk3["pos"].x) + 400.0, float(sk3["pos"].y), "right")
		inside["def"] = 500.0
		inside["mr"] = 500.0          # ★真伤: 双抗拉满也要照吃
		_s._units.append(inside)
		_s._units.append(outside)
		var hi: float = float(inside["hp"])
		var ho: float = float(outside["hp"])
		## 直接把寿命耗掉, 走产品自己那条「到期自灭」的路
		sk3["summon_life"] = 0.02
		for _k in range(20):
			_s._sim_step(_s.SIM_DT, false, false)
		var di: float = hi - float(inside["hp"])
		var do_: float = ho - float(outside["hp"])
		var want: float = float(inside["maxHp"]) * BOOM[si]
		_ok("③ ★★★%d 星到期爆炸: 圈内(150 码)吃 %.0f(应 %.0f = %.0f%% 最大生命)"
			% [si + 1, di, want, BOOM[si] * 100.0],
			absf(di - want) < 2.0,
			"★双抗拉满也照吃 ⇒ 确是【真实伤害】; 若为 0 则是到期自灭那条路没走通")
		_ok("③ ★★%d 星: 圈外(400 码 > %.0f 码)的没挨打(%.0f) —— 挡多了也是错"
			% [si + 1, float(sk3.get("boom_radius", 200.0)), do_],
			absf(do_) < 0.01)
		_ok("③ %d 星爆炸之后骷髅已不在场" % [si + 1], _skel_of(c3).is_empty(),
			"到期要自灭, 不是一直站着")

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 16:
		print("  [FAIL] ★断言只有 %d 条(<16) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 032 唤灵骨符" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
