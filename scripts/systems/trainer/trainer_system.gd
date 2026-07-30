class_name TrainerSystem
extends RefCounted
## 训龟大师·场外技能系统(钩锁/冰川/怒火/口哨/AI/普攻·从主场景抽出·2026-07-25)。
## 【训龟大师技能与龟技能/装备分开·用户定向】类内名不变;外部名加 battle.

## ★训龟大师数值常量(2026-07-30 需求3 大师技能审核时补的)。
## 原来这个文件【一个 const 都没有】, 数值全是散在函数里的字面量 ——
## 后果有两个: ①pet_effect_dump 抽不到(它靠展开具名常量) ②verify_trainer_desc
## 没法从常量推期望值, 于是怒火药水/口哨/冰川三个技能的实质数值【门禁一个都不查】,
## 只查了射程和 CD。补成常量后这些数字才进得了门禁。值一律不变, 纯口径修正。
const MS_HASTE_PER_STACK := 0.05  # 魔法石: 每次普攻命中自身 +5% 攻速(可叠·每路开打清零)
const FURY_RADIUS := 300.0       # 怒火药水: 落点生效半径(码)
const FURY_SEC := 5.0            # 怒火药水: buff 持续(秒)
const FURY_HASTE := 1.3          # 怒火药水: 攻速 ×1.3 (+30%)
const FURY_MOVE := 1.25          # 怒火药水: 移速 ×1.25 (+25%)
const FURY_ECHARGE := 1.25       # 怒火药水: 龟能充能 ×1.25 (+25%)
const WHISTLE_TEMPHP := 700.0    # 口哨①: 临时最大生命
const WHISTLE_TEMPHP_SEC := 5.0  # 口哨①: 临时生命持续(到期按比例削)  ★文案没写这个时长
const WHISTLE_WAVE_DMG := 200.0  # 口哨②: 灵体气波物理伤害
const WHISTLE_WAVE_KB := 100.0   # 口哨②: 击飞距离
const WHISTLE_SHRED_SEC := 5.0   # 口哨②: 削甲持续(秒)  ★文案没写这个时长
const WHISTLE_BERSERK_ATK := 0.2 # 口哨③: 攻击力 +20%
const WHISTLE_BERSERK_LS := 20   # 口哨③: 生命偷取 +20(定值)
const WHISTLE_BERSERK_SEC := 4.0 # 口哨③: 狂暴/免死 持续(秒)
const GLACIER_SLOW_MAG := 0.6    # 冰川: 移速 ×0.6 (-40%)
## ★地面印记/符文环的【世界直径·米】—— 与"效果半径"是两码事, 千万别再用效果半径当尺寸。
##   踩过的坑(2026-07-30 目视审核抓到): 猎龟令印记原本写
##     pixel_size = HUNT_TAUNT_R * 2 * WS / 128   → 直径 19.20 m
##   而战场 ARENA 只有 38.3 × 17.5 m —— 圈占战场宽的 50%、【比纵深还长 110%】。
##   后果有两层, 两层都致命:
##     ①读不出信息: 这一技的核心信息是"哪只龟被标了", 圈大到看不出圆心在谁身上;
##     ②像素崩了: 128px 贴图铺 19.2 m = 0.150 m/texel, 是龟像素格(≈0.05)的 3 倍粗,
##       "猩红破碎环 + 橙金刻度"糊成红板砖 + 黄色块, 破坏全局像素单位。
##   ★嘲讽半径(400码)【不画】—— 用户 2026-07-30 拍板: 范围本不需精确告知玩家,
##     画它就必然要一张 19 m 尺度的专用低频素材(细虚线环), 现在不做。
const SIGIL_D_M := 2.6           # 猎龟令印记: 略大于龟(龟身高 2.0 m) → 128px 铺 2.6m = 0.020 m/texel(比龟还细·锐利)
const TAME_RUNE_D_M := 3.6       # 驯服符文环: 原值(150码×WS)换算过来就是 3.6 m, 尺度本来就对, 只是改成显式常量

var battle

## 在飞的钩子(真 skillshot 逐帧推进; 见 _cast_hook 的注释)。
var _flights: Array = []

## ★AI_TRAINER_LEFT=1: 让【我方】大师也交给 AI 托管(游走 + CD 好了自动放主动)。
## 只给无头仿真用 —— 正式对局里我方大师是玩家操控的, AI 不接管。
## 起因(2026-07-27 队列模拟): 原来只有右侧大师有 AI, 左侧全程站着不动、一个主动技都不放
## → 左右两侧系统性不对称, 机器人互打的胜负数据作废, 随机分配的五选一技能对左侧也完全是摆设。
## ★用 get_environment != "" 而不是 has_environment: 后者对"设了但为空"也返回 true,
##   会让"关掉开关"的写法(set_environment(name, ""))静默失效 —— 探针第一版就栽在这。
var _ai_left_trainer := OS.get_environment("AI_TRAINER_LEFT") != ""


func _init(b) -> void:
	battle = b

func _trainer_input_vec() -> Vector2:
	if battle._joystick != null and is_instance_valid(battle._joystick):
		return battle._joystick.value
	var v = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v.normalized() if v.length() > 1.0 else v


## 找我方训龟大师(没有则 null)
func _trainer_move_by(u: Dictionary, dir: Vector2, delta: float) -> void:
	if battle._t < float(u.get("_cast_lock_until", 0.0)):
		return   # 甩钩/施法前摇+飞行期间站定(锤石Q口径·用户2026-07-24)
	if dir.length() < 0.001:
		return
	var spd: float = float(u.get("move_spd", battle.TRAINER_MOVE_SPD))
	u["pos"] += dir * spd * delta
	# ★clamp 进战场 —— 不夹的话摇杆一直推就飞出地图外了
	u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
	if absf(dir.x) > 0.05:
		u["face_right"] = dir.x > 0.0


## 摆位阶段能不能拖这个单位: 只拖我方(left)非蛋非召唤非训龟大师(用户2026-07-23 点6)。
## ★抽成纯函数便于门禁直接测(不用起 3D 场景)。
func _trainer_ticks_active() -> bool:
	return not battle._over and battle._dl_state != "place" and not battle._dl_sys._dl_is_present() and not battle._edit_mode


func _trainer_input_tick(delta: float) -> void:
	if not _trainer_ticks_active():
		return
	var u = battle._my_trainer()
	if u == null:
		return
	_trainer_move_by(u, _trainer_input_vec(), delta)


## 训龟大师普攻: 站定扔石头, 抛物线飞向最近敌, 命中 1 物理(用户2026-07-22:「射程2000扔石头1物理」)。
## ★双方的训龟大师都要打(己方玩家操控但攻击自动、敌方人机), 所以对【全体 is_trainer】跑。
##   它不被主动索敌(见 _nearest_enemy 的跳过), 但【它自己会索敌开火】—— 这两件事不矛盾:
##   前者是"别人能不能锁它", 后者是"它能不能锁别人"。
func _tick_trainer_attacks(delta: float) -> void:
	if not _trainer_ticks_active():
		return   # ★摆位/呈现/编辑期大师不投掷(用户2026-07-23 点6: 战斗没开始就别扔石头)
	for u in battle._units:
		if not u.get("is_trainer", false) or not u.get("alive", false):
			continue
		u["_tr_atk_cd"] = maxf(0.0, float(u.get("_tr_atk_cd", 0.0)) - delta)
		if float(u["_tr_atk_cd"]) > 0.0:
			continue
		var tgt = battle._targeting._nearest_enemy_for_trainer(u)
		if tgt == null:
			continue
		# 魔法石(被动): 每次攻击 +5% 攻速(可叠·本场结束重置) → 攻击间隔按叠层缩短
		var haste: float = 1.0 + MS_HASTE_PER_STACK * float(u.get("_ms_stacks", 0)) if str(u.get("_tr_passive", "")) == "magic_stone" else 1.0
		u["_tr_atk_cd"] = battle.TRAINER_ATK_INTERVAL / haste
		# 朝向目标(扔之前转身), 再播扔石头动作
		u["face_right"] = tgt["pos"].x > u["pos"].x
		u["_tr_throw_vec"] = tgt["pos"] - u["pos"]   # R6-B 4方向: 扔石头朝向目标
		u["_tr_throw_t0"] = battle._t
		u["_tr_throw_until"] = battle._t + 0.64       # 7帧@11fps 扔石头动画时长(_update_trainer_anim 播一次)
		_trainer_throw_anim(u)
		# ★魔法石那段魔法伤害【跟着石头走】, 不在这里立刻结算 ——
		#   用户 2026-07-28 报"石头命中只看到一个伤害数字": 根因不是少了一段,
		#   而是两段【在时间上错开】: 魔法在扔出瞬间就跳字, 物理要等石头飞到目标(0.25~0.9秒)。
		#   现在把魔法标进弹道(ms_onhit), 由 _step_projectiles 在命中那一刻和物理一起结算。
		battle._ballistics._fire_trainer_rock(u, tgt, str(u.get("_tr_passive", "")) == "magic_stone")


