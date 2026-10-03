extends Control

## MainMenuScene — 主菜单, 1:1 PoC MainMenuScene.ts 布局.
## 设计台 1280×720. 标题menu-title图@(240,130) / 左栏btn-frame按钮(360×87)中心x=240 /
## 右墙 frame-coin龟币框 + 4个frame-square磁贴(图鉴/教程/排行榜/战绩, 仅图标).

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
## 拆墙之后那句非阻塞提示要把人送到【绑定屏】去, 而那一屏的代码在设置页那侧
## ⇒ 跨场景传一个 static 布尔 `open_bind_on_entry`。
## ★不在这边再建一份绑定 UI: 抄一份就要把昵称那一行和验证码状态机抄第二遍
##   (memory `fb-hand-rolled-copies-drift`)。
const _SET := preload("res://scripts/scenes/SettingsScene.gd")

const W := 1280
const H := 720
const LEFT_CX := 240        # 标题图中轴 (原 LEFT_PAD60 + 按钮宽360/2; 按钮栈已重排, 只剩标题在用)
                            # 排行榜/图鉴/教程/战绩 走右侧 4 磁贴。4×(87+12)=396 → 234..630 < 720, 不溢出。
                            # 〔原注释写"5 入口…排行榜"= 陈旧, 排行榜早就挪到右侧磁贴了〕
const WALL := 16

## ── 左栏按钮栈的几何 (2026-08-15 版式体检) ──
## ★抽成常量是因为【右信息板要和这个栈对齐到同一条竖直带】: 两边各写各的坐标,
##   就是上一版右下角空出 560×161 一大块、而左栏比右栏长 140px 的根因。
##   verify_mainmenu_layout 会量真实 rect 断言两栏首尾各差 ≤2px。
## ── 版面 (2026-09-17 重做) ────────────────────────────────────────────────
## 原版式是【三块等高圆角卡并排】: 左栏 6 个木框按钮 / 中间赛程日历 / 右边 560×398 的
## 赛季表格。用户: 「你不觉得很丑吗, 市面上哪里有游戏会这么排版呢」—— 他是对的。
##
## 从 Game UI Database 的 Main Menus 分类下了 8 张真实主菜单逐张看, 共同点四条,
## 这一版就是照这四条重排的(对照印相在方案书里):
##   ① 画面主体是【游戏世界本身】 —— Absolum / Black Jacket / Replaced 右侧全是角色群像,
##      Fuga / Zombie Rollerz 干脆让角色铺满整屏。⇒ 背景换成 28 只龟的群像(_bg)。
##   ② 次级入口是【无框文字】 —— 8 张里 4 张如此。木框只留给主 CTA。
##   ③ 玩家数据【贴角成小胶囊】 —— Zookeeper World 右上金币/钻石、WarioWare 右上 950。
##      没有一张把它做成占屏 24% 的竖排表格。⇒ 赛季数据压成一行(_status_row)。
##   ④ 主 CTA 【又大又孤立】 —— Zookeeper World 的巨型绿 PLAY 在右下角(横屏右手拇指位)。
##      ⇒ 开始战斗挪到右下, 是全屏唯一的大木框。
##
## ★竖向预算是被【触摸线】锁死的: 可点元素短边 ≥81 视口像素(=44pt, 见 _probe_ui_layout)。
##   所以左栏只放得下 1 个状态行 + 4 个入口 (5×81=405), 训龟大师因此挪到右栏跟主 CTA 一组
##   —— 它俩都是"出战准备"语义, 放一起也讲得通, 不是硬塞。
const LOGO_CY := 106.0                      # 标题图中心 y (原 130, 上移给状态行腾位)
const LOGO_SCALE := 0.98                    # 原 1.1
const ROW_H := 81.0                         # ★触摸线: 44pt = 81 视口像素, 左栏每行都吃它
const LEFT_X := 48.0                        # 左栏左沿 (= WALL*3, 与 LOGO 左沿对齐)
const LEFT_W := 382.0                       # 左栏宽
const STATUS_Y := 210.0                     # 状态+战绩行 顶沿
## ★★状态行是【两行】(2026-09-28)。这个名字同时是**那两行文字的容器节点名**,
##   门禁按它从场景树里把那一块抓出来量真实 rect —— 不靠"第几个子节点"这种会漂的定位。
## 为什么拆两行, 见 `_status_row()` 头上那段(量出来的: 周六那句 ink 485px / 框 374px)。
const STATUS_TWO_LINE := "StatusTwoLine"
## 三段文字在 holder 里的顶沿与字号。★抽成常量是因为**竖向一分都涨不了**
##   (剖面见 `_status_row()` 头注), 三段必须塞进原来的 ROW_H=81 里, 数字改一个就要重算全部。
##   眼睛看不出"差 1px 就顶穿", 所以把它们摆成一张表, 旁边写清各自的实测行高。
const STATUS_L1_Y := 1.0                    # 身份行: 18 号字实测行高 27 ⇒ 占 0..29(含 ±1 描边)
const STATUS_L2_Y := 29.0                   # 今天行: 17 号字实测行高 25 ⇒ 占 28..55
const STATUS_L3_Y := 54.0                   # 战绩行: 17 号字 ⇒ 占 53..80, 底下还剩 1px
const STATUS_L1_FONT := 18                  # 身份行
## ★L2 与 L3 **共用**这一个字号(17): 它们是同一档「次级读数」, 不许各写一个 17 ——
##   同一个数存两份, 改一处漏一处(memory `fb-hand-rolled-copies-drift`)。
const STATUS_L2_FONT := 17                  # 今天行 + 战绩行
const MENU_Y := 299.0                       # 四个次级入口 顶沿
const MENU_N := 4
const HERO_SIZE := Vector2(508.0, 158.0)    # 主 CTA: 全屏唯一大木框, 右下角
const HERO_POS := Vector2(732.0, 462.0)
## 训龟大师【明显更窄】并与主 CTA 右沿对齐 —— 第一版两个框同宽 472, 实拍出来分不出主次,
## 而参考里主 CTA 永远是压倒性的(Zookeeper World 的绿 PLAY / Fuga 的橙高亮条)。
const TRAINER_SIZE := Vector2(340.0, 82.0)   # ★82 不是 78: 触摸线 81 视口像素(=44pt), 78 差 3px 门禁当场红
const TRAINER_POS := Vector2(900.0, 344.0)  # 900+340 = 1240 = 732+508, 右沿同轴; 与主 CTA 留 36px
## ★★★赛程条是**贴底对齐**的, 不是写死顶沿(2026-09-27 修)。
##   起因: 周日那一格放的是「决赛日 看对阵图」按钮, 它高 **81**(触控下限 44pt = 81 视口像素,
##   比 STRIP_H 的 68 还高) ⇒ 整条被撑到 95, 而写死 `y = 636` 让底边落在 **731 > 720**,
##   `verify_mainmenu_layout ①` 与 `verify_ios_ui` 双双判红(越界 18 个)。
##   ⚠ 这个 bug **一周只有周日看得见** —— 又一条「判据挂在星期几上」: 门禁一直在守,
##   只是它和这个形状一周才碰一次面。(同族已修四条, 见 v0.19.446。)
## ⇒ 顶沿 = `STRIP_BOTTOM - 实际高`, 条子多高都贴着底, 不会掉出屏幕。
const STRIP_BOTTOM := 719.0                 # 被撑高时的底沿上限(见 `_week_strip` 里那段)
const STRIP_Y := 636.0                      # = STRIP_BOTTOM - STRIP_H, 常规高度下的顶沿
const STRIP_H := 68.0
const STRIP_X := 48.0
const STRIP_W := 884.0
## ★★★今天那一格的上下留白(九宫格亮牌的内边距)。这个数字是**量出来的**:
##   `ui/panel-wide-on.png` 真实边带 8px, 而 `verify_ui_consistency._band_of`
##   从贴图中心往外扫到的是 **7**(实测, 见 `tests/_probe_mmprofile.gd`)。
##   两行字实测共 **45px** ⇒ 格高 = 9 + 45 + 9 = **63**, 字块居中后
##   距边带内沿还剩 **2px** ⇒ 「文字压边带」那条棘轮(主菜单基线 2, 只降不升)不会涨。
## ⚠ 改小了(比如 7)字就骑在金属边带上; 改大了条子变高, 而**周日**那天
##   条高 = 门按钮 81 + 上下 margin, 顶沿与左栏栈底实测只差 **1px**。
const STRIP_TODAY_PAD := 9.0
## 训龟大师: 原 300×62 (4.84:1, 全场最扁) 且离 2×2 网格 71px = 看着像掉队的孤儿。
## 改成与网格同高 82 (3.66:1), 并按网格自己的 14px 节奏紧贴其下 —— 归队, 不再单飞。

