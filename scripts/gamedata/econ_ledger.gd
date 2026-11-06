extends RefCounted
## 局外经济操作的记账口(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.2 / §4.3)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」—— 擂台赛押主站真币(严格零和),
##   装备 / 深海币却全在客户端存档里, 改存档 = 直接抢钱。
##
## ★做法: 每一笔掷货 / 买 / 刷新 / 锁货架 / 买经验 / 开糖果罐都走 `do(gs, op)`:
##   `apply` 改状态, 成功才往 `gs.econ_log` 追加一条流水(序号 + 当时的 season_total_battles + 操作本身)。
##   服务器(S4)拿同一份流水 + 裁判结果, 用**这同一份代码**从本周开局重放出权威状态, 再与快照比对。
##   ⇒ 不在服务器另抄一份商店(手抄副本必然漂移)。
## ★所有随机都吃 op 里的 `seed`: 本机掷还是服务器发(S3)只是 `draw_seed` 的事; 重放时用流水里记的那个。
## ★`apply` 不碰界面(重放时没有界面); 成交提示 / 选中态 / 重画由调用方(ShopScene)按返回值做。
##
## ══ S2(2026-11-06): 其余写入点全部收进来 ══
##   背包: 穿 / 卸 / 换人 / 卖 / 等级器 / 换位(`econ_inv.gd`) · 小木斧: 选最终造物 / 局内击杀经验 · 换统领后的羁绊赠送件同步
##   收入: 一局的币 / 大轮经验 / 斧头 / 糖果罐 = 一条 `income`(积分赛 / 闯关 / 决赛 / 配额补发 / 陪练号同一种);
##     S4 服务器拿自己的裁判账核这几个数, 客户端说多少不算数。
##   宝箱 / 香火: 战斗里照旧当场写存档(换路要读回来, 那是对局规则的一部分, 不能改);
##     下一次存档 / 记账时发现它们变了 ⇒ 补一条 `prog`(终值)。裁判局的结果单走 `chest` / `incense`。
## ★哨兵(运行时): 每次存档 / 记账之前比一次资产指纹, 与上一笔记账后的不同 = 有人绕过这里改了资产
##   (静态扫描看不见的别名写法: `var b = gs.persistent_bench; b.append(..)`、经函数参数改卡池……)⇒ `econ_drift` +1。
##   只记不拦(S4 上报); 回放 / 切磋 / 裁判机 / 教程这几个沙盒里静音(`econ_quiet` 随沙盒备份一起还原)。

const REFRESH_COST := 2      # 刷新一次的花费(原 ShopScene.REFRESH_COST, 收到这里: 重放也要用同一个数)
const PRICE_MULT := 1        # 售价 = 装备费用 × 1(原 ShopScene.PRICE_MULT, 用户 2026-07-01)
const SHOP_SLOTS := 10       # 货架格数(roll_shop 的 count 与小木斧每格概率的槽数必须是同一个数)
const AXE_ID := "p2eq_096"
## test_mode 下商店场景第 k 次掷货用 TEST_SHOP_SEED + k(第 0 次与原来 `_rng.seed = 20260819` 掷出来逐件相同,
##   门禁里「数一数货架上有几个 X」的判据不随机红, 理由见 ShopScene._ready 旧注释)。
const TEST_SHOP_SEED := 20260819

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _Phase2Equip := preload("res://scripts/gamedata/phase2_equip.gd")
const _Inv := preload("res://scripts/gamedata/econ_inv.gd")


## 本机掷一个种子(S1)。S3 起改成向服务器要(服务器记账、玩家拿不到后面的种子)。
## ★用 crypto 随机不用 randi(): 后者受 TURTLE_SEED 之类的播种影响(同 GameState.get_install_uid)。
static func draw_seed() -> int:
	return int(Crypto.new().generate_random_bytes(4).decode_u32(0))


