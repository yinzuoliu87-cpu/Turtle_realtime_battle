extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
const TutorialGuide = preload("res://scripts/scenes/TutorialGuide.gd")   # 教程锚点: vis_rect(只认真看得见的控件)
var _top_bar = null

const RichTooltip = preload("res://scripts/scenes/rich_tooltip.gd")
## 深海币图标 —— 与商店同一张(ShopScene.COIN_TEX)。同一种货币在两屏必须长得一样,
## 拿 `◆`/`💠` 之类的字符凑就等于让玩家自己去猜"这两个数是不是同一种钱"。
const COIN_TEX = preload("res://assets/sprites/menu/ic-deepsea.png")

## ── 像素图标(2026-09-28 · 把 emoji 当图标的地方换掉)──
## ★为什么非换不可: emoji 的字形来自回退链第三级 `NotoEmoji-Regular.ttf` ——
##   抗锯齿的矢量描边, 而这一屏其余全部是 3~4px 笔触的像素画 ⇒ **同屏两种画法**,
##   正是用户 2026-09-27 点名的「ai 味/网页味」最刺眼的那一处。
##   (判据不是眼睛: `tests/verify_no_emoji_icons.gd` 问三张字体文件谁有这个码点 ——
##    只有 NotoEmoji 有 = emoji 图标; ★ ✓ ⚠ 在 NotoSansSC 里, 与正文同一套字, 不算。)
## ★尺寸: 两张源图都是 **32×32**, 一律按 **1x** 画(`icon_max_width = ICON_PX` /
##   `TextureRect.size = 32`) —— 像素贴图缩放就糊, 这里连 0.5x 都不许(源图是
##   1px 网格画的, 折半会**丢掉一半像素**, 已逐像素量过)。
const ICON_PX := 32
const LOCK_ICON := "res://assets/sprites/ui/icon-lock.png"
const EQUIP_ICON := "res://assets/sprites/ui/icon-equip.png"
## 全队装备容量那一行的节点名 —— 门禁靠**名字**找它, 不靠文案(见 `capl.name` 处的注释)。
const CAP_ROW_NAME := "EquipCapRow"
## 底栏那颗「细看」键的节点名 —— 同上, 门禁靠**名字**找它, 不拿按钮上的字当尺子
## (2026-09-28: 这颗键原来叫「详情」, `verify_inventory_layout` ⑬ 就是按那两个字找的)。
const DETAIL_BTN_NAME := "EquipDetailButton"
## 糖果罐在背包格子里的像素图。★这张图一直躺在 `assets/sprites/equip/` 里没人接线
##   (全仓 grep 零引用), 而它的文件名就是给糖果罐画的 —— 接上它不是"拿别的图顶替"。
const CANDY_JAR_ICON := "res://assets/sprites/equip/equip-candy-jar.png"
## ── 2026-10-22 背包重做的皮 ──
## 顶栏 / 两路标题木牌: 商店那一张(方案里点名「顶栏直接用商店那一套」, 用户「做」)。
const PLANK_TEX = preload("res://assets/sprites/shop/shop-plank.png")
const WORN_STAR_TEX = preload("res://assets/sprites/shop/star-glint.png")   # 卡上装备格的星级(第 0 帧)
const PLANK_MARGIN := 18
## 背包格 = 装备卡: 与商店说明卡同一套费用档框(同一件装备在两页长同一张脸); 选中整张换图(乘色提不亮深色框)。
const ITEM_CARD_TEX := [
	preload("res://assets/sprites/shop/card-frame-t1.png"),
	preload("res://assets/sprites/shop/card-frame-t2.png"),
	preload("res://assets/sprites/shop/card-frame-t3.png"),
	preload("res://assets/sprites/shop/card-frame-t4.png"),
	preload("res://assets/sprites/shop/card-frame-t5.png"),
]
const ITEM_CARD_SEL = preload("res://assets/sprites/shop/card-frame-s.png")
const ITEM_CARD_MARGIN := 8
## 单位卡的框 / 场景底图: 本页新画(PixelLab), 没到位时退回纯色。
## 统领 = 金饰框, 小将 = 铜饰框(一眼分得出谁是龟、谁是补位)。原生 75×95, 按 2 倍画。
const UNIT_CARD_TEX_PATH := "res://assets/sprites/inventory/unit-card.png"
const UNIT_CARD_MINION_TEX_PATH := "res://assets/sprites/inventory/unit-card-minion.png"
const BG_TEX_PATH := "res://assets/sprites/inventory/inv-backdrop.png"

## InventoryScene — V2 局外背包 / 出战配置 (阶段2 UI 首版, 设计§十).
## 上部: 出战阵容 (上路/下路, 龟统领 + 小将占位); 下部: 装备管理 (背包 bench).
## 首版 = 布局 + 显示 (实时挤位/防吞/装备拖拽/3合1 后续迭代). 截图验证布局用.
## 数据: season_leaders(锁定3统领) 优先, 空则 lastLineup.json 末次阵容; persistent_bench(持久背包).

const W := 1280.0
const H := 720.0
const SLOT := 140.0   # 2026-10-22 用户「装备背包4列不行吗」: 右栏 608 宽排 4 列, 格子放大(原 96)
## 格子里的文字离格边的留白。
## ★槽框贴图的金属边带**实测 6px 厚**(不是配置边距 12 —— 那是切九宫格的位置, 不是画了多宽)。
##   原来装备名摆在 x=2、底边贴着格底 ⇒ 名字压在边带上(判据 13 量到 4px)。
const SLOT_PAD := 7.0
## ★格子里不再写装备名(2026-10-21 手机版: 12 号字在 iPhone 上 1 毫米出头); 原 NAME_FS / NAME_FS_MIN / NAME_BREATH 已删。
## ── 本屏的几条布局基准线(2026-08-15 重排, 用户「利用这个空间可以把右边的排版过来」)──
##   原来顶部有一整行「🎒 背包 / 出战配置」的牌子 —— 玩家是自己点进来的, 不需要被告知
##   自己在哪一页 ⇒ 删掉, 整屏内容上提, 右侧那条从 y≈180 空到底的死列由羁绊区补上。
## ── 2026-10-22 背包重做(用户「把龟做成卡片」「最好要支持卡片式拖动的」· 方案书 20261022-背包重做.md) ──
##   6 张竖卡一排: 上路三张在左、下路三张在右, 各顶一块木牌标题; 右边羁绊列; 下半屏整片是背包。
##   原来两条上下叠放的横卡战场带(244×116)与常驻图例删掉 —— 卡上装备格被那个版式卡死在 40px。
## ★2026-10-22 二改(用户「背包你左边应该只放6张卡，携带装备应该是贴在卡上吧」):
##   左边 = 6 张卡两排(上路一排、下路一排), 装备三格贴在卡的下沿(不再另放托盘); 卡下面一条羁绊;
##   右边整块 = 背包(7 列, 22 件一屏放得下)。
## ★2026-10-22 三改(用户「卡片大一点啊」): 框图按 3 倍画(原生 75×95 → 225×285, 整数倍不变形), 6 张卡占满左半边;
##   右边背包 5 列, 羁绊条挪到右下。
## ★四改(用户「每个龟的卡片你告诉我是怎么回事」): 框图裁掉四周透明留边(原生 64×84, ×3 = 192×252), 卡与卡等距;
##   装备不再压在木框下沿上, 而是框底一条木托条、三格嵌在条里(空格画成凹槽)。
const CARD_W := 192.0
const CARD_H := 252.0          # = 裁边后的框图 × 3
const CARD_GAP := 12.0
const CARDS_X := 24.0
const LANE_HDR_Y := 84.0       # 上路木牌; 下路木牌 = 它 + ROW_PITCH
const LANE_SIGN_H := 36.0      # = 20 号字 + 描边 5 的最小行高(28 时字撑出木牌、压进卡顶 4px)
## 卡顶 = 木牌下沿 + 4(框图已裁掉透明留边, 不再让木牌压进卡里 —— 那会盖住框顶的贝壳)
const CARD_DROP := LANE_SIGN_H + 4.0
const ROW_PITCH := CARD_DROP + CARD_H + 2.0   # 297
const CARDS_Y := LANE_HDR_Y + CARD_DROP
const CARD_BORDER := 39.0      # 框到内窗的距离(裁边后原生 13, × 3)
const PORTRAIT_H := 90.0       # 内窗(114×174)上半截立绘
## ★立绘比内窗大一圈、压出木框(卡牌游戏常见的「破框」画法)
const PORTRAIT_POP := 20.0
const NAME_Y := CARD_BORDER + PORTRAIT_H + 6.0     # 135
const NAME_FS := 24
const EQ_CELL := 56.0          # 嵌在托条里的装备格
const EQ_GAP := 6.0
const GEAR_STRIP := Rect2(6.0, 186.0, 180.0, 62.0)   # 框底木托条(卡内坐标)
const SLOT_ROW_Y := 189.0      # 三格的 y(托条里)
## 旧名保留: 教程锚点 / 门禁按它们找「阵容区」
const LANE_TOP := CARDS_Y
const LANE_GAP := ROW_PITCH
const LEFT_W := 3.0 * CARD_W + 2.0 * CARD_GAP   # 左边卡区宽 695
## 顶栏右侧「币 / 全队装备」这一组的左沿(不跟羁绊列走)。
const HDR_GROUP_X := 828.0
## 顶栏「站位」签占的宽度 + 间距(右上「币 / 全队装备」这一组为它左移这么多)。
const FORMATION_BTN_ROOM := 112.0
## 教程里右上「跳过教程」(132 宽)比它占的「?」(81 宽)多出的那截, 再加两格间距的余量。
const TUT_SKIP_EXTRA := 80.0
## 背包: 右边整块(羁绊条在它下面)
const BENCH_X := CARDS_X + LEFT_W + 20.0     # 644
const BENCH_HDR_Y := LANE_HDR_Y
## 羁绊: 背包下面一条, 一行横排(多了横着滑)
const SYN_X := BENCH_X
const SYN_W := 1252.0 - BENCH_X
const SYN_TOP := 600.0          # 16:9 下的名义位置; 实际走 syn_top()(贴着可用区底边, 手机避开底部横条)
const SYN_BOTTOM := 712.0
const SYN_HORIZONTAL := true
const SYN_CHIP_W := 192.0      # 两块整的 + 第三块露一截(看得出还能往右滑)
const BENCH_TOP := BENCH_HDR_Y + 34.0
const BENCH_PITCH := SLOT + 12.0   # 格子行距(格 + 12 间隙)
## ★2026-10-22 背包三改: 左边是大卡, 操作条横在屏幕底会压住下路那排卡(选中装备时正要去点卡)
##   ⇒ 三种操作条都住进右栏(背包那一栏)、改成两层: 上面名字 + 效果, 下面一排键。
const OP_BAR_H := 232.0
const OPS_X := 644.0          # = BENCH_X(常量顺序在前, 写死同值)
const OPS_W := 1252.0 - OPS_X
## ★2026-10-21 手机优先: 最小字号 20(iPhone 上约 11pt); 底边只用到「视口底 - 底部横条」(见 _bottom_limit)。
const MIN_FONT_PX := 20
const OP_BODY_FS := 20         # 底栏效果正文字号(14 → 20 手机最小字号)
const OP_BODY_ROWS := 3        # 底栏效果正文显示几【整】行(20 号字下最长的简述 3 行; 2026-10-21 由 2 改 3)
const DETAIL_BODY_FS := 20     # 装备详情框正文字号(16 → 20)
const P2 = preload("res://scripts/gamedata/phase2_config.gd")
const Phase2Types = preload("res://scripts/gamedata/phase2_types.gd")
const UnitStatPreview = preload("res://scripts/scenes/inventory/unit_stat_preview.gd")   # 点龟卡的属性小卡(本体 + 装备)
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")   # 装备逐星属性表(与战斗实装同源; 2026-07-23 从回合制P2RT抽出)
const Phase2Minion = preload("res://scripts/gamedata/phase2_minion.gd")

var _sel_bench: int = -1   # 当前选中的背包装备索引 (-1=无)
## 糖果罐是否被选中。★单独一个标记而不是塞进 `_sel_bench` ——
##   `_sel_bench` 直接索引 `GameState.persistent_bench`, 而糖果罐是合成条目不在里面。
var _sel_jar: bool = false
var _inv_ops := InvOps.new(self)   # 背包·装备/卸下/卖出 业务逻辑(2026-07-25 抽出)
var _inv_jar := InvCandyJar.new(self)   # 背包·糖果罐(打碎领奖)(2026-07-25 抽出)
var _formation := InvFormation.new(self)   # 背包·站位编辑(2026-10-19)
var _drag := InvDrag.new(self)   # 背包·卡片式拖动(2026-10-22 用户「最好要支持卡片式拖动的」)
## 本次重建出来的单位卡 [{box, lane, idx, unit}] —— 拖动时逐张判能不能接(抬亮 / 压暗), 门禁也读它
var _unit_boxes: Array = []
## 背包滚动区: 已装的装备拖回这里 = 卸下
var _bench_area: Control = null
## 拖动中有人要重建 ⇒ 记下来, 拖完再建(被拖的卡就是重建要销毁的节点)
var _rebuild_pending := false
## 单位卡按下的位置(松手时位移小才算点一下 —— 按下就算的话, 想拖的那一下会先被当成点、整页重建)
var _unit_press := Vector2.ZERO
## ── 点装备弹说明小卡(2026-10-22 用户「然后问你点击物品应该怎么样」→ 我答「旁边弹说明小卡, 卡底是动作」) ──
##   与商店 / 局内信息面板同一张 InspectCard。背包里的一件 = 卡底「卖出 / 详情」; 卡上的一件 = 「卸下 / 详情」。
var _insp := InspectCard.new(self)
var _ui_layer: Node = null           # InspectCard 往这里挂卡(= 本场景)
var _insp_anchor: Control = null     # 小卡贴着谁弹(被点的那一格 / 那张单位卡)
## 点了单位卡上的哪一件 {lane, idx, cell(真实下标)}; 空 = 没点
var _sel_worn: Dictionary = {}
var _inv_synergy := InvSynergy.new(self)   # 背包·类型羁绊面板+详情弹框(2026-07-25 抽出)
var _dl_sel: Dictionary = {}   # 双路布阵选中框 {lane, idx} (点两个互换分路)
var _vw: float = 1280.0   # 实际视口宽(手机expand后可达~1560): 顶栏/背包按真实宽铺开·不再左挤留空(2026-07-18)
var _press_pos := Vector2.ZERO   # 背包格触屏点选/滑动判定: 松开位移小才算点选(可滑动列表·2026-07-18)
var _press_ms := 0               # 背包格按下的时刻(按住 ≥ InvDrag.HOLD_MS 再动 = 拿起来拖)
var _op_body: RichTextLabel = null   # 底栏效果正文(算"还有几行被裁"要读它自己报的行数)
var _op_more: Label = null           # 底栏"下面还有 N 行"提示

