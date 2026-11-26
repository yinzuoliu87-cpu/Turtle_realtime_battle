class_name WeeklySynergy
extends RefCounted
## 本周羁绊: 16 个大羁绊每周纯随机抽 10 个, 当周商店只出这 10 个羁绊的装备(方案书 docs/plans/20261124d-16羁绊每周轮换.md §4.2)。
##
## 用户 11-24:「每次抽的话是十六个抽十个羁绊嘛」「轮换的话…纯随机就好了」; 11-26 第 6 个由乐器换成长矛(方案书 20261126)。
##
## ★纯函数(照 WeeklyFree): 不读钟、不读档、不用引擎随机。排序键 = FNV-1a 32 位("周锚点|羁绊名"), 全服同一份;
##   同键再按羁绊名逐码点比。门禁 verify_weekly_synergy 拿独立 Python 实现(tools/weekly_synergy_gold.py)算的金标比。
## ★小木斧(斧头)、香火石(香火)、仪式匕首里的「仪式」不算大羁绊 —— 只属于非大羁绊类型的件永远可以出。
## ★商店池版本(EconLedger.POOL_VER): 经济流水里每条记当时客户端的池版本。版本 1(0.23.5 及以前, 流水里没有 pv)= 老池:
##   只有 001~096、不轮换 —— 换版当天(周一 00:00 换周 ~ 21:00 换版)老客户端掷的货, 服务器用新代码重放也对得上
##   (经济方案书 20261106 R10「经济规则改动不在周中上」, 这一版不得不在周中上, 靠版本号兜住)。
const ALL: Array[String] = ["剑", "盾", "枪", "弓箭", "法器", "灵物", "奇械", "食物", "遗物", "药水",
	"匕首", "魔法书", "面具", "筹码", "炸弹", "长矛"]
const COUNT := 10
## 池版本 1 的最后一件(0.23.5 正式服商店 95 件 = p2eq_001 ~ p2eq_096; 2026-11-26 从 v0.23.5 标签里的装备表数过)
const LEGACY_LAST := 96
## 从这一周起轮换(含)。0 = 有池版本 2 的流水就轮换。
const START_WEEK := 0
## 上线那一周(2026-11-30 周一 00:00 UTC)保底: 6 个新羁绊全在, 另 4 个从 10 个老羁绊里按同一排序键取前 4。
##   11-27 自查: 纯随机这一周抽不到面具 / 炸弹 / 长矛(面具和炸弹要连缺 4 周); 用户 11-27「直接做就好了呀」⇒ 按我的建议上线周强制。之后各周照旧纯随机。
const LAUNCH_WEEK := 1795996800
const LAUNCH_NEW: Array[String] = ["匕首", "魔法书", "面具", "筹码", "炸弹", "长矛"]

const _P2T := preload("res://scripts/gamedata/phase2_types.gd")


## 这一周的 10 个(按排序先后)。周锚点 ≤ 0(没有周 —— 演示台 / 门禁 / 裁判沙盒)⇒ 16 个全在。
static func of_week(week_anchor: int) -> Array:
	if week_anchor <= 0 or week_anchor < START_WEEK:
		return ALL.duplicate()
	var keyed: Array = []
	var launch: bool = week_anchor == LAUNCH_WEEK
	for t in ALL:
		if launch and LAUNCH_NEW.has(t):
			continue
		keyed.append([WeeklyFree.fnv1a32("%d|%s" % [week_anchor, t]), t])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1])))
	var out: Array = []
	if launch:
		out = LAUNCH_NEW.duplicate()
	for i in range(COUNT - out.size()):
		out.append(str(keyed[i][1]))
	return out


static func _num(eid: String) -> int:
	return int(eid.trim_prefix("p2eq_")) if eid.begins_with("p2eq_") else 0


## 这件装备这一周(在这个池版本下)能不能出。
static func pool_ok(eid: String, week_anchor: int, pv: int) -> bool:
	if pv < 2:
		return _num(eid) <= LEGACY_LAST
	var types: Array = _P2T.types_of(eid)
	var big: Array = []
	for t in types:
		if ALL.has(str(t)):
			big.append(str(t))
	if big.is_empty():
		return true          # 只属于非大羁绊类型(小木斧 / 香火石 …): 不参与轮换
	var wk: Array = of_week(week_anchor)
	for t in big:
		if wk.has(t):
			return true      # 一件属于多个羁绊: 有一个在本周就能出(方案书 §4.2)
	return false


## 对局里随机给装备(宝箱龟 / 魔法海螺)用: 对局永远按当前代码的池版本(= EconLedger.POOL_VER, verify_weekly_synergy 核两边相等)。
const BATTLE_PV := 2


static func battle_ok(eid: String, week_anchor: int) -> bool:
	return pool_ok(eid, week_anchor, BATTLE_PV)


## 过滤一份装备定义表(Array of Dictionary)。
static func filter_defs(defs: Array, week_anchor: int, pv: int) -> Array:
	var out: Array = []
	for e in defs:
		if e is Dictionary and pool_ok(str((e as Dictionary).get("id", "")), week_anchor, pv):
			out.append(e)
	return out
