class_name TwoHeadSystem
extends RefCounted
## 双头龟技能系统
## 类内名不变;外部名加 battle.

## ★双头数值单一事实源(用户2026-07-28)。文案在 data/pets.json，改这里要同步改那边。
const DISRUPT_TRUE := 2.0   # 精神干扰(远程形态): ×ATK 真实伤害 (原 1.0×ATK 魔法)
## ★★2026-08-22 文案根除: 双生(被动)的这一组原来散在 `_two_head_after_cast` /
##   `_two_head_enhanced_basic` / `_two_head_retreat` 的函数体里, 文案又各手写一遍。
## 【切近战时的属性变化】(基准都是 ATK)
const MELEE_HP_COEF := 2.5       # 最大生命 +
const MELEE_DEF_COEF := 0.25     # 护甲 +
const MELEE_MR_COEF := 0.25      # 魔抗 +
const MELEE_ATK_PENALTY := 0.30  # 攻击力 −
const MELEE_SHIELD_COEF := 1.1   # 切近战时立即获得的护盾 = ATK ×
## 【两形态射程】
const RANGED_RANGE := 400.0
const MELEE_RANGE := 70.0
## 【切换强化: 下一发普攻】
const ENH_RANGED_COEF := 1.4     # 切远程 → 额外 ×ATK 物理
const ENH_ARMOR_DOWN := 0.25     # 并使目标 −% 护甲
const ENH_MELEE_COEF := 0.6      # 切近战 → 额外 ×ATK 魔法
const ENH_SHIELD_COEF := 1.1     # 并给自己 ×ATK 护盾
const ENH_SEC := 4.0             # 破甲/护盾持续秒
## 【切远程的滑退距离】
const RETREAT_DIST := 200.0

var battle

func _init(b) -> void:
	battle = b

func _two_head_apply_melee(u: Dictionary, on: bool) -> void:
	var buffed: bool = u.get("two_melee_buffed", false)
	if on and not buffed:
		var a: float = u["base_atk"]
		u["two_melee_buffed"] = true
		u["_th_hp"] = a * MELEE_HP_COEF; u["_th_def"] = a * MELEE_DEF_COEF; u["_th_mr"] = a * MELEE_MR_COEF; u["_th_atk"] = a * MELEE_ATK_PENALTY   # 近战生命加成 1.5→2.5×ATK(用户2026-07-29 第四轮·攻击惩罚 0.30 不动)
		u["maxHp"] += u["_th_hp"]; u["hp"] += u["_th_hp"]
		u["base_def"] += u["_th_def"]; u["base_mr"] += u["_th_mr"]
		u["base_atk"] = maxf(1.0, u["base_atk"] - u["_th_atk"])
		battle._recalc_stats(u); battle._damage._grant_shield(u, a * MELEE_SHIELD_COEF)
	elif not on and buffed:
		u["two_melee_buffed"] = false
		u["maxHp"] = maxf(1.0, u["maxHp"] - float(u.get("_th_hp", 0.0)))
		u["hp"] = minf(u["hp"], u["maxHp"])
		u["base_def"] = maxf(0.0, u["base_def"] - float(u.get("_th_def", 0.0)))
		u["base_mr"] = maxf(0.0, u["base_mr"] - float(u.get("_th_mr", 0.0)))
		u["base_atk"] += float(u.get("_th_atk", 0.0))
		battle._recalc_stats(u)

func _sk_two_head_strike(u: Dictionary, tgt) -> void:            # 双头·技能一 form-variant(用户2026-07-11重设计): 远程=灵能冲击(大紫炮弹→碰第一敌爆炸200码AOE 1A+10%maxHp物理) / 近战=锤击(跳起落地砸·1.4A物理+50%伤害盾4s)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	if u["melee"]:
		_two_head_hammer(u, tgt)                                # 近战锤击: 跳起→落在目标→地面锤击
	else:
		var dir: Vector2 = tgt["pos"] - u["pos"]
		if dir.length() < 1.0: dir = Vector2.RIGHT
		_two_head_cannon(u, u["pos"], dir.normalized())         # 远程灵能冲击: 大紫炮弹

