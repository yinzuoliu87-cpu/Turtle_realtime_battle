class_name HidingSystem
extends RefCounted
## 缩头龟(含随从小将)技能系统
## 类内名不变;外部名加 battle.

## ★★2026-08-22 文案根除: 下面这些原来是函数体里的裸字面量。
## 【防御】护盾 + 护甲, 两者时长不同; 护盾到期把剩余部分按比例转生命。
## 【喊龟(被动)】开局随机召唤一只 A/B/C 稀有度的龟当随从, 属性按原龟打折。
## 【缩壳(普攻)】每击永久涨双抗 + 一小块盾, 真值在主场景普攻表与 rider。
const BASIC_COEF := 1.0          # ×ATK 物理
const HARDEN_RESIST := 1.0       # 每击 +护甲/+魔抗(永久累积)
const HARDEN_SHIELD := 0.1       # 每击护盾 = ×ATK
## 【缩头】给随从灌龟能 + 自身缩壳一段时间(高减伤但不能动)。
const SHRINK_MINION_ENERGY := 0.5  # 给随从灌 = 该技龟能消耗 ×
const SHRINK_SEC := 3.0            # 缩壳持续(秒)·期间定身且锁龟能
const SHRINK_DR := 0.80            # 缩壳期间的伤害减免
const MINION_HP_SCALE := 0.40    # 随从最大生命 = 原龟 ×
const MINION_ATK_SCALE := 0.80   # 随从攻击力 = 原龟 ×
const DEFEND_SHIELD_PCT := 0.20   # 护盾 = 自身最大生命 ×
const DEFEND_SHIELD_SEC := 4.0    # 护盾持续(秒)·持盾期锁龟能
const DEFEND_DEF_UP := 0.20       # 护甲提升
const DEFEND_DEF_SEC := 5.0       # 护甲加成持续(秒)
const DEFEND_CONVERT := 0.20      # 到期时把【剩余护盾】× 此值转成生命
## 【强化随从】给随从的一组增益(随从先死则本体永久继承, 可叠)。
const EMPOWER_SEC := 5.0          # 持续(秒)
const EMPOWER_STAT := 0.10        # 攻击力 / 护甲 / 魔抗 / 生命偷取 各 +
const EMPOWER_CRIT := 0.20        # 暴击率 +

var battle

func _init(b) -> void:
	battle = b

# 小将立绘字典 (静态单帧: minion.png 前排 / minion-back.png 后排 / minion-elite.png 精英)
func _minion_sprite_dict(is_elite: bool, is_back: bool) -> Dictionary:
	var img: String = "pets/minion-elite.png" if is_elite else ("pets/minion-back.png" if is_back else "pets/minion.png")
	var path: String = battle.SPRITE_DIR + img
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var th: int = tex.get_height() if tex != null else 64
	return {"tex": tex, "frames": 1, "fps": 1.0, "frame_h": th, "hframes": 1, "vframes": 1, "loop": false}

# 龟蛋立绘字典 (pets/egg.png = 单蛋 3帧 idle 动画横排 79×80, 修: 原当 frames:1 显成"3蛋并排")
# ============================================================================
#  🎮 训龟大师操控 (用户 2026-07-22:「还是分pc和移动2版吧, 移动要遥感」)
# ============================================================================
# PC   = 键盘 WASD / 方向键 —— 鼠标三种手势已排满(拖=平移 / 点=选中 / 滚轮=缩放),
#        键盘是唯一还空着的通道; 且与摇杆同属"连续直接控制", 两端手感一致。
#        战斗场只占用了 R(重开) 与 ESC(关面板/退场), WASD 与方向键全空。
# 移动端 = 左下角虚拟摇杆(VirtualJoystick, mouse_filter=STOP 吃掉本区域事件, 不抢镜头平移)。
#
# ★只操控【我方(left)】那一个; 对面那个是人机, 玩家的输入碰不到它。
# ★移动本身随暂停一起停 —— 这是玩法动作, 不是观察操作(与"暂停仍可拖镜头/光标仍跟手"不同)。
#   主场景是 PAUSABLE, _process 停跑即天然满足, 不用额外判断。


## 本帧的移动输入。移动端读摇杆, PC 读键盘; 返回长度 0..1 的方向量。
# ═════ 小将主动技(用户2026-07-18): 近战人体浪板 / 远程追踪火箭筒 (各120龟能·射程2000) ═════
func _sk_minion_rocket(u: Dictionary, tgt) -> void:   # 远程小将·追踪火箭筒: 蓄力1.5s(枪口聚能)→枪口喷火发射→定向慢速追踪导弹(尾焰)→命中核爆(400码4A物理+4s50%治疗削减)
	if tgt == null or not tgt.get("alive", false): return
	var uu = u
	var tref: Dictionary = tgt
	uu["_slam"] = true                                  # 蓄力期定身(举火箭筒瞄准)
	## ★2026-08-21 补上动画调用: 这个技能此前**一次动画调用都没有**, 只有 VFX ——
	##   远程小将从头到尾没有任何动作图, 蓄力 1.5 秒里它是站着不动的。
	##   动画时长(6 帧 ÷ 4fps = 1.5 秒)与这里的蓄力节拍**焊死相等**,
	##   由 verify_elite_anim 的 RANGED_BEATS 守着 —— 不等的话动画先播完、角色站着发呆。
	battle._melee_anim(uu, "skill")
	var aim: Vector2 = (tref["pos"] as Vector2) - (uu["pos"] as Vector2)
	aim = aim.normalized() if aim.length() > 1.0 else (Vector2.RIGHT if uu.get("face_right", true) else Vector2.LEFT)
	uu["face_right"] = aim.x >= 0.0
	battle._rocket_sys._rocket_charge_vfx(uu, aim)                         # 蓄力表现(用户2026-07-18): 枪口聚能球渐大转白热+火星汇入+脚下能量环脉冲
	battle._pending_shots.append({"delay": 1.5, "fn": func() -> void:   # 蓄力1.5s→发射
		uu["_slam"] = false
		if not uu.get("alive", false): return
		var aim2: Vector2 = (tref["pos"] as Vector2) - (uu["pos"] as Vector2)
		aim2 = aim2.normalized() if aim2.length() > 1.0 else aim
		uu["face_right"] = aim2.x >= 0.0
		var muzzle: Vector2 = (uu["pos"] as Vector2) + aim2 * 34.0
		battle._rocket_sys._rocket_muzzle_flash(uu, muzzle, aim2)          # 枪口特效动画(用户2026-07-18): 白热闪+锥形喷火+火星前喷+后坐
		_minion_rocket_fly(uu, tref, muzzle)
	, "src": u})

