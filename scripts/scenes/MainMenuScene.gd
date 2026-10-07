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
## D-1: 服务状态三态(没配 / 正常 / 维护中 / 连不上)。维护态要盖掉赛程页的倒计时, 见 `week_card_info`。
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
const GOAL_BOX_NAME := "GoalBox"           # 玩家卡右边的晋级进度块(照荒野乱斗奖杯块)
const GOAL_W := 220.0
const GOAL_GAP := 8.0
const LV_BADGE_NAME := "LevelBadge"         # 大等级徽章(menu/hud/lvbadge.png, 黄铜盾)
const LV_TEXT_NAME := "LevelNum"            # 徽章上的等级数字
const LV_BADGE_SIZE := Vector2(68.0, 76.0)  # lvbadge.png 原尺寸 1:1
const LV_BADGE_POS := Vector2(20.0, 26.0)   # 卡内: 左端木面竖向居中(26..102)
const LV_FONT := 34
const CARD_L0_Y := 18.0                     # 昵称 + #ID(原 14: 字块顶压进卡顶边带 3px, CI 量出)
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
const SQ := 100.0                           # 原 88: 字压在方框底边木条上、「排行榜」比内框宽(2026-10-05 实拍)
const SQ_GAP := 8.0
const SQ_X := 16.0
const SQ_Y0 := 144.0
const SQ_ICON := 44.0
const SQ_FONT := 17
const SQ_NAME_PREFIX := "Sq_"               # 每颗方键的节点名 = 前缀 + 入口名(门禁按名字找, 不按下标)
const BADGE_NAME := "Badge"                 # 红点槽(默认藏着, 有事时由入口自己点亮)
const LOCK_REASON_NAME := "LockReason"      # 商店锁的短理由(贴在方键底边的小签)
const LOCK_ICON_NAME := "LockIcon"          # 像素锁(menu/hud/lock.png); 替换原系统表情 🔒

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
const MODE_SIZE := Vector2(320.0, 112.0)   # 原 108: 标题/倒计时字块压进上下边带(CI 量出 +2/+6); 112 = 顶沿正好贴角斗龟脚底(再高就盖住龟)
const MODE_POS := Vector2(HERO_POS.x - 12.0 - 320.0, HERO_POS.y + HERO_SIZE.y - 112.0)   # 452..772 × 584..692
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
const CURRENCY_BAR_NAME := "CurrencyBar"   # 右上货币条(两种货币同一条, 照荒野乱斗)
const CUR_PAD := 16.0                       # 每段两端留白(含斜切)
const CUR_SEP := 4.0                        # 两段之间的斜缝
const CUR_ICON := 34.0                      # 货币图标
const CUR_FONT := 24                        # 货币数字
const CUR_GAP := 8.0                        # 货币条与 ? 键之间
const ICON_TAP := 81.0                                 # ? / ⚙ 的点击区(触摸线)
const ICON_VIS := 50.0                                 # ? / ⚙ 看得见的暗槽(82→54→50; 2026-10-05 换像素小图标)

