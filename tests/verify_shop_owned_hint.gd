extends Node
## verify_shop_owned_hint.gd — 货架上「背包里已有这件」的提示: 真的出现、真的在动(2026-10-22)
##
## 用户 10-22「商店物品的提示呢，背包里有二星，不提示吗」。两处都是坏的:
##   ① 判「已拥有」借了合成进度的口径 `_owned_count(id)`, 它只数 ★1 ⇒ 背包只有 ★2 时没有任何提示;
##   ② 呼吸金光 / 斜掠高光是循环 tween, 被 UIFrame 收编时误杀(TweenKit) ⇒ 金光定在一个亮度、高光停在框外看不见。
## verify_shop_layout 里那几条是查源码字符串(「源码里有 tween_property(glow…)」), 两处坏着它照样绿 ⇒ 这里量真对象。
##
## 断言:
##   O1  ★背包只有 ★2 ⇒ 那件在货架上的格子有 OwnedGlow + OwnedShine
##   O2  背包只有 ★1 ⇒ 同样有(回归)
##   O3  没拥有的格子没有(反面: 不是每格都镀)
##   O4  ★三秒里金光亮度 ≥ 3 种值、高光横移 ≥ 30px(真的在动)
##   O5  合成进度口径不变: `_owned_count(id)` 仍只数 ★1(verify_shop_merge_pips 管的那条)

const SHOP := preload("res://scenes/Shop.tscn")
const OWN := "p2eq_001"
const OTHER := "p2eq_002"

var _fail := 0
var _n := 0
const MIN_ASSERTS := 10
var gs


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _find(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r = _find(c, nm)
		if r != null:
			return r
	return null


func _setup(bench: Array) -> void:
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.persistent_bench = bench
	gs.persistent_equipped = {}
	gs.meta_shop_locked = false
	## 第 0 格 = 背包里有的那件, 其余 = 没拥有的
	var offer: Array = [{"id": OWN}]
	for _i in range(9):
		offer.append({"id": OTHER})
	gs.meta_shop_offer = offer
	gs.meta_shop_battles = int(gs.season_total_battles)


func _open() -> Node:
	var sc = SHOP.instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	return sc


func _close(sc: Node) -> void:
	remove_child(sc)
	sc.free()


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 商店: 背包已有的提示 ===")

	# ── O1 / O3 / O4: 背包只有 ★2 ──
	_setup([{"id": OWN, "star": 2}, {"id": "p2eq_010", "star": 1}])
	var sc = await _open()
	var c0: Node = _find(sc, "ShelfItem0")
	var c1: Node = _find(sc, "ShelfItem1")
	_ok("分母: 货架第 0 / 1 格都在", c0 != null and c1 != null)
	if c0 == null or c1 == null:
		_finish(); return
	var glow: Control = _find(c0, "OwnedGlow") as Control
	var shine_box: Node = _find(c0, "OwnedShine")
	_ok("O1 ★背包只有 ★2 ⇒ 那一格有呼吸金光", glow != null)
	_ok("O1 ★背包只有 ★2 ⇒ 那一格有斜掠高光", shine_box != null)
	_ok("O3 没拥有的格子没有金光 / 高光", _find(c1, "OwnedGlow") == null and _find(c1, "OwnedShine") == null)
	if glow != null and shine_box != null:
		var shine: Control = null
		for c in shine_box.get_children():
			for cc in c.get_children():
				if cc is ColorRect:
					shine = cc
		_ok("O4 分母: 找到高光那一条", shine != null)
		var alphas := {}
		var xmin := 1e9
		var xmax := -1e9
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			await get_tree().process_frame
			alphas[snappedf(glow.modulate.a, 0.01)] = true
			if shine != null:
				xmin = minf(xmin, shine.position.x)
				xmax = maxf(xmax, shine.position.x)
		_ok("O4 ★三秒里金光亮度 ≥ 3 种值(在呼吸)", alphas.size() >= 3, "%d 种" % alphas.size())
		_ok("O4 ★三秒里高光横移 ≥ 30px(在扫)", shine != null and xmax - xmin >= 30.0, "%.0f px" % (xmax - xmin))
	_ok("O5 合成进度口径不变: _owned_count 只数 ★1(背包只有 ★2 ⇒ 0)", int(sc._owned_count(OWN)) == 0, str(sc._owned_count(OWN)))
	_ok("O5 已拥有提示数任何星级(⇒ 1)", int(sc._owned_any_star(OWN)) == 1, str(sc._owned_any_star(OWN)))
	_close(sc)

	# ── O2: 背包只有 ★1 ──
	_setup([{"id": OWN, "star": 1}])
	sc = await _open()
	var c0b: Node = _find(sc, "ShelfItem0")
	_ok("O2 背包只有 ★1 ⇒ 那一格同样有金光", c0b != null and _find(c0b, "OwnedGlow") != null)
	_close(sc)
	_finish()


func _finish() -> void:
	_ok("分母: 断言数 ≥ %d" % MIN_ASSERTS, _n >= MIN_ASSERTS, "%d 条" % _n)
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("FAILED: %d" % _fail)
		get_tree().quit(1)
