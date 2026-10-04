extends Node
## verify_shop_lock.gd — 商店货架锁(学云顶)
##
## 用户 2026-10-04 原话:「5是每局打完商店会自动刷新，需要加个锁定键防止被自动刷新走，你知道这个意思吗」
## 复述 + 用户确认:「对的，学云顶的」⇒ 锁一直锁着(跨多场), 直到手动解锁。
## 方案书 docs/plans/20261004-五件新需求.md §⑤。
##
## ★走真入口: 每一步都**真的实例化 Shop.tscn**(自动换货只发生在 ShopScene._ready 里),
##   不是拿戳记比一比就算(verify_shop_persist 那种比戳记的判据量不到「店里到底换没换」)。
## ★种子问题: test_mode 下商店用固定种子 ⇒ 重掷出来的货和上一批**一模一样**, 拿「货变没变」
##   当判据会把「换了货」误判成「没换」。⇒ 每一步先把货架写成一份**哨兵货架**(手挑的 id + 一格空位),
##   换货 = 哨兵被覆盖 —— 与掷出什么无关。
##
## 断言(L = lock):
##   L0  分母: 商店真的开了(货架 10 格) + 锁钮存在、未锁态文案「锁货」、与「刷新」同一行不重叠
##   L1  对照: **不锁** + 打完一场 → 哨兵被换掉(证明这套判据能看见换货)
##   L2  ★锁上 + 打完一场 → 货架逐字节不变; 再打一场 → 仍不变
##   L3  ★锁上时按钮文案「已锁」
##   L4  ★重启保留: _save_dict → JSON → _apply_save_dict 往返后仍是锁着的
##   L5  ★锁着手动「刷新」仍可换(扣 2 币) + 换完**自动解锁**(云顶: 刷新顺带解锁, tft.ninja「The Shop」)
##   L6  ★解锁当下不换货(云顶: 解锁不等于刷新); 解锁后打完下一场 → 换货
##   L7  新赛季 / 清档都解锁

