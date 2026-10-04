extends Node
## verify_hud_gamefeel.gd — 战斗 UI 的【游戏味】门禁 (2026-09-28)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-28:「一点也看不出来游戏的味道, 全是 ai 味和网页味, 文字语言也是」。
## 那一轮把三块屏改了皮也改了词, 这份门禁守**改对的那些东西不许回来**。
##
## 守两类:
##   ① **词** —— 后台/报表用语不许回到玩家屏上(「数据」「统计」「同步」「结算」「项」「次/秒」…),
##      全角括号计数（N 项）不许回来。判据扫的是**字符串字面量**, 注释不算。
##   ② **形** —— 伤害榜(战中「战报」浮层)每一行的**名次形态差异真的存在**:
##      冠亚季是签牌、第四名之后是裸数字; 头名字号/色与别行不同; 数值定宽右对齐;
##      条是**分段**的而不是一根纯色条; 一个圆角都没有。
##
## ══════════════════════════════════════════════════════════════════
##  ★判据纪律(这份文件自己要守的)
## ══════════════════════════════════════════════════════════════════
## · **每条断言配一条分母断言** —— 先证明那一屏/那些行真的建起来了, 再判它长什么样。
##   本项目栽过的形状: 判据没错但被测对象不在场(memory `fb-gate-subject-never-constructed`)、
##   0 命中的空检查照样绿(memory `fb-judge-must-fit-the-shape`)。
## · **能渲染就渲染**, 不拿源码字面量替代: 战报浮层走 `setup()+build()+render()` 真入口,
##   结算表走 `_stats_column()`, 结算屏那块 chip 走 `_build_reward_chips()`。
##   只有"某个词不许出现在源码里"这一类才必须扫源码(渲染不到的屏也要守)。
## · 反面对照: 第 4 名与第 5 名的形态必须**一样** —— 否则"每行都不同"也能让"形态有差异"绿。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_hud_gamefeel.tscn --quit-after 500

const HUD := preload("res://scripts/scenes/battle/battle_hud.gd")
const DSP := preload("res://scripts/scenes/battle/dmg_stats_panel.gd")
const RP := preload("res://scripts/net/remote_pool.gd")
const UIP := preload("res://scripts/util/ui_palette.gd")

## 扫的文件 = 本轮改过的三块屏(结算屏 2026-10-04 起分在两个文件里)。
const FILES := [
	"res://scripts/scenes/battle/battle_hud.gd",
	"res://scripts/scenes/battle/dmg_stats_panel.gd",
	"res://scripts/scenes/battle/info_panel.gd",
	## 2026-10-04 结算屏拆成三页后, 那一屏的字住在这里(同一块屏, 换了文件不许出视野)
	"res://scripts/scenes/battle/settle_screen.gd",
]

## ★后台/报表用语黑名单。每一条都写清**为什么它是后台词**, 不写理由的词不许加进来
##   (否则下一个人只会照着绕过它, 而不是理解它)。
const BAD_WORDS := [
	## 「数据」: dashboard 的词。玩家问的是"这场打得怎么样", 不是"给我看数据"。
	"数据",
	## 「统计」: 后台报表的说法。同一件事在这个项目里叫【战报】。
	"统计",
	## 「同步」: 网络内部词 —— 玩家不知道同步的是什么、和谁同步。
	"同步",
	## 「结算」: ① 后台词; ② 它在本项目里**还专指战斗结束那一屏** ⇒ 一个词两个意思,
	##   泡泡龟那条「X 秒后结算」读起来像"这只龟要打完了"。
	"结算",
	## 「项」: 表单/报表里数条目的量词(「共 11 项」)。嘴里说的是"11 个"。
	"项",
	## 「次/秒」: `X/Y` 是规格表写单位的写法(m/s)。嘴里说的是"每秒几下"。
	"次/秒",
	## 「配置」: 设置面板的后台叫法。
	"配置",
	## 「简明只给算好的数值; 详细展开公式与比率」—— 在**教玩家怎么用按钮**。
	##   按钮自己写着「简明」「详细」, 再解释一遍就是说明书口气。
	"简明只给",
]

