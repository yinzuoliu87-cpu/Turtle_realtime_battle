extends Node
## verify_no_emoji_icons.gd — 「屏幕上不许拿 emoji 当图标」的存量台账门禁 (2026-09-28)
##
## ═══════════════════════════════════════════════════════════════════════
##  ★★ 为什么有这个东西
## ═══════════════════════════════════════════════════════════════════════
## 用户 2026-09-27:「一点也看不出来游戏的味道, 全是 ai 味和网页味」。
## 实拍量下来, 最刺眼的**单一来源**是: 全项目拿 emoji 当图标 —— 52 种 / 176 次。
##
## emoji 不是我们画的。它由**系统/回退字体**渲染:
##   · 🐢 是平滑抗锯齿的**彩色矢量**
##   · ⚔ 是**单色线条**
##   · 而我们的 UI 是 **3~4px 的像素笔触**
## ⇒ **同一块屏上三种画法**。这不是审美意见, 是可量的。
##
## ═══════════════════════════════════════════════════════════════════════
##  ★★★ 判据: 不问我的眼睛, 问字体文件
## ═══════════════════════════════════════════════════════════════════════
## 「什么算 emoji 图标」这件事, 我第一版是手写一张 Unicode 区块表 —— 那等于
## **我说是就是**, 而且当场把 `★ ✓ ⚠ → ·` 全判成了 emoji(176 次里一大半)。
##
## 真判据摆在仓库里: 打包字体回退链是 `m6x11 → NotoSansSC → NotoEmoji`
## (见 `tests/verify_fonts.gd` 与 `default_theme.tres`)。于是 ——
##
##   **一个码点, 只有 NotoEmoji 有、前两张都没有 ⇒ 它在屏幕上就是 emoji 字体画的。**
##
## 逐张字体 `has_char()` 问出来的结果(实测):
##   · `★ ☆ ✓ ⚠ ♥ ▶ → ·` 全在 **NotoSansSC** 里 ⇒ 和正文**同一套字**, 不算 emoji。
##     (所以装备星级 `★★★`、警示 `⚠`、勾 `✓` 本门禁一个都不碰 —— 它们是排版字符。)
##   · `🐢 🔒 💀 ⚔ ⚙ ❌ 📦 🍬 …` 只有 **NotoEmoji** 有 ⇒ 正是要清的那一类。
## ⇒ 判据**刚好卡住那个形状**: 不是"一个 emoji 都不许有", 是"别拿另一套字当图标"。
##
## ═══════════════════════════════════════════════════════════════════════
##  两条互补的判据(各自带分母)
## ═══════════════════════════════════════════════════════════════════════
## ① **运行时**: 逐屏实例化 → 走真实节点树 → 收所有【可见控件】的 `text`/`tooltip_text`。
##    这一条能看见"拼出来的"字(`"%s %s" % [emoji_of(t), name]`), 源码扫描看不见。
##    ★而且**主动把"点了才出现"的界面催出来**: 底部操作条 / 糖果罐弹框 / 装备详情 /
##      重置确认框 / 邮箱对话框 / 图鉴五个页签的详情 / 撮合的"已匹配"那一屏。
##      上一轮四个屏栽在同一个形状上 —— 判据在静止页恒绿, 反向验证也照样被骗过去。
## ② **静态**: 扫 `scripts/scenes/**` 的字符串字面量(去注释、去 print 行), 按文件记账。
##    它覆盖那些**本门禁没实例化**的屏(战斗 HUD / 商店 / 主菜单 …), 不用把它们建起来。
##
## ═══════════════════════════════════════════════════════════════════════
##  ★ 台账 = 棘轮, 每条带理由。**只许降不许升。**
## ═══════════════════════════════════════════════════════════════════════
## 照本仓 `tools/glow_ball_audit.py` / `vfx_discipline_debt.json` /
## `tests/verify_ui_consistency.gd` 的 `BASE` 同一个形状。
## **不写理由的白名单和放宽判据是一回事** —— 所以每一条后面都写清为什么还留着。
##
## ═══════════════════════════════════════════════════════════════════════
##  ★★★ 分母 —— 三层, 缺一层这份门禁就可能是空检查
## ═══════════════════════════════════════════════════════════════════════
## ① **探子(canary)**: 每一屏量之前, 先往它的树上挂一个写着 🐢 的 Label,
##    断言扫描器**真的逮到它**, 然后摘掉再正式量。
##    ⇒ 这一条证明的是「**这一屏上如果有 emoji, 判据看得见**」——
##      而不是「这一屏恰好没有 emoji, 所以绿」。两种可能答案不会再碰巧相同。
##    (由来: 战斗那边一条老判据拿 `atk_interval = 1.0` 当样本, 而 1.0 下
##     速率和间隔数值相同 ⇒ 判据根本分不开这两者, 一直靠文案在撑。同一个坑。)
## ② **文本量**: 每屏至少扫到 N 条带字的控件, 少于它 = 屏没建起来(本仓栽过 6 次)。
## ③ **分类器自证**: 直接喂它 🐢 / ★ / ⚠ / 汉字, 断言只有 🐢 被判成 emoji。
##    再断言三张字体文件都真的加载到了(拿不到字体时 `has_char` 全 false ⇒ 判据会恒绿)。
##
## 跑法:
##   godot --headless --path . res://tests/verify_no_emoji_icons.tscn --quit-after 8000
##   EMOJI_DUMP=1 …  额外打印每一处命中的【是谁】(整改要的是清单, 不是个数)

