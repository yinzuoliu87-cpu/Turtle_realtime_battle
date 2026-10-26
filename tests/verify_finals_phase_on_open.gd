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
	## ★2026-10-26 闯关赛收盘挪到周日 17:30 UTC ⇒ 「周日 = 决赛日」钉 19:00(原来钉 10:00, 现在那是闯关赛);
	##   周日 10:00 留作 ② 的对照: 那一刻按时钟是闯关赛, 而对阵图开的局仍必须是决赛。
	var sun: int = P2.week_anchor_utc(int(Time.get_unix_time_from_system())) + 6 * 86400 + 19 * 3600
	var sun_am: int = sun - 9 * 3600

	## ① 复现现场: 周六选过队(存档里是 gauntlet), 周日从对阵图直接开战
	var keep_dual := bool(GameState.dual_active)
	GameState.week_phase = P2.PHASE_GAUNTLET
	GameState.finals_match = {}
	## ★2026-10-11 周日实操: 刚启动的进程 dual_active 是默认 false(主菜单「开始战斗」才写 true)
	GameState.dual_active = false
	_ok("① ★分母: 开战前存档里确实是周六的阶段(复现现场)", _kind() == P2.SETTLE_GAUNTLET, _kind())
	MAP.stamp_finals_match(GameState, 0, 1, 3, 1, sun)
	_ok("① ★★开战后 dual_active = true(否则打的是非双路对局: 十几秒就完、不录像)", bool(GameState.dual_active))
	_ok("① ★★这一局会录像(对阵图格子的「回放」靠它)", ReplayRecorder.should_record())
	_ok("① ★★开战后 week_phase = 决赛日", str(GameState.week_phase) == P2.PHASE_FINALS, str(GameState.week_phase))
	_ok("① ★★结算口径 = SETTLE_FINALS(不是闯关赛 —— 否则闯关战绩被改、快照重传)", _kind() == P2.SETTLE_FINALS, _kind())
	var fm: Dictionary = GameState.finals_match
	_ok("① finals_match 四个键照旧写上", int(fm.get("bucket", -9)) == 0 and int(fm.get("round", -9)) == 1
		and int(fm.get("match", -9)) == 3 and int(fm.get("side", -9)) == 1, str(fm))

	## ② ★★2026-10-26 判据反过来了: 原来是「阶段从开局时钟算, 换成周六时钟就变闯关赛」。
	##   闯关赛打到周日 17:30 之后, 周日上午按时钟是**闯关赛** —— 而对阵图上开的那一局**就是决赛**,
	##   产品改成显式戳 PHASE_FINALS(`BracketMapScene.stamp_finals_match`, 不再读 `now_utc`)。
	##   ⇒ 量「时钟说闯关赛的那一刻, 对阵图开局照样戳成决赛」, 并先证明那一刻时钟确实说的是闯关赛。
	_ok("② ★分母: 周日 10:00 按时钟是闯关赛(收盘 17:30 之前) —— 下一条才不是恒真",
		P2.phase_at_utc(sun_am) == P2.PHASE_GAUNTLET, P2.phase_at_utc(sun_am))
	GameState.week_phase = P2.PHASE_GAUNTLET
	MAP.stamp_finals_match(GameState, 0, 1, 3, 1, sun_am)
	_ok("② ★★周日上午(时钟仍是闯关赛)从对阵图开战 ⇒ week_phase 仍是决赛日(不跟时钟走)",
		str(GameState.week_phase) == P2.PHASE_FINALS, str(GameState.week_phase))
	_ok("② ★★结算口径 = SETTLE_FINALS", _kind() == P2.SETTLE_FINALS, _kind())

	## ③ 真入口: _try_start_match 必须经过这一步, 不许再就地只写 finals_match
	var src := FileAccess.get_file_as_string("res://scripts/scenes/BracketMapScene.gd")
	var i0 := src.find("func _try_start_match")
	var i1 := src.find("\nfunc ", i0 + 10)
	var body := src.substr(i0, i1 - i0)
	_ok("③ ★分母: 找到 _try_start_match 函数体", i0 >= 0 and body.length() > 100, str(body.length()))
	_ok("③ ★★开战入口调了 stamp_finals_match", body.find("stamp_finals_match(") >= 0)
	_ok("③ 开战入口不再就地写 finals_match(只写一半的那种)", body.find("GameState.finals_match =") < 0)

	## ③b ★2026-10-18: 拿对手失败后必须清掉「在等这一场」(杯赛半决赛 / 决赛因此挂一小时被代判)
	var SBF = load("res://scripts/net/supabase.gd")
	var mp = MAP.new()
	mp._await_match = Vector2i(2, 1)
	SBF._opp = {"ok": false, "reason": "wrong_round"}
	SBF._opp_tried = true
	var started: bool = mp._try_start_match()
	_ok("③b ★分母: 拿对手失败 ⇒ 不开打", not started)
	_ok("③b ★★拿对手失败 ⇒ 等待标记清掉(再点就是重新问)", mp._await_match == Vector2i(-1, -1), str(mp._await_match))
	SBF.opponent_clear()
	mp.free()

	## ★2026-10-11: 2 人一组只有决赛一场, 倒计时不许写「下一轮」
	var t2: String = MAP.round_tip(1, 2, 322)
	_ok("④ ★★2 人组第 1 轮 = 决赛, 不写「下一轮」", t2.begins_with("决赛") and t2.find("下一轮") < 0, t2)
	var t8a: String = MAP.round_tip(1, 8, 60)
	var t8c: String = MAP.round_tip(3, 8, 60)
	_ok("④ 对照: 8 人组第 1 轮仍是「下一轮」、第 3 轮是「决赛」", t8a.begins_with("下一轮") and t8c.begins_with("决赛"),
		"%s / %s" % [t8a, t8c])

	GameState.week_phase = keep_phase
	GameState.finals_match = keep_match
	GameState.dual_active = keep_dual
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
