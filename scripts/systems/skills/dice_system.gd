class_name DiceSystem
extends RefCounted
## 骰子龟技能系统
## 类内名不变;外部名加 battle.

## ★骰子数值单一事实源(用户2026-07-28 第三轮加强·整只 13.3% 全表最弱)。文案在 data/pets.json。
## 【孤注一掷】前方扇形镰刀斩。
## 【骰子攻击(普攻)】物理 + 一段按【暴击率】走的固定加成, 真值在主场景普攻表。
const BASIC_ATK_COEF := 0.9      # ×ATK 物理
const BASIC_CRIT_FLAT := 55.0    # + 暴击率 × 此值(文案写成 5500%)
## 【赌徒之血(被动)】按已损生命线性拉暴击率, 到门槛吃满。
const BLOOD_LOST_GATE := 0.30    # 已损这么多生命 → 暴击加成吃满
const ALLIN_RANGE := 300.0        # 扇形半径(码)
const ALLIN_ARC_DEG := 120.0      # 扇面全角(度)·代码里用半角 = 它的一半
const ALLIN_DMG := 1.5            # 孤注一掷: ×ATK 物理 (1.2→1.5)
const ALLIN_LIFESTEAL := 0.30     # 孤注一掷: 生命偷取
const FLASH_SEG_MIN := 7          # 稳定骰子: 段数下限 (原 4+d6 = 5)
const FLASH_SEG_MAX := 11         # 稳定骰子: 段数上限 (原 4+d6 = 10)
const FLASH_SHIELD_PER_HIT := 0.2 # 稳定骰子: 每穿一次获得 ×ATK 护盾
const FLASH_SHIELD_SEC := 6.0     # 稳定骰子护盾持续(秒)·原写死在 _grant_shield 里(10-16)
const FATE_LIFESTEAL := 0.50      # 命运骰子: 释放后首次攻击的生命偷取
## 【命运骰子】掷出的暴击率提升区间(持续到下次释放本技能)。
const FATE_CRIT_MIN := 0.40       # 区间下限
const FATE_CRIT_MAX := 1.30       # 区间上限
## 【稳定骰子】首段系数与逐段递减(段数上下限见上面 FLASH_SEG_*)。
const FLASH_FIRST_COEF := 0.9     # 首段 ×ATK
const FLASH_FALLOFF := 0.10       # 之后每段递减
const FLASH_KEEP := 1.0 - FLASH_FALLOFF   # 推导: 每段为上一段的比例(文案引用)

var battle

func _init(b) -> void:
	battle = b

# 设当前段目标 + 算「穿过落点」(目标位置再往冲刺方向前 overshoot) → 下一段自然从另一侧穿回来
func _dice_dash_set_target(u: Dictionary, tgt) -> void:
	u["dice_dash_target"] = tgt
	u["dice_dash_seg_start"] = battle._t                                  # 本段起始(超时保险)
	_dash_streak_end(u)
	if tgt == null: return
	_dash_streak_begin(u)
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
	dir = DetMath.norm(dir)
	u["dice_dash_dir"] = dir
	var land: Vector2 = tgt["pos"] + dir * battle.DICE_DASH_OVERSHOOT     # 落点在目标后方一点(穿过去)
	land = ArenaShape.clamp_in(land, battle.ARENA, 20)   # ★落点clamp进场内(否则算到边界外→被clamp卡死)
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
	if DetMath.vlen(to_land) <= 26.0 or DetMath.dot(to_land, ddir) <= 0.0 or stuck:   # 到达落点/已穿过/卡住 → 挥剑斩结算
		u["pos"] = land
		u["pos"] = ArenaShape.clamp_in(u["pos"], battle.ARENA)
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
	u["pos"] = ArenaShape.clamp_in(u["pos"], battle.ARENA)
	u["face_right"] = ddir.x > 0.0
	_dash_streak_update(u)                                   # 冲刺光带: 起点 → 当前位置(11-05 换掉每两帧一张的淡蓝残影)

func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
	var scale_i: float = FLASH_FIRST_COEF * DetMath.dpow(1.0 - FLASH_FALLOFF, float(int(u.get("dice_dash_seg", 0))))   # 每段递减10%(回合制falloffPct=10)
	battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, scale_i, tgt), Color("#ff4444"))
	battle._damage._grant_shield(u, float(u["atk"]) * FLASH_SHIELD_PER_HIT, FLASH_SHIELD_SEC)   # 每穿一次 +0.2ATK 护盾(用户2026-07-28)
	_dice_blade_slash(tgt["pos"], dir)   # AI挥剑斩(沿冲刺方向)
	_dice_cut_mark(tgt, DetMath.datan2(dir.y, dir.x))
	_dash_streak_end(u)
	battle._melee_lunge(u, tgt)

