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
## 触手数量（逐档）
const TENTACLES := [1, 2, 2, 2]
## 拍击伤害 = 目标最大生命 × HIT_HP_PCT + HIT_FLAT，再乘档位系数。
## ★用户 2026-08-20 拍板:「拍击伤害为目标5%最大生命值+100物理伤害」
##   +「8件这里改为使拍击伤害提升50%」「10件这里使拍击伤害提升100%」
##   (原 4% + 55 / [1,1,1.30,1.60])。100 是**固定基础值**, 缩放全交给档位系数 ——
##   用户原话「固定100，但我后面有说整体伤害会随档位怎么提升」。
const HIT_HP_PCT := 0.05
const HIT_FLAT := 100.0
const HIT_MULT := [1.0, 1.0, 1.50, 2.00]
## 伤害带半宽（码）。★用户 2026-08-05 拍板 ×3（40→120）。
## ⚠ 必须与 `tentacle_vfx.WARN_HALF_W` 相等 —— 一个是打的范围、一个是画给玩家看的预警区。
const HIT_HALF_W := 120.0

## 【闪避蓄能】★2026-08-20 用户改机制:「5件的时候友方有闪避成功时触手会获得一层拍击层数。
##   拍击现在造成完整伤害。不再有2.5秒的限制」
##   ⇒ 原来的「立刻打 25 折追击 + 每 2.5 秒最多 N 次」整组删掉(
##   `CHASE_SHARE 0.25` / `CHASE_CAP [0,3,3,5]` / `CHASE_WINDOW 2.5`)。
##   闪避改成 **+1 层拍击层数**, 走与周期产层同一条消费管线 ⇒ 完整伤害、有预警、无次数上限。
## 闪避从第几档开始给层(用户:「应该5层以上吧」= 羁绊 5 件及以上, 2 件不给)
const DODGE_STACK_MIN_TIER := 2
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
## 【拍击层数】key = "side|idx" —— **每根触手各自一份**(用户 2026-08-20 拍板)。
## 无上限(用户:「无上限」)。产层: 每 SLAP_PERIOD 秒 +1; 闪避成功再 +1(5 件起)。
var _stacks: Dictionary = {}
## 拍击结算账本(探针): queued=排了几次延时结算 / dropped=被 is_striking 闸门丢掉
## / resolved=真跑了结算 / zero_hit=跑了但一个都没打到。用户 2026-08-22:
## 「有的时候触手打中没任何伤害」—— 这三个数分别对应三种完全不同的根因,
## 不数清楚就只能猜。无条件记账(不采样), 正式对局开销=四次整数加。
var _pk: Dictionary = {}


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


## ── 拍击层数(每根触手各自一份) ──
func _sk(side: String, idx: int) -> String:
	return "%s|%d" % [side, idx]


## 这根触手现在攒了几层。
func stack_of(side: String, idx: int) -> int:
	return int(_stacks.get(_sk(side, idx), 0))


## 给这根触手 +1 层。**无上限**(用户 2026-08-20:「无上限」)。
func add_stack(side: String, idx: int) -> void:
	_stacks[_sk(side, idx)] = stack_of(side, idx) + 1


## 这根触手的射程内有没有活着的敌人。
##
## ★单一来源: 消费层数(要"射程内有敌人")与转移阵地(要"射程内没敌人")问的是**同一件事**,
##   分别手写一遍就是抄一次永远落后一次(memory [[fb-hand-rolled-copies-drift]])。
func _foe_in_range(side: String, idx: int) -> bool:
	var tv = battle._tentacle_vfx
	var rng: float = float(tv.attack_range_2d)
	var origin: Vector2 = tv.root_pos(side, idx)
	## ★★2026-08-22 用户:「这触手很多时候该攻击的时候又不攻击，比如机甲，龟蛋破蛋」。
	## 【病根】这里原来手写 `alive + 阵营`, 而 `_slap` 选靶走 `_pick_enemies_of_side`
	##   (§PICK-TARGET 闸门: 排除【围栏未破的蛋】【机甲 5 秒组装期 untargetable】【训龟大师】)。
	##   两个谓词不一样 ⇒ 场上只剩蛋/组装中机甲时:
	##     · 这里说"有敌人" ⇒ tick 扣掉层数并调 `_slap`;
	##     · `_slap` 拿到的名单是空的 ⇒ return 0, **一下都没拍**;
	##     · `_reloc_tick` 也因为这里说"有敌人"而**不搬家** ⇒ 触手杵着空烧层数。
	##   玩家看到的就是「该攻击的时候不攻击」。
	## 【修法】同一个问题只留一份实现(memory [[fb-hand-rolled-copies-drift]]):
	##   判据从"活着的敌人"改成"**打得着的**敌人", 与 `_slap` 用同一份名单。
	for u in battle._targeting._pick_enemies_of_side(side):
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if origin.distance_squared_to(Vector2(u["pos"])) <= rng * rng:
			return true
	return false