## 字号层级 (原来 hero27 / 面板标题25 / 次级22 / 行20 —— 主次只差 5 号, 分不出层)
const FONT_HERO := 30
const FONT_BTN := 22
const FONT_VERSION := 16

var page_box: Control       # 当前页按钮容器
var content_root: Control   # 内容层 (1280×720 设计框, 居中于真实视口); 背景另铺满全窗口
var _bg_tile: TextureRect   # 背景图 (resize 时重设尺寸)
var _bg_is_crowd := false   # true=28龟群像(铺满视口) / false=旧平铺纹理(要+512给漂移)


func _ready() -> void:
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
	## ★★决赛日那一场的**结果**也要补报 —— 与上面那句同一层、同一个理由:
	##   「那一刻可能没网, 而那一刻只有一次」。漏报会让那一场只能靠 960 秒宽限兜,
	##   **可能把错的人送进下一轮**(2026-09-27)。
	_BE.retry_finals_report()
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
	_week_strip(paint_ts)       # 左右两栏之间那条空档 → 本周赛程条(吃 paint_ts, 不再自己读钟)
	## ★D-1: 去问一次服务状态(没配后端时这一句什么都不做, 连节点都不建)。
	##   答复是异步回来的 ⇒ 配一个**挂在自己身上的 Timer 子节点**轮询状态变没变,
	##   变了就重建赛程条。★不能用 `get_tree().create_timer` 接闭包 ——
	##   那种计时器活过场景释放, 响的时候去绑已释放的捕获就报错
	##   (`tools/tree_timer_audit.py` 守这条, 它推荐的修法就是 Timer 子节点)。
	_SB.fetch_status_async()
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
		## 群像是【一张图】按 COVERED 填满视口; 只有平铺才需要比屏幕大一格(512)给漂移留量。
		## 原来无条件 +512 —— 换成群像后会把图放大到超出视口, 右下角内容被推出画面。
		_bg_tile.size = vp if _bg_is_crowd else Vector2(vp.x + 512, vp.y + 512)


# 不再 _exit_tree 还原 KEEP: 项目级 aspect 已是 EXPAND(全场景统一), 离场不翻转 → 场景切换丝滑。
#   各场景背景铺满已各自处理(menu平铺/select-bg/Codex全锚), 无需切回 KEEP。