const FONT_PIXEL := "res://assets/fonts/m6x11.ttf"
const FONT_CJK := "res://assets/fonts/NotoSansSC-Regular.otf"
const FONT_EMOJI := "res://assets/fonts/NotoEmoji-Regular.ttf"

## ── ① 运行时台账: 屏 → [允许的 emoji 字符数上限, 理由] ──────────────
## **只许降不许升。** 想放大必须先说服自己那不是回归。
const SCREEN_LEDGER: Dictionary = {
	## 图鉴。剩下的全是**装备类型图标**(剑/奇械/食物/盾/药水/枪/弓箭/法器/灵物/香火/遗物),
	## 见 `CodexScene.TYPE_STYLE` 与 `Phase2Types.TYPE_EMOJI`。
	## ★为什么没换: `assets/sprites/tags/` 是**空目录** —— 这 11~12 张类型标签图
	##   一张都还没画。素材铁律是「不拿语义不符的图顶替」, 所以只能等新素材。
	##   它同时喂着 图鉴/背包羁绊栏/选龟羁绊栏/商店/战斗 HUD 五处, 是本轮最大的一块缺口。
	## ★数字口径 = 一次扫描里出现的 emoji **字符数**(同一类型在页签/详情各出现一次也各算一次),
	##   所以它随"当前选中哪一条"浮动 ⇒ 取实测上沿。
	"Codex": [38, "类型图标(tags/ 未画) + data/equipment.json 里 5 件消耗品名字自带 emoji + 🛠(debug 构建)"],
	## ⚠★★ Codex 这 38 个里有 **5 个根本不在任何 .gd 里** —— 它们在
	##   `data/equipment.json` 的 **`name` 字段**里: 「🔥 怒火药水」「⛑ 应急护盾」
	##   「🌿 急救包」「✨ 净化」「🎯 必中标记」(5 件消耗品)。
	##   ★这正是【运行时扫描】比【源码扫描】多拿到的一类: 源码里一个字都搜不到。
	##   改它们要动 `data/`(不在本轮地盘) ⇒ 已登记进缺口表交上去。
	## ⚠ 另一条现成的 bug(顺手记下, 不在本轮改): 类型「斧头」在 `CodexScene.TYPE_STYLE`
	##   里**没有条目** ⇒ 羁绊页把它画成默认的 🔗。同一个病 2026-08-15 在「香火」上犯过一次
	##   (那次的注释就写在 TYPE_STYLE 上面), 加第 12 个类型时又漏了同一张表。
	## 背包。剩下的 1 个 = 【临时等级器】那张卡上的 🔼 ——
	## 它是这件东西在背包里的**唯一视觉**, 删了就是一张空卡; 而仓库里没有任何
	## 「升级 / 等级」的像素图标(已 grep: level/upgrade/arrow 全无)。
	## 其余是羁绊栏的类型图标(同上)。
	"Inventory": [5, "临时等级器 🔼 ×1(无素材) + 右侧羁绊栏的类型图标 ×4"],
	## 选龟。全部是羁绊 chips 的类型图标(`Phase2Types.emoji_of`)。
	"TeamSelect": [6, "羁绊 chips 的类型图标 ×6(tags/ 未画)"],
	"Record": [0, ""],
	## 设置。⚠ 不计入(它在 NotoSansSC 里, 与正文同一套字);
	## 🛠 调试场只在 `OS.is_debug_build()` 下建 —— 正式包玩家看不到, 不是玩家路径。
	"Settings": [1, "🛠 调试场入口(仅 debug 构建, 不是玩家路径)"],
	"TrainerConfig": [0, ""],
	"Matchmaking": [0, ""],
}

