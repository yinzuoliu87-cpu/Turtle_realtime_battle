class_name SpiritSynergySystem
extends RefCounted
## 灵物羁绊【触手 / 闪避追击 / 亡灵】（2026-08-03）
##
## 来源：学派「无头议会」（触手）+「亡灵」（`docs/archive/学派效果-实装规格.md`）。
## 类型原生属性是 `dodgePct`（每件 +5/9/13/18% 闪避率，硬上限 75% 钳在 `_recalc_stats`）。
##
## ── 三条的作用域 ─────────────────────────────────────────────────────
## | 触手     | **队伍**（1/2/2/2 个，属于整支队伍，不属于某只龟）|
## | 闪避追击 | **队伍**（任何人闪避成功都触发，共用同一个每周期上限）|
## | 亡灵     | **队伍**（任何友方单位阵亡都召唤）                |
##
## ══════════════════════════════════════════════════════════════════════
##  ★触手做成【逻辑实体】，和枪的炮台同一套做法
## ══════════════════════════════════════════════════════════════════════
## 原文写的是「**无敌**触手」—— 无敌 = 没有血量、不会被摧毁、不参与选靶。
## 那它就不需要"单位"的任何东西（生成 / 阵亡 / 换路重建 / 被打 / 被治疗），
## 只需要"一个位置 + 一个计时器"。⇒ 本文件里的几个 float 就是全部实现。
## 表现走现成的特效函数（`_bolt_line`），玩家看到的东西一样。
##
## ⚠ 亡魂**不是**逻辑实体 —— 它要被打、要死、要循环，是真的召唤单位（走 `_spawn_summon`）。

var battle

## 拍击周期。★用户 2026-08-04 定为 **5 秒**（原 2.5）——
##   触手是常驻 AOE，2.5 秒一次在 6 只对 6 只的场面上刷得太密。
const SLAP_PERIOD := 5.0
## 闪避追击的**次数窗口**仍是 2.5 秒（规格原文），**不跟着拍击周期走** ——
## 共用一个计时器的话，追击上限就被动砍半了，而那不是用户改的那件事。
## （同枪的两座炮台各走各的节拍。）
const CHASE_WINDOW := 2.5
## 触手数量（逐档）
const TENTACLES := [1, 2, 2, 2]
## 拍击伤害 = 目标最大生命 × HIT_HP_PCT + HIT_FLAT，再乘档位系数
const HIT_HP_PCT := 0.04
const HIT_FLAT := 55.0
const HIT_MULT := [1.0, 1.0, 1.30, 1.60]
## 伤害带半宽（码）。★用户 2026-08-05 拍板 ×3（40→120）。
## ⚠ 必须与 `tentacle_vfx.WARN_HALF_W` 相等 —— 一个是打的范围、一个是画给玩家看的预警区。
const HIT_HALF_W := 120.0

## 【闪避追击】追击伤害占拍击的比例 + 每 2.5 秒的次数上限（档1 无）
const CHASE_SHARE := 0.25
const CHASE_CAP := [0, 3, 3, 5]
## 【亡灵】亡魂继承阵亡者的属性比例（逐档）
const WRAITH_INHERIT := [0.20, 0.38, 0.65, 1.00]
## 亡魂阵亡后还能再循环几次（逐档），每次属性 ×0.9
const WRAITH_LOOPS := [0, 1, 2, 3]
const WRAITH_DECAY := 0.9

## 【转移阵地】每根触手"射程内无敌人"已持续多久（key = "side|idx"）。
## 用户 2026-08-04：「触手攻击范围内没有敌人持续一秒后，触手会钻入地下消失，
##   然后从可攻击的目标附近再重新破土而出」。
const RELOC_IDLE_T := 1.0            # 空转多久开始搬家
const RELOC_NEAR := 0.70             # 搬到"距目标 0.70×射程"处（留出余量，别贴脸）
var _dry: Dictionary = {}

var _t_slap := 0.0
var _t_chase := 0.0
## 各方本周期已用掉的追击次数
var _chase_used := {"left": 0, "right": 0}


func _init(b) -> void:
	battle = b


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "灵物")))
	return t