func _bg() -> void:
	# PoC (index.html menu-bg-active + BootScene:579): 菜单背景 = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var vp := get_viewport_rect().size   # 真实视口(EXPAND 后=窗口比例); bg 全填它, 含原黑边区
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color("#1a3a2a")   # 深绿底 — 用 PoC 字面色值, 不四舍五入
	add_child(base)
	# ★2026-09-17 背景换成【28 只龟的群像】(menu-bg-crowd.png)。
	#   原来是 menu-bg-tile.png 平铺装备暗纹 + 25s 漂移 —— 一张淡到几乎看不见的纹理,
	#   等于把屏幕上最大的一块画布浪费掉了。而实拍参考里 Fuga / Zombie Rollerz 的做法是
	#   【让角色自己铺满整屏当背景】, 这个游戏正好有 28 只龟。
	#   图由 tools/build_menu_crowd_bg.py 从 data/pets.json 的第 0 帧合成(五层纵深 + 左侧压暗),
	#   不是手画的 —— 加龟/换立绘重跑一次就同步。
	#   ⚠ 不再漂移: 平铺纹理漂移看不出接缝, 而群像有具体内容, 一动就穿帮。
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-crowd.png"):
		var crowd := TextureRect.new()
		crowd.texture = load("res://assets/sprites/menu/menu-bg-crowd.png")
		crowd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# COVERED: 非 16:9 视口下【填满 + 居中裁切】, 不留黑边也不拉变形
		crowd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		crowd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风, 放大不许插值糊掉
		crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowd.size = vp
		crowd.position = Vector2.ZERO
		add_child(crowd)
		_bg_tile = crowd
		_bg_is_crowd = true
	elif ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		# 回退: 群像图没导入时仍走原来的平铺, 免得整屏纯色
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		_bg_tile = tile
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40), 压暗背景
	# 显式设 offsets+colors (别用 set_color/add_point — Gradient 默认 offset1 是白点, 会漏成底部白光)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	## ★用群像背景时遮罩要减半: 那张图在生成阶段就已经压暗(×0.62)+暗角了,
	##   再叠原来给【平铺纹理】调的 0.15~0.40, 整屏黑成一团、龟全看不见。
	##   (平铺那条回退路仍走原值, 免得它跟着一起变。)
	var _soft := _bg_is_crowd
	grad.colors = PackedColorArray([
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.06 if _soft else 0.15),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.10 if _soft else 0.25),
		Color(8.0 / 255.0, 12.0 / 255.0, 20.0 / 255.0, 0.22 if _soft else 0.40),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 8; gt.height = 128
	var ov := TextureRect.new(); ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt; ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
	# (金色飘落粒子已移除 — 用户要求去掉; PoC 虽有 add.particles 但实机极淡, Godot 渲染显突兀)


func _title() -> void:
	# 标题图 menu-title.png. PoC MainMenuScene.ts:54-65:
	#   TITLE_W360 TITLE_H203, 中心 origin0.5; 起点 center=(LEFT_CX240, TITLE_BASE_Y130-180=-50),
	#   scale0.85 alpha0 → tween 到 center y130, scale TITLE_SCALE1.1, alpha1, duration550 delay250 EASE_MENU_IN.
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
		var end_top_y := LOGO_CY - 101.5                # center → 左上 y
		var start_top_y := LOGO_CY - 180.0 - 101.5      # 起点在屏外上方(原 PoC: center-180)
		t.position = Vector2(LEFT_CX - 180, start_top_y)
		t.scale = Vector2(0.85, 0.85); t.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.25)                          # PoC delay 250ms
		tw.tween_property(t, "position:y", end_top_y, UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "scale", Vector2(LOGO_SCALE, LOGO_SCALE), UIPalette.T_SLOW).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(t, "modulate:a", 1.0, UIPalette.T_SLOW)
		return
	else:
		var l := Label.new(); l.text = "斗龟场"; l.add_theme_font_size_override("font_size", 80)
		l.add_theme_color_override("font_color", Color("#ffd93d")); l.position = Vector2(LEFT_CX - 150, 90); content_root.add_child(l)


# ─── 左栏按钮页 (实时版: 单一干净主菜单, 无子页过场) ───
## 实时版重做: 去掉回合制残留的多页(online/local)+过场飞出/飞入逻辑.
##   主菜单就一组清晰按钮(各自从左滑入入场), 点击直接 _go 切场景, 不再有页间过场.
##   (2026-08-15 删掉了只剩一页还在传"页名"的 _show_page/_active_page —— 单页了就别再演多页。)


## 左栏四个入口的第 i 行顶沿。★一个来源 —— 状态行、入口、赛程条都靠它算,
## 各自写死就会在改版时漂开(原版式的信息板就是因为这个跟左栏栈对不齐过)。
func _menu_row_y(i: int) -> float:
	return MENU_Y + float(i) * ROW_H


## 左栏内容的下沿 (最后一个入口的底)
func _menu_bottom() -> float:
	return _menu_row_y(MENU_N - 1) + ROW_H