## ★白名单: 只放**玩家永远看不到**的串。每条写清为什么放过。
##   ⚠ 白名单不是"我懒得改"的出口 —— 放进来的条件是"这个控件只在 DEBUG_EDIT 下建出来"。
const OK_EXACT := [
	## `_build_topright_btns` 里 `if battle.DEBUG_EDIT:` 之内的调试日志键。
	"日志",
	## `_build_log_panel` 的标题, 同样只在调试场出现(正式对局里这块面板不建)。
	"战斗日志",
]
## 含这个词的串一律放过: 地图编辑器那条操作提示(只有它提到「笔刷」)。
## 调试场/地图编辑器是**开发工具**, 不进玩家的包的判断路径(MAPEDIT / DEBUG_EDIT 开关)。
const OK_IF_CONTAINS := ["笔刷"]

## 结算战报表那 4 个数值列的表头。★这份名单**不是**我另抄一份口径 ——
##   下面 ④ 会断言它与 `DmgStatsPanel.TABS` 的页签名【逐字一致】(单一出处)。
## ★2026-10-04 用户「打出，抗住，这就很ai味」⇒ 改商业游戏通行叫法
const WANT_HDR := ["伤害", "承伤", "治疗", "击杀"]

var _n := 0
var _fail := 0
var _bak := {}


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + ex) if ex != "" else ""])


## ── 最小替身 battle：只提供被测那几个函数真正读的字段/方法 ────────────────
## ★这些**与被测的事无关**(名字怎么取、稀有度什么色), 喂它们不构成恒真式;
##   被测的是"表头叫什么""行长什么样"。
class FakeBattle extends RefCounted:
	var _had_season := true
	var _last_reward := 12
	var _last_was_exhibition := false
	func _st_name(u: Dictionary) -> String:
		var n := str(u.get("name", ""))
		return n if n != "" else str(u.get("id", "未知龟"))
	func _pet_rarity_color(_r: String) -> Color:
		return Color("#9aa6b3")


