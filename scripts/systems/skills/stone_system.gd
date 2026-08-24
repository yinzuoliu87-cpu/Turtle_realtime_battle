class_name StoneSystem
extends RefCounted
## 石头龟技能系统
## 类内名不变;外部名加 battle.

## ★★2026-08-22 文案根除: 嘲讽这一组原来全是 `_sk_stone_taunt` 里的裸字面量。
## 【岩石护盾】全队盾 + 自身双抗, 两者时长不同。
## 【坚壁(被动)】周期性永久涨护甲(有上限) + 受击按双抗反弹。
## ★这些原来散在【两个别的文件】: 涨护甲在主场景 `_tick_periodic_passive`, 反伤在 battle_damage。
const BULWARK_IV := 2.5          # 每几秒涨一次
const BULWARK_GAIN_DIV := 6.0    # 每次涨 = 开局护甲 ÷ 它
const BULWARK_CAP_MULT := 2.0    # 累积上限 = 开局护甲 ×
const REFLECT_BASE := 0.05       # 反弹基础比例
const REFLECT_PER_DEF := 0.01    # 每点护甲再 +
const REFLECT_MR_WEIGHT := 0.5   # 魔抗按此权重折算成护甲
## 【磐石之躯】岩层被动 + 横排冲击波。
const ROCK_LAYER_CAP := 30       # 岩层上限
const ROCK_DR_PER_LAYER := 0.01  # 每层伤害减免
const ROCK_SIZE_PER_LAYER := 0.02  # 每层体型 +
const ROCK_WAVE_DEF_COEF := 0.5  # 冲击波 = ×护甲
const ROCK_WAVE_MR_COEF := 0.5   # + ×魔抗
const ROCK_WAVE_PER_LAYER := 0.04  # 再 ×(1 + 此值 × 岩层数)
const ROCK_WAVE_STUN := 2.0      # 必定眩晕(秒)
const RS_ATK_COEF := 1.0         # 全队盾 = ×【石头龟】ATK
const RS_MAXHP_PCT := 0.06       # + ×【石头龟】最大生命
const RS_SHIELD_SEC := 4.0       # 盾持续(秒)·持盾期锁龟能
const RS_RESIST_UP := 0.20       # 自身护甲与魔抗各 +(百分比)
const RS_RESIST_SEC := 5.0       # 双抗持续(秒)
const TAUNT_RADIUS := 500.0      # 嘲讽半径(码)
const TAUNT_SEC := 4.0           # 嘲讽 / 自身减伤 的持续(秒)
const TAUNT_SHIELD_COEF := 1.0   # 自身永久护盾 = ×ATK (dur=0, 不随嘲讽消失)
const TAUNT_DR_PER_DEF := 0.5    # 减伤% = 此系数 × 护甲(再 ×1%)
const TAUNT_DR_CAP := 0.50       # 减伤上限
const SLAM_DELAY := 3.5          # 嘲讽开始后第几秒砸地(砸完龟能才重新充能)
const SLAM_RADIUS := 400.0       # 砸地半径(码)
const SLAM_ATK_COEF := 1.0       # 砸地 ×ATK 魔法
const SLAM_KNOCK_SEC := 1.2      # 砸地击飞滞空(秒)

var battle

func _init(b) -> void:
	battle = b

func _sk_stone_rock_shield(u: Dictionary) -> void:               # 石头龟·岩石护盾(用户设计: 合并岩石护甲+磐石·100龟能): 全队盾1A+6%maxHp(4秒) + 自身双抗+20%5秒
	for o in battle._targeting._allies_of(u):
		battle._damage._grant_shield(o, u["atk"] * RS_ATK_COEF + u["maxHp"] * RS_MAXHP_PCT, RS_SHIELD_SEC)   # 全队盾=1×石头ATK+6%【石头龟】最大生命(用户2026-07-11: 0.2A+5%→1A+6%)·每友军等量·4秒
		o["rock_shield_until"] = battle._t + RS_SHIELD_SEC                          # 标记"石头岩石护盾"来源: LoL式六棱屏障VFX + 锁龟能(持盾期不充能), 盾破/到期即释放(用户2026-07-11)
		battle._skill_ring(o["pos"], Color(0.79, 0.64, 0.42, 0.45), 46.0)
	battle._damage._buff(u, "def", RS_RESIST_UP, true, RS_RESIST_SEC)   # 自身护甲+20%(pct·5秒)
	battle._damage._buff(u, "mr", RS_RESIST_UP, true, RS_RESIST_SEC)    # 自身魔抗+20%

func _rock_chunk_erupt(pos2d: Vector2) -> void:   # 岩石破土冒起(石棕灰)→短留→碎(仿 _gold_chunk_erupt·换石色)
	var tex: Texture2D = load("res://assets/sprites/vfx/gold-chunk.png")
	if tex == null: return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(randf_range(0.5, 0.62), randf_range(0.44, 0.54), randf_range(0.36, 0.44), 0.0)   # 石棕灰·起始透明
	var sc: float = randf_range(0.8, 1.35)
	spr.pixel_size = (1.5 * sc) / float(maxi(1, int(tex.get_height())))
	var wh: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = battle._world_pos(pos2d, wh * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.55, 0.0)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(0.16)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(spr.queue_free)

