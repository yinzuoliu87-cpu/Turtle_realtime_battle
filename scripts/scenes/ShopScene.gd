extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
const TutorialGuide = preload("res://scripts/scenes/TutorialGuide.gd")   # 教程锚点: vis_rect(只认真看得见的控件)
var _top_bar = null

## ShopScene — V2 局外商店 (阶段2, 设计§五/§十一). 10 卡货架, 用 meta_deepsea_coins 买装备入持久背包.
## 刷新固定 2 币; 买价 = 装备 cost (几费卖几深海币, 1:1, 用户 2026-07-01); 出货档随赛季总战斗数. 复用 Phase2Equip.roll_shop 出货算法.

const W := 1280.0
const H := 720.0
## 装备逐星属性表 —— 与战斗实装/背包/图鉴【同一张表】(CLAUDE.md §1: 装备属性的真事实源)
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")
## 类型羁绊: 阈值/档位/类型映射 —— 与背包羁绊面板/战斗侧同一份(2026-08-11 商店信息栏显示羁绊)
const Phase2Types = preload("res://scripts/gamedata/phase2_types.gd")
const AxeEvo = preload("res://scripts/gamedata/axe_evolution.gd")   # 096 小木斧: 形态/售价/出货概率
const AxePanel = preload("res://scripts/scenes/shop/axe_panel.gd")   # 096: 砍伐进度条 + 最终造物四选一
const AxeEvoShow = preload("res://scripts/scenes/shop/axe_evo_show.gd")   # 096: 进化演出
## 深海币图标 —— 复用主菜单那张(MainMenuScene:564 `mic + "ic-deepsea.png"`)。
## ★用户 2026-07-28「深海币可以复用吧」: 商店原先 6 处全在打 emoji 💠(方片), 而主菜单/局内
##   是这枚螺旋贝币 —— 同一种货币两套视觉。emoji 还随系统字体变, 换机器就换样。
const COIN_TEX = preload("res://assets/sprites/menu/ic-deepsea.png")
## 进度条框 —— 与战斗 HUD 的血条/龟能条【同一张】(`battlehud/bar-frame.png`, 96×24)。
## ★为什么不是两个 ColorRect(2026-09-28): 「底一块 + 填一块」的纯色矩形正是
##   `info_panel.gd:1390` 那段注释记下的用户原话「血条，龟能条都跟网页一样」——
##   CSS 进度条的长相。那边 2026-08-17 就换成这张斜切金属槽了, 而商店的
##   等级经验条 / 砍伐经验条**两条都还是纯色矩形**, 是本屏最后两处网页盒子。
## ★边距是量过的(见 info_panel 同名注释): 黑槽 x 8..87 / y 5..18 ⇒ 左右 11 / 上下 6,
##   各留 2~3px 把斜切角整个盖进角块。⚠ 上下 6+6=12 < 条高(16/20), 中段不会被压成负。
const BAR_TEX = preload("res://assets/sprites/battlehud/bar-frame.png")
const BAR_MARGIN_X := 11
const BAR_MARGIN_Y := 6
## ★固化版式(方案书 docs/plans/20260729c-商店页重设计.md §7.3) —— 每个数都算过, 总计 716 < 720。
##   改这里要同步跑 tests/verify_shop_layout.gd(不超界 + 按钮 ≥44px)。
##   为什么不用容器自动布局: 全文件既有风格就是绝对坐标, 混两套更难维护。
## ★★2026-10-21 手机优先重排(方案书 20261018-商店背包合一.md「手机优先重排」一节)。
##   iPhone 6.1" 实拍: 宝箱只露半截、货架伸出屏幕、字 1~2 毫米、可点的 10 件挤在右半。
##   ⇒ 版式只认【安全设计区】: 设计框 1280×720 居中(宽屏两侧 ≥142 设计像素 > 刘海 / 圆角 111),
##     底边只用到 SAFE_BOTTOM(iPhone 底部横条 21pt ≈ 38 设计像素), 其余是铺满整窗的场景底图。
##   换算: iPhone 横屏高 402pt = 720 设计像素 ⇒ 1pt ≈ 1.8 设计像素; 44pt 触控 = 81(全项目同一个数);
##     最小字号 20(≈ 11pt)。门禁 tests/verify_shop_inv_phone.gd 在 19.5:9 / 16:9 / 4:3 三种比例下量。
const SAFE_BOTTOM := 682.0
const MIN_FONT_PX := 20
## 货柜(2026-10-21 用户「右边这个柜子不能在往左边变大一下吗」): 新画的宽货柜 shop-shelf-wide.png,
##   原生 324×192, 两层板从左立柱通到右立柱。★倍率 = 场景底图同一个(W/384), 像素粗细一致。
##   量的(原生): 立柱内沿 x28 / x296, 上层板面 y94, 下层板面 y149, 下层板沿底 y166; y171..192 是通长底座(10-21 补)。
const CAB_TEX = preload("res://assets/sprites/shop/shop-shelf-wide.png")
const CAB_SCALE := 1280.0 / 384.0
const CAB_X := 1262.0 - 324.0 * CAB_SCALE   # 182
## 底沿 = SAFE_BOTTOM; 顶上的横梁 / 绳子藏进顶栏(87)下面, 像从顶梁上挂下来。
const CAB_Y := SAFE_BOTTOM - 192.0 * CAB_SCALE   # 42
const BOARD_X := CAB_X + 28.0 * CAB_SCALE  # 板左沿(左立柱内沿) 275
const SLOT_W := 268.0 * CAB_SCALE / 5.0    # 一格商品的宽 178.7(5 格 = 两根立柱之间)
const SLOT_H := 120.0                      # 物品(108)立在板面上; 价签也立在板面上(格底 = 板面)
const BOARD_TOP_Y := CAB_Y + 94.0 * CAB_SCALE    # 上层板面 355
const BOARD_LOW_Y := CAB_Y + 149.0 * CAB_SCALE   # 下层板面 539
const BOARD_LOW_BOTTOM := CAB_Y + 166.0 * CAB_SCALE   # 下层板沿底 595(刷新 / 锁定 / 买经验那一排在它下面)
const GRID_X := BOARD_X                    # 货架左沿
const GRID_Y := BOARD_TOP_Y - SLOT_H       # 上层商品格的顶 235
const GRID_GAP_X := 0.0
const GRID_GAP_Y := BOARD_LOW_Y - BOARD_TOP_Y - SLOT_H   # 下层格顶 = 下层板面 - SLOT_H
const ITEM_W := 116.0                      # 物品图标
const ITEM_H := 108.0
const ITEM_X := 4.0                        # 物品在格里偏左, 右脚边立价签
## 价签(用户 2026-10-21「而且价格标签你在弄啥？」): 原来是深色方块 + 一圈费用色描边的 UI 框, 首尾相接
##   盖满整条板沿。改成新画的像素立牌(price-tag.png 原生 22×20, 同倍率), 立在物品右脚边的板面上,
##   大号数字; 费用档只用牌面左上一颗色点(参考背包乱斗的纸牌价签)。
const TAG_TEX = preload("res://assets/sprites/shop/price-tag.png")
## 5×7 像素数字(价签用, 逐行 5 位, 1 = 画; 画时横向加粗 1 列 ⇒ 6×7)。在价签原生像素格(22×20)上画, 与价签同倍率放大 ⇒ 两者像素一样大。
const PRICE_DIGITS := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}
## 价签正面牌面(原生): x7..20, y3..16 ⇒ 中心 (13.5, 9.5)
const PRICE_FACE_CX := 13.5
const PRICE_FACE_CY := 9.5
static var _price_tex_cache: Dictionary = {}

