extends RefCounted
class_name WeekCloseCard
## 周末收盘卡(2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 A+B / C)。
##
## 用户 10-26:「晋级的人……补发深海币和经验，有任何提示方式吗」→ 选「登录弹一次结算卡」;
##   「没晋级的你第一次进搞个弹窗？你设计一下」;「文案你学习商业游戏的说法」。
## 收盘之后第一次进主菜单弹, 每周每张各一次(存档 `close_card_ranked_wk` / `close_card_gauntlet_wk` 记弹过的那一周):
##   积分赛收盘(周五 23:00 UTC)后: 晋级 ⇒ RANKED_IN(没打的场次化成的奖励) / 没晋级且打过 ⇒ RANKED_OUT(去观战)
##   闯关赛收盘(周日 17:30 UTC)后: 4 胜 ⇒ GAUNTLET_IN(决赛日几点; 省下的场次第 4 胜当场就发了) / 打过但没打完 ⇒ GAUNTLET_CUT
## ★文案照商业游戏中文原文的写法(docs/plans/ref/20261026-周末文案参考.md): 标题只说发生了什么,
##   正文第一句复述结果带数字、第二句说下一步去哪; 奖励单独一行「名称 +数量」; 不用「补发 / 折算」(那是运营词)。
##   ★2026-10-26 用户「玩家比如4-0，他是不明白为什么会有未打完的2场的」⇒ 把上限说出来(括号里: 每周 16 场, 未进行的 N 场按场发放)。
##   ★★同日用户「我还需要怎么强调商业游戏的描述和口语？」⇒ 不用「你 + 口语动词」(「你用 4 场就晋级了」「省下的」「照发」「看看」「没打的」):
##     标题只写状态; 正文是数据式短陈述(「本周积分赛战绩 12 胜 1 负，晋级周六闯关赛。」); 奖励给名词标签, 规则放括号里;
##     下一步写成「下一轮积分赛：下周二开始。」(memory fb-no-colloquial-copy)。
## ★金额一个数都不自己算: 读 `backfill_summary()` —— 与真发钱那个函数同一份账。
## ★时刻一律按玩家设备时区说(用户「根据机子的时间去显示正确时间」): `phase2_config.local_wd_hhmm`。
## ★样子与教程选择框同一套(TutorialChoice): 压暗 + panel-frame 九宫格 + `UISkin.card_button`(卡片里不用木牌按钮)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const COIN_TEX := preload("res://assets/sprites/menu/ic-deepsea.png")

const NODE_NAME := "WeekCloseCard"
const KIND_RANKED_IN := "ranked_in"
const KIND_RANKED_OUT := "ranked_out"
const KIND_GAUNTLET_IN := "gauntlet_in"
const KIND_GAUNTLET_CUT := "gauntlet_cut"
## 按钮去处(主菜单按它接场景)
const DOOR_NONE := ""
const DOOR_BOARD := "board"        # 全场赛况(闯关赛)
const DOOR_BRACKET := "bracket"    # 对阵图(决赛日)

const TXT_CLAIM := "领取"
const TXT_OK := "好的"
const TXT_CLOSE := "关闭"
const TXT_WATCH := "观战"
const TXT_BRACKET := "查看对阵图"
## 下一次机会(周一休赛 ⇒ 下一轮积分赛是周二)。收盘卡与拦截提示共用这一句。
const TXT_NEXT_WEEK := "下一轮积分赛：下周二开始。"
const BODY_W := 640.0
const BTN_SIZE := Vector2(168, 81)


