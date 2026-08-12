class_name GunSynergySystem
extends RefCounted
## 枪羁绊【三座炮台】（学派·深海军械库「军火」原设计，2026-08-03 用户要求恢复）
##
## ★我之前在方案书 §5.7 把三座压成了顶档一座、还把火控拆成 6 档的独立效果 ——
##   那是我自己加的框架。用户指出后按原设计恢复：**三档各生成一座，火控是第三座的作用**。
##
## 原文（`docs/archive/学派效果-实装规格.md:27-31`）：
## 【3件】最前方生成**第一座炮台**：选一名敌人轰击，对炮台↔该敌**直线上所有**命中单位造成
##        80 物理伤害，并为**最低血友军**回复（30% × 造成伤害）的生命。
## 【6件】+ 中心**第二座**：每回合产 100 能量（每持一件军械库装备额外 +20）。
##        第 1 回合能量→转护盾均摊全队；第 2 回合能量→化弹幕向敌全体（均摊该能量值魔法）；两回合循环。
## 【9件】+ 后方**第三座**：为携带者接通**火控**，使其额外造成 (10 + 每件军械库装备 × 5)% 真实伤害。
##
## ══════════════════════════════════════════════════════════════════════
##  ★炮台做成【逻辑实体】，不是单位
## ══════════════════════════════════════════════════════════════════════
## 方案书自己写着「炮台是全表最贵的一条，一条全新机制可能超过其余全部之和」——
## 那个估价是按「新的场上单位」算的：生成 / 朝向 / 弹道 / 阵亡 / **换路重建** 全都要处理。
## 但**原设计里炮台没有血量、也不会被摧毁** —— 它只是"一个位置 + 一个计时器"。
## ⇒ 做成逻辑实体（本文件里的几个 float），表现走现成的特效函数。
##   省掉的正是那套复杂度，而玩家看到的东西一模一样。
##
## ★「每回合」一律换算成 **2.5 秒**（`RealtimeBattle3DScene.EQ_TICK`，全项目唯一口径）。
##   第二座的周期由用户定为 **5 秒**（原文是"每回合产能量、两回合循环"，换算后正好是这个量级）。

var battle

const TICK := 2.5                    # 第一座: 每 2.5 秒(1 回合)
const T2_PERIOD := 5.0               # 第二座: 每 5 秒(用户 2026-08-03 定, 比第一座慢一倍)
## 第一座：直线轰击的基础伤害 + 给最低血友军回复的比例
const T1_DMG := 80.0
const T1_HEAL_SHARE := 0.30
const T1_LINE_HALFW := 40.0          # 直线判定半宽（码）
## 第二座：每周期产的能量 = 基数 + 每件枪 × N
const T2_BASE_ENERGY := 100.0
const T2_PER_GUN := 20.0
## 第三座（火控）：带枪者额外造成 `(10 + 【携带者身上】枪件数 × 10)%` 真实伤害（用户 2026-08-03 定）。
## ★口径是【携带者身上】不是全队 —— 单只上限 3 件 ⇒ 最高 **40%**，而不是原学派"全队每件×5%"
##   在 9 件时的 55%。这条是 R8 点名的形状（乘算 + 所有伤害都吃它），上限锁死才不会失控。
##   ⇒ 同时它奖励"把 3 把枪堆在一只龟身上"，与专精主题一致。
const T3_BASE := 0.10
const T3_PER_GUN := 0.10

## 各阵营的节拍与第二座的相位（true = 这次转护盾，false = 这次化弹幕）
var _t_acc := 0.0
var _t2_acc := 0.0
## 火控链接光束的节拍(秒) —— 常驻机制不能每帧画, 会刷屏
const FIRECTRL_IV := 1.6
var _fc_acc := 0.0
var _t2_shield_phase := {"left": true, "right": true}


func _init(b) -> void:
	battle = b


## 某阵营的枪件数（按装备 id 去重，与羁绊计数同口径）
func gun_count(side: String) -> int:
	var seen: Dictionary = {}
	for u in battle._units:
		if not (u is Dictionary) or str(u.get("side", "")) != side:
			continue
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "枪":
				seen[str((e as Dictionary).get("id", ""))] = true
	return seen.size()