func _ready() -> void:
	if OS.has_environment("INV_DEMO"):   # dev截图用: 内存填演示背包(不save·不碰真存档)
		_inject_demo_inventory()
	if OS.has_environment("PH_DEMO"):    # dev: 清统领模拟大轮开局 → 看统领1/2/3问号占位(不save)
		GameState.season_leaders = []
		GameState.dual_lineup = {}
	_rebuild()
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null:
		_td.attach_guide(self, "inventory")        # 教程: 点击一件装备 → 点击一只龟装上 → 点击完成教程
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
	if _drag.active():
		_rebuild_pending = true
		return
	_rebuild_pending = false
	_unit_boxes = []
	_bench_area = null
	_insp_anchor = null
	# ★2026-08-01 改回设计宽(用户「有些画面都没有居中」「pc端做一板，手机端做一板」):
	#   原来这里取【真实视口宽】(手机 expand 后 ~1560)让顶栏/背包铺满, 但页面里其余元素
	#   仍按 1280 设计坐标摆 —— 于是宽屏上"一半跟着屏幕走、一半不动", 审计器实测
	#   1280→1680 时内容包围盒整体漂 +200(比不适配还乱)。
	#   现在统一走 UIFrame 设计框(内容锁 1280×720 居中·背景铺满整窗), 全屏一个口径。
	_vw = W
	for c in get_children():
		if c.is_in_group("tut_overlay") or c.is_in_group(TOAST_GROUP):
			## ★教学浮层(引导/下一站按钮)不随重建销毁 —— 装/卸装备会触发 _rebuild。
			## ★★提示层(toast)同理, 而且它是本函数亲手杀掉过的: 见 `_toast()` 头注。
			continue
		c.visible = false   # 立即隐藏避免与新节点重叠 (queue_free 延到帧末, 不在信号中即时free防崩)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	## 点空白处 = 收起说明小卡 / 取消选中(松手才算, 与别处点按同一个口径)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_clear_selection())
	## ★2026-10-22 背包重做: 场景底图(像素后仓), 与商店的木头货铺是同一条街。满铺(UIFrame 不收编满铺层)。
	if ResourceLoader.exists(BG_TEX_PATH):
		var bgi := TextureRect.new(); bgi.name = "InvBackdrop"
		bgi.texture = load(BG_TEX_PATH)
		bgi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bgi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bgi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bgi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bgi)
		var dim := ColorRect.new(); dim.name = "InvBackdropDim"
		dim.color = Color(0.02, 0.04, 0.06, 0.38)   # 压一层暗: 卡片和格子在前, 底图只当环境
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)

	## ★顶部那行「🎒 背包 / 出战配置」已删(用户 2026-08-15:「玩家是自己点进来的」)。
	##   它占着 440×46 只为复述玩家刚点过的按钮; 腾出来的整条顶栏给右侧羁绊列上提。
	##   ⚠ 别再加回来 —— 也别改成小字放别处, 那还是同一块牌子。

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   原来是两枚金属签牌皮的厚按钮(返回/商店) + 右边一枚手写的深底小方框(?)
	##   —— **同一条横线上两套语言**。146 款参考里返回一律是扁平薄片,
	##   而「去另一个枢纽页」的入口紧跟在页名后面(Botworld 的 Loadout/Inventory/Robopedia)。
	##   右侧的深海币/装备容量那条资源条**不动** —— 它本来就是参考里的结构。
	var shop_locked: bool = int(GameState.season_total_battles) <= 0
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		## ★★2026-09-28 去掉页名前的 🧳(理由与图鉴/设置/战绩同, 见 CodexScene 那条长注释):
		##   146 款参考的枢纽页顶栏一律是「返回箭头 + 裸页名」, 没有一款给页名挂图标;
		##   而 🧳 的字形来自 NotoEmoji, 与这一屏的像素笔触是两套画法。
		"title": "",
		## 2026-10-22 背包重做: 顶栏换商店那一套(木牌签、不画深色底带)—— 两页来回切是同一条街。
		"palette": TopBar.WOOD.merged({"no_plate": true, "chip_tex": PLANK_TEX, "chip_margin": PLANK_MARGIN}),
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
		## ★2026-10-22 用户「左上角返回，商店，背包你到底打算怎么设计啊」: 两页左上角一模一样 ——
		##   「← | 商店 | 背包」一对页签, 当前页那一签亮着(active), 点另一签切过去; 不再单写页名。
		"left_actions": [[
			"商店",
			func(): get_tree().change_scene_to_file("res://scenes/Shop.tscn"),
			{"disabled": shop_locked,
				"tooltip": "本大轮首战后解锁" if shop_locked else "前往商店"},
		], [
			"背包", func() -> void: pass, {"active": true},
		]],
	})
	## ★★2026-09-28「🔒 商店」的锁**不许只是删掉** —— 它是这枚键的【状态】(没开店),
	##   删了就只剩一个灰键, 玩家看不出为什么点不动。⇒ 换成像素挂锁图标。
	##   (🛒 是纯装饰, 「商店」两个字已经说完了它是什么 ⇒ 直接去掉, 不拿别的图顶替。)
	## ★1x: 源图 32×32, `icon_max_width = ICON_PX` ⇒ 不缩放; NEAREST 保住 3px 笔触。
	if shop_locked and not _top_bar.action_btns.is_empty():
		var _shop_btn: Button = _top_bar.action_btns[0] as Button
		if _shop_btn != null and ResourceLoader.exists(LOCK_ICON):
			_shop_btn.icon = load(LOCK_ICON)
			_shop_btn.expand_icon = true
			_shop_btn.add_theme_constant_override("icon_max_width", ICON_PX)
			_shop_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## ── 右上角这一组: 深海币 / 全队装备容量 / 「?」 **排成横着一条**(用户 2026-08-15)──
	##   原来是"币在上、装备上限在下"竖着堆在最右 232px 里, 而「?」还单独浮在它们左边 ——
	##   三块东西谁也不挨着谁, 中间那片宽度全空着(标题删掉之后更空)。
	##   现在整组左沿对齐下面的羁绊列(SYN_X), 右沿对齐屏幕右边距, 宽度正好 SYN_W。
	##   字号也一并调大: 用户「字搞这么小干嘛」。
	## ★深海币用**真图标**(assets/sprites/menu/ic-deepsea.png), 不再用 `◆`/`💠` 拿字符凑 ——
	##   商店里一直用的就是这张(ShopScene.COIN_TEX)。图标是用户点名允许复用的那一类。
	var ci := TextureRect.new()
	ci.texture = COIN_TEX
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★教程: 右上「?」那一格让给「跳过教程」(132 宽 > 「?」的 81) ⇒ 币/容量这一组左移让位。
	## ★2026-10-19 顶栏「?」左边多了「站位」签(非教程时) ⇒ 这一组再左移一格让位(实拍: 原位置被「站位」压住「全队装备」)。
	## ★教程 v3(2026-10-20): 教程里「站位」也在(教程要教它) ⇒ 让位 = 跳过钮多出的那截 + 「站位」那一格。
	var _tsh: float = (TUT_SKIP_EXTRA + FORMATION_BTN_ROOM) if _tut_on() else FORMATION_BTN_ROOM
	ci.position = Vector2(HDR_GROUP_X - _tsh, 24); ci.size = Vector2(36, 36)
	add_child(ci)
	var coin := Label.new()
	coin.text = "%d" % int(GameState.meta_deepsea_coins)
	coin.add_theme_font_size_override("font_size", 26)
	coin.add_theme_color_override("font_color", Color("#5fd0e0"))
	coin.position = Vector2(HDR_GROUP_X + 42 - _tsh, 22); coin.size = Vector2(130, 40)
	coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(coin)

	# ★全队装备容量计数器 (2026-07-27 新规则): 单只≤3 且 全队合计≤team_equip_cap(赛季等级)。
	#   没有这个计数器, 玩家点不上装备时只会觉得"点了没反应" —— 容量是全队共享的, 光看单只格子看不出来。
	var used := int(GameState.team_equipped_count())
	var cap := int(GameState.team_equip_cap())
	## ★★2026-09-28「⚙」→ 像素图标 `ui/icon-equip.png`(交叉双剑)。
	##   ⚙ 是**齿轮**, 而这一行说的是**装备件数** —— 齿轮在通用 UI 里代表"设置",
	##   本来就跟这行的意思对不上(同一个 ⚙ 在设置页顶栏也用着)。换成"装备"自己那张图。
	##   摆法照上面深海币那一组: 图标在字前面, 各自一个控件, 图标 1x 不缩放。
	var eqi := TextureRect.new()
	eqi.texture = load(EQUIP_ICON)
	eqi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eqi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eqi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	eqi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eqi.position = Vector2(HDR_GROUP_X + 176 - _tsh, 26); eqi.size = Vector2(ICON_PX, ICON_PX)
	add_child(eqi)
	var capl := Label.new()
	## ★★这一族**必须有名字**(`CAP_ROW_NAME`)。由来与 `SettingsScene.ACCT_ROW_PREFIX` 同:
	##   `verify_inventory_layout` ⑤ 原来靠 `begins_with("⚙ 装备")` 找它 —— **拿字面量当尺子**。
	##   而我这一刻正是把「⚙」换成图标 ⇒ 那条断言会**恒真地找不到**(cap_r 全零),
	##   看着像"三块没排成一条线", 实际是尺子被我自己改没了
	##   (memory `fb-tests-pin-screen-words` / `fb-gate-tautological-when-it-spans-a-frame`)。
	##   ⇒ 判据平移到【这一族节点在不在、在哪】, 文案以后怎么改都不影响它。
	capl.name = CAP_ROW_NAME
	capl.text = "全队装备 %d/%d" % [used, cap]
	capl.add_theme_font_size_override("font_size", 24)
	capl.add_theme_color_override("font_color", Color("#ffb454") if used >= cap else Color("#b9cbdc"))
	capl.position = Vector2(HDR_GROUP_X + 176 + ICON_PX + 6 - _tsh, 22); capl.size = Vector2(190 - ICON_PX - 6, 40)
	capl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var _nxt := int(GameState.season_level) + 1
	## ★原文"全队 6 只合计上限随赛季等级提升。当前 Lv3 → 5 件"是规则书的写法("上限""提升"
	##   加一个箭头)。改成跟玩家说话: 现在能装几件、再升一级能装几件。
	capl.tooltip_text = "单位装备上限 %d 件\n全队上限由赛季等级决定（当前 Lv%d：%d 件）%s" % [
		P2.UNIT_EQUIP_CAP, int(GameState.season_level), cap,
		("\nLv%d 可装备 %d 件" % [_nxt, P2.team_equip_cap(_nxt)]) if _nxt <= P2.MAX_LEVEL else "\n已达上限"]
	add_child(capl)

	## ★糖果罐已改为【背包格子里的一张卡】(用户 2026-08-14「以一个装备的形式」),
	##   右上角那块 372×44 的独立面板不再画 —— 否则同一个东西**同时出现在两个地方**。
	##   `InvCandyJar` 本身保留: 打碎的领奖/存档/弹窗逻辑(`_on_break_jar`)仍由它负责,
	##   新卡片只是换了个入口去调它。

	var leaders := _lineup_ids()
	_build_lineup(leaders)
	## 底部操作条出来时(选中了装备 / 糖果罐 / 有装备的单位), 它正好压在左下的羁绊条上 ⇒ 这时不画羁绊(否则标题只剩半截)
	if _op_bar_shows():
		_inv_synergy.first_on_chip = null
	else:
		_inv_synergy._build_synergy_panel(leaders)
	_build_bench()
	_build_op_bar()
	_insp.card = null; _insp.key = ""      # 上面整页清过一遍, 旧卡已在释放队列里
	_open_item_card()
	_open_unit_card()
	# ★★UIFrame 必须在【每次重建之后】重挂(用户 2026-08-01:「背包点一下后整个屏幕左移」)。
	#   本函数开头把所有子节点 queue_free —— 设计框也在里面。而 attach 原来只在 _ready 调过一次,
	#   于是点一下之后【一个框都没有】, 内容退回原始设计坐标 → 整体左移(实测宽屏下左移 140px,
	#   正好等于框的居中偏移量)。attach 是幂等的, 重复调只重新收编+居中。
	#   ★同样的坑商店踩过一次(见 ShopScene._rebuild 末尾), 当时没横向查其它屏 —— 这次补齐。
	UIFrame.attach(self)
	## 首次提示「羁绊已激活」(账号侧, 教程中不出; 判据与文案在 FirstTips)
	if _inv_synergy.first_on_chip != null:
		FirstTips.show(self, FirstTips.FIRST_SYNERGY, _inv_synergy.first_on_chip)

## 取出战 3 统领: season_leaders 优先, 空则 lastLineup.json.
## ★2026-08-11 本体收拢进 GameState.lineup_leader_ids(商店/背包共用, 副本会漂)。
func _lineup_ids() -> Array:
	return GameState.lineup_leader_ids()

# ─── 上部: 双路布阵 (上战场/下战场, 3统领+3小将分3+3; 点头像互换分路, 点小将切前/后排) ───
const UBOX_W := CARD_W   # 阵容单位框(再放大·填左侧空间+适手机点触·用户2026-07-19)
const UBOX_H := CARD_H
const UBOX_GAP := CARD_GAP

func _build_lineup(_leaders: Array) -> void:
	var lineup := GameState.get_dual_lineup()
	## ★「?」搬进顶栏原语(2026-09-19): 原来它是手写的 StyleBoxFlat(深底+1px边+圆角),
	##   而同屏的返回/商店是金属签牌皮 —— 同一条横线上两套语言。
	##   现在三枚都走 `TopBar._chip()`, 同款同高同热区。
	if _top_bar != null:
		var _hb = _top_bar.add_right_action("?", func(): _show_lineup_help(), {"tooltip": "阵容说明"})
		_hb.position = Vector2(SYN_X + SYN_W - 81.0, (TopBar.BAR_H - TopBar.TOUCH_MIN) / 2.0)
		## ★2026-10-19 站位在背包里摆(用户「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」)。
		##   与「?」同一种顶栏签, 排在它左边。
		var _fb = _top_bar.add_right_action("站位", func(): _formation.open(), {"tooltip": "设置开战站位"})
		_fb.name = "FormationBtn"
		_fb.position = Vector2(_hb.position.x - 8.0 - _fb.size.x, _hb.position.y)
		##   顶栏换宽度时按「离右沿多远」重排右侧签(`TopBar._fit_to_viewport`), 记的是添加那一刻的默认位
		##   ⇒ 两枚会叠在一起。把「站位」那一格的离右沿距离改成「?」的再往左一格。
		var _ib: int = _top_bar.action_btns.find(_hb)
		var _if: int = _top_bar.action_btns.find(_fb)
		if _ib >= 0 and _if >= 0 and _if < _top_bar._right_off.size():
			_top_bar._right_off[_if] = float(_top_bar._right_off[_ib]) + 8.0 + _fb.size.x
		## ★教程: 「?」让位给右上「跳过教程」(见 _tutorial_skip_slot); 返回键的位置换成「完成教程」。
		## ★教程 v3: 「站位」不再藏(10-19 起站位只能在这里改, 教程第 12~14 步就教它) ⇒ 排到跳过钮左边。
		if _tut_on():
			_hb.visible = false
			## 跳过钮(132 宽)占「?」(81 宽)那一格并向左多出一截 ⇒ 「站位」再往左让这一截。
			##   跳过钮自己的位置反过来跟着「站位」走(`_tutorial_skip_slot`), 宽屏上两者一起贴右沿, 不会叠。
			var _extra: float = 132.0 - 81.0
			_fb.position.x -= _extra
			if _ib >= 0 and _if >= 0 and _if < _top_bar._right_off.size():
				_top_bar._right_off[_if] = float(_top_bar._right_off[_ib]) + _extra + 8.0 + _fb.size.x
			_build_tut_finish()
	## ★2026-10-22 背包重做: 6 张竖卡一排, 上路三张在左、下路三张在右, 各顶一块木牌标题。
	##   原来两条上下叠放的战场带 + 常驻图例(统领 / 小将 / 前排后排)删掉 —— 规则在「?」里。
	for li in range(2):
		var lkey: String = "top" if li == 0 else "bottom"
		var arr: Array = lineup.get(lkey, [])
		var lead_n := 0
		for u in arr:
			if u is Dictionary and str(u.get("kind", "")) == "leader": lead_n += 1
		var ly: float = LANE_HDR_Y + float(li) * ROW_PITCH
		for i in range(arr.size()):
			var _ub: Control = _dl_unit_box(lkey, i, arr[i], lead_n, Vector2(CARDS_X + float(i) * (CARD_W + CARD_GAP), ly + CARD_DROP))
			add_child(_ub)
			if lkey == "top" and i == 0:
				_tut_first_leader = _ub  # 教程手势指针「点击一只龟装上」指的就是它(上路第一只)
		## 木牌后加 = 压在卡的上沿空白上(见 CARD_DROP)
		var lsign := _lane_sign("上战场" if li == 0 else "下战场", Color("#ffd93d") if li == 0 else Color("#8fdcff"))
		lsign.name = "LaneSign_" + lkey
		lsign.position = Vector2(CARDS_X, ly); lsign.size = Vector2(LEFT_W, LANE_SIGN_H)
		add_child(lsign)


