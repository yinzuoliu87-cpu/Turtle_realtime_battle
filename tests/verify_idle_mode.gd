extends Node
## verify_idle_mode.gd — 摸鱼模式（竖持小窗）：留黑版式 + ★输入坐标映射
##
## 需求（用户 2026-07-28）：设置里一个按钮 → 整个游戏缩成手机中间一条 16:9 小横窗、
## 上下留黑、小窗内可正常点击、再点还原、开关持久化。
##
## ★方案书 docs/plans/20260729b-摸鱼模式小窗口.md §6.2 明写：
##   「验收清单第 4 条(小窗内可正常点击)不能靠目视，要写成门禁测试」——
##   这就是那条门禁。缩放后触摸点的屏幕坐标 ≠ 游戏内坐标，算错就是"点不中"。
##
## 查六件事：
##   ① letterbox 几何：竖屏视口里，内容区是【居中的 16:9 横带】，上下留黑、宽度铺满
##   ② 留黑面积对得上（不是把内容拉伸铺满 —— 那样画面会变形而不是留黑）
##   ③ ★屏幕坐标 → 画布坐标：小窗四角分别映射到画布的 (0,0) / (1280,720)
##   ④ ★小窗中心点映射到画布中心（最容易被"差一个 0.5 倍"糊弄过去的那个点）
##   ⑤ 黑边里的点映射出去在画布外（说明黑边确实不接受点击，不会误命中）
##   ⑥ 开关能开能关，且 is_on 读的是窗口实际状态
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_idle_mode.tscn

