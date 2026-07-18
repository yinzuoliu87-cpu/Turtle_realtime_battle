extends Control

## MatchmakingScene — 匹配动画: 选龟后进入, 匹配几秒 → 显示「我 vs 对手」(头像+ID) → 进 2.5D 战斗.
## 实时版流程: MainMenu → TeamSelect(选龟) → Matchmaking(本场景, 抽对手) → RealtimeBattle3D(战斗).
## 对手 = 后端 ghost 池抽同档快照 (池空 → bot 兜底); 抽到的写 GameState.dual_ghost, 战斗右队读其 leaders.

const W := 1280
const H := 720
const FAKE_NAMES := [
	"深海霸主", "龟界传说", "咸鱼翻身", "老司机带带我", "萌新龟龟", "海底捞月", "龟速前进", "一击三连",
	"佛系养龟", "头号玩家", "水深危险", "乌龟跑得快", "退役龟皇", "龟龟不下班", "南极来的", "稳健型选手",
]
const Backend := preload("res://scripts/engine/backend.gd")

var content_root: Control
var _font_cache: FontVariation = null
var _dots_lbl: Label = null
var _dots_tween: Tween = null
var _cancelled := false


func _ready() -> void:
	await get_tree().process_frame
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await get_tree().process_frame
	Audio.play_bgm("menu", 1.0, 0.4)
	_bg()
	content_root = Control.new()
	content_root.size = Vector2(W, H); content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	_center()
	get_viewport().size_changed.connect(_center)

	_build_cancel_btn()   # 取消键: 误点匹配可中途返回主菜单 (流程审计 F1)
	# V2 异步匹配: 后端抽同档对手快照 (ghost/池空→bot 兜底); 战斗右队读 dual_ghost.leaders (RealtimeBattle3DScene._resolve_right).
	#   排除自己上传的ghost(防匹到自己阵容) + 最近3场对手; vs 卡头像/名取自抽到的对手 profile.
	var _rng := RandomNumberGenerator.new(); _rng.randomize()
	var exclude: Array = ["g_%d" % int(GameState.season_id)]   # ★排除自己ghost(按稳定id·2026-07-18): 原塞season_leaders(宠物id)与ghost_id口径不符=死代码防不住; 玩家自己upload的id=g_<大轮id>
	exclude.append_array(GameState.recent_ghost_ids)   # 排除最近3场对手(防连续同一快照·用户2026-07-15)
	GameState.dual_ghost = Backend.find_opponent(Backend.bracket_for_battles(int(GameState.season_total_battles)), exclude, _rng)
	var _gid := str((GameState.dual_ghost as Dictionary).get("ghost_id", "")) if GameState.dual_ghost is Dictionary else ""
	if _gid != "":
		GameState.recent_ghost_ids.append(_gid)
		while GameState.recent_ghost_ids.size() > 3: GameState.recent_ghost_ids.pop_front()
	var opp := _opponent_from_ghost(GameState.dual_ghost)
	GameState.dual_opponent = opp
	_build_searching()
	await get_tree().create_timer(2.2).timeout
	if _cancelled or not is_inside_tree():
		return
	_build_vs(opp)
	await get_tree().create_timer(2.2).timeout
	if _cancelled or not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/RealtimeBattle3D.tscn")


func _center() -> void:
	if content_root != null:
		content_root.position = ((get_viewport_rect().size - Vector2(W, H)) / 2.0).round()


## 取消匹配键 (左上角): 加到 self 而非 content_root → 不被 _build_searching/_build_vs 的清屏移除.
func _build_cancel_btn() -> void:
	var btn := Button.new()
	btn.text = "← 取消"
	btn.add_theme_font_override("font", _bold_font())
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#cfe0ee"))
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#16283a"); sb.set_corner_radius_all(10); sb.set_border_width_all(2); sb.border_color = Color("#2d4658")
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate(); sbh.bg_color = Color("#1d3447"); sbh.border_color = Color("#3d5a70")
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.position = Vector2(28, 28)
	btn.pressed.connect(_on_cancel)
	add_child(btn)


func _on_cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	if _dots_tween != null and _dots_tween.is_valid():
		_dots_tween.kill()
	GameState.mode = "single"   # 离开双路 → 中性态; 下次入口会再 reset_dual_lane
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


## 对手资料卡 = 抽到的 ghost 快照 profile (头像取其首领 / 名+ID); profile 缺字段时随机兜底 (老 bot 也有 profile).
func _opponent_from_ghost(ghost: Dictionary) -> Dictionary:
	var prof: Dictionary = ghost.get("profile", {}) if ghost is Dictionary else {}
	var leaders: Array = ghost.get("leaders", []) if ghost is Dictionary else []
	var avatar := str(prof.get("avatar", ""))
	if avatar == "" and not leaders.is_empty():
		avatar = str(leaders[0])
	if avatar == "":
		avatar = "basic"
	var nm := str(prof.get("name", ""))
	if nm == "":
		nm = FAKE_NAMES[randi() % FAKE_NAMES.size()]
	var oid := str(prof.get("id", ""))
	if oid == "" or oid == "BOT":
		oid = "#%06d" % (randi() % 1000000)
	return {"name": nm, "avatar": avatar, "id": oid}


