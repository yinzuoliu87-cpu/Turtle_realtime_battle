extends Node

## verify_glyph_coverage.gd — 屏幕文案里的每个字, 打包字体里都有字形; 比分不许写成会糊成一团的「1:1」(2026-10-21)
##
## 由来(主会话自审 v4 首启介绍截图): 第 2 页「赢两个战场获胜，1:1 进入终极战场」在屏上读成「11」。
##   查实**不是缺字**: 全局主题回退链 m6x11 → NotoSansSC → (SystemFont) → NotoEmoji, 半角「:」由 m6x11 画,
##   而 m6x11 的冒号前进宽只有 192/1024(数字 448/1024), 夹在两个细「1」中间就并成一个「11」。
##   ⇒ 比分一律写「1 : 1」(与结算卡「我方 %d : %d 对方」同一写法)。
## 量:
##   ① 语料 = 产品文案快照(tests/golden/gd_text_snapshot.txt 屏幕侧 + text_snapshot.txt 数据侧)+ data/tutorial-steps.json
##      —— 快照由 tools/text_golden.py 从代码 / json 自动生成, 不是手抄; 语料不足 ⇒ 判红(空检查)
##   ② 每个字都在打包字体里(m6x11 / NotoSansSC / NotoEmoji, 从项目主题的回退链读, 去掉 SystemFont ——
##      iOS 上没有系统字体, 见 scripts/util/font_kit.gd)。缺字 ⇒ 列出字与出处
##   ③ 单个数字夹半角冒号(「1:1」这种比分)= 0 处(时间「19:00」不算)
##   ④ 尺子自检: 一个肯定缺的字(U+0378 未分配码位)会被判成缺; 一句「比分 1:1」会被 ③ 抓到

const THEME := "res://assets/themes/default_theme.tres"
const SNAP_GD := "res://tests/golden/gd_text_snapshot.txt"
const SNAP_DATA := "res://tests/golden/text_snapshot.txt"
const STEPS := "res://data/tutorial-steps.json"
## 不是要画出来的字: 变体选择符 / 零宽连接(彩色 emoji 序列的胶水)/ 零宽空格。
const SKIP_CODES := [0xFE0F, 0xFE0E, 0x200D, 0x200B]
## 玩家看不到的开发工具屏(只在环境变量打开时出现)—— 每条写清理由。
const DEV_ONLY := {
	"scripts/scenes/battle/battle_vfx_lab.gd": "VFXLAB 特效调试台, 全程 OS.has_environment(\"VFXLAB\") 闸(文件头注), 正式对局零影响",
}

