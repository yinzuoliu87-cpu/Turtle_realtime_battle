extends Node
## verify_shop_lantern_flicker.gd — 商店货柜里四盏灯笼的烛火真的在动(2026-10-21)
##
## 用户 10-21「商店你不是说灯是动态吗」: 原来只有柜外一团淡光在抖, 灯笼本身是底图里画死的, 手机上看不出在动。
## 现在每盏灯叠一层原生像素格的烛火(ShopAmbience.LANTERN_MASK 五帧) + 外光同节拍变亮变大。
##
## 断言:
##   L1  掩码 == 底图: 四盏灯的玻璃 #ffb145 / 火苗 #fdfff2 逐像素对 shop-shelf-wide.png(换了底图掩码不跟着改就红)
##   L2  五帧两两不同(帧没生成出差别 = 叠了层也看不出动)
##   L3  ★真开店: 四盏灯各自的火苗层在场、贴在灯的原生坐标上; 8 秒里每盏都换过 ≥ 3 次帧(原来的 bug = 0 次)、外光亮度 ≥ 3 种值
##   L5  也不能太快(用户 10-22「频率这么快干啥」): 8 秒里每盏换帧 ≤ 16 次(原来 0.06~0.16 秒一跳 ⇒ 8 秒 50+ 次)
##   L4  四盏不同步(各抽各的节拍, 不是整排一起闪)

const SHOP := preload("res://scenes/Shop.tscn")
const AMB := preload("res://scripts/scenes/shop/shop_ambience.gd")
const PNG := "res://assets/sprites/shop/shop-shelf-wide.png"

var _fail := 0
var _n := 0
const MIN_ASSERTS := 20


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


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 商店灯笼烛火 ===")

	# ── L1 掩码 == 底图 ──
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(PNG))
	_ok("L1 分母: 读到底图 PNG", err == OK and img.get_width() == 324, "%dx%d" % [img.get_width(), img.get_height()])
	var glass := Color8(0xff, 0xb1, 0x45)
	var flame := Color8(0xfd, 0xff, 0xf2)
	for i in range(AMB.LANTERN_MASK.size()):
		var o: Vector2i = AMB.LANTERN_ORIGIN[i]
		var mask: Array = AMB.LANTERN_MASK[i]
		var bad := 0
		var nf := 0
		for y in range(mask.size()):
			for x in range((mask[y] as String).length()):
				var p := img.get_pixel(o.x + x, o.y + y)
				var exp := "g" if p.is_equal_approx(glass) else ("f" if p.is_equal_approx(flame) else ".")
				if exp != (mask[y] as String)[x]:
					bad += 1
				if exp == "f":
					nf += 1
		_ok("L1 灯 %d 掩码逐像素 == 底图(含 ≥ 8 个火苗像素)" % i, bad == 0 and nf >= 8, "不一致 %d · 火苗 %d" % [bad, nf])

	# ── L2 五帧两两不同 ──
	var fr: Array = AMB.flame_frames(AMB.LANTERN_MASK[1])
	var same := 0
	for a in range(fr.size()):
		for b in range(a + 1, fr.size()):
			if (fr[a] as Texture2D).get_image().get_data() == (fr[b] as Texture2D).get_image().get_data():
				same += 1
	_ok("L2 五帧两两不同", fr.size() == 5 and same == 0, "帧数 %d · 相同的对 %d" % [fr.size(), same])

	# ── L3 / L4 真开店 ──
	## 开店前置照 verify_shop_chest._reset(没有赛季/货架时商店只显示一行提示, 灯笼根本不建)
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.meta_shop_locked = false
	var offer: Array = []
	for _i in range(10):
		offer.append({"id": "p2eq_001"})
	gs.meta_shop_offer = offer
	gs.meta_shop_battles = int(gs.season_total_battles)
	var sc = SHOP.instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var fls: Array = []
	var gls: Array = []
	for i in range(4):
		fls.append(_find(sc, "LanternFlame%d" % i))
		gls.append(_find(sc, "LanternGlow%d" % i))
	var present := 0
	for i in range(4):
		if fls[i] != null and gls[i] != null:
			present += 1
	_ok("L3 分母: 四盏灯的火苗层 + 外光都在", present == 4, "%d/4" % present)
	if present < 4:
		_dump(sc, 0)
	if present < 4:
		_finish(); return
	for i in range(4):
		var f: Control = fls[i]
		var want: Vector2 = Vector2(AMB.LANTERN_ORIGIN[i]) * float(sc.CAB_SCALE)
		_ok("L3 灯 %d 火苗层贴在原生坐标上" % i, f.position.distance_to(want) < 0.01, "%s vs %s" % [f.position, want])
	var changes := [0, 0, 0, 0]
	var alphas := [{}, {}, {}, {}]
	var last := []
	for i in range(4):
		last.append((fls[i] as TextureRect).texture)
	var seq := ["", "", "", ""]
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		for i in range(4):
			var tx: Texture2D = (fls[i] as TextureRect).texture
			if tx != last[i]:
				changes[i] += 1
				last[i] = tx
				seq[i] += str(tx.get_rid().get_id() % 97) + ","
			alphas[i][snappedf((gls[i] as Control).modulate.a, 0.01)] = true
	for i in range(4):
		_ok("L3 ★灯 %d 八秒内换帧 ≥ 3 次、外光亮度 ≥ 3 种" % i, changes[i] >= 3 and alphas[i].size() >= 3,
			"换帧 %d · 亮度 %d 种" % [changes[i], alphas[i].size()])
		_ok("L5 灯 %d 八秒内换帧 ≤ 16 次(不闪)" % i, changes[i] <= 16, "换帧 %d" % changes[i])
	var distinct := {}
	for i in range(4):
		distinct[seq[i]] = true
	_ok("L4 四盏灯换帧序列各不相同(不是整排一起闪)", distinct.size() == 4, "%d 种" % distinct.size())
	remove_child(sc)
	sc.free()
	_finish()


func _dump(n: Node, d: int) -> void:
	if d < 4:
		print("    ".repeat(d), n.name, " (", n.get_child_count(), ")")
		for c in n.get_children():
			_dump(c, d + 1)


func _finish() -> void:
	_ok("分母: 断言数 ≥ %d" % MIN_ASSERTS, _n >= MIN_ASSERTS, "%d 条" % _n)
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("FAILED: %d" % _fail)
		get_tree().quit(1)
