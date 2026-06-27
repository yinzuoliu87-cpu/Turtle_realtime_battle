extends Node2D
## RealtimeBattleScene — 斗龟场实时版 · 实时战斗原型 (阶段0+1 + 阶段2/3雏形)
## 2D 俯视自由走位 3v3: 近战追最近敌 / 远程保持射程风筝 · 按攻速自动普攻 ·
## 龟能随时间回满→放各自的主动技 · 灭对方全队=胜.
## 时间制状态系统(按秒): 护盾吸收 / 灼烧DoT / 麻痹眩晕 —— 验证"回合→秒"改造.
## 全新自含, 不碰回合制 BattleScene. 复用 data/pets.json 数据 + avatars 精灵.
## ⚠ 所有数值是 #7 草案起步值 + 简化伤害公式, 全待 F5 调手感.

const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 x,y,w,h
const MAX_ENERGY := 100.0
const REGEN_PER_SEC := 14.0                # 龟能每秒回 (≈7s 满)
const SEP_RADIUS := 48.0                   # 单位软分离半径
const SHIELD_CAP_MULT := 1.5               # 护盾上限 = maxHp ×

# 全 28 龟战斗属性 (28龟角色映射草案 #7 档位): id → [melee, move_spd, atk_interval(s), atk_range]
const STATS := {
	"basic": [true, 105.0, 1.0, 70.0], "stone": [true, 70.0, 1.5, 70.0], "bamboo": [true, 105.0, 1.0, 70.0],
	"angel": [false, 105.0, 1.0, 230.0], "ice": [false, 105.0, 1.0, 230.0], "ninja": [true, 145.0, 0.65, 70.0],
	"two_head": [true, 145.0, 1.0, 70.0], "ghost": [false, 145.0, 0.65, 340.0], "diamond": [true, 70.0, 1.5, 70.0],
	"fortune": [true, 105.0, 1.0, 70.0], "dice": [false, 145.0, 0.65, 230.0], "rainbow": [true, 105.0, 1.0, 70.0],
	"gambler": [false, 145.0, 1.0, 230.0], "hunter": [false, 145.0, 0.65, 340.0], "pirate": [false, 105.0, 1.0, 230.0],
	"candy": [false, 105.0, 1.0, 230.0], "bubble": [false, 70.0, 1.5, 230.0], "line": [false, 145.0, 0.65, 340.0],
	"lightning": [false, 145.0, 0.65, 340.0], "phoenix": [false, 105.0, 1.0, 230.0], "lava": [true, 145.0, 1.0, 70.0],
	"cyber": [false, 105.0, 1.0, 230.0], "crystal": [true, 70.0, 1.5, 70.0], "chest": [true, 105.0, 1.5, 70.0],
	"space": [false, 145.0, 1.0, 340.0], "hiding": [true, 70.0, 1.5, 70.0], "headless": [true, 145.0, 1.0, 70.0],
	"shell": [true, 105.0, 1.5, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 1.0, 70.0]
# demo 兜底阵容 (id 列表, 属性查 STATS) — 没配队时用
const LEFT_DEMO := ["stone", "basic", "lightning"]
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

var _units: Array = []
var _data_by_id: Dictionary = {}
var _over := false
var _banner: Label = null
var _t := 0.0   # 战斗经过秒数 (时间制基准, 取代回合计数)

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
	hint.text = "近战追·远程风筝·攒满龟能放各自技能(护盾/突进/闪电/诅咒)·灭队=胜   [R 重开 · ESC 返回菜单]"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("#7f97ad"))
	hint.position = Vector2(70, 86)
	add_child(hint)

func _spawn_teams() -> void:
	var left := _resolve_left()
	var right := _resolve_right(left)
	for i in range(left.size()):
		var pos := Vector2(ARENA.position.x + 130, ARENA.position.y + 110 + i * 150)
		_units.append(_make_unit(str(left[i]), "left", pos))
	for i in range(right.size()):
		var pos := Vector2(ARENA.end.x - 130, ARENA.position.y + 110 + i * 150)
		_units.append(_make_unit(str(right[i]), "right", pos))

func _resolve_left() -> Array:
	# 玩家赛季阵容优先 (GameState.season_leaders), 否则 demo
	var ldr := _season_leaders()
	return ldr if ldr.size() >= 1 else LEFT_DEMO.duplicate()

func _resolve_right(left: Array) -> Array:
	# 敌队 = 随机 bot 3 龟 (后续接 ghost 快照); demo 时固定对位
	if _season_leaders().is_empty():
		return RIGHT_DEMO.duplicate()
	return _random_bot(3)

