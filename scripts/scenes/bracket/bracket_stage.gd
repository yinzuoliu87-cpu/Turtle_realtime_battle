class_name BracketStage
extends RefCounted
## bracket_stage.gd —— 叠在对阵上的几场「过场」(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 B 行)
##
##   · 本轮名牌墙(⑭ · G4 · Fall Guys 2-5 / Trackmania 5-1): 本轮所有人的名牌一排 → 输家逐个盖红叉 → 晋级者亮起抬高 → 揭晓下一轮对阵
##   · 3 分钟备战屏(⑮ · G5 · Chess.com 3-4 / 金铲铲 W-6): 大倒计时 + 本轮进度 + 下一轮谁对谁与一句利害 + 一排在动的选手卡
##   · 全部组宫格(⑲ · G23 · 9-7): 每格 组号 / 正在播谁 / 比分 / 组冠军, 点哪格进哪组
##   · 开赛前大倒计时(⑫ · P12): 18:00 分组前 / 20:00 冠军杯赛前, 大字倒计时 + 已报名人数
##   · 即将开播那一格的说明卡(S 分身清单第 7 条): 只写「X 后开播」
## ★这些全不在 `_canvas` 里(③「画布里真按钮数 == 可点场次数」); 字一律不以「✓」开头(①的分母只数对阵卡)。
## ★过场里不判任何东西: 谁输谁赢 / 下一轮谁对谁 / 还剩几秒, 全由场景算好喂进来(`BracketMapScene.wall_data()` 等)。

const _H := preload("res://scripts/scenes/bracket/bracket_hero.gd")
const _C := preload("res://scripts/scenes/bracket/bracket_chrome.gd")

const WALL_SEC := 5.6          # 名牌墙整段时长(G4: 打叉 → 亮起 → 揭晓, 不放按钮; 点一下跳过)
const N_WALL := "NameWall"
const N_PREP := "PrepScreen"
const N_GRID := "GroupGrid"
const N_PRESHOW := "PreShow"
const N_UPCOMING := "UpcomingCard"

var s
var root: Control = null
var live_texts: Array = []
var _carousel: Control = null
var _carousel_w := 0.0
var _ticker: Control = null
var _ticker_w := 0.0
var _beat: Array = []          # 最后 10 秒跳一下的大倒计时
var _t := 0.0
## 名牌墙播过的轮次(组 + 周 + 翻面时刻 + 轮)。★静态: 看完回放回来不重播。
static var wall_played: Dictionary = {}
## 备战屏被玩家点「查看对阵图」收起的那一轮(同一轮不再自己弹出来)。
static var prep_dismissed: Dictionary = {}


func _init(scene) -> void:
	s = scene


## ★名牌墙不跟着重画走(它自己放完淡出自删): 轮询 / 回包一来就整屏重画, 原来会把放到一半的墙一起删掉
##   (录屏自查抓到: 进场 set_week + set_data 两次重画, 第二次把第一次弹出的墙删了)。换到别的组时由场景调 `drop_wall_unless`。
var wall: Control = null


func drop_wall_unless(bucket: int) -> void:
	if wall != null and is_instance_valid(wall) and int(wall.get_meta("bucket", -9)) != bucket:
		wall.queue_free()
		wall = null


func clear() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	live_texts.clear()
	_carousel = null
	_ticker = null
	_beat.clear()


func _ensure_root() -> Control:
	if root != null and is_instance_valid(root):
		return root
	root = Control.new()
	root.name = "HeroStage"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(root)
	s.move_child(root, s._canvas.get_index() + 1)
	return root


func tick(dt: float) -> void:
	_t += dt
	if _carousel != null and is_instance_valid(_carousel) and _carousel_w > 0.0:
		_carousel.position.x -= dt * 38.0
		if _carousel.position.x < -_carousel_w:
			_carousel.position.x += _carousel_w
	if _ticker != null and is_instance_valid(_ticker) and _ticker_w > 0.0:
		_ticker.position.x -= dt * 46.0
		if _ticker.position.x < -_ticker_w:
			_ticker.position.x += _ticker_w
	for b in _beat:
		if is_instance_valid(b):
			var lb := b as Control
			var left := int(lb.get_meta("left_fn", Callable()).call()) if lb.has_meta("left_fn") else 99
			var k := 1.0 + (0.08 * maxf(0.0, sin(_t * 6.0)) if left <= 10 else 0.0)
			lb.scale = Vector2(k, k)


func refresh_texts() -> void:
	for it in live_texts:
		if is_instance_valid(it[0]):
			(it[0] as Control).set("text", str((it[1] as Callable).call()))


# ═══════════════════════════════════════════════════════════════════
#  小工具
# ═══════════════════════════════════════════════════════════════════
func _box(p: Control, r: Rect2, col: Color) -> ColorRect:
	return _C._add_box(p, r, col)


func _lb(t: String, fs: int, col: Color, outline: bool = true) -> Label:
	return s._hero._label(t, fs, col, outline)


