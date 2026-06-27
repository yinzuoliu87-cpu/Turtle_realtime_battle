extends Node2D
## RealtimeBattleScene — 斗龟场实时版 · 第一个实时战斗原型 (阶段0+1)
## 2D 俯视自由走位 3v3: 近战追最近敌 / 远程保持射程风筝 · 按攻速自动普攻 ·
## 龟能随时间回满→放通用主动技 · 灭对方全队=胜.
## 全新自含, 不碰回合制 BattleScene. 复用 data/pets.json 数据 + avatars 精灵.
## ⚠ 所有数值是 #7 草案起步值 + 简化伤害公式, 全待 F5 调手感.

const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 x,y,w,h
const MAX_ENERGY := 100.0
const REGEN_PER_SEC := 14.0                # 龟能每秒回 (≈7s 满)
const SEP_RADIUS := 48.0                   # 单位软分离半径
const SKILL_MULT := 2.5                    # 主动技 = 普攻基数 ×
const SKILL_SPLASH := 120.0               # 主动技溅射半径

# 阵容档位: [id, melee, move_spd, atk_interval(s), atk_range] —— 按 28龟角色映射草案 #7 档位
const LEFT_TEAM := [
	["stone",     true,   70.0, 1.5,  70.0],   # 石头 坦克 慢/慢攻/近
	["basic",     true,  105.0, 1.0,  70.0],   # 小龟 近战dps 中
	["lightning", false, 145.0, 0.65, 340.0],  # 闪电 远程 快/快攻/远
]
const RIGHT_TEAM := [
	["diamond",   true,   70.0, 1.5,  70.0],   # 钻石 坦克
	["ninja",     true,  145.0, 0.65, 70.0],   # 忍者 近战刺杀 快
	["ghost",     false, 145.0, 0.65, 340.0],  # 幽灵 远程狙击 快/远
]

var _units: Array = []
var _data_by_id: Dictionary = {}
var _over := false
var _banner: Label = null

func _ready() -> void:
	_load_pets()
	_build_arena()
	_spawn_teams()

func _load_pets() -> void:
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	if f == null:
		push_warning("RealtimeBattle: pets.json 打不开")
		return
	var arr = JSON.parse_string(f.get_as_text())
	if arr is Array:
		for p in arr:
			if p is Dictionary and p.has("id"):
				_data_by_id[str(p["id"])] = p

func _build_arena() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0a1420")
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var floor := ColorRect.new()
	floor.color = Color("#13283d")
	floor.position = ARENA.position
	floor.size = ARENA.size
	add_child(floor)
	var title := Label.new()
	title.text = "实时战斗原型 · 3v3 俯视自由走位 (左队 vs 右队)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(70, 60)
	add_child(title)
	var hint := Label.new()
	hint.text = "近战追·远程风筝·攒满龟能放技能·灭队=胜   [R 重开]"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("#7f97ad"))
	hint.position = Vector2(70, 86)
	add_child(hint)

func _spawn_teams() -> void:
	for i in range(LEFT_TEAM.size()):
		var pos := Vector2(ARENA.position.x + 130, ARENA.position.y + 110 + i * 150)
		_units.append(_make_unit(LEFT_TEAM[i], "left", pos))
	for i in range(RIGHT_TEAM.size()):
		var pos := Vector2(ARENA.end.x - 130, ARENA.position.y + 110 + i * 150)
		_units.append(_make_unit(RIGHT_TEAM[i], "right", pos))