# ══════════════════════════════════════════════════════════════
# §HOOK 钩锁技能 (点3·法术圆盘第一个技能, 用户2026-07-23。参考 LoL 锤石Q)
# 大师朝方向甩出钩锁(射程600), 钩住第一个敌人 → 眩晕4秒 + 4秒内每秒朝大师拖70码 + 期间受伤+25%; CD20秒, 空放返还10秒。
# ★结算逻辑从演出里抽出可测(照海盗钩索/CLAUDE.md §3.5): _hook_grab 是纯效果, _cast_hook 判命中, 都不依赖 tween。
# ══════════════════════════════════════════════════════════════

## 从 trainer 沿 dir 方向找【射程内】第一个可钩的敌人(600码内、线上最近)。走 battle._targeting._pick_enemies_of(不含大师/不可选)。
func _hook_first_target(trainer: Dictionary, dir: Vector2):
	if dir.length() < 0.01:
		return null
	var d = dir.normalized()
	var best = null
	var bd: float = battle.HOOK_RANGE * battle.HOOK_RANGE
	for o in battle._targeting._pick_enemies_of(trainer):
		if not battle._on_line(trainer["pos"], d, o["pos"], 80.0):   # 带宽80(视觉留美术, 文案不写)
			continue
		var dd: float = (o["pos"] - trainer["pos"]).length_squared()
		if dd <= bd:
			bd = dd; best = o
	return best

## ★主动技能统一入口: 按大师装配的 _tr_active 分派。aim=施法方向/点(相对大师的向量)。返回是否"命中/成功"(供AI/测试)。
## 冷却门在各技能里自查 _active_cd(所有主动共用这一个冷却字段·单槽)。
func _cast_active(trainer: Dictionary, aim: Vector2) -> bool:
	if trainer == null or not trainer.get("alive", false):
		return false
	match str(trainer.get("_tr_active", "hook")):
		"hook":        return _cast_hook(trainer, aim)
		"fury_potion": return battle._cast_fury_potion(trainer, aim)
		"whistle":     return battle._cast_whistle(trainer, aim)
		"glacier":     return battle._cast_glacier(trainer, aim)
		"hunt_order":  return _cast_hunt_order(trainer, aim)
		"tame":        return _cast_tame(trainer, aim)
	return false

## 施放钩锁 —— 真 skillshot(2026-07-30 重做)。
##
## ★★ 改前是【出手瞬间就判定命中】的假 skillshot:
##   _hook_first_target 在出手那一刻沿方向选定目标, 算好 arrive, 然后 _pending_shots
##   定时到点【必钩】(唯一条件只是"还活着")。飞行期间目标走出路径/跑出射程/绕到背后
##   都无效。代码注释自己都写着「返回是否【将】命中」。
##
##   决定性的一条: HOOK_MISSILE_SPD 那行注释是
##   「用户2026-07-26 再−40%: 950→570·【更像可躲skillshot】」——
##   用户当时降速 40% 就是为了让它可躲, 而命中判定在出手瞬间, 那次降速【根本没让它变可躲】,
##   只是让钩子飞得更慢、看起来像能躲。飞得越慢, 这个"假可躲窗口"越长(现在整整 1.05 秒)。
##   用户 2026-07-30:「lol锤石的Q哪有这么锁的？」
##
## ★成因推测: 注释写「结算逻辑从演出里抽出可测(照海盗钩索/CLAUDE.md §3.5)」——
##   §3.5 的目标是【别让数值结算依赖演出 tween】(海盗钩索那次连红三次的教训), 这是对的;
##   但实现时把【命中判定】也一起挪到了出手瞬间, 过头了。
##   正确做法两者兼得: 钩头位置按 delta 逐帧推进(不用 tween → 无头也稳、可测),
##   每帧做碰撞检测(真 skillshot → 能躲)。推进挂在 _tick_hooks, 它本来就在 sim tick 里。
##
## 出手时【不知道会不会命中】, 所以:
##   · 返回值语义改成「是否成功放出去」(原来是"是否将命中")。★游戏内三处调用都不看返回值,
##     只有 verify_hook 断言它 —— 已同步改。
##   · CD 出手即进 HOOK_CD(锤石 Q 同); 飞满射程未命中才【返还】成 HOOK_CD_MISS。
##   · 甩钩站定按"飞满射程"算, 命中时提前解锁。
func _cast_hook(trainer: Dictionary, dir: Vector2) -> bool:
	if trainer == null or not trainer.get("alive", false):
		return false
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	var d: Vector2 = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	trainer["_active_cd"] = battle.HOOK_CD                     # 出手即进 CD; 空放到底再返还
	var full_t: float = battle.HOOK_WINDUP + battle.HOOK_RANGE / battle.HOOK_MISSILE_SPD
	trainer["_cast_lock_until"] = battle._t + full_t           # 甩钩期站定(命中时提前解)
	var hook: Sprite3D = _hook_head_node(trainer["pos"])
	_flights.append({"src": trainer, "dir": d, "from": trainer["pos"],
		"t": 0.0, "node": hook})
	return true


## 钩头节点(纯演出容器; 位置由 _tick_hook_flights 每帧更新 —— 不用 tween)。
func _hook_head_node(from2d: Vector2) -> Sprite3D:
	if battle._world == null:
		return null
	var hook := Sprite3D.new()
	var hp := "res://assets/sprites/vfx/trainer-hook.png"
	if ResourceLoader.exists(hp):
		hook.texture = load(hp)
		hook.pixel_size = (44.0 * battle.WS) / float(maxi(1, hook.texture.get_height()))
	else:
		push_warning("[钩锁] 钩头素材缺失: %s" % hp)
		hook.texture = VfxTex._make_bolt_texture(Color("#9fd8ff"))
		hook.pixel_size = 0.02
	hook.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hook.shaded = false; hook.transparent = true
	hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hook.position = battle._world_pos(from2d, 1.0)
	battle._world.add_child(hook)
	return hook


## 钩头【当前位置】周围 HOOK_HIT_R 内的敌人(最近的那个)。这就是真 skillshot 的碰撞判定。
## ★与旧的 _hook_first_target 的区别: 那个是【出手瞬间沿整条射线】扫; 这个是【钩头此刻在哪】。
##   前者=锁定, 后者=能躲。
func _hook_hit_at(src: Dictionary, pos: Vector2):
	var best = null
	var bd: float = battle.HOOK_HIT_R * battle.HOOK_HIT_R
	for o in battle._targeting._pick_enemies_of(src):
		var dd: float = (o["pos"] - pos).length_squared()
		if dd <= bd:
			bd = dd; best = o
	return best


## 每帧推进所有在飞的钩子。★delta 制、不依赖 tween → 无头可测(CLAUDE.md §3.5)。
## 由 _tick_hooks 调用(后者已在 RealtimeBattle3DScene._sim_step 的 sim tick 里)。
func _tick_hook_flights(delta: float) -> void:
	if _flights.is_empty():
		return
	var keep: Array = []
	for f in _flights:
		var src: Dictionary = f["src"]
		if not src.get("alive", false):                        # 大师死了 → 钩子作废
			_hook_head_free(f)
			continue
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) < battle.HOOK_WINDUP:                 # ① 前摇: 钩子还没出手
			keep.append(f)
			continue
		var flown: float = (float(f["t"]) - battle.HOOK_WINDUP) * battle.HOOK_MISSILE_SPD
		if flown >= battle.HOOK_RANGE:                         # ③ 飞满射程未命中 → 空放返还
			src["_active_cd"] = battle.HOOK_CD_MISS
			src["_cast_lock_until"] = battle._t
			_hook_head_free(f)
			continue
		var p: Vector2 = (f["from"] as Vector2) + (f["dir"] as Vector2) * flown
		var nd = f.get("node", null)
		if nd is Sprite3D and is_instance_valid(nd):
			(nd as Sprite3D).position = battle._world_pos(p, 1.0)
		if battle._world != null:
			_hook_chain(src["pos"], p)                         # 链条: 大师 ↔ 钩头当前位置
		# ② ★每帧碰撞 —— 这一行就是"能躲"的全部: 判的是钩头此刻的位置, 不是出手时选的人
		var v = _hook_hit_at(src, p)
		if v != null:
			_hook_grab(src, v)
			src["_cast_lock_until"] = battle._t                # 命中即解锁(不用站到飞满)
			_hook_hit_fx(p)
			_hook_head_free(f)
			continue
		keep.append(f)
	_flights = keep


## 回收钩头节点。
func _hook_head_free(f: Dictionary) -> void:
	var nd = f.get("node", null)
	if nd is Sprite3D and is_instance_valid(nd):
		(nd as Sprite3D).queue_free()

