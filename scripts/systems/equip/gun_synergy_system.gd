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
## 激光画多长(码): 没打到人时的默认长度。★判定本身是"沿射线正方向 + 半宽内"无限远,
## 所以这只是【画】的默认值; 有命中点时按最远命中点再多 40 码画(见 _turret_one)。
const T1_LINE_LEN := 900.0
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
var _t2_shield_phase := {"left": true, "right": true}
## 这一拍炮台二的记账(门禁读它: 相位/能量/均摊人数) —— 结算已延到波扫到才发生,
## 需要一个"这一拍打算做什么"的同步证据, 否则门禁只能等演出(CLAUDE.md §3.5 禁止)。
var _t2_last := {}


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
	## ★开局一次性附魔(2026-08-12 用户重做): 收集这一局被接通火控的携枪者, 收完放一次演出。
	var _fc_targets: Array = []
	var _fc_side := "left"
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
		_fc_targets.append(Vector2(u["pos"]))
		_fc_side = str(u.get("side", "left"))
	## 演出: 火控塔向这些人各射一道接通束 + 身上升起符文环(一局一次, 不做周期性表现)
	if not _fc_targets.is_empty() and battle._vfx != null and battle._vfx._syn != null:
		var svf = battle._vfx._syn
		svf.gun_turret_ensure("%s|2" % _fc_side, _turret_pos(_fc_side, 2), 2)
		svf.gun_firectrl_enchant("%s|2" % _fc_side, _fc_targets)

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
	## ★火控塔不做周期性表现(2026-08-12 用户:「只需要战斗开始后展示一个演示特效就好」)——
	##   开局那一次附魔在 apply_all 里放, 这里每帧只保活炮台本身。


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "枪")))
	return t


