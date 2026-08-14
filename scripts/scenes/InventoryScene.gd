extends Control

const RichTooltip = preload("res://scripts/scenes/rich_tooltip.gd")

## InventoryScene — V2 局外背包 / 出战配置 (阶段2 UI 首版, 设计§十).
## 上部: 出战阵容 (上路/下路, 龟统领 + 小将占位); 下部: 装备管理 (背包 bench).
## 首版 = 布局 + 显示 (实时挤位/防吞/装备拖拽/3合1 后续迭代). 截图验证布局用.
## 数据: season_leaders(锁定3统领) 优先, 空则 lastLineup.json 末次阵容; persistent_bench(持久背包).

const W := 1280.0
const H := 720.0
const SLOT := 96.0
const P2 = preload("res://scripts/gamedata/phase2_config.gd")
const Phase2Types = preload("res://scripts/gamedata/phase2_types.gd")
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")   # 装备逐星属性表(与战斗实装同源; 2026-07-23 从回合制P2RT抽出)
const Phase2Minion = preload("res://scripts/gamedata/phase2_minion.gd")

var _sel_bench: int = -1   # 当前选中的背包装备索引 (-1=无)
var _inv_ops := InvOps.new(self)   # 背包·装备/卸下/卖出 业务逻辑(2026-07-25 抽出)
var _inv_jar := InvCandyJar.new(self)   # 背包·糖果罐(打碎领奖)(2026-07-25 抽出)
var _inv_synergy := InvSynergy.new(self)   # 背包·类型羁绊面板+详情弹框(2026-07-25 抽出)
var _dl_sel: Dictionary = {}   # 双路布阵选中框 {lane, idx} (点两个互换分路)
var _vw: float = 1280.0   # 实际视口宽(手机expand后可达~1560): 顶栏/背包按真实宽铺开·不再左挤留空(2026-07-18)
var _press_pos := Vector2.ZERO   # 背包格触屏点选/滑动判定: 松开位移小才算点选(可滑动列表·2026-07-18)

func _ready() -> void:
	if OS.has_environment("INV_DEMO"):   # dev截图用: 内存填演示背包(不save·不碰真存档)
		_inject_demo_inventory()
	if OS.has_environment("PH_DEMO"):    # dev: 清统领模拟大轮开局 → 看统领1/2/3问号占位(不save)
		GameState.season_leaders = []
		GameState.dual_lineup = {}
	_rebuild()
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null:
		_td.attach_guide(self, "inventory")        # 分步引导(带高亮: 战场/背包)
		_td.attach_next_button(self, "inventory")  # 右上"看看图鉴"推进钮
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住。)
	UIFrame.attach(self)

