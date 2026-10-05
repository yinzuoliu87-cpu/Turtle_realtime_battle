extends Control

## MainMenuScene — 主菜单, 1:1 PoC MainMenuScene.ts 布局.
## 设计台 1280×720. 标题menu-title图@(240,130) / 左栏btn-frame按钮(360×87)中心x=240 /
## 右上货币芯片(裸图标+数字) + 左列 4 颗方键(背包/商店/图鉴/排行榜).

## 商店按钮的文字。★它同时是【商店锁的判别式】(下面 `str(s[0]) == SHOP_LABEL`) ——
##   所以必须是一个常量, 不能两处各写一遍字面量: 改了按钮名字而漏改判别式,
##   锁会【静默失效】(没打过第一场的玩家直接进得去商店), 不报错、没人看得出来。
##   同一形状 2026-08-26 在 `Backend._is_self_ghost` 上踩过一次真的, 那次的代价是
##   "接上服务器后永远匹配不到别人"。
const SHOP_LABEL := "商店"

## A5: 配额上限从常量取, 不写死 —— 写死就是把参数抄两份。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
## D-1: 服务状态三态(没配 / 正常 / 维护中 / 连不上)。维护态要盖掉赛程显示, 见 `_week_close_block`。
const _SB := preload("res://scripts/net/supabase.gd")
const _BE := preload("res://scripts/net/backend.gd")
const _RU := preload("res://scripts/systems/replay/replay_uploader.gd")
## 拆墙之后那句非阻塞提示要把人送到【绑定屏】去, 而那一屏的代码在设置页那侧
## ⇒ 跨场景传一个 static 布尔 `open_bind_on_entry`。
## ★不在这边再建一份绑定 UI: 抄一份就要把昵称那一行和验证码状态机抄第二遍
##   (memory `fb-hand-rolled-copies-drift`)。
const _SET := preload("res://scripts/scenes/SettingsScene.gd")
## 冠军/亚军/四强头衔的发放链住在对阵图那侧(`record_progress_from`), 主菜单只喂 feed 调它。
const _BMS := preload("res://scripts/scenes/BracketMapScene.gd")

const W := 1280
const H := 720
const WALL := 16

## ══════════════════════════════════════════════════════════════════════
##  版面 —— 2026-10-05 第三轮「手游大厅骨架」
## ══════════════════════════════════════════════════════════════════════
## 用户追问「额，你参考了谁的」「别再瞎看了好吗」「你自己找」「去网上搜」之后,
## 参考固定成 6 张**手游主大厅**截图(docs/plans/ref/20261005-手游大厅/, 出处 sources.tsv):
##   荒野乱斗 ×2 / 英雄联盟手游 / 使命召唤手游 / 刀塔霸业 / 皇室战争(竖屏, 只看布局逻辑)。
## 只取**布局骨架**, 不学任何一家的画风与形状(皮仍是本作的像素木头 + 黄铜):
##   左上   玩家信息卡(等级徽章 + 昵称 #ID + 经验条 + 大轮)   ← 荒野乱斗/使命召唤/英雄联盟手游 三家同位
##   右上   两种货币一行 + ? / ⚙ 小图标键                              ← 五张横屏全在右上
##   左侧   一列方形图标键(图标在上、字在下, 带红点槽)                 ← 荒野乱斗两张
##   中间   擂台与两只角斗龟(不许压)                                   ← 每一张中间都是角色本身
##   右下   开始战斗 = 最大、全屏唯一实心亮色                           ← 荒野乱斗/使命召唤/刀塔霸业
##   它左边 「今天」模式卡(赛制 + 一句规则 + 倒计时), 点开看整周赛程 ← 荒野乱斗那块活动卡
## ★为什么 Logo 挪到顶部居中、缩到一半: 左上角在三张同构参考里都是「你是谁」那一格,
##   Logo 占着它就只能把玩家信息挤成散字(上一版的样子)。顶部居中在荒野乱斗/使命召唤里
##   也只放小件, 而它正好压在擂台的拱顶上方, 像挂在场馆门楣上的招牌 —— 不跟任何入口抢位置。

## ── 左上: 玩家信息卡(2026-10-05 第四轮: 照皇室战争/英雄联盟手游的标准写法) ──
## 用户:「按标准写法怎么写啊，商业游戏怎么写啊」「头像？我们有头像吗？」
## ⇒ 卡里只放四样东西, 每样一件事:
##   [大等级徽章]  昵称 #ID
##                [===经验条 x/y===]
##                第 N 大轮
##   · 等级徽章 = 大轮等级(season_level)。占原来头像那一格 —— 本作**没有头像系统**, 人人同一个龟壳 = 占位, 删了。
##     徽章紧贴经验条左端, 读成皇室战争那种「2 [42/50]」。
##   · ID 紧跟昵称、小号冷灰、不带「ID」二字(皇室战争 #2PP 那种写法)。
##   · 战绩行删了(整卡点进战绩页; 左列也不再单设「战绩」键)。
##   · 命与本周场次挪到开始战斗正上方(荒野乱斗 PLAY 上面那条计数), 周六/周日的读数进模式卡。
const LEFT_W := 340.0                       # 玩家卡文字栏宽(上限)
const CARD_POS := Vector2(16.0, 6.0)
const CARD_TEXT_X := 104.0                  # 文字栏左沿 = 等级徽章右边
const CARD_H := 130.0                       # = card.png 高, 竖向 1:1(木面 16..111, 底边铜线在 112 以下)
const CARD_PAD_R := 20.0                    # 文字栏右边到卡右沿(右端铜钉 + 描边余量)
const CARD_TAG_GAP := 8.0                   # 昵称与 #ID 之间
const CARD_NAME := "PlayerCard"
const LV_BADGE_NAME := "LevelBadge"         # 大等级徽章(menu/hud/lvbadge.png, 黄铜盾)
const LV_TEXT_NAME := "LevelNum"            # 徽章上的等级数字
const LV_BADGE_SIZE := Vector2(68.0, 76.0)  # lvbadge.png 原尺寸 1:1
const LV_BADGE_POS := Vector2(20.0, 26.0)   # 卡内: 左端木面竖向居中(26..102)
const LV_FONT := 34
const CARD_L0_Y := 14.0                     # 昵称 + #ID: 22 号字墨迹 ~18..41
const CARD_L0_FONT := 22
const CARD_TAG_FONT := 17
const XP_BAR_NAME := "XpBar"                # 经验条(TextureProgressBar, value/max = season_xp/xp_to_next)
const XP_TEXT_NAME := "XpText"              # 条上的「x/y」/「满级」
const XP_Y := 50.0
const XP_H := 26.0
const XP_MIN_W := 220.0
const XP_FONT := 17
const XP_MAX_TEXT := "满级"
const SEASON_LINE_NAME := "SeasonLine"      # 「第 N 大轮」小字一行(经验条下面)
const SEASON_Y := 82.0                      # 17 号字框 82..107, 墨迹 ~86..103(< 112 铜线)
const SEASON_FONT := 17

## ── 开始战斗正上方: 今天在动的两个数(荒野乱斗 PLAY 上面那条计数) ──
## ★只在吃命/吃配额的日子建(= `_phase_status_line()` 返回空串的那几天);
##   周六/周日这两个数整天不动, 摆着只会误导 —— 那两天的读数进模式卡。
const TODAY_COUNTER_NAME := "TodayCounter"
const COUNTER_H := 32.0
const COUNTER_GAP := 6.0                    # 计数条与开始战斗之间
const COUNTER_FONT := 18
const COUNTER_PAD := 14.0
const SOLID_OUTLINE := 6

## ── 左侧: 一列方形图标键 ──
## ★88 不是 81: 触摸线 81(=44pt), 图标 44 + 字 20 + 上下留白要装进去; 4 × 88 + 3 × 8 = 376 ⇒ 144..520,
##   上面是玩家卡(底 136), 下面空着 —— 左下角正是擂台阴影最深处, 不压任何东西。
const SQ := 88.0
const SQ_GAP := 8.0
const SQ_X := 16.0
const SQ_Y0 := 144.0
const SQ_ICON := 44.0
const SQ_FONT := 19
const SQ_NAME_PREFIX := "Sq_"               # 每颗方键的节点名 = 前缀 + 入口名(门禁按名字找, 不按下标)
const BADGE_NAME := "Badge"                 # 红点槽(默认藏着, 有事时由入口自己点亮)
const LOCK_REASON_NAME := "LockReason"      # 商店锁的短理由(方键右边常驻一行)

## ── 右下: 开始战斗 + 模式卡 + 训龟大师 ──
## ★主 CTA 440×120: 木框保留(R2), 框里那块面换成**全屏唯一的饱和亮黄**(menu/hud/cta-face.png)。
##   比例 3.7:1 —— frame-rect 原件 4.1:1, 压得再方就会把四角铜钉压扁。底沿 696: 下面 24px 留给版本号。
const HERO_SIZE := Vector2(480.0, 124.0)
const HERO_POS := Vector2(W - WALL - 480.0, 568.0)    # 784..1264 × 568..692(下面 28px 给版本号, 整行在屏内)
const HERO_FACE_INSET := Vector2(17.0, 18.0)           # frame-rect 木框边在 480×124 下的实宽(原件 24px × 0.72 / × 0.77)
const HERO_FACE_NAME := "HeroFace"
## ★返工(照荒野乱斗 PLAY 旁那块活动卡): 与开始战斗**同底沿、高度接近、间距 12** ⇒ 读成一组。
##   两只角斗龟的脚原来落在 y=608, 卡顶要到 584 ⇒ 生成器把龟的脚底线 FOOT_Y 151 → 144(抬 28px),
##   龟仍完整露出(verify_mainmenu_layout ⑮e 量真框)。
const MODE_SIZE := Vector2(320.0, 108.0)
const MODE_POS := Vector2(HERO_POS.x - 12.0 - 320.0, HERO_POS.y + HERO_SIZE.y - 108.0)   # 452..772 × 584..692
const MODE_CARD_NAME := "ModeCard"
const MODE_TITLE_FONT := 30                  # 今天的赛制(≥26)
const MODE_RULE_FONT := 17                   # 一句规矩(≥17)
const MODE_CD_FONT := 19                     # 倒计时(单独一行、亮色)
## 训龟大师: 明显比主 CTA 小一档、换一种皮(铁箍木板), 贴在主 CTA 正上方、右沿同轴。
## ★宽 280 不是 240: 铁箍木板两端的箍在 240 宽下压到字(verify_ui_consistency「文字压边带」实测 +14)。
const TRAINER_SIZE := Vector2(280.0, 82.0)   # ★82 不是 78: 触摸线 81 视口像素(=44pt)
const TRAINER_POS := Vector2(W - WALL - 280.0, HERO_POS.y - 8.0 - 82.0)
## 有计数条的日子, 训龟大师让到计数条上面(训龟大师 / 计数条 / 开始战斗 三层同一条右栏)。
const TRAINER_POS_UP := Vector2(TRAINER_POS.x, HERO_POS.y - COUNTER_GAP - COUNTER_H - 8.0 - 82.0)
const RIGHT_EDGE := float(W - WALL)          # 右栏共用右沿: 货币/?⚙/训龟大师/开始战斗

## ── 右上: 货币一行 + ? / ⚙ 小图标键 ──
const CHIP_W := 160.0                                  # 货币牌宽(高 56, 外框仍按 85 排位)
const ICON_TAP := 81.0                                 # ? / ⚙ 的点击区(触摸线)
const ICON_VIS := 54.0                                 # ? / ⚙ 看得见的那块方框(原来 82, 用户「太大」)

## ── 本周赛程: 收进模式卡后面的弹层 ──
## ★赛程条组件原样复用(七格 + 收盘块 + 周六/周日的门), 只是从贴底常驻挪进弹层。
const WEEK_POPUP_NAME := "WeekPopup"
const POP_CY := 360.0                       # 条子竖向中心(条高随内容 81..95, resized 时重算顶沿)
const STRIP_H := 68.0
const STRIP_W := 884.0
## ★★★今天那一格的上下留白(九宫格亮牌的内边距)。这个数字是**量出来的**:
##   两行字实测共 **45px** ⇒ 格高 = 9 + 45 + 9 = **63**, 字块居中后距边带内沿还剩 **2px**
##   ⇒ 「文字压边带」那条棘轮(主菜单基线 2, 只降不升)不会涨。改小了字就骑在铜边上。
const STRIP_TODAY_PAD := 9.0
## 赛程条的皮与字(2026-10-05 UI 重做)。★七格**同一套**字色 —— 今天只靠铜边框 + 「今」字区分。
const STRIP_TEX := "strip-plank.png"
const STRIP_TODAY_TEX := "brass-frame.png"
const STRIP_DAY_FONT := 19
const STRIP_PHASE_FONT := 17
const STRIP_DAY_COL := Color("#fff0c8")
const STRIP_PHASE_COL := Color("#f2d9a6")

## 字号层级
const FONT_HERO := 44
const FONT_BTN := 22
const ROW_H := 81.0                         # ★触摸线: 44pt = 81 视口像素(赛程条每格、门都吃它)

## 件全在 assets/sprites/menu/hud/(PixelLab 新生成, 原件 src/, 烘焙 tools/build_menu_hud.py)。
## 沿用的旧件只有: menu/frame-rect.png(主 CTA 木框, R2 拍板保留) / menu/frame-square.png(?/⚙ 方框)。
const HUD := "res://assets/sprites/menu/hud/"
const FONT_VERSION := 15

var page_box: Control       # 当前页按钮容器
var content_root: Control   # 内容层 (1280×720 设计框, 居中于真实视口); 背景另铺满全窗口
var _bg_tile: MenuArenaBackdrop   # 背景 = 擂台场景 (resize 时重新铺满)


func _ready() -> void:
	SimFinalsPilot.attach_menu(self)   # 模拟窗口周日自动驾驶(只在 SIM_AUTOPILOT 开着时; 见 autopilot_finals.gd)
	if OS.has_environment("PH_DEMO"):   # dev: 模拟大轮开局(未打第一场) → 看商店键灰锁
		GameState.season_total_battles = 0
	await get_tree().process_frame
	# 1:1 PoC: 背景铺满整个窗口(无黑边), 内容 1280×720 居中。EXPAND → 视口随窗口比例扩展(不裁不缩内容)。
	#   16:9 屏 EXPAND 不扩展 = 与旧 FIT 完全一致(无回归); 非 16:9 时背景填满、内容居中。
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await get_tree().process_frame   # 让视口按 EXPAND 重算尺寸再读
	Audio.play_bgm("menu", 1.0, 0.4)   # 1:1 PoC menu BGM volume 0.4
	_bg()                            # 背景层 → self 最底, 填满真实视口(含原黑边区)
	content_root = Control.new()     # 内容层 → 1280×720 设计框, 居中
	content_root.size = Vector2(W, H)
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	_center_content()
	## ★★★一屏只读一次钟(2026-09-29)。这一句是本屏唯一的「现在」,
	##   往下传给状态行 / 赛程条 / 入口按钮 三处。
	## ★★为什么非得这样: 探针 `tests/_probe_twoclocks.gd` 实测——`_build_page_buttons()`
	##   原来调 `GameState.ranked_quota_full()` **不带参**, 而那个函数的兜底是
	##   真实系统钟 ⇒ 它既不过 `clock_override_ts` 也不过全局缝
	##   `phase2_config.now_override_ts`。同一屏上的后果(探针原文):
	##     钉周六 ⇒ 状态行画的是「闯关赛 1-1 · 再赢 3 场晋级」(周六不吃积分赛配额),
	##     而商店那一行画的是「🔒 商店」(拿真实的周二算出来的「配额打满」),
	##     而 `_open_shop()` 自己的判据是 false ⇒ **锁画在那里, 门却是开的**。
	##   10 个构造时刻里 5 个两种写法给出不同答案(quota) / 3 个(gauntlet)。
	##   memory `fb-second-clock-drops-events`。
	## ★两个 override 都是 0 时行为**逐字节不变**(玩家路径一字未动)。
	var paint_ts: int = _now_ts()
	_title()
	_right_column(paint_ts)
	## ★★D-3: 建服务端身份。**必须在登录墙之前** —— v0.19.440 上墙之后这一句原本在
	##   下面第 118 行, 而墙会在这之前 `return`, 于是**全新安装的玩家永远拿不到 token**:
	##   绑定流程(`send_code_async` 的 FLOW_BIND 分支)要求 `_token != ""`, 拿不到就回
	##   「还没登录，先联网开一局再绑」—— 而墙正好不让他开局。
	##   唯一兜底是 GameState 那个 `wait_time=20 autostart` 的保活 tick(**第一次在 t=20s**)
	##   ⇒ 装完头 20 秒游戏打不开, 且提示在教玩家做一件不可能的事。
	##   探针: `tests/_probe_wall_deadlock.gd`(墙触发 ⇒ `_auth_inflight=false`; 不触发 ⇒ true)。
	##   门禁: `verify_login_wall` ③。
	## ★这一句本身是幂等的: 已经有 account_id 且 token 没过期就什么都不做, 连节点都不建
	##   (每次开游戏都新建匿名号会把服务端刷出一堆一次性账号, Supabase 自己警告过)。
	_SB.ensure_signed_in_async()
	## ★★★补报周日决赛日: 周六晋级了但那一刻没报上去(没网 / token 刚过期 / 杀了 App)
	##   ⇒ 在这里补一次。**必须在登录墙之前** —— 与上面那句同一个理由:
	##   墙会在下面 `return`, 排在墙后面的代码对被挡住的人永远跑不到。
	##   (`ensure_signed_in_async` 就是因为排在墙后面, 让全新安装的头 20 秒打不开游戏。)
	## ★三条判据都在 `Backend.ensure_finals_entry()` 里, 主菜单不自己判 ——
	##   「该不该补报」不是主菜单的事(同 `login_wall_on` 那条纪律: 判据只留一处)。
	_BE.ensure_finals_entry()
	_BE.ensure_gauntlet_entry_snapshot()   # 周六 0-0 进场快照(每周一次; 判据全在 Backend 里)
	## ★★决赛日那一场的**结果**也要补报 —— 与上面那句同一层、同一个理由:
	##   「那一刻可能没网, 而那一刻只有一次」。漏报会让那一场只能靠 960 秒宽限兜,
	##   **可能把错的人送进下一轮**(2026-09-27)。
	_BE.retry_finals_report()
	## 回放 S2: 没回读确认传上去的周六录像补传一次(同上一句同一个理由; 判据全在 ReplayUploader 里)。
	_RU.retry()
	load("res://scripts/net/ghost_uploader.gd").retry()   # E7: 没回读确认的对手快照补传(判据全在 ghost_uploader 里)
	## ★★★ 2026-09-29 【墙拆了】—— 用户「那就不用必须绑定吧」推翻了他 2026-09-24
	##   那句「直接改为必须绑定账号吧」。`login_wall_on()` 现在**恒假**
	##   (`phase2_config.WALL_BLOCKS = false`) ⇒ 下面这三行对玩家永远不成立,
	##   第一屏就是主菜单。没绑邮箱的人改用下面 `_bind_nudge()` 那句**非阻塞**提示。
	##   ★★为什么不删这三行: 门禁那条「拦不住人」的判据要能**反向验证** ——
	##     把 `WALL_BLOCKS` 翻成 true, 墙当场回来(这三行就是它的身体),
	##     那条判据当场红、而且红的形状就是「走不过去」。删干净了就再也证不了
	##     它不是恒真式(memory `fb-gate-must-measure-requirement-not-my-hook`)。
	##   ★主菜单**不自己判**要不要挡 —— 判据只有 `phase2_config.WALL_BLOCKS` 一处,
	##     设置页也读同一个(两处各判一份必然漂)。
	##   ★★只在**自己就是 current_scene** 时才跳 —— 门禁/实拍常把主菜单当子节点挂起来
	##     量东西, 那不是玩家流程; 在那种情况下 `change_scene_to_file` 会把**宿主的**
	##     场景树换掉(本仓踩过这个)。
	if _P2C.login_wall_on(_SB.enabled(), str(GameState.account_email)) \
			and get_tree() != null and get_tree().current_scene == self:
		call_deferred("_go", "Settings")
		return
	## 本周赛程收进弹层(默认藏着), 右下角模式卡只说今天 —— 两处都吃 paint_ts, 不再自己读钟。
	_week_popup(paint_ts)
	_mode_card(paint_ts)
	## ★D-1: 去问一次服务状态(没配后端时这一句什么都不做, 连节点都不建)。
	##   答复是异步回来的 ⇒ 配一个**挂在自己身上的 Timer 子节点**轮询状态变没变,
	##   变了就重建赛程条。★不能用 `get_tree().create_timer` 接闭包 ——
	##   那种计时器活过场景释放, 响的时候去绑已释放的捕获就报错
	##   (`tools/tree_timer_audit.py` 守这条, 它推荐的修法就是 Timer 子节点)。
	_SB.fetch_status_async()
	_finals_title_pull(paint_ts)   # 决赛日: 不进对阵图也对一次冠军/四强头衔账(U1)
	## (D-3 建身份已经**挪到登录墙之前**了, 见上面那段长注释 —— 放这儿的话墙一 return
	##  就永远跑不到。这里不要再调一次: 两处各调一份, 改动时必然漂掉一处。)
	var sb_t := Timer.new()
	sb_t.wait_time = 1.0
	sb_t.autostart = true
	sb_t.timeout.connect(_sb_poll)     # 方法引用, 不是闭包
	add_child(sb_t)
	page_box = Control.new()
	content_root.add_child(page_box)
	_build_page_buttons(paint_ts)
	## ★★拆墙之后唯一还会主动找玩家的地方 —— 见 `_bind_nudge()` 头注。
	##   放在 `_build_page_buttons` **之后**: 它不进 `page_box`(那一叠的子节点数是
	##   `verify_mainmenu_layout` 的分母「左栏按钮栈 = 6 个」), 直接挂 `content_root`。
	_bind_nudge()
	content_root.move_child(_week_pop, -1)   # 弹层盖在所有入口上面(点开时才看得见)
	get_viewport().size_changed.connect(_on_menu_resize)
	# (去掉全屏询问弹窗·用户2026-07-18「去掉这个全屏提示」; _maybe_ask_fullscreen 保留未调用, 需要可在设置里切全屏)
	# ★首次打开强制新手教学(用户2026-07-23)。判据: 从没走完过教学(onboarded=false)。
	#   ONBOARD=1/0 可强制开/关, 供开发与门禁 —— 否则本机跑一次就 onboarded=true, 再也测不到。
	_maybe_first_launch_tutorial()


