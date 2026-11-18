extends CanvasLayer
## 网页播放器性能读数(2026-11-18 · 主站网页录像看着卡: 11-18 凌晨录屏数到开打后 21~23 帧/秒 —— 后来查明录屏工具自己只录得到约 35 帧/秒,
##   那个数不可信; 同条件下正式站与本机构建一样, 真正显眼的是偶发的长卡顿(一次 0.9 秒)⇒ 本读数专门抓长帧)。
## 网址带 `perf=1` 才挂(scripts/scenes/WebPlayerScene.gd), 挂在根节点下, 换进战斗场也还在; 平时不挂、零开销。
## 左上角每 0.5 秒刷一次:
##   ① 帧率 / 这半秒的帧时长(均值、最慢)—— 用真时钟(Time.get_ticks_usec)量相邻两帧, 不用 _process 的 delta
##      (引擎默认开 delta 平滑, 量出来的是平滑过的数);
##   ② 绘制调用 / 渲染对象 / 图元 / 节点数;
##   ③ 长帧(≥ HITCH_MS)总数与最慢的 HITCH_SHOW 次: 时长、其中脚本段 / 其余段、当时的场景、对局时钟 `_t`(战斗场才有)、开页后第几秒。
##      脚本段 = 本帧 process_frame 信号(所有 _process 之前)到本节点 _process(优先级最低, 最后跑)之间 —— 建特效 / load 解图都在这;
##      其余段 = 上一帧脚本段结束到本帧开始 —— 渲染(着色器首次编译、贴图上传)+ 物理 + 等垂直同步。
## 同一行另 print 到浏览器控制台(前缀 [perf]), 长帧单独一行(前缀 [hitch])。

const NAME := "WebPerfOverlay"
const PERIOD := 0.5
const HITCH_MS := 50.0
const HITCH_SHOW := 10

var _lbl: Label = null
var _last_us := 0
var _acc_us := 0
var _n := 0
var _max_ms := 0.0
var _hitches: Array = []      # [ms, 场景名, _t]
var _hitch_n := 0
var _t0_us := 0
var _begin_us := 0
var _end_us := 0


func _ready() -> void:
	name = NAME
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1 << 30
	get_tree().process_frame.connect(func() -> void: _begin_us = Time.get_ticks_usec())
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.position = Vector2(4, 4)
	bg.size = Vector2(470, 300)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_lbl = Label.new()
	_lbl.position = Vector2(12, 8)
	_lbl.add_theme_font_size_override("font_size", 16)
	_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl)
	_t0_us = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us == 0:
		_last_us = now
		return
	var us := now - _last_us
	_last_us = now
	var ms := us / 1000.0
	var script_ms := (now - _begin_us) / 1000.0
	var other_ms := (_begin_us - _end_us) / 1000.0 if _end_us > 0 else 0.0
	_end_us = now
	_acc_us += us
	_n += 1
	_max_ms = maxf(_max_ms, ms)
	if ms >= HITCH_MS:
		_hitch_n += 1
		var sc := get_tree().current_scene
		var t = sc.get("_t") if sc != null else null
		var row := [ms, script_ms, other_ms, str(sc.name) if sc != null else "-", float(t) if t != null else -1.0, (now - _t0_us) / 1000000.0]
		_hitches.append(row)
		_hitches.sort_custom(func(a, b): return a[0] > b[0])
		if _hitches.size() > HITCH_SHOW:
			_hitches.resize(HITCH_SHOW)
		print("[hitch] %.0f ms (脚本 %.0f · 其余 %.0f) · %s · 对局 t=%.2f · 开页后 %.1f 秒" % row)
	if _acc_us < int(PERIOD * 1000000.0):
		return
	var lines := PackedStringArray()
	lines.append("fps %d | frame avg %.1f max %.1f ms" % [Engine.get_frames_per_second(), _acc_us / 1000.0 / maxf(1.0, float(_n)), _max_ms])
	lines.append("draw %d | objects %d | prims %d | nodes %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	lines.append("hitches >= %d ms: %d" % [int(HITCH_MS), _hitch_n])
	for h in _hitches:
		lines.append("  %4.0f ms (s%.0f o%.0f) %s t=%.2f @%.1fs" % h)
	_lbl.text = "\n".join(lines)
	print("[perf] " + " | ".join(lines.slice(0, 3)))
	_acc_us = 0
	_n = 0
	_max_ms = 0.0
