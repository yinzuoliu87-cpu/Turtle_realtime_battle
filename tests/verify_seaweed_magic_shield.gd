extends Node
## verify_seaweed_magic_shield.gd — 012 海藻重做(2026-10-08): 魔抗 + 登场魔法护盾 + 周期护盾分星
##
## 用户原话:「海草提供的生命值改为90/180/300，不再提供护甲，改为提供7/16/23魔抗。
##   效果为登场时获得相当于25/40/60%最大生命值的魔法护盾（只能挡魔法伤害）。
##   此外每四秒获得40/60/90+3/4/5.5%最大生命值护盾」
## 方案书: docs/plans/20261008-海藻重做.md
##
## 判据走真入口: 登场 / 周期都走 `_tick_jelly`(主场景每帧 tick 调的那个), 伤害走两条真伤害路径
##   (`_apply_damage_from` 普攻/技能、`_apply_damage` DoT), 血条走 `HpBar.update_state`,
##   面板走 `_info_status_chips` + `_status_sig_own`。
## ★期望值写需求字面量, 不引用被测常量。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
const HpBarScript := preload("res://scripts/scenes/hp_bar.gd")

const WANT_HP := [90, 180, 300]
const WANT_MR := [7, 16, 23]
const WANT_MS_PCT := [0.25, 0.40, 0.60]
const WANT_FLAT := [40.0, 60.0, 90.0]
const WANT_PCT := [0.03, 0.04, 0.055]
const MAXHP := 10000.0

var _n := 0
var _fail := 0
var s
var ip
var tk
var c: Vector2


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append(str((n as Label).text))
	for ch in n.get_children():
		_texts(ch, out)


func _chips(u: Dictionary) -> String:
	var vb := VBoxContainer.new()
	add_child(vb)
	ip._info_status_chips(vb, u)
	var arr: Array = []
	_texts(vb, arr)
	vb.queue_free()
	return " | ".join(PackedStringArray(arr))


## 干净合成单位: 不暴击、不闪避、零双抗、没盾没加成, 最大生命 10000
func _clean(id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos)
	u["maxHp"] = MAXHP; u["hp"] = MAXHP
	u["crit"] = 0.0; u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["heal_amp"] = 0.0; u["shield_amp"] = 0.0
	u["dodge"] = 0.0
	s._units.append(u)
	return u


func _carrier(star: int) -> Dictionary:
	var u := _clean("basic", "left", c)
	u["equips"] = [{"id": "p2eq_012", "star": star}]
	u["eq_state"] = {}
	s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_012", star)
	s._equip_sys._stats._eq_apply_flags(u, "p2eq_012", star)
	u["maxHp"] = MAXHP; u["hp"] = MAXHP
	## 伤害数学要干净: 双抗清零(012 给的魔抗另由 ① 验)
	u["def"] = 0.0; u["mr"] = 0.0; u["base_def"] = 0.0; u["base_mr"] = 0.0
	return u


