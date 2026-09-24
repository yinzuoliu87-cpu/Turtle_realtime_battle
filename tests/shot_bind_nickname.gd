extends Node
## shot_bind_nickname.gd — 实拍: 绑定邮箱那一屏加了昵称之后还装得下吗
##
## ★为什么要实拍: 对话框原来 520×340、六个控件按**绝对坐标**摆;
##   加一行要长到 400 且下面四个各下移 52 —— 算错一个数就会有控件掉到框外面,
##   而 `verify_nickname` 量的是**规则与数据**，量不到这个
##   (memory `fb-screenshot-must-settle-and-multi-ratio`: 门禁算矩形不能代替实拍)。
## ★两屏都要拍: **绑定**(有昵称行) 与 **取回**(没有) —— 只拍一屏等于没验那个 if。
##
## 跑法(★不能 --headless):
##   NO_SAVE=1 <godot> --path . res://tests/shot_bind_nickname.tscn \
##     --position 5000,5000 --resolution 1280x720 --audio-driver Dummy --quit-after 900

const SB := preload("res://scripts/net/supabase.gd")
const OUT := "user://shot_bind_nickname"

var _shots: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	await _settle(60)
	var decoy := Node.new()
	get_tree().root.add_child(decoy)
	get_tree().current_scene = decoy          # ★把自己挪出"会被换掉"的位置
	GameState.onboarded = true
	GameState.account_id = "uid-shot-0001"
	GameState.nickname = ""
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")
	await _settle(240)
	var st = get_tree().current_scene
	print("=== 实拍: 绑定邮箱 + 昵称 ===")

	## ① 绑定流程: 该有昵称那一行
	st._open_email_dialog(SB.FLOW_BIND)
	await _settle(150)
	_shot("1-bind")
	print("  绑定屏: 昵称输入框 %s" % ("在" if st._nick_edit != null else "★不在"))
	if st._nick_edit != null:
		print("     昵称框 %s  对话框内" % str(st._nick_edit.get_global_rect()))

	## ② 取回流程: **不该**有昵称那一行
	if st._email_layer != null:
		st._email_layer.queue_free()
		st._email_layer = null
	st._nick_edit = null
	await _settle(30)
	st._open_email_dialog(SB.FLOW_RECOVER)
	await _settle(150)
	_shot("2-recover")
	print("  取回屏: 昵称输入框 %s(应为不在 —— 那个号已经有昵称了)"
		% ("★在" if st._nick_edit != null else "不在"))
	print("  图: %s" % str(_shots))
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(tag: String) -> void:
	var p := "%s/%s.png" % [OUT, tag]
	get_viewport().get_texture().get_image().save_png(p)
	_shots.append(ProjectSettings.globalize_path(p))
