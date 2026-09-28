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
## 2026-09-28 第二轮又清掉 2 处(`↳`→`└ ` / `↻重载`→`重载`), 台账 4 处 → **2 处**,
##   只剩 `⊟` 那一个跨文件配对的按钮(见台账里的理由)。同轮还补了两个盲区:
##   ①扫描根从 `scripts/` 扩成 `scripts/` + `autoload/`
##   ②`\u`/`\U` 转义以前**整对跳过**(注释还写着"实测 0 个" —— 假的, 实有 1 个),
##     现在真解码。
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
##   · `SCAN_ROOTS` 下全部 `.gd`(= `scripts/` + `autoload/`), 只取**字符串字面量**里的字符
##     ★2026-09-28 把根从「只有 `scripts/`」扩成「`scripts/` + `autoload/`」——
##       `autoload/` 8 个 .gd 里有**真上屏文案**: `tutorial_director.gd:142-145` 的
##       `"装备买好了 → 去背包"` / `"看完了 → 打第二把 ▶"` 就是引导条上的字。
##       原来整个目录是**盲区**(不是"没问题", 是**没被看过**)。
##       单跑 `autoload/` 实测: 8 文件 / 514 含字面量行 / 58 个不同非 ASCII 码点 /
##       1 个三引号块 / **0 条豆腐块存量** —— 它用的 `→`(U+2192) 和 `▶`(U+25B6)
##       NotoSansSC 都有字形。扩根没照出新存量, 但盲区补上了。
##   · 去掉 `#` 注释(认引号里的 `#`, 否则 `"#ffd93d"` 会把整行吃掉)
##   · 去掉 `print/printerr/push_warning/push_error/print_rich` 的**整个实参表** ——
##     它们只进终端, 豆腐块不上屏。★按**括号深度**判, 不按行:
##     `battle_vfx_lab.gd:678` 的 `✗` 就在一个**跨 5 行**的 `print(` 里,
##     按行判会把它当成屏幕文案误报(第一版就误报了它)。
##   · 三引号块单独收: 本仓的 `"""…"""` 全是 **shader 源码**(里面 `//` 注释带中文),
##     不是屏幕文案 ⇒ 不计入, 但**断言它们确实都是 shader**(冒出别的就红)。
##   · `\uXXXX` / `\UXXXXXXXX` 转义**真解码**后进判据(见 `_scan_text` 里的长注释) ——
##     以前是整对跳过, 注释还写着"本仓实测 0 个", 而实测其实有 1 个。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★ 已知失明清单 —— 写在明面上。不写等于在宣称"没有盲区", 而那从来不成立
## ══════════════════════════════════════════════════════════════════════
## 下面这些形状这个扫描器**看不见**。不是"不会出问题", 是"出了也不会红":
##  ① **运行时拼出来的字符**: `char(cp)` / `String.chr(cp)` / `"%c" % cp` ——
##     源码里根本没有那个字符, 静态扫必漏。
##  ② **代理对写法**: 写成「反斜杠 u D83D」+「反斜杠 u DC22」这种 UTF-16
##     代理对的, 不会被合成成 U+1F422 —— 会被当成两个孤立的 D800 区码点(而那两个三张字体都没有 ⇒ 反而
##     **误报**)。本仓实测 0 处, 真出现了先改这里再说。
##  ③ **`scripts/` + `autoload/` 之外的上屏文本**: `.tscn` 节点的 `text=` 属性、
##     `.tres` 主题、`data/*.json` 的装备/龟名、`.csv` 翻译表。
##     2026-09-28 量过: 那四处对当时已知的 21 个无字形码点**命中 0** ——
##     但那是"今天没漏", 不是"以后不会漏"。`data/` 的 emoji 装备名另有
##     `verify_no_emoji_icons` 的**运行时**扫描盯着(那条看的是真跑起来的控件)。
##  ④ **拼接出来的组合字**: 零宽连接 / 变体选择符 / 组合音标单看每个码点都有字形,
##     合起来画不出来这个判据看不出。
##  ⑤ **注释里的字符**故意不算(它们不上屏)—— 但如果哪天有人把注释当文案 `print`
##     到界面上(比如塞进 RichTextLabel), 这条就从"正确"变成"失明"。
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

## 扫哪些根。★别只扫 `scripts/` —— `autoload/` 里也有上屏文案(引导词/存档提示),
## 漏一个目录 = 那个目录里的豆腐块永远照不出来(它不会红, 它只是**没被看过**)。
const SCAN_ROOTS := ["res://scripts", "res://autoload"]

