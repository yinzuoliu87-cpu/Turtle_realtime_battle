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
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类 DoT 每秒结算一次
const HP_MULT := 2.5                       # 战斗节奏旋钮: HP放大让战斗更耐看(~20s,技能多放几轮), 待F5调

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
	_apply_spawn_passives()

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
	var hp := float(d.get("hp", 450)) * HP_MULT
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
		"base_atk": float(d.get("atk", 40)), "base_def": float(d.get("def", 12)), "base_mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": float(st[3]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		# 永久护盾 / 控制 / 灼烧(保留旧名) ----
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0,
		# 新增效果积木状态 ----
		"buffs": [],                 # [{stat, mult/add, until}] 临时属性 buff
		"dots": [],                  # [{tag, dps, until, raw(bool=真伤)}] 流血/中毒/诅咒/灼烧通用 DoT
		"taunt_until": 0.0, "taunt_by": null,   # 被嘲讽: 强制索敌 taunt_by 直到 until
		"slow_until": 0.0,           # 冰寒减速/减攻
		"stacks": {},                # 叠层标记 {electric:n, crystal:n, ink:n, ...}
		"rage": 0.0,                 # 怒气 (熔岩)
		"star_energy": 0.0,          # 星能 (星际)
		"store_energy": 0.0,         # 储能 (龟壳)
		"gold": 0.0,                 # 财神金币池
		"dmg_dealt": 0.0,            # 累计造成伤害 (天使"伤害最高"/宝箱财宝值)
		"reborn_used": false,        # 首死复活 (天使圣光/凤凰涅槃)
		"untargetable_until": 0.0,   # 不可选 (黑洞)
		"summons": [],               # 召唤物单位引用
		# UI ----
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
	# 注: 战斗中可能召唤新单位 → 迭代副本, 召唤体也走同一套 tick
	for u in _units.duplicate():
		if not u["alive"]:
			continue
		_tick_effects(u, delta)        # DoT/buff到期/累积条/周期被动
		if not u["alive"]:
			continue
		var stunned: bool = _t < u["stun_until"]
		_update_status_dot(u, stunned)

		var tgt = _acquire_target(u)
		if tgt == null:
			_update_bars(u); continue
		var to_t: Vector2 = tgt["pos"] - u["pos"]
		var dist := to_t.length()
		var rng: float = u["atk_range"]
		if not stunned:
			var spd: float = u["move_spd"] * (0.6 if _t < u["slow_until"] else 1.0)
			# 移动: 近战追到射程 / 远程维持射程并风筝
			var intent := Vector2.ZERO
			if dist > rng:
				intent = to_t.normalized()
			elif not u["melee"] and dist < rng * 0.7:
				intent = -to_t.normalized()
			intent += _separation(u)
			if intent.length() > 0.01:
				u["vel"] = intent.normalized() * spd
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
		# 龟能 (麻痹时不回, 体现控制价值; 选被动的龟 energy 维持 0 → 永不放主动)
		if not stunned and not _is_passive_pick(u):
			u["energy"] += REGEN_PER_SEC * delta
			if u["energy"] >= MAX_ENERGY:
				u["energy"] = 0.0
				_cast_active(u, tgt)
		_update_bars(u)
	_check_end()

# 每单位每帧: DoT 落血 / buff 到期清理 / 累积条 / 周期被动钩子
func _tick_effects(u: Dictionary, delta: float) -> void:
	# 旧式灼烧 (兼容 burn_until/burn_dps)
	if _t < u["burn_until"] and u["burn_dps"] > 0.0:
		_raw_lose(u, u["burn_dps"] * delta)
		if not u["alive"]:
			return
	# 通用 DoT 列表 (流血/中毒/诅咒/灼烧, raw=真伤穿护盾)
	var keep: Array = []
	for dot in u["dots"]:
		if _t < dot["until"]:
			_raw_lose(u, dot["dps"] * delta)
			if not u["alive"]:
				return
			keep.append(dot)
	u["dots"] = keep
	# buff 到期 → 重算属性
	var changed := false
	var kept_buffs: Array = []
	for b in u["buffs"]:
		if _t < b["until"]:
			kept_buffs.append(b)
		else:
			changed = true
	if changed:
		u["buffs"] = kept_buffs
		_recalc_stats(u)
	# 周期被动 (龟自身计时器在 _per_unit_timers)
	_tick_periodic_passive(u, delta)

func _update_status_dot(u: Dictionary, stunned: bool) -> void:
	if stunned:
		u["dot"].color = Color("#ffe14d")        # 黄=眩晕/冻结/麻痹
	elif _t < u["taunt_until"]:
		u["dot"].color = Color("#ff4dff")        # 紫=被嘲讽
	elif u["dots"].size() > 0 or _t < u["burn_until"]:
		u["dot"].color = Color("#ff7a33")        # 橙=DoT
	elif _t < u["slow_until"]:
		u["dot"].color = Color("#7ad0ff")        # 蓝=减速冰寒
	else:
		u["dot"].color = Color(1, 1, 1, 0)

# 索敌: 被嘲讽则强制打嘲讽来源, 否则最近敌 (跳过 untargetable)
func _acquire_target(u: Dictionary):
	if _t < u["taunt_until"] and u["taunt_by"] != null and u["taunt_by"]["alive"]:
		return u["taunt_by"]
	return _nearest_enemy(u)

func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d := INF
	for o in _units:
		if o["side"] == u["side"] or not o["alive"]:
			continue
		if _t < o["untargetable_until"]:   # 黑洞/缩头随从遮挡 → 不可被选
			continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] != u["side"] and o["alive"]:
			out.append(o)
	return out

func _allies_of(u: Dictionary, include_self: bool = true) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] == u["side"] and o["alive"] and (include_self or o != u):
			out.append(o)
	return out

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

