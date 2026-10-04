extends RefCounted
## _gs_read_trace.gd — 运行时量「谁读了 GameState 的哪个变量」(回放录像瘦身的尺子)。
##
## 做法: 把 `autoload/GameState.gd` 的源码读进来, 给每一个顶层 `var x ...` 补一个 getter
##   (`get: _rd_hit("x"); return x`), 编译成新脚本, **原地换到 GameState 这个节点上**
##   (节点对象不变 ⇒ 全仓的 `GameState.xxx` 照样指向它), 再把换脚本前的全部变量值抄回去。
##   GDScript 4 的 getter 在类内部访问时**也会走**(`self.x` 与裸 `x` 都走, 只有 getter 自己体内不走),
##   ⇒ GameState 自己的方法(`get_dual_lineup()` 读 `dual_lineup` 等)间接读到的也记得到。
##
## 为什么不列白名单: 白名单天生会漏(memory fb-recursive-scan-not-structured-walk)。
##   「回放实际读了什么」是**量**出来的, 不是**猜**出来的。
##
## 用法:
##   var tr = load("res://tests/_gs_read_trace.gd").new()
##   var err := tr.install(gs)      # "" = 成功
##   tr.begin(); ...; var reads: Dictionary = tr.end()   # {变量名: 读次数}
##   tr.uninstall(gs)               # 换回原脚本、值抄回去

const SRC := "res://autoload/GameState.gd"

var _orig: Script = null
var _inst: GDScript = null
var var_names: Array = []          # 顶层变量名(分母: 补了 getter 的个数)


## 找一行里第一个不在字符串里的 `#`(注释起点); -1 = 没有注释。
static func _comment_at(line: String) -> int:
	var q := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if q != "":
			if c == "\\":
				i += 2
				continue
			if c == q:
				q = ""
		elif c == "\"" or c == "'":
			q = c
		elif c == "#":
			return i
		i += 1
	return -1


## 源码 → 带 getter 的源码。返回 [新源码, 变量名数组]。
static func instrument(src: String) -> Array:
	var names: Array = []
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("^var ([A-Za-z_][A-Za-z_0-9]*)\\b")
	for raw in src.split("\n"):
		var line: String = raw.trim_suffix("\r")
		var m := re.search(line)
		if m == null:
			out.append(line)
			continue
		var n := m.get_string(1)
		var ci := _comment_at(line)
		var code := (line.substr(0, ci) if ci >= 0 else line).strip_edges(false, true)
		names.append(n)
		out.append(code + ":")
		out.append("\tget:")
		out.append("\t\t_rd_hit(\"%s\")" % n)
		out.append("\t\treturn %s" % n)
	out.append("")
	out.append("var __rd_log: Dictionary = {}")
	out.append("var __rd_on: bool = false")
	out.append("func _rd_hit(n: String) -> void:")
	out.append("\tif __rd_on:")
	out.append("\t\t__rd_log[n] = int(__rd_log.get(n, 0)) + 1")
	return ["\n".join(out), names]


func install(gs: Object) -> String:
	var src := FileAccess.get_file_as_string(SRC)
	if src == "":
		return "读不到 " + SRC
	var r: Array = instrument(src)
	var_names = r[1]
	_inst = GDScript.new()
	_inst.source_code = r[0]
	var err := _inst.reload()
	if err != OK:
		return "带 getter 的 GameState 编译失败 err=%d" % err
	var vals := _snapshot(gs)
	_orig = gs.get_script()
	gs.set_script(_inst)
	for k in vals:
		gs.set(k, vals[k])
	return ""


func uninstall(gs: Object) -> void:
	if _orig == null:
		return
	var vals := _snapshot(gs)
	gs.set_script(_orig)
	for k in vals:
		gs.set(k, vals[k])
	_orig = null


func begin(gs: Object) -> void:
	gs.set("__rd_log", {})
	gs.set("__rd_on", true)


func end(gs: Object) -> Dictionary:
	gs.set("__rd_on", false)
	var d: Dictionary = gs.get("__rd_log")
	return d.duplicate()


static func _snapshot(gs: Object) -> Dictionary:
	var out := {}
	for p in gs.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p.get("name", ""))
		if n.begins_with("__rd_"):
			continue
		out[n] = gs.get(n)
	return out