func _minion_rocket_fly(u: Dictionary, tref: Dictionary, from: Vector2) -> void:   # 定向慢速追踪导弹(真导弹立绘·机头领飞+尾焰·−30%速)→命中/超时核爆
	var mtex: Texture2D = load("res://assets/sprites/vfx/rocket-missile.png")   # 真导弹立绘(机头朝+X·用户2026-07-18"不是直的导弹"→换真弹身)
	var miss = Sprite3D.new()
	miss.texture = mtex if mtex != null else VfxTex._make_fire_glow_tex()
	miss.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # ★不billboard→机头朝行进方向(用户2026-07-18"弹道没有方向")·由_orient_billboard_dir逐帧转
	miss.shaded = false; miss.transparent = true
	miss.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	miss.pixel_size = (74.0 * battle.WS) / float(maxi(1, (miss.texture as Texture2D).get_width()))   # 按弹长~74码(横向立绘按宽定)
	miss.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var pos: Vector2 = from
	var mh: float = 0.95
	miss.position = battle._world_pos(pos, mh)
	battle._world.add_child(miss)
	var halo: MeshInstance3D = battle._glow_bb(pos, mh, 42.0, Color(1.0, 0.58, 0.26, 0.7))   # 弹头发光晕(加性·跟随脉动)
	var flew: float = 0.0
	var lastdir: Vector2 = (tref["pos"] as Vector2) - pos
	lastdir = lastdir.normalized() if lastdir.length() > 1.0 else Vector2.RIGHT
	var trailc: float = 0.0
	var puls: float = 0.0
	while is_instance_valid(battle) and flew < 2400.0 and is_instance_valid(miss) and battle.is_inside_tree():
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if battle._over: break
		if battle._hitstop > 0.0 or (not battle._timestop._ts_active.is_empty() and not battle._arr_has_unit(battle._timestop._ts_active, u)): continue   # 时停: 只冻非active单位; 携带沙漏的自己要照常落地(否则_slam永不解锁=卡空中·用户2026-07-19)   # 顿帧/时停期悬停
		var dt: float = battle.get_process_delta_time()
		var target_pos: Vector2 = (tref["pos"] as Vector2) if tref.get("alive", false) else pos
		var to: Vector2 = target_pos - pos
		var dir: Vector2 = to.normalized() if to.length() > 1.0 else lastdir
		lastdir = dir
		var step: float = 266.0 * dt                    # 慢速追踪(−30%·用户2026-07-18: 380→266码/s)
		flew += step
		if to.length() <= step + 26.0:
			pos = target_pos; break                     # 命中
		pos += dir * step
		miss.position = battle._world_pos(pos, mh)
		var travel_world: Vector3 = battle._world_pos(pos + dir, mh) - battle._world_pos(pos, mh)
		battle._orient_billboard_dir(miss, travel_world)       # 尖头领着飞(朝屏幕行进方向)
		puls += dt                                       # 引擎燃烧脉动(弹身微暖闪·保留金属本色+光晕呼吸)
		var glow: float = 0.5 + 0.5 * sin(puls * 32.0)
		miss.modulate = Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.9, 0.78), glow)
		if is_instance_valid(halo):
			halo.position = battle._world_pos(pos, mh)
			halo.scale = Vector3.ONE * (0.9 + 0.18 * sin(puls * 32.0))
		trailc += dt
		if trailc >= 0.022:                             # 尾焰(推进尾迹)
			trailc = 0.0
			battle._rocket_sys._rocket_exhaust_puff(pos - dir * 14.0, mh, dir)
	if is_instance_valid(miss): miss.queue_free()
	if is_instance_valid(halo): halo.queue_free()
	var boom: Vector2 = (tref["pos"] as Vector2) if tref.get("alive", false) else pos
	_minion_rocket_nuke(u, boom)

func _minion_rocket_nuke(u: Dictionary, center: Vector2) -> void:   # 核爆(用户2026-07-18"命中不够惊艳·再设计"): 全屏白闪+重震顿帧+白热核+膨胀火球+3冲击环+放射火焰+火花碎石+烟柱焦痕; 400码4A物理+4s50%治疗削减
	if not battle.is_inside_tree(): return
	# ① 撞击拍: 全屏白闪 + 重震 + 顿帧
	battle._screen_flash_light()
	battle._shake(0.4); battle._add_hitstop(0.09)
	# ② 白热核心闪(瞬爆特大→收·引爆过曝)
	var core = Sprite3D.new()
	core.texture = VfxTex._make_fire_glow_tex()
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
	core.pixel_size = (128.0 * battle.WS) / 128.0
	core.modulate = Color(1.0, 1.0, 0.98, 0.0)
	core.position = battle._world_pos(center, 1.0); core.scale = Vector3.ONE * 0.5
	battle._world.add_child(core)
	var ct = battle._reg_tween(); ct.set_parallel(true)
	ct.tween_property(core, "scale", Vector3.ONE * 2.2, 0.07).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	ct.tween_property(core, "modulate:a", 1.0, 0.05)
	ct.chain().tween_property(core, "modulate:a", 0.0, 0.18)
	ct.chain().tween_callback(core.queue_free)
	# ③ 主火球膨胀至~400码(白热→橙→红→透)
	var ball = Sprite3D.new()
	ball.texture = VfxTex._make_fire_glow_tex()
	ball.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ball.shaded = false; ball.transparent = true
	ball.pixel_size = (128.0 * battle.WS) / 128.0
	ball.modulate = Color(1.0, 0.9, 0.55, 0.0)
	ball.position = battle._world_pos(center, 0.9); ball.scale = Vector3.ONE * 0.4
	battle._world.add_child(ball)
	var bt = battle._reg_tween()
	bt.tween_property(ball, "modulate", Color(1.0, 0.95, 0.7, 0.95), 0.06)
	bt.parallel().tween_property(ball, "scale", Vector3.ONE * (400.0 / 128.0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(ball, "modulate", Color(1.0, 0.45, 0.18, 0.85), 0.16)   # 转橙红
	bt.tween_property(ball, "modulate:a", 0.0, 0.28)
	bt.tween_callback(ball.queue_free)
	# ④ 冲击波环×3(白快·橙中·焦痕慢)
	battle._rocket_sys._rocket_shock_ring(center, Color(1.0, 0.97, 0.9, 0.9), 430.0, 0.3)
	battle._rocket_sys._rocket_shock_ring(center, Color(1.0, 0.7, 0.32, 0.7), 400.0, 0.42)
	battle._pending_shots.append({"delay": 0.05, "src": u, "fn": func() -> void: battle._rocket_sys._rocket_shock_ring(center, Color(0.9, 0.55, 0.25, 0.45), 300.0, 0.5)})
	# ⑤ 放射火焰streak×12(向外快闪)
	for k in range(12):
		var ang: float = TAU * float(k) / 12.0 + 0.26
		var d2: Vector2 = Vector2(cos(ang), sin(ang))
		battle._bolt_line(center + d2 * 30.0, center + d2 * randf_range(150.0, 240.0), Color(1.0, 0.75, 0.4, 0.8))
	# ⑥ 火花四溅 + 碎石 + 烟柱 + 焦痕
	battle._vfx._impact_particles(center, 0.4)
	battle._vfx._impact_particles(center, 1.6)
	battle._slam_debris(center)
	battle._rocket_sys._rocket_smoke_plume(center)
	battle._rocket_sys._rocket_scorch(center)
	# ⑦ 结算伤害(数值/机制封板不动)
	battle._skill_ring(center, Color(1.0, 0.7, 0.3, 0.75), 400.0)
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if (o["pos"] as Vector2).distance_to(center) > 400.0: continue
		battle._vfx._hit_spark(o)
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 4.0, o, false), Color("#ff4444"))   # 4A物理
		o["heal_reduce_until"] = maxf(float(o.get("heal_reduce_until", 0.0)), battle._t + 4.0)   # 4秒50%治疗削减
		o["heal_reduce_pct"] = maxf(float(o.get("heal_reduce_pct", 0.0)), 0.5)

