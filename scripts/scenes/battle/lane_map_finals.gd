## lane_map_finals.gd — 周日决赛日那一场: 把对阵卡融进桌面地图(方案书 docs/plans/20261122-周日全流程走查与优化.md B2)。
##
## 用户 11-22 U2:「肯定是那个立体的那个动画，那个是最好的呀。但是你周日的话…周日就是更加的高级。那看看怎么融合…
##   把这个对阵卡融合到我们的桌面地图呢？…对阵卡完全没有任何动画效果，它像一个游戏吗？」
## ⇒ 周日不再在地图上面盖一层平面 VS 卡(finals_vs_intro) / 平面「战果」插卡(finals_watch_hud 的 break), 而是在地图幕布上加:
##   开场(overview): 金边框 → 顶上缎带从中间展开写轮次 → 双方名牌从两侧冲进来砸在桌边(震屏 + 扬尘)
##                   → 中间龟甲 VS 盾徽从天砸下 + 冲击环 → 盾徽缩小飞走, 接平时那一套(棋子落位 / 镜头推近本路)
##   一路战果(lane_settle): 同一个金边框 + 名牌; 顶上记分牌换成「名字  金字比分  名字」, 赢的那边数字翻牌;
##                   看别人的比赛时战果章写「X 赢得上路」(「本战场胜利」是录像方的视角, 对旁观者是错话)
## ★只管画面, 与 lane_map_intro 同一个做法: build 时登记轨道, pose(t) 按时刻摆(不用 tween, 门禁能摆到任意时刻去量)。
## ★平时的对局不建这个(wanted() = null), 一行不变。
extends RefCounted

const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const EndBeatsS := preload("res://scripts/scenes/battle/finals_end_beats.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const LMI := preload("res://scripts/scenes/battle/lane_map_intro.gd")   # Dust / CREST(本文件由它 load(), 不互相 preload)

## 节点名(门禁按名字找)
const N_LAYER := "FinalsTableLayer"
const N_RIBBON := "FinalsRibbon"
const N_TITLE := "FinalsRibbonTitle"
const N_PLATE := "FinalsPlate_"          # + left / right
const N_CREST := "FinalsCrest"
const N_SCORE := "FinalsScore"
const N_DIGIT := "FinalsDigit_"          # + left / right

const PLATE_W := 300.0
const PLATE_H := 96.0
const AV := 72.0
const RIB_H := 64.0
const BOTTOM_BAND := 72.0
## 开场时间线(秒; 幕布一共 5 秒, 平时那套的台子 0.25 起依次弹出、棋子 1.05 起落位)
const T_FRAME := 0.0
const T_RIBBON := 0.10
const T_PLATE := 0.30
const T_PLATE_HIT := 0.58
const T_CREST := 0.80
const T_CREST_HIT := 0.98
const T_CREST_FLY := 1.50
## 战果幕: 比分翻牌那一下(平时那套的打叉 0.8、印章 0.95)
const T_FLIP := 1.15

const COL_GOLD := Color("#ffd93d")
const COL_TEXT := Color("#f2f6fa")
const COL_DIM := Color("#b8c6d6")
const COL_BLUE := Color("#5b9cf0")
const COL_RED := Color("#ef5b66")

var intro = null                 # lane_map_intro 实例(轨道 / 声音 / 根节点都借它的)
var info: Dictionary = {}        # replay_controls.intro_info(): title / sub / gold / cards{left,right}
var me := ""                     # 看的人是哪一边("" = 看别人)
var names: Dictionary = {}       # {"l", "r"}
var layer: Control = null
var vp := Vector2(1560, 720)
var inset_b := 0.0
var ftracks: Array = []          # 本文件自己的轨道: ribbon / crest / ring / shake / flip
var _n: Dictionary = {}


## 周日开播(观战页建了)才要; 平时 / 回放 / 不是决赛日 ⇒ null。
static func wanted(battle) -> Object:
	if battle == null or not is_instance_valid(battle):
		return null
	var h = battle.get("_hud")
	var rc = h.get("_replay_ui") if h != null else null
	if rc == null or rc.get("hud") == null:
		return null
	return rc


static func make(battle) -> RefCounted:
	var rc = wanted(battle)
	if rc == null:
		return null
	var f = load("res://scripts/scenes/battle/lane_map_finals.gd").new()
	f.info = rc.intro_info()
	f.names = (rc.get("_names") as Dictionary) if rc.get("_names") is Dictionary else {}
	f.me = EndBeatsS.me_side_of(f.names, ReplayRecorder.play_names, str(GameState.nickname) if GameState != null else "")
	return f


# ══════════════════════════════════════════════════════════════════════
#  建: lane_map_intro._build_table 末尾调
# ══════════════════════════════════════════════════════════════════════
func build(it, settle: bool, inset_bottom: float) -> void:
	intro = it
	vp = it.vp
	inset_b = inset_bottom
	layer = Control.new()
	layer.name = N_LAYER
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.size = vp
	it.root.add_child(layer)
	## 金边框(决赛日标识): 开场淡入, 战果幕直接在
	var fr := GoldFrame.new()
	fr.size = vp
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fr)
	if not settle:
		it._fade(fr, T_FRAME, 0.35)
	for side in ["left", "right"]:
		_build_plate(side, settle)
	if settle:
		_build_score()
		_restamp()
	else:
		_build_ribbon()
		_build_crest()


