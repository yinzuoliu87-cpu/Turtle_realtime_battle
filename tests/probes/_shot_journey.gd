extends Node
## _shot_journey.gd —— 夺冠之路一整周实拍(方案书 20261124; 探针, 不进门禁)。造一份全周回包喂给冠军收盘, 拍 path 拍落定 + 定格卡。
## 跑法: WINDOW=1 bash godot-quiet.sh --resolution 1560x720 --position 2000,80 res://tests/probes/_shot_journey.tscn
## 产物: .out/journey/path-<宽>x<高>.png / card-<宽>x<高>.png

const FIX := preload("res://tests/_champion_fixture.gd")
const DATA := preload("res://scripts/scenes/bracket/champion_data.gd")
const SHOW := preload("res://scripts/scenes/bracket/champion_show.gd")
const JN := preload("res://scripts/net/journey_net.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const NAMES := ["深海小龟王", "火山岩", "北极光", "Kiki", "huihui", "老王不在", "afei23", "糖豆", "竹子先生", "不吃香菜",
	"石头统领", "龟龟冲鸭", "jyz11", "头发多多", "小辉同学", "ykx1314"]


func _row(id: int, kind: String, won: bool, la: Dictionary, bucket: int = -1) -> Dictionary:
	var d := {"id": id, "kind": kind, "at": 1000 + id, "won": won, "lanes": la,
		"foe": {"name": NAMES[id % NAMES.size()], "avatar": "basic", "leaders": ["basic"]}}
	if kind == "finals":
		d["finals"] = {"bucket": bucket, "round": 1, "match": 0}
	return d


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var out := ProjectSettings.globalize_path("res://.out/journey")
	DirAccess.make_dir_recursive_absolute(out)
	var pats := [{"top": "me", "bottom": "me"}, {"top": "me", "bottom": "foe", "final": "me"}, {"top": "me"},
		{"top": "foe", "bottom": "me", "final": "me"}]
	var lose := {"top": "foe", "bottom": "foe"}
	var raw: Array = []
	var id := 0
	for i in range(16):
		id += 1
		raw.append(_row(id, "ranked", i % 4 != 3, pats[i % 4] if i % 4 != 3 else lose))
	for i in range(6):
		id += 1
		raw.append(_row(id, "gauntlet", i != 2 and i != 4, pats[i % 2] if (i != 2 and i != 4) else lose))
	for i in range(2):
		id += 1
		raw.append(_row(id, "finals", true, pats[i], 9900001))
	var st: Array = JN.stages(JN.parse(true, 200, JSON.stringify({"ok": true, "rows": raw}))["rows"])
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var d: Dictionary = DATA.cup_show(FIX.view(), FIX.WEEK, FIX.rows(), FIX.acc(4, 0))
	d["journey"] = st
	d["vp"] = vp
	var s = SHOW.create(d)
	s.auto_advance = false
	add_child(s)
	await get_tree().process_frame
	while s.current_beat() != "path":
		s.advance(1.0 / 60.0)
	var anim: float = float(s._beat("path")["anim"])
	while s.current_beat() == "path" and s.bt < anim + 0.1:
		s.advance(1.0 / 60.0)
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/path-%dx%d.png" % [out, int(vp.x), int(vp.y)])
	while not s.is_settled():
		s.advance(1.0 / 60.0)
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/card-%dx%d.png" % [out, int(vp.x), int(vp.y)])
	print("SHOTS DONE")
	get_tree().quit(0)