## 夭折落地时长(秒)。文案不引用它, 但门禁要按它等 —— 具名常量便于两边同源。
const FALL_T := 0.22

## 【不可阻挡】施法期间的免控窗口(每个续期点往后延这么久)。
##
## ★★2026-08-21 从 0.3 改成 1.2 —— 验收场景当场抓到的洞:
##   续期点只有 0.00 / 0.68 / 1.28 / 踩滑每帧, 而 **0.00→0.68 之间隔了 0.68 秒**,
##   0.3 秒的窗口中途就到期了 ⇒ 起跳途中丢一发眩晕**照样能生效**(实测抓到)。
##   ⇒ 窗口必须**大于最大续期间隔**。1.2 覆盖 0.68 还留余量。
## ★为什么敢用长窗口: 每一条退出路径(正常收尾/中途夭折/阵亡)都**显式**调 `_unstoppable_clear`,
##   不靠"自然到期"兜底 —— 所以不会留悬空免控。
const UNSTOPPABLE_TICK := 1.2
## 【目标免控分支】原地结算的伤害: 目标最大生命 × 这个 + 1.5×ATK 物理(用户 2026-08-20 拍板)
const IMMUNE_BRANCH_MAXHP_PCT := 0.10
const IMMUNE_BRANCH_ATK_COEF := 1.5

## 【不可阻挡】开启/续期。按 LoL 奥拉夫 R 那一档: 清掉已有控制 + 免疫一切(含减速、含位移)。
##
## ★为什么要反复调而不是开一次: 减速有**两条并行通道**(slow_until 与 spd_move_mult/spd_aspd_mult),
##   免控窗口只挡得住"新的眩晕", 挡不住"已经挂上的减速" ⇒ 要在技能的几个节点各清一次。
##   (066 鲸涎浓浆的注释写过: 施加点散在几十处, 别在每个施加点判免疫, 改成周期清。)
func _unstoppable_apply(u: Dictionary) -> void:
	if not u.get("_unstoppable", false):
		return
	u["cc_immune_until"] = battle._t + UNSTOPPABLE_TICK
	u["_knock_immune"] = true
	u["stun_until"] = 0.0
	u["taunt_until"] = 0.0
	u["slow_until"] = 0.0
	u["spd_dbf_until"] = 0.0
	u["spd_move_mult"] = maxf(1.0, float(u.get("spd_move_mult", 1.0)))
	u["spd_aspd_mult"] = maxf(1.0, float(u.get("spd_aspd_mult", 1.0)))


## 【不可阻挡】解除。★每一条退出路径都要调 —— 正常收尾 / 中途夭折 / 自己阵亡,
##   漏一条就会留一个"永久免控"的单位(memory: 写进去了没人读 / 悬空状态)。
func _unstoppable_clear(u: Dictionary) -> void:
	u["_unstoppable"] = false
	u["cc_immune_until"] = 0.0
	u.erase("_knock_immune")


## 人体浪板中途夭折(目标先死/自己先死)时把小将放回地面。
##
## ★为什么不直接 `height = 0`: 那是瞬移, 会看到小将从半空"闪"到地上。
##   给一段短下落(0.22s, 二次加速=重力感), 和正常落地读起来一致。
## ★为什么不复用击飞的物理: 那条路要设 airborne/vy, 会把单位交给击飞状态机,
##   而这里只是收尾, 不该产生"被击飞"的语义(免控/受击判定都会跟着变)。
func _minion_abort_fall(u: Dictionary) -> void:
	u["_slam"] = false
	_unstoppable_clear(u)   # 夭折也要解除不可阻挡, 否则留一个永久免控的单位
	var h0: float = float(u.get("height", 0.0))
	if h0 <= 0.01:
		u["height"] = 0.0
		return
	var tw = battle._reg_tween()
	tw.tween_method(func(q: float) -> void:
		if u.get("alive", false):
			u["height"] = h0 * (1.0 - q * q)          # 二次加速下落
	, 0.0, 1.0, FALL_T)
	## ★★归零【不能只挂在 tween 末尾】: 无头 CI 下 tween 推进不稳(CLAUDE.md §3.5,
	##   海盗钩索为此连红三次)。⇒ tween 只负责"看着顺滑", **真正的归零走 sim 驱动的
	##   `_pending_shots`**(每帧按游戏时钟处理, 无头照样跑)。两条都到位 = 演出好看且结果确定。
	battle._pending_shots.append({"delay": FALL_T, "src": u, "fn": func() -> void:
		if u.get("alive", false):
			u["height"] = 0.0
			battle._melee_anim(u, "land")
	})


