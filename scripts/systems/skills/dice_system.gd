class_name DiceSystem
extends RefCounted
## 骰子龟技能系统
## 类内名不变;外部名加 battle.

## ★骰子数值单一事实源(用户2026-07-28 第三轮加强·整只 13.3% 全表最弱)。文案在 data/pets.json。
## 【孤注一掷】前方扇形镰刀斩。
const ALLIN_RANGE := 300.0        # 扇形半径(码)
const ALLIN_ARC_DEG := 120.0      # 扇面全角(度)·代码里用半角 = 它的一半
const ALLIN_DMG := 1.5            # 孤注一掷: ×ATK 物理 (1.2→1.5)
const ALLIN_LIFESTEAL := 0.30     # 孤注一掷: 生命偷取
const FLASH_SEG_MIN := 7          # 稳定骰子: 段数下限 (原 4+d6 = 5)
const FLASH_SEG_MAX := 11         # 稳定骰子: 段数上限 (原 4+d6 = 10)
const FLASH_SHIELD_PER_HIT := 0.2 # 稳定骰子: 每穿一次获得 ×ATK 护盾
const FATE_LIFESTEAL := 0.50      # 命运骰子: 释放后首次攻击的生命偷取
## 【命运骰子】掷出的暴击率提升区间(持续到下次释放本技能)。
const FATE_CRIT_MIN := 0.40       # 区间下限
const FATE_CRIT_MAX := 1.30       # 区间上限
## 【稳定骰子】首段系数与逐段递减(段数上下限见上面 FLASH_SEG_*)。
const FLASH_FIRST_COEF := 0.9     # 首段 ×ATK
const FLASH_FALLOFF := 0.10       # 之后每段递减

var battle

func _init(b) -> void:
	battle = b

# 设当前段目标 + 算「穿过落点」(目标位置再往冲刺方向前 overshoot) → 下一段自然从另一侧穿回来
func _dice_dash_set_target(u: Dictionary, tgt) -> void:
	u["dice_dash_target"] = tgt
	u["dice_dash_seg_start"] = battle._t                                  # 本段起始(超时保险)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	u["dice_dash_dir"] = dir
	var land: Vector2 = tgt["pos"] + dir * battle.DICE_DASH_OVERSHOOT     # 落点在目标后方一点(穿过去)
	land.x = clampf(land.x, battle.ARENA.position.x + 20.0, battle.ARENA.end.x - 20.0)   # ★落点clamp进场内(否则算到边界外→被clamp卡死)
	land.y = clampf(land.y, battle.ARENA.position.y + 20.0, battle.ARENA.end.y - 20.0)
	u["dice_dash_land"] = land

# 稳定骰子真冲刺连突(刀妹Irelia Q式): 逐帧固定速位移穿过目标到落点 → 挥剑斩 → 顿0.2s → 下一段. 覆盖正常AI(锁住).
# 稳定骰子真冲刺连突(刀妹Irelia Q式): 逐帧固定速位移穿过目标到落点 → 挥剑斩 → 顿0.2s → 下一段. 覆盖正常AI(锁住).
func _dice_dash_tick(u: Dictionary, delta: float) -> void:
	if battle._t < float(u.get("dice_dash_pause_until", 0.0)):   # 到位后顿一下(0.2s)再冲下一个(用户2026-07-13)
		return
	var tgt = u.get("dice_dash_target", null)
	if tgt == null or not tgt.get("alive", false):
		_dice_dash_set_target(u, _dice_pick_strike_target(u))   # 目标死/无 → 换随机敌(重算落点)
		tgt = u.get("dice_dash_target", null)
	if tgt == null:
		u["dice_dash_active"] = false; u["state"] = "move"
		return
	var ddir: Vector2 = u.get("dice_dash_dir", Vector2.RIGHT)
	var land: Vector2 = u.get("dice_dash_land", tgt["pos"])
	var to_land: Vector2 = land - u["pos"]
	var stuck: bool = battle._t - float(u.get("dice_dash_seg_start", battle._t)) > 1.6   # ★超时保险: 本段冲>1.6s还没到(卡边界)→强制结算
	if to_land.length() <= 26.0 or to_land.dot(ddir) <= 0.0 or stuck:   # 到达落点/已穿过/卡住 → 挥剑斩结算
		u["pos"] = land
		u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
		_dice_dash_hit(u, tgt, ddir)
		u["dice_dash_remaining"] = int(u.get("dice_dash_remaining", 1)) - 1
		u["dice_dash_seg"] = int(u.get("dice_dash_seg", 0)) + 1
		if int(u["dice_dash_remaining"]) <= 0:
			u["dice_dash_active"] = false; u["state"] = "move"
			return
		_dice_dash_set_target(u, _dice_pick_strike_target(u))   # 下一段随机敌(单个目标→从另一侧穿回来)
		u["dice_dash_pause_until"] = battle._t + battle.DICE_DASH_PAUSE       # 顿一下再冲
		return
	u["pos"] += ddir * battle.DICE_DASH_SPD * delta                   # 固定速真位移(沿冲刺方向直线·穿过目标)
	u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
	u["face_right"] = ddir.x > 0.0
	if int(battle._t * 45.0) % 2 == 0:                      # 青蓝刀锋拖尾(刀妹穿刺残影)
		_dice_blade_trail(u["pos"], ddir)

