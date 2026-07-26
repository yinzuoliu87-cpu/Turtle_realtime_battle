class_name TrainerSystem
extends RefCounted
## 训龟大师·场外技能系统(钩锁/冰川/怒火/口哨/AI/普攻·从主场景抽出·2026-07-25)。
## 【训龟大师技能与龟技能/装备分开·用户定向】类内名不变;外部名加 battle.

var battle

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
		var haste: float = 1.0 + 0.05 * float(u.get("_ms_stacks", 0)) if str(u.get("_tr_passive", "")) == "magic_stone" else 1.0
		u["_tr_atk_cd"] = battle.TRAINER_ATK_INTERVAL / haste
		# 朝向目标(扔之前转身), 再播扔石头动作
		u["face_right"] = tgt["pos"].x > u["pos"].x
		_trainer_throw_anim(u)
		battle._fire_trainer_rock(u, tgt)
		if str(u.get("_tr_passive", "")) == "magic_stone":
			_trainer_magicstone_onhit(u, tgt)


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
	return false

## 施放钩锁(仔细照锤石Q·2026-07-24返工): 前摇→中速飞→【到达才】钩住(不再瞬间结算)。命中CD20/空放CD10。
## ★到达才结算走 battle._pending_shots(delta制·无头也稳), 不是等tween跑完(照 CLAUDE.md §3.5)。返回是否【将】命中。
func _cast_hook(trainer: Dictionary, dir: Vector2) -> bool:
	if trainer == null or not trainer.get("alive", false):
		return false
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	var tgt = _hook_first_target(trainer, dir)
	if tgt != null:
		trainer["_active_cd"] = battle.HOOK_CD
		var dist: float = (tgt["pos"] - trainer["pos"]).length()
		var arrive: float = battle.HOOK_WINDUP + dist / battle.HOOK_MISSILE_SPD   # 前摇 + 中速飞行
		trainer["_cast_lock_until"] = battle._t + arrive                  # 甩钩期间大师站定(锤石: 飞行中不能动)
		var tt: Dictionary = trainer
		var kk: Dictionary = tgt
		battle._pending_shots.append({"delay": arrive, "src": trainer, "fn": func() -> void:
			if kk.get("alive", false):
				_hook_grab(tt, kk)})                               # 钩子到达那一刻才钩住
		_hook_dramatize(trainer, tgt)                              # 演出: 前摇→中速飞→到达
		return true
	trainer["_active_cd"] = battle.HOOK_CD_MISS                           # 空放: 只10秒(返还10)
	trainer["_cast_lock_until"] = battle._t + battle.HOOK_WINDUP + battle.HOOK_RANGE / battle.HOOK_MISSILE_SPD
	_hook_dramatize_miss(trainer, dir)
	return false

## ── 怒火药水(主动·CD16·700码点·用户2026-07-23 需求): 丢药水→落点300码内友军 5秒 +30%攻速 +25%龟能充能 +25%移速 ──
func _fury_apply_buffs(trainer: Dictionary, point: Vector2) -> int:
	var side: String = str(trainer.get("side", ""))
	var n: int = 0
	for o in battle._units:
		if not o.get("alive", false) or o.get("is_trainer", false):
			continue
		if str(o.get("side", "")) != side:
			continue
		if o["pos"].distance_to(point) > 300.0:
			continue
		o["haste_mult"] = 1.3;      o["haste_until"] = battle._t + 5.0        # +30% 攻速
		o["move_buff_mult"] = 1.25; o["move_buff_until"] = battle._t + 5.0    # +25% 移速
		o["echarge_mult"] = 1.25;   o["echarge_until"] = battle._t + 5.0      # +25% 龟能充能速率
		n += 1
	return n