## ── 怒火药水(主动·CD16·700码点·用户2026-07-23 需求): 丢药水→落点300码内友军 5秒 +30%攻速 +25%龟能充能 +25%移速 ──
func _fury_apply_buffs(trainer: Dictionary, point: Vector2) -> int:
	var side: String = str(trainer.get("side", ""))
	var n: int = 0
	for o in battle._units:
		if not o.get("alive", false) or o.get("is_trainer", false):
			continue
		if str(o.get("side", "")) != side:
			continue
		if o["pos"].distance_to(point) > FURY_RADIUS:
			continue
		o["haste_mult"] = FURY_HASTE;      o["haste_until"] = battle._t + FURY_SEC   # +30% 攻速
		o["move_buff_mult"] = FURY_MOVE;   o["move_buff_until"] = battle._t + FURY_SEC   # +25% 移速
		o["echarge_mult"] = FURY_ECHARGE;  o["echarge_until"] = battle._t + FURY_SEC   # +25% 龟能充能速率
		battle._buff_aura(o, Color(1.0, 0.45, 0.2, 0.55), 5.0)                # R2-3 受益友军红橙脚下光环5秒
		battle._body_glow(o, Color(1.0, 0.03, 0.03, 0.6), 5.0)               # R2-3 身体发纯红怒火光5秒(纯红·适中alpha防washed成粉·用户2026-07-26)
		n += 1
	return n

## 怒火药水演出: 抛物线飞到落点 → 橙红 splash + 怒火圈(纯观感)。素材(原图)待 R1g, 暂用火光占位。
func _fury_dramatize(trainer: Dictionary, point: Vector2) -> void:
	if battle._world == null:
		return
	_trainer_throw_anim(trainer)                 # R4 ② 投掷前摇(大师举瓶挥臂·复用扔石头动画)
	var from2d: Vector2 = trainer["pos"]
	var tex = load("res://assets/sprites/vfx/fury-potion.png") if ResourceLoader.exists("res://assets/sprites/vfx/fury-potion.png") else VfxTex._make_fire_glow_tex()
	var pot = Sprite3D.new()
	pot.texture = tex; pot.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; pot.shaded = false; pot.transparent = true
	pot.pixel_size = (40.0 * battle.WS) / float(maxi(1, tex.get_height()))
	pot.modulate = Color(1.0, 0.55, 0.25)
	battle._world.add_child(pot)
	var peak: float = 2.4
	var ct = [0.0]
	var tw = battle._reg_tween()
	tw.tween_interval(battle.HOOK_WINDUP)
	tw.tween_method(func(p: float) -> void:   # R4 ③ 抛物线飞 + 橙红拖尾
		if not is_instance_valid(pot): return
		var cp: Vector2 = from2d.lerp(point, p)
		var ph: float = 0.9 + peak * sin(PI * p)
		pot.position = battle._world_pos(cp, ph)
		ct[0] += 0.02
		if ct[0] >= 0.07:
			ct[0] = 0.0
			var tg = battle._glow_bb(cp, ph, 28.0, Color(1.0, 0.5, 0.2, 0.6))   # 拖尾一粒橙火淡出
			var trt = battle._reg_tween()
			trt.tween_property(tg.material_override, "albedo_color", Color(1.0, 0.5, 0.2, 0.0), 0.3)
			trt.tween_callback(tg.queue_free)
	, 0.0, 1.0, maxf(0.15, from2d.distance_to(point) / 800.0))
	tw.tween_callback(func() -> void:   # R4 ④ 落地: 怒火圈 + 爆点 + 轻震屏
		if is_instance_valid(pot): pot.queue_free()
		battle._splash_ring_bold(point, Color(1.0, 0.55, 0.22, 0.85), 300.0)  # 300码怒火冲击环
		battle._burst_vfx("res://assets/sprites/vfx/cannon-blast.png", point, 120.0, 0.4)
		battle._shake(battle.JUICE_SHAKE_HEAVY))

## R5 口哨前摇: 大师头顶冒出♪音符, 上浮淡出(施法提示·所有分支共用)。
func _whistle_note(u: Dictionary) -> void:
	if battle._world == null:
		return
	var lb := Label3D.new()
	lb.text = "♪"
	lb.font_size = 110
	lb.pixel_size = 0.012
	lb.modulate = Color(1.0, 0.95, 0.55, 1.0)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	var base: Vector3 = battle._world_pos(u["pos"], float(u.get("height", 0.0)) + 2.1)
	lb.position = base
	battle._world.add_child(lb)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(lb, "position", base + Vector3(0.25, 0.9, 0.0), 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lb, "modulate:a", 0.0, 0.75)
	tw.chain().tween_callback(lb.queue_free)

## ── 口哨(主动·CD14·无目标·用户2026-07-23): 随机 3 选 1 —— 临时血 / 灵体小龟气波 / 狂暴免死 ──
func _whistle_temphp(trainer: Dictionary):
	var ally = battle._random_ally(trainer)
	if ally == null:
		return null
	battle._apply_temp_maxhp(ally, WHISTLE_TEMPHP, WHISTLE_TEMPHP_SEC)
	battle._skill_ring(ally["pos"], Color(0.5, 1.0, 0.6, 0.7), 46.0)   # 施加瞬闪
	battle._buff_aura(ally, Color(0.45, 1.0, 0.55, 0.5), 5.0)          # R2-3 临时血绿光环5秒(持续)
	if battle._world != null:                                          # R5 绿光柱(生命涌入·竖向拉长的glow)
		var pil = battle._glow_bb(ally["pos"], 1.3, 46.0, Color(0.45, 1.0, 0.55, 0.0))
		pil.scale = Vector3(0.55, 3.4, 1.0)
		var pt = battle._reg_tween()
		pt.tween_property(pil.material_override, "albedo_color", Color(0.45, 1.0, 0.55, 0.9), 0.12)
		pt.tween_property(pil.material_override, "albedo_color", Color(0.45, 1.0, 0.55, 0.0), 0.5)
		pt.tween_callback(pil.queue_free)
	return ally

## ★临时最大生命(可测·纯函数): +amt maxHp&hp, sec 秒后到期【按比例削】(§2.4: 当前血 × 新上限/旧上限)。
func _whistle_spirit_wave(trainer: Dictionary) -> int:
	var tgt = battle._targeting._nearest_enemy_for_trainer(trainer)
	if tgt == null:
		return 0
	var origin: Vector2 = trainer["pos"]
	var dir: Vector2 = (tgt["pos"] - origin).normalized()
	var n: int = 0
	for o in battle._targeting._pick_enemies_of(trainer):   # 定向(不选大师/组装机甲)
		if not battle._on_line(origin, dir, o["pos"], 80.0):
			continue
		o["def_shred_until"] = battle._t + WHISTLE_SHRED_SEC   # 先削甲(30%·让这一发也吃到)
		battle._damage._apply_damage_from(trainer, o, battle._resolve_dmg(trainer, WHISTLE_WAVE_DMG, o, false), Color("#8fd0ff"), 0.0, false, false)   # 200物理
		battle._damage._knockback(trainer, o, WHISTLE_WAVE_KB)   # 击飞
		n += 1
	_whistle_spirit_dramatize(trainer, origin, dir)
	return n

## 效果③狂暴: 随机友军 +20%攻击力 +20%吸血(4秒) + 免疫死亡(4秒·deathfloor血锁不死)。
func _whistle_berserk(trainer: Dictionary):
	var ally = battle._random_ally(trainer)
	if ally == null:
		return null
	_whistle_berserk_on(ally)
	return ally

## ★狂暴纯效果(可测): 对指定友军上 buff。
func _whistle_berserk_on(ally: Dictionary) -> void:
	battle._damage._buff(ally, "atk", WHISTLE_BERSERK_ATK, true, WHISTLE_BERSERK_SEC)   # +20% 攻击力
	battle._damage._buff(ally, "lifesteal", WHISTLE_BERSERK_LS, false, WHISTLE_BERSERK_SEC)   # +20% 生命偷取
	ally["deathfloor_until"] = battle._t + WHISTLE_BERSERK_SEC   # 4秒免疫死亡(血锁≥1)
	battle._skill_ring(ally["pos"], Color(1.0, 0.4, 0.3, 0.75), 46.0)   # 施加瞬闪
	battle._buff_aura(ally, Color(1.0, 0.32, 0.3, 0.55), 4.0)           # R2-3 狂暴红战意光环4秒(持续)
	if battle._world != null:                                          # R5 免死金盾闪 + 吸血血滴
		var sh = battle._glow_bb(ally["pos"], 1.0, 92.0, Color(1.0, 0.85, 0.35, 0.9))   # 金盾闪(免疫死亡)
		var st = battle._reg_tween(); st.set_parallel(true)
		st.tween_property(sh, "scale", Vector3.ONE * 1.9, 0.3)
		st.tween_property(sh.material_override, "albedo_color", Color(1.0, 0.85, 0.35, 0.0), 0.42)
		st.chain().tween_callback(sh.queue_free)
		for k in range(5):                                            # 红血滴上溅淡出(吸血)
			var a: float = float(k) * TAU / 5.0
			var d = battle._glow_bb(ally["pos"] + Vector2(cos(a), sin(a)) * 18.0, 0.7, 16.0, Color(0.9, 0.12, 0.12, 0.9))
			var dt = battle._reg_tween(); dt.set_parallel(true)
			dt.tween_property(d, "position", d.position + Vector3(0.0, 0.5, 0.0), 0.32)
			dt.tween_property(d.material_override, "albedo_color", Color(0.9, 0.12, 0.12, 0.0), 0.42)
			dt.chain().tween_callback(d.queue_free)