## 一路的木牌标题(商店同一张木牌底)。
func _lane_sign(txt: String, col: Color) -> Control:
	var np := NinePatchRect.new()
	np.texture = PLANK_TEX
	np.patch_margin_left = PLANK_MARGIN; np.patch_margin_right = PLANK_MARGIN
	np.patch_margin_top = PLANK_MARGIN; np.patch_margin_bottom = PLANK_MARGIN
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new(); l.text = txt
	l.add_theme_font_size_override("font_size", MIN_FONT_PX)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("#1a0e05")); l.add_theme_constant_override("outline_size", 5)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.add_child(l)
	return np

## 这一只单位身上的装备清单 —— **全屏唯一一份口径**。
##
## ★★为什么必须抽出来(2026-09-30 抓到的真 bug, 探针实测):
##   统领的装备住在 `GameState.persistent_equipped[pid]`, 小将的住在 `unit["equips"]`。
##   `_dl_unit_box` 原来就地写着这个二分, 而底部那条「44pt 卸下条」(`_build_unit_equip_bar`)
##   **只读了后一半** —— `unit.get("equips", [])` 对统领永远是空 ⇒ `eqs.is_empty()` 就地 return
##   ⇒ **选中统领卡时那条操作栏一个按钮都不建**。实测: 选中带 3 件装备的统领 basic,
##     「卸下」按钮 **0 个 / 标题 0 条**; 同一刻选中小将 **2 个 190×81**(对照组成立)。
##   于是 `_build_equip_cells` 注释里写的「真正的 44pt 路径另给」对**一半的单位是句空话**:
##   统领要卸装备只剩那 3 个 40px(21.7pt) 的迷你格 —— 台账 ⑭「整屏最小的靶子恰好是主操作」
##   说的正是这个, 而它之所以成立**不是因为格子小, 是因为大的那条路根本没通**。
##   ⇒ 两处读同一个函数。手抄的副本必然落后(memory fb-hand-rolled-copies-drift)。
func _unit_equips(unit: Dictionary) -> Array:
	if str(unit.get("kind", "")) == "leader":
		if GameState.persistent_equipped is Dictionary:
			var pe = GameState.persistent_equipped.get(str(unit.get("id", "")), [])
			return pe if pe is Array else []
		return []
	return unit.get("equips", []) if unit.get("equips", null) is Array else []


## 把一只单位的装备分成【占位的】与【羁绊白送的】两摊, 各自带真实下标。
## ★下标必须是 `_unit_equips()` 里的真实下标 —— 卸下按它走, 不能按"第几个格子"
##   (赠送件插在数组中间时, 按格号卸会卸错一件)。
## ★这也是**唯一一份**分摊口径: 三个迷你格与底部那条 44pt 卸下条都用它,
##   否则两边对"哪一件算装备位"各有一套, 屏幕上就会出现"格子里有、卸下条里没有"。
func _split_equips(eqs: Array) -> Array:
	var wear: Array = []
	var grants: Array = []
	for i in range(eqs.size()):
		if GameState.is_synergy_grant(eqs[i]):
			grants.append({"i": i, "it": eqs[i]})
		else:
			wear.append({"i": i, "it": eqs[i]})
	return [wear, grants]


## 一张单位卡(竖卡, 2026-10-22 背包重做): 上 = 立绘, 中 = 名字, 下 = 三格装备(+ 羁绊赠送徽章一行)。
##   松手算点一下: 无选中 = 选中 / 已选背包装备 = 装上 / 已选单位 = 交换。
##   按住拖: 拖这张卡去和别的卡换位; 按在装备格上拖 = 拖那一件(换人 / 拖回背包卸下)。
func _dl_unit_box(lane: String, idx: int, unit: Dictionary, lead_n: int, pos: Vector2) -> Control:
	var kind := str(unit.get("kind", "minion"))
	var pid := str(unit.get("id", ""))
	var is_ph := kind == "leader" and pid == ""   # 占位统领(大轮未选统领·id空) → 显示「统领N ?」
	var sel := str(_dl_sel.get("lane", "")) == lane and int(_dl_sel.get("idx", -1)) == idx
	var is_elite := kind == "minion" and lead_n == 0 and _dl_first_minion_idx(lane) == idx
	var can_equip := _sel_bench >= 0 and not is_ph   # 选了装备 → 这张卡可装
	var box := Panel.new()
	box.name = "UnitCard_%s_%d" % [lane, idx]
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.position = pos; box.size = Vector2(CARD_W, CARD_H)
	box.add_child(_unit_card_frame(is_ph, is_elite, kind == "leader"))
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素框不插值
	var is_reg_minion := kind == "minion" and not is_elite
	var _worn: Array = []   # 卡上已装的装备格 [{rect, cell, it}] —— 按在它上面拖 = 拖这一件
	## 立绘那一截(框图内窗本身就是深海蓝底, 不再另垫一块)
	var pw := Rect2(CARD_BORDER, CARD_BORDER, CARD_W - 2.0 * CARD_BORDER, PORTRAIT_H)
	if is_ph:
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", 58)
		q.add_theme_color_override("font_color", Color("#9fb2c8"))
		q.position = pw.position; q.size = pw.size
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
			a.position = pw.position - Vector2(PORTRAIT_POP, PORTRAIT_POP + 6.0); a.size = pw.size + Vector2(2.0 * PORTRAIT_POP, 2.0 * PORTRAIT_POP)
			a.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(a)
	var nm := Label.new()
	if is_ph:
		nm.text = "统领%d" % (int(unit.get("slot", idx)) + 1)
	elif kind == "leader":
		var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
		nm.text = str(pet.get("name", pid))
	else:
		nm.text = "精英小将" if is_elite else "小将"
	nm.add_theme_font_size_override("font_size", NAME_FS); nm.add_theme_color_override("font_color", Color("#f4e8cf"))
	nm.add_theme_color_override("font_outline_color", Color("#1a0e05")); nm.add_theme_constant_override("outline_size", 4)
	nm.position = Vector2(20.0, NAME_Y); nm.size = Vector2(CARD_W - 40.0, 34)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(nm)
	nm.visible = not is_reg_minion   # 普通小将: 名字那一行让给「前排 / 后排」签
	if is_ph:
		var hint := Label.new()
		hint.text = "空槽位"
		hint.add_theme_font_size_override("font_size", MIN_FONT_PX)
		hint.add_theme_color_override("font_color", Color("#9a8a70"))
		hint.position = Vector2(4, NAME_Y + 2.0); hint.size = Vector2(CARD_W - 8, 30)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; box.add_child(hint)
	else:
		var eqs: Array = _unit_equips(unit)
		# ★格数【恒定 = 单只上限 3】: 三格就是"你的装备位"; 羁绊赠送件不进这三格, 另挂在下面一行(见 _build_equip_cells)。
		var strip := NinePatchRect.new(); strip.name = "GearStrip"
		strip.texture = PLANK_TEX
		strip.patch_margin_left = PLANK_MARGIN; strip.patch_margin_right = PLANK_MARGIN
		strip.patch_margin_top = PLANK_MARGIN; strip.patch_margin_bottom = PLANK_MARGIN
		strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		strip.position = GEAR_STRIP.position; strip.size = GEAR_STRIP.size
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(strip)
		_worn = _build_equip_cells(box, SLOT_ROW_Y, eqs, P2.UNIT_EQUIP_CAP, GEAR_STRIP.position.x)
	# 小将 前排/后排 签: 立绘窗下沿居中(精英小将 = 统领替身, 不显)
	if is_reg_minion:
		var front := str(unit.get("role", "front")) == "front"
		var tgl := Button.new()
		tgl.text = "前排" if front else "后排"
		tgl.tooltip_text = "切换站位：前排近战 / 后排远程"
		tgl.add_theme_font_size_override("font_size", MIN_FONT_PX)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color("#5a3410") if front else Color("#0f3646")
		tsb.border_color = Color("#e0954a") if front else Color("#4ab0d0")
		tsb.set_border_width_all(1); tsb.set_corner_radius_all(6)
		var _tf := UISkin.nine("chip-frame.png", 7, tsb)
		if _tf is StyleBoxTexture:
			var _tc: Color = UISkin.tint_of(tsb.border_color)
			for _st in [["normal", 1.0], ["hover", 1.22], ["pressed", 0.74]]:
				var _c := StyleBoxTexture.new()
				_c.texture = (_tf as StyleBoxTexture).texture
				_c.set_texture_margin_all(7)
				_c.modulate_color = Color(_tc.r * float(_st[1]), _tc.g * float(_st[1]), _tc.b * float(_st[1]), 1.0)
				_c.content_margin_left = 6; _c.content_margin_right = 6
				_c.content_margin_top = 2; _c.content_margin_bottom = 2
				tgl.add_theme_stylebox_override(str(_st[0]), _c)
		else:
			tgl.add_theme_stylebox_override("normal", tsb)
			tgl.add_theme_stylebox_override("hover", tsb)
			tgl.add_theme_stylebox_override("pressed", tsb)
		tgl.add_theme_color_override("font_color", Color("#ffdba8") if front else Color("#b8e8ff"))
		tgl.position = Vector2((CARD_W - 104.0) * 0.5, NAME_Y - 2.0); tgl.size = Vector2(104, 40)
		tgl.focus_mode = Control.FOCUS_NONE
		tgl.pressed.connect(func(): _dl_toggle_role(lane, idx))
		## 热区 = 立绘窗下半截(44pt 达标); 立绘本来就不是别的操作的靶子
		var pad := Control.new(); pad.name = "TouchPad"
		pad.position = Vector2(-((CARD_W - 2.0 * CARD_BORDER) - 96.0) * 0.5, 38.0 - 81.0 + 2.0); pad.size = Vector2(CARD_W - 2.0 * CARD_BORDER, 81)
		pad.mouse_filter = Control.MOUSE_FILTER_STOP
		pad.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _dl_toggle_role(lane, idx))
		tgl.add_child(pad)
		box.add_child(tgl)
	## 状态描边(选中 = 金 / 选了装备时可装 = 绿): 像素直边四条, 不靠给深色木框乘色(乘法提不亮)
	if sel:
		_ring(box, Color("#ffd93d"), 4.0)
	elif can_equip:
		_ring(box, Color("#7fe39a"), 3.0)
	## ★松手才算点一下(按下就算会先整页重建, 按住想拖就拖不起来)。
	box.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_unit_press = ev.position
			elif ev.position.distance_to(_unit_press) < 16.0:
				if _sel_bench < 0:
					for wc in _worn:
						if (wc["rect"] as Rect2).has_point(ev.position):
							_on_worn_click(lane, idx, int(wc["cell"]))
							return
				_dl_click(lane, idx))
	if (str(_sel_worn.get("lane", "")) == lane and int(_sel_worn.get("idx", -1)) == idx) or sel:
		_insp_anchor = box
	_unit_boxes.append({"box": box, "lane": lane, "idx": idx, "unit": unit})
	_drag.wire_unit(box, lane, idx, unit, _worn)
	return box


## 单位卡的框(像素木框, 卡的上半截; 素材没到位时退回纯色框)。
func _unit_card_frame(is_ph: bool, is_elite: bool, is_leader: bool) -> Control:
	var path: String = UNIT_CARD_TEX_PATH if (is_leader or is_elite) else UNIT_CARD_MINION_TEX_PATH
	if ResourceLoader.exists(path):
		var fr := TextureRect.new(); fr.name = "CardFrame"
		fr.texture = load(path)
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fr.size = Vector2(CARD_W, CARD_H)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_ph:
			fr.modulate = Color(0.62, 0.66, 0.74)
		elif is_elite:
			fr.modulate = Color(1.0, 0.9, 0.7)
		return fr
	var pnl := Panel.new(); pnl.name = "CardFrame"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#22304a") if is_ph else Color("#16202c")
	sb.border_color = Color("#c79a3a") if is_elite else Color("#7a5530")
	sb.set_border_width_all(int(CARD_BORDER / 2.0))
	pnl.add_theme_stylebox_override("panel", sb)
	pnl.size = Vector2(CARD_W, CARD_H)
	pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pnl


## 卡片外圈一道像素直边(四条, 不用圆角盒)。
func _ring(box: Control, col: Color, w: float) -> void:
	for r in [Rect2(-w, -w, box.size.x + 2.0 * w, w), Rect2(-w, box.size.y, box.size.x + 2.0 * w, w),
			Rect2(-w, 0, w, box.size.y), Rect2(box.size.x, 0, w, box.size.y)]:
		var e := ColorRect.new(); e.name = "Ring"
		e.color = col
		e.position = (r as Rect2).position; e.size = (r as Rect2).size
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(e)