## 建主菜单的可点元素 (2026-09-17 版式重做, 见文件头的四条参考结论):
##   左栏  背包 / 商店 / 图鉴 / 排行榜   —— 无框文字, 每行 ROW_H
##   右栏  训龟大师(小木框) + ⚔开始战斗(巨型木框, 全屏唯一大框)
## 原版式是 1 个英雄键 + 2×2 网格 + 训龟大师, 六个木框全挤在左栏。
## ★`now` = 本屏那一刻(`_ready` 传)。**商店锁就指这一刻** —— 不传的话
##   `ranked_quota_full()` 兜底去读真实系统钟, 于是本屏就有两条钟
##   (详见 `_ready` 里 `paint_ts` 那段 + 探针 `tests/_probe_twoclocks.gd`)。
func _build_page_buttons(now: int = 0) -> void:
	var ts: int = now if now > 0 else _now_ts()
	## ★★★两颗按钮的锁**都从各自那条真判据取**(2026-09-29 台账 ④):
	##   原来商店的锁在这里就地写了一遍 `<=0 or eliminated or quota_full`, 而
	##   `_open_shop()` 里又写了一遍 —— 同一件事两份公式(memory `fb-hand-rolled-copies-drift`);
	##   「开始战斗」更糟: 画的锁只看 `eliminated`, 而它自己的门 `_battle_block_msg()` 还管
	##   **配额打满**与**周末阶段** ⇒ 打满 24 场后它**照样亮着**, 点下去只飘一行 1.9 秒的字,
	##   而同屏的商店已经正确上锁。玩家读到的是「能打」, 门说的是「不能打」。
	##   ⇒ 现在两颗都是「问那扇门自己」: 门说拦 ⇒ 画锁。判据 PLAY_LOCK_SAME_SOURCE 守着。
	var shop_locked := _shop_block_msg(ts) != ""
	var battle_locked := _battle_block_msg(ts) != ""
	var mic := "res://assets/sprites/menu/"
	var subs: Array = [
		["背包", func(): _go("Inventory"), mic + "ic-bag.png", false],
		[SHOP_LABEL, func(): _open_shop(), mic + "ic-shop.png", shop_locked],
		["图鉴", func(): _go("Codex"), mic + "ic-codex.png", false],
		["排行榜", func(): _go("Leaderboard"), mic + "ic-trophy.png", false],
	]
	for i in range(subs.size()):
		var sN: Array = subs[i]
		var e := _text_entry(str(sN[0]), sN[1], str(sN[2]), bool(sN[3]))
		e.position = Vector2(LEFT_X, _menu_row_y(i))
		page_box.add_child(e)
		_slide_in_left(e, i)
	# ── 训龟大师: 挪到右栏、贴在主 CTA 正上方 ──
	#    它跟「开始战斗」是同一件事的两步(配大师 → 出战), 放一起比塞在左栏列表里更讲得通;
	#    直接原因则是竖向预算: 左栏 5×81 放不下(见文件头"触摸线"那段)。
	## ★★2026-09-27 去掉文字里的 emoji「🐢」(用户:「全是 ai 味和网页味」)。
	##   实拍放大看得很清楚: emoji 走的是**系统彩色字体**(平滑抗锯齿的圆润小龟),
	##   而它正贴在一块像素木牌上 —— 两种画法并排, 一眼就是"拿 emoji 当图标"。
	##   (`verify_fonts` 早就记着 m6x11/NotoSansSC 里没有 🐢 ⇒ 它一定是 fallback
	##    到 NotoEmoji 或系统 emoji 字体画出来的, 与像素风无关。)
	## ★不换成别的图标: 仓里没有"训龟大师"的图标素材, 拿别件的顶替是本项目的铁律禁区。
	##   木牌上只留字, 反而更像市面上的像素游戏。
	var tb := _frame_button("训龟大师", func(): _go("TrainerConfig"), false, TRAINER_SIZE, FONT_BTN, "")
	tb.position = TRAINER_POS
	page_box.add_child(tb)
	_slide_in(tb, 4)
	# ── ⚔ 开始战斗: 右下角巨型主 CTA ──
	#    位置照 Zookeeper World 的绿 PLAY —— 横屏手机右手拇指的落点, 也是全屏唯一的大木框。
	## ★同上: 去掉「⚔」。这个字符在本项目的字体链里是**单色 emoji 兜底**画的,
	##   实拍是一对细线条的交叉剑 —— 旁边整块木牌都是 3~4px 的像素笔触, 它是唯一的矢量线条。
	##   全屏唯一的主 CTA 上, 一行大金字比一个外来字形更立得住。
	var hero := _frame_button("开始战斗", func(): _start_battle_flow(), false, HERO_SIZE, FONT_HERO, "", battle_locked)
	hero.position = HERO_POS
	page_box.add_child(hero)
	## ★锁要**看得见地静态存在**: 灰框 + 🔒 角标。原来只有"点下去飘一行 1.9 秒的字",
	##   而那一行还压在 LOGO 上 —— 一个状态不该只在瞬时提示里存在。
	if battle_locked:
		_add_lock_badge(hero, HERO_SIZE)
	_slide_in(hero, 5)


## 【非阻塞提示】位置与大小。
## ★x / 宽与主 CTA **同轴**(右栏那一叠从上到下: 提示 → 训龟大师 → 开始战斗),
##   高 = `ROW_H`(81 视口像素 = 44pt), 与全屏所有靶子同一条触摸线。
## ★y 是**算出来的空地**: 它的底沿 240+81 = 321, 训龟大师顶沿 `TRAINER_POS.y` = 344
##   ⇒ 留 23px; 头上那排货币/磁贴到 y≈115 就结束了。两边都不挤。
const NUDGE_SIZE := Vector2(508.0, 81.0)
const NUDGE_POS := Vector2(732.0, 240.0)


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