static func _price_tex(price: int, col: Color) -> Texture2D:
	var key := "%d|%s" % [price, col.to_html()]
	if _price_tex_cache.has(key):
		return _price_tex_cache[key]
	var txt := str(price)
	var img := Image.create(22, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var w: int = txt.length() * 7 - 1      # 每字 5 列 + 加粗 1 列, 字间 1 列
	var x0: int = int(floor(PRICE_FACE_CX - float(w) * 0.5 + 0.5))
	var y0: int = int(floor(PRICE_FACE_CY - 3.5 + 0.5))
	for k in range(txt.length()):
		var g: Array = PRICE_DIGITS.get(txt[k], [])
		for row in range(g.size()):
			var line: String = g[row]
			for c in range(line.length()):
				if line[c] == "1":
					var py: int = y0 + row
					for dx in [0, 1]:   # 横向加粗 1 像素(1 像素笔画在手机上太细)
						var px: int = x0 + k * 7 + c + dx
						if px >= 0 and px < 22 and py >= 0 and py < 20:
							img.set_pixel(px, py, col)
	var tex := ImageTexture.create_from_image(img)
	_price_tex_cache[key] = tex
	return tex
const TAG_W := 22.0 * CAB_SCALE            # 73
const TAG_H := 20.0 * CAB_SCALE            # 67
## 小卡宽 / 小卡里小木斧进度块的宽度(= 小卡宽 - 左右内边距)
## 说明卡宽(2026-10-22 用户「把卡片宽度加宽」400 → 600): 货架 5 列左沿 275 / 454 / 633 / 811 / 990,
##   左两列弹在右边、其余弹在左边 ⇒ 最紧的是第 2 列(633 − 8 − 宽 ≥ LEFT_X 18)⇒ 上限 607, 取 600(第 2 列弹卡时离左沿还剩 7)。
const CARD_W := 600.0
const AXE_IN_CARD_W := CARD_W - 30.0
## 卡头右上角「购买」的宽: 放得下最长的那句「还差 12 枚深海币」(22 号字 9 个字 + 内边距)。
const BUY_W := 240.0
## 左栏(货柜左边): 只站店主。★2026-10-21 用户「商店要这么搞」: 羁绊与背包那一排不在商店里(背包页才有)。
const LEFT_X := 18.0
const LEFT_R := CAB_X - 8.0
const MIN_TOUCH_H := 81.0   # 移动端触摸目标最低高度(用户2026-07-28「买经验按钮很小」: 原36不达标)
const REFRESH_COST := 2   # 刷新花费。原 phase2_config 那套(SHOP_REFRESH_BASE + shop_refresh_cost())已随死代码清理删除, 现在这里是唯一来源(2026-07-19)
## 原背景 shop-bg.png(PixelLab 原生 384×216)不再直接画: 底图 / 货柜两张都是从它离线切出来的(见 _build_backdrop / CAB_TEX)。
const PRICE_MULT := 1        # 售价 = 装备 cost (费) × 1 = 几费卖几深海币 (用户 2026-07-01; 原 ×3 占位已改)
const Phase2Equip = preload("res://scripts/gamedata/phase2_equip.gd")
const P2 = preload("res://scripts/gamedata/phase2_config.gd")

var _offer: Array = []
var _rng := RandomNumberGenerator.new()
var _tut_coin: Label = null   # 教学高亮"深海币"锚点(每次 _rebuild 重设)
var _tut_xp_btn: Button = null   # 教程高亮「买经验」钮(每次 _rebuild 重设)
var _tut_buy_btn: Button = null  # 教程手势指针: 详情面板里买得起时的「购买」钮
var _sel: int = -1            # 当前选中的货架格(两步购买: 点卡选中 → 面板里确认)
## 当前选中的【已拥有装备】id。与 _sel 互斥: 选了货架格就清空它, 反之亦然。
## ★为什么要这个: 背包格/龟身格原来只有 tooltip_text 能看名字 —— 手机没有 hover, 等于看不到。
##   这正是本次重设计要根治的坑(货架卡片的描述原来也藏在 tooltip 里), 底部两栏当时漏了。
##   现在点一下就把详情送进右侧同一块面板, 不新开弹窗。
var _sel_own: String = ""
var _sel_own_star: int = 1
## ★买和装同一屏(2026-10-18·方案书 20261018-商店背包合一.md): 右侧常驻阵容 + 底部背包条。
##   `_sel_bench` = 背包条里选中的「待装」那件(下标), 名字与 InventoryScene 同 ——
##   因为装/卸/卖直接复用背包页那套 `InvOps`, 它按这个名字读写宿主。
var _sel_bench: int = -1
var _inv_ops := InvOps.new(self)
var _chest := ShopChest.new(self)
var _amb := ShopAmbience.new(self)   # 灯笼光闪 / 水泡 / 货品轻浮(用户 2026-10-21「商店需要动态」)
var _toast_node: Label = null   # 一句话提示(见 _toast); 同时只留一条
var _insp := InspectCard.new(self)   # 说明小卡(与局内信息面板同一张)
var _ui_layer: Node = null           # InspectCard 往这里挂卡(= 本场景)
var _show_odds := false         # 点「Lv」切换: 等级行上方显示各费用出货概率
var _coin_box: Control = null   # 顶栏里的深海币(图标 + 数字)
## 小木斧待选最终造物那张(自动弹的)被点空白收起了 ⇒ 本次进店不再自动弹(见 _dismiss_popups)
var _axe_card_closed := false
## 买成之后这个时刻(毫秒)之前, 货架上的真点击不选货 —— 挡「双击购买」的第二下点穿到卡下面那件(见 _card)
var _shelf_tap_after_ms := 0
const BUY_TAP_GUARD_MS := 400

func _ready() -> void:
	var _td = get_node_or_null("/root/TutorialDirector")
	var _in_tut: bool = _td != null and _td.is_active()
	if int(GameState.season_total_battles) <= 0 and not _in_tut:
		_build_locked()   # 商店锁: 本大轮未打第一场 → 不开店(用户2026-07-18「商店打完第一场后解锁」)
		return             # ★教学沙盒不计战斗数(不给奖励)→ 会永远锁; 教学模式旁路开店(用户2026-07-23"教买装备")
	## ★test_mode 下用固定种子, 不 randomize(): 货架是随机掷的 ⇒ 每次跑出来的卡片/样式数都不同,
	##   任何"数一数商店里有几个 X"的门禁都会**随机红**。2026-08-19 实测同一份代码连跑三次拿到 0/1/3。
	##   ⇒ 把被测对象钉死, 比把阈值放宽诚实(放宽只是让判据看不见问题)。
	if GameState.test_mode:
		_rng.seed = 20260819
	else:
		_rng.randomize()
	# ★货架要跨场景保留 —— 原来这里无条件 _roll(), 于是每次退出重进都重掷:
	#   买掉的位子会复活、看中的货被冲掉(用户 2026-07-21 报的 bug)。
	#   现在只有【打完新的一场】(season_total_battles 变了)才自动换货, 否则恢复上次的货架。
	if not _restore_offer():
		_roll()
	_rebuild()
	_wallet_gain()
	get_viewport().size_changed.connect(_on_vp_resized)
	if OS.has_environment("SHOP_SHOT"):   # dev: 商店自截图(SHOP_SHOT=秒 SHOT_SEL=选中第几格 SHOT_OUT=路径)·截完自退
		_shop_selfshot()
		return
	if _td != null:
		_td.attach_guide(self, "shop")          # 教程: 买经验升 2 级 → 买 1 件装备 → 点击背包


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
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT") if OS.get_environment("SHOT_OUT") != "" else "res://_shop.png")
	get_tree().quit()

## 从 GameState 恢复货架。成功返回 true; 货架不存在/已过期(打过新战斗)返回 false。
## ★上了锁(meta_shop_locked)就**不看**场次戳 —— 打完多少场都恢复原货架(云顶的锁)。
##   恢复后把戳补成当前场次: 否则解锁那一刻再进店, 戳还是旧的 ⇒ **立刻**换货,
##   而云顶的解锁是「下一回合才刷」, 不是「解锁即刷」。
func _restore_offer() -> bool:
	var _locked: bool = bool(GameState.meta_shop_locked)
	if not _locked and int(GameState.meta_shop_battles) != int(GameState.season_total_battles):
		return false      # 打过新的一场 → 该换货了
	var saved: Array = GameState.meta_shop_offer
	if saved.is_empty():
		return false
	if _locked and int(GameState.meta_shop_battles) != int(GameState.season_total_battles):
		GameState.meta_shop_battles = int(GameState.season_total_battles)
		GameState.save()
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
	## ★文案换成摊主的口气(2026-09-28 用户「全是 ai 味和网页味, 文字语言也是」)。
	##   原「商店未开 / 本大轮打完第一场战斗后开店」是一句**系统状态播报**:
	##   主语是"商店"这个功能模块, 句式是"条件 + 后 + 动作"——那正是网页提示条的写法。
	lbl.text = "商店未解锁\n\n本大轮首战后解锁"
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(vw / 2.0 - 320.0, 250.0); lbl.size = Vector2(640, 180)
	add_child(lbl)
	## ★上锁屏也要换薄片(2026-09-19) —— 本文件自己的注释就写过
	##   「有 early return 的地方就要各自收口」, 我第一遍又只改了正常态那条分支,
	##   门禁当场拓出来(还是 120×44 = 24pt, 低于触控下限)。
	_top_bar = TopBar.new(self, {
		"palette": TopBar.WOOD,   # 2026-10-18 整页重做: 场景是木头货铺, 顶栏跟着木色
		"width": W,
		"on_back": func(): SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn"),
	})
	# ★上锁屏也要套设计框 —— _ready 在这条分支上是 `_build_locked(); return`,
	#   末尾那句 UIFrame.attach 【根本走不到】。我第一版就漏了这条路径, 于是量出来
	#   "商店完全没居中", 实际量的是这一屏。有 early return 的地方就要各自收口。
	UIFrame.attach(self)
	_pin_top_bar()

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
	## ★096 小木斧的出货是【独立的一条通路】(方案书四期 / 未决点 ⑫)。三种模式:
	##   ""      没激活斧头羁绊 → 什么都不做, 走常规 1 费档(它本来就是 1 费, 天然成立)
	##   "off"   已选完最终造物 → 从池里剔掉, 彻底不再出货
	##   "indep" 已激活羁绊 → 先从常规池剔掉, 再按每格独立概率铺回去
	##           (不剔就是**两条路叠加**, 实际概率比标称的高)
	var _axe_mode: String = AxeEvo.shelf_mode(GameState.axe_synergy_active(), GameState.axe_final)
	var _axe_def = null
	if _axe_mode != "":
		var _kept: Array = []
		for e2 in pool:
			if e2 is Dictionary and str((e2 as Dictionary).get("id", "")) == "p2eq_096":
				_axe_def = e2
			else:
				_kept.append(e2)
		pool = _kept
	_offer = Phase2Equip.roll_shop(pool, _shop_level(), 10, _rng)
	## ★每格概率由【整货架至少出一个】反解而来(AxeEvo.slot_prob), 不是把 3% 直接当每格用。
	##   槽数必须与上面 roll_shop 的 count 是**同一个数** —— 分头写死两个 10 就会漂。
	if _axe_mode == "indep" and _axe_def != null:
		var _q: float = AxeEvo.slot_prob(GameState.axe_syn_matches, _offer.size())
		for _i in range(_offer.size()):
			if _rng.randf() < _q:
				_offer[_i] = _axe_def
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

## ★096 小木斧的【形态与售价随进化变】(方案书四期)。返回**浅拷贝**, 原 edef 一个字段不碰。
##   为什么不直接改 `_offer` 里那份: 货架是**落盘持久化**的(_persist_offer), 写脏了就等于
##   把形态冻在掷货那一刻 —— 进化之后要等下一次刷新才更新, 而刷新要花钱。
##   `id` 保持不变 ⇒ 拿装饰后的 edef 去 pool_take / 进背包 / _price 全都对。
##   其余 95 件**原样返回**(连 duplicate 都不做), 免得每次重绘白拷 95 个字典。
func _deco(edef) -> Dictionary:
	if not (edef is Dictionary):
		return {}
	if str((edef as Dictionary).get("id", "")) != "p2eq_096":
		return edef
	var d: Dictionary = (edef as Dictionary).duplicate()
	var disp: Dictionary = AxeEvo.display(GameState.axe_stage, GameState.axe_final)
	d["name"] = str(disp["name"])
	d["cost"] = int(disp["cost"])
	## ★图**不在这里改** —— 换形态已收口到 `EquipIcon.stage_img()`(唯一出口)。
	##   曾经在这儿覆盖 `img`, 结果**只有商店这一屏是对的**, 背包/对局内/图鉴五处全画木斧。
	return d


var _axe_panel = AxePanel.new(self)   # 096 砍伐进度 + 四选一(照 dmg_stats_panel 的拆分模板)
var _axe_evo = AxeEvoShow.new(self)


func _price(edef: Dictionary) -> int:
	return maxi(1, int(edef.get("cost", 1))) * PRICE_MULT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		## ★说明卡 / 出货概率开着时, ESC 先收起它(与点空白同一个动作), 再按一次才离开商店(2026-10-22 交互排查)。
		if _dismiss_popups():
			get_viewport().set_input_as_handled()
			return
		SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn")


## 收起本屏弹出的东西(说明卡 / 出货概率 / 小木斧待选那张)。收了返回 true, 什么都没开着返回 false。
## ★点空白与 ESC 共用这一个出口(2026-10-22 交互排查): 原来点空白只清选中, 概率牌与小木斧那张都关不掉。
func _dismiss_popups() -> bool:
	var any := false
	if _sel >= 0 or _sel_own != "" or _sel_bench >= 0:
		_sel = -1; _sel_own = ""; _sel_bench = -1
		any = true
	if _show_odds:
		_show_odds = false
		any = true
	if not any and _axe_card_wanted() and not _axe_card_closed:
		## 小木斧待选那张是自动弹的、盖住货架左边三列 ⇒ 点空白收起, 本次进店不再自动弹
		##   (四选一仍在每件货的说明卡里, 下次进店也会再弹)。
		_axe_card_closed = true
		any = true
	if any:
		_rebuild()
	return any

# ══════════════════════════════════════════════════════════════
#  §一句话提示 (toast)
# ══════════════════════════════════════════════════════════════
## ★由来(2026-09-29 真机实测): 商店里「按不动」的路径原来**一条反馈都没有** ——
##   满级还去买经验、币不够去买装备, 都是一句 `return` 或一个空的 else。
##   玩家看到的是「点了没反应」, 而那与「游戏卡住了」在屏幕上**长得一模一样**。
##   实测一个只看屏幕的 agent 在满级后连点了 8 下 —— 它不是笨, 是界面没说话。
## ★★不在提示后面调 `_rebuild()`: 背包页那 7 条 toast 全部看不见, 根因就是
##   `host._toast(...)` 的**下一行**就是 `host._rebuild()`, 而 `_rebuild()` 开头把
##   子节点全 `queue_free()` ⇒ 提示生下来那一帧就被销毁。这里的提示只在
##   「什么都没变」的分支出现, 本来就不需要重画; 上一条记在 `_toast_node` 里, 下一条来时先收掉。
const TOAST_W := 640.0
## 168..224: 让出顶栏下沿那一条(首次提示「合成升星」指着顶栏「背包」时贴在它下面), 也不压上层货品(235 起)。
const TOAST_Y := 168.0

func _toast(msg: String) -> void:
	if _toast_node != null and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#ffe9a8"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(TOAST_W, 56)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## ★★y 430 → 656(2026-09-30): 430..474 **正好盖住「换一批」按钮的上沿**
	##   (按钮 y 448..524) —— 而现在最常出现的提示之一就是"深海币不够 · 换一批要 2",
	##   等于一句话挡住它解释的那颗按钮。656..700 落在底栏两颗按钮(552..648)之下、
	##   720 设计框之内, 是本屏唯一一条谁都不压的横带(门禁 BUY_FEEDBACK 会穷举核这一条)。
	##   ⚠ 弹层(z=20)仍被它压住 —— 那是故意的, 见下面 z_index 那行。
	## ★★2026-10-18: 底栏换成背包条(552..657), 右侧阵容面板常驻(x 800 起) ⇒
	##   提示收进卡区宽度 40..780、背包条之下 664..708, 不压背包格也不压面板。
	## ★2026-10-18 整页重做: 提示在左上(羁绊条下面、店主头顶), 不压店主、宝箱和货架。
	## ★2026-10-21 宽货柜: 左栏只剩一根店主宽, 放不下一句话 ⇒ 提示挪到货柜上沿正中(顶栏下、上层货品头顶的灯带上)。
	t.position = Vector2(CAB_X + (1262.0 - CAB_X - TOAST_W) * 0.5, TOAST_Y)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 30       # 底栏弹层是 20 —— 提示必须压得住它
	var bgp := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a1a0e")          # 木色: 与经验条 / 宝箱格同一套
	sb.border_color = Color("#8a5a32")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)   # 全屏统一直角
	bgp.add_theme_stylebox_override("panel", sb)
	bgp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgp.show_behind_parent = true
	t.add_child(bgp)
	add_child(t)
	_toast_node = t
	## 2.4 秒后自己收走。★这里用 `create_timer` 是对的 —— CLAUDE.md §3.5 禁的是
	##   「拿 create_timer 等**游戏内**效果」(战斗时钟走钳制后的 delta), 而商店没有 sim 时钟,
	##   这条量的就是真实时间。
	## ★★ 2026-09-29: 原来用树级 `create_timer` + 闭包 —— 它**会活过场景释放**:
	##   玩家 2.4 秒内离开商店, 回调照样触发。`is_instance_valid` 挡得住崩溃,
	##   挡不住闭包把 self 延寿 —— `tree_timer` 守的正是这个。
	##   ⇒ 换成挂在自己身上的 Timer 子节点: 场景没了它跟着没。
	## ★★★计时器挂在**提示自己身上**, 不挂在场景上(2026-09-30 改):
	##   `_rebuild()` 会把 `self` 的每个直接子节点做 `c.visible = false` —— 而 `Timer`
	##   不是 `CanvasItem`, **没有 `visible` 这个属性** ⇒ 一旦有过 toast, 下一次
	##   `_rebuild()` 当场 `SCRIPT ERROR: Invalid assignment of property 'visible' … on Timer`。
	##   在此之前 `_toast` 只被"什么都没变"的分支调用(那些分支不 `_rebuild`), 所以这颗雷
	##   一直没炸; 我给"买成功"加提示(它后面紧跟 `_rebuild`)第一下就踩到了。
	##   ⇒ 挂在提示 Label 下: 提示被清掉时计时器跟着走, 而 `_rebuild` 永远看不见它。
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = 2.4
	t.add_child(tm)
	tm.timeout.connect(func():
		if is_instance_valid(t):
			t.queue_free())
	tm.start()


