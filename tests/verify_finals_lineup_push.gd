extends Node
## verify_finals_lineup_push.gd —— 周日决赛: 背包里调的阵容在哪一屏都交上去, 交没交上有回执(2026-11-15)。
## 用户 11-15:「这明明手明明在背包里面调了阵容，为什么在比赛里面的阵容不是这个备赛的呢？」
## 正式服只读核对: LouisT01 决赛用的是周六第 4 胜那一份 —— 原来只有对阵图界面会推, 推了也不看回包。
## 判据(注入传输, 量真发出去的请求; 钟钉死):
##   ① 备战窗内(不在对阵图, 只走全局层这一条)第一拍就推 finals_update_snapshot, 带组号
##   ② ★阵容一变 ≥ 2 秒就再推(不等 15 秒); 没变 15 秒内不重复推
##   ③ ★回执: 服务端回 true ⇒「阵容已提交…」; 同一份再推不重复说; 回 false ⇒「没有生效…」; 网络失败 ⇒「提交失败…重试」
##   ④ 备战窗外: 不推; 改了阵容 ⇒「下一轮备战开始时…」(一次)
##   ⑤ 没入座 / 组已收盘: 什么都不做
##   ⑥ 接线: 全局层 FinalsDay.tick 调 FinalsLineupPush.tick; supabase 回包交给 note_result
## 反向验证(11-15): 去掉「指纹变了提前推」⇒ ② 红; note_result 里把 body 判据写死 true ⇒ ③ 的「没有生效」红。

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const FLP := preload("res://scripts/net/finals_lineup_push.gd")

var _n := 0
var _fail := 0
var _sent: Array = []
var _reply: Array = ["true"]
var _code: Array = [200]


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _posts() -> int:
	return _sent.filter(func(x): return str(x["u"]).ends_with("/rpc/finals_update_snapshot")).size()


## 走一拍(钟往前拨 dt 秒), 等回包回来, 返回这一拍要弹的那句
func _step(lv: Dictionary, dt: int) -> String:
	P2C.now_override_ts += dt
	var msg: String = FLP.tick(lv, {}, P2C.now_override_ts)
	for _i in 4:
		await get_tree().process_frame
	## 回包在这几帧里到; 再拍一次(不拨钟)把回执取出来
	var msg2: String = FLP.tick(lv, {}, P2C.now_override_ts)
	return msg if msg != "" else msg2


