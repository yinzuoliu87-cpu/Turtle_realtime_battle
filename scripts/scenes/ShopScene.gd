extends Control

## ShopScene — V2 局外商店 (阶段2, 设计§五/§十一). 10 卡货架, 用 meta_deepsea_coins 买装备入持久背包.
## 刷新固定 2 币; 买价 = 装备 cost (几费卖几深海币, 1:1, 用户 2026-07-01); 出货档随赛季总战斗数. 复用 Phase2Equip.roll_shop 出货算法.

const W := 1280.0
const H := 720.0
## 装备逐星属性表 —— 与战斗实装/背包/图鉴【同一张表】(CLAUDE.md §1: 装备属性的真事实源)
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")
## 类型羁绊: 阈值/档位/类型映射 —— 与背包羁绊面板/战斗侧同一份(2026-08-11 商店信息栏显示羁绊)
const Phase2Types = preload("res://scripts/gamedata/phase2_types.gd")
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
const BENCH_Y := 484.0       # 备战席(现只在弹层里用, 主页面是按钮)
const BOTTOM_BTN_Y := 552.0  # 底部两个摘要按钮
const LINEUP_Y := 580.0      # 阵容装备(横排)
## 羁绊总览条(货架与底部按钮之间那条空带)。★进 verify_shop_layout 的越界检查
const SYN_BAR_Y := 528.0
const SYN_CHIP_W := 176.0
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
var _popup: Control = null   # 底栏弹层(备战席/出战阵容)

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
			# SHOT_OWNED2=N: 再塞 N 件 ★2 —— 截"买 1 件会一路合成到 ★3"那一态用
			var ow2 := OS.get_environment("SHOT_OWNED2")
			if ow2.is_valid_int():
				for _k2 in range(int(ow2)):
					GameState.persistent_bench.append({"id": str((_offer[si] as Dictionary).get("id", "")), "star": 2})
	# SHOT_COINS=N: 强制深海币数(截"买不起"态用) / SHOT_SOLD=i,j: 把这几格置空(截"已购"态)
	if OS.get_environment("SHOT_COINS").is_valid_int():
		GameState.meta_deepsea_coins = int(OS.get_environment("SHOT_COINS"))
	for _si in OS.get_environment("SHOT_SOLD").split(","):
		if _si.is_valid_int() and int(_si) >= 0 and int(_si) < _offer.size():
			_offer[int(_si)] = null
	if OS.get_environment("SHOT_SEL") != "":
		_sel = int(OS.get_environment("SHOT_SEL"))
	_rebuild()
	# SHOT_POPUP=bench|lineup: 直接把底栏弹层打开 —— 否则截不到它(不能靠嘴说"点开会显示")
	if OS.get_environment("SHOT_POPUP") != "":
		_open_bottom_popup(OS.get_environment("SHOT_POPUP"))
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
	# ★2026-08-01: 同背包 —— 内容锁设计宽, 居中交给 UIFrame(原来这里取真实视口宽,
	#   但本屏其余元素按 1280 摆, 半适配反而让整体在宽屏上偏得更远)。
	var vw := W
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
	# ★上锁屏也要套设计框 —— _ready 在这条分支上是 `_build_locked(); return`,
	#   末尾那句 UIFrame.attach 【根本走不到】。我第一版就漏了这条路径, 于是量出来
	#   "商店完全没居中", 实际量的是这一屏。有 early return 的地方就要各自收口。
	UIFrame.attach(self)

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
	# ★2026-08-03 批2 私人池: 只掷【池里还有张】的件。抽空(0)与满3★冻结(-1)都不出。
	#   注意上面的 _maxed_item_ids 过滤【仍然保留】—— 它管的是"背包里已满星", 池冻结管的是"池子里的张",
	#   两者在正常流程下同时发生, 但存档损坏/调试快进时可能只有一边成立, 各守各的。
	GameState.ensure_equip_pool()
	pool = EquipPool.available(GameState.equip_pool, pool)
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
	# 框宽 320→200: 文字居中所以视觉不动, 但 320 宽的框右边止于 800、把币图标(起 760)整个圈进去了,
	# 右上角三组因此挤成一坨。收窄后止于 740, 给右侧留出干净的 40px 间隙。
	title.position = Vector2(W / 2.0 - 100, 16); title.size = Vector2(200, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title)

	var back := Button.new(); back.text = "← 返回"; back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 20); back.size = Vector2(126, 52)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")); _skin_button(back); add_child(back)

	var inv := Button.new(); inv.text = "🎒 背包"; inv.add_theme_font_size_override("font_size", 20)
	inv.position = Vector2(166, 20); inv.size = Vector2(126, 52)
	inv.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Inventory.tscn")); _skin_button(inv); add_child(inv)

	# ★图标在左、数字在右, 两者【不能重叠】——
	#   第一版我把图标放在 W-424, 而数字标签右对齐正好收在 W-390 → 数字整个被图标盖住,
	#   截图上只剩一枚币、看不到余额。门禁④当时只查"按钮被压", 压的是 Label 就漏了(已补⑦)。
	# ★右上三组【统一竖直中心 = 48】(用户 2026-07-29「右上角需要改」)。
	#   原先币 41 / 等级 41 / 买经验 48, 三个中心各走各的, 看着就是没对齐。
	#   横向排布: 币 756..874 | 等级 894..1016 | 买经验 1036..1252 (右边距 28), 组间隙 20。
	_coin_icon(self, Vector2(756, 32), 32.0)
	var coin := Label.new(); coin.text = "%d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 24); coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(794, 31); coin.size = Vector2(80, 34)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(coin)
	_tut_coin = coin   # 教学高亮"币"锚点

	# ★等级从一行小字改成【文字 + 进度条】: 原来只有 "Lv3 XP 6/10" 一行 17 号字,
	#   离下一级还差多少全靠玩家自己算; 买经验按钮就在旁边, 没有进度反馈等于让人盲买。
	var _lx := 894.0
	var _lw := 122.0
	var _need: int = maxi(1, P2.xp_to_next(int(GameState.season_level)))
	var _have: int = int(GameState.season_xp)
	var lv := Label.new(); lv.text = "Lv%d" % int(GameState.season_level)
	lv.add_theme_font_size_override("font_size", 18); lv.add_theme_color_override("font_color", Color("#ffd93d"))
	lv.position = Vector2(_lx, 32); lv.size = Vector2(46, 20)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; add_child(lv)

	var xpn := Label.new(); xpn.text = "%d/%d" % [_have, _need]
	xpn.add_theme_font_size_override("font_size", 15); xpn.add_theme_color_override("font_color", Color("#9fb4c8"))
	xpn.position = Vector2(_lx + 46.0, 34); xpn.size = Vector2(_lw - 46.0, 18)
	xpn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(xpn)

	var xbg := ColorRect.new(); xbg.color = Color("#16293a")
	xbg.position = Vector2(_lx, 56); xbg.size = Vector2(_lw, 8); add_child(xbg)
	var xfl := ColorRect.new(); xfl.color = Color("#ffd93d")
	xfl.position = Vector2(_lx, 56)
	xfl.size = Vector2(_lw * clampf(float(_have) / float(_need), 0.0, 1.0), 8); add_child(xfl)

	# 买经验: 200×36 字号15 → 216×60 字号18 (用户2026-07-28「买经验按钮很小」·移动端触摸目标 ≥44px)
	var bxp := Button.new(); bxp.text = "买经验 4 → +4XP"
	bxp.add_theme_font_size_override("font_size", 18)
	bxp.position = Vector2(W - 244, 18); bxp.size = Vector2(216, 60)
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
	rf.add_theme_font_size_override("font_size", 22)
	# 纵向节奏: 卡区止于 420 → 刷新 448(隔 28) → 底部按钮 552(隔 28) → 收于 648, 页底留 72
	rf.position = Vector2(GRID_X + 250, 448); rf.size = Vector2(240, 76)
	_coin_button_icon(rf, 20)
	rf.pressed.connect(_on_refresh); _skin_button(rf); add_child(rf)

	_build_synergy_bar()    # ★羁绊总览: 当前激活了哪些 + 距下一档还差几件(2026-08-12 用户点名)
	_build_detail_panel()   # ★右侧常驻详情面板(本次重设计的核心: 描述不再藏在 tooltip 里)
	_build_bottom_buttons()
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 内容装进 1280×720 设计框并居中于真实视口。
	# ★放在 _rebuild 末尾而不是 _ready 末尾 —— 本函数开头会 free 掉【所有】子节点(买一件装备
	#   就触发一次), 框和框里的内容会被一起清掉。attach 是幂等的, 重复调只重新收编+居中。
	UIFrame.attach(self)

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
		chip.text = "费用%d %d%%" % [c + 1, pct]
		chip.add_theme_font_size_override("font_size", 16)
		var cc := Color(cost_cols[c])
		chip.add_theme_color_override("font_color", cc if pct > 0 else Color(cc.r, cc.g, cc.b, 0.28))
		row.add_child(chip)