## 怒火药水演出: 抛物线飞到落点 → 橙红 splash + 怒火圈(纯观感)。素材(原图)待 R1g, 暂用火光占位。
func _fury_dramatize(trainer: Dictionary, point: Vector2) -> void:
	if battle._world == null:
		return
	var from2d: Vector2 = trainer["pos"]
	var tex = load("res://assets/sprites/vfx/fury-potion.png") if ResourceLoader.exists("res://assets/sprites/vfx/fury-potion.png") else VfxTex._make_fire_glow_tex()
	var pot = Sprite3D.new()
	pot.texture = tex; pot.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pot.billboard = BaseMaterial3D.BILLBOARD_ENABLED; pot.shaded = false; pot.transparent = true
	pot.pixel_size = (40.0 * battle.WS) / float(maxi(1, tex.get_height()))
	pot.modulate = Color(1.0, 0.55, 0.25)
	battle._world.add_child(pot)
	var peak: float = 2.4
	var tw = battle._reg_tween()
	tw.tween_interval(battle.HOOK_WINDUP)
	tw.tween_method(func(p: float) -> void:   # 抛物线飞
		if not is_instance_valid(pot): return
		pot.position = battle._world_pos(from2d.lerp(point, p), 0.9 + peak * sin(PI * p))
	, 0.0, 1.0, maxf(0.15, from2d.distance_to(point) / 800.0))
	tw.tween_callback(func() -> void:
		if is_instance_valid(pot): pot.queue_free()
		battle._skill_ring(point, Color(1.0, 0.5, 0.2, 0.75), 300.0)          # 300码怒火圈
		battle._burst_vfx("res://assets/sprites/vfx/cannon-blast.png", point, 120.0, 0.4))

## ── 口哨(主动·CD14·无目标·用户2026-07-23): 随机 3 选 1 —— 临时血 / 灵体小龟气波 / 狂暴免死 ──
func _whistle_temphp(trainer: Dictionary):
	var ally = battle._random_ally(trainer)
	if ally == null:
		return null
	battle._apply_temp_maxhp(ally, 700.0, 5.0)
	battle._skill_ring(ally["pos"], Color(0.5, 1.0, 0.6, 0.7), 46.0)
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
		o["def_shred_until"] = battle._t + 5.0    # 先削甲(30%·让这一发也吃到)
		battle._damage._apply_damage_from(trainer, o, battle._resolve_dmg(trainer, 200.0, o, false), Color("#8fd0ff"), 0.0, false, false)   # 200物理
		battle._damage._knockback(trainer, o, 100.0)      # 击飞
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
	battle._damage._buff(ally, "atk", 0.2, true, 4.0)          # +20% 攻击力
	battle._damage._buff(ally, "lifesteal", 20, false, 4.0)    # +20% 生命偷取
	ally["deathfloor_until"] = battle._t + 4.0         # 4秒免疫死亡(血锁≥1)
	battle._skill_ring(ally["pos"], Color(1.0, 0.4, 0.3, 0.75), 46.0)

## 灵体小龟演出: 蓝幽灵小龟入场(spirit-turtle.png·缺图则只放气波不崩) + 蓝气波束(qibo-ball.png 真气波素材)。
func _whistle_spirit_dramatize(trainer: Dictionary, origin: Vector2, dir: Vector2) -> void:
	if battle._world == null:
		return
	_spawn_spirit_turtle(origin)
	var end2d: Vector2 = origin + dir * 500.0
	battle._beam_vfx("res://assets/sprites/vfx/qibo-ball.png", origin, end2d, 66.0, Color(0.6, 0.9, 1.0, 0.9), 0.35)
	battle._skill_ring(origin, Color(0.5, 0.8, 1.0, 0.6), 40.0)

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
			o["slow_mag"] = 0.6
			o["glacier_vuln_until"] = battle._t + 0.2   # 受伤 +20%(见 _mitigate_incoming)
	battle._glacier_zones = keep