## 开战 / 换路后：把【火控】写到带枪者身上（第三座炮台的作用，仅顶档）。
## ★火控是"额外造成 N% 真实伤害" ⇒ 用现成的 `damage_amp` 装不下（那是增伤不是真伤），
##   所以单开一个字段，由伤害管线读。
func apply_all() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		u["_fire_ctrl"] = 0.0
		if int(battle._synergy.tier_for(u, "枪")) < 3:
			continue
		var mine := 0
		for e2 in u.get("equips", []):
			if e2 is Dictionary and battle.Phase2Types.type_of(str(e2.get("id", ""))) == "枪":
				mine += 1
		if mine <= 0:
			continue          # ★原文是为【携带者】接通火控 —— 不带枪的连基数 10% 都不给。
			                  #   (门禁抓出来的: 我上一版删掉了这个判断, 不带枪的白拿 10%。)
		u["_fire_ctrl"] = T3_BASE + T3_PER_GUN * float(mine)


func tick(delta: float) -> void:
	# ★两座炮台【各走各的节拍】: 第一座 2.5 秒、第二座 5 秒(用户定)。
	#   共用一个计时器的话, 第二座只能是第一座的整数倍且相位锁死 —— 那不是同一件事。
	## ★炮台【常驻实体】保活(2026-08-12 用户:「炮台我完全没看到啊」) ——
	##   以前只有开火那 0.32 秒闪一根光柱, 场上没有任何"这里有一座炮台"的东西。
	##   现在每帧保活: 有档位就站着, 掉档/换路就撤走。
	_turret_keepalive(delta)
	_t_acc += delta
	if _t_acc >= TICK:
		_t_acc -= TICK
		for side in ["left", "right"]:
			if _side_tier(side) >= 1:
				_turret_one(side)          # 3 件起
	_t2_acc += delta
	if _t2_acc >= T2_PERIOD:
		_t2_acc -= T2_PERIOD
		for side2 in ["left", "right"]:
			if _side_tier(side2) >= 2:
				_turret_two(side2)         # 6 件起


## 炮台实体的保活/撤走。★炮台不是单位 —— 它只是演出层的一个常驻节点。
##   档位规则与开火完全一致(≥1 档第一座 / ≥2 档第二座), 免得"看得见的"与"会打的"对不上。
func _turret_keepalive(delta: float) -> void:
	var sv = null
	if battle._vfx != null:
		sv = battle._vfx._syn
	if sv == null:
		return
	## ★三档 = 三座, 各一个形态(权威文档 TIER_DESCS["枪"]: 炮台一轰击 / 炮台二能量 / 炮台三·火控)
	for side in ["left", "right"]:
		var t: int = _side_tier(side)
		for idx in range(3):
			var key: String = "%s|%d" % [side, idx]
			if t >= idx + 1:
				sv.gun_turret_ensure(key, _turret_pos(side, idx), idx)
			else:
				sv.gun_turret_free(key)
	sv.gun_turret_tick(delta)
	## 火控塔(第三座)不开火 ⇒ 它"在工作"的证据是【向每个携枪者接通的光束】, 每 FIRECTRL_IV 秒一次
	_fc_acc += delta
	if _fc_acc >= FIRECTRL_IV:
		_fc_acc -= FIRECTRL_IV
		for side2 in ["left", "right"]:
			if _side_tier(side2) < 3:
				continue
			var tos: Array = []
			for u in battle._units:
				if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side2:
					continue
				if float(u.get("_fire_ctrl", 0.0)) > 0.0:
					tos.append(u["pos"])
			if not tos.is_empty():
				sv.gun_firectrl_link("%s|2" % side2, tos)


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "枪")))
	return t