# 双头·灵能冲击炮弹(用户2026-07-11): 大紫炮弹朝目标方向飞(射程2000·760码/s)→碰第一敌(46码)爆炸→200码内敌 1A+10%目标maxHp 物理
# 双头·灵能冲击炮弹(用户2026-07-11): 大紫炮弹朝目标方向飞(射程2000·760码/s)→碰第一敌(46码)爆炸→200码内敌 1A+10%目标maxHp 物理
func _two_head_cannon(u: Dictionary, from2d: Vector2, dir: Vector2) -> void:
	var spr = Sprite3D.new()
	spr.texture = VfxTex._make_glow_texture()
	spr.modulate = Color(0.78, 0.5, 1.0, 0.96)              # 灵能紫
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.pixel_size = (66.0 * battle.WS) / float(maxi(1, spr.texture.get_width()))   # 大炮弹
	spr.position = battle._world_pos(from2d, 1.1)
	battle._world.add_child(spr)
	var traveled = 0.0
	var pos = from2d
	var hit = null
	while is_instance_valid(battle) and traveled < 2000.0 and u.get("alive", false) and battle.is_inside_tree():
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		traveled = minf(2000.0, traveled + 760.0 * battle.get_process_delta_time())
		pos = from2d + dir * traveled
		pos.x = clampf(pos.x, battle.ARENA.position.x, battle.ARENA.end.x)
		pos.y = clampf(pos.y, battle.ARENA.position.y, battle.ARENA.end.y)
		if is_instance_valid(spr): spr.position = battle._world_pos(pos, 1.1)
		for o in battle._targeting._enemies_of(u):
			if o.get("alive", false) and pos.distance_to(o["pos"]) <= 46.0:
				hit = o; break
		if hit != null: break
	if is_instance_valid(spr): spr.queue_free()
	_two_head_cannon_boom(u, pos)

func _two_head_cannon_boom(u: Dictionary, at2d: Vector2) -> void:
	battle._shake(0.13)
	var g = VfxTex._make_glow_texture()
	var sp = Sprite3D.new()
	sp.texture = g; sp.modulate = Color(0.82, 0.56, 1.0, 0.95)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
	sp.pixel_size = (58.0 * battle.WS) / float(maxi(1, g.get_width()))
	sp.position = battle._world_pos(at2d, 0.85)
	battle._world.add_child(sp)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(sp, "pixel_size", sp.pixel_size * 3.4, 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(sp.queue_free)
	battle._skill_ring(at2d, Color(0.76, 0.55, 1.0, 0.9), 200.0)       # 200码爆炸范围冲击波
	battle._skill_ring(at2d, Color(0.86, 0.72, 1.0, 0.7), 110.0)
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and at2d.distance_to(o["pos"]) <= 200.0:
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 1.0, o) + int(o["maxHp"] * 0.10), Color("#c0a0ff"))
			battle._vfx._flash(o, Color(0.8, 0.6, 1.0))

# 双头·锤击(近战 技1·用户2026-07-11): 跳起→落在目标身前→地面锤击(1.4A物理+获50%伤害盾4s)+落地震屏/冲击环/尘爆
# 双头·锤击(近战 技1·用户2026-07-11): 跳起→落在目标身前→地面锤击(1.4A物理+获50%伤害盾4s)+落地震屏/冲击环/尘爆
func _two_head_hammer(u: Dictionary, tgt: Dictionary) -> void:
	var from2d: Vector2 = u["pos"]
	var d: Vector2 = tgt["pos"] - from2d
	var land2d: Vector2 = tgt["pos"] - (d.normalized() if d.length() > 1.0 else Vector2.RIGHT) * 52.0
	u["_slam"] = true                                           # 跳跃期免分离推挤
	u["_anim_lock_until"] = battle._t + 0.46                           # 跳跃期AI不出手/不移动
	var dmg: int = battle._atk_dmg(u, 1.4, tgt)
	var tw = battle._reg_tween()
	tw.tween_method(_two_head_hammer_arc.bind(u, from2d, land2d), 0.0, 1.0, 0.42)
	tw.tween_callback(_two_head_hammer_land.bind(u, tgt, land2d, dmg, battle._last_dmg_type))   # 捕获举锤时的伤害类型(空中会被覆写)