## ── 本周赛程: 点模式卡打开的整页(结构照荒野乱斗「CHOOSE EVENT」, 见 `_week_popup`) ──
const WEEK_POPUP_NAME := "WeekPopup"

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
	## 2026-10-06 用户「顶上那个斗龟场动画可以去掉」⇒ 主菜单不再放标题图(_title() 已删; 登录墙有自己的标题)
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
	## 教程走完回到主菜单: 飘一行「教程完成」(方案书 §6.1 完成提示)。导演只留一句话, 由这里说出来。
	var _tdm = get_node_or_null("/root/TutorialDirector")
	## ★用 get/set 不直接点属性: 导演是 autoload, 万一跑的是旧版本(没有这个字段)也只是不飘字, 不报错中断 _ready。
	if _tdm != null and str(_tdm.get("pending_toast")) not in ["", "<null>"]:
		_toast(str(_tdm.get("pending_toast")))
		_tdm.set("pending_toast", "")


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
const NUDGE_H := 30.0                        # 齿轮下方绑定提示条高(不含尖角)
const NUDGE_FONT := 16


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
	## ★2026-10-06: 从主菜单正中的大木牌改成【设置齿轮正下方的小提示条】
	##   (照使命召唤手游主大厅: 齿轮下面一个带尖角的黄框小条「LINK TO SOCIAL ACCOUNT」)。
	##   原来压在擂台画面正中、比训龟大师还大(用户「改」, 60 人实操台账 M1)。
	var txt := str(_P2C.bind_nudge_text())
	var tw_n: float = ceilf(_bold_font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, NUDGE_FONT).x)
	var bw: float = tw_n + 28.0
	var gear_cx: float = RIGHT_EDGE - ICON_TAP / 2.0
	## 尖角顶 = 齿轮【点击区】底沿再往下 1px(不压 ?/⚙ 的 81px 触摸区; 看得见的空隙 ≈12px)。
	var top: float = 30.0 + (85.0 - ICON_TAP) / 2.0 + ICON_TAP + 1.0 + 8.0
	var b := Control.new()
	b.name = NUDGE_NAME
	b.size = Vector2(bw, maxf(NUDGE_H + 8.0, ICON_TAP))   # 整块 = 点击区(81 触摸线); 看得见的条在上面 38px
	b.position = Vector2(minf(gear_cx - bw / 2.0, RIGHT_EDGE - bw), top - 8.0)
	var arrow := Polygon2D.new()
	var ax: float = gear_cx - b.position.x
	arrow.polygon = PackedVector2Array([Vector2(ax - 8.0, 8.0), Vector2(ax + 8.0, 8.0), Vector2(ax, 0.0)])
	arrow.color = Color("#e8b84a")
	b.add_child(arrow)
	var box := ColorRect.new()
	box.color = Color("#e8b84a")
	box.position = Vector2(0.0, 8.0)
	box.size = Vector2(bw, NUDGE_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var inner := ColorRect.new()
	inner.color = Color("#1a1206")
	inner.position = Vector2(2.0, 10.0)
	inner.size = Vector2(bw - 4.0, NUDGE_H - 4.0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inner)
	var lb := _menu_label(txt, NUDGE_FONT, Color("#ffd27a"))
	lb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lb.position = Vector2(0.0, 8.0)
	lb.size = Vector2(bw, NUDGE_H)
	b.add_child(lb)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	## 点击区: 看得见的条只有 30 高, 点击区往下补到 81(触摸线), 不往上(上面是齿轮的点击区)。
	btn.position = Vector2(0.0, 0.0)
	btn.size = Vector2(bw, maxf(NUDGE_H + 8.0, ICON_TAP))
	btn.pressed.connect(_open_bind_screen)
	b.add_child(btn)
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
		it.position = Vector2((SQ - SQ_ICON) / 2.0, 8.0 if locked else 14.0)   # 锁着: 底边要挂小签, 图标/字整体上提
		it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			it.modulate = Color(0.55, 0.55, 0.58)
		holder.add_child(it)
	var lb := _menu_label(label, SQ_FONT, Color("#b9b2a6") if locked else Color("#ffe9a8"))
	lb.add_theme_color_override("font_outline_color", Color("#140a03"))
	lb.add_theme_constant_override("outline_size", 6)
	lb.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lb.position = Vector2(0.0, 52.0 if locked else 61.0)   # 平时字框 61..85(底边木条 ~86 起之上); 锁着上提到 52..76, 给底边小签让位
	lb.size = Vector2(SQ, 24.0)
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
		## ★2026-10-05 商业游戏标准锁态: 整块压暗 + 像素锁盖在图标正中 + 解锁条件贴在按钮自己底边的小签上。
		##   原来是系统表情 🔒 骑在右上角(红点的位置, 像"有新消息")+ 理由飘在方键外面的看台上。
		holder.add_child(_pixel_lock(Vector2((SQ - 24.0) / 2.0, 8.0 + (SQ_ICON - 30.0) / 2.0), 2.0))
		if reason != "":
			var tag_box := Rect2(Vector2(-4.0, SQ - 23.0), Vector2(SQ + 8.0, 23.0))   # 整条落在方键里(底边木条上), 不探进下一颗
			var tagbg := _nine_rect("xpbar.png", Vector4(8, 8, 8, 8), tag_box)
			tagbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(tagbg)
			var rs := _place_outlined(reason, 14, Color("#ffe6b8"), tag_box.position, tag_box.size)
			rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	## ★2026-10-05: 系统表情 🔒 → 像素锁(menu/hud/lock.png ×2.5)。
	var lock := _pixel_lock(Vector2.ZERO, 2.5)
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
	holder.add_child(lock)


## 像素锁(12×15 原图, 最近邻按 k 倍贴)。名字固定 LOCK_ICON_NAME —— 门禁按名字找它。
func _pixel_lock(pos: Vector2, k: float) -> TextureRect:
	var t := TextureRect.new()
	t.name = LOCK_ICON_NAME
	t.texture = load(HUD + "lock.png")
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = Vector2(12.0, 15.0) * k
	t.position = pos
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 右上角的小图标键(? / ⚙): 暗槽(与经验条同一张 xpbar.png) + 一个字形(? 用像素字体 m6x11, ⚙ 走打包字体里的单色线稿齿轮)。
## 点击区 = ICON_TAP(81, 触摸线), 看得见的暗槽 = ICON_VIS, 居中。
func _icon_button(glyph: String, glyph_size: int, col: Color, cb: Callable, pos: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(ICON_TAP, ICON_TAP)
	holder.custom_minimum_size = holder.size
	holder.pivot_offset = holder.size / 2.0
	var vo: float = (ICON_TAP - ICON_VIS) / 2.0
	## ★2026-10-06: 实体按钮(亮顶面 + 深底边 + 阴影, menu/hud/iconbtn.png), 照荒野乱斗右上方键的厚度; 原来是细铜线空框。
	var slot := _nine_rect("iconbtn.png", Vector4(6, 6, 8, 16), Rect2(Vector2(vo, vo), Vector2(ICON_VIS, ICON_VIS + 4.0)))
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(slot)
	var ic := Label.new()
	ic.text = glyph
	## 字形对准【顶面】中心(顶面 = 暗槽去掉底边厚 10px), 不是整块按钮的中心。
	ic.position = Vector2(vo, vo)
	ic.size = Vector2(ICON_VIS, ICON_VIS - 6.0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if glyph == "?":
		ic.add_theme_font_override("font", load("res://assets/fonts/m6x11.ttf"))
		## m6x11 的「?」字形在行框里偏上偏左(2026-10-06 实测墨迹中心 dx=-1 / dy=-2.5) ⇒ 整体挪回暗槽正中
		ic.position += Vector2(0.5, 5.0)   # 2026-10-06 实体按钮版再量: 对准顶面中心
	else:
		ic.position += Vector2(-1.0, 1.0)  # ⚙ 线稿齿轮同样实量
	ic.add_theme_font_size_override("font_size", glyph_size)
	ic.add_theme_color_override("font_color", col)
	ic.add_theme_color_override("font_outline_color", Color("#140a03"))
	ic.add_theme_constant_override("outline_size", 6)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): slot.modulate = Color(1.3, 1.22, 1.1))
	btn.mouse_exited.connect(func(): slot.modulate = Color.WHITE)
	btn.button_down.connect(func(): holder.position.y += 3.0)   # 按下 = 往下沉一截(实体按钮的手感)
	btn.button_up.connect(func(): holder.position.y -= 3.0)
	btn.pressed.connect(func(): cb.call())
	return holder


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
	var help_x := set_x - ICON_VIS - CUR_GAP   # 看得见的两个暗槽之间 = CUR_GAP(与货币条到 ? 同宽); 点击区互相叠一截, 不影响
	var uy := 30.0 + (85.0 - ICON_TAP) / 2.0                   # 与货币牌竖直居中对齐
	## ★2026-10-05: ⚙(系统表情)/蓝色圆 ? 换成像素小图标 + 暗槽(参考: 荒野乱斗 ≡ / 英雄联盟手游齿轮 —— 角上的小图标, 不跟货币抢)。
	var set_tile := _icon_button("⚙", 30, Color("#d8d4cc"), func(): _go("Settings"), Vector2(set_x, uy))
	content_root.add_child(set_tile)
	_slide_in(set_tile, 1)
	var help_tile := _icon_button("?", 30, Color("#ffd27a"), func(): _on_tutorial(), Vector2(help_x, uy))
	content_root.add_child(help_tile)
	_slide_in(help_tile, 2)
	## ★2026-10-06 照荒野乱斗主大厅右上角(interfaceingame brawl-stars-main-menu / -lobby):
	##   所有货币挤在【同一条】深色长条里(图标 + 数字, 中间一道分隔), 长条右边紧挨着方形小键, 同高、底边对齐。
	##   原来两块带尖角的木牌是自己画的, 7 张参考里没有一款这么做(用户「金币框哪个游戏这么做的」)。
	var slot_y: float = uy + (ICON_TAP - ICON_VIS) / 2.0
	var bar := _currency_bar([
		["res://assets/sprites/menu/ic-deepsea.png", Color(0, 0, 0, -1.0), int(GameState.meta_deepsea_coins)],
		["res://assets/sprites/ui/coin.png", Color(0.122, 0.561, 0.247), int(GameState.coins)],
	])
	bar.position = Vector2(help_x + (ICON_TAP - ICON_VIS) / 2.0 - CUR_GAP - bar.size.x, slot_y)
	content_root.add_child(bar)
	_slide_in(bar, 0)
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


## 右上货币条: 一条深色长条(xpbar.png 暗槽, 与 ? / ⚙ 同底同高) + 每种货币「图标 + 数字」, 中间一道竖分隔。
## items = [[图标路径, 染色(a<0 = 不染), 数值], ...] 从左到右。返回未定位的 Control。
func _currency_bar(items: Array) -> Control:
	var holder := Control.new()
	holder.name = CURRENCY_BAR_NAME
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ★2026-10-06 第二版: 去掉铜边框(用户「你自己觉得这些框很好看吗」)。照荒野乱斗: 每种货币一段
	##   半透明黑底、两头斜切, 段与段之间留一道斜缝(cur_seg.png 九宫格, 左右边距 = 斜切宽)。
	var x: float = 0.0
	var parts: Array = []
	for i in range(items.size()):
		var it: Array = items[i]
		if i > 0:
			x += CUR_SEP
		var seg_x: float = x
		x += CUR_PAD
		var ic := _currency_icon(str(it[0]), it[1])
		ic.size = Vector2(CUR_ICON, CUR_ICON)
		ic.position = Vector2(x, (ICON_VIS - CUR_ICON) / 2.0)
		parts.append(ic)
		x += CUR_ICON + 8.0
		var num := "%d" % int(it[2])
		var nw: float = ceilf(_bold_font().get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, CUR_FONT).x) + 6.0
		var cl := _menu_label(num, CUR_FONT, Color("#fff4d6"), HORIZONTAL_ALIGNMENT_LEFT)
		cl.add_theme_color_override("font_outline_color", Color("#140a03"))
		cl.add_theme_constant_override("outline_size", 6)
		cl.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cl.position = Vector2(x, 3.0)   # 纯数字在 CJK 粗体行框里偏上 3px(2026-10-06 帧差实测)
		cl.size = Vector2(nw, ICON_VIS)
		parts.append(cl)
		x += nw + CUR_PAD
		var seg := _nine_rect("cur_seg.png", Vector4(12, 0, 12, 0), Rect2(Vector2(seg_x, 0.0), Vector2(x - seg_x, ICON_VIS)))
		parts.insert(parts.size() - 2, seg)
	holder.size = Vector2(x, ICON_VIS)
	holder.custom_minimum_size = holder.size
	for pp in parts:
		holder.add_child(pp)
	return holder


