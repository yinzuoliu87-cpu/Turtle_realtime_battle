extends Control

## ShopScene — V2 局外商店 (阶段2, 设计§五/§十一). 10 卡货架, 用 meta_deepsea_coins 买装备入持久背包.
## 刷新固定 2 币; 买价 = 装备 cost (几费卖几深海币, 1:1, 用户 2026-07-01); 出货档随赛季总战斗数. 复用 Phase2Equip.roll_shop 出货算法.

const W := 1280.0
const H := 720.0
## 装备逐星属性表 —— 与战斗实装/背包/图鉴【同一张表】(CLAUDE.md §1: 装备属性的真事实源)
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")
## 深海币图标 —— 复用主菜单那张(MainMenuScene:564 `mic + "ic-deepsea.png"`)。
## ★用户 2026-07-28「深海币可以复用吧」: 商店原先 6 处全在打 emoji 💠(方片), 而主菜单/局内
##   是这枚螺旋贝币 —— 同一种货币两套视觉。emoji 还随系统字体变, 换机器就换样。
const COIN_TEX = preload("res://assets/sprites/menu/ic-deepsea.png")
## ★固化版式(方案书 docs/plans/20260729c-商店页重设计.md §7.3) —— 每个数都算过, 总计 716 < 720。
##   改这里要同步跑 tests/verify_shop_layout.gd(不超界 + 按钮 ≥44px)。
##   为什么不用容器自动布局: 全文件既有风格就是绝对坐标, 混两套更难维护。
const SLOT_W := 132.0        # 卡宽 (108→132)
const SLOT_H := 136.0        # 卡高 (132→136)
const GRID_X := 40.0         # 卡区左边界
const GRID_Y := 124.0        # 卡区上边界
const GRID_GAP_X := 20.0
const GRID_GAP_Y := 24.0
const PANEL_X := 800.0       # 右侧详情面板
const PANEL_W := 440.0
const PANEL_Y := 124.0
const PANEL_H := 592.0
const BENCH_Y := 484.0       # 备战席
const LINEUP_Y := 580.0      # 阵容装备(横排)
const MIN_TOUCH_H := 44.0    # 移动端触摸目标最低高度(用户2026-07-28「买经验按钮很小」: 原36不达标)
const REFRESH_COST := 2   # 刷新花费。原 phase2_config 那套(SHOP_REFRESH_BASE + shop_refresh_cost())已随死代码清理删除, 现在这里是唯一来源(2026-07-19)
const PRICE_MULT := 1        # 售价 = 装备 cost (费) × 1 = 几费卖几深海币 (用户 2026-07-01; 原 ×3 占位已改)
const Phase2Equip = preload("res://scripts/gamedata/phase2_equip.gd")
const P2 = preload("res://scripts/gamedata/phase2_config.gd")

var _offer: Array = []
var _rng := RandomNumberGenerator.new()
var _tut_coin: Label = null   # 教学高亮"深海币"锚点(每次 _rebuild 重设)
var _sel: int = -1            # 当前选中的货架格(两步购买: 点卡选中 → 面板里确认)
## 当前选中的【已拥有装备】id。与 _sel 互斥: 选了货架格就清空它, 反之亦然。
## ★为什么要这个: 背包格/龟身格原来只有 tooltip_text 能看名字 —— 手机没有 hover, 等于看不到。
##   这正是本次重设计要根治的坑(货架卡片的描述原来也藏在 tooltip 里), 底部两栏当时漏了。
##   现在点一下就把详情送进右侧同一块面板, 不新开弹窗。
var _sel_own: String = ""
var _sel_own_star: int = 1

func _ready() -> void:
	var _td = get_node_or_null("/root/TutorialDirector")
	var _in_tut: bool = _td != null and _td.is_active()
	if int(GameState.season_total_battles) <= 0 and not _in_tut:
		_build_locked()   # 商店锁: 本大轮未打第一场 → 不开店(用户2026-07-18「商店打完第一场后解锁」)
		return             # ★教学沙盒不计战斗数(不给奖励)→ 会永远锁; 教学模式旁路开店(用户2026-07-23"教买装备")
	_rng.randomize()
	# ★货架要跨场景保留 —— 原来这里无条件 _roll(), 于是每次退出重进都重掷:
	#   买掉的位子会复活、看中的货被冲掉(用户 2026-07-21 报的 bug)。
	#   现在只有【打完新的一场】(season_total_battles 变了)才自动换货, 否则恢复上次的货架。
	if not _restore_offer():
		_roll()
	_rebuild()
	if OS.has_environment("SHOP_SHOT"):   # dev: 商店自截图(SHOP_SHOT=秒 SHOT_SEL=选中第几格 SHOT_OUT=路径)·截完自退
		_shop_selfshot()
		return
	if _td != null:
		_td.attach_guide(self, "shop")          # 分步引导(带高亮: 币/货架)
		_td.attach_next_button(self, "shop")    # 右上"去背包"推进钮


## dev 商店自截图: 等 SHOP_SHOT 秒 → 抓主视口存 SHOT_OUT → 退。SHOT_SEL=N 可先选中第 N 格(验详情面板)。
## ★照 CodexScene._codex_selfshot 同一套 —— 开发机跑重载 3D 窗口必 BSOD(memory: project-machine-bsod-during-tests),
##   但商店是纯 2D 轻 I/O, 可以开窗口截图。
func _shop_selfshot() -> void:
	var sv := OS.get_environment("SHOP_SHOT")
	var delay := sv.to_float() if sv.is_valid_float() and sv.to_float() > 0.1 else 1.0
	# SHOT_OWNED=N: 往背包塞 N 件【当前选中那格】的同款, 好让三合一圆点亮起来 ——
	# 否则空存档下 owned=0, 圆点全灭, 截图看不出这块做没做对。
	var ow := OS.get_environment("SHOT_OWNED")
	if ow.is_valid_int() and int(ow) > 0:
		var si: int = int(OS.get_environment("SHOT_SEL")) if OS.get_environment("SHOT_SEL").is_valid_int() else 0
		if si >= 0 and si < _offer.size() and _offer[si] != null:
			for _k in range(int(ow)):
				GameState.persistent_bench.append({"id": str((_offer[si] as Dictionary).get("id", "")), "star": 1})
	if OS.get_environment("SHOT_SEL") != "":
		_sel = int(OS.get_environment("SHOT_SEL"))
	_rebuild()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT") if OS.get_environment("SHOT_OUT") != "" else "res://_shop.png")
	get_tree().quit()

