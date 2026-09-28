extends Control
## BracketMapScene — 周日决赛日的桶地图 (E-B2, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这一屏是什么
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-09-23：「周日有单独的桶界面，是一个大的可拖动地图」，形态选了
## **抽象对阵图（清爽）**那版。版式比例是从 Worlds 2024 官方对阵图上**量**来的，
## 逐条写在 `bracket_layout.gd` 里（三列 / 32px 与 94px 的 3 倍间隔 / 横条节点）。
##
## ★★**每一场对局自己就是按钮** —— 所以「重放/开播按钮放哪」这个问题不存在，
##   不用在菜单上另辟一个入口。
##
## ══════════════════════════════════════════════════════════════════════
##  四条硬规矩
## ══════════════════════════════════════════════════════════════════════
## ★① **开图自动居中到自己那一场**。32 个节点里找自己是这屏最容易失败的地方；
##     角落钉一个「回到我」，拖多远都不跑。
## ★② **不剧透**：当前轮**根本不下发结果**，不是"拿到了但不显示"。
##     后者一个渲染 bug 就漏，而且没人会发现漏了 —— 让客户端**没有**那个数据，
##     是唯一守得住的做法（同族：`_settle_season` 的两条口径各自成段）。
## ★③ **拖不拖由规模决定**，不是一律能拖：`needs_pan()` 按 1:1 画放不放得下来判。
##     Worlds 8 队一屏放得下所以不需要拖；我们 4 人桶比它还小，更不需要。
## ★④ **用词写「开播」**：写「直播」是假话（它就是回放），写「回放」会泄露"已经打完了"。
##
## ══════════════════════════════════════════════════════════════════════
##  数据长什么样（`set_bucket()` 的入参）
## ══════════════════════════════════════════════════════════════════════
##   {
##     "size":  4,                       # 这个桶里几个人
##     "round": 2,                       # 当前进行到第几轮(1 起)
##     "me":    1,                       # 我的种子号(-1 = 我不在这个桶, 纯观众)
##     "names": ["小龟","石头龟", ...],    # 按种子序
##     "done":  {"1-0": 0, "1-1": 1},    # 【已翻面】的场次 → 赢家在这一场的哪一侧(0/1)
##   }
## ⚠ `done` 里**只有已经翻面的轮次**。当前轮不在里面 —— 见 ★②。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★周日是【两场】不是一场（用户 2026-09-23 指出，我原来糊成了一张图）
## ══════════════════════════════════════════════════════════════════════
##   · **上午·分桶赛**：你自己那个桶，5 轮 → 产生**桶冠军**
##   · **晚上·冠军签表**：20:00 开赛，**全部桶冠军**进一张新图，单败打到决赛
##
## 两者对同一个玩家的意义完全不同：**上午你是选手，晚上你多半是观众**
## （只有桶冠军进得去）。所以：
##   ★顶上两个 Tab，随时能切 —— 桶里输了就想看别人的，晚上也想回看自己桶里的路；
##   ★**默认看哪张跟着时刻走**（20:00 之后默认冠军赛），不让人每次自己找；
##   ★签表**上午还没形成** ⇒ 那时候切过去要说人话（等各桶决出冠军 + 倒计时），
##     不是画一张空图。

const TopBar := preload("res://scripts/util/top_bar.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")

const BG := Color("#0a0e18")           # 黑底(Worlds 那张也是几乎纯黑)
const LINE := Color("#8fa3bd")         # 连接线: 细、冷、低调
const TXT := Color("#e8f0f6")
const ACCENT := Color("#4ff0d0")       # ★全屏**唯一**的强调色(Worlds 用的是青色)
const DIM := Color("#5a6a80")          # 轮空/空位
const MINE := Color("#ffd93d")         # 只有"我"用金色 —— 找自己是这屏的头等大事

## ══════════════════════════════════════════════════════════════════════
##  ★★2026-09-27 改版: 用户「一点也看不出来游戏的味道, 全是 ai 味和网页味」
## ══════════════════════════════════════════════════════════════════════
## 这一屏的"网页味"是**两个具体东西**, 不是气质问题:
##   ① 圆角矩形卡片(已改直角) ② **一根粗细颜色都一样的 2px 直角细线**当连接线
##      —— 那就是 CSS 流程图的长相; 赛事对阵图的连线是有**轻重**的:
##      已决出的那条粗而亮、还没决出的细而暗, 而且末端**带箭头**(谁走向哪一场)。
## 像素味靠的是: 直角 + **不羽化的硬投影** + 粗细两档的实心块 + 明确描边,
## 而**不是**再生成一张贴图 —— 节点是 104~268 宽的横条, 九宫格框的边带会把名字挤掉
## (UISkin.MIN_FRAME_PX 那条教训的同族), 参考图(Worlds 官方图)本来也是直角实心条。
const SHADOW := Color("#04070e")       # 硬投影 —— 像素 UI 的招牌(不是模糊 box-shadow)
const LINE_DIM := Color("#31405a")     # 连线: 还没决出
const DASH := Color("#46566f")         # 虚线描边(「还没到」的空槽)
const PLATE_WIN := Color(0.31, 0.94, 0.82, 0.13)   # 胜者那一行的底板
const PLATE_LOSE := Color(0.0, 0.0, 0.0, 0.42)     # 败者那一行压暗
const LINE_W_LIT := 4.0                # 连线: 已决出 = 粗
const LINE_W_DIM := 2.0                # 连线: 还没决出 = 细
## 节点右侧那条槽 —— 「你」/「冠」小签与开打标住这里; 名字条**不许伸进来**(会撞上)。
const GUTTER := 30.0

var _bucket: Dictionary = {}           # 上午: 我自己那个桶
var _finals: Dictionary = {}           # 晚上: 桶冠军的签表(上午是空的)
var _view: String = _L.VIEW_BUCKET     # 现在看的是哪一张
var _now_override := 0                 # ★只给门禁喂已知时刻; 产品不传
var _tabs: HBoxContainer = null
var _empty_lb: Label = null
## 空态那句话的**框**。★没桶的人整个周日看到的就只有这一屏, 一句裸字飘在黑底上
##   正是"网页味"最重的地方 ⇒ 套共享皮的金属框(UISkin.nine, 不手写圆角矩形)。
var _empty_box: Panel = null
## 空态那一枚像素图标(跟着 `_empty_kind()` 换)。★由来见 `_empty_icon_path()`。
var _empty_icon: TextureRect = null
var _bg: ColorRect = null
var _canvas: Control = null            # 拖动的是它, 不是整屏
var _scale := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _can_pan := false
var _top_bar = null
var _home_btn: Button = null
## 点了哪一场 —— 外部接重放用。留成信号, 本屏不管怎么播。
signal match_opened(r: int, m: int)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	## ★必须**真盖住**全局 `PersistentBg`(layer -100 的深绿瓷砖) —— 那一层是给
	##   场景切换空隙用的, 各屏都得自己铺不透明底。只设 anchors 拿不到尺寸(实拍抓到:
	##   整屏透出绿瓷砖), ⇒ 显式给 size, 并在 `_rebuild()` 里跟着视口更新。
	_bg = ColorRect.new()
	_bg.color = BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.size = get_viewport().get_visible_rect().size
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	var sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		"title": "周日 · 决赛日",
		"palette": TopBar.DEEP,
		"safe": sm,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
	})

	## ★两个 Tab: 上午看自己那个桶, 晚上看桶冠军的签表。
	##   钉在顶栏下方, **不跟着画布走** —— 切图是全屏动作, 不该拖没了。
	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(24, 96)
	_tabs.add_theme_constant_override("separation", 10)
	add_child(_tabs)
	for pair in [[_L.VIEW_BUCKET, "我这一组"], [_L.VIEW_FINALS, "冠军赛"]]:
		var b := Button.new()
		b.text = str(pair[1])
		b.custom_minimum_size = Vector2(132, 81)    # 触控下限 81px(=44pt)
		var v: String = str(pair[0])
		b.pressed.connect(func(): set_view(v))
		## ★页签同上 —— 换皮走共享层, 不在这里手写 StyleBox。
		UISkin.button(b)
		## ★★选中态不能只靠字色(那是网页 tab 的做法): 底下压一条 4px 实心杠,
		##   **形态**上就分得出现在看的是哪一张。颜色在 `_sync_tabs()` 里跟着切。
		##   名字定死成 `Underline` —— `_sync_tabs` 按名字找它, 不靠子节点下标。
		var ul := ColorRect.new()
		ul.name = "Underline"
		ul.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ul.position = Vector2(6.0, 81.0 - 6.0)
		ul.size = Vector2(132.0 - 12.0, 4.0)
		b.add_child(ul)
		_tabs.add_child(b)

	## 签表还没形成时说人话的那一行(不是画一张空图)
	## ★先建框、后建字 —— 加入顺序就是绘制顺序, 反了字会被框盖住。
	_empty_box = Panel.new()
	_empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ebfb := StyleBoxFlat.new()
	ebfb.bg_color = Color("#121a27")
	ebfb.border_color = Color("#2c3950")
	ebfb.set_border_width_all(2)
	ebfb.set_corner_radius_all(0)
	_empty_box.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, ebfb))
	_empty_box.visible = false
	add_child(_empty_box)
	## ★★这一屏对**没晋级的人**就是整个周日的全部内容 —— 一句裸字孤零零躺在框里
	##   正是"网页味"最重的形状。⇒ 左边压一枚像素图标, 32px 素材按**整 2 倍**放到 64
	##   (最近邻整数倍才不糊; 1.5 倍会掉像素 —— `pk-vs-emblem` 那条教训的同族)。
	##   图标**跟着空态的种类换** ⇒ 它也是"这是哪一种情况"的一维形态信息。
	_empty_icon = TextureRect.new()
	_empty_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_icon.visible = false
	add_child(_empty_icon)
	_empty_lb = Label.new()
	_empty_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_lb.add_theme_font_size_override("font_size", 19)
	_empty_lb.add_theme_color_override("font_color", TXT)
	_empty_lb.visible = false
	add_child(_empty_lb)

	## ★「回到我」钉在右下角, **不跟着画布走** —— 拖多远它都在。
	##   触控下限 81px(= 44pt), 与全项目同一条线。
	_home_btn = Button.new()
	_home_btn.text = "回到我"
	_home_btn.custom_minimum_size = Vector2(140, 81)
	_home_btn.pressed.connect(func(): _center_on_me())
	## ★2026-09-27 换皮: 原来是裸 `Button.new()` = Godot 默认皮(圆角灰板)。
	##   周日对阵图**整天都在看**, 而这一屏至今一条 UI 判据都没量过
	##   (`verify_ui_consistency` 原来只有 7 屏, 没有它)。
	UISkin.button(_home_btn)
	add_child(_home_btn)

	if not _bucket.is_empty() or not _finals.is_empty():
		_injected = true
		_rebuild()
	else:
		## ★没人喂 ⇒ 这是玩家自己从主菜单点进来的, 自己去服务端取
		_start_feed()