## 顶上缎带: 轮次(「冠军杯赛半决赛 · 第 1 场」), 从中间往两边展开
func _build_ribbon() -> void:
	var gold := bool(info.get("gold", false))
	var rib := Control.new()
	rib.name = N_RIBBON
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rib.size = Vector2(minf(680.0, vp.x - 320.0), RIB_H + 16.0)
	rib.position = Vector2(roundf((vp.x - rib.size.x) * 0.5), 6.0)
	rib.pivot_offset = rib.size * 0.5
	rib.draw.connect(func() -> void: Ctx.draw_ribbon(rib, rib.size, RIB_H, not gold))
	layer.add_child(rib)
	var txt := str(info.get("title", ""))
	var sub := str(info.get("sub", ""))
	if sub != "":
		txt = "%s · %s" % [txt, sub]
	var tl := Ctx.title_lbl(txt, 30, Color("#fff2c8") if not gold else Color("#3a1e04"))
	tl.name = N_TITLE
	tl.size = Vector2(rib.size.x - 120.0, RIB_H)
	tl.position = Vector2(60.0, 0.0)
	Ctx.outline(tl, 6 if not gold else 0)
	rib.add_child(tl)
	Lang.fit_font(tl, tl.size.x, 30, 18)
	ftracks.append({"k": "ribbon", "node": rib, "t0": T_RIBBON, "dur": 0.38})
	intro._sfx("ui_confirm", T_RIBBON + 0.05, 0.6, 0.8)