## 从 GameState 恢复货架。成功返回 true; 货架不存在/已过期(打过新战斗)返回 false。
func _restore_offer() -> bool:
	if int(GameState.meta_shop_battles) != int(GameState.season_total_battles):
		return false      # 打过新的一场 → 该换货了
	var saved: Array = GameState.meta_shop_offer
	if saved.is_empty():
		return false
	_offer = []
	for row in saved:
		if row == null:
			_offer.append(null)          # 这一格已经买走, 保持空
			continue
		var eid := str((row as Dictionary).get("id", ""))
		var found = null
		for e in DataRegistry.phase2_equipment:
			if str((e as Dictionary).get("id", "")) == eid:
				found = e
				break
		_offer.append(found)             # 数据里查无此装备(改过json) → null, 不崩
	return true

## 把当前货架写回 GameState(只存 id, 不存整份装备字典 —— 存档不膨胀且不会存旧数值)
func _persist_offer() -> void:
	var out: Array = []
	for it in _offer:
		if it == null:
			out.append(null)
		else:
			out.append({"id": str((it as Dictionary).get("id", ""))})
	GameState.meta_shop_offer = out
	GameState.meta_shop_battles = int(GameState.season_total_battles)

## 商店上锁屏 (大轮开局·未打第一场): 提示 + 返回, 不出货架
func _build_locked() -> void:
	var vw := maxf(W, get_viewport_rect().size.x)
	var bg := ColorRect.new()
	bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var lbl := Label.new()
	lbl.text = "🔒 商店未开\n\n本大轮打完第一场战斗后开店"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 320.0, 250.0); lbl.size = Vector2(640, 180)
	add_child(lbl)
	var back := Button.new()
	back.text = "← 返回"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	_skin_button(back); add_child(back)

func _shop_level() -> int:
	return clampi(int(GameState.season_level), 1, 10)   # 大轮等级驱动出货档 (用户 2026-06-27)

func _roll() -> void:
	# 用户2026-07-18: 已3星(满星)的装备不再出现在货架(买了也没用·避免占位)
	var maxed := _maxed_item_ids()
	var pool: Array = DataRegistry.phase2_equipment
	if not maxed.is_empty():
		pool = []
		for e in DataRegistry.phase2_equipment:
			if not maxed.has(str((e as Dictionary).get("id", ""))):
				pool.append(e)
	_offer = Phase2Equip.roll_shop(pool, _shop_level(), 10, _rng)
	_persist_offer()   # 掷完立刻落盘, 否则退出重进又变了

# 玩家已有 3 星(满星)的装备 id 集合(背包+统领已装+小将已装)→ 商店 roll 时排除
func _maxed_item_ids() -> Dictionary:
	var s := {}
	for it in GameState.persistent_bench:
		if it is Dictionary and int(it.get("star", 1)) >= 3: s[str(it.get("id", ""))] = true
	if GameState.persistent_equipped is Dictionary:
		for pid in GameState.persistent_equipped:
			for it2 in GameState.persistent_equipped[pid]:
				if it2 is Dictionary and int(it2.get("star", 1)) >= 3: s[str(it2.get("id", ""))] = true
	if GameState.has_method("get_dual_lineup"):
		var lineup: Dictionary = GameState.get_dual_lineup()
		for lk in ["top", "bottom"]:
			for u in lineup.get(lk, []):
				if u is Dictionary and u.get("equips") is Array:
					for it3 in u["equips"]:
						if it3 is Dictionary and int(it3.get("star", 1)) >= 3: s[str(it3.get("id", ""))] = true
	return s

func _price(edef: Dictionary) -> int:
	return maxi(1, int(edef.get("cost", 1))) * PRICE_MULT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _rebuild() -> void:
	for c in get_children():
		if c.is_in_group("tut_overlay"):
			continue   # ★教学浮层(引导/下一站按钮)不能随重建销毁 —— 买装备会触发 _rebuild
		c.visible = false
		c.queue_free()
	var bg := ColorRect.new(); bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)

	# ── 头部 y 0–96 (原 0–130, 压缩 34px 腾给卡区; 币与等级并到同一行) ──
	var title := Label.new(); title.text = "🛒 深海商店"
	title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(W / 2.0 - 160, 16); title.size = Vector2(320, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title)

	var back := Button.new(); back.text = "← 返回"; back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 22); back.size = Vector2(120, MIN_TOUCH_H)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")); _skin_button(back); add_child(back)

	var inv := Button.new(); inv.text = "🎒 背包"; inv.add_theme_font_size_override("font_size", 20)
	inv.position = Vector2(160, 22); inv.size = Vector2(120, MIN_TOUCH_H)
	inv.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Inventory.tscn")); _skin_button(inv); add_child(inv)

	# ★图标在左、数字在右, 两者【不能重叠】——
	#   第一版我把图标放在 W-424, 而数字标签右对齐正好收在 W-390 → 数字整个被图标盖住,
	#   截图上只剩一枚币、看不到余额。门禁④当时只查"按钮被压", 压的是 Label 就漏了(已补⑦)。
	_coin_icon(self, Vector2(W - 520, 25), 32.0)
	var coin := Label.new(); coin.text = "%d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 24); coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(W - 482, 24); coin.size = Vector2(96, 34)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; add_child(coin)
	_tut_coin = coin   # 教学高亮"币"锚点

	var lv := Label.new()
	lv.text = "Lv%d  XP %d/%d" % [int(GameState.season_level), int(GameState.season_xp), P2.xp_to_next(int(GameState.season_level))]
	lv.add_theme_font_size_override("font_size", 17); lv.add_theme_color_override("font_color", Color("#ffd93d"))
	lv.position = Vector2(W - 380, 28); lv.size = Vector2(130, 26)   # 原(W-350,120)止于1050, 与买经验(起1032)重叠18px
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(lv)

	# 买经验: 200×36 字号15 → 220×48 字号18 (用户2026-07-28「买经验按钮很小」·移动端触摸目标 ≥44px)
	var bxp := Button.new(); bxp.text = "买经验 4 → +4XP"
	bxp.add_theme_font_size_override("font_size", 18)
	bxp.position = Vector2(W - 244, 20); bxp.size = Vector2(216, 48)
	_coin_button_icon(bxp, 20)
	bxp.pressed.connect(func(): if GameState.buy_season_xp(): _rebuild())
	_skin_button(bxp); add_child(bxp)

	_build_odds_row()   # 出货概率行 y 96–124 (原在 116, 现紧贴卡区上方)

	# ── 卡区 5×2  x 40–780 / y 124–420 ──
	for i in range(_offer.size()):
		var col := i % 5
		var row := i / 5
		add_child(_card(i, Vector2(GRID_X + col * (SLOT_W + GRID_GAP_X), GRID_Y + row * (SLOT_H + GRID_GAP_Y))))

	var rf := Button.new(); rf.text = "刷新  -%d" % REFRESH_COST
	rf.add_theme_font_size_override("font_size", 20)
	rf.position = Vector2(GRID_X + 260, 436); rf.size = Vector2(220, 48)
	_coin_button_icon(rf, 20)
	rf.pressed.connect(_on_refresh); _skin_button(rf); add_child(rf)

	_build_detail_panel()   # ★右侧常驻详情面板(本次重设计的核心: 描述不再藏在 tooltip 里)
	_build_bench_preview()
	_build_lineup_equips()

