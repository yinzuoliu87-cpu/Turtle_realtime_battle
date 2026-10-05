extends Node
## verify_replay_watch.gd — 回放 S3 门禁「战绩页看回放」(方案书 docs/plans/20261003-跨设备回放.md S3)
##
## 用户原话:「理想效果是我能在其他设备上看到比赛回放」。
##
## ★全程走真入口: 真战斗场录一局周六闯关赛 → 真的实例化 `Record.tscn` → **按那一行的按钮**
##   (`pressed.emit()`, 就是手指点下去那个信号) → `ReplayFetcher.open` → `ReplayRecorder.play`
##   真换场景到 `RealtimeBattle3D.tscn` → 播完按「退出回放」→ 真换回 `Record.tscn`。
## ★网络是假的(`SupabaseNet._transport_for_test`), 假的是**服务器**: 按 match_id 回它存着的那一行。
##   不向任何外部服务发请求。
##
## 段落:
##   ① 本机有录像 ⇒ 一个请求都不发就播; 播完全程校验点一个不差; 退回战绩页
##   ② 本机没有 ⇒ 带登录令牌按 match_id 取**那一行** → 解码 → 播的是同一场(产品校验点逐个对上录制那一份)
##      → 取回来的那份存到本机 ⇒ 再点一次一个请求都不发; 中途退出也还原
##   ③ 每一种失败原因各给一句**不同的**话, 按钮回来(不禁用、签牌复原), 不换场景、GameState 不动
##      (没令牌 / 断网 / 服务端 500 / 没这一行 / 录像坏了 ×3 种 / 版本不同 / 服务器不回话 → 看门狗)
##      看门狗那一条: 迟到的回包**不许**再把人拽进回放
##   ④ 每一段之后: 存档文件逐字节不变 / GameState 与 test_mode 还原 / 战绩条数不变
##   ⑤ 没有回放的行不出按钮(没 id / id 不像样 / 服务端已清 / 旧本机 id 文件没了 / 没接服务器)
##
## ★每条断言配分母: 按钮真的找到了、请求真的发了、场景真的换过去了、校验点真的比过了。

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RECORD_SCENE := "res://scenes/Record.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const TOKEN := "tok-watch"
const MAX_PLAY_FRAMES := 3000

var _fail := 0
var _n := 0
var _gs
var _mode := "ok"
var _reqs: Array = []
var _rows: Dictionary = {}          # 假服务器的 matches 表: match_id → replay(base64)
var _bad_rows: Dictionary = {}      # 各失败模式下回的那一列
var _hang_cbs: Array = []
var _rec: Dictionary = {}           # 录制那一份(本机文件读回来的)
var _id := ""
var _n_real_cp := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _bearer(h) -> String:
	for line in (h as PackedStringArray):
		if str(line).begins_with("Authorization: Bearer "):
			return str(line).substr(len("Authorization: Bearer "))
	return ""


