extends Node
## verify_await_token_fresh.gd —— 等令牌只认【没过期】的令牌(2026-10-11 全项目通读·赛制第 7 条)
##
## ★读码发现: `_await_token` 入口判 token_fresh, 但等待循环里判的是 `_token != ""` ⇒
##   手里攥着一个**已过期**的旧令牌时, 第一帧就放行 ⇒ 后台一小时回来, 第一批上传/拉对手带过期令牌 401,
##   拉对手悄悄回落机器人。
## ★判据: 旧令牌已过期、续期也没成功(本进程没配后端 ⇒ 续不了) ⇒ `_await_token()` 必须返回 false。

const SB := preload("res://scripts/net/supabase.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 等令牌只认没过期的 ===")
	var now: int = int(Time.get_unix_time_from_system())
	SB._reset_auth_for_test()
	SB._token = "expired-token"
	SB._expires_at = now - 100
	SB._auth_inflight = false
	_ok("★分母: 这个令牌确实判为不新鲜", not SB.token_fresh(now))
	var n = SB.new()
	add_child(n)
	var got: bool = await n._await_token()
	_ok("★★过期令牌、续期没成 ⇒ _await_token 返回 false(不拿过期令牌去发请求)", got == false, "返回 %s" % str(got))
	SB._token = "fresh-token"
	SB._expires_at = now + 3600
	var got2: bool = await n._await_token()
	_ok("★对照: 新鲜令牌 ⇒ 直接放行", got2 == true, "返回 %s" % str(got2))
	n.queue_free()
	SB._reset_auth_for_test()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
