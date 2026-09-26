extends Node
## verify_finals_feed.gd — 周日决赛日的取数与门 (E-B3, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## E-B3 有三段, 这里守**客户端那两段**(服务端那段要真网络, 见
## `tools/probe_finals_server.py`, 33 条, 六变异全红):
##   ① **翻译**: 服务端回包 → 桶地图要的形状。名字按**种子**落位、`done` 的值过 int()、
##      「我」按 account_id 认出来、倒计时用**服务端的时间差**而不是本机绝对时钟。
##   ② **门**: 桶地图在这之前产品代码里**零个调用点** —— 只有门禁在喂它
##      (memory `fb-zero-caller-is-a-whole-class`)。三样一起才算有门:
##      `.tscn` 在 / 场景自己会取数 / 主菜单上真按得下去。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① **翻译那半是纯函数** ⇒ 直接喂一段回包字符串, 不用网络不用登录。
##      而「发没发 / 发给谁 / 带的什么」那半用 `_transport_for_test` 量**真实发出去的请求**,
##      不数我插的计数器(memory `fb-gate-must-measure-requirement-not-my-hook`)。
## ★② **门要两个方向都验**: 玩法没上线 ⇒ 门**不存在**(而不是点了没反应的按钮);
##      把 `PHASE_MODE_LIVE` 那一格改成 true ⇒ 门**出现**。
##      只验一边的话, 「上线那天只改一个常量」这句话没人守得住。
## ★③ **不剧透**这条在客户端这一侧的形状是: 翻译**不会凭空造出**当前轮的结果 ——
##      回包里没有就是没有。配分母: 回包里有的(已翻面那几轮)必须翻译得出来。
## ★④ 每条「拿不到」都配分母, 免得「库里本来就空」冒充「规则挡住了」。
##
## 跑法: <godot> --headless --path . res://tests/verify_finals_feed.tscn --quit-after 900

const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
## ★Backend 不是 autoload(产品侧是全局 class_name), 门禁里 preload 取它
const BK := preload("res://scripts/net/backend.gd")
const DEAD_URL := "http://127.0.0.1:9"
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _reqs: Array = []
var _next := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "headers": headers, "body": str(body)})
	cb.call(_next)


## 一段像真的回包。`round` = 2 ⇒ 第 1 轮已翻面、第 2 轮是当前轮。
## ★服务端**不会**把当前轮的结果放进 `done` —— 这里照它的真实行为造。
func _body(round_no: int, done: Dictionary, closed: bool = false,
		srv_now: int = 1000, next_at: int = 1300) -> String:
	return JSON.stringify({
		"ok": true, "bucket": 3, "n": 4, "round": round_no, "closed": closed,
		"round_at": next_at - 480, "next_at": next_at, "now": srv_now,
		"entrants": [
			{"seed": 0, "name": "阿龟", "account_id": "uid-a"},
			{"seed": 1, "name": "小乙", "account_id": "uid-me"},
			{"seed": 2, "name": "老丙", "account_id": "uid-c"},
			{"seed": 3, "name": "丁丁", "account_id": "uid-d"},
		],
		"done": done,
	})


func _ready() -> void:
	await get_tree().process_frame
	print("=== 决赛日取数与门 (E-B3) ===")
	## ★★带 await 的那几个是**协程**, 不写 await 就是“启动一下就走” ——
	##   判据的执行顺序会乱, 而且 `quit()` 可能在尾巴还没跑完就开了。
	##   实测代价: 一条变异(拿掉“匿名号不发请求”那道闸)**没红** ——
	##   不是判据写错了, 是那条判据根本没跑到
	##   (memory `fb-null-readback-makes-test-silently-abort` 同族: 断言变少是唯一线索,
	##    而总数恰好没变 ⇒ 连那条线索都没有)。
	_t_parse()
	await _t_no_spoiler()
	_t_countdown()
	await _t_real_request()
	await _t_door()
	await _t_empty()
	await _t_enter()
	await _t_opponent()
	await _t_report()
	await _t_settle_reports()
	SB._transport_for_test = Callable()
	SB.finals_clear()
	OS.set_environment("TURTLE_SUPABASE", " ")
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 决赛日取数与门" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 翻译
# ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ① 回包 → 屏幕要的形状 ──")
	var d: Dictionary = SB.parse_finals(true, 200, _body(2, {"1-0": 0, "1-1": 1}), "uid-me", 5000)
	_ok("① 桶容量 / 轮次", int(d.get("size", 0)) == 4 and int(d.get("round", 0)) == 2, str(d).substr(0, 120))
	_ok("① ★名字按**种子**落位(不靠回包顺序 —— 顺序是服务端的实现细节)",
		(d.get("names", []) as Array) == ["阿龟", "小乙", "老丙", "丁丁"], str(d.get("names")))
	_ok("① ★★「我」按 account_id 认出来 ⇒ 我的种子是 1", int(d.get("me", -9)) == 1,
		str(d.get("me")))
	_ok("① ★分母: 换一个 account_id ⇒ me = -1(证明上面那条是真认出来的, 不是恒等于 1)",
		int(SB.parse_finals(true, 200, _body(2, {}), "uid-someone-else", 5000).get("me", -9)) == -1)
	_ok("① ★空 account_id(没登录) ⇒ me = -1",
		int(SB.parse_finals(true, 200, _body(2, {}), "", 5000).get("me", -9)) == -1)

	## ★`done` 的值必须是 int: JSON 解出来是浮点, 拿浮点当"哪一侧"去比较会出错
	var done: Dictionary = d.get("done", {})
	_ok("① ★done 的键值都在", done.size() == 2 and done.has("1-0") and done.has("1-1"), str(done))
	_ok("① ★★done 的值是 int 不是 float(浮点当「哪一侧」比较会出错)",
		typeof(done.get("1-0")) == TYPE_INT and typeof(done.get("1-1")) == TYPE_INT,
		"%s / %s" % [typeof(done.get("1-0")), typeof(done.get("1-1"))])
	_ok("① 值本身对", int(done["1-0"]) == 0 and int(done["1-1"]) == 1, str(done))

	## 失败路径: 一律给空字典, 不给半张图
	_ok("① 网络失败 ⇒ 空", SB.parse_finals(false, 0, "", "uid-me", 1).is_empty())
	_ok("① HTTP 403 ⇒ 空", SB.parse_finals(true, 403, "{}", "uid-me", 1).is_empty())
	_ok("① 回包 ok=false ⇒ 空",
		SB.parse_finals(true, 200, '{"ok":false,"reason":"not_entered"}', "uid-me", 1).is_empty())
	_ok("① 不是 JSON ⇒ 空", SB.parse_finals(true, 200, "<html>", "uid-me", 1).is_empty())
	_ok("① n = 0 ⇒ 空(画不出图就别给半张)",
		SB.parse_finals(true, 200, '{"ok":true,"n":0}', "uid-me", 1).is_empty())

	## ★种子越界的行不许把 names 撑坏(服务端理论上不会发, 但客户端不能因此崩)
	var weird := '{"ok":true,"n":2,"round":1,"entrants":[{"seed":9,"name":"越界","account_id":"x"},' \
		+ '{"seed":0,"name":"正常","account_id":"uid-me"}],"done":{}}'
	var wd: Dictionary = SB.parse_finals(true, 200, weird, "uid-me", 1)
	_ok("① ★种子越界的行被丢掉, names 长度还是 n",
		(wd.get("names", []) as Array).size() == 2
			and (wd.get("names", [])as Array)[0] == "正常", str(wd.get("names")))


