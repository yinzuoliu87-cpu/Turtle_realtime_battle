class_name ThornCut
extends RefCounted
## 荆棘海胆 015 追加效果「反伤削弱」(用户 2026-10-07):
##   「携带者的反伤会对目标施加持续3秒的50%治疗效果和护盾效果的削弱」
##   同日:「没有护盾效果的属性吗」「有吧」⇒ 削的是目标的【治疗强度 / 护盾强度】两个属性
##   (heal_amp / shield_amp), 不是另立一个「护盾削减」状态。
##   方案书: docs/plans/20261007-荆棘海胆重做.md
##
## ★这是【追加】不是替换: 015 原来的「累计反伤 → 护盾 + 强化下一次普攻流血」原样保留
##   (用户同日更正:「不不不，不要去掉旧效果」)。
## ★触发口径 = 携带者【任何来源】的反伤命中攻击者 —— 015 自己那条专属反伤
##   (equip_system._eq_on_target 的 p2eq_015 分支) 与通用反伤 (battle_damage: 013 反伤% /
##   龟壳觉醒 / 石头龟坚壁) 两处都调 on_reflect; 没带 015 的单位反伤不触发。
## ★与既有「治疗削减」(heal_reduce_until) 是两回事, 各算各的(那条没动)。
## ★生效点只有一处: BattleDamage.heal_strength / shield_strength —— 结算(_heal / _grant_shield)
##   与信息面板的「治疗强度 / 护盾强度」两行都读它们, 面板显示的就是此刻实际倍率。
## ★为什么单开文件: equip_system.gd 已顶着 arch_budget 的 3000 行上限。

const EQ_ID := "p2eq_015"
const CUT_SEC := 3.0     # 持续秒数
const AMP_CUT := 0.5     # 治疗强度 / 护盾强度 各 ×(1 - 0.5)


## 单位是否携带 015
static func carries(u: Dictionary) -> bool:
	for e in u.get("equips", []):
		if e is Dictionary and str(e.get("id", "")) == EQ_ID:
			return true
	return false


## 携带者的反伤刚打中 attacker 时调用。没带 015 = 什么都不做。
## 多来源不叠加取最高、重复施加刷新时长; 已过期的旧幅度不参与取最高。
static func on_reflect(carrier: Dictionary, attacker, t: float) -> void:
	if not (attacker is Dictionary) or is_same(carrier, attacker) or not carries(carrier):
		return
	_take_highest(attacker, "heal_amp_cut", AMP_CUT, t)
	_take_highest(attacker, "shield_amp_cut", AMP_CUT, t)


static func _take_highest(o: Dictionary, key: String, pct: float, t: float) -> void:
	var k_until: String = key + "_until"
	var live: bool = t < float(o.get(k_until, 0.0))
	o[key] = maxf(float(o.get(key, 0.0)), pct) if live else pct
	o[k_until] = maxf(float(o.get(k_until, 0.0)), t + CUT_SEC)


## 生效中的削弱幅度(0 = 没有)
static func cut_of(u: Dictionary, key: String, t: float) -> float:
	if t < float(u.get(key + "_until", 0.0)):
		return clampf(float(u.get(key, 0.0)), 0.0, 1.0)
	return 0.0
