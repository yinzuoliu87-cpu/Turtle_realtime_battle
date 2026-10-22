extends Node
## verify_axe_evo_show.gd — 小木斧进化演出(方案书 docs/plans/20261022-小木斧进化演出.md §6)
##
## 用户 2026-10-22「小木斧需要设计进化动画吧」「补到进背包时吧」。
##   ① 时间轴(纯函数 state_at): 旧形态原色 → 白剪影 → 新旧交替越换越快 → 闪光 → 硬切新形态 → 名字晚出 → 收起
##   ② a 路: 商店里真点「购买」差 1 点就进化的小木斧 ⇒ 当场播新档名; 不进待播队列
##   ②b 不能跳过(用户 2026-10-22「点一下就跳过？不行」): 点了还在播, 播完自己收起; 播的时候遮罩挡住货架
##      还没补放的(结算攒的)排在前面一起播, 顺序是 1→2 再 2→3
##   ③ b/c 路: 结算 / 击杀走 axe_add_exp 跨档 ⇒ 入队; 进背包补放一次、队列清空; 再进背包不重播
##   ④ d 路: 四选一真点「余烬」⇒ 播最终造物那一段
##   ⑤ 演出开着时宿主 _rebuild 不会把它清掉(商店 / 背包都是买完、点完立刻整页重建)
## ★走真入口: 货架 / 按钮 / 遮罩全部派真的鼠标按下 + 松开(Viewport.push_input)。
## ★force_anim: 测试模式默认瞬播(不拖门禁), 要看画面的那几段打开它按真时长播。
##
## 跑法: bash godot-quiet.sh res://tests/verify_axe_evo_show.tscn --quit-after 3000

const SHOP := preload("res://scenes/Shop.tscn")
const INV := preload("res://scenes/Inventory.tscn")
const SHOW := preload("res://scripts/scenes/shop/axe_evo_show.gd")
const SHOP_GD := preload("res://scripts/scenes/ShopScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

const MIN_ASSERTS := 40

var _fail := 0
var _n := 0
var gs


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)


func _click(p: Vector2) -> void:
	_ev(p, true)
	await get_tree().process_frame
	_ev(p, false)
	await _frames(6)


func _dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


func _live(root: Node, nm: String) -> Control:
	if root == null:
		return null
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not _dying(c):
			return c
	return null


## 屏上的演出层(没在删的那一个)。
func _layer(sc: Node) -> CanvasLayer:
	for c in sc.get_children():
		if c is CanvasLayer and str(c.name).begins_with(SHOW.NODE_NAME) and not _dying(c):
			return c
	return null


func _layer_text(sc: Node, nm: String) -> String:
	var ly := _layer(sc)
	if ly == null:
		return ""
	var l = ly.find_child(nm, true, false)
	return str(l.text) if l is Label else ""


func _seed() -> void:
	gs.test_mode = true
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_xp = 0
	gs.season_total_battles = 3
	gs.meta_shop_locked = false
	gs.meta_shop_offer = []
	gs.meta_shop_battles = -1
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.axe_exp_bar = 0
	gs.axe_exp_total = 0
	gs.axe_stage = 0
	gs.axe_final = ""
	gs.axe_evo_pending = []
	gs.equip_pool = {}


func _shelf(ids: Array) -> void:
	var out: Array = []
	for i in range(10):
		out.append({"id": str(ids[i % ids.size()])})
	gs.meta_shop_offer = out
	gs.meta_shop_battles = int(gs.season_total_battles)


func _enter_shop(force_anim: bool) -> Control:
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)
	var sc: Control = SHOP.instantiate()
	sc._axe_evo.force_anim = force_anim
	add_child(sc)
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sc.position = Vector2.ZERO
	sc.size = Vector2(1280, 720)
	await _frames(3)
	sc._rebuild()
	await _frames(4)
	return sc


func _leave(sc: Node) -> void:
	remove_child(sc)
	sc.free()
	await _frames(1)


