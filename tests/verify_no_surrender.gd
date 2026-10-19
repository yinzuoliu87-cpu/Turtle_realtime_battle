extends Node
## verify_no_surrender —— 投降整个删掉(用户 2026-10-19「投降不要了」), 旧录像照样能播。
##
## 背景: 服务器裁判算的对局里没有投降(docs/plans/20261019-服务器裁判.md U4) ⇒ 用户拍板整个功能删掉, 所有模式。
##
## 段落:
##   ① 战斗场里没有投降: 认输键 / 确认框字段不存在; `_do_surrender` / 开收确认框三个方法不存在;
##      UI 层里没有写着「认输」的按钮; `scripts/` `autoload/` 源码里一处都不许再出现这些符号(分母: 扫过的文件数)
##   ② 计分对局里 ESC 不再被拦(原来 = 弹认输框), R 仍拦
##   ③ ★旧录像(带 `surrender` 事件)照样播完: 用与旧版认输键同一条录制路径(`allow_input("surrender")`)录一份
##      第一路打一会儿就 surrender 的录像 ⇒ 交给播放模式: 不分叉、那一条事件被重放、播到结算、终局与录制一致
##   ④ 新录像不再产生 surrender: 同样打一会儿走判负收尾(`_forfeit_match()`, 补打用的入口) ⇒ 事件名是 forfeit
## ★反证(写在报告里): 把 `_fire_due` 里 "surrender" 那一支删掉 ⇒ ③ 必须红(「事件 surrender 在本机没能发生」)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const DT := 0.05
const SYMBOLS := ["_do_surrender", "_surrender_btn", "_surrender_panel", "_show_surrender_confirm",
	"_hide_surrender_confirm", "_build_surrender_panel", "ICON_SURRENDER", "hud-surrender"]

var _fail := 0
var _n := 0
var _gs


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _setup() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = true
	_gs.tutorial_active = false
	_gs.week_phase = "ranked"
	_gs.season_level = 4
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.persistent_equipped = {}
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	_gs.dual_ghost = BE.make_bot(6, rng)
	_gs.dual_active = true


func _buttons_with(n: Node, txt: String) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Button and str((ch as Button).text).contains(txt):
			c += 1
		c += _buttons_with(ch, txt)
	return c


