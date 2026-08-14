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
	##   ★★用户 2026-08-14 已拍板:**保留**。冲突到此结案, 这条从"待定"升为正式规则。
	_ok("★★用户 2026-08-14 拍板: 卖掉石头后充能【保留】(共享池的必然结果)",
		int(inc._chg.get("left", 0)) == 1500,
		"局内条=%d 存档=%d" % [int(inc._chg.get("left", 0)), int(GameState.incense_charge)])
	_ok("★★卖掉之后全队【仍吃到刻痕的加成】(刻痕跟羁绊走)",
		float(holder.get("damage_amp", 0.0)) > 0.0,
		"增伤=%.4f" % float(holder.get("damage_amp", 0.0)))

	# ── ⑬ 反面: 赛季重置【必须】把刻痕与充能一起清零 ────────────────────────
	##   ★用户 2026-08-14 拍板「卖掉充能保留」⇒ 唯一该清空它的就只剩赛季重置。
	##     没有这条反面, "永远保留"和"永远清不掉"在门禁眼里长得一模一样。
	##   ★全仓写 `incense_charge` 的只有 6 处: 登场读 / _persist_chg 写回 /
	##     每场一次性加载 / 存盘 / 读盘 / **赛季重置**。卖出路径一处都不碰 ⇒ 卖掉必然保留。
	var _gs := FileAccess.get_file_as_string("res://autoload/GameState.gd")
	var _n_reset := 0
	for ln in _gs.split("
"):
		if str(ln).strip_edges().begins_with("incense_charge = 0"):
			_n_reset += 1
	_ok("★★赛季重置处会把充能清零(共 %d 处), 且【只有】赛季重置会" % _n_reset,
		_n_reset == 2, "实得 %d 处(应 2: start_new_season 与另一处重置)" % _n_reset)
	_ok("★★卖出路径不碰 incense_charge(所以卖掉必然保留 —— 用户 2026-08-14 拍板)",
		_gs.find("sell") < 0 or _gs.count("incense_charge") <= 6,
		"GameState 里出现 %d 次" % _gs.count("incense_charge"))

	# ── ⑭ 满 300 刻痕封顶: 到顶后【不再涨】, 但增伤要停在顶值 ──────────────
	##   ★上限判定在写入侧(IncenseStoneSystem), `MARK_CAP = 300`。
	##     只验"到了 300"不够 —— 还要验**到顶之后继续打伤害不会溢出**。
	inc.clear_all()
	inc._loaded = {"left": false, "right": false}
	inc._marks["left"] = 0
	inc._chg["left"] = 0
	GameState.incense_marks = Inc.MARK_CAP        # 已经满了
	GameState.incense_charge = 0
	s._units.clear()
	var cap_u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-150, 0))
	cap_u["atk"] = 100.0
	cap_u["equips"] = [{"id": Inc.EID, "star": 1}]
	cap_u["eq_state"] = {Inc.EID: {}}
	s._units.append_array([cap_u, e])
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★分母: 刻痕已在上限 %d" % Inc.MARK_CAP, inc.marks_of("left") == Inc.MARK_CAP,
		"刻痕=%d" % inc.marks_of("left"))
	## 满刻痕时携带者增伤 = 300 × (ITEM_AMP + TEAM_AMP) —— 从常量推导, 不写死
	var cap_expect: float = float(Inc.MARK_CAP) * (Inc.ITEM_AMP + Inc.TEAM_AMP)
	_ok("★★满刻痕增伤 = %d × (%.3f + %.3f) = %.2f%%" % [Inc.MARK_CAP, Inc.ITEM_AMP, Inc.TEAM_AMP, cap_expect * 100.0],
		absf(float(cap_u.get("damage_amp", 0.0)) - cap_expect) < 1e-4,
		"实得 %.4f(应 %.4f)" % [float(cap_u.get("damage_amp", 0.0)), cap_expect])
	# 到顶后继续打 3 道份的伤害 ⇒ 不许溢出
	s._damage._apply_damage_from(cap_u, e, Inc.PER_MARK * 3, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★到顶后继续打伤害【不再涨】(不溢出上限)", inc.marks_of("left") == Inc.MARK_CAP,
		"刻痕=%d(应仍是 %d)" % [inc.marks_of("left"), Inc.MARK_CAP])
	_ok("★★增伤也停在顶值(没跟着溢出)",
		absf(float(cap_u.get("damage_amp", 0.0)) - cap_expect) < 1e-4,
		"实得 %.4f" % float(cap_u.get("damage_amp", 0.0)))

	# ── ⑮ 一帧打出多道刻痕: 要合成一次, 不是刷 N 条重叠飘字 ──────────────────
	##   ★代码注释说处理过(2026-08-09 实拍: 一次斩击 2 万伤害 ⇒ while 在同一帧转 5 圈),
	##     但**没有断言守着**。这里补上: 一次打 5 道份, 刻痕必须正好 +5。
	inc.clear_all()
	inc._loaded = {"left": false, "right": false}
	inc._marks["left"] = 0
	inc._chg["left"] = 0
	GameState.incense_marks = 0
	GameState.incense_charge = 0
	s._units.clear()
	var mf: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-150, 0))
	mf["atk"] = 100.0
	mf["equips"] = [{"id": Inc.EID, "star": 1}]
	mf["eq_state"] = {Inc.EID: {}}
	s._units.append_array([mf, e])
	s._equip_sys._stats._eq_apply_all_stats()
	s._damage._apply_damage_from(mf, e, Inc.PER_MARK * 5, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	## ★判据是【不变式】而不是"我以为打了多少": 刻痕 = 携带者累计伤害 ÷ PER_MARK。
	##   我第一版写死"应 +5", 实测 6 —— 因为 `_apply_damage_from` 会走暴击/增伤,
	##   实发伤害不等于我传进去的数。**先打分母再定判据**, 别拿输入当输出。
	var dealt: int = int(mf.get("_st_dealt", 0))
	var want_marks: int = int(dealt / Inc.PER_MARK)
	_ok("★分母: 这一发实际打出 %d 伤害(不是我传的 %d —— 走了暴击/增伤)" % [dealt, Inc.PER_MARK * 5],
		dealt > 0, "_st_dealt=%d" % dealt)
	_ok("★★一帧内多道刻痕【一次合成到位】: 刻痕 = 实发伤害 ÷ %d = %d" % [Inc.PER_MARK, want_marks],
		inc.marks_of("left") == want_marks, "刻痕=%d(应 %d)" % [inc.marks_of("left"), want_marks])
	_ok("★★这些刻痕也真的换成了增伤(%d × %.3f)" % [want_marks, Inc.ITEM_AMP + Inc.TEAM_AMP],
		absf(float(mf.get("damage_amp", 0.0)) - float(want_marks) * (Inc.ITEM_AMP + Inc.TEAM_AMP)) < 1e-4,
		"实得 %.4f(应 %.4f)" % [float(mf.get("damage_amp", 0.0)), float(want_marks) * (Inc.ITEM_AMP + Inc.TEAM_AMP)])

	# ── ⑯ 敌方也带石头: 两个池子不许串 ──────────────────────────────────────
	var foe: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(200, 0))
	foe["atk"] = 100.0
	foe["equips"] = [{"id": Inc.EID, "star": 1}]
	foe["eq_state"] = {Inc.EID: {}}
	s._units.append(foe)
	s._equip_sys._stats._eq_apply_all_stats()
	var my_before: int = inc.marks_of("left")
	var ally: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-260, 0))
	s._units.append(ally)
	s._damage._apply_damage_from(foe, ally, Inc.PER_MARK * 2, Color.RED, 0.0, true)
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★★敌方携带者打出伤害 ⇒ 只涨【敌方】的池", inc.marks_of("right") >= 2,
		"right=%d" % inc.marks_of("right"))
	_ok("★★本方的池【纹丝不动】(两侧不串)", inc.marks_of("left") == my_before,
		"left %d → %d" % [my_before, inc.marks_of("left")])
	_ok("★★敌方的刻痕【不许写进本方存档】(存档是本方赛季池)",
		int(GameState.incense_marks) == my_before,
		"存档=%d(本方局内 %d)" % [int(GameState.incense_marks), my_before])

	# ── ⑰ 图标读数【真的在更新】吗(不是只在配置表里有一行) ──────────────────
	##   ★用户 2026-08-13 问过「香火石图标那里有放数字吗」。
	##     前面只验了 `equip_readouts` 里有 p2eq_093 —— 那只证明**配好了**,
	##     不证明**数字会动**。装备格的层数徽章读 `eq_state[iid][key]`,
	##     所以真正要验的是: 刻痕/充能涨了之后, 那两个镜像字段跟着涨。
	##     (这正是"写进去了没人读"的镜像版: 配置指着一个永远不更新的字段。)
	var ro2 := FileAccess.get_file_as_string("res://scripts/gamedata/equip_readouts.gd")
	var cnt_key := "marks"      # PANEL_COUNT 里 093 指的字段
	var chg_key := "chg"        # PANEL_CHARGE 里 093 指的字段(分母 4000)
	_ok("★分母: 读数表把 093 指向 %s / %s" % [cnt_key, chg_key],
		ro2.find('"p2eq_093": "%s"' % cnt_key) >= 0 and ro2.find('"p2eq_093": ["%s"' % chg_key) >= 0)
	var mstt: Dictionary = mf.get("eq_state", {}).get(Inc.EID, {})
	_ok("★★层数徽章读的 `%s` 字段【跟着刻痕涨了】(不是永远 0)" % cnt_key,
		int(mstt.get(cnt_key, -1)) == inc.marks_of("left"),
		"stt[%s]=%d · 真实刻痕=%d" % [cnt_key, int(mstt.get(cnt_key, -1)), inc.marks_of("left")])
	_ok("★★充能条读的 `%s` 字段【跟着充能走】(不是停在登场那一刻)" % chg_key,
		int(mstt.get(chg_key, -1)) == int(inc._chg.get("left", 0)),
		"stt[%s]=%d · 真实充能=%d" % [chg_key, int(mstt.get(chg_key, -1)), int(inc._chg.get("left", 0))])

	# ── ⑱ 星级: 刻痕收益【不看星】(当前设计), 星只给基础属性 ──────────────────
	##   ★钉住现状: `on_spawn(u, eid, _si)` 的 `_si` 带下划线 = 明确不用;
	##     ITEM_AMP/TEAM_AMP 都是常量。哪天有人给星级加收益, 这条会红并逼他来改。
	inc.clear_all()
	inc._loaded = {"left": false, "right": false}
	inc._marks["left"] = 0
	inc._chg["left"] = 0
	GameState.incense_marks = 10
	GameState.incense_charge = 0
	s._units.clear()
	var s1: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-150, 0))
	s1["equips"] = [{"id": Inc.EID, "star": 1}]
	s1["eq_state"] = {Inc.EID: {}}
	var s3: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-210, 0))
	s3["equips"] = [{"id": Inc.EID, "star": 3}]
	s3["eq_state"] = {Inc.EID: {}}
	s._units.append_array([s1, s3, e])
	s._equip_sys._stats._eq_apply_all_stats()
	s._sim_step(1.0 / 60.0, false, false)
	_ok("★分母: 两只各带 ★1 / ★3, 场上 10 道刻痕", inc.marks_of("left") == 10,
		"刻痕=%d" % inc.marks_of("left"))
	## ★★先要求【非零】再比"一样" —— 两个都是 0 时"一样"恒成立, 那是假绿。
	##   (今天第三次栽在这个形状上: 0==0 / 空名单全通过 / 恒真观察句。)
	var a1: float = float(s1.get("damage_amp", 0.0))
	var a3: float = float(s3.get("damage_amp", 0.0))
	## ★★★双方同时有香火时, 两侧的登记表必须【各自独立】。
	##   2026-08-14 探针抓到的真 bug: `_given` 曾是一张全局表, `_reapply(side)` 开头的
	##   `_revoke()` 把两侧全撤掉再只重发自己这侧 ⇒ **后跑的一侧抹掉先跑那侧的加成**。
	##   实测当时: 左 10 道 / 右 2 道 ⇒ 左边两只 `damage_amp` 都是 0.0000, `_given.size()==1`。
	_ok("★★双方同侧登记表独立: 左侧发了 %d 份(场上左侧 %d 只)"
			% [(inc._given.get("left", []) as Array).size(), _count_side(s, "left")],
		(inc._given.get("left", []) as Array).size() == _count_side(s, "left"),
		"left 登记 %d / 存活 %d · right 登记 %d"
			% [(inc._given.get("left", []) as Array).size(), _count_side(s, "left"),
			   (inc._given.get("right", []) as Array).size()])
	_ok("★分母: 两只都真的拿到了刻痕增伤(非零)", a1 > 0.0 and a3 > 0.0,
		"★1=%.4f ★3=%.4f" % [a1, a3])
	_ok("★★★1 与 ★3 的刻痕增伤【一样】(当前设计: 刻痕收益不看星)",
		a1 > 0.0 and absf(a1 - a3) < 1e-6, "★1=%.4f ★3=%.4f" % [a1, a3])

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


func _count_side(s, side: String) -> int:
	var n := 0
	for o in s._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) == side:
			n += 1
	return n


func _amp_keys(u: Dictionary) -> Array:
	var out: Array = []
	for k in u.keys():
		var ks := str(k)
		if ks.find("amp") >= 0 or ks.find("bonus") >= 0 or ks.find("incense") >= 0:
			out.append("%s=%s" % [ks, str(u[k])])
	return out