# ---------- 普攻 (各龟 0 能基础技, 见规格) ----------
# 普攻表: id → [scale, hits]  (scale=单段倍率, hits=段数). 没列的用 DEFAULT_BASIC.
# 复杂普攻(财神随金币/骰子随暴击/星际随HP等)在 _basic_attack 内特判.
const BASIC_ATK := {
	"basic": [0.7, 2],     "stone": [0.7, 2],     "bamboo": [0.21, 3],   "angel": [1.4, 3],
	"ice": [0.5, 6],       "ninja": [1.0, 1],     "two_head": [1.0, 1],  "ghost": [0.65, 1],
	"diamond": [0.7, 1],   "fortune": [0.5, 2],   "dice": [0.9, 1],      "rainbow": [0.7, 2],
	"gambler": [0.45, 3],  "hunter": [0.55, 3],   "pirate": [0.35, 4],   "candy": [1.1, 1],
	"bubble": [0.5, 3],    "line": [0.5, 3],      "lightning": [1.15, 5],"phoenix": [0.9, 1],
	"lava": [1.0, 1],      "cyber": [0.15, 5],    "crystal": [0.5, 2],   "chest": [1.5, 3],
	"space": [0.4, 3],     "hiding": [1.0, 1],    "headless": [0.65, 2], "shell": [0.6, 2],
}
const DEFAULT_BASIC := [1.0, 1]

func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	var spec: Array = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	var scale: float = spec[0]
	var hits: int = spec[1]
	# 复杂普攻特判 (基于当前金币/暴击/HP)
	match u["id"]:
		"fortune":  scale = 0.5 + 0.06 * u["gold"]                       # 币越多越疼
		"dice":     scale = 0.9 + u["crit"] * 0.55                       # 暴击率加成
		"space":    scale = 0.4 + 0.06 * (u["hp"] / 100.0)              # 随当前HP (近似)
		"crystal":  pass                                                  # 叠结晶在下面
	var per := _atk_dmg(u, scale, tgt)
	for i in range(hits):
		if not tgt["alive"]:
			break
		if u["melee"]:
			_apply_damage_from(u, tgt, per, Color("#ffe08a"))
			if i == 0:
				_flash(tgt); _melee_lunge(u, tgt)
		else:
			_fire_bolt_from(u, tgt, per, Color("#ffe08a"))
	# 普攻 on-hit 被动钩子 (墨迹/电击/结晶叠层 + 猎杀斩杀 等)
	_on_basic_hit(u, tgt)

func _melee_lunge(u: Dictionary, tgt: Dictionary) -> void:
	var s = u["spr"]
	if not is_instance_valid(s):
		return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() <= 1.0:
		return
	var base: Vector2 = s.position
	var tw := create_tween()
	tw.tween_property(s, "position", base + dir.normalized() * 12.0, 0.06)
	tw.tween_property(s, "position", base, 0.1)

func _fire_bolt(from: Vector2, tgt: Dictionary, dmg: int, col: Color) -> void:
	_fire_bolt_from(null, tgt, dmg, col, from)

# 投射物: 飞到目标再落伤. src 用于 lifesteal/伤害统计/反伤归属 (可 null)
func _fire_bolt_from(src, tgt: Dictionary, dmg: int, col: Color, from = null) -> void:
	var start: Vector2 = from if from != null else (src["pos"] if src != null else tgt["pos"])
	var p := ColorRect.new()
	p.color = col; p.size = Vector2(10, 10); p.position = start - Vector2(5, 5); p.z_index = 8
	add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "position", tgt["pos"] - Vector2(5, 5), 0.14)
	tw.tween_callback(_on_bolt_hit.bind(p, src, tgt, dmg, col))

func _on_bolt_hit(p: ColorRect, src, tgt: Dictionary, dmg: int, col: Color) -> void:
	if is_instance_valid(p):
		p.queue_free()
	if tgt["alive"]:
		if src != null:
			_apply_damage_from(src, tgt, dmg, col)
		else:
			_apply_damage(tgt, dmg, col)
		_flash(tgt)

# ============================================================================
#  主动技注册表 (28 龟 · 各取规格里的「候选1」)  + 默认时长常量
#  完整实装 = ✅ / 简化 = ⚠ / 留 TODO = 🚧, 见每条注释
# ============================================================================
const BUFF_SEC := 5.0      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const CTRL_SEC := 1.5      # 眩晕/冻结/嘲讽 默认秒数

