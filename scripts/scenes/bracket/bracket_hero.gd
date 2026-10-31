class_name BracketHero
extends RefCounted
## bracket_hero.gd —— 周日对阵图的「对阵本体」(画布那一层 · 2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md §4 B 行)
##
## 用户 10-31:「检查每个地方的样式美术等等，是否是商业游戏的标准，不是就去改，这样显示8强框图是否合理」
##   「准备统一套用到对阵图上？不行啊，得重新弄」「你学习商业游戏」。逐条依据见 docs/plans/ref/20261031-周日赛事参考/学到的.md。
##
## 这一层只画**对阵本体**(画布 `_canvas` 里的东西): 列标题 / 连线 / 对阵卡 / 正中冠军位(奖杯 · 组冠军 → 冠军杯 · 收盘领奖台)。
## 屏幕上的固定件(标题 / 处境句 / 组页签 / 我这一路 / 下一场 / 主按钮)在 `bracket_chrome.gd`,
## 叠在对阵上的过场(名牌墙 / 备战屏 / 全部组宫格 / 开赛前倒计时)在 `bracket_stage.gd`。
##
## ★版式(对标笔记 C01 / 1-5 / 9-9): 左右对称往正中收, 冠军位在正中; 8 签首轮每侧 2 场。
## ★一场 = 一张卡, 四态靠**形态**分(④): 等待中(灰边、问号头像)/ 开播中(红边呼吸 + 「开播」签)/
##   已播(比分 + ✓ + 胜章, 输方压暗 + 红叉)/ 轮空(半高小卡, 只坐一人)。即将开播(一场接一场)= 琥珀色签 + 倒计时。
## ★不判胜负: 谁赢 / 开没开播 / 能不能点 一律调场景自己的判定(competitor / match_state / winner_side / can_open …)。
## ★门禁认的东西照留: 胜者名字以「✓」开头(①的分母)、能点的格子恰好一颗 NodeBtn(③)、开播签叫 PremiereTag 且每场开播一枚、
##   比分叫 Score0 / Score1、能点的格子有 PlayMark、我要开打的那场有 PlayTag、头像节点带 meta「Portrait」。
## ★画布里除了 NodeBtn 不放任何按钮(③「屏上真按钮数 == 可点场次数」): 即将开播那一格的说明卡由一颗**不叫 NodeBtn、
##   不带 rm** 的透明热区弹出(S 分身清单第 7 条)。