## ── 豆腐块存量台账: 源文件 → [允许的无字形字符数, 为什么还留着] ──────────
## **只减不增**, 且实测数与登记数必须**相等**。
const TOFU_LEDGER := {
	## ★★2026-09-28 **台账现在是空的** —— 全仓玩家可见文案里没有一个豆腐块字符。
	##   空不等于这条判据没用: 它是**只减不增**的棘轮, 新写进一个没字形的字符当场红。
	##   分母见下面那几条断言(扫了多少文件/多少行/多少个不同码位) —— **分母为 0 才是空检查**。
	## ⚠ 往这里加条目之前先问一句: 是真的换不掉, 还是我不想换?
	##   跨文件配对那种(同一个按钮两处分居两个文件)**不是**加台账的理由, 是**两处一起换**的理由。
	## ── 已清掉的(留痕, 别再当"历史存量"往回加) ──────────────────────────
	## 2026-09-28 清掉 3 条/4 处:
	##   `battle_hud.gd:1674`  `↳ `(U+21B3) 召唤物缩进 → `└ `(U+2514, NotoSansSC 有)
	##   `map_editor.gd:90`    `↻重载`(U+21BB) → `重载`(同排「清空」「撤销」本就没图标, 去掉反而齐)
	##   `battle_hud.gd:1844` + `battle_debug_arena.gd:266`  `⊟ 折叠`(U+229F) → `▼ 折叠`
	##      —— **同一个按钮的两处, 分居两个文件**。只改一半 = 初始豆腐块、点一下变 ▼,
	##         比统一的豆腐块更像 bug ⇒ 两处同一个提交一起换。`▶`(U+25B6) 本来就有字形,
	##         所以换完展开/折叠两态都干净。字形是**两种独立探针**量过的
	##         (引擎侧 `FontFile.has_char` + fontTools 读 cmap, 两边结论一致)。
	## 2026-09-28 清掉 2 条/2 处:
	##   `battle_hud.gd:1674`  `↳ `(U+21B3) 召唤物缩进 → `└ `(U+2514, NotoSansSC 有)
	##      —— 与 `dmg_stats_panel.gd` 同语义处保持一致的写法。
	##   `map_editor.gd:90`    `↻重载`(U+21BB) → `重载`
	##      —— 直接去掉这个字符: 按钮上「重载」两个字已经把话说完, 而且同排的
	##         「清空」「撤销」本来就没有图标, 去掉反而齐了。
	##   ⇒ 台账从 4 处/3 个文件降到 2 处/2 个文件。
}

