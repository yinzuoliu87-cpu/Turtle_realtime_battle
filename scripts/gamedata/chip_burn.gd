extends RefCounted
## 筹码(消耗品, 方案书 docs/plans/20261126b-筹码.md): 把穿在统领 / 小将身上的筹码全部拿掉(这一场用掉了), 张数退回卡池(守恒律照旧)。
## 只由 EconLedger._income 在正式对局那一笔进账时调 —— 服务器重放走同一份代码, 两边一定一致。返回烧掉几枚。
## (11-26 从 GameState 搬出: GameState 已到 arch_budget 3000 行上限)
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")


static func burn(gs) -> int:
	var n := 0
	for pid in gs.persistent_equipped.keys():
		var keep: Array = []
		for it in gs.persistent_equipped[pid]:
			if it is Dictionary and _P2T.types_of(str((it as Dictionary).get("id", ""))).has("筹码"):
				gs.pool_give_back(str((it as Dictionary)["id"]), int((it as Dictionary).get("star", 1)))
				n += 1
			else:
				keep.append(it)
		gs.persistent_equipped[pid] = keep
	var a: Dictionary = gs.get_dual_lineup().duplicate(true)
	var changed := false
	for lane in a.keys():
		if not (a[lane] is Array):
			continue
		for u in a[lane]:
			if not (u is Dictionary) or not ((u as Dictionary).get("equips") is Array):
				continue
			var keep2: Array = []
			for it2 in (u as Dictionary)["equips"]:
				if it2 is Dictionary and _P2T.types_of(str((it2 as Dictionary).get("id", ""))).has("筹码"):
					gs.pool_give_back(str((it2 as Dictionary)["id"]), int((it2 as Dictionary).get("star", 1)))
					n += 1
					changed = true
				else:
					keep2.append(it2)
			(u as Dictionary)["equips"] = keep2
	if changed:
		gs.dual_lineup = a
	if n > 0:
		gs.sync_synergy_grants()
	return n