## 暖色牌子(与对阵卡同一套: 墨描边 + 青铜边 + 不透明底 + 上沿高光)
func _plate(p: Control, r: Rect2, edge: Color = _H.BRONZE, bg: Color = _H.PLATE) -> void:
	_box(p, r.grow(3.0), _H.INK)
	_box(p, r.grow(1.0), edge)
	_box(p, r, bg)
	_box(p, Rect2(r.position, Vector2(r.size.x, 2.0)), _H.BRONZE_HI)


## 一个头像(默认龟头像兜底, 不写首字)
func _avatar(p: Control, r: Rect2, c: Dictionary, dim: bool = false, gold: bool = false) -> void:
	s._hero._portrait(p, r, c, 0 if gold else -1, 0 if not dim else 1, gold)
	if dim:
		for k in p.get_children():
			if str(k.name) == "Portrait" and is_instance_valid(k):
				(k as CanvasItem).modulate = Color(0.55, 0.52, 0.55, 1.0)


# ═══════════════════════════════════════════════════════════════════
#  ⑫ 开赛前大倒计时
# ═══════════════════════════════════════════════════════════════════
## `d` = {"title", "end_ts"(服务端 unix, 0 = 不数), "sub"}; 返回大倒计时块的下沿(空态框接在它下面)。
func preshow(vp: Vector2, band: Dictionary, d: Dictionary) -> float:
	var rt := _ensure_root()
	var box := Control.new()
	box.name = N_PRESHOW
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_child(box)
	var top := float(band.get("top", 150.0)) - 24.0
	var w := clampf(vp.x * 0.56, 560.0, 760.0)
	var r := Rect2(Vector2((vp.x - w) * 0.5, top), Vector2(w, 196.0))
	_plate(box, r, _H.GOLD_DEEP)
	## 奖杯两侧各一枚(像素原图整数倍)
	if ResourceLoader.exists(_H.TEX_TROPHY):
		for k in [0, 1]:
			var tr := TextureRect.new()
			tr.texture = load(_H.TEX_TROPHY)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(96, 96)
			tr.position = Vector2(r.position.x + 24.0 if k == 0 else r.end.x - 120.0, r.position.y + 50.0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(tr)
	var tl := _lb(str(d.get("title", "")), 24, _H.GOLD)
	tl.name = "PreShowTitle"
	tl.position = r.position + Vector2(0, 16)
	tl.size = Vector2(w, 32)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tl)
	var end_ts := int(d.get("end_ts", 0))
	var big := _lb("", 44, _H.TXT)
	big.name = "PreShowCountdown"
	big.position = r.position + Vector2(0, 62)
	big.size = Vector2(w, 64)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(big)
	var fn := func() -> String:
		if end_ts <= 0:
			return str(d.get("big", ""))
		return str(s._info.big_countdown(end_ts - int(s.srv_now())))
	big.text = fn.call()
	live_texts.append([big, fn])
	var sl := _lb(str(d.get("sub", "")), 17, Color("#e9d6a8"))
	sl.name = "PreShowSub"
	sl.position = r.position + Vector2(0, 140)
	sl.size = Vector2(w, 40)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(sl)
	## 一图讲清一整晚(2-1): 小组赛 → 组冠军 → 冠军杯赛 → 冠军; 现在走到哪一站亮金
	var steps: Array = d.get("steps", [])
	if not steps.is_empty():
		var sy := r.end.y + 196.0
		var sw := minf(vp.x - 120.0, 860.0)
		var sx := (vp.x - sw) * 0.5
		var gapw := sw / float(steps.size())
		for i in range(steps.size()):
			var st: Dictionary = steps[i]
			var cxs := sx + gapw * (float(i) + 0.5)
			var on := bool(st.get("on", false))
			if i < steps.size() - 1:
				_box(box, Rect2(cxs + 14.0, sy + 11.0, gapw - 28.0, 3.0), _H.GOLD_DEEP if on else _H.BRONZE)
			_box(box, Rect2(cxs - 12.0, sy, 24.0, 24.0).grow(2.0), _H.INK)
			_box(box, Rect2(cxs - 12.0, sy, 24.0, 24.0), _H.GOLD if on else _H.BRONZE)
			_box(box, Rect2(cxs - 7.0, sy + 5.0, 14.0, 14.0), _H.PLATE if not on else Color("#fff0b8"))
			var t1 := _lb(str(st.get("time", "")), 15, _H.GOLD if on else _H.TXT_DIM, true)
			t1.position = Vector2(cxs - gapw * 0.5, sy - 26.0)
			t1.size = Vector2(gapw, 22.0)
			t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(t1)
			var t2 := _lb(str(st.get("name", "")), 17, _H.TXT if on else _H.TXT_DIM, true)
			t2.position = Vector2(cxs - gapw * 0.5, sy + 30.0)
			t2.size = Vector2(gapw, 24.0)
			t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(t2)
	if end_ts > 0:
		box.modulate.a = 0.0
		var tw := box.create_tween()
		tw.tween_property(box, "modulate:a", 1.0, 0.3)
	return r.end.y + 18.0


