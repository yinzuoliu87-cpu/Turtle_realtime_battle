extends Node
## verify_econ_server_check —— S4b 验收: 服务器核得住收入, 老实人不被误伤(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 / §6)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」判据:
##   A ★老实的一周: 走真结算入口(积分赛 12 场 / 闯关 4 场 + 第 4 胜补发 / 决赛一轮 + 铸币 + 揭晓 / 积分赛补发 / 裁判宝箱 + 香火 /
##     商店 / 背包穿统领与小将), 九种收入来源都出现; 按恰好的账本 strict 重放 ⇒ 一条不拦、与本机逐字节相同。
##   B ★判据卡得刚好: 账本每一项少 1(或配额多用 1)⇒ 都停在某一条。证明上限不是虚设(A 过 + B 红 = 正好卡在真实值上)。
##   C ★作弊: 编收入 / 编字段 / 编宝箱 / 编香火 / 场次倒退拿免费换货 / 场次超过服务器 / 本机斧头经验 ⇒ 停在那一条, 前面的不受影响;
##     没拿到账本(facts 缺)⇒ 什么收入都不认(fail closed)。
##   D ★真快照契约: econ_check 读的每个键, 真快照 / 真重放结果里都有(分母打印); 真快照 + 真重放结果这一份样本嵌在 SQL 检查脚本里
##     (C1 ~ C4 由 PGlite / 内测服跑)。这里比「嵌的样本 = 现在代码算出来的」: 快照或重放的形状一变就红 ——
##     CI 没有数据库, 但只要样本没漂, SQL 那边验过的结论就还成立。
##     更新样本: ECON_CONTRACT_UPDATE=1 跑一次本测试, 再 python tools/sb_migrate.py sandbox 20261106c_econ_state。
##   E 重放零副作用。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const InvScene := preload("res://scripts/scenes/InventoryScene.gd")
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const SQL_MIG := "res://server/supabase/migrations/20261106c_econ_state.sql"
const SQL_CHK := "res://server/supabase/tests/20261106c_econ_state_check.sql"
const MARK_A := "-- >>> 契约样本(verify_econ_server_check 生成; 手改无效)"
const MARK_B := "-- <<< 契约样本"
## econ_check 读的快照键(D 段再从 SQL 文本里扫一遍, 对不上就红)
const SNAP_KEYS := ["leaders", "equipped", "minions", "season_level", "axe_exp_total", "axe_stage", "axe_final",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge"]
const ASSET_KEYS := ["lv", "worn", "minions", "axe", "leaders"]

var _fails := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	print(("  [PASS] " if c else "  [FAIL] ") + n + ("" if c or d == "" else "  " + d))
	if not c:
		_fails += 1


func _canon(gs) -> String:
	return JSON.stringify({"a": EL.assets_of(gs), "p": EL.progress_of(gs)})


func _replay(gs, rows: Array, facts) -> Dictionary:
	var input := {"rows": rows, "strict": true}
	if facts != null:
		input["facts"] = facts
	return EconReplay.run(gs, input)


func _led(n: int, w: int, used: int, reward: int) -> Dictionary:
	return {"battles": n, "wins": w, "hearts": 6, "sweeps": 0, "eggs": w, "used": used, "reward": reward}


## 老实的一周。返回恰好的账本(= 服务端 econ_facts 这时候应该回的)。全走真结算入口, 手写的只有服务器回包。
func _honest_week(gs) -> Dictionary:
	var wk := P2.week_anchor_utc(int(P2.now_utc()))
	gs.start_new_season()
	gs.week_anchor_ts = wk
	gs.econ_log = []
	gs.econ_up = 0
	gs.econ_drift = 0
	gs.econ_drift_note = ""
	EL.rebase(gs)
	gs.econ({"op": "leaders", "ids": ["candy", "stone", "ice"]})        # 选龟页「开始」

	## 积分赛 12 场(11 胜 ⇒ 晋级)。服务器账本 + 结果单
	var r_coins := 0
	var chest_list: Array = []
	var inc_list: Array = []
	for i in range(12):
		var won := i != 5
		var w := i + 1 if i < 5 else i
		var reward := 14 + (6 if won else 0)
		r_coins += reward
		var st := {"status": "done", "won": 1 if won else 0, "coins": 0, "ranked": _led(i + 1, w, i + 1, reward)}
		if i == 3:
			st["chest"] = {"value": 120.5, "won": ["t1"]}
			st["incense"] = {"marks": 1, "charge": 2}
			chest_list.append(st["chest"])
			inc_list.append(st["incense"])
		gs.referee_pending = RW.ranked_bill(1000 + i, MID, wk, {})
		var v: Dictionary = RW.settle_ranked(gs, 1000 + i, st)
		_ok("A 分母: 第 %d 场真记账" % (i + 1), not v.is_empty()) if i == 0 else null
	gs.promoted = true
	var bf: int = gs.backfill_ranked_quota()                           # 只打 12 场 ⇒ 补发 4 场

	## 闯关 4 胜(第 4 胜 settle 里当场补发省下的场次)
	var g_minted := 0
	for i in range(4):
		var m := 3 + i
		g_minted += m
		gs.referee_pending = RW.pending_for(2000 + i, MID, wk, {})
		RW.settle(gs, 2000 + i, {"status": "done", "won": 1, "coins": m, "gw": i + 1, "gl": 0})

	## 决赛一轮: 封存(轮次币 + 经验)→ 铸币待取单 → 揭晓(糖果罐)
	RW.finals_seal(gs, 0, 1, 0, wk)
	var f_minted := 7
	var paid: int = RW.finals_coins_settle(gs, {"week": wk, "bucket": 0, "round": 1, "match": 0}, f_minted)
	gs.finals_reveal(true)

	## 商店(固定种子)+ 背包: 掷货 → 买 → 买经验 → 穿统领 / 小将
	gs.econ({"op": "roll", "seed": 20261106})
	var bought := 0
	for slot in range(6):
		if bought < 3 and bool(gs.econ({"op": "buy", "slot": slot}).get("ok", false)):
			bought += 1
	gs.econ({"op": "buy_xp"})
	var sc = InvScene.new()
	get_tree().root.add_child(sc)
	await get_tree().process_frame
	var ops = sc._inv_ops
	var lane := "top"
	var mi := -1
	for lk in ["top", "bottom"]:
		var arr: Array = gs.get_dual_lineup()[lk]
		for k in range(arr.size()):
			if mi < 0 and arr[k] is Dictionary and str(arr[k].get("kind", "")) == "minion":
				lane = lk
				mi = k
	ops._equip_to("candy", _gear_at(gs))
	ops._equip_minion(lane, mi, _gear_at(gs))
	sc.queue_free()
	await get_tree().process_frame
	print("  本周流水 %d 条(补发 %d 场, 买 %d 件, 决赛铸币 %d)" % [(gs.econ_log as Array).size(), bf, bought, paid])
	return {"ranked": {"n": 12, "w": 11, "coins": r_coins, "used": 12},
		"gauntlet": {"n": 4, "w": 4, "minted": g_minted},
		"finals": {"n": 1, "w": 1, "minted": f_minted},
		"chest": chest_list, "incense": inc_list}


func _gear_at(gs) -> int:
	for k in range((gs.persistent_bench as Array).size()):
		var it = gs.persistent_bench[k]
		if it is Dictionary and str((it as Dictionary).get("kind", "")) != "item":
			return k
	return -1


func _bump(facts: Dictionary, k: String, f: String, d: int) -> Dictionary:
	var out: Dictionary = facts.duplicate(true)
	out[k][f] = int(out[k][f]) + d
	return out


func _with(rows: Array, row: Dictionary) -> Array:
	var out: Array = rows.duplicate(true)
	var r: Dictionary = row.duplicate(true)
	r["seq"] = out.size()
	out.append(r)
	return out


func _sample(gs, res: Dictionary) -> String:
	var snap: Dictionary = JSON.parse_string(JSON.stringify(RW.my_snapshot_ranked()))
	var s := {}
	for k in SNAP_KEYS:
		s[k] = snap.get(k, null)
	var asset: Dictionary = res.get("assets", {})
	var a := {}
	for k in ASSET_KEYS:
		a[k] = asset.get(k, null)
	return JSON.stringify({"snap": s, "assets": a, "progress": res.get("progress", {})}, "", true)


func _ready() -> void:
	await get_tree().process_frame
	var gs = GameState
	gs.test_mode = true
	var keep: int = P2.now_override_ts
	var wk0 := P2.week_anchor_utc(int(P2.now_utc()))
	P2.now_override_ts = wk0 + 2 * 86400 + 12 * 3600                   # 本周三 12:00

	## ── A 老实的一周 ──
	var facts: Dictionary = await _honest_week(gs)
	var log: Array = (gs.econ_log as Array).duplicate(true)
	var live := _canon(gs)
	var srcs := {}
	for row in log:
		if str(row.get("op", "")) == "income":
			srcs[str(row.get("src", ""))] = true
	print("  收入来源: ", srcs.keys())
	var need := ["ranked_ref", "gauntlet", "gauntlet_ref", "finals", "finals_ref", "finals_coins", "finals_reveal",
		"backfill_ranked", "backfill_gauntlet"]
	var miss: Array = []
	for s in need:
		if not srcs.has(s):
			miss.append(s)
	_ok("A 分母: 九种服务器收入来源都走到了(%d 种)" % srcs.size(), miss.is_empty(), "缺 %s" % str(miss))
	_ok("A 分母: 宝箱 / 香火 / 掷货 / 买 / 穿 都落了流水", _count(log, "chest") == 1 and _count(log, "incense") == 1
		and _count(log, "roll") == 1 and _count(log, "buy") >= 1 and _count(log, "equip") == 2,
		"chest %d inc %d roll %d buy %d equip %d" % [_count(log, "chest"), _count(log, "incense"), _count(log, "roll"), _count(log, "buy"), _count(log, "equip")])
	_ok("A 分母: 哨兵一次没响", int(gs.econ_drift) == 0, str(gs.econ_drift_note))
	var cap0: Dictionary = ReplayRecorder.capture_all()
	var res := _replay(gs, log, facts)
	_ok("A ★恰好的账本: 老实的一周 %d 条一条不拦" % log.size(), int(res.get("bad_at", 0)) == -1 and int(res.get("upto", -1)) == log.size(),
		"bad_at=%d why=%s row=%s" % [int(res.get("bad_at", 0)), str(res.get("why", "")), str(log[int(res.get("bad_at", 0))]) if int(res.get("bad_at", -1)) >= 0 else ""])
	_ok("A ★重放结果 = 本机逐字节(%d 字节)" % live.length(), JSON.stringify({"a": res.get("assets", {}), "p": res.get("progress", {})}) == live)
	_ok("E ★重放前后 GameState 逐字节相同", var_to_bytes(ReplayRecorder.capture_all()) == var_to_bytes(cap0))

	## ── B 判据卡得刚好 ──
	for c in [["ranked", "n", -1], ["ranked", "w", -1], ["ranked", "coins", -1], ["ranked", "used", 1],
			["gauntlet", "n", -1], ["gauntlet", "w", -1], ["gauntlet", "minted", -1],
			["finals", "n", -1], ["finals", "w", -1], ["finals", "minted", -1]]:
		var r := _replay(gs, log, _bump(facts, c[0], c[1], c[2]))
		_ok("B ★账本 %s.%s %+d ⇒ 拦下(说明上限卡在真实值上)" % [c[0], c[1], c[2]], int(r.get("bad_at", -1)) >= 0, "没拦")
	var f_nc: Dictionary = facts.duplicate(true)
	f_nc["chest"] = []
	_ok("B ★账本里没有那一局的宝箱结果 ⇒ over:chest", str(_replay(gs, log, f_nc).get("why", "")) == "over:chest")
	var f_ni: Dictionary = facts.duplicate(true)
	f_ni["incense"] = []
	_ok("B ★账本里没有那一局的香火结果 ⇒ over:incense", str(_replay(gs, log, f_ni).get("why", "")) == "over:incense")

	## ── C 作弊 ──
	var bt := int((log[-1] as Dictionary).get("bt", 0))
	var n0 := log.size()
	var fake := {"op": "income", "src": "ranked_ref", "coins": 99999, "xp": P2.RANKED_XP_PER_MATCH, "axe": true, "candy": 2, "bt": bt}
	var r1 := _replay(gs, _with(log, fake), facts)
	_ok("C ★编一笔 99999 币的积分赛收入 ⇒ 从那条起作废", int(r1.get("bad_at", -1)) == n0 and str(r1.get("why", "")) == "over:ranked_ref", str(r1.get("why", "")))
	_ok("C ★前面的老实流水不受影响(资产 = 没编之前)", JSON.stringify({"a": r1.get("assets", {}), "p": r1.get("progress", {})}) == live)
	var r2 := _replay(gs, _with(log, {"op": "income", "src": "gauntlet_ref", "coins": 1, "bt": bt}), facts)
	_ok("C ★闯关币多报 1 ⇒ over", str(r2.get("why", "")) == "over:gauntlet_ref", str(r2.get("why", "")))
	var f_more := _bump(facts, "ranked", "n", 1)
	var shaped := fake.duplicate()
	shaped["coins"] = 0
	shaped["xp"] = 999
	_ok("C ★经验报 999(有场次额度也不行)⇒ shape", str(_replay(gs, _with(log, shaped), f_more).get("why", "")) == "shape:ranked_ref")
	_ok("C ★不存在的来源 ⇒ src", str(_replay(gs, _with(log, {"op": "income", "src": "gift", "coins": 5, "bt": bt}), facts).get("why", "")) == "src:gift")
	_ok("C ★编宝箱值 ⇒ over:chest", str(_replay(gs, _with(log, {"op": "chest", "chest": {"value": 99999.0, "won": ["t1"]}, "bt": bt}), facts).get("why", "")) == "over:chest")
	_ok("C ★编战利品 ⇒ over:chest", str(_replay(gs, _with(log, {"op": "chest", "chest": {"value": 120.5, "won": ["t1", "t9"]}, "bt": bt}), facts).get("why", "")) == "over:chest")
	_ok("C ★编香火 ⇒ over:incense", str(_replay(gs, _with(log, {"op": "incense", "inc": {"marks": 9, "charge": 9}, "bt": bt}), facts).get("why", "")) == "over:incense")
	_ok("C ★场次倒退(白拿免费换货)⇒ bt:back", str(_replay(gs, _with(log, {"op": "roll", "seed": 1, "bt": bt - 1}), facts).get("why", "")) == "bt:back")
	_ok("C ★场次超过服务器记的 ⇒ bt:over", str(_replay(gs, _with(log, {"op": "lock", "on": true, "bt": 99}), facts).get("why", "")) == "bt:over")
	_ok("C ★本机斧头经验(服务器局里没有这条路)⇒ local_only", str(_replay(gs, _with(log, {"op": "axe_exp", "n": 6, "bt": bt}), facts).get("why", "")) == "local_only:axe_exp")
	var r3 := _replay(gs, log, null)
	_ok("C ★没拿到账本 ⇒ 什么收入都不认(fail closed)", int(r3.get("bad_at", -1)) >= 0 and (str(r3.get("why", "")).begins_with("over:") or str(r3.get("why", "")) == "bt:over"), str(r3.get("why", "")))
	var f_np := _bump(facts, "ranked", "w", -1)
	var bf_i := -1
	for i in range(log.size()):
		if str(log[i].get("src", "")) == "backfill_ranked":
			bf_i = i
	_ok("C ★没晋级不能领积分赛补发 ⇒ 停在补发那一条(或之前的胜场上限)", int(_replay(gs, log, f_np).get("bad_at", -1)) <= bf_i and bf_i >= 0)

	## ── D 真快照契约 ──
	var snap: Dictionary = RW.my_snapshot_ranked()
	var mig := FileAccess.get_file_as_string(SQL_MIG)
	_ok("D 分母: 读到迁移文本", mig.length() > 1000)
	var re := RegEx.new()
	re.compile("(p_snap|v_a|v_p) ->>? '(\\w+)'")
	var seen := {}
	for m in re.search_all(mig.substr(mig.find("function public.econ_check"), mig.find("function public.econ_truncate") - mig.find("function public.econ_check"))):
		seen["%s.%s" % [m.get_string(1), m.get_string(2)]] = true
	var assets: Dictionary = res.get("assets", {})
	var prog: Dictionary = res.get("progress", {})
	var absent: Array = []
	for k in seen:
		var parts: PackedStringArray = str(k).split(".")
		var src_d: Dictionary = snap if parts[0] == "p_snap" else (assets if parts[0] == "v_a" else prog)
		if not src_d.has(parts[1]):
			absent.append(k)
	print("  econ_check 读的键 %d 个: %s" % [seen.size(), str(seen.keys())])
	_ok("D ★econ_check 读的每个键, 真快照 / 真重放结果里都有(分母 %d 个)" % seen.size(), absent.is_empty() and seen.size() >= 12, "缺 %s" % str(absent))
	var chk := FileAccess.get_file_as_string(SQL_CHK)
	var a := chk.find(MARK_A)
	var b := chk.find(MARK_B)
	_ok("D 分母: SQL 检查脚本里有样本标记", a >= 0 and b > a)
	var want := "create or replace function pg_temp.contract() returns jsonb language sql as $c$ select $j$%s$j$::jsonb $c$;" % _sample(gs, res)
	var got := chk.substr(a + MARK_A.length(), b - a - MARK_A.length()).strip_edges()
	if OS.get_environment("ECON_CONTRACT_UPDATE") == "1":
		var out := chk.substr(0, a + MARK_A.length()) + "\n" + want + "\n" + chk.substr(b)
		var f := FileAccess.open(ProjectSettings.globalize_path(SQL_CHK), FileAccess.WRITE)
		f.store_string(out)
		f.close()
		print("  已更新 SQL 里的契约样本, 记得重跑 sb_migrate sandbox")
		got = want
	_ok("D ★嵌在 SQL 里的样本 = 现在代码算出来的(%d 字节; 不同 ⇒ ECON_CONTRACT_UPDATE=1 更新后重跑 sandbox)" % want.length(), got == want,
		"样本 %s\n现在 %s" % [got.left(300), want.left(300)])

	P2.now_override_ts = keep
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fails == 0 else "FAILED: %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _count(rows: Array, op: String) -> int:
	var n := 0
	for r in rows:
		if str((r as Dictionary).get("op", "")) == op:
			n += 1
	return n
