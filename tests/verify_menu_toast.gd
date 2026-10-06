extends Node
## verify_menu_toast.gd — 主菜单提示条不许压在左上角 Logo 上 (2026-10-03 周六实操台账 S11)
## 原现象: 点上锁的「开始战斗」, 「✅ 已晋级决赛日 · 闯关赛到此为止(4-0) · 明天周日来打决赛日」那个 ✅ 骑在 Logo 右下角。
## ★量真东西: 真主菜单、真 `_toast()`、Logo 节点落定后的矩形 vs 提示条矩形。

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 主菜单提示条不压 Logo ===")
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	for _i in range(150):                 # 等 Logo 入场 tween 落定
		await get_tree().process_frame
	var logo = mm.find_child("PlayerCard", true, false)   # 2026-10-06 Logo 已去掉, 左上占位的是玩家卡
	_ok("★分母: 找得到玩家卡节点", logo is Control)
	if not (logo is Control):
		_done(mm)
		return
	var msg := "✅ 已晋级决赛日 · 闯关赛到此为止(4-0) · 明天周日来打决赛日"
	var before: int = mm.get_child_count()
	mm._toast(msg)
	await get_tree().process_frame
	var toast: Label = null
	for c in mm.get_children():
		if c is Label and (c as Label).text == msg:
			toast = c
	_ok("★分母: 提示条真的建出来了", toast != null and mm.get_child_count() == before + 1)
	if toast == null:
		_done(mm)
		return
	var lr: Rect2 = (logo as Control).get_global_rect()
	var tr: Rect2 = toast.get_global_rect()
	_ok("★分母: 玩家卡有真实尺寸(没在屏外)", lr.size.x > 100 and lr.position.x >= 0, str(lr))
	_ok("★★提示条与左上玩家卡不相交(原 bug: ✅ 骑在左上 Logo 右下角)", not lr.intersects(tr), "logo=%s toast=%s" % [str(lr), str(tr)])
	_done(mm)


func _done(mm) -> void:
	mm.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 提示条不压 Logo" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