## ★#2 出货概率行(云顶式): 当前大轮等级下各费用档(1-5)的出货概率%. 每费用色=对应稀有度色, 0%淡显.
func _build_odds_row() -> void:
	var odds: Array = P2.shop_cost_odds(_shop_level())   # [费1% .. 费5%]
	var cost_cols := ["#9aa0b0", "#4ade80", "#60a5fa", "#c084fc", "#fbbf24"]   # 费1-5: 普通灰/精良绿/稀有蓝/史诗紫/传说金
	var row := HBoxContainer.new()
	row.position = Vector2(GRID_X, 96); row.size = Vector2(740, 24)   # y96–120: 紧贴卡区上方(原116会压进卡区)
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var lbl := Label.new(); lbl.text = "出货概率"
	lbl.add_theme_font_size_override("font_size", 15); lbl.add_theme_color_override("font_color", Color("#8aa0b4"))
	row.add_child(lbl)
	for c in range(5):
		var pct: int = int(odds[c]) if c < odds.size() else 0
		var chip := Label.new()
		chip.text = "%d费 %d%%" % [c + 1, pct]
		chip.add_theme_font_size_override("font_size", 16)
		var cc := Color(cost_cols[c])
		chip.add_theme_color_override("font_color", cc if pct > 0 else Color(cc.r, cc.g, cc.b, 0.28))
		row.add_child(chip)

## 商店下部背包预览 (设计§十一: 显装备管理方便对照/3合1; 详细操作回背包页).
func _build_bench_preview() -> void:
	var bench: Array = GameState.persistent_bench
	var bh := Label.new()
	# ★原文案是「我的背包 (N 件) — 回 🎒 背包页 装备/合星/卖」——
	#   用户 2026-07-28:「你那下面写背包那么多字意义在哪里」。确实没意义:
	#   顶部已经有一个「🎒 背包」按钮, 后半句只是在解释背包页能干嘛 = 教程文字不是界面。
	#   删掉, 改成告诉玩家【这里能点】(因为现在它真的能点了)。
	bh.text = "我的背包 %d 件%s" % [bench.size(), "   · 点格子看详情" if bench.size() > 0 else ""]
	bh.add_theme_font_size_override("font_size", 15); bh.add_theme_color_override("font_color", Color("#9fb6c9"))
	bh.position = Vector2(GRID_X, BENCH_Y); bh.size = Vector2(740, 22); add_child(bh)   # 原(80,560)宽900会伸进详情面板
	var n := mini(10, bench.size())   # 14×72=1008 会伸出左栏(740) → 收到 10 件
	for j in range(n):
		var it: Dictionary = bench[j]
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("#162230"); csb.border_color = _cost_color(int(edef.get("cost", 1)))
		csb.set_border_width_all(2); csb.set_corner_radius_all(6)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(GRID_X + j * 72, BENCH_Y + 26); cell.size = Vector2(64, 64); add_child(cell)
		if str(it.get("id", "")) == _sel_own and int(it.get("star", 1)) == _sel_own_star:
			csb.border_color = Color("#ffd93d"); csb.set_border_width_all(3)
		_wire_own_tap(cell, str(it.get("id", "")), int(it.get("star", 1)))
		var img := str(edef.get("img", ""))
		if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
			var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.position = Vector2(14, 6); ic.size = Vector2(36, 32); cell.add_child(ic)
		var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
		st.add_theme_font_size_override("font_size", 11); st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.position = Vector2(0, 44); st.size = Vector2(64, 16); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(st)
	if bench.is_empty():
		var e := Label.new(); e.text = "（空 — 上面买几件）"
		e.add_theme_font_size_override("font_size", 14); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(GRID_X + 4, BENCH_Y + 28); e.size = Vector2(400, 22); add_child(e)