func _sk_minion_bodysurf(u: Dictionary, tgt) -> void:   # 近战小将·人体浪板: 高跳回2A血→(太近后跳)→射铁链晕→拉己向目标→接触10%目标maxHP物理→踩滑(对被踩逐渐2A物理·沿途1.5A+击退)→跳下
	if tgt == null or not tgt.get("alive", false): return
	var uu = u
	var tref: Dictionary = tgt
	uu["_slam"] = true
	## ★★【不可阻挡】(用户 2026-08-20:「在释放技能时会给自己不可阻挡的状态，就是免疫控制，
	##   跳起来放完技能完成最后的跳出动作后解除不可阻挡」)。
	##   按 LoL 的**奥拉夫 R 那一档**(用户:「按LOL 的」+「免推开，推开不就是控制技能吗」):
	##   先清掉身上已有的控制 + 免疫一切控制(含减速、含位移), 免控 ≠ 无敌(照样能被打死)。
	##   ⚠ 减速有**两条并行通道**(slow_* 与 spd_*), 只挡一条 = 半个免疫
	##   (这条坑写在 eq_potion_batch.gd:165-172, 066 鲸涎浓浆踩过)。
	uu["_unstoppable"] = true
	_unstoppable_apply(uu)
	battle._melee_anim(uu, "leap")                              # 0.00-0.64 蓄力+蹬地起跳
	battle._damage._heal(uu, float(uu.get("atk", 30.0)) * 2.0)          # 高跳: 回复2ATK生命
	battle._skill_ring(uu["pos"], Color(0.7, 0.85, 1.0, 0.5), 40.0)
	# ★蓄力→往后上方自然起跳(用户2026-07-18"正常蓄力往高处/后高处跳·别直上直下"): 位移往后+升到峰→悬停(不落)·等拉向目标才俯冲
	var jstart: Vector2 = uu["pos"]
	var back_dir: Vector2 = (jstart - (tref["pos"] as Vector2))
	back_dir = back_dir.normalized() if back_dir.length() > 1.0 else Vector2.LEFT
	var apex: Vector2 = jstart + back_dir * 120.0        # 往后上方跳~120码(后撤+20%·用户2026-07-18)
	apex.x = clampf(apex.x, battle.ARENA.position.x + 30.0, battle.ARENA.end.x - 30.0)
	apex.y = clampf(apex.y, battle.ARENA.position.y + 20.0, battle.ARENA.end.y - 20.0)
	var jt = battle._reg_tween()
	jt.tween_interval(0.3)                               # 蓄力更久(蹬地聚力·用户2026-07-18"蓄力久点·用力一跳·符合现实")
	jt.tween_method(func(q: float) -> void:              # 用力爆发式起跳: 高度sin(离地瞬间最快→到顶减速=真实抛物上升)·水平匀速往后上→到顶悬停
		if uu.get("alive", false):
			uu["pos"] = jstart.lerp(apex, q)
			uu["height"] = 5.76 * sin(q * PI * 0.5)
	, 0.0, 1.0, 0.34)
	battle._pending_shots.append({"delay": 0.68, "fn": func() -> void:   # 到顶后→从小将射铁链向目标+晕住顿一下(蓄力变久后挪·2026-07-18)
		if not (uu.get("alive", false) and tref.get("alive", false)):
			## ★2026-08-21 用户报「小将跳起时敌人死亡会飞到天上」—— 根因就在这里:
			##   起跳 tween 把 height 抬到 5.76 后【故意悬停不落】(等 _minion_bodysurf_ride 拉下来),
			##   而这两个提前返回只解锁了 _slam, **height 一个字没碰** ⇒ 永远挂在天上。
			##   全局那个 height<=0 归零只在【击飞路径】(airborne)里跑, 本技能不走击飞 ⇒ 没人管它。
			_minion_abort_fall(uu)
			return
		_unstoppable_apply(uu)                                   # 续免控(减速要周期清)
		battle._melee_anim(uu, "throw")                          # 0.68 滞空甩索(与射链同帧)
		## ★★【目标免控分支】(用户 2026-08-20:「如果这个技能的目标免疫控制则在绳索拉到对方后
		##   直接造成10%最大生命值加1.5ATK物理伤害而不会把自己拉向对方」)。
		##   在这里判是因为「绳索拉到对方」就是这一刻(射链命中)。
		##   10% 是**目标的**最大生命(用户确认), 走物理结算。
		##   ⚠ 判定必须走 `_is_cc_immune` —— `_stun()` 被免疫时静默 return, 拿不到信息。
		if battle._damage._is_cc_immune(tref):
			battle._surf_chain_shoot(uu["pos"], float(uu.get("height", 0.0)) + 0.6, tref["pos"], Color(0.6, 0.15, 0.15, 0.95))
			var _ib: float = float(tref.get("maxHp", 0.0)) * IMMUNE_BRANCH_MAXHP_PCT + float(uu.get("atk", 0.0)) * IMMUNE_BRANCH_ATK_COEF
			battle._damage._apply_damage_from(uu, tref,
				maxi(1, int(battle._resolve_dmg(uu, _ib, tref, false))), Color("#ff4444"))
			battle._vfx._hit_spark(tref)
			_minion_abort_fall(uu)                               # 不拉自己过去, 原地掉回地面
			return
		battle._surf_chain_shoot(uu["pos"], float(uu.get("height", 0.0)) + 0.6, tref["pos"], Color(0.6, 0.15, 0.15, 0.95))   # 从小将(空中·当前height)射铁链向目标
		battle._damage._stun(tref, 1.1, "_sk_minion_bodysurf", true)   # 晕住覆盖整个空中顿+俯冲
		battle._vfx._hit_spark(tref)
	, "src": u})
	battle._pending_shots.append({"delay": 1.28, "fn": func() -> void:   # 空中顿~0.6s(0.68射链→1.28拉)→拉己俯冲向目标→接触→踩滑(coroutine·用户2026-07-18)
		if not (uu.get("alive", false) and tref.get("alive", false)):
			## ★2026-08-21 用户报「小将跳起时敌人死亡会飞到天上」—— 根因就在这里:
			##   起跳 tween 把 height 抬到 5.76 后【故意悬停不落】(等 _minion_bodysurf_ride 拉下来),
			##   而这两个提前返回只解锁了 _slam, **height 一个字没碰** ⇒ 永远挂在天上。
			##   全局那个 height<=0 归零只在【击飞路径】(airborne)里跑, 本技能不走击飞 ⇒ 没人管它。
			_minion_abort_fall(uu)
			return
		_unstoppable_apply(uu)
		## 途中目标才变免控 ⇒ 中断伤害并跳回地面(用户 2026-08-20 原话)
		if battle._damage._is_cc_immune(tref):
			_minion_abort_fall(uu)
			return
		battle._melee_anim(uu, "dive")                           # 1.28-1.58 被绳拉着俯冲, 双脚前伸
		_minion_bodysurf_ride(uu, tref)
	, "src": u})