func _inject_demo_inventory() -> void:   # 仅 INV_DEMO 环境: 填装备看满仓布局(不调 save)
	## ★★演示环境【强制 test_mode】—— 2026-08-12 血泪: 我开着 INV_DEMO 的窗口给用户看,
	##   窗口里任何一次装/卸/换位都会 GameState.save() ⇒ **演示数据被写进玩家真实存档**
	##   (basic 身上凭空多了 3 件盾 + 2 个圣光护盾), 之后所有读存档的门禁都跟着红
	##   (verify_eq_blade_batch / verify_eq_gadget_batch 护盾数值全对不上, 我一度以为是自己改坏了)。
	##   注释里那句"不调 save"只是【本函数】不调, 挡不住界面上的任何一次操作。
	##   ⚠ 同类事故 2026-07-10 发生过一次(存档目录里还留着 `.bak-被测试污染`)。
	##   test_mode 是 GameState.save() 的第一道闸(save 头一行就 return), 所以这里直接立起来。
	GameState.test_mode = true
	GameState.season_level = 8
	var ids := ["p2eq_001", "p2eq_004", "p2eq_005", "p2eq_007", "p2eq_009", "p2eq_011", "p2eq_013", "p2eq_014", "p2eq_016", "p2eq_017", "p2eq_021", "p2eq_022", "p2eq_028", "p2eq_032", "p2eq_035", "p2eq_039", "p2eq_044", "p2eq_048", "p2eq_050", "p2eq_052", "p2eq_005", "p2eq_007"]
	GameState.persistent_bench = []
	for i in range(ids.size()):
		GameState.persistent_bench.append({"id": ids[i], "star": (i % 3) + 1})
	var leaders := _lineup_ids()
	if leaders.size() > 0:
		GameState.persistent_equipped[str(leaders[0])] = [{"id": "p2eq_001", "star": 2}, {"id": "p2eq_005", "star": 1}, {"id": "p2eq_007", "star": 1}]
	var lineup := GameState.get_dual_lineup()
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and str(u.get("kind", "")) == "minion":
				u["equips"] = [{"id": "p2eq_004", "star": 1}, {"id": "p2eq_009", "star": 2}]
				break
	GameState.dual_lineup = lineup
	## ★INV_DEMO_HOLY=1: 第一只统领装满 3 件【盾】⇒ 盾羁绊档1 ⇒ 发圣光护盾,
	##   用来【肉眼验收】"三格恒定 + 赠送件挂徽章"这件事(2026-08-12)。
	##   放这里而不是另写一套: 演示数据本来就归 _inject_demo_inventory 管。
	if OS.has_environment("INV_DEMO_HOLY"):
		## ★演示环境里 season_leaders 常常是空的(全是"?"占位) —— 那样装备写进空 id,
		##   界面上一件都看不到。先保证有三只真统领, 否则这个演示等于没开。
		##   (2026-08-12: 我第一版就这么白开了一个窗口给用户看。)
		if leaders.is_empty():
			var picks: Array = []
			for pdef in DataRegistry.launch_pets:
				if picks.size() < 3:
					picks.append(str((pdef as Dictionary).get("id", "")))
			leaders = picks
		## ★统领槽显示的 id 由 `_resolve_leader_slots` 按 **season_leaders** 回填,
		##   而 `_lineup_ids()` 可能是从 lastLineup.json 拿的 —— 两者不同步时界面全是"?"。
		##   演示里把它对齐(dev-only)。(2026-08-12: 我白开了两次窗口才查出这条。)
		GameState.season_leaders = leaders.duplicate()
		## 槽位 id 由 get_dual_lineup() 按 season_leaders 回填 ⇒ 改完要再取一次刷新
		GameState.get_dual_lineup()
		var shield_ids: Array = []
		for e in DataRegistry.phase2_equipment:
			var iid := str((e as Dictionary).get("id", ""))
			if iid != "p2eq_095" and Phase2Types.type_of(iid) == "盾" and shield_ids.size() < 6:
				shield_ids.append(iid)
		GameState.persistent_equipped[str(leaders[0])] = [
			{"id": str(shield_ids[0]), "star": 1}, {"id": str(shield_ids[1]), "star": 2},
			{"id": str(shield_ids[2]), "star": 1}]
		if leaders.size() > 1:
			GameState.persistent_equipped[str(leaders[1])] = [
				{"id": str(shield_ids[3]), "star": 1}, {"id": str(shield_ids[4]), "star": 1},
				{"id": str(shield_ids[5]), "star": 1}]
		GameState.sync_synergy_grants()
		## ★背包里也放几件盾 —— 否则这个演示只能"看", 没法自己动手装/卸试(用户 2026-08-12:
		##   「你打开的这个窗口咋放盾啊」)。装/卸都会触发 sync, 圣光护盾会当场增减。
		for sid in shield_ids:
			GameState.persistent_bench.append({"id": str(sid), "star": 1})
		## 两个赠品都装到第一只身上 —— 正是用户问的"一只龟放两个圣盾"
		for i in range(GameState.persistent_bench.size() - 1, -1, -1):
			if GameState.is_synergy_grant(GameState.persistent_bench[i]):
				(GameState.persistent_equipped[str(leaders[0])] as Array).append(
					GameState.persistent_bench[i])
				GameState.persistent_bench.remove_at(i)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _rebuild() -> void:
	# ★2026-08-01 改回设计宽(用户「有些画面都没有居中」「pc端做一板，手机端做一板」):
	#   原来这里取【真实视口宽】(手机 expand 后 ~1560)让顶栏/背包铺满, 但页面里其余元素
	#   仍按 1280 设计坐标摆 —— 于是宽屏上"一半跟着屏幕走、一半不动", 审计器实测
	#   1280→1680 时内容包围盒整体漂 +200(比不适配还乱)。
	#   现在统一走 UIFrame 设计框(内容锁 1280×720 居中·背景铺满整窗), 全屏一个口径。
	_vw = W
	for c in get_children():
		if c.is_in_group("tut_overlay"):
			continue   # ★教学浮层(引导/下一站按钮)不随重建销毁 —— 装/卸装备会触发 _rebuild
		c.visible = false   # 立即隐藏避免与新节点重叠 (queue_free 延到帧末, 不在信号中即时free防崩)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题
	var title := Label.new()
	title.text = "🎒 背包 / 出战配置"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(_vw / 2.0 - 220, 22); title.size = Vector2(440, 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# 返回
	var back := Button.new()
	back.text = "← 返回"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	add_child(back)

	# 🛒 商店 —— 商店有「→🎒背包」(ShopScene.gd:139), 反向却一直没有:
	#   背包空了想买装备, 得先退回主菜单再点商店(用户需求1「背包里加条路径去前往商店」)。
	# ★锁着时不隐藏而是【灰显 + 说明为什么】: 直接不画按钮会让人以为没这条路,
	#   而"打完第一场解锁"这条规则本身也需要被告知(ShopScene.gd:18 是同一条门槛)。
	var shop := Button.new()
	var shop_locked: bool = int(GameState.season_total_battles) <= 0
	shop.text = "🛒 商店" if not shop_locked else "🔒 商店"
	shop.add_theme_font_size_override("font_size", 20)
	shop.position = Vector2(160, 26); shop.size = Vector2(120, 44)
	shop.disabled = shop_locked
	shop.tooltip_text = "打完本大轮第一场后解锁" if shop_locked else "去商店买装备"
	shop.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Shop.tscn"))
	add_child(shop)

	# 深海币 (右上)
	var coin := Label.new()
	coin.text = "💠 深海币 %d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 22)
	coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(_vw - 260, 30); coin.size = Vector2(232, 32)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(coin)

	# ★全队装备容量计数器 (2026-07-27 新规则): 单只≤3 且 全队合计≤team_equip_cap(赛季等级)。
	#   没有这个计数器, 玩家点不上装备时只会觉得"点了没反应" —— 容量是全队共享的, 光看单只格子看不出来。
	var used := int(GameState.team_equipped_count())
	var cap := int(GameState.team_equip_cap())
	var capl := Label.new()
	capl.text = "⚙ 装备 %d / %d" % [used, cap]
	capl.add_theme_font_size_override("font_size", 18)
	capl.add_theme_color_override("font_color", Color("#ffb454") if used >= cap else Color("#9fb6c9"))
	capl.position = Vector2(_vw - 260, 62); capl.size = Vector2(232, 26)
	capl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var _nxt := int(GameState.season_level) + 1
	capl.tooltip_text = "每只统领/小将最多装 %d 件；全队 6 只合计上限随赛季等级提升。\n当前 Lv%d → %d 件%s" % [
		P2.UNIT_EQUIP_CAP, int(GameState.season_level), cap,
		("\n升到 Lv%d → %d 件" % [_nxt, P2.team_equip_cap(_nxt)]) if _nxt <= P2.MAX_LEVEL else "（已满级）"]
	add_child(capl)

	_inv_jar._build_candy_jar()

	var leaders := _lineup_ids()
	_build_lineup(leaders)
	_inv_synergy._build_synergy_panel(leaders)
	_build_bench()
	_build_op_bar()
	# ★★UIFrame 必须在【每次重建之后】重挂(用户 2026-08-01:「背包点一下后整个屏幕左移」)。
	#   本函数开头把所有子节点 queue_free —— 设计框也在里面。而 attach 原来只在 _ready 调过一次,
	#   于是点一下之后【一个框都没有】, 内容退回原始设计坐标 → 整体左移(实测宽屏下左移 140px,
	#   正好等于框的居中偏移量)。attach 是幂等的, 重复调只重新收编+居中。
	#   ★同样的坑商店踩过一次(见 ShopScene._rebuild 末尾), 当时没横向查其它屏 —— 这次补齐。
	UIFrame.attach(self)

## 取出战 3 统领: season_leaders 优先, 空则 lastLineup.json.
## ★2026-08-11 本体收拢进 GameState.lineup_leader_ids(商店/背包共用, 副本会漂)。
func _lineup_ids() -> Array:
	return GameState.lineup_leader_ids()

# ─── 上部: 双路布阵 (上战场/下战场, 3统领+3小将分3+3; 点头像互换分路, 点小将切前/后排) ───
const UBOX_W := 244.0   # 阵容单位框(再放大·填左侧空间+适手机点触·用户2026-07-19)
const UBOX_H := 116.0
const UBOX_GAP := 16.0

func _build_lineup(_leaders: Array) -> void:
	var lineup := GameState.get_dual_lineup()
	var box_span := 3.0 * UBOX_W + 2.0 * UBOX_GAP
	# "?"帮助放顶栏右侧(不占阵容区·不压返回键→修「出战阵容」压返回的重叠·用户2026-07-19)。
	# 操作引导靠单位框变色: 选了装备→框绿边"装这里" / 选中单位→框金边; 不再铺常驻文字。
	var help := Button.new()
	help.text = "?"; help.tooltip_text = "怎么配阵容"
	help.add_theme_font_size_override("font_size", 16)
	var hsb := StyleBoxFlat.new(); hsb.bg_color = Color("#1a2634"); hsb.border_color = Color("#4a6a8a")
	hsb.set_border_width_all(1); hsb.set_corner_radius_all(14)
	help.add_theme_stylebox_override("normal", hsb); help.add_theme_stylebox_override("hover", hsb); help.add_theme_stylebox_override("pressed", hsb)
	help.add_theme_color_override("font_color", Color("#9fc0dd"))
	# ★手机板触控热区(2026-08-01): 28×28 = 手机上 15pt, 点不中 → 48×48(26pt)。
	help.position = Vector2(_vw - 314.0, 20.0); help.size = Vector2(48, 48)   # 顶栏右·深海币左侧
	help.pressed.connect(func(): _show_lineup_help())
	add_child(help)
	# 两条"战场带"(染色圆角底 + 战场名 + 编成计数) → 一眼看出上/下是两个各自开打的战场
	for lane_info in [["上战场", "top", 108.0, Color("#ffd93d"), Color(0.24, 0.19, 0.06)], ["下战场", "bottom", 254.0, Color("#7fd0ff"), Color(0.05, 0.14, 0.24)]]:
		var bf := str(lane_info[0]); var lkey := str(lane_info[1]); var by := float(lane_info[2])
		var lcol: Color = lane_info[3]; var bandbg: Color = lane_info[4]
		var arr: Array = lineup.get(lkey, [])
		var lead_n := 0
		for u in arr:
			if u is Dictionary and str(u.get("kind", "")) == "leader": lead_n += 1
		var band := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(bandbg.r, bandbg.g, bandbg.b, 0.5)
		bsb.border_color = Color(lcol.r, lcol.g, lcol.b, 0.45)
		bsb.set_border_width_all(2); bsb.set_corner_radius_all(12)
		band.add_theme_stylebox_override("panel", bsb)
		band.position = Vector2(30, by - 24); band.size = Vector2(box_span + 20, UBOX_H + 28)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		var ll := Label.new()
		ll.text = "%s  %s" % ["⬆" if lkey == "top" else "⬇", bf]
		ll.add_theme_font_size_override("font_size", 16); ll.add_theme_color_override("font_color", lcol)
		ll.position = Vector2(44, by - 21); ll.size = Vector2(180, 18); add_child(ll)
		var minion_n := arr.size() - lead_n
		var ctext := ""
		if lead_n > 0:
			ctext = "统领 ×%d" % lead_n
		if minion_n > 0:
			ctext += ("　　小将 ×%d" % minion_n) if ctext != "" else ("小将 ×%d" % minion_n)
		var cnt := Label.new()
		cnt.text = ctext
		cnt.add_theme_font_size_override("font_size", 13)
		cnt.add_theme_color_override("font_color", Color(lcol.r, lcol.g, lcol.b, 0.72))
		cnt.position = Vector2(30 + box_span + 20 - 200, by - 20); cnt.size = Vector2(186, 16)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(cnt)
		for i in range(arr.size()):
			add_child(_dl_unit_box(lkey, i, arr[i], lead_n, Vector2(40 + i * (UBOX_W + UBOX_GAP), by)))

## 布阵单位框(大改): 大立绘+名+可点装备格(点填充格=卸那件)+小将前后排角标. 选中装备时整框高亮"装这里". 点框body=装备(选中时)↔互换分路.
func _dl_unit_box(lane: String, idx: int, unit: Dictionary, lead_n: int, pos: Vector2) -> Control:
	var kind := str(unit.get("kind", "minion"))
	var pid := str(unit.get("id", ""))
	var is_ph := kind == "leader" and pid == ""   # 占位统领(大轮未选统领·id空) → 显示「统领N ?」
	var sel := str(_dl_sel.get("lane", "")) == lane and int(_dl_sel.get("idx", -1)) == idx
	var is_elite := kind == "minion" and lead_n == 0 and _dl_first_minion_idx(lane) == idx
	var can_equip := _sel_bench >= 0 and not is_ph   # 选了装备 → 此框可装(占位统领无真龟·不可装)
	var bg := Color("#22304a") if is_ph else (Color("#13314a") if kind == "leader" else (Color("#4a3410") if is_elite else Color("#1a2230")))
	var bd: Color
	if sel: bd = Color("#ffd93d")
	elif can_equip: bd = Color("#7fe39a")   # 选中装备时所有单位框高亮"装这里"(含小将→一眼可装)
	elif is_ph: bd = Color("#8a97a8")   # 占位统领: 灰蓝虚位感
	else: bd = (Color("#2e5a7e") if kind == "leader" else (Color("#c79a3a") if is_elite else Color("#3a4658")))
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = bd
	sb.set_border_width_all(4 if sel else (3 if can_equip else 2)); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos; box.size = Vector2(UBOX_W, UBOX_H)
	# ── 横排卡片(用户2026-07-19: 宽框别太空): 左=大立绘/占位?, 右=名+装备格; 小将前后排pill在右上 ──
	var left_w := 102.0
	var rx := left_w + 8.0                 # 右列起点 110
	var is_reg_minion := kind == "minion" and not is_elite
	if is_ph:
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 58)
		q.add_theme_color_override("font_color", Color("#9fb2c8"))
		q.position = Vector2(6, 6); q.size = Vector2(left_w - 8, UBOX_H - 12)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(q)
	else:
		var img_path := ""
		if kind == "leader":
			img_path = "res://assets/sprites/avatars/%s.png" % pid
		else:
			img_path = "res://assets/sprites/%s" % Phase2Minion.minion_img(is_elite, str(unit.get("role", "front")) == "back")
		if ResourceLoader.exists(img_path):
			var a := TextureRect.new(); a.texture = load(img_path)
			a.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; a.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			a.position = Vector2(6, 6); a.size = Vector2(left_w - 8, UBOX_H - 12); a.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(a)
	var nm := Label.new()
	if is_ph:
		nm.text = "统领%d" % (int(unit.get("slot", idx)) + 1)
	elif kind == "leader":
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		nm.text = str(pet.get("name", pid))
	else:
		nm.text = "精英小将" if is_elite else "小将"
	nm.add_theme_font_size_override("font_size", 16); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(rx, 14); nm.size = Vector2(UBOX_W - rx - (60.0 if is_reg_minion else 8.0), 22)   # 小将留右上pill空间
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(nm)
	if is_ph:
		var hint := Label.new()
		hint.text = "选龟后填入"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color("#7f8fa0"))
		hint.position = Vector2(rx, 62); hint.size = Vector2(UBOX_W - rx - 8, 16)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(hint)
	else:
		var eqs: Array = []
		if kind == "leader":
			if GameState.persistent_equipped is Dictionary:
				eqs = GameState.persistent_equipped.get(pid, [])
		elif unit.get("equips", null) is Array:
			eqs = unit.get("equips", [])
		# ★格数【恒定 = 单只上限 3】: 三格就是"你的装备位", 布局稳定、一眼看出还能装几件。
		#   羁绊赠送件(圣光护盾)不占装备位 ⇒ 它不进这三格, 由 _build_equip_cells 画在三格
		#   【之后】的一枚小徽章上(金边 + "赠"角标)。
		#   (2026-08-12 修: 之前写死 3 格却把赠送件排在数组第 4 位 ⇒ 界面上根本看不见它;
		#    中途改成 3+N 格也不对 —— 队列里有的 3 格有的 4 格, 且第 4 格看着像"能装 4 件"。)
		_build_equip_cells(box, 60.0, eqs, P2.UNIT_EQUIP_CAP, kind == "leader", pid, lane, idx, rx)
	# 小将 前排/后排 pill (右上·精英小将=统领替身不显·用户2026-07-18)
	if is_reg_minion:
		var front := str(unit.get("role", "front")) == "front"
		var tgl := Button.new()
		tgl.text = "前排" if front else "后排"
		tgl.tooltip_text = "前排=近战挥砍 / 后排=远程射击 · 点切换"
		tgl.add_theme_font_size_override("font_size", 12)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color("#5a3410") if front else Color("#0f3646")
		tsb.border_color = Color("#e0954a") if front else Color("#4ab0d0")
		tsb.set_border_width_all(1); tsb.set_corner_radius_all(6)
		tgl.add_theme_stylebox_override("normal", tsb)
		tgl.add_theme_stylebox_override("hover", tsb)
		tgl.add_theme_stylebox_override("pressed", tsb)
		tgl.add_theme_color_override("font_color", Color("#ffdba8") if front else Color("#b8e8ff"))
		# ★手机板触控热区(2026-08-01): 50×22 = 手机上 27×12pt, 是这屏最难点的一个 →
		#   加到 56×44(30×24pt)。宽只加 6 是因为右边就是单位框边缘, 再宽会溢出框。
		tgl.position = Vector2(UBOX_W - 62.0, 8.0); tgl.size = Vector2(56, 44)
		tgl.pressed.connect(func(): _dl_toggle_role(lane, idx))
		box.add_child(tgl)
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _dl_click(lane, idx))
	return box