## 冰川带演出: 从大师沿方向铺一条真冰带(ice-field.png), 铺满整条 500 码带、亮蓝白, 持续 6 秒 = 冰川区判定寿命。
func _glacier_dramatize(from2d: Vector2, dir: Vector2) -> void:
	if battle._world == null:
		return
	# 用真冰贴图铺地(160×64 蓝白冰), 而非链束占位; 6 秒常驻(与 battle._glacier_zones 的 until 对齐, 站上去减速期间一直看得见冰)
	battle._beam_vfx("res://assets/sprites/vfx/ice-field.png", from2d, from2d + dir * 500.0, 90.0, Color(0.85, 0.95, 1.0, 0.9), 6.0, 0.12)
	battle._skill_ring(from2d, Color(0.7, 0.9, 1.0, 0.6), 46.0)

## ★纯效果结算(可测): 钩住 target → 眩晕(吃韧性) + 标记4秒【一段段拽】 + 4秒受伤放大。不建任何 tween。
func _hook_grab(trainer: Dictionary, target: Dictionary) -> void:
	battle._damage._stun(target, battle.HOOK_STUN, "hook")                          # 眩晕4秒(吃韧性)
	target["_hook_pull_until"] = battle._t + battle.HOOK_STUN               # 4秒内被拽
	target["_hook_pull_by"] = trainer                         # 朝这个大师拽
	target["_hook_tug_t0"] = battle._t + battle.HOOK_TUG_DELAY              # 第一下拽的时刻(0.1s后·锤石口径)
	target["hook_vuln_until"] = battle._t + battle.HOOK_STUN                # 4秒内受伤 ×1.25(见 _mitigate_incoming)
	target["_hooked_by"] = trainer                            # 触发证据(同步标记, 非tween)

## 每帧: 大师钩锁冷却扣减; 被钩单位【一段段】朝大师拽(每 battle.HOOK_PULL_INTERVAL 秒里, 前 battle.HOOK_TUG_DUR 秒快速位移一段, 其余停顿)。
## ★非匀速(用户2026-07-24: 锤石钩住是一下一下拽, 不是匀速)。在 _process 战斗门内调。
func _tick_hooks(delta: float) -> void:
	var tug_spd: float = battle.HOOK_TUG_DIST / battle.HOOK_TUG_DUR         # 拽的那一下的速度(码/秒)
	for u in battle._units:
		if u.get("is_trainer", false) and float(u.get("_active_cd", 0.0)) > 0.0:
			u["_active_cd"] = maxf(0.0, float(u["_active_cd"]) - delta)
		if battle._t < float(u.get("_hook_pull_until", 0.0)):
			var by = u.get("_hook_pull_by", null)
			if by is Dictionary and by.get("alive", false):
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
		if str(u.get("side", "")) == "left" and not battle._stress:
			continue   # 左侧=玩家操控, AI 不接管(无头压测除外)
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

## 每帧刷新法术圆盘: 喂我方大师钩锁冷却(比例+剩余秒); 非战斗期(摆位/呈现/结束)隐藏。
func _hook_dramatize(trainer: Dictionary, target: Dictionary) -> void:
	if battle._world == null:
		return   # 无场景(门禁裸实例)→只跑结算不跑演出
	var from2d: Vector2 = trainer["pos"]
	var to2d: Vector2 = target["pos"]
	var htex = load("res://assets/sprites/vfx/trainer-hook.png")
	if htex == null:
		return
	var hook = Sprite3D.new()
	hook.texture = htex; hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hook.billboard = BaseMaterial3D.BILLBOARD_DISABLED; hook.shaded = false; hook.transparent = true
	hook.pixel_size = (46.0 * battle.WS) / float(maxi(1, htex.get_height()))
	hook.position = battle._world_pos(from2d, 1.0)
	hook.modulate.a = 0.0                     # 前摇期钩子还没甩出→先隐形
	battle._world.add_child(hook)
	battle._skill_ring(from2d, Color(0.55, 0.8, 1.0, 0.5), 30.0)   # 前摇: 大师脚下蓄力环
	var flight: float = maxf(0.12, from2d.distance_to(to2d) / battle.HOOK_MISSILE_SPD)   # 中速(600码≈0.63s)
	var ct = [0.0]
	var tw = battle._reg_tween()
	tw.tween_interval(battle.HOOK_WINDUP)            # ① 前摇: 松手/按Q后不立刻丢
	tw.tween_callback(func() -> void:
		if is_instance_valid(hook): hook.modulate.a = 1.0)   # ② 甩出: 钩子现身
	tw.tween_method(func(p: float) -> void:   # ③ 中速飞向目标(带链条)
		if not is_instance_valid(hook): return
		var hp2: Vector2 = from2d.lerp(to2d, p)
		hook.position = battle._world_pos(hp2, 1.0)
		battle._face_screen_dir(hook, from2d, hp2)
		ct[0] += 0.02
		if ct[0] >= 0.05:
			ct[0] = 0.0
			battle._pirate_sys._pirate_chain(from2d, hp2)
	, 0.0, 1.0, flight)
	tw.tween_callback(func() -> void:         # ④ 到达
		battle._skill_ring(to2d, Color(0.75, 0.82, 0.95, 0.7), 40.0)
		if is_instance_valid(hook): hook.queue_free())

