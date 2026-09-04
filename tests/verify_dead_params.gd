extends Node
## verify_dead_params.gd — 死参数棘轮（签名里有、函数体一次都没用）
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么这条值得有
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-04：「彻查项目的所有代码…」「真实伤害数字是一团乱，应该统一规则的」
##
## 真伤那件事的**静态形状就是一个死参数**：
##   `_apply_damage_from(src, u, dmg, col, …)` 的 `col` —— **227 个调用点**辛辛苦苦
##   传了颜色，而函数体里根本没用它（颜色由 `_ncol` 按伤害类型统一取）。
##   于是那 227 处传的主题色**一个都不生效**，却没人知道，直到用户发现真伤颜色乱。
## ⇒ 「传了不用」是「同一概念多套实现」最容易机器化的一面。
##
## ══════════════════════════════════════════════════════════════════
##  ★★判据怎么来的（我试错了两版才对）
## ══════════════════════════════════════════════════════════════════
## 正则扫源码**不可靠**，我连错两版：
##   v1 漏了**多行签名** → 报出 `tgt) -> void` 这种假参数名（43 处）
##   v2 拼多行时把**行尾注释**拼进参数列表 → 报出 `用户` / `费用才是真档位…`（99 处）
## GDScript 的签名能跨行、带默认值，注释里还有括号和逗号 —— 正则猜不动。
## ⇒ 改成让**引擎自己报**：`GDScript.get_script_method_list()` 给的是解析后的真参数名。
##   实测 2741 个方法 → **25 处**，零误报。
##
## ★`_` 前缀的参数**不算**：那是作者显式声明「我知道它没用」。
##   要消掉一条死参数，改名加 `_` 前缀就行（比删参数安全 —— 删了要改所有调用点）。
const DEBT_PATH := "res://tests/golden/dead_params_debt.txt"

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _gather(d: String, out: Array) -> void:
	var dir := DirAccess.open(d)
	if dir == null:
		return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		var p: String = d + "/" + n
		if dir.current_is_dir():
			if not n.begins_with("."):
				_gather(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = dir.get_next()
	dir.list_dir_end()


## 返回 ["文件\t函数\t参数", …]，已排序
func _scan() -> Array:
	var files: Array = []
	for d in ["res://scripts", "res://autoload"]:
		_gather(d, files)
	var dead: Array = []
	var methods := 0
	for path in files:
		var sc = load(path)
		if not (sc is GDScript):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = src.split("\n")
		for m in (sc as GDScript).get_script_method_list():
			var fname: String = str(m.get("name", ""))
			var args: Array = m.get("args", [])
			if fname == "" or args.is_empty():
				continue
			var def_line := -1
			for i in range(lines.size()):
				if lines[i].begins_with("func " + fname + "(") or lines[i].begins_with("static func " + fname + "("):
					def_line = i
					break
			if def_line < 0:
				continue      # 继承来的方法，不是本脚本定义的
			methods += 1
			var end_line: int = lines.size()
			for j in range(def_line + 1, lines.size()):
				if lines[j].begins_with("func ") or lines[j].begins_with("static func "):
					end_line = j
					break
			var body := ""
			for j in range(def_line + 1, end_line):
				var lj: String = lines[j]
				if lj.strip_edges().begins_with("#"):
					continue
				var hp: int = lj.find("#")
				if hp >= 0:
					lj = lj.substr(0, hp)
				body += lj + "\n"
			for a in args:
				var an: String = str(a.get("name", ""))
				if an == "" or an.begins_with("_"):
					continue
				var rx := RegEx.new()
				rx.compile("\\b" + an + "\\b")
				if rx.search(body) == null:
					dead.append("%s\t%s\t%s" % [path, fname, an])
	_ok("★分母: 扫到 %d 个文件 / %d 个本脚本定义的带参方法" % [files.size(), methods],
		files.size() > 100 and methods > 1000,
		"扫不到东西 ⇒ 下面全是空检查")
	dead.sort()
	return dead


func _ready() -> void:
	print("=== 死参数棘轮（只减不增）===")
	var now: Array = _scan()

	var debt: Array = []
	if FileAccess.file_exists(DEBT_PATH):
		for l in FileAccess.get_file_as_string(DEBT_PATH).split("\n"):
			var s: String = l.strip_edges()
			if s != "" and not s.begins_with("#"):
				debt.append(s)
	debt.sort()

	_ok("★分母: 台账读到 %d 条" % debt.size(), debt.size() > 0,
		"台账为空 ⇒ 下面的『没新增』是恒真式")

	var added: Array = []
	for x in now:
		if not debt.has(x):
			added.append(x)
	var fixed: Array = []
	for x in debt:
		if not now.has(x):
			fixed.append(x)

	_ok("① **没有新增**的死参数（现 %d / 台账 %d）" % [now.size(), debt.size()],
		added.is_empty(),
		"新增 %d 条:\n     %s" % [added.size(), "\n     ".join(added)])

	if not fixed.is_empty():
		print("  [提示] 已修掉 %d 条，把台账更新掉（只减不增）:" % fixed.size())
		for f in fixed:
			print("     - %s" % f)
		_ok("② 台账要跟着缩（修好了就从台账里删掉）", false,
			"台账里有 %d 条已经不存在了，请更新 %s" % [fixed.size(), DEBT_PATH])
	else:
		_ok("② 台账与现状一致（没有已修好却还挂在账上的）", true)

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
