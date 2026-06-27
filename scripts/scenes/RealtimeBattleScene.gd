extends Node2D
## RealtimeBattleScene — 斗龟场实时版 · 实时战斗原型 (阶段0+1 + 阶段2/3雏形)
## 2D 俯视自由走位 3v3: 近战追最近敌 / 远程保持射程风筝 · 按攻速自动普攻 ·
## 龟能随时间回满→放各自的主动技 · 灭对方全队=胜.
## 时间制状态系统(按秒): 护盾吸收 / 灼烧DoT / 麻痹眩晕 —— 验证"回合→秒"改造.
## 全新自含, 不碰回合制 BattleScene. 复用 data/pets.json 数据 + avatars 精灵.
## ⚠ 所有数值是 #7 草案起步值 + 简化伤害公式, 全待 F5 调手感.

const Backend := preload("res://scripts/engine/backend.gd")
const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 x,y,w,h
const MAX_ENERGY := 100.0
const REGEN_PER_SEC := 14.0                # 龟能每秒回 (≈7s 满)
const SEP_RADIUS := 48.0                   # 单位软分离半径
const SHIELD_CAP_MULT := 1.5               # 护盾上限 = maxHp ×
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类 DoT 每秒结算一次
const KNOCK_DUR := 0.22                     # 击飞滑行时长(秒) — 2D伪3D: 不瞬移而是滑行
const KNOCK_HOP := 14.0                     # 击飞假抬升高度(px) — 立绘视觉抬起再落回(俯视假"飞起来")
const HP_MULT := 3.0                       # 战斗节奏旋钮: 攻速校准后整体DPS↑~20%, 提到3.0维持一局~20-22s(贴Botworld实测20-30s); 待F5微调

# 全 28 龟战斗属性 (28龟角色映射草案 #7 档位): id → [melee, move_spd, atk_interval(s), atk_range]
# 攻速档按 Botworld 真数据校准(2026-06-27): 旧 0.65/1.0/1.5 → 0.6/0.85/1.1
# Botworld 实测攻速 0.5(追击)~1.08(闪避), 多数0.8-0.9, 坦克仅0.8 → 旧1.5s慢攻速严重超标已修
const STATS := {
	"basic": [true, 105.0, 0.85, 70.0], "stone": [true, 70.0, 1.1, 70.0], "bamboo": [true, 105.0, 0.85, 70.0],
	"angel": [false, 105.0, 0.85, 230.0], "ice": [false, 105.0, 0.85, 230.0], "ninja": [true, 145.0, 0.6, 70.0],
	"two_head": [true, 145.0, 0.85, 70.0], "ghost": [false, 145.0, 0.6, 340.0], "diamond": [true, 70.0, 1.1, 70.0],
	"fortune": [true, 105.0, 0.85, 70.0], "dice": [false, 145.0, 0.6, 230.0], "rainbow": [true, 105.0, 0.85, 70.0],
	"gambler": [false, 145.0, 0.85, 230.0], "hunter": [false, 145.0, 0.6, 340.0], "pirate": [false, 105.0, 0.85, 230.0],
	"candy": [false, 105.0, 0.85, 230.0], "bubble": [false, 70.0, 1.1, 230.0], "line": [false, 145.0, 0.6, 340.0],
	"lightning": [false, 145.0, 0.6, 340.0], "phoenix": [false, 105.0, 0.85, 230.0], "lava": [true, 145.0, 0.85, 70.0],
	"cyber": [false, 105.0, 0.85, 230.0], "crystal": [true, 70.0, 1.1, 70.0], "chest": [true, 105.0, 1.1, 70.0],
	"space": [false, 145.0, 0.85, 340.0], "hiding": [true, 70.0, 1.1, 70.0], "headless": [true, 145.0, 0.85, 70.0],
	"shell": [true, 105.0, 1.1, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 0.85, 70.0]
# demo 兜底阵容 (id 列表, 属性查 STATS) — 没配队时用
const LEFT_DEMO := ["stone", "basic", "lightning"]
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

var _units: Array = []
var _data_by_id: Dictionary = {}
var _over := false
var _t := 0.0   # 战斗经过秒数 (时间制基准, 取代回合计数)
var _settled := false                       # 结果只喂赛季一次的守卫 (防 _check_end 重复触发)
var _last_reward := 0                        # 本局给的深海币 (结算浮层显示用)
var _last_was_exhibition := false            # 本局是否表演赛 (进场前已0命; 不喂命/计战/上榜)
var _had_season := false                     # 本局是否有赛季态 (玩家配了 season_leaders); demo 跑时 false → 不喂只显横幅

func _ready() -> void:
	_load_pets()
	_build_arena()
	_spawn_teams()
	_inject_equipment()         # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备)
	_apply_spawn_passives()
	_eq_apply_all_stats()        # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)

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
		# 层数式 DoT (灼烧/中毒/流血, 1:1 回合制 dot.gd 层数衰减模型) ----
		"dot_stacks": {},            # {burn:N, poison:N, bleed:N} 层数, 每秒出伤后衰减
		"_dottimer": 0.0,            # 层数 DoT 结算计时 (满 STACK_DOT_TICK 结算一次)
		"dot_src": {},               # {burn:src, poison:src, bleed:src} 各类最近施加者 (供归功; 可 null)
		"true_fire_until": 0.0,      # 余烬燃油瓶022「真火」: <until 时灼烧转真实伤害
		# 新增效果积木状态 ----
		"buffs": [],                 # [{stat, mult/add, until}] 临时属性 buff
		"dots": [],                  # [{tag, dps, until, raw(bool=真伤)}] 诅咒等 flat DoT (灼烧/中毒/流血已改层数 dot_stacks)
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
		# 装备 ----
		"equips": [],                # [{id, star}] 本龟携带的装备 (注入时填)
		"eq_state": {},              # 各装备运行时状态 (充能/层数/标记, per-id 键)
		"hp50_fired": false,         # HP阈值钩子 (首次<50%) 已触发标记
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
		# 2D击飞滑行中: 水平滑开 + 立绘抬升(伪3D俯视假"飞起来"), 覆盖正常移动/攻击
		var knocked: bool = u.get("knock_t", 0.0) > 0.0
		if knocked:
			u["knock_t"] -= delta
			u["pos"] += u["knock_vel"] * delta
			u["knock_vel"] *= 0.85
			u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
			u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
			u["node"].position = u["pos"]
			var kp: float = clampf(1.0 - u["knock_t"] / KNOCK_DUR, 0.0, 1.0)
			u["spr"].position.y = u.get("spr_base_y", 0.0) - KNOCK_HOP * sin(kp * PI)
			if u["knock_t"] <= 0.0:
				u["spr"].position.y = u.get("spr_base_y", 0.0)
		if not stunned and not knocked:
			var spd: float = u["move_spd"] * (0.6 if _t < u["slow_until"] else 1.0)
			# 移动: 近战追到射程 / 远程维持射程并风筝
			var intent := Vector2.ZERO
			if dist > rng:
				intent = to_t.normalized()
			elif not u["melee"] and dist < rng * 0.7:
				intent = -to_t.normalized()
			intent += _separation(u) * (0.25 if dist <= rng else 1.0)   # 到攻击射程→减弱软分离,站稳原地打不抖(Botworld"停下来打"); 接近中才全力分离防重叠
			if intent.length() > 0.01:
				u["vel"] = intent.normalized() * spd
				u["pos"] += u["vel"] * delta
				u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
				u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
				u["node"].position = u["pos"]
				if absf(u["vel"].x) > 1.0:
					u["spr"].scale.x = absf(u["spr"].scale.x) * (1.0 if u["vel"].x >= 0.0 else -1.0)
			# 普攻 (no_basic 召唤体=只靠周期特殊技/掉血, 不平A)
			if dist <= rng and not u.get("no_basic", false):
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
	# flat DoT 列表 (诅咒等, raw=真伤穿护盾; 灼烧/中毒/流血已移到 dot_stacks 层数模型)
	var keep: Array = []
	for dot in u["dots"]:
		if _t < dot["until"]:
			_raw_lose(u, dot["dps"] * delta)
			if not u["alive"]:
				return
			keep.append(dot)
	u["dots"] = keep
	# 层数式 DoT (灼烧/中毒/流血): 每 STACK_DOT_TICK(1秒) 结算一次出伤+衰减 (1:1 dot.gd tick)
	u["_dottimer"] = u.get("_dottimer", 0.0) + delta
	while u["_dottimer"] >= STACK_DOT_TICK:
		u["_dottimer"] -= STACK_DOT_TICK
		_tick_dot_stacks(u)
		if not u["alive"]:
			return
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
	# 召唤体周期特殊技 + 自损 (海盗船开炮/水晶球射线/浮游炮打随机敌/糖果炸弹掉血)
	if u.get("is_summon", false):
		_tick_summon_special(u, delta)
		if not u["alive"]:
			return
	# 周期被动 (龟自身计时器在 _per_unit_timers)
	_tick_periodic_passive(u, delta)
	# 装备周期 tick (每 2.5 秒) — A类回合节拍效果
	if not u.get("equips", []).is_empty():
		_eq_tick(u, delta)

func _update_status_dot(u: Dictionary, stunned: bool) -> void:
	if stunned:
		u["dot"].color = Color("#ffe14d")        # 黄=眩晕/冻结/麻痹
	elif _t < u["taunt_until"]:
		u["dot"].color = Color("#ff4dff")        # 紫=被嘲讽
	elif u["dots"].size() > 0 or not u.get("dot_stacks", {}).is_empty() or _t < u["burn_until"]:
		u["dot"].color = Color("#ff7a33")        # 橙=DoT (诅咒flat / 灼烧中毒流血层数)
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
		if _t < o["untargetable_until"]:   # 黑洞 → 不可被选
			continue
		# 缩头随从: 缩头本体存活时, 随从躲身后不可被敌单体选中 (AOE 仍可命中)
		if o.get("hiding_protected", false):
			var ow = o.get("summon_owner", null)
			if ow != null and ow.get("alive", false):
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
		"lava":
			if u.get("volcano", false):                                  # 火山形态: 烈焰重击式平A (更重·单段)
				scale = 1.6; hits = 1
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
		"two_head":  _sk_two_head(u, tgt)            # ✅ 双头: 切形态(选一套)+放新形态这套招; 常驻坚韧在 on-target
		"lava":      _sk_lava_cast(u, tgt)           # ✅ 熔岩: 选一套→放当前形态(小/火山)这套招; 攒怒变身在 tick
		"cyber":     _sk_cyber_cannon(u, tgt)        # ⚠ 赛博: 能量大炮(浮游炮被动在 tick)
		"candy":     _sk_candy_armor(u)              # ✅ 焦糖铠: 自护盾+回血 (糖果罐/炸弹召唤留TODO)
		"hiding":    _sk_hiding_defend(u)            # ⚠ 缩头: 防御自护盾 (随从召唤被动在 spawn)
		"shell":     _sk_shell_absorb(u, tgt)        # ⚠ 龟壳: 吸收偷HP (觉醒/储能被动在 tick)
		_:           _sk_burst(u, tgt)               # 兜底重击
	_eq_on_cast(u, tgt)                              # on-cast: 放主动技后装备 (千刃风暴/火炮连射/水晶光束/灼热主动 等)

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
# 双头龟·选一套 (demo 默认套1). 每次攒满龟能 → 切形态(swap 近战↔远程的属性+平A) + 放新形态这套招.
# 常驻被动 双头坚韧 在 _eq_on_target 之外的受伤钩子里 (见 _apply_damage_from 内 two_head 段).
func _sk_two_head(u: Dictionary, tgt: Dictionary) -> void:       # 双头龟 ✅ 选一套+切换形态
	var set_id: String = u.get("two_set", "1")
	# 切形态: 近战↔远程 (属性+平A方式)
	u["two_form"] = "ranged" if u.get("two_form", "melee") == "melee" else "melee"
	var to_ranged: bool = u["two_form"] == "ranged"
	u["melee"] = not to_ranged
	u["atk_range"] = 300.0 if to_ranged else 70.0
	# 远程脆高攻 / 近战肉 (体现双生框架): 切换时调攻速 (近战慢重锤, 远程快法波)
	u["atk_interval"] = 1.1 if not to_ranged else 0.8
	if not to_ranged:
		# 切到近战 → 放近战这套招
		match set_id:
			"1", "3":   # 套1/套3 近战位都是 锤击(物+永久护盾)
				_float_text(u["pos"] + Vector2(0, -64), "近战·锤击!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt), Color("#ffb05c"))
				_grant_shield(u, u["atk"] * 0.5)
			"2":        # 套2 近战位 = 吸收(伤害+回血)
				_float_text(u["pos"] + Vector2(0, -64), "近战·吸收!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ffb05c"), 0.35)
	else:
		# 切到远程 → 放远程这套招
		match set_id:
			"1":        # 套1 远程 = 精神干扰(破盾50%+削治疗50%)
				_float_text(u["pos"] + Vector2(0, -64), "远程·精神干扰!", Color("#b0c0ff"))
				tgt["shield"] *= 0.5
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt, true), Color("#c0d0ff"))
				_buff(tgt, "atk", -0.20, true)   # 削治疗简化为减攻debuff
			"2":        # 套2 远程 = 魔法波四段(物+真)
				_float_text(u["pos"] + Vector2(0, -64), "远程·魔法波!", Color("#b0c0ff"))
				for i in range(4):
					if not tgt["alive"]: break
					_apply_damage_from(u, tgt, _atk_dmg(u, 0.6, tgt, i % 2 == 0), Color("#c0d0ff"))
			"3":        # 套3 远程 = 灵能冲击(全体AoE+15%最大HP)
				_float_text(u["pos"] + Vector2(0, -64), "远程·灵能冲击!", Color("#b0c0ff"))
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true) + int(o["maxHp"] * 0.15), Color("#c0d0ff"))

