class_name InvOps
extends RefCounted
## 背包·装备/卸下/卖出 业务逻辑
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _unequip_at(pet_id: String, cell_idx: int) -> void:
	var eqs: Array = GameState.persistent_equipped.get(pet_id, [])
	if cell_idx < 0 or cell_idx >= eqs.size():
		return
	GameState.persistent_bench.append(eqs[cell_idx])
	eqs.remove_at(cell_idx)
	GameState.persistent_equipped[pet_id] = eqs
	GameState.auto_merge_all()
	GameState.sync_synergy_grants()   # 盾件数可能变了 → 补发/收回圣光护盾
	GameState.save()
	host._rebuild()

## 卸下小将第 cell_idx 件装备 → 回背包.
func _unequip_minion_at(lane: String, idx: int, cell_idx: int) -> void:
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
		return
	var u: Dictionary = a[lane][idx]
	var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
	if cell_idx < 0 or cell_idx >= eqs.size():
		return
	GameState.persistent_bench.append(eqs[cell_idx])
	eqs.remove_at(cell_idx)
	u["equips"] = eqs
	a[lane][idx] = u
	GameState.dual_lineup = a
	GameState.auto_merge_all()
	GameState.sync_synergy_grants()   # 盾件数可能变了 → 补发/收回圣光护盾
	GameState.save()
	host._rebuild()