## 单位身上的装备格一行: 填充格显图标·点它=卸那一件(无选中时); 选中装备时格子透传→点框body装备.
func _build_equip_cells(box: Control, y: float, eqs: Array, slots: int, is_leader: bool, pet_id: String, lane: String, idx: int, x_start: float = -1.0) -> void:
	var cw := 28.0
	var gap := 5.0
	var team_full: bool = not GameState.team_has_equip_room()   # 全队预算是否已用尽(空格样式据此区分)
	## ★三格只放【占装备位】的件; 羁绊赠送件(圣光护盾)另挂徽章 —— 它不是装备位。
	##   `slot_idx` 记录每格对应 eqs 里的真实下标: 卸下要按真实下标走, 不能按格号。
	var wear: Array = []        # [{i(真实下标), it}]
	var grants: Array = []      # 同上, 羁绊赠送件
	for i in range(eqs.size()):
		if GameState.is_synergy_grant(eqs[i]):
			grants.append({"i": i, "it": eqs[i]})
		else:
			wear.append({"i": i, "it": eqs[i]})
	var total := float(slots) * cw + maxf(0.0, float(slots - 1)) * gap
	var x0 := x_start if x_start >= 0.0 else (UBOX_W / 2.0 - total / 2.0)   # x_start≥0=横排卡片右列左对齐, 否则居中
	for ci in range(slots):
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		var filled := ci < wear.size()
		if filled:
			var eid := str(((wear[ci] as Dictionary)["it"] as Dictionary).get("id", ""))
			var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
			csb.bg_color = _cost_color(int(edef.get("cost", 1)))
			csb.border_color = Color(1, 1, 1, 0.5)
		elif team_full:
			# 空格但【全队预算已满】: 压暗 + 冷边框, 与"空着可以装"明确区分 ——
			# 不区分的话玩家会对着一个看起来能装的空格反复点, 以为界面坏了。
			csb.bg_color = Color(0, 0, 0, 0.55); csb.border_color = Color("#2a3340")
		else:
			csb.bg_color = Color(0, 0, 0, 0.35); csb.border_color = Color("#3a4452")
		csb.set_border_width_all(1); csb.set_corner_radius_all(3)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(x0 + float(ci) * (cw + gap), y); cell.size = Vector2(cw, cw)
		if filled:
			var eid2 := str(((wear[ci] as Dictionary)["it"] as Dictionary).get("id", ""))
			var edef2: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid2, {})
			## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
			var ic2 := EquipIcon.make(edef2, Vector2(cw - 2, cw - 2), true)
			ic2.position = Vector2(1, 1)
			cell.add_child(ic2)
		if _sel_bench >= 0:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 装备模式: 透传→点框body装上
		elif filled:
			cell.tooltip_text = "点击卸下这件 → 回背包"
			var cci := int((wear[ci] as Dictionary)["i"])    # ★真实下标, 不是格号
			cell.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: (_inv_ops._unequip_at(pet_id, cci) if is_leader else _inv_ops._unequip_minion_at(lane, idx, cci)))
		else:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空格透传
			cell.tooltip_text = ("全队装备已满 %d / %d · 升赛季等级可再装" % [
				GameState.team_equipped_count(), GameState.team_equip_cap()]) if team_full \
				else "空槽 · 先点背包里的装备, 再点这只单位"
		box.add_child(cell)

	## ★羁绊赠送件的徽章: 排在三格【之后】, 更小 + 金边 + 右下角"赠"字 ——
	##   一眼分得出"它不占我的装备位"。点它同样能卸(卸掉也会被 sync 立刻补发回背包)。
	for gi in range(grants.size()):
		var g: Dictionary = grants[gi]
		## ★徽章比装备格【明显小一圈】+ 与三格之间留出明显空档 ——
		##   实拍自查: 只小 6px、只隔一个 gap 时, 5 个方块连成一排, 读起来像"我有 5 个装备位"。
		var gw := cw - 10.0
		var gcell := Panel.new()
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = Color("#3a2f10")
		gsb.border_color = Color("#ffd93d")
		gsb.set_border_width_all(1)
		gsb.set_corner_radius_all(3)
		gcell.add_theme_stylebox_override("panel", gsb)
		## ★放在三格【下面一行】而不是右边: 右边放不下 —— 卡片宽 244, 右列起点 110,
		##   三格占到 204, 两枚徽章排下去右沿到 258 ⇒ 溢出卡片 14px(实测算过)。
		##   下一行还有个好处: "这一排是你的装备位, 下面那个是羁绊送的"读起来更清楚。
		gcell.position = Vector2(x0 + float(gi) * (gw + 4.0), y + cw + 4.0)
		gcell.size = Vector2(gw, gw)
		var gdef: Dictionary = DataRegistry.phase2_equipment_by_id.get(
			str((g["it"] as Dictionary).get("id", "")), {})
		var gic := EquipIcon.make(gdef, Vector2(gw - 2, gw - 2), true)
		gic.position = Vector2(1, 1)
		gcell.add_child(gic)
		## ★角标用【形】不用【字】: 22px 的格子里塞个汉字既挤又土, 而"它不占装备位"这件事
		##   靠"更小 + 金边 + 右上角金角"已经说得清; 具体说明留给 tooltip。
		##   (2026-08-12 用户:「为什么要赠字」—— 拿文字补设计是偷懒。)
		var corner := ColorRect.new()
		corner.color = Color("#ffd93d")
		corner.position = Vector2(gw - 5.0, 0.0)
		corner.size = Vector2(5, 5)
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gcell.add_child(corner)
		if _sel_bench >= 0:
			gcell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			gcell.tooltip_text = "%s · 羁绊赠送(不占装备位) · 盾羁绊掉档时自动收回" % str(gdef.get("name", ""))
			var gci := int(g["i"])
			gcell.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: (_inv_ops._unequip_at(pet_id, gci) if is_leader else _inv_ops._unequip_minion_at(lane, idx, gci)))
		box.add_child(gcell)

