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

	# ── ⑧ 全队共享: 【没带石头】的队友也要吃到羁绊那一半 ─────────────────────
	##   ★设计: 每道刻痕 → 携带者 +0.2%/+0.1%(装备) + 全队 +0.1%/+0.05%(羁绊)。
	##     所以一个**空手队友**必须有增伤; 没有就等于羁绊那一半根本没发出去。
	##   ★这条是用户 2026-08-14 点名要我自己想到的粒度 —— 我原来只测了携带者。
	var mate: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-260, 0))
	mate["equips"] = []
	mate["eq_state"] = {}
	s._units.append(mate)
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	var mk_now: int = inc.marks_of("left")
	var mate_amp: float = float(mate.get("damage_amp", 0.0))
	var carry_amp: float = float(u.get("damage_amp", 0.0))
	_ok("★分母: 此刻本方 %d 道刻痕" % mk_now, mk_now > 0, "刻痕=%d" % mk_now)
	_ok("★★【没带石头的队友】也吃到羁绊那一半增伤(全队共享)", mate_amp > 0.0,
		"队友增伤=%.4f · 携带者=%.4f" % [mate_amp, carry_amp])
	_ok("★★携带者拿的比队友多(装备那一半是携带者独享)", carry_amp > mate_amp,
		"携带者 %.4f > 队友 %.4f" % [carry_amp, mate_amp])
	## 比例校验: 携带者 0.3%/道, 队友 0.1%/道 ⇒ 携带者应是队友的 3 倍
	_ok("★★比例对得上(携带者 0.3%/道 ÷ 队友 0.1%/道 = 3 倍)",
		mate_amp > 0.0 and absf(carry_amp / maxf(mate_amp, 1e-9) - 3.0) < 0.25,
		"实得 %.2f 倍" % (carry_amp / maxf(mate_amp, 1e-9)))

	# ── ⑨ 局内【继承上次的充能进度】—— 用户 2026-08-14 点名 ─────────────────
	##   ★用户 2026-08-13 拍板过:「到了第二路可能充能到了1000就1000继续啊」。
	##     所以新一场开打时, 条要从**存档里的余额**起步, 不是从 0。
	##   ★做法: 把赛季池设成一个"差一点就满一道"的值, 再让一只新龟登场, 看条从哪起。
	##   ⚠ 顺序很要命: `clear_all()` 内部会 `_persist_chg()` 把【局内的值】写回存档。
	##     我第一版先播种再 clear_all ⇒ 种子被自己覆盖, 报出一个**假 bug**(条=0 存档 3500)。
	##     必须 **先 clear_all, 再播种**。
	var inc2 = s._equip_sys._incense
	inc2.clear_all()                           # 模拟换场: 撤干净
	inc2._chg["left"] = 0
	inc2._marks["left"] = 0
	var SEED: int = Inc.PER_MARK - 500        # 差 500 就满一道
	GameState.incense_charge = SEED
	GameState.incense_marks = 7
	var v: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-320, 0))
	v["atk"] = 100.0
	v["equips"] = [{"id": Inc.EID, "star": 1}]
	v["eq_state"] = {Inc.EID: {}}
	s._units.append(v)
	s._equip_sys._stats._eq_apply_all_stats()
	_ok("★★新一场登场: 充能条【从存档余额起步】(不是从 0 重攒)",
		int(inc2._chg.get("left", 0)) == SEED,
		"条=%d(存档 %d)" % [int(inc2._chg.get("left", 0)), SEED])
	_ok("★★刻痕也一并继承(跨对局保留)",
		inc2.marks_of("left") == 7, "刻痕=%d(存档 7)" % inc2.marks_of("left"))
	## 再打 500 就该立刻刻一道 —— 证明"继承的余额是真能用的", 不是只做个显示
	s._damage._apply_damage_from(v, e, 500, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★继承来的余额【真能用】: 再打 500 立刻刻第 8 道(不是白显示)",
		inc2.marks_of("left") == 8, "刻痕=%d(应 8)" % inc2.marks_of("left"))

	# ── ⑩ 【中途才出现】的友军拿不拿得到? (用户 2026-08-14 追问"全队共享你确定") ──
	##   ★`_reapply` 只在两个时机跑: 刻了新痕 / 带石头的龟登场。
	##     ⇒ 战斗中途才生成的单位(召唤物·机甲·大熊·海螺虫)如果之后没再刻痕,
	##       就【永远拿不到】那一份全队增伤。我上面那条队友是靠 _eq_apply_all_stats
	##       顺带触发 on_spawn 才拿到的, 没隔离这个情形。
	var late: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-380, 0))
	late["equips"] = []
	late["eq_state"] = {}
	late["damage_amp"] = 0.0
	s._units.append(late)                       # ★只加进场, 不调 _eq_apply_all_stats
	s._sim_step(1.0 / 60.0, false, false)
	var late_amp0: float = float(late.get("damage_amp", 0.0))
	## ★★这条原来写成恒真(观察用)。修好之后必须变成真断言, 否则等于没测。
	##   修之前实测: 场上 8 道刻痕, 中途加入的友军增伤 **0.0000** —— 要等下一道刻痕才补。
	_ok("★★中途加入的友军【立刻】拿到全队增伤(不用等下一道刻痕)",
		late_amp0 > 0.0, "增伤=%.4f (刻痕 %d)" % [late_amp0, inc.marks_of("left")])
	## 面板显示: 小数值不许被 %d 抹成 0(用户 2026-08-14「增伤减伤显示那里不是 0 吗」)
	var ip := FileAccess.get_file_as_string("res://scripts/scenes/battle/info_panel.gd")
	_ok("★★属性面板的增伤/减伤【保留小数】(0.2% 不再显示成 0%)",
		ip.find("\"增伤 \" + _pct(") >= 0 and ip.find("\"减伤 \" + _pct(") >= 0)
	# 再刻一道 ⇒ _reapply 跑一次, 这时它必须补上
	s._damage._apply_damage_from(u, e, Inc.PER_MARK, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★刻了新痕之后, 中途加入的友军【补上了】全队增伤",
		float(late.get("damage_amp", 0.0)) > 0.0,
		"增伤 %.4f → %.4f" % [late_amp0, float(late.get("damage_amp", 0.0))])

	# ── ⑪ 【这一路没有携带者】时, 全队还拿不拿得到? ─────────────────────────
	##   ★★★用户 2026-08-14 实测:「攒了20刀也是0, 为什么上半有下半没有」。
	##     假说: `_reapply` 只有两个触发点 —— 刻新痕 / **带石头的龟登场**。
	##     石头若装在只打上路的龟身上, 下路没有携带者登场 ⇒ `_reapply` 一次都不跑
	##     ⇒ 下路全队 0, 攒多少道刻痕都没用。
	##   ★而香火是【羁绊】: 按 v0.19.138 羁绊按全阵容算、三个战场共享 ——
	##     所以下路本就该吃到全队那一份。
	inc.clear_all()
	inc._chg["left"] = 0
	inc._marks["left"] = 0
	inc._roster_n = {"left": -1, "right": -1}
	GameState.incense_marks = 20        # 存档里躺着 20 道
	GameState.incense_charge = 200      # ★还有 200 点没满一道的零头(用户举的例子)
	s._units.clear()
	# 下路阵容: 三只龟, 【一块石头都没有】(携带者留在上路)
	var lane2: Array = []
	for i in range(3):
		var w: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-150.0 - 60.0 * float(i), 0))
		w["equips"] = []
		w["eq_state"] = {}
		w["damage_amp"] = 0.0
		w["damage_reduction"] = 0.0
		lane2.append(w)
		s._units.append(w)
	s._units.append(e)
	s._equip_sys._stats._eq_apply_all_stats()
	for _f in range(10):
		s._sim_step(1.0 / 60.0, false, false)
	var w0: Dictionary = lane2[0]
	_ok("★分母: 存档里有 20 道刻痕, 但这一路没有任何携带者",
		int(GameState.incense_marks) == 20, "存档刻痕=%d" % int(GameState.incense_marks))
	_ok("★★★这一路没有携带者时, 全队仍拿到香火增伤(20 道 × 0.1% = 2%)",
		float(w0.get("damage_amp", 0.0)) > 0.0,
		"增伤=%.4f · 局内刻痕=%d" % [float(w0.get("damage_amp", 0.0)), inc.marks_of("left")])
	_ok("★★减伤那一半也要到位(20 道 × 0.05% = 1%)",
		float(w0.get("damage_reduction", 0.0)) > 0.0,
		"减伤=%.4f" % float(w0.get("damage_reduction", 0.0)))
	## ★★用户 2026-08-14 追问:「在上路战场应该从 200 充能开始而不是 0」——
	##   `_chg` 与 `_marks` 是同一个毛病: 只在 `on_spawn` 里从存档读。
	##   ⇒ 这一路没有携带者时充能条也是 0, 上一把剩的零头全丢。
	_ok("★★★充能条也要从存档余额起步(不是从 0)", int(inc._chg.get("left", 0)) == 200,
		"条=%d(存档 200)" % int(inc._chg.get("left", 0)))

	# ── ⑫ 卖掉石头之后(用户 2026-08-13 专门问过) ────────────────────────────
	##   ★方案书拍板:「只有充能会丢, 已投进羁绊的刻痕不退」。
	##     用户原话:「如果卖掉了就丢失这 20」(指没满一道的充能), 刻痕是已经兑现的收益。
	inc.clear_all()
	inc._loaded = {"left": false, "right": false}
	inc._marks["left"] = 0
	inc._chg["left"] = 0
	GameState.incense_marks = 12
	GameState.incense_charge = 1500     # 没满一道的零头
	s._units.clear()
	var holder: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-150, 0))
	holder["atk"] = 100.0
	holder["equips"] = [{"id": Inc.EID, "star": 1}]
	holder["eq_state"] = {Inc.EID: {}}
	s._units.append_array([holder, e])
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★分母: 带着石头时刻痕 12 / 充能 1500",
		inc.marks_of("left") == 12 and int(inc._chg.get("left", 0)) == 1500,
		"刻痕=%d 充能=%d" % [inc.marks_of("left"), int(inc._chg.get("left", 0))])
	# 卖掉: 把石头从身上摘下来, 再走一次换路
	holder["equips"] = []
	holder["eq_state"] = {}
	inc.clear_all()
	inc._marks["left"] = 0
	inc._chg["left"] = 0
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★卖掉石头后【刻痕不退】(已兑现的收益不收回)", inc.marks_of("left") == 12,
		"刻痕=%d(应 12)" % inc.marks_of("left"))
	## ⚠⚠【规则冲突·待用户拍板】卖掉之后充能保不保留, 用户给过两条相反的话:
	##   · 2026-08-06「如果卖掉了就丢失这 20」—— 那时充能存在【装备实例】上
	##   · 2026-08-13「羁绊里有多少刻痕和充能都是重新激活状态…就接着激活啊」
	##     +「两个火石一起叠充能, 共享充能条」—— 充能被搬到【羁绊池】
	##   后一条的必然结果: 共享池不该因为卖掉其中一块就清空(否则带两块的人卖一块,
	##   另一块的进度也跟着没了)。⇒ **当前实装跟随后一条**。
	##   ★这条断言钉住的是【当前规则】, 不是"验证过的正确"。用户改主意就来改这里。
	_ok("★当前规则: 卖掉石头后充能【保留】(2026-08-13 搬进羁绊共享池的必然结果)",
		int(inc._chg.get("left", 0)) == 1500,
		"局内条=%d 存档=%d ⚠ 与 2026-08-06「卖掉就丢失」冲突, 待拍板"
			% [int(inc._chg.get("left", 0)), int(GameState.incense_charge)])
	_ok("★★卖掉之后全队【仍吃到刻痕的加成】(刻痕跟羁绊走)",
		float(holder.get("damage_amp", 0.0)) > 0.0,
		"增伤=%.4f" % float(holder.get("damage_amp", 0.0)))

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
