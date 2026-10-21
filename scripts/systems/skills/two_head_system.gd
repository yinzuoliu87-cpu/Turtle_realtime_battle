class_name TwoHeadSystem
extends RefCounted
## 双头龟技能系统
## 类内名不变;外部名加 battle.

## ★双头数值单一事实源(用户2026-07-28)。文案在 data/pets.json，改这里要同步改那边。
const DISRUPT_TRUE := 2.0   # 精神干扰(远程形态): ×ATK 真实伤害 (原 1.0×ATK 魔法)
## ★★2026-08-22 文案根除: 双生(被动)的这一组原来散在 `_two_head_after_cast` /
##   `_two_head_enhanced_basic` / `_two_head_retreat` 的函数体里, 文案又各手写一遍。
## 【切近战时的属性变化】(基准都是 ATK)
## 【双头攻击(普攻)】随形态两套系数, 真值在【主场景】(那里引用本组常量)。
const BASIC_RANGED_COEF := 1.2   # 远程形态: 灵能弹 ×ATK 物理
const BASIC_MELEE_COEF := 0.9    # 近战形态: 挥砍 ×ATK 物理
const MELEE_HP_COEF := 2.5       # 最大生命 +
const MELEE_DEF_COEF := 0.25     # 护甲 +
const MELEE_MR_COEF := 0.25      # 魔抗 +
const MELEE_ATK_PENALTY := 0.30  # 攻击力 −
## 【融合·魔法波】主动的龟能消耗。★真值放这里、由 SkillEnergy.SKILL_COST 反过来引用 ——
##   那张表是 dict, `{C:}` 索引不了, 而 skill_energy.gd 故意没有 class_name。
const FUSION_WAVE_ENERGY := 85.0
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
## 【技能二·远程形态: 精神干扰】(真伤系数见上面 DISRUPT_TRUE)
## 【技能一·远程形态: 灵能冲击】紫炮弹碰第一个敌人即爆。
const STRIKE_RANGED_COEF := 1.0    # ×ATK 物理
const STRIKE_RANGED_MAXHP := 0.10  # + 目标最大生命 ×
const STRIKE_BLAST_RADIUS := 200.0 # 爆点半径(码)
## 【技能一·近战形态: 锤击】
const STRIKE_MELEE_COEF := 1.4     # ×ATK 物理
const STRIKE_SHIELD_PCT := 0.5     # 获得 = 所造成伤害 × 的护盾
const STRIKE_SHIELD_SEC := 4.0     # 护盾持续(秒)
## ★锤击是范围技(用户 2026-10-20「锤击是单体技能吗」→「这样，改为aoe」→「范围200码」):
##   以【锤头落点】为圆心、这个半径(码)内的每个敌人各吃一次 STRIKE_MELEE_COEF×ATK 物理;
##   护盾只按【主目标】那一下的伤害算(不随命中人数叠加)。砸地特效的扩散半径读的也是这个常量(特效即判定)。
const STRIKE_MELEE_RADIUS := 200.0
## 锤头落点 = 施法者落点往立绘朝向前方这么多码(立绘是公告板, 锤头在画面里永远是左右伸出去的)。
##   由立绘量出: melee_strike 第 6~8 帧锤头(石灰色)重心离中线 ≈39 像素 × 0.025 米 ÷ WS 0.024 ≈ 41 码。
##   门禁 verify_two_head_anim F② 按素材量, 不读这个常量。
const STRIKE_MELEE_HEAD_FWD := 41.0
const DISRUPT_HEALCUT_PCT := 0.5   # 治疗削减比例
const DISRUPT_HEALCUT_SEC := 5.0   # 治疗削减持续(秒)
const DISRUPT_SHIELD_BREAK := 0.5  # 破除目标护盾的比例
## 【技能二·近战形态: 吸收】
const ABSORB_ATK_COEF := 0.6       # ×ATK 物理
const ABSORB_MAXHP_PCT := 0.08     # + 目标最大生命 ×
const ABSORB_HEAL_ATK := 0.4       # 回血 = ×ATK
const ABSORB_HEAL_LOST := 0.18     # 回血 + 自身已损生命 ×
## 【技能三·融合】
const FUSION_WAVE_BASE := 4        # 魔法波基础段数(每次释放 +1, 累积到战斗结束)
const FUSION_WAVE_COEF := 0.8      # 每段 ×ATK (物理与真实交替)
const FUSION_TOUGH_CAP := 20       # 双头坚韧: 护甲/魔抗各自的上限
const FUSION_WAVE_FLY_SEC := 0.27  # 每道魔法波飞到目标的时长(秒·到达才结算该段)