func _rebuild() -> void:
	for c in get_children():
		if c.is_in_group("tut_overlay") or c.is_in_group(AxeEvoShow.GROUP):
			continue   # ★教学浮层(引导/下一站按钮)与小木斧进化演出不能随重建销毁 —— 买装备会触发 _rebuild
		## ★`visible = false` 是为了**立刻**从屏上消失(`queue_free` 要等到帧末)。
		##   ⚠ 必须先问是不是 `CanvasItem`: 非 CanvasItem(Timer/AudioStreamPlayer…)
		##     没有 `visible`, 直接赋值会 `SCRIPT ERROR`(2026-09-30 被 toast 的计时器踩出来)。
		if c is CanvasItem:
			(c as CanvasItem).visible = false
		c.queue_free()
	## ★2026-10-18 整页重做(用户「没有任何游戏搞的这种浏览器网页感」): 背景是一张场景图 ——
	##   左边场地站队伍、右边墙上两层货架、左下储物箱。PixelLab 原生 384×216, 最近邻放大。
	var bgc := ColorRect.new(); bgc.color = Color("#06141c")
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bgc)
	## 点空白处 = 收起说明 / 取消选中 / 收起出货概率(没有「×」)
	bgc.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_tap(bgc, func(): _dismiss_popups())
	_build_backdrop()
	_build_cabinet()
	_amb.build(self)

	# ── 头部 y 0–96 ──
	## ★标题「🛒 深海商店」删掉(用户 2026-08-15)。玩家是自己点进来的, 不需要一块牌子告诉他站在哪;
	##   这 200px 让给右上角三组去排版 —— 它们原来因为标题框占着中间, 被挤在 756..1252 的窄带里。

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   146 款触屏游戏里返回一律是**扁平薄片**, 没有一款用厚装饰框。
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		## ★**不给页名** —— 用户 2026-08-15 明确删过「🛒 深海商店」这块牌子
		##   (「玩家是自己点进来的, 不需要一块牌子告诉他站在哪」, 见本文件上方注释)。
		##   我换顶栏时把它加回来了, 实拍一看还把右边的金币条压住了 —— 两错并一错。
		## 2026-10-21 用户「那个顶上横幅？」: 不画深色底带(压在货柜顶梁上像补丁), 薄片换成像素木牌(与底部三块同一张)
		"palette": TopBar.WOOD.merged({"no_plate": true, "chip_tex": PLANK_TEX, "chip_margin": PLANK_MARGIN}),
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		"on_back": func(): SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn"),
		## 左上「← | 商店 | 背包」一对页签, 当前页那一签亮着(用户 2026-10-22「左上角返回，商店，背包你到底打算怎么设计啊」;
		##   与背包页同一对)。「背包」那一签是教程锚点(tutorial_keep / E5「点击背包」) —— 别再按 action_btns[0] 取, 见 _bag_tab()。
		"left_actions": [["商店", func() -> void: pass, {"active": true}], ["背包", _go_inventory, {"tutorial_keep": true}]],
	})

	## ── 头部三组重排(用户 2026-08-15「右上角咋做的, 中间给你这么空位你在干啥啊」)──
	##
	## 删掉标题后中间空出一大片, 而三组还挤在右侧 500px 里 —— 白空着。
	## 现在把它们**均匀铺开在 340..1252**(返回/背包止于 292, 右边距 28), 组间距等宽 131:
	##   币 320..520 | 等级 560..900(条长 340) | 购买说明 940..1096 | 按钮 1112..1252
	## ★用户 2026-08-15 再打回:「进度条太短, 留了很多空位, 右上字体太小, 按钮那么小那么扁干嘛」
	##   ⇒ 全部放大并铺满可用宽度(返回/背包止于 304, 右边距 28)。
	## ★三组竖直中心统一 = 48(门禁⑩量的就是这条基准线)。
	const HDR_CY := 48.0

	# 组1: 深海币 —— 图标 40 + 间隙 12 + 数字 30 号。原来图标 756/数字 794 只隔 6px 挤成一坨。
	## ★装进一个顶栏高的盒子: 4:3(iPad)上顶栏贴视口顶, 币跟着它走(_pin_top_bar), 不留在设计框里。
	_coin_box = Control.new(); _coin_box.name = "CoinGroup"
	_coin_box.position = Vector2.ZERO; _coin_box.size = Vector2(W, TopBar.BAR_H)
	_coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_coin_box)
	## 2026-10-21 用户「背包深海币？」: 原来数字孤零零浮在顶栏中间。⇒ 装进右上角一块木牌(钱袋牌), 贴设计框右沿。
	##   教程里右上角是「跳过」钮 ⇒ 木牌整块左移让开它(verify_tutorial_flow_v3 B7)。
	var cpx: float = COIN_PLAQUE_X - (TUT_SKIP_W + 24.0 if (get_node_or_null("/root/TutorialDirector") != null and get_node("/root/TutorialDirector").is_active()) else 0.0)
	var cplq := _plank(_coin_box, Vector2(cpx, HDR_CY - 40.0), Vector2(1262.0 - COIN_PLAQUE_X, 80.0)); cplq.name = "CoinPlaque"
	_wallet_icon = _coin_icon(_coin_box, Vector2(cpx + 22.0, HDR_CY - 24.0), 48.0)
	var coin := Label.new(); coin.text = "%d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 38); coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.add_theme_color_override("font_outline_color", Color("#1a0e05")); coin.add_theme_constant_override("outline_size", 6)
	## ★高度按【字体最小高度】给(30 号字实测 44), 不是我想给多少给多少 ——
	##   给 38 的话 Label 自己撑到 44, 并集矩形底沿多出 6px, 组中心偏到 50.5 ⇒ 门禁⑩红。
	coin.position = Vector2(cpx + 80.0, HDR_CY - 28.0); coin.size = Vector2(1262.0 - COIN_PLAQUE_X - 100.0, 56)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; _coin_box.add_child(coin)
	_tut_coin = coin   # 教学高亮"币"锚点


	# ── 货架 5×2(货柜两层板上) ──
	for i in range(_offer.size()):
		var col := i % 5
		var row := i / 5
		add_child(_card(i, _shelf_pos(i)))

	## ★★2026-10-04 用户「用商业游戏的词行吗，刷新和锁定」⇒ 改回「刷新」(云顶/酒馆战棋通行叫法), 锁货→「锁定」。
	## (旧注: 「刷新 -2」→「换一批 2」: 「刷新」是浏览器的词, 「-2」是账本的写法。)
	##   摊主的说法是"给我换一批货"; 价钱由按钮上那枚深海币图标讲(`_coin_button_icon`),
	##   不需要再打一个负号 —— 图标本身就说明这 2 是要付出去的。
	## ★2026-10-18 用户「说了几遍了不要用之前的金木框按钮，重新设计一个更好的」:
	##   刷新 / 锁定改成【无框图标钮】—— 新画的像素图标在上、描边字在下, 悬停 / 按下靠亮度变化,
	##   立在货架下沿的沙地上。图标: assets/sprites/shop/icon-refresh / icon-lock-closed / icon-lock-open。
	var rf := _icon_button("ShopRefreshBtn", REFRESH_ICON, "刷新 %d" % REFRESH_COST,
		Vector2(ROW_BTN_X, ROW_BTN_Y), Vector2(ROW_BTN_W, ROW_BTN_H))
	_coin_after_text(rf)
	## ★★买不起时: disabled + 整颗压暗(价钱那枚币是子节点, 只有 modulate 会往下传)。
	var _rf_afford: bool = int(GameState.meta_deepsea_coins) >= REFRESH_COST
	rf.disabled = not _rf_afford
	rf.modulate = Color(1, 1, 1, 1) if _rf_afford else Color(1, 1, 1, 0.42)
	rf.pressed.connect(_on_refresh); add_child(rf)
	## ★disabled 的按钮不发 pressed ⇒ 买不起时真点下去原来什么都没有(`_on_refresh` 里那句提示只有程序直调才到得了)。
	##   点到压暗的「刷新」也要说一句为什么(2026-10-22 交互排查)。
	if not _rf_afford:
		_wire_tap(rf, _on_refresh)
	_build_lock_button(rf.position + Vector2(rf.size.x + LOCK_GAP, 0.0), rf.size.y)
	_build_level_row(rf.position + Vector2(2.0 * (rf.size.x + LOCK_GAP), 0.0))

	## ★2026-10-21 用户「商店里为什么会显示背包的装备和羁绊？」→「对啊，商店要这么搞」+「商店里就不能卖装备」:
	##   羁绊总览与背包那一排(含卖出)不在商店里画, 都在背包页。左边只站店主。
	_chest.build_keeper(self)
	## ★2026-10-18: 说明 = 局内信息面板那张已认可的小卡(InspectCard), 贴着被点的东西弹出、高度随内容。
	##   小木斧的砍伐进度 / 最终造物四选一也装进这张小卡(原来是 440×592 的旧大面板, 打开时盖住
	##   底下刷新 / 锁定 / 买经验三颗键 —— verify_ios_ui「按钮被后画的面板盖住」)。
	_insp.card = null; _insp.key = ""      # 上面整页清过一遍, 那张旧卡已在释放队列里
	if _detail_wanted():
		_open_detail_card()
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 内容装进 1280×720 设计框并居中于真实视口。
	# ★放在 _rebuild 末尾而不是 _ready 末尾 —— 本函数开头会 free 掉【所有】子节点(买一件装备
	#   就触发一次), 框和框里的内容会被一起清掉。attach 是幂等的, 重复调只重新收编+居中。
	UIFrame.attach(self)
	_pin_top_bar()


## 场景底图(2026-10-21): 原背景去掉货柜与左下半截宝箱、四边外扩(shop-backdrop.png, 原生 512×296,
##   场景本体在 (64,40) 起的 384×216, 与原 shop-bg.png 逐像素同一张图)。
## ★为什么要外扩: 设计框 1280×720 在 19.5:9 上两侧各空 142、在 4:3(iPad)上下各空 120 ——
##   原来两侧是把原图边缘镜像接上(右边正好是货柜 ⇒ 镜像出半截「第三列」货架), 上下是纯色黑带。
## ★只画视口里看得见的那一块(AtlasTexture 裁): 整张铺出去会伸出视口(verify_ui_layout「不溢出视口」)。
const BACKDROP_TEX = preload("res://assets/sprites/shop/shop-backdrop.png")
const CRATES_TEX = preload("res://assets/sprites/shop/shop-crates.png")
const BACKDROP_PAD := Vector2(64.0, 40.0)    # 场景本体在外扩图里的原生偏移

func _build_backdrop() -> void:
	var k: float = W / 384.0                         # 原生 → 设计像素(×3.333, 与原背景同倍率)
	var full := Rect2(-BACKDROP_PAD * k, Vector2(BACKDROP_TEX.get_size()) * k)
	## 视口在设计框坐标里的范围(框居中: 偏移 = (可用 - 设计) / 2, 与 UIFrame._center 同一个式子)
	var vs: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var host_sz: Vector2 = size if (size.x >= W and size.y >= 360.0) else vs
	var off: Vector2 = ((host_sz - Vector2(W, H)) * 0.5).round()
	var vis := Rect2(-off, host_sz).intersection(full)
	if vis.size.x < 1.0 or vis.size.y < 1.0:
		return
	var at := AtlasTexture.new(); at.atlas = BACKDROP_TEX
	at.region = Rect2((vis.position - full.position) / k, vis.size / k)
	var bg := TextureRect.new(); bg.name = "ShopBackdrop"
	bg.texture = at
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	## ★它恰好铺满视口 ⇒ UIFrame 当它是满铺层、不收进设计框 ⇒ 坐标按宿主(= 视口)给, 不是按设计框。
	bg.position = vis.position + off; bg.size = vis.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	## 货柜右立柱外侧一堆木箱 / 木桶 / 绳子(用户 2026-10-21「商店为什么不加上最右边的木箱」)。
	##   ★挂在底图上(满铺层): 它在设计框外(x ≥ 1262), 只在宽屏手机上露出来; 16:9 上本来就看不见。
	## 海水那一条(底图原生 y 61..190 ⇒ 场景本体 y 21..150)里的上浮水泡 —— 画在底图之上、货柜之下, 横向铺满视口。
	var wband := Rect2(Vector2(0.0, (61.0 - BACKDROP_PAD.y) * k + off.y) - bg.position, Vector2(host_sz.x, 129.0 * k))
	_amb.build_water(bg, wband)
	##   ★与底图同理只画视口里看得见的那一截(verify_ui_layout「不溢出视口」); 露出来不到 24 像素就不画。
	var cfull := Rect2(Vector2(1256.0, SAFE_BOTTOM + 14.0 - float(CRATES_TEX.get_height()) * k) + off,
		Vector2(CRATES_TEX.get_size()) * k)
	var cvis := cfull.intersection(Rect2(Vector2.ZERO, host_sz))
	if cvis.size.x >= 24.0 and cvis.size.y >= 24.0:
		var cat := AtlasTexture.new(); cat.atlas = CRATES_TEX
		cat.region = Rect2((cvis.position - cfull.position) / k, cvis.size / k)
		var cr := TextureRect.new(); cr.name = "ShopCrates"
		cr.texture = cat
		cr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cr.stretch_mode = TextureRect.STRETCH_SCALE
		cr.position = cvis.position - bg.position; cr.size = cvis.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(cr)


