extends Control
## 网页录像播放器页(2026-11-08 · 场景 scenes/WebPlayer.tscn = 导出预设 `WebPlayer` 的主场景)。
## 方案书 docs/plans/20261105c-主站对接偷袭.md §4.7 · 约定 docs/specs/主站对接约定.md §4.4 · 判据与地址见 web_player_core.gd 头注。
##
## 只播不算: 读网址里的 `match` → 取这一局的 end.json(版本 / 块数 / 名字)→ 拉第 0 块读出地图种子 →
##   `StreamWatch.enter_web` 进战斗场, 由现有状态流播放器(StreamPlayer)播, 画面与 App 里的回放同一套(特效完整)。
## ★不登录、不走联网闸、不写任何数据: 进程判据 WebPlayerMode(开机就停后端、开存档保护), 本页自己再停一次后端;
##   本页只发两种 GET(end.json / 过期记号)+ 状态流块(StreamSource.Http)。静态检查 tools/web_player_audit.py 守。
## 看完 / 点「退出」回到本页 ⇒「播放结束」+「重新播放」(不自动再放一遍)。

const WC := preload("res://scripts/systems/replay/web_player_core.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const TIMEOUT_SEC := 15.0
## 网络一直不通时, 等第 0 块等多久改说网络失败那一句(WebPlayerCore.TXT_OFFLINE)(块来源自己按退避一直重试)。
const FIRST_CHUNK_WAIT_SEC := 20.0
const BG := Color(0.0392, 0.0549, 0.0941)
const N_STATUS := "WebPlayerStatus"
const N_BUTTON := "WebPlayerButton"

## 页面状态: checking / loading / playing(已交给战斗场)/ ended / mobile / not_found / expired / version / offline / error
var state := ""
var match_id := ""
var origin := ""
var meta: Dictionary = {}
var map_seed := -1
var src = null
## 观测量(门禁): 本页发过的请求 [地址, 回的码](块请求在块来源里数)
var requests: Array = []
var _req: HTTPRequest = null
var _kind := ""
var _lbl: Label = null
var _btn: Button = null
var _wait := 0.0
var _pulse := 0.0


func _ready() -> void:
	WebPlayerMode.silence_backend()
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true             # 存档保护(网页上开机已开; 桌面直接跑本页时这里补上)
	_build_ui()
	_req = HTTPRequest.new()
	_req.timeout = TIMEOUT_SEC
	add_child(_req)
	_req.request_completed.connect(_on_done)
	var id := WC.norm_match_id(_read_match())
	if id != "" and id == WC.last_played:
		match_id = id
		origin = _read_origin()
		_show("ended", WC.TXT_ENDED, WC.BTN_REPLAY)
		return
	begin()


## 从头判一遍(进页 / 「重试」/「重新播放」)。
func begin() -> void:
	WC.last_played = ""
	src = null
	meta = {}
	map_seed = -1
	match_id = WC.norm_match_id(_read_match())
	origin = _read_origin()
	if WC.is_mobile(_read_ua(), _read_touch()):
		_show("mobile", WC.TXT_MOBILE)
		return
	if match_id == "":
		_show("not_found", WC.TXT_NOT_FOUND)
		return
	_show("checking", WC.TXT_LOADING)
	_fetch(WC.end_url(origin, match_id), "end")


func _fetch(url: String, kind: String) -> void:
	_kind = kind
	requests.append([url, 0])
	if _req.request(url, PackedStringArray([StreamSource.Http.HDR_VERSION + ": " + _ver()])) != OK:
		requests[-1][1] = -1
		_show("offline", WC.TXT_OFFLINE, WC.BTN_RETRY)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not requests.is_empty():
		requests[-1][1] = code if result == HTTPRequest.RESULT_SUCCESS else 0
	if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500:
		_show("offline", WC.TXT_OFFLINE, WC.BTN_RETRY)
		return
	match _kind:
		"end":
			if code == 200:
				var j := JSON.new()
				meta = j.data if j.parse(body.get_string_from_utf8()) == OK and j.data is Dictionary else {}
				match WC.check_end(meta, _ver()):
					"":
						_start_stream()
					"version":
						_wrong_version()
					_:
						_show("not_found", WC.TXT_NOT_FOUND)
			elif code == 404:
				_fetch(WC.expired_url(origin, match_id), "expired")
			elif code == 426:
				_wrong_version()
			else:
				_show("offline", WC.TXT_OFFLINE, WC.BTN_RETRY)
		"expired":
			if code == 200:
				_show("expired", WC.TXT_EXPIRED)
			elif code == 404:
				_show("not_found", WC.TXT_NOT_FOUND)
			else:
				_show("offline", WC.TXT_OFFLINE, WC.BTN_RETRY)


## 这一局不是这一版录的: 网页上回入口页重新选目录(入口页按 end.json 的版本跳); 回过一次还不对 / 不在网页上 ⇒ 说版本不一致。
func _wrong_version() -> void:
	if OS.has_feature("web") and WC.query_param(_js("window.location.search"), "hop") == "":
		_show("checking", WC.TXT_LOADING)
		JavaScriptBridge.eval("window.location.replace(%s)" % JSON.stringify(WC.entry_url(origin, match_id)), true)
		return
	_show("version", WC.TXT_VERSION)


func _start_stream() -> void:
	_show("loading", WC.TXT_LOADING)
	src = StreamSource.Http.new(WC.streams_base(origin), match_id, {"finished": true, "version": _ver()})
	_wait = 0.0


func _process(dt: float) -> void:
	if _lbl != null and state in ["checking", "loading"]:
		_pulse += dt
		_lbl.modulate.a = 0.65 + 0.35 * cos(_pulse * 3.0)
	if state != "loading" or src == null:
		return
	_wait += dt
	if src.fetched() >= 1:
		map_seed = WC.seed_of_chunk(src.chunk(0))
		if map_seed <= 0:
			_show("error", StreamPlayer.TXT_ERROR)
			return
		_enter()
	elif str(src.state) == StreamSource.Http.ST_GONE:
		_show("not_found", WC.TXT_NOT_FOUND)
	elif str(src.state) == StreamSource.Http.ST_UPDATE:
		_wrong_version()
	elif _wait > FIRST_CHUNK_WAIT_SEC and int(src.net_fail) > 0:
		src = null
		_show("offline", WC.TXT_OFFLINE, WC.BTN_RETRY)


func _enter() -> void:
	state = "playing"
	WC.last_played = match_id
	var w := SW.enter_web(get_tree(), match_id, src, map_seed, meta, WebPlayerMode.SCENE)
	if w != "":
		WC.last_played = ""
		_show("error", w)


func _on_button() -> void:
	if state in ["offline", "ended", "error"]:
		begin()


# ─────────────────────────────── 读浏览器 / 注入 ───────────────────────────────

func _ver() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _js(expr: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v = JavaScriptBridge.eval(expr, true)
	return "" if v == null else str(v)


func _read_match() -> String:
	if OS.has_feature("web"):
		return WC.query_param(_js("window.location.search"), "match")
	return OS.get_environment(WC.ENV_MATCH)


func _read_origin() -> String:
	var o := _js("window.location.origin") if OS.has_feature("web") else OS.get_environment(WC.ENV_ORIGIN).strip_edges()
	return o if o != "" else WC.DEFAULT_ORIGIN


func _read_ua() -> String:
	return _js("navigator.userAgent") if OS.has_feature("web") else OS.get_environment(WC.ENV_UA)


func _read_touch() -> int:
	var t := _js("String(navigator.maxTouchPoints || 0)") if OS.has_feature("web") else OS.get_environment(WC.ENV_TOUCH)
	return int(t) if t.is_valid_int() else 0


# ─────────────────────────────── 画面 ───────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 200)
	box.position = Vector2(-280, -100)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	add_child(box)
	_lbl = Label.new()
	_lbl.name = N_STATUS
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.add_theme_font_size_override("font_size", 30)
	_lbl.add_theme_color_override("font_color", Color("#fff1d6"))
	box.add_child(_lbl)
	_btn = Button.new()
	_btn.name = N_BUTTON
	_btn.custom_minimum_size = Vector2(220, 56)
	_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn.add_theme_font_size_override("font_size", 24)
	UISkin.card_button(_btn)
	_btn.visible = false
	_btn.pressed.connect(_on_button)
	box.add_child(_btn)


func _show(st: String, text: String, button: String = "") -> void:
	state = st
	if _lbl != null:
		_lbl.text = text
		_lbl.modulate.a = 1.0
	if _btn != null:
		_btn.text = button
		_btn.visible = button != ""
