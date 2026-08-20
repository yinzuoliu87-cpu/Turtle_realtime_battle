class_name NinjaSystem
extends RefCounted
## 忍者龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _ninja_mark_shatter(spr) -> void:
	if not is_instance_valid(spr): return
	var pos: Vector3 = spr.position
	var sc0: Vector3 = spr.scale
	var bt = battle.create_tween(); bt.set_parallel(true)
	bt.tween_property(spr, "modulate:a", 0.0, 0.2)
	bt.tween_property(spr, "scale", sc0 * 1.6, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.chain().tween_callback(spr.queue_free)
	for k in range(4):
		var sh = Sprite3D.new()
		sh.texture = load("res://assets/sprites/vfx/crystal-shard.png")
		sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sh.shaded = false; sh.transparent = true
		sh.modulate = Color(1.0, 0.35, 0.35, 0.9)
		sh.pixel_size = 0.006
		sh.position = pos
		battle._world.add_child(sh)
		var ang: float = float(k) * TAU / 4.0 + 0.4
		var dst = pos + Vector3(cos(ang) * 0.2, 0.06, sin(ang) * 0.2)
		var st = battle.create_tween().bind_node(sh); st.set_parallel(true)
		st.tween_property(sh, "position", dst, 0.24)
		st.tween_property(sh, "modulate:a", 0.0, 0.24)
		st.chain().tween_callback(sh.queue_free)

func _ninja_dash(u: Dictionary, target: Dictionary) -> void:    # 被动·冲击(亚索E式): 朝最近敌固定位移300码(2026-07-22订正: 头注释一直没跟上同日的 450→300)·主目标1.3A/路径其余0.8A物理+击飞0.8s·每敌10s冷却·无伤害递增
	# 〖用户2026-07-06〗"450码固定距离，最近，所以理想的效果就是他会连着滑几下，不用加递增"; 伤害取回合制 ninjaImpact(atkScale=1.3 / behindScale=0.8)
	u["_ninja_last_dash"] = battle._t
	var start: Vector2 = u["pos"]
	var dir: Vector2 = target["pos"] - start
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	# ★#5修〖用户2026-07-11〗: 亚索 E 式【滑行穿过】(非瞬移), 滑速 600 码/秒. 固定路径 300 码(同日 450→300).
	var endp: Vector2 = start + dir * 300.0                     # 冲刺距离 300码(用户2026-07-11: 450→300)
	endp.x = clampf(endp.x, battle.ARENA.position.x, battle.ARENA.end.x)
	endp.y = clampf(endp.y, battle.ARENA.position.y, battle.ARENA.end.y)
	# 路径上的敌 (按沿路投影排序 → 滑到谁割谁)
	var hits: Array = []
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if not battle._on_line(start, dir, o["pos"], 62.0): continue
		var proj: float = (o["pos"] - start).dot(dir)
		if proj < 0.0 or proj > 300.0: continue
		hits.append({"o": o, "proj": proj, "done": false})
	hits.sort_custom(func(a, b): return float(a["proj"]) < float(b["proj"]))
	battle._bolt_line(start, endp, Color(0.7, 0.95, 1.0, 0.5))         # 冲刺残影(淡)
	_ninja_glide(u, start, endp, dir, target, hits)            # 滑行(async, fire-and-forget)

## 忍者冲击滑行 (亚索 E 式 · 600 码/秒 · 穿过路径敌逐个割). no_move 期间分离跳过, 每帧直接推 pos.
func _ninja_glide(u: Dictionary, start: Vector2, endp: Vector2, dir: Vector2, target: Dictionary, hits: Array) -> void:
	var total: float = start.distance_to(endp)
	if total < 1.0:
		return
	var was_nm: bool = bool(u.get("no_move", false))
	var was_nb: bool = bool(u.get("no_basic", false))
	u["no_move"] = true
	u["no_basic"] = true
	u["_ninja_gliding"] = true                                 # 滑行中(含起手/落地)→触发器不再触发下一次冲刺(用户2026-07-11)
	var _nspr = u.get("sprite", null)
	var _ndsd = battle._resolve_action("pets/animations/ninja/dash.png", 16.0)   # 忍者冲刺动作。★真实表只有 7 帧(0~6) —— 帧号一律经 _nspr_last() 钳制, 别照旧注释的"5-8/9-11"写死(见下方 2026-08-07 那段)
	var _ndash: bool = (not _ndsd.is_empty()) and is_instance_valid(_nspr)
	if _ndash:
		u["_manual_anim"] = true                          # 手动逐帧(阻止_advance_anim自动推进)
		battle._set_anim_sheet(u, _ndsd, "dash", false)
		u["face_right"] = dir.x > 0.0                      # 朝滑行方向
		for _wf in range(4):                                # 起手 1-4帧
			if not u.get("alive", false): break
			if is_instance_valid(_nspr): _nspr.frame = _wf
			await battle._wait_sim(0.045)
			if not is_instance_valid(battle): return   ## await 回来 battle 可能已被 queue_free(战斗结束)
	var traveled = 0.0
	# ★冲击特效(用户2026-07-11): 角色前方一道疾风拖影伴随滑行(fx-trail·贴地朝行进方向·每帧跟随身前)
	var lead = Sprite3D.new()
	lead.texture = load("res://assets/sprites/vfx/fx-trail.png")
	lead.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	lead.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lead.axis = Vector3.AXIS_Y
	lead.shaded = false; lead.transparent = true
	lead.modulate = Color(0.72, 0.95, 1.0, 0.9)                # 疾风蓝白
	var _lt = float(maxi(1, int(lead.texture.get_width())))
	lead.pixel_size = (160.0 * battle.WS) / _lt
	lead.rotation.y = -atan2(dir.y, dir.x)                      # 朝行进方向
	lead.position = battle._world_pos(start + dir * 60.0, 1.0)
	battle._world.add_child(lead)
	while is_instance_valid(battle) and traveled < total and u.get("alive", false) and battle.is_inside_tree():
		await battle.get_tree().process_frame
		if not is_instance_valid(battle): return   ## ★await 期间战斗可能已结束(场景 queue_free), 回来必须重新确认
		traveled = minf(total, traveled + 600.0 * battle.get_process_delta_time())   # 恒速 600 码/秒
		u["pos"] = start + dir * traveled
		if is_instance_valid(lead): lead.position = battle._world_pos(u["pos"] + dir * 60.0, 1.0)   # 拖影跟在身前
		# ★★2026-08-07 修: 这里原来写死 `4 + (…% 4)` = 取第 4~7 帧, 落地那段写死 range(8, 11) = 第 8~10 帧,
		#   两处都按【≥11 帧的精灵表】算。而真实的忍者冲刺表只有 **7 帧(0~6)**
		#   ⇒ 每次冲刺都刷 `ERROR: Index p_frame = 7/8/9/10 is out of bounds (…= 7)`。
		#   注释写着"滑行 5-8帧""落地 9-11帧" —— **表换过、代码没跟上**, 而这条报错原先不在
		#   run-tests.sh 的 FATAL 正则里 ⇒ 一直红着没人看见(补了 `is out of bounds` 才暴露)。
		#   改成**按表的真实帧数钳制**: 表以后再换也不会越界。
		if _ndash and is_instance_valid(_nspr):
			_nspr.frame = mini(4 + (int(traveled / 45.0) % 4), _nspr_last(_nspr))
		for h in hits:
			if not h["done"] and traveled >= float(h["proj"]):
				h["done"] = true
				var o: Dictionary = h["o"]
				if o.get("alive", false):
					battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, 1.3 if is_same(o, target) else 0.8, o), Color("#9fe8ff"))
					battle._damage._knockback(u, o, 40.0, 1.468, 1.0)          # 击飞 0.8s 滞空
					if is_same(o, target): o["_ninja_dash_until"] = battle._t + 10.0          # 只有【目标】进10s冷却·顺路割到的不占(用户2026-07-11)
					battle._burst_vfx("res://assets/sprites/vfx/ninja-slash.png", o["pos"], 88.0, 1.0)
	u["pos"] = endp
	u["no_move"] = was_nm
	u["no_basic"] = was_nb
	if is_instance_valid(lead):                                # 冲刺结束→拖影淡出
		var _lw = battle._reg_tween()
		_lw.tween_property(lead, "modulate:a", 0.0, 0.14)
		_lw.tween_callback(lead.queue_free)
	battle._burst_vfx("res://assets/sprites/vfx/ninja-slash.png", u["pos"], 98.0, 1.0)   # 落点疾风斩弧
	if _ndash:
		# 落地三帧: 取表的最后三帧(原来写死 8/9/10, 越界; 理由见上面滑行那段的注释)
		# ★★2026-08-07 真根因(冒烟随机报 `p_frame = 16/17 out of bounds (…=7)` 追了很久):
		#   上限 `_nlast` 原来**在循环外算一次**(冲刺表 18 帧 ⇒ 17), 而循环里**有 await** ——
		#   忍者若在这三帧之间**阵亡**, 表会被换成 7 帧的 `ninja/death.png`,
		#   后续两次写就是 frame=16、17 打在 7 帧的表上。**两条连续报错正是这么来的。**
		#   ⇒ **每次写之前重新按精灵当前的 hframes×vframes 算上限**。
		#   通则: **跨 await 的帧号上限一律不能缓存** —— await 中间世界会变。
		for _step in [2, 1, 0]:
			if is_instance_valid(_nspr):
				var _lim: int = _nspr_last(_nspr)
				_nspr.frame = clampi(_lim - _step, 0, _lim)
			await battle._wait_sim(0.05)
			if not is_instance_valid(battle): return   ## await 回来 battle 可能已被 queue_free(战斗结束)
		u["_manual_anim"] = false
		if is_instance_valid(_nspr): battle._set_anim_sheet(u, u.get("idle_sd", {}), "", true)   # 回idle
	u["_ninja_gliding"] = false                               # 冲刺(含落地)结束→放开触发