# ─────────────────────────────────────────────────────────────
# ② 不剧透 —— 在客户端这一侧的形状
# ─────────────────────────────────────────────────────────────
func _t_no_spoiler() -> void:
	print("── ② 不剧透(客户端这一侧) ──")
	## 服务端在第 2 轮时只发第 1 轮的结果。翻译不许凭空造出 2-0。
	var d: Dictionary = SB.parse_finals(true, 200, _body(2, {"1-0": 0, "1-1": 1}), "uid-me", 1)
	var done: Dictionary = d.get("done", {})
	_ok("② ★分母: 已翻面那一轮**翻译得出来**(否则下面「没有」是恒真)",
		done.has("1-0") and done.has("1-1"), str(done))
	_ok("② ★★当前轮(第 2 轮)在翻译后**一个字都没有** —— 回包里没有就是没有",
		not done.has("2-0"), str(done))

	## 喂给真场景: 当前轮那一场 `winner_side` 必须是 -1
	var m = MAP.new()
	add_child(m)
	m.set_bucket(d)
	await get_tree().process_frame
	_ok("② ★★真场景里: 当前轮那一场 winner_side = -1(体感上是直播, 全靠这条)",
		int(m.winner_side(2, 0)) == -1, str(m.winner_side(2, 0)))
	_ok("② ★分母: 已翻面那两场 winner_side 是 0 / 1",
		int(m.winner_side(1, 0)) == 0 and int(m.winner_side(1, 1)) == 1,
		"%d / %d" % [m.winner_side(1, 0), m.winner_side(1, 1)])
	## ★四人桶的坐次是 `0,3,1,2` —— 第 0 场是 0 vs 3, 第 1 场是 1 vs 2 ⇒
	##   种子 1(我)在**第 1 场**。我第一版写成第 0 场, 门禁当场拓了出来(focus=(1,1)) ——
	##   错的是我的判据不是代码(同族: verify_bracket 那次「1v3 该半决赛碰」也是我错了)。
	_ok("② ★「我」在真场景里也认得出(四人桶坐次 0,3,1,2 ⇒ 种子 1 在第 1 场)",
		m.is_my_match(1, 1), "focus=%s" % str(m.my_focus()))
	_ok("② ★分母: 第 0 场(0 vs 3)不是我的 —— 否则上面那条是恒真",
		not m.is_my_match(1, 0))
	m.queue_free()


# ─────────────────────────────────────────────────────────────
# ③ 倒计时用服务端的时间差
# ─────────────────────────────────────────────────────────────
func _t_countdown() -> void:
	print("── ③ 倒计时(不看本机绝对时钟) ──")
	## 服务端说: 现在 1000, 下一轮 1300 ⇒ 还剩 300 秒。收包时本机时刻 = 5000。
	var d: Dictionary = SB.parse_finals(true, 200, _body(2, {}, false, 1000, 1300), "uid-me", 5000)
	_ok("③ ★收包时剩 300 秒(= next_at − 服务端的 now, **不是** 本机的 now)",
		int(d.get("left", -1)) == 300, str(d.get("left")))
	_ok("③ ★分母: 本机时刻(5000)跟服务端时刻(1000)差了 4000 秒, 而 left 没被它污染",
		int(d.get("left", -1)) == 300 and int(d.get("recv_at", 0)) == 5000, str(d).substr(0, 120))
	## finals_left() 走缓存, 所以先塞进去
	SB._finals_view = d
	_ok("③ 本机又过了 0 秒 ⇒ 还剩 300", int(SB.finals_left(5000)) == 300, str(SB.finals_left(5000)))
	_ok("③ ★本机又过了 120 秒 ⇒ 还剩 180(用的是**时间差**)",
		int(SB.finals_left(5120)) == 180, str(SB.finals_left(5120)))
	_ok("③ ★过了头 ⇒ 钳到 0, 不给负数",
		int(SB.finals_left(9999)) == 0, str(SB.finals_left(9999)))
	var bad: Dictionary = SB.parse_finals(true, 200,
		'{"ok":true,"n":4,"round":1,"entrants":[],"done":{}}', "uid-me", 5000)
	_ok("③ 回包没带时间 ⇒ left = -1(不显示倒计时, 不瞎猜)",
		int(bad.get("left", -9)) == -1, str(bad.get("left")))
	SB.finals_clear()
	_ok("③ ★分母: 缓存清了 ⇒ finals_left 返回 -1", int(SB.finals_left(5000)) == -1)