func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	match u["id"]:
		# --- 简单龟: 完整实装 ---
		"basic":     _sk_basic_shield(u, tgt)        # ✅ 龟盾: 伤害+永久护盾+击退
		"stone":     _sk_stone_armor(u)              # ✅ 岩石护甲: 全队永久护盾
		"bamboo":    _sk_bamboo_heal(u)              # ✅ 自然恢复: 自疗+队友护盾
		"angel":     _sk_angel_bless(u)              # ✅ 祝福: 单友永久护盾+甲魔抗buff
		"ice":       _sk_ice_frost(u)                # ✅ 冰霜: 全体削魔抗+魔伤
		"ninja":     _sk_ninja_impact(u, tgt)        # ✅ 冲击: 突进直线+击飞
		"ghost":     _sk_ghost_soulstorm(u, tgt)     # ✅ 灵魂风暴: 魔伤+诅咒DoT
		"diamond":   _sk_diamond_unbreak(u)          # ✅ 坚不可摧: 自护盾+甲魔抗buff
		"dice":      _sk_dice_allin(u)               # ✅ 孤注一掷: 全体物伤+吸血
		"rainbow":   _sk_rainbow_shield(u)           # ✅ 棱镜护盾: 全体友护盾
		"gambler":   _sk_gambler_wild(u, tgt)        # ✅ 万能牌: 伤害+自护盾回血+减益
		"hunter":    _sk_hunter_hide(u)              # ✅ 隐蔽: 伤害+闪避buff+护盾
		"pirate":    _sk_pirate_volley(u)            # ✅ 火炮齐射: 全体六段(不可闪避)
		"bubble":    _sk_bubble_shield(u, tgt)       # ✅ 泡泡盾: 友护盾(到期爆裂)
		"line":      _sk_line_link(u)                # ✅ 连笔: 连两敌+叠墨迹
		"lightning": _sk_lightning_surge(u, tgt)     # ✅ 涌动: 电击增伤buff+真伤
		"phoenix":   _sk_phoenix_lavashield(u)       # ✅ 熔岩盾: 护盾+受击反击
		"headless":  _sk_headless_fear(u, tgt)       # ✅ 恐吓: 伤害+恐惧减伤debuff
		"fortune":   _sk_fortune_dice(u)             # ✅ 骰子: 加金币+回血
		# --- 控制/治疗/AoE 简单龟 ---
		"crystal":   _sk_crystal_bulwark(u)          # ✅ 水晶壁垒: 自护盾+全友甲魔抗buff
		"chest":     _sk_chest_inventory(u)          # ✅ 清点财宝: 自疗+护盾
		"space":     _sk_space_meteor(u)             # ✅ 流星暴击: 全体魔伤+削魔抗(+星能)
		# --- 召唤/变身龟: 简化版 (见注释) ---
		"two_head":  _sk_two_head(u, tgt)            # ⚠ 双头: 切形态+当前形态招(简化为锤击/魔法波交替)
		"lava":      _sk_lava_small(u)               # ⚠ 熔岩: 小形态地裂(变身被动在 tick)
		"cyber":     _sk_cyber_cannon(u, tgt)        # ⚠ 赛博: 能量大炮(浮游炮被动在 tick)
		"candy":     _sk_candy_armor(u)              # ✅ 焦糖铠: 自护盾+回血 (糖果罐/炸弹召唤留TODO)
		"hiding":    _sk_hiding_defend(u)            # ⚠ 缩头: 防御自护盾 (随从召唤被动在 spawn)
		"shell":     _sk_shell_absorb(u, tgt)        # ⚠ 龟壳: 吸收偷HP (觉醒/储能被动在 tick)
		_:           _sk_burst(u, tgt)               # 兜底重击

# ---------------------------------------------------------------------------
# 各龟主动技实装
# ---------------------------------------------------------------------------
func _sk_basic_shield(u: Dictionary, tgt: Dictionary) -> void:   # 小龟·龟盾 ✅
	_float_text(u["pos"] + Vector2(0, -64), "龟盾!", Color("#ffd93d"))
	var lost: float = (tgt["maxHp"] - tgt["hp"]) * 0.20
	var raw: float = u["atk"] * 0.7
	var dmg := _atk_dmg(u, 0.7, tgt) + int(lost)
	_apply_damage_from(u, tgt, dmg, Color("#ffe08a"))
	_grant_shield(u, (raw + lost) * 0.80)            # 80% 伤害值永久护盾
	_knockback(u, tgt, 60.0)