func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
	var scale_i: float = FLASH_FIRST_COEF * pow(1.0 - FLASH_FALLOFF, float(int(u.get("dice_dash_seg", 0))))   # 每段递减10%(回合制falloffPct=10)
	battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, scale_i, tgt), Color("#ff4444"))
	battle._damage._grant_shield(u, float(u["atk"]) * FLASH_SHIELD_PER_HIT, 6.0)   # 每穿一次 +0.2ATK 护盾(用户2026-07-28)
	_dice_blade_slash(tgt["pos"], dir)   # AI挥剑斩(沿冲刺方向)
	battle._melee_lunge(u, tgt)

func _dice_blade_slash(pos2d: Vector2, dir: Vector2) -> void:   # AI挥剑斩弧(dice-slash.png): 立绘朝相机·按冲刺左右镜像(斩弧沿冲刺方向)·放大淡出
	var tex: Texture2D = load("res://assets/sprites/vfx/dice-slash.png")
	if tex == null: return
	var s = Sprite3D.new()
	s.texture = tex; s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # 立绘朝相机(剑光在空中·不糊在地上)
	s.flip_h = dir.x < 0.0                            # 冲刺朝左→镜像 → 斩弧总沿冲刺方向(用户2026-07-13: 方向要对)
	s.shaded = false; s.transparent = true
	s.pixel_size = (170.0 * battle.WS) / float(maxi(1, int(tex.get_height())))
	s.position = battle._world_pos(pos2d, 0.7)
	battle._world.add_child(s)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3(1.35, 1.35, 1.35), 0.16).from(Vector3(0.7, 0.7, 0.7)).set_trans(Tween.TRANS_BACK)
	tw.tween_property(s, "modulate:a", 0.0, 0.18).set_delay(0.05)
	tw.chain().tween_callback(s.queue_free)

# 骰子赌徒之血: 低血→身上泛血色气焰(随已损生命渐强·损30%满·脉动), 满血无. 暗示"血越低暴击越猛".
func _dice_blade_trail(pos2d: Vector2, dir: Vector2) -> void:   # 冲刺青蓝刀锋残影(立绘朝相机·按冲刺左右镜像)
	var tex: Texture2D = load("res://assets/sprites/vfx/dice-slash.png")
	if tex == null: return
	var s = Sprite3D.new()
	s.texture = tex; s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.flip_h = dir.x < 0.0
	s.shaded = false; s.transparent = true
	s.pixel_size = (110.0 * battle.WS) / float(maxi(1, int(tex.get_height())))
	s.position = battle._world_pos(pos2d, 0.55)
	s.modulate = Color(0.6, 0.85, 1.0, 0.5)
	battle._world.add_child(s)
	var tt = battle._reg_tween(); tt.tween_property(s, "modulate:a", 0.0, 0.14); tt.tween_callback(s.queue_free)

func _dice_pick_strike_target(u: Dictionary):                   # 随机敌(用户2026-07-13:不是最近/残血)·射程2000·_enemies_of已跳围栏内蛋(注意龟蛋)
	var cand: Array = []
	for o in battle._targeting._pick_enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(u["pos"]) > 2000.0: continue   # 射程2000
		cand.append(o)
	if cand.is_empty(): return null
	return cand[battle._battle_rng.randi() % cand.size()]

func _dice_scythe_sweep(u: Dictionary, origin: Vector2, dir: Vector2, rng: float, half_deg: float) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/dice-scythe.png")
	if tex == null: return
	var base_ang: float = atan2(dir.y, dir.x)
	var blade = Sprite3D.new()
	blade.texture = tex
	blade.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blade.billboard = BaseMaterial3D.BILLBOARD_DISABLED; blade.axis = Vector3.AXIS_Y   # 贴地
	blade.shaded = false; blade.transparent = true
	var fh: float = float(maxi(1, int(tex.get_height())))
	blade.pixel_size = (rng * 0.85 * battle.WS) / fh          # 镰刀高 ≈ 0.85×射程(盖住扇形纵深)
	battle._world.add_child(blade)
	var tw = battle._reg_tween()
	tw.tween_method(_dice_scythe_step.bind(blade, origin, base_ang, rng, half_deg), 0.0, 1.0, 0.40)
	tw.tween_property(blade, "modulate:a", 0.0, 0.10)
	tw.tween_callback(blade.queue_free)

