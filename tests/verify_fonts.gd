extends Node
## verify_fonts.gd — 自证: 字体回退链覆盖 项目实际用到的全部 emoji/符号 + 常用中文。
## 跑法: godot --headless --path . res://tests/verify_fonts.tscn --quit-after 200
##
## ★关键: 测试构造的回退链【不含 SystemFont】 = 模拟 Web / Linux / 无系统字体的机器。
##   桌面 Windows 上 allow_system_fallback 会命中 Segoe UI Emoji 把问题盖住, 测了等于没测。
##
## 扫描口径: 只取【字符串字面量】里的字符(注释不渲染, 不计入)。
## 覆盖:
##  1. m6x11(打底) 单独扛不住中文/emoji  → 证明回退链是必需的(不是摆设)
##  2. 打包链 [m6x11 → NotoSansSC → NotoEmoji] 覆盖: 全部 %d 个项目实际用到的码点 + 常用中文
##  3. 主题 default_theme.tres 的 default_font 确实挂上了 emoji 回退

const USED_CODEPOINTS := [0x2190, 0x2192, 0x2194, 0x2605, 0x2620, 0x2660, 0x2663, 0x2665, 0x2666, 0x2693, 0x2694, 0x2699, 0x26A0, 0x26A1, 0x26B1, 0x26D1, 0x270F, 0x2713, 0x2716, 0x2728, 0x2744, 0x274C, 0x2764, 0x1F0CF, 0x1F308, 0x1F30A, 0x1F30B, 0x1F319, 0x1F327, 0x1F329, 0x1F32A, 0x1F33A, 0x1F33F, 0x1F343, 0x1F356, 0x1F36C, 0x1F381, 0x1F38B, 0x1F392, 0x1F3AD, 0x1F3AF, 0x1F3B0, 0x1F3B2, 0x1F3C6, 0x1F3CB, 0x1F3F0, 0x1F3F4, 0x1F3F9, 0x1F3FA, 0x1F40C, 0x1F419, 0x1F41A, 0x1F422, 0x1F432, 0x1F441, 0x1F465, 0x1F47B, 0x1F480, 0x1F48D, 0x1F48E, 0x1F497, 0x1F49A, 0x1F4A0, 0x1F4A2, 0x1F4A3, 0x1F4A5, 0x1F4A7, 0x1F4A8, 0x1F4B0, 0x1F4CA, 0x1F4CF, 0x1F4E1, 0x1F4E6, 0x1F4EF, 0x1F4FF, 0x1F504, 0x1F50A, 0x1F50C, 0x1F50D, 0x1F512, 0x1F517, 0x1F525, 0x1F527, 0x1F528, 0x1F529, 0x1F52B, 0x1F52D, 0x1F52E, 0x1F534, 0x1F535, 0x1F53C, 0x1F56F, 0x1F5E1, 0x1F5FF, 0x1F607, 0x1F608, 0x1F680, 0x1F6D2, 0x1F6E0, 0x1F6E1, 0x1F7E2, 0x1F916, 0x1F95A, 0x1F977, 0x1F988, 0x1F991, 0x1F994, 0x1F9A0, 0x1F9AA, 0x1F9E7, 0x1F9EA, 0x1F9F8, 0x1F9FF, 0x1FA78, 0x1FA99, 0x1FA9D, 0x1FAA8, 0x1FAB6, 0x1FAB8, 0x1FAE3, 0x1FAE7]

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ✓ ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  ✗ ", name, "  ", detail)

func _ready() -> void:
	var m6 := load("res://assets/fonts/m6x11.ttf") as FontFile
	var noto := load("res://assets/fonts/NotoSansSC-Regular.otf") as FontFile
	var emoji := load("res://assets/fonts/NotoEmoji-Regular.ttf") as FontFile
	if m6 == null or noto == null or emoji == null:
		print("✗ 字体文件加载失败"); get_tree().quit(1); return

	print("=== 0. 字体文件都在 ===")
	_ok("m6x11.ttf", m6 != null)
	_ok("NotoSansSC-Regular.otf", noto != null)
	_ok("NotoEmoji-Regular.ttf", emoji != null)

	print("=== 1. 打底字体单独扛不住 (证明回退链必需) ===")
	_ok("m6x11 无中文 '龟'", not m6.has_char(0x9F9F))
	_ok("m6x11 无 emoji 🐢", not m6.has_char(0x1F422))
	_ok("NotoSansSC 无 emoji 🐢 (它只有中文)", not noto.has_char(0x1F422))

	print("=== 2. 打包回退链 (无 SystemFont = 模拟 Web/Linux) ===")
	var chain := FontVariation.new()
	chain.base_font = m6
	chain.fallbacks = [noto, emoji]

	var missing: Array = []
	for cp in USED_CODEPOINTS:
		if not _chain_has(chain, int(cp)):
			missing.append(int(cp))
	_ok("项目实际用到的 %d 个 emoji/符号 全部有字形" % USED_CODEPOINTS.size(), missing.is_empty(), _fmt_missing(missing))

	var cjk := "龟深海币装备背包商店战斗技能被动主动升级赛季统领小将糖果罐临时等级器打碎奖励"
	var cjk_missing: Array = []
	for i in range(cjk.length()):
		if not _chain_has(chain, cjk.unicode_at(i)):
			cjk_missing.append(cjk.unicode_at(i))
	_ok("常用中文 %d 字 全部有字形" % cjk.length(), cjk_missing.is_empty(), _fmt_missing(cjk_missing))

	var ascii_ok := true
	for cp in range(0x20, 0x7F):
		if not _chain_has(chain, cp): ascii_ok = false
	_ok("ASCII 全覆盖", ascii_ok)

	print("=== 3. 主题 default_font 挂了 emoji 回退 ===")
	var th := load("res://assets/themes/default_theme.tres") as Theme
	_ok("主题加载成功", th != null)
	if th != null:
		var df: Font = th.default_font
		_ok("default_font 非空", df != null)
		if df is FontVariation:
			var fbs: Array = (df as FontVariation).fallbacks
			var has_emoji := false
			for f in fbs:
				if f is FontFile and str((f as FontFile).resource_path).ends_with("NotoEmoji-Regular.ttf"):
					has_emoji = true
			_ok("default_font 回退链含 NotoEmoji", has_emoji, "fallbacks=%d" % fbs.size())
			_ok("NotoEmoji 排在最后 (桌面优先系统彩色 emoji)", fbs.size() > 0 and (fbs[fbs.size() - 1] is FontFile) and str(fbs[fbs.size() - 1].resource_path).ends_with("NotoEmoji-Regular.ttf"))

	print("")
	if _fail == 0:
		print("ALL PASS — 字体回退链 (Web/Linux 无系统字体也不出豆腐块)")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## Font.has_char 只查自己; 手动沿回退链查
func _chain_has(fv: FontVariation, cp: int) -> bool:
	if (fv.base_font as Font).has_char(cp):
		return true
	for f in fv.fallbacks:
		if (f as Font).has_char(cp):
			return true
	return false


func _fmt_missing(a: Array) -> String:
	if a.is_empty(): return ""
	var s := "缺 %d 个: " % a.size()
	for i in range(mini(12, a.size())):
		s += "U+%04X(%s) " % [int(a[i]), char(int(a[i]))]
	return s