## 单位身上的装备格一行: 填充格显图标·点它=**选中这只单位**(底部随即出现大号「卸下」键);
## 选中装备时格子透传→点框body装备.
## ★★`is_leader` / `pet_id` 两个参数 2026-09-30 **删掉了**: 它们原来只喂给格子上那句
##   就地卸下(`_unequip_at(pet_id, …)`); 卸下改走底部 81px 的键之后这两个就没人读了,
##   留着就是下一个"写了没人读"。`lane`/`idx` 仍在用(选中这只单位要它们)。
func _build_equip_cells(box: Control, y: float, eqs: Array, slots: int, x_start: float = -1.0) -> Array:
	var worn: Array = []   # 返回: 已装那几格在卡内的矩形 + 真实下标(拖动源用)
	## ★28 → 40: 手机触控下限是 44pt(81px), 而卡片右列只有约 134px 宽 ——
	##   3 格要到 81px 得 243px, **版式里塞不下**(加高卡片又会撞到下面的背包区)。
	##   所以取版式允许的最大值: 3×40 + 2×4 = 128 ≤ 134。从 15pt 提到 22pt。
	## ★★2026-09-30 量过一遍确认 40 就是**版式硬上限**, 不是"懒得再挤":
	##   右列可用宽 = UBOX_W(244) − rx(110) − 右留白 6 = 128 ⇒ (128 − 2×gap 4) / 3 = 40.0 整。
	##   往外要地方也没有: 单位区右沿 804 / 羁绊列左沿 828(只剩 24px, 三格分不到 8px 一格);
	##   竖向两条战场带 88..236 与 234..382 已经**互相压了 2px**, 而背包标题在 386 ——
	##   UBOX_H 一个像素都涨不了。所以**格子不可能达到 44pt**, 只能让它**不再是靶子**:
	## ★★★点格子 = 选中这只单位(非破坏性), 不再是"就地卸掉那一件"。
	##   由来(台账 ⑭「整屏最小的靶子恰好是主操作」): 21.7pt 的格子、相邻只隔 2.2pt,
	##   而它原来直接执行**卸下** —— 手指偏一格就卸错一件, 且卸下没有任何提示。
	##   现在三个格子映射到**同一个**动作(选中这只单位) ⇒ 偏一格也不会做错事,
	##   而真正的卸下走底部那条 81px(44pt) 的「卸下」键。
	##   ⚠ 不是改成 `MOUSE_FILTER_IGNORE` 透传给框 —— 框 body 的语义是
	##     "已有选中时 = **互换分路**", 那样点第二只龟身上的装备会把两只龟换路(更坏)。
	##     所以显式接一个"只选中、不换路"的处理。
	## ★2026-10-22 竖卡版式: 三格贴在卡的下沿(EQ_CELL / EQ_GAP), 压在木框上像嵌进去的宝石。
	var cw := EQ_CELL
	var gap := EQ_GAP
	var team_full: bool = not GameState.team_has_equip_room()   # 全队预算是否已用尽(空格样式据此区分)
	## ★三格只放【占装备位】的件; 羁绊赠送件(圣光护盾)另挂徽章 —— 它不是装备位。
	##   `i` 记录每格对应 eqs 里的真实下标: 卸下要按真实下标走, 不能按格号。
	##   ★分摊口径走 `_split_equips()`(与底部 44pt 卸下条同一份), 不在这里再写一遍。
	var _sp: Array = _split_equips(eqs)
	var wear: Array = _sp[0]    # [{i(真实下标), it}]
	var grants: Array = _sp[1]  # 同上, 羁绊赠送件
	var total := float(slots) * cw + maxf(0.0, float(slots - 1)) * gap
	var x0 := x_start if x_start >= 0.0 else (CARD_W / 2.0 - total / 2.0)   # x_start≥0=横排卡片右列左对齐, 否则居中
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
			csb.bg_color = Color("#0b0705"); csb.border_color = Color("#2a2018")
		else:
			## 托条上的凹槽: 深色底 + 木色边(2026-10-22, 原来半透明黑块压在木框上像破洞)
			csb.bg_color = Color("#1a100a"); csb.border_color = Color("#6b4a2a")
		csb.set_border_width_all(1); csb.set_corner_radius_all(3)
		## ⚠★2026-08-18 这里**试过换金属槽框, 实拍对比后退回了**, 原因记下免得再试:
		##   格子只有约 26px, 而槽框原生 57×57 —— 四角铆钉在这个尺寸下**吃掉大半格子**,
		##   图标被挤没空间; 更要命的是**费用色从"整块实心"退化成"一圈细边"**,
		##   而那块实心色本身就是信息(一眼分得出 2/3/4/5 费)。改完信息强度反而掉一档。
		##   ⇒ **贴图框有它的最小可用尺寸**; 小于它就该保持纯色块, 不是硬套。
		##   (背包大格 88px、卡片 88px 都够, 只有这 18 个迷你格不够。)
		cell.add_theme_stylebox_override("panel", csb)
		cell.position = Vector2(x0 + float(ci) * (cw + gap), y); cell.size = Vector2(cw, cw)
		if filled:
			var eid2 := str(((wear[ci] as Dictionary)["it"] as Dictionary).get("id", ""))
			var edef2: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid2, {})
			## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(EquipIcon.make 的 else 分支)
##   ⚠"060~095 有 36 件没配图"这句已作废: 实测 95 件装备**全部**有 img 且图都在盘上
##     ⇒ emoji 兜底一次都不会触发(留着仍对, 但别当"有 36 件没图"的证据)。
			var ic2 := EquipIcon.make(edef2, Vector2(cw - 2, cw - 2), true)
			ic2.position = Vector2(1, 1)
			cell.add_child(ic2)
			_worn_stars(cell, int(((wear[ci] as Dictionary)["it"] as Dictionary).get("star", 1)), cw)
			worn.append({"rect": Rect2(cell.position, cell.size), "cell": int((wear[ci] as Dictionary)["i"]),
				"it": (wear[ci] as Dictionary)["it"]})
		if _sel_bench >= 0:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 装备模式: 透传→点框body装上
		elif filled:
			## ★★2026-10-21 手机版: 格子不再是单独的靶子(40px = 22pt, 低于 44pt), 点它 = 点这张单位卡。
			##   规则只剩一条, 与「?」里写的一致: 点单位 = 选中(底部列出它的装备、可卸下), 依次点两个单位 = 交换位置。
			##   (原来格子单独接「只选中不换路」: 一张卡上两种手势、靶子只有 22pt —— 手指偏一点就是另一个动作。)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空格透传
			cell.tooltip_text = ("全队装备已达上限 %d/%d" % [
				GameState.team_equipped_count(), GameState.team_equip_cap()]) if team_full \
				else "空槽位"
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
		## ★2026-10-22 竖卡: 托盘只放得下三格 ⇒ 赠送徽章叠在立绘窗右上角, 往左排(它本来就不是装备位)。
		gcell.position = Vector2(CARD_W - CARD_BORDER - 2.0 - float(gi + 1) * (gw + 4.0) + 4.0, CARD_BORDER + 2.0)
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
		## 原文"羁绊赠送(不占装备位) · 盾羁绊掉档时自动收回": 括号注解 + "掉档"这种表述。
		gcell.tooltip_text = "%s · 盾羁绊赠送 · 不占装备位 · 羁绊失效时移除" % str(gdef.get("name", ""))
		## ★2026-10-21: 徽章同装备格, 不单独当靶子(30px = 16pt) —— 点它 = 点这张单位卡。
		gcell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(gcell)
	return worn


## 卡上那一格的星级: 左下角 1~3 颗小星(2026-10-22 对照参考: 云顶 / 循环勇者都把等级标在格子角上,
##   原来卡上只看得出费用色和图标, 看不出是几星)。星 = 商店合成指示星的第 0 帧(同一套 UI 语言), 不压图标中间。
const WORN_STAR_PX := 16.0
const WORN_STAR_STEP := 11.0
func _worn_stars(cell: Control, star: int, cw: float) -> void:
	var at := AtlasTexture.new()
	at.atlas = WORN_STAR_TEX
	at.region = Rect2(0, 0, 32, 32)
	for k in range(clampi(star, 1, 3)):
		var s := TextureRect.new()
		s.name = "WornStar"
		s.texture = at
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.position = Vector2(1.0 + float(k) * WORN_STAR_STEP, cw - WORN_STAR_PX - 1.0)
		s.size = Vector2(WORN_STAR_PX, WORN_STAR_PX)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(s)


## 卸下统领第 cell_idx 件装备 → 回背包.
func _dl_first_minion_idx(lane: String) -> int:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	for i in range(arr.size()):
		if arr[i] is Dictionary and str(arr[i].get("kind", "")) == "minion":
			return i
	return -1

## 点布阵框: 选了装备+点统领=装备; 否则 无选中→选中, 已选中→与该框互换分路(跨/同路都行), 再点自己=取消.
func _dl_click(lane: String, idx: int) -> void:
	_sel_worn = {}
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	var unit: Dictionary = arr[idx] if idx < arr.size() and arr[idx] is Dictionary else {}
	if _sel_bench >= 0 and str(unit.get("kind", "")) in ["leader", "minion"]:
		_equip_bench_to_unit(lane, idx, _sel_bench)
		return
	if _dl_sel.is_empty():
		_dl_sel = {"lane": lane, "idx": idx}
		_rebuild(); return
	var sl := str(_dl_sel.get("lane", "")); var si := int(_dl_sel.get("idx", -1))
	_dl_sel = {}
	if sl == lane and si == idx:
		_rebuild(); return
	_swap_units(sl, si, lane, idx)

## 两张单位卡互换(跨路 / 同路都行)—— 点两张与拖一张到另一张共用这一个。
func _swap_units(sl: String, si: int, lane: String, idx: int) -> void:
	if sl == lane and si == idx:
		_rebuild(); return
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(sl) or not a.has(lane) or si < 0 or si >= (a[sl] as Array).size() or idx < 0 or idx >= (a[lane] as Array).size():
		_rebuild(); return
	var tmp = a[sl][si]
	a[sl][si] = a[lane][idx]
	a[lane][idx] = tmp
	GameState.dual_lineup = a
	GameState.save()
	_rebuild()


## 背包第 bidx 件装到这只单位 —— 点选(点卡 → 点龟)与拖拽落下共用这一个(2026-10-22)。
func _equip_bench_to_unit(lane: String, idx: int, bidx: int) -> void:
	var arr: Array = GameState.get_dual_lineup().get(lane, [])
	var unit: Dictionary = arr[idx] if idx >= 0 and idx < arr.size() and arr[idx] is Dictionary else {}
	var n0: int = int(GameState.team_equipped_count())
	if str(unit.get("kind", "")) == "leader":
		_inv_ops._equip_to(str(unit.get("id", "")), bidx)
	elif str(unit.get("kind", "")) == "minion":
		_inv_ops._equip_minion(lane, idx, bidx)
	else:
		return
	if int(GameState.team_equipped_count()) > n0:
		_tut_notify("item_equipped")   # 教程「点击一只龟装上」: 真装上了才前进


## 拖动结束(落下或放弃): 收掉高亮; 拖动中被推迟的重建这时补上。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag.on_drag_end()
		if _rebuild_pending:
			_rebuild()




## 底部操作条这一刻画不画(临时等级器 / 糖果罐 / 有装备的单位)。
func _op_bar_shows() -> bool:
	if _sel_jar and GameState.has_candy_jar():
		return true
	return _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size() \
		and str((GameState.persistent_bench[_sel_bench] as Dictionary).get("kind", "")) == "item"


## 点单位卡上已装的那一件: 再点同一件 = 收起。
func _on_worn_click(lane: String, idx: int, cell: int) -> void:
	if str(_sel_worn.get("lane", "")) == lane and int(_sel_worn.get("idx", -1)) == idx and int(_sel_worn.get("cell", -1)) == cell:
		_sel_worn = {}
	else:
		_sel_worn = {"lane": lane, "idx": idx, "cell": cell}
	_sel_bench = -1
	_sel_jar = false
	_dl_sel = {}
	_rebuild()


## 收掉所有选中(点空白处)。
func _clear_selection() -> void:
	if _sel_bench < 0 and _sel_worn.is_empty() and _dl_sel.is_empty() and not _sel_jar:
		return
	_sel_bench = -1
	_sel_worn = {}
	_dl_sel = {}
	_sel_jar = false
	_rebuild()


## 说明小卡: 背包里选中的装备 / 单位卡上点的那一件。
func _open_item_card() -> void:
	_ui_layer = self
	var it: Dictionary = {}
	var worn := false
	if _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size():
		it = GameState.persistent_bench[_sel_bench]
		if str(it.get("kind", "")) == "item":
			return                         # 临时等级器走底部操作条
	elif not _sel_worn.is_empty():
		var u: Dictionary = {}
		var arr: Array = GameState.get_dual_lineup().get(str(_sel_worn.get("lane", "")), [])
		var ui: int = int(_sel_worn.get("idx", -1))
		if ui >= 0 and ui < arr.size() and arr[ui] is Dictionary:
			u = arr[ui]
		var eqs: Array = _unit_equips(u)
		var ci: int = int(_sel_worn.get("cell", -1))
		if ci < 0 or ci >= eqs.size():
			_sel_worn = {}
			return
		it = eqs[ci]
		worn = true
	else:
		return
	if _insp_anchor == null or not is_instance_valid(_insp_anchor):
		return
	var eid := str(it.get("id", ""))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	if edef.is_empty():
		return
	var star: int = int(it.get("star", 1))
	var col: Color = _cost_color(int(edef.get("cost", 1)))
	var stats: Array = []
	for kv in EquipStats.stat_lines(eid, star):
		stats.append(InspectCard.eq_stat_row(kv, Color("#f4ead8")))
	if stats.is_empty():
		stats.append(["", "无属性加成", Color("#a89c86")])
	var img := str(edef.get("img", ""))
	var tp := str(Phase2Types.type_of(eid))
	var tag_bb := "[color=#ffd93d]%s[/color]  %d费" % ["★".repeat(clampi(star, 1, 3)), int(edef.get("cost", 1))]
	if tp != "":
		tag_bb += "  ·  " + Phase2Types.icon_bb(tp, 16) + " " + tp
	var body := SkillText.highlight_star(SkillText.equip_brief_bb(edef, MIN_FONT_PX), star) \
		if str(edef.get("effectBrief", "")) != "" else "（无主动效果）"
	var lv: Dictionary = _insp.open(("worn:" if worn else "bench:") + eid, null, {
		"icon": ("res://assets/sprites/" + img) if img.ends_with(".png") else "",
		"title": str(edef.get("name", eid)), "title_col": col,
		"icon_border": col, "frame_col": col,
		"tag_bb": tag_bb, "tag_col": Color("#e8dcc4"),
		"stats": stats,
		"body": body, "body_px": MIN_FONT_PX,
		"width": ITEM_CARD_W, "min_px": MIN_FONT_PX,
	})
	if not lv.has("vbox"):
		return
	(_insp.card as Control).name = "ItemInspectCard"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	(lv["vbox"] as VBoxContainer).add_child(row)
	if worn:
		var un := Button.new(); un.name = "UnequipBtn"; un.text = "卸下"
		_card_btn(un)
		var w0: Dictionary = _sel_worn.duplicate()
		un.pressed.connect(func() -> void:
			var arr2: Array = GameState.get_dual_lineup().get(str(w0["lane"]), [])
			var u2: Dictionary = arr2[int(w0["idx"])] if int(w0["idx"]) < arr2.size() else {}
			_sel_worn = {}
			if str(u2.get("kind", "")) == "leader":
				_inv_ops._unequip_at(str(u2.get("id", "")), int(w0["cell"]))
			else:
				_inv_ops._unequip_minion_at(str(w0["lane"]), int(w0["idx"]), int(w0["cell"])))
		row.add_child(un)
	else:
		var sell := Button.new(); sell.name = "SellBtn"
		sell.text = "卖出 +%d" % _inv_ops._sell_value(it)
		_card_btn(sell)
		sell.pressed.connect(func() -> void: _inv_ops._sell_selected())
		row.add_child(sell)
	var det := Button.new(); det.name = DETAIL_BTN_NAME; det.text = "详情"
	_card_btn(det)
	var it0: Dictionary = it
	det.pressed.connect(func() -> void: _show_equip_detail(it0))
	row.add_child(det)


## 龟卡属性小卡的六行: [键, 名字, 图标]。名字与装备属性行同一套叫法(EquipStats.lines_of)。
const UNIT_STAT_ROWS := [["hp", "最大生命值", "hp"], ["atk", "攻击力", "atk"], ["def", "护甲", "def"],
	["mr", "魔抗", "mr"], ["crit", "暴击率", "crit"], ["critDmg", "暴击伤害", "crit-dmg"]]
const STAT_EQUIP_COL := Color("#7fe39a")   # 装备加的那部分(与「选了装备时可装」的绿描边同色)