func _hit(src: Dictionary, u: Dictionary, dmg: int, dtype: String) -> void:
	if dtype == "true":
		s._damage._apply_damage_from(src, u, dmg, Color.WHITE, 0.0, true, false, true, true)
	else:
		s._damage.set_dtype(dtype, u, false, true)
		s._damage._apply_damage_from(src, u, dmg, Color.WHITE, 0.0, false, false, true, true)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 012 海藻: 魔抗 / 登场魔法护盾 / 周期护盾 ===")
	RB.DEBUG_EDIT = true
	s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	c = s.ARENA.position + s.ARENA.size * 0.5
	ip = InfoPanel.new(s)
	tk = s._equip_tick_sys
	s._units.clear()
	s._edit_mode = false
	s._over = false
	s._copy_fx_mult = 1.0

	_g1_stats()
	_g2_spawn_amount()
	_g3_absorb_paths()
	_g4_periodic()
	_g5_display_and_text()

	print("--- %d 条, 失败 %d ---" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


func _edef() -> Dictionary:
	for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/phase2-equipment.json")):
		if e is Dictionary and str(e.get("id", "")) == "p2eq_012":
			return e
	return {}


## ① 属性: 生命 90/180/300、魔抗 7/16/23、不再给护甲
func _g1_stats() -> void:
	print("-- ① 属性 --")
	var rows: Array = EquipStats.STATS.get("p2eq_012", [])
	_ok("★分母: STATS 里 012 有三档", rows.size() == 3, str(rows.size()))
	for i in range(mini(3, rows.size())):
		var r: Dictionary = rows[i]
		_ok("%d★ hp=%d mr=%d 且没有护甲" % [i + 1, WANT_HP[i], WANT_MR[i]],
			int(r.get("hp", -1)) == WANT_HP[i] and int(r.get("mr", -1)) == WANT_MR[i] and not r.has("def"), str(r))
	_ok("展示镜像 baseStats1", str(_edef().get("baseStats1", "")) == "+生命90/180/300·魔抗7/16/23", str(_edef().get("baseStats1", "")))
	## 真入口施加: 魔抗真的加到单位上
	s._units.clear()
	var u := _clean("basic", "left", c)
	var mr0: float = float(u.get("base_mr", 0.0))
	var def0: float = float(u.get("base_def", 0.0))
	u["equips"] = [{"id": "p2eq_012", "star": 3}]
	u["eq_state"] = {}
	s._equip_sys._stats._eq_apply_one_stats(u, "p2eq_012", 3)
	_ok("★3★ 施加后 base_mr +23", absf(float(u.get("base_mr", 0.0)) - mr0 - 23.0) < 0.01, "%.1f → %.1f" % [mr0, float(u.get("base_mr", 0.0))])
	_ok("★3★ 施加后护甲不变", absf(float(u.get("base_def", 0.0)) - def0) < 0.01, "%.1f → %.1f" % [def0, float(u.get("base_def", 0.0))])


## ② 登场魔法护盾: 25/40/60% 最大生命 × 护盾强度; 只给一次; 新单位(换路重建)再给
func _g2_spawn_amount() -> void:
	print("-- ② 登场魔法护盾 --")
	for i in range(3):
		s._units.clear()
		var u := _carrier(i + 1)
		_ok("★分母: %d★ 登场前没有魔法护盾" % (i + 1), float(u.get("magic_shield", 0.0)) == 0.0)
		tk._tick_jelly(u, 0.016)
		var want: float = MAXHP * WANT_MS_PCT[i]
		_ok("★★%d★ 登场魔法护盾 = %.0f" % [i + 1, want], absf(float(u.get("magic_shield", 0.0)) - want) < 0.5, "%.1f" % float(u.get("magic_shield", 0.0)))
		_ok("%d★ 魔法护盾不进普通护盾" % (i + 1), float(u.get("shield", 0.0)) < 0.01, "%.1f" % float(u.get("shield", 0.0)))
	s._units.clear()
	var u2 := _carrier(1)
	tk._tick_jelly(u2, 0.016)
	u2["magic_shield"] = 100.0
	tk._tick_jelly(u2, 0.016)
	tk._tick_jelly(u2, 0.016)
	_ok("★★同一路只给一次(后续 tick 不补)", absf(float(u2["magic_shield"]) - 100.0) < 0.01, "%.1f" % float(u2["magic_shield"]))
	## 换路 = 单位字典整体重建 ⇒ 新字典第一次 tick 再给
	s._units.clear()
	var u3 := _carrier(1)
	tk._tick_jelly(u3, 0.016)
	_ok("★新一路(新单位字典)再给一次", absf(float(u3.get("magic_shield", 0.0)) - MAXHP * 0.25) < 0.5, "%.1f" % float(u3.get("magic_shield", 0.0)))
	## 吃护盾强度: +20% ⇒ ×1.2; 015 反伤削弱生效时再 ×0.5
	s._units.clear()
	var u4 := _carrier(2)
	u4["shield_amp"] = 0.2
	tk._tick_jelly(u4, 0.016)
	_ok("★★护盾强度 +20%%: 40%% × 1.2 = %.0f" % (MAXHP * 0.4 * 1.2), absf(float(u4.get("magic_shield", 0.0)) - MAXHP * 0.4 * 1.2) < 0.5, "%.1f" % float(u4.get("magic_shield", 0.0)))
	s._units.clear()
	var u5 := _carrier(2)
	u5["shield_amp_cut"] = 0.5; u5["shield_amp_cut_until"] = s._t + 3.0
	tk._tick_jelly(u5, 0.016)
	_ok("★护盾强度被削到 50%% ⇒ 40%% × 0.5", absf(float(u5.get("magic_shield", 0.0)) - MAXHP * 0.4 * 0.5) < 0.5, "%.1f" % float(u5.get("magic_shield", 0.0)))
	## 两件海藻 ⇒ 两份
	s._units.clear()
	var u6 := _carrier(1)
	u6["equips"] = [{"id": "p2eq_012", "star": 1}, {"id": "p2eq_012", "star": 1}]
	tk._tick_jelly(u6, 0.016)
	_ok("两件海藻各给一份", absf(float(u6.get("magic_shield", 0.0)) - MAXHP * 0.5) < 0.5, "%.1f" % float(u6.get("magic_shield", 0.0)))


## ③ 吸收: 只挡魔法(两条伤害路径都挡), 先于普通护盾; 物理与真实伤害绕过
func _g3_absorb_paths() -> void:
	print("-- ③ 吸收 --")
	s._units.clear()
	## ★攻击方不用 basic: 小龟「不屈」对任何伤害按目标稀有度增伤, 会让数字不干净
	var a := _clean("stone", "right", c + Vector2(60, 0))
	a["crit"] = 0.0
	var u := _carrier(1)
	## 物理: 魔法护盾不动, 普通护盾先扛
	u["magic_shield"] = 500.0; u["shield"] = 300.0
	_hit(a, u, 200, "physical")
	_ok("★★物理伤害不碰魔法护盾", absf(float(u["magic_shield"]) - 500.0) < 0.01, "%.1f" % float(u["magic_shield"]))
	_ok("★分母: 物理伤害由普通护盾扛了 200", absf(float(u["shield"]) - 100.0) < 0.5, "%.1f" % float(u["shield"]))
	## 真实: 同样绕过
	u["magic_shield"] = 500.0; u["shield"] = 0.0; u["hp"] = MAXHP
	_hit(a, u, 200, "true")
	_ok("★★真实伤害不碰魔法护盾", absf(float(u["magic_shield"]) - 500.0) < 0.01, "%.1f" % float(u["magic_shield"]))
	_ok("★分母: 真实伤害打到了生命", float(u["hp"]) < MAXHP - 150.0, "%.0f" % float(u["hp"]))
	## 魔法(普攻/技能路): 先扣魔法护盾, 普通护盾不动
	u["magic_shield"] = 500.0; u["shield"] = 300.0; u["hp"] = MAXHP
	_hit(a, u, 200, "magic")
	_ok("★★魔法伤害(技能路)先扣魔法护盾 500→300", absf(float(u["magic_shield"]) - 300.0) < 0.5, "%.1f" % float(u["magic_shield"]))
	_ok("★★魔法伤害被魔法护盾挡住时普通护盾不动", absf(float(u["shield"]) - 300.0) < 0.01, "%.1f" % float(u["shield"]))
	_ok("魔法伤害被挡住时生命不掉", absf(float(u["hp"]) - MAXHP) < 0.01, "%.0f" % float(u["hp"]))
	## 溢出: 魔法护盾 100, 打 250 ⇒ 魔法护盾归零, 余 150 由普通护盾扛
	u["magic_shield"] = 100.0; u["shield"] = 300.0; u["hp"] = MAXHP
	_hit(a, u, 250, "magic")
	_ok("★★溢出: 魔法护盾打空", float(u["magic_shield"]) < 0.01, "%.1f" % float(u["magic_shield"]))
	_ok("★★溢出: 余下 150 由普通护盾接", absf(float(u["shield"]) - 150.0) < 0.5, "%.1f" % float(u["shield"]))
	## DoT 路(_apply_damage, bucket=mag): 一样先扣魔法护盾
	u["magic_shield"] = 500.0; u["shield"] = 0.0; u["hp"] = MAXHP
	s._damage._apply_damage(u, 120, Color.WHITE, a, "mag")
	_ok("★★魔法 DoT(另一条伤害路)也扣魔法护盾 500→380", absf(float(u["magic_shield"]) - 380.0) < 0.5, "%.1f" % float(u["magic_shield"]))
	_ok("魔法 DoT 被挡住时生命不掉", absf(float(u["hp"]) - MAXHP) < 0.01, "%.0f" % float(u["hp"]))
	s._damage._apply_damage(u, 120, Color.WHITE, a, "phy")
	_ok("★★物理 DoT 不碰魔法护盾", absf(float(u["magic_shield"]) - 380.0) < 0.5, "%.1f" % float(u["magic_shield"]))


## ④ 周期护盾: 每 4 秒 40/60/90 + 3/4/5.5% 最大生命(普通护盾)
func _g4_periodic() -> void:
	print("-- ④ 周期护盾 --")
	for i in range(3):
		s._units.clear()
		var u := _carrier(i + 1)
		tk._tick_jelly(u, 0.016)   # 登场那一下(给魔法护盾)
		u["shield"] = 0.0
		tk._tick_jelly(u, 3.9)
		_ok("★分母: %d★ 未到 4 秒不给" % (i + 1), float(u["shield"]) < 0.01, "%.1f" % float(u["shield"]))
		tk._tick_jelly(u, 0.2)
		var want: float = WANT_FLAT[i] + MAXHP * WANT_PCT[i]
		_ok("★★%d★ 每 4 秒护盾 = %.0f" % [i + 1, want], absf(float(u["shield"]) - want) < 0.5, "%.1f" % float(u["shield"]))


## ⑤ 血条 / 面板 / 状态表 / 图标 / 文案
func _g5_display_and_text() -> void:
	print("-- ⑤ 显示 / 文案 --")
	s._units.clear()
	var u := _carrier(3)
	var bar = HpBarScript.new()
	add_child(bar)
	bar.setup(true, false)
	bar.update_state(u)
	var bm0: float = float(bar._bm)
	tk._tick_jelly(u, 0.016)
	u["hp"] = MAXHP * 0.5
	bar.update_state(u)
	_ok("★★血条读到魔法护盾量", absf(float(bar._magic) - float(u["magic_shield"])) < 0.5, "%.1f vs %.1f" % [float(bar._magic), float(u["magic_shield"])])
	_ok("★血条分母含魔法护盾(半血 + 60%% 魔法护盾 = 110%%)", absf(float(bar._bm) - MAXHP * 1.1) < 1.0, "%.0f (满血时 %.0f)" % [float(bar._bm), bm0])
	_ok("★魔法护盾段颜色与普通护盾段不同", bar._MAGIC_L != bar._SHIELD_L and bar._MAGIC_L != bar._MANA_L)
	bar.queue_free()
	var t1 := _chips(u)
	_ok("★★面板状态签「魔法护盾 N」", t1.find("魔法护盾 %d" % int(u["magic_shield"])) >= 0, t1)
	var sig0: String = ip._status_sig_own(u)
	u["magic_shield"] = float(u["magic_shield"]) - 100.0
	_ok("★面板签名随魔法护盾数值变化", ip._status_sig_own(u) != sig0)
	u["magic_shield"] = 0.0
	_ok("魔法护盾打空后不显示签", _chips(u).find("魔法护盾") < 0, _chips(u))
	_ok("★★新图标存在且能加载", ResourceLoader.exists("res://assets/sprites/status/magic-shield-icon.png")
		and load("res://assets/sprites/status/magic-shield-icon.png") is Texture2D)
	var found := false
	for st in DataRegistry.status_defs:
		if str(st.get("id", "")) == "magic-shield" and str(st.get("name", "")) == "魔法护盾" and str(st.get("category", "")) == "buff":
			found = true
	_ok("★状态表(图鉴状态页)有「魔法护盾」增益", found)
	var full: String = SkillText.equip_full(_edef())
	var brief: String = SkillText.equip_brief(_edef())
	_ok("★文案详细: 登场 25/40/60% 魔法护盾", full.find("登场时获得自身最大生命值 25/40/60% 的魔法护盾") >= 0, full)
	_ok("★文案详细: 每 4 秒 40/60/90+3/4/5.5%", full.find("每 4 秒获得（40/60/90+自身最大生命值 3/4/5.5%）点护盾") >= 0, full)
	_ok("★文案简述含百分比部分", brief.find("40/60/90+自身最大生命值 3/4/5.5%") >= 0 and brief.find("自身最大生命值 25/40/60%") >= 0, brief)
	_ok("★文案没有残留占位符", full.find("{C:") < 0 and brief.find("{C:") < 0)