func tick(delta: float) -> void:
	# ★每帧让场上的触手数量 == 本档位应有的数量（多了撤场、少了出土）。
	#   文案写的是「N 个无敌触手【登场】」——"登场"意味着它在场上；
	#   不常驻的话玩家永远读不到这四个字（用户 2026-08-04 指出的正是这件事：
	#   「整个触手在这个羁绊里是什么流程」）。
	for sd in ["left", "right"]:
		var tt: int = _side_tier(str(sd))
		battle._tentacle_vfx.ensure(str(sd), TENTACLES[clampi(tt - 1, 0, 3)] if tt > 0 else 0)
	_reloc_tick(delta)
	## ── 产层: 每 SLAP_PERIOD 秒, 每根触手各 +1(无上限) ──
	_t_slap += delta
	if _t_slap >= SLAP_PERIOD:
		_t_slap -= SLAP_PERIOD
		for side in ["left", "right"]:
			var s0: String = str(side)
			var t0: int = _side_tier(s0)
			if t0 <= 0:
				continue
			for i in range(TENTACLES[clampi(t0 - 1, 0, 3)]):
				add_stack(s0, i)
	## ── 消费: 触手【空闲】时消耗 1 层拍一次 ──
	## 用户对「空闲」的定义(2026-08-20 逐句过 + 追问补充):
	##   ① 不在拍击动作中 ② 不在搬家 ③ **射程内有敌人**(否则会对着空气拍)
	## ★ ①② 由 `state_of == ST_IDLE(1)` 一并覆盖 —— 搬家走的是 ST_RETRACT,
	##   拍击走 WARN/REAR/SLAM/RECOVER, 都不等于 1。
	for side in ["left", "right"]:
		var s: String = str(side)
		var ti: int = _side_tier(s)
		if ti <= 0:
			continue
		for i in range(TENTACLES[clampi(ti - 1, 0, 3)]):
			if stack_of(s, i) <= 0:
				continue
			if battle._tentacle_vfx.state_of(s, i) != 1:      # 1 = ST_IDLE
				continue
			if not _foe_in_range(s, i):
				continue
			## ★★只有【真的拍出去了】才扣层(2026-08-22)。
			##   原来是先扣再拍, 而 `_slap` 有好几条 `return 0` 的早退路径
			##   (射程内没有【可选中】的敌人等) ⇒ 层数白烧、一下都没打。
			##   用户:「这触手很多时候该攻击的时候又不攻击」。`_slap` 不依赖层数, 换序安全。
			if _slap(s, i, 1.0) > 0:
				_stacks[_sk(s, i)] = stack_of(s, i) - 1


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
		## 搬家要挑的是【打得着的】敌人 —— 与 `_foe_in_range` / `_slap` 选靶
		## **同一份名单**(§PICK-TARGET: 排除围栏未破的蛋、机甲组装期、训龟大师)。
		## ★★2026-08-22 第二次踩同一个坑: 我修了 `_foe_in_range` 却漏了这里 ⇒
		##   场上只剩蛋/组装机甲时: 搬到蛋旁边 → 到了发现打不着 → 再搬,
		##   **反复搬家却永远不打**。同一个问题在三处各写一遍就是这个下场
		##   (memory [[fb-hand-rolled-copies-drift]])。三处现在都问同一句话。
		var foes: Array = battle._targeting._pick_enemies_of_side(s2)
		for i in range(TENTACLES[clampi(ti - 1, 0, 3)]):
			var k: String = "%s|%d" % [s2, i]
			if tv.state_of(s2, i) != 1:          # 只有【待机】中的才考虑搬家
				_dry[k] = 0.0
				continue
			var origin: Vector2 = tv.root_pos(s2, i)
			if _foe_in_range(s2, i):        # 与"消费层数"问的是同一件事, 只留一份实现
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
	## ★触手选的是"最近的那一个" = 单体指向 ⇒ 走标准闸, 不锁训龟大师
	##   (用户 2026-08-12:「召唤物触手都会锁训龟大师, 不应该」)。
	##   触手挥击的带状结算仍是范围语义, 大师被扫到照吃 —— 那是设计。
	var foes: Array = battle._targeting._pick_enemies_of_side(side)
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
	## ★★2026-08-22 改: 伤害不再另起一条延时队列, 直接挂在【梢端触地】那一刻。
	##   旧做法(_queue_shots + is_striking 复核)是**第二条时钟**, 与演出时钟只有 0.15 秒
	##   余量、且时停时两者冻结规则不同 ⇒ 探针实测 60 秒一场有 13% 的拍击【完整演出、
	##   零伤害】(用户 2026-08-22:「有的时候触手打中没任何伤害」)。
	##   现在演出与结算共用同一个一次性标志, 结构上不可能错开; 被新指令覆盖时
	##   `strike()` 会换掉回调, 老伤害自然不发生 —— 原 serial 闸门的语义原样保留。
	_pk["queued"] = int(_pk.get("queued", 0)) + 1
	var _on_touch := func() -> void:
		_pk["resolved"] = int(_pk.get("resolved", 0)) + 1
		if _slap_resolve(side, origin, dir, rng, mult) <= 0:
			_pk["zero_hit"] = int(_pk.get("zero_hit", 0)) + 1
	## 闪避追击(share<0.9)走点刺: `strike()` 置 ST_SLAM 且 touch_ts=0 ⇒ 下一帧 tick 即触地结算,
	## 与正常拍击【同一条路】, 不再有"第 0 帧特判"这条第二实现。
	battle._tentacle_vfx.strike(side, idx, Vector2(aim["pos"]), share, _on_touch)
	## 返回的是**按 t=0 站位预计会打中几个** —— 真实命中数要等触地才知道。
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