## 点龟卡 = 这只的六项基础属性(用户 2026-10-22「点击龟得有龟的属性显示吧，基本的就好，生命值，攻击力，护甲魔抗，暴击和暴击伤害」;
##   「因为是被装备施加了属性的」⇒ 大字 = 本体 + 身上装备, 后面绿字 = 其中装备加的)。取数走 UnitStatPreview, 与战斗同一套。
## ★这张卡顶替了原来右栏那条「卸下装备」操作条: 卸装备 = 点卡上那一件(说明小卡里的「卸下」), 或拖回背包。
func _open_unit_card() -> void:
	if _sel_bench >= 0 or not _sel_worn.is_empty() or _sel_jar:
		return
	var u: Dictionary = _sel_unit()
	if u.is_empty() or _insp_anchor == null or not is_instance_valid(_insp_anchor):
		return
	var kind := str(u.get("kind", ""))
	var pid := str(u.get("id", ""))
	if kind == "leader" and pid == "":
		return                               # 占位统领: 还没有龟
	var lane := str(_dl_sel.get("lane", ""))
	var idx := int(_dl_sel.get("idx", -1))
	var eqs: Array = _unit_equips(u)
	var pv: Dictionary
	var title: String
	var tag: String
	var icon: String
	if kind == "leader":
		var lv: int = GameState.battle_level_for(pid)
		pv = UnitStatPreview.leader(pid, lv, eqs)
		title = str((DataRegistry.pet_by_id.get(pid, {}) as Dictionary).get("name", pid))
		tag = "Lv %d" % lv
		icon = "res://assets/sprites/avatars/%s.png" % pid
	else:
		## 精英 / 等级与战斗同一个判据: 这一路没有统领时第一个小将是精英; 等级 = 赛季等级 + 这一格的临时等级器
		var lead_n := 0
		for x in (GameState.get_dual_lineup().get(lane, []) as Array):
			if x is Dictionary and str(x.get("kind", "")) == "leader":
				lead_n += 1
		var elite: bool = lead_n == 0 and _dl_first_minion_idx(lane) == idx
		var front: bool = str(u.get("role", "front")) == "front"
		var mlv: int = GameState.battle_level_for("") + int(u.get("temp_lv", 0))
		pv = UnitStatPreview.minion(elite, front, mlv, eqs)
		title = "精英小将" if elite else "小将"
		tag = "Lv %d  ·  %s" % [mlv, "精英" if elite else ("前排" if front else "后排")]
		icon = "res://assets/sprites/%s" % Phase2Minion.minion_img(elite, not front)
	_ui_layer = self
	var live: Dictionary = _insp.open("unit:%s:%d" % [lane, idx], null, {
		"icon": icon if ResourceLoader.exists(icon) else "",
		"title": title, "tag": tag, "tag_col": Color("#e8dcc4"),
		"width": ITEM_CARD_W, "min_px": MIN_FONT_PX,
	})
	if not live.has("vbox"):
		return
	(_insp.card as Control).name = "UnitInspectCard"
	var vb: VBoxContainer = live["vbox"]
	var rule := ColorRect.new()
	rule.color = InspectCard.C_LINE
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(rule)
	var grid := GridContainer.new()
	grid.name = "UnitStatGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(grid)
	var base: Dictionary = pv["base"]
	var add: Dictionary = pv["equip"]
	for row in UNIT_STAT_ROWS:
		var k := str(row[0])
		var pct: bool = k == "crit" or k == "critDmg"
		var mul: float = 100.0 if pct else 1.0
		var tot: int = roundi((float(base[k]) + float(add[k])) * mul)
		var plus: int = roundi(float(add[k]) * mul)
		var nb := HBoxContainer.new()
		nb.add_theme_constant_override("separation", 6)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ip := "res://assets/sprites/stats/%s-icon.png" % str(row[2])
		if ResourceLoader.exists(ip):
			var tr := TextureRect.new()
			tr.texture = load(ip)
			tr.modulate = SkillText.stat_icon_color_of(ip)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.custom_minimum_size = Vector2(24, 24)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nb.add_child(tr)
		nb.add_child(_stat_lbl(str(row[1]), InspectCard.C_BODY))
		grid.add_child(nb)
		var vl := _stat_lbl(("%d%%" % tot) if pct else str(tot), InspectCard.C_TITLE)
		vl.name = "Val_" + k
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(vl)
		var el := _stat_lbl((("+%d%%" % plus) if pct else ("+%d" % plus)) if plus != 0 else "", STAT_EQUIP_COL)
		el.name = "Eq_" + k
		grid.add_child(el)


func _stat_lbl(t: String, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", MIN_FONT_PX)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 说明小卡卡底的动作钮: 木色直角, 高 81(= 44pt 触控下限)—— 与商店说明卡同一个样子。
func _card_btn(b: Button) -> void:
	b.custom_minimum_size = Vector2(0, 81)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	for st in [["normal", "#6a3f1c", "#d89a48"], ["hover", "#7d4b22", "#f0b45a"], ["pressed", "#4e2d12", "#d89a48"],
			["disabled", "#3a2a1c", "#7a6040"]]:
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(st[1]); sb.border_color = Color(st[2])
		sb.set_border_width_all(3); sb.set_corner_radius_all(0)
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_color_override("font_color", Color("#fff1d6"))
	b.add_theme_color_override("font_hover_color", Color("#fff8e8"))


const ITEM_CARD_W := 340.0


## InspectCard 定位回调: 背包里的一件 = 背包那一栏里贴着它(下方放不下就上方); 龟卡 / 卡上的一件 = 背包那一栏、与卡顶齐平。
func inspect_card_pos(card: Control, h: float) -> Vector2:
	var w: float = card.size.x
	var par := card.get_parent() as CanvasItem
	var inv: Transform2D = par.get_global_transform().affine_inverse() if par != null else Transform2D.IDENTITY
	var top := 80.0
	var bot: float = _bottom_limit() - 6.0
	if _insp_anchor == null or not is_instance_valid(_insp_anchor):
		return Vector2(BENCH_X, BENCH_TOP)
	var r: Rect2 = _insp_anchor.get_global_rect()
	var p0: Vector2 = inv * r.position
	var p1: Vector2 = inv * r.end
	var x: float
	var y: float
	if p0.x >= BENCH_X - 4.0:
		x = clampf((p0.x + p1.x) * 0.5 - w * 0.5, BENCH_X, 1252.0 - w)
		y = p1.y + 8.0
		if y + h > bot:
			y = p0.y - 8.0 - h
	else:
		## 卡上的(点龟卡 / 点卡上那一件): 一律放进右边背包那一栏 —— 贴在卡右边会盖住隔壁的卡,
		##   而选中一只之后下一步常常就是去点另一只(交换)或往另一只身上拖(2026-10-22)。
		x = BENCH_X
		y = p0.y
	y = clampf(y, top, maxf(top, bot - h))
	return Vector2(x, y)


## 背包区现在要不要滚动(内容比可视区高)—— 不用滚时拖拽不必让着滚动。
func bench_scrolls() -> bool:
	if _bench_area == null or not is_instance_valid(_bench_area) or _bench_area.get_child_count() == 0:
		return false
	var c: Control = _bench_area.get_child(0) as Control
	return c != null and c.custom_minimum_size.y > _bench_area.size.y + 1.0


## 拖动时跟手那张卡的底 = 背包格同一套(商店说明卡的费用档框)。
func card_style(cost: int, lifted: bool) -> StyleBox:
	var st := StyleBoxTexture.new()
	st.texture = ITEM_CARD_SEL if lifted else ITEM_CARD_TEX[clampi(cost, 1, 5) - 1]
	st.set_texture_margin_all(ITEM_CARD_MARGIN)
	return st


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
	## ★★2026-08-17 换成与战斗面板同一张九宫格槽框。
	##   由来: 把判据推到 7 个屏幕实测 —— 背包 44 个网页盒、54 个圆角盒、**零张九宫格**,
	##   而战斗面板是全游戏唯一一个金属框界面 ⇒ 从战斗切回背包像两个游戏。
	##   这是我通宵那轮制造的新不一致, 现在收口。
	##   ★状态色走 `modulate_color`(黄=选中/紫=道具), **不是各做一张图** ——
	##     否则"按状态配色"这套信息会被贴图吃掉(战斗面板状态签那次的教训)。
	##   ★空槽压暗: 战斗面板里"空槽画灰框"曾是**死代码**(兜底 StyleBoxFlat 永远不被用),
	##     实拍空满槽一模一样。这里一次做对。
	##   ★贴图缺失时原样退回上面这份 StyleBoxFlat, 不崩不空白。
	var _empty: bool = bg.a < 0.30
	box.add_theme_stylebox_override("panel",
		UISkin.slot(sb, UISkin.tint_of(border), _empty))
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
	var bw := 720.0; var bh := 460.0   # 2026-10-22 八条 ⇒ 460; 2026-10-19 多一行「站位」: 306 → 330; 2026-10-21 字 15 → 20、键 81 高 ⇒ 720×500
	var box := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	## ★2026-08-18 弹窗换面板框(同上: 一块区域)。
	box.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, sb))
	box.position = Vector2(_vw / 2.0 - bw / 2.0, maxf(96.0, minf(H / 2.0 - bh / 2.0, _popup_bottom() - bh))); box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(box)
	var ttl := Label.new(); ttl.text = "阵容说明"
	ttl.add_theme_font_size_override("font_size", 22); ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 30); box.add_child(ttl)
	var body := Label.new()
	## ★原文每条都是「X = Y」的对照表式("点两个单位 = 互换它们的战场 / 位置"),
	##   那是策划表的写法。改成直接对玩家说"你点了会怎样" —— 同样是六条, 一条不少。
	## ★2026-10-22 背包重做: 常驻图例(统领 / 小将 / 前排后排)撤了, 那一句挪进来当第一条;
	##   点单位改成看属性, 卸装备改点卡上那一件(右栏卸下条已撤)。
	body.text = "· 统领：本大轮出战龟　小将：补位单位\n· 上路、下路独立作战\n· 依次点击两个单位，或把一个拖到另一个上：交换位置\n· 小将卡上【前排 / 后排】：切换近战 / 远程\n· 右上「站位」：拖动单位设置开战站位\n· 点击单位：查看属性；点击单位身上的装备：卸下\n· 选择背包装备后点击单位，或拖动装备到单位：装备\n· 3 件同名同星装备自动合成升星"
	body.add_theme_font_size_override("font_size", MIN_FONT_PX); body.add_theme_color_override("font_color", Color("#cfe0ef"))
	body.position = Vector2(24, 58); body.size = Vector2(bw - 48, bh - 58 - 100); body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(body)
	var ok := Button.new(); ok.text = "知道了"; ok.add_theme_font_size_override("font_size", MIN_FONT_PX)
	ok.position = Vector2(bw / 2.0 - 80, bh - 94); ok.size = Vector2(160, 81)
	UISkin.button(ok, Color("#ffd93d"))
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)


# ─── 下部: 装备背包 (大改: 可滑动列表·铺满宽·大格; 说明移到底部操作条) ───
## 背包滚动区的底边: 选中了东西(底部操作条会画出来) → 让到操作条上方; 否则铺到屏底。
## ★这是"操作条画不画"的**同一个判据**, 不是各写一份 —— 两边口径不同就会重叠或留缝。
func _bench_bottom() -> float:
	## 只有临时等级器还走底部操作条(装备是说明小卡, 不占地方)
	var sel_eq: bool = _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size() \
		and str((GameState.persistent_bench[_sel_bench] as Dictionary).get("kind", "")) == "item"
	var sel_jar: bool = _sel_jar and GameState.has_candy_jar()
	## 没选中东西时下面是羁绊条(syn_top() 起) ⇒ 背包铺到它上面为止
	return (_op_bar_y() - 8.0) if (sel_eq or sel_jar) else syn_top() - 8.0


## ★2026-10-21 手机优先: 本页能用到的最底沿(设计框坐标)。
##   = 视口底(4:3 时设计框顶对齐, 下面多出 240 归背包网格) - 底部横条(SafeArea 下内缩) - 6。
##   原来写死 H - 8 = 712: iPhone 上最后一排格子压进底部横条(实拍 10-20)。
func _bottom_limit() -> float:
	var vs: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var host_h: float = size.y if (size.x >= W and size.y >= 360.0) else vs.y
	var ins: Vector4 = SafeArea.insets(vs)
	return maxf(H, host_h) - ins.w - 6.0


## 弹框(阵容说明 / 装备详情 / 羁绊详情)的底沿上限: 不过底部横条, 也不出 720 设计框
##   (4:3 上设计框顶对齐、下面多出来的那段只给背包网格, 弹框仍按设计框居中)。
func _popup_bottom() -> float:
	return minf(H - 8.0, _bottom_limit())


## 羁绊条顶沿: 与底部操作条一样贴着 _bottom_limit 往上长(块高 = SYN_BOTTOM - SYN_TOP + 2)。
##   ★2026-10-22 原来写死 SYN_TOP 600 ⇒ iPhone 上那排羁绊块底沿 713, 压进底部横条(安全区下沿 682);
##   iPad(4:3)上背包止于 592、下面空 240。贴底之后两边都对, 16:9 仍是 600。
func syn_top() -> float:
	return _bottom_limit() - (SYN_BOTTOM - SYN_TOP + 2.0)


## 底部操作条顶沿: 贴着 _bottom_limit 往上长。
func _op_bar_y() -> float:
	return _bottom_limit() - OP_BAR_H


## UIFrame 顶对齐(见 UIFrame._center): 4:3 多出来的高度全给下面的背包网格。
func ui_frame_top_align() -> bool:
	return true


func _sel_unit() -> Dictionary:
	if _sel_bench >= 0 or _dl_sel.is_empty():
		return {}
	if _sel_jar and GameState.has_candy_jar():
		return {}                        # 糖果罐那条操作栏优先(与 _build_op_bar 同序)
	var arr: Array = GameState.get_dual_lineup().get(str(_dl_sel.get("lane", "")), [])
	var i := int(_dl_sel.get("idx", -1))
	if i < 0 or i >= arr.size() or not (arr[i] is Dictionary):
		return {}
	return arr[i]


