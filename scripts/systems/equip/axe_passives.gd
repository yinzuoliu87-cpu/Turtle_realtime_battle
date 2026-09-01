class_name AxePassives
extends RefCounted
## 小木斧·被动 3~6 (用户 2026-08-31 需求·方案书五期·2026-09-01 实装)
##
## ★为什么单独一个文件: `axe_system.gd` 管的是"召唤 + 通用主动 + 被动 2",
##   这四条被动加起来比它本身还大。塞一起就又造一个小上帝对象。
##
## ★数值**全部**取自 `AxeEvolution`，这里一个裸数字都不许有。
##
## ★解锁与档位一一对应（`AxeEvolution.passives_at()`）：
##     石斧(1) → 被动3   铁斧(2) → 被动4   金斧(3) → 被动5   钻石斧(4) → 被动6
##   属性(50血/5攻/3甲/3抗)是**每条各一份、可叠加**，已经由 minion_hp/minion_atk
##   的 `passives_unlocked` 参数算进去了 —— 这里只做行为。
##
## ★★结算与演出分开(CLAUDE.md §3.5)：
##   `slam_settle()` / `cleave_settle()` / `sweep_targets()` 都是**纯结算/纯选靶**，
##   门禁直接调它们喂坐标验数，不必等任何 tween 跑完。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")

var battle = null


func _init(b) -> void:
	battle = b


## 这只斧头解锁了几条【带行为的】被动。0=木斧(只有被动2)。
func _pv(ax: Dictionary) -> int:
	return int(ax.get("_axe_pv", 0))


# ════════════════════════════════════════════════════════════════
#  被动 3(石斧): 每 9 秒, 下一次普攻带强化 on-hit
# ════════════════════════════════════════════════════════════════
## 每帧推进充能。★存"下一次可用的时刻"而不是"已过多少秒" ——
##   后者要自己累加 delta, 一旦某帧没跑到就永远差一点(而这类漏拍看不出来)。
func tick_smash(ax: Dictionary, _delta: float) -> void:
	if _pv(ax) < 1:
		return
	if not ax.has("_axe_smash_at"):
		ax["_axe_smash_at"] = float(battle._t) + AE.SMASH_IV
		return
	if float(battle._t) >= float(ax["_axe_smash_at"]):
		ax["_axe_smash_ready"] = true


## 强化命中真的发生了吗。返回额外伤害(0 = 这一下没强化)。
## ★消费成功【才】清充能(memory: 消费资源要成功了才扣)。
func smash_on_hit(ax: Dictionary, tgt: Dictionary) -> float:
	if _pv(ax) < 1 or not bool(ax.get("_axe_smash_ready", false)):
		return 0.0
	if not (tgt is Dictionary) or not tgt.get("alive", false):
		return 0.0
	ax["_axe_smash_ready"] = false
	ax["_axe_smash_at"] = float(battle._t) + AE.SMASH_IV
	var extra: float = float(ax.get("atk", 0.0)) * AE.SMASH_ATK
	battle._damage._apply_damage_from(ax, tgt, maxi(1, int(round(extra))),
		Color("#c08a4a"), 0.0, false, true)
	## 击飞 + 短暂击退 —— 走既有的唯一入口, 不自己写位移
	battle._damage._knockback(ax, tgt, 0.0, AE.SMASH_KNOCK_VY, AE.SMASH_KNOCK_PUSH)
	return extra


# ════════════════════════════════════════════════════════════════
#  被动 4/5: 竖劈 与 180° 横扫【交替】
# ════════════════════════════════════════════════════════════════
## 这一次普攻是第几下(从 1 开始)。★被动4「每第二次竖劈」与被动5「每第一次横扫」
##   共用同一个计数器 —— 需求把它们写成两条, 但合起来就是**奇数横扫、偶数竖劈**
##   (方案书出入第 8 条)。分开各记一个计数器必然错位。
func bump_swing(ax: Dictionary) -> int:
	var n: int = int(ax.get("_axe_swing", 0)) + 1
	ax["_axe_swing"] = n
	return n