## 拍击的【伤害来源】。
##
## ★★2026-08-22 重写。触手是**无敌**的, 会活过携带者的死亡 ⇒ `_any_carrier` 返回 null
##   在真实对局里**经常**发生。上一版为此手搓了一个 ghost 字典当来源, 结果:
##     · 缺 `dmg_dealt` ⇒ `+=` 运行时错误, 函数当场中止(后面吸血/统计/死亡全不跑);
##     · 更糟的是**反伤**会把它当【受害者】打回来 ⇒ 缺 `shield`/`id`, smoke 一场刷 11 条红。
##   手搓精简单位这条路仓库里已经栽过一次(battle_vfx.gd:881 的注释就是那次)。
##   ⇒ 不再造合成单位: 没有活着的携带者就退回**本方任一存活单位**当来源
##     (它是真单位, 每个键都齐)。一个活人都没有 = 这一侧已被团灭, 那时不打也罢。
func _slap_source(side: String):
	var c = _any_carrier(side)
	if c is Dictionary:
		return c
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side:
			return u
	return null


## 真正结算一次拍击的伤害。返回打中了几个。
func _slap_resolve(side: String, origin: Vector2, dir: Vector2, rng: float, mult: float) -> int:
	var shooter = _slap_source(side)
	if not (shooter is Dictionary):
		return 0                      # 这一侧一个活人都没有 ⇒ 胜负已定, 不必再打
	var hits := 0
	for f in _band_foes(side, origin, dir, rng):
		## ★★2026-08-20 用户:「这是物理伤害就要按规则走啊」
		##   原来这条**不走 `_resolve_dmg`** ⇒ 既不吃护甲、也不吃魔抗、也不是真伤,
		##   而文案(phase2_types.gd:125)写的是「物理伤害」—— 代码从来没落实过。
		##   走 `_resolve_dmg(..., false)` 后 `_last_dmg_type` 自动是物理 ⇒ 飘字自动是规则里的红。
		##   (`col` 参数在两条伤害路里**都没被读**, 颜色一律查全局 —— 传什么都不影响。)
		var base: float = float(f.get("maxHp", 0.0)) * HIT_HP_PCT + HIT_FLAT
		var dmg: int = maxi(1, int(battle._resolve_dmg(shooter, base, f, false) * mult))
		battle._damage._apply_damage_from(shooter, f, dmg, Color("#b388ff"))
		## ★2026-08-21: 逐个被命中者各来一次撞击表现。
		##   在这里调而不是在演出侧, 是因为**只有这里知道带上真正扫到了谁**
		##   (名单是命中那一刻由 `_band_foes` 重算的)。
		##   用户 2026-08-21:「想想两个人被命中为什么只有一个」—— 就是这条缺的。
		battle._tentacle_vfx.impact_on_victim(Vector2(f["pos"]), mult >= 0.9)
		hits += 1
	return hits


## 【闪避蓄能】某只单位闪避成功时调（挂 `_eq_on_dodge` 旁边）。
## ★2026-08-20 用户改机制: 不再"立刻打 25 折追击", 而是**给每根触手各 +1 层**。
##   「友方有闪避成功」= **全队任何一只**(用户原话「任何一只」), 不限于带灵物装备的。
##   **不设上限**(用户原话「不需要上限」)。
func on_dodge(u) -> void:
	if not (u is Dictionary):
		return
	var side: String = str((u as Dictionary).get("side", ""))
	var ti: int = _side_tier(side)
	if ti < DODGE_STACK_MIN_TIER:
		return
	for i in range(TENTACLES[clampi(ti - 1, 0, 3)]):
		add_stack(side, i)


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
		## ★2026-08-21 补 spr_id: 此前没传 ⇒ 落到 battle_spawn 的兜底 = **队色软发光球**,
	##   用户 2026-08-20:「亡魂也需要建模和动作或者动画立绘」。
	var w = battle._spawn._spawn_summon(dead, "wraith", hp, atk, {"col_size": 20.0, "spr_id": "wraith"})
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
	_dry.clear()
	## ★换路要把层数也清掉 —— 否则上一路攒的层会跟到下一路开场连拍。
	##   (这正是 memory [[fb-write-without-reader-and-fake-gates]] 那类"换路没清干净"的坑。)
	_stacks.clear()
