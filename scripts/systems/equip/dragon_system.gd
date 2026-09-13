class_name DragonSystem
extends RefCounted
## 龙·烈焰召唤系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 类内 _dragon_* 名字不变→内部互调零改动;外部名加 battle. 前缀。无状态成员。

## 【024 龙蛋·喷火龙】火柱是一条直线, 两侧各多宽算命中。
const BREATH_HALF_W := 88.0   # 半宽(码)

## ★火柱扫到谁那一刻才对谁结算 —— 挂在**游戏钟**上的待结算队列(不是 tween)。
##   每项: {at=结算时刻(battle._t), foe=是敌是友, u/o/si, expl/burn}
var _pending: Array = []

var battle

func _init(b) -> void:
	battle = b

# 蓄力后爆发: 召唤火爆+震屏+预警线+放龙+结算(同线敌=魔法伤+灼烧, 同线友=回血)
func _dragon_unleash(u: Dictionary, si: int, start: Vector2, end: Vector2, dir: Vector2, total: float, dur: float) -> void:
	_dragon_summon_burst(start)
	battle._shake(0.12)
	_spawn_fire_dragon(start, end, dur)
	var expl: Texture2D = load("res://assets/sprites/vfx/fx_explosion.png")
	var burn_tex: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	# 火柱扫到谁那一刻才对谁结算(非召唤即一次性算完): 延时=火柱沿线到达该单位的时间
	## ★★2026-09-13: 这两段原来是 `tween_interval` + `tween_callback` 延时投递 ——
	##   **tween 走未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5)。
	##   门禁 verify_dragon_breath ④「走真入口后敌人确实掉血」**实测 0 伤害**, 当场确诊。
	##   改成挂进**游戏钟队列** `_pending`, 由 tick(dt) 按 battle._t 到点结算 ——
	##   与 031 水晶球B 同一条路(「结算走 sim 时钟, 不走 tween」)。
	for o in battle._targeting._enemies_of(u):
		if battle._on_line(start, dir, o["pos"], BREATH_HALF_W):
			var d_e: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			_pending.append({"at": battle._t + d_e, "foe": true,
				"u": u, "o": o, "si": si,
				"expl": expl, "burn": burn_tex})
	for o in battle._targeting._allies_of(u):
		if battle._on_line(start, dir, o["pos"], BREATH_HALF_W):
			var d_a: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			_pending.append({"at": battle._t + d_a, "foe": false,
				"u": u, "o": o, "si": si})

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

## 放龙(纯演出) —— 2026-09-13 从主文件搬来: CLAUDE.md §5「不在 _sim_step 调用链上的不进主文件」,
##   顺带给下面那条【游戏钟队列】腾出主文件的一行接线(arch_budget 台账只减不增)。
func _spawn_fire_dragon(start2d: Vector2, end2d: Vector2, dur: float) -> void:
	var dragon_tex: Texture2D = load("res://assets/sprites/vfx/dragon-fly.png")   # PixelLab 5帧振翅
	if dragon_tex != null:
		var d := Sprite3D.new()
		d.texture = dragon_tex
		d.hframes = 5
		d.frame = 0
		d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		d.shaded = false
		d.transparent = true
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		d.flip_h = (end2d.x < start2d.x)               # 素材朝右; 往左飞则翻转
		d.pixel_size = (215.0 * battle.WS) / (float(maxi(1, int(dragon_tex.get_width()))) / 5.0)
		d.position = battle._world_pos(start2d, 2.9)          # 龙在天上(高空)
		battle._world.add_child(d)
		d.modulate = Color(1, 1, 1, 0)                 # 从召唤火里淡入现身
		var tfade = battle._reg_tween()
		tfade.tween_property(d, "modulate:a", 1.0, 0.22)
		var tw = battle._reg_tween()
		tw.tween_method(_dragon_fly_step.bind(d, start2d, end2d), 0.0, 1.0, dur)
		tw.tween_callback(d.queue_free)
		var tf = battle._reg_tween()                       # 振翅: 乒乓循环5帧(~4次/秒)
		tf.tween_method(_dragon_flap_frame.bind(d), 0.0, 32.0 * dur, dur)
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	var perp: Vector2 = (end2d - start2d).orthogonal().normalized()
	for i in range(1, 19):                           # 燃烧带: 沿线真像素火, 大小/横向随机=有机火带(非机械等距), 龙飞到才点燃
		var f: float = float(i) / 19.0
		var jit: Vector2 = perp * randf_range(-28.0, 28.0)
		battle._delayed_ground_fire(start2d.lerp(end2d, f) + jit, burn, randf_range(74.0, 128.0), f * dur * 0.9)
	_dragon_mouth_jet(start2d, end2d, dur)           # 龙嘴喷火(从嘴喷向地面)


## 每帧由主场景的 sim tick 调(与 _crystal_sys.tick 同一处)。
## ★用 `battle._t`(钳制后的游戏钟), 不用 delta 累加 —— 单位在动, 到点就结算。
func tick(_dt: float) -> void:
	if _pending.is_empty():
		return
	var i: int = _pending.size() - 1
	while i >= 0:
		var it: Dictionary = _pending[i]
		if battle._t < float(it["at"]):
			i -= 1; continue
		_pending.remove_at(i)
		## kind=unleash 是【前摇到点放龙】; 其余是【火柱扫到某人那一刻的结算】
		if str(it.get("kind", "")) == "unleash":
			_dragon_unleash(it["u"], int(it["si"]), it["start"],
				it["end"], it["dir"], float(it["total"]), float(it["dur"]))
			i -= 1
			continue
		var o: Dictionary = it["o"]
		if o.get("alive", false):
			if bool(it["foe"]):
				_dragon_hit_enemy(it["u"], o, int(it["si"]),
					it.get("expl", null), it.get("burn", null))
			else:
				_dragon_heal_ally(it["u"], o, int(it["si"]))
		i -= 1


## 前摇到点才真的放龙 —— 由 tick 按游戏钟触发(不是 tween)。
func schedule_unleash(u: Dictionary, si: int, start: Vector2, end: Vector2,
		dir: Vector2, total: float, dur: float, windup: float) -> void:
	_pending.append({"at": battle._t + windup, "kind": "unleash",
		"u": u, "si": si, "start": start, "end": end,
		"dir": dir, "total": total, "dur": dur})

