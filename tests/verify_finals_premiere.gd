extends Node
## verify_finals_premiere.gd — 周日逐轮开播门禁(方案书 docs/plans/20261007-实时观赛.md「周日·逐轮开播」)
##
## 原稿 §六「晚上节目单式逐轮同步开播，观众观看时不知结果——物理上是回放，体感上是直播」;
## 用户 2026-10-07「观赛和回放是两码事明白吗」。
##
## 段落:
##   ① 纯函数 `live_spectate`: 哪一轮在开播(没收盘 = 上一轮 / 收盘 = 最后一轮)/ 翻面时刻(revealed_at 优先,
##      没有就退回 round_at, 收盘又没有 revealed_at ⇒ 不开播)/ 窗口(翻面 + 上限 或 + 真实时长 + 缓冲)边界逐秒
##   ② 对阵图(观众): 窗口内那一轮没有 ✓、没有「胜」、标「开播」; 下一轮那个坑写「待定」; 弹卡不写胜负、按钮「观赛」;
##      窗口一过 ⇒ ✓ / 胜者 / 「X 获胜」/「观看」全回来; 看过的那一场在窗口内也揭晓
##   ③ 对阵图(选手): 我在下一轮那一场 ⇒ 对手名字照常(要打), 「开始对战」照常
##   ④ 收盘那一轮: 有 revealed_at ⇒ 决赛也开播(没有「冠」); 没有 revealed_at ⇒ 直接揭晓
##   ⑤ 观赛跟播: 点「观赛」(真入口)⇒ 观赛模式「开播」小签、无播放控件; 追帧到「翻面至今」的那一步再 1 倍跟播(不倒回);
##      看完 ⇒ 收尾卡揭晓胜者; 回到对阵图那一场立刻揭晓(其余仍在窗口里)
##   ⑥ 迟到到这一场已经播完 ⇒ 当回放放(带控件), 并记成看过
##   ⑦ 服务端下发 revealed_at / round_at(周视图), JSON null 当 0
## 每条新断言都做过反向验证(改坏 → 红 → 逐字节还原), 见方案书「实施回填」。