func _two_head_hammer_arc(pf: float, u: Dictionary, from2d: Vector2, land2d: Vector2) -> void:
	u["pos"] = from2d.lerp(land2d, pf)
	u["_slam_voff"] = Vector3(0.0, sin(pf * PI) * 4.2, 0.0)     # 跳起弧线(render偏移·峰高4.2)

## `dt` = 举锤那一刻 `_resolve_dmg` 定下的伤害类型。锤子在空中飞 ~1.5 秒, 期间全局
## `battle._last_dmg_type` 会被场上任何一发伤害覆写 ⇒ 落地时飘字捡别人的颜色
## (哨兵 DMGSENTINEL 实测抓到)。与弹道 `pr["dtype"]` 同一套办法: 发射时捕获、命中时还原。
func _two_head_hammer_land(u: Dictionary, tgt: Dictionary, at2d: Vector2, dmg: int, dt: String = "") -> void:
	u["_slam_voff"] = Vector3.ZERO
	u["_slam"] = false
	u["pos"] = at2d
	_two_head_slam_impact(at2d)                                # 高质量砸地冲击(AI星爆+三层环+尘+岩屑+顿帧+大震屏·用户2026-07-11)
	if tgt.get("alive", false):
		if dt != "":
			battle._damage.set_dtype(dt, tgt)
		battle._damage._apply_damage_from(u, tgt, dmg, Color("#ffb05c"))
		battle._damage._grant_shield(u, dmg * 0.5, 4.0)                        # 获造成伤害50%护盾(4秒)
		battle._vfx._flash(tgt)


# 高质量砸地冲击(用户2026-07-11「搞质量高的·AI跑特效」): AI冲击星爆(PixelLab生成) + 三层地面冲击波环 + 大尘爆 + 岩屑迸溅 + 顿帧 + 大震屏
# 高质量砸地冲击(用户2026-07-11「搞质量高的·AI跑特效」): AI冲击星爆(PixelLab生成) + 三层地面冲击波环 + 大尘爆 + 岩屑迸溅 + 顿帧 + 大震屏
func _two_head_slam_impact(at2d: Vector2) -> void:
	battle._shake(battle.JUICE_SHAKE_BIG)
	battle._hitstop = maxf(battle._hitstop, 0.06)
	var burst = Sprite3D.new()                                # ① AI 冲击星爆(billboard·由小爆大→亮闪→褪)
	burst.texture = load("res://assets/sprites/vfx/slam-impact.png")
	burst.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	burst.shaded = false; burst.transparent = true
	burst.pixel_size = (300.0 * battle.WS) / 128.0
	burst.position = battle._world_pos(at2d, 0.7)
	burst.modulate = Color(1.0, 0.96, 0.82, 1.0)
	battle._world.add_child(burst)
	var bt = battle._reg_tween()
	bt.tween_property(burst, "scale", Vector3.ONE * 1.35, 0.13).from(Vector3.ONE * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_interval(0.05)
	bt.tween_property(burst, "modulate:a", 0.0, 0.22)
	bt.tween_callback(burst.queue_free)
	battle._skill_ring(at2d, Color(1.0, 0.72, 0.34, 0.92), 108.0)     # ② 地面冲击波环 ×3(依次外扩)
	battle._skill_ring(at2d, Color(1.0, 0.86, 0.5, 0.6), 58.0)
	var rtw = battle._reg_tween()
	rtw.tween_interval(0.09)
	rtw.tween_callback(battle._skill_ring.bind(at2d, Color(1.0, 0.58, 0.26, 0.5), 156.0))
	battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", at2d, 230.0, 0.35)   # ③ 大尘爆
	battle._slam_debris(at2d)                                         # ④ 岩屑迸溅
	battle._vfx._impact_particles(at2d, 0.0)                               # ⑤ 冲击尘粒

# 砸地岩屑: 灰褐碎块一次性向上+四散迸溅+重力回落(0.75s后回收)
func _sk_two_head_disrupt(u: Dictionary, tgt) -> void:           # 双头·技能二 form-variant(封板): 远程=精神干扰(2.0A真伤+治疗削减50%5s+破盾50%·用户2026-07-28加强) / 近战=吸收(0.6A+8%maxHp物理+回血40%A+18%已损)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	if u["melee"]:
		var dmg: int = battle._atk_dmg(u, 0.6, tgt) + int(tgt["maxHp"] * 0.08)
		battle._damage._apply_damage_from(u, tgt, dmg, Color("#c0d0ff"))
		battle._damage._heal(u, u["atk"] * 0.4 + (u["maxHp"] - u["hp"]) * 0.18)   # 回血40%攻击力+18%已损生命
		_two_head_absorb_vfx(u, tgt)                               # 吸收VFX(用户2026-07-11): 生命虹吸束+微粒回流+回血绿环
	else:
		var broke: bool = float(tgt.get("shield", 0.0)) > 0.0
		if broke: tgt["shield"] = float(tgt["shield"]) * 0.5       # 破盾50%
		battle._damage._apply_damage_from(u, tgt, int(maxf(1.0, u["atk"] * DISRUPT_TRUE)), Color("#ffffff"), 0.0, true)   # 真伤(raw=true): 无装备对局里治疗削减/破盾常常空转, 伤害本体要立得住
		tgt["heal_reduce_until"] = battle._t + 5.0
		tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), 0.5)             # 治疗削减50%5秒
		_two_head_disrupt_vfx(u, tgt, broke)                       # 精神干扰VFX(用户2026-07-11): 精神波+紫涟漪+(破盾)盾碎裂+裂心标记