## 只喂一张（老调用点/门禁用）。
func set_bucket(d: Dictionary) -> void:
	set_data(d, {})


## 喂两张。★`finals` 为空 = 签表还没形成（上午就是这样），不是"出错了"。
func set_data(bucket: Dictionary, finals: Dictionary, now: int = 0) -> void:
	_injected = true
	if _poll != null:
		_poll.stop()          # ★有人喂了就别再联网覆盖
	_bucket = bucket.duplicate(true)
	_finals = finals.duplicate(true)
	_now_override = now
	_view = _L.default_view(_clock())
	## ★默认那张要是还没形成, 就退回另一张 —— 别让人开屏就看到一张空图
	if _view == _L.VIEW_FINALS and int(_finals.get("size", 0)) <= 1:
		_view = _L.VIEW_BUCKET
	_record_progress()
	if is_inside_tree():
		_rebuild()


## ★★★把「我在决赛日走到第几轮 / 有没有夺冠」记进存档, 并对一次头衔账。
##   方案书 `docs/plans/20260926-冠军四强头衔发放.md`。
##
## ★为什么在这里: 这是**权威结果到手**的那一刻。冠军/四强不能从本地
##   `finals_settle(won)` 数出来 —— 周日是双方各自在本地打对方的快照, 两边都可能
##   算出自己赢(服务端 `finals_report` 用 `on conflict do nothing`, 先报的算),
##   拿本地结果发头衔 = 一个桶里出两个冠军。权威只有 feed 里的 `done`。
##
## ★依据取 `_bucket`(**我那个桶**那一张), 不是 `cur()` —— `cur()` 跟着页签变,
##   切到「冠军赛」那张就会拿另一张图的 `done` 去算我的名次。
## ★两条路都调它: 联网那条(`_on_poll` 指纹变了)与喂数据那条(`set_data`)。
##   只挂一条的话, 门禁验的就不是玩家真走的那条(memory fb-verify-must-run-the-real-path)。
func _record_progress() -> void:
	if GameState == null:
		return
	var n := int(_bucket.get("size", 0))
	var me := int(_bucket.get("me", -1))
	if n <= 1 or me < 0:
		return                        # 没有桶 / 我不在桶里(纯观众) ⇒ 一个字都不记
	var pr: Dictionary = _B.my_progress(me, n, _bucket.get("done", {}) as Dictionary)
	var changed: bool = GameState.record_finals_progress(
		int(pr.get("deepest", 0)), int(pr.get("total", 0)), bool(pr.get("champion", false)))
	if _reveal_sealed():
		changed = true
	## ★头衔在 `sync_titles()` 里发(与满配额/进决赛日同一个入口) —— 这里不自己发。
	##   `sync_titles` 自带按 `{id, week}` 去重, 每次 feed 都调一遍是幂等的。
	var got: int = GameState.sync_titles()
	if changed or got > 0:
		GameState.save()


## ══════════════════════════════════════════════════════════════════════
##  ★★★揭晓被封存的那一场(2026-09-27) —— 原稿 §五.5「统一至开播时刻全服解锁」
## ══════════════════════════════════════════════════════════════════════
## 战斗结束时**只结算了与胜负无关的那部分**(场次/经验/轮次币, 原稿逐字「赢家输家一样多」),
## 吃胜负的那几项(糖罐 / season_wins / season_eggs_killed)封存着等这里。
##
## ★为什么权威在这儿: `finals_view` 下发的 `done`(哪一场哪一侧赢)**一个桶里只有一个值**,
##   而它只返回**已翻面的轮次** ⇒ 拿得到就说明那一轮已经推进、结果已解锁。
##   周日是双方各自在本机打对方的快照(两场不同的战斗, 都可能算出自己赢), 本机结果不是权威。
##
## ★**幂等**: 揭晓完把 `finals_pending_reveal` 清掉 ⇒ 同一场 feed 来多少次都只补一次。
## ★只看 `_bucket`(我那个桶)那一张, 不看 `cur()` —— `cur()` 跟着页签变,
##   切到「冠军赛」那张会拿另一张图的 `done` 去判我的场。
## 返回值: 真的揭晓了吗(调用方据此决定要不要存档)。
func _reveal_sealed() -> bool:
	if GameState == null:
		return false
	var p = GameState.get("finals_pending_reveal")
	if not (p is Dictionary) or (p as Dictionary).is_empty():
		return false
	var pd: Dictionary = p
	var r := int(pd.get("round", -1))
	var m := int(pd.get("match", -1))
	if r < 1 or m < 0:
		GameState.finals_pending_reveal = {}    # 坏坐标: 清掉, 别永远挂着
		return true
	var n := int(_bucket.get("size", 0))
	var me := int(_bucket.get("me", -1))
	## ★`me < 0` 这一半是**防御性, 不承重**(2026-09-27 反向验证查实): 唯一的调用方
	##   `_record_progress()` 第一行就挡了 `me < 0`, 所以拿掉它一条断言都不红。
	##   留着是把「纯观众没有待揭晓的场」写在明面上。
	##   ⚠ 别因为它在这儿就以为「纯观众」有判据在守 —— 守它的是
	##   `verify_bracket_map` ⑧e 那条「纯观众 ⇒ 胜场不动、pending 也不清」, 它量的是**结果**,
	##   所以无论哪一层挡住的都算。(memory fb-mutation-not-reddening-can-mean-dead-code)
	## ★`n <= 1` 那一半**是承重的**: feed 还没到时 `_bucket` 是空的。
	if n <= 1 or me < 0:
		return false                            # 还没桶 / 我不在桶里 ⇒ 等下一次 feed
	var w = (_bucket.get("done", {}) as Dictionary).get("%d-%d" % [r, m], -1)
	if int(w) < 0:
		return false                            # 那一轮还没翻面 —— 这正是「封存」本身
	var side := _B.my_side_in(me, r, m, n, _bucket.get("done", {}) as Dictionary)
	if side < 0:
		GameState.finals_pending_reveal = {}    # 我根本不在那一场里(坐标错了) ⇒ 清掉
		return true
	GameState.finals_reveal(int(w) == side)
	GameState.finals_pending_reveal = {}
	return true


func _clock() -> int:
	return _now_override if _now_override > 0 else int(Time.get_unix_time_from_system())


## 现在这一张的数据。★全屏所有判据都从这里取 —— 切 Tab 只换它, 其余一行不动。
func cur() -> Dictionary:
	return _finals if _view == _L.VIEW_FINALS else _bucket


func set_view(v: String) -> void:
	if v == _view:
		return
	_view = v
	_rebuild()


## ─────────────────────────────────────────────────────────────
## 一场对局在**我这一侧**看起来是什么状态。
## ★这是全屏的判据中心 —— 节点画成什么样、点不点得动，全看它。
## ─────────────────────────────────────────────────────────────
const ST_BYE := "bye"          # 轮空(对手那个坑是空的)
const ST_LOCKED := "locked"    # 还轮不到(上一轮没打完)
const ST_LIVE := "live"        # ★当前轮: 可以点开看, 但**不显示结果**
const ST_DONE := "done"        # 已翻面: 显示胜者
func match_state(r: int, m: int) -> String:
	var n := int(cur().get("size", 0))
	var cur_r := int(cur().get("round", 1))
	var key := "%d-%d" % [r, m]
	if (cur().get("done", {}) as Dictionary).has(key):
		return ST_DONE
	if r == 1:
		var sa: int = m * 2
		var sb: int = m * 2 + 1
		if _B.is_bye_slot(sa, n) or _B.is_bye_slot(sb, n):
			return ST_BYE
	if r > cur_r:
		return ST_LOCKED
	return ST_LIVE


## ★★★重放做出来了没有。**没有** —— `matches` 表建好了、索引和清理任务都有,
##   但客户端**一行都没往里写过**(全仓 `rest/v1/matches` 零命中)。
## ⇒ 拿一个命名常量把「没上线」变成可读状态, 而不是让 `can_open` 悄悄放行
##   (memory fb-branch-to-an-unbuilt-mode-is-a-backdoor: 分流给没做的模式 = 开后门)。
##   重放真上线那天改这一格, 并把 `verify_bracket_map` ③ 那条判据一起翻回来。
const REPLAY_LIVE := false

## ★★跨桶「冠军赛」做出来了没有。**没有**(F 阶段)—— 服务端没有桶冠军汇总,
##   客户端联网那条路只写 `_bucket`。上线那天改这一格。
const CROSS_BUCKET_LIVE := false

