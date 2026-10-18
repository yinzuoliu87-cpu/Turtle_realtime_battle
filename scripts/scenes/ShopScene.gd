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
## ★2026-10-18 整页重做: 货架 = 背景图(shop-bg.png)右侧两层木板, 下列数值是量那张图得来的
##   (原生 384×216 ×3.333: 上层板面 y 74→247, 下层 128→427, 左右 216..373 → 720..1243)。
const SLOT_W := 104.0        # 一格商品的宽(5 格 = 520 = 板长)
const SLOT_H := 142.0        # 一格商品的高: 物品立在板上, 价签挂在板沿
const GRID_X := 722.0        # 货架左沿
const GRID_Y := 128.0        # 上层商品格的顶(底 270 = 板沿)
const GRID_GAP_X := 0.0
const GRID_GAP_Y := 38.0       # 下层格顶 308, 底 450 = 下层板沿
## 小卡里小木斧进度块的宽度(= 小卡宽 360 - 左右内边距)
const AXE_IN_CARD_W := 330.0
## 羁绊总览条(货架与底部按钮之间那条空带)。★进 verify_shop_layout 的越界检查
const SYN_BAR_Y := 100.0
const SYN_X := 40.0          # 羁绊条左沿 = 场地左沿
const SYN_CHIP_W := 176.0
## 羁绊 chip 的字号 / 行高 / 行内类型图标边长。
## ★★2026-09-28 换 `RichTextLabel` + 行内像素图标后**逐项量过**(探针 `f.get_string_size`):
##   · 最长的普通 chip「🏺遗物 2/5 ★☆☆☆」= 文字 111 + 图标 16 = **127** ⇒ 176 够, 宽不用动。
##   · 但**行高不够**: 14px 字的行高是 **22**, 而原来 chip 高写死 20 ——
##     `Label` 只横向 `clip_text` 所以看不出来, 换 `RichTextLabel` + `clip_contents`
##     之后就是**底下 2px 被切掉**。⇒ 高度 20 → 22。
##   · 斧头那条(带砍伐进度)= 252 ⇒ 仍需双倍宽 352(那条双倍宽原来从没生效, 见下方注释)。
## ★图标 16 而不是 14/18: 源图 32×32 硬边像素画, 只有 16(1:2) 与 32(1×) 落在像素网格上。
const SYN_CHIP_FONT_PX := 14
const SYN_CHIP_H := 22.0
const SYN_CHIP_ICON_PX := 16
const MIN_TOUCH_H := 44.0    # 移动端触摸目标最低高度(用户2026-07-28「买经验按钮很小」: 原36不达标)
const REFRESH_COST := 2   # 刷新花费。原 phase2_config 那套(SHOP_REFRESH_BASE + shop_refresh_cost())已随死代码清理删除, 现在这里是唯一来源(2026-07-19)
const SHOP_BG = preload("res://assets/sprites/shop/shop-bg.png")
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
var _toast_node: Label = null   # 一句话提示(见 _toast); 同时只留一条
var _insp := InspectCard.new(self)   # 说明小卡(与局内信息面板同一张)
var _ui_layer: Node = null           # InspectCard 往这里挂卡(= 本场景)
var _show_odds := false         # 点「Lv」切换: 等级行上方显示各费用出货概率

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
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
	})
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


