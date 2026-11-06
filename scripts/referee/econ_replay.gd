class_name EconReplay
extends RefCounted
## 裁判机上重放一个人本周的局外经济流水(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 · S4a)。
##
## 用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」—— 权威状态 = 本周开局 + 逐条重放流水。
## ★起点 = 全新 GameState 的初值(换周 `start_new_season` 把经济全清, 门禁 verify_econ_replay_job ① 守「两者相同」);
##   不另抄一份「起点清单」—— 手抄的副本必然漂移。
## ★重放用的就是客户端那一份 `EconLedger.apply`(同一份代码), 不在服务器另写一份商店 / 背包。
## ★逐条校验: 序号连续、操作种类在白名单里; `strict`(记账开关开着的那一周)时收入只认「裁判结果」那几种来源,
##   本机计分局才有的来源与 `prog` 一律不认(方案书 R7)。金额由服务器拿自己的账去对(输出按来源汇总, S4b)。
## ★零副作用: 进来先整份备份 GameState(capture_all), 走完原样还原(同 RefereeRunner)。

const EL := preload("res://scripts/gamedata/econ_ledger.gd")

## 记账口认识的全部操作(econ_ledger.gd `apply`)。不在表里 ⇒ 不合法。
const OPS := ["roll", "refresh", "lock", "buy", "buy_xp", "candy", "equip", "unequip", "move", "sell", "leveler", "swap",
	"leaders", "axe_final", "axe_exp", "income", "chest", "incense", "prog"]
## 开关开着时认的收入来源 = 裁判结果 / 服务器账本上有的那几种(GameState 结算函数与 RefereeWatch 里写下的 src)。
const SRC_SERVER := ["ranked_ref", "gauntlet", "gauntlet_ref", "finals", "finals_ref", "finals_coins", "finals_reveal",
	"backfill_ranked", "backfill_gauntlet"]
## 开关开着时不认的操作: 本机打的计分局里宝箱 / 香火的终值(服务器没有对应的裁判局可核)。
const LOCAL_ONLY := ["prog"]
## 重放要从初值开始的经济字段(= assets_of / progress_of 读的那些 + 它们依赖的场次戳 / 阵容 / 进化排队)。
const KEYS := ["meta_deepsea_coins", "persistent_bench", "persistent_equipped", "dual_lineup", "equip_pool",
	"meta_shop_offer", "meta_shop_battles", "meta_shop_locked", "season_level", "season_xp", "season_leaders",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches", "axe_evo_pending",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge", "season_total_battles"]


## 把经济字段摆回全新 GameState 的初值(= 本周开局)。
static func week_start(gs) -> void:
	var fresh: Object = (gs.get_script() as Script).new()
	for k in KEYS:
		var v = fresh.get(k)
		gs.set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)
	if fresh is Node:
		(fresh as Node).free()


## 一条流水合不合法(不看它能不能成交 —— 那是 apply 的事)。"" = 合法。
static func check_row(row, i: int, strict: bool) -> String:
	if not (row is Dictionary):
		return "not_dict"
	var d: Dictionary = row
	if int(d.get("seq", -1)) != i:
		return "seq"
	var op := str(d.get("op", ""))
	if not op in OPS:
		return "op:" + op
	if strict and op in LOCAL_ONLY:
		return "local_only:" + op
	if strict and op == "income" and not str(d.get("src", "")) in SRC_SERVER:
		return "src:" + str(d.get("src", ""))
	return ""