## ★2026-11-05 冲刺光带(参考 LoL 艾瑞莉娅 Q 逐帧: 冲刺时人整个拉成一道头亮尾细的长光, 冲到目标那一刻白光一闪)。
##   原来每两帧丢一张半透明淡蓝刀光残影, 在地面上几乎看不出(审核片 11-05)。
##   光带 = 激光束贴图(白热核 + 青光晕, 两端尖)躺平在 0.35 高度, 从本段起点拉到骰子当前位置; 命中后 0.03 秒满亮再 0.14 秒收掉。
##   只是演出, 存在本系统的表里(不往单位字典里加字段: 单位字典进确定性摘要)。
var _dash_fx: Array = []          # [{u, node, from}]
var _streak_tex: Texture2D = null
const DASH_STREAK_THICK := 56.0   # 光带粗(码)·贴地躺平, 相机斜看会压扁一半, 30 码时实拍像一根激光细线
const DASH_STREAK_TAIL := 240.0   # 光带最长(码): 只拖在骰子身后一段彗尾(艾瑞莉娅 Q), 不是整条路径(长冲刺会横穿半场)

func _dash_fx_of(u: Dictionary) -> int:
	for i in range(_dash_fx.size()):
		if is_same(_dash_fx[i]["u"], u):
			return i
	return -1

func _dash_streak_begin(u: Dictionary) -> void:
	if _streak_tex == null:
		_streak_tex = VfxTex._make_laser_beam_tex(Color(0.45, 0.85, 1.0))
	var sp := Sprite3D.new()
	sp.texture = _streak_tex
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sp.axis = Vector3.AXIS_Y
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = battle.WS
	sp.visible = false
	battle._world.add_child(sp)
	_dash_fx.append({"u": u, "node": sp, "from": u["pos"]})
	## 保险: 冲刺被控制打断时(主场景直接把 dice_dash_active 置 false)不会走到 _dash_streak_end ⇒ 2 秒后自己删
	var guard = battle._reg_tween().bind_node(sp)
	guard.tween_interval(2.0)
	guard.tween_callback(sp.queue_free)

func _dash_streak_update(u: Dictionary) -> void:
	var i := _dash_fx_of(u)
	if i < 0: return
	var sp = _dash_fx[i]["node"]   # ★不带类型: 保险删掉之后再赋给 Sprite3D 变量会报「assign previously freed instance」(CI 11-05)
	if not is_instance_valid(sp):
		_dash_fx.remove_at(i)
		return
	var a: Vector2 = _dash_fx[i]["from"]
	var b: Vector2 = u["pos"]
	var d: Vector2 = b - a
	var L: float = d.length()
	if L > DASH_STREAK_TAIL:
		a = b - d / L * DASH_STREAK_TAIL
		d = b - a
		L = DASH_STREAK_TAIL
	if L < 8.0: return
	sp.visible = true
	sp.position = battle._world_pos((a + b) * 0.5, 0.35)
	sp.rotation = Vector3(0.0, -atan2(d.y, d.x), 0.0)
	sp.scale = Vector3((L + 40.0) / 100.0, 1.0, DASH_STREAK_THICK / 16.0)

func _dash_streak_end(u: Dictionary) -> void:
	var i := _dash_fx_of(u)
	if i < 0: return
	var sp = _dash_fx[i]["node"]   # 不带类型(同上)
	_dash_fx.remove_at(i)
	if not is_instance_valid(sp): return
	var tw = battle._reg_tween().bind_node(sp)
	tw.tween_interval(0.03)
	tw.tween_property(sp, "modulate:a", 0.0, 0.14)
	tw.parallel().tween_property(sp, "scale:z", sp.scale.z * 0.3, 0.14)
	tw.tween_callback(sp.queue_free)

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
func _dice_pick_strike_target(u: Dictionary):                   # 随机敌(用户2026-07-13:不是最近/残血)·射程2000·_enemies_of已跳围栏内蛋(注意龟蛋)
	var cand: Array = []
	for o in battle._targeting._pick_enemies_of(u):
		if not o.get("alive", false): continue
		if DetMath.dist(o["pos"], u["pos"]) > 2000.0: continue   # 射程2000
		cand.append(o)
	if cand.is_empty(): return null
	return cand[battle._battle_rng.randi() % cand.size()]

