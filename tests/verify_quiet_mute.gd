extends Node

## verify_quiet_mute.gd — `QUIET=1` 真的让引擎一声不出 (2026-10-01)
##
## 【由来】用户在用电脑时要求「一定要静音」。我先答了"headless 没窗口"——答的不是他问的那一维；
## 改成到处加 `--audio-driver Dummy` 之后他说**还是有声音**；最后他挑明「你一开窗口，就有声音」。
##
## 【为什么不靠 `--audio-driver Dummy`】我拿不出它生效的证据：`--verbose` 里引擎
## 根本不打印选中了哪个音频驱动。"我加了 Dummy" 只是一个说法，不是一条可量的事实。
## ⇒ 改成在**引擎内部的主总线**上静音（`autoload/Audio.gd::_apply_quiet_gate`），
## 它与音频驱动无关，而且 `AudioServer.is_bus_mute(0)` 能在这里**直接量出来**。
##
## 【这条门禁量的是引擎自己的账】`AudioServer.is_bus_mute(0)` / `get_bus_volume_db(0)`
## 都是引擎报的状态，不是我插的标记。
##
## ★跑法: 门禁里本测试由 run-tests.sh 带 `QUIET=1` 启动（见那边 run_one）。
##   没有 QUIET 时它断言的是**反面**：主总线不该被静音（否则玩家也听不见声音了）。

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	var has_q := OS.has_environment("QUIET") and str(OS.get_environment("QUIET")).strip_edges() not in ["", "0", "false"]
	var muted := AudioServer.is_bus_mute(0)
	var db := AudioServer.get_bus_volume_db(0)
	print("  [分母] QUIET 环境变量 = %s / 主总线 mute=%s volume=%.1f dB"
		% [("有:" + OS.get_environment("QUIET")) if OS.has_environment("QUIET") else "没有", str(muted), db])
	_ok("★分母: 读得到主总线(总线数 ≥ 1, 读不到则下面全是空检查)", AudioServer.bus_count >= 1,
		"总线数 %d" % AudioServer.bus_count)

	if has_q:
		_ok("★QUIET=1 ⇒ 主总线已静音", muted, "mute=%s" % str(muted))
		_ok("★QUIET=1 ⇒ 主总线音量压到 -80 dB(双保险: 有人把 mute 改回去也听不见)",
			db <= -79.9, "%.1f dB" % db)
		_ok("★QUIET=1 ⇒ Audio 自己的音量也归零", Audio.sfx_volume == 0.0 and Audio.bgm_volume == 0.0,
			"sfx=%.2f bgm=%.2f" % [Audio.sfx_volume, Audio.bgm_volume])
	else:
		## ★反面同样要守: 没设 QUIET 还把总线闷掉, 就是**玩家也听不见声音**。
		##   只断言"设了就静音"而不断言"没设就不静音", 那条判据可以靠"永远静音"作弊通过。
		_ok("★没设 QUIET ⇒ 主总线【不】静音(否则玩家也听不见)", not muted)
		_ok("★没设 QUIET ⇒ 主总线音量正常", db > -79.9, "%.1f dB" % db)

	## ★★门禁里本测试是**带着 QUIET=1** 跑的(run-tests.sh 给所有测试都加了),
	##   所以上面那个 else 分支在门禁里**走不到** —— 只剩"设了就静音"这一半,
	##   而那一半可以靠"永远静音"作弊通过(出厂包也没声音, 玩家听不见)。
	##   ⇒ 补一条**源码级**的反面证据: 静音必须是**有条件的**。
	##   (memory `fb-judge-must-fit-the-shape`: 判据宽一格造假 bug、窄一格放过真 bug。)
	var src := FileAccess.get_file_as_string("res://autoload/Audio.gd")
	_ok("★分母: 读得到 autoload/Audio.gd", src.length() > 200, "只有 %d 字符" % src.length())
	_ok("★静音是【有条件的】—— 没有 QUIET 这个环境变量时直接 return(否则出厂包也没声音)",
		src.contains("if not OS.has_environment(\"QUIET\"):") and src.contains("AudioServer.set_bus_mute(0, true)"))

	print("ALL PASS — QUIET 静音总闸" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
