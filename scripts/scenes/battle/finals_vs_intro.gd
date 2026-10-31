extends RefCounted
## finals_vs_intro.gd — 周日开播前一拍「对手入场」(方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C ① · G6)。
##
## 照 docs/plans/ref/20261031-周日赛事参考/仪式与奖励/研究笔记.md §3.1 的时间轴(约 6 秒, 看别人与看自己相同):
##   0.00  两条斜带从左右扫入(左蓝 / 右红; 决赛整套换金)
##   0.30  顶上轮次名「冠军杯赛 · 半决赛」+ 第几场
##   0.40  双方名牌落位: 头像 + 名字 + 头衔 + 来历「B 组冠军」+ 本周战绩(入口给了才写)
##   0.80  中央对阵徽章砸下(屏震 2px)
##   1.00~ 双方锁定的阵容按路逐只翻出(先闪白再显形, 每只隔 0.1 秒)
##   1.60  迷你对阵: 本场那条线点亮(一明一暗地呼吸)
##   2.60  一行实话「双方阵容已锁定 · 服务器实时演算」(异步也照样有这一拍, 10-1)
##   3.00~ 3 → 2 → 1(每拍 0.66 秒)
##   5.00  「开战」0.8 秒 → 5.8 起淡出, 6.2 收掉
## ★动画不用 tween: `pose(t)` 按时刻把全部节点摆好, 每帧按帧间隔推 t —— 门禁摆到任意时刻去量, 不靠 tween 在无头 CI 上推进(CLAUDE.md §3.5)。
## ★不碰播放器: 开场幕布(三路总览 + 对阵预览, 共 10 秒)在下面照常走, 这一层整屏盖住它; 6.2 秒收掉时幕布还剩约 4 秒的本路对阵, 接着开打。
##   ⇒ 开播排期(服务端每场留 30 秒开场与幕布)一秒不变, 所有人仍在同一条时间线上。

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")

const DUR := 6.2
const T_TITLE := 0.30
const T_CARDS := 0.40
const T_CREST := 0.80
const T_CHIPS := 1.00
const CHIP_GAP_T := 0.10
const T_MINI := 1.60
const T_NOTE := 2.60
const T_COUNT := 3.00
const COUNT_STEP := 0.66
const T_GO := 5.00
const T_OUT := 5.80

const CREST := "res://assets/sprites/finals/vs-crest.png"
const CREST_GOLD := "res://assets/sprites/finals/vs-crest-gold.png"
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const COL_GOLD := Color("#ffd93d")
const COL_GOLD_DIM := Color("#c9a24a")
const COL_BLUE := Color("#2b5aa8")
const COL_RED := Color("#a8323e")
## 名牌头像 / 阵容头像: 宽屏(手机 1560)与窄屏(iPad 960)两档 —— 整屏要「满」(C-5 / 1-2 全屏对手名牌)
const AVATAR := 168.0
const AVATAR_NARROW := 136.0
const CHIP := 72.0
const CHIP_NARROW := 60.0
const CHIP_SEP := 10.0
const NARROW_W := 1280.0
const LAYOUT_H := 720.0             # 版心高(手机横屏的逻辑高)
const TXT_GO := "开战"

## 节点名(门禁按名字找)
const N_ROOT := "FinalsVS"
const N_TITLE := "VSTitle"
const N_SUB := "VSSub"
const N_CARD := "VSCard_"          # + left / right
const N_NAME := "VSName_"
const N_ORIGIN := "VSOrigin_"
const N_RECORD := "VSRecord_"
const N_CREST := "VSCrest"
const N_CHIP := "VSChip_"          # + left_0 …; meta pid
const N_MINI := "VSMini"           # meta lit = "r-m"
const N_NOTE := "VSNote"
const N_COUNT := "VSCount"
const N_GO := "VSGo"
const N_BAR_DOCK := "VSBarDock"       # 全局决赛日小条的停靠位