## ★2026-11-05 重做(用户「整个镰刀都是一个平滑运动，这是确定是你学到的东西吗？这个得改呀」; 参考德莱厄斯 Q 逐帧,
##   docs/studies/20261105-镰刀参考-德莱厄斯Q逐帧.md):
##   原来 0.4 秒匀速转 120° + 每帧一张分开的红色复制图, 伤害第 0 帧就跳完、刀 0.4 秒后才扫到人。
##   现在: 0.11 秒扫完(先快后慢) + 连续月牙刀光(SmearVfx) 0.22 秒收掉; 刀经过每个被砍中的敌人那一帧, 敌人身上一道白色斩痕。
const SCYTHE_SWEEP_SEC := 0.11
const SCYTHE_FADE_SEC := 0.22
const SCYTHE_SMEAR_PATH := "res://assets/sprites/vfx/dice-scythe-smear.png"   # 月牙刀光帧表(tools/assetgen/build_scythe_smear.py; 时长/缓出与上面两个常量同一套)
const SCYTHE_SMEAR_FRAMES := 7
const SCYTHE_SMEAR_FPS := 30.0

func _dice_scythe_sweep(u: Dictionary, origin: Vector2, dir: Vector2, rng: float, half_deg: float, hits: Array = []) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/dice-scythe.png")
	if tex == null: return
	var base_ang: float = DetMath.datan2(dir.y, dir.x)
	var half: float = deg_to_rad(half_deg)
	SmearVfx.play_sheet(battle, SCYTHE_SMEAR_PATH, SCYTHE_SMEAR_FRAMES, SCYTHE_SMEAR_FPS, origin, base_ang, rng)
	var blade = Sprite3D.new()
	blade.texture = tex
	blade.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blade.billboard = BaseMaterial3D.BILLBOARD_DISABLED; blade.axis = Vector3.AXIS_Y   # 贴地
	blade.shaded = false; blade.transparent = true
	var fh: float = float(maxi(1, int(tex.get_height())))
	blade.pixel_size = (rng * 0.85 * battle.WS) / fh          # 镰刀高 ≈ 0.85×射程(盖住扇形纵深)
	battle._world.add_child(blade)
	_dice_scythe_step(0.0, blade, origin, base_ang, rng, half)
	var tw = battle._reg_tween().bind_node(blade)
	tw.tween_method(_dice_scythe_step.bind(blade, origin, base_ang, rng, half), 0.0, 1.0, SCYTHE_SWEEP_SEC)
	tw.tween_property(blade, "modulate:a", 0.0, SCYTHE_FADE_SEC * 0.6)
	tw.tween_callback(blade.queue_free)
	for o in hits:                                   # 刀经过谁, 那一帧谁身上一道斩痕
		var to_o: Vector2 = o["pos"] - origin
		var rel: float = wrapf(DetMath.datan2(to_o.y, to_o.x) - base_ang, -PI, PI)
		var s: float = clampf((rel + half) / (2.0 * half), 0.0, 1.0)
		var th = battle._reg_tween()
		th.tween_interval(SCYTHE_SWEEP_SEC * SmearVfx.time_at(s))
		th.tween_callback(_dice_cut_mark.bind(o, base_ang + rel + PI * 0.5))

func _dice_scythe_step(fr: float, blade: Sprite3D, origin: Vector2, base_ang: float, rng: float, half: float) -> void:
	if not is_instance_valid(blade): return
	var a: float = base_ang - half + 2.0 * half * SmearVfx.ease_out(fr)   # 先快后慢: 从 -60° 扫到 +60°
	var bd = Vector2(cos(a), sin(a))
	blade.rotation = Vector3(0.0, -a - PI * 0.5, 0.0)     # 刀刃切向沿扫掠方向(镰刀立绘上=刀朝上→旋转对齐弧线)
	blade.position = battle._world_pos(origin + bd * (rng * 0.5), 0.16)

## 斩痕: 一道沿刀切向的白色细长光, 0.03 秒拉满 → 0.12 秒变细淡出(在单位身上, 立着朝相机)。
func _dice_cut_mark(o: Dictionary, tangent: float) -> void:
	if not o.has("pos"): return
	## ★不能用 _make_blob_texture: 那是【黑色】软阴影(乘白还是黑, 11-05 第一版就是因此看不见)
	if _cut_tex == null:
		_cut_tex = VfxTex._make_slash_texture(Color(1.0, 0.55, 0.6))
	var s := Sprite3D.new()
	s.texture = _cut_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.flip_h = cos(tangent) < 0.0                        # 斩弧方向跟刀走
	s.no_depth_test = true; s.render_priority = 20       # 画在单位身上(不被龟立绘挡住)
	s.pixel_size = (120.0 * battle.WS) / 64.0
	s.position = battle._world_pos(o["pos"], 0.45)
	s.scale = Vector3.ONE * 0.55
	battle._world.add_child(s)
	var tw = battle._reg_tween().bind_node(s)
	tw.tween_property(s, "scale", Vector3.ONE * 1.1, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.10)       # 先满亮 0.05 秒再收(不一出生就淡)
	tw.tween_callback(s.queue_free)