const _B := preload("res://scripts/gamedata/bracket.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DL_SCORE := preload("res://scripts/gamedata/phase2_duallane.gd")
const _LS := preload("res://scripts/systems/replay/live_spectate.gd")

const TEX_BG := "res://assets/sprites/bracket/bracket-bg-arena.png"
const TEX_TROPHY := "res://assets/sprites/bracket/bracket-trophy.png"
const TEX_RIBBON := "res://assets/sprites/bracket/bracket-ribbon.png"
const TEX_MEDAL := "res://assets/sprites/bracket/bracket-medal.png"
const TEX_AVATAR_DEFAULT := "res://assets/sprites/bracket/bracket-avatar-default.png"
const TEX_X := "res://assets/sprites/bracket/bracket-x-stamp.png"
const TEX_PODIUM := "res://assets/sprites/bracket/bracket-podium.png"

## ── 配色: 夜晚竞技场的暖色(火把 / 青铜 / 金)。强调色只三种: 金 = 我 / 冠军, 红 = 开播 / 输, 琥珀 = 即将开播(对标 C26) ──
const PLATE := Color("#211a22")         # 卡身
const PLATE_HEAD := Color("#352823")    # 卡顶状态条
const ROW_IDLE := Color("#2a2129")      # 一行: 有人、还没结果
const ROW_WIN := Color("#4a3a26")       # 一行: 胜者(暖亮)
const ROW_LOSE := Color("#17121a")      # 一行: 输家(压暗)
const ROW_EMPTY := Color("#1c161d")     # 一行: 等待中 / 轮空
const BRONZE := Color("#7a5d3e")        # 卡边
const BRONZE_HI := Color("#b48a58")     # 卡边上沿高光
const INK := Color("#0b0809")           # 最外一圈硬描边
const GOLD := Color("#f4c552")          # 我 / 冠军
const GOLD_DEEP := Color("#9a6a1c")
const LIVE := Color("#e2484e")          # 开播
const LIVE_DEEP := Color("#5e1c20")
const AMBER := Color("#e8a23a")         # 即将开播
const LOSS := Color("#d8473f")          # 输(红叉)
const TXT := Color("#f6ecd9")
const TXT_DIM := Color("#9c8f80")
const TXT_FAINT := Color("#6d6158")
const LINE_DONE := Color("#d8c7a2")
const LINE_IDLE := Color("#4c4038")

const HEAD_H := 26.0
const SCORE_W := 34.0
const TOP_DEFAULT := 150.0
const BOTTOM_PAD := 104.0

var s                        # BracketMapScene(构造注入; 只调它的公开判定)
var _anim_once := {}         # 每张图只播一次入场(轮询每 30 秒重画一次, 不能每次都弹)
var _pulse: Array = []       # 开播那几场的红框 / 签上的灯(呼吸)
var _amber: Array = []       # 即将开播的签(慢闪)
var _trophy: TextureRect = null
var _t := 0.0
## 已经亮过「输家打叉 + 光点走线」的场次(按组 + 周 + 场次)。★静态: 看完回放回来(新场景实例)不再重播一遍。
static var _seen_reveal: Dictionary = {}
## 每格要每秒刷新的字(即将开播的倒计时): [[Label, Callable() -> String], ...]
var live_texts: Array = []


func _init(scene) -> void:
	s = scene


static func applies(n: int) -> bool:
	return n >= 2 and n <= 8


# ═══════════════════════════════════════════════════════════════════
#  几何: 左右对称 · 冠军位在正中 · 8 签首轮每侧 2 场
# ═══════════════════════════════════════════════════════════════════
## 返回 {"r-m": Rect2, "card": Vector2, "final": Rect2, "mid": float, "col_top": float, "center": Dictionary}。坐标 = 屏幕坐标。
## `top` / `bottom` = 对阵区上下沿(屏幕固定件让出来之后的那一段); `podium` = 收盘领奖台占正中上方。
static func layout(n: int, vp: Vector2, top: float = TOP_DEFAULT, bottom: float = -1.0, safe_l: float = 0.0,
		safe_r: float = 0.0, podium: bool = false, promo: bool = false) -> Dictionary:
	var out := {}
	var total := _B.rounds_for(n)
	if bottom < 0.0:
		bottom = vp.y - BOTTOM_PAD
	var area_h := maxf(220.0, bottom - top)
	var mid := top + area_h * 0.5
	var pad := 18.0
	var gap_c := clampf(vp.x * 0.024, 22.0, 44.0)
	var side_cols := maxi(0, total - 1)
	var fw := clampf(vp.x * 0.21, 230.0, 330.0)
	if total == 1:
		fw = clampf(vp.x * 0.30, 290.0, 400.0)
	var card_w := 0.0
	if side_cols > 0:
		var side_w := (vp.x - fw) * 0.5 - pad - gap_c - maxf(safe_l, safe_r)
		card_w = clampf((side_w - float(side_cols - 1) * gap_c) / float(side_cols), 140.0, 330.0)
	var per1 := maxi(1, _B.matches_in_round(n, 1) / 2) if total >= 2 else 1
	var card_h := 0.0
	var gap_v := 0.0
	if per1 >= 2:
		gap_v = clampf(area_h * 0.10, 26.0, 64.0)
		card_h = clampf((area_h - 34.0 - gap_v) * 0.5, 104.0, 176.0)     # 高屏(iPad 4:3 ⇒ 可见区 1280×960)卡跟着长
	else:
		card_h = clampf(area_h * 0.36, 118.0, 184.0)
	var fh := card_h + 12.0
	## 正中那一列自上而下: [领奖台 | 奖杯] + 冠军缎带 + 决赛卡 + 奖励一行; 小组赛再在最上面挂「晋级冠军杯赛」牌 + 箭头
	var promo_h := 54.0 if promo else 0.0
	var crown_h := 0.0
	if podium:
		crown_h = clampf(area_h * 0.40, 150.0, 196.0)
	else:
		crown_h = clampf(area_h - promo_h - 58.0 - fh - 34.0 - 12.0, 56.0, 104.0)
	var col_h := promo_h + crown_h + 58.0 + fh + 30.0
	var col_top := maxf(top - 6.0, mid - col_h * 0.5)
	if col_top + col_h > bottom + 6.0:
		col_top = bottom + 6.0 - col_h
	var final_y := col_top + promo_h + crown_h + 58.0
	var final_rc := Rect2(Vector2((vp.x - fw) * 0.5, final_y), Vector2(fw, fh))
	out["card"] = Vector2(card_w, card_h)
	out["final"] = final_rc
	out["mid"] = mid
	out["col_top"] = col_top
	out["center"] = {"promo": Rect2(Vector2(vp.x * 0.5 - 150.0, col_top), Vector2(300.0, promo_h)),
		"crown": Rect2(Vector2(vp.x * 0.5 - 150.0, col_top + promo_h), Vector2(300.0, crown_h)),
		## 缎带 52 高(字 18): 字要落在缎带正面那一条里(verify_ui_consistency「文字压边带」, 46 高时越 3px)
		"ribbon": Rect2(Vector2(vp.x * 0.5 - clampf(fw * 0.56, 140.0, 190.0), final_y - 56.0),
			Vector2(clampf(fw * 1.12, 280.0, 380.0), 52.0)),
		"reward": Rect2(Vector2(vp.x * 0.5 - 260.0, final_rc.end.y + 6.0), Vector2(520.0, 24.0))}
	for r in range(1, total + 1):
		var cnt := _B.matches_in_round(n, r)
		for m in range(cnt):
			var rc := Rect2()
			if r >= total:
				rc = final_rc
			else:
				var left := m < cnt / 2
				var idx := m if left else m - cnt / 2
				var cy := mid
				if total == 2:
					cy = final_rc.get_center().y          # 4 人组: 两场半决赛与决赛同高, 连线走直线
				elif r == 1 and per1 >= 2:
					var start := mid - (card_h * 2.0 + gap_v) * 0.5
					cy = start + card_h * 0.5 + float(idx) * (card_h + gap_v)
				var x := pad + safe_l + float(r - 1) * (card_w + gap_c)
				if not left:
					x = vp.x - pad - safe_r - float(r - 1) * (card_w + gap_c) - card_w
				rc = Rect2(Vector2(x, cy - card_h * 0.5), Vector2(card_w, card_h))
			out["%d-%d" % [r, m]] = rc
	return out


## 轮空那一场画成半高小卡(P4): 竖向居中在原来那一格里, 连线照原格中线走(结构不变 · 对标 C04 / C09)。
static func bye_rect(rc: Rect2) -> Rect2:
	var h := clampf(rc.size.y * 0.56, 64.0, 84.0)
	return Rect2(Vector2(rc.position.x, rc.get_center().y - h * 0.5), Vector2(rc.size.x, h))


# ═══════════════════════════════════════════════════════════════════
#  背景 / 氛围(进场建一次)
# ═══════════════════════════════════════════════════════════════════
func build_backdrop(host: Control) -> void:
	if host.has_node("HeroBackdrop"):
		return
	var root := Control.new()
	root.name = "HeroBackdrop"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsz := host.get_viewport().get_visible_rect().size
	root.size = vsz
	host.add_child(root)
	host.move_child(root, 1)            # 在纯色底(_bg)之上、画布之下
	if ResourceLoader.exists(TEX_BG):
		var tr := TextureRect.new()
		tr.texture = load(TEX_BG)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = vsz
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	## 中间压暗(图要读得清) + 四周更暗(视线收到中间)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.50)
	dim.size = vsz
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.62)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.48)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 128
	gt.height = 72
	var vg := TextureRect.new()
	vg.texture = gt
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.size = vsz
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vg)
	## 火星: 从底边往上飘的小方块(像素风 = 方的, 不要圆粒子)
	var em := CPUParticles2D.new()
	em.name = "Embers"
	em.amount = 36
	em.lifetime = 6.0
	em.preprocess = 6.0
	em.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	em.emission_rect_extents = Vector2(root.size.x * 0.5, 4.0)
	em.position = Vector2(root.size.x * 0.5, root.size.y + 6.0)
	em.direction = Vector2(0, -1)
	em.spread = 18.0
	em.gravity = Vector2(0, -6)
	em.initial_velocity_min = 22.0
	em.initial_velocity_max = 48.0
	em.scale_amount_min = 2.0
	em.scale_amount_max = 4.0
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	cg.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.0), Color(1.0, 0.62, 0.22, 0.85), Color(0.9, 0.3, 0.1, 0.0)])
	em.color_ramp = cg
	root.add_child(em)


