extends Node
## verify_abandoned_match.gd — 中途退出的对局自动结算(方案书 docs/plans/20261010-中途退出自动结算.md §6)
##
## 用户 2026-10-10「学习他们的做法」: 杀进程 / 闪退之后, 那一局不作废、不直接判负, 按正常规则打完并结算。
##
##   A 确定性: 同一局(拖过站位、点过幕布)正常打完 vs 打到一半「被杀」后复算 ⇒ 结束步 / 终局指纹 / 胜负 / 事件 / 全部校验点逐一相同
##   B 只结一次: 命 / 币 / 胜场 / 配额 / 总场次 / 战绩的结果与正常打完相同; 结算后单子删了; 再开一次什么都不做
##   C 结算后、删单前被杀 ⇒ 只删单, 不再结算
##   D 复算途中被杀 ⇒ 下次重试(已试 2 次), 仍只结一次、结果相同
##   E 版本变了 ⇒ 判负(积分赛扣一命、战绩一条负); 跨周 ⇒ 作废不动账; 复算闪退过头 ⇒ 作废
##   F 教学 / 表演赛 / 存档不落盘 / 调试场 ⇒ 不落单; 真「被杀」(释放战斗场不结算)后单子在、未结算、id 对得上
##   G 主菜单在登录墙之前调
##
## ★「被杀」= 战斗场直接释放、`_settle_season` 一行没跑; 盘上留下的就是那一刻的待结算单(A 里在第一路开打后 200 步把盘上那份抄下来)。
## ★「重开」= GameState 还原成开局前那一份(= 重开时从存档读回来的) + 把抄下的单子写回盘 + `AbandonedMatch.prepare()`(主菜单调的就是它)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const AM := preload("res://scripts/systems/replay/abandoned_match.gd")
const MAX_FRAMES := 40000
const KILL_AFTER := 200            # 第一路开打后多少步「被杀」
## 结算会动的账(B/D 逐个比; 分母见 _ok「分母 · 正常打完那一局真的动了账」)。
const LEDGER := ["hearts", "meta_deepsea_coins", "season_wins", "ranked_used", "season_total_battles",
	"battles_total", "battles_won", "season_xp", "season_level", "season_sweeps", "candy_jar_count",
	"axe_exp_total", "incense_charge", "chest_treasure_value"]

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _setup_gs(gs) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false                     # ★要量真存档与待结算单(门禁每个测试一份独立 user://)
	gs.tutorial_active = false
	gs.tutorial = false
	gs.week_phase = "ranked"                 # 积分赛: 输了扣命, 账最多
	gs.hearts = 5
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic"}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.persistent_equipped = {"basic": [{"id": "p2eq_001", "star": 3}], "ninja": [{"id": "p2eq_065", "star": 3}]}
	gs.season_level = 4
	gs.trainer_skill = "hook"
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true


