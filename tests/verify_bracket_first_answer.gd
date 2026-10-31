extends Node
## verify_bracket_first_answer.gd — 对阵图第一次问到名册之后, 屏幕必须当拍换掉「正在查询分组」
## (2026-10-31 周日彩排 P13, 方案书 docs/plans/20261031c-周日赛事界面重做.md §4.1 D)
##
## ══════════════════════════════════════════════════════════════════════
##  由来(探针 tests/_probe_bracket_wait.gd: 真场景 + 注入传输, 打每一拍的数)
## ══════════════════════════════════════════════════════════════════════
##   对阵图只在「指纹」变了时重画(`_on_poll` 的 sig), 而指纹只看 size / round / done 条数 + 观赛 / 杯 / 开播。
##   「还没回音」(缓存 {})与「回音是还没分组 / 人太少 / 连不上 / 没有我这一组」(缓存 {reason…}, size 0)**指纹相同**。
##   ⇒ 只要另一份回包(finals_week_view)比 finals_view 先到、先触发了一次重画(那时还没回音 ⇒ 画「正在查询分组」),
##     finals_view 回来之后就再也不重画 —— 屏幕停在「正在查询分组」/ 页签「查询中」, 直到别的东西变了
##     (18:00 分组 / 点页签 / 下一轮翻面)。探针实测: 回包 661 ms 就到了, 屏幕 65 秒都没换。
##     彩排两次: 分组前约 90 秒、分组那一刻约 20 秒(下一次 30 秒重拉拿到分好的组才变)。
##
## ══════════════════════════════════════════════════════════════════════
##  判据(走真场景 BracketMap.tscn + 真入口 fetch_finals_async / fetch_finals_week_async, 网络 = 注入传输, 不碰网络)
## ══════════════════════════════════════════════════════════════════════
##   两份回包**扣在手里**, 按「观赛那份先到」的次序放, 每放一份调一次场景自己的轮询 `_on_poll`(就是 Timer 调的那个):
##   ★屏上那句 == 此刻的 `_empty_text()`(不抄屏幕字面量: 量「屏幕与此刻的判断一致」), 页签同理;
##   ★分母: 回包真的到了(`_feed_kind()` 不再是 wait)、放回包之前屏上确实是 wait 那一档。
##   四种回音(还没分组 / 连不上 / 人太少 / 没有我这一组)各一遍 + 一遍反过来的次序(修前修后都该绿, 证明判据不是恒红)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_bracket_first_answer.tscn --quit-after 500

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const KEYS := ["titles", "account_id", "finals_deepest_round", "finals_rounds_total", "finals_champion",
	"finals_runner_up", "finals_pending_reveal"]

var _n := 0
var _fail := 0
var _held := {}            # "finals_view" / "finals_week_view" → [cb, …]
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _transport(_m, url, _h, _b, cb) -> void:
	var u := str(url)
	if u.find("/rpc/finals_week_view") >= 0:
		(_held.get_or_add("finals_week_view", []) as Array).append(cb)
	elif u.find("/rpc/finals_view") >= 0:
		(_held.get_or_add("finals_view", []) as Array).append(cb)
	elif u.find("/rest/v1/matches") >= 0:
		cb.call({"ok": true, "code": 200, "body": "[]"})
	else:
		cb.call({"ok": true, "code": 200, "body": "{}"})


func _release(key: String, res: Dictionary) -> int:
	var cbs: Array = _held.get(key, [])
	_held[key] = []
	for cb in cbs:
		(cb as Callable).call(res)
	return cbs.size()


func _shown(bm) -> String:
	return str(bm._empty_lb.text) if bm._empty_box != null and bm._empty_box.visible else "(画了图)"


func _tab(bm) -> String:
	return str((bm._tabs.get_child(0) as Button).text)


func _week_ok() -> Dictionary:
	return {"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": 1, "now": P2C.now_utc(), "buckets": [], "cup": null})}