# ═══════════════════════════════════════════════════════════════════
#  整张图
# ═══════════════════════════════════════════════════════════════════
func build(canvas: Control, n: int, vp: Vector2, top: float, bottom: float, safe_l: float, safe_r: float) -> Dictionary:
	_pulse.clear()
	_amber.clear()
	live_texts.clear()
	var total := _B.rounds_for(n)
	var podium: bool = bool(s._info.podium_on())
	var promo: bool = str(s._view) != "finals"
	var lay := layout(n, vp, top, bottom, safe_l, safe_r, podium, promo)
	s._hero_final_w = (lay["final"] as Rect2).size.x
	var key := "%s|%d|%d" % [str(s._view), int(s.cur().get("bucket", -1)), n]
	var anim: bool = not _anim_once.has(key)
	_anim_once[key] = true
	var sheet := "%d|%d" % [int(s.cur().get("bucket", -1)), int(s.feed_week())]
	_round_titles(canvas, n, total, lay)
	_links(canvas, n, total, lay)
	_center(canvas, n, total, lay, anim, podium, promo)
	var order := 0
	var reveals: Array = []
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			var rc: Rect2 = lay["%d-%d" % [r, m]]
			var card := _card(r, m, rc, r >= total)
			canvas.add_child(card)
			if anim:
				_pop_in(card, 0.06 + float(order) * 0.06)
			order += 1
			## 新揭晓的场次: 输家盖红叉 + 光点沿连线走到下一格(G9 · C-2)
			var ws: int = s.winner_side(r, m)
			if ws >= 0 and not _is_bye_match(r, m):
				var rk := "%s|%d-%d" % [sheet, r, m]
				if not _seen_reveal.has(rk):
					_seen_reveal[rk] = true
					reveals.append([r, m, ws, card])
	var k := 0
	for it in reveals:
		_stamp_loser(it[3], it[2], 0.45 + float(k) * 0.35)
		if int(it[0]) < total:
			_travel_dot(canvas, lay, n, int(it[0]), int(it[1]), 0.75 + float(k) * 0.35)
		k += 1
	return lay


func _is_bye_match(r: int, m: int) -> bool:
	return bool(s.competitor(r, m, 0).get("bye", false)) or bool(s.competitor(r, m, 1).get("bye", false))


## 入场: 小一点 + 透明 → 回弹到位(每张错开一点, 像发牌)
func _pop_in(c: Control, delay: float) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.86, 0.86)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 每帧: 奖杯呼吸 + 开播红框呼吸 + 即将开播的签慢闪(场景 `_process` 调)
func tick(dt: float) -> void:
	_t += dt
	if _trophy != null and is_instance_valid(_trophy):
		_trophy.position.y = float(_trophy.get_meta("y0", _trophy.position.y)) + sin(_t * 2.2) * 3.0
		var glow := 0.9 + 0.1 * sin(_t * 3.1)
		_trophy.modulate = Color(glow, glow, glow * 0.95, 1.0)
	for nd in _pulse:
		if is_instance_valid(nd):
			(nd as CanvasItem).modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 4.4))
	for nd2 in _amber:
		if is_instance_valid(nd2):
			(nd2 as CanvasItem).modulate.a = 0.7 + 0.3 * (0.5 + 0.5 * sin(_t * 2.0))


## 「观看开播 · N 场」按下: 把开播中的那几格各弹三下(提示去点哪一格), 不替玩家挑。
func flash_live(canvas: Control) -> void:
	for c in canvas.get_children():
		if not (c is Control) or c is Button or not c.has_meta("rm"):
			continue
		var rm: Vector2i = c.get_meta("rm")
		if str(s.match_state(rm.x, rm.y)) != str(s.ST_PREMIERE):
			continue
		var card := c as Control
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween()
		for _i in range(3):
			tw.tween_property(card, "scale", Vector2(1.07, 1.07), 0.12).set_trans(Tween.TRANS_SINE)
			tw.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)


## 每秒刷新那几行倒计时(场景 `_process` 里按 0.5 秒一拍调)。
func refresh_texts() -> void:
	for it in live_texts:
		var lb = it[0]
		if is_instance_valid(lb):
			(lb as Label).text = str((it[1] as Callable).call())


# ── 列标题: 「1/4 决赛 · 半决赛」(决赛那一列由正中的冠军缎带 + 决赛卡的卡顶说) ──
func _round_titles(canvas: Control, n: int, total: int, lay: Dictionary) -> void:
	var cur_r := int(s._info.title_round())
	for r in range(1, total):
		var cnt := _B.matches_in_round(n, r)
		for m in [0, cnt / 2]:
			if not lay.has("%d-%d" % [r, m]):
				continue
			var rc: Rect2 = lay["%d-%d" % [r, m]]
			var top_y := rc.position.y
			for k in range(cnt):
				var o: Rect2 = lay["%d-%d" % [r, k]]
				if absf(o.position.x - rc.position.x) < 1.0:
					top_y = minf(top_y, o.position.y)
			var on := r == cur_r
			var lb := _label(round_name(n, r), 18, GOLD if on else TXT, true)
			lb.name = "RoundTitle"
			lb.set_meta("bk", "round_title")
			lb.position = Vector2(rc.position.x, top_y - 32.0)
			lb.size = Vector2(rc.size.x, 26.0)
			lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			canvas.add_child(lb)
			if on:
				## 当前轮: 标题下一道金杠(对标 C02 当前列变色)
				_box(canvas, Rect2(rc.position.x + rc.size.x * 0.5 - 22.0, top_y - 7.0, 44.0, 3.0), GOLD)


## 列名(P5)。★8 签首轮叫「1/4 决赛」(有轮空也照叫 —— Dota A03 轮空那张首轮同样叫 QUARTER FINALS, 轮空写在格子里)。
static func round_name(n: int, r: int) -> String:
	var total := _B.rounds_for(n)
	if r >= total:
		return "决赛"
	if r == total - 1:
		return "半决赛"
	if r == total - 2:
		return "1/4 决赛"
	return "1/%d 决赛" % (1 << (total - r))


# ── 连线: 粗、带硬描边; 已决出的亮、我那条整条金色 ──
func _links(canvas: Control, n: int, total: int, lay: Dictionary) -> void:
	for r in range(1, total):
		for m in range(_B.matches_in_round(n, r)):
			var pts := link_points(lay, n, r, m)
			if pts.is_empty():
				continue
			var ws: int = s.winner_side(r, m)
			var decided := ws >= 0
			## 轮空晋级的那一位也已站到下一格(连线照画、照亮 —— 对标 C09)
			if _is_bye_match(r, m):
				decided = true
				ws = 1 if bool(s.competitor(r, m, 0).get("bye", false)) else 0
			var mine: bool = decided and bool(s._is_me_side(r, m, ws))
			var col := GOLD if mine else (LINE_DONE if decided else LINE_IDLE)
			var w := 5.0 if decided else 3.0
			for i in range(pts.size() - 1):
				_seg(canvas, pts[i], pts[i + 1], w, col)


