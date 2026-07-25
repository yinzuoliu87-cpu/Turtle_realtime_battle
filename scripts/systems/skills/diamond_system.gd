class_name DiamondSystem
extends RefCounted
## 钻石龟技能系统
## 类内簇函数名不变;外部名加 battle. 前缀。

var battle

func _init(b) -> void:
	battle = b

# 滚球位移tick(每帧·在_tick_unit免CC段调): 0→满速4s加速·朝最近敌滚·进120码撞击结算
func _diamond_roll_tick(u: Dictionary, delta: float) -> void:
	var sf: float = clampf((battle._t - float(u.get("roll_start", battle._t))) / 4.0, 0.0, 1.0)   # 0→满速4秒线性加速
	var tgt = battle._nearest_enemy(u)
	if tgt == null:   # 无敌可撞→退出滚动 (用户2026-07-12: 取消6秒超时限制, 滚到撞上为止)
		u["roll_active"] = false; u["state"] = "move"
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	if to_t.length() <= 120.0:                                     # 进入120码→撞击结算
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
	for o in battle._enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(cp) > 120.0: continue             # 撞击点120码小AOE
		var dmg: int = int(u["def"] * (0.1 + 0.9 * sf) + u["mr"] * (0.1 + 0.9 * sf) + o["maxHp"] * (0.02 + 0.18 * sf))   # 按速插值(封板: 0速0.1甲0.1抗2%→满速1.0甲1.0抗20%)
		battle._apply_damage_from(u, o, dmg, Color("#9bdcff"))
		battle._knockback(u, o, 50.0, 1.8, 1.0)                          # 击飞1秒(vy高)
		battle._freeze(o, 0.5 + 2.5 * sf)                                # 眩晕0.5~3s(随速插值·满速3s)
	battle._burst_vfx("res://assets/sprites/vfx/diamond-impact.png", cp, 120.0 + 70.0 * sf, 0.5)   # 水晶碎裂撞击(按速插值·越快越大)
	battle._skill_ring(cp, Color(0.6, 0.86, 1.0, 0.6), 120.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY if sf > 0.6 else battle.JUICE_SHAKE_LIGHT)  # 满速更炸(封板美术L231)

func _diamond_smash_impact(u: Dictionary, tgt) -> void:         # 蓄力结束→冲撞落地结算
	if not u.get("alive", false): return
	if tgt == null or not tgt.get("alive", false):
		tgt = battle._nearest_enemy(u)
	if tgt == null: return
	battle._dash_to(u, tgt, 45.0)
	var dmg: int = int(u["def"] + u["mr"] + u["atk"] * 0.1)     # 保留原撞击伤害(1.0甲+1.0抗+0.1A物理·用户2026-07-12保留)
	battle._apply_damage_from(u, tgt, dmg, Color("#9bdcff"))
	var bstacks: int = maxi(1, roundi(0.5 * float(u["atk"]) + 0.1 * float(u["def"]) + 0.1 * float(u["mr"])))   # 流血层数=0.5A+0.1甲+0.1抗(用户2026-07-12·走既有层数式流血)
	battle._apply_dot_stacks(tgt, "bleed", bstacks, u)
	var prev_slow: float = float(tgt.get("slow_mag", 1.0)) if battle._t < float(tgt.get("slow_until", 0.0)) else 1.0
	battle._knockback(u, tgt, 0.0, battle.DIAMOND_SMASH_KNOCK_VY, battle.DIAMOND_SMASH_PUSH)   # 击退~300码(顺冲撞方向)+一点点击飞
	tgt["slow_until"] = maxf(float(tgt.get("slow_until", 0.0)), battle._t + 3.0)   # 3秒50%减速
	tgt["slow_mag"] = minf(prev_slow, 0.5)
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
