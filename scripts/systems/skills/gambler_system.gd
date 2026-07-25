class_name GamblerSystem
extends RefCounted
## 赌徒龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# gambler 多重打击(云顶剑士式连击): 普攻命中后掷概率→中则快攻速再打一发(连锁每次概率×0.8递减), 没中→回正常普攻冷却+重置
func _gambler_multi_cd(u: Dictionary) -> float:
	var base_ch: float = float(u.get("multi_base", 0.40))     # 命运之轮选中→0.60; 否则0.40
	if battle._t < float(u.get("gambler_bet_until", 0.0)):
		base_ch += 0.20                                       # 赌注放技→3秒内临时+20%(封顶示例0.80)
	var ch: float = float(u.get("multi_chance", base_ch))
	if battle._battle_rng.randf() < ch:
		u["multi_chance"] = ch * 0.8                  # 递减: 每次连锁×0.8
		return maxf(0.12, u["atk_interval"] * 0.30)   # 快攻速再打 (~3.3×攻速; F5可调)
	u["multi_chance"] = base_ch                       # 没中→重置回基础(含命运之轮0.60/赌注+0.20), 等下一次普攻
	return u["atk_interval"]

# 当前多重打击概率(命运之轮0.60/否则0.40 + 赌注放技3秒内+0.20)
func _gambler_bet_ch(u: Dictionary) -> float:
	var ch = float(u.get("multi_base", 0.40))
	if battle._t < float(u.get("gambler_bet_until", 0.0)): ch += 0.20
	return ch

# B(用户2026-07-14): 赌注每张牌命中掷多重打击→中则额外甩一发普攻(1.0A)+继续以×0.8递减连锁(滚雪球)
# B(用户2026-07-14): 赌注每张牌命中掷多重打击→中则额外甩一发普攻(1.0A)+继续以×0.8递减连锁(滚雪球)
func _gambler_bet_multi(u: Dictionary, tgt: Dictionary, ch: float) -> void:
	if not u.get("alive", false) or tgt == null or not tgt.get("alive", false): return
	if battle._battle_rng.randf() >= ch: return
	battle._heal(u, u["atk"] * 0.3)   # ★每触发一次多重打击回0.3ATK生命(用户2026-07-14·赌注期间回血本)
	var bdmg: int = battle._atk_dmg(u, 1.0, tgt)   # 额外一发=普攻1.0A
	battle._pending_shots.append({"delay": 0.09, "fn": func() -> void:
		_gambler_throw_hit(u, tgt, bdmg, false, false)   # 甩基础牌(普攻物理红·非穿透·自身不再掷·递归在下句续)
		_gambler_bet_multi(u, tgt, ch * 0.8)         # 连锁×0.8递减
		, "src": u})

