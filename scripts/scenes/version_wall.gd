extends CanvasLayer
class_name VersionWall
## 强制最低版本 · 整屏挡墙(2026-10-19 · 方案书 docs/plans/20261019-服务器裁判.md §4)。
##
## 用户 10-19「需要强制最低版本」。下一轮内测连正式服、上架 App Store。
## ★判据不在这里: 挡不挡只读 `SupabaseNet.update_required()`(本机版本 < 服务端 `min_client_version`,
##   且这一进程真的问到了服务端)。离线 / 问不到 ⇒ 不挡。
## ★挂在 GameState 下(`install`), 跨场景常驻; layer 远高于各场景的 CanvasLayer ⇒ 盖住一切。
##   挡住时整屏吃掉点击与按键, 只留一颗「前往更新」(去商店)。
## ★开 App 时问一次服务状态; 从后台回前台(APPLICATION_RESUMED / 窗口重新拿到焦点)再问一次,
##   ⇒ 玩家挂在后台期间发了新版、抬了最低版本, 切回来就挡住。
## ★文案: 短指令/名词, 不口语化(memory fb-no-colloquial-copy)。
## ★按钮: 像素实心按钮(`UISkin.pixel_button`), 不用擂台金木框贴图皮。
## 门禁: tests/verify_min_version_wall.gd

const SB := preload("res://scripts/net/supabase.gd")

const NODE_NAME := "VersionWall"
const LAYER := 120
const TXT_TITLE := "需要更新"
const TXT_BODY := "当前版本已停止服务，请更新到最新版本后继续。"
const TXT_BUTTON := "前往更新"
const TXT_VER := "当前版本 %s　·　最低版本 %s"

## ★商店链接(待填): App Store 正式上架后换成 `https://apps.apple.com/app/id<数字>`;
##   上架前内测走 TestFlight 公开链接 `https://testflight.apple.com/join/<代码>`。
##   Android 包名取 export_presets.cfg 的 `package/unique_name`(com.turtlebattle.realtime)。
##   桌面 / 网页包没有商店 ⇒ 退回 iOS 那一条(桌面测试包本来就整层离线, 碰不到这面墙)。
## ★2026-10-20 留好两个链接位(方案书 docs/plans/20261020-AppStore上架.md §4.6):
##   · APP_STORE_APP_ID: App Store Connect → App 信息 → 「Apple ID」那串纯数字; 上架后填。
##   · TESTFLIGHT_JOIN_CODE: TestFlight 外部测试组开「公开链接」后 join/ 后面那段; 公测期填。
##   两个都空 ⇒ 退回 STORE_URL_IOS(TestFlight 首页)。拿到真值之前不许乱填。
const APP_STORE_APP_ID := ""
const TESTFLIGHT_JOIN_CODE := ""
const STORE_URL_IOS := "https://testflight.apple.com/"
const STORE_URL_ANDROID := "https://play.google.com/store/apps/details?id=com.turtlebattle.realtime"
## 从后台回前台(或重新拿到焦点)后再问服务状态的最小间隔: 焦点在桌面上会频繁进出。
const REFETCH_MIN_SEC := 5.0

var _root: Control = null
var _ver_label: Label = null
var _btn: Button = null
var _last_fetch_ms := -100000
## 观测量(门禁分母): 本节点发起过几次服务状态查询 / 点过几次前往更新。
var fetch_count := 0
var open_count := 0
## 门禁注入: 非空 ⇒ 点按钮时调它而不是 `OS.shell_open`(无头里别真开浏览器)。
var open_url_for_test: Callable = Callable()


static func install(host: Node) -> VersionWall:
	var old := host.get_node_or_null(NODE_NAME)
	if old != null:
		return old as VersionWall
	var w := VersionWall.new()
	w.name = NODE_NAME
	host.add_child(w)
	return w


## 纯函数: iOS 该去哪。优先级: App Store 正式页 > TestFlight 公开链接 > TestFlight 首页。
static func ios_store_url(app_id: String = APP_STORE_APP_ID, tf_code: String = TESTFLIGHT_JOIN_CODE) -> String:
	if app_id.strip_edges() != "":
		return "https://apps.apple.com/app/id%s" % app_id.strip_edges()
	if tf_code.strip_edges() != "":
		return "https://testflight.apple.com/join/%s" % tf_code.strip_edges()
	return STORE_URL_IOS


