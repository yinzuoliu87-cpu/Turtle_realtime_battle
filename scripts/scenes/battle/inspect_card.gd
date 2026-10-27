class_name InspectCard
extends RefCounted
## 信息面板【左侧】弹出的独立小卡 —— 点装备 / 技能 / 属性图标时出现(2026-10-06 重做)。
##
## ★用户原话:「人家如果点击了技能图标或装备图标，人家是会弹新窗口来显示技能信息或装备信息的」
##   「比如人家点击图片后，就会弹这种小框」。参考图 docs/plans/ref/20261006-云顶装备弹窗/。
## ★版式照云顶(方案书 docs/plans/20261006-对局信息面板重做.md 第二节):
##   头部 = 图标 + 名字(+ 右侧小标签) → 属性行(图标+数字) → 细线 → 正文
##   → 特殊段/脚注(灰斜体) → [技能] 细线 + 数值拆解表 / [装备] 细线 + 本局统计。
## ★面板本身不动 —— 小卡是挂在 _ui_layer 上的独立节点, 贴着面板左沿。
## ★一次只开一张; 再点同一个图标 = 收起; 面板关了小卡跟着关(见 close())。
## ★卡比可用高度高(2026-10-27: 小木斧 3 星宽 300 时高 1994, 四个形态 + 四个造物全列、内容不删)⇒
##   卡头(图标 / 名字 / 星级 / 属性行)不动, 正文到「本局」那一段改成卡内上下滑动(_fit), 卡总高收进可用高度:
##   上边 TOP_Y; 下边 = 屏幕底边, 回放 / 观赛时 = 与小卡横向重叠的操作条上沿; 各留 EDGE。

const HUD_TEX := "res://assets/sprites/battlehud/"
const CARD_W := 300.0
const GAP := 8.0                      # 小卡右沿与面板左沿的间距
const ICON := 44.0                    # 头部图标边长
const TOP_Y := 50.0                   # 卡顶最高到这(顶栏下沿)
const EDGE := 8.0                     # 卡底与屏幕底边 / 操作条上沿留的缝
## 卡内滚动框(正文那段放不下时才建)。门禁按名字找它。
const N_SCROLL := "CardScroll"
const N_FLOW := "CardFlow"
const SCROLL_MIN_H := 60.0            # 滚动框最少露这么高(卡头再高也不压成一条缝)
const SCROLL_GUTTER := UISkin.SCROLL_W + 4.0   # 正文给竖滚动条让出的宽(条宽跟皮走, 再留 4; 与商店 CardBodyScroll 同一个口径)
const SCROLL_DEADZONE := 8            # 手指按下后挪过这么多像素才算拖动(点一下手抖不滚)
const SNAP_MAX := 40.0                # 收整行时最多收这么多(切在大块非正文控件中间时不收)
## 宿主摆位(商店 / 背包)时先让宿主自己收卡高 —— 商店 _refit_card 隔两帧把正文装进它的 CardBodyScroll、再隔一帧定位;
##   这里再多等一帧才看还放不放得下, 放得下就什么都不做(不套第二层滚动)。
const HOST_SETTLE_FRAMES := 4
## 装备属性名 → 属性图标(assets/sprites/stats/<x>-icon.png)。局内信息面板与商店小卡共用这一份。
const EQ_STAT_ICON := {"攻击力": "atk", "最大生命值": "hp", "护甲": "def", "魔抗": "mr", "暴击率": "crit",
	"暴击伤害": "crit-dmg", "护甲穿透": "armorpen", "魔法穿透": "magicpen", "生命偷取": "lifesteal",
	"闪避": "dodge", "反伤": "reflect", "治疗增幅": "healamp", "护盾增幅": "shieldamp",
	"治疗与护盾增幅": "shieldheal", "初始龟能": "maxenergy", "龟能充能速率": "echarge", "射程": "range",
	"攻击速度": "aspd", "移动速度": "move", "攻击射程": "range"}


