extends RefCounted
## 造成伤害按类型拆 + 灵物触手单列 —— 纯数据(只读单位字典 / 快照行的标量键), 不依赖任何场景脚本。
## 由来(2026-11-11): 这些函数原写在 settle_screen.gd, 伤害统计面板为了用它们 preload 了整个结算页脚本(结算页依赖一长串
##   UI / 联网 / 回放类), 战斗场景因此连带编译一长串无关脚本。挪到这里, 面板只 preload 这一个无依赖文件;
##   (当时 verify_tutorial 的「Nonexistent function 'new'」后来查清不是这条依赖, 是文案常量后台预加载与进战斗同时编译, 见 SkillText.prewarm_busy)
##   settle_screen 留同名函数转调这里(调用方不用改)。不设 class_name: 按路径 preload, 不吃全局类缓存。
## ── 灵物触手单列(用户 11-11「整个伤害面板都没有统计这个出手的伤害…为什么不单独做一个…触手造成的伤害呢？」) ──
## 触手是独立出手方(11-11): 拍击不进任何龟的 _st_dealt, 只记在本方挂账单位的 _st_spirit_dealt / _st_spirit_by_type(battle_damage.spirit_src)。
## 显示: 本方多一行「灵物触手」(不评 MVP); 龟那一行就是它自己的 _st_dealt。

const SPIRIT_NAME := "灵物触手"
const SPIRIT_ICON := "res://assets/sprites/tags/tag-spirit.png"


## 造成伤害按类型拆开: [物理, 魔法, 真实]。键名与 `battle_damage._record_buckets` 写的桶一致
##   (phy / mag / tru; 持续伤害走 `_apply_damage` 默认的 dot 桶, 与真伤同列 —— 同 `DmgStatsPanel` 的分段条)。
## ★三者之和 == `_st_dealt`(门禁 verify_settle_pages 走真伤害入口对这笔账)。
## 快照行(`_st_row`)已经拆好成 `_st_phy/_st_mag/_st_tru` 三个标量 ⇒ 直接读; 活单位读分桶字典。
static func dealt_split(u: Dictionary) -> Array:
	if u.has("_st_phy"):
		return [int(u["_st_phy"]), int(u.get("_st_mag", 0)), int(u.get("_st_tru", 0))]
	var bt: Dictionary = u.get("_st_dealt_by_type", {})
	return [int(bt.get("phy", 0)), int(bt.get("mag", 0)), int(bt.get("tru", 0)) + int(bt.get("dot", 0))]


static func spirit_split(u: Dictionary) -> Array:
	var bt = u.get("_st_spirit_by_type", {})
	if not (bt is Dictionary):
		return [0, 0, 0]
	return [int(bt.get("phy", 0)), int(bt.get("mag", 0)), int(bt.get("tru", 0)) + int(bt.get("dot", 0))]


## 这只单位自己打出的伤害(触手独立后 = _st_dealt; 留这一层是为了战报 / 结算行只有一个取数口)
static func own_dealt(u: Dictionary) -> int:
	return int(u.get("_st_dealt", 0))


static func own_split(u: Dictionary) -> Array:
	return dealt_split(u)


## 一方的「灵物触手」行(纯标量, 快照可存; 没有拍击伤害 ⇒ {})
static func spirit_row(units: Array) -> Dictionary:
	var tot := 0
	var sp := [0, 0, 0]
	for u in units:
		if not (u is Dictionary) or int(u.get("_st_spirit_dealt", 0)) <= 0:
			continue
		tot += int(u["_st_spirit_dealt"])
		var s: Array = spirit_split(u)
		for i in range(3):
			sp[i] = int(sp[i]) + int(s[i])
	if tot <= 0:
		return {}
	return {"name": SPIRIT_NAME, "id": "__spirit__", "is_summon": false, "_st_spirit": true, "_st_multi": false, "_st_mkind": "",
		"rarity": "C", "alive": true, "hp": 0.0, "maxHp": 0.0, "_st_dealt": tot, "_st_taken": 0, "_st_heal": 0, "_st_crit": 0,
		"_st_kills": 0, "_st_shield": 0, "_st_phy": int(sp[0]), "_st_mag": int(sp[1]), "_st_tru": int(sp[2]),
		"_st_portrait": SPIRIT_ICON, "_st_pf": "1,1"}


## 快照行(纯标量)再过一遍 _st_row 时要留住的键: 灵物行标记、头像兜底(活单位没有这些键 ⇒ 空字典; merge 不覆盖已有键)
static func keep_flags(u: Dictionary) -> Dictionary:
	var out := {}
	for k in ["_st_spirit", "_st_portrait", "_st_pf"]:
		if u.has(k):
			out[k] = u[k]
	return out


## 给一份 {left:[行], right:[行]} 按方补上「灵物触手」行; side_of(单位) → "left" / "right"
static func add_spirit_rows(snap: Dictionary, units: Array, side_of: Callable) -> void:
	for sd in ["left", "right"]:
		var mine: Array = []
		for u in units:
			if u is Dictionary and str(side_of.call(u)) == sd:
				mine.append(u)
		var r: Dictionary = spirit_row(mine)
		if not r.is_empty():
			(snap[sd] as Array).append(r)