## 卸下统领第 cell_idx 件装备 → 回背包.
func _dl_first_minion_idx(lane: String) -> int:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
			return i
	return -1

## 点布阵框: 选了装备+点统领=装备; 否则 无选中→选中, 已选中→与该框互换分路(跨/同路都行), 再点自己=取消.
func _dl_click(lane: String, idx: int) -> void:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	var unit: Dictionary = arr[idx] if idx < arr.size() and arr[idx] is Dictionary else {}
	if _sel_bench >= 0 and str(unit.get("kind", "")) == "leader":
		_inv_ops._equip_to(str(unit.get("id", "")), _sel_bench)
		return
	if _sel_bench >= 0 and str(unit.get("kind", "")) == "minion":
		_inv_ops._equip_minion(lane, idx, _sel_bench)
		return
	if _dl_sel.is_empty():
		_dl_sel = {"lane": lane, "idx": idx}
		_rebuild(); return
	var sl := str(_dl_sel.get("lane", "")); var si := int(_dl_sel.get("idx", -1))
	_dl_sel = {}
	if sl == lane and si == idx:
		_rebuild(); return
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	var tmp = a[sl][si]
	a[sl][si] = a[lane][idx]
	a[lane][idx] = tmp
	GameState.dual_lineup = a
	GameState.save()
	_rebuild()

