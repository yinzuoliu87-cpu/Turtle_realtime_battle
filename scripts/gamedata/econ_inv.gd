extends RefCounted
## 背包操作的记账部分(方案书 docs/plans/20261106-装备与深海币服务器记账.md S2)。只给 `EconLedger.apply` 调。
##
## 原来写在 `scripts/scenes/inventory/equip_ops.gd`(界面层)里, 直接改 GameState ⇒ 服务器重放看不见。
## ★原样搬来(判序 / 容量口径 / 自动合成 / 羁绊赠送件同步一处不改), 只把「弹提示 / 选中态 / 重画」留在界面:
##   这里返回 `{ok, reason}`, 界面按 reason 出那几句原话(「装备栏已满」「全队装备已达上限」「羁绊赠送装备不可出售」)。
## ★小将按「哪一路第几格」寻址 ⇒ 背包里两张单位卡换位(`swap`)也要进流水, 否则重放时同一个地址是另一只小将。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")


static func _bad() -> Dictionary:
	return {"ok": false, "reason": "bad"}


## 背包第 bi 格是不是临时等级器(消耗品, 不当装备穿)。
static func is_leveler(gs, bi: int) -> bool:
	var bench: Array = gs.persistent_bench
	if bi < 0 or bi >= bench.size() or not (bench[bi] is Dictionary):
		return false
	return str((bench[bi] as Dictionary).get("kind", "")) == "item"


## 单位身上那几件(统领住 persistent_equipped[id], 小将住阵容里的 equips; 同 InventoryScene._unit_equips 的二分)。
static func unit_equips(gs, u: Dictionary) -> Array:
	if str(u.get("kind", "")) == "leader":
		if gs.persistent_equipped is Dictionary:
			var pe = gs.persistent_equipped.get(str(u.get("id", "")), [])
			return pe if pe is Array else []
		return []
	return u.get("equips", []) if u.get("equips", null) is Array else []


## 卖价(★单一事实源 = Phase2Config.sell_value(); 原 InvOps._sell_value, 理由见那边旧注释:
##   原来手写 `int(floor(cost * star * 0.8))` ⇒ 1费1★ 卖 0)。
static func sell_value(item: Dictionary) -> int:
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(item.get("id", "")), {})
	var cost = maxi(1, int(edef.get("cost", 1)))
	var star = maxi(1, int(item.get("star", 1)))
	return int(_P2.sell_value(int(cost), int(star)))


## 穿: {pid, bench} 给统领 / {lane, idx, bench} 给小将。
## ★羁绊赠送件(圣光护盾)不占容量 ⇒ 也不被「已装满」拦(用户 2026-08-10「背包里应该不算占位, 怎么满了就不能装」)。
## ★两种装不了要分开说(单只 3 件 / 全队按大轮等级), 判序与原来一致: 先单只、后全队。
static func equip(gs, op: Dictionary) -> Dictionary:
	var bench: Array = gs.persistent_bench
	var bi := int(op.get("bench", -1))
	if bi < 0 or bi >= bench.size() or is_leveler(gs, bi):
		return _bad()
	var grant: bool = gs.is_synergy_grant(bench[bi])
	if op.has("pid"):
		var pid := str(op["pid"])
		var eqs: Array = gs.persistent_equipped.get(pid, [])
		var why := _room(gs, eqs, grant)
		if why != "":
			return {"ok": false, "reason": why}
		var item = bench[bi]
		bench.remove_at(bi)
		eqs.append(item)
		gs.persistent_equipped[pid] = eqs
	else:
		var lane := str(op.get("lane", ""))
		var idx := int(op.get("idx", -1))
		var a: Dictionary = gs.get_dual_lineup().duplicate(true)
		if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
			return _bad()
		var u: Dictionary = a[lane][idx]
		if str(u.get("kind", "")) != "minion":
			return _bad()
		var meqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
		var why2 := _room(gs, meqs, grant)
		if why2 != "":
			return {"ok": false, "reason": why2}
		meqs.append(bench[bi])
		bench.remove_at(bi)
		u["equips"] = meqs
		a[lane][idx] = u
		gs.dual_lineup = a
	gs.auto_merge_all()           # 装上后若凑够 3 件(背包 + 身上)自动合星
	gs.sync_synergy_grants()      # 盾件数可能变了 → 补发 / 收回圣光护盾
	return {"ok": true}


## "" = 装得下; 否则 "full"(单只 3 件)/ "team_full"(全队按大轮等级)。
static func _room(gs, eqs: Array, grant: bool) -> String:
	if grant:
		return ""
	if gs._cap_count(eqs) >= _P2.UNIT_EQUIP_CAP:
		return "full"
	if not gs.team_has_equip_room():
		return "team_full"
	return ""


## 卸: {pid, cell} / {lane, idx, cell} → 回背包。
static func unequip(gs, op: Dictionary) -> Dictionary:
	var cell := int(op.get("cell", -1))
	if op.has("pid"):
		var pid := str(op["pid"])
		var eqs: Array = gs.persistent_equipped.get(pid, [])
		if cell < 0 or cell >= eqs.size():
			return _bad()
		gs.persistent_bench.append(eqs[cell])
		eqs.remove_at(cell)
		gs.persistent_equipped[pid] = eqs
	else:
		var lane := str(op.get("lane", ""))
		var idx := int(op.get("idx", -1))
		var a: Dictionary = gs.get_dual_lineup().duplicate(true)
		if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
			return _bad()
		var u: Dictionary = a[lane][idx]
		var meqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
		if cell < 0 or cell >= meqs.size():
			return _bad()
		gs.persistent_bench.append(meqs[cell])
		meqs.remove_at(cell)
		u["equips"] = meqs
		a[lane][idx] = u
		gs.dual_lineup = a
	gs.auto_merge_all()
	gs.sync_synergy_grants()
	return {"ok": true}


