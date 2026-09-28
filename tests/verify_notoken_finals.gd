extends Node
## verify_notoken_finals.gd — 周日决赛日: 【请求根本没发出去】那一刻屏幕不许说谎
## (2026-09-28)
##
## ══════════════════════════════════════════════════════════════════════
##  守的是哪个 bug
## ══════════════════════════════════════════════════════════════════════
## 屏幕原文: 「本周没有你的桶 · 周六闯关赛晋级才进得来」
## 对谁说的: 一个**真的打进了决赛日**的玩家(promoted=true / gauntlet_state=in / 闯关赛 4-0)。
##
## `Supabase.fetch_finals_async` 在 `_token == ""` 时**请求一个字节都不发**, 却把
## `_finals_tried` 标成 true, 而 `_finals_view` 留空**且没有 `reason` 字段** ⇒
## `BracketMapScene._empty_text()` 三道判据全躲过(`finals_tried()` 已真 →
## reason != UNREACHABLE → reason != too_few) ⇒ 掉到兜底那句。
##
## ★**不是边角**: `_token` 只活在内存、从不落盘 ⇒ **每次冷启动都是空的**;
##   而周日主菜单那扇「决赛日 · 看对阵图 →」**第一帧就能点**, 恢复要等
##   `BracketMapScene.REFRESH_SEC = 30` ⇒ **最长 30 秒都在说这句假话**。
## ★这是 2026-09-27 修过的同一个 bug 的另一半: 那次修的是**回包**侧
##   (「问不到就别抹掉好数据、别说成你没桶」), **请求侧这一半漏了**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① **走真路径**: `fetch_finals_async` → `_empty_text()`, 不是自己拼一个字典去喂
##      纯函数(纯函数那半 `verify_finals_feed` 已经守了; 漏掉的恰恰是**入口那道闸**)。
## ★② **后端要真打开着**。门禁给每个测试 `TURTLE_SUPABASE=" "` ⇒ `enabled()` 恒假,
##      而 `enabled()` 假时 `fetch_finals` 那条早退是**另一个分支**、说的是另一句话
##      ⇒ 关着后端跑的话这一整节都在量错的分支(memory `fb-gate-subject-never-constructed`)。
##      照 `verify_finals_feed` ⑩ 那一节的样式: `OS.set_environment` + ProjectSettings
##      临时打开后端 + `_transport_for_test` 塞假回包, **不碰网络**。
## ★③ **每条断言配分母**: 后端真开着 / token 真是空的 / 玩家真是已晋级 /
##      请求真的一个字节都没发 / 那句话真被算出来了。
##      少任何一条, 这一节都可能因为「前提根本不成立」而空绿。
## ★④ **判据不许恒真**: 同一个 `_empty_text()` 在「还没问过」时必须说另一句话,
##      在「服务端真说了没报名」时必须说第三句话 —— 三句两两不同。
## ★⑤ **与上一轮的修复共存**: 「问不到别抹掉上一份好视图」焊在回调里,
##      这里的写法如果一律覆盖, 就会把那条修回去 ⇒ 专门配一条断言。
##
## 跑法:
##   TURTLE_BACKEND=" " TURTLE_SUPABASE=" " <godot> --headless --audio-driver Dummy \
##     --path . res://tests/verify_notoken_finals.tscn --quit-after 6000

const SB := preload("res://scripts/net/supabase.gd")
const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const WEEK := 1789862400

var _n := 0
var _fail := 0
var _reqs: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 一段像真的 `finals_view` 回包(4 人桶, 第 1 轮已翻面)。
func _body() -> String:
	return JSON.stringify({
		"ok": true, "bucket": 3, "n": 4, "round": 2, "closed": false,
		"round_at": 820, "next_at": 1300, "now": 1000,
		"entrants": [
			{"seed": 0, "name": "阿龟", "account_id": "uid-a"},
			{"seed": 1, "name": "小乙", "account_id": "uid-me"},
			{"seed": 2, "name": "老丙", "account_id": "uid-c"},
			{"seed": 3, "name": "丁丁", "account_id": "uid-d"},
		],
		"done": {"1-0": 0},
	})


## 屏幕中间那句话。★走**真** `_empty_text()`, 不复述它的逻辑。
func _screen() -> String:
	var m = MAP.new()
	var t := str(m._empty_text())
	m.free()
	return t