# 精神干扰VFX(用户2026-07-11「AI跑素材」): 头顶精神波(AI psychic-blast) + 紫色心灵涟漪环×2 + 破盾时盾碎裂(AI shield-shatter) + 治疗削减裂心标记
# 精神干扰VFX(用户2026-07-11「AI跑素材」): 头顶精神波(AI psychic-blast) + 紫色心灵涟漪环×2 + 破盾时盾碎裂(AI shield-shatter) + 治疗削减裂心标记
func _two_head_disrupt_vfx(u: Dictionary, tgt: Dictionary, broke_shield: bool) -> void:
	var head: Vector2 = tgt["pos"]
	battle._burst_vfx("res://assets/sprites/vfx/psychic-blast.png", head, 155.0, 1.5)
	battle._skill_ring(head, Color(0.72, 0.36, 1.0, 0.78), 66.0)
	var r2 = battle._reg_tween()
	r2.tween_interval(0.09)
	r2.tween_callback(battle._skill_ring.bind(head, Color(0.6, 0.3, 0.95, 0.5), 110.0))
	battle._shake(0.06)
	if broke_shield:
		battle._burst_vfx("res://assets/sprites/vfx/shield-shatter.png", tgt["pos"], 135.0, 1.0)
	_two_head_heal_reduce_mark(tgt)

# 治疗削减·裂心标记(用户2026-07-11): 头顶挂裂心(AI heart-crack), 跟随目标5秒后褪(复用 battle._follow_vfx 自动贴位+剔除)
# 治疗削减·裂心标记(用户2026-07-11): 头顶挂裂心(AI heart-crack), 跟随目标5秒后褪(复用 battle._follow_vfx 自动贴位+剔除)
func _two_head_heal_reduce_mark(tgt: Dictionary) -> void:
	var old = tgt.get("_hr_mark", null)
	if old != null and is_instance_valid(old):
		return                                                    # 已挂标记不叠
	var m = Sprite3D.new()
	m.texture = load("res://assets/sprites/vfx/heart-crack.png")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.shaded = false; m.transparent = true
	m.pixel_size = (34.0 * battle.WS) / 64.0
	m.modulate = Color(1, 1, 1, 0.95)
	battle._world.add_child(m)
	tgt["_hr_mark"] = m
	battle._follow_vfx.append({"spr": m, "unit": tgt, "h": 2.0})         # 头顶跟随
	var mtw = battle._reg_tween()
	mtw.tween_interval(4.5)
	mtw.tween_property(m, "modulate:a", 0.0, 0.5)
	mtw.tween_callback(m.queue_free)