## 这一刻该弹哪几张, 按先后。★纯函数(gs 可以是门禁造的替身, 只读字段 / 调那几个查询)。
## ★存档还没滚到这一周(`week_anchor_ts` ≠ 本周锚点)⇒ 一张都不弹: 那时 promoted / 战绩还是上一周的。
static func due(gs, now: int) -> Array:
	var a: int = _P2.week_anchor_utc(now)
	if gs == null or int(gs.week_anchor_ts) != a:
		return []
	var out: Array = []
	if now >= _P2.ranked_close_ts(a) and int(gs.close_card_ranked_wk) != a and _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		if bool(gs.promoted):
			out.append(KIND_RANKED_IN)
		elif int(gs.ranked_used) > 0:
			out.append(KIND_RANKED_OUT)
	if now >= _P2.gauntlet_close_ts(a) and int(gs.close_card_gauntlet_wk) != a and bool(gs.promoted):
		var w: int = int(gs.gauntlet_wins)
		var l: int = int(gs.gauntlet_losses)
		var st: String = _P2.gauntlet_state(w, l)
		if st == _P2.GAUNTLET_IN:
			out.append(KIND_GAUNTLET_IN)
		elif st == _P2.GAUNTLET_RUNNING and w + l > 0:
			out.append(KIND_GAUNTLET_CUT)
	return out


## 记「本周这张弹过了」。★在弹出那一刻记(不是关掉时): 杀进程不会让同一张再弹一次; 钱早已入账, 不会少。
static func mark_seen(gs, kind: String, now: int) -> void:
	var a: int = _P2.week_anchor_utc(now)
	if kind == KIND_RANKED_IN or kind == KIND_RANKED_OUT:
		gs.close_card_ranked_wk = a
	else:
		gs.close_card_gauntlet_wk = a


## 积分赛本周战绩: 胜 = 赛季胜场 − 闯关胜场(周六的胜场也记进 season_wins); 负 = 掉了几条命(只有积分赛输了掉命)。
static func ranked_record(gs) -> Vector2i:
	var w: int = maxi(0, int(gs.season_wins) - int(gs.gauntlet_wins))
	var l: int = maxi(0, int(_P2.HEARTS_MAX) - int(gs.hearts))
	return Vector2i(w, l)


