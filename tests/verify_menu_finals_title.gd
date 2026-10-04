extends Node
## verify_menu_finals_title.gd — 冠军/亚军/四强头衔**不必打开对阵图**(方案书 20260926 头衔发放 · U1)
##
## 由来: 头衔原来只在 `BracketMapScene` 拿到 feed 时才发 ⇒ 周日打完、之后只开主菜单的人
##   永远拿不到。2026-10-04 让主菜单在决赛日打开时也拉一次 feed, 交给**同一条链**
##   `BracketMapScene.record_progress_from()`。
##
## ★走真入口: 实例化 MainMenu(把钟钉在本周周日), 后端**真的打开**(环境变量 + 假传输
##   `_transport_for_test`, 不碰网络), 量**存档里的头衔**。全程**不实例化对阵图**(分母断言守着)。
## ★三种桶: 冠军 / 亚军 / 纯观众; 再加一条「不是周日 ⇒ 一个 finals_view 请求都不发」。
## ★冠军/亚军是谁**不抄**: 拿 `bracket.my_progress` 在给定 `done` 上算出来再把我塞进那个种子。
##
## 跑法: <godot> --headless --path . res://tests/verify_menu_finals_title.tscn --quit-after 3000

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const BR := preload("res://scripts/gamedata/bracket.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")

const KEYS := ["titles", "ranked_used", "promoted", "week_anchor_ts", "account_id",
	"finals_deepest_round", "finals_rounds_total", "finals_champion", "finals_runner_up",
	"finals_pending_reveal"]

var _n := 0
var _fail := 0
var _bak := {}
var _finals_reqs := 0
var _body := ""


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


## 4 人桶, `done` 全翻面。me_seed = -1 ⇒ 我不在桶里(纯观众)。
func _mk_body(done: Dictionary, me_seed: int) -> String:
	var ent: Array = []
	for s in range(4):
		ent.append({"seed": s, "name": "龟%d" % s, "account_id": "uid-me" if s == me_seed else "uid-%d" % s})
	return JSON.stringify({"ok": true, "bucket": 1, "n": 4, "round": 3, "closed": true,
		"round_at": 500, "next_at": 980, "now": 1000, "entrants": ent, "done": done})


func _has_bracket_node(n: Node) -> bool:
	var sc = n.get_script()
	if sc != null and str((sc as Script).resource_path).ends_with("BracketMapScene.gd"):
		return true
	for c in n.get_children():
		if _has_bracket_node(c):
			return true
	return false


## 开一屏主菜单(钟钉在 ts), 等主菜单这条路记完账(或超时)。返回那一屏的 records 计数。
func _open_menu(ts: int, wait_ms: int = 8000) -> int:
	var mm = load("res://scenes/MainMenu.tscn").instantiate()
	mm.clock_override_ts = ts
	add_child(mm)
	var t0 := Time.get_ticks_msec()
	var saw_bracket := false
	while Time.get_ticks_msec() - t0 < wait_ms and int(mm.finals_title_records) < 1:
		await get_tree().process_frame
		if _has_bracket_node(get_tree().root):
			saw_bracket = true
	_ok("  ★分母: 全程没有实例化对阵图(量的就是「不打开对阵图」)", not saw_bracket and not _has_bracket_node(get_tree().root))
	var rec: int = int(mm.finals_title_records)
	mm.queue_free()
	await get_tree().process_frame
	return rec