var _fail := 0
var _n := 0
const MIN_ASSERTS := 8
var _fonts: Array = []
var _ratio := RegEx.create_from_string("(?<![0-9])[0-9]:[0-9](?![0-9])")


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var th: Theme = load(THEME)
	_collect(th.default_font if th != null else null)
	var names: Array = []
	for f in _fonts:
		names.append(str((f as FontFile).resource_path.get_file()))
	_ok("★分母: 打包字体回退链读到了(m6x11 + NotoSansSC + NotoEmoji)", _fonts.size() >= 3
		and "m6x11.ttf" in names and "NotoSansSC-Regular.otf" in names, str(names))
	## 原因写进门禁: m6x11 的半角冒号比数字窄得多(这就是 ③ 的理由; 换了字体这条会提醒重新评估 ③)
	var m6: FontFile = load("res://assets/fonts/m6x11.ttf")
	var w_col: float = m6.get_string_size(":", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var w_one: float = m6.get_string_size("1", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	print("    [m6x11] 「:」宽 %.1f · 「1」宽 %.1f (32px)" % [w_col, w_one])
	_ok("m6x11 的半角冒号确实很窄(③ 的依据)", w_col > 0.0 and w_col < w_one * 0.6, "%.1f vs %.1f" % [w_col, w_one])

	var segs := _corpus()
	var chars := {}
	for sg in segs:
		for ch in str(sg[1]):
			chars[ch] = true
	print("    [语料] %d 段 · %d 种字" % [segs.size(), chars.size()])
	_ok("★分母: 语料 ≥ 2000 段、≥ 1000 种字(空检查不算过)", segs.size() >= 2000 and chars.size() >= 1000)

	## ② 缺字
	var missing := {}
	for sg in segs:
		for ch in str(sg[1]):
			if not _covered(ch) and not missing.has(ch):
				missing[ch] = "%s 「%s」" % [str(sg[0]), str(sg[1]).substr(0, 30)]
	var lines: Array = []
	for ch in missing.keys():
		lines.append("U+%04X「%s」← %s" % [str(ch).unicode_at(0), ch, missing[ch]])
	for l in lines.slice(0, 20):
		print("    [缺字] " + str(l))
	_ok("★★屏幕文案里每个字都在打包字体里有字形", missing.is_empty(), "%d 个字缺" % missing.size())

	## ③ 比分冒号
	var hits: Array = []
	for sg in segs:
		if _ratio.search(str(sg[1])) != null:
			hits.append("%s「%s」" % [str(sg[0]), str(sg[1]).substr(0, 40)])
	for h in hits.slice(0, 20):
		print("    [比分] " + str(h))
	_ok("★★没有「1:1」式比分(m6x11 冒号太窄会读成「11」; 写「1 : 1」)", hits.is_empty(), "%d 处" % hits.size())

	## ④ 尺子自检
	_ok("尺子自检: 未分配码位 U+0378 判成缺字", not _covered(String.chr(0x0378)))
	_ok("尺子自检: 「比分 1:1」会被 ③ 抓到、「1 : 1」与「19:00」不会", _ratio.search("比分 1:1") != null
		and _ratio.search("比分 1 : 1") == null and _ratio.search("周日 19:00 开始") == null)
	_ok("尺子自检: 中文 / 数字 / 全角标点都判成有", _covered("赢") and _covered("1") and _covered("，") and _covered("："))

	print("  (共 %d 条断言)" % _n)
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 屏幕文案字形全覆盖 · 无糊成一团的比分冒号" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 主题默认字体 + 回退链(深度优先), 只收打包的 FontFile。
func _collect(f: Font) -> void:
	if f == null:
		return
	if f is FontFile and not (f in _fonts):
		_fonts.append(f)
	if f is FontVariation and (f as FontVariation).base_font != null:
		_collect((f as FontVariation).base_font)
	for fb in f.fallbacks:
		if fb is SystemFont:
			continue
		_collect(fb)


func _covered(ch: String) -> bool:
	var c: int = ch.unicode_at(0)
	if c < 0x20 or c in SKIP_CODES:
		return true
	for f in _fonts:
		if (f as FontFile).has_char(c):
			return true
	return false


## [出处, 文案] 列表。快照里的「\n」是两个字(反斜杠 + n), 先还原成换行。
func _corpus() -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(SNAP_GD).split("\n"):
		var parts := line.split("|", true, 2)
		if parts.size() == 3 and not DEV_ONLY.has(parts[0]):
			out.append([parts[0], parts[2].replace("\\n", "\n").strip_edges(false, true)])
	for line in FileAccess.get_file_as_string(SNAP_DATA).split("\n"):
		var parts := line.split("|", true, 3)
		if parts.size() == 4:
			out.append(["%s|%s|%s" % [parts[0], parts[1], parts[2]], parts[3].replace("\\n", "\n").strip_edges(false, true)])
	var steps = JSON.parse_string(FileAccess.get_file_as_string(STEPS))
	if steps is Dictionary:
		for k in (steps as Dictionary).keys():
			if str(k).begins_with("_") or not (steps[k] is Array):
				continue
			for st in steps[k]:
				if st is Dictionary:
					out.append(["tutorial-steps.json|" + str(k), str(st.get("text", ""))])
	return out
