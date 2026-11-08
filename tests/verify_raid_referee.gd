extends Node
## verify_raid_referee.gd — 偷袭(raid)裁判任务能跑完, 结果映射到 attacker / defender
## (2026-11-09 · 工作线 A2 · 方案书 docs/plans/20261107-龟战主站对接.md §4.2 / §4.4)。
##
## 全程真入口 `RefereeRunner.run`(战斗场原样实例化), 两方快照都走真生产函数 `Backend.build_ghost_snapshot`
## (合成阵容: 强 = 三只统领各 3 件 3 星、小将也带; 弱 = 一件装备都没有), 任务单形状 = 服务端 referee_claim 给偷袭局的那份
## (mode = raid、key 带 raid_id 与服务端盖的 a_owned / b_owned / a_account / b_account), 经一次 JSON 往返(与服务器上一样)。
## ★两方快照里另外故意塞了 owned / account_id(旧任务形状 / 别的路带进来的): 裁判不许把它们带进录像(V8)。
##
##   V1 分母: 两份快照都是三统领、强弱差得开(强方 9 件统领装备 / 弱方 0 件); 任务单 mode = raid 过 validate
##   V2 ★强攻弱: 算完(ok、步数 > 0、开打过、有路分出胜负); winner = a ⇒ raid_result = attacker; 结果单 mode = raid
##   V3 ★弱攻强(同两份阵容换边): winner = b ⇒ raid_result = defender —— 两种结果都真走到过(分母)
##   V4 ★与周赛完全一样: V2 那份任务单只把 mode 换成 ranked ⇒ winner / 比分码 / 步数 / 终局指纹 / 两路结果 / 录像逐字节相同;
##      积分赛结果单没有 raid_result(不多一个键)
##   V5 守方没开轮(两只统领) ⇒ 偷袭拒算 b_bad_snapshot(permanent, 不进战斗场); 同一个 B 当积分赛对手照算(周赛 B 不要求三只)
##   V6 mode 拼错 ⇒ bad_mode; 映射函数两个值 = 服务端 raid_on_job 认的那两个字面值(迁移 20261109c)
##   V7 零副作用: 跑完 GameState 还原成跑之前那一份、存档逐字节不变(偷袭不计场数 / 不发币 —— 裁判这一侧本来就不结算)
##   V8 ★私有字段不外泄(工作线 F): V2 那一局的录像(结果单 replay_b64 解码 = 进 matches 的那一份; 直播 rs 是同一份 state)
##      里找不到两个账号 id、没有 owned 键; 录像里的对手快照(dual_ghost)摘掉了两键、其余(统领 / 分路)原样; 任务单原件不动
##   V9 ★装备上限两份对得上: 服务端检查脚本 20261109c_raid_check L0 钉的字面表(raid_cap_table / raid_unit_cap)
##      = phase2_config.gd team_equip_cap(0 ~ 11) / UNIT_EQUIP_CAP(raid_lock_snapshot 照它不认超上限的件)

const Backend := preload("res://scripts/net/backend.gd")
const MIG := "res://server/supabase/migrations/20261109c_raid.sql"
const CHK := "res://server/supabase/tests/20261109c_raid_check.sql"
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MID := "8b1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4c"
const SEED := 3000026
const LEVEL := 6

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 一方快照(真生产函数)。strong = 统领每只 3 件 3 星 + 小将各 3 件; 否则全裸。
func _snap(gs, leaders: Array, strong: bool, tag: String) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = leaders.duplicate()
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in leaders:
		var l: Array = []
		for _j in range(3 if strong else 0):
			l.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		if not l.is_empty():
			pe[pid] = l
	gs.persistent_equipped = pe
	var meq := func() -> Array:
		var l2: Array = []
		for _j in range(3 if strong else 0):
			l2.append({"id": str(shop[k % shop.size()]), "star": 3})
			k += 1
		return l2
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": str(leaders[0])},
			{"kind": "minion", "role": "front", "equips": meq.call()},
			{"kind": "minion", "role": "back", "equips": meq.call()},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": str(leaders[1])},
			{"kind": "leader", "slot": 2, "id": str(leaders[2])},
			{"kind": "minion", "role": "back", "equips": meq.call()},
		],
	}
	gs.loadouts = {}
	gs.trainer_skill = "hook"
	gs.season_level = LEVEL
	return Backend.build_ghost_snapshot("g_raid_" + tag, {"name": tag, "avatar": str(leaders[0]), "id": "g_raid_" + tag})


