extends Node
## verify_fonts.gd — 自证: 打包字体回退链覆盖【项目自己扫出来的】全部非 ASCII 字符。
## 跑法: godot --headless --path . res://tests/verify_fonts.tscn --quit-after 400
##       GLYPH_DUMP=1 …   额外打印每个码点出现在哪 (整改要清单, 不是个数)
##
## ★关键: 测试构造的回退链【不含 SystemFont】 = 模拟 Web / Linux / 无系统字体的机器。
##   桌面 Windows 上 allow_system_fallback 会命中 Segoe UI Emoji 把问题盖住, 测了等于没测。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★ 2026-09-28 整段重写: `USED_CODEPOINTS` 是**手抄名单** ⇒ 天生会漏
## ══════════════════════════════════════════════════════════════════════
## 旧版是一行硬编码的 121 个码点。名单是手抄的, 于是「用了一个没字形的字符」
## 这一整类**必然漏**。证据摆在名单里: `✖`(U+2716) **在**名单上, 而只差一个码位的
## `✕`(U+2715) **不在** —— 而恰恰是 U+2715 三张字体一张都没有, 屏幕上是豆腐块。
##
## 改成**自己扫**之后当场照出 6 个码点(旧名单一个都没盖到):
##   `✕`(U+2715) ×4处 / `✗`(U+2717) / `✦`(U+2726) / `↳`(U+21B3) ×2处 /
##   `↻`(U+21BB) / `⊟`(U+229F) ×2处
## 其中 4 处已换成有字形的写法(`× └ ◆`), 剩下的进下面的台账。
##
## ══════════════════════════════════════════════════════════════════════
##  判据: 不靠我列名单, 问字体文件
## ══════════════════════════════════════════════════════════════════════
## 一个码点在 `m6x11 / NotoSansSC / NotoEmoji` **三张里一张都没有** ⇒ 屏幕上是豆腐块。
## 有一张有 ⇒ 过。**不问它属于哪个 Unicode 区块, 不问它像不像 emoji** ——
## 那是「我说是就是」。(同一条判据在 `verify_no_emoji_icons.gd` 里用来分
## 「排版字符 vs emoji 图标」: 只有 NotoEmoji 有 = emoji。两处同一个事实源。)
##
## 扫描口径(每一条都会打分母, 见 §2 的 `[分母]` 行):
##   · `scripts/**/*.gd` 全部文件, 只取**字符串字面量**里的字符
##   · 去掉 `#` 注释(认引号里的 `#`, 否则 `"#ffd93d"` 会把整行吃掉)
##   · 去掉 `print/printerr/push_warning/push_error/print_rich` 的**整个实参表** ——
##     它们只进终端, 豆腐块不上屏。★按**括号深度**判, 不按行:
##     `battle_vfx_lab.gd:678` 的 `✗` 就在一个**跨 5 行**的 `print(` 里,
##     按行判会把它当成屏幕文案误报(第一版就误报了它)。
##   · 三引号块单独收: 本仓的 `"""…"""` 全是 **shader 源码**(里面 `//` 注释带中文),
##     不是屏幕文案 ⇒ 不计入, 但**断言它们确实都是 shader**(冒出别的就红)。
##
## ══════════════════════════════════════════════════════════════════════
##  台账 = 棘轮, 每条带理由。**只减不增**(照 `tools/glow_ball_audit.py` 的形状)
## ══════════════════════════════════════════════════════════════════════
## 扩判据一定照出存量。存量按**文件**记账: 修好一处就把数字改小; 新增一处当场红;
## **修好了不改小也红**(否则台账会留下一个静默的洞)。
## 不写理由的白名单和放宽判据是一回事 ⇒ 每条都写清为什么还留着。

const FONTS := {
	"m6x11": "res://assets/fonts/m6x11.ttf",
	"NotoSansSC": "res://assets/fonts/NotoSansSC-Regular.otf",
	"NotoEmoji": "res://assets/fonts/NotoEmoji-Regular.ttf",
}

## 只进终端的调用 —— 它们的**整个实参表**(按括号深度)都不算屏幕文案。
const LOG_CALLS := ["print", "printerr", "push_warning", "push_error", "print_rich", "printt", "prints"]

