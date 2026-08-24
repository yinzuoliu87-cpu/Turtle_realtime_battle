class_name DiamondSystem
extends RefCounted
## 钻石龟技能系统
## 类内簇函数名不变;外部名加 battle. 前缀。

## ★★2026-08-22 文案根除: 下面这些原来全是函数体里的裸字面量。
## 【钻石滚球】按撞击瞬间的移动速度在 0 速 ↔ 满速之间**线性插值**
## 【坚不可摧】护盾 + 双抗, 两者时长不同(护盾 4 秒 / 双抗 5 秒)。
const FORTIFY_SHIELD_PCT := 0.20   # 护盾 = 自身最大生命 ×
const FORTIFY_SHIELD_SEC := 4.0    # 护盾持续(秒)·持盾期锁龟能
const FORTIFY_RESIST_COEF := 0.20  # 护甲与魔抗 各 += ATK ×
const FORTIFY_RESIST_SEC := 5.0    # 双抗持续(秒)
const ROLL_ACCEL_SEC := 4.0       # 从静止加速到满速要几秒
const ROLL_HIT_RADIUS := 120.0    # 撞击点小 AOE 半径(码)
const ROLL_RESIST_MIN := 0.1      # 0 速时 ×护甲 与 ×魔抗
const ROLL_RESIST_MAX := 1.0      # 满速时 ×护甲 与 ×魔抗
const ROLL_MAXHP_MIN := 0.02      # 0 速时 + 目标最大生命 ×
const ROLL_MAXHP_MAX := 0.20      # 满速时 + 目标最大生命 ×
const ROLL_KNOCK_SEC := 1.0       # 击飞滞空(秒)
const ROLL_STUN_MIN := 0.5        # 眩晕(秒)·0 速
const ROLL_STUN_MAX := 3.0        # 眩晕(秒)·满速
const ROLL_AUTO_RANGE := 200.0    # 被动: 最近敌**远于**此距离(=此范围内无敌)就免费自动滚
const ROLL_AUTO_CD := 0.8         # 被动: 防抖冷却(秒)
## 【钻石冲撞】
const SMASH_RESIST_COEF := 1.0    # ×护甲 + ×魔抗
const SMASH_ATK_COEF := 0.1       # + ×ATK 物理
const SMASH_KNOCK_DIST := 300.0   # 沿冲撞方向击退(码)·真值走 battle.DIAMOND_SMASH_PUSH
const SMASH_BLEED_ATK := 0.5      # 流血层数 = ×ATK + ×护甲 + ×魔抗(下两行)
const SMASH_BLEED_RESIST := 0.1
const SMASH_SLOW_PCT := 0.50      # 减速比例(语义值)
const SMASH_SLOW_MULT := 1.0 - SMASH_SLOW_PCT
const SMASH_SLOW_SEC := 3.0       # 减速持续(秒)
const SMASH_SELF_RESIST_BONUS := 1.00   # 打包被动: 选此技 → 登场自身护甲/魔抗额外 +100%

var battle

func _init(b) -> void:
	battle = b

# 滚球位移tick(每帧·在_tick_unit免CC段调): 0→满速4s加速·朝最近敌滚·进120码撞击结算
func _diamond_roll_tick(u: Dictionary, delta: float) -> void:
	var sf: float = clampf((battle._t - float(u.get("roll_start", battle._t))) / ROLL_ACCEL_SEC, 0.0, 1.0)   # 0→满速4秒线性加速
	var tgt = battle._targeting._nearest_enemy(u)
	if tgt == null:   # 无敌可撞→退出滚动 (用户2026-07-12: 取消6秒超时限制, 滚到撞上为止)
		u["roll_active"] = false; u["state"] = "move"
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	if to_t.length() <= ROLL_HIT_RADIUS:                                     # 进入120码→撞击结算
		_diamond_roll_impact(u, tgt["pos"], sf)
		u["roll_active"] = false; u["state"] = "move"
		return
	var roll_spd: float = battle.DIAMOND_ROLL_MAX_SPD * (0.1 + 0.9 * sf)  # 0.1起步(避免完全不动)→满速
	u["pos"] += to_t.normalized() * roll_spd * delta
	u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
	u["face_right"] = to_t.x > 0.0
	if int(battle._t * 30.0) % 2 == 0:                                    # 速度线拖尾(越快越猛·美术L231)
		battle._skill_ring(u["pos"], Color(0.6, 0.86, 1.0, 0.2 + 0.35 * sf), 28.0 + 22.0 * sf)