# 右侧只读面板: 出战阵容(上/下路6单位)每个龟/小将身上装了什么(用户2026-07-18「商店里看不到装备在龟身上的东西」)。在🎒背包页调整; 这里只看。
func _build_lineup_equips() -> void:
	var lineup: Dictionary = GameState.get_dual_lineup() if GameState.has_method("get_dual_lineup") else {}
	# ★竖排 6 行(原 px=730 / y=178+row*56) → 横排 6 列, 挪到底部 LINEUP_Y。
	#   原位置在右侧 x730, 与本次新增的详情面板(x800)和第5列卡片重叠 —— 截图才看出来。
	var hdr := Label.new(); hdr.text = "🐢 出战阵容 · 已装备（回 🎒 背包页调整）"
	hdr.add_theme_font_size_override("font_size", 15); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(GRID_X, LINEUP_Y); hdr.size = Vector2(740, 20); add_child(hdr)
	var row := 0
	for lk in ["top", "bottom"]:
		for u in (lineup.get(lk, []) as Array):
			if not (u is Dictionary): continue
			var cx := GRID_X + row * 124.0    # 横排: 每格 124px 宽 × 6 = 744 ≈ 左栏宽
			var y := LINEUP_Y + 24.0
			row += 1
			var is_leader := str(u.get("kind", "")) == "leader"
			var nm := ""
			if is_leader:
				nm = str(DataRegistry.pet_by_id.get(str(u.get("id", "")), {}).get("name", u.get("id", "龟")))
			elif bool(u.get("elite", false)):
				nm = "精英小将"
			else:
				nm = "近战小将" if str(u.get("role", "front")) == "front" else "远程小将"
			var nl := Label.new(); nl.text = "%s·%s" % ["上" if lk == "top" else "下", nm]
			nl.add_theme_font_size_override("font_size", 13); nl.add_theme_color_override("font_color", Color("#e8f2ff"))
			nl.position = Vector2(cx, y); nl.size = Vector2(118, 20); nl.clip_text = true; add_child(nl)
			var eqs: Array = []
			if is_leader:
				var pe = GameState.persistent_equipped.get(str(u.get("id", "")), []) if GameState.persistent_equipped is Dictionary else []
				if pe is Array: eqs = pe
			elif u.get("equips") is Array:
				eqs = u["equips"]
			# ★空位画【3 个空槽方框】而不是写「（无装备）」——
			#   原来这里是一行小灰字, 6 只龟全空时底部就是 6 行同样的灰字, 一大片死区。
			#   空槽方框既占住位置说明"这里能放 3 件", 又和有装备时的格子对齐, 一眼看懂。
			if eqs.is_empty():
				for ci0 in range(3):
					var hole := Panel.new()
					var hsb := StyleBoxFlat.new()
					hsb.bg_color = Color(1, 1, 1, 0.03)
					hsb.border_color = Color(1, 1, 1, 0.10)
					hsb.set_border_width_all(1); hsb.set_corner_radius_all(6)
					hole.add_theme_stylebox_override("panel", hsb)
					hole.position = Vector2(cx + ci0 * 40, y + 22); hole.size = Vector2(36, 36)
					hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
					add_child(hole)
			else:
				for ci in range(mini(eqs.size(), 3)):   # 横排每列只放得下 3 格(3×40=120)
					var it: Dictionary = eqs[ci]
					var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
					var cell := Panel.new()
					var csb := StyleBoxFlat.new(); csb.bg_color = Color("#162230")
					csb.border_color = _cost_color(int(edef.get("cost", 1))); csb.set_border_width_all(2); csb.set_corner_radius_all(6)
					cell.add_theme_stylebox_override("panel", csb)
					cell.position = Vector2(cx + ci * 40, y + 22); cell.size = Vector2(36, 36)
					# ★不要只靠 tooltip —— 手机没有 hover, 这正是本次重设计要根治的坑
					#   (货架卡片的描述原来就藏在 tooltip 里)。这里补一行常驻的名字。
					#   tooltip 保留给桌面端当补充, 但不再是【唯一】途径。
					cell.tooltip_text = "%s ★%d" % [str(edef.get("name", "?")), int(it.get("star", 1))]
					add_child(cell)
					if str(it.get("id", "")) == _sel_own and int(it.get("star", 1)) == _sel_own_star:
						csb.border_color = Color("#ffd93d"); csb.set_border_width_all(3)
					_wire_own_tap(cell, str(it.get("id", "")), int(it.get("star", 1)))
					var enm := Label.new(); enm.text = str(edef.get("name", "?"))
					enm.add_theme_font_size_override("font_size", 10)
					enm.add_theme_color_override("font_color", Color("#7f93a6"))
					enm.clip_text = true
					enm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					enm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					enm.mouse_filter = Control.MOUSE_FILTER_IGNORE
					enm.position = Vector2(cx + ci * 40, y + 59); enm.size = Vector2(36, 14)
					add_child(enm)
					var img := str(edef.get("img", ""))
					if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
						var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
						ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
						ic.position = Vector2(4, 2); ic.size = Vector2(28, 24); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(ic)
					var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
					st.add_theme_font_size_override("font_size", 10); st.add_theme_color_override("font_color", Color("#ffd93d"))
					st.position = Vector2(0, 24); st.size = Vector2(36, 12); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)
	if row == 0:
		var e2 := Label.new(); e2.text = "（尚未编排出战阵容 · 去背包/选龟）"
		e2.add_theme_font_size_override("font_size", 14); e2.add_theme_color_override("font_color", Color("#5a6675"))
		e2.position = Vector2(GRID_X, LINEUP_Y + 24); e2.size = Vector2(400, 22); add_child(e2)

# 已拥有该装备件数(背包+统领已装+小将已装): 商店卡标"已有N"→知道再买几件凑3合1升星(用户2026-07-18"看不到已装备/不知道多少件才2/3星")
## 已拥有的【指定星级】件数。★star 参数不是可有可无的 ——
##
## GameState.auto_merge_all() 的合成键是 "id|star": 必须【同 id 且同星】的 3 件才合。
## 本函数原先不分星级地数, 于是探针(tests/verify_shop_merge_pips.gd)实测到:
##   背包 1×★2 + 1×★1 → 数出 2 → 商店显示「合成进度 2/3」、圆点亮 2 颗
##   再买 1 件 ★1 → ★1=2 / ★2=1, 【根本没合成】—— 显示在骗人。
## 商店只卖 ★1, 所以进度一律按 ★1 数。
func _owned_count(item_id: String, star: int = 1) -> int:
	if item_id == "": return 0
	var n := 0
	for it in GameState.persistent_bench:
		if it is Dictionary and str(it.get("id", "")) == item_id and int(it.get("star", 1)) == star: n += 1
	if GameState.persistent_equipped is Dictionary:
		for pid in GameState.persistent_equipped:
			for it2 in GameState.persistent_equipped[pid]:
				if it2 is Dictionary and str(it2.get("id", "")) == item_id and int(it2.get("star", 1)) == star: n += 1
	if GameState.has_method("get_dual_lineup"):
		var lineup: Dictionary = GameState.get_dual_lineup()
		for lk in ["top", "bottom"]:
			for u in lineup.get(lk, []):
				if u is Dictionary and u.get("equips", null) is Array:
					for it3 in u["equips"]:
						if it3 is Dictionary and str(it3.get("id", "")) == item_id and int(it3.get("star", 1)) == star: n += 1
	return n

