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

var _bucket: Dictionary = {}           # 上午: 我自己那个桶
var _finals: Dictionary = {}           # 晚上: 桶冠军的签表(上午是空的)
var _view: String = _L.VIEW_BUCKET     # 现在看的是哪一张
var _now_override := 0                 # ★只给门禁喂已知时刻; 产品不传
var _tabs: HBoxContainer = null
var _empty_lb: Label = null
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
	for pair in [[_L.VIEW_BUCKET, "我的桶"], [_L.VIEW_FINALS, "冠军赛"]]:
		var b := Button.new()
		b.text = str(pair[1])
		b.custom_minimum_size = Vector2(132, 81)    # 触控下限 81px(=44pt)
		var v: String = str(pair[0])
		b.pressed.connect(func(): set_view(v))
		_tabs.add_child(b)

	## 签表还没形成时说人话的那一行(不是画一张空图)
	_empty_lb = Label.new()
	_empty_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lb.add_theme_font_size_override("font_size", 19)
	_empty_lb.add_theme_color_override("font_color", DIM)
	_empty_lb.visible = false
	add_child(_empty_lb)

	## ★「回到我」钉在右下角, **不跟着画布走** —— 拖多远它都在。
	##   触控下限 81px(= 44pt), 与全项目同一条线。
	_home_btn = Button.new()
	_home_btn.text = "回到我"
	_home_btn.custom_minimum_size = Vector2(140, 81)
	_home_btn.pressed.connect(func(): _center_on_me())
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
	## ★头衔在 `sync_titles()` 里发(与满配额/进决赛日同一个入口) —— 这里不自己发。
	##   `sync_titles` 自带按 `{id, week}` 去重, 每次 feed 都调一遍是幂等的。
	var got: int = GameState.sync_titles()
	if changed or got > 0:
		GameState.save()


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
			_empty_lb.position = Vector2(0, vp0.y * 0.5 - 20.0)
			_empty_lb.size = Vector2(vp0.x, 40.0)
			_empty_lb.visible = true
		if _home_btn != null:
			_home_btn.visible = false
		return
	if _empty_lb != null:
		_empty_lb.visible = false
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

	var total := _B.rounds_for(n)
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			_canvas.add_child(_make_node(r, m))
	_make_links(n, total)
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
## ★★用词仍然是「开播」，而且**带倒计时** —— 「20:00 开播」比「敬请期待」有用得多。
func _empty_text() -> String:
	## ★自己联网取数时: **还没问到回音**跟**问到了但我没桶**要分开说。
	##   混成一句的话, 网络慢的人会以为自己没进决赛日。
	if not _injected and not _SB.finals_tried():
		return "正在连线 · 取本周的桶"
	## ★★「有资格但人不够」与「没资格」说的必须是两句话(2026-09-25)。
	##   `finals_seat` 对 1 个人故意不建桶(一人一桶 = 没有对手的冠军, 那不是比赛),
	##   而那个人**确实周六 4 胜晋级了** —— 底下那句「晋级才进得来」对他是假话,
	##   他会以为自己的胜场没算。10 个人规模下晋级率约 34% ⇒ 只 0~1 人晋级约 10%,
	##   这不是假想的边角。
	var _fv: Dictionary = _SB.finals_cached() if not _injected else _bucket
	if str(_fv.get("reason", "")) == "too_few":
		var ent := int(_fv.get("entered", 0))
		return "本周只有 %d 人晋级 · 人太少没开起来, 你的晋级算数, 下周再来" % ent
	if _view == _L.VIEW_FINALS:
		## ★★★2026-09-26: 跨桶冠军赛是 **F 阶段**, 一行都没做 ——
		##   服务端只有 `finals_buckets/entrants/results/scout/pending`, 没有任何
		##   「桶冠军汇总」; 客户端 `_finals` 只有老调用点 `set_data()`(门禁用)会写,
		##   联网那条路 `_on_poll` **只写 `_bucket`**。
		##   ⇒ 原来这里一小时一小时地倒计时, 而那个东西永远不会来。
		##   ★★而且 10 人规模下全周只有**一个桶**(`finals_bucket_count(10) = 1`),
		##     「等各桶决出冠军」连概念都不存在 —— 那句话本身就是假的。
		##   ⚠ 客户端**算不出**全周有几个桶(`_bucket` 只装我自己那个桶的人数),
		##     所以不去猜"是不是只有一个桶", 只说**确定为真**的那一句。
		##   ⇒ 上线那天把 `CROSS_BUCKET_LIVE` 翻成 true, 倒计时那两句就回来
		##     (memory fb-branch-to-an-unbuilt-mode-is-a-backdoor: 让「没上线」是可读状态)。
		## ★写成 if/else 而**不是** `if not CROSS_BUCKET_LIVE: return …` ——
		##   后者会让下面的倒计时变成死代码, `tools/const_branch_audit.py` 当场判红
		##   (恒真常量分支 + return 吞掉同函数后续代码), 而那条审计器是对的:
		##   那几行在开关翻开之前一次都跑不到。审计器自己给的三条修法里,
		##   「刻意留的对照就不该以 return 收尾, 改成 if/else」正是这一处该走的。
		if CROSS_BUCKET_LIVE:
			var left: int = int(_L.finals_start_ts(_clock())) - _clock()
			if left > 0:
				return "冠军赛 %d 小时 %d 分后开播 · 先等各桶决出冠军" % [left / 3600, (left % 3600) / 60]
			return "冠军赛正在集结 · 等各桶决出冠军"
		else:
			return "跨桶冠军赛还没做 · 你那个桶的冠军就是本周冠军"
	return "本周没有你的桶 · 周六闯关赛晋级才进得来"