## 商店下部背包预览 (设计§十一: 显装备管理方便对照/3合1; 详细操作回背包页).
## 备战席格子。★host/ox/oy: 既能画在主页面, 也能画进弹层(用户 2026-07-29
## 「把这两个打包成按钮式的, 点击展示完整的」)。
func _build_bench_preview(host: Node = null, ox: float = 0.0, oy: float = 0.0) -> void:
	if host == null:
		host = self
	var bench: Array = GameState.persistent_bench
	var bh := Label.new()
	# ★原文案是「我的背包 (N 件) — 回 🎒 背包页 装备/合星/卖」——
	#   用户 2026-07-28:「你那下面写背包那么多字意义在哪里」。确实没意义:
	#   顶部已经有一个「🎒 背包」按钮, 后半句只是在解释背包页能干嘛 = 教程文字不是界面。
	#   删掉, 改成告诉玩家【这里能点】(因为现在它真的能点了)。
	bh.text = "我的背包 %d 件%s" % [bench.size(), "   · 点格子看详情" if bench.size() > 0 else ""]
	bh.add_theme_font_size_override("font_size", 15); bh.add_theme_color_override("font_color", Color("#9fb6c9"))
	bh.position = Vector2(ox + GRID_X, (oy + BENCH_Y)); bh.size = Vector2(740, 22); host.add_child(bh)   # 原(80,560)宽900会伸进详情面板
	var n := mini(10, bench.size())   # 14×72=1008 会伸出左栏(740) → 收到 10 件
	for j in range(n):
		var it: Dictionary = bench[j]
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
		var cell := Panel.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color("#162230"); csb.border_color = _cost_color(int(edef.get("cost", 1)))
		csb.set_border_width_all(2); csb.set_corner_radius_all(6)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(ox + GRID_X + j * 72, (oy + BENCH_Y) + 26); cell.size = Vector2(64, 64); host.add_child(cell)
		if str(it.get("id", "")) == _sel_own and int(it.get("star", 1)) == _sel_own_star:
			csb.border_color = Color("#ffd93d"); csb.set_border_width_all(3)
		_wire_own_tap(cell, str(it.get("id", "")), int(it.get("star", 1)))
		## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
		var ic2 := EquipIcon.make(edef, Vector2(36, 32))
		ic2.position = Vector2(14, 6)
		cell.add_child(ic2)
		var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
		st.add_theme_font_size_override("font_size", 11); st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.position = Vector2(0, 44); st.size = Vector2(64, 16); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(st)
	if bench.is_empty():
		var e := Label.new(); e.text = "（空 — 上面买几件）"
		e.add_theme_font_size_override("font_size", 14); e.add_theme_color_override("font_color", Color("#5a6675"))
		e.position = Vector2(ox + GRID_X + 4, (oy + BENCH_Y) + 28); e.size = Vector2(400, 22); host.add_child(e)