## 【锤击跳跃】从起跳到落地砸下的时长(秒)。动作驱动 TwoHeadArt 拿它对齐"砸地"那一帧。
const HAMMER_LEAP_SEC := 0.42

var battle
var vfx: TwoHeadVfx      # 技能特效(sim 步里建节点, 直播录得到)
var art: TwoHeadArt      # 动作驱动(渲染层, 只读 sim 状态)

func _init(b) -> void:
	battle = b
	vfx = TwoHeadVfx.new(b)
	art = TwoHeadArt.new(b)


## 普攻(从主场景整段搬来, 结算一字未改): 远程 1.2A 物理灵能弹 / 近战 0.9A 物理挥锤。
func basic(u: Dictionary, tgt: Dictionary) -> void:
	var _thsc: float = BASIC_MELEE_COEF if u["melee"] else BASIC_RANGED_COEF
	battle._emit_basic(u, tgt, battle._atk_dmg(u, _thsc, tgt), Color("#c0a0ff"), 0)
	if u["melee"]:
		vfx.hammer_swing(u, tgt)                                 # 挥锤弧(命中那一刻, 与伤害同一步)
	if str(u.get("_th_enh", "")) != "":                      # 双生强化普攻: 搬旧切形态那一下的伤害+效果(就这1下·用户2026-07-11 B案)
		_two_head_enhanced_basic(u, tgt, str(u["_th_enh"]))
		u["_th_enh"] = ""
	battle._on_basic_hit(u, tgt)

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
		vfx.shell_behind(u)                                    # 护盾罩退到立绘后面一层(正好落在变脸挡脸那一帧, 见 TwoHeadVfx.SHELL_BEHIND_PRIO)
	elif not on and buffed:
		u["two_melee_buffed"] = false
		u["maxHp"] = maxf(1.0, u["maxHp"] - float(u.get("_th_hp", 0.0)))
		u["hp"] = minf(u["hp"], u["maxHp"])
		u["base_def"] = maxf(0.0, u["base_def"] - float(u.get("_th_def", 0.0)))
		u["base_mr"] = maxf(0.0, u["base_mr"] - float(u.get("_th_mr", 0.0)))
		u["base_atk"] += float(u.get("_th_atk", 0.0))
		battle._recalc_stats(u)

func _sk_two_head_strike(u: Dictionary, tgt) -> void:            # 双头·技能一 form-variant(用户2026-07-11重设计): 远程=灵能冲击(大紫炮弹→碰第一敌爆炸200码AOE 1A+10%maxHp物理) / 近战=锤击(跳起落地砸·锤头落点200码内各1.4A物理+主目标伤害50%盾4s)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	if u["melee"]:
		_two_head_hammer(u, tgt)                                # 近战锤击: 跳起→落在目标→地面锤击
	else:
		var dir: Vector2 = tgt["pos"] - u["pos"]
		if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
		_two_head_cannon(u, u["pos"], DetMath.norm(dir))         # 远程灵能冲击: 大紫炮弹

# 双头·灵能冲击炮弹(用户2026-07-11): 大紫炮弹朝目标方向飞(射程2000·760码/s)→碰第一敌(46码)爆炸→200码内敌 1A+10%目标maxHp 物理
# 双头·灵能冲击炮弹(用户2026-07-11): 大紫炮弹朝目标方向飞(射程2000·760码/s)→碰第一敌(46码)爆炸→200码内敌 1A+10%目标maxHp 物理
func _two_head_cannon(u: Dictionary, from2d: Vector2, dir: Vector2) -> void:
	var spr = vfx.orb_new(from2d)                           # 法球: 出手后先胀大, 再转飞行循环(按已飞行时间切帧)
	var traveled = 0.0
	var pos = from2d
	var hit = null
	while is_instance_valid(battle) and traveled < 2000.0 and u.get("alive", false) and battle.is_inside_tree():
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if battle._timestop.holds(u): continue   # 时停: 被定格的单位这一步不推进(携带者照常; 顿帧行为不变)
		traveled = minf(2000.0, traveled + 760.0 * battle._frame_sim_dt)
		pos = from2d + dir * traveled
		pos = ArenaShape.clamp_in(pos, battle.ARENA)
		if is_instance_valid(spr):
			spr.position = battle._world_pos(pos, TwoHeadVfx.CHEST_H)
			vfx.orb_step(spr, traveled / 760.0)
		for o in battle._targeting._enemies_of(u):
			if o.get("alive", false) and DetMath.dist(pos, o["pos"]) <= 46.0:
				hit = o; break
		if hit != null: break
	if is_instance_valid(spr): spr.queue_free()
	_two_head_cannon_boom(u, pos)

