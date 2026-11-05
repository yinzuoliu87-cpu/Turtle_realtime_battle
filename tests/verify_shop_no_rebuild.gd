extends Node
## verify_shop_no_rebuild.gd — 商店点一下不整页重建(2026-11-05)
##
## 由来: 用户 2026-11-05「这个商店因为是动态的，然后我任意点击屏幕上一个地方，都会使这个商店重置一下，于是所有图片都卡一下」。
##   查实: 选中一件货 / 点空白收起 / 点等级看概率都调 `_rebuild()` —— 整页(背景、货柜、10 件货、店主、氛围动效)销毁再建,
##   呼吸光 / 斜掠高光 / 店主待机全从头播。改成 `_refresh_popups()`: 只动选中金光、说明卡、概率牌。
## 判据(真鼠标按下 + 松开, 走引擎命中, 写法同 verify_shop_interactions):
##   ① 点货架 / 点同一格收起 / 点另一格 / 点空白 / 点等级开概率 / 再点收起 —— 每一步之后, 背景、10 件货、刷新钮、等级牌、
##      钱袋牌、店主这些节点【还是同一个实例】(没被销毁重建), 且「已拥有」呼吸光的循环补间没被换掉(动画没重播)
##   ② 该出现的出现: 选中金光在被点那格、说明卡开着 / 收起, 概率牌开 / 收
##   ③ 第一次点开说明卡不现场加载脚本: 进店时后台已排上预加载(SkillText.prewarm_consts), 第一次耗时 ≤ 第二次的 5 倍
##      (原来 948 vs 9 毫秒; 相对同进程参照, 不跟机器快慢挂钩。墙钟「点击 + 6 帧」在无头下只量到帧节奏, 区分不出, 不用)
## 跑法: bash godot-quiet.sh res://tests/verify_shop_no_rebuild.tscn

const SHOP := preload("res://scenes/Shop.tscn")
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


## 一次点按; 返回从松开(点击在松开时生效)到其后 6 帧走完的墙钟微秒 —— 销毁旧节点 / 排版都在后面几帧里
func _click(p: Vector2) -> int:
	_ev(p, true)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	_ev(p, false)
	await _frames(6)
	return Time.get_ticks_usec() - t0


func _dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


func _live(root: Node, nm: String) -> Control:
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not _dying(c):
			return c
	return null


func _glow_slot(sc: Node) -> int:
	for i in range(10):
		var b := _live(sc, "ShelfItem%d" % i)
		if b != null and b.find_child("SelGlow", true, false) != null:
			return i
	return -1


func _slot_center(sc: Node, i: int) -> Vector2:
	var b := _live(sc, "ShelfItem%d" % i)
	return b.get_global_rect().get_center() if b != null else Vector2(-100, -100)


## 「不该被重建」的那一批: 名字 → 实例号
func _stable(sc: Node) -> Dictionary:
	var out := {}
	var names := ["CoinPlaque", "LevelPlaque", "ShopRefreshBtn"]
	for i in range(10):
		names.append("ShelfItem%d" % i)
	for nm in names:
		var c := _live(sc, nm)
		out[nm] = c.get_instance_id() if c != null else 0
	## 背景(整页第一层 ColorRect)与店主: 按类型 / 名字里有 Keeper 找
	for c in sc.find_children("*Keeper*", "", true, false):
		if not _dying(c):
			out["keeper:" + str(c.name)] = c.get_instance_id()
	for c in sc.find_children("*", "TextureRect", true, false):
		if not _dying(c) and (c as TextureRect).texture != null and str((c as TextureRect).texture.resource_path).find("backdrop") >= 0:
			out["backdrop"] = c.get_instance_id()
			break
	return out