## = referee_claim 给偷袭局的任务单(key = meta + week + match_key; 服务端把 owned / 账号盖在 key 里)。
## ★快照里也塞了 owned / account_id(旧形状 / 兜底): V8 量的就是它们进不了录像。
const ACC_A := "11111111-2222-4333-8444-555555555555"
const ACC_B := "66666666-7777-4888-8999-000000000000"
func _job(a: Dictionary, b: Dictionary, mode: String = "raid") -> Dictionary:
	var aa := a.duplicate(true)
	var bb := b.duplicate(true)
	aa["owned"] = (aa["leaders"] as Array).duplicate()
	aa["account_id"] = ACC_A
	bb["owned"] = (bb["leaders"] as Array).duplicate()
	bb["account_id"] = ACC_B
	var j := {"v": 1, "job_id": 77, "match_id": MID, "mode": mode,
		"key": {"raid_id": 9001, "attacker": "ChkAtt01", "defender": "ChkDef01", "account": ACC_A,
			"b_account": ACC_B, "a_account": ACC_A, "a_owned": aa["owned"], "b_owned": bb["owned"],
			"expire_ms": 1, "week": 1, "match_key": "raid:9001"},
		"seed": SEED, "client_version": ReplayRecorder.client_version(), "level": LEVEL, "a": aa, "b": bb}
	return JSON.parse_string(JSON.stringify(j))


