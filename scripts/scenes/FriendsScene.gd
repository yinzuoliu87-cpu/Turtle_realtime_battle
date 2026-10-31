extends Control
## FriendsScene —— 好友 + 切磋(2026-10-24 · 方案书 docs/plans/20261023-好友切磋.md §4.2 / §4.3)。
##
## 用户 2026-10-23「接下来新任务，好友系统，主要实现切磋 … 切磋是当前的背包阵容vs好友的最新背包阵容」;
##   入口 = 主菜单左栏「好友」键; 加好友 = 双方同意(两项都是用户在选项里选的)。
##
## 版面(1280×720 设计框, 末尾 UIFrame 居中):
##   顶栏   返回 + 「好友」
##   左栏   我的玩家 ID(+ 复制) / 添加好友(输入 ID → 查找 → 申请) / 好友申请(同意 · 拒绝) + 已发出(撤回)
##   右栏   好友 N / 100: 每行 头像(对方第一只统领) · 昵称 · ID · 阵容更新时间 ·「切磋」·「删除」
## ★卡片里的按钮一律 `UISkin.card_button`(用户 10-22「为什么还在用这个木头按钮？我说了无数遍啊」)。
## ★切磋: 「切磋」→ `FriendsNet.fetch_lineup`(服务端先验是好友 + 本机验规则版本)→ `Spar.start` 直接进战斗场。
##   隔离(不叠香火 / 宝箱 / 赌神 / 斧头, 不进战绩, 不录像)全在 `Spar`, 本屏不碰。
## ★进本屏先 `put_lineup`(只在阵容变了才传): 我把 ID 告诉别人之前, 服务端得先有我这一行, 否则别人查不到我。

const TopBar = preload("res://scripts/util/top_bar.gd")
const FN := preload("res://scripts/net/friends_net.gd")
const SBN := preload("res://scripts/net/supabase.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")
const BL := preload("res://scripts/util/blocklist.gd")

const W := 1280.0
const TOP_Y := 98.0
const BOT_Y := 704.0
const LEFT_X := 24.0
const LEFT_W := 452.0
const RIGHT_X := 492.0
const RIGHT_W := 764.0
const PAD := 22.0                 # > panel-frame 实测边带 13px
const ROW_H := 100.0              # 一行卡: 按钮 81(触控线 44pt) + 上下边带
const BTN_H := 81.0
const AV_PX := 64.0
const F_CAP := 15
const F_NAME := 22
const F_SUB := 15
const F_TAG := 34
const COL_CAP := Color("#7fb8d8")
const COL_NAME := Color("#fff1d6")
const COL_SUB := Color("#9fb0c0")
const COL_GOLD := Color("#ffd27a")
const COL_MSG := Color("#ffe7a0")

## 屏上的字(门禁按它找)。
const TXT_TITLE := "好友"
const TXT_MY_ID := "我的玩家 ID"
const TXT_COPY := "复制"
const TXT_ADD := "添加好友"
const TXT_FIND := "查找"
const TXT_ID_HINT := "输入对方的玩家 ID"
const TXT_ASK := "申请好友"
const TXT_REQS := "好友申请"
const TXT_ACCEPT := "同意"
const TXT_DECLINE := "拒绝"
const TXT_WAITING := "等待对方同意"
const TXT_CANCEL := "撤回"
const TXT_SPAR := "切磋"
const TXT_DEL := "删除"
const TXT_DEL_SURE := "确认删除"
const TXT_EMPTY_FRIENDS := "暂无好友。可将玩家 ID 发给朋友，或在左侧输入对方的玩家 ID 添加。"
const TXT_EMPTY_REQS := "暂无好友申请"
const TXT_LOADING := "正在读取…"
const TXT_NO_LINEUP := "尚未配置阵容"

var _top_bar = null
var _tag_lbl: Label
var _id_edit: LineEdit
var _find_box: VBoxContainer
var _req_box: VBoxContainer
var _friend_box: VBoxContainer
var _count_lbl: Label
var _msg_lbl: Label
## 最近一次 friend_list 的回包(门禁读)。
var data: Dictionary = {}
## 屏上最近一句提示(门禁读)。
var last_msg := ""
## 正在等的请求数(>0 时按钮不重复发)。
var _busy := 0
## 「删除」两步确认: 第一次按变成「确认删除」, 3 秒内再按才删。
var _del_armed := ""
var _del_armed_at := 0
## 切磋开局入口(默认 `Spar.start`: 挂上 + 换到战斗场)。门禁换成记账的, 免得把门禁自己的场景换掉。
var spar_start: Callable = Spar.start


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn")