func _two_head_cannon_boom(u: Dictionary, at2d: Vector2) -> void:
	battle._shake(0.13)
	vfx.orb_blast(at2d)                                                              # 爆炸: 闪→壳→火球→烟→碎(像素表)
	battle._skill_ring(at2d, Color(0.76, 0.55, 1.0, 0.9), STRIKE_BLAST_RADIUS)       # 地面环 = 真实判定半径 200 码(谁在圈里谁挨炸)
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and DetMath.dist(at2d, o["pos"]) <= STRIKE_BLAST_RADIUS:
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, STRIKE_RANGED_COEF, o) + battle._phys_after_armor(u, float(o["maxHp"]) * STRIKE_RANGED_MAXHP, o), Color("#c0a0ff"))
			battle._vfx._flash(o, Color(0.8, 0.6, 1.0))

# 变脸龟·锤击(近战 技1): 跳起→落在目标身前→锤头落点 200 码内敌人各 1.4A 物理(2026-10-20 改范围)+获主目标那一下伤害 50% 的盾 4s
func _two_head_hammer(u: Dictionary, tgt: Dictionary) -> void:
	var from2d: Vector2 = u["pos"]
	var d: Vector2 = tgt["pos"] - from2d
	var land2d: Vector2 = tgt["pos"] - (DetMath.norm(d) if DetMath.vlen(d) > 1.0 else Vector2.RIGHT) * 52.0
	u["_slam"] = true                                           # 跳跃期免分离推挤
	u["_anim_lock_until"] = battle._t + 0.46                           # 跳跃期AI不出手/不移动
	var dmg: int = battle._atk_dmg(u, STRIKE_MELEE_COEF, tgt)
	var tw = battle._reg_tween()
	tw.tween_method(_two_head_hammer_arc.bind(u, from2d, land2d), 0.0, 1.0, HAMMER_LEAP_SEC)
	tw.tween_callback(_two_head_hammer_land.bind(u, tgt, land2d, dmg, battle._last_dmg_type))   # 捕获举锤时的伤害类型(空中会被覆写)

func _two_head_hammer_arc(pf: float, u: Dictionary, from2d: Vector2, land2d: Vector2) -> void:
	u["pos"] = DetMath.vlerp(from2d, land2d, pf)
	u["_slam_voff"] = Vector3(0.0, DetMath.dsin(pf * PI) * 4.2, 0.0)     # 跳起弧线(render偏移·峰高4.2)
	vfx.leap_step(u, pf, land2d)                                # 起跳残影 / 锤头光跟弧线 / 下砸月牙弧(纯演出)