func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(cp) > ROLL_HIT_RADIUS: continue             # 撞击点120码小AOE
		var dmg: int = int(u["def"] * (ROLL_RESIST_MIN + (ROLL_RESIST_MAX - ROLL_RESIST_MIN) * sf) + u["mr"] * (ROLL_RESIST_MIN + (ROLL_RESIST_MAX - ROLL_RESIST_MIN) * sf) + o["maxHp"] * (ROLL_MAXHP_MIN + (ROLL_MAXHP_MAX - ROLL_MAXHP_MIN) * sf))   # 按速插值(封板: 0速0.1甲0.1抗2%→满速1.0甲1.0抗20%)
		battle._damage._apply_damage_from(u, o, dmg, Color("#9bdcff"))
		battle._damage._knockback(u, o, 50.0, 1.8, 1.0)                          # 击飞1秒(vy高)
		battle._freeze(o, ROLL_STUN_MIN + (ROLL_STUN_MAX - ROLL_STUN_MIN) * sf)                                # 眩晕0.5~3s(随速插值·满速3s)
	battle._burst_vfx("res://assets/sprites/vfx/diamond-impact.png", cp, 120.0 + 70.0 * sf, 0.5)   # 水晶碎裂撞击(按速插值·越快越大)
	battle._skill_ring(cp, Color(0.6, 0.86, 1.0, 0.6), 120.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY if sf > 0.6 else battle.JUICE_SHAKE_LIGHT)  # 满速更炸(封板美术L231)

func _diamond_smash_impact(u: Dictionary, tgt) -> void:         # 蓄力结束→冲撞落地结算
	if not u.get("alive", false): return
	if tgt == null or not tgt.get("alive", false):
		tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	battle._dash_to(u, tgt, 45.0)
	var dmg: int = int(u["def"] * SMASH_RESIST_COEF + u["mr"] * SMASH_RESIST_COEF + u["atk"] * SMASH_ATK_COEF)     # 保留原撞击伤害(1.0甲+1.0抗+0.1A物理·用户2026-07-12保留)
	battle._damage._apply_damage_from(u, tgt, dmg, Color("#9bdcff"))
	var bstacks: int = maxi(1, roundi(SMASH_BLEED_ATK * float(u["atk"]) + SMASH_BLEED_RESIST * float(u["def"]) + SMASH_BLEED_RESIST * float(u["mr"])))   # 流血层数=0.5A+0.1甲+0.1抗(用户2026-07-12·走既有层数式流血)
	battle._damage._apply_dot_stacks(tgt, "bleed", bstacks, u)
	var prev_slow: float = float(tgt.get("slow_mag", 1.0)) if battle._t < float(tgt.get("slow_until", 0.0)) else 1.0
	battle._damage._knockback(u, tgt, 0.0, battle.DIAMOND_SMASH_KNOCK_VY, battle.DIAMOND_SMASH_PUSH)   # 击退~300码(顺冲撞方向)+一点点击飞
	tgt["slow_until"] = maxf(float(tgt.get("slow_until", 0.0)), battle._t + SMASH_SLOW_SEC)   # 3秒50%减速
	tgt["slow_mag"] = minf(prev_slow, SMASH_SLOW_MULT)
	battle._burst_vfx("res://assets/sprites/vfx/diamond-impact.png", tgt["pos"], 110.0, 0.5)   # 水晶碎裂撞击
	battle._skill_ring(tgt["pos"], Color(0.7, 0.9, 1.0, 0.55), 54.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY)

