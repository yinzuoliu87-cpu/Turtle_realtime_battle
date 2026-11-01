extends CanvasLayer
class_name OnlineWall
## 「无法连接服务器」框(2026-11-01 · 方案书 docs/plans/20261101b-游戏必须联网.md)。判据在 `OnlineGate`, 这里只管画与问。
##
## 用户 2026-11-01「这个游戏就一定要是要联网的…不能有什么这种本地」⇒ 连不上时不给本地替代, 只给这一框:
##   标题「无法连接服务器」+ 一句「X需要连接服务器。请检查网络后重试。」+「重试」「返回」(卡片钮 `UISkin.card_button`)。
## ★打开时先去问一次服务器(服务状态 + 令牌): 问得快(多数不到 0.4 秒)框根本不露面, 问到连得上 ⇒ 自己关掉、接着做原来那一步;
##   这期间整屏吃掉点击(防连点两次开出两局)。问不到 / 维护中 / 登录失效 ⇒ 露出框, 说清是哪一种。
## ★不自动重试、不倒计时: 玩家按「重试」才再问(连不上时自己一直刷请求只会把弱网压得更死)。
## ★存档不动: 这一框只拦「下一步」, 一行存档都不写; 「返回」只关框(调用方给了 on_back 就照它走)。
## ★挂成 CanvasLayer(layer 110): 战斗场 / 各页的 HUD 都在更低的层上; 版本挡墙(VersionWall, 120)仍盖在它上面。
## 门禁: tests/verify_online_only.gd

const SB := preload("res://scripts/net/supabase.gd")

const NODE_NAME := "OnlineWall"
const LAYER := 110
const TXT_TITLE := "无法连接服务器"
const TXT_BODY := "%s需要连接服务器。请检查网络连接后重试。"
const TXT_CONNECTING := "正在连接服务器…"
const TXT_MAINT_TITLE := "服务器维护中"
const TXT_MAINT_BODY := "服务器正在维护，请稍后再试。"
const TXT_SESSION_TITLE := "登录已失效"
const TXT_SESSION_BODY := "请在设置页用邮箱重新登录。"
const TXT_RETRY := "重试"
const TXT_BACK := "返回"
const BTN_SIZE := Vector2(168, 81)
## 问得快就不露面的那段时间(毫秒)。
const SHOW_DELAY_MS := 400
## 一次问多久算问不到(毫秒): 网络层单次请求 6 秒超时(`SupabaseNet.TIMEOUT_SEC`)+ 登录那一次的余量。
const PROBE_TIMEOUT_MS := 9000

## 状态: probe(正在问)/ fail(问不到)/ maintenance / session / update / done(已放行或已返回)
var state: String = ""
var what: String = ""
var resume: Callable = Callable()
var on_back: Callable = Callable()
## 观测量(门禁分母): 这一框问过几次。
var probe_count: int = 0

var _probe_on_ready := false
var _ask0 := 0
var _t0 := 0
var _dim: ColorRect = null
var _box: Control = null
var _title: Label = null
var _body: Label = null
var _retry: Button = null
var _back: Button = null


## 在 host 上开框(已有就复用那一个, 换成这一次的去处)。`probe` = 先去问一次; false = 直接显示「问不到」。
static func open(host: Node, what_: String, resume_: Callable, on_back_: Callable = Callable(), probe: bool = true) -> OnlineWall:
	if host == null or not is_instance_valid(host):
		var tree := Engine.get_main_loop() as SceneTree
		host = tree.root if tree != null else null
	if host == null:
		return null
	var w := host.get_node_or_null(NODE_NAME) as OnlineWall
	if w == null:
		w = OnlineWall.new()
		w.name = NODE_NAME
		w.what = what_
		w.resume = resume_
		w.on_back = on_back_
		w._probe_on_ready = probe
		host.add_child(w)
		return w
	w.what = what_
	w.resume = resume_
	w.on_back = on_back_
	if probe and w.state != "probe":
		w._probe()
	elif not probe:
		w._fail("fail")
	return w


