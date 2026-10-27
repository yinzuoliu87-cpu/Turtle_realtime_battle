extends Control
## 首启流程(2026-10-21 v4, 方案书 docs/plans/20261020-教程重写.md §v4)。
##
## 用户 2026-10-21:「第一次打开你得介绍这个游戏，然后问玩家要不要新手教程吧」。
##   顺序: 游戏介绍(本屏, 独立全屏, 不压在主菜单上) → 问「开始教程 / 跳过」→
##     开始: 直接进教程第一战(TutorialDirector.enter) …… 完成教程 → 起名(本屏 name 模式) → 主菜单
##     跳过: 起名(就在本屏) → 主菜单
##
## 每一处照的实机画面(docs/plans/ref/20261021-新手引导实机/, 时间码 = 录像内时间):
##   · 介绍 = 真实游戏画面上压一句短句, 自动往下走、点一下翻页:
##       Marvel Snap 00:24「WELCOME TO MARVEL SNAP」整屏标题卡(MarvelSnap/00m24s_WelcomeTo.jpg);
##       Marvel Snap 01:07「Win 2 out of 3 Locations!」一句规则压在真实对局上(MarvelSnap/01m07.5s_赢3处中2处.jpg);
##       皇室战争 00:20「Welcome to Clash Royale!」→ 00:22「Let's complete some training matches first!」
##         真实竞技场上一句一句(皇室战争ClashRoyale/00m20s_欢迎.jpg、00m22.5s_国王_先打几场训练.jpg)。
##   · 右上「跳过」= 炉石 02:07 右上常驻 Skip(炉石传说Hearthstone/02m07.5s_攻击提示_右上Skip.jpg)。
##   · 问要不要教程 = 云顶之弈 00:56「Greetings, tactician! Are you new?」✗/✓ 小框压在压暗的上一屏上
##       (云顶之弈TFT/00m56s_AreYouNew.jpg)。框本身是既有的 TutorialChoice(节点名、按钮名不变, 驱动与门禁按名字找)。
##   · 起名 = 背包乱斗 00:19「My name is…」/ Marvel Snap 04:37「ENTER A NAME」: 压暗上一屏 + 预填一个名字 + 一颗确认
##       (背包乱斗BackpackBrawl/00m18.8s_打完商店才起名.jpg、MarvelSnap/04m37.5s_起名.jpg)。
##       写名字走设置页同一个函数 `SettingsScene.rename_apply`(规则 / 存档 / 云存档标脏同一条链, 不另写一份)。
##
## ★2026-10-21 再改(用户「开始的时候这些语气根本不是商业游戏吧而且也没介绍斗龟场是什么」「顺序不对吧，哪些东西是放在新手教程里面的」
##   「赛程…应该放在教程最后面吧」): 介绍只剩 **1 屏**(标题 + 一句「在这里，你将……」), 然后问教程。
##   两路 / 龟蛋 / 商店只在教程里用到时教; 每周赛程挪到教程结束后第一次进主菜单(MainMenuScene._first_week);
##   跳过教程的玩家第一场正式对战再补两路 / 龟蛋 / 终极战场三句(TutorialDirector._attach_first_battle_tips)。
## ★文案: 不口语化(memory fb-no-colloquial-copy); 「欢迎来到斗龟场」是用户点名要留的(10-07); 那一句是用户 10-21 定稿原句。
## ★背景: 本游戏真实画面截图(assets/sprites/intro/, tests/_shot_intro_pages.gd 拍的), 不借别的界面的素材。
## ★时间全按 `_process` 的 delta 自己数(不建 tween): 门禁可以一步一步喂, 也不受场景树 tween 在无头下推进不稳的影响。

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _BE := preload("res://scripts/net/backend.gd")

## 介绍页(只有 1 屏, 用户 10-21)。title = 「欢迎来到斗龟场」(用户 10-07 要留); text = 用户 10-21 定稿那句去掉开头与标题重复的半句。
## dim = 背景压暗系数(字多的界面截图压暗一些, 让那一句先被读到; Snap 01:07 规则条下面的对局整块虚化压暗)。
const PAGES := [
	{"img": "res://assets/sprites/intro/intro-1-team.jpg", "title": "欢迎来到斗龟场",
		"text": "在这里，你将组建一支由 3 只龟组成的队伍，为它们搭配装备、安排站位，与其他玩家的队伍自动对战。", "dim": 0.85},
]
## 那一屏停多久(秒)才自己去问。一句约 45 字, 按每秒 8 字读完再留 1 秒。
const PAGE_SEC := 7.0
## 那一句最宽多少(视口像素): 折成两行(字号 34 时每行约 25 字)。窄屏再收(左右各留 16 安全区 + 底板内边距)。
const CAPTION_MAX_W := 880.0
## 起名那一屏的背景: 固定用赛程那张(不用第 1 张: 那张顶上写着拍摄账号的名字, 正在起名时背后挂着别人的名字
##   会被看成自己的 —— 实拍自评, 10-21)。只当背景, 不配字。
const NAME_BG := "res://assets/sprites/intro/intro-5-week.jpg"
const NAME_BG_DIM := 0.7
const FADE_SEC := 0.35