## 名牌: 头像 + 名字 + 来历(组冠军 / 卫冕)+ 闯关战绩。左下 / 右下, 开场从屏外冲进来砸住(震屏 + 扬尘)
func _build_plate(side: String, settle: bool) -> void:
	var cd: Dictionary = ((info.get("cards", {}) as Dictionary).get(side, {})) as Dictionary
	var right := side == "right"
	var team := COL_BLUE if not right else COL_RED
	var p := Panel.new()
	p.name = N_PLATE + side
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.94)
	sb.set_border_width_all(3)
	sb.border_color = team
	sb.border_width_top = 4
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(PLATE_W, PLATE_H)
	## 底部那一排(退出键 / 全局决赛日小条)占约 64 px ⇒ 名牌落在它上面
	var to := Vector2(16.0 if not right else vp.x - PLATE_W - 16.0, vp.y - inset_b - PLATE_H - BOTTOM_BAND)
	p.position = to
	layer.add_child(p)
	## 金色内衬线(决赛日)
	var gl := ColorRect.new()
	gl.color = Color("#c9a24a")
	gl.size = Vector2(PLATE_W - 12.0, 2.0)
	gl.position = Vector2(6.0, PLATE_H - 8.0)
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(gl)
	var av := MatchCard.avatar(str(cd.get("pid", "")), AV, right)
	av.position = Vector2(10.0 if not right else PLATE_W - AV - 10.0, (PLATE_H - AV) * 0.5 - 2.0)
	p.add_child(av)
	var tx: float = 10.0 + AV + 10.0 if not right else 12.0
	var tw: float = PLATE_W - AV - 32.0
	var al := HORIZONTAL_ALIGNMENT_LEFT if not right else HORIZONTAL_ALIGNMENT_RIGHT
	var nm := Ctx.title_lbl(str(cd.get("name", "")) if str(cd.get("name", "")) != "" else "—", 26, COL_TEXT)
	nm.horizontal_alignment = al
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size = Vector2(tw, 32)
	nm.position = Vector2(tx, 8)
	Ctx.outline(nm, 6)
	p.add_child(nm)
	var badge := str(cd.get("title", ""))
	var origin := str(cd.get("origin", ""))
	var line := origin if badge == "" else ((Lang.t("%s（%s）") % [Lang.t(origin), Lang.t(badge)]) if origin != "" else badge)
	var y := 42.0
	for row in [[line, 17, Color("#ffd668")], [str(cd.get("record", "")), 15, COL_DIM]]:
		if str(row[0]) == "":
			continue
		var l := Label.new()
		l.text = str(row[0])
		l.add_theme_font_size_override("font_size", int(row[1]))
		l.add_theme_color_override("font_color", row[2])
		Ctx.outline(l, 4)
		l.horizontal_alignment = al
		l.clip_text = true
		l.size = Vector2(tw, 22)
		l.position = Vector2(tx, y)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
		Lang.fit_font(l, tw, int(row[1]), 11)
		y += 22.0
	_n["plate_" + side] = p
	if settle:
		return
	var from := to + Vector2(-(PLATE_W + 60.0) if not right else PLATE_W + 60.0, 0.0)
	var t0: float = T_PLATE + (0.0 if not right else 0.08)
	intro._slide(p, from, to, t0, T_PLATE_HIT - T_PLATE, true)
	## 落地: 扬尘(lane_map_intro 的 Dust)+ 震屏
	var du := LMI.Dust.new()
	du.size = Vector2(PLATE_W + 40.0, 60.0)
	du.position = to + Vector2(-20.0, PLATE_H - 50.0)
	du.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(du)
	intro.tracks.append({"k": "dust", "node": du, "t0": t0 + (T_PLATE_HIT - T_PLATE) * 0.7, "dur": 0.55})
	ftracks.append({"k": "shake", "t0": t0 + (T_PLATE_HIT - T_PLATE) * 0.7, "dur": 0.22, "amp": 5.0})
	intro._sfx("g_crit", t0 + (T_PLATE_HIT - T_PLATE) * 0.7, 0.55, 0.65 if not right else 0.6)


## 中间 VS 盾徽: 从天砸下(冲击环 + 大震) → 停一下 → 缩小往上飞走、淡掉(本路的小盾徽 2.2 秒起由平时那套出)
func _build_crest() -> void:
	var tex: Texture2D = load(LMI.CREST) if ResourceLoader.exists(LMI.CREST) else null
	if tex == null:
		return
	var c := TextureRect.new()
	c.name = N_CREST
	c.texture = tex
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(160, 160)
	c.pivot_offset = c.size * 0.5
	var at := Vector2(vp.x * 0.5, (vp.y - inset_b) * 0.47)
	c.position = at - c.size * 0.5
	c.modulate.a = 0.0
	layer.add_child(c)
	var ring := Ring.new()
	ring.size = Vector2(640, 640)
	ring.position = at - ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ring)
	ftracks.append({"k": "crest", "node": c, "at": at, "t0": T_CREST})
	ftracks.append({"k": "ring", "node": ring, "t0": T_CREST_HIT, "dur": 0.5})
	ftracks.append({"k": "shake", "t0": T_CREST_HIT, "dur": 0.3, "amp": 9.0})
	intro._sfx("g_shield_break", T_CREST_HIT, 0.75, 0.8)
	intro._sfx("match_found", T_CREST_HIT + 0.05, 0.5)