func _scan(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out["files"] = int(out["files"]) + 1
			var src := FileAccess.get_file_as_string(dir.path_join(f))
			for sym in SYMBOLS:
				if src.contains(sym):
					(out["hits"] as Array).append("%s: %s" % [dir.path_join(f), sym])
	for sub in d.get_directories():
		_scan(dir.path_join(sub), out)


## 录一局: 第一路开打后第 `after` 帧按 `kind` 判负收尾。返回录下的那一份(带 end)。
func _record(kind: String, after: int) -> Dictionary:
	_setup()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_ok("分母(%s): 这一局在录" % kind, str(s._replay.mode) == "rec", str(s._replay.mode))
	var last := ""
	var stf := 0
	var done := false
	var i := 0
	while i < 4000 and not bool(s._settled):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "fight" and stf == after and not done:
			done = true
			if kind == "surrender":
				## ★旧版认输键的录制路径逐字是这一句(`_do_surrender` 第一行): allow_input("surrender") 记一条 {s, k:"surrender", i}。
				##   新代码里能走到这条路的只有播放端, 这里借同一个入口造一份「旧录像」。
				s._forfeit_match("surrender")
			else:
				s._forfeit_match()
		s._process(DT)
		await get_tree().process_frame
		i += 1
	var rec: Dictionary = (s._replay.rec as Dictionary).duplicate(true)
	_ok("分母(%s): 打到结算了、录像带终局" % kind, bool(s._settled) and rec.has("end"), "帧 %d" % i)
	s.queue_free()
	await get_tree().process_frame
	return rec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	_ok("分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")

	# ── ① ──
	print("=== ① 战斗场里没有投降 ===")
	_setup()
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)
	_ok("分母: 战斗场 UI 层建出来了(战报键在)", s._ui_layer != null and s._hud._stats_btn != null)
	_ok("★认输键 / 认输框字段不存在", not ("_surrender_btn" in s) and not ("_surrender_panel" in s))
	_ok("★_do_surrender / 开 / 收确认框 三个方法都不存在", not s.has_method("_do_surrender")
		and not s.has_method("_show_surrender_confirm") and not s.has_method("_hide_surrender_confirm"))
	_ok("★UI 层里没有写着「认输」/「投降」的按钮", _buttons_with(s._ui_layer, "认输") == 0 and _buttons_with(s._ui_layer, "投降") == 0)
	# ── ② ──
	_ok("★② 计分对局: ESC 不再被键盘守卫吞掉(原来弹认输框), R 仍吞", s._world_builder._is_scored_match()
		and not s._world_builder._scored_key_guard(KEY_ESCAPE) and s._world_builder._scored_key_guard(KEY_R))
	s.queue_free()
	await get_tree().process_frame
	var sc := {"files": 0, "hits": []}
	_scan("res://scripts", sc)
	_scan("res://autoload", sc)
	_ok("分母: 扫过 %d 个 .gd" % int(sc["files"]), int(sc["files"]) > 150)
	_ok("★源码里投降相关符号 0 处(%d 个符号)" % SYMBOLS.size(), (sc["hits"] as Array).is_empty(), str((sc["hits"] as Array).slice(0, 6)))
	_ok("★认输图标文件已删", not FileAccess.file_exists("res://assets/sprites/ui/hud-surrender.png"))

	# ── ③ 旧录像能播 ──
	print("=== ③ 旧录像(带 surrender 事件)照样播完 ===")
	var old: Dictionary = await _record("surrender", 90)
	var kinds := {}
	for e in old.get("events", []):
		kinds[str(e["k"])] = int(kinds.get(str(e["k"]), 0)) + 1
	_ok("分母 ③: 造出的旧录像里恰有一条 surrender、至少一次开打 %s" % str(kinds),
		int(kinds.get("surrender", 0)) == 1 and int(kinds.get("fight", 0)) >= 1 and not kinds.has("forfeit"))
	ReplayRecorder.begin_play(old)
	var p = RB.new()
	add_child(p)
	p.set_process(false)
	await get_tree().process_frame
	_ok("分母 ③: 播放模式", p._replay.is_playing())
	var j := 0
	while j < 4000 and not bool(p._replay.finished) and int(p._replay.diverged_at) < 0:
		p._process(0.033)
		await get_tree().process_frame
		j += 1
	var end: Dictionary = old.get("end", {})
	_ok("★★③ 旧录像播完: 不分叉、播到结算(%s)" % str(p._replay.diverge_why), int(p._replay.diverged_at) < 0
		and bool(p._replay.finished) and bool(p._settled), "diverged_at=%d 帧 %d" % [int(p._replay.diverged_at), j])
	_ok("★③ surrender 那一条被重放了(事件全部消费 %d/%d)" % [int(p._replay._ev_i), (old.get("events", []) as Array).size()],
		int(p._replay._ev_i) == (old.get("events", []) as Array).size())
	## 终局由播放端自己的 `on_settle` 比(步号 / 指纹 / 胜负三样, 对不上就记分叉); 上面那条已断言没分叉 ⇒ 这里补分母。
	_ok("★③ 终局一致: 录的是判负(第 %d 步)、播放端比过 %d 个校验点" % [int(end.get("s", -1)), int(p._replay.cp_checked)],
		not bool(end.get("won", true)) and int(end.get("s", -1)) > 0 and int(p._replay.cp_checked) > 0)
	p.queue_free()
	await get_tree().process_frame
	ReplayRecorder.end_play()

	# ── ④ 新录像 ──
	print("=== ④ 新录像里不再有 surrender ===")
	var nw: Dictionary = await _record("forfeit", 90)
	var k2 := {}
	for e in nw.get("events", []):
		k2[str(e["k"])] = int(k2.get(str(e["k"]), 0)) + 1
	_ok("★④ 判负收尾录成 forfeit、没有 surrender %s" % str(k2), int(k2.get("forfeit", 0)) == 1 and not k2.has("surrender"))
	_finish()


func _finish() -> void:
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n > 0:
		print("ALL PASS — 投降已删、旧录像能播")
	get_tree().quit(1 if _fail > 0 else 0)