var root: Control = null
var t := 0.0
var done := false
var info: Dictionary = {}
var on_done: Callable = Callable()
var _n: Dictionary = {}
var _chips: Array = []              # [Control, 翻出时刻, 白闪层]
var _vp := Vector2.ZERO
var _av := AVATAR
var _cp := CHIP
var _ticker = null                  # 每帧钟(Ctx.start_ticker); 不标类型: 根释放后这里是失效实例


## `info` = {title, sub, gold, cards: {left: {name, pid, origin, record, title}, right}, lineups: {left: [[路, [{pid, minion}]]], right},
##   mini: {n, r, m}, note}。纯数据, 由 replay_controls 从入口与录像开局状态拼好(`intro_info`)。
func build(parent: Control, inf: Dictionary, vp: Vector2) -> Control:
	info = inf
	_vp = vp
	var wide: bool = vp.x >= NARROW_W
	_av = AVATAR if wide else AVATAR_NARROW
	_cp = CHIP if wide else CHIP_NARROW
	root = Control.new()
	root.name = N_ROOT
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = vp
	root.mouse_filter = Control.MOUSE_FILTER_STOP          # 盖住下面的幕布: 幕布在观赛里本来就点不动, 这里也不让点穿
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(root)
	var gold := bool(info.get("gold", false))
	var bg := Control.new()
	bg.name = "VSBands"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = vp
	bg.draw.connect(_draw_bands.bind(bg))
	root.add_child(bg)
	_n["bands"] = bg
	## 版心: 按 720 高排版, 比 720 高的屏(iPad 逻辑 1280×960)整块竖向居中(不在下面空一截)
	var body := Control.new()
	body.name = "VSBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = Vector2(vp.x, minf(vp.y, LAYOUT_H))
	body.position = Vector2(0.0, roundf((vp.y - body.size.y) * 0.5))
	root.add_child(body)
	_n["body"] = body
	var cx: float = roundf(vp.x * 0.5)
	## 顶上轮次名(决赛金字)
	var tl := Ctx.title_lbl(str(info.get("title", "")), 36, COL_GOLD if gold else Color("#ffe7a0"))
	tl.name = N_TITLE
	tl.size = Vector2(vp.x, 48)
	tl.position = Vector2(0, 18)
	body.add_child(tl)
	_n["title"] = tl
	var sub := str(info.get("sub", ""))
	if sub != "":
		var sl := SettleScreenS._lbl(sub, 24, Color("#c9d8ea"), HORIZONTAL_ALIGNMENT_CENTER)
		sl.name = N_SUB
		Ctx.outline(sl, 6)
		sl.size = Vector2(vp.x, 32)
		sl.position = Vector2(0, 72)
		body.add_child(sl)
		_n["sub"] = sl
	## 双方名牌
	var cw: float = clampf(vp.x * 0.30, 260.0, 400.0)
	for side in ["left", "right"]:
		var ccx: float = roundf(vp.x * (0.25 if side == "left" else 0.75))
		var ch: float = _av + 8.0 + 140.0
		_build_card(side, Rect2(ccx - cw * 0.5, 104.0, cw, ch))
		_build_lineup(side, ccx, 104.0 + ch + 8.0)
	## 中央对阵徽章 + 倒数
	var crest := PixelKey.sprite(CREST_GOLD if gold else CREST, 3 if vp.x >= 1280.0 else 2)   # 宽屏中间空, ×3; iPad ×2
	crest.name = N_CREST
	crest.pivot_offset = crest.size * 0.5
	crest.position = Vector2(cx - crest.size.x * 0.5, 116.0 if wide else 132.0)
	body.add_child(crest)
	_n["crest"] = crest
	_n["crest_pos"] = crest.position
	bg.set_meta("crest_cy", body.position.y + crest.position.y + crest.size.y * 0.5)
	var vs := Ctx.title_lbl("VS", 72 if crest.size.x > 150.0 else 48, Color("#fff6dc"))
	vs.size = crest.size
	vs.position = Vector2.ZERO
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crest.add_child(vs)
	## 迷你对阵(本场那条线点亮)
	var mini: Dictionary = info.get("mini", {}) if info.get("mini", {}) is Dictionary else {}
	if int(mini.get("n", 0)) >= 2 and int(mini.get("r", 0)) >= 1:
		var mc := Control.new()
		mc.name = N_MINI
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		## 宽屏: 盾徽正下方居中(两张名牌之间那一栏); 窄屏(iPad)中间那一栏太窄 ⇒ 放到两边阵容下面整屏居中, 同样放大
		if wide:
			mc.size = Vector2(340, 150)
			mc.position = Vector2(roundf(cx - mc.size.x * 0.5), crest.position.y + crest.size.y + 18.0)
		else:
			mc.size = Vector2(340, 96)
			mc.position = Vector2(roundf(cx - mc.size.x * 0.5), 104.0 + _av + 8.0 + 140.0 + 8.0 + 2.0 * (_cp + 10.0) + 10.0)
		mc.set_meta("lit", "%d-%d" % [int(mini["r"]), int(mini.get("m", 0))])
		mc.set_meta("pulse", 1.0)
		mc.draw.connect(_draw_mini.bind(mc, mini, gold))
		body.add_child(mc)
		_n["mini"] = mc
	## 全局决赛日小条的停靠位: 两边阵容下面、底下那一行上面, 正中(整屏 VS 期间小条不压名牌 / 盾徽 / 阵容)
	var dock_y: float = 104.0 + _av + 8.0 + 140.0 + 8.0 + 2.0 * (_cp + 10.0) + 6.0
	if not wide and _n.has("mini"):
		dock_y = (_n["mini"] as Control).position.y + (_n["mini"] as Control).size.y + 6.0
	var dock := Ctx.bar_dock(N_BAR_DOCK, Rect2(roundf(cx - Ctx.BAR_W * 0.5), dock_y, Ctx.BAR_W, Ctx.BAR_H))
	body.add_child(dock)
	_n["bar_dock"] = dock
	var note := SettleScreenS._lbl(str(info.get("note", Ctx.TXT_LOCKED)), 24, Color("#c9d8ea"), HORIZONTAL_ALIGNMENT_CENTER)
	note.name = N_NOTE
	Ctx.outline(note, 6)
	note.size = Vector2(vp.x, 32)
	note.position = Vector2(0, vp.y - 72.0)
	root.add_child(note)
	_n["note"] = note
	## 倒数 / 开战: 大字美术字(结算屏同一套做法); 标签的字照旧(3 / 2 / 1 /「开战」), 自己透明
	var cnt := Ctx.title_lbl("3", 96, Color("#fff6dc"))
	cnt.name = N_COUNT
	cnt.size = Vector2(240, 120)
	cnt.pivot_offset = cnt.size * 0.5
	cnt.position = Vector2(cx - 120.0, crest.position.y + crest.size.y * 0.5 - 60.0)
	body.add_child(cnt)
	Ctx.set_digit(cnt, 3, true)
	_n["count"] = cnt
	var go := Ctx.title_lbl(TXT_GO, 72, COL_GOLD)
	go.name = N_GO
	go.size = Vector2(vp.x, 120)
	go.pivot_offset = go.size * 0.5
	go.position = Vector2(0, roundf(body.size.y * 0.5 - 60.0))
	body.add_child(go)
	Ctx.dress_art(go)
	_n["go"] = go
	t = 0.0
	pose(0.0)
	_disconnect()                        # 同一个对象再搭一次(换比例)⇒ 钟跟着挂到新根上
	_ticker = Ctx.start_ticker(root, self)
	return root