## 货柜(放大摆在右侧, 底沿 = SAFE_BOTTOM)。商品立在它的两层板上。
func _build_cabinet() -> void:
	## 柜子立在地上: 底座下一道阴影(用户 2026-10-21「商店柜子的地下怎么被切了一样」⇒ 底部补了一条通长底座 + 这道影子)
	var sh := ShopChest.ellipse(1270.0 - (CAB_X - 16.0), 26.0, 64, 5, Color(0.05, 0.03, 0.02, 0.45)); sh.name = "CabinetShadow"
	sh.position = Vector2(CAB_X - 16.0, SAFE_BOTTOM - 12.0)
	add_child(sh)
	var cab := TextureRect.new(); cab.name = "ShopCabinet"
	cab.texture = CAB_TEX
	cab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cab.stretch_mode = TextureRect.STRETCH_SCALE
	cab.position = Vector2(CAB_X, CAB_Y)
	cab.size = Vector2(CAB_TEX.get_size()) * CAB_SCALE
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cab)


## 设计框在 4:3(iPad)上被上下居中 ⇒ 顶栏跟着下移 120。顶栏要贴视口顶(与 x 方向 `TopBar._fit_to_viewport` 同理)。
func _pin_top_bar() -> void:
	if _top_bar == null or _top_bar.bar == null or not is_instance_valid(_top_bar.bar):
		return
	var p = _top_bar.bar.get_parent()
	if p is Control:
		_top_bar.bar.position.y = -(p as Control).global_position.y + global_position.y
		if _coin_box != null and is_instance_valid(_coin_box):
			_coin_box.position.y = _top_bar.bar.position.y


## 视口变了(转屏 / 分屏 / 窗口拖动): 底图裁的那一块、顶栏贴顶都要重算 ⇒ 整页重建(本页本来就靠 _rebuild 刷新)。
func _on_vp_resized() -> void:
	if is_inside_tree() and not _offer.is_empty():
		_rebuild.call_deferred()


## ★#2 出货概率行(云顶式): 当前大轮等级下各费用档(1-5)的出货概率%. 每费用色=对应稀有度色, 0%淡显.
func _build_odds_row() -> void:
	var odds: Array = P2.shop_cost_odds(_shop_level())   # [费1% .. 费5%]
	var cost_cols := ["#9aa0b0", "#4ade80", "#60a5fa", "#c084fc", "#fbbf24"]   # 费1-5: 普通灰/精良绿/稀有蓝/史诗紫/传说金
	## ★2026-10-18: 不再常驻在货架上(浮在横梁上看不清, 4/5 费几乎看不见); 点「Lv」时弹在等级行上方。
	var row := HBoxContainer.new(); row.name = "OddsRow"
	row.position = Vector2(ROW_X, ROW_BTN_Y - 50.0); row.size = Vector2(1262.0 - ROW_X - 6.0, 40)
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bgp := Panel.new()
	var bsb := StyleBoxFlat.new(); bsb.bg_color = Color("#2a1a0e"); bsb.border_color = Color("#8a5a32")
	bsb.set_border_width_all(2); bsb.set_corner_radius_all(0)
	bgp.add_theme_stylebox_override("panel", bsb)
	bgp.position = row.position - Vector2(6, 2); bgp.size = row.size + Vector2(12, 4)
	bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE; bgp.name = "OddsPlate"
	add_child(bgp)
	add_child(row)
	## ★★文案去网页味(2026-09-28)。原来这一行是「出货概率 / 费用1 45% / 费用2 30% …」——
	##   一个统计学名词加五组 `label: value`, 读起来是后台报表, 不是摊位。
	##   改成摊主挂的牌子「今日货源」+「1费 45%」: 数字一个不少(用户 2026-08-12 点名要数字),
	##   但把字段名那一半去掉 —— 颜色已经在讲"这是哪一档"(与卡框同一套 5 色)。
	var lbl := Label.new(); lbl.text = "商品"
	lbl.add_theme_font_size_override("font_size", MIN_FONT_PX); lbl.add_theme_color_override("font_color", Color("#e8dcc4"))
	row.add_child(lbl)
	for c in range(5):
		var pct: int = int(odds[c]) if c < odds.size() else 0
		var chip := Label.new()
		## ★数字与汉字之间要有空格 —— json 侧的文案门禁焊了这条, UI 侧一直没人管,
		##   于是同一个游戏里「1 费」和「费用1」两种写法并存。跟 json 的口径。
		chip.text = "%d 费 %d%%" % [c + 1, pct]
		chip.add_theme_font_size_override("font_size", MIN_FONT_PX)
		var cc := Color(cost_cols[c])
		chip.add_theme_color_override("font_color", cc if pct > 0 else Color(0.55, 0.5, 0.45))
		row.add_child(chip)


# 已拥有该装备件数(背包+统领已装+小将已装): 商店卡标"已有N"→知道再买几件凑3合1升星(用户2026-07-18"看不到已装备/不知道多少件才2/3星")
## 已拥有的【指定星级】件数。★star 参数不是可有可无的 ——
##
## GameState.auto_merge_all() 的合成键是 "id|star": 必须【同 id 且同星】的 3 件才合。
## 本函数原先不分星级地数, 于是探针(tests/verify_shop_merge_pips.gd)实测到:
##   背包 1×★2 + 1×★1 → 数出 2 → 商店显示「合成进度 2/3」、圆点亮 2 颗
##   再买 1 件 ★1 → ★1=2 / ★2=1, 【根本没合成】—— 显示在骗人。
## 商店只卖 ★1, 所以进度一律按 ★1 数。
func _owned_count(item_id: String, star: int = 1) -> int:
	return int(GameState.copies_of(item_id, star))   # 2026-10-22 收拢到 GameState(背包合成进度同一个数)

## 「背包里有没有这件」: 不分星级(货架上的已拥有提示用)。合成进度仍用上面分星级的 `_owned_count`。
func _owned_any_star(item_id: String) -> int:
	return _owned_count(item_id, 1) + _owned_count(item_id, 2) + _owned_count(item_id, 3)


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

func _shelf_pos(i: int) -> Vector2:
	return Vector2(GRID_X + (i % 5) * (SLOT_W + GRID_GAP_X), GRID_Y + (i / 5) * (SLOT_H + GRID_GAP_Y))


## 货架上的一件商品 —— ★2026-10-18 整页重做: 不再是方框卡片。
##   物品直接立在背景图的木板上, 价签挂在板沿(背包乱斗 / The Bazaar 的写法)。名字不写在货架上
##   (点了在详情卡里看), 档位由价签边色表示。买走的位置空着(板上就是空的)。
func _card(idx: int, pos: Vector2) -> Control:
	var box := Control.new(); box.name = "ShelfItem%d" % idx
	box.position = pos; box.size = Vector2(SLOT_W, SLOT_H)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	if _offer[idx] == null:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return box
	var edef: Dictionary = _deco(_offer[idx])
	var sel: bool = idx == _sel
	var price := _price(edef)
	var afford := int(GameState.meta_deepsea_coins) >= price
	## 选中: 物品身后一圈金光
	if sel:
		var sg := ShopChest.ellipse(ITEM_W + 8.0, ITEM_H, 26, 22, Color(1.0, 0.86, 0.35, 0.45)); sg.name = "SelGlow"
		sg.position = Vector2(ITEM_X - 4.0, 0.0); box.add_child(sg)
	## 已拥有同款: 身后一团呼吸的淡金光(原卡片镀层的同一个意思, 换成不带框的光)
	## ★数【任何星级】(用户 2026-10-22「背包里有二星，不提示吗」): 原来借的是合成进度那个口径 `_owned_count(id)`,
	##   它默认只数 ★1(07-29 为「合成进度 N/3」改的) ⇒ 背包里只有 ★2 时这里是 0, 一点提示都没有。
	var owned := _owned_any_star(str(edef.get("id", "")))
	if owned > 0:
		## 用户 2026-08-14「背包里有的装备在货架栏出现时要有镀层闪光效果」: 身后一团呼吸淡金光 + 一道斜掠高光。
		var glow := ShopChest.ellipse(ITEM_W + 8.0, ITEM_H, 24, 20, Color(1.0, 0.84, 0.35, 0.30)); glow.name = "OwnedGlow"
		glow.position = Vector2(ITEM_X - 4.0, 0.0); box.add_child(glow)
		var bt := TweenKit.loop_bound(self, glow)
		bt.tween_property(glow, "modulate:a", 0.12, 0.9).set_trans(Tween.TRANS_SINE)
		bt.tween_property(glow, "modulate:a", 0.30, 0.9).set_trans(Tween.TRANS_SINE)
		var shine_box := Control.new(); shine_box.name = "OwnedShine"
		shine_box.position = Vector2(ITEM_X, 0.0); shine_box.size = Vector2(ITEM_W, ITEM_H)
		shine_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(shine_box)
		var shine_clip := _clip_box(shine_box)
		var shine := ColorRect.new()                          # 斜掠高光: 从左下扫到右上
		shine.color = Color(1.0, 0.95, 0.7, 0.22)
		shine.size = Vector2(18, SLOT_H * 1.6)
		shine.rotation = -0.5
		shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shine.position = Vector2(-40, -20)
		shine_clip.add_child(shine)
		var st2 := TweenKit.loop_bound(self, shine)
		st2.tween_property(shine, "position:x", float(SLOT_W) + 40.0, 1.4).set_trans(Tween.TRANS_SINE)
		st2.tween_interval(1.6)
		st2.tween_callback(func() -> void:
			if is_instance_valid(shine): shine.position.x = -40.0)
	## 物品本身(大图标, 底沿贴着板面)
	var ic := EquipIcon.make(edef, Vector2(ITEM_W, ITEM_H))
	ic.name = "Item"
	ic.position = Vector2(ITEM_X, SLOT_H - ITEM_H)   # 底沿踩在板面(格底 = 板面), 偏左, 右脚边让给价签
	box.add_child(ic)
	_amb.bob_item(ic, idx)
	## 这一买会合成到几星
	var will_star := _purchase_merge_star(str(edef.get("id", "")))
	if will_star >= 2:
		for k in range(will_star):
			_glint_star(box, Vector2(ITEM_X + ITEM_W - 20.0 - k * 20.0, 4), 20.0, k * 0.3)
	## 价签: 立在物品右脚边板面上的像素立牌(TAG_TEX)。大号深色数字; 买不起 = 红字。
	##   费用档(用户 2026-07-29「框框随费用变化」)只用牌面左上一颗色点, 不再整圈描边。
	var tag := TextureRect.new(); tag.name = "PriceTag"
	tag.texture = TAG_TEX
	tag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tag.stretch_mode = TextureRect.STRETCH_SCALE
	tag.position = Vector2(SLOT_W - TAG_W - 6.0, SLOT_H - TAG_H + 4.0); tag.size = Vector2(TAG_W, TAG_H)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(tag)
	var dot := ColorRect.new(); dot.name = "CostDot"
	dot.color = _cost_color(int(edef.get("cost", 1)))
	## 牌面右上角(原生 16,1)一颗色点, 外圈 1 像素深边; 不进数字那块
	var dot_edge := ColorRect.new(); dot_edge.color = Color("#3a2414")
	dot_edge.position = Vector2(16.0, 1.0) * CAB_SCALE; dot_edge.size = Vector2(4.0, 4.0) * CAB_SCALE
	dot_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE; tag.add_child(dot_edge)
	dot.position = Vector2(1.0, 1.0) * CAB_SCALE; dot.size = Vector2(2.0, 2.0) * CAB_SCALE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE; dot_edge.add_child(dot)
	## 价签数字(用户 2026-10-21「价签上的数字换成像素字体」→「这个3你没觉得歪吗」):
	##   字体渲染的像素格(×3)和价签的像素格(×3.33)对不上, 又偏在牌面左边 ⇒ 改成在价签【原生像素格】上逐点画 5×7 数字,
	##   与价签同一张贴图倍率放大, 居中在正面牌面(原生 x7..20 / y3..16)。
	var pr := TextureRect.new(); pr.name = "Price"
	pr.texture = _price_tex(price, Color("#3a2414") if afford else Color("#c0262b"))
	pr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; pr.stretch_mode = TextureRect.STRETCH_SCALE
	pr.position = Vector2.ZERO; pr.size = tag.size
	pr.tooltip_text = "%d" % price
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(pr)
	if not afford:
		ic.modulate = Color(0.45, 0.48, 0.55)
	for ch in box.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = str(edef.get("name", ""))
	_wire_tap(box, func():
		## ★买完那一刻的连点不算选货(2026-10-22 交互排查): 说明卡买完就收起, 双击「购买」的第二下
		##   落到卡下面那件货上 ⇒ 又自动选中了别的一件。只拦真点击, 程序调 _on_select 不受影响。
		if Time.get_ticks_msec() < _shelf_tap_after_ms:
			return
		_on_select(idx))
	return box


## 点按 = 松手时位移很小(手指在屏上滑一下不算点)。
func _wire_tap(ct: Control, fn: Callable) -> void:
	var st := {"p": Vector2.ZERO}
	ct.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				st["p"] = ev.position
			elif (ev.position - st["p"]).length() < 12.0 and not get_viewport().gui_is_dragging():
				fn.call())


## 一张【卡大小的剪刀】: 装那些"斜着画、必然超出卡片轮廓"的东西(掠光 / 斜纹)。
##
## ★为什么必须有它: Godot 的 Control **默认不裁子节点**。一条旋转过的长条只要比卡长,
##   多出来的部分就直接画到卡外的空隙上 —— 2026-09-28 实拍抓到的掠光溢出就是这么来的,
##   而且**没有任何门禁能响**(溢出的是 ColorRect, 不是文字也不是框)。
## ★两处共用一个函数: 斜向元素以后再加第三个, 也不会有人忘了套剪刀。
func _clip_box(parent: Control) -> Control:
	var clip := Control.new()
	clip.position = Vector2.ZERO
	clip.size = parent.size if parent.size.x > 0.0 else Vector2(SLOT_W, SLOT_H)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(clip)
	return clip




