extends Node
## verify_backend_not_silent.gd — 阵容同步失败【不许静默】(2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01:「而且我刚刚打了1把赢的上传了吗」。
## 一查 —— **后端整个不在了**: `turtle-ghost.yinzuoliu87-cpu.deno.net` 回
## `404 DEPLOYMENT_NOT_FOUND`(不是路由错, 根路径就 404)。
## 而 `RemotePool.upload()` 是**发完就忘**(不等结果、失败不弹错), 于是:
##   · 每赢一把都在往虚空里发
##   · 拉取幽灵池也 404 ⇒ 对手全是 bot
##   · **游戏里一点提示都没有** —— 他不问, 我永远不知道
##
## ★★静默失败比失败本身危险: 失败会被修, 静默不会。
##
## 这份门禁守两件事:
##   ① 失败**留得下痕迹**(fail_count / last_fail_reason / looks_broken)
##   ② **没配地址时不误报** —— 那是"有意关掉"不是"坏了"(当前 backend_url 就是空的)
##      判据两边都要卡: 只验"坏了会报"会放过"天天误报"; 而天天见到的警报没人看。
const RP := preload("res://scripts/net/remote_pool.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 阵容同步失败不许静默 ===")

	# ── ① 当前配置: 后端是【有意关掉】的 ──
	var url: String = str(ProjectSettings.get_setting("turtle/backend_url", ""))
	_ok("★后端地址当前是空的(Deno 部署已 DEPLOYMENT_NOT_FOUND, 2026-09-01 主动清空)",
		url.strip_edges() == "", "实测「%s」" % url)

	# ── ② 失败留痕 ──
	RP.fail_count = 0
	RP.ok_count = 0
	RP.last_fail_reason = ""
	_ok("★分母: 起手是干净的(没发过 = 不该报警)", not RP.looks_broken())
	RP.note_result(false, 404)
	_ok("★★失败一次就留下痕迹: 次数 %d · 原因「%s」"
		% [RP.fail_count, RP.last_fail_reason],
		RP.fail_count == 1 and RP.last_fail_reason != "")
	_ok("★★404 的原因要写成人话(带「部署不存在」), 不是丢个裸数字",
		RP.last_fail_reason.contains("404") and RP.last_fail_reason.contains("部署不存在"),
		RP.last_fail_reason)
	_ok("★★looks_broken() 为真 ⇒ 结算屏会显示「阵容同步 失败」", RP.looks_broken())

	# ── ③ ★不许误报: 成功过就不算坏 ──
	RP.note_result(true, 200)
	_ok("★★★成功过一次之后就不再报警(半通不通 ≠ 坏了)", not RP.looks_broken(),
		"ok=%d fail=%d" % [RP.ok_count, RP.fail_count])
	_ok("★成功会清掉上一次的失败原因", RP.last_fail_reason == "")
	## ★"压根没发过"也不许报警 —— 后端关着是**有意的**, 天天弹警告没人会看
	RP.fail_count = 0
	RP.ok_count = 0
	_ok("★★★压根没发过时不报警(后端关着是有意的, 不是坏了)", not RP.looks_broken())

	# ── ④ 三个失败出口都记账(漏一个就还是静默) ──
	var src: String = FileAccess.get_file_as_string("res://scripts/net/remote_pool.gd")
	var n_note: int = src.count("note_result(")
	## 一次定义 + 三个出口(不在树 / request() 返错 / 回调) = 4 次出现, 外加静态函数体内 0 次
	_ok("★★_http 的**每一个**失败出口都调了 note_result(实测源码里出现 %d 次)"
		% n_note, n_note >= 4, "漏一个出口 = 那条路径仍然静默")

	# ── ⑤ 结算屏真的读它 ──
	var hud: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("★★结算屏真的读 looks_broken() 并显示「阵容同步」(写了没人读 = 白写)",
		hud.contains("looks_broken()") and hud.contains("阵容同步"))

	if _n < 10:
		print("  [FAIL] ★分母: 断言只有 %d 条(<10)" % _n)
		_fail += 1
	print("ALL PASS — 同步失败不静默(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