func _same(a: Dictionary, b: Dictionary) -> Array:
	var bad: Array = []
	for k in a:
		if int(a[k]) == 0 or int(b.get(k, -1)) != int(a[k]) or not is_instance_valid(instance_from_id(int(a[k]))) or _dying(instance_from_id(int(a[k]))):
			bad.append(k)
	return bad


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	print("=== 商店点一下不整页重建 ===")
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
	gs.axe_stage = 0
	gs.axe_final = ""
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)
	var sc: Control = SHOP.instantiate()
	add_child(sc)
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sc.position = Vector2.ZERO
	sc.size = Vector2(1280, 720)
	await _frames(3)
	sc._rebuild()
	await _frames(4)
	## ③ 第一次点开说明卡不卡: 进店时文案里 {C:类.常量} 引用的脚本已交给后台线程加载(SkillText.prewarm_consts)。
	##   原来第一次 948 毫秒、之后每次约 9 毫秒(EquipSystem 主线程现场加载 930 毫秒)。判据用同一进程里的「第二次」作参照。
	var pend: Array = SkillText._warm_pending.keys()
	## 等后台做完: 一次性阻塞取完(SkillText.flush_prewarm), 不按帧轮询 —— CI 无头跑帧极快, 轮询 15 秒会先把帧预算用光(11-05 CI 红过一次)
	var tw := Time.get_ticks_msec()
	SkillText.flush_prewarm()
	var eq_path := ""
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "EquipSystem":
			eq_path = str(c.get("path", ""))
	_ok("③ 进店时后台已排上文案常量脚本的预加载(含 EquipSystem)", pend.size() > 0 and (pend.has(eq_path) or SkillText._const_cache.has("EquipSystem")),
		"%d 个 · 等后台用了 %d 毫秒" % [pend.size(), Time.get_ticks_msec() - tw])
	var t1 := Time.get_ticks_usec()
	sc._on_select(4)
	var first_us := Time.get_ticks_usec() - t1
	sc._on_select(4)
	await _frames(3)
	t1 = Time.get_ticks_usec()
	sc._on_select(4)
	var second_us := Time.get_ticks_usec() - t1
	sc._on_select(4)
	await _frames(3)
	_ok("③ 第一次点开说明卡 %.1f 毫秒 ≤ 第二次 %.1f 毫秒的 5 倍(原来约 100 倍)" % [first_us / 1000.0, second_us / 1000.0], first_us <= second_us * 5 + 3000, "")
	var base := _stable(sc)
	_ok("分母: 盯着的节点 %d 个(10 件货 + 钱袋牌 / 等级牌 / 刷新钮 + 背景 + 店主)" % base.size(), base.size() >= 14 and _same(base, base).is_empty(), str(base.keys()))
	var steps := [
		["点第 3 格货", func(): return _slot_center(sc, 2), 2, true, false],
		["再点同一格收起", func(): return _slot_center(sc, 2), -1, false, false],
		["点第 7 格货", func(): return _slot_center(sc, 6), 6, true, false],
		["点另一格(第 1 格)", func(): return _slot_center(sc, 0), 0, true, false],
		["点空白(店主脚边)收起", func(): return Vector2(120, 660), -1, false, false],
		["点等级开出货概率", func(): return _live(sc, "LevelTap").get_global_rect().get_center(), -1, false, true],
		["点空白收起概率", func(): return Vector2(120, 660), -1, false, false],
	]
	for st in steps:
		await _click((st[1] as Callable).call())
		var now := _stable(sc)
		var bad := _same(base, now)
		_ok("① %s: 背景 / 货架 / 按钮 / 店主还是同一批节点(没重建)" % st[0], bad.is_empty(), "被重建: %s" % str(bad))
		var card_open := _live(sc, "InspectCard") != null
		var odds_open := _live(sc, "OddsRow") != null
		_ok("② %s: 选中光在第 %d 格 · 说明卡%s · 概率牌%s" % [st[0], int(st[2]) + 1, "开" if st[3] else "收", "开" if st[4] else "收"],
			_glow_slot(sc) == int(st[2]) and card_open == bool(st[3]) and odds_open == bool(st[4]),
			"光=%d 卡=%s 概率=%s" % [_glow_slot(sc), card_open, odds_open])
	print("")
	_ok("分母: 断言条数 %d ≥ 17" % _n, _n >= 17)
	print("ALL PASS — 商店点一下不整页重建" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