func _ready() -> void:
	await get_tree().process_frame
	print("=== 决赛阵容: 在哪一屏都交上去 + 回执 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	var acc0 := str(gs.account_id)
	gs.account_id = "uid-me"
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	SB._transport_for_test = func(_m, u, _h, b, cb):
		_sent.append({"u": str(u), "b": str(b)})
		cb.call({"ok": _code[0] == 200, "code": _code[0], "body": _reply[0]})
	var leaders0 = gs.season_leaders.duplicate(true)
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.dual_lineup = {}
	var ts0: int = P2C.now_override_ts
	P2C.now_override_ts = 1794240000
	BE._finals_snap_at = 0
	FLP.reset()
	_ok("分母: 后端打开了(注入传输)", SB.enabled())
	var srv: int = P2C.now_override_ts
	## 我那一组: 2 人、我是 0 号、第 1 轮刚开打 30 秒(备战窗 180 秒还开着)
	var lv := {"size": 2, "round": 1, "me": 0, "bucket": 4, "closed": false, "round_at": srv - 30, "srv_now": srv, "recv_at": srv}
	## ── ① 窗内第一拍就推 ──
	var m1: String = await _step(lv, 0)
	_ok("① ★备战窗内第一拍就推(不在对阵图, 只走全局层)", _posts() == 1, "posts=%d" % _posts())
	var req: Array = _sent.filter(func(x): return str(x["u"]).ends_with("/rpc/finals_update_snapshot"))
	_ok("① 推的是 finals_update_snapshot、带组号 4 与快照", req.size() == 1 and str(req[0]["b"]).find("\"p_bucket\":4") >= 0 and str(req[0]["b"]).find("p_snapshot") >= 0)
	_ok("③ ★服务端回 true ⇒ 弹「阵容已提交」", m1 == FLP.TXT_OK, m1)
	## ── ② 没变 15 秒内不重推; 变了 ≥ 2 秒就推 ──
	var m2: String = await _step(lv, 5)
	_ok("② 阵容没变: 5 秒后不重推", _posts() == 1, "posts=%d" % _posts())
	_ok("③ 没有新回包 ⇒ 不弹", m2 == "", m2)
	## 改阵容: 上路两只、下路一只 → 换成下路两只(换路 = 背包里拖一下)
	var dl: Dictionary = gs.get_dual_lineup().duplicate(true)
	var top: Array = dl.get("top", [])
	var bot: Array = dl.get("bottom", [])
	if top.size() > 0:
		bot.append(top.pop_back())
	dl["top"] = top
	dl["bottom"] = bot
	gs.dual_lineup = dl
	var m3: String = await _step(lv, 2)
	_ok("② ★阵容一变, 2 秒就再推(不等 15 秒)", _posts() == 2, "posts=%d" % _posts())
	_ok("③ 新阵容收下 ⇒ 再弹「阵容已提交」", m3 == FLP.TXT_OK, m3)
	var m4: String = await _step(lv, 15)
	_ok("② 没变: 15 秒补推一次", _posts() == 3, "posts=%d" % _posts())
	_ok("③ 同一份补推收下 ⇒ 不重复弹", m4 == "", m4)
	## ── ③ 服务端不收 / 网络失败 ──
	_reply[0] = "false"
	gs.season_leaders = ["basic", "stone", "candy"]
	var m5: String = await _step(lv, 2)
	_ok("③ ★服务端回 false ⇒ 弹「没有生效」", m5 == FLP.TXT_REJECTED, m5)
	var m6: String = await _step(lv, 15)
	_ok("③ 同一份再被拒 ⇒ 不反复弹", m6 == "", m6)
	_reply[0] = ""
	_code[0] = 0
	gs.season_leaders = ["basic", "stone", "lava"]
	var m7: String = await _step(lv, 2)
	_ok("③ 网络失败 ⇒ 弹「提交失败, 正在重试」", m7 == FLP.TXT_NET, m7)
	_code[0] = 200
	_reply[0] = "true"
	## ── ④ 窗外: 不推; 改阵容 ⇒ 说清楚什么时候算 ──
	var lv_out := lv.duplicate()
	lv_out["round_at"] = P2C.now_override_ts - P2C.FINALS_SHOP_SEC - 60
	lv_out["srv_now"] = P2C.now_override_ts
	lv_out["recv_at"] = P2C.now_override_ts
	var p0 := _posts()
	var m8: String = await _step(lv_out, 20)
	_ok("④ 备战窗外不推", _posts() == p0, "posts %d → %d" % [p0, _posts()])
	_ok("④ 窗外没改阵容 ⇒ 不弹", m8 == "", m8)
	gs.season_leaders = ["basic", "stone", "phoenix"]
	var m9: String = await _step(lv_out, 3)
	_ok("④ ★窗外改了阵容 ⇒ 弹「下一轮备战开始时…」", m9 == FLP.TXT_LATER, m9)
	var m10: String = await _step(lv_out, 3)
	_ok("④ 只说一次", m10 == "", m10)
	## ── ⑤ 没入座 / 收盘 ──
	var p1 := _posts()
	var lv_watch := lv.duplicate()
	lv_watch["me"] = -1
	await _step(lv_watch, 20)
	var lv_closed := lv.duplicate()
	lv_closed["closed"] = true
	await _step(lv_closed, 20)
	_ok("⑤ 观众(me < 0)/ 组已收盘 ⇒ 不推", _posts() == p1, "posts %d → %d" % [p1, _posts()])
	## ── ⑥ 接线 ──
	var layer_src := FileAccess.get_file_as_string("res://scripts/ui/finals_day_layer.gd")
	var sb_src := FileAccess.get_file_as_string("res://scripts/net/supabase.gd")
	_ok("⑥ 全局层每拍调 FinalsLineupPush.tick(在哪一屏都推)", layer_src.contains("_FLP.tick("))
	_ok("⑥ supabase 回包交给 note_result(回执)", sb_src.contains("finals_lineup_push.gd\").note_result(res, snapshot)"))
	## 收尾
	gs.season_leaders = leaders0
	gs.dual_lineup = {}
	gs.account_id = acc0
	P2C.now_override_ts = ts0
	SB._transport_for_test = Callable()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	FLP.reset()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