func _sk_ninja_backstab(u: Dictionary, tgt: Dictionary) -> void: # 技三·背刺(1:1回合制 ninjaBackstab): +15穿甲5秒(用户2026-07-11: 5→15)→闪现到【全场最远敌】身后→背刺【3段·每段300ms(hitStaggerMs)】各0.6667A物理(共2.0A)→留该处追砍
	var far = null
	var fd = -1.0
	for o in battle._targeting._pick_enemies_of(u):   # ★单体定向(闪现到最远敌身后)走 battle._targeting._pick_enemies_of: 否则忍者会瞬移到场外训龟大师身后背刺(场外·永远最远); 见 §PICK-TARGET(用户2026-07-24)
		if not o.get("alive", false): continue
		var dd: float = u["pos"].distance_to(o["pos"])
		if dd > fd: fd = dd; far = o
	if far == null: far = tgt
	if far == null: return
	var from2d: Vector2 = u["pos"]
	u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 15.0       # +15穿甲(5秒后撤销·用户2026-07-11: 5→15)
	var uu: Dictionary = u
	battle._pending_shots.append({"delay": 5.0, "fn": func(): uu["armor_pen"] = float(uu.get("armor_pen", 0.0)) - 15.0, "src": u})
	battle._dash_to(u, far, -70.0)                                     # 闪现到最远敌身后
	u["face_right"] = far["pos"].x > u["pos"].x                # 面向最远敌(背刺sheet已镜像统一朝向)
	battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", from2d, u["pos"], 34.0, Color(0.8, 0.9, 1.0, 0.55), 0.28)   # 闪现刀光拖影(起点→落点)
	var asd = battle._resolve_action("pets/animations/ninja/backstab-rt.png", 16.0)   # 忍者背刺18帧全身动作(盖身上·播完回idle)
	if not asd.is_empty():
		battle._set_anim_sheet(u, asd, "backstab", false)                            # action="backstab"→_play_action 里挡普攻/受击换anim
		u["_anim_lock_until"] = battle._t + float(asd.get("frames", 18)) / 16.0 + 0.05   # 动作播完前锁出手/移动(用户2026-07-11「动作播完前不打断」)
	# 背刺三段: 每段 300ms 一刀(hitStaggerMs 300) 各 0.6667A 物理 + 斩弧, 目标死则跳过后续段
	var far2: Dictionary = far
	for i in range(3):
		battle._pending_shots.append({"delay": 0.30 * float(i), "src": u, "fn": func():
			if not u.get("alive", false) or not far2.get("alive", false):
				return
			battle._damage._apply_damage_from(u, far2, battle._atk_dmg(u, 0.6667, far2), Color("#cfd8e8"))
			battle._burst_vfx("res://assets/sprites/vfx/ninja-slash.png", far2["pos"], 88.0, 1.0)   # 每刀斩弧
			battle._vfx._hit_spark(far2)
		})