func _minion_bodysurf_ride(u: Dictionary, tref: Dictionary) -> void:   # 拉己向目标→接触10%maxHP→踩着目标滑行(coroutine)
	var from: Vector2 = u["pos"]
	var h0: float = float(u.get("height", 0.0))           # 从空中悬停高度俯冲下来
	var d = 0.0
	while is_instance_valid(battle) and d < 0.3 and u.get("alive", false):             # 0.3s从空中俯冲扑到目标身上(边冲边下落·减速40%·用户2026-07-18)
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if battle._over: break
		if battle._hitstop > 0.0 or (not battle._timestop._ts_active.is_empty() and not battle._arr_has_unit(battle._timestop._ts_active, u)): continue   # 时停: 只冻非active单位; 携带沙漏的自己要照常落地(否则_slam永不解锁=卡空中·用户2026-07-19)
		d += battle.get_process_delta_time()
		var kk: float = clampf(d / 0.3, 0.0, 1.0)
		if u.get("alive", false):
			u["pos"] = from.lerp((tref["pos"] as Vector2), kk)   # 水平接近目标
			u["height"] = h0 - (h0 - 0.3) * kk * kk       # 高度按重力加速下落(前段高·末段猛扎)→路径成弧线俯冲, 不直线飞(用户2026-07-18"符合现实")
	if not (u.get("alive", false) and tref.get("alive", false)):
		u["_slam"] = false; return
	battle._damage._apply_damage_from(u, tref, int(float(tref["maxHp"]) * 0.10), Color("#ff4444"))   # 接触: 10%目标最大生命(物理)
	battle._melee_anim(u, "surf")                                # 1.58-2.41 踩在目标身上滑行
	battle._vfx._hit_spark(tref); battle._shake(0.14)
	var sdir: Vector2 = ((tref["pos"] as Vector2) - from)
	sdir = sdir.normalized() if sdir.length() > 1.0 else Vector2.RIGHT
	var slide_from: Vector2 = tref["pos"]
	var slide_to: Vector2 = slide_from + sdir * 200.0
	slide_to.x = clampf(slide_to.x, battle.ARENA.position.x + 30.0, battle.ARENA.end.x - 30.0)
	slide_to.y = clampf(slide_to.y, battle.ARENA.position.y + 20.0, battle.ARENA.end.y - 20.0)
	var hit_others: Array = []                           # 已蹭到的敌(Array身份去重·不用dict-key防recursive_hash)
	var dot_t = 0.0
	var sd = 0.0
	var slide_dur = 0.833   # 滑行减速40%(0.5→0.833s·同距离更慢·用户2026-07-18)
	while is_instance_valid(battle) and sd < slide_dur and u.get("alive", false) and tref.get("alive", false):
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		if battle._over: break
		if battle._hitstop > 0.0 or (not battle._timestop._ts_active.is_empty() and not battle._arr_has_unit(battle._timestop._ts_active, u)): continue   # 时停: 只冻非active单位; 携带沙漏的自己要照常落地(否则_slam永不解锁=卡空中·用户2026-07-19)
		## 每帧续免控(减速要周期清), 并检查目标是否中途变成免控
		_unstoppable_apply(u)
		if battle._damage._is_cc_immune(tref):
			## 用户 2026-08-20:「途中目标免疫则中断伤害并跳回地面」
			_minion_abort_fall(u)
			return
		var dt = battle.get_process_delta_time()
		sd += dt
		var _sq: float = clampf(sd / slide_dur, 0.0, 1.0)
		_sq = 1.0 - (1.0 - _sq) * (1.0 - _sq)             # ease-out减速: 俯冲惯性大→摩擦逐渐减速停下(非匀速·用户2026-07-18)
		var mypos: Vector2 = slide_from.lerp(slide_to, _sq)
		u["pos"] = mypos
		u["height"] = 0.3                                  # 踩在目标身上(略高=站在冲浪板上·参考浪板)
		if tref.get("alive", false): tref["pos"] = mypos   # 踩着目标一起滑(目标=冲浪板)
		dot_t += dt
		if dot_t >= 0.1 and tref.get("alive", false):      # 对被踩目标逐渐2A物理(分摊·敌死则循环退出=自动结束·参考"血见底自动结束")
			dot_t -= 0.1
			battle._damage._apply_damage_from(u, tref, battle._atk_dmg(u, 2.0 * 0.1 / slide_dur, tref, false), Color("#ff4444"))
		for o in battle._targeting._enemies_of(u):                           # 沿途撞到的其他敌: 1.5A物理+撞飞(参考"撞飞其他敌")
			if is_same(o, tref) or not o.get("alive", false) or battle._arr_has_unit(hit_others, o): continue
			if (o["pos"] as Vector2).distance_to(mypos) <= 70.0:
				hit_others.append(o)
				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 1.5, o, false), Color("#ff4444"))
				## ★2026-08-21: 免控的第三方**不被撞飞** —— 用户已定「推开就是控制技能」,
				##   那免控就该免它。(伤害照吃, 免控 ≠ 免伤。)
				if not battle._damage._is_cc_immune(o):
					battle._damage._knockback(u, o, 150.0, 1.5, 1.1)      # 撞飞(vy×1.5腾空)
	battle._melee_anim(u, "land")                                # 2.41 侧跳→单膝落地
	# 完美收尾: 从目标身上跳到【目标周围】(不重叠·用户2026-07-18)→龟能随后正常回充
	var land_from: Vector2 = u["pos"]
	var perp: Vector2 = Vector2(-sdir.y, sdir.x)         # 滑向的垂直方向=往侧边跳
	if perp.length() < 0.5: perp = Vector2.UP
	var base: Vector2 = (tref["pos"] as Vector2) if tref.get("alive", false) else land_from
	var land_to: Vector2 = base + perp * 72.0            # 跳到目标侧边72码(不与目标重叠)
	land_to.x = clampf(land_to.x, battle.ARENA.position.x + 30.0, battle.ARENA.end.x - 30.0)
	land_to.y = clampf(land_to.y, battle.ARENA.position.y + 20.0, battle.ARENA.end.y - 20.0)
	var ho = battle._reg_tween()
	ho.tween_method(func(q: float) -> void:
		if u.get("alive", false):
			u["pos"] = land_from.lerp(land_to, q)       # 跳到目标周围
			u["height"] = 0.3 + 1.5 * 4.0 * q * (1.0 - q)   # 跳弧
	, 0.0, 1.0, 0.3)
	ho.tween_callback(func() -> void:
		if u.get("alive", false): u["height"] = 0.0)
	u["_slam"] = false
	## ★「完成最后的跳出动作后解除不可阻挡」——用户原话就在这一步
	_unstoppable_clear(u)