func _sk_stone_armor(u: Dictionary) -> void:                     # 石头龟·岩石护甲 ✅
	_float_text(u["pos"] + Vector2(0, -64), "岩石护甲!", Color("#c9a36b"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.24 + o["maxHp"] * 0.05)

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies := _allies_of(u, false)
	if allies.is_empty():
		_heal(u, u["maxHp"] * 0.15)
	else:
		_heal(u, u["maxHp"] * 0.10)
		for o in allies:
			_grant_shield(o, o["maxHp"] * 0.12)
	_float_text(u["pos"] + Vector2(0, -64), "自然恢复!", Color("#39d353"))

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_grant_shield(ally, u["atk"] * 1.2)
	_buff(ally, "def", 0.2, true)                    # +20% 护甲 N秒
	_buff(ally, "mr", 0.2, true)
	_float_text(ally["pos"] + Vector2(0, -64), "祝福!", Color("#ffe9a8"))

func _sk_ice_frost(u: Dictionary) -> void:                       # 寒冰龟·冰霜 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冰霜!", Color("#9be7ff"))
	for o in _enemies_of(u):
		_buff(o, "mr", -0.25, true)                  # -25% 魔抗 N秒
		for i in range(10):
			_apply_damage_from(u, o, _atk_dmg(u, 0.1, o, true), Color("#bfe9ff"))
		_skill_ring(o["pos"], Color(0.6, 0.9, 1.0, 0.5), 50.0)

func _sk_ninja_impact(u: Dictionary, tgt: Dictionary) -> void:   # 忍者龟·冲击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冲击!", Color("#9be7ff"))
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	_dash_to(u, tgt, 60.0)
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ff9d5c"))
	_knockback(u, tgt, 50.0)                          # 击飞
	# 沿冲锋方向身后一线敌 0.8ATK
	for o in _enemies_of(u):
		if o == tgt:
			continue
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#ff9d5c"))

func _sk_ghost_soulstorm(u: Dictionary, tgt: Dictionary) -> void: # 幽灵龟·灵魂风暴 ✅
	_float_text(u["pos"] + Vector2(0, -64), "灵魂风暴!", Color("#c77dff"))
	var cursed: bool = _has_dot(tgt, "curse")
	if cursed:
		_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt, true), Color("#e0b0ff"))  # 真伤
	else:
		for i in range(2):
			_apply_damage_from(u, tgt, _atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))
		_add_dot(tgt, "curse", tgt["maxHp"] * 0.05, BUFF_SEC)   # 每秒5%最大HP真伤

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧 ✅
	_float_text(u["pos"] + Vector2(0, -64), "坚不可摧!", Color("#9bdcff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true); _buff(u, "mr", 0.2, true)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷 ✅
	_float_text(u["pos"] + Vector2(0, -64), "孤注一掷!", Color("#ffd93d"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o), Color("#ffe08a"), 0.30)  # 30% 吸血

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	_float_text(u["pos"] + Vector2(0, -64), "棱镜护盾!", Color("#ff8ad8"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.65)

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌 ✅
	_float_text(u["pos"] + Vector2(0, -64), "万能牌!", Color("#ffd93d"))
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ffe08a"))
	_grant_shield(u, u["atk"] * 0.25)
	_heal(u, u["maxHp"] * 0.05)
	_buff(tgt, "atk", -0.15, true)                   # 随机减益(简化为减攻)

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽 ✅
	_float_text(u["pos"] + Vector2(0, -64), "隐蔽!", Color("#a8ffb0"))
	var tgt = _nearest_enemy(u)
	if tgt != null:
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(u, "dodge", 0.25, true)
	_grant_shield(u, u["atk"] * 0.6)

func _sk_pirate_volley(u: Dictionary) -> void:                   # 海盗龟·火炮齐射 ✅
	_float_text(u["pos"] + Vector2(0, -64), "火炮齐射!", Color("#ffb05c"))
	for o in _enemies_of(u):
		for i in range(6):
			_apply_damage_from(u, o, _atk_dmg(u, 0.17, o) + int(o["maxHp"] * 0.017), Color("#ffd07a"))

func _sk_bubble_shield(u: Dictionary, tgt: Dictionary) -> void:  # 泡泡龟·泡泡盾 ✅(简化:无延迟爆裂)
	var ally = _lowest_hp_ally(u)
	if ally == null: ally = u
	_grant_shield(ally, u["atk"] * 1.8)
	_float_text(ally["pos"] + Vector2(0, -64), "泡泡盾!", Color("#aef1ff"))
	# ⚠ 简化: 立即对全体敌一次爆裂魔伤 (规格是护盾到期才爆, 留 TODO)
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 2.0, o, true), Color("#cdebff"))

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅
	_float_text(u["pos"] + Vector2(0, -64), "连笔!", Color("#cccccc"))
	var picked := 0
	for o in _enemies_of(u):
		if picked >= 2: break
		_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#dddddd"))
		_add_stack(o, "ink", 1, 5)
		picked += 1

func _sk_lightning_surge(u: Dictionary, tgt: Dictionary) -> void: # 闪电龟·涌动 ✅
	_float_text(u["pos"] + Vector2(0, -64), "涌动!", Color("#7ee8ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.23, tgt, true), Color("#bff0ff"))
	_add_stack(tgt, "electric", 2, 6)
	_buff(u, "atk", 0.5, true)                       # 简化: 增伤buff代表电击+50%

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 ✅(反击留TODO)
	_float_text(u["pos"] + Vector2(0, -64), "熔岩盾!", Color("#ff7a33"))
	_grant_shield(u, u["atk"] * 0.75)
	# 🚧 TODO: 护盾期受击反击 0.14ATK 魔 (需受伤钩子里查 phoenix shield 标记)

func _sk_headless_fear(u: Dictionary, tgt: Dictionary) -> void:  # 无头龟·恐吓 ✅
	_float_text(u["pos"] + Vector2(0, -64), "恐吓!", Color("#a0a0ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(tgt, "atk", -0.20, true)                   # 恐惧: 对所有伤害-20% (简化为减攻)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子 ✅
	_float_text(u["pos"] + Vector2(0, -64), "骰子+金币!", Color("#ffd93d"))
	u["gold"] += randi_range(2, 6)
	_heal(u, u["maxHp"] * 0.08)

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒 ✅
	_float_text(u["pos"] + Vector2(0, -64), "水晶壁垒!", Color("#c0a8ff"))
	_grant_shield(u, u["atk"] * 0.9)
	for o in _allies_of(u):
		_buff(o, "def", 0.15, true); _buff(o, "mr", 0.15, true)

func _sk_chest_inventory(u: Dictionary) -> void:                 # 宝箱龟·清点财宝 ✅
	_float_text(u["pos"] + Vector2(0, -64), "清点财宝!", Color("#ffcf5c"))
	_heal(u, u["maxHp"] * 0.05)
	var bonus: float = 1.0 + minf(u["dmg_dealt"] / 2000.0, 1.0)   # 随财宝值(累计伤害)强化
	_grant_shield(u, u["atk"] * 0.6 * bonus)

func _sk_space_meteor(u: Dictionary) -> void:                    # 星际龟·流星暴击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "流星暴击!", Color("#b08cff"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#c9b0ff"))
		_buff(o, "mr", -0.2, true)
	# 星能满 → 消耗全部, 对全体敌 +100% 星能真伤
	if u["star_energy"] >= u["maxHp"] * 0.40:
		var burst: float = u["star_energy"]
		u["star_energy"] = 0.0
		for o in _enemies_of(u):
			_raw_lose(o, burst)
			_float_text(o["pos"] + Vector2(0, -48), str(int(burst)), Color("#ffd0ff"))

func _sk_candy_armor(u: Dictionary) -> void:                     # 糖果龟·焦糖铠 ✅
	_float_text(u["pos"] + Vector2(0, -64), "焦糖铠!", Color("#ffb0d0"))
	_grant_shield(u, u["atk"] * 0.8)
	_heal(u, u["maxHp"] * 0.10)

# --- 变身/召唤龟 简化版 ---
func _sk_two_head(u: Dictionary, tgt: Dictionary) -> void:       # 双头龟 ⚠ 简化
	# ⚠ 简化: 每次攒满龟能切形态(标记 form), 近战=锤击+永久护盾 / 远程=魔法波四段
	u["two_form"] = "ranged" if u.get("two_form", "melee") == "melee" else "melee"
	if u["two_form"] == "melee":
		u["melee"] = true; u["atk_range"] = 70.0
		_float_text(u["pos"] + Vector2(0, -64), "近战·锤击!", Color("#ffb05c"))
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt), Color("#ffb05c"))
		_grant_shield(u, u["atk"] * 0.5)
	else:
		u["melee"] = false; u["atk_range"] = 300.0
		_float_text(u["pos"] + Vector2(0, -64), "远程·魔法波!", Color("#b0c0ff"))
		for i in range(4):
			_apply_damage_from(u, tgt, _atk_dmg(u, 0.6, tgt, true), Color("#c0d0ff"))

func _sk_lava_small(u: Dictionary) -> void:                      # 熔岩龟·小形态地裂 ⚠
	# ⚠ 小形态招完整; 火山变身在 _tick_periodic_passive(怒气满→属性强化+AoE)
	_float_text(u["pos"] + Vector2(0, -64), "地裂!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.7, o, true), Color("#ff9d5c"))
		_buff(o, "mr", -0.2, true)

func _sk_cyber_cannon(u: Dictionary, tgt: Dictionary) -> void:   # 赛博龟·能量大炮 ⚠
	# ⚠ 浮游炮被动召唤在 _tick_periodic_passive; 这里 = 跃至目标直线轰激光
	_float_text(u["pos"] + Vector2(0, -64), "能量大炮!", Color("#7ee8ff"))
	_dash_to(u, tgt, 80.0)
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#9bf0ff"))
	# 按浮游炮数追加真伤
	var drones: int = u["summons"].size()
	if drones > 0:
		_apply_damage_from(u, tgt, int(u["atk"] * 0.2 * drones), Color("#d0ffff"), 0.0, true)

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御 ⚠
	# ⚠ 随从召唤在 spawn 被动; 这里 = 自护盾 (到期转HP留TODO)
	_float_text(u["pos"] + Vector2(0, -64), "防御!", Color("#9be7ff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true)

func _sk_shell_absorb(u: Dictionary, tgt: Dictionary) -> void:   # 龟壳·吸收 ⚠
	# ⚠ 觉醒/储能被动在 tick; 这里 = 偷目标 10% 最大HP 转给自身
	var steal: float = tgt["maxHp"] * 0.10
	_raw_lose(tgt, steal)
	_heal(u, steal)
	_float_text(u["pos"] + Vector2(0, -64), "吸收!", Color("#b0ffd0"))

func _sk_burst(u: Dictionary, tgt: Dictionary) -> void:          # 兜底重击
	_float_text(u["pos"] + Vector2(0, -64), "重击!", Color("#ff9d5c"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt), Color("#ff9d5c"))
	for o in _enemies_of(u):
		if o != tgt and (o["pos"] - tgt["pos"]).length() <= 110.0:
			_apply_damage_from(u, o, _atk_dmg(u, 1.25, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"], Color(1.0, 0.6, 0.3, 0.5), 110.0)

# ============================================================================
#  效果积木 (可复用) — 治疗/护盾/控制/buff/DoT/位移/吸血/累积/净化/叠层
# ============================================================================

# 攻击伤害值: scale×ATK, 走护甲/魔抗减伤; magic=true 走魔抗. (含暴击)
func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool = false) -> int:
	var base: float = u["atk"] * scale
	# 暴击
	if randf() < u["crit"]:
		base *= u["crit_dmg"]
	var resist: float = float(tgt["mr"]) if magic else float(tgt["def"])
	resist = maxf(0.0, resist - u["pierce"])         # 穿透
	return maxi(1, int(round(base * (100.0 / (100.0 + resist)))))

# 永久护盾 (打光为止)
func _grant_shield(u: Dictionary, amt: float) -> void:
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)
	_update_bars(u)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)

# 治疗
func _heal(u: Dictionary, amt: float) -> void:
	if amt <= 0.0: return
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	_update_bars(u)
	_float_text(u["pos"] + Vector2(0, -40), "+" + str(int(amt)), Color("#39d353"))

# 冻结/眩晕/麻痹 (定身 N 秒)
func _freeze(u: Dictionary, sec: float = CTRL_SEC) -> void:
	u["stun_until"] = maxf(u["stun_until"], _t + sec)
	_skill_ring(u["pos"], Color(0.6, 0.9, 1.0, 0.6), 48.0)

# 嘲讽 (强制 targets 索敌 by, N 秒)
func _taunt(by: Dictionary, targets: Array, sec: float = BUFF_SEC) -> void:
	for o in targets:
		o["taunt_until"] = _t + sec
		o["taunt_by"] = by

# 临时属性 buff. stat ∈ atk/def/mr/crit/dodge/lifesteal. pct=true 为百分比加成.
func _buff(u: Dictionary, stat: String, amount: float, pct: bool, sec: float = BUFF_SEC) -> void:
	u["buffs"].append({"stat": stat, "amount": amount, "pct": pct, "until": _t + sec})
	_recalc_stats(u)

# 重算属性 = base × (1+Σpct) + Σflat (含 buff)
func _recalc_stats(u: Dictionary) -> void:
	var acc := {"atk": [0.0, 0.0], "def": [0.0, 0.0], "mr": [0.0, 0.0]}   # [pctSum, flatSum]
	var dodge := 0.0
	var ls := 0.0
	for b in u["buffs"]:
		var s: String = b["stat"]
		if s == "dodge":
			dodge += b["amount"]; continue
		if s == "lifesteal":
			ls += b["amount"]; continue
		if not acc.has(s):
			continue
		if b["pct"]:
			acc[s][0] += b["amount"]
		else:
			acc[s][1] += b["amount"]
	u["atk"] = maxf(0.0, u["base_atk"] * (1.0 + acc["atk"][0]) + acc["atk"][1])
	u["def"] = maxf(0.0, u["base_def"] * (1.0 + acc["def"][0]) + acc["def"][1])
	u["mr"]  = maxf(0.0, u["base_mr"]  * (1.0 + acc["mr"][0])  + acc["mr"][1])
	u["dodge_bonus"] = dodge
	u["ls_bonus"] = ls

# 击退 (远离施法者) / 拉近 (towards). dist<0 = 拉近
func _knockback(by: Dictionary, tgt: Dictionary, dist: float) -> void:
	if tgt.get("_knock_immune", false): return
	var dir: Vector2 = (tgt["pos"] - by["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	tgt["pos"] += dir * dist
	tgt["pos"].x = clampf(tgt["pos"].x, ARENA.position.x, ARENA.end.x)
	tgt["pos"].y = clampf(tgt["pos"].y, ARENA.position.y, ARENA.end.y)
	tgt["node"].position = tgt["pos"]

func _pull(by: Dictionary, tgt: Dictionary, to_dist: float) -> void:
	# 把 tgt 拉到 by 面前 to_dist 处
	var dir: Vector2 = (tgt["pos"] - by["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	tgt["pos"] = by["pos"] + dir * to_dist
	tgt["pos"].x = clampf(tgt["pos"].x, ARENA.position.x, ARENA.end.x)
	tgt["pos"].y = clampf(tgt["pos"].y, ARENA.position.y, ARENA.end.y)
	tgt["node"].position = tgt["pos"]

# 突进: 把 u 瞬移到 tgt 旁 gap 处 (近战切入)
func _dash_to(u: Dictionary, tgt: Dictionary, gap: float) -> void:
	var dir: Vector2 = (u["pos"] - tgt["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	u["pos"] = tgt["pos"] + dir * gap
	u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
	u["node"].position = u["pos"]

# 通用 DoT (流血/中毒/诅咒/灼烧). dps = 每秒落血, raw=真伤穿护盾(默认真)
func _add_dot(u: Dictionary, tag: String, dps: float, sec: float) -> void:
	u["dots"].append({"tag": tag, "dps": dps, "until": _t + sec})

func _has_dot(u: Dictionary, tag: String) -> bool:
	for d in u["dots"]:
		if d["tag"] == tag and _t < d["until"]:
			return true
	return false

# 净化: 清除目标所有减益 (DoT/减攻buff/减速)
func _cleanse(u: Dictionary) -> int:
	var n: int = u["dots"].size()
	u["dots"] = []
	var kept: Array = []
	for b in u["buffs"]:
		if b["amount"] < 0.0:    # 负向 = 减益
			n += 1
		else:
			kept.append(b)
	u["buffs"] = kept
	u["slow_until"] = 0.0
	_recalc_stats(u)
	return n

# 叠层标记 (电击/结晶/墨迹). 满 cap → 由调用方引爆. 返回当前层数.
func _add_stack(u: Dictionary, tag: String, n: int, cap: int) -> int:
	var cur: int = u["stacks"].get(tag, 0) + n
	cur = mini(cur, cap)
	u["stacks"][tag] = cur
	return cur

func _consume_stacks(u: Dictionary, tag: String) -> int:
	var c: int = u["stacks"].get(tag, 0)
	u["stacks"][tag] = 0
	return c

# 直线判定: p 是否在 origin 出发 dir 方向的一条宽 width 直线带上 (前方)
func _on_line(origin: Vector2, dir: Vector2, p: Vector2, width: float) -> bool:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(dir)
	if along < 0.0: return false                     # 在身后
	var perp: float = (rel - dir * along).length()
	return perp <= width

func _lowest_hp_ally(u: Dictionary):
	var best = null; var bv := INF
	for o in _allies_of(u):
		if o["hp"] < bv:
			bv = o["hp"]; best = o
	return best

# ---------- 伤害 / 状态 ----------
# (伤害计算见 _atk_dmg: scale×ATK + 暴击 + 穿透 + 物/法分流减伤)

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

# 来源已知的伤害: 处理 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动
# extra_ls = 本次技能额外吸血%; raw=真伤(穿护盾)
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false) -> void:
	# 闪避 (目标 dodge_bonus)
	if u.get("dodge_bonus", 0.0) > 0.0 and randf() < u["dodge_bonus"]:
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#cfe6ff"))
		return
	var d := float(dmg)
	if not raw and u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	_update_bars(u)
	_float_text(u["pos"] + Vector2(0, -40), str(dmg), col)
	# 来源累积 ----
	src["dmg_dealt"] += float(dmg)
	# 吸血 (lifesteal 基础 + buff + 技能 extra)
	var ls: float = src.get("lifesteal", 0.0) + src.get("ls_bonus", 0.0) + extra_ls
	if ls > 0.0 and src["alive"]:
		_heal(src, float(dmg) * ls)
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava":
		src["rage"] = minf(RAGE_MAX, src["rage"] + float(dmg) * 0.25)
	if u["id"] == "lava":
		u["rage"] = minf(RAGE_MAX, u["rage"] + float(dmg) * 0.20)
	# 星能 (星际造伤62%)
	if src["id"] == "space":
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.62)
	# 储能 (龟壳受伤转储能, 上限50%最大HP)
	if u["id"] == "shell":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
	# 石头龟坚壁: 受伤反弹 (5%+1%DEF+0.5%MR)
	if u["id"] == "stone" and src["alive"] and src["side"] != u["side"]:
		var reflect: float = float(dmg) * 0.05 + u["def"] * 0.01 + u["mr"] * 0.005
		if reflect >= 1.0:
			_raw_lose(src, reflect)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u, src)

func _raw_lose(u: Dictionary, amt: float) -> void:
	# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], amt)
		u["shield"] -= ab; amt -= ab
	u["hp"] = maxf(0.0, u["hp"] - amt)
	_update_bars(u)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

func _kill(u: Dictionary, killer = null) -> void:
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为被动选项时生效, 简化为常驻一次
	if not u["reborn_used"] and (u["id"] == "angel" or u["id"] == "phoenix"):
		u["reborn_used"] = true
		var pct: float = 0.30 if u["id"] == "phoenix" else 0.25
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		_update_bars(u)
		_float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧
			for o in _enemies_of(u):
				_add_dot(o, "burn", o["maxHp"] * 0.02, BUFF_SEC)
		return
	u["alive"] = false
	_on_unit_death(u, killer)
	var n: Node2D = u["node"]
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.4)
	tw.tween_callback(n.hide)

# 死亡钩子: 猎人窃取 / 幽灵死亡诅咒 / 财神死亡给币 / 海盗钩锁 等
func _on_unit_death(u: Dictionary, killer) -> void:
	# 财神聚宝盆: 任意单位死亡给所有存活财神金币
	for o in _units:
		if o["alive"] and o["id"] == "fortune" and o["side"] != u["side"]:
			o["gold"] += 2
	# 猎人猎杀: 击杀者是猎人 → 窃取属性+叠吸血
	if killer != null and killer["alive"] and killer["id"] == "hunter":
		killer["base_atk"] += u["base_atk"] * 0.14
		killer["lifesteal"] += 0.08
		_recalc_stats(killer)
		_float_text(killer["pos"] + Vector2(0, -64), "猎杀!", Color("#a8ffb0"))
	# 幽灵强化怨灵: 死亡时再诅咒全体敌一次
	if u["id"] == "ghost":
		for o in _enemies_of(u):
			_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
	# 海盗掠夺: 死亡钩锁击杀者 25% 最大HP 真伤
	if u["id"] == "pirate" and killer != null and killer["alive"]:
		_raw_lose(killer, killer["maxHp"] * 0.25)

func _update_bars(u: Dictionary) -> void:
	if not is_instance_valid(u["hp_fill"]):
		return
	if u.get("is_summon", false):
		# 召唤体只有血条 (宽 28), 不画护盾/龟能
		u["hp_fill"].size.x = 28.0 * clampf(u["hp"] / u["maxHp"], 0.0, 1.0)
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

# ============================================================================
#  被动系统: 登场被动 / on-hit / 周期被动 / 召唤
# ============================================================================

# 本龟当前选的是被动 (4选1选了 [被] 项) → 不涨龟能/不放主动. 简化: 默认全选主动.
# 召唤体也走这里 (永远主动平A, 不放技能).
func _is_passive_pick(u: Dictionary) -> bool:
	return u.get("is_summon", false)

# 登场被动 (开战即生效)
func _apply_spawn_passives() -> void:
	for u in _units.duplicate():
		match u["id"]:
			"ninja":                                   # 忍术+忍者足: 开局暴击/暴伤/穿透/闪避
				u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["pierce"] += 8.0
				_buff(u, "dodge", 0.25, false, 9999.0)  # dodge 经 _recalc_stats → dodge_bonus
			"ghost":                                   # 怨灵: 开战诅咒全体敌
				for o in _enemies_of(u):
					_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
			"ice":                                     # 冰寒: 开战全体敌减攻+减速
				for o in _enemies_of(u):
					_buff(o, "atk", -0.20, true, BUFF_SEC * 1.5)
					o["slow_until"] = _t + BUFF_SEC * 1.5
			"headless":                                # 亡灵: 登场22%吸血
				u["lifesteal"] += 0.22
			"dice":                                    # 真正的赌徒: 甲魔抗转穿透
				u["pierce"] += u["def"] + u["mr"]
				u["base_def"] = 0.0; u["base_mr"] = 0.0; _recalc_stats(u)
			"pirate":                                  # 掠夺: 开局轰随机敌25%最大HP真伤
				var es := _enemies_of(u)
				if not es.is_empty():
					var v = es[randi() % es.size()]
					_raw_lose(v, v["maxHp"] * 0.25)
			"candy":                                   # 甜蜜掠夺: 开战偷随机敌25%最大HP(留1HP)
				var ce := _enemies_of(u)
				if not ce.is_empty():
					var v = ce[randi() % ce.size()]
					var steal: float = minf(v["maxHp"] * 0.25, v["hp"] - 1.0)
					if steal > 0: _raw_lose(v, steal); _heal(u, steal)
			"hiding":                                  # 喊龟: 召唤一只随从 (独立单位)
				_spawn_summon(u, "minion", u["maxHp"] * 0.40, u["atk"] * 0.8)

# 普攻命中 on-hit 被动 (墨迹/电击/结晶叠层引爆 + 猎杀斩杀 + 财宝值)
func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":                                        # 墨迹: 每笔叠1层 (上限5)
			_add_stack(tgt, "ink", 1, 5)
		"lightning":                                   # 雷电: 叠电击, 满8引爆雷暴
			var lv := _add_stack(tgt, "electric", 1, 8)
			if lv >= 8:
				_consume_stacks(tgt, "electric")
				_apply_damage_from(u, tgt, int(u["atk"] * 0.82), Color("#bff0ff"), 0.0, true)
		"crystal":                                     # 水晶共鸣: 叠结晶, 满4引爆
			var cv := _add_stack(tgt, "crystal", 1, 4)
			if cv >= 4:
				_consume_stacks(tgt, "crystal")
				_apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
				_buff(tgt, "mr", -0.2, true)
	# 猎人猎杀: 攻击后斩杀<14%HP敌 (_raw_lose 到0会自行 _kill, 但不带killer →
	# 这里先标记 killer 让死亡钩子能拿到; _raw_lose 内部 _kill 无 killer, 猎杀窃取改在此处直接做)
	if u["id"] == "hunter" and tgt["alive"] and tgt["hp"] < tgt["maxHp"] * 0.14:
		_float_text(tgt["pos"] + Vector2(0, -56), "斩杀!", Color("#ff6b6b"))
		var was_alive: bool = tgt["alive"]
		tgt["hp"] = 0.0
		_update_bars(tgt)
		if was_alive:
			_kill(tgt, u)
	# 无头亡灵: 每损1%HP攻击+1%(上限+100%) — 每次受伤后重算, 这里近似在攻击时刷新
	if u["id"] == "headless":
		var lost_pct: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["atk"] = u["base_atk"] * (1.0 + lost_pct)

# 周期被动 (每帧累加计时器, 到周期触发一次)
func _tick_periodic_passive(u: Dictionary, delta: float) -> void:
	u["_ptimer"] = u.get("_ptimer", 0.0) + delta
	# --- 熔岩变身: 怒气满100 → 变火山N秒 (属性强化+登场AoE) ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		u["rage"] = 0.0
		u["volcano"] = true
		u["volcano_until"] = _t + 6.0
		_buff(u, "atk", 0.6, true, 6.0); _buff(u, "def", 0.4, true, 6.0); _buff(u, "mr", 0.4, true, 6.0)
		u["maxHp"] *= 1.3; u["hp"] *= 1.3
		_float_text(u["pos"] + Vector2(0, -70), "变身·火山龟!", Color("#ff5a2a"))
		for o in _enemies_of(u):                        # 变身瞬间 AoE 魔伤+灼烧
			_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#ff7a33"))
			_add_dot(o, "burn", o["maxHp"] * 0.02, BUFF_SEC)
			_heal(u, (o["maxHp"] - o["hp"]) * 0.08)
	if u.get("volcano", false) and _t >= u["volcano_until"]:
		u["volcano"] = false
		u["maxHp"] /= 1.3; u["hp"] = minf(u["hp"], u["maxHp"])
	# --- 赛博浮游炮: 每周期生成1 (上限10) ---
	if u["id"] == "cyber":
		if u["_ptimer"] >= 3.0:
			u["_ptimer"] = 0.0
			if u["summons"].size() < 10:
				var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25)
				if dr != null: u["summons"].append(dr)
	# --- 石头坚壁: 每秒+护甲 (上限100%开局护甲) ---
	elif u["id"] == "stone":
		if u["_ptimer"] >= STACK_DOT_TICK:
			u["_ptimer"] = 0.0
			if u["def"] < u["base_def"] * 2.0:
				u["base_def"] += u["base_def"] * 0.02; _recalc_stats(u)
	# --- 竹叶生长: 每N秒充能 → 永久+ATK/HP ---
	elif u["id"] == "bamboo":
		if u["_ptimer"] >= 4.0:
			u["_ptimer"] = 0.0
			u["base_atk"] *= 1.06; u["maxHp"] *= 1.04; u["hp"] += u["maxHp"] * 0.08
			_recalc_stats(u)
	# --- 星际星能: 流星暴击时已处理; 这里无周期 ---
	# --- 龟壳气场觉醒: 开战~10秒触发一次属性强化 ---
	elif u["id"] == "shell":
		if not u.get("awakened", false) and _t >= 10.0:
			u["awakened"] = true
			_buff(u, "atk", 0.12, true, 9999.0); _buff(u, "def", 0.12, true, 9999.0); _buff(u, "mr", 0.12, true, 9999.0)
			u["crit"] += 0.25; _recalc_stats(u)
			_float_text(u["pos"] + Vector2(0, -70), "气场觉醒!", Color("#b0ffe0"))
	# --- 财神聚宝盆: 每秒+2金币 ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 1.0:
			u["_goldtimer"] = 0.0; u["gold"] += 2

# 召唤独立单位 (浮游炮/随从/海盗船) — 简化版战斗体, 走同一 tick
func _spawn_summon(owner: Dictionary, kind: String, hp: float, atk: float):
	var pos: Vector2 = owner["pos"] + Vector2(randf_range(-40, 40), randf_range(30, 60))
	pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)
	pos.y = clampf(pos.y, ARENA.position.y, ARENA.end.y)
	var col := Color("#3fa9ff") if owner["side"] == "left" else Color("#ff5a5a")
	var node := Node2D.new(); node.position = pos; add_child(node)
	var c := ColorRect.new()
	c.color = Color(col.r, col.g, col.b, 0.8); c.size = Vector2(22, 22); c.position = Vector2(-11, -11)
	node.add_child(c)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#39d353"); hp_fill.position = Vector2(-14, -20); hp_fill.size = Vector2(28, 4)
	node.add_child(hp_fill)
	var dot := ColorRect.new(); dot.color = Color(1,1,1,0); node.add_child(dot)
	var su := {
		"id": "_summon_" + kind, "name": kind, "rarity": "C", "side": owner["side"],
		"pos": pos, "vel": Vector2.ZERO, "hp": hp, "maxHp": hp,
		"atk": atk, "def": 0.0, "mr": 0.0, "base_atk": atk, "base_def": 0.0, "base_mr": 0.0,
		"crit": 0.0, "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
		"melee": kind != "drone", "move_spd": 120.0, "atk_interval": 1.2,
		"atk_range": 280.0 if kind == "drone" else 70.0,
		"atk_cd": 0.0, "energy": 0.0, "alive": true, "is_summon": true,
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0,
		"buffs": [], "dots": [], "taunt_until": 0.0, "taunt_by": null, "slow_until": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0, "summons": [],
		"node": node, "spr": c, "hp_fill": hp_fill,
		"shield_fill": hp_fill, "en_fill": hp_fill, "dot": dot,
	}
	_units.append(su)
	return su

func _check_end() -> void:
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"] and not u.get("is_summon", false):    # 召唤体不计入胜负判定
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