## 一张卡的内容: {kind, title, body:[段], coins, xp, primary:[字, 去处], secondary:[字, 去处] 或 []}。
static func spec(kind: String, gs, now: int) -> Dictionary:
	var a: int = _P2.week_anchor_utc(now)
	var g_close: int = _P2.gauntlet_close_ts(a)
	var seat: int = _P2.finals_seat_ts(a)
	var d := {"kind": kind, "title": "", "body": [], "coins": 0, "xp": 0, "primary": [TXT_OK, DOOR_NONE], "secondary": []}
	match kind:
		KIND_RANKED_IN:
			var r := ranked_record(gs)
			var bf: Dictionary = gs.backfill_summary()
			var n: int = int(bf.get("games", 0))
			d["title"] = "积分赛已晋级"
			d["body"] = ["本周积分赛战绩 %d 胜 %d 负，晋级周六闯关赛。" % [r.x, r.y]]
			if n > 0:
				(d["body"] as Array).append("未进行场次奖励（积分赛每周 %d 场，未进行的 %d 场按场发放）" % [int(_P2.RANKED_QUOTA), n])
			if now < g_close:
				(d["body"] as Array).append("闯关赛：%d 胜晋级决赛日，%d 负淘汰，%s 截止。" % [
					int(_P2.GAUNTLET_WINS_IN), int(_P2.GAUNTLET_LOSSES_OUT), _P2.local_wd_hhmm(g_close)])
			if n > 0:
				d["coins"] = int(bf.get("coins", 0))
				d["xp"] = int(bf.get("xp", 0))
				d["primary"] = [TXT_CLAIM, DOOR_NONE]
		KIND_RANKED_OUT:
			var r2 := ranked_record(gs)
			d["title"] = "积分赛已结束"
			if bool(gs.is_eliminated()):
				d["body"] = ["本周积分赛战绩 %d 胜 %d 负，生命已耗尽，未晋级闯关赛。" % [r2.x, r2.y]]
			else:
				d["body"] = ["本周积分赛战绩 %d 胜 %d 负，距晋级还差 %d 胜，未晋级闯关赛。" % [
					r2.x, r2.y, maxi(1, int(_P2.PROMOTE_WINS) - r2.x)]]
			if now < g_close:
				(d["body"] as Array).append("闯关赛与决赛日开放观战。" + TXT_NEXT_WEEK)
				d["primary"] = [TXT_WATCH, DOOR_BOARD]
			else:
				(d["body"] as Array).append("决赛日开放观战。" + TXT_NEXT_WEEK)
				d["primary"] = [TXT_WATCH, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
		KIND_GAUNTLET_IN:
			## ★2026-10-26 「省下的场次」在第 4 胜那一刻就发了、结算屏上说过(GameState.gauntlet_promote_bonus),
			##   这张卡只提醒决赛日几点开始, 不再发奖励(否则同一笔钱领两遍的样子)。
			d["title"] = "闯关赛已晋级"
			d["body"] = ["闯关赛战绩 %d 胜 %d 负，晋级周日决赛日。" % [int(gs.gauntlet_wins), int(gs.gauntlet_losses)]]
			if now < seat:
				(d["body"] as Array).append("决赛日%s：%s 开始。" % [_P2.STAGE_GROUP, _P2.local_wd_hhmm(seat)])
			else:
				(d["body"] as Array).append("决赛日已开始，比赛在对阵图中进行。")
			d["primary"] = [TXT_BRACKET, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
		KIND_GAUNTLET_CUT:
			d["title"] = "闯关赛已截止"
			d["body"] = ["闯关赛已于%s 截止，最终战绩 %d 胜 %d 负，未晋级决赛日。" % [
				_P2.local_wd_hhmm(g_close), int(gs.gauntlet_wins), int(gs.gauntlet_losses)],
				"决赛日开放观战。" + TXT_NEXT_WEEK]
			d["primary"] = [TXT_WATCH, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
	return d


## 建卡挂到 host 上。on_done(door: String, from_pos: Vector2) 在点了按钮、卡关掉之后调:
##   door = 按钮的去处(DOOR_*), from_pos = 奖励行那枚币的画布坐标(点「领取」时飞币的起点; 其它按钮 = (-1, -1))。
static func open(host: Node, d: Dictionary, on_done: Callable) -> Control:
	var ov := ColorRect.new()
	ov.name = str(d.get("node_name", NODE_NAME))
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_meta("kind", str(d.get("kind", "")))
	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH; box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(0)
	var bframe := UISkin.nine("panel-frame.png", 20, bsb)
	bframe.content_margin_left = 44; bframe.content_margin_right = 44
	bframe.content_margin_top = 30; bframe.content_margin_bottom = 30
	box.add_theme_stylebox_override("panel", bframe)
	ov.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vb)
	var t := Label.new()
	t.name = "Title"
	t.text = str(d.get("title", ""))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	t.add_theme_constant_override("outline_size", 5)
	t.visible = t.text != ""
	vb.add_child(t)
	var bi := 0
	for para in (d.get("body", []) as Array):
		var l := Label.new()
		l.name = "Body%d" % bi
		bi += 1
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 22 if bi == 1 else 20)
		l.add_theme_color_override("font_color", Color("#f2ead8") if bi == 1 else Color("#b9c4d2"))
		var lay: Array = sentence_lines(l, str(para), 22 if bi == 1 else 20)
		l.text = str(lay[0])
		l.custom_minimum_size = Vector2(float(lay[1]), 0)
		vb.add_child(l)
	var coin_icon: Control = null
	if int(d.get("coins", 0)) > 0 or int(d.get("xp", 0)) > 0:
		var rr := HBoxContainer.new()
		rr.name = "Rewards"
		rr.alignment = BoxContainer.ALIGNMENT_CENTER
		rr.add_theme_constant_override("separation", 48)
		vb.add_child(rr)
		if int(d.get("coins", 0)) > 0:
			var cb := HBoxContainer.new()
			cb.add_theme_constant_override("separation", 10)
			var ic := TextureRect.new()
			ic.name = "CoinIcon"
			ic.texture = COIN_TEX
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.custom_minimum_size = Vector2(48, 48)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cb.add_child(ic)
			coin_icon = ic
			cb.add_child(_reward_lbl("深海币", "+%d" % int(d["coins"]), Color("#ffd93d"), "CoinAmount"))
			rr.add_child(cb)
		if int(d.get("xp", 0)) > 0:
			rr.add_child(_reward_lbl("经验", "+%d" % int(d["xp"]), Color("#8fe0ff"), "XpAmount"))
	var bh := HBoxContainer.new()
	bh.name = "Buttons"
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 18)
	vb.add_child(bh)
	var btns: Array = [d.get("primary", [])]
	if not (d.get("secondary", []) as Array).is_empty():
		btns.append(d["secondary"])
	for i in range(btns.size()):
		var spec_b: Array = btns[i]
		if spec_b.is_empty():
			continue
		var b := Button.new()
		b.name = "Primary" if i == 0 else "Secondary"
		b.text = str(spec_b[0])
		b.custom_minimum_size = BTN_SIZE
		b.add_theme_font_size_override("font_size", 24)
		UISkin.card_button(b)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		bh.add_child(b)
		var door: String = str(spec_b[1])
		var claim: bool = str(spec_b[0]) == TXT_CLAIM
		b.pressed.connect(func() -> void:
			## ★领取: 先记下币的位置(卡一关它就没了), 再关卡, 再交给主菜单去飞。
			var from_icon: Control = coin_icon if claim else null
			var from_pos: Vector2 = from_icon.get_global_rect().get_center() if from_icon != null and is_instance_valid(from_icon) else Vector2(-1, -1)
			ov.queue_free()
			on_done.call(door, from_pos))
	host.add_child(ov)
	## 弹入: 卡从 0.85 放大到 1(与结算屏大字同一种 BACK 缓动), 压暗淡入。时长走 UIPalette 节拍表(tools/ui_tempo_audit.py)。
	box.pivot_offset = box.size / 2.0
	box.resized.connect(func() -> void: box.pivot_offset = box.size / 2.0)
	box.scale = Vector2(0.85, 0.85)
	ov.modulate.a = 0.0
	var tw := ov.create_tween().set_parallel(true)
	tw.tween_property(ov, "modulate:a", 1.0, UIPalette.T_BASE)
	tw.tween_property(box, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return ov


## 正文怎么折行: 返回 [要显示的字, 标签宽]。
##   ① 一行放得下 ⇒ 一行;
##   ② 放不下 ⇒ 在句号处换行(每句各占一行, 句子短的拼在一起), 不在词中间断开(实拍:「本周未晋 / 级」);
##   ③ 某一句本身就放不下 ⇒ 按「行数均分」的宽交给引擎折(+ 两个字的余量), 不让最后一行只剩一两个字(实拍:「未能晋级闯关 / 赛。」)。上限 BODY_W。
static func sentence_lines(l: Label, txt: String, fs: int) -> Array:
	var f: Font = l.get_theme_font("font")
	if f == null:
		return [txt, BODY_W]
	var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w <= BODY_W:
		return [txt, maxf(360.0, ceilf(w) + 4.0)]
	var parts: PackedStringArray = txt.split("。", false)
	var sents: Array = []
	for i in range(parts.size()):
		sents.append(parts[i] + ("。" if i < parts.size() - 1 or txt.ends_with("。") else ""))
	var lines: Array = []
	var cur := ""
	var widest := 0.0
	for s in sents:
		if f.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BODY_W:
			var n: int = int(ceil(w / BODY_W))
			return [txt, minf(BODY_W, ceilf(w / float(n)) + fs * 2.0)]
		var tryline: String = cur + str(s)
		if cur != "" and f.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BODY_W:
			lines.append(cur)
			cur = str(s)
		else:
			cur = tryline
	if cur != "":
		lines.append(cur)
	for ln in lines:
		widest = maxf(widest, f.get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return ["\n".join(PackedStringArray(lines)), maxf(360.0, ceilf(widest) + 4.0)]


## 奖励行一格: 名称(小字) 在上、数量(大字) 在下。
static func _reward_lbl(cap: String, val: String, col: Color, nm: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var c := Label.new()
	c.text = cap
	c.add_theme_font_size_override("font_size", 18)
	c.add_theme_color_override("font_color", Color("#9fb3c8"))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	var n := Label.new()
	n.name = nm
	n.text = val
	n.add_theme_font_size_override("font_size", 36)
	n.add_theme_color_override("font_color", col)
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	n.add_theme_constant_override("outline_size", 5)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	return v
