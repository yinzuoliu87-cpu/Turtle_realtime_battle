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

const TopBar := preload("res://scripts/util/top_bar.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")
const _L := preload("res://scripts/gamedata/bracket_layout.gd")

const BG := Color("#0a0e18")           # 黑底(Worlds 那张也是几乎纯黑)
const LINE := Color("#8fa3bd")         # 连接线: 细、冷、低调
const TXT := Color("#e8f0f6")
const ACCENT := Color("#4ff0d0")       # ★全屏**唯一**的强调色(Worlds 用的是青色)
const DIM := Color("#5a6a80")          # 轮空/空位
const MINE := Color("#ffd93d")         # 只有"我"用金色 —— 找自己是这屏的头等大事

var _bucket: Dictionary = {}
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
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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

	## ★「回到我」钉在右下角, **不跟着画布走** —— 拖多远它都在。
	##   触控下限 81px(= 44pt), 与全项目同一条线。
	_home_btn = Button.new()
	_home_btn.text = "回到我"
	_home_btn.custom_minimum_size = Vector2(140, 81)
	_home_btn.pressed.connect(func(): _center_on_me())
	add_child(_home_btn)

	if not _bucket.is_empty():
		_rebuild()


func set_bucket(d: Dictionary) -> void:
	_bucket = d.duplicate(true)
	if is_inside_tree():
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
	var n := int(_bucket.get("size", 0))
	var cur := int(_bucket.get("round", 1))
	var key := "%d-%d" % [r, m]
	if (_bucket.get("done", {}) as Dictionary).has(key):
		return ST_DONE
	if r == 1:
		var sa: int = m * 2
		var sb: int = m * 2 + 1
		if _B.is_bye_slot(sa, n) or _B.is_bye_slot(sb, n):
			return ST_BYE
	if r > cur:
		return ST_LOCKED
	return ST_LIVE


## 这一场能不能点开看。★轮空与未开打**不可点** —— 点了没东西放，
##   而"点了没反应"比"按钮是灰的"糟得多。
func can_open(r: int, m: int) -> bool:
	var st := match_state(r, m)
	return st == ST_LIVE or st == ST_DONE


## 这一场是不是**我的**。
func is_my_match(r: int, m: int) -> bool:
	var me := int(_bucket.get("me", -1))
	var n := int(_bucket.get("size", 0))
	if me < 0 or n <= 0:
		return false
	var seat := _B.seat_of_seed(me, n)
	if seat < 0:
		return false
	## 第 r 轮第 m 场覆盖的坑位区间
	var span: int = int(pow(2, r))
	return seat / span == m


## 我现在应该看哪一场（开图居中用）：**我还活着的那一场**；
## 出局了就定位到**淘汰我的那一场**（原稿那条"我止步在这"）。
func my_focus() -> Vector2i:
	var n := int(_bucket.get("size", 0))
	var cur := int(_bucket.get("round", 1))
	var total := _B.rounds_for(n)
	if int(_bucket.get("me", -1)) < 0:
		return Vector2i(mini(cur, maxi(1, total)), 0)      # 纯观众: 看当前轮第一场
	for r in range(1, total + 1):
		var cnt := _B.matches_in_round(n, r)
		for m in range(cnt):
			if not is_my_match(r, m):
				continue
			var st := match_state(r, m)
			if st == ST_LIVE or st == ST_LOCKED:
				return Vector2i(r, m)                      # 还在打: 就是这一场
			if st == ST_DONE and not _i_won(r, m):
				return Vector2i(r, m)                      # 输在这里
	return Vector2i(maxi(1, total), 0)


func _i_won(r: int, m: int) -> bool:
	var key := "%d-%d" % [r, m]
	var w = (_bucket.get("done", {}) as Dictionary).get(key, -1)
	if int(w) < 0:
		return false
	var n := int(_bucket.get("size", 0))
	var seat := _B.seat_of_seed(int(_bucket.get("me", -1)), n)
	var span: int = int(pow(2, r))
	## 赢家在这一场的哪一侧(0=上半 1=下半)
	var my_side: int = (seat % span) / (span / 2)
	return my_side == int(w)


## ─────────────────────────────────────────────────────────────
## 画
## ─────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in _canvas.get_children():
		c.queue_free()
	var n := int(_bucket.get("size", 0))
	if n <= 1:
		return
	var vp := get_viewport().get_visible_rect().size
	_scale = _L.fit_scale(n, vp)
	_can_pan = _L.needs_pan(n, vp)
	_canvas.scale = Vector2(_scale, _scale)

	var total := _B.rounds_for(n)
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
				ACCENT if r == int(_bucket.get("round", 1)) else DIM)
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(lb)


func _make_node(r: int, m: int) -> Control:
	var n := int(_bucket.get("size", 0))
	var rect: Rect2 = _L.node_rect(n, r, m)
	var st := match_state(r, m)
	var mine := is_my_match(r, m)

	var holder := Control.new()
	holder.position = rect.position
	holder.custom_minimum_size = rect.size
	holder.size = rect.size

	var bar := ColorRect.new()
	bar.size = rect.size
	bar.color = Color(1, 1, 1, 0.06) if st != ST_BYE else Color(1, 1, 1, 0.02)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bar)

	## ★只有"我"那一场给金色左条 —— 找自己是这屏的头等大事
	if mine:
		var mark := ColorRect.new()
		mark.color = MINE
		mark.size = Vector2(5, rect.size.y)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(mark)

	var lb := Label.new()
	lb.text = _node_text(r, m)
	lb.position = Vector2(12, 0)
	lb.size = Vector2(rect.size.x - 16, rect.size.y)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 15)
	lb.add_theme_color_override("font_color",
		MINE if mine else (DIM if st == ST_BYE else TXT))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lb)

	if can_open(r, m):
		var btn := Button.new()
		btn.flat = true
		btn.size = rect.size
		btn.tooltip_text = "开播"
		btn.pressed.connect(func(): match_opened.emit(r, m))
		holder.add_child(btn)
	return holder


## 节点上写什么字。★★**当前轮不写胜者** —— 客户端压根没有那个数据(见 ★②)。
func _node_text(r: int, m: int) -> String:
	var n := int(_bucket.get("size", 0))
	var names: Array = _bucket.get("names", [])
	var st := match_state(r, m)
	if st == ST_BYE:
		return "轮空"
	if st == ST_LOCKED:
		return "- VS -"                   # 还没决出谁进来(Worlds 那张也是这么留位的)
	if st == ST_LIVE:
		return "▶ 你的这一场" if is_my_match(r, m) else "▶ 待开播"
	## 已翻面: 报胜者
	var key := "%d-%d" % [r, m]
	var w := int((_bucket.get("done", {}) as Dictionary).get(key, 0))
	var span: int = int(pow(2, r))
	var seat: int = m * span + w * (span / 2)
	var sd := _B.seed_at_seat(seat, n)
	var who: String = str(names[sd]) if sd >= 0 and sd < names.size() else "?"
	return "%s 晋级" % who


func _center_on_me() -> void:
	var n := int(_bucket.get("size", 0))
	if n <= 1:
		return
	var f := my_focus()
	var vp := get_viewport().get_visible_rect().size
	_pan = _L.center_offset_on(n, f.x, f.y, vp, _scale)
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