## 重放。input = {rows: [流水...], strict: bool}。返回
##   {ok, upto(成交了几条), bad_at(第一条不合法 / 不成交的序号, -1 = 全过), why, assets, progress, fp, income{来源: {coins, xp, n}}}
static func run(gs, input: Dictionary) -> Dictionary:
	if gs == null:
		return {"ok": false, "why": "no_gamestate"}
	var rows: Array = input.get("rows", []) if input.get("rows") is Array else []
	var strict := bool(input.get("strict", true))
	var bk: Dictionary = ReplayRecorder.capture_all()
	var tm0 := bool(gs.test_mode)
	gs.test_mode = true                  # 任何 save() 空转
	gs.econ_quiet = int(gs.econ_quiet) + 1
	week_start(gs)
	var upto := 0
	var bad_at := -1
	var why := ""
	var income := {}
	for i in range(rows.size()):
		var w := check_row(rows[i], i, strict)
		if w != "":
			bad_at = i
			why = w
			break
		var row: Dictionary = rows[i]
		gs.season_total_battles = int(row.get("bt", 0))
		var r: Dictionary = EL.apply(gs, row)
		if not bool(r.get("ok", false)):
			bad_at = i
			why = "apply:%s:%s" % [str(row.get("op", "")), str(r.get("reason", ""))]
			break
		if str(row.get("op", "")) == "income":
			var src := str(row.get("src", ""))
			var acc: Dictionary = income.get(src, {"coins": 0, "xp": 0, "n": 0})
			acc["coins"] = int(acc["coins"]) + maxi(0, int(row.get("coins", 0)))
			acc["xp"] = int(acc["xp"]) + maxi(0, int(row.get("xp", 0)))
			acc["n"] = int(acc["n"]) + 1
			income[src] = acc
		upto += 1
	var out := {"ok": true, "upto": upto, "bad_at": bad_at, "why": why, "assets": EL.assets_of(gs),
		"progress": EL.progress_of(gs), "fp": EL.fingerprint(gs), "income": income}
	for n in bk:
		var v = bk[n]
		gs.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = tm0
	return out


## 本机按服务器那份流水对齐(S4b: 开局回 econ_mismatch / econ_invalid 之后, EconNet.adopt_async 拉下来调这里)。
##   与 run 同一个起点、同一份 apply, 但**留下**重放结果; 本机流水换成服务器那一份(成交的那一截), econ_up 跟上。
##   ★场次(season_total_battles)不动 —— 它归积分赛 / 闯关账本管(adopt_ranked_ledger), 不是经济流水的东西。
##   ★缺 bt 的(服务器刚发的种子行, 本机还没传回)按当前场次算。
##   ⚠ 阵型站位 / 前后排不在流水里, 对齐之后回到默认阵(只在对不上时才走这里)。
static func adopt(gs, rows: Array) -> Dictionary:
	var bt0 := int(gs.season_total_battles)
	gs.econ_quiet = int(gs.econ_quiet) + 1     # 重放过程中顺手存的盘不算漂移、不落流水
	week_start(gs)
	var kept: Array = []
	var bad_at := -1
	for i in range(rows.size()):
		if not (rows[i] is Dictionary):
			bad_at = i
			break
		var row: Dictionary = (rows[i] as Dictionary).duplicate(true)
		row["seq"] = i
		if not row.has("bt"):
			row["bt"] = bt0
		gs.season_total_battles = int(row["bt"])
		if not bool(EL.apply(gs, row).get("ok", false)):
			bad_at = i
			break
		kept.append(row)
	gs.season_total_battles = bt0
	gs.econ_log = kept
	gs.econ_up = kept.size()
	gs.econ_quiet = int(gs.econ_quiet) - 1
	EL.rebase(gs)
	return {"ok": bad_at < 0, "upto": kept.size(), "bad_at": bad_at}


## 裁判机命令行入口(referee_main `--econ-replay=<流水.json> --out=<结果.json>`)。返回进程退出码: 0 = 写出了结果, 4 = 读写失败。
##   输入两种: {rows, strict} 单个号 ⇒ 输出 run 的结果;
##   {jobs: [{account_id, week, seen, rows}], strict} 一批号(轮询器用: 一个 Godot 进程算多个号, 省掉每次起进程)⇒
##   {results: [{account_id, week, seen, result}]}(= 服务端 econ_replay_done 吃的形状)。
static func run_files(host: Node, in_path: String, out_path: String) -> int:
	var txt := FileAccess.get_file_as_string(in_path)
	var j = JSON.parse_string(txt) if txt != "" else null
	if not (j is Dictionary):
		return 4
	var gs = host.get_node_or_null("/root/GameState")
	var res: Dictionary
	if (j as Dictionary).get("jobs") is Array:
		var outs: Array = []
		for job in (j as Dictionary)["jobs"]:
			if not (job is Dictionary):
				continue
			var r := run(gs, {"rows": (job as Dictionary).get("rows", []), "strict": bool((j as Dictionary).get("strict", true))})
			outs.append({"account_id": str(job.get("account_id", "")), "week": int(job.get("week", 0)),
				"seen": int(job.get("seen", 0)), "result": r})
		res = {"results": outs}
	else:
		res = run(gs, j)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return 4
	f.store_string(JSON.stringify(res))
	f.close()
	return 0