## 真点货架第 i 格 → 真点卡里的「购买」。返回是否点到了购买。
func _buy_slot(sc: Node, i: int) -> bool:
	var cell := _live(sc, "ShelfItem%d" % i)
	if cell == null:
		return false
	await _click(cell.get_global_rect().get_center())
	var bb := _live(_live(sc, "InspectCard"), "BuyBtn")
	if bb == null or (bb as Button).disabled:
		return false
	await _click(bb.get_global_rect().get_center())
	return true


## 把正在播的这一段推到播完: 走它自己那条 tween, 用 custom_step 一次推完(不靠墙钟 —— CLAUDE.md §3.5)。
func _finish(ev) -> void:
	if ev._tw != null and ev._tw.is_valid():
		ev._tw.custom_step(SHOW.total(true) + 1.0)
	await _frames(2)


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	print("=== 小木斧进化演出 ===")
	var bak := {
		"bar": int(gs.axe_exp_bar), "tot": int(gs.axe_exp_total), "st": int(gs.axe_stage),
		"fin": str(gs.axe_final), "pend": (gs.axe_evo_pending as Array).duplicate(true),
		"bench": gs.persistent_bench.duplicate(true), "coins": int(gs.meta_deepsea_coins),
	}
	_t_timeline()
	await _t_shop_buy()
	await _t_shop_buy_order()
	await _t_instant()
	await _t_backpack()
	await _t_final_pick()
	gs.axe_exp_bar = int(bak["bar"]); gs.axe_exp_total = int(bak["tot"]); gs.axe_stage = int(bak["st"])
	gs.axe_final = str(bak["fin"]); gs.axe_evo_pending = bak["pend"]
	gs.persistent_bench = bak["bench"]; gs.meta_deepsea_coins = int(bak["coins"])
	_ok("分母: 断言条数 %d ≥ %d(协程没半路断)" % [_n, MIN_ASSERTS], _n >= MIN_ASSERTS)
	print("ALL PASS — 小木斧进化演出" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 时间轴: 逐毫秒采样纯函数。
func _t_timeline() -> void:
	print("\n-- ① 时间轴 --")
	for final in [false, true]:
		var tag := "最终造物" if final else "普通进化"
		var tot: float = SHOW.total(final)
		var cut: float = SHOW.t_cut(final)
		var lo := 3.0 if final else 1.8
		var hi := 4.5 if final else 2.6
		_ok("%s 总长 %.2f 秒落在 [%.1f, %.1f](参考: 反复发生的短、一大轮一次的长)" % [tag, tot, lo, hi], tot >= lo and tot <= hi)
		var s_old: Dictionary = SHOW.state_at(SHOW.T_DIM + SHOW.T_OLD * 0.5, final)
		_ok("%s 开场先给旧形态原色" % tag, str(s_old["form"]) == "old" and float(s_old["white"]) == 0.0, str(s_old))
		var s_sil: Dictionary = SHOW.state_at(SHOW.T_DIM + SHOW.T_OLD + SHOW.T_SIL * 0.5, final)
		_ok("%s 然后旧形态变白剪影" % tag, str(s_sil["form"]) == "old" and float(s_sil["white"]) == 1.0, str(s_sil))
		## 剪影交替: 逐毫秒数形态切换次数与每次停留时长
		var prev := ""
		var last_t := 0.0
		var holds: Array = []
		var flips := 0
		var samples := 0
		var t := SHOW.T_DIM + SHOW.T_OLD + SHOW.T_SIL
		while t < cut - 0.0005:
			var st: Dictionary = SHOW.state_at(t, final)
			samples += 1
			if float(st["white"]) != 1.0:
				break
			var f := str(st["form"])
			if prev != "" and f != prev:
				flips += 1
				holds.append(t - last_t)
				last_t = t
			elif prev == "":
				last_t = t
			prev = f
			t += 0.001
		_ok("%s 分母: 交替段采了 %d 个点" % [tag, samples], samples > 500)
		_ok("★%s 新旧白剪影交替 %d 次(≥ 8)" % [tag, flips], flips >= 8, str(holds))
		_ok("★%s 越换越快: 第一次停留 %.3f > 最后一次 %.3f 秒" % [tag, float(holds[0]) if holds.size() > 0 else 0.0, float(holds[-1]) if holds.size() > 0 else 0.0],
			holds.size() >= 2 and float(holds[0]) > float(holds[-1]) * 2.0)
		_ok("%s 交替最后停在新形态上(闪光盖住的是新形态)" % tag, prev == "new")
		var s_pre: Dictionary = SHOW.state_at(cut - 0.01, final)
		_ok("%s 换图前闪光已经亮起来(盖住换图)" % tag, float(s_pre["flash"]) > 0.3, str(s_pre["flash"]))
		var s_cut: Dictionary = SHOW.state_at(cut + 0.001, final)
		_ok("★%s 换图那一刻: 新形态原色(剪影撤掉) + 闪光峰值 + 粒子炸开" % tag,
			str(s_cut["form"]) == "new" and float(s_cut["white"]) == 0.0 and float(s_cut["flash"]) > 0.7 and float(s_cut["burst"]) >= 0.0, str(s_cut))
		_ok("%s 名字晚出: 换图后 0.1 秒还没有" % tag, float(SHOW.state_at(cut + 0.1, final)["name_a"]) == 0.0)
		_ok("%s 名字晚出: 换图后 0.5 秒已经全显" % tag, float(SHOW.state_at(cut + 0.5, final)["name_a"]) == 1.0)
		_ok("%s 揭晓后新形态在动(待机帧号会变)" % tag, int(SHOW.state_at(cut + 0.05, final)["idle"]) != int(SHOW.state_at(cut + 0.5, final)["idle"]))
		_ok("%s 收尾淡出" % tag, float(SHOW.state_at(tot - 0.01, final)["alpha"]) < 0.1)
	_ok("最终造物比普通进化长", SHOW.total(true) > SHOW.total(false) + 0.8)
	var miss: Array = []
	for k in AxeArt.FORMS:
		if not SHOW.TINT.has(k):
			miss.append(k)
	_ok("九个形态都有闪光主色(分母 %d)" % AxeArt.FORMS.size(), miss.is_empty(), str(miss))


## ② a 路: 商店真点「购买」, 差 1 点就进化。
func _t_shop_buy() -> void:
	print("\n-- ② 商店买到当场进化 --")
	_seed()
	gs.axe_exp_bar = int(AE.STAGES[1]["need"]) - 1
	gs.axe_exp_total = gs.axe_exp_bar
	_shelf(["p2eq_096", "p2eq_001", "p2eq_002"])
	var sc := await _enter_shop(true)
	_ok("分母: 进店时没有演出", _layer(sc) == null)
	var bought := await _buy_slot(sc, 0)
	_ok("分母: 真点到了小木斧的「购买」并成交(档位 0→%d)" % int(gs.axe_stage), bought and int(gs.axe_stage) == 1)
	_ok("★买到当场播: 演出层在屏上", _layer(sc) != null)
	_ok("★横幅是新档名「%s」" % str(AE.STAGES[1]["name"]), _layer_text(sc, "FormName") == str(AE.STAGES[1]["name"]), _layer_text(sc, "FormName"))
	_ok("副行写新售价", _layer_text(sc, "SubLine") == "售价 %d 费" % int(AE.STAGES[1]["cost"]), _layer_text(sc, "SubLine"))
	var k: String = sc._axe_evo.shown_key()
	_ok("画面上的斧头是新旧两个形态之一(%s)" % k, k == "wood" or k == "stone")
	_ok("★商店当场播的不进待播队列(否则进背包会再播一次)", (gs.axe_evo_pending as Array).is_empty(), str(gs.axe_evo_pending))
	sc._rebuild()
	await _frames(2)
	_ok("★演出开着时整页重建, 演出层还在", _layer(sc) != null)
	## 播的时候点货架另一格: 遮罩挡住。先等过「买完 0.4 秒不接货架点击」那道闸, 免得是那道闸挡住的(假绿)
	OS.delay_msec(SHOP_GD.BUY_TAP_GUARD_MS + 60)
	var sel0 := int(sc._sel)
	var cell1 := _live(sc, "ShelfItem1")
	if cell1 != null:
		await _click(cell1.get_global_rect().get_center())
	_ok("★播的时候点货架: 被遮罩挡住(不选中、不弹说明卡)", cell1 != null and int(sc._sel) == sel0 and _live(sc, "InspectCard") == null,
		"_sel %d→%d" % [sel0, int(sc._sel)])
	await _click(Vector2(640, 360))
	await _frames(2)
	_ok("★点一下【不】跳过(用户 10-22「点一下就跳过？不行」): 演出层还在", _layer(sc) != null)
	await _finish(sc._axe_evo)
	_ok("★播完自己收起", _layer(sc) == null)
	if cell1 != null:
		await _click(cell1.get_global_rect().get_center())
	_ok("分母: 演出收起后再点同一格, 能选中(证明上面挡住的是遮罩)", int(sc._sel) == 1, "_sel=%d" % int(sc._sel))
	_ok("分母: 一共播了 1 段", int(sc._axe_evo.played) == 1, str(sc._axe_evo.played))
	await _leave(sc)


## ② 续: 结算攒出来的还没补放, 这时商店里又买到进化 ⇒ 先播旧的那段, 再播这段。
func _t_shop_buy_order() -> void:
	print("\n-- ② 续 顺序: 先补旧的, 再播这一次 --")
	_seed()
	gs.axe_stage = 1
	gs.axe_exp_bar = int(AE.STAGES[2]["need"]) - 1
	gs.axe_exp_total = 200
	gs.axe_evo_pending = [{"from": 0, "to": 1}]
	gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]
	_shelf(["p2eq_096", "p2eq_001", "p2eq_002"])
	var sc := await _enter_shop(true)
	var bought := await _buy_slot(sc, 0)
	_ok("分母: 成交且进化到档 2", bought and int(gs.axe_stage) == 2, "stage=%d" % int(gs.axe_stage))
	_ok("★第一段是还没补放的「%s」" % str(AE.STAGES[1]["name"]), _layer_text(sc, "FormName") == str(AE.STAGES[1]["name"]), _layer_text(sc, "FormName"))
	await _click(Vector2(640, 360))
	await _frames(2)
	_ok("点一下不跳过: 还是第一段", _layer_text(sc, "FormName") == str(AE.STAGES[1]["name"]), _layer_text(sc, "FormName"))
	await _finish(sc._axe_evo)
	_ok("★第一段播完自动接第二段, 是这一次的「%s」" % str(AE.STAGES[2]["name"]), _layer_text(sc, "FormName") == str(AE.STAGES[2]["name"]), _layer_text(sc, "FormName"))
	_ok("待播队列已取空", (gs.axe_evo_pending as Array).is_empty(), str(gs.axe_evo_pending))
	await _finish(sc._axe_evo)
	_ok("两段都播完后演出层收起", _layer(sc) == null)
	await _leave(sc)