## 这一场能不能点开看。★轮空与未开打**不可点** —— 点了没东西放，
##   而"点了没反应"比"按钮是灰的"糟得多。
##
## ★★★2026-09-26 收紧: 原来 `ST_LIVE or ST_DONE` 都放行, 而唯一的监听者
##   `_on_match_opened` 第一行就是 `if not should_fetch_opponent(r, m): return` ——
##   于是这几种情况**点了一个字都不变**, 而屏幕上有个覆盖整格、tooltip 写着「开播」的按钮:
##     · 已翻面的场次(想看重放)—— 而重放数据一行都没有
##     · 不是我的那一场(想观战)—— 观战没做
##   3 人桶里第一轮就输掉的人, 整个周日唯一能点的就是决赛那一格, 点了什么都不会发生。
##   **这正是本函数注释自己写的那句**「点了没反应比按钮是灰的糟得多」。
## ⇒ 判据改成「点下去真有事发生」= `should_fetch_opponent`(它同时管住了
##   「当前轮」「是我的场」「问得出对手」三条), 外加重放那条**显式的**没上线开关。
func can_open(r: int, m: int) -> bool:
	if REPLAY_LIVE and match_state(r, m) == ST_DONE:
		return true
	return should_fetch_opponent(r, m)


## 这一场是不是**我的** —— 判据是「我是这一场的某一侧」。
## ★★不能用「坑位区间包含我」那种算法(第一版就是): 决赛覆盖**所有**坑位,
##   于是**每个人的决赛格都会被标成自己的**; 而我在半决赛已经输了的那一场也照标。
##   实拍当场看出来的 —— 几何对、语义错。
func is_my_match(r: int, m: int) -> bool:
	return _is_me_side(r, m, 0) or _is_me_side(r, m, 1)


## 我现在应该看哪一场（开图居中用）：**我还活着的那一场**；
## 出局了就定位到**淘汰我的那一场**（原稿那条"我止步在这"）。
func my_focus() -> Vector2i:
	var n := int(cur().get("size", 0))
	var cur_r := int(cur().get("round", 1))
	var total := _B.rounds_for(n)
	if int(cur().get("me", -1)) < 0:
		return Vector2i(mini(cur_r, maxi(1, total)), 0)      # 纯观众: 看当前轮第一场
	## ★我**真正在的最深那一场** —— 赢一轮就往里走一格, 输了就停在输掉的那一场
	##   (原稿那条"我止步在这")。用 `competitor()` 判, 它会顺着 `done` 一路递归上来。
	var best := Vector2i(1, 0)
	var found := false
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			if is_my_match(r, m):
				best = Vector2i(r, m)
				found = true
	return best if found else Vector2i(maxi(1, mini(cur_r, total)), 0)


## 我在第 r 轮第 m 场的**哪一侧**（0 = 上半，1 = 下半）。`-1` = 我不在这个桶里。
## ★★抽出来共用（原来 `_i_won()` 里有一份、E-B6 报结果时又要一份）——
##   抄第二份就是「抄一次永远落后一次」（[[fb-hand-rolled-copies-drift]]）。
##   而这个量报错了**不会有任何报错**：它只会把对手静静送进下一轮。
## ★算法：坑位号对「本轮的跨度」取模，落在上半还是下半。
##   第 1 轮 span=2（相邻两坑一场），第 2 轮 span=4，逐轮翻倍。
func my_side(r: int, m: int) -> int:
	var me := int(cur().get("me", -1))
	if me < 0:
		return -1
	## ★★★**必须先问「我在不在这一场」**。侧别只由「坐次 + 轮次」决定，
	##   所以不判这一条的话，**我没参加的那一场也会算出一个侧来** ——
	##   而 `_i_won()` 拿它跟 `done` 里的赢家比，就会把**别人赢的那一场**算成我赢了。
	##   （这条是 `verify_dead_params` 逼出来的：它报「参数 `m` 从来没被用过」，
	##    查下去才发现不是"参数多余"，是**少了一道判断** ——
	##    死参数有时是缺陷的影子，不是噪声。）
	if not is_my_match(r, m):
		return -1
	var n := int(cur().get("size", 0))
	var seat := _B.seat_of_seed(me, n)
	if seat < 0:
		return -1
	var span: int = int(pow(2, r))
	if span < 2:
		return -1
	return (seat % span) / (span / 2)


## 这一场我打赢了要报给服务端的 `winner_side`；`-1` = 不该报。
## ★★★`finals_report` 收的是「**哪一侧**赢」，不是「谁赢」。
##   反了也不会报错 —— 它会静静地把对手送进下一轮，而屏幕上一切正常。
##   所以判据要卡的是「**我输了的时候报的是对手那一侧**」，不是「报了就行」。
func winner_side_for(r: int, m: int, i_won: bool) -> int:
	## ★「不是我的场 ⇒ -1」这条现在由 `my_side()` 自己管了（它里面先问 `is_my_match`），
	##   这里**不再重复判一遍** —— 同一判据存两份必然有一处落后。
	var s := my_side(r, m)
	if s < 0:
		return -1                     # 不是我的场 / 我不在这个桶 ⇒ 我没资格说谁赢
	return s if i_won else (1 - s)


func _i_won(r: int, m: int) -> bool:
	var key := "%d-%d" % [r, m]
	var w = (cur().get("done", {}) as Dictionary).get(key, -1)
	if int(w) < 0:
		return false
	var s := my_side(r, m)
	return s >= 0 and s == int(w)


## ─────────────────────────────────────────────────────────────
## 画
## ─────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in _canvas.get_children():
		c.queue_free()
	var vp0 := get_viewport().get_visible_rect().size
	if _bg != null:
		_bg.size = vp0                 # ★视口变了要跟上, 否则又露出瓷砖底
	_sync_tabs()
	var n := int(cur().get("size", 0))
	if n <= 1:
		## ★★不是画一张空图 —— 说清楚在等什么, 还剩多久。
		##   上午切到「冠军赛」是常态(它本来就还没形成), 这不是出错。
		if _empty_lb != null:
			_empty_lb.text = _empty_text()
			var bw: float = minf(660.0, vp0.x - 80.0)
			var bh := 126.0
			var bp := Vector2((vp0.x - bw) * 0.5, vp0.y * 0.5 - bh * 0.5 + 30.0)
			if _empty_box != null:
				_empty_box.position = bp
				_empty_box.size = Vector2(bw, bh)
				_empty_box.visible = true
			## ★图标与文字**并排**: 图标占左边 64, 文字从 108 起(留 18 的呼吸)。
			##   贴图不在就原样退回"只有字"的版式 —— 不许因为少一张图就空出一块
			##   (UISkin 铁律①「贴图缺失必须优雅退回」同族)。
			var tx_x := 30.0
			if _empty_icon != null:
				var ip := _empty_icon_path(_empty_kind())
				if ResourceLoader.exists(ip):
					_empty_icon.texture = load(ip)
					_empty_icon.position = bp + Vector2(26.0, (bh - 64.0) * 0.5)
					_empty_icon.size = Vector2(64.0, 64.0)
					_empty_icon.visible = true
					tx_x = 108.0
				else:
					_empty_icon.visible = false
			_empty_lb.position = bp + Vector2(tx_x, 18.0)
			_empty_lb.size = Vector2(bw - tx_x - 30.0, bh - 36.0)
			_empty_lb.visible = true
		if _home_btn != null:
			_home_btn.visible = false
		return
	if _empty_lb != null:
		_empty_lb.visible = false
	if _empty_box != null:
		_empty_box.visible = false
	if _empty_icon != null:
		_empty_icon.visible = false
	## ★★按**可用区**算, 不是整个视口 —— 顶栏 + 页签占掉 TOP_RESERVED。
	##   实拍抓到: 32 人桶内容 599 高, 视口 720 说"放得下", 而可用只有 530 ⇒ 其实放不下,
	##   左边两列的轮次标签被页签压在了底下。
	var vp := vp0
	var usable := Vector2(vp0.x, maxf(120.0, vp0.y - TOP_RESERVED))
	_can_pan = _L.needs_pan(n, usable)
	## ★★**要拖就不缩** —— 缩到放得下了就不需要拖, 两件事只能选一件。
	##   实拍拓到: 32 人桶同时缩到 0.80 **又**能拖, 于是字被压成 12px 还要拖——
	##   两头都不讨好。而且这是像素风项目, 缩放文字直接糊。
	_scale = 1.0 if _can_pan else _L.fit_scale(n, usable)
	_canvas.scale = Vector2(_scale, _scale)

	## ★★加入顺序 = 绘制顺序, 四层从后往前: 本轮竖带 → 连线 → 对阵格 → 轮次标签。
	##   原来是「格子 → 连线」, 连线画在格子上面 —— 箭头顶进格子里就会糊在描边上。
	var total := _B.rounds_for(n)
	_make_round_band(n, total)
	_make_links(n, total)
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			_canvas.add_child(_make_node(r, m))
	_make_round_labels(n, total)
	_center_on_me()
	if _home_btn != null:
		## 不需要拖的规模就没有"迷路"这回事 ⇒ 藏起来, 不占地方
		_home_btn.visible = _can_pan
		_home_btn.position = vp - Vector2(140 + 24, 81 + 24)