const TXT_SKIP := "跳过"
## 「跳过」吃 44pt 触摸线(81 视口像素)。
const SKIP_SIZE := Vector2(150.0, 81.0)
const TXT_NAME_TITLE := "输入昵称"
const TXT_NAME_OK := "确认"
## 节点名(门禁 / 模拟号驱动按名字找, 不抄文案)。
const N_SKIP := "SkipIntro"
const N_CAPTION := "Caption"
const N_TITLE := "IntroTitle"
const N_NAME_BOX := "NamingBox"
const N_NAME_EDIT := "NameEdit"
const N_NAME_REROLL := "NameReroll"
const N_NAME_OK := "NameOk"
const N_NAME_STATUS := "NameStatus"

## 模式: intro(介绍 → 问) / name(起名, 导演在教程结束时把场景换过来)。
var mode := "intro"
var _page := -1
var _page_t := 0.0
var _asking := false
var _naming := false
var _bg_a: TextureRect = null      # 当前页
var _bg_b: TextureRect = null      # 上一页(淡出)
var _fade_t := 1.0
var _caption: Label = null
var _title: Label = null
var _plate: PanelContainer = null
var _skip: Button = null
var _ui: Control = null
var _shade: TextureRect = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("#0b0d14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_b = _mk_bg()
	_bg_a = _mk_bg()
	## 底边一条渐暗(那一句压在上面): 截图下沿是前景草丛 / 按钮行, 不压暗字读不清。
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.82))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 4; gt.height = 64
	_shade = TextureRect.new()
	_shade.texture = gt
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_build_caption()
	_build_skip()
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null and str(td.get("first_launch_mode")) == "name":
		td.set("first_launch_mode", "")
		mode = "name"
	if mode == "name":
		## 走完教程来起名: 背景 NAME_BG(见常量头注: 不用第 1 张)。
		_show_name_bg()
		_caption_visible(false)
		_skip.visible = false
		open_naming()
	else:
		_show_page(0, true)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _mk_bg() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


## 一句短句压在画面下三分之一(皇室战争对话框 / Snap 规则条都在主体画面之外的一块); 第一页另有标题。
func _build_caption() -> void:
	_title = Label.new()
	_title.name = N_TITLE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## 像素标题字 60 号(整屏主标题档, docs/plans/20261027-UI美术规矩.md §4.1); 行高 80 < 标题框高 90。
	##   描边 20 = 每边 5px = 一个源像素(outline_size 每边约画 1/4, 实拍量过)。
	_title.add_theme_font_size_override("font_size", 60)
	UISkin.title_label(_title, 60)
	_title.add_theme_color_override("font_color", Color("#ffd93d"))
	_title.add_theme_color_override("font_outline_color", Color("#1a0d02"))
	_title.add_theme_constant_override("outline_size", 20)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title)
	_plate = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	## 与教程引导条同一种条(TutorialGuide._build_ui): 深蓝底 + 金边 —— 首启与教程里的一句话是同一个样子。
	sb.bg_color = Color(0.071, 0.110, 0.204, 0.94)
	sb.set_border_width_all(3); sb.border_color = Color("#ffd93d")
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 36; sb.content_margin_right = 36
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	_plate.add_theme_stylebox_override("panel", sb)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_plate)
	_caption = Label.new()
	_caption.name = N_CAPTION
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## 一句约 45 字 ⇒ 限宽折行(两行); 宽度在 _place_plate 里按视口定。
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color("#fff4d6"))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_caption)
	## 折行标签放进容器、拿到真宽度之后最小高度才对 ⇒ 底板最小尺寸一变就重新摆一次(值不变时引擎不再发这个信号, 不会循环)。
	_plate.minimum_size_changed.connect(func() -> void: if is_inside_tree(): _place_plate.call_deferred())


