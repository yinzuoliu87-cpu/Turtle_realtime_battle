extends Node
const VfxTexRef := preload("res://scripts/util/vfx_textures.gd")
## verify_candy_jar.gd — 自证: 糖果罐/临时等级器 端到端 (逻辑 + 数据形状 + 3合1不炸).
## 跑法: godot --headless --path . res://tests/verify_candy_jar.tscn --quit-after 120
##
## 覆盖 (每条打印 期望 vs 实际):
##  1. has_candy_jar 只在"统领含糖果龟且未碎"时为 true
##  2. candy_jar_add: 赢+2 / 输+3 / 封顶60(2026-10-22 改)
##  3. candy_jar_tier: 12 档区间(每 5 点一档) · 3b 每档 2~4 套、深海币不超过 45、档位越高不降
##  4. break_candy_jar: 这一档随机给一套(深海币 / 装备 / 大轮经验 / 临时等级器的组合)
##  5. ★奖励进背包后 persistent_bench 全是 Dictionary (曾塞裸 String "temp_leveler" → auto_merge_all/_equip_cell 必崩)
##  6. ★auto_merge_all() 在背包含消耗品时不崩, 且不把消耗品当装备合成
##  7. apply_temp_leveler / temp_level_bonus
##  8. 老存档迁移: 裸 String → Dictionary

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	if gs == null:
		print("✗ GameState autoload 缺失"); get_tree().quit(1); return
	gs.test_mode = true   # ★不写盘: 否则本测试会把玩家的 user://savegame.json 覆盖掉

	print("=== 1. has_candy_jar 门槛 ===")
	gs.season_leaders = ["basic", "stone", "ninja"]
	gs.candy_jar_broken = false
	_ok("统领无糖果龟 → 无罐", not gs.has_candy_jar())
	gs.season_leaders = ["candy", "stone", "ninja"]
	_ok("统领含糖果龟 → 有罐", gs.has_candy_jar())
	gs.candy_jar_broken = true
	_ok("已碎 → 无罐", not gs.has_candy_jar())
	gs.candy_jar_broken = false

	## 2026-10-22 用户「改为赢+2，输+3，封顶60，分为12档」(方案书 docs/plans/20261022-糖果罐12档.md)
	print("=== 2. 计数: 赢+2 / 输+3 / 封顶60 ===")
	gs.candy_jar_count = 0
	gs.candy_jar_add(gs.CANDY_JAR_WIN); _ok("赢+2", gs.CANDY_JAR_WIN == 2 and gs.candy_jar_count == 2, "got=%d" % gs.candy_jar_count)
	gs.candy_jar_add(gs.CANDY_JAR_LOSS); _ok("输+3", gs.CANDY_JAR_LOSS == 3 and gs.candy_jar_count == 5, "got=%d" % gs.candy_jar_count)
	gs.candy_jar_count = 58
	gs.candy_jar_add(gs.CANDY_JAR_LOSS); _ok("封顶60", gs.candy_jar_count == 60, "got=%d" % gs.candy_jar_count)

	print("=== 3. 档位区间 (每 5 点一档: 0-4=1 … 50-54=11 / 55-60=12) ===")
	for pair in [[0, 1], [4, 1], [5, 2], [9, 2], [10, 3], [24, 5], [25, 6], [34, 7], [35, 8], [49, 10], [50, 11], [54, 11], [55, 12], [60, 12]]:
		gs.candy_jar_count = int(pair[0])
		_ok("count=%d → 档%d" % [int(pair[0]), int(pair[1])], gs.candy_jar_tier() == int(pair[1]), "got=%d" % gs.candy_jar_tier())

	## ③b 每档 2~4 套、打碎随机给一套(用户「每档制定2-4种奖励，之前说错了」→ 选「每档 2~4 套，随机给一套」)
	##   任何一套深海币不超过 45(「顶档只提供45深海币」); 档位越高, 各类奖励的最好那套不降
	var tiers: Array = gs._CANDY_JAR_TIERS
	var bad_n: Array = []
	var bad_mono: Array = []
	var bad_coin: Array = []
	var best := func(packs: Array) -> Array:      # [深海币下限最高, 装备最高费, 经验最高, 等级器最多]
		var b := [0, 0, 0, 0]
		for pk in packs:
			var d: Dictionary = pk
			b[0] = maxi(int(b[0]), int((d.get("coins", [0, 0]) as Array)[0]))
			for es in d.get("equips", []):
				for c in (es as Dictionary)["cost"]:
					b[1] = maxi(int(b[1]), int(c))
			b[2] = maxi(int(b[2]), int(d.get("xp", 0)))
			b[3] = maxi(int(b[3]), int(d.get("leveler", 0)))
		return b
	for i in range(tiers.size()):
		var packs: Array = tiers[i]
		if packs.size() < 2 or packs.size() > 4:
			bad_n.append("第 %d 档 %d 套" % [i + 1, packs.size()])
		for pk in packs:
			if (pk as Dictionary).is_empty():
				bad_n.append("第 %d 档有空套" % [i + 1])
			if int(((pk as Dictionary).get("coins", [0, 0]) as Array)[1]) > 45:
				bad_coin.append("第 %d 档 %s" % [i + 1, gs.candy_jar_pack_text(pk)])
		if i > 0:
			var cur: Array = best.call(packs)
			var prev: Array = best.call(tiers[i - 1])
			for k in range(4):
				if int(cur[k]) < int(prev[k]):
					bad_mono.append("第 %d 档第 %d 类比第 %d 档低" % [i + 1, k, i])
	_ok("③b ★分母: 12 档", tiers.size() == 12, str(tiers.size()))
	_ok("③b 每档 2~4 套, 没有空套", bad_n.is_empty(), str(bad_n))
	_ok("③b 任何一套深海币不超过 45", bad_coin.is_empty(), str(bad_coin))
	_ok("③b 档位越高, 深海币 / 装备费 / 经验 / 等级器各自的最好那套不降", bad_mono.is_empty(), str(bad_mono))

	print("=== 4/5. 打碎第 12 档 60 次: 每次结果 = 抽中的那一套, 4 套都出现过 ===")
	var packs12: Array = tiers[11]
	var seen := {}
	var mismatch: Array = []
	var shape_bad: Array = []
	for n in range(60):
		gs.persistent_bench = []
		gs.persistent_equipped = {}
		gs.candy_temp_levels = {}
		gs.candy_jar_count = 60
		gs.candy_jar_broken = false
		var coins_before: int = int(gs.meta_deepsea_coins)
		var r: Dictionary = gs.break_candy_jar()
		if r.is_empty() or int(r.get("tier", 0)) != 12:
			mismatch.append("第 %d 次: tier=%s" % [n, str(r.get("tier", "-"))])
			continue
		var pi: int = int(r.get("pack", -1))
		seen[pi] = true
		var sp: Dictionary = packs12[pi]
		var cr: Array = sp.get("coins", [0, 0])
		var dc: int = int(gs.meta_deepsea_coins) - coins_before
		var eqs: Array = r.get("equips", [])
		var want_eqs: Array = sp.get("equips", [])
		var ok_eq: bool = eqs.size() == want_eqs.size()
		if ok_eq:
			for j in range(eqs.size()):
				var cost: int = int((DataRegistry.phase2_equipment_by_id.get(str((eqs[j] as Dictionary)["id"]), {}) as Dictionary).get("cost", 0))
				if not ((want_eqs[j] as Dictionary)["cost"] as Array).has(cost) or int((eqs[j] as Dictionary)["star"]) != int((want_eqs[j] as Dictionary)["star"]):
					ok_eq = false
		var lv_in_bench := 0
		var eq_in_bench := 0
		for it in gs.persistent_bench:
			if not (it is Dictionary):
				shape_bad.append("背包里有裸 String")
			elif str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
				lv_in_bench += 1
			else:
				eq_in_bench += 1
		if dc < int(cr[0]) or dc > int(cr[1]) or not ok_eq or int(r.get("xp", -1)) != int(sp.get("xp", 0)) \
				or lv_in_bench != int(sp.get("leveler", 0)) or eq_in_bench != want_eqs.size():
			mismatch.append("第 %d 次 第 %d 套: 币 %d / 装备 %s / 经验 %d / 等级器 %d" % [n, pi, dc, str(eqs), int(r.get("xp", -1)), lv_in_bench])
	_ok("④ ★分母: 第 12 档 %d 套都抽到过(60 次)" % packs12.size(), seen.size() == packs12.size(), str(seen.keys()))
	_ok("④ ★★每次到手的 = 抽中那一套(深海币在区间内、装备费档与星级、经验、等级器个数)", mismatch.is_empty(), str(mismatch.slice(0, 3)))
	_ok("⑤ ★背包全是 Dictionary (无裸 String)", shape_bad.is_empty(), str(shape_bad.slice(0, 2)))
	_ok("打碎后 has_candy_jar=false", not gs.has_candy_jar())
	_ok("is_equip_item 识别消耗品", not gs.is_equip_item(gs.TEMP_LEVELER_ITEM))

	print("=== 6. ★auto_merge_all 含消耗品不崩, 且不合消耗品 ===")
	## 每档随机给一套之后, 上面打碎留在背包里的东西不固定 ⇒ 这里自己摆: 1 个等级器 + 1 件装备
	gs.persistent_bench = [gs.TEMP_LEVELER_ITEM.duplicate(), {"id": "p2eq_001", "star": 1}]
	gs.persistent_bench.append(gs.TEMP_LEVELER_ITEM.duplicate())
	gs.persistent_bench.append(gs.TEMP_LEVELER_ITEM.duplicate())   # 3 个等级器: 若被当装备就会被合成掉
	var before: int = gs.persistent_bench.size()
	gs.auto_merge_all()                                            # 曾经在这里 String.get() 崩
	var after_levelers := 0
	for it in gs.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
			after_levelers += 1
	_ok("auto_merge_all 未崩", true)
	_ok("3 个临时等级器没被 3合1 吃掉", after_levelers == 3, "got=%d (bench %d→%d)" % [after_levelers, before, gs.persistent_bench.size()])

	print("=== 7. 临时等级器: 龟统领 ===")
	gs.candy_temp_levels = {}
	_ok("初始 +0", gs.temp_level_bonus("candy") == 0)
	gs.apply_temp_leveler("candy")
	_ok("用 1 次 → +1", gs.temp_level_bonus("candy") == 1, "got=%d" % gs.temp_level_bonus("candy"))
	gs.apply_temp_leveler("candy")
	_ok("再用 1 次 → +2 (累加)", gs.temp_level_bonus("candy") == 2, "got=%d" % gs.temp_level_bonus("candy"))
	_ok("消耗: consume_temp_leveler 移除该格", gs.consume_temp_leveler(_first_leveler_idx(gs)))

	print("=== 7b. 临时等级器: 小将 (记在阵容格子上) ===")
	var dl: Dictionary = gs.get_dual_lineup()
	var mlane := ""
	var midx := -1
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
				mlane = lane; midx = i; break
		if midx >= 0: break
	if midx < 0:
		print("  – 默认阵容无小将格, 跳过 (非失败)")
	else:
		var lv0: int = int(gs.get_dual_lineup()[mlane][midx].get("temp_lv", 0))   # 存档里可能已有值 → 断言用 delta
		var ok1: bool = gs.apply_temp_leveler_minion(mlane, midx)
		var lv: int = int(gs.get_dual_lineup()[mlane][midx].get("temp_lv", 0))
		_ok("小将 +1 级写入阵容格子", ok1 and lv == lv0 + 1, "lane=%s idx=%d temp_lv %d→%d" % [mlane, midx, lv0, lv])
		_ok("对统领格调用返回 false", not gs.apply_temp_leveler_minion(mlane, _first_leader_idx(gs, mlane)))

	print("=== 8. 老存档迁移: 裸 String → Dictionary ===")
	gs.persistent_bench = ["temp_leveler", {"id": "p2eq_001", "star": 1}]
	# 复现 load() 里的迁移逻辑 (老存档把临时等级器存成裸 String)
	for i in range(gs.persistent_bench.size()):
		if gs.persistent_bench[i] is String and str(gs.persistent_bench[i]) == gs.TEMP_LEVELER_ID:
			gs.persistent_bench[i] = gs.TEMP_LEVELER_ITEM.duplicate()
	_ok("迁移后无裸 String", not (gs.persistent_bench[0] is String))
	gs.auto_merge_all()
	_ok("迁移后 auto_merge_all 不崩", true)

	# ── 甜蜜掠夺演出重做(用户 2026-08-14:「糖果龟的被动展现方式也要改」)──────
	##   ★原来是 4 颗 `_glow_bb` 圆光球 —— 没有语义, 读不出"糖"也读不出"被抽走"。
	##   ★判据数【产品自己建的节点】: 糖粒是 Sprite3D 且用专属纹理, 不是发光公告板。
	var src_cd := FileAccess.get_file_as_string("res://scripts/systems/skills/candy_system.gd")
	_ok("★★甜蜜掠夺不再用发光圆球(_glow_bb)",
		src_cd.find("_glow_bb(from2d") < 0, "源码里还有 _glow_bb(from2d")
	_ok("★★改用专属【糖粒】纹理(菱形方糖+糖果条纹)",
		src_cd.find("VfxTex._make_candy_bit_texture") >= 0)
	_ok("★糖粒数按吸取量走(抽得多飞得多, 不用读数字也看得出量级)",
		src_cd.find("var bits: int = clampi(6 + int(amt / 60), 6, 14)") >= 0)
	_ok("★★吸收闪光收在【糖果龟自己】身上(让\"抽给了谁\"看得见)",
		src_cd.find("battle._vfx._flash(candy,") >= 0)
	var tex_ok: Texture2D = VfxTexRef._make_candy_bit_texture(Color.WHITE)
	var img_c: Image = tex_ok.get_image()
	var opaque := 0
	for yy in range(img_c.get_height()):
		for xx in range(img_c.get_width()):
			if img_c.get_pixel(xx, yy).a > 0.2: opaque += 1
	var frac := float(opaque) / float(img_c.get_width() * img_c.get_height())
	_ok("★★糖粒是【菱形】不是圆/方块(实心占比 %.0f%%, 菱形约 40~60%%)" % (frac * 100.0),
		frac > 0.25 and frac < 0.72, "实心占比 %.1f%%" % (frac * 100.0))

	# ── 糖果罐以【装备的形式】进背包(用户 2026-08-14)──────────────────────
	##   ★原来是右上角一块 372×44 的独立面板 —— 和背包里的东西不是一套语言。
	##   ★判据落在源码事实 + 复用关系上: 走同一个 `_slot_panel`(视觉同源),
	##     且打碎复用 `_on_break_jar`(不复制一份领奖逻辑)。
	var src_inv := FileAccess.get_file_as_string("res://scripts/scenes/InventoryScene.gd")
	_ok("★★糖果罐排进背包格子(合成条目 kind=candy_jar)",
		src_inv.find('{"kind": "candy_jar"') >= 0)
	_ok("★★用装备卡同一个外框 `_slot_panel`(视觉同源, 不自画一套)",
		src_inv.find("func _candy_jar_cell") >= 0 and src_inv.find("var jbox := _slot_panel(pos,") >= 0)
	_ok("★★打碎【复用】_on_break_jar(不复制领奖逻辑)",
		src_inv.find("_inv_jar._on_break_jar()") >= 0)
	_ok("★合成条目【不写进存档】(糖果罐不是可交易装备, 写进去会被卖出/升星逻辑当普通装备)",
		src_inv.find("GameState.persistent_bench.append({\"kind\": \"candy_jar\"") < 0)
	_ok("★没有糖果罐时不占格子(has_candy_jar 才注入)",
		src_inv.find("if GameState.has_candy_jar():") >= 0)
	## ★★★最要命的一条: 糖果罐是插在【最前面】的合成条目, 它不在 persistent_bench 里。
	##   而 `_equip_cell` 的 idx 会被 `_on_bench_click` 存成 `_sel_bench`,
	##   `_sel_bench` 又直接索引 `persistent_bench` ⇒ 若把渲染下标当数据下标传,
	##   **点第 1 件装备会装备/卖掉第 2 件** —— 坏存档。
	##   判据: 渲染循环里必须有独立的数据下标 `bidx`, 且合成条目不占号。
	## ── 交互用例(用户 2026-08-14:「点击装备, 下面把出售和什么按钮换成打碎就好了啊」)──
	##   ★最终形态就是【和装备一模一样】: 点一下 = 选中, 同一个位置把"卖出"换成"打碎"。
	##     我先做的自定义 gui_input + 确认弹窗是**过度设计** —— 选中本身可撤销, 不需要再弹一层。
	_ok("★★★点它 = 选中(不是直接碎) —— 用独立标记 `_sel_jar`",
		src_inv.find("_sel_jar = not _sel_jar") >= 0)
	_ok("★★★`_sel_jar` 不占 `_sel_bench`(后者直接索引 persistent_bench, 占了就索引错位)",
		src_inv.find("var _sel_jar: bool = false") >= 0
		and src_inv.find("_sel_bench = -1                              # 选糖果罐") >= 0)
	_ok("★★滑列表不误触: 位移 ≥16px 不算点击(与装备卡同一套)",
		src_inv.find("if ev.position.distance_to(_press_pos) >= 16.0:") >= 0)
	_ok("★★选装备与选糖果罐【互斥】",
		src_inv.find("_sel_jar = false                       # 选装备") >= 0)
	_ok("★★已删掉过度设计的确认弹窗(_confirm_smash_jar 不再存在)",
		src_inv.find("func _confirm_smash_jar") < 0)
	_ok("★卡面显示【档位】而不是 ×N(一大轮只能碎一次, N 是累积糖数)",
		src_inv.find('jnm.text = "%d 档" % GameState.candy_jar_tier()') >= 0)   # 格子只写档位(「糖果罐」在说明小卡)

	## ★★2026-10-22 装备改成贴着那一格弹说明小卡(InspectCard), 不再画底部操作条 ⇒ 糖果罐跟着改。
	##   原来这里 grep 两颗键的源码坐标「同一位置同一尺寸」—— 装备那条栏没了, 那两行坐标比的是一段死代码。
	##   现在【真开两张卡来比】: 走真入口(格子的 gui_input 按下 + 松开), 量卡上那颗键。
	gs.season_leaders = ["candy", "stone", "ninja"]
	gs.candy_jar_broken = false
	gs.candy_jar_count = 12
	gs.persistent_bench = [{"id": "p2eq_021", "star": 1}, {"id": "p2eq_004", "star": 1}]
	var name0 := str(DataRegistry.phase2_equipment_by_id.get("p2eq_021", {}).get("name", ""))
	var inv = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	for _i in range(10):
		await get_tree().process_frame
	## 糖果罐格子 = 带 CellName「N 档」的那一格; 它后面那个兄弟 = 背包第一件装备(渲染第 2 格)
	var jar_cell: Control = _jar_cell(inv, gs.candy_jar_tier())
	_ok("★分母: 背包里有糖果罐那一格", jar_cell != null)
	var eq_cell: Control = null
	if jar_cell != null:
		var sib: Array = jar_cell.get_parent().get_children()
		var ji: int = sib.find(jar_cell)
		if ji >= 0 and ji + 1 < sib.size():
			eq_cell = sib[ji + 1]
	_ok("★分母: 糖果罐后面紧挨着一件装备", eq_cell != null)
	## ① 渲染下标与【数据下标】分开: 糖果罐占渲染第 1 格但不占背包下标 ⇒ 点它后面那格 = 背包第 0 件
	##   (把渲染下标当数据下标传 ⇒ 选中的是第 1 件, 卖出 / 装上都会动错那一件 —— 坏存档)
	if eq_cell != null:
		_tap(eq_cell)
		for _i in range(4):
			await get_tree().process_frame
	var item_card: Node = _named(inv, "ItemInspectCard")
	var ttl: Node = _named(item_card, "Title") if item_card != null else null
	_ok("★★★渲染下标与【数据下标】分开: 点糖果罐后面那格 = 背包第 0 件(合成条目不占号)",
		int(inv._sel_bench) == 0 and ttl != null and str((ttl as Label).text) == name0,
		"sel=%d 卡标题「%s」应为「%s」" % [int(inv._sel_bench), str((ttl as Label).text) if ttl != null else "", name0])
	var sell: Button = _named(item_card, "SellBtn") as Button if item_card != null else null
	_ok("★分母: 装备的说明小卡上有「卖出」", sell != null)
	## 先记下「卖出」的位置与尺寸: 下一下点击整页重建, 这颗键随旧卡一起释放
	var sell_at := [sell.get_index(), sell.custom_minimum_size.y, sell.get_theme_font_size("font_size")] if sell != null else []
	## ② 点糖果罐那一格 ⇒ 和装备同一张小卡, 「打碎」站在「卖出」的位置
	jar_cell = _jar_cell(inv, gs.candy_jar_tier())    # 上一下点击整页重建过, 旧格子已释放
	if jar_cell != null:
		_tap(jar_cell)
		for _i in range(4):
			await get_tree().process_frame
	var jar_card: Node = _named(inv, "JarInspectCard")
	var smash: Button = _named(jar_card, "SmashBtn") as Button if jar_card != null else null
	_ok("★★点糖果罐 ⇒ 弹出说明小卡, 卡上有「打碎」", jar_card != null and smash != null)
	_ok("★★选中糖果罐时不再冒出底部操作条(和装备一样只有那张小卡)", not inv._op_bar_shows())
	_ok("★★装备小卡已收起(两张小卡不同时在)", _named(inv, "ItemInspectCard") == null)
	if not sell_at.is_empty() and smash != null:
		var smash_at := [smash.get_index(), smash.custom_minimum_size.y, smash.get_theme_font_size("font_size")]
		_ok("★打碎与卖出【同一位置同一尺寸】: 都是各自按钮行的第 1 颗、同高、同字号",
			smash_at == sell_at and int(smash_at[0]) == 0,
			"打碎 [序号, 高, 字号] %s / 卖出 %s" % [str(smash_at), str(sell_at)])
	else:
		_ok("★打碎与卖出【同一位置同一尺寸】", false, "卖出 %s / 打碎 %s" % [str(not sell_at.is_empty()), str(smash != null)])
	## ③ 按下「打碎」= 真碎(直连 `_inv_jar._on_break_jar()`, 不另起确认弹窗)
	if smash != null:
		smash.pressed.emit()
		for _i in range(3):
			await get_tree().process_frame
	_ok("★★按下「打碎」⇒ 罐子真碎了(不另起确认弹窗)", not gs.has_candy_jar())
	inv.queue_free()
	await get_tree().process_frame

	## ★糖果罐不许【同时出现在两个地方】—— 旧的右上角独立面板必须撤掉,
	##   否则玩家在背包里看到一张卡、右上角还有一块板, 是同一个东西的两份。
	var src_jar := FileAccess.get_file_as_string("res://scripts/scenes/inventory/candy_jar.gd")
	_ok("★★右上角的旧独立面板【已删】(不是留着不调 —— 死函数会被门禁假保护)",
		src_inv.find("_inv_jar._build_candy_jar()") < 0
		and src_jar.find("func _build_candy_jar") < 0)
	_ok("★但 InvCandyJar 本身保留(打碎的领奖/存档/弹窗仍由它负责)",
		src_inv.find("_inv_jar._on_break_jar()") >= 0)

	print("")
	if _fail == 0:
		print("ALL PASS — 糖果罐/临时等级器 端到端")
	else:
		print("FAIL ×", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _first_leveler_idx(gs) -> int:
	for i in range(gs.persistent_bench.size()):
		var it = gs.persistent_bench[i]
		if it is Dictionary and str(it.get("id", "")) == gs.TEMP_LEVELER_ID:
			return i
	return -1


func _first_leader_idx(gs, lane: String) -> int:
	var arr: Array = gs.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "leader":
			return i
	return -1

## 真点一下: 按下 + 松开(背包里的格子与单位卡都是「松手才算点」)。
func _tap(c: Control) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = c.size * 0.5
		c.gui_input.emit(ev)


func _all(n: Node) -> Array:
	var out: Array = []
	var st: Array = [n]
	while not st.is_empty():
		var x: Node = st.pop_back()
		out.append(x)
		st.append_array(x.get_children())
	return out


func _jar_cell(inv: Node, tier: int) -> Control:
	for n in _all(inv):
		if n is Label and str(n.name) == "CellName" and str((n as Label).text) == "%d 档" % tier \
				and not n.is_queued_for_deletion():
			return (n as Node).get_parent() as Control
	return null


func _named(root: Node, nm: String) -> Node:
	if root == null:
		return null
	for x in _all(root):
		if str(x.name) == nm and not x.is_queued_for_deletion():
			return x
	return null
