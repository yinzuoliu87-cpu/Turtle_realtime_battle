extends Node
## verify_studio_intro.gd —— 工作室开场「灯鱼」(2026-10-29, docs/plans/20261029-工作室开场动画.md)
##
## ① 无头不播(门禁 / 裁判 / 陪练号不白等 2.5 秒); 同一进程只播一次
## ② 盖在最上层(layer 9000), 底色 = boot_splash/bg_color(= iPhone 启动屏同色, 启动屏 → 开场不闪)
## ③ 时间轴: 0 秒就看得到小鱼(参考: 0.3 秒内看清) / 火星 / 点灯那一下(瞪眼 + 光芒 + 光环) / 字母逐个落下 / 副标 / 眨眼 / 淡出 / 2.5 秒结束
## ④ 跳过: 0.3 秒前点不算; 之后点 ⇒ 直接进淡出
## ⑤ 播放期间压住背景音乐, 播完放开(不许留静音; 半路被拆也放开)
## ⑥ 摆位: 整组水平居中, 字标宽在屏宽 18%~32%(规格 25~30%, 参考 Supercell 21%), 全在屏内
## ⑦ 时间轴 / 字宽与素材脚本 tools/build_studio_intro.py 逐项相同; 素材零半透明; 音效长度 = 时间轴总长
## ⑧ 主菜单真的接上了: 冷启动第一个主菜单盖一层, 第二个主菜单不再盖

const SI := preload("res://scripts/scenes/studio_intro.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _intro() -> StudioIntro:
	return get_tree().root.get_node_or_null(StudioIntro.NODE) as StudioIntro


## 不走 _process, 由门禁一步步推(每步 0.01 秒)。
func _goto(it: StudioIntro, target: float) -> void:
	it.set_process(false)
	while it.t < target - 1e-6 and is_instance_valid(it) and not it.is_queued_for_deletion():
		it.advance(minf(0.01, target - it.t))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 工作室开场 ===")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await _t_should_play()
	await _t_timeline()
	await _t_skip()
	_t_parity()
	await _t_mainmenu()
	StudioIntro.force_override = -1
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)


## ①
func _t_should_play() -> void:
	StudioIntro.force_override = -1
	StudioIntro.played = false
	_ok("① 无头 ⇒ 不播", not StudioIntro.should_play() and StudioIntro.play_once(get_tree()) == null)
	_ok("① 不播时不压背景音乐", Audio.bgm_hold == false)
	StudioIntro.force_override = 1
	StudioIntro.played = false
	var it := StudioIntro.play_once(get_tree())
	_ok("① 要播 ⇒ 盖一层", it != null)
	_ok("① 同一进程第二次不再播", StudioIntro.play_once(get_tree()) == null)
	await _frames(2)
	var on_root := _intro()
	_ok("② 挂在 root 上(换场景不跟着拆)", on_root != null and on_root == it)
	_ok("② 最上层 layer ≥ 9000", it != null and it.layer >= 9000, str(it.layer if it != null else -1))
	var bg := it.get_node_or_null("Root/Bg") as ColorRect if it != null else null
	var want: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	_ok("② ★底色 = 启动屏底色", bg != null and absf(bg.color.r - want.r) < 0.004 and absf(bg.color.g - want.g) < 0.004 and absf(bg.color.b - want.b) < 0.004,
		str(bg.color if bg != null else null))
	_ok("⑤ 播放期间压住背景音乐", Audio.bgm_hold == true)
	## 压着时 play_bgm 不淡入
	Audio.play_bgm("menu", 0.2, 0.4)
	await _frames(20)
	var p = Audio.get("_bgm_player")
	_ok("⑤ ★压着时 play_bgm 停在静音", p == null or float(p.volume_db) <= -79.0, str(p.volume_db if p != null else null))
	if it != null:
		it.queue_free()
	await _frames(2)
	_ok("⑤ ★半路被拆也放开背景音乐", Audio.bgm_hold == false)


