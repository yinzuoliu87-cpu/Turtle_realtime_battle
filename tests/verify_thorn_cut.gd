extends Node
## verify_thorn_cut.gd — 荆棘海胆 015 追加效果「反伤 → 3 秒治疗强度/护盾强度 -50%」(2026-10-07)
##
## 用户原话:「提供的生命值加强为180/350/1000，新效果为携带者的反伤会对目标施加持续3秒的50%治疗效果和护盾效果的削弱」
##         同日更正:「不不不，不要去掉旧效果」(累计反伤 → 护盾 + 强化普攻流血 原样保留)
##         同日:「没有护盾效果的属性吗」「有吧」⇒ 削的是【治疗强度 / 护盾强度】属性, 不另立状态
## 方案书: docs/plans/20261007-荆棘海胆重做.md
##
## 判据走真入口: 伤害走 `_apply_damage_from`(反伤由产品自己的两条反伤路径打出), 治疗走 `_heal`,
##   护盾走 `_grant_shield`, 面板读 `_info_stat_tiles` / `_info_stat_rows_minor`(面板真正画的那两张表)。
## ★期望值写需求字面量(3 秒 / 50% / 180·350·1000), 不引用被测常量 —— 否则恒真。
## ★时钟: DEBUG_EDIT 场景里 `_t` 不走, 由本测试手动推进(与机器快慢无关)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")

const WANT_SEC := 3.0
const WANT_CUT := 0.5
const WANT_HP := [180, 350, 1000]

var _n := 0
var _fail := 0
var s
var ip
var c: Vector2


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 干净合成单位: 不暴击、没盾、没减伤、没加成, 血量很厚(不会被打死)
func _clean(id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos)
	u["maxHp"] = 999999.0; u["hp"] = 999999.0
	u["crit"] = 0.0; u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["heal_amp"] = 0.0; u["shield_amp"] = 0.0
	u["dodge"] = 0.0
	s._units.append(u)
	return u


func _equip(u: Dictionary, iid: String, star: int) -> void:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	s._equip_sys._stats._eq_apply_one_stats(u, iid, star)
	s._equip_sys._stats._eq_apply_flags(u, iid, star)


## 量一次「受到 100 治疗实得多少 / 获得 100 护盾实得多少」, 量完把血/盾还原
func _heal_got(u: Dictionary) -> float:
	u["hp"] = float(u["maxHp"]) - 5000.0
	var h0: float = float(u["hp"])
	s._damage._heal(u, 100.0, true)
	var got: float = float(u["hp"]) - h0
	u["hp"] = float(u["maxHp"])
	return got


func _shield_got(u: Dictionary) -> float:
	u["shield"] = 0.0
	s._damage._grant_shield(u, 100.0)
	var got: float = float(u["shield"])
	u["shield"] = 0.0
	return got


func _hit(att: Dictionary, carrier: Dictionary, dmg: int = 1000) -> float:
	var a0: float = float(att["hp"])
	s._damage._apply_damage_from(att, carrier, dmg, Color.WHITE)
	var back: float = a0 - float(att["hp"])
	att["hp"] = float(att["maxHp"])
	carrier["hp"] = float(carrier["maxHp"])
	return back


## 面板两张表里「治疗强度 / 护盾强度」的显示值
func _tile(u: Dictionary, nm: String) -> String:
	for r in ip._info_stat_tiles(u):
		if str(r[1]) == nm:
			return str(r[2])
	return "<没有这一格>"


func _minor(u: Dictionary, nm: String) -> String:
	for r in ip._info_stat_rows_minor(u):
		if str(r[1]).begins_with(nm + " "):
			return str(r[1]).substr(nm.length() + 1)
	return "<没有这一行>"


func _ready() -> void:
	await get_tree().process_frame
	print("=== 荆棘海胆 015: 反伤 → 治疗强度/护盾强度 -50% ===")
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	c = s.ARENA.position + s.ARENA.size * 0.5
	ip = InfoPanel.new(s)
	s._units.clear()
	s._edit_mode = false
	s._over = false
	s._copy_fx_mult = 1.0

	_g1_stats()
	_g2_branch_path()
	_g3_expire_refresh_stack()
	_g4_generic_path()
	_g5_negative()
	_g6_panel_and_text()

	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


## ① 生命值 180/350/1000(事实源 EquipStats.STATS + 展示镜像 baseStats1)
func _g1_stats() -> void:
	print("-- ① 生命值 --")
	var rows: Array = EquipStats.STATS.get("p2eq_015", [])
	_ok("★分母: STATS 里 015 有三档", rows.size() == 3, str(rows.size()))
	for i in range(mini(3, rows.size())):
		_ok("%d★ hp == %d" % [i + 1, WANT_HP[i]], int(rows[i].get("hp", -1)) == WANT_HP[i], str(rows[i]))
	_ok("展示镜像 baseStats1 写 180/350/1000", str(_edef().get("baseStats1", "")).find("180/350/1000") >= 0, str(_edef().get("baseStats1", "")))


func _edef() -> Dictionary:
	for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/phase2-equipment.json")):
		if e is Dictionary and str(e.get("id", "")) == "p2eq_015":
			return e
	return {}