func _build_skip() -> void:
	_skip = Button.new()
	_skip.name = N_SKIP
	_skip.text = TXT_SKIP
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 22)
	_skip.add_theme_color_override("font_color", Color("#e8f0f6"))
	## 尺寸先于 UISkin.button(它按控件尺寸挑皮; 先套皮再设尺寸会读到 0x0 挑错皮 —— nine_downgrade_audit G 类)。
	_skip.custom_minimum_size = SKIP_SIZE
	_skip.size = SKIP_SIZE
	UISkin.button(_skip, Color("#9fb6c9"))
	_skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_skip.pressed.connect(skip_intro)
	_ui.add_child(_skip)


func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var sm: Vector4 = SafeArea.margins(vp, 16.0)
	## 「跳过」右上, 吃 44pt 触摸线(81 视口像素)。
	_skip.size = SKIP_SIZE
	_skip.position = Vector2(vp.x - sm.z - _skip.size.x, sm.y)
	_shade.size = Vector2(vp.x, vp.y * 0.42)
	_shade.position = Vector2(0.0, vp.y * 0.58)
	_title.size = Vector2(vp.x, 90.0)
	_title.position = Vector2(0.0, vp.y * 0.64 - 45.0)
	_place_plate()


func _place_plate() -> void:
	var vp: Vector2 = get_viewport_rect().size
	## 那一句限宽: CAPTION_MAX_W, 窄屏收到「视口 − 两侧安全区 − 底板内边距(36×2) − 边框」。
	var cw := minf(CAPTION_MAX_W, vp.x - 32.0 - 72.0 - 6.0)
	## ★折行标签的最小高度引擎按它「此刻」的宽度算(放进容器之前是 0 宽 ⇒ 一字一行、高几千像素):
	##   这里按限宽自己量好折行后的高度, 直接给成最小尺寸。
	_caption.custom_minimum_size = Vector2(cw, wrapped_h(_caption, cw))
	_plate.reset_size()
	var ps: Vector2 = _plate.get_combined_minimum_size()
	_plate.size = ps
	## 下沿那一条(截图下沿是前景 / 次要按钮行); 离底边留安全区。
	var sm: Vector4 = SafeArea.margins(vp, 16.0)
	_plate.position = Vector2((vp.x - ps.x) / 2.0, minf(vp.y * 0.88 - ps.y / 2.0, vp.y - sm.w - ps.y - 8.0))


## 折行标签在宽 w 下的文字高度(按它自己的字体 / 字号量)。
static func wrapped_h(l: Label, w: float) -> float:
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	if f == null or l.text == "":
		return 0.0
	return ceilf(f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y)


func _caption_visible(on: bool) -> void:
	_plate.visible = on
	_title.visible = on and _title.text != ""


func _show_page(i: int, instant: bool = false) -> void:
	_page = i
	_page_t = 0.0
	var pg: Dictionary = PAGES[i]
	_bg_b.texture = _bg_a.texture
	_bg_b.self_modulate = _bg_a.self_modulate
	_bg_b.modulate.a = 1.0
	var p := str(pg["img"])
	_bg_a.texture = load(p) if ResourceLoader.exists(p) else null
	var dk := float(pg.get("dim", 1.0))
	_bg_a.self_modulate = Color(dk, dk, dk, 1.0)
	_fade_t = 1.0 if instant else 0.0
	_bg_a.modulate.a = 1.0 if instant else 0.0
	_title.text = str(pg["title"])
	_caption.text = str(pg["text"])
	_caption_visible(true)
	if is_inside_tree():
		_place_plate()


## 起名那一屏的背景(NAME_BG), 不带标题 / 那一句。
func _show_name_bg() -> void:
	_bg_b.texture = null
	_bg_a.texture = load(NAME_BG) if ResourceLoader.exists(NAME_BG) else null
	_bg_a.self_modulate = Color(NAME_BG_DIM, NAME_BG_DIM, NAME_BG_DIM, 1.0)
	_bg_a.modulate.a = 1.0
	_fade_t = 1.0
	_title.text = ""
	_caption.text = ""


func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + dt / FADE_SEC)
		_bg_a.modulate.a = _fade_t
		_ui.modulate.a = _fade_t if not _asking and not _naming else 1.0
	if mode != "intro" or _asking or _naming:
		return
	_page_t += dt
	if _page_t >= PAGE_SEC:
		advance()


## 点画面任意处 = 下一页(「跳过」钮自己吃点击)。
func _gui_input(ev: InputEvent) -> void:
	if mode != "intro" or _asking or _naming:
		return
	var tap := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if tap:
		accept_event()
		advance()


## 下一页; 最后一页之后 ⇒ 问要不要教程。
func advance() -> void:
	if _asking or _naming:
		return
	if _page + 1 < PAGES.size():
		_show_page(_page + 1)
	else:
		_ask()