func _cost_color(cost: int) -> Color:   # 按费用上色(用户2026-07-19: 稀有度字段废弃, 费用才是真档位; 与旧稀有度严格1:1 → 颜色不变)
	match cost:
		2: return Color("#4ade80")
		3: return Color("#60a5fa")
		4: return Color("#c084fc")
		5: return Color("#fbbf24")
		_: return Color("#8a96a3")

func _card(idx: int, pos: Vector2) -> Control:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	var bought: bool = _offer[idx] == null
	var sel: bool = (idx == _sel) and not bought
	# ★描边交给新生成的卡框(card-frame.png)去表现, 这里只留底色。
	#   原来是 2px 纯色描边 —— 费用档只靠"边框换个颜色"区分, 没有任何材质差异, 是最
	#   "程序员画的"的一处。现在: 底色随费用档微调 + 卡框按费用档染色, 选中时整框转金。
	sb.bg_color = Color("#11202e") if not bought else Color("#0c141c")
	if sel:
		sb.bg_color = Color("#1c3348")
	sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos; box.size = Vector2(SLOT_W, SLOT_H)
	if not bought:
		var fr := _nine(box, CARD_TEX, CARD_MARGIN, Vector2.ZERO, Vector2(SLOT_W, SLOT_H), 1)
		# 框本身是冷蓝的, 用 modulate 染成该费用档的色相 —— 一眼看出贵贱, 不用读"N费"
		fr.modulate = Color("#ffd93d") if sel else _cost_color(int((_offer[idx] as Dictionary).get("cost", 1))).lerp(Color(1, 1, 1), 0.35)
	if bought:
		var sold := Label.new(); sold.text = "已购"
		sold.add_theme_color_override("font_color", Color("#4a5663")); sold.add_theme_font_size_override("font_size", 16)
		sold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sold.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(sold)
		return box
	var edef: Dictionary = _offer[idx]
	var cost := Label.new(); cost.text = "%d 费" % int(edef.get("cost", 1))
	cost.add_theme_font_size_override("font_size", 12); cost.add_theme_color_override("font_color", Color("#9fb6c9"))
	cost.position = Vector2(0, 13); cost.size = Vector2(SLOT_W, 17); cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cost)
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.position = Vector2(SLOT_W / 2.0 - 27, 32); ic.size = Vector2(54, 50)
		box.add_child(ic)
	var nm := Label.new(); nm.text = str(edef.get("name", edef.get("id", "?")))
	nm.add_theme_font_size_override("font_size", 15); nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.position = Vector2(11, 84); nm.size = Vector2(SLOT_W - 22, 20)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.clip_text = true
	box.add_child(nm)
	# ★卡面【不放】效果摘要(用户 2026-07-28:「小卡片内别加摘要」)。
	#   我原本放了一行截断摘要, 理由是"10 件商品 1 个详情面板, 没摘要就得点 10 次"。
	#   但卡宽 132 只放得下约 11 个字, 截断句在卡上又小又碎 —— 用户拍板砍掉,
	#   完整描述【全部交给右侧详情面板】(字号也加大到 18)。
	#   腾出的 16px 给了图标和名字, 见下面的 y 排布。
	var owned := _owned_count(str(edef.get("id", "")))   # 已拥有件数(凑3件同款同星→自动升星)
	if owned > 0:
		# 卡角也用圆点(与详情面板同一套视觉), 不再写「已有N」——
		# 一眼看出离三合一还差几颗, 比数字更快。
		_merge_pips(box, Vector2(SLOT_W - 44, 15), owned, 8.0)
	var price := _price(edef)
	var afford := int(GameState.meta_deepsea_coins) >= price
	_coin_icon(box, Vector2(SLOT_W / 2.0 - 25, SLOT_H - 33), 18.0)
	var pr := Label.new(); pr.text = "%d" % price
	pr.add_theme_font_size_override("font_size", 16)
	pr.add_theme_color_override("font_color", Color("#5fd0e0") if afford else Color("#ff6b6b"))
	pr.position = Vector2(SLOT_W / 2.0 - 2, SLOT_H - 36); pr.size = Vector2(46, 24); pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(pr)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ★不再用 tooltip 放描述 —— 手机没有 hover, 那是"看不到装备描述"的直接原因(用户2026-07-28)。
	#   描述改由右侧【常驻】详情面板显示; 点卡只负责【选中】, 买要在面板里再确认一次(防误触花钱)。
	box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _on_select(idx))
	return box


## 点卡 → 选中(两步购买第一步)。再点同一张 = 取消选中。
func _on_select(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	_sel = -1 if _sel == idx else idx
	_sel_own = ""          # 与"已拥有"选中互斥 —— 同一块面板同时只讲一件事
	_rebuild()


## 把"已拥有的某件装备"接成可点。
## ★只认 mouse: 触屏由 emulate_mouse_from_touch(默认开)自动转 mouse; 若同时收 touch 会
##   【双触发】, 而这是 toggle → 点一下等于选中又取消(背包页 _wire_bench_tap 就踩过这个)。
func _wire_own_tap(cell: Control, eid: String, star: int) -> void:
	if eid == "":
		return
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_select_own(eid, star))