func _ready() -> void:
	_bg()
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new(self, {
		"title": TXT_TITLE,
		"palette": TopBar.DEEP,
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		"on_back": func(): SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn"),
	})
	var left := _panel(Vector2(LEFT_X, TOP_Y), Vector2(LEFT_W, BOT_Y - TOP_Y))
	var right := _panel(Vector2(RIGHT_X, TOP_Y), Vector2(RIGHT_W, BOT_Y - TOP_Y))
	_build_left(left)
	_build_right(right)
	_tag_lbl.text = Backend.my_tag()
	if not SBN.enabled():
		_say(FN.msg("off"))
		_render_list({})
	else:
		_say(TXT_LOADING)
		FN.put_lineup(func(_r: Dictionary) -> void: refresh())
	UIFrame.attach(self)


## 重新取一遍好友页数据。
func refresh() -> void:
	_busy += 1
	FN.list(func(r: Dictionary) -> void:
		_busy -= 1
		if not is_inside_tree():
			return
		if not bool(r["ok"]):
			_say(FN.msg(str(r["reason"])))
			return
		data = r["data"]
		if str(data.get("tag", "")) != "":
			_tag_lbl.text = str(data["tag"])
		if last_msg == TXT_LOADING:
			_say("")
		_render_list(data))


# ─────────────────────────────── 左栏 ───────────────────────────────

func _build_left(p: Control) -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(PAD, PAD - 4.0)
	v.custom_minimum_size = Vector2(LEFT_W - PAD * 2.0, 0)
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(_lbl(TXT_MY_ID, F_CAP, COL_CAP))
	var idrow := HBoxContainer.new()
	idrow.add_theme_constant_override("separation", 12)
	v.add_child(idrow)
	_tag_lbl = _lbl("", F_TAG, COL_GOLD)
	_tag_lbl.name = "MyTag"
	_tag_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idrow.add_child(_tag_lbl)
	idrow.add_child(_btn(TXT_COPY, 110.0, _copy_tag, "CopyTag"))
	v.add_child(_sep())
	v.add_child(_lbl(TXT_ADD, F_CAP, COL_CAP))
	var add := HBoxContainer.new()
	add.add_theme_constant_override("separation", 12)
	v.add_child(add)
	_id_edit = LineEdit.new()
	_id_edit.name = "IdEdit"
	_id_edit.placeholder_text = TXT_ID_HINT
	_id_edit.max_length = 8
	_id_edit.custom_minimum_size = Vector2(0, BTN_H)
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.add_theme_font_size_override("font_size", 24)
	_id_edit.add_theme_color_override("font_color", COL_NAME)
	_id_edit.add_theme_color_override("font_placeholder_color", Color("#6f8090"))
	for st in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0a1422")
		sb.border_color = Color("#d89a48") if st == "focus" else Color("#6a5a34")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		_id_edit.add_theme_stylebox_override(st, sb)
	_id_edit.text_submitted.connect(func(_t: String) -> void: _find())
	## ID 只有字母和数字 ⇒ 给英文键盘(默认键盘在中文用户手上是拼音, 还多一条候选栏)。
	_id_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	add.add_child(_id_edit)
	## 手机上字打在键盘上方的输入条里; 条里的主键就是「查找」, 按下收键盘再查(原来点查找键盘不收, 结果出在键盘底下)。
	KeyboardBar.attach(_id_edit, {"primary": TXT_FIND, "primary_cb": func(_t: String) -> void: _find()})
	add.add_child(_btn(TXT_FIND, 110.0, _find, "FindBtn"))
	_find_box = VBoxContainer.new()
	_find_box.name = "FindResults"
	_find_box.add_theme_constant_override("separation", 6)
	v.add_child(_find_box)
	_msg_lbl = _lbl("", F_SUB, COL_MSG)
	_msg_lbl.name = "Msg"
	_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_lbl.custom_minimum_size = Vector2(LEFT_W - PAD * 2.0, 0)
	v.add_child(_msg_lbl)
	v.add_child(_sep())
	v.add_child(_lbl(TXT_REQS, F_CAP, COL_CAP))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(LEFT_W - PAD * 2.0, 0)
	UISkin.scrollbar(sc)
	v.add_child(sc)
	## 申请区占左栏剩下的高度(VBox 不会自己撑满父 Panel ⇒ 量出剩余量设成最小高)。
	v.custom_minimum_size.y = BOT_Y - TOP_Y - PAD * 2.0
	_req_box = VBoxContainer.new()
	_req_box.name = "Requests"
	_req_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_req_box.add_theme_constant_override("separation", 6)
	sc.add_child(_req_box)