## 内容框居中于真实视口 (1:1 PoC FIT 居中); bg 在 self 上随视口自适应
func _center_content() -> void:
	if content_root != null:
		content_root.position = ((get_viewport_rect().size - Vector2(W, H)) / 2.0).round()


func _on_menu_resize() -> void:
	_center_content()
	var vp := get_viewport_rect().size
	if is_instance_valid(_bg_tile):
		## 擂台场景自己按 COVERED 铺满视口、居中裁边(原来平铺纹理要 +512 给漂移留量, 现在不用了)。
		_bg_tile.fit(vp)


# 不再 _exit_tree 还原 KEEP: 项目级 aspect 已是 EXPAND(全场景统一), 离场不翻转 → 场景切换丝滑。
#   各场景背景铺满已各自处理(menu平铺/select-bg/Codex全锚), 无需切回 KEEP。


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var vp := get_viewport_rect().size   # 真实视口(EXPAND 后=窗口比例); bg 全填它, 含原黑边区
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#1a3a2a")   # 深绿底 — 用 PoC 字面色值, 不四舍五入
	add_child(base)
	# ★★2026-10-05 背景换成【擂台 + 看台】(方案书 20260917-主菜单版式重做 R1 / R1-a / R1-b)。
	#   原来是 28 只龟第 0 帧拼的群像墙(menu-bg-crowd.png) —— 用户先拍板「擂台 + 看台」,
	#   又定了「尽量不要复用」「不能用现有的龟立绘」⇒ 场馆、观众、角斗龟、火盆、旗全是新画的,
	#   由 tools/build_menu_arena_bg.py 分层烘好, MenuArenaBackdrop 拼起来并让观众/火/旗/主角动。
	#   (群像图没删: 登录墙 `login_wall_art.gd` 还在用它。)
	_bg_tile = MenuArenaBackdrop.new()
	add_child(_bg_tile)
	_bg_tile.fit(vp)
	## (原来这里还有一条「群像图没导入就退回平铺」的分支: 场景是代码 + 生成常量表拼的,
	##  不存在"没导入"这一态 ⇒ 那条分支恒走不到, 删了。其他屏的平铺底照旧在 PreloadCache 里。)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	## ★遮罩只用原来的一半(0.06~0.22, 不是给平铺纹理调的 0.15~0.40): 场景图在烘焙阶段
	##   已经去饱和/左侧压暗/暗角过了, 再按旧值叠一层整屏黑成一团、看台上的龟全看不见。
	grad.colors = PackedColorArray([
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.06),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.10),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.22),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 8; gt.height = 128
	var ov := TextureRect.new(); ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt; ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
	# (金色飘落粒子已移除 — 用户要求去掉; PoC 虽有 add.particles 但实机极淡, Godot 渲染显突兀)


## Logo: 顶部居中、缩到一半(理由见文件头「为什么 Logo 挪到顶部居中」)。
const LOGO_SCALE := 0.5
const LOGO_TOP := 4.0                        # 缩放后看得见的那块的顶沿


func _title() -> void:
	# 标题图 menu-title.png(360×203)。入场: 从屏外上方落下 + 放大 + 淡入(原 PoC 那一套, 只换落点)。
	var anim_path := "res://assets/sprites/menu/menu-title-anim.png"
	var static_path := "res://assets/sprites/menu/menu-title.png"
	if ResourceLoader.exists(anim_path) or ResourceLoader.exists(static_path):
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = Vector2(360, 203)
		t.pivot_offset = Vector2(180, 101.5)            # 绕中心缩放
		# PoC .menu-title-anim (index.html:97-105): menu-title-anim.png 5帧 421×237, steps(5) 1s 循环
		if ResourceLoader.exists(anim_path):
			var sheet: Texture2D = load(anim_path)
			var n := 5
			var fw: float = float(sheet.get_width()) / float(n)   # 2105/5 = 421
			var fh: float = float(sheet.get_height())             # 237
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(0.0, 0.0, fw, fh)
			t.texture = at
			content_root.add_child(t)
			var fanim := t.create_tween().set_loops()   # 帧循环 5fps (1s/5帧), int(f) 离散跳帧 ≈ steps(5)
			fanim.tween_method(func(f: float): at.region = Rect2(float(int(f) % n) * fw, 0.0, fw, fh), 0.0, float(n), float(n) * 0.2).set_trans(Tween.TRANS_LINEAR)
		else:
			t.texture = load(static_path)
			content_root.add_child(t)
		t.name = "Logo"                                 # 门禁 verify_menu_toast 量提示条不压它
		## 绕中心缩放 ⇒ 看得见的顶沿 = position.y + 101.5 × (1 − scale)
		var end_top_y := LOGO_TOP - 101.5 * (1.0 - LOGO_SCALE)
		var start_top_y := end_top_y - 180.0            # 起点在屏外上方
		t.position = Vector2(W / 2.0 - 180.0, start_top_y)
		t.scale = Vector2(LOGO_SCALE * 0.85, LOGO_SCALE * 0.85); t.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.25)                          # PoC delay 250ms
		tw.tween_property(t, "position:y", end_top_y, UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "scale", Vector2(LOGO_SCALE, LOGO_SCALE), UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "modulate:a", 1.0, UIPalette.T_SLOW)
		return
	else:
		var l := Label.new(); l.text = "斗龟场"; l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", Color("#ffd93d")); l.position = Vector2(W / 2.0 - 60.0, 20); content_root.add_child(l)


## 九宫格贴图块(像素件一律最近邻, 不许插值糊掉)。margins = 左/上/右/下(贴图像素)。
func _nine_rect(file: String, margins: Vector4, rect: Rect2) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(HUD + file)
	n.patch_margin_left = int(margins.x); n.patch_margin_top = int(margins.y)
	n.patch_margin_right = int(margins.z); n.patch_margin_bottom = int(margins.w)
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.position = rect.position
	n.size = rect.size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


## 一块【定好位、左对齐】的实心描边文字(Label 自带 outline, 不是 4 个偏移副本)。
## ★没有底板的字(状态区下两行 / 商店锁的理由)用它: 4 副本描边只有 1px, 压在看台上读不出。
func _place_outlined(text: String, size: int, fill: Color, pos: Vector2, box: Vector2) -> Label:
	var l := _menu_label(text, size, fill, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_color_override("font_outline_color", Color("#140a03"))
	l.add_theme_constant_override("outline_size", SOLID_OUTLINE)
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.size = box
	l.custom_minimum_size = box
	l.position = pos
	return l


## 次级键: 铁箍木板(不带金边、不发光)。与主 CTA 的金边木框 + 呼吸光晕是两种材质 ——
## 主次靠材质分, 不只靠大小。
func _plank_button(label: String, cb: Callable, size: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.size = size
	holder.pivot_offset = size / 2.0
	var plank := _nine_rect("btn-plank.png", Vector4(40, 14, 40, 14), Rect2(Vector2.ZERO, size))
	holder.add_child(plank)
	var lbl := _menu_label(label, 26, Color("#ffe9a8"))
	lbl.add_theme_color_override("font_outline_color", Color("#1e0f04"))
	lbl.add_theme_constant_override("outline_size", 8)
	holder.add_child(lbl)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func() -> void:
		holder.scale = Vector2(1.03, 1.03); plank.modulate = Color(1.18, 1.12, 1.0))
	btn.mouse_exited.connect(func() -> void:
		holder.scale = Vector2.ONE; plank.modulate = Color.WHITE)
	btn.button_down.connect(func() -> void: holder.scale = Vector2(0.97, 0.97))
	btn.pressed.connect(func() -> void:
		holder.scale = Vector2.ONE
		cb.call())
	return holder


# ─── 主菜单的可点元素 (实时版: 单一主菜单, 点击直接 _go 切场景, 无子页过场) ───


## 左列第 i 颗方键的顶沿。★一个来源 —— 门禁与布局都从这里算。
func _sq_y(i: int) -> float:
	return SQ_Y0 + float(i) * (SQ + SQ_GAP)


## 建主菜单的可点元素 (2026-10-05 第三轮「手游大厅骨架」, 见文件头):
##   左列  背包 / 商店 / 图鉴 / 排行榜   —— 方形图标键, 图标在上、字在下, 带红点槽
##   右下  训龟大师(铁箍木板, 小一档) + 开始战斗(木框 + 亮黄面, 全屏最大)
## ★`now` = 本屏那一刻(`_ready` 传)。**商店锁就指这一刻** —— 不传的话
##   `ranked_quota_full()` 兜底去读真实系统钟, 于是本屏就有两条钟
##   (详见 `_ready` 里 `paint_ts` 那段 + 探针 `tests/_probe_twoclocks.gd`)。
func _build_page_buttons(now: int = 0) -> void:
	var ts: int = now if now > 0 else _now_ts()
	## ★★★两颗按钮的锁**都从各自那条真判据取**(2026-09-29 台账 ④):
	##   原来商店的锁在这里就地写了一遍 `<=0 or eliminated or quota_full`, 而
	##   `_open_shop()` 里又写了一遍 —— 同一件事两份公式(memory `fb-hand-rolled-copies-drift`);
	##   「开始战斗」更糟: 画的锁只看 `eliminated`, 而它自己的门 `_battle_block_msg()` 还管
	##   **配额打满**与**周末阶段** ⇒ 打满后它**照样亮着**, 点下去只飘一行字。
	##   ⇒ 现在两颗都是「问那扇门自己」: 门说拦 ⇒ 画锁。判据 PLAY_LOCK_SAME_SOURCE 守着。
	var shop_locked := _shop_block_msg(ts) != ""
	var battle_locked := _battle_block_msg(ts) != ""
	var mic := "res://assets/sprites/menu/"
	## ★2026-10-05 第四轮删掉第五颗「战绩」: 整张玩家卡就点进战绩页, 再单设一颗是同一个入口摆两遍
	##   (用户:「点击整个卡那就不要战绩单独给按钮啊」)。
	var subs: Array = [
		["背包", func(): _go("Inventory"), mic + "ic-bag.png", false],
		[SHOP_LABEL, func(): _open_shop(), mic + "ic-shop.png", shop_locked],
		["图鉴", func(): _go("Codex"), mic + "ic-codex.png", false],
		["排行榜", func(): _go("Leaderboard"), mic + "ic-trophy.png", false],
	]
	## 锁着的那颗右边常驻一行短原因(不点也看得见) —— 只有商店有锁, 所以只给它传。
	var shop_reason := _shop_lock_reason(ts)
	for i in range(subs.size()):
		var sN: Array = subs[i]
		var e := _square_entry(str(sN[0]), sN[1], str(sN[2]), bool(sN[3]),
			shop_reason if str(sN[0]) == SHOP_LABEL else "")
		e.position = Vector2(SQ_X, _sq_y(i))
		page_box.add_child(e)
		_slide_in_left(e, i)
	# ── 训龟大师: 主 CTA 正上方、右沿同轴, 小一档、另一种皮 ──
	#    它跟「开始战斗」是同一件事的两步(配大师 → 出战), 放一起讲得通。
	## ★★2026-09-27 文字里不带 emoji(用户:「全是 ai 味和网页味」): 系统彩色 emoji 贴在像素木牌上是两种画法。
	var tb := _plank_button("训龟大师", func(): _go("TrainerConfig"), TRAINER_SIZE)
	## 有计数条的日子(吃命/配额)它让到计数条上面; 周六/周日没有计数条, 照旧贴着开始战斗。
	tb.position = TRAINER_POS_UP if not today_counter_texts(ts).is_empty() else TRAINER_POS
	page_box.add_child(tb)
	_slide_in(tb, 4)
	# ── 开始战斗: 右下角主 CTA —— 全屏最大, 也是全屏唯一一块实心亮色 ──
	#    横屏手机右手拇指的落点(荒野乱斗 / 使命召唤 / 刀塔霸业 三张参考同位)。
	var hero := _frame_button("开始战斗", func(): _start_battle_flow(), false, HERO_SIZE, FONT_HERO, "", battle_locked, true)
	hero.position = HERO_POS
	page_box.add_child(hero)
	## ★锁要**看得见地静态存在**: 灰框 + 🔒 角标(不画亮黄面)。原来只有"点下去飘一行字"。
	if battle_locked:
		_add_lock_badge(hero, HERO_SIZE)
	else:
		## R2(用户拍板): 主 CTA 保留木框, 靠【呼吸光晕 + 金边】拉开量级。
		##   锁着时不挂: 灰框配金光是在说「快点我」, 而点了只会被拦。
		MenuCtaGlow.attach(hero, HERO_SIZE)
	_slide_in(hero, 5)


## 【非阻塞提示】位置与大小。
## ★右沿与右栏同轴(右栏那一叠从上到下: 提示 → 训龟大师 → 开始战斗),
##   高 = `ROW_H`(81 视口像素 = 44pt), 与全屏所有靶子同一条触摸线。
## ★y 是**算出来的空地**: 底沿 386+81 = 467, 训龟大师顶沿 `TRAINER_POS.y` = 478 ⇒ 留 11px;
##   左沿 756 在两只角斗龟右边(龟的右沿 732), 不压主角。
const NUDGE_SIZE := Vector2(508.0, 81.0)
const NUDGE_POS := Vector2(W - WALL - 508.0, 346.0)   # 底沿 427 < 训龟大师上移后的顶沿 440


## 【拆墙的配件】没绑邮箱的人在主菜单上看到的那一句。
##
## ★★★它存在的理由: 2026-09-29 拆墙的代价是「一批人永远不绑, 换手机就丢档」,
##   而缓解**只能**靠这一句。它说一个**事实**(进度没备份) + 给一个**动作**(绑定)。
## ★★**不许退回成拦路**: 它就是主菜单上一个普通可点元素 —— 不点照常开始战斗,
##   不弹窗、不遮罩、不拦 `_start_battle_flow()`。这一条由 `verify_login_wall`
##   那条「一个绑定控件都不碰也能走到打一局」守着。
## ★字**不在这里拼**: `phase2_config.bind_nudge_text()` 是唯一一份。
## ★条件也不在这里判: `bind_needed()` 是唯一一处(设置页/绑定屏读的是同一个)。
## ★★后端没配时不建——于是门禁进程(`TURTLE_SUPABASE=" "`)里它一直不在场,
##   所以 `verify_login_wall` 里是**真开后端配置**把它造出来冏量的
##   (memory `fb-gate-subject-never-constructed`)。
func _bind_nudge() -> void:
	if not _P2C.bind_needed(_SB.enabled(), str(GameState.account_email)):
		return
	var b := _frame_button(_P2C.bind_nudge_text(), _open_bind_screen, false,
		NUDGE_SIZE, FONT_BTN, "")
	b.name = NUDGE_NAME
	b.position = NUDGE_POS
	content_root.add_child(b)
	_slide_in(b, 3)


## 提示那一块的节点名 —— 门禁按它找得到这一块(不靠数字下标, 也不靠抄一份文案)。
const NUDGE_NAME := "BindNudge"


## 点了那句提示 → 去【绑定屏】。
## ★绑定屏的代码在 `SettingsScene` 那侧(昵称 + 两步验码流都在那里),
##   所以这里只竖一个 static 旗子再过去 —— 在这边再建一份就是抄第二遍。
## ★不是 `func(): ...` 闭包: 具名方法门禁量得到(本仓 `verify_login_wall` 那条
##   「返回键接的是具名方法」同一个理由)。
func _open_bind_screen() -> void:
	_SET.open_bind_on_entry = true
	_go("Settings")


## 左列的一颗方形图标键: 方木块底(menu/hud/sqbtn.png) + 图标在上 + 字在下。
## ★可点区 = 整块 88×88(过 44pt 触摸线)。
## ★红点槽: 右上角一个名为 BADGE_NAME 的小红牌, 默认藏着 —— 有新东西时由那个入口点亮(写字 + visible)。
## ★锁着(只有商店会锁): 木块与图标压灰 + 右上角 🔒 角标(挂在 holder 直属, 与主 CTA 同一种角标);
##   锁的短理由**常驻**在方键右边那一行(LOCK_REASON_NAME), 点了再飘长句 toast —— 与上一版一样好懂。
func _square_entry(label: String, cb: Callable, icon_path: String, locked: bool, reason: String = "") -> Control:
	var holder := Control.new()
	holder.name = SQ_NAME_PREFIX + label
	holder.custom_minimum_size = Vector2(SQ, SQ)
	holder.size = Vector2(SQ, SQ)
	holder.pivot_offset = Vector2(SQ, SQ) / 2.0
	var base := _nine_rect("sqbtn.png", Vector4(24, 24, 24, 24), Rect2(Vector2.ZERO, Vector2(SQ, SQ)))
	base.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	base.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	if locked:
		base.modulate = Color(0.62, 0.58, 0.55)
	holder.add_child(base)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var it := TextureRect.new()
		it.texture = load(icon_path)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		it.size = Vector2(SQ_ICON, SQ_ICON)
		it.position = Vector2((SQ - SQ_ICON) / 2.0, 9.0)
		it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			it.modulate = Color(0.55, 0.55, 0.58)
		holder.add_child(it)
	var lb := _menu_label(label, SQ_FONT, Color("#b9b2a6") if locked else Color("#ffe9a8"))
	lb.add_theme_color_override("font_outline_color", Color("#140a03"))
	lb.add_theme_constant_override("outline_size", 6)
	lb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lb.position = Vector2(0.0, 55.0)
	lb.size = Vector2(SQ, 26.0)
	holder.add_child(lb)
	## 红点槽(默认藏着)。★直角纯色块: 圆角/描边盒是「网页味」(verify_ui_consistency 的棘轮)。
	var badge := Label.new()
	badge.name = BADGE_NAME
	badge.visible = false
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color("#fff4e0"))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#c8281e")
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(0)
	badge.add_theme_stylebox_override("normal", bsb)
	badge.position = Vector2(SQ - 18.0, -4.0)
	badge.size = Vector2(22.0, 22.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(badge)
	if locked:
		## 🔒 角标挂在 holder 直属、骑在方块右上角(不压图标) —— verify_season_elim 按「直属 Label 含 🔒」数它。
		var lk := Label.new()
		lk.text = "🔒"
		lk.add_theme_font_size_override("font_size", 20)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.position = Vector2(SQ - 30.0, 2.0)
		lk.size = Vector2(28.0, 28.0)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lk)
		if reason != "":
			## 理由没有底板, 压在看台最暗那一截上 ⇒ 实心描边 + 17 号字。
			var rs := _place_outlined(reason, 17, Color("#ffe6b8"),
				Vector2(SQ + 10.0, (SQ - 27.0) / 2.0), Vector2(220.0, 27.0))
			rs.name = LOCK_REASON_NAME
			rs.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(rs)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	## ★先设 size 再 FULL_RECT 会把 size 当 offset 叠上去(实测按钮变 2 倍大) ⇒ 只设锚点。
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	var base_mod: Color = base.modulate
	btn.mouse_entered.connect(func():
		base.modulate = base_mod * Color(1.22, 1.16, 1.06)
		holder.scale = Vector2(1.04, 1.04))
	btn.mouse_exited.connect(func():
		base.modulate = base_mod
		holder.scale = Vector2.ONE)
	btn.button_down.connect(func():
		base.modulate = base_mod * Color(0.8, 0.8, 0.8)
		holder.scale = Vector2(0.96, 0.96))
	btn.pressed.connect(func():
		base.modulate = base_mod
		holder.scale = Vector2.ONE
		cb.call())
	return holder


