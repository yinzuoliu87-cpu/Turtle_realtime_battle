extends RefCounted
## SkillForms — 【多形态技能】的单一事实源 (2026-08-28)。
##
## 用 preload 引:  const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")
##
## ★★由来(用户 2026-08-27~28 连着指出两个):
##   有些技能【一个槽位里塞了两个完全不同的效果】, 按自身状态切换, 而对外
##   **只有一个图标、一个名字** —— 玩家看不出下一发会是哪个。
##     · 海盗船: 首次召实体船+冲锋撞击 / 之后每次打霰弹
##     · 精英铁锤: 普通砸地 60°锥500码 / **每第3次**跃起下锤 700码全域(连动画帧都是两套)
##   用户原话:「我希望的是铁锤也像海盗一样分两个技能图标, 当时偷的哪个就放普通的还是强化的」。
##
## ★为什么做成【通用机制】而不是两个特例:
##   ① 判据千奇百怪(海盗船看布尔 `ship_summoned`、铁锤看计数器 `_hammer_n % 3`),
##      写成特例的话每加一个技能就要改一遍显示层和复制层;
##   ② **龟壳复制只要读"当前形态"这一个接口**, 不必认识每个技能的内部字段 ——
##      否则复制那边会长出一堆 `if stype == "pirateShipPassive": ...` 的分支。
##   ⇒ 技能自己声明"我有几个形态 + 怎么判当前是哪个", 显示与复制都只问这一个函数。
##
## ★本文件【只描述形态, 不改行为】—— 拆分不动数值(海盗船仍 120 龟能, 铁锤仍 100),
##   这一轮只解决"看得见"与"抄得对"。数值调整单独一轮, 出了问题才分得清是谁引入的。

## 每个多形态技能一条: type → {forms: [形态...], pick: 判据说明}
##
## 形态字段:
##   key    —— 形态的稳定标识(给复制/门禁用, 不落盘不进存档)
##   name   —— 玩家看到的名字
##   icon   —— 图标路径(相对 assets/sprites/)。★实测 112/112 个技能都有 icon 且文件都在
##   brief  —— 一句话说明这一态干什么
const FORMS := {
	"pirateShipPassive": {
		"pick": "u[\"ship_summoned\"] 为假 → 形态0(冲锋召船); 为真 → 形态1(霰弹)",
		"forms": [
			{"key": "charge", "name": "海盗船·冲锋", "icon": "skills/pirate-ship.png",
			 "brief": "召出实体船并冲锋撞击, 撞到的第一个敌人受魔法伤害并被击飞; 船留在场上"},
			{"key": "shotgun", "name": "霰弹", "icon": "skills/pirate-shotgun.png",
			 "brief": "朝目标喷出扇面弹丸, 每颗对命中的第一个敌人造成物理伤害并击退"},
		],
	},
	"eliteHammer": {
		"pick": "u[\"_hammer_n\"] % 3 == 2 → 下一发是第3次 → 形态1(强化); 否则形态0(普通)",
		"forms": [
			{"key": "normal", "name": "铁锤", "icon": "skills/elite-hammer.png",
			 "brief": "举拳蓄力后砸地, 对身前锥形范围造成魔法伤害"},
			{"key": "big", "name": "铁锤·跃击", "icon": "skills/elite-hammer-big.png",
			 "brief": "高高跃起、空中蓄力后下锤, 覆盖更大范围并造成更高魔法伤害"},
		],
	},
}


## 【钉住形态】用的键。★全仓只有本文件写它、只有本文件读它 ——
## 加新键前先想"会不会激活别的机制"(memory fb-home-pos-only-if-exists: 凭空创建
## `_home_pos` 把真实单位永久钉死)。这个键是新的, 没有第二个消费者。
const PIN_KEY := "_form_pin"


## 这个技能是不是多形态的。
static func is_multi(stype: String) -> bool:
	return FORMS.has(stype)


