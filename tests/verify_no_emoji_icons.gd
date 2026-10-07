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
	## 图鉴。★★ 2026-09-28 类型图标已换成 `assets/sprites/tags/` 的 12 张 32×32 像素图
	##   (见 `CodexScene.TYPE_STYLE` 的 `icon` 与 `_type_icon()`) ⇒ 这一格从 **38 降到 6**。
	##   降幅 32 = 羁绊页列表行 16 + 羁绊详情头图 16(四个类型带 VS16 变体符→各算 2 个字符)。
	##   ★数字是 `EMOJI_DUMP=1` 量出来的, 不是 38−12 算出来的 —— 按算术估会差 20。
	## ★数字口径 = 一次扫描里出现的 emoji **字符数**(同一类型在页签/详情各出现一次也各算一次),
	##   所以它随"当前选中哪一条"浮动 ⇒ 取实测上沿。
	## ★2026-10-07 6 → 0(实测): 消耗品分组 10-02 已删, 右上角 🛠 调试面板 10-07 按用户「右上角调试器直接删掉」整块删除。
	"Codex": [0, "已清零: 消耗品分组与 🛠 调试面板都删了"],
	## ⚠★★ Codex 剩下的 6 个里有 **5 个根本不在任何 .gd 里** —— 它们在
	##   `data/equipment.json` 的 **`name` 字段**里: 「🔥 怒火药水」「⛑ 应急护盾」
	##   「🌿 急救包」「✨ 净化」「🎯 必中标记」(5 件消耗品)。
	##   ★这正是【运行时扫描】比【源码扫描】多拿到的一类: 源码里一个字都搜不到。
	##   改它们要动 `data/`(不在本轮地盘) ⇒ 已登记进缺口表交上去。
	## ★另外那 1 个是右上角的 🛠 调试面板钮 —— 只在 `OS.is_debug_build()` 下建, 不是玩家路径。
	## 背包。★★2026-09-28 **5 → 1**: 右侧羁绊栏的类型图标已换成 `tags/` 像素图
	##   (`Phase2Types.TYPE_ICON` + `icon_bb()`, 行名与弹框标题两处都换)。
	##   剩下的 1 个 = 【临时等级器】那张卡上的 🔼 ——
	##   它是这件东西在背包里的**唯一视觉**, 删了就是一张空卡; 而仓库里没有任何
	##   「升级 / 等级」的像素图标(已 grep: level/upgrade/arrow 全无)。
	## ★1 是 `EMOJI_DUMP=1` **实测**的, 不是 5−4 算的 —— 上一轮按算术估会差 20。
	"Inventory": [1, "临时等级器 🔼 ×1(无素材)"],
	## 选龟。★★2026-09-28 **6 → 0**: 羁绊 chips 的类型图标全部换成 `tags/` 像素图
	##   (`Label` → `RichTextLabel` + 行内 `[img=16x16]`)。这一屏已经一个 emoji 都没有。
	##   ★0 是实测, 不是"应该为 0" —— 而登 0 的价值是**钉住**: 以后这屏再冒一个就红。
	"TeamSelect": [0, ""],
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
	## ★★★ 2026-09-28 **20 → 3**。台账只许降不许升, 这是在还债。
	##   `TYPE_STYLE` 的 12 条 `"emoji"` 已全部换成 `"icon"`(`assets/sprites/tags/tag-*.png`),
	##   `_type_emoji()` 也改成了 `_type_icon()`。
	## ★降了 17 而不是 12: 12 个类型里有 **4 个带 VS16 变体符**(🗡️/⚙️/🛡️/🕯️)→各算 2 个字符 = 16,
	##   再加上 `_type_emoji` 的兜底值 🔗 一个 = 17。**这个数是 `EMOJI_DUMP=1` 量出来的**,
	##   不是 20−12 算出来的 —— 按算术估会多留 5 个的余量, 而余量就是下一次悄悄长回来的地方。
	## ★兜底值从 🔗 改成 **""**(缺的类型就不画图) —— 香火(2026-08-15)/斧头(2026-09-28)
	##   两次事故都是"兜底成别的东西", 看上去像是有意设计。
	"scripts/scenes/CodexScene.gd": [1,
		"数据未加载那行的 ❌(平时 visible=false); 🛠 调试面板 ×2 已于 2026-10-07 整块删除"],
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
	## ★★2026-09-28 **14 → 5**(实测)。局内羁绊 chips 的类型图标已换成 `tags/` 像素图,
	##   但 ⚠ **这一格的数字并不是因此降的** —— 类型 emoji 从来不是这个文件里的字面量,
	##   它们住在 `scripts/gamedata/phase2_types.gd`, 而本静态扫描的范围只有
	##   `scripts/scenes/**` ⇒ 那 12 个 emoji **一直不在这张台账里**(见文件末尾的缺口说明)。
	##   14 是别的路清理时留下的余量, 现在按实测收到 5。
	"scripts/scenes/battle/battle_hud.gd": [5,
		"战斗日志那行的 🏆/💀 ×2 + 调试场面板的 🛠⏸🔁 ×3(调试场是开发工具, 不是玩家路径)"],
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
	var raw_bb: Dictionary = {}
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
		## ★★bbcode 原文泄漏那一条**只看直接画在控件上的字**(上面 parts 里这几项),
		##   **不看 `tooltip_text`** —— 本仓的技能提示(`SkillTipButton` / `TutorialGuide`)
		##   是**带样式的自定义 tooltip**, 它的 `tooltip_text` 里本来就装着 bbcode,
		##   由那个渲染器解析。把它算进去就是 5 条假违规(实测: 选龟屏三个技能钮)。
		for pd in parts:
			if str(pd).find("[img=") >= 0 or str(pd).find("[/img]") >= 0:
				raw_bb[("%s: %s" % [str(ctrl.get_class()), str(pd).substr(0, 56)])] = true
		if str(ctrl.tooltip_text) != "":
			parts.append(str(ctrl.tooltip_text))
		var any := false
		for p in parts:
			if str(p).strip_edges() != "":
				any = true
			var r: Array = _scan_text(str(p))
			## ★★2026-09-28 补一条**同族的**失明: 类型图标换成行内 `[img=WxH]…[/img]`
			##   之后,「图标没画出来」有了第二种长相 —— **bbcode 原文上了屏**:
			##     · 把 `RichTextLabel` 改回 `Label`(Label 不认 bbcode)
			##     · 或忘了 `bbcode_enabled = true`
			##   两种都不报错、不崩溃, 屏幕上就是一串 `[img=16x16]res://…png[/img]枪 5/6`。
			##   emoji 台账逮不到它(那串里一个 emoji 都没有) ⇒ 必须单开一条。
			## ★量的是【上了屏的字】, 与控件是哪个类无关 —— 改回 Label 照样逮得到。
			##   (`RichTextLabel` 走 `get_parsed_text()`, 正常渲染时那串标记已经不在了。)
			##   ⇒ 实际收集在上面 `parts` 组装完、把 tooltip 追加进来【之前】那一段。
			if int(r[0]) > 0:
				n += int(r[0])
				## ★ key 里带上控件类 + 命中的字 + 前 40 字 ⇒ 同一个控件在不同状态
				##   被反复扫到时只算一次(跨状态并集用, 见 `_absorb`)。
				hits[("%s「%s」%s" % [str(ctrl.get_class()), str(r[1]),
					str(p).substr(0, 40)])] = int(r[0])
		if any:
			texts += 1
	return {"n": n, "texts": texts, "hits": hits, "raw_bb": raw_bb}


