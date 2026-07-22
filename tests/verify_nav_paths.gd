extends Node

## verify_nav_paths.gd — 场景之间的导航路径 (2026-07-22)
##
## 用户需求1:「背包里加条路径去前往商店」。
## 此前商店有「🎒 背包」按钮(ShopScene.gd:139), **反向没有** —— 背包空了想买装备,
## 得先退回主菜单再点商店。背包里只有一句提示文字「（背包空 — 去商店买装备）」, 没有按钮。
##
## ★行为级: 真实例化背包场景、遍历节点树找按钮, 并检查它和「返回」不重叠。
##   只查源码有没有 "商店" 两个字是不够的 —— 那句提示文字里本来就有。

const INV_SCENE := "res://scenes/Inventory.tscn"
const SHOP_SRC := "res://scripts/scenes/ShopScene.gd"

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	await _test_inventory_has_shop_button()
	_test_shop_has_inventory_button()
	print("ALL PASS — 背包 ↔ 商店 双向导航" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _test_inventory_has_shop_button() -> void:
	var packed = load(INV_SCENE)
	_ok("载得到背包场景", packed != null)
	if packed == null:
		return
	var inv: Node = packed.instantiate()
	get_tree().root.add_child(inv)
	for i in 5:
		await get_tree().process_frame
	var buttons: Array = []
	for n in _walk(inv):
		if n is Button:
			buttons.append(n)
	print("  [分母] 背包场景里共 %d 个 Button" % buttons.size())
	_ok("背包建出了按钮(N=0 说明场景没起来, 下面全是空检查)", buttons.size() > 0)

	var shop_btn: Button = null
	var back_btn: Button = null
	for b in buttons:
		var t := str(b.text)
		if t.contains("商店"):
			shop_btn = b
		if t.contains("返回"):
			back_btn = b
	_ok("★背包里有【商店】按钮(此前只有一句提示文字, 没有按钮)",
		shop_btn != null, "按钮文字: %s" % str(buttons.map(func(b): return str(b.text))))
	_ok("背包里有【返回】按钮", back_btn != null)

	if shop_btn != null and back_btn != null:
		var r1 := Rect2(shop_btn.position, shop_btn.size)
		var r2 := Rect2(back_btn.position, back_btn.size)
		_ok("★商店按钮不压在返回键上", not r1.intersects(r2),
			"商店 %s / 返回 %s" % [r1, r2])
		_ok("商店按钮有实际尺寸(0 尺寸=点不到)", r1.size.x > 10.0 and r1.size.y > 10.0, "%s" % r1.size)

	# 锁态: 本大轮未打第一场时该按钮要禁用而不是消失 —— 消失会让人以为没这条路
	if shop_btn != null:
		var locked: bool = int(GameState.season_total_battles) <= 0
		print("  [实测] season_total_battles=%d → 期望 disabled=%s, 实际 disabled=%s"
			% [int(GameState.season_total_battles), locked, shop_btn.disabled])
		_ok("★锁/开状态与商店自己的门槛一致(ShopScene.gd:18 同一条)",
			shop_btn.disabled == locked)
		_ok("锁着时说明了为什么(光禁用不说原因等于没告知)",
			(not locked) or str(shop_btn.tooltip_text) != "", "tooltip=%s" % str(shop_btn.tooltip_text))
	inv.queue_free()
	await get_tree().process_frame

	# ★还要验【解锁后】那一半 —— 无头默认 season_total_battles=0, 只测锁态等于只测了一半,
	#   "打完第一场就能点" 这条正好是玩家最常走的路。
	var saved: int = int(GameState.season_total_battles)
	GameState.season_total_battles = 1
	var inv2: Node = packed.instantiate()
	get_tree().root.add_child(inv2)
	for i in 5:
		await get_tree().process_frame
	var shop2: Button = null
	for n in _walk(inv2):
		if n is Button and str(n.text).contains("商店"):
			shop2 = n
	_ok("解锁态下仍有商店按钮", shop2 != null)
	if shop2 != null:
		print("  [实测] season_total_battles=1 → disabled=%s, 文字=%s" % [shop2.disabled, str(shop2.text)])
		_ok("★打完第一场后商店按钮可点", not shop2.disabled)
		_ok("★可点时不再显示锁图标", not str(shop2.text).contains("🔒"), str(shop2.text))
	inv2.queue_free()
	GameState.season_total_battles = saved
	await get_tree().process_frame


## 反向那条路本来就有, 守住别被删
func _test_shop_has_inventory_button() -> void:
	var src := FileAccess.get_file_as_string(SHOP_SRC)
	_ok("读得到 ShopScene.gd", src != "")
	_ok("商店里仍有去背包的按钮(双向都要在)",
		src.contains("res://scenes/Inventory.tscn"))


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
