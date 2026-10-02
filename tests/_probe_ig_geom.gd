extends Node
## _probe_ig_geom.gd — 把【结算屏 / 商店 / 背包】三屏的真实控件几何倒成 JSON。
##
## ══════════════════════════════════════════════════════════════════════
##  这只是一支【探针】(只读, 不改产品代码, 不进门禁)。
##  用途: 给 `tools/ingame_screen_audit.py diff` 喂"我们这一侧"的真值。
## ══════════════════════════════════════════════════════════════════════
##
## ★为什么不读常量、不看截图, 只量 `get_global_rect()`:
##   memory [[fb-write-without-reader-and-fake-gates]] —— 门禁模拟公式 ≠ 量真实对象;
##   memory [[fb-verify-artifact-not-steps]] —— 产物才是判据。
##   常量会被 clampf / 容器 / SafeArea 三层改写, 抄常量抄出来的表是编的。
##
## ★无头下 `--resolution` 不生效(见 verify_result_reachable 头注), 必须自己设
##   `root.content_scale_size` + `root.size`。
##
## 跑法:
##   IG_MODE=settle IG_OUT=C:/tmp/uiref/ours_settle.json IG_UNITS=28 \
##   APPDATA=C:/tmp/uiref/ad NO_SAVE=1 TURTLE_SUPABASE=" " \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_ig_geom.tscn --quit-after 2400

const SCENE_BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const SCENE_SHOP := "res://scenes/Shop.tscn"
const SCENE_INV := "res://scenes/Inventory.tscn"