## 沙盒里(回放 / 切磋 / 裁判机 / 教程): 不记流水、哨兵不响 —— 离场时整份状态还原, 这里发生的都不算数。
static func quiet(gs) -> bool:
	return int(gs.econ_quiet) > 0 or bool(gs.tutorial_active)


## 记账入口: 成功才落一条流水。返回值同 `apply`。
## ★先落流水再改(失败再撤): `apply` 里有几处顺手存盘(糖果罐 / 等级器 / 选最终造物), 那一刻盘上的流水必须已经有这一条,
##   否则恰好在那之后闪退 = 盘上有结果、流水里没有这一笔。
## ★嵌套(apply 里又调到 do)只改不记: 外层那一条重放时会再走一遍里面。
static func do(gs, op: Dictionary) -> Dictionary:
	if int(gs._econ_depth) > 0 or quiet(gs):
		return apply(gs, op)
	check(gs, "do:" + str(op.get("op", "")))
	var led: Array = gs.econ_log
	var row: Dictionary = op.duplicate(true)
	row["seq"] = led.size()
	row["bt"] = int(gs.season_total_battles)
	led.append(row)
	gs._econ_depth = int(gs._econ_depth) + 1
	var r: Dictionary = apply(gs, op)
	gs._econ_depth = int(gs._econ_depth) - 1
	if not bool(r.get("ok", false)):
		led.pop_back()
	rebase(gs)
	return r


# ═════════════════════════════════ 哨兵 ═════════════════════════════════

## 资产(哨兵盯的那部分)规整成一份可比的字典。
##   ★不含: 宝箱 / 香火(战斗工作副本, 见文件头)、装备实例上的 `chg`(香火石充能的旧镜像, 局内写、没人读)、
##     `axe_evo_pending`(进化演出排队, 不是资产)、`meta_shop_battles`(什么时候自动换货的戳)、阵型 / 前后排 / 站位。
##   ★小将按「装了什么 + 临时等级」排序后比(换位不改资产); 卡池按「补齐之后」比(`ensure_equip_pool` 只是把懒补齐落地)。
static func assets_of(gs) -> Dictionary:
	var worn := {}
	if gs.persistent_equipped is Dictionary:
		for pid in gs.persistent_equipped:
			var arr = gs.persistent_equipped[pid]
			if arr is Array and not (arr as Array).is_empty():
				worn[str(pid)] = _items(arr)
	var mins: Array = []
	if gs.dual_lineup is Dictionary:
		for lane in gs.dual_lineup:
			if not (gs.dual_lineup[lane] is Array):
				continue
			for u in gs.dual_lineup[lane]:
				if not (u is Dictionary) or str((u as Dictionary).get("kind", "")) != "minion":
					continue
				var eq: Array = _items((u as Dictionary)["equips"]) if (u as Dictionary).get("equips") is Array else []
				var lv := int((u as Dictionary).get("temp_lv", 0))
				if not eq.is_empty() or lv != 0:
					mins.append(JSON.stringify(_norm({"eq": eq, "lv": lv})))   # 先规整(读档出来的 1.0 与记账口新造的 1 是同一个数)再变字符串
	mins.sort()
	return _norm({
		"coins": gs.meta_deepsea_coins, "bench": _items(gs.persistent_bench), "worn": worn, "minions": mins,
		"pool": _eff_pool(gs), "shop": gs.meta_shop_offer, "lock": gs.meta_shop_locked,
		"lv": gs.season_level, "xp": gs.season_xp, "leaders": gs.season_leaders,
		"axe": [gs.axe_exp_bar, gs.axe_exp_total, gs.axe_stage, str(gs.axe_final), gs.axe_syn_matches],
		"candy": [gs.candy_jar_count, gs.candy_jar_broken], "tl": gs.candy_temp_levels,
	})


## 战斗工作副本(宝箱财宝值 / 已开战利品 / 香火刻痕 / 充能)。
static func progress_of(gs) -> Dictionary:
	return _norm({"cv": gs.chest_treasure_value, "cw": gs.chest_treasures_won,
		"im": gs.incense_marks, "ic": gs.incense_charge})