## 假服务器。
func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	_reqs.append({"m": str(m), "u": url, "bearer": _bearer(h)})
	if url.find("/auth/v1/token") >= 0 or url.find("/auth/v1/signup") >= 0:
		if _mode == "authfail":
			cb.call({"ok": false, "code": 0, "body": ""})
		else:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({
				"access_token": TOKEN, "refresh_token": "r2", "expires_in": 3600,
				"user": {"id": ME, "is_anonymous": true}})})
		return
	if url.find("/rest/v1/matches?") >= 0 and str(m) == "GET":
		var k := url.find("match_id=eq.")
		var id := url.substr(k + len("match_id=eq.")).get_slice("&", 0) if k >= 0 else ""
		match _mode:
			"offline":
				cb.call({"ok": false, "code": 0, "body": ""})
			"server":
				cb.call({"ok": true, "code": 500, "body": "{\"message\":\"boom\"}"})
			"hang":
				_hang_cbs.append(cb)
			"missing":
				cb.call({"ok": true, "code": 200, "body": "[]"})
			"ok":
				var out: Array = []
				if _rows.has(id):
					out.append({"match_id": id, "replay": str(_rows[id])})
				cb.call({"ok": true, "code": 200, "body": JSON.stringify(out)})
			_:
				cb.call({"ok": true, "code": 200,
					"body": JSON.stringify([{"match_id": id, "replay": str(_bad_rows.get(_mode, ""))}])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


func _gets() -> Array:
	var out: Array = []
	for r in _reqs:
		if str(r["u"]).find("/rest/v1/matches?") >= 0 and str(r["m"]) == "GET":
			out.append(r)
	return out


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = false                  # ★④ 要量真存档: 门禁每个测试一份独立 user://
	_gs.tutorial_active = false
	_gs.week_phase = "gauntlet"            # 周六(2026-10-05 起积分赛也录; 这里沿用周六)
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
	rng.seed = 20261004
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME
	_gs.auth_refresh = "r1"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	_ok("分母: 录制时后端是关的(录完那一下不往外传)", not SB.enabled())
	_setup_gs()

	await _record()
	if _id == "":
		_finish()
		return

	## 战绩页上另外五行: 都**不该**有按钮(⑤)。加在录制那一行后面。
	var now := int(Time.get_unix_time_from_system())
	_gs.match_history.append({"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 30, "ts": now - 60})
	_gs.match_history.append({"result": "lose", "lineup": ["basic"], "mode": "实时", "turn": 31, "ts": now - 60,
		"replay_id": "../../savegame"})
	_gs.match_history.append({"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 32,
		"ts": now - 15 * 86400, "replay_id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"})
	_gs.match_history.append({"result": "lose", "lineup": ["basic"], "mode": "实时", "turn": 33, "ts": now - 60,
		"replay_id": "0123456789abcdef01234567"})
	## 这一行在**别的设备**上打的(本机没有录像, 服务端有) —— 后端开着时**该**有按钮。
	_gs.match_history.append({"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 34, "ts": now - 60,
		"replay_id": "99999999-8888-4777-8666-555555555555"})

	await _t_no_button_without_backend()

	## 开后端(假服务器)。令牌预先给好 ⇒ 取录像那一下不触发续登录(续登录会合法地改存档, 那不是回放的副作用)。
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = TOKEN
	_ok("★分母: 后端真的打开了(关着的话 ②③ 全是空检查)", SB.enabled())
	_rows[_id] = RU.upload_b64(_rec)

	## ④ 基线
	_gs.save()
	var base := _baseline()
	_ok("分母: 存档文件真的在(否则「逐字节不变」是空检查)", (base["save"] as PackedByteArray).size() > 0,
		"%d 字节" % (base["save"] as PackedByteArray).size())

	var rs: Node = await _open_record()
	_t_buttons(rs)
	rs = await _t_local(rs, base)
	rs = await _t_remote(rs, base)
	rs = await _t_failures(rs, base)

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	SB.match_fetch_timeout_for_test = 0.0
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	_finish()


# ─────────────────────────────── 录一局 ───────────────────────────────
## 扮演玩家(点幕布 / 拖站位 / 按开打 / 第二路打一会儿认输), 与 verify_replay_roundtrip 同一套动作。
func _record() -> void:
	print("── 录: 真战斗场打一局周六闯关赛 ──")
	var hist0: int = (_gs.match_history as Array).size()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_ok("分母: 这一局在录(周六闯关赛)", str(s._replay.mode) == "rec", str(s._replay.mode))
	var last := ""
	var stf := 0
	var fights := 0
	var surrendered := false
	var i := 0
	while i < 6000 and (_gs.match_history as Array).size() == hist0:
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 6:
			for u in s._units:
				if str(u.get("side", "")) == "left" and s._can_place_drag(u):
					u["pos"] = s._dl_sys._dl_clamp_place((u["pos"] as Vector2) + Vector2(-60.0, 25.0 + 20.0 * fights))
					break
		elif st == "place" and stf == 20 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fights += 1
		elif st == "fight" and fights >= 2 and stf == 120 and not surrendered:
			s._do_surrender()
			surrendered = true
		s._process(0.05)
		await get_tree().process_frame
		i += 1
	await _frames(10)
	_id = str(_gs.match_history[0].get("replay_id", "")) if (_gs.match_history as Array).size() > hist0 else ""
	_ok("分母: 结算挂上了回放 id(uuid)", SB.is_uuid(_id), _id)
	_ok("分母: 两路都开打过、认输过", fights >= 2 and surrendered, "fights=%d" % fights)
	_rec = ReplayRecorder.load_record(_id) if _id != "" else {}
	_ok("分母: 本机录像读得回来", not _rec.is_empty())
	for h in _rec.get("cps", []):
		if str(h) != ReplayRecorder.PLACE_CP:
			_n_real_cp += 1
	_ok("分母: 录到的非摆位校验点 %d 个 > 0" % _n_real_cp, _n_real_cp > 0)
	s.queue_free()
	await _frames(4)
	if _rec.is_empty():
		_id = ""


# ─────────────────────────────── 场景与按钮 ───────────────────────────────

func _is_record(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null \
		and str((n.get_script() as Script).resource_path).ends_with("RecordScene.gd")


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


## 真的实例化战绩页, 并把它设成「当前场景」(换场景时被换掉的是它, 不是本测试)。
func _open_record() -> Node:
	var rs: Node = (load(RECORD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(rs)
	get_tree().current_scene = rs
	await _frames(3)
	return rs


func _buttons(rs: Node) -> Array:
	return rs.find_children("ReplayBtn", "Button", true, false) if rs != null else []


func _btn_for(rs: Node, id: String) -> Button:
	for b in _buttons(rs):
		if str((b as Button).get_meta("replay_id", "")) == id:
			return b
	return null


func _chip_text(b: Button) -> String:
	var row := b.get_parent() if b != null else null
	var t: Label = row.find_child("ReplayChipText", true, false) as Label if row != null else null
	return t.text if t != null else "<没有签牌>"


# ⑤ ─────────────────────────────────────────────────────────────
func _t_no_button_without_backend() -> void:
	print("── ⑤a 没接服务器: 只有本机有录像的那一行出按钮 ──")
	var rs: Node = await _open_record()
	var ids: Array = []
	for b in _buttons(rs):
		ids.append(str((b as Button).get_meta("replay_id", "")))
	_ok("⑤a 分母: 战绩页画出了 6 行", (_gs.match_history as Array).size() == 6)
	_ok("⑤a ★没接服务器 ⇒ 只有本机有录像的那一行有按钮", ids == [_id], str(ids))
	rs.queue_free()
	await _frames(3)


func _t_buttons(rs: Node) -> void:
	print("── ⑤ 有回放的行才出按钮 ──")
	var ids: Array = []
	for b in _buttons(rs):
		ids.append(str((b as Button).get_meta("replay_id", "")))
	_ok("⑤ 分母: 是战绩页、6 行都在", _is_record(rs) and (_gs.match_history as Array).size() == 6)
	_ok("⑤ ★★恰好两行有按钮: 本机录的那一场 + 别的设备打的那一场(服务端有)",
		ids == [_id, "99999999-8888-4777-8666-555555555555"], str(ids))
	_ok("⑤ 没 id / id 不像样 / 服务端已清(15 天前)/ 旧本机 id 文件没了 ⇒ 都没有按钮", ids.size() == 2)
	var b := _btn_for(rs, _id)
	_ok("⑤ 按钮签牌写「回放」", b != null and _chip_text(b) == "回放", _chip_text(b))
	_ok("⑤ 整行是热区(宽 ≥ 200, 触控下限的豁免条件), 不是行尾一个小钮",
		b != null and b.size.x >= 200.0, str(b.size) if b != null else "")


# ④ ─────────────────────────────────────────────────────────────
func _baseline() -> Dictionary:
	return {"save": FileAccess.get_file_as_bytes(_gs.SAVE_PATH), "state": var_to_bytes(ReplayRecorder.capture_state()),
		"tm": bool(_gs.test_mode), "hist": var_to_bytes(_gs.match_history)}


func _check_restored(tag: String, base: Dictionary) -> void:
	_ok("④ %s ★存档文件逐字节不变" % tag, FileAccess.get_file_as_bytes(_gs.SAVE_PATH) == base["save"])
	_ok("④ %s ★GameState 还原成播之前那一份" % tag, var_to_bytes(ReplayRecorder.capture_state()) == base["state"])
	_ok("④ %s test_mode 还原(%s)" % [tag, str(_gs.test_mode)], bool(_gs.test_mode) == bool(base["tm"]))
	_ok("④ %s 战绩一条没多一条没少" % tag, var_to_bytes(_gs.match_history) == base["hist"])
	_ok("④ %s 没有挂着的待播 / 备份" % tag, ReplayRecorder.pending_play.is_empty() and not ReplayRecorder._has_backup)


## 等「当前场景」换成满足 pred 的那一个。
func _wait_scene(pred: Callable, max_frames: int = 120) -> Node:
	for _i in range(max_frames):
		var cs := get_tree().current_scene
		if pred.call(cs):
			return cs
		await get_tree().process_frame
	return null


## 进了战斗场之后: full = 播完再按退出; 否则播几十步就按退出(中途退出)。返回退回来的战绩页。
func _play_and_exit(tag: String, full: bool) -> Dictionary:
	var b = await _wait_scene(_is_battle)
	_ok("%s ★分母: 真的换到了战斗场" % tag, b != null)
	if b == null:
		return {"rs": get_tree().current_scene}
	b.set_process(false)
	_ok("%s 战斗场处在回放模式" % tag, b._replay.is_playing())
	var i := 0
	while i < MAX_PLAY_FRAMES:
		b._process(0.1)
		await get_tree().process_frame
		i += 1
		if b._replay.diverged_at >= 0 or b._replay.finished:
			break
		if not full and int(b._sim_step_n) > 200:
			break
	var res := {"div": int(b._replay.diverged_at), "why": str(b._replay.diverge_why),
		"cps": int(b._replay.cp_checked), "finished": bool(b._replay.finished), "steps": int(b._sim_step_n)}
	await _frames(2)
	var bar = b._hud._replay_bar
	var exit_btn: Button = null
	## 2026-10-05 回放体验打磨: 回放条改成铭牌 + 底部操作条, 退出钮按节点名找(不按「第几个子节点」)。
	if bar != null and is_instance_valid(bar):
		exit_btn = (bar as Node).find_child(ReplayControls.N_EXIT, true, false) as Button
	_ok("%s 分母: 回放条上有「退出回放」" % tag, exit_btn != null and exit_btn.text == "退出回放")
	if exit_btn != null:
		exit_btn.pressed.emit()            # 真入口: 人按「退出回放」
	var rs = await _wait_scene(_is_record)
	_ok("%s ★退出回放 ⇒ 回到战绩页" % tag, rs != null)
	await _frames(3)
	res["rs"] = rs if rs != null else get_tree().current_scene
	return res


# ① ─────────────────────────────────────────────────────────────
func _t_local(rs: Node, base: Dictionary) -> Node:
	print("── ① 本机有录像: 不发请求直接播 ──")
	_mode = "ok"
	_reqs.clear()
	var b := _btn_for(rs, _id)
	_ok("① 分母: 找到了这一行的按钮", b != null)
	if b == null:
		return rs
	b.pressed.emit()                       # 真入口: 手指点下去
	_ok("① ★进了回放(code 为空)", str(rs.last_replay_code) == "", "%s %s" % [rs.last_replay_code, rs.last_replay_msg])
	var res := await _play_and_exit("①", true)
	_ok("① ★★一个请求都没发(本机有录像)", _reqs.is_empty(), str(_reqs))
	_ok("① ★★播完全程没有一个校验点对不上(diverged_at=%d %s)" % [int(res.get("div", -9)), str(res.get("why", ""))],
		int(res.get("div", -9)) < 0)
	_ok("① ★产品比过的校验点 %d 个 = 录到的 %d 个" % [int(res.get("cps", 0)), _n_real_cp],
		int(res.get("cps", 0)) == _n_real_cp and _n_real_cp > 0)
	_ok("① 播到了结算(finished, 终局也比过)", bool(res.get("finished", false)))
	_check_restored("①", base)
	return res["rs"]


# ② ─────────────────────────────────────────────────────────────
func _t_remote(rs: Node, base: Dictionary) -> Node:
	print("── ② 本机没有: 按 match_id 去服务端取 → 解码 → 播 ──")
	_mode = "ok"
	_reqs.clear()
	DirAccess.remove_absolute(ReplayRecorder.SAVE_DIR + _id + ".rpl")
	_ok("② 分母: 本机录像已删(这台设备 = 「另一台设备」)", not RF.local_available(_id))
	var b := _btn_for(rs, _id)
	_ok("② 分母: 本机没有录像了, 按钮照样在(服务端有)", b != null)
	if b == null:
		return rs
	b.pressed.emit()
	var gets := _gets()
	_ok("② ★发了恰好一条取录像的请求", gets.size() == 1, str(gets))
	if gets.size() >= 1:
		_ok("② ★问的是**这一行**(match_id=eq.<id>)", str(gets[0]["u"]).contains("match_id=eq." + _id), str(gets[0]["u"]))
		_ok("② ★带的是登录令牌, 不是公共匿名钥匙", str(gets[0]["bearer"]) == TOKEN, str(gets[0]["bearer"]))
	_ok("② ★进了回放(code 为空)", str(rs.last_replay_code) == "", "%s %s" % [rs.last_replay_code, rs.last_replay_msg])
	var res := await _play_and_exit("②", true)
	_ok("② ★★播的是同一场: 全程没有一个校验点对不上(diverged_at=%d %s)" % [int(res.get("div", -9)), str(res.get("why", ""))],
		int(res.get("div", -9)) < 0)
	_ok("② ★★产品逐个比过录制那一份的校验点 %d 个 = %d 个" % [int(res.get("cps", 0)), _n_real_cp],
		int(res.get("cps", 0)) == _n_real_cp and _n_real_cp > 0)
	_ok("② 播到了结算(终局步号 / 指纹 / 胜负都比过)", bool(res.get("finished", false)))
	_check_restored("②", base)
	rs = res["rs"]
	## 取回来的那份落了本机 ⇒ 第二次点不再发请求
	var raw := Marshalls.base64_to_raw(str(_rows[_id]))
	_ok("② 取回来的录像存到了本机, 与服务端那份逐字节相同",
		FileAccess.get_file_as_bytes(ReplayRecorder.SAVE_DIR + _id + ".rpl") == raw)
	_reqs.clear()
	var b2 := _btn_for(rs, _id)
	_ok("② 分母: 回到战绩页后按钮还在", b2 != null)
	if b2 != null:
		b2.pressed.emit()
		var res2 := await _play_and_exit("②b 中途退出", false)
		_ok("②b ★第二次点: 一个请求都没发(用的是存在本机的那份)", _gets().is_empty(), str(_reqs))
		_ok("②b 分母: 真的播了一段(%d 步)才退出" % int(res2.get("steps", 0)), int(res2.get("steps", 0)) > 100)
		_ok("②b 那一段校验点也对得上", int(res2.get("div", -9)) < 0)
		_check_restored("②b 中途退出", base)
		rs = res2["rs"]
	return rs


# ③ ─────────────────────────────────────────────────────────────
func _t_failures(rs: Node, base: Dictionary) -> Node:
	print("── ③ 每一种失败: 一句不同的话 + 按钮回来 + 不换场景 ──")
	var junk := PackedByteArray()
	for k in range(64):
		junk.append((k * 37 + 11) % 256)
	var other: Dictionary = _rec.duplicate(true)
	other["id"] = "99999999-8888-4777-8666-555555555555"   # 别的一场的录像, 回在这一行上
	var old: Dictionary = _rec.duplicate(true)
	old["client_version"] = "0.0.1"
	_bad_rows = {
		"corrupt_b64": "这不是*base64@@@=",
		"corrupt_zip": Marshalls.raw_to_base64(junk),
		"corrupt_other": RU.upload_b64(other),
		"version": RU.upload_b64(old),
	}
	## [模式, 期望原因码, 说明]
	var cases := [
		["offline", "offline", "断网"],
		["server", "server", "服务端 500"],
		["missing", "missing", "服务端没有这一行"],
		["corrupt_b64", "corrupt", "录像列不是 base64"],
		["corrupt_zip", "corrupt", "录像列解出来不是压缩数据"],
		["corrupt_other", "corrupt", "录像是别的一场"],
		["version", "unplayable", "旧版本打的"],
		["hang", "timeout", "服务器不回话 → 看门狗"],
		["authfail", "no_token", "拿不到登录令牌"],
	]
	var msgs := {}
	for c in cases:
		rs = await _t_one_failure(rs, str(c[0]), str(c[1]), str(c[2]), msgs)
	_ok("③ ★★%d 种失败原因, %d 句不同的话" % [7, msgs.size()], msgs.size() == 7, str(msgs))
	_check_restored("③", base)
	return rs


func _t_one_failure(rs: Node, mode: String, want: String, what: String, msgs: Dictionary) -> Node:
	_mode = mode
	_reqs.clear()
	_hang_cbs.clear()
	DirAccess.remove_absolute(ReplayRecorder.SAVE_DIR + _id + ".rpl")
	if mode == "authfail":
		SB._reset_auth_for_test()          # 冷启动: 内存里没令牌, 去续 → 续不上
	else:
		SB._token = TOKEN
	SB.match_fetch_timeout_for_test = 0.4 if mode == "hang" else 0.0
	var b := _btn_for(rs, _id)
	if b == null:
		_ok("③ %s 分母: 找到按钮" % what, false)
		return rs
	b.pressed.emit()
	## 等回调(同步回包的当场就回来了; 看门狗那条要等墙钟)
	var t0 := Time.get_ticks_msec()
	while str(rs._rp_busy) != "" and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await _frames(3)
	var code := str(rs.last_replay_code)
	var msg := str(rs.last_replay_msg)
	_ok("③ %s ★原因码 %s" % [what, want], code == want, "%s · %s" % [code, msg])
	_ok("③ %s 给了一句人话" % what, msg != "" and not msg.contains("%"), msg)
	if code == want and msg != "":
		msgs[want] = msg if not msgs.has(want) or str(msgs[want]) == msg else str(msgs[want]) + " ≠ " + msg
	_ok("③ %s ★按钮回来了(没在转)" % what, str(rs._rp_busy) == "" and not b.disabled and _chip_text(b) == "回放",
		"busy=%s disabled=%s chip=%s" % [str(rs._rp_busy), str(b.disabled), _chip_text(b)])
	_ok("③ %s 那句话显示在列表上方" % what, rs._list_title != null and rs._list_title.text == msg)
	_ok("③ %s ★没进回放: 还在这一页、没挂待播" % what,
		get_tree().current_scene == rs and ReplayRecorder.pending_play.is_empty() and not ReplayRecorder._has_backup)
	if mode == "authfail":
		_ok("③ %s 分母: 真去续过令牌、而且一条取录像的请求都没发(不拿匿名钥匙读)" % what,
			_reqs.size() >= 1 and _gets().is_empty(), str(_reqs))
	else:
		var gets := _gets()
		_ok("③ %s 分母: 真的问了这一行" % what, gets.size() == 1 and str(gets[0]["u"]).contains(_id), str(gets))
	if mode == "hang":
		_ok("③ %s 分母: 请求真的挂着没回(%d 条)" % [what, _hang_cbs.size()], _hang_cbs.size() == 1)
		## 迟到的回包(内容还是好的) —— 不许再把人拽进回放
		for cb in _hang_cbs:
			(cb as Callable).call({"ok": true, "code": 200,
				"body": JSON.stringify([{"match_id": _id, "replay": str(_rows[_id])}])})
		await _frames(5)
		_ok("③ %s ★迟到的回包不许再进回放" % what,
			get_tree().current_scene == rs and ReplayRecorder.pending_play.is_empty() and str(rs.last_replay_code) == "timeout")
	_ok("③ %s 坏数据不落本机" % what, mode == "version" or not RF.local_available(_id))
	return rs


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 回放 S3 战绩页看回放 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