# 赌神: 甩1张牌→命中结算dmg+金光pop (赌注barrage用·命中才跳伤害; roll_multi=每张触发多重打击)
# 赌神: 甩1张牌→命中结算dmg+金光pop (赌注barrage用·命中才跳伤害; roll_multi=每张触发多重打击)
func _gambler_throw_hit(u: Dictionary, tgt: Dictionary, dmg: int, roll_multi: bool = false, is_true: bool = true) -> void:
	if tgt == null or not tgt.get("alive", false): return
	var dcol: Color = Color("#ffd93d") if is_true else Color("#ff6b6b")   # 穿透金 / 普攻物理红
	var from3 = battle._world_pos(u["pos"], 1.0)
	var tp: Vector2 = tgt["pos"]
	var to3 = battle._world_pos(tp, 1.0)
	var th: float = float(tgt.get("height", 0.0))
	var t: Texture2D = load("res://assets/sprites/vfx/gambler-card.png")
	if t == null:
		battle._apply_damage_from(u, tgt, dmg, dcol, 0.0, is_true)
		if roll_multi: _gambler_bet_multi(u, tgt, _gambler_bet_ch(u))
		return
	var card = Sprite3D.new()
	card.texture = t; card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.billboard = BaseMaterial3D.BILLBOARD_DISABLED; card.shaded = false; card.transparent = true
	card.pixel_size = 1.0 / 54.0
	card.position = from3
	battle._world.add_child(card)
	var seg = to3 - from3
	var perp = Vector3(seg.z, 0.0, -seg.x)
	if perp.length() > 0.01: perp = perp.normalized()
	var arc = randf_range(0.7, 1.5)                 # 抛物线拱高(每张不同)
	var lat = randf_range(-1.0, 1.0)                # 侧向弧偏(每张不同→扇形散开)
	var ctw = battle._reg_tween()
	ctw.tween_method(func(f: float) -> void:
		if not is_instance_valid(card): return
		var pos = from3.lerp(to3, f)
		pos.y += arc * sin(PI * f)                    # 抛物线拱起(不再贴地直飞)
		pos += perp * lat * sin(PI * f)               # 侧向弧线(每张不同→扇形·不再直直)
		card.position = pos
		if battle._cam != null:
			var ct: Transform3D = card.global_transform
			ct.basis = battle._cam.global_transform.basis * Basis(Vector3(0, 0, 1), f * 11.0)
			card.global_transform = ct
		, 0.0, 1.0, 0.52)   # 0.34→0.52放慢(用户2026-07-14)
	ctw.tween_callback(func() -> void:
		if is_instance_valid(card): card.queue_free()
		if tgt.get("alive", false):
			battle._apply_damage_from(u, tgt, dmg, dcol, 0.0, is_true)   # ★命中才跳伤害(穿透金/物理红)
			if roll_multi: _gambler_bet_multi(u, tgt, _gambler_bet_ch(u))  # 每张牌触发多重打击(B)
		_gambler_pop(tp, th, Color(1.0, 0.85, 0.35, 0.9)))

# 命运之轮转盘: 花色♠♥♦♣老虎机式快转→减速→落定抽中花色+该色大爆
# 命运之轮转盘: 花色♠♥♦♣老虎机式快转→减速→落定抽中花色+该色大爆
func _gambler_wheel_vfx(u: Dictionary, suit: int) -> void:
	var suits = ["♠", "♥", "♦", "♣"]
	var scols = [Color("#ffd93d"), Color("#ff5b6b"), Color("#ff9f43"), Color("#5be08a")]
	var lbl = Label3D.new()
	lbl.text = "♠"
	lbl.font_size = 180
	lbl.pixel_size = 0.011
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 14
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.position = battle._world_pos(u["pos"], 3.7)   # 头顶更高(用户2026-07-14"再高一点")
	battle._world.add_child(lbl)
	var target = 12.0 + float(suit)           # 3整圈+落在suit(12%4=0→末位=suit)
	var tw = battle._reg_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(lbl):
			var idx = int(round(v)) % 4
			lbl.text = suits[idx]
			lbl.modulate = scols[idx]
		, 0.0, target, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 快转→减速落定
	tw.tween_callback(func() -> void:
		_gambler_pop(u["pos"], float(u.get("height", 0.0)) + 2.8, Color(scols[suit].r, scols[suit].g, scols[suit].b, 0.95))
		battle._skill_ring(u["pos"], Color(scols[suit].r, scols[suit].g, scols[suit].b, 0.65), 62.0))
	tw.tween_interval(0.55)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.3)
	tw.tween_callback(lbl.queue_free)

func _gambler_apply_wheel_suit(u: Dictionary, suit: int) -> void:   # 命运之轮落定实装: 加属性+跳文字(该花色色)
	match suit:
		0:
			u["base_atk"] = float(u["base_atk"]) + 3.0; u["maxHp"] += 10.0; u["hp"] += 10.0
			battle._float_text(u["pos"] + Vector2(0, -64), "♠ 攻+3 血+10", Color("#ffd93d"))
		1:
			u["base_def"] = float(u["base_def"]) + 1.0; u["base_mr"] = float(u["base_mr"]) + 1.0
			battle._float_text(u["pos"] + Vector2(0, -64), "♥ 护甲+1 魔抗+1", Color("#ff5b6b"))
		2:
			u["crit"] = float(u["crit"]) + 0.02; u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 1.0
			battle._float_text(u["pos"] + Vector2(0, -64), "♦ 暴击+2% 护穿+1", Color("#ff9f43"))
		_:
			battle._buff(u, "lifesteal", 0.005, false, 9999.0); u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + 0.02
			battle._float_text(u["pos"] + Vector2(0, -64), "♣ 吸血+0.5% 攻速+2%", Color("#5be08a"))
	battle._recalc_stats(u)