func _ready() -> void:
	await get_tree().process_frame
	var mode: String = OS.get_environment("IG_MODE")
	if mode == "":
		mode = "settle"
	var w: int = int(OS.get_environment("IG_W")) if OS.get_environment("IG_W") != "" else 1280
	var h: int = int(OS.get_environment("IG_H")) if OS.get_environment("IG_H") != "" else 720
	get_tree().root.content_scale_size = Vector2i(w, h)
	get_tree().root.size = Vector2i(w, h)
	for _q in range(4):
		await get_tree().process_frame

	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          ## ★不许写玩家真存档
		## ★★商店/背包不是"打开就有东西"的屏: 商店在本大轮未打第一场时走 `_build_locked()`
		##   (ShopScene.gd:82), 我第一版量到的就是那张【上锁屏】——**7 个控件**, 那不是商店。
		##   ⇒ 量之前先把存档喂到"正常在玩"的状态, 否则量的是一块提示牌。
		gs.season_total_battles = 3
		gs.season_level = 5
		gs.season_xp = 2
		gs.meta_deepsea_coins = 200
		gs.coins = 200
		if gs.season_leaders is Array and (gs.season_leaders as Array).is_empty():
			gs.season_leaders = ["green", "stone", "thunder"]
		## ★`left_team: Array[String]` 是**有类型**的数组 —— 直接喂字面量会
		##   `Invalid assignment ... of type 'Array'` 当场红。必须先声明类型再赋。
		if gs.left_team is Array and (gs.left_team as Array).is_empty():
			var _lt: Array[String] = ["green", "stone", "thunder"]
			gs.left_team = _lt
		## 背包里塞一批装备 —— 空背包量不到"格子放不下"那个形状。
		## ★★字段是 `persistent_bench` 不是 `bench_inventory`:
		##   后者是**局内临时**的旧字段(GameState.gd:970 原话"取代局内临时 bench_inventory"),
		##   背包屏读的是 `persistent_bench`(inventory/equip_ops.gd:44)。
		##   我第一版喂错字段 ⇒ 屏幕上写着「背包是空的」而我照样量到了 33 个格子,
		##   要不是那行提示语露了马脚, 这就是一份**空检查**。
		var _nb: int = int(OS.get_environment("IG_BAG")) if OS.get_environment("IG_BAG") != "" else 18
		if gs.persistent_bench is Array and _nb > 0:
			var _bag: Array = []
			var _pool: Array = DataRegistry.phase2_equipment
			for i in range(_nb):
				if _pool.is_empty():
					break
				var e: Dictionary = _pool[i % _pool.size()]
				_bag.append({"id": str(e.get("id", "")), "star": 1})
			gs.persistent_bench = _bag

	var root_node: Node = null
	var extra: Dictionary = {}
	match mode:
		"settle":
			root_node = await _make_settle(extra)
		"shop":
			root_node = await _make_plain(SCENE_SHOP)
		"inventory":
			root_node = await _make_plain(SCENE_INV)
		_:
			push_error("未知 IG_MODE %s" % mode)
			get_tree().quit(2)
			return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var out: Dictionary = {
		"mode": mode, "vp": [vp.x, vp.y],
		"godot": Engine.get_version_info()["string"],
		"version": ProjectSettings.get_setting("application/config/version", "?"),
		"extra": extra,
		"nodes": [],
	}
	var acc: Array = out["nodes"]
	_walk(root_node, acc, 0, "")
	## CanvasLayer 里的 UI 不在场景根的 Control 树上 —— 逐个 layer 也要走
	var st: Node = get_tree().root
	for c in st.get_children():
		if c != self and c != root_node:
			_walk(c, acc, 0, "<root>")
	print("[IG] mode=%s 扫到 %d 个控件  视口 %s" % [mode, acc.size(), str(vp)])
	## ── 实拍一张(可选) ────────────────────────────────────────────────
	## ★`IG_SHOT=<png 绝对路径>`。必须【去掉 --headless】跑, 否则抓到的是空图
	##   **而且不报错**(同 tests/_shot_scene.gd 头注那条)。窗口挪到 5000,5000
	##   不影响结果 —— 抓的是视口纹理, 不是屏幕。
	## ★为什么顺手加在这支探针里而不另写一个台子: 这一屏的"造长名单"那套设置
	##   (IG_UNITS / NO_SAVE / test_mode)全在这里, 另写一份就是抄第二遍。
	if OS.has_environment("IG_SHOT"):
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var sp: String = OS.get_environment("IG_SHOT")
		var err: int = img.save_png(sp)
		print("[IG] 实拍 %s  rc=%d  %dx%d" % [sp, err, img.get_width(), img.get_height()])
	var p: String = OS.get_environment("IG_OUT")
	if p == "":
		p = "C:/tmp/uiref/ours_%s.json" % mode
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_error("写不开 %s" % p)
	else:
		f.store_string(JSON.stringify(out))
		f.close()
		print("[IG] 写盘 %s" % p)
	get_tree().quit(0)


## ── 造一个【单位很多】的结算屏 ────────────────────────────────────
## ★用户点名的形状是"很多单位看不到", 3v3 教学局量不到它 ⇒ 分母必须先塞满。
##   造法照抄 tests/verify_result_reachable.gd(已在门禁里, 不另发明)。
func _make_settle(extra: Dictionary) -> Node:
	var sc = load(SCENE_BATTLE).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(30):
		await get_tree().process_frame
	var per: int = int(OS.get_environment("IG_UNITS")) if OS.get_environment("IG_UNITS") != "" else 14
	var made := 0
	for side in ["left", "right"]:
		for k in range(per):
			var u = sc._spawn._make_unit("green", side, sc.ARENA.position + sc.ARENA.size * 0.5
				+ Vector2(-260.0 + 34.0 * float(k), -140.0 + 120.0 * (0.0 if side == "left" else 1.0)))
			if u is Dictionary:
				u["dmg_done"] = 1000.0 + 137.0 * float(k)
				u["dmg_taken"] = 500.0 + 91.0 * float(k)
				u["heal_done"] = 40.0 * float(k)
				u["_st_dealt"] = 1000 + 137 * k
				u["_st_taken"] = 500 + 91 * k
				u["_st_heal"] = 40 * k
				u["_st_kills"] = k % 3
				if not sc._arr_has_unit(sc._units, u):
					sc._units.append(u)
				made += 1
	extra["units_made"] = made
	extra["units_total"] = sc._units.size()
	for _i in range(8):
		await get_tree().process_frame
	sc._hud._show_banner(true)
	## 喂过 0.4 秒自刷周期 + 让 minimum_size_changed 那条事件链跑完
	var _w := 0.0
	while _w < 1.2:
		await get_tree().process_frame
		_w += get_process_delta_time()
	for _i in range(20):
		await get_tree().process_frame
	return sc


