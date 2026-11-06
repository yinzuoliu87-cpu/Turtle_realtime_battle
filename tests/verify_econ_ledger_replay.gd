extends Node
## verify_econ_ledger_replay —— 局外经济流水重放(方案书 docs/plans/20261106-装备与深海币服务器记账.md §6 第一条, S1)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」服务器要能拿玩家的经济流水,
##   用同一份代码从本周开局重放出一模一样的深海币 / 背包 / 身上装备 / 货架 / 卡池 / 大轮等级 / 小木斧 / 糖果罐。
##
## 判据(全走真入口: 商店场景的按钮回调 + GameState 的买经验 / 开糖果罐):
##   ① 分母: 每种操作都真发生过(掷货 ≥ 2、买 ≥ 2、刷新、锁 / 解锁、买经验、开罐)
##   ② 把状态退回开局, 只按 `GameState.econ_log` 逐条 `EconLedger.apply` ⇒ 每条都成交, 结果与本机逐字节相同
##   ③ 再重放一遍 ⇒ 与第一遍逐字节相同(确定性)
##   ④ ★反向: 把第一条掷货的种子 +1 再重放 ⇒ 结果必须不同(证明 ② 不是恒真式: 种子真的决定了货架)
## 反向验证(手工, 见方案书): 把 EconLedger._roll 里的 rng.randf() 换成全局 randf() ⇒ ② 红。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
## 进账本的字段(方案书 §2.3; meta_shop_battles 是「什么时候自动换货」的戳, 不是资产, 不比)
const KEYS := ["meta_deepsea_coins", "persistent_bench", "persistent_equipped", "dual_lineup", "equip_pool",
	"meta_shop_offer", "meta_shop_locked", "season_level", "season_xp",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches", "axe_evo_pending",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels"]

var _fails := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _snap() -> Dictionary:
	var d := {}
	for k in KEYS:
		var v = GameState.get(k)
		d[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


func _put(d: Dictionary) -> void:
	for k in KEYS:
		var v = d[k]
		GameState.set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)


## 从开局状态按流水重放, 返回 [结束状态, 不成交的那几条]
func _replay(start: Dictionary, log: Array) -> Array:
	_put(start)
	var bad: Array = []
	for op in log:
		GameState.season_total_battles = int((op as Dictionary).get("bt", 0))   # 与对局交错的位置(换货戳 / 锁戳读它)
		var r: Dictionary = EL.apply(GameState, op)
		if not bool(r.get("ok", false)):
			bad.append("%s#%s:%s" % [str(op.get("op", "")), str(op.get("seq", "")), str(r.get("reason", ""))])
	return [_snap(), bad]


func _ready() -> void:
	var gs = GameState
	gs.test_mode = true   # save() 不落盘; 商店用固定种子序列
	## 本周开局: 打过 3 场、Lv3、500 深海币、统领含糖果龟(有罐, 25 点)
	gs.econ_log = []
	gs.season_total_battles = 3
	gs.meta_deepsea_coins = 500
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.equip_pool = {}
	gs.meta_shop_offer = []
	gs.meta_shop_battles = -1
	gs.meta_shop_locked = false
	gs.season_level = 3
	gs.season_xp = 0
	gs.axe_exp_bar = 0
	gs.axe_exp_total = 0
	gs.axe_stage = 0
	gs.axe_final = ""
	gs.axe_evo_pending = []
	gs.season_leaders = ["candy", "stone", "ice"]
	gs.candy_jar_count = 25
	gs.candy_jar_broken = false
	gs.candy_temp_levels = {}
	var start := _snap()

	## ── 真入口操作 ──
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)                                   # _ready: 场次变了 ⇒ 掷货(roll)
	var bought := 0
	for i in range(10):
		if bought >= 2:
			break
		if i < shop._offer.size() and shop._offer[i] != null:
			var c0: int = int(gs.meta_deepsea_coins)
			shop._on_buy(i)
			if int(gs.meta_deepsea_coins) < c0:
				bought += 1
	shop._on_toggle_lock()                            # 锁
	shop._on_toggle_lock()                            # 解锁
	shop._on_refresh()                                # 扣 2 + 掷新货
	for i2 in range(10):
		if i2 < shop._offer.size() and shop._offer[i2] != null:
			shop._on_buy(i2)
			break
	shop._on_buy_xp()                                 # GameState.buy_season_xp
	shop.queue_free()
	gs.break_candy_jar()                              # 开罐(种子记进流水)
	gs.season_total_battles = 4                       # 打完一场, 再进店 ⇒ 自动换货
	var shop2 = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop2)
	shop2.queue_free()

	var live := _snap()
	var log: Array = (gs.econ_log as Array).duplicate(true)

	## ① 分母
	var kinds := {}
	for op in log:
		var k := str((op as Dictionary).get("op", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("  流水 %d 条: %s" % [log.size(), str(kinds)])
	_ok("① 分母: 掷货 ≥ 2(进店一次 + 打完一场再进店一次)", int(kinds.get("roll", 0)) >= 2, str(kinds))
	_ok("① 分母: 买 ≥ 2", int(kinds.get("buy", 0)) >= 2, str(kinds))
	_ok("① 分母: 刷新 / 锁 / 买经验 / 开罐各至少一次",
		int(kinds.get("refresh", 0)) >= 1 and int(kinds.get("lock", 0)) >= 2
		and int(kinds.get("buy_xp", 0)) >= 1 and int(kinds.get("candy", 0)) >= 1, str(kinds))
	_ok("① 分母: 本机状态确实变了(深海币不再是开局的 500)", int(live["meta_deepsea_coins"]) != 500,
		"coins=%d" % int(live["meta_deepsea_coins"]))

	## ② 重放 = 本机
	var r1: Array = _replay(start, log)
	_ok("② 每条流水重放都成交", (r1[1] as Array).is_empty(), str(r1[1]))
	var a := JSON.stringify(live)
	var b := JSON.stringify(r1[0])
	_ok("② ★重放结果与本机逐字节相同(%d 字节)" % a.length(), a == b, _first_diff(live, r1[0]))

	## ③ 再重放一遍
	var r2: Array = _replay(start, log)
	_ok("③ 两遍重放逐字节相同", JSON.stringify(r2[0]) == b)

	## ④ 反向: 第一条掷货的种子 +1 ⇒ 结果必须不同
	var bent: Array = log.duplicate(true)
	for op in bent:
		if str((op as Dictionary).get("op", "")) == "roll":
			op["seed"] = int(op["seed"]) + 1
			break
	var r3: Array = _replay(start, bent)
	_ok("④ ★反向: 掷货种子 +1 ⇒ 重放结果不同(判据不是恒真式)", JSON.stringify(r3[0]) != b)

	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _first_diff(x: Dictionary, y: Dictionary) -> String:
	for k in KEYS:
		if JSON.stringify(x[k]) != JSON.stringify(y[k]):
			return "%s: 本机 %s / 重放 %s" % [k, JSON.stringify(x[k]).left(200), JSON.stringify(y[k]).left(200)]
	return ""