## 测试模式瞬播: 照样开播(计数涨), 但不挡门禁。
func _t_instant() -> void:
	print("\n-- 测试模式瞬播 --")
	_seed()
	gs.axe_exp_bar = int(AE.STAGES[1]["need"]) - 1
	_shelf(["p2eq_096", "p2eq_001", "p2eq_002"])
	var sc := await _enter_shop(false)
	var bought := await _buy_slot(sc, 0)
	_ok("分母: 成交且进化", bought and int(gs.axe_stage) == 1)
	_ok("瞬播: 开播了 1 段", int(sc._axe_evo.played) == 1, str(sc._axe_evo.played))
	_ok("瞬播: 几帧之内已经收起", _layer(sc) == null)
	await _leave(sc)


## ③ b/c 路: 结算 / 击杀的进化入队, 进背包补放一次。
func _t_backpack() -> void:
	print("\n-- ③ 结算 / 战斗里的进化 → 进背包补放 --")
	_seed()
	gs.axe_exp_bar = int(AE.STAGES[1]["need"]) - 1
	gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]
	var evo: bool = gs.axe_add_exp(AE.EXP_ON_MATCH)
	_ok("分母: 打完一局 +%d 跨档" % AE.EXP_ON_MATCH, evo and int(gs.axe_stage) == 1)
	_ok("★跨档入待播队列 {from 0, to 1}", (gs.axe_evo_pending as Array).size() == 1
		and int(gs.axe_evo_pending[0].get("from", -1)) == 0 and int(gs.axe_evo_pending[0].get("to", -1)) == 1, str(gs.axe_evo_pending))
	gs.axe_add_exp(1)
	_ok("没跨档的经验不入队", (gs.axe_evo_pending as Array).size() == 1)
	var inv: Control = INV.instantiate()
	inv._axe_evo.force_anim = true
	add_child(inv)
	await _frames(3)
	_ok("★进背包补放: 演出层在屏上", _layer(inv) != null)
	_ok("★横幅是「%s」" % str(AE.STAGES[1]["name"]), _layer_text(inv, "FormName") == str(AE.STAGES[1]["name"]), _layer_text(inv, "FormName"))
	_ok("★取走即清空待播队列", (gs.axe_evo_pending as Array).is_empty(), str(gs.axe_evo_pending))
	inv._rebuild()
	await _frames(2)
	_ok("★背包整页重建, 演出层还在", _layer(inv) != null)
	await _click(Vector2(640, 360))
	await _frames(2)
	_ok("点一下不跳过", _layer(inv) != null)
	await _finish(inv._axe_evo)
	_ok("播完自己收起", _layer(inv) == null)
	remove_child(inv); inv.free()
	await _frames(1)
	var inv2: Control = INV.instantiate()
	inv2._axe_evo.force_anim = true
	add_child(inv2)
	await _frames(3)
	_ok("★再进背包不重播", _layer(inv2) == null and int(inv2._axe_evo.played) == 0, str(inv2._axe_evo.played))
	remove_child(inv2); inv2.free()
	await _frames(1)