# 吸收VFX(用户2026-07-11): 敌→自 红紫生命虹吸束 + 生命微粒回流 + 自身回血绿环
# 吸收VFX(用户2026-07-11): 敌→自 红紫生命虹吸束 + 生命微粒回流 + 自身回血绿环
func _two_head_absorb_vfx(u: Dictionary, tgt: Dictionary) -> void:
	battle._bolt_line(tgt["pos"], u["pos"], Color(0.92, 0.26, 0.52))
	var gt = VfxTex._make_glow_texture()
	var from2d: Vector2 = tgt["pos"]
	var to2d: Vector2 = u["pos"]
	for k in range(4):
		var mote = Sprite3D.new()
		mote.texture = gt
		mote.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mote.shaded = false; mote.transparent = true
		mote.modulate = Color(1.0, 0.36, 0.56, 0.9)
		mote.pixel_size = (26.0 * battle.WS) / float(maxi(1, gt.get_height()))
		mote.position = battle._world_pos(from2d, 1.0)
		battle._world.add_child(mote)
		var mtw = battle._reg_tween()
		mtw.tween_interval(float(k) * 0.05)
		mtw.tween_method(battle._absorb_mote_step.bind(mote, from2d, to2d), 0.0, 1.0, 0.3)
		mtw.tween_callback(mote.queue_free)
	battle._skill_ring(u["pos"], Color(0.32, 0.92, 0.5, 0.62), 66.0)

func _sk_two_head_fusion(u: Dictionary, tgt) -> void:            # 双头·技能三融合(封板): 主动魔法波(4段·物理80%+真实80%共1.6A); 锁形态/坚韧/合体近战属性在登场gate
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var n: int = int(u.get("two_wave_count", 4))               # 波数量: 基础4段·每次释放+1累积到战斗结束(用户2026-07-11)
	for i in range(n):                                          # n段交替弧形魔法波(物理紫/真实白)依次飞向目标·波到结算该段
		battle._pending_shots.append({"delay": float(i) * 0.11, "src": u, "fn": _two_head_fusion_wave.bind(u, tgt, i % 2 == 1)})
	u["two_wave_count"] = n + 1                                 # 后续释放波数量+1

# 融合·魔法波: 一道弧形波(magic-wave AI图)从双头飞向目标, 到达时结算该段伤害+紫/白冲击环
# 融合·魔法波: 一道弧形波(magic-wave AI图)从双头飞向目标, 到达时结算该段伤害+紫/白冲击环
func _two_head_fusion_wave(u: Dictionary, tgt: Dictionary, is_true: bool) -> void:
	if not u.get("alive", false) or not tgt.get("alive", false):
		return
	var col: Color = Color(1.0, 1.0, 1.0, 1.0) if is_true else Color(0.74, 0.46, 1.0, 1.0)   # 真实白/物理紫
	var from2d: Vector2 = u["pos"]
	var to2d: Vector2 = tgt["pos"]
	var wv = Sprite3D.new()
	wv.texture = load("res://assets/sprites/vfx/magic-wave.png")
	wv.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	wv.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wv.shaded = false; wv.transparent = true
	wv.modulate = col
	wv.pixel_size = (95.0 * battle.WS) / 128.0
	wv.position = battle._world_pos(from2d, 1.0)
	battle._world.add_child(wv)
	var wtw = battle._reg_tween()
	wtw.tween_method(_two_head_wave_step.bind(wv, from2d, to2d), 0.0, 1.0, 0.27)   # 移速降40%(用户2026-07-11: 0.16→0.27s)
	wtw.tween_callback(_two_head_fusion_wave_hit.bind(u, tgt, is_true, wv))