## `dt` = 举锤那一刻 `_resolve_dmg` 定下的伤害类型。锤子在空中飞 ~1.5 秒, 期间全局
## `battle._last_dmg_type` 会被场上任何一发伤害覆写 ⇒ 落地时飘字捡别人的颜色
## (哨兵 DMGSENTINEL 实测抓到)。与弹道 `pr["dtype"]` 同一套办法: 发射时捕获、命中时还原。
func _two_head_hammer_land(u: Dictionary, tgt: Dictionary, at2d: Vector2, dmg: int, dt: String = "") -> void:
	u["_slam_voff"] = Vector3.ZERO
	u["_slam"] = false
	u["pos"] = at2d
	var hit_at: Vector2 = hammer_point(at2d, bool(u.get("face_right", true)))
	vfx.leap_end(u)
	_two_head_slam_impact(at2d, bool(u.get("face_right", true)))   # 砸地: 震屏+顿帧+锤头落点冲击(范围 = STRIKE_MELEE_RADIUS)+挥锤弧
	if tgt.get("alive", false):
		if dt != "":
			## ★resolved=true: 伤害是【举锤那一刻】`_atk_dmg`(→`_resolve_dmg`)算好的,
			##   护甲已经吃过了; 落地这里只是把类型还原。不传 true 的话哨兵第三只眼
			##   会把它误报成"不吃护甲"(它只看落地那一刻)。
			battle._damage.set_dtype(dt, tgt, null, true)
		battle._damage._apply_damage_from(u, tgt, dmg, Color("#ffb05c"))
		battle._damage._grant_shield(u, dmg * STRIKE_SHIELD_PCT, STRIKE_SHIELD_SEC)                        # 获造成伤害50%护盾(4秒)·只按主目标这一下
		vfx.shell_behind(u)                                    # 护盾罩退到立绘后面一层, 不盖砸地
		battle._vfx._flash(tgt)
	## 范围: 锤头落点 STRIKE_MELEE_RADIUS 码内的其余敌人各吃一次 1.4×ATK 物理(各自现算护甲; 主目标上面已经打过, 不重复)
	for o in battle._targeting._enemies_of(u):
		if is_same(o, tgt) or not o.get("alive", false):
			continue
		if DetMath.dist(hit_at, o["pos"]) <= STRIKE_MELEE_RADIUS:
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, STRIKE_MELEE_COEF, o), Color("#ffb05c"))
			battle._vfx._flash(o)


## 锤头落点(场地坐标): 结算圆心与砸地特效同一点。
static func hammer_point(at2d: Vector2, face_right: bool) -> Vector2:
	return at2d + Vector2((1.0 if face_right else -1.0) * STRIKE_MELEE_HEAD_FWD, 0.0)


# 锤击落地: 震屏 + 顿帧 + 锤头落点砸地冲击(2026-10-20 改范围技后重做: 冲击扩到 STRIKE_MELEE_RADIUS = 判定半径)
func _two_head_slam_impact(at2d: Vector2, face_right: bool = true) -> void:
	battle._shake(battle.JUICE_SHAKE_BIG)
	battle._hitstop = maxf(battle._hitstop, 0.06)
	vfx.hammer_slam(at2d, face_right)      # 锤头落点砸地: 白核闪 + 贴地冲击波扩到判定半径 + 符文地裂 + 碎石 + 尘 + 挥锤弧(落点见 hammer_point)

# 砸地岩屑: 灰褐碎块一次性向上+四散迸溅+重力回落(0.75s后回收)
func _sk_two_head_disrupt(u: Dictionary, tgt) -> void:           # 双头·技能二 form-variant(封板): 远程=精神干扰(2.0A真伤+治疗削减50%5s+破盾50%·用户2026-07-28加强) / 近战=吸收(0.6A+8%maxHp物理+回血40%A+18%已损)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	if u["melee"]:
		var dmg: int = battle._atk_dmg(u, ABSORB_ATK_COEF, tgt) + battle._phys_after_armor(u, float(tgt["maxHp"]) * ABSORB_MAXHP_PCT, tgt)
		battle._damage._apply_damage_from(u, tgt, dmg, Color("#c0d0ff"))
		battle._damage._heal(u, u["atk"] * ABSORB_HEAL_ATK + (u["maxHp"] - u["hp"]) * ABSORB_HEAL_LOST)   # 回血40%攻击力+18%已损生命
		_two_head_absorb_vfx(u, tgt)                               # 吸收VFX(用户2026-07-11): 生命虹吸束+微粒回流+回血绿环
	else:
		var broke: bool = float(tgt.get("shield", 0.0)) > 0.0
		if broke: tgt["shield"] = float(tgt["shield"]) * DISRUPT_SHIELD_BREAK       # 破盾50%
		battle._damage._apply_damage_from(u, tgt, int(maxf(1.0, u["atk"] * DISRUPT_TRUE)), Color("#ffffff"), 0.0, true)   # 真伤(raw=true): 无装备对局里治疗削减/破盾常常空转, 伤害本体要立得住
		tgt["heal_reduce_until"] = battle._t + DISRUPT_HEALCUT_SEC
		tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), DISRUPT_HEALCUT_PCT)             # 治疗削减50%5秒
		_two_head_disrupt_vfx(u, tgt, broke)                       # 精神干扰VFX(用户2026-07-11): 精神波+紫涟漪+(破盾)盾碎裂+裂心标记