## 点小将[前/后]: 切前排(近战挥砍×1.4) ↔ 后排(远程射击×1.5)
func _dl_toggle_role(lane: String, idx: int) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	var u = a[lane][idx]
	if u is Dictionary and str(u.get("kind", "")) == "minion":
		u["role"] = "back" if str(u.get("role", "front")) == "front" else "front"
		a[lane][idx] = u
		GameState.dual_lineup = a
		GameState.save()
		_rebuild()

func _slot_center_label(box: Control, txt: String, col: Color) -> void:
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", 13); l.add_theme_color_override("font_color", col)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
## 点格子: 选了装备+点龟=装备; 否则=单位摆位(无选中→选中, 已选中→移到该格, 占用则交换).
# (旧 _on_grid_click 阵容格子已删, 双路布阵改用 _dl_click / _dl_toggle_role)

func _slot_panel(pos: Vector2, bg: Color, border: Color) -> Panel:
	var box := Panel.new()   # Panel(非PanelContainer): 子节点自由定位, 不被容器拉伸成重叠
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg; sb.border_color = border
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos
	box.size = Vector2(SLOT, SLOT)
	return box

# ─── 右侧: 类型羁绊 (装备类型激活, 设计§十) ───
## 羁绊统计: 统领装备(persistent_equipped) + 小将装备(dual_lineup)·跟龟一样计入(用户2026-07-18)
func _show_lineup_help() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	add_child(dim)
	var bw := 560.0; var bh := 306.0
	var box := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(_vw / 2.0 - bw / 2.0, 180.0); box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(box)
	var ttl := Label.new(); ttl.text = "怎么配出战阵容"
	ttl.add_theme_font_size_override("font_size", 22); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 30); box.add_child(ttl)
	var body := Label.new()
	body.text = "· 上/下是两个各自开打的战场, 分兵布置\n· 点两个单位 = 互换它们的战场 / 位置\n· 点小将的【前排 / 后排】= 近战挥砍 ↔ 远程射击\n· 点下方背包里的装备 → 再点龟 / 小将 = 装上\n· 点单位身上的装备格 = 卸下回背包\n· 3 件同款同星装备自动合成升星"
	body.add_theme_font_size_override("font_size", 15); body.add_theme_color_override("font_color", Color("#cfe0ef"))
	body.position = Vector2(24, 58); body.size = Vector2(bw - 48, bh - 120); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(body)
	var ok := Button.new(); ok.text = "知道了"; ok.add_theme_font_size_override("font_size", 17)
	ok.position = Vector2(bw / 2.0 - 60, bh - 52); ok.size = Vector2(120, 40)
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


