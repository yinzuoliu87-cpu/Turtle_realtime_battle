extends Control

## LeaderboardScene — V2 排行榜 (阶段5 MVP, 设计§五/§十三). 按本赛季击杀龟蛋数降序.
## MVP: 本地 ghost 池各阵容的 season_eggs_killed + 自己, 排序展示. 真后端复算防作弊=上线版.

const W := 1280.0
const Backend = preload("res://scripts/engine/backend.gd")

func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color("#0a1622")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)

	var title := Label.new(); title.text = "🏆 排行榜 · 本赛季击杀龟蛋数"
	title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.position = Vector2(W / 2.0 - 280, 24); title.size = Vector2(560, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(title)

	var back := Button.new(); back.text = "← 返回"; back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(28, 26); back.size = Vector2(120, 44)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")); add_child(back)

	var pool := Backend.load_pool()
	var rows := Backend.leaderboard(pool, "我 (玩家)", int(GameState.season_eggs_killed), 30)

	# 表面板
	var panel := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.12, 0.18, 0.9); psb.border_color = Color("#2e4a5e")
	psb.set_border_width_all(2); psb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(W / 2.0 - 360, 96); panel.size = Vector2(720, 560)
	add_child(panel)

	# 表头
	_row_labels(panel, 14, "#58d3ff", "排名", "玩家", "击杀蛋数", true)
	var y := 52
	var rank := 1
	for r in rows:
		var is_self: bool = bool(r.get("is_self", false))
		if y > 540:
			break
		if is_self:
			var hl := ColorRect.new(); hl.color = Color(1.0, 0.85, 0.24, 0.14)
			hl.position = Vector2(8, y - 4); hl.size = Vector2(704, 36); panel.add_child(hl)
		_row_labels(panel, y, "#ffd93d" if is_self else "#dfe9f2",
			"#%d" % rank, str(r.get("name", "?")) + ("  ◀ 你" if is_self else ""), str(int(r.get("eggs", 0))), false)
		y += 40
		rank += 1
	if rows.size() <= 1:
		var hint := Label.new(); hint.text = "（打几局上传阵容后, 这里会出现更多对手排名）"
		hint.add_theme_font_size_override("font_size", 15); hint.add_theme_color_override("font_color", Color("#5a6675"))
		hint.position = Vector2(24, y + 12); hint.size = Vector2(680, 24); panel.add_child(hint)

func _row_labels(parent: Control, y: int, color: String, c1: String, c2: String, c3: String, header: bool) -> void:
	var fs := 15 if header else 18
	var xs := [40, 160, 560]
	var txts := [c1, c2, c3]
	var ws := [110, 380, 140]
	for i in range(3):
		var l := Label.new(); l.text = txts[i]
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color(color))
		l.position = Vector2(xs[i], y); l.size = Vector2(ws[i], 28)
		if i == 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		parent.add_child(l)
