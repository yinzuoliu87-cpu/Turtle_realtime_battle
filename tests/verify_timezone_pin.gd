extends Node
## verify_timezone_pin.gd — 读【本地时间/时区】的地方钉死在显示层那几处; 换算方向与单位钉死
##
## ══════════════════════════════════════════════════════════════════════
##  由来(2026-10-04 欠账盘点 R6)
## ══════════════════════════════════════════════════════════════════════
## E2 拍板(`phase2_config.gd` 赛程段头注):「**赛程逻辑一律用 UTC, 时区换算只发生在显示层**。
##   两边都换算必然有一边忘 —— 那种 bug 一年只在夏令时切换那两天出现, 最难查。」
## 全仓读本地时区的只有两处, 都在显示层:
##   · `phase2_config.gd::local_hhmm`   —— 「本地 HH:MM」唯一换算口(主菜单 / 对阵图共用)
##   · `MainMenuScene.gd::_local_dict`  —— 「周X HH:MM 收盘」
## (外加 `battle_watchdog.gd` 一处打日志用的本地时间戳, 不进任何判定。)
## **但没有一条断言钉住它** —— 哪天有人在判定层顺手读一次 `get_datetime_dict_from_system()`,
## 本机(UTC+8)一切正常, CI(UTC)一切正常, 只有某个时区的玩家在某个钟点被判错。
##
## ★两把尺子:
##   ① 静态: 全仓 `.gd` 里读本地时间/时区的 API 只许出现在下面 ALLOW 那几个【函数】里
##      (不是"那几个文件" —— 同一个文件里多一处判定层的读也要红)。新增 ⇒ 红; 少了 ⇒ 红(台账跟着改)。
##   ② 运行时: `local_hhmm` 的换算方向/单位(bias 是**分钟**、是**加**到 UTC 上)用一条独立的整数算式对账。
##      ⚠ 诚实登记: CI(ubuntu)跑在 UTC, bias = 0 ⇒ ②在 CI 上只验得到「格式 + 零偏移」, 方向/单位的齿只在
##        非 UTC 机器(本机实测 bias = 60 分钟)上咬得住。① 两边都满齿。

const P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 本地时间 / 时区 API(不带 `true` 参数时都是本地时间; 带了也一样要登记 —— 判定层一律走 unix 秒)
const API_RX := "\\b(get_time_zone_from_system|get_datetime_dict_from_system|get_date_dict_from_system|get_time_dict_from_system|get_datetime_string_from_system|get_date_string_from_system|get_time_string_from_system)\\s*\\("

## "文件::函数" → 允许处数 + 理由。★只减不增; 想加一处必须写清楚它为什么属于显示层。
const ALLOW := {
	"res://scripts/gamedata/phase2_config.gd::local_hhmm": [1, "「本地 HH:MM」唯一换算口(E2: 换算只在显示层)"],
	"res://scripts/scenes/MainMenuScene.gd::_local_dict": [1, "主菜单「周X HH:MM 收盘」(显示层)"],
	"res://scripts/scenes/battle/battle_watchdog.gd::_snapshot": [1, "卡死猎手日志的时间戳(只打印, 不进判定)"],
}

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 时区钉死: 本地时间只在显示层读 ===")
	var rx := RegEx.new()
	rx.compile(API_RX)
	var fn_rx := RegEx.new()
	fn_rx.compile("^(?:static\\s+)?func\\s+([A-Za-z_]\\w*)")
	var files: Array = []
	for d in ["res://scripts", "res://autoload"]:
		_gather(d, files)
	var lines_n := 0
	var hits := {}     # "文件::函数" → [行号…]
	for path in files:
		var src: String = FileAccess.get_file_as_string(str(path))
		var fn := ""
		var ln := 0
		for raw in src.split("\n"):
			ln += 1
			var line: String = raw.trim_suffix("\r")
			var m := fn_rx.search(line)
			if m != null:
				fn = m.get_string(1)
			var code: String = _strip_comment(line)
			if rx.search(code) != null:
				var key: String = "%s::%s" % [str(path), fn]
				if not hits.has(key):
					hits[key] = []
				(hits[key] as Array).append(ln)
		lines_n += ln
	_ok("①★分母: 扫了 %d 个 .gd / %d 行" % [files.size(), lines_n], files.size() >= 150 and lines_n >= 80000,
		"扫描面塌了 ⇒ 下面那条恒真")
	var extra: Array = []
	for k in hits:
		var cap: int = int((ALLOW.get(k, [0, ""]) as Array)[0])
		if (hits[k] as Array).size() > cap:
			extra.append("%s 行 %s" % [k, str(hits[k])])
	_ok("①★★读本地时间/时区的只有 ALLOW 里那 %d 个显示层函数(判定层一律 UTC)" % ALLOW.size(),
		extra.is_empty(), "多出来的: %s —— 判定层要用 unix 秒; 真属于显示层就登记进 ALLOW 并写理由" % str(extra))
	var gone: Array = []
	for k in ALLOW:
		if not hits.has(k) or (hits[k] as Array).size() < int((ALLOW[k] as Array)[0]):
			gone.append(str(k))
	_ok("①★台账与现状一致(登记了却找不到 = 函数改名/挪走了, 台账要跟着改)", gone.is_empty(), str(gone))

	## ② 换算方向与单位: 独立整数算式对账
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0))
	print("  [信息] 本机时区偏移 bias = %d 分钟(CI/UTC 上为 0, 见头注的诚实登记)" % bias)
	## 1789948800 = 2026-09-21 周一 00:00 UTC(= `_det_scenarios.PIN_WEEK_ANCHOR`) ⇒ 减一天 = 周日 00:00 UTC
	var sun0: int = 1789948800 - 86400
	var samples: Array = [sun0 + 8 * 3600, sun0 + 20 * 3600, sun0 + 23 * 3600 + 59 * 60, sun0]
	var bad: Array = []
	for ts in samples:
		var utc_min: int = int(((int(ts) % 86400) + 86400) % 86400) / 60
		var loc: int = ((utc_min + bias) % 1440 + 1440) % 1440
		var want: String = "%02d:%02d" % [loc / 60, loc % 60]
		var got: String = P2.local_hhmm(int(ts))
		if got != want:
			bad.append("%d: 得 %s / 应 %s" % [int(ts), got, want])
	_ok("②★分母: 样本覆盖 4 个钟点(含跨午夜的 23:59 与 00:00)", samples.size() == 4)
	_ok("②★★`local_hhmm` = UTC 分钟 + bias(分钟) 再取模(独立整数算式, 不调产品的换算)", bad.is_empty(), str(bad))
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 时区钉死" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 引号感知地去掉行内注释(字符串里的 `#` 不算注释)。
func _strip_comment(line: String) -> String:
	var q := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if q != "":
			if ch == "\\":
				i += 2
				continue
			if ch == q:
				q = ""
		elif ch == "\"" or ch == "'":
			q = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line


func _gather(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n.begins_with("."):
			n = dir.get_next()
			continue
		var p := dir_path + "/" + n
		if dir.current_is_dir():
			_gather(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = dir.get_next()
	dir.list_dir_end()