func _two_head_wave_step(pf: float, wv, from2d: Vector2, to2d: Vector2) -> void:
	if not is_instance_valid(wv):
		return
	wv.position = battle._world_pos(from2d.lerp(to2d, pf), lerpf(1.0, 1.15, pf))
	wv.scale = Vector3.ONE * lerpf(0.7, 1.15, pf)

func _two_head_fusion_wave_hit(u: Dictionary, tgt: Dictionary, is_true: bool, wv) -> void:
	if is_instance_valid(wv):
		var ft = battle._reg_tween()
		ft.tween_property(wv, "modulate:a", 0.0, 0.1)
		ft.tween_callback(wv.queue_free)
	if not tgt.get("alive", false):
		return
	if is_true:
		battle._damage._apply_damage_from(u, tgt, int(u["atk"] * 0.8), Color("#ffffff"), 0.0, true)   # 真实 0.8A(用户2026-07-11)
		battle._skill_ring(tgt["pos"], Color(1.0, 1.0, 1.0, 0.5), 42.0)
	else:
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, 0.8, tgt), Color("#c39bff"))             # 物理 0.8A(用户2026-07-11)
		battle._skill_ring(tgt["pos"], Color(0.74, 0.46, 1.0, 0.5), 42.0)
	battle._damage._knockback(u, tgt, 0.0, 0.6, 0.4)                                                  # 附加一点击飞(轻·airborne守卫防过度juggle·用户2026-07-11)