func _season_leaders() -> Array:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var ldr = gs.get("season_leaders")
	if not (ldr is Array):
		return []
	var out: Array = []
	for x in ldr:
		if STATS.has(str(x)):
			out.append(str(x))
		if out.size() >= 3:
			break
	return out

func _random_bot(n: int) -> Array:
	var pool: Array = STATS.keys()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array = []
	for i in range(mini(n, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

func _make_unit(id: String, side: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = _data_by_id.get(id, {})
	var st: Array = STATS.get(id, DEFAULT_STAT)
	var hp := float(d.get("hp", 450))
	var team_col := Color("#3fa9ff") if side == "left" else Color("#ff5a5a")

	var node := Node2D.new()
	node.position = pos
	add_child(node)

	var ground := ColorRect.new()
	ground.color = Color(team_col.r, team_col.g, team_col.b, 0.35)
	ground.size = Vector2(52, 16); ground.position = Vector2(-26, 18)
	node.add_child(ground)
	var spr := _make_sprite(id)
	node.add_child(spr)
	var nm := Label.new()
	nm.text = str(d.get("name", id))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", team_col)
	nm.position = Vector2(-30, -52); nm.size = Vector2(60, 14)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(nm)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color("#3a0d0d"); hp_bg.position = Vector2(-26, -38); hp_bg.size = Vector2(52, 7)
	node.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#39d353"); hp_fill.position = Vector2(-26, -38); hp_fill.size = Vector2(52, 7)
	node.add_child(hp_fill)
	var shield_fill := ColorRect.new()   # 护盾盖在血条上 (金)
	shield_fill.color = Color("#ffd93d"); shield_fill.position = Vector2(-26, -38); shield_fill.size = Vector2(0, 7)
	node.add_child(shield_fill)
	var en_fill := ColorRect.new()
	en_fill.color = Color("#48c9ff"); en_fill.position = Vector2(-26, -29); en_fill.size = Vector2(0, 4)
	node.add_child(en_fill)
	var dot := ColorRect.new()   # 状态点 (灼烧橙/麻痹黄)
	dot.color = Color(1, 1, 1, 0); dot.position = Vector2(20, -40); dot.size = Vector2(8, 8)
	node.add_child(dot)

	return {
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")),
		"side": side, "pos": pos, "vel": Vector2.ZERO,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": float(st[3]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0,
		"node": node, "spr": spr, "hp_fill": hp_fill, "shield_fill": shield_fill, "en_fill": en_fill, "dot": dot,
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
	var c := ColorRect.new(); c.color = Color("#8aa"); c.size = Vector2(48, 48); c.position = Vector2(-24, -24)
	var holder := Node2D.new(); holder.add_child(c)
	return holder

func _physics_process(delta: float) -> void:
	if _over:
		return
	_t += delta
	for u in _units:
		if not u["alive"]:
			continue
		# 灼烧 DoT (按秒, 穿过护盾后落血)
		if _t < u["burn_until"] and u["burn_dps"] > 0.0:
			_raw_lose(u, u["burn_dps"] * delta)
			if not u["alive"]:
				continue
		var stunned: bool = _t < u["stun_until"]
		# 状态点
		if stunned:
			u["dot"].color = Color("#ffe14d")
		elif _t < u["burn_until"]:
			u["dot"].color = Color("#ff7a33")
		else:
			u["dot"].color = Color(1, 1, 1, 0)

		var tgt = _nearest_enemy(u)
		if tgt == null:
			continue
		var to_t: Vector2 = tgt["pos"] - u["pos"]
		var dist := to_t.length()
		var rng: float = u["atk_range"]
		if not stunned:
			# 移动: 近战追到射程 / 远程维持射程并风筝
			var intent := Vector2.ZERO
			if dist > rng:
				intent = to_t.normalized()
			elif not u["melee"] and dist < rng * 0.7:
				intent = -to_t.normalized()
			intent += _separation(u)
			if intent.length() > 0.01:
				u["vel"] = intent.normalized() * u["move_spd"]
				u["pos"] += u["vel"] * delta
				u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
				u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
				u["node"].position = u["pos"]
				if absf(u["vel"].x) > 1.0:
					u["spr"].scale.x = absf(u["spr"].scale.x) * (1.0 if u["vel"].x >= 0.0 else -1.0)
			# 普攻
			if dist <= rng:
				u["atk_cd"] -= delta
				if u["atk_cd"] <= 0.0:
					_basic_attack(u, tgt)
					u["atk_cd"] = u["atk_interval"]
		# 龟能 (麻痹时不回, 体现控制价值)
		if not stunned:
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

# ---------- 普攻 ----------
func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	_apply_damage(tgt, _hit_dmg(u["atk"], tgt), Color("#ffe08a"))
	_flash(tgt)

# ---------- 主动技 (按龟 distinct) ----------
func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	match u["id"]:
		"stone":     _skill_team_shield(u, 80.0)               # 全队护盾
		"diamond":   _skill_team_shield(u, 120.0)              # 大护盾
		"ninja":     _skill_dash_combo(u, tgt)                 # 突进三连
		"lightning": _skill_aoe_stun(u, 1.4, 0.8)              # 范围闪电+麻痹
		"ghost":     _skill_curse(u, tgt)                      # 诅咒DoT
		_:           _skill_burst(u, tgt)                      # 默认重击 (小龟)

func _skill_team_shield(u: Dictionary, amt: float) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "护盾!", Color("#ffd93d"))
	for o in _units:
		if o["side"] == u["side"] and o["alive"]:
			o["shield"] = minf(o["shield"] + amt, o["maxHp"] * SHIELD_CAP_MULT)
			_update_bars(o)

func _skill_dash_combo(u: Dictionary, tgt: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "突进!", Color("#9be7ff"))
	# 瞬移到目标旁
	var dir: Vector2 = u["pos"] - tgt["pos"]
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	u["pos"] = tgt["pos"] + dir * (u["atk_range"] * 0.8)
	u["node"].position = u["pos"]
	for i in range(3):
		_apply_damage(tgt, _hit_dmg(u["atk"] * 0.9, tgt), Color("#ff9d5c"))
	_flash(tgt)

func _skill_aoe_stun(u: Dictionary, mult: float, stun_sec: float) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "闪电!", Color("#7ee8ff"))
	for o in _units:
		if o["side"] != u["side"] and o["alive"]:
			_apply_damage(o, _hit_dmg(u["atk"] * mult, o), Color("#9bdcff"))
			o["stun_until"] = maxf(o["stun_until"], _t + stun_sec)
			_skill_ring(o["pos"], Color(0.5, 0.85, 1.0, 0.5), 60.0)

func _skill_curse(u: Dictionary, tgt: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "诅咒!", Color("#c77dff"))
	_apply_damage(tgt, _hit_dmg(u["atk"] * 1.2, tgt), Color("#c77dff"))
	tgt["burn_dps"] = u["atk"] * 0.5
	tgt["burn_until"] = _t + 4.0   # 4 秒灼烧 (时间制)

func _skill_burst(u: Dictionary, tgt: Dictionary) -> void:
	_float_text(u["pos"] + Vector2(0, -64), "重击!", Color("#ff9d5c"))
	_apply_damage(tgt, _hit_dmg(u["atk"] * 2.5, tgt), Color("#ff9d5c"))
	for o in _units:
		if o != tgt and o["side"] != u["side"] and o["alive"] and (o["pos"] - tgt["pos"]).length() <= 110.0:
			_apply_damage(o, _hit_dmg(u["atk"] * 1.25, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"], Color(1.0, 0.6, 0.3, 0.5), 110.0)

# ---------- 伤害 / 状态 ----------
func _hit_dmg(base: float, tgt: Dictionary) -> int:
	# 简化护甲减伤 (TODO: 接 Damage.calc_damage + 物/法分流)
	return maxi(1, int(round(base * (100.0 / (100.0 + float(tgt["def"]))))))

func _apply_damage(u: Dictionary, dmg: int, col: Color) -> void:
	var d := float(dmg)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	_update_bars(u)
	_float_text(u["pos"] + Vector2(0, -40), str(dmg), col)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

func _raw_lose(u: Dictionary, amt: float) -> void:
	# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], amt)
		u["shield"] -= ab; amt -= ab
	u["hp"] = maxf(0.0, u["hp"] - amt)
	_update_bars(u)
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
	u["shield_fill"].size.x = 52.0 * clampf(u["shield"] / u["maxHp"], 0.0, 1.0)
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
	l.position = pos; l.z_index = 10
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 28.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)

func _skill_ring(pos: Vector2, col: Color, radius: float) -> void:
	var r := ColorRect.new()
	r.color = col
	r.size = Vector2(20, 20); r.position = pos - Vector2(10, 10); r.z_index = 5
	add_child(r)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "size", Vector2(radius * 2, radius * 2), 0.35)
	tw.tween_property(r, "position", pos - Vector2(radius, radius), 0.35)
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
	_banner.position = Vector2(420, 320); _banner.z_index = 50
	add_child(_banner)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
