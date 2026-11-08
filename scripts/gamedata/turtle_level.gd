class_name TurtleLevel
extends RefCounted
## 按龟等级（R1）与龟的经验曲线 —— 方案书 docs/plans/20261107b-龟等级与经验.md、20261105c-主站对接偷袭.md §4.2。
##
## ══════════════════════════════════════════════════════════════════════
##  两个「等级」
## ══════════════════════════════════════════════════════════════════════
##   · 龟等级（本文件）：每只龟 1 ~ 10 级，永久，打周赛涨经验（服务器发，迁移 20261109b `pet_xp_grant`）。
##     管：这只龟的主属性每级 +5%（`UnitScaling.level_multiplier`）、它的装备固定加值 / 固定召唤物；三只统领的平均管龟蛋血量。
##   · 赛季等级（GameState.season_level / 快照 season_level，每周清零）：只剩全队装备格数、小将等级。
##
## ══════════════════════════════════════════════════════════════════════
##  lv 表（快照 `lv` / GameState.pet_lv）
## ══════════════════════════════════════════════════════════════════════
##   {pet_key: 1 ~ 10}。**非空 = 这一方按龟等级**（表里没有的龟按 1 级）；**空 / 没有 = 旧快照 ⇒ 退回整队等级**（逐位同改之前）。
##   · 右方：对手快照的 `lv`（`build_ghost_snapshot` 写三只统领；服务器裁判开算时按服务器等级表覆盖，迁移 20261109b `pet_stamp_snapshot`）。
##   · 左方：GameState.pet_lv（本机 = 服务器等级的缓存，`PetLevelsNet` 写 28 只全表；裁判机 = A 快照的 `lv`，`RefereeJob.state_for`）。
##     它在录像 STATE_KEYS 里 ⇒ 回放照样复现。

const MAX := 10
## 一局周赛上场的三只统领各得（用户 11-07）
const WIN_XP := 8
const LOSE_XP := 6


## 升到 lv 级要的累计经验：N 级升 N+1 级要 50 + 20 × N（主站原曲线，用户 11-07「升级曲线没问题」）。
##   2 级 70 / 3 级 160 / … / 10 级 1350。
static func xp_to_reach(lv: int) -> int:
	var l := clampi(lv, 1, MAX)
	return (l - 1) * (50 + 10 * l)


## 累计经验 → 等级（1 ~ 10）。
static func level_for_xp(xp: int) -> int:
	var lv := 1
	while lv < MAX and xp >= xp_to_reach(lv + 1):
		lv += 1
	return lv


## 满级累计经验（满级后不再累计）
static func xp_cap() -> int:
	return xp_to_reach(MAX)


## 快照 / GameState 里的 lv 表 → 规整后的 {pet: 1 ~ 10}。不是字典 / 空 ⇒ {}（= 没有按龟等级）。
##   快照是别人传上来的 ⇒ 只认字符串键、数字值，一律夹到 1 ~ MAX。
static func table_of(v) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in (v as Dictionary):
		var x = (v as Dictionary)[k]
		if (k is String or k is StringName) and (x is int or x is float):
			out[str(k)] = clampi(int(x), 1, MAX)
	return out


## 表里这只龟的等级；表空 / 没给龟 ⇒ -1（调用方退回整队等级）。表里没有的龟 = 1。
static func level_in(table: Dictionary, pid: String) -> int:
	if table.is_empty() or pid == "":
		return -1
	return clampi(int(table.get(pid, 1)), 1, MAX)


## 一方的 lv 表：左 = GameState.pet_lv；右 = 对手快照 dual_ghost 的 lv（只在双路模式，同 `_unit_level` 右方原来的口径）。
static func side_table(gs, side: String, dual: bool) -> Dictionary:
	if gs == null:
		return {}
	if side == "left":
		return table_of(gs.get("pet_lv"))
	if not dual:
		return {}
	var g = gs.get("dual_ghost")
	return table_of((g as Dictionary).get("lv", null)) if g is Dictionary else {}


## 这一方这只龟的龟等级；这一方没有 lv 表 ⇒ -1。
static func level_of(gs, side: String, pid: String, dual: bool) -> int:
	if pid == "":
		return -1
	return level_in(side_table(gs, side, dual), pid)


## 单位 → 查 lv 表用的龟 id：统领 = 自己；召唤物 = 顺着主人找到统领；小将 / 龟蛋 / 大师 = ""（整队等级）。
static func pid_of(u: Dictionary) -> String:
	var cur: Dictionary = u
	for _i in range(4):
		if not bool(cur.get("is_summon", false)):
			break
		var o = cur.get("summon_owner", null)
		if not (o is Dictionary):
			return ""
		cur = o
	if bool(cur.get("is_summon", false)) or bool(cur.get("_isMinion", false)) or bool(cur.get("_isEgg", false)) \
			or bool(cur.get("is_trainer", false)):
		return ""
	return str(cur.get("id", ""))


## 查哪一方的 lv 表(""= 单位自己那一方): 驯服过来进终极战场的龟带 lv_side(原主人那一方); 召唤物按主人。
static func table_side_of(u: Dictionary) -> String:
	var cur: Dictionary = u
	for _i in range(4):
		if not bool(cur.get("is_summon", false)):
			break
		var o = cur.get("summon_owner", null)
		if not (o is Dictionary):
			return ""
		cur = o
	return str(cur.get("lv_side", ""))


## 龟蛋按几级算：这一方按龟等级 ⇒ 三只统领的平均（四舍五入，整数算法：(2 × 和 + 只数) / (2 × 只数)）；没有 lv 表 ⇒ fallback。
static func egg_level(table: Dictionary, leaders: Array, fallback: int) -> int:
	if table.is_empty() or leaders.is_empty():
		return fallback
	var s := 0
	for p in leaders:
		s += level_in(table, str(p))
	var n := leaders.size()
	return clampi((2 * s + n) / (2 * n), 1, MAX)


## 快照用：这几只统领各自的等级（mine = 本机的 lv 表；表空 ⇒ {}，快照不带 lv = 旧口径）。
static func snapshot_table(leaders: Array, mine: Dictionary) -> Dictionary:
	if mine.is_empty():
		return {}
	var out := {}
	for p in leaders:
		out[str(p)] = maxi(1, level_in(mine, str(p)))
	return out


## 客户端缓存：28 只全表 —— 拥有的按服务器等级（没有记录 = 1），其余 1。
static func full_table(owned: Array, levels: Dictionary) -> Dictionary:
	var own := {}
	for p in owned:
		own[str(p)] = true
	var lv := table_of(levels)
	var out := {}
	for pid in WeeklyFree.ALL:
		out[pid] = int(lv.get(pid, 1)) if own.has(pid) else 1
	return out
