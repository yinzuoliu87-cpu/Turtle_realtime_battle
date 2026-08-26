extends Node
## verify_accum_lane_scope.gd — 累积类余额(068 法力充能 / 070 灰条)的【重置口径】(2026-08-25)
##
## 补 `docs/plans/20260804-新装备35件效果.md` 那条「累积类以场重置还是以路重置」。
##
## ★★★用户 2026-08-26 拍板:**「清零」** —— 换路把六件的累积余额全部归零。
##   本文件从"锁住现状等拍板"升级为"锁住已拍板的口径"。判据不变(现状就是清零), 但性质变了:
##   以前红了要先问用户, 现在红了就是**回归**。
##
## ★拍板前查清的两件事(方案书那行原本是错的):
##   · **是 6 件不是 4 件**: 064 溺者的浮囊 / 068 深海气压罐 / 070 压舱咸鱼砖
##     / 071 炼乳罐 / 072 铁皮蛋糕盒 / 087 盗令潜水钟。
##     方案书列的 091/092 **根本没有累积余额**(091 周期回血、092 召唤物)。
##   · **六件里只有两件真有分歧**: 064/071/087 的**玩家文案里本来就写着"每路"**,
##     072 是用户 2026-08-05 亲口定的 ⇒ 从没定过的只有 068 充能条与 070 灰血条。
##
## ★以下是拍板前的调查记录, 保留:
##   · 方案书(2026-08-04)那行提议「→ 与羁绊同口径(以场 = 跨路保留)」
##   · 实际代码(2026-08-06 统一接线, `dual_lane_flow.gd:492`)是
##     `battle._spec.clear_all()  # 换路: 所有特殊余额(幽灵/法力/灰条/奶油/终极盾)归零`
##     —— **以路归零**, 而且紧邻的 493 行注着「这就是用户定的『每路一次』口径」。
##   实现把两类分开了, 看着是有意的:
##     · **进度类**(羁绊的战利品攻击力 / 远古之力增伤 / 食物成长) = 以场, 跨路保留(v0.19.11)
##     · **战斗内资源**(怒气 / 腐蚀 / 法力 / 灰条 / 血线阈值) = 每路归零
##   ⚠ 这条差异已写进方案书**摆给用户确认**; 若用户要改成"以场", 那是**行为改动**,
##     本文件的期望值要跟着改 —— 所以判据写成常量 WANT_LANE_RESET, 一处即可翻转。
##
## ★为什么值得有这条门禁: 换路归零这件事**全仓零断言**(2026-08-25 查过)。
##   `verify_b4_lane_leak` 守的是召唤物/光环, 不碰 `_spec`;
##   068/070 自己的测试守的是"释放后清零""转化后剩 95%"这些**局内**行为, 不是换路。
##   ⇒ 谁把 `_spec.clear_all()` 那一行删掉, 现在没有任何东西会红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_accum_lane_scope.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 换路归零 —— **用户 2026-08-26 拍板的口径**。留成常量是为了"要翻只翻一处",
## 不是"还没定"。真要改回以场保留才动它(那是行为改动, 要重新拍板)。
const WANT_LANE_RESET := true

const K_MANA := "p2eq_068_mana"    # 068 深海气压罐的法力护盾余额
const K_GREY := "p2eq_070_grey"    # 070 压舱咸鱼砖的灰色血条

## ★★六件全部纳入 —— 原来只验 068/070 两件, 而 `_spec.clear_all()` 管的是六件:
##   谁哪天把某一件从 clear_all 里漏掉, 只验两件的门禁**看不见**。
##   键名从各自的产品常量抄过来会漂 ⇒ 这里写成一张表并在下面**逐条断言它真的被清了**。
const ALL_KEYS := {
	"p2eq_064_ghost":   "064 溺者的浮囊·幽灵盾",
	"p2eq_068_mana":    "068 深海气压罐·法力充能",
	"p2eq_070_grey":    "070 压舱咸鱼砖·灰色血条",
	"p2eq_071_cream":   "071 炼乳罐·奶油盾",
	"p2eq_072_ult":     "072 铁皮蛋糕盒·终极盾",
	"p2eq_087_ballast": "087 盗令潜水钟·压载舱",
}

