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
	for k in KEYS:
		GameState.set(k, _bak[k])
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