func _hiding_dome(u: Dictionary, col: Color, dur: float) -> void:   # 缩头·壳护罩: hex-bubble罩身呼吸dur秒→碎裂放大淡出(跟随单位·2026-07-17 Q4草案)
	var dm = Sprite3D.new()
	dm.texture = load("res://assets/sprites/vfx/fx-hex-bubble.png")
	dm.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dm.shaded = false; dm.transparent = true
	dm.pixel_size = (128.0 * battle.WS) / float(maxi(1, dm.texture.get_height()))   # 110→128+alpha0.75→0.85(2026-07-17自查: 挤团时罩偏淡)
	dm.modulate = Color(col.r, col.g, col.b, 0.0)
	dm.position = battle._world_pos(u["pos"], 0.75)
	battle._world.add_child(dm)
	battle._follow_vfx.append({"spr": dm, "unit": u, "h": 0.75})
	var cycles: int = maxi(1, int(round((dur - 0.6) / 0.6)))
	var t = battle._reg_tween()
	t.tween_property(dm, "modulate:a", 0.85, 0.18)
	for i in range(cycles):                                     # 呼吸脉动(护罩活着的感觉)
		t.tween_property(dm, "scale", Vector3.ONE * 1.08, 0.3)
		t.tween_property(dm, "scale", Vector3.ONE, 0.3)
	t.tween_interval(maxf(0.05, dur - 0.18 - float(cycles) * 0.6 - 0.28))
	t.tween_property(dm, "scale", Vector3.ONE * 1.35, 0.28)     # 到期碎裂: 放大+淡出(不瞬删)
	t.parallel().tween_property(dm, "modulate:a", 0.0, 0.28)
	t.chain().tween_callback(dm.queue_free)