func _ready() -> void:
	await get_tree().process_frame
	print("=== 决赛日: 请求没发出去时屏幕不许说谎 (2026-09-28) ===")

	# ── 存下来, 收尾要逐个还原(全是 static / 环境变量, 活过本测试) ──
	var env0: String = OS.get_environment(SB.ENV_URL)
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	var gs = get_node_or_null("/root/GameState")
	var acc0 := str(gs.account_id) if gs != null else ""
	var promoted0 = gs.promoted if gs != null else false
	var gw0 := int(gs.gauntlet_wins) if gs != null else 0
	var gl0 := int(gs.gauntlet_losses) if gs != null else 0
	var tm0 = gs.test_mode if gs != null else false

	await _t_notoken()

	# ── 收尾 ──
	SB._transport_for_test = Callable()
	SB.finals_clear()
	SB._reset_auth_for_test()
	if gs != null:
		gs.account_id = acc0
		gs.promoted = promoted0
		gs.gauntlet_wins = gw0
		gs.gauntlet_losses = gl0
		gs.test_mode = tm0
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.set_environment(SB.ENV_URL, " ")
	_ok("⑨ ★收尾: 后端已关回去(留着会把后面每个测试都喂上假后端)", not SB.enabled(),
		"base='%s' key='%s'" % [SB.base_url(), str(SB.anon_key())])
	_ok("⑨ ★收尾: 缓存/令牌/传输都清了(它们是 static, 活过本测试)",
		SB.finals_cached().is_empty() and not SB.finals_tried()
			and SB.access_token() == "" and not SB._transport_for_test.is_valid(),
		"view=%s tried=%s token='%s'" % [str(SB.finals_cached()),
			str(SB.finals_tried()), SB.access_token()])

	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d/%d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