# 右侧只读面板: 出战阵容(上/下路6单位)每个龟/小将身上装了什么(用户2026-07-18「商店里看不到装备在龟身上的东西」)。在🎒背包页调整; 这里只看。
## 出战阵容各单位已装的装备。★同上, 可画进弹层。
func _build_lineup_equips(host: Node = null, ox: float = 0.0, oy: float = 0.0) -> void:
	if host == null:
		host = self
	var lineup: Dictionary = GameState.get_dual_lineup() if GameState.has_method("get_dual_lineup") else {}
	# ★竖排 6 行(原 px=730 / y=178+row*56) → 横排 6 列, 挪到底部 (oy + LINEUP_Y)。
	#   原位置在右侧 x730, 与本次新增的详情面板(x800)和第5列卡片重叠 —— 截图才看出来。
	# 「回背包页调整」那半句删掉 —— 顶部本来就有背包按钮, 那是教程文字不是界面
	#   (用户 2026-07-28 已就同类文案说过一次)。
	var hdr := Label.new(); hdr.text = "🐢 出战阵容 · 已装备"
	hdr.add_theme_font_size_override("font_size", 15); hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(ox + GRID_X, (oy + LINEUP_Y)); hdr.size = Vector2(740, 20); host.add_child(hdr)
	var row := 0
	for lk in ["top", "bottom"]:
		for u in (lineup.get(lk, []) as Array):
			if not (u is Dictionary): continue
			var cx := GRID_X + row * 124.0    # 横排: 每格 124px 宽 × 6 = 744 ≈ 左栏宽
			var y := (oy + LINEUP_Y) + 24.0
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
			nl.position = Vector2(ox + cx, y); nl.size = Vector2(118, 20); nl.clip_text = true; host.add_child(nl)
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
					hole.position = Vector2(ox + cx + ci0 * 40, y + 22); hole.size = Vector2(36, 36)
					hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
					host.add_child(hole)
			else:
				for ci in range(mini(eqs.size(), 3)):   # 横排每列只放得下 3 格(3×40=120)
					var it: Dictionary = eqs[ci]
					var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {})
					var cell := Panel.new()
					var csb := StyleBoxFlat.new(); csb.bg_color = Color("#162230")
					csb.border_color = _cost_color(int(edef.get("cost", 1))); csb.set_border_width_all(2); csb.set_corner_radius_all(6)
					cell.add_theme_stylebox_override("panel", csb)
					cell.position = Vector2(ox + cx + ci * 40, y + 22); cell.size = Vector2(36, 36)
					# ★不要只靠 tooltip —— 手机没有 hover, 这正是本次重设计要根治的坑
					#   (货架卡片的描述原来就藏在 tooltip 里)。这里补一行常驻的名字。
					#   tooltip 保留给桌面端当补充, 但不再是【唯一】途径。
					cell.tooltip_text = "%s ★%d" % [str(edef.get("name", "?")), int(it.get("star", 1))]
					host.add_child(cell)
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
					enm.position = Vector2(ox + cx + ci * 40, y + 59); enm.size = Vector2(36, 14)
					host.add_child(enm)
					## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
					var ic2 := EquipIcon.make(edef, Vector2(28, 24), true)
					ic2.position = Vector2(4, 2)
					cell.add_child(ic2)
					var st := Label.new(); st.text = "★".repeat(int(it.get("star", 1)))
					st.add_theme_font_size_override("font_size", 10); st.add_theme_color_override("font_color", Color("#ffd93d"))
					st.position = Vector2(0, 24); st.size = Vector2(36, 12); st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					st.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(st)
	if row == 0:
		var e2 := Label.new(); e2.text = "（尚未编排出战阵容 · 去背包/选龟）"
		e2.add_theme_font_size_override("font_size", 14); e2.add_theme_color_override("font_color", Color("#5a6675"))
		e2.position = Vector2(ox + GRID_X, (oy + LINEUP_Y) + 24); e2.size = Vector2(400, 22); host.add_child(e2)

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