## 一件装备从一只单位直接挪到另一只(拖拽「换人」, 2026-10-22): {sl, si, cell, dl, di}。
## ★不走「卸下 → 再装上」两步(卸下会进背包并 auto_merge_all, 可能当场被合掉, 第二步装上的就是别的东西)。
## ★全队件数不变 ⇒ 只查目标自己的 3 件上限; 羁绊赠送件不占容量照旧放行。占位统领(没有真龟)不收。
static func move(gs, op: Dictionary) -> Dictionary:
	var sl := str(op.get("sl", ""))
	var si := int(op.get("si", -1))
	var dl := str(op.get("dl", ""))
	var di := int(op.get("di", -1))
	var cell := int(op.get("cell", -1))
	if sl == dl and si == di:
		return _bad()
	var a: Dictionary = gs.get_dual_lineup().duplicate(true)
	if not a.has(sl) or not a.has(dl):
		return _bad()
	var sarr: Array = a[sl]
	var darr: Array = a[dl]
	if si < 0 or si >= sarr.size() or di < 0 or di >= darr.size():
		return _bad()
	var su: Dictionary = sarr[si]
	var du: Dictionary = darr[di]
	if str(du.get("kind", "")) == "leader" and str(du.get("id", "")) == "":
		return _bad()
	var s_eqs: Array = unit_equips(gs, su).duplicate()
	if cell < 0 or cell >= s_eqs.size():
		return _bad()
	var item = s_eqs[cell]
	var d_eqs: Array = unit_equips(gs, du).duplicate()
	if not gs.is_synergy_grant(item) and gs._cap_count(d_eqs) >= _P2.UNIT_EQUIP_CAP:
		return {"ok": false, "reason": "full"}
	s_eqs.remove_at(cell)
	d_eqs.append(item)
	_write_equips(gs, a, sl, si, su, s_eqs)
	_write_equips(gs, a, dl, di, du, d_eqs)
	gs.dual_lineup = a
	gs.auto_merge_all()
	gs.sync_synergy_grants()
	return {"ok": true}


static func _write_equips(gs, a: Dictionary, lane: String, idx: int, u: Dictionary, eqs: Array) -> void:
	if str(u.get("kind", "")) == "leader":
		gs.persistent_equipped[str(u.get("id", ""))] = eqs
	else:
		u["equips"] = eqs
		a[lane][idx] = u


## 卖: {bench}。★羁绊赠送件不能卖(2026-08-12 实测: 卖它得 0 币、随即被 sync 补发回来 —— 「点了卖 → 闪一下又回来」)。
## ★私人池按份数退(D22: 1★退1 / 2★退3 / 3★退9 —— 买 9 张合出 3★ 再卖掉, 池子恰好回到原样)。
static func sell(gs, op: Dictionary) -> Dictionary:
	var bi := int(op.get("bench", -1))
	if bi < 0 or bi >= (gs.persistent_bench as Array).size() or not (gs.persistent_bench[bi] is Dictionary):
		return _bad()
	var it: Dictionary = gs.persistent_bench[bi]
	if gs.is_synergy_grant(it):
		return {"ok": false, "reason": "grant"}
	var v := sell_value(it)
	gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) + v
	gs.pool_give_back(str(it.get("id", "")), int(it.get("star", 1)))
	gs.persistent_bench.remove_at(bi)
	gs.sync_synergy_grants()      # 盾件数可能变了 → 补发 / 收回圣光护盾
	return {"ok": true, "coins": v}


## 用临时等级器: {pid, bench} 统领(记在 candy_temp_levels) / {lane, idx, bench} 小将(记在那一格的 temp_lv)。
static func leveler(gs, op: Dictionary) -> Dictionary:
	var bi := int(op.get("bench", -1))
	if not is_leveler(gs, bi) or str((gs.persistent_bench[bi] as Dictionary).get("id", "")) != str(gs.TEMP_LEVELER_ID):
		return _bad()
	if op.has("pid"):
		gs.apply_temp_leveler(str(op["pid"]))
	elif not gs.apply_temp_leveler_minion(str(op.get("lane", "")), int(op.get("idx", -1))):
		return _bad()
	gs.consume_temp_leveler(bi)
	return {"ok": true}


## 两张单位卡互换(跨路 / 同路都行): {sl, si, dl, di}。不改资产, 只改小将的地址(见文件头)。
static func swap(gs, op: Dictionary) -> Dictionary:
	var sl := str(op.get("sl", ""))
	var si := int(op.get("si", -1))
	var dl := str(op.get("dl", ""))
	var di := int(op.get("di", -1))
	if sl == dl and si == di:
		return _bad()
	var a: Dictionary = gs.get_dual_lineup().duplicate(true)
	if not a.has(sl) or not a.has(dl) or si < 0 or si >= (a[sl] as Array).size() or di < 0 or di >= (a[dl] as Array).size():
		return _bad()
	var tmp = a[sl][si]
	a[sl][si] = a[dl][di]
	a[dl][di] = tmp
	gs.dual_lineup = a
	return {"ok": true}
