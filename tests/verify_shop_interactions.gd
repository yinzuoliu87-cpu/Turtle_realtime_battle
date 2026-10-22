extends Node
## verify_shop_interactions.gd — 商店交互漏洞门禁(2026-10-22)
##
## 由来: 用户 2026-10-22「商店还有交互bug啊，买完一个东西，点了刷新后怎么自动选中一个物品？把所有漏洞给我找出来」。
##   逐个状态 × 逐个操作走了一遍(探针实测), 确认的漏洞一条一条焊在这里:
##   I1  买完再刷新 ⇒ 新货架同一格的货被自动选中、说明卡自己弹出来(用户报的那条)
##   I2  选着一件直接刷新 ⇒ 选中跳到新货架同一格的另一件
##   I3  双击「购买」⇒ 第二下点穿到卡下面那件货, 又自动选中了别的一件
##   I4  钱不够点压暗的「刷新」/ 满级或钱不够点「买经验」⇒ 一句话都没有(disabled 吞掉点击)
##   I5  钱不够时「买经验」亮着、旁边「刷新」暗着(同一排两种长相)
##   I6  小木斧待选最终造物: 买掉任意一件之后那张卡整个消失
##   I7  小木斧待选那张高 1224、四选一按钮落在屏幕外(y 1258)永远点不到; 盖住货架 6 格、点空白关不掉
##   I8  说明特别长的装备(084 卡高 733)卡底「购买」在屏幕外买不了; 超高卡被横挪后盖住被点的那件
##   I9  选着货点等级看概率 ⇒ 概率牌被说明卡盖住左半截; 点空白收不起概率牌
##   I10 说明卡开着按 ESC ⇒ 直接退出商店(应先收卡)
##   (2026-10-22 补) I7 四选一按钮一排四颗 88×44 · 15 号字(低于手机下限 81 / 20)⇒ 2×2 · 81 高 · 20 号字,
##       三种比例下小木斧自己那张、和卡底带「购买」的货卡里都量; I8 正文滚动条是 Godot 默认灰色圆角条 ⇒ 木框 / 黄铜皮
##
## ★走真入口: 货架 / 按钮 / 空白全部派真的鼠标按下 + 松开(`Viewport.push_input`, 走引擎自己的命中);
##   货架内容走产品自己的恢复路径(写 GameState.meta_shop_offer, 进店时 `_restore_offer` 读回), 不往场景里塞变量。
##   判据看【屏上】: 说明卡在不在、哪格带选中光、提示条说了什么、矩形在不在视口里。
## ★每条配分母: 先证明那一步真的发生了(真的选中了 / 真的买走了 / 真的换货了 / 第二下真的落在一件货上)。
##
## 跑法: bash godot-quiet.sh res://tests/verify_shop_interactions.tscn --quit-after 3000

const SHOP := preload("res://scenes/Shop.tscn")
const SHOP_GD := preload("res://scripts/scenes/ShopScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SBJ := preload("res://tests/_scrollbar_skin_judge.gd")
## 手机下限(与 verify_shop_inv_phone 同一口径: 可点区短边 81 = 44pt · 字 20 ≈ 11pt)。
## ★写在门禁这边、不读产品常量: 产品那边把下限改小了, 这里照样红。
const MIN_TAP := 81.0
const MIN_FONT := 20

## ★= 实测条数(2026-10-22: 85 → 补四选一下限 / 滚动条皮 / 正文整行之后 111)。少一条就红 —— 协程半路报错时 _ready 照样往下走、照样打 ALL PASS(本文件第一版就这样漏过一次)。
const MIN_ASSERTS := 111
## 说明最长的 10 件(2026-10-22 探针实测未封顶卡高: 084=733 072=673 068/069/080=643 034/040/059/087/096=613)。
##   ★只用来把「最难放」的卡摆满货架; 全 96 件另有一轮在 16:9 下逐件量。
## 加宽后说明卡仍要滚动的装备(只有小木斧: 四个形态 + 四个造物); 别的出现滚动条 ⇒ I8 红。
const SCROLL_OK := ["p2eq_096"]
const TALL := ["p2eq_084", "p2eq_072", "p2eq_068", "p2eq_069", "p2eq_080", "p2eq_034", "p2eq_040", "p2eq_059", "p2eq_087", "p2eq_096"]
## 说明最短的那几件(卡高 253~283): 卡短 ⇒ 卡底「购买」正好落在下层货架上 —— 双击点穿就发生在这里。
const SHORT := ["p2eq_054", "p2eq_002", "p2eq_018", "p2eq_035", "p2eq_046"]

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


# ══════════════════════════════ 真输入 ══════════════════════════════

func _ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)


## 一次点按: 按下 → 一帧 → 松开 → 等说明卡排完版(InspectCard 一帧 + _refit_card 两帧, 封顶时再一帧)。
func _click(p: Vector2) -> void:
	_ev(p, true)
	await get_tree().process_frame
	_ev(p, false)
	await _frames(6)


func _esc() -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	k.pressed = true
	get_viewport().push_input(k)
	await get_tree().process_frame
	k = k.duplicate()
	k.pressed = false
	get_viewport().push_input(k)
	await _frames(5)


# ══════════════════════════════ 屏上读数 ══════════════════════════════

## 活着的(没排队删除、整条祖先链都可见)同名控件。_rebuild 只 queue_free 旧节点, 同一帧里旧的还挂在树上。
func _live(root: Node, nm: String) -> Control:
	if root == null:
		return null
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not _dying(c):
			return c
	return null


func _dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


func _card(sc: Node) -> Control:
	return _live(sc, "InspectCard")


func _card_title(sc: Node) -> String:
	var c := _card(sc)
	if c == null:
		return ""
	var t = c.find_child("Title", true, false)
	return str(t.text) if t != null else "?"


