extends Node
## verify_account.gd — D-3：匿名账号 + 换设备丢档的提示（2026-09-21）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## D3 拍板「匿名起步 + 补绑邮箱」：不强制注册就能玩，代价是**没绑邮箱换设备就丢档**。
## 方案书 D-3 明写这一点「要在 UI 上说清楚」——
## 不说清楚的话，玩家是在**不知情**的前提下承担这个代价。
##
## ★`account_id` 会进服务端 `ghosts` 的主键 `(account_id, season_week, battles)`。
##   少了「谁」这一维，两个人会在服务端**静默互相覆盖**
##   （memory `fb-id-without-owner-dimension`；A6/U11 补的是「第几场」，这次补「谁」）。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 登录回包解析**逐条喂**（用 2026-09-20 真发 curl 拿回来的形状）。
##     重点是失败分支：**不许编一个本地 id 顶上** —— 那会让「没登录成功」看起来像
##     「登录成功了」，而后果要等到上传被 RLS 拒掉才显形（隔了好几层）。
## ★② `account_id` 是**身份不是进度**：切大轮**不许**动它、清档**不许**清它。
##     ⚠ 这条特意不写成「切轮后 == 0」—— `week_anchor_ts` 就是被那种断言钉死的
##     （门禁把 bug 钉住了，见 memory `fb-gate-can-pin-the-bug-in-place`）。
##     先问这字段本来该干什么：计数类该归零，**身份类该原样不动**。
## ★③ 不重复建号：已经有 `account_id` 时 `ensure_signed_in_async()` 连节点都不建。
##     （Supabase 建项目时自己警告过匿名登录被刷会撑爆 MAU。）
## ★★④ **走真入口**：实例化真的 `Settings.tscn`，断言屏幕上真有那行警告。
##     只验纯函数的话，这一层完全可能是个「写了没人读」——
##     本项目 2026-09-20 一天修过三个同族的。
##     配**反向分母**：绑了邮箱之后那行警告**不许**出现，否则「找得到」是恒真式。
## ★⑤ 没配后端 ⇒ 整行不显示（不是显示"离线"）。与 D-1 三态同一条原则。

const SB := preload("res://scripts/net/supabase.gd")
const SETTINGS := preload("res://scenes/Settings.tscn")

## 2026-09-20 真发 `POST /auth/v1/signup` 拿回来的形状（uuid 与 token 已换成假值）
const BODY_OK := '{"access_token":"eyJhbGciOiJIUzI1NiJ9.fake.sig","token_type":"bearer","expires_in":3600,"user":{"id":"3220fbae-067e-4c96-bac5-acabfc467308","aud":"authenticated","role":"authenticated","email":"","is_anonymous":true}}'
const UID_OK := "3220fbae-067e-4c96-bac5-acabfc467308"

const KEYS := ["account_id", "account_email", "install_uid", "season_id", "hearts",
	"ranked_used", "week_anchor_ts", "season_start_ts"]

var _ok := 0
var _fail := 0
var _bak := {}
var _tree: SceneTree = null


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	_chk("★分母: test_mode 已置位(下面会写 GameState)", bool(GameState.test_mode))
	for k in KEYS:
		_bak[k] = GameState.get(k)

	print("=== D-3 账号 ===")
	_t_parse()
	_t_identity_not_progress()
	_t_no_duplicate_signup()
	await _t_real_settings()
	await _t_unwall()

	for k in KEYS:
		GameState.set(k, _bak[k])
	SB._reset_auth_for_test()
	_chk("★收尾: GameState 已还原", str(GameState.account_id) == str(_bak["account_id"]))

	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — D-3 账号" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 登录回包解析 —— 重点在失败分支不许编 id