## 顶部那一行轮次标签：`32强 | 16强 | 8强 | 半决赛 | 决赛 | 半决赛 | 8强 | 16强 | 32强`。
## ★参考图（用户给的世界杯晋级图）顶部就是这一条，而且**是对称的** ——
##   它一眼告诉你"现在看的是哪一轮"，在 9 列的 32 人桶里是必需品。
## ★跟着画布一起拖（不是钉在屏上）—— 标签必须停在它那一列的正上方，飘走就没意义了。
## 当前那张还没形成时，屏幕中间说什么。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★★空态【先分类, 再翻成人话】(2026-09-28)
## ══════════════════════════════════════════════════════════════════════
## 原来 `_empty_text()` 一个函数既判断又措辞, 于是三条门禁判据**各自抄了一份屏幕字面量**:
##   · `verify_finals_feed` ⑥ 抄「没有你的桶」「正在连线」
##   · `verify_bracket_map` ⑤ 抄「还没做」
## 后果有两层, 第二层才是真的坏:
##   ① 换一个词就红 —— 而这一轮要换掉的正是「桶」(bucket 的直译, 玩家不知道那是什么);
##   ② **判据把缺陷钉在了原地**: 「还没做」是一句**开发状态**, 而那条判据要求它
##      必须出现在玩家眼前(memory fb-gate-can-pin-the-bug-in-place)。玩家不需要知道
##      我们做完没做完, 只需要知道**现在按什么算**。
## ⇒ 拆成两层: `_empty_kind()` 是**唯一那份判断**(返回下面几个命名常量),
##   `_empty_text()` 只负责把它翻成人话, 自己一个条件都不判。
##   门禁改成量**分类**, 文案随便改都不影响; 而「两种情况说的必须是两句不同的话」
##   由 `txt_wait != txt_done` 那条断言守着 —— 它量的本来就是行为。
## ⚠ 判断只有这一份, 所以两层不会漂(memory fb-hand-rolled-copies-drift)。
const EK_WAIT := "wait"                  # 还没问到回音(正在找名册)
const EK_UNREACHABLE := "unreachable"    # 问不到 —— 每 30 秒自己再看一次
const EK_TOO_FEW := "too_few"            # 我晋级了, 但全周人太少, 决赛日没开起来
const EK_FINALS_SOON := "finals_soon"    # 冠军赛还没集结(CROSS_BUCKET_LIVE 之后才走到)
const EK_FINALS_LOCAL := "finals_local"  # 跨组总决赛没上线 ⇒ 各组自己评冠军
const EK_NO_GROUP := "no_group"          # 确实没有我这一组(没晋级)


## 空态判断与措辞共用的那一份数据: 自己联网时取缓存, 被喂过就用喂进来的那张。
func _feed_view() -> Dictionary:
	return _bucket if _injected else (_SB.finals_cached() as Dictionary)


## 现在是哪一种空态。★★门禁量这个, **不量屏幕字面量**(见上面那段的由来)。
func _empty_kind() -> String:
	## ★自己联网取数时: **还没问到回音**跟**问到了但没有我这一组**要分开说。
	##   混成一句的话, 网络慢的人会以为自己没进决赛日。
	if not _injected and not _SB.finals_tried():
		return EK_WAIT
	var fv: Dictionary = _feed_view()
	## ★★「问不到」要说「这会儿连不上」, **不能**掉到最后那句「本周没有你这一组」——
	##   那对一个已晋级的人是假话(2026-09-27 查实)。每 30 秒自己再看, 所以要说清这件事。
	if str(fv.get("reason", "")) == _SB.UNREACHABLE:
		return EK_UNREACHABLE
	## ★★「有资格但人不够」与「没资格」说的必须是两句话(2026-09-25)。
	##   `finals_seat` 对 1 个人故意不开组(一个人一组 = 没有对手的冠军, 那不是比赛),
	##   而那个人**确实周六 4 胜晋级了** —— 「晋级才进得来」对他是假话,
	##   他会以为自己的胜场没算。10 个人规模下晋级率约 34% ⇒ 只 0~1 人晋级约 10%,
	##   这不是假想的边角。
	if str(fv.get("reason", "")) == "too_few":
		return EK_TOO_FEW
	if _view == _L.VIEW_FINALS:
		## ★★★2026-09-26: 跨组总决赛是 **F 阶段**, 一行都没做 ——
		##   服务端只有 `finals_buckets/entrants/results/scout/pending`, 没有任何
		##   「各组冠军汇总」; 客户端 `_finals` 只有老调用点 `set_data()`(门禁用)会写,
		##   联网那条路 `_on_poll` **只写 `_bucket`**。
		##   ⇒ 原来这里一小时一小时地倒计时, 而那个东西永远不会来。
		##   ⇒ 上线那天把 `CROSS_BUCKET_LIVE` 翻成 true, 倒计时那两句就回来
		##     (memory fb-branch-to-an-unbuilt-mode-is-a-backdoor: 让「没上线」是可读状态)。
		## ★写成 if/else 而**不是** `if not CROSS_BUCKET_LIVE: return …` ——
		##   后者会让上线那一支变成死代码, `tools/const_branch_audit.py` 当场判红
		##   (恒真常量分支 + return 吞掉同函数后续代码), 而那条审计器是对的。
		if CROSS_BUCKET_LIVE:
			return EK_FINALS_SOON
		else:
			return EK_FINALS_LOCAL
	return EK_NO_GROUP


## 空态图标 —— 分类 → `assets/sprites/ui/` 里**现成**的像素图标。
## ★CLAUDE.md「素材库先搜再造」: 这几张是已有的, 一张都没新生成。
## ★三种「还在读名册」的情况共用夹板(quota) —— 它们讲的本来就是同一件事;
##   冠军那两档用奖杯; 「没有我这一组」用锁(你进不来, 不是出错了)。
func _empty_icon_path(kind: String) -> String:
	match kind:
		EK_FINALS_SOON, EK_FINALS_LOCAL:
			return "res://assets/sprites/ui/icon-trophy.png"
		EK_NO_GROUP:
			return "res://assets/sprites/ui/icon-lock.png"
	return "res://assets/sprites/ui/icon-quota.png"


## 把分类翻成人话。★★这里**一个条件都不判** —— 判断全在 `_empty_kind()`。
##
## ★★★用词(2026-09-28): 屏幕上不许出现「桶」「拉」「取」「重试」「连线」这些
##   **内部词 / 接口词**, 也不许出现「还没做」这类**开发状态**。
##   「桶」是 bucket 的中文直译, 玩家根本不知道那是什么 ⇒ 全屏统一成「组」,
##   自称一律「我这一组」。
## ★用词仍然是「开播」，不写「直播」(它就是回放)也不写「回放」(会泄露已经打完了)。
func _empty_text() -> String:
	match _empty_kind():
		EK_WAIT:
			return "正在翻本周的名册 · 看看你分在哪一组"
		EK_UNREACHABLE:
			return "连不上服务器 · 你这一组还没看到, 每 30 秒自己再看一次"
		EK_TOO_FEW:
			return "本周只有 %d 人晋级 · 人太少, 决赛日没开起来; 你的晋级算数, 下周再来" % int(_feed_view().get("entered", 0))
		EK_FINALS_SOON:
			var left: int = int(_L.finals_start_ts(_clock())) - _clock()
			if left > 0:
				return "冠军赛 %d 小时 %d 分后开播 · 先等各组决出自己的冠军" % [left / 3600, (left % 3600) / 60]
			return "冠军赛正在集结 · 等各组决出自己的冠军"
		EK_FINALS_LOCAL:
			## ★★★只说**现在按什么算**, 不把内部进度顶在玩家脸上(2026-09-28)。
			##   原来这句话缀着「跨组总决赛还没做出来」—— 一句**开发状态**,
			##   而且是被 `verify_bracket_map` ⑤ 的判据**要求**必须在的
			##   (那条判据已同一次改成量分类, 见上)。
			return "本周按各组自己算冠军 · 你这一组的冠军就是本周冠军"
	return "本周没有你这一组 · 周六闯关赛晋级才进得来"


## 两个 Tab 的样子：当前那张高亮；**还没形成的那张不禁用**（要让人点进去看倒计时），
## 但名字后面缀一个「·未开」，免得点进去才发现是空的。
func _sync_tabs() -> void:
	if _tabs == null:
		return
	var kids := _tabs.get_children()
	if kids.size() < 2:
		return
	var names := [
		"我这一组" + ("" if int(_bucket.get("size", 0)) > 1 else " · 还没分"),
		"冠军赛" + ("" if int(_finals.get("size", 0)) > 1 else " · 未开赛"),
	]
	var views := [_L.VIEW_BUCKET, _L.VIEW_FINALS]
	for i in range(2):
		var b := kids[i] as Button
		b.text = str(names[i])
		_fit_tab(b)
		var on: bool = str(views[i]) == _view
		b.add_theme_color_override("font_color", ACCENT if on else DIM)
		## ★形态: 选中那一页底下压一条实心杠; 没选中的只留一道暗底槽。
		var ul := b.get_node_or_null("Underline") as ColorRect
		if ul != null:
			ul.size.x = b.custom_minimum_size.x - 12.0
			ul.color = ACCENT if on else Color("#222c3e")


## 页签宽度**按字量**, 不拍脑袋。
##
## ★★★2026-09-28 实拍抓到: 页签的字**压在木边带上** —— 「我这一组 · 还没分」
##   9 个字比写死的 132 宽, 首尾两个字骑在木框上, 一眼就是没做完的样子。
##   而这个坑**一直没人看见**: `verify_ui_consistency` 的「文字压边带」那条
##   只量 Label 和 TextureRect 图标, **量不到 Button 自己画的字**
##   (memory fb-gate-subject-never-constructed 的同族: 判据没错, 被测的那个量不在它眼里)。
##   ⇒ 判据补在 `verify_finals_feed` ⑥, 宽度在这里算。
##
## ★边带宽度**从 StyleBox 上读**, 不在这里抄一份 27
##   (`UISkin.button` 给大按钮套的是 `menu/frame-rect.png`, 九宫格边距 27) ——
##   抄一次就永远落后(memory fb-hand-rolled-copies-drift)。换皮/换图都不用动这里。
func _fit_tab(b: Button) -> void:
	var band := 0.0
	var sbx = b.get_theme_stylebox("normal")
	if sbx is StyleBoxTexture:
		band = maxf(float((sbx as StyleBoxTexture).texture_margin_left),
			float((sbx as StyleBoxTexture).texture_margin_right))
	var need := 132.0
	var fnt := b.get_theme_font("font")
	if fnt != null:
		## +16 = 两侧各 8 的呼吸。贴着边带排也算"没压上", 但看着像挤的。
		need = fnt.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			b.get_theme_font_size("font_size")).x + band * 2.0 + 16.0
	b.custom_minimum_size.x = maxf(132.0, ceilf(need))