# ─── 下部: 装备背包 (大改: 可滑动列表·铺满宽·大格; 说明移到底部操作条) ───
func _build_bench() -> void:
	var hdr := Label.new()
	hdr.text = "装备背包　(可上下滑动)"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(40, 386); hdr.size = Vector2(_vw - 80, 26)
	add_child(hdr)
	var bench: Array = GameState.persistent_bench if GameState.persistent_bench is Array else []
	## ★★用户 2026-08-14:「还有糖果罐, 在背包里我希望是以一个装备的形式」。
	##   原来糖果罐是右上角一块 372×44 的独立面板 —— 和背包里的东西不是一套语言,
	##   玩家要在两个地方找自己的资产。现在把它**排进背包格子**, 和装备一样。
	##   ★用合成条目而不是真的写进 `persistent_bench`: 糖果罐不是可交易/可合成的装备,
	##     写进去会污染存档、被卖出/升星逻辑当成普通装备处理。
	##     合成条目只活在这一次渲染里, `kind` 打成 `candy_jar` 由 `_equip_cell` 分派。
	##   ★排在**最前面**: 它是限时资源(本大轮打碎才有奖, 切轮消失), 该第一眼看到。
	if GameState.has_candy_jar():
		bench = ([{"kind": "candy_jar", "id": "candy_jar",
			"count": int(GameState.candy_jar_count)}] as Array) + bench
	var gx := 40.0
	var top := 418.0
	var pitch := SLOT + 16.0
	var scroll_w := _vw - 2.0 * gx
	var scroll_h := 630.0 - top             # 到操作条上方
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(gx, top)
	scroll.custom_minimum_size = Vector2(scroll_w, scroll_h); scroll.size = Vector2(scroll_w, scroll_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 隐滚动条·保留拖动滚动(用户2026-07-19·跟选龟一致)
	add_child(scroll)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS   # 触屏拖动透传→ScrollContainer 滚动
	scroll.add_child(content)
	var per_row := maxi(8, int(scroll_w / (SLOT + 8.0)))
	var cpitch := SLOT + 8.0
	var min_rows := int(ceil(scroll_h / pitch))                       # 至少铺满可视区
	var used_rows := int(ceil(float(maxi(bench.size(), 1)) / float(per_row)))
	var total_cells := maxi(min_rows, used_rows) * per_row
	content.custom_minimum_size = Vector2(scroll_w - 4.0, float(int(ceil(float(total_cells) / float(per_row)))) * pitch)
	var i := 0
	for it in bench:
		var col := i % per_row
		var row := i / per_row
		content.add_child(_equip_cell(it, i, Vector2(float(col) * cpitch, float(row) * pitch)))
		i += 1
	while i < total_cells:
		var col2 := i % per_row
		var row2 := i / per_row
		content.add_child(_empty_bench_cell(Vector2(float(col2) * cpitch, float(row2) * pitch)))
		i += 1
	if bench.is_empty():
		var hint := Label.new()
		hint.text = "（背包空 — 去商店买装备）"
		hint.add_theme_font_size_override("font_size", 14); hint.add_theme_color_override("font_color", Color("#5a6675"))
		hint.position = Vector2(6, 6); hint.size = Vector2(600, 22); hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(hint)

# ─── 底部选中操作条 (大改: 替代满屏文字说明; 选中装备才显名/效果/卖出/取消) ───
func _build_op_bar() -> void:
	if _sel_bench < 0 or _sel_bench >= GameState.persistent_bench.size():
		return   # 无选中装备 → 不显底部操作条(原那行"3件同款合成"已收进"?"帮助·用户2026-07-19)
	var by := 636.0
	var bar := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#101c2a"); sb.border_color = Color("#2a3a4e")
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("panel", sb)
	var bw := _vw - 48.0
	bar.position = Vector2(24, by); bar.size = Vector2(bw, 66); add_child(bar)
	if _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size():
		var sit: Dictionary = GameState.persistent_bench[_sel_bench]
		if str(sit.get("kind", "")) == "item":
			var l := Label.new(); l.text = "🔼 临时等级器已选  →  点一只 龟 / 小将,本大轮永久 +1 级"
			l.add_theme_font_size_override("font_size", 16); l.add_theme_color_override("font_color", Color("#e6d8ff"))
			l.position = Vector2(16, 20); l.size = Vector2(bw - 320, 28); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
		else:
			var sdef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sit.get("id", "")), {})
			# ★装备文案按玩家当前星级高亮(2026-07-22): 三元组 a/b/c 里这一档亮、另两档暗。
			#   只在渲染时变换, 数据格式一个字不动 —— tooltip_number_audit 靠那个正则对账。
			var _star: int = int(sit.get("star", 1))
			var l := RichTextLabel.new()
			l.bbcode_enabled = true
			## ★★2026-08-11 从 `fit_content=true / scroll_active=false` 改成【可滚】。
			##   底栏用 `l.size = Vector2(bw - 320, 48)` 固定 48 px 高，14 号字 + 4 行距
			##   ⇒ 约 2.6 行。而装备文案中位数 116 字、**最长 327 字(084 手半剑)**，
			##   95 件里 44 件超过两行 ⇒ **将近一半的装备，玩家看不到后面几行**。
			##   与路线图 §二·五 第 6 条「图鉴详情长条目裁尾」同族。
			##   ⚠ 为什么不是"把框改高": 底栏在 y=636、高 66，下边已经贴到 720 设计框底部；
			##     往上长会撞到备战席网格(它的高度是动态算的)。**可滚是零布局风险的那个解。**
			##   门禁 `verify_inventory_text_fit` 量的是 `get_content_height()` 与框高，
			##   不是我按"每行几个字"估的。
			l.fit_content = false
			l.scroll_active = true
			l.text = "▶ %s  ★%d  (%s)   —— 点上方【龟 / 小将】装上   ·   %s" % [str(sdef.get("name", "")), _star, "费用%d" % int(sdef.get("cost", 1)), SkillText.highlight_star(str(sdef.get("effectDesc1", "")), _star)]
			l.add_theme_font_size_override("normal_font_size", 14); l.add_theme_color_override("default_color", Color("#ffd93d"))
			l.position = Vector2(16, 10); l.size = Vector2(bw - 320, 48); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
			var sv := _inv_ops._sell_value(sit)
			var sell := Button.new(); sell.text = "💰 卖出 +%d💠" % sv
			sell.add_theme_font_size_override("font_size", 16)
			sell.position = Vector2(bw - 290, 14); sell.size = Vector2(170, 38)
			sell.pressed.connect(_inv_ops._sell_selected); bar.add_child(sell)
		var cancel := Button.new(); cancel.text = "取消"
		cancel.add_theme_font_size_override("font_size", 16)
		cancel.position = Vector2(bw - 108, 14); cancel.size = Vector2(92, 38)
		cancel.pressed.connect(func(): _sel_bench = -1; _rebuild()); bar.add_child(cancel)

