class_name GamblerSystem
extends RefCounted
## 赌徒龟技能系统
## 类内名不变;外部名加 battle.

## ★赌神数值单一事实源(用户2026-07-28 第三轮加强)。文案在 data/pets.json。
const MULTI_ASPD := 0.1667   # 多重打击再打一次的攻击间隔倍率(0.30→0.1667 = ~3.3×→~6×攻速)
const JOKER_DMG := 2.0       # 万能牌: ×ATK 物理 (1.0→2.0)
const JOKER_SHIELD := 1.0    # 万能牌: ×ATK 永久护盾 (0.25→1.0)

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
		# ★★2026-08-03 用户拍板:【连击不触发剑士】。
		#   赌神本身就是"云顶剑士式连击", 而剑羁绊的【剑士】也是连击 ——
		#   两者相乘会让赌神拿满剑达到普通龟的 2.1 倍(实测 576% vs 272%)。
		#   这里标记"下一次普攻是连击产生的", swordsman_system.on_basic_attack 读它并跳过。
		#   ⚠ 只跳过【连击那几发】—— 赌神正常节奏的第一发照常触发剑士, 它不该被开除出剑队。
		#   ⚠ 赌注 barrage(_gambler_bet_multi) 不走 _basic_attack(直接结算伤害) ⇒ 本来就不触发, 无需处理。
		u["_chained_atk"] = true
		return maxf(0.06, u["atk_interval"] * MULTI_ASPD)   # 快攻速再打 (用户2026-07-28: ~3.3×→~6×攻速)
	u["multi_chance"] = base_ch                       # 没中→重置回基础(含命运之轮0.60/赌注+0.20), 等下一次普攻
	u["_chained_atk"] = false                         # 链断了 → 下一次是正常普攻, 照常触发剑士
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
	battle._damage._heal(u, u["atk"] * 0.3)   # ★每触发一次多重打击回0.3ATK生命(用户2026-07-14·赌注期间回血本)
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
		battle._damage._apply_damage_from(u, tgt, dmg, dcol, 0.0, is_true)
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
			battle._damage._apply_damage_from(u, tgt, dmg, dcol, 0.0, is_true)   # ★命中才跳伤害(穿透金/物理红)
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
			battle._vfx._float_text(u["pos"] + Vector2(0, -64), "♠ 攻+3 血+10", Color("#ffd93d"))
		1:
			u["base_def"] = float(u["base_def"]) + 1.0; u["base_mr"] = float(u["base_mr"]) + 1.0
			battle._vfx._float_text(u["pos"] + Vector2(0, -64), "♥ 护甲+1 魔抗+1", Color("#ff5b6b"))
		2:
			u["crit"] = float(u["crit"]) + 0.02; u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 1.0
			battle._vfx._float_text(u["pos"] + Vector2(0, -64), "♦ 暴击+2% 护穿+1", Color("#ff9f43"))
		_:
			battle._damage._buff(u, "lifesteal", 0.005, false, 9999.0); u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + 0.02
			battle._vfx._float_text(u["pos"] + Vector2(0, -64), "♣ 吸血+0.5% 攻速+2%", Color("#5be08a"))
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
		battle._damage._buff(u, "lifesteal", 0.005, false, 9999.0); u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + 0.02
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
				battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, JOKER_DMG, tgt), Color("#ff4444"))   # ★命中才跳伤害
				battle._damage._buff(tgt, "atk", -0.15, true)                                        # 减攻也命中才上
			_gambler_pop(tp, th, Color(1.0, 0.85, 0.35, 0.95))        # 命中金光
			_gambler_pop(tp, th + 0.25, Color(1.0, 0.30, 0.30, 0.8)))  # 减攻红标
	else:   # 无牌素材兜底: 即时结算目标伤害+减攻
		if tgt.get("alive", false):
			battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, JOKER_DMG, tgt), Color("#ff4444"))
			battle._damage._buff(tgt, "atk", -0.15, true)
	battle._shield_dome(u)                                                   # 护盾罩
	_gambler_pop(u["pos"], float(u.get("height", 0.0)), Color(0.30, 1.0, 0.5, 0.85))   # 回血绿