const SB := preload("res://scripts/net/supabase.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const BRACKET := "res://scenes/BracketMap.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const DT := 1.0 / 60.0

var _fail := 0
var _n := 0
var _gs
var _now := 0
var _rec: Dictionary = {}
var _id := ""
var _asked := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	_gs.test_mode = true
	_gs.finals_pending_reveal = {}
	LS.watched = {}
	LS.known_len = {}
	## 一个周日晚上(服务器钟)
	_now = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 20 * 3600
	_t_pure()
	_t_parse()
	_t_rng_031()
	await _t_spectator_map()
	await _t_player_map()
	await _t_closed()
	await _record()
	if _id != "":
		await _t_watch()
		await _t_late()
	_cleanup()
	_finish()


func _cleanup() -> void:
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	LS.pending = {}
	LS.watched = {}
	LS.known_len = {}
	_gs.finals_pending_reveal = {}


# ① ─────────────────────────────────────────────────────────────
func _b(rnd: int, closed: bool, round_at: int, revealed: int, done: Dictionary, bucket: int = 0) -> Dictionary:
	return {"bucket": bucket, "size": 8, "round": rnd, "closed": closed, "round_at": round_at,
		"revealed_at": revealed, "done": done}


func _t_pure() -> void:
	print("── ① 开播窗口(纯函数) ──")
	var T := 1_000_000
	var d1 := {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}
	var b := _b(2, false, T, T, d1)
	_ok("① 没收盘: 开播的是上一轮", LS.premiere_round(b) == 1)
	_ok("① 收盘: 开播的是最后一轮", LS.premiere_round(_b(3, true, T, T, {})) == 3)
	_ok("① 第 1 轮还没翻过面 ⇒ 0", LS.premiere_round(_b(1, false, T, 0, {})) == 0)
	_ok("① 翻面时刻: revealed_at 优先", LS.flip_ts_of(_b(2, false, T - 50, T, d1)) == T)
	_ok("① ★没有 revealed_at(服务端没上线)·没收盘 ⇒ 退回 round_at", LS.flip_ts_of(_b(2, false, T, 0, d1)) == T)
	_ok("① ★收盘又没有 revealed_at ⇒ 0(不开播)", LS.flip_ts_of(_b(3, true, T, 0, {})) == 0)
	_ok("① 第 1 轮的 round_at 不是翻面时刻 ⇒ 0", LS.flip_ts_of(_b(1, false, T, 0, {})) == 0)
	_ok("① 窗口上限 = 翻面 + %d" % LS.PREMIERE_SEC, LS.premiere_end(T, 0) == T + LS.PREMIERE_SEC)
	_ok("① 知道时长 ⇒ 翻面 + ceil(步数/60) + %d" % LS.PREMIERE_BUFFER, LS.premiere_end(T, 3001) == T + 51 + LS.PREMIERE_BUFFER)
	var e := T + LS.PREMIERE_SEC
	var edges := [[T - 1, false], [T, true], [T + 1, true], [e - 1, true], [e, false], [e + 100, false]]
	var bad: Array = []
	for pr in edges:
		if LS.premiere_hidden(b, 1, 0, int(pr[0])) != bool(pr[1]):
			bad.append(int(pr[0]) - T)
	_ok("① ★窗口边界逐秒: 翻面前不藏 / [翻面, 翻面+%d) 藏 / 之后不藏" % LS.PREMIERE_SEC, bad.is_empty(), str(bad))
	_ok("① 不是开播那一轮 ⇒ 不藏", not LS.premiere_hidden(_b(3, false, T, T, {"1-0": 0, "2-0": 1}), 1, 0, T + 5))
	_ok("① done 里没有这一场 ⇒ 不藏(当前轮本来就没有结果)", not LS.premiere_hidden(b, 2, 0, T + 5))
	var k := LS.premiere_key(b, 1, 0)
	LS.known_len[k] = 1200
	_ok("① 知道这一场 20 秒 ⇒ 窗口 = 翻面 + 20 + %d" % LS.PREMIERE_BUFFER,
		LS.premiere_hidden(b, 1, 0, T + 20 + LS.PREMIERE_BUFFER - 1) and not LS.premiere_hidden(b, 1, 0, T + 20 + LS.PREMIERE_BUFFER))
	LS.known_len = {}
	LS.watched[k] = true
	_ok("① ★这台设备看完了 ⇒ 窗口内也不藏", not LS.premiere_hidden(b, 1, 0, T + 5) and LS.premiere_hidden(b, 1, 1, T + 5))
	LS.watched = {}
	_ok("① key 带翻面时刻(下一周同一坐标不会撞)", LS.premiere_key(b, 1, 0) != LS.premiere_key(_b(2, false, T + 604800, T + 604800, d1), 1, 0))


# ⑧ ─────────────────────────────────────────────────────────────
## ★开播 / 直播 / 回放都是「本机重算」: 一处没播种的随机改了结果, 观众就在那一刻「直播中断」。
##   2026-10-07 本方案实施时查出的那一处: 031 水晶扫射的起始角用的是裸 `randf()`(引擎全局 RNG)
##   ⇒ 同一份录像重播 7 次分叉 4 次(探针 tests/_probe_lf_speed.gd)。这里钉住它不再回退。
func _t_rng_031() -> void:
	print("── ⑧ 031 扫射起始角走种子化 RNG ──")
	var f := FileAccess.open("res://scripts/systems/equip/equip_system.gd", FileAccess.READ)
	var src := f.get_as_text().replace("\r\n", "\n") if f != null else ""
	var a := src.find("func _eq_crystal_sweep(")
	var b := src.find("\nfunc ", a + 10)
	var body := src.substr(a, b - a) if a >= 0 and b > a else ""
	var code := ""
	for ln in body.split("\n"):
		code += str(ln).split("#")[0] + "\n"
	var re := RegEx.new()
	re.compile("(?<![\\.\\w])(randf|randi|randf_range|randi_range)\\s*\\(")
	_ok("⑧ 分母: 找到 _eq_crystal_sweep 函数体", body.length() > 200)
	_ok("⑧ 分母: 这条正则认得出裸 randf(喂一行样本)", re.search("\tvar x := randf() * TAU\n") != null and re.search("x = battle._battle_rng.randf()") == null)
	_ok("⑧ ★起始角走 battle._battle_rng(没有裸 randf)", code.contains("battle._battle_rng.randf()") and re.search(code) == null)


# ⑦ ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ⑦ 服务端下发 ──")
	var body := JSON.stringify({"ok": true, "week": 1, "now": 5000, "buckets": [
		{"bucket": 0, "n": 4, "round": 2, "closed": false, "round_at": 4000, "revealed_at": 4000,
			"done": {"1-0": 0, "1-1": 1}, "entrants": [{"seed": 0, "name": "a", "account_id": "x"}]},
		{"bucket": 1, "n": 4, "round": 2, "closed": false, "round_at": 4100, "revealed_at": null,
			"done": {"1-0": 0}, "entrants": []}]})
	var w: Dictionary = SB.parse_finals_week(true, 200, body, "", 777)
	var bs: Array = w.get("buckets", [])
	_ok("⑦ 分母: 两组", bs.size() == 2)
	if bs.size() == 2:
		_ok("⑦ ★周视图每组带 revealed_at / round_at / 服务端钟", int(bs[0]["revealed_at"]) == 4000 and int(bs[0]["round_at"]) == 4000
			and int(bs[0]["srv_now"]) == 5000)
		_ok("⑦ revealed_at 是 JSON null ⇒ 0(不报错)", int(bs[1]["revealed_at"]) == 0 and int(bs[1]["round_at"]) == 4100)
	var one: Dictionary = SB.parse_finals(true, 200, JSON.stringify({"ok": true, "bucket": 3, "n": 4, "round": 2, "closed": false,
		"round_at": 9000, "revealed_at": 9000, "next_at": 9480, "now": 9010, "entrants": [], "done": {"1-0": 1}}), "", 1)
	_ok("⑦ 我那一组(finals_view)也带 revealed_at", int(one.get("revealed_at", -1)) == 9000)
	var old: Dictionary = SB.parse_finals(true, 200, JSON.stringify({"ok": true, "bucket": 3, "n": 4, "round": 2, "closed": false,
		"round_at": 9000, "next_at": 9480, "now": 9010, "entrants": [], "done": {"1-0": 1}}), "", 1)
	_ok("⑦ 服务端没上线(没有这个键) ⇒ 0", int(old.get("revealed_at", -1)) == 0)


# ② ─────────────────────────────────────────────────────────────
func _week(flip: int, closed: bool = false, revealed: int = -1, rnd: int = 2, done: Dictionary = {}) -> Dictionary:
	var nm := ["石头统领", "海风小将", "阿龟", "竹林隐士", "老船长", "浪里白条", "夜光贝", "铁甲先生"]
	var ents: Array = []
	for i in range(8):
		ents.append({"seed": i, "name": nm[i], "account_id": "acct-%d" % i})
	var dd: Dictionary = done if not done.is_empty() else {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1}
	return SB.parse_finals_week(true, 200, JSON.stringify({"ok": true, "week": 1, "now": _now, "buckets": [
		{"bucket": 0, "n": 8, "round": rnd, "closed": closed, "round_at": flip,
			"revealed_at": flip if revealed < 0 else revealed, "done": dd, "entrants": ents}]}), "", _now)


func _open_map(w: Dictionary, now: int, bucket: Dictionary = {}) -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	var m: Node = (load(BRACKET) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	await _frames(3)
	m.set_data(bucket, {}, now)
	m.set_week(w)
	await _frames(6)
	return m


func _ticks(m: Node) -> int:
	var k := 0
	for c in m._canvas.find_children("*", "Label", true, false):
		if str((c as Label).text).begins_with("✓"):
			k += 1
	return k


func _badges(m: Node, t: String) -> int:
	var k := 0
	for c in m._canvas.find_children("*", "Label", true, false):
		if str((c as Label).text) == t:
			k += 1
	return k


func _node_btn(m: Node, r: int, mm: int) -> Button:
	for c in m._canvas.find_children(BMS.N_NODE_BTN, "Button", true, false):
		if (c as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return c
	return null


func _popup_texts(m: Node) -> Array:
	var out: Array = []
	var p: Node = m.find_child("MatchPopup", true, false)
	if p != null:
		for c in p.find_children("*", "Label", true, false):
			out.append((c as Label).text)
		for c in p.find_children("*", "Button", true, false):
			out.append("[%s]" % (c as Button).text)
	return out


func _t_spectator_map() -> void:
	print("── ② 对阵图(观众): 窗口内 / 窗口后 / 看过的 ──")
	var flip := _now - 30
	var m: Node = await _open_map(_week(flip), _now)
	_ok("② 分母: 观赛那一组(8 人, 第 2 轮, 我不在里面)", int(m.cur().get("size", 0)) == 8 and int(m.cur().get("me", 0)) == -1)
	_ok("② 分母: 第 1 轮四场都在 done 里", (m.cur().get("done", {}) as Dictionary).size() == 4)
	_ok("② ★窗口内: 一个 ✓ 都没有", _ticks(m) == 0, "✓ %d" % _ticks(m))
	_ok("② ★窗口内: 没有「胜」也没有「冠」", _badges(m, "胜") == 0 and _badges(m, "冠") == 0)
	_ok("② ★窗口内: 第 1 轮四场都标「开播」", m._canvas.find_children("PremiereTag", "", true, false).size() == 4
		and _badges(m, "开播") == 4)
	var tbd := 0
	for side in [0, 1]:
		for mm in range(2):
			if str(m.competitor(2, mm, side).get("name", "")) == "待定":
				tbd += 1
	_ok("② ★窗口内: 第 2 轮四个坑都写「待定」(名字本身就是剧透)", tbd == 4, "%d" % tbd)
	_ok("② 窗口内: 第 1 轮四格都能点(观赛)", _node_btn(m, 1, 0) != null and _node_btn(m, 1, 3) != null
		and str(m.match_state(1, 0)) == BMS.ST_PREMIERE)
	_node_btn(m, 1, 0).pressed.emit()
	await _frames(3)
	var pt := _popup_texts(m)
	_ok("② ★窗口内弹卡: 横幅「开播」、不写「获胜」、按钮「观赛」", pt.has("开播") and not str(pt).contains("获胜")
		and pt.has("[观赛]") and not pt.has("[观看]"), str(pt))
	m._close_popup()
	## 窗口过了(翻面 + 上限)
	var m2: Node = await _open_map(_week(flip), flip + LS.PREMIERE_SEC)
	_ok("② ★窗口一过: 四个 ✓ 回来、「开播」没了", _ticks(m2) == 4 and m2._canvas.find_children("PremiereTag", "", true, false).is_empty(),
		"✓ %d" % _ticks(m2))
	_ok("② 窗口一过: 第 2 轮的坑写出名字", str(m2.competitor(2, 0, 0).get("name", "")) == "石头统领")
	_node_btn(m2, 1, 0).pressed.emit()
	await _frames(3)
	var pt2 := _popup_texts(m2)
	_ok("② ★窗口一过弹卡: 「X 获胜」+「观看」", str(pt2).contains("石头统领 获胜") and pt2.has("[观看]"), str(pt2))
	m2._close_popup()
	## 看过 1-1 那一场 ⇒ 窗口内它也揭晓, 其余照旧
	var b0: Dictionary = m2.cur()
	LS.watched[LS.premiere_key(b0, 1, 1)] = true
	var m3: Node = await _open_map(_week(flip), _now)
	_ok("② ★看过的那一场窗口内也揭晓(✓ 1 个、「开播」3 个)", _ticks(m3) == 1
		and m3._canvas.find_children("PremiereTag", "", true, false).size() == 3, "✓ %d" % _ticks(m3))
	LS.watched = {}
	## 服务端没上线 revealed_at(=0): 没收盘 ⇒ 退回 round_at 照样开播
	var m4: Node = await _open_map(_week(flip, false, 0), _now)
	_ok("② ★服务端没有 revealed_at ⇒ 按 round_at 照样开播", _ticks(m4) == 0 and _badges(m4, "开播") == 4)
	## 轮询指纹: 窗口一过要重画
	_ok("② 轮询指纹里有开播场数(4 → 窗口外 0)", m4.premiere_count() == 4)
	m4._now_override = flip + LS.PREMIERE_SEC
	_ok("② 窗口外 premiere_count = 0", m4.premiere_count() == 0)


# ③ ─────────────────────────────────────────────────────────────
func _t_player_map() -> void:
	print("── ③ 对阵图(选手): 下一轮有我 ──")
	var flip := _now - 30
	var ents: Array = []
	var nm := ["我自己", "乙", "丙", "丁"]
	for i in range(4):
		ents.append({"seed": i, "name": nm[i], "account_id": ME if i == 0 else "acct-x%d" % i})
	var bk: Dictionary = SB.parse_finals(true, 200, JSON.stringify({"ok": true, "bucket": 0, "n": 4, "round": 2, "closed": false,
		"round_at": flip, "revealed_at": flip, "next_at": flip + 480, "now": _now, "entrants": ents,
		"done": {"1-0": 0, "1-1": 1}}), ME, int(Time.get_unix_time_from_system()))
	_gs.account_id = ME
	var m: Node = await _open_map({"buckets": []}, _now, bk)
	_ok("③ 分母: 我那一组(4 人, 我是 0 号, 第 2 轮)", int(m.cur().get("me", -1)) == 0 and int(m.cur().get("round", 0)) == 2)
	_ok("③ 分母: 第 1 轮两场都在开播窗口里", m.premiere_hidden(1, 0) and m.premiere_hidden(1, 1))
	var foe := str(m.competitor(2, 0, 1).get("name", ""))
	_ok("③ ★决赛有我 ⇒ 对手名字照常写(要打)", foe != "待定" and foe != "" and m.is_my_match(2, 0), foe)
	_ok("③ ★「开始对战」照常(问得出对手)", m.should_fetch_opponent(2, 0) and m.my_opponent_seed(2, 0) >= 0)
	_ok("③ 第 1 轮那两格仍不写胜负", _ticks(m) == 0)


# ④ ─────────────────────────────────────────────────────────────
func _t_closed() -> void:
	print("── ④ 收盘那一轮 ──")
	var flip := _now - 30
	var done := {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1, "2-0": 0, "2-1": 1, "3-0": 1}
	var m: Node = await _open_map(_week(flip, true, flip, 3, done), _now)
	_ok("④ 分母: 收盘、7 场都在 done", bool(m.cur().get("closed", false)) and (m.cur().get("done", {}) as Dictionary).size() == 7)
	_ok("④ ★有 revealed_at ⇒ 决赛在开播: 没有「冠」、决赛标「开播」, 前两轮照常揭晓(✓ 6 个)",
		_badges(m, "冠") == 0 and str(m.match_state(3, 0)) == BMS.ST_PREMIERE and _ticks(m) == 6, "✓ %d" % _ticks(m))
	var m2: Node = await _open_map(_week(flip, true, 0, 3, done), _now)
	_ok("④ ★收盘但没有 revealed_at ⇒ 不开播, 直接揭晓(有「冠」、✓ 7 个)", _badges(m2, "冠") == 1 and _ticks(m2) == 7,
		"✓ %d" % _ticks(m2))


# ⑤ ─────────────────────────────────────────────────────────────
func _record() -> void:
	print("── 录一局(当作被采纳的那一份) ──")
	_gs.reset_dual_lane()
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.week_phase = "ranked"
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var last := ""
	var stf := 0
	var fights := 0
	var i := 0
	while i < 6000 and not s._replay.finished:
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fights += 1
		elif st == "fight" and fights >= 2 and stf == 200:
			s._do_surrender()
		s._process(0.05)
		if i % 4 == 0:
			await get_tree().process_frame
		i += 1
	await _frames(4)
	_id = str(s._replay.rec.get("id", ""))
	_rec = ReplayRecorder.load_record(_id)
	_ok("分母: 录好了一局(%d 步)" % int((_rec.get("end", {}) as Dictionary).get("s", -1)), not _rec.is_empty()
		and int((_rec.get("end", {}) as Dictionary).get("s", -1)) > 600)
	s.queue_free()
	await _frames(4)
	if _rec.is_empty():
		_id = ""
		return
	OS.set_environment(SB.ENV_URL, "http://premiere.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "premiere-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"


func _transport(m, u, _h, _b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/rpc/finals_replay") >= 0:
		_asked += 1
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "match_id": _id, "replay": RU.upload_b64(_rec)})})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


func _is_map(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == BMS


func _wait_scene(pred: Callable, max_frames: int = 240) -> Node:
	for _i in range(max_frames):
		var cs := get_tree().current_scene
		if pred.call(cs):
			return cs
		await get_tree().process_frame
	return null


func _t_watch() -> void:
	print("── ⑤ 观赛跟播(开播) ──")
	var tot := int((_rec["end"] as Dictionary)["s"])
	## 翻面在「这一场还剩 8 秒」的那一刻之前: 进去要追到 tot − 480 附近, 再 1 倍看完最后 8 秒
	var flip := _now - (tot / 60 - 8)
	var m: Node = await _open_map(_week(flip), _now)
	_ok("⑤ 分母: 第 1 轮第 1 场在开播窗口里", str(m.match_state(1, 0)) == BMS.ST_PREMIERE)
	var key := LS.premiere_key(m.cur(), 1, 0)
	_node_btn(m, 1, 0).pressed.emit()
	await _frames(2)
	var go := m.find_child(BMS.N_POPUP_GO, true, false) as Button
	_ok("⑤ 弹卡按钮「观赛」", go != null and go.text == "观赛")
	## ★2026-10-07 用户「按钮框能不能换一种呢，这不适合我们啊」: 周末页按钮从木牌(`menu/frame-rect.png`)
	##   换成像素按钮表 `UISkin.PIXEL_BTN`; 观赛 = 红那一行, 关闭 = 石板那一行(表的行号见 ui_skin.gd)。
	##   量的是**按钮真拿到的那张 StyleBox**, 不是调用方传了什么参数。
	var cl := m.find_child(BMS.N_POPUP_CLOSE, true, false) as Button
	for pair in [[go, 0, "观赛=红"], [cl, 2, "关闭=石板"]]:
		var pb := pair[0] as Button
		var psb = pb.get_theme_stylebox("normal") if pb != null else null
		var ppath := str((psb as StyleBoxTexture).texture.resource_path) if psb is StyleBoxTexture else ""
		var prow := int((psb as StyleBoxTexture).region_rect.position.y / UISkin.PX_CELL.y) if psb is StyleBoxTexture else -1
		_ok("⑤ ★弹卡按钮(%s)用像素按钮皮, 不是木牌" % str(pair[2]),
			ppath == UISkin.PIXEL_BTN and prow == int(pair[1]) and ppath.find("frame-rect") < 0,
			"贴图 %s 行 %d" % [ppath, prow])
	go.pressed.emit()
	var b = await _wait_scene(_is_battle)
	_ok("⑤ ★进了战斗场、是观赛(开播)", b != null and b._replay.is_live() and str(b._replay.live.kind) == LS.KIND_PREMIERE,
		"%s %s" % [str(m.last_replay_code) if is_instance_valid(m) else "", str(m.last_replay_msg) if is_instance_valid(m) else ""])
	_ok("⑤ 取的是这一场(组 0 / 第 1 轮 / 第 1 场)", _asked == 1)
	if b == null or not b._replay.is_live():
		return
	b.set_process(false)
	var lv = b._replay.live
	b._process(DT)
	await _frames(2)
	var mark := b.find_child("ReplayMark", true, false) as Control
	var ml: Array = mark.find_children("*", "Label", true, false) if mark != null else []
	_ok("⑤ ★顶栏小签「开播」", ml.size() == 1 and (ml[0] as Label).text == LS.TAG_PREMIERE)
	var found: Array = []
	for nm in [RC.N_PAUSE, RC.N_SPEED, RC.N_TIME, "ReplayStrip", RC.N_PAUSED]:
		if b.find_child(nm, true, false) != null:
			found.append(nm)
	_ok("⑤ ★没有暂停 / 倍速 / 进度条 / 时长(不能倒回、不能快进)", found.is_empty(), str(found))
	var caught_n := -1
	var caught_tgt := -1
	var mono := true
	var prev := int(b._sim_step_n)
	var frames := 0
	var sync_seen := false
	var tw := Time.get_ticks_msec()
	while frames < 6000 and not b._replay.finished and b._replay.diverged_at < 0 and Time.get_ticks_msec() - tw < 120000:
		frames += 1
		b._process(DT)
		var n := int(b._sim_step_n)
		if n < prev:
			mono = false
		prev = n
		if str(lv.status) == LS.TXT_SYNC:
			sync_seen = true
		if caught_n < 0 and not lv.catching:
			caught_n = n
			caught_tgt = lv.target_step()
		## 一帧喂 4 次 `_process`(每次至多 8 步): CI 无头 15 帧/秒时追帧也追得上真实时间(--max-fps 15 实测过)
		if frames % 4 == 0:
			await get_tree().process_frame
	var want_lo := (tot / 60 - 8) * 60
	_ok("⑤ ★追帧到「翻面至今」那一步(追上时第 %d 步 / 应在 ≥ %d)" % [caught_n, want_lo],
		caught_n >= want_lo and caught_n >= caught_tgt - LS.CATCH_PER_FRAME and caught_n <= caught_tgt + LS.CATCH_PER_FRAME,
		"target %d" % caught_tgt)
	_ok("⑤ 追帧时屏上「同步中」", sync_seen)
	_ok("⑤ 步号只增不减(不倒回)", mono)
	## 终局(结算那一步的步号 + 指纹 + 胜负)由 `on_settle` 播放分支逐字比过, 对不上会记成分叉 ⇒ 这里看 diverged_at。
	##   (不直接比 `_sim_step_n`: 结算那一帧里剩下的几步照样会跑完, 步号会比结算步多几步。)
	_ok("⑤ ★看完: 不分叉、终局一致(on_settle 比过结算步号与指纹)", b._replay.finished and b._replay.diverged_at < 0 and int(b._sim_step_n) >= tot,
		"fin=%s n=%d tot=%d frames=%d %s" % [str(b._replay.finished), int(b._sim_step_n), tot, frames, str(b._replay.diverge_why)])
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 2500 and b.find_child(RC.N_CARD, true, false) == null:
		await get_tree().process_frame
	var card: Node = b.find_child(RC.N_CARD, true, false)
	var res := card.find_child("ReplayResult", true, false) as Label if card != null else null
	_ok("⑤ ★收尾卡揭晓胜者(石头统领 获胜)、没有「再看一遍」、有「返回对阵图」",
		res != null and res.text == "石头统领 获胜" and card.find_child(RC.N_AGAIN, true, false) == null
		and (card.find_child(RC.N_BACK, true, false) as Button).text == "返回对阵图", res.text if res != null else "<无卡>")
	_ok("⑤ ★看完记成看过", LS.watched.has(key))
	(card.find_child(RC.N_BACK, true, false) as Button).pressed.emit()
	var back = await _wait_scene(_is_map)
	_ok("⑤ 回到对阵图", back != null)
	if back != null:
		back.set_data({}, {}, _now)
		back.set_week(_week(flip))
		await _frames(6)
		_ok("⑤ ★回来之后那一场揭晓(✓ 1 个), 其余三场仍在开播", _ticks(back) == 1
			and back._canvas.find_children("PremiereTag", "", true, false).size() == 3, "✓ %d" % _ticks(back))


# ⑥ ─────────────────────────────────────────────────────────────
func _t_late() -> void:
	print("── ⑥ 迟到 ──")
	LS.watched = {}
	LS.known_len = {}
	var tot := int((_rec["end"] as Dictionary)["s"])
	var flip := _now - (tot / 60 + 5)
	var m: Node = await _open_map(_week(flip), _now)
	_ok("⑥ 分母: 翻面已过 %d 秒, 但还在窗口上限里 ⇒ 仍藏着" % (tot / 60 + 5), str(m.match_state(1, 0)) == BMS.ST_PREMIERE)
	var key := LS.premiere_key(m.cur(), 1, 0)
	m.open_replay(1, 0)
	var b = await _wait_scene(_is_battle)
	_ok("⑥ ★这一场已经播完 ⇒ 当回放放(有暂停钮), 不是观赛", b != null and b._replay.is_playing() and not b._replay.is_live())
	if b != null:
		b.set_process(false)
		b._process(DT)
		await _frames(2)
		_ok("⑥ 回放有暂停钮", b.find_child(RC.N_PAUSE, true, false) != null)
	_ok("⑥ ★记成看过、记下真实时长", LS.watched.has(key) and int(LS.known_len.get(key, 0)) == tot)
	if b != null:
		b._hud._replay_exit()
		await _frames(6)


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周日逐轮开播" if _fail == 0 and _n > 40 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