# 熔岩龟·选一套 (demo 默认套A; lava_set ∈ A/B/C). 龟能满→放【当前形态】(小/火山)这套对应招.
# 怒气满变身火山(_tick_periodic_passive)与龟能放技两条独立.
func _sk_lava_cast(u: Dictionary, tgt: Dictionary) -> void:      # 熔岩龟·选一套各自触发 ✅
	var set_id: String = u.get("lava_set", "A")
	var volcano: bool = u.get("volcano", false)
	match set_id:
		"A":   # AoE核: 小=地裂(全体魔+削魔抗) / 火山=火山爆发(全体五段+灼烧+回血)
			if volcano: _lava_volcano_erupt(u)
			else:       _lava_quake(u)
		"B":   # 单体续航: 小=岩浆涌动(单体魔+永久护盾) / 火山=烈焰重击(单体物+吸血)
			if volcano: _lava_flame_strike(u, tgt)
			else:       _lava_magma_surge(u, tgt)
		"C":   # AoE+控: 小=熔岩喷射(全体+灼烧) / 火山=岩浆践踏(全体+眩晕+回血)
			if volcano: _lava_magma_stomp(u)
			else:       _lava_spray(u)
		_:
			_lava_quake(u)

func _lava_quake(u: Dictionary) -> void:                         # 小·地裂: 全体魔+削魔抗
	_float_text(u["pos"] + Vector2(0, -64), "地裂!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.7, o, true), Color("#ff9d5c"))
		_buff(o, "mr", -0.2, true)

func _lava_volcano_erupt(u: Dictionary) -> void:                 # 火山·火山爆发: 全体五段+灼烧+回血
	_float_text(u["pos"] + Vector2(0, -64), "火山爆发!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		for i in range(5):
			if not o["alive"]: break
			_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true), Color("#ff7a33"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # 技能灼烧: 默认层数 max(1,round(ATK×0.67))
	_heal(u, u["maxHp"] * 0.12)
	_skill_ring(u["pos"], Color(1.0, 0.4, 0.1, 0.5), 130.0)

func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 单体魔+永久护盾
	_float_text(u["pos"] + Vector2(0, -64), "岩浆涌动!", Color("#ff7a33"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt, true), Color("#ff9d5c"))
	_grant_shield(u, u["atk"] * 0.8)

func _lava_flame_strike(u: Dictionary, tgt: Dictionary) -> void: # 火山·烈焰重击: 单体物+吸血
	_float_text(u["pos"] + Vector2(0, -64), "烈焰重击!", Color("#ff5a2a"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.2, tgt), Color("#ff7a33"), 0.30)

func _lava_spray(u: Dictionary) -> void:                         # 小·熔岩喷射: 全体+灼烧
	_float_text(u["pos"] + Vector2(0, -64), "熔岩喷射!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.6, o, true), Color("#ff9d5c"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # 技能灼烧: 默认层数 max(1,round(ATK×0.67))

func _lava_magma_stomp(u: Dictionary) -> void:                   # 火山·岩浆践踏: 全体+40%眩晕+回血
	_float_text(u["pos"] + Vector2(0, -64), "岩浆践踏!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.9, o, true), Color("#ff7a33"))
		if randf() < 0.40:
			_freeze(o, CTRL_SEC)
	_heal(u, u["maxHp"] * 0.10)

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
	# 2D伪3D击飞: 不再瞬移, 给击飞速度 → tick里水平滑行 + 立绘抬升再落回(俯视假"飞起来", 地面标记/血条不动作参照)
	if tgt.get("knock_t", 0.0) <= 0.0:
		tgt["spr_base_y"] = tgt["spr"].position.y   # 捕获立绘基准y (防hop重复偏移)
	tgt["knock_vel"] = dir * (dist * 2.0 / KNOCK_DUR)   # 线性衰减下总滑距≈dist
	tgt["knock_t"] = KNOCK_DUR
	# 飞镖056: 任意敌被己方击飞 → 标"靶子", 携带者周期 tick 射镖
	if tgt["side"] != by["side"] and _side_has_equip(by["side"], "p2eq_056"):
		tgt["eq_target_until"] = _t + 99999.0

# 某一方是否有存活单位携带某装备 (飞镖靶子标记用)
func _side_has_equip(side: String, item_id: String) -> bool:
	for o in _units:
		if o["side"] == side and o["alive"]:
			for e in o.get("equips", []):
				if str(e["id"]) == item_id:
					return true
	return false

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

# flat DoT (诅咒等). dps = 每秒落血; 真伤穿护盾. 灼烧/中毒/流血改走 _apply_dot_stacks 层数模型.
func _add_dot(u: Dictionary, tag: String, dps: float, sec: float) -> void:
	u["dots"].append({"tag": tag, "dps": dps, "until": _t + sec})

# 层数式 DoT 施加 (1:1 回合制 dot.gd apply_stacks). type∈[burn,poison,bleed]; 多次施加→累加层数.
#   burn 检免疫 (_burnImmune flag / passive.burnImmune). src=施加者 (供归功; 可 null).
func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if u == null or not u.get("alive", false) or stacks <= 0:
		return
	if type == "burn":
		if u.get("_burnImmune", false):
			return
		var passive = u.get("passive", null)
		if passive is Dictionary and passive.get("burnImmune", false):
			return
	var ds: Dictionary = u["dot_stacks"]
	ds[type] = int(ds.get(type, 0)) + stacks
	if src != null:
		u["dot_src"][type] = src

# 灼烧默认层数 = max(1, round(attacker.atk × 0.67))  (1:1 dot.gd default_burn_stacks)
func _default_burn_stacks(attacker: Dictionary) -> int:
	return maxi(1, roundi(float(attacker.get("atk", 0.0)) * 0.67))

func _has_dot(u: Dictionary, tag: String) -> bool:
	# 灼烧/中毒/流血 = 层数模型 (dot_stacks); 诅咒等仍走 flat dots 列表
	if tag == "burn" or tag == "poison" or tag == "bleed":
		return int(u.get("dot_stacks", {}).get(tag, 0)) > 0
	for d in u["dots"]:
		if d["tag"] == tag and _t < d["until"]:
			return true
	return false

# 层数 DoT 每秒结算 (1:1 dot.gd tick). 固定顺序 burn→poison→bleed; 出伤后层数衰减, ≤0 移除.
#   burn:   dmg = 层数 + round(maxHp×层数×0.001);  衰减 floor(层数×2/3);  魔法; 有真火→真实(穿盾)
#   poison: dmg = 层数;                            衰减 floor(层数×3/4);  魔法 (青绿)
#   bleed:  dmg = 层数;                            衰减 floor(层数×3/4);  物理 (红)
func _tick_dot_stacks(u: Dictionary) -> void:
	var ds: Dictionary = u.get("dot_stacks", {})
	if ds.is_empty():
		return
	var max_hp: float = u["maxHp"]
	for type in ["burn", "poison", "bleed"]:   # 固定结算顺序
		var stacks: int = int(ds.get(type, 0))
		if stacks <= 0:
			continue
		var dmg: int = 0
		var new_val: int = 0
		match type:
			"burn":
				dmg = stacks + roundi(max_hp * stacks * 0.001)
				new_val = floori(stacks * 2.0 / 3.0)   # 衰减 1/3
				if _t < u.get("true_fire_until", 0.0):  # 真火: 灼烧转真实伤害(穿盾)
					_raw_lose(u, float(dmg))
				else:
					_apply_damage(u, dmg, Color("#7aa8ff"))   # 魔蓝
			"poison":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)   # 衰减 1/4
				_apply_damage(u, dmg, Color("#7ee87e"))    # 青绿
			"bleed":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)   # 衰减 1/4
				_apply_damage(u, dmg, Color("#ff6b6b"))    # 红
		ds[type] = maxi(0, new_val)
		if ds[type] <= 0:
			ds.erase(type)
		if not u["alive"]:
			return

# 净化: 清除目标所有减益 (DoT层数/flat DoT/减攻buff/减速)
func _cleanse(u: Dictionary) -> int:
	var n: int = u["dots"].size()
	u["dots"] = []
	for type in ["burn", "poison", "bleed"]:   # 层数 DoT 也算减益, 一并清
		if int(u.get("dot_stacks", {}).get(type, 0)) > 0:
			n += 1
			u["dot_stacks"][type] = 0
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
# from_equip=true 时表示这一段是【装备效果自身造的伤害】→ 不再触发 on-hit/on-target 装备钩子 (防递归刷屏).
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false) -> void:
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	if u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and randf() < u["dodge_bonus"]:
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#cfe6ff"))
		_eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 靶向器055: 被标记目标受伤 +20%
	if _t < u.get("eq_marked_until", 0.0):
		dmg = int(dmg * 1.2)
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
	# 双头坚韧 (常驻被动): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head":
		var th: int = int(u.get("two_tough", 0))
		if th < 20:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; _recalc_stats(u)
	# 石头龟坚壁: 受伤反弹 (5%+1%DEF+0.5%MR)
	if u["id"] == "stone" and src["alive"] and src["side"] != u["side"]:
		var reflect: float = float(dmg) * 0.05 + u["def"] * 0.01 + u["mr"] * 0.005
		if reflect >= 1.0:
			_raw_lose(src, reflect)
	# 装备事件钩子 (on-hit 攻击方 / on-target 防守方 / HP阈值) — 装备自身造的段不再回钩
	if not from_equip:
		if src["alive"] and u["alive"]:
			_eq_on_hit(src, u, dmg)        # on-hit: 攻击者装备 (流血/灼烧/连锁/追击/穿透/标记 等)
		if u["alive"]:
			_eq_on_target(u, src, dmg)     # on-target: 防守者装备 (硬化层/冰封反制 等)
	if u["alive"]:
		_eq_check_hp_threshold(u)          # HP阈值: 首次<50% (深海项链/珍珠耳环)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u, src)

func _raw_lose(u: Dictionary, amt: float) -> void:
	# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], amt)
		u["shield"] -= ab; amt -= ab
	u["hp"] = maxf(0.0, u["hp"] - amt)
	_update_bars(u)
	if u["alive"]:
		_eq_check_hp_threshold(u)          # DoT 也可能压到<50% → 触发救命装备
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

func _kill(u: Dictionary, killer = null) -> void:
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为被动选项时生效, 简化为常驻一次
	if not u["reborn_used"] and (u["id"] == "angel" or u["id"] == "phoenix"):
		u["reborn_used"] = true
		var pct: float = 0.30 if u["id"] == "phoenix" else 0.25
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		u["dot_stacks"] = {}   # 复活清掉灼烧/中毒/流血层数
		_update_bars(u)
		_float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧
			for o in _enemies_of(u):
				_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # 技能灼烧: 默认层数 max(1,round(ATK×0.67))
		return
	u["alive"] = false
	if killer != null and killer.get("alive", false):
		_eq_on_kill(killer, u)             # on-kill: 击杀者装备 (暴君之牙处决回能/回血 等)
	_eq_on_death(u, killer)                # on-death: 阵亡者装备 (复活海螺变虫 / 齿轮折币)
	_on_unit_death(u, killer)
	var n: Node2D = u["node"]
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.4)
	tw.tween_callback(n.hide)

