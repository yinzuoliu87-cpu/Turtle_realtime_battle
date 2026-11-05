## 切页过场(2026-11-05)—— 暗幕淡入 + 新页面后台线程加载 + 换场景 + 暗幕淡出。SceneNav.go 调。
##
## 由来: 用户 11-05「商店这个卡顿，它只是个…典型的这个错误，整个游戏里面会不会有很多这种问题呢？」
##   开窗口实走各页(tests/probes/_walk_pages.gd): 进选龟页最长一帧 343 毫秒、排行榜 146 毫秒、图鉴 72 毫秒;
##   拆段(tests/probes/_probe_scene_open_split.gd): 选龟页 加载 164 + 搭界面 671 毫秒 —— 换场景时主线程冻住, 画面停在旧页上。
## 做法(商业游戏通行的切页过场):
##   ① 点下去暗幕 0.10 秒淡入(挡住点击, 防连点切两次), 同时 ResourceLoader 后台线程加载新页面;
##   ② 暗幕盖满且加载完 ⇒ change_scene_to_packed —— 新页面 _ready 搭界面那几百毫秒在暗幕下面, 看不到冻住的画面;
##   ③ 新页面挂上并画过两帧后暗幕 0.15 秒淡出。
## 暗幕颜色 = 各页背景的深海底色(#06141c, 与 PersistentBg / 商店底一致), 不是纯黑。
## 无头(门禁 / 陪练号 / 裁判)不走这里(见 SceneNav.go), 由 tests/verify_scene_transition.gd 强制打开来量。
class_name SceneFader
extends CanvasLayer

const FADE_OUT_SEC := 0.10
const FADE_IN_SEC := 0.15
const COLOR := Color("#06141c")
## 后台加载最多等多久(秒): 超时就退回同步 load(加载器出问题时不让玩家卡在暗幕里)
const LOAD_TIMEOUT_SEC := 10.0
## 暗幕下等加载超过这么久才亮「加载中」(短的切页看不到它; 门禁实测冷启动进图鉴等加载 2 秒, 一屏暗着没反馈不行)
const HINT_AFTER_SEC := 0.35

var _rect: ColorRect = null
var _hint: Label = null
var busy := false
## 上一次过场各段的耗时(毫秒), 门禁读
var last: Dictionary = {}


static func instance(tree: SceneTree) -> SceneFader:
	var f := tree.root.get_node_or_null("SceneFader") as SceneFader
	if f == null:
		f = SceneFader.new()
		f.name = "SceneFader"
		tree.root.add_child(f)
	return f


func _init() -> void:
	layer = 128   # 盖在所有页面与弹层之上
	_rect = ColorRect.new()
	_rect.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.0)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_hint = Label.new()
	_hint.text = "加载中"
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_color", Color("#9fb6c9"))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position.y -= 90.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	add_child(_hint)
	visible = false


## 走一次过场。正在过场时再来的请求丢掉(连点的第二下)。
func go(path: String) -> void:
	if busy:
		return
	busy = true
	var t0 := Time.get_ticks_msec()
	var tree := get_tree()
	visible = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var req_ok: bool = ResourceLoader.load_threaded_request(path) == OK
	await _fade_to(1.0, FADE_OUT_SEC)
	var t1 := Time.get_ticks_msec()
	var ps: PackedScene = null
	if req_ok:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
				and Time.get_ticks_msec() - t1 < int(LOAD_TIMEOUT_SEC * 1000.0):
			if not _hint.visible and Time.get_ticks_msec() - t1 >= int(HINT_AFTER_SEC * 1000.0):
				_hint.visible = true
			await tree.process_frame
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ps = ResourceLoader.load_threaded_get(path) as PackedScene
	if ps == null:
		ps = load(path) as PackedScene   # 后台加载失败 / 超时: 退回同步加载
	var t2 := Time.get_ticks_msec()
	if ps != null:
		tree.change_scene_to_packed(ps)
	## 新页面挂上(换场是延后到这一帧末尾的)并画过两帧
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	var t3 := Time.get_ticks_msec()
	_hint.visible = false
	await _fade_to(0.0, FADE_IN_SEC)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	last = {"path": path, "fade_out_ms": t1 - t0, "wait_load_ms": t2 - t1, "build_ms": t3 - t2, "total_ms": Time.get_ticks_msec() - t0, "ok": ps != null}
	busy = false


func _fade_to(a: float, sec: float) -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", a, sec)
	await tw.finished