static func fingerprint(gs) -> String:
	return JSON.stringify(assets_of(gs))


## 以当前状态为起点(读档 / 清档 / 换周 / 每笔记账之后)。
static func rebase(gs) -> void:
	gs._econ_fp = fingerprint(gs)
	gs._econ_prog = JSON.stringify(progress_of(gs))


## 哨兵。资产与上一笔记账后不同 ⇒ `econ_drift` +1(记下在哪、哪几块变了), 以当前为新起点; 返回 false。
##   宝箱 / 香火变了 ⇒ 不算漂移, 补一条 `prog`(终值)。
static func check(gs, where: String) -> bool:
	if quiet(gs) or int(gs._econ_depth) > 0:
		return true
	if str(gs._econ_fp) == "":
		rebase(gs)                    # 还没有起点(刚启动、读档之前)
		return true
	var ok := true
	var fp := fingerprint(gs)
	if fp != str(gs._econ_fp):
		ok = false
		gs.econ_drift = int(gs.econ_drift) + 1
		gs.econ_drift_note = "%s: %s" % [where, ",".join(_diff_keys(str(gs._econ_fp), fp))]
		if OS.has_environment("ECON_DRIFT_LOG"):
			print("[ECON-DRIFT] ", gs.econ_drift_note)
			print_stack()
		gs._econ_fp = fp
	var pg := JSON.stringify(progress_of(gs))
	if pg != str(gs._econ_prog):
		var row: Dictionary = progress_of(gs)
		row["op"] = "prog"
		row["seq"] = (gs.econ_log as Array).size()
		row["bt"] = int(gs.season_total_battles)
		(gs.econ_log as Array).append(row)
		gs._econ_prog = pg
	return ok


static func _diff_keys(a: String, b: String) -> Array:
	var da = JSON.parse_string(a)
	var db = JSON.parse_string(b)
	var out: Array = []
	if da is Dictionary and db is Dictionary:
		for k in db:
			if JSON.stringify(da.get(k)) != JSON.stringify(db[k]):
				out.append(str(k))
	return out


static func _items(arr) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for it in arr:
		if it is Dictionary:
			var d: Dictionary = (it as Dictionary).duplicate(true)
			d.erase("chg")
			out.append(d)
		else:
			out.append(it)
	return out


static func _eff_pool(gs) -> Dictionary:
	var full: Dictionary = EquipPool.full_pool(DataRegistry.phase2_equipment)
	var p: Dictionary = gs.equip_pool if gs.equip_pool is Dictionary else {}
	if p.is_empty():
		return full
	var out: Dictionary = p.duplicate()
	for k in full:
		if not out.has(k):
			out[k] = full[k]
	return out


## 数值规整: 整数值的 float(读档出来的 1.0)当 int, 字典键一律字符串 ⇒ 同一份资产只有一种写法。
static func _norm(v):
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e15:
		return int(roundf(v))
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_norm(x))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _norm(v[k])
		return d
	return v


# ═════════════════════════════════ 操作 ═════════════════════════════════