func _sk_ninja_shuriken(u: Dictionary, tgt) -> void:           # 技·手里剑(封板·远程·1:1回合制_ninja_shuriken): 掷旋转飞镖·命中1.6A物理; 暴击(按忍者暴击率)=暴击总伤拆两段→红物理(吃减甲)+白真伤(穿甲·占(40+2%/级)%), 同一发跳两个数字
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var base_dmg: float = float(u["atk"]) * 1.6               # 1.6A 基础(未减甲/未暴击)
	var is_crit: bool = battle._battle_rng.randf() < minf(float(u.get("crit", 0.0)), 1.0)   # 暴击=忍者自身暴击率(非固定概率)
	var phys_raw: float = base_dmg                            # 非暴击: 全物理一发
	var true_raw: float = 0.0
	if is_crit:
		var crit_mult: float = DamageMath.crit_multiplier(float(u.get("crit", 0.0)), float(u.get("crit_dmg", 1.5)))   # 暴击倍率(溢出100%每1%→1.5%·同_resolve_dmg)
		var crit_total: float = round(base_dmg * crit_mult)  # 暴击总伤(已乘暴击倍率)
		var lv: int = int(u.get("level", 1))
		true_raw = round(crit_total * minf(100.0, 40.0 + 2.0 * float(lv)) / 100.0)   # 其中(40+2%/级)%(封顶100%)→真实伤害(穿甲)
		phys_raw = maxf(0.0, crit_total - true_raw)           # 余下→物理(吃减甲)
	battle._ballistics._fire_shuriken(u, tgt, phys_raw, true_raw, is_crit)

