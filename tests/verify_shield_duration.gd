extends Node
## verify_shield_duration.gd — 【通用护盾 = 4 秒】封板规则的门禁 (2026-09-11)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来
## ════════════════════════════════════════════════════════════════════════
## 用户看 012 演示时问:「**而且盾不过期是什么东西，我记得通用护盾是4秒啊，
## 特殊护盾有特殊说明啊，这几件不会都是这种问题吧**」。
##
## 他记得没错。封板规则写在 `docs/design/技能改制设计决策.md`(石龟封板补全一节):
##   「全局规则: 所有"通用护盾"持续=4秒(嘲讽的"永久护盾"是特例除外)。」
##
## 2026-08 那一轮把这条扫进了**技能**(bamboo/bubble/diamond 各自存了一份
## `*_SHIELD_SEC := 4.0`), 却**一处都没扫进装备** —— 装备层 49 个给盾点里
## 27 个还在吃 `_grant_shield` 的默认 `dur = 0`(永久)。
##
## ★这条门禁守两件事:
##   ① 四件文案没写时长的装备(012/015/016/021) 必须给 **4 秒** 盾;
##   ② 013 炙烤海胆 文案写了「10 秒内逐渐衰减」⇒ 它**不该**被扫成 4 秒(反面样本)。
##   顺带守住 ②' 新加的"限时/永久分账": 一份 4 秒盾到期不许把永久盾一起抹掉。
##
## ★★锚点是【封板规则】不是代码常量。期望值写死 `SPEC_SEC = 4.0`,
##   **不拿 `BattleDamage.COMMON_SHIELD_SEC` 当期望值** —— 那是拿被测对象量它自己,
##   调常量时两边一起动, 判据永远绿([[fb-gate-tautological-when-it-spans-a-frame]] 同族)。
##
## ★判据一律落在【产品自己的账】上: `shield` / `shield_until` 的真实数值 +
##   走真入口(`_tick_jelly` / `_tick_ironwall` / `_tick_barnacle` / `_eq_on_target`)
##   + 到期这一步走真的 `_tick_periodic_passive`, 不自己模拟过期公式。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BD := preload("res://scripts/scenes/battle/battle_damage.gd")

## 封板值(来源: docs/design/技能改制设计决策.md 石龟封板补全「所有"通用护盾"持续=4秒」)
const SPEC_SEC := 4.0

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## 干净合成单位: 抹掉一切会干扰护盾/伤害数值的属性(CLAUDE.md §7「用干净合成单位隔离」)。
## ★用 green 不用 basic —— 小龟有【不屈】全局增伤被动, 会把伤害数值弄歪
##   (verify_shield_synergy 踩过, 探针才看出来)。
func _mk(side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c + off)
	for k in ["shield", "flat_dr", "def", "mr", "base_def", "base_mr", "dodge_bonus",
			"damage_reduction", "damage_amp", "crit", "armor_pen", "magic_pen",
			"armor_pen_pct", "magic_pen_pct", "lifesteal", "heal_amp", "shield_amp"]:
		u[k] = 0.0
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield_until"] = 0.0
	u["shield_timed"] = 0.0
	u["dots"] = []
	u["no_basic"] = true
	u["no_move"] = true
	u["eq_state"] = {}
	return u


## 推进到"超过到期时刻", 然后走**真的**每帧被动 tick 让它自己过期。
## ★不自己写 `if _t >= until: shield = 0` —— 那是把被测逻辑抄一份到测试里。
func _expire(u: Dictionary, extra: float = 0.2) -> void:
	_s._t += SPEC_SEC + extra
	_s._tick_periodic_passive(u, 0.016)