## ── 豆腐块存量台账: 源文件 → [允许的无字形字符数, 为什么还留着] ──────────
## **只减不增**, 且实测数与登记数必须**相等**。
const TOFU_LEDGER := {
	## `⊟ 折叠`(U+229F)。★为什么没换: 这个按钮的【创建处】在 `battle_hud.gd:1844`、
	##   【切换处】在 `battle_debug_arena.gd:266`, **分居两个文件**, 而本轮地盘只有后者
	##   ⇒ 只改一半 = 同一个按钮初始显示豆腐块、点一下变 `▼`, 比统一的豆腐块更像 bug。
	##   两处要一起换成 `▼ 折叠`(已实测 `▼` U+25BC 在 NotoSansSC 里)。
	##   而且它只在 `DEBUG_EDIT` 调试场里建, **不是玩家路径**。
	"scripts/scenes/battle/battle_debug_arena.gd": [1, "⊟ 折叠(U+229F) ×1 —— 配对的创建处在 battle_hud.gd, 不在本轮地盘; 且仅 DEBUG_EDIT 调试场"],
	## `↳`(U+21B3) 召唤物缩进标记 ×1 + `⊟ 折叠`(U+229F) ×1。
	## ★同一语义的 `↳` 在 `dmg_stats_panel.gd` 里本轮已换成 `└ `(U+2514, NotoSansSC 里有),
	##   这一处照同样改法即可 —— 只是 `battle_hud.gd` 不在本轮地盘。
	"scripts/scenes/battle/battle_hud.gd": [2, "↳ 召唤缩进(U+21B3) ×1 + ⊟ 折叠(U+229F) ×1 —— 文件不在本轮地盘, 改法已定(└ / ▼)"],
	## `↻重载`(U+21BB)。MAPEDIT 地图编辑器, 开发工具, 玩家进不去; 且不在本轮地盘。
	## 改法: 直接去掉这个字符 —— 按钮上「重载」两个字已经把话说完了。
	"scripts/scenes/map_editor.gd": [1, "↻ 重载(U+21BB) ×1 —— MAPEDIT 地图编辑器(开发工具), 且不在本轮地盘"],
}

## 分母下限 —— 低于它说明扫描根本没跑起来, 下面的"0 个豆腐块"全是假的。
const MIN_FILES := 150
const MIN_CODEPOINTS := 800
const MIN_LIT_LINES := 10000

var _pass := 0
var _fail := 0
var _dump: bool = OS.get_environment("GLYPH_DUMP") != ""
var _f: Dictionary = {}
var _cache: Dictionary = {}


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s%s" % [nm, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