const SHOP := preload("res://scenes/Shop.tscn")
const SHOP_GD = preload("res://scripts/scenes/ShopScene.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 16
const SENTINEL := [{"id": "p2eq_001"}, {"id": "p2eq_002"}, null, {"id": "p2eq_003"}, {"id": "p2eq_004"},
	{"id": "p2eq_005"}, {"id": "p2eq_006"}, {"id": "p2eq_007"}, {"id": "p2eq_008"}, {"id": "p2eq_009"}]

var gs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _shelf() -> String:
	return JSON.stringify(gs.meta_shop_offer)


func _put_sentinel() -> void:
	gs.meta_shop_offer = SENTINEL.duplicate(true)
	gs.meta_shop_battles = int(gs.season_total_battles)


## 打完一场: 走产品自己的结算记账(三条结算路径都是 season_total_battles += 1, 这里走闯关那条)。
func _play_one_match() -> void:
	gs.gauntlet_settle(false)


## 进一次商店(= 真实的「回到商店」), 返回场景实例; 调用方负责 _leave。
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


func _find_refresh(n: Node) -> Button:
	if n is Button and str((n as Button).text).begins_with("刷新"):
		return n
	for c in n.get_children():
		var r = _find_refresh(c)
		if r != null:
			return r
	return null


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	gs.test_mode = true
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.meta_shop_locked = false
	gs.meta_shop_offer = []
	gs.meta_shop_battles = -1
	print("=== 商店货架锁(学云顶) ===")

	# ── L0 分母 ──
	var sc = await _enter()
	_ok("L0 分母: 商店开店且掷出 10 格货架", (sc._offer as Array).size() == 10, "格数 %d" % (sc._offer as Array).size())
	var lb := _find(sc, "ShopLockBtn") as Button
	var rf := _find_refresh(sc)
	_ok("L0 锁钮存在", lb != null)
	_ok("L0 「刷新」存在", rf != null)
	if lb != null and rf != null:
		_ok("L0 未锁态文案「锁货」", lb.text == "锁定", lb.text)
		_ok("L0 锁钮与「刷新」同一行、贴在它右边、不重叠",
			absf(lb.position.y - rf.position.y) < 0.5 and lb.position.x >= rf.position.x + rf.size.x
			and lb.position.x + lb.size.x <= SHOP_GD.PANEL_X,
			"rf=%s+%s lb=%s+%s" % [rf.position, rf.size, lb.position, lb.size])
		_ok("L0 锁钮够大(高 ≥ 44 触控下限)", lb.size.y >= 44.0, str(lb.size))
		_ok("L0 锁钮图标是现成的 icon-lock(不新画)", lb.icon != null and str(lb.icon.resource_path).ends_with("ui/icon-lock.png"),
			str(lb.icon.resource_path) if lb.icon != null else "null")
	_leave(sc)

	# ── L1 对照: 不锁 → 打完一场换货 ──
	_put_sentinel()
	var s0 := _shelf()
	_play_one_match()
	sc = await _enter()
	_ok("L1 对照: 不锁 + 打完一场 → 货架换了(判据看得见换货)", _shelf() != s0, _shelf().substr(0, 60))
	_leave(sc)

	# ── L2/L3 锁上 → 打完一场、两场都不换 ──
	_put_sentinel()
	sc = await _enter()
	sc._on_toggle_lock()
	_ok("L3 点锁钮 → meta_shop_locked = true", bool(gs.meta_shop_locked))
	lb = sc._lock_btn   # ★不按名字找: _rebuild 只 queue_free 旧钮, 这一帧旧钮还挂在树上
	_ok("L3 已锁态文案「已锁」", lb != null and lb.text == "已锁定", lb.text if lb != null else "null")
	_leave(sc)
	s0 = _shelf()
	_ok("L2 前提: 锁的就是哨兵货架", s0 == JSON.stringify(SENTINEL))
	_play_one_match()
	sc = await _enter()
	_ok("★L2 锁着 + 打完一场 → 货架逐字节不变", _shelf() == s0, _shelf().substr(0, 60))
	_leave(sc)
	_play_one_match()
	sc = await _enter()
	_ok("★L2 锁着 + 再打一场 → 仍逐字节不变(锁跨多场)", _shelf() == s0)
	_ok("L2 锁没被进店流程顺手解开", bool(gs.meta_shop_locked))
	_leave(sc)

	# ── L4 重启保留 ──
	var d = JSON.parse_string(JSON.stringify(gs._save_dict()))
	gs.meta_shop_locked = false
	gs._apply_save_dict(d)
	_ok("★L4 存档往返(_save_dict→JSON→_apply_save_dict)后仍锁着", bool(gs.meta_shop_locked))
	_ok("★L4 存档往返后货架逐字节不变", _shelf() == s0)

	# ── L5 锁着手动刷新 ──
	sc = await _enter()
	var c0: int = int(gs.meta_deepsea_coins)
	sc._on_refresh()
	_ok("★L5 锁着手动「刷新」照样换货", _shelf() != s0)
	_ok("L5 刷新照常扣 %d 币" % SHOP_GD.REFRESH_COST, int(gs.meta_deepsea_coins) == c0 - SHOP_GD.REFRESH_COST,
		"%d → %d" % [c0, int(gs.meta_deepsea_coins)])
	_ok("★L5 换完自动解锁(云顶: 刷新顺带解锁)", not bool(gs.meta_shop_locked))
	_leave(sc)

	# ── L6 解锁 ──
	_put_sentinel()
	gs.meta_shop_locked = true
	s0 = _shelf()
	sc = await _enter()
	sc._on_toggle_lock()
	_ok("L6 再点一下 → 解锁", not bool(gs.meta_shop_locked))
	_leave(sc)
	sc = await _enter()
	_ok("★L6 解锁当下重进店 → 不换货(解锁不等于刷新)", _shelf() == s0)
	_leave(sc)
	_play_one_match()
	sc = await _enter()
	_ok("★L6 解锁后打完下一场 → 换货", _shelf() != s0)
	_leave(sc)

	# ── L7 新赛季 / 清档解锁 ──
	gs.meta_shop_locked = true
	gs.start_new_season()
	_ok("L7 新赛季 → 解锁", not bool(gs.meta_shop_locked))
	gs.meta_shop_locked = true
	gs.reset_save()
	_ok("L7 清档 → 解锁", not bool(gs.meta_shop_locked))

	_ok("分母: 断言条数 %d ≥ %d(协程没半路断)" % [_n, MIN_ASSERTS], _n >= MIN_ASSERTS)
	print("ALL PASS — 商店货架锁" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