## 空放演出: 钩爪飞到射程末端再消失(告诉玩家「没勾到」)。
func _hook_dramatize_miss(trainer: Dictionary, dir: Vector2) -> void:
	if battle._world == null:
		return   # 无场景(门禁裸实例)→只跑结算不跑演出
	var from2d: Vector2 = trainer["pos"]
	var d = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var end2d: Vector2 = from2d + d * battle.HOOK_RANGE
	var htex = load("res://assets/sprites/vfx/trainer-hook.png")
	if htex == null:
		return
	var hook = Sprite3D.new()
	hook.texture = htex; hook.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hook.billboard = BaseMaterial3D.BILLBOARD_DISABLED; hook.shaded = false; hook.transparent = true
	hook.pixel_size = (46.0 * battle.WS) / float(maxi(1, htex.get_height()))
	hook.position = battle._world_pos(from2d, 1.0)
	battle._world.add_child(hook)
	var ct = [0.0]
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:   # 甩出→末端→(链条)
		if not is_instance_valid(hook): return
		var hp2: Vector2 = from2d.lerp(end2d, p if p < 0.5 else 1.0 - (p - 0.5))   # 去程一半+收回一半
		hook.position = battle._world_pos(hp2, 1.0)
		battle._face_screen_dir(hook, from2d, hp2)
		ct[0] += 0.02
		if ct[0] >= 0.05:
			ct[0] = 0.0
			battle._pirate_sys._pirate_chain(from2d, hp2)
	, 0.0, 1.0, 0.34)
	tw.tween_callback(func() -> void:
		if is_instance_valid(hook): hook.queue_free())


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
	var magic: int = maxi(1, int(battle._resolve_dmg(u, float(tgt["maxHp"]) * 0.02, tgt, true)))   # 2%目标最大生命·魔法(过魔抗)
	battle._damage._apply_damage_from(u, tgt, magic, Color("#c86bff"), 0.0, false, true)
	u["_ms_stacks"] = int(u.get("_ms_stacks", 0)) + 1                                        # 攻速叠一层(持续到本场结束)


## 移动端才建摇杆; PC 上根本不建(不占屏)。
## ★TRAINER_JOY=1 可在 PC 上强开, 用于自验手感与门禁 —— 否则这段代码在开发机上永远跑不到,
##   等于没写(EQDEMO 那次的教训: 触发不到的路径看着像"没生效")。
func _trainer_sprite_dict() -> Dictionary:
	var tex: Texture2D = null
	if ResourceLoader.exists(battle.TRAINER_SPRITE):
		tex = load(battle.TRAINER_SPRITE)
	if tex == null:
		battle.push_warning("[训龟大师] 立绘未就绪 —— 用程序占位图。形象待定(用户要「像素风的冒险家」)")
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