## 只改状态、不落流水(重放走这个)。`{ok, reason, ...}`; 不认识的操作 ⇒ ok=false。
static func apply(gs, op: Dictionary) -> Dictionary:
	match str(op.get("op", "")):
		"roll":
			return _roll(gs, int(op.get("seed", 0)))
		"refresh":
			if int(gs.meta_deepsea_coins) < REFRESH_COST:
				return {"ok": false, "reason": "coins", "need": REFRESH_COST}
			gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) - REFRESH_COST
			## 刷新顺带解锁(照云顶, 理由见 ShopScene._on_refresh 旧注释)
			gs.meta_shop_locked = false
			return _roll(gs, int(op.get("seed", 0)))
		"lock":
			gs.meta_shop_locked = bool(op.get("on", false))
			## 锁的那一刻把戳对齐当前场次(货架就是本场次的货)
			gs.meta_shop_battles = int(gs.season_total_battles)
			return {"ok": true}
		"buy":
			return _buy(gs, int(op.get("slot", -1)))
		"buy_xp":
			if int(gs.meta_deepsea_coins) < _P2.BUY_XP_COST or int(gs.season_level) >= _P2.MAX_LEVEL:
				return {"ok": false, "reason": "coins" if int(gs.season_level) < _P2.MAX_LEVEL else "max"}
			gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) - _P2.BUY_XP_COST
			gs.add_season_xp(_P2.BUY_XP_AMOUNT)
			return {"ok": true}
		"candy":
			var rw: Dictionary = gs.candy_jar_open_seeded(int(op.get("seed", 0)))
			return {"ok": not rw.is_empty(), "reason": "" if not rw.is_empty() else "no_jar", "reward": rw}
		## ── 背包(S2) ──
		"equip":
			return _Inv.equip(gs, op)
		"unequip":
			return _Inv.unequip(gs, op)
		"move":
			return _Inv.move(gs, op)
		"sell":
			return _Inv.sell(gs, op)
		"leveler":
			return _Inv.leveler(gs, op)
		"swap":
			return _Inv.swap(gs, op)
		"leaders":
			## 锁本大轮的三只统领(选龟页「开始」)。它不是资产, 但羁绊(赠送件 / 斧头独立出货)、糖果罐有没有都看它 ⇒ 重放要有。
			##   换完统领顺手补发 / 收回圣光护盾(2026-08-10: 原来只有装 / 卸 / 卖同步, 换统领这条漏了)。没变就不记。
			var before := fingerprint(gs)
			gs.season_leaders = (op.get("ids", []) as Array).duplicate() if op.get("ids") is Array else []
			gs.sync_synergy_grants()
			return {"ok": fingerprint(gs) != before}
		## ── 小木斧(S2) ──
		"axe_final":
			return {"ok": bool(gs.axe_pick_final(str(op.get("key", ""))))}
		"axe_exp":
			## 局内击杀 / 助攻(AxeSystem.on_death)。一局只有几次, 逐次记。
			var before_axe := [int(gs.axe_exp_total), int(gs.axe_stage)]
			var evolved := bool(gs.axe_add_exp(int(op.get("n", 0))))
			return {"ok": before_axe != [int(gs.axe_exp_total), int(gs.axe_stage)], "evolved": evolved}
		## ── 收入(S2): 服务器 S4 拿裁判账核这几个数 ──
		"income":
			return _income(gs, op)
		"chest":
			return {"ok": _chest(gs, op.get("chest", {}) if op.get("chest") is Dictionary else {})}
		"incense":
			return {"ok": _incense(gs, op.get("inc", {}) if op.get("inc") is Dictionary else {})}
		"prog":
			## 本机打的那一局里宝箱 / 香火的终值(哨兵补记的, 见 check)。
			gs.chest_treasure_value = float(op.get("cv", 0.0))
			gs.chest_treasures_won = (op.get("cw", []) as Array).duplicate() if op.get("cw") is Array else []
			gs.incense_marks = int(op.get("im", 0))
			gs.incense_charge = int(op.get("ic", 0))
			return {"ok": true}
	return {"ok": false, "reason": "unknown_op"}


## 一局(或配额补发)的进账: {src, coins, xp, axe, candy}。
##   coins 深海币 / xp 大轮经验 / axe = 打完一整场的小木斧记账(持有才给经验 + 羁绊局数, 函数里判)/ candy 糖果罐计数。
##   `src` 只是标签(ranked / gauntlet / finals / backfill_* …), S4 按它去对裁判账。全为 0 ⇒ 不成交、不记。
static func _income(gs, op: Dictionary) -> Dictionary:
	var c := maxi(0, int(op.get("coins", 0)))
	var xp := maxi(0, int(op.get("xp", 0)))
	var axe := bool(op.get("axe", false))
	var cj := int(op.get("candy", 0))
	if c == 0 and xp == 0 and not axe and cj == 0:
		return {"ok": false, "reason": "empty"}
	gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) + c
	if xp > 0:
		gs.add_season_xp(xp)
	if axe:
		gs.axe_on_match_end()
	if cj != 0:
		gs.candy_jar_add(cj)
	return {"ok": true, "coins": c}