## 第一座：选一名敌人轰击，直线上所有敌人各吃 80 物理；最低血友军回 30% × 造成伤害。
func _turret_one(side: String) -> void:
	var origin: Vector2 = _turret_pos(side, 0)
	## ★选【轰击方向】是单体指向 ⇒ 走标准闸(排大师/不可选中/按有效阵营), 不再手写敌表。
	##   直线上的扫射结算仍是范围语义, 那一步照旧(大师被线扫到就该吃)。
	var foes: Array = battle._targeting._pick_enemies_of_side(side)
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
	var healed = null
	if total > 0.0:
		var low = _lowest_ally(side)
		if low is Dictionary:
			battle._damage._heal(low, total * T1_HEAL_SHARE)
			healed = low
	## ★旧的 900 码 `_bolt_line` 已删(2026-08-12): 它是一条【定长、单层、匀亮】的橙线,
	##   不管打到谁都一路射出战场 —— 用户要的"激光"正是它的反面。
	##   现在改由 sv2.gun_laser 画: 白热芯 + 双层外晕, 长度 = 打到哪画到哪。
	# ★演出: 伤害与治疗上面已经结算完了, 下面这些【只是好看】。
	if battle._vfx != null and battle._vfx._syn != null:
		var sv2 = battle._vfx._syn
		sv2.gun_turret_one(origin, [])          # 炮位光柱(命中火花改由激光命中效果给)
		## 炮塔转向这一轮的目标 + 后坐 + 炮口闪(看得出是【这座炮台】打的)
		if not hit_pos.is_empty():
			sv2.gun_turret_fire("%s|0" % side, hit_pos[0])
		## ★2026-08-12 用户三条:「第一座要改为激光直线 / 激光命中要有命中效果 /
		##   被治疗的友军用绿光回复效果(中上半身冒绿光)」
		##   激光长度 = 打到最远那个命中点再多一截(没人命中就照射程画满) —— 线的长度
		##   本身就是"这一炮打到哪"的读数, 不是随便给个定值。
		## 打到人 ⇒ 画到【最远那个命中点】再多一截; 没打到人才用默认长度。
		## (上一版写成 maxf(默认, 命中距离) ⇒ 永远至少 900 码, 激光冲出战场老远)
		var far: float = T1_LINE_LEN
		if not hit_pos.is_empty():
			far = 0.0
			for hp2 in hit_pos:
				far = maxf(far, origin.distance_to(hp2) + 55.0)
		sv2.gun_laser(origin, dir, far)
		for hp3 in hit_pos:
			sv2.gun_laser_hit(hp3, dir)
		if healed is Dictionary:
			sv2.heal_glow(Vector2(healed["pos"]))


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
	var origin: Vector2 = _turret_pos(side, 1)
	var sv = null
	if battle._vfx != null:
		sv = battle._vfx._syn
	## ★★2026-08-12 用户重做:「炮台也不要直接去放, 而是有个蓄力, 然后释放」+
	##   「波碰到单位才施加效果」⇒ 结算从"立刻全给"改成:
	##     ① 先蓄力 CHARGE_SEC 秒(演出: 共振环收紧发亮 + 星点内吸, 炮台换成本相位的颜色)
	##     ② 释放星浪(白=转护盾 / 红=化弹幕)
	##     ③ 每个目标的效果延到【波扫到它】那一刻(距离 ÷ 波速), 与 070 咸鱼砖同一条纪律。
	##   ⇒ 能量/均摊口径一个字没改: 均摊分母仍是这一拍的目标数, 只是到账时刻跟着波走。
	var targets: Array = allies if is_shield else foes
	if targets.is_empty():
		return
	var each: float = energy / float(targets.size())
	var shooter = _any_carrier(side)
	if sv != null:
		sv.gun_wave_charge("%s|1" % side, is_shield)
	## 蓄力结束才释放 —— 用 sim 内定时器(_pending_shots), 不用 tween(CLAUDE.md §3.5)
	var charge_sec: float = SynergyVfx.CHARGE_SEC
	battle._pending_shots.append({"delay": charge_sec, "src": shooter, "fn": func() -> void:
		if sv != null:
			sv.gun_wave_release("%s|1" % side, is_shield)
		for t in targets:
			if not (t is Dictionary) or not (t as Dictionary).get("alive", false):
				continue
			## 到达时刻 = 距离 ÷ 波速(与演出同一个常量 —— 波扫到谁, 谁那一刻才吃效果)
			var d: float = origin.distance_to(Vector2((t as Dictionary)["pos"]))
			battle._pending_shots.append({"delay": d / SynergyVfx.WAVE_SPEED, "src": shooter,
				"fn": func() -> void:
					if not (t as Dictionary).get("alive", false):
						return
					if is_shield:
						battle._damage._grant_shield(t, each)
					else:
						var dmg: int = maxi(1, int(each))
						if shooter is Dictionary:
							battle._damage._apply_damage_from(shooter, t, dmg, Color("#ff5a55"), 0.0, true, true)
						else:
							battle._damage._apply_damage(t, dmg, Color("#ff5a55"), true)})
	})
	_t2_shield_phase[side] = not is_shield
	_t2_last[side] = {"shield": is_shield, "energy": energy, "n": targets.size()}


## 炮台位置：按阵营的场地方向排在后方（idx 0=最前 1=中 2=后）。
## ★炮台不是单位, 所以这里只是"一个坐标"—— 它不会被选中、不会被攻击、不会死。
func _turret_pos(side: String, idx: int) -> Vector2:
	## ★三座按【三角形】站位(2026-08-12 用户拍板:「以三角形放置: 前上前下和后面」)——
	##   前上 = 炮台一·轰击 / 前下 = 炮台二·能量 / 后方 = 炮台三·火控。
	##   之前是三座横排(相距 96 码)、再之前我改成前中后但用纵向错开半档, 都不好看;
	##   三角形既拉得开又是个能读出来的阵形。
	## ⚠ 站位会改动炮台一那条穿透线的起点与炮台二的辐射源 —— 这是站位本身的含义, 不是副作用。
	var a: Rect2 = battle.ARENA
	## [横向比例, 纵向偏移(相对场高)] —— 以左方为例, 右方横向镜像、纵向不镜像
	var spec := [[0.32, -0.20], [0.32, 0.20], [0.10, 0.0]]
	var fx: float = float(spec[clampi(idx, 0, 2)][0])
	var fy: float = float(spec[clampi(idx, 0, 2)][1])
	var x: float = a.position.x + a.size.x * (fx if side == "left" else 1.0 - fx)
	var y: float = a.position.y + a.size.y * (0.5 + fy)
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