## 1费用灰(用户 2026-07-29「1费不应该是灰色吗」)。#9aa6b4 在卡底 #11202e 上
## 对比度 6.68, 落在 3费蓝(6.50)与 2费绿(9.49)之间 —— 是灰的, 又不会在五档里显得没做完。
## (原 #8a96a3 对比度 5.49 其实也够读, 我先前说它"像禁用"是主观判断, 不成立。)
func _cost_color(cost: int) -> Color:   # 按费用上色(用户2026-07-19: 稀有度字段废弃, 费用才是真档位; 与旧稀有度严格1:1 → 颜色不变)
	match cost:
		2: return Color("#4ade80")
		3: return Color("#60a5fa")
		4: return Color("#c084fc")
		5: return Color("#fbbf24")
		_: return Color("#9aa6b4")   # 1费 = 灰

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
		# ★选中与否【换不同贴图】, 不再 modulate 染色 ——
		#   modulate 是乘法, 深色贴图乘什么都提不亮: 实测染色版"选中 vs 普通"色差只有 26
		#   (人眼要 >60), 肉眼分不出。两张独立贴图的边框色差是 135。
		#   费用档也不再压在框上, 改由【名字颜色】承担。
		var _c: int = clampi(int((_offer[idx] as Dictionary).get("cost", 1)), 1, 5)
		_nine(box, CARD_TEX_SEL if sel else CARD_TEX_TIER[_c - 1], CARD_MARGIN, Vector2.ZERO, Vector2(SLOT_W, SLOT_H), 1)
	if bought:
		var sold := Label.new(); sold.text = "已购"
		sold.add_theme_color_override("font_color", Color("#4a5663")); sold.add_theme_font_size_override("font_size", 16)
		sold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sold.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(sold)
		return box
	var edef: Dictionary = _offer[idx]
	# ★卡上【不再写「N 费」】(用户 2026-07-29:「1费和1图标都存在」)。
	#   实测 PRICE_MULT = 1 → 售价恒等于费用, 59/59 件都相等 ——
	#   卡上同时写「1 费」和「◎ 1」等于把同一个数字显示两遍。
	#   保留下面那个带币图标的价格(购买决策要看的是它); 费用档由【卡框颜色】表达
	#   (灰/绿/蓝/紫/金 = 1~5 费, 与出货概率行同一套色)。
	# 「N 费」撤掉后顶部空出 17px, 全给图标 —— 卡片上最该被一眼认出的是【这是什么东西】
	# 卡框边 10 → 内容从 18 起, 底部对称留 8。原来上留 12 / 下留 5.5, 差一倍。
	## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
	var ic2 := EquipIcon.make(edef, Vector2(60, 56))
	ic2.position = Vector2(SLOT_W / 2.0 - 30, 18)
	box.add_child(ic2)
	# ★名字按费用档着色(用户 2026-07-29)。撤掉「N 费」文字后费用信息一度是【丢的】——
	#   我当时说"靠卡框颜色表达", 但实测卡框 modulate 染色的色差只有 6~10(人眼要 >60),
	#   等于没表达。名字是卡上唯一够大的文字, 由它承担费用档最实在。
	var nm := Label.new(); nm.text = str(edef.get("name", edef.get("id", "?")))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", _cost_color(int(edef.get("cost", 1))))
	nm.position = Vector2(11, 78); nm.size = Vector2(SLOT_W - 22, 22)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.clip_text = true
	box.add_child(nm)
	# ★卡面【不放】效果摘要(用户 2026-07-28:「小卡片内别加摘要」)。
	#   我原本放了一行截断摘要, 理由是"10 件商品 1 个详情面板, 没摘要就得点 10 次"。
	#   但卡宽 132 只放得下约 11 个字, 截断句在卡上又小又碎 —— 用户拍板砍掉,
	#   完整描述【全部交给右侧详情面板】(字号也加大到 18)。
	#   腾出的 16px 给了图标和名字, 见下面的 y 排布。
	var owned := _owned_count(str(edef.get("id", "")))   # 已拥有 ★1 件数
	var will_star := _purchase_merge_star(str(edef.get("id", "")))   # 这一买会合成到几星(0=不合成)
	if will_star >= 2:
		# ★只在「差 1 件就合成」时出现两颗闪光星。1 件不画 ——
		#   装备自己就有 ★1/★2/★3, 画一颗星会被读成"这是 ★1 装备"(每张卡都是), 等于噪音。
		# ★星星数 = 这一买会合成到几星(2 或 3), 不是"已有几件"。
		#   3 星的情形: ★1 已有 2 件【且】★2 也已有 2 件 —— auto_merge_all 是 while 循环,
		#   会一路级联 3×★1→★2、再 3×★2→★3。这是最值得提示的一刻。
		# ★右端定在 x=118: 选中框的青色发光边比档位框厚, 实测星星放到 120 会被它切掉半颗。
		for k in range(will_star):
			_glint_star(box, Vector2(118.0 - 13.0 - k * 14.0, 13), 13.0, k * 0.3)
	var price := _price(edef)
	var afford := int(GameState.meta_deepsea_coins) >= price
	# ★币 + 数字当【一个整体】水平居中, 且竖直按中线对齐。
	#   原来是各自绝对定位: 实测竖直差 3.2px、整体偏左 9.5px, 而且价格是【左对齐+固定起点】,
	#   价格变两位数时会更偏。用 HBoxContainer 交给引擎排, 位数再变也不会跑。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, 102); row.size = Vector2(SLOT_W, 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var ci := TextureRect.new()
	ci.texture = COIN_TEX
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.custom_minimum_size = Vector2(15, 15)
	ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ci)
	var pr := Label.new(); pr.text = "%d" % price
	pr.add_theme_font_size_override("font_size", 15)
	pr.add_theme_color_override("font_color", Color("#a8cfe0") if afford else Color("#ff6b6b"))
	pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pr)
	# ★买不起 → 【整张卡变灰变暗】(用户 2026-07-29:「云顶的做法是…买不起时整个卡片去变灰」)。
	#   原来只是价格数字变红 —— 那是个很弱的信号, 要盯着数字看才发现。
	#   整卡压暗是"这张现在与你无关"的最直白表达, 而且【不干扰】费用框色和选中态:
	#   modulate 在这里是【压暗】不是提亮, 乘法正好胜任(这也是它唯一擅长的事)。
	if not afford:
		box.modulate = Color(0.42, 0.46, 0.52)
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
## 羁绊总览条(货架下方): 当前激活的每一系 + 距下一档还差几件。
## ★口径与战斗/背包完全一致: 只数【装在身上】的、按 id 去重(GameState.team_p2_equips_for_synergy)。
##   ⚠ 不数背包 —— "买到 ≠ 装上"(2026-08-12 圣光护盾白送 bug 的同一条教训)。
## 用户 2026-08-12:「商店里应该显示目前背包里激活的羁绊和下一个档位需求数量」。
func _build_synergy_bar() -> void:
	## ★算法住在 GameState.synergy_rows() —— 出战页 chips 用的是同一份(2026-08-12)。
	##   去重口径 / "差几件" / 排序三样都在那里, 两处显示才不会漂。
	var rows: Array = GameState.synergy_rows()

	var y: float = SYN_BAR_Y
	var hdr := Label.new()
	hdr.text = "羁绊"
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(GRID_X, y); hdr.size = Vector2(44, 20)
	add_child(hdr)
	if rows.is_empty():
		var none := Label.new()
		none.text = "（还没装上任何同类型装备 · 装 3 件同类型即可激活）"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", Color("#5a6675"))
		none.position = Vector2(GRID_X + 46, y + 1); none.size = Vector2(700, 20)
		add_child(none)
		return
	var x: float = GRID_X + 46.0
	for r in rows:
		if x > GRID_X + 700.0:
			break
		var chip := Label.new()
		var tier: int = int(r["tier"])
		var need: int = int(r["need"])
		var n_now: int = int(r["n"])
		## ★用【数字】表达进度, 不用一句话去说(2026-08-12 用户:「想想怎么以图片或数字的
		##   形式显示差几件而不是文字这么去说」)。写法取自走棋通行式: 图标 + 当前/下一档阈值,
		##   再跟满/空星表示已激活到第几档 —— 一眼扫过去就是"我还差几件"。
		var star_n: int = (Phase2Types.TYPES[str(r["t"])] as Dictionary).get("tiers", []).size()
		var stars := ""
		for si in range(star_n):
			stars += "★" if si < tier else "☆"
		if need > 0:
			chip.text = "%s%s %d/%d %s" % [str(Phase2Types.emoji_of(str(r["t"]))), str(r["t"]),
				n_now, n_now + need, stars]
		else:
			chip.text = "%s%s %d %s" % [str(Phase2Types.emoji_of(str(r["t"]))), str(r["t"]),
				n_now, stars]
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color",
			Color("#ffd93d") if tier > 0 else Color("#7a92a8"))
		chip.position = Vector2(x, y + 1)
		chip.size = Vector2(SYN_CHIP_W, 20)
		chip.clip_text = true
		add_child(chip)
		x += SYN_CHIP_W + 6.0


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
	## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(060~095 有 36 件没配图)
	var ic2 := EquipIcon.make(edef, Vector2(66, 58))
	ic2.position = Vector2(34, 32)
	box.add_child(ic2)
	var nm := Label.new(); nm.text = str(edef.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 26)
	nm.add_theme_color_override("font_color", _cost_color(cost))
	nm.position = Vector2(112, 36); nm.size = Vector2(PANEL_W - 148, 32)
	box.add_child(nm)
	# 直接写清单位: 「2 深海币」比「费用 2」更明确 —— 费用和售价在本作恒等(PRICE_MULT=1),
	# 与其用一个抽象档位名, 不如告诉玩家【要付多少、付的是什么】。(用户 2026-07-29)
	var cl := Label.new(); cl.text = "%d 深海币" % _price(edef)
	cl.add_theme_font_size_override("font_size", 17)
	cl.add_theme_color_override("font_color", Color("#9fb6c9"))
	cl.position = Vector2(112, 70); cl.size = Vector2(160, 22)
	box.add_child(cl)

	# ★羁绊小签(2026-08-11 用户: 「商店页面的信息栏优化, 要去显示羁绊」):
	#   费用行右侧一眼可见【类型 ×现有件数 · 档位】; 完整阈值与"装上后升不升档"在描述区首行。
	var syn: Dictionary = _synergy_info(str(edef.get("id", "")))
	if not syn.is_empty():
		var sg := Label.new()
		sg.text = "%s%s ×%d·%s" % [str(syn["emoji"]), str(syn["name"]), int(syn["count"]),
			("档%d" % int(syn["tier"])) if int(syn["tier"]) > 0 else "未激活"]
		sg.add_theme_font_size_override("font_size", 13)
		sg.add_theme_color_override("font_color",
			Color("#ffd93d") if int(syn["tier"]) > 0 else Color("#7a92a8"))
		sg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		## ★Label 会被字体最小宽度撑破给定 size(实测 15 号字撑到 201px, 右沿压进面板框边)
		##   ⇒ 定宽 + clip_text 双保险; 门禁⑧量的是真实节点矩形, 压框直接红。
		sg.clip_text = true
		sg.position = Vector2(205, 72); sg.size = Vector2(PANEL_W - 34 - 205, 20)
		box.add_child(sg)

	_panel_sep(box, 104)

	# ★完整效果描述(常驻可见) —— 富文本走 RichTextLabel, 与图鉴同口径
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = false
	desc.scroll_active = true
	# 字号 16 → 18(用户 2026-07-28:「这么小的字?」)。卡面摘要砍掉后, 完整描述全靠这一块。
	desc.add_theme_font_size_override("normal_font_size", 20)
	desc.position = Vector2(34, 112); desc.size = Vector2(PANEL_W - 68, 264)
	desc.text = _synergy_bbcode(syn) + _rich_desc(edef, own_star if own_mode else 1)
	box.add_child(desc)
	# ★59 件里有 1 件(玩偶小熊 297px > 框 230)一屏放不下 —— 门禁⑥量出来的。
	#   不加提示的话, 玩家看到的是"描述断在半句", 会以为是 bug 而不是"可以滚"。
	_add_scroll_hint(box, desc)

	var _sep_a := _panel_sep(box, 384)

	# ★属性数值 —— 商店原先【一个数字都不显示】: 花钱买之前看不到它加多少攻/血/暴击。
	#   截图才发现这块本来是 235px 的空白。
	#   复用 EquipStats.stat_lines(背包/图鉴同一个格式化函数) —— 不自己写第二份会漂的镜像。
	var _stat_hdr := Label.new(); _stat_hdr.text = "属性"
	_stat_hdr.add_theme_font_size_override("font_size", 15)
	_stat_hdr.add_theme_color_override("font_color", Color("#58d3ff"))
	_stat_hdr.position = Vector2(34, 390); _stat_hdr.size = Vector2(80, 18)
	box.add_child(_stat_hdr)
	var _stat_nodes: Array = _build_stat_rows(box, str(edef.get("id", "")), own_star if own_mode else 1)


	# 合成进度: 「已有 N/3」+ 三颗圆点。
	# ★原来这里还有一句 _merge_hint()「集齐 3 件同款可合成 ★2」——【删了】。
	#   用户 2026-07-28:「这 3 合 1 为啥还有提示呢，你不是参考了商业游戏吗」。
	#   云顶/酒馆战棋都不在每件商品上重复全局规则, 只显示进度。圆点就是进度。
	# ★详情面板【不再显示合成块】(用户 2026-07-29「干脆不要合成了」)。
	#   卡片右上角那两三颗星仍在 —— 那是"这一买会升到几星"的即时提示, 在做购买决定的
	#   那一眼就看得到; 面板里再画一遍算式属于重复, 而且占掉的正是描述最缺的高度。
	#   省下来的 ~76px 全给描述框(字号加大后原本有 7 件要滚, 现在只剩 1 件)。
	# ★描述短时把下面几块【居中收拢】(用户 2026-07-29 反馈中段空太多)。
	#   我先前试过"往上顶"并否决了 —— 购买按钮钉死在底部, 上顶会让空洞从"文字后的留白"
	#   变成"合成进度与按钮之间的悬空洞", 更难看。
	#   现在改成【把中间那一坨在剩余空间里居中】: 上下各分一半, 看起来像是有意留的,
	#   而不是某一侧漏了东西。购买按钮仍然不动(CTA 位置不该随内容长短跳)。
	_center_middle(desc, [_sep_a, _stat_hdr] + _stat_nodes)



	# ★购买按钮(第二步确认) —— 花钱的按钮做最大
	var buy := Button.new()
	buy.add_theme_font_size_override("font_size", 22)
	# ★按钮加高 56 → 68 → 78(用户 2026-07-29「购买按钮你不觉得很扁吗」/「按钮重新做吧」)。
	#   372×56 = 6.6:1 → 68 = 5.5:1 → 78 = 4.8:1。它是全页最主要的动作, 本来就该是最大的可点物,
	#   所以宽度不收(372 = 面板宽的 85%), 只往上长。
	# ★下沿焊在 565: 面板框九宫格 margin=25 → 内容安全区下界 567(门禁⑧会查)。
	#   上沿因此落在 487, 距属性区末行(止于 470)留 17px。再高就压属性了。
	buy.position = Vector2(34, PANEL_H - 105); buy.size = Vector2(PANEL_W - 68, 78)
	if own_mode:
		# 看的是自己已有的那件 —— 商店不做装备/合星/卖, 那些在背包页。这里给一条去路。
		buy.text = "去 🎒 背包页 装备 / 卖"
		buy.add_theme_font_size_override("font_size", 19)
		buy.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Inventory.tscn"))
		_skin_button(buy, true, BUY_BTN_TEX)
		_gold_btn_text(buy)
		box.add_child(buy)
		return
	_coin_button_icon(buy, 24)
	if coins >= price:
		buy.text = "购买  %d" % price
		buy.pressed.connect(func(): _on_buy(_sel))
	else:
		# 买不起要说清【原因和差多少】, 不是只把按钮变灰(用户 P1-4)
		buy.text = "深海币不足 (还差 %d)" % (price - coins)
		buy.disabled = true
	_skin_button(buy, true, BUY_BTN_TEX)
	_gold_btn_text(buy)
	box.add_child(buy)




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
## 两列 x。★右列 226 + 宽 180 = 406 < 面板框安全区右界 415(PANEL_W 440 - margin 25)。
## 原来宽 196 → 右端 422, 压进右边框 7px, 是门禁⑧挖出来的(肉眼看不出)。
const STAT_COL_X := [34.0, 226.0]
const STAT_ROW_Y := [412.0, 431.0, 450.0]   # 紧跟「属性」标题(y390, 高18) —— 隔 4px 不断开


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
		lb.add_theme_font_size_override("font_size", 17)
		lb.add_theme_color_override("font_color", Color("#9fe8c4"))
		lb.clip_text = true      # ★先于 size: 否则 Label 最小尺寸=文字全宽, 会把 size 顶开(踩过)
		lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lb.position = Vector2(STAT_COL_X[i % 2], STAT_ROW_Y[i / 2])
		lb.size = Vector2(180, 22)
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


