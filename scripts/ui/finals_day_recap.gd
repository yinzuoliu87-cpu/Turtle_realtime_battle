extends CanvasLayer
## 收盘补看(2026-10-31 方案书 20261031c 块 M ⑧ · G21 / 7-3 Township / C-7 / 5-6 CSR2 / 3-3 Duel Links):
##   没守到最后的人(冠军杯赛决出那一刻不在场), 周日收盘后下次打开主菜单先补那一刻 —— 全屏三拍, 与冠军仪式(块 D)一套风格:
##     竞技场背景压暗 + 转动的光束 + 像素彩带。
##     ① 冠军: 奖杯从天上砸下来(扬尘 + 彩带)→ 冠军头像在冠军框里放大 →「冠军杯赛冠军」像素大字盖章 → 金缎带写名字 → 规模一行
##     ② 最终名次: 领奖台上 3 → 2 → 1 依次落下头像与名字(并列第 3 两人同站), 「你的名次」单独一行高亮、名次数字滚到位
##     ③ 我的比赛: 每轮一张横条牌(轮次 · 对手头像与名字 · 比分滚动 · 胜 / 负章盖下), 每张「重看」; 右上「关闭」
##   前两拍自己往下走; 点屏 = 先跳到这一拍的终态, 已是终态再点 = 下一拍(G8)。只弹一次(按周记在 user://)。
## ★演出按时间算状态(给 t 就能画出那一刻; 跳拍 = 把 t 拨到终态), 不靠 Tween 跑完 —— 门禁直接拨 t 量(CLAUDE.md §3.5, 与冠军仪式同一做法)。
## ★在场守到了(全局层亲眼见到冠军杯赛从没决出到决出)⇒ 记过了, 不弹(finals_day_layer `_recap_mark`)。
## ★窗口: 周日冠军杯赛开赛之后 ~ 周一(对阵图周一还看上周), 周二起不补。
## ★素材: 竞技场背景 / 奖杯 / 领奖台 / 冠军框 / 金缎带 / VS 是对阵图与冠军仪式那一套(同一场赛事的结果, asset_borrow_audit CROSS_OK 有理由);
##   「冠军杯赛冠军」大字是观战结束那一套美术字(assets/sprites/finals/bt-cup-champ.png); 胜 / 负章是结算屏那一套(BigTitle.LANE)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _F := preload("res://scripts/ui/finals_day_feed.gd")
const _W := preload("res://scripts/ui/finals_day_watch.gd")
const _DL := preload("res://scripts/gamedata/phase2_duallane.gd")
const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const FX := preload("res://scripts/scenes/bracket/champion_fx.gd")

const NODE_NAME := "FinalsDayRecap"
const SEEN_PATH := "user://finals_day_seen.json"
const LAYER := 85
const TEX_PODIUM := "res://assets/sprites/bracket/bracket-podium.png"
const TEX_CUP_TITLE := "res://assets/sprites/finals/bt-cup-champ.png"
const STAMP_WIN := "res://assets/sprites/ui/bigtitle/lane_win.png"
const STAMP_LOSE := "res://assets/sprites/ui/bigtitle/lane_lose.png"
const GOLD := Color("#f4c552")
const MENU_SCENE := "res://scenes/MainMenu.tscn"
## 每拍: 入场演完(终态)的时刻 / 自己往下走的时刻(最后一拍不走)。
const BEAT_END := [2.0, 2.9, 0.0]          # 第 3 拍的终态按场数算(`beat_end`)
const BEAT_LEN := [4.4, 5.0, 0.0]
## 领奖台(原件 134×54, ×4): 三块台面的中心 x 与站人的 y(源像素, 量出来的)
const PODIUM_SCALE := 4.0
const STEP_X := {1: 66.0, 2: 31.0, 3: 112.0}
const STEP_Y := {1: 6.0, 2: 18.0, 3: 24.0}

