extends Node
## verify_upload_auth.gd — 上传对手快照前必须先有【这个账号的】登录令牌 (2026-10-04)
##
## 由来: 10 个模拟号这周打了两百多场积分赛, 服务端 `ghosts` 里一行都没有(真库只读查实)。
##   探针: 令牌为空时上传 ⇒ `_headers()` 退回公共匿名钥匙 ⇒ 401 / 42501「违反行级权限」;
##   先续期拿到令牌再传 ⇒ 201。令牌只活在内存(冷启动头几秒为空)、约 1 小时过期,
##   上传那条路原来**不看令牌**就发, 失败只记计数不打日志。
## ★走真入口 `upload_ghost_async` / `upload_gauntlet_async`, 网络用注入的假传输(不碰真服务器),
##   量的是**真正发出去的请求**: 先续期, 再带着新令牌上传。

const SB := preload("res://scripts/net/supabase.gd")

var _fail := 0
var _n := 0
var _reqs: Array = []

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _bearer(h) -> String:
	for line in (h as PackedStringArray):
		if str(line).begins_with("Authorization: Bearer "):
			return str(line).substr(len("Authorization: Bearer "))
	return ""


func _ready() -> void:
	await get_tree().process_frame
	print("=== 上传快照前必须先有登录令牌 ===")
	var gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", gs != null)
	if gs == null:
		get_tree().quit(1)
		return
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var acc0 := str(gs.account_id)
	var ref0 := str(gs.auth_refresh)
	var tm0 = gs.test_mode

	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	gs.test_mode = true
	gs.account_id = "uid-me"
	gs.auth_refresh = "r1"
	_ok("★分母: 后端真的打开了", SB.enabled())

	for table in ["ghosts", "gauntlet_ghosts", "pull:ghosts", "pull:gauntlet_ghosts", "rpc/finals_opponent", "rpc/finals_report"]:
		SB._reset_auth_for_test()
		gs.auth_refresh = "r1"
		_reqs.clear()
		SB._transport_for_test = func(m, u, h, b, cb):
			_reqs.append({"url": str(u), "bearer": _bearer(h)})
			if str(u).find("/auth/v1/token") >= 0:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({
					"access_token": "tok-new", "refresh_token": "r2", "expires_in": 3600,
					"user": {"id": "uid-me", "is_anonymous": true}})})
			else:
				cb.call({"ok": true, "code": 200 if (str(m) == "GET" or str(u).find("/rpc/") >= 0) else 201, "body": "[]" if str(m) == "GET" else ("{\"ok\":true}" if str(u).find("/rpc/") >= 0 else "")})
		_ok("[%s] ★分母: 起点令牌是空的(冷启动 / 过期)" % table, SB.access_token() == "")
		if table == "ghosts":
			SB.upload_ghost_async(SB.ghost_row_from_snapshot({"x": 1}, "uid-me", 1790553600, 3, "gate"))
		elif table == "gauntlet_ghosts":
			SB.upload_gauntlet_async(SB.gauntlet_row_from_snapshot({"x": 1}, "uid-me", 1790553600, 1, 0, "gate"))
		elif table == "pull:ghosts":
			SB.pull_opponents_async(1790553600, 3, "uid-me")
		elif table == "pull:gauntlet_ghosts":
			SB.pull_gauntlet_async(1790553600, 1, 0, "uid-me")
		elif table == "rpc/finals_opponent":
			SB.opponent_clear()
			SB._opp_inflight = false
			SB.fetch_opponent_async(1790553600, 0, 1, 3)
		else:
			SB.finals_report_clear()
			SB._report_inflight = false
			SB.report_finals_async(1790553600, 0, 1, 0, 0, 42)
		for _i in range(60):
			await get_tree().process_frame
		var up := {}
		var refresh_i := -1
		var up_i := -1
		for i in range(_reqs.size()):
			var r: Dictionary = _reqs[i]
			if str(r["url"]).find("/auth/v1/token") >= 0 and refresh_i < 0:
				refresh_i = i
			if str(r["url"]).find("/rest/v1/" + table.trim_prefix("pull:") + ("?" if table.begins_with("pull:") else "")) >= 0:
				up = r
				up_i = i
		_ok("[%s] ★★上传真的发出去了" % table, up_i >= 0, str(_reqs))
		_ok("[%s] ★★上传带的是【这个账号的令牌】, 不是公共匿名钥匙(原 bug: 401 / 42501)" % table,
			str(up.get("bearer", "")) == "tok-new", "bearer=%s" % str(up.get("bearer", "")))
		_ok("[%s] 先续期、后上传" % table, refresh_i >= 0 and refresh_i < up_i, "续期#%d 上传#%d" % [refresh_i, up_i])

	## 分母: 令牌本来就有效 ⇒ 不续期, 直接传
	SB._reset_auth_for_test()
	SB._token = "tok-live"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600
	_reqs.clear()
	SB.upload_ghost_async(SB.ghost_row_from_snapshot({"x": 1}, "uid-me", 1790553600, 4, "gate"))
	for _i in range(20):
		await get_tree().process_frame
	var n_ref := 0
	for r in _reqs:
		if str(r["url"]).find("/auth/v1/token") >= 0:
			n_ref += 1
	_ok("★分母: 令牌有效时不多续一次、直接带它上传",
		n_ref == 0 and _reqs.size() == 1 and str(_reqs[0]["bearer"]) == "tok-live", str(_reqs))

	SB._transport_for_test = Callable()
	SB._reset_auth_for_test()
	gs.account_id = acc0
	gs.auth_refresh = ref0
	gs.test_mode = tm0
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 上传前先有令牌" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