## 该路首个小将 idx (0统领路首小将=精英)
func _equip_to(pet_id: String, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		host._sel_bench = -1; host._rebuild(); return
	if str((bench[bench_idx] as Dictionary).get("kind", "")) == "item":   # 临时等级器 → 该龟本大轮永久+1级
		GameState.apply_temp_leveler(pet_id)
		GameState.consume_temp_leveler(bench_idx)
		host._sel_bench = -1
		host._toast("临时等级器 → %s 本大轮 +1 级 (现 +%d)" % [pet_id, GameState.temp_level_bonus(pet_id)])
		host._rebuild(); return
	var eqs: Array = GameState.persistent_equipped.get(pet_id, [])
	## ★★【羨绞赠送件】直接放行: 它不占任何容量(见 GameState._cap_count),
	##   所以也不该被"已装满"拦住。
	##   ★★原来的写法把容量检查放在**读取要装哪件之前** —— 于是一只装满 3 件的龟
	##   永远接不了圣光护盾(用户 2026-08-10:「背包里应该不算占位, 怎么满了就不能装」)。
	##   数的时候跳过它、拦的时候却拦它, 两边口径不一致。
	var _grant: bool = GameState.is_synergy_grant(bench[bench_idx])
	# ★装备容量统一规则(2026-07-27): 单只≤3 且 全队合计≤team_equip_cap(赛季等级)。两条都要过。
	#   两种"装不了"的原因必须分别告诉玩家 —— 否则只会觉得"点了没反应"。
	# ★羁绊赠送的装备(圣光护盾)不占单只上限 —— 数的时候要跳过它,
	#   漏了这一处就会出现"明明只装了 2 件却说已装满"。
	if not _grant and GameState._cap_count(eqs) >= host.P2.UNIT_EQUIP_CAP:
		host._sel_bench = -1
		host._toast("这只已装满 %d 件（单只上限）" % host.P2.UNIT_EQUIP_CAP)
		host._rebuild(); return
	if not _grant and not GameState.team_has_equip_room():
		host._sel_bench = -1
		host._toast("全队装备已满 %d/%d · 升赛季等级可再装" % [GameState.team_equipped_count(), GameState.team_equip_cap()])
		host._rebuild(); return
	var item = bench[bench_idx]
	bench.remove_at(bench_idx)
	eqs.append(item)
	GameState.persistent_equipped[pet_id] = eqs
	host._sel_bench = -1
	GameState.auto_merge_all()   # 装上后若凑够3件(背包+龟身)自动合星
	GameState.sync_synergy_grants()   # 盾件数可能变了 → 补发/收回圣光护盾
	GameState.save()
	host._rebuild()

## 小将装备(实时新增): 存 dual_lineup[lane][idx].equips (id共享__minion__进不了persistent_equipped). 战斗端 _spawn_lane_side 读 .equips→_dl_equips 注入.
func _equip_minion(lane: String, idx: int, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		host._sel_bench = -1; host._rebuild(); return
	if str((bench[bench_idx] as Dictionary).get("kind", "")) == "item":   # 临时等级器 → 该小将本大轮永久+1级
		if GameState.apply_temp_leveler_minion(lane, idx):
			GameState.consume_temp_leveler(bench_idx)
			host._toast("临时等级器 → 小将(%s路第%d格) 本大轮 +1 级" % [lane, idx + 1])
		host._sel_bench = -1
		host._rebuild(); return
	var a: Dictionary = GameState.get_dual_lineup().duplicate(true)
	if not a.has(lane) or idx < 0 or idx >= (a[lane] as Array).size():
		host._sel_bench = -1; host._rebuild(); return
	var u: Dictionary = a[lane][idx]
	if str(u.get("kind", "")) != "minion":
		host._sel_bench = -1; host._rebuild(); return
	var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
	## ★★【羨绞赠送件】直接放行: 它不占任何容量(见 GameState._cap_count),
	##   所以也不该被"已装满"拦住。
	##   ★★原来的写法把容量检查放在**读取要装哪件之前** —— 于是一只装满 3 件的龟
	##   永远接不了圣光护盾(用户 2026-08-10:「背包里应该不算占位, 怎么满了就不能装」)。
	##   数的时候跳过它、拦的时候却拦它, 两边口径不一致。
	var _grant: bool = GameState.is_synergy_grant(bench[bench_idx])
	# 小将与统领【同一套容量规则】(用户 2026-07-27:「单只统领或小将的上限固定为3」)
	# ★羁绊赠送的装备(圣光护盾)不占单只上限 —— 数的时候要跳过它,
	#   漏了这一处就会出现"明明只装了 2 件却说已装满"。
	if not _grant and GameState._cap_count(eqs) >= host.P2.UNIT_EQUIP_CAP:
		host._sel_bench = -1
		host._toast("这个小将已装满 %d 件（单只上限）" % host.P2.UNIT_EQUIP_CAP)
		host._rebuild(); return
	if not _grant and not GameState.team_has_equip_room():
		host._sel_bench = -1
		host._toast("全队装备已满 %d/%d · 升赛季等级可再装" % [GameState.team_equipped_count(), GameState.team_equip_cap()])
		host._rebuild(); return
	eqs.append(bench[bench_idx])
	bench.remove_at(bench_idx)
	u["equips"] = eqs
	a[lane][idx] = u
	GameState.dual_lineup = a
	host._sel_bench = -1
	GameState.auto_merge_all()   # 整理背包(小将装的不进合成池, 但背包其余照常3合1)
	GameState.sync_synergy_grants()   # 盾件数可能变了 → 补发/收回圣光护盾
	GameState.save()
	host._rebuild()

func _sell_value(item: Dictionary) -> int:
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(item.get("id", "")), {})
	var cost = maxi(1, int(edef.get("cost", 1)))
	var star = maxi(1, int(item.get("star", 1)))
	return int(floor(cost * star * 0.8))

func _sell_selected() -> void:
	if host._sel_bench < 0 or host._sel_bench >= GameState.persistent_bench.size():
		return
	var _it: Dictionary = GameState.persistent_bench[host._sel_bench]
	## ★羁绊赠送件(圣光护盾)【不能卖】(2026-08-12 实测: 卖它得 0 币、随即被 sync 补发回来,
	##   玩家看到的是"点了卖 → 东西闪一下又回来 → 一分钱没有" —— 那是 bug 观感)。
	##   它的进出只由盾羁绊档位决定(掉档自动收回), 不该出现在交易路径上。
	if GameState.is_synergy_grant(_it):
		host._sel_bench = -1
		host._toast("圣光护盾是羁绊赠送的，不能卖（盾羁绊掉档时会自动收回）")
		host._rebuild()
		return
	GameState.meta_deepsea_coins += _sell_value(_it)
	# ★私人池(2026-08-03 批2·D22): 卖出【按份数退】—— 1★退1 / 2★退3 / 3★退9。
	#   守恒律: 买 9 张合出 3★ 再卖掉, 池子恰好回到原样。退 1 张的话池子会漏水,
	#   而漏水是玩家永远看不见的 bug —— 所以 verify_equip_pool 专门有一条守恒断言。
	GameState.pool_give_back(str(_it.get("id", "")), int(_it.get("star", 1)))
	GameState.persistent_bench.remove_at(host._sel_bench)
	host._sel_bench = -1
	GameState.sync_synergy_grants()   # 盾件数可能变了 → 补发/收回圣光护盾
	GameState.save()
	host._rebuild()

# ============================================================================
#  糖果罐（糖果龟被动 · 局外经济行 · 用户2026-07-07设计）
#  · 大轮开始时若锁定统领含糖果龟 → 拥有 1 个糖果罐
#  · 赢一局计数 +1 / 输一局 +4（逆风快攒）· 封顶 30
#  · 随时可打碎领奖: 计数越高档位越高(6档) → 深海币 + 装备(按档费/星) + 临时等级器(按档概率)
#  · 打碎后本大轮消失
#  逻辑全在 GameState: has_candy_jar / candy_jar_count / candy_jar_tier / break_candy_jar
# ============================================================================