## 点卡 → 选中(两步购买第一步)。再点同一张 = 取消选中。
func _on_select(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	_sel = -1 if _sel == idx else idx
	_sel_own = ""          # 与"已拥有"选中互斥 —— 同一块面板同时只讲一件事
	_sel_bench = -1        # 看货架就不再选着宝箱里那件
	_show_odds = false     # 出货概率牌与说明卡同时只开一个(卡底会压住概率牌, 2026-10-22 交互排查)
	_rebuild()
	if _sel >= 0:
		_tut_notify("offer_selected")   # 教程 v3「点击一件装备」(两步购买的第一步; 取消选中不算)


## 说明小卡。货架上的 = 卡底一颗「购买」; 宝箱里的 = 只看(卖出在宝箱格旁)。
func _open_detail_card() -> void:
	_ui_layer = self
	## 什么都没选、但小木斧攒够了待选最终造物 ⇒ 直接弹小木斧自己那张(这一步错过就做不了最终进化)
	## ★按「选着的那格真有货」判, 不按 `_sel < 0`: 买走后 `_sel` 若还指着那个空格, 这里原来走货架分支、
	##   读到 null 直接 return ⇒ 小木斧四选一那张整个消失(2026-10-22 交互排查)。
	var axe_only: bool = not _shelf_sel_valid() and _sel_own == ""
	var own: bool = _sel_own != "" or axe_only
	var own_id: String = AxePanel.EID if axe_only else _sel_own
	var edef: Dictionary = _deco(DataRegistry.phase2_equipment_by_id.get(own_id, {})) if own else _deco(_offer[_sel])
	if edef.is_empty():
		return
	var eid := str(edef.get("id", ""))
	var star: int = _sel_own_star if own else 1
	var cost: int = int(edef.get("cost", 1))
	var col: Color = _cost_color(cost)
	var stats: Array = []
	## 属性行 = 图标 + 数值(与局内信息面板的装备小卡同一种写法, 同一张对照表)
	for kv in EquipStats.stat_lines(eid, star):
		stats.append(InspectCard.eq_stat_row(kv, Color("#f4ead8")))
	## 没属性的装备明说(与背包 `_stat_block` 逐字同一句, verify_shop_layout ⑭)
	if stats.is_empty():
		stats.append(["", "无属性加成", Color("#a89c86")])
	var img := str(edef.get("img", ""))
	var tp := str(Phase2Types.type_of(eid))
	## 标签 = 「N 深海币  ·  [类型图标] 类型」(与旧详情面板的价格行同一格式, 门禁 ⑫ 解析它)
	var tag_bb := ("[color=#ffd93d]%s[/color]" % "★".repeat(clampi(star, 1, 3))) if own else ("%d 深海币" % _price(edef))
	if tp != "":
		tag_bb += "  ·  " + Phase2Types.icon_bb(tp, 16) + " " + tp
	## 「购买」在卡头右上角(用户 2026-10-22「你不要把购买按钮放地下，去放右上角」):
	##   原来压在卡底占一整行 81 高 —— 说明卡封顶高度里, 那一行正好是正文最缺的地方。
	var buy: Button = null
	if not own:
		var price := _price(edef)
		var coins := int(GameState.meta_deepsea_coins)
		buy = Button.new(); buy.name = "BuyBtn"
		_card_button_skin(buy)
		buy.custom_minimum_size = Vector2(BUY_W, MIN_TOUCH_H)
		buy.size_flags_horizontal = Control.SIZE_SHRINK_END
		if coins >= price:
			buy.text = "购买  %d" % price
			buy.pressed.connect(func(): _on_buy(_sel))
			_tut_buy_btn = buy
		else:
			buy.text = "还差 %d 枚深海币" % (price - coins)
			buy.disabled = true
	var lv: Dictionary = _insp.open(("own:" if own else "shop:") + eid, null, {
		"icon": ("res://assets/sprites/" + img) if img.ends_with(".png") else "",
		"title": str(edef.get("name", eid)), "title_col": col,
		"icon_border": col, "frame_col": col,
		"tag_bb": tag_bb, "tag_col": Color("#e8dcc4"),
		"stats": stats,
		"body": _rich_desc(edef, star), "body_px": MIN_FONT_PX,
		"width": CARD_W, "min_px": MIN_FONT_PX,
		"head_right": buy,
	})
	if not lv.has("vbox"):
		if buy != null:
			buy.queue_free()          # 卡没开出来(再点一次 = 收起): 这颗没挂上树, 别漏掉
		return
	## 小木斧: 砍伐进度条 + (攒够时)最终造物四选一, 接在说明下面
	if AxePanel.should_show(GameState) and (eid == AxePanel.EID or AxeEvo.final_ready(
			int(GameState.axe_exp_bar), int(GameState.axe_stage), str(GameState.axe_final))):
		var hold := Control.new(); hold.name = "AxeProgress"
		(lv["vbox"] as VBoxContainer).add_child(hold)
		## 卡底还要放「购买」(货架上的那件)⇒ 面板走紧凑版, 四选一按钮才放得进封顶高度(axe_panel.gd 头上的高度账)
		var ah: float = _axe_panel.build(hold, 0.0, 0.0, AXE_IN_CARD_W, not own)
		hold.custom_minimum_size = Vector2(AXE_IN_CARD_W, ah)
	if own:
		## 宝箱里点的那一件: 卡底一颗「卖出 +N」(与货架卡底的「购买」同一个位置、同一种钮)。
		##   ★2026-10-21 原来是宝箱那一排末尾两颗「详情 / 卖出」—— 手机版宝箱一排 5 格铺满左栏, 没地方放;
		##     而且「先点格 → 再点详情 → 才看到说明」比货架多一步。现在两边一致: 点 = 弹说明卡, 卡底是动作。
		## ★2026-10-21 用户「商店里就不能卖装备」: 已有的那件只看说明, 卖出只在背包页。
		_refit_card.call_deferred()
		return
	_refit_card.call_deferred()


## 说明卡底的动作钮(购买 / 卖出): 木色直角, 高 81(= 44pt 触控下限), 字 22。
func _card_button_skin(b: Button) -> void:
	b.custom_minimum_size = Vector2(0, 81)
	b.add_theme_font_size_override("font_size", 22)
	UISkin.card_button(b)


## 卡里塞了按钮后高度要按内容重算(容器只会长不会缩), 等两帧排完版再收。
## ★不用 `await process_frame`: 场景在这两帧里被释放(离开商店 / 门禁拆场)时, await 会在已释放的实例上恢复
##   (`Resumed function after await, but class instance is gone`)。改成挂在树信号上的一次性回调 ——
##   实例没了, Godot 自动断开这条连接。
func _refit_card(frames: int = 2) -> void:
	if frames > 0:
		var cb := _refit_card.bind(frames - 1)
		if is_inside_tree() and not get_tree().process_frame.is_connected(cb):
			get_tree().process_frame.connect(cb, CONNECT_ONE_SHOT)
		return
	var c = _insp.card
	if c == null or not is_instance_valid(c):
		return
	## 卡比货柜里那块地方高 ⇒ 正文改成可拖动滚的一段, 再等一帧排完版重新定位
	if _cap_card_height(c as Control):
		_refit_card(1)
		return
	_snap_card_body()
	(c as Control).size = Vector2((c as Control).size.x, 0)
	(c as Control).position = inspect_card_pos(c, (c as Control).get_combined_minimum_size().y)
	## 购买 / 卖出钮: 币紧跟在数字后面(按钮自带的 icon 只能贴边)
	var b = c.find_child("BuyBtn", true, false)
	if b == null:
		b = c.find_child("SellBtn", true, false)
	if b is Button and not (b as Button).disabled and (b as Button).get_node_or_null("Coin") == null:
		var f: Font = (b as Button).get_theme_font("font")
		var tw: float = f.get_string_size((b as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x if f != null else 60.0
		var ci := TextureRect.new(); ci.name = "Coin"; ci.texture = COIN_TEX
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ci.size = Vector2(28, 28)
		ci.position = Vector2((b as Button).size.x * 0.5 + tw * 0.5 + 6.0, ((b as Button).size.y - 28.0) * 0.5)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(b as Button).add_child(ci)


## 说明卡的顶 / 最大高: 顶栏(87)之下, 底沿不过刷新 / 锁定 / 买经验那一排(ROW_BTN_Y - 6)。
## ★为什么要封顶(2026-10-22 交互排查, 探针实测 96 件): 原来卡多高画多高 —— 23 件超过这块地方,
##   最高的 084 卡高 733 > 整个设计框 720, 在 16:9 / 手机上卡底那颗「购买」整个在屏幕外, 买不了;
##   小木斧攒满待选时那张高 1224, 四选一按钮落在 y 1258, 永远点不到(最终进化做不了)。
##   超高的卡还会被横挪到按钮排左边, 盖住被点的那件和等级牌。
## ⇒ 超高时只让【正文】那段变成可拖动滚的(与背包羁绊弹框 / 图鉴详情同一种 ScrollContainer),
##   标题、属性、小木斧进度与四选一、「购买」钮都留在卡里看得见的地方。
const CARD_TOP := 96.0
const CARD_MAX_H := ROW_BTN_Y - 6.0 - CARD_TOP
const CARD_BODY_MIN_H := 60.0
const CARD_SCROLL_W := UISkin.SCROLL_W + 4.0     # 竖滚动条让出的宽(正文不压在滚动条下; 条宽跟皮走, 再留 4)


## 卡超高 ⇒ 把正文装进滚动框, 返回 true(调用方等一帧排版后再定位); 不超或已经装过 ⇒ false。
func _cap_card_height(c: Control) -> bool:
	var need: float = c.get_combined_minimum_size().y
	if need <= CARD_MAX_H + 0.5:
		return false
	var body = _insp.live.get("body")
	if not is_instance_valid(body) or not (body is RichTextLabel):
		return false
	var rt := body as RichTextLabel
	var vb := rt.get_parent()
	if vb == null or vb is ScrollContainer:
		return false
	var vis_h: float = maxf(CARD_BODY_MIN_H, rt.get_combined_minimum_size().y - (need - CARD_MAX_H))
	var sc := ScrollContainer.new()
	sc.name = "CardBodyScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.follow_focus = false
	## 滚动条换木框 / 黄铜皮(默认是 Godot 的灰色圆角细条, 与卡的像素木框不搭; 粗细不变)
	UISkin.scrollbar(sc)
	sc.custom_minimum_size = Vector2(rt.custom_minimum_size.x, vis_h)
	var at := rt.get_index()
	vb.remove_child(rt)
	vb.add_child(sc)
	vb.move_child(sc, at)
	rt.custom_minimum_size = Vector2(maxf(0.0, rt.custom_minimum_size.x - CARD_SCROLL_W), 0.0)
	rt.mouse_filter = Control.MOUSE_FILTER_PASS   # 手指拖动交给外面的 ScrollContainer
	sc.add_child(rt)
	return true


## 正文滚动框的可见高收到【整行】(2026-10-22)。
## ★由来: 封顶时可见高是按像素倒推的(卡正好顶到 CARD_MAX_H), 常常切在某一行中间 ⇒
##   框底露出下一行字的上半截, 像一道脏线(实拍: 小木斧四选一那张卡, 正文两行下面露着第 3 行的字头)。
## ★在封顶之后的下一帧做(正文已按滚动框里的宽重排完, 行偏移才准); 只收不放 ⇒ 卡不会因此变高。
func _snap_card_body() -> void:
	var body = _insp.live.get("body")
	if not is_instance_valid(body) or not (body is RichTextLabel):
		return
	var rt := body as RichTextLabel
	var sc := rt.get_parent() as ScrollContainer
	if sc == null:
		return
	var vis: float = sc.custom_minimum_size.y
	if float(rt.get_content_height()) <= vis + 0.5:
		return                      # 整段都看得见 ⇒ 没有被切的行
	var keep := 0.0
	for i in range(1, rt.get_line_count()):
		var top: float = rt.get_line_offset(i)
		if top > vis + 0.5:
			break
		keep = top                  # 第 i 行的顶还在框里 ⇒ 前 i 行完整
	if keep > 0.0 and keep < vis - 0.5:
		sc.custom_minimum_size.y = keep


## InspectCard 的定位回调: 货架上的贴在货架左边、与那件同高; 宝箱里的弹在宝箱那一排上方。
func inspect_card_pos(card: Control, h: float) -> Vector2:
	var w: float = card.size.x
	## ★2026-10-21 宽货柜: 货柜左边只剩店主那一根宽, 放不下 400 宽的卡 ⇒ 贴着被点的那一格弹:
	##   左两列弹在它右边, 其余弹在它左边(盖住别的货, 不盖被点的那件)。底沿不过 SAFE_BOTTOM。
	if _sel_own != "" or not _shelf_sel_valid():
		return Vector2(BOARD_X, CARD_TOP)   # 小木斧那张(没有选中货架): 货柜左段, 不压右下刷新 / 锁定 / 买经验
	var sp := _shelf_pos(maxi(0, _sel))
	var x: float = (sp.x + SLOT_W + 8.0) if (_sel % 5) <= 1 else (sp.x - w - 8.0)
	## 底沿不压刷新 / 锁定 / 买经验那一排(ROW_BTN_Y)
	var y: float = clampf(sp.y, CARD_TOP, maxf(CARD_TOP, ROW_BTN_Y - 6.0 - h))
	## 说明很长、卡高到顶住也会伸进按钮那一排 ⇒ 横向挪到按钮左边(verify_ios_ui「按钮被后画的面板盖住」)
	if y + h > ROW_BTN_Y - 6.0 and x + w > ROW_BTN_X - 8.0:
		x = maxf(LEFT_X, ROW_BTN_X - 8.0 - w)
	return Vector2(x, y)


## 详情卡要不要盖在阵容上: 选了货架卡 / 点了「详情」看已有那件 / 斧头四选一待选。
func _detail_wanted() -> bool:
	if _shelf_sel_valid():
		return true
	if _sel_own != "":
		return true
	return _axe_card_wanted() and not _axe_card_closed


## 选着的那格货架上真的有货(买走 / 换货之后那格可能是空的, 或换成了别的)。
func _shelf_sel_valid() -> bool:
	return _sel >= 0 and _sel < _offer.size() and _offer[_sel] != null


## 小木斧攒够、待选最终造物, 且此刻没选着别的 ⇒ 自动弹它自己那张。
## ★出货概率牌开着时不弹: 两者都在货柜左段、卡底压住概率牌(同一时刻只开一个)。
func _axe_card_wanted() -> bool:
	if _show_odds or _sel_own != "" or _shelf_sel_valid():
		return false
	return AxePanel.should_show(GameState) and AxeEvo.final_ready(
		int(GameState.axe_exp_bar), int(GameState.axe_stage), str(GameState.axe_final))






## 完整描述。★实测: 95 件装备的 effectDesc1 【全是纯文本】—— 无 HTML 标签、无方括号
## (龟技能才有 <span class="val-atk"> 那套)。所以不需要 html_to_bbcode(空转), 也不怕 BBCode 吃掉 [xxx]。
## 保留 bbcode_enabled 只为将来装备文案要上色时不用改结构。
func _rich_desc(edef: Dictionary, star: int = 1) -> String:
	## ★2026-08-20: 加一道 `render_consts` —— 文案里现在可能有 {C:类名.常量名}(直接引用代码常量,
	##   见 skill_text.gd)。不展开就会把 `{C:...}` 原样显示给玩家。
	##   ⚠ 上面那句"全是纯文本"从此不再成立, 别再据此省掉渲染。
	## ★★2026-10-01(两层渲染 P2): 换成 `_bb` 版 —— 与龟技能走同一条上色/内联图标管线。
	##   上面那句「保留 bbcode_enabled 只为将来装备文案要上色时不用改结构」兑现了, 结构确实没改。
	var raw := SkillText.equip_full_bb(edef, 20)   # ★走唯一取值口, 别再手抄 effectDesc1(手抄的副本必然落后)
	if raw == "":
		## ★★原句「(这件装备还没有效果描述)」是**开发者的空态**: 半角括号 + "还没有…描述"
		##   等于当面告诉玩家"我们没写"。而且实测 95 件的 `effectDesc1` 全都有
		##   ⇒ 这一支**打不到**, 它只是数据损坏时的兜底。
		##   ⇒ 换成一句不暴露内情的摊主话: 玩家读到也只当是这件东西玄乎, 不会读成 bug。
		return "[color=#5b7a92]暂无说明[/color]"
	# ★按星级高亮(用户 2026-07-29「上面的效果能按照描述规则渲染吗」)。
	#   装备描述里的 `1/1.2/1.5` 是【一/二/三星三档值】。商店卖 ★1, 原来三档同色平铺,
	#   玩家看不出哪个数才是自己买到的。highlight_star 把当前星那档高亮、另两档压暗。
	#   ★背包页(InventoryScene)一直在用这个函数, 商店漏了 —— 同一份文案两套渲染。
	return SkillText.highlight_star(raw, star)


func _on_buy(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	var edef: Dictionary = _deco(_offer[idx])
	var price := _price(edef)
	var _nm: String = str(edef.get("name", "这件"))
	## ★★三条不成交的路原来都是【裸 return】—— 玩家看到的是"点了没反应",
	##   而那与"游戏卡住了"在屏幕上长得一模一样(同 `_toast` 头注记的那次真机实测)。
	##   ⚠ 别以为"按钮已经 disabled 了所以走不到": 那是**另一处**的判断。
	##     按钮文案与这里各算一遍价钱, 两边一漂(或按钮被程序触发)这里就是唯一的出口 ——
	##     满级那颗买经验按钮的 else 分支就是为同一个理由补的。
	if int(GameState.meta_deepsea_coins) < price:
		_toast("深海币不足 · 「%s」需要 %d，还差 %d" % [_nm, price, price - int(GameState.meta_deepsea_coins)])
		return   # 买不起
	# ★私人池: 先扣张再扣钱 —— 扣不到张就整笔不成交(货架是异步持久化的, 极端情况下
	#   可能出现"货架上还挂着、池子已被别的路径抽空"; 那时宁可这一次点击无效, 也不能凭空造张)。
	var _eid: String = str(edef.get("id", ""))
	if not GameState.pool_take(_eid, 1):
		## ★这一条**不是**到不了的分支: 货架是异步持久化的, 同一件被别的路径抽空时
		##   摊上那张卡还挂着。玩家点下去钱没扣、货没来, 必须有人告诉他为什么。
		_toast("「%s」已失效 · 请刷新" % _nm)
		return
	GameState.meta_deepsea_coins -= price
	## ★096 小木斧(方案书未决点 ⑧, 用户 2026-08-31 亲自纠正过我): **只能拥有一把**。
	##   已经有了还买 ⇒ 这一次购买【整笔化成 +15 砍伐经验】, 不进背包。
	##   钱照扣 —— 这就是它的"用钱换经验"通路, 也是需求原话「购买该装备会使经验条+15」。
	##   ⚠ 第一把也 +15(需求没有"第一把不算"的例外), 差别只在进不进背包。
	## ★成交反馈要说的那句话在**合成发生之前**才算得出来 ——
	##   `auto_merge_all()` 跑完之后 ★1 已经被吃掉, 再问"这一买合到几星"永远是 0。
	var _will_star: int = _purchase_merge_star(_eid)
	var _axe_dup := false
	var _axe_from: int = int(GameState.axe_stage)
	var _axe_evolved := false
	if _eid == "p2eq_096":
		var _dup: bool = GameState.axe_owned()
		_axe_dup = _dup
		_axe_evolved = GameState.axe_add_exp(AxeEvo.EXP_ON_BUY, false)   # 进化了就在下面当场播, 不进待播队列
		if not _dup:
			GameState.persistent_bench.append({"id": _eid, "star": 1})
	else:
		GameState.persistent_bench.append({"id": _eid, "star": 1})
	GameState.auto_merge_all()   # 买后自动 3 合 1 (背包+龟身一起算)
	_offer[idx] = null
	## ★买走的那格不再算「选中」(2026-10-22 用户「买完一个东西，点了刷新后怎么自动选中一个物品？」):
	##   原来 `_sel` 还指着这个空格, 卡是因为格空了才没画; 一刷新这格长出新货 ⇒ 新货被自动选中、说明卡自己弹出来。
	##   小木斧待选那张也被这个残留的下标挡掉(_open_detail_card 读到空格就 return)。
	if _sel == idx:
		_sel = -1
	_shelf_tap_after_ms = Time.get_ticks_msec() + BUY_TAP_GUARD_MS
	_persist_offer()   # 买走的位子要留空, 不能退出重进又长回来
	GameState.save()
	_rebuild()
	## ★★成交也要有一句话(用户 2026-09-29 台账 ⑮:「买成功的唯一反馈是整屏重画」)。
	##   `_rebuild()` 之后才发 —— 它开头把所有子节点 queue_free, 先发就当场被清掉
	##   (背包页那 7 条 toast 全部看不见, 根因一模一样, 见 `_toast` 头注)。
	##   ★三种成交各有各的话: 合成到 ★N / 小木斧重复买(化成砍伐经验) / 普通进背包。
	##     合成那条最要紧 —— 卡片消失了而背包里【多出来的是另一件东西】, 不说就是"我的钱去哪了"。
	if _will_star >= 2:
		_toast("购买成功 · 「%s」合成 ★%d" % [_nm, _will_star])
		## 首次提示「3 件同名同星装备自动合成升星」, 圈左下宝箱里升星的那一格(教程中不出)。
		##   ★不圈顶栏「背包」: 那里提示条只能放进顶栏, 压住深海币读数(10-20 实拍)。宝箱放不下那一件(溢出)时才退回顶栏。
		FirstTips.show(self, FirstTips.FIRST_MERGE, merge_tip_target(_eid, _will_star))
	elif _axe_dup:
		_toast("已拥有「%s」· 转化为砍伐经验 +%d" % [_nm, int(AxeEvo.EXP_ON_BUY)])
	else:
		_toast("购买成功 · 「%s」已放入背包" % _nm)
	_tut_notify("item_bought")   # 教程「购买 1 件装备」: 成交才前进(方案书 B2)
	if _axe_evolved:
		## ★还没补放的(结算 / 战斗里攒出来的)排在前面一起播 —— 否则先在这里看到 2→3, 进背包才补 1→2, 顺序反了。
		play_axe_evo(GameState.axe_evo_take() + [{"from": _axe_from, "to": int(GameState.axe_stage)}])

## 小木斧进化演出(买到当场进化 / 四选一点下)。宿主 _rebuild 不会清掉它(AxeEvoShow.GROUP)。
func play_axe_evo(steps: Array) -> void:
	_axe_evo.play(steps)

## 合成升星那一件在左下宝箱里的格子(首次提示圈它; 门禁 verify_first_tips ⑦b 也读它)。没摆出来 ⇒ 顶栏「背包」。
func merge_tip_target(eid: String, star: int) -> Control:
	var bench: Array = GameState.persistent_bench
	for j in range(bench.size()):
		var it = bench[j]
		if it is Dictionary and str((it as Dictionary).get("id", "")) == eid and int((it as Dictionary).get("star", 1)) == star:
			var cell := find_child("BenchCell%d" % j, true, false) as Control
			if cell != null:
				return cell
	return _bag_tab()


## 顶栏「背包」那一签(首次提示 / 教程 E5 都指它)。★按字找, 不按下标: 左上现在是「商店 | 背包」一对页签,
##   action_btns[0] 是亮着的「商店」(教程里还是藏起来的那颗)。
func _bag_tab() -> Button:
	if _top_bar == null:
		return null
	for b in _top_bar.action_btns:
		if is_instance_valid(b) and b is Button and str((b as Button).text) == "背包":
			return b
	return null


## ── 货架锁(用户 2026-10-04 · 学云顶) ─────────────────────────────────
## 「换一批」右边一颗方钮, 图标复用 `icon-lock.png`(不新画: 背包页/对阵图同一张)。
## ★没有「开着的锁」那张图 ⇒ 两态靠**整颗按钮的亮暗 + 金边**区分:
##   未锁 = 图标压暗(半透) + 普通冷色皮 + 字「锁货」; 已锁 = 图标全亮 + 金色主按钮皮 + 字「已锁」。
## ★字是必须的: 只有一把锁的图标, 光看图标分不出"点了会锁"还是"现在锁着"。
const REFRESH_ICON := preload("res://assets/sprites/shop/icon-refresh.png")
const LOCK_CLOSED_ICON := preload("res://assets/sprites/shop/icon-lock-closed.png")
const LOCK_OPEN_ICON := preload("res://assets/sprites/shop/icon-lock-open.png")
const LOCK_GAP := 8.0
## 三颗钮同宽同高(128×100): 两边都 ≥ 81(44pt), 不再靠「长边 ≥ 200」的例外过线。
const LOCK_W := ROW_BTN_W
## ★2026-10-18 用户「你没发现下面是空的吗」: 货架下面那块沙地空着, 而顶栏挤着等级 / 经验 / 买经验。
##   参考云顶: 刷新、买经验、等级都在商店那一排 ⇒ 底部一排 = 刷新 · 锁定 · 买经验, 上面一行是等级 + 经验条 + 装备数。
## ★2026-10-21 手机版: 这一排挪进货柜底座(下层板沿 574 以下、SAFE_BOTTOM 682 以上),
##   左段 = 等级 · 经验条(点它看出货概率), 右段 = 刷新 · 锁定 · 买经验; 「装备 N/M」挪到宝箱标题那一行。
## ★2026-10-21 宽货柜: 这一排在下层板沿(595)以下、SAFE_BOTTOM 以上, 高 84(≥ 81 = 44pt)。
const ROW_X := BOARD_X + 4.0                         # 等级段左沿 279(左立柱内沿)
const ROW_BTN_W := 180.0                             # 木牌按钮(「买经验 4」+ 币要放得下, 币不压牌边)
const ROW_BTN_H := 82.0                              # ≥ 81(44pt 触控下限)
const ROW_BTN_Y := SAFE_BOTTOM - ROW_BTN_H - 2.0     # 598
const ROW_BTN_X := 1262.0 - 3.0 * ROW_BTN_W - 2.0 * LOCK_GAP   # 870
const ROW_INFO_Y := ROW_BTN_Y + 8.0                 # 等级那一行(36 高)竖直居中在按钮那一排
const XP_ICON := preload("res://assets/sprites/shop/icon-xp.png")
var _lock_btn: Button = null

func _build_lock_button(pos: Vector2, h: float) -> void:
	var locked: bool = bool(GameState.meta_shop_locked)
	## 锁着: 合上的锁 + 金色「已锁定」; 没锁: 开着的锁 + 普通字 —— 靠图案和字分两态。
	var lb := _icon_button("ShopLockBtn", LOCK_CLOSED_ICON if locked else LOCK_OPEN_ICON,
		"已锁定" if locked else "锁定", pos, Vector2(LOCK_W, h))
	lb.tooltip_text = "已锁定 · 点击解锁" if locked else "锁定商品：下场战斗后不刷新"
	## 两态靠图案区分(开着的锁 / 合上的锁), 不压暗 —— 压暗看着像点不了
	lb.add_theme_color_override("font_color", Color("#ffe27a") if locked else Color("#e8dcc4"))
	lb.pressed.connect(_on_toggle_lock)
	add_child(lb)
	_lock_btn = lb


## 买经验(无框图标钮, 与刷新 / 锁定同一种) + 上面一行: 等级 · 经验条 · 装备数。
func _build_level_row(btn_pos: Vector2) -> void:
	var _need: int = maxi(1, P2.xp_to_next(int(GameState.season_level)))
	var _have: int = int(GameState.season_xp)
	## ★★满级不印哨兵分母(xp_to_next 满级返回 999999 = 「升不了」, 印出来读成「还差好多」)
	var _maxed: bool = int(GameState.season_level) >= P2.MAX_LEVEL
	## 点等级行 = 看各费用出货概率(参考云顶: 概率挂在等级旁, 不常驻在货架上)
	## ★热区 = 整段(380×100); 等级 / 经验条 / 经验字都是它的子节点 —— 字是这块热区上的字, 不是压在别的靶子上
	##   (verify_shop_inv_phone ⑤ 2026-10-21: 原来三者是热区的兄弟节点, 量出来就是「字压在热区上」)。
	var lvhit := Control.new(); lvhit.name = "LevelTap"
	var o := Vector2(ROW_X - 4.0, ROW_BTN_Y)
	lvhit.position = o; lvhit.size = Vector2(ROW_BTN_X - ROW_X - 8.0, ROW_BTN_H)
	lvhit.mouse_filter = Control.MOUSE_FILTER_STOP
	lvhit.tooltip_text = "各费用出货概率"
	_wire_tap(lvhit, func():
		_show_odds = not _show_odds
		## 概率牌与说明卡同时只开一个: 原来选着货时点等级, 概率牌弹在说明卡底下、被卡盖住左半截(2026-10-22 交互排查)
		if _show_odds:
			_sel = -1; _sel_own = ""; _sel_bench = -1
		_rebuild())
	add_child(lvhit)
	## 2026-10-21 用户「底下的经验条」: 等级 / 经验 / 可装备 装进一块木牌(与三颗按钮同一张), 不再是散在底座上的小字
	var lvplq := _plank(lvhit, Vector2.ZERO, lvhit.size); lvplq.name = "LevelPlaque"
	var lv := Label.new(); lv.name = "LevelLabel"; lv.text = "Lv%d" % int(GameState.season_level)
	lv.add_theme_font_size_override("font_size", 28); lv.add_theme_color_override("font_color", Color("#ffd93d"))
	lv.add_theme_color_override("font_outline_color", Color("#1a0e05")); lv.add_theme_constant_override("outline_size", 6)
	lv.position = Vector2(ROW_X + 14.0, ROW_INFO_Y) - o; lv.size = Vector2(70, 36)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lvhit.add_child(lv)
	if _show_odds:
		_build_odds_row()
	var bar_x := ROW_X + 92.0
	var bar_w := 180.0
	_wood_bar(lvhit, Vector2(bar_x, ROW_INFO_Y + 6.0) - o, Vector2(bar_w, 24), 1.0 if _maxed else (float(_have) / float(_need)))
	var xpn := Label.new(); xpn.name = "XpLabel"
	xpn.text = "已满级" if _maxed else ("经验 %d/%d" % [_have, _need])
	xpn.add_theme_font_size_override("font_size", MIN_FONT_PX); xpn.add_theme_color_override("font_color", Color("#fff4dc"))
	xpn.add_theme_color_override("font_outline_color", Color("#1a0e05")); xpn.add_theme_constant_override("outline_size", 6)
	xpn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 字放在条的右边, 不压在槽框的金属边带上(verify_ui_consistency「文字压边带」)
	xpn.position = Vector2(bar_x + bar_w + 8.0, ROW_INFO_Y) - o; xpn.size = Vector2(ROW_BTN_X - (bar_x + bar_w + 8.0) - 6.0, 36)
	xpn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xpn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lvhit.add_child(xpn)
	## 等级的用处写在等级旁边: 全队可装备件数 = (等级 − 1) × 2(P2.team_equip_cap) —— 1 级是 0 件。
	var capn := Label.new(); capn.name = "EquipCapLabel"
	var _cap_now: int = int(P2.team_equip_cap(int(GameState.season_level)))
	capn.text = "可装备 %d 件" % _cap_now
	if not _maxed:
		capn.text += "  ·  Lv%d 可装备 %d 件" % [int(GameState.season_level) + 1, int(P2.team_equip_cap(int(GameState.season_level) + 1))]
	capn.add_theme_font_size_override("font_size", MIN_FONT_PX)
	capn.add_theme_color_override("font_color", Color("#ffb454") if _cap_now == 0 else Color("#e8dcc4"))
	capn.add_theme_color_override("font_outline_color", Color("#1a0e05")); capn.add_theme_constant_override("outline_size", 6)
	capn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capn.position = Vector2(ROW_X + 14.0, ROW_INFO_Y + 34.0) - o; capn.size = Vector2(ROW_BTN_X - ROW_X - 36.0, 32)
	capn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lvhit.add_child(capn)
	## 「装备 N/M」(全队已装 / 上限)挪到左栏宝箱标题那一行(ShopChest.build_bench) —— 它说的是装备, 跟宝箱放一起。

	var bxp := _icon_button("ShopBuyXpBtn", XP_ICON, "等级已满" if _maxed else ("买经验 %d" % int(P2.BUY_XP_COST)),
		btn_pos, Vector2(ROW_BTN_W, ROW_BTN_H))
	if not _maxed:
		_coin_after_text(bxp)
	## ★满级: 点不动 + 整颗压暗(价钱那枚币是子节点, 只有 modulate 往下传) + 被程序按下也要说一句
	## ★买不起也一样压暗(2026-10-22 交互排查): 原来只有满级才暗, 钱不够时它亮着、旁边的「刷新」却暗着 ——
	##   同一排两颗按钮对「买不起」两种长相。
	var _xp_dead: bool = _maxed or int(GameState.meta_deepsea_coins) < int(P2.BUY_XP_COST)
	bxp.disabled = _xp_dead
	bxp.modulate = Color(1, 1, 1, 0.42) if _xp_dead else Color(1, 1, 1, 1)
	bxp.tooltip_text = "经验 +%d" % int(P2.BUY_XP_AMOUNT)
	bxp.pressed.connect(_on_buy_xp)
	## disabled 的按钮不发 pressed ⇒ 真点到压暗的它, 原来一句话都没有(满级 / 钱不够那两句只有程序直调才到得了)
	if _xp_dead:
		_wire_tap(bxp, _on_buy_xp)
	## 教程: 「买经验」教到才出现(云顶教程 04:30 才出 Buy XP; 方案书 20261021-教程分镜v5 E1→E2)。
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active() and not _tut_xp_revealed:
		bxp.visible = false
	add_child(bxp)
	_tut_xp_btn = bxp


func _on_buy_xp() -> void:
	var _lv0: int = int(GameState.season_level)
	if GameState.buy_season_xp():
		_rebuild()
		if int(GameState.season_level) > _lv0:
			_tut_notify("level_up")   # 教程「购买经验，升到 2 级」
	elif int(GameState.season_level) >= int(P2.MAX_LEVEL):
		_toast("已达最高等级 Lv%d" % int(P2.MAX_LEVEL))
	else:
		_toast("深海币不足（需要 %d）" % int(P2.BUY_XP_COST))


## 教程导引每进一步就告诉宿主当前高亮的是谁(TutorialGuide 调)。到「买经验」那一步才把按钮放出来。
var _tut_xp_revealed := false
func tut_step_shown(highlight: String) -> void:
	if highlight == "xp_button" and not _tut_xp_revealed:
		_tut_xp_revealed = true
		if _tut_xp_btn != null and is_instance_valid(_tut_xp_btn):
			_tut_xp_btn.visible = true


## 经验条: 木槽 + 暖黄填充(不再借战斗 HUD 的蓝边血条槽)。不透明底 = 不是网页盒。
const XP_BAR_PAD := 3.0
func _wood_bar(parent: Control, pos: Vector2, sz: Vector2, ratio: float) -> void:
	## 2026-10-21 像素经验条: 1 像素 = 3 设计像素(与木牌同倍率) —— 黑描边 / 深槽 / 金色填充 + 顶亮行 + 底暗行, 槽里每 1/4 一道刻度。
	var u := XP_BAR_PAD
	var slot := Panel.new(); slot.name = "XpBarSlot"
	var ssb := StyleBoxFlat.new(); ssb.bg_color = Color("#000000"); ssb.set_corner_radius_all(0)
	slot.add_theme_stylebox_override("panel", ssb)
	slot.position = pos; slot.size = sz; slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	## 槽底与刻度用 Panel(不是 ColorRect): 门禁按 ColorRect 数填充量比例, 槽里的块不能被当成填充
	var inner := Panel.new()
	var isb := StyleBoxFlat.new(); isb.bg_color = Color("#232b2e"); isb.set_corner_radius_all(0)
	inner.add_theme_stylebox_override("panel", isb)
	inner.position = Vector2(u, u); inner.size = sz - Vector2(2.0 * u, 2.0 * u); inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(inner)
	var tsb := StyleBoxFlat.new(); tsb.bg_color = Color("#101623"); tsb.set_corner_radius_all(0)
	for q in [0.25, 0.5, 0.75]:
		var tick := Panel.new(); tick.add_theme_stylebox_override("panel", tsb)
		tick.position = Vector2(roundf(inner.size.x * q / u) * u, 0.0); tick.size = Vector2(u, inner.size.y)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE; inner.add_child(tick)
	var w: float = floorf(inner.size.x * clampf(ratio, 0.0, 1.0) / u) * u
	if w >= u:
		var fl := ColorRect.new(); fl.color = Color("#ffb145")
		fl.position = pos + Vector2(u, u); fl.size = Vector2(w, inner.size.y)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(fl)
		var hl := ColorRect.new(); hl.color = Color("#fdfff2")
		hl.position = fl.position; hl.size = Vector2(w, u)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(hl)
		var sh := ColorRect.new(); sh.color = Color("#b36f43")
		sh.position = fl.position + Vector2(0.0, fl.size.y - u); sh.size = Vector2(w, u)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(sh)

## 无框图标钮: 图标在上(像素图 ×2, 最近邻)、描边字在下; 五种状态的底都是空的(不是金木框, 也不是网页盒)。
func _icon_button(nm: String, tex: Texture2D, label: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new(); b.name = nm
	b.text = label
	b.icon = tex
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 40)
	b.add_theme_constant_override("h_separation", 8)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color("#e8dcc4"))
	b.add_theme_color_override("font_hover_color", Color("#fff4dc"))
	b.add_theme_color_override("font_pressed_color", Color("#ffe27a"))
	b.add_theme_color_override("font_outline_color", Color("#1a0e05"))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("icon_hover_color", Color(1.15, 1.15, 1.15, 1))
	b.add_theme_color_override("icon_pressed_color", Color(0.85, 0.85, 0.85, 1))
	## 2026-10-21 用户「3个按钮？」: 原来是三颗无底小圆图标 + 下面一行小字, 看不出能按。⇒ 每颗一块像素木牌(PLANK_TEX), 图标在左、字在右。
	for st in [["normal", 1.0], ["hover", 1.15], ["pressed", 0.8], ["disabled", 1.0], ["focus", 1.0]]:
		var tb := StyleBoxTexture.new()
		tb.texture = PLANK_TEX; tb.set_texture_margin_all(PLANK_MARGIN)
		tb.content_margin_left = 12; tb.content_margin_right = 12
		tb.modulate_color = Color(float(st[1]), float(st[1]), float(st[1]), 1.0)
		b.add_theme_stylebox_override(str(st[0]), tb)
	b.position = pos; b.size = sz
	return b


## 像素木牌底(九宫格, 与按钮同一张 PLANK_TEX)。
const PLANK_TEX = preload("res://assets/sprites/shop/shop-plank.png")
const PLANK_MARGIN := 18
const COIN_PLAQUE_X := 1040.0
func _plank(parent: Control, pos: Vector2, sz: Vector2) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = PLANK_TEX
	np.patch_margin_left = PLANK_MARGIN; np.patch_margin_right = PLANK_MARGIN
	np.patch_margin_top = PLANK_MARGIN; np.patch_margin_bottom = PLANK_MARGIN
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.position = pos; np.size = sz
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(np)
	return np


## 刷新钮字后面跟一枚深海币(子节点, 跟着按钮一起压暗)。
func _coin_after_text(b: Button) -> void:
	var c := TextureRect.new(); c.texture = COIN_TEX
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## 量字宽再放: 「刷新  2」居中, 币紧贴在字的右边(写死偏移会压在数字上 —— 实拍过)
	var f: Font = b.get_theme_font("font")
	var tw: float = f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, b.get_theme_font_size("font_size")).x if f != null else 60.0
	## 木牌按钮: 图标在左(12 + 40 + 8), 字左对齐 ⇒ 币紧跟字尾、竖直居中
	c.position = Vector2(12.0 + 40.0 + 8.0 + tw + 4.0, (b.size.y - 26.0) * 0.5); c.size = Vector2(26, 26)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)


func _on_toggle_lock() -> void:
	GameState.meta_shop_locked = not bool(GameState.meta_shop_locked)
	## 锁的那一刻把戳对齐当前场次(货架就是本场次的货; 防一份旧戳在解锁后被当成"该换了")
	GameState.meta_shop_battles = int(GameState.season_total_battles)
	GameState.save()
	_rebuild()   # ★先重建再提示 —— _rebuild 会清掉全部子节点(提示也在其中)
	_toast("已锁定 · 下场战斗后不刷新" if GameState.meta_shop_locked else "已解锁 · 下场战斗后刷新")


func _on_refresh() -> void:
	if int(GameState.meta_deepsea_coins) < REFRESH_COST:
		## ★同 `_on_buy`: 原来是裸 return。而「换一批」那颗按钮**一直是亮的**
		##   (实测 coins=0 时 `disabled=false`) ⇒ 玩家点得下去、什么也不发生。
		##   这是满级买经验那颗死按钮的同一个形状: 死按钮要长得像死的 + 点了要说为什么。
		_toast("深海币不足（需要 %d）" % REFRESH_COST)
		return
	GameState.meta_deepsea_coins -= REFRESH_COST
	## ★锁着也能换一批, 而且**换完自动解锁** —— 照云顶(tft.ninja「The Shop」: 锁住的商店
	##   一直锁到你手动解锁、**或者你刷新**为止; 刷新会顺带解锁)。理由: 锁的是「这批货」,
	##   你亲手把这批货换掉了, 锁就没有对象了。方案书 §⑤ 未决点 U5-1 记着, 用户要反过来改这一行。
	GameState.meta_shop_locked = false
	_roll()
	## ★换了一批货, 原来选着的那件已经不在了 ⇒ 不选任何一件(原来下标留着, 新货架同一格的货被自动选中)。
	_sel = -1
	GameState.save()
	_rebuild()


## 顶栏「背包」: 非教程直接换屏; 教程里先报「点击背包」这一步, 再走导演推进到背包站。
func _go_inventory() -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null and td.is_active():
		td.notify("shop_to_bag")
		SceneNav.go(get_tree(), td.next_scene_after("shop"))
		return
	SceneNav.go(get_tree(), "res://scenes/Inventory.tscn")


const TUT_SKIP_W := 132.0

## ★竖直跟顶栏(币那一排)走, 不跟设计框: 4:3(iPad)上顶栏贴视口顶(_pin_top_bar), 设计框却下移 120,
##   按框算会落在货柜顶梁上(2026-10-21 三比例自查)。
func _tutorial_skip_slot() -> Rect2:
	var p := Vector2(W - 28.0 - TUT_SKIP_W, 48.0 - 28.0) + _frame_off()
	if _coin_box != null and is_instance_valid(_coin_box):
		p.y = _coin_box.global_position.y + 48.0 - 28.0
	return Rect2(p, Vector2(TUT_SKIP_W, 56.0))


func _tut_notify(ev: String) -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null:
		td.notify(ev)


## 设计框(UIFrame)的屏幕偏移 —— 本屏内容按 1280×720 设计坐标画, 宽屏上整体居中平移。
func _frame_off() -> Vector2:
	for c in get_children():
		if c is UIFrame and not (c as Node).is_queued_for_deletion():
			return (c as Control).global_position
	return Vector2.ZERO


## 新手引导高亮锚点。名字→屏幕矩形; 解析不到返回空 Rect2(本步不显示)。
func _tutorial_anchor(anchor: String) -> Rect2:
	match anchor:
		"coins":   # 深海币显示
			if _tut_coin != null and is_instance_valid(_tut_coin):
				return _tut_coin.get_global_rect()
		"xp_button":
			return TutorialGuide.vis_rect(_tut_xp_btn)
		"buy_button":   # 教程 v3「点击购买」: 说明卡里的「购买」钮(买得起才有)
			return TutorialGuide.vis_rect(_tut_buy_btn)
		"detail_card":  # 教程 v3「点击购买」的高亮: 整张说明卡(买之前要看得清买的是什么; 实拍 10-20 只挖「购买」时说明被压暗)
			if _insp.card != null and is_instance_valid(_insp.card):
				return TutorialGuide.vis_rect(_insp.card)
		"offer_card":   # 教程 v3「点击一件装备」的手势指针: 第一张买得起的卡
			for i in range(_offer.size()):
				if _offer[i] != null and _price(_deco(_offer[i])) <= int(GameState.meta_deepsea_coins):
					return Rect2(_shelf_pos(i) + _frame_off(), Vector2(SLOT_W, SLOT_H))
		"shelf":        # 货架 5×2(不含说明卡: 这一步只点卡)
			var gr := Rect2(GRID_X, GRID_Y, 5.0 * SLOT_W + 4.0 * GRID_GAP_X, 2.0 * SLOT_H + GRID_GAP_Y)
			return Rect2(gr.position + _frame_off(), gr.size)
		"offer":   # 货架 5×2 + 说明小卡(v2 那一步用的; v3 拆成 shelf / buy_button 两步后只剩 verify_tutorial 的版面声称还读它)
			var grid := Rect2(GRID_X, GRID_Y, 5.0 * SLOT_W + 4.0 * GRID_GAP_X, 2.0 * SLOT_H + GRID_GAP_Y)
			var u := Rect2(grid.position + _frame_off(), grid.size)
			if _insp.card != null and is_instance_valid(_insp.card):
				u = u.merge(TutorialGuide.vis_rect(_insp.card))
			return u
		"level_row":    # 教程 v5 E1「1 级不能装备」: 等级 · 经验 · 可装备 N 件 那一段
			var lt := find_child("LevelTap", true, false) as Control
			if lt != null:
				return TutorialGuide.vis_rect(lt)
		"bag_button":
			return TutorialGuide.vis_rect(_bag_tab())
	return Rect2()


## 深海币小图标。★复用 COIN_TEX(主菜单同一张), 不再用 emoji 💠。
## ══ 深海币入账动画(2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 F) ══
## 打完一场点结算屏「前往商店」直接来这里(用户 10-26「玩家会尽量去看商店的」)⇒ 这一场的深海币在商店钱包里飞进来:
##   钱包先显示旧值, 屏幕中央亮出「+N」和币堆, 币飞进右上角钱包、数字一步步跳(scripts/util/coin_fly.gd, 与主菜单同一个)。
## ★只管显示, 钱早在结算时入账; 动画期间买东西会整页重建(`_rebuild`), 新钱包直接显示真值, 动画随旧节点一起没了。
var _wallet_icon: TextureRect = null
const WALLET_DELAY_SEC := 0.35

func _wallet_gain() -> void:
	var real: int = int(GameState.meta_deepsea_coins)
	var gain: int = CoinFly.gain_since_seen(real)
	if gain <= 0 or _tut_coin == null or not is_instance_valid(_tut_coin):
		return
	_tut_coin.text = str(maxi(0, real - gain))
	var t := Timer.new()          # 挂在自己身上(不是树级计时器): 商店先没了它跟着没
	t.one_shot = true
	t.wait_time = WALLET_DELAY_SEC
	add_child(t)
	t.start()
	await t.timeout
	t.queue_free()
	if _tut_coin == null or not is_instance_valid(_tut_coin) or not _tut_coin.is_inside_tree():
		return
	CoinFly.play(self, get_viewport_rect().size / 2.0, _tut_coin, _wallet_icon, maxi(0, real - gain), gain)


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




## 一条【像素槽】进度条: 九宫格金属槽 + 槽内填充。取代「两个 ColorRect 摞一起」。
##
## ★本屏两条进度条(头部等级经验 / 小木斧砍伐经验)走**同一个函数** ——
##   `axe_panel.gd` 的注释本来就写着「同一个界面里两条进度条不该长得不一样」,
##   而那时是各写一份纯色矩形。手抄的副本必然落后, 所以这里只留一处实现。
## ★填充画在槽内(按九宫格边距内缩), 不是画在框上 —— 否则填充会骑在金属边带上。
## ★`ratio` 由调用方钳到 0~1; 0 时填充宽为 0(不画), 满时正好齐槽右沿。
func _pixel_bar(parent: Control, pos: Vector2, sz: Vector2, ratio: float, fill: Color) -> void:
	## ★★槽【先】加、填充【后】加 —— 顺序反了填充就永远看不见。
	##   `bar-frame.png` 是**实心**贴图(整张不透明: 黑槽是画出来的, 不是镂空),
	##   我第一版按"框压住填充两端"的直觉把框画在后面, 实拍 14/36 的经验条**一格都不涨**
	##   (截图里那条槽全黑)。空心框(card-frame 那种)能后画, 实心的不能 ——
	##   ⇒ 判断依据是**贴图中间透不透**, 不是"框该不该压着内容"。
	var _slot := _nine_xy(parent, BAR_TEX, BAR_MARGIN_X, BAR_MARGIN_Y, pos, sz, 0)
	_slot.name = "XpBarSlot"
	var slot_x := float(BAR_MARGIN_X)
	var slot_y := float(BAR_MARGIN_Y)
	var inner := Vector2(maxf(1.0, sz.x - slot_x * 2.0), maxf(1.0, sz.y - slot_y * 2.0))
	var fl := ColorRect.new()
	fl.color = fill
	fl.position = pos + Vector2(slot_x, slot_y)
	fl.size = Vector2(inner.x * clampf(ratio, 0.0, 1.0), inner.y)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fl)