func _reset_progress(wk: int) -> void:
	GameState.titles = []
	GameState.week_anchor_ts = wk
	GameState.ranked_used = 0
	GameState.promoted = false
	GameState.finals_deepest_round = 0
	GameState.finals_rounds_total = 0
	GameState.finals_champion = false
	GameState.finals_runner_up = false
	GameState.finals_pending_reveal = {}


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== 决赛日头衔: 主菜单也发(U1) ===")

	## ① 纯判据穷举
	var due_cases := 0
	var due_bad: Array = []
	for on in [false, true]:
		for ph in [P2C.PHASE_REST, P2C.PHASE_RANKED, P2C.PHASE_GAUNTLET, P2C.PHASE_FINALS]:
			for live in [false, true]:
				due_cases += 1
				var want: bool = on and live and ph == P2C.PHASE_FINALS
				if MENU.finals_title_due(on, ph, live) != want:
					due_bad.append("%s/%s/%s" % [str(on), ph, str(live)])
	_ok("① finals_title_due: 只有「后端开 + 周日 + 玩法上线」才拉 (穷举 %d 格)" % due_cases,
		due_bad.is_empty() and due_cases == 16, str(due_bad))
	_ok("① ★分母: 决赛日玩法开着(关着的话下面只能验「发不出来」)", P2C.phase_mode_live(P2C.PHASE_FINALS))

	## ② 打开后端(假传输) —— 门禁默认 `TURTLE_SUPABASE=" "`, 不开的话这条路一次都不会跑
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	_ok("② ★分母: 后端真的打开了", SB.enabled(), SB.base_url())
	GameState.account_id = "uid-me"
	SB._token = "gate-token"
	SB._transport_for_test = func(_m, u, _h, _b, cb):
		if str(u).find("finals_view") >= 0:
			_finals_reqs += 1
			cb.call({"ok": true, "code": 200, "body": _body})
		else:
			cb.call({"ok": false, "code": 0, "body": ""})

	var wk: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sun: int = wk + 6 * 86400 + 12 * 3600
	var sat: int = wk + 5 * 86400 + 12 * 3600
	_ok("② ★分母: 钉的那一刻确实是决赛日", P2C.phase_at_utc(sun) == P2C.PHASE_FINALS, P2C.phase_at_utc(sun))

	## 谁是冠军/亚军: 在 done 上**算**出来, 不抄
	var done := {"1-0": 0, "1-1": 1, "2-0": 1}
	var ch_seed := -1
	var ru_seed := -1
	for s in range(4):
		var pr: Dictionary = BR.my_progress(s, 4, done)
		if bool(pr.get("champion", false)):
			ch_seed = s
		if bool(pr.get("runner_up", false)):
			ru_seed = s
	_ok("② ★分母: 这份 done 里算得出冠军与亚军", ch_seed >= 0 and ru_seed >= 0 and ch_seed != ru_seed,
		"冠 %d 亚 %d" % [ch_seed, ru_seed])

	## ③ 冠军
	_reset_progress(wk)
	_body = _mk_body(done, ch_seed)
	_finals_reqs = 0
	var r3: int = await _open_menu(sun)
	print("  ③ titles = %s · finals_view 请求 %d 次" % [str(GameState.titles), _finals_reqs])
	_ok("③ ★分母: 主菜单真的拉了 finals feed 并记了账", _finals_reqs >= 1 and r3 >= 1,
		"请求 %d · 记账 %d" % [_finals_reqs, r3])
	_ok("③ ★★★冠军不进对阵图也拿到【冠军】头衔", P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, wk),
		str(GameState.titles))
	_ok("③ 冠军没有【亚军】", not P2C.title_has(GameState.titles, P2C.TITLE_RUNNER_UP, wk))

	## ④ 亚军
	_reset_progress(wk)
	_body = _mk_body(done, ru_seed)
	_finals_reqs = 0
	var r4: int = await _open_menu(sun)
	_ok("④ ★分母: 记了账", r4 >= 1, "记账 %d" % r4)
	_ok("④ ★★★亚军不进对阵图也拿到【亚军】头衔", P2C.title_has(GameState.titles, P2C.TITLE_RUNNER_UP, wk),
		str(GameState.titles))
	_ok("④ 亚军没有【冠军】", not P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, wk))

	## ⑤ 纯观众: 问到了, 但我不在桶里 ⇒ 一条都不发
	_reset_progress(wk)
	_body = _mk_body(done, -1)
	_finals_reqs = 0
	var r5: int = await _open_menu(sun)
	_ok("⑤ ★分母: 问到了(记账那一步走到了)", r5 >= 1 and _finals_reqs >= 1)
	_ok("⑤ ★纯观众一个头衔都不发", (GameState.titles as Array).is_empty(), str(GameState.titles))

	## ⑥ 不是周日 ⇒ 不拉(别的天不该替人去问决赛)
	_reset_progress(wk)
	_body = _mk_body(done, ch_seed)
	_finals_reqs = 0
	var r6: int = await _open_menu(sat, 2500)
	_ok("⑥ ★周六打开主菜单 ⇒ 一个 finals_view 请求都不发、不记账", _finals_reqs == 0 and r6 == 0,
		"请求 %d · 记账 %d" % [_finals_reqs, r6])
	_ok("⑥ ★周六不发冠军头衔", not P2C.title_has(GameState.titles, P2C.TITLE_CHAMPION, wk))

	## 收尾: static 与环境全部还原
	SB._transport_for_test = Callable()
	SB.finals_clear()
	SB._token = ""
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n >= 18:
		print("ALL PASS — 决赛日头衔主菜单也发")
		get_tree().quit(0)
	else:
		print("FAIL x%d (断言 %d 条)" % [_fail, _n])
		get_tree().quit(1)
