class_name HpLines
extends RefCounted

## hp_lines.gd — 【多条血线阈值】基建（2026-08-05）
##
## ★为什么要它：
##   既有的 `_eq_check_hp_threshold` 是**写死一条 50% 线**的（`hp50_fired` 单标记 + 硬编码
##   `u["hp"] > u["maxHp"] * 0.5`），只够 044 深海项链 / 045 珍珠耳环用。
##
##   2026-08-05 用户重做装备后，一口气出现**多件要多条线**：
##     · 069 珊瑚糖糕 —— 三块糕分别在 **<80% / <55% / <30%** 首次跌破时吃
##     · 064 溺者的浮囊 —— **<35%** 一道
##     · 091（明天再定）—— 方案书 B 组提案也是三道线
##   再往 `_eq_check_hp_threshold` 里塞 `hp80_fired` / `hp55_fired` / `hp30_fired`
##   这种标记就是灾难（每加一件多三个字段，而且 044/045 那条 50% 的逻辑会被越挤越乱）。
##
## ★与既有那条 50% 线的关系：**并存，互不干扰**。
##   老的继续管 044/045，本层管新装备。等以后有空再把老的迁过来（现在不动，避免动到
##   正在被并行改的 equip_system.gd）。
##
## ★每路重置：注册表存在本对象上，`clear_all()` 由换路流程调用 —— 与
##   `SpecialBalance` 同一处清理点。这正是用户定的「每路一次」口径。

var battle
## uid → { key(String) → { "frac": float, "cb": Callable, "fired": bool } }
var _lines: Dictionary = {}
var _next_uid: int = 1


func _init(b) -> void:
	battle = b


## ★不能拿单位字典当 key（CLAUDE.md §3.2：Godot 递归哈希 + 单位字典互引成环 → 卡死）
func _uid(u: Dictionary) -> String:
	if not u.has("_hpl_uid"):
		u["_hpl_uid"] = "hl%d" % _next_uid
		_next_uid += 1
	return str(u["_hpl_uid"])


## 注册一条阈值线。生命百分比**首次**跌破 frac 时回调一次（本路一次；换路自动重置）。
## key 自取唯一串，建议 "<装备id>_<第几道>"，例：`"p2eq_069_l1"`。
## 同一个 key 重复注册只保留第一次（不会重置 fired）。
func add(u: Dictionary, key: String, frac: float, cb: Callable) -> void:
	var uid: String = _uid(u)
	if not _lines.has(uid):
		_lines[uid] = {}
	var slot: Dictionary = _lines[uid]
	if slot.has(key):
		return
	slot[key] = {"frac": frac, "cb": cb, "fired": false, "u": u}


## 这条线触发过没有（给装备侧查"第几块糕吃掉了"用）
func fired(u: Dictionary, key: String) -> bool:
	var uid: String = str(u.get("_hpl_uid", ""))
	if uid == "" or not _lines.has(uid):
		return false
	var slot: Dictionary = _lines[uid]
	return slot.has(key) and bool(slot[key]["fired"])


## 【伤害路径调用】血量变化后检查。已在 battle_damage.gd 的 HP 阈值处接好。
## ★按 frac 从**高到低**依次判：一次掉血跌穿多条线时，三条会**按顺序全部触发**
##   （069 明确要求"掉血够快会一口气吃完三块"）。
func check(u: Dictionary) -> void:
	if not u.get("alive", false):
		return
	var uid: String = str(u.get("_hpl_uid", ""))
	if uid == "" or not _lines.has(uid):
		return
	var slot: Dictionary = _lines[uid]
	if slot.is_empty():
		return
	var mh: float = maxf(1.0, float(u.get("maxHp", 1.0)))
	var f: float = float(u.get("hp", 0.0)) / mh
	# 高线先触发 —— 顺序确定，门禁可验
	var keys: Array = slot.keys()
	keys.sort_custom(func(a, b): return float(slot[a]["frac"]) > float(slot[b]["frac"]))
	for k in keys:
		var e: Dictionary = slot[k]
		if bool(e["fired"]) or f > float(e["frac"]):
			continue
		e["fired"] = true
		var cb = e["cb"]
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(u, str(k))


## 换路 / 清场 —— 这就是「每路一次」口径的落点
func clear_all() -> void:
	_lines.clear()
