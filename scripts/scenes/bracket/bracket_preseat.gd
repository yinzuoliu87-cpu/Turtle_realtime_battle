extends RefCounted
## bracket_preseat.gd —— 开赛前那一页(2026-11-01 · 方案书 docs/plans/20261101e-决赛日文案与赛前页.md)。
##
## 用户 2026-11-01 看对阵图(18:00 分组之前, 没晋级的号):
##   「哎呦，未晋级的玩家是看不到别人的分组吗？还是什么情况呢？」
##   「但是作为玩家看到的东西是什么呢？你觉得玩家看到合理吗？」
## 原来这时整页只有一行「未晋级 · 需通过周六闯关赛」+ 一把锁: 几点分组、谁晋级了、今晚怎么安排, 一样都没有;
##   「需通过周六闯关赛」是叫观众去做今天做不了的事。晋级的人看到的是「未分组 · 18:00 自动分组」+ 一条四站时间线。
## 商业游戏同一处给三样(对照表 §1.5 / 共同规律 12): 开赛倒计时 + 参赛名单(人数 + 名字) + 赛程; 资格写成条件, 不写指令。
##
## 两种用法(同一套版式):
##   · 小组赛页 18:00 分组之前(晋级的人 = EK_NOT_SEATED, 没晋级的人 = EK_NO_GROUP 且还没到分组时间)
##     ⇒ 距小组赛开始 + 今晚赛程 + 本周晋级选手(服务端 finals_qualified_list)
##   · 冠军杯赛页开赛之前(EK_FINALS_SOON)
##     ⇒ 距冠军杯赛开始 + 今晚赛程 + 冠军杯赛参赛选手(已产生的组冠军)
## ★时刻全读常量(phase2_config 分组 FINALS_SEAT_HOUR_UTC / 冠军杯赛 FINALS_START_HOUR_UTC), 显示按设备时区; 不写死。
## ★只画, 不判: 哪一种情况由场景 `_empty_kind()` 判好传进来; 名单由 `FinalsQualified` / 场景的组冠军汇总给。