## 战果幕顶上的记分牌: 「名字  金字比分  名字」; 平时那块「我方 x : y 对方」的板子与那行字留着(门禁 / 读屏), 画面让给这一块
func _build_score() -> void:
	for nm in ["LaneSettleRecord"]:
		var l := intro.root.find_child(nm, true, false) as Label
		if l != null:
			l.self_modulate.a = 0.0
	for c in intro.root.get_children():
		if c is Panel and c.get_parent() == intro.root and c.position.y <= 8.0:
			(c as Panel).self_modulate.a = 0.0       # 平时那块记分牌底板
	var eggs := intro.root.find_child("LaneSettleEggs", true, false) as Label
	var lane: String = intro.lane
	var win_lr := "right" if str(intro.battle._dl_pending_loser) == "left" else "left"
	var lr: Dictionary = (GameState.lane_results as Dictionary) if GameState != null and GameState.lane_results is Dictionary else {}
	var before := [0, 0]
	for k in lr.keys():
		if str(k) == lane:
			continue
		if str(lr[k]) == "left":
			before[0] += 1
		else:
			before[1] += 1
	var after := before.duplicate()
	after[0 if win_lr == "left" else 1] += 1
	var bw: float = minf(720.0, vp.x - 200.0)
	var bd := Panel.new()
	bd.name = N_SCORE
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.92)
	sb.set_border_width_all(3)
	sb.border_color = Color("#c9a24a")
	sb.set_corner_radius_all(4)
	bd.add_theme_stylebox_override("panel", sb)
	bd.size = Vector2(bw, 96)
	bd.position = Vector2(roundf((vp.x - bw) * 0.5), 4)
	layer.add_child(bd)
	var cx := bw * 0.5
	for i in 2:
		var side: String = ["left", "right"][i]
		var n := Ctx.title_lbl(str(names.get("l" if i == 0 else "r", "")), 26, COL_BLUE.lerp(Color.WHITE, 0.35) if i == 0 else COL_RED.lerp(Color.WHITE, 0.35))
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT
		n.size = Vector2(cx - 110.0, 40)
		n.position = Vector2(12.0 if i == 0 else cx + 98.0, 28)
		Ctx.outline(n, 6)
		bd.add_child(n)
		var d := Ctx.title_lbl("0", 60, COL_GOLD)
		d.name = N_DIGIT + side
		d.size = Vector2(60, 84)
		d.pivot_offset = Vector2(30, 42)
		d.position = Vector2(cx + (-88.0 if i == 0 else 28.0), 6)
		bd.add_child(d)
		Ctx.set_digit(d, int(before[i]), int(before[i]) >= int(before[1 - i]))
		_n["digit_" + side] = d
	var colon := Ctx.title_lbl(":", 48, COL_GOLD)
	colon.size = Vector2(40, 84)
	colon.position = Vector2(cx - 20.0, 2)
	bd.add_child(colon)
	if eggs != null:
		eggs.self_modulate.a = 0.0     # 「龟蛋生命 我方 / 对方」: 看别人的比赛没有「我方」; 字留着(门禁 / 读屏)
	var wi: int = 0 if win_lr == "left" else 1
	ftracks.append({"k": "flip", "node": _n["digit_" + win_lr], "t0": T_FLIP, "dur": 0.24, "v": int(after[wi]),
		"gold": int(after[wi]) >= int(after[1 - wi]), "other": _n["digit_" + ("right" if wi == 0 else "left")],
		"ov": int(after[1 - wi]), "ogold": int(after[1 - wi]) >= int(after[wi]), "done": false})
	intro._sfx("ui_click", T_FLIP + 0.12, 0.9, 1.3)


## 战果章: 看别人的比赛 ⇒「X 赢得上路」(金色); 自己的比赛照旧「本战场胜利 / 失败」
func _restamp() -> void:
	if me != "":
		return
	var res := intro.root.find_child("LaneSettleResult", true, false) as Label
	if res == null:
		return
	var win_lr := "right" if str(intro.battle._dl_pending_loser) == "left" else "left"
	var who := str(names.get("l" if win_lr == "left" else "r", ""))
	if who == "":
		return
	res.text = Lang.t("%s 赢得%s") % [who, Lang.t(str(Ctx.LANE_SHORT.get(intro.lane, "")))]
	res.add_theme_color_override("font_color", COL_GOLD)
	res.add_theme_font_size_override("font_size", 30)