func _gambler_apply_wheel_stacks(u: Dictionary) -> void:   # 命运之轮跨场累积(方案B): 登场套用GameState本大轮已抽花色(切轮重置)·只玩家赌神调用
	var ws: Dictionary = GameState.gambler_wheel_stacks
	if ws.is_empty(): return
	for i in range(int(ws.get("spade", 0))):
		u["base_atk"] = float(u["base_atk"]) + 3.0; u["maxHp"] += 10.0; u["hp"] += 10.0
	for i in range(int(ws.get("heart", 0))):
		u["base_def"] = float(u["base_def"]) + 1.0; u["base_mr"] = float(u["base_mr"]) + 1.0
	for i in range(int(ws.get("diamond", 0))):
		u["crit"] = float(u["crit"]) + 0.02; u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 1.0
	for i in range(int(ws.get("club", 0))):
		battle._buff(u, "lifesteal", 0.005, false, 9999.0); u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + 0.02
	battle._recalc_stats(u)

# 赌神小型glow pop(缩放淡出·放慢放大更明显·用户2026-07-14)
# 赌神小型glow pop(缩放淡出·放慢放大更明显·用户2026-07-14)
func _gambler_pop(pos2d: Vector2, h: float, col: Color) -> void:
	var g = battle._glow_bb(pos2d, h + 0.5, 155.0, col)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 1.9, 0.55)
	tw.tween_property(g, "material_override:albedo_color", Color(col.r, col.g, col.b, 0.0), 0.55)
	tw.chain().tween_callback(g.queue_free)

# 万能牌特效: 丢发光小丑牌(旋转)→命中金光+减攻红标 + 施法者护盾罩+回血绿
# 万能牌特效: 丢发光小丑牌(旋转)→命中金光+减攻红标 + 施法者护盾罩+回血绿
func _gambler_wild_vfx(u: Dictionary, tgt: Dictionary) -> void:
	var t: Texture2D = load("res://assets/sprites/vfx/gambler-joker.png")
	if t != null:
		var card = Sprite3D.new()
		card.texture = t; card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		card.billboard = BaseMaterial3D.BILLBOARD_DISABLED; card.shaded = false; card.transparent = true
		card.pixel_size = 1.6 / 56.0   # 比普攻牌大(特殊技·放大更明显)
		var from3 = battle._world_pos(u["pos"], 1.0)
		var to3 = battle._world_pos(tgt["pos"], 1.0)
		card.position = from3
		battle._world.add_child(card)
		var tp: Vector2 = tgt["pos"]
		var th: float = float(tgt.get("height", 0.0))
		var ctw = battle._reg_tween()
		ctw.tween_method(func(f: float) -> void:
			if not is_instance_valid(card): return
			card.position = from3.lerp(to3, f)
			if battle._cam != null:
				var ct: Transform3D = card.global_transform
				ct.basis = battle._cam.global_transform.basis * Basis(Vector3(0, 0, 1), f * 9.0)   # 面向相机+滚转
				card.global_transform = ct
			, 0.0, 1.0, 0.62)   # 飞行0.35→0.62s放慢看清(用户2026-07-14)
		ctw.tween_callback(func() -> void:
			if is_instance_valid(card): card.queue_free()
			if tgt.get("alive", false):
				battle._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.0, tgt), Color("#ff4444"))   # ★命中才跳伤害
				battle._buff(tgt, "atk", -0.15, true)                                        # 减攻也命中才上
			_gambler_pop(tp, th, Color(1.0, 0.85, 0.35, 0.95))        # 命中金光
			_gambler_pop(tp, th + 0.25, Color(1.0, 0.30, 0.30, 0.8)))  # 减攻红标
	else:   # 无牌素材兜底: 即时结算目标伤害+减攻
		if tgt.get("alive", false):
			battle._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.0, tgt), Color("#ff4444"))
			battle._buff(tgt, "atk", -0.15, true)
	battle._shield_dome(u)                                                   # 护盾罩
	_gambler_pop(u["pos"], float(u.get("height", 0.0)), Color(0.30, 1.0, 0.5, 0.85))   # 回血绿
