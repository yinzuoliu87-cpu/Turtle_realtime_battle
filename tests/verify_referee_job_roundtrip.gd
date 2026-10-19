extends Node
## verify_referee_job_roundtrip.gd — 服务器裁判: 同一份任务算两遍逐位相同; 裁判的录像手机直接播、逐步一致
## 方案书 docs/plans/20261019-服务器裁判.md 验收清单「裁判机能领活、算完写回录像与结果; 同一份输入算两次结果相同」。
##
## ★两组对局: 「镜像」那组(B = A 同一份阵容换个名字)跑 R1~R5 —— 对局要打满三路(含终极)、而且吃种子
##   (一边倒的对局上路就碎蛋, 种子改了也是同一局: 第一版就这么让 R4 / 种子反证假红过;
##    A 对带装备的机器人则是 16 个种子 16 场 2:0, 到不了终极);
##   「一强一弱」那组(A 满 3 星 vs 全裸机器人)只跑 R6。镜像那组的种子从候选里挑「打到终极」的第一个(分母), 不靠运气。
##
##   R1 确定: 同一份任务单(经 JSON 往返, 与服务器上一样)跑两遍 ⇒ 胜方 / 比分码 / 步数 / 终局指纹 / 录像 base64 逐字节相同
##   R2 可播: 裁判产出的录像(上传格式 base64)交给 `ReplayRecorder` 播放模式, 本机 GameState 先改成另一份 ⇒
##            产品自己的校验点一个不差、终局一致、且**每一个 sim 步**的全场指纹与裁判那一遍相同(播放帧切法乱跳)
##   R2 反证: 录像种子改一位 / 第一路开打站位挪 40 码 ⇒ 播放必须停下(证明 R2 的判据会红)
##   R3 帧切法无关: 裁判每帧预算从 100ms 换成 2ms(一帧只推一两步) ⇒ 结果与录像逐字节相同
##   R4 换种子结果变: 只改种子 ⇒ 终局指纹不同
##   R5 站位进了对局: 只去掉 A 快照里的站位(off) ⇒ 终局指纹不同; 录像 state 里带着那几个 off
##   R6 A/B 互换胜方镜像: A 满 3 星装备、B 一件装备都没有 ⇒ A 在左赢(winner=a, side 0)、A 在右也赢(winner=b, side 1)
##   R7 拒算: 版本不同 / 种子不合法 / A 不足 3 统领 / B 分路坏 ⇒ 结果单 ok=false 且 permanent=true; 不进战斗场
##   R8 零副作用: 跑完 GameState 还原成跑之前那一份、存档文件逐字节不变、本机不多一份录像
##   R9 录像干净: state 的键 ⊆ STATE_KEYS; 对手快照摘掉了 is_bot / ghost_id; 没有幕布 / 认输事件; 三路都开打过; 大小在上传上限内
##   R10 SQL 静态(server/supabase/migrations/20261019_referee_jobs.sql): 迁移 = schema.sql 里同一段(逐字、只一次、三个被重定义的函数
##       最后一个定义落在这一段里); 领活 RPC 下发的任务单键 = 裁判读的键; 录像上限 / 种子上限 / 周六 4-3-6 / 比分码 = 客户端常量
##
## ★分母: 每一局都打完了(steps > 0、cps > 0); 逐步比较的步数 ≥ 终局步数一半; 反证那两条「停下」的原因各打印出来。
## 可选: `REFEREE_DUMP_DIR=<目录>` ⇒ 把第一份任务单 / 结果单写成 json(给命令行入口 / 轮询器手测用)。