## ③ ⑥
func _t_timeline() -> void:
	StudioIntro.force_override = 1
	StudioIntro.played = false
	var it := StudioIntro.play_once(get_tree())
	await _frames(2)
	if it == null or not is_instance_valid(it):
		_ok("③ 开场建出来了", false)
		return
	it.set_process(false)
	var fish := it.get_node("Root/Fish") as TextureRect
	var vs := get_viewport().get_visible_rect().size
	## 0 秒
	_ok("③ ★0 秒就看得到小鱼(睡着、灯灭)", fish.visible and fish.texture != null and str(fish.get_meta("state")) == "off")
	_ok("③ 0 秒还没有字", not (it.get_node("Root/Letter0") as Control).visible)
	## 摆位
	var fr := fish.get_global_rect()
	_ok("⑥ 小鱼水平居中", absf(fr.get_center().x - vs.x / 2.0) <= StudioIntro.S, "%.1f vs %.1f" % [fr.get_center().x, vs.x / 2.0])
	var l0 := (it.get_node("Root/Letter0") as Control)
	var l7 := (it.get_node("Root/Letter7") as Control)
	var ww := l7.position.x + l7.size.x - l0.position.x
	_ok("⑥ 字标宽在屏宽 18%~32%", ww / vs.x >= 0.18 and ww / vs.x <= 0.32, "%.1f%%" % (ww / vs.x * 100.0))
	_ok("⑥ 字标水平居中", absf((l0.position.x + ww / 2.0) - vs.x / 2.0) <= StudioIntro.S)
	var zh := it.get_node("Root/Zh") as Control
	_ok("⑥ 整组在屏内", fr.position.y >= 0.0 and zh.position.y + zh.size.y <= vs.y, "%.0f..%.0f" % [fr.position.y, zh.position.y + zh.size.y])
	## 火星 / 点灯
	_goto(it, 0.06)
	_ok("③ 第一下火星: 灯闪亮", str(fish.get_meta("state")) == "on")
	_goto(it, 0.10)
	_ok("③ 火星之间灯又灭", str(fish.get_meta("state")) == "off")
	_goto(it, 0.25)
	_ok("③ ★点灯那一下: 瞪眼 + 光芒 + 光环", str(fish.get_meta("state")) == "flash" and (it.get("_rays") as Control).visible
		and ((it.get("_rings") as Array).filter(func(r): return (r as Control).visible).size() == 1))
	_goto(it, 0.30)
	_ok("③ 点灯后惊醒一跳(整格往上)", fish.position.y < it.get("_fish_pos").y and int(it.get("_fish_pos").y - fish.position.y) % StudioIntro.S == 0,
		"%.0f" % (it.get("_fish_pos").y - fish.position.y))
	_goto(it, 0.40)
	_ok("③ 之后灯亮着(短光线在)", str(fish.get_meta("state")) == "on" and ((it.get("_ticks") as Array).filter(func(r): return (r as Control).visible).size() == 1))
	## 字母逐个
	var vis := func() -> int:
		var c := 0
		for i in range(8):
			if (it.get_node("Root/Letter%d" % i) as Control).visible:
				c += 1
		return c
	_goto(it, 0.53)
	var c1: int = vis.call()
	_goto(it, 0.62)
	var c2: int = vis.call()
	_goto(it, 0.90)
	var c3: int = vis.call()
	_ok("③ ★字母逐个落下(1 → 3 → 8)", c1 == 1 and c2 == 3 and c3 == 8, "%d / %d / %d" % [c1, c2, c3])
	_ok("③ 副标还没出", not zh.visible)
	_goto(it, 1.00)
	_ok("③ 副标「灯鱼游戏」出现", zh.visible)
	_goto(it, 1.47)
	_ok("③ 眨眼", str(fish.get_meta("state")) == "blink")
	_goto(it, 2.0)
	var root := it.get_node("Root") as Control
	_ok("③ 停留段不透明", absf(root.modulate.a - 1.0) < 0.001)
	_goto(it, 2.35)
	_ok("③ 2.2 秒起淡出", root.modulate.a > 0.3 and root.modulate.a < 0.7, "%.2f" % root.modulate.a)
	var got := [false]
	it.finished.connect(func() -> void: got[0] = true)
	_goto(it, 2.5)
	await _frames(1)
	_ok("③ ★2.5 秒结束: 发 finished 并拆掉", got[0] and not is_instance_valid(it))
	_ok("⑤ ★播完放开背景音乐", Audio.bgm_hold == false)


