class_name HunterSystem
extends RefCounted
## 猎人龟技能系统
## 类内名不变;外部名加 battle.

## ★★2026-08-22 文案根除: 精准射击这一组原来是 `_sk_hunter_shot` / `_hunter_execute` 里的裸字面量。
const SHOT_ATK_COEF := 2.0       # 蓄力狙 ×ATK 物理
const SHOT_POISON_COEF := 0.5    # 中毒层数 = ×ATK
const SHOT_HEALCUT_PCT := 0.50   # 治疗削减比例
const SHOT_HEALCUT_SEC := 5.0    # 治疗削减持续(秒)
const MARK_SEC := 5.0            # 猎杀印记持续(秒)
const EXEC_MARKED := 0.24        # 有印记时的斩杀线
const EXEC_BASE := 0.14          # 无印记时的斩杀线
## 【狩猎弹幕】连珠速射, 每根随机锁敌、慢速抛物线追踪。
const BARRAGE_ARROWS := 10       # 共几根
const BARRAGE_GAP := 0.2         # 每几秒发一根
const BARRAGE_COEF := 0.36       # 每根 ×ATK 真实

## ★★2026-08-24 文案根除: 【隐蔽】翻滚距离原在函数内 `const ROLL`, 强化普攻的系数
## 更远 —— 在【主场景】的普攻分支里(消费点与生产点隔了一个文件)。
const ROLL_DIST := 250.0        # 智能翻滚距离(码)
const ROLL_ATK_COEF := 0.9      # 下次普攻附带 ×ATK 物理(吃生命偷取)
const ROLL_DODGE := 0.25        # 闪避
const ROLL_DODGE_SEC := 5.0     # 闪避持续(秒)
const ROLL_SHIELD_COEF := 0.7   # 护盾 = ×ATK

var battle