# ═══════════════════════════════════════════════════════════════════
#  ⑭ 本轮名牌墙
# ═══════════════════════════════════════════════════════════════════
## `d` = {"key", "title", "seats": [{"c": 选手, "lost": bool, "bye": bool, "mine": bool}], "next_title", "pairs": [[a, b], ...]}
func name_wall(vp: Vector2, band: Dictionary, d: Dictionary) -> void:
	var rt := _ensure_root()
	var top := float(band.get("top", 150.0)) - 30.0
	var bottom := float(band.get("bottom", vp.y - 100.0))
	var area := Rect2(Vector2(0, top), Vector2(vp.x, bottom - top))
	var wall := Control.new()
	wall.name = N_WALL
	wall.mouse_filter = Control.MOUSE_FILTER_STOP
	wall.position = area.position
	wall.size = area.size
	wall.set_meta("bucket", int(s.cur().get("bucket", -1)))
	s.add_child(wall)
	s.move_child(wall, rt.get_index() + 1)       # 在备战屏上面(墙放完淡出, 露出备战屏), 不挂在会被重画清掉的 HeroStage 下
	self.wall = wall
	var dim := _box(wall, Rect2(Vector2.ZERO, area.size), Color(0.03, 0.02, 0.03, 0.95))
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rib_w := clampf(vp.x * 0.30, 320.0, 440.0)
	s._hero._ribbon(wall, Rect2(Vector2((vp.x - rib_w) * 0.5, 8.0), Vector2(rib_w, 48.0)), str(d.get("title", "")), 22, true)
	var seats: Array = d.get("seats", [])
	var k := seats.size()
	var gap := 10.0
	var pw := clampf((vp.x - 60.0 - float(k - 1) * gap) / float(maxi(1, k)), 96.0, 168.0)
	var ph := clampf(area.size.y * 0.46, 150.0, 196.0)
	var x0 := (vp.x - (pw * float(k) + gap * float(k - 1))) * 0.5
	var y0 := 72.0
	var t_stamp := 0.9
	var lost_i := 0
	for i in range(k):
		var it: Dictionary = seats[i]
		var plate := Control.new()
		plate.name = "WallPlate"
		plate.set_meta("bk", "wall_plate")
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.position = Vector2(x0 + float(i) * (pw + gap), y0)
		plate.size = Vector2(pw, ph)
		wall.add_child(plate)
		var mine := bool(it.get("mine", false))
		_plate(plate, Rect2(Vector2.ZERO, plate.size), _H.GOLD if mine else _H.BRONZE)
		var av := clampf(pw - 36.0, 56.0, 96.0)
		var arc := Rect2(Vector2((pw - av) * 0.5, 16.0), Vector2(av, av))
		var c: Dictionary = it.get("c", {})
		s._hero._portrait(plate, arc, c, -1, 0, false)
		var nl := _lb(s._fit_name(str(c.get("name", "")), pw - 12.0, false, 16.0), 16, _H.GOLD if mine else _H.TXT)
		nl.name = "WallName"
		nl.position = Vector2(4, arc.end.y + 8.0)
		nl.size = Vector2(pw - 8, 24)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plate.add_child(nl)
		var og := str(it.get("origin", ""))
		if og != "":
			var ol := _lb(og, 12, _H.TXT_DIM, false)
			ol.position = Vector2(4, arc.end.y + 32.0)
			ol.size = Vector2(pw - 8, 18)
			ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plate.add_child(ol)
		## 入场: 从下往上依次落位
		plate.modulate.a = 0.0
		plate.position.y += 24.0
		var tw := plate.create_tween()
		tw.tween_interval(0.05 + float(i) * 0.06)
		tw.set_parallel(true)
		tw.tween_property(plate, "modulate:a", 1.0, 0.18)
		tw.tween_property(plate, "position:y", y0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.set_parallel(false)
		if bool(it.get("lost", false)):
			## 输家: 依次盖红叉 + 整块压暗(压暗那层垫在红叉下面)
			var shade := _box(plate, Rect2(Vector2.ZERO, plate.size), Color(0.02, 0.01, 0.02, 0.0))
			var xm: Control = s._hero._x_mark(plate, arc.grow(6.0))
			xm.pivot_offset = xm.size * 0.5
			xm.scale = Vector2(2.4, 2.4)
			xm.modulate.a = 0.0
			var at := t_stamp + float(lost_i) * 0.28
			lost_i += 1
			var tx := xm.create_tween()
			tx.tween_interval(at)
			tx.set_parallel(true)
			tx.tween_property(xm, "modulate:a", 1.0, 0.08)
			tx.tween_property(xm, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			var td := plate.create_tween()
			td.tween_interval(at + 0.12)
			td.tween_property(shade, "color:a", 0.5, 0.2)
			var out := _lb("出局", 14, Color.WHITE, true)
			out.position = Vector2(0, ph - 26.0)
			out.size = Vector2(pw, 20)
			out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			out.modulate.a = 0.0
			plate.add_child(out)
			var to := out.create_tween()
			to.tween_interval(at + 0.1)
			to.tween_property(out, "modulate:a", 1.0, 0.15)
		else:
			## 晋级者: 打叉之后亮起、抬高(G4「晋级者亮起」)
			var glow := Control.new()
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glow.modulate.a = 0.0
			plate.add_child(glow)
			plate.move_child(glow, 0)
			_box(glow, Rect2(Vector2(-7, -7), plate.size + Vector2(14, 14)), Color(1.0, 0.78, 0.3, 0.55))
			var tag := _lb("轮空晋级" if bool(it.get("bye", false)) else "晋级", 14, Color("#2a1a06"), false)
			var trc := Rect2(Vector2(pw * 0.5 - 40.0, ph - 28.0), Vector2(80.0, 22.0))
			var tagbox := Control.new()
			tagbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tagbox.modulate.a = 0.0
			plate.add_child(tagbox)
			_box(tagbox, trc, _H.GOLD)
			tag.position = trc.position
			tag.size = trc.size
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tagbox.add_child(tag)
			var rise := t_stamp + 0.28 * float(_count_lost(seats)) + 0.35
			var tg := plate.create_tween()
			tg.tween_interval(rise)
			tg.set_parallel(true)
			tg.tween_property(plate, "position:y", y0 - 14.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tg.tween_property(glow, "modulate:a", 1.0, 0.25)
			tg.tween_property(tagbox, "modulate:a", 1.0, 0.2)
	## 揭晓下一轮对阵
	var reveal_at := t_stamp + 0.28 * float(_count_lost(seats)) + 1.0
	var nx := Control.new()
	nx.name = "WallNext"
	nx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nx.modulate.a = 0.0
	wall.add_child(nx)
	var ny := y0 + ph + 22.0
	var nt := _lb("下一轮 · %s" % str(d.get("next_title", "")), 22, _H.GOLD)
	nt.position = Vector2(0, ny)
	nt.size = Vector2(vp.x, 30)
	nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nx.add_child(nt)
	var pairs: Array = d.get("pairs", [])
	var lines := PackedStringArray()
	for p in pairs:
		lines.append("%s  对  %s" % [str((p[0] as Dictionary).get("name", "")), str((p[1] as Dictionary).get("name", ""))])
	var pl := _lb("    ".join(lines), 20, _H.TXT)
	pl.name = "WallPairs"
	pl.position = Vector2(0, ny + 34.0)
	pl.size = Vector2(vp.x, 30)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nx.add_child(pl)
	nx.pivot_offset = Vector2(vp.x * 0.5, ny + 30.0)
	nx.scale = Vector2(0.9, 0.9)
	var tn := nx.create_tween()
	tn.tween_interval(reveal_at)
	tn.set_parallel(true)
	tn.tween_property(nx, "modulate:a", 1.0, 0.2)
	tn.tween_property(nx, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	## 收尾: 整块淡出(点一下 = 直接淡出)
	var tf := wall.create_tween()
	tf.tween_interval(WALL_SEC)
	tf.tween_property(wall, "modulate:a", 0.0, 0.4)
	tf.tween_callback(wall.queue_free)
	wall.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and is_instance_valid(wall):
			wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tq := wall.create_tween()
			tq.tween_property(wall, "modulate:a", 0.0, 0.25)
			tq.tween_callback(wall.queue_free))


func _count_lost(seats: Array) -> int:
	var k := 0
	for it in seats:
		if bool((it as Dictionary).get("lost", false)):
			k += 1
	return k


# ═══════════════════════════════════════════════════════════════════
#  ⑮ 3 分钟备战屏
# ═══════════════════════════════════════════════════════════════════
## `d` = {"key", "title", "end_ts", "progress", "pairs": [[a, b, mine]], "stake", "me_line", "players": [选手...]}
func prep(vp: Vector2, band: Dictionary, d: Dictionary) -> void:
	var rt := _ensure_root()
	var top := float(band.get("top", 150.0)) - 30.0
	var bottom := float(band.get("bottom", vp.y - 100.0))
	var w := clampf(vp.x * 0.62, 700.0, 900.0)
	w = minf(w, vp.x - 40.0)
	var r := Rect2(Vector2((vp.x - w) * 0.5, top), Vector2(w, bottom - top))
	var pnl := Control.new()
	pnl.name = N_PREP
	pnl.mouse_filter = Control.MOUSE_FILTER_STOP
	pnl.position = r.position
	pnl.size = r.size
	rt.add_child(pnl)
	_plate(pnl, Rect2(Vector2.ZERO, r.size), _H.GOLD_DEEP, Color("#1b1519"))
	var tl := _lb(str(d.get("title", "")), 22, _H.GOLD)
	tl.name = "PrepTitle"
	tl.position = Vector2(0, 8)
	tl.size = Vector2(w, 30)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pnl.add_child(tl)
	## 大倒计时(最后 10 秒跳动)
	var end_ts := int(d.get("end_ts", 0))
	var big := _lb("", 46, _H.TXT)
	big.name = "PrepCountdown"
	big.position = Vector2(0, 38)
	big.size = Vector2(w, 60)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.pivot_offset = Vector2(w * 0.5, 30)
	pnl.add_child(big)
	var left_fn := func() -> int: return end_ts - int(s.srv_now())
	var fn := func() -> String:
		var lf: int = left_fn.call()
		return ("%s后开播" % s.countdown_text(lf)) if lf > 0 else "即将开播…"
	big.text = fn.call()
	big.set_meta("left_fn", left_fn)
	live_texts.append([big, fn])
	_beat.append(big)
	var pg := _lb(str(d.get("progress", "")), 16, _H.TXT_DIM, false)
	pg.position = Vector2(0, 98)
	pg.size = Vector2(w, 22)
	pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pnl.add_child(pg)
	## 下一轮对阵(我那一场金边)
	var pairs: Array = d.get("pairs", [])
	var py := 128.0
	var row_h := clampf((r.size.y - 128.0 - 150.0) / float(maxi(1, pairs.size())), 46.0, 104.0)
	for p in pairs:
		var a: Dictionary = p[0]
		var b: Dictionary = p[1]
		var mine := bool(p[2]) if (p as Array).size() > 2 else false
		var rr := Rect2(Vector2(w * 0.12, py), Vector2(w * 0.76, row_h - 8.0))
		_box(pnl, rr.grow(1.0), _H.GOLD if mine else _H.BRONZE)
		_box(pnl, rr, Color("#2a2129"))
		var av := clampf(rr.size.y - 12.0, 30.0, 76.0)
		_avatar(pnl, Rect2(Vector2(rr.position.x + 8.0, rr.position.y + (rr.size.y - av) * 0.5), Vector2(av, av)), a)
		_avatar(pnl, Rect2(Vector2(rr.end.x - 8.0 - av, rr.position.y + (rr.size.y - av) * 0.5), Vector2(av, av)), b)
		var half := rr.size.x * 0.5 - av - 46.0
		var an := _lb(s._fit_name(str(a.get("name", "")), half, false, 19.0), 19, _H.GOLD if bool(a.get("_me", false)) else _H.TXT)
		an.position = Vector2(rr.position.x + av + 18.0, rr.position.y)
		an.size = Vector2(half, rr.size.y)
		an.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pnl.add_child(an)
		var bn := _lb(s._fit_name(str(b.get("name", "")), half, false, 19.0), 19, _H.GOLD if bool(b.get("_me", false)) else _H.TXT)
		bn.position = Vector2(rr.get_center().x + 36.0, rr.position.y)
		bn.size = Vector2(half, rr.size.y)
		bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pnl.add_child(bn)
		var vs := _lb("VS", 24, _H.GOLD)
		vs.position = Vector2(rr.get_center().x - 30.0, rr.position.y)
		vs.size = Vector2(60, rr.size.y)
		vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pnl.add_child(vs)
		py += row_h
	var stake := _lb(str(d.get("stake", "")), 17, Color("#e9d6a8"))
	stake.name = "PrepStake"
	stake.position = Vector2(0, py + 2.0)
	stake.size = Vector2(w, 24)
	stake.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pnl.add_child(stake)
	var ml := str(d.get("me_line", ""))
	if ml != "":
		var mll := _lb(ml, 14, _H.TXT_DIM, false)
		mll.position = Vector2(0, py + 26.0)
		mll.size = Vector2(w, 20)
		mll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pnl.add_child(mll)
	## 一排在动的选手卡(G5「一样在动的东西」): 本轮还在场的人, 从右往左慢慢走
	var players: Array = d.get("players", [])
	var strip_h := 64.0
	var strip := Control.new()
	strip.name = "PrepCarousel"
	strip.clip_contents = true
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(14.0, r.size.y - strip_h - 12.0)
	strip.size = Vector2(w - 28.0 - 170.0, strip_h)
	pnl.add_child(strip)
	if not players.is_empty():
		var reel := Control.new()
		reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(reel)
		var cw := 176.0
		var reps := maxi(2, int(ceil(strip.size.x / (cw * float(players.size())))) + 1)
		var x := 0.0
		for _rep in range(reps):
			for pc in players:
				var card := Control.new()
				card.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.position = Vector2(x, 4)
				card.size = Vector2(cw - 10.0, strip_h - 8.0)
				reel.add_child(card)
				_box(card, Rect2(Vector2.ZERO, card.size), Color("#2a2129"))
				_box(card, Rect2(Vector2.ZERO, Vector2(card.size.x, 2.0)), _H.BRONZE_HI)
				var av2 := card.size.y - 10.0
				_avatar(card, Rect2(Vector2(5, 5), Vector2(av2, av2)), pc)
				var cn := _lb(s._fit_name(str((pc as Dictionary).get("name", "")), card.size.x - av2 - 18.0, false, 15.0), 15, _H.TXT)
				cn.position = Vector2(av2 + 12.0, 4)
				cn.size = Vector2(card.size.x - av2 - 16.0, 26)
				card.add_child(cn)
				var og := _lb(str((pc as Dictionary).get("_origin", "")), 12, _H.TXT_DIM, false)
				og.position = Vector2(av2 + 12.0, 28)
				og.size = Vector2(card.size.x - av2 - 16.0, 18)
				card.add_child(og)
				x += cw
		_carousel = reel
		_carousel_w = cw * float(players.size())
	## 收起 ⇒ 看对阵图(这一轮不再自己弹)
	var bt := Button.new()
	bt.name = "PrepHide"
	bt.text = "查看对阵图"
	bt.focus_mode = Control.FOCUS_NONE
	bt.custom_minimum_size = Vector2(156, 81)
	bt.size = bt.custom_minimum_size
	bt.position = Vector2(w - 168.0, r.size.y - 81.0 - 6.0)
	bt.add_theme_font_size_override("font_size", 18)
	UISkin.card_button(bt)
	var key := str(d.get("key", ""))
	bt.pressed.connect(func():
		prep_dismissed[key] = true
		if is_instance_valid(pnl):
			pnl.queue_free())
	pnl.add_child(bt)
	pnl.modulate.a = 0.0
	var tw := pnl.create_tween()
	tw.tween_property(pnl, "modulate:a", 1.0, 0.25)


# ═══════════════════════════════════════════════════════════════════
#  ⑲ 全部组宫格
# ═══════════════════════════════════════════════════════════════════
## `cells` = [{"bucket", "title", "state"(live/prep/done/wait), "chip", "a", "b", "score": [x, y], "line", "mine"}]
func grid(vp: Vector2, band: Dictionary, cells: Array) -> void:
	var rt := _ensure_root()
	var top := float(band.get("top", 150.0)) - 24.0
	var bottom := float(band.get("bottom", vp.y - 100.0))
	var k := cells.size()
	var cols := 3 if k > 4 else 2
	if k > 6:
		cols = 4
	var rows := int(ceil(float(k) / float(cols)))
	var gap := 16.0
	var sm: Vector4 = SafeArea.margins(vp, 0.0)
	var aw := vp.x - 40.0 - sm.x - sm.z
	var cw := minf(380.0, (aw - gap * float(cols - 1)) / float(cols))
	var ch := clampf((bottom + 60.0 - top - gap * float(rows - 1)) / float(maxi(1, rows)), 104.0, 210.0)
	var x0 := (vp.x - (cw * float(cols) + gap * float(cols - 1))) * 0.5
	## 高屏(iPad 4:3 ⇒ 可见区 1280×960)格子封顶后下面会空一大截 ⇒ 整块在可用区里竖向居中
	top += maxf(0.0, (bottom + 60.0 - top - (ch * float(rows) + gap * float(rows - 1))) * 0.5)
	var gr := Control.new()
	gr.name = N_GRID
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_child(gr)
	for i in range(k):
		var c: Dictionary = cells[i]
		var rc := Rect2(Vector2(x0 + float(i % cols) * (cw + gap), top + float(i / cols) * (ch + gap)), Vector2(cw, ch))
		var bt := Button.new()
		bt.name = "GridCell"
		bt.set_meta("bk", "grid_cell")
		bt.flat = true
		bt.focus_mode = Control.FOCUS_NONE
		for sk in ["normal", "hover", "pressed", "focus", "disabled"]:
			bt.add_theme_stylebox_override(sk, StyleBoxEmpty.new())
		bt.position = rc.position
		bt.size = rc.size
		bt.custom_minimum_size = rc.size
		var bk = c.get("bucket", -1)
		bt.pressed.connect(func(): s.pick_chip(bk))
		gr.add_child(bt)
		var vis := Control.new()
		vis.show_behind_parent = true
		vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vis.size = rc.size
		bt.add_child(vis)
		var st := str(c.get("state", "wait"))
		var edge := _H.BRONZE
		if st == "live":
			edge = _H.LIVE
		if bool(c.get("mine", false)):
			edge = _H.GOLD
		_plate(vis, Rect2(Vector2.ZERO, rc.size), edge)
		var head_col := _H.LIVE_DEEP if st == "live" else _H.PLATE_HEAD
		_box(vis, Rect2(3, 3, cw - 6, 28), head_col)
		var tl := _lb(str(c.get("title", "")), 17, _H.GOLD if bool(c.get("mine", false)) else _H.TXT)
		tl.position = Vector2(10, 3)
		tl.size = Vector2(cw * 0.5, 28)
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vis.add_child(tl)
		var chip := str(c.get("chip", ""))
		var ccol := _H.LIVE if st == "live" else (_H.AMBER if st == "prep" else (_H.GOLD_DEEP if st == "done" else Color("#4a3e36")))
		var chw := 84.0
		_box(vis, Rect2(cw - chw - 8, 7, chw, 20), ccol)
		var cl := _lb(chip, 13, Color.WHITE if st == "live" else Color("#1d1208"), false)
		cl.name = "GridChip"
		cl.set_meta("bk", "grid_chip")
		cl.position = Vector2(cw - chw - 8, 6)
		cl.size = Vector2(chw, 22)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vis.add_child(cl)
		if st == "live":
			var lamp := _box(vis, Rect2(cw - chw - 2, 13, 7, 7), Color.WHITE)
			s._chrome._blink.append(lamp)
		## 正文: 两个头像 + 名字(+ 比分); 收盘 = 组冠军一人
		var body := Rect2(Vector2(10, 38), Vector2(cw - 20, ch - 46))
		var a: Dictionary = c.get("a", {})
		var b: Dictionary = c.get("b", {})
		var av := clampf(body.size.y - 30.0, 34.0, 64.0)
		if st == "done" and not a.is_empty():
			_avatar(vis, Rect2(Vector2(body.position.x + 6, body.position.y + 2), Vector2(av, av)), a, false, true)
			var nl := _lb(s._fit_name(str(a.get("name", "")), body.size.x - av - 24.0, false, 19.0), 19, _H.GOLD)
			nl.position = Vector2(body.position.x + av + 18, body.position.y + 2)
			nl.size = Vector2(body.size.x - av - 24, av * 0.55)
			nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			vis.add_child(nl)
			var sl := _lb("组冠军 · 晋级%s" % s._P2C.STAGE_CUP, 13, _H.TXT_DIM, false)
			sl.position = Vector2(body.position.x + av + 18, body.position.y + 2 + av * 0.55)
			sl.size = Vector2(body.size.x - av - 24, av * 0.45)
			vis.add_child(sl)
		elif not a.is_empty() and not b.is_empty():
			_avatar(vis, Rect2(Vector2(body.position.x + 4, body.position.y + 2), Vector2(av, av)), a)
			_avatar(vis, Rect2(Vector2(body.end.x - 4 - av, body.position.y + 2), Vector2(av, av)), b)
			var vs := _lb("VS", 20, _H.GOLD)
			var sc: Array = c.get("score", [])
			if sc.size() == 2:
				vs.text = "%d : %d" % [int(sc[0]), int(sc[1])]
			vs.position = Vector2(body.get_center().x - 40, body.position.y + 2)
			vs.size = Vector2(80, av)
			vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			vis.add_child(vs)
			var nw := body.size.x * 0.5 - 6.0
			var an := _lb(s._fit_name(str(a.get("name", "")), nw, false, 14.0), 14, _H.TXT, false)
			an.position = Vector2(body.position.x, body.position.y + av + 4)
			an.size = Vector2(nw, 20)
			vis.add_child(an)
			var bn := _lb(s._fit_name(str(b.get("name", "")), nw, false, 14.0), 14, _H.TXT, false)
			bn.position = Vector2(body.get_center().x + 6, body.position.y + av + 4)
			bn.size = Vector2(nw, 20)
			bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			vis.add_child(bn)
		var ln := str(c.get("line", ""))
		if ln != "":
			var ll := _lb(ln, 13, _H.TXT_DIM, false)
			ll.name = "GridLine"
			ll.position = Vector2(10, ch - 24)
			ll.size = Vector2(cw - 20, 20)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vis.add_child(ll)
		## 入场
		bt.modulate.a = 0.0
		var tw := bt.create_tween()
		tw.tween_interval(0.04 * float(i))
		tw.tween_property(bt, "modulate:a", 1.0, 0.18)


# ═══════════════════════════════════════════════════════════════════
#  ⑰ 收盘: 滚动全部参赛者(底部那一条)
# ═══════════════════════════════════════════════════════════════════
func ticker(vp: Vector2, y: float, w: float, text: String) -> void:
	var rt := _ensure_root()
	var clip := Control.new()
	clip.name = "EntrantTicker"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2((vp.x - w) * 0.5, y)
	clip.size = Vector2(w, 24)
	rt.add_child(clip)
	var reel := Control.new()
	reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(reel)
	var f: Font = s.get_theme_font("font", "Label")
	var tw := 600.0
	if f != null:
		tw = f.get_string_size(text + "　　　", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	for i in range(int(ceil(w / maxf(tw, 1.0))) + 2):
		var lb := _lb(text + "　　　", 15, Color("#e9d6a8"), true)
		lb.position = Vector2(float(i) * tw, 0)
		lb.size = Vector2(tw, 24)
		reel.add_child(lb)
	_ticker = reel
	_ticker_w = tw


# ═══════════════════════════════════════════════════════════════════
#  即将开播那一格的说明卡(S 分身清单第 7 条)
# ═══════════════════════════════════════════════════════════════════
func upcoming_card(vp: Vector2, title: String, a: Dictionary, b: Dictionary, left_fn: Callable) -> Control:
	var ov := ColorRect.new()
	ov.name = N_UPCOMING
	ov.color = Color(0, 0, 0, 0.62)
	ov.size = vp
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	s.add_child(ov)
	var w := 480.0
	var h := 250.0
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.position = (vp - Vector2(w, h)) * 0.5
	card.size = Vector2(w, h)
	ov.add_child(card)
	_plate(card, Rect2(Vector2.ZERO, card.size), _H.AMBER)
	var tl := _lb(title, 20, _H.AMBER)
	tl.position = Vector2(0, 12)
	tl.size = Vector2(w, 28)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(tl)
	var av := 56.0
	_avatar(card, Rect2(Vector2(40, 52), Vector2(av, av)), a)
	_avatar(card, Rect2(Vector2(w - 40 - av, 52), Vector2(av, av)), b)
	var pv := _lb("%s  对  %s" % [s._fit_name(str(a.get("name", "")), 130.0, false, 18.0),
		s._fit_name(str(b.get("name", "")), 130.0, false, 18.0)], 18, _H.TXT)
	pv.position = Vector2(100, 52)
	pv.size = Vector2(w - 200, av)
	pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(pv)
	var big := _lb("", 30, _H.TXT)
	big.name = "UpcomingCountdown"
	big.position = Vector2(0, 120)
	big.size = Vector2(w, 40)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(big)
	var fn := func() -> String:
		var lf := int(left_fn.call())
		return ("%s后开播" % s.countdown_text(lf)) if lf > 0 else "即将开播…"
	big.text = fn.call()
	live_texts.append([big, fn])
	var cl := Button.new()
	cl.name = "UpcomingClose"
	cl.text = "关闭"
	cl.focus_mode = Control.FOCUS_NONE
	cl.custom_minimum_size = Vector2(150, 81)
	cl.size = cl.custom_minimum_size
	cl.position = Vector2((w - 150) * 0.5, h - 81 - 4)
	cl.add_theme_font_size_override("font_size", 20)
	UISkin.card_button(cl)
	cl.pressed.connect(ov.queue_free)
	card.add_child(cl)
	ov.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			ov.queue_free())
	return ov


# ═══════════════════════════════════════════════════════════════════
#  ⑫ 空态整页: 顶上固定件 + 开赛前大倒计时(18:00 分组 / 20:00 冠军杯赛)+ 已报名人数 + 一整晚四站; 说明框接在下面
# ═══════════════════════════════════════════════════════════════════
func empty_preshow(vp0: Vector2, bw: float, bh: float) -> void:
	s._hero_on = true
	var band: Dictionary = s._chrome.build(vp0, false)
	_restyle_empty_box()
	var d := {}
	var kind := str(s._empty_kind())
	var cup_ts := int(s._cup_start_ts())
	if kind == str(s.EK_NOT_SEATED):
		var seat_ts: int = int(s._P2C.finals_seat_ts(int(s.feed_week())))
		var en := int(s._feed_view().get("entered", 0))
		d = {"title": "%s · %s 开赛" % [s._P2C.STAGE_GROUP, s._P2C.local_hhmm(seat_ts)], "end_ts": seat_ts,
			"sub": ("已报名 %d 人 · " % en if en > 0 else "") + "分组单败 · 组冠军晋级%s（%s）" % [s._P2C.STAGE_CUP,
				s._P2C.local_hhmm(cup_ts)], "steps": night_steps(0)}
	elif kind == str(s.EK_FINALS_SOON) or kind == str(s.EK_GROUP_SOLO):
		d = {"title": "%s · %s 开赛" % [s._P2C.STAGE_CUP, s._P2C.local_hhmm(cup_ts)], "end_ts": cup_ts,
			"sub": "组冠军晋级 · 单败淘汰 · 一场接一场开播", "steps": night_steps(2)}
	var y: float = float(band["top"]) - 10.0
	if not d.is_empty():
		y = preshow(vp0, band, d)
	y = minf(y, vp0.y - bh - 16.0)
	s._empty_box.position = Vector2((vp0.x - bw) * 0.5, y)
	s._refresh_lines()


## 一整晚四站(2-1): 走到第 `at` 站(0 起)亮金。
func night_steps(at: int) -> Array:
	var seat_ts: int = int(s._P2C.finals_seat_ts(int(s.feed_week())))
	var names := [["分组开赛", s._P2C.local_hhmm(seat_ts)], ["小组赛", "依次开播"],
		[s._P2C.STAGE_CUP, s._P2C.local_hhmm(int(s._cup_start_ts()))], ["冠军诞生", "收盘"]]
	var out: Array = []
	for i in range(names.size()):
		out.append({"name": names[i][0], "time": names[i][1], "on": i <= at})
	return out


## 说明框换成这一屏的暖色牌子(不透明底 + 青铜边 + 直角; 不是金属框)。
func _restyle_empty_box() -> void:
	if s._empty_box == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = _H.PLATE
	sb.border_color = _H.BRONZE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	(s._empty_box as PanelContainer).add_theme_stylebox_override("panel", sb)
	if s._empty_lb != null:
		(s._empty_lb as Label).add_theme_color_override("font_color", _H.TXT)
