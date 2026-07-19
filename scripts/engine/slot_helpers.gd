class_name SlotHelpers
extends RefCounted
# ══════════════════════════════════════════════════════════
# slot_helpers.gd — 站位/邻接 helper (1:1 移植 PoC slot-helpers.ts → JS engine.js:707-738)
#
# Slot grid (每队): rows front/back × cols 0/1/2, key = "%s-%s" % [row, col].
# Col index 沿屏幕垂直 (col 0 上, col 2 下).
# ⚠ 视觉方向 ≠ 代码命名 (col 索引是纵向, 所以 "column" 在屏上反而是横的):
#   · same_column_fighters (同 col 索引, {front-N, back-N}) = 屏上【横排】(同高度、左右排开, 最多2个)
#   · same_row_fighters    (同 front/back, front-0/1/2)     = 屏上【竖排】(同前/后、上下排开, 3个)
#   判方向永远看坐标 (x=前/后, y=col 索引), 别被 Column/Row 字面带偏。
# "Adjacent" 邻接 = 3×2 网格的四向邻居:
#   · 同 row, col ± 1  (上 / 下)
#   · 对 row, 同 col   (前 / 后)
#
# fighter = Dictionary, key: _slotKey(String "front-1"), side(String), alive(bool), _position(String)
# ══════════════════════════════════════════════════════════


const SLOT_KEYS := ["front-0", "front-1", "front-2", "back-0", "back-1", "back-2"]


# PoC defaultSlotKeys: 前 N 个槽 (3 龟 = front-0/1/2 全前排)
static func default_slot_keys(count: int) -> Array:
	return SLOT_KEYS.slice(0, count)


# PoC autoAssignSlotsForFighters: effHp 降序 + 50/50 A/B 菱形阵; boss 单龟 = front-1
# team = Array[Dictionary] (已建好的 fighter, 读 maxHp + _passive)
static func auto_assign_slots(team: Array) -> Array:
	var n := team.size()
	if n == 1:
		return ["front-1"]
	# 注: 不能给 n==2 加固定特例 (曾自创 front-0/front-2) — PoC 无此分支, 2 龟也走下面 formation
	#   逻辑, 取 formation[0..1] (随 A/B 50/50: front-1,back-0 或 front-0,front-2)。
	# effHp = maxHp (缩头强化召唤 hidingEnhancedSummon ×0.5)
	var eff := func(f: Dictionary) -> int:
		var mh: int = f.get("maxHp", 0)
		return roundi(mh * 0.5) if f.get("_passive", "") == "hidingEnhancedSummon" else mh
	var order: Array = []
	for i in range(n):
		order.append(i)
	order.sort_custom(func(a, b): return eff.call(team[a]) > eff.call(team[b]))
	# 50/50 两种菱形阵: A=front-1/back-0/back-2, B=front-0/front-2/back-1
	var formation := ["front-1", "back-0", "back-2"] if randf() < 0.5 else ["front-0", "front-2", "back-1"]
	# 最高血吃 formation[0]: 按 order(降序)第 k 个 fighter → formation[k]
	var out: Array = []
	out.resize(n)
	for k in range(n):
		out[order[k]] = formation[k]
	return out


# 给一个 slot key, 返回最多 3 个邻接 slot keys
static func adjacent_slots(slot_key: String) -> Array:
	if slot_key == "":
		return []
	var parts := slot_key.split("-")
	if parts.size() < 2:
		return []
	var row: String = parts[0]
	var col := int(parts[1])
	var other := "back" if row == "front" else "front"
	var out: Array = []
	if col > 0:
		out.append("%s-%d" % [row, col - 1])
	if col < 2:
		out.append("%s-%d" % [row, col + 1])
	out.append("%s-%d" % [other, col])
	return out