func _sk_ninja_bomb(u: Dictionary, tgt) -> void:
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var opts = {"phys": 2.0, "defDown": 0.20, "color": Color("#ff9a3c")}   # 伤害2.0A(用户2026-07-11)·破甲25%→20%(用户2026-07-29 第五轮·龟能同时 100→120)
	var land: Vector2 = tgt["pos"]            # 落点 = 当前目标位置 (400码爆炸半径中心)
	battle._anticipate(u)                            # 短蓄力(掏炸弹)
	var spr = Sprite3D.new()
	spr.texture = load("res://assets/sprites/vfx/ninja-bomb.png")
	spr.hframes = 12                          # 768×64 = 12帧(球0-4→引信5-7→爆闪8→火球9→蘑菇云10-11); 球在帧内小·爆炸填满帧
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (150.0 * battle.WS) / 64.0      # 炸弹/爆炸尺寸(3D里过大会钻地)
	spr.position = battle._world_pos(u["pos"], 0.8)
	battle._world.add_child(spr)
	# 抛物线(3段弹跳)0.4s + 12帧动画1.2s播一次 (并行), 全播完(1.2s)销毁
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_bomb_arc.bind(spr, u["pos"], land), 0.0, 1.0, 0.4)
	tw.tween_method(_bomb_anim.bind(spr), 0.0, 12.0, 1.2)
	tw.chain().tween_callback(spr.queue_free)
	# 引爆 @0.8s: 震屏 + 400码冲击波环 + 半径伤害 (帧动画此刻正到爆炸帧8)
	var boom = battle._reg_tween()
	boom.tween_interval(0.8)
	boom.tween_callback(_bomb_explode.bind(spr, u, land, opts))