## 左栏键入场: 从屏外左侧滑入 + 淡入, 错峰 (保留原 PoC 好动画)
func _slide_in_left(holder: Control, idx: int) -> void:
	if GameState != null and GameState.perf_lite:   # 同 _slide_in: 低画质直接就位
		return
	var home_x := holder.position.x
	holder.modulate.a = 0.0
	holder.position.x = -560.0
	var tw := create_tween()
	tw.tween_interval(0.5 + 0.08 * float(idx))
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


## 锁定角标: 右上角 🔒 (商店未开时叠在灰框上, 一眼看出锁着)
func _add_lock_badge(holder: Control, size: Vector2) -> void:
	var lock := Label.new()
	lock.text = "🔒"
	lock.add_theme_font_size_override("font_size", 26)
	## ★2026-08-19 从 (w-36, 2) 挪到 (w-44, 10): 原位置让锁**骑在木牌右上角的花纹柱上、还探出板外**
	##   (实拍确认, 门禁也报了「🔒+8」)。木牌的花纹边实测约占 22px, 往里让开就落在木面上。
	## ★★★2026-10-03 又超了, 门禁报「🔒+13」。根因是上一次**照症状挪**(报 +8 就挪 8px),
	##   而没有按花纹边的真宽度算 ⇒ 换一个控件尺寸就又探出去。
	##   现在按带宽推: 右沿必须退到 `BAND` 以内 ⇒ x = size.x - BAND - 宽, 并留 2px 余量。
	##   ⚠ 这个缺陷**只在周六/周日出现**(商店锁着才画角标), 平时根本看不见 ——
	##   是 2026-10-03 周六跑门禁才照出来的。
	const _BAND := 22.0          # 木牌花纹边宽(实拍量的)
	const _LOCK_W := 32.0
	lock.position = Vector2(size.x - _BAND - _LOCK_W - 2.0, 10.0)
	lock.size = Vector2(_LOCK_W, _LOCK_W)
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lock)


## btn-frame.png 金色边框按钮 (NinePatchRect 9宫格保证渲染 + 透明Button点击 + 文字)
## `size` 2026-09-17 从"默认 360×87"改成【必填】: 版式重做后只剩训龟大师与主 CTA 两个木框,
## 两处都显式传尺寸, 那对默认常量(BTN_W/BTN_H)就再没人读了 —— 与其留着烂掉不如删。
func _frame_button(label: String, cb: Callable, disabled: bool, size: Vector2, font_size: int = 22, icon_path: String = "", locked: bool = false, primary: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.size = size
	holder.pivot_offset = size / 2.0   # hover/press 绕中心缩放
	# 木框背景 menu-frame-rect = frame-rect.png — Phaser setDisplaySize 整图拉伸, TextureRect STRETCH_SCALE 1:1
	var frame_path := "res://assets/sprites/menu/frame-rect.png"
	if not ResourceLoader.exists(frame_path):
		frame_path = "res://assets/sprites/menu/btn-frame.png"
	var frame_node: TextureRect = null
	if ResourceLoader.exists(frame_path):
		frame_node = TextureRect.new()
		frame_node.texture = load(frame_path)
		frame_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame_node.stretch_mode = TextureRect.STRETCH_SCALE
		frame_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# PoC ts:314 bg.setAlpha(0.95); 禁用走灰 tint (ts:311)
		frame_node.modulate = Color(0.6, 0.6, 0.6, 0.95) if (disabled or locked) else Color(1, 1, 1, 0.95)
		holder.add_child(frame_node)
	## ★2026-10-05 第三轮: 主 CTA 的面换成**全屏唯一的实心亮黄**(menu/hud/cta-face.png, 本轮新画)。
	##   R2 拍板「保留木框 + 呼吸光晕」⇒ 木框一个像素不动, 只在框里铺这块面。
	##   锁着时不铺: 灰框配亮黄是在说「快点我」, 而点了只会被拦(与光晕同一条规矩)。
	if primary and not (disabled or locked):
		var face := _nine_rect("cta-face.png", Vector4(8, 8, 8, 8),
			Rect2(HERO_FACE_INSET, size - HERO_FACE_INSET * 2.0))
		face.name = HERO_FACE_NAME
		holder.add_child(face)
	# 透明 Button 接点击 (flat 无样式, 不盖金框)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.disabled = disabled
	btn.focus_mode = Control.FOCUS_NONE
	holder.add_child(btn)
	# 文字 = 1:1 PoC addDomText: 22px 雅黑Bold, 填充#3a1f00, "描边"实为 4 方向 text-shadow(±1px 金#ffe4a0)
	#   (dom-text.ts:43-48 — 非 outline 轮廓扩张! 故不能用 Godot outline_size, 要 4 个偏移金副本)
	var fill := Color("#8b7755") if (disabled or locked) else Color("#3a1f00")
	var lbl: Control
	if primary:
		## 主 CTA 的字(2026-10-05 UI 重做): 原来是深棕字 + 1px 金影压在棕木上, 对比太低、字也小。
		## 改成亮金字 + 粗深棕描边 + 下投影 —— 全屏唯一一处这种字, 与木框金边 + 呼吸光晕一起拉开量级。
		## 第三轮: 字压在亮黄面上 ⇒ 奶白字 + 粗深棕描边(亮黄字在亮黄面上读不出)。
		var pl := _menu_label(label, font_size,
			Color("#8d8577") if (disabled or locked) else Color("#fffaf0"))
		pl.add_theme_color_override("font_outline_color", Color("#3a1a02"))
		pl.add_theme_constant_override("outline_size", 12)
		pl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		pl.add_theme_constant_override("shadow_offset_x", 0)
		pl.add_theme_constant_override("shadow_offset_y", 5)
		pl.add_theme_constant_override("shadow_outline_size", 12)
		lbl = pl
	else:
		lbl = _make_stroked_label(label, font_size, fill, Color("#ffe4a0"))
	holder.add_child(lbl)
	# 左侧 64px 图标(用户2026-07-18: 图标化+协调) — 文字移到图标右侧区居中(避让, 不遮)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var isz: float = size.y * 0.62
		var ix: float = size.x * 0.09
		var ic := TextureRect.new()
		ic.texture = load(icon_path)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(isz, isz)
		ic.position = Vector2(ix, (size.y - isz) / 2.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ic)
		var lx: float = ix + isz + 6.0
		lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		lbl.position = Vector2(lx, 0.0)
		lbl.size = Vector2(size.x - lx - size.x * 0.06, size.y)
	# hover/press 动画 (PoC ts:358-375): hover scale1.04 + 暖金 tint; 点击 press scale0.96 → 渲染1帧 → 回弹+回调
	if not disabled:
		if locked:
			btn.pressed.connect(cb)   # 锁定态: 保持灰(不做会重置灰的hover/press动画), 但仍可点→cb出toast提示
		else:
			btn.mouse_entered.connect(_btn_hover.bind(holder, frame_node, true))
			btn.mouse_exited.connect(_btn_hover.bind(holder, frame_node, false))
			# PoC ts:370-375: pointerdown → setScale(0.96) → delayedCall(16) → resetVisual + onClick。
			#   旧版 pressed.connect(cb) 在松手同帧立刻 change_scene → press 缩放没机会渲染 = "点了没动画"。
			btn.button_down.connect(_btn_press.bind(holder, frame_node, cb))
	return holder


## 1:1 PoC addDomText 描边 = 4 方向 text-shadow (非 outline): 4 个 ±1px 金副本在底 + 主填充在上
## `halign` 2026-09-17 加: 新版左栏的无框文字入口要【左对齐】, 而这里原本写死居中。
## 加可选参数而不是另写一个左对齐版本 —— 抄一份就永远落后一份(fb-hand-rolled-copies-drift)。
func _make_stroked_label(text: String, size: int, fill: Color, stroke: Color,
		halign: int = HORIZONTAL_ALIGNMENT_CENTER) -> Control:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for off in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var s := _menu_label(text, size, stroke, halign)
		s.offset_left = off.x; s.offset_right = off.x
		s.offset_top = off.y; s.offset_bottom = off.y
		wrap.add_child(s)
	wrap.add_child(_menu_label(text, size, fill, halign))   # 主填充在最上
	return wrap


func _menu_label(text: String, size: int, col: Color,
		halign: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 加粗字体 (1:1 PoC fontWeight:'bold' = 雅黑 Bold/weight700 真粗体)。
## 旧版 variation_embolden=1.0 假粗 → 中文字形外扩破填充, 看着"空心/描边"。改用 CJK 回退请求真 700 字重。
var _bold_font_cache: FontVariation = null
func _bold_font() -> FontVariation:
	if _bold_font_cache == null:
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		cjk.font_weight = 700              # 真粗体 (= PoC YaHei Bold), 非 embolden 膨胀
		cjk.allow_system_fallback = true
		# 中文平滑抗锯齿 (修"锯齿"): m6x11 像素字 import antialiasing=0, 但中文不能跟着关 AA。
		#   灰度 AA + 自动亚像素 + 不强制 hinting → 接近浏览器渲染雅黑的平滑度。
		cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		cjk.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		cjk.hinting = TextServer.HINTING_NONE
		_bold_font_cache = FontVariation.new()
		_bold_font_cache.base_font = load("res://assets/fonts/m6x11.ttf") as FontFile   # 英文/数字像素打底
		# 回退链: 系统雅黑Bold(桌面美观, 顺带给彩色emoji) → 【打包 Noto SC】(web/linux 无系统字体时的中文兜底)
		#         → 【打包 Noto Emoji】(单色 emoji 兜底, 防豆腐块). 原来只挂 cjk(SystemFont) = 无系统字体时中文/emoji 全掉字形。
		_bold_font_cache.fallbacks = [
			cjk,
			load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile,
			load("res://assets/fonts/NotoEmoji-Regular.ttf") as FontFile,
		]
		_bold_font_cache.variation_embolden = 0.0    # 中文粗体已走 cjk.font_weight=700; 不用 embolden(会糙边)
	return _bold_font_cache


## 按钮 hover 视觉 (PoC ts:358-371) — 从中心缩放
func _btn_hover(holder: Control, frame_node: TextureRect, on: bool) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0   # 中心缩放 (PoC setScale 绕 origin center)
		holder.scale = Vector2(1.04, 1.04) if on else Vector2(1, 1)
	if is_instance_valid(frame_node):
		frame_node.modulate = Color(1.0, 0.941, 0.753, 1.0) if on else Color(1, 1, 1, 0.95)


## 按钮点击: press 0.96 → 等 16ms (PoC delayedCall(16), 保证 press 渲染≥1帧) → 回弹 + 切场景回调
func _btn_press(holder: Control, frame_node: TextureRect, cb: Callable) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(0.96, 0.96)
	await get_tree().create_timer(0.016).timeout
	if is_instance_valid(holder):
		_btn_hover(holder, frame_node, false)
	if cb.is_valid():
		cb.call()


# ─── 右上工具簇(设置/教程/龟币) + 右信息板(赛季进度/战绩) — 正式化重排(用户2026-07-18) ───
#   去掉旧的右侧 4 磁贴竖列 + 左上赛季裸条; 信息统一进右侧金边信息板, 设置/教程收进右上小磁贴.
## ★`now` = 本屏那一刻(`_ready` 里算一次)。自己不读钟 —— 它只负责往下传。
func _right_column(now: int = 0) -> void:
	# ── 右上一排(从右往左): [⚙][?] 小图标键 · [龟币][深海币] 货币牌 —— 都收在 RIGHT_EDGE 这条右沿上 ──
	## ★2026-10-05 第三轮: 货币在左、?/⚙ 在最右(五张横屏参考里设置/菜单键都是最靠角的那一颗),
	##   ?/⚙ 看得见的方框从 82 缩到 ICON_VIS(用户「太大」), 点击区仍是 81(触摸线)。
	var set_x := RIGHT_EDGE - ICON_TAP
	var help_x := set_x - ICON_TAP
	var uy := 30.0 + (85.0 - ICON_TAP) / 2.0                   # 与货币牌竖直居中对齐
	var set_tile := _tile("", "⚙", func(): _go("Settings"), Vector2(set_x, uy), "", ICON_TAP, ICON_VIS)
	content_root.add_child(set_tile)
	_slide_in(set_tile, 1)
	var help_tile := _tile("ui/help-button", "❓", func(): _on_tutorial(), Vector2(help_x, uy), "", ICON_TAP, ICON_VIS)
	content_root.add_child(help_tile)
	_slide_in(help_tile, 2)
	## A5: 两种货币并排(金币 + 宝石那种摆法, 用户 2026-09-17)。右 = 龟币(主站货币), 左 = 深海币。
	var coin := _coin_frame()                                  # 龟币: value<0 => GameState.coins
	coin.position = Vector2(help_x - 6.0 - CHIP_W, 30)
	content_root.add_child(coin)
	_slide_in(coin, 0)
	var dsea := _coin_frame(int(GameState.meta_deepsea_coins),
		"res://assets/sprites/menu/ic-deepsea.png", Color(0, 0, 0, -1.0))   # a<0 = keep original colours
	dsea.position = Vector2(help_x - 6.0 - CHIP_W - 8.0 - CHIP_W, 30)
	content_root.add_child(dsea)
	_slide_in(dsea, 0)
	_status_row(now)       # 左上玩家信息卡
	_version_stamp()
	_travel_badge()


## 右下角版本号 —— 版本号最大的实际价值就是【测试者报 bug 时能说清是哪个版本】。
## ★必须从 ProjectSettings 读, 不许写死字符串: 写死就等于多一份会漂的副本,
##   而 iOS/Android/游戏内三处版本号曾经就是各说各的(无 / 0.9.0 / 1.0)。
##   门禁 verify_version 会断言这里没有硬编码版本号。
func _version_stamp() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	if v == "":
		return
	var l := _menu_label("v%s" % v, FONT_VERSION, Color("#7f8a99"))
	# ★★2026-08-01 修「版本号在主菜单上根本看不见」(审计器量出来的, 不是看像素猜的):
	#   _menu_label 里设了 set_anchors_preset(PRESET_FULL_RECT) —— 锚点 right/bottom = 1,
	#   于是【下一帧布局会按父容器重算 size】, 把这里设的 (200,22) 冲掉, 实测变成 1480×744。
	#   再叠上 HORIZONTAL_ALIGNMENT_RIGHT, 文字被画到那个巨框的右端 ≈ x 2544 —— 屏幕外。
	#   审计器 tests/_probe_ui_layout.gd 报: @Label@42 超出右 1064~1264 · 尺寸 1480x744。
	#   ★修法是把锚点先掰回 TOP_LEFT, 再设 size/position; 只改 size 不改锚点是没用的。
	#   版本号的全部价值 = 测试者报 bug 时能说清是哪个版本(CLAUDE.md §2.5), 看不见 = 等于没有。
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(200, 24)
	l.custom_minimum_size = Vector2(200, 24)
	## 2026-10-05 第三轮: 右下角是主 CTA(底 692) ⇒ 版本号落在它正下方, 底边留 3px —— 整行字都在屏内(返工: 原来贴着 720 被切)。
	l.position = Vector2(W - WALL - 200, H - 27)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(l)


## 【开发包时间穿越】角标的节点名 —— 门禁 `verify_time_travel` 按名字找它。
const TRAVEL_BADGE_NAME := "DevClockBadge"

## 开发包里一旦穿越了, 右下角版本号上方挂一行「测试时间 周六 15:00 UTC」(2026-10-04)。
## ★为什么必须有: 主菜单整屏(赛程条「今」、倒计时、能不能开打)都会跟着假时间变,
##   不挂这一行的话测试者截图报 bug 时**看不出那是假时间**, 会当成真赛程的 bug。
## ★没穿越 / 正式包 ⇒ `travel_badge_text()` 返回 "" ⇒ 一个节点都不建(玩家路径一字不动)。
## ★字从 `_P2C.travel_badge_text()` 取, 本屏不另外读钟(`_P2C.now_utc()` 在本文件只许出现在 `_now_ts()` 里)。
func _travel_badge() -> void:
	var t: String = _P2C.travel_badge_text()
	if t == "":
		return
	var l := _menu_label(t, FONT_VERSION, Color("#ffb347"))
	l.name = TRAVEL_BADGE_NAME
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)   # 同 `_version_stamp`: 先掰回锚点再设 size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(300, 24)
	l.custom_minimum_size = Vector2(300, 24)
	l.position = Vector2(W - WALL - 200 - 12 - 300, H - 27)   # 版本号左边同一行(主 CTA 底下)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(l)


## 货币芯片 (裸图标染色 + 描边数字, 无底框) — 抽出复用; 返回未定位的 Control, 调用方定位/入场
## A5(2026-09-17, user): 龟币 is the MAIN-SITE currency and must stay visible, but the two
## currencies used to sit in two totally different places/styles - 龟币 in a frame up top,
## 深海币 as a text row inside the season panel. User asked for the usual game treatment:
## gold and gems side by side. So this chip is parameterised and drawn twice.
## value < 0 => GameState.coins (龟币). icon_path "" => the old green coin.png.
func _coin_frame(value: int = -1, icon_path: String = "", tint: Color = Color(0.122, 0.561, 0.247)) -> Control:
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(CHIP_W, 85); coin.size = Vector2(CHIP_W, 85)
	## 2026-10-05 UI 重做: 货币要有底座 —— 一块暗木 + 黄铜包边的小牌(PixelLab 新生成, menu/hud/chip.png),
	##   左端是币槽, 图标落进槽里。不是按钮材质(按钮是金边木框/铁箍木板), 不会被读成按钮。
	coin.add_child(_nine_rect("chip.png", Vector4(56, 16, 20, 16), Rect2(0, 14.5, CHIP_W, 56)))
	## P0-2(方案书 20260917 主菜单版式重做): 货币区【不套任何按钮材质】。
	##   原来这里垫一张 menu/frame-coin 贴图 —— 与按钮同一族木框, 两个芯片看着像两个按钮。
	##   参考的 18 款里没有一款给货币套框: 一律裸图标 + 描边数字。
	##   外框尺寸 152x85 保留(右上那排磁贴按它排位), 只是不再画底。
	var _ip: String = icon_path if icon_path != "" else "res://assets/sprites/ui/coin.png"
	if ResourceLoader.exists(_ip):   # 黑线稿→非透明像素染绿(#1f8f3f)
		var cimg: Image = load(_ip).get_image()
		var green := tint
		## tint.a < 0 means "this icon is already coloured, do not repaint it".
		## Found by actually looking at the shot: the tint loop paints EVERY non-transparent
		## pixel one flat colour. coin.png is line art so an outline survives; ic-deepsea.png
		## is solid, so it came out as a featureless blue dot - unreadable as an icon.
		var _repaint: bool = tint.a >= 0.0
		for yy in range(cimg.get_height()):
			for xx in range(cimg.get_width()):
				var px := cimg.get_pixel(xx, yy)
				if _repaint and px.a > 0.0:
					cimg.set_pixel(xx, yy, Color(green.r, green.g, green.b, px.a))
		var ci := TextureRect.new(); ci.texture = ImageTexture.create_from_image(cimg)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ci.size = Vector2(34, 34); ci.position = Vector2(36 - 17, 42.5 - 17); coin.add_child(ci)
	var cl := Label.new(); cl.text = "%d" % (GameState.coins if value < 0 else value)
	cl.position = Vector2(64, 0); cl.size = Vector2(CHIP_W - 64 - 20, 85)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## 没了木底, 深绿字直接压在背景上读不出来 ⇒ 改亮字 + 黑描边(同 _tile 的数字)。
	cl.add_theme_font_size_override("font_size", 26); cl.add_theme_color_override("font_color", Color("#fff4d6"))
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)); cl.add_theme_constant_override("outline_size", 6)
	coin.add_child(cl)
	return coin


