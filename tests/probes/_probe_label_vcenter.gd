extends Node
## 探针(11-27): 「文字框比一行字还矮 ⇒ 引擎没法垂直居中, 字从框顶往下画、整体偏下」全场排查。
## 由来: 用户 11-27 看本周羁绊揭晓「炸弹两个字…很明显低了吧」(量出框 28 高 < 22 号字一行 33 高, 低 4 像素),
##   接着「这个文字位置问题似乎在周日的那个显示界面那里也有」⇒ 同一类一次量全。
## 跑法: SCENE_LIST=逗号分隔 FAKE_TS=<unix> <godot> --path . --resolution 1280x720 res://tests/probes/_probe_label_vcenter.tscn
## 判据: 可见的 Label, 垂直对齐 = 居中 / 底, 有字, 框高 + 1 < 这个字号的行高(font.get_height) ⇒ 报。容器里的 Label 由容器撑高, 不会命中。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DEF := "MainMenu,BracketMap,GauntletBoard,Leaderboard,Shop,Inventory,Codex,Record,Friends,Settings,TeamSelect,TrainerConfig,Matchmaking"
var _hits := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.tutorial_active = false
	gs.onboarded = true
	gs.battles_total = 30
	StudioIntro.played = true
	if OS.has_environment("FAKE_TS"):
		_P2C.now_override_ts = int(OS.get_environment("FAKE_TS"))
	var names: PackedStringArray = (OS.get_environment("SCENE_LIST") if OS.has_environment("SCENE_LIST") else DEF).split(",")
	for nm in names:
		var path := "res://scenes/%s.tscn" % nm
		if not ResourceLoader.exists(path):
			continue
		var sc: Node = load(path).instantiate()
		get_tree().root.add_child(sc)
		get_tree().current_scene = sc
		for _i in range(40):
			await get_tree().process_frame
		_scan(nm, sc)
		sc.queue_free()
		await get_tree().process_frame
	print("[VC] 共 %d 处" % _hits)
	get_tree().quit()


func _scan(nm: String, root: Node) -> void:
	for n in root.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		if l.vertical_alignment != VERTICAL_ALIGNMENT_CENTER and l.vertical_alignment != VERTICAL_ALIGNMENT_BOTTOM:
			continue
		var f: Font = l.get_theme_font("font")
		var fs: int = l.get_theme_font_size("font_size")
		if f == null:
			continue
		var nl: int = maxi(1, l.get_line_count())
		var lh: float = f.get_height(fs) * float(nl) + float(l.get_theme_constant("line_spacing")) * float(nl - 1)   # 行距只算行与行之间(单行不加)
		if l.size.y + 1.0 < lh:
			_hits += 1
			print("[VC] %s | %s | 「%s」 框高 %.0f < 行高 %.0f (%d 号) ⇒ 偏下约 %.0f 像素" % [nm, str(root.get_path_to(l)), l.text.replace("\n", "⏎").left(24), l.size.y, lh, fs, (lh - l.size.y) * 0.5])
