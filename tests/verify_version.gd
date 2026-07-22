extends Node

## verify_version.gd — 版本号单一事实源 (用户 2026-07-22 需求2:「我们需要有版本号这种东西」)
##
## 版本号散在四处, 一处漏改就说不清测试者报的是哪个版本:
##   ① project.godot   config/version        ← 事实源, 游戏内显示读它
##   ② CHANGELOG.md    最新 `## x.y.z` 条目
##   ③ export_presets  iOS  application/short_version
##   ④ export_presets  Android version/name
##
## ★这条门禁的价值全在"会红"上 —— 只改代码忘了记账, 或改了 CHANGELOG 忘了改包,
##   都必须当场红。所以每条断言都打印【两边的实际值】, 不打印就等于没法判断是不是空比较。
##
## ★还守一条: 主菜单不许把版本号写成字面量 —— 那就是第五份会漂的副本。

const PROJECT_CFG := "res://project.godot"
const CHANGELOG := "res://CHANGELOG.md"
const PRESETS := "res://export_presets.cfg"
const MENU_SRC := "res://scripts/scenes/MainMenuScene.gd"

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	# ★先让出一帧: _ready 期间 root 还在"装配子节点"状态, 这时 add_child 会被拒
	#   (下面要真实例化主菜单)。没这一帧的话 Label 数是 0, 看着像"版本号没显示"。
	await get_tree().process_frame
	var v_proj := _project_version()
	_ok("project.godot 有 config/version", v_proj != "", "读到 %s" % ("(空)" if v_proj == "" else v_proj))
	if v_proj == "":
		_done()
		return
	_ok("版本号形如 x.y.z", _is_semverish(v_proj), v_proj)

	# ── ② CHANGELOG 最新条目 ──
	var entries := _changelog_versions()
	print("  [分母] CHANGELOG 里解析到 %d 个版本条目" % entries.size())
	_ok("CHANGELOG 至少有一个版本条目(N=0 是空检查不是通过)", entries.size() >= 1)
	if entries.size() >= 1:
		var top: String = entries[0]
		_ok("★project.godot 与 CHANGELOG 最新条目一致",
			top == v_proj, "project=%s  CHANGELOG首条=%s" % [v_proj, top])
		_ok("CHANGELOG 最新条目带日期(patch notes 要能看出什么时候发的)",
			_changelog_top_has_date(), "首条标题: %s" % _changelog_top_line())

	# ── ③④ 导出预设 ──
	var ios := _preset_field("application/short_version")
	var android := _preset_field("version/name")
	_ok("★iOS 包版本与 project.godot 一致",
		ios == v_proj, "iOS short_version=%s  project=%s" % [ios, v_proj])
	_ok("★Android 包版本与 project.godot 一致",
		android == v_proj, "Android version/name=%s  project=%s" % [android, v_proj])

	# ── ⑤ 主菜单必须读 ProjectSettings, 不许硬编码 ──
	var menu := _read(MENU_SRC)
	_ok("主菜单从 ProjectSettings 取版本号",
		_code_only(menu).contains("application/config/version"),
		"没读 ProjectSettings = 版本号又多一份副本")
	var hard := _hardcoded_version_literals(menu)
	_ok("主菜单里没有硬编码的版本号字面量",
		hard.is_empty(), "发现 %s" % str(hard))

	# ── ⑥ 行为级: 真进主菜单, 屏幕上必须有一个写着版本号的 Label ──
	#    ★上面几条全是查源码 —— 代码写了但没 add_child、被别的节点盖住、或 v=="" 提前 return,
	#      静态检查一条都抓不到。测试者报 bug 时看不到版本号, 这套东西就白做了。
	await _check_menu_shows_version(v_proj)

	# ── 反向自检: 确认上面的比较不是"空 == 空" ──
	_ok("四处版本号都非空(否则上面的一致性断言是空比较)",
		v_proj != "" and ios != "" and android != "" and (entries.size() > 0 and str(entries[0]) != ""),
		"project=%s ios=%s android=%s changelog=%s"
			% [v_proj, ios, android, ("(无)" if entries.is_empty() else str(entries[0]))])
	_done()


## 真实例化主菜单, 遍历节点树找写着版本号的 Label
func _check_menu_shows_version(v: String) -> void:
	var packed := load("res://scenes/MainMenu.tscn")
	if packed == null:
		_ok("★主菜单里能看到版本号", false, "载不到 MainMenu.tscn")
		return
	var menu: Node = packed.instantiate()
	get_tree().root.add_child(menu)
	for i in 6:
		await get_tree().process_frame
	var n_labels := 0
	var hit := ""
	for node in _walk(menu):
		if node is Label:
			n_labels += 1
			if str(node.text).contains(v):
				hit = str(node.text)
	print("  [分母] 主菜单里共 %d 个 Label" % n_labels)
	_ok("主菜单确实建出了 Label(N=0 说明场景没起来, 下条是空检查)", n_labels > 0)
	_ok("★主菜单屏幕上真的显示了版本号(测试者报 bug 时看得见)",
		hit != "", "找到 %s (期望含 %s)" % [("(没有)" if hit == "" else hit), v])
	menu.queue_free()
	await get_tree().process_frame


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _project_version() -> String:
	# ★读文件而不是 ProjectSettings.get_setting: 要验的就是【文件里写没写】。
	#   get_setting 有默认值兜底, 字段删了也能返回东西 → 会把漏写判成通过。
	var re := RegEx.new()
	re.compile("config/version\\s*=\\s*\"([^\"]+)\"")
	var m := re.search(_read(PROJECT_CFG))
	return m.get_string(1) if m != null else ""


func _is_semverish(v: String) -> bool:
	var re := RegEx.new()
	re.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	return re.search(v) != null


## CHANGELOG 里所有 `## x.y.z` 标题, 按出现顺序(最新在前)
func _changelog_versions() -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("^##\\s+([0-9]+\\.[0-9]+\\.[0-9]+)")
	for line in _read(CHANGELOG).split("\n"):
		var m := re.search(str(line))
		if m != null:
			out.append(m.get_string(1))
	return out


func _changelog_top_line() -> String:
	var re := RegEx.new()
	re.compile("^##\\s+[0-9]+\\.[0-9]+\\.[0-9]+.*$")
	for line in _read(CHANGELOG).split("\n"):
		var m := re.search(str(line))
		if m != null:
			return str(line)
	return "(无)"


func _changelog_top_has_date() -> bool:
	var re := RegEx.new()
	re.compile("[0-9]{4}-[0-9]{2}-[0-9]{2}")
	return re.search(_changelog_top_line()) != null


func _preset_field(key: String) -> String:
	var re := RegEx.new()
	re.compile(key.replace("/", "\\/") + "\\s*=\\s*\"([^\"]*)\"")
	var m := re.search(_read(PRESETS))
	return m.get_string(1) if m != null else ""


## 找形如 "0.9.3" / "v0.9.3" 的字面量 —— 版本号只能有一个来源
func _hardcoded_version_literals(src: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"v?[0-9]+\\.[0-9]+\\.[0-9]+\"")
	for m in re.search_all(_code_only(src)):
		out.append(m.get_string(0))
	return out


## 剥注释 —— 否则注释里举例写个 "0.9.3" 就会误报, 或注释里提到 ProjectSettings 就假通过
func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out


func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	if s == "":
		_fail += 1
		print("  [FAIL] 读不到 %s" % path)
	return s


func _done() -> void:
	print("ALL PASS — 版本号四处一致(project/CHANGELOG/iOS/Android)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