func _copy_tag() -> void:
	DisplayServer.clipboard_set(_tag_lbl.text)
	_say("已复制玩家 ID")


func _find() -> void:
	if _busy > 0:
		return
	_clear(_find_box)
	_busy += 1
	FN.lookup(_id_edit.text, func(r: Dictionary) -> void:
		_busy -= 1
		if not is_inside_tree():
			return
		if not bool(r["ok"]):
			_say(FN.msg(str(r["reason"])))
			return
		var ppl: Array = (r["data"] as Dictionary).get("people", [])
		## ★玩家 ID 不唯一(方案书 R2): 回了几个就列几个, 让玩家按昵称认人。
		_say("找到 %d 位玩家，请核对昵称" % ppl.size() if ppl.size() > 1 else "")
		for c in ppl:
			if c is Dictionary:
				_find_box.add_child(_person_row(c, [[TXT_ASK, func() -> void: _ask(c), "AskBtn"]], "")))


func _ask(c: Dictionary) -> void:
	_act(func(done: Callable) -> void: FN.request(str(c.get("account", "")), done),
		func(d: Dictionary) -> void:
			_clear(_find_box)
			_id_edit.text = ""
			_say("已成为好友" if str(d.get("status", "")) == "accepted" else "已发送好友申请，等待对方同意"))


# ─────────────────────────────── 右栏 ───────────────────────────────

