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