const Backend := preload("res://scripts/net/backend.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
## 镜像那组的候选种子(取第一个打到终极的; 2026-10-19 扫过: 这几个在当时的平衡下都打满三路)。
const SEEDS := [2000023, 3000026, 4000029, 5000032, 8000041, 9000044]
const LEVEL := 6
## 播放那一遍的帧长(秒): 含一帧 0 步(0.004)与一帧到顶 8 步(0.15), 与裁判那一遍(一帧几十步)切法完全不同。
const PAT_PLAY := [0.15, 0.05, 0.0167, 0.004, 0.12, 0.033, 0.15, 0.07]
const MAX_PLAY_FRAMES := 30000
const MIG := "res://server/supabase/migrations/20261019_referee_jobs.sql"
const SCHEMA := "res://server/supabase/schema.sql"
const MARK_BEGIN := "-- >>> BEGIN referee_jobs 20261019 >>>"
const MARK_END := "-- <<< END referee_jobs 20261019 <<<"
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DL := preload("res://scripts/gamedata/phase2_duallane.gd")

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## A 方快照: 走真生产函数 `Backend.build_ghost_snapshot`(与客户端上传同一份), 带站位 / 装备 / 技能选择 / 大师技能。
## strong = 每格 3 件 3 星(R6 的强方); 否则每只统领 1 件 1 星、小将不带(与机器人势均力敌)。
func _snap_a(gs, strong: bool) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var k := 0
	var pe := {}
	for pid in gs.season_leaders:
		var l: Array = []
		for _j in range(3 if strong else 1):
			l.append({"id": str(shop[k % shop.size()]), "star": 3 if strong else 1})
			k += 1
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
			{"kind": "leader", "slot": 0, "id": "basic", "off": [-100, 160]},
			{"kind": "minion", "role": "front", "equips": meq.call(), "off": [150, -200]},
			{"kind": "minion", "role": "back", "equips": meq.call()},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": [], "off": [60, -120]},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": meq.call()},
		],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	return Backend.build_ghost_snapshot("g_referee_a", {"name": "甲方", "avatar": "basic", "id": "g_referee_a"})


## B 方快照: 机器人(三统领)。naked = 装备全部摘掉 ⇒ 与满 3 星的 A 强弱差足够大(R6 的前提)。
func _snap_b(naked: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var g: Dictionary = Backend.make_bot(30, rng)
	if not naked:
		return g
	g["equipped"] = {}
	for lk in ["top", "bottom"]:
		for m in (g["minions"] as Dictionary).get(lk, []):
			(m as Dictionary).erase("equips")
	return g


## 与服务器上一样: 任务单经过一次 JSON(数字都变成 float)。
func _job(a: Dictionary, b: Dictionary, seed: int, extra: Dictionary = {}) -> Dictionary:
	var j := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": seed, "client_version": ReplayRecorder.client_version(),
		"level": LEVEL, "a": a, "b": b}
	for kk in extra:
		j[kk] = extra[kk]
	return JSON.parse_string(JSON.stringify(j))