## 第一座：选一名敌人轰击，直线上所有敌人各吃 80 物理；最低血友军回 30% × 造成伤害。
func _turret_one(side: String) -> void:
	var origin: Vector2 = _turret_pos(side, 0)
	var foes: Array = []
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) != side:
			foes.append(u)
	if foes.is_empty():
		return
	# ★确定性选取: 取【最近的】那个当轰击方向 —— 同炮台/猎物的规矩, 随机会让门禁与回放都不稳。
	var aim = null
	var best := INF
	for f in foes:
		var d: float = origin.distance_squared_to(Vector2(f["pos"]))
		if d < best:
			best = d
			aim = f
	if aim == null:
		return
	var dir: Vector2 = (Vector2(aim["pos"]) - origin)
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var total := 0.0
	var shooter = _any_carrier(side)
	var hit_pos: Array = []
	for f in foes:
		# 点到射线的距离 —— 直线上(半宽内)且在正方向才算命中
		var rel: Vector2 = Vector2(f["pos"]) - origin
		if rel.dot(dir) < 0.0:
			continue
		if absf(rel.cross(dir)) > T1_LINE_HALFW:
			continue
		var dmg: int = maxi(1, int(T1_DMG))
		if shooter is Dictionary:
			battle._damage._apply_damage_from(shooter, f, dmg, Color("#ffb74d"))
		else:
			battle._damage._apply_damage(f, dmg, Color("#ffb74d"))
		total += float(dmg)
		hit_pos.append(Vector2(f["pos"]))
	if total > 0.0:
		var low = _lowest_ally(side)
		if low is Dictionary:
			battle._damage._heal(low, total * T1_HEAL_SHARE)
	battle._bolt_line(origin, origin + dir * 900.0, Color(1.0, 0.72, 0.3, 0.75))
	# ★演出(批 B3): 伤害与治疗上面已经结算完了, 这一行【只是好看】——
	#   现状那条 900 码的橙线是从"看不见的地方"射出来的, 玩家读不到"有一座炮台"。
	#   炮位一根矮光柱 = 标出炮台在哪; 命中点火花 = 标出这一线打到了谁。
	if battle._vfx != null and battle._vfx._syn != null:
		battle._vfx._syn.gun_turret_one(origin, hit_pos)
		## 炮塔转向这一轮的目标 + 后坐 + 炮口闪(看得出是【这座炮台】打的)
		if not hit_pos.is_empty():
			battle._vfx._syn.gun_turret_fire("%s|0" % side, hit_pos[0])


## 第二座：每周期产能量，交替【转护盾均摊全队】/【化弹幕敌方全体均摊魔法】。
func _turret_two(side: String) -> void:
	var energy: float = T2_BASE_ENERGY + T2_PER_GUN * float(gun_count(side))
	var allies: Array = []
	var foes: Array = []
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		if str(u.get("side", "")) == side:
			allies.append(u)
		else:
			foes.append(u)
	var is_shield: bool = bool(_t2_shield_phase.get(side, true))
	var lit: Array = []          # 这一发【辐射到谁】—— 只喂演出, 不参与任何结算
	if is_shield:
		if not allies.is_empty():
			var each: float = energy / float(allies.size())
			for a in allies:
				battle._damage._grant_shield(a, each)
				lit.append(Vector2(a["pos"]))
	else:
		if not foes.is_empty():
			var each2: int = maxi(1, int(energy / float(foes.size())))
			var shooter2 = _any_carrier(side)
			for f in foes:
				if shooter2 is Dictionary:
					battle._damage._apply_damage_from(shooter2, f, each2, Color("#9bdcff"))
				else:
					battle._damage._apply_damage(f, each2, Color("#9bdcff"))
				lit.append(Vector2(f["pos"]))
	# ★演出(批 B3): 这条效果唯一要传达的是【相位可辨】——
	#   现状护盾靠通用金环、弹幕靠伤害数字, "这次是给盾还是打人"完全看不出。
	#   蓝=护盾辐射给全队 / 橙=弹幕射向敌方全体, 颜色与辐射对象两条一起分。
	if battle._vfx != null and battle._vfx._syn != null:
		battle._vfx._syn.gun_turret_two(_turret_pos(side, 1), lit, is_shield)
		if not lit.is_empty():
			battle._vfx._syn.gun_turret_fire("%s|1" % side, lit[0], is_shield)
	_t2_shield_phase[side] = not is_shield


## 炮台位置：按阵营的场地方向排在后方（idx 0=最前 1=中 2=后）。
## ★炮台不是单位, 所以这里只是"一个坐标"—— 它不会被选中、不会被攻击、不会死。
func _turret_pos(side: String, idx: int) -> Vector2:
	var a: Rect2 = battle.ARENA
	var y: float = a.position.y + a.size.y * 0.5
	var x: float = a.position.x + a.size.x * (0.12 + 0.06 * float(idx))
	if side != "left":
		x = a.position.x + a.size.x * (0.88 - 0.06 * float(idx))
	return Vector2(x, y)


## 找一个该阵营带枪的单位当"射击者" —— 伤害要归属到某个单位身上,
## 否则统计面板与击杀归属都会缺一块。
func _any_carrier(side: String):
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side:
			continue
		for e in u.get("equips", []):
			if e is Dictionary and battle.Phase2Types.type_of(str(e.get("id", ""))) == "枪":
				return u
	return null


func _lowest_ally(side: String):
	var best = null
	var bv := INF
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side:
			continue
		var r: float = float(u.get("hp", 0.0)) / maxf(1.0, float(u.get("maxHp", 1.0)))
		if r < bv:
			bv = r
			best = u
	return best


func clear() -> void:
	_t_acc = 0.0
	_t2_acc = 0.0
	_t2_shield_phase = {"left": true, "right": true}