func _price(edef: Dictionary) -> int:
	return maxi(1, int(edef.get("cost", 1))) * PRICE_MULT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

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
func _toast(msg: String) -> void:
	if _toast_node != null and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#ffe9a8"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(650, 44)
	## ★★y 430 → 656(2026-09-30): 430..474 **正好盖住「换一批」按钮的上沿**
	##   (按钮 y 448..524) —— 而现在最常出现的提示之一就是"深海币不够 · 换一批要 2",
	##   等于一句话挡住它解释的那颗按钮。656..700 落在底栏两颗按钮(552..648)之下、
	##   720 设计框之内, 是本屏唯一一条谁都不压的横带(门禁 BUY_FEEDBACK 会穷举核这一条)。
	##   ⚠ 弹层(z=20)仍被它压住 —— 那是故意的, 见下面 z_index 那行。
	## ★★2026-10-18: 底栏换成背包条(552..657), 右侧阵容面板常驻(x 800 起) ⇒
	##   提示收进卡区宽度 40..780、背包条之下 664..708, 不压背包格也不压面板。
	## ★2026-10-18 整页重做: 提示在左上(羁绊条下面、店主头顶), 不压店主、宝箱和货架。
	t.position = Vector2(40.0, 136.0)
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
		if c.is_in_group("tut_overlay"):
			continue   # ★教学浮层(引导/下一站按钮)不能随重建销毁 —— 买装备会触发 _rebuild
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
	## 点空白处 = 收起说明 / 取消选中(没有「×」)
	bgc.mouse_filter = Control.MOUSE_FILTER_STOP
	_wire_tap(bgc, func():
		if _sel >= 0 or _sel_own != "" or _sel_bench >= 0:
			_sel = -1; _sel_own = ""; _sel_bench = -1
			_rebuild())
	var bg := TextureRect.new(); bg.name = "ShopBackdrop"
	bg.texture = SHOP_BG
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.position = Vector2.ZERO; bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	## 宽屏(手机 19.5:9)两侧不留黑边: 背景本体不动(货架/台面坐标是量这张图对齐的),
	##   两侧多出来的宽度 = 图边上同宽的一段【镜像翻过来】接上(拉伸边缘像素会成一道道花条纹)。
	var _vs: Vector2 = get_viewport().get_visible_rect().size
	var _side: float = maxf(0.0, (_vs.x * H / maxf(1.0, _vs.y) - W) * 0.5)
	## 这段宽度在原图里是几列。★不取整、不多留: 多出来的会伸出视口(verify_ui_layout「不溢出视口」@1560×720 溢出 7px)
	var _nat: float = _side * float(SHOP_BG.get_width()) / W
	for _sd in ([0, 1] if _side >= 1.0 else []):   # 16:9 不加(否则伸出 1280 设计框)
		var at := AtlasTexture.new(); at.atlas = SHOP_BG
		at.region = Rect2(0.0 if _sd == 0 else SHOP_BG.get_width() - _nat, 0, _nat, SHOP_BG.get_height())
		var ext := TextureRect.new(); ext.name = "BackdropEdge%d" % _sd
		ext.flip_h = true
		ext.texture = at; ext.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ext.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ext.stretch_mode = TextureRect.STRETCH_SCALE
		ext.position = Vector2(-_nat * W / SHOP_BG.get_width() if _sd == 0 else W, 0.0)
		ext.size = Vector2(_nat * W / SHOP_BG.get_width(), H)
		ext.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ext)

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
		"palette": TopBar.WOOD,   # 2026-10-18 整页重做: 场景是木头货铺, 顶栏跟着木色
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
		"left_actions": [["🎒 背包", _go_inventory, {"tutorial_keep": true}]],
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
	_coin_icon(self, Vector2(320, HDR_CY - 26.0), 52.0)
	var coin := Label.new(); coin.text = "%d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 38); coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	## ★高度按【字体最小高度】给(30 号字实测 44), 不是我想给多少给多少 ——
	##   给 38 的话 Label 自己撑到 44, 并集矩形底沿多出 6px, 组中心偏到 50.5 ⇒ 门禁⑩红。
	coin.position = Vector2(382, HDR_CY - 28.0); coin.size = Vector2(138, 56)
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(coin)
	_tut_coin = coin   # 教学高亮"币"锚点


	# ── 卡区 5×2  x 40–780 / y 124–420 ──
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
	var rf := _icon_button("ShopRefreshBtn", REFRESH_ICON, "刷新  %d" % REFRESH_COST,
		Vector2(ROW_X, ROW_BTN_Y), Vector2(ROW_BTN_W, ROW_BTN_H))
	_coin_after_text(rf)
	## ★★买不起时: disabled + 整颗压暗(价钱那枚币是子节点, 只有 modulate 会往下传)。
	var _rf_afford: bool = int(GameState.meta_deepsea_coins) >= REFRESH_COST
	rf.disabled = not _rf_afford
	rf.modulate = Color(1, 1, 1, 1) if _rf_afford else Color(1, 1, 1, 0.42)
	rf.pressed.connect(_on_refresh); add_child(rf)
	_build_lock_button(rf.position + Vector2(rf.size.x + LOCK_GAP, 0.0), rf.size.y)
	_build_level_row(rf.position + Vector2(2.0 * (rf.size.x + LOCK_GAP), 0.0))

	_build_synergy_bar()    # ★羁绊总览: 当前激活了哪些 + 距下一档还差几件(2026-08-12 用户点名)
	## ★右侧: 常驻【出战阵容】; 选中货架卡 / 已有装备时, 详情盖在它上面(带关闭)。
	##   底部: 原来两颗只读弹层按钮 → 可点的背包条(点一件 → 点龟 = 装上)。
	_chest.build_keeper(self)
	_chest.build_bench(self)
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