func _build_bench() -> void:
	var hdr := Label.new()
	## ★半角/全角混用清掉: 原文是「装备背包　(可上下滑动)」—— 全角空格 + 半角括号,
	##   而同一屏的空背包提示用的是全角括号。滑动提示改成右端独立小字, 不再塞在标题里。
	hdr.text = "装备背包"
	hdr.add_theme_font_size_override("font_size", 22)
	hdr.add_theme_color_override("font_color", Color("#9fb6c9"))
	hdr.position = Vector2(BENCH_X, BENCH_HDR_Y); hdr.size = Vector2(300, 30)
	add_child(hdr)
	## ★2026-10-22 用户「下面还有是什么鬼」: 原来标题右边一行「▼ 下面还有」—— 最后一排格子露半截本身就说明能往下滑, 去掉。
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
	var gx := BENCH_X
	var top := BENCH_TOP
	var pitch := BENCH_PITCH
	var scroll_w := 1252.0 - gx
	## ★背包高度跟着底部操作条走(用户 2026-08-15「备战席挤在下面」):
	##   没选中任何东西时**底下那 90px 是空的** —— 操作条只在选中后才画。
	##   于是没选中 = 背包铺到 712(能看见 3 行), 选中 = 让位给操作条(2 行 + 第 3 行露头)。
	##   ⇒ 屏幕上不再有"留给某个偶尔出现的东西"的常驻空白。
	var scroll_h := _bench_bottom() - top
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(gx, top)
	scroll.custom_minimum_size = Vector2(scroll_w, scroll_h); scroll.size = Vector2(scroll_w, scroll_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 隐滚动条·保留拖动滚动(用户2026-07-19·跟选龟一致)
	add_child(scroll)
	_bench_area = scroll
	_drag.wire_bench_area(scroll)   # 已装的拖回背包区 = 卸下
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS   # 触屏拖动透传→ScrollContainer 滚动
	scroll.add_child(content)
	var per_row := maxi(4, int((scroll_w + 6.0) / (SLOT + 6.0)))   # 格间至少 6: 右栏 513 宽排 4 列
	## ★格间距把剩余宽度【均分】而不是固定 8 —— 固定 8 时 11 列只排到 x=1176,
	##   右边白留 64px 一条空列(实测), 看着像"最后一格坏了"。
	var cpitch := (scroll_w - SLOT) / float(maxi(1, per_row - 1)) if per_row > 1 else SLOT
	## ★★2026-10-21 按【实际件数】排格子, 不再「至少铺满可视区」: 原来 22 件也画满 33 格,
	##   空背包画 22 个空格 —— 一屏空框读起来像「容量 33」, 而背包本来就没有容量上限。
	##   现在 = 有几件画几格(空格不画: 背包没有容量上限, 空格只会被读成「容量」), 一件没有就只写「背包为空」。
	var used_rows := int(ceil(float(bench.size()) / float(per_row)))
	var total_cells := bench.size()
	content.custom_minimum_size = Vector2(scroll_w - 4.0, maxf(44.0, float(used_rows) * pitch))
	## ★★★渲染索引与【数据索引】必须分开 —— 血泪(2026-08-14 自己刚踩):
	##   糖果罐是插在最前面的**合成条目**, 它不在 `GameState.persistent_bench` 里。
	##   而 `_equip_cell(it, idx, ...)` 的 idx 会被 `_on_bench_click` 存成 `_sel_bench`,
	##   `_sel_bench` 又是**直接索引 `persistent_bench`** 的(equip_ops.gd:137 / 本文件 615)。
	##   ⇒ 若把渲染下标当数据下标传, 每件装备偏 1, **点第 1 件会装备/卖掉第 2 件** —— 坏存档。
	##   所以: `i` 只管摆位置, `bidx` 才是喂给 `_equip_cell` 的真实背包下标(合成条目不占号)。
	var i := 0
	## 先配好每格的【数据下标】(糖果罐 = -1, 不占号) —— 点 / 拖 / 卖都按数据下标走。
	var order: Array = []
	var _bi := 0
	for it in bench:
		var synth0: bool = str(it.get("kind", "")) == "candy_jar"
		order.append({"it": it, "bidx": -1 if synth0 else _bi})
		if not synth0:
			_bi += 1
	for e in order:
		var it: Dictionary = e["it"]
		var bidx: int = int(e["bidx"])
		var col := i % per_row
		var row := i / per_row
		var synth: bool = bidx < 0
		var _cell: Control = _equip_cell(it, bidx,
			Vector2(float(col) * cpitch, float(row) * pitch))
		content.add_child(_cell)
		if bidx == 0:
			_tut_first_item = _cell      # 教程手势指针「点击一件装备」指的就是它(数据下标 0 = 刚买的那件)
		i += 1
	while i < total_cells:
		var col2 := i % per_row
		var row2 := i / per_row
		content.add_child(_empty_bench_cell(Vector2(float(col2) * cpitch, float(row2) * pitch)))
		i += 1
	if bench.is_empty():
		var hint := Label.new()
		hint.text = "背包为空"
		hint.add_theme_font_size_override("font_size", MIN_FONT_PX); hint.add_theme_color_override("font_color", Color("#7f8fa0"))
		## 2026-10-21: 空背包不再画空格 ⇒ 提示放在格子区第一行的位置。
		hint.position = Vector2(6, 8); hint.size = Vector2(600, 28); hint.mouse_filter = Control.MOUSE_FILTER_IGNORE; content.add_child(hint)

# ─── 底部选中操作条 (大改: 替代满屏文字说明; 选中装备才显名/效果/卖出/取消) ───
func _build_op_bar() -> void:
	## ★选中糖果罐 ⇒ 同一条操作栏, 把"卖出"换成"打碎"(用户 2026-08-14)。
	##   走同一个 bar 而不是另起一条 —— 用户要的就是"和装备一样"。
	if _sel_jar and GameState.has_candy_jar():
		_build_jar_op_bar()
		return
	if _sel_bench < 0 or _sel_bench >= GameState.persistent_bench.size():
		return   # 无选中装备 → 不显底部操作条
	if str((GameState.persistent_bench[_sel_bench] as Dictionary).get("kind", "")) != "item":
		return   # ★2026-10-22 装备改成贴着那一格弹说明小卡(_open_item_card), 不再画底部操作条(原那行"3件同款合成"已收进"?"帮助·用户2026-07-19)
	var by := _op_bar_y()
	var bar := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#101c2a"); sb.border_color = Color("#2a3a4e")
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	## ★2026-08-18 底部操作条换面板框 —— 它是"一块区域"不是格子, 与战斗面板描述浮层同类。
	bar.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, sb))
	var bw := OPS_W
	bar.position = Vector2(OPS_X, by); bar.size = Vector2(bw, OP_BAR_H); add_child(bar)
	if _sel_bench >= 0 and _sel_bench < GameState.persistent_bench.size():
		var sit: Dictionary = GameState.persistent_bench[_sel_bench]
		if str(sit.get("kind", "")) == "item":
			## ★原文「🔼 临时等级器已选 → 点一只 龟 / 小将,本大轮永久 +1 级」: "已选"+双箭头
			##   是状态机说明书的口气。换成直接跟玩家说下一步做什么。
			## ★2026-09-28 去掉句首的 🔼 —— 纯装饰(这条提示自己把话说全了),
			##   而它左边那张卡上就画着临时等级器。
			var l := Label.new(); l.text = "选择单位 · 本大轮等级 +1"
			l.add_theme_font_size_override("font_size", MIN_FONT_PX); l.add_theme_color_override("font_color", Color("#e6d8ff"))
			l.position = Vector2(16, 36); l.size = Vector2(bw - 32, 28); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
		else:
			var sdef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(sit.get("id", "")), {})
			# ★装备文案按玩家当前星级高亮(2026-07-22): 三元组 a/b/c 里这一档亮、另两档暗。
			#   只在渲染时变换, 数据格式一个字不动 —— tooltip_number_audit 靠那个正则对账。
			var _star: int = int(sit.get("star", 1))
			## ── 第一行: 这件东西【是什么】。名字白、星级金、费用/类型灰蓝 ——
			##    2026-08-15 之前这里名字/星级/费用/操作提示/效果正文**全是同一个黄色 14 号字**
			##    连成一条 369 字的长句, 眼睛找不到任何边界。
			var head := RichTextLabel.new()
			head.bbcode_enabled = true
			head.fit_content = false
			head.scroll_active = false
			head.add_theme_font_size_override("normal_font_size", MIN_FONT_PX)
			head.add_theme_font_size_override("bold_font_size", MIN_FONT_PX)
			var _tname := str(Phase2Types.type_of(str(sit.get("id", ""))))
			head.text = "[b][color=#ffffff]%s[/color][/b]   [color=#ffd93d]%s[/color]   [color=#8fa6bb]%d费%s[/color]" % [
				str(sdef.get("name", "")), "★".repeat(maxi(1, _star)), int(sdef.get("cost", 1)),
				("  ·  " + _tname) if _tname != "" else ""]   # 类型名本身(剑), 不加「系」—— 与羁绊列 / 商店同一个名字
			head.position = Vector2(16, 8); head.size = Vector2(bw - 32 - 200, 30)   # 右边 260 留给「查看更多」
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(head)
			## ── 第二段: 效果正文。正文色改成浅蓝灰(#cfe0ef), 只留【数值】是黄的 ——
			##    这样一眼能扫到数字, 而不是满屏一片黄。
			var l := RichTextLabel.new()
			l.bbcode_enabled = true
			## ★★2026-08-15 第三版。前两版的历史:
			##   ① `fit_content=true` 固定 48 高 → 文字**静默截断**;
			##   ② 改成 `scroll_active=true` 让它可滚 —— 但正文 `mouse_filter=IGNORE`,
			##      滚轮事件根本进不来, 手机上只剩一根 5px 宽的滚动条可拖 ⇒ 等于没解决。
			##   ③ 现在: 底栏只放**摘要 2 行**, 全文交给【细看】弹框(手机也能看),
			##      并且**被裁了就明说还有几行** —— 判据是 RichTextLabel 自己的
			##      `get_line_count()` / `get_visible_line_count()`(产品自己的账),
			##      不是我按"每行几个字"估的。
			##   ⚠ 别再改回 `fit_content = true`: 那会让"内容高 ≤ 框高"恒成立, 检查永远不触发。
			l.fit_content = false
			l.scroll_active = false
			## 背包格子里的一行说明 —— 用一句话简述(原文中位 129 字, 这里放不下)。
			var plain := SkillText.equip_brief_bb(sdef, OP_BODY_FS)   # ★_bb: 上色+内联属性图标(2026-10-01 P2)
			l.text = SkillText.highlight_star(plain, _star)
			l.add_theme_font_size_override("normal_font_size", OP_BODY_FS)
			l.add_theme_color_override("default_color", Color("#cfe0ef"))
			var body_w := bw - 32.0
			## 框高 = 【整数】行 —— 用字体自己报的行高算, 不是拍一个 40。
			##   拍 40 的后果实拍看到了: 第 3 行被从中间切开半条, 比直接不显示还难看。
			var lh := _op_line_h(l)
			l.position = Vector2(16, 38); l.size = Vector2(body_w, lh * float(OP_BODY_ROWS))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE; bar.add_child(l)
			_op_body = l
			_op_more = null
			## 放不下就明说还有几行 —— 数字**同步算出来**, 见 _op_total_lines 的长注释。
			var total := _op_total_lines(l, plain, body_w)
			if total > OP_BODY_ROWS:
				var more := Label.new()
				## "还有 N 行"是排版口径, 玩家关心的是**还有没说完的事**。
				more.text = "查看更多（%d 行）" % (total - OP_BODY_ROWS)
				more.add_theme_font_size_override("font_size", MIN_FONT_PX)
				more.add_theme_color_override("font_color", Color("#7fb0d8"))
				more.position = Vector2(bw - 16.0 - 200.0, 8); more.size = Vector2(200, 28)
				more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				more.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bar.add_child(more)
				_op_more = more
			## ── 【细看】: 属性 + 效果全文。原来这些只在 tooltip 里,
			##    而手机上没有 hover ⇒ 手机玩家**一辈子看不到装备加了多少属性**。
			## ★★2026-09-28 两处一起改:
			##   · 「详情」→「细看」: 「详情」是后台/表单里的栏目名(detail), 而这颗键
			##     要说的是玩家的动作。战斗信息框那边已经是「点开细看」(battle_hud.gd),
			##     同一个动作全游戏一个词。
			##   · tooltip 整条删掉: 原文「看这件的完整属性和效果」是**字段名罗列**,
			##     而且**手机没有 hover** —— 这条提示在真实玩家那里等于不存在,
			##     键上「细看」两个字已经把它说完了。
			##   ★节点名走常量 `DETAIL_BTN_NAME`: 门禁按名字 + 按下去真开框来判,
			##     不拿"按钮上写着哪两个字"当尺子(memory [[fb-tests-pin-screen-words]])。
			var det := Button.new(); det.text = "详情"
			det.name = DETAIL_BTN_NAME
			det.add_theme_font_size_override("font_size", MIN_FONT_PX)
			det.position = Vector2(16, OP_BAR_H - 91.0); det.size = Vector2(96, 81)
			## ★★底栏这三个键原来全是 Godot 默认皮(圆角纯色) ——
			##   `verify_click_targets_alive` 自己写着「圆角纯色是最直接的『没游戏味』」,
			##   它们只是因为底栏得先选中一件装备才建、静止态的屏上不在场, 才一直没被数到。
			##   ⚠ `UISkin.button` 按**按钮真实尺寸**挑大框/小签 ⇒ 必须在 `size` 之后调。
			UISkin.button(det, Color("#9fb6c9"))
			det.pressed.connect(func(): _show_equip_detail(sit)); bar.add_child(det)
			var sv := _inv_ops._sell_value(sit)
			## ★★2026-09-28「💰 卖出 +N💠」两个 emoji 都拆掉:
			##   · 💰(钱袋)是**装饰** —— 「卖出」两个字已经说完了。直接去掉, 不拿别的图顶替。
			##   · 💠 是**深海币本身**, 不能只删 —— 删了就只剩一个光秃秃的数字, 玩家看不出
			##     卖的是哪种钱。换成商店/顶栏用的同一张 `ic-deepsea.png`(这屏顶栏就挂着它),
			##     靠右放 ⇒ 读作「卖出 +3 ◎」, 与 `ShopScene._coin_button_icon` 同一个摆法。
			##   ⚠ 币图是 64×64, 按钮只有 38 高 ⇒ 这里是**本轮唯一一处非 1x**(2:1 折半)。
			##     真正干净的做法是要一张 32×32 的深海币 —— 已登记进缺口表。
			var sell := Button.new(); sell.text = "卖出 +%d" % sv
			sell.icon = COIN_TEX
			sell.expand_icon = true
			sell.add_theme_constant_override("icon_max_width", ICON_PX)
			sell.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sell.add_theme_font_size_override("font_size", MIN_FONT_PX)
			sell.position = Vector2(122, OP_BAR_H - 91.0); sell.size = Vector2(170, 81)
			UISkin.button(sell, Color("#ffd93d"))
			sell.pressed.connect(_inv_ops._sell_selected); bar.add_child(sell)
		var cancel := Button.new(); cancel.text = "取消"
		cancel.add_theme_font_size_override("font_size", MIN_FONT_PX)
		cancel.position = Vector2(bw - 108, OP_BAR_H - 91.0); cancel.size = Vector2(92, 81)
		UISkin.button(cancel, Color("#9fb6c9"))
		cancel.pressed.connect(func(): _sel_bench = -1; _rebuild()); bar.add_child(cancel)


## 一段文字在给定宽度/字号下【排出来有多高】。
## ★同 `_op_total_lines`: 用字体引擎同步量, 不依赖任何帧/绘制状态, 也不是按字数估。
##   门禁可以拿它的返回值当判据(函数返回值, 不是我插的标记)。
func _measured_text_h(plain: String, width: float, fs: int) -> float:
	if plain.strip_edges() == "" or width <= 0.0:
		return 0.0
	var f: Font = get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	return f.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, width, fs).y


## 一行占多高(字体高 + 行距) —— 框高按它取整数倍, 才不会把最后一行从中间切开。
func _op_line_h(l: RichTextLabel) -> float:
	var f: Font = l.get_theme_font("normal_font")
	if f == null:
		f = ThemeDB.fallback_font
	return float(f.get_height(OP_BODY_FS) + l.get_theme_constant("line_separation"))


## 这段文案在给定宽度下【一共要几行】。
##
## ★★为什么不用 `RichTextLabel.get_line_count()`(2026-08-15 实测踩过):
##   它要等控件排完版才有值, 而排版时机跟"这一帧画没画到它"绑在一起 ——
##   同一份代码, 截图那个进程里读到 3 行, 另一个进程里读到 **0 行**;
##   而且在节点刚建出来那一帧调它(哪怕 call_deferred), 它是按**还没设好的宽度**排的,
##   算出来的数**看着挺像样、其实是错的**(实拍显示"还有 3 行", 真实只多 1 行)。
##   门禁读到 0 就是恒不触发的假检查, 读到错数就是骗玩家。
## ⇒ 改用 `Font.get_multiline_string_size()`: **同步**, 给什么宽度按什么宽度排,
##   不依赖任何帧/绘制状态, 两个进程结果一致。它是字体引擎自己的排版结果,
##   不是我按"每行几个字"估的。
func _op_total_lines(l: RichTextLabel, plain: String, width: float) -> int:
	if plain.strip_edges() == "" or width <= 0.0:
		return 0
	var f: Font = l.get_theme_font("normal_font")
	if f == null:
		f = ThemeDB.fallback_font
	var fh := float(f.get_height(OP_BODY_FS))
	if fh <= 0.0:
		return 0
	## ★2026-10-21: 传进来的是 bbcode(equip_brief_bb) —— 原来连 `[color=#ffd93d]` 这些标签一起量,
	##   20 号字下一行的简述被算成 4 行、挂着「查看更多(1 行)」(实拍)。先去标签; 行内图标按一个全角字的宽算。
	var rx := RegEx.new()
	rx.compile("\\[img[^\\]]*\\][^\\[]*\\[/img\\]")
	var shown: String = rx.sub(plain, "囗", true)
	rx.compile("\\[[^\\]]*\\]")
	shown = rx.sub(shown, "", true)
	var sz: Vector2 = f.get_multiline_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, width, OP_BODY_FS)
	return int(round(sz.y / fh))