## ══════════════════════════════════════════════════════════════════════
##  像素描边小工具 —— 这一屏所有"质感"都由这四个函数堆出来, 一张贴图都不用
## ══════════════════════════════════════════════════════════════════════
## ★`mouse_filter = IGNORE` 是**必需的**, 不是顺手: ColorRect 继承 Control,
##   默认 `MOUSE_FILTER_STOP` ⇒ 铺在格子上的装饰块会把「每一场自己就是按钮」那件事
##   整片吃掉(点了没反应)。
func _rect(parent: Control, x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = col
	cr.position = Vector2(x, y)
	cr.size = Vector2(maxf(w, 1.0), maxf(h, 1.0))
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
	return cr


## 四条边的实心描边(直角, 不是 StyleBox —— 半透明描边走 StyleBoxFlat 会被
## `verify_ui_consistency` 判成"网页盒"(四边描边 + 半透底 = CSS border+rgba 的长相),
## 而这里要的正是半透明金色外环 ⇒ 用色块拼)。
func _outline(parent: Control, r: Rect2, t: float, col: Color) -> void:
	_rect(parent, r.position.x, r.position.y, r.size.x, t, col)
	_rect(parent, r.position.x, r.end.y - t, r.size.x, t, col)
	_rect(parent, r.position.x, r.position.y, t, r.size.y, col)
	_rect(parent, r.end.x - t, r.position.y, t, r.size.y, col)


## 一段虚线(横 `horiz=true` / 竖)。★「还没到」的那一格靠它与实线描边区分 ——
##   形态差别不靠颜色, 弱视/小屏/截图压缩下都还在。
func _dash(parent: Control, x: float, y: float, len_px: float, t: float,
		col: Color, horiz: bool, on: float = 6.0, off: float = 5.0) -> void:
	var p := 0.0
	while p < len_px:
		var seg: float = minf(on, len_px - p)
		if horiz:
			_rect(parent, x + p, y, seg, t, col)
		else:
			_rect(parent, x, y + p, t, seg, col)
		p += on + off


func _dash_box(parent: Control, r: Rect2, t: float, col: Color) -> void:
	_dash(parent, r.position.x, r.position.y, r.size.x, t, col, true)
	_dash(parent, r.position.x, r.end.y - t, r.size.x, t, col, true)
	_dash(parent, r.position.x, r.position.y, r.size.y, t, col, false)
	_dash(parent, r.end.x - t, r.position.y, r.size.y, t, col, false)


## 阶梯像素箭头(不是三角形多边形 —— 斜边会被抗锯齿糊掉, 像素风要的是台阶)。
## `tip_x` 是尖端, `to_right` 决定往哪边张开; `steps` 由可用空档决定(空档窄就缩短)。
func _arrow(parent: Control, tip_x: float, y: float, to_right: bool,
		col: Color, steps: int) -> void:
	for i in range(steps):
		var hh: float = float(i + 1) * 4.0
		var x: float = (tip_x - float(i + 1) * 3.0) if to_right else (tip_x + float(i) * 3.0)
		_rect(parent, x, y - hh * 0.5, 3.0, hh, col)


## 一格的底色与描边色。★**形态**(实线 / 实线加粗+角标 / 虚线)才是主判据,
##   颜色只是帮忙 —— 用户要的是"一眼分得出", 不是"配色好看"。
func _state_colors(st: String) -> Array:
	match st:
		ST_DONE:
			return [Color("#111b24"), Color("#3f6579")]
		ST_LIVE:
			return [Color("#1a2437"), ACCENT]
		ST_LOCKED:
			return [Color("#0b0f17"), Color("#161d2b")]
		ST_BYE:
			return [Color("#0d1118"), Color("#1a2231")]
	return [Color("#141b28"), Color("#2c3950")]


## 名字太长就截断。★不能用 `clip_text`: 那会被 `verify_ui_consistency` 判成
##   「被 clip_text 截断的文字」(它是对的 —— 硬裁出来的半个字读不出来)。
##   ⇒ 在**文字层**截, 留一个省略号。13px 的汉字≈13px 宽, 除得到能放几个。
func _fit_name(nm: String, px: float, tick: bool) -> String:
	var avail: float = px - (16.0 if tick else 0.0)
	var maxc: int = int(avail / 13.0)
	if maxc < 2 or nm.length() <= maxc:
		return nm
	return nm.substr(0, maxi(1, maxc - 1)) + "…"


## 【本轮】那一列的竖带。★9 列的 32 人桶里"现在打到哪儿了"光靠标签变色看不出来,
##   整列压一条极淡的带子, 眼睛一扫就落在对的那一列上。镜像布局两侧各一条。
func _make_round_band(n: int, total: int) -> void:
	var r0 := int(cur().get("round", 1))
	if r0 < 1 or r0 > total:
		return
	var cnt := _B.matches_in_round(n, r0)
	var picks: Array = [0] if r0 >= total else [0, cnt / 2]
	var cs: Vector2 = _L.content_size(n)
	for m in picks:
		var rect: Rect2 = _L.node_rect(n, r0, m)
		if rect.size == Vector2.ZERO:
			continue
		_rect(_canvas, rect.position.x - 10.0, -44.0, rect.size.x + 20.0, cs.y + 56.0,
			Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.05))


func _make_round_labels(n: int, total: int) -> void:
	for r in range(1, total + 1):
		var txt := _L.round_label(n, r)
		if txt == "":
			continue
		## 每一侧各放一个；决赛只有中间一个
		var cnt := _B.matches_in_round(n, r)
		var picks: Array = [0] if r >= total else [0, cnt / 2]
		for m in picks:
			var rect: Rect2 = _L.node_rect(n, r, m)
			if rect.size == Vector2.ZERO:
				continue
			## 标签底下压一条杠: 本轮是实心亮杠, 其余是一道暗槽 —— 与页签同一套语言。
			var on: bool = r == int(cur().get("round", 1))
			_rect(_canvas, rect.position.x + 6.0, -12.0, rect.size.x - 12.0,
				3.0 if on else 1.0, ACCENT if on else Color("#222c3e"))
			var lb := Label.new()
			lb.text = txt
			lb.position = Vector2(rect.position.x, -34.0)
			lb.size = Vector2(rect.size.x, 24.0)
			lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lb.add_theme_font_size_override("font_size", 13)
			## 当前轮用强调色 —— 其余淡下去, 免得九个标签一样抢眼
			lb.add_theme_color_override("font_color",
				ACCENT if r == int(cur().get("round", 1)) else DIM)
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(lb)


## 这一场某一侧（0=上 1=下）坐的是谁。
## 返回 {"name": 名字/"待定"/"轮空", "seed": 种子号(-1=未定), "bye": 是不是空位}
## ★★递归: 第 r 轮上面那一侧 = 第 r−1 轮第 2m 场的**赢家**。
##   —— 这正是"对阵图"这件事本身, 写成查表就会跟晋级规则脱钩。
## ★★★2026-09-26 这里原来有一整份递归(顺着 `done` 一路往前推谁坐这个坑)。
##   已下沉到 `bracket.gd` 的 `occupant_seed()` —— 因为**多了第二个消费者**:
##   发冠军/四强头衔也要「我走到第几轮」, 而那必须用同一份推导
##   (memory fb-hand-rolled-copies-drift: 抄一次永远落后一次)。
## ⇒ 本函数现在只做一件事: **把种子号换成显示名**。轮空/待定两种空态各自保留,
##   它们在界面上是两句不同的话("轮空" vs "待定"), 混成一个会让有轮空的桶
##   在第二轮显示成"待定 vs 待定"(2026-09-25 修过一次的那个)。
func competitor(r: int, m: int, side: int) -> Dictionary:
	var n := int(cur().get("size", 0))
	var names: Array = cur().get("names", [])
	var sd := _B.occupant_seed(r, m, side, n, cur().get("done", {}) as Dictionary)
	if sd == _B.OCC_BYE:
		return {"name": "轮空", "seed": -1, "bye": true}
	if sd < 0:
		return {"name": "待定", "seed": -1, "bye": false}
	return {"name": str(names[sd]) if sd < names.size() else "神秘龟", "seed": sd, "bye": false}


## 本轮这一场里，**我的对手**是几号种子。`-1` = 拿不到。
## ★★这个函数存在的唯一理由是 E-B4：`finals_opponent` **每人每轮只能问一个种子**
##   （服务端 `finals_scout` 先到先得），所以「我的对手是谁」必须在**问之前**算准 ——
##   算错了就浪费掉这一轮唯一的机会。
## 四种拿不到，各自的含义完全不同，所以都返回 -1 但由调用方按场景说话：
##   · 我不在这一场里（点的是别人的格子）
##   · 我轮空（没有对手）
##   · 对手那一侧还没产生（上一轮没打完 ⇒ "待定"）
##   · 我压根不在这个桶里（纯观众）
func my_opponent_seed(r: int, m: int) -> int:
	var me := int(cur().get("me", -1))
	if me < 0:
		return -1
	var a: Dictionary = competitor(r, m, 0)
	var b: Dictionary = competitor(r, m, 1)
	var foe: Dictionary = {}
	if int(a.get("seed", -1)) == me:
		foe = b
	elif int(b.get("seed", -1)) == me:
		foe = a
	else:
		return -1                     # 不是我的场
	## ★**防御性，不承重**（2026-09-25 反向验证查实）：`competitor()` 给轮空返回的
	##   dict 里 `seed` 本来就是 -1，所以把这一行改坏**一条断言都不红** ——
	##   它在任何输入下都不改变结果。留着是为了把「轮空 = 没有对手」这个意思写在明面上，
	##   以及万一以后 `competitor()` 改成给轮空也带个真种子号。
	##   ⚠ 不要因为它在这儿就以为「轮空」这件事有判据在守 ——
	##   守它的是下面 `should_fetch_opponent()` 里的 `match_state != ST_LIVE`。
	if bool(foe.get("bye", false)):
		return -1                     # 轮空: 没有对手可问
	return int(foe.get("seed", -1))   # 「待定」时它本来就是 -1