## 每屏至少该扫到这么多【带字的可见控件】。少于它 = 屏没建起来, 下面的"0 emoji"全是假的。
## ★数字按实测定, 留了约 30% 余量(商店货架/图鉴选中项会让条数浮动)。
const MIN_TEXTS: Dictionary = {
	"Codex": 60, "Inventory": 60, "TeamSelect": 60,
	"Record": 20, "Settings": 8, "TrainerConfig": 18, "Matchmaking": 6,
}

## ── ② 静态台账: 源文件 → [允许的 emoji 字符数上限, 理由] ─────────────
## 口径: `scripts/scenes/**/*.gd` 的**双引号字符串字面量**, 去掉 `#` 注释,
##       去掉 `print/printerr/push_warning/push_error` 那些只进终端的行。
## ★这张表是**从真扫描生成**的(`EMOJI_DUMP=1` 打出来再抄进来), 不是我按印象手写 ——
##   memory `fb-hand-rolled-copies-drift`: 手抄的副本必然落后。
const SRC_LEDGER: Dictionary = {
	# ── 本轮地盘内, 有理由留着的 ──
	## ★★★2026-09-28 19 → 20: **这是抬基线, 所以必须把理由说到位**。
	##   `TYPE_STYLE` 原来**缺「斧头」**(第 12 个类型 2026-08-31 就进了 TYPES),
	##   羁绊页因此把斧头画成默认的 🔗。补上 🪓 让这一格 +1。
	## ★为什么这次允许升: 正确的修法是**换成像素图标**, 而 `assets/sprites/tags/` 是**空目录**
	##   —— 12 张类型图标一张都没画。在图画出来之前, 三条路里
	##   「画错的 🔗」<「统一的 emoji」<「像素图标」, 只能取中间那条。
	## ⇒ 这一格的债**已登记在方案书**(缺的素材第 1 项), 画好接线时这个数要一次降 12。
	##   ⚠ 除此之外**不许**再往上抬这个数 —— 抬基线是把尺子改到能量过为止。
	"scripts/scenes/CodexScene.gd": [20,
		"类型图标 12 处(含 2026-09-28 补的斧头🪓; 其中 4 处带 VS16 变体符→各算 2 个字符) + 🛠 调试面板 ×2(仅 debug 构建) + 数据未加载那行的 ❌(平时 visible=false)"],
	"scripts/scenes/InventoryScene.gd": [1, "临时等级器 🔼(无素材)"],
	"scripts/scenes/SettingsScene.gd": [1, "🛠 调试场(仅 debug 构建, 不是玩家路径)"],
	"scripts/scenes/codex/detail_views.gd": [1,
		"装备详情头图的 📦 兜底 —— 96 件装备**全部**有 PNG 且图都在盘上(下面有一条断言在守), 这一支永不触发"],
	"scripts/scenes/team_select/layout_editor.gd": [5,
		"F9 布局编辑器: 开发工具, 玩家按不出来(`_flash_status`/保存坐标), 不是玩家路径"],
	# ── 地盘之外(本轮由别的路在改)。基线按**当下实测**登记, 只许降。 ──
	## ⚠ 这几条不是"我认可它们该留着", 是「不属于本轮地盘、但也不许再长」。
	##   它们的改法与上面一样: 有对得上的像素图就接图, 没有就登记进缺口表。
	"scripts/scenes/MainMenuScene.gd": [15, "主菜单(另一路在改)"],
	"scripts/scenes/ShopScene.gd": [13, "商店(另一路在改)"],
	"scripts/scenes/battle/battle_hud.gd": [14, "战斗 HUD(另一路在改)"],
	"scripts/scenes/battle/battle_debug_arena.gd": [7, "调试场: 开发工具, 不是玩家路径"],
	## ★这两条实测已经是 **0** —— 它们的 emoji 全在 `print/printerr` 里(只进终端,
	##   不上屏), 本扫描器本来就跳掉那些行。登 0 是为了**钉住**它们别变成屏幕文案。
	"scripts/scenes/battle/battle_vfx_lab.gd": [0, "开发工具, 只有终端输出(实测已 0)"],
	"scripts/scenes/battle/battle_watchdog.gd": [0, "只进终端 printerr(实测已 0)"],
	"scripts/scenes/battle/dual_lane_flow.gd": [6, "换路展示(另一路在改)"],
	"scripts/scenes/RealtimeBattle3DScene.gd": [7, "战斗日志/统领兜底(另一路在改)"],
	## ★这两条实测也是 0: 它们里的 `★` / `✓` 在 **NotoSansSC** 里(与正文同一套字),
	##   本门禁按定义就不算它们 —— 登 0 是钉住"别再长出真 emoji"。
	"scripts/scenes/battle/info_panel.gd": [0, "只有 ★(NotoSansSC 的字), 实测已 0"],
	"scripts/scenes/BracketMapScene.gd": [0, "只有 ✓(NotoSansSC 的字), 实测已 0"],
	"scripts/scenes/LeaderboardScene.gd": [1, "🏆 页名(另一路在改)"],
	"scripts/scenes/map_editor.gd": [2, "MAPEDIT 地图编辑器: 开发工具"],
	"scripts/scenes/battle/review_console.gd": [2, "REVIEW 审阅台: 开发工具"],
	"scripts/scenes/TutorialGuide.gd": [0, ""],
	"scripts/scenes/shop/axe_panel.gd": [1, "小木斧面板(另一路在改)"],
	"scripts/scenes/battle/dmg_stats_panel.gd": [0, ""],
	"scripts/scenes/battle/battle_vfx.gd": [0, ""],
}