# 死亡钩子: 猎人窃取 / 幽灵死亡诅咒 / 财神死亡给币 / 海盗钩锁 等
func _on_unit_death(u: Dictionary, killer) -> void:
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_apply_damage_from(u, o, int(per), Color("#ff8ad8"), 0.0, true, true)
			_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 120.0)
			_float_text(u["pos"] + Vector2(0, -40), "炸!", Color("#ff8ad8"))
	# 缩头随从死亡 → 缩头本体不再受保护 (反向: 缩头死则随从同死, 见下)
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				if is_instance_valid(o["node"]): o["node"].hide()
	# 赛博龟阵亡 → 所有浮游炮组装成机甲继续战斗
	if u["id"] == "cyber":
		_cyber_assemble_mech(u)
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

# 赛博龟阵亡 → 浮游炮全部组装成机甲 (独立单位, HP/ATK 按浮游炮数, 攻最低血敌 150%ATK)
func _cyber_assemble_mech(u: Dictionary) -> void:
	# 收集本龟存活浮游炮
	var drones: Array = []
	for o in _units:
		if o.get("is_summon", false) and o["alive"] and o.get("summon_owner", null) == u and o.get("summon_kind", "") == "drone":
			drones.append(o)
	if drones.is_empty():
		return
	var n: int = drones.size()
	# 机甲 HP/ATK 按浮游炮数 (基础 + 每炮叠加 + 吸收剩余炮血)
	var mech_hp: float = u["maxHp"] * 0.5 + 200.0 * HP_MULT * n
	var mech_atk: float = u["base_atk"] * (0.6 + 0.25 * n)
	for d in drones:                       # 吸收: 浮游炮消失, 血并入机甲
		mech_hp += d["hp"]
		d["alive"] = false
		if is_instance_valid(d["node"]): d["node"].hide()
	var mech = _spawn_summon(u, "mech", mech_hp, mech_atk, {
		"label": "机甲", "col_size": 40.0, "hp_w": 46.0, "melee": false,
		"move_spd": 130.0, "atk_interval": 1.0, "atk_range": 320.0,
		"special": "mech_blast", "special_cd": 2.5, "special_scale": 1.5,
	})
	if mech != null:
		mech["pos"] = u["pos"]; mech["node"].position = u["pos"]
		# 机甲攻最低血敌 (在 special 派发, 这里标 mech 走 mech_blast)
		_float_text(u["pos"] + Vector2(0, -70), "机甲组装!", Color("#7ee8ff"))
		_skill_ring(u["pos"], Color(0.5, 0.9, 1.0, 0.6), 80.0)

# 缩头随从: 随机 A 级及以下乌龟 (40%常规最大HP, 独立单位+独立AI, 用真立绘).
# 简化: 不可被敌单体技选中 (untargetable, 但敌AOE/平A仍可命中; 不计入胜负)
const HIDING_POOL := ["basic", "stone", "bamboo", "ninja", "dice", "rainbow", "hunter", "pirate", "candy", "bubble", "line", "headless"]
func _spawn_hiding_minion(u: Dictionary) -> void:
	var pick: String = HIDING_POOL[randi() % HIDING_POOL.size()]
	var d: Dictionary = _data_by_id.get(pick, {})
	var st: Array = STATS.get(pick, DEFAULT_STAT)
	var hp: float = float(d.get("hp", 450)) * HP_MULT * 0.40
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8, {
		"label": "随从", "spr_id": pick, "col_size": 36.0, "hp_w": 30.0,
		"melee": bool(st[0]), "move_spd": float(st[1]), "atk_interval": float(st[2]), "atk_range": float(st[3]),
		"crit": float(d.get("crit", 0.2)),
	})
	if minion != null:
		minion["minion_kind"] = pick
		# 躲缩头身后: 缩头存活时随从不可被敌单体选中 (周期在 special 不需要; 这里持续标记)
		minion["hiding_protected"] = true

func _spawn_pirate_ship(u: Dictionary) -> void:
	# 海盗船: 开战N秒后召唤 (150%HP/100%ATK/无甲魔抗) 独立单位, 每隔N秒对随机敌开炮
	var ship = _spawn_summon(u, "ship", u["maxHp"] * 1.5, u["atk"], {
		"label": "海盗船", "col_size": 38.0, "hp_w": 44.0, "melee": false,
		"move_spd": 70.0, "atk_range": 360.0, "no_basic": true,
		"special": "cannon", "special_cd": 2.0, "special_scale": 0.2,
	})
	if ship != null:
		_float_text(u["pos"] + Vector2(0, -70), "召唤海盗船!", Color("#ffb05c"))

func _update_bars(u: Dictionary) -> void:
	if not is_instance_valid(u["hp_fill"]):
		return
	if u.get("is_summon", false):
		# 召唤体只有血条 (宽 hp_w, 机甲更宽), 不画护盾/龟能
		u["hp_fill"].size.x = float(u.get("hp_w", 28.0)) * clampf(u["hp"] / u["maxHp"], 0.0, 1.0)
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
				# [被]糖果炸弹 (demo 默认开此召唤): 登场召唤糖果炸弹(40%HP/0攻/每秒掉血), 死亡爆炸全体敌
				_spawn_summon(u, "candybomb", u["maxHp"] * 0.40, 0.0, {
					"label": "糖果炸弹", "col_size": 20.0, "hp_w": 24.0,
					"no_basic": true, "no_move": true, "self_decay": 0.08,
					"death_aoe": 1.5,   # 死亡爆炸 = 自身maxHp×150% 魔伤均摊全体敌
				})
			"hiding":                                  # 喊龟: 召唤一只A级及以下随从 (独立单位+独立AI)
				_spawn_hiding_minion(u)
			"crystal":                                 # [被]水晶球 (demo 默认开此召唤): 登场召唤水晶球, 周期射线
				_spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
					"label": "水晶球", "col_size": 20.0, "hp_w": 26.0, "melee": false,
					"move_spd": 90.0, "atk_range": 320.0, "no_basic": true,
					"special": "ray", "special_cd": 2.5, "special_scale": 1.0,
				})
			"lava":                                    # 选一套: demo 默认套A (AoE核)
				u["lava_set"] = "A"
			"two_head":                                # 选一套: demo 默认套1 (锤击+精神干扰)
				u["two_set"] = "1"; u["two_form"] = "melee"

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
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # 技能灼烧: 默认层数 max(1,round(ATK×0.67))
			_heal(u, (o["maxHp"] - o["hp"]) * 0.08)
	if u.get("volcano", false) and _t >= u["volcano_until"]:
		u["volcano"] = false
		u["maxHp"] /= 1.3; u["hp"] = minf(u["hp"], u["maxHp"])
	# --- 赛博浮游炮: 每周期生成1 (上限10), 浮游炮每隔N秒打随机敌 ---
	if u["id"] == "cyber":
		if u["_ptimer"] >= 3.0:
			u["_ptimer"] = 0.0
			# 清掉死掉的浮游炮引用
			var live: Array = []
			for d in u["summons"]:
				if d is Dictionary and d.get("alive", false): live.append(d)
			u["summons"] = live
			if u["summons"].size() < 10:
				var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25, {
					"label": "浮游炮", "col_size": 16.0, "hp_w": 22.0, "melee": false,
					"move_spd": 110.0, "atk_range": 300.0, "atk_interval": 1.0,
					"no_basic": true, "special": "random_hit", "special_cd": 1.6, "special_scale": 0.25,
				})
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
	# --- 龟壳气场觉醒: 开战~10秒觉醒(全属性+12%+暴击) + 每N秒消耗储能 AoE物伤+气场护盾 ---
	elif u["id"] == "shell":
		if not u.get("awakened", false) and _t >= 10.0:
			u["awakened"] = true
			_buff(u, "atk", 0.12, true, 9999.0); _buff(u, "def", 0.12, true, 9999.0); _buff(u, "mr", 0.12, true, 9999.0)
			u["crit"] += 0.25; _recalc_stats(u)
			_float_text(u["pos"] + Vector2(0, -70), "气场觉醒!", Color("#b0ffe0"))
		# 储能消耗周期: 每3秒, 若有储能→对全体敌储能×40%物伤 + 自身储能×80%气场护盾
		u["_shelltimer"] = u.get("_shelltimer", 0.0) + delta
		if u["_shelltimer"] >= 3.0:
			u["_shelltimer"] = 0.0
			var se: float = u["store_energy"]
			if se >= 1.0:
				u["store_energy"] = 0.0
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(se * 0.40), Color("#b0ffe0"))
				_grant_shield(u, se * 0.80)
				_float_text(u["pos"] + Vector2(0, -64), "气场释放!", Color("#b0ffe0"))
				_skill_ring(u["pos"], Color(0.7, 1.0, 0.88, 0.5), 120.0)
	# --- 海盗船召唤: 开战~4秒后召唤一次 (独立单位, 周期开炮) ---
	if u["id"] == "pirate" and not u.get("ship_summoned", false) and _t >= 4.0:
		u["ship_summoned"] = true
		_spawn_pirate_ship(u)
	# --- 财神聚宝盆: 每秒+2金币 ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 1.0:
			u["_goldtimer"] = 0.0; u["gold"] += 2