func _t_notoken() -> void:
	var gs = get_node_or_null("/root/GameState")
	_ok("① ★分母: 拿到 GameState(拿不到的话下面全是空检查)", gs != null)
	if gs == null:
		return

	## ── 把后端真打开(否则量到的是 `not enabled()` 那条**别的**分支) ──
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	_ok("① ★★分母: 后端**真的打开了** —— 这一节要量的是「后端在、只是还没 token」",
		SB.enabled(), "base=%s" % SB.base_url())

	## ── 造一个【真的打进了决赛日】的玩家 ──
	gs.test_mode = true
	gs.account_id = "uid-me"           # 服务端认得出他是谁
	gs.promoted = true                 # 积分赛收盘拿到闯关赛资格
	gs.gauntlet_wins = 4               # 闯关赛 4-0 = 打进决赛日
	gs.gauntlet_losses = 0
	_ok("① ★★分母: 这个玩家**真的已晋级**(promoted + gauntlet_state=IN) —— 对他说「晋级才进得来」才叫说谎",
		bool(gs.promoted) and gs.gauntlet_state() == P2C.GAUNTLET_IN
			and str(gs.account_id) != "",
		"promoted=%s state=%s acc=%s" % [str(gs.promoted), gs.gauntlet_state(),
			str(gs.account_id)])

	## ── token 清空: 冷启动头一秒 / 离线 / 过期, 全是这一格 ──
	SB._reset_auth_for_test()
	SB.finals_clear()
	_ok("① ★★分母: token **真是空的**(它只活在内存、从不落盘 ⇒ 每次冷启动都是这一格)",
		SB.access_token() == "", "token='%s'" % SB.access_token())
	_ok("① ★分母: 一开始「还没问过」, 缓存是空的", not SB.finals_tried()
		and SB.finals_cached().is_empty(), str(SB.finals_cached()))

	## ═══════════════════════════════════════════════════════════════
	##  ② 走真入口: 请求真的没发出去, 而屏幕不许说「你没桶」
	## ═══════════════════════════════════════════════════════════════
	print("── ② 没 token 时走真入口 fetch_finals_async ──")
	_reqs.clear()
	SB._transport_for_test = func(m, u, h, b, cb):
		_reqs.append({"method": str(m), "url": str(u), "headers": h, "body": str(b)})
		cb.call({"ok": true, "code": 200, "body": _body()})
	SB._finals_inflight = false
	SB.fetch_finals_async(WEEK, -1)
	for _i in range(4):
		await get_tree().process_frame

	_ok("② ★★分母: 请求**一个字节都没发出去**(没登录就别白跑一趟 —— 这条行为要保住)",
		_reqs.is_empty(), "发出 %d 条" % _reqs.size())
	_ok("② ★分母: 但标成了「问过了」—— 否则屏幕会永远转着「正在连线」(实拍抓到过)",
		SB.finals_tried())
	_ok("② ★★★没发出去 ⇒ 缓存要标成「问不到」(UNREACHABLE), 不许留一个**没有 reason 的空字典**",
		str(SB.finals_cached().get("reason", "")) == SB.UNREACHABLE,
		str(SB.finals_cached()))
	var txt_notoken := _screen()
	print("    屏幕中间那句 = 「%s」" % txt_notoken)

	## ═══════════════════════════════════════════════════════════════
	##  ③ 屏幕说的那句话: **不抄字面量**, 量它与另外三种空态的关系
	## ═══════════════════════════════════════════════════════════════
	## ★★★为什么不写 `contains("连不上服务器")`: 那会把措辞钉在门禁里, 产品换个说法
	##   就红(2026-09-28 全屏刚把「桶」改成「一组」, 老判据当场被钉住过)。
	##   这里量的三条关系, **换措辞不影响、换行为一定红**:
	##     · 请求侧没发出去 **必须与回包侧「问不到」说同一句话** ——
	##       这正是「同一个 bug 的另一半」这句话的可验形式。
	##     · 必须**不同于**服务端真答「你没报名」那一句(那才是原来的谎)。
	##     · 必须**不同于**「还没问过」那一句(否则会永远转着「正在找」)。
	print("── ③ 屏幕那句话: 量关系, 不抄字面量 ──")

	## (a) 回包侧「问不到」: 有 token、真发出去了、服务端回 500
	SB.finals_clear()
	SB._token = "gate-token"
	SB._transport_for_test = func(m, u, h, b, cb):
		_reqs.append({"method": str(m), "url": str(u), "headers": h, "body": str(b)})
		cb.call({"ok": true, "code": 500, "body": "<html>502 bad gateway</html>"})
	_reqs.clear()
	SB._finals_inflight = false
	SB.fetch_finals_async(WEEK, -1)
	for _i2 in range(4):
		await get_tree().process_frame
	_ok("③a ★分母: 这一次**真发了**请求(有 token 就该发)", _reqs.size() == 1,
		"发出 %d 条 url=%s" % [_reqs.size(),
			str(_reqs[0].get("url", "")) if _reqs.size() > 0 else "-"])
	_ok("③a ★分母: 回包侧也标成了 UNREACHABLE(2026-09-27 修的那一半还在)",
		str(SB.finals_cached().get("reason", "")) == SB.UNREACHABLE,
		str(SB.finals_cached()))
	var txt_unreach := _screen()

	## (b) 服务端**真答**「你没报名」—— 那句话本身是**对的**, 不许被这次修复删掉
	SB.finals_clear()
	SB._transport_for_test = func(m, u, h, b, cb):
		_reqs.append({"method": str(m), "url": str(u), "headers": h, "body": str(b)})
		cb.call({"ok": true, "code": 200, "body": '{"ok":false,"reason":"not_entered"}'})
	_reqs.clear()
	SB._finals_inflight = false
	SB.fetch_finals_async(WEEK, -1)
	for _i3 in range(4):
		await get_tree().process_frame
	_ok("③b ★分母: 这一次也真发了请求", _reqs.size() == 1, "发出 %d 条" % _reqs.size())
	_ok("③b ★分母: 服务端说「没报名」⇒ 缓存是空的(这才是「确实没有你这一组」)",
		SB.finals_cached().is_empty(), str(SB.finals_cached()))
	var txt_noseat := _screen()

	## (c) 还没问过
	SB.finals_clear()
	var txt_wait := _screen()

	print("    (a)问不到=「%s」" % txt_unreach)
	print("    (b)没报名=「%s」" % txt_noseat)
	print("    (c)还没问=「%s」" % txt_wait)
	_ok("③ ★★★请求侧没发出去 ⇒ 屏幕说的必须**和回包侧「问不到」一模一样**(同一个 bug 的两半)",
		txt_notoken == txt_unreach, "[%s] vs [%s]" % [txt_notoken, txt_unreach])
	_ok("③ ★★★而且**不许**等于「确实没有你这一组」那一句 —— 那是对一个真晋级的人说谎",
		txt_notoken != txt_noseat, "[%s] vs [%s]" % [txt_notoken, txt_noseat])
	_ok("③ ★也不许等于「还没问过」那一句(否则会永远转着「正在找」)",
		txt_notoken != txt_wait, "[%s] vs [%s]" % [txt_notoken, txt_wait])
	_ok("③ ★★分母: 那三句本来就两两不同 —— 否则上面三条里必有恒真的",
		txt_unreach != txt_noseat and txt_unreach != txt_wait
			and txt_noseat != txt_wait,
		"[%s] | [%s] | [%s]" % [txt_unreach, txt_noseat, txt_wait])

	## ═══════════════════════════════════════════════════════════════
	##  ④ ★★与上一轮的修复共存: 已经有好数据时, 没 token **不许抹掉它**
	## ═══════════════════════════════════════════════════════════════
	print("── ④ 有好数据时, 没 token 不许把签表抹掉 ──")
	SB.finals_clear()
	SB._token = "gate-token"
	SB._transport_for_test = func(m, u, h, b, cb):
		_reqs.append({"method": str(m), "url": str(u), "headers": h, "body": str(b)})
		cb.call({"ok": true, "code": 200, "body": _body()})
	_reqs.clear()
	SB._finals_inflight = false
	SB.fetch_finals_async(WEEK, -1)
	for _i3 in range(4):
		await get_tree().process_frame
	var v1: Dictionary = SB.finals_cached()
	_ok("④ ★分母: 先拿到了一份**真的签表**(拿不到 = 下面全是空检查)",
		int(v1.get("size", 0)) == 4 and int(v1.get("round", 0)) == 2,
		"size=%d round=%d" % [int(v1.get("size", 0)), int(v1.get("round", 0))])

	## token 掉了(过期 / 切后台回来), 下一拍轮询又来一次
	SB._reset_auth_for_test()
	_ok("④ ★分母: token 真的掉了", SB.access_token() == "")
	_reqs.clear()
	SB._finals_inflight = false
	SB.fetch_finals_async(WEEK, -1)
	for _i4 in range(4):
		await get_tree().process_frame
	_ok("④ ★分母: 这一次又是一个字节都没发", _reqs.is_empty(), "发出 %d 条" % _reqs.size())
	var v2: Dictionary = SB.finals_cached()
	_ok("④ ★★★上一份好签表**还在**(2026-09-27 刚焊死的那条, 不许被这次修复顶回去)",
		int(v2.get("size", 0)) == 4 and int(v2.get("round", 0)) == 2
			and str(v2.get("reason", "")) != SB.UNREACHABLE,
		str(v2).substr(0, 160))

	SB._transport_for_test = Callable()
	SB.finals_clear()

	## ═══════════════════════════════════════════════════════════════
	##  ⑤ ★★同族: 请求没发出去, **闸也必须放开**(2026-09-28 穷举同族时抓到)
	## ═══════════════════════════════════════════════════════════════
	## `_auth_inflight` 是 `ensure_signed_in_async` **进门之前**就置上的, 而
	## `sign_in_anonymous` 的 `not enabled()` 早退原来**不清它** ⇒ 一旦走到,
	## `_auth_inflight` 永久为真 ⇒ 之后每次 `ensure_signed_in_async` 都在第一行 return
	## ⇒ **这个进程再也拿不到 token** ⇒ 存档不同步 + 周日永远看不到分组
	##   (而且屏幕只会说「连不上」—— 上面 ② 那句话会变成永久的)。
	## ★旁证(不是我猜的口径): 同文件 `refresh_session` 的同一条早退**是**清的。
	print("── ⑤ 同族: 没发出去 ⇒ inflight 闸必须放开 ──")
	OS.set_environment(SB.ENV_URL, " ")     # 后端关掉 ⇒ 走 `not enabled()` 那条早退
	_ok("⑤ ★分母: 后端真的关了(开着就走不到那条早退, 这一节全是空检查)",
		not SB.enabled(), "base='%s'" % SB.base_url())
	var n2 = SB.new()
	add_child(n2)
	_reqs.clear()
	n2._transport = func(m, u, h, b, cb):
		_reqs.append({"method": str(m), "url": str(u), "headers": h, "body": str(b)})
		cb.call({"ok": false, "code": 0, "body": ""})
	SB._auth_inflight = true                # 调用方进门前置上的那一格
	_ok("⑤ ★分母: 闸**真的是关着**的(不是本来就开着 ⇒ 下面那条才不是恒真)",
		SB._auth_inflight)
	n2.sign_in_anonymous()
	await get_tree().process_frame
	_ok("⑤ ★分母: 请求一个字节都没发出去(这一节量的就是「没发出去」那条路)",
		_reqs.is_empty(), "发出 %d 条" % _reqs.size())
	_ok("⑤ ★★★没发出去 ⇒ `_auth_inflight` 必须放回 false, 否则这个进程再也登不上",
		not SB._auth_inflight)
	n2.queue_free()
	await get_tree().process_frame
	SB._reset_auth_for_test()