## 我方资料卡: 头像取本场锁定的首领 (season_leaders[0]), 否则随机.
func _player_profile() -> Dictionary:
	var pid := "basic"
	var leaders: Array = GameState.season_leaders if GameState.season_leaders is Array else []
	if not leaders.is_empty():
		pid = str(leaders[0])
	elif not DataRegistry.launch_pets.is_empty():
		pid = str(DataRegistry.launch_pets[randi() % DataRegistry.launch_pets.size()].get("id", "basic"))
	return {"name": "你", "avatar": pid, "id": "#%06d" % (randi() % 1000000)}


func _bg() -> void:
	var base := ColorRect.new(); base.set_anchors_preset(Control.PRESET_FULL_RECT); base.color = Color("#0a1622")
	add_child(base)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0); grad.set_color(0, Color(0.04, 0.09, 0.14, 1.0))
	grad.set_offset(1, 1.0); grad.set_color(1, Color(0.02, 0.04, 0.07, 1.0))
	var gt := GradientTexture2D.new(); gt.gradient = grad; gt.fill_from = Vector2(0.5, 0.0); gt.fill_to = Vector2(0.5, 1.0)
	var tr := TextureRect.new(); tr.set_anchors_preset(Control.PRESET_FULL_RECT); tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)


func _font(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold_font())
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bold_font() -> FontVariation:
	if _font_cache == null:
		var cjk := SystemFont.new()
		cjk.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		cjk.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
		cjk.font_weight = 700; cjk.allow_system_fallback = true; cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_cache = FontVariation.new()
		_font_cache.base_font = load("res://assets/fonts/m6x11.ttf") as FontFile
		_font_cache.fallbacks = [cjk]
	return _font_cache


func _build_searching() -> void:
	for c in content_root.get_children():
		c.queue_free()
	var title := _font(40, Color("#ffd93d"))
	title.text = "🔍 匹配中"
	title.size = Vector2(W, 56); title.position = Vector2(0, 300); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(title)
	_dots_lbl = _font(40, Color("#ffd93d"))
	_dots_lbl.text = ""; _dots_lbl.size = Vector2(60, 56); _dots_lbl.position = Vector2(W / 2.0 + 96, 300)
	content_root.add_child(_dots_lbl)
	var sub := _font(20, Color("#9fb6c9"))
	sub.text = "正在为你寻找势均力敌的对手..."
	sub.size = Vector2(W, 28); sub.position = Vector2(0, 366); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(sub)
	# 跳动的点
	_dots_tween = create_tween().set_loops()
	for d in ["", ".", "..", "..."]:
		_dots_tween.tween_callback(func(): if is_instance_valid(_dots_lbl): _dots_lbl.text = d)
		_dots_tween.tween_interval(0.35)


func _build_vs(opp: Dictionary) -> void:
	if _dots_tween != null and _dots_tween.is_valid():
		_dots_tween.kill()
	for c in content_root.get_children():
		c.queue_free()
	var found := _font(26, Color("#7fd98a"))
	found.text = "✓ 已匹配到对手!"
	found.size = Vector2(W, 34); found.position = Vector2(0, 110); found.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(found)
	# VS
	var vs := _font(64, Color("#ff6b6b"))
	vs.text = "VS"; vs.size = Vector2(160, 80); vs.position = Vector2(W / 2.0 - 80, 320); vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_root.add_child(vs)
	vs.scale = Vector2(0.2, 0.2); vs.pivot_offset = Vector2(80, 40)
	vs.create_tween().tween_property(vs, "scale", Vector2(1, 1), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
	# 两张资料卡 (左=你 滑入, 右=对手 滑入)
	var me := _player_profile()
	_build_card(me, Vector2(170, 230), Color("#5aa9ff"), -500.0)
	_build_card(opp, Vector2(740, 230), Color("#ff6b6b"), 500.0)


func _build_card(prof: Dictionary, pos: Vector2, accent: Color, slide_from_dx: float) -> void:
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#10202c"); sb.set_corner_radius_all(14); sb.set_border_width_all(3); sb.border_color = accent
	card.add_theme_stylebox_override("panel", sb)
	card.size = Vector2(370, 280); card.position = pos
	content_root.add_child(card)
	# 头像
	var avatar_path := "res://assets/sprites/avatars/%s.png" % str(prof.get("avatar", "basic"))
	if ResourceLoader.exists(avatar_path):
		var tr := TextureRect.new(); tr.texture = load(avatar_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.size = Vector2(140, 140); tr.position = Vector2(115, 20)
		card.add_child(tr)
	else:
		var emo := _font(96, Color.WHITE); emo.text = "🐢"; emo.size = Vector2(370, 140); emo.position = Vector2(0, 24)
		emo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(emo)
	var name_l := _font(28, accent)
	name_l.text = str(prof.get("name", "?")); name_l.size = Vector2(370, 36); name_l.position = Vector2(0, 178)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(name_l)
	var id_l := _font(18, Color("#9fb6c9"))
	id_l.text = "ID %s" % str(prof.get("id", "")); id_l.size = Vector2(370, 24); id_l.position = Vector2(0, 220)
	id_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; card.add_child(id_l)
	# 滑入动画
	var home_x := pos.x
	card.position.x = home_x + slide_from_dx; card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", home_x, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.5)