func _sk_stone_taunt(u: Dictionary) -> void:                    # 石头龟·嘲讽(用户设计·120龟能): 500码敌4秒硬嘲讽 + 自身1A永久盾 + 0.5×护甲减伤4秒 + 将结束砸地(400码1A魔法+击飞1.2s)
	var victims: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(u["pos"]) <= TAUNT_RADIUS:
			victims.append(o)
	battle._taunt(u, victims, TAUNT_SEC)
	battle._damage._grant_shield(u, u["atk"] * TAUNT_SHIELD_COEF)          # 1A永久盾(dur=0·不随嘲讽消失)
	u["stone_dr_until"] = battle._t + TAUNT_SEC            # 0.5×护甲%减伤4秒
	u["energy_lock_until"] = battle._t + SLAM_DELAY        # 砸击(3.5s)之后龟能才重新充能(用户#8"砸击后龟能才重新充能")
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, TAUNT_RADIUS, Color(0.86, 0.68, 0.42, 0.42), TAUNT_SEC)   # 500码仇恨光环(嘲讽4秒·贴地跟随·用户#8)
	var uu = u
	var slam = func() -> void:                # 蓄力3.5s→砸地(在4秒嘲讽内·K'Sante Q3式)
		if not uu.get("alive", false): return
		battle._burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", uu["pos"], 220.0)   # 砸地岩石冲击(用户2026-07-06"像地面猛砸")
		for o in battle._targeting._enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(uu["pos"]) <= SLAM_RADIUS:
				battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, SLAM_ATK_COEF, o, true), Color("#c8a878"))
				if not o.get("airborne", false):
						battle._damage._knockback(uu, o, 80.0, 3.6111)   # 击飞【1.2秒·峰高6.5】(用户2026-07-11) — vy=6.0×3.6111=21.667
						o["knock_g"] = -36.111            # 配重力-36.111→ 滞空=2×21.667/36.111=1.2s·峰高=21.667²/(2×36.111)=6.5(解耦时长与抛高)
		battle._shake(0.06)
	battle._pending_shots.append({"delay": SLAM_DELAY, "fn": slam, "src": u})

func _sk_rock_shockwave(u: Dictionary) -> void:                  # 石头龟·岩石之躯 主动: 前方带状(±90)岩脊向前破土推进, (0.5DEF+0.5MR)×(1+4%岩层)物理 + 【必中眩晕2s】+ 击退60
#   (2026-07-19订正: 头注释原写"1%×层眩晕1.5s"是旧版, 用户2026-07-11已改成必中2秒, 见下方 battle._damage._stun 那行); 伤害随波前经过逐个同步(用户2026-07-11补VFX·原=只1个130px环)
	var tgt = battle._targeting._acquire_target(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp = Vector2(-dir.y, dir.x)
	var layers: int = int(u.get("rock_layers", 0))
	var origin: Vector2 = u["pos"]
	var uu = u
	var windup = 0.16                                       # 起手踏地时长
	var wave_spd = 900.0                                    # 岩脊波前推进速度(码/秒)
	# ── 起手: 石头抬身猛踏(_slam_voff 抬→砸) ──
	var smt = battle._reg_tween()
	smt.tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.0, 0.55, 0.1).set_ease(Tween.EASE_OUT)
	smt.chain().tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.55, 0.0, 0.06).set_ease(Tween.EASE_IN)
	smt.chain().tween_callback(func(): uu["_slam_voff"] = Vector3.ZERO)
	# ── 踏地瞬间(windup 后): 震屏+顿帧+脚下碎石+起手环 ──
	var wf = func() -> void:
		battle._shake(battle.JUICE_SHAKE_HEAVY); battle._hitstop = maxf(battle._hitstop, 0.05)
		battle._vfx._impact_particles(origin, 0.0)
		battle._burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", origin, 210.0, 0.06)
		battle._skill_ring(origin, Color(0.79, 0.64, 0.42, 0.6), 120.0)
	battle._pending_shots.append({"delay": windup, "src": u, "fn": wf})
	# ── 岩脊沿 dir 向前破土推进(铺满带宽·波前渐进) ──
	var reach = 820.0
	var step = 44.0
	var d = 34.0
	while d < reach:
		var cp: Vector2 = origin + dir * d
		var dl: float = windup + d / wave_spd
		var pa: Vector2 = cp + perp * randf_range(-32.0, 32.0)
		var fa = func() -> void: _rock_chunk_erupt(pa)
		battle._pending_shots.append({"delay": dl, "src": u, "fn": fa})
		if randf() < 0.7:
			var pb: Vector2 = cp + perp * randf_range(-86.0, 86.0)
			var fb = func() -> void: _rock_chunk_erupt(pb)
			battle._pending_shots.append({"delay": dl, "src": u, "fn": fb})
		d += step
	# ── 伤害: 前方带状(几何不变)·随波前经过逐个同步结算 ──
	var dmgv: int = int((u["def"] * ROCK_WAVE_DEF_COEF + u["mr"] * ROCK_WAVE_MR_COEF) * (1.0 + ROCK_WAVE_PER_LAYER * layers))
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - origin
		if rel.dot(dir) <= 0.0: continue                     # 只前方
		if absf(rel.dot(perp)) > 90.0: continue              # 带宽~180
		var oo = o
		var hit_delay: float = windup + maxf(0.0, rel.dot(dir)) / wave_spd
		var hf = func() -> void:
			if not oo.get("alive", false): return
			battle._damage._apply_damage_from(uu, oo, dmgv, Color("#c8a878"))
			battle._damage._stun(oo, ROCK_WAVE_STUN, "_sk_rock_shockwave")   # 命中即眩晕2秒(用户2026-07-11: 除击退外必附2s眩晕·原1%×层概率改必中·头顶通用眩晕圈由_update_stun_vfx画)
			battle._damage._knockback(uu, oo, 60.0)
			_rock_chunk_erupt(oo["pos"])                     # 命中点额外破土
			battle._vfx._flash(oo)
		battle._pending_shots.append({"delay": hit_delay, "src": u, "fn": hf})

