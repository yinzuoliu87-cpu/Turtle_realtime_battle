extends PanelContainer
## 全局决赛日小条(2026-10-31 方案书 20261031c 块 M ④ · G16 / J-2 / 9-1): 周日开赛期间每一屏都挂着
##   「阶段 · (开播中) · 一句我的处境 / 下一场 · 倒计时」, 点了直达对阵图(开播中 ⇒ 直达那一场)。
## 画法: 不透明暗金底 + 2px 金边 + 直角 + 4px 硬投影(像素 UI 的招牌, 与对阵图冠军牌同一套; 半透底 + 描边会被判成网页盒)。
## 摆在哪由 finals_day_layer 量出来(避开当前这一屏所有看得见的按钮), 这里只管长什么样。

const BADGE := "res://assets/sprites/menu/weekend/badge-finals.png"
const N_HEAD := "FdBarHead"
const N_LIVE := "FdBarLive"
const N_BODY := "FdBarBody"
const N_CD := "FdBarCd"

const H := 48.0
const FONT := 18
const FONT_CD := 20
const GOLD := Color("#d9a441")
const BG := Color("#1d1708")
const RED := Color("#d8473f")

var head: Label
var live_chip: PanelContainer
var live_dot: ColorRect
var body: Label
var cd: Label
var tappable := false
## 门禁读: 正文换过几次字(换字那一下冲亮)
var flashes := 0
var _cd_w := 0.0


func _init() -> void:
	name = "FinalsDayBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color("#04070e")
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(4, 4)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(0, H)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	if ResourceLoader.exists(BADGE):
		var bd := TextureRect.new()
		bd.texture = load(BADGE)
		bd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bd.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		bd.custom_minimum_size = Vector2(34, 38)
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bd)
	head = _lb(N_HEAD, FONT, Color("#ffd27a"))
	row.add_child(head)
	## 「开播中」红签 + 一闪一闪的点(开播 / 进行中才亮)
	live_chip = PanelContainer.new()
	live_chip.name = N_LIVE
	live_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := StyleBoxFlat.new()
	ls.bg_color = RED
	ls.set_corner_radius_all(0)
	ls.content_margin_left = 6
	ls.content_margin_right = 8
	ls.content_margin_top = 1
	ls.content_margin_bottom = 1
	live_chip.add_theme_stylebox_override("panel", ls)
	live_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 5)
	lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_chip.add_child(lr)
	live_dot = ColorRect.new()
	live_dot.color = Color("#fff4ee")
	live_dot.custom_minimum_size = Vector2(6, 6)
	live_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lr.add_child(live_dot)
	var lt := _lb("FdBarLiveText", 15, Color("#fff4ee"))
	lt.text = "开播中"
	lr.add_child(lt)
	row.add_child(live_chip)
	live_chip.visible = false
	var sep := ColorRect.new()
	sep.color = Color("#6a5430")
	sep.custom_minimum_size = Vector2(2, 26)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	body = _lb(N_BODY, FONT, Color("#fff1d6"))
	row.add_child(body)
	cd = _lb(N_CD, FONT_CD, Color("#ffe27a"))
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cd)
	## 点击区不在这里: 条只有 48 高, 触摸线 81 由 layer 在条外面补一颗透明键(见 finals_day_layer `_hit`)。


func _ready() -> void:
	## 开播点: 一秒一闪(真在动)
	var tw := create_tween().set_loops()
	tw.tween_property(live_dot, "modulate:a", 0.15, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(live_dot, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func _lb(nm: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.name = nm
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 画一行: {"head", "body", "cd"(秒, < 0 不显示), "live", "tap"}。
func paint(line: Dictionary) -> void:
	var h := str(line.get("head", ""))
	if head.text != h:
		head.text = h
	live_chip.visible = bool(line.get("live", false))
	var b := str(line.get("body", ""))
	if body.text != b:
		var first := body.text == ""
		body.text = b
		if not first:
			_flash()
	var c := int(line.get("cd", -1))
	cd.visible = c >= 0
	if c >= 0:
		cd.text = _clock(c)
		## 倒计时那一格按最宽的「0:00:00」留宽, 数字跳动时整条不抖
		if _cd_w <= 0.0:
			var f: Font = cd.get_theme_font("font")
			_cd_w = ceilf(f.get_string_size("0:00:00", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CD).x) + 4.0 if f != null else 76.0
		cd.custom_minimum_size.x = _cd_w if c >= 600 else _cd_w * 0.72
	tappable = bool(line.get("tap", false))
	reset_size()


## 十分钟以上写满「0:19:56」(紧跟在「18:00 开赛」后面, 只写「19:56」分不清是时刻还是剩多久); 十分钟以内「4:07」。
static func _clock(sec: int) -> String:
	var s := maxi(0, sec)
	if s >= 600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## 正文换字那一下: 冲亮再落回(与主菜单阶段切换同一组数)。
func _flash() -> void:
	flashes += 1
	body.modulate = Color(1.9, 1.75, 1.3, 1.0)
	body.create_tween().tween_property(body, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