## ★#2 出货概率行(云顶式): 当前大轮等级下各费用档(1-5)的出货概率%. 每费用色=对应稀有度色, 0%淡显.
func _build_odds_row() -> void:
	var odds: Array = P2.shop_cost_odds(_shop_level())   # [费1% .. 费5%]
	var cost_cols := ["#9aa0b0", "#4ade80", "#60a5fa", "#c084fc", "#fbbf24"]   # 费1-5: 普通灰/精良绿/稀有蓝/史诗紫/传说金
	## ★2026-10-18: 不再常驻在货架上(浮在横梁上看不清, 4/5 费几乎看不见); 点「Lv」时弹在等级行上方。
	var row := HBoxContainer.new(); row.name = "OddsRow"
	row.position = Vector2(ROW_X, ROW_INFO_Y - 40.0); row.size = Vector2(514, 30)
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
	lbl.add_theme_font_size_override("font_size", 16); lbl.add_theme_color_override("font_color", Color("#e8dcc4"))
	row.add_child(lbl)
	for c in range(5):
		var pct: int = int(odds[c]) if c < odds.size() else 0
		var chip := Label.new()
		## ★数字与汉字之间要有空格 —— json 侧的文案门禁焊了这条, UI 侧一直没人管,
		##   于是同一个游戏里「1 费」和「费用1」两种写法并存。跟 json 的口径。
		chip.text = "%d 费 %d%%" % [c + 1, pct]
		chip.add_theme_font_size_override("font_size", 16)
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
		var sg := ShopChest.ellipse(SLOT_W - 8.0, 96.0, 26, 22, Color(1.0, 0.86, 0.35, 0.45)); sg.name = "SelGlow"
		sg.position = Vector2(4, 22); box.add_child(sg)
	## 已拥有同款: 身后一团呼吸的淡金光(原卡片镀层的同一个意思, 换成不带框的光)
	var owned := _owned_count(str(edef.get("id", "")))
	if owned > 0:
		## 用户 2026-08-14「背包里有的装备在货架栏出现时要有镀层闪光效果」: 身后一团呼吸淡金光 + 一道斜掠高光。
		var glow := ShopChest.ellipse(SLOT_W - 20.0, 84.0, 24, 20, Color(1.0, 0.84, 0.35, 0.30)); glow.name = "OwnedGlow"
		glow.position = Vector2(10, 22); box.add_child(glow)
		var bt := TweenKit.loop_bound(self, glow)
		bt.tween_property(glow, "modulate:a", 0.12, 0.9).set_trans(Tween.TRANS_SINE)
		bt.tween_property(glow, "modulate:a", 0.30, 0.9).set_trans(Tween.TRANS_SINE)
		var shine_box := Control.new(); shine_box.name = "OwnedShine"
		shine_box.position = Vector2(8, 10); shine_box.size = Vector2(SLOT_W - 16, SLOT_H - 36)
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
	var ic := EquipIcon.make(edef, Vector2(76, 70))
	ic.name = "Item"
	ic.position = Vector2((SLOT_W - 76.0) * 0.5, SLOT_H - 22.0 - 70.0 - 4.0)
	box.add_child(ic)
	## 这一买会合成到几星
	var will_star := _purchase_merge_star(str(edef.get("id", "")))
	if will_star >= 2:
		for k in range(will_star):
			_glint_star(box, Vector2(SLOT_W - 18.0 - k * 14.0, 8), 13.0, k * 0.3)
	## 价签: 挂在板沿的小木牌。框 = 费用 5 档那套框(CARD_TEX_TIER, 用户 2026-07-29「框框随费用变化」);
	##   选中换金框 CARD_TEX_SEL; 买不起换中性框 CARD_TEX_N + 斜纹(三态各有各的形状)。
	var _c: int = clampi(int(edef.get("cost", 1)), 1, 5)
	var tag := Panel.new(); tag.name = "PriceTag"
	var tsb := StyleBoxFlat.new(); tsb.bg_color = Color("#2e1c10"); tsb.set_corner_radius_all(0)
	tag.add_theme_stylebox_override("panel", tsb)
	tag.position = Vector2((SLOT_W - 66.0) * 0.5, SLOT_H - 34.0); tag.size = Vector2(66, 34)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(tag)
	_nine(tag, CARD_TEX_SEL if sel else (CARD_TEX_TIER[_c - 1] if afford else CARD_TEX_N), CARD_MARGIN,
		Vector2.ZERO, tag.size, 0)
	var ci := TextureRect.new(); ci.texture = COIN_TEX
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.position = Vector2(11, 9); ci.size = Vector2(16, 16); ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(ci)
	var pr := Label.new(); pr.name = "Price"; pr.text = "%d" % price
	pr.add_theme_font_size_override("font_size", 15)
	pr.add_theme_color_override("font_color", Color("#ffe9a8") if afford else Color("#ff6b6b"))
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.position = Vector2(27, 8); pr.size = Vector2(28, 18); pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(pr)
	if not afford:
		_hatch(tag)
	if not afford:
		ic.modulate = Color(0.45, 0.48, 0.55)
	for ch in box.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = str(edef.get("name", ""))
	_wire_tap(box, func(): _on_select(idx))
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


## 买不起时盖在卡上的【斜纹】。三态里唯一一个"内容齐全却不能买"的状态, 要有自己的形状。
##
## ★做法: 一个 `clip_contents` 的空 Control 当剪刀, 里头几根旋转过的细长条 ——
##   出框的部分被剪掉, 于是斜纹严丝合缝地卡在卡片轮廓里(不用为每种卡尺寸画一张贴图)。
## ★角度 -0.5 rad 与已有的"镀层掠光"(`shine`)同一个倾角 —— 同一张卡上两种斜向元素
##   不该各斜各的。
## ★`z_index = 1` 与档位框同层: 压住图标/名字/价签(它们 z=0), 但不盖住 z=2 的合成指示星
##   —— 那两颗星讲的是"再买一件就合成", 买不起的时候反而最需要看见。
func _hatch(box: Control) -> void:
	var clip := _clip_box(box)
	clip.z_index = 1
	for i in range(4):
		var bar := ColorRect.new()
		bar.color = Color(0.04, 0.07, 0.11, 0.55)
		bar.size = Vector2(3.0, maxf(box.size.y, 24.0) * 2.2)
		bar.rotation = -0.5
		bar.position = Vector2(-26.0 + float(i) * box.size.x * 0.36, -24.0)   # 跟着被盖的那块宽度铺(现在盖的是价签)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(bar)


## 点卡 → 选中(两步购买第一步)。再点同一张 = 取消选中。
func _on_select(idx: int) -> void:
	if idx < 0 or idx >= _offer.size() or _offer[idx] == null:
		return
	_sel = -1 if _sel == idx else idx
	_sel_own = ""          # 与"已拥有"选中互斥 —— 同一块面板同时只讲一件事
	_sel_bench = -1        # 看货架就不再选着宝箱里那件
	_rebuild()