## 货币图标: 线稿图标按 tint 染色(tint.a < 0 = 原色)。
func _currency_icon(path: String, tint: Color) -> TextureRect:
	var ci := TextureRect.new()
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ResourceLoader.exists(path):
		return ci
	var cimg: Image = load(path).get_image()
	if tint.a >= 0.0:
		for yy in range(cimg.get_height()):
			for xx in range(cimg.get_width()):
				var px := cimg.get_pixel(xx, yy)
				if px.a > 0.0:
					cimg.set_pixel(xx, yy, Color(tint.r, tint.g, tint.b, px.a))
	ci.texture = ImageTexture.create_from_image(cimg)
	return ci


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
		return "闯关赛 · 未晋级"
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
		conv = " · 未使用 %d 场已折算：深海币 +%d · 经验 +%d" % [
			int(bf["games"]), int(bf["coins"]), int(bf["xp"])]
	if st == _P2C.GAUNTLET_IN:
		return "闯关赛 %s · 已晋级决赛日%s" % [lab, conv]
	if st == _P2C.GAUNTLET_OUT:
		return "闯关赛 %s · 已出局%s" % [lab, conv]
	return "闯关赛 %s · 晋级还需 %d 胜 / 剩余 %d 负%s" % [
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
	return "决赛日 · 未晋级"


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
	_player_card(ts)
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


## ★`now` = 本屏那一刻(由 `_status_row` 传入), 原样转给 `_goal_box` —— 一屏只读一次钟(verify_quota_clock ④)。
func _player_card(now: int) -> void:
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
		LV_BADGE_POS + Vector2(2.0, 13.0), Vector2(LV_BADGE_SIZE.x, 44.0))   # 2026-10-05 实测原位偏左 1.5 / 偏高 6.5, 挪到盾面直边段中心
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
			Vector2(tx, CARD_L0_Y + 7.5), Vector2(maxf(CARD_TEXT_X + tw - tx, 1.0), 25.0))   # +7.5: 实测 +4 时 #ID 字块中心比昵称高 3.5px
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
	xt.position.y += 3.0   # 纯数字在 CJK 粗体行框里偏上(2026-10-06 帧差实测 dy=-3)
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
	_goal_box(CARD_POS + Vector2(card_size.x + GOAL_GAP, 0.0), card_size.y, now)   # 用落位 CARD_POS(holder.position 已被入场动画挪到屏外)


## 晋级进度块: 玩家卡右边紧挨一块「图标 + 大数字 + 进度条(末端写奖励)」。
## ★照荒野乱斗主大厅左上角(interfaceingame brawl-stars-main-menu): 玩家卡右边就是奖杯数 + 一根通往下一个奖励的进度条。
##   本作的「下一个奖励」= 周六闯关赛资格(season_wins ≥ PROMOTE_WINS)。只在积分赛那几天(含周一)显示; 周六/周日不放。
func _goal_box(pos: Vector2, card_h: float, now: int) -> void:
	var ts: int = now
	var ph: String = _P2C.phase_at_utc(ts)
	if ph == _P2C.PHASE_GAUNTLET or ph == _P2C.PHASE_FINALS:
		return
	var need: int = int(_P2C.PROMOTE_WINS)
	var have: int = mini(int(GameState.season_wins), need)
	var holder := Control.new()
	holder.name = GOAL_BOX_NAME
	holder.position = pos
	holder.size = Vector2(GOAL_W, card_h)
	holder.custom_minimum_size = holder.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_nine_rect("card.png", Vector4(40, 16, 40, 16), Rect2(Vector2.ZERO, holder.size)))
	## ★图标是新画的胜利小旗(menu/hud/goal-flag.png, PixelLab), 不复用左列「排行榜」的奖杯
	##   (用户「为啥复用这个奖杯啊」: 同一个奖杯出现两次 = 读成排行榜, 也违反新内容不复用素材)。
	## ★图标 + 数字作为一组在块里水平居中(用户「字体居中？」; 原来贴左, 右边空一截, 实测偏左 30px)。
	var txt := "%d / %d" % [have, need]
	var tw_g: float = ceilf(_bold_font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x) + 6.0
	var gx: float = (GOAL_W - (40.0 + 8.0 + tw_g)) / 2.0
	var ic := TextureRect.new()
	ic.texture = load(HUD + "goal-flag.png")
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size = Vector2(40.0, 40.0)
	ic.position = Vector2(gx, 24.0)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	var num := _place_outlined(txt, 28, Color("#ffd24a"), Vector2(gx + 48.0, 25.0), Vector2(tw_g, 38.0))
	num.name = "GoalNum"
	holder.add_child(num)
	var bar_r := Rect2(Vector2(22.0, 74.0), Vector2(GOAL_W - 44.0, 26.0))
	holder.add_child(_nine_rect("xpbar.png", Vector4(8, 8, 8, 8), bar_r))
	var bar := TextureProgressBar.new()
	bar.name = "GoalBar"
	bar.texture_progress = load(HUD + "xpbar-fill.png")
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 4; bar.stretch_margin_right = 4; bar.stretch_margin_top = 4; bar.stretch_margin_bottom = 4
	bar.position = bar_r.position + Vector2(4.0, 4.0)
	bar.size = bar_r.size - Vector2(8.0, 8.0)
	bar.min_value = 0.0
	bar.max_value = float(need)
	bar.step = 0.0
	bar.value = float(have)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bar)
	## 进度条末端 = 奖励是什么(荒野乱斗在末端放下一个奖励的头像; 本作写「晋级」)。
	var rw := _place_outlined("晋级闯关赛", 15, Color("#ffffff"), bar_r.position, bar_r.size)
	rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(rw)
	content_root.add_child(holder)
	_slide_in_left(holder, 1)


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
	lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER   # 字框比字宽多 6(描边余量), 左对齐时余量全堆在右边 ⇒ 整行偏左
	holder.add_child(lh)
	var lq := _place_outlined(str(tx[1]), COUNTER_FONT, Color("#ffe9a8"),
		Vector2(COUNTER_PAD + w0 + gap, 3.0), Vector2(w1, COUNTER_H - 6.0))
	lq.name = "CounterQuota"
	lq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


## ══════════════════════════════════════════════════════════════════════
##  「今天」模式卡 + 本周赛程弹层(2026-10-05 第三轮)
## ══════════════════════════════════════════════════════════════════════
## 原来七天赛程是一条贴底的满宽长条, 常驻占掉屏幕最底下一整行。参考里(荒野乱斗那块活动卡)
## 主 CTA 左边只放**今天**那一件事: 今天打什么、一句规矩、还剩多久 —— 整周的表点开才看。
## ⇒ 模式卡只说今天; 点它打开**本周赛程页**(四个阶段四张卡, 周六/周日的门都在卡上)。
## ★赛程判定与数据一个字都没动, 只换了「摆在哪」: 模式卡的三行字全是现成的纯函数/常量拼出来的。
var _mode_box: Control = null
var _week_pop: Control = null
var _week_dim: ColorRect = null
const WEEK_DIM_NAME := "WeekPopupDim"


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
	var left: int = _P2C.close_left_sec(now)
	var kind := _close_kind_at(now)
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
	## ★2026-10-06 照荒野乱斗开战按钮旁的模式卡(模式名 + 下面一行副标题 + 上沿倒计时), 不写规则句
	##   (用户「每周最多16场，周五截止，这是什么意味呢」「哪个游戏这么说」)。规则收进赛程弹层。
	var second := "第 %d 大轮" % int(GameState.season_id)
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