const _H := preload("res://scripts/scenes/bracket/bracket_hero.gd")
const _FC := preload("res://scripts/ui/finals_copy.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const N_ROOT := "Preseat"
const N_TITLE := "PreseatTitle"
const N_COUNT := "PreseatCountdown"
const N_SUB := "PreseatSub"
const N_BADGE := "PreseatBadge"
const N_SCHED := "PreseatSchedule"
const N_LIST := "PreseatList"
const N_LIST_HEAD := "PreseatListHead"
const N_LIST_COUNT := "PreseatListCount"
const N_ROW := "PreseatRow"
const N_EMPTY := "PreseatListEmpty"

const MODE_GROUP := "group"
const MODE_CUP := "cup"

var s


func _init(scene) -> void:
	s = scene


## 这一页该不该出: 返回 MODE_GROUP / MODE_CUP / ""。`kind` = 场景 `_empty_kind()`。
static func mode_for(kind: String, before_seating: bool, viewing_past: bool) -> String:
	if viewing_past:
		return ""
	if kind == "not_seated":
		return MODE_GROUP
	if kind == "no_group" and before_seating:
		return MODE_GROUP
	## 1 人组(group_solo)不走这一页: 那一屏要先说清「本组仅 1 人，直接晋级」(说明框), 不是一张冠军杯赛倒计时
	if kind == "finals_soon":
		return MODE_CUP
	return ""


## 今晚赛程两行: [{"time", "name", "state", "rule"}](state = 未开始 / 进行中 / 已结束, 与主菜单决赛日卡同一份判据;
##   rule = 这一段怎么打, 给第一次看的人 —— 「组冠军」「单败」在别处没人解释过)。
static func schedule_rows(now: int, groups: Array, cup: Dictionary) -> Array:
	var word := {_M.S3_COUNT: "未开始", _M.S3_LIVE: "进行中", _M.S3_END: "已结束"}
	return [
		{"time": _FC.at(_M.seat_ts(now)), "name": _P2.STAGE_GROUP, "state": str(word.get(_M.group_state(now, groups), "")),
			"rule": "分组单败淘汰，组冠军晋级%s" % _P2.STAGE_CUP},
		{"time": _FC.at(_M.cup_ts(now)), "name": _P2.STAGE_CUP, "state": str(word.get(_M.cup_state(now, cup), "")),
			"rule": "组冠军单败淘汰，决出冠军"},
	]


## 名单一行的战绩(「4 胜 1 负」= 周六闯关赛战绩)。
static func record_text(gw: int, gl: int) -> String:
	return "%d 胜 %d 负" % [gw, gl]


## 整页。`d` = {"mode", "end_ts", "now", "me_in", "list": [{name, tag, gw, gl, me}] 或 null(拿不到), "n",
##   "champs": ["A 组冠军：名字", ...](冠军杯模式), "groups", "cup"}。返回根节点。
func build(parent: Control, vp: Vector2, top: float, d: Dictionary) -> Control:
	var root := Control.new()
	root.name = N_ROOT
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var mode := str(d.get("mode", MODE_GROUP))
	var cup_mode := mode == MODE_CUP
	## ── 上面那块: 距开始 + 大倒计时 + 一句赛制 ──
	var pw := clampf(vp.x * 0.56, 560.0, 760.0)
	var pr := Rect2(Vector2((vp.x - pw) * 0.5, top - 24.0), Vector2(pw, 150.0))
	s._stage._plate(root, pr, _H.GOLD_DEEP)
	if ResourceLoader.exists(_H.TEX_TROPHY):
		for k in [0, 1]:
			var tr := TextureRect.new()
			tr.texture = load(_H.TEX_TROPHY)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(80, 80)
			tr.position = Vector2(pr.position.x + 22.0 if k == 0 else pr.end.x - 102.0, pr.position.y + 36.0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(tr)
	var stage_name: String = _P2.STAGE_CUP if cup_mode else _P2.STAGE_GROUP
	var tl := _lb("距%s开始" % stage_name, 20, _H.GOLD)
	tl.name = N_TITLE
	tl.position = pr.position + Vector2(0, 12)
	tl.size = Vector2(pw, 28)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tl)
	var end_ts := int(d.get("end_ts", 0))
	var big := _lb("", 40, _H.TXT)
	big.name = N_COUNT
	big.position = pr.position + Vector2(0, 42)
	big.size = Vector2(pw, 58)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(big)
	var fn := func() -> String:
		var left := end_ts - int(s.srv_now())
		return _FC.dur(left) if left > 0 else "即将开始"
	big.text = fn.call()
	s._stage.live_texts.append([big, fn])
	var sub := _lb((_FC.at(end_ts) + " 开赛") if cup_mode else ("%s 公布分组" % _FC.at(end_ts)), 16, Color("#e9d6a8"), false)
	sub.name = N_SUB
	sub.position = pr.position + Vector2(0, 108)
	sub.size = Vector2(pw, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	if bool(d.get("me_in", false)) and not cup_mode:
		var br := Rect2(Vector2(pr.end.x - 96.0, pr.position.y + 10.0), Vector2(84.0, 26.0))
		s._stage._box(root, br.grow(1.0), _H.INK)
		s._stage._box(root, br, Color("#3f6a2a"))
		var bl := _lb("已晋级", 15, Color("#e8ffd6"), false)
		bl.name = N_BADGE
		bl.position = br.position
		bl.size = br.size
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		root.add_child(bl)
	## ── 下面两张: 今晚赛程 | 名单 ──
	var y0 := pr.end.y + 16.0
	var bottom := vp.y - 68.0                  # 底下让给全局决赛日小条
	var ch := maxf(150.0, bottom - y0)
	var tw := minf(vp.x - 64.0, 1000.0)
	var gap := 16.0
	var lw := clampf(tw * 0.40, 300.0, 400.0)
	var rw := tw - lw - gap
	var x0 := (vp.x - tw) * 0.5
	_schedule(root, Rect2(Vector2(x0, y0), Vector2(lw, ch)), d)
	_list(root, Rect2(Vector2(x0 + lw + gap, y0), Vector2(rw, ch)), d)
	return root


func _lb(t: String, fs: int, col: Color, outline: bool = true) -> Label:
	return s._hero._label(t, fs, col, outline)


func _card_head(p: Control, r: Rect2, title: String, nm: String) -> void:
	s._stage._plate(p, r)
	var hl := _lb(title, 18, _H.GOLD)
	hl.name = nm
	hl.position = r.position + Vector2(18, 10)
	hl.size = Vector2(r.size.x - 36, 26)
	p.add_child(hl)
	s._stage._box(p, Rect2(r.position + Vector2(14, 42), Vector2(r.size.x - 28, 2)), _H.BRONZE)


func _schedule(root: Control, r: Rect2, d: Dictionary) -> void:
	var box := Control.new()
	box.name = N_SCHED
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_card_head(box, r, "今晚赛程", "PreseatScheduleHead")
	var rows: Array = schedule_rows(int(d.get("now", 0)), d.get("groups", []) as Array, d.get("cup", {}) as Dictionary)
	var y := r.position.y + 56.0
	for row in rows:
		var on := str(row["state"]) == "进行中"
		var t := _lb(str(row["time"]), 20, _H.GOLD if on else _H.TXT, true)
		t.position = Vector2(r.position.x + 18, y)
		t.size = Vector2(70, 30)
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(t)
		var nm := _lb(str(row["name"]), 20, _H.TXT, true)
		nm.position = Vector2(r.position.x + 96, y)
		nm.size = Vector2(r.size.x - 200, 30)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(nm)
		var st := _lb(str(row["state"]), 15, _H.LIVE if on else _H.TXT_DIM, false)
		st.name = "PreseatState"
		st.position = Vector2(r.end.x - 100, y)
		st.size = Vector2(82, 30)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(st)
		var ru := _lb(str(row["rule"]), 14, _H.TXT_DIM, false)
		ru.position = Vector2(r.position.x + 96, y + 30)
		ru.size = Vector2(r.size.x - 110, 22)
		ru.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ru.clip_text = true
		box.add_child(ru)
		y += 66.0
	## 资格(写成条件, 不写指令 —— Dota「勇士联赛积分名列前茅的玩家具有参赛资格。」)
	var notes := PackedStringArray([
		_FC.kv("参赛资格", "周六闯关赛 %d 胜" % int(d.get("wins_in", 4))),
	])
	var ny := maxf(y + 8.0, r.end.y - 30.0 * float(notes.size()) - 10.0)
	for nt in notes:
		var nl := _lb(nt, 15, _H.TXT_DIM, false)
		nl.position = Vector2(r.position.x + 18, ny)
		nl.size = Vector2(r.size.x - 36, 26)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(nl)
		ny += 28.0


func _list(root: Control, r: Rect2, d: Dictionary) -> void:
	var box := Control.new()
	box.name = N_LIST
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var cup_mode := str(d.get("mode", "")) == MODE_CUP
	_card_head(box, r, "%s参赛选手" % _P2.STAGE_CUP if cup_mode else "本周晋级选手", N_LIST_HEAD)
	var rows: Array = []
	if cup_mode:
		for ln in (d.get("champs", []) as Array):
			rows.append({"name": str(ln), "right": "", "me": false})
	else:
		## 玩家 ID 只在名单里真有重名时才带(与对阵卡同一条: `competitor` 只在本组重名时带号)
		var lst: Array = d.get("list", []) if d.get("list", null) is Array else []
		var cnt := {}
		for it in lst:
			cnt[str(it.get("name", ""))] = int(cnt.get(str(it.get("name", "")), 0)) + 1
		for it in lst:
			var nm0 := str(it.get("name", ""))
			rows.append({"name": nm0, "tag": str(it.get("tag", "")) if int(cnt.get(nm0, 0)) > 1 else "",
				"right": record_text(int(it.get("gw", 0)), int(it.get("gl", 0))), "me": bool(it.get("me", false))})
	var n := int(d.get("n", rows.size())) if not cup_mode else rows.size()
	if n > 0:
		var cl := _lb("%d 人" % n, 17, _H.TXT, false)
		cl.name = N_LIST_COUNT
		cl.position = r.position + Vector2(18, 10)
		cl.size = Vector2(r.size.x - 36, 26)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(cl)
	var inner := Rect2(r.position + Vector2(10, 50), r.size - Vector2(20, 58))
	if rows.is_empty():
		var el := _lb(("组冠军产生后公布" if cup_mode else "%s 公布" % _FC.at(int(d.get("end_ts", 0)))), 17, _H.TXT_DIM, false)
		el.name = N_EMPTY
		el.position = inner.position
		el.size = inner.size
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(el)
		return
	var sc := ScrollContainer.new()
	sc.name = "PreseatScroll"
	sc.position = inner.position
	sc.size = inner.size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(sc)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(inner.size.x - 12.0, 0)
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(col)
	for i in range(rows.size()):
		var it: Dictionary = rows[i]
		var row := Control.new()
		row.name = "%s%d" % [N_ROW, i]
		row.custom_minimum_size = Vector2(inner.size.x - 12.0, 34)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		if i % 2 == 0 or bool(it.get("me", false)):
			var bg := ColorRect.new()
			bg.color = Color("#3a2a14") if bool(it.get("me", false)) else Color(1, 1, 1, 0.04)
			bg.size = row.custom_minimum_size
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bg)
		var me := bool(it.get("me", false))
		var tag := str(it.get("tag", ""))
		var rw := 96.0 if str(it.get("right", "")) != "" else 0.0
		var nm := _lb(s._fit_name(str(it["name"]), row.custom_minimum_size.x - rw - 110.0, false, 17.0), 17,
			_H.GOLD if me else _H.TXT, false)
		nm.position = Vector2(10, 0)
		nm.size = Vector2(row.custom_minimum_size.x - rw - 20.0, 34)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nm)
		if tag != "":
			var f: Font = nm.get_theme_font("font")
			var nw := f.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x if f != null else 80.0
			var tg := _lb(tag, 13, _H.TXT_FAINT, false)
			tg.position = Vector2(18.0 + nw, 0)
			tg.size = Vector2(90, 34)
			tg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(tg)
		if rw > 0.0:
			var rl := _lb(str(it["right"]), 15, _H.TXT_DIM, false)
			rl.position = Vector2(row.custom_minimum_size.x - rw - 8.0, 0)
			rl.size = Vector2(rw, 34)
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(rl)