## 装备详情框: 名 / 星 / 费 / 类型 + 【属性加成】 + 【效果全文】。
## ★为什么要它: 这些内容一直只活在 tooltip 里, 而手机没有 hover ——
##   等于把"这件装备加多少属性"藏起来了(用户 2026-07-19 明确要过"必须写完整")。
##   底栏只有两行的位置, 长文案(最长 369 字)注定放不下 ⇒ 全文有个去处才叫放得下。
func _show_equip_detail(item: Dictionary) -> void:
	var eid := str(item.get("id", ""))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var star := maxi(1, int(item.get("star", 1)))
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: dim.queue_free())
	add_child(dim)
	var bbody := ""
	var rows: Array = EquipStats.stat_lines(eid, star)
	if rows.is_empty():
		bbody = "[color=#8fa6bb]无属性加成[/color]"
	else:
		var parts: Array = []
		for kv in rows:
			parts.append("[color=#9fb6c9]%s[/color]  [color=#7fe39a][b]%s[/b][/color]" % [kv[0], kv[1]])
		bbody = "  　　".join(parts)
	## 详情弹窗是"点开看全部"那一层, 给**全文**; 操作栏/tooltip 才给一句话简述。
	## ★先上色再 highlight_star: highlight_star 认的是 `数/数/数`, 而上色产出的
	##   `[img width=16 color=#xxxxxx]` 与 `res://assets/...` 里没有这个形状, 不会误伤。
	var eff := SkillText.highlight_star(SkillText.equip_full_bb(edef, DETAIL_BODY_FS), star)
	if eff.strip_edges() == "":
		## ★★2026-09-28。原文「这件没有额外效果，属性直接生效。」三个词全是规格书用语:
		##   「额外效果」是字段名、「直接生效」是实现说明, 而句尾那个句号连它的**姊妹句**
		##   (`_stat_block` 的「这件不加属性，只有效果」, 没有句号)都不一致。
		##   ⇒ 定稿成姊妹句的镜像: 不加属性/只有效果 ←→ 只加属性/不带效果。
		eff = "[color=#8fa6bb]无特殊效果[/color]"
	## ★★2026-09-28 段标题「带来的属性」→「属性」: 「带来的」是 "brought by" 的翻译腔,
	##   而商店详情面板(`ShopScene._build_stat_rows` 的「属性」标题)和图鉴
	##   (`detail_views.gd:857` 的「属性」)本来就都只写两个字 —— 同一段信息三个界面
	##   现在一个词。★下面那份【量高用的平文】必须跟着改, 否则量的高度和渲染的不是同一段字。
	var bb := "[color=#9fb6c9][b]属性[/b][/color]\n%s\n\n[color=#9fb6c9][b]效果[/b][/color]\n[color=#cfe0ef]%s[/color]" % [bbody, eff]
	## 框高按【字体自己排出来的高度】算, 不是按"每行几个字"估 ——
	## 估的那一版实拍下面空了 160px(估多了), 而估少了就会把文案切掉。
	## 估不准还有个更隐蔽的坏处: 每件装备的框高都对不上内容, 看起来就是"随便拍的"。
	var bw := 700.0
	var body_plain := "属性\n%s\n\n效果\n%s" % [
		("无属性加成" if rows.is_empty() else _stat_block(eid, star)),
		SkillText.equip_full(edef)]
	var bh: float = clampf(_measured_text_h(body_plain, bw - 48.0, DETAIL_BODY_FS) + 180.0,
		300.0, _popup_bottom() - 24.0)
	var box := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	## ★2026-08-18 弹窗换面板框(同上: 一块区域)。
	box.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, sb))
	box.position = Vector2(_vw / 2.0 - bw / 2.0, maxf(24.0, minf(H / 2.0 - bh / 2.0, _popup_bottom() - bh)))
	box.size = Vector2(bw, bh)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.add_child(box)
	var tname := str(Phase2Types.type_of(eid))
	var ttl := RichTextLabel.new()
	ttl.bbcode_enabled = true
	ttl.fit_content = false
	ttl.scroll_active = false
	ttl.add_theme_font_size_override("normal_font_size", 22)
	ttl.add_theme_font_size_override("bold_font_size", 22)
	ttl.text = "[b][color=#ffffff]%s[/color][/b]   [color=#ffd93d]%s[/color]   [color=#8fa6bb]%d费%s[/color]" % [
		str(edef.get("name", eid)), "★".repeat(star), int(edef.get("cost", 1)),
		("  ·  " + tname) if tname != "" else ""]
	ttl.position = Vector2(24, 18); ttl.size = Vector2(bw - 48, 34); box.add_child(ttl)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = false
	rt.scroll_active = true          # 万一还是放不下 → 能滚, 不静默吃字
	rt.add_theme_font_size_override("normal_font_size", DETAIL_BODY_FS)
	rt.add_theme_font_size_override("bold_font_size", DETAIL_BODY_FS)
	rt.position = Vector2(24, 62); rt.size = Vector2(bw - 48, bh - 62 - 100)
	rt.text = bb
	rt.name = "EquipDetailBody"
	box.add_child(rt)
	## 「关闭」是网页/工具栏的词; 本屏的阵容帮助框一直用的是「知道了」—— 统一到那一个。
	var ok := Button.new(); ok.text = "知道了"; ok.add_theme_font_size_override("font_size", MIN_FONT_PX)
	ok.position = Vector2(bw / 2.0 - 80, bh - 94); ok.size = Vector2(160, 81)
	UISkin.button(ok, Color("#ffd93d"))
	ok.pressed.connect(func(): dim.queue_free())
	box.add_child(ok)

## 糖果罐的底部操作栏 —— 与装备那条【同一个位置、同一套尺寸】, 只是把"卖出"换成"打碎"。
## ★用户 2026-08-14:「点击装备, 下面把出售和什么按钮换成打碎就好了啊」。
##   照做: 不另起弹窗、不另起面板 —— 选中可撤销, 误触点一下再点"取消"即可。
func _build_jar_op_bar() -> void:
	var by := _op_bar_y()
	var bar := Panel.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("#1c1226"); sb.border_color = Color("#e79bd6")
	sb.set_border_width_all(2); sb.set_corner_radius_all(8)
	## ★★2026-09-28 换九宫格金属框 —— **这是本屏最后一个真·圆角盒**。
	##   隔壁 `_build_op_bar`(装备那条操作栏, 同一个位置同一套尺寸)2026-08-18 就换过了,
	##   而它这个双胞胎漏了 ⇒ 选装备时底栏是金属框、选糖果罐时同一块地方变回圆角网页盒。
	##   ★为什么一直没被门禁数到: 这条栏只在【选中糖果罐】之后才建,
	##     `verify_ui_consistency` / `_probe_webbox` 量的是静止态的屏, 那时它不在场。
	##     (memory [[fb-gate-subject-never-constructed]]: 判据没错, 被测对象不在场。)
	##   ★糖果粉那道描边不丢: 走 `UISkin.tint_of` 把它变成框的 modulate ——
	##     一张中性金属框 modulate 出"这是糖果罐那条栏", 而不是各做一张图。
	var jtex := UISkin.nine("panel-frame.png", 20, sb)
	if jtex is StyleBoxTexture:
		(jtex as StyleBoxTexture).modulate_color = UISkin.tint_of(sb.border_color)
	bar.add_theme_stylebox_override("panel", jtex)
	var bw := OPS_W
	bar.position = Vector2(OPS_X, by); bar.size = Vector2(bw, OP_BAR_H); add_child(bar)
	## ★★2026-08-15 修 off-by-one: `candy_jar_tier()` 返回的**已经是 1~6**
	##   (`verify_candy_jar` 逐区间焊死, `break_candy_jar` 也按 `[tier-1]` 取奖励)。
	##   这里原来又 `tier + 1` ⇒ 卡面/底栏写"第 3 档", 而同一行右边给的奖励是
	##   `candy_jar_tier_preview(tier)` = **第 2 档**的 —— 数字和奖励自相矛盾;
	##   攒满 30 颗时还会显示【第 7 档】, 而总共只有 6 档。
	var tier: int = GameState.candy_jar_tier()
	var l := Label.new()
	## ★原文「🍬 糖果罐(第 N 档) —— 打碎后本大轮消失。当前档位奖励: X」三样毛病:
	##   括号计数「(第 N 档)」、"当前档位奖励:" 的 label: value 句式、以及「档位」这个词本身
	##   ——「档位」正是 `verify_inventory_layout` ㉖ 明令界面上不许出现的字(它只是因为
	##   这条栏不在静止态的屏上才没被数到)。
	## ⚠ 但「第 %d 档」和 `candy_jar_tier_preview` 的原文**必须留在这句里**:
	##   ㉑ 逐区间拿它们对账 off-by-one(7 组 count→tier), 少一个当场红。
	## ★2026-09-28 去掉句首的 🍬 —— 它是**纯装饰**(「糖果罐」三个字就在后面),
	##   而这一格里已经有糖果罐的像素图了。emoji 走 NotoEmoji, 与全屏像素笔触两套画法。
	l.text = "糖果罐 · 第 %d 档\n打碎可获得：%s（每大轮限 1 次）" % [
		tier, GameState.candy_jar_tier_preview(tier)]
	l.add_theme_font_size_override("font_size", MIN_FONT_PX)
	l.add_theme_color_override("font_color", Color("#f0d6ff"))
	l.position = Vector2(16, 12); l.size = Vector2(bw - 32, OP_BAR_H - 81.0 - 30.0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	## ★2026-09-28 去掉 🔨 —— 纯装饰, 「打碎」两个字已经说完了这枚键干什么。
	##   ⚠ 这一行的**源码字面**被 `tests/verify_candy_jar.gd` 钉着(它 grep 本文件源码),
	##     那条断言已同步改成按行为找这枚键。
	var smash := Button.new(); smash.text = "打碎"
	smash.add_theme_font_size_override("font_size", MIN_FONT_PX)
	smash.position = Vector2(16, OP_BAR_H - 91.0); smash.size = Vector2(170, 81)   # ★与"卖出"同一位置同一尺寸
	UISkin.button(smash, Color("#e79bd6"))
	smash.pressed.connect(func() -> void:
		_sel_jar = false
		if _inv_jar != null:
			_inv_jar._on_break_jar())
	bar.add_child(smash)
	var cancel := Button.new(); cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", MIN_FONT_PX)
	cancel.position = Vector2(bw - 108, OP_BAR_H - 91.0); cancel.size = Vector2(92, 81)
	UISkin.button(cancel, Color("#9fb6c9"))
	cancel.pressed.connect(func(): _sel_jar = false; _rebuild())
	bar.add_child(cancel)


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
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", card_style(int(edef.get("cost", 1)), sel))
	box.position = pos; box.size = Vector2(SLOT, SLOT)
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## ★走 EquipIcon: 无图时退化成 emoji 而不是空白(EquipIcon.make 的 else 分支)
##   ⚠"060~095 有 36 件没配图"这句已作废: 实测 95 件装备**全部**有 img 且图都在盘上
##     ⇒ emoji 兜底一次都不会触发(留着仍对, 但别当"有 36 件没图"的证据)。
	## ★★2026-10-21 手机版: 格子里只画【图标 + 星级】, 名字不再写在格子里。
	##   名字原来 12 号字(放不下再缩到 10 号) —— iPhone 上 1 毫米出头, 读不出来; 而 96 格放不下 20 号的 5 字名。
	##   参考里手机横屏的背包 / 商店格(Halls of Torment / Rogue Legacy / Peglin / Underlords)都是图标格,
	##   名字在选中后的说明里给 —— 本页选中后底部操作条第一行就是名字(20 号)。
	var ic2 := EquipIcon.make(edef, Vector2(100, 88))
	ic2.position = Vector2(SLOT / 2.0 - 50, 38)
	box.add_child(ic2)
	var star := int(it.get("star", 1))
	var st := Label.new()
	st.text = "★".repeat(star)
	st.add_theme_font_size_override("font_size", MIN_FONT_PX)
	st.add_theme_color_override("font_color", Color("#ffd93d"))
	st.position = Vector2(0, 4); st.size = Vector2(SLOT, 28)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(st)
	## 合成进度(2026-10-22): 同名同星已有 ≥ 2 件 ⇒ 右下角「2/3」(再来一件就合成)。数的是 GameState.copies_of,
	##   与商店「再买合成」同一个数、同一个范围(背包 + 统领 + 小将)。满星 / 不升星的件不显示。
	var _cp: int = int(GameState.copies_of(eid, star))
	if star < 3 and _cp >= 2 and not EquipPool.NO_STAR.has(eid):
		var mp := Label.new(); mp.name = "MergeProgress"
		mp.text = "%d/3" % mini(_cp, 3)
		mp.add_theme_font_size_override("font_size", MIN_FONT_PX)
		mp.add_theme_color_override("font_color", Color("#7fe39a"))
		mp.add_theme_color_override("font_outline_color", Color("#06140a")); mp.add_theme_constant_override("outline_size", 5)
		mp.position = Vector2(SLOT - 46.0, SLOT - 30.0); mp.size = Vector2(40, 26)
		mp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(mp)
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# tooltip: 名字/★/费用 + 【该星级全部属性加成】 + 效果(用户2026-07-19"背包里我要看到每件装备提供的属性, 必须写完整")
	# ★系统 tooltip 是纯文本, 会把 [color=..] 原样显示给玩家 —— 所以挂 rich_tooltip
	#   覆写 _make_custom_tooltip, 才能真的渲染出星级高亮。
	box.set_script(RichTooltip)
	## ★"(费用3)" 括号计数 + "属性加成:" / "效果:" 的 label: value 句式, 两样都换掉。
	##   小标题用的词与【细看】弹框逐字一致(那边是"属性" / "效果", 见 `_show_equip_detail`)
	##   —— 同一件东西的同一段信息, 两个入口不该有两套叫法。
	## ★★2026-10-02: 效果那段换 `_bb` 版(上色 + 内联属性图标)。
	##   这一格的 tooltip 宿主【本来就是 RichTextLabel】(上面那行 set_script),
	##   却一直喂纯文本 ⇒ 同一屏上, 底下操作栏(`equip_brief_bb`、2026-10-01 P2 改过)
	##   是彩色带图标的, 而鼠标悬在格子上弹出来的是一片白字。两个入口两套长相。
	## ★`highlight_star` 认的是 `数/数/数`, 上色产出的 `[img width=15 color=#xxxxxx]`
	##   里没有这个形状, 不会误伤 —— 与 `_show_equip_detail` 里那次同一条理由。
	box.tooltip_text = "[b]%s[/b]  ★%d  %d费\n\n属性\n%s\n\n效果\n%s" % [
		str(edef.get("name", eid)), star, int(edef.get("cost", 1)),
		_stat_block(eid, star), SkillText.highlight_star(SkillText.equip_brief_bb(edef, 13) if str(edef.get("effectBrief", "")) != "" else "（无主动效果）", star)]
	_wire_bench_tap(box, idx)
	_drag.wire_bench_source(box, idx, it)
	if sel:
		_insp_anchor = box
	return box


# 背包格点选: 透传拖动给 ScrollContainer(可滑动) + 松开位移小才算点选(滑动不误选).
# ★仅认 mouse: 触屏由 emulate_mouse_from_touch(默认开) 自动转 mouse → 若同时收 touch 会【双触发】, 而 _on_bench_click 是 toggle → 选中瞬间又被切回=装不上(用户2026-07-18"背包怎么装装备"). 只认mouse则每次点选恰一次.
## 多行属性块(tooltip 用): 每行 "· 攻击力  +20"; 无属性的装备明说, 别留空
func _stat_block(eid: String, star: int) -> String:
	var rows: Array = EquipStats.stat_lines(eid, star)
	if rows.is_empty():
		## ★★这一句的定稿在这里(2026-09-28)。原文「（本件不提供属性加成，只有效果）」是公文体,
		##   而 `ShopScene._build_stat_rows` **有一句一模一样的** —— 同一句话出两个版本比都不改更糟
		##   (玩家会以为商店和背包说的不是一回事)。⇒ 定稿为下面这一句, 商店那边同步到同一句。
		##   本屏另外两处(`_show_equip_detail` 的渲染文与量高用的平文)也用同一句, 三处逐字一致。
		return "  无属性加成"
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
				_press_ms = Time.get_ticks_msec()
			elif ev.position.distance_to(_press_pos) < 16.0:
				_on_bench_click(idx))