## 某单位【当前】处在这个技能的哪个形态(下标)。不是多形态技能 → 0。
##
## ★判据写在这里而不是各自的技能文件里 —— 它要被【显示层】和【复制】两边读,
##   放技能文件里就变成"两个消费者各自去认对方的内部字段"。
static func current_index(u, stype: String) -> int:
	if not (u is Dictionary) or not FORMS.has(stype):
		return 0
	var d: Dictionary = u
	## ★钉住的形态优先 —— 龟壳复制时"偷的是哪一态就放哪一态"(用户 2026-08-28)。
	##   放在最前面而不是各技能实现里各判一次: 只有一处认识"当前是哪态"这件事。
	var pin: Dictionary = d.get(PIN_KEY, {})
	if pin is Dictionary and (pin as Dictionary).has(stype):
		return clampi(int((pin as Dictionary)[stype]), 0, form_count(stype) - 1)
	match stype:
		"pirateShipPassive":
			return 1 if bool(d.get("ship_summoned", false)) else 0
		"eliteHammer":
			## ★注意是【下一发】: `_sk_elite_hammer` 会先 `_hammer_n += 1` 再判 `% 3 == 0`,
			##   所以"下一发是不是强化"要看当前值 % 3 == 2。
			##   (判据写错一格 = 图标永远比实际慢一发, 而且不报错。门禁逐值验过 0~5。)
			return 1 if (int(d.get("_hammer_n", 0)) % 3 == 2) else 0
	return 0


## 某单位当前形态的 {key, name, icon, brief}。不是多形态技能 → 空字典。
static func current_form(u, stype: String) -> Dictionary:
	if not FORMS.has(stype):
		return {}
	var arr: Array = (FORMS[stype] as Dictionary)["forms"]
	var i: int = clampi(current_index(u, stype), 0, arr.size() - 1)
	return (arr[i] as Dictionary).duplicate(true)


## 这个技能有几个形态。不是多形态技能 → 1(它只有"一种样子")。
static func form_count(stype: String) -> int:
	if not FORMS.has(stype):
		return 1
	return ((FORMS[stype] as Dictionary)["forms"] as Array).size()


## 把某单位的这个技能【钉在指定形态】。复制时用: 记下被偷者当时是哪一态。
##
## ★成对使用, 放完必须 unpin —— 钉子留在身上会让这只龟之后永远放同一态。
##   (`_form_pin` 只有本文件读, 但漏解钉的后果是"这只龟的形态卡住"而且不报错。)
static func pin_form(u, stype: String, idx: int) -> void:
	if not (u is Dictionary) or not FORMS.has(stype):
		return
	var d: Dictionary = u
	var pin: Dictionary = d.get(PIN_KEY, {})
	if not (pin is Dictionary):
		pin = {}
	pin[stype] = clampi(idx, 0, form_count(stype) - 1)
	d[PIN_KEY] = pin


## 解掉钉子。stype 为空 → 解掉这只龟身上全部钉子。
static func unpin_form(u, stype: String = "") -> void:
	if not (u is Dictionary):
		return
	var d: Dictionary = u
	if stype == "":
		d.erase(PIN_KEY)
		return
	var pin: Dictionary = d.get(PIN_KEY, {})
	if pin is Dictionary:
		(pin as Dictionary).erase(stype)


## 这只龟这个技能【被钉住了吗】(技能实现拿它决定要不要推进自己的计数器)。
static func is_pinned(u, stype: String) -> bool:
	if not (u is Dictionary):
		return false
	var pin: Dictionary = (u as Dictionary).get(PIN_KEY, {})
	return pin is Dictionary and (pin as Dictionary).has(stype)


## 这个技能所有形态的 key 列表(门禁/复制枚举用)。
static func form_keys(stype: String) -> Array:
	if not FORMS.has(stype):
		return []
	var out: Array = []
	for f in ((FORMS[stype] as Dictionary)["forms"] as Array):
		out.append(str((f as Dictionary).get("key", "")))
	return out