## 赛季状态行 —— 原来是右侧 560×398 的金边表格卡(大轮/Lv/命/本周场次/战绩 五行)。
## 实拍的 8 张主菜单里【没有一张】把玩家数据做成占屏 24% 的竖排表格:
## Zookeeper World 是右上角两个小胶囊(金币 590 / 钻石 30)、WarioWare Gold 是右上 950。
## ⇒ 压成 LOGO 下面的一行, 把那 24% 的屏幕还给龟群像。
##
## 整行可点 → 战绩(Record), 所以行高吃 ROW_H(81) 过 44pt 触摸线;
## 视觉上只是一行字, 但手指目标不小 —— 跟 _text_entry 同一个思路。
## 周六那一行读数。返回**空串 = 今天不是闯关赛日**(调用方照旧显示积分赛那一行)。
##
## ★★为什么单列一个函数而不是在 `_status_row()` 里插个 if:
##   周六显示「本周 N/24」是**错的读数** —— 周六的场次根本不吃那个配额,
##   玩家会盯着一个整天不动的数字, 还以为自己打的场次没记上。
## ★三种状态各说各的, 而且**带上还差几场** —— 「2-1」本身不告诉玩家还剩多少机会,
##   而"再输两场就出局"正是闯关赛每一场的分量所在。
## ★`now` 只给门禁喂已知日期(同 `_battle_block_msg`)。产品调用一律不传 ——
##   不给注入口的话, 这一行**只有周六跑门禁才会被执行到**(今天已经栽过一次)。
func _gauntlet_status_line(now: int = 0) -> String:
	var ts: int = now if now > 0 else _now_ts()
	if _P2C.phase_at_utc(ts) != _P2C.PHASE_GAUNTLET:
		return ""
	if not _P2C.phase_mode_live(_P2C.PHASE_GAUNTLET):
		return ""
	if not GameState.gauntlet_eligible():
		return "闯关赛 · 本周没晋级"
	var w: int = int(GameState.gauntlet_wins)
	var l: int = int(GameState.gauntlet_losses)
	var lab: String = _P2C.gauntlet_label(w, l)
	var st: String = GameState.gauntlet_state()
	## ★★「没打的场次化成了多少」—— 晋级者才可能有, 所以挂在这几条后面。
	##   金额与 `backfill_ranked_quota()` 读同一份账(见 `backfill_summary()` 头注),
	##   这里一个数都不自己算。`backfill_paid == 0` 时是空串, 不占位。
	var bf: Dictionary = GameState.backfill_summary()
	var conv: String = ""
	if int(bf.get("games", 0)) > 0:
		conv = " · 没打的 %d 场化成 深海币 +%d · 经验 +%d" % [
			int(bf["games"]), int(bf["coins"]), int(bf["xp"])]
	if st == _P2C.GAUNTLET_IN:
		return "闯关赛 %s · 已晋级决赛日%s" % [lab, conv]
	if st == _P2C.GAUNTLET_OUT:
		return "闯关赛 %s · 已出局%s" % [lab, conv]
	return "闯关赛 %s · 再赢 %d 场晋级 / 再输 %d 场出局%s" % [
		lab, maxi(0, int(_P2C.GAUNTLET_WINS_IN) - w), maxi(0, int(_P2C.GAUNTLET_LOSSES_OUT) - l), conv]


## 周日那一行读数。返回**空串 = 今天不是决赛日**。
##
## ★★★2026-09-28 补。周六那一行 2026-09-22 就修过(理由见上面那段: 配额周六不动,
##   摆着只会误导), 而**周日一模一样却漏了**:
##     `phase_uses_ranked_quota(FINALS)` = false ⇒ `ranked_used` 周日一整天不动;
##     `finals_settle_sealed()` / `finals_reveal()` **一个字都不碰 `hearts`**
##     (单败淘汰里"输"= 出局, 不该再扣命 —— 见 GameState 那两个函数的头注)
##   ⇒ 真实 UTC 周日实拍到的就是「第 1 大轮 · Lv 1   ♥ 3/8   本周 7/24」,
##     **两个数周日全程冻结**。玩家打完一轮回来看, 会以为自己那一轮没记上。
## ⇒ 与周六同一个形状: 周日把那两个数**整段换掉**, 换成今天真在动的那件事。
##
## ★三态各说各的, 判据与别处同一处: 「进没进决赛日」= `gauntlet_state() == GAUNTLET_IN`,
##   「有没有拿到闯关赛资格」= `gauntlet_eligible()` —— 与 `_battle_block_msg` 周日那一支
##   传给 `_P2C.finals_block_msg()` 的**就是这两个**, 两处不许各问一套。
## ★进了决赛日的人要**指路**(那一场不在「开始战斗」后面, 在赛程条周日那一格的
##   「决赛日 看对阵图」门后面) —— 与 `finals_block_msg` 同一个去处。
## ★`now` 只给门禁喂已知日期; 产品走 `_status_row()` → `_now_ts()`。
func _finals_status_line(now: int = 0) -> String:
	var ts: int = now if now > 0 else _now_ts()
	if _P2C.phase_at_utc(ts) != _P2C.PHASE_FINALS:
		return ""
	if not _P2C.phase_mode_live(_P2C.PHASE_FINALS):
		return ""
	if GameState.gauntlet_state() == _P2C.GAUNTLET_IN:
		return "决赛日 · 已晋级"
	var lab: String = _P2C.gauntlet_label(
		int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	if GameState.gauntlet_eligible():
		## ★打过闯关赛但没打进 —— **不许说他「没晋级」**(周一~五刚夸过他已过晋级线),
		##   与 `finals_block_msg(false, true)` 同一个口径。
		return "决赛日 · 闯关赛止步 %s" % lab
	return "决赛日 · 本周没晋级"


## 今天这一天该在状态行里显示哪一段。空串 = 照旧显示积分赛那一行(命 + 本周配额)。
##
## ★★★2026-09-28: 这一层原来不存在, `_status_row()` 直接 `_gauntlet_status_line()`
##   **不传参** ⇒ 那一行走的是 `Time.get_unix_time_from_system()`,
##   而同文件的 `_battle_block_msg` / `_open_shop` / `_start_battle_flow` 早就走
##   `_now_ts()`(`clock_override_ts` 可注入)。后果是**门禁盲区**:
##   钉死时钟之后, 不传参那个调用仍然读真实时钟 ⇒ 那一行**一周只有一天会被执行到**,
##   周六/周日两支改坏了也没人红(实测: 设 `clock_override_ts=周六` 后
##   `_gauntlet_status_line()` 不传参照旧返回空串)。
## ⇒ 分派做成一个函数 + 走 `_now_ts()`, 门禁就能注入七天逐天验那一行说的话。
func _phase_status_line(now: int = 0) -> String:
	var ts: int = now if now > 0 else _now_ts()
	var ph: String = _P2C.phase_at_utc(ts)
	if ph == _P2C.PHASE_GAUNTLET:
		return _gauntlet_status_line(ts)
	if ph == _P2C.PHASE_FINALS:
		return _finals_status_line(ts)
	return ""


## ══════════════════════════════════════════════════════════════════════
##  左上玩家卡 + 开始战斗上方的计数条(2026-10-05 第四轮, 照手游大厅的标准写法)
## ══════════════════════════════════════════════════════════════════════
## 原来这里是一张塞了四段字的卡(头像 + 昵称 ID + 绶带「第 N 大轮 · Lv X」+ ♥/本周 + 战绩行)。
## 用户:「按标准写法怎么写啊，商业游戏怎么写啊」「头像？我们有头像吗？」⇒ 拆成各归其位:
##   玩家卡   = [等级徽章] 昵称 #ID / 经验条 x/y / 第 N 大轮     ← 皇室战争 / 英雄联盟手游 左上那一格
##   计数条   = ♥ 命   本周对战 n/配额   贴在开始战斗正上方     ← 荒野乱斗 PLAY 上面那条
##   周六周日 = 那两个数整天不动 ⇒ 不建计数条, 当天读数进模式卡(`mode_card_lines` 第二行)
## ★`now` = 本屏那一刻; 0 时才自己问一次(单独被门禁/实拍调用时)。
func _status_row(now: int = 0) -> void:
	var ts: int = now if now > 0 else _now_ts()
	_player_card()
	_today_counter(ts)


## 经验条的读数: [当前, 本级所需, 条上的字]。满级 ⇒ [1, 1, 「满级」](整条填满)。
## ★两个数都问唯一出处: `GameState.season_xp` / `phase2_config.xp_to_next(season_level)`(升级判据 `add_season_xp` 用的同一个)。
func xp_readout() -> Array:
	var lv: int = int(GameState.season_level)
	if lv >= int(_P2C.MAX_LEVEL):
		return [1, 1, XP_MAX_TEXT]
	var need: int = maxi(1, int(_P2C.xp_to_next(lv)))
	var cur: int = clampi(int(GameState.season_xp), 0, need)
	return [cur, need, "%d/%d" % [cur, need]]


## 计数条那一行字: [命, 本周]。空数组 = 今天不吃命/配额(周六/周日), 不建计数条。
## ★满命/配额读常量 —— 原来写死成 `/8`, 2026-09-30 满命改成 6 之后就显示过「♥ 6/8」。
func today_counter_texts(now: int) -> Array:
	if _phase_status_line(now) != "":
		return []
	return ["♥ %d/%d" % [int(GameState.hearts), int(_P2C.HEARTS_MAX)],
		"本周对战 %d/%d" % [int(GameState.ranked_used), int(_P2C.RANKED_QUOTA)]]


func _player_card() -> void:
	## 先问 ID 再问名字: `my_tag()` 会顺手把安装号建出来, 而默认昵称的种子就是安装号 ——
	##   反过来的话全新安装第一屏拿到的是没种子的兜底名, 下一屏才换成真默认名(门禁实测抓到过)。
	var tag_s := str(_BE.my_tag())
	var name_s := str(_BE.player_display_name())
	## `my_tag()` 自己就带「#」(#XXXXXX) ⇒ 原样摆, 不再加前缀。
	var tag_txt := tag_s
	var season_txt := "第 %d 大轮" % int(GameState.season_id)
	var xp: Array = xp_readout()
	var bf := _bold_font()
	var name_w: float = bf.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_L0_FONT).x
	var tag_w: float = bf.get_string_size(tag_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_TAG_FONT).x
	## ★卡宽跟着内容收: 取「昵称 #ID」/ 经验条下限 / 大轮那行 里最宽的, 上限 LEFT_W。
	var tw: float = maxf(XP_MIN_W, name_w + CARD_TAG_GAP + tag_w + 8.0)
	tw = maxf(tw, bf.get_string_size(season_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, SEASON_FONT).x + 8.0)
	tw = minf(ceilf(tw), LEFT_W)
	var card_size := Vector2(CARD_TEXT_X + tw + CARD_PAD_R, CARD_H)

	var holder := Control.new()
	holder.name = CARD_NAME
	holder.position = CARD_POS
	holder.custom_minimum_size = card_size
	holder.size = card_size
	## 卡底: 铭牌木板(menu/hud/card.png; 左端原来的头像圆环已抹成木面, 那一格放等级徽章)。
	var plate := _nine_rect("card.png", Vector4(112, 16, 40, 16), Rect2(Vector2.ZERO, card_size))
	holder.add_child(plate)
	## 大等级徽章: 黄铜盾(menu/hud/lvbadge.png, 原尺寸 1:1) + 大号等级数字。
	var badge := TextureRect.new()
	badge.name = LV_BADGE_NAME
	badge.texture = load(HUD + "lvbadge.png")
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.size = LV_BADGE_SIZE
	badge.position = LV_BADGE_POS
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(badge)
	## 数字落在盾面上半(盾尖往下收, 视觉重心偏上): 框 = 盾宽 × 盾面直边那段。
	var lv := _place_outlined(str(int(GameState.season_level)), LV_FONT, Color("#fff4d6"),
		LV_BADGE_POS + Vector2(0.0, 10.0), Vector2(LV_BADGE_SIZE.x, 44.0))
	lv.name = LV_TEXT_NAME
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(lv)
	## 第一行: 昵称(大) + #ID(小号冷灰, 紧跟昵称)。★两个都问唯一出处, 不在这里拼。
	var nm := _place_outlined(name_s, CARD_L0_FONT, Color("#fff4d6"),
		Vector2(CARD_TEXT_X, CARD_L0_Y), Vector2(minf(name_w + 4.0, tw), 31.0))
	nm.name = "Nickname"
	holder.add_child(nm)
	if tag_txt != "":
		var tx: float = CARD_TEXT_X + minf(name_w, tw) + CARD_TAG_GAP
		var tg := _place_outlined(tag_txt, CARD_TAG_FONT, Color("#b8c4cf"),
			Vector2(tx, CARD_L0_Y + 4.0), Vector2(maxf(CARD_TEXT_X + tw - tx, 1.0), 25.0))
		tg.name = "PlayerTag"
		holder.add_child(tg)
	## 第二行: 经验条。暗槽(九宫格) + 里面一根 TextureProgressBar(value/max 就是读数本身) + 条上「x/y」。
	var bar_r := Rect2(Vector2(CARD_TEXT_X, XP_Y), Vector2(tw, XP_H))
	holder.add_child(_nine_rect("xpbar.png", Vector4(8, 8, 8, 8), bar_r))
	var bar := TextureProgressBar.new()
	bar.name = XP_BAR_NAME
	bar.texture_progress = load(HUD + "xpbar-fill.png")
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 4
	bar.stretch_margin_right = 4
	bar.stretch_margin_top = 4
	bar.stretch_margin_bottom = 4
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.position = bar_r.position + Vector2(4.0, 4.0)
	bar.size = bar_r.size - Vector2(8.0, 8.0)
	bar.min_value = 0.0
	bar.max_value = float(xp[1])
	bar.step = 0.0
	bar.value = float(xp[0])
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bar)
	var xt := _place_outlined(str(xp[2]), XP_FONT, Color("#ffffff"), bar_r.position, bar_r.size)
	xt.name = XP_TEXT_NAME
	xt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(xt)
	## 第三行: 大轮(小字)。「大轮」是本作的赛季叫法, 不改。
	var sl := _place_outlined(season_txt, SEASON_FONT, Color("#ecd9b0"),
		Vector2(CARD_TEXT_X, SEASON_Y), Vector2(tw, 25.0))
	sl.name = SEASON_LINE_NAME
	holder.add_child(sl)
	## 整卡可点 → 战绩(左列不再单设战绩键; 用户:「点击整个卡那就不要战绩单独给按钮啊」)。
	var btn := Button.new()
	btn.name = "CardTap"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	## 悬停 = 卡底提亮(与左列方键同一种反馈)
	btn.mouse_entered.connect(func(): holder.create_tween().tween_property(plate, "modulate", Color(1.2, 1.15, 1.08), UIPalette.T_TAP))
	btn.mouse_exited.connect(func(): holder.create_tween().tween_property(plate, "modulate", Color.WHITE, UIPalette.T_TAP))
	btn.pressed.connect(_open_record)
	content_root.add_child(holder)
	_slide_in_left(holder, 0)


## 点玩家卡 → 战绩页。★具名方法(门禁量得到接线), 不是闭包。
func _open_record() -> void:
	_go("Record")