func _make_plain(path: String) -> Node:
	var sc = load(path).instantiate()
	get_tree().root.add_child(sc)
	for _i in range(60):
		await get_tree().process_frame
	return sc


## ── 遍历: 每个 Control 一行 ────────────────────────────────────────
func _walk(n: Node, acc: Array, depth: int, path: String) -> void:
	var here: String = path + "/" + str(n.name)
	if n is Control:
		var c: Control = n
		var r: Rect2 = c.get_global_rect()
		var row: Dictionary = {
			"cls": c.get_class(), "name": str(c.name), "path": here, "d": depth,
			"x": snappedf(r.position.x, 0.01), "y": snappedf(r.position.y, 0.01),
			"w": snappedf(r.size.x, 0.01), "h": snappedf(r.size.y, 0.01),
			"vis": c.is_visible_in_tree(),
			"mf": int(c.mouse_filter),
			"cms": [c.custom_minimum_size.x, c.custom_minimum_size.y],
			"clip": c.clip_contents,
			"minsz": [snappedf(c.get_combined_minimum_size().x, 0.01),
					  snappedf(c.get_combined_minimum_size().y, 0.01)],
		}
		if c is Label:
			row["text"] = (c as Label).text
			row["lines"] = (c as Label).get_line_count()
			row["vlines"] = (c as Label).get_visible_line_count()
			row["fs"] = (c as Label).get_theme_font_size("font_size")
		elif c is RichTextLabel:
			row["text"] = (c as RichTextLabel).get_parsed_text()
			row["lines"] = (c as RichTextLabel).get_line_count()
			row["vlines"] = (c as RichTextLabel).get_visible_line_count()
			row["fs"] = (c as RichTextLabel).get_theme_font_size("normal_font_size")
		elif c is Button:
			row["text"] = (c as Button).text
			row["disabled"] = (c as Button).disabled
			row["fs"] = (c as Button).get_theme_font_size("font_size")
		elif c is LineEdit:
			row["text"] = (c as LineEdit).text
			row["ph"] = (c as LineEdit).placeholder_text
		if c is ScrollContainer:
			var s: ScrollContainer = c
			var vb: VScrollBar = s.get_v_scroll_bar()
			var hb: HScrollBar = s.get_h_scroll_bar()
			var inner: Vector2 = Vector2.ZERO
			for ch in s.get_children():
				if ch is Control and (ch as Control).is_visible_in_tree():
					inner.x = maxf(inner.x, (ch as Control).size.x)
					inner.y = maxf(inner.y, (ch as Control).size.y)
			row["scroll"] = {
				"v_mode": int(s.vertical_scroll_mode),
				"h_mode": int(s.horizontal_scroll_mode),
				"v_visible": vb != null and vb.visible,
				"v_max": (vb.max_value if vb != null else -1.0),
				"v_page": (vb.page if vb != null else -1.0),
				"v_value": (vb.value if vb != null else -1.0),
				"h_visible": hb != null and hb.visible,
				"content_h": snappedf(inner.y, 0.01),
				"content_w": snappedf(inner.x, 0.01),
				"clip": s.clip_contents,
			}
		acc.append(row)
	## ★★`get_children()` 默认**不含内部子节点**, 而 ScrollContainer 的两根滚动条
	##   正是内部子节点 ⇒ 第一版扫到 772 个控件里**一根滚动条都没有**。
	##   要量"滚动条多宽/在哪", 必须 `get_children(true)`。
	for ch in n.get_children(true):
		_walk(ch, acc, depth + 1, here)