## 这件装备的羁绊信息(2026-08-11 用户: 「商店页面的信息栏优化, 要去显示羁绊」)。
## 返回 {} = 无类型(不显示)。count/tier 是【队伍已装上】的现状(替补席不算 · id 去重),
## 口径 = GameState.team_p2_equips_for_synergy + Phase2Types.calc_active(背包/战斗同一份)。
func _synergy_info(eid: String) -> Dictionary:
	var typ: String = Phase2Types.type_of(eid)
	if typ == "" or not Phase2Types.TYPES.has(typ):
		return {}
	var seen: Dictionary = {}
	var n := 0
	for it in GameState.team_p2_equips_for_synergy():
		if not (it is Dictionary):
			continue
		var iid := str((it as Dictionary).get("id", ""))
		if iid == "" or seen.has(iid):
			continue
		seen[iid] = true
		if Phase2Types.type_of(iid) == typ:
			n += 1
	var tiers: Array = (Phase2Types.TYPES[typ] as Dictionary).get("tiers", [])
	var tier := 0
	for i in range(tiers.size()):
		if n >= int(tiers[i]):
			tier = i + 1
	# 装上后(去重: 已拥有同款 id 时 +0)
	var owned: bool = seen.has(eid)
	var n2: int = n if owned else n + 1
	var tier2 := 0
	for i in range(tiers.size()):
		if n2 >= int(tiers[i]):
			tier2 = i + 1
	## ★名字用【纯类型名】(枪/盾/法器…), 不用 display_name ——
	##   那个是"盾·守护""奇械·魔抗"这类带后缀的花名(2026-08-12 用户:「而不是什么守护那种词,
	##   就是枪, 盾什么的」)。玩家凑羁绊时脑子里想的就是"我还差几件盾"。
	return {"type": typ, "name": typ, "emoji": Phase2Types.emoji_of(typ),
		"tiers": tiers, "count": n, "tier": tier, "owned": owned, "count2": n2, "tier2": tier2}