## ② 015 专属反伤分支: 攻击者 3 秒内治疗强度 / 护盾强度 ×0.5
func _g2_branch_path() -> void:
	print("-- ② 015 专属反伤 → 削弱 --")
	s._units.clear()
	var h := _clean("basic", "left", c)
	var a := _clean("basic", "right", c + Vector2(60, 0))
	_equip(h, "p2eq_015", 1)
	_ok("★分母: 攻击者起始 治疗实得 100", absf(_heal_got(a) - 100.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★分母: 攻击者起始 护盾实得 100", absf(_shield_got(a) - 100.0) < 0.01, "%.2f" % _shield_got(a))
	var t0: float = s._t
	var back := _hit(a, h)
	_ok("★分母: 015 真的反伤了", back > 0.0, "%.0f" % back)
	_ok("★分母: 旧效果仍在 —— 累计器 thorn_accum 记了这次反伤",
		float((h["eq_state"].get("p2eq_015", {}) as Dictionary).get("thorn_accum", 0.0)) > 0.0)
	_ok("★★受到 100 治疗 → 实得 50", absf(_heal_got(a) - 100.0 * (1.0 - WANT_CUT)) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★获得 100 护盾 → 实得 50", absf(_shield_got(a) - 100.0 * (1.0 - WANT_CUT)) < 0.01, "%.2f" % _shield_got(a))
	_ok("携带者自己不受削弱(治疗)", absf(_heal_got(h) - 100.0) < 0.01, "%.2f" % _heal_got(h))
	_ok("携带者自己不受削弱(护盾)", absf(_shield_got(h) - 100.0) < 0.01, "%.2f" % _shield_got(h))
	s._t = t0 + WANT_SEC - 0.05
	_ok("★★第 2.95 秒仍生效(治疗)", absf(_heal_got(a) - 50.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★第 2.95 秒仍生效(护盾)", absf(_shield_got(a) - 50.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = t0 + WANT_SEC + 0.05
	_ok("★★第 3.05 秒到期: 治疗恢复 100", absf(_heal_got(a) - 100.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★第 3.05 秒到期: 护盾恢复 100", absf(_shield_got(a) - 100.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = t0
	## 是对【属性】打折: 自带 +30% 治疗强度 / +20% 护盾强度的目标 → 130%×0.5 / 120%×0.5
	a["heal_amp"] = 0.3; a["shield_amp"] = 0.2
	_hit(a, h)
	_ok("★削的是治疗强度属性: +30% 的目标 → 实得 65", absf(_heal_got(a) - 65.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★削的是护盾强度属性: +20% 的目标 → 实得 60", absf(_shield_got(a) - 60.0) < 0.01, "%.2f" % _shield_got(a))
	## 与既有「治疗削减」是两回事: 两者同时在 → 各乘各的
	a["heal_amp"] = 0.0; a["shield_amp"] = 0.0
	a["heal_reduce_until"] = s._t + 10.0; a["heal_reduce_pct"] = 0.5
	_ok("★与治疗削减(50%)各算各的: 100 → 25", absf(_heal_got(a) - 25.0) < 0.01, "%.2f" % _heal_got(a))
	a["heal_reduce_until"] = 0.0; a["heal_reduce_pct"] = 0.0


## ③ 刷新 / 不叠加 / 过期旧幅度不粘住
func _g3_expire_refresh_stack() -> void:
	print("-- ③ 刷新 / 不叠加 --")
	s._units.clear()
	var h := _clean("basic", "left", c)
	var a := _clean("basic", "right", c + Vector2(60, 0))
	_equip(h, "p2eq_015", 3)
	var t0: float = s._t
	_hit(a, h)
	_hit(a, h)
	_hit(a, h)
	_ok("★★连中三次不叠加: 治疗仍实得 50(不是 12.5)", absf(_heal_got(a) - 50.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★连中三次不叠加: 护盾仍实得 50", absf(_shield_got(a) - 50.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = t0 + 2.0
	_hit(a, h)
	s._t = t0 + 3.5
	_ok("★★刷新: 第 2 秒再中一次 → 第 3.5 秒仍生效(治疗)", absf(_heal_got(a) - 50.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★刷新: 第 2 秒再中一次 → 第 3.5 秒仍生效(护盾)", absf(_shield_got(a) - 50.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = t0 + 5.05
	_ok("★★刷新后 3 秒到期: 治疗恢复 100", absf(_heal_got(a) - 100.0) < 0.01, "%.2f" % _heal_got(a))
	_ok("★★刷新后 3 秒到期: 护盾恢复 100", absf(_shield_got(a) - 100.0) < 0.01, "%.2f" % _shield_got(a))
	## 取最高 + 过期不粘: 先摆一份 80% 的削弱, 生效中再中 015 仍是 80%; 过期后再中只有 50%
	a["shield_amp_cut"] = 0.8; a["shield_amp_cut_until"] = s._t + 1.0
	_hit(a, h)
	_ok("★已有 80% 生效时取最高(仍 80%)", absf(_shield_got(a) - 20.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = s._t + 3.5
	_hit(a, h)
	_ok("★★旧的 80% 过期后再中 015 只有 50%(不被粘住)", absf(_shield_got(a) - 50.0) < 0.01, "%.2f" % _shield_got(a))
	s._t = t0


## ④ 通用反伤路径(石头龟坚壁)也触发 —— 专属分支的反伤比例清零以隔离
func _g4_generic_path() -> void:
	print("-- ④ 通用反伤路径(坚壁) --")
	s._units.clear()
	var st := _clean("stone", "left", c)
	var a := _clean("basic", "right", c + Vector2(60, 0))
	_equip(st, "p2eq_015", 1)
	(st["eq_state"]["p2eq_015"] as Dictionary)["reflect_pct"] = 0.0   # 专属分支不发 ⇒ 只剩坚壁那一发
	_ok("★分母: 坚壁反伤比例 > 0", StoneSystem.reflect_generic(st) > 0.0, "%.3f" % StoneSystem.reflect_generic(st))
	var back := _hit(a, st)
	_ok("★分母: 坚壁真的反伤了", back > 0.0, "%.0f" % back)
	_ok("★★坚壁的反伤也削护盾强度", absf(_shield_got(a) - 50.0) < 0.01, "%.2f" % _shield_got(a))
	_ok("★★坚壁的反伤也削治疗强度", absf(_heal_got(a) - 50.0) < 0.01, "%.2f" % _heal_got(a))


## ⑤ 没带 015 的反伤: 不触发
func _g5_negative() -> void:
	print("-- ⑤ 没带 015 --")
	s._units.clear()
	var st := _clean("stone", "left", c)
	var a := _clean("basic", "right", c + Vector2(60, 0))
	var back := _hit(a, st)
	_ok("★分母: 无装备石头龟坚壁真的反伤了", back > 0.0, "%.0f" % back)
	_ok("★★没带 015: 护盾不削", absf(_shield_got(a) - 100.0) < 0.01, "%.2f" % _shield_got(a))
	_ok("★★没带 015: 治疗不削", absf(_heal_got(a) - 100.0) < 0.01, "%.2f" % _heal_got(a))
	s._units.clear()
	var u13 := _clean("basic", "left", c)
	var b := _clean("basic", "right", c + Vector2(60, 0))
	_equip(u13, "p2eq_013", 3)
	var back13 := _hit(b, u13)
	_ok("★分母: 013 海胆壳真的反伤了", back13 > 0.0, "%.0f" % back13)
	_ok("★★013 反伤不削护盾强度", absf(_shield_got(b) - 100.0) < 0.01, "%.2f" % _shield_got(b))


## ⑥ 信息面板「治疗强度 / 护盾强度」显示此刻实际倍率 + 文案
func _g6_panel_and_text() -> void:
	print("-- ⑥ 面板 / 文案 --")
	s._units.clear()
	var h := _clean("basic", "left", c)
	var a := _clean("basic", "right", c + Vector2(60, 0))
	_equip(h, "p2eq_015", 1)
	var t0: float = s._t
	_ok("★分母: 中招前 网格「治疗强度」= 100%", _tile(a, "治疗强度") == "100%", _tile(a, "治疗强度"))
	_ok("★分母: 中招前 网格「护盾强度」= 100%", _tile(a, "护盾强度") == "100%", _tile(a, "护盾强度"))
	_hit(a, h)
	_ok("★★中招后 网格「治疗强度」= 50%", _tile(a, "治疗强度") == "50%", _tile(a, "治疗强度"))
	_ok("★★中招后 网格「护盾强度」= 50%", _tile(a, "护盾强度") == "50%", _tile(a, "护盾强度"))
	_ok("★★中招后 小字行「治疗强度」= 50%", _minor(a, "治疗强度") == "50%", _minor(a, "治疗强度"))
	_ok("★★中招后 小字行「护盾强度」= 50%", _minor(a, "护盾强度") == "50%", _minor(a, "护盾强度"))
	s._t = t0 + WANT_SEC + 0.05
	_ok("★到期后 网格两格回到 100%", _tile(a, "治疗强度") == "100%" and _tile(a, "护盾强度") == "100%",
		_tile(a, "治疗强度") + " / " + _tile(a, "护盾强度"))
	s._t = t0
	var full: String = SkillText.equip_full(_edef())
	var brief: String = SkillText.equip_brief(_edef())
	_ok("★文案: 详细写出「治疗强度与护盾强度降低 50%，持续 3 秒」", full.find("治疗强度与护盾强度降低 50%，持续 3 秒") >= 0, full)
	_ok("★文案: 旧效果仍写着(累计反伤 → 护盾 + 流血)", full.find("300/270/230") >= 0 and full.find("30/50/90 层流血") >= 0, full)
	_ok("★文案: 简述写出「治疗强度与护盾强度降低 50%，持续 3 秒」", brief.find("治疗强度与护盾强度降低 50%，持续 3 秒") >= 0, brief)
	_ok("★文案: 没有残留占位符", full.find("{C:") < 0 and brief.find("{C:") < 0)