## 开始战斗正上方的计数条: `♥ a/b   本周对战 n/q`, 居中压在主 CTA 上沿之上。
## ★底 = 经验条同一张暗槽(xpbar.png): 一屏只有一种「读数槽」。
func _today_counter(now: int) -> void:
	var tx: Array = today_counter_texts(now)
	if tx.is_empty():
		return
	var bf := _bold_font()
	var w0: float = ceilf(bf.get_string_size(str(tx[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTER_FONT).x) + 6.0
	var w1: float = ceilf(bf.get_string_size(str(tx[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTER_FONT).x) + 6.0
	var gap := 22.0
	var w: float = COUNTER_PAD * 2.0 + w0 + gap + w1
	var holder := Control.new()
	holder.name = TODAY_COUNTER_NAME
	holder.size = Vector2(w, COUNTER_H)
	holder.custom_minimum_size = holder.size
	holder.position = Vector2(HERO_POS.x + (HERO_SIZE.x - w) / 2.0, HERO_POS.y - COUNTER_GAP - COUNTER_H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_nine_rect("xpbar.png", Vector4(8, 8, 8, 8), Rect2(Vector2.ZERO, holder.size)))
	var lh := _place_outlined(str(tx[0]), COUNTER_FONT, Color("#ffb4a2"),
		Vector2(COUNTER_PAD, 3.0), Vector2(w0, COUNTER_H - 6.0))
	lh.name = "CounterHearts"
	holder.add_child(lh)
	var lq := _place_outlined(str(tx[1]), COUNTER_FONT, Color("#ffe9a8"),
		Vector2(COUNTER_PAD + w0 + gap, 3.0), Vector2(w1, COUNTER_H - 6.0))
	lq.name = "CounterQuota"
	holder.add_child(lq)
	content_root.add_child(holder)
	_slide_in(holder, 5)

## 右栏卡片入场: 从右(贴墙外)滑入 + 淡入. PoC delay 850+60*idx, dur420.
func _slide_in(holder: Control, idx: int) -> void:
	## ★低画质: 直接就位, 不播入场。
	##   背景从「平铺+25s 漂移」换成静态群像后, perf_lite 在主菜单【一个消费者都没有了】
	##   (verify_settings 当场红: 「主菜单背景漂移读 perf_lite」)。
	##   静态图没有漂移可关, 但入场 tween 还在 —— 低画质关掉它, 这个开关才不是空的。
	if GameState != null and GameState.perf_lite:
		return
	var home_x := holder.position.x
	holder.position.x = home_x + 60.0
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.85 + 0.06 * idx)
	tw.tween_property(holder, "position:x", home_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.42)


func _tile(icon_key: String, label: String, cb: Callable, pos: Vector2, sub_value: String = "", sz: float = 82.0, vis: float = -1.0) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.size = Vector2(sz, sz)
	## ★`vis` > 0: 看得见的方框比点击区小(2026-10-05 第三轮 ?/⚙ 缩小, 用户「太大」) ——
	##   方框画在 holder 正中, 点击区仍铺满 holder(触摸线 81 不让)。
	var v: float = vis if vis > 0.0 else sz
	var vo: float = (sz - v) / 2.0
	var btn := TextureButton.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.ignore_texture_size = true; btn.stretch_mode = TextureButton.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/menu/frame-square.png"):
		if vis > 0.0:
			var fr := TextureRect.new()
			fr.texture = load("res://assets/sprites/menu/frame-square.png")
			fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; fr.stretch_mode = TextureRect.STRETCH_SCALE
			fr.size = Vector2(v, v); fr.position = Vector2(vo, vo)
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(fr)
		else:
			btn.texture_normal = load("res://assets/sprites/menu/frame-square.png")
	# 磁贴 hover/press (PoC ts:585-588: hover scale1.06 / press0.97 + delayedCall(60))
	if cb.is_valid():
		btn.mouse_entered.connect(_tile_hover.bind(holder, true))
		btn.mouse_exited.connect(_tile_hover.bind(holder, false))
		btn.button_down.connect(_tile_press.bind(holder, cb))
	holder.add_child(btn)
	var ipath := "res://assets/sprites/%s.png" % icon_key   # icon_key 已含子目录 (menu/.. 或 ui/..)
	if icon_key != "" and ResourceLoader.exists(ipath):
		var ic := TextureRect.new(); ic.texture = load(ipath)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 有 subValue(战绩) 时图标缩到 0.58 + 上移 size*0.10 给文字让位 (1:1 PoC makeSquareTile)
		var has_sub := sub_value != ""
		var isz := roundi(v * (0.58 if has_sub else 0.72))    # 无sub图标(教程❓)填满些 (原0.62偏小)
		var iy_off := -v * 0.10 if has_sub else 0.0           # 无sub → 正居中(原-6上偏→与旁边⚙不齐·歪·用户2026-07-18)
		ic.size = Vector2(isz, isz); ic.position = Vector2((sz - isz) / 2.0, (sz - isz) / 2.0 + iy_off)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(ic)
		if has_sub:
			var vl := Label.new()
			vl.text = sub_value
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			vl.add_theme_font_size_override("font_size", 13)
			vl.add_theme_color_override("font_color", Color("#ffd966"))
			vl.size = Vector2(sz, 16); vl.position = Vector2(0, sz / 2.0 + sz * 0.34 - 8.0)
			vl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(vl)
	else:
		var tl := Label.new(); tl.text = label; tl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", roundi(v * 0.44)); tl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(tl)
	return holder


## 磁贴 hover (PoC ts:585 scale1.06) — 从中心缩放
func _tile_hover(holder: Control, on: bool) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(1.06, 1.06) if on else Vector2(1, 1)


## 磁贴点击 press (PoC ts:587-588 scale0.97 + delayedCall(60)) → 回弹 + 回调
func _tile_press(holder: Control, cb: Callable) -> void:
	if is_instance_valid(holder):
		holder.pivot_offset = holder.size / 2.0
		holder.scale = Vector2(0.97, 0.97)
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(holder):
		holder.scale = Vector2(1, 1)
	if cb.is_valid():
		cb.call()


## ══════════════════════════════════════════════════════════════════════
##  「今天」模式卡 + 本周赛程弹层(2026-10-05 第三轮)
## ══════════════════════════════════════════════════════════════════════
## 原来七天赛程是一条贴底的满宽长条, 常驻占掉屏幕最底下一整行。参考里(荒野乱斗那块活动卡)
## 主 CTA 左边只放**今天**那一件事: 今天打什么、一句规矩、还剩多久 —— 整周的表点开才看。
## ⇒ 模式卡只说今天; 点它弹出**原来那条赛程条**(组件一个字没改, 七格 + 收盘块 + 周六/周日的门都在里面)。
## ★赛程判定与数据一个字都没动, 只换了「摆在哪」: 模式卡的三行字全是现成的纯函数/常量拼出来的。
var _mode_box: Control = null
var _week_pop: Control = null
var _week_dim: ColorRect = null
const WEEK_DIM_NAME := "WeekPopupDim"


## 这个阶段的一句规矩(不带星期几、不带阶段名)。★数字一律读规则常量。
## ★与赛程条点格子飘的那句(`_week_day_note`)同一份字 —— 那句就是「周X 阶段名 · 这一句」。
func _phase_rule(ph: String) -> String:
	match ph:
		_P2C.PHASE_REST:
			return "规则同积分赛，计入本周场次"
		_P2C.PHASE_GAUNTLET:
			return "积分赛 %d 胜可参加" % int(_P2C.PROMOTE_WINS)
		_P2C.PHASE_FINALS:
			return "闯关赛晋级玩家参赛"
	return "每周最多 %d 场 · 周五截止" % int(_P2C.RANKED_QUOTA)


## 下一个阶段从哪一刻开始(UTC 零点)。★只问 `phase_at_utc`, 不另写一张星期表。
func _next_phase_start(now: int) -> int:
	var ph: String = _P2C.phase_at_utc(now)
	var t: int = now - (now % 86400) + 86400
	for _i in range(7):
		if _P2C.phase_at_utc(t) != ph:
			return t
		t += 86400
	return t


## 模式卡第三行: 倒计时。★档位与赛程条收盘块**同一个分类函数**(`close_block_kind`), 不另判一遍。
func _mode_countdown(now: int) -> String:
	var ph: String = _P2C.phase_at_utc(now)
	var left: int = _P2C.close_left_sec(now)
	var live: bool = (_P2C.phase_mode_live(_P2C.PHASE_FINALS)
		if strip_finals_live_override < 0 else strip_finals_live_override == 1)
	var kind := close_block_kind(ph, live,
		_SB.service_state() == _SB.ST_MAINTENANCE, left, _P2C.can_start_match_utc(now))
	match kind:
		BK_MAINTENANCE:
			return "维护中"
		BK_COUNTDOWN:
			return "距截止 %s" % _left_text(left)
		BK_LOCKED:
			return "已截止 · 停止匹配"
		BK_CLOSED_TODAY:
			return "今日已截止"
		BK_BRACKET_DOOR:
			## 决赛日那一场在对阵图里, 门在本周赛程里 —— 这一行就是指路。
			return "查看对阵图 »"
	var nxt: int = _next_phase_start(now)
	return "距%s开始 %s" % [str(_P2C.PHASE_LABEL.get(_P2C.phase_at_utc(nxt), "")), _left_text(nxt - now)]


## 模式卡三行字: [今天的赛制, 第二行, 倒计时]。门禁直接喂时间戳调它。
## ★第二行: 平日 = 一句规则; 周六/周日 = 玩家自己今天的读数(`_phase_status_line`, 闯关赛战绩 / 决赛日去向)。
##   那两天命与本周场次整天不动, 开始战斗上方不建计数条 ⇒ 今天在动的那件事就写在这张卡上。
##   读数开头的赛制名(「闯关赛」/「决赛日」)与卡的标题重复 ⇒ 去掉, 只留后半句。
func mode_card_lines(now: int) -> Array:
	var ph: String = _P2C.phase_at_utc(now)
	var title := str(_P2C.PHASE_LABEL.get(ph, ph))
	var second := _phase_rule(ph)
	var st: String = _phase_status_line(now)
	if st != "":
		second = _strip_phase_head(st, title)
	return [title, second, _mode_countdown(now)]


## 「闯关赛 2-1 · 再赢…」→「2-1 · 再赢…」; 「决赛日 · 已晋级」→「已晋级」。
static func _strip_phase_head(line: String, title: String) -> String:
	var s := line
	if title != "" and s.begins_with(title):
		s = s.substr(title.length()).strip_edges()
	if s.begins_with("·"):
		s = s.substr(1).strip_edges()
	return s if s != "" else line


## 建 / 重建模式卡。★`now` 由调用方给(首屏 = `_ready` 那一刻; 每秒轮询 = `_strip_now()`), 自己不读钟。
func _mode_card(now: int) -> void:
	if is_instance_valid(_mode_box):
		_mode_box.queue_free()
	var lines: Array = mode_card_lines(now)
	## ★第二行(周六/周日是玩家今天的读数)装不下一行就折行, 卡**往上**长(底沿永远与开始战斗对齐)。
	##   平常的读数都装得下(「2-1 · 再赢 2 场晋级 / 再输 2 场出局」17 号 ~265 < 284);
	##   只有晋级者带「没打的 N 场化成…」那条长尾时才会长高。
	var rule_w: float = MODE_SIZE.x - 36.0
	var ink: float = _bold_font().get_string_size(str(lines[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, MODE_RULE_FONT).x
	var extra_rows: int = maxi(0, int(ceil(ink / rule_w)) - 1)
	var grow: float = 24.0 * float(extra_rows)
	var msz := MODE_SIZE + Vector2(0.0, grow)
	var holder := Control.new()
	holder.name = MODE_CARD_NAME
	holder.position = MODE_POS - Vector2(0.0, grow)
	holder.size = msz
	holder.custom_minimum_size = msz
	holder.pivot_offset = msz / 2.0
	## 卡底: 木告示牌 + 铜包角 + 顶铜条(menu/hud/modecard.png, PixelLab 新生成)。中段 TILE, 木纹不拉糊。
	var plate := _nine_rect("modecard.png", Vector4(20, 18, 20, 18), Rect2(Vector2.ZERO, msz))
	plate.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	plate.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	holder.add_child(plate)
	## 三行字(返工: 「太小太弱」): 赛制名 30 号最大; 规矩 17 号; 倒计时**单独一行、亮色 + 一条压暗底带**。
	##   右上角「赛程 »」告诉人这块能点(原来那行小字「本周赛程」读起来像标签, 不像入口)。
	var title := _place_outlined(str(lines[0]), MODE_TITLE_FONT, Color("#ffe9a8"), Vector2(18.0, 9.0), Vector2(180.0, 40.0))
	title.name = "ModeTitle"
	holder.add_child(title)
	var cap := _place_outlined("赛程 »", 18, Color("#ffd99a"), Vector2(MODE_SIZE.x - 18.0 - 100.0, 15.0), Vector2(100.0, 28.0))
	cap.name = "ModeHint"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(cap)
	var rule := _place_outlined(str(lines[1]), MODE_RULE_FONT, Color("#ecd9b0"), Vector2(18.0, 48.0), Vector2(rule_w, 26.0 + grow))
	rule.name = "ModeRule"
	if extra_rows > 0:
		rule.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	holder.add_child(rule)
	var band := ColorRect.new()
	band.name = "CountdownBand"
	band.color = Color(0.0, 0.0, 0.0, 0.30)
	band.position = Vector2(12.0, 75.0 + grow)
	band.size = Vector2(MODE_SIZE.x - 24.0, 24.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(band)
	var cd := _place_outlined(str(lines[2]), MODE_CD_FONT, Color("#ffc94a"), Vector2(18.0, 74.0 + grow), Vector2(MODE_SIZE.x - 36.0, 26.0))
	cd.name = "ModeCountdown"
	holder.add_child(cd)
	var btn := Button.new()
	btn.name = "ModeTap"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): plate.modulate = Color(1.2, 1.15, 1.08))
	btn.mouse_exited.connect(func(): plate.modulate = Color.WHITE)
	btn.pressed.connect(_open_week_popup)
	content_root.add_child(holder)
	_mode_box = holder
	## 弹层要盖在模式卡上面(重建时模式卡会排到最后)
	if is_instance_valid(_week_pop):
		content_root.move_child(_week_pop, -1)


## 本周赛程弹层的壳: 压暗遮罩 + 标题 + 「收起」+ 赛程条(`_week_strip` 往里放)。默认藏着。
## ★遮罩不是 Button(点哪都关): 点压暗处由色块自己的 gui_input 接 —— 不然它会被当成一个盖满全屏的「按钮」。
func _week_popup(paint_now: int) -> void:
	_week_pop = Control.new()
	_week_pop.name = WEEK_POPUP_NAME
	_week_pop.size = Vector2(W, H)
	_week_pop.visible = false
	_week_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 压暗色块**比设计框大一圈**(宽屏 1560 两侧也要压暗), 点它 = 关(返工: 点弹层外面也要能关)。
	## ★它只在弹层打开时 visible —— 藏着的时候它不能是一块「铺满视口又 STOP」的东西
	##   (verify_ui_layout ④ 按节点自己的 visible 量)。
	_week_dim = ColorRect.new()
	_week_dim.name = WEEK_DIM_NAME
	_week_dim.color = Color(0.03, 0.02, 0.01, 0.66)
	_week_dim.position = Vector2(-1000.0, -1000.0)
	_week_dim.size = Vector2(W + 2000.0, H + 2000.0)
	_week_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_week_dim.visible = false
	_week_dim.gui_input.connect(_on_pop_dim_input)
	_week_pop.add_child(_week_dim)
	## 表头一行(返工): 标题在左、「收起」在右, 同一行, 紧贴在条子上沿(留 4px)。
	var sx: float = (W - STRIP_W) / 2.0
	var row_y: float = POP_CY - 48.0 - 4.0 - 82.0
	var head := _place_outlined("本周赛程", 26, Color("#ffe9a8"), Vector2(sx + 4.0, row_y + 21.0), Vector2(300.0, 40.0))
	head.name = "WeekPopupTitle"
	_week_pop.add_child(head)
	var close := _plank_button("收起", _close_week_popup, Vector2(140.0, 82.0))
	close.name = "WeekPopupClose"
	close.position = Vector2(sx + STRIP_W - 140.0, row_y)
	_week_pop.add_child(close)
	content_root.add_child(_week_pop)
	_week_strip(paint_now)


## 弹层表头跟着条子的**真实**宽高走(条子宽由内容决定, 收盘块长了会撑宽): 标题左端对齐条子左沿,
## 「收起」右端对齐条子右沿, 两者同一行、贴在条子上沿上面 4px。
func _layout_pop_header(box: Control) -> void:
	if not is_instance_valid(_week_pop):
		return
	var r := Rect2(box.position, box.size)
	var close := _week_pop.get_node_or_null("WeekPopupClose") as Control
	var head := _week_pop.get_node_or_null("WeekPopupTitle") as Control
	if close != null:
		close.position = Vector2(r.end.x - close.size.x, r.position.y - 4.0 - close.size.y)
	if head != null and close != null:
		head.position = Vector2(r.position.x + 4.0, close.position.y + (close.size.y - head.size.y) / 2.0)


func _open_week_popup() -> void:
	if is_instance_valid(_week_pop):
		content_root.move_child(_week_pop, -1)
		_week_pop.visible = true
		_week_dim.visible = true


func _close_week_popup() -> void:
	if is_instance_valid(_week_pop):
		_week_pop.visible = false
		_week_dim.visible = false


func _on_pop_dim_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
			or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
		_close_week_popup()


# ─── 📅 本周赛程条 (贴底横条) ───
## v2 的核心是周赛制, 而玩家在主菜单上【完全看不到这周是怎么安排的】: 哪天积分赛、
## 哪天闯关、什么时候收盘, 全靠记。这条横着的七格就是干这个的。
##
## ★第一版做成了【中间一列竖排七行的日历表】, 连同右侧的赛季表格一起被用户否掉:
##   「市面上哪里有游戏会这么排版呢」。实拍参考里周期性/模式信息走的是
##   **底部一排横向卡**(King of Meat), 没有一张用竖排日历。⇒ 改成贴底横条。
##
## ★★E2/E4 的唯一 UI 落点: 赛程判定全程按 UTC(phase2_config 里那几个纯函数),
##   本地时区**只在 `_local_dict` 里做一次显示层换算**, 换算结果一个字节都不回流到判定。
##   门禁 verify_week_season ⑥ 焊死了这条: 判定层源码里不许出现本地时间 API。
## ★2026-10-04 收进 `phase2_config.WEEKDAY_CN`(时间穿越角标也要用同一份)。
const _WD_CN := _P2C.WEEKDAY_CN

## 赛程条的外框。★留引用是为了服务状态变化时能把它换掉(见 `_sb_poll`)。
var _week_box: Control = null
## 建这条赛程条时的服务状态。★存下来才知道"变没变" —— 只看当前值没法判断要不要重建。
var _sb_state_shown: String = ""


## D-1: 服务状态变了就重建赛程条(维护态要盖掉收盘倒计时)。
## ★判据是**状态变了**而不是"每秒都重建" —— 后者会让主菜单每秒扔一堆节点。
func _sb_poll() -> void:
	if _SB.take_update_hint(): _toast(_SB.UPDATE_HINT)   # E15: 服务端要求的最低版本高于本机 ⇒ 非阻塞提示一次
	var s: String = _SB.service_state()
	## ★★2026-10-03 周六实操 S16: 原来**只在服务状态变了才重画** ⇒ 倒计时停在打开主菜单那一刻
	##   (22:36 与 22:49 两张截图都写「距收盘 24 分 18 秒」), 22:50 的「已封盘」也永远出不来。
	##   ⇒ 右侧那一块要显示的东西(档位 + 剩余时间文字)变了也重画。
	if s == _sb_state_shown and _close_key(_strip_now()) == _close_key_shown:
		return
	rebuild_week_strip()


## 赛程条此刻用哪个时钟(与 `_week_strip` 同一条: strip_now_override → _now_ts())。
func _strip_now() -> int:
	return strip_now_override if strip_now_override > 0 else _now_ts()


## 右侧收盘块「要显示的内容」的指纹: 档位 + 剩余时间文字。变了就该重画。
var _close_key_shown: String = ""

func _close_key(now: int) -> String:
	var ph: String = _P2C.phase_at_utc(now)
	var left: int = _P2C.close_left_sec(now)
	var live: bool = (_P2C.phase_mode_live(_P2C.PHASE_FINALS)
		if strip_finals_live_override < 0 else strip_finals_live_override == 1)
	var kind := close_block_kind(ph, live,
		_SB.service_state() == _SB.ST_MAINTENANCE, left, _P2C.can_start_match_utc(now))
	## ★模式卡第三行(倒计时)也算进指纹: 休赛/决赛日那几天它数的是「距下一阶段」, 收盘块不变它也在变。
	return "%s|%s|%s|%s" % [ph, kind, _left_text(left) if left >= 0 else "", _mode_countdown(now)]


## 重建赛程条。★抽出来是因为实拍要在换过时钟之后再建一次 ——
##   就地再抄一遍那两行就是「手抄的副本必然落后」。
func rebuild_week_strip() -> void:
	if is_instance_valid(_week_box):
		_week_box.queue_free()
	_week_strip()
	## 模式卡的倒计时跟着同一次重画走(同一条钟: `_strip_now()`)。
	if is_instance_valid(content_root):
		_mode_card(_strip_now())


## ★只给门禁与实拍喂已知时刻; **产品一律不传**。
##   先例: `TeamSelectScene.lockout_now_override` / `GameState.ranked_quota_full(now)`。
##   ⚠ 为什么非要这个口子: 赛程条是**按星期分支**的东西 ⇒ 不给口子的话,
##     「周日那一格变成对阵图的门」只有周日才会被执行, 变异改坏了也没人红
##     (memory `fb-gate-subject-never-constructed`)。
var strip_now_override: int = 0

## ★同上, 只给门禁与实拍: 强制把「决赛日玩法上线了没有」当成 是/否。
##   **-1 = 问规则, 产品永远是这个**(`verify_finals_feed` 有一条断言守住默认值)。
##   为什么要这个口子: `PHASE_MODE_LIVE` 是 **const 字典**, Godot 4 里改不了内容 ⇒
##   实拍没法"临时把决赛日打开"再去真按一下那扇门。
var strip_finals_live_override: int = -1


## ★`paint_now` = 本屏那一刻(`_ready` 传); 0 = 自己问一次
##   (`rebuild_week_strip()` 走这一支 —— 它是**另一次刷屏**, 该读新的)。
func _week_strip(paint_now: int = 0) -> void:
	## ★UTC 纪元秒, 与本地时区无关
	## ★★★兜底走 `_now_ts()`, 不再就地读系统钟(2026-09-28)。
	##   原来这一行是主菜单上**第二条独立的时钟**: 把 `clock_override_ts` 钉在周六渲整屏时,
	##   状态行已经改说「闯关赛」, 而赛程条仍把**真实的那一天**标成「今」。
	##   实测(`tests/_probe_mmclock.gd`, 修前): 只注 `clock_override_ts` 逐日走一遍,
	##   **七天里六天**条上标「今」的格与注入日对不上 —— 对得上的只有
	##   “恰好是真实今天”那一天。memory `fb-second-clock-drops-events`。
	## ★`strip_now_override` 不删, 留作**更细的一层**(截图脚本 `shot_menu_to_bracket`
	##   与 `verify_week_strip` 在用); 但**真实时钟那条路只剩一条**:
	##   `_now_ts()` → `clock_override_ts` → `_P2C.now_utc()`。
	##   两个 override 都是 0 时行为**逐字节不变**(玩家路径一字未动)。
	var now: int = strip_now_override if strip_now_override > 0 \
		else (paint_now if paint_now > 0 else _now_ts())
	var today: int = _P2C.iso_weekday_utc(now)
	_sb_state_shown = _SB.service_state()
	var box := PanelContainer.new()
	## ★给它一个名字当**地址** —— 门禁要只量条内那 7 格。
	##   2026-09-27 探针扫全屏时把右侧「今天是什么日子」指示块的标签也数了进来,
	##   凭空多出一格(x=812 vs 条内 x=126)。**判据宽一格就会造出假 bug。**
	## ★名字只用来定位, **判据仍是相位序列**(与 `phase_of_weekday` 比), 不是名字本身。
	box.name = "WeekStrip"
	box.position = Vector2((W - STRIP_W) / 2.0, POP_CY - STRIP_H / 2.0)
	box.custom_minimum_size = Vector2(STRIP_W, STRIP_H)
	box.size = Vector2(STRIP_W, STRIP_H)
	## ★2026-10-05 第三轮: 条子从「贴底常驻」挪进本周赛程弹层, 在弹层里**竖向居中**。
	##   条高由子控件决定(常规 95; 周日那扇门也是 81 高的按钮) ⇒ `resized` 时按实际高度重算顶沿,
	##   不写死坐标(原来写死 y=636 那次, 周日被撑高后掉出屏幕)。
	box.resized.connect(func() -> void:
		if is_instance_valid(box):
			box.position = Vector2((W - box.size.x) / 2.0, POP_CY - box.size.y / 2.0)
			_layout_pop_header(box))
	var sb := StyleBoxFlat.new()
	## ★不描边 + 底色更实: verify_ui_consistency 的「网页盒」= 四边有边框 + 底半透明
	##   = CSS border+rgba 的长相(用户 2026-08-15「去掉 ai 味」时建的判据)。
	##   条子靠更实的底色跟背景分开就够了, 不需要 1px 金描边。
	sb.bg_color = Color(0.04, 0.10, 0.16, 0.94)
	sb.set_border_width_all(0)
	## ★直角不圆角: verify_ui_consistency 把「圆角盒」当网页感的指标(用户 2026-08-15「去掉 ai 味」),
	##   主菜单上限 3 个, 而赛程条一家就能凑 8 个(外框 + 七格)。像素风里圆角也本来就是异类。
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 7; sb.content_margin_bottom = 7
	## ★★★2026-09-28 外框上九宫格 `ui/panel-wide-flat.png`(不可点的底板 · 源图 80×48 · 边带 8)。
	##   **一个框, 不是七个** —— 七格各套一个实拍读成表格(理由见 `_week_day_cell` 头注)。
	## ★它对「文字压边带」是安全的: 这张图的实测 band = **5**(比另两张薄),
	##   而最靠边的字块距内沿还有 11px 以上(`tests/_probe_mmprofile.gd`)。
	## ⚠ content_margin **必须原样钉住 12/12/7/7**: StyleBoxTexture 默认拿
	##   texture_margin(8) 当 content_margin ⇒ 上下各 +1 ⇒ 条子长高 2px。
	##   而**周日**那天条高 = 门按钮 81 + 上下 margin, 顶沿 = 719 − 条高,
	##   实测顶沿与左栏栈底只差 **1px** ⇒ 多 2px 当场压住入口(门禁 ④ 那条)。
	## ★★2026-10-05 UI 重做: 冷色藏青金属框 → 铁箍木板(menu/hud/strip-plank.png, PixelLab 新生成)。
	##   原来那块藏青底 + 细边在暖色擂台上就是一个网页控件; 现在与左栏木牌、货币牌、训龟大师同一套材质。
	##   两端铁箍占 22px ⇒ 左右内边距 12 → 26。
	## ★★木纹**不许被拉伸**(用户:「木纹不要拉糊」): 贴图是烘好的 1400×95 长板,
	##   中段走 TILE —— 条子比贴图窄就是原像素裁出来, 一个像素都不缩放。
	##   竖向: 条高 = 格高 81 + 上下 7 = 95 = 贴图高 ⇒ 1:1(门禁 ⑯g 量这条)。
	var frame := StyleBoxTexture.new()
	frame.texture = load(HUD + STRIP_TEX)
	frame.texture_margin_left = 22; frame.texture_margin_right = 22
	frame.texture_margin_top = 11; frame.texture_margin_bottom = 12
	frame.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	frame.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	frame.content_margin_left = 26; frame.content_margin_right = 26
	frame.content_margin_top = 7; frame.content_margin_bottom = 7
	frame.modulate_color = Color(0.62, 0.55, 0.50)   # 木板压暗, 字才浮得出来(对比度)
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_theme_stylebox_override("panel", frame)
	## 放进本周赛程弹层(没有弹层时 —— 门禁单独调这一段 —— 退回内容层)。
	(_week_pop if is_instance_valid(_week_pop) else content_root).add_child(box)
	_week_box = box          # D-1: 服务状态变了要能把它换掉
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for wd in range(1, 8):
		h.add_child(_week_day_cell(wd, today))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	h.add_child(_week_close_block(now))


## 赛程条的一格 = 一天。上行周几、下行阶段名。
## 今天给金边金底; 已过去的天淡到 0.42 —— 一眼看出这周走到哪了。
func _week_day_cell(wd: int, today: int) -> Control:
	var ph: String = _P2C.phase_of_weekday(wd)
	var is_today := (wd == today)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(92, 0)
	var cs := StyleBoxFlat.new()
	cs.set_corner_radius_all(0)          # 同上: 七个格子也不圆角
	cs.content_margin_left = 6; cs.content_margin_right = 6
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	## 今天那格也不描边(同上)。改成更实的金底 + 顶部一条金色实条 ——
	## 实条是 ColorRect 不是 StyleBox, 既不算"盒", 在像素风里也比 1px 描边立得住。
	## ★★2026-09-27 材质层(用户:「全是 ai 味和网页味」)。
	##   原来**七格每格都有一块** `Color(1,1,1,0.05)` 的半透明底 —— 那正是 CSS 的
	##   `rgba(255,255,255,.05)`; 七块并排 + 一行细灰字, 屏幕上读起来是**网页的标签栏**。
	##   零边框零圆角只让它不被门禁判成"网页盒", 并没有让它变成游戏里的东西
	##   (判据量的是"有没有 border+rgba 那个长相", 不是"像不像游戏")。
	##
	## ★★我先试的是【给七格都套九宫格金属芯片 `chip-frame`】, **实拍之后退掉了**:
	##   chip-frame 源图 48×24, 拉到 92×54 之后那圈金属只剩 **1px 亮边** ——
	##   屏幕上就是七个细线描边的方盒, 比原来的半透明块**更像网页表格**。
	##   (这就是 `ui_skin.gd` 记的「贴图有它的最小可用尺寸」, 只是这次卡在"拉太大"那头;
	##    我是**量完 band=4 判定安全、拍完才看出来不对** —— 数值过关不等于长相过关。)
	##
	## ⇒ 改法是**把盒子拿掉**, 不是换一种盒子: 过去/未来的日子直接落在条子上,
	##   只有今天那格留一块实心金牌 + 顶上一条金边。一排日子 + 一块高亮牌,
	##   这是游戏里周历的长相; 七个等大的框是表格的长相。
	cs.bg_color = Color(1.0, 0.85, 0.24, 0.32) if is_today else Color(0, 0, 0, 0)
	## ★★★2026-09-28 今天那一格换成**九宫格亮牌** `ui/panel-wide-on.png`。
	##   上面那段说的「不换一种盒子」仍然成立 —— **只有今天这一格有牌子**,
	##   其余六天还是直接落在条子上。一排日子 + 一块亮牌 = 游戏里的周历;
	##   七个等大的框才是表格(上一轮四版对照实拍拍出来的, 不是推的)。
	## ★为什么把 4px 金条去掉: 牌子本身就是高亮, 再掞一条金条就是两层高亮叠着;
	##   而且那 4px 会把字块顶成 49px, 直接吃掉边带的余量。
	## ⚠ 贴图不在就退回原来的金底(`cs`) —— `UISkin.nine` 自带这一手。
	var skin: StyleBox = cs
	if is_today:
		## ★2026-10-05 UI 重做: 今天这格**不填底**, 与其余六天同一套明暗, 只套一圈黄铜边框
		##   (brass-frame.png = 铜牌挖空) —— 实心铜牌配深色字是反色, 一排里跳出来像个按下去的键。
		cs.bg_color = Color(0, 0, 0, 0)
		skin = UISkin.nine("menu/hud/" + STRIP_TODAY_TEX, 10, cs)   # 10 = 挖空的边界(tools/build_menu_hud.py), 就是那圈铜的真宽
		skin.content_margin_left = 6; skin.content_margin_right = 6
		skin.content_margin_top = STRIP_TODAY_PAD
		skin.content_margin_bottom = STRIP_TODAY_PAD
	cell.add_theme_stylebox_override("panel", skin)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
	## ★★七格**一律竖向居中**。不居中的话: 今天那格的内边距是 9(要避边带),
	##   其余格是 3, 而 HBox 会把七格拉成等高 ⇒ 一排日子的字会差出 6px, 读起来是歪的。
	## ★居中之后两种 margin 给出的**绝对位置完全相同**(内容区上下对称),
	##   七格自动齐 —— 不用再给其余六格也填一份跟着漂的 margin。
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(v)
	var d := Label.new(); d.text = _WD_CN[wd - 1]
	d.add_theme_font_size_override("font_size", STRIP_DAY_FONT)
	d.add_theme_color_override("font_color", STRIP_DAY_COL)
	d.add_theme_color_override("font_outline_color", Color("#140a03")); d.add_theme_constant_override("outline_size", 5)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var n := Label.new()
	## ★今天那格在名字后缀一个「今」——横条的格子只有 92px 宽, 光靠金边在缩略/小屏上读不出来;
	##   顺带让门禁能量到"恰好一天是今天"(竖排那版有「今天」标签, 改横条时漏掉了)。
	n.text = (str(_P2C.PHASE_LABEL.get(ph, ph)) + " 今") if is_today else str(_P2C.PHASE_LABEL.get(ph, ph))
	n.add_theme_font_size_override("font_size", STRIP_PHASE_FONT)
	n.add_theme_color_override("font_color", STRIP_PHASE_COL)
	n.add_theme_color_override("font_outline_color", Color("#140a03")); n.add_theme_constant_override("outline_size", 5)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	## ★★2026-10-04 台账 S15(两轮实操都记了「点别的天什么都不会发生」):
	##   七格并排 + 今天一块亮牌 = 页签的长相, 玩家就会去点 ⇒ 让它**点了有回应**:
	##   飘一行「那天是什么、谁能打」。不切页 —— 主菜单没有"别的天"的内容可切。
	## ★触摸线: 格高吃 ROW_H(81), 与全屏所有靶子同一条线; 条子因此恒为周日那天的高度(95),
	##   顶沿由 `resized` 那段贴底算出, 不是新的写死坐标。
	cell.custom_minimum_size = Vector2(84, ROW_H)
	var tap := Button.new()
	tap.name = DAY_TAP_PREFIX + str(wd)
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tap.pressed.connect(func() -> void: _toast(_week_day_note(wd)))
	cell.add_child(tap)
	## PanelContainer 会把子控件缩进 content_margin 里(今天那格上下各 9 ⇒ 只剩 63 高)。
	##   `sort_children` 在容器排完之后才发 ⇒ 这里把按钮铺回整格, 点击区 = 整格 92×81。
	cell.sort_children.connect(func() -> void:
		if is_instance_valid(tap) and is_instance_valid(cell):
			tap.position = Vector2.ZERO
			tap.size = cell.size)
	if wd < today:
		cell.modulate.a = 0.42
	return cell


## 赛程条每一格那个透明按钮的节点名前缀(+ 星期几 1~7)。门禁按它找, 不抄文案。
const DAY_TAP_PREFIX := "DayTap"


## 点了赛程条某一天飘的那一句: 那天打什么、谁能打。
## ★数字一律读规则常量(配额 / 晋级线), 不抄字面量。
func _week_day_note(wd: int) -> String:
	var ph: String = _P2C.phase_of_weekday(wd)
	## ★规矩那半句与模式卡同一份(`_phase_rule`), 不各写一遍。
	return "周%s %s · %s" % [str(_WD_CN[wd - 1]), str(_P2C.PHASE_LABEL.get(ph, ph)), _phase_rule(ph)]


## 条子右端的收盘块: 主行(倒计时/状态) + 副行(本地时刻)。
## 三种态各说各的话, 不拿一句话硬凑:
##   · 有收盘的阶段 → 倒计时 + 本地几点收盘
##   · 已进封盘窗口 → 直说"不开新局了", 因为这时点开始战斗会被拦下
##   · 休赛/决赛日 → 没有收盘概念(close_left_sec 返回 -1), 说各自该说的事
## 那一格属于哪一类。★**纯静态函数**, 门禁能把四个入参穷举着喂 ——
##   尤其「玩法上线了没有」这一维: `PHASE_MODE_LIVE` 是 const 字典, 改不动,
##   不抽出来门禁就只能等到真上线那天才验得了「门会出现」。
## ★顺序就是原来那串 if 的顺序, 一个都没挪: 维护 → 决赛日的门 → 玩法没上线 → 收盘。
const BK_MAINTENANCE := "maintenance"
const BK_BRACKET_DOOR := "bracket_door"      # ★决赛日玩法上线后: 进对阵图的门
const BK_PENDING := "pending"                # 玩法还没上线, 直说
const BK_NO_CLOSE := "no_close"              # 这个阶段没有收盘概念
const BK_LOCKED := "locked"                  # 已进封盘窗口
const BK_COUNTDOWN := "countdown"            # 距收盘还有多久
const BK_CLOSED_TODAY := "closed_today"      # 今天有收盘、而且已经收了(周五/周六 23:00 之后)
static func close_block_kind(phase: String, finals_live: bool, maintenance: bool,
		close_left: int, can_start: bool) -> String:
	if maintenance:
		return BK_MAINTENANCE
	if phase == _P2C.PHASE_FINALS and finals_live:
		return BK_BRACKET_DOOR
	## ★★到这里如果 phase 是 FINALS, 就说明 `finals_live == false` ⇒ 直接是「还没上线」那一档。
	##   **不许再去问 `phase_pending_note()`** —— 它读的是**全局常量** `PHASE_MODE_LIVE`
	##   而不是入参, 于是 2026-09-25 把开关翻成 true 之后, 连喂 `finals_live=false`
	##   的那一支也拿到 ""、掉进下面的 `BK_NO_CLOSE`。
	##   ⇒ 这个函数原本对 `finals_live` **只有一半是纯的**: 抽出入参的全部意义就是
	##     「门禁能在不改常量的前提下把两侧都验一遍」, 半纯等于白抽。
	##   (`verify_finals_feed` ⑤ 那条「没上线 ⇒ 是话不是门」当场红, 就是它抓到的。)
	if phase == _P2C.PHASE_FINALS:
		return BK_PENDING
	if _P2C.phase_pending_note(phase) != "":
		return BK_PENDING
	## ★★2026-10-03 周六实拍: 23:00 收盘之后 `close_left` 变负 ⇒ 原来落进 BK_NO_CLOSE,
	##   那一支只认「周日 / 其余当休赛日」⇒ 周六收盘后写着「休赛日 · 周二开赛 · 本日维护」,
	##   而明天就是决赛日。积分赛/闯关赛这两个**有收盘**的阶段收完盘要单独一档。
	if close_left < 0 and (phase == _P2C.PHASE_RANKED or phase == _P2C.PHASE_GAUNTLET):
		return BK_CLOSED_TODAY
	if close_left < 0:
		return BK_NO_CLOSE
	if not can_start:
		return BK_LOCKED
	return BK_COUNTDOWN


func _week_close_block(now: int) -> Control:
	_close_key_shown = _close_key(now)
	var ph: String = _P2C.phase_at_utc(now)
	var left: int = _P2C.close_left_sec(now)
	var head := ""
	var sub := ""
	var live: bool = (_P2C.phase_mode_live(_P2C.PHASE_FINALS)
		if strip_finals_live_override < 0 else strip_finals_live_override == 1)
	var kind := close_block_kind(ph, live,
		_SB.service_state() == _SB.ST_MAINTENANCE, left, _P2C.can_start_match_utc(now))
	## ★★D-1(2026-09-20): 后端**主动说自己在维护**时, 这一块盖掉赛程显示。
	##   方案书 U7/§4.7 拍板「版本维护期放在周一休赛, 停服 → 发版本 → 开服」,
	##   而在此之前玩家只会看到「连不上」⇒ 以为游戏坏了。
	##   ⚠ 只有 **MAINTENANCE** 这一态才盖: 「没配后端」(当前状态)与「连不上」都不盖 ——
	##     没配是有意关掉, 连不上是网络问题, 两者都不该在主菜单上喊话
	##     (网络层第一原则: 永远不能把游戏搞坏; 这里也不能把没事说成有事)。
	if kind == BK_MAINTENANCE:
		head = "维护中"
		var n := _SB.notice_text()
		sub = n if n != "" else "版本维护, 稍后回来"
		return _close_block_labels(head, sub)
	## ★★2026-09-22: 有些阶段的**玩法还没上线**(见 `phase2_config.PHASE_MODE_LIVE`) ⇒
	##   那三天实际走的是积分赛规则(照常开局、吃配额)。这一块必须**直说** ——
	##   在此之前周日写「决赛日 本地 X 点开打」、周一写「本日维护」, 而两天都能照常开局:
	##   玩家按字面读会以为自己错过了决赛、或者以为维护日不能玩。**说了做不到的事就是缺陷**。
	## ★★周日决赛日**玩法上线之后**, 这一格变成进对阵图的门。
	##   在此之前 `phase_mode_live(PHASE_FINALS)` 是 false ⇒ 走下面 BK_PENDING 那一支,
	##   **门根本不存在** —— 而不是摆一个点了没反应的按钮
	##   (memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor`: 没做出来的那一支
	##    要让「没上线」是个可读状态)。
	if kind == BK_BRACKET_DOOR:
		return _finals_entry()
	if kind == BK_PENDING:
		head = str(_P2C.PHASE_LABEL.get(ph, ph))
		sub = _P2C.phase_pending_note(ph)
		## ★兜底: 走到 BK_PENDING 而 `phase_pending_note()` 给空串, 只有一种情况 ——
		##   用 `strip_finals_live_override` 把决赛日**手动**按成"没上线"(截图台/调试用),
		##   而那张表里它其实已经上线了。不兜的话这一格会渲出一行空 Label。
		## ★★2026-09-28 摘掉开发状态。原文是「玩法开发中, 暂按积分赛规则」——
		##   「开发中」「暂按」是**开发备注**(玩家不需要知道我们做到哪了, 而「暂」
		##   还顺带许了个不存在的期限)。玩家要知道的只有一件事: **这天按什么规矩打**。
		##   与 `phase2_config.PHASE_PENDING_NOTE` 同一口径(那张表 2026-09-27 就改过,
		##   只剩这条兜底一直没跟上), 后半句一字不差 —— 那是两处共同的那条信息。
		## ★仍写字面量而不是去读那张表: 这一支的前提正是"那张表里查不到这个阶段"。
		if sub == "":
			sub = "规则同积分赛"
		return _close_block_labels(head, sub)
	if kind == BK_NO_CLOSE:
		if ph == _P2C.PHASE_FINALS:
			head = "决赛日"
			sub = "%s 开赛" % _local_hhmm(_utc_today_at(now, int(_P2C.FINALS_SEAT_HOUR_UTC)))
		else:
			head = "休赛日"
			sub = "周二开赛 · 本日维护"
	elif kind == BK_CLOSED_TODAY:
		head = "今日已截止"
		var _tmr: int = now + 86400
		var _tph: String = _P2C.phase_at_utc(_tmr)
		if _tph == _P2C.PHASE_FINALS:
			sub = "明天决赛日 · %s 开赛" % _local_hhmm(_utc_today_at(_tmr, int(_P2C.FINALS_SEAT_HOUR_UTC)))
		else:
			sub = "明天%s" % str(_P2C.PHASE_LABEL.get(_tph, ""))
	elif kind == BK_LOCKED:
		head = "已截止"
		sub = "截止前 %d 分钟停止匹配" % int(_P2C.CLOSE_LOCKOUT_SEC / 60)
	else:
		head = "距截止 %s" % _left_text(left)
		sub = "本地 %s" % _local_stamp(now + left)
	## ★周六(闯关赛上线时)这一块是赛况板的门: 收盘前、封盘、收盘后都开着(收盘后正是看全场结果的时候)。
	if ph == _P2C.PHASE_GAUNTLET and _P2C.phase_mode_live(_P2C.PHASE_GAUNTLET) \
			and kind in [BK_COUNTDOWN, BK_LOCKED, BK_CLOSED_TODAY]:
		return _gauntlet_board_entry(head, sub)
	return _close_block_labels(head, sub)


## 周日决赛日那扇门通到哪。★具名常量 —— 门禁拿它去验"目标场景真的存在",
##   写死成字符串的话门禁就只能自己再抄一遍(抄一次永远落后一次)。
const BRACKET_SCENE := "BracketMap"


## 周日决赛日的门。★一整块都能按 —— 那一格本来就只有两行字, 做成"字旁边一个小按钮"
##   反而更难点中(触控下限 81px 是全项目同一条线)。
func _finals_entry() -> Control:
	## ★★2026-09-27 去掉行尾的「→」。它跟上面状态行那个「›」是同一族:
	##   网页的「更多 →」写法 —— 用一个箭头告诉人"这里可以点"。
	##   这一整块本来就是一个 150×81 的按钮(触控下限), 不需要箭头来交代。
	return _door("决赛日\n看对阵图", _open_bracket_map)


## 周六赛况板那扇门(周末看回放 2026-10-04, docs/plans/20261004-周末看回放.md)。
## ★与周日「看对阵图」**同一扇门**(`_door`: 同一张 `ui/panel-wide.png`、同一个尺寸) —— 不另造一种长相。
## ★原来那两行(倒计时 / 收盘时刻或「明天决赛日 · 几点开打」)**一字不动**, 第三行说点进去看什么 ——
##   第一版把第二行让给了「全场赛况」, `verify_week_strip` ⑥ 当场红: 周六收盘后那句「明天决赛日 · 本地 X 开打」没了。
##   ⇒ 不是把字塞进 Button.text(Button 不按内容长宽), 而是**一块贴着内容的牌子 + 盖一层透明按钮**
##   (与战绩页回放行同一个做法)。牌子皮与周日那扇门同一张 `ui/panel-wide.png`, 高度同为 81(触控下限)。
const GAUNTLET_BOARD_SCENE := "GauntletBoard"
const GAUNTLET_BOARD_LINE := "全场赛况"


func _gauntlet_board_entry(head: String, sub: String) -> Control:
	var pc := PanelContainer.new()
	pc.name = "GauntletBoardPlate"
	pc.custom_minimum_size = Vector2(172, 81)   # 2026-10-05: 铜牌边 14px, 150 宽装不下「距收盘 X 小时 Y 分」
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.05, 0.16, 0.15, 0.94)
	fsb.set_border_width_all(0)
	fsb.set_corner_radius_all(0)
	var skin: StyleBox = UISkin.nine("menu/hud/brass.png", 14, fsb)   # 2026-10-05 UI 重做: 黄铜门牌
	skin.content_margin_left = 12; skin.content_margin_right = 12
	skin.content_margin_top = 6; skin.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", skin)
	var v: Control = _close_block_labels(head, sub)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 黄铜门牌上用深色字(收盘块默认是给木板配的亮字 + 深描边, 压在铜上读不出)
	for lab in v.get_children():
		if lab is Label:
			(lab as Label).add_theme_color_override("font_color", Color("#2a1400"))
			(lab as Label).add_theme_constant_override("outline_size", 0)
			(lab as Label).add_theme_font_size_override("font_size", 14)
	var go := Label.new()
	go.text = GAUNTLET_BOARD_LINE
	go.add_theme_font_size_override("font_size", 14)
	go.add_theme_color_override("font_color", Color("#5a1a08"))
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(go)
	pc.add_child(v)
	var b := Button.new()
	b.name = "GauntletBoardDoor"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	## 按下 / 悬停的反馈打在整块牌子上(与 `_door` 同一组系数)
	b.mouse_entered.connect(func() -> void: pc.self_modulate = Color(1.22, 1.22, 1.22))
	b.mouse_exited.connect(func() -> void: pc.self_modulate = Color.WHITE)
	b.pressed.connect(_open_gauntlet_board)
	pc.add_child(b)
	return pc


func _open_gauntlet_board() -> void:
	_go(GAUNTLET_BOARD_SCENE)


## 赛程条右端那扇门(周日对阵图 / 周六赛况板共用)。
func _door(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 81)
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("#2a1400"))
	b.add_theme_color_override("font_hover_color", Color("#2a1400"))
	## ★★2026-09-27 上皮。原来它用的是 **Godot 默认皮**(圆角纯灰), 与全屏其它按钮完全两个味。
	##   `verify_ui_consistency` 的第 3 条判据一直在守这个, 但它**一周只在周日露面**
	##   —— 今天(UTC 周日)才第一次被抓到。又一条「判据挂在星期几上」:
	##   门禁没错、按钮也一直是错的, 只是两者一周才碰面一次。
	## ★★**零圆角、零边框** —— 这是本屏(以至全项目)的口径, 不是我随手定的:
	##   `verify_ui_consistency` 的第 1/2 条(网页盒 / 圆角盒)是**只降不升的棘轮**,
	##   而主菜单那一格记的是 **0**。我第一版加了 2px 边框 + 8px 圆角, 当场把这两条顶红
	##   —— 判据是对的: 圆角 + 半透边框是"网页味"，像素风里立不住。
	##   ⇒ 照旁边那几块面板的做法(`sb.set_border_width_all(0)` / `set_corner_radius_all(0)`)。
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.05, 0.16, 0.15, 0.94)
	fsb.set_border_width_all(0)
	fsb.set_corner_radius_all(0)
	## ★**不设 content_margin**: 第一版加了 10/6, 把按钮撑宽 ⇒ `verify_ios_ui`「全在屏内」
	##   与 `verify_mainmenu_layout`「都在 1280×720 内」双双判红(越界 18 个)。
	##   这一格的尺寸由 `custom_minimum_size` 定死(150×81, 触控下限), 皮只管颜色。
	## ★★2026-09-27 **试过换九宫格金属皮, 实拍后退掉了** —— 记在这里免得下次再试一遍。
	##   想法是对的(纯色块没有材质, 跟旁边的木牌不是一个世界), 但这个尺寸没有合适的贴图:
	##     · `UISkin.button()` 会按尺寸自动挑 `menu/frame-rect.png`(150×81 判为"大"),
	##       而它**边带实测 27px**, 上下 27+28=55, 装不下两行 15 号字(约 40 高)
	##       ⇒ `verify_ui_consistency` 第 11 条「文字压边带」当场 +1(主菜单基线 2, 只降不升)。
	##     · 退而用 `chip-frame`(边带 4px, 数值上完全安全) —— 但它源图只有 48×24,
	##       拉到 150×81 之后那圈金属只剩 **1px 亮边**, 实拍就是一个**细线描边的青色方框**,
	##       比原来的纯色块更像网页按钮。**量得过 ≠ 长得对**, 拍了才知道。
	##   ⇒ 真正的修法是给这个尺寸画一张自己的九宫格 —— **2026-09-28 画好了**。
	## ★★★2026-09-28 上皮: `ui/panel-wide.png`(可点的门 · 源图 80×48 · 边带 8 · 中段纯色
	##   · alpha 全 255 ⇒ 不用补 expand margin)。
	## ⚠ **不走 `UISkin.button()`**: 它的 `big` 判据(短边 ≥56 且面积 ≥5000)会让
	##   150×81 又去挑 `menu/frame-rect.png` —— **就是上面记的那张边带 27 的**。
	## ★竖向预算(实测 `tests/_probe_mmprofile.gd`): 这张图 band = **7**,
	##   门 150×81 ⇒ 内容区 67px, 两行 15 号字 45px 居中 ⇒ 上下各余 11px。
	##   (frame-rect 那张 27×2=54 ⇒ 内容区只剩 27, 装不下 —— 差得就是这么远。)
	var fnine: StyleBox = UISkin.nine("menu/hud/brass.png", 14, fsb)   # 2026-10-05 UI 重做: 黄铜门牌
	b.add_theme_stylebox_override("normal", fnine)
	## 三态: 贴图在就用 modulate 提亮/压暗(与 `UISkin.button` 同一招、同一组系数);
	##   贴图缺了 `UISkin.nine` 退回 fsb, 这里就走原来的换底色。
	var fhov: StyleBox = fnine.duplicate()
	var fprs: StyleBox = fnine.duplicate()
	if fnine is StyleBoxTexture:
		(fhov as StyleBoxTexture).modulate_color = Color(1.22, 1.22, 1.22, 1.0)
		(fprs as StyleBoxTexture).modulate_color = Color(0.74, 0.74, 0.74, 1.0)
	else:
		(fhov as StyleBoxFlat).bg_color = Color(0.09, 0.26, 0.24, 0.98)
		(fprs as StyleBoxFlat).bg_color = Color(0.09, 0.26, 0.24, 0.98)
	b.add_theme_stylebox_override("hover", fhov)
	b.add_theme_stylebox_override("pressed", fprs)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b


## ★具名方法(不是匿名闭包): 门禁量 `pressed.get_connections()` 时能看到方法名,
##   匿名闭包只能看到"有一个连接" —— 那就只能写出假判据。
func _open_bracket_map() -> void:
	_go(BRACKET_SCENE)


## 收盘块的两行标签。★抽出来是因为上面维护态那条要提前 return, 而**两条路必须长得一样** ——
##   就地再写一份 Label 就是「手抄的副本必然落后」(本项目记过)。
func _close_block_labels(head: String, sub: String) -> Control:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
	## ★同七格: 竖向居中。不居中的话它会被 HBox 拉成满高而字靠顶,
	##   与旁边居中的七格差出九几像素(实测 643 vs 652)。
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var a := Label.new(); a.text = head
	a.add_theme_font_size_override("font_size", 16)
	a.add_theme_color_override("font_color", Color("#ffd93d"))
	a.add_theme_color_override("font_outline_color", Color("#1e0f04")); a.add_theme_constant_override("outline_size", 5)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(a)
	var b := Label.new(); b.text = sub
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color("#ecd5a8"))
	b.add_theme_color_override("font_outline_color", Color("#1e0f04")); b.add_theme_constant_override("outline_size", 4)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(b)
	return v