## 静态扫描要跳过的行首动词 —— 它们只进终端, 不上屏。
const LOG_CALLS := ["print(", "printerr(", "push_warning(", "push_error(", "print_rich("]

var _pass := 0
var _fail := 0
var _dump: bool = OS.get_environment("EMOJI_DUMP") != ""
var _emoji_font: FontFile = null
var _pixel_font: FontFile = null
var _cjk_font: FontFile = null
var _cls_cache: Dictionary = {}


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## ★★判据本体: 这个码点在屏幕上是不是**另一套字**画的。
##   只有 NotoEmoji 有 = 是; 打底像素字或中文字有 = 不是(那是排版字符, 如 ★ ✓ ⚠)。
func _is_emoji_cp(cp: int) -> bool:
	if _cls_cache.has(cp):
		return bool(_cls_cache[cp])
	var r: bool = _emoji_font.has_char(cp) \
		and not _pixel_font.has_char(cp) and not _cjk_font.has_char(cp)
	_cls_cache[cp] = r
	return r


## 一段文字里有几个 emoji 字符 + 都是哪些。
func _scan_text(s: String) -> Array:
	var n := 0
	var chars := ""
	for i in range(s.length()):
		var cp := s.unicode_at(i)
		if cp < 0x2000:              # ASCII/拉丁/基本标点: 一律不是, 省 has_char 开销
			continue
		if _is_emoji_cp(cp):
			n += 1
			chars += s[i]
	return [n, chars]


# ═══════════════════════════════════════════════════════════════════
#  运行时扫描
# ═══════════════════════════════════════════════════════════════════

## 走节点树, 收所有【可见】控件的 text / tooltip_text。
## 返回 {n: emoji 字符数, texts: 带字控件条数, hits: {明细 → 该条几个}}
func _audit_tree(root: Node) -> Dictionary:
	var n := 0
	var texts := 0
	var hits: Dictionary = {}
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if not (node is Control):
			continue
		var ctrl := node as Control
		if not ctrl.is_visible_in_tree():
			continue
		var parts: Array = []
		if ctrl is Label:
			parts.append(str((ctrl as Label).text))
		elif ctrl is Button:
			parts.append(str((ctrl as Button).text))
		elif ctrl is RichTextLabel:
			## ★取 `get_parsed_text()` 而不是 `text`: BBCode 标记里有 `#ffd93d` 之类,
			##   而真正上屏的是解析后的那串。
			parts.append(str((ctrl as RichTextLabel).get_parsed_text()))
		elif ctrl is LineEdit:
			parts.append(str((ctrl as LineEdit).text))
			parts.append(str((ctrl as LineEdit).placeholder_text))
		if str(ctrl.tooltip_text) != "":
			parts.append(str(ctrl.tooltip_text))
		var any := false
		for p in parts:
			if str(p).strip_edges() != "":
				any = true
			var r: Array = _scan_text(str(p))
			if int(r[0]) > 0:
				n += int(r[0])
				## ★ key 里带上控件类 + 命中的字 + 前 40 字 ⇒ 同一个控件在不同状态
				##   被反复扫到时只算一次(跨状态并集用, 见 `_absorb`)。
				hits[("%s「%s」%s" % [str(ctrl.get_class()), str(r[1]),
					str(p).substr(0, 40)])] = int(r[0])
		if any:
			texts += 1
	return {"n": n, "texts": texts, "hits": hits}


