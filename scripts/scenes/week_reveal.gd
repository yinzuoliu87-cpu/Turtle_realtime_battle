class_name WeekReveal
extends RefCounted
## 本周羁绊开周揭晓(方案书 docs/plans/20261127b-本周羁绊开周揭晓.md; 参考 docs/studies/20261127-参考-酒馆战棋开局揭晓畸变.md)。
## 用户 11-27:「周二开赛…设计个东西去显示这周会出现的羁绊…可能要动画」「反正你就自己做一版吧，然后给我看一下成果的视频」。
## 触发: 周二起(积分赛 / 闯关 / 决赛)第一次进主菜单, 每个账号每周一次(FirstTips 记「week_reveal_<周锚点>」, 随存档 / 云存档走);
##   周一休赛(换版那天)不放; 没有周(演示 / 冷启动, of_week = 16 个全在)不放。主菜单排在收盘卡之后(menu_weekend.next_card), 一次一件事。
## 分段(方案书 §4 分段表):
##   ① 0.3 秒   压暗 + 标题「本周羁绊」与日期从上落下
##   ② 发牌     10 张卡背从下方飞到两行五张的位置(每张错开 0.04 秒)
##   ③ 逐张翻开 每 0.22 秒一张: 横向压扁 → 换正面 → 弹开; 翻开那一下卡框金光圈(Aseprite 6 帧)+ 上周没有的挂「新」
##   ④ 停留     卡框一圈金光沿边流动(week_card_rim.gdshader), 底部「点击继续」呼吸闪; 等玩家点
##   ⑤ 收起     每张卡泛白 → 碎成金色碎片飞向主菜单「商店」按钮(常驻的本周羁绊木牌在商店里), 压暗淡出
## 任何时候点一下: 发牌 / 翻牌中 ⇒ 直接全部翻开到 ④; ④ 里点 ⇒ ⑤。不读写对局状态、不动 RULES_VER。
## 素材全部 Aseprite 后台逐像素画(tools/assetgen/ase/week_reveal.lua + .aseprite): 卡背 / 卡面 / 翻开金光圈 / 碎片; 羁绊图标用现成的 tag-*.png。

const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")
const NODE_NAME := "WeekReveal"
const SEEN_PREFIX := "week_reveal_"
const V := "res://assets/sprites/ui/"
const BACK_TEX := V + "week-card-back.png"
const FRONT_TEX := V + "week-card-front.png"
const FLASH_TEX := V + "week-card-flash.png"
const SHARD_TEX := V + "week-shard.png"
const RIM_SHADER := "res://assets/shaders/week_card_rim.gdshader"
const W := 1280.0
const H := 720.0
const CARD := Vector2(192.0, 256.0)     # 卡面 96×128 原生 × 2(整数倍: 像素均匀; 11-27 用户问文字位置后从 1.75 改)
const PX := 2.0
const GAP := Vector2(20.0, 14.0)
const TOP := 136.0
const FLIP_EVERY := 0.22
const DEAL_EVERY := 0.04

var host: Control
var on_done: Callable
var ov: ColorRect
var box: Control
var cards: Array = []          # {root, back, front, flash, t}
var stage := 0                 # 1 发牌翻牌中 / 2 停留 / 3 收起
var master: Tween
var hint: Label
var syns: Array = []
var fresh: Array = []


## 这一周该不该放(纯判断, 不改状态)。now = 主菜单画面时刻(UTC 秒)。
static func due(gs, now: int) -> bool:
	if gs == null or bool(gs.get("tutorial_active")):
		return false
	var anchor: int = int(gs.get("week_anchor_ts"))
	if anchor <= 0 or WeeklySynergy.of_week(anchor).size() >= WeeklySynergy.ALL.size():
		return false
	if _P2C.phase_at_utc(now) == _P2C.PHASE_REST:
		return false
	return FirstTips.can_show(SEEN_PREFIX + str(anchor))


