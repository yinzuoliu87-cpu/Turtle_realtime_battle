class_name MagicShield
extends RefCounted
## 【魔法护盾】—— 只挡魔法伤害的护盾(012 海藻 登场给, 用户 2026-10-08):
##   「海草提供的生命值改为90/180/300，不再提供护甲，改为提供7/16/23魔抗。
##    效果为登场时获得相当于25/40/60%最大生命值的魔法护盾（只能挡魔法伤害）。
##    此外每四秒获得40/60/90+3/4/5.5%最大生命值护盾」
##   方案书: docs/plans/20261008-海藻重做.md
##
## ★独立字段 `u["magic_shield"]`, 不进 `u["shield"]` —— 普通护盾的所有读写点(破盾、偷盾、
##   到期清理、护盾条、各种「有盾时」判定)一个都不受影响。
## ★吸收顺序: 魔法伤害先由魔法护盾扛, 剩下的再走普通护盾 / 特殊余额 / 生命。
##   物理与真实伤害完全绕过它。两条伤害路径(_apply_damage / _apply_damage_from)都接(CLAUDE.md §3.3)。
## ★不随时间消失(用户没写时长), 打空为止。它不经 `_grant_shield`, 不在 shield_duration 台账的口径里。
## ★给的量乘携带者的【护盾强度】(BattleDamage.shield_strength, 含 015 反伤削弱)。
## ★「登场」= 每一路开战后携带者第一次 tick(此时羁绊加的最大生命都已写完); 换路重建单位字典 ⇒ 每路重新给。

const SEAWEED_ID := "p2eq_012"
const SEAWEED_MAXHP_PCT := [0.25, 0.40, 0.60]   # 登场魔法护盾 = 自身最大生命 ×


## 魔法伤害先扣魔法护盾; 返回剩余伤害。非魔法伤害原样返回。
static func absorb(u: Dictionary, d: float, is_magic: bool) -> float:
	if not is_magic or d <= 0.0:
		return d
	var ms: float = float(u.get("magic_shield", 0.0))
	if ms <= 0.0:
		return d
	var ab: float = minf(ms, d)
	u["magic_shield"] = ms - ab
	return d - ab


## 012 登场: 每件海藻各给一次(同一只龟带两件 = 两份)。返回给出的量。
static func seaweed_on_spawn(battle, u: Dictionary, si: int) -> float:
	var amt: float = float(u.get("maxHp", 0.0)) * float(SEAWEED_MAXHP_PCT[si]) * BattleDamage.shield_strength(u, battle._t)
	if amt <= 0.0:
		return 0.0
	u["magic_shield"] = float(u.get("magic_shield", 0.0)) + amt
	u["_st_shield"] = float(u.get("_st_shield", 0)) + amt   # §STATS 获盾(与 _grant_shield 同口径; 装备账 == Σ获盾 由 verify_equip_tally 对账)
	battle._equip_sys.tally.on_shield(u, amt)   # ④ 装备统计: 记进 012 的「护盾」一栏
	return amt
