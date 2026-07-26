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
	battle._vfx._hit_spark(target)
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

func _sk_lightning_barrage(u: Dictionary) -> void:             # 闪电龟·雷暴 (用户2026-07-15纠错重做: 原风暴云低压施法者脸上像帽子=离谱→改敌方阵型上空高处的大风暴云下雷)
	var es = battle._enemies_of(u)
	var center: Vector2 = u["pos"]                 # 风暴云中心=敌方阵型质心(雷暴"随机轰击敌方"→云在敌上空非施法者头顶)
	if not es.is_empty():
		center = Vector2.ZERO
		for e in es:
			center += e["pos"]
		center /= float(es.size())
	var cloud_h = 4.5                             # 敌上空高处(原3.4太低压脸·5.4又顶出画面顶→4.5)
	var cloud = Sprite3D.new()
	var ctex = load("res://assets/sprites/skills/lightning-2.png")
	if ctex != null:
		cloud.texture = ctex
		cloud.pixel_size = 5.2 / float(maxi(1, ctex.get_height()))   # 大风暴云(原3.4→5.2)
	cloud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cloud.shaded = false
	cloud.transparent = true
	cloud.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cloud.position = battle._world_pos(center, cloud_h)
	cloud.modulate = Color(0.55, 0.66, 0.92, 0.0)  # 冷色压暗成阴沉风暴云(非亮图标)·淡入
	battle._world.add_child(cloud)
	var tin = battle._reg_tween()
	tin.tween_property(cloud, "modulate:a", 0.96, 0.22)
	var tw = battle._reg_tween()
	for i in range(20):                            # 20道天降落雷(每0.075s·稍慢更可读)
		tw.tween_callback(battle._barrage_bolt.bind(u, cloud_h))
		tw.tween_interval(0.075)
	tw.tween_callback(battle._barrage_cloud_fade.bind(cloud))

func _sk_lightning_shield(u: Dictionary) -> void:              # 闪电龟·雷盾 (用户2026-07-07: 3ATK护盾5秒, 盾在时反击0.1A魔法叠电击=见_apply_damage_from; 2026-07-15补以雷电包裹自身VFX)
	battle._grant_shield(u, u["atk"] * 3.0, 5.0)   # 雷盾5秒(与反击窗口thunder_shield_until同步·封板)
	u["thunder_shield_until"] = battle._t + 5.0
	battle._skill_ring(u["pos"], Color(0.45, 0.85, 1.0, 0.5), 50.0)
	battle._aura_vfx("res://assets/sprites/skills/lightning-3.png", u, 58.0, Color(0.45, 0.85, 1.0, 0.5), 5.0)   # 脚下电爆光环随身5秒
	var etex: Texture2D = load("res://assets/sprites/vfx/electric-zap.png")   # 以雷电包裹自身: 3道电弧环绕身体5秒
	if etex != null:
		var n = 3
		for i in range(n):
			var s = Sprite3D.new()
			s.texture = etex
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false; s.transparent = true
			s.modulate = Color(0.72, 0.92, 1.0, 0.92)
			s.pixel_size = (42.0 * battle.WS) / float(maxi(1, etex.get_height()))
			s.position = battle._world_pos(u["pos"], float(u.get("height", 0.0)) + 0.7)
			battle._world.add_child(s)
			battle._follow_vfx.append({"spr": s, "unit": u, "h": 0.7, "orbit_r": 0.30, "orbit_a": float(i) * TAU / float(n), "orbit_spd": 6.0})
			var tw = battle._reg_tween()
			tw.tween_interval(4.7)                                  # 环绕5秒后淡出(sprite free→_follow_vfx自动剔除)
			tw.tween_property(s, "modulate:a", 0.0, 0.3)
			tw.tween_callback(s.queue_free)

func _sk_lightning_surge(u: Dictionary, tgt: Dictionary) -> void: # 闪电龟·涌动 ✅
	if tgt != null and tgt.get("alive", false):
		battle._apply_damage_from(u, tgt, int(u["atk"] * 1.23), Color("#4dabf7"), 0.0, true)   # 立即1次被动电击=真实(原误为魔法)
	u["shock_boost_until"] = battle._t + 5.0      # 5秒内被动电击真伤+50%(窄化; 原误为通用+50%攻击+stray层)
	u["shock_boost_pct"] = 0.5
	battle._skill_ring(u["pos"], Color(0.45, 0.85, 1.0, 0.5), 52.0)
	battle._aura_vfx("res://assets/sprites/skills/lightning-3.png", u, 54.0, Color(0.3, 0.67, 0.97, 0.5), 5.0)   # 涌动增伤电流光环5秒(标示buff激活期)
	battle._vfx._hit_spark(u)                                                                                          # 自身电流上涌