var _cut_tex: Texture2D = null

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷(用户设计: 前方120°/300码镰刀扇形斩·1.5A物理+30%吸血·用户2026-07-28 1.2→1.5)
	var tgt = battle._targeting._nearest_enemy(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
	dir = DetMath.norm(dir)
	var half_cos: float = DetMath.dcos(deg_to_rad(ALLIN_ARC_DEG * 0.5))   # 半角60°=全120°
	var hits: Array = []
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var to_o: Vector2 = o["pos"] - u["pos"]
		var d: float = DetMath.vlen(to_o)
		if d > ALLIN_RANGE or d < 1.0: continue
		if DetMath.dot(dir, to_o / d) < half_cos: continue
		hits.append(o)
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, ALLIN_DMG, o), Color("#ff4444"), ALLIN_LIFESTEAL)
	_dice_scythe_sweep(u, u["pos"], dir, ALLIN_RANGE, ALLIN_ARC_DEG * 0.5, hits)   # 红镰刀贴地弧扫过120°扇形(用户2026-07-13) + 月牙刀光(11-05)
	battle._skill_ring(u["pos"], Color(1.0, 0.3, 0.3, 0.35), 52.0)

# 骰子龟·稳定骰子(刀妹Q式·〖#4"刀妹Q式·你仔细设计"〗; 数值取回合制 diceFlashStrike: baseHits=4 / perHitScale=0.9 / falloffPct=10)
#   直接掷段数 FLASH_SEG_MIN~MAX (7~11) 次冲刺; 首段 0.9×ATK 物理(吃暴击), 之后每段递减 10% (0.9 × 0.9^i)
#   每刺间隔 DICE_STRIKE_GAP 秒【分帧铺开】(原来全部在同一帧解算 → 视觉糊成一坨/飘字堆叠)
func _sk_dice_flash_strike(u: Dictionary) -> void:   # 稳定骰子(刀妹Irelia Q·破空斩式·用户2026-07-13): 掷 7~11 段, 每段真冲刺穿到随机敌+挥剑斩·递减10%
	# 用户2026-07-28: 4+d6(5~10段) → 7~11段。直接掷段数而不是"6+d5" —— 后者会让飘字显示 1~5 点,
	# 与"骰子"的六面设定矛盾; 现在飘字直接报段数, 不再假装是点数。
	var count: int = battle._battle_rng.randi_range(FLASH_SEG_MIN, FLASH_SEG_MAX)   # B 阶段: 掷几段=打几下, 对局结果走受控 PRNG
	battle._vfx._float_text(u["pos"] + Vector2(0, -64), "稳定骰子 %d刺" % count, Color("#ffd93d"))
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
	var roll: float = DetMath.rrange(battle._battle_rng, FATE_CRIT_MIN, FATE_CRIT_MAX)   # B 阶段: 命运暴击的点数是对局结果(方案书 20260916c §2.3 点名的那一处)
	var over: float = maxf(0.0, (u["crit"] + roll) - 1.0)   # 暴击封顶100%, 超出转暴伤
	var add_crit: float = roll - over
	var add_cd: float = over * DamageMath.CRIT_OVERFLOW   # 原写死 1.5, 文案引用的是这个常量
	u["crit"] += add_crit
	u["crit_dmg"] += add_cd
	u["crit_fate_until"] = battle._t + 999.0   # 持续到下次放技能(开头撤旧增益自然重掷·用户设计)
	u["crit_fate_amt"] = add_crit
	u["crit_dmg_fate_amt"] = add_cd
	u["dice_fate_ls"] = true   # 用户2026-07-28: 释放后【首次攻击】附带 50% 生命偷取(在 _on_basic_hit 消费)
	battle._vfx._float_text(u["pos"] + Vector2(0, -64), "命运骰子 +%d%% 暴击率" % int(roll * 100), Color("#ffd93d"))

# 龟壳·复制: 随机复制 2 个敌方可用技立即释放 (60%效果简化为全效, 留 batch3)
# 龟壳复制期的"非伤害"效果乘数(护盾/治疗/DoT). 伤害走 src["dmg_out_mult"]. 两者都只覆盖【同步段】:
# 被复制技能里延迟触发的子效果(tween/_pending_shots)仍按全效结算 → 见 附录B-07。