## 触手的位置（逻辑实体，只是一个坐标）。idx 0/1 分列上下。
## ★★2026-08-04：这里原来是 `TentacleVfx.root_pos` 的**手抄副本**（同一条公式写两遍）。
##   手抄的副本必然落后（memory [[fb-hand-rolled-copies-drift]]）—— 这一轮为了让两根
##   触手在攻击时**收敛成 V 形**要挪根部位置，一改就是两处，漏一处就变成
##   「伤害沿 A 线结算、演出画在 B 线」。⇒ 改成直接问演出侧要坐标，只留一份公式。
func tentacle_pos(side: String, idx: int) -> Vector2:
	return battle._tentacle_vfx.root_pos(side, idx)


func tick(delta: float) -> void:
	# ★每帧让场上的触手数量 == 本档位应有的数量（多了撤场、少了出土）。
	#   文案写的是「N 个无敌触手【登场】」——"登场"意味着它在场上；
	#   不常驻的话玩家永远读不到这四个字（用户 2026-08-04 指出的正是这件事：
	#   「整个触手在这个羁绊里是什么流程」）。
	for sd in ["left", "right"]:
		var tt: int = _side_tier(str(sd))
		battle._tentacle_vfx.ensure(str(sd), TENTACLES[clampi(tt - 1, 0, 3)] if tt > 0 else 0)
	# 追击次数窗口(2.5 秒)与拍击周期(5 秒)【各走各的】
	_t_chase += delta
	if _t_chase >= CHASE_WINDOW:
		_t_chase -= CHASE_WINDOW
		_chase_used = {"left": 0, "right": 0}
	_reloc_tick(delta)
	_t_slap += delta
	if _t_slap < SLAP_PERIOD:
		return
	_t_slap -= SLAP_PERIOD
	for side in ["left", "right"]:
		var s: String = str(side)
		var ti: int = _side_tier(s)
		if ti <= 0:
			continue
		for i in range(TENTACLES[clampi(ti - 1, 0, 3)]):
			_slap(s, i, 1.0)


## 【转移阵地】每帧看每根触手射程内有没有敌人；连续 `RELOC_IDLE_T` 秒没有 → 搬家。
## ★这条以前**写了 `relocate()` 但零调用者** —— 典型的"写进去了没人读"
##   （memory [[fb-write-without-reader-and-fake-gates]]）。现在接上。
func _reloc_tick(delta: float) -> void:
	var tv = battle._tentacle_vfx
	var rng: float = float(tv.attack_range_2d)
	for side in ["left", "right"]:
		var s2: String = str(side)
		var ti: int = _side_tier(s2)
		if ti <= 0:
			continue
		# 本方能打的敌人（活着的对方单位）
		var foes: Array = []
		for u in battle._units:
			if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) != s2:
				foes.append(u)
		for i in range(TENTACLES[clampi(ti - 1, 0, 3)]):
			var k: String = "%s|%d" % [s2, i]
			if tv.state_of(s2, i) != 1:          # 只有【待机】中的才考虑搬家
				_dry[k] = 0.0
				continue
			var origin: Vector2 = tv.root_pos(s2, i)
			var has_target := false
			for f in foes:
				if origin.distance_squared_to(Vector2(f["pos"])) <= rng * rng:
					has_target = true
					break
			if has_target:
				_dry[k] = 0.0
				continue
			_dry[k] = float(_dry.get(k, 0.0)) + delta
			if float(_dry[k]) < RELOC_IDLE_T:
				continue
			_dry[k] = 0.0
			# 搬到"离最近的敌人 0.70×射程"处，方向朝我方一侧（不贴脸）
			var best = null
			var bd := INF
			for f in foes:
				var d: float = origin.distance_squared_to(Vector2(f["pos"]))
				if d < bd:
					bd = d; best = f
			if best == null:
				continue                          # 全场没敌人了，别瞎搬
			var fp: Vector2 = Vector2(best["pos"])
			var back: Vector2 = (origin - fp)
			if back.length() < 1.0:
				back = Vector2.LEFT if s2 == "left" else Vector2.RIGHT
			var to2: Vector2 = fp + back.normalized() * (rng * RELOC_NEAR)
			to2.x = clampf(to2.x, battle.ARENA.position.x + 40.0,
				battle.ARENA.position.x + battle.ARENA.size.x - 40.0)
			to2.y = clampf(to2.y, battle.ARENA.position.y + 40.0,
				battle.ARENA.position.y + battle.ARENA.size.y - 40.0)
			tv.relocate(s2, i, to2)


