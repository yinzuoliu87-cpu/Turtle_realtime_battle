class_name LightningSystem
extends RefCounted
## 闪电龟技能系统
## 类内簇函数名不变;外部名加 battle. 前缀。

var battle

func _init(b) -> void:
	battle = b

func _lightning_basic(u: Dictionary, tgt: Dictionary) -> void:
	# 建链(顺序最近未连): 打1 → 1找最近2 → 2找最近3, 最多连锁2跳
	var chain: Array = [tgt]
	var prev: Dictionary = tgt
	for _i in range(2):
		var nxt = null
		var bestd := 260.0                       # 连锁射程上限(像素)
		for o in battle._pick_enemies_of(u):
			if battle._arr_has_unit(chain, o) or not o["alive"]:
				continue
			var dd: float = (o["pos"] - prev["pos"]).length()
			if dd < bestd:
				bestd = dd; nxt = o
		if nxt == null:
			break
		chain.append(nxt); prev = nxt
	# 顺序错峰劈: 彩虹→1, 1→2, 2→3, 每跳隔0.07s(看得见跳跃) + 锯齿电弧
	var tw = battle._reg_tween()
	var from_pos: Vector2 = u["pos"]
	var fr := 1.0
	for i in range(chain.size()):
		tw.tween_callback(_lightning_hop.bind(u, from_pos, chain[i], fr, i))
		tw.tween_interval(0.07)
		from_pos = chain[i]["pos"]
		fr *= 0.6

func _lightning_electric(u: Dictionary, target: Dictionary) -> void:   # 叠1层电击; 满8引爆(天降+清零)
	var lv = battle._add_stack(target, "electric", 1, 8)
	if lv >= 8:
		battle._consume_stacks(target, "electric")
		battle._apply_damage_from(u, target, battle._shock_dmg(u), Color("#4dabf7"), 0.0, true)
		_lightning_strike(target["pos"], Color("#cdfaff"))
		battle._skill_ring(target["pos"], Color(0.72, 0.95, 1.0, 0.75), 76.0)
		battle._shake(battle.JUICE_SHAKE_LIGHT)   # 被动8层引爆=目标本地天降落雷+环, 不拉施法者→目标连线(用户2026-07-15)

func _lightning_hop(u: Dictionary, from_pos: Vector2, target: Dictionary, fr: float, hop_i: int) -> void:
	if not target.get("alive", false):
		return
	_lightning_arc(from_pos, target["pos"], Color("#aef0ff"))   # 锯齿电弧
	battle._apply_damage_from(u, target, battle._atk_dmg(u, 0.6 * fr, target, true), Color("#4dabf7"))
	battle._hit_spark(target)
	if hop_i > 0:
		_lightning_electric(u, target)   # 连锁每跳也叠电击层(主目标由_on_basic_hit叠, 避免重复)

func _lightning_strike(pos2d: Vector2, _col: Color, world_h: float = 2.6) -> void:   # 天降闪电 common-lightning-strike 5帧(9fps); world_h=雷高度(越大雷越大, 中心≈world_h*0.478); 4.6时中心≈2.2=飘字高度→伤害跳在雷中间
	var tex := load("res://assets/sprites/vfx/common-lightning-strike.png")
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = world_h / float(maxi(1, tex.get_height()))
	spr.position = battle._world_pos(pos2d, world_h * 0.478)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	for f in range(5):                              # 5帧 9fps(~0.06s/帧)
		tw.tween_callback(battle._lstrike_frame.bind(spr, f))
		tw.tween_interval(1.0 / 9.0)   # 9fps = 回合制 common-lightning-strike 同播放时长(5帧0.556s)
	tw.tween_callback(spr.queue_free)

func _lightning_arc(a2d: Vector2, b2d: Vector2, col: Color) -> void:   # 锯齿状电弧(zigzag折线, 像真闪电劈过去)
	var n := 6
	var perp := (b2d - a2d).orthogonal().normalized()
	var prev := a2d
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var mid := a2d.lerp(b2d, t)
		if i < n:
			mid += perp * battle._juice_rng.randf_range(-16.0, 16.0)
		battle._bolt_line(prev, mid, col)
		prev = mid

# 伤害公式 (1:1 复用 2D battle._atk_dmg): base×scale ×暴击 ×(100/(100+resist-pierce))
# 伤害核心: 暴击(封顶100%溢出转暴伤×1.5) → 有效护甲/魔抗(先%后flat,可负) → 减伤倍率(K=40,负防增伤) → 增伤/减伤