## 灵体小龟演出: 蓝幽灵小龟入场(spirit-turtle.png·缺图则只放气波不崩) + 蓝气波束(qibo-ball.png 真气波素材)。
func _whistle_spirit_dramatize(trainer: Dictionary, origin: Vector2, dir: Vector2) -> void:
	if battle._world == null:
		return
	_spawn_spirit_turtle(origin)
	battle._skill_ring(origin, Color(0.5, 0.8, 1.0, 0.6), 40.0)
	# R5 真气波(照小龟龟派气波 _sk_basic_chiwave 观感·chiwave-fly 6帧循环动画火球·沿dir恒速300码/秒飞·带青光晕), 替静态 qibo-ball 束
	var end2d: Vector2 = origin + dir * 500.0
	var ball = Sprite3D.new()
	ball.texture = load("res://assets/sprites/vfx/chiwave-fly.png")
	ball.hframes = 6; ball.frame = 0
	ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ball.shaded = false; ball.transparent = true
	ball.pixel_size = (150.0 * battle.WS) / 128.0
	ball.position = battle._world_pos(origin, 0.9)
	battle._world.add_child(ball)
	battle._orient_billboard_dir(ball, Vector3(dir.x, 0.0, dir.y))
	var glow = battle._glow_bb(origin, 0.9, 180.0, Color(0.5, 0.86, 1.0, 0.7))   # 青光晕随波
	var flydur: float = 500.0 / 300.0                                            # 300码/秒(小龟气波口径)
	var mtw = battle._reg_tween()
	mtw.tween_method(func(p: float) -> void:
		if not is_instance_valid(ball): return
		var cp: Vector2 = origin.lerp(end2d, p)
		ball.position = battle._world_pos(cp, 0.9)
		ball.frame = int(p * 18.0) % 6                                          # 6帧循环
		if is_instance_valid(glow): glow.position = battle._world_pos(cp, 0.9)
	, 0.0, 1.0, flydur)
	mtw.tween_callback(func() -> void:
		if is_instance_valid(ball): ball.queue_free()
		if is_instance_valid(glow): glow.queue_free())

## 蓝幽灵小龟短暂现身: 幽蓝 billboard 从大师身前淡入上浮再淡出(纯演出·缺图优雅跳过, 不阻塞气波)。
func _spawn_spirit_turtle(origin: Vector2) -> void:
	var path = "res://assets/sprites/vfx/spirit-turtle.png"
	if not ResourceLoader.exists(path):
		return                                     # 素材未就绪: 只放气波(R1g 前的优雅降级)
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (battle.TARGET_BODY_H * 0.55) / float(maxi(1, tex.get_height()))   # 比正规龟小一号(灵体小龟)
	spr.modulate = Color(0.7, 0.9, 1.0, 0.0)       # 幽蓝, 从透明淡入
	var base: Vector3 = battle._world_pos(origin, 1.1)
	spr.position = base
	battle._world.add_child(spr)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(spr, "modulate:a", 0.9, 0.15)
	tw.parallel().tween_property(spr, "position", base + Vector3(0.0, 0.8, 0.0), 0.75)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(spr.queue_free)

## ── 冰川(主动·CD17·方向·用户2026-07-23): 沿方向生成 500码 冰川带(持续6秒); 站带上的敌 -40%移速 + 受伤+20% ──
func _tick_glaciers(_delta: float) -> void:
	if battle._glacier_zones.is_empty():
		return
	var keep: Array = []
	for z in battle._glacier_zones:
		if battle._t >= float(z["until"]):
			continue
		keep.append(z)
		var from2d: Vector2 = z["from"]
		var dir: Vector2 = z["dir"]
		var zlen: float = float(z["len"])
		var half_w: float = float(z["width"]) * 0.5
		for o in battle._units:
			if not o.get("alive", false) or o.get("is_trainer", false):
				continue
			if str(o.get("side", "")) == str(z["side"]):
				continue   # 只冻【敌方】
			var rel: Vector2 = o["pos"] - from2d
			var along: float = rel.dot(dir)
			if along < 0.0 or along > zlen:
				continue
			if (rel - dir * along).length() > half_w:
				continue
			o["slow_until"] = battle._t + 0.2      # -40% 移速(slow_mag 0.6)
			o["slow_mag"] = GLACIER_SLOW_MAG
			o["glacier_vuln_until"] = battle._t + 0.2   # 受伤 +20%(见 _mitigate_incoming)
			if battle._world != null and battle._t > float(o.get("_frost_until", 0.0)):
				battle._buff_aura(o, Color(0.55, 0.85, 1.0, 0.5), 1.6, 40.0)   # R4 ⑤ 敌脚蓝寒雾(在区内每~1.4s续=持续寒气)
				o["_frost_until"] = battle._t + 1.4
	battle._glacier_zones = keep

## 冰川带演出【R6·专属美术·分层重做·不复用·用户 2026-07-26「重新设计·别复用」】
##   旧版糊: ice-field(冰云 blob)硬拉 8 倍成糊带·无结构·瞬现·同青地板色。改成:
##   ① 冻地冰河(glacier-ground 平铺不拉伸·近→远) ② 冰脊(glacier-crystals 逐根升起·持6s·收尾下沉)
##   ③ 寒雾(加性图元) ④ 出现冲击(冲击环+震屏)。纯演出·_world==null 直接跳(判定在 _tick_glaciers)。
##   变化全走【索引确定性】不用裸随机(护 rng_discipline 棘轮 + 演出可复现)。
func _glacier_dramatize(from2d: Vector2, dir: Vector2) -> void:
	if battle._world == null:
		return
	var zlen: float = 500.0
	var life: float = 6.0
	var perp: Vector2 = Vector2(-dir.y, dir.x)             # 带的横向单位向量
	var heavy: bool = battle._glacier_zones.size() <= 2    # 降级: 场上>2条冰川只铺地不长冰晶(护帧)

	# ── ④ 出现冲击(origin) ──
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._splash_ring_bold(from2d, Color(0.78, 0.93, 1.0, 0.7), 72.0)

	# ── ① 冻地冰河: 沿方向平铺 6 张(不拉伸·近→远逐张淡入) ──
	var tiles: int = 6
	for i in range(tiles):
		var f: float = float(i) / float(tiles - 1)     # i=0 贴大师脚下·i=末覆盖 500 末端(从脚下起铺·用户 2026-07-26)
		var gp: Vector2 = from2d + dir * (zlen * f) + perp * (12.0 * float((i % 3) - 1))
		_glacier_ground_tile(gp, dir, 118.0, life, float(i) * 0.03, i)

	# ── ② 冰脊冰晶: 中线+两侧交错·近→远逐根升起·持 life·收尾下沉 ──
	if heavy:
		var spikes: int = 9
		for i in range(spikes):
			var f: float = 0.06 + 0.94 * float(i) / float(spikes - 1)   # 从脚下略前(~30码·不戳穿大师身)起, 到 500 末端
			var lateral: float = 0.0
			if i % 3 == 1: lateral = 28.0
			elif i % 3 == 2: lateral = -28.0
			var sp: Vector2 = from2d + dir * (zlen * f) + perp * lateral
			var sz: float = 66.0 if i % 3 == 0 else 46.0   # 中线大·两侧小
			_glacier_spike(sp, sz, life, float(i) * 0.045)

	# ── ③ 寒雾: 沿带 5 团加性蓝白上飘(氛围 + 压过青地板) ──
	for i in range(5):
		var f: float = (float(i) + 0.5) / 5.0
		var mp: Vector2 = from2d + dir * (zlen * f) + perp * (30.0 * float((i % 3) - 1))
		_glacier_mist(mp, float(i) * 0.09)