func _diamond_slash_fx(u: Dictionary, tgt: Dictionary) -> void:   # 钻石普攻·切割: 水晶新月斩弧, 随攻击方向翻转·落在攻击者→目标之间(近战无弹道·用户2026-07-12指出方向问题)
	var to_r: bool = tgt["pos"].x >= u["pos"].x
	var at: Vector2 = u["pos"].lerp(tgt["pos"], 0.7) + Vector2(0, -6)   # 斩弧落在偏目标一侧(斩到敌身上)
	var b := Sprite3D.new()
	b.texture = load("res://assets/sprites/vfx/diamond-slash.png")
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED; b.shaded = false; b.transparent = true
	b.flip_h = not to_r                        # 凹口朝攻击者·凸刃朝目标→随左右翻转(方向反了就改这行布尔)
	var th := float(maxi(1, int(b.texture.get_height())))
	b.pixel_size = (88.0 * battle.WS) / th
	b.position = battle._world_pos(at, 0.7)
	battle._world.add_child(b)
	var t = battle._reg_tween()
	t.tween_property(b, "scale", Vector3.ONE, 0.09).from(Vector3(0.55, 0.55, 0.55)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.06)
	t.tween_property(b, "modulate:a", 0.0, 0.2)
	t.tween_callback(b.queue_free)

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧(封板): 20%最大生命护盾(4秒·限时盾原语)+护甲/魔抗各+20%攻击力(flat·5秒)
	battle._damage._grant_shield(u, u["maxHp"] * FORTIFY_SHIELD_PCT, FORTIFY_SHIELD_SEC)
	u["diamond_fortify_until"] = battle._t + FORTIFY_SHIELD_SEC   # 持盾期锁龟能+青水晶护罩(与shield同4s·盾破/到期即恢复·用户2026-07-12)
	battle._damage._buff(u, "def", u["atk"] * 0.2, false, 5.0)
	battle._damage._buff(u, "mr", u["atk"] * 0.2, false, 5.0)
	battle._burst_vfx("res://assets/sprites/vfx/diamond-fortify.png", u["pos"], 100.0, 0.5)   # 水晶护甲成型(蓝晶迸发·此前零特效)
	battle._skill_ring(u["pos"], Color(0.55, 0.82, 1.0, 0.55), 58.0)
	battle._shake(battle.JUICE_SHAKE_LIGHT)

func _sk_diamond_powerball(u: Dictionary, tgt) -> void:          # 钻石龟·钻石滚球(封板·龙龟Q Powerball·100龟能): 进入蜷球滚动位移态(移速0起4s加速满速·朝最近敌·免疫定身沉默打断)·撞击120码AOE(护甲/魔抗/2%maxHp按速插值)+击飞1s+眩晕0.5~3s
	if battle._targeting._nearest_enemy(u) == null:
		return
	u["roll_active"] = true
	u["roll_start"] = battle._t
	battle._skill_ring(u["pos"], Color(0.6, 0.86, 1.0, 0.5), 44.0)

func _sk_diamond_smash(u: Dictionary, tgt) -> void:             # 钻石龟·钻石冲撞(用户2026-07-12改): 短暂蓄力→撞击(保留1.0甲+1.0抗+0.1A物理)+击退300码顺冲撞方向+一点点击飞+流血(层数=0.5A+0.1甲+0.1抗)+3s50%减速
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	u["_anim_lock_until"] = battle._t + battle.DIAMOND_SMASH_CHARGE          # 蓄力期锁定原地聚力(不走不打)
	battle._anticipate(u)
	battle._burst_vfx("res://assets/sprites/vfx/diamond-fortify.png", u["pos"], 72.0, 0.5)   # 蓄力: 水晶能量在身上聚起
	battle._skill_ring(u["pos"], Color(0.6, 0.86, 1.0, 0.5), 40.0)
	battle._pending_shots.append({"delay": battle.DIAMOND_SMASH_CHARGE, "src": u, "fn": _diamond_smash_impact.bind(u, tgt)})