## 左栏的一个无框文字入口。
## ★"无框"是照参考来的(Absolum / Black Jacket / Replaced / Fuga 的次级项都没有框),
##   但【可点区域仍然是整行 LEFT_W×ROW_H】—— 视觉轻、手指目标不小, 两件事不能混为一谈。
## 悬停时: 左侧 ◆ 淡入 + 文字右移 6px + 一层金色底光, 代替原来那个木框。
func _text_entry(label: String, cb: Callable, icon_path: String, locked: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(LEFT_W, ROW_H)
	holder.size = Vector2(LEFT_W, ROW_H)
	var glow := ColorRect.new()                     # 悬停底光(默认全透明), 放最底层
	glow.color = Color(1.0, 0.85, 0.24, 0.0)
	glow.size = Vector2(LEFT_W, ROW_H)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	var dia := _place_stroked("◆", 18, Color("#ffd93d"), Vector2(0, ROW_H / 2.0 - 14), Vector2(26, 28))
	dia.modulate.a = 0.0
	holder.add_child(dia)
	var tx := 30.0
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var it := TextureRect.new()
		it.texture = load(icon_path)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.size = Vector2(40, 40)
		it.position = Vector2(tx, ROW_H / 2.0 - 20)
		it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if locked:
			it.modulate = Color(0.55, 0.55, 0.58)
		holder.add_child(it)
		tx += 52.0
	# 文字: 背景是龟群像(有明有暗), 所以一律带黑描边 —— 纯色字在群像上会读不出
	var col := Color("#8d9099") if locked else Color("#ffe9a8")
	var lb := _place_stroked(("🔒 " if locked else "") + label, 26, col,
		Vector2(tx, ROW_H / 2.0 - 21), Vector2(LEFT_W - tx - 8.0, 42))
	holder.add_child(lb)
	## (不画分隔线: 第一版画了, 实拍出来那条线横跨在背景的龟身上, 把版面切碎了。
	##  参考里的无框菜单 Absolum / Black Jacket / Replaced 一条分隔线都没有 —— 行距本身就够分行。)
	# 透明按钮铺满 = 真正的点击区 (整行 382×81, 过 44pt 触摸线)
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	## ★先设 size 再 set_anchors_preset(FULL_RECT) 会把 size 当成 offset 叠上去 ——
	## 门禁实测这个 Button 变成 764×162(正好 2 倍), 于是相邻两行互相压住、还压到右下的主 CTA。
	## 同一个坑 `_version_stamp` 的注释里写过(「锚点先掰回再设 size/position」), 这次是反向踩的。
	## FULL_RECT 自己就会铺满 holder, 不要再设 size。
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	var tx0 := tx
	btn.mouse_entered.connect(func():
		var tw := holder.create_tween().set_parallel()
		tw.tween_property(glow, "color:a", 0.10, UIPalette.T_TAP)
		tw.tween_property(dia, "modulate:a", 1.0, UIPalette.T_TAP)
		tw.tween_property(lb, "position:x", tx0 + 6.0, UIPalette.T_TAP))
	btn.mouse_exited.connect(func():
		var tw := holder.create_tween().set_parallel()
		tw.tween_property(glow, "color:a", 0.0, UIPalette.T_TAP)
		tw.tween_property(dia, "modulate:a", 0.0, UIPalette.T_TAP)
		tw.tween_property(lb, "position:x", tx0, UIPalette.T_TAP))
	btn.pressed.connect(func(): cb.call())
	return holder


## 一块【定好位、左对齐】的描边文字。
## ★必须先把锚点掰回 TOP_LEFT 再设 size/position —— `_make_stroked_label` 里是 PRESET_FULL_RECT,
##   不掰的话下一帧布局会按父容器把 size 冲掉, 文字被画到别的地方去
##   (版本号 2026-08-01 就是这么跑到屏幕外 x≈2544 的, 见 _version_stamp 的注释)。
func _place_stroked(text: String, size: int, fill: Color, pos: Vector2, box: Vector2) -> Control:
	var c := _make_stroked_label(text, size, fill, Color(0, 0, 0, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.size = box
	c.custom_minimum_size = box
	c.position = pos
	return c


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
func _frame_button(label: String, cb: Callable, disabled: bool, size: Vector2, font_size: int = 22, icon_path: String = "", locked: bool = false) -> Control:
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
	var lbl := _make_stroked_label(label, font_size, fill, Color("#ffe4a0"))
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
	# ── 右上一排: [教程][设置] 方形磁贴 + 龟币框 (右边缘贴墙) ──
	## A5: two currency chips side by side (gold + gems treatment, user 2026-09-17).
	##   right = 龟币 (main-site currency), left = 深海币 (the in-run currency, moved out of
	##   the season panel below - it used to be a text row there, a different style entirely).
	var coin := _coin_frame()                                  # 龟币: value<0 => GameState.coins
	coin.position = Vector2(W - WALL - 152, 30)
	content_root.add_child(coin)
	_slide_in(coin, 0)
	var dsea := _coin_frame(int(GameState.meta_deepsea_coins),
		"res://assets/sprites/menu/ic-deepsea.png", Color(0, 0, 0, -1.0))   # a<0 = keep original colours
	dsea.position = Vector2(W - WALL - 152 - 12 - 152, 30)
	content_root.add_child(dsea)
	_slide_in(dsea, 0)
	# 磁贴 62 → 82: 62px 在手机上只有 34pt, 低于 iOS HIG 的 44pt(=本项目 81 视口像素, 见 tests/_probe_ui_layout.gd)。
	# 82 同时更贴近旁边 85 高的龟币框, 三者读起来才是一排。
	var usz := 82.0
	var uy := 30.0 + (85.0 - usz) / 2.0                       # 与龟币框竖直居中对齐
	var set_x := float(W - WALL - 152 - 12 - 152) - 14.0 - usz   # A5: 让开第二个货币芯片
	var help_x := set_x - 10.0 - usz
	var set_tile := _tile("", "⚙", func(): _go("Settings"), Vector2(set_x, uy), "", usz)
	content_root.add_child(set_tile)
	_slide_in(set_tile, 1)
	var help_tile := _tile("ui/help-button", "❓", func(): _on_tutorial(), Vector2(help_x, uy), "", usz)
	content_root.add_child(help_tile)
	_slide_in(help_tile, 2)
	_status_row(now)       # 赛季状态压成一行(原来是 560×398 的表格卡)
	_version_stamp()


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
	l.size = Vector2(200, 22)
	l.custom_minimum_size = Vector2(200, 22)
	l.position = Vector2(W - WALL - 200, H - WALL - 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(l)


## 龟币框 (frame-coin + 绿龟币图标染色 + 数字) — 抽出复用; 返回未定位的 Control, 调用方定位/入场
## A5(2026-09-17, user): 龟币 is the MAIN-SITE currency and must stay visible, but the two
## currencies used to sit in two totally different places/styles - 龟币 in a frame up top,
## 深海币 as a text row inside the season panel. User asked for the usual game treatment:
## gold and gems side by side. So this chip is parameterised and drawn twice.
## value < 0 => GameState.coins (龟币). icon_path "" => the old green coin.png.
func _coin_frame(value: int = -1, icon_path: String = "", tint: Color = Color(0.122, 0.561, 0.247)) -> Control:
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(152, 85); coin.size = Vector2(152, 85)
	if ResourceLoader.exists("res://assets/sprites/menu/frame-coin.png"):
		var cf := TextureRect.new(); cf.texture = load("res://assets/sprites/menu/frame-coin.png")
		cf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; cf.stretch_mode = TextureRect.STRETCH_SCALE
		cf.size = Vector2(152, 85); coin.add_child(cf)
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
		ci.size = Vector2(36, 36); ci.position = Vector2(76 - 39.5 - 18, 42 - 18); coin.add_child(ci)
	var cl := Label.new(); cl.text = "%d" % (GameState.coins if value < 0 else value)
	cl.position = Vector2(79, 0); cl.size = Vector2(73, 85)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 22); cl.add_theme_color_override("font_color", Color("#2c4a1e")); coin.add_child(cl)
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
		return "决赛日 · 去看对阵图"
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
##  ★★★状态行是**两行**(2026-09-28) —— 一行装不下, 而且是量出来的不是看出来的
## ══════════════════════════════════════════════════════════════════════
## 周六那句实测 `第 1 大轮 · Lv 1   闯关赛 2-1 · 再赢 2 场晋级 / 再输 2 场出局`
## = **ink 485px**, 而框只有 `LEFT_W - 8` = **374px** ⇒ **顶穿控件 111px**
## (真渲染量到的 Label rect 是 x 51..538, 而 holder 右沿在 430)。
## 从 2026-09-22 周六那条读数上线时就在, 一直没红 —— 因为**它一周只渲染一天**,
## 而 `verify_ui_consistency` / `verify_mainmenu_layout` 扫的都是「今天」那一屏。
##
## ★为什么不削词: 量过 16 个更短的写法, 装得进 374 的**都要削掉「再赢/再输」的后果**
##   (最短可读的 407 仍然超; 降到 371 就只剩「再赢 2 / 再输 2」, 丢了晋级/出局这件事)。
##   那句话的信息量是拍板过的 —— 「再输两场就出局」正是闯关赛每一场的分量。
## ★为什么不加宽左栏: `LEFT_W` 同时定着四个入口、赛程条的对齐带与右栏的镜像,
##   动它就是动整屏版式。两行只动这一行自己。
##
## ★★★竖向一分都涨不了 —— 剖面(实测, `tests/_probe_satrow.gd`):
##     LOGO 底沿  205.5      ← 上面只剩 4.5px
##     状态行     210..291   (= STATUS_Y + ROW_H)
##     四个入口   299..623
##     赛程条     周日被「看对阵图」按钮撑到 95 高 ⇒ 顶沿 **624**
##   ⇒ 栈底与条顶只差 **1px**: `MENU_Y` 往下挪一格整屏就溢出(那条 2026-09-27 刚修过)。
##   ⇒ 三段文字必须塞进原来的 81px: 27(18号) + 25(17号) + 25(17号) = 77, 上下各留 2。
##
## ⚠ `Control` 会把自己夹到 `get_combined_minimum_size()` ⇒ 给 Label 设 box **只是下限**:
##   字比 box 宽时它照样长出去(顶穿就是这么来的, 一个错都不报)。
##   所以门禁量的是**真实 rect 包不包得住 holder**, 不是"我设了多大的 box"。
##   (同一个坑 2026-09-28 在训龟大师那屏也栽过: 以为是"名字换行", 真因是内容最小高 102 > 94。)
##
## 三段各说一件事:
##   L1 身份 `第 N 大轮 · Lv X`                 ← 七天一个字不变
##   L2 今天 `♥ a/8   本周 n/24` | 闯关赛… | 决赛日…  ← `_phase_status_line()` 分派
##   L3 战绩 `[纹章] 战绩  x 胜 y 负`
## ★★★命与本周场次进 **L2 而不是 L1** —— 它们是「今天在动的数」, 而周六周日**都不动**
##   (`phase_uses_ranked_quota(GAUNTLET/FINALS)=false`; `finals_*` 一个字都不碰 `hearts`)。
##   摆在 L1 就得给 L1 加一个"今天是不是积分赛"的分支, 而那个分支一周只走两天 ——
##   本文件刚因为"一周只走一天的代码"栽过两次。⇒ **L1 无条件、七天同字**, 一个分支都不要。
## ★`now` = 本屏那一刻; 0 时才自己问一次(单独被门禁/实拍调用时)。
func _status_row(now: int = 0) -> void:
	## L1 身份 —— 七天不变, 没有任何分支。
	var id_txt := "第 %d 大轮 · Lv %d" % [
		int(GameState.season_id), int(GameState.season_level)]
	## L2 今天 ——★★走 `_now_ts()`: 不传参的话这一行读的是真实时钟, 于是**一周只有一天**
	##   会被门禁执行到(见 `_phase_status_line` 头注)。
	var today_txt: String = _phase_status_line(now if now > 0 else _now_ts())
	if today_txt == "":
		## 积分赛/休赛那几天: 命与本周场次**就是**今天在动的那两个数。
		## ★满命读常量 —— 原来写死成 `/8`, 而 2026-09-30 满命改成 6 之后
		##   主菜单会显示「♥ 6/8」。实拍才照出来的 —— 我那条 HEARTS_ONE_SOURCE
		##   逐行扫, 而这句的格式串与 `GameState.hearts` **分在两行** ⇒ 它没看见。
		today_txt = "♥ %d/%d   本周 %d/%d" % [
			int(GameState.hearts), int(_P2C.HEARTS_MAX),
			int(GameState.ranked_used), int(_P2C.RANKED_QUOTA)]
	var wN: int = GameState.battles_won
	var tN: int = GameState.battles_total
	## ★★空态文案 2026-09-27 改: 「暂无战绩」是后台/电商的那句「暂无数据」——
	##   同一个模子还有"暂无记录/暂无内容"。游戏里没人这么说话。
	##   改成一句**有人味、且在催你去打**的话; 它旁边就是「开始战斗」那块大木牌。
	var rec := "%d 胜 %d 负" % [wN, maxi(0, tN - wN)] if tN > 0 else "还没上过场"
	## ★E-B5 头衔: 只挂**最高一档**。这一行宽 382px, 完整串会溢出 ——
	##   而玩家要一眼看到的本来就是最硬的那个, 完整列表在战绩屏。
	##   ★没有头衔时**一个字都不加**(不写「暂无头衔」): 那一行已经有"暂无战绩"了,
	##     再来一句"暂无"就是拿空状态占屏幕。
	var top_title: String = _P2C.title_top(GameState.titles)
	if top_title != "":
		rec = "%s · 🏅 %s" % [rec, top_title]

	var holder := Control.new()
	holder.position = Vector2(LEFT_X, STATUS_Y)
	holder.custom_minimum_size = Vector2(LEFT_W, ROW_H)
	holder.size = Vector2(LEFT_W, ROW_H)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.85, 0.24, 0.0)
	glow.size = Vector2(LEFT_W, ROW_H)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	## ★两行装进一个**具名容器**: 门禁按 `STATUS_TWO_LINE` 抓它, 再逐个 Label 量
	##   "rect 有没有长出 holder"。容器自己不吃鼠标, 整块的点击仍由下面那个 Button 接。
	var two := Control.new()
	two.name = STATUS_TWO_LINE
	two.size = Vector2(LEFT_W, ROW_H)
	two.custom_minimum_size = Vector2(LEFT_W, ROW_H)
	two.mouse_filter = Control.MOUSE_FILTER_IGNORE
	two.add_child(_place_stroked(id_txt, STATUS_L1_FONT, Color("#ffe9a8"),
		Vector2(4, STATUS_L1_Y), Vector2(LEFT_W - 8, 26)))
	two.add_child(_place_stroked(today_txt, STATUS_L2_FONT, Color("#ffe9a8"),
		Vector2(4, STATUS_L2_Y), Vector2(LEFT_W - 8, 25)))
	holder.add_child(two)
	## ★★2026-09-27 去掉行尾那个 › —— 网页的「更多 ›」写法
	##   (用户 2026-09-27:「一点也看不出来游戏的味道, 全是 ai 味和网页味」)。
	##   这一行本来就是可点的整块, 不靠一个箭头告诉人。
	## ★(下面这段是旧注释, 讲的是箭头为什么曾经连进同一行 —— 现在没有箭头了, 留档)
	## ★箭头连进同一行文字 —— 第一版把它钉在行尾(x≈410), 而"暂无战绩"到 x≈190 就结束了,
	##   中间一百多像素空着, 屏幕上就是一个飘在龟身上的孤零零箭头。
	## ★★2026-09-27 把「📜」换成真像素图标 `menu/icon-record.png`(交叉双剑纹章)。
	##   左栏四个入口(背包/商店/图鉴/排行榜)用的全是像素图标, **只有这一行用 emoji** ——
	##   同一栏里两种画法, 那正是"ai 味"最好认的形状。
	## ★不是拿别件素材顶替: 这张图的文件名就叫 `icon-record`, 是**给战绩画的**,
	##   而且全仓 grep 下来一个调用点都没有(画好了没人用), 这里是它的正主。
	## ★图标 24px 与 17 号字同高一档; 文字左沿随之从 4 推到 32。
	var _rec_ic_x := 4.0
	var _rec_tx := 4.0
	if ResourceLoader.exists("res://assets/sprites/menu/icon-record.png"):
		var rec_ic := TextureRect.new()
		rec_ic.texture = load("res://assets/sprites/menu/icon-record.png")
		rec_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rec_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rec_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 像素风: 缩小也不许插值糊掉
		rec_ic.size = Vector2(24, 24)
		rec_ic.position = Vector2(_rec_ic_x, STATUS_L3_Y + 1.0)
		rec_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rec_ic)
		_rec_tx = _rec_ic_x + 28.0
	## ★颜色从冷灰 #cfd8e4 改成暖羊皮纸 #ddcaa4: 冷灰细字 = 网页的次级说明句,
	##   而这一屏的语言是木头 + 金边。同一行里"战绩"两个字仍在(门禁 ⑦ 按它找入口)。
	holder.add_child(_place_stroked("战绩  %s" % rec, STATUS_L2_FONT, Color("#ddcaa4"),
		Vector2(_rec_tx, STATUS_L3_Y), Vector2(LEFT_W - _rec_tx - 8.0, 25)))
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(btn)
	btn.mouse_entered.connect(func(): holder.create_tween().tween_property(glow, "color:a", 0.09, UIPalette.T_TAP))
	btn.mouse_exited.connect(func(): holder.create_tween().tween_property(glow, "color:a", 0.0, UIPalette.T_TAP))
	btn.pressed.connect(func(): _go("Record"))
	content_root.add_child(holder)
	_slide_in_left(holder, 0)


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


func _tile(icon_key: String, label: String, cb: Callable, pos: Vector2, sub_value: String = "", sz: float = 82.0) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.size = Vector2(sz, sz)
	var btn := TextureButton.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.ignore_texture_size = true; btn.stretch_mode = TextureButton.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/menu/frame-square.png"):
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
		var isz := roundi(sz * (0.58 if has_sub else 0.72))   # 无sub图标(教程❓)填满些 (原0.62偏小)
		var iy_off := -sz * 0.10 if has_sub else 0.0          # 无sub → 正居中(原-6上偏→与旁边⚙不齐·歪·用户2026-07-18)
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
		tl.add_theme_font_size_override("font_size", roundi(sz * 0.44)); tl.mouse_filter = Control.MOUSE_FILTER_IGNORE; holder.add_child(tl)
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
const _WD_CN := ["一", "二", "三", "四", "五", "六", "日"]

## 赛程条的外框。★留引用是为了服务状态变化时能把它换掉(见 `_sb_poll`)。
var _week_box: Control = null
## 建这条赛程条时的服务状态。★存下来才知道"变没变" —— 只看当前值没法判断要不要重建。
var _sb_state_shown: String = ""


## D-1: 服务状态变了就重建赛程条(维护态要盖掉收盘倒计时)。
## ★判据是**状态变了**而不是"每秒都重建" —— 后者会让主菜单每秒扔一堆节点。
func _sb_poll() -> void:
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
	return "%s|%s|%s" % [ph, kind, _left_text(left) if left >= 0 else ""]


## 重建赛程条。★抽出来是因为实拍要在换过时钟之后再建一次 ——
##   就地再抄一遍那两行就是「手抄的副本必然落后」。
func rebuild_week_strip() -> void:
	if is_instance_valid(_week_box):
		_week_box.queue_free()
	_week_strip()


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
	box.position = Vector2(STRIP_X, STRIP_Y)
	box.custom_minimum_size = Vector2(STRIP_W, STRIP_H)
	box.size = Vector2(STRIP_W, STRIP_H)
	## ★**只有被撑高时才往上挪**, 常规日一个像素都不动(STRIP_Y = 636 是拍过板的版式)。
	##   周日那一格是 81 高的按钮(触控下限), 把条子撑到 95 ⇒ 顶沿必须落在一个窄窗口里:
	##     · 底边 ≤ 720(不出屏) 且 底沿距屏底 ≤ 24 ⇒ 顶沿 ∈ [601, 625]
	##     · 顶沿 ≥ 左栏栈底 - 2 = 621(不压住入口)
	##   ⇒ 取 `STRIP_BOTTOM - 高`, `STRIP_BOTTOM = 719` 时周日顶沿 = 624, 正在窗口中间。
	##   `resized` 而不是建的时候算 —— 高度由子控件决定, 那会儿还不知道。
	box.resized.connect(func() -> void:
		if is_instance_valid(box):
			box.position.y = minf(STRIP_Y, STRIP_BOTTOM - box.size.y))
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
	var frame: StyleBox = UISkin.nine("ui/panel-wide-flat.png", 8, sb)
	frame.content_margin_left = 12; frame.content_margin_right = 12
	frame.content_margin_top = 7; frame.content_margin_bottom = 7
	box.add_theme_stylebox_override("panel", frame)
	content_root.add_child(box)
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
	_slide_in(box, 6)


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
		skin = UISkin.nine("ui/panel-wide-on.png", 8, cs)
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
	d.add_theme_font_size_override("font_size", 15)
	d.add_theme_color_override("font_color", Color("#ffd93d") if is_today else Color("#c6d2e0"))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var n := Label.new()
	## ★今天那格在名字后缀一个「今」——横条的格子只有 92px 宽, 光靠金边在缩略/小屏上读不出来;
	##   顺带让门禁能量到"恰好一天是今天"(竖排那版有「今天」标签, 改横条时漏掉了)。
	n.text = (str(_P2C.PHASE_LABEL.get(ph, ph)) + " 今") if is_today else str(_P2C.PHASE_LABEL.get(ph, ph))
	n.add_theme_font_size_override("font_size", 14)
	n.add_theme_color_override("font_color", Color("#ffe9a8") if is_today else Color("#9fb0c4"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	if wd < today:
		cell.modulate.a = 0.42
	return cell


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
			sub = "这天按积分赛的规矩打"
		return _close_block_labels(head, sub)
	if kind == BK_NO_CLOSE:
		if ph == _P2C.PHASE_FINALS:
			head = "决赛日"
			sub = "本地 %s 开打" % _local_hhmm(_utc_today_at(now, int(_P2C.FINALS_START_HOUR_UTC)))
		else:
			head = "休赛日"
			sub = "周二开赛 · 本日维护"
	elif kind == BK_CLOSED_TODAY:
		head = "今日已收盘"
		var _tmr: int = now + 86400
		var _tph: String = _P2C.phase_at_utc(_tmr)
		if _tph == _P2C.PHASE_FINALS:
			sub = "明天决赛日 · 本地 %s 开打" % _local_hhmm(_utc_today_at(_tmr, int(_P2C.FINALS_START_HOUR_UTC)))
		else:
			sub = "明天%s" % str(_P2C.PHASE_LABEL.get(_tph, ""))
	elif kind == BK_LOCKED:
		head = "已封盘"
		sub = "收盘前 %d 分钟起不开新局" % int(_P2C.CLOSE_LOCKOUT_SEC / 60)
	else:
		head = "距收盘 %s" % _left_text(left)
		sub = "本地 %s" % _local_stamp(now + left)
	return _close_block_labels(head, sub)


## 周日决赛日那扇门通到哪。★具名常量 —— 门禁拿它去验"目标场景真的存在",
##   写死成字符串的话门禁就只能自己再抄一遍(抄一次永远落后一次)。
const BRACKET_SCENE := "BracketMap"


## 周日决赛日的门。★一整块都能按 —— 那一格本来就只有两行字, 做成"字旁边一个小按钮"
##   反而更难点中(触控下限 81px 是全项目同一条线)。
func _finals_entry() -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 81)
	## ★★2026-09-27 去掉行尾的「→」。它跟上面状态行那个「›」是同一族:
	##   网页的「更多 →」写法 —— 用一个箭头告诉人"这里可以点"。
	##   这一整块本来就是一个 150×81 的按钮(触控下限), 不需要箭头来交代。
	b.text = "决赛日\n看对阵图"
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("#4ff0d0"))
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
	var fnine: StyleBox = UISkin.nine("ui/panel-wide.png", 8, fsb)
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
	b.pressed.connect(_open_bracket_map)
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
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(a)
	var b := Label.new(); b.text = sub
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color("#9fb0c4"))
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
	return "周%s %02d:%02d 收盘" % [_WD_CN[wi - 1], int(d.get("hour", 0)), int(d.get("minute", 0))]


func _local_hhmm(utc_ts: int) -> String:
	var d := _local_dict(utc_ts)
	return "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]


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
	if GameState.is_eliminated():
		return _msg_eliminated()
	if GameState.ranked_quota_full(ts):
		return _msg_quota_full()
	if int(GameState.season_total_battles) <= 0:
		return "🔒 本大轮打完第一场才开店"
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
		return "✅ 已晋级决赛日 · 闯关赛到此为止(%s) · 明天周日来打决赛日" % _P2C.gauntlet_label(
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
func _toast(msg: String) -> void:
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vw := get_viewport_rect().size.x
	t.position = Vector2(vw / 2.0 - 320.0, 120.0); t.size = Vector2(640, 40)
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