# ─────────────────────────────────────────────────────────────
# ④ ★走真入口, 量真实发出去的请求
# ─────────────────────────────────────────────────────────────
func _t_real_request() -> void:
	print("── ④ 真请求(不数我插的计数器) ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB.finals_clear()
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_email = "me@x.co"
	GameState.account_id = "uid-me"

	_next = {"ok": true, "code": 200, "body": _body(2, {"1-0": 1})}
	_reqs.clear()
	SB.fetch_finals_async(1789344000, -1)
	await get_tree().process_frame
	_ok("④ ★分母: 真的发出去了一个请求", _reqs.size() == 1, str(_reqs.size()))
	var r: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_ok("④ ★★打的是服务端函数 finals_view, **不是直接读表**(表上没给直接读的策略)",
		str(r.get("url", "")).ends_with("/rest/v1/rpc/finals_view"), str(r.get("url")))
	_ok("④ 方法是 POST", str(r.get("method", "")) == "POST", str(r.get("method")))
	_ok("④ ★带的是「我那个桶」(p_bucket = -1) —— 客户端不知道自己被分到哪个桶",
		str(r.get("body", "")).find('"p_bucket":-1') >= 0, str(r.get("body")).substr(0, 120))
	_ok("④ ★周号是本周的周一锚点", str(r.get("body", "")).find("1789344000") >= 0,
		str(r.get("body")).substr(0, 120))
	_ok("④ ★★回包进了缓存(这才叫「这条路通了」)",
		int(SB.finals_cached().get("size", 0)) == 4
			and int(SB.finals_cached().get("me", -1)) == 1, str(SB.finals_cached()).substr(0, 140))

	## ★匿名号一个请求都不发(与存档同步同一条承诺)
	SB.finals_clear()
	GameState.account_email = ""
	_reqs.clear()
	SB.fetch_finals_async(1789344000, -1)
	await get_tree().process_frame
	## ★★判据翻了向(2026-09-24): 原来钉的是「匿名号一个请求都不发」——
	##   那条行为本身是错的(用户拍板「guest 应该也能打周六周日」),
	##   **不改判据这个修复根本上不去**(memory `fb-gate-can-pin-the-bug-in-place`)。
	## ★翻的时候更紧不更松: **一对**判据 ——
	##   访客(有服务端身份、没绑邮箱) ⇒ 发; 完全没身份 ⇒ 不发。
	##   只写前一条的话「什么身份都往外发」也会绿。
	_ok("④ ★★访客(没绑邮箱但有服务端身份) ⇒ **照样读桶**", _reqs.size() == 1,
		str(_reqs.size()))
	## 完全没身份: 连匿名号都还没建出来
	SB._reset_auth_for_test()
	GameState.account_id = ""
	_reqs.clear()
	SB.finals_clear()
	SB._enter_inflight = false
	SB.fetch_finals_async(1789344000, -1)
	await get_tree().process_frame
	_ok("④ ★分母: 完全没身份(没 account_id / 没 token) ⇒ 一个请求都不发",
		_reqs.is_empty(), str(_reqs.size()))
	## ★量完就把登录装回去 —— 后面还有判据要用它
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_id = "uid-me"
	GameState.account_email = "me@x.co"

	## 服务端说没报名 ⇒ 缓存留空, 不画半张图
	SB.finals_clear()
	_next = {"ok": true, "code": 200, "body": '{"ok":false,"reason":"not_entered"}'}
	_reqs.clear()
	SB.fetch_finals_async(1789344000, -1)
	await get_tree().process_frame
	_ok("④ ★分母: 这一次也真发了", _reqs.size() == 1, str(_reqs.size()))
	_ok("④ ★没报名 ⇒ 缓存是空的(屏幕上说人话, 不画半张图)",
		SB.finals_cached().is_empty(), str(SB.finals_cached()).substr(0, 120))
	SB.finals_clear()

	## ══════════════════════════════════════════════════════════════════
	## ④b ★★★「有资格但人不够」不许和「没资格」说同一句话
	##
	## `finals_seat` 对 1 个人**故意不建桶**(一人一桶 = 没有对手的冠军, 那不是比赛),
	## 于是那个**确实周六 4 胜晋级**的人在 `finals_pending` 里有行、`finals_entrants`
	## 里没有 ⇒ 服务端原来一律回 `not_entered` ⇒ 屏幕照它说
	## 「周六闯关赛晋级才进得来」——**在告诉他一件假事**, 他会以为胜场没算。
	##
	## ★10 个人规模下这不是边角: 周六晋级率约 34%(6 场配额 / 4 胜进 / 3 负出)
	##   ⇒ 只有 0~1 人晋级的概率约 **10%**。
	##
	## ★判据配一条**分母**: 同一条路上「没资格」仍必须回空字典 ——
	##   不然把两种情况又合成一种(反方向的同一个 bug)也会绿。
	## ══════════════════════════════════════════════════════════════════
	_next = {"ok": true, "code": 200,
		"body": '{"ok":false,"reason":"too_few","entered":1}'}
	_reqs.clear()
	SB.fetch_finals_async(1789344000, -1)
	await get_tree().process_frame
	var vf: Dictionary = SB.finals_cached()
	_ok("④b ★分母: 这一次也真发了请求", _reqs.size() == 1, str(_reqs.size()))
	_ok("④b ★★人不够那条**带出来了**(不是和「没资格」一样吞成空字典)",
		str(vf.get("reason", "")) == "too_few" and int(vf.get("entered", -1)) == 1,
		str(vf).substr(0, 120))
	_ok("④b ★不带 size 键 ⇒ 画图那侧读到的仍是 0(不许因此画半张图)",
		int(vf.get("size", 0)) == 0, str(vf.get("size", "缺")))
	## ★★走真场景的那个函数, 量**屏幕上真会出现的那句话**
	var m2 = MAP.new()
	add_child(m2)
	await get_tree().process_frame
	var txt := str(m2._empty_text())
	_ok("④b ★★★屏幕上说的是人话: 要承认他晋级了, 且**不许**再说「晋级才进得来」",
		txt.contains("晋级算数") and not txt.contains("晋级才进得来"), txt)
	_ok("④b ★而且把人数说出来(「只有 1 人」比「人太少」有用)", txt.contains("1 人"), txt)
	m2.queue_free()
	await get_tree().process_frame
	SB.finals_clear()

	## ══════════════════════════════════════════════════════════════════
	## ④c ★★★周六晋级了但那一刻**没报上去** ⇒ 下次开主菜单要补报
	##
	## `report_finals_entry()` 在**第 4 胜那一刻**调, 而 `enter_finals` 原来是
	## **发了就不管**(回调空): 那一刻没网 / token 刚过期 / 玩家顺手杀了 App,
	## 就静默漏报 ⇒ 周日进不去, 而屏幕说他「晋级才进得来」——他明明打到了 4 胜,
	## 而且**没有任何自救办法**。10 个人测一周撞上一个很正常。
	##
	## ★判据落在 `Backend.ensure_finals_entry()` 这个**产品自己的入口**上,
	##   量的是「它到底发不发那条请求」(注入传输能看见真实发出的 URL),
	##   不是「我插的标记有没有被置位」。
	## ★三条分母都配上: 少任何一条, 这条判据就会变成"每次开主菜单都往服务端捶一下"
	##   也全绿 —— 那是另一种 bug(白流量 + 服务端被刷)。
	## ══════════════════════════════════════════════════════════════════
	print("── ④c 周六晋级但漏报 ⇒ 补报 ──")
	var kp_gw: int = int(GameState.gauntlet_wins)
	var kp_gl: int = int(GameState.gauntlet_losses)
	var kp_ew: int = int(GameState.finals_entered_week)
	var kp_wk: int = int(GameState.week_anchor_ts)
	var WK4: int = 1789948800

	GameState.week_anchor_ts = WK4
	GameState.gauntlet_wins = P2C.GAUNTLET_WINS_IN      # 4 胜 = 晋级
	GameState.gauntlet_losses = 0
	GameState.finals_entered_week = 0                   # 还没报上
	_ok("④c ★分母: 本地战绩确实是「晋级」(否则下面全是空检查)",
		str(GameState.gauntlet_state()) == "in", str(GameState.gauntlet_state()))
	_ok("④c ★分母: 这一周确实还没确认报成", not SB.finals_entered(WK4))
	_reqs.clear()
	SB._enter_inflight = false
	BK.ensure_finals_entry()
	await get_tree().process_frame
	var ent := _rpc_calls("finals_enter")
	_ok("④c ★★★漏报了 ⇒ 真的补发了一条 finals_enter", ent.size() == 1,
		"发了 %d 条: %s" % [ent.size(), str(ent).substr(0, 110)])

	## ★分母一: 已经确认报成了 ⇒ **一个字都不许再发**(不然每次开主菜单都捶一下服务端)
	GameState.finals_entered_week = WK4
	_reqs.clear()
	SB._enter_inflight = false
	BK.ensure_finals_entry()
	await get_tree().process_frame
	_ok("④c ★★已经报成过 ⇒ 不再发(否则每次开主菜单都白捶一次服务端)",
		_rpc_calls("finals_enter").is_empty(), str(_rpc_calls("finals_enter").size()))

	## ★分母二: 还在打(没晋级) ⇒ 不许报
	GameState.finals_entered_week = 0
	GameState.gauntlet_wins = 1
	_reqs.clear()
	SB._enter_inflight = false
	BK.ensure_finals_entry()
	await get_tree().process_frame
	_ok("④c ★★还在打(1 胜) ⇒ 不许报(报了就是把没晋级的人塞进决赛日)",
		_rpc_calls("finals_enter").is_empty(), str(_rpc_calls("finals_enter").size()))

	## ★分母三: 赛季没初始化(周锚点 0) ⇒ 不许报
	GameState.gauntlet_wins = P2C.GAUNTLET_WINS_IN
	GameState.week_anchor_ts = 0
	_reqs.clear()
	SB._enter_inflight = false
	BK.ensure_finals_entry()
	await get_tree().process_frame
	_ok("④c ★赛季没初始化(周锚点=0) ⇒ 不许报(报了记不清是哪一周)",
		_rpc_calls("finals_enter").is_empty(), str(_rpc_calls("finals_enter").size()))

	## ★★回包解析: 只有 `{"ok":true}` 算报成。`already_seated` 是「桶已经切了而我不在里面」
	##   ⇒ 补报也进不去了, **不许**把标记写成成功(否则下次连重试都不会有)。
	_ok("④c ★★ok:true ⇒ 算报成", SB.finals_enter_ok(true, 200, '{"ok":true}'))
	_ok("④c ★★already_seated ⇒ **不算**报成(还留着重试的机会)",
		not SB.finals_enter_ok(true, 200, '{"ok":false,"reason":"already_seated"}'))
	_ok("④c ★网络失败(code 0) ⇒ 不算报成", not SB.finals_enter_ok(false, 0, ""))
	_ok("④c ★坏正文(5xx 回 HTML) ⇒ 不算报成", not SB.finals_enter_ok(true, 200, "<html>502</html>"))

	GameState.gauntlet_wins = kp_gw
	GameState.gauntlet_losses = kp_gl
	GameState.finals_entered_week = kp_ew
	GameState.week_anchor_ts = kp_wk
	SB.finals_clear()


# ─────────────────────────────────────────────────────────────
# ⑥ ★★没数据的时候这一屏说什么(实拍抓出来的一整类)
# ─────────────────────────────────────────────────────────────
func _t_empty() -> void:
	print("── ⑥ 没数据时 ──")
	OS.set_environment("TURTLE_SUPABASE", " ")      # 后端没配 = 这一屏拿不到数据
	SB.finals_clear()
	_ok("⑥ ★分母: 一开始「还没问过」", not SB.finals_tried())

	var m = MAP.new()
	add_child(m)
	await get_tree().process_frame
	## ★★开屏就得画一次 —— 实拍抓到: 不画的话整屏空白,
	##   「回到我」停在默认的 (0,0) 压住返回箭头, 页签后缀也没同步。
	_ok("⑥ ★★没数据也画了空状态那行字(不是一片空白)",
		m._empty_lb != null and m._empty_lb.visible, str(m._empty_lb != null))
	_ok("⑥ ★★「回到我」在没数据时不可见(否则它停在 (0,0) 压住返回箭头)",
		m._home_btn != null and not m._home_btn.visible,
		"visible=%s pos=%s" % [m._home_btn.visible, str(m._home_btn.position)])
	_ok("⑥ ★页签后缀同步了(「我的桶 ·无」而不是光秃秃的「我的桶」)",
		str((m._tabs.get_child(0) as Button).text).find("·") >= 0,
		str((m._tabs.get_child(0) as Button).text))

	## ★★「还没问到回音」与「问到了但我没桶」要说不同的话 ——
	##   混成一句的话, 网络慢的人会以为自己没进决赛日。
	##   而 `finals_tried` 必须在**每一条早退路径**上都标: 实拍抓到没配后端那条没标,
	##   屏幕就永远转着「正在连线」(这是「状态位只在顺利那条路上写」的老毛病)。
	var txt_done := str(m._empty_text())
	_ok("⑥ ★分母: 后端没配 ⇒ 已经「问过了」(早退路径也得标, 否则永远转圈)",
		SB.finals_tried())
	_ok("⑥ ★问过了 ⇒ 说「本周没有你的桶」", txt_done.find("没有你的桶") >= 0, txt_done)
	SB.finals_clear()
	var txt_wait := str(m._empty_text())
	_ok("⑥ ★还没问过 ⇒ 说「正在连线」", txt_wait.find("正在连线") >= 0, txt_wait)
	_ok("⑥ ★★两句**真的不一样**(否则上面两条里必有一条恒真)", txt_wait != txt_done,
		"%s | %s" % [txt_wait, txt_done])
	m.queue_free()
	SB.finals_clear()


# ─────────────────────────────────────────────────────────────
# ⑦ ★★报到: 只在【这一场把我打成晋级】时报, 而且报的是真请求
# ─────────────────────────────────────────────────────────────
func _t_enter() -> void:
	print("── ⑦ 决赛日报到 ──")
	## 组包那半是纯函数
	var body: Dictionary = SB.finals_enter_body(123, "龟主-ab12", {"pets": [1, 2]}, 6, 1)
	_ok("⑦ 组包: 五个参数都在且键名与服务端对得上",
		body.get("p_week") == 123 and str(body.get("p_name")) == "龟主-ab12"
			and int(body.get("p_gw", -1)) == 6 and int(body.get("p_gl", -1)) == 1
			and (body.get("p_snapshot", {}) as Dictionary).has("pets"), str(body).substr(0, 140))

	## ★★走真入口, 量真实发出去的请求
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_email = "me@x.co"
	GameState.account_id = "uid-me-1234"
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	_next = {"ok": true, "code": 200, "body": '{"ok":true}'}

	## 还在打(1 胜 0 负) ⇒ 不该报
	GameState.gauntlet_wins = 1
	GameState.gauntlet_losses = 0
	_reqs.clear()
	SB._enter_inflight = false
	BK.report_finals_entry()
	await get_tree().process_frame
	_ok("⑦ ★还在打(1胜0负) ⇒ 一个请求都不发", _reqs.is_empty(), str(_reqs.size()))

	## 出局(0 胜 3 负) ⇒ 不该报
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 3
	_reqs.clear()
	SB._enter_inflight = false
	BK.report_finals_entry()
	await get_tree().process_frame
	_ok("⑦ ★出局(0胜3负) ⇒ 一个请求都不发", _reqs.is_empty(), str(_reqs.size()))

	## 晋级 ⇒ 该报
	GameState.gauntlet_wins = 4
	GameState.gauntlet_losses = 1
	GameState.week_anchor_ts = 1789344000
	_reqs.clear()
	SB._enter_inflight = false
	BK.report_finals_entry()
	await get_tree().process_frame
	_ok("⑦ ★★分母: 晋级(4胜1负) ⇒ 真的发出去了(证明上面两条是「状态」挡的)",
		_reqs.size() == 1, str(_reqs.size()))
	var r: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_ok("⑦ ★★打的是服务端函数 finals_enter(不是直接写表 —— 表上没给写的策略)",
		str(r.get("url", "")).ends_with("/rest/v1/rpc/finals_enter"), str(r.get("url")))
	_ok("⑦ ★带的战绩是**这一场之后**的(4胜1负) —— 服务端按它定种子",
		str(r.get("body", "")).find('"p_gw":4') >= 0
			and str(r.get("body", "")).find('"p_gl":1') >= 0, str(r.get("body")).substr(0, 160))
	_ok("⑦ ★周号是本周的周一锚点", str(r.get("body", "")).find("1789344000") >= 0,
		str(r.get("body")).substr(0, 160))
	_ok("⑦ ★阵容快照带上了(周日代打要用)",
		str(r.get("body", "")).find("p_snapshot") >= 0
			and str(r.get("body", "")).length() > 120, "%d 字节" % str(r.get("body", "")).length())

	## 名字: 两个号必须不一样 —— 一桶 32 个同名的对阵图没法看
	var n1 := str(BK.player_display_name())
	GameState.account_id = "uid-other-9999"
	var n2 := str(BK.player_display_name())
	GameState.account_id = "uid-me-1234"
	_ok("⑦ ★★两个号的显示名不一样(否则对阵图上全是同一个名字)", n1 != n2, "%s vs %s" % [n1, n2])
	_ok("⑦ ★分母: 名字不是空的", n1.length() >= 3 and n2.length() >= 3, "%s / %s" % [n1, n2])
	## ★★登记缺口: 这**不是**真昵称, 是账号短码凑的
	_ok("⑦ ★登记缺口: 项目还没有「玩家昵称」⇒ 现在用的是账号短码(见 backend.player_display_name)",
		n1.begins_with("龟主-"), n1)

	## 匿名号不发(与存档同步同一条承诺)
	GameState.account_email = ""
	_reqs.clear()
	SB._enter_inflight = false
	BK.report_finals_entry()
	await get_tree().process_frame
	## ★★判据翻了向(2026-09-24): 原来钉的是「匿名号一个请求都不发」——
	##   那条行为本身是错的(用户拍板「guest 应该也能打周六周日」),
	##   **不改判据这个修复根本上不去**(memory `fb-gate-can-pin-the-bug-in-place`)。
	## ★翻的时候更紧不更松: **一对**判据 ——
	##   访客(有服务端身份、没绑邮箱) ⇒ 发; 完全没身份 ⇒ 不发。
	##   只写前一条的话「什么身份都往外发」也会绿。
	_ok("⑦ ★★访客(没绑邮箱但有服务端身份) ⇒ **照样报名**", _reqs.size() == 1,
		str(_reqs.size()))
	## 完全没身份: 连匿名号都还没建出来
	SB._reset_auth_for_test()
	GameState.account_id = ""
	_reqs.clear()
	SB.finals_clear()
	SB._enter_inflight = false
	BK.report_finals_entry()
	await get_tree().process_frame
	_ok("⑦ ★分母: 完全没身份(没 account_id / 没 token) ⇒ 一个请求都不发",
		_reqs.is_empty(), str(_reqs.size()))
	## ★量完就把登录装回去 —— 后面还有判据要用它
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_id = "uid-me"
	GameState.account_email = "me@x.co"
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")


# ─────────────────────────────────────────────────────────────
# ⑤ ★★门: 两个方向都验
# ─────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────
# ⑧ 对手快照 (E-B4, 2026-09-25)
#
# 背景: 快照一直写在 `finals_entrants.snapshot`, 但**没有任何人读得回来**
#   (`finals_view` 不下发) ⇒ 不在线的对手没法代打 ⇒ 那场没人报 ⇒ 桶永久卡死。
#
# ★这一节守两半, 缺一不可:
#   ①【翻译】纯函数喂回包 —— 不用网络就能穷举各种 reason
#   ②【发信】走真入口, 量**真实发出去的请求**(地址/正文), 不是我插的计数器
# ─────────────────────────────────────────────────────────────
func _t_opponent() -> void:
	print("── ⑧ 对手快照 ──")
	## ── ① 翻译那半 ──
	var good := SB.parse_opponent(true, 200,
		'{"ok":true,"seed":3,"name":"阿海","snapshot":{"pets":[1,2,3]}}')
	_ok("⑧ 正路: 快照/种子/名字都翻出来了",
		bool(good.get("ok")) and int(good.get("seed", -1)) == 3
			and str(good.get("name")) == "阿海"
			and (good.get("snapshot", {}) as Dictionary).has("pets"), str(good).substr(0, 140))

	## ★★空快照当成**拿不到**, 不是「拿到一个空阵容」——
	##   后者会让代打打一场 0 人对局, 而且看起来像"对手太弱"
	var empty := SB.parse_opponent(true, 200, '{"ok":true,"seed":3,"name":"x","snapshot":{}}')
	_ok("⑧ ★★空快照算**拿不到**(不然会打一场 0 人对局, 还看着像对手太弱)",
		not bool(empty.get("ok")) and str(empty.get("reason")) == "empty_snapshot",
		str(empty).substr(0, 120))

	## 被拒: reason 要原样带出来 —— 屏幕按它说不同的话
	var used := SB.parse_opponent(true, 200, '{"ok":false,"reason":"already_asked","seed":5}')
	_ok("⑧ 被拒时把 reason 带出来(屏幕要按它说不同的话)",
		not bool(used.get("ok")) and str(used.get("reason")) == "already_asked", str(used))
	_ok("⑧ ★★还要带出「我这一轮实际问过谁」—— 能和本机算出的对手对一下, 对不上就是两边对阵图不一致",
		int(used.get("asked", -1)) == 5, str(used))
	_ok("⑧ ★★被拒时**一个字节的快照都没有**", not used.has("snapshot"), str(used))

	var oob := SB.parse_opponent(true, 200, '{"ok":false,"reason":"not_in_bucket"}')
	_ok("⑧ not_in_bucket 照样翻得出", str(oob.get("reason")) == "not_in_bucket", str(oob))
	_ok("⑧ ★分母: 没有 seed 字段时不许凭空造一个 asked", not oob.has("asked"), str(oob))

	_ok("⑧ 网络层就失败 ⇒ reason=net", str(SB.parse_opponent(false, 0, "").get("reason")) == "net")
	_ok("⑧ HTTP 500 ⇒ 也算 net(不是把 500 的正文当结果解)",
		str(SB.parse_opponent(true, 500, '{"ok":true,"snapshot":{"pets":[1]}}').get("reason")) == "net")
	_ok("⑧ 正文不是 JSON ⇒ bad_body",
		str(SB.parse_opponent(true, 200, "不是json").get("reason")) == "bad_body")

	## ── ② 发信那半: 走真入口, 量真实请求 ──
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_id = "uid-me-1234"
	SB.opponent_clear()
	_next = {"ok": true, "code": 200,
		"body": '{"ok":true,"seed":7,"name":"乙","snapshot":{"pets":[9]}}'}
	_reqs.clear()
	SB._opp_inflight = false
	SB.fetch_opponent_async(777, 2, 3, 7)
	await get_tree().process_frame
	_ok("⑧ ★分母: 真入口确实发出了请求", _reqs.size() >= 1, str(_reqs.size()))
	var r0: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_ok("⑧ ★★发去的是 `/rest/v1/rpc/finals_opponent`",
		str(r0.get("url", "")).ends_with("/rest/v1/rpc/finals_opponent"), str(r0.get("url", "")))
	var sent = JSON.parse_string(str(r0.get("body", "{}")))
	_ok("⑧ ★★四个参数原样带上(week/bucket/round/seed) —— 少一个服务端就没法校验",
		sent is Dictionary and int(sent.get("p_week", -1)) == 777
			and int(sent.get("p_bucket", -1)) == 2 and int(sent.get("p_round", -1)) == 3
			and int(sent.get("p_seed", -1)) == 7, str(sent).substr(0, 140))
	_ok("⑧ 回包落进缓存, 屏幕拿得到",
		bool(SB.opponent_cached().get("ok")) and SB.opponent_tried(),
		str(SB.opponent_cached()).substr(0, 120))

	## ★★没登录就别白跑一趟, 但**要标成「问过了」**——
	##   否则屏幕永远转着「正在连线」(这个形状实拍抓到过一次)
	SB.opponent_clear()
	SB._reset_auth_for_test()          # token 没了
	GameState.account_id = "uid-me-1234"
	_reqs.clear()
	SB._opp_inflight = false
	SB.fetch_opponent_async(777, 2, 3, 7)
	await get_tree().process_frame
	_ok("⑧ ★没 token 时不发请求", _reqs.size() == 0, str(_reqs.size()))
	_ok("⑧ ★★但要标成「问过了」—— 不然屏幕永远转着「正在连线」", SB.opponent_tried())
	SB._transport_for_test = Callable()
	SB.opponent_clear()


# ─────────────────────────────────────────────────────────────
# ⑨ 报结果 (E-B6, 2026-09-25)
#
# ★`finals_report` 这个 RPC 从 2026-09-23 就在服务端, 而**客户端一个调用者都没有**
#   ⇒ 没有任何一场的结果能被报上去 ⇒ 对阵图永远停在第 1 轮。
# ★这一节守三件: 组包键名对不对 / 无效 side 不许发出去 / 同一场只报一次。
# ─────────────────────────────────────────────────────────────
func _t_report() -> void:
	print("── ⑨ 报结果 ──")
	var b: Dictionary = SB.finals_report_body(123, 2, 3, 1, 0, 42)
	_ok("⑨ 组包: 六个键名与服务端对得上",
		int(b.get("p_week", -1)) == 123 and int(b.get("p_bucket", -9)) == 2
			and int(b.get("p_round", -1)) == 3 and int(b.get("p_match", -1)) == 1
			and int(b.get("p_winner_side", -1)) == 0 and int(b.get("p_seed", -1)) == 42,
		str(b).substr(0, 150))

	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.account_id = "uid-me-1234"
	SB.finals_report_clear()
	_next = {"ok": true, "code": 200, "body": '{"ok":true}'}

	## ★★`winner_side = -1` 是 `winner_side_for()` 说的「我没资格报」——
	##   这一步就该拦住。能发出去就意味着"不是我的场"也能报。
	_reqs.clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 1, -1, 5)
	await get_tree().process_frame
	_ok("⑨ ★★★winner_side = -1(不是我的场) ⇒ **一个请求都不发**",
		_reqs.size() == 0, str(_reqs.size()))
	_ok("⑨ ★分母: 拦住了也不许把它记成「报过了」(否则真要报时会被自己挡住)",
		not SB.finals_reported(3, 1))

	## 正路
	_reqs.clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 1, 0, 42)
	await get_tree().process_frame
	_ok("⑨ ★分母: 正路确实发出了请求", _reqs.size() == 1, str(_reqs.size()))
	var r0: Dictionary = _reqs[0] if _reqs.size() > 0 else {}
	_ok("⑨ ★发去的是 `/rest/v1/rpc/finals_report`",
		str(r0.get("url", "")).ends_with("/rest/v1/rpc/finals_report"), str(r0.get("url", "")))
	var sent = JSON.parse_string(str(r0.get("body", "{}")))
	_ok("⑨ ★★报的 winner_side 原样送到(这个数反了不会报错, 只会静静送错人)",
		sent is Dictionary and int(sent.get("p_winner_side", -9)) == 0, str(sent).substr(0, 140))

	## ★★同一场只报一次 —— 结算路径会被重入(投降/重开结算屏)
	_reqs.clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 1, 0, 42)
	await get_tree().process_frame
	_ok("⑨ ★★★同一场再报一次 ⇒ 不发(结算路径会被重入, 没这道闸一场会报好几次)",
		_reqs.size() == 0, str(_reqs.size()))
	_ok("⑨ ★分母: **另一场**照样发得出去(上一条不是把所有请求都挡了)",
		true)
	_reqs.clear()
	SB._report_inflight = false
	SB.report_finals_async(777, 2, 3, 2, 1, 42)
	await get_tree().process_frame
	_ok("⑨ ★★分母(续): 换一场 m=2 确实发出去了", _reqs.size() == 1, str(_reqs.size()))

	SB._transport_for_test = Callable()
	SB.finals_report_clear()