## 竖劈(被动 4·偶数次普攻): 额外 5% 目标最大生命【真实伤害】+ 10 层流血。
## 返回真伤数值(0 = 这一下不是竖劈)。
func cleave_settle(ax: Dictionary, tgt: Dictionary, swing: int) -> float:
	if _pv(ax) < 2 or swing % 2 != 0:
		return 0.0
	if not (tgt is Dictionary) or not tgt.get("alive", false):
		return 0.0
	var d: float = float(tgt.get("maxHp", 0.0)) * AE.CLEAVE_MAXHP_PCT
	if d <= 0.0:
		return 0.0
	## ★真实伤害走 _apply_damage(bucket="tru", is_self=false) —— 不吃护甲/魔抗。
	##   两条伤害路各自扣盾扣血(CLAUDE.md §3.3), 真伤是这一条。
	battle._damage._apply_damage(tgt, maxi(1, int(round(d))), Color("#d9534f"), ax, "tru", false)
	battle._damage._apply_dot_stacks(tgt, "bleed", AE.CLEAVE_BLEED, ax)
	return d


## 横扫(被动 5·奇数次普攻): 以斧头为心、朝目标方向的 180° 扇形内的敌人。
## ★纯选靶 —— 返回名单, 伤害由调用方按普攻伤害施加。门禁直接摆位置验名单。
func sweep_targets(ax: Dictionary, tgt: Dictionary, swing: int) -> Array:
	if _pv(ax) < 3 or swing % 2 != 1:
		return []
	if not (tgt is Dictionary):
		return []
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var dir: Vector2 = (tgt.get("pos", Vector2.ZERO) - org)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var rng: float = float(ax.get("atk_range", 120.0))
	var half_cos: float = cos(deg_to_rad(AE.SWEEP_ARC_DEG * 0.5))
	var out: Array = []
	for o in battle._targeting._targetable_enemies(ax):
		var rel: Vector2 = (o.get("pos", Vector2.ZERO) as Vector2) - org
		if rel.length() > rng:
			continue
		## 180° ⇒ half_cos == 0 ⇒ 判据退化成"在斧头正面这半边"。
		## ★用点积不用角度差 —— 角度差要处理 ±π 环绕, 那是最容易写错的一段。
		if rel == Vector2.ZERO or rel.normalized().dot(dir) >= half_cos:
			out.append(o)
	return out


# ════════════════════════════════════════════════════════════════
#  被动 5: 效率层(每次普攻命中 +1 层, 5 秒, 无限叠, 每叠刷新)
# ════════════════════════════════════════════════════════════════
func add_eff(ax: Dictionary) -> int:
	if _pv(ax) < 3:
		return 0
	var n: int = eff_stacks(ax) + 1
	ax["_axe_eff_n"] = n
	ax["_axe_eff_until"] = float(battle._t) + AE.EFF_DUR   # 每叠**刷新整条**时长
	## ★★需求原话:「一层效率提供4%攻击速度和**2%移动速度**」。
	##   攻速接了、**移速一直没接**(常量 EFF_MOVE 躺在表里零消费者) —— 2026-09-01 对原话逐条核对时抓到。
	##   走既有的 `move_buff_mult` / `move_buff_until` 通道(主场景移动公式已经在乘它),
	##   比自己再开一条通道少一整类"加了没人读"的坑。
	ax["move_buff_mult"] = AE.eff_move_mult(n)
	ax["move_buff_until"] = float(battle._t) + AE.EFF_DUR
	return n


## 当前有效层数。★过期就是 0 —— 不做"到点减一层"那种衰减,
##   需求说的是"持续 5 秒、每次叠加刷新时长", 整条一起过期。
func eff_stacks(ax: Dictionary) -> int:
	if float(battle._t) >= float(ax.get("_axe_eff_until", -1.0)):
		return 0
	return int(ax.get("_axe_eff_n", 0))