## ④
func _t_skip() -> void:
	StudioIntro.force_override = 1
	StudioIntro.played = false
	var it := StudioIntro.play_once(get_tree())
	await _frames(2)
	if it == null:
		_ok("④ 开场建出来了", false)
		return
	it.set_process(false)
	_goto(it, 0.10)
	it.skip()
	_ok("④ 0.3 秒前点不算", absf(it.t - 0.10) < 0.001, "%.2f" % it.t)
	_goto(it, 0.50)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	(it.get_node("Root") as Control).gui_input.emit(ev)
	_ok("④ ★之后点任意处 ⇒ 直接进淡出", absf(it.t - float(StudioIntro.TIMING["fade"])) < 0.001, "%.2f" % it.t)
	_goto(it, float(StudioIntro.TIMING["end"]))
	await _frames(1)
	_ok("④ 跳过后 0.3 秒内结束", not is_instance_valid(it))


## ⑦
func _t_parity() -> void:
	var src := FileAccess.get_file_as_string("res://tools/build_studio_intro.py")
	_ok("⑦ 读得到素材脚本", src.length() > 1000)
	var re := RegEx.new()
	var bad: Array = []
	for k in StudioIntro.TIMING.keys():
		re.compile("\"%s\":\\s*([0-9.]+)" % k)
		var m := re.search(src)
		if m == null or absf(float(m.get_string(1)) - float(StudioIntro.TIMING[k])) > 1e-9:
			bad.append(k)
	_ok("⑦ ★时间轴与素材脚本逐项相同(%d 项)" % StudioIntro.TIMING.size(), bad.is_empty(), str(bad))
	## 字宽: 从脚本的 LETTERS 表数每个字母第一行的宽
	var ws: Array = []
	for ch in ["L", "A", "M", "P", "F", "I", "S", "H"]:
		re.compile("\"%s\":\\s*(?:\\[\"([.#]+)\"|\\[\"([.#]+)\"\\]\\s*\\*)" % ch)
		var m := re.search(src)
		ws.append(-1 if m == null else maxi(m.get_string(1).length(), m.get_string(2).length()))
	_ok("⑦ 字宽与素材脚本相同", ws == StudioIntro.LETTER_W, str(ws))
	## 素材在、零半透明
	var names: Array = ["fish_on", "fish_off", "fish_blink", "fish_flash", "rays", "zh", "ticks_0", "ticks_1"]
	for i in range(4):
		names.append("ring_%d" % i)
	for i in range(8):
		names.append("letter_%d" % i)
	var semi := 0
	var missing: Array = []
	for n in names:
		var tex := load(StudioIntro.DIR + n + ".png") as Texture2D if ResourceLoader.exists(StudioIntro.DIR + n + ".png") else null
		if tex == null:
			missing.append(n)
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var a := img.get_pixel(x, y).a
				if a > 0.004 and a < 0.996:
					semi += 1
	_ok("⑦ 素材 %d 张都在" % names.size(), missing.is_empty(), str(missing))
	_ok("⑦ ★零半透明", semi == 0, "%d 个半透明像素" % semi)
	var wav := load(StudioIntro.SFX) as AudioStream if ResourceLoader.exists(StudioIntro.SFX) else null
	_ok("⑦ 音效长度 = 时间轴总长", wav != null and absf(wav.get_length() - float(StudioIntro.TIMING["end"])) < 0.02,
		"%.3f" % (wav.get_length() if wav != null else -1.0))


## ⑧
func _t_mainmenu() -> void:
	StudioIntro.force_override = 1
	StudioIntro.played = false
	var m1: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(m1)
	await _frames(3)
	var it := _intro()
	_ok("⑧ ★冷启动第一个主菜单盖上开场", it != null)
	var m2: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(m2)
	await _frames(3)
	var count := 0
	for c in get_tree().root.get_children():
		if c is StudioIntro:
			count += 1
	_ok("⑧ 再进主菜单不重放", count == 1, str(count))
	if it != null and is_instance_valid(it):
		it.queue_free()
	m1.queue_free()
	m2.queue_free()
	await _frames(3)
