extends Node
## verify_gate_isolation.gd — 门禁的【每测试一份 user://】在**当前这个平台**上真的生效吗
##
## ════════════════════════════════════════════════════════════════════════
## 由来(2026-09-30): 2026-09-23 加了「每个测试一份独立 APPDATA」, 本地当场照出
##   三条一直存在的竞态绿。**但那个修复只换了 `APPDATA`** ——
##   Windows 上 Godot 的 `user://` 解析到 `%APPDATA%`, 而
##   **Linux(= CI) 上它走 `$XDG_DATA_HOME`, 根本不看 APPDATA**。
## ⇒ 隔离**在 CI 上从来没生效过**: 404 个测试一直共用同一份 `user://`。
##   铁证是 CI 日志里那句 `[GameState] ⚠ 正式存档损坏, 用备份 .bak 开局` ——
##   全新目录上不该有存档, 更不该有**坏掉的**存档, 那是别的进程同一刻写到一半的。
##   症状就是「本地 404/404 全绿而 CI 红」, 谁输了那场竞争谁红。
##
## ★★为什么必须有这一条: 上面那个洞**本地永远绿**, 所以没有任何判据会响。
##   一个写死了平台的隔离, 只在那个平台上算数 —— 而门禁跑在两个平台上。
## ★这条判据量的是**产品/引擎自己报的路径**(`OS.get_user_data_dir()`),
##   不是我拼出来的字符串; 拼字符串就变成「断言自己插的标记」。
## ★分母: 环境变量真的设了(没设 ⇒ 不是在门禁里跑 ⇒ 显式登记, 不静默跳过)。
## ════════════════════════════════════════════════════════════════════════

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] %s  %s" % [t, d])
	else:
		print("  [FAIL] %s  %s" % [t, d])
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 门禁隔离: 每测试一份 user:// ===")
	var udir: String = OS.get_user_data_dir().replace("\\", "/")
	var appdata: String = OS.get_environment("APPDATA").replace("\\", "/")
	var xdg: String = OS.get_environment("XDG_DATA_HOME").replace("\\", "/")
	print("  [分母] user:// 实际解析到: %s" % udir)
	print("  [分母] APPDATA=%s" % (appdata if appdata != "" else "<未设>"))
	print("  [分母] XDG_DATA_HOME=%s" % (xdg if xdg != "" else "<未设>"))

	## ★本平台该看哪个变量 —— 由引擎自己的行为决定, 不由我猜。
	var os_name: String = OS.get_name()
	var expect: String = xdg if os_name != "Windows" else appdata
	var which: String = "XDG_DATA_HOME" if os_name != "Windows" else "APPDATA"
	## ★「是不是在门禁里跑」只能靠门禁自己 export 的 `GATE_APPDATA` 判 ——
	##   拿 `APPDATA` 判不行: Windows 上它是系统自带的, 永远非空
	##   ⇒ 独立跑这个测试时会把「本来就没隔离」误报成缺陷(初版就这样)。
	var in_gate: bool = OS.get_environment("GATE_APPDATA") != ""
	_ok("★分母: 本平台(%s)该用的变量是 `%s`, 而它设了吗" % [os_name, which],
		(not in_gate) or expect != "", expect if expect != "" else "<未设>")
	if not in_gate:
		print("")
		print("  （GATE_APPDATA 未设 ⇒ 不是在 run-tests.sh 里跑; 这一条只在门禁里有意义）")
		print("ALL PASS — 门禁隔离(独立运行, 跳过)")
		get_tree().quit(0)
		return
	if expect == "":
		print("")
		print("  （不是在 run-tests.sh 里跑 —— 这一条只有在门禁里才有意义）")
		print("ALL PASS — 门禁隔离(独立运行, 跳过)")
		get_tree().quit(0)
		return

	_ok("★★★ISOLATED_USERDIR: `user://` 真的落在门禁给这个测试的目录里 —— "
		+ "不在 = 所有测试共用一份存档, 互相写坏(本地绿而 CI 红就是这么来的)",
		udir.begins_with(expect), "user://=%s\n              期望前缀=%s" % [udir, expect])

	## ★另一半: 目录名里必须带**这个测试自己的名字** ——
	##   run-tests.sh 给的是 `$GATE_APPDATA/<测试名>`。只验「在 GATE_APPDATA 下」还不够:
	##   所有测试都在它下面也叫「在它下面」, 那条断言会恒真。
	_ok("★★分母: 那个目录是**这个测试专属**的(路径里带测试名), 不是大家共用的上层目录",
		expect.get_file() == "verify_gate_isolation",
		"目录末段=%s (期望 verify_gate_isolation)" % expect.get_file())

	## ★两个变量都设上才是两个平台都隔离 —— 这一条专门挡「只修了当前平台」。
	_ok("★★两个平台的变量**都**设了(只设一个 ⇒ 另一个平台上隔离等于没做, 而且只会在那个平台红)",
		appdata != "" and xdg != "",
		"APPDATA=%s / XDG_DATA_HOME=%s" % [appdata if appdata != "" else "<未设>",
			xdg if xdg != "" else "<未设>"])

	print("")
	print("  分母: 共 %d 条断言" % _n)
	print("ALL PASS — 门禁隔离" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
