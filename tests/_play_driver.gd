extends Node
## 实玩驱动(调试工具, 不进门禁): 从 PLAY_DIR/cmd.txt 读指令, 往真游戏里注入鼠标事件并截图。
## 指令一行一条:  <序号> click x y | drag x1 y1 x2 y2 | shot 名字 | ui | wait 秒
## 结果写 PLAY_DIR/out.txt(追加)。坐标 = 1280x720 视口坐标。

var _dir := ""
var _done := 0
var _busy := false

func _ready() -> void:
	_dir = OS.get_environment("PLAY_DIR")
	if _dir == "":
		_dir = "C:/tmp/play"
	DirAccess.make_dir_recursive_absolute(_dir)
	var main: String = ProjectSettings.get_setting("application/run/main_scene")
	call_deferred("_hop", main)

func _hop(main: String) -> void:
	var r := get_tree().root
	get_parent().remove_child(self)
	r.add_child(self)
	GameState.test_mode = false   # 从 tests/ 启动会被存档闸置 true; 实玩要真存档(APPDATA 已隔离)
	get_tree().change_scene_to_file(main)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	t.timeout.connect(_poll)
	add_child(t)

func _log(s: String) -> void:
	var f := FileAccess.open(_dir + "/out.txt", FileAccess.READ_WRITE if FileAccess.file_exists(_dir + "/out.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(s)
	f.close()

func _poll() -> void:
	if _busy or not FileAccess.file_exists(_dir + "/cmd.txt"):
		return
	var lines := FileAccess.get_file_as_string(_dir + "/cmd.txt").split("\n")
	for ln in lines:
		var p := ln.strip_edges().split(" ", false)
		if p.size() < 2 or int(p[0]) <= _done:
			continue
		_busy = true
		await _run(p)
		_done = int(p[0])
		_busy = false
		return

func _btn(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	var w: Vector2 = get_viewport().get_final_transform() * pos
	e.position = w
	e.global_position = w
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)

func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	var w: Vector2 = get_viewport().get_final_transform() * pos
	e.position = w
	e.global_position = w
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _run(p: PackedStringArray) -> void:
	var id := p[0]
	match p[1]:
		"click":
			var v := Vector2(float(p[2]), float(p[3]))
			_motion(v, Vector2.ZERO)
			await _frames(2)
			_btn(v, true)
			await _frames(2)
			_btn(v, false)
			await _frames(20)
			_log("%s click %s -> scene %s" % [id, str(v), _scene()])
		"drag":
			var a := Vector2(float(p[2]), float(p[3]))
			var b := Vector2(float(p[4]), float(p[5]))
			_motion(a, Vector2.ZERO)
			await _frames(2)
			_btn(a, true)
			await _frames(3)
			for k in range(1, 13):
				var q := a.lerp(b, k / 12.0)
				_motion(q, (b - a) / 12.0)
				await _frames(2)
			_btn(b, false)
			await _frames(20)
			_log("%s drag %s->%s -> scene %s" % [id, str(a), str(b), _scene()])
		"clock":
			load("res://scripts/gamedata/phase2_config.gd").now_override_ts = int(p[2])
			_log("%s clock %s" % [id, p[2]])
		"setup":
			GameState.season_leaders = [p[2], p[3], p[4]]
			GameState.dual_lineup = {}
			GameState.get_dual_lineup()
			GameState.meta_deepsea_coins = int(p[5])
			GameState.season_total_battles = maxi(1, int(GameState.season_total_battles))
			if p.size() > 6:
				GameState.season_level = int(p[6])
			GameState.meta_shop_offer = []
			GameState.persistent_bench = []
			GameState.persistent_equipped = {}
			GameState.save()
			_log("%s setup leaders=%s coins=%s" % [id, str(GameState.season_leaders), p[5]])
		"insets":   # 模拟真机安全区(逻辑像素 左 上 右 下): 桌面进程拿不到刘海 / 底部横条, 只能喂
			SafeArea.override_insets = Vector4(float(p[2]), float(p[3]), float(p[4]), float(p[5]))
			_log("%s insets %s" % [id, str(SafeArea.override_insets)])
		"scene":
			get_tree().change_scene_to_file(p[2])
			await _frames(30)
			_log("%s scene -> %s" % [id, _scene()])
		"wait":
			await get_tree().create_timer(float(p[2])).timeout
			_log("%s wait -> scene %s" % [id, _scene()])
		"shot":
			await _frames(3)
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s.png" % [_dir, p[2]])
			_log("%s shot %s" % [id, p[2]])
		"ui":
			_log("%s ui scene=%s" % [id, _scene()])
			_dump(get_tree().root)
			_log("%s ui-end" % id)

func _scene() -> String:
	var c := get_tree().current_scene
	return c.scene_file_path if c else "?"

func _dump(n: Node) -> void:
	for c in n.get_children():
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is BaseButton:
			var r := (c as Control).get_global_rect()
			var t := ""
			if c is Button:
				t = (c as Button).text
			_log("  BTN [%s] %s @(%d,%d %dx%d)%s" % [t.replace("\n", "/"), c.name, r.position.x, r.position.y, r.size.x, r.size.y, " disabled" if (c as BaseButton).disabled else ""])
		_dump(c)