## 点开一场时要不要去问服务端要对手快照。
## ★★★**只有「我自己的、当前轮的、对手已定的」那一场才问** ——
##   每人每轮只有一次机会，替别人点一下就把它烧掉了。
##   这一条是纯判定，与网络无关 ⇒ 门禁能穷举，不用起网络。
func should_fetch_opponent(r: int, m: int) -> bool:
	if match_state(r, m) != ST_LIVE:
		return false                  # 已翻面的场次不用问，轮空/未开打也问不出东西
	if r != int(cur().get("round", 1)):
		return false                  # 服务端只认当前轮，问了也是 wrong_round
	return my_opponent_seed(r, m) >= 0


## 这一侧是不是我。
func _is_me_side(r: int, m: int, side: int) -> bool:
	var me := int(cur().get("me", -1))
	if me < 0:
		return false
	return int(competitor(r, m, side).get("seed", -1)) == me


## 这一场的赢家在哪一侧；-1 = 还不知道（**当前轮就是 -1，靠这个不剧透**）。
func winner_side(r: int, m: int) -> int:
	var d: Dictionary = cur().get("done", {})
	var key := "%d-%d" % [r, m]
	return int(d[key]) if d.has(key) else -1


## ══════════════════════════════════════════════════════════════════════
##  一格对阵 —— 三种状态**靠形态**分, 不只靠颜色(用户 2026-09-27)
## ══════════════════════════════════════════════════════════════════════
##   · 已打完 ST_DONE  : 实线框 + **胜者那一行整条亮底 + 前缘 4px 竖条 + ✓**,
##                       败者那一行**压暗**。两行的明暗差本身就是"结果"。
##   · 正在打 ST_LIVE  : 加粗描边 + **四角准星括号** + 中缝是**锯齿**(两边还在咬)
##   · 还没到 ST_LOCKED: **虚线空槽**(描边宽度 0, 靠虚线画), 中缝也是虚线
##   · 轮空   ST_BYE   : 最暗的底, 实线细框 —— 它不是"等着打", 而是"这里没人"
## ★为什么不靠颜色: 这四种在灰度截图 / 小屏 / 色弱下都得分得出来。
##   原来 LIVE 与 LOCKED **长得一模一样**(同底同框), 只有一个 ▶ 的差别。
func _make_node(r: int, m: int) -> Control:
	var n := int(cur().get("size", 0))
	var rect: Rect2 = _L.node_rect(n, r, m)
	var st := match_state(r, m)
	var mine := is_my_match(r, m)
	var ws := winner_side(r, m)
	var sh: float = _L.slot_h()
	var total := _B.rounds_for(n)
	var w: float = rect.size.x
	var h: float = rect.size.y

	var holder := Control.new()
	holder.position = rect.position
	holder.custom_minimum_size = rect.size
	holder.size = rect.size

	## ★★「我在哪一格」= 这屏的头等大事(文件头 ★①)。原来只有**一圈 2px 金边**,
	##   而已打完的格子也有亮底、当前轮也有亮框 ⇒ 32 人桶里根本挑不出来。
	##   ⇒ 两层金色外环 往外撑 7px, 谁都不会长这样。
	if mine:
		_outline(holder, Rect2(-7.0, -7.0, w + 14.0, h + 14.0), 2.0,
			Color(MINE.r, MINE.g, MINE.b, 0.15))
		_outline(holder, Rect2(-4.0, -4.0, w + 8.0, h + 8.0), 2.0,
			Color(MINE.r, MINE.g, MINE.b, 0.45))

	## ★硬投影(右下 4px, **不羽化**) —— 像素 UI 的招牌。
	##   网页味的那种是 `box-shadow: 0 2px 8px rgba(...)`, 有羽化; 这里一格实心块。
	_rect(holder, 4.0, 4.0, w, h, SHADOW)

	var cols: Array = _state_colors(st)
	var bd_w: int = 2 if st == ST_LIVE else 1
	var bd_c: Color = cols[1]
	if mine:
		bd_c = MINE
		bd_w = 2
	var frame := Panel.new()
	frame.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = cols[0]
	sb.border_color = bd_c
	## ★「还没到」那一格描边宽度给 0 —— 它的边由下面的**虚线**画。
	##   (我那一格例外: 金边压倒一切, 否则"我在哪"又看不见了。)
	sb.set_border_width_all(0 if (st == ST_LOCKED and not mine) else bd_w)
	## ★★2026-09-27 改**直角**: 原来 `set_corner_radius_all(3)`, 而圆角正是用户点名的
	##   「很 ai 味和网页味」。参考图(Worlds 官方对阵图)的节点本来就是**直角横条**。
	sb.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	if st == ST_LOCKED and not mine:
		_dash_box(holder, Rect2(0.0, 0.0, w, h), 2.0, DASH)
	else:
		## 内缘一亮一暗 = 像素浮雕。比 CSS 的渐变便宜, 而且缩放不糊。
		_rect(holder, float(bd_w), float(bd_w), w - float(bd_w) * 2.0, 1.0, Color(1, 1, 1, 0.07))
		_rect(holder, float(bd_w), h - float(bd_w) - 1.0, w - float(bd_w) * 2.0, 1.0,
			Color(0, 0, 0, 0.30))

	## ★已翻面: 两行的**明暗**就是结果。不剧透靠的是 `ws == -1`(当前轮拿不到),
	##   所以这一整块在当前轮根本不画 —— 而不是"画了再藏起来"(文件头 ★②)。
	if ws >= 0:
		_rect(holder, 1.0, float(ws) * sh + 1.0, w - 2.0, sh - 2.0, PLATE_WIN)
		_rect(holder, 1.0, float(1 - ws) * sh + 1.0, w - 2.0, sh - 2.0, PLATE_LOSE)
		_rect(holder, 1.0, float(ws) * sh + 1.0, 4.0, sh - 2.0,
			MINE if _is_me_side(r, m, ws) else ACCENT)

	## 两行: 上侧 / 下侧
	var name_w: float = maxf(28.0, w - 9.0 - GUTTER)
	for side in range(2):
		var c: Dictionary = competitor(r, m, side)
		var nm := str(c.get("name", "神秘龟"))
		var is_bye := bool(c.get("bye", false))
		var tick: bool = ws >= 0 and side == ws
		var lb := Label.new()
		lb.position = Vector2(9, float(side) * sh)
		## ★★宽度**必须**给右边那条槽留出 GUTTER —— 「你」/「冠」小签住在那里,
		##   不留的话名字会骑在小签上(而 `verify_ui_consistency` 的"两段文字压在一起"
		##   只量 Label 矩形, 骑上去它也照样绿 ⇒ 这一条得自己守)。
		lb.size = Vector2(name_w, sh)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 13)
		## ★★谁赢**只在已翻面时**标出来 —— 当前轮 `ws == -1`, 两侧一样亮 ⇒ 不剧透。
		##   而双方**名字照常显示**(参考里 SF1「法国 VS 西班牙」就是还没打的那一场),
		##   剧透的是"谁赢"不是"谁打"。
		var col := TXT
		if is_bye:
			col = DIM
		elif ws >= 0:
			col = ACCENT if side == ws else DIM
		if _is_me_side(r, m, side):
			col = MINE
		lb.add_theme_color_override("font_color", col)
		## ★「✓ 」前缀**必须留在最前面**: `verify_bracket_map` ① 数的是
		##   `begins_with("✓")` 的 Label 条数(它正是"已翻面才标胜者"那条判据的分母)。
		lb.text = ("✓ " if tick else "") + _fit_name(nm, name_w, tick)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lb)

		## ★右槽小签: 金牌子 + 深色字, 一眼跳出来。「冠」优先于「你」——
		##   我自己夺冠时"冠"信息量更大, 而我那一格本来就有金环 + 金字在标。
		var badge := ""
		if r >= total and ws == side:
			badge = "冠"
		elif _is_me_side(r, m, side):
			badge = "你"
		if badge != "":
			var bx: float = w - GUTTER + 2.0
			var by: float = float(side) * sh + (sh - 22.0) * 0.5
			_rect(holder, bx + 2.0, by + 2.0, 24.0, 22.0, SHADOW)
			_rect(holder, bx, by, 24.0, 22.0, MINE)
			_rect(holder, bx, by, 24.0, 2.0, Color(1, 1, 1, 0.45))
			var bl := Label.new()
			bl.text = badge
			bl.position = Vector2(bx, by)
			bl.size = Vector2(24.0, 22.0)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bl.add_theme_font_size_override("font_size", 13)
			bl.add_theme_color_override("font_color", BG)
			bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(bl)

	## ★中缝三种形态: 实线(打完/轮空) · 锯齿(正在打) · 虚线(还没到)。
	##   参考图那里是个 VS 徽章, 但 104~268 宽的条子上塞 76x56 的徽章要缩到半尺寸,
	##   像素图 0.5 倍最近邻会掉掉一半像素(battle_hud 那张 `pk-vs-emblem` 是原尺寸用的)
	##   ⇒ 改用**缝的形状**说话, 零缩放、零新素材。
	var seam_y: float = sh - 1.0
	if st == ST_LIVE:
		var i := 0
		var x := 6.0
		while x < w - 9.0:
			_rect(holder, x, seam_y + (-2.0 if i % 2 == 0 else 1.0), 4.0, 3.0,
				MINE if mine else ACCENT)
			x += 6.0
			i += 1
	elif st == ST_LOCKED:
		_dash(holder, 6.0, seam_y, w - 12.0, 1.0, DASH, true, 5.0, 4.0)
	else:
		_rect(holder, 6.0, seam_y, w - 12.0, 1.0, Color("#2c3950"))

	## ★四角准星括号 = 「正在打」的形态标记(赛事直播里锁定镜头的那种)。
	if st == ST_LIVE:
		var cc: Color = MINE if mine else ACCENT
		var al := 11.0
		for sx in [0, 1]:
			for sy in [0, 1]:
				_rect(holder, 0.0 if sx == 0 else w - al, 0.0 if sy == 0 else h - 3.0,
					al, 3.0, cc)
				_rect(holder, 0.0 if sx == 0 else w - 3.0, 0.0 if sy == 0 else h - al,
					3.0, al, cc)

	if can_open(r, m):
		## 能点的那一格右槽里放一个**阶梯像素播放标**(原来是字体里的 ▶ 字形 ——
		## 那玩意儿在像素风里是唯一一个抗锯齿的东西)。
		var pc: Color = MINE if mine else ACCENT
		for i2 in range(4):
			var hh: float = float(4 - i2) * 4.0
			_rect(holder, w - GUTTER + 6.0 + float(i2) * 3.0, sh - hh * 0.5, 3.0, hh, pc)
		var btn := Button.new()
		btn.flat = true
		btn.size = rect.size
		## ★★用词分两种(2026-09-27): `can_open` 现在**只对我自己的当前轮**为真
		##   (见 `can_open` 的头注), 点下去是**我上场打**, 不是看别人 ⇒ 写「开播」是错的。
		##   重放那条路上线之后才是真的"开播看回放"(文件头 ★④: 不许写「直播」「回放」)。
		btn.tooltip_text = "上场开打" if should_fetch_opponent(r, m) else "开播"
		btn.pressed.connect(func(): match_opened.emit(r, m))
		holder.add_child(btn)
	return holder