## 一次拍击：朝一名敌人拍下去，**沿途**（触手↔目标直线上）的敌人都吃伤害。
## share = 伤害比例（正常拍击 1.0，闪避追击 0.25）。返回打中了几个。
func _slap(side: String, idx: int, share: float) -> int:
	var ti: int = _side_tier(side)
	if ti <= 0:
		return 0
	var origin: Vector2 = tentacle_pos(side, idx)
	var foes: Array = []
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) != side:
			foes.append(u)
	if foes.is_empty():
		return 0
	# ★确定性选取: 最近的那个(同炮台/收殓的规矩)
	# ⚠ 且**必须在触手的固定射程内** —— 用户 2026-08-04:「俄洛伊触手的攻击长度是固定的」。
	#   固定长度意味着有明确的攻击范围；范围外的敌人不该被选中(否则演出伸不到、
	#   或者为了够到而拉长，两种都会让"安全距离"这条规则失效)。
	var rng: float = float(battle._tentacle_vfx.attack_range_2d)
	var aim = null
	var best := INF
	for f in foes:
		var d: float = origin.distance_squared_to(Vector2(f["pos"]))
		if d > rng * rng:
			continue                      # 射程外
		if d < best:
			best = d
			aim = f
	if aim == null:
		return 0
	var dir: Vector2 = Vector2(aim["pos"]) - origin
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var mult: float = HIT_MULT[clampi(ti - 1, 0, 3)] * share
	## ══════════════════════════════════════════════════════════════
	##  ★★演出先起、伤害后到（用户 2026-08-10 拍板【方案 A】）
	## ══════════════════════════════════════════════════════════════
	## 改之前这里是【先把伤害全打完, 再调 strike() 起演出】, 而正常拍击要走
	## 预警 1.00s → 前摇 0.13s → ST_SLAM 第一帧爆闪 ⇒ **伤害比视觉命中早 1.13 秒**。
	## 用户:「什么时候算命中, 是拍下去打到目标啊」。
	##
	## 现在:
	##   · **方向与带子在 t=0 定死**(origin/dir/rng 都已算好, 下面不再动) ——
	##     预警画的就是它, 一变就成骗人;
	##   · **吃伤害的名单在【视觉命中那一刻】重算** —— 谁那时候站在带子里就打谁,
	##     所以"看到预警走开"真的有用。这是方案 A 与方案 B 的唯一区别。
	## ⚠ 代价: 触手会变弱(1.13 秒足够走出 107~136 码, 而带子半宽只有 120)。
	##   这是**有意的平衡改动**, 不是副作用。
	battle._tentacle_vfx.strike(side, idx, Vector2(aim["pos"]), share)
	var _serial: int = battle._tentacle_vfx.strike_serial(side, idx)
	var _delay: float = battle._tentacle_vfx.hit_delay(share)
	if _delay <= 0.0:
		# 闪避追击走点刺, 视觉命中就在第 0 帧 ⇒ 立即结算(它本来就是对的)
		return _slap_resolve(side, origin, dir, rng, mult)
	## ★走 `_queue_shots` 而不是 tween: 它按**钳制后的 sim delta** 推进、尊重时停,
	##   且换路时 `dual_lane_flow` 会 `_pending_shots.clear()` ⇒ 无跨路残留。
	battle._queue_shots(1, 0.0, func() -> void:
		## 期间可能被撤回/搬家/被新指令覆盖 —— 那时候不该再出伤
		if not battle._tentacle_vfx.is_striking(side, idx, _serial):
			return
		_slap_resolve(side, origin, dir, rng, mult), null, "", Callable(), _delay)
	## 返回的是**按 t=0 站位预计会打中几个** —— 真实命中数要等 `_delay` 之后才知道。
	return _band_foes(side, origin, dir, rng).size()


## 伤害带里的敌人（带子由 origin/dir/rng 定死，半宽 HIT_HALF_W）。
## ★抽出来是因为它要被调用两次：t=0 预计一次、命中那一刻真算一次。
##   就地各写一遍 = 抄一次永远落后一次（memory [[fb-hand-rolled-copies-drift]]）。
func _band_foes(side: String, origin: Vector2, dir: Vector2, rng: float) -> Array:
	var out: Array = []
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if str(u.get("side", "")) == side:
			continue
		var rel: Vector2 = Vector2(u["pos"]) - origin
		var along: float = rel.dot(dir)
		# ★★2026-08-05 补的长度上限：原来只排除"在身后"，没有长度限制 ⇒
		#   伤害带是【向前无限延伸】的半平面，触手够不到的敌人照样挨打
		#   (探针实测: 640 码外的敌人被打掉 48065)。
		if along < 0.0 or along > rng:
			continue
		# ★★半宽 120（用户 2026-08-05 拍板 ×3）。
		#   ⚠ 必须与 `tentacle_vfx.WARN_HALF_W` 一致 —— 那是画给玩家看的预警区，
		#     两者不等 = 打得到却不画(骗玩家) 或 画了打不到(白吓唬)。
		#     `verify_spirit_slap_range` ⑤b 焊着这一条。
		if absf(rel.cross(dir)) > HIT_HALF_W:
			continue
		out.append(u)
	return out