func _init(b) -> void:
	battle = b

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽(封板·薇恩Q Tumble·80龟能): 智能翻滚~250码→下次普攻附带0.9A物理(吃吸血)+25%闪避+0.7A护盾
	var dir = Vector2.RIGHT
	var nm = null
	var nmd = 150.0
	for o in battle._targeting._enemies_of(u):                                     # ① 近战/刺客贴近(<150码)→朝远离最近近战威胁滚(拉距保远程)
		if o.get("alive", false) and o.get("melee", false):
			var dd: float = u["pos"].distance_to(o["pos"])
			if dd < nmd: nmd = dd; nm = o
	if nm != null:
		dir = (u["pos"] - nm["pos"]).normalized()
	elif u["hp"] < u["maxHp"] * 0.35:                           # ② 残血→朝敌质心反向撤退
		var cen = Vector2.ZERO
		var cn = 0
		for o in battle._targeting._enemies_of(u):
			if o.get("alive", false): cen += o["pos"]; cn += 1
		if cn > 0: cen /= float(cn); dir = (u["pos"] - cen).normalized()
	else:                                                       # ③ 安全→朝当前目标最佳射程滚(目标<14%凑近确保处决,否则拉开保持射程)
		var tg = battle._targeting._nearest_enemy(u)
		if tg != null:
			if float(tg["hp"]) < float(tg["maxHp"]) * 0.14: dir = (tg["pos"] - u["pos"]).normalized()
			else: dir = (u["pos"] - tg["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var dest: Vector2 = _hunter_roll_best_dest(u["pos"], dir)   # 墙感翻滚: 贴墙沿墙滚/角落朝内滚(避免撞墙位移浪费·用户2026-07-14)
	var rdir: Vector2 = dir.normalized()
	if u["pos"].distance_to(dest) > 1.0: rdir = (dest - u["pos"]).normalized()
	battle._skill_ring(u["pos"], Color(0.45, 1.0, 0.68, 0.6), 60.0)                       # 起手灵巧绿环(闪避激活)
	battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", u["pos"], 175.0, 0.12)  # 起跳轻尘
	u["_roll_dest"] = dest                                       # 进入平滑翻滚滑行态(真位移·非瞬移·由_hunter_roll_tick逐帧驱动)
	u["_roll_dir"] = rdir
	u["_roll_ghost_t"] = 0.0
	u["hunter_roll_active"] = true
	u["hunter_roll_buff"] = true                                # 下次普攻附带0.9A物理(吃吸血)
	battle._damage._buff(u, "dodge", ROLL_DODGE, true, ROLL_DODGE_SEC)                          # 25%闪避5秒
	battle._damage._grant_shield(u, u["atk"] * ROLL_SHIELD_COEF)                            # 0.7A护盾

func _hunter_roll_best_dest(from2d: Vector2, pref_dir: Vector2) -> Vector2:
	# 墙感智能翻滚落点(用户2026-07-14"被逼到边界/角落怎么翻滚"): 意图方向撞墙时改沿墙/朝内翻滚,
	# 保证每次翻滚都有真实位移(不被clamp吃掉)。360°采样候选→按(实际位移 + 与意图对齐度)打分选最优。
	if pref_dir.length() < 0.1: pref_dir = Vector2.RIGHT
	pref_dir = pref_dir.normalized()
	const ROLL := ROLL_DIST
	const ALIGN_W := 90.0              # 对齐权重: 开阔时优先意图方向; 撞墙时"实际位移"主导→自动沿墙/朝内
	var pad = 40.0                    # 离墙内缩(不贴死边线)
	var xlo = battle.ARENA.position.x + pad; var xhi = battle.ARENA.end.x - pad
	var ylo = battle.ARENA.position.y + pad; var yhi = battle.ARENA.end.y - pad
	var best = from2d
	var best_score = -1.0e9
	for deg in [0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180]:
		var d: Vector2 = pref_dir.rotated(deg_to_rad(float(deg)))
		var raw: Vector2 = from2d + d * ROLL
		var cl = Vector2(clampf(raw.x, xlo, xhi), clampf(raw.y, ylo, yhi))
		var reached: float = cl.distance_to(from2d)          # clamp后真实位移(贴墙方向→接近0)
		var align = 0.0
		if reached > 1.0: align = (cl - from2d).normalized().dot(pref_dir)   # 落点方向与意图的一致度[-1,1]
		var score: float = reached + ALIGN_W * align
		if score > best_score:
			best_score = score; best = cl
	return best

func _hunter_roll_tick(u: Dictionary, delta: float) -> void:
	# 平滑翻滚滑行(逐帧真位移·薇恩Q式·覆盖正常AI): 沿_roll_dir冲到_roll_dest, 逐帧铺灵巧绿幻影拖尾, 到点落地轻尘
	var dest: Vector2 = u.get("_roll_dest", u["pos"])
	var rdir: Vector2 = u.get("_roll_dir", Vector2.RIGHT)
	var step: float = battle.HUNTER_ROLL_SPD * delta
	u["_roll_ghost_t"] = float(u.get("_roll_ghost_t", 0.0)) + delta
	if float(u["_roll_ghost_t"]) >= 0.028:                       # 逐帧铺绿幻影(节流·真motion blur拖尾)
		u["_roll_ghost_t"] = 0.0
		_hunter_roll_ghost(u)
	u["face_right"] = rdir.x > 0.0
	var to_d: Vector2 = dest - u["pos"]
	if to_d.length() <= step + 2.0 or to_d.dot(rdir) <= 0.0:     # 到达/穿过 → 落地结算
		u["pos"] = dest
		u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)
		u["hunter_roll_active"] = false
		u["state"] = "move"
		battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", u["pos"], 200.0, 0.12)   # 落地轻尘
		return
	u["pos"] += rdir * step                                      # 固定速真位移(平滑滑行·非瞬移)
	u["pos"].x = clampf(u["pos"].x, battle.ARENA.position.x, battle.ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, battle.ARENA.position.y, battle.ARENA.end.y)

func _hunter_roll_ghost(u: Dictionary) -> void:                 # 单道灵巧绿立绘幻影(在当前位铺·淡出=翻滚拖尾)
	var spr = u.get("sprite", null)
	if not (is_instance_valid(spr) and spr.texture != null): return
	var g = Sprite3D.new()
	g.texture = spr.texture
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	# ★先归零再改帧网格(这一族的统一写法): setter 会立即用新乘积校验当前 frame,
	#   设 hframes 那一瞬 vframes 还是 1 ⇒ 乘积可能远小于要复制过来的 frame。
	g.frame = 0
	g.hframes = spr.hframes; g.vframes = spr.vframes
	g.frame = clampi(int(spr.frame), 0, maxi(0, int(g.hframes) * int(g.vframes) - 1))
	g.flip_h = spr.flip_h
	g.pixel_size = spr.pixel_size
	g.offset = spr.offset
	g.position = battle._world_pos(u["pos"], float(u.get("height", 0.0)))
	g.modulate = Color(0.35, 1.0, 0.6, 0.5)
	battle._world.add_child(g)
	var tw = battle._reg_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.28)
	tw.tween_callback(g.queue_free)