## 装备属性一行 [名, 值] → 小卡 `stats` 的一项 [图标路径, 文字, 颜色]。
##   有图标 ⇒ 只写数值(图标就是属性名); 没有 ⇒ 「名 值」。图标在 `open()` 里按属性染色(stat_icon_color_of)。
static func eq_stat_row(kv: Array, col: Color) -> Array:
	var ik := str(EQ_STAT_ICON.get(str(kv[0]), ""))
	if ik == "":
		return ["", "%s %s" % [kv[0], kv[1]], col]
	return ["res://assets/sprites/stats/%s-icon.png" % ik, str(kv[1]), col]

const C_TITLE := Color("#f4ead8")
const C_BODY := Color("#d2c7b4")
const C_DIM := Color("#8c7f6c")
const C_LINE := Color(0.65, 0.47, 0.16, 0.55)   # 细线 = 面板黄铜边的淡色

var battle
var card: PanelContainer = null
var key: String = ""
## 每帧刷新要改的节点(技能正文 / 装备本局统计 / 属性数值), 由调用方按 key 取。
var live: Dictionary = {}
var _w: float = CARD_W
## 字号下限(商店手机版 2026-10-21 传 20 = 手机上约 11pt)。0 = 不设(局内信息面板照旧)。
var _min_px: int = 0
## open() 建的正文那一段(细线 / 正文 / 脚注 / 拆解表 / 本局), 卡放不下时整段挪进滚动框。
##   卡头、属性行、宿主接在卡底的按钮(背包「卖出 / 详情」)不在里面 —— 它们不滚, 永远看得见。
var _flow: Array = []
var _scroll: ScrollContainer = null


func _init(b) -> void:
	battle = b


func is_open(k: String) -> bool:
	return card != null and is_instance_valid(card) and key == k


func close() -> void:
	if card != null and is_instance_valid(card):
		var p := card.get_parent()
		if p != null:
			p.remove_child(card)
		card.queue_free()
	card = null
	key = ""
	live = {}
	_flow = []
	_scroll = null