## 冻地冰河一张: glacier-ground 躺平贴地·对齐方向·淡入→持 life→淡出。pixel_size 定尺=不拉伸。
func _glacier_ground_tile(pos2d: Vector2, dir: Vector2, size_px: float, life: float, delay: float, idx: int) -> void:
	var t: Texture2D = load("res://assets/sprites/vfx/glacier-ground.png")
	if t == null:
		return
	var s := Sprite3D.new()
	s.texture = t
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y                                # 躺平贴地
	s.shaded = false; s.transparent = true
	s.pixel_size = (size_px * battle.WS) / float(maxi(1, t.get_height()))
	s.position = battle._world_pos(pos2d, 0.04 + 0.015 * float(idx % 3))   # 微抬错层防 z-fight
	var wdir: Vector3 = battle._world_pos(pos2d + dir, 0.0) - battle._world_pos(pos2d, 0.0)   # 对齐方向(照 _beam_vfx 口径)
	s.rotation.y = -atan2(wdir.z, wdir.x) + 0.18 * float((idx % 3) - 1)    # +索引微扰(冰面不规则)
	s.modulate = Color(0.85, 0.95, 1.0, 0.0)
	battle._world.add_child(s)
	var tw = battle._reg_tween()
	tw.tween_interval(delay)
	tw.tween_property(s, "modulate:a", 0.9, 0.12)
	tw.tween_interval(maxf(0.05, life - 0.62))
	tw.tween_property(s, "modulate:a", 0.0, 0.4)
	tw.tween_callback(s.queue_free)

## 冰脊一根: glacier-crystals billboard 立在地上·从地里升起(上移+等比放大+淡入)·持 life·收尾下沉淡出。
##   用【等比】scale(billboard 非等比 scale 有坑), 靠 position 上移做"冒出地面"。
func _glacier_spike(pos2d: Vector2, size_px: float, life: float, delay: float) -> void:
	var t: Texture2D = load("res://assets/sprites/vfx/glacier-crystals.png")
	if t == null:
		return
	var s := Sprite3D.new()
	s.texture = t
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.pixel_size = (size_px * battle.WS) / float(maxi(1, t.get_height()))
	var world_h: float = size_px * battle.WS * 0.5         # 中心抬半高→底边贴地
	s.position = battle._world_pos(pos2d, world_h * 0.6)   # 起点略低(半埋感)
	s.scale = Vector3.ONE * 0.5
	s.modulate = Color(0.92, 0.98, 1.0, 0.0)
	battle._world.add_child(s)
	var tw = battle._reg_tween()
	tw.tween_interval(delay)
	tw.tween_property(s, "position", battle._world_pos(pos2d, world_h), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.95, 0.15)
	tw.tween_interval(maxf(0.05, life - 0.65))
	tw.tween_property(s, "modulate:a", 0.0, 0.42)
	tw.parallel().tween_property(s, "position", battle._world_pos(pos2d, world_h * 0.7), 0.42)
	tw.parallel().tween_property(s, "scale", Vector3.ONE * 0.7, 0.42)
	tw.tween_callback(s.queue_free)

## 寒雾一团: 加性蓝白 glow 图元·淡入→上飘→淡出(氛围层·加性 glow 是通用图元非 themed 复用)。
func _glacier_mist(pos2d: Vector2, delay: float) -> void:
	var g = battle._glow_bb(pos2d, 0.3, 62.0, Color(0.72, 0.9, 1.0, 0.0))
	var mat := g.material_override as StandardMaterial3D
	var base: Vector3 = g.position
	var tw = battle._reg_tween()
	tw.tween_interval(delay)
	tw.tween_property(mat, "albedo_color", Color(0.72, 0.9, 1.0, 0.6), 0.3)
	tw.parallel().tween_property(g, "position", base + Vector3(0.0, 0.7, 0.0), 1.2)
	tw.tween_property(mat, "albedo_color", Color(0.72, 0.9, 1.0, 0.0), 0.5)
	tw.tween_callback(g.queue_free)

## ★纯效果结算(可测): 钩住 target → 眩晕(吃韧性) + 标记4秒【一段段拽】 + 4秒受伤放大。不建任何 tween。
func _hook_grab(trainer: Dictionary, target: Dictionary) -> void:
	battle._damage._stun(target, battle.HOOK_STUN, "hook")                          # 眩晕4秒(吃韧性)
	target["_hook_pull_until"] = battle._t + battle.HOOK_STUN               # 4秒内被拽
	target["_hook_pull_by"] = trainer                         # 朝这个大师拽
	target["_hook_tug_t0"] = battle._t + battle.HOOK_TUG_DELAY              # 第一下拽的时刻(0.1s后·锤石口径)
	target["hook_vuln_until"] = battle._t + battle.HOOK_STUN                # 4秒内受伤 ×1.25(见 _mitigate_incoming)
	target["_hooked_by"] = trainer                            # 触发证据(同步标记, 非tween)
	battle._buff_aura(target, Color(1.0, 0.35, 0.35, 0.45), battle.HOOK_STUN, 44.0)   # R3 易伤标记(受伤×1.25期间红环·守_world空)

## 每帧: 大师钩锁冷却扣减; 被钩单位【一段段】朝大师拽(每 battle.HOOK_PULL_INTERVAL 秒里, 前 battle.HOOK_TUG_DUR 秒快速位移一段, 其余停顿)。
## ★非匀速(用户2026-07-24: 锤石钩住是一下一下拽, 不是匀速)。在 _process 战斗门内调。
func _tick_hooks(delta: float) -> void:
	_tick_hook_flights(delta)      # ★真 skillshot: 钩头逐帧推进 + 每帧碰撞(见 _cast_hook 注释)
	var tug_spd: float = battle.HOOK_TUG_DIST / battle.HOOK_TUG_DUR         # 拽的那一下的速度(码/秒)
	for u in battle._units:
		if u.get("is_trainer", false) and float(u.get("_active_cd", 0.0)) > 0.0:
			u["_active_cd"] = maxf(0.0, float(u["_active_cd"]) - delta)
		if battle._t < float(u.get("_hook_pull_until", 0.0)):
			var by = u.get("_hook_pull_by", null)
			if by is Dictionary and by.get("alive", false):
				if battle._world != null:
					_hook_chain(by["pos"], u["pos"])   # R3 全程钩链(专属铁链·每帧重画=连续绷紧·连着大师↔被钩目标·补"拖拽4秒里链条断了")
				var ph: float = battle._t - float(u.get("_hook_tug_t0", battle._t))   # 相对第一下拽的相位
				if ph >= 0.0 and fmod(ph, battle.HOOK_PULL_INTERVAL) < battle.HOOK_TUG_DUR:   # 处在"拽"的窗口内
					var to: Vector2 = by["pos"] - u["pos"]
					if to.length() > 24.0:                    # 留 24 码不重叠
						u["pos"] += to.normalized() * tug_spd * delta
						u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
						u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)

## 敌方(右侧/快照)训龟大师 AI: 像真人一样来回乱走 + 逮到机会甩钩锁(场外援助·用户2026-07-23 点3)。
## 左侧大师由玩家操控(WASD 走 + Q 甩); 但 STRESS 无头对练时左侧也交给 AI ——
## 否则钩锁在无头冒烟流程里从不触发, 等于没测到(照 CLAUDE.md「靠触发的东西冒烟必须真触发」)。
func _tick_trainer_ai(delta: float) -> void:
	if not _trainer_ticks_active():
		return
	for u in battle._units:
		if not u.get("is_trainer", false) or not u.get("alive", false):
			continue
		if str(u.get("side", "")) == "left" and not battle._stress and not _ai_left_trainer:
			continue   # 左侧=玩家操控, AI 不接管(无头压测/AI_TRAINER_LEFT 仿真除外)
		_trainer_ai_step(u, delta)

func _trainer_ai_step(u: Dictionary, delta: float) -> void:
	var is_left = str(u.get("side", "")) == "left"
	# ① 乱走: 每隔一小段换一个随机游走点(限在自己半场后方, 不越中线冲进战场), 朝它半速晃
	u["_ai_wander_cd"] = float(u.get("_ai_wander_cd", 0.0)) - delta
	if float(u["_ai_wander_cd"]) <= 0.0 or not u.has("_ai_wander_to"):
		u["_ai_wander_cd"] = battle._battle_rng.randf_range(0.8, 1.8)
		var xmin: float = battle.ARENA.position.x if is_left else battle._arena_center.x + 60.0
		var xmax: float = battle._arena_center.x - 60.0 if is_left else battle.ARENA.end.x
		u["_ai_wander_to"] = Vector2(randf_range(xmin, xmax), randf_range(battle.ARENA.position.y + 50.0, battle.ARENA.end.y - 50.0))
	var to: Vector2 = u["_ai_wander_to"] - u["pos"]
	if to.length() > 12.0:
		_trainer_move_by(u, to.normalized() * 0.6, delta)   # 半速晃(悠着点=真人感)
	# ② 逮机会放主动: CD 好了 → 朝最近敌人方向放(钩锁在射程/线上则命中, 否则空放; 其余技能各自处理)
	if float(u.get("_active_cd", 0.0)) <= 0.0:
		var tgt = battle._targeting._nearest_enemy_for_trainer(u)
		if tgt != null:
			_cast_active(u, tgt["pos"] - u["pos"])