# ============================================================================
#  统一头顶信息层调度 (用户2026-07-15): 每单位每帧收集激活的头顶2D标记→分带→以头顶为中心对称横排
#  · 归类: 状态图标行(瞬时态·纯图标·猎杀/未来眩晕嘲讽沉默诅咒) + 叠层计数行(持续·图标+数字·墨迹/电击/未来岩层怒气)
#  · 定位: 锚到血条同一世界点(head+bar_head_h·大单位自动抬高)→unproject拿角色头顶真实屏幕位→行内以此为中心对称铺开(单个正中·不左右偏·随角色)
#  · 防重叠: 两带固定竖直分带; 行内固定间距; 超上限截断
#  · 3D环绕类(眩晕火花/诅咒骷髅/忍者锁定)保持绕身体另一套, 不进此层
# ============================================================================
func _sk_hunter_shot(u: Dictionary, tgt) -> void:              # 猎人龟·精准射击(封板·90龟能·射箭+毒箭+猎杀印记三合一): 蓄力狙2.0A物理+中毒5s+治疗削减50%5s+猎杀印记5s(<24%处决)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var tref: Dictionary = tgt
	var uu: Dictionary = u
	# ① 瞄准蓄力(0.4s): 细红瞄准线 + 猎人蓄力红光
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], tref["pos"], 6.0, Color(1.0, 0.35, 0.2, 0.4), 0.4, 1.0)
	battle._gambler_sys._gambler_pop(u["pos"], float(u.get("height", 0.0)) + 0.5, Color(1.0, 0.45, 0.2, 0.7))   # 蓄力红光(复用通用glow pop)
	# ② 0.4s后开火: 金色狙击曳光 → 到位(0.16s)才结算伤害+毒+印记+爆(命中才跳伤害)
	battle._pending_shots.append({"delay": 0.4, "fn": func() -> void:
		if not uu.get("alive", false) or not tref.get("alive", false): return
		var tp: Vector2 = tref["pos"]
		battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], tp, 18.0, Color(1.0, 0.9, 0.45, 0.9), 0.18, 1.0)   # 金色狙击曳光(粗亮快)
		battle._shake(0.06)
		battle._pending_shots.append({"delay": 0.16, "fn": func() -> void:
			if not tref.get("alive", false): return
			battle._damage._apply_damage_from(uu, tref, battle._atk_dmg(uu, SHOT_ATK_COEF, tref), Color("#ff4444"))   # 物理红(2.0A物理狙击·飘字色规范)
			battle._damage._apply_dot_stacks(tref, "poison", maxi(1, int(round(uu["atk"] * SHOT_POISON_COEF))), uu)   # 中毒5s
			tref["heal_reduce_until"] = battle._t + SHOT_HEALCUT_SEC                         # 治疗削减50%·5秒
			tref["heal_reduce_pct"] = maxf(float(tref.get("heal_reduce_pct", 0.0)), SHOT_HEALCUT_PCT)
			tref["hunt_mark_until"] = battle._t + MARK_SEC                           # 猎杀印记5秒: <24%即处决(头顶状态图标行贴十字准星·_layout_head_badges·不用文字)
			battle._skill_ring(tref["pos"], Color(0.5, 0.9, 0.2, 0.6), 40.0)   # 命中毒绿环(小·非大绿球)
			for _pb in range(4): battle._spawn_poison_bubble(tref)             # 命中即冒一簇毒泡
			battle._shake(battle.JUICE_SHAKE_HEAVY)
			, "src": uu})
		, "src": u})

func _sk_hunter_barrage(u: Dictionary, _tgt) -> void:          # 猎人龟·狩猎弹幕(封板·100龟能): 10箭·每0.2s一发·随机目标(注意龟蛋)·慢速抛物线追踪·箭头随角度·命中才跳0.36A真实(共3.6A)·每箭<14%即处决(用户2026-07-14重做)
	for i in range(BARRAGE_ARROWS):
		var uu: Dictionary = u
		battle._pending_shots.append({"delay": float(i) * BARRAGE_GAP, "src": u, "fn": func() -> void:   # 每0.2s射一发
			if not uu.get("alive", false): return
			var cand: Array = []                                # 随机目标(非最残血): _enemies_of已跳围栏未破的蛋; 破栏后的蛋是合法目标(注意龟蛋)
			for o in battle._targeting._pick_enemies_of(uu):
				if o.get("alive", false) and not battle._is_untargetable(o):
					cand.append(o)
			if cand.is_empty(): return
			var tgt: Dictionary = cand[battle._battle_rng.randi() % cand.size()]   # 随机选一个敌
			battle._ballistics._fire_hunter_arrow(uu, tgt, int(round(float(uu["atk"]) * BARRAGE_COEF)))   # 每箭0.36A(共3.6A)
			})

func _hunter_execute_fx(u: Dictionary) -> void:   # 被动猎杀·处决瞬间: 金色斩杀爆(环+金光pop+轻震)·配"处决!"金字(用户2026-07-14)
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.7), 56.0)
	battle._gambler_sys._gambler_pop(u["pos"], float(u.get("height", 0.0)) + 0.5, Color(1.0, 0.86, 0.3, 0.85))
	battle._shake(0.05)