# 精神干扰VFX: 额头符文眼→目标头部的精神波(2026-10-20 重做) + 破盾时盾碎裂(shield-shatter) + 治疗削减裂心标记
func _two_head_disrupt_vfx(u: Dictionary, tgt: Dictionary, broke_shield: bool) -> void:
	vfx.mind_wave(u, tgt)                                       # 精神波: 从额头符文眼到目标头部同一刻铺开(伤害当场结算, 波不许后到)
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

# 吸收VFX(2026-10-20 重做): 目标身上攥出生命 + 一股血流涌回自己
func _two_head_absorb_vfx(u: Dictionary, tgt: Dictionary) -> void:
	vfx.siphon(u, tgt)          # 目标身上攥出生命 + 一股血流涌回自己(回血当场结算, 精魄不慢飞)

func _sk_two_head_fusion(u: Dictionary, tgt) -> void:            # 双头·技能三融合(封板): 主动魔法波(4段·物理80%+真实80%共1.6A); 锁形态/坚韧/合体近战属性在登场gate
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var n: int = int(u.get("two_wave_count", FUSION_WAVE_BASE))               # 波数量: 基础4段·每次释放+1累积到战斗结束(用户2026-07-11)
	for i in range(n):                                          # n段交替弧形魔法波(物理紫/真实白)依次飞向目标·波到结算该段
		battle._pending_shots.append({"delay": float(i) * 0.11, "src": u, "fn": _two_head_fusion_wave.bind(u, tgt, i % 2 == 1)})
	u["two_wave_count"] = n + 1                                 # 后续释放波数量+1

# 融合·魔法波: 一道弧形波(twohead-fusion-wave 像素表)飞向目标, 到达时结算该段伤害+紫/白冲击环
func _two_head_fusion_wave(u: Dictionary, tgt: Dictionary, is_true: bool) -> void:
	if not u.get("alive", false) or not tgt.get("alive", false):
		return
	var from2d: Vector2 = u["pos"]
	var to2d: Vector2 = tgt["pos"]
	var wv = vfx.fusion_wave_new(from2d, to2d, is_true)        # 魔法波: 真实段白 / 物理段紫
	var wtw = battle._reg_tween()
	wtw.tween_method(_two_head_wave_step.bind(wv, from2d, to2d), 0.0, 1.0, FUSION_WAVE_FLY_SEC)   # 移速降40%(用户2026-07-11: 0.16→0.27s)
	wtw.tween_callback(_two_head_fusion_wave_hit.bind(u, tgt, is_true, wv))

func _two_head_wave_step(pf: float, wv, from2d: Vector2, to2d: Vector2) -> void:
	if not is_instance_valid(wv):
		return
	wv.position = battle._world_pos(from2d.lerp(to2d, pf), TwoHeadVfx.CHEST_H)
	vfx.fusion_wave_frame(wv, pf * FUSION_WAVE_FLY_SEC)        # 像素表只切帧, 不缩放(vfx_discipline A)

func _two_head_fusion_wave_hit(u: Dictionary, tgt: Dictionary, is_true: bool, wv) -> void:
	if is_instance_valid(wv):
		var ft = battle._reg_tween()
		ft.tween_property(wv, "modulate:a", 0.0, 0.1)
		ft.tween_callback(wv.queue_free)
	if not tgt.get("alive", false):
		return
	if is_true:
		battle._damage._apply_damage_from(u, tgt, int(u["atk"] * FUSION_WAVE_COEF), Color("#ffffff"), 0.0, true)   # 真实 0.8A(用户2026-07-11)
		battle._skill_ring(tgt["pos"], Color(1.0, 1.0, 1.0, 0.5), 42.0)
	else:
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, FUSION_WAVE_COEF, tgt), Color("#c39bff"))             # 物理 0.8A(用户2026-07-11)
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
	if battle._damage.is_controlled(u):
		return   # ★被控就作废(用户 10-16 被控规则): 蓄力 / 延迟期间被眩晕、定身、击飞, 到点不再出手
	battle._cast_skill(u, tgt, stype)
	var _tl0: Array = battle._equip_sys.tally.capture()   # ④ 装备统计: 分发函数里逐件切上下文, 这里还原
	battle._equip_sys._eq_on_cast(u, tgt)
	battle._equip_sys.tally.pop(_tl0)

