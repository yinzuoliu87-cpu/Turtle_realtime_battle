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
				## ★★ 2026-09-29 修一个**判据自己的 bug**: 原来是 `lj.find("#")` 然后砍掉后面 ——
				##   而 `#` 也会出现在**字符串里**。两个真实误报:
				##     `return "%s#%d@%s" % [base, n, lane]`      砍在 `"%s` ⇒ `lane` 被切掉
				##     `Color("#f0c27a") if primary else Color(...)` 砍在 `Color("` ⇒ `primary` 被切掉
				##   ⇒ 参数明明用了, 却被判成死的。**去注释必须认引号。**
				var q := ""          # 当前在哪种引号里("" = 不在字符串里)
				var cut := -1
				for ci in range(lj.length()):
					var ch := lj[ci]
					if q != "":
						if ch == "\\":
							continue
						if ch == q:
							q = ""
					elif ch == "\"" or ch == "'":
						q = ch
					elif ch == "#":
						cut = ci
						break
				if cut >= 0:
					lj = lj.substr(0, cut)
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


## 台账文本 → 已排序的条目。★唯一的解析口(上面的行尾判据也走它)。
func _parse_debt(txt: String) -> Array:
	var out: Array = []
	for l in txt.split("\n"):
		var s: String = l.strip_edges()
		if s != "" and not s.begins_with("#"):
			out.append(s)
	out.sort()
	return out


func _ready() -> void:
	print("=== 死参数棘轮（只减不增）===")
	var now: Array = _scan()

	var debt_txt: String = FileAccess.get_file_as_string(DEBT_PATH) if FileAccess.file_exists(DEBT_PATH) else ""
	var debt: Array = _parse_debt(debt_txt)

	_ok("★分母: 台账读到 %d 条" % debt.size(), debt.size() > 0,
		"台账为空 ⇒ 下面的『没新增』是恒真式")
	## ★★台账比对**对行尾必须不敏感**(2026-10-04 补·`docs/plans/20261002-文案落点BBCode普查.md` §6 点名)。
	##   本仓 `core.autocrlf=true` ⇒ 新 worktree 检出来是 CRLF, CI 是 LF。`verify_elite_anim` 就栽在
	##   「按行切、行尾多一个 CR」上: 新 worktree 必红、主仓绿。这一份今天靠 `strip_edges()` 扒掉了 CR,
	##   所以**现在**不瞎 —— 这条把「现在」钉住: 同一份文本强制造出 LF 版与 CRLF 版, 过同一个解析口
	##   (`_parse_debt`, 也就是上面真在用的那个), 两份台账必须逐条相同、条目里 0 个 CR。
	##   哪天有人把 `strip_edges()` 换成别的(比如只去空格), CRLF 那一侧每条都多一个 CR ⇒ 当场红。
	var d_lf: Array = _parse_debt(debt_txt.replace("\r\n", "\n"))
	var d_crlf: Array = _parse_debt(debt_txt.replace("\r\n", "\n").replace("\n", "\r\n"))
	var cr_in := 0
	for x in d_crlf:
		if str(x).contains("\r"): cr_in += 1
	_ok("★台账比对与行尾无关: LF %d 条 / CRLF %d 条逐条相同、条目里 %d 个 CR(须 0)"
		% [d_lf.size(), d_crlf.size(), cr_in],
		d_lf.size() > 0 and d_lf == d_crlf and cr_in == 0,
		"解析对行尾敏感 ⇒ 新 worktree(CRLF) 与 CI(LF) 读出两份不同的台账")

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
