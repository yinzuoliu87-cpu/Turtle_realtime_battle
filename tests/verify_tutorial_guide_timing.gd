extends Node

## verify_tutorial_guide_timing.gd — 提示等宿主「可以引导了」才出现(方案书 B6 那一类)
##
## 录屏 B6: 进图鉴那一步, 提示条第一帧就满不透明 + 暗幕, 页面还在淡入 ⇒ 约 0.6 秒画面是「一条提示 + 一片空」。
## 修好之后实拍又抓到一个同族的: 结算屏「前往商店」还在淡入, 洞已经挖在一块空地上。
## ⇒ 引导条三道闸, 本门禁逐条量(每条先证明闸关着时提示真的不在, 再证明闸开了它真的出来):
##   ① 宿主 ready_fn 为假 ⇒ 不显示(战斗: 三路总览 / 对阵卡演出期间)
##   ② 目标矩形还在动(入场滑入) ⇒ 不显示; 停下 STABLE_FRAMES 帧后才显示
##   ③ 目标还在淡入(一路往上透明度乘积 < 0.98)⇒ vis_rect 给空矩形 ⇒ 不显示

const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 9

var _ready_flag := false
var _rect := Rect2(200, 200, 160, 60)
var _fade_parent: Control = null
var _fade_btn: Button = null


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var steps := [{"text": "测试", "highlight": "t", "advanceOn": "x"}]

	# ① ready_fn
	var g1 = TutorialGuide.new()
	add_child(g1)
	g1.start(steps, Callable(), func(_n2: String) -> Rect2: return _rect, func() -> bool: return _ready_flag)
	var shown := 0
	for _i in range(30):
		await get_tree().process_frame
		if g1.is_showing():
			shown += 1
	_ok("★① 宿主说「还不行」的 30 帧里一帧都没显示", shown == 0, "显示了 %d 帧" % shown)
	_ready_flag = true
	var w := await _wait_show(g1)
	_ok("★① 宿主说「可以了」⇒ 显示出来(分母: 闸真的能开)", g1.is_showing(), "等了 %d 帧" % w)
	_ready_flag = false
	await get_tree().process_frame
	_ok("★① 宿主又说「不行」(换路回到演出)⇒ 立刻收起", not g1.is_showing())
	g1.queue_free()

	# ② 目标还在动
	var g2 = TutorialGuide.new()
	add_child(g2)
	g2.start(steps, Callable(), func(_n2: String) -> Rect2: return _rect)
	shown = 0
	for i in range(20):
		_rect.position.x = 200.0 + float(i) * 6.0      # 入场滑入: 每帧都在动
		await get_tree().process_frame
		if g2.is_showing():
			shown += 1
	_ok("★② 目标还在滑入的 20 帧里一帧都没显示", shown == 0, "显示了 %d 帧" % shown)
	w = await _wait_show(g2)
	_ok("★② 停下来之后显示出来", g2.is_showing(), "等了 %d 帧" % w)
	_ok("★② 而且至少等了 STABLE_FRAMES 帧(不是停下那一帧就出来)", w >= TutorialGuide.STABLE_FRAMES, "w=%d" % w)
	g2.queue_free()

	# ③ 目标还在淡入
	_fade_parent = Control.new()
	add_child(_fade_parent)
	_fade_btn = Button.new()
	_fade_btn.position = Vector2(300, 300); _fade_btn.size = Vector2(160, 60)
	_fade_parent.add_child(_fade_btn)
	_fade_parent.modulate.a = 0.3
	var g3 = TutorialGuide.new()
	add_child(g3)
	g3.start(steps, Callable(), func(_n2: String) -> Rect2: return TutorialGuide.vis_rect(_fade_btn))
	shown = 0
	for _i in range(20):
		await get_tree().process_frame
		if g3.is_showing():
			shown += 1
	_ok("★③ 目标的父节点还在淡入(α=0.3)的 20 帧里一帧都没显示", shown == 0, "显示了 %d 帧" % shown)
	_ok("★③ vis_rect 对半透明目标给空矩形", TutorialGuide.vis_rect(_fade_btn).size == Vector2.ZERO)
	_fade_parent.modulate.a = 1.0
	w = await _wait_show(g3)
	_ok("★③ 淡入完 ⇒ 显示出来", g3.is_showing(), "等了 %d 帧" % w)
	g3.queue_free()

	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 提示等内容到位才出现" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _wait_show(g) -> int:
	var w := 0
	while w < 60 and not g.is_showing():
		await get_tree().process_frame
		w += 1
	return w