## 服务器那一局结束时我方宝箱龟的进度(原 RefereeWatch.apply_chest, 2026-10-22b)。
##   裁判机从我交上去的进度起算 ⇒ 它那份正常就是「本地 + 这一局」; 仍只往前走(取大 / 取长),
##   防迟到的回包把本地已经更新的进度倒退回去。返回存档有没有变。
static func _chest(gs, chest: Dictionary) -> bool:
	if chest.is_empty():
		return false
	var changed := false
	var v: float = float(chest.get("value", 0.0))
	if v > float(gs.chest_treasure_value):
		gs.chest_treasure_value = v
		changed = true
	var won: Array = chest.get("won", []) if chest.get("won") is Array else []
	if won.size() > (gs.chest_treasures_won as Array).size():
		gs.chest_treasures_won = won.duplicate()
		changed = true
	return changed


## 服务器那一局结束时我方 093 香火石的刻痕 + 充能(原 RefereeWatch.apply_incense, 2026-10-23)。
##   只往前走: 刻痕多 ⇒ 两个都换; 刻痕一样 ⇒ 充能取大。返回存档有没有变。
static func _incense(gs, inc: Dictionary) -> bool:
	if inc.is_empty():
		return false
	var m: int = int(inc.get("marks", 0))
	var c: int = int(inc.get("charge", 0))
	if m > int(gs.incense_marks):
		gs.incense_marks = m
		gs.incense_charge = c
		return true
	if m == int(gs.incense_marks) and c > int(gs.incense_charge):
		gs.incense_charge = c
		return true
	return false


## 这件装备在商店里卖多少(小木斧随进化变形态与售价, 其余 = 费用 × PRICE_MULT)。与 ShopScene._price(_deco(e)) 同值。
static func price_of(gs, eid: String) -> int:
	var cost: int = 1
	if eid == AXE_ID:
		cost = int(AxeEvolution.display(int(gs.axe_stage), str(gs.axe_final))["cost"])
	else:
		var e = _edef(eid)
		if e is Dictionary:
			cost = int((e as Dictionary).get("cost", 1))
	return maxi(1, cost) * PRICE_MULT


## 玩家已有 3 星(满星)的装备 id 集合(背包 + 统领已装 + 小将已装)→ 掷货时排除(用户 2026-07-18)。
static func maxed_ids(gs) -> Dictionary:
	var s := {}
	for it in gs.persistent_bench:
		if it is Dictionary and int(it.get("star", 1)) >= 3:
			s[str(it.get("id", ""))] = true
	if gs.persistent_equipped is Dictionary:
		for pid in gs.persistent_equipped:
			for it2 in gs.persistent_equipped[pid]:
				if it2 is Dictionary and int(it2.get("star", 1)) >= 3:
					s[str(it2.get("id", ""))] = true
	var lineup: Dictionary = gs.get_dual_lineup()
	for lk in ["top", "bottom"]:
		for u in lineup.get(lk, []):
			if u is Dictionary and u.get("equips") is Array:
				for it3 in u["equips"]:
					if it3 is Dictionary and int(it3.get("star", 1)) >= 3:
						s[str(it3.get("id", ""))] = true
	return s


static func _edef(eid: String):
	for e in DataRegistry.phase2_equipment:
		if str((e as Dictionary).get("id", "")) == eid:
			return e
	return null