func _ready() -> void:
	# ══════════════════════════════════════════════════════════════════
	print("=== 0. 三张打包字体 + ★字体真加载到了(拿不到字体 has_char 全 false ⇒ 判据恒绿) ===")
	var loaded := 0
	for k in FONTS.keys():
		var ff := load(str(FONTS[k])) as FontFile
		_f[k] = ff
		if ff != null:
			loaded += 1
		_ok("%s 加载成功" % k, ff != null)
	_ok("★分母: 三张字体全加载到了", loaded == FONTS.size(), "%d/%d" % [loaded, FONTS.size()])
	if loaded != FONTS.size():
		print("\nFAIL x%d — 字体都拿不到, 后面全是空检查, 提前退出" % _fail)
		get_tree().quit(1)
		return

	## ★正向对照: 每张字体各给一个**它一定有**的字符。全 false 说明 has_char 本身废了
	##   (那时"三张都没有"会对每个码点成立 ⇒ 门禁恒红; 反之若恒 true 则恒绿)。
	_ok("★分母: m6x11 有 'A'", (_f["m6x11"] as FontFile).has_char(0x41))
	_ok("★分母: NotoSansSC 有 '龟'", (_f["NotoSansSC"] as FontFile).has_char(0x9F9F))
	_ok("★分母: NotoEmoji 有 '🐢'", (_f["NotoEmoji"] as FontFile).has_char(0x1F422))
	## 反向对照: 每张字体各给一个**它一定没有**的字符 —— 否则 has_char 恒 true。
	_ok("★分母: m6x11 没有 '龟'(证明 has_char 不是恒 true)", not (_f["m6x11"] as FontFile).has_char(0x9F9F))
	_ok("★分母: NotoSansSC 没有 '🐢'", not (_f["NotoSansSC"] as FontFile).has_char(0x1F422))
	_ok("★分母: NotoEmoji 没有 'A'", not (_f["NotoEmoji"] as FontFile).has_char(0x41))

	# ══════════════════════════════════════════════════════════════════
	print("=== 1. 打底字体单独扛不住 (证明回退链是必需的, 不是摆设) ===")
	var m6 := _f["m6x11"] as FontFile
	var noto := _f["NotoSansSC"] as FontFile
	_ok("m6x11 无中文 '龟'", not m6.has_char(0x9F9F))
	_ok("m6x11 无 emoji 🐢", not m6.has_char(0x1F422))
	_ok("NotoSansSC 无 emoji 🐢 (它只有中文)", not noto.has_char(0x1F422))

	# ══════════════════════════════════════════════════════════════════
	print("=== 2. ★自动扫 scripts/**/*.gd 的字符串字面量, 逐个问三张字体 ===")
	## 分类器自证: 喂几个已知答案进去, 判据必须分得开。
	##   (旧版这里是一行手抄名单 ⇒ 名单漏了就等于没测, 没有任何一条能照出来。)
	_ok("★分类器自证: `×`(U+00D7) 有字形(m6x11 里就有)", _has_glyph(0x00D7))
	_ok("★分类器自证: `★`(U+2605) 有字形(NotoSansSC 里)", _has_glyph(0x2605))
	_ok("★分类器自证: `🐢`(U+1F422) 有字形(NotoEmoji 里)", _has_glyph(0x1F422))
	_ok("★分类器自证: `✕`(U+2715) 判成**没有字形**", not _has_glyph(0x2715))
	_ok("★分类器自证: 汉字 `龟` 有字形", _has_glyph(0x9F9F))

	## 扫描器自证(探子): 喂一段合成源码, 断言它
	##   ①逮到字面量里的豆腐块 ②不把注释里的算进来 ③不把 print 实参算进来
	##   ④跨行的 print 实参也不算(按括号深度, 不按行)。
	var canary_src := "var a := \"✕tofu\"\n# ✗ comment only\nprint(\"✦ in print\")\nprint(\"x %s\" % [\n\t\"↻ multi-line print\"])\n"
	var cres: Dictionary = _scan_text(canary_src, "canary")
	var ckeys: Array = (cres["cps"] as Dictionary).keys()
	_ok("★探子: 字面量里的 ✕ 被逮到", ckeys.has(0x2715), "收到 %d 个码点" % ckeys.size())
	_ok("★探子: 注释里的 ✗ 不算(注释不上屏)", not ckeys.has(0x2717))
	_ok("★探子: print 实参里的 ✦ 不算(只进终端)", not ckeys.has(0x2726))
	_ok("★探子: **跨行** print 实参里的 ↻ 也不算(按括号深度不按行)", not ckeys.has(0x21BB))

	## ── 真扫 ──
	var files := _all_gd("res://scripts")
	var cps: Dictionary = {}        # cp -> {"file:line": true}
	var per_file: Dictionary = {}   # rel -> 无字形字符出现次数
	var lit_lines := 0
	var trip_blocks := 0
	var trip_bad: Array = []
	for p in files:
		var src := FileAccess.get_file_as_string(p)
		if src == "":
			continue
		var rel: String = str(p).replace("res://", "")
		var r: Dictionary = _scan_text(src, rel)
		lit_lines += int(r["lit_lines"])
		trip_blocks += (r["triples"] as Array).size()
		for t in (r["triples"] as Array):
			## 三引号块必须是 shader 源码 —— 冒出别的就得单独看, 别悄悄放过。
			if str(t).find("shader_type") < 0:
				trip_bad.append("%s 的三引号块不含 shader_type(前 40 字: %s)" % [rel, str(t).substr(0, 40)])
		for cp in (r["cps"] as Dictionary).keys():
			if not cps.has(cp):
				cps[cp] = {}
			for w in ((r["cps"] as Dictionary)[cp] as Dictionary).keys():
				(cps[cp] as Dictionary)[w] = true

	var tofu: Array = []
	for cp in cps.keys():
		if not _has_glyph(int(cp)):
			tofu.append(int(cp))
	tofu.sort()
	for cp in tofu:
		for w in (cps[cp] as Dictionary).keys():
			var rel2: String = str(w).substr(0, str(w).rfind(":"))
			per_file[rel2] = int(per_file.get(rel2, 0)) + 1

	print("  [分母] 扫了 %d 个 .gd · 含字面量的行 %d 行 · 不同非 ASCII 码点 %d 个 · 三引号块 %d 个"
		% [files.size(), lit_lines, cps.size(), trip_blocks])
	print("  [结果] 三张字体都没有字形的码点 %d 个, 落在 %d 个文件里" % [tofu.size(), per_file.size()])
	for cp in tofu:
		var ws: Array = (cps[cp] as Dictionary).keys()
		ws.sort()
		print("     U+%04X 「%s」 ×%d 处%s" % [cp, char(int(cp)), ws.size(),
			("  " + ", ".join(ws)) if (_dump or ws.size() <= 4) else ""])

	_ok("★分母: 扫到的文件数 ≥ %d" % MIN_FILES, files.size() >= MIN_FILES, "%d 个" % files.size())
	_ok("★分母: 含字面量的行数 ≥ %d" % MIN_LIT_LINES, lit_lines >= MIN_LIT_LINES, "%d 行" % lit_lines)
	_ok("★分母: 收集到的不同非 ASCII 码点 ≥ %d" % MIN_CODEPOINTS, cps.size() >= MIN_CODEPOINTS, "%d 个" % cps.size())
	## ★分母: 三引号块真被认出来了。少了这一条, 把三引号当普通字符串收
	##   也能全绿 —— 因为 shader 里的中文注释那些字**都有字形**,
	##   于是 "全是 shader 源码" 变成了 0/0 的空检查(反向验证当场抄出来的)。
	_ok("★分母: 真认出了三引号块(否则下一条是 0/0 空检查)", trip_blocks >= 3, "%d 个" % trip_blocks)
	_ok("三引号块全是 shader 源码(不是屏幕文案)", trip_bad.is_empty(),
		"%d 个块; 例外: %s" % [trip_blocks, ", ".join(trip_bad)])

	# ── 台账棘轮: 只减不增, 且实测 == 登记 ──
	var bad: Array = []
	for rel in per_file.keys():
		var got := int(per_file[rel])
		if not TOFU_LEDGER.has(rel):
			bad.append("%s: 豆腐块 %d 处, **不在台账里** —— 新增的当场红" % [rel, got])
		elif got > int((TOFU_LEDGER[rel] as Array)[0]):
			bad.append("%s: 豆腐块 %d 处 > 台账 %d 处 —— **新增了**" % [rel, got, int((TOFU_LEDGER[rel] as Array)[0])])
	for rel in TOFU_LEDGER.keys():
		var want := int((TOFU_LEDGER[rel] as Array)[0])
		var got2 := int(per_file.get(rel, 0))
		if got2 < want:
			bad.append("%s: 豆腐块只剩 %d 处(台账写着 %d) —— 修好了就把台账改小, 棘轮只减不增" % [rel, got2, want])
	var ledger_total := 0
	for rel in TOFU_LEDGER.keys():
		ledger_total += int((TOFU_LEDGER[rel] as Array)[0])
	_ok("豆腐块台账对得上(只减不增)", bad.is_empty(),
		"台账 %d 处/%d 个文件, 实测 %d 处/%d 个文件%s" % [ledger_total, TOFU_LEDGER.size(),
			tofu_count(per_file), per_file.size(), ("\n        " + "\n        ".join(bad)) if not bad.is_empty() else ""])

	# ══════════════════════════════════════════════════════════════════
	print("=== 3. 回退链还得覆盖常用中文 + 全 ASCII ===")
	var chain := FontVariation.new()
	chain.base_font = m6
	chain.fallbacks = [noto, _f["NotoEmoji"]]
	var cjk := "龟深海币装备背包商店战斗技能被动主动升级赛季统领小将糖果罐临时等级器打碎奖励"
	var cjk_missing := 0
	for i in range(cjk.length()):
		if not _chain_has(chain, cjk.unicode_at(i)):
			cjk_missing += 1
	_ok("常用中文 %d 字 全部有字形" % cjk.length(), cjk_missing == 0, "缺 %d 个" % cjk_missing)
	var ascii_missing := 0
	for cp in range(0x20, 0x7F):
		if not _chain_has(chain, cp):
			ascii_missing += 1
	_ok("ASCII 0x20~0x7E 全覆盖", ascii_missing == 0, "缺 %d 个" % ascii_missing)
	## ★这条证明 `_chain_has` 不是恒 true: 一个三张都没有的字符必须查不到。
	_ok("★分母: 回退链查 `✕`(U+2715) 必须查不到(证明 _chain_has 不恒 true)", not _chain_has(chain, 0x2715))

	# ══════════════════════════════════════════════════════════════════
	print("=== 4. 主题 default_font 挂了 emoji 回退 ===")
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
			_ok("NotoEmoji 排在最后 (桌面优先系统彩色 emoji)",
				fbs.size() > 0 and (fbs[fbs.size() - 1] is FontFile)
				and str(fbs[fbs.size() - 1].resource_path).ends_with("NotoEmoji-Regular.ttf"))

	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d) — 字体回退链: 项目自己扫出来的字符在 Web/Linux 也不出豆腐块"
			% [_pass, _pass + _fail])
	else:
		print("FAIL x%d  (%d/%d)" % [_fail, _pass, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func tofu_count(per_file: Dictionary) -> int:
	var t := 0
	for k in per_file.keys():
		t += int(per_file[k])
	return t


## ★判据本体: 三张打包字体里有没有任何一张能画出这个码点。
func _has_glyph(cp: int) -> bool:
	if _cache.has(cp):
		return bool(_cache[cp])
	var r := false
	for k in FONTS.keys():
		if (_f[k] as FontFile).has_char(cp):
			r = true
			break
	_cache[cp] = r
	return r


## Font.has_char 只查自己; 手动沿回退链查(用来验回退链本身接对了)。
func _chain_has(fv: FontVariation, cp: int) -> bool:
	if (fv.base_font as Font).has_char(cp):
		return true
	for f in fv.fallbacks:
		if (f as Font).has_char(cp):
			return true
	return false


func _all_gd(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var d: String = str(dirs.pop_back())
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if da.current_is_dir():
				if not f.begins_with("."):
					dirs.append(d + "/" + f)
			elif f.ends_with(".gd"):
				out.append(d + "/" + f)
			f = da.get_next()
		da.list_dir_end()
	out.sort()
	return out


## ══════════════════════════════════════════════════════════════════════
##  扫描器: 整份源码走一遍字符状态机
## ══════════════════════════════════════════════════════════════════════
## 为什么不按行: `print(` 的实参可以跨好几行(`battle_vfx_lab.gd:674-678` 就跨 5 行),
## 按行判会把它的 `✗` 当成屏幕文案。改成**按括号深度**: 记住每个 log 调用在哪一层开的,
## 深度回到那一层之前所有字面量都只进终端。
## 返回 {cps: {cp: {"file:line": true}}, lit_lines: int, triples: [块正文]}
func _scan_text(src: String, rel: String) -> Dictionary:
	var cps: Dictionary = {}
	var triples: Array = []
	var lit_line_seen: Dictionary = {}
	var n := src.length()
	var i := 0
	var line := 1
	var depth := 0
	var log_levels: Array = []     # 每个 log 调用开括号时的外层深度
	var word := ""                 # 刚扫过的标识符(判 `print(` 用)
	while i < n:
		var ch := src[i]
		# ── 三引号块: 本仓全是 shader 源码, 单独收, 不计入屏幕文案 ──
		if ch == "\"" and i + 2 < n and src[i + 1] == "\"" and src[i + 2] == "\"":
			var e := src.find("\"\"\"", i + 3)
			if e < 0:
				e = n
			var body := src.substr(i + 3, e - i - 3)
			triples.append(body)
			for c in body:
				if c == "\n":
					line += 1
			i = e + 3
			word = ""
			continue
		# ── 普通字符串(双引号 / 单引号, 由**开引号**决定谁能闭合) ──
		if ch == "\"" or ch == "'":
			var q := ch
			var in_log: bool = not log_levels.is_empty()
			i += 1
			while i < n:
				var c2 := src[i]
				if c2 == "\\":
					## 转义符: 本仓 scripts/ 实测 0 个 `\u`/`\U` 转义(已量), 整对跳过。
					i += 2
					continue
				if c2 == q:
					i += 1
					break
				if c2 == "\n":
					line += 1
					i += 1
					continue
				var cp := src.unicode_at(i)
				if cp >= 0x80 and not in_log:
					if not cps.has(cp):
						cps[cp] = {}
					(cps[cp] as Dictionary)["%s:%d" % [rel, line]] = true
					lit_line_seen["%s:%d" % [rel, line]] = true
				elif cp >= 0x20 and not in_log:
					lit_line_seen["%s:%d" % [rel, line]] = true
				i += 1
			word = ""
			continue
		# ── 注释: 到行末 ──
		if ch == "#":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if ch == "\n":
			line += 1
			i += 1
			word = ""
			continue
		if ch == "(":
			if LOG_CALLS.has(word):
				log_levels.append(depth)
			depth += 1
			word = ""
			i += 1
			continue
		if ch == ")":
			depth -= 1
			while not log_levels.is_empty() and depth <= int(log_levels[log_levels.size() - 1]):
				log_levels.pop_back()
			word = ""
			i += 1
			continue
		if _is_word_char(ch):
			word += ch
		else:
			word = ""
		i += 1
	return {"cps": cps, "lit_lines": lit_line_seen.size(), "triples": triples}


func _is_word_char(ch: String) -> bool:
	return ch == "_" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")