func _bomb_arc(pf: float, spr: Sprite3D, from2d: Vector2, to2d: Vector2) -> void:
	if not is_instance_valid(spr):
		return
	# 3段弹跳抛物线 (1:1 PoC ARC_PEAK -160/-55/-22 → 3D height); 水平线性推进; base 0.6=贴地飞(小炸弹球不钻地)
	var arc: float
	var sub: float
	if pf < 0.5:      sub = pf / 0.5;           arc = 2.6
	elif pf < 0.75:   sub = (pf - 0.5) / 0.25;  arc = 1.0
	elif pf < 0.95:   sub = (pf - 0.75) / 0.20; arc = 0.4
	else:             sub = 1.0;                arc = 0.0
	spr.position = battle._world_pos(from2d.lerp(to2d, pf), 0.6 + arc * 4.0 * sub * (1.0 - sub))

func _bomb_anim(fv: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		spr.frame = mini(11, int(fv))          # 12帧播一次(0→11 不循环·1:1 PoC repeat:0)

func _bomb_explode(spr, u: Dictionary, at2d: Vector2, opts: Dictionary) -> void:
	if is_instance_valid(spr):
		spr.position = battle._world_pos(at2d, 1.3)   # ★爆炸中心抬到贴地(大火球底边≈地面·防中心太低被地面挡=钻地)
	battle._shake(0.16)                               # 1:1 PoC cameras.shake(260)
	# ★400码爆炸范围可视: 扩张冲击波环到 battle.NINJA_BOMB_RADIUS + 内圈亮闪 → 看清波及范围
	battle._skill_ring(at2d, Color(1.0, 0.55, 0.2, 0.9), battle.NINJA_BOMB_RADIUS)
	battle._skill_ring(at2d, Color(1.0, 0.82, 0.4, 0.75), battle.NINJA_BOMB_RADIUS * 0.55)
	# 落点 400码内敌人: 先 -20%护甲(吃在这发上) 再 2.0A 物理; 圈外不受影响
	var col: Color = opts.get("color", Color("#ff9a3c"))
	var hit: Array = []
	for e in battle._targeting._enemies_of(u):
		if e != null and e.get("alive", false) and e["pos"].distance_to(at2d) <= battle.NINJA_BOMB_RADIUS:
			hit.append(e)
	for e in hit:
		battle._apply_skill_extras(u, e, opts)        # -20%护甲(defDown 0.20·BUFF_SEC=5秒)
		battle._skill_ring(e["pos"], Color(col.r, col.g, col.b, 0.5), 46.0)   # 每敌破甲小环
	for e in hit:
		if e.get("alive", false):
			var dmg = battle._atk_dmg(u, float(opts.get("phys", 2.0)), e, false)
			if dmg > 0:
				battle._damage._apply_damage_from(u, e, dmg, col)


## 某个 Sprite3D 精灵表的【最后一帧下标】。★不要写死帧号 ——
## 忍者冲刺表就因为"表从 11 帧换成 7 帧、代码没跟"每次冲刺刷 4 条越界报错,
## 而那条报错当时不在 FATAL 正则里, 红了很久没人看见。
static func _nspr_last(spr) -> int:
	if spr == null or not is_instance_valid(spr):
		return 0
	return maxi(0, int(spr.hframes) * int(spr.vframes) - 1)