## 右上「跳过」: 不看介绍, 直接问。
func skip_intro() -> void:
	if _asking or _naming:
		return
	if _page != PAGES.size() - 1:
		_show_page(PAGES.size() - 1, true)
	_ask()


func _ask() -> void:
	_asking = true
	_skip.visible = false
	_caption_visible(false)
	TutorialChoice.open(self, true)


# ═══════════════════════════════ 起名 ═══════════════════════════════

## 起名框(背包乱斗「My name is…」/ Snap「ENTER A NAME」): 压暗 + 标题 + 预填名字 + 换一个 + 确认。
## ★框放在上半屏: 手机横屏弹出键盘会盖住下半屏(Snap 04:37 那一帧框就在键盘上方)。
func open_naming() -> void:
	if _naming:
		return
	_naming = true
	_asking = false
	_show_name_bg()
	_skip.visible = false
	_caption_visible(false)
	var old := get_node_or_null(TutorialChoice.NODE_NAME)
	if old != null:
		old.queue_free()
	var dim := ColorRect.new()
	dim.name = N_NAME_BOX
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var box := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.set_border_width_all(0); bsb.set_corner_radius_all(0)
	var bframe := UISkin.nine("panel-frame.png", 20, bsb)
	bframe.content_margin_left = 40; bframe.content_margin_right = 40
	bframe.content_margin_top = 26; bframe.content_margin_bottom = 26
	box.add_theme_stylebox_override("panel", bframe)
	box.anchor_left = 0.5; box.anchor_right = 0.5; box.anchor_top = 0.0; box.anchor_bottom = 0.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = 70.0
	dim.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := Label.new()
	t.text = TXT_NAME_TITLE
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 36)
	UISkin.title_label(t, 36)          # 弹框里的整屏流程标题: 像素标题字 36 号
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(t)
	var rule := Label.new()
	rule.text = "%d~%d 个字 · 显示于排行榜" % [_P2C.NICK_MIN, _P2C.NICK_MAX]
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.add_theme_font_size_override("font_size", 16)
	rule.add_theme_color_override("font_color", Color("#9fb4c8"))
	vb.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var ed := LineEdit.new()
	ed.name = N_NAME_EDIT
	ed.text = str(_BE.player_display_name())
	ed.max_length = _P2C.NICK_MAX * 2   # 按规范化后判长度, 这里只防手滑贴一长串(同设置页改名)
	ed.custom_minimum_size = Vector2(300, 81)
	ed.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ed.add_theme_font_size_override("font_size", 24)
	row.add_child(ed)
	var rr := Button.new()
	rr.name = N_NAME_REROLL
	rr.text = _P2C.NICK_REROLL
	rr.custom_minimum_size = Vector2(130, 81)
	rr.add_theme_font_size_override("font_size", 20)
	rr.focus_mode = Control.FOCUS_NONE
	UISkin.card_button(rr)
	rr.pressed.connect(func() -> void: ed.text = _P2C.nickname_suggest(ed.text))
	row.add_child(rr)
	var st := Label.new()
	st.name = N_NAME_STATUS
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.custom_minimum_size = Vector2(0, 22)
	st.add_theme_font_size_override("font_size", 16)
	st.add_theme_color_override("font_color", Color("#ff9a9a"))
	vb.add_child(st)
	var ok := Button.new()
	ok.name = N_NAME_OK
	ok.text = TXT_NAME_OK
	ok.custom_minimum_size = Vector2(220, 81)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.add_theme_font_size_override("font_size", 24)
	ok.focus_mode = Control.FOCUS_NONE
	UISkin.card_button(ok)
	ok.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ok.pressed.connect(func() -> void: confirm_name(ed.text))
	vb.add_child(ok)


## 确认名字。返回要对玩家说的错误; 空串 = 已写进账号存档并去主菜单。
## ★规则 / 写法只有设置页一份(`rename_apply`: nickname_error → nickname_clean → GameState.save,
##   save 末尾给云存档标脏; 之后上传快照取名走 Backend.player_display_name)—— 与「设置 → 修改昵称」同一条链。
func confirm_name(raw: String) -> String:
	var err: String = load("res://scripts/scenes/SettingsScene.gd").rename_apply(raw)
	var st := find_child(N_NAME_STATUS, true, false) as Label
	if err != "":
		if st != null:
			st.text = err
		return err
	if is_inside_tree() and get_tree().current_scene == self:
		SceneNav.go(get_tree(), MAIN_MENU)
	return ""


## 门禁 / 驱动读。
func page_index() -> int:
	return _page


func is_asking() -> bool:
	return _asking


func is_naming() -> bool:
	return _naming