## ★★★**每一个被催出来的状态都要当场量一遍**。
##   否则 `_coax` 把底栏/弹框/页签一个个点开, 最后只按**最后那一个状态**量 ⇒
##   中间那几屏等于没量(上一轮四个屏栓在这个形状上)。
##   并集按「控件类+命中字+文本」去重, 所以背景里一直在的那几条不会被重复计数。
var _acc_hits: Dictionary = {}
var _acc_texts: int = 0
var _acc_states: int = 0
var _acc_raw_bb: Dictionary = {}

func _absorb(root: Node) -> Dictionary:
	var d: Dictionary = _audit_tree(root)
	for k in (d["hits"] as Dictionary).keys():
		_acc_hits[k] = int((d["hits"] as Dictionary)[k])
	for k2 in (d["raw_bb"] as Dictionary).keys():
		_acc_raw_bb[k2] = true
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

	# ── ②.5 类型图标表: 每个类型都要有图, 且图真在盘上 ─────────
	## ★★这一节是**反向验证当场照出来的洞**(2026-09-28)。把 `TYPE_STYLE` 里「剑」
	##   那条从 `icon` 换回 `emoji` 之后实测:
	##     · 静态台账  红(5 > 3) —— **只因为换成的是 emoji**
	##     · 运行时    绿 —— `_type_icon` 返回 "", 屏上什么都不画
	##     · verify_codex_layout ⑥/⑦  绿 —— ⑥ 取的是 95 件里的**最大值**, 别的类型顶着
	##     · type_tables_audit          绿 —— 它只比**顶层键集**, 不问值里有没有 icon
	##   ⇒ 把 `"icon"` 那一项**直接删掉**(不换成 emoji), **一条都不会红**。
	## ★那正是「香火变成一把剑(2026-08-15) / 斧头变成一条链(2026-09-28)」换了个壳:
	##   不报错、不崩溃, 只是悄悄少画一个图标。两次都是“补了数据、没补门禁”。
	## ★分母: 先断言类型表真的解析出来了(≥ 10 个) —— 拿不到表时下面两条恒绿。
	var _codex_scr: GDScript = load("res://scripts/scenes/CodexScene.gd")
	var _p2t: GDScript = load("res://scripts/gamedata/phase2_types.gd")
	var _style: Dictionary = {}
	var _types: Dictionary = {}
	if _codex_scr != null:
		_style = _codex_scr.get("TYPE_STYLE") if _codex_scr.get("TYPE_STYLE") is Dictionary else {}
	if _p2t != null:
		_types = _p2t.get("TYPES") if _p2t.get("TYPES") is Dictionary else {}
	_ok("★分母: 两张类型表都拿到了(TYPES %d / TYPE_STYLE %d, 各 ≥ 10)"
		% [_types.size(), _style.size()], _types.size() >= 10 and _style.size() >= 10,
		"拿不到 = 下面两条是空检查")
	var _no_icon: Array = []
	var _no_file: Array = []
	for _t in _types.keys():
		var _ip: String = str((_style.get(_t, {}) as Dictionary).get("icon", ""))
		if _ip == "":
			_no_icon.append(str(_t))
		elif not ResourceLoader.exists(_ip):
			_no_file.append("%s→%s" % [str(_t), _ip])
	_ok("★★ TYPE_STYLE 里每个类型都有 icon(少一个 = 那一项悄悄不画图标)",
		_no_icon.is_empty(), "缺图标的类型: %s" % str(_no_icon))
	_ok("★★ 每张类型图真的在盘上(路径写错也是悄悄不画)",
		_no_file.is_empty(), "加载不到: %s" % str(_no_file))

	# ── ②.6 ★★**第二张**类型图标表 `Phase2Types.TYPE_ICON` —— 同样三条 ─────
	## ★★为什么要照搬一份: 上面那三条只盯 `CodexScene.TYPE_STYLE`(图鉴那一屏),
	##   而**商店 / 出战选人 / 战斗 HUD / 背包羁绊面板**走的是**另一张表**
	##   `Phase2Types.TYPE_ICON`(经 `icon_of()` / `icon_bb()`)。
	##   ⇒ 只给一张表配判据 = 另一张表照样能悄悄丢图标, 而那正是
	##   「香火显示成一把剑(2026-08-15)」「斧头显示成一条链(2026-09-28)」两次事故的形状:
	##   **表分几张而只改了一张**。
	## ★这三条各自能单独红, 对应三种"不报错的坏":
	##   ① 分母拿不到表 ⇒ 下面两条是空检查   ② 键在而 icon 是空串 ⇒ 悄悄不画
	##   ③ 路径打错 / 被换成一个 emoji       ⇒ 加载不到, 也是悄悄不画
	## ★第四条是**兜底值**: 它原来是 `"🗡️"` —— 缺图标的类型会画成一把剑,
	##   **看上去像是有意设计**, 所以两次事故都是等用户发现的。现在必须回 ""。
	var _icons: Dictionary = {}
	if _p2t != null:
		_icons = _p2t.get("TYPE_ICON") if _p2t.get("TYPE_ICON") is Dictionary else {}
	_ok("★分母: 第二张表也拿到了(TYPES %d / Phase2Types.TYPE_ICON %d, 各 ≥ 10)"
		% [_types.size(), _icons.size()], _types.size() >= 10 and _icons.size() >= 10,
		"拿不到 = 下面三条是空检查")
	var _p2_no_icon: Array = []
	var _p2_no_file: Array = []
	var _p2_uniq: Dictionary = {}
	for _t in _types.keys():
		## ★走**产品自己的取值口** `icon_of()`, 不直接读字典 ——
		##   读字典会绕开兜底那一支, 而兜底正是这两次事故的发生地。
		var _ip2: String = str(_p2t.call("icon_of", str(_t))) if _p2t != null else ""
		if _ip2 == "":
			_p2_no_icon.append(str(_t))
			continue
		_p2_uniq[_ip2] = true
		if not ResourceLoader.exists(_ip2):
			_p2_no_file.append("%s→%s" % [str(_t), _ip2])
	_ok("★★ Phase2Types.TYPE_ICON 里每个类型都有 icon(少一个 = 那一屏悄悄不画图标)",
		_p2_no_icon.is_empty(), "缺图标的类型: %s" % str(_p2_no_icon))
	_ok("★★ 每张图真的在盘上(路径写错 / 被换回 emoji 都落在这一条)",
		_p2_no_file.is_empty(), "加载不到: %s" % str(_p2_no_file))
	## ★分母: 12 个类型必须是 12 张【互不相同】的图。
	##   少了这条, 「所有类型都回落成同一张」能把上面两条全骗过去(都非空、都加载得到)。
	_ok("★分母: %d 个类型 %d 张互不相同的图(全回落成同一张时上面两条会假绿)"
		% [_types.size(), _p2_uniq.size()], _p2_uniq.size() == _types.size())
	## ★★兜底值: 不存在的类型必须返回 ""(什么都不画), 不是某个类型的图。
	var _fb: String = str(_p2t.call("icon_of", "__这个类型不存在__")) if _p2t != null else "x"
	_ok("★★ 兜底值是空串 —— 不许兜底成别的类型的图(「香火显示成一把剑」的直接成因)",
		_fb == "", "实得「%s」" % _fb)
	## ★两张表必须指向**同一批文件** —— 两张各画一套, 同一个类型在图鉴与商店会长得不一样。
	var _mismatch: Array = []
	for _t in _types.keys():
		var _a: String = str((_style.get(_t, {}) as Dictionary).get("icon", ""))
		var _b: String = str(_p2t.call("icon_of", str(_t))) if _p2t != null else ""
		if _a != _b:
			_mismatch.append("%s: 图鉴 %s ≠ 其余 %s" % [str(_t), _a, _b])
	_ok("★★两张表指向同一批文件(否则同一个类型在图鉴与商店长得不一样)",
		_mismatch.is_empty(), str(_mismatch.slice(0, 4)))
	## ★★★下面这条补的是**本门禁自己的一个盲区**:
	##   ②(静态扫描)的范围写死 `scripts/scenes/**`, 而这张表住在
	##   `scripts/gamedata/phase2_types.gd` ⇒ 它那 12 个 emoji **从来不在台账里**
	##   (所以 ShopScene/battle_hud 那两格的数字换图标前后一个样 —— 不是没换, 是没数)。
	##   ⇒ 单独盯这一个文件: 它是两张图标表之一的家, 里面**一个 emoji 字面量都不该有**。
	##   (不把整个 `scripts/gamedata/` 纳进台账, 是因为那会把别的路在改的几个文件一并钉住。)
	var _p2t_src: Array = _scan_source("res://scripts/gamedata/phase2_types.gd")
	_ok("★★ phase2_types.gd 里一个 emoji 字面量都没有(它是类型图标表的家, 却在静态扫描范围外)",
		int(_p2t_src[0]) == 0, "实测 %d 个: %s" % [int(_p2t_src[0]), str((_p2t_src[1] as Array).slice(0, 6))])

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
	## ★★2026-09-28 把「余量」也**机械地报出来**。
	##   由来: 「多留的余量就是下次悄悄长回来的地方」—— 但一条条手写"这里还有 7 格余量"
	##   的提醒**本身会烂**(memory `fb-registered-todos-rot`)。
	##   ⇒ 让门禁**每轮自己算**: 实测比上限低 ≥3 的条目直接列出来, 谁拥有那个文件谁收。
	##   (不判红: 别人正在改的文件此刻低于上限是好事, 钉死会让他们拿到假红;
	##    但**必须看得见** —— 看不见的余量才是悄悄长回来的那种。)
	var slack: Array = []
	for k2 in SRC_LEDGER.keys():
		var cap2: int = int((SRC_LEDGER[k2] as Array)[0])
		var got2: int = int(src_seen.get(str(k2), 0))
		if cap2 > 0 and src_seen.has(str(k2)) and cap2 - got2 >= 3:
			slack.append("%s 实测 %d / 上限 %d(余 %d)" % [str(k2), got2, cap2, cap2 - got2])
	if not slack.is_empty():
		print("    [提醒] 这几格还留着余量, 收紧到实测值即可(余量 = 下次悄悄长回来的地方):")
		for s2 in slack:
			print("            %s" % str(s2))

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
	_acc_raw_bb = {}
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
	## ★★「图标没画出来」的第二种长相: bbcode 原文上了屏(见 `_audit_tree` 里那段注释)。
	##   一个都不许有 —— 这不是台账项, 因为它没有"有理由留着"的情形。
	_ok("%s: 屏上没有 bbcode 原文(`[img=…]` 漏成文字 = 图标没画出来的另一种长相)" % scn,
		_acc_raw_bb.is_empty(), "%d 处: %s" % [_acc_raw_bb.size(), str(_acc_raw_bb.keys().slice(0, 3))])
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
			var tabs: Array = ["pets", "equips", "synergies", "status"]   # 「规则」页签 2026-10-07 已删
			var built := 0
			for t in tabs:
				inst.call("_switch_tab", str(t))
				await _wait(3)
				if int(inst.get("_items").size()) > 0:
					inst.call("_select", 0)
					await _wait(3)
					built += 1
				_absorb(inst)          # ★每个页签当场量, 不留到最后
			_ok("★分母 Codex: 四个页签都建出了条目(%d/4)" % built, built == 4)
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
