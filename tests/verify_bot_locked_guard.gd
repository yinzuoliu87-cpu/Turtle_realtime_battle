extends Node
## verify_bot_locked_guard.gd —— 陪练号已锁统领本周不能上场 ⇒ 本轮不排队(2026-11-15)。
##
## 由来: 11-14 周六用户 iPad 闯关赛「匹配成功」后「结算失败，请重新开战」—— 陪练号 p01 / p02 用旧版(0.22.9)锁了本周统领,
##   0.23.3 的「拥有 ∪ 本周限免」规则不认 ⇒ 排上闯关被裁判拒(b_bad_snapshot)。memory project-bot-locked-leaders-1114 根治①。
## 判据(走 PetLevelsNet.bad_locked, 陪练号 sim_driver._do_team 开打前就用它):
##   ① 分母: 登录了后端(有账号) ⇒ 过滤开; 本周能上场的 ≥ 3 只、且全 28 只里有本周不能上场的
##   ② 锁的三只都能上 ⇒ 不拦(空表)
##   ③ 锁里混了一只本周不能上的 ⇒ 把那一只报出来(只报它)
##   ④ 没登录后端(本机开发 / 门禁) ⇒ 不过滤 ⇒ 不拦(与 fill_allowed 同一口径)
##   ⑤ sim_driver 源码里 `_do_team` 真的调了它, 而且在「没锁才清空重选」之前(否则锁着的号照样往下走去开打)
## 反向验证: bad_locked 恒返回 [] ⇒ ③ 红; 删 sim_driver 那段 ⇒ ⑤ 红。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 陪练号已锁统领本周不能上场 ⇒ 不排队 ===")
	var gs = get_node_or_null("/root/GameState")
	var acc0: String = str(gs.account_id)
	var wk0: int = int(gs.week_anchor_ts)
	var own0: Array = PetLevelsNet.owned.duplicate()
	gs.test_mode = true
	gs.account_id = "acc_guard_probe"
	gs.week_anchor_ts = 1763337600
	PetLevelsNet.owned = []
	var ok_ids: Array = PetLevelsNet.allowed_now()
	var not_ok: Array = []
	for p in WeeklyFree.ALL:
		if not ok_ids.has(str(p)):
			not_ok.append(str(p))
	_ok("① 分母: 过滤开着(有账号)、本周能上 %d 只、不能上 %d 只" % [ok_ids.size(), not_ok.size()],
		PetLevelsNet.filter_on() and ok_ids.size() >= 3 and not_ok.size() >= 1)
	if ok_ids.size() >= 3 and not_ok.size() >= 1:
		var good: Array = [ok_ids[0], ok_ids[1], ok_ids[2]]
		_ok("② 锁的三只都能上 ⇒ 不拦", PetLevelsNet.bad_locked(good).is_empty(), str(PetLevelsNet.bad_locked(good)))
		var mixed: Array = [ok_ids[0], not_ok[0], ok_ids[1]]
		var b: Array = PetLevelsNet.bad_locked(mixed)
		_ok("③ ★★锁里混了一只本周不能上的(%s) ⇒ 报出来且只报它" % str(not_ok[0]), b.size() == 1 and str(b[0]) == str(not_ok[0]), str(b))
	gs.account_id = ""
	_ok("④ 没登录后端 ⇒ 不过滤 ⇒ 不拦", PetLevelsNet.bad_locked(["no_such_pet"]).is_empty())
	gs.account_id = acc0
	gs.week_anchor_ts = wk0
	PetLevelsNet.owned = own0
	## ⑤ 接线: _do_team 里调了 bad_locked, 而且在「if not locked: 清空重选」之前
	var src: String = FileAccess.get_file_as_string("res://scripts/systems/sim/sim_driver.gd")
	var i_fn: int = src.find("func _do_team(")
	var i_guard: int = src.find("PetLevelsNet.bad_locked(", i_fn)
	var i_clear: int = src.find("t.call(\"_on_clear_all\")", i_fn)
	_ok("⑤ ★陪练号 _do_team 开打前把关(调用在清空重选之前)", i_fn >= 0 and i_guard > i_fn and i_clear > i_guard,
		"fn %d · guard %d · clear %d" % [i_fn, i_guard, i_clear])
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