## 周末(闯关赛 / 决赛日)没资格的人: 模式卡压灰 + 像素锁。
## ★判据不另写: 今天那张赛程卡锁着(`week_card_info` 的锁 = gauntlet_eligible / gauntlet_line_reached / gauntlet_state)
##   **且** 开始战斗那扇门真的拦着(`_battle_block_msg`)。平日不走这一支(平日的锁画在开始战斗上)。
func mode_card_locked(now: int) -> bool:
	var ph: String = _P2C.phase_at_utc(now)
	if ph != _P2C.PHASE_GAUNTLET and ph != _P2C.PHASE_FINALS:
		return false
	return bool(week_card_info(ph, now)["locked"]) and _battle_block_msg(now) != ""


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
	## ★周末没资格(开始战斗锁着)⇒ 整张压灰 + 像素锁, 与赛程页那张锁着的卡同一个判据(`mode_card_locked`)。
	var locked := mode_card_locked(now)
	var plate_mod := Color(0.56, 0.54, 0.53) if locked else Color.WHITE
	plate.modulate = plate_mod
	holder.add_child(plate)
	## ★2026-10-06 排法照荒野乱斗那张模式卡: 上沿一条暗带(倒计时靠右 + 右端「i」), 中间大字模式名, 下面一行彩色副标题。
	var band := ColorRect.new()
	band.name = "CountdownBand"
	band.color = Color(0.0, 0.0, 0.0, 0.42)
	band.position = Vector2(12.0, 10.0)
	band.size = Vector2(MODE_SIZE.x - 24.0, 26.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(band)
	var cd := _place_outlined(str(lines[2]), MODE_CD_FONT - 2, Color("#ffc94a"), Vector2(18.0, 10.0), Vector2(MODE_SIZE.x - 36.0 - 30.0, 26.0))
	cd.name = "ModeCountdown"
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(cd)
	var cap := _place_outlined("i", 18, Color("#fff4d6"), Vector2(MODE_SIZE.x - 12.0 - 26.0 + 1.5, 12.5), Vector2(26.0, 26.0))   # +1.5/+2.5: 帧差实测对准蓝底方块中心
	cap.name = "ModeHint"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", load("res://assets/fonts/m6x11.ttf"))
	var capbg := ColorRect.new()
	capbg.color = Color("#2f6fb8")
	capbg.position = Vector2(MODE_SIZE.x - 12.0 - 26.0 + 3.0, 13.0)
	capbg.size = Vector2(20.0, 20.0)
	capbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(capbg)
	holder.add_child(cap)
	var tx := 18.0
	if locked:
		var lk := _pixel_lock(Vector2(18.0, 36.0 + (40.0 - 30.0) / 2.0), 2.0)
		holder.add_child(lk)
		tx += 24.0 + 10.0
	var title := _place_outlined(str(lines[0]), MODE_TITLE_FONT, Color("#cfc9c2") if locked else Color("#fff4d6"),
		Vector2(tx, 36.0), Vector2(MODE_SIZE.x - 18.0 - tx, 40.0))
	title.name = "ModeTitle"
	holder.add_child(title)
	var rule := _place_outlined(str(lines[1]), MODE_RULE_FONT + 1, Color("#b9b2a6") if locked else Color("#a8e06a"), Vector2(18.0, 76.0), Vector2(rule_w, 24.0 + grow))
	rule.name = "ModeRule"
	if extra_rows > 0:
		rule.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	holder.add_child(rule)
	var btn := Button.new()
	btn.name = "ModeTap"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): plate.modulate = plate_mod * Color(1.2, 1.15, 1.08))
	btn.mouse_exited.connect(func(): plate.modulate = plate_mod)
	btn.pressed.connect(_open_week_popup)
	content_root.add_child(holder)
	_mode_box = holder
	## 弹层要盖在模式卡上面(重建时模式卡会排到最后)
	if is_instance_valid(_week_pop):
		content_root.move_child(_week_pop, -1)


## ══════════════════════════════════════════════════════════════════════
##  本周赛程页(2026-10-06, 照荒野乱斗「CHOOSE EVENT」那一页)
## ══════════════════════════════════════════════════════════════════════
## 参考: interfaceingame.com/screenshots/brawl-stars-choose-event(本地 C:/tmp/lobby/brawl-stars-choose-event.png)。
## 照着它的结构, 不照它的画风(皮仍是本作的暖色像素):
##   顶栏      左上返回箭头 + 页名
##   2×2 卡    每张 = 上沿一条暗带(右对齐的时间 + 右端「i」) / 彩色抬头(大字模式名 + 副标题) / 下面的要点
##   锁着的卡  整张压灰 + 左边一把锁 + 旁边写解锁条件(参考里「Reach 350 total Trophies to unlock」那一格)
## ★赛程判定与数据一个字没动, 只换了长相: 阶段 / 倒计时 / 门 / 锁全问原来那几个函数
##   (`phase_at_utc` / `_mode_countdown` / `close_block_kind` / `gauntlet_eligible` / `gauntlet_state` / `phase_mode_live`)。
## ★原来模式卡上那句规则(「每周最多 16 场 · 周五截止」)收到这里每张卡的要点里, 数字一律读规则常量。
const WEEK_BAR_H := 84.0                     # 顶栏高 = 返回键触摸线 81 + 底边铜线 3(返回键不探出屏顶)
const WEEK_BACK_NAME := "WeekPopupBack"
const WEEK_CARDS_NAME := "WeekCards"         # 四张卡的容器(门禁按名字找)
const WEEK_CARD_PREFIX := "PhaseCard_"       # 每张卡 = 前缀 + 阶段 id
const WEEK_CARD_SIZE := Vector2(572.0, 296.0)
const WEEK_CARD_GAP := 20.0
## 2×2 居中在 1280 设计框里: 左右各 58, 竖向 96..708(顶栏 84 + 12 留白, 底下 12)
const WEEK_GRID_POS := Vector2((W - 572.0 * 2.0 - 20.0) / 2.0, 96.0)
const CARD_STRIP_H := 30.0                   # 上沿暗带
const CARD_HEAD_H := 84.0                    # 彩色抬头
const CARD_PAD := 18.0
const CARD_CHIP_SIZE := Vector2(112.0, 58.0)
const CARD_LINE_H := 26.0
const WEEK_PHASES := [_P2C.PHASE_REST, _P2C.PHASE_RANKED, _P2C.PHASE_GAUNTLET, _P2C.PHASE_FINALS]
## 抬头底色: 一个阶段一个颜色, 都在暖色像素调色板里(灰褐 / 铜橙 / 绛红 / 暗金)。
const PHASE_HEAD_COL := {
	_P2C.PHASE_REST: Color("#7a6856"),
	_P2C.PHASE_RANKED: Color("#b0602c"),
	_P2C.PHASE_GAUNTLET: Color("#9c3328"),
	_P2C.PHASE_FINALS: Color("#a87a22"),
}
const CARD_LOCK_HEAD := Color("#5c5652")     # 锁着: 抬头压灰
const CARD_LOCK_BODY := Color("#2c2826")
const CARD_BODY_COL := Color("#2a1a10")
const CARD_TODAY_COL := Color("#ffd34a")     # 今天那张的金边
const CARD_PAST_TEXT := "已结束"
const WEEK_DOOR_BRACKET := "bracket"
const WEEK_DOOR_BOARD := "board"


## 本周赛程页的壳: 压暗底 + 顶栏(返回 + 页名)。卡由 `_week_cards` 往里放。默认藏着。
## ★压暗色块不是 Button: 它只负责挡住下面的主菜单(STOP), 关页面走左上角返回键 / 返回键(ui_cancel)。
func _week_popup(paint_now: int) -> void:
	_week_pop = Control.new()
	_week_pop.name = WEEK_POPUP_NAME
	_week_pop.size = Vector2(W, H)
	_week_pop.visible = false
	_week_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 压暗色块**比设计框大一圈**(宽屏 1560 两侧也要盖住)。
	## ★它只在页面打开时 visible —— 藏着的时候它不能是一块「铺满视口又 STOP」的东西
	##   (verify_ui_layout ④ 按节点自己的 visible 量)。
	_week_dim = ColorRect.new()
	_week_dim.name = WEEK_DIM_NAME
	_week_dim.color = Color(0.06, 0.035, 0.02, 0.93)
	_week_dim.position = Vector2(-1000.0, -1000.0)
	_week_dim.size = Vector2(W + 2000.0, H + 2000.0)
	_week_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_week_dim.visible = false
	_week_pop.add_child(_week_dim)
	## 顶栏: 一条横贯视口的暗木色带 + 底边一道铜线(宽屏两侧跟着延长)。
	## ★与压暗色块同一条规矩: 比设计框宽, 所以只在页面打开时 visible(藏着时不算「超出视口」的控件)。
	_week_bar = ColorRect.new()
	_week_bar.name = "WeekPopupBar"
	_week_bar.color = Color("#160d07")
	_week_bar.position = Vector2(-1000.0, 0.0)
	_week_bar.size = Vector2(W + 2000.0, WEEK_BAR_H)
	_week_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_week_bar.visible = false
	_week_pop.add_child(_week_bar)
	var edge := ColorRect.new()
	edge.color = Color("#7a4e22")
	edge.position = Vector2(0.0, WEEK_BAR_H - 3.0)
	edge.size = Vector2(W + 2000.0, 3.0)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.visible = false
	_week_bar.add_child(edge)
	var back := _back_button()
	back.position = Vector2(WALL, (WEEK_BAR_H - 3.0 - ICON_TAP) / 2.0)
	_week_pop.add_child(back)
	var hz := Control.new()
	hz.name = "WeekPopupHead"
	hz.size = Vector2(W, WEEK_BAR_H - 3.0)
	hz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_week_pop.add_child(hz)
	var head := _place_outlined("本周赛程", 30, Color("#ffe9a8"),
		Vector2(WALL + ICON_TAP + 4.0, -1.0), Vector2(360.0, WEEK_BAR_H - 3.0))
	head.name = "WeekPopupTitle"
	hz.add_child(head)
	content_root.add_child(_week_pop)
	_week_cards(paint_now)


