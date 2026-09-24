extends Node
## verify_login_wall.gd — 登录墙 (2026-09-24)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-09-24:「直接改为必须绑定账号吧」，在三个选项里选的是
## **开局就必须绑，没有 guest** —— 明确接受「没网 / 后端挂了就打不开」。
##
## 这道墙最容易出的两种错，各自成节：
##   ① **挡多了**：把「后端没配置」也挡住 ⇒ 384 条门禁当场全红、开发机打不开游戏。
##      「没配」是 dev 状态，不是玩家状态；「配了但连不上」才该挡。
##   ② **挡不住**：墙上留着「关闭」或返回键还能用 —— **关得掉的墙不是墙**。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 判定是纯函数 ⇒ **穷举** 后端配没配 × 绑没绑 四格，不靠起整个场景去试。
## ★② 「墙上没有关闭」不数源码，**真开一次墙、在节点树里数 Button**。
## ★③ 返回键：量它接的**方法名**（具名方法才量得到），再单独验那个方法在墙上不跳转。
## ★④ 每条都配分母：没墙时那些东西**必须在**，否则「墙上没有」是恒真式。
##
## 跑法: <godot> --headless --path . res://tests/verify_login_wall.tscn --quit-after 900

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const DEAD_URL := "http://127.0.0.1:9"

var _n := 0
var _fail := 0
const KEYS := ["account_email", "account_id", "nickname"]
var _bak := {}
## ★注入传输用: 记下**真实发出去的请求**(方法/地址/正文)。
## 照抄 `verify_session_refresh.gd` 的形状 —— 那是本仓验"发没发、发给谁"的标准写法。
var _reqs: Array = []


func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	## 回一个"连不上", 让产品侧照常走它的失败分支(我们只关心它发没发)
	cb.call({"ok": false, "code": 0, "body": ""})


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)
	print("=== 登录墙 ===")
	_t_rule()
	await _t_wall_ui()
	await _t_identity_under_wall()
	for k in KEYS:
		GameState.set(k, _bak[k])
	SB._transport_for_test = Callable()
	OS.set_environment("TURTLE_SUPABASE", " ")
	SB._reset_auth_for_test()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 登录墙" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 判定: 四格穷举
# ─────────────────────────────────────────────────────────────
func _t_rule() -> void:
	print("── ① 什么时候挡 ──")
	_ok("① ★★后端配了 + 没绑 ⇒ **挡**", P2C.login_wall_on(true, ""))
	_ok("① 后端配了 + 绑了 ⇒ 不挡", not P2C.login_wall_on(true, "me@x.co"))
	_ok("① ★★★后端**没配**(dev/门禁) ⇒ **不挡** —— 挡住的话 384 条门禁当场全红",
		not P2C.login_wall_on(false, ""))
	_ok("① 后端没配 + 绑了 ⇒ 不挡", not P2C.login_wall_on(false, "me@x.co"))
	## ★空白邮箱也算没绑 —— 存档里留一串空格不该当成绑过了
	_ok("① ★邮箱是空白 ⇒ 仍然挡", P2C.login_wall_on(true, "   "))
	## 文案: 墙上第一句要让老玩家别慌
	var body := str(P2C.login_wall_body())
	print("     墙上第一句: 「%s」" % body.split("\n")[0])
	_ok("① ★★墙上第一句先说【进度还在】—— 老玩家升级过来会被挡一次, 别让他以为丢了",
		body.find("进度还在") >= 0, body.substr(0, 40))
	_ok("① ★还告诉他收不到验证码怎么办(不然就是死路)",
		body.find("垃圾") >= 0 or body.find("重发") >= 0 or body.find("换一个") >= 0,
		body.substr(0, 60))