## ★★★**每一个被催出来的状态都要当场量一遍**。
##   否则 `_coax` 把底栏/弹框/页签一个个点开, 最后只按**最后那一个状态**量 ⇒
##   中间那几屏等于没量(上一轮四个屏栓在这个形状上)。
##   并集按「控件类+命中字+文本」去重, 所以背景里一直在的那几条不会被重复计数。
var _acc_hits: Dictionary = {}
var _acc_texts: int = 0
var _acc_states: int = 0

func _absorb(root: Node) -> Dictionary:
	var d: Dictionary = _audit_tree(root)
	for k in (d["hits"] as Dictionary).keys():
		_acc_hits[k] = int((d["hits"] as Dictionary)[k])
	_acc_texts = maxi(_acc_texts, int(d["texts"]))
	_acc_states += 1
	return d


func _acc_n() -> int:
	var t := 0
	for k in _acc_hits.keys():
		t += int(_acc_hits[k])
	return t


## ★★探子: 证明「这一屏上如果有 emoji, 上面那个扫描器逮得到」。
##   挂一个写着 🐢 的 Label 进去 → 扫 → 必须多出至少 1 个 → 摘掉。
##   没有这一条, 「某屏 0 emoji」既可能是真干净, 也可能是**扫描器根本没走到这棵树**。
func _canary(root: Node, base: int) -> bool:
	var probe := Label.new()
	probe.name = "EmojiCanary"
	probe.text = "\U01F422"           # 🐢
	root.add_child(probe)
	await get_tree().process_frame
	var d: Dictionary = _audit_tree(root)
	var seen: bool = int(d["n"]) > base
	probe.queue_free()
	await get_tree().process_frame
	return seen


