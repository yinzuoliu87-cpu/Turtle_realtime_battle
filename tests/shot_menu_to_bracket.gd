extends Node
## shot_menu_to_bracket.gd — 实拍: 主菜单 → 按那扇门 → 真的到了桶地图 (E-B3)
##
## ★为什么非要实拍不可: 「按下去场景真的换过去了」这一步**无头门禁量不到** ——
##   `change_scene_to_file` 会把门禁自己的 current_scene 当场拆掉
##   (memory `fb-gate-can-pin-the-bug-in-place`: 一个进程只能成功走一次 `_on_start()`)。
##   `verify_finals_feed ⑤` 里把这个缺口**显式登记成一条断言**(指向本文件), 不静默截断。
##
## ★这不是自证测试(要渲染, 会截图) ⇒ 文件名是 `shot_` 不是 `verify_`, 门禁不会自动发现它。
##   跑法(★不能 --headless, 无头截不出图; 窗口挪到屏外免得挡住用户):
##     NO_SAVE=1 <godot> --path . res://tests/shot_menu_to_bracket.tscn \
##       --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --quit-after 900
##
## ★★两个坑已经踩过, 写在这里免得下次再踩:
##   ① **要渲染 ⇒ 不是 headless ⇒ `test_mode` 不会自动置位 ⇒ 会写玩家真存档。**
##      靠的是「命令行给了非主场景路径」这道闸(见 `verify_save_guard`), 外加 NO_SAVE=1。
##   ② **实拍要等落位**(memory `fb-screenshot-must-settle-and-multi-ratio`):
##      140 帧拍出来过互相重叠的木牌, 420 帧才干净 ⇒ 这里每一步都等足帧数。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const OUT := "user://shot_menu_to_bracket"

var _step := 0
var _shots: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	print("=== 实拍: 主菜单 → 桶地图 ===")
	await _settle(60)
	## ★★**先把自己挪出「会被换掉」那个位置**。
	##   本脚本自己就是 `current_scene`, 而 `change_scene_to_file` 会把它当场释放 ⇒
	##   下一句 `get_tree()` 就是 null(实测: Invalid access ... on a null instance)。
	##   做法: 拿一个空节点顶上去当 current_scene, 让它去被释放。
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy
	## ★没走过新手教程的存档进主菜单会**被直接送去选龟界面**
	##   (`onboarded` 为假 ⇒ `_begin_tutorial` 强制走教学) ⇒ 根本看不到赛程条。
	##   隔离 APPDATA 跑的每一次都是新存档, 所以这一行每次都要。
	GameState.onboarded = true
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	await _settle(120)
	## ★把赛程条的时钟换成周日再建一次 —— 今天不是周日的话那一格根本不会出现。
	var menu = get_tree().current_scene
	menu.strip_now_override = _sunday_ts()
	## ★把「决赛日玩法上线了」打开 —— 否则门根本不存在(那是设计, 不是 bug)。
	##   `PHASE_MODE_LIVE` 是 const 字典改不动, 所以走 MainMenuScene 那一侧的口子。
	menu.strip_finals_live_override = 1
	menu.rebuild_week_strip()
	await _settle(180)
	_shot("1-menu")

	var btn := _find_door(get_tree().current_scene)
	if btn == null:
		print("  [FAIL] 主菜单上找不到那扇门(决赛日入口按钮)")
		_finish(1)
		return
	print("  找到门: 「%s」 @ %s" % [btn.text.replace("\n", " / "), str(btn.global_position)])
	btn.emit_signal("pressed")
	await _settle(240)
	_shot("2-bracket")

	var now_path := str(get_tree().current_scene.scene_file_path) \
		if get_tree().current_scene != null else "<none>"
	print("  现在的场景: %s" % now_path)
	var ok := now_path == "res://scenes/BracketMap.tscn"
	print("  [%s] ★★按下去真的换到了桶地图" % ("PASS" if ok else "FAIL"))
	print("  图: %s" % str(_shots))
	_finish(0 if ok else 1)


## 按钮怎么找: **按它连的方法名**找, 不按文案找 —— 文案会改, 接线不会。
func _find_door(n: Node) -> Button:
	if n == null:
		return null
	if n is Button:
		for c in (n as Button).pressed.get_connections():
			if str((c["callable"] as Callable).get_method()) == "_open_bracket_map":
				return n as Button
	for k in n.get_children():
		var r := _find_door(k)
		if r != null:
			return r
	return null


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [OUT, tag]
	img.save_png(p)
	_shots.append(ProjectSettings.globalize_path(p))


func _finish(code: int) -> void:
	get_tree().quit(code)


## 找一个**周日**的 UTC 时刻。★不写死日期 —— 写死的过一周就指到别的阶段。
func _sunday_ts() -> int:
	var t := int(Time.get_unix_time_from_system())
	for i in range(8):
		var ts: int = t + i * 86400
		if P2C.phase_at_utc(ts) == P2C.PHASE_FINALS:
			return ts
	return t