func _dice_scythe_step(fr: float, blade: Sprite3D, origin: Vector2, base_ang: float, rng: float, half_deg: float) -> void:
	if not is_instance_valid(blade): return
	var a: float = base_ang + deg_to_rad(lerpf(-half_deg, half_deg, fr))   # 从 -60° 扫到 +60°
	var bd = Vector2(cos(a), sin(a))
	blade.rotation = Vector3(0.0, -a - PI * 0.5, 0.0)     # 刀刃切向沿扫掠方向(镰刀立绘上=刀朝上→旋转对齐弧线)
	blade.position = battle._world_pos(origin + bd * (rng * 0.5), 0.16)
	var tr = Sprite3D.new()   # 红拖尾(残影)
	tr.texture = blade.texture
	tr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tr.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tr.axis = Vector3.AXIS_Y
	tr.shaded = false; tr.transparent = true
	tr.pixel_size = blade.pixel_size; tr.rotation = blade.rotation; tr.position = blade.position
	tr.modulate = Color(1.0, 0.28, 0.32, 0.30)
	battle._world.add_child(tr)
	var tt = battle._reg_tween(); tt.tween_property(tr, "modulate:a", 0.0, 0.15); tt.tween_callback(tr.queue_free)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷(用户设计: 前方120°/300码镰刀扇形斩·1.5A物理+30%吸血·用户2026-07-28 1.2→1.5)
	var tgt = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var half_cos: float = cos(deg_to_rad(ALLIN_ARC_DEG * 0.5))   # 半角60°=全120°
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var to_o: Vector2 = o["pos"] - u["pos"]
		var d: float = to_o.length()
		if d > ALLIN_RANGE or d < 1.0: continue
		if dir.dot(to_o / d) < half_cos: continue
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, ALLIN_DMG, o), Color("#ff4444"), ALLIN_LIFESTEAL)
	_dice_scythe_sweep(u, u["pos"], dir, ALLIN_RANGE, ALLIN_ARC_DEG * 0.5)   # 红镰刀贴地弧扫过120°扇形(用户2026-07-13)
	battle._skill_ring(u["pos"], Color(1.0, 0.3, 0.3, 0.35), 52.0)

# 骰子龟·稳定骰子(刀妹Q式·〖#4"刀妹Q式·你仔细设计"〗; 数值取回合制 diceFlashStrike: baseHits=4 / perHitScale=0.9 / falloffPct=10)
#   直接掷段数 FLASH_SEG_MIN~MAX (7~11) 次冲刺; 首段 0.9×ATK 物理(吃暴击), 之后每段递减 10% (0.9 × 0.9^i)
#   每刺间隔 DICE_STRIKE_GAP 秒【分帧铺开】(原来全部在同一帧解算 → 视觉糊成一坨/飘字堆叠)
func _sk_dice_flash_strike(u: Dictionary) -> void:   # 稳定骰子(刀妹Irelia Q·破空斩式·用户2026-07-13): 掷 7~11 段, 每段真冲刺穿到随机敌+挥剑斩·递减10%
	# 用户2026-07-28: 4+d6(5~10段) → 7~11段。直接掷段数而不是"6+d5" —— 后者会让飘字显示 1~5 点,
	# 与"骰子"的六面设定矛盾; 现在飘字直接报段数, 不再假装是点数。
	var count: int = randi_range(FLASH_SEG_MIN, FLASH_SEG_MAX)
	battle._vfx._float_text(u["pos"] + Vector2(0, -64), "稳定骰子! %d刺" % count, Color("#ffd93d"))
	var t0 = _dice_pick_strike_target(u)
	if t0 == null: return
	u["dice_dash_active"] = true                    # 进入真冲刺连突态(逐帧穿刺, 见 _dice_dash_tick)
	u["dice_dash_remaining"] = count
	u["dice_dash_seg"] = 0
	_dice_dash_set_target(u, t0)                    # 设目标+算穿过落点

func _sk_dice_fate(u: Dictionary) -> void:
	if u.get("crit_fate_until", 0.0) > battle._t:           # 撤销未到期旧增益, 防叠加
		u["crit"] -= u.get("crit_fate_amt", 0.0)
		u["crit_dmg"] -= u.get("crit_dmg_fate_amt", 0.0)
	var roll: float = randf_range(FATE_CRIT_MIN, FATE_CRIT_MAX)
	var over: float = maxf(0.0, (u["crit"] + roll) - 1.0)   # 暴击封顶100%, 超出转暴伤
	var add_crit: float = roll - over
	var add_cd: float = over * 1.5
	u["crit"] += add_crit
	u["crit_dmg"] += add_cd
	u["crit_fate_until"] = battle._t + 999.0   # 持续到下次放技能(开头撤旧增益自然重掷·用户设计)
	u["crit_fate_amt"] = add_crit
	u["crit_dmg_fate_amt"] = add_cd
	u["dice_fate_ls"] = true   # 用户2026-07-28: 释放后【首次攻击】附带 50% 生命偷取(在 _on_basic_hit 消费)
	battle._vfx._float_text(u["pos"] + Vector2(0, -64), "命运骰子! +%d%%暴击" % int(roll * 100), Color("#ffd93d"))

# 龟壳·复制: 随机复制 2 个敌方可用技立即释放 (60%效果简化为全效, 留 batch3)
# 龟壳复制期的"非伤害"效果乘数(护盾/治疗/DoT). 伤害走 src["dmg_out_mult"]. 两者都只覆盖【同步段】:
# 被复制技能里延迟触发的子效果(tween/_pending_shots)仍按全效结算 → 见 附录B-07。