func _build_card(side: String, r: Rect2) -> void:
	var gold := bool(info.get("gold", false))
	var cd: Dictionary = (info.get("cards", {}) as Dictionary).get(side, {})
	var card := Control.new()
	card.name = N_CARD + side
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = r.position
	card.size = r.size
	card.pivot_offset = card.size * 0.5
	(_n["body"] as Control).add_child(card)
	_n["card_" + side] = card
	_n["card_pos_" + side] = r.position
	## 头像框(直角 + 2px 边 + 一圈内阴影; 左蓝右红, 决赛金)
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a1422")
	sb.set_border_width_all(3)
	sb.border_color = COL_GOLD_DIM if gold else (Color("#5f8fe0") if side == "left" else Color("#e0606e"))
	sb.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(_av + 8.0, _av + 8.0)
	frame.position = Vector2(roundf((r.size.x - frame.size.x) * 0.5), 0.0)
	card.add_child(frame)
	var av := MatchCard.avatar(str(cd.get("pid", "")), _av, side == "right")
	av.position = Vector2(4, 4)
	frame.add_child(av)
	var y := frame.size.y + 6.0
	var nm := SettleScreenS._lbl(str(cd.get("name", "—")), 40, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.name = N_NAME + side
	Ctx.outline(nm, 8)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size = Vector2(r.size.x, 40)
	nm.position = Vector2(0, y)
	card.add_child(nm)
	y += nm.size.y                                  # 进树后按字体的最小高撑开 ⇒ 按实际高往下排
	var badge := str(cd.get("title", ""))
	var origin := str(cd.get("origin", ""))
	var line := origin if badge == "" else (badge + ("  ·  " + origin if origin != "" else ""))
	if line != "":
		var ol := SettleScreenS._lbl(line, 28, COL_GOLD if gold else Color("#ffd668"), HORIZONTAL_ALIGNMENT_CENTER)
		ol.name = N_ORIGIN + side
		Ctx.outline(ol, 6)
		ol.size = Vector2(r.size.x, 28)
		ol.position = Vector2(0, y)
		card.add_child(ol)
		if badge != "":
			ol.set_meta("badge", badge)
		y += ol.size.y
	var rec := str(cd.get("record", ""))
	if rec != "":
		var rl := SettleScreenS._lbl(rec, 24, Color("#c9d8ea"), HORIZONTAL_ALIGNMENT_CENTER)
		rl.name = N_RECORD + side
		Ctx.outline(rl, 6)
		rl.size = Vector2(r.size.x, 26)
		rl.position = Vector2(0, y)
		card.add_child(rl)


## 一边的锁定阵容: 每一路一行「上路 [龟][龟][小将]」, 以名牌中线居中。
func _build_lineup(side: String, ccx: float, y0: float) -> void:
	var rows: Array = (info.get("lineups", {}) as Dictionary).get(side, [])
	var k := 0
	var y := y0
	for row in rows:
		var ln := str(row[0])
		var units: Array = row[1]
		if units.is_empty():
			continue
		var lab_w := 64.0
		var w: float = lab_w + float(units.size()) * (_cp + CHIP_SEP) - CHIP_SEP
		var x: float = roundf(ccx - w * 0.5)
		var ll := SettleScreenS._lbl(str(Ctx.LANE_SHORT.get(ln, ln)), 24, Color("#c9d8ea"), HORIZONTAL_ALIGNMENT_LEFT)
		Ctx.outline(ll, 6)
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ll.size = Vector2(lab_w, _cp)
		ll.position = Vector2(x, y)
		(_n["body"] as Control).add_child(ll)
		_n["lane_lb_%s_%d" % [side, k]] = ll
		x += lab_w
		for u in units:
			var chip := _chip(u, side)
			chip.name = "%s%s_%d" % [N_CHIP, side, k]
			chip.position = Vector2(x, y)
			(_n["body"] as Control).add_child(chip)
			var flash := ColorRect.new()
			flash.color = Color(1, 1, 1, 0)
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flash.size = chip.size
			chip.add_child(flash)
			_chips.append([chip, T_CHIPS + CHIP_GAP_T * float(k), flash])     # 两边第 k 只同一刻翻(对称)
			x += _cp + CHIP_SEP
			k += 1
		y += _cp + 10.0


func _chip(u: Dictionary, side: String) -> Control:
	if bool(u.get("minion", false)):
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0a1422")
		sb.set_border_width_all(1)
		sb.border_color = Color("#3a4a5c")
		sb.set_corner_radius_all(0)
		pc.add_theme_stylebox_override("panel", sb)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.custom_minimum_size = Vector2(_cp, _cp)
		pc.size = Vector2(_cp, _cp)
		pc.set_meta("pid", "minion")
		var tr := TextureRect.new()
		var mp := MinionCodex.portrait_path(str(u.get("kind", "front")))      # 与图鉴 / 幕布同一张(按前排 / 后排 / 精英 / 援军)
		tr.texture = load(mp) if mp != "" else null
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.flip_h = side == "right"
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(tr)
		return pc
	var av := MatchCard.avatar(str(u.get("pid", "")), _cp, side == "right")
	av.size = Vector2(_cp, _cp)
	av.set_meta("pid", str(u.get("pid", "")))
	return av


# ─────────────────────────────── 动 ───────────────────────────────

## 倒数此刻显示几(3/2/1); 不在倒数段 = 0。
static func count_at(x: float) -> int:
	if x < T_COUNT or x >= T_GO:
		return 0
	return 3 - int(floor((x - T_COUNT) / COUNT_STEP))


func pose(x: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	var out := 1.0 - Ctx.k01(x, T_OUT, DUR - T_OUT)
	root.modulate.a = out
	(_n["bands"] as Control).set_meta("p", Ctx.ease_out(Ctx.k01(x, 0.0, 0.25)))
	(_n["bands"] as Control).queue_redraw()
	var tl: Control = _n["title"]
	tl.modulate.a = Ctx.k01(x, T_TITLE, 0.18)
	tl.position.y = 18.0 - 18.0 * (1.0 - Ctx.ease_out(Ctx.k01(x, T_TITLE, 0.25)))
	if _n.has("sub"):
		(_n["sub"] as Control).modulate.a = Ctx.k01(x, T_TITLE + 0.12, 0.2)
	for side in ["left", "right"]:
		var c: Control = _n["card_" + side]
		var p := Ctx.k01(x, T_CARDS, 0.28)
		var p0: Vector2 = _n["card_pos_" + side]
		c.position = p0 + Vector2((-1.0 if side == "left" else 1.0) * 220.0 * (1.0 - Ctx.ease_back(p)), 0.0)
		c.modulate.a = Ctx.k01(x, T_CARDS, 0.10)
	## 徽章: 从 1.7 倍砸到 1 倍, 落地那 0.15 秒左右抖 2px
	var cr: Control = _n["crest"]
	var pc := Ctx.k01(x, T_CREST, 0.18)
	cr.scale = Vector2.ONE * Ctx.mix(1.7, 1.0, Ctx.ease_out(pc))
	cr.modulate.a = Ctx.k01(x, T_CREST, 0.06)
	var shake := 0.0
	if x >= T_CREST + 0.18 and x < T_CREST + 0.33:
		shake = 2.0 if int(floor(x * 60.0)) % 2 == 0 else -2.0
	cr.position = (_n["crest_pos"] as Vector2) + Vector2(shake, 0.0)
	root.position = Vector2(0.0, shake * 0.5)
	## 阵容逐只翻出: 先一片白(0.08 秒)再显形; 翻的同时横向压扁再展开(像翻牌)
	for it in _chips:
		var ch: Control = it[0]
		var t0: float = it[1]
		var fl: ColorRect = it[2]
		var q := Ctx.k01(x, t0, 0.16)
		ch.modulate.a = 1.0 if x >= t0 else 0.0
		ch.pivot_offset = ch.size * 0.5
		ch.scale = Vector2(maxf(0.05, absf(1.0 - 2.0 * q)), 1.0)       # 白背面压扁 → 侧立 → 正面展开
		fl.color.a = (1.0 if q < 0.5 else 1.0 - Ctx.k01(x, t0 + 0.08, 0.12)) if x >= t0 else 0.0
	for key in _n:
		if str(key).begins_with("lane_lb_"):
			(_n[key] as Control).modulate.a = Ctx.k01(x, T_CHIPS - 0.1, 0.2)
	if _n.has("mini"):
		var mc: Control = _n["mini"]
		mc.modulate.a = Ctx.k01(x, T_MINI, 0.3)
		mc.set_meta("pulse", 0.55 + 0.45 * Ctx.wave((x - T_MINI) * 1.0) if x >= T_MINI else 1.0)
		mc.queue_redraw()
	(_n["note"] as Control).modulate.a = Ctx.k01(x, T_NOTE, 0.3)
	var cnt: Label = _n["count"]
	var c := count_at(x)
	cnt.visible = c > 0
	if c > 0:
		if cnt.text != str(c):
			Ctx.set_digit(cnt, c, true)
		var ph := fmod(x - T_COUNT, COUNT_STEP) / COUNT_STEP
		cnt.scale = Vector2.ONE * Ctx.mix(1.6, 1.0, Ctx.ease_out(clampf(ph * 3.0, 0.0, 1.0)))
		cnt.modulate.a = 1.0 - clampf((ph - 0.75) * 4.0, 0.0, 1.0)
	cr.self_modulate.a = 0.35 if c > 0 or x >= T_GO else 1.0
	var go: Control = _n["go"]
	go.visible = x >= T_GO
	var pg := Ctx.k01(x, T_GO, 0.2)
	go.scale = Vector2.ONE * Ctx.mix(2.0, 1.0, Ctx.ease_back(pg))
	go.modulate.a = pg


func _tick(dt: float) -> void:
	if done or root == null or not is_instance_valid(root):
		_disconnect()
		return
	t += dt
	pose(t)
	if t >= DUR:
		finish()


## 收掉(播完 / 被叫停)。
func finish() -> void:
	if done:
		return
	done = true
	_disconnect()
	## 停靠位当场退组(queue_free 要到这一帧末才离树; 这一帧里观战页那一块已经亮了, 两块同时在组里小条会挑错)
	if _n.has("bar_dock") and is_instance_valid(_n["bar_dock"]):
		(_n["bar_dock"] as Node).remove_from_group(Ctx.BAR_DOCK)
	if root != null and is_instance_valid(root):
		root.queue_free()
	if on_done.is_valid():
		on_done.call()


func _disconnect() -> void:
	Ctx.stop_ticker(_ticker)
	_ticker = null


# ─────────────────────────────── 画 ───────────────────────────────

## 斜带: 左右两块平行四边形从屏外扫进来, 在中线处一道斜缝(左蓝右红; 决赛两边都是金)。两级阶梯明暗, 不做平滑渐变。
func _draw_bands(c: Control) -> void:
	var s := c.size
	var p := float(c.get_meta("p", 1.0))
	var gold := bool(info.get("gold", false))
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.06, 0.96))
	var slant := 90.0
	var cx := s.x * 0.5
	## 决赛: 两边都是近黑的暖底(金色留给边线 / 徽章 / 字 / 光芒, 底色发棕会显脏)
	var lc: Color = Color("#22180a") if gold else Color("#14284e")
	var rc: Color = Color("#2c1e0a") if gold else Color("#4e141c")
	var off_l := -(cx + slant) * (1.0 - p)
	var off_r := (cx + slant) * (1.0 - p)
	for band in [[lc, off_l, true], [rc, off_r, false]]:
		var col: Color = band[0]
		var o: float = band[1]
		var pts: PackedVector2Array
		if bool(band[2]):
			pts = PackedVector2Array([Vector2(o, 0), Vector2(cx + slant * 0.5 + o - 4.0, 0), Vector2(cx - slant * 0.5 + o - 4.0, s.y), Vector2(o, s.y)])
		else:
			pts = PackedVector2Array([Vector2(cx + slant * 0.5 + o + 4.0, 0), Vector2(s.x + o, 0), Vector2(s.x + o, s.y), Vector2(cx - slant * 0.5 + o + 4.0, s.y)])
		c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))
		## 中间亮一档的横带(名牌那一块), 两级阶梯
		var mid := PackedVector2Array()
		for q in pts:
			mid.append(Vector2(q.x, clampf(q.y, s.y * 0.14, s.y * 0.62)))
		c.draw_colored_polygon(mid, Color(col.r * 1.35, col.g * 1.35, col.b * 1.35, 0.35))
	## 斜纹底纹(两边各一套, 跟着斜带一起扫进来)
	Ctx.draw_hatch(c, Rect2(off_l, 0, cx + slant * 0.5, s.y), Color(1, 1, 1, 0.045 * p), 16.0)
	Ctx.draw_hatch(c, Rect2(cx - slant * 0.5 + off_r, 0, s.x - cx + slant * 0.5, s.y), Color(1, 1, 1, 0.045 * p), 16.0)
	## 盾徽背后一圈光芒(8 道, 方向写死; 本目录不许裸调 sin / cos): 普通场淡白, 决赛金 + 中间那道斜缝描金
	var ctr := Vector2(cx, float(c.get_meta("crest_cy", s.y * 0.3)))
	Ctx.draw_rays(c, ctr, s.y * 0.42, 70.0, Color(1.0, 0.82, 0.30, 0.10 * p) if gold else Color(0.85, 0.92, 1.0, 0.05 * p))
	if gold:
		c.draw_line(Vector2(cx + slant * 0.5, 0), Vector2(cx - slant * 0.5, s.y), Color(1.0, 0.85, 0.35, 0.9 * p), 3.0)
	## 上下两道金线
	var line := Color("#d8b45a") if not gold else Color("#ffd93d")
	c.draw_rect(Rect2(0, 6, s.x * p, 3), line)
	c.draw_rect(Rect2(s.x * (1.0 - p), s.y - 9, s.x * p, 3), line)