var _n := 0
var _fail := 0
var _s = null
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 累积类余额的换路口径 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var lead: Array = _gs.season_leaders if _gs.season_leaders is Array else []
	var id0: String = str(lead[0]) if lead.size() > 0 else "stone"
	var id1: String = str(lead[1]) if lead.size() > 1 else "basic"
	var id2: String = str(lead[2]) if lead.size() > 2 else "diamond"
	var eqs := [{"id": "p2eq_068", "star": 2}, {"id": "p2eq_070", "star": 2}]
	_gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": id0, "slot": 0, "equips": eqs.duplicate(true)},
			{"kind": "leader", "id": id1, "slot": 1},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": id2, "slot": 2, "equips": eqs.duplicate(true)},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "back"},
		],
	}

	_gs.current_lane = "top"
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	var u0 = _carrier()
	_ok("★分母: 上路生成了带 068/070 的龟", u0 != null)
	if u0 == null:
		_done()
		return

	## 直接往产品自己的余额账上记 —— 这两件的攒法各有各的入口(受伤/普攻),
	## 而本文件要验的是【换路那一下】, 不是攒法本身(攒法各自的测试已经在守)。
	## ★★六件【全部】攒上, 不只 068/070 —— `_spec.clear_all()` 管的是六件,
	##   只喂两件的话"谁把某一件从 clear_all 里漏掉"这种回归**看不见**。
	##   每件喂一个**互不相同**的数, 免得串了也看不出来。
	var amt := 0.0
	var before := {}
	for k in ALL_KEYS.keys():
		amt += 137.0                      # 137/274/411… 各不相同且不是倍数关系
		_s._spec.grant(u0, str(k), amt)
		before[k] = _s._spec.val(u0, str(k))
	var n_up := 0
	for k in ALL_KEYS.keys():
		if float(before[k]) > 0.0:
			n_up += 1
	_ok("★★分母: 换路前【六件】余额都真的攒起来了(%d/%d)" % [n_up, ALL_KEYS.size()],
		n_up == ALL_KEYS.size(),
		"实得 %s" % str(before))
	var m0: float = _s._spec.val(u0, K_MANA)
	var g0: float = _s._spec.val(u0, K_GREY)

	# ── 真换路: 清场 + 重建 ──
	_s._dl_sys._dl_clear_units()
	_gs.current_lane = "bottom"
	_s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	var u1 = _carrier()
	_ok("★分母: 下路也生成了带 068/070 的龟", u1 != null)
	if u1 == null:
		_done()
		return
	_ok("★★分母: 换路后是全新单位字典(is_same(旧,新) == false)", not is_same(u0, u1))

	var m1: float = _s._spec.val(u1, K_MANA)
	var g1: float = _s._spec.val(u1, K_GREY)
	if WANT_LANE_RESET:
		_ok("★★① 068 法力充能余额【换路归零】(%.0f → %.0f)" % [m0, m1],
			absf(m1) < 0.01, "实得 %.2f" % m1)
		_ok("★★① 070 灰条余额【换路归零】(%.0f → %.0f)" % [g0, g1],
			absf(g1) < 0.01, "实得 %.2f" % g1)
		## ★还要证明【旧那只身上的账也清了】—— 只看新单位的话, "新单位本来就是 0"
		##   会把"没清旧账"这种泄漏放过去(新旧是两个 key, 各记各的)。
		_ok("★★① 旧携带者身上的两笔账也一并清了",
			absf(_s._spec.val(u0, K_MANA)) < 0.01 and absf(_s._spec.val(u0, K_GREY)) < 0.01,
			"旧: 法力 %.2f 灰条 %.2f" % [_s._spec.val(u0, K_MANA), _s._spec.val(u0, K_GREY)])
		## ★★逐件断言 —— 用户 2026-08-26 拍板的口径覆盖的是【六件】,
		##   所以六件都要各红各的: 谁漏了哪一件, 报文里直接点名是哪一件。
		for k in ALL_KEYS.keys():
			var left_new: float = _s._spec.val(u1, str(k))
			var left_old: float = _s._spec.val(u0, str(k))
			_ok("★★① %s 换路归零(攒了 %.0f)" % [str(ALL_KEYS[k]), float(before[k])],
				absf(left_new) < 0.01 and absf(left_old) < 0.01,
				"新 %.2f / 旧 %.2f" % [left_new, left_old])
	else:
		_ok("★★① 068 法力充能【跨路保留】", absf(m1 - m0) < 0.01, "实得 %.2f" % m1)
		_ok("★★① 070 灰条【跨路保留】", absf(g1 - g0) < 0.01, "实得 %.2f" % g1)
		_ok("(以场口径下这条不适用)", true)
	_done()


func _carrier():
	for u in _s._units:
		if str(u.get("side", "")) != "left":
			continue
		for e in (u.get("equips", []) as Array):
			if str((e as Dictionary).get("id", "")) == "p2eq_068":
				return u
	return null


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 累积类换路口径" if _fail == 0 else "FAIL x%d — 累积类换路口径" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