func _wait(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


# ═══════════════════════════════════════════════════════════════════
#  静态扫描(源码字面量)
# ═══════════════════════════════════════════════════════════════════

## 去掉 `#` 注释(要认引号里的 `#`, 否则 `"#ffd93d"` 会把整行吃掉)。
func _strip_comment(line: String) -> String:
	var out := ""
	var i := 0
	var in_q := false
	while i < line.length():
		var ch := line[i]
		if in_q:
			if ch == "\\":
				out += ch
				i += 1
				if i < line.length():
					out += line[i]
					i += 1
				continue
			if ch == "\"":
				in_q = false
			out += ch
			i += 1
			continue
		if ch == "\"":
			in_q = true
			out += ch
			i += 1
			continue
		if ch == "#":
			break
		out += ch
		i += 1
	return out


## 一行代码里所有双引号字面量拼起来。
func _literals_of(code: String) -> String:
	var out := ""
	var i := 0
	var in_q := false
	while i < code.length():
		var ch := code[i]
		if in_q:
			if ch == "\\":
				i += 2
				continue
			if ch == "\"":
				in_q = false
				i += 1
				continue
			out += ch
			i += 1
			continue
		if ch == "\"":
			in_q = true
		i += 1
	return out


func _scan_source(path: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	if src == "":
		return [0, []]
	var n := 0
	var hits: Array = []
	var ln := 0
	for line in src.split("\n"):
		ln += 1
		var code := _strip_comment(str(line))
		var skip := false
		for lg in LOG_CALLS:
			if code.find(lg) >= 0:
				skip = true
				break
		if skip:
			continue
		var r: Array = _scan_text(_literals_of(code))
		if int(r[0]) > 0:
			n += int(r[0])
			hits.append("%s:%d 「%s」" % [path.replace("res://", ""), ln, str(r[1])])
	return [n, hits]


func _all_scene_scripts() -> Array:
	var out: Array = []
	var dirs: Array = ["res://scripts/scenes"]
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


# ═══════════════════════════════════════════════════════════════════
#  主流程
# ═══════════════════════════════════════════════════════════════════

func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	await get_tree().process_frame
	print("=== 屏幕上不许拿 emoji 当图标 ===")

	# ── ③ 分母 A: 三张字体真的加载到了 ────────────────────────────
	## ★没有这一条, 字体加载失败时 `has_char()` 全 false ⇒ `_is_emoji_cp` 恒 false
	##   ⇒ **整份门禁恒绿**。这正是 memory `fb-gate-subject-never-constructed` 那一类。
	_pixel_font = load(FONT_PIXEL) as FontFile
	_cjk_font = load(FONT_CJK) as FontFile
	_emoji_font = load(FONT_EMOJI) as FontFile
	_ok("★分母: 三张字体都加载到了(拿不到字体 ⇒ 判据恒绿)",
		_pixel_font != null and _cjk_font != null and _emoji_font != null)
	if _pixel_font == null or _cjk_font == null or _emoji_font == null:
		print("FAILED: 字体加载不到, 后面一条都别信")
		get_tree().quit(1)
		return
	_ok("★分母: 回退链本身是活的(NotoEmoji 有 🐢 / NotoSansSC 有 ★)",
		_emoji_font.has_char(0x1F422) and _cjk_font.has_char(0x2605))

	# ── ③ 分母 B: 分类器自证(喂已知样本, 两个方向都验) ─────────────
	## ★只验"🐢 被判成 emoji"是**半条判据**: 一个恒 true 的分类器也能过。
	##   必须同时验"★ ✓ ⚠ 汉字 数字 不被判成 emoji" —— 那正是第一版手写区块表翻的车。
	var yes := "\U01F422\U01F512\U01F4A3"          # 🐢 🔒 💣
	var no := "★✓⚠→·龟 Lv3"  # ★ ✓ ⚠ → · 龟 Lv3
	_ok("★分母: 分类器把 🐢🔒💣 判成 emoji(3/3)", int(_scan_text(yes)[0]) == 3,
		"实测 %d" % int(_scan_text(yes)[0]))
	_ok("★分母: 分类器**不**把 ★✓⚠→·汉字 判成 emoji(0/8)", int(_scan_text(no)[0]) == 0,
		"误报 %d 个「%s」" % [int(_scan_text(no)[0]), str(_scan_text(no)[1])])

	# ── ② 静态扫描 ───────────────────────────────────────────────
	print("  ── 静态: scripts/scenes/**.gd 的屏幕字面量 ──")
	var files: Array = _all_scene_scripts()
	_ok("★分母: 真的扫到了场景脚本(≥ 25 个文件)", files.size() >= 25,
		"%d 个" % files.size())
	var src_total := 0
	var src_over: Array = []
	var src_seen: Dictionary = {}
	for f in files:
		var rel: String = str(f).replace("res://", "")
		var r: Array = _scan_source(str(f))
		var n := int(r[0])
		src_total += n
		if n <= 0:
			continue
		src_seen[rel] = n
		var cap := int((SRC_LEDGER.get(rel, [0, ""]) as Array)[0])
		if n > cap:
			src_over.append("%s 实测 %d > 台账 %d" % [rel, n, cap])
		if _dump:
			print("    [DUMP] %-52s %3d  (台账 %d)" % [rel, n, cap])
			for h in (r[1] as Array):
				print("            %s" % str(h))
	_ok("★分母: 静态扫描真的找得到 emoji(全仓 ≥ 20 个, 否则扫描器是瞎的)",
		src_total >= 20, "%d 个" % src_total)
	_ok("静态: 没有文件超出台账(只许降不许升)", src_over.is_empty(),
		"; ".join(src_over.slice(0, 6)))
	## ★台账里登记了、而实际一个都没扫到的条目 = **陈旧登记**。
	##   不当失败(别人把它修好了是好事), 但要打出来提醒清账 ——
	##   memory `fb-registered-todos-rot`: 登记会烂。
	var stale: Array = []
	for k in SRC_LEDGER.keys():
		if int((SRC_LEDGER[k] as Array)[0]) > 0 and not src_seen.has(str(k)):
			stale.append(str(k))
	if not stale.is_empty():
		print("    [提醒] 台账里这几条已经清零了, 下次可以把上限改成 0: %s" % str(stale))

	# ── ① 运行时扫描(逐屏 + 主动催出"点了才出现"的界面)──────────────
	print("  ── 运行时: 逐屏走真实节点树 ──")
	for scn in SCREEN_LEDGER.keys():
		await _audit_screen(str(scn))

	print("  %d passed, %d failed" % [_pass, _fail])
	if _fail == 0:
		print("ALL PASS — 屏幕上不许拿 emoji 当图标")
	get_tree().quit(1 if _fail > 0 else 0)


func _audit_screen(scn: String) -> void:
	var path := "res://scenes/%s.tscn" % scn
	if not ResourceLoader.exists(path):
		_ok("场景在位: %s" % scn, false, "找不到 %s" % path)
		return
	_seed_for(scn)
	var inst = (load(path) as PackedScene).instantiate()
	## ★★撮合屏会**自己走掉**(2.2s 后 `change_scene_to_file` 进战斗) ——
	##   那会把门禁自己拆掉(`get_tree()` 变 null, 后面断言连跑都没跑, 而且
	##   **不打 ALL PASS**、rc 还是 0, 看着像通过)。
	##   它自己有三道 `if _cancelled or not is_inside_tree(): return` 的闸 ⇒
	##   加进树之前就把闸拉下来, 再由我自己调它的两个 `_build_*` 把两屏都催出来。
	if scn == "Matchmaking":
		inst.set("_cancelled", true)
	_acc_hits = {}
	_acc_texts = 0
	_acc_states = 0
	add_child(inst)
	await _wait(24)
	_absorb(inst)                       # 静止页先量一遍
	await _coax(scn, inst)              # 里面每催出一个状态就 `_absorb` 一次
	await _wait(6)
	var d: Dictionary = _absorb(inst)   # 收尾再量一遍
	var cap: int = int((SCREEN_LEDGER[scn] as Array)[0])
	var why: String = str((SCREEN_LEDGER[scn] as Array)[1])
	var total: int = _acc_n()

	_ok("★分母 %s: 屏真的建起来了(带字控件 ≥ %d)" % [scn, int(MIN_TEXTS.get(scn, 10))],
		_acc_texts >= int(MIN_TEXTS.get(scn, 10)),
		"实测 %d 条(跨 %d 个状态取最大)" % [_acc_texts, _acc_states])
	## ★★探子: 证明这一屏上**如果**有 emoji, 判据看得见。
	var canary_ok: bool = await _canary(inst, int(d["n"]))
	_ok("★★分母 %s: 探子 —— 往这一屏塞一个 🐢, 判据逮得到" % scn, canary_ok,
		"逮不到 = 这一屏的 0 是假的(扫描器没走到这棵树)")
	_ok("%s: emoji 图标 ≤ %d%s" % [scn, cap, ("  (台账: " + why + ")") if why != "" else ""],
		total <= cap, "实测 %d 个(跨 %d 个状态取并集)" % [total, _acc_states])
	if _dump:
		print("    ── %s 明细 %d 条(并集) ──" % [scn, _acc_hits.size()])
		for h in _acc_hits.keys():
			print("       ×%d  %s" % [int(_acc_hits[h]), str(h)])

	inst.queue_free()
	await _wait(2)


## 每屏进去之前先把数据喂成【有内容】的样子 —— 空屏上的"0 emoji"是假绿。
## ★一律走 `tests/_setup_*.gd` 这几份现成的种子(截图/门禁共用), 不在这里另写一份。
func _seed_for(scn: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.test_mode = true
	if int(gs.season_total_battles) <= 0:
		gs.season_total_battles = 3
	match scn:
		"Inventory", "TeamSelect", "Codex":
			_run_setup("res://tests/_setup_inv_demo.gd")
			if scn == "TeamSelect":
				_run_setup("res://tests/_setup_syn_demo.gd")
		"Record":
			_run_setup("res://tests/_setup_record_demo.gd")


func _run_setup(p: String) -> void:
	if not ResourceLoader.exists(p):
		_ok("★分母: 种子脚本在位 %s" % p, false, "找不到 = 量的是空屏")
		return
	var sc = load(p)
	## ★★跑不起来**当场判红**: 种子脚本有 Parse Error 时 `has_method` 直接 false,
	##   会一声不响地不执行, 而屏幕照样建得起来 ⇒ 量空屏、报全绿(本仓栽过)。
	if sc == null or not sc.has_method("run"):
		_ok("★分母: 种子脚本跑得起来 %s" % p, false, "load/has_method 失败")
		return
	sc.run()


## ★★★把「点了才出现」的界面**主动催出来**。
##   上一轮在四个屏上抓到同一个形状: 判据只量静止页 ⇒ 弹框/详情/二级页签里的毛病
##   一个都逮不到, 连反向验证都被骗过去(静止页恒绿)。
##   ⇒ 这里走**产品自己的入口**(不是自己拼界面), 每一处都配一条"它真的建起来了"的分母。
func _coax(scn: String, inst) -> void:
	match scn:
		"Codex":
			## 五个页签**全过一遍**, 每个再选中一条 —— 详情面板是这一屏 emoji 最密的地方
			## (羁绊详情的「同类装备」一张表就列十几件)。
			var tabs: Array = ["pets", "equips", "synergies", "status", "rules"]
			var built := 0
			for t in tabs:
				inst.call("_switch_tab", str(t))
				await _wait(3)
				if int(inst.get("_items").size()) > 0:
					inst.call("_select", 0)
					await _wait(3)
					built += 1
				_absorb(inst)          # ★每个页签当场量, 不留到最后
			_ok("★分母 Codex: 五个页签都建出了条目(%d/5)" % built, built == 5)
			## 双形态龟(双头/熔岩)的「换形态」钮 —— 只有这两只身上才画。
			inst.call("_switch_tab", "pets")
			await _wait(3)
			var items: Array = inst.get("_items")
			var form_idx := -1
			for i in range(items.size()):
				if not (items[i] is Dictionary):
					continue
				## ★字段名取自 `detail_views._render_skill_cards` 自己读的那两个,
				##   不是我编的 —— 拿错字段会让这条分母恒为“没找到”。
				var _pd: Dictionary = items[i] as Dictionary
				var _ms = _pd.get("meleeSkills", [])
				var _vs = _pd.get("volcanoSkills", [])
				var _has_m: bool = _ms is Array and not (_ms as Array).is_empty()
				var _has_v: bool = _vs is Array and not (_vs as Array).is_empty()
				if _has_m or _has_v:
					form_idx = i
					break
			if form_idx >= 0:
				inst.call("_select", form_idx)
				await _wait(3)
				_absorb(inst)
				## 另一个形态也要看 —— 两颗钮的文案是三元式的两支, 只量一支就漏一半。
				inst.set("_codex_form_view", not bool(inst.get("_codex_form_view")))
				inst.call("_select", form_idx)
				await _wait(3)
				_absorb(inst)
				inst.set("_codex_form_view", false)
			_ok("★分母 Codex: 找到了双形态龟(换形态钮那一支)", form_idx >= 0,
				"没找到 = 那两颗钮没被量到")
			## 回到羁绊页收尾 —— 类型详情页留在屏上, 好让台账量的是它。
			inst.call("_switch_tab", "synergies")
			await _wait(3)
			## ★羽维详情页**逐条都走一遍**: 「同类装备」那张表每个类型列的东西不同,
			##   只选第 0 条 = 只量到十一个类型里的一个。
			var syn_n: int = int(inst.get("_items").size())
			for si in range(syn_n):
				inst.call("_select", si)
				await _wait(2)
				_absorb(inst)
			_ok("★分母 Codex: 羽维页逐条走遍了(%d 条)" % syn_n, syn_n >= 10,
				"少于 10 = 类型表没建全")
		"Inventory":
			## ① 选中一件装备 ⇒ 底部操作条(卖出/详情/取消)才建
			inst.set("_sel_bench", 0)
			inst.call("_rebuild")
			await _wait(6)
			var d1: Dictionary = _absorb(inst)
			_ok("★分母 Inventory: 选中装备后底栏出来了(控件变多)", int(d1["texts"]) > 40,
				"%d 条" % int(d1["texts"]))
			## ② 装备【详情】弹框
			var bench: Array = GameState.persistent_bench
			var eq_it: Dictionary = {}
			for it in bench:
				if it is Dictionary and str((it as Dictionary).get("kind", "")) == "":
					eq_it = it as Dictionary
					break
			if not eq_it.is_empty():
				inst.call("_show_equip_detail", eq_it)
				await _wait(6)
				_absorb(inst)
			_ok("★分母 Inventory: 拿到了一件真装备来开详情", not eq_it.is_empty())
			## ③ 糖果罐: 选中它 ⇒ 另一条底栏(打碎/取消)
			inst.set("_sel_bench", -1)
			inst.set("_sel_jar", true)
			inst.call("_rebuild")
			await _wait(6)
			_absorb(inst)
		"Settings":
			## ① 重置存档的二次确认框(⚠ 那一屏)
			inst.call("_ask_reset")
			await _wait(6)
			var d2: Dictionary = _absorb(inst)
			_ok("★分母 Settings: 重置确认框真的弹出来了", int(d2["texts"]) >= 12,
				"%d 条" % int(d2["texts"]))
		"Matchmaking":
			## 撮合有两屏: 「正在找」与「已匹配」。后者是 2.2 秒后才建的 ——
			## 静止量只会量到前一屏(又一个"点了才出现"的形状)。
			## ⇒ 直接调它自己的 `_build_vs()`, 不等真实时间(等 = 让它把门禁拆掉)。
			var opp = GameState.dual_opponent
			if opp is Dictionary and not (opp as Dictionary).is_empty():
				inst.call("_build_vs", opp)
				await _wait(8)
				_absorb(inst)
			_ok("★分母 Matchmaking: 拿到了对手数据(没有 = 只量到「正在找」那一屏)",
				opp is Dictionary and not (opp as Dictionary).is_empty())
		_:
			pass