## 纯函数: 当前平台用哪条商店链接。
static func store_url_for(os_name: String) -> String:
	match os_name:
		"Android":
			return STORE_URL_ANDROID
	return ios_store_url()


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	refresh()
	call_deferred("_fetch")


func _build() -> void:
	_root = ColorRect.new()
	_root.name = "Blocker"
	(_root as ColorRect).color = Color("#0b1020")
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.name = "Box"
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 22)
	vb.custom_minimum_size = Vector2(560, 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(vb)
	var t := Label.new()
	t.name = "Title"
	t.text = TXT_TITLE
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 48)
	UISkin.title_label(t, 48)          # 像素标题字 48 号(小整屏大字档, docs/plans/20261027-UI美术规矩.md §4.1)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(t)
	var b := Label.new()
	b.name = "Body"
	b.text = TXT_BODY
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color("#e8eef6"))
	vb.add_child(b)
	_ver_label = Label.new()
	_ver_label.name = "Versions"
	_ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ver_label.add_theme_font_size_override("font_size", 18)
	_ver_label.add_theme_color_override("font_color", Color("#8a93a0"))
	vb.add_child(_ver_label)
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	_btn = Button.new()
	_btn.name = "GoUpdate"
	_btn.text = TXT_BUTTON
	_btn.custom_minimum_size = Vector2(260, 84)
	_btn.add_theme_font_size_override("font_size", 26)
	_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UISkin.pixel_button(_btn, UISkin.PX_GOLD)
	_btn.pressed.connect(_open_store)
	row.add_child(_btn)


## 挡没挡着(门禁与调用方读它)。
func is_blocking() -> bool:
	return _root != null and _root.visible


## 按当前判据同步显示。每帧调一次(只读几个静态量, 不建节点)。
func refresh() -> void:
	if _root == null:
		return
	var on := SB.update_required()
	if on and _ver_label != null:
		_ver_label.text = TXT_VER % [ReplayRecorder.client_version(), SB.min_client_version()]
	if on != _root.visible:
		_root.visible = on
		if on:
			print("[VersionWall] 客户端版本 %s 低于最低版本 %s, 挡住" % [ReplayRecorder.client_version(), SB.min_client_version()])


func _process(_dt: float) -> void:
	refresh()


## 挡着的时候按键一律吃掉(回车/空格/Esc 不许穿过去触发底下场景的快捷键)。
## 原始触摸 / 手势(镜头拖拽、双指缩放走 `_unhandled_input`)也吃掉。
## 鼠标不在这里吃: 由整屏 `MOUSE_FILTER_STOP` 挡, 而「前往更新」本身要收得到点击
##   (手机上的点按经「触摸模拟鼠标」变成另一条鼠标事件, 不受吃掉原始触摸影响)。
func _input(event: InputEvent) -> void:
	if not is_blocking():
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion \
			or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventGesture:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		## ★2026-10-23: 引擎下发这几条通知时是从根节点往下逐个传, 根节点此刻「忙」, 同步 add_child 必失败(正式服报错「Parent node is busy setting up children」)⇒ SupabaseNet._spawn 建的请求节点进不了树、请求当场判失败。一律延后到这一帧末尾再做。
		##   原来每次回前台都问不到 ⇒ 状态记成「连不上」⇒ 墙被撤掉、回前台发现新的最低版本从没生效过。
		call_deferred("_fetch")


## 去问一次服务状态(没配后端 = 什么都不做)。限频: 焦点进出很频繁。
func _fetch() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_fetch_ms < int(REFETCH_MIN_SEC * 1000.0):
		return
	_last_fetch_ms = now
	if not SB.enabled():
		return
	fetch_count += 1
	SB.fetch_status_async()


func _open_store() -> void:
	open_count += 1
	var url := store_url_for(OS.get_name())
	if open_url_for_test.is_valid():
		open_url_for_test.call(url)
		return
	OS.shell_open(url)