## 说明小卡。货架上的 = 卡底一颗「购买」; 宝箱里的 = 只看(卖出在宝箱格旁)。
func _open_detail_card() -> void:
	_ui_layer = self
	## 什么都没选、但小木斧攒够了待选最终造物 ⇒ 直接弹小木斧自己那张(这一步错过就做不了最终进化)
	var axe_only: bool = _sel < 0 and _sel_own == ""
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
	var lv: Dictionary = _insp.open(("own:" if own else "shop:") + eid, null, {
		"icon": ("res://assets/sprites/" + img) if img.ends_with(".png") else "",
		"title": str(edef.get("name", eid)), "title_col": col,
		"icon_border": col, "frame_col": col,
		"tag_bb": tag_bb, "tag_col": Color("#e8dcc4"),
		"stats": stats,
		"body": _rich_desc(edef, star), "body_px": 16,
		"width": 360.0,
	})
	if not lv.has("vbox"):
		return
	## 小木斧: 砍伐进度条 + (攒够时)最终造物四选一, 接在说明下面
	if AxePanel.should_show(GameState) and (eid == AxePanel.EID or AxeEvo.final_ready(
			int(GameState.axe_exp_bar), int(GameState.axe_stage), str(GameState.axe_final))):
		var hold := Control.new(); hold.name = "AxeProgress"
		(lv["vbox"] as VBoxContainer).add_child(hold)
		var ah: float = _axe_panel.build(hold, 0.0, 0.0, AXE_IN_CARD_W)
		hold.custom_minimum_size = Vector2(AXE_IN_CARD_W, ah)
	if own:
		_refit_card.call_deferred()
		return
	var price := _price(edef)
	var coins := int(GameState.meta_deepsea_coins)
	var buy := Button.new(); buy.name = "BuyBtn"
	buy.custom_minimum_size = Vector2(0, 52)
	buy.add_theme_font_size_override("font_size", 20)
	for st in [["normal", "#6a3f1c", "#d89a48"], ["hover", "#7d4b22", "#f0b45a"], ["pressed", "#4e2d12", "#d89a48"],
			["disabled", "#3a2a1e", "#6a5440"], ["focus", "#6a3f1c", "#ffe27a"]]:
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(st[1]); sb.border_color = Color(st[2])
		sb.set_border_width_all(3); sb.set_corner_radius_all(0)
		buy.add_theme_stylebox_override(st[0], sb)
	buy.add_theme_color_override("font_color", Color("#fff1d6"))
	buy.add_theme_color_override("font_hover_color", Color("#fff8e8"))
	buy.add_theme_color_override("font_disabled_color", Color("#c9a98a"))
	if coins >= price:
		buy.text = "购买  %d" % price
		buy.pressed.connect(func(): _on_buy(_sel))
		_tut_buy_btn = buy
	else:
		buy.text = "还差 %d 枚深海币" % (price - coins)
		buy.disabled = true
	(lv["vbox"] as VBoxContainer).add_child(buy)
	_refit_card.call_deferred()