func _on_select_own(eid: String, star: int) -> void:
	if _sel_own == eid and _sel_own_star == star:
		_sel_own = ""                       # 再点一次 = 取消
	else:
		_sel_own = eid
		_sel_own_star = star
		_sel = -1                           # 与货架格选中互斥
	_rebuild()


## ★右侧常驻详情面板 —— 本次重设计的核心。
## 用户 2026-07-28:「商店页面看不到装备的描述」+「你要一劳永逸的改」
## → 所以详情是【常驻可见的面板】, 不是又一个"要触发才出现"的提示(tooltip/弹窗都不行:
##   图鉴当初就是因为 hover 在手机上不存在, 才补的点击弹窗; 商店这里直接做成常驻)。
func _build_detail_panel() -> void:
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	# 底板只负责填色; 外框改用新生成的 panel-frame.png(海带/贝壳纹 + 金角托 + 青内框)
	sb.bg_color = Color("#0e1a26")
	sb.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(PANEL_X, PANEL_Y); box.size = Vector2(PANEL_W, PANEL_H)
	add_child(box)
	_nine(box, PANEL_TEX, PANEL_MARGIN, Vector2.ZERO, Vector2(PANEL_W, PANEL_H), 1)

	# ★面板有两种来源: 货架格(可买) / 已拥有的某件(只看)。同一块面板, 不新开弹窗 ——
	#   底部背包格和龟身格原来只有 tooltip_text 能看名字, 手机没 hover = 看不到。
	var own_mode := false
	var own_star := 1
	var edef: Dictionary = {}
	if _sel_own != "":
		edef = DataRegistry.phase2_equipment_by_id.get(_sel_own, {})
		own_mode = not edef.is_empty()
		own_star = _sel_own_star
	if not own_mode and (_sel < 0 or _sel >= _offer.size() or _offer[_sel] == null):
		var hint := Label.new()
		hint.text = "← 点货架卡片看详情\n点下面的格子看已有装备"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color("#5b7a92"))
		hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(hint)
		return

	if not own_mode:
		edef = _offer[_sel]
	var cost := int(edef.get("cost", 1))
	var price := _price(edef)
	var owned := _owned_count(str(edef.get("id", "")), own_star if own_mode else 1)
	var coins := int(GameState.meta_deepsea_coins)

	# 图标 + 名称 + 费用
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new(); ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.position = Vector2(34, 32); ic.size = Vector2(66, 58)
		box.add_child(ic)
	var nm := Label.new(); nm.text = str(edef.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 24)
	nm.add_theme_color_override("font_color", _cost_color(cost))
	nm.position = Vector2(112, 36); nm.size = Vector2(PANEL_W - 148, 32)
	box.add_child(nm)
	var cl := Label.new(); cl.text = "%d 费" % cost
	cl.add_theme_font_size_override("font_size", 16)
	cl.add_theme_color_override("font_color", Color("#9fb6c9"))
	cl.position = Vector2(112, 70); cl.size = Vector2(160, 22)
	box.add_child(cl)

	_panel_sep(box, 104)

	# ★完整效果描述(常驻可见) —— 富文本走 RichTextLabel, 与图鉴同口径
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = false
	desc.scroll_active = true
	# 字号 16 → 18(用户 2026-07-28:「这么小的字?」)。卡面摘要砍掉后, 完整描述全靠这一块。
	desc.add_theme_font_size_override("normal_font_size", 18)
	desc.position = Vector2(34, 116); desc.size = Vector2(PANEL_W - 68, 214)
	desc.text = _rich_desc(edef)
	box.add_child(desc)
	# ★59 件里有 1 件(玩偶小熊 297px > 框 230)一屏放不下 —— 门禁⑥量出来的。
	#   不加提示的话, 玩家看到的是"描述断在半句", 会以为是 bug 而不是"可以滚"。
	_add_scroll_hint(box, desc)

	_panel_sep(box, 344)

	# ★属性数值 —— 商店原先【一个数字都不显示】: 花钱买之前看不到它加多少攻/血/暴击。
	#   截图才发现这块本来是 235px 的空白。
	#   复用 EquipStats.stat_lines(背包/图鉴同一个格式化函数) —— 不自己写第二份会漂的镜像。
	_build_stat_rows(box, str(edef.get("id", "")), own_star if own_mode else 1)

	_panel_sep(box, 424)

	# 合成进度: 「已有 N/3」+ 三颗圆点。
	# ★原来这里还有一句 _merge_hint()「集齐 3 件同款可合成 ★2」——【删了】。
	#   用户 2026-07-28:「这 3 合 1 为啥还有提示呢，你不是参考了商业游戏吗」。
	#   云顶/酒馆战棋都不在每件商品上重复全局规则, 只显示进度。圆点就是进度。
	var own := Label.new()
	# 看自己已有的 ★2/★3 时, 进度该按【那一星】数(3 件 ★2 才升 ★3), 不是按 ★1。
	own.text = "合成进度  %d/3" % owned if not own_mode else "★%d · 已有 %d 件" % [own_star, owned]
	own.add_theme_font_size_override("font_size", 16)
	own.add_theme_color_override("font_color", Color("#ffd93d") if owned >= 2 else Color("#9fb6c9"))
	own.position = Vector2(34, 436); own.size = Vector2(170, 22)
	box.add_child(own)
	_merge_pips(box, Vector2(206, 442), owned, 11.0)
	# ★这里【故意不做】"按文字实际高度把下面几块上移"的收拢。
	#   我先做了收拢, 探针实测 content_h=135 / 框 214 → 该上移 67px。但购买按钮是【钉死在
	#   面板底部】的(CTA 位置不该随内容长短跳动, 手机上尤其), 于是那 67px 空洞会从
	#   "描述框内的段后留白"变成"合成进度与购买按钮之间的悬空洞" —— 反而更难看。
	#   固定版式下: 空白留在文字后面像留白, 留在两块中间像漏了东西。


	# ★购买按钮(第二步确认) —— 花钱的按钮做最大
	var buy := Button.new()
	buy.add_theme_font_size_override("font_size", 22)
	buy.position = Vector2(34, PANEL_H - 100); buy.size = Vector2(PANEL_W - 68, 56)
	if own_mode:
		# 看的是自己已有的那件 —— 商店不做装备/合星/卖, 那些在背包页。这里给一条去路。
		buy.text = "去 🎒 背包页 装备 / 卖"
		buy.add_theme_font_size_override("font_size", 19)
		buy.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Inventory.tscn"))
		_skin_button(buy); box.add_child(buy)
		return
	_coin_button_icon(buy, 24)
	if coins >= price:
		buy.text = "购买  %d" % price
		buy.pressed.connect(func(): _on_buy(_sel))
	else:
		# 买不起要说清【原因和差多少】, 不是只把按钮变灰(用户 P1-4)
		buy.text = "深海币不足 (还差 %d)" % (price - coins)
		buy.disabled = true
	_skin_button(buy); box.add_child(buy)




## 描述一屏放不下时, 在框右下角挂一个"▼ 下滑"提示。
##
## ★必须等一帧才问 get_content_height() —— 刚 add_child 时还没排版, 拿到的是 0,
##   于是永远判"放得下"、提示永远不出现(这就是个不会红的假检查)。
func _add_scroll_hint(box: Control, desc: RichTextLabel) -> void:
	await get_tree().process_frame
	if not is_instance_valid(box) or not is_instance_valid(desc):
		return
	if desc.get_content_height() <= desc.size.y + 0.5:
		return
	var h := Label.new()
	h.text = "▼ 下滑看完整描述"
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", Color("#7fb5d8"))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.position = Vector2(desc.position.x, desc.position.y + desc.size.y - 16.0)
	h.size = Vector2(desc.size.x, 16)
	box.add_child(h)


## 详情面板的属性数值块(★1)。两列, 最多 3 行 = 6 项。
##
## 由来: 商店原先【一个装备属性数字都不显示】—— 花钱买之前看不到它加多少攻/血/暴击。
## 是把整页截出来放大看, 发现右侧面板中间空着 235px 才注意到的。
##
## ★复用 EquipStats.stat_lines() —— 背包(_stat_block)和图鉴(stat_line_all_stars)用的同一个函数,
##   量纲/名称/百分号全在那一处定义。自己在这里再写一遍格式化就是又造一份会漂的镜像。
##   (实测量纲不能靠数值范围猜: crit 存 0~1, 而 dodgePct/healAmp 存 0~100, 都是百分比。)
const STAT_COL_X := [34.0, 226.0]
const STAT_ROW_Y := [352.0, 373.0, 394.0]


func _build_stat_rows(box: Control, eid: String, star: int = 1) -> Array:
	var made: Array = []
	# ★星级跟着来源走: 货架永远卖 ★1, 但点的是自己已有的 ★2/★3 时必须显示【那一星】的数值。
	#   写死 1 的话, 玩家看到的是"我这件的属性"却其实是 ★1 的数字 —— 又一处显示与事实不符。
	var rows: Array = EquipStats.stat_lines(eid, star)
	if rows.is_empty():
		var none := Label.new()
		none.text = "（本件不提供属性加成，只有效果）"
		none.add_theme_font_size_override("font_size", 15)
		none.add_theme_color_override("font_color", Color("#5b7a92"))
		none.position = Vector2(34, STAT_ROW_Y[0]); none.size = Vector2(PANEL_W - 68, 22)
		box.add_child(none)
		return [none]
	var cap: int = STAT_COL_X.size() * STAT_ROW_Y.size()
	for i in range(mini(rows.size(), cap)):
		var kv: Array = rows[i]
		var lb := Label.new()
		lb.text = "%s %s" % [str(kv[0]), str(kv[1])]
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", Color("#9fe8c4"))
		lb.clip_text = true      # ★先于 size: 否则 Label 最小尺寸=文字全宽, 会把 size 顶开(踩过)
		lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lb.position = Vector2(STAT_COL_X[i % 2], STAT_ROW_Y[i / 2])
		lb.size = Vector2(196, 20)
		box.add_child(lb); made.append(lb)
	# ★装不下就明说, 不要静默截断(CLAUDE.md: 无声上限=假装覆盖全了)
	if rows.size() > cap:
		var more := Label.new()
		more.text = "…另有 %d 项属性" % (rows.size() - cap)
		more.add_theme_font_size_override("font_size", 13)
		more.add_theme_color_override("font_color", Color("#5b7a92"))
		more.position = Vector2(STAT_COL_X[0], STAT_ROW_Y[2] + 20.0); more.size = Vector2(PANEL_W - 68, 18)
		box.add_child(more); made.append(more)
	return made


func _panel_sep(parent: Control, y: float) -> Control:
	var ln := ColorRect.new()
	ln.color = Color(1, 1, 1, 0.10)
	ln.position = Vector2(34, y); ln.size = Vector2(PANEL_W - 68, 1)
	parent.add_child(ln)
	return ln


## 完整描述。★实测: 59 件装备的 effectDesc1 【全是纯文本】—— 无 HTML 标签、无方括号
## (龟技能才有 <span class="val-atk"> 那套)。所以不需要 html_to_bbcode(空转), 也不怕 BBCode 吃掉 [xxx]。
## 保留 bbcode_enabled 只为将来装备文案要上色时不用改结构。
func _rich_desc(edef: Dictionary) -> String:
	var raw := str(edef.get("effectDesc1", ""))
	if raw == "":
		return "[color=#5b7a92](这件装备还没有效果描述)[/color]"
	return raw