## 门禁读: 走到第几拍 / 这一拍此刻的 t / 每拍的字
var beat := -1
var t := 0.0
var beat_end: Array = BEAT_END.duplicate()
var beats: Array = []
var data: Dictionary = {}
var vp := Vector2(1280, 720)
var _root: Control
var _fx
var _stage: Control
var _flash: ColorRect
var _hint: Label
var _dots: Array = []
var _anims: Array = []
var _rolls: Array = []       # [Label, 起, 止, t0, t1, 格式]
var _burst_at := -1.0
var _burst_c := Vector2.ZERO


# ══════════════════════════════ 看过没有 ══════════════════════════════

static func seen(week: int) -> bool:
	var f := FileAccess.open(SEEN_PATH, FileAccess.READ)
	if f == null:
		return false
	var v = JSON.parse_string(f.get_as_text())
	if not (v is Dictionary) or not ((v as Dictionary).get("recap", null) is Array):
		return false
	return ((v as Dictionary)["recap"] as Array).has(float(week))


static func mark_seen(week: int) -> void:
	var lst: Array = []
	var f := FileAccess.open(SEEN_PATH, FileAccess.READ)
	if f != null:
		var v = JSON.parse_string(f.get_as_text())
		if v is Dictionary and v.get("recap", null) is Array:
			lst = v["recap"]
		f.close()
	if lst.has(float(week)):
		return
	lst.append(float(week))
	while lst.size() > 8:
		lst.pop_front()
	var w := FileAccess.open(SEEN_PATH, FileAccess.WRITE)
	if w != null:
		w.store_string(JSON.stringify({"recap": lst}))


## 此刻该补哪一周(周锚点); 0 = 不在补看窗口里。周日冠军杯赛开赛之后 = 本周; 周一 = 上周。
static func window_week(now: int) -> int:
	var wd: int = _P2.iso_weekday_utc(now)
	if wd == 7 and now >= _M.cup_ts(now):
		return _P2.week_anchor_utc(now)
	if wd == 1:
		return _P2.week_anchor_utc(now) - 7 * 86400
	return 0


# ══════════════════════════════ 弹不弹 ══════════════════════════════

## 主菜单开屏调: 在窗口里、没看过 ⇒ 问那一周(只回调不落缓存), 冠军杯赛决出了 ⇒ 弹。返回 true = 去问了 / 弹了。
static func maybe_show(menu: Node, now: int) -> bool:
	var wk := window_week(now)
	if wk <= 0 or seen(wk) or menu == null:
		return false
	if not _F.override.is_empty():
		var f: Dictionary = _F.feeds()
		return show_for(menu, wk, f["groups"], f["cup"], now)
	if not _SB.enabled():
		return false
	_F.pull_avatars(wk)
	return _SB.fetch_finals_week_cb(wk, func(res: Dictionary) -> void:
		if not is_instance_valid(menu) or not menu.is_inside_tree():
			return
		var cup: Dictionary = res.get("cup", {}) if res.get("cup", null) is Dictionary else {}
		var groups: Array = res.get("buckets", []) if res.get("buckets", null) is Array else []
		show_for(menu, wk, groups, cup, _P2.now_utc()))


static func show_for(menu: Node, wk: int, groups: Array, cup: Dictionary, now: int) -> bool:
	if menu.get_node_or_null(NODE_NAME) != null:
		return false
	## 冠军杯赛没决出(决赛还在开播也算没决出)⇒ 名次表是空的 ⇒ 不弹(判据只在 standings 一处)
	var rows: Array = _M.standings(groups, cup, now)
	if rows.is_empty():
		return false
	var group: Dictionary = {}
	for g in groups:
		if g is Dictionary and int((g as Dictionary).get("me", -1)) >= 0:
			group = g
	var rc = load("res://scripts/ui/finals_day_recap.gd").new()
	rc.data = {"week": wk, "cup": cup, "groups": groups, "group": group, "rows": rows, "now": now}
	mark_seen(wk)
	menu.add_child(rc)
	return true


# ══════════════════════════════ 底座 ══════════════════════════════