# ─────────────────────────────────────────────────────────────
# ⑩ 打完真的把结果报上去 (E-B6, 走真入口 `_settle_season()`)
#
# ★★★这一节守的是整条链的**最后一环**: 前面全做完了, 这一环不通的话
#   对阵图**永远停在第 1 轮**, E-B4 的补判会把每一场都判给 side 0 ——
#   冠军是一个从没打过的人。
# ★判据落在**真实发出去的请求**(注入传输), 不是我插的计数器。
# ★★最要紧那条: **我输了要报对手那一侧**。这个数反了不会有任何报错,
#   它只会静静把对手送进下一轮。
# ─────────────────────────────────────────────────────────────
func _t_settle_reports() -> void:
	print("── ⑩ 打完把结果报上去(真入口 _settle_season) ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._transport_for_test = _spy
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200,
		'{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",'
		+ '"user":{"id":"uid-me","email":"me@x.co"}}')
	GameState.test_mode = true
	GameState.account_id = "uid-me-1234"
	GameState.account_email = "me@x.co"
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	## ★★★周锚点必须用**当前这一周**的: 原来写死 1700000000(2023 年) ⇒
	##   `ensure_season()` 看成「换轮了」⇒ 开新赛季 ⇒ **把 season_leaders 清掉** ⇒
	##   `_had_season=false` ⇒ `_settle_season` 在第二条 early return 就走了。
	##   症状是七条断言全红而**一条报错都没有** —— 探针打出 leaders=[] 才看清。
	GameState.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))
	_next = {"ok": true, "code": 200, "body": '{"ok":true}'}

	var scene = RB.new()
	add_child(scene)
	for _i in range(30):
		await get_tree().process_frame
	## ★★`season_leaders` 必须在**场景建好之后**再设: 战斗场那 30 帧的初始化里
	##   会把它清掉(探针打出来的: leaders=[] ⇒ `_had_season=false` ⇒
	##   `_settle_season` 在第二条 early return 就走了, 我那一行根本跑不到)。
	##   设在前面看着更顺, 但那是**被测对象还没到场**的另一种形状。
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	## ★★★周锚点必须用**当前这一周**的: 原来写死 1700000000(2023 年) ⇒
	##   `ensure_season()` 看成「换轮了」⇒ 开新赛季 ⇒ **把 season_leaders 清掉** ⇒
	##   `_had_season=false` ⇒ `_settle_season` 在第二条 early return 就走了。
	##   症状是七条断言全红而**一条报错都没有** —— 探针打出 leaders=[] 才看清。
	GameState.week_anchor_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system()))

	## ① 不是决赛场 ⇒ 一个字都不报
	GameState.finals_match = {}
	SB.finals_report_clear()
	_reqs.clear()
	scene._settle_season(true)
	await get_tree().process_frame
	var rep := _reports()
	_ok("⑩ ★★不是决赛场 ⇒ **一个 finals_report 都不发**", rep.size() == 0, str(rep.size()))

	## ② 决赛场 + 我在 side 0 + 赢了 ⇒ 报 0
	GameState.finals_match = {"bucket": 2, "round": 3, "match": 1, "side": 0}
	SB.finals_report_clear()
	SB._report_inflight = false
	_reqs.clear()
	scene._settle_season(true)
	await get_tree().process_frame
	rep = _reports()
	_ok("⑩ ★分母: 决赛场确实发出了 finals_report(否则下面全是空检查)",
		rep.size() == 1, str(rep.size()))
	var b0 = JSON.parse_string(str(rep[0].get("body", "{}"))) if rep.size() > 0 else {}
	_ok("⑩ side 0 的我赢了 ⇒ 报 0",
		b0 is Dictionary and int(b0.get("p_winner_side", -9)) == 0, str(b0).substr(0, 140))
	_ok("⑩ ★桶号/轮/场号原样送到(送错场等于替别人定胜负)",
		b0 is Dictionary and int(b0.get("p_bucket", -9)) == 2
			and int(b0.get("p_round", -9)) == 3 and int(b0.get("p_match", -9)) == 1,
		str(b0).substr(0, 140))
	_ok("⑩ ★★★报完**立刻清空** —— 不清的话下一场普通对局会被当成决赛再报一次",
		(GameState.finals_match as Dictionary).is_empty(), str(GameState.finals_match))

	## ③ ★★★决赛场 + 我在 side 0 + **输了** ⇒ 报 1(对手那一侧)
	GameState.finals_match = {"bucket": 2, "round": 3, "match": 5, "side": 0}
	SB.finals_report_clear()
	SB._report_inflight = false
	_reqs.clear()
	scene._settle_season(false)
	await get_tree().process_frame
	rep = _reports()
	var b1 = JSON.parse_string(str(rep[0].get("body", "{}"))) if rep.size() > 0 else {}
	_ok("⑩ ★★★side 0 的我**输了** ⇒ 报 1(对手那一侧) —— 反了不会报错, 只会静静送错人",
		b1 is Dictionary and int(b1.get("p_winner_side", -9)) == 1, str(b1).substr(0, 140))

	## ④ ★下半区也验: side 1 输了 ⇒ 报 0(只验一种的话整体反了也能绿)
	GameState.finals_match = {"bucket": 2, "round": 3, "match": 6, "side": 1}
	SB.finals_report_clear()
	SB._report_inflight = false
	_reqs.clear()
	scene._settle_season(false)
	await get_tree().process_frame
	rep = _reports()
	var b2 = JSON.parse_string(str(rep[0].get("body", "{}"))) if rep.size() > 0 else {}
	_ok("⑩ ★★下半区(side 1)输了 ⇒ 报 0 —— 只验上半的话整体反了也能绿",
		b2 is Dictionary and int(b2.get("p_winner_side", -9)) == 0, str(b2).substr(0, 140))

	## ⑤ side 非法(-1: 不是我的场) ⇒ 不报, 但照样清空
	GameState.finals_match = {"bucket": 2, "round": 3, "match": 7, "side": -1}
	SB.finals_report_clear()
	SB._report_inflight = false
	_reqs.clear()
	scene._settle_season(true)
	await get_tree().process_frame
	_ok("⑩ ★side = -1(不是我的场) ⇒ 不报", _reports().size() == 0, str(_reports().size()))
	_ok("⑩ ★★但**照样清空** —— 留着它下一场会被当成决赛",
		(GameState.finals_match as Dictionary).is_empty(), str(GameState.finals_match))

	scene.queue_free()
	await get_tree().process_frame
	SB._transport_for_test = Callable()
	SB.finals_report_clear()
	GameState.finals_match = {}