func _same(x: Dictionary, y: Dictionary) -> bool:
	return var_to_bytes(x) == var_to_bytes(y)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	_t_sql()
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var a := _snap_a(gs, false)
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "乙方", "avatar": "stone", "id": "g_referee_b"}
	b["ghost_id"] = "g_referee_b"
	var a_strong := _snap_a(gs, true)
	var b_naked := _snap_b(true)
	## 跑之前那一份 GameState(R8 的基线): 门禁进程自己的 —— 与 A 的快照来源无关
	gs.reset_dual_lane()
	gs.season_leaders = ["ninja", "dice", "pirate"]
	gs.season_level = 9
	gs.trainer_skill = "whistle"
	var gs0: Dictionary = ReplayRecorder.capture_all()
	var save0: PackedByteArray = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var rp0 := _count_replays()
	_ok("分母 · A 快照: 3 统领 / 带站位 / 统领带装备", (a["leaders"] as Array).size() == 3
		and (a.get("leader_off", {}) as Dictionary).size() == 2 and ((a["equipped"] as Dictionary).get("basic", []) as Array).size() == 1,
		str(a.get("leader_off")))
	_ok("分母 · B 快照: A 的镜像(同阵容)、带 ghost_id / is_bot 键(R9 摘字段才不是空检查)", (b["leaders"] as Array).size() == 3
		and b.has("ghost_id") and b.has("is_bot"))
	_ok("分母 · R6 那组: 强方统领 3 件 3 星 / 弱方一件装备都没有", ((a_strong["equipped"] as Dictionary).get("basic", []) as Array).size() == 3
		and (b_naked["equipped"] as Dictionary).is_empty())

	# ── R1 同一份任务跑两遍 ──
	print("=== R1: 同一份任务单跑两遍(先挑一个打到终极的种子) ===")
	var job1 := {}
	var fps1 := {}
	var r1 := {}
	var tried: Array = []
	for sd in SEEDS:
		var fp := {}
		var jj := _job(a, b, int(sd))
		var rr0: Dictionary = await RefereeRunner.run(self, jj, func(bt) -> void:
			bt.sim_stepped.connect(func() -> void: fp[int(bt._sim_step_n)] = ReplayRecorder.fingerprint(bt)))
		_print_res("候选种子 %d" % int(sd), rr0)
		tried.append(int(sd))
		if bool(rr0.get("ok", false)) and int(rr0.get("fights", 0)) >= 3:
			job1 = jj
			fps1 = fp
			r1 = rr0
			break
	_ok("分母 · 候选种子里有一局打到终极(三路; 试了 %s)" % str(tried), not r1.is_empty())
	if r1.is_empty():
		_finish()
		return
	var seed1 := int(job1["seed"])
	_ok("分母 · 第一遍算完(ok)", bool(r1.get("ok", false)), str(r1.get("error", "")))
	if not bool(r1.get("ok", false)):
		_finish()
		return
	_ok("分母 · 打完了: 步数 %d > 0 · 校验点 %d > 0 · 开打 %d 次 = 3 · 终极路有结果 %s" % [int(r1["steps"]), int(r1["cps"]), int(r1["fights"]), str(r1["lane_results"])],
		int(r1["steps"]) > 0 and int(r1["cps"]) > 0 and int(r1["fights"]) == 3 and (r1["lane_results"] as Dictionary).has("final"))
	var r1b: Dictionary = await RefereeRunner.run(self, job1)
	_print_res("第二遍", r1b)
	for f in ["winner", "winner_side", "score_code", "steps", "digest", "lane_results", "egg_hp", "replay_b64"]:
		_ok("★★R1 两遍 %s 相同" % f, str(r1.get(f)) == str(r1b.get(f)), "%s / %s" % [str(r1.get(f)).left(60), str(r1b.get(f)).left(60)])
	_ok("R1 结果单自洽: winner_side = (a 赢 ? 0 : 1)、三路打满 ⇒ 比分码 1(2:1)、终极胜方 = 胜方",
		int(r1["winner_side"]) == (0 if bool(r1["a_won"]) else 1) and int(r1["score_code"]) == 1
		and str((r1["lane_results"] as Dictionary).get("final", "")) == ("left" if bool(r1["a_won"]) else "right"),
		"score_code=%d" % int(r1["score_code"]))

	# ── R9 录像干净 ──
	var rec: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(str(r1["replay_b64"])))
	_ok("分母 · 录像 base64 解得开", not rec.is_empty())
	if rec.is_empty():
		_finish()
		return
	var st: Dictionary = rec.get("state", {})
	var extra_keys: Array = []
	for kk in st:
		if not str(kk) in ReplayRecorder.STATE_KEYS:
			extra_keys.append(kk)
	_ok("★R9 录像 state 的键 ⊆ STATE_KEYS", extra_keys.is_empty(), str(extra_keys))
	_ok("★R9 录像 state 带全部 %d 个 STATE_KEYS(左方不留本机残值)" % ReplayRecorder.STATE_KEYS.size(),
		st.size() == ReplayRecorder.STATE_KEYS.size(), str(st.size()))
	var dg: Dictionary = st.get("dual_ghost", {})
	_ok("★R9 对手快照摘掉了机器人标记(is_bot / ghost_id)", dg.size() > 0 and not dg.has("is_bot") and not dg.has("ghost_id"), str(dg.keys()))
	var kinds := {}
	for e in rec.get("events", []):
		kinds[str(e["k"])] = int(kinds.get(str(e["k"]), 0)) + 1
	_ok("★R9 事件只有开打(没有点幕布 / 认输): %s" % str(kinds), kinds.size() == 1 and int(kinds.get("fight", 0)) == 3)
	var not_i := true
	for e in rec.get("events", []):
		if bool((e as Dictionary).get("i", true)):
			not_i = false
	_ok("★R9 开打事件都记成 i=false(步开头按的, 播放时在 pre_step 重放)", not_i)
	_ok("R9 录像版本 = 本机版本、格式 = FORMAT_V、种子 = 任务单种子、id = 任务单 match_id",
		str(rec.get("client_version", "")) == ReplayRecorder.client_version() and int(rec.get("v", 0)) == ReplayRecorder.FORMAT_V
		and int(rec.get("seed", 0)) == seed1 and str(rec.get("id", "")) == str(job1["match_id"]))
	_ok("R9 录像在上传上限内(%d ≤ %d)" % [str(r1["replay_b64"]).length(), RU.REPLAY_MAX_B64], bool(r1["replay_ok_size"]))
	_ok("R9 等级 = 任务单 level(%d)" % int(st.get("season_level", -1)), int(st.get("season_level", -1)) == LEVEL)
	var dl: Dictionary = st.get("dual_lineup", {})
	_ok("R9 左方每路规整到 3 个单位(%d / %d)" % [(dl.get("top", []) as Array).size(), (dl.get("bottom", []) as Array).size()],
		(dl.get("top", []) as Array).size() == 3 and (dl.get("bottom", []) as Array).size() == 3)
	_ok("R5 录像 state 里带着 A 的站位(上路统领 off = [-100, 160])", _off_of(dl, "basic") == [-100, 160], str(_off_of(dl, "basic")))

	# ── R2 手机播放裁判的录像 ──
	print("=== R2: 裁判的录像交给播放模式(本机 GameState 已是另一份) ===")
	var n_real_cp := 0
	for h in rec.get("cps", []):
		if str(h) != ReplayRecorder.PLACE_CP:
			n_real_cp += 1
	var play: Dictionary = await _play(rec)
	_ok("★★R2 播放全程没有一个校验点对不上(diverged_at=%d %s)" % [int(play["div"]), str(play["why"])], int(play["div"]) < 0)
	_ok("★R2 播放比过 %d 个校验点 = 录像里的非摆位校验点 %d 个" % [int(play["cps"]), n_real_cp],
		int(play["cps"]) == n_real_cp and n_real_cp > 0)
	_ok("★R2 播放打完了(终局步号 / 指纹 / 胜负由产品自己的 on_settle 比)", bool(play["finished"]) and str(play["state"]) == "done")
	var cmp: Array = _compare(fps1, play["fps"], int(r1["steps"]))
	_ok("★★★R2 逐 sim 步全场指纹一致: %d/%d 步分叉(首个 %d)" % [int(cmp[0]), int(cmp[1]), int(cmp[2])],
		int(cmp[0]) == 0 and int(cmp[1]) >= int(r1["steps"]) / 2, str(cmp[3]))
	_ok("分母 · 播放那一遍一帧跑过 0 步也跑过 ≥ 5 步(帧切法与裁判完全不同)", int(play["min_pf"]) == 0 and int(play["max_pf"]) >= 5,
		"%d / %d" % [int(play["min_pf"]), int(play["max_pf"])])
	_ok("R2 播完 GameState 还原(门禁自己那一份)", _same(ReplayRecorder.capture_all(), gs0))

	# ── R2 反证: 判据会红 ──
	print("=== R2 反证(每条都必须停下) ===")
	var bad1: Dictionary = rec.duplicate(true)
	bad1["seed"] = int(bad1["seed"]) ^ 1
	var p1: Dictionary = await _play(bad1)
	_ok("★反证 · 录像种子改一位 ⇒ 播放停下(diverged_at=%d · %s)" % [int(p1["div"]), str(p1["why"])], int(p1["div"]) >= 0)
	var bad2: Dictionary = rec.duplicate(true)
	var moved := false
	for e in bad2["events"]:
		if str(e["k"]) == "fight":
			for p in e["p"]:
				if str(p[1]) == "left" and not str(p[0]).begins_with("__"):
					p[2] = (p[2] as Vector2) + Vector2(-40.0, 0.0)
					moved = true
					break
			break
	var p2: Dictionary = await _play(bad2)
	_ok("★反证 · 第一路开打时一个左方站位挪 40 码 ⇒ 播放停下(diverged_at=%d · %s)" % [int(p2["div"]), str(p2["why"])],
		moved and int(p2["div"]) >= 0)

	# ── R3 帧切法无关 ──
	print("=== R3: 每帧预算 100ms → 2ms ===")
	var b0 := ReplayRecorder.referee_budget_us
	ReplayRecorder.referee_budget_us = 2000
	var r3: Dictionary = await RefereeRunner.run(self, job1)
	ReplayRecorder.referee_budget_us = b0
	_print_res("2ms 预算", r3)
	_ok("分母 · 2ms 预算那一遍帧数(%d)远多于 100ms 那一遍(%d)" % [int(r3.get("frames", 0)), int(r1["frames"])],
		int(r3.get("frames", 0)) > int(r1["frames"]) * 3)
	_ok("★★R3 换每帧预算 ⇒ 终局指纹与录像逐字节相同", str(r3.get("digest")) == str(r1["digest"]) and str(r3.get("replay_b64")) == str(r1["replay_b64"]))

	# ── R4 换种子 ──
	var r4: Dictionary = await RefereeRunner.run(self, _job(a, b, seed1 + 1))
	_print_res("换种子", r4)
	_ok("★R4 只换种子 ⇒ 终局指纹不同", bool(r4.get("ok", false)) and str(r4.get("digest")) != str(r1["digest"]),
		"%s / %s" % [str(r4.get("digest")), str(r1["digest"])])

	# ── R5 站位真的进了对局 ──
	var a_nooff: Dictionary = a.duplicate(true)
	a_nooff["leader_off"] = {}
	for lk in ["top", "bottom"]:
		for m in (a_nooff["minions"] as Dictionary).get(lk, []):
			(m as Dictionary).erase("off")
	var r5: Dictionary = await RefereeRunner.run(self, _job(a_nooff, b, seed1))
	_print_res("去掉站位", r5)
	_ok("★R5 只去掉 A 的站位(off) ⇒ 终局指纹不同(站位用的是快照里的)", bool(r5.get("ok", false)) and str(r5.get("digest")) != str(r1["digest"]))

	# ── R6 A/B 互换 ──
	var r6a: Dictionary = await RefereeRunner.run(self, _job(a_strong, b_naked, seed1))
	_print_res("强方在左", r6a)
	var r6: Dictionary = await RefereeRunner.run(self, _job(b_naked, a_strong, seed1))
	_print_res("A/B 互换", r6)
	_ok("★R6 强方(A 满 3 星)在左 ⇒ winner=a、side 0", str(r6a.get("winner")) == "a" and int(r6a.get("winner_side", -1)) == 0, str(r6a.get("winner")))
	_ok("★R6 同一强方换到右边(任务单里成了 b) ⇒ winner=b、side 1", bool(r6.get("ok", false)) and str(r6.get("winner")) == "b"
		and int(r6.get("winner_side", -1)) == 1, str(r6.get("winner")))
	_ok("R6 互换后不是同一局(指纹不同)", str(r6.get("digest")) != str(r6a.get("digest")))

	# ── R7 拒算 ──
	var bad_ver := _job(a, b, seed1, {"client_version": "0.0.1"})
	var a2: Dictionary = a.duplicate(true)
	a2["leaders"] = ["basic", "stone"]
	var b_broken: Dictionary = b.duplicate(true)
	b_broken["lane_assign"] = {"top": [], "bottom": []}
	var a_dup: Dictionary = a.duplicate(true)
	(a_dup["lane_assign"] as Dictionary)["bottom"] = ((a_dup["lane_assign"] as Dictionary)["bottom"] as Array) + ["basic"]
	for c in [["wrong_version", bad_ver], ["bad_seed", _job(a, b, 0)], ["bad_seed", _job(a, b, seed1, {"seed": 1.5})],
			["a_bad_snapshot", _job(a2, b, seed1)], ["b_bad_snapshot", _job(a, b_broken, seed1)],
			["a_bad_snapshot", _job(a_dup, b, seed1)], ["bad_mode", _job(a, b, seed1, {"mode": "ranked"})]]:
		var rr: Dictionary = await RefereeRunner.run(self, c[1])
		_ok("★R7 拒算 %s ⇒ ok=false 且 permanent" % str(c[0]), not bool(rr.get("ok", true)) and str(rr.get("error", "")) == str(c[0])
			and bool(rr.get("permanent", false)), str(rr.get("error", "")))

	# ── R8 零副作用 ──
	_ok("★R8 跑完 GameState 还原成跑之前那一份", _same(ReplayRecorder.capture_all(), gs0))
	_ok("★R8 存档文件逐字节不变", FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == save0)
	_ok("★R8 本机不多一份录像(%d)" % _count_replays(), _count_replays() == rp0)
	_ok("R8 没有残留的待裁判 / 待播", ReplayRecorder.pending_referee.is_empty() and ReplayRecorder.pending_play.is_empty())

	if OS.get_environment("REFEREE_DUMP_DIR") != "":
		var d := OS.get_environment("REFEREE_DUMP_DIR")
		DirAccess.make_dir_recursive_absolute(d)
		var f := FileAccess.open(d.path_join("job1.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(job1))
		f.close()
		var f2 := FileAccess.open(d.path_join("result1.json"), FileAccess.WRITE)
		f2.store_string(JSON.stringify(r1))
		f2.close()
		print("  [dump] %s" % d)
	_finish()


## R10: 迁移 SQL 与客户端 / 裁判程序的约定(纯文本, 不连库)。
func _t_sql() -> void:
	print("=== R10: 迁移 SQL 静态对账 ===")
	var mig := FileAccess.get_file_as_string(MIG)
	var sch := FileAccess.get_file_as_string(SCHEMA)
	_ok("分母 · 迁移文件与 schema.sql 都读得到", mig.length() > 1000 and sch.length() > 1000, "%d / %d 字" % [mig.length(), sch.length()])
	var seg := _seg(mig)
	_ok("★R10 迁移文件首尾标记各一", seg != "" and mig.count(MARK_BEGIN) == 1 and mig.count(MARK_END) == 1)
	_ok("★R10 schema.sql 里同一段逐字相同(只出现一次)", sch.count(MARK_BEGIN) == 1 and _seg(sch) == seg)
	var a0 := sch.find(MARK_BEGIN)
	for fn in ["finals_advance", "finals_report", "finals_enter"]:
		var last := sch.rfind("create or replace function public.%s(" % fn)
		_ok("★R10 schema.sql 里最后一个 %s 定义落在本段内(整份重放时生效的是带开关的版本)" % fn, last > a0 and a0 > 0)
	var claim := _fn(seg, "referee_claim")
	var keys: Array = []
	for k in ["v", "job_id", "match_id", "mode", "key", "seed", "client_version", "level", "a", "b"]:
		if claim.find("'%s', " % k) < 0:
			keys.append(k)
	_ok("★R10 referee_claim 下发的任务单带齐裁判读的 10 个键", claim != "" and keys.is_empty(), "缺 " + str(keys))
	_ok("★R10 录像上限 = 客户端 REPLAY_MAX_B64(%d)" % RU.REPLAY_MAX_B64,
		_fn(seg, "referee_complete").find("between 1 and %d" % RU.REPLAY_MAX_B64) >= 0)
	_ok("★R10 种子上限 = GameState.BATTLE_SEED_MAX = RefereeJob.SEED_MAX", RefereeJob.SEED_MAX == GameState.BATTLE_SEED_MAX
		and seg.find("seed between 1 and %d" % RefereeJob.SEED_MAX) >= 0 and _fn(seg, "referee_new_seed").find("& %d" % RefereeJob.SEED_MAX) >= 0)
	_ok("★R10 周六结束条件 = 客户端 %d 胜 / %d 负 / %d 场" % [P2C.GAUNTLET_WINS_IN, P2C.GAUNTLET_LOSSES_OUT, P2C.GAUNTLET_QUOTA],
		_fn(seg, "referee_submit_gauntlet").find("v_gw >= %d or v_gl >= %d or v_gw + v_gl >= %d" % [P2C.GAUNTLET_WINS_IN, P2C.GAUNTLET_LOSSES_OUT, P2C.GAUNTLET_QUOTA]) >= 0)
	_ok("★R10 写回认的比分码 = 客户端 score_code 的四个值", _fn(seg, "referee_complete").find("sc in (0, 1, %d, %d)" % [DL.SCORE_1_0, DL.SCORE_1_1]) >= 0)
	_ok("R10 三个裁判 RPC 只给 service_role", seg.find("grant execute on function public.referee_claim(text, text[], int) to service_role;") >= 0
		and seg.find("grant execute on function public.referee_complete(bigint, text, jsonb) to service_role;") >= 0
		and seg.find("grant execute on function public.referee_fail(bigint, text, text, boolean) to service_role;") >= 0
		and seg.find("referee_claim(text, text[], int) to authenticated") < 0)


func _seg(t: String) -> String:
	var a := t.find(MARK_BEGIN)
	var b2 := t.find(MARK_END)
	return t.substr(a, b2 + MARK_END.length() - a) if a >= 0 and b2 > a else ""


func _fn(t: String, name: String) -> String:
	var a := t.find("create or replace function public.%s(" % name)
	if a < 0:
		return ""
	var b2 := t.find("end $$;", a)
	return t.substr(a, b2 - a) if b2 > a else ""


func _off_of(dl: Dictionary, id: String):
	for lk in dl:
		for u in dl[lk]:
			if u is Dictionary and str((u as Dictionary).get("id", "")) == id:
				return (u as Dictionary).get("off", null)
	return null


func _print_res(tag: String, r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		print("  [量] %s: winner=%s score=%d steps=%d digest=%s 帧=%d 墙钟=%dms 录像=%d 字节(base64)" % [tag, str(r["winner"]),
			int(r["score_code"]), int(r["steps"]), str(r["digest"]), int(r["frames"]), int(r["elapsed_ms"]), str(r["replay_b64"]).length()])
	else:
		print("  [量] %s: ERR %s" % [tag, str(r.get("error", ""))])


## 手机那一侧: 播放模式重算一份录像(真入口 begin_play + 战斗场; 帧长由我喂, 交互累加器照常工作)。
func _play(r: Dictionary) -> Dictionary:
	ReplayRecorder.begin_play(r)
	var s = (load(BATTLE) as PackedScene).instantiate()
	add_child(s)
	s.set_process(false)
	var fps := {}
	s.sim_stepped.connect(func() -> void: fps[int(s._sim_step_n)] = ReplayRecorder.fingerprint(s))
	await get_tree().process_frame
	var min_pf := 99
	var max_pf := 0
	var done_frames := 0
	var i := 0
	while i < MAX_PLAY_FRAMES:
		var before: int = int(s._sim_step_n)
		s._process(float(PAT_PLAY[i % PAT_PLAY.size()]))
		await get_tree().process_frame
		var stepped: int = int(s._sim_step_n) - before
		if str(s._dl_state) == "fight":
			min_pf = mini(min_pf, stepped)
			max_pf = maxi(max_pf, stepped)
		i += 1
		if s._replay.diverged_at >= 0:
			break
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 5:
				break
	var out := {"fps": fps, "state": str(s._dl_state), "div": int(s._replay.diverged_at), "why": str(s._replay.diverge_why),
		"cps": int(s._replay.cp_checked), "finished": bool(s._replay.finished), "min_pf": min_pf, "max_pf": max_pf}
	s.queue_free()
	for _g in range(3):
		await get_tree().process_frame
	return out


func _compare(a: Dictionary, b: Dictionary, end_s: int) -> Array:
	var bad := 0
	var n := 0
	var first := -1
	var det := ""
	for k in range(1, end_s + 1):
		if not a.has(k) or not b.has(k):
			continue
		if str(a[k]).contains("|place|") or str(b[k]).contains("|place|"):
			continue
		n += 1
		if str(a[k]) != str(b[k]):
			bad += 1
			if first < 0:
				first = k
				var sa: PackedStringArray = str(a[k]).split("|")
				var sb: PackedStringArray = str(b[k]).split("|")
				for j in range(mini(sa.size(), sb.size())):
					if sa[j] != sb[j]:
						det = "%s ≠ %s" % [sa[j], sb[j]]
						break
	return [bad, n, first, det]


func _count_replays() -> int:
	var d := DirAccess.open(ReplayRecorder.SAVE_DIR)
	if d == null:
		return 0
	return d.get_files().size()


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 服务器裁判 任务单 → 结果 / 录像 → 手机重放 逐步一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
