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
## 【闪避追击】追击伤害占拍击的比例 + 每 2.5 秒的次数上限（档1 无）
const CHASE_SHARE := 0.25
const CHASE_CAP := [0, 3, 3, 5]
## 【亡灵】亡魂继承阵亡者的属性比例（逐档）
const WRAITH_INHERIT := [0.20, 0.38, 0.65, 1.00]
## 亡魂阵亡后还能再循环几次（逐档），每次属性 ×0.9
const WRAITH_LOOPS := [0, 1, 2, 3]
const WRAITH_DECAY := 0.9

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
	var shooter = _any_carrier(side)
	var hits := 0
	for f in foes:
		var rel: Vector2 = Vector2(f["pos"]) - origin
		if rel.dot(dir) < 0.0:
			continue
		if absf(rel.cross(dir)) > 40.0:
			continue
		var dmg: int = maxi(1, int((float(f.get("maxHp", 0.0)) * HIT_HP_PCT + HIT_FLAT) * mult))
		if shooter is Dictionary:
			battle._damage._apply_damage_from(shooter, f, dmg, Color("#b388ff"))
		else:
			battle._damage._apply_damage(f, dmg, Color("#b388ff"))
		hits += 1
	# ★演出与结算【解耦】: 伤害上面已经结算完了, 这里只是好看。
	#   一个测数值的用例不该依赖任何动画跑完(CLAUDE.md §3.5)。
	battle._tentacle_vfx.strike(side, idx, Vector2(aim["pos"]), share)
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
	_chase_used = {"left": 0, "right": 0}