## 分母下限 —— 低于它说明扫描根本没跑起来, 下面的"0 个豆腐块"全是假的。
## 2026-09-28 扩根后实测 188 文件 / 19200 含字面量行 / 1269 码点, 下限随之抬紧一档
## (抬**下限**是把判据变严, 不是放宽)。留足余量: 别人正常删死码不该把它撞红;
## 而「某个根整体扫成 0」由 `empty_roots` 那条单独盯, 不靠这三个数。
const MIN_FILES := 170
const MIN_CODEPOINTS := 1000
const MIN_LIT_LINES := 14000

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
	print("=== 2. ★自动扫 scripts/ + autoload/ 下 **/*.gd 的字符串字面量, 逐个问三张字体 ===")
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
	##   ⑤`\uXXXX` / `\UXXXXXXXX` 转义解得开(以前是整对跳过 ⇒ 这一类**天生漏**)
	##   ⑥`\\`(转义的反斜杠)仍按**一对**吃掉 —— 否则它会把结尾的引号当成 `\"`,
	##     字符串就永远闭合不了, 后面的**注释**会被当字符串内容收进来。
	##     所以这一条用「结尾反斜杠 + 注释里放个 ⨯(U+2A2F)」来判: 收到了就说明闭合错了。
	var canary_src := "var a := \"✕tofu\"\n# ✗ comment only\nprint(\"✦ in print\")\nprint(\"x %s\" % [\n\t\"↻ multi-line print\"])\nvar e := \"\\u2718 esc4 \\U0001F600 esc8\"\nvar f := \"a\\\\\"  # ⨯ tail comment\n"
	var cres: Dictionary = _scan_text(canary_src, "canary")
	var ckeys: Array = (cres["cps"] as Dictionary).keys()
	_ok("★探子: 字面量里的 ✕ 被逮到", ckeys.has(0x2715), "收到 %d 个码点" % ckeys.size())
	_ok("★探子: 注释里的 ✗ 不算(注释不上屏)", not ckeys.has(0x2717))
	_ok("★探子: print 实参里的 ✦ 不算(只进终端)", not ckeys.has(0x2726))
	_ok("★探子: **跨行** print 实参里的 ↻ 也不算(按括号深度不按行)", not ckeys.has(0x21BB))
	_ok("★探子: `\\u2718` 4 位转义被解开并计入(U+2718)", ckeys.has(0x2718))
	_ok("★探子: `\\U0001F600` 8 位转义被解开并计入(U+1F600)", ckeys.has(0x1F600))
	_ok("★探子: 结尾 `\\\\` 按一对吃掉(字符串正常闭合 ⇒ 注释里的 ⨯ 没被收进来)", not ckeys.has(0x2A2F))

	## ── 真扫 ──
	var files := _all_gd(SCAN_ROOTS)
	## ★分母: 每个根都真的出了文件。少了这条, 哪天某个根写错字(或目录改名)
	##   就会静默变成"扫了 0 个文件"的空检查, 而总数仍被 scripts/ 撑着 ⇒ 照样全绿。
	var per_root: Dictionary = {}
	for p in files:
		for r in SCAN_ROOTS:
			if str(p).begins_with(str(r) + "/"):
				per_root[r] = int(per_root.get(r, 0)) + 1
	var empty_roots: Array = []
	for r in SCAN_ROOTS:
		if int(per_root.get(r, 0)) <= 0:
			empty_roots.append(str(r))
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

	var root_parts: Array = []
	for r in SCAN_ROOTS:
		root_parts.append("%s=%d" % [str(r).replace("res://", ""), int(per_root.get(r, 0))])
	print("  [分母] 扫了 %d 个 .gd (%s) · 含字面量的行 %d 行 · 不同非 ASCII 码点 %d 个 · 三引号块 %d 个"
		% [files.size(), " + ".join(root_parts), lit_lines, cps.size(), trip_blocks])
	print("  [结果] 三张字体都没有字形的码点 %d 个, 落在 %d 个文件里" % [tofu.size(), per_file.size()])
	for cp in tofu:
		var ws: Array = (cps[cp] as Dictionary).keys()
		ws.sort()
		print("     U+%04X 「%s」 ×%d 处%s" % [cp, char(int(cp)), ws.size(),
			("  " + ", ".join(ws)) if (_dump or ws.size() <= 4) else ""])

	_ok("★分母: 扫到的文件数 ≥ %d" % MIN_FILES, files.size() >= MIN_FILES, "%d 个" % files.size())
	_ok("★分母: SCAN_ROOTS 每个根都出了文件(没有哪个根静默扫成 0)", empty_roots.is_empty(),
		"%s%s" % [" + ".join(root_parts), ("; 空根: " + ", ".join(empty_roots)) if not empty_roots.is_empty() else ""])
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


func _all_gd(roots: Array) -> Array:
	var out: Array = []
	var dirs: Array = roots.duplicate()
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
					## ── 转义符 ──
					## ★★2026-09-28: 这里原来写着「本仓 scripts/ 实测 0 个 `\u`/`\U` 转义(已量)」
					##   然后**整对跳过**。那句话是**假的** —— 重新量了一遍(scripts/ + autoload/
					##   共 188 个 .gd)有 **1 个**: `scripts/gamedata/phase2_config.gd:745`
					##   里那个全角空格(写成「反斜杠 u 3000」; 实测 m6x11/NotoSansSC 都有字形,
					##   所以没漏成豆腐块, 但那是**运气**不是判据)。
					##   ⇒ 不再靠「实测 0 个」这个会烂的前提, 改成**真解码**: `\uXXXX`(4 位) /
					##     `\UXXXXXXXX`(8 位) 解出的码点照样进判据(canary 有自证)。
					var esc: String = src[i + 1] if i + 1 < n else ""
					var hexlen := 0
					if esc == "u":
						hexlen = 4
					elif esc == "U":
						hexlen = 8
					if hexlen > 0 and i + 2 + hexlen <= n:
						var hx: String = src.substr(i + 2, hexlen)
						if hx.is_valid_hex_number(false):
							var ecp := hx.hex_to_int()
							if ecp >= 0x80 and not in_log:
								if not cps.has(ecp):
									cps[ecp] = {}
								(cps[ecp] as Dictionary)["%s:%d" % [rel, line]] = true
								lit_line_seen["%s:%d" % [rel, line]] = true
							i += 2 + hexlen
							continue
					if esc == "\n":
						line += 1        # `\` 接真换行: 不数行号会让后面所有 file:line 偏
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
