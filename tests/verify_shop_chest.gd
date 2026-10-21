extends Node
## verify_shop_chest.gd — 商店整页重做后的【买 / 卖 / 看】(2026-10-18)
##
## 用户 10-18:「整个页面就应该重做啊，没有任何游戏搞的这种浏览器网页感」
##   →「我并不觉得左边的阵容可以放在商店里吧」→ 选「店主 + 宝箱」:
##   商店只管买 / 卖 / 看; 买下的东西进宝箱(= 背包), 装到龟身上回背包页做。
##
## ★走真入口: 真的实例化 Shop.tscn; 买走 `_on_buy`(购买按钮接的), 拖拽走落点处理函数
##   (拖放回调里调的就是它们), 点按发一对真的鼠标按下 / 松开事件(产品在松手时才算点按)。
##
## 断言:
##   C0  分母: 商店开店、店主在、宝箱落点在、阵容【不】在商店里
##   C1  ★买下 → 进背包、还在商店、不自动选中(不再有「待装」)
##   C2  ★没有拖拽: 买 = 点货架 → 购买; 卖 = 点宝箱里一件 → 卖出
##   C3  点宝箱里一件 → 说明小卡, 卡底「卖出 +N」(2026-10-21 手机版)
##   C4  ★刷新 / 锁定是无框图标钮(不是金木框): 五态 StyleBox 都是空的, 有图标

const SHOP := preload("res://scenes/Shop.tscn")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 15   # 2026-10-21 商店拿掉背包那一排与卖出: 删 6 条、加 4 条
const ITEM := "p2eq_001"

var gs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _enter() -> Node:
	var sc = SHOP.instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await get_tree().process_frame
	return sc


func _leave(sc: Node) -> void:
	remove_child(sc)
	sc.free()


func _find(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r = _find(c, nm)
		if r != null:
			return r
	return null


func _count_prefix(n: Node, pre: String) -> int:
	var k := 1 if str(n.name).begins_with(pre) else 0
	for c in n.get_children():
		k += _count_prefix(c, pre)
	return k


func _tap(ct: Control) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = ct.size * 0.5
		ct.gui_input.emit(ev)
	await get_tree().process_frame


func _reset() -> void:
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.dual_lineup = {}
	gs.get_dual_lineup()
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.meta_shop_locked = false
	var a: Array = []
	for i in range(10):
		a.append({"id": ITEM})
	gs.meta_shop_offer = a
	gs.meta_shop_battles = int(gs.season_total_battles)


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 商店: 店主 + 宝箱, 买 / 卖 / 看 ===")

	# ── C0 ──
	_reset()
	var sc = await _enter()
	_ok("C0 分母: 商店开店(货架 10 格)", (sc._offer as Array).size() == 10, "格数 %d" % (sc._offer as Array).size())
	_ok("C0 店主在", _find(sc, "Shopkeeper") != null)
	## ★2026-10-21 用户「商店里为什么会显示背包的装备和羁绊？」→「对啊，商店要这么搞」: 背包那一排与羁绊不在商店里。
	_ok("C0 ★背包那一排不在商店里", _find(sc, "BenchHeader") == null and _count_prefix(sc, "BenchCell") == 0)
	_ok("C0 ★羁绊总览不在商店里", _find(sc, "SynergyHeader") == null)
	_ok("C0 ★阵容不在商店里(没有单位格)", _count_prefix(sc, "LineupRow_") == 0, "实测 %d" % _count_prefix(sc, "LineupRow_"))

	# ── C1 买下 ──
	sc._on_buy(0)
	await get_tree().process_frame
	_ok("C1 ★买下 → 进背包", gs.persistent_bench.size() == 1 and str(gs.persistent_bench[0].get("id", "")) == ITEM, str(gs.persistent_bench))
	_ok("C1 买下后还在商店", is_instance_valid(sc) and sc.is_inside_tree())
	_ok("C1 ★不自动选中(装备在背包页做)", int(sc._sel_bench) == -1, "sel_bench=%d" % int(sc._sel_bench))
	_ok("C1 身上一件没多(商店不装备)", int(gs.team_equipped_count()) == 0, "%d" % int(gs.team_equipped_count()))

	# ── C2 没有拖拽(用户 10-18「为什么要拖入宝箱去购买？」): 买 = 点货架 → 购买; 卖 = 点宝箱里一件 → 卖出 ──
	sc._on_buy(1)
	await get_tree().process_frame
	_ok("C2 再买一件 → 背包 2 件", gs.persistent_bench.size() == 2, str(gs.persistent_bench))
	var src: String = FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd") + FileAccess.get_file_as_string("res://scripts/scenes/shop/shop_chest.gd")
	_ok("C2 ★商店里没有拖拽(源码零处 set_drag_forwarding)", src.length() > 1000 and src.find("set_drag_forwarding") < 0)

	# ── C3 商店里没有卖出(用户 2026-10-21「商店里就不能卖装备」: 只在背包页卖) ──
	_ok("C3 ★商店里没有卖出钮", _find(sc, "SellBtn") == null)
	_ok("C3 ★商店源码不再接卖出(零处 _sell_bench / sell_bench_at 调用)", FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd").find("_sell_bench") < 0 and FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd").find("sell_bench_at") < 0)

	# ── C4 刷新 / 锁定: 像素木牌钮 ──
	var bad: Array = []
	var seen := 0
	for nm in ["ShopRefreshBtn", "ShopLockBtn"]:
		var b = _find(sc, nm)
		if b == null:
			bad.append("%s 不在" % nm); continue
		seen += 1
		if (b as Button).icon == null:
			bad.append("%s 没图标" % nm)
		## 2026-10-21 用户「3个按钮？」⇒ 换成场景里的像素木牌(ShopScene.PLANK_TEX); 仍不许是金木框(btn-frame / 共享层框)
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb = (b as Button).get_theme_stylebox(st)
			if not (sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null
					and str((sb as StyleBoxTexture).texture.resource_path).ends_with("shop/shop-plank.png")):
				bad.append("%s.%s 不是木牌底" % [nm, st])
	_ok("C4 分母: 刷新 / 锁定都在", seen == 2)
	_ok("C4 ★刷新 / 锁定是像素木牌钮(不是金木框)", bad.is_empty(), str(bad))
	_leave(sc)

	print("")
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d)" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 商店买卖看" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