## 玩家按 Q: 我方(左侧)大师朝【鼠标方向】甩钩锁(PC·学 LoL 锤石 Q·用户2026-07-23 点3)。
func _player_cast_hook() -> void:
	if not _trainer_ticks_active():
		return
	var tr = battle._my_trainer()
	if tr == null:
		return
	var u: Dictionary = tr
	var mp: Vector2 = battle.get_viewport().get_mouse_position() if battle.get_viewport() != null else Vector2.ZERO
	var aim: Vector2 = battle._screen_to_field(mp) - u["pos"]
	_cast_active(u, aim)

## 移动端点圆盘: 我方大师朝【最近敌人】放主动(触屏没有鼠标方向, 自动瞄准; 拖动瞄准在 spell_disc 内处理)。
func _player_cast_hook_auto() -> void:
	if not _trainer_ticks_active():
		return
	var tr = battle._my_trainer()
	if tr == null:
		return
	var u: Dictionary = tr
	var tgt = battle._targeting._nearest_enemy_for_trainer(u)
	var aim: Vector2 = (tgt["pos"] - u["pos"]) if tgt != null else (Vector2.LEFT if str(u.get("side","")) == "right" else Vector2.RIGHT)
	_cast_active(u, aim)

## (已删 _hook_dramatize —— 钩锁 2026-07-30 改真 skillshot 后它就是死代码:
##  飞行/命中演出全在 _cast_hook + _tick_hook_flights 里(钩头节点逐帧更新位置, 不用 tween)。
##  ★它留着害过人: VFXPREVIEW 还指着它, 于是我"目视确认新实现"看的其实是旧实现 = 无效验证。
##  而 verify_trainer_audit 有一条"_hook_dramatize 存在"的断言, 于是全套门禁照样绿 ——
##  【断言函数存在, 守不住"这个函数还有没有人调"】。同批删掉的还有 _hook_dramatize_miss:
##  空放现在由 _tick_hook_flights 飞满射程时收尾。)
## R3 钩子命中特效(LoL 式·用户2026-07-26"像lol一样爆一个闪光"): 爆闪光(亮白青·瞬间炸大→快消) + 醒目冲击环 + 轻震屏。
func _hook_hit_fx(pos2d: Vector2) -> void:
	if battle._world == null:
		return
	battle._splash_ring_bold(pos2d, Color(0.6, 0.92, 1.0, 0.95), 60.0)          # ① 冲击波环(shockwave)
	battle._shake(battle.JUICE_SHAKE_BIG)                                       # 重震屏(钩中=大事件)
	# ② 青光晕(大·扩散慢一点): 外层能量
	var halo = battle._glow_bb(pos2d, 0.8, 150.0, Color(0.5, 0.86, 1.0, 0.9))
	var ht = battle._reg_tween(); ht.set_parallel(true)
	ht.tween_property(halo, "scale", Vector3.ONE * 1.9, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ht.tween_property(halo.material_override, "albedo_color", Color(0.5, 0.86, 1.0, 0.0), 0.24)
	ht.chain().tween_callback(halo.queue_free)
	# ③ ★白热核(小·极亮·瞬炸快消): LoL 命中那一下的爆闪
	var core = battle._glow_bb(pos2d, 0.85, 78.0, Color(1.0, 1.0, 1.0, 1.0))
	var ct = battle._reg_tween(); ct.set_parallel(true)
	ct.tween_property(core, "scale", Vector3.ONE * 3.4, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ct.tween_property(core.material_override, "albedo_color", Color(0.8, 0.95, 1.0, 0.0), 0.14)
	ct.chain().tween_callback(core.queue_free)

## R3 钩链(专属铁链·替海盗电光 chain-bolt·连续调=连续绷紧): 横向铁链贴图从 A 拉到 B。
func _hook_chain(from2d: Vector2, to2d: Vector2) -> void:
	battle._beam_vfx("res://assets/sprites/vfx/hook-chain.png", from2d, to2d, 20.0, Color(0.92, 0.94, 0.98, 1.0), 0.13)

## 训龟大师【自己】的索敌: 射程内最近的敌人。不复用 _nearest_enemy ——
## 那个会跳过 is_trainer(别人锁不到它), 但没有射程限制、也不该被别的规则牵连。
func _trainer_throw_anim(u: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	if not u.has("_throw_sd"):
		u["_throw_sd"] = battle._resolve_action("pets/animations/trainer/throw.png", 10.0)
	var tsd: Dictionary = u["_throw_sd"]
	if tsd.is_empty():
		return
	battle._set_anim_sheet(u, tsd, "throw", false)   # anim_action=throw → 播一次到末帧回 idle


## 抛物线石头: 从训龟大师胸口飞向目标, 到点命中扣 1 物理(经 _mitigate 后仍是 1)。
func _trainer_magicstone_onhit(u: Dictionary, tgt: Dictionary) -> void:
	if not (tgt is Dictionary and tgt.get("alive", false)):
		return
	# (2 + 0.1×大轮等级)% 目标最大生命(用户 2026-07-28) → Lv1=2.1% … Lv10=3.0%
	var lv: int = clampi(int(GameState.season_level), 1, 10)
	var pct: float = battle.MS_MAXHP_BASE + battle.MS_MAXHP_PER_LV * float(lv)
	var magic: int = maxi(1, int(battle._resolve_dmg(u, float(tgt["maxHp"]) * pct, tgt, true)))
	battle._damage._apply_damage_from(u, tgt, magic, Color("#c86bff"), 0.0, false, true)
	u["_ms_stacks"] = int(u.get("_ms_stacks", 0)) + 1                                        # 攻速叠一层(持续到本场结束)


## 移动端才建摇杆; PC 上根本不建(不占屏)。
## ★TRAINER_JOY=1 可在 PC 上强开, 用于自验手感与门禁 —— 否则这段代码在开发机上永远跑不到,
##   等于没写(EQDEMO 那次的教训: 触发不到的路径看着像"没生效")。
# 形象 id → 战场立绘(与 TrainerConfigScene.APPEARANCES 对齐; 改一处两处都要动)。
# R6-A(2026-07-26): 玩家在配置页选的形象【真的进战场】—— 之前 _trainer_sprite_dict 死读 pets/trainer.png, 配置选了也白选。
const _APPEARANCE_SPRITES := {
	"villager": "res://assets/sprites/trainer/trainer-villager.png",
	"mage": "res://assets/sprites/trainer/trainer-mage.png",
	"girl": "res://assets/sprites/trainer/trainer-girl.png",
}

func _trainer_sprite_dict(appearance_id: String = "default") -> Dictionary:
	# R6-B: 有4方向动画帧表 → 用 idle 表(4行 S/E/N/W·48px格)当基准立绘, 战场由 battle_render._update_trainer_anim 逐帧切方向/动作。
	var anim_idle: String = "res://assets/sprites/trainer/anim/trainer-" + appearance_id + "-idle.png"
	if _APPEARANCE_SPRITES.has(appearance_id) and ResourceLoader.exists(anim_idle):
		return {"tex": load(anim_idle), "frames": 1, "fps": 1.0, "frame_h": 48, "hframes": 1, "vframes": 4, "loop": false}
	# 兜底: 单帧朝南立绘(敌方/未量产动画的形象)
	var tex: Texture2D = null
	var path: String = str(_APPEARANCE_SPRITES.get(appearance_id, ""))   # 选到三形象之一 → 用它; 否则(含"default"/敌方)回退通用立绘
	if path != "" and ResourceLoader.exists(path):
		tex = load(path)
	if tex == null and ResourceLoader.exists(battle.TRAINER_SPRITE):
		tex = load(battle.TRAINER_SPRITE)
	if tex == null:
		battle.push_warning("[训龟大师] 立绘未就绪 —— 用程序占位图。")
		tex = battle._make_trainer_placeholder_tex()
	var th: int = tex.get_height() if tex != null else 64
	return {"tex": tex, "frames": 1, "fps": 1.0, "frame_h": th, "hframes": 1, "vframes": 1, "loop": false}


## 造一张【一眼就知道美术还没做】的占位纹理: 洋红/黑棋盘拼的人形。
##
## ★为什么不拿现成立绘兜底: 项目里 pets/*.png 【全是精灵表】(bamboo.png 是 4000×800 装 9 帧),
##   当单帧用会把整张表糊成一坨。
## ★为什么必须程序生成: 我原来的兜底路径写的是 pets/basic.png —— 那个文件【根本不存在】
##   (basic 的真立绘是 pets/animations/basic/idle.png), 于是 tex=null, 训龟大师在场上
##   【完全看不见】, 我还对着窗口跟用户说"长得就是小龟的样子"。
##   而当时的门禁只断言了"会 battle.push_warning", 没断言"占位图真的能显示" ——
##   守住了会吭声, 没守住看得见。程序生成没有路径依赖, 不可能再出这种事。

# ══════════════════════════════════════════════════════════════
# §HUNT 猎龟令 (用户 2026-07-28)
#
# CD30 / 射程600 / 指定敌方目标(aim:"target" 锁头弹道, 不是直线发射)。
# 命中后目标 15 秒内:
#   · 受到伤害 +15%          → 走【唯一入口】_mitigate_incoming 的 hunt_until 分支
#   · 以目标为圆心 400 码内的【我方友军优先攻击它】→ 每帧刷新圈内友军的嘲讽
# 圈跟着目标走(用户: "跟着目标走的, 压的很小没问题的")。
#
# ★为什么嘲讽要【每帧刷】而不是施法时刷一次:
#   现成的 taunt_until/taunt_by 语义是"某个单位被嘲讽 N 秒", 是【打在友军身上】的。
#   而猎龟令要的是"以目标为圆心的一个区域, 谁进圈谁就被嘲讽" —— 圈会动、人也会动,
#   施法时刷一次的话, 之后跑进圈的友军不会被嘲讽、跑出圈的却还锁着。
# ══════════════════════════════════════════════════════════════

## 在 600 码内、离瞄准点最近的敌人。aim 是【相对大师的偏移】(与其他主动技口径一致)。
## 返回 null = 没锁到人(空放)。
func _hunt_pick_target(trainer: Dictionary, aim: Vector2):
	var want: Vector2 = trainer["pos"] + aim.limit_length(battle.HUNT_RANGE)
	var best = null
	var bd: float = INF
	for o in battle._targeting._pick_enemies_of(trainer):
		if (o["pos"] - trainer["pos"]).length() > battle.HUNT_RANGE:
			continue                      # 超出射程的不能锁
		var dd: float = (o["pos"] - want).length_squared()
		if dd < bd:
			bd = dd; best = o
	return best


## 标记生效(纯效果·不依赖演出 —— 照 CLAUDE.md §3.5: 测数值的用例不该等 tween)。
func _hunt_mark(trainer: Dictionary, tgt: Dictionary) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	tgt["hunt_until"] = battle._t + battle.HUNT_SEC
	tgt["hunt_by"] = trainer                          # 谁下的令(嘲讽指向用)
	tgt["_hunt_marked"] = true                        # ★同步的触发证据(供门禁断言, 不看"有没有建 tween")


## 施放猎龟令。返回是否锁到目标。
func _cast_hunt_order(trainer: Dictionary, aim: Vector2) -> bool:
	if trainer == null or not trainer.get("alive", false):
		return false
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	var tgt = _hunt_pick_target(trainer, aim)
	if tgt == null:
		trainer["_active_cd"] = battle.HUNT_CD * 0.5   # 空放返还一半(与钩锁同思路)
		return false
	trainer["_active_cd"] = battle.HUNT_CD
	var dist: float = (tgt["pos"] - trainer["pos"]).length()
	var arrive: float = dist / battle.HUNT_MISSILE_SPD
	var tt: Dictionary = trainer
	var kk: Dictionary = tgt
	# 到达才生效(走 _pending_shots 的 delta 制, 无头也稳 —— 不是等 tween)
	battle._pending_shots.append({"delay": arrive, "src": trainer, "fn": func() -> void:
		if kk.get("alive", false):
			_hunt_mark(tt, kk)})
	_hunt_dramatize(trainer, tgt, arrive)
	return true


## 每帧: 刷新【所有被猎龟令标记者】周围 400 码内我方友军的嘲讽。
## ★在 battle 的 sim tick 里调。标记过期自动停(不用额外清理)。
func _tick_hunt_taunt(_delta: float) -> void:
	for m in battle._units:
		if not m.get("alive", false):
			continue
		if battle._t >= float(m.get("hunt_until", 0.0)):
			continue
		var by = m.get("hunt_by", null)
		if not (by is Dictionary):
			continue
		for o in battle._units:
			if not o.get("alive", false) or o.get("is_trainer", false):
				continue
			if not battle._is_ally(o, by):        # 只嘲讽【下令方】的友军
				continue
			if not battle._is_hostile(o, m):      # 已经归顺我方的不该被嘲讽去打自己人
				continue
			if o["pos"].distance_to(m["pos"]) > battle.HUNT_TAUNT_R:
				continue
			# 只刷到"下一帧" —— 出圈立刻失效, 不留尾巴
			o["taunt_until"] = battle._t + 0.2
			o["taunt_by"] = m


## 猎龟令演出。★用户 2026-07-28「不不不，不要复用素材」→ 这里用的是本技能【新生成】的
## hunt-mark.png(猩红破碎环 + 橙金刻度 + 虚线警戒圈), 不借任何现成 vfx 贴图。
##
## 三段: ① 大师身前射出一枚猩红锁头弹 → ② 到达时目标脚下炸开猎龟令印记 →
##       ③ 印记常驻 15 秒并【跟着目标走】(圈是随目标移动的, 用户已确认)。
## ★演出全在这里, 数值一点不在这里 —— _hunt_mark 才是效果, 门禁直接调它, 不等 tween。
func _hunt_dramatize(trainer: Dictionary, tgt: Dictionary, arrive: float) -> void:
	if battle._world == null:
		return
	# ① 锁头弹: 直接用 _pending_shots 的到达时间做 tween 时长, 两者同一个数 → 视觉与结算对齐
	var bolt := Sprite3D.new()
	bolt.texture = VfxTex._make_bolt_texture(Color("#ff3b30"))
	bolt.pixel_size = 0.03
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.shaded = false; bolt.transparent = true
	bolt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bolt.position = battle._world_pos(trainer["pos"], 1.1)
	battle._world.add_child(bolt)
	var kk: Dictionary = tgt
	var tw = bolt.create_tween()
	tw.tween_method(func(f: float) -> void:
		if is_instance_valid(bolt):
			# ★每帧重新读目标位置 = 真"锁头": 目标跑开也追得到(用户: 像安妮的 Q)
			bolt.position = bolt.position.lerp(battle._world_pos(kk["pos"], 1.0), minf(1.0, f)),
		0.35, 1.0, maxf(0.05, arrive))
	tw.tween_callback(func() -> void:
		if is_instance_valid(bolt):
			bolt.queue_free())
	# ② + ③ 印记: 到达后出现, 跟随目标, 到期自己消失
	battle._pending_shots.append({"delay": arrive, "src": trainer, "fn": func() -> void:
		if kk.get("alive", false):
			_hunt_sigil(kk)})


## 猎龟令印记(跟随目标·15秒)。用新素材 hunt-mark.png; 缺图则不画(不静默换别的贴图 —— 
## 悄悄兜底会让人以为美术已经做完了, 训龟大师立绘那次就是这么发现的)。
func _hunt_sigil(tgt: Dictionary) -> void:
	var path := "res://assets/sprites/vfx/hunt-mark.png"
	if battle._world == null or not ResourceLoader.exists(path):
		if not ResourceLoader.exists(path):
			push_warning("[猎龟令] 缺素材 %s —— 印记不画(不复用别的贴图兜底)" % path)
		return
	var s := Sprite3D.new()
	s.texture = load(path)
	# ★按【印记该有多大】定尺寸, 不是按嘲讽半径(见 SIGIL_D_M 头注: 原来 19.20 m 比战场纵深还长)
	s.pixel_size = SIGIL_D_M / float(maxi(1, s.texture.get_height()))
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y                                          # Sprite3D.axis 是枚举(Vector3.Axis)不是向量 —— 写 Vector3.UP 会解析失败
	s.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = Color(1.0, 1.0, 1.0, 0.85)
	# ★★入树前【先摆到位】—— 不设初始 position 的话节点生在世界原点 (0,0,0),
	#   要等下面那个 .set_delay(0.03) 的循环 tween 第一次回调才归位。
	#   探针实测: 头 2 帧待在原点, 与目标脚下偏差 16.21 m → 【地图正中先闪一下红环】再跳到目标身上。
	#   (驯服的 _tame_rune 同一个毛病, 同批修。)
	s.position = battle._world_pos(tgt["pos"], 0.06)
	battle._world.add_child(s)
	tgt["_hunt_sigil"] = s
	var kk: Dictionary = tgt
	# 跟随: 每帧把印记挪到目标脚下; 标记到期(或目标死)自毁
	var tw = s.create_tween().set_loops()
	tw.tween_callback(func() -> void:
		if not is_instance_valid(s):
			return
		if not kk.get("alive", false) or battle._t >= float(kk.get("hunt_until", 0.0)):
			s.queue_free()
			return
		s.position = battle._world_pos(kk["pos"], 0.06)).set_delay(0.03)


# ══════════════════════════════════════════════════════════════
# §TAME 驯服 (用户 2026-07-28)
#
# CD60 / 射程600 / 指定敌方目标(同 aim:"target" 锁头弹道)。
# 被驯服的敌人【死亡时不真死】:
#   · 以 30% 最大生命重生, 2.5 秒演出期间无敌且不可选中
#   · 重生后【归顺我方】(用户:「顺归算我方」) —— 走 tamed_side, 绝不改写 side
#   · 归顺后每秒损失 2% 最大生命(永久, 没有解除手段)
#   · 活到本路结束可跨入终极战场, 掉血 buff 继续
#
# ★与赛博侵入(hijacked)是两种语义, 别混:
#   hijacked = 孤军(对所有人都是敌人); tamed = 真换队(我方给它治疗/护盾都算数)。
# ══════════════════════════════════════════════════════════════

## 施放驯服。返回是否锁到目标。
func _cast_tame(trainer: Dictionary, aim: Vector2) -> bool:
	if trainer == null or not trainer.get("alive", false):
		return false
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	var want: Vector2 = trainer["pos"] + aim.limit_length(battle.TAME_RANGE)
	var tgt = null
	var bd: float = INF
	for o in battle._targeting._pick_enemies_of(trainer):
		if (o["pos"] - trainer["pos"]).length() > battle.TAME_RANGE:
			continue
		if str(o.get("tamed_side", "")) != "" or o.get("tame_pending", false):
			continue                       # 已经被驯服/已标记的不重复标
		var dd: float = (o["pos"] - want).length_squared()
		if dd < bd:
			bd = dd; tgt = o
	if tgt == null:
		trainer["_active_cd"] = battle.TAME_CD * 0.5   # 空放返还一半
		return false
	trainer["_active_cd"] = battle.TAME_CD
	var dist: float = (tgt["pos"] - trainer["pos"]).length()
	var arrive: float = dist / battle.TAME_MISSILE_SPD
	var tt: Dictionary = trainer
	var kk: Dictionary = tgt
	battle._pending_shots.append({"delay": arrive, "src": trainer, "fn": func() -> void:
		if kk.get("alive", false):
			_tame_mark(tt, kk)})
	_tame_dramatize(trainer, tgt, arrive)
	return true


## 打上驯服标记(纯效果·可直接被门禁调, 不依赖演出)。
## ★B3: 标记【没有 until】—— 持续到战斗结束或死亡, 不是定时 buff。
func _tame_mark(trainer: Dictionary, tgt: Dictionary) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	tgt["tame_pending"] = true
	tgt["tame_by_side"] = str(trainer.get("side", "left"))
	tgt["_tamed_marked"] = true                       # 同步的触发证据(供门禁断言)


## 死亡时被 _kill 调。返回 true = 已接管(不真死)。
func _tame_try_revive(u: Dictionary) -> bool:
	if not u.get("tame_pending", false) or u.get("tame_used", false):
		return false
	u["tame_used"] = true
	u["tame_pending"] = false
	u["hp"] = float(u["maxHp"]) * battle.TAME_REVIVE_PCT      # B4: 30% 最大生命
	u["dots"] = []
	u["dot_stacks"] = {}
	u["shield"] = 0.0
	u["tamed_side"] = str(u.get("tame_by_side", "left"))      # B5: 归顺(不改写 side)
	u["untargetable_until"] = battle._t + battle.TAME_REVIVE_SEC   # B7: 演出期不可选中
	u["_tame_invuln_until"] = battle._t + battle.TAME_REVIVE_SEC   # B7: 演出期无敌
	u["taunt_until"] = 0.0                                     # 换队了, 旧嘲讽作废
	u["taunt_by"] = null
	u["hunt_until"] = 0.0                                      # 自家人不该还挂着猎龟令
	battle._vfx._float_text(u["pos"] + Vector2(0, -64), "归顺!", Color("#7de8c8"))
	_tame_revive_dramatize(u)
	return true


## 每帧: 归顺者每秒损失 2% 最大生命(B8·永久)。演出期不掉。
## ★走 _apply_damage(...is_self=true): 自损不吃增伤类修正, 否则被靶向器标记之类会把
##   2%/秒放大 —— 与"固定每秒 2%"的设定不符(暴露蛋那次就是这么踩的)。
func _tick_tame_decay(delta: float) -> void:
	for u in battle._units:
		if not u.get("alive", false):
			continue
		if str(u.get("tamed_side", "")) == "":
			continue
		if battle._t < float(u.get("_tame_invuln_until", 0.0)):
			continue                                   # 重生演出期间不掉血
		var d: float = float(u["maxHp"]) * battle.TAME_DECAY_PCT * delta
		# ★参数位置: _apply_damage(u, dmg, col, src, bucket, is_self, ...) ——
		#   第 4 个是 src 不是 is_self。写成 (u, d, col, true) 会把 true 当 src 传进去。
		battle._damage._apply_damage(u, int(ceilf(d)), Color("#8b2e4a"), null, "dot", true)


## 驯服演出: 青碧锁扣弹飞向目标 → 命中后目标脚下亮起符文环(常驻到它死/归顺)。
## ★素材是本技能【新生成】的 tame-rune.png(青碧双环 + 白金符文 + 锁链), 不复用现成贴图。
func _tame_dramatize(trainer: Dictionary, tgt: Dictionary, arrive: float) -> void:
	if battle._world == null:
		return
	var bolt := Sprite3D.new()
	bolt.texture = VfxTex._make_bolt_texture(Color("#4fe0c0"))
	bolt.pixel_size = 0.028
	bolt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bolt.shaded = false; bolt.transparent = true
	bolt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bolt.position = battle._world_pos(trainer["pos"], 1.1)
	battle._world.add_child(bolt)
	var kk: Dictionary = tgt
	var tw = bolt.create_tween()
	tw.tween_method(func(f: float) -> void:
		if is_instance_valid(bolt):
			bolt.position = bolt.position.lerp(battle._world_pos(kk["pos"], 1.0), minf(1.0, f)),
		0.35, 1.0, maxf(0.05, arrive))
	tw.tween_callback(func() -> void:
		if is_instance_valid(bolt):
			bolt.queue_free())
	battle._pending_shots.append({"delay": arrive, "src": trainer, "fn": func() -> void:
		if kk.get("alive", false):
			_tame_rune(kk)})


## 驯服符文环(跟随目标)。缺图则不画并 push_warning —— 不静默换别的贴图兜底。
func _tame_rune(tgt: Dictionary) -> void:
	var path := "res://assets/sprites/vfx/tame-rune.png"
	if battle._world == null or not ResourceLoader.exists(path):
		if not ResourceLoader.exists(path):
			push_warning("[驯服] 缺素材 %s —— 符文环不画(不复用别的贴图兜底)" % path)
		return
	var s := Sprite3D.new()
	s.texture = load(path)
	s.pixel_size = TAME_RUNE_D_M / float(maxi(1, s.texture.get_height()))
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = Color(1.0, 1.0, 1.0, 0.8)
	s.position = battle._world_pos(tgt["pos"], 0.05)   # ★同 _hunt_sigil: 先摆到位, 否则头 2 帧在世界原点闪
	battle._world.add_child(s)
	var kk: Dictionary = tgt
	var tw = s.create_tween().set_loops()
	tw.tween_callback(func() -> void:
		if not is_instance_valid(s):
			return
		if not kk.get("alive", false):
			s.queue_free()
			return
		s.position = battle._world_pos(kk["pos"], 0.05)
		s.rotate_y(0.06)).set_delay(0.03)


## 归顺重生演出(B6): 符文环转青 + 冒字。
##
## ★这里【一个数值都不改】—— 血量在 _tame_try_revive 里已经定死为 30% 最大生命。
##   第一版我写成"hp 先设 0.01, 再用 tween 涨到 30%" 做逐渐回血的观感, 那正是
##   CLAUDE.md §3.5 明写的坑: 无头 CI 下场景树 tween 推进不稳, tween 跑不完
##   → 血永远停在 0.01 → 单位一碰就死, 而本地永远复现不出来。
##   "逐渐回血"的观感交给血条自己的插值, 不拿真实 hp 当动画变量。
## ★血条颜色按 _eff_side 取而不是 side —— 上面已让 _eff_side 认 tamed_side, 归顺后自动显示我方色。
func _tame_revive_dramatize(u: Dictionary) -> void:
	if battle._world == null:
		return
	_tame_rune(u)
	battle._vfx._float_text(u["pos"] + Vector2(0, -40), "+%d" % int(float(u["maxHp"]) * battle.TAME_REVIVE_PCT), Color("#7de8c8"))