## 迷你对阵: 每一轮一列小格, 格与格之间直角连线; 本场那一格与它两条来路金色(呼吸), 去路一截虚线; 其余暗灰。
func _draw_mini(c: Control, mini: Dictionary, gold: bool) -> void:
	var n := int(mini.get("n", 2))
	var rr := int(mini.get("r", 1))
	var mm := int(mini.get("m", 0))
	var rounds := _B.rounds_for(n)
	var slots := _B.slots_for(n)
	if rounds < 1:
		return
	var s := c.size
	var colw: float = s.x / float(rounds + 1)
	var dim := Color(0.45, 0.52, 0.62, 0.55)
	var hot := (COL_GOLD if gold else Color("#ffe08a"))
	var pulse := float(c.get_meta("pulse", 1.0))
	hot.a = pulse
	var bw := 14.0
	var bh := 8.0
	for r in range(1, rounds + 2):
		var cnt: int = maxi(1, slots >> r) if r <= rounds else 1
		var x: float = colw * (float(r) - 0.5)
		for j in range(cnt):
			var y: float = s.y * (float(j) + 0.5) / float(cnt)
			var lit := r == rr and j == mm
			if r <= rounds:
				var nx: float = colw * (float(r) + 0.5)
				var ny: float = s.y * (float(j / 2) + 0.5) / float(maxi(1, slots >> (r + 1)) if r < rounds else 1)
				var lc: Color = hot if lit else dim
				c.draw_line(Vector2(x + bw * 0.5, y), Vector2(x + colw * 0.5, y), lc, 2.0)
				c.draw_line(Vector2(x + colw * 0.5, y), Vector2(x + colw * 0.5, ny), lc if not lit else Color(hot.r, hot.g, hot.b, hot.a * 0.6), 2.0)
				c.draw_line(Vector2(x + colw * 0.5, ny), Vector2(nx - bw * 0.5, ny), dim, 2.0)
			var box := Rect2(x - bw * 0.5, y - bh * 0.5, bw, bh)
			if r > rounds:
				box = Rect2(x - 6.0, y - 6.0, 12.0, 12.0)
			c.draw_rect(box, Color("#0a1422"))
			c.draw_rect(box, hot if lit else (Color("#c9a24a") if r > rounds else dim), false, 2.0)
	## 本场的两条来路(上一轮那两格)也点亮
	if rr >= 2:
		var px: float = colw * (float(rr - 1) - 0.5)
		var pcnt: int = maxi(1, slots >> (rr - 1))
		for j in [mm * 2, mm * 2 + 1]:
			var y: float = s.y * (float(j) + 0.5) / float(pcnt)
			c.draw_line(Vector2(px + bw * 0.5, y), Vector2(px + colw * 0.5, y), hot, 2.0)