func _hiding_summon_vfx(pos: Vector2) -> void:                 # 喊龟·召唤法阵(2026-07-17 Q4草案): 细线环扩开+内环倒收+土金光柱+星粒上腾+落地尘
	var glow = VfxTex._make_fire_glow_tex()
	var stex = VfxTex._make_star_texture()
	var ring = Sprite3D.new()                                  # 外法阵环扩开
	ring.texture = VfxTex._make_thin_ring_tex()
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ring.axis = Vector3.AXIS_Y
	ring.shaded = false; ring.transparent = true
	ring.modulate = Color(0.95, 0.8, 0.45, 0.9)
	ring.pixel_size = (20.0 * battle.WS) / 256.0
	ring.position = battle._world_pos(pos, 0.065)
	battle._world.add_child(ring)
	var rt = battle._reg_tween()
	rt.tween_method(func(q: float) -> void:
		if is_instance_valid(ring): ring.pixel_size = (maxf(20.0, 300.0 * q) * battle.WS) / 256.0
	, 0.0, 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_interval(0.45)
	rt.tween_property(ring, "modulate:a", 0.0, 0.3)
	rt.tween_callback(ring.queue_free)
	var inner = battle._px_ground_sprite(VfxTex._make_pixel_ring_tex(), pos, 260.0, Color(0.85, 0.7, 0.4, 0.7), 0.06)   # 内环倒收(聚拢感)
	var it = battle._reg_tween()
	it.tween_method(func(q: float) -> void:
		if is_instance_valid(inner): inner.pixel_size = (maxf(50.0, 260.0 * (1.0 - q)) * battle.WS) / 48.0
	, 0.0, 1.0, 0.45)
	it.tween_property(inner, "modulate:a", 0.0, 0.2)
	it.tween_callback(inner.queue_free)
	for gi in range(3):                                         # 土金光柱(三段叠高·从地亮起)
		var gp = Sprite3D.new()
		gp.texture = glow
		gp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gp.shaded = false; gp.transparent = true
		gp.pixel_size = (float(90 - gi * 20) * battle.WS) / 128.0
		gp.modulate = Color(1.0, 0.85, 0.5, 0.0)
		gp.position = battle._world_pos(pos, 0.3 + 0.55 * float(gi))
		battle._world.add_child(gp)
		var gt = battle._reg_tween()
		gt.tween_property(gp, "modulate:a", 0.7, 0.15).set_delay(0.08 * float(gi))
		gt.tween_interval(0.3)
		gt.tween_property(gp, "modulate:a", 0.0, 0.3)
		gt.tween_callback(gp.queue_free)
	for si in range(6):                                         # 星粒上腾
		var sp = Sprite3D.new()
		sp.texture = stex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.006
		sp.modulate = Color(1.0, 0.9, 0.6, 0.95)
		var sa: float = TAU * float(si) / 6.0
		sp.position = battle._world_pos(pos + Vector2(cos(sa), sin(sa)) * randf_range(30.0, 70.0), 0.1)
		battle._world.add_child(sp)
		var spt = battle._reg_tween(); spt.set_parallel(true)
		spt.tween_property(sp, "position", battle._world_pos(pos + Vector2(cos(sa), sin(sa)) * randf_range(20.0, 50.0), randf_range(1.2, 1.8)), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spt.tween_property(sp, "modulate:a", 0.0, 0.7)
		spt.chain().tween_callback(sp.queue_free)
	battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", pos, 130.0, 0.12)

func _hiding_legacy_vfx(from_pos: Vector2, owner: Dictionary) -> void:   # 遗志继承: 金光点从随从尸位飞回主人入体+金环闪(2026-07-17 Q4草案)
	var glow = VfxTex._make_fire_glow_tex()
	var oref: Dictionary = owner
	for i in range(5):
		var dot = Sprite3D.new()
		dot.texture = glow
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dot.shaded = false; dot.transparent = true
		dot.pixel_size = 0.005
		dot.modulate = Color(1.0, 0.85, 0.45, 0.95)
		var start: Vector2 = from_pos + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
		dot.position = battle._world_pos(start, randf_range(0.3, 0.9))
		battle._world.add_child(dot)
		var dt = battle._reg_tween()
		dt.tween_interval(0.06 * float(i))
		dt.tween_method(func(q: float) -> void:                 # 活追踪主人(主人在走也能飞进身体)
			if is_instance_valid(dot) and oref.get("alive", false):
				dot.position = battle._world_pos(start.lerp(oref["pos"], q), lerpf(0.6, 0.8, q))
		, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dt.tween_property(dot, "modulate:a", 0.0, 0.12)
		dt.tween_callback(dot.queue_free)
	var ft = battle._reg_tween()                                      # 入体金环闪
	ft.tween_interval(0.55)
	ft.tween_callback(func() -> void:
		if oref.get("alive", false):
			battle._skill_ring(oref["pos"], Color(1.0, 0.85, 0.4, 0.7), 70.0))

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御(封板·100龟能): 缩壳20%maxHp盾(4秒)+护甲+20%(5秒)·到期剩余盾20%转生命; 2026-07-17用户: 持盾锁龟能+盾段壳青绿特殊色
	battle._damage._grant_shield(u, u["maxHp"] * DEFEND_SHIELD_PCT, DEFEND_SHIELD_SEC)
	u["_hidingShellVal"] = u["maxHp"] * 0.20                     # 血条壳青绿特殊盾段(hp_bar照圣盾段收敛)
	u["hiding_shield_until"] = battle._t + DEFEND_SHIELD_SEC                          # 持盾锁龟能(石头rock_shield四连判据同款·盾破/到期恢复)
	battle._damage._buff(u, "def", DEFEND_DEF_UP, true, DEFEND_DEF_SEC)
	var uu: Dictionary = u
	battle._pending_shots.append({"delay": 3.95, "fn": func(): battle._damage._heal(uu, float(uu.get("shield", 0.0)) * DEFEND_CONVERT), "src": u})   # 到期前读剩余盾×20%转生命
	battle._pending_shots.append({"delay": 4.0, "fn": func(): uu["_hidingShellVal"] = 0.0, "src": u})   # 到期清特殊段标记
	_hiding_dome(u, Color(0.55, 0.85, 0.6, 1.0), 4.0)          # 壳青绿护罩4秒呼吸→碎裂(2026-07-17: 原零画面)
	battle._pending_shots.append({"delay": 4.0, "fn": func(): _hiding_legacy_heal_vfx(uu), "src": u})   # 碎裂后: 绿光点流入(剩盾转血可视)

func _hiding_legacy_heal_vfx(u: Dictionary) -> void:            # 防御盾到期转血: 绿光点绕身流入
	if not u.get("alive", false): return
	var glow = VfxTex._make_fire_glow_tex()
	var oref: Dictionary = u
	for i in range(3):
		var dot = Sprite3D.new()
		dot.texture = glow
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dot.shaded = false; dot.transparent = true
		dot.pixel_size = 0.005
		dot.modulate = Color(0.5, 0.95, 0.6, 0.9)
		var sa: float = TAU * float(i) / 3.0
		var start: Vector2 = (oref["pos"] as Vector2) + Vector2(cos(sa), sin(sa)) * 60.0
		dot.position = battle._world_pos(start, 0.4)
		battle._world.add_child(dot)
		var dt = battle._reg_tween()
		dt.tween_method(func(q: float) -> void:
			if is_instance_valid(dot) and oref.get("alive", false):
				dot.position = battle._world_pos(start.lerp(oref["pos"], q), lerpf(0.4, 0.8, q))
		, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dt.tween_property(dot, "modulate:a", 0.0, 0.1)
		dt.tween_callback(dot.queue_free)

func _hiding_minion_of(u: Dictionary):                          # 取该缩头龟的存活随从(A方案完整龟)
	var result = null
	for o in battle._units:
		if o.get("is_summon", false) and is_same(o.get("summon_owner", null), u) and o.get("minion_kind", null) != null and o.get("alive", false):
			result = o
			break
	return result

func _hiding_apply_buff(o: Dictionary, dur: float) -> void:     # 强化随从增益(dur秒·dur<=0=永久·供随从死亡继承给主人): 攻/甲/抗+10%·吸血+10%·暴击+20%
	var d: float = dur if dur > 0.0 else 9999.0
	battle._damage._buff(o, "atk", EMPOWER_STAT, true, d)
	battle._damage._buff(o, "def", EMPOWER_STAT, true, d)
	battle._damage._buff(o, "mr", EMPOWER_STAT, true, d)
	battle._damage._buff(o, "lifesteal", EMPOWER_STAT, false, d)
	o["crit"] = float(o.get("crit", 0.0)) + EMPOWER_CRIT
	if dur > 0.0:
		var oo: Dictionary = o
		battle._pending_shots.append({"delay": dur, "fn": func(): oo["crit"] = float(oo.get("crit", 0.0)) - EMPOWER_CRIT, "src": o})
		var gl = Sprite3D.new()                                 # 用户2026-07-17: 被强化对象冒红光持续到效果结束·渐入渐出不瞬变(跟随单位)
		gl.texture = VfxTex._make_fire_glow_tex()
		gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gl.shaded = false; gl.transparent = true
		gl.pixel_size = (72.0 * battle.WS) / 128.0
		gl.modulate = Color(1.0, 0.32, 0.25, 0.0)
		gl.position = battle._world_pos(o["pos"], 0.55)
		battle._world.add_child(gl)
		battle._follow_vfx.append({"spr": gl, "unit": o, "h": 0.55})
		var glt = battle._reg_tween()
		glt.tween_property(gl, "modulate:a", 0.55, 0.4)          # 渐入0.4s
		for pi in range(maxi(1, int((dur - 0.8) / 0.8))):        # 中段呼吸(力量涌动)
			glt.tween_property(gl, "modulate:a", 0.38, 0.4)
			glt.tween_property(gl, "modulate:a", 0.55, 0.4)
		glt.tween_property(gl, "modulate:a", 0.0, 0.4)           # 渐出0.4s(到效果结束)
		glt.tween_callback(gl.queue_free)
	battle._skill_ring(o["pos"], Color(0.9, 0.7, 0.3, 0.5), 44.0)

func _sk_hiding_shrink(u: Dictionary) -> void:                  # 缩头(封板·100龟能): 立即给随从+50%技能龟能 + 自身缩头3秒(80%减伤·不能攻击/移动·★龟能条锁定=设stun_until→_tick_skill_cd遇stun直接return不充能·对用户#1"且锁龟能条")
	var m = _hiding_minion_of(u)
	if m != null:
		var cost: float = 95.0
		var acts: Array = m.get("active_skills", [])
		if not acts.is_empty(): cost = battle.SkillEnergy.cost_of(str(acts[0]))
		## ★★这里原来写的是 `m["energy"] += cost * 0.5` —— **随从的 `energy` 字段全引擎零读者**,
		##   随从跟真龟一样走技能冷却(`skill_cd`), 龟能的唯一入口是 `_eq_grant_energy`(龟能银行)。
		##   探针实测(2026-09-01): 随从 bamboo/bambooHeal 冷却剩 8.050 秒, 放完缩头**仍是 8.050** ——
		##   这个 100 龟能大招「立即给随从 +50% 技能龟能」那一半**完全是空的**。
		##   (与同日抓到的斧头 `ax["energy"]` 是同一个形状: 读/写了一个没人配对的字段)
		battle._equip_sys._eq_grant_energy(m, cost * SHRINK_MINION_ENERGY)   # 给随从+50%技能龟能(加速放技)
		battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], m["pos"], 20.0, Color(0.5, 0.85, 1.0, 0.6), 0.4)   # 能量束射向随从(2026-07-17)
		var mref: Dictionary = m
		var mb = battle._reg_tween()
		mb.tween_interval(0.35)
		mb.tween_callback(func() -> void:
			if mref.get("alive", false): battle._skill_ring(mref["pos"], Color(0.6, 0.9, 1.0, 0.6), 50.0))
	battle._damage._stun(u, SHRINK_SEC, "_sk_hiding_shrink", true)   # 缩头3秒: 不能攻击/移动(定身)
	u["damage_reduction"] = SHRINK_DR                                # 80%减伤
	var uu: Dictionary = u
	battle._pending_shots.append({"delay": 3.0, "fn": func(): uu["damage_reduction"] = 0.0, "src": u})
	_hiding_dome(u, Color(0.78, 0.64, 0.4, 1.0), 3.0)          # 土棕硬壳护罩3秒(80%减伤可视·与技2壳绿区分)
	battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", u["pos"], 90.0, 0.1)   # 缩进壳的尘土

func _sk_hiding_buff(u: Dictionary) -> void:                    # 强化随从(封板·80龟能): 随从注入力量5秒(攻/甲/抗+10%·吸血+10%·暴击+20%)
	var m = _hiding_minion_of(u)
	if m == null: return
	_hiding_apply_buff(m, EMPOWER_SEC)
	battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], m["pos"], 24.0, Color(1.0, 0.85, 0.4, 0.65), 0.45)   # 金色注入光束(2026-07-17)
	var stex = VfxTex._make_star_texture()
	var mref: Dictionary = m
	for si in range(3):                                         # 3颗金星绕随从升腾
		var sp = Sprite3D.new()
		sp.texture = stex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.007
		sp.modulate = Color(1.0, 0.88, 0.45, 0.0)
		sp.position = battle._world_pos(m["pos"], 0.3)
		battle._world.add_child(sp)
		var a0: float = TAU * float(si) / 3.0
		var st = battle._reg_tween()
		st.tween_interval(0.3)
		st.tween_method(func(q: float) -> void:
			if not is_instance_valid(sp): return
			if mref.get("alive", false):
				var aa: float = a0 + q * TAU * 1.5
				sp.position = battle._world_pos((mref["pos"] as Vector2) + Vector2(cos(aa), sin(aa)) * 34.0, 0.3 + q * 1.3)
			sp.modulate.a = 0.95 * clampf(q / 0.15, 0.0, 1.0) * clampf((1.0 - q) / 0.25, 0.0, 1.0)
		, 0.0, 1.0, 0.9)
		st.tween_callback(sp.queue_free)

