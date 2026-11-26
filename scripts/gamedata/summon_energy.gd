extends RefCounted
## summon_energy.gd —— 召唤物龟能充能: 一份规矩, 和龟的技能充能完全同口径(2026-11-27)
##
## 由来: 用户 11-27「这个召唤物的龟能增长，没按规矩来吗？」—— 查出各批召唤物各写一份 _en_gain, 各漏各的:
##   舞狮另外每次普攻 +20 龟能(我自己加的, 文案没写、用户没说过); 舞狮 / 百夫长没算风暴锁龟能、寒冰充能减速、沙漏时停加速;
##   百夫长连「引导中不充」都漏了。
## 规矩的事实源 = 主文件 `RealtimeBattle3DScene._tick_skill_cd`(龟的技能充能):
##   龟能按固定速率一直充(1 点 = 0.075 秒, SkillEnergy.CD_FACTOR);
##   眩晕 / 引导 / 击飞 / 风暴 / 显式龟能锁 ⇒ 不充;
##   × 充能加速 buff(echarge_mult, 期间内) × 充能减速 debuff(spd_echarge_mult, 期间内; 合起来不低于 5%)
##   × 装备永久充能速率(echarge_perm) × 沙漏时停期加速(_ts_echarge)。
##   (龟身上那几种「持盾期锁龟能」是各只龟自己技能的规则, 召唤物没有那些盾, 不适用。)
## 引用: const SummonEnergy := preload("res://scripts/gamedata/summon_energy.gd")  (不用 class_name: 无头跑时注册不稳)

const SEC_PER_ENERGY := 0.075


## 这一步该涨多少龟能
static func gain(u: Dictionary, t: float, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	if t < float(u.get("stun_until", 0.0)) or t < float(u.get("channel_until", 0.0)) or bool(u.get("airborne", false)) \
			or t < float(u.get("storm_until", 0.0)) or t < float(u.get("energy_lock_until", 0.0)):
		return 0.0
	var ecm: float = maxf(1.0, float(u.get("echarge_mult", 1.0))) if t < float(u.get("echarge_until", 0.0)) else 1.0
	if t < float(u.get("spd_dbf_until", 0.0)):
		ecm *= float(u.get("spd_echarge_mult", 1.0))
	ecm = maxf(0.05, ecm)
	return delta / SEC_PER_ENERGY * ecm * maxf(0.0, float(u.get("echarge_perm", 1.0))) * float(u.get("_ts_echarge", 1.0))