## GameState 全部脚本变量(= 重开时从存档读回来的那一份; 不在存档里的局内变量也一起, 免得两遍起点不同)。
func _snap(gs) -> Dictionary:
	var out := {}
	for p in gs.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var k := str(p.get("name", ""))
		var v = gs.get(k)
		if typeof(v) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
			continue
		out[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


func _restore(gs, snap: Dictionary) -> void:
	for k in snap:
		var v = snap[k]
		if v is Array:
			(gs.get(k) as Array).assign((v as Array).duplicate(true))
		elif v is Dictionary:
			gs.set(k, (v as Dictionary).duplicate(true))
		else:
			gs.set(k, v)


func _ledger(gs) -> Dictionary:
	var out := {}
	for k in LEDGER:
		out[k] = gs.get(k)
	out["hist_n"] = (gs.match_history as Array).size()
	out["hist0"] = str((gs.match_history[0] as Dictionary).get("result", "")) if not (gs.match_history as Array).is_empty() else ""
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")        # 复算那一遍走交互累加器(sim_feed), 不许 det
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	AM.clear()

	# ── G 主菜单在登录墙之前调 ──
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MainMenuScene.gd")
	var i_am := mm.find("_AM.resume_if_any(")
	var i_sign := mm.find("_SB.ensure_signed_in_async()")
	var i_wall := mm.find("_P2C.login_wall_on(")
	_ok("★G 主菜单调 AbandonedMatch.resume_if_any, 位置在建身份之后、登录墙之前(%d < %d < %d)" % [i_sign, i_am, i_wall],
		i_sign > 0 and i_am > i_sign and i_wall > i_am)

	# ── F 落单判据 ──
	_setup_gs(gs)
	_ok("分母 · F 计分积分赛 ⇒ 落单", AM.wanted(null))
	gs.tutorial_active = true
	_ok("★F 教学 ⇒ 不落单", not AM.wanted(null))
	gs.tutorial_active = false
	gs.hearts = 0
	_ok("★F 表演赛(0 命打积分赛) ⇒ 不落单", not AM.wanted(null))
	gs.hearts = 5
	gs.test_mode = true
	_ok("★F 存档不落盘(test_mode) ⇒ 不落单", not AM.wanted(null))
	gs.test_mode = false
	gs.dual_active = false
	_ok("★F 非双路(调试 / 审阅台) ⇒ 不落单", not AM.wanted(null))
	gs.dual_active = true

	# ── A 参照: 正常打完的那一局(中途在第一路开打后 KILL_AFTER 步把盘上的待结算单抄下来 = 那一刻被杀会留下的) ──
	_setup_gs(gs)
	var pre: Dictionary = _snap(gs)
	print("=== A 参照: 正常打完(拖站位 + 点幕布 + 每路一进摆位就开打) ===")
	var ref: Dictionary = await _run_ref()
	_ok("分母 · 参照那一局打完了(%s)、开打 %d 次、点过幕布、拖过站位" % [str(ref["state"]), int(ref["fights"])],
		str(ref["state"]) == "done" and int(ref["fights"]) >= 2 and bool(ref["clicked"]) and bool(ref["dragged"]))
	_ok("★F 开局就落了待结算单, id = 这一局录像 id", bool(ref["pending_at_start"]), str(ref["pid0"]))
	var kill: PackedByteArray = ref["kill"]
	var kp: Dictionary = ReplayRecorder.decode(kill)
	var kevs: Array = (kp.get("rec", {}) as Dictionary).get("events", [])
	var kk := []
	for e in kevs:
		kk.append(str(e["k"]))
	_ok("分母 · 被杀那一刻的单子里有点幕布与第一路开打(%s), 没有后面几路" % str(kk),
		kk.has("present") and kk.count("fight") == 1)
	var hist: Array = gs.match_history
	var rid: String = str((hist[0] as Dictionary).get("replay_id", "")) if not hist.is_empty() else ""
	var rec_a: Dictionary = ReplayRecorder.load_record(rid)
	_ok("分母 · 参照那一局的录像读得回来、id 与单子一致", not rec_a.is_empty() and rid == str(ref["pid0"]), rid)
	var post_a: Dictionary = _ledger(gs)
	var pre_l: Dictionary = _ledger_of(pre)
	_ok("分母 · 正常打完那一局真的动了账(总场次 / 配额 / 战绩 +1)",
		int(post_a["season_total_battles"]) == int(pre_l["season_total_battles"]) + 1
		and int(post_a["ranked_used"]) == int(pre_l["ranked_used"]) + 1 and int(post_a["hist_n"]) == int(pre_l["hist_n"]) + 1,
		"%s → %s" % [str(pre_l), str(post_a)])
	_ok("★B 正常打完后单子删了", not AM.exists())
	if rec_a.is_empty() or kill.is_empty():
		_finish()
		return

	# ── A/B 被杀 → 重开 → 复算 ──
	print("=== A/B 重开: 还原存档 + 写回单子 + 复算 ===")
	_restore(gs, pre)
	gs.dual_ghost = {}                         # 不在存档里: 重开后是空的, 必须从单子里来
	gs.dual_active = false
	gs.week_phase = ""
	_write_raw(kill)
	var act: String = AM.prepare()
	_ok("★A 判定 = resume(%s)" % act, act == "resume")
	_ok("★A 复算前状态摆回去了(dual_ghost / dual_active / week_phase / 未上场统领的装备没被录像裁掉)",
		not (gs.dual_ghost as Dictionary).is_empty() and bool(gs.dual_active) and str(gs.week_phase) == "ranked"
		and (gs.persistent_equipped as Dictionary).has("ninja") and (gs.persistent_equipped as Dictionary).has("basic"))
	var rb: Dictionary = await _run_resume(-1)
	_ok("分母 · 复算那一局结算了、结算屏出了、遮罩撤了", bool(rb["finished"]) and bool(rb["settled"]) and bool(rb["revealed"]),
		str(rb))
	_ok("分母 · 复算一帧推了不止一步(真的是快进: 共 %d 步 / %d 帧)" % [int(rb["steps"]), int(rb["frames"])],
		int(rb["steps"]) > int(rb["frames"]) * 4)
	_ok("分母 · 复算前缀没有对不上(%s)" % str(rb["dropped"]), str(rb["dropped"]) == "")
	var rec_b: Dictionary = ReplayRecorder.load_record(rid)
	var ea: Dictionary = rec_a.get("end", {})
	var eb: Dictionary = rec_b.get("end", {})
	_ok("★★A 结束步 / 终局指纹 / 胜负与正常打完相同(%s / %s)" % [str(ea), str(eb)],
		not eb.is_empty() and int(ea["s"]) == int(eb["s"]) and str(ea["h"]) == str(eb["h"]) and bool(ea["won"]) == bool(eb["won"]))
	_ok("★★A 事件序列(种类 / 步号 / 步内标记 / 开打站位)逐条相同(%d 条)" % (rec_a["events"] as Array).size(),
		var_to_bytes(rec_a["events"]) == var_to_bytes(rec_b.get("events", [])), "%s\n      %s" % [_ev_str(rec_a["events"]), _ev_str(rec_b.get("events", []))])
	_ok("★★A 全部校验点逐一相同(%d 个)" % (rec_a["cps"] as Array).size(),
		(rec_a["cps"] as Array).size() > 10 and var_to_bytes(rec_a["cps"]) == var_to_bytes(rec_b.get("cps", [])))
	var post_b: Dictionary = _ledger(gs)
	_ok("★★B 复算结算后的账与正常打完逐项相同", var_to_bytes(post_a) == var_to_bytes(post_b), "%s\n      %s" % [str(post_a), str(post_b)])
	_ok("★B 战绩行挂着同一个 id(只一行)", _count_id(gs, rid) == 1)
	_ok("★B 复算结算后单子删了", not AM.exists())
	_ok("★B 再开一次: 判定 none、什么都不做", AM.prepare() == "none" and AM.pending_resume.is_empty())

	# ── C 结算后、删单前被杀 ⇒ 只删单 ──
	_write_raw(kill)
	var snap_c: Dictionary = _ledger(gs)
	_ok("★★C 战绩里已有这一局 ⇒ 判定 settled、只删单", AM.prepare() == "settled" and not AM.exists() and AM.pending_resume.is_empty())
	_ok("★C 账一分没动", var_to_bytes(snap_c) == var_to_bytes(_ledger(gs)))

	# ── D 复算途中被杀 ⇒ 重试, 仍只结一次 ──
	print("=== D 复算途中被杀 ===")
	_restore(gs, pre)
	_write_raw(kill)
	_ok("分母 · D 第一次复算判定 resume", AM.prepare() == "resume")
	var rd1: Dictionary = await _run_resume(3)
	_ok("分母 · D 第一次复算没结算就被杀(推了 %d 步)" % int(rd1["steps"]), not bool(rd1["finished"]) and int(rd1["steps"]) > 0)
	_ok("★D 复算途中遮罩盖着、音效静音; 战斗场没了音效还原", bool(rd1["cover_left"]) and bool(rd1["muted"])
		and not bool(get_node("/root/Audio").mute_sfx))
	_ok("★D 单子还在、已试 1 次", AM.exists() and int((AM.read().get("meta", {}) as Dictionary).get("tries", -1)) == 1)
	_restore(gs, pre)                          # 重开: 内存里复算了一半的东西全没了, 从存档读回来
	_ok("★D 重开再判定 resume", AM.prepare() == "resume")
	_ok("分母 · D 第二次进场前已试 2 次", int((AM.read().get("meta", {}) as Dictionary).get("tries", -1)) == 2)
	var rd2: Dictionary = await _run_resume(-1)
	_ok("★★D 第二次打完, 账与正常打完逐项相同(只结一次)", bool(rd2["finished"]) and var_to_bytes(post_a) == var_to_bytes(_ledger(gs)),
		str(_ledger(gs)))
	_ok("★D 战绩行只有一行这个 id、单子删了", _count_id(gs, rid) == 1 and not AM.exists())

	# ── E 版本变了 ⇒ 判负 ──
	print("=== E 版本变了 / 跨周 / 闪退过头 ===")
	_restore(gs, pre)
	var kv: Dictionary = kp.duplicate(true)
	(kv["rec"] as Dictionary)["client_version"] = "0.0.1"
	AM.write(kv["rec"], kv["meta"])
	_ok("★E 版本不同 ⇒ 判定 loss_version", AM.prepare() == "loss_version")
	var re: Dictionary = await _run_resume(-1)
	var post_e: Dictionary = _ledger(gs)
	_ok("★★E 判负: 积分赛扣一命、战绩一条负、总场次 / 配额 +1(%s)" % str(post_e),
		bool(re["finished"]) and int(post_e["hearts"]) == int(pre_l["hearts"]) - 1 and str(post_e["hist0"]) == "lose"
		and int(post_e["season_total_battles"]) == int(pre_l["season_total_battles"]) + 1
		and int(post_e["ranked_used"]) == int(pre_l["ranked_used"]) + 1 and int(post_e["hist_n"]) == int(pre_l["hist_n"]) + 1)
	var rec_e: Dictionary = ReplayRecorder.load_record(rid)
	var ee: Array = rec_e.get("events", [])
	_ok("★★E 判负走的是认输结算: 录像里只有一条开局认输(%s · 结束步 %s)、录像版本 = 本机" % [_ev_str(ee), str((rec_e.get("end", {}) as Dictionary).get("s", "?"))],
		ee.size() == 1 and str(ee[0]["k"]) == "surrender" and int(ee[0]["s"]) <= 1
		and str(rec_e.get("client_version", "")) == ReplayRecorder.client_version())
	_ok("★E 结算屏顶上写着判负原因「%s」" % str(re["header"]), str(re["header"]) == AM.TXT_LOSS_VERSION)
	_ok("★E 判负那一局也只结一次、单子删了", _count_id(gs, rid) == 1 and not AM.exists())
	## 结算口径跟着【开局那一刻】的阶段走(单子里的 phase), 不是重开时存档里的: 周六 ⇒ 记闯关负场、不扣命
	_restore(gs, pre)
	var kg: Dictionary = kv.duplicate(true)
	(kg["meta"] as Dictionary)["phase"] = "gauntlet"
	AM.write(kg["rec"], kg["meta"])
	var gl0 := int(gs.gauntlet_losses)
	_ok("分母 · E 周六那一份判定 loss_version、单子里的阶段摆回去了(重开前存档里 %s)" % str(gs.week_phase),
		AM.prepare() == "loss_version" and str(gs.week_phase) == "gauntlet")
	var rg: Dictionary = await _run_resume(-1)
	_ok("★E 周六那一局按闯关赛结: 闯关负场 +1、不扣命、不吃积分赛配额(负 %d→%d · 命 %d · 配额 %d)" % [gl0, int(gs.gauntlet_losses), int(gs.hearts), int(gs.ranked_used)],
		bool(rg["finished"]) and int(gs.gauntlet_losses) == gl0 + 1 and int(gs.hearts) == int(pre_l["hearts"])
		and int(gs.ranked_used) == int(pre_l["ranked_used"]))
	## 周日决赛场: 单子里带着 finals_match(它不在存档里) ⇒ 结算照常记补报单(带那一场的种子) + 待揭晓
	_restore(gs, pre)
	gs.finals_match = {}
	var kf: Dictionary = kv.duplicate(true)
	(kf["meta"] as Dictionary)["phase"] = "finals"
	(kf["meta"] as Dictionary)["finals_match"] = {"bucket": 3, "round": 2, "match": 1, "side": 0}
	AM.write(kf["rec"], kf["meta"])
	_ok("分母 · E 周日那一份判定 loss_version", AM.prepare() == "loss_version")
	var rfn: Dictionary = await _run_resume(-1)
	var frp: Dictionary = gs.finals_report_pending
	_ok("★E 周日那一局照常报结果: 补报单 桶3 第2轮 第1场 判给对面(side 1)、种子 = 原局种子(%s)" % str(frp),
		bool(rfn["finished"]) and int(frp.get("bucket", -1)) == 3 and int(frp.get("round", -1)) == 2
		and int(frp.get("match", -1)) == 1 and int(frp.get("side", -1)) == 1
		and int(frp.get("seed", -1)) == GameState.note_battle_seed(int((kf["rec"] as Dictionary)["seed"]))
		and (gs.finals_pending_reveal as Dictionary).get("round", -1) == 2 and (gs.finals_match as Dictionary).is_empty())
	_ok("★E 周日那一局不扣命", int(gs.hearts) == int(pre_l["hearts"]))
	## 跨周 ⇒ 作废
	_restore(gs, pre)
	var kw: Dictionary = kp.duplicate(true)
	(kw["meta"] as Dictionary)["week"] = int(gs.week_anchor_ts) - 7 * 86400
	AM.write(kw["rec"], kw["meta"])
	var l0: Dictionary = _ledger(gs)
	AM.notice = ""
	_ok("★E 跨周 ⇒ 判定 void_week、单子删了、不进战斗场", AM.prepare() == "void_week" and not AM.exists() and AM.pending_resume.is_empty())
	_ok("★E 跨周作废不动账、主菜单提示「%s」" % AM.notice, var_to_bytes(l0) == var_to_bytes(_ledger(gs)) and AM.notice == AM.TXT_VOID_WEEK)
	AM.notice = ""
	## 复算闪退过头
	var kt: Dictionary = kp.duplicate(true)
	(kt["meta"] as Dictionary)["tries"] = AM.MAX_RESIM_TRIES
	AM.write(kt["rec"], kt["meta"])
	_ok("★E 复算闪退 %d 次 ⇒ 判定 loss_crash(改判负)" % AM.MAX_RESIM_TRIES, AM.prepare() == "loss_crash")
	AM.pending_resume = {}
	_restore(gs, pre)
	(kt["meta"] as Dictionary)["tries"] = AM.MAX_RESIM_TRIES + 1
	AM.write(kt["rec"], kt["meta"])
	_ok("★E 判负那一次也没结算完 ⇒ 判定 void_crash、单子删了", AM.prepare() == "void_crash" and not AM.exists())
	AM.notice = ""
	_ok("★E 坏单 ⇒ 删掉、判定 none", _bad_file_none())

	# ── F 真「被杀」: 开一局、打一会儿、释放战斗场(不结算) ──
	print("=== F 真被杀 ===")
	_restore(gs, pre)
	var fk: Dictionary = await _run_kill()
	var fp: Dictionary = AM.read()
	_ok("★F 被杀后单子在、id 是那一局的、未结算", not fp.is_empty() and str((fp["rec"] as Dictionary).get("id", "")) == str(fk["id"])
		and not AM.is_settled(str(fk["id"])), str(fk))
	_ok("★F 账没动(被杀那一局没结算)", var_to_bytes(_ledger(gs)) == var_to_bytes(pre_l))
	_ok("★F 重开判定 resume", AM.prepare() == "resume")
	var rf: Dictionary = await _run_resume(-1)
	_ok("★F 复算打完结算一次", bool(rf["finished"]) and _count_id(gs, str(fk["id"])) == 1 and not AM.exists())
	_finish()


func _ledger_of(snap: Dictionary) -> Dictionary:
	var out := {}
	for k in LEDGER:
		out[k] = snap.get(k)
	var h: Array = snap.get("match_history", [])
	out["hist_n"] = h.size()
	out["hist0"] = str((h[0] as Dictionary).get("result", "")) if not h.is_empty() else ""
	return out


func _count_id(gs, id: String) -> int:
	var n := 0
	for row in gs.match_history:
		if row is Dictionary and str((row as Dictionary).get("replay_id", "")) == id:
			n += 1
	return n


func _write_raw(b: PackedByteArray) -> void:
	var f := FileAccess.open(AM.PATH, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _bad_file_none() -> bool:
	_write_raw(PackedByteArray([1, 2, 3, 4, 5, 6, 7]))
	return AM.prepare() == "none" and not AM.exists()


func _ev_str(evs: Array) -> String:
	var out := []
	for e in evs:
		out.append("%s@%d%s" % [str(e.get("k", "")), int(e.get("s", -1)), "i" if bool(e.get("i", false)) else ""])
	return str(out)


## 参照局: det 模式(一帧恰一步), 扮演玩家。每路一进摆位就开打 —— 与复算「摆位屏立刻开打」同一个时刻;
##   第一路开打前拖一只龟、开局总览点一下幕布(这两条是复算要从单子里重放的前缀输入)。
func _run_ref() -> Dictionary:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._deterministic = true
	var pid0 := str(s._replay.rec.get("id", ""))
	var p0: Dictionary = AM.read()
	var pending_at_start: bool = not p0.is_empty() and str((p0["rec"] as Dictionary).get("id", "")) == pid0 and pid0 != ""
	var fights := 0
	var clicked := false
	var dragged := false
	var st_frames := 0
	var last := ""
	var fight1 := -1
	var kill := PackedByteArray()
	var done_frames := 0
	for _i in range(MAX_FRAMES):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			st_frames = 0
		st_frames += 1
		if st == "overview" and st_frames == 9 and not clicked:
			s._dl_sys._dl_present_click()
			clicked = true
		elif st == "place" and st_frames == 1:
			if fights == 0:
				for u in s._units:
					if str(u.get("side", "")) == "left" and s._can_place_drag(u):
						var q0: Vector2 = u["pos"]
						u["pos"] = s._dl_sys._dl_clamp_place(q0 + Vector2(-70.0, 40.0))
						dragged = (u["pos"] as Vector2) != q0
						break
			s._dl_sys._dl_start_fight()
			fights += 1
			if fights == 1:
				fight1 = int(s._sim_step_n)
		s._process(s.SIM_DT)
		await get_tree().process_frame
		if kill.is_empty() and fight1 >= 0 and int(s._sim_step_n) >= fight1 + KILL_AFTER:
			kill = FileAccess.get_file_as_bytes(AM.PATH)
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 5:
				break
	var out := {"state": str(s._dl_state), "fights": fights, "clicked": clicked, "dragged": dragged,
		"kill": kill, "pid0": pid0, "pending_at_start": pending_at_start}
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out


## 重开后复算: 战斗场照常跑(引擎自己调 _process), 等它结算并撤掉遮罩。kill_frames ≥ 0 = 跑这么多帧就释放(复算途中被杀)。
func _run_resume(kill_frames: int) -> Dictionary:
	var s = RB.new()
	add_child(s)
	var f := 0
	var revealed := false
	while f < MAX_FRAMES:
		await get_tree().process_frame
		f += 1
		if kill_frames >= 0 and f >= kill_frames:
			break
		if s._replay.finished and bool(s._settled) and s.get_node_or_null("AbandonedHeader") != null:
			revealed = true
			break
	var hd := s.get_node_or_null("AbandonedHeader/AbandonedHeaderLabel")
	var out := {"finished": bool(s._replay.finished), "settled": bool(s._settled), "revealed": revealed,
		"steps": int(s._replay.resume_steps), "frames": f, "dropped": str(s._replay.resume_dropped),
		"mode": str(s._replay.mode), "header": (hd as Label).text if hd != null else "",
		"cover_left": s.get_node_or_null("AbandonedCover") != null, "muted": bool(get_node("/root/Audio").mute_sfx)}
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out


## 真被杀: 正常开一局(引擎自己跑), 跑一会儿就释放, 结算一行都不跑。
func _run_kill() -> Dictionary:
	var s = RB.new()
	add_child(s)
	for _i in range(60):
		await get_tree().process_frame
	var out := {"id": str(s._replay.rec.get("id", "")), "mode": str(s._replay.mode), "steps": int(s._sim_step_n)}
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	return out


func _finish() -> void:
	AM.clear()
	print("")
	if _fail == 0:
		print("ALL PASS — 中途退出自动结算 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