func _hiding_shell_harden(u: Dictionary) -> void:              # 缩壳(普攻rider): 每次普攻+1护甲+1魔抗(永久累积)+0.1A护盾
	u["base_def"] = float(u["base_def"]) + HARDEN_RESIST
	u["base_mr"] = float(u["base_mr"]) + 1.0
	battle._recalc_stats(u)
	battle._damage._grant_shield(u, u["atk"] * HARDEN_SHIELD)
	u["_harden_n"] = int(u.get("_harden_n", 0)) + 1             # 硬化反馈(2026-07-17·Q12轻量): 每击微光, 每5层一次甲片环
	var gp = Sprite3D.new()
	gp.texture = VfxTex._make_fire_glow_tex()
	gp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; gp.shaded = false; gp.transparent = true
	gp.pixel_size = (26.0 * battle.WS) / 128.0
	gp.modulate = Color(0.9, 0.78, 0.5, 0.8)
	gp.position = battle._world_pos(u["pos"], 0.7)
	battle._world.add_child(gp)
	var gt = battle._reg_tween()
	gt.tween_property(gp, "modulate:a", 0.0, 0.2)
	gt.tween_callback(gp.queue_free)
	if int(u["_harden_n"]) % 5 == 0:
		battle._skill_ring(u["pos"], Color(0.85, 0.72, 0.45, 0.55), 56.0)

# 返回当前所有 A/B/C 稀有度的龟 id (缩头召唤池)。数据缺失时退回 battle.HIDING_POOL 兜底。
func _hiding_pool() -> Array:
	var out: Array = []
	for id in battle._data_by_id:
		var r = str((battle._data_by_id[id] as Dictionary).get("rarity", ""))
		if r == "A" or r == "B" or r == "C":
			out.append(str(id))
	return out if not out.is_empty() else battle.HIDING_POOL