## 描述区首行的羁绊详情(bbcode)。空信息返回空串(描述原样)。
func _synergy_bbcode(syn: Dictionary) -> String:
	if syn.is_empty():
		return ""
	var parts: PackedStringArray = []
	for t in (syn["tiers"] as Array):
		parts.append(str(int(t)))
	var line := "[color=#58d3ff]羁绊·%s%s[/color]  阈值 %s · 队伍现有 ×%d(%s)" % [
		str(syn["emoji"]), str(syn["name"]), "/".join(parts), int(syn["count"]),
		("档%d" % int(syn["tier"])) if int(syn["tier"]) > 0 else "未激活"]
	var second := ""
	if bool(syn["owned"]):
		second = "[color=#8fa2b5]已有同款 —— 羁绊按种类去重, 重复买不涨羁绊数[/color]"
	elif int(syn["tier2"]) > int(syn["tier"]):
		second = "[color=#7fe39a]买入并装上 → ×%d · 升到档%d[/color]" % [int(syn["count2"]), int(syn["tier2"])]
	else:
		second = "买入并装上 → ×%d" % int(syn["count2"])
	return line + "\n" + second + "\n\n"


## 完整描述。★实测: 59 件装备的 effectDesc1 【全是纯文本】—— 无 HTML 标签、无方括号
## (龟技能才有 <span class="val-atk"> 那套)。所以不需要 html_to_bbcode(空转), 也不怕 BBCode 吃掉 [xxx]。
## 保留 bbcode_enabled 只为将来装备文案要上色时不用改结构。
func _rich_desc(edef: Dictionary, star: int = 1) -> String:
	var raw := str(edef.get("effectDesc1", ""))
	if raw == "":
		return "[color=#5b7a92](这件装备还没有效果描述)[/color]"
	# ★按星级高亮(用户 2026-07-29「上面的效果能按照描述规则渲染吗」)。
	#   装备描述里的 `1/1.2/1.5` 是【一/二/三星三档值】。商店卖 ★1, 原来三档同色平铺,
	#   玩家看不出哪个数才是自己买到的。highlight_star 把当前星那档高亮、另两档压暗。
	#   ★背包页(InventoryScene:507/575)一直在用这个函数, 商店漏了 —— 同一份文案两套渲染。
	return SkillText.highlight_star(raw, star)