func _build_right(p: Control) -> void:
	var head := HBoxContainer.new()
	head.position = Vector2(PAD, PAD - 4.0)
	head.custom_minimum_size = Vector2(RIGHT_W - PAD * 2.0, 0)
	p.add_child(head)
	var t := _lbl(TXT_TITLE, F_CAP + 3, COL_CAP)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count_lbl = _lbl("", F_CAP + 3, COL_SUB)
	_count_lbl.name = "FriendCount"
	head.add_child(_count_lbl)
	var sc := ScrollContainer.new()
	sc.position = Vector2(PAD, PAD + 30.0)
	sc.size = Vector2(RIGHT_W - PAD * 2.0, BOT_Y - TOP_Y - PAD * 2.0 - 34.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UISkin.scrollbar(sc)
	p.add_child(sc)
	_friend_box = VBoxContainer.new()
	_friend_box.name = "Friends"
	_friend_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_box.add_theme_constant_override("separation", 8)
	sc.add_child(_friend_box)


func _render_list(d: Dictionary) -> void:
	_clear(_friend_box)
	_clear(_req_box)
	var fr: Array = d.get("friends", []) if d.get("friends") is Array else []
	_count_lbl.text = "%d / %d" % [fr.size(), int(d.get("cap", FN.CAP))]
	if fr.is_empty():
		var e := _lbl(TXT_EMPTY_FRIENDS, F_SUB + 2, COL_SUB)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(RIGHT_W - PAD * 2.0 - 20.0, 0)
		_friend_box.add_child(e)
	for c in fr:
		if not (c is Dictionary):
			continue
		var acc := str(c.get("account", ""))
		var sub := ("阵容更新于 " + ago(str(c.get("updated_at", "")), int(_P2C.now_utc()))) \
			if bool(c.get("has_lineup", false)) else TXT_NO_LINEUP
		## 主动作「切磋」宽、亮金边; 「删除」窄、压暗(两步确认) —— 主次分开, 别让删除和切磋一样抢眼。
		_friend_box.add_child(_person_row(c, [
			[TXT_SPAR, func() -> void: _spar(c), "SparBtn", 150.0, 1],
			[TXT_DEL_SURE if _del_armed == acc else TXT_DEL, func() -> void: _remove(c), "DelBtn",
				120.0 if _del_armed == acc else 92.0, -1],
		], sub))
	var inc: Array = d.get("incoming", []) if d.get("incoming") is Array else []
	var outg: Array = d.get("outgoing", []) if d.get("outgoing") is Array else []
	if inc.is_empty() and outg.is_empty():
		_req_box.add_child(_lbl(TXT_EMPTY_REQS, F_SUB, COL_SUB))
	for c in inc:
		if c is Dictionary:
			_req_box.add_child(_person_row(c, [
				[TXT_ACCEPT, func() -> void: _respond(c, true), "AcceptBtn", 92.0, 1],
				[TXT_DECLINE, func() -> void: _respond(c, false), "DeclineBtn"],
			], "", true))
	for c in outg:
		if c is Dictionary:
			_req_box.add_child(_person_row(c, [[TXT_CANCEL, func() -> void: _cancel(c), "CancelBtn"]], TXT_WAITING, true))


func _respond(c: Dictionary, accept: bool) -> void:
	_act(func(done: Callable) -> void: FN.respond(str(c.get("account", "")), accept, done),
		func(_d: Dictionary) -> void: _say("已成为好友" if accept else "已拒绝该申请"))


func _cancel(c: Dictionary) -> void:
	_act(func(done: Callable) -> void: FN.remove(str(c.get("account", "")), done),
		func(_d: Dictionary) -> void: _say("已撤回好友申请"))


func _remove(c: Dictionary) -> void:
	var acc := str(c.get("account", ""))
	var now := Time.get_ticks_msec()
	if _del_armed != acc or now - _del_armed_at > 3000:
		_del_armed = acc
		_del_armed_at = now
		## 推迟到这一帧末尾再重画(同闯关赛况板 `_hit`): 手指点按时引擎先发模拟鼠标松手(⇒ 走到这里), 紧接着把触摸松手
		##   也派给同一颗按钮 —— 当场重画会把它连行一起摘下树 ⇒ 引擎报 `Condition "!is_inside_tree()"`(verify_scroll_touch_sweep 手指点实测)。
		_render_list.call_deferred(data)
		return
	_del_armed = ""
	_act(func(done: Callable) -> void: FN.remove(acc, done),
		func(_d: Dictionary) -> void: _say("已解除好友关系"))


## 一次写操作: 发 → 成功后提示 + 重新取列表; 失败 ⇒ 屏上那句原因。
func _act(send: Callable, on_ok: Callable) -> void:
	if _busy > 0:
		return
	_busy += 1
	send.call(func(r: Dictionary) -> void:
		_busy -= 1
		if not is_inside_tree():
			return
		if not bool(r["ok"]):
			_say(FN.msg(str(r["reason"])))
			return
		on_ok.call(r["data"])
		refresh())


## 切磋: 我这边能不能打 → 取对方最新阵容(服务端验好友 + 本机验规则版本)→ 直接进战斗场。
func _spar(c: Dictionary) -> void:
	if _busy > 0:
		return
	var why := Spar.my_side_check()
	if why != "":
		_say(why)
		return
	_busy += 1
	_say("正在读取对方阵容…")
	FN.fetch_lineup(str(c.get("account", "")), func(r: Dictionary) -> void:
		_busy -= 1
		if not is_inside_tree():
			return
		if not bool(r["ok"]):
			_say(FN.msg(str(r["reason"])))
			return
		var d: Dictionary = r["data"]
		var err: String = spar_start.call(get_tree(), d.get("snapshot", {}), {
			"account": str(c.get("account", "")),
			"name": str(d.get("name", c.get("name", ""))),
			"tag": str(d.get("tag", c.get("tag", ""))),
			"avatar": str(c.get("lead", "")),
		})
		if err != "":
			_say(err))


# ─────────────────────────────── 件 ───────────────────────────────

## 一个人一行卡: 头像 · 昵称 / ID(+ 副行) · 右侧按钮。`narrow` = 左栏(窄, 按钮小一号字)。
func _person_row(c: Dictionary, btns: Array, sub: String, narrow: bool = false) -> Control:
	var card := PanelContainer.new()
	card.name = "Person"
	card.set_meta("account", str(c.get("account", "")))
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color("#0d1a28")
	fb.set_corner_radius_all(0)
	var sb := UISkin.nine("slot-frame.png", 12, fb)
	if sb is StyleBoxTexture:
		(sb as StyleBoxTexture).content_margin_left = 12
		(sb as StyleBoxTexture).content_margin_right = 12
		(sb as StyleBoxTexture).content_margin_top = 8
		(sb as StyleBoxTexture).content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(0, ROW_H)
	## ★★手机上好友 / 申请列表滑不动(2026-10-31 verify_scroll_touch_sweep 实测: 手指按在行上拖 160px, 滚动框收到 0 个事件、Δ=0;
	##   一屏可按的地方 90% 以上是行卡和行里的按钮): PanelContainer 默认 STOP, 事件到行卡就停了。
	##   行卡只是画框, 不收点击 ⇒ IGNORE; 行里的按钮 PASS(见下), 与闯关赛况板行框同一个修法。
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var nm := BL.shown_name(str(c.get("name", "")), str(c.get("tag", "")))
	h.add_child(MatchCard.avatar(str(c.get("lead", "")), AV_PX if not narrow else 52.0, false, false, nm))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	h.add_child(info)
	var n := _lbl(nm if nm != "" else "玩家", F_NAME if not narrow else F_NAME - 3, COL_NAME)
	n.name = "Name"
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	info.add_child(n)
	info.add_child(_lbl(str(c.get("tag", "")), F_SUB, COL_SUB))
	if sub != "":
		var s := _lbl(sub, F_SUB - 1, COL_SUB)
		s.name = "Sub"
		info.add_child(s)
	for b in btns:
		var w: float = float(b[3]) if b.size() > 3 else (92.0 if narrow else 120.0)
		var rb := _btn(str(b[0]), w, b[1], str(b[2]), int(b[4]) if b.size() > 4 else 0)
		## 按在「切磋 / 删除 / 同意…」上起手也要能滑: PASS 让拖动冒到滚动框;
		##   滑过的那一下不算点 —— 滚动框一开始拖就广播 SCROLL_BEGIN, 引擎自己把这颗按钮的按下作废(门禁「快甩」验过)。
		rb.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(rb)
	return card


## `rank`: 1 = 主动作(亮金边、字大一号); -1 = 次要(压暗、字小一号); 0 = 普通。皮都是 `UISkin.card_button`。
func _btn(t: String, w: float, cb: Callable, nm: String, rank: int = 0) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.custom_minimum_size = Vector2(w, BTN_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20 + rank * 2)
	b.focus_mode = Control.FOCUS_NONE
	UISkin.card_button(b)
	if rank > 0:
		for st in ["normal", "hover"]:
			var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
			if sb != null:
				sb.border_color = Color("#ffd27a")
				sb.set_border_width_all(4)
				b.add_theme_stylebox_override(st, sb)
	elif rank < 0:
		b.self_modulate = Color(0.78, 0.74, 0.70)
	b.pressed.connect(cb)
	return b


func _lbl(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sep() -> Control:
	var s := ColorRect.new()
	s.color = Color(0.35, 0.55, 0.70, 0.45)
	s.custom_minimum_size = Vector2(0, 2)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _panel(pos: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.12, 0.18, 0.9)
	psb.set_corner_radius_all(0)
	var ptex := UISkin.nine("panel-frame.png", 20, psb)
	if ptex is StyleBoxTexture:
		(ptex as StyleBoxTexture).modulate_color = Color(0.74, 0.94, 1.14, 1.0)
	panel.add_theme_stylebox_override("panel", ptex)
	panel.position = pos
	panel.size = sz
	add_child(panel)
	return panel


func _clear(box: Node) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()


func _say(t: String) -> void:
	last_msg = t
	if _msg_lbl != null:
		_msg_lbl.text = t


## 「阵容更新于 …」: 服务端时间串(ISO 8601, UTC) → 刚刚 / N 分钟前 / N 小时前 / N 天前。
static func ago(iso: String, now: int) -> String:
	if iso.length() < 19:
		return "—"
	var t := int(Time.get_unix_time_from_datetime_string(iso.left(19)))
	var d := maxi(0, now - t)
	if d < 60:
		return "刚刚"
	if d < 3600:
		return "%d 分钟前" % (d / 60)
	if d < 86400:
		return "%d 小时前" % (d / 3600)
	return "%d 天前" % (d / 86400)


func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.031, 0.047, 0.078, 0.38)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