func _print_res(tag: String, r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		print("  [量] %s: winner=%s raid_result=%s score=%d steps=%d fights=%d digest=%s 帧=%d 墙钟=%dms" % [tag,
			str(r["winner"]), str(r.get("raid_result", "-")), int(r["score_code"]), int(r["steps"]), int(r["fights"]),
			str(r["digest"]), int(r["frames"]), int(r["elapsed_ms"])])
	else:
		print("  [量] %s: ERR %s" % [tag, str(r.get("error", ""))])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var strong := _snap(gs, ["basic", "stone", "bamboo"], true, "强")
	var weak := _snap(gs, ["ninja", "dice", "pirate"], false, "弱")
	## 跑之前那一份 GameState(V7 的基线): 门禁进程自己的
	gs.reset_dual_lane()
	gs.season_leaders = ["angel", "ice", "fortune"]
	gs.season_level = 9
	gs.season_total_battles = 5
	gs.trainer_skill = "whistle"
	var gs0: Dictionary = ReplayRecorder.capture_all()
	var save0: PackedByteArray = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)

	print("=== V1 分母 ===")
	var n_eq := 0
	for p in (strong.get("equipped", {}) as Dictionary):
		n_eq += ((strong["equipped"] as Dictionary)[p] as Array).size()
	_ok("V1 分母 · 两方三统领; 强方统领装备 %d 件 / 弱方 %d 件" % [n_eq, (weak.get("equipped", {}) as Dictionary).size()],
		(strong["leaders"] as Array).size() == 3 and (weak["leaders"] as Array).size() == 3
		and n_eq == 9 and (weak.get("equipped", {}) as Dictionary).is_empty())
	var j_sw := _job(strong, weak)
	_ok("V1 偷袭任务单过 validate(mode = raid 在 MODES 里)", RefereeJob.validate(j_sw) == "" and RefereeJob.MODES.has("raid"),
		RefereeJob.validate(j_sw))

	print("=== V2 强攻弱 ===")
	var r_sw: Dictionary = await RefereeRunner.run(self, j_sw)
	_print_res("强(攻) vs 弱(守)", r_sw)
	## 强弱悬殊 ⇒ 上路就碎蛋(1 : 0, score_code = SCORE_1_0)也是打完的一局: 量的是「打完了」, 不是打满三路
	_ok("V2 算完: ok、步数 > 0、开打 ≥ 1 次、有路分出胜负", bool(r_sw.get("ok", false)) and int(r_sw.get("steps", 0)) > 0
		and int(r_sw.get("fights", 0)) >= 1 and not (r_sw.get("lane_results", {}) as Dictionary).is_empty(),
		str(r_sw.get("error", "")))
	_ok("★V2 攻方(A)赢 ⇒ winner = a、raid_result = attacker", str(r_sw.get("winner", "")) == "a"
		and str(r_sw.get("raid_result", "")) == "attacker", "%s / %s" % [str(r_sw.get("winner")), str(r_sw.get("raid_result"))])
	_ok("V2 结果单 mode = raid、match_id / seed = 任务单的", str(r_sw.get("mode", "")) == "raid"
		and str(r_sw.get("match_id", "")) == MID and int(r_sw.get("seed", 0)) == SEED)

	print("=== V3 弱攻强 ===")
	var r_ws: Dictionary = await RefereeRunner.run(self, _job(weak, strong))
	_print_res("弱(攻) vs 强(守)", r_ws)
	_ok("★V3 守方(B)赢 ⇒ winner = b、raid_result = defender", bool(r_ws.get("ok", false))
		and str(r_ws.get("winner", "")) == "b" and str(r_ws.get("raid_result", "")) == "defender",
		"%s / %s %s" % [str(r_ws.get("winner")), str(r_ws.get("raid_result")), str(r_ws.get("error", ""))])
	_ok("V3 分母: attacker / defender 两种结果都真走到过", str(r_sw.get("raid_result", "")) != str(r_ws.get("raid_result", "")))

	print("=== V4 与周赛完全一样 ===")
	var j_rk := _job(strong, weak, "ranked")
	var r_rk: Dictionary = await RefereeRunner.run(self, j_rk)
	_print_res("同一份按积分赛跑", r_rk)
	for f in ["winner", "winner_side", "score_code", "steps", "digest", "lane_results", "egg_hp", "replay_b64", "coins", "coins_b"]:
		_ok("★V4 偷袭 = 积分赛: %s 相同" % f, str(r_sw.get(f)) == str(r_rk.get(f)),
			"%s / %s" % [str(r_sw.get(f)).left(60), str(r_rk.get(f)).left(60)])
	_ok("V4 积分赛结果单不带 raid_result(非偷袭局一个键都不多)", bool(r_rk.get("ok", false)) and not r_rk.has("raid_result"))

	print("=== V5 守方没开轮 ===")
	var weak2: Dictionary = weak.duplicate(true)
	weak2["leaders"] = ["ninja", "dice"]
	weak2["lane_assign"] = {"top": ["ninja"], "bottom": ["dice"]}
	var j_b2 := _job(strong, weak2)
	_ok("★V5 守方两只统领 ⇒ 偷袭拒算 b_bad_snapshot", RefereeJob.validate(j_b2) == "b_bad_snapshot", RefereeJob.validate(j_b2))
	var r_b2: Dictionary = await RefereeRunner.run(self, j_b2)
	_ok("V5 RefereeRunner 回 ok=false、permanent(不重领)、没进战斗场", not bool(r_b2.get("ok", true))
		and bool(r_b2.get("permanent", false)) and not r_b2.has("steps"), str(r_b2))
	_ok("V5 同一个 B 当积分赛对手照算(周赛的 B 是对手快照, 不要求三只)", RefereeJob.validate(_job(strong, weak2, "ranked")) == "")

	print("=== V6 拼写 / 字面值 ===")
	_ok("V6 mode 拼错(raidx) ⇒ bad_mode", RefereeJob.validate(_job(strong, weak, "raidx")) == "bad_mode")
	var sql := FileAccess.get_file_as_string(MIG)
	_ok("V6 分母 · 读到迁移 20261109c", sql.length() > 5000, str(sql.length()))
	_ok("V6 映射字面值 = 服务端 raid_on_job 认的(a ⇒ attacker / b ⇒ defender)",
		RefereeJob.raid_result_of(true) == "attacker" and RefereeJob.raid_result_of(false) == "defender"
		and sql.contains("when 'a' then 'attacker' when 'b' then 'defender'") and sql.contains("'raid_result'"))
	_ok("V6 任务种类: 裁判认 raid、服务端约束也认", sql.contains("check (kind in ('gauntlet', 'finals', 'ranked', 'raid'))"))

	print("=== V7 零副作用 ===")
	_ok("★V7 跑完 GameState 还原成跑之前那一份(场次 5 / 等级 9 / 统领不变)", var_to_bytes(ReplayRecorder.capture_all()) == var_to_bytes(gs0)
		and int(gs.season_total_battles) == 5 and int(gs.season_level) == 9)
	_ok("★V7 存档文件逐字节不变", FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == save0)
	_ok("V7 没有残留的待裁判 / 待播", ReplayRecorder.pending_referee.is_empty() and ReplayRecorder.pending_play.is_empty())

	print("=== V8 私有字段不外泄 ===")
	var rec8: Dictionary = {}
	var b64 := str(r_sw.get("replay_b64", ""))
	if b64 != "":
		rec8 = ReplayRecorder.decode(Marshalls.base64_to_raw(b64))
	var txt8 := JSON.stringify(rec8)
	var st8: Dictionary = rec8.get("state", {}) if rec8.get("state") is Dictionary else {}
	var g8: Dictionary = st8.get("dual_ghost", {}) if st8.get("dual_ghost") is Dictionary else {}
	_ok("V8 分母 · 录像解得出来、带开局 state、对手快照统领 = 守方三只", txt8.length() > 1000
		and str(g8.get("leaders", [])) == str(weak["leaders"]), "%d 字 / %s" % [txt8.length(), str(g8.get("leaders", []))])
	_ok("★V8 录像里找不到两个账号 id、没有 owned 键", not txt8.contains(ACC_A) and not txt8.contains(ACC_B)
		and not txt8.contains("\"owned\""))
	_ok("V8 对手快照摘掉两键、分路原样", not g8.has("owned") and not g8.has("account_id")
		and JSON.stringify(g8.get("lane_assign", {})) == JSON.stringify(weak.get("lane_assign", {})))
	_ok("V8 任务单原件不动(validate 读的那一份仍带着)", (j_sw["b"] as Dictionary).has("owned")
		and str((j_sw["b"] as Dictionary).get("account_id", "")) == ACC_B)

	print("=== V9 装备上限两份对得上 ===")
	var chk := FileAccess.get_file_as_string(CHK)
	var want_tbl := ""
	var want_unit := -1
	for line in chk.split("\n"):
		if line.contains("-- raid_cap_table"):
			var m := RegEx.create_from_string("array\\[([0-9, ]+)\\]").search(line)
			if m != null:
				want_tbl = m.get_string(1).replace(" ", "")
		if line.contains("-- raid_unit_cap"):
			var m2 := RegEx.create_from_string("raid_unit_equip_cap\\(\\) = ([0-9]+)").search(line)
			if m2 != null:
				want_unit = int(m2.get_string(1))
	var got: Array = []
	for l in range(0, 12):
		got.append(str(P2.team_equip_cap(l)))
	_ok("V9 分母 · 检查脚本里两张字面表都找到", want_tbl != "" and want_unit >= 0, "%s / %d" % [want_tbl, want_unit])
	_ok("★V9 全队上限 0 ~ 11 级 = phase2_config.team_equip_cap", want_tbl == ",".join(got), "%s / %s" % [want_tbl, ",".join(got)])
	_ok("★V9 单只上限 = phase2_config.UNIT_EQUIP_CAP", want_unit == P2.UNIT_EQUIP_CAP, "%d / %d" % [want_unit, P2.UNIT_EQUIP_CAP])
	_finish()


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 偷袭裁判任务跑完、结果映射 attacker / defender、与周赛同一套 sim" if _fail == 0 and _n >= 35
		else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
