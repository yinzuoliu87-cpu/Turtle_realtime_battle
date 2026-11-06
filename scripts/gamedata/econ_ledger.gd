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

const REFRESH_COST := 2      # 刷新一次的花费(原 ShopScene.REFRESH_COST, 收到这里: 重放也要用同一个数)
const PRICE_MULT := 1        # 售价 = 装备费用 × 1(原 ShopScene.PRICE_MULT, 用户 2026-07-01)
const SHOP_SLOTS := 10       # 货架格数(roll_shop 的 count 与小木斧每格概率的槽数必须是同一个数)
const AXE_ID := "p2eq_096"
## test_mode 下商店场景第 k 次掷货用 TEST_SHOP_SEED + k(第 0 次与原来 `_rng.seed = 20260819` 掷出来逐件相同,
##   门禁里「数一数货架上有几个 X」的判据不随机红, 理由见 ShopScene._ready 旧注释)。
const TEST_SHOP_SEED := 20260819

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _Phase2Equip := preload("res://scripts/gamedata/phase2_equip.gd")


## 本机掷一个种子(S1)。S3 起改成向服务器要(服务器记账、玩家拿不到后面的种子)。
## ★用 crypto 随机不用 randi(): 后者受 TURTLE_SEED 之类的播种影响(同 GameState.get_install_uid)。
static func draw_seed() -> int:
	return int(Crypto.new().generate_random_bytes(4).decode_u32(0))


## 记账入口: 成功才落一条流水。返回值同 `apply`。
static func do(gs, op: Dictionary) -> Dictionary:
	var r: Dictionary = apply(gs, op)
	if bool(r.get("ok", false)):
		var row: Dictionary = op.duplicate(true)
		row["seq"] = (gs.econ_log as Array).size()
		row["bt"] = int(gs.season_total_battles)
		(gs.econ_log as Array).append(row)
	return r


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
	return {"ok": false, "reason": "unknown_op"}


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