## 一场 → 下一格的折线三点(横 → 竖 → 横)。
static func link_points(lay: Dictionary, n: int, r: int, m: int) -> Array:
	if not lay.has("%d-%d" % [r, m]) or not lay.has("%d-%d" % [r + 1, m / 2]):
		return []
	var src: Rect2 = lay["%d-%d" % [r, m]]
	var dst: Rect2 = lay["%d-%d" % [r + 1, m / 2]]
	var left := src.get_center().x < dst.get_center().x
	var x0 := src.end.x if left else src.position.x
	var x1 := dst.position.x if left else dst.end.x
	var y0 := src.get_center().y
	var y1 := dst.get_center().y
	var xm := (x0 + x1) * 0.5
	return [Vector2(x0, y0), Vector2(xm, y0), Vector2(xm, y1), Vector2(x1, y1)]


func _seg(canvas: Control, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var r := Rect2(Vector2(minf(a.x, b.x) - w * 0.5, minf(a.y, b.y) - w * 0.5),
		Vector2(absf(b.x - a.x) + w, absf(b.y - a.y) + w))
	_box(canvas, r.grow(1.0), INK)
	_box(canvas, r, col)


## 光点沿连线走到下一格(G9): 一枚发光方块, 走完在落点闪一下。
func _travel_dot(canvas: Control, lay: Dictionary, n: int, r: int, m: int, delay: float) -> void:
	var pts := link_points(lay, n, r, m)
	if pts.is_empty():
		return
	var dot := ColorRect.new()
	dot.name = "TravelDot"
	dot.color = Color("#fff3c4")
	dot.size = Vector2(10, 10)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.position = (pts[0] as Vector2) - Vector2(5, 5)
	dot.modulate.a = 0.0
	canvas.add_child(dot)
	var halo := ColorRect.new()
	halo.color = Color(1.0, 0.8, 0.35, 0.45)
	halo.size = Vector2(18, 18)
	halo.position = Vector2(-4, -4)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_child(halo)
	var tw := dot.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(dot, "modulate:a", 1.0, 0.08)
	for i in range(1, pts.size()):
		var seg_len: float = ((pts[i] as Vector2) - (pts[i - 1] as Vector2)).length()
		tw.tween_property(dot, "position", (pts[i] as Vector2) - Vector2(5, 5), maxf(0.06, seg_len / 520.0))
	tw.tween_property(dot, "scale", Vector2(2.4, 2.4), 0.16)
	tw.parallel().tween_property(dot, "modulate:a", 0.0, 0.22)
	tw.tween_callback(dot.queue_free)


## 输家盖红叉(G9): 从大到小砸下来, 带一下震。
func _stamp_loser(card: Control, ws: int, delay: float) -> void:
	var tgt: Control = card.get_meta("loser_mark", null) if card.has_meta("loser_mark") else null
	if tgt == null or not is_instance_valid(tgt):
		return
	tgt.pivot_offset = tgt.size * 0.5
	tgt.scale = Vector2(2.2, 2.2)
	tgt.modulate.a = 0.0
	var tw := tgt.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(tgt, "modulate:a", 1.0, 0.10)
	tw.tween_property(tgt, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	var p0 := card.position
	tw.tween_property(card, "position", p0 + Vector2(3, 2), 0.04)
	tw.tween_property(card, "position", p0 - Vector2(2, 1), 0.04)
	tw.tween_property(card, "position", p0, 0.04)
	var _u := ws


# ── 正中: [晋级冠军杯赛牌 + 箭头] / [奖杯 | 领奖台] + 冠军缎带 + 奖励一行 ──
func _center(canvas: Control, n: int, total: int, lay: Dictionary, anim: bool, podium: bool, promo: bool) -> void:
	var cen: Dictionary = lay["center"]
	var fr: Rect2 = lay["final"]
	var cx := fr.get_center().x
	var ws: int = s.winner_side(total, 0)
	var champ: Dictionary = s.competitor(total, 0, ws) if ws >= 0 else {}
	var decided := ws >= 0 and int(champ.get("seed", -1)) >= 0
	var crown: Rect2 = cen["crown"]
	## 小组赛: 「组冠军 → 冠军杯赛」那条线(②)
	if promo:
		var pr: Rect2 = cen["promo"]
		var plate := Rect2(Vector2(cx - 132.0, pr.position.y), Vector2(264.0, 32.0))
		_box(canvas, plate.grow(2.0), INK)
		_box(canvas, plate.grow(1.0), GOLD_DEEP if not decided else GOLD)
		_box(canvas, plate, Color("#2b2016"))
		var pl := _label("晋级 %s · %s" % [_P2C.STAGE_CUP, str(s._info.cup_start_hhmm())], 16, GOLD if decided else TXT, true)
		pl.name = "PromoPlate"
		pl.position = plate.position
		pl.size = plate.size
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		canvas.add_child(pl)
		## 箭头: 奖杯 → 牌子(金 = 已决出, 青铜 = 还没)
		var acol := GOLD if decided else BRONZE
		var ay0 := plate.end.y + 2.0
		var ay1 := crown.position.y + 6.0
		if ay1 > ay0 + 4.0:
			_box(canvas, Rect2(cx - 3.0, ay0 + 8.0, 6.0, ay1 - ay0 - 8.0), INK)
			_box(canvas, Rect2(cx - 2.0, ay0 + 8.0, 4.0, ay1 - ay0 - 8.0), acol)
			for i in range(4):
				_box(canvas, Rect2(cx - float(i) * 2.0 - 1.0, ay0 + float(i) * 2.0, float(i) * 4.0 + 2.0, 2.0), acol)
	if podium:
		_podium(canvas, crown, total, anim)
	else:
		## 决出冠军: 奖杯后面一圈金光 + 一直冒的小闪光(Dota A02 冠军格发光)
		var tsz := clampf(crown.size.y, 56.0, 104.0)
		var tpos := Vector2(cx - tsz * 0.5, crown.end.y - tsz)
		if decided:
			_glow(canvas, Vector2(cx, tpos.y + tsz * 0.5), tsz * 2.1)
			_sparkles(canvas, Vector2(cx, tpos.y + tsz * 0.5), tsz * 0.55)
		if ResourceLoader.exists(TEX_TROPHY):
			var tr := TextureRect.new()
			tr.name = "HeroTrophy"
			tr.texture = load(TEX_TROPHY)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			tr.size = Vector2(tsz, tsz)
			tr.position = tpos
			tr.set_meta("y0", tr.position.y)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not decided:
				tr.self_modulate = Color(0.78, 0.74, 0.70, 1.0)
			canvas.add_child(tr)
			_trophy = tr
			if anim:
				tr.pivot_offset = tr.size * 0.5
				tr.scale = Vector2(0.6, 0.6)
				var tw := tr.create_tween()
				tw.tween_property(tr, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	## 冠军缎带: 未决出 =「冠军」/「A 组冠军」, 决出 = 名字(冠军位未决出前是空的 —— 对标 C20)
	var rib: Rect2 = cen["ribbon"]
	var who := str(s._info.champion_title())
	var rib_txt := who if not decided else "%s · %s" % [who, s._fit_name(str(champ.get("name", "")), rib.size.x - 150.0, false, 20.0)]
	_ribbon(canvas, rib, rib_txt, 18, decided)
	## 奖励一行(决赛卡下面); 收盘那一刻这一行让给滚动名单(⑰)
	if podium:
		return
	var rw := _label(str(s._info.reward_line()), 15, Color("#e9d6a8"), true)
	rw.name = "RewardLine"
	var rr: Rect2 = cen["reward"]
	rw.position = rr.position
	rw.size = rr.size
	rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(rw)


func _glow(canvas: Control, c: Vector2, gsz: float) -> void:
	var gg := Gradient.new()
	gg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gg.colors = PackedColorArray([Color(1.0, 0.82, 0.35, 0.55), Color(1.0, 0.7, 0.2, 0.18), Color(1.0, 0.7, 0.2, 0.0)])
	var gtx := GradientTexture2D.new()
	gtx.gradient = gg
	gtx.fill = GradientTexture2D.FILL_RADIAL
	gtx.fill_from = Vector2(0.5, 0.5)
	gtx.fill_to = Vector2(1.0, 0.5)
	gtx.width = 64
	gtx.height = 64
	var glow := TextureRect.new()
	glow.name = "ChampGlow"
	glow.texture = gtx
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.size = Vector2(gsz, gsz)
	glow.position = c - Vector2(gsz, gsz) * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(glow)


func _sparkles(canvas: Control, c: Vector2, radius: float) -> void:
	var sp := CPUParticles2D.new()
	sp.name = "ChampSparkles"
	sp.amount = 18
	sp.lifetime = 1.4
	sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = radius
	sp.position = c
	sp.direction = Vector2(0, -1)
	sp.spread = 180.0
	sp.gravity = Vector2.ZERO
	sp.initial_velocity_min = 4.0
	sp.initial_velocity_max = 16.0
	sp.scale_amount_min = 3.0
	sp.scale_amount_max = 5.0
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	sg.colors = PackedColorArray([Color(1, 1, 0.8, 0.0), Color(1, 0.95, 0.6, 1.0), Color(1, 0.8, 0.3, 0.0)])
	sp.color_ramp = sg
	canvas.add_child(sp)


## 收盘领奖台(⑰ · G22 · Lichess 3-5): 冠军站中间最高, 亚军左, 两位四强右; 头像站在台上, 名字在头像下。
func _podium(canvas: Control, crown: Rect2, total: int, anim: bool) -> void:
	var cx := crown.get_center().x
	var fr_w: float = s._hero_final_w
	var pw := clampf(crown.size.y * 1.9, 220.0, minf(360.0, fr_w * 1.08))
	var ph := pw * 54.0 / 134.0          # 贴图 134×54(按整图量的台面位置, 见下)
	var base := Rect2(Vector2(cx - pw * 0.5, crown.end.y - ph * 0.62), Vector2(pw, ph * 0.62))
	var steps: Array = []   # [台面矩形(头像站在它上沿), 名次]
	if ResourceLoader.exists(TEX_PODIUM):
		var tr := TextureRect.new()
		tr.name = "Podium"
		tr.texture = load(TEX_PODIUM)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(pw, ph)
		tr.position = Vector2(cx - pw * 0.5, crown.end.y - ph)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(tr)
		## 台面(量自贴图: 中台 x 31%~69% 顶 2% / 左台 9%~30% 顶 24% / 右台 74%~96% 顶 36%)
		var x0 := tr.position.x
		var y0 := tr.position.y
		steps = [[Rect2(Vector2(x0 + pw * 0.31, y0 + ph * 0.02), Vector2(pw * 0.38, 4.0)), 1],
			[Rect2(Vector2(x0 + pw * 0.09, y0 + ph * 0.24), Vector2(pw * 0.21, 4.0)), 2],
			[Rect2(Vector2(x0 + pw * 0.74, y0 + ph * 0.36), Vector2(pw * 0.22, 4.0)), 3]]
	else:
		## 贴图不在: 三块直角台(同一套硬边色块)
		var hs := [ph * 0.62, ph * 0.42, ph * 0.30]
		var xs := [cx - pw * 0.17, cx - pw * 0.5, cx + pw * 0.17]
		for i in range(3):
			var rr := Rect2(Vector2(float(xs[i]), base.end.y - float(hs[i])), Vector2(pw * 0.33, float(hs[i])))
			_box(canvas, rr.grow(2.0), INK)
			_box(canvas, rr, [GOLD_DEEP, Color("#6f6a66"), Color("#7a4a2a")][i])
			_box(canvas, Rect2(rr.position, Vector2(rr.size.x, 3.0)), BRONZE_HI)
			var nl := _label(str(i + 1), 26, TXT, true)
			nl.position = rr.position
			nl.size = rr.size
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			canvas.add_child(nl)
			steps.append([Rect2(rr.position, Vector2(rr.size.x, 4.0)), i + 1])
	var places: Dictionary = s._info.podium_places()
	if places.has(1):
		## 冠军那一台背后一圈金光(垫在头像下面)
		var first: Rect2 = steps[0][0]
		_glow(canvas, Vector2(first.get_center().x, first.position.y - 34.0), 200.0)
		_sparkles(canvas, Vector2(first.get_center().x, first.position.y - 34.0), 46.0)
	var order := 0
	for st in steps:
		var top: Rect2 = st[0]
		var place: int = int(st[1])
		var who: Array = places.get(place, [])
		if who.is_empty():
			continue
		var k := who.size()
		## 头像同级大小(冠军 56, 其余 44); 两位四强左右分开站在 3 号台两侧(台窄就往外探), 名字一上一下两行错开
		var av := 56.0 if place == 1 else 44.0
		var gap := 14.0
		for i in range(k):
			var c: Dictionary = who[i]
			var ax := top.get_center().x - (float(k) * (av + gap) - gap) * 0.5 + float(i) * (av + gap)
			var arc := Rect2(Vector2(ax, top.position.y - av - 2.0), Vector2(av, av))
			var hold := Control.new()
			hold.name = "PodiumSeat%d" % place
			hold.set_meta("place", place)
			hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
			canvas.add_child(hold)
			_portrait(hold, arc, c, -1, 0, place == 1)
			var nfs := 17 if place == 1 else 15
			var nm := _label(s._fit_name(str(c.get("name", "")), 104.0, false, float(nfs)), nfs, GOLD if place == 1 else TXT, true)
			nm.name = "PodiumName"
			nm.set_meta("bk", "podium_name")
			nm.position = Vector2(arc.get_center().x - 56.0, arc.position.y - 24.0 - (22.0 if (k > 1 and i % 2 == 1) else 0.0))
			nm.size = Vector2(112.0, 22.0)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hold.add_child(nm)
			if anim:
				hold.modulate.a = 0.0
				var tw := hold.create_tween()
				tw.tween_interval(0.25 + float(3 - place) * 0.25 + float(order) * 0.05)
				tw.tween_property(hold, "modulate:a", 1.0, 0.25)
			order += 1


## 缎带(bracket-ribbon.png 160×40 九宫拉宽) + 居中字
func _ribbon(parent: Control, r: Rect2, text: String, fs: int, gold: bool) -> void:
	if ResourceLoader.exists(TEX_RIBBON):
		var np := NinePatchRect.new()
		np.name = "Ribbon"
		np.texture = load(TEX_RIBBON)
		np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		np.patch_margin_left = 34
		np.patch_margin_right = 34
		np.patch_margin_top = 8
		np.patch_margin_bottom = 8
		np.position = r.position
		np.size = r.size
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(np)
	var lb := _label(text, fs, GOLD if gold else TXT, true)
	lb.name = "RibbonText"
	lb.position = r.position + Vector2(40.0, -2.0)
	lb.size = r.size - Vector2(80.0, 4.0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)


# ═══════════════════════════════════════════════════════════════════
#  一场 = 一张对阵卡: 卡顶状态条 + 上下两行(头像 · 名字 · 来历 · 比分)
# ═══════════════════════════════════════════════════════════════════
func _card(r: int, m: int, rc0: Rect2, is_final: bool) -> Control:
	var st: String = s.match_state(r, m)
	var mine: bool = s.is_my_match(r, m)
	var ws: int = s.winner_side(r, m)
	var a: Dictionary = s.competitor(r, m, 0)
	var b: Dictionary = s.competitor(r, m, 1)
	var bye := bool(a.get("bye", false)) or bool(b.get("bye", false))
	if bye:
		ws = -1                       # 轮空那一场没打: 不画胜负(同 `_make_node` 的口径)
	var rc := bye_rect(rc0) if bye else rc0
	var live: bool = st == s.ST_PREMIERE
	var upcoming: bool = st == s.ST_UPCOMING
	var w := rc.size.x
	var h := rc.size.y
	var holder := Control.new()
	holder.name = "MatchCard"
	holder.position = rc.position
	holder.size = rc.size
	holder.custom_minimum_size = rc.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta("rm", Vector2i(r, m))

	## 卡身: 硬描边 + 边色(我 = 金, 开播 = 红, 即将开播 = 琥珀, 决赛 = 暗金) + 不透明底
	var edge := BRONZE
	if is_final:
		edge = GOLD_DEEP
	if upcoming:
		edge = AMBER
	if live:
		edge = LIVE
	if mine:
		edge = GOLD
	_box(holder, Rect2(-3, -3, w + 6, h + 6), INK)
	_box(holder, Rect2(-1, -1, w + 2, h + 2), edge)
	_box(holder, Rect2(1, 1, w - 2, h - 2), PLATE)
	if live:
		## 开播: 外面再套一圈呼吸的红框(对标 C11: 描边换色 + 卡上文字标签)
		var ring := Control.new()
		ring.name = "LiveRing"
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ring)
		_box(ring, Rect2(-8, -8, w + 16, 4), LIVE)
		_box(ring, Rect2(-8, h + 4, w + 16, 4), LIVE)
		_box(ring, Rect2(-8, -8, 4, h + 16), LIVE)
		_box(ring, Rect2(w + 4, -8, 4, h + 16), LIVE)
		_pulse.append(ring)

	## 卡顶状态条
	var head_col := PLATE_HEAD
	if live:
		head_col = LIVE_DEEP
	elif upcoming:
		head_col = Color("#4a3418")
	elif ws >= 0 and s._is_me_side(r, m, ws):
		head_col = GOLD_DEEP
	_box(holder, Rect2(3, 3, w - 6, HEAD_H), head_col)
	_box(holder, Rect2(3, 3, w - 6, 2), BRONZE_HI if not mine else Color("#fff0b8"))
	var chip_w := 0.0
	if live:
		## 红色胶囊「开播」+ 一盏会闪的灯(用词: 周日是先算好、到点播出 ⇒ 叫「开播」不叫「直播」)
		chip_w = 62.0
		_box(holder, Rect2(w - chip_w - 6, 6, chip_w, HEAD_H - 6), LIVE)
		var lamp := ColorRect.new()
		lamp.color = Color.WHITE
		lamp.position = Vector2(w - chip_w + 1, 13)
		lamp.size = Vector2(7, 7)
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lamp)
		_pulse.append(lamp)
		var pt := _label(str(_LS.TAG_PREMIERE), 14, Color.WHITE, false)
		pt.name = "PremiereTag"
		pt.position = Vector2(w - chip_w + 6, 3)
		pt.size = Vector2(chip_w - 12, HEAD_H)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(pt)
	elif upcoming:
		## 琥珀签「即将开播」(S 分身清单第 1 条); 倒计时写在卡顶左边那句里, 每秒刷新
		chip_w = 76.0
		var chip := Control.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(chip)
		_box(chip, Rect2(w - chip_w - 6, 6, chip_w, HEAD_H - 6), AMBER)
		var ut := _label("即将开播", 13, Color("#2a1a06"), false)
		ut.name = "UpcomingTag"
		ut.position = Vector2(w - chip_w - 6, 3)
		ut.size = Vector2(chip_w, HEAD_H)
		ut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ut.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(ut)
		_amber.append(chip)
	var hl := _label(str(s._info.card_head_text(r, m)), 14, GOLD if (ws >= 0 and s._is_me_side(r, m, ws)) else TXT, false)
	hl.name = "CardHead"
	hl.position = Vector2(10, 3)
	hl.size = Vector2(w - 20 - chip_w, HEAD_H)
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hl.clip_text = false
	holder.add_child(hl)
	var head_w := w - 20.0 - chip_w - 4.0
	_fit_head(hl, head_w)
	if upcoming:
		live_texts.append([hl, func() -> String:
			hl.add_theme_font_size_override("font_size", 14)
			var t := str(s._info.card_head_text(r, m))
			hl.text = t
			_fit_head(hl, head_w)
			return hl.text])

	if bye:
		_bye_body(holder, a, b, w, h)
	else:
		var body_top := HEAD_H + 6.0
		var row_h := (h - body_top - 4.0) * 0.5
		var sc_raw = (s.cur().get("scores", {}) as Dictionary).get("%d-%d" % [r, m], null)
		var sc_pair: Array = DL_SCORE.score_pair(int(sc_raw)) if (ws >= 0 and sc_raw != null) else []
		for side in range(2):
			_row(holder, r, m, side, a if side == 0 else b, ws, Rect2(3.0, body_top + float(side) * row_h, w - 6.0, row_h - 2.0),
				sc_pair, live or upcoming)

	## 能点的那一场: 整格热区(门禁认 NodeBtn / PlayMark / PlayTag)
	if s.can_open(r, m):
		var pm := Control.new()
		pm.name = "PlayMark"
		pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pm)
		var play: bool = s.should_fetch_opponent(r, m)
		if play:
			## 我要开打的那一场(本机开打的老规则; 服务器裁判开着时不会走到这里): 卡顶金签「对战」
			var pt2 := _label("对战", 13, Color("#2a1a06"), false)
			pt2.name = "PlayTag"
			_box(holder, Rect2(w - 58, 6, 50, HEAD_H - 6), GOLD)
			pt2.position = Vector2(w - 58, 3)
			pt2.size = Vector2(50, HEAD_H)
			pt2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pt2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.add_child(pt2)
		var btn := Button.new()
		btn.name = s.N_NODE_BTN
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for sk in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(sk, StyleBoxEmpty.new())
		btn.size = rc.size
		btn.tooltip_text = "开始对战" if play else (_LS.BTN_WATCH if live else "观看回放")
		btn.set_meta("rm", Vector2i(r, m))
		btn.pressed.connect(func(): s._open_popup(r, m))
		holder.add_child(btn)
	elif upcoming:
		## 即将开播那一格: 点了弹一张只写「X 后开播」的小卡(S 分身清单第 7 条)。★不叫 NodeBtn、不带 rm(③ 的分母不变)。
		var ub := Button.new()
		ub.name = "UpcomingInfo"
		ub.flat = true
		ub.focus_mode = Control.FOCUS_NONE
		for sk2 in ["normal", "hover", "pressed", "focus", "disabled"]:
			ub.add_theme_stylebox_override(sk2, StyleBoxEmpty.new())
		ub.size = rc.size
		ub.set_meta("up_rm", Vector2i(r, m))
		ub.pressed.connect(func(): s._open_upcoming_card(r, m))
		holder.add_child(ub)
	return holder