func _on_buy(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	var edef: Dictionary = _offer[idx]
	var price := _price(edef)
	if int(GameState.meta_deepsea_coins) < price:
		return   # 买不起
	# ★私人池: 先扣张再扣钱 —— 扣不到张就整笔不成交(货架是异步持久化的, 极端情况下
	#   可能出现"货架上还挂着、池子已被别的路径抽空"; 那时宁可这一次点击无效, 也不能凭空造张)。
	var _eid: String = str(edef.get("id", ""))
	if not GameState.pool_take(_eid, 1):
		return
	GameState.meta_deepsea_coins -= price
	GameState.persistent_bench.append({"id": _eid, "star": 1})
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
## 购买按钮专用金框 —— 它是全页最主要的动作, 用和"返回/背包/刷新"一样的灰蓝框
## 就没有主次(用户 2026-07-29「购买按钮你不觉得很扁吗」的另一半: 不只是矮, 是不够重)。
const BUY_BTN_TEX = preload("res://assets/sprites/shop/buy-btn.png")
## ★卡框换新(2026-07-29)。旧的 card-frame.png 是珊瑚/藤壶纹, 两个问题:
##   ① 132px 下那些碎装饰就是噪点, 十张并排还形成很强的重复图案
##   ② 它同时背着"费用档"和"选中态"两个颜色职责, 而 modulate 是【乘法】——
##      深色贴图乘什么都提不亮, 实测色差 6~10 和 26(人眼要 >60), 两个都失效
## 现在: 卡框只当中性边框; 费用档交给【名字颜色】, 选中态整张换成 CARD_TEX_SEL(不染色)。
## 风格上向已在用的 btn-frame 看齐(同金属/同青内框/同金铆钉), 至少按钮和卡片是一家人。
## ★卡框【按费用档 5 张】(用户 2026-07-29:「不是5档吗」/「云顶的做法是框框随费用变化」)。
## 不是 modulate 染色 —— modulate 是乘法, 深色贴图乘什么都提不亮(实测色差只有 6~10)。
## 这 5 张是拿中性框【按亮度重上色】画出来的(tools 里那段: 暗端=色×0.20, 亮端向白 15%),
## 形状逐像素一致、颜色我说了算。实测相邻档色差 92/98/64/163, 全部 >60(人眼可辨门槛)。
const CARD_TEX_TIER := [
	preload("res://assets/sprites/shop/card-frame-t1.png"),
	preload("res://assets/sprites/shop/card-frame-t2.png"),
	preload("res://assets/sprites/shop/card-frame-t3.png"),
	preload("res://assets/sprites/shop/card-frame-t4.png"),
	preload("res://assets/sprites/shop/card-frame-t5.png"),
]
## 选中态【整张换图】而不是给上面那张染色 —— 实测两框边框色差 135(modulate 版只有 26)。
const CARD_TEX_SEL = preload("res://assets/sprites/shop/card-frame-s.png")
const PANEL_TEX = preload("res://assets/sprites/shop/panel-frame.png")
const BTN_MARGIN := 18
const CARD_MARGIN := 8       # 量的: 新框 72×72, 边框 7px
## 合成指示星(像素·12 帧闪光循环)。★只在「已有 2 件、再买 1 件就合成」时出现 ——
## 装备本身就有 ★1/★2/★3 星级, 画一颗星会被读成"这是 ★1 装备", 而每张货架卡都是 ★1 = 零信息。
const STAR_TEX = preload("res://assets/sprites/shop/star-glint.png")
const STAR_FRAMES := 12
const STAR_FRAME_W := 32
const PANEL_MARGIN := 25


## 给按钮套上新生成的深海金属框, 取代 Godot 默认灰皮。
## 三态用 modulate 区分, 不另外生成贴图: normal / hover 提亮 / pressed 压暗+文字下沉。
func _skin_button(b: Button, disabled_dim := true, tex: Texture2D = null) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex if tex != null else BTN_TEX
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


## 会闪的合成指示星。用 AtlasTexture 逐帧切 star-glint.png(12 帧)。
##
## ★为什么不用 tween 改 modulate 做"发光": 那是矢量做法, 和满屏像素画混在一起就是
##   用户说的「网站加游戏风」。这里换的是【真像素帧】, 高光是画出来的不是算出来的。
## ★phase: 两颗星错开起始相位, 不然齐刷刷同步闪, 像坏了。
func _glint_star(parent: Control, pos: Vector2, sz: float, phase: float) -> void:
	var tr := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = STAR_TEX
	at.region = Rect2(0, 0, STAR_FRAME_W, STAR_FRAME_W)
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = pos
	tr.size = Vector2(sz, sz)
	# ★必须比卡框高一层: 卡框是 z_index=1 画在所有内容之上(好让内容不溢出到框上),
	#   星星不抬 z 就会被选中框那圈更厚的发光边切掉半颗(放大 10 倍才看出来的)。
	tr.z_index = 2
	parent.add_child(tr)
	# 12 帧 × 0.09 秒 ≈ 1.1 秒一轮
	var tw := tr.create_tween().set_loops()
	if phase > 0.0:
		tw.tween_interval(phase)
	tw.tween_method(func(i: float) -> void:
		if is_instance_valid(tr):
			at.region = Rect2(float(int(i)) * STAR_FRAME_W, 0.0, STAR_FRAME_W, STAR_FRAME_W),
		0.0, float(STAR_FRAMES) - 0.01, float(STAR_FRAMES) * 0.09)


## 买【这一件】会合成到几星？返回 0(不合成) / 2 / 3。
##
## ★不是"已有几件" —— GameState.auto_merge_all 是 `while changed` 循环, 会【级联】:
##   3×★1 合成 1×★2 之后, 若 ★2 也够 3 件, 会继续合成 ★3。
##   所以「★1 已有 2 件 且 ★2 已有 2 件」时, 买 1 件直接到 ★3, 那是最值得提示的一刻。
## ★这里模拟的是 auto_merge_all 的规则(同 id 同星 3 件进 1 星), 与它是同一套口径;
##   门禁 verify_shop_merge_pips 焊死"显示口径 = 真实合成规则"。
func _purchase_merge_star(eid: String) -> int:
	if eid == "":
		return 0
	# 下标 = 星级; [1] 已含这次购买的那一件
	var n := [0, _owned_count(eid, 1) + 1, _owned_count(eid, 2), _owned_count(eid, 3)]
	var top := 0
	for st in [1, 2]:
		if n[st] >= 3:
			n[st] -= 3
			n[st + 1] += 1
			top = st + 1
	return top


## 描述短时, 把它【下面那一坨】(分隔线/属性/合成进度)在剩余空间里【居中】。
##
## 由来: 描述框按最长的那件(玩偶小熊 297px)留高, 而中位数只有 4 行 ≈ 90px ——
## 短描述下面会空出约 150px(用户 2026-07-29 反馈"中段空太多")。
##
## ★为什么是"居中"而不是"上顶": 上顶试过并否决 —— 购买按钮钉死在面板底部(CTA 位置
##   不该随内容长短跳), 上顶只会把空洞从"文字后的留白"搬到"合成进度与按钮之间",
##   那更像漏了东西。居中则上下各分一半, 看起来是有意留的。
## ★必须等一帧再问 get_content_height(): 刚 add_child 时还没排版, 拿到 0 会把这一坨
##   一路顶到描述正下方、和描述叠在一起(这是 CLAUDE.md §3.5 那类坑的近亲)。
func _center_middle(desc: RichTextLabel, nodes: Array) -> void:
	await get_tree().process_frame
	# ★去重: 同一个节点若在数组里出现两次会被【移两倍】。
	#   实测踩过 —— _stat_hdr 既被 append 进 _stat_nodes、调用时又单独列了一次,
	#   于是"属性"标题跑到属性行上方 110px(本该只隔 22px), 看着像布局崩了。
	var uniq: Array = []
	for n in nodes:
		var dup := false
		for u in uniq:
			if is_same(u, n):
				dup = true; break
		if not dup:
			uniq.append(n)
	nodes = uniq
	if not is_instance_valid(desc):
		return
	var ch: float = desc.get_content_height()
	if ch <= 0.0:
		return                                  # 还没排版好, 宁可不动也不要算错
	var slack: float = maxf(0.0, desc.size.y - ch - 12.0)   # 文字没用掉的高度(留 12 呼吸)
	if slack < 16.0:
		return                                  # 差得不多就别动, 免得每次选中都轻微跳
	var shift: float = floorf(slack * 0.5)      # ★只上移一半 = 上下各分一半空白
	for n in nodes:
		if is_instance_valid(n) and n is Control:
			(n as Control).position.y -= shift




## 金底按钮的字色。抽出来是因为它要在两个分支各用一次(可买 / 已拥有跳背包),
## 而那两处缩进层级不同 —— 直接把四行贴进去撕过一次块结构(CLAUDE.md §3.7 同族)。
func _gold_btn_text(b: Button) -> void:
	b.add_theme_color_override("font_color", Color("#3a2a06"))
	b.add_theme_color_override("font_hover_color", Color("#1e1503"))
	b.add_theme_color_override("font_pressed_color", Color("#5c4712"))


# ══════════════════════════════════════════════════════════════
# §底栏 备战席 / 出战阵容 —— 打包成两个按钮, 点开看全部
#
# 用户 2026-07-29:「需要备战席和出战席位的, 但你可以把这两个打包成按钮式的,
# 点击展示完整的」。
#
# 原来这两栏平铺在底部占 190px, 而它们【只读】(真正的装备操作在背包页) ——
# 常驻这么大面积不划算。改成摘要按钮 + 点开弹层: 信息一条不少, 屏幕还回来了。
# ══════════════════════════════════════════════════════════════

## 统计出战阵容里已装备的件数 / 总槽位(每单位 3 格)
func _lineup_equip_count() -> Array:
	var lineup: Dictionary = GameState.get_dual_lineup() if GameState.has_method("get_dual_lineup") else {}
	var n := 0
	var slots := 0
	for lk in ["top", "bottom"]:
		for u in (lineup.get(lk, []) as Array):
			if not (u is Dictionary):
				continue
			slots += 3
			var eqs: Array = []
			if str(u.get("kind", "")) == "leader":
				var pe = GameState.persistent_equipped.get(str(u.get("id", "")), []) if GameState.persistent_equipped is Dictionary else []
				if pe is Array: eqs = pe
			elif u.get("equips") is Array:
				eqs = u["equips"]
			n += eqs.size()
	return [n, slots]


func _build_bottom_buttons() -> void:
	var bench: Array = GameState.persistent_bench
	var lc: Array = _lineup_equip_count()
	# ★宽高比: 原 360×52 = 6.9:1, 是全页最扁的两个(用户 2026-07-29「太扁了」)。
	#   现 360×96 = 3.75:1。底栏把两个平铺栏收成按钮后腾出 190px, 高度管够。
	# ★左右边缘【与卡区对齐】: 卡区 x 40..780(5×132 + 4×20 = 740)。
	#   上一版用 GRID_X+40 起、间距 40, 跨 80..720 → 中心 400 而卡区中心 410, 差 10px 看着就是歪的。
	#   现在两按钮各 (740-20)/2 = 360, 起 40 与 420, 正好铺满卡区宽度 —— 边缘对齐比居中更稳。
	var bw := (740.0 - 20.0) * 0.5
	var bh2 := 96.0
	var b1 := Button.new()
	b1.text = "🎒 我的背包  %d 件" % bench.size()
	b1.add_theme_font_size_override("font_size", 21)
	b1.position = Vector2(GRID_X, BOTTOM_BTN_Y); b1.size = Vector2(bw, bh2)
	b1.pressed.connect(func(): _open_bottom_popup("bench"))
	_skin_button(b1); add_child(b1)

	var b2 := Button.new()
	b2.text = "🐢 出战阵容  已装 %d / %d" % [int(lc[0]), int(lc[1])]
	b2.add_theme_font_size_override("font_size", 21)
	b2.position = Vector2(GRID_X + bw + 20.0, BOTTOM_BTN_Y); b2.size = Vector2(bw, bh2)
	b2.pressed.connect(func(): _open_bottom_popup("lineup"))
	_skin_button(b2); add_child(b2)


## 弹层: 半透明遮罩 + 面板 + 关闭。点遮罩或按 ESC 都能关。
func _open_bottom_popup(kind: String) -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	var lay := Control.new()
	lay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_STOP     # ★吃掉点击, 否则会穿透到底下的卡片
	# ★z_index 必须高过 10 —— 卡框和详情面板框都设了 z_index=1(好让内容不溢出到框上),
	#   弹层不抬 z 就会被它们【画在上面】: 遮罩盖不住卡片, 卡片从弹层里透出来。
	lay.z_index = 20
	add_child(lay)
	_popup = lay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(dim)
	lay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			lay.queue_free())

	var pw := 820.0
	var ph := 300.0
	var px := (W - pw) * 0.5
	var py := (H - ph) * 0.5
	var pan := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("#0e1a26"); psb.set_corner_radius_all(10)
	pan.add_theme_stylebox_override("panel", psb)
	pan.position = Vector2(px, py); pan.size = Vector2(pw, ph)
	pan.mouse_filter = Control.MOUSE_FILTER_STOP     # 面板内点击不关弹层
	lay.add_child(pan)
	# ★用 BTN_TEX 而不是 PANEL_TEX: 面板框源图 191×246 是竖长条, 拉成 820×300 的横板会
	#   把边饰扯变形(截图上很明显)。按钮框 128×64 是 2:1, 与这里的 2.7:1 接近得多。
	#   ★z 传 0 不是 1: BTN_TEX 是【实心】按钮板(中间不透明), z=1 会把它画在内容之上、
	#     整块盖住(卡框能透是因为它中间是透明的)。弹层的底板本来就该在内容【后面】。
	_nine(pan, BTN_TEX, BTN_MARGIN, Vector2.ZERO, Vector2(pw, ph), 0)

	# ★把原来那两个构建函数【原样画进弹层】—— 它们已经改成接受 host/ox/oy,
	#   所以这里不需要复制一份布局代码(复制就会有两份会漂的实现)。
	if kind == "bench":
		_build_bench_preview(pan, 40.0 - GRID_X, 44.0 - BENCH_Y)
	else:
		_build_lineup_equips(pan, 40.0 - GRID_X, 44.0 - LINEUP_Y)

	var cl := Button.new()
	cl.text = "关闭"
	cl.add_theme_font_size_override("font_size", 18)
	cl.position = Vector2(pw - 150.0, ph - 66.0); cl.size = Vector2(110, 46)
	cl.pressed.connect(func(): lay.queue_free())
	_skin_button(cl); pan.add_child(cl)