func _make_unit(spec: Array, side: String, pos: Vector2) -> Dictionary:
	var id := str(spec[0])
	var d: Dictionary = _data_by_id.get(id, {})
	var hp := float(d.get("hp", 450))
	var team_col := Color("#3fa9ff") if side == "left" else Color("#ff5a5a")

	var node := Node2D.new()
	node.position = pos
	add_child(node)

	# 脚下队伍色地标
	var ground := ColorRect.new()
	ground.color = Color(team_col.r, team_col.g, team_col.b, 0.35)
	ground.size = Vector2(52, 16)
	ground.position = Vector2(-26, 18)
	node.add_child(ground)
	# 精灵 (avatar 头像当 token)
	var spr := _make_sprite(id)
	node.add_child(spr)
	# 名字
	var nm := Label.new()
	nm.text = str(d.get("name", id))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", team_col)
	nm.position = Vector2(-30, -52)
	nm.size = Vector2(60, 14)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(nm)
	# 血条
	var hp_bg := ColorRect.new()
	hp_bg.color = Color("#3a0d0d"); hp_bg.position = Vector2(-26, -38); hp_bg.size = Vector2(52, 7)
	node.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#39d353"); hp_fill.position = Vector2(-26, -38); hp_fill.size = Vector2(52, 7)
	node.add_child(hp_fill)
	# 龟能条
	var en_fill := ColorRect.new()
	en_fill.color = Color("#48c9ff"); en_fill.position = Vector2(-26, -29); en_fill.size = Vector2(0, 4)
	node.add_child(en_fill)

	return {
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")),
		"side": side, "pos": pos, "vel": Vector2.ZERO,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"melee": bool(spec[1]), "move_spd": float(spec[2]),
		"atk_interval": float(spec[3]), "atk_range": float(spec[4]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		"node": node, "spr": spr, "hp_fill": hp_fill, "en_fill": en_fill,
	}

func _make_sprite(id: String) -> Node2D:
	var path := "res://assets/sprites/avatars/%s.png" % id
	if ResourceLoader.exists(path):
		var s := Sprite2D.new()
		s.texture = load(path)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tw := float(s.texture.get_width())
		if tw > 0:
			s.scale = Vector2.ONE * (56.0 / tw)
		return s
	# 兜底: 色块
	var c := ColorRect.new(); c.color = Color("#8aa"); c.size = Vector2(48, 48); c.position = Vector2(-24, -24)
	var holder := Node2D.new(); holder.add_child(c)
	return holder

func _physics_process(delta: float) -> void:
	if _over:
		return
	for u in _units:
		if not u["alive"]:
			continue
		var tgt = _nearest_enemy(u)
		if tgt == null:
			continue
		var to_t: Vector2 = tgt["pos"] - u["pos"]
		var dist := to_t.length()
		var rng: float = u["atk_range"]
		# 移动意图: 近战追到射程 / 远程维持射程并风筝
		var intent := Vector2.ZERO
		if dist > rng:
			intent = to_t.normalized()
		elif not u["melee"] and dist < rng * 0.7:
			intent = -to_t.normalized()   # 远程后撤风筝
		intent += _separation(u)
		if intent.length() > 0.01:
			u["vel"] = intent.normalized() * u["move_spd"]
			u["pos"] += u["vel"] * delta
			u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
			u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
			u["node"].position = u["pos"]
			if absf(u["vel"].x) > 1.0:
				u["spr"].scale.x = absf(u["spr"].scale.x) * (1.0 if u["vel"].x >= 0.0 else -1.0)
		# 攻击
		if dist <= rng:
			u["atk_cd"] -= delta
			if u["atk_cd"] <= 0.0:
				_basic_attack(u, tgt)
				u["atk_cd"] = u["atk_interval"]
		# 龟能
		u["energy"] += REGEN_PER_SEC * delta
		if u["energy"] >= MAX_ENERGY:
			u["energy"] = 0.0
			_cast_active(u, tgt)
		_update_bars(u)
	_check_end()

func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d := INF
	for o in _units:
		if o["side"] == u["side"] or not o["alive"]:
			continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

func _separation(u: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	for o in _units:
		if o == u or not o["alive"]:
			continue
		var d: Vector2 = u["pos"] - o["pos"]
		var l := d.length()
		if l > 0.01 and l < SEP_RADIUS:
			push += d.normalized() * (1.0 - l / SEP_RADIUS)
	return push * 0.9

func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	var dmg := _hit_dmg(u["atk"], tgt)
	_apply_damage(tgt, dmg, Color("#ffe08a"))
	_flash(tgt)

func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "技能!", Color("#7ee8ff"))
	# 主区目标重击 + 范围溅射
	var main_dmg := _hit_dmg(u["atk"] * SKILL_MULT, tgt)
	_apply_damage(tgt, main_dmg, Color("#ff9d5c"))
	for o in _units:
		if o == tgt or o["side"] == u["side"] or not o["alive"]:
			continue
		if (o["pos"] - tgt["pos"]).length() <= SKILL_SPLASH:
			_apply_damage(o, _hit_dmg(u["atk"] * SKILL_MULT * 0.5, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"])

func _hit_dmg(base: float, tgt: Dictionary) -> int:
	# 简化护甲减伤 (TODO: 接 Damage.calc_damage + 物/法分流)
	return maxi(1, int(round(base * (100.0 / (100.0 + float(tgt["def"]))))))

func _apply_damage(u: Dictionary, dmg: int, col: Color) -> void:
	u["hp"] = maxf(0.0, u["hp"] - float(dmg))
	_update_bars(u)
	_float_text(u["pos"] + Vector2(0, -40), str(dmg), col)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

func _kill(u: Dictionary) -> void:
	u["alive"] = false
	var n: Node2D = u["node"]
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.4)
	tw.tween_callback(n.hide)

func _update_bars(u: Dictionary) -> void:
	if not is_instance_valid(u["hp_fill"]):
		return
	u["hp_fill"].size.x = 52.0 * clampf(u["hp"] / u["maxHp"], 0.0, 1.0)
	u["en_fill"].size.x = 52.0 * clampf(u["energy"] / MAX_ENERGY, 0.0, 1.0)

func _flash(u: Dictionary) -> void:
	var s = u["spr"]
	if not is_instance_valid(s):
		return
	s.modulate = Color(2, 2, 2)
	var tw := create_tween()
	tw.tween_property(s, "modulate", Color.WHITE, 0.15)

func _float_text(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.position = pos
	l.z_index = 10
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 28.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)

func _skill_ring(pos: Vector2) -> void:
	var r := ColorRect.new()
	r.color = Color(1.0, 0.6, 0.3, 0.5)
	r.size = Vector2(20, 20); r.position = pos - Vector2(10, 10)
	r.z_index = 5
	add_child(r)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "size", Vector2(SKILL_SPLASH * 2, SKILL_SPLASH * 2), 0.35)
	tw.tween_property(r, "position", pos - Vector2(SKILL_SPLASH, SKILL_SPLASH), 0.35)
	tw.tween_property(r, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(r.queue_free)

func _check_end() -> void:
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"]:
			if u["side"] == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		_show_banner("左队 胜利!" if right_alive == 0 else "右队 胜利!")

func _show_banner(text: String) -> void:
	_banner = Label.new()
	_banner.text = text + "   按 R 重开"
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", Color("#ffd93d"))
	_banner.position = Vector2(420, 320)
	_banner.z_index = 50
	add_child(_banner)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()