# ══════════════════════════════════════════════════════════════════════
#  摆: lane_map_intro.pose 末尾调
# ══════════════════════════════════════════════════════════════════════
func pose(t: float) -> void:
	var shake := Vector2.ZERO
	for tr in ftracks:
		var x: float = (t - float(tr["t0"])) / maxf(0.001, float(tr.get("dur", 1.0)))
		match str(tr["k"]):
			"ribbon":
				var rib: Control = tr["node"]
				var k := clampf(x, 0.0, 1.0)
				rib.scale = Vector2(maxf(0.02, Ctx.ease_back(k)) if x > 0.0 else 0.02, 1.0)
				rib.modulate.a = clampf(x * 4.0, 0.0, 1.0)
			"crest":
				var c: TextureRect = tr["node"]
				var at: Vector2 = tr["at"]
				var t0: float = float(tr["t0"])
				if t < t0:
					c.modulate.a = 0.0
				elif t < T_CREST_HIT:
					var k1: float = (t - t0) / (T_CREST_HIT - t0)
					c.modulate.a = clampf(k1 * 3.0, 0.0, 1.0)
					c.scale = Vector2.ONE * lerpf(3.2, 1.0, k1 * k1)
					c.position = at - c.size * 0.5 + Vector2(0, -260.0 * (1.0 - k1 * k1))
				elif t < T_CREST_FLY:
					var k2: float = clampf((t - T_CREST_HIT) / 0.16, 0.0, 1.0)
					c.modulate.a = 1.0
					c.scale = Vector2.ONE * (1.0 + 0.18 * sin(k2 * PI))       # 砸下那一下回弹
					c.position = at - c.size * 0.5
				else:
					var k3: float = Ctx.ease_out(clampf((t - T_CREST_FLY) / 0.5, 0.0, 1.0))
					c.scale = Vector2.ONE * lerpf(1.0, 0.35, k3)
					c.position = at - c.size * 0.5 + Vector2(0, lerpf(0.0, -(at.y - 120.0), k3))
					c.modulate.a = 1.0 - k3
			"ring":
				var r: Ring = tr["node"]
				r.prog = x
				r.queue_redraw()
			"shake":
				if x > 0.0 and x < 1.0:
					var amp: float = float(tr["amp"]) * (1.0 - x)
					shake += Vector2(sin(x * 53.0) * amp, cos(x * 41.0) * amp * 0.6)
			"flip":
				## 翻牌: 前半段压扁(旧数字), 一半时换成新数字, 后半段弹开
				var d: Label = tr["node"]
				if x <= 0.0:
					d.scale = Vector2.ONE
				elif x < 0.5:
					d.scale = Vector2(1.0, maxf(0.05, 1.0 - x * 2.0))
				else:
					if not bool(tr["done"]):
						tr["done"] = true
						Ctx.set_digit(d, int(tr["v"]), bool(tr["gold"]))
						Ctx.set_digit(tr["other"], int(tr["ov"]), bool(tr["ogold"]))
					d.scale = Vector2(1.0, minf(1.0, Ctx.ease_back(clampf((x - 0.5) * 2.0, 0.0, 1.0)))) if x < 1.0 else Vector2.ONE
	if layer != null and is_instance_valid(layer):
		layer.position = shake.round()
		## 桌面地图(3D 视口贴图)跟着一起震
		if intro.table_view != null and is_instance_valid(intro.table_view):
			intro.table_view.position = shake.round()


## 金边框: 整屏内缩一圈的金线 + 四角亮金折角(决赛日)
class GoldFrame extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_rect(r, Color("#2a1606"), false, 6.0)
		draw_rect(r, Color("#c9a24a"), false, 3.0)
		var L := 34.0
		var w := 6.0
		var hi := Color("#ffd668")
		for cx in [r.position.x, r.end.x]:
			for cy in [r.position.y, r.end.y]:
				var sx := 1.0 if cx == r.position.x else -1.0
				var sy := 1.0 if cy == r.position.y else -1.0
				var o := Vector2(cx, cy) - Vector2(sx, sy) * 2.0
				draw_rect(Rect2(o.x if sx > 0 else o.x - L, o.y - (0.0 if sy > 0 else w), L, w).abs(), hi)
				draw_rect(Rect2(o.x - (0.0 if sx > 0 else w), o.y if sy > 0 else o.y - L, w, L).abs(), hi)


## 冲击环: 盾徽砸下那一下往外推一圈金白光, 越推越细越淡
class Ring extends Control:
	var prog := 0.0

	func _draw() -> void:
		if prog <= 0.0 or prog >= 1.0:
			return
		var e := 1.0 - pow(1.0 - prog, 3.0)
		var c := size * 0.5
		var rad := lerpf(50.0, size.x * 0.5, e)
		var a := 1.0 - prog
		draw_arc(c, rad, 0.0, TAU, 72, Color(1.0, 0.92, 0.6, a * 0.9), maxf(2.0, 14.0 * (1.0 - prog)))
		draw_arc(c, rad * 0.82, 0.0, TAU, 72, Color(1.0, 0.75, 0.3, a * 0.5), maxf(1.0, 6.0 * (1.0 - prog)))