## 左上角返回键: 与右上 ? / ⚙ 同一种实体按钮(iconbtn.png), 里面一支像素箭头(menu/hud/back.png, 本轮新画)。
## 点击区 = ICON_TAP(81, 触摸线)。★具名方法 `_close_week_popup`, 门禁量得到接的是谁。
func _back_button() -> Control:
	var holder := Control.new()
	holder.name = WEEK_BACK_NAME
	holder.size = Vector2(ICON_TAP, ICON_TAP)
	holder.custom_minimum_size = holder.size
	var vo: float = (ICON_TAP - ICON_VIS) / 2.0
	var slot := _nine_rect("iconbtn.png", Vector4(6, 6, 8, 16), Rect2(Vector2(vo, vo), Vector2(ICON_VIS, ICON_VIS + 4.0)))
	holder.add_child(slot)
	var arrow := TextureRect.new()
	arrow.name = "BackArrow"
	arrow.texture = load(HUD + "back.png")
	arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_SCALE
	arrow.size = Vector2(15.0, 19.0) * 2.0
	## 对准【顶面】中心(顶面 = 暗槽去掉底边厚 10px), 与 ? / ⚙ 同一个口径
	arrow.position = Vector2(vo + (ICON_VIS - arrow.size.x) / 2.0, vo + (ICON_VIS - 6.0 - arrow.size.y) / 2.0)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(arrow)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): slot.modulate = Color(1.3, 1.22, 1.1))
	btn.mouse_exited.connect(func(): slot.modulate = Color.WHITE)
	btn.pressed.connect(_close_week_popup)
	return holder


var _week_bar: ColorRect = null


func _open_week_popup() -> void:
	if is_instance_valid(_week_pop):
		content_root.move_child(_week_pop, -1)
		_week_pop.visible = true
		_week_dim.visible = true
		_week_bar.visible = true
		for e in _week_bar.get_children():
			(e as CanvasItem).visible = true


func _close_week_popup() -> void:
	if is_instance_valid(_week_pop):
		_week_pop.visible = false
		_week_dim.visible = false
		_week_bar.visible = false
		for e in _week_bar.get_children():
			(e as CanvasItem).visible = false


## 系统返回键 / Esc 关掉赛程页(整页盖着主菜单, 不能只有左上角一个出口)。
func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel") and is_instance_valid(_week_pop) and _week_pop.visible:
		_close_week_popup()
		get_viewport().set_input_as_handled()


# ─── 📅 本周赛程 ───
## v2 的核心是周赛制, 而玩家在主菜单上【完全看不到这周是怎么安排的】: 哪天积分赛、
## 哪天闯关、什么时候收盘, 全靠记。
## ★2026-10-06 从「七格横条」换成整页四张阶段卡(见 `_week_popup` 头注); 下面是横条那一版的来历。
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

## 赛程页四张卡的容器。★留引用是为了服务状态变化时能把它换掉(见 `_sb_poll`)。
var _week_box: Control = null
## 建这一页卡时的服务状态。★存下来才知道"变没变" —— 只看当前值没法判断要不要重建。
var _sb_state_shown: String = ""


## D-1: 服务状态变了就重建赛程页(维护态要盖掉倒计时)。
## ★判据是**状态变了**而不是"每秒都重建" —— 后者会让主菜单每秒扔一堆节点。
func _sb_poll() -> void:
	if _SB.take_update_hint(): _toast(_SB.UPDATE_HINT)   # E15: 服务端要求的最低版本高于本机 ⇒ 非阻塞提示一次
	var s: String = _SB.service_state()
	## ★★2026-10-03 周六实操 S16: 原来**只在服务状态变了才重画** ⇒ 倒计时停在打开主菜单那一刻
	##   (22:36 与 22:49 两张截图都写「距收盘 24 分 18 秒」), 22:50 的「已封盘」也永远出不来。
	##   ⇒ 右侧那一块要显示的东西(档位 + 剩余时间文字)变了也重画。
	if s == _sb_state_shown and _close_key(_strip_now()) == _close_key_shown:
		return
	rebuild_week_page()


## 赛程页此刻用哪个时钟(与 `_week_cards` 同一条: strip_now_override → _now_ts())。
func _strip_now() -> int:
	return strip_now_override if strip_now_override > 0 else _now_ts()


## 右侧收盘块「要显示的内容」的指纹: 档位 + 剩余时间文字。变了就该重画。
var _close_key_shown: String = ""

func _close_key(now: int) -> String:
	var ph: String = _P2C.phase_at_utc(now)
	var left: int = _P2C.close_left_sec(now)
	var kind := _close_kind_at(now)
	## ★模式卡第三行(倒计时)也算进指纹: 休赛/决赛日那几天它数的是「距下一阶段」, 收盘块不变它也在变。
	return "%s|%s|%s|%s" % [ph, kind, _left_text(left) if left >= 0 else "", _mode_countdown(now)]


## 重建赛程页的四张卡(+ 模式卡)。★抽出来是因为实拍要在换过时钟之后再建一次 ——
##   就地再抄一遍那两行就是「手抄的副本必然落后」。
func rebuild_week_page() -> void:
	if is_instance_valid(_week_box):
		_week_box.queue_free()
	_week_cards()
	## 模式卡的倒计时跟着同一次重画走(同一条钟: `_strip_now()`)。
	if is_instance_valid(content_root):
		_mode_card(_strip_now())


## ★只给门禁与实拍喂已知时刻; **产品一律不传**。
##   先例: `TeamSelectScene.lockout_now_override` / `GameState.ranked_quota_full(now)`。
##   ⚠ 为什么非要这个口子: 赛程页是**按星期分支**的东西 ⇒ 不给口子的话,
##     「周日那张卡上的对阵图门」只有周日才会被执行, 变异改坏了也没人红
##     (memory `fb-gate-subject-never-constructed`)。
var strip_now_override: int = 0

## ★同上, 只给门禁与实拍: 强制把「决赛日玩法上线了没有」当成 是/否。
##   **-1 = 问规则, 产品永远是这个**(`verify_finals_feed` 有一条断言守住默认值)。
##   为什么要这个口子: `PHASE_MODE_LIVE` 是 **const 字典**, Godot 4 里改不了内容 ⇒
##   实拍没法"临时把决赛日打开"再去真按一下那扇门。
var strip_finals_live_override: int = -1