func _hunter_apply_steal(killer: Dictionary, victim: Dictionary) -> void:   # 被动猎杀·窃取结算: 偷14%攻/防/魔抗/最大生命+叠8%吸血(永久累积到战斗结束)+金色精华VFX
	if killer == null or not killer.get("alive", false) or killer.get("id", "") != "hunter": return
	killer["base_atk"] += float(victim["base_atk"]) * 0.14
	killer["base_def"] += float(victim["base_def"]) * 0.14   # 窃取: 护甲/魔抗/最大生命也偷14%
	killer["base_mr"] += float(victim["base_mr"]) * 0.14
	var hs: float = float(victim["maxHp"]) * 0.14
	killer["maxHp"] += hs; killer["hp"] += hs
	killer["lifesteal"] += 0.08
	battle._recalc_stats(killer)
	_hunter_steal_fx(killer, victim["pos"])

func _hunter_steal_fx(killer: Dictionary, from2d: Vector2) -> void:   # 被动猎杀·窃取: 金色精华从死者流向猎人 + "掠夺!"金字 + 猎人金光环(累积变强可视化·用户2026-07-14)
	if not killer.get("alive", false): return
	var kp: Vector2 = killer["pos"]
	for k in range(3):
		var off = Vector2(randf_range(-18.0, 18.0), randf_range(-14.0, 14.0))
		var mote = battle._glow_bb(from2d + off, 0.9, 24.0, Color(1.0, 0.83, 0.28, 0.95))
		var tw = battle._reg_tween()
		tw.tween_interval(float(k) * 0.07)
		var mv = tw.tween_property(mote, "position", battle._world_pos(kp, 1.1), 0.45)
		mv.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mote, "scale", Vector3(0.4, 0.4, 0.4), 0.45)
		tw.chain().tween_callback(mote.queue_free)
	battle._vfx._float_text(kp + Vector2(0, -66), "掠夺!", Color("#ffd700"))
	battle._skill_ring(kp, Color(1.0, 0.84, 0.2, 0.55), 46.0)

## 单位当前是否【不可被选中/锁定】。
##
## ★2026-07-19 修真bug: 原先四处写的是 `o.get("_untargetable", false)` —— 那是个【幽灵字段】,
## 全项目从来没有任何地方给它赋过值(只在回合制遗留的 damage.gd 注释里出现过),
## 所以那四处判定【恒为 false, 保护不了任何东西】。真正生效的字段是 `untargetable_until`(时间戳),
## 由 黑洞 / 滞空 / 熔岩腾空 / 赛博机甲组装 等设置。
## 后果(用户2026-07-19 实测报告「机甲变身时被猎人龟直接处决」): 组装期机甲血量从 1% 往上爬,
## 正卡在 14% 处决线下, 猎人每 0.1s 扫场 → 射处决箭 → `_hunter_exec_arrow_hit` 直接 hp=0 + battle._kill,
## 完全绕过 `battle._damage._apply_damage_from` 里的 `_assembling` 免疫闸。黑洞中/滞空中的单位同样能被处决。
func _hunter_exec_arrow_hit(src, tgt) -> void:   # 强化箭命中: 目标仍<斩杀线且非免疫→处决+窃取(demo靶不真死复位)
	if tgt == null or not tgt.get("alive", false): return
	tgt["_hunt_exec_pending"] = false
	if tgt.get("egg", false) or tgt.get("_eggImmune", false) or tgt.get("eq_exec_immune", false) or battle._is_untargetable(tgt):   # 免疫处决: 蛋/不沉之锚/不可选(含机甲组装期) → 命中但不斩
		battle._vfx._hit_spark(tgt); return
	var thr: float = EXEC_MARKED if battle._t < float(tgt.get("hunt_mark_until", 0.0)) else EXEC_BASE
	if float(tgt["hp"]) >= float(tgt["maxHp"]) * thr:   # 飞行途中被治疗回到斩杀线上→不处决(仅命中火花)
		battle._vfx._hit_spark(tgt); return
	if tgt.get("_hunt_demo_victim", false):   # 被动demo靶: 处决→窃取+复位残血(循环看·在deathfloor判前, demo也带deathfloor)
		_hunter_execute_fx(tgt)
		battle._vfx._float_text(tgt["pos"] + Vector2(0, -40), "处决!", Color("#ffd700"))
		_hunter_apply_steal(src, tgt)
		tgt["hp"] = float(tgt["maxHp"]) * 0.12
		return
	if float(tgt.get("deathfloor_until", 0.0)) > battle._t:   # 临时免死(亡灵等)→免疫处决(命中但不斩)
		battle._vfx._hit_spark(tgt); return
	_hunter_execute_fx(tgt)
	battle._vfx._float_text(tgt["pos"] + Vector2(0, -40), "处决!", Color("#ffd700"))
	tgt["hp"] = 0.0
	battle._kill(tgt, src)