func _two_head_after_cast(u: Dictionary, tgt) -> void:          # 被动·双生(用户2026-07-11 B案): 切形态+挂"下1下强化普攻"; 近战不单独位移(锤击自带跳接近)/远程纯滑退到射程
	var to_ranged: bool = u["melee"]
	u["two_form"] = "ranged" if to_ranged else "melee"
	_two_head_apply_melee(u, not to_ranged)
	u["melee"] = not to_ranged
	u["atk_range"] = RANGED_RANGE if to_ranged else MELEE_RANGE
	u["_th_enh"] = "ranged" if to_ranged else "melee"          # 挂强化: 下1下普攻搬旧切形态那一下的伤害+效果(远程=1.4A物理+破甲 / 近战=0.6A魔法+1.1A盾)
	_two_head_form_art(u)
	vfx.face_swap(u)                                           # 斗篷甩过脸那一下的两色烟(换脸就在这一刻)
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
		away = DetMath.norm((from2d - et["pos"]))
		if DetMath.vlen(away) < 0.1: away = Vector2.RIGHT
	var dest: Vector2 = from2d + away * RETREAT_DIST                  # 切远程滑退距离(用户2026-07-11: 350→200码)
	dest = ArenaShape.clamp_in(dest, battle.ARENA)
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
		vfx.shell_behind(u)                                    # 护盾罩退到立绘后面一层, 不盖挥锤
		## (2026-10-20 删: 原来这里在自己脚下画一圈 62 码的地面环 —— 既不是射程也不是判定范围,
		##  玩家只会读成「这里有个范围」(特效九类毛病④)。这一下的两件事各自已有演出:
		##  0.6×ATK 魔法伤害 = 目标身上的命中与伤害数字, 1.1×ATK 护盾 = 上一行的护盾罩。)
	else:
		if tgt.get("alive", false):
			battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, ENH_RANGED_COEF, tgt), Color("#c0d0ff"))          # 远程强化: +1.4A物理伤害
			battle._damage._buff(tgt, "def", -ENH_ARMOR_DOWN, true, ENH_SEC)                                          # + 命中目标 -25% 护甲(4s·破甲)

func _two_head_slide_step(pf: float, u: Dictionary, from2d: Vector2, dest: Vector2) -> void:
	u["pos"] = DetMath.vlerp(from2d, dest, pf)

func _two_head_slide_end(u: Dictionary) -> void:
	u["_slam"] = false

# 熔岩龟·选一套 (demo 默认套A). 龟能满→放【当前形态】(小/火山)这套对应招. 攒怒变身在 _tick_periodic_passive.


## 形态立绘(2026-10-07 变脸龟定稿·用户「定稿吧」): 远程=术士 `pets/two_head.png`(开局, 也是 pets.json 的 img) /
## 近战=战士 `pets/two_head_melee.png`。切形态时换 `idle_sd` 源头(不是 spr.texture —— 渲染层每帧按 idle_sd 还原, 同 087 蛋糕礼盒)。
## ★在礼盒形态里(还存着 `_cake_o_idle_sd`)就只换那份存档, 出盒时自然换回对的形态。
const FORM_ART := {"ranged": "res://assets/sprites/pets/two_head.png", "melee": "res://assets/sprites/pets/two_head_melee.png"}
func _two_head_form_art(u: Dictionary) -> void:
	var p: String = str(FORM_ART.get(str(u.get("two_form", "ranged")), ""))
	if p == "" or not ResourceLoader.exists(p):
		return
	var sd: Dictionary = battle._sprite_dict_from(load(p), null, false)
	art.attach(u)                                              # 死亡帧表按形态换
	if u.has("_cake_o_idle_sd"):
		u["_cake_o_idle_sd"] = sd
		return
	u["idle_sd"] = sd
	battle._set_anim_sheet(u, sd, "", true)
