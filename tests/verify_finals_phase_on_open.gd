extends Node
## verify_finals_phase_on_open.gd — 周日从对阵图开战, 这一局必须按【决赛日】结算(2026-10-04 周日实操)
## 现象: 第 1 轮打完, 结算副标题写「闯关 5-0 · 晋级决赛日」; 存档 gauntlet_wins 4 → 5, week_phase 仍是 "gauntlet"。
## 根因: week_phase 全仓只有选队界面在写, 周日【对阵图 → 直接开战】不经过选队 ⇒ 留着周六的值 ⇒ 结算走闯关赛分支。
## ★走产品自己那一步: BracketMapScene.stamp_finals_match(); 量的是结算自己用的判据 Phase2Cfg.settle_kind()。

const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _kind() -> String:
	var ph := str(GameState.week_phase)
	return P2.settle_kind(ph, P2.phase_mode_live(ph))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日对阵图开战 ⇒ 按决赛日结算 ===")
	var keep_phase := str(GameState.week_phase)
	var keep_match: Dictionary = (GameState.finals_match as Dictionary).duplicate(true)
	var sun: int = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 10 * 3600
	var sat: int = sun - 86400

	## ① 复现现场: 周六选过队(存档里是 gauntlet), 周日从对阵图直接开战
	GameState.week_phase = P2.PHASE_GAUNTLET
	GameState.finals_match = {}
	_ok("① ★分母: 开战前存档里确实是周六的阶段(复现现场)", _kind() == P2.SETTLE_GAUNTLET, _kind())
	MAP.stamp_finals_match(GameState, 0, 1, 3, 1, sun)
	_ok("① ★★开战后 week_phase = 决赛日", str(GameState.week_phase) == P2.PHASE_FINALS, str(GameState.week_phase))
	_ok("① ★★结算口径 = SETTLE_FINALS(不是闯关赛 —— 否则闯关战绩被改、快照重传)", _kind() == P2.SETTLE_FINALS, _kind())
	var fm: Dictionary = GameState.finals_match
	_ok("① finals_match 四个键照旧写上", int(fm.get("bucket", -9)) == 0 and int(fm.get("round", -9)) == 1
		and int(fm.get("match", -9)) == 3 and int(fm.get("side", -9)) == 1, str(fm))

	## ② 对照: 阶段是从【开局时钟】算的, 不是写死 finals
	MAP.stamp_finals_match(GameState, 0, 1, 3, 1, sat)
	_ok("② 对照: 换成周六的时钟 ⇒ 阶段跟着变成闯关赛(证明读的是时钟不是常量)",
		str(GameState.week_phase) == P2.PHASE_GAUNTLET, str(GameState.week_phase))

	## ③ 真入口: _try_start_match 必须经过这一步, 不许再就地只写 finals_match
	var src := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var i0 := src.find("func _try_start_match")
	var i1 := src.find("\nfunc ", i0 + 10)
	var body := src.substr(i0, i1 - i0)
	_ok("③ ★分母: 找到 _try_start_match 函数体", i0 >= 0 and body.length() > 100, str(body.length()))
	_ok("③ ★★开战入口调了 stamp_finals_match", body.find("stamp_finals_match(") >= 0)
	_ok("③ 开战入口不再就地写 finals_match(只写一半的那种)", body.find("GameState.finals_match =") < 0)

	GameState.week_phase = keep_phase
	GameState.finals_match = keep_match
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