# ─────────────────────────────────────────────────────────────
# ② ★★真开一次墙: 关不掉、返回不了
# ─────────────────────────────────────────────────────────────
func _t_wall_ui() -> void:
	print("── ② 墙关不关得掉 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = "uid-wall"

	var st = SET.new()
	add_child(st)
	await get_tree().process_frame
	_ok("② ★分母: 后端算「配了」(否则下面全是空检查)", SB.enabled())
	_ok("② ★★墙真的开了(对话框在场)",
		st._email_layer != null and is_instance_valid(st._email_layer),
		str(st._email_layer))

	var btns := _buttons(st._email_layer)
	var labels: Array = []
	for b in btns:
		labels.append(str((b as Button).text))
	print("     墙上的按钮: %s" % str(labels))
	_ok("② ★★★墙上**没有「关闭」** —— 关得掉的墙不是墙",
		not labels.has("关闭"), str(labels))
	_ok("② ★分母: 墙上该有的按钮在(发验证码 / 确认)",
		labels.has("发验证码") and labels.has("确认"), str(labels))
	## ★★实拍拓出来的: 顶栏在更高的 CanvasLayer 上, 遮罩盖不住返回箭头 ⇒
	##   它看着能按、按下去却没反应。本仓原则:「点了没反应」比「按钮是灰的」糟得多。
	_ok("② ★★★墙上返回箭头**藏起来了**(而不是留着让人点了没反应)",
		st._top_bar != null and st._top_bar.back_btn != null
			and not st._top_bar.back_btn.visible,
		str(st._top_bar.back_btn.visible) if st._top_bar != null else "<no bar>")
	st.queue_free()
	await get_tree().process_frame

	## ★同一个对话框在**设置里主动绑定**时该有「关闭」—— 否则上面那条是恒真式
	GameState.account_email = "me@x.co"          # 绑过了 ⇒ 不开墙
	var st2 = SET.new()
	add_child(st2)
	await get_tree().process_frame
	_ok("② ★分母: 绑过了就不开墙", st2._email_layer == null, str(st2._email_layer))
	st2._open_email_dialog(SB.FLOW_BIND)          # 主动打开(可关闭那一档)
	await get_tree().process_frame
	var labels2: Array = []
	for b in _buttons(st2._email_layer):
		labels2.append(str((b as Button).text))
	_ok("② ★★分母: **主动**打开时「关闭」在 —— 证明上面那条是「墙」挡的, 不是对话框本来就没有",
		labels2.has("关闭"), str(labels2))

	_ok("② ★返回键接的是具名方法 `_on_back`(匿名闭包门禁量不到)",
		st2.has_method("_on_back"))
	_ok("② ★分母: 没墙时返回箭头**看得见**(否则下面那条是恒真)",
		st2._top_bar != null and st2._top_bar.back_btn != null
			and st2._top_bar.back_btn.visible,
		str(st2._top_bar.back_btn.visible) if st2._top_bar != null else "<no bar>")
	st2.queue_free()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ③ ★★被墙挡住的人, 还拿不拿得到服务端身份
#
#    v0.19.440 上墙之后出的真 bug(2026-09-24 实测): 主菜单 `_ready` 里
#    `ensure_signed_in_async()` 排在墙的 `return` **后面** ⇒ 全新安装永远没有 token
#    ⇒ 点「发验证码」撞上 FLOW_BIND 的 `_token != ""` 前置条件 ⇒ 回「先联网开一局再绑」
#    ⇒ **而墙正好不让他开局**。唯一兜底是 GameState 那个第一次要等 20 秒的保活 tick。
#
#    这一节守两件事, 缺一不可:
#      ①「墙触发了, 身份照样在建」—— 真走主菜单入口量, 不看源码顺序
#         (源码顺序是我改的东西, 拿它当判据等于自己数自己)
#      ②「提示不许教玩家去做墙不让他做的事」—— 量**函数真的吐出来的那句话**
# ─────────────────────────────────────────────────────────────
func _t_identity_under_wall() -> void:
	print("── ③ 被墙挡住时, 身份还建不建 ──")
	OS.set_environment("TURTLE_SUPABASE", DEAD_URL)
	SB._reset_auth_for_test()
	GameState.account_email = ""
	GameState.account_id = ""

	## ── ②先验文案: 没有 token 时点「发验证码」, 玩家看到什么 ──
	_ok("③ ★分母: 复位之后确实没有 token(否则下面走不到那一支)", SB._token == "")
	SB.send_code_async("newplayer@example.com", SB.FLOW_BIND)
	var msg := str(SB._email_msg)
	print("     玩家看到: 「%s」" % msg)
	_ok("③ ★分母: 确实走到了「没有 token」那一支(state=err 且有话说)",
		SB._email_state == SB.EM_ERR and msg != "", "%s / %s" % [SB._email_state, msg])
	_ok("③ ★★★提示不许教玩家「先开一局」—— 墙就是开局前那一屏, 他做不到",
		msg.find("开一局") < 0, msg)
	_ok("③ ★提示要说清现在在干嘛 + 怎么办(不然玩家只知道失败了)",
		msg.find("再点") >= 0 or msg.find("重试") >= 0 or msg.find("再试") >= 0, msg)
	## 验码那一侧同一句话的另一份拷贝(`bind_accepts`), 一起守 —— 两处各写一份必然漂
	var br: Dictionary = SB.bind_accepts({"ok": true, "account_id": "a"}, "")
	_ok("③ ★分母: `bind_accepts` 确实走到「本机没账号」那一支",
		not bool(br.get("ok", true)) and str(br.get("reason", "")) != "", str(br))
	_ok("③ ★★`bind_accepts` 的同一句话也不许说「开一局」",
		str(br.get("reason", "")).find("开一局") < 0, str(br.get("reason", "")))

	## ── ①再验真入口: 走一次真实开机, 看墙触发之后身份有没有在建 ──
	## ★★★判据换过一次(2026-09-24 CI 当场红): 原来量的是 `_auth_inflight`,
	##   那是个**瞬时量** —— 只在请求在飞的那几帧为真, 回包一到就被清回 false。
	##   同一份代码, 本地跑到 412 帧它还是 true, CI 上 16 帧就已经是 false 了
	##   ⇒ 这条判据的答案**跟机器快慢走**, 本地必绿、CI 必红(本仓「尺子跟机器速度走」那一族)。
	## ⇒ 改成注入传输, 量**真实发出去的那个请求**: 发没发、发去哪儿。
	##   它是记录下来的, 不会被时间清掉; 而且量的是产品自己拼的 URL, 不是我插的计数器。
	SB._reset_auth_for_test()
	_reqs.clear()
	SB._transport_for_test = _spy
	_ok("③ ★★分母: 进主菜单之前一个请求都没发 —— 否则下面那条是恒真式",
		_reqs.size() == 0, str(_reqs.size()))
	## ★不能直接 `change_scene_to_file`: 门禁自己就是 `current_scene`, 那一句当场把
	##   门禁拆掉(本仓踩过)。先把 current_scene 置空 —— 引擎只 `memdelete(current_scene)`,
	##   置空之后它谁也不删, 门禁作为 root 的普通子节点活下来继续量。
	## ★必须走真 `change_scene_to_file`: 墙的条件里有 `current_scene == self`,
	##   手动 `add_child` 的话墙根本不会触发(第一版探针就是这么骗过自己的)。
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	for _i in 16:
		await get_tree().process_frame
	var cur := get_tree().current_scene
	_ok("③ ★★分母: 墙**真的触发了**(被送到 Settings) —— 否则下面量的是没墙的路径",
		cur != null and cur.name == "Settings", cur.name if cur != null else "<null>")
	var urls: Array = []
	for r in _reqs:
		urls.append(str(r.get("url", "")).replace(DEAD_URL, ""))
	print("     墙触发之后, 真实发出去的请求: %s" % str(urls))
	_ok("③ ★★★墙触发之后, 建身份**仍然跑了** —— 不跑的话玩家永远发不出验证码",
		urls.has("/auth/v1/signup"), str(urls))
	SB._transport_for_test = Callable()
	_reqs.clear()


## 递归收集某棵子树里的 Button。
func _buttons(root) -> Array:
	var out: Array = []
	if root == null or not is_instance_valid(root):
		return out
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button:
			out.append(n)
		for c in (n as Node).get_children():
			stack.append(c)
	return out