## 卡里塞了按钮后高度要按内容重算(容器只会长不会缩), 等两帧排完版再收。
func _refit_card() -> void:
	for _i in range(2):
		await get_tree().process_frame
	var c = _insp.card
	if c == null or not is_instance_valid(c):
		return
	(c as Control).size = Vector2((c as Control).size.x, 0)
	(c as Control).position = inspect_card_pos(c, (c as Control).get_combined_minimum_size().y)
	## 购买钮: 币紧跟在数字后面(按钮自带的 icon 只能贴边)
	var b = c.find_child("BuyBtn", true, false)
	if b is Button and not (b as Button).disabled and (b as Button).get_node_or_null("Coin") == null:
		var f: Font = (b as Button).get_theme_font("font")
		var tw: float = f.get_string_size((b as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x if f != null else 60.0
		var ci := TextureRect.new(); ci.name = "Coin"; ci.texture = COIN_TEX
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ci.size = Vector2(26, 26)
		ci.position = Vector2((b as Button).size.x * 0.5 + tw * 0.5 + 6.0, ((b as Button).size.y - 26.0) * 0.5)
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(b as Button).add_child(ci)


## InspectCard 的定位回调: 货架上的贴在货架左边、与那件同高; 宝箱里的弹在宝箱那一排上方。
func inspect_card_pos(card: Control, h: float) -> Vector2:
	var w: float = card.size.x
	if _sel_own != "" or _sel < 0:
		return Vector2(clampf(40.0, 8.0, W - w - 8.0), clampf(ShopChest.BENCH_Y - h - 12.0, 8.0, H - h - 8.0))
	var sp := _shelf_pos(maxi(0, _sel))
	return Vector2(GRID_X - w - 14.0, clampf(sp.y - 10.0, 96.0, H - h - 8.0))


## 详情卡要不要盖在阵容上: 选了货架卡 / 点了「详情」看已有那件 / 斧头四选一待选。
func _detail_wanted() -> bool:
	if _sel >= 0 and _sel < _offer.size() and _offer[_sel] != null:
		return true
	if _sel_own != "":
		return true
	return AxePanel.should_show(GameState) and AxeEvo.final_ready(
		int(GameState.axe_exp_bar), int(GameState.axe_stage), str(GameState.axe_final))


func _on_select_own(eid: String, star: int) -> void:
	if _sel_own == eid and _sel_own_star == star:
		_sel_own = ""                       # 再点一次 = 取消
	else:
		_sel_own = eid
		_sel_own_star = star
		_sel = -1                           # 与货架格选中互斥
	_rebuild()


## 羁绊总览条(货架下方): 当前激活的每一系 + 距下一档还差几件。
## ★口径与战斗/背包完全一致: 只数【装在身上】的、按 id 去重(GameState.team_p2_equips_for_synergy)。
##   ⚠ 不数背包 —— "买到 ≠ 装上"(2026-08-12 圣光护盾白送 bug 的同一条教训)。
## 用户 2026-08-12:「商店里应该显示目前背包里激活的羁绊和下一个档位需求数量」。
func _build_synergy_bar() -> void:
	## ★算法住在 GameState.synergy_rows() —— 出战页 chips 用的是同一份(2026-08-12)。
	##   去重口径 / "差几件" / 排序三样都在那里, 两处显示才不会漂。
	var rows: Array = GameState.synergy_rows()

	var y: float = SYN_BAR_Y
	## ★2026-10-18: 没有羁绊时整条不画(原来是一条暗条 + 一句操作说明横在水上);
	##   有羁绊时只画标签, 描边字直接压在场景上, 不垫暗条。
	if rows.is_empty():
		return
	var hdr := Label.new()
	hdr.text = "羁绊"
	hdr.add_theme_font_size_override("font_size", 15)
	hdr.add_theme_color_override("font_color", Color("#ffe3a3"))
	hdr.add_theme_color_override("font_outline_color", Color("#1a0e05")); hdr.add_theme_constant_override("outline_size", 5)
	hdr.position = Vector2(SYN_X, y); hdr.size = Vector2(44, 20)
	add_child(hdr)
	var x: float = SYN_X + 46.0
	for r in rows:
		if x > SYN_X + 700.0:
			break
		## ★★2026-09-28 类型图标从 emoji 换成 `tags/` 像素图 ⇒ 这一条必须从 `Label`
		##   换成 `RichTextLabel`: **Label 画不了行内图**。
		##   写法走 `Phase2Types.icon_bb()`(内部就是 `[img=16x16]`, 与图鉴副标同一份)。
		## ★`clip_text` 是 Label 的属性, RTL 侧对应的是 `clip_contents` + 关掉滚动/换行:
		##   三个缺一个, 长条子(斧头那条)就会换行顶破 20px 的行高或长出滚动条。
		var chip := RichTextLabel.new()
		chip.bbcode_enabled = true
		chip.fit_content = false
		chip.scroll_active = false
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.clip_contents = true
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 32→16 不许线性插值糊掉硬边
		var _wide: bool = false                                   # 斧头那条要双倍宽(见下)
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
			chip.text = "%s%s %d/%d %s" % [Phase2Types.icon_bb(str(r["t"]), SYN_CHIP_ICON_PX),
				str(r["t"]), n_now, n_now + need, stars]
		else:
			chip.text = "%s%s %d %s" % [Phase2Types.icon_bb(str(r["t"]), SYN_CHIP_ICON_PX),
				str(r["t"]), n_now, stars]
		## ★★斧头羁绊的 chip 上【直接带砍伐进度】(用户 2026-09-01:
		##   「应该是在羁绊里显示最好啊，这是跟着羁绊走的」)。
		##   砍伐经验确实是跟着这条羁绊走的东西 —— 它不该藏在某件装备的详情面板里,
		##   要在主页面一眼看到。四选一按钮太大放不进这一行, 仍在详情面板。
		if str(r["t"]) == "斧头" and AxePanel.should_show(GameState):
			var _d4: Dictionary = AxeEvo.display(int(GameState.axe_stage), str(GameState.axe_final))
			var _nd: int = AxeEvo.need_for_next(int(GameState.axe_stage))
			var _rd: bool = AxeEvo.final_ready(int(GameState.axe_exp_bar),
				int(GameState.axe_stage), str(GameState.axe_final))
			## ★尾巴那句原来是「  可进化!」—— 去掉感叹号。门禁⑫ 焊死的正是
			##   "不许有带感叹号的推销话术"那一类; 它说的是事实, 但语气是广告位。
			chip.text += "  ·  %s %d/%d%s" % [str(_d4["name"]), int(GameState.axe_exp_bar),
				_nd, "  可进化" if _rd else ""]
			## ⚠ 2026-09-28 顺手修掉一处**双倍宽从来没生效过**: 原来这里写
			##   `chip.size = Vector2(SYN_CHIP_W * 2.0, 20)`, 而下面还有一行**无条件**的
			##   `chip.size = Vector2(SYN_CHIP_W, 20)` —— 后者在后面, 直接把它盖掉,
			##   于是斧头这条长条子一直被 `clip_text` 截在 176px。改成用标记, 由末尾统一定宽。
			## ⚠⚠ 同时挪掉原来这里的 `x += SYN_CHIP_W`: 它在 `chip.position` **之前**,
			##   效果是把斧头这条**整体右推 176px**(前面留一个 176 的洞), 而它自己只有
			##   176 宽时刚好不撞上下一条。宽度真的变成 352 之后, 那个推法就会让它
			##   **压住下一条 170px**。改成「原位摆 + 按真实宽度进位」——
			##   合计步进一个字没变(旧: 176 前推 + 182 后进 = 358 / 新: 352 + 6 = 358)。
			_wide = true
		## ★RichTextLabel 的主题键名与 Label **不同**: `normal_font_size` / `default_color`
		##   (照抄 Label 的 `font_size` / `font_color` 会静默无效 —— 不报错, 只是字号颜色不变)。
		chip.add_theme_font_size_override("normal_font_size", SYN_CHIP_FONT_PX)
		chip.add_theme_color_override("default_color",
			Color("#ffd93d") if tier > 0 else Color("#7a92a8"))
		chip.position = Vector2(x, y + 1)
		var _cw: float = SYN_CHIP_W * (2.0 if _wide else 1.0)
		chip.size = Vector2(_cw, SYN_CHIP_H)
		add_child(chip)
		x += _cw + 6.0


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
	if _eid == "p2eq_096":
		var _dup: bool = GameState.axe_owned()
		_axe_dup = _dup
		GameState.axe_add_exp(AxeEvo.EXP_ON_BUY)
		if not _dup:
			GameState.persistent_bench.append({"id": _eid, "star": 1})
	else:
		GameState.persistent_bench.append({"id": _eid, "star": 1})
	GameState.auto_merge_all()   # 买后自动 3 合 1 (背包+龟身一起算)
	_offer[idx] = null
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
	elif _axe_dup:
		_toast("已拥有「%s」· 转化为砍伐经验 +%d" % [_nm, int(AxeEvo.EXP_ON_BUY)])
	else:
		_toast("购买成功 · 「%s」已放入背包" % _nm)
	_tut_notify("item_bought")   # 教程「购买 1 件装备」: 成交才前进(方案书 B2)

## ── 货架锁(用户 2026-10-04 · 学云顶) ─────────────────────────────────
## 「换一批」右边一颗方钮, 图标复用 `icon-lock.png`(不新画: 背包页/对阵图同一张)。
## ★没有「开着的锁」那张图 ⇒ 两态靠**整颗按钮的亮暗 + 金边**区分:
##   未锁 = 图标压暗(半透) + 普通冷色皮 + 字「锁货」; 已锁 = 图标全亮 + 金色主按钮皮 + 字「已锁」。
## ★字是必须的: 只有一把锁的图标, 光看图标分不出"点了会锁"还是"现在锁着"。
const REFRESH_ICON := preload("res://assets/sprites/shop/icon-refresh.png")
const LOCK_CLOSED_ICON := preload("res://assets/sprites/shop/icon-lock-closed.png")
const LOCK_OPEN_ICON := preload("res://assets/sprites/shop/icon-lock-open.png")
const LOCK_GAP := 12.0
## ★宽 200 不是随手定的: verify_ui_consistency 的「热区不足」判据是 短边 < 81px(44pt) **且** 长边 < 200px。
##   高度要跟「换一批」(76)对齐一行, 只能靠长边 ≥ 200 过线(「换一批」240×76 也是这么过的)。
const LOCK_W := 130.0
## ★2026-10-18 用户「你没发现下面是空的吗」: 货架下面那块沙地空着, 而顶栏挤着等级 / 经验 / 买经验。
##   参考云顶: 刷新、买经验、等级都在商店那一排 ⇒ 底部一排 = 刷新 · 锁定 · 买经验, 上面一行是等级 + 经验条 + 装备数。
const ROW_X := 736.0
const ROW_BTN_Y := 604.0
const ROW_BTN_W := 130.0
const ROW_BTN_H := 96.0
const ROW_INFO_Y := 556.0
const XP_ICON := preload("res://assets/sprites/shop/icon-xp.png")
const DETAIL_ICON := preload("res://assets/sprites/shop/icon-detail.png")
const SELL_ICON := preload("res://assets/sprites/shop/icon-sell.png")
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
	var lv := Label.new(); lv.name = "LevelLabel"; lv.text = "Lv%d" % int(GameState.season_level)
	lv.add_theme_font_size_override("font_size", 26); lv.add_theme_color_override("font_color", Color("#ffd93d"))
	lv.add_theme_color_override("font_outline_color", Color("#1a0e05")); lv.add_theme_constant_override("outline_size", 6)
	lv.position = Vector2(ROW_X, ROW_INFO_Y); lv.size = Vector2(62, 34)
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(lv)
	## 点等级行 = 看各费用出货概率(参考云顶: 概率挂在等级旁, 不常驻在货架上)
	var lvhit := Control.new(); lvhit.name = "LevelTap"
	lvhit.position = Vector2(ROW_X, ROW_INFO_Y - 4.0); lvhit.size = Vector2(300, 42)
	lvhit.mouse_filter = Control.MOUSE_FILTER_STOP
	lvhit.tooltip_text = "各费用出货概率"
	_wire_tap(lvhit, func():
		_show_odds = not _show_odds
		_rebuild())
	add_child(lvhit)
	if _show_odds:
		_build_odds_row()
	var bar_x := ROW_X + 66.0
	var bar_w := 170.0
	_wood_bar(Vector2(bar_x, ROW_INFO_Y + 8.0), Vector2(bar_w, 18), 1.0 if _maxed else (float(_have) / float(_need)))
	var xpn := Label.new(); xpn.name = "XpLabel"
	xpn.text = "已满级" if _maxed else ("经验 %d/%d" % [_have, _need])
	xpn.add_theme_font_size_override("font_size", 16); xpn.add_theme_color_override("font_color", Color("#fff4dc"))
	xpn.add_theme_color_override("font_outline_color", Color("#1a0e05")); xpn.add_theme_constant_override("outline_size", 5)
	## 字放在条的右边, 不压在槽框的金属边带上(verify_ui_consistency「文字压边带」)
	xpn.position = Vector2(bar_x + bar_w + 8.0, ROW_INFO_Y + 4.0); xpn.size = Vector2(110, 26)
	xpn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xpn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(xpn)
	var used: int = int(GameState.team_equipped_count())
	var cap: int = int(GameState.team_equip_cap())
	var cnt := Label.new(); cnt.name = "TeamEquipCount"
	cnt.text = "装备 %d/%d" % [used, cap]
	cnt.add_theme_font_size_override("font_size", 18)
	cnt.add_theme_color_override("font_color", Color("#ffb454") if used >= cap else Color("#ffe3a3"))
	cnt.add_theme_color_override("font_outline_color", Color("#1a0e05")); cnt.add_theme_constant_override("outline_size", 6)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(bar_x + bar_w + 120.0, ROW_INFO_Y); cnt.size = Vector2(1250.0 - (bar_x + bar_w + 120.0), 34)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; add_child(cnt)

	var bxp := _icon_button("ShopBuyXpBtn", XP_ICON, "等级已满" if _maxed else ("买经验  %d" % int(P2.BUY_XP_COST)),
		btn_pos, Vector2(ROW_BTN_W, ROW_BTN_H))
	if not _maxed:
		_coin_after_text(bxp)
	## ★满级: 点不动 + 整颗压暗(价钱那枚币是子节点, 只有 modulate 往下传) + 被程序按下也要说一句
	bxp.disabled = _maxed
	bxp.modulate = Color(1, 1, 1, 0.42) if _maxed else Color(1, 1, 1, 1)
	bxp.tooltip_text = "经验 +%d" % int(P2.BUY_XP_AMOUNT)
	bxp.pressed.connect(func():
		var _lv0: int = int(GameState.season_level)
		if GameState.buy_season_xp():
			_rebuild()
			if int(GameState.season_level) > _lv0:
				_tut_notify("level_up")   # 教程「购买经验，升到 2 级」
		elif int(GameState.season_level) >= int(P2.MAX_LEVEL):
			_toast("已达最高等级 Lv%d" % int(P2.MAX_LEVEL))
		else:
			_toast("深海币不足（需要 %d）" % int(P2.BUY_XP_COST)))
	add_child(bxp)
	_tut_xp_btn = bxp


## 经验条: 木槽 + 暖黄填充(不再借战斗 HUD 的蓝边血条槽)。不透明底 = 不是网页盒。
const XP_BAR_PAD := 3.0
func _wood_bar(pos: Vector2, sz: Vector2, ratio: float) -> void:
	var slot := Panel.new(); slot.name = "XpBarSlot"
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#22130a"); sb.border_color = Color("#8a5a32")
	sb.set_border_width_all(int(XP_BAR_PAD)); sb.set_corner_radius_all(0)
	slot.add_theme_stylebox_override("panel", sb)
	slot.position = pos; slot.size = sz; slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	var w: float = (sz.x - 2.0 * XP_BAR_PAD) * clampf(ratio, 0.0, 1.0)
	if w >= 1.0:
		var fl := ColorRect.new(); fl.color = Color("#f2b44a")
		fl.position = pos + Vector2(XP_BAR_PAD, XP_BAR_PAD); fl.size = Vector2(w, sz.y - 2.0 * XP_BAR_PAD)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(fl)
		var hl := ColorRect.new(); hl.color = Color("#ffe39a")
		hl.position = fl.position; hl.size = Vector2(w, 2)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(hl)


## 无框图标钮: 图标在上(像素图 ×2, 最近邻)、描边字在下; 五种状态的底都是空的(不是金木框, 也不是网页盒)。
func _icon_button(nm: String, tex: Texture2D, label: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new(); b.name = nm
	b.text = label
	b.icon = tex
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 64)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color("#e8dcc4"))
	b.add_theme_color_override("font_hover_color", Color("#fff4dc"))
	b.add_theme_color_override("font_pressed_color", Color("#ffe27a"))
	b.add_theme_color_override("font_outline_color", Color("#1a0e05"))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("icon_hover_color", Color(1.15, 1.15, 1.15, 1))
	b.add_theme_color_override("icon_pressed_color", Color(0.85, 0.85, 0.85, 1))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.position = pos; b.size = sz
	return b


## 刷新钮字后面跟一枚深海币(子节点, 跟着按钮一起压暗)。
func _coin_after_text(b: Button) -> void:
	var c := TextureRect.new(); c.texture = COIN_TEX
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## 量字宽再放: 「刷新  2」居中, 币紧贴在字的右边(写死偏移会压在数字上 —— 实拍过)
	var f: Font = b.get_theme_font("font")
	var tw: float = f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, b.get_theme_font_size("font_size")).x if f != null else 60.0
	c.position = Vector2(b.size.x * 0.5 + tw * 0.5 + 2.0, b.size.y - 32.0); c.size = Vector2(24, 24)
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
	GameState.save()
	_rebuild()