## ④ d 路: 四选一真点「余烬」。
func _t_final_pick() -> void:
	print("\n-- ④ 四选一 → 最终造物演出 --")
	_seed()
	_shelf(["p2eq_001", "p2eq_002", "p2eq_003"])
	gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]
	gs.axe_stage = AE.STAGES.size() - 1
	gs.axe_exp_bar = AE.FINAL_NEED
	gs.axe_exp_total = 900
	var sc := await _enter_shop(true)
	var pick: Button = null
	var card := _live(sc, "InspectCard")
	if card != null:
		for b in card.find_children("*", "Button", true, false):
			if str((b as Button).text) == "余烬" and (b as Control).is_visible_in_tree():
				pick = b
	_ok("分母: 进店自动弹出小木斧那张, 找得到「余烬」", pick != null)
	if pick != null:
		await _click(pick.get_global_rect().get_center())
	_ok("分母: 真选上了余烬", str(gs.axe_final) == "ember", str(gs.axe_final))
	_ok("★点下就播: 演出层在屏上", _layer(sc) != null)
	_ok("★横幅是「余烬」", _layer_text(sc, "FormName") == "余烬", _layer_text(sc, "FormName"))
	_ok("副行写「最终造物」", _layer_text(sc, "SubLine") == "最终造物", _layer_text(sc, "SubLine"))
	var k: String = sc._axe_evo.shown_key()
	_ok("画面上的斧头是钻石斧或余烬(%s)" % k, k == "diamond" or k == "ember")
	await _click(Vector2(640, 360))
	await _frames(2)
	_ok("点一下不跳过", _layer(sc) != null)
	await _finish(sc._axe_evo)
	_ok("播完自己收起", _layer(sc) == null)
	await _leave(sc)