## 剩余秒 → 人话。跨天时说"天/小时"比说 47:00:00 好读。
func _left_text(sec: int) -> String:
	if sec >= 86400:
		return "%d 天 %d 小时" % [sec / 86400, (sec % 86400) / 3600]
	if sec >= 3600:
		return "%d 小时 %d 分" % [sec / 3600, (sec % 3600) / 60]
	return "%d 分 %02d 秒" % [sec / 60, sec % 60]


## 当天(UTC)的某个整点 → unix 秒。用来把 FINALS_START_HOUR_UTC 变成一个具体时刻。
func _utc_today_at(ts: int, hour: int) -> int:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	var secs: int = int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))
	return ts - secs + hour * 3600


## ★★全局唯一的时区换算点(E2/E4)。判定层永远是 UTC, 只有【说给玩家听】的时候才翻译。
##   陷阱: `get_time_zone_from_system().bias` 的单位是**分钟**不是小时。
##   把偏移加到 UTC 秒上、再用 UTC 版的 from_unix_time 格式化 = 玩家墙上的时间。
func _local_dict(utc_ts: int) -> Dictionary:
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))   # 分钟
	return Time.get_datetime_dict_from_unix_time(utc_ts + bias * 60)


func _local_stamp(utc_ts: int) -> String:
	var d := _local_dict(utc_ts)
	var w: int = int(d.get("weekday", 0))
	var wi := 7 if w == 0 else w
	return "周%s %02d:%02d 截止" % [_WD_CN[wi - 1], int(d.get("hour", 0)), int(d.get("minute", 0))]