## 只挑 finals_report 那几条 —— 结算路径上还会发别的请求(上传快照等)。
## 发出去的请求里, 打到某个 RPC 的那几条。★照 `_reports()` 的形状 ——
## 判据量的是**真实发出的 URL**, 不是我插的计数器。
func _rpc_calls(rpc: String) -> Array:
	var out: Array = []
	for r in _reqs:
		if str((r as Dictionary).get("url", "")).ends_with("/rest/v1/rpc/" + rpc):
			out.append(r)
	return out


func _reports() -> Array:
	var out: Array = []
	for r in _reqs:
		if str((r as Dictionary).get("url", "")).ends_with("/rest/v1/rpc/finals_report"):
			out.append(r)
	return out


func _t_door() -> void:
	print("── ⑤ 门(桶地图在这之前零个产品调用点) ──")
	_ok("⑤ ★场景文件在(没有它 change_scene_to_file 没东西可切)",
		ResourceLoader.exists("res://scenes/BracketMap.tscn"))
	var sc = load("res://scenes/BracketMap.tscn")
	_ok("⑤ ★而且真能实例化出来", sc != null and sc.instantiate() != null)

	## ★★判定穷举。`PHASE_MODE_LIVE` 是 **const 字典**(Godot 里改不动) ⇒
	##   门禁没法"临时把决赛日打开再看一眼" ⇒ 判定抽成了 `close_block_kind()` 纯函数。
	##   不抽的话「上线那天只改一个常量」这句话只有到了那天才验证得了。
	var off := MENU.close_block_kind(P2C.PHASE_FINALS, false, false, -1, true)
	var on := MENU.close_block_kind(P2C.PHASE_FINALS, true, false, -1, true)
	print("     周日那一格: 玩法没上线 ⇒ %s / 上线了 ⇒ %s" % [off, on])
	_ok("⑤ ★★没上线 ⇒ 那一格是「玩法开发中」那句话, **不是门**", off == MENU.BK_PENDING, off)
	_ok("⑤ ★★上线了 ⇒ 那一格**变成门**", on == MENU.BK_BRACKET_DOOR, on)
	_ok("⑤ ★分母: 两个方向**真的不一样**(否则上面两条里必有一条恒真)", off != on,
		"%s vs %s" % [off, on])

	## ★维护态压过一切 —— 服务端说在维护时不该把人往决赛日送
	_ok("⑤ ★维护中压过门(上线了也先说维护)",
		MENU.close_block_kind(P2C.PHASE_FINALS, true, true, -1, true) == MENU.BK_MAINTENANCE)
	## ★门只长在决赛日: 别的阶段就算 finals_live=true 也不许冒出门来
	_ok("⑤ ★★门只长在周日: 积分赛那天即使 finals_live=true 也不是门",
		MENU.close_block_kind(P2C.PHASE_RANKED, true, false, 3600, true) == MENU.BK_COUNTDOWN)
	_ok("⑤ ★周一休赛: 玩法本来就没有 ⇒ 还是那句话",
		MENU.close_block_kind(P2C.PHASE_REST, true, false, -1, true) == MENU.BK_PENDING)
	_ok("⑤ 封盘窗口内 ⇒ 说已封盘",
		MENU.close_block_kind(P2C.PHASE_RANKED, false, false, 60, false) == MENU.BK_LOCKED)

	## ★★真场景一致性: 真开一遍主菜单, 那一格的**实际长相**必须跟纯判定一致。
	##   (只验纯函数 = 验我自己的判定表; 要证明产品真的按它走, 得看真控件)
	var sun := _sunday_ts()
	var real_kind := await _menu_block_kind(sun)
	var want: String = MENU.close_block_kind(P2C.phase_at_utc(sun),
		P2C.phase_mode_live(P2C.PHASE_FINALS), false, P2C.close_left_sec(sun),
		P2C.can_start_match_utc(sun))
	print("     真主菜单在周日建出来的是: %s / 判定说该是: %s" % [real_kind, want])
	_ok("⑤ ★★真主菜单建出来的那一格, 跟纯判定说的一致",
		(real_kind == "button") == (want == MENU.BK_BRACKET_DOOR),
		"%s vs %s" % [real_kind, want])
	_ok("⑤ ★分母: 今天这个开关下, 判定说的是「%s」" % want, want != "", want)

	## ★★按下去连的是谁: 量 `pressed` 那个连接的**方法名**。
	##   产品侧原来写的是匿名闭包 `func(): _go("BracketMap")`, 门禁就只看得到
	##   「有一个连接」 —— 我据此写过一条「有连接 且 文案含『对阵图』」的判据,
	##   那是在数我自己插的东西, 不是量需求。改成具名方法之后这一条才有内容。
	var wired := _door_method()
	_ok("⑤ ★★门按钮连的是 _open_bracket_map(具名方法, 不是匿名闭包)",
		wired == "_open_bracket_map", wired)
	_ok("⑤ ★★门的目标场景真的存在: res://scenes/%s.tscn" % MENU.BRACKET_SCENE,
		ResourceLoader.exists("res://scenes/%s.tscn" % MENU.BRACKET_SCENE),
		str(MENU.BRACKET_SCENE))

	## ★★★**登记一个门禁量不到的缺口**(不静默截断):
	##   「按下去之后场景真的换过去了」在无头门禁里量不到 ——
	##   `change_scene_to_file` 会把门禁自己的 current_scene 当场拆掉
	##   (memory `fb-gate-can-pin-the-bug-in-place`: 一个进程只能成功走一次)。
	##   这一步由实拍覆盖: `tests/shot_menu_to_bracket.gd`(周日时钟 + 真按一下 + 截图)。
	_ok("⑤ ★登记缺口: 「按下去真的换了场景」由实拍守, 不在本门禁内",
		FileAccess.file_exists("res://tests/shot_menu_to_bracket.gd"),
		"实拍脚本要在位, 否则这个缺口就是没人管")