## 一遍: 钟钉在 at, 进对阵图, 先放 first 那份、再放 second 那份(回包 replies[key]), 每放一份轮询一次。
func _case(nm: String, at: int, first: String, second: String, replies: Dictionary, want_kind: String) -> void:
	print("── %s ──" % nm)
	P2C.now_override_ts = at
	SB.finals_clear()
	SB.finals_week_clear()
	_held = {}
	var bm = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	add_child(bm)
	## 轮询由本测试一拍一拍地调(与 Timer 调的是同一个 `_on_poll`), 次序才是确定的
	bm._poll.stop()
	for _i in range(3):
		await get_tree().process_frame          # 两个请求都是推迟一帧才发的
	var asked: bool = (_held.get("finals_view", []) as Array).size() == 1 and (_held.get("finals_week_view", []) as Array).size() == 1
	_ok("%s · 分母: 进场真的发了 finals_view / finals_week_view 各一次(回包扣在手里)" % nm, asked, str(_held.keys()))
	bm._on_poll()
	var k0: String = bm._empty_kind()
	_ok("%s · 分母: 回包到之前屏上是「还没回音」那一档、且与判断一致" % nm, k0 == MAP.EK_WAIT and _shown(bm) == bm._empty_text(),
		"kind=%s 屏=「%s」" % [k0, _shown(bm)])
	_release(first, replies[first])
	bm._on_poll()
	_release(second, replies[second])
	bm._on_poll()
	var k: String = bm._empty_kind()
	_ok("%s · 分母: 回包真的到了(问名册那一步 = %s)" % [nm, want_kind], SB.finals_tried() and k == want_kind,
		"tried=%s kind=%s cached=%s" % [str(SB.finals_tried()), k, str(SB.finals_cached())])
	_ok("%s · ★★★屏上那句当拍跟上(屏「%s」 ↔ 此刻该说「%s」)" % [nm, _shown(bm), bm._empty_text()],
		_shown(bm) == bm._empty_text())
	var want_tab: String = P2C.STAGE_GROUP + MAP.bucket_tab_suffix(bm._bucket_kind())
	_ok("%s · ★★页签也跟上(「%s」 ↔ 「%s」)" % [nm, _tab(bm), want_tab], _tab(bm) == want_tab)
	bm.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== 对阵图第一次问到名册: 屏幕当拍跟上 (P13) ===")
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	GameState.account_id = "uid-me"
	SB._token = "gate-token"
	SB._transport_for_test = _transport
	_ok("分母 · 后端真的打开了(关着的话一个请求都不发, 下面全是空检查)", SB.enabled(), SB.base_url())

	var wk: int = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	var sun_1731: int = wk + 6 * 86400 + 17 * 3600 + 31 * 60     # 分组(18:00)之前
	var sun_1805: int = wk + 6 * 86400 + 18 * 3600 + 40 * 60     # 分组(18:00, 15 分钟宽限)之后、冠军杯赛之前
	_ok("分母 · 两个钟点都是决赛日", P2C.phase_at_utc(sun_1731) == P2C.PHASE_FINALS and P2C.phase_at_utc(sun_1805) == P2C.PHASE_FINALS,
		"%s / %s" % [P2C.phase_at_utc(sun_1731), P2C.phase_at_utc(sun_1805)])

	var not_seated := {"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "not_seated", "entered": 24})}
	var too_few := {"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "too_few", "entered": 1})}
	var not_entered := {"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "not_entered"})}
	var dead := {"ok": false, "code": 0, "body": ""}
	await _case("A 还没分组(彩排 18:00 前那次)", sun_1731, "finals_week_view", "finals_view",
		{"finals_week_view": _week_ok(), "finals_view": not_seated}, MAP.EK_NOT_SEATED)
	await _case("B 连不上", sun_1731, "finals_week_view", "finals_view",
		{"finals_week_view": _week_ok(), "finals_view": dead}, MAP.EK_UNREACHABLE)
	await _case("C 人太少", sun_1805, "finals_week_view", "finals_view",
		{"finals_week_view": _week_ok(), "finals_view": too_few}, MAP.EK_TOO_FEW)
	await _case("D 没有我这一组", sun_1805, "finals_week_view", "finals_view",
		{"finals_week_view": _week_ok(), "finals_view": not_entered}, MAP.EK_NO_GROUP)
	await _case("E 反过来的次序(名册先到; 修前修后都该绿)", sun_1731, "finals_view", "finals_week_view",
		{"finals_week_view": _week_ok(), "finals_view": not_seated}, MAP.EK_NOT_SEATED)

	## 收尾: static / 环境 / 存档键全部还原(它们活过本测试)
	SB._transport_for_test = Callable()
	SB.finals_clear()
	SB.finals_week_clear()
	SB._token = ""
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0 and _n >= 27:
		print("ALL PASS — 对阵图第一次问到名册, 屏幕当拍跟上")
		get_tree().quit(0)
	else:
		print("FAIL x%d (断言 %d 条)" % [_fail, _n])
		get_tree().quit(1)