## ══════════════════════════════════════════════════════════════════════
##  ★★★连接线 —— 用户点名的"网页味"第二个来源就在这里(2026-09-27)
## ══════════════════════════════════════════════════════════════════════
## 原来: 每一段都是**同一个颜色、同一个 2px 粗细**的直角细线 ⇒ 那就是 CSS 流程图。
## 真的赛事对阵图里连线是**有轻重的**, 而且轻重**就是信息**:
##   · 已经有人走过去了(那个坑的占位者已确定) ⇒ **4px 亮线 + 末端阶梯箭头**
##   · 还没决出                              ⇒ **2px 暗线**, 没箭头
##   · 那条路是**我**走的                     ⇒ 金色(和"我"那一格同一个语言)
## ★★判据用 `competitor(r, m, side).seed >= 0` 而不是 `match_state(r-1, ...)`:
##   前者就是「这个坑里坐的是谁」本身(`occupant_seed` 连**轮空自动晋级**都算进去了),
##   后者会把"上一场是轮空"这种情况判成"还没决出" —— 而那个人其实已经站在这儿了。
## ★不剧透不受影响: 当前轮的 `done` 客户端根本没有 ⇒ 占位者是 -1 ⇒ 线是暗的。
func _make_links(n: int, total: int) -> void:
	for r in range(2, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			var me_rect: Rect2 = _L.node_rect(n, r, m)
			var a: Rect2 = _L.node_rect(n, r - 1, m * 2)
			var b: Rect2 = _L.node_rect(n, r - 1, m * 2 + 1)
			if me_rect.size == Vector2.ZERO or a.size == Vector2.ZERO:
				continue
			## 来源在本场的左边还是右边 —— 镜像布局两侧相反
			var from_left: bool = a.position.x < me_rect.position.x
			var src_x: float = a.end.x if from_left else a.position.x
			var dst_x: float = me_rect.position.x if from_left else me_rect.end.x
			var mid_x: float = (src_x + dst_x) * 0.5
			var ay: float = a.position.y + a.size.y * 0.5
			var by: float = b.position.y + b.size.y * 0.5
			var my: float = me_rect.position.y + me_rect.size.y * 0.5
			## `a` 喂本场的 0 侧、`b` 喂 1 侧 —— 与 `bracket.occupant_seed` 的
			## `src_m = m * 2 + side` 同一条口径(反了会把两条线的明暗对调)。
			var lit_a: bool = int(competitor(r, m, 0).get("seed", -1)) >= 0
			var lit_b: bool = int(competitor(r, m, 1).get("seed", -1)) >= 0
			var mine_a: bool = _is_me_side(r, m, 0)
			var mine_b: bool = _is_me_side(r, m, 1)
			_h_line(src_x, mid_x, ay, lit_a, mine_a)
			_h_line(src_x, mid_x, by, lit_b, mine_b)
			_v_line(mid_x, ay, by, lit_a and lit_b, mine_a or mine_b)
			var lit: bool = lit_a or lit_b
			_h_line(mid_x, dst_x, my, lit, is_my_match(r, m))
			if lit:
				## 箭头长度受空档限制: 32 人桶列间只剩 19px, 4 级台阶(12px)会顶过
				## 中线糊在竖线上 ⇒ 按可用空档收级数。
				var room: float = absf(dst_x - mid_x)
				_arrow(_canvas, dst_x, my, from_left,
					_link_col(true, is_my_match(r, m)), clampi(int(room / 3.0), 2, 4))


## 连线的颜色: 亮/暗两档 × 是不是我走的那条。
func _link_col(lit: bool, mine: bool) -> Color:
	if not lit:
		return LINE_DIM
	return MINE if mine else ACCENT


## 一段横线(带硬投影)。★投影压在线的**下方 2px**, 与格子的右下投影同一个光源方向 ——
##   方向不一致的话整屏立刻显得是拼出来的。
func _h_line(x0: float, x1: float, y: float, lit: bool, mine: bool) -> void:
	var t: float = LINE_W_LIT if lit else LINE_W_DIM
	var w: float = absf(x1 - x0)
	if w <= 0.5:
		return
	var x: float = minf(x0, x1)
	_rect(_canvas, x, y + t * 0.5, w, 2.0, SHADOW)
	_rect(_canvas, x, y - t * 0.5, w, t, _link_col(lit, mine))


## 一段竖线(把两个来源并起来)。★两端各外扩 t/2, 否则拐角处会缺一小块
##   —— 直角拼线的老毛病, 缺口正好在最显眼的位置。
func _v_line(x: float, y0: float, y1: float, lit: bool, mine: bool) -> void:
	var t: float = LINE_W_LIT if lit else LINE_W_DIM
	var h: float = absf(y1 - y0)
	if h <= 0.5:
		return
	var y: float = minf(y0, y1)
	_rect(_canvas, x + t * 0.5, y - t * 0.5 + 2.0, 2.0, h + t, SHADOW)
	_rect(_canvas, x - t * 0.5, y - t * 0.5, t, h + t, _link_col(lit, mine))


## 顶栏 + 页签占掉的高度 —— 图要摆在它们下面, 不然被压住。
const TOP_RESERVED := 190.0


func _center_on_me() -> void:
	var n := int(cur().get("size", 0))
	if n <= 1:
		return
	var vp := get_viewport().get_visible_rect().size
	var usable := Vector2(vp.x, maxf(120.0, vp.y - TOP_RESERVED))
	if not _can_pan:
		## ★★放得下 ⇒ 把**整张图**摆正中, **不要去追"我"那一场**。
		##   追了会把另外半边推出屏幕 —— 实拍当场抓到: 32 人桶右半区整个不见,
		##   而门禁 30 条全绿(它量的是"我那一场在视口正中", 那条本身没错, 错在前提)。
		var cs: Vector2 = _L.content_size(n)
		_pan = Vector2(
			(usable.x - cs.x * _scale) * 0.5 - _L.SIDE_PAD * _scale,
			TOP_RESERVED + (usable.y - cs.y * _scale) * 0.5)
	else:
		var f := my_focus()
		_pan = _L.center_offset_on(n, f.x, f.y, usable, _scale) + Vector2(0.0, TOP_RESERVED)
	_apply_pan()


func _apply_pan() -> void:
	if _canvas != null:
		_canvas.position = _pan


func _gui_input(ev: InputEvent) -> void:
	if not _can_pan:
		return                            # ★放得下就不让拖 —— 拖一张不动的图很困惑
	if ev is InputEventMouseButton:
		if (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_dragging = (ev as InputEventMouseButton).pressed
	elif ev is InputEventMouseMotion and _dragging:
		_pan += (ev as InputEventMouseMotion).relative
		_apply_pan()


## ─────────────────────────────────────────────────────────────
## 自己去服务端取数据。★门禁与调试台会先 `set_data()` 注入,
##   那时**不许**再去联网覆盖(否则门禁量的是网络回包不是喂进去的样本)。
## ─────────────────────────────────────────────────────────────
const _SB := preload("res://scripts/net/supabase.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _poll: Timer = null
var _injected := false          # ★有人喂过数据 ⇒ 这一屏不联网
var _fetch_left := 0.0          # 距下次重新拉(服务端每过一轮, 图上就该翻一面)
var _tip: Label = null
## E-B7 备战购物窗那一行。★与 `_tip` 分成**两个**标签：一个说「还能买多久」、
##   一个说「对手阵容拿没拿到」；挤进同一行会互相盖掉，而那两件事同时成立。
var _shop_row: Label = null
var _last_sig := ""

## 每 30 秒重拉一次 —— 服务端一轮 8 分钟, 30 秒的粒度足够让"翻面"看着是自动的。
const REFRESH_SEC := 30.0


func _start_feed() -> void:
	_tip = Label.new()
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", 15)
	_tip.add_theme_color_override("font_color", ACCENT)
	_tip.visible = false
	add_child(_tip)
	_shop_row = Label.new()
	_shop_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_row.add_theme_font_size_override("font_size", 15)
	_shop_row.add_theme_color_override("font_color", MINE)
	_shop_row.visible = false
	add_child(_shop_row)
	_poll = Timer.new()
	_poll.wait_time = 0.5
	_poll.timeout.connect(_on_poll)
	add_child(_poll)
	_poll.start()
	## ★★先画一次 —— 「还没有数据」也是一种状态, 得说话。
	##   不画的话: 空白屏 + 「回到我」停在默认的 (0,0) 压住返回箭头 + 页签后缀没同步。
	## ★★把 `match_opened` 接上 —— 在这之前它发了**没有任何人听**。
	##   只在自己联网这条路上接: 门禁喂数据那条路不该去打网络。
	match_opened.connect(_on_match_opened)
	_rebuild()
	_pull()


func _pull() -> void:
	_fetch_left = REFRESH_SEC
	_SB.fetch_finals_async(_P2C.week_anchor_utc(_clock()), -1)


# ─────────────────────────────────────────────────────────────
# E-B4 点开我的那一场 → 去要对手快照（2026-09-25）
#
# ★★在这之前 `match_opened` 这个信号**一个人都没听**，而 `fetch_opponent_async`
#   **一个调用者都没有** —— 两个「写了没人读」。接上才算做完。
#   (⚠ `tools/zero_caller_audit.py` **不扫 `scripts/net/`**，所以它不会替我发现。)
#
# ★★★只给「我自己的、当前轮的、对手已定的」那一场问：
#   服务端 `finals_scout` 是**每人每轮只给一次**，替别人点一下就把机会烧掉了。
#   判定抽成 `should_fetch_opponent()`（纯判定，门禁能穷举，不用起网络）。
# ─────────────────────────────────────────────────────────────
## 正在等哪一场的对手快照。`Vector2i(-1, -1)` = 没在等。
var _await_match := Vector2i(-1, -1)


func _on_match_opened(r: int, m: int) -> void:
	if not should_fetch_opponent(r, m):
		return
	var bk := int(cur().get("bucket", -1))
	if bk < 0:
		return                        # 桶号还没回来，问了服务端也认不出
	_SB.opponent_clear()
	_await_match = Vector2i(r, m)
	_SB.fetch_opponent_async(_P2C.week_anchor_utc(_clock()), bk, r, my_opponent_seed(r, m))


## 对手快照到了 ⇒ 开打。
## ★★这是 E-B6 的落点：在这之前，拿到快照也**没有任何人用它** ——
##   E-B4 把「读得回来」做通了，但「拿它打一场」还是空的。
## ★★★把这一局标成决赛场（`GameState.finals_match`），打完 `_settle_season()`
##   才知道要报给谁 —— 没有它，结果会按普通对局结算、**一个字都不会报上去**，
##   于是对阵图永远停在这一轮。
func _try_start_match() -> bool:
	if _await_match.x < 0 or not _SB.opponent_tried():
		return false
	var res: Dictionary = _SB.opponent_cached()
	if not bool(res.get("ok", false)):
		return false                  # 拿不到 ⇒ `_tip` 那边照 reason 说话，不开打
	var r := _await_match.x
	var m := _await_match.y
	var side := my_side(r, m)
	if side < 0:
		_await_match = Vector2i(-1, -1)
		return false
	var snap: Dictionary = res.get("snapshot", {})
	if snap.is_empty():
		_await_match = Vector2i(-1, -1)
		return false
	_await_match = Vector2i(-1, -1)
	## 与匹配屏同一套交接口径：对手快照 + 对手资料 → 战斗场自己读
	GameState.dual_ghost = snap.duplicate(true)
	GameState.dual_opponent = {
		"name": str(res.get("name", "对手")),
		"avatar": str((snap.get("leaders", []) as Array)[0]) if not (snap.get("leaders", []) as Array).is_empty() else "basic",
		"id": "#%d" % int(res.get("seed", -1)),
	}
	GameState.finals_match = {"bucket": int(cur().get("bucket", -1)),
		"round": r, "match": m, "side": side}
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")
	return true


## 备战购物窗那一行该说什么。`""` = 这一行根本不出现。
## ★★**纯函数**（喂两个数就能验），理由同 `finals_shop_open` 本身：
##   只写在屏幕里的话，门禁只量得到"此刻"那一格，窗外那一大段全是空检查。
## ★三种状态说的话完全不同 —— 混成一句「购物」等于没说：
##   · 开着：还剩多久（**倒计时是这一行的全部价值**，没有它玩家不知道该不该现在去）
##   · 关了：说清在等什么（不是"不能买"，而是"这一轮的备战结束了"）
##   · 没上线 / 没桶：不出现
static func shop_tip(shop_open: bool, left_sec: int, has_bucket: bool) -> String:
	if not has_bucket:
		return ""
	if shop_open:
		return "备战购物 · 还剩 %d:%02d" % [left_sec / 60, left_sec % 60]
	return "本轮备战已结束 · 等开打"


## 对手快照这一步该跟玩家说什么。★**纯函数**：喂一份 `opponent_cached()` 的产物
## 就能验，不用起网络。★每种 `reason` 说的话都不一样 —— 「这一轮你已经看过 3 号了」
## 和「你不在这个桶里」是两件完全不同的事，混成一句「取不到」等于没说。
static func opponent_tip(res: Dictionary, tried: bool) -> String:
	if not tried:
		return ""
	if bool(res.get("ok", false)):
		return "对手阵容已就位 · %s" % str(res.get("name", "对手"))
	match str(res.get("reason", "")):
		"already_asked":
			return "这一轮你已经看过 %d 号了 · 一轮只能看一个对手" % int(res.get("asked", -1))
		"wrong_round":
			return "这一轮已经翻篇了 · 刷新一下看看新的对阵"
		"not_in_bucket":
			return "你不在这一组里 · 只能看别人打"
		"empty_snapshot", "no_such_seed":
			return "对手没留下阵容 · 这一场算他弃权"
		"net", "bad_body":
			return "连不上服务器 · 过两秒再点一次"
	return "暂时看不到对手阵容 · 过两秒再点一次"


## ★轮询缓存而不是接回调: 回调在网络那一侧, 接过来就得处理"场景已经被切掉了"的情况。
##   轮询这边只读一个静态字典, 场景没了定时器也就没了。
func _on_poll() -> void:
	## ★★E-B6: 对手快照回来了就开打。放在轮询里而不是接回调 —— 理由同下面那段:
	##   回调在网络那一侧, 接过来就得自己处理"场景已经被切掉了"。
	##   `_try_start_match()` 自己会判"到底能不能开"; 开了就换场景, 这一拍不用再往下走。
	if _try_start_match():
		return
	## ★★E-B7 备战购物窗那一行。放在对手提示**之前**算 ——
	##   两者共用 `_tip`，而"拿不到对手阵容"是**当下要处理的事**，
	##   优先级高于"还能买多久"，所以下面那句有内容时会盖掉这一句。
	if _shop_row != null:
		var now_l := _clock()
		var st := shop_tip(_SB.finals_shop_open_now(now_l), _SB.finals_shop_left_now(now_l),
			int(cur().get("size", 0)) > 1)
		_shop_row.text = st
		_shop_row.visible = st != ""
		if st != "":
			var vs := get_viewport().get_visible_rect().size
			_shop_row.position = Vector2(0, vs.y - 156)
			_shop_row.size = Vector2(vs.x, 26)
	## 对手那边的结果(拿不到/被拒/连不上)要说人话 —— 每种 reason 说的不一样。
	if _tip != null:
		var tip := opponent_tip(_SB.opponent_cached(), _SB.opponent_tried())
		_tip.text = tip
		_tip.visible = tip != ""
		if tip != "":
			_tip.position = Vector2(0, get_viewport().get_visible_rect().size.y - 120)
			_tip.size = Vector2(get_viewport().get_visible_rect().size.x, 28)
	_fetch_left -= 0.5
	if _fetch_left <= 0.0:
		_pull()
	var v: Dictionary = _SB.finals_cached()
	## ★比一个「指纹」而不是逐字段比: 只比 size 会漏掉翻面, 只比 round 会漏掉
	##   **同一轮里陆续出结果**(一个桶里那几场不是同时结束的) ⇒ 半张图要等到下一轮才亮。
	var sig := "%d/%d/%d" % [int(v.get("size", 0)), int(v.get("round", 0)),
		(v.get("done", {}) as Dictionary).size()]
	## ★空了也要重画(比如服务端说「你没报名」) —— 只在"有数据且变了"时重画,
	##   就会把开屏那句「正在连线」永远留在屏幕上。
	if sig != _last_sig:
		_last_sig = sig
		_bucket = v.duplicate(true)
		_record_progress()             # ★权威结果到手 ⇒ 记进度 + 对头衔账(见那个函数的头注)
		_rebuild()
	_sync_tip()


## 顶上那行「下一轮 X 分 Y 秒后开」。★秒数来自**服务端的时间差**, 不看本机时钟绝对值。
func _sync_tip() -> void:
	if _tip == null:
		return
	var left: int = _SB.finals_left(_clock())
	if left < 0 or bool(_bucket.get("closed", false)):
		_tip.visible = false
		return
	_tip.visible = true
	_tip.text = "下一轮 %d:%02d 后开播" % [left / 60, left % 60]
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_tip.size.x = vp.x
	_tip.position = Vector2(0.0, 150.0)