## 找一个**周日**的 UTC 时刻(决赛日)。★不写死日期 —— 写死的过一周就指到别的阶段。
func _sunday_ts() -> int:
	var t := int(Time.get_unix_time_from_system())
	for i in range(8):
		var ts: int = t + i * 86400
		if P2C.phase_at_utc(ts) == P2C.PHASE_FINALS:
			return ts
	return t


## 真开一次主菜单, 问「周日那一格」建出来的是按钮还是标签。
func _menu_block_kind(sun: int) -> String:
	var menu = MENU.new()
	add_child(menu)
	await get_tree().process_frame
	var blk = menu._week_close_block(sun)
	var kind := "button" if (blk is Button) else "labels"
	menu.queue_free()
	return kind


## 门按钮 `pressed` 连的那个方法叫什么。★直接建那个控件(`_finals_entry`),
##   不经过 `_week_close_block` —— 后者要等决赛日玩法上线才会走到这一支,
##   而"接线对不对"跟"今天星期几"无关。
## ★不 emit: emit 会真的切场景, 把门禁自己的场景树拆掉。
func _door_method() -> String:
	var menu = MENU.new()
	add_child(menu)
	var blk = menu._finals_entry()
	var got := "<不是按钮>"
	if blk is Button:
		var cons: Array = (blk as Button).pressed.get_connections()
		got = "<没接>" if cons.is_empty() else str((cons[0]["callable"] as Callable).get_method())
	menu.queue_free()
	return got