# 融合登场VFX(用户2026-07-11): 合体能量爆发(fusion-burst AI图) + 持续"融合态"光环(跟随+脉冲, 显示锁定/强化)
# 融合登场VFX(用户2026-07-11): 合体能量爆发(fusion-burst AI图) + 持续"融合态"光环(跟随+脉冲, 显示锁定/强化)
func _two_head_fusion_onset(u: Dictionary) -> void:
	var burst = Sprite3D.new()
	burst.texture = load("res://assets/sprites/vfx/fusion-burst.png")
	burst.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	burst.shaded = false; burst.transparent = true
	burst.pixel_size = (260.0 * battle.WS) / 128.0
	burst.position = battle._world_pos(u["pos"], 1.0)
	battle._world.add_child(burst)
	var bt = battle._reg_tween()
	bt.tween_property(burst, "scale", Vector3.ONE * 1.4, 0.2).from(Vector3.ONE * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.parallel().tween_property(burst, "modulate:a", 0.0, 0.42)
	bt.chain().tween_callback(burst.queue_free)
	battle._shake(0.1)
	var aura = Sprite3D.new()
	aura.texture = VfxTex._make_glow_texture()
	aura.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	aura.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	aura.shaded = false; aura.transparent = true
	aura.modulate = Color(0.72, 0.44, 1.0, 0.42)
	aura.pixel_size = (98.0 * battle.WS) / float(maxi(1, aura.texture.get_height()))
	battle._world.add_child(aura)
	battle._follow_vfx.append({"spr": aura, "unit": u, "h": 0.5, "pulse": true})   # 脉冲交给 _tick_follow_vfx(避免 set_loops 空目标报"infinite loop")
	u["_fuse_aura"] = aura

func _two_head_deferred_cast(u: Dictionary, tgt, stype: String) -> void:
	if not u.get("alive", false):
		return
	battle._cast_skill(u, tgt, stype)
	battle._equip_sys._eq_on_cast(u, tgt)

func _two_head_after_cast(u: Dictionary, tgt) -> void:          # 被动·双生(用户2026-07-11 B案): 切形态+挂"下1下强化普攻"; 近战不单独位移(锤击自带跳接近)/远程纯滑退到射程
	var to_ranged: bool = u["melee"]
	u["two_form"] = "ranged" if to_ranged else "melee"
	_two_head_apply_melee(u, not to_ranged)
	u["melee"] = not to_ranged
	u["atk_range"] = RANGED_RANGE if to_ranged else MELEE_RANGE
	u["_th_enh"] = "ranged" if to_ranged else "melee"          # 挂强化: 下1下普攻搬旧切形态那一下的伤害+效果(远程=1.4A物理+破甲 / 近战=0.6A魔法+1.1A盾)
	if to_ranged:
		var et = (tgt if (tgt is Dictionary and tgt.get("alive", false)) else battle._targeting._nearest_enemy(u))
		_two_head_retreat(u, et)                               # 切远程: 纯平滑滑退200码到射程(伤害/破甲已挪到强化普攻)
	# 切近战: 不单独位移 — 锤击(_two_head_hammer)自带跳跃接近敌人

# 双头·切远程纯滑退(用户2026-07-11 B案: 伤害/破甲挪到强化普攻, 这里只位移): 向远离目标方向平滑滑退200码
# ★2026-08-02 更正注释: 实参早就是 200(见函数体里 away * 200.0 那行, 它自己也标了 350→200), 注释还写 350
# 双头·切远程纯滑退(用户2026-07-11 B案: 伤害/破甲挪到强化普攻, 这里只位移): 向远离目标方向平滑滑退200码
# ★2026-08-02 更正注释: 实参早就是 200(见函数体里 away * 200.0 那行, 它自己也标了 350→200), 注释还写 350
func _two_head_retreat(u: Dictionary, et) -> void:
	var from2d: Vector2 = u["pos"]
	var away: Vector2 = Vector2.RIGHT
	if et != null:
		away = (from2d - et["pos"]).normalized()
		if away.length() < 0.1: away = Vector2.RIGHT
	var dest: Vector2 = from2d + away * RETREAT_DIST                  # 切远程滑退距离(用户2026-07-11: 350→200码)
	dest.x = clampf(dest.x, battle.ARENA.position.x, battle.ARENA.end.x)
	dest.y = clampf(dest.y, battle.ARENA.position.y, battle.ARENA.end.y)
	u["_slam"] = true
	u["_anim_lock_until"] = battle._t + 0.36
	var tw = battle._reg_tween()
	tw.tween_method(_two_head_slide_step.bind(u, from2d, dest), 0.0, 1.0, 0.32)
	tw.tween_callback(_two_head_slide_end.bind(u))

# 双生强化普攻(用户2026-07-11·就下1下·B案连伤害一起搬): 切形态挂的强化, 普攻命中时把旧"切形态那一下"的伤害+效果并进这次普攻
# 双生强化普攻(用户2026-07-11·就下1下·B案连伤害一起搬): 切形态挂的强化, 普攻命中时把旧"切形态那一下"的伤害+效果并进这次普攻
func _two_head_enhanced_basic(u: Dictionary, tgt: Dictionary, form: String) -> void:
	if form == "melee":
		if tgt.get("alive", false):
			battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, ENH_MELEE_COEF, tgt, true), Color("#ffb05c"))   # 近战强化: +0.6A魔法伤害
		battle._damage._grant_shield(u, u["atk"] * ENH_SHIELD_COEF, ENH_SEC)                                            # + 自己获 1.1×ATK 护盾(4s)
		battle._skill_ring(u["pos"], Color(0.72, 0.8, 1.0, 0.6), 62.0)
	else:
		if tgt.get("alive", false):
			battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, ENH_RANGED_COEF, tgt), Color("#c0d0ff"))          # 远程强化: +1.4A物理伤害
			battle._damage._buff(tgt, "def", -ENH_ARMOR_DOWN, true, ENH_SEC)                                          # + 命中目标 -25% 护甲(4s·破甲)

func _two_head_slide_step(pf: float, u: Dictionary, from2d: Vector2, dest: Vector2) -> void:
	u["pos"] = from2d.lerp(dest, pf)

func _two_head_slide_end(u: Dictionary) -> void:
	u["_slam"] = false

# 熔岩龟·选一套 (demo 默认套A). 龟能满→放【当前形态】(小/火山)这套对应招. 攒怒变身在 _tick_periodic_passive.