# 同队中 target 的邻接 alive fighters (不含 target 自己)
static func adjacent_fighters(all_fighters: Array, target: Dictionary) -> Array:
	var tkey: String = target.get("_slotKey", "")
	if tkey == "":
		return []
	var keys := adjacent_slots(tkey)
	var out: Array = []
	for f in all_fighters:
		if f.get("alive", false) and not is_same(f, target) and f.get("side", "") == target.get("side", "") \
				and f.get("_slotKey", "") != "" and keys.has(f.get("_slotKey", "")):
			out.append(f)
	return out


# 给一个 front 排 fighter, 返回它身后的 back 同 col fighter (没有返回 null)
static func fighter_behind(all_fighters: Array, f: Dictionary):
	var key: String = f.get("_slotKey", "")
	if key == "":
		return null
	var parts := key.split("-")
	if parts.size() < 2 or parts[0] != "front":
		return null
	var col: String = parts[1]
	var want := "back-" + col
	for t in all_fighters:
		if t.get("alive", false) and t.get("side", "") == f.get("side", "") and t.get("_slotKey", "") == want:
			return t
	return null


# 给一个 back 排 fighter, 返回它前方的 front 同 col fighter
static func fighter_in_front(all_fighters: Array, f: Dictionary):
	var key: String = f.get("_slotKey", "")
	if key == "":
		return null
	var parts := key.split("-")
	if parts.size() < 2 or parts[0] != "back":
		return null
	var col: String = parts[1]
	var want := "front-" + col
	for t in all_fighters:
		if t.get("alive", false) and t.get("side", "") == f.get("side", "") and t.get("_slotKey", "") == want:
			return t
	return null


# back 排 fighter: 它前面 (same col) 的 front 槽是否空 (无 alive friendly)
static func front_slot_empty(all_fighters: Array, f: Dictionary) -> bool:
	var key: String = f.get("_slotKey", "")
	if key == "":
		return false
	var parts := key.split("-")
	if parts.size() < 2 or parts[0] != "back":
		return false  # 只有 back 排关心前方
	var want := "front-" + String(parts[1])
	for t in all_fighters:
		if t.get("alive", false) and t.get("side", "") == f.get("side", "") and t.get("_slotKey", "") == want:
			return false
	return true


# 同行 (front 或 back) 的所有 alive friendly fighters (含自身) — 屏上竖排
static func same_row_fighters(all_fighters: Array, f: Dictionary) -> Array:
	var key: String = f.get("_slotKey", "")
	if key == "":
		return []
	var row: String = key.split("-")[0]
	var prefix := row + "-"
	var out: Array = []
	for t in all_fighters:
		if t.get("alive", false) and t.get("side", "") == f.get("side", "") \
				and String(t.get("_slotKey", "")).begins_with(prefix):
			out.append(t)
	return out


# 同列 (col 0/1/2) 的所有 alive friendly fighters (含自身) — 屏上横排, {front-N, back-N}
static func same_column_fighters(all_fighters: Array, f: Dictionary) -> Array:
	var key: String = f.get("_slotKey", "")
	if key == "":
		return []
	var parts := key.split("-")
	if parts.size() < 2:
		return []
	var col: String = parts[1]
	var suffix := "-" + col
	var out: Array = []
	for t in all_fighters:
		if t.get("alive", false) and t.get("side", "") == f.get("side", "") \
				and String(t.get("_slotKey", "")).ends_with(suffix):
			out.append(t)
	return out


# 敌方"可见目标": 默认前排 alive 都算 front 守门. 若敌方前排无 alive, 所有 back 暴露.
# 返回排序后的目标列表 (front 优先, 同排按 slot 0/1/2). 排除 _untargetable.
static func visible_enemy_targets(all_fighters: Array, attacker: Dictionary) -> Array:
	var enemies: Array = []
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != attacker.get("side", "") \
				and not f.get("_untargetable", false):
			enemies.append(f)
	var front_alive: Array = []
	for e in enemies:
		if String(e.get("_slotKey", "")).begins_with("front-"):
			front_alive.append(e)
	var pool := front_alive if front_alive.size() > 0 else enemies
	pool.sort_custom(func(a, b): return String(a.get("_slotKey", "")) < String(b.get("_slotKey", "")))
	return pool
