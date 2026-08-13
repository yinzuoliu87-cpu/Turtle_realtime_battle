extends Node
## verify_incense_stone_real.gd — 093 香火石【实测探针】(2026-08-14)
##
## ★由来: 用户实测「凤凰龟复活, 香火石, 攻速实时变化, 全都是问题」。
##   `docs/plans/20260813-香火羁绊.md` 标着**已完成**、验收清单齐全、当时全套绿。
##   ⇒ 先不猜, 走真入口打数值。今天已经证明"读源码"会读错三次。
##
## 判据全部落在【产品自己的账】上: 充能条 `_chg` / 刻痕 `_marks` / 携带者身上的增伤字段。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Inc := preload("res://scripts/systems/equip/incense_stone_system.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 093 香火石: 实测 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var inc = s._equip_sys._incense

	## ★★★把赛季池清零并【记下原值】—— 两个理由, 都是硬的:
	##   ① 不清零的话"已回写存档"是假绿: 上一轮跑测试留下的 2 道刻痕会让断言蒙混过关
	##      (我第一版就是这么绿的, 打印出 "起始 2" 才看见)。
	##   ② 测试**绝不许污染真存档**(用户明令)。收尾必须还原。
	var _save_m: int = int(GameState.incense_marks)
	var _save_c: int = int(GameState.incense_charge)
	GameState.incense_marks = 0
	GameState.incense_charge = 0

	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	u["atk"] = 100.0
	u["maxHp"] = 5000.0
	u["hp"] = 5000.0
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e["maxHp"] = 1.0e9
	e["hp"] = 1.0e9
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": Inc.EID, "star": 1}]
	u["eq_state"] = {Inc.EID: {}}
	s._equip_sys._stats._eq_apply_all_stats()

	# ── ① 登场链路: _b4_eq 守卫 + on_spawn 建账 ────────────────────────────
	_ok("★分母: 装上 093 后每帧 tick 的守卫被打开(_b4_eq)", bool(u.get("_b4_eq", false)),
		"_b4_eq=%s" % str(u.get("_b4_eq", false)))
	var stt0 = u.get("eq_state", {}).get(Inc.EID, null)
	_ok("★分母: on_spawn 建了账(有 dealt0 基线)",
		stt0 is Dictionary and (stt0 as Dictionary).has("dealt0"),
		"stt=%s" % str(stt0))

	# ── ② 携带者造成伤害 ⇒ 充能条真的涨吗 ───────────────────────────────
	##   ★用户 2026-08-13 定的口径:「刻痕充能我说的明明就是火石的携带者打得伤害」。
	##     所以判据是【携带者自己打出的伤害】进条, 不是全队。
	var chg0: int = int(inc._chg.get("left", 0))
	var need: int = Inc.PER_MARK
	# 打出正好 1 道刻痕所需的伤害(走真伤害入口, 不直接改 _st_dealt)
	s._damage._apply_damage_from(u, e, need, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	var chg1: int = int(inc._chg.get("left", 0))
	var mk1: int = inc.marks_of("left")
	_ok("★分母: 携带者的累计伤害账真的涨了(_st_dealt)", int(u.get("_st_dealt", 0)) >= need,
		"_st_dealt=%d(需 %d)" % [int(u.get("_st_dealt", 0)), need])
	_ok("★★打满 %d 伤害 ⇒ 刻下 1 道刻痕" % need, mk1 >= 1,
		"刻痕=%d 充能=%d→%d" % [mk1, chg0, chg1])

	# ── ③ 刻痕真的换成增伤了吗(装备 0.2%/道 + 羁绊 0.1%/道) ──────────────
	##   ★这是玩家唯一能感知的东西。只验"刻痕数涨了"守不住 ——
	##     数字涨了但没人读它, 就是"写进去了没人读"(我踩过一整天)。
	var amp: float = 0.0
	## ★字段名是 `damage_amp`(我第一版猜了四个名字全不对, 靠 _amp_keys 打印才看到)。
	##   0.3%/道 = 装备 0.2% + 羁绊 0.1%, 正是设计值。
	for k in ["damage_amp", "dmg_amp", "incense_amp"]:
		if u.has(k):
			amp = maxf(amp, float(u.get(k, 0.0)))
	_ok("★★刻痕换成了携带者身上的【增伤字段】(不是只有一个数字在涨)", amp > 0.0,
		"增伤=%.4f · 携带者字段里带 amp 的: %s" % [amp, str(_amp_keys(u))])

	# ── ④ 局内读数: 装备图标框有没有出口 ────────────────────────────────
	##   ★用户 2026-08-13 问过「香火石图标那里有放数字吗」。
	##     读数一律进装备图标框(PANEL_CHARGE / PANEL_COUNT), 不许自造头顶条。
	var ro := FileAccess.get_file_as_string("res://scripts/gamedata/equip_readouts.gd")
	_ok("★★093 在装备图标框的读数表里(局内看得到充能/刻痕)",
		ro.find("p2eq_093") >= 0, "equip_readouts 里%s p2eq_093" % ("有" if ro.find("p2eq_093") >= 0 else "★没有"))

	# ── ⑤ 两块石头共享同一条充能条(用户拍板 A) ──────────────────────────
	var u2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-200, 0))
	u2["atk"] = 100.0
	u2["equips"] = [{"id": Inc.EID, "star": 1}]
	u2["eq_state"] = {Inc.EID: {}}
	s._units.append(u2)
	s._equip_sys._stats._eq_apply_all_stats()
	var mk_before: int = inc.marks_of("left")
	s._damage._apply_damage_from(u2, e, need, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★第二块石头的携带者打伤害 ⇒ 灌进【同一条】共享条(刻痕继续涨)",
		inc.marks_of("left") > mk_before,
		"刻痕 %d → %d" % [mk_before, inc.marks_of("left")])

	# ── ⑥ 反面: 敌方(right)不该蹭到本方的刻痕 ───────────────────────────
	_ok("★反面: 敌方刻痕池独立且为 0(每场从 0 起)", inc.marks_of("right") == 0,
		"right=%d" % inc.marks_of("right"))

	# ── ⑦ 跨对局保留: 打完一把, 刻痕与充能要落进存档 ────────────────────────
	##   ★用户 2026-08-13 的原始场景就是这个:「玩家打了一把买了香火石打下一把都发生了什么」。
	##     方案书拍板: 刻痕【跟羁绊走】、存赛季池、`start_new_season()` 才清零。
	##   ★★这是最可能坏的一段 —— 前面六条都在【一场之内】, 而用户是【跨场】实测的。
	var gs_m0: int = 0                       # ★上面已清零, 这就是真起点
	var gs_c0: int = int(GameState.incense_charge)
	var live_m: int = inc.marks_of("left")
	_ok("★分母: 局内已经攒到 %d 道刻痕" % live_m, live_m >= 2, "刻痕=%d" % live_m)
	_ok("★★局内刻痕【已经回写存档】(从 0 起攒, 不是蒙上一轮的残留)",
		int(GameState.incense_marks) == live_m and live_m > 0,
		"存档 %d(局内 %d) · 起始 %d" % [int(GameState.incense_marks), live_m, gs_m0])
	_ok("★★不满一道的余额也回写(否则每场的零头都丢)",
		int(GameState.incense_charge) != gs_c0 or int(inc._chg.get("left", 0)) == gs_c0,
		"存档充能 %d(局内 %d) · 起始 %d" % [int(GameState.incense_charge), int(inc._chg.get("left", 0)), gs_c0])

	## ★还原真存档 —— 不还原就是拿测试改玩家数据(用户明令: 演示/测试不许写真存档)。
	GameState.incense_marks = _save_m
	GameState.incense_charge = _save_c
	_ok("★收尾: 真存档已还原(刻痕 %d / 充能 %d)" % [_save_m, _save_c],
		int(GameState.incense_marks) == _save_m and int(GameState.incense_charge) == _save_c)

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 093 香火石")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


func _amp_keys(u: Dictionary) -> Array:
	var out: Array = []
	for k in u.keys():
		var ks := str(k)
		if ks.find("amp") >= 0 or ks.find("bonus") >= 0 or ks.find("incense") >= 0:
			out.append("%s=%s" % [ks, str(u[k])])
	return out