func _dur_of(u: Dictionary) -> float:
	return float(u.get("shield_until", 0.0)) - float(_s._t)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true            # ★调试台要渲染 ⇒ 不是 headless ⇒ 不置位会写真存档
	print("=== 通用护盾 = 4 秒(封板规则) ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s._edit_mode = false
	_s._over = false

	_g1_primitive()
	_g2_perm_not_killed()
	_g3_jelly_012()
	_g4_ironwall_016()
	_g5_barnacle_021()
	_g6_thorn_015()
	_g7_urchin_013_is_special()

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 24:
		print("  [FAIL] ★分母: 断言只有 %d 条(<24) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 通用护盾 4 秒" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ── ① 原语: dur>0 才过期, dur=0 仍是永久 ────────────────────────────────
func _g1_primitive() -> void:
	print("--- ① 限时盾原语 ---")
	_ok("①a ★锚点: 封板值 4 秒在代码里有一个共用常量(装备层原本一份都没有)",
		absf(BD.COMMON_SHIELD_SEC - SPEC_SEC) < 0.001,
		"COMMON_SHIELD_SEC=%.2f 封板 %.2f" % [BD.COMMON_SHIELD_SEC, SPEC_SEC])

	var u: Dictionary = _mk("left", Vector2(-160, 0))
	_s._units.clear()
	_s._units.append(u)
	_s._damage._grant_shield(u, 100.0, SPEC_SEC)
	_ok("①b ★分母: 真的拿到盾了(0 = 下面全是空检查)", float(u["shield"]) > 1.0,
		"盾 %.0f" % float(u["shield"]))
	_ok("①b 限时盾到期时刻 = 当前时间 + 4 秒", absf(_dur_of(u) - SPEC_SEC) < 0.05,
		"剩余 %.3f 秒" % _dur_of(u))
	_expire(u)
	_ok("①c ★到点后盾**真的没了**(走真 _tick_periodic_passive, 不是测试自己算的)",
		float(u["shield"]) < 0.01, "盾 %.1f" % float(u["shield"]))

	## 对照: 不传 dur 的还是永久 —— 证明 ①c 不是"盾被别的什么东西清掉了"
	var p: Dictionary = _mk("left", Vector2(-200, 0))
	_s._units.append(p)
	_s._damage._grant_shield(p, 100.0)
	_ok("①d 对照: 不传时长 ⇒ 不记到期(shield_until 保持 0)",
		absf(float(p.get("shield_until", -1.0))) < 0.001,
		"shield_until=%.3f" % float(p.get("shield_until", -1.0)))
	_expire(p)
	_ok("①d 对照: 同样推进 4.2 秒后永久盾**还在**(否则 ①c 是假阳性)",
		float(p["shield"]) > 99.0, "盾 %.1f" % float(p["shield"]))


# ── ② 限时/永久分账: 一份 4 秒盾到期不许把永久盾一起杀掉 ──────────────────
func _g2_perm_not_killed() -> void:
	print("--- ② 限时盾到期不许误杀永久盾 ---")
	## ★这个坑原本就在(2026-08 起就有 18 处限时给盾), 四件装备改成限时后变得常见:
	##   石龟嘲讽给自己 1A **永久**盾, 队友带 016 铁壁盾每 5 秒给全队一份 4 秒盾 ⇒
	##   老写法 `u["shield"] = 0.0` 会在 4 秒到点把嘲讽盾一起抹掉。
	var u: Dictionary = _mk("left", Vector2(-160, 40))
	_s._units.clear()
	_s._units.append(u)
	_s._damage._grant_shield(u, 100.0)            # 永久
	_s._damage._grant_shield(u, 50.0, SPEC_SEC)   # 限时
	_ok("②a ★分母: 两份盾都进账了(150)", absf(float(u["shield"]) - 150.0) < 0.5,
		"盾 %.1f" % float(u["shield"]))
	_expire(u)
	_ok("②b ★★到期后只掉限时那 50, 永久那 100 还在", absf(float(u["shield"]) - 100.0) < 0.5,
		"盾 %.1f(应 100)" % float(u["shield"]))

	## 伤害先吃限时那一份
	var v: Dictionary = _mk("left", Vector2(-200, 40))
	var foe: Dictionary = _mk("right", Vector2(200, 40))
	_s._units.clear()
	_s._units.append_array([v, foe])
	_s._damage._grant_shield(v, 100.0)
	_s._damage._grant_shield(v, 50.0, SPEC_SEC)
	_s._damage._apply_damage_from(foe, v, 30, Color.WHITE, 0.0, true, true)
	_ok("②c ★分母: 30 点伤害确实被盾吃了(盾 150 → 120)",
		absf(float(v["shield"]) - 120.0) < 1.5, "盾 %.1f" % float(v["shield"]))
	_expire(v)
	_ok("②c ★限时那份先被消耗 ⇒ 到期后永久 100 完好",
		absf(float(v["shield"]) - 100.0) < 1.5, "盾 %.1f(应 100)" % float(v["shield"]))

	var w: Dictionary = _mk("left", Vector2(-240, 40))
	_s._units.clear()
	_s._units.append_array([w, foe])
	_s._damage._grant_shield(w, 100.0)
	_s._damage._grant_shield(w, 50.0, SPEC_SEC)
	_s._damage._apply_damage_from(foe, w, 80, Color.WHITE, 0.0, true, true)
	_expire(w)
	_ok("②d 打穿限时那份后继续吃永久: 挨 80 ⇒ 到期后剩 70",
		absf(float(w["shield"]) - 70.0) < 1.5, "盾 %.1f(应 70)" % float(w["shield"]))


# ── ③ 012(海藻): 每 4 秒自盾, 该盾 4 秒 ────────────────────────────────
func _g3_jelly_012() -> void:
	print("--- ③ 012: 每 4 秒自盾 ---")
	var u: Dictionary = _mk("left", Vector2(-160, -40), 5000.0)
	u["equips"] = [{"id": "p2eq_012", "star": 3}]
	u["eq_state"] = {"p2eq_012": {}}
	_s._units.clear()
	_s._units.append(u)
	var tk = _s._equip_tick_sys
	tk._tick_jelly(u, 3.9)
	_ok("③ ★分母: 3.9 秒还没到点 ⇒ 不该给盾(否则下面量的是别的东西)",
		float(u["shield"]) < 0.01, "盾 %.1f" % float(u["shield"]))
	tk._tick_jelly(u, 0.2)
	_ok("③ ★分母: 跨过 4 秒真的给盾了", float(u["shield"]) > 1.0, "盾 %.1f" % float(u["shield"]))
	_ok("③ ★★012 的盾持续 4 秒(封板通用护盾), 不是永久",
		absf(_dur_of(u) - SPEC_SEC) < 0.05, "剩余 %.3f 秒" % _dur_of(u))
	_expire(u)
	_ok("③ ★端到端: 到点后盾清零", float(u["shield"]) < 0.01, "盾 %.1f" % float(u["shield"]))


# ── ④ 016 铁壁盾: 全队分摊的那份也要 4 秒 ───────────────────────────────
func _g4_ironwall_016() -> void:
	print("--- ④ 016 铁壁盾(全队分摊) ---")
	var u: Dictionary = _mk("left", Vector2(-160, 80), 5000.0)
	var mate: Dictionary = _mk("left", Vector2(-120, 80), 5000.0)
	u["equips"] = [{"id": "p2eq_016", "star": 3}]
	u["eq_state"] = {"p2eq_016": {}}
	_s._units.clear()
	_s._units.append_array([u, mate])
	_s._equip_tick_sys._tick_ironwall(u, 5.1)
	_ok("④ ★分母: 携带者拿到分摊的盾", float(u["shield"]) > 1.0, "盾 %.1f" % float(u["shield"]))
	_ok("④ ★分母: **队友**也拿到了(不带装备的那只)", float(mate["shield"]) > 1.0,
		"盾 %.1f" % float(mate["shield"]))
	_ok("④ ★★携带者那份 4 秒", absf(_dur_of(u) - SPEC_SEC) < 0.05,
		"剩余 %.3f 秒" % _dur_of(u))
	_ok("④ ★★队友那份也 4 秒(分摊出去的盾不许变永久)",
		absf(_dur_of(mate) - SPEC_SEC) < 0.05, "剩余 %.3f 秒" % _dur_of(mate))


# ── ⑤ 021 守护贝母: 连给友军的盾 4 秒 ──────────────────────────────────
func _g5_barnacle_021() -> void:
	print("--- ⑤ 021 守护贝母(连最高攻友军) ---")
	var u: Dictionary = _mk("left", Vector2(-160, 120), 5000.0)
	var mate: Dictionary = _mk("left", Vector2(-120, 120), 5000.0)
	mate["atk"] = 999.0                      # 让它当"全队攻击力最高的友军"
	u["atk"] = 10.0
	u["equips"] = [{"id": "p2eq_021", "star": 3}]
	u["eq_state"] = {"p2eq_021": {}}
	_s._units.clear()
	_s._units.append_array([u, mate])
	_s._equip_tick_sys._tick_barnacle(u, 5.1)
	_ok("⑤ ★分母: 被连接的友军真的拿到盾了", float(mate["shield"]) > 1.0,
		"盾 %.1f" % float(mate["shield"]))
	_ok("⑤ ★★那份盾 4 秒(文案没写时长 ⇒ 吃通用规则)",
		absf(_dur_of(mate) - SPEC_SEC) < 0.05, "剩余 %.3f 秒" % _dur_of(mate))


# ── ⑥ 015 荆棘海胆: 攒够反伤给的盾 4 秒 ────────────────────────────────
func _g6_thorn_015() -> void:
	print("--- ⑥ 015 荆棘海胆(反伤攒满给盾) ---")
	var u: Dictionary = _mk("left", Vector2(-160, 160), 5000.0)
	var foe: Dictionary = _mk("right", Vector2(160, 160))
	u["equips"] = [{"id": "p2eq_015", "star": 1}]     # ★1: 阈值 300, 反伤 12%
	_s._units.clear()
	_s._units.append_array([u, foe])
	_s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_015", 1)
	_s._equip_sys._stats._eq_apply_flags(u, "p2eq_015", 1)
	## 挨三发 1000 ⇒ 反伤 3×120 = 360 ≥ 阈值 300 ⇒ 触发一次给盾
	for _i in range(3):
		_s._equip_sys._eq_on_target(u, foe, 1000)
	_ok("⑥ ★分母: 攒过阈值并真的给了盾", float(u["shield"]) > 1.0,
		"盾 %.1f" % float(u["shield"]))
	_ok("⑥ ★★那份盾 4 秒", absf(_dur_of(u) - SPEC_SEC) < 0.05,
		"剩余 %.3f 秒" % _dur_of(u))


# ── ⑦ 反面样本: 013 文案写了自己的时长 ⇒ 不许被扫成 4 秒 ────────────────
func _g7_urchin_013_is_special() -> void:
	print("--- ⑦ 反面: 013 炙烤海胆是【特殊护盾】 ---")
	## 用户原话:「**特殊护盾有特殊说明啊**」。013 文案写着「该护盾在 10 秒内逐渐衰减」,
	## 实装是每帧按 URCHIN_DECAY 线性扣(RealtimeBattle3DScene 的海胆衰减那一行),
	## **不该**走通用 4 秒过期 —— 否则第 4 秒直接归零, 和文案说的"逐渐衰减"对不上。
	## ★这条是这次改动的【边界】: 证明我改的是"文案没写时长的", 不是一刀切全扫。
	var u: Dictionary = _mk("left", Vector2(-160, 200), 5000.0)
	u["equips"] = [{"id": "p2eq_013", "star": 3}]
	u["eq_state"] = {"p2eq_013": {}}
	_s._units.clear()
	_s._units.append(u)
	_s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_013", 3)
	_s._equip_sys._stats._eq_apply_flags(u, "p2eq_013", 3)   # ★ harden_cap/harden_inc 靠这一步写进 eq_state
	var cap: int = int(_s._equip_sys.URCHIN_CAP)
	_ok("⑦ ★分母: 013 的衰减时长是文案写的 10 秒(不是 4)",
		absf(float(_s._equip_sys.URCHIN_DECAY) - 10.0) < 0.001,
		"URCHIN_DECAY=%.1f" % float(_s._equip_sys.URCHIN_DECAY))
	## 叠满硬化层 → 触发海胆护盾
	for _i in range(cap + 1):
		_s._equip_sys._eq_on_target(u, u, 10)
	_ok("⑦ ★分母: 叠满 %d 层后拿到海胆护盾" % cap, float(u["shield"]) > 1.0,
		"盾 %.1f" % float(u["shield"]))
	_ok("⑦ ★★013 **不**走通用 4 秒到期(shield_until 必须是 0 = 交给自己的衰减机制)",
		absf(float(u.get("shield_until", -1.0))) < 0.001,
		"shield_until=%.3f" % float(u.get("shield_until", -1.0)))