func _cost_color(cost: int) -> Color:   # 按费用上色(用户2026-07-19: 稀有度字段废弃, 费用才是真档位; 与旧稀有度严格1:1 → 颜色不变)
	match cost:
		2: return Color("#4ade80")
		3: return Color("#60a5fa")
		4: return Color("#c084fc")
		5: return Color("#fbbf24")
		_: return Color("#8a96a3")

func _empty_bench_cell(pos: Vector2) -> Control:
	var box := _slot_panel(pos, Color(0, 0, 0, 0.22), Color("#28323e"))
	_slot_center_label(box, "·", Color("#39434f"))
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 空格也透传拖动→可滑动
	return box

func _equip_cell(it: Dictionary, idx: int, pos: Vector2) -> Control:
	if str(it.get("kind", "")) == "candy_jar":  # 糖果罐: 以装备卡的形式排进背包(用户 2026-08-14)
		return _candy_jar_cell(it, pos)
	if str(it.get("kind", "")) == "item":       # 消耗品(临时等级器): 不是装备, 不查装备表/不显星
		return _item_cell(it, idx, pos)

	var sel := idx == _sel_bench
	var eid := str(it.get("id", ""))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var rcol := _cost_color(int(edef.get("cost", 1)))
	var box := _slot_panel(pos, Color("#2a3a1c") if sel else Color("#1c2836"), Color("#ffd93d") if sel else rcol)
	## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
	var ic2 := EquipIcon.make(edef, Vector2(44, 36))
	ic2.position = Vector2(SLOT / 2.0 - 22, 18)
	box.add_child(ic2)
	var nm := Label.new()
	nm.text = str(edef.get("name", eid))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(2, SLOT - 36); nm.size = Vector2(SLOT - 4, 32)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	var star := int(it.get("star", 1))
	var st := Label.new()
	st.text = "★".repeat(star)
	st.add_theme_font_size_override("font_size", 13)
	st.add_theme_color_override("font_color", Color("#ffd93d"))
	st.position = Vector2(0, 4); st.size = Vector2(SLOT, 18)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(st)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# tooltip: 名字/★/费用 + 【该星级全部属性加成】 + 效果(用户2026-07-19"背包里我要看到每件装备提供的属性, 必须写完整")
	# ★系统 tooltip 是纯文本, 会把 [color=..] 原样显示给玩家 —— 所以挂 rich_tooltip
	#   覆写 _make_custom_tooltip, 才能真的渲染出星级高亮。
	box.set_script(RichTooltip)
	box.tooltip_text = "[b]%s[/b]  ★%d  (费用%d)\n\n属性加成:\n%s\n\n效果: %s" % [
		str(edef.get("name", eid)), star, int(edef.get("cost", 1)),
		_stat_block(eid, star), SkillText.highlight_star(str(edef.get("effectDesc1", "（无主动效果）")), star)]
	_wire_bench_tap(box, idx)
	return box