## 打开一张卡。spec:
##   icon: 贴图路径("" = 不画) · icon_tint: 白模板图标的染色(属性图标用)
##   title · title_col · tag(右上小字, 如「天生」「技能」「★★」) · tag_col
##   stats: [[图标路径, 文字, 颜色], ...] 头部下面那一行(装备加的属性 / 属性当前值)
##   body: bbcode 正文 · foot: bbcode 灰斜体脚注
##   table: [[左, 右], ...] 技能的数值拆解表(两列, bbcode)
##   extra_title + extra: 装备的「本局统计」(纯文本, 每行一项)
##   head_right: 放在卡头最右边的控件(商店的「购买」, 2026-10-22 用户「购买按钮放右上角」)
## anchor = 被点的那个控件(小卡顶边对齐它)。返回 live 字典。
func open(k: String, anchor: Control, spec: Dictionary) -> Dictionary:
	if is_open(k):
		close()                          # 再点一次 = 收起
		return {}
	close()
	## ★宿主若提供 inspect_card_pos(card, h) 就由它定位置(商店 2026-10-18 复用这张卡), 此时不需要信息面板。
	var _custom: bool = battle.has_method("inspect_card_pos")
	if battle._ui_layer == null or (not _custom and (battle._info_panel == null or not is_instance_valid(battle._info_panel))):
		return {}
	_w = float(spec.get("width", CARD_W))
	_min_px = int(spec.get("min_px", 0))
	key = k
	card = PanelContainer.new()
	card.name = "InspectCard"
	card.add_theme_stylebox_override("panel", _frame(spec.get("frame_col", null)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP   # 点在卡上不穿到战场(否则会关掉面板)
	card.custom_minimum_size = Vector2(_w, 0)
	card.size = Vector2(_w, 0)
	battle._ui_layer.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	_head(vb, spec)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		_stat_row(vb, stats)
	var n_head := vb.get_child_count()
	var body := str(spec.get("body", ""))
	if body != "":
		_line(vb)
		live["body"] = _rtl(vb, body, int(spec.get("body_px", 14)), C_BODY)
	var foot := str(spec.get("foot", ""))
	if foot != "":
		_rtl(vb, foot, 12, C_DIM)
	var table: Array = spec.get("table", [])
	if not table.is_empty():
		_line(vb)
		live["table"] = _table(vb, table)
	if spec.has("extra_title"):
		_line(vb)
		var et := _label(vb, str(spec["extra_title"]), 12, C_DIM)
		et.name = "ExtraTitle"
		var ex := _label(vb, str(spec.get("extra", "")), 13, C_BODY)
		ex.name = "Extra"
		ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		live["extra"] = ex
		live["extra_title"] = et
	_flow = vb.get_children().slice(n_head)
	live["vbox"] = vb
	_place(anchor)
	return live


## 九宫格框: insp-card.png(新画·深暖黑 + 细黄铜边), 缺图时退回纯色。
func _frame(col = null) -> StyleBox:
	## ★装备卡: 整个框按费用上色(用户 2026-10-06「装备详细窗口也是，名字也是」)。
	if col is Color:
		var cf := StyleBoxFlat.new()
		cf.bg_color = Color(0.07, 0.055, 0.04, 0.98)
		cf.set_border_width_all(2); cf.border_color = col
		cf.set_corner_radius_all(0)
		cf.shadow_color = Color(0, 0, 0, 1); cf.shadow_size = 2
		cf.content_margin_left = 14; cf.content_margin_right = 14
		cf.content_margin_top = 12; cf.content_margin_bottom = 12
		return cf
	var p := HUD_TEX + "insp-card.png"
	if ResourceLoader.exists(p):
		var t := StyleBoxTexture.new()
		t.texture = load(p)
		t.set_texture_margin_all(12)
		t.content_margin_left = 14; t.content_margin_right = 14
		t.content_margin_top = 12; t.content_margin_bottom = 12
		return t
	var f := StyleBoxFlat.new()
	f.bg_color = Color("#120e0a")
	f.set_border_width_all(2); f.border_color = Color("#a5751d")
	f.set_content_margin_all(12)
	return f


func _head(vb: VBoxContainer, spec: Dictionary) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	var ip := str(spec.get("icon", ""))
	if ip != "" and ResourceLoader.exists(ip):
		var box := PanelContainer.new()
		var bsb: StyleBox = _slot_box()
		if spec.has("icon_border"):          # 装备: 图标框按费用上色(与面板里的槽同色)
			var fb := StyleBoxFlat.new()
			fb.bg_color = Color("#0c0907")
			fb.set_border_width_all(2); fb.border_color = spec["icon_border"]
			fb.set_corner_radius_all(0); fb.set_content_margin_all(3)
			bsb = fb
		box.add_theme_stylebox_override("panel", bsb)
		box.custom_minimum_size = Vector2(ICON, ICON) if _min_px <= 0 else Vector2(56, 56)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(box)
		var tr := TextureRect.new()
		tr.texture = load(ip)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec.has("icon_tint"):
			tr.modulate = spec["icon_tint"]
		box.add_child(tr)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(col)
	var tl := _label(col, str(spec.get("title", "")), 17, spec.get("title_col", C_TITLE))
	tl.name = "Title"
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tag := str(spec.get("tag", ""))
	if spec.has("tag_bb"):                # 带行内图标的标签(商店: 价格 · 类型图标 + 类型名)
		var tr2 := _rtl(col, str(spec["tag_bb"]), 13, spec.get("tag_col", C_DIM))
		tr2.name = "Tag"
		tr2.custom_minimum_size = Vector2(0, 0)
	elif tag != "":
		_label(col, tag, 12, spec.get("tag_col", C_DIM)).name = "Tag"
	var hr = spec.get("head_right", null)
	if hr is Control:
		(hr as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(hr)


## 头部下那一行: 图标 + 数字横排(云顶的 ❤+250 ⚔+25%)。
func _stat_row(vb: VBoxContainer, stats: Array) -> void:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 12)
	fl.add_theme_constant_override("v_separation", 2)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.name = "StatRow"
	vb.add_child(fl)
	for s in stats:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.add_child(hb)
		var ip := str(s[0])
		if ip != "" and ResourceLoader.exists(ip):
			var tr := TextureRect.new()
			tr.texture = load(ip)
			tr.modulate = SkillText.stat_icon_color_of(ip)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.custom_minimum_size = Vector2(18, 18) if _min_px <= 0 else Vector2(24, 24)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(tr)
		var l := _label(hb, str(s[1]), 15, s[2] if s.size() > 2 else C_TITLE)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not live.has("stat_lbls"):
			live["stat_lbls"] = []
		(live["stat_lbls"] as Array).append(l)


func _line(vb: VBoxContainer) -> void:
	var r := ColorRect.new()
	r.color = C_LINE
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(r)


func _rtl(vb: Control, bb: String, px: int, col: Color) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	px = maxi(px, _min_px)
	t.add_theme_font_size_override("normal_font_size", px)
	t.add_theme_font_size_override("bold_font_size", px)
	t.add_theme_font_size_override("italics_font_size", px)
	t.add_theme_color_override("default_color", col)
	t.custom_minimum_size = Vector2(_w - 28.0, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.text = bb
	vb.add_child(t)
	return t


func _label(parent: Control, txt: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", maxi(px, _min_px))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 技能拆解表: 每行 [左(项目: 当前值 = 系数), 右(补充)]。两列各一个 RichTextLabel。
func _table(vb: VBoxContainer, rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hb)
		var l := _rtl(hb, str(r[0]), 13, C_BODY)
		l.custom_minimum_size = Vector2(0, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var rr := _rtl(hb, str(r[1]) if r.size() > 1 else "", 13, C_DIM)
		rr.custom_minimum_size = Vector2(0, 0)
		rr.autowrap_mode = TextServer.AUTOWRAP_OFF
		rr.fit_content = true
		out.append(l)
	return out


func _slot_box() -> StyleBox:
	var p := HUD_TEX + "insp-slot.png"
	if ResourceLoader.exists(p):
		var t := StyleBoxTexture.new()
		t.texture = load(p)
		t.set_texture_margin_all(6)
		t.set_content_margin_all(3)
		return t
	var f := StyleBoxFlat.new()
	f.bg_color = Color("#0c0907")
	return f


## 摆位: 右沿贴面板左沿(留 GAP), 顶边对齐被点的控件; 超出视口就往上收。
## ★高度要等一帧排完版才准(RichTextLabel fit_content) ⇒ 先摆一次, 下一帧再按真实高收一次。
## ★收到顶还放不下 ⇒ 正文那段改成卡内上下滑动(_fit); 宿主摆位时等宿主自己收完再看(HOST_SETTLE_FRAMES)。
func _place(anchor: Control) -> void:
	_place_now(anchor)
	var c := card
	await battle.get_tree().process_frame
	if not is_instance_valid(battle):
		return
	if c == card and is_instance_valid(c):
		var a: Control = anchor if is_instance_valid(anchor) else null   # 被点的槽这一帧里可能已被重建掉
		c.size = Vector2(_w, 0)              # 让容器按内容重算高度
		_place_now(a)
		_fit_after(c, a, HOST_SETTLE_FRAMES if battle.has_method("inspect_card_pos") else 0)


func _place_now(anchor: Control) -> void:
	if card == null or not is_instance_valid(card):
		return
	var h: float = maxf(card.get_combined_minimum_size().y, card.size.y)
	if battle.has_method("inspect_card_pos"):
		card.position = battle.inspect_card_pos(card, h)
		return
	var y: float = 54.0
	if anchor != null and is_instance_valid(anchor):
		y = anchor.get_global_rect().position.y - 6.0
	## ★底边避开回放 / 观赛的底部操作条(2026-10-27 用户截图: 铜管手铳的说明下半截被进度条挡住, 文字断在「上限为 1」)。
	##   操作条在 _ui_layer 上面一层(replay_controls.gd 为了压住血条), 卡挂在 _ui_layer ⇒ 往上收;
	##   收到 TOP_Y 还放不下的长卡由 _fit 改成卡内滑动, 卡总高本身就收在操作条上沿之上 —— 不挪层、不压操作条。
	var x: float = _card_x()
	y = clampf(y, TOP_Y, maxf(TOP_Y, _bottom_y(x) - h))
	card.position = Vector2(x, y)


## 小卡左沿: 右沿贴信息面板左沿(留 GAP)。面板已经不在(这几帧里被关掉)⇒ 原地不动。
func _card_x() -> float:
	var ip = battle.get("_info_panel")
	if ip != null and is_instance_valid(ip) and ip is Control:
		return (ip as Control).get_global_rect().position.x - GAP - CARD_W
	return card.position.x


## 屏幕底边能用到的最低处: 视口底 − 底部手势条(SafeArea; 桌面 / 无头为 0) − EDGE。
func _screen_bottom() -> float:
	var vr: Rect2 = battle.get_viewport().get_visible_rect()
	return vr.end.y - SafeArea.insets(vr.size).w - EDGE


## 卡底能到的最低处(局内): 屏幕底边; 回放 / 观赛时与小卡横向重叠的那块操作条的上沿。各留 EDGE。
func _bottom_y(x: float) -> float:
	var bottom: float = _screen_bottom()
	var bar_top: float = _bottom_bar_top(x, x + CARD_W)
	if bar_top > 0.0:
		bottom = minf(bottom, bar_top - EDGE)
	return bottom


## 回放 / 观赛时底部操作条的上沿(只算与小卡横向 [x0, x1] 有重叠的那几块); 不在回放 / 都不重叠 = -1。
##   回放 = 底部整条 ReplayStrip; 观赛 = 左下角一颗「退出」(老观赛叫 N_LIVE_EXIT, 逐帧直播叫 N_EXIT)。
##   ★只算横向重叠的: 左下角那颗「退出」离小卡很远, 不该把小卡也往上顶。
func _bottom_bar_top(x0: float, x1: float) -> float:
	var hud = battle.get("_hud")
	var rb = hud.get("_replay_bar") if hud != null else null
	if rb == null or not is_instance_valid(rb) or not (rb as Control).is_visible_in_tree():
		return -1.0
	var top := -1.0
	for nm in ["ReplayStrip", ReplayControls.N_EXIT, ReplayControls.N_LIVE_EXIT]:
		var c := (rb as Node).find_child(nm, true, false) as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		if r.end.x <= x0 or r.position.x >= x1:
			continue
		top = r.position.y if top < 0.0 else minf(top, r.position.y)
	return top


## 卡能用的总高。局内 = 从 TOP_Y 到 _bottom_y; 宿主摆位 = 从宿主给这张卡(按现在的高)的卡顶到 _screen_bottom,
##   换算到卡的父节点坐标里量(背包 / 商店的卡可能被 UIFrame 收进居中的设计框)。
func _room(h: float) -> float:
	if not battle.has_method("inspect_card_pos"):
		return _bottom_y(_card_x()) - TOP_Y
	var top: float = (battle.inspect_card_pos(card, h) as Vector2).y
	var bottom_g := Vector2(0.0, _screen_bottom())
	var par := card.get_parent() as CanvasItem
	var bottom: float = (par.get_global_transform().affine_inverse() * bottom_g).y if par != null else bottom_g.y
	return bottom - top


## 隔 frames 帧再 _fit。挂在树信号上的一次性回调, 不用 await —— 宿主在这几帧里没了(离开商店 / 门禁拆场)这条连接跟着断,
##   不会在已释放的实例上恢复。★c / anchor 不标类型: 卡在这几帧里被关掉(商店整页重建)时绑着的是已释放的对象,
##   标了 Control 会在调用这一刻报参数类型错; 先判 is_instance_valid 再用。
func _fit_after(c, anchor, frames: int) -> void:
	if not is_instance_valid(c) or c != card or not is_instance_valid(battle) or not battle.is_inside_tree():
		return
	var a: Control = anchor as Control if is_instance_valid(anchor) else null
	if frames > 0:
		battle.get_tree().process_frame.connect(_fit_after.bind(c, a, frames - 1), CONNECT_ONE_SHOT)
		return
	if _fit(a):
		## 正文按让出滚动条后的宽重排要等一帧; 排完把可见高收到整行, 再摆一次
		battle.get_tree().process_frame.connect(_snap_after.bind(c, a), CONNECT_ONE_SHOT)


func _snap_after(c, anchor) -> void:
	if not is_instance_valid(c) or c != card or not is_instance_valid(battle):
		return
	_snap_flow()
	(c as Control).size = Vector2(_w, 0)
	_place_now(anchor as Control if is_instance_valid(anchor) else null)


## 卡比可用高度高 ⇒ 正文那段装进卡内滚动框, 可见高 = 可用高 − 不滚的那部分(卡头 / 属性行 / 宿主按钮 / 边距), 卡总高 = 可用高。
## 返回 true = 这次装了滚动框(调用方等一帧排版后收整行)。放得下 / 宿主已自己装了滚动框 ⇒ false, 什么都不动。
func _fit(anchor: Control) -> bool:
	if card == null or not is_instance_valid(card) or _scroll != null:
		return false
	card.size = Vector2(_w, 0)
	var room: float = _room(card.get_combined_minimum_size().y)
	if card.get_combined_minimum_size().y <= room + 0.5:
		return false
	## 宿主已经把正文装进它自己的滚动框(商店 CardBodyScroll)⇒ 卡高归宿主管, 不套第二层
	if not card.find_children("*", "ScrollContainer", true, false).is_empty():
		return false
	if not _wrap_flow():
		return false
	_scroll.custom_minimum_size.y = 0.0
	card.size = Vector2(_w, 0)
	var fixed_h: float = card.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = maxf(SCROLL_MIN_H, floorf(room - fixed_h))
	card.size = Vector2(_w, 0)
	_place_now(anchor)
	return true


## 把正文那段(_flow, 不含打头那道细线)原样挪进卡内滚动框, 滚动框放回它原来的位置。
## ★滚动框 PASS、里面的字全 IGNORE ⇒ 按下落在滚动框上: 滚轮、手机按住拖动(Godot 有触屏时才开的拖动滚)都由它接,
##   再往上交给卡(STOP)吃掉 —— 不会穿到战场 / 背包底去关面板、关卡。
func _wrap_flow() -> bool:
	var vb = live.get("vbox")
	if vb == null or not is_instance_valid(vb):
		return false
	var nodes: Array = []
	for n in _flow:
		if is_instance_valid(n) and (n as Node).get_parent() == vb:
			nodes.append(n)
	## 卡头下面那道细线留在滚动框外: 滚动时正文从线下面滑过, 卡头和正文始终隔着它
	while not nodes.is_empty() and nodes[0] is ColorRect:
		nodes.pop_front()
	if nodes.is_empty():
		return false
	var sc := ScrollContainer.new()
	sc.name = N_SCROLL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.follow_focus = false
	sc.scroll_deadzone = SCROLL_DEADZONE
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	UISkin.scrollbar(sc)
	var inner := VBoxContainer.new()
	inner.name = N_FLOW
	inner.add_theme_constant_override("separation", (vb as VBoxContainer).get_theme_constant("separation"))
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(inner)
	var at: int = (nodes[0] as Node).get_index()
	(vb as Node).add_child(sc)
	(vb as Node).move_child(sc, at)
	for n in nodes:
		(vb as Node).remove_child(n)
		inner.add_child(n)
		if n is RichTextLabel and (n as Control).custom_minimum_size.x > 0.0:
			(n as Control).custom_minimum_size.x = maxf(0.0, (n as Control).custom_minimum_size.x - SCROLL_GUTTER)
	_scroll = sc
	return true


## 滚动框可见高收到【整行】: 按像素倒推的可见高常常切在某一行中间, 框底露出半行字头像一道脏线
##   (与商店 _snap_card_body 2026-10-22 同一个由来)。只收不放 ⇒ 卡不会因此变高、仍在可用高度里。
func _snap_flow() -> void:
	if _scroll == null or not is_instance_valid(_scroll) or _scroll.get_child_count() == 0:
		return
	var inner := _scroll.get_child(0) as Control
	var vis: float = _scroll.custom_minimum_size.y
	for ch in inner.get_children():
		var c := ch as Control
		if c == null or not c.visible or c.position.y + c.size.y <= vis + 0.5:
			continue
		var keep: float = c.position.y
		if c is RichTextLabel:
			var rt := c as RichTextLabel
			for i in range(1, rt.get_line_count()):
				var lt: float = c.position.y + rt.get_line_offset(i)
				if lt > vis + 0.5:
					break
				keep = lt
		if keep >= SCROLL_MIN_H and keep < vis - 0.5 and vis - keep <= SNAP_MAX:
			_scroll.custom_minimum_size.y = keep
		return