# ════════════════════════════════════════════════════════════════════════
#  皮肤: 卡框 / 面板框 —— 【本项目新生成】的像素框 (assets/sprites/shop/)
#
#  ★用户 2026-07-28「别复用，自己画或生产」「只有背包或商店的图标可以复用」——
#    所以这些是 PixelLab 新生成的, 没有从 menu/ 搬现成的 frame-*.png。
#    (深海币 ic-deepsea.png 是用户点名允许复用的那个例外。)
#  ★★2026-09-29 这条**只管卡框/面板框了**: 按钮那两张已经退场(见下)。
#    这两条不冲突 —— 那条铁律说的是「不许拿别的内容的素材顶替新内容」,
#    而按钮不是"商店的新内容", 它是**全游戏同一种控件**; 同一种控件长两副样子
#    正是用户 2026-09-29 说的「不好看的按钮」。⇒ 卡框保持自产, 按钮归共享层。
#
#  ★margin 是【量出来的】不是猜的: 见工具输出
#      card-frame 117x117 边框 L13 R14 T16 B13 → 17
#      panel-frame 191x246 边框 L23 R22 T24 B24 → 25
#    九宫格 margin 大于控件一半会把中间压没。
# ════════════════════════════════════════════════════════════════════════
## ★★说明卡里的按钮(购买 / 小木斧四选一)走 `UISkin.card_button`(深棕底 + 黄铜细边、直角)——
##   用户 2026-10-22「为什么还在用这个木头按钮？我说了无数遍啊」, 原来的木牌皮 `_skin_button` 已删。
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
const CARD_MARGIN := 8       # 量的: 新框 72×72, 边框 7px
## 合成指示星(像素·12 帧闪光循环)。★只在「已有 2 件、再买 1 件就合成」时出现 ——
## 装备本身就有 ★1/★2/★3 星级, 画一颗星会被读成"这是 ★1 装备", 而每张货架卡都是 ★1 = 零信息。
const STAR_TEX = preload("res://assets/sprites/shop/star-glint.png")
const STAR_FRAMES := 12
const STAR_FRAME_W := 32