## 两个 Tab 的样子：当前那张高亮；**还没形成的那张不禁用**（要让人点进去看倒计时），
## 但名字后面缀一个「·未开」，免得点进去才发现是空的。
func _sync_tabs() -> void:
	if _tabs == null:
		return
	var kids := _tabs.get_children()
	if kids.size() < 2:
		return
	var names := [
		"我的桶" + ("" if int(_bucket.get("size", 0)) > 1 else " ·无"),
		"冠军赛" + ("" if int(_finals.get("size", 0)) > 1 else " ·未开"),
	]
	var views := [_L.VIEW_BUCKET, _L.VIEW_FINALS]
	for i in range(2):
		var b := kids[i] as Button
		b.text = str(names[i])
		b.add_theme_color_override("font_color",
			ACCENT if str(views[i]) == _view else DIM)


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
	return {"name": str(names[sd]) if sd < names.size() else "?", "seed": sd, "bye": false}


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


func _make_node(r: int, m: int) -> Control:
	var n := int(cur().get("size", 0))
	var rect: Rect2 = _L.node_rect(n, r, m)
	var st := match_state(r, m)
	var mine := is_my_match(r, m)
	var ws := winner_side(r, m)
	var sh: float = _L.slot_h()

	var holder := Control.new()
	holder.position = rect.position
	holder.custom_minimum_size = rect.size
	holder.size = rect.size

	## ★边框 + 实心底 —— 参考图的格子是圆角描边卡片, 没有边框就没有"格子感"。
	var frame := Panel.new()
	frame.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#141b28") if st != ST_BYE else Color("#0e1219")
	sb.border_color = MINE if mine else Color("#2c3950")
	sb.set_border_width_all(2 if mine else 1)
	sb.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)

	## 两行: 上侧 / 下侧
	for side in range(2):
		var c: Dictionary = competitor(r, m, side)
		var nm := str(c.get("name", "?"))
		var is_bye := bool(c.get("bye", false))
		var lb := Label.new()
		lb.position = Vector2(9, float(side) * sh)
		lb.size = Vector2(rect.size.x - 14, sh)
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
		lb.text = ("✓ " if (ws >= 0 and side == ws) else "") + nm
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lb)

	## 中间那道分隔线 —— 参考图两行之间有 VS，这里用一条细线 + 右侧状态标
	var sep := ColorRect.new()
	sep.color = Color("#2c3950")
	sep.position = Vector2(6, sh - 1)
	sep.size = Vector2(rect.size.x - 12, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sep)

	if st == ST_LIVE:
		var play := Label.new()
		play.text = "▶"
		play.position = Vector2(rect.size.x - 22, sh - 10)
		play.size = Vector2(20, 20)
		play.add_theme_font_size_override("font_size", 14)
		play.add_theme_color_override("font_color", MINE if mine else ACCENT)
		play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(play)

	if can_open(r, m):
		var btn := Button.new()
		btn.flat = true
		btn.size = rect.size
		btn.tooltip_text = "开播"
		btn.pressed.connect(func(): match_opened.emit(r, m))
		holder.add_child(btn)
	return holder


## ★★连接线 —— 参考图里那些直角线。没有它，整张图就是一堆飘着的条。
##   每一场画三段: 两个来源各自伸出一小截 → 一条竖线把它们并起来 → 一截进本场。
##   镜像布局里右半区方向相反, 所以 `dir` 决定往左还是往右伸。
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
			_line(minf(src_x, mid_x), ay, absf(mid_x - src_x), 2.0)
			_line(minf(src_x, mid_x), by, absf(mid_x - src_x), 2.0)
			_line(mid_x - 1.0, minf(ay, by), 2.0, absf(by - ay))
			_line(minf(mid_x, dst_x), my, absf(dst_x - mid_x), 2.0)


func _line(x: float, y: float, w: float, h: float) -> void:
	var seg := ColorRect.new()
	seg.color = LINE
	seg.position = Vector2(x, y - h * 0.5 if h <= 2.0 else y)
	seg.size = Vector2(maxf(w, 2.0), maxf(h, 2.0))
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(seg)


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
			return "你不在这个桶里 · 只能观战"
		"empty_snapshot", "no_such_seed":
			return "对手没留下阵容 · 这一场按无人应战处理"
		"net", "bad_body":
			return "连不上服务器 · 过两秒再点一次"
	return "暂时取不到对手阵容 · 过两秒再点一次"


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