# 召唤独立单位 — 真·独立战斗体: 自己移动索敌 + 按攻速平A + (可选)周期特殊技. 走同一 tick.
# behavior(可选) 字段控制各召唤体差异化 AI:
#   "spr_id": String     用真立绘(缩头随从=随机A级龟) 而非小色块
#   "special": String    周期特殊技标签 (cannon/ray/random_hit/hp_drain) — 在 _tick_summon_special 派发
#   "special_cd": float   特殊技周期秒
#   "special_scale": float 特殊技倍率
#   "owner": Dictionary  归属龟引用 (随从死亡同步/水晶共享结晶等)
#   "no_move": bool      不移动 (糖果炸弹/海盗船定点)
#   "no_basic": bool     不平A (糖果炸弹只靠周期特殊/掉血)
#   "death_aoe": float   死亡爆炸 AoE 倍率(×自身maxHp 魔伤均摊全体敌)
#   "self_decay": float  每秒自损 maxHp×pct (糖果炸弹)
#   "hp_w": float / "atk_w": float  血条/格子宽度 (机甲更大)
#   "col_size": float    色块边长
func _spawn_summon(owner: Dictionary, kind: String, hp: float, atk: float, behavior: Dictionary = {}):
	var pos: Vector2 = owner["pos"] + Vector2(randf_range(-40, 40), randf_range(30, 60))
	pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)
	pos.y = clampf(pos.y, ARENA.position.y, ARENA.end.y)
	var col := Color("#3fa9ff") if owner["side"] == "left" else Color("#ff5a5a")
	var node := Node2D.new(); node.position = pos; add_child(node)
	var spr_node: CanvasItem        # Sprite2D/Node2D 或 ColorRect 都行 (走 modulate/位置)
	var spr_id: String = str(behavior.get("spr_id", ""))
	var col_size: float = float(behavior.get("col_size", 22.0))
	if spr_id != "" and ResourceLoader.exists("res://assets/sprites/avatars/%s.png" % spr_id):
		spr_node = _make_sprite(spr_id)
		node.add_child(spr_node)
	else:
		var c := ColorRect.new()
		c.color = Color(col.r, col.g, col.b, 0.85)
		c.size = Vector2(col_size, col_size); c.position = Vector2(-col_size * 0.5, -col_size * 0.5)
		node.add_child(c)
		spr_node = c
	var hp_w: float = float(behavior.get("hp_w", 28.0))
	var hp_bg := ColorRect.new()
	hp_bg.color = Color("#3a0d0d"); hp_bg.position = Vector2(-hp_w * 0.5, -20); hp_bg.size = Vector2(hp_w, 4)
	node.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#39d353"); hp_fill.position = Vector2(-hp_w * 0.5, -20); hp_fill.size = Vector2(hp_w, 4)
	node.add_child(hp_fill)
	var lbl := Label.new()
	lbl.text = str(behavior.get("label", kind))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", col)
	lbl.position = Vector2(-hp_w * 0.5, -36); lbl.size = Vector2(hp_w, 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(lbl)
	var dot := ColorRect.new(); dot.color = Color(1,1,1,0); dot.position = Vector2(hp_w * 0.5, -22); dot.size = Vector2(6, 6)
	node.add_child(dot)
	var su := {
		"id": "_summon_" + kind, "name": kind, "rarity": "C", "side": owner["side"],
		"pos": pos, "vel": Vector2.ZERO, "hp": hp, "maxHp": hp,
		"atk": atk, "def": 0.0, "mr": 0.0, "base_atk": atk, "base_def": 0.0, "base_mr": 0.0,
		"crit": float(behavior.get("crit", 0.0)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
		"melee": bool(behavior.get("melee", kind != "drone")),
		"move_spd": float(behavior.get("move_spd", 0.0 if behavior.get("no_move", false) else 120.0)),
		"atk_interval": float(behavior.get("atk_interval", 1.2)),
		"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else 70.0)),
		"atk_cd": 0.0, "energy": 0.0, "alive": true, "is_summon": true,
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0,
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0,
		"buffs": [], "dots": [], "taunt_until": 0.0, "taunt_by": null, "slow_until": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0, "summons": [],
		# 召唤 AI 行为字段 ----
		"summon_kind": kind, "summon_owner": owner, "hp_w": hp_w,
		"no_basic": bool(behavior.get("no_basic", false)),
		"summon_special": str(behavior.get("special", "")),
		"special_cd": float(behavior.get("special_cd", 0.0)),
		"special_timer": 0.0,
		"special_scale": float(behavior.get("special_scale", 1.0)),
		"death_aoe": float(behavior.get("death_aoe", 0.0)),
		"self_decay": float(behavior.get("self_decay", 0.0)),
		"equips": [], "eq_state": {},
		"node": node, "spr": spr_node, "hp_fill": hp_fill,
		"shield_fill": hp_fill, "en_fill": hp_fill, "dot": dot,
	}
	_units.append(su)
	return su

# 召唤体周期特殊技 + 自损 (在 _tick_effects 内对 is_summon 单位调用)
# 让召唤体不只是平A: 海盗船周期开炮 / 水晶球周期射线 / 浮游炮周期打随机敌 / 糖果炸弹掉血 等
func _tick_summon_special(u: Dictionary, delta: float) -> void:
	# 自损 (糖果炸弹每秒掉 maxHp×pct, 归零→死亡触发爆炸)
	if u.get("self_decay", 0.0) > 0.0:
		_raw_lose(u, u["maxHp"] * u["self_decay"] * delta)
		if not u["alive"]:
			return
	var special: String = u.get("summon_special", "")
	if special == "" or u.get("special_cd", 0.0) <= 0.0:
		return
	u["special_timer"] = u.get("special_timer", 0.0) + delta
	if u["special_timer"] < u["special_cd"]:
		return
	u["special_timer"] = 0.0
	var owner = u.get("summon_owner", u)
	if owner == null or not owner.get("alive", false):
		owner = u
	match special:
		"cannon":   # 海盗船: 每隔N秒对随机敌开炮 (0.2ATK·不可闪避·简化)
			var es := _enemies_of(u)
			if es.is_empty(): return
			var o = es[randi() % es.size()]
			_fire_bolt_from(u, o, _atk_dmg(u, u.get("special_scale", 0.2), o), Color("#ffb05c"))
			_skill_ring(o["pos"], Color(1.0, 0.6, 0.2, 0.45), 40.0)
		"ray":      # 水晶球: 每隔N秒射魔法线两段 + 叠结晶(共享归属龟结晶)
			var t = _nearest_enemy(u)
			if t == null: return
			_bolt_line(u["pos"], t["pos"], Color("#c9b0ff"))
			for i in range(2):
				if not t["alive"]: break
				_apply_damage_from(u, t, _atk_dmg(u, u.get("special_scale", 1.0), t, true), Color("#c9b0ff"), 0.0, true)
			# 共享结晶: 给归属龟的结晶系统叠层 (满4由 owner 引爆)
			if t["alive"]:
				var cv := _add_stack(t, "crystal", 1, 4)
				if cv >= 4:
					_consume_stacks(t, "crystal")
					_apply_damage_from(u, t, int(t["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
		"random_hit":   # 浮游炮: 每隔N秒打随机敌 (0.25ATK物)
			var es2 := _enemies_of(u)
			if es2.is_empty(): return
			var o2 = es2[randi() % es2.size()]
			_fire_bolt_from(u, o2, _atk_dmg(u, u.get("special_scale", 0.25), o2), Color("#9bf0ff"))
		"mech_blast":   # 赛博机甲: 攻最低血敌 150%ATK (激光两段)
			var low = null; var lv := INF
			for o in _enemies_of(u):
				if o["hp"] < lv: lv = o["hp"]; low = o
			if low == null: return
			_bolt_line(u["pos"], low["pos"], Color("#9bf0ff"))
			for i in range(2):
				if not low["alive"]: break
				_apply_damage_from(u, low, _atk_dmg(u, u.get("special_scale", 1.5) * 0.5, low), Color("#9bf0ff"))

func _check_end() -> void:
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"] and not u.get("is_summon", false):    # 召唤体不计入胜负判定
			if u["side"] == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		var won: bool = right_alive == 0            # 左队(玩家)全灭对方 = 胜
		_settle_season(won)                          # 结果喂赛季 (一次性守卫)
		_show_settlement(won)

## 实时战斗结果喂局外赛季 (复用 DualLaneMapScene._grant_settlement_reward 那套 V2 公式).
## 玩家=左队. 赢: season_wins+1 / 给币(含+15) / +1总战斗 / +2经验 / upload_ghost.
##                输: lose_heart / 给币(无+15) / +1总战斗 / +2经验.
## 0命表演赛兜底: 不掉命/不计战/不上榜, 只少量练手币 (沿用 V2, 防送命换币).
## 守卫: _settled 防重复. demo 跑(无 season_leaders)→ 不喂只显横幅.
func _settle_season(won: bool) -> void:
	if _settled:
		return
	_settled = true
	var gs = get_node_or_null("/root/GameState")
	# demo / 无赛季态: 玩家没配 season_leaders → 不喂赛季 (只显结算横幅, 别崩)
	_had_season = gs != null and (gs.get("season_leaders") is Array) and (gs.get("season_leaders") as Array).size() >= 1
	if not _had_season:
		return
	if gs.has_method("ensure_season"):
		gs.ensure_season()                           # 兜底初始化/滚赛季
	_last_was_exhibition = gs.is_eliminated()        # 进场前已0命 = 表演赛 (无 stake)
	if _last_was_exhibition:
		_last_reward = 5                             # 表演赛: 少量练手币, 不掉命/不计战/不上榜 (V2 §十五#2)
	else:
		if not won:
			gs.lose_heart()                          # V2 输→失一颗心 (0命=is_eliminated 淘汰)
		var lost_hearts: int = maxi(0, 8 - int(gs.hearts))   # 8 = 赛季初始命数
		_last_reward = 25 + 2 * int(gs.hearts) + 5 * lost_hearts + (15 if won else 0)
		gs.season_total_battles += 1
		gs.add_season_xp(2)                          # V2: 每场 +2 大轮经验
		if won:
			gs.season_wins += 1                      # 实时胜场 +1 (排行指标)
			gs.season_eggs_killed += 1               # 灭敌全队 ≈ 击碎龟蛋 → 排行榜口径 +1
			# 上传自己阵容快照进 ghost 池 (供别人异步匹配; 非表演赛才传)
			# build_ghost_snapshot 读 GameState.left_team → 用 season_leaders 同步, 否则空快照.
			if gs.get("left_team") is Array and (gs.left_team as Array).is_empty():
				var _ldr: Array = gs.get("season_leaders")
				gs.left_team.assign(_ldr.slice(0, 3))
			var _gid := "g_%d_%d" % [int(gs.season_id), int(Time.get_unix_time_from_system())]
			var _av := str(gs.season_leaders[0]) if (gs.season_leaders as Array).size() > 0 else "basic"
			Backend.upload_ghost(Backend.build_ghost_snapshot(_gid, {"name": "玩家阵容", "avatar": _av, "id": _gid}))
	gs.meta_deepsea_coins += _last_reward
	gs.save()

## 结算浮层: 胜/败 + 本局奖励(币/命) + 返回菜单 / 再战 按钮. demo 无赛季态也显(只少奖励行).
func _show_settlement(won: bool) -> void:
	var gs = get_node_or_null("/root/GameState")
	var accent := Color("#ffd93d") if won else Color("#ff6b6b")
	# 半透明遮罩
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6); dim.position = Vector2.ZERO; dim.size = Vector2(1280, 720)
	dim.z_index = 49
	add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color("#0c1a26"); panel.size = Vector2(520, 360)
	panel.position = Vector2(640 - 260, 360 - 180); panel.z_index = 50
	add_child(panel)
	var border := ColorRect.new()
	border.color = Color(accent.r, accent.g, accent.b, 0.18)
	border.size = Vector2(520, 6); border.position = Vector2(0, 0); border.z_index = 51
	panel.add_child(border)
	var y := 26
	var big := Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 52)
	big.add_theme_color_override("font_color", accent)
	big.position = Vector2(0, y); big.size = Vector2(520, 64)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; big.z_index = 51
	panel.add_child(big)
	y += 96
	if _had_season and gs != null:
		# 奖励行: 深海币
		var rwd := Label.new()
		rwd.text = "💠 深海币 +%d   (累计 %d)" % [_last_reward, int(gs.meta_deepsea_coins)]
		rwd.add_theme_font_size_override("font_size", 22)
		rwd.add_theme_color_override("font_color", Color("#ffd93d"))
		rwd.position = Vector2(0, y); rwd.size = Vector2(520, 28)
		rwd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; rwd.z_index = 51
		panel.add_child(rwd)
		y += 40
		# 命数变化行
		var hp_txt: String
		var hp_col: Color
		if _last_was_exhibition:
			hp_txt = "🎯 表演赛 (已淘汰 · 0 命 · 无 stake)"; hp_col = Color("#9fb6c9")
		elif gs.is_eliminated():
			hp_txt = "💀 0 命 — 本赛季淘汰 (下局起表演赛)"; hp_col = Color("#ff9aa2")
		elif won:
			hp_txt = "❤ 命 %d/8 (保住)" % int(gs.hearts); hp_col = Color("#9fe6b0")
		else:
			hp_txt = "💔 失去 1 命 → 剩 %d/8" % int(gs.hearts); hp_col = Color("#ff9aa2")
		var hp_l := Label.new()
		hp_l.text = hp_txt
		hp_l.add_theme_font_size_override("font_size", 18)
		hp_l.add_theme_color_override("font_color", hp_col)
		hp_l.position = Vector2(0, y); hp_l.size = Vector2(520, 26)
		hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hp_l.z_index = 51
		panel.add_child(hp_l)
		y += 38
		# 赛季胜场行
		var wl := Label.new()
		wl.text = "🐢 赛季胜场 %d   ·   总战斗 %d" % [int(gs.season_wins), int(gs.season_total_battles)]
		wl.add_theme_font_size_override("font_size", 16)
		wl.add_theme_color_override("font_color", Color("#9fb6c9"))
		wl.position = Vector2(0, y); wl.size = Vector2(520, 24)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; wl.z_index = 51
		panel.add_child(wl)
		y += 36
	else:
		# demo / 无赛季态: 不喂赛季, 只提示
		var demo_l := Label.new()
		demo_l.text = "(demo 对局 · 无赛季结算)"
		demo_l.add_theme_font_size_override("font_size", 16)
		demo_l.add_theme_color_override("font_color", Color("#7f97ad"))
		demo_l.position = Vector2(0, y); demo_l.size = Vector2(520, 24)
		demo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; demo_l.z_index = 51
		panel.add_child(demo_l)
		y += 40
	# 按钮行: 返回菜单 / 再战
	var back := Button.new()
	back.text = "返回菜单"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(70, 296); back.size = Vector2(170, 44); back.z_index = 51
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	panel.add_child(back)
	var again := Button.new()
	again.text = "再战"
	again.add_theme_font_size_override("font_size", 20)
	again.position = Vector2(280, 296); again.size = Vector2(170, 44); again.z_index = 51
	again.pressed.connect(func(): get_tree().reload_current_scene())
	panel.add_child(again)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
#  装备实时实装 (59件 p2eq_*) — docs/design/装备实时实装规格.md
#  数据驱动: 逐星属性复用 P2RT.STATS (回合制版已抠好的权威逐星数值);
#  事件钩子 on-hit/on-cast/on-target/on-dodge/on-kill/on-death/HP阈值 + 周期 tick(2.5s).
#  回合→秒: 1回合≈EQ_TICK(2.5s); 站位→直线/最近/最远; 护盾永久.
#  分类标注: ✅完整 / ⚠改造(节拍·时长·站位) / 🚧TODO(简化).
# ============================================================================
const P2RT := preload("res://scripts/engine/phase2_equip_runtime.gd")
const EQ_TICK := 2.5            # 装备周期触发 = 1回合 ≈ 2.5 秒 (规格)
const EQ_BLEED_SEC := 5.0       # 流血/灼烧 DoT 持续秒 (待F5)
const EQ_BURN_SEC := 5.0

# demo 测试装备 (persistent_equipped 空时): 给每龟塞2-3件有视觉效果的件, 验证效果真触发.
# 键=龟id, 值=[{id, star}]. 选: 流血/灼烧DoT/周期护盾/连锁闪电/追击/处决/破甲 等可见效果.
const DEMO_EQUIP := {
	"stone":     [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_013", "star": 2}],          # 铁壁盾(周期全队护盾)+炙烤海胆(受击硬化)
	"basic":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_005", "star": 2}, {"id": "p2eq_023", "star": 2}],  # 海带卷刀(流血)+双生匕首(追击)+灼热火珊瑚(灼烧)
	"lightning": [{"id": "p2eq_026", "star": 2}, {"id": "p2eq_004", "star": 2}],          # 雷电法杖(连锁闪电)+暴君之牙(处决)
	"diamond":   [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_046", "star": 2}],          # 铁壁盾(周期护盾)+幽灵墨鱼(闪避护盾)
	"ninja":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_054", "star": 1}, {"id": "p2eq_058", "star": 2}],  # 流血+瞄准镜(必中)+穿甲遗弹(贯穿)
	"ghost":     [{"id": "p2eq_023", "star": 3}, {"id": "p2eq_026", "star": 1}],          # 灼热火珊瑚(灼烧)+雷电法杖(连锁)
}

# 装备注入: 玩家队(left)读 persistent_equipped; demo 阵容兜底塞测试装备.
func _inject_equipment() -> void:
	var gs = get_node_or_null("/root/GameState")
	var pe: Dictionary = {}
	if gs != null and gs.get("persistent_equipped") is Dictionary:
		pe = gs.get("persistent_equipped")
	var use_demo: bool = pe.is_empty()
	for u in _units:
		if u.get("is_summon", false):
			continue
		var key: String = str(u["id"])
		var list: Array = []
		if not use_demo and pe.has(key):
			# 玩家局外配的 build (仅左队携带; 右队=bot, demo 时才给测试装备)
			if u["side"] == "left":
				for it in (pe[key] as Array):
					if it is Dictionary and it.has("id"):
						list.append({"id": str(it["id"]), "star": int(it.get("star", 1))})
		if use_demo and DEMO_EQUIP.has(key):
			list = (DEMO_EQUIP[key] as Array).duplicate(true)
		u["equips"] = list
		for e in list:
			u["eq_state"][str(e["id"])] = {}

# 开战: 全装备纯属性 + 永久 flag 加到携带者 (在 spawn 被动之后, 让属性叠上不被覆盖).
func _eq_apply_all_stats() -> void:
	for u in _units:
		for e in u.get("equips", []):
			_eq_apply_one_stats(u, str(e["id"]), int(e.get("star", 1)))

# 单件逐星属性 → 实时单位字段 (复用 P2RT.STATS; 字段口径换到实时引擎).
#  realtime 字段: base_atk/atk · base_def/def · base_mr/mr · maxHp(已×HP_MULT) · crit(小数) · pierce(护穿+魔穿合并) · lifesteal(小数).
func _eq_apply_one_stats(u: Dictionary, item_id: String, star: int) -> void:
	var arr: Array = P2RT.STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		_eq_apply_flags(u, item_id, star)
		return
	var st: Dictionary = arr[i]
	if st.has("atk"):
		u["base_atk"] += float(st["atk"])
	if st.has("hp"):
		var add: float = float(st["hp"]) * HP_MULT   # 装备HP也按战斗节奏放大(与本体maxHp同口径)
		u["maxHp"] += add; u["hp"] += add
	if st.has("crit"):
		u["crit"] += float(st["crit"])
	if st.has("armorPen"):
		u["pierce"] += float(st["armorPen"])
	if st.has("magicPen"):
		u["pierce"] += float(st["magicPen"])   # 实时单一 pierce 字段同时减 def/mr → 合并
	if st.has("_lifestealPct"):
		u["lifesteal"] += float(st["_lifestealPct"]) / 100.0
	if st.has("def"):
		u["base_def"] += float(st["def"])
	if st.has("mr"):
		u["base_mr"] += float(st["mr"])
	if st.has("critDmg"):
		u["crit_dmg"] += float(st["critDmg"])
	# _maxEnergy(沙漏/匕首+龟能): 实时龟能上限固定 MAX_ENERGY → 折成"开局起步龟能"(更快放首技, 近似)
	if st.has("_maxEnergy"):
		u["energy"] = minf(MAX_ENERGY - 1.0, u["energy"] + float(st["_maxEnergy"]) * 0.2)
	_recalc_stats(u)
	_eq_apply_flags(u, item_id, star)

# 永久 flag / 初始充能 (受击/闪避/必中类被动开关 + 充能计数器初值).
func _eq_apply_flags(u: Dictionary, item_id: String, star: int) -> void:
	var si: int = clampi(star, 1, 3) - 1
	var stt: Dictionary = u["eq_state"].get(item_id, {})
	match item_id:
		"p2eq_046":   # 幽灵墨鱼: 永久闪避 buff (复用 dodge 系统)
			_buff(u, "dodge", [0.15, 0.25, 0.50][si], false, 99999.0)
			stt["ghost_shield"] = [30.0, 50.0, 120.0][si]
		"p2eq_054":   # 瞄准镜: 必中 (无视目标闪避)
			u["eq_cannot_be_dodged"] = true
		"p2eq_013", "p2eq_014":   # 炙烤海胆 / 深海堡垒甲: 受击硬化层 +def/mr (cap20)
			stt["harden_inc"] = [1.0, 1.5, 2.0][si]
			stt["harden_stacks"] = 0
			stt["harden_shield"] = (50.0 if item_id == "p2eq_013" else 0.0) if si == 0 else ([60.0, 80.0][si - 1] if item_id == "p2eq_013" else 0.0)
			stt["harden_given"] = false
		"p2eq_015":   # 荆棘海胆: 反伤转真伤+施流血 (受击时, 实时简化为受击直接反真伤)
			stt["reflect_pct"] = [10.0, 17.0, 25.0][si] / 100.0
			stt["reflect_bleed"] = [2.0, 2.5, 3.0][si]
		"p2eq_024":   # 龙蛋: 装备即3层吐息
			stt["dragon_stacks"] = 3
		"p2eq_039":   # 竹制弓箭: 生长充能数 (3★=3次)
			stt["bamboo_charges"] = [1, 1, 3][si]
		"p2eq_052":   # 左轮: 6发子弹
			stt["revolver_bullets"] = 6
		"p2eq_027":   # 电棍: 3层电击
			stt["baton_charges"] = 3
		"p2eq_047":   # 重击锤: ATK += maxHp×pct (动态, 这里一次性按当前maxHp折算 + 标记)
			var pct: float = [0.04, 0.06, 0.15][si]
			u["base_atk"] += u["maxHp"] / HP_MULT * pct   # 用未放大的maxHp算(对齐回合制口径)
			_recalc_stats(u)
		"p2eq_035":   # 黄铜齿轮: 齿轮层
			stt["gears"] = 0
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag, knockback/execute 读)
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
		"p2eq_036":   # 温泉蛋: 孵化进度 → 满级全队护盾(一次)
			stt["incub"] = 0.0
			stt["incub_given"] = false
			stt["incub_shield"] = [300.0, 400.0, 600.0][si]
	u["eq_state"][item_id] = stt

# ── 工具: 遍历某龟装备 (id, star, state) ──
func _eq_each(u: Dictionary, cb: Callable) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"])
		cb.call(iid, int(e.get("star", 1)), u["eq_state"].get(iid, {}))

func _eq_si(star: int) -> int:
	return clampi(star, 1, 3) - 1

# 直线弹道首个命中 (origin→dir 上最近的敌) — 枪械"沿途第一可挡"用
func _eq_first_in_line(u: Dictionary, dir: Vector2, width: float):
	var best = null; var bd := INF
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], width):
			var dd: float = (o["pos"] - u["pos"]).length_squared()
			if dd < bd: bd = dd; best = o
	return best

func _eq_farthest_enemies(u: Dictionary, half: bool) -> Array:
	var es := _enemies_of(u)
	es.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() > (b["pos"] - u["pos"]).length_squared())
	if half:
		return es.slice(0, maxi(1, es.size() / 2))
	return es

# ============================================================================
#  事件钩子: on-hit (每段命中后, attacker 视角)
# ============================================================================
func _eq_on_hit(src: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if src.get("equips", []).is_empty():
		return
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = src["eq_state"].get(iid, {})
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌 (5/7/10%maxHP + 10/15/40%×暴击率)
				var line: float = [0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					tgt["hp"] = 0.0; _update_bars(tgt)
					if was: _kill(tgt, src)   # → 触发 on-kill 回血
			"p2eq_002":   # 海带卷刀: 命中→施加 (0.075/0.1/0.15×ATK) 层流血 (desc"流血层数"; 多段自然叠层)
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "bleed", bs, src)
			"p2eq_003":   # 锋利鲨齿: 溅射相邻格(命中点小半径)15/28/50%本段伤害
				var frac: float = [0.15, 0.28, 0.50][si]
				for o in _enemies_of(src):
					if o != tgt and (o["pos"] - tgt["pos"]).length() <= 70.0:
						_apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
			"p2eq_005":   # 双生匕首: 50/75/100%概率追击 0.7/0.8/1.0×ATK
				if randf() < [0.5, 0.75, 1.0][si]:
					_apply_damage_from(src, tgt, _atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ffe08a"), 0.0, false, true)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外施加 (5/7/10 + 7/11/15%ATK) 层灼烧 (desc"层灼烧")
				var burn: int = maxi(1, roundi([5.0, 7.0, 10.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "burn", burn, src)
				_eq_charge(stt, "fire_mana", 1.0, 8.0, func(): _eq_fire_coral_active(src, si))
			"p2eq_009":   # 宽刃弯刀: 每段充刃能20/20/25, 满100→命中目标所在直线(列)伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si], 100.0, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖: 单体伤害充能25, 满100→连锁闪电
				_eq_charge(stt, "thunder", 25.0, 100.0, func(): _eq_chain_lightning(src, si))
			"p2eq_029":   # 冰封水母: 20/25/30%概率额外魔伤+冻结1回合, 冻结→自护盾
				if randf() < [0.20, 0.25, 0.30][si]:
					_apply_damage_from(src, tgt, [10, 15, 25][si], Color("#bfe9ff"), 0.0, false, true)
					_freeze(tgt, EQ_TICK)
					_grant_shield(src, [20.0, 30.0, 50.0][si])
			"p2eq_055":   # 靶向器: 命中标记目标 (+20% 受伤) 2回合
				tgt["eq_marked_until"] = _t + EQ_TICK * 2.0
			"p2eq_058":   # 穿甲遗弹: 贯穿→身后同列(朝向直线后方)敌 25/40/60%本段
				var frac2: float = [0.25, 0.40, 0.60][si]
				var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
				for o in _enemies_of(src):
					if o != tgt and _on_line(tgt["pos"], dir, o["pos"], 40.0):
						_apply_damage_from(src, o, maxi(1, int(dmg * frac2)), Color("#ffd07a"), 0.0, false, true)
		src["eq_state"][iid] = stt

# 充能助手: 累加 amt, 达 cap → 清零(保留溢出)并触发 on_full.
func _eq_charge(stt: Dictionary, key: String, amt: float, cap: float, on_full: Callable) -> void:
	var v: float = float(stt.get(key, 0.0)) + amt
	if v >= cap:
		stt[key] = v - cap
		on_full.call()
	else:
		stt[key] = v

# 雷电法杖 026: 连锁闪电, 跳 4/5/6 个目标, 每跳 20/25/30 魔法真伤
func _eq_chain_lightning(src: Dictionary, si: int) -> void:
	var hops: int = [4, 5, 6][si]; var dmg: int = [20, 25, 30][si]
	var hit: Array = []
	var pool := _enemies_of(src)
	if pool.is_empty():
		return
	var cur = pool[randi() % pool.size()]
	var prev: Vector2 = src["pos"]
	for h in range(hops):
		if cur == null:
			break
		hit.append(cur)
		_bolt_line(prev, cur["pos"], Color("#bff0ff"))
		_apply_damage_from(src, cur, dmg, Color("#bff0ff"), 0.0, true, true)
		prev = cur["pos"]
		# 下一跳: 最近的未命中敌
		var nx = null; var bd := INF
		for o in _enemies_of(src):
			if o in hit: continue
			var dd: float = (o["pos"] - cur["pos"]).length_squared()
			if dd < bd: bd = dd; nx = o
		cur = nx

# 宽刃弯刀 009: 刃能满→命中目标所在直线(列)每敌真伤+物理, 该列仅1敌则×2/2.5/3
func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:
	var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	var line_targets: Array = []
	for o in _enemies_of(src):
		if _on_line(src["pos"], dir, o["pos"], 55.0):
			line_targets.append(o)
	var mult: float = ([2.0, 2.5, 3.0][si]) if line_targets.size() <= 1 else 1.0
	for o in line_targets:
		_apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#9bf0ff"), 0.0, true, true)
		_apply_damage_from(src, o, int(_atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#9bf0ff"), 0.0, false, true)
	_bolt_line(src["pos"], tgt["pos"] + dir * 200.0, Color("#9bf0ff"))

# 灼热火珊瑚 023(主动满法力): 对全体敌各施大量灼烧
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:
	_float_text(src["pos"] + Vector2(0, -70), "烈焰爆发!", Color("#ff7a33"))
	for o in _enemies_of(src):
		_apply_dot_stacks(o, "burn", 60, src)   # desc"对全体敌各施加60层灼烧"(各星同)
		_skill_ring(o["pos"], Color(1.0, 0.5, 0.2, 0.5), 44.0)

# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
func _eq_on_target(u: Dictionary, src: Dictionary, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_013", "p2eq_014":   # 受击硬化: +def/mr (cap20层); 013满层给护盾
				var cur: int = int(stt.get("harden_stacks", 0))
				if cur < 20:
					cur += 1
					var inc: float = float(stt.get("harden_inc", 1.0))
					u["base_def"] += inc; u["base_mr"] += inc
					_recalc_stats(u)
					stt["harden_stacks"] = cur
					if cur >= 20 and not bool(stt.get("harden_given", false)) and float(stt.get("harden_shield", 0.0)) > 0.0:
						stt["harden_given"] = true
						_grant_shield(u, float(stt["harden_shield"]))
			"p2eq_015":   # 荆棘海胆: 反伤真伤 + 施流血给攻击者
				if src.get("alive", false) and src["side"] != u["side"]:
					var refl: float = float(dmg) * float(stt.get("reflect_pct", 0.10))
					if refl >= 1.0:
						_raw_lose(src, refl)
					# desc"对攻击者施 2/2.5/3 层流血"; reflect_bleed 存的就是层数
					_apply_dot_stacks(src, "bleed", maxi(1, roundi(float(stt.get("reflect_bleed", 2.0)))), u)
		u["eq_state"][iid] = stt

# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
func _eq_on_dodge(u: Dictionary) -> void:
	for e in u.get("equips", []):
		if str(e["id"]) == "p2eq_046":   # 幽灵墨鱼: 闪避→永久护盾
			var stt: Dictionary = u["eq_state"].get("p2eq_046", {})
			_grant_shield(u, float(stt.get("ghost_shield", 30.0)))

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_006":   # 千刃风暴: 一排剑穿过全体敌 (70/100/400+0.8/1.3/4.0×ATK 物理)
				var flat: int = [70, 100, 400][si]; var sc: float = [0.8, 1.3, 4.0][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, sc, o) + flat, Color("#dfe8ff"), 0.0, false, true)
				_skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.5), 120.0)
			"p2eq_007":   # 锈蚀阔剑: 斩最近敌一横排(朝向直线)+自护盾(本次总伤%)
				var dir: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var tot := 0
				for o in _enemies_of(u):
					if _on_line(u["pos"], dir, o["pos"], 55.0):
						var dd: int = _atk_dmg(u, [0.5, 0.8, 1.1][si], o) + [20, 35, 60][si]
						_apply_damage_from(u, o, dd, Color("#ffe08a"), 0.0, false, true); tot += dd
				_grant_shield(u, tot * [0.5, 0.75, 1.0][si])
			"p2eq_008":   # 双穿珊瑚刺: 对最远敌 (1/1.2/1.5×ATK物 + 8/12/18%目标maxHP魔)
				var far = null; var fd := -1.0
				for o in _enemies_of(u):
					var dd2: float = (o["pos"] - u["pos"]).length_squared()
					if dd2 > fd: fd = dd2; far = o
				if far != null:
					_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ffe08a"), 0.0, false, true)
					_apply_damage_from(u, far, int(far["maxHp"] * [0.08, 0.12, 0.18][si]), Color("#bfe9ff"), 0.0, true, true)
			"p2eq_011":   # 饮血护符坠: 连斩5/6/8次随机敌 (衰减), 溢出治疗→护盾(已由lifesteal属性近似)
				var n: int = [5, 6, 8][si]
				var es := _enemies_of(u)
				for k in range(n):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					var decay: float = pow(0.85, k)
					_apply_damage_from(u, o, int((_atk_dmg(u, [0.5, 0.7, 1.0][si], o) + [40, 50, 70][si]) * decay), Color("#ff8aa0"), 0.33, false, true)
			"p2eq_014":   # 深海堡垒甲(主动): 汲取全敌 0.8/1.0/1.5×(def+mr)魔伤, 每汲取回血
				var k2: float = [0.8, 1.0, 1.5][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(k2 * (u["def"] + u["mr"])), Color("#bfe9ff"), 0.0, true, true)
					_heal(u, [40, 65, 130][si])
			"p2eq_022":   # 余烬燃油瓶: 对最近敌施加灼烧(真火)
				var t2 = _nearest_enemy(u)
				if t2 != null:
					# desc"(20/35/60+10/15/20%ATK)层灼烧 +「真火」5秒"; 真火→灼烧 tick 转真实
					var tf: int = maxi(1, roundi([20, 35, 60][si] + [0.10, 0.15, 0.20][si] * u["atk"]))
					_apply_dot_stacks(t2, "burn", tf, u)
					t2["true_fire_until"] = _t + 5.0
			"p2eq_028":   # 冰霜冻露瓶: 对最近敌40/60/100魔伤+冰寒(减速)3回合
				var t3 = _nearest_enemy(u)
				if t3 != null:
					_apply_damage_from(u, t3, [40, 60, 100][si], Color("#bfe9ff"), 0.0, true, true)
					t3["slow_until"] = _t + EQ_TICK * 3.0
			"p2eq_030":   # 迷你水晶球A: 沿一列(穿过最近敌直线)2/2/3段水晶光束+叠层引爆
				var t4 = _nearest_enemy(u)
				if t4 != null:
					var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
					for _seg in range([2, 2, 3][si]):
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir2, o["pos"], 50.0):
								_apply_damage_from(u, o, [30, 35, 40][si], Color("#c9b0ff"), 0.0, true, true)
								_eq_crystal_stack(u, o, si)
					_bolt_line(u["pos"], t4["pos"] + dir2 * 200.0, Color("#c9b0ff"))
			"p2eq_031":   # 迷你水晶球B: 对全体敌各20/25/30魔伤+叠层引爆
				for o in _enemies_of(u):
					_apply_damage_from(u, o, [20, 25, 30][si], Color("#c9b0ff"), 0.0, true, true)
					_eq_crystal_stack(u, o, si)
			"p2eq_039":   # 竹制弓箭: 充能内→强化攻击(随机敌 25/30/35+20%maxHP魔)+自回血+永久+maxHP
				var stt2: Dictionary = u["eq_state"].get("p2eq_039", {})
				if int(stt2.get("bamboo_charges", 0)) > 0:
					stt2["bamboo_charges"] = int(stt2["bamboo_charges"]) - 1
					var t5 = _nearest_enemy(u)
					if t5 != null:
						_apply_damage_from(u, t5, [25, 30, 35][si] + int(u["maxHp"] / HP_MULT * 0.20), Color("#a8ffb0"), 0.0, true, true)
					_heal(u, u["maxHp"] * 0.20)
					var grow: float = [90.0, 95.0, 100.0][si] * HP_MULT
					u["maxHp"] += grow; u["hp"] += grow
					_float_text(u["pos"] + Vector2(0, -70), "生长!", Color("#39d353"))
					u["eq_state"]["p2eq_039"] = stt2
			"p2eq_048":   # 黄铜手铳: 射4/5/6发, 每发命中朝向直线首敌 0.5/0.54/0.6×ATK
				var dir3: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				for _b in range([4, 5, 6][si]):
					var ft = _eq_first_in_line(u, dir3, 36.0)
					if ft != null:
						_apply_damage_from(u, ft, _atk_dmg(u, [0.5, 0.54, 0.6][si], ft), Color("#ffd07a"), 0.0, false, true)
			"p2eq_049":   # 连发弩: 对每名较远半数敌(后排)连射1/2/3发, 按已损血加伤
				for o in _eq_farthest_enemies(u, true):
					var lost: float = clampf((1.0 - o["hp"] / o["maxHp"]) / 0.3, 0.0, 1.0)
					var sc2: float = lerpf(0.8, 1.3, lost)
					for _r in range([1, 2, 3][si]):
						_apply_damage_from(u, o, _atk_dmg(u, sc2, o), Color("#ffd07a"), 0.0, false, true)
			"p2eq_050":   # 幽灵加特林: 20/30/60发随机分布, 每发0.1/0.12/0.14×ATK+永久减甲
				for _g in range([20, 30, 60][si]):
					var es2 := _enemies_of(u)
					if es2.is_empty(): break
					var o = es2[randi() % es2.size()]
					_apply_damage_from(u, o, _atk_dmg(u, [0.1, 0.12, 0.14][si], o), Color("#d0ffff"), 0.0, false, true)
					o["base_def"] = maxf(0.0, o["base_def"] - [1.0, 2.0, 3.0][si]); _recalc_stats(o)
			"p2eq_051":   # 激光手枪: 朝向直线首敌1.5/2.0/2.8×ATK+流血, 身后50%
				var dir4: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var first = _eq_first_in_line(u, dir4, 50.0)
				if first != null:
					_apply_damage_from(u, first, _atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
					# desc"施加 0.5/0.5/0.6×ATK 流血"
					_apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
					for o in _enemies_of(u):
						if o != first and _on_line(first["pos"], dir4, o["pos"], 50.0):
							_apply_damage_from(u, o, _atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
			"p2eq_053":   # 霰弹贝古: 扇形12/14/18发, 每发0.22×ATK, 被8+发命中→眩晕
				var hitc: Dictionary = {}
				for _s in range([12, 14, 18][si]):
					var es3 := _enemies_of(u)
					if es3.is_empty(): break
					var o = es3[randi() % es3.size()]
					_apply_damage_from(u, o, _atk_dmg(u, 0.22, o), Color("#ffd07a"), 0.0, false, true)
					hitc[o] = int(hitc.get(o, 0)) + 1
				for o in hitc:
					if int(hitc[o]) >= 8: _freeze(o, EQ_TICK)
			"p2eq_057":   # 狙击长管: 对最低血%敌沿途敌2/3/7×ATK, 击杀则再开(上限12)
				_eq_sniper(u, si, 0)
			"p2eq_010":   # 激光长刃: 横扫一列(朝向直线), 命中1则竖斩; 回血
				var t6 = _nearest_enemy(u)
				if t6 != null:
					var dir5: Vector2 = (t6["pos"] - u["pos"]).normalized()
					var tot2 := 0; var cnt := 0
					for o in _enemies_of(u):
						if si == 2 or _on_line(u["pos"], dir5, o["pos"], 55.0):   # 3★全体
							var dd3: int = _atk_dmg(u, [1.2, 2.5, 5.0][si], o) + [100, 200, 2000][si]
							_apply_damage_from(u, o, dd3, Color("#9bf0ff"), 0.0, false, true); tot2 += dd3; cnt += 1
					if cnt == 1:   # 只命中1 → 竖斩追加
						_apply_damage_from(u, t6, _atk_dmg(u, [1.2, 2.5, 5.0][si], t6), Color("#9bf0ff"), 0.0, false, true)
					_heal(u, tot2 * [0.35, 0.8, 1.0][si])

# 水晶叠层 (A/B共用): 满3引爆 14/17/20%maxHP魔伤
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv := _add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		_consume_stacks(o, "p2crystal")
		_apply_damage_from(src, o, int(o["maxHp"] * [0.14, 0.17, 0.20][si]), Color("#c9b0ff"), 0.0, true, true)

# 狙击长管 057: 递归开枪
func _eq_sniper(u: Dictionary, si: int, depth: int) -> void:
	if depth >= 12:
		return
	var low = null; var lv := INF
	for o in _enemies_of(u):
		var p: float = o["hp"] / o["maxHp"]
		if p < lv: lv = p; low = o
	if low == null:
		return
	var dir: Vector2 = (low["pos"] - u["pos"]).normalized()
	_bolt_line(u["pos"], low["pos"], Color("#ffe08a"))
	var killed := false
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			_apply_damage_from(u, o, _atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ffe08a"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper(u, si, depth + 1)

# ============================================================================
#  on-kill (处决/击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, _victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		if str(e["id"]) == "p2eq_004":   # 暴君之牙: 处决后回40血(实时无龟能回点→回血)
			_heal(killer, 40.0)
			_float_text(killer["pos"] + Vector2(0, -64), "处决!", Color("#ff6b6b"))

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 / 玩偶小熊
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_033":   # 复活海螺: 阵亡→原位变小虫 (复用 _spawn_summon)
				var worm = _spawn_summon(u, "worm", [150.0, 200.0, 300.0][si] * HP_MULT, [20.0, 30.0, 40.0][si])
				if worm != null:
					worm["pos"] = u["pos"]; worm["node"].position = u["pos"]
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂 (简化: 在虫的 tick 走, 这里标记 owner)
						worm["worm_split"] = true
				_float_text(u["pos"] + Vector2(0, -40), "复活海螺!", Color("#c0ffd0"))
			"p2eq_035":   # 黄铜齿轮: 死亡→每层折2深海币 (深海币局内有 → 叠 meta 收入; 仅玩家左队计入)
				var gears: int = int(stt.get("gears", 0))
				if gears > 0 and u["side"] == "left":
					var gs = get_node_or_null("/root/GameState")
					if gs != null and gs.get("meta_deepsea_coins") != null:
						gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + gears * 2)
			"p2eq_034":   # 玩偶小熊: 🚧 简化 — 阵亡时召唤大熊 (250生命/50攻击)
				var bear = _spawn_summon(u, "bear", 250.0 * HP_MULT, 50.0)
				if bear != null:
					bear["eq_state"] = {}; bear["equips"] = []

# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
func _eq_check_hp_threshold(u: Dictionary) -> void:
	if u.get("hp50_fired", false) or u["hp"] > u["maxHp"] * 0.5 or not u["alive"]:
		return
	var fired := false
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_044":   # 深海项链: 首次<50%回血
				_heal(u, u["maxHp"] * [0.12, 0.27, 0.40][si]); fired = true
			"p2eq_045":   # 珍珠耳环: 首次<50%回血+发火球(魔伤+灼烧)
				_heal(u, u["maxHp"] * [0.15, 0.29, 0.65][si])
				var balls: int = [1, 1, 2][si]
				var es := _enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_apply_damage_from(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), Color("#ff7a33"), 0.0, true, true)
					_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # desc未给层数→默认公式 max(1,round(ATK×0.67))
				fired = true
	if fired:
		u["hp50_fired"] = true

# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
func _eq_tick(u: Dictionary, delta: float) -> void:
	u["eq_timer"] = u.get("eq_timer", 0.0) + delta
	if u["eq_timer"] < EQ_TICK:
		return
	u["eq_timer"] = 0.0
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_001":   # 锈蚀短剑: 每周期劈砍最近敌
				var t = _nearest_enemy(u)
				if t != null:
					_apply_damage_from(u, t, _atk_dmg(u, [0.6, 0.75, 1.0][si], t) + int([40, 60, 100][si] * u["crit"]), Color("#ffe08a"), 0.0, false, true)
			"p2eq_012":   # 龟苓膏块: 每周期自护盾
				_grant_shield(u, [30.0, 40.0, 55.0][si])
			"p2eq_016":   # 铁壁盾: 每周期全队(含自己)护盾
				for o in _allies_of(u):
					_grant_shield(o, [15.0, 20.0, 25.0][si])
			"p2eq_018":   # 守护贝壳: 每周期自回血
				_heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])
			"p2eq_019":   # 海葵药膏: 每周期奶自己+最低血友军
				_heal(u, [30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si])
				var low = _lowest_hp_ally(u)
				if low != null and low != u:
					_heal(low, [30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si])
			"p2eq_020":   # 哑铃: 每周期+锻炼层(+maxHP/HP) + 向最近敌扔哑铃(5/7/10%自身maxHP物)
				var gain: float = [20.0, 25.0, 30.0][si] * HP_MULT
				u["maxHp"] += gain; u["hp"] += gain; _update_bars(u)
				var t2 = _nearest_enemy(u)
				if t2 != null:
					_apply_damage_from(u, t2, int(u["maxHp"] / HP_MULT * [0.05, 0.07, 0.10][si]), Color("#ffe08a"), 0.0, false, true)
			"p2eq_021":   # 守护贝母: 每周期连接攻击最高友军→给护盾+净化(伤害转移简化掉)
				var best = null; var ba := -1.0
				for o in _allies_of(u):
					if o["atk"] > ba: ba = o["atk"]; best = o
				if best != null:
					_grant_shield(best, [40.0, 60.0, 90.0][si])
					best["dots"] = []; best["dot_stacks"] = {}   # 净化负面 (简化: 清DoT层数)
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙沿随机有敌直线(同列扫射)
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 每周期降1/2/3道雷各电击随机敌 1×ATK真伤
				for _d in range([1, 2, 3][si]):
					var es := _enemies_of(u)
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_bolt_line(Vector2(o["pos"].x, ARENA.position.y), o["pos"], Color("#bff0ff"))
					_apply_damage_from(u, o, int(u["atk"]), Color("#bff0ff"), 0.0, true, true)
			"p2eq_027":   # 电棍: 每周期电击随机敌+眩晕, 消耗1层(0停)
				if int(stt.get("baton_charges", 0)) > 0:
					var es2 := _enemies_of(u)
					if not es2.is_empty():
						stt["baton_charges"] = int(stt["baton_charges"]) - 1
						var o = es2[randi() % es2.size()]
						_apply_damage_from(u, o, [30, 40, 50][si], Color("#bff0ff"), 0.0, true, true)
						_freeze(o, EQ_TICK)
			"p2eq_035":   # 黄铜齿轮: 每周期+1/2/3层
				stt["gears"] = int(stt.get("gears", 0)) + [1, 2, 3][si]
			"p2eq_017":   # 不沉之锚: ⚠简化 — 每周期击飞+眩晕最近敌, 造((0.4/0.6/3.0)×(def+mr)+15/25/70%maxHP)物理
				var at = _nearest_enemy(u)
				if at != null:
					_apply_damage_from(u, at, int([0.4, 0.6, 3.0][si] * (u["def"] + u["mr"]) + at["maxHp"] * [0.15, 0.25, 0.70][si]), Color("#9be7ff"), 0.0, false, true)
					_knockback(u, at, 60.0); _freeze(at, EQ_TICK)
			"p2eq_036":   # 温泉蛋: 孵化进度(每周期+5), 满100→全队均摊护盾(一次)
				stt["incub"] = float(stt.get("incub", 0.0)) + 5.0
				if float(stt["incub"]) >= 100.0 and not bool(stt.get("incub_given", false)):
					stt["incub_given"] = true
					var allies := _allies_of(u)
					var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
					for o in allies:
						_grant_shield(o, per)
					_float_text(u["pos"] + Vector2(0, -70), "孵化!", Color("#ffe9a8"))
			"p2eq_042":   # 涟漪药剂: 每周期全队回已损血3/6/10%
				for o in _allies_of(u):
					_heal(o, (o["maxHp"] - o["hp"]) * [0.03, 0.06, 0.10][si])
			"p2eq_043":   # 海浪护符: 每周期+1巨浪层, 满→横排扫敌我(友盾+减甲敌)
				stt["wave"] = int(stt.get("wave", 0)) + 1
				if int(stt["wave"]) >= [3, 2, 2][si]:
					stt["wave"] = 0
					for o in _allies_of(u):
						_grant_shield(o, [40.0, 95.0, 120.0][si]); o["base_def"] += [2, 3, 5][si]; o["base_mr"] += [2, 3, 5][si]; _recalc_stats(o)
					for o in _enemies_of(u):
						_apply_damage_from(u, o, [60, 110, 200][si], Color("#9be7ff"), 0.0, true, true)
						o["base_def"] = maxf(0.0, o["base_def"] - [2, 3, 5][si]); o["base_mr"] = maxf(0.0, o["base_mr"] - [2, 3, 5][si]); _recalc_stats(o)
			"p2eq_052":   # 左轮: 每周期向随机敌射1发(150/310/1200+3/5/9×ATK), 子弹0停
				if int(stt.get("revolver_bullets", 0)) > 0:
					var es3 := _enemies_of(u)
					if not es3.is_empty():
						stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
						var o = es3[randi() % es3.size()]
						_fire_bolt_from(u, o, _atk_dmg(u, [3.0, 5.0, 9.0][si], o) + [150, 310, 1200][si], Color("#ffd07a"))
			"p2eq_037":   # 蛋糕蜡烛: 3阶段循环 (熄灭/微弱回血/燃烧灼烧横排)
				var ph: int = int(stt.get("candle", 0))
				stt["candle"] = (ph + 1) % 3
				if ph == 1:   # 微弱: 回血+相邻友半数
					_heal(u, [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si])
				elif ph == 2:   # 燃烧: 随机敌横排魔伤+灼烧
					var t3 = _nearest_enemy(u)
					if t3 != null:
						var dir: Vector2 = (t3["pos"] - u["pos"]).normalized()
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir, o["pos"], 55.0):
								_apply_damage_from(u, o, [20, 30, 44][si] + int(u["atk"] * [0.5, 0.7, 1.0][si]), Color("#ff7a33"), 0.0, true, true)
								_apply_dot_stacks(o, "burn", [20, 30, 40][si], u)   # desc"施加20/30/40层灼烧"
			"p2eq_038":   # 信号放大器: 每周期刷新本回合增伤buff (10~16/25~40/70~80%)
				var lo: Array = [0.10, 0.25, 0.70]; var hi: Array = [0.16, 0.40, 0.80]
				var amp: float = randf_range(lo[si], hi[si])
				# 简化: 折成 atk buff 持续到下次刷新 (EQ_TICK 后)
				_buff(u, "atk", amp, true, EQ_TICK + 0.1)
			"p2eq_040":   # FPGA板: 每周期抽1/2/4个状态当回合生效 (简化几类)
				for _k in range([1, 2, 4][si]):
					match randi() % 4:
						0: _heal(u, u["maxHp"] * 0.05); u["base_def"] += 2; u["base_mr"] += 2; _recalc_stats(u)
						1: u["base_atk"] += 5; u["lifesteal"] += 0.04; _recalc_stats(u)
						2: _buff(u, "atk", 0.15, true, EQ_TICK + 0.1)
						3: _buff(u, "def", 0.25, true, EQ_TICK + 0.1)   # 简化: 减伤≈加甲
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				for o in _enemies_of(u):
					if _t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						_fire_bolt_from(u, o, _atk_dmg(u, [1.5, 3.0, 9.0][si], o) + [130, 190, 600][si], Color("#ffd07a"))
						_apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * 0.1)), u)   # desc"施加流血"无明确层数→沿用 0.1×ATK 层
		u["eq_state"][iid] = stt
	# 复活海螺3★ 小虫分裂 (简化: worm 单位每周期空位分裂一只)
	if u.get("worm_split", false) and _count_summons(u["side"], "worm") < 4:
		var nw = _spawn_summon(u, "worm", u["maxHp"], u["atk"])
		if nw != null:
			nw["eq_state"] = {}; nw["equips"] = []; nw["worm_split"] = true

func _count_summons(side: String, kind: String) -> int:
	var c := 0
	for o in _units:
		if o.get("is_summon", false) and o["side"] == side and o["alive"] and str(o.get("name", "")) == kind:
			c += 1
	return c

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es := _enemies_of(u)
	if es.is_empty():
		return
	var anchor = es[randi() % es.size()]
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	_bolt_line(u["pos"], anchor["pos"] + dir * 200.0, Color("#ff7a33"))
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [50, 120, 1500][si], Color("#ff7a33"), 0.0, true, true)
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)   # desc未给层数→默认公式 max(1,round(ATK×0.67))
	for o in _allies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_heal(o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [70, 150, 1000][si])

# 雷电/光束/狙击 弹道线 (临时直线 VFX)
func _bolt_line(a: Vector2, b: Vector2, col: Color) -> void:
	var line := Line2D.new()
	line.add_point(a); line.add_point(b)
	line.width = 3.0; line.default_color = col; line.z_index = 9
	add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.25)
	tw.tween_callback(line.queue_free)