func _local_hhmm(utc_ts: int) -> String:
	return _P2C.local_hhmm(utc_ts)


# ─── 路由 ───
## 切场景。找不到目标 → 不切、打印错误 (原来直接 change_scene_to_file, 打错名字就静默黑屏)
func _go(scene: String) -> void:
	var path := "res://scenes/%s.tscn" % scene
	if not ResourceLoader.exists(path):
		push_error("[MainMenu] 目标场景不存在: " + path)
		return
	get_tree().change_scene_to_file(path)


## 商店入口: 大轮未打第一场 → 上锁不进(用户2026-07-18); 打完第一场解锁
func _open_shop() -> void:
	var block: String = _shop_block_msg(_now_ts())
	if block != "":
		_toast(block)
		return
	_go("Shop")


## 现在能不能进商店? 返回**要飘给玩家的那句话**; 空串 = 放行。
##
## ★★★它同时是**画在商店那行上的锁**的唯一来源(`_build_page_buttons` 读它) ——
##   原来这两处各写了一遍同样的三条公式, 改一处漏一处就是「锁画在那儿而门是开的」
##   (本函数上一版的头注就为这件事写过警告, 而警告防不住第二份公式)。
## A4(2026-09-17): three reasons, each with its own message - same wording as
##   _start_battle_flow so the player never sees two different names for one state.
##   Quota-full also locks the shop (user decision: stop completely when the quota is used up).
## ★★`ts` 必须由调用方传 —— 不传的话这个入口跟着今天星期几变: `ranked_quota_full()`
##   内部先问 `phase_uses_ranked_quota(phase_at_utc(ts))`, UTC 周六/周日不吃积分赛配额
##   ⇒ 恒返回 false ⇒ **配额打满的人在周末照样进得了商店**。
##   (这是真行为差异, 不只是门禁的事: 周末该不该锁店是玩法问题, 而原来它是
##    "跟着星期几悄悄变"—— 现在至少变成一个可注入、可验的量。)
## ★三条的**先后顺序有意义**, 与 `_battle_block_msg` 同一个排法: 命尽是最终态、
##   配额是本周期上限、没开店只是"还没到"。
##
## A4(2026-09-17 user decision): quota full also locks the shop.
## WARNING: this function affects FIVE gates that rely on setting season_total_battles=3
##   (verify_shop_layout / shop_merge_pips / shop_persist / ui_consistency / ui_layout).
##   None of them sets ranked_used => on a fresh CI save ranked_used=0 < quota,
##   so they happen NOT to be locked. That is luck, not design: if someone sets the
##   quota to 0 or feeds those gates a ranked_used, all five go red at once -
##   do not chase it as a product regression then.
func _shop_block_msg(ts: int) -> String:
	match _shop_block_kind(ts):
		SHOP_LOCK_OUT:
			return _msg_eliminated()
		SHOP_LOCK_QUOTA:
			return _msg_quota_full()
		SHOP_LOCK_FIRST:
			return "🔒 完成本大轮首场对战后解锁商店"
	return ""


## 商店锁的三种原因。★公式只住在 `_shop_block_kind` 一处 ——
##   长句(点了飘的 toast)与短句(常驻在那一行下面的小字)都从它翻译, 不各判一遍。
const SHOP_LOCK_OUT := "out"
const SHOP_LOCK_QUOTA := "quota"
const SHOP_LOCK_FIRST := "first"


## 现在锁着的话是哪一条原因; 空串 = 放行。顺序与 `_battle_block_msg` 同(见上)。
func _shop_block_kind(ts: int) -> String:
	if GameState.is_eliminated():
		return SHOP_LOCK_OUT
	if GameState.ranked_quota_full(ts):
		return SHOP_LOCK_QUOTA
	if int(GameState.season_total_battles) <= 0:
		return SHOP_LOCK_FIRST
	return ""


## 常驻在商店那一行下面的**短**原因(方案书 20260917 P1-4 / 验收「不点不弹 toast 也看得见」)。
## ★原来锁的理由只在 toast 里活 2.6 秒 —— 不点就永远不知道为什么锁。
## ★要短: 左栏一行只有 ~300px; 「下一步去哪」那半句留给 toast(长句)说。
## 空串 = 没锁。
func _shop_lock_reason(ts: int) -> String:
	match _shop_block_kind(ts):
		SHOP_LOCK_OUT:
			return "本大轮已出局"
		SHOP_LOCK_QUOTA:
			return "本周场次已用完"
		SHOP_LOCK_FIRST:
			return "首场对战后解锁"
	return ""


## ★★拦截提示的文案放这两个函数里 —— 商店入口与开打入口原来**各写了一份同样的字符串**,
##   改一处漏一处就是「同一个状态两个名字」(memory fb-hand-rolled-copies-drift)。
## ★★2026-09-22: 原文案「等周六闯关赛(开赛观战)」**说的是做不到的事** ——
##   当时闯关赛玩法一行没写(现在 E-A 已落地), 观赛入口更是 F 阶段的事;
##   玩家按字面读会周六打开游戏找闯关赛, 然后发现还是原来那个积分赛。
##   ⇒ 没上线时说**真的会发生的那件事**: 下周一换新的一轮(自然周锚点, UTC 周一 00:00)。
##   玩法上线后自动换回原文案, 不用再记得改这里。
## 这一周后面**还有闯关赛可打吗**? 三个条件缺一不可。
## ★★提示语问的是这个, 不是"开关翻了没有" —— 同样打满配额的两个人,
##   晋级了的那个周六真有东西打, 没晋级的那个要等下周一。跟开关走就会对其中一个说谎。
##
## ★★★2026-09-28 修: 原来第二条问的是 `gauntlet_eligible()`(= `promoted`), 而
##   `promoted` 全仓**只有 `settle_ranked_close()` 一个写入点**, 那个函数开头就
##   「周五 23:00 UTC 之前直接 return」⇒ **周一~周五这一支结构上恒假**。
##   于是 `season_wins=20`(线=5)、配额打满的人, 周一~周五被告知「下周一开新的一轮」——
##   而他周六铁定有 6 场可打。**这个函数自己的头注(上面那两行)写的就是要防这件事,
##   而那件事正发生在它自己身上。**(探针 `tests/_probe_promote_ahead.gd`:
##   「周六闯关赛见」在 `promoted=false` 时七天 0 次出现。)
## ⇒ 收盘前该问的是「**胜场过没过晋级线**」(`GameState.gauntlet_line_reached()`),
##   收盘后 `promoted` 已经是事实 ⇒ 两个**取并集**, 缺一不可:
##     · 只问线 —— 收盘后被清过场次的边角状态会漏(线是 `season_wins`, 不是存档标记);
##     · 只问 `promoted` —— 就是上面那个 bug。
func _gauntlet_ahead() -> bool:
	if not _P2C.phase_mode_live(_P2C.PHASE_GAUNTLET):
		return false                      # 闯关赛玩法还没上线
	if not (GameState.gauntlet_eligible() or GameState.gauntlet_line_reached()):
		return false                      # 收盘算过了没晋级, 而且胜场也没到线
	return _P2C.gauntlet_can_play(int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))


## 「周六还有东西打」这半句话怎么说。空串 = 这一周到此为止。
## ★★收盘前后**不是同一句话**, 这一条是诚实度的分界:
##     收盘后 `promoted` 已经算出来了 ⇒ 「你已晋级」是既成事实;
##     收盘前谁也没算过 ⇒ 只能说**已知的那件事**:「胜场过了晋级线」。
##   查实(见 `GameState.gauntlet_line_reached()` 头注三条): 晋级判据里只有胜场、
##   没有名额上限也没有排名截断、`season_wins` 只增不减 ⇒ 过了线就一定会晋级,
##   所以这里敢接「周六闯关赛见」。**将来加了名额/排名线, 要改的是那个函数的头注与这一句。**
func _gauntlet_ahead_tail() -> String:
	if not _gauntlet_ahead():
		return ""
	if GameState.gauntlet_eligible():
		return "但你已晋级, 周六闯关赛见"
	return "但你已过晋级线, 周六闯关赛见"


func _msg_eliminated() -> String:
	## ⚠ 0 命**不等于**没资格: 5 胜 + 8 负 = 13 场, 完全可能既淘汰又晋级。
	##   原稿的终榜排序是「胜场 > 余命 > 横扫」, 余命只是第二键, 不是门槛。
	var tail: String = _gauntlet_ahead_tail()
	if tail != "":
		return "💀 本大轮已出局 · %s" % tail
	return "💀 本大轮已出局 · 下周一开新的一轮"


func _msg_quota_full() -> String:
	var q: int = int(_P2C.RANKED_QUOTA)
	var tail: String = _gauntlet_ahead_tail()
	if tail != "":
		return "📋 本周配额 %d 场已打满 · %s" % [q, tail]
	return "📋 本周配额 %d 场已打满 · 下周一开新的一轮" % q


