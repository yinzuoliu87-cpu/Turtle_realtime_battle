class_name DragonSystem
extends RefCounted
## 龙·烈焰召唤系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 类内 _dragon_* 名字不变→内部互调零改动;外部名加 battle. 前缀。无状态成员。

## 【024 龙蛋·喷火龙】火柱是一条直线, 两侧各多宽算命中。
const BREATH_HALF_W := 88.0   # 半宽(码)

var battle

func _init(b) -> void:
	battle = b

# 蓄力后爆发: 召唤火爆+震屏+预警线+放龙+结算(同线敌=魔法伤+灼烧, 同线友=回血)
func _dragon_unleash(u: Dictionary, si: int, start: Vector2, end: Vector2, dir: Vector2, total: float, dur: float) -> void:
	_dragon_summon_burst(start)
	battle._shake(0.12)
	battle._spawn_fire_dragon(start, end, dur)
	var expl: Texture2D = load("res://assets/sprites/vfx/fx_explosion.png")
	var burn_tex: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	# 火柱扫到谁那一刻才对谁结算(非召唤即一次性算完): 延时=火柱沿线到达该单位的时间
	for o in battle._targeting._enemies_of(u):
		if battle._on_line(start, dir, o["pos"], BREATH_HALF_W):
			var d_e: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			var twe = battle._reg_tween()
			twe.tween_interval(d_e)
			twe.tween_callback(_dragon_hit_enemy.bind(u, o, si, expl, burn_tex))
	for o in battle._targeting._allies_of(u):
		if battle._on_line(start, dir, o["pos"], BREATH_HALF_W):
			var d_a: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			var twa = battle._reg_tween()
			twa.tween_interval(d_a)
			twa.tween_callback(_dragon_heal_ally.bind(u, o, si))

# 火柱扫到敌人那一刻: 魔法伤害+灼烧+金爆+着火 (同步, 数字跟火柱一起)
# 火柱扫到敌人那一刻: 魔法伤害+灼烧+金爆+着火 (同步, 数字跟火柱一起)
func _dragon_hit_enemy(u: Dictionary, o: Dictionary, si: int, expl: Texture2D, burn: Texture2D) -> void:
	if not o.get("alive", false):
		return
	# 龙蛋削弱二(用户 2026-07-29): (50/120/1500 + 0.7/1.0/2.0×ATK) → (45/80/120 + 1×ATK)。
	# ★系数拍平成 1.0 是关键: 原来 ★3 的 2.0 会把这件装备自己加的 +300 攻【再翻倍打回去】, 自我放大。
	var base_e: float = u["atk"] * 1.0 + float([45, 80, 120][si])
	battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, base_e, o, true), Color("#c86bff"), 0.0, false, true)   # 魔法伤害
	battle._damage._apply_dot_stacks(o, "burn", [20, 35, 50][si], u)   # 灼烧 30/45/70 → 20/35/50(用户2026-07-29; 更早 2026-07-23 从 0.67×ATK 改成固定层)
	if expl != null:
		battle.play_sheet_vfx(o["pos"], expl, 8, 150.0, 0.5, 0.7)
	battle._ground_fire(o["pos"], burn, 82.0)

# 火柱扫到友军那一刻: 回血+绿治疗环
# 火柱扫到友军那一刻: 回血+绿治疗环
func _dragon_heal_ally(u: Dictionary, o: Dictionary, si: int) -> void:
	if not o.get("alive", false):
		return
	# 治疗同削弱(用户 2026-07-29): (70/150/1000 + 0.7/1.0/2.0×ATK) → 与伤害同口径 (45/80/120 + 1×ATK)
	battle._damage._heal(o, u["atk"] * 1.0 + float([45, 80, 120][si]))
	battle._skill_ring(o["pos"], Color(0.45, 1.0, 0.55, 0.55), 46.0)

# 前摇: 召唤点火球聚大变亮 + 火花从外向内收束 + 脉动环 (蓄力感)
# 前摇: 召唤点火球聚大变亮 + 火花从外向内收束 + 脉动环 (蓄力感)
func _dragon_windup(pos2d: Vector2) -> void:
	var tex := VfxTex._make_fire_glow_tex()
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	var orb := Sprite3D.new()
	orb.texture = tex
	orb.modulate = Color(1.0, 0.62, 0.22, 0.0)
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orb.shaded = false
	orb.transparent = true
	orb.pixel_size = (26.0 * battle.WS) / tw_w
	orb.position = battle._world_pos(pos2d, 1.3)
	battle._world.add_child(orb)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "pixel_size", (155.0 * battle.WS) / tw_w, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(orb, "modulate:a", 1.0, 0.5)
	tw.chain().tween_callback(orb.queue_free)
	for k in range(8):
		battle._windup_spark(pos2d, TAU * float(k) / 8.0)
	battle._skill_ring(pos2d, Color(1.0, 0.5, 0.2, 0.55), 66.0)

func _dragon_fly_step(p: float, spr: Sprite3D, start2d: Vector2, end2d: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = battle._world_pos(start2d.lerp(end2d, p), lerpf(2.9, 3.5, clampf(p * 2.5, 0.0, 1.0)) + sin(p * PI) * 0.18)

func _dragon_flap_frame(v: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		var seq := [0, 1, 2, 3, 4, 3, 2, 1]           # 乒乓: 翅上→下→上
		spr.frame = seq[int(v) % 8]

# 召唤火爆: 携带者处火环扩散+火焰爆闪+火花, 龙从中现身(修"凭空出现啥也没有")
# 召唤火爆: 携带者处火环扩散+火焰爆闪+火花, 龙从中现身(修"凭空出现啥也没有")
func _dragon_summon_burst(pos2d: Vector2) -> void:
	battle._skill_ring(pos2d, Color(1.0, 0.55, 0.2, 0.75), 105.0)
	battle._skill_ring(pos2d, Color(1.0, 0.85, 0.45, 0.6), 64.0)
	var tex := VfxTex._make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.8, 0.45, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	spr.pixel_size = (80.0 * battle.WS) / tw_w
	spr.position = battle._world_pos(pos2d, 1.1)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "pixel_size", (255.0 * battle.WS) / tw_w, 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(spr.queue_free)
	battle._vfx._impact_particles(pos2d, 1.0)

# 龙嘴喷火: 沿飞行线, 从龙嘴(前方)持续喷真像素火落向地面 = "喷火"读感
# 龙嘴喷火: 沿飞行线, 从龙嘴(前方)持续喷真像素火落向地面 = "喷火"读感
func _dragon_mouth_jet(start2d: Vector2, end2d: Vector2, dur: float) -> void:
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	if burn == null:
		return
	var n := 30
	for i in range(n):
		var p: float = float(i) / float(n)
		var col_pos: Vector2 = start2d.lerp(end2d, p)               # 火柱落点=龙嘴正下方(在掠射线上)
		var top_h: float = lerpf(2.9, 3.5, clampf(p * 2.5, 0.0, 1.0)) + 0.25   # 火柱顶=龙嘴高度
		var tw = battle._reg_tween()
		tw.tween_interval(p * dur * 0.95)
		tw.tween_callback(battle._spawn_fire_pillar.bind(burn, col_pos, top_h))

# 一根竖直火柱: 从地面到龙嘴, 同一x竖向叠火焰(=直的), 底大顶小, 短暂显现再淡