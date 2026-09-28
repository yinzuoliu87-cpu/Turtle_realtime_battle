extends Node
## _probe_glyphs.gd — 探针: ①逐张字体复量几个可疑码点 ②全量扫 scripts/ 的字面量非 ASCII 码点
## 跑法: godot --headless --path . res://tests/_probe_glyphs.tscn --quit-after 400

const FONTS := {
	"m6x11": "res://assets/fonts/m6x11.ttf",
	"NotoSansSC": "res://assets/fonts/NotoSansSC-Regular.otf",
	"NotoEmoji": "res://assets/fonts/NotoEmoji-Regular.ttf",
}
const LOG_CALLS := ["print(", "printerr(", "push_warning(", "push_error(", "print_rich("]

var _f: Dictionary = {}

func _ready() -> void:
	# ── 0. 字体真加载到了吗(分母) ──
	var loaded := 0
	for k in FONTS.keys():
		var ff := load(str(FONTS[k])) as FontFile
		_f[k] = ff
		var ok: bool = ff != null
		if ok: loaded += 1
		print("[font] %-11s loaded=%s  glyphs_probe(A=%s 龟=%s)" % [k, ok,
			(ff.has_char(65) if ok else "n/a"), (ff.has_char(0x9F9F) if ok else "n/a")])
	print("[分母] 字体 %d/%d 张加载成功" % [loaded, FONTS.size()])
	if loaded != FONTS.size():
		get_tree().quit(1); return

	# ── 1. 定点复量: 任务里点名的三个 + 相邻对照 ──
	print("\n=== 1. 定点复量 (逐张字体 has_char) ===")
	var battery := [0x2713, 0x2714, 0x2715, 0x2716, 0x2717, 0x2718,
		0x2725, 0x2726, 0x2727, 0x2605, 0x2606, 0x1FA93, 0x1F422, 0x9F9F, 0x274C, 0x00D7,
		0x00D7, 0x0058, 0x2A2F,
		0x25C6, 0x25CF, 0x25B8, 0x25C8, 0x2666, 0x2022, 0x2732, 0x273B, 0x25C7, 0x2756,
		0x2514, 0x251C, 0x00BB, 0x2192, 0x2937, 0x27A5, 0x2199, 0x21AA, 0x2E2E,
		0x25BC, 0x25B2, 0x2212, 0x2013, 0x25AC, 0x25A0, 0x25B6, 0x25B7, 0x2796,
		0x21BB, 0x21BA, 0x27F3, 0x2B6F, 0x2261]
	var seen: Dictionary = {}
	var n_cp := 0
	for cp in battery:
		if seen.has(cp): continue
		seen[cp] = true
		n_cp += 1
		var row := "U+%04X %s  " % [cp, char(cp)]
		var any := false
		for k in FONTS.keys():
			var h: bool = (_f[k] as FontFile).has_char(cp)
			if h: any = true
			row += "%s=%s " % [k, ("Y" if h else "-")]
		row += " => %s" % ("OK" if any else "★★TOFU(三张都没有)")
		print("  ", row)
	print("[分母] 定点查了 %d 个码点 × %d 张字体 = %d 次 has_char" % [n_cp, FONTS.size(), n_cp * FONTS.size()])

	# ── 2. 全量自动扫 ──
	for mode in ["dq", "dq+sq"]:
		print("\n=== 2. 自动扫 scripts/**/*.gd  引号口径=%s ===" % mode)
		var files := _all_gd("res://scripts")
		var cps: Dictionary = {}    # cp -> [ "file:line", ... ]
		var lit_lines := 0
		var skipped := 0
		for p in files:
			var src := FileAccess.get_file_as_string(p)
			var ln := 0
			for line in src.split("\n"):
				ln += 1
				var pair: Array = _split_line(str(line), mode == "dq+sq")
				var code: String = str(pair[0])
				var lit: String = str(pair[1])
				var is_log := false
				for lg in LOG_CALLS:
					if code.find(lg) >= 0:
						is_log = true; break
				if is_log:
					if lit != "": skipped += 1
					continue
				if lit == "": continue
				lit_lines += 1
				for i in range(lit.length()):
					var cp := lit.unicode_at(i)
					if cp < 0x80: continue
					if not cps.has(cp): cps[cp] = []
					var where := "%s:%d" % [p.replace("res://", ""), ln]
					if not (cps[cp] as Array).has(where):
						(cps[cp] as Array).append(where)
		var keys: Array = cps.keys()
		keys.sort()
		var missing: Array = []
		for cp in keys:
			var any := false
			for k in FONTS.keys():
				if (_f[k] as FontFile).has_char(int(cp)): any = true; break
			if not any: missing.append(int(cp))
		print("[分母] 文件 %d 个 / 含字面量的行 %d 行 / 跳过的日志行 %d 行 / 不同非ASCII码点 %d 个" % [
			files.size(), lit_lines, skipped, keys.size()])
		print("[结果] 三张字体都没有字形的码点: %d 个" % missing.size())
		for cp in missing:
			var w: Array = cps[cp]
			print("   U+%04X 「%s」 ×%d 处: %s" % [cp, char(int(cp)), w.size(),
				", ".join(w.slice(0, 8))])
	get_tree().quit(0)


func _all_gd(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var d: String = str(dirs.pop_back())
		var da := DirAccess.open(d)
		if da == null: continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if da.current_is_dir():
				if not f.begins_with("."): dirs.append(d + "/" + f)
			elif f.ends_with(".gd"):
				out.append(d + "/" + f)
			f = da.get_next()
		da.list_dir_end()
	out.sort()
	return out


## 一行 → [去注释后的代码, 全部字符串字面量正文拼起来]
## 【开引号】决定谁能闭合 ⇒ "it's" 里的 ' 不会被当分隔符。
func _split_line(line: String, allow_sq: bool) -> Array:
	var code := ""
	var lit := ""
	var i := 0
	var q := ""
	while i < line.length():
		var ch := line[i]
		if q != "":
			if ch == "\\":
				code += ch
				i += 1
				if i < line.length():
					code += line[i]; i += 1
				continue
			if ch == q:
				q = ""; code += ch; i += 1; continue
			lit += ch; code += ch; i += 1
			continue
		if ch == "\"" or (allow_sq and ch == "'"):
			q = ch; code += ch; i += 1; continue
		if ch == "#":
			break
		code += ch; i += 1
	return [code, lit]