## 带选中光(SelGlow)的货架格下标; 没有 = -1。
func _glow_slot(sc: Node) -> int:
	for i in range(10):
		var b := _live(sc, "ShelfItem%d" % i)
		if b != null and b.find_child("SelGlow", true, false) != null:
			return i
	return -1


func _slot_center(sc: Node, i: int) -> Vector2:
	var b := _live(sc, "ShelfItem%d" % i)
	return b.get_global_rect().get_center() if b != null else Vector2(-100, -100)


func _item_rect(sc: Node, i: int) -> Rect2:
	var b := _live(sc, "ShelfItem%d" % i)
	if b == null:
		return Rect2()
	var it = b.find_child("Item", true, false)
	return (it as Control).get_global_rect() if it is Control else Rect2()


## 屏上(可见、没在删)含 needle 的一行字。
func _screen_text(sc: Node, needle: String) -> String:
	for c in sc.find_children("*", "Label", true, false):
		var l := c as Label
		if l.is_visible_in_tree() and not _dying(l) and str(l.text).find(needle) >= 0:
			return str(l.text)
	return ""


func _offer_ids(sc: Node) -> Array:
	var out: Array = []
	for e in sc._offer:
		out.append("-" if e == null else str((e as Dictionary).get("id", "")))
	return out


func _sold(sc: Node) -> int:
	var k := 0
	for e in sc._offer:
		if e == null:
			k += 1
	return k


# ══════════════════════════════ 进店 ══════════════════════════════

func _seed(coins: int = 999) -> void:
	gs.test_mode = true
	gs.meta_deepsea_coins = coins
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
	gs.equip_pool = {}


## 把货架写成指定的 10 件(产品自己的恢复路径: 本场次的货架原样读回)。
func _shelf(ids: Array) -> void:
	var out: Array = []
	for i in range(10):
		out.append({"id": str(ids[i % ids.size()])})
	gs.meta_shop_offer = out
	gs.meta_shop_battles = int(gs.season_total_battles)


func _enter(vp: Vector2 = Vector2(1280, 720)) -> Control:
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(vp)
	await _frames(2)
	var sc: Control = SHOP.instantiate()
	add_child(sc)
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sc.position = Vector2.ZERO
	sc.size = vp
	await _frames(3)
	sc._rebuild()          # 按设好的尺寸重排一次(同 verify_shop_inv_phone)
	await _frames(4)
	return sc


func _leave(sc: Node) -> void:
	remove_child(sc)
	sc.free()
	await _frames(1)


## 买成之后货架有 0.4 秒不接受真点击(挡双击点穿)。墙钟过去而不推进帧: 帧预算与机器快慢无关。
func _wait_guard() -> void:
	OS.delay_msec(SHOP_GD.BUY_TAP_GUARD_MS + 60)


# ══════════════════════════════ 主流程 ══════════════════════════════