## 真正结算一次拍击的伤害。返回打中了几个。
func _slap_resolve(side: String, origin: Vector2, dir: Vector2, rng: float, mult: float) -> int:
	var shooter = _any_carrier(side)
	var hits := 0
	for f in _band_foes(side, origin, dir, rng):
		var dmg: int = maxi(1, int((float(f.get("maxHp", 0.0)) * HIT_HP_PCT + HIT_FLAT) * mult))
		if shooter is Dictionary:
			battle._damage._apply_damage_from(shooter, f, dmg, Color("#b388ff"))
		else:
			battle._damage._apply_damage(f, dmg, Color("#b388ff"))
		hits += 1
	return hits


## 【闪避追击】某只单位闪避成功时调（挂 `_eq_on_dodge` 旁边）。
## ★次数上限是**整支队伍共用**的，不是每只各 3 次 —— 否则 6 只全闪 = 18 次追击。
func on_dodge(u) -> void:
	if not (u is Dictionary):
		return
	var side: String = str((u as Dictionary).get("side", ""))
	var ti: int = _side_tier(side)
	if ti <= 0:
		return
	var cap: int = CHASE_CAP[clampi(ti - 1, 0, 3)]
	if cap <= 0:
		return
	if int(_chase_used.get(side, 0)) >= cap:
		return
	_chase_used[side] = int(_chase_used.get(side, 0)) + 1
	_slap(side, 0, CHASE_SHARE)


## 【亡灵】友方单位阵亡 → 原地召唤 1 只亡魂，继承其 N% 攻击力与生命。
## 挂 `_kill`（与盾的收殓、药水的猎获同一处）。
##
## ★三道闸，缺一个都会出事：
##   ① **亡魂自己死了不能再召唤新亡魂** —— 否则是无限循环。用 `_wraith_loops` 计数。
##   ② **龟蛋不召唤** —— 龟蛋是胜负判定的容器，它死了这一路就结束了。
##   ③ **召唤物阵亡不召唤**（除了亡魂自己的循环）—— 否则别的召唤物死也能刷亡魂。
func on_death(dead) -> void:
	if not (dead is Dictionary):
		return
	if dead.get("_isEgg", false):
		return
	var side: String = str(dead.get("side", ""))
	var ti: int = _side_tier(side)
	if ti <= 0:
		return
	var inherit: float = WRAITH_INHERIT[clampi(ti - 1, 0, 3)]
	var loops_left: int = WRAITH_LOOPS[clampi(ti - 1, 0, 3)]
	if dead.get("_is_wraith", false):
		# 亡魂自己死了: 还有循环次数就再生一只(属性 ×0.9), 没有就到此为止
		loops_left = int(dead.get("_wraith_loops", 0)) - 1
		if loops_left < 0:
			return
		inherit = float(dead.get("_wraith_inherit", 0.0)) * WRAITH_DECAY
	elif dead.get("summon_kind", "") != "":
		return          # 别的召唤物阵亡不生亡魂
	if inherit <= 0.0:
		return
	var hp: float = float(dead.get("maxHp", 0.0)) * inherit
	var atk: float = float(dead.get("base_atk", dead.get("atk", 0.0))) * inherit
	if hp < 1.0 or atk < 1.0:
		return
	var w = battle._spawn._spawn_summon(dead, "wraith", hp, atk, {"col_size": 20.0})
	if w is Dictionary:
		w["_is_wraith"] = true
		w["_wraith_loops"] = loops_left
		w["_wraith_inherit"] = inherit
		w["pos"] = Vector2(dead["pos"])        # 原地(_spawn_summon 会随机抖一点, 亡灵要求"原地")


## 找一个该阵营带灵物的单位当"施术者" —— 伤害要归属到某个单位，否则统计与击杀归属缺一块。
func _any_carrier(side: String):
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side:
			continue
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == "灵物":
				return u
	return null


func clear() -> void:
	_t_slap = 0.0
	_t_chase = 0.0
	_dry.clear()
	_chase_used = {"left": 0, "right": 0}