## 掷一批货(原 ShopScene._roll 原样搬来, 只把场景里的 `_rng` 换成按 seed 新建的)。写回 gs.meta_shop_offer(只存 id)。
static func _roll(gs, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	## 已 3 星(满星)的装备不再出现在货架(买了也没用·避免占位, 用户 2026-07-18)
	var maxed := maxed_ids(gs)
	var pool: Array = DataRegistry.phase2_equipment
	if not maxed.is_empty():
		pool = []
		for e in DataRegistry.phase2_equipment:
			if not maxed.has(str((e as Dictionary).get("id", ""))):
				pool.append(e)
	## 私人池: 只掷池里还有张的件(抽空与满 3★ 冻结都不出)。上面的满星过滤仍保留, 两者各守各的。
	gs.ensure_equip_pool()
	pool = EquipPool.available(gs.equip_pool, pool)
	## 096 小木斧独立出货通路(三种模式见 AxeEvolution.shelf_mode): 激活羁绊时先从常规池剔掉, 再按每格概率铺回去
	var axe_mode: String = AxeEvolution.shelf_mode(gs.axe_synergy_active(), str(gs.axe_final))
	var axe_def = null
	if axe_mode != "":
		var kept: Array = []
		for e2 in pool:
			if e2 is Dictionary and str((e2 as Dictionary).get("id", "")) == AXE_ID:
				axe_def = e2
			else:
				kept.append(e2)
		pool = kept
	var offer: Array = _Phase2Equip.roll_shop(pool, clampi(int(gs.season_level), 1, 10), SHOP_SLOTS, rng)
	if axe_mode == "indep" and axe_def != null:
		var q: float = AxeEvolution.slot_prob(int(gs.axe_syn_matches), offer.size())
		for i in range(offer.size()):
			if rng.randf() < q:
				offer[i] = axe_def
	var out: Array = []
	for it in offer:
		out.append(null if it == null else {"id": str((it as Dictionary).get("id", ""))})
	gs.meta_shop_offer = out
	gs.meta_shop_battles = int(gs.season_total_battles)
	return {"ok": true}


## 买货架第 `slot` 格(原 ShopScene._on_buy 的记账部分原样搬来)。
static func _buy(gs, slot: int) -> Dictionary:
	var offer: Array = gs.meta_shop_offer
	if slot < 0 or slot >= offer.size() or not (offer[slot] is Dictionary):
		return {"ok": false, "reason": "empty"}
	var eid: String = str((offer[slot] as Dictionary).get("id", ""))
	if _edef(eid) == null:
		return {"ok": false, "reason": "empty"}   # 数据里查无此装备(改过 json)⇒ 与 ShopScene 恢复货架时当空格同口径
	var price: int = price_of(gs, eid)
	if int(gs.meta_deepsea_coins) < price:
		return {"ok": false, "reason": "coins", "need": price - int(gs.meta_deepsea_coins)}
	## 私人池: 先扣张再扣钱 —— 扣不到张就整笔不成交, 不能凭空造张
	if not gs.pool_take(eid, 1):
		return {"ok": false, "reason": "pool"}
	gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) - price
	## 096 小木斧只能有一把; 已有再买 = 整笔化成砍伐经验、不进背包(钱照扣, 用户 2026-08-31)
	var axe_dup := false
	var axe_evolved := false
	if eid == AXE_ID:
		axe_dup = bool(gs.axe_owned())
		axe_evolved = bool(gs.axe_add_exp(AxeEvolution.EXP_ON_BUY, false))
		if not axe_dup:
			gs.persistent_bench.append({"id": eid, "star": 1})
	else:
		gs.persistent_bench.append({"id": eid, "star": 1})
	gs.auto_merge_all()   # 买后自动 3 合 1(背包 + 龟身一起算)
	offer[slot] = null
	gs.meta_shop_offer = offer
	gs.meta_shop_battles = int(gs.season_total_battles)
	return {"ok": true, "id": eid, "price": price, "axe_dup": axe_dup, "axe_evolved": axe_evolved}