# ─────────────────────────────────────────────────────────────
func _t_parse() -> void:
	print("── ① 登录回包解析 ──")
	var good := SB.account_from_auth_response(true, 200, BODY_OK)
	_chk("① 成功回包 → ok", bool(good["ok"]))
	_chk("① 取到 account_id", str(good["account_id"]) == UID_OK, str(good["account_id"]))
	_chk("① 认出这是匿名账号", bool(good["is_anonymous"]))
	_chk("① 取到 token", str(good["token"]) != "")

	## ★失败的五种形状, **一个都不许吐出非空 account_id**
	var bads := [
		["传输失败", SB.account_from_auth_response(false, 0, "")],
		["HTTP 422(匿名登录没开)", SB.account_from_auth_response(true, 422,
			'{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}')],
		["HTTP 401(key 不对)", SB.account_from_auth_response(true, 401, '{"message":"No API key found"}')],
		["网关返回 HTML", SB.account_from_auth_response(true, 200, "<html>502</html>")],
		["200 但没有 user.id", SB.account_from_auth_response(true, 200, '{"access_token":"x","user":{}}')],
	]
	var leaked := 0
	for b in bads:
		var r: Dictionary = b[1]
		var clean: bool = (not bool(r["ok"])) and str(r["account_id"]) == ""
		if not clean:
			leaked += 1
		_chk("① %s → ok=false 且 account_id 为空" % str(b[0]), clean, str(r))
	_chk("① ★★五种失败形状里一个都没编出 id(编了的话「没登录」会看起来像「登录了」)",
		leaked == 0, "违例 %d/5" % leaked)
	## ★分母: 成功与失败确实给出了不同答案
	_chk("① ★分母: 成功分支与失败分支答案不同",
		bool(good["ok"]) != bool((bads[0][1] as Dictionary)["ok"]))


# ─────────────────────────────────────────────────────────────
# ② 身份不是进度: 切大轮不动、清档不清
# ─────────────────────────────────────────────────────────────
func _t_identity_not_progress() -> void:
	print("── ② account_id 是身份, 不是本轮进度 ──")
	GameState.account_id = UID_OK
	GameState.account_email = "someone@example.com"
	GameState.ranked_used = 7            # ★对照组: 这个**该**被切轮清掉
	var sid := int(GameState.season_id)
	GameState.start_new_season()
	_chk("② ★分母: 对照组 ranked_used 确实被切轮清了(证明切轮真的执行了)",
		int(GameState.ranked_used) == 0, "ranked_used=%d" % int(GameState.ranked_used))
	_chk("② ★分母: 赛季号确实 +1", int(GameState.season_id) == sid + 1)
	_chk("② ★★切大轮【不动】account_id —— 换一轮赛季不换人",
		str(GameState.account_id) == UID_OK, "实得「%s」" % str(GameState.account_id))
	_chk("② ★★切大轮也不动 account_email",
		str(GameState.account_email) == "someone@example.com", str(GameState.account_email))

	## 清档: 清的是「这局游戏」不是「你是谁」
	GameState.account_id = UID_OK
	GameState.account_email = "someone@example.com"
	GameState.reset_save()
	_chk("② ★分母: 清档确实把进度清了(hearts 回到满命 %d)" % int(_P2C_ACC.HEARTS_MAX),
		int(GameState.hearts) == int(_P2C_ACC.HEARTS_MAX),
		"hearts=%d" % int(GameState.hearts))
	_chk("② ★★清档【保留】account_id —— 清掉的话服务器上那份数据就再也认不回来了",
		str(GameState.account_id) == UID_OK, "实得「%s」" % str(GameState.account_id))
	_chk("② ★★清档也保留 account_email",
		str(GameState.account_email) == "someone@example.com", str(GameState.account_email))


# ─────────────────────────────────────────────────────────────
# ③ 不重复建号
# ─────────────────────────────────────────────────────────────
func _t_no_duplicate_signup() -> void:
	print("── ③ 已有身份就不再建号 ──")
	## 门禁进程是 TURTLE_SUPABASE=" " ⇒ 整层停用, 先把这个前提断言出来
	_chk("③ ★分母: 本进程这一层是停用的", not SB.enabled(), "base_url=「%s」" % SB.base_url())
	var before: int = _tree.root.get_child_count()
	SB.ensure_signed_in_async()
	_chk("③ 停用时连节点都不建", _tree.root.get_child_count() == before,
		"%d → %d" % [before, _tree.root.get_child_count()])

	## 开启这一层, 且已经有 account_id ⇒ 仍然不许建节点
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	## ★★D-3c(2026-09-21)之后「不重复建号」的前提是【会话还有效】, 不再只是「有 account_id」。
	##   原来这里只设了 account_id —— 那正是 bug 的形状: 有号但没 token 时**就该**去续,
	##   而旧代码直接返回, 于是重开 App 后再也没有 token。
	##   旧写法在 D-3c 之后还能碰巧绿(② 留下了邮箱 ⇒ 判成「等重登」不建节点),
	##   碰巧绿不算数 ⇒ 这里先把一个【有效会话】落地, 再断言不建节点。
	SB._reset_auth_for_test()
	SB.apply_auth_response(true, 200, BODY_OK)     # expires_in 3600 ⇒ 远没到续期线
	GameState.account_id = UID_OK
	_chk("③ ★分母: 会话确实有效(有 token 且没到续期线)", SB.access_token() != ""
		and SB.token_expires_at() - int(Time.get_unix_time_from_system()) > SB.REFRESH_MARGIN_SEC)
	_chk("③ ★分母: 这一层现在是启用的(否则下面是空检查)", SB.enabled())
	var b2: int = _tree.root.get_child_count()
	SB.ensure_signed_in_async()
	_chk("③ ★★会话有效 ⇒ 不重复建号(每次开游戏建一个会把服务端刷爆)",
		_tree.root.get_child_count() == b2,
		"%d → %d" % [b2, _tree.root.get_child_count()])
	OS.set_environment("TURTLE_SUPABASE", " ")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "")


# ─────────────────────────────────────────────────────────────
# ④⑤ ★★走真入口: 设置页屏幕上真的有那行警告
# ─────────────────────────────────────────────────────────────
func _find_text(n: Node, needle: String) -> bool:
	if n is Label and str((n as Label).text).contains(needle):
		return true
	for c in n.get_children():
		if _find_text(c, needle):
			return true
	return false


## ★按钮是 `Button` 节点, `_find_text` 只找 Label —— v0.19.424 方案书里
##   「设置页有『用邮箱取回』入口, 由 ④ 走真入口验」那个勾打的时候,
##   ④ **一个按钮都没查过**(按我干了多少打勾, 不按有什么证据打勾)。
func _find_button(n: Node, needle: String) -> bool:
	if n is Button and str((n as Button).text).contains(needle):
		return true
	for c in n.get_children():
		if _find_button(c, needle):
			return true
	return false


func _n_buttons(n: Node) -> int:
	var k := 1 if n is Button else 0
	for c in n.get_children():
		k += _n_buttons(c)
	return k


func _n_labels(n: Node) -> int:
	var k := 1 if n is Label else 0
	for c in n.get_children():
		k += _n_labels(c)
	return k


## ★★2026-09-28 数【账号行那一族节点】有几个 —— ⑤ 的新尺子。
##
## 由来: ⑤ 守的需求是「没配后端 ⇒ **整行不显示**(不是显示"离线")」，
##   而它原来的实现是 `not _find_text(s3, "账号：")` —— **拿屏幕上的字面量当尺子**。
##   2026-09-28 设置屏去网页味时要拿掉那个冒号(`label: value` 是网页表单的读法)，
##   拿掉的同一刻这条断言就变成**恒真**：找不到是因为那个词没了，不是因为行没建。
##   ——「改了文案，判据静默变空检查」，与 memory
##     `fb-changing-a-param-meaning-makes-gates-tautological` 同一族：
##     类型没变、名字没变、编译器不拦，只有跑起来数分母才看得见。
##
## ⇒ 判据平移到**行为**：这一族节点到底在不在场景树上。文案以后随便改都不影响它。
## ★前缀**从产品那边 preload 取**，门禁不自己抄一份字符串
##   (memory `fb-hand-rolled-copies-drift`：抄一次就永远落后一次)。
const SETTINGS_SCRIPT := preload("res://scripts/scenes/SettingsScene.gd")

func _n_acct_row(n: Node) -> int:
	var k := 1 if str(n.name).begins_with(SETTINGS_SCRIPT.ACCT_ROW_PREFIX) else 0
	for c in n.get_children():
		k += _n_acct_row(c)
	return k


func _open_settings() -> Node:
	var s = SETTINGS.instantiate()
	add_child(s)
	var w := 0
	while w < 600 and not s.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(30):
		await get_tree().process_frame
	return s


## ★★2026-09-21 换判据。原来这里写死 `"换设备会丢失存档"`，
##   而那句话**是不准确的**：核实过服务端五张表
##   (`accounts` / `ghosts` / `matches` / `standings` / `service_status`)，
##   **没有一张存玩家存档** —— 龟等级/装备/深海币全在本机。
##   绑邮箱找回的是【账号(赛季身份)】，不是【存档】。
##   ⇒ 旧判据把一句**架构上做不到**的承诺【钉】在产品里了
##     (memory `fb-gate-can-pin-the-bug-in-place` 那一类)。
## ★改判据不是放松，是**更紧**：
##   ① 匿名态必须说清楚账号找不回来（`WARN`）
##   ② 绑定态不许再有那句（反向分母，证明 ① 不是恒真式）
##   ③ **任何状态下都不许**出现「丢失存档 / 取回存档」这种假承诺（`FALSE_PROMISE`）
const WARN := "无法恢复进度"
const FALSE_PROMISE := ["丢失存档", "取回存档", "找回存档"]


func _t_real_settings() -> void:
	print("── ④ 走真入口: 设置页真的说了「换设备会丢档」 ──")
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	_chk("④ ★分母: 这一层现在是启用的", SB.enabled())

	# ── 匿名(没绑邮箱) ⇒ 必须警告 ──
	GameState.account_id = UID_OK
	GameState.account_email = ""
	var s1 = await _open_settings()
	var n_lab: int = _n_labels(s1)
	_chk("④ ★分母: 设置页真的建出了 Label(N=0 的话下面是空检查)", n_lab > 0, "%d 个" % n_lab)
	## ★★⑤ 的分母(2026-09-28): ⑤ 要断言「后端关掉时这一行不在」, 那就必须先证明
	##   **后端开着时它真的在** —— 否则 ⑤ 那条「不在」是恒真的空检查。
	##   (memory `fb-judge-must-fit-the-shape` / `fb-gate-subject-never-constructed`:
	##    凡「X 不许出现」必须配一条「X 真的出现过」。)
	var n_row1: int = _n_acct_row(s1)
	_chk("④ ★★分母: 后端开着时账号行【真的建在树上】(⑤ 的「整行不显示」才有意义)",
		n_row1 >= 3, "%s* 节点 %d 个" % [SETTINGS_SCRIPT.ACCT_ROW_PREFIX, n_row1])
	_chk("④ ★★匿名态: 屏幕上说清楚了【账号】找不回来", _find_text(s1, WARN))
	var lied1 := []
	for p in FALSE_PROMISE:
		if _find_text(s1, str(p)):
			lied1.append(str(p))
	_chk("④ ★★匿名态不许承诺「存档」能找回(服务端根本没存存档)",
		lied1.is_empty(), str(lied1))
	_chk("④ 匿名态: 也显示了账号前 8 位(报问题时能对上号)",
		_find_text(s1, UID_OK.substr(0, 8)), UID_OK.substr(0, 8))
	_chk("④ ★分母: 设置页真的建出了按钮(N=0 的话下面两条是空检查)", _n_buttons(s1) > 0,
		"%d 个" % _n_buttons(s1))
	_chk("④ 匿名态: 有「绑定邮箱」按钮", _find_button(s1, "绑定邮箱"))
	## ★验证码位数是后台设置(实测 mailer_otp_length=8), 界面里写死位数就会漂 ——
	##   v0.19.423 就写成了「6 位」。扫整个设置页源码里有没有「N 位」这种字样。
	var src := FileAccess.get_file_as_string("res://scripts/scenes/SettingsScene.gd")
	var rx := RegEx.create_from_string("[0-9]+ ?位(数字|验证码)")
	_chk("④ ★界面文案里不写死验证码位数(后台是 8 位, 我曾写成 6 位)", rx.search(src) == null,
		rx.search(src).get_string() if rx.search(src) != null else "")
	_chk("④ ★★匿名态: 有「用邮箱取回」按钮(新手机上拿回旧号的唯一入口; v0.19.423 就漏了它)",
		_find_button(s1, "邮箱登录"))
	s1.queue_free()
	await get_tree().process_frame

	# ── 绑了邮箱 ⇒ 那行警告【不许】再出现(反向分母) ──
	GameState.account_email = "someone@example.com"
	var s2 = await _open_settings()
	_chk("④ ★★绑了邮箱之后【没有】那行警告(证明上面那条不是恒真式)",
		not _find_text(s2, WARN))
	## ★★D-8(2026-09-21)之后这条的事实变了: 绑了邮箱的号**会**同步进度
	##   (verify_save_sync ⑦ 用真请求证明了「绑定号推、匿名号不推」)⇒ 绑定态**该**说能取回进度。
	##   原来这里断言「绑定态不许承诺存档」—— 事实变了还留着它, 就是门禁把旧事实钉在产品里
	##   (memory `fb-gate-can-pin-the-bug-in-place`)。**匿名态那条禁令不动**: 匿名号仍然不同步。
	_chk("④ ★★绑定态说了能取回【进度】(D-8 之后这是真的, 由 verify_save_sync ⑦ 守着)",
		_find_text(s2, "登录恢复进度"))
	_chk("④ 绑了邮箱: 屏幕上显示的是邮箱", _find_text(s2, "someone@example.com"))
	_chk("④ 绑了邮箱: 按钮变成「换个邮箱」", _find_button(s2, "更换邮箱"))
	_chk("④ ★反向分母: 没有冲突时【不】出现「处理存档冲突」", not _find_button(s2, "处理存档冲突"))
	s2.queue_free()
	await get_tree().process_frame

	# ── D-8 存档冲突 ⇒ 提示 + 二选一入口 ──
	SB._reset_save_sync_for_test()
	SB.apply_push_response(true, 200, '{"ok": false, "reason": "conflict", "rev": 7}', "")
	_chk("④ ★分母: 冲突状态确实立起来了", SB.save_conflict())
	var s4 = await _open_settings()
	_chk("④ ★★存档冲突: 屏幕上说了「云端存档和这台设备的不一样」",
		_find_text(s4, "云端存档与本地存档不一致"))
	_chk("④ ★★存档冲突: 有「处理存档冲突」按钮(不然玩家永远卡在停推状态)",
		_find_button(s4, "处理存档冲突"))
	s4.queue_free()
	SB._reset_save_sync_for_test()
	await get_tree().process_frame

	# ── ⑤ 没配后端 ⇒ 整行不显示 ──
	print("── ⑤ 没配后端: 整行不显示(不是显示「离线」) ──")
	OS.set_environment("TURTLE_SUPABASE", " ")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "")
	GameState.account_email = ""
	_chk("⑤ ★分母: 这一层已停用", not SB.enabled())
	var s3 = await _open_settings()
	## ★★2026-09-28 换尺子: 原来是 `not _find_text(s3, "账号：")`。
	##   那是**拿屏幕上的字面量当判据** —— 设置屏去网页味时要拿掉那个冒号
	##   (`label: value` 是网页表单的读法), 拿掉的同一刻这条就静默变成恒真。
	##   现在量**行为**: 账号行那一族节点(`AcctRow*`)到底在不在树上。
	##   配套分母在 ④(后端开着时 ≥3 个) —— 两条合起来才卡得住「整行不显示」这个形状。
	var n_row3: int = _n_acct_row(s3)
	_chk("⑤ ★★没配后端: 账号行【整行没建出来】(量节点不量字面量, 文案改了判据不该变空检查)",
		n_row3 == 0, "%s* 节点 %d 个" % [SETTINGS_SCRIPT.ACCT_ROW_PREFIX, n_row3])
	## ★需求原话是「不显示(**不是显示"离线"**)」—— 那半句也要有人守:
	##   做成常驻的"在线/离线"角标是反的, 等于告诉玩家"你是残缺状态, 去修",
	##   而玩家多半修不了 ⇒ 制造焦虑但给不出行动(`remote_pool.gd` 头注同一条取舍)。
	_chk("⑤ ★也没有「离线」这种常驻角标(需求明确不要它, 不是漏做)", not _find_text(s3, "离线"))
	_chk("⑤ 也没有那行丢档警告", not _find_text(s3, WARN))
	## ★分母: 设置页本身是好的(别把"页面没建起来"读成"没显示账号行")
	_chk("⑤ ★分母: 设置页仍然正常(能找到「重置所有存档」)", _find_text(s3, "重置所有存档"))
	s3.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ⑥ ★★★WALL_SOFT: 拆墙之后, 绑过邮箱的老玩家行为一个字不变 (2026-09-29)
#
#    用户 2026-09-24「直接改为必须绑定账号吧」→ 2026-09-29「那就不用必须绑定吧」。
#    后一句在后 ⇒ 墙拆了（判据只有 `phase2_config.WALL_BLOCKS` 一处）。
#    拆墙带来两条**不许破**的规矩, 都在这一节量, 而且**都配反向分母**：
#      · 风险 3「绑过邮箱的老玩家不许受影响」—— 光断言「他没被打扰」是恒真式,
#        必须配一条「没绑的人**真的**变了」才证得出那条判据卡住了形状。
#      · 风险 4「`sync_allowed` 这条闸不许动」—— 拆的是**墙**, 不是「云存档要邮箱」。
#        动它会让匿名号去写别人的档（memory `fb-id-without-owner-dimension`）。
#
#    ★为什么在这份门禁里: 「谁是谁」「哪些功能匿名号就够」本来就是这一份守的事,
#      墙关不关得掉那一面在 `verify_login_wall`（那边 ⑧ 走真入口从第一屏走到一局）。
# ─────────────────────────────────────────────────────────────
const _P2C_ACC := preload("res://scripts/gamedata/phase2_config.gd")
## ★提示那一块的节点名从产品那边取, 不在测试里抄一份字(memory `fb-hand-rolled-copies-drift`)。
const _MM_ACC := preload("res://scripts/scenes/MainMenuScene.gd")
const MAINMENU := preload("res://scenes/MainMenu.tscn")


func _find_node_named(n: Node, nm: String) -> bool:
	if str(n.name) == nm:
		return true
	for c in n.get_children():
		if _find_node_named(c, nm):
			return true
	return false


func _t_unwall() -> void:
	print("── ⑥ WALL_SOFT: 绑过邮箱的老玩家一个字不变 ──")
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	_chk("⑥ ★分母: 这一层现在是启用的(关着的话整节是空检查)", SB.enabled())

	# ── ⑥a 纯函数: 拦谁 / 请谁 ──
	_chk("⑥a ★★绑过邮箱 ⇒ **不再请他绑**(老玩家不该再被提示)",
		not _P2C_ACC.bind_needed(true, "someone@example.com"))
	_chk("⑥a ★★分母: 而没绑的人**要请** —— 没有这一条, 上面那条是恒真式",
		_P2C_ACC.bind_needed(true, ""))
	_chk("⑥a ★★★WALL_SOFT: 谁都不许被**拦**(判据只有 `WALL_BLOCKS` 一处, 现在是 false)",
		(not _P2C_ACC.WALL_BLOCKS)
			and not _P2C_ACC.login_wall_on(true, "")
			and not _P2C_ACC.login_wall_on(true, "someone@example.com"),
		"WALL_BLOCKS=%s" % str(_P2C_ACC.WALL_BLOCKS))

	# ── ⑥b 真造一个【已绑账号】, 走真入口进设置页 ──
	## ★分母的意思: 拆墙之前绑过邮箱的人进设置页也是不弹绑定屏的 ⇒ 这一条要的是
	##   「**和从前一模一样**」, 不是「现在也不弹」。所以下面 ⑥c 再拿没绑的那一档作对照。
	GameState.account_id = UID_OK
	GameState.account_email = "someone@example.com"
	var s5 = await _open_settings()
	_chk("⑥b ★★★已绑账号进设置页: 绑定屏**不弹**(和拆墙之前一模一样)",
		s5._email_layer == null, str(s5._email_layer))
	_chk("⑥b ★分母: 而账号行照旧写着他的邮箱(页面真的建起来了)",
		_find_text(s5, "someone@example.com"))
	_chk("⑥b ★★已绑账号**看不到**那句「没备份」(那句话是给没绑的人的)",
		not _find_text(s5, str(_P2C_ACC.bind_nudge_text())),
		str(_P2C_ACC.bind_nudge_text()))
	_chk("⑥b ★分母: 按钮照旧是「换个邮箱」(绑定入口留着, 且没变成别的字)",
		_find_button(s5, "更换邮箱"))
	s5.queue_free()
	await get_tree().process_frame

	# ── ⑥c 主菜单那句非阻塞提示: 绑过的人没有 / 没绑的人有 ──
	## ★★这一对就是「老玩家一个字不变」的**真分母**: 只量绑过的人看不到它,
	##   那么把整块提示删掉也能绿。两档一起量才卡得住。
	## ★主菜单当**子节点**挂(不是 current_scene) ⇒ 首启教学与场景跳转都不触发,
	##   这一节只想看「那块提示建不建」。
	for case in [["someone@example.com", false], ["", true]]:
		GameState.account_email = str(case[0])
		var want: bool = bool(case[1])
		var mm = MAINMENU.instantiate()
		add_child(mm)
		for _i in range(8):
			await get_tree().process_frame
		var has: bool = _find_node_named(mm, str(_MM_ACC.NUDGE_NAME))
		_chk("⑥c %s ⇒ 主菜单上那句「没备份」提示 %s" % [
				("绑过邮箱" if want == false else "没绑邮箱"),
				("不该在" if want == false else "**该在**")],
			has == want, "实测 %s" % str(has))
		mm.queue_free()
		await get_tree().process_frame

	# ── ⑥d 风险 4: `sync_allowed` 一个字没动 ──
	## ★★★拆的是**墙**, 不是「云存档要邮箱」这条规则。动它 = 让匿名号去写别人的档。
	##   四格穷举: 三者齐才许, 缺一个就不许。
	_chk("⑥d ★★★绑定号(id + 邮箱 + token 三者齐) ⇒ 许同步",
		SB.sync_allowed(UID_OK, "someone@example.com", "tok"))
	_chk("⑥d ★★★而**匿名号**(邮箱为空)仍然**不许**同步 —— 这条闸一个字没动",
		not SB.sync_allowed(UID_OK, "", "tok"))
	_chk("⑥d ★没 token 不许", not SB.sync_allowed(UID_OK, "someone@example.com", ""))
	_chk("⑥d ★没 account_id 不许", not SB.sync_allowed("", "someone@example.com", "tok"))

	## 收尾: 把这一层关回去(与 ⑤ 留下的状态一致), 免得污染后面
	OS.set_environment("TURTLE_SUPABASE", " ")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "")
	_chk("⑥ ★收尾: 这一层已关回去", not SB.enabled())