const BASE := Vector2(1280.0, 720.0)      # project.godot 的基准分辨率
## 典型竖持手机视口（iPhone 14 Pro 逻辑分辨率 393×852 的整数倍口径）
const PORTRAIT := Vector2(786.0, 1704.0)

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 摸鱼模式 ===")
	print("  基准 %.0f×%.0f  |  竖持视口 %.0f×%.0f (★分母)" % [BASE.x, BASE.y, PORTRAIT.x, PORTRAIT.y])

	# ── ① letterbox 几何 ──
	var r: Rect2 = IdleMode.content_rect(PORTRAIT, BASE)
	var want_scale: float = PORTRAIT.x / BASE.x            # 竖屏下宽度是瓶颈 → KEEP 取宽比
	var want_sz := BASE * want_scale
	var want_pos := (PORTRAIT - want_sz) * 0.5
	print("")
	print("  ① 内容区 = @(%.1f,%.1f) %.1f×%.1f" % [r.position.x, r.position.y, r.size.x, r.size.y])
	print("     期望   = @(%.1f,%.1f) %.1f×%.1f  (缩放 %.4f)" % [want_pos.x, want_pos.y, want_sz.x, want_sz.y, want_scale])
	_chk("① 内容区是居中的 16:9 横带", r.position.is_equal_approx(want_pos) and r.size.is_equal_approx(want_sz))
	_chk("① 宽度铺满、左右不留黑", absf(r.position.x) < 0.01 and absf(r.size.x - PORTRAIT.x) < 0.01)
	_chk("① 上下各留黑一条(高度小于视口)", r.size.y < PORTRAIT.y - 1.0 and r.position.y > 0.5)

	# ── ② 留黑面积 ──
	var black: float = PORTRAIT.x * PORTRAIT.y - r.size.x * r.size.y
	var black_pct: float = black / (PORTRAIT.x * PORTRAIT.y)
	print("")
	print("  ② 留黑占屏 %.1f%%  (内容 %.0f×%.0f 于 %.0f×%.0f)" % [black_pct * 100.0, r.size.x, r.size.y, PORTRAIT.x, PORTRAIT.y])
	print("     若是【拉伸铺满】则留黑 = 0%% —— 那是画面变形, 不是需求要的留黑")
	_chk("② 确实留黑(不是拉伸铺满)", black_pct > 0.3)

	# ── ③ ★四角坐标映射 ──
	print("")
	print("  ③ 屏幕坐标 → 画布坐标(四角):")
	var corners := [
		[r.position,                                   Vector2(0.0, 0.0)],
		[r.position + Vector2(r.size.x, 0.0),          Vector2(BASE.x, 0.0)],
		[r.position + Vector2(0.0, r.size.y),          Vector2(0.0, BASE.y)],
		[r.position + r.size,                          BASE],
	]
	var ok3 := true
	for c in corners:
		var got: Vector2 = IdleMode.screen_to_canvas(c[0], PORTRAIT, BASE)
		var good: bool = got.is_equal_approx(c[1])
		if not good:
			ok3 = false
		print("     屏(%7.1f,%7.1f) → 画布(%7.1f,%7.1f)   期望(%7.1f,%7.1f)  %s" % [
			c[0].x, c[0].y, got.x, got.y, c[1].x, c[1].y, "ok" if good else "★差"])
	_chk("③ ★小窗四角精确映射到画布四角", ok3)

	# ── ④ ★中心点 ──
	var mid_screen: Vector2 = r.position + r.size * 0.5
	var mid_canvas: Vector2 = IdleMode.screen_to_canvas(mid_screen, PORTRAIT, BASE)
	print("")
	print("  ④ 小窗中心 屏(%.1f,%.1f) → 画布(%.1f,%.1f)  期望(%.1f,%.1f)" % [
		mid_screen.x, mid_screen.y, mid_canvas.x, mid_canvas.y, BASE.x * 0.5, BASE.y * 0.5])
	_chk("④ ★中心点映射到画布中心(差 0.5 倍的错在这里现形)", mid_canvas.is_equal_approx(BASE * 0.5))

	# ── ⑤ 黑边里的点 ──
	var top_black := Vector2(PORTRAIT.x * 0.5, r.position.y * 0.5)
	var tb: Vector2 = IdleMode.screen_to_canvas(top_black, PORTRAIT, BASE)
	print("")
	print("  ⑤ 上方黑边内一点 屏(%.1f,%.1f) → 画布(%.1f,%.1f)" % [top_black.x, top_black.y, tb.x, tb.y])
	print("     应落在画布【外】(y<0) —— 否则黑边会误命中界面元素")
	_chk("⑤ 黑边映射到画布外(不会误命中)", tb.y < 0.0)

	# ── ⑦ ★工程必须【允许竖屏】, 否则 iOS 直接拒绝切换 ──
	#    这条是拆开 CI 出的真 IPA 读 Info.plist 才发现的:
	#      UISupportedInterfaceOrientations = ['UIInterfaceOrientationLandscapeLeft']
	#    只有横屏 → DisplayServer.screen_set_orientation(PORTRAIT) 被系统拒绝 →
	#    摸鱼模式在真机上【是死的】。而桌面端用"改窗口尺寸"模拟, 本地永远看不出来。
	#    Godot 从 display/window/handheld/orientation 生成那份列表, 所以焊在这里。
	var orient := str(ProjectSettings.get_setting("display/window/handheld/orientation", ""))
	print("")
	print("  ⑦ display/window/handheld/orientation = \"%s\"" % orient)
	print("     必须是 \"sensor\"(允许全部方向) —— \"sensor_landscape\" 会让 iOS 只写横屏进 Info.plist")
	_chk("⑦ ★工程允许竖屏(否则 iOS 拒绝切换, 功能在真机上是死的)", orient == "sensor")

	# ── ⑥ 开关 ──
	var win := get_window()
	var was: bool = IdleMode.is_on(win)
	IdleMode.apply(win, true)
	var on1: bool = IdleMode.is_on(win)
	IdleMode.apply(win, false)
	var off1: bool = IdleMode.is_on(win)
	IdleMode.apply(win, was)
	print("")
	print("  ⑥ 开 → is_on=%s   关 → is_on=%s" % [str(on1), str(off1)])
	_chk("⑥ 开关能开能关(状态读窗口实际值)", on1 and not off1)

	print("")
	print("ALL PASS — 摸鱼模式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])