## ★`paint_now` = 本屏那一刻(`_ready` 传); 0 = 自己问一次
##   (`rebuild_week_page()` 走这一支 —— 它是**另一次刷屏**, 该读新的)。
## ★★兜底走 `_now_ts()`, 不就地读系统钟(2026-09-28, memory `fb-second-clock-drops-events`):
##   `strip_now_override` → `paint_now` → `_now_ts()`(→ `clock_override_ts` → `_P2C.now_utc()`)。
##   两个 override 都是 0 时行为逐字节不变(玩家路径一字未动)。
func _week_cards(paint_now: int = 0) -> void:
	var now: int = strip_now_override if strip_now_override > 0 \
		else (paint_now if paint_now > 0 else _now_ts())
	_sb_state_shown = _SB.service_state()
	_close_key_shown = _close_key(now)
	var box := Control.new()
	box.name = WEEK_CARDS_NAME
	box.position = WEEK_GRID_POS
	box.size = WEEK_CARD_SIZE * 2.0 + Vector2(WEEK_CARD_GAP, WEEK_CARD_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 放进赛程页(没有页面时 —— 门禁单独调这一段 —— 退回内容层)。
	(_week_pop if is_instance_valid(_week_pop) else content_root).add_child(box)
	_week_box = box          # D-1: 服务状态变了要能把它换掉
	for i in range(WEEK_PHASES.size()):
		var card := _week_card(week_card_info(str(WEEK_PHASES[i]), now))
		card.position = Vector2(float(i % 2), float(i / 2)) * (WEEK_CARD_SIZE + Vector2(WEEK_CARD_GAP, WEEK_CARD_GAP))
		box.add_child(card)


## 这个阶段占本周哪几天: [首日, 末日](ISO 1..7)。★只问 `phase_of_weekday`, 不另写一张星期表。
static func _phase_days(ph: String) -> Vector2i:
	var a := 0
	var b := 0
	for wd in range(1, 8):
		if _P2C.phase_of_weekday(wd) == ph:
			if a == 0:
				a = wd
			b = wd
	return Vector2i(a, b)


## 「周二 ~ 周五」/「周六」
static func _phase_days_text(ph: String) -> String:
	var d := _phase_days(ph)
	if d.x <= 0:
		return ""
	if d.x == d.y:
		return "周%s" % _WD_CN[d.x - 1]
	return "周%s ~ 周%s" % [_WD_CN[d.x - 1], _WD_CN[d.y - 1]]


## 决赛日玩法上线了没有(门禁/实拍可用 `strip_finals_live_override` 按成是/否; -1 = 问规则)。
func _finals_live() -> bool:
	return (_P2C.phase_mode_live(_P2C.PHASE_FINALS)
		if strip_finals_live_override < 0 else strip_finals_live_override == 1)


## 此刻那一档(倒计时 / 已截止 / 门 …)。★`_mode_countdown` / `_close_key` / 卡上的门三处共用这一个。
func _close_kind_at(now: int) -> String:
	return close_block_kind(_P2C.phase_at_utc(now), _finals_live(),
		_SB.service_state() == _SB.ST_MAINTENANCE, _P2C.close_left_sec(now), _P2C.can_start_match_utc(now))


## 赛程页一张卡要显示的全部内容。★纯数据, 门禁直接喂时间戳调它, 再与屏幕上那张卡逐字比。
##   phase / title / days / state(past·now·future) / today / time / locked / lock_text
##   / chips([[数字, 说明], …]) / points([一行, …]) / door("" · board · bracket)
## ★判据全是原来那几个函数:
##   阶段 = `phase_at_utc`; 当前阶段的时间 = `_mode_countdown`(模式卡第三行同一个);
##   门 = `close_block_kind`(原赛程条收盘块同一个分类); 锁 = `gauntlet_eligible` / `gauntlet_line_reached`
##   / `gauntlet_state` / `phase_mode_live` / `is_eliminated`(与开始战斗那扇门同一组)。
## ★数字一律读规则常量(HEARTS_MAX / RANKED_QUOTA / PROMOTE_WINS / GAUNTLET_* / FINALS_SHOP_SEC)。
func week_card_info(ph: String, now: int) -> Dictionary:
	var today: int = _P2C.iso_weekday_utc(now)
	var days := _phase_days(ph)
	var anchor: int = _P2C.week_anchor_utc(now)
	var state := "future"
	if today >= days.x and today <= days.y:
		state = "now"
	elif days.y < today:
		state = "past"
	var info := {
		"phase": ph,
		"title": str(_P2C.PHASE_LABEL.get(ph, ph)),
		"days": _phase_days_text(ph),
		"state": state,
		"today": state == "now",
		"locked": false,
		"lock_text": "",
		"chips": [],
		"points": [],
		"door": "",
	}
	## ── 上沿那条暗带的时间 ──
	if state == "now":
		info["time"] = _mode_countdown(now)
	elif state == "past":
		info["time"] = CARD_PAST_TEXT
	else:
		var start: int = anchor + (days.x - 1) * 86400
		if ph == _P2C.PHASE_FINALS:
			start = _utc_today_at(start, int(_P2C.FINALS_SEAT_HOUR_UTC))     # 决赛日按分组开赛那一刻(原赛程条「X 开赛」同一个时刻)
		info["time"] = "%s 开始" % _local_wd_hhmm(start)
	## ── 要点 ──
	var live: bool = _finals_live() if ph == _P2C.PHASE_FINALS else _P2C.phase_mode_live(ph)
	var chips: Array = []
	var pts: Array = []
	if not live:
		## 玩法没上线的阶段(周一休赛): 直说这天按什么规矩 —— 那一句只有 `phase_pending_note` 一处。
		var note: String = _P2C.phase_pending_note(ph)
		if note == "":
			note = "规则同%s" % str(_P2C.PHASE_LABEL[_P2C.PHASE_RANKED])   # 手动按成「没上线」而表里查不到时的兜底
		pts.append(note)
		if ph == _P2C.PHASE_REST:
			pts.append("版本更新在本日进行")
	else:
		match ph:
			_P2C.PHASE_RANKED:
				chips = [[int(_P2C.HEARTS_MAX), "条生命"], [int(_P2C.RANKED_QUOTA), "场上限"], [int(_P2C.PROMOTE_WINS), "胜晋级"]]
				pts = ["每负一场扣 1 条生命，耗尽即本周出局",
					"%d 胜获得周六闯关赛资格" % int(_P2C.PROMOTE_WINS),
					_local_stamp(_P2C.ranked_close_ts(anchor))]
			_P2C.PHASE_GAUNTLET:
				chips = [[int(_P2C.GAUNTLET_WINS_IN), "胜晋级"], [int(_P2C.GAUNTLET_LOSSES_OUT), "负出局"], [int(_P2C.GAUNTLET_QUOTA), "场上限"]]
				pts = ["不消耗生命",
					"晋级者参加周日决赛日",
					_local_stamp(_P2C.gauntlet_close_ts(anchor))]
			_P2C.PHASE_FINALS:
				chips = [[1, "负淘汰"], [int(_P2C.FINALS_SHOP_SEC / 60.0), "分钟备战"]]
				## ★2026-10-07 用户「那么上午就叫小组赛啊，晚上叫冠军杯赛」: 两段各自的开赛时刻都写出来。
				pts = ["%s %s · %s %s" % [_P2C.STAGE_GROUP,
						_P2C.local_hhmm(_utc_today_at(anchor + 6 * 86400, int(_P2C.FINALS_SEAT_HOUR_UTC))),
						_P2C.STAGE_CUP,
						_P2C.local_hhmm(_utc_today_at(anchor + 6 * 86400, int(_P2C.FINALS_START_HOUR_UTC)))],
					"组冠军进入%s，单败决出冠军" % _P2C.STAGE_CUP,
					"冠军、亚军、四强、组冠军获得头衔"]
	## ── 锁(只锁现在和以后; 过去的阶段只说「已结束」) ──
	if state != "past":
		match ph:
			_P2C.PHASE_RANKED:
				if GameState.is_eliminated():
					info["locked"] = true
					info["lock_text"] = "生命已耗尽 · 下周二可参加"
			_P2C.PHASE_GAUNTLET:
				if live and not (GameState.gauntlet_eligible() or GameState.gauntlet_line_reached()):
					info["locked"] = true
					## 胜场够了但生命耗尽(2026-10-03 S13: 14 胜的人被告知「打够 11 胜就能来」)
					if GameState.is_eliminated() and int(GameState.season_wins) >= int(_P2C.PROMOTE_WINS):
						info["lock_text"] = "积分赛生命耗尽 · 本周无法参加"
					else:
						info["lock_text"] = "积分赛 %d 胜可参加" % int(_P2C.PROMOTE_WINS)
			_P2C.PHASE_FINALS:
				if live and not (GameState.gauntlet_eligible() and GameState.gauntlet_state() == _P2C.GAUNTLET_IN):
					info["locked"] = true
					info["lock_text"] = "闯关赛 %d 胜可参加" % int(_P2C.GAUNTLET_WINS_IN)
	## ── 门(只在当天): 周六「全场赛况」/ 周日「对阵图」—— 档位与原赛程条收盘块同一个分类 ──
	if state == "now":
		var kind: String = _close_kind_at(now)
		if kind == BK_MAINTENANCE:
			var n := _SB.notice_text()
			pts.push_front(n if n != "" else "版本维护中")
		elif ph == _P2C.PHASE_FINALS and kind == BK_BRACKET_DOOR:
			info["door"] = WEEK_DOOR_BRACKET
		elif ph == _P2C.PHASE_GAUNTLET and _P2C.phase_mode_live(_P2C.PHASE_GAUNTLET) \
				and kind in [BK_COUNTDOWN, BK_LOCKED, BK_CLOSED_TODAY]:
			info["door"] = WEEK_DOOR_BOARD
	info["chips"] = chips
	info["points"] = pts
	return info


## 一块不可点的纯色面(像素风: 直角、不描边、不透明)。
func _flat_cell(parent: Control, r: Rect2, col: Color, nm: String = "") -> ColorRect:
	var c := ColorRect.new()
	if nm != "":
		c.name = nm
	c.color = col
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## 一个只用来定位的区块(卡上的暗带 / 抬头 / 正文 / 数字牌): 字挂在它下面, 对齐就按它的框算。
func _zone(parent: Control, nm: String, r: Rect2, col: Color) -> Control:
	var z := Control.new()
	z.name = nm
	z.position = r.position
	z.size = r.size
	z.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(z)
	_flat_cell(z, Rect2(Vector2.ZERO, r.size), col, "Fill")
	return z


## 一张阶段卡。结构照参考: 暗带(时间 + i) / 抬头(名字 + 副标题, 锁着时换成锁 + 条件) / 正文(数字牌 + 要点 + 门)。
func _week_card(info: Dictionary) -> Control:
	var ph := str(info["phase"])
	var locked := bool(info["locked"])
	var sz := WEEK_CARD_SIZE
	var card := Control.new()
	card.name = WEEK_CARD_PREFIX + ph
	card.size = sz
	card.custom_minimum_size = sz
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## 外框: 落影 + 深色描边; 今天那张外面再套一圈金边。
	_flat_cell(card, Rect2(Vector2(0.0, 6.0), sz), Color(0.0, 0.0, 0.0, 0.45), "Shadow")
	if bool(info["today"]):
		_flat_cell(card, Rect2(Vector2(-6.0, -6.0), sz + Vector2(12.0, 12.0)), CARD_TODAY_COL, "TodayFrame")
	_flat_cell(card, Rect2(Vector2(-3.0, -3.0), sz + Vector2(6.0, 6.0)), Color("#140a03"), "Outline")
	## ── 上沿暗带: 时间右对齐 + 右端「i」 ──
	var strip := _zone(card, "CardStrip", Rect2(0.0, 0.0, sz.x, CARD_STRIP_H), Color("#100906"))
	var tcol := Color("#ffc94a") if str(info["state"]) == "now" else Color("#cdbb9a")
	var tl := _place_outlined(str(info["time"]), 17, tcol, Vector2(CARD_PAD, 0.0), Vector2(sz.x - CARD_PAD - 46.0, CARD_STRIP_H))
	tl.name = "CardTime"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	strip.add_child(tl)
	card.add_child(_card_info_badge(info, Vector2(sz.x - 36.0, 3.0)))
	## ── 彩色抬头 ──
	var hcol: Color = CARD_LOCK_HEAD if locked else PHASE_HEAD_COL.get(ph, CARD_LOCK_HEAD)
	var head := _zone(card, "CardHead", Rect2(0.0, CARD_STRIP_H, sz.x, CARD_HEAD_H), hcol)
	_flat_cell(head, Rect2(0.0, 0.0, sz.x, 3.0), hcol.lightened(0.22))                 # 上亮边
	_flat_cell(head, Rect2(0.0, CARD_HEAD_H - 4.0, sz.x, 4.0), hcol.darkened(0.35))   # 下暗边
	var tx := CARD_PAD
	if locked:
		var lk := _pixel_lock(Vector2(CARD_PAD, (CARD_HEAD_H - 45.0) / 2.0), 3.0)
		head.add_child(lk)
		tx += 36.0 + 14.0
	var title := _place_outlined(str(info["title"]), 34, Color("#d8d2cc") if locked else Color("#fff4d6"),
		Vector2(tx, 3.0), Vector2(sz.x - tx - CARD_PAD, 44.0))
	title.name = "CardTitle"
	title.add_theme_constant_override("outline_size", 8)
	head.add_child(title)
	var sub_txt: String = str(info["lock_text"]) if locked else str(info["days"])
	var sub := _place_outlined(sub_txt, 19, Color("#ffe08a") if locked else Color("#ffe9c4"),
		Vector2(tx, 47.0), Vector2(sz.x - tx - CARD_PAD, 26.0))
	sub.name = "CardSub"
	head.add_child(sub)
	## ── 正文 ──
	var body_h: float = sz.y - CARD_STRIP_H - CARD_HEAD_H
	var body := _zone(card, "CardBody", Rect2(0.0, CARD_STRIP_H + CARD_HEAD_H, sz.x, body_h),
		CARD_LOCK_BODY if locked else CARD_BODY_COL)
	var y := 14.0
	var chips: Array = info["chips"]
	for i in range(chips.size()):
		var c: Array = chips[i]
		var chip := _zone(body, "Chip%d" % i, Rect2(Vector2(CARD_PAD - 2.0 + float(i) * (CARD_CHIP_SIZE.x + 10.0), y), CARD_CHIP_SIZE),
			Color("#1a1412") if locked else Color("#170d07"))
		## 数字一行、说明一行, 各自一个定位框(字按框居中)。偏移是帧差实测的墨迹偏差(tests/_probe_textpos.gd):
		##   m6x11 数字字形整体偏左 1.5、偏下 2; 中文 15 号偏左 1、偏下 1.5。
		var nrow := Control.new()
		nrow.name = "ChipNumRow"
		nrow.position = Vector2(0.0, 3.0)
		nrow.size = Vector2(CARD_CHIP_SIZE.x, 32.0)
		nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(nrow)
		var num := _place_outlined(str(c[0]), 28, Color("#bdb6ae") if locked else Color("#ffd34a"), Vector2(1.5, -2.0), Vector2(CARD_CHIP_SIZE.x, 32.0))
		num.name = "ChipNum"
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nrow.add_child(num)
		var crow := Control.new()
		crow.name = "ChipCapRow"
		crow.position = Vector2(0.0, 35.0)
		crow.size = Vector2(CARD_CHIP_SIZE.x, 20.0)
		crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(crow)
		var cap := _place_outlined(str(c[1]), 15, Color("#a8a29c") if locked else Color("#e8d6b0"), Vector2(1.0, -1.5), Vector2(CARD_CHIP_SIZE.x, 20.0))
		cap.name = "ChipCap"
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crow.add_child(cap)
	if not chips.is_empty():
		y += CARD_CHIP_SIZE.y + 10.0
	var door := str(info["door"])
	var text_w: float = sz.x - CARD_PAD * 2.0 - ((150.0 + 12.0) if door != "" else 0.0)
	var pts: Array = info["points"]
	for k in range(pts.size()):
		var pl := _place_outlined(str(pts[k]), 17, Color("#b4ada6") if locked else Color("#ecdcbc"),
			Vector2(CARD_PAD, y + float(k) * CARD_LINE_H), Vector2(text_w, CARD_LINE_H))
		pl.name = "CardPoint%d" % k
		body.add_child(pl)
	## 门: 周六「全场赛况」/ 周日「查看对阵图」。目标与原赛程条那两扇门同一处(`_open_gauntlet_board` / `_open_bracket_map`)。
	if door != "":
		var d: Button = _finals_entry() if door == WEEK_DOOR_BRACKET else _gauntlet_board_door()
		d.position = Vector2(sz.x - CARD_PAD - 150.0, body_h - 81.0 - 12.0)
		body.add_child(d)
	if str(info["state"]) == "past":
		card.modulate = Color(0.72, 0.72, 0.72)
	return card


## 暗带右端的「i」: 点了飘一行这张卡的要点(参考里那颗 i 也是「这个模式怎么玩」)。
## ★看得见的是 22×22 小方块, 点击区按触摸线 81 铺开(居中在小方块上)。
func _card_info_badge(info: Dictionary, pos: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "CardInfo"
	holder.position = pos
	holder.size = Vector2(24.0, 24.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat_cell(holder, Rect2(0.0, 0.0, 24.0, 24.0), Color("#140a03"))
	_flat_cell(holder, Rect2(2.0, 2.0, 20.0, 20.0), Color("#2f6fb8"))
	var cap := _place_outlined("i", 18, Color("#fff4d6"), Vector2(1.5, 2.5), Vector2(24.0, 24.0))   # +1.5/+2.5: 帧差实测对准方块中心
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", load("res://assets/fonts/m6x11.ttf"))
	cap.add_theme_constant_override("outline_size", 4)
	holder.add_child(cap)
	var b := Button.new()
	b.name = "CardInfoTap"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.position = Vector2(12.0 - ROW_H / 2.0, 0.0)
	b.size = Vector2(ROW_H, CARD_STRIP_H + 20.0)
	var parts: Array = []
	for c in (info["chips"] as Array):
		parts.append("%s %s" % [str(c[0]), str(c[1])])
	parts.append_array(info["points"] as Array)
	var msg := "%s · %s" % [str(info["title"]), "，".join(PackedStringArray(parts))]
	b.pressed.connect(func() -> void: _toast(msg))
	holder.add_child(b)
	return holder


## 「周六 07:00」(玩家本地时区)。★时区换算只在 `_local_dict` 一处。
func _local_wd_hhmm(utc_ts: int) -> String:
	var d := _local_dict(utc_ts)
	var w: int = int(d.get("weekday", 0))
	var wi := 7 if w == 0 else w
	return "周%s %02d:%02d" % [_WD_CN[wi - 1], int(d.get("hour", 0)), int(d.get("minute", 0))]


## 此刻属于哪一档(倒计时 / 已截止 / 今日已截止 / 门 / 维护 …)。
## 模式卡第三行(`_mode_countdown`)与赛程页卡上的门(`week_card_info`)都按它分。
## 那一档属于哪一类。★**纯静态函数**, 门禁能把四个入参穷举着喂 ——
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


## 周日决赛日那扇门通到哪。★具名常量 —— 门禁拿它去验"目标场景真的存在",
##   写死成字符串的话门禁就只能自己再抄一遍(抄一次永远落后一次)。
const BRACKET_SCENE := "BracketMap"


## 周日决赛日的门。★一整块都能按 —— 那一格本来就只有两行字, 做成"字旁边一个小按钮"
##   反而更难点中(触控下限 81px 是全项目同一条线)。
func _finals_entry() -> Control:
	## ★★2026-09-27 去掉行尾的「→」。它跟上面状态行那个「›」是同一族:
	##   网页的「更多 →」写法 —— 用一个箭头告诉人"这里可以点"。
	##   这一整块本来就是一个 150×81 的按钮(触控下限), 不需要箭头来交代。
	var b := _door("查看对阵图", _open_bracket_map)
	b.name = "BracketDoor"
	return b


## 周六赛况板那扇门(周末看回放 2026-10-04, docs/plans/20261004-周末看回放.md)。
## ★与周日「看对阵图」**同一扇门**(`_door`: 同一张 `ui/panel-wide.png`、同一个尺寸) —— 不另造一种长相。
const GAUNTLET_BOARD_SCENE := "GauntletBoard"
const GAUNTLET_BOARD_LINE := "全场赛况"


## 周六卡上那扇门: 与周日「查看对阵图」同一扇门(`_door`: 同一张黄铜门牌、同一个尺寸)。
func _gauntlet_board_door() -> Button:
	var b := _door(GAUNTLET_BOARD_LINE, _open_gauntlet_board)
	b.name = "GauntletBoardDoor"
	return b


func _open_gauntlet_board() -> void:
	_go(GAUNTLET_BOARD_SCENE)


## 赛程页卡上那扇门(周日对阵图 / 周六赛况板共用)。
func _door(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 81)
	b.text = text
	b.add_theme_font_size_override("font_size", 18)   # 2026-10-06: 15 号细体比卡上其它字弱一截 ⇒ 18 号粗体
	b.add_theme_font_override("font", _bold_font())
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
	return "%s 截止" % _local_wd_hhmm(utc_ts)


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
			return "本大轮首战后解锁"
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
			return "已出局"
		SHOP_LOCK_QUOTA:
			return "场次已用完"
		SHOP_LOCK_FIRST:
			return "首战后解锁"
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
		return "本大轮已出局 · %s" % tail
	return "本大轮已出局 · 下周一重置"


func _msg_quota_full() -> String:
	var q: int = int(_P2C.RANKED_QUOTA)
	var tail: String = _gauntlet_ahead_tail()
	if tail != "":
		return "本周 %d 场已用完 · %s" % [q, tail]
	return "本周 %d 场已用完 · 下周一重置" % q


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
			return "本周未晋级 · 积分赛生命已耗尽 · 下周一重置"
		return "本周未晋级 · 下周一重置 · 积分赛 %d 胜可参加" % int(
			_P2C.PROMOTE_WINS)
	var st: String = GameState.gauntlet_state()
	if st == _P2C.GAUNTLET_IN:
		return "已晋级决赛日（%s）· 周日开赛" % _P2C.gauntlet_label(
			int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	if st == _P2C.GAUNTLET_OUT:
		return "闯关赛已出局（%s）· 下周一重置" % _P2C.gauntlet_label(
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
	## ★周一休赛(用户原稿: 周一 = 休赛期·发奖/终榜公示; 2026-10-05「周一哪来的比赛」)。
	##   原来周一照常能打积分赛且计入本周场次 —— 实现漏洞, 不是设计。
	if _P2C.phase_at_utc(ts) == _P2C.PHASE_REST:
		return "今日休赛 · 积分赛周二开启"
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


## 右上「?」: 弹新手教程选择框(「开始教程 / 取消」)。与首启同一个框(scripts/scenes/tutorial_choice.gd)。
## ★2026-10-07 方案书 §4.3: 原来这里是一块单独手写的弹窗, 文案口语化(「先下场练练 / 来一场热身局, 我教你挑龟、摆阵 /
##   开打 / 等会儿」), 且是全游戏唯一重开教程的入口 —— 与首启各走各的。现在两处共用一个框。
func _on_tutorial() -> void:
	TutorialChoice.open(self, false)


## 首次打开 → 弹选择框「开始教程 / 跳过」(用户 2026-10-07「一般是有跳过和开始教程选项啊」)。
## 已看过(onboarded) / ONBOARD=0 → 不弹; ONBOARD=1 → 强制弹(门禁用)。
func _maybe_first_launch_tutorial() -> void:
	if OS.get_environment("ONBOARD") == "0":
		return   # 显式关(测试/开发)
	var force := OS.get_environment("ONBOARD") == "1"
	# ★只在【真正作为当前主场景】时触发 —— 冒烟/门禁把主菜单当子节点 instantiate() 时不弹。
	if not force and get_tree().current_scene != self:
		return
	if not force and GameState.tutorial_active:
		return   # 已经在教程里(防重入)
	## ★老存档迁移(方案书 §4.3): 打过积分赛却没有 onboarded 标记的号(早期 ONBOARD=0 建的 sim 号 / 老玩家)
	##   ⇒ 静默记成看过, 不弹框。
	if not force and not GameState.onboarded and (int(GameState.season_total_battles) > 0 or not GameState.match_history.is_empty()):
		GameState.onboarded = true
		GameState.save()
	if not force and GameState.onboarded:
		return
	TutorialChoice.open(self, true)


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
		if not _SB.finals_tried() or not _SB.finals_week_tried():
			return                                    # 还在路上(我那组 + 冠军杯赛两份都要等回音)
		_ft_sent = false
		var v: Dictionary = _SB.finals_cached()
		if str(v.get("reason", "")) != _SB.UNREACHABLE:
			## 问到了: 有桶就走那条链; 没桶(观众 / 人不够)那条链自己会一个字都不记。
			_BMS.record_progress_from(v)
			## ★冠军杯赛(2026-10-07): 冠军 / 亚军 / 四强从杯那一张来 —— 不进对阵图也要对得上账。
			##   服务端没部署 / 没成表 ⇒ `finals_cup_cached()` 是空的, 那条链一个字都不记。
			_BMS.record_cup_from(_SB.finals_cup_cached())
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
	_SB.finals_week_clear()
	_SB.fetch_finals_week_async(_ft_week)
	_ft_sent = true


func _finals_title_stop() -> void:
	if is_instance_valid(_ft_timer):
		_ft_timer.stop()
		_ft_timer.queue_free()
	_ft_timer = null