# ─── 交互: 点背包装备选中 → 点龟装上 (再点已选=取消; 点龟身无选中=卸最后一件回背包) ───
func _on_bench_click(idx: int) -> void:
	_sel_worn = {}
	_dl_sel = {}
	_sel_jar = false                       # 选装备 ⇒ 取消糖果罐选中(互斥, 底部只有一条操作栏)
	_sel_bench = -1 if _sel_bench == idx else idx
	_rebuild()
	if _sel_bench >= 0:
		_tut_notify("bench_selected")      # 教程「点击一件装备」

## 选中的背包装备装到 pet_id (槽够才装).
func _item_cell(it: Dictionary, idx: int, pos: Vector2) -> Control:
	var sel := idx == _sel_bench
	var box := _slot_panel(pos, Color("#2a3a1c") if sel else Color("#26203a"), Color("#ffd93d") if sel else Color("#a98bd8"))
	var ic := Label.new()
	## ⚠★★2026-09-28 **这一个 emoji 是有意留下的**, 登记在
	##   `tests/verify_no_emoji_icons.gd` 的存量台账里(带理由), 不是漏改:
	##   它是【临时等级器】这件东西在背包里的**唯一视觉** —— 删掉就是一张空卡,
	##   而仓库里没有任何一张"升级/等级"的像素图标(已 grep: level/upgrade/arrow 全无)。
	##   素材铁律是"新内容一律新素材", 所以**不拿语义不符的图顶替**。
	##   ⇒ 等新图标画好再换; 在那之前台账钉着它, 不许再多一个。
	ic.text = "🔼"
	ic.add_theme_font_size_override("font_size", 40)
	ic.position = Vector2(0, 18); ic.size = Vector2(SLOT, 56)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ic)
	## 名字不写在格子里(同装备格, 2026-10-21): 选中后底部操作条那一行说它是什么。
	for ch in box.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 原文"临时等级器 (糖果罐战利品)\n选中它 → 点一只龟统领或小将 → 该单位【本大轮】永久 +1 级 (切大轮重置)":
	## 两个括号注解 + 两个箭头 = 说明书腔。改成两句话直说。
	box.tooltip_text = "临时等级器\n指定单位本大轮等级 +1"
	_wire_bench_tap(box, idx)
	_drag.wire_bench_source(box, idx, it)
	return box


## 提示层所在的组。★`_rebuild()` 必须跳过它 —— 理由见 `_toast()` 头注。
const TOAST_GROUP := "ui_toast"
var _toast_layer: CanvasLayer = null

# 轻量提示条 (1.4s 后淡出) — 装备位满了 / 全队满了 / 临时等级器 等一次性反馈
#
# ★★★TOAST_SURVIVES(2026-09-29 查实): 原来这行是 `add_child(l)` —— 直接挂在本场景下。
#   而每一处 `host._toast(...)` 的【下一行】就是 `host._rebuild()`(见 inventory/equip_ops.gd 七处),
#   `_rebuild()` 开头把所有非浮层子节点 `visible=false; queue_free()`
#   ⇒ **提示生下来那一帧就被销毁**。实测(tests/_probe_toast_killed.gd):
#       触发前 0 个 → 同帧立刻查 1 个 → +1 帧起 0 个 … +6 帧 0 个
#   七条提示玩家一条都没看见过 —— 这就是「装到上限点了没反应」的真根因(提示其实全写好了)。
#
# ★为什么用 CanvasLayer, 而不是"给 Label 加个组让 _rebuild 跳过":
#   跳过只解决【活下来】, 解决不了【看得见】—— `_rebuild()` 随后建的 `bg` 是满铺不透明的
#   ColorRect, 而它比提示【后】加 ⇒ 提示被压在背景底下(节点还在、visible 还是 true, 只是没人看得见,
#   判据照样报绿)。CanvasLayer 的 `layer` 与子节点顺序无关, 结构上保证画在内容之上。
#   layer 取 6000 < 教学浮层的 7000 ⇒ 教学「下一站」按钮仍在最上。
# ★为什么不改 equip_ops 的七处调用顺序(先 _rebuild 再 _toast): 那是"每处都得记得"的修法,
#   下一个人照现有写法再加一条就又没了。这里收口一次, 七处与将来的第八处一起管。
func _toast(msg: String) -> void:
	if _toast_layer == null or not is_instance_valid(_toast_layer):
		_toast_layer = CanvasLayer.new()
		_toast_layer.name = "ToastLayer"
		_toast_layer.layer = 6000
		_toast_layer.add_to_group(TOAST_GROUP)
		add_child(_toast_layer)
	## 上一条还没淡完就来新的 → 把旧的收掉, 否则两行金字叠在同一处成一团糊。
	## ★用 `queue_free` 不用 `free`: 本函数是从 `gui_input` 信号里被调到的(点格子 → 装备),
	##   在信号里即时 free 会崩(与 `_rebuild()` 里同一条理由)。
	for old_t in _toast_layer.get_children():
		(old_t as CanvasItem).visible = false
		old_t.queue_free()
	var l := Label.new()
	l.name = "Toast"   # ★verify_ui_consistency._is_toast 认这个名字(浮层与内容重叠是设计如此)
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("#ffd93d"))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 5)   # 描边: 提示浮在内容上, 没描边会糊进背景
	## ★按【真实视口宽】居中, 不按设计宽 W: 提示层是 CanvasLayer, 坐标就是屏幕坐标,
	##   而宽屏视口可达 1680 —— 用 W/2 会把它顶到左边去(UIFrame 头注记的那个指纹)。
	var vw: float = maxf(W, get_viewport_rect().size.x)
	l.position = Vector2(vw / 2.0 - 300.0, 96.0); l.size = Vector2(600, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(l)
	var tw := create_tween()
	## ★2026-10-04 台账 S18: 1.4+0.6 秒读不完「这只已装满 3 件 · 先点它卸下一件」这种两截的提示,
	##   玩家报的是「什么都不发生」。与主菜单 `_toast` 同一组停留(那边台账 ④ 已从 1.9 秒加到 3.2 秒)。
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _tut_on() -> bool:
	var td = get_node_or_null("/root/TutorialDirector")
	return td != null and td.is_active()


func _tut_notify(ev: String) -> void:
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null:
		td.notify(ev)


## 教程文案占位(TutorialGuide.fill_text): {item} = 背包第一件(= 教程里刚买、合成的那件, 锚点 first_item 指的同一件)的名字。
func tut_text_vars() -> Dictionary:
	var nm := ""
	for it in GameState.persistent_bench:
		if it is Dictionary and GameState.is_equip_item(it):
			var d: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((it as Dictionary).get("id", "")), {})
			nm = str(d.get("name", ""))
			break
	return {"item": nm}


## 教程最后一步的「完成教程」钮 —— 站在返回键的位置(教程里返回键是藏起来的, 见 TopBar)。
## 点了 = TutorialDirector.end_tutorial("completed"): 与「跳过」同一个出口(需求 2)。
var _tut_finish_btn: Button = null
var _tut_first_item: Control = null
var _tut_first_leader: Control = null
const TUT_FINISH_POS := Vector2(18, 10)
const TUT_FINISH_SIZE := Vector2(176, 62)

func _build_tut_finish() -> void:
	var b := Button.new()
	b.name = "TutorialFinish"
	b.text = "完成教程"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = TUT_FINISH_SIZE
	b.size = TUT_FINISH_SIZE
	b.position = TUT_FINISH_POS
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color("#ffe9a8"))
	UISkin.button(b, Color("#ffd08a"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void:
		var td = get_node_or_null("/root/TutorialDirector")
		if td != null:
			td.notify("tutorial_finished")
			td.end_tutorial("completed"))
	add_child(b)
	_tut_finish_btn = b
	## ★「完成教程」教到最后一步(F6)才出现(分镜「按钮教到才出现」): 之前它站在左上, F2 的箭头从它正下方伸出来,
	##   读起来像在指它(10-21 录屏自评); 也不许提前点掉后面的步骤。
	b.visible = _tut_finish_shown


## 引导条每换一步调一次(TutorialGuide._render)。到 F6(finish_button)才亮出「完成教程」。
var _tut_finish_shown := false

func tut_step_shown(highlight: String) -> void:
	if highlight == "finish_button":
		_tut_finish_shown = true
		if _tut_finish_btn != null and is_instance_valid(_tut_finish_btn):
			_tut_finish_btn.visible = true


## 右上「跳过教程」的位置: 教程里藏起来的「?」那一格(顶栏右端, 已知空位; 方案书 B7)。
func _tutorial_skip_slot() -> Rect2:
	var r := Rect2(Vector2(SYN_X + SYN_W - 132.0, (TopBar.BAR_H - TopBar.TOUCH_MIN) / 2.0), Vector2(132, TopBar.TOUCH_MIN))
	r = Rect2(r.position + _frame_off(), r.size)
	## ★教程 v3: 「站位」在教程里也显示, 顶栏右侧签跟着视口右沿走 ⇒ 跳过钮紧挨在它右边(同一条右沿规则, 宽屏不叠)。
	var fb := find_child("FormationBtn", true, false) as Control
	if fb != null and fb.is_visible_in_tree():
		r.position.x = fb.get_global_rect().end.x + 8.0
	return r


## 设计框(UIFrame)的屏幕偏移 —— 本屏按 1280×720 设计坐标画, 宽屏上整体居中平移。
func _frame_off() -> Vector2:
	for c in get_children():
		if c is UIFrame and not (c as Node).is_queued_for_deletion():
			return (c as Control).global_position
	return Vector2.ZERO


## 新手引导高亮锚点。名字→屏幕矩形; 与 _build_lineup/_build_bench 同口径常量算(+ 设计框偏移)。
func _tutorial_anchor(anchor: String) -> Rect2:
	var r := Rect2()
	match anchor:
		"lanes":     # 上/下战场两条带
			r = Rect2(CARDS_X - 6.0, LANE_HDR_Y, LEFT_W + 12.0, 2.0 * ROW_PITCH)
		"backpack":  # 装备背包区
			r = Rect2(BENCH_X, BENCH_HDR_Y, 1252.0 - BENCH_X, _bench_bottom() - BENCH_HDR_Y)
		"finish_button":
			return TutorialGuide.vis_rect(_tut_finish_btn)
		"first_item":
			return TutorialGuide.vis_rect(_tut_first_item)
		"first_leader":
			return TutorialGuide.vis_rect(_tut_first_leader)
		"formation_button":   # 教程 v3: 顶栏「站位」
			return TutorialGuide.vis_rect(find_child("FormationBtn", true, false))
		"formation_field", "formation_token", "formation_done":   # 教程 v3: 站位面板里的三处
			return _formation.tut_anchor(anchor)
		_:
			return Rect2()
	return Rect2(r.position + _frame_off(), r.size)


## 糖果罐格子 —— 长得像装备卡(同一个 `_slot_panel` 尺寸与描边), 但点击是【打碎领奖】。
## ★沿用装备卡的外框而不是自画一个: 用户要的就是"以装备的形式", 视觉必须同源;
##   自画一套会又变成"背包里有两种长得不一样的东西"。
func _candy_jar_cell(it: Dictionary, pos: Vector2) -> Control:
	var tier: int = GameState.candy_jar_tier()
	var jbox := _slot_panel(pos, Color("#3a2446") if _sel_jar else Color("#2a1c36"),
		Color("#ffd93d") if _sel_jar else Color("#e79bd6"))   # 选中态: 与装备卡同一套金边
	## 原文"已攒 N 颗糖(第 M 档)…当前档位奖励: X": 括号计数 + label: value + "档位"这个词。
	jbox.tooltip_text = "糖果罐里攒了 %d 颗糖, 现在是第 %d 档
一大轮只能碎一次, 碎完就没了
现在打碎能开出 %s" % [
		int(it.get("count", 0)), tier, GameState.candy_jar_tier_preview(tier)]
	## ★★2026-09-28「🍬」→ 真像素图 `equip/equip-candy-jar.png`。
	##   **不是拿别的图顶替**: 这张图的文件名就叫 `equip-candy-jar`, 是给糖果罐画的,
	##   而且全仓 grep 下来**一处都没接线**(画完就躺着) —— 接上它正是它的用途。
	##   这一格是糖果罐在背包里的**唯一视觉**, 所以不能像别处那样"把 emoji 删掉了事"。
	## ⚠ 源图 64×64, 这一格的图标带只有 36 高 ⇒ 按 **0.5x(32×32)** 画。
	##   这是本屏唯一的非 1x, 而 0.5 是**整比折半**(一个输出像素 = 一个源像素, NEAREST
	##   不插值), 放大看仍是干净的像素画 —— 已逐像素比过 64/32 两版。
	##   想要真 1x 需要一张原生 32×32 的糖果罐, 已登记进缺口表。
	var jic := TextureRect.new()
	jic.texture = load(CANDY_JAR_ICON)
	jic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	jic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	jic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## 2026-10-21: 手机版格子不写名字 ⇒ 图标画原生 1x(64×64), 不再折半。
	jic.position = Vector2(SLOT / 2.0 - 48, 8); jic.size = Vector2(96, 96)
	jic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jbox.add_child(jic)
	var jnm := Label.new()
	## ★★"×N" 是**误导**: `break_candy_jar` 设的是 `candy_jar_broken = true` ——
	##   **一大轮只能碎一次**; `candy_jar_count` 是累积糖数、**决定档位**, 不是"N 个罐子"。
	##   写成 ×N 会被读成一叠可碎 N 次的消耗品。改成显示【档位】, 糖数放 tooltip。
	## 2026-10-21: 格子里只留档位(20 号字), 「糖果罐」三个字在选中后的底部操作条里。
	jnm.text = "%d 档" % GameState.candy_jar_tier()
	jnm.name = "CellName"
	jnm.add_theme_font_size_override("font_size", MIN_FONT_PX)
	jnm.add_theme_color_override("font_color", Color("#e79bd6"))
	jnm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jnm.position = Vector2(0, SLOT - 34.0); jnm.size = Vector2(SLOT, 28)
	jnm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jbox.add_child(jnm)
	## ★★★点它 = 【选中】, 和点装备完全一样(用户 2026-08-14:
	##   「点击装备, 下面把出售和什么按钮换成打碎就好了啊」)。
	##   ⇒ 复用 `_wire_bench_tap`: 它本来就处理"滑列表 vs 点一下"(位移<16px 才算点),
	##     所以手机上滑动不会误触; 选中本身可撤销, 也就不需要确认弹窗。
	##   ★用 `_sel_jar` 单独标记, **不占 `_sel_bench`** —— 后者直接索引
	##     `GameState.persistent_bench`, 而糖果罐不在里面(占了就是索引错位)。
	jbox.mouse_filter = Control.MOUSE_FILTER_PASS
	jbox.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			_press_pos = ev.position
			return
		if ev.position.distance_to(_press_pos) >= 16.0:
			return                                   # 位移过大 = 在滑列表, 不是点它
		_sel_jar = not _sel_jar
		_sel_bench = -1                              # 选糖果罐 ⇒ 取消装备选中(互斥)
		_rebuild())
	return jbox