## 顶栏「背包」: 非教程直接换屏; 教程里先报「点击背包」这一步, 再走导演推进到背包站。
func _go_inventory() -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null and td.is_active():
		td.notify("shop_to_bag")
		get_tree().change_scene_to_file(td.next_scene_after("shop"))
		return
	get_tree().change_scene_to_file("res://scenes/Inventory.tscn")


const TUT_SKIP_W := 132.0

func _tutorial_skip_slot() -> Rect2:
	return Rect2(Vector2(W - 28.0 - TUT_SKIP_W, 48.0 - 28.0) + _frame_off(), Vector2(TUT_SKIP_W, 56.0))


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
		"offer_pick":   # 手势指针: 已选中且买得起 ⇒ 指「购买」; 否则指第一张买得起的卡
			var br := TutorialGuide.vis_rect(_tut_buy_btn)
			if br.size.x > 0.0:
				return br
			for i in range(_offer.size()):
				if _offer[i] != null and _price(_deco(_offer[i])) <= int(GameState.meta_deepsea_coins):
					var cp := _shelf_pos(i)
					return Rect2(cp + _frame_off(), Vector2(SLOT_W, SLOT_H))
		"offer":   # 货架 5×2 + 说明小卡(「购买」在小卡里, 两步购买都得在洞里; 没选中时没有小卡)
			var grid := Rect2(GRID_X, GRID_Y, 5.0 * SLOT_W + 4.0 * GRID_GAP_X, 2.0 * SLOT_H + GRID_GAP_Y)
			var u := Rect2(grid.position + _frame_off(), grid.size)
			if _insp.card != null and is_instance_valid(_insp.card):
				u = u.merge(TutorialGuide.vis_rect(_insp.card))
			return u
		"bag_button":
			if _top_bar != null and not _top_bar.action_btns.is_empty():
				return TutorialGuide.vis_rect(_top_bar.action_btns[0])
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
## ★★2026-09-29 **按钮皮已全部交给共享层 `UISkin.button`** —— 见下方 `_skin_button`。
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
## 中性档框(不带费用色)。★库里一直有这张、一直没人引用 —— 2026-09-28 起它管两件事:
##   ① **空货位**的框(买走之后那一格原来是块裸矩形)
##   ② **已拥有**那圈金边(原来是 2px 纯色描边 + 圆角 = 网页盒)
##   两处都是"框的形状要在、但不该讲费用档"的场合, 正好是它。
##   ⇒ 先搜库再动手: 不为这两件事新生成贴图(assets/sprites/shop/ 已有 9 张框)。
const CARD_TEX_N = preload("res://assets/sprites/shop/card-frame-n.png")
const CARD_MARGIN := 8       # 量的: 新框 72×72, 边框 7px
## 合成指示星(像素·12 帧闪光循环)。★只在「已有 2 件、再买 1 件就合成」时出现 ——
## 装备本身就有 ★1/★2/★3 星级, 画一颗星会被读成"这是 ★1 装备", 而每张货架卡都是 ★1 = 零信息。
const STAR_TEX = preload("res://assets/sprites/shop/star-glint.png")
const STAR_FRAMES := 12
const STAR_FRAME_W := 32