## 门禁 / 调用方找框用。
static func find(host: Node) -> OnlineWall:
	return host.get_node_or_null(NODE_NAME) as OnlineWall if host != null else null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if _probe_on_ready:
		_probe()
	else:
		_fail("fail")


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP     # 问的那一会儿也吃掉点击(框还没露面)
	add_child(_dim)
	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5; box.anchor_top = 0.5; box.anchor_right = 0.5; box.anchor_bottom = 0.5
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH; box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.content_margin_left = 40; bsb.content_margin_right = 40; bsb.content_margin_top = 30; bsb.content_margin_bottom = 30
	var frame := UISkin.nine("panel-frame.png", 20, bsb)
	frame.content_margin_left = 40; frame.content_margin_right = 40
	frame.content_margin_top = 30; frame.content_margin_bottom = 30
	box.add_theme_stylebox_override("panel", frame)
	box.visible = false
	_dim.add_child(box)
	_box = box
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	vb.custom_minimum_size = Vector2(520, 0)
	box.add_child(vb)
	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", Color("#ffd93d"))
	UISkin.title_label(_title, 36)
	vb.add_child(_title)
	_body = Label.new()
	_body.name = "Body"
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 22)
	_body.add_theme_color_override("font_color", Color("#e8eef6"))
	vb.add_child(_body)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 18)
	vb.add_child(bh)
	_retry = _card_btn("Retry", TXT_RETRY)
	_retry.pressed.connect(_on_retry)
	bh.add_child(_retry)
	_back = _card_btn("Back", TXT_BACK)
	_back.pressed.connect(_on_back)
	bh.add_child(_back)


func _card_btn(nm: String, txt: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.custom_minimum_size = BTN_SIZE
	b.add_theme_font_size_override("font_size", 22)
	UISkin.card_button(b)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## 去问一次: 服务状态 + 登录(令牌没有 / 快过期时续)。回音在 `_process` 里判。
func _probe() -> void:
	state = "probe"
	probe_count += 1
	_ask0 = SB.ask_count()
	_t0 = Time.get_ticks_msec()
	if _title != null:
		_title.text = TXT_CONNECTING
		_body.text = ""
		_retry.visible = false
	SB.fetch_status_async()
	SB.ensure_signed_in_async()


func _process(_dt: float) -> void:
	if state != "probe":
		return
	var waited := Time.get_ticks_msec() - _t0
	if waited >= SHOW_DELAY_MS:
		_show()
	if not SB.enabled():
		_fail("fail")
		return
	if SB.ask_count() > _ask0:
		var v: String = OnlineGate.verdict()
		match v:
			"ok":
				_succeed()
				return
			"maintenance", "update", "session":
				_fail(v)
				return
			"token":
				## 服务状态问到了, 令牌还在路上(匿名登录 / 续期)⇒ 等它; 已经不在路上 ⇒ 登录没成 = 连不上
				if bool(SB._auth_inflight) and waited < PROBE_TIMEOUT_MS:
					return
				_fail("fail")
				return
			_:
				_fail("fail")
				return
	if waited >= PROBE_TIMEOUT_MS:
		_fail("fail")


func _show() -> void:
	if _dim != null:
		_dim.color = Color(0, 0, 0, 0.6)
	if _box != null:
		_box.visible = true


func _fail(kind: String) -> void:
	state = kind
	_show()
	match kind:
		"maintenance":
			_title.text = TXT_MAINT_TITLE
			var n: String = str(SB.notice_text()).strip_edges()
			_body.text = n if n != "" else TXT_MAINT_BODY
		"session":
			_title.text = TXT_SESSION_TITLE
			_body.text = TXT_SESSION_BODY
		"update":
			_title.text = VersionWall.TXT_TITLE
			_body.text = VersionWall.TXT_BODY
		_:
			_title.text = TXT_TITLE
			_body.text = TXT_BODY % what
	_retry.visible = true


func _succeed() -> void:
	OnlineGate.note_ok()
	var r := resume
	_close()
	if r.is_valid():
		r.call()


func _on_retry() -> void:
	_probe()


func _on_back() -> void:
	var b := on_back
	_close()
	if b.is_valid():
		b.call()


## 关框。★先改名再释放: 释放是延后的, 同一帧里调用方可能马上再开一框(按名字找到的会是这个将死的)。
func _close() -> void:
	state = "done"
	name = NODE_NAME + "Closed"
	queue_free()