func _ready() -> void:
	name = NODE_NAME
	layer = LAYER
	vp = get_viewport().get_visible_rect().size
	_root = Control.new()
	_root.name = "RecapRoot"
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_dim_input)
	add_child(_root)
	var bg := UI.tex_rect(UI.TEX_BG, vp, "ArenaBg")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.42, 0.38, 0.44, 1.0)              # 竞技场压暗(冠军仪式同一组数)
	_root.add_child(bg)
	UI.box(_root, Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.03, 0.45), "Dim")
	_fx = FX.new()
	_fx.size = vp
	_root.add_child(_fx)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.size = vp
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage)
	_flash = UI.box(_root, Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0), "WhiteFlash")
	_hint = UI.label("点击继续", 18, UI.TXT_DIM, true, false, "RecapHint")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, _oy() + 690.0)
	_hint.size = Vector2(vp.x, 24)
	_root.add_child(_hint)
	for i in range(_last() + 1):
		var d := UI.box(_root, Rect2(Vector2(vp.x / 2.0 - (_last() + 1) * 11.0 + i * 22.0 + 5.0, _oy() + 672.0), Vector2(12, 12)),
			Color("#4a3a24"), "RecapDot%d" % i)
		_dots.append(d)
	_go(0)


## 720 高的内容框在视口里的上沿(iPad 4:3 视口更高 ⇒ 内容框居中)。
func _oy() -> float:
	return maxf(0.0, (vp.y - 720.0) * 0.5)


func _last() -> int:
	return 2 if int((data.get("group", {}) as Dictionary).get("me", -1)) >= 0 else 1


func _process(delta: float) -> void:
	if beat < 0 or beat > 2:
		return
	var prev := t
	t += delta
	_apply(t)
	_fx_step(prev, delta)
	if beat < _last() and t >= float(BEAT_LEN[beat]):
		_go(beat + 1)