# ══════════════════════════════════════════════════════════════════
#  源码字面量扫描器(只取字符串字面量, 注释不算)
# ══════════════════════════════════════════════════════════════════
## ★为什么必须自己切而不能 `src.contains("数据")`: 这三个文件里**注释比代码多**,
##   而注释里满是"数据/统计/同步"(全是在解释为什么改掉它们) ⇒ 整份判据会被自己的说明喂红。
func _cjk_literals(path: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	var out: Array = []
	for raw in src.split("\n"):
		var line := str(raw)
		var i := 0
		var n := line.length()
		while i < n:
			var c := line[i]
			if c == "#":
				break                      # 行内注释: 此后整行不看(引号内的 # 不会走到这里)
			if c == "\"" or c == "'":
				var q := c
				var j := i + 1
				var buf := ""
				while j < n:
					if line[j] == "\\":
						buf += line.substr(j, 2)
						j += 2
						continue
					if line[j] == q:
						break
					buf += line[j]
					j += 1
				if _has_cjk(buf):
					out.append(buf)
				i = j + 1
				continue
			i += 1
	return out


## 只有带中文的字面量才可能出现在屏幕上 —— 节点名/资源路径/格式串一律是 ASCII。
func _has_cjk(s: String) -> bool:
	for k in range(s.length()):
		var cp := s.unicode_at(k)
		if cp >= 0x4E00 and cp <= 0x9FFF:
			return true
	return false


func _whitelisted(s: String) -> bool:
	if OK_EXACT.has(s):
		return true
	for w in OK_IF_CONTAINS:
		if s.contains(str(w)):
			return true
	return false


# ══════════════════════════════════════════════════════════════════
#  树遍历小工具
# ══════════════════════════════════════════════════════════════════
func _all_labels(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		_all_labels(c, out)
	return out


func _all_text(n: Node) -> String:
	var s := ""
	for l in _all_labels(n, []):
		s += str(l.text) + "|"
	return s


## 收集树里所有 StyleBoxFlat(用来验"一个圆角都没有")。
func _all_flat(n: Node, out: Array = []) -> Array:
	if n is Panel or n is PanelContainer or n is Button or n is ProgressBar:
		for nm in ["panel", "normal", "background", "fill"]:
			var sb: StyleBox = (n as Control).get_theme_stylebox(nm) if (n as Control).has_theme_stylebox_override(nm) else null
			if sb is StyleBoxFlat:
				out.append(sb as StyleBoxFlat)
	for c in n.get_children():
		_all_flat(c, out)
	return out


## 一枚名次牌的"牌面色": 签牌贴图在的时候是 modulate_color, 退回纯色时是 bg_color。
func _badge_tint(c: Control) -> Color:
	var sb: StyleBox = c.get_theme_stylebox("panel") if c.has_theme_stylebox_override("panel") else null
	if sb is StyleBoxTexture:
		return (sb as StyleBoxTexture).modulate_color
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


## 造一只只用于渲染的合成单位。★不用随机 spawn —— 精确数值的判据碰上未播种 RNG
##   会在 CI 偶发红(CLAUDE.md §7)。
func _mk(nm: String, dealt: int, phy: int, mag: int, tru: int, alive: bool = true) -> Dictionary:
	return {
		"id": nm, "name": nm, "alive": alive, "is_summon": false, "rarity": "C",
		"_st_dealt": dealt, "_st_taken": int(dealt * 0.5), "_st_heal": int(dealt * 0.2),
		"_st_shield": 0, "_st_kills": 1 if dealt > 0 else 0,
		"_st_dealt_by_type": {"phy": phy, "mag": mag, "tru": tru, "dot": 0},
		"_st_taken_by_type": {"phy": int(dealt * 0.5), "mag": 0, "tru": 0, "dot": 0},
	}


func _ready() -> void:
	await get_tree().process_frame
	print("=== 战斗 UI 游戏味门禁 ===")

	# ══════════════════════════════════════════════════════════════
	#  ① 后台词不许回来(源码字面量)
	# ══════════════════════════════════════════════════════════════
	print("── ① 后台/报表用语不许回到玩家屏上 ──")
	var total := 0
	var bad: Array = []
	var seen_anchor := false            # 分母用: 扫到过一条我知道一定在的串
	for f in FILES:
		var lits := _cjk_literals(str(f))
		total += lits.size()
		for s in lits:
			if str(s) == "战报":
				seen_anchor = true
			if _whitelisted(str(s)):
				continue
			for w in BAD_WORDS:
				if str(s).contains(str(w)):
					bad.append("%s ← 「%s」(%s)" % [str(s).substr(0, 40), str(w), str(f).get_file()])
	## ★分母①: 切词器真的切出了东西。0 条 = 判据是空的, 下面那条永远绿。
	_ok("①分母 扫到带中文的字面量 %d 条(0 条 = 空检查)" % total, total >= 100,
		"三个文件合计, 期望 ≥100")
	## ★分母②: 切词器不只是"什么都没切到"—— 它确实切到了一条**我知道一定在**的串。
	##   (「战报」是这一轮定的名字, 战中浮层名牌 / 右上角键 tooltip / 结算表标题三处同名。)
	_ok("①分母 切词器切得出「战报」这个真串(证明它不是一直返回空)", seen_anchor)
	_ok("①★ 一个后台词都没有(黑名单 %d 个词)" % BAD_WORDS.size(), bad.is_empty(),
		"命中: %s" % str(bad.slice(0, 5)))

	## 全角括号计数「更多属性（11 项）」不许回来。
	## ★判据是**全角括号本身**: 这个游戏的 UI 里全角括号只出现过那一处
	##   (别处一律半角 + `·`), 所以"有全角括号"就等于"那种文档写法回来了"。
	var fw: Array = []
	var more_row := ""
	for f in FILES:
		for s in _cjk_literals(str(f)):
			if str(s).contains("（") or str(s).contains("）"):
				fw.append("%s (%s)" % [str(s).substr(0, 40), str(f).get_file()])
			if str(s).begins_with("更多属性"):
				more_row = str(s)
	## ★分母: 「更多属性」那条入口的标题串**真的在场** —— 它就是当初出事的那一条,
	##   找不到它就说明这组判据在对着空气检查(memory `fb-gate-subject-never-constructed`)。
	_ok("②分母 找到「更多属性」那条入口的标题串", more_row != "", more_row)
	_ok("②★ 标题里没有括号计数, 也没有量词「项」",
		more_row != "" and not more_row.contains("（") and not more_row.contains("项"), more_row)
	_ok("②★ 三块屏的字面量里一个全角括号都没有", fw.is_empty(), str(fw.slice(0, 5)))

	# ══════════════════════════════════════════════════════════════
	#  ③ 结算屏那块 chip: 阵容上传失败的那一行说的是人话
	# ══════════════════════════════════════════════════════════════
	print("── ③ 结算屏「阵容上传 / 没传上去」那一行 ──")
	## ★逐个写死取 —— `RP.get("fail_count")` 在类(不是实例)上调不通(静态变量没有 `get()`)。
	_bak["fail_count"] = int(RP.fail_count)
	_bak["ok_count"] = int(RP.ok_count)
	_bak["last_fail_reason"] = str(RP.last_fail_reason)
	var gs = GameState
	for k2 in ["week_phase", "ranked_used", "season_wins", "hearts", "season_level"]:
		_bak[k2] = gs.get(k2)
	gs.week_phase = "ranked"
	gs.ranked_used = 3
	var hud = HUD.new(FakeBattle.new())

	## 先做**反面对照**: 后端干净 ⇒ 这一行压根不该出现。
	## ★没有这一条, "无条件永远显示" 也能让下面那条绿。
	RP.fail_count = 0
	RP.ok_count = 0
	RP.last_fail_reason = ""
	var clean = hud._build_reward_chips(gs)
	var t_clean := _all_text(clean) if clean != null else ""
	_ok("③分母 结算屏 chip 真的建出来了(不是 null/空)", t_clean != "", t_clean.substr(0, 70))
	_ok("③反面 后端没出错时【不出现】上传失败那一行", not t_clean.contains("没传上去"), t_clean.substr(0, 70))

	## 再让它真的坏掉(走产品自己的记账入口, 不直接改 looks_broken)。
	RP.note_result(false, 404)
	_ok("③分母 looks_broken() 现在为真(前置条件成立)", RP.looks_broken(),
		"fail=%d ok=%d" % [int(RP.fail_count), int(RP.ok_count)])
	var broken = hud._build_reward_chips(gs)
	var t_broken := _all_text(broken) if broken != null else ""
	_ok("③分母 坏掉之后那一行真的画出来了", t_broken.contains("没传上去"), t_broken.substr(0, 90))
	## 判据: 整块 chip 的**渲染后文本**里一个后台词都没有 —— 尤其不许再有「同步」。
	var chip_bad: Array = []
	for w in BAD_WORDS:
		if t_broken.contains(str(w)):
			chip_bad.append(str(w))
	_ok("③★ 那一行(以及整块 chip)里没有后台词", chip_bad.is_empty(),
		"命中 %s / 全文 %s" % [str(chip_bad), t_broken.substr(0, 90)])
	## 与**成功**那一行同一个词根 —— 成功说"上传"、失败说别的就是同一件事两个名字。
	_ok("③★ 与成功那行(「阵容已上传 · …」)用同一个词根「上传」", t_broken.contains("上传"),
		t_broken.substr(0, 90))
	RP.fail_count = int(_bak["fail_count"])
	RP.ok_count = int(_bak["ok_count"])
	RP.last_fail_reason = str(_bak["last_fail_reason"])

	# ══════════════════════════════════════════════════════════════
	#  ④ 结算战报表: 表头是短动词栏牌, 不是 <th>
	# ══════════════════════════════════════════════════════════════
	print("── ④ 结算屏战报表的表头 ──")
	var units: Array = [_mk("甲", 900, 500, 300, 100), _mk("乙", 200, 200, 0, 0, false)]
	var col = hud._stats_column("我方", units, Color("#8ee6a0"))
	_ok("④分母 表真的建出来了, 5 列 × (1 表头 + 2 行)",
		col != null and (col as GridContainer).columns == 5 and col.get_child_count() == 15,
		"children=%d" % (col.get_child_count() if col != null else -1))
	var hdr_txt: Array = []
	var hdr_plated := 0
	if col != null:
		for i in range(1, 5):
			var cell: Node = col.get_child(i)
			if cell is PanelContainer:
				hdr_plated += 1
			var ls := _all_labels(cell, [])
			if ls.size() > 0:
				hdr_txt.append(str((ls[0] as Label).text))
	_ok("④分母 取到了 4 个数值列表头", hdr_txt.size() == 4, str(hdr_txt))
	_ok("④★ 表头是 %s(主动语态短动词, 不是「造成伤害/承受伤害/治疗量」)" % str(WANT_HDR),
		hdr_txt == WANT_HDR, str(hdr_txt))
	## 「一行金色裸字压着几列数字」= `<th>`+`<td>` 的长相 ⇒ 每个数值列表头必须包在栏牌里。
	_ok("④★ 4 个表头都装在栏牌(PanelContainer)里, 不是裸 Label", hdr_plated == 4,
		"带牌的 %d/4" % hdr_plated)
	## 单一出处: 战中「战报」浮层的页签名与这张表的列名【逐字一致】。
	var tab_names: Array = []
	for pair in DSP.TABS:
		tab_names.append(str((pair as Array)[1]))
	_ok("④分母 战报浮层有 4 个页签名", tab_names.size() == 4, str(tab_names))
	_ok("④★ 页签名前三个与表头前三个逐字一致(同一件事不许两种叫法)",
		tab_names.slice(0, 3) == WANT_HDR.slice(0, 3), "%s vs %s" % [str(tab_names), str(WANT_HDR)])
	## MVP 角标: 一张全是数字的表要能一眼看出"这场谁扛的"。
	var mvp := 0
	for l in _all_labels(col, []):
		if str(l.text) == "MVP":
			mvp += 1
	_ok("④★ 本队恰好一个 MVP 角标(打出最高的那只)", mvp == 1, "数到 %d 个" % mvp)

	# ══════════════════════════════════════════════════════════════
	#  ⑤ 战中「战报」浮层: 每一行的形态差异真的存在
	# ══════════════════════════════════════════════════════════════
	print("── ⑤ 伤害榜每一行的名次形态差异 ──")
	var layer := CanvasLayer.new()
	add_child(layer)
	## 5 只, 打出值互不相同 ⇒ 排完序名次就是 1..5(第 4/5 两名是**反面对照组**)。
	var lefts: Array = [
		_mk("一号", 5000, 3000, 1500, 500),
		_mk("二号", 4000, 4000, 0, 0),
		_mk("三号", 3000, 1000, 1000, 1000),
		_mk("四号", 2000, 2000, 0, 0),
		_mk("五号", 1000, 1000, 0, 0),
	]
	var dsp = DSP.new()
	dsp.setup(layer, func(side: String) -> Array: return lefts if side == "left" else [])
	dsp.build()
	dsp.render()
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("⑤分母 浮层真的建出来了(走 setup+build+render 真入口)",
		dsp.panel != null and is_instance_valid(dsp.panel))
	var rows: Array = []
	if dsp._cols.size() >= 1:
		for c in (dsp._cols[0] as Node).get_children():
			rows.append(c)
	_ok("⑤分母 我方那一列真的排出了 5 行", rows.size() == 5, "实得 %d 行" % rows.size())

	if rows.size() == 5:
		## 每行结构: VBox[ HBox top(牌/名/值), 条 ]
		var badges: Array = []
		var names: Array = []
		var vals: Array = []
		for r in rows:
			var top: Node = (r as Node).get_child(0)
			badges.append(top.get_child(0))
			names.append(top.get_child(1))
			vals.append(top.get_child(2))
		## 分母: 三样部件逐行都取到了
		var parts_ok := true
		for i in range(5):
			if badges[i] == null or not (names[i] is Label) or not (vals[i] is Label):
				parts_ok = false
		_ok("⑤分母 5 行的 [名次牌 / 名字 / 数值] 三样部件逐行都在", parts_ok)

		## ── 形态 A: 冠亚季是签牌, 第四名之后是裸数字 ──
		var top3_plated := 0
		for i in range(3):
			if badges[i] is PanelContainer:
				top3_plated += 1
		_ok("⑤A★ 冠亚季三行的名次牌是【签牌】(PanelContainer)", top3_plated == 3,
			"带牌的 %d/3" % top3_plated)
		_ok("⑤A★ 第 4/5 名是【裸数字】(Label, 没有牌)",
			(badges[3] is Label) and not (badges[3] is PanelContainer)
			and (badges[4] is Label) and not (badges[4] is PanelContainer),
			"第4=%s 第5=%s" % [badges[3].get_class(), badges[4].get_class()])
		## ★牌与裸数字**必须一样宽**, 否则第 3/4 行的名字起笔位置会跳。
		var w3: float = (badges[2] as Control).get_combined_minimum_size().x
		var w4: float = (badges[3] as Control).get_combined_minimum_size().x
		_ok("⑤A★ 签牌与裸数字占同样宽(名字起笔不许跟着名次跳)", absf(w3 - w4) <= 1.0,
			"第3名牌 %.1fpx / 第4名 %.1fpx (RANK_W=%.0f)" % [w3, w4, DSP.RANK_W])

		## ── 形态 B: 冠亚季三档牌面色互不相同 ──
		var c1 := _badge_tint(badges[0] as Control)
		var c2 := _badge_tint(badges[1] as Control)
		var c3 := _badge_tint(badges[2] as Control)
		_ok("⑤B分母 三块牌都取到了牌面色(不是全透明 = 没读到 StyleBox)",
			c1.a > 0.01 and c2.a > 0.01 and c3.a > 0.01,
			"%s / %s / %s" % [str(c1), str(c2), str(c3)])
		_ok("⑤B★ 冠亚季三档牌面色互不相同", c1 != c2 and c2 != c3 and c1 != c3,
			"%s / %s / %s" % [str(c1), str(c2), str(c3)])

		## ── 形态 C: 头名的名字与数值各大一档、数值是金的 ──
		var fs1: int = (names[0] as Label).get_theme_font_size("font_size")
		var fs2: int = (names[1] as Label).get_theme_font_size("font_size")
		_ok("⑤C分母 字号读得到(>0)", fs1 > 0 and fs2 > 0, "头名 %d / 第2名 %d" % [fs1, fs2])
		_ok("⑤C★ 头名的名字比第 2 名大一档(名次差异不能只挂在一个小角标上)", fs1 > fs2,
			"头名 %d / 第2名 %d" % [fs1, fs2])
		var vc1: Color = (vals[0] as Label).get_theme_color("font_color")
		var vc4: Color = (vals[3] as Label).get_theme_color("font_color")
		_ok("⑤C★ 头名的数值色与第 4 名不同(头名是金的)", vc1 != vc4,
			"头名 %s / 第4名 %s" % [str(vc1), str(vc4)])

		## ── 反面对照: 第 4 名与第 5 名的形态**必须一样** ──
		## ★没有这一条, "每一行都长得不一样"(纯噪声)也能让上面全绿 ——
		##   要守的是"差异**来自名次**", 不是"行与行随便有点不同"。
		var fs4: int = (names[3] as Label).get_theme_font_size("font_size")
		var fs5: int = (names[4] as Label).get_theme_font_size("font_size")
		var vc5: Color = (vals[4] as Label).get_theme_color("font_color")
		_ok("⑤反面 第 4 名与第 5 名形态完全相同(差异只来自冠亚季这一档)",
			fs4 == fs5 and vc4 == vc5 and absf(w4 - (badges[4] as Control).get_combined_minimum_size().x) <= 1.0,
			"字号 %d/%d · 色 %s/%s" % [fs4, fs5, str(vc4), str(vc5)])

		## ── 形态 D: 数值列定宽 + 右对齐 = 这里的 tabular-nums ──
		var aligned := 0
		for v in vals:
			var lb := v as Label
			if absf(lb.custom_minimum_size.x - DSP.VAL_W) < 0.5 					and lb.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				aligned += 1
		_ok("⑤D★ 5 行数值都是【定宽 %.0f + 右对齐】(个位落在同一条竖线上)" % DSP.VAL_W,
			aligned == 5, "合格 %d/5" % aligned)

		## ── 形态 E: 条是**分段**的, 不是一根纯色条 ──
		## 一号龟有 物理/魔法/真伤 三段, 二号龟只有物理一段 ⇒ 段数必须**跟着数据变**。
		var seg1 := _count_segs(rows[0])
		var seg2 := _count_segs(rows[1])
		_ok("⑤E分母 两行的条都建出了段(0 段 = 条根本没画)", seg1 > 0 and seg2 > 0,
			"一号 %d 段 / 二号 %d 段" % [seg1, seg2])
		_ok("⑤E★ 段数跟着伤害类型走(三类 3 段 / 单类 1 段), 不是一根纯色条",
			seg1 == 3 and seg2 == 1, "一号 %d 段 / 二号 %d 段" % [seg1, seg2])

	## ── 形态 F: 一个圆角都没有(圆角矩形 = CSS 的长相) ──
	var flats := _all_flat(dsp.panel, []) if dsp.panel != null else []
	var rounded: Array = []
	for sb in flats:
		var f := sb as StyleBoxFlat
		if f.corner_radius_top_left > 0 or f.corner_radius_top_right > 0 				or f.corner_radius_bottom_left > 0 or f.corner_radius_bottom_right > 0:
			rounded.append("r=%d bg=%s" % [f.corner_radius_top_left, str(f.bg_color)])
	_ok("⑤F分母 浮层里数到 %d 个 StyleBoxFlat(0 个 = 空检查)" % flats.size(), flats.size() >= 5)
	_ok("⑤F★ 一个圆角都没有(圆角矩形是网页盒的长相)", rounded.is_empty(),
		str(rounded.slice(0, 4)))

	## ── 浮层的渲染后文本里也不许有后台词(标题必须是「战报」) ──
	var t_panel := _all_text(dsp.panel) if dsp.panel != null else ""
	_ok("⑤分母 浮层渲染后的文本非空", t_panel != "", t_panel.substr(0, 80))
	_ok("⑤★ 浮层标题是「战报」", t_panel.contains("战报"), t_panel.substr(0, 80))
	var pbad: Array = []
	for w in BAD_WORDS:
		if t_panel.contains(str(w)):
			pbad.append(str(w))
	_ok("⑤★ 浮层渲染后的文本里没有后台词", pbad.is_empty(),
		"命中 %s / 全文 %s" % [str(pbad), t_panel.substr(0, 120)])
	## ★页签名那条判据(④)读的是 `DSP.TABS` 常量 —— 这里补一条"常量真的到了屏幕上":
	##   四个页签是 Button 不是 Label(上面 `_all_text` 只收 Label), 所以单独读一遍。
	##   没有这一条, 改了 TABS 而渲染侧读别的地方也能让 ④ 绿(memory `fb-read-a-field-nobody-writes`)。
	var btn_txt: Array = []
	for tb in dsp._tab_btns:
		btn_txt.append(str(((tb as Dictionary)["btn"] as Button).text))
	_ok("⑤分母 4 个页签键真的建出来了", btn_txt.size() == 4, str(btn_txt))
	_ok("⑤★ 页签键上印的字 = `TABS` 里那四个(常量真的到了屏幕上)",
		btn_txt == tab_names, "%s vs %s" % [str(btn_txt), str(tab_names)])

	# ── 收尾 ──
	if dsp.panel != null and is_instance_valid(dsp.panel):
		dsp.panel.queue_free()
	layer.queue_free()
	_restore(gs)
	_ok("★收尾 GameState 与 RemotePool 都还原成跑之前的样子",
		str(gs.week_phase) == str(_bak["week_phase"]) and int(gs.ranked_used) == int(_bak["ranked_used"])
		and int(RP.fail_count) == int(_bak["fail_count"]) and int(RP.ok_count) == int(_bak["ok_count"]),
		"week_phase=%s ranked_used=%d fail=%d ok=%d"
		% [str(gs.week_phase), int(gs.ranked_used), int(RP.fail_count), int(RP.ok_count)])

	## ★分母(整份): 断言条数太少 = 我把一半判据写漏了也会"全绿"。
	if _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30), 说明有整组判据没跑到" % _n)
		_fail += 1
	print("")
	print("ALL PASS (%d/%d) — 战斗 UI 游戏味" % [_n, _n] if _fail == 0
		else "FAIL x%d / %d — 战斗 UI 游戏味" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## 一行里条的**段数**: 段是 stretch_ratio 来自伤害值的 Panel, 末尾那个余量 spacer 是 Control(不算)。
func _count_segs(row: Node) -> int:
	var wrap: Node = (row as Node).get_child(1)          # VBox 的第 2 个孩子 = 条
	var n := 0
	var st: Array = [wrap]
	while not st.is_empty():
		var x: Node = st.pop_back()
		if x is HBoxContainer:
			for seg in (x as Node).get_children():
				if seg is Panel:
					n += 1
		for c in x.get_children():
			st.append(c)
	return n


## ★调试台/门禁写 GameState 会落盘污染玩家存档(本项目栽过) ⇒ 跑完必须还原。
func _restore(gs) -> void:
	for k in ["week_phase", "ranked_used", "season_wins", "hearts", "season_level"]:
		if _bak.has(k):
			gs.set(k, _bak[k])
	RP.fail_count = int(_bak.get("fail_count", 0))
	RP.ok_count = int(_bak.get("ok_count", 0))
	RP.last_fail_reason = str(_bak.get("last_fail_reason", ""))