func _sk_gambler_bet(u: Dictionary, tgt: Dictionary) -> void:    # 赌神龟·赌注(用户封板·100龟能): 需当前生命>40%; 消耗当前生命40%→7段物理砸目标(共≈0.4×当前生命); 施放3秒多重概率+20%
	if tgt == null or not tgt.get("alive", false): return
	if u["hp"] < u["maxHp"] * 0.40:                              # ★低血模式(用户2026-07-14): 血不够押本→转而回8%maxHp + 3秒多重+20%(不甩牌·不消耗血)
		battle._damage._heal(u, u["maxHp"] * 0.08)
		u["gambler_bet_until"] = battle._t + 3.0
		battle._vfx._flash(u, Color(0.4, 1.7, 0.6))                         # 绿闪(求稳回血)
		battle._skill_ring(u["pos"], Color(0.3, 1.0, 0.5, 0.55), 54.0)   # 绿环
		_gambler_pop(u["pos"], float(u.get("height", 0.0)), Color(0.3, 1.0, 0.5, 0.85))   # 回血绿
		return
	var cost: float = u["hp"] * 0.40
	u["hp"] = maxf(1.0, u["hp"] - cost)
	battle._vfx._flash(u, Color(1.7, 0.4, 0.4))                            # HP牺牲红闪(押上血本)
	var per: int = maxi(1, int(cost / 7.0))
	u["gambler_bet_until"] = battle._t + 3.0                           # 3秒多重概率+20%(见_gambler_multi_cd·回补钩)
	battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.55), 54.0)
	for i in range(7):                                         # 7张牌barrage(错峰0.11s·命中才跳伤害·每张触发多重打击B·扣'七段')
		# ★用户2026-07-28 报的 bug: 这里原来只传了 roll_multi=true, 而 _gambler_throw_hit 的
		#   is_true 默认值是 true → 七段全走【真实伤害】穿透双抗, 与"七段物理伤害"的设定不符。
		#   显式传 false 走物理。(另一处调用 :37 本来就显式传了 false,false, 只有这行漏了)
		battle._pending_shots.append({"delay": float(i) * 0.11, "fn": func() -> void: _gambler_throw_hit(u, tgt, per, true, false), "src": u})

func _sk_gambler_fate_wheel(u: Dictionary) -> void:             # 赌神龟·命运之轮(用户封板·80龟能): 抽1花色永久加属性(♠攻+3&血+10/♥护甲魔抗各+1/♦暴击+2%&护穿+1/♣吸血+0.5%&攻速+2%)·跨场累积=存GameState.gambler_wheel_stacks(本大轮累积·切轮重置·方案B·用户2026-07-09)
	var _suit = battle._battle_rng.randi() % 4
	if u.get("side", "") == "left":   # 跨场累积: 抽中即记录(只玩家赌神写本大轮累积·敌/ghost镜像不写·切轮reset)
		var _sk: String = ["spade", "heart", "diamond", "club"][_suit]
		GameState.gambler_wheel_stacks[_sk] = int(GameState.gambler_wheel_stacks.get(_sk, 0)) + 1
	# ★流程优化(用户2026-07-14): 放技→抽取阶段锁龟能+转盘动画→花色落定后才跳文字+实装属性→龟能自动解锁
	var SPIN = 1.0
	u["energy_lock_until"] = battle._t + SPIN + 0.15   # 抽取阶段锁龟能(转盘转完+缓冲·到期自动解锁·_tick_skill_cd判)
	_gambler_wheel_vfx(u, _suit)                # 花色老虎机转盘spin(SPIN秒·EASE_OUT减速落定)
	var uu: Dictionary = u
	var suit: int = _suit
	battle._pending_shots.append({"delay": SPIN, "fn": func() -> void:   # 花色落定那一刻才结算
		if not uu.get("alive", false): return
		_gambler_apply_wheel_suit(uu, suit)
		, "src": u})

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌: 丢1张牌=1段2.0A物理(用户2026-07-09"只造成1段伤害"·2026-07-28 1.0→2.0)+自身1.0A护盾(0.25→1.0)+回5%maxHp+目标攻-15%
	battle._damage._grant_shield(u, u["atk"] * JOKER_SHIELD)   # 自身护盾/回血即时(施法者)
	battle._damage._heal(u, u["maxHp"] * 0.05)
	_gambler_wild_vfx(u, tgt)   # 丢小丑牌; ★目标伤害+减攻在牌命中回调里结算(命中才跳伤害·用户2026-07-14)