## 周六点「开打」被拦住时说什么。返回空串 = 没拦, 可以开。
## ★与 `GameState.gauntlet_can_play()` **共用同一组判据**(`phase2_config.gauntlet_state`),
##   这里只负责把状态翻译成人话 —— 就地再写一遍 `if wins >= 4` 就是同一判据存两份。
##
## ★★★2026-09-28: 这两把锁原来**都不指下一步**, 而同族的每一句都带
##   (「下周一开新的一轮」/「周六闯关赛见」)。周六是这两句唯一的出场日,
##   玩家当天读完就该知道"接下来去哪"：
##     · 没晋级那句里的「积分赛」指周二~周五, **本周已经过去了** ⇒ 必须写清是下周一,
##       而且把门槛写出来(线在 `PROMOTE_WINS`, 不抄数字);
##     · 刚晋级那句只说了"到此为止", **没告诉他明天有决赛日** ⇒ 他周日不来,
##       座位空着、桶还可能卡住。
func _msg_gauntlet_block() -> String:
	if not GameState.gauntlet_eligible():
		## ★2026-10-03 周六实操 S13: 14 胜 / 16 胜的人被告知「打够 11 胜就能来」——
		##   晋级是「胜场过线 **且** 没淘汰」(gauntlet_line_reached), 这句原来不分是哪一条没过。
		if GameState.is_eliminated() and int(GameState.season_wins) >= int(_P2C.PROMOTE_WINS):
			return "🔒 本周没晋级 · 积分赛命用完了 · 下周一开新的一轮"
		return "🔒 本周没晋级 · 下周一开新的一轮, 积分赛打够 %d 胜就能来" % int(
			_P2C.PROMOTE_WINS)
	var st: String = GameState.gauntlet_state()
	if st == _P2C.GAUNTLET_IN:
		return "✅ 已晋级决赛日 · 闯关赛到此为止(%s) · 明天周日参加决赛日" % _P2C.gauntlet_label(
			int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	if st == _P2C.GAUNTLET_OUT:
		return "💀 闯关赛已出局(%s) · 下周一开新的一轮" % _P2C.gauntlet_label(
			int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	return ""


## 轻提示: 顶部飘一行金字, 停 2.6s 后淡出。
##
## ★★2026-09-29 停留从 1.4+0.5 加到 2.6+0.6(台账 ④「点下去有提示但只活 1.9 秒」)。
##   1.9 秒读不完「📋 本周配额 24 场已打满 · 下周一开新的一轮」这种双句提示。
## ★★**位置动不了**, 而这不是懒: 主菜单竖向是排满的(剖面见 `_status_row` 头注 ——
##   LOGO 4.5..205.5 / 状态行 210..291 / 四个入口 299..623 / 赛程条 624..720,
##   栈底与条顶只差 1px)。**任何 y 都会压住别的东西** ⇒ 与其挪个位置压别人,
##   不如让这行字不再是唯一的通道: 锁现在是**画在按钮上的静态状态**
##   (灰框 + 🔒 角标, 见 `_build_page_buttons` 里 `battle_locked`),
##   提示退回它本来的角色 —— 解释为什么。
## 主菜单提示条的左边界: 左上角 Logo 的右缘(Logo 约 x 70~410)再留一点。
const TOAST_LEFT_PX := 530.0

func _toast(msg: String) -> void:
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vw := get_viewport_rect().size.x
	## ★2026-10-03 周六实操台账 S11: 固定 640 宽居中, 长句(「✅ 已晋级决赛日 · 闯关赛到此为止(4-0) · 明天周日来打决赛日」)
	##   溢出到左上角 Logo 上。⇒ 只占 Logo 右边那一段, 放不下就折行。
	var left := TOAST_LEFT_PX
	t.position = Vector2(left, 128.0); t.size = Vector2(maxf(320.0, vw - left - 30.0), 40)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.z_index = 200
	add_child(t)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(t, "modulate:a", 0.0, 0.6)
	tw.tween_callback(t.queue_free)


## 开始战斗 → 选龟流程 (实时版): 选龟(TeamSelect) → 匹配(Matchmaking) → 2.5D 战斗(RealtimeBattle3D).
##   非教程的常规入口. mode 置 single (含经济, 非教程标记). 进选龟前清掉上局对手快照, 让 Matchmaking 重抽.
## 开局拦截。★★A4(大轮赛制 v2·2026-09-17): 从【一个闸】拆成【三种原因各自一条提示】——
##   原来不管为什么打不了, 玩家只看到「赛季已淘汰」, 而配额打满和不在开赛时段都不是"淘汰"。
## ★三条的**先后顺序有意义**: 命尽是最终态(重置存档才解)、配额是本周期上限(等下一阶段)、
##   阶段不对只是"现在不行"。按"多严重"排, 玩家看到的是最根本的那条原因。
## 现在能不能开局? 返回**要飘给玩家的那句话**; 空串 = 放行。
##
## ★★E-A(2026-09-22): **周六走闯关赛自己的闸**, 不走积分赛那两条。
##   两套闸的差别不是"多一条少一条", 是**判据完全不同**:
##     · 积分赛: 0 命锁死 + 24 场配额
##     · 闯关赛: 有没有资格 / 4 胜晋级 / 3 负出局, **而且 0 命不锁**
##       (5 胜 + 8 负 = 13 场 ⇒ 完全可能既淘汰又晋级; 余命在终榜里只是第二排序键)
##   把它们塞进同一串 if 迟早会把"淘汰"这条错误地盖到周六头上。
##
## ★★为什么要 `now` 这个入参: 不给的话, 周六那条分支**只有周六跑门禁才会被执行**
##   —— 实测变异(把周六分支整个关掉)一条门禁都没红, 因为那天是周二
##   (memory `fb-gate-subject-never-constructed`)。产品调用一律不传, 只有门禁传。
##   先例: `GameState.ranked_quota_full(now)`、`TeamSelectScene.lockout_now_override`。
func _battle_block_msg(now: int = 0) -> String:
	## ★兜底同样走 `_now_ts()`(2026-09-28): 否则这里就是本文件的第三条时钟。
	##   产品路径(`_start_battle_flow`)本来就传 `_now_ts()` ∴ 行为逐字节不变。
	var ts: int = now if now > 0 else _now_ts()
	if _P2C.phase_at_utc(ts) == _P2C.PHASE_GAUNTLET \
			and _P2C.phase_mode_live(_P2C.PHASE_GAUNTLET):
		return _msg_gauntlet_block()
	## ★★★周日也要有一支(2026-09-27)。原来只有周六, 而周日**不吃积分赛配额**
	##   (`phase_uses_ranked_quota(FINALS)` = false, 因为玩法已上线) ⇒ 周日是唯一
	##   「不吃配额 + 没有拦截」的一天 = **可以无限刷积分赛**, 七天实测只有它是【可打】。
	##   而匹配是严格同场次的 ⇒ 周日刷完的人下周只配得到机器人。
	## ★与周六同一个形状: 挂 `phase_mode_live` 闸(没上线就别分流过去 ——
	##   memory `fb-branch-to-an-unbuilt-mode-is-a-backdoor`)。
	## ★「已晋级」取 `gauntlet_state()`, 与赛程条/闯关赛那支同一处判据。
	if _P2C.phase_at_utc(ts) == _P2C.PHASE_FINALS \
			and _P2C.phase_mode_live(_P2C.PHASE_FINALS):
		## ★两个维度分开传: 「进没进决赛日」与「有没有拿到闯关赛资格」不是一回事,
		##   混成一个 bool 就会说出「你已晋级」和「本周没晋级」这种自相矛盾的话。
		##   `_gauntlet_ahead()` 是周一~五那句用的同一处判据 —— 口径必须一致。
		return _P2C.finals_block_msg(
			GameState.gauntlet_state() == _P2C.GAUNTLET_IN,
			GameState.gauntlet_eligible())
	if GameState.is_eliminated():   # 大轮淘汰锁(用户2026-07-24): 0命封匹配, 只重置存档解锁
		## ★U9 拍板(2026-09-16):「0 命的话就只能等到周 6 周日观赛了, 不再打表演赛」
		##   ⇒ 文案从「设置→重置存档」改成指向观赛。观赛入口在 F 阶段, 先把话说对。
		return _msg_eliminated()
	if GameState.ranked_quota_full(ts):
		return _msg_quota_full()
	return ""


## ★★★门禁用的「现在是哪一刻」注入口。**0 = 用真实时钟**(玩家路径一字不动)。
##
## 为什么非有它不可(2026-09-26): `_battle_block_msg(now)` 早就收 `now` 了,
## 但 `_start_battle_flow()` 调它时**不传** ⇒ 这个入口的行为**跟着今天星期几变**。
## 后果不是"判据偶发红", 而是: UTC 周六时**已晋级的 0 命玩家可以打闯关赛**
## ⇒ 这个函数一路走到 `change_scene_to_file` ⇒ **当场把门禁自己拆掉**
## (`get_tree()` 变 null), 后面所有断言连跑都没跑,
## 而且**没打 ALL PASS**、rc 还是 0 —— 单跑时看着像"5 条断言红了", 实际是整份没跑完。
## ⇒ 与 `strip_finals_live_override` 同一条路子: 把"那一刻"做成可注入,
##   门禁钉住一个确定的日子, 玩家路径完全不变。
var clock_override_ts: int = 0

## ★兜底走 `_P2C.now_utc()` 而不是就地读系统时钟(2026-09-28): 那条是**全局**时间缝
##   (`phase2_config.now_override_ts`, 默认 0 = 真实时钟)。本函数的默认行为
##   **逐字节不变**(两个 override 都是 0 时 `now_utc()` 就是 `Time.get_unix_time_from_system()`),
##   但端到端门禁从此能用一处缝把整屏(主菜单 + 匹配 + 赛程判定)钉在同一刻 ——
##   两条互不相通的时钟正是 memory `fb-second-clock-drops-events` 那一族。
func _now_ts() -> int:
	_clock_reads += 1
	return clock_override_ts if clock_override_ts > 0 else int(_P2C.now_utc())


## 门禁用: 「这一屏问了几次现在几点」的计数。一屏刷完应该恰好 **1**。
##
## ⚠★它单独不成判据 —— 数的是我自己插的计数器(memory
##   `fb-gate-must-measure-requirement-not-my-hook`)。有人绕过 `_now_ts()` 直接
##   `Time.get_unix_time_from_system()` 它数不到。★所以 `verify_quota_clock` 里
##   它**总和一条源码扇一起**用: 本文件里 `Time.get_unix_time_from_system` 必须 0 次,
##   `_P2C.now_utc()` 只允许出现在 `_now_ts()` 里。两条合起来才堵得住。
## ★恰好 1 而不是“≤N”: 数到 0 说明这一屏根本没建起来(空检查),
##   数到 ≥2 说明又有人自己去问钟了。
var _clock_reads: int = 0


func _start_battle_flow() -> void:
	var block: String = _battle_block_msg(_now_ts())
	if block != "":
		_toast(block)
		return
	GameState.mode = "single"
	GameState.tutorial = false
	GameState.dual_ghost = {}
	GameState.dual_opponent = {}
	GameState.dual_active = true   # 常规开始战斗 = 双路对局(分路/小将/蛋/半场流程)
	_go("TeamSelect")


## 教程: 确认弹窗 → 固定阵容教程战斗 (1:1 PoC confirmStartTutorial → startTutorialBattle, 直进 Battle 不经选龟)
func _on_tutorial() -> void:
	if has_node("TutorialConfirm"):
		return
	var ov := ColorRect.new()
	ov.name = "TutorialConfirm"
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := PanelContainer.new()
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH; box.grow_vertical = Control.GROW_DIRECTION_BOTH
	## ★★★2026-09-27 这块弹窗是**全主菜单唯一一个真正的"网页盒"**:
	##   `#16213a` 底 + 2px 金描边 + **12px 圆角** + 一个 8px 圆角的纯色主按钮
	##   + 一个**完全没换过皮的 Godot 默认按钮**(圆角纯灰)。
	##   照着 `verify_ui_consistency` 的 13 条判据逐条对, 它一次占了 1(网页盒) / 2(圆角盒) / 3(默认皮)。
	## ★★为什么门禁一直没红: 那张基线表扫的是**主菜单加载完的样子**, 而这块弹窗要按过
	##   ❓ 磁贴才建得出来 ⇒ **被测对象根本不在场**(memory `fb-gate-subject-never-constructed`)。
	##   跟上周那个"一周只有周日露面"的决赛日按钮是同一族: 判据没错, 只是碰不到面。
	## ⇒ 换成共享皮肤层的九宫格金属面板(与背包/图鉴/排行榜的面板同一张皮), 零圆角零描边。
	## ★内容留白设在**返回的那个 StyleBox 上**, 不是设在 `bsb` 上 ——
	##   `UISkin.nine` 换掉的是整个 StyleBox, 写在 fallback 上的 margin 不会被带过去
	##   (贴图缺失退回时才用得上, 所以两边都要设)。
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(0)
	bsb.content_margin_left = 36; bsb.content_margin_right = 36; bsb.content_margin_top = 28; bsb.content_margin_bottom = 28
	var bframe := UISkin.nine("panel-frame.png", 20, bsb)
	bframe.content_margin_left = 36; bframe.content_margin_right = 36
	bframe.content_margin_top = 28; bframe.content_margin_bottom = 28
	box.add_theme_stylebox_override("panel", bframe)
	ov.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16); vb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vb)
	## ★★文案改口(2026-09-27)。原稿是**说明书腔**:「新手教程」/「是否开始龟龟对战教程？」——
	##   "是否…？" 是表单确认框的句式(Are you sure you want to…), 不是游戏里会有人说的话,
	##   而且它在**描述一个功能**(教程), 不是在**招呼玩家做一件事**。
	## ⇒ 改成场里那位老师傅开口: 说清楚要干嘛(选龟 + 摆阵), 一句话, 不带问句模板。
	var t := Label.new()
	t.text = "先下场练练"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20); t.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(t)
	var d := Label.new()
	d.text = "来一场热身局, 我教你挑龟、摆阵"; d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_font_size_override("font_size", 15); d.add_theme_color_override("font_color", Color("#e8d9b0"))
	vb.add_child(d)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER; bh.add_theme_constant_override("separation", 14)
	vb.add_child(bh)
	## ★主按钮: 原来是 `#ffc23c` 纯色 + **8px 圆角** —— 那是 Bootstrap 的 primary button,
	##   不是像素游戏的按钮。走 `UISkin.button` 上金属签牌皮(它自己按真实尺寸挑框:
	##   120×40 短边 <56 ⇒ 用 48×24 的 `chip-frame`, 正是给这个尺寸画的那张)。
	## ★文字色跟着改: 签牌是**深色金属**, 原来那个深褐 `#3a1f00` 压在上面根本读不出
	##   (它是配亮金底的)。换暖金字。
	var start_btn := Button.new()
	start_btn.text = "开打"; start_btn.custom_minimum_size = Vector2(120, 40)
	start_btn.add_theme_color_override("font_color", Color("#ffe9a8"))
	UISkin.button(start_btn, Color("#ffd08a"))
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(start_btn)
	## ★次按钮原来是**一个字都没动过的 Godot 默认皮**(圆角纯灰) ——
	##   `ui_skin.gd` 头注里记着的那 12 个"没游戏味最直接的来源", 这是漏网的第 13 个。
	##   (它连门禁第 3 条都躲过了, 因为那条先查 `has_theme_stylebox_override`,
	##    而默认主题不是 override —— 跟战斗面板「✕」「详细」两个按钮当年一模一样。)
	## ★「取消」也是表单词。这里不是在取消一个操作, 是在回一句话。
	var cancel_btn := Button.new()
	cancel_btn.text = "等会儿"; cancel_btn.custom_minimum_size = Vector2(96, 40)
	cancel_btn.add_theme_color_override("font_color", Color("#c6d2e0"))
	UISkin.button(cancel_btn, Color("#9fb6c9"))
	cancel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bh.add_child(cancel_btn)
	start_btn.pressed.connect(func() -> void:
		ov.queue_free()
		_begin_tutorial(false))   # ❓ 手动重玩: 可跳过(mandatory=false)
	cancel_btn.pressed.connect(func() -> void: ov.queue_free())
	add_child(ov)


## 首次打开 → 强制走教学(不弹确认框、不能跳)。已走完(onboarded)则不触发。
func _maybe_first_launch_tutorial() -> void:
	if OS.get_environment("ONBOARD") == "0":
		return   # 显式关(测试/开发)
	var force := OS.get_environment("ONBOARD") == "1"
	# ★只在【真正作为当前主场景】时触发 —— 冒烟/门禁把主菜单当子节点 instantiate() 时,
	#   get_tree().current_scene 不是它, 这时 change_scene 会搅乱人家的场景树(smoke 报 44 条 null)。
	#   force(ONBOARD=1)时放行, 供门禁真跑首次流程。
	if not force and get_tree().current_scene != self:
		return
	if not force and GameState.onboarded:
		return   # 走完过, 不再强制
	if not force and GameState.tutorial_active:
		return   # 已经在教学里(防重入)
	_begin_tutorial(true)   # 首次: mandatory=true(无跳过)


## 统一的教学启动: 从【选龟界面】进第一把(教选龟+站位)。mandatory=首次不能跳。
## ★沙盒(tutorial_active): 不给奖励(_settle_season 直接 return)、固定阵容、弱对手。
## ★走完整流程(选龟→双路战斗含摆位), 但选龟界面只显 3 只教学龟(用户2026-07-23)。
func _begin_tutorial(mandatory: bool) -> void:
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.dual_active = true               # 双路模式 → 战斗有【摆位阶段】可教站位
	GameState.tutorial_stage = "match1_pick"   # 导演: 第一把从选龟开始
	GameState.tutorial_mandatory = mandatory
	GameState.dungeon_stage = 1
	GameState.dungeon_carry_hp = {}; GameState.dungeon_dead_ids = []
	GameState.clear_team()
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null:
		_td.begin_sandbox()    # 快照真经济+发教学币(结束还原, 不给奖励)
	get_tree().change_scene_to_file("res://scenes/TeamSelect.tscn")


## ══════════════════════════════════════════════════════════════════════
##  ★★决赛日头衔不必打开对阵图(方案书 20260926-冠军四强头衔发放 · U1 · 2026-10-04)
## ══════════════════════════════════════════════════════════════════════
## 原来冠军/亚军/四强**只在 `BracketMapScene` 拿到 feed 时**才记进度、才 `sync_titles()` ——
##   周日打完、之后只开主菜单不再点进对阵图的人, **永远拿不到头衔**。
## ⇒ 主菜单在决赛日(UTC 周日, 玩法已上线)打开时也拉一次 feed, 拿到就交给
##   `BracketMapScene.record_progress_from()` —— **同一条链**(记进度 → 揭晓封存 → sync_titles → 存档),
##   主菜单这里一个判据都不写(memory `fb-hand-rolled-copies-drift`)。
## ★问不到(没网 / token 还没下来: 冷启动时 `ensure_signed_in_async` 是异步的)⇒ 隔几秒重试, 有上限。
## ★问到了「没有你的桶」⇒ 收手(纯观众不发, 判据在 `record_progress_from` 里)。
## ⚠ 已知边界: 只在**周日**拉。周一 00:00 换轮会清掉决赛进度(`start_new_season`),
##   所以周日一次都没开游戏的人仍拿不到 —— 与闯关赛补发同一个既有取舍(方案书 U1 原文)。
## ★自带一个 Timer 子节点(不借 `_sb_poll`): 不是决赛日时一个节点都不建。
const FINALS_TITLE_TRIES := 5          # 问不到时最多再问几次
const FINALS_TITLE_RETRY_TICKS := 5    # 问不到后隔几拍(秒)再问
var _ft_timer: Timer = null
var _ft_sent := false
var _ft_tries := 0
var _ft_cool := 0
var _ft_week := 0                      # 拉哪一周(决赛日那一周的锚点)
## 门禁读: 主菜单这条路记过几次(= 调过几次 `record_progress_from`)。
var finals_title_records := 0


## 现在该不该替玩家拉一次决赛 feed。**纯静态**, 门禁能把四个入参穷举。
static func finals_title_due(backend_on: bool, phase: String, finals_live: bool) -> bool:
	return backend_on and finals_live and phase == _P2C.PHASE_FINALS


func _finals_title_pull(now: int) -> void:
	if not finals_title_due(_SB.enabled(), _P2C.phase_at_utc(now),
			_P2C.phase_mode_live(_P2C.PHASE_FINALS)):
		return
	_ft_week = _P2C.week_anchor_utc(now)
	_ft_tries = 0
	_ft_cool = 0
	_ft_sent = false
	_ft_timer = Timer.new()
	_ft_timer.wait_time = 1.0
	_ft_timer.autostart = true
	_ft_timer.timeout.connect(_finals_title_tick)     # 方法引用, 不是闭包(tree_timer_audit)
	add_child(_ft_timer)
	_finals_title_tick()



func _finals_title_tick() -> void:
	if _ft_sent:
		if not _SB.finals_tried():
			return                                    # 还在路上
		_ft_sent = false
		var v: Dictionary = _SB.finals_cached()
		if str(v.get("reason", "")) != _SB.UNREACHABLE:
			## 问到了: 有桶就走那条链; 没桶(观众 / 人不够)那条链自己会一个字都不记。
			_BMS.record_progress_from(v)
			finals_title_records += 1
			_finals_title_stop()
			return
		_ft_cool = FINALS_TITLE_RETRY_TICKS
	if _ft_cool > 0:
		_ft_cool -= 1
		return
	if _ft_tries >= FINALS_TITLE_TRIES:
		_finals_title_stop()
		return
	_ft_tries += 1
	## ★先清缓存: 不清的话, 上一次(比如刚从对阵图回来)留下的旧视图会被当成这次的答案。
	_SB.finals_clear()
	_SB.fetch_finals_async(_ft_week, -1)
	_ft_sent = true


func _finals_title_stop() -> void:
	if is_instance_valid(_ft_timer):
		_ft_timer.stop()
		_ft_timer.queue_free()
	_ft_timer = null