## 卡顶字放不下: 去掉最前面那一段(「第 2 场 · 」)→ 缩到 12 号。
func _fit_head(hl: Label, avail: float) -> void:
	var f: Font = hl.get_theme_font("font")
	if f == null:
		return
	var fs := hl.get_theme_font_size("font_size")
	if f.get_string_size(hl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
		return
	var parts := hl.text.split(" · ")
	if parts.size() > 1:
		hl.text = " · ".join(parts.slice(1))
	if f.get_string_size(hl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		hl.add_theme_font_size_override("font_size", 12)


## 一行: [头像] [✓ 名字 / 来历] …… [比分]
func _row(holder: Control, r: int, m: int, side: int, c: Dictionary, ws: int, rr: Rect2, sc_pair: Array, hidden: bool) -> void:
	var sd := int(c.get("seed", -1))
	var tick: bool = ws >= 0 and side == ws
	var lost: bool = ws >= 0 and side != ws
	var me_side: bool = s._is_me_side(r, m, side)
	var fill := ROW_IDLE
	if sd < 0:
		fill = ROW_EMPTY
	elif tick:
		fill = ROW_WIN
	elif lost:
		fill = ROW_LOSE
	_box(holder, rr, fill)
	if tick:
		_box(holder, Rect2(rr.position, Vector2(4.0, rr.size.y)), GOLD)
	elif me_side:
		_box(holder, Rect2(rr.position, Vector2(4.0, rr.size.y)), GOLD_DEEP)
	var av := clampf(rr.size.y - 8.0, 26.0, 60.0)
	var arc := Rect2(Vector2(rr.position.x + 9.0, rr.position.y + (rr.size.y - av) * 0.5), Vector2(av, av))
	var mark := _portrait(holder, arc, c, ws, side, false)
	if lost and mark != null:
		holder.set_meta("loser_mark", mark)
	if me_side:
		var yt := _label("你", 12, Color("#2a1a06"), false)
		var yr := Rect2(arc.end - Vector2(17, 15), Vector2(19, 17))
		_box(holder, yr.grow(1.0), INK)
		_box(holder, yr, GOLD)
		yt.position = yr.position
		yt.size = yr.size
		yt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		yt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(yt)
	var sc_w := SCORE_W if not sc_pair.is_empty() else 0.0
	var nx := arc.end.x + 8.0
	var nw := maxf(30.0, rr.end.x - nx - sc_w - 6.0)
	var origin := str(s._info.origin_label(sd)) if sd >= 0 else ""
	if lost and bool(s._info.is_forfeit(r, m)):
		origin = "阵容无效 · 判负"
	var two_line := origin != "" and rr.size.y >= 40.0
	var nm := str(c.get("name", ""))
	if sd < 0 and not bool(c.get("bye", false)):
		nm = "等待中"                 # 未定 = 「等待中」(1-13: 不写「待定」—— 会泄露胜负)
	var tg := str(c.get("tag", ""))
	var col := TXT
	if sd < 0:
		col = TXT_FAINT
	elif lost:
		col = TXT_DIM
	if me_side:
		col = GOLD
	var fs := 17 if rr.size.y >= 40.0 else 15
	var shown: String = s._fit_name(nm, nw - (78.0 if tg != "" else 0.0), tick, float(fs))
	if tg != "":
		shown += " " + tg            # 本组真有人重名时才带号(competitor 判)
	var nl := _label(("✓ " if tick else "") + shown, fs, col, true)
	nl.name = "SeatName"
	nl.position = Vector2(nx, rr.position.y + (2.0 if two_line else 0.0))
	nl.size = Vector2(nw, rr.size.y * (0.58 if two_line else 1.0))
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(nl)
	if two_line:
		var ol := _label(origin, 12, GOLD if origin.find("卫冕") >= 0 else (LOSS if origin.find("判负") >= 0 else TXT_DIM), false)
		ol.name = "SeatOrigin"
		ol.set_meta("bk", "seat_origin")
		ol.position = Vector2(nx, rr.position.y + rr.size.y * 0.56)
		ol.size = Vector2(nw, rr.size.y * 0.40)
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(ol)
	if not sc_pair.is_empty():
		var sb := Rect2(Vector2(rr.end.x - sc_w, rr.position.y), Vector2(sc_w, rr.size.y))
		_box(holder, sb, GOLD if tick else Color("#120e12"))
		var sl := _label(str(sc_pair[0] if tick else sc_pair[1]), 20, Color("#2a1a06") if tick else TXT_DIM, false)
		sl.name = "Score%d" % side
		sl.position = sb.position
		sl.size = sb.size
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(sl)
	var _u := hidden


## 轮空小卡(P4): 只坐一人 +「直接晋级」
func _bye_body(holder: Control, a: Dictionary, b: Dictionary, w: float, h: float) -> void:
	var who: Dictionary = b if bool(a.get("bye", false)) else a
	var rr := Rect2(Vector2(3.0, HEAD_H + 6.0), Vector2(w - 6.0, h - HEAD_H - 10.0))
	_box(holder, rr, ROW_EMPTY)
	if int(who.get("seed", -1)) < 0:
		return
	var av := clampf(rr.size.y - 8.0, 24.0, 40.0)
	var arc := Rect2(Vector2(rr.position.x + 9.0, rr.position.y + (rr.size.y - av) * 0.5), Vector2(av, av))
	_portrait(holder, arc, who, -1, 0, false)
	var me_b: bool = int(who.get("seed", -1)) == int(s.cur().get("me", -1))
	var nw := rr.end.x - arc.end.x - 92.0
	var nl := _label(s._fit_name(str(who.get("name", "")), nw, false, 16.0), 16, GOLD if me_b else TXT, true)
	nl.name = "SeatName"
	nl.position = Vector2(arc.end.x + 8.0, rr.position.y)
	nl.size = Vector2(nw, rr.size.y)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(nl)
	var cr := Rect2(Vector2(rr.end.x - 80.0, rr.get_center().y - 11.0), Vector2(74.0, 22.0))
	_box(holder, cr, Color("#3a3024"))
	var cl := _label("直接晋级", 13, Color("#e9d6a8"), false)
	cl.position = cr.position
	cl.size = cr.size
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(cl)


## 头像(⑨ · P7): 有图画图, 对不上就画默认龟头像 —— **不写名字首字**; 未定 = 问号; 胜者挂奖章; 输家压暗 + 红叉。
## 节点是带 meta「Portrait」的 PanelContainer(与 MatchCard.avatar 同一个认法, 门禁按 meta 数头像)。返回红叉节点(输家)。
func _portrait(parent: Control, r: Rect2, c: Dictionary, ws: int, side: int, big_gold: bool) -> Control:
	var sd := int(c.get("seed", -1))
	_box(parent, r.grow(2.0), INK)
	_box(parent, r.grow(1.0), GOLD if ((ws >= 0 and side == ws) or big_gold) else BRONZE)
	var pc := PanelContainer.new()
	pc.name = "Portrait"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#120e12")
	sb.set_corner_radius_all(0)
	pc.add_theme_stylebox_override("panel", sb)
	pc.position = r.position
	pc.size = r.size
	pc.custom_minimum_size = r.size
	parent.add_child(pc)
	if bool(c.get("bye", false)):
		pc.set_meta("Portrait", "")
		return null
	if sd < 0:
		pc.set_meta("Portrait", "")
		var q := _label("?", int(r.size.y * 0.6), TXT_FAINT, true)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(q)
		return null
	var pid: String = str(c["_pid"]) if c.has("_pid") else str(s.portrait_of(sd))
	var path := "res://assets/sprites/avatars/%s.png" % pid
	if pid == "" or not ResourceLoader.exists(path):
		path = TEX_AVATAR_DEFAULT
	pc.set_meta("Portrait", pid if path != TEX_AVATAR_DEFAULT else "default")
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.flip_h = side == 1 and pid != ""
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ws >= 0 and side != ws:
			tr.modulate = Color(0.40, 0.38, 0.40, 1.0)
		pc.add_child(tr)
	if ws >= 0 and side == ws and ResourceLoader.exists(TEX_MEDAL):
		## 胜章: 挂在头像左上角(只是图, 不写字 —— 揭晓后格子里不挂「胜」「冠」字签, 门禁 verify_finals_premiere ④)
		var md := TextureRect.new()
		md.name = "WinMedal"
		md.texture = load(TEX_MEDAL)
		md.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		md.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		md.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var ms := clampf(r.size.x * 0.5, 18.0, 26.0)
		md.size = Vector2(ms, ms)
		md.position = r.position + Vector2(-ms * 0.35, -ms * 0.30)
		md.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(md)
	if ws >= 0 and side != ws:
		return _x_mark(parent, r)
	return null


## 红叉(输): 优先用出图的印章; 贴图不在就用两条斜向色块拼(直角像素, 不羽化)。
func _x_mark(parent: Control, r: Rect2) -> Control:
	var hold := Control.new()
	hold.name = "LoseMark"
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := r.size.x * 1.05
	hold.position = r.get_center() - Vector2(sz, sz) * 0.5
	hold.size = Vector2(sz, sz)
	parent.add_child(hold)
	if ResourceLoader.exists(TEX_X):
		var tr := TextureRect.new()
		tr.texture = load(TEX_X)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = hold.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hold.add_child(tr)
		return hold
	var step := maxf(2.0, floorf(sz / 14.0))
	var n := int(sz / step)
	for i in range(n):
		for d in [0, 1]:
			var x := float(i) * step if d == 0 else sz - float(i + 1) * step
			_box(hold, Rect2(x - step * 0.5, float(i) * step - step * 0.5, step * 2.0, step * 2.0), INK)
	for i2 in range(n):
		for d2 in [0, 1]:
			var x2 := float(i2) * step if d2 == 0 else sz - float(i2 + 1) * step
			_box(hold, Rect2(x2, float(i2) * step, step, step), LOSS)
	return hold


# ── 小工具 ──
func _box(parent: Control, r: Rect2, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = col
	cr.position = r.position
	cr.size = Vector2(maxf(r.size.x, 1.0), maxf(r.size.y, 1.0))
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
	return cr


func _label(t: String, fs: int, col: Color, outline: bool) -> Label:
	var lb := Label.new()
	lb.text = t
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	if outline:
		lb.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.02, 0.95))
		lb.add_theme_constant_override("outline_size", 5)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb
