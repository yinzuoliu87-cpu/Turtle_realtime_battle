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
	_chk("② ★分母: 清档确实把进度清了(hearts 回到 8)", int(GameState.hearts) == 8,
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
	GameState.account_id = UID_OK
	_chk("③ ★分母: 这一层现在是启用的(否则下面是空检查)", SB.enabled())
	var b2: int = _tree.root.get_child_count()
	SB.ensure_signed_in_async()
	_chk("③ ★★已有 account_id ⇒ 不重复建号(每次开游戏建一个会把服务端刷爆)",
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


func _n_labels(n: Node) -> int:
	var k := 1 if n is Label else 0
	for c in n.get_children():
		k += _n_labels(c)
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
const WARN := "找不回来"
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
	_chk("④ ★★匿名态: 屏幕上说清楚了【账号】找不回来", _find_text(s1, WARN))
	var lied1 := []
	for p in FALSE_PROMISE:
		if _find_text(s1, str(p)):
			lied1.append(str(p))
	_chk("④ ★★匿名态不许承诺「存档」能找回(服务端根本没存存档)",
		lied1.is_empty(), str(lied1))
	_chk("④ 匿名态: 也显示了账号前 8 位(报问题时能对上号)",
		_find_text(s1, UID_OK.substr(0, 8)), UID_OK.substr(0, 8))
	s1.queue_free()
	await get_tree().process_frame

	# ── 绑了邮箱 ⇒ 那行警告【不许】再出现(反向分母) ──
	GameState.account_email = "someone@example.com"
	var s2 = await _open_settings()
	_chk("④ ★★绑了邮箱之后【没有】那行警告(证明上面那条不是恒真式)",
		not _find_text(s2, WARN))
	var lied2 := []
	for p in FALSE_PROMISE:
		if _find_text(s2, str(p)):
			lied2.append(str(p))
	_chk("④ ★★绑定态也不许承诺「存档」能找回(原文案就是栽在这句上)",
		lied2.is_empty(), str(lied2))
	_chk("④ 绑了邮箱: 屏幕上显示的是邮箱", _find_text(s2, "someone@example.com"))
	s2.queue_free()
	await get_tree().process_frame

	# ── ⑤ 没配后端 ⇒ 整行不显示 ──
	print("── ⑤ 没配后端: 整行不显示(不是显示「离线」) ──")
	OS.set_environment("TURTLE_SUPABASE", " ")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "")
	GameState.account_email = ""
	_chk("⑤ ★分母: 这一层已停用", not SB.enabled())
	var s3 = await _open_settings()
	_chk("⑤ ★★没配后端: 屏幕上没有「账号：」这一行", not _find_text(s3, "账号："))
	_chk("⑤ 也没有那行丢档警告", not _find_text(s3, WARN))
	## ★分母: 设置页本身是好的(别把"页面没建起来"读成"没显示账号行")
	_chk("⑤ ★分母: 设置页仍然正常(能找到「重置所有存档」)", _find_text(s3, "重置所有存档"))
	s3.queue_free()
	await get_tree().process_frame