func _on_buy(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	var edef: Dictionary = _offer[idx]
	var price := _price(edef)
	if int(GameState.meta_deepsea_coins) < price:
		return   # 买不起
	GameState.meta_deepsea_coins -= price
	GameState.persistent_bench.append({"id": str(edef.get("id", "")), "star": 1})
	GameState.auto_merge_all()   # 买后自动 3 合 1 (背包+龟身一起算)
	_offer[idx] = null
	_persist_offer()   # 买走的位子要留空, 不能退出重进又长回来
	GameState.save()
	_rebuild()

func _on_refresh() -> void:
	if int(GameState.meta_deepsea_coins) < REFRESH_COST:
		return
	GameState.meta_deepsea_coins -= REFRESH_COST
	_roll()
	GameState.save()
	_rebuild()


## 新手引导高亮锚点(用户2026-07-23 D)。名字→屏幕矩形; 解析不到返回空 Rect2(本步不挖洞)。
func _tutorial_anchor(anchor: String) -> Rect2:
	match anchor:
		"coins":   # 深海币显示
			if _tut_coin != null and is_instance_valid(_tut_coin):
				return _tut_coin.get_global_rect()
		"offer":   # 货架卡片区(5列×2行, 与 _rebuild 同口径 gx=80 gy=150)
			var w: float = 5.0 * (SLOT_W + 24.0)
			var h: float = 2.0 * (SLOT_H + 28.0)
			return Rect2(80.0, 150.0, w, h)
	return Rect2()


## 深海币小图标。★复用 COIN_TEX(主菜单同一张), 不再用 emoji 💠。
func _coin_icon(parent: Control, pos: Vector2, sz: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = COIN_TEX
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = pos
	t.size = Vector2(sz, sz)
	parent.add_child(t)
	return t


## 给按钮挂深海币图标(按钮里没法插 TextureRect, 用 Button 自带的 icon 槽)。
## 图标靠右 —— 读作「购买 2 ◎」, 价格跟货币符号挨着。
func _coin_button_icon(b: Button, px: int) -> void:
	b.icon = COIN_TEX
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", px)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## 三合一进度圆点 ●●○ —— 取代原来那句「集齐 3 件同款可合成 ★2」。
##
## ★用户 2026-07-28:「这 3 合 1 为啥还有提示呢，你不是参考了商业游戏吗」——
##   说得对。云顶/酒馆战棋都【不会】在每件商品上写一遍三合一规则: 那是全局通用规则,
##   写 10 遍是教程噪音。它们只显示【进度】(酒馆的 triple 指示器)。
##   所以这里只画进度点: 已有几件亮几颗, 满 3 颗自动升星。
## ★用 Panel+StyleBoxFlat 画圆, 不用 "●" 字符 —— 游戏字体不保证有那个码位,
##   缺字会渲染成豆腐块(而且是换机器才复现的那种)。
func _merge_pips(parent: Control, pos: Vector2, owned: int, dot: float = 9.0) -> Array:
	var made: Array = []
	for i in range(3):
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		var lit: bool = i < owned
		sb.bg_color = Color("#ffd93d") if lit else Color(1, 1, 1, 0.16)
		sb.set_corner_radius_all(int(dot / 2.0))
		p.add_theme_stylebox_override("panel", sb)
		p.position = pos + Vector2(i * (dot + 5.0), 0.0)
		p.size = Vector2(dot, dot)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(p)
		made.append(p)
	return made


# ════════════════════════════════════════════════════════════════════════
#  皮肤: 三张【本项目新生成】的像素框 (assets/sprites/shop/)
#
#  ★用户 2026-07-28「别复用，自己画或生产」「只有背包或商店的图标可以复用」——
#    所以这三张是 PixelLab 新生成的, 没有从 menu/ 搬现成的 frame-*.png。
#    (深海币 ic-deepsea.png 是用户点名允许复用的那个例外。)
#
#  ★margin 是【量出来的】不是猜的: 见工具输出
#      btn-frame  128x64  边框 L14 R14 T17 B16 → 18
#      card-frame 117x117 边框 L13 R14 T16 B13 → 17
#      panel-frame 191x246 边框 L23 R22 T24 B24 → 25
#    九宫格 margin 大于控件一半会把中间压没 —— 按钮最矮 44px, 上下 18+18=36 < 44, 成立。
# ════════════════════════════════════════════════════════════════════════
const BTN_TEX = preload("res://assets/sprites/shop/btn-frame.png")
const CARD_TEX = preload("res://assets/sprites/shop/card-frame.png")
const PANEL_TEX = preload("res://assets/sprites/shop/panel-frame.png")
const BTN_MARGIN := 18
const CARD_MARGIN := 10
const PANEL_MARGIN := 25


## 给按钮套上新生成的深海金属框, 取代 Godot 默认灰皮。
## 三态用 modulate 区分, 不另外生成贴图: normal / hover 提亮 / pressed 压暗+文字下沉。
func _skin_button(b: Button, disabled_dim := true) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxTexture.new()
		sb.texture = BTN_TEX
		sb.texture_margin_left = BTN_MARGIN
		sb.texture_margin_right = BTN_MARGIN
		sb.texture_margin_top = BTN_MARGIN
		sb.texture_margin_bottom = BTN_MARGIN
		# ★content_margin 必须显式设小 —— 它默认【跟随 texture_margin】(18), 于是按钮的
		#   最小高度 = 文字高 + 36, 刷新键从 48 被撑到 66、压到了下面的备战席标题(门禁④抓到)。
		#   texture_margin 管九宫格怎么切图, content_margin 管文字离边多远, 两码事。
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		match st:
			"hover":    sb.modulate_color = Color(1.22, 1.22, 1.22)
			"pressed":  sb.modulate_color = Color(0.78, 0.78, 0.78)
			"disabled": sb.modulate_color = Color(0.5, 0.52, 0.55) if disabled_dim else Color(1, 1, 1)
			"focus":    sb.modulate_color = Color(1.1, 1.1, 1.1)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color("#dff2ff"))
	b.add_theme_color_override("font_hover_color", Color("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("#9fd8ea"))
	b.add_theme_color_override("font_disabled_color", Color("#6b7f8e"))


## 九宫格框(卡片/面板用)。★MOUSE_FILTER_IGNORE —— 框是纯装饰, 不能吃掉点击。
func _nine(parent: Control, tex: Texture2D, margin: int, pos: Vector2, sz: Vector2, z := -1) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = margin
	np.patch_margin_right = margin
	np.patch_margin_top = margin
	np.patch_margin_bottom = margin
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.position = pos
	np.size = sz
	np.z_index = z
	parent.add_child(np)
	return np