## 给按钮上皮 —— **一律走共享层 `UISkin.button`**, 商店不再有自己的一套。
##
## ★由来(用户 2026-09-29:「不好看的按钮」)。原来这里自己建 `StyleBoxTexture`,
##   贴 `assets/sprites/shop/btn-frame.png`(128×64) + `shop/buy-btn.png`, margin 18。
##   **那张图 64 行里 36 行是边框, 中段只剩 28 行** —— 套到实测 76~96 高的按钮上
##   中段被拉 2.7~3.4 倍, 金属质感全被拉平, 实拍(改前图)就是**一圈青色细描边的方块**。
##   这与 2026-08-19 给返回键换框时量到的是**同一条**毛病(`ui_skin.gd:112`:
##   「小签牌拉 2.5~3.4 倍 ⇒ 看起来就是一块灰板」)。
## ★★为什么不是"再画一张商店专用的大框": 全项目 10 个屏(背包/图鉴/主菜单/排行榜/
##   设置/对阵表/战斗面板/羁绊面板/糖罐/选龟)都走 `UISkin.button`, **商店是唯一的例外** ——
##   例外本身就是用户看到的那个毛病。共享层已经按**控件真实尺寸**挑框
##   (短边 ≥56 且面积 ≥5000 → `menu/frame-rect.png` margin 27; 否则 `chip-frame.png` margin 7),
##   判据是「边带×2 装不装得进这个控件」而不是「哪张更华丽」(ui_skin.gd:117 那段是量出来的)。
##   ⚠ 顺带记下**量过但用不了**的那张: `menu/btn-frame.png`(893×212) 端花左右各 101px、
##   上下边带实测 85/41 —— 上下加起来 126, 而商店最高的按钮才 96。**装不进去, 不是不想用。**
## ★主次改用 `tint` 表达, 不再靠第二张贴图: 「买下」是全页最主要的动作 ⇒ 暖金;
##   其余冷蓝。(原来那张 `buy-btn.png` 金框正是"屏幕专用的一次性皮"。)
## ⚠ 调用方必须**先设好 `size` 再调** —— `UISkin.button` 按真实尺寸挑框, size 还是 0 会挑错。
func _skin_button(b: Button, primary := false) -> void:
	UISkin.button(b, Color("#f0c27a") if primary else Color("#b9c8d8"))
	## 字色留在商店侧(它是本屏的配色, 不是皮): 主按钮暖白, 其余冷白。
	b.add_theme_color_override("font_color", Color("#fff1d6") if primary else Color("#dff2ff"))
	b.add_theme_color_override("font_hover_color", Color("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color("#e7c68a") if primary else Color("#9fd8ea"))
	b.add_theme_color_override("font_disabled_color", Color("#6b7f8e"))


## 九宫格框(卡片/面板用)。★MOUSE_FILTER_IGNORE —— 框是纯装饰, 不能吃掉点击。
func _nine(parent: Control, tex: Texture2D, margin: int, pos: Vector2, sz: Vector2, z := -1) -> NinePatchRect:
	return _nine_xy(parent, tex, margin, margin, pos, sz, z)


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