## 本周新轮进来的: 上线那周 = 6 个新羁绊; 之后 = 上周 10 个里没有的。
static func fresh_of(anchor: int) -> Array:
	if anchor == WeeklySynergy.LAUNCH_WEEK:
		return WeeklySynergy.LAUNCH_NEW.duplicate()
	var prev: Array = WeeklySynergy.of_week(anchor - 7 * 86400)
	var out: Array = []
	for t in WeeklySynergy.of_week(anchor):
		if not prev.has(t):
			out.append(t)
	return out


## 卡上那一句: 总述(TYPE_INTRO 第一条)里讲招牌机制的那一句 —— 第一句是「X 提高携带者的 Y」就取第二句, 只有一句就整句。
static func blurb(t: String) -> String:
	var lines: Array = _P2T.intro_lines(t)
	if lines.is_empty():
		return ""
	var s: String = SkillText.render_consts(Lang.t(str(lines[0])))
	## 卡上只放一句: 括号里的补充(「（包括召唤物）」)去掉 —— 图鉴里是全文。11-27 魔法书那句带括号最长, 拖得 10 张卡一起缩到 12 号字
	var rx := RegEx.create_from_string("（[^）]*）| ?[(][^)]*[)]")
	s = rx.sub(s, "", true)
	var parts: PackedStringArray = s.split("。", false)
	if parts.size() < 2:
		parts = s.split(". ", false)
	if parts.size() >= 2:
		var second: String = parts[1].strip_edges()
		return second + ("。" if s.contains("。") else ".")
	return s.strip_edges()


static func play(h: Control, anchor: int, done: Callable) -> WeekReveal:
	FirstTips.mark_seen(SEEN_PREFIX + str(anchor))
	var r := WeekReveal.new()
	r.host = h
	r.on_done = done
	r.syns = WeeklySynergy.of_week(anchor)
	r.fresh = fresh_of(anchor)
	r._build(anchor)
	return r