## 点屏(松手才算): 这一拍还没演完 ⇒ 跳到终态; 已是终态 ⇒ 下一拍(最后一拍不动, 只认「关闭」)。
func _on_dim_input(ev: InputEvent) -> void:
	var up: bool = (ev is InputEventMouseButton and not (ev as InputEventMouseButton).pressed
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if not up:
		return
	tap()


func tap() -> void:
	if beat < 0 or beat > 2:
		return
	if t < float(beat_end[beat]):
		t = float(beat_end[beat])
		_apply(t)
	elif beat < _last():
		_go(beat + 1)


## 走到第 i 拍(超过最后一拍不动)。
func _go(i: int) -> void:
	if i > _last():
		return
	beat = i
	t = 0.0
	_anims.clear()
	_rolls.clear()
	_burst_at = -1.0
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()
	_fx.parts.clear()
	match i:
		0:
			_beat_champion()
		1:
			_beat_standings()
		_:
			_beat_mine()
	_hint.visible = i < _last()
	for k in range(_dots.size()):
		(_dots[k] as ColorRect).color = GOLD if k == i else Color("#4a3a24")
	_apply(0.0)


# ══════════════════════════════ 按时间算状态 ══════════════════════════════

## 一条动画: 节点 n 的属性 p 在 [t0, t1] 从 a 走到 b(ez: out / back / in / lin)。
func _anim(n: Node, p: String, t0: float, t1: float, a, b, ez: String = "out") -> void:
	_anims.append([n, NodePath(p), t0, t1, a, b, ez])


func _ease(x: float, ez: String) -> float:
	match ez:
		"back":
			return UI.ease_back(x)
		"in":
			return UI.ease_in(x)
		"lin":
			return x
		"bounce":
			## 落地弹一下: 0.8 处到底, 再回弹一点点
			if x < 0.75:
				return UI.ease_in(x / 0.75)
			return 1.0 - 0.06 * sin((x - 0.75) / 0.25 * PI)
	return UI.ease_out(x)


func _apply(tt: float) -> void:
	for a in _anims:
		var n: Node = a[0]
		if not is_instance_valid(n):
			continue
		var k := _ease(UI.seg(tt, float(a[2]), float(a[3])), str(a[6]))
		var v
		if a[4] is Vector2:
			v = (a[4] as Vector2).lerp(a[5], k)
		elif a[4] is Color:
			v = (a[4] as Color).lerp(a[5], k)
		else:
			v = lerpf(float(a[4]), float(a[5]), k)
		n.set_indexed(a[1], v)
	for r in _rolls:
		var lb: Label = r[0]
		if is_instance_valid(lb):
			var k2 := UI.ease_out(UI.seg(tt, float(r[3]), float(r[4])))
			lb.text = str(r[5]) % int(round(lerpf(float(r[1]), float(r[2]), k2)))
	## 光束 / 白闪按拍走
	match beat:
		0:
			_fx.rays_alpha = 0.4 * UI.ease_out(UI.seg(tt, 0.2, 0.9))
			_flash.color.a = 0.8 * (1.0 - UI.seg(tt, 0.55, 0.85)) if tt >= 0.55 else 0.0
		1:
			_fx.rays_alpha = 0.32 * UI.ease_out(UI.seg(tt, 1.3, 1.9))
			_flash.color.a = 0.0
		_:
			_fx.rays_alpha = 0.0
			_flash.color.a = 0.0


func _fx_step(prev: float, dt: float) -> void:
	if _burst_at >= 0.0 and prev < _burst_at and t >= _burst_at:
		_fx.burst(_burst_c, 70, 560.0)
		_fx.dust(_burst_c + Vector2(0, 90), 18, 160.0)
	_fx.rays_rot += dt * 0.35
	_fx.step(dt)


# ══════════════════════════════ ① 冠军 ══════════════════════════════

func _beat_champion() -> void:
	var cup: Dictionary = data["cup"]
	var now := int(data["now"])
	var sd := _M.champion_visible(cup, now)
	var nm := _M.name_of(cup, sd)
	var av := _F.avatar_of(int(data["week"]), _M.tag_of(cup, sd))
	var cx := vp.x * 0.5
	var oy := _oy()
	var row_y := oy + 255.0
	_fx.rays_center = Vector2(cx, row_y)
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.6
	_fx.rays_col = Color("#ffd772")
	## 「冠军杯赛冠军」像素大字(×3), 盖章落下
	var tt := UI.tex_at(_stage, TEX_CUP_TITLE, Vector2(cx, oy + 82.0), Vector2(300, 60), "RecapCupTitle")
	tt.stretch_mode = TextureRect.STRETCH_SCALE
	_anim(tt, "scale", 1.05, 1.3, Vector2(2.2, 2.2), Vector2.ONE, "out")
	_anim(tt, "modulate:a", 1.05, 1.15, 0.0, 1.0, "lin")
	## 奖杯从天上砸下来(左), 落地那一下扬尘 + 彩带
	var tr := UI.tex_at(_stage, UI.TEX_TROPHY, Vector2(cx - 150.0, row_y), Vector2(192, 192), "RecapTrophy")
	_anim(tr, "position:y", 0.1, 0.62, row_y - 96.0 - vp.y * 0.7, row_y - 96.0, "bounce")
	_burst_at = 0.6
	_burst_c = Vector2(cx - 150.0, row_y)
	## 冠军头像在冠军框里放大(右)
	var fr := Control.new()
	fr.name = "RecapChampFrame"
	fr.size = Vector2(200, 200)
	fr.position = Vector2(cx + 150.0 - 100.0, row_y - 100.0)
	fr.pivot_offset = fr.size * 0.5
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(fr)
	## 框的内框是实心暗底 ⇒ 先框后脸(脸叠在内框上, 内框约占 17%~83%)
	var fz := UI.tex_rect(UI.TEX_FRAME, Vector2(200, 200), "RecapFrameArt")
	fr.add_child(fz)
	var face := UI.tex_rect(UI.avatar_path(av), Vector2(128, 128), "RecapChampFace")
	face.position = Vector2(36, 36)
	fr.add_child(face)
	_anim(fr, "scale", 0.65, 1.0, Vector2(0.1, 0.1), Vector2.ONE, "back")
	_anim(fr, "modulate:a", 0.65, 0.75, 0.0, 1.0, "lin")
	## 金缎带写名字(浅字 + 近黑描边 + 落影, 冠军仪式同一条缎带)
	var rb := UI.ribbon(_stage, Vector2(cx, oy + 455.0), 560.0, nm, 48, "gold", "RecapChampRibbon")
	_anim(rb, "scale", 1.3, 1.65, Vector2(0.0, 1.0), Vector2.ONE, "back")
	var sc := UI.label_in(_stage, Rect2(cx - 400.0, oy + 540.0, 800.0, 36.0),
		"本周决赛日 %d 人参赛，分为 %d 组" % [(data["rows"] as Array).size(), (data["groups"] as Array).size()],
		24, UI.TXT, false, "RecapScale")
	_anim(sc, "modulate:a", 1.6, 1.95, 0.0, 1.0, "lin")
	beats.append("冠军 %s" % nm)


# ══════════════════════════════ ② 最终名次(领奖台) ══════════════════════════════

func _beat_standings() -> void:
	var rows: Array = data["rows"]
	var cx := vp.x * 0.5
	var oy := _oy()
	var head := UI.label_in(_stage, Rect2(cx - 300.0, oy + 34.0, 600.0, 64.0), "最终名次", 48, UI.GOLD, true, "RecapHead")
	_anim(head, "modulate:a", 0.0, 0.3, 0.0, 1.0, "lin")
	var by_rank := {}
	for r in rows:
		if int(r["rank"]) <= 3:
			if not by_rank.has(int(r["rank"])):
				by_rank[int(r["rank"])] = []
			(by_rank[int(r["rank"])] as Array).append(r)
	## 领奖台(×4 = 536×216), 底沿压在 oy + 600
	var pw := 134.0 * PODIUM_SCALE
	var ph := 54.0 * PODIUM_SCALE
	var px := cx - pw * 0.5
	var py := oy + 600.0 - ph
	var pod := UI.tex_rect(TEX_PODIUM, Vector2(pw, ph), "RecapPodium")
	pod.stretch_mode = TextureRect.STRETCH_SCALE
	pod.position = Vector2(px, py)
	_stage.add_child(pod)
	_anim(pod, "position:y", 0.0, 0.35, py + 120.0, py, "out")
	_anim(pod, "modulate:a", 0.0, 0.2, 0.0, 1.0, "lin")
	_fx.rays_center = Vector2(px + STEP_X[1] * PODIUM_SCALE, py)
	_fx.rays_radius = maxf(vp.x, vp.y) * 0.5
	_fx.rays_col = Color("#ffd772")
	## 3 → 2 → 1 依次落到台上(并列第 3 两人同站一块)
	var order := [3, 2, 1]
	var t0 := {3: 0.35, 2: 0.85, 1: 1.35}
	var lines := PackedStringArray()
	for rk in order:
		if not by_rank.has(rk):
			continue
		var ppl: Array = by_rank[rk]
		var size_px := 120.0 if rk == 1 else (100.0 if rk == 2 else (84.0 if ppl.size() == 1 else 70.0))
		var foot_y: float = py + float(STEP_Y[rk]) * PODIUM_SCALE
		var sx: float = px + float(STEP_X[rk]) * PODIUM_SCALE
		var names := PackedStringArray()
		for j in range(ppl.size()):
			var r: Dictionary = ppl[j]
			var off := (float(j) - (ppl.size() - 1) * 0.5) * (size_px + 12.0)
			var c := Vector2(sx + off, foot_y - size_px * 0.5 - 6.0)
			var edge: Color = UI.GOLD if rk == 1 else (UI.SILVER if rk == 2 else UI.BRONZE_HI)
			var pt := UI.portrait(_stage, c, size_px, _F.avatar_of(int(data["week"]), str(r["tag"])), edge, "RecapP%d_%d" % [rk, j])
			_anim(pt, "position:y", float(t0[rk]), float(t0[rk]) + 0.4, c.y - size_px * 0.5 - 260.0, c.y - size_px * 0.5, "bounce")
			_anim(pt, "modulate:a", float(t0[rk]), float(t0[rk]) + 0.12, 0.0, 1.0, "lin")
			names.append(str(r["name"]))
		var nl := UI.label_in(_stage, Rect2(sx - 150.0, foot_y - size_px - 54.0, 300.0, 36.0), "、".join(names),
			26 if rk == 1 else 22, UI.GOLD if rk == 1 else UI.TXT, false, "RecapRank%d" % rk)
		_anim(nl, "modulate:a", float(t0[rk]) + 0.35, float(t0[rk]) + 0.55, 0.0, 1.0, "lin")
		var tl := UI.label_in(_stage, Rect2(sx - 150.0, foot_y - size_px - 84.0, 300.0, 30.0), _M.rank_text(rk, rows),
			20, UI.TXT_DIM, false, "RecapRankT%d" % rk)
		_anim(tl, "modulate:a", float(t0[rk]) + 0.35, float(t0[rk]) + 0.55, 0.0, 1.0, "lin")
		lines.append("%s %s" % [tl.text, nl.text])
		if rk == 1:
			_burst_at = 1.75
			_burst_c = Vector2(sx, foot_y - size_px)
	## 「你的名次」单独一行、高亮牌, 名次数字从总人数滚到位。没进决赛日的人没有这一行(也不预告下一场比赛: 下一站归每周赛程条)。
	var me := _my_row(rows)
	var you_txt := ""
	if not me.is_empty():
		var yr := Rect2(cx - 300.0, oy + 618.0, 600.0, 52.0)
		var plate := UI.plate(_stage, yr, UI.GOLD, Color("#2a1f0c"), "RecapYouPlate")
		var you := UI.label_in(_stage, yr, "", 28, Color("#ffe27a"), false, "RecapYou")
		var rk_me := int(me["rank"])
		var tie := _M.rank_text(rk_me, rows).begins_with("并列")
		you.text = "你的名次：%s" % _M.rank_text(rk_me, rows)
		you_txt = you.text
		_rolls.append([you, float(rows.size()), float(rk_me), 2.0, 2.8, "你的名次：%s第 %%d 名" % ("并列" if tie else "")])
		_anim(plate, "scale", 1.9, 2.1, Vector2(1.0, 0.0), Vector2.ONE, "back")
		_anim(you, "modulate:a", 1.95, 2.1, 0.0, 1.0, "lin")
	beats.append("名次 %s / %s" % [" | ".join(lines), you_txt])
	if _last() == 1:
		_close_btn(Vector2(cx + 300.0 - 150.0, oy + 24.0))


func _my_row(rows: Array) -> Dictionary:
	var acc := str(GameState.account_id)
	var g: Dictionary = data.get("group", {})
	var me_name := _M.name_of(g, int(g.get("me", -1)))
	for r in rows:
		if (acc != "" and str(r["acc"]) == acc) or (acc == "" and me_name != "" and str(r["name"]) == me_name):
			return r
	return {}


# ══════════════════════════════ ③ 我的比赛 ══════════════════════════════

func _beat_mine() -> void:
	var cx := vp.x * 0.5
	var oy := _oy()
	var cw := 860.0
	var head := UI.label_in(_stage, Rect2(cx - 300.0, oy + 22.0, 600.0, 64.0), "我的比赛", 48, UI.GOLD, true, "RecapHead")
	_anim(head, "modulate:a", 0.0, 0.25, 0.0, 1.0, "lin")
	_close_btn(Vector2(cx + cw * 0.5 - 150.0, oy + 14.0))
	var ms: Array = _M.my_matches(data.get("group", {}), data.get("cup", {}), int(data["now"]))
	var lines := PackedStringArray()
	var wk := int(data["week"])
	for i in range(ms.size()):
		var it: Dictionary = ms[i]
		var y := oy + 104.0 + i * 104.0
		var card := UI.plate(_stage, Rect2(cx - cw * 0.5, y, cw, 92.0), UI.GOLD if bool(it["won"]) else UI.BRONZE, UI.PLATE, "RecapRow%d" % i)
		var t0 := 0.15 + 0.2 * i
		_anim(card, "position:x", t0, t0 + 0.32, cx - cw * 0.5 + vp.x * 0.6, cx - cw * 0.5, "out")
		var lb := UI.label_in(card, Rect2(18, 0, 230, 92), str(it["label"]), 22, UI.TXT, false, "RecapMatch", HORIZONTAL_ALIGNMENT_LEFT)
		var b: Dictionary = it["b"]
		var opp_sd := -1
		for sd in range(int(b.get("size", 0))):
			if _M.name_of(b, sd) == str(it["opp"]):
				opp_sd = sd
		UI.portrait(card, Vector2(282, 46), 60.0, _F.avatar_of(wk, _M.tag_of(b, opp_sd)), UI.BRONZE_HI, "RecapOpp")
		var on := UI.label_in(card, Rect2(322, 0, 200, 92), "对 %s" % str(it["opp"]), 22, UI.TXT, false, "RecapOppName", HORIZONTAL_ALIGNMENT_LEFT)
		on.clip_text = true
		## 比分(胜方路数 : 败方路数, 按我这一侧摆); 服务端没给比分 ⇒ 不写
		var sp: Array = _DL.score_pair(int(it.get("score", -1))) if int(it.get("score", -1)) != -1 else []
		var sc := UI.label_in(card, Rect2(522, 0, 120, 92), "", 36, UI.GOLD if bool(it["won"]) else UI.TXT_DIM, true, "RecapScore")
		if not sp.is_empty():
			var mine := int(sp[0]) if bool(it["won"]) else int(sp[1])
			var theirs := int(sp[1]) if bool(it["won"]) else int(sp[0])
			sc.text = "%d : %d" % [mine, theirs]
			_rolls.append([sc, 0.0, float(mine), t0 + 0.3, t0 + 0.6, "%%d : %d" % theirs])
		## 胜 / 负章(结算屏那一套美术字 ×3), 盖下来
		var st := UI.tex_at(card, STAMP_WIN if bool(it["won"]) else STAMP_LOSE, Vector2(690, 46), Vector2(57, 60), "RecapStamp")
		st.stretch_mode = TextureRect.STRETCH_SCALE
		st.set_meta("won", bool(it["won"]))
		_anim(st, "scale", t0 + 0.4, t0 + 0.55, Vector2(2.6, 2.6), Vector2.ONE, "in")
		_anim(st, "rotation", t0 + 0.4, t0 + 0.55, -0.5, -0.14, "in")
		_anim(st, "modulate:a", t0 + 0.4, t0 + 0.45, 0.0, 1.0, "lin")
		var rb := UI.button("重看", 120.0, "RecapReplay")
		rb.position = Vector2(cw - 18.0 - 120.0, 5.5)
		var itd: Dictionary = it
		rb.pressed.connect(func() -> void: _replay(itd))
		card.add_child(rb)
		lines.append("%s %s %s %s" % ["胜" if bool(it["won"]) else "负", lb.text, on.text, sc.text])
	beat_end[2] = 0.15 + 0.2 * ms.size() + 0.6
	beats.append("我的比赛 %s" % " | ".join(lines))


func _close_btn(pos: Vector2) -> void:
	var b := UI.button("关闭", 150.0, "RecapClose")
	b.position = pos
	b.pressed.connect(close)
	_stage.add_child(b)


func _replay(it: Dictionary) -> void:
	_W.open(get_tree(), int(data["week"]), it["b"], int(it["r"]), int(it["m"]), _P2.now_utc(), MENU_SCENE)


func close() -> void:
	beat = 99
	queue_free()