func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	print("=== 商店交互漏洞门禁 ===")
	await _i1_buy_then_refresh()
	await _i2_select_then_refresh()
	await _basic_transitions()
	await _i3_double_click_buy()
	await _i4_i5_dead_buttons()
	await _i6_i7_axe()
	await _i8_tall_cards()
	await _i9_odds()
	await _i10_esc()
	await _top_tabs()
	SafeArea.override_insets = Vector4(-1, -1, -1, -1)
	get_tree().root.size = Vector2i(1280, 720)
	print("")
	_ok("分母: 断言条数 %d ≥ %d(协程没半路断)" % [_n, MIN_ASSERTS], _n >= MIN_ASSERTS)
	print("  (用了 %d 帧)" % Engine.get_process_frames())
	print("ALL PASS — 商店交互" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## I1 —— 用户报的那条: 选一件 → 卡里点「购买」→ 点「刷新」。
func _i1_buy_then_refresh() -> void:
	print("\n-- I1 买完再刷新 --")
	_seed()
	var sc := await _enter()
	await _click(_slot_center(sc, 0))
	_ok("I1 分母: 真点第 0 格 → 说明卡弹出、第 0 格带选中光", _card(sc) != null and _glow_slot(sc) == 0,
		"卡=%s 光=%d" % [_card_title(sc), _glow_slot(sc)])
	var bb := _live(_card(sc), "BuyBtn") if _card(sc) != null else null
	_ok("I1 分母: 卡里有可点的「购买」", bb != null and not (bb as Button).disabled)
	var c0 := int(gs.meta_deepsea_coins)
	if bb != null:
		await _click(bb.get_global_rect().get_center())
	_ok("I1 分母: 真的买走了(第 0 格空、币少了)", sc._offer[0] == null and int(gs.meta_deepsea_coins) < c0,
		"币 %d→%d" % [c0, int(gs.meta_deepsea_coins)])
	_ok("I1 买完: 屏上没有说明卡、没有哪格带选中光", _card(sc) == null and _glow_slot(sc) == -1,
		"卡=%s 光=%d" % [_card_title(sc), _glow_slot(sc)])
	_ok("★I1 买完: 选中下标已清(不再指着那个空格)", int(sc._sel) == -1, "_sel=%d" % int(sc._sel))
	var ids0 := _offer_ids(sc)
	var c1 := int(gs.meta_deepsea_coins)
	await _click(_live(sc, "ShopRefreshBtn").get_global_rect().get_center())
	_ok("I1 分母: 真的刷新了(扣 %d、第 0 格长出新货)" % SHOP_GD.REFRESH_COST,
		int(gs.meta_deepsea_coins) == c1 - SHOP_GD.REFRESH_COST and sc._offer[0] != null and _offer_ids(sc) != ids0,
		"%s → %s" % [str(ids0.slice(0, 3)), str(_offer_ids(sc).slice(0, 3))])
	_ok("★★I1 刷新后: 没有任何一件被自动选中(无说明卡、无选中光)", _card(sc) == null and _glow_slot(sc) == -1,
		"卡=%s 光=%d" % [_card_title(sc), _glow_slot(sc)])
	await _leave(sc)


## I2 —— 选着一件直接刷新。
func _i2_select_then_refresh() -> void:
	print("\n-- I2 选着刷新 --")
	_seed()
	var sc := await _enter()
	await _click(_slot_center(sc, 3))
	var t0 := _card_title(sc)
	_ok("I2 分母: 选中第 3 格「%s」" % t0, _card(sc) != null and _glow_slot(sc) == 3)
	await _click(_live(sc, "ShopRefreshBtn").get_global_rect().get_center())
	_ok("I2 分母: 真的换了货", int(gs.meta_deepsea_coins) == 999 - SHOP_GD.REFRESH_COST)
	_ok("★I2 刷新后不选任何一件(原来选中跳到新货「%s」)" % _card_title(sc), _card(sc) == null and _glow_slot(sc) == -1,
		"卡=%s 光=%d" % [_card_title(sc), _glow_slot(sc)])
	await _leave(sc)


## 基本转换(都是对的, 当分母与回归守着): 点另一格 / 再点同一格 / 点空白 / 选着锁定 / 选着买经验。
func _basic_transitions() -> void:
	print("\n-- 基本转换 --")
	_seed()
	var sc := await _enter()
	await _click(_slot_center(sc, 4))
	await _click(_slot_center(sc, 0))
	_ok("点另一格 → 选中跟过去", _glow_slot(sc) == 0 and _card(sc) != null, "光=%d" % _glow_slot(sc))
	await _click(_slot_center(sc, 0))
	_ok("再点同一格 → 收起", _glow_slot(sc) == -1 and _card(sc) == null)
	await _click(_slot_center(sc, 4))
	await _click(Vector2(120, 660))   # 左下空地(店主脚边)
	_ok("点空白 → 收起", _glow_slot(sc) == -1 and _card(sc) == null)
	await _click(_slot_center(sc, 7))
	var t7 := _card_title(sc)
	await _click(_live(sc, "ShopLockBtn").get_global_rect().get_center())
	_ok("选着点锁定 → 锁上了、说明卡还是那件(锁不换货)", bool(gs.meta_shop_locked) and _card_title(sc) == t7 and _glow_slot(sc) == 7,
		"锁=%s 卡=%s" % [str(gs.meta_shop_locked), _card_title(sc)])
	var lv0 := int(gs.season_level)
	var xp0 := int(gs.season_xp)
	await _click(_live(sc, "ShopBuyXpBtn").get_global_rect().get_center())
	_ok("选着点买经验 → 经验涨了、说明卡还是那件", (int(gs.season_xp) != xp0 or int(gs.season_level) != lv0) and _card_title(sc) == t7,
		"Lv%d xp%d → Lv%d xp%d" % [lv0, xp0, int(gs.season_level), int(gs.season_xp)])
	## 买空整排货架 → 刷新 → 仍然什么都不选
	## ★先收起第 7 格那张卡: 它盖着第 0 格(卡盖住别的货是对的), 不收的话点第 0 格会被卡吃掉、买成第 7 格。
	await _click(Vector2(120, 660))
	for i in range(10):
		if sc._offer[i] == null:
			continue
		_wait_guard()
		await _click(_slot_center(sc, i))
		var bb := _live(_card(sc), "BuyBtn") if _card(sc) != null else null
		if bb != null and not (bb as Button).disabled:
			await _click(bb.get_global_rect().get_center())
	_ok("买空: 10 格全部买走", _sold(sc) == 10, "空 %d 格" % _sold(sc))
	_ok("买空: 屏上没有说明卡", _card(sc) == null)
	await _click(_live(sc, "ShopRefreshBtn").get_global_rect().get_center())
	_ok("买空后刷新: 货回来了、没有一件被自动选中", _sold(sc) == 0 and _card(sc) == null and _glow_slot(sc) == -1,
		"空 %d 格 卡=%s" % [_sold(sc), _card_title(sc)])
	await _leave(sc)
	## 合成触发后: 背包里先有 2 件 ★1, 买第 3 件 ⇒ ★2; 之后刷新也不自动选中
	_seed()
	_shelf(["p2eq_001", "p2eq_002", "p2eq_003", "p2eq_004", "p2eq_005"])
	gs.persistent_bench = [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_001", "star": 1}]
	sc = await _enter()
	await _click(_slot_center(sc, 0))
	var bm := _live(_card(sc), "BuyBtn") if _card(sc) != null else null
	if bm != null:
		await _click(bm.get_global_rect().get_center())
	var star2 := 0
	for it in gs.persistent_bench:
		if str((it as Dictionary).get("id", "")) == "p2eq_001" and int((it as Dictionary).get("star", 1)) == 2:
			star2 += 1
	_ok("合成 分母: 买第 3 件真的合成了 ★2", star2 == 1, "★2 件数 %d" % star2)
	_ok("合成 屏上那句「合成 ★2」看得见", _screen_text(sc, "合成") != "", _screen_text(sc, "合成"))
	await _click(_live(sc, "ShopRefreshBtn").get_global_rect().get_center())
	_ok("合成后刷新: 没有一件被自动选中", _card(sc) == null and _glow_slot(sc) == -1, "卡=%s" % _card_title(sc))
	await _leave(sc)


## I3 —— 双击「购买」: 卡短 ⇒ 卡底「购买」正好压在下层货架上, 第二下点穿。
func _i3_double_click_buy() -> void:
	print("\n-- I3 双击购买 --")
	var hits := 0
	for si in range(5):
		_seed()
		var ids: Array = []
		for k in range(10):
			ids.append(SHORT[(k + si) % SHORT.size()])
		_shelf(ids)
		var sc := await _enter()
		await _click(_slot_center(sc, si))
		var bb := _live(_card(sc), "BuyBtn") if _card(sc) != null else null
		if bb == null:
			_ok("I3 slot%d 分母: 卡里有「购买」" % si, false)
			await _leave(sc)
			continue
		var p := bb.get_global_rect().get_center()
		## 分母: 卡收起之后, 这个点下面真的是一件货(否则「没点穿」是因为下面本来就是空地)
		var under := -1
		for j in range(10):
			if j != si:
				var b := _live(sc, "ShelfItem%d" % j)
				if b != null and sc._offer[j] != null and b.get_global_rect().has_point(p):
					under = j
		if under >= 0:
			hits += 1
		_ev(p, true); await get_tree().process_frame; _ev(p, false); await get_tree().process_frame
		_ev(p, true); await get_tree().process_frame; _ev(p, false); await _frames(6)
		_ok("I3 slot%d 双击「购买」: 只买走 1 件" % si, _sold(sc) == 1, "空 %d 格" % _sold(sc))
		_ok("★I3 slot%d 双击「购买」: 第二下(落在第 %d 格上)没有选中别的货" % [si, under],
			_card(sc) == null and _glow_slot(sc) == -1, "卡=%s 光=%d" % [_card_title(sc), _glow_slot(sc)])
		if si == 0 and under >= 0:
			## 防连点只挡那一下: 过了 0.4 秒再点同一件, 照常选中
			_wait_guard()
			await _click(_slot_center(sc, under))
			_ok("I3 防连点不误伤: 过一会再点第 %d 格 → 照常选中" % under, _glow_slot(sc) == under and _card(sc) != null,
				"光=%d" % _glow_slot(sc))
		await _leave(sc)
	_ok("I3 分母: 至少 3 格的「购买」压在别的货上(这条判据真的量到了点穿的几何)", hits >= 3, "命中 %d / 5" % hits)


## I4 / I5 —— 压暗的按钮被真点到也要说一句; 买不起时两颗按钮一个长相。
func _i4_i5_dead_buttons() -> void:
	print("\n-- I4/I5 买不起 / 满级 --")
	_seed(1)
	var sc := await _enter()
	var rf := _live(sc, "ShopRefreshBtn") as Button
	var bx := _live(sc, "ShopBuyXpBtn") as Button
	_ok("I4 分母: 币 1 时「刷新」压暗(disabled 且 alpha<0.6)", rf != null and rf.disabled and rf.modulate.a < 0.6)
	var ids0 := _offer_ids(sc)
	await _click(rf.get_global_rect().get_center())
	var said := _screen_text(sc, "深海币不足")
	_ok("★I4 真点压暗的「刷新」→ 屏上说清要 %d 枚(「%s」)" % [SHOP_GD.REFRESH_COST, said],
		said.find(str(SHOP_GD.REFRESH_COST)) >= 0)
	_ok("I4 分母: 没换货、没扣钱", _offer_ids(sc) == ids0 and int(gs.meta_deepsea_coins) == 1)
	bx = _live(sc, "ShopBuyXpBtn") as Button
	_ok("★I5 币 1 时「买经验」也压暗(与「刷新」同一个长相, alpha %.2f)" % (bx.modulate.a if bx != null else -1.0),
		bx != null and bx.disabled and bx.modulate.a < 0.6)
	var xp0 := int(gs.season_xp)
	await _click(bx.get_global_rect().get_center())
	said = _screen_text(sc, "深海币不足")
	_ok("★I4 真点压暗的「买经验」→ 屏上说清要 %d 枚(「%s」)" % [int(P2.BUY_XP_COST), said],
		said.find(str(int(P2.BUY_XP_COST))) >= 0)
	_ok("I4 分母: 经验没涨、没扣钱", int(gs.season_xp) == xp0 and int(gs.meta_deepsea_coins) == 1)
	await _leave(sc)
	_seed(999)
	sc = await _enter()
	bx = _live(sc, "ShopBuyXpBtn") as Button
	rf = _live(sc, "ShopRefreshBtn") as Button
	_ok("I5 分母: 币够时两颗都是亮的、能点", bx != null and not bx.disabled and bx.modulate.a > 0.95
		and rf != null and not rf.disabled and rf.modulate.a > 0.95)
	await _leave(sc)
	_seed(999)
	gs.season_level = int(P2.MAX_LEVEL)
	sc = await _enter()
	bx = _live(sc, "ShopBuyXpBtn") as Button
	await _click(bx.get_global_rect().get_center())
	said = _screen_text(sc, "最高等级")
	_ok("★I4 满级真点「买经验」→ 屏上说「已达最高等级」(「%s」)" % said, said != "")
	_ok("I4 分母: 满级时它确实是压暗的", bx.disabled and bx.modulate.a < 0.6)
	await _leave(sc)


## 小木斧攒满待选最终造物的那一态。
func _axe_ready() -> void:
	_seed()
	_shelf(["p2eq_001", "p2eq_002", "p2eq_003", "p2eq_004", "p2eq_005", "p2eq_006", "p2eq_007", "p2eq_008", "p2eq_009", "p2eq_010"])
	gs.persistent_bench = [{"id": "p2eq_096", "star": 1}]
	gs.axe_stage = AE.STAGES.size() - 1
	gs.axe_exp_bar = AE.FINAL_NEED
	gs.axe_exp_total = 900
	gs.axe_final = ""


func _final_btns(sc: Node) -> Array:
	var out: Array = []
	var c := _card(sc)
	if c == null:
		return out
	for f in AE.FINALS:
		for b in c.find_children("*", "Button", true, false):
			if str((b as Button).text) == str((f as Dictionary)["name"]) and (b as Control).is_visible_in_tree():
				out.append(b)
	return out


## 四选一按钮的毛病; 没毛病返回 ""。
##   ① 短边 ≥ 81 ② 字 ≥ 20 ③ 字放得进按钮 ④ 2×2(两列两行) ⑤ 互不重叠、也不压 `others`(卡底「购买」)
## ★2026-10-22 由来: 原来一排四颗 88×44 · 15 号字, 而本门禁只量「在不在屏幕里」—— 在屏里的小按钮照样绿。
func _final_btns_bad(btns: Array, others: Array) -> String:
	var xs := {}
	var ys := {}
	for b in btns:
		var bt := b as Button
		var r := bt.get_global_rect()
		if minf(r.size.x, r.size.y) < MIN_TAP - 0.5:
			return "「%s」%.0f×%.0f 短边 < %.0f" % [bt.text, r.size.x, r.size.y, MIN_TAP]
		var fs := bt.get_theme_font_size("font_size")
		if fs < MIN_FONT:
			return "「%s」字 %d < %d" % [bt.text, fs, MIN_FONT]
		var f := bt.get_theme_font("font")
		var tw: float = f.get_string_size(bt.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x if f != null else 0.0
		var sbn := bt.get_theme_stylebox("normal")
		var pad: float = (sbn.get_margin(SIDE_LEFT) + sbn.get_margin(SIDE_RIGHT)) if sbn != null else 0.0
		if tw + pad > r.size.x + 0.5:
			return "「%s」字宽 %.0f + 内边距 %.0f 放不进 %.0f 宽的按钮" % [bt.text, tw, pad, r.size.x]
		xs[roundi(r.position.x)] = true
		ys[roundi(r.position.y)] = true
	if xs.size() != 2 or ys.size() != 2:
		return "不是 2×2(%d 列 × %d 行)" % [xs.size(), ys.size()]
	var all: Array = btns + others
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			var x: Rect2 = (all[i] as Control).get_global_rect().intersection((all[j] as Control).get_global_rect())
			if x.size.x >= 1.0 and x.size.y >= 1.0:
				return "「%s」压着「%s」(%.0f×%.0f)" % [str(all[i].text), str(all[j].text), x.size.x, x.size.y]
	return ""


## 一块里可见的、带字、字号 < 20 的标签; 第二项 = 量了几行(分母)。
func _small_text(root: Control) -> Array:
	var bad: Array = []
	var n := 0
	if root == null:
		return [bad, n]
	for c in root.find_children("*", "Label", true, false):
		var l := c as Label
		if not l.is_visible_in_tree() or str(l.text).strip_edges() == "":
			continue
		n += 1
		if l.get_theme_font_size("font_size") < MIN_FONT:
			bad.append("「%s」%d" % [str(l.text).left(10), l.get_theme_font_size("font_size")])
	return [bad, n]


## I6 / I7 —— 小木斧四选一。
func _i6_i7_axe() -> void:
	print("\n-- I6/I7 小木斧待选最终造物 --")
	for r in [{"n": "16:9", "vp": Vector2(1280, 720), "ins": Vector4(0, 0, 0, 0)},
			{"n": "19.5:9", "vp": Vector2(1560, 720), "ins": Vector4(111, 0, 111, 38)},
			{"n": "4:3", "vp": Vector2(1280, 960), "ins": Vector4(0, 0, 0, 25)}]:
		_axe_ready()
		## 货架摆说明最长的 10 件: 下面点第 4 格(080)时, 那张货卡是「正文封顶 + 四选一 + 购买」三样挤一张的最难情形
		_shelf(TALL)
		SafeArea.override_insets = r["ins"]
		var sc := await _enter(r["vp"])
		var vp: Vector2 = r["vp"]
		var safe := Rect2(Vector2(r["ins"].x, r["ins"].y), vp - Vector2(r["ins"].x + r["ins"].z, r["ins"].y + r["ins"].w))
		var btns := _final_btns(sc)
		_ok("I7 [%s] 分母: 进店自动弹出小木斧那张, 四选一按钮 %d 个" % [r["n"], btns.size()], btns.size() == AE.FINALS.size())
		var off: Array = []
		for b in btns:
			if not safe.encloses((b as Control).get_global_rect()):
				off.append("%s %s" % [(b as Button).text, str((b as Control).get_global_rect())])
		_ok("★★I7 [%s] 四选一按钮全在屏幕安全区里(原来落在 y 1258)" % r["n"], btns.size() > 0 and off.is_empty(), str(off))
		var c := _card(sc)
		_ok("I7 [%s] 那张卡底沿不过按钮排(%.0f)" % [r["n"], SHOP_GD.ROW_BTN_Y - 6.0],
			c != null and c.get_global_rect().end.y - sc._frame_off().y <= SHOP_GD.ROW_BTN_Y - 6.0 + 1.0,
			str(c.get_global_rect()) if c != null else "无卡")
		var why := _final_btns_bad(btns, [])
		_ok("★★I7 [%s] 四选一按钮够大、2×2 排(短边 ≥ %.0f · 字 ≥ %d · 字放得下 · 互不重叠)" % [r["n"], MIN_TAP, MIN_FONT],
			btns.size() == AE.FINALS.size() and why == "", why)
		var st: Array = _small_text(_live(c, "AxeProgress") if c != null else null)
		_ok("I7 [%s] 小木斧那块的字全 ≥ %d(量了 %d 行: 形态 / 累计 / 进度 / 提示)" % [r["n"], MIN_FONT, int(st[1])],
			int(st[1]) >= 4 and (st[0] as Array).is_empty(), str(st[0]))
		var sb_why := SBJ.problem(c.find_child("CardBodyScroll", true, false) as ScrollContainer if c != null else null,
			SHOP_GD.CARD_SCROLL_W)
		_ok("★I7 [%s] 小木斧那张正文的滚动条是木框 / 黄铜皮(不是默认的灰色圆角条)" % r["n"], sb_why == "", sb_why)
		## 小木斧那张的正文封顶情况(下面一点货架它就被重建掉了, 先量)
		var cuts: Array = []
		if c == null or c.find_child("CardBodyScroll", true, false) == null:
			cuts.append("小木斧那张: 没封顶 / 没卡")
		elif _body_cut(c) != "":
			cuts.append("小木斧那张: " + _body_cut(c))
		## ── 同一态点货架第 4 格(不在小木斧那张底下): 货卡卡底有「购买」⇒ 四选一走紧凑版 ──
		await _click(_slot_center(sc, 4))
		var c4 := _card(sc)
		var bb4 := _live(c4, "BuyBtn") if c4 != null else null
		var btns4 := _final_btns(sc)
		_ok("I7 [%s] 分母: 点第 4 格「%s」→ 那张货卡里有「购买」+ 四选一 %d 个" % [r["n"], _card_title(sc), btns4.size()],
			_glow_slot(sc) == 4 and bb4 != null and btns4.size() == AE.FINALS.size())
		var off4: Array = []
		for b in btns4 + ([bb4] if bb4 != null else []):
			if not safe.encloses((b as Control).get_global_rect()):
				off4.append("%s %s" % [(b as Button).text, str((b as Control).get_global_rect())])
		_ok("★★I7 [%s] 货卡里: 四选一 + 「购买」全在安全区, 卡底沿不过按钮排" % r["n"],
			c4 != null and off4.is_empty() and c4.get_global_rect().end.y - sc._frame_off().y <= SHOP_GD.ROW_BTN_Y - 6.0 + 1.0,
			"%s 卡 %s" % [str(off4), str(c4.get_global_rect()) if c4 != null else "无"])
		var why4 := _final_btns_bad(btns4, [bb4] if bb4 != null else [])
		_ok("★★I7 [%s] 货卡里的四选一也够大、2×2、不压「购买」" % r["n"], btns4.size() == AE.FINALS.size() and why4 == "", why4)
		var st4: Array = _small_text(_live(c4, "AxeProgress") if c4 != null else null)
		_ok("I7 [%s] 货卡里小木斧那块的字全 ≥ %d(量了 %d 行)" % [r["n"], MIN_FONT, int(st4[1])],
			int(st4[1]) >= 1 and (st4[0] as Array).is_empty(), str(st4[0]))
		if c4 == null or c4.find_child("CardBodyScroll", true, false) == null:
			cuts.append("货卡: 没封顶 / 没卡")
		elif _body_cut(c4) != "":
			cuts.append("货卡: " + _body_cut(c4))
		_ok("I7 [%s] 两张卡(小木斧 / 货卡)的正文都封顶成滚动框, 且底边不切在行中间" % r["n"], cuts.is_empty(), str(cuts))
		await _leave(sc)
	SafeArea.override_insets = Vector4(-1, -1, -1, -1)
	## 真点一个造物 → 选定
	_axe_ready()
	var sc2 := await _enter()
	var bs := _final_btns(sc2)
	if bs.size() >= 2:
		await _click((bs[1] as Control).get_global_rect().get_center())
	_ok("★★I7 真点「%s」→ 最终造物选定" % str((AE.FINALS[1] as Dictionary)["name"]),
		str(gs.axe_final) == str((AE.FINALS[1] as Dictionary)["key"]), "axe_final=%s" % str(gs.axe_final))
	await _leave(sc2)
	## 点空白收起那张 → 被它盖住的第 0 格点得到
	_axe_ready()
	var sc := await _enter()
	var cover := _card(sc)
	_ok("I7 分母: 小木斧那张盖着第 0 格", cover != null and cover.get_global_rect().has_point(_slot_center(sc, 0)))
	await _click(Vector2(120, 660))
	_ok("★I7 点空白 → 小木斧那张收起", _card(sc) == null)
	await _click(_slot_center(sc, 0))
	_ok("★I7 收起后第 0 格点得到(选中、弹它自己的卡)", _glow_slot(sc) == 0 and _card(sc) != null, "光=%d" % _glow_slot(sc))
	_ok("I7 选中的货卡里四选一也在(收起那张不等于错过最终进化)", _final_btns(sc).size() == AE.FINALS.size())
	await _leave(sc)
	## I6: 买掉一件之后小木斧那张回来
	_axe_ready()
	sc = await _enter()
	await _click(_slot_center(sc, 4))
	_ok("I6 分母: 选中第 4 格(它的卡里也带四选一)", _glow_slot(sc) == 4)
	var bb := _live(_card(sc), "BuyBtn") if _card(sc) != null else null
	if bb != null:
		await _click(bb.get_global_rect().get_center())
	_ok("I6 分母: 买走了第 4 格", sc._offer[4] == null)
	_ok("★★I6 买完: 小木斧待选那张回来了(四选一 %d 个)" % _final_btns(sc).size(), _final_btns(sc).size() == AE.FINALS.size(),
		"卡=%s" % _card_title(sc))
	await _leave(sc)


## I8 —— 说明卡的位置: 不出屏、「购买」在安全区、不盖被点那件、不压底下那一排。
func _i8_tall_cards() -> void:
	print("\n-- I8 说明卡位置 --")
	var ratios := [{"n": "16:9", "vp": Vector2(1280, 720), "ins": Vector4(0, 0, 0, 0)},
		{"n": "19.5:9", "vp": Vector2(1560, 720), "ins": Vector4(111, 0, 111, 38)},
		{"n": "4:3", "vp": Vector2(1280, 960), "ins": Vector4(0, 0, 0, 25)}]
	## ① 三种比例 × 最长的 10 件铺满 10 格
	for r in ratios:
		_seed()
		_shelf(TALL)
		SafeArea.override_insets = r["ins"]
		var sc := await _enter(r["vp"])
		var bad: Array = []
		var capped := 0
		for i in range(10):
			await _click(_slot_center(sc, i))
			var why := _card_bad(sc, i, r)
			if why != "":
				bad.append(why)
			if _card(sc) != null and _card(sc).find_child("CardBodyScroll", true, false) != null:
				capped += 1
			await _click(_slot_center(sc, i))   # 收起
		_ok("★★I8 [%s] 最长的 10 件 × 10 格: 卡不出屏、「购买」在安全区、不盖被点那件、不压按钮排 / 等级牌" % r["n"],
			bad.is_empty(), str(bad.slice(0, 3)))
		## ★2026-10-22 卡宽 400 → 600、「购买」挪到卡头右上角(用户): 这 10 件里多数已整段放得下, 只有小木斧还超高。
		##   分母改成「滚动那条路至少走到 1 次」(否则 ③ 那几条量的是空气)。
		_ok("I8 [%s] 分母: 超高的那件(小木斧)正文改成了可滚动的一段(%d / 10 件走了滚动)" % [r["n"], capped], capped >= 1)
		await _leave(sc)
	SafeArea.override_insets = Vector4(-1, -1, -1, -1)
	## ② 16:9 下全部装备逐件量
	var all_ids: Array = []
	for e in DataRegistry.phase2_equipment:
		all_ids.append(str((e as Dictionary).get("id", "")))
	var bad2: Array = []
	var n2 := 0
	var scroll_ids: Array = []
	var r16: Dictionary = ratios[0]
	var k := 0
	while k < all_ids.size():
		_seed()
		_shelf(all_ids.slice(k, mini(k + 10, all_ids.size())))
		var sc := await _enter()
		for i in range(mini(10, all_ids.size() - k)):
			await _click(_slot_center(sc, i))
			if _card(sc) != null:
				n2 += 1
				if _card(sc).find_child("CardBodyScroll", true, false) != null:
					scroll_ids.append(str(all_ids[k + i]))
			var why := _card_bad(sc, i, r16)
			if why != "":
				bad2.append(why)
			await _click(_slot_center(sc, i))
		await _leave(sc)
		k += 10
	_ok("I8 分母: 16:9 下逐件弹出了 %d / %d 张说明卡" % [n2, all_ids.size()], n2 == all_ids.size())
	_ok("★I8 16:9 全部装备: 说明卡位置一处不坏", bad2.is_empty(), str(bad2.slice(0, 3)))
	## ★★用户在商店看小木斧时问「为什么有滑动条」→ 2026-10-22「购买按钮放右上角」「把卡片宽度加宽」:
	##   加宽后只有小木斧(四个形态 + 四个造物)整段放不下。别的哪件说明写长了、又冒出滚动条 ⇒ 这里当场红。
	var scroll_extra: Array = scroll_ids.filter(func(x): return not SCROLL_OK.has(x))
	_ok("★★I8 16:9 全部装备: 除小木斧外说明卡都不出滚动条(出了 %d 件: %s)" % [scroll_ids.size(), str(scroll_ids)],
		scroll_extra.is_empty() and n2 == all_ids.size(), str(scroll_extra))
	## ③ 封顶后正文真能滚到底(内容比可见区高, 滚动条的量程覆盖得到最后一行)。084 加宽后放得下了 ⇒ 换小木斧量。
	_seed()
	_shelf(["p2eq_096"])
	var sc3 := await _enter()
	await _click(_slot_center(sc3, 0))
	var scr := _card(sc3).find_child("CardBodyScroll", true, false) as ScrollContainer if _card(sc3) != null else null
	var rt: RichTextLabel = null
	if scr != null and scr.get_child_count() > 0:
		for ch in scr.get_children():
			if ch is RichTextLabel:
				rt = ch
	var vb := scr.get_v_scroll_bar() if scr != null else null
	_ok("I8 096 的正文在滚动框里, 内容比可见区高(%.0f > %.0f)" % [rt.size.y if rt != null else -1.0, scr.size.y if scr != null else -1.0],
		rt != null and rt.size.y > scr.size.y + 10.0)
	_ok("I8 096 滚动条量程盖得住整段正文(max %.0f ≥ 内容 %.0f)" % [vb.max_value if vb != null else -1.0, rt.size.y if rt != null else -1.0],
		vb != null and rt != null and vb.max_value >= rt.size.y - 1.0)
	_ok("I8 096 正文一个字没丢(滚动框里那段 = 装备说明全文)", rt != null and rt.get_parsed_text().length() > 40)
	## 滚动条的皮(2026-10-22): 默认是 Godot 的灰色圆角细条 ⇒ 换木框 / 黄铜。粗细不变(上面两条量程 / 内容照旧)。
	_ok("I8 096 分母: 竖滚动条真的画出来了(内容比可见区高)", vb != null and vb.is_visible_in_tree())
	var sb_why := SBJ.problem(scr, SHOP_GD.CARD_SCROLL_W)
	_ok("★★I8 096 滚动条是木框 / 黄铜皮(直角 · 暖色滑块 · 深色槽 · 不宽过正文让出的 %.0f)" % SHOP_GD.CARD_SCROLL_W,
		scr != null and sb_why == "", sb_why)
	await _leave(sc3)


## 一张说明卡的位置毛病; 没毛病返回 ""。
func _card_bad(sc: Node, i: int, r: Dictionary) -> String:
	var c := _card(sc)
	if c == null:
		return "slot%d 没弹卡" % i
	var vp: Vector2 = r["vp"]
	var ins: Vector4 = r["ins"]
	var safe := Rect2(Vector2(ins.x, ins.y), vp - Vector2(ins.x + ins.z, ins.y + ins.w))
	var cr := c.get_global_rect()
	var tag := "[%s slot%d %s]" % [r["n"], i, _card_title(sc)]
	if not Rect2(Vector2.ZERO, vp).encloses(cr):
		return "%s 卡出屏 %s" % [tag, str(cr)]
	var bb := _live(c, "BuyBtn")
	if bb != null and not safe.encloses(bb.get_global_rect()):
		return "%s 「购买」出安全区 %s" % [tag, str(bb.get_global_rect())]
	if cr.intersects(_item_rect(sc, i)):
		return "%s 卡盖住被点那件 %s" % [tag, str(cr)]
	for nm in ["ShopRefreshBtn", "ShopLockBtn", "ShopBuyXpBtn", "LevelTap"]:
		var b := _live(sc, nm)
		if b != null and cr.intersects(b.get_global_rect()):
			return "%s 卡压住 %s %s" % [tag, nm, str(cr)]
	var cut := _body_cut(c)
	if cut != "":
		return "%s %s" % [tag, cut]
	return ""


## 封顶后正文滚动框的底边切在某一行中间(框底露出下一行字的上半截, 像一道脏线); 没切 / 没封顶 ⇒ ""。
## ★2026-10-22 实拍抓到: 可见高按像素倒推(70 = 2.3 行) ⇒ 小木斧那张卡正文两行下面露着第 3 行的字头。
func _body_cut(c: Control) -> String:
	var scr := c.find_child("CardBodyScroll", true, false) as ScrollContainer if c != null else null
	if scr == null:
		return ""
	var rt: RichTextLabel = null
	for ch in scr.get_children():
		if ch is RichTextLabel:
			rt = ch
	if rt == null:
		return "滚动框里没有正文"
	var vis: float = scr.size.y
	if float(rt.get_content_height()) <= vis + 0.5:
		return ""
	for i in range(rt.get_line_count()):
		if absf(rt.get_line_offset(i) - vis) <= 0.5:
			return ""
	return "正文可见高 %.0f 切在行中间(露出下一行的字头)" % vis


## I9 —— 概率牌与说明卡同时只开一个; 点空白也收得起概率牌。
func _i9_odds() -> void:
	print("\n-- I9 出货概率 --")
	_seed()
	var sc := await _enter()
	await _click(_slot_center(sc, 7))
	_ok("I9 分母: 选中第 7 格", _glow_slot(sc) == 7 and _card(sc) != null)
	await _click(_live(sc, "LevelTap").get_global_rect().get_center())
	var plate := _live(sc, "OddsPlate")
	_ok("I9 分母: 点等级 → 概率牌出来了", plate != null)
	var c := _card(sc)
	_ok("★I9 概率牌没有被说明卡盖住", plate != null and (c == null or not c.get_global_rect().intersects(plate.get_global_rect())),
		"卡=%s 牌=%s" % [str(c.get_global_rect()) if c != null else "无", str(plate.get_global_rect()) if plate != null else "无"])
	await _click(_slot_center(sc, 2))
	plate = _live(sc, "OddsPlate")
	_ok("I9 看着概率时点一件货 → 弹它的卡、概率牌收起", _glow_slot(sc) == 2 and _card(sc) != null and plate == null)
	await _click(_slot_center(sc, 2))
	await _click(_live(sc, "LevelTap").get_global_rect().get_center())
	_ok("I9 分母: 概率牌又打开了", _live(sc, "OddsPlate") != null)
	await _click(Vector2(120, 660))
	_ok("★I9 点空白 → 概率牌收起", _live(sc, "OddsPlate") == null)
	await _leave(sc)


## 顶栏左上「← | 商店 | 背包」一对页签(用户 2026-10-22): 「商店」亮着、点了不做事; 「背包」是教程 / 首次提示的锚点。
##   ★不真点「背包」: 它换场景, 而本测试自己就是当前场景(换走即中断)。
func _top_tabs() -> void:
	print("\n-- 顶栏页签 --")
	_seed()
	var sc := await _enter()
	var shop_tab: Button = null
	var bag_tab: Button = null
	for b in sc._top_bar.action_btns:
		if b is Button and str((b as Button).text) == "商店":
			shop_tab = b
		elif b is Button and str((b as Button).text) == "背包":
			bag_tab = b
	_ok("页签 分母: 左上有「商店」「背包」两签(不带 emoji)", shop_tab != null and bag_tab != null,
		str(sc._top_bar.action_btns.map(func(x): return str((x as Button).text) if x is Button else "?")))
	if shop_tab == null or bag_tab == null:
		await _leave(sc)
		return
	_ok("页签 「商店」在「背包」左边、两签不重叠", shop_tab.get_global_rect().end.x <= bag_tab.get_global_rect().position.x + 0.5,
		"%s / %s" % [str(shop_tab.get_global_rect()), str(bag_tab.get_global_rect())])
	_ok("页签 当前页「商店」亮着(金字)", shop_tab.get_theme_color("font_color") == Color("#ffd93d"))
	_ok("页签 「背包」不是亮的那签", bag_tab.get_theme_color("font_color") != Color("#ffd93d"))
	await _click(_slot_center(sc, 2))
	## ★选货会整页重建(顶栏也重建) ⇒ 两签要重新取, 上面那两个引用已经释放了
	shop_tab = _tab(sc, "商店")
	await _click(shop_tab.get_global_rect().get_center())
	_ok("页签 真点亮着的「商店」→ 不换场、不动选中", is_instance_valid(sc) and sc.is_inside_tree() and _glow_slot(sc) == 2)
	bag_tab = _tab(sc, "背包")
	var ar: Rect2 = sc._tutorial_anchor("bag_button")
	_ok("★页签 教程锚点 bag_button 指在「背包」那一签上", ar.size.x > 0.0 and ar.is_equal_approx(bag_tab.get_global_rect()),
		"锚点 %s / 背包 %s" % [str(ar), str(bag_tab.get_global_rect())])
	var mt = sc.merge_tip_target("p2eq_001", 2)
	_ok("页签 首次合成提示也指「背包」那一签", mt == bag_tab)
	await _leave(sc)


func _tab(sc: Node, txt: String) -> Button:
	for b in sc._top_bar.action_btns:
		if b is Button and is_instance_valid(b) and str((b as Button).text) == txt:
			return b
	return null


## I10 —— 说明卡开着按 ESC: 先收卡, 不离开商店。
func _i10_esc() -> void:
	print("\n-- I10 ESC --")
	_seed()
	var sc := await _enter()
	await _click(_slot_center(sc, 1))
	_ok("I10 分母: 选中第 1 格", _card(sc) != null)
	await _esc()
	_ok("★I10 ESC → 说明卡收起、商店还在", is_instance_valid(sc) and sc.is_inside_tree() and _card(sc) == null and _glow_slot(sc) == -1)
	await _leave(sc)