func _build(anchor: int) -> void:
	ov = ColorRect.new()
	ov.name = NODE_NAME
	ov.color = Color(0.02, 0.03, 0.06, 0.0)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.gui_input.connect(_on_input)
	ov.set_meta("reveal", self)    # 节点活着时持有本对象(RefCounted)
	host.add_child(ov)
	box = Control.new()
	box.name = "Box"
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.offset_left = -W * 0.5; box.offset_right = W * 0.5; box.offset_top = -H * 0.5; box.offset_bottom = H * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(box)
	## ① 标题 + 日期
	var title := _label(Lang.t("本周羁绊"), 52, Color("#ffe6a8"), Color("#2a1406"), 14)
	title.name = "Title"
	title.position = Vector2(0.0, -90.0); title.size = Vector2(W, 70.0)
	box.add_child(title)
	var d0: Dictionary = Time.get_datetime_dict_from_unix_time(anchor + 86400)       # 周二
	var d1: Dictionary = Time.get_datetime_dict_from_unix_time(anchor + 7 * 86400 - 1)   # 周日
	var sub := _label(Lang.t("%d 月 %d 日") % [int(d0["month"]), int(d0["day"])] + "  –  " + Lang.t("%d 月 %d 日") % [int(d1["month"]), int(d1["day"])], 22, Color("#cfd8ea"), Color("#0c1220"), 6)
	sub.name = "Dates"
	sub.position = Vector2(0.0, 96.0); sub.size = Vector2(W, 30.0); sub.modulate.a = 0.0
	box.add_child(sub)
	## ② 卡
	for i in range(syns.size()):
		cards.append(_card(i, str(syns[i])))
	## 10 张简介统一字号 = 最长那张放得下的那一档(各卡各缩一档看着参差)
	var px_min := 17
	for c in cards:
		px_min = mini(px_min, (c["ds"] as Label).get_theme_font_size("font_size"))
	for c in cards:
		(c["ds"] as Label).add_theme_font_size_override("font_size", px_min)
	hint = _label(Lang.t("点击继续"), 22, Color("#fff6dc"), Color("#0c1220"), 6)
	hint.name = "Hint"
	hint.position = Vector2(0.0, 670.0); hint.size = Vector2(W, 34.0); hint.modulate.a = 0.0
	box.add_child(hint)
	## 时间线(一根主补间; 跳过 = 杀掉它直接摆到 ④)
	stage = 1
	master = ov.create_tween()
	master.set_parallel(true)
	master.tween_property(ov, "color:a", 0.86, 0.3)
	master.tween_property(title, "position:y", 30.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	master.tween_property(sub, "modulate:a", 1.0, 0.3).set_delay(0.3)
	for i in range(cards.size()):
		var c: Dictionary = cards[i]
		var root: Control = c["root"]
		master.tween_property(root, "position", c["pos"], 0.32).set_delay(0.35 + DEAL_EVERY * float(i)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		master.tween_property(root, "modulate:a", 1.0, 0.15).set_delay(0.35 + DEAL_EVERY * float(i))
		master.tween_callback(_flip.bind(i)).set_delay(0.35 + DEAL_EVERY * float(cards.size()) + 0.3 + FLIP_EVERY * float(i))
	master.tween_callback(_to_hold).set_delay(0.35 + DEAL_EVERY * float(cards.size()) + 0.3 + FLIP_EVERY * float(cards.size()) + 0.3)


func _label(txt: String, px: int, col: Color, outline: Color, osz: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", osz)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _tex_rect(path: String, sz: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path) if ResourceLoader.exists(path) else null
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = sz
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _card(i: int, t: String) -> Dictionary:
	var col: int = i % 5
	var row: int = i / 5
	var x0: float = (W - (CARD.x * 5.0 + GAP.x * 4.0)) * 0.5
	var pos := Vector2(x0 + float(col) * (CARD.x + GAP.x), TOP + float(row) * (CARD.y + GAP.y))
	var root := Control.new()
	root.name = "Card_" + t
	root.size = CARD
	root.pivot_offset = CARD * 0.5
	root.position = Vector2(W * 0.5 - CARD.x * 0.5, H + 40.0)
	root.modulate.a = 0.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(root)
	var back := _tex_rect(BACK_TEX, CARD)
	back.name = "Back"
	root.add_child(back)
	var front := Control.new()
	front.name = "Front"
	front.size = CARD
	front.visible = false
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(front)
	front.add_child(_tex_rect(FRONT_TEX, CARD))
	var ic := _tex_rect(_P2T.icon_of(t), Vector2(32.0, 32.0) * PX)
	ic.position = Vector2(32.0, 16.0) * PX
	front.add_child(ic)
	var nm := _label(Lang.t(t), 22, Color("#fff2c8"), Color("#2a0a06"), 6)
	nm.position = Vector2(8.0, 56.0) * PX; nm.size = Vector2(80.0, 14.0) * PX   # 红条 55..70 内(去掉上下金线)
	front.add_child(nm)
	var ds := Label.new()
	ds.text = blurb(t)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ds.add_theme_font_size_override("font_size", 14)
	ds.add_theme_color_override("font_color", Color("#e9dcc2"))
	ds.add_theme_constant_override("line_spacing", 1)
	ds.position = Vector2(10.0, 72.0) * PX; ds.size = Vector2(76.0, 48.0) * PX   # 内框(离外沿 6 像素那道金线)以内: x 10..86, y 72..120
	ds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ds.clip_text = true
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(ds)
	## 放不下就缩字号(17 → 12), 不截断。★按字体直接算多行高度: 卡面这时还藏着(没翻开), Label 的行数量出来不准(11-27 一度全缩到 12 号)
	var fnt: Font = ds.get_theme_font("font")
	for px in [17, 16, 15, 14, 13, 12]:
		ds.add_theme_font_size_override("font_size", px)
		if fnt == null:
			break
		var hh: float = fnt.get_multiline_string_size(ds.text, HORIZONTAL_ALIGNMENT_CENTER, ds.size.x, px).y
		var lines: int = int(ceil(hh / fnt.get_height(px)))
		if hh + float(maxi(0, lines - 1)) * 1.0 <= ds.size.y:
			break
	if fresh.has(t):
		var nw := _label(Lang.t("新"), 18, Color("#ffffff"), Color("#5a0a06"), 6)
		nw.name = "New"
		var bg := ColorRect.new()
		bg.color = Color("#c8321e"); bg.size = Vector2(32.0, 24.0); bg.position = Vector2(87.0 * PX - 32.0, 8.0 * PX)   # 内框右上角以内, 不压金边铆钉
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nw.size = bg.size
		bg.add_child(nw)
		front.add_child(bg)
	var rim := ColorRect.new()
	rim.name = "Rim"
	rim.size = CARD
	rim.color = Color.WHITE
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(RIM_SHADER):
		var m := ShaderMaterial.new()
		m.shader = load(RIM_SHADER)
		m.set_shader_parameter("phase", float(i) * 0.1)
		m.set_shader_parameter("on", 0.0)
		rim.material = m
	front.add_child(rim)
	## 翻开金光圈(112×144 一格, 卡在中间, 四周各 8)
	var fl := TextureRect.new()
	fl.name = "Flash"
	var ft: Texture2D = load(FLASH_TEX) if ResourceLoader.exists(FLASH_TEX) else null
	if ft != null:
		var at := AtlasTexture.new(); at.atlas = ft; at.region = Rect2(0, 0, 112, 144)
		fl.texture = at
	fl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fl.stretch_mode = TextureRect.STRETCH_SCALE
	fl.size = Vector2(112.0, 144.0) * PX
	fl.position = -Vector2(8.0, 8.0) * PX
	fl.visible = false
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fl)
	return {"root": root, "back": back, "front": front, "flash": fl, "rim": rim, "pos": pos, "open": false, "ds": ds}


## ③ 翻一张: 横向压扁 → 换正面 → 弹开 + 金光圈 6 帧
func _flip(i: int) -> void:
	var c: Dictionary = cards[i]
	if bool(c["open"]):
		return
	c["open"] = true
	var root: Control = c["root"]
	var tw := ov.create_tween()
	tw.tween_property(root, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		(c["back"] as Control).visible = false
		(c["front"] as Control).visible = true
		_flash(c))
	tw.tween_property(root, "scale:x", 1.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(c: Dictionary) -> void:
	var fl: TextureRect = c["flash"]
	if not (fl.texture is AtlasTexture):
		return
	fl.visible = true
	var tw := ov.create_tween()
	tw.tween_method(func(k: float) -> void:
		(fl.texture as AtlasTexture).region = Rect2(112.0 * float(mini(5, int(k))), 0.0, 112.0, 144.0), 0.0, 6.0, 0.3)
	tw.tween_callback(func() -> void: fl.visible = false)


## ④ 停留: 全部翻开、卡框流光、「点击继续」呼吸
func _to_hold() -> void:
	if stage != 1:
		return
	stage = 2
	for c in cards:
		var root: Control = c["root"]
		root.position = c["pos"]
		root.modulate.a = 1.0
		root.scale = Vector2.ONE
		(c["back"] as Control).visible = false
		(c["front"] as Control).visible = true
		c["open"] = true
		var rim: ColorRect = c["rim"]
		if rim.material is ShaderMaterial:
			(rim.material as ShaderMaterial).set_shader_parameter("on", 1.0)
	var tl := box.get_node("Title") as Control
	tl.position.y = 30.0
	(box.get_node("Dates") as Control).modulate.a = 1.0
	ov.color.a = 0.86
	var tw := ov.create_tween().set_loops()
	tw.tween_property(hint, "modulate:a", 1.0, 0.6)
	tw.tween_property(hint, "modulate:a", 0.35, 0.6)


func _on_input(ev: InputEvent) -> void:
	var tap: bool = (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not tap:
		return
	ov.accept_event()
	if stage == 1:
		if master != null and master.is_valid():
			master.kill()
		_to_hold()
	elif stage == 2:
		_close()


## ⑤ 收起: 每张泛白 → 碎成金色碎片飞向商店按钮 → 压暗淡出
func _close() -> void:
	stage = 3
	hint.visible = false
	var target: Vector2 = _shop_target()
	var tw := ov.create_tween()
	tw.set_parallel(true)
	for i in range(cards.size()):
		var root: Control = cards[i]["root"]
		var dl: float = 0.025 * float(i)
		tw.tween_property(root, "modulate", Color(2.2, 2.0, 1.5, 1.0), 0.14).set_delay(dl)
		tw.tween_property(root, "scale", Vector2(0.2, 0.2), 0.22).set_delay(dl + 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(root, "modulate:a", 0.0, 0.12).set_delay(dl + 0.24)
		tw.tween_callback(_shards.bind(root, target)).set_delay(dl + 0.16)
	tw.tween_property(box.get_node("Title"), "modulate:a", 0.0, 0.25)
	tw.tween_property(box.get_node("Dates"), "modulate:a", 0.0, 0.25)
	tw.tween_property(ov, "color:a", 0.0, 0.4).set_delay(0.3)
	tw.tween_callback(_arrive_glow.bind(target)).set_delay(0.62)
	tw.chain().tween_interval(0.5)
	tw.chain().tween_callback(_finish)


func _shards(root: Control, target: Vector2) -> void:
	var st: Texture2D = load(SHARD_TEX) if ResourceLoader.exists(SHARD_TEX) else null
	if st == null:
		return
	var c0: Vector2 = root.global_position + CARD * 0.5 * root.scale
	for k in range(7):
		var s := TextureRect.new()
		var at := AtlasTexture.new(); at.atlas = st; at.region = Rect2(0, 0, 8, 8)
		s.texture = at
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.size = Vector2(20.0, 20.0)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.add_child(s)
		var a: float = TAU * float(k) / 7.0
		var p0: Vector2 = c0 - ov.global_position + Vector2(cos(a), sin(a)) * 12.0 - s.size * 0.5
		var mid: Vector2 = p0 + Vector2(cos(a), sin(a)) * 22.0
		var p1: Vector2 = target - ov.global_position - s.size * 0.5
		s.position = p0
		var tw := ov.create_tween()
		tw.tween_property(s, "position", mid, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position", p1, 0.3 + 0.015 * float(k)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_method(func(q: float) -> void:
			at.region = Rect2(8.0 * float(mini(3, int(q))), 0.0, 8.0, 8.0), 0.0, 4.0, 0.4)
		tw.tween_callback(s.queue_free)


## 碎片飞到时商店按钮那里亮一下(白色光斑染金, 叠加发光, 撑开淡掉)
func _arrive_glow(target: Vector2) -> void:
	var gp := "res://assets/sprites/vfx/candy-glow.png"
	if not ResourceLoader.exists(gp):
		return
	var g := TextureRect.new()
	g.texture = load(gp)
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.size = Vector2(150.0, 150.0)
	g.pivot_offset = g.size * 0.5
	g.position = target - ov.global_position - g.size * 0.5
	g.modulate = Color(1.0, 0.82, 0.35, 0.0)
	var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = m
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(g)
	g.scale = Vector2(0.4, 0.4)
	var tw := ov.create_tween().set_parallel(true)
	tw.tween_property(g, "modulate:a", 1.0, 0.08)
	tw.tween_property(g, "scale", Vector2(1.3, 1.3), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "modulate:a", 0.0, 0.3).set_delay(0.12)


## 主菜单「商店」按钮的中心(画布坐标); 找不到 ⇒ 右上角。
func _shop_target() -> Vector2:
	var want: String = Lang.t("商店")
	for n in host.find_children("*", "", true, false):
		if n is Button and (n as Button).text == want and (n as Control).is_visible_in_tree():
			return (n as Control).global_position + (n as Control).size * 0.5
		if n is Label and (n as Label).text == want and (n as Control).is_visible_in_tree():
			return (n as Control).global_position + (n as Control).size * 0.5
	return Vector2(ov.size.x - 80.0, 60.0)


func _finish() -> void:
	if is_instance_valid(ov):
		ov.queue_free()
	if on_done.is_valid():
		on_done.call()