# 背包格点选: 透传拖动给 ScrollContainer(可滑动) + 松开位移小才算点选(滑动不误选).
# ★仅认 mouse: 触屏由 emulate_mouse_from_touch(默认开) 自动转 mouse → 若同时收 touch 会【双触发】, 而 _on_bench_click 是 toggle → 选中瞬间又被切回=装不上(用户2026-07-18"背包怎么装装备"). 只认mouse则每次点选恰一次.
## 多行属性块(tooltip 用): 每行 "· 攻击力  +20"; 无属性的装备明说, 别留空
func _stat_block(eid: String, star: int) -> String:
	var rows: Array = EquipStats.stat_lines(eid, star)
	if rows.is_empty():
		return "  （本件不提供属性加成，只有效果）"
	var out: Array = []
	for kv in rows:
		out.append("  · %s  %s" % [kv[0], kv[1]])
	return "\n".join(out)


func _wire_bench_tap(box: Control, idx: int) -> void:
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_pos = ev.position
			elif ev.position.distance_to(_press_pos) < 16.0:
				_on_bench_click(idx))

# ─── 交互: 点背包装备选中 → 点龟装上 (再点已选=取消; 点龟身无选中=卸最后一件回背包) ───
func _on_bench_click(idx: int) -> void:
	_sel_bench = -1 if _sel_bench == idx else idx
	_rebuild()

## 选中的背包装备装到 pet_id (槽够才装).
func _item_cell(it: Dictionary, idx: int, pos: Vector2) -> Control:
	var sel := idx == _sel_bench
	var box := _slot_panel(pos, Color("#2a3a1c") if sel else Color("#26203a"), Color("#ffd93d") if sel else Color("#a98bd8"))
	var ic := Label.new()
	ic.text = "🔼"
	ic.add_theme_font_size_override("font_size", 30)
	ic.position = Vector2(0, 16); ic.size = Vector2(SLOT, 36)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ic)
	var nm := Label.new()
	nm.text = "临时等级器"
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e6d8ff"))
	nm.position = Vector2(2, SLOT - 36); nm.size = Vector2(SLOT - 4, 32)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(nm)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = "临时等级器 (糖果罐战利品)\n选中它 → 点一只龟统领或小将 → 该单位【本大轮】永久 +1 级 (切大轮重置)"
	_wire_bench_tap(box, idx)
	return box


# 轻量提示条 (1.4s 后淡出) — 临时等级器等一次性反馈
func _toast(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#ffd93d"))
	l.position = Vector2(W / 2.0 - 300, 96); l.size = Vector2(600, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## 新手引导高亮锚点(用户2026-07-23 D)。名字→屏幕矩形; 与 _build_lineup/_build_bench 同口径常量算。
func _tutorial_anchor(anchor: String) -> Rect2:
	match anchor:
		"lanes":     # 上/下战场两条带(教"调站位")
			var box_span: float = 3.0 * UBOX_W + 2.0 * UBOX_GAP
			return Rect2(30.0, 84.0, box_span + 20.0, 290.0)
		"backpack":  # 装备背包区(教"装装备")
			return Rect2(40.0, 386.0, _vw - 80.0, 244.0)
	return Rect2()


## 糖果罐格子 —— 长得像装备卡(同一个 `_slot_panel` 尺寸与描边), 但点击是【打碎领奖】。
## ★沿用装备卡的外框而不是自画一个: 用户要的就是"以装备的形式", 视觉必须同源;
##   自画一套会又变成"背包里有两种长得不一样的东西"。
func _candy_jar_cell(it: Dictionary, pos: Vector2) -> Control:
	var tier: int = GameState.candy_jar_tier()
	var jbox := _slot_panel(pos, Color("#2a1c36"), Color("#e79bd6"))
	jbox.tooltip_text = "糖果罐 ×%d
打碎后本大轮消失。
当前档位奖励: %s" % [
		int(it.get("count", 0)), GameState.candy_jar_tier_preview(tier)]
	var jic := Label.new()
	jic.text = "🍬"
	jic.add_theme_font_size_override("font_size", 30)
	jic.position = Vector2(0, 16); jic.size = Vector2(SLOT, 36)
	jic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jbox.add_child(jic)
	var jnm := Label.new()
	jnm.text = "糖果罐 ×%d" % int(it.get("count", 0))
	jnm.add_theme_font_size_override("font_size", 12)
	jnm.add_theme_color_override("font_color", Color("#e79bd6"))
	jnm.position = Vector2(2, SLOT - 36); jnm.size = Vector2(SLOT - 4, 32)
	jnm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jnm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jnm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jbox.add_child(jnm)
	jbox.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			## ★复用 `InvCandyJar._on_break_jar` —— 打碎的全部逻辑(领奖/存档/弹窗/重建)
			##   都在它里面。这里只换入口, **不复制一份领奖逻辑**(手抄的副本必然落后)。
			if _inv_jar != null:
				_inv_jar._on_break_jar())
	return jbox