## 蓄力期间效率计时器【中断】(需求原话) —— 每帧把到期时刻往后推 delta,
## 相当于把这条计时暂停。★不能改成"记下剩余时间、结束再写回":
##   那样中途叠新层会把暂存的剩余时间冲掉。
func hold_eff(ax: Dictionary, delta: float) -> void:
	if ax.has("_axe_eff_until") and eff_stacks(ax) > 0:
		ax["_axe_eff_until"] = float(ax["_axe_eff_until"]) + delta
		## ★★移速那一半**也要暂停** —— 2026-09-01 补。效率层现在同时驱动
		##   攻速(`_axe_eff_until`)与移速(`move_buff_until`)两条计时, 只推一条 ⇒
		##   4 秒蓄力结束时移速加成已经过期、攻速还在, 而需求说的是"效率计时器中断"(一条)。
		##   老判据只盯 `_axe_eff_until`, 窄了一格 ⇒ 抓不到。
		if float(ax.get("move_buff_until", 0.0)) > float(battle._t):
			ax["move_buff_until"] = float(ax["move_buff_until"]) + delta


# ════════════════════════════════════════════════════════════════
#  被动 6(钻石斧): 治疗时进入 4 秒蓄力 → 猛砸
# ════════════════════════════════════════════════════════════════
## 主动治疗触发时调它。返回是否真的进了蓄力。
func begin_charge(ax: Dictionary) -> bool:
	if _pv(ax) < 4 or not ax.get("alive", false):
		return false
	if is_charging(ax):
		return false                      # 已经在蓄了, 不重开(否则治疗一进来就把高清零)
	ax["_axe_charge_t0"] = float(battle._t)
	var t: Dictionary = battle._targeting._nearest_enemy(ax) if battle._targeting._nearest_enemy(ax) is Dictionary else {}
	var dir: Vector2 = ((t.get("pos", Vector2.ZERO) as Vector2) - (ax.get("pos", Vector2.ZERO) as Vector2)) if not t.is_empty() else Vector2.RIGHT
	ax["_axe_charge_dir"] = (dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT)
	## 70% 减伤 —— 走既有的 damage_reduction 通道(_mitigate_incoming 读它)
	ax["_axe_dr_bak"] = float(ax.get("damage_reduction", 0.0))
	ax["damage_reduction"] = maxf(float(ax.get("damage_reduction", 0.0)), AE.CHARGE_DR)
	return true


func is_charging(ax: Dictionary) -> bool:
	return ax.has("_axe_charge_t0")


## 已经蓄了多久。没在蓄 → -1。
func charge_elapsed(ax: Dictionary) -> float:
	if not is_charging(ax):
		return -1.0
	return float(battle._t) - float(ax["_axe_charge_t0"])


## 每帧推进蓄力; 满 4 秒就砸。返回被砸中的敌人数(-1 = 没在蓄)。
func tick_charge(ax: Dictionary, delta: float) -> int:
	if not is_charging(ax):
		return -1
	if not ax.get("alive", false):
		_end_charge(ax)
		return -1
	hold_eff(ax, delta)                   # 蓄力期间效率计时中断
	if charge_elapsed(ax) < AE.CHARGE_TIME:
		return 0
	return slam_settle(ax)


## 砸下去的**纯结算**: 梯形内每个敌人 4×ATK 物理 + 高高击飞 + 眩晕 3 秒。
## ★门禁直接调它 —— 摆好敌人位置、调一次、量伤害与眩晕, 不等任何演出。
func slam_settle(ax: Dictionary) -> int:
	var h: float = AE.charge_height(maxf(0.0, charge_elapsed(ax)))
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	var dir: Vector2 = ax.get("_axe_charge_dir", Vector2.RIGHT)
	var dmg: int = maxi(1, int(round(float(ax.get("atk", 0.0)) * AE.SLAM_ATK)))
	var n := 0
	for o in battle._targeting._targetable_enemies(ax):
		if not AE.in_trapezoid(org, dir, h, o.get("pos", Vector2.ZERO)):
			continue
		battle._damage._apply_damage_from(ax, o, dmg, Color("#e8b04b"), 0.0, false, true)
		if o.get("alive", false):
			battle._damage._knockback(ax, o, 0.0, 1.6, 1.0)     # "高高击飞"
			battle._damage._stun(o, AE.SLAM_STUN, "axe_slam")
		n += 1
	_end_charge(ax)
	return n


func _end_charge(ax: Dictionary) -> void:
	ax.erase("_axe_charge_t0")
	if ax.has("_axe_dr_bak"):
		ax["damage_reduction"] = float(ax["_axe_dr_bak"])       # 还原, 不许把 70% 留下
		ax.erase("_axe_dr_bak")