## 横竖边距不同的九宫格。条框这类**扁贴图**必须分开给: bar-frame 的左右边带 11px、
## 上下只有 6px —— 一律用 11 会把 16px 高的条压成负中段(框根本画不出来)。
func _nine_xy(parent: Control, tex: Texture2D, mx: int, my: int, pos: Vector2, sz: Vector2, z := -1) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = mx
	np.patch_margin_right = mx
	np.patch_margin_top = my
	np.patch_margin_bottom = my
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
	var tw := TweenKit.loop_on(tr)
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
	if EquipPool.NO_STAR.has(eid):
		return 0          # 【不升星】的件: 卡上不预告"这一买会合成到几星"(用户2026-08-31 小木斧)
	# 下标 = 星级; [1] 已含这次购买的那一件
	var n := [0, _owned_count(eid, 1) + 1, _owned_count(eid, 2), _owned_count(eid, 3)]
	var top := 0
	for st in [1, 2]:
		if n[st] >= 3:
			n[st] -= 3
			n[st + 1] += 1
			top = st + 1
	return top


# §左半 —— 2026-10-18 起是店主 + 宝箱(背包), 见 scripts/scenes/shop/shop_chest.gd。装备在背包页做。
#   原来那两颗只读弹层按钮(备战席 / 出战阵容)已删: 弹层只能看不能装, 装还得换页。
