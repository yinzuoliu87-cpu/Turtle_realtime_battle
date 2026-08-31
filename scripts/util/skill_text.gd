class_name SkillText
extends RefCounted
# ══════════════════════════════════════════════════════════
# skill_text.gd — 技能/被动/装备 描述模板渲染器
#   1:1 PoC src/systems/skill-text.ts (renderSkillTemplate + buildSkillVars + evalSkillExpr)
#
# 模板语法 (来自 JS pets.js):
#   {N:expr} 物理橙 / {P:expr} 穿透白 / {S:expr} 护盾浅白 / {H:expr} 治疗绿
#   {B:expr} 增益浅绿 / {D:expr} 防御黄 / {M:expr} 法术蓝 / {T:expr} 真实白
#   {expr}   计算但不上色 (e.g. {cd}, {ATK})
# expr 里 ATK/DEF/MR/HP/atkScale… 等替换成真值, 算出后 round.
# 关键词 (物理伤害/攻击力/护甲/灼烧…) 自动上色.
# 输出 BBCode (RichTextLabel), 中间态走 PoC 同款 HTML 再转 BBCode 保证关键词 lookbehind 一致.
# ══════════════════════════════════════════════════════════

# ★用 preload 常量而不是靠 class_name 全局注册 —— 新建脚本在编辑器重扫之前
#   全局类名不存在, 无头跑测试会 "Identifier UIPalette not declared"。
const UIPalette = preload("res://scripts/util/ui_palette.gd")

# 颜色字母 → val-class
const COLOR_CLASS := {
	"N": "val-normal", "P": "val-pierce", "S": "val-shield",
	"H": "val-heal", "B": "val-buff", "D": "val-def",
	"M": "val-magic", "T": "val-true",
}

# val-class → hex。三色伤害等语义色【引用 UIPalette】, 不再写字面量
# (2026-07-22: 物理红原为 #ff6b6b, 与飘字/统计面板的 #ff4444 打架; 用户拍板统一到后者)
const VAL_HEX := {
	"val-normal": UIPalette.PHYS, "val-magic": UIPalette.MAGIC, "val-true": UIPalette.TRUE_DMG,
	"val-pierce": UIPalette.PIERCE, "val-shield": UIPalette.SHIELD_TEXT, "val-heal": UIPalette.HEAL,
	"val-buff": UIPalette.BUFF, "val-def": UIPalette.DEF, "val-extra": "#ffcc00",
	"val-burn": "#ff6600", "val-lifesteal": "#e85d75", "val-dot": "#9b59b6",
	"val-stun": "#fbbf24", "val-crit": UIPalette.PHYS, "val-crit-dmg": "#ffaa33",
	"val-reflect": "#94a3b8", "val-heal-reduce": "#a78bfa", "val-atk": UIPalette.PHYS,
}

# 关键词自动上色 (照搬 PoC ui-skill-text.js:107-136, 顺序敏感 — 长词在前)
# [pattern, val-class, 可选 icon-key]; pattern 是 PCRE2 (支持 lookbehind/lookahead).
# ★第 3 项 = 属性图标 key(assets/sprites/stats/<key>-icon.png), 有则在该关键词【前面】内联一枚图标
#   (用户2026-07-24 需求·选 A: 只给【真属性】加图标, 伤害类型/DoT/控制词 保持彩色字不加图标)。
const ICON_PX := 16     # 内联属性图标默认像素高(没传字号时的兜底; 传了字号则按字号缩放, 见 render_bbcode)
const KEYWORD_RULES := [
	["物理伤害", "val-normal"], ["魔法伤害", "val-magic"], ["真实伤害", "val-true"],
	["(?<!\">)真实(?!伤害|<)", "val-true"], ["(?<!\">)物理(?!伤害|<)", "val-normal"],
	["(?<!\">)魔法(?!伤害|<)", "val-magic"], ["防御力加成", "val-def", "def"],
	["(?<!\">)攻击力(?!<)", "val-normal", "atk"], ["(?<!\">)护甲穿透(?!<)", "val-def"],
	["(?<!\">)护甲(?!穿透|<)", "val-def", "def"], ["(?<!\">)魔抗(?!<)", "val-magic", "mr"],
	["(?<!\">)最大生命值?(?!<)", "val-heal", "hp"], ["(?<!\">)最大HP(?!<)", "val-heal", "hp"],
	["(?<!\">)治疗削减(?!<)", "val-heal-reduce"], ["(?<!\">)灼烧(?!<)", "val-burn"],
	["(?<!\">)生命偷取(?!<)", "val-lifesteal", "lifesteal"], ["(?<!\">)眩晕(?!<)", "val-stun"],
	["(?<!\">)诅咒(?!<)", "val-dot"], ["(?<!\">)护盾(?!<)", "val-shield", "shield"],
	["(?<!\">)中毒(?!<)", "val-dot"], ["(?<!\">)流血(?!<)", "val-lifesteal"],
	["(?<!\">)冰寒(?!<)", "val-magic"], ["(?<!\">)反伤(?!<)", "val-reflect"],
	["(?<!\">)暴击率(?!<)", "val-crit", "crit"], ["(?<!\">)暴击伤害(?!<)", "val-crit-dmg", "crit-dmg"],
	["(?<!\">)闪避(?!<)", "val-buff", "dodge"], ["(?<!\">)移动速度(?!<)", "val-magic", "move"],
	["(?<!\">)攻击速度(?!<)", "val-crit", "aspd"], ["(?<!\">)射程(?!<)", "val-def", "range"],
	["(?<!\">)额外伤害(?!<)", "val-extra"],
]


## 安全计算 expr: 用 Expression 把 ATK/atkScale… 替换成真值再算; 失败原样返回. PoC evalSkillExpr.
## 表达式里出现的 `类名.常量名` —— 求值前先换成数值(见 _sub_consts 的说明)。
static var _CONST_IN_EXPR := RegEx.create_from_string("[A-Z][A-Za-z0-9_]*\\.[A-Z][A-Z0-9_]{2,}")


## 把表达式里的 `类名.常量名` 替换成它的数值。
##
## ★为什么要有这个: `{N:0.9*ATK}` 里的 0.9 是**手写的**, 跟代码没有任何绑定 ——
##   代码系数改成 1.1, 文案照样显示 0.9。它和占位符外面那些裸数字是同一个毛病,
##   只是藏在公式里更不容易被发现(实测这类有 289 个, 占"没人验"的 60%)。
##   有了这个预处理, 文案可以写 `{N:StoneSystem.HIT_ATK_COEF*ATK}`, 真正跟着代码走。
##
## ★解析不出来时**故意不兜底**: 原样留着 → Expression.parse 失败 → eval_expr 返回原文
##   → 渲染门禁报"占位符没渲染出来"。宁可当场红, 也不要静默显示一个错数。
static func _sub_consts(expr: String) -> String:
	if not _CONST_IN_EXPR.search(expr):
		return expr
	var out := ""
	var last := 0
	for m in _CONST_IN_EXPR.search_all(expr):
		out += expr.substr(last, m.get_start() - last)
		var raw := m.get_string(0)
		var v := const_of(raw)
		## const_of 解析不了会回 "{C:...}" —— 那种原样放回去, 让上面那条规矩生效。
		out += (raw if v.begins_with("{C:") else v)
		last = m.get_end()
	return out + expr.substr(last)


static func eval_expr(expr: String, vars: Dictionary) -> Variant:
	expr = _sub_consts(expr)
	var names := PackedStringArray(vars.keys())
	var values: Array = []
	for k in names:
		values.append(vars[k])
	var e := Expression.new()
	if e.parse(expr, names) != OK:
		return expr.strip_edges()
	var r = e.execute(values, null, false)
	if e.has_execute_failed():
		return expr.strip_edges()
	if r is float or r is int:
		return roundi(r)
	return r


## 拼 vars 上下文 (PoC buildSkillVars). f = fighter dict, s = skill dict.
static func build_vars(f: Dictionary, s: Dictionary) -> Dictionary:
	var fn := func(k: String, fallback: float = 0.0) -> float:
		return float(s[k]) if (s.has(k) and (s[k] is float or s[k] is int)) else fallback
	var ob := func(k: String) -> Dictionary:
		return s[k] if (s.has(k) and s[k] is Dictionary) else {}
	var p: Dictionary = f.get("passive", {}) if f.get("passive", null) is Dictionary else {}
	var drones: Array = f.get("_drones", [])
	var drone_n: int = drones.size() if not drones.is_empty() else int(p.get("droneCount", 0))
	var armor_break: Dictionary = ob.call("armorBreak")
	var atk_down: Dictionary = ob.call("atkDown")
	var def_down: Dictionary = ob.call("defDown")
	var def_up: Dictionary = ob.call("defUp")
	var def_up_pct: Dictionary = ob.call("defUpPct")
	var hot: Dictionary = ob.call("hot")
	return {
		"ATK": int(f.get("atk", 0)), "DEF": int(f.get("def", 0)),
		"MR": int(f.get("mr", 0)), "HP": int(f.get("maxHp", 0)),
		"LV": int(f.get("lv", f.get("_level", 1))),
		"hits": fn.call("hits", 1.0), "power": fn.call("power"), "pierce": fn.call("pierce"), "cd": fn.call("cd"),
		"atkScale": fn.call("atkScale"), "defScale": fn.call("defScale"), "dmgScale": fn.call("dmgScale"),
		"hpPct": fn.call("hpPct"), "mrScale": fn.call("mrScale"), "arrowScale": fn.call("arrowScale"),
		"shieldScale": fn.call("shieldScale"), "trapScale": fn.call("trapScale"),
		"burstScale": fn.call("burstScale"), "counterScale": fn.call("counterScale"),
		"shieldHpPct": fn.call("shieldHpPct"), "shieldDuration": fn.call("shieldDuration"),
		"shieldHealPct": fn.call("shieldHealPct"), "shieldBreak": fn.call("shieldBreak"),
		"burnAtkScale": fn.call("burnAtkScale"), "burnHpPct": fn.call("burnHpPct"), "burnTurns": fn.call("burnTurns"),
		"execThresh": fn.call("execThresh"), "execCrit": fn.call("execCrit"), "execCritDmg": fn.call("execCritDmg"),
		"fearTurns": fn.call("fearTurns"), "fearReduction": fn.call("fearReduction"),
		"splashPct": fn.call("splashPct"), "duration": fn.call("duration"),
		"atkUpPct": fn.call("atkUpPct"), "atkUpTurns": fn.call("atkUpTurns"),
		"bindPct": fn.call("bindPct"), "dodgePct": fn.call("dodgePct"), "dodgeTurns": fn.call("dodgeTurns"),
		"minScale": fn.call("minScale"), "maxScale": fn.call("maxScale"),
		## ★熔岩龟变身(2026-08-22 文案根除): 这几个值就在**同一个 passive 对象**里
		##   (`transformHpScale: 2.5` …), 而文案里又手写了一遍 "250%"/"20%"/"15 秒"/"100" ——
		##   同一个对象内部自己跟自己分歧, 是最没道理的一类。补进变量表后文案直接引用。
		##   ⚠ 这张表是**固定白名单**, 天生会漏(memory [[fb-recursive-scan-not-structured-walk]]);
		##     新字段要用就得来这里加一行, 别指望它自动认。
		"transformHpScale": fn.call("transformHpScale"), "transformAtkScale": fn.call("transformAtkScale"),
		"transformDefScale": fn.call("transformDefScale"), "transformMrScale": fn.call("transformMrScale"),
		"transformDuration": fn.call("transformDuration"), "rageMax": fn.call("rageMax"),
		"healPct": fn.call("healPct"), "heal": fn.call("heal"), "shield": fn.call("shield"),
		"crit": f.get("crit", 0.25),
		"armorBreakPct": armor_break.get("pct", 0), "armorBreakTurns": armor_break.get("turns", 0),
		"atkDownPct": atk_down.get("pct", 0), "atkDownTurns": atk_down.get("turns", 0),
		"defDownPct": def_down.get("pct", 0), "defDownTurns": def_down.get("turns", 0),
		"defUpVal": def_up.get("val", 0), "defUpTurns": def_up.get("turns", 0),
		"defUpPctVal": def_up_pct.get("pct", 0), "defUpPctTurns": def_up_pct.get("turns", 0),
		"hotPerTurn": hot.get("hpPerTurn", 0), "hotTurns": hot.get("turns", 0),
		"shieldFlat": fn.call("shieldFlat"), "shieldHpPctVal": fn.call("shieldHpPct"),
		"totalScale": fn.call("totalScale"), "shieldTurns": fn.call("shieldTurns"),
		"defBoostTurns": fn.call("defBoostTurns"), "stunAfter": fn.call("stunAfter"),
		"transferPct": fn.call("transferPct"),
		"goldCoins": int(f.get("_goldCoins", 0)),
		"droneCount": drone_n,
		"mechHp": drone_n * int(p.get("mechHpPer", 30)),
		"mechAtk": drone_n * int(p.get("mechAtkPer", 5)),
		"bambooGainedHp": int(f.get("_bambooGainedHp", 0)),
		"stoneDefGained": int(f.get("_stoneDefGained", 0)),
		"rockLayers": int(f.get("_rockLayers", 0)),
		"initDef": int(f.get("_initDef", f.get("baseDef", f.get("def", 0)))),
		"capTurns": int(p.get("capTurns", 0)),
		"maxDefInitPct": int(p.get("maxDefInitPct", 0)),
		"lavaTransformTurns": int(f.get("_lavaTransformTurns", 0)),
		"hunterKills": int(f.get("_hunterKills", 0)),
		"hunterStolenAtk": int(f.get("_hunterStolenAtk", 0)),
		"hunterStolenDef": int(f.get("_hunterStolenDef", 0)),
		"hunterStolenHp": int(f.get("_hunterStolenHp", 0)),
		"hunterStolenMr": int(f.get("_hunterStolenMr", 0)),
		"resilienceDef": int(f.get("_twoHeadResStacks", 0)),
		"resilienceMr": int(f.get("_twoHeadResStacks", 0)),
		"lifesteal": int(f.get("_lifestealPct", 0)),
		"stackMax": fn.call("stackMax") if fn.call("stackMax") > 0 else int(p.get("stackMax", 0)),
		"maxStacks": fn.call("maxStacks") if fn.call("maxStacks") > 0 else int(p.get("maxStacks", 0)),
		"pctPerStack": fn.call("pctPerStack") if fn.call("pctPerStack") > 0 else int(p.get("pctPerStack", 0)),
		"atkPct": fn.call("atkPct") if fn.call("atkPct") > 0 else int(p.get("atkPct", 0)),
		"defPct": fn.call("defPct") if fn.call("defPct") > 0 else int(p.get("defPct", 0)),
		"defBuffAmp": fn.call("defBuffAmp") if fn.call("defBuffAmp") > 0 else int(p.get("defBuffAmp", 0)),
		"perCoinPierce": fn.call("perCoinAtkPierce"),
		"perCoinNormal": fn.call("perCoinAtkNormal"),
	}


# 缓存编译的 RegEx (静态构造一次)
static var _token_re: RegEx
static var _span_re: RegEx
static var _keyword_re: Array = []


static func _ensure_re() -> void:
	if _token_re == null:
		_token_re = RegEx.create_from_string("\\{([NPHSBDMTC]):([^}]+)\\}|\\{([^}]+)\\}")
		_span_re = RegEx.create_from_string("<span\\s+(?:class=\"([^\"]+)\"|style=\"color:\\s*(#[0-9a-fA-F]+)[^\"]*\")[^>]*>([^<]*)</span>|([^<]+)")
		for rule in KEYWORD_RULES:
			_keyword_re.append([RegEx.create_from_string(rule[0]), rule[1], (rule[2] if rule.size() > 2 else "")])


## 渲染模板 → HTML (1:1 PoC renderSkillTemplate: token 展开 + 关键词上色).
static func render_html(template: String, f: Dictionary, s: Dictionary) -> String:
	_ensure_re()
	var vars := build_vars(f, s)
	# 1) token 展开
	var result := ""
	var last := 0
	for m in _token_re.search_all(template):
		result += template.substr(last, m.get_start() - last)
		var color := m.get_string(1)
		var expr := m.get_string(2)
		if expr == "":
			expr = m.get_string(3)
		## ★{C:类名.常量名} —— 直接读**代码里的常量**, 中间不经任何副本。
		##   写 {C:VenomDroneSystem.FOG_LIFE} 的文案, 改代码常量它自己就跟着变, 不存在"忘了同步"。
		var val = (const_of(expr) if color == "C" else eval_expr(expr, vars))
		if color != "" and color != "C" and COLOR_CLASS.has(color):
			result += "<span class=\"%s\">%s</span>" % [COLOR_CLASS[color], str(val)]
		else:
			result += str(val)
		last = m.get_end()
	result += template.substr(last)
	# 2) 关键词自动上色 (+ 属性词前内联图标·用户2026-07-24)
	for kr in _keyword_re:
		var re: RegEx = kr[0]
		var cls: String = kr[1]
		var ico: String = kr[2]
		# 提取关键词文本: 用 sub 把每个匹配替换成 span; 匹配文本本身用 $0 (PCRE2 \0)
		var repl := "<span class=\"%s\">$0</span>" % cls
		if ico != "":   # 真属性 → 关键词【前】插一枚图标(html_to_bbcode 转 [img]); 伤害类型/DoT/控制词 ico="" 不插
			repl = "<img src=\"res://assets/sprites/stats/%s-icon.png\"/>" % ico + repl
		result = re.sub(result, repl, true)
	return result


## HTML → BBCode (span → [color]; PoC parseRichText 的 Godot 等价).
##
## ★栈式解析, 正确处理【嵌套 span】(2026-07-23 重写)。旧实现是一条正则
##   `<span..>([^<]*)</span>` —— 内层 `[^<]*` 一碰到嵌套的 `<` 就断裂, 外层 span
##   整个匹配失败 → 掉进「纯文本」分支 → `span class="val-true">` 这种【原始标签字面量
##   直接漏给玩家】。嵌套从两处天然产生: ①灰字注释里写了自动上色关键词(护甲/最大生命值/
##   真实伤害…)会被关键词规则包一层 span; ②手写 span 里放了 {token}(token 自展开成 span)。
##   实测 pets.json 有 58 处这样的泄漏, 且「别在灰字里写关键词」这条脆弱人肉约定谁都守不住。
##
## ★语义采【最外层 span 颜色胜出】: 灰字注释整段保持灰(去强调本意), 内层关键词不再抢色;
##   手写色块整段保持该色。对【无嵌套】输入与旧实现逐字节等价(仅多解码 &lt; 等实体), 只消泄漏不造泄漏。
static func html_to_bbcode(html: String, icon_px: int = ICON_PX) -> String:
	var s := html
	var out := ""
	var depth := 0   # span 嵌套深度; 只在最外层 span 开/合处发 [color]/[/color]
	var i := 0
	var n := s.length()
	while i < n:
		if s[i] == "<":
			var gt := s.find(">", i)
			if gt < 0:
				out += "<"   # 孤立的 < 当普通字符
				i += 1
				continue
			var tag := s.substr(i, gt - i + 1)
			i = gt + 1
			var low := tag.to_lower()
			if low.begins_with("<br"):
				out += "\n"
			elif low == "<b>": out += "[b]"
			elif low == "</b>": out += "[/b]"
			elif low == "<i>": out += "[i]"
			elif low == "</i>": out += "[/i]"
			elif low.begins_with("</span"):
				if depth > 0:
					depth -= 1
					if depth == 0:
						out += "[/color]"
			elif low.begins_with("<span"):
				if depth == 0:
					out += "[color=%s]" % _span_color(tag)
				depth += 1
			elif low.begins_with("<img"):
				# 内联属性图标: <img src="res://..."/> → [img=W]path[/img](等比·高≈字高)。
				# ★放在 depth 判断【之外】: 图标插在关键词 span【前】, 此刻可能在灰字 span 内(depth>0),
				#   但 [img] 不受 [color] 影响, 直接输出即可(图标本身有色, 不吃文字色)。
				var isrc := _img_src(tag)
				if isrc != "":
					out += "[img=%d]%s[/img]" % [icon_px, isrc]
			# 其它未知标签: 丢弃
		else:
			var lt := s.find("<", i)
			if lt < 0:
				lt = n
			out += _decode_entities(s.substr(i, lt - i))
			i = lt
	if depth > 0:
		out += "[/color]"   # 兜底: 未闭合 span
	return out

## 从 <span ...> 起始标签抽颜色: class="val-x" → VAL_HEX; style="color:#hex" → 原色。
static func _span_color(tag: String) -> String:
	var cq := tag.find("class=\"")
	if cq >= 0:
		var e := tag.find("\"", cq + 7)
		if e > cq:
			return VAL_HEX.get(tag.substr(cq + 7, e - cq - 7), "#ffffff")
	var sp := tag.find("color:")
	if sp >= 0:
		var h := ""
		var k := sp + 6
		while k < tag.length() and tag[k] == " ":
			k += 1
		while k < tag.length() and "#0123456789abcdefABCDEF".contains(tag[k]):
			h += tag[k]; k += 1
		if h != "":
			return h
	return "#ffffff"

## 从 <img src="..."/> 抽 src 路径。
static func _img_src(tag: String) -> String:
	var q := tag.find("src=\"")
	if q < 0:
		return ""
	var e := tag.find("\"", q + 5)
	if e < 0:
		return ""
	return tag.substr(q + 5, e - q - 5)

## 解码 HTML 实体 → 真字符。RichTextLabel 不解实体, 数据里写的 &lt;120码 不解会原样显示成 "&lt;120码"。
## &amp; 最后解, 免得把 &amp;lt; 二次解码成 <。
static func _decode_entities(t: String) -> String:
	if not t.contains("&"):
		return t
	return t.replace("&lt;", "<").replace("&gt;", ">").replace("&#39;", "'").replace("&quot;", "\"").replace("&amp;", "&")


## 便捷: 模板 → BBCode (RichTextLabel 直用).
## font_px = 该描述所在 RichTextLabel 的字号 → 内联属性图标按字号缩放, 每个场合都与文字同高(用户2026-07-24 选C)。
## 传 0 = 用默认 ICON_PX。图标高 ≈ 字号×1.15(实测比字号略大一点点最贴, 见 20260724 方案书)。
static func render_bbcode(template: String, f: Dictionary, s: Dictionary, font_px: int = 0) -> String:
	var ipx := ICON_PX if font_px <= 0 else maxi(12, roundi(float(font_px) * 1.15))
	return html_to_bbcode(render_html(template, f, s), ipx)


## 便捷: 模板 → 纯文本 (无色, 仅展开数字; Label 用). 去掉所有 <…> 标签.
## 【装备文案的唯一取值口】—— 简述 / 全文。
##
## ★由来(2026-08-19): 95 件装备原来只有 `effectDesc1` 一个字段, 它同时干着
##   "一句话简述"和"完整机制说明"两件事 —— 实测中位 129 字、最长 329 字,
##   而同类游戏(实抓 489 条 / 14 款)是 12~85 字。挤在背包格子、战斗信息面板里根本读不完。
##   现在每件装备补了 `effectBrief`(一句话, 中位 36 字), 原文留作全文。
## ★为什么做成函数而不是让七个消费点各自 `get("effectBrief")`:
##   memory `fb-hand-rolled-copies-drift`「手抄的副本必然落后 —— 抄一次永远落后一次」。
##   没有简述的装备(理论上不该有, 门禁守着)自动退回全文, 不会显示空白。
static func equip_brief(edef: Dictionary) -> String:
	## ★这两个是**共享入口** —— {C:...} 在这里展开, 所有消费方(图鉴/商店/战斗)一次全好,
	##   不用每个调用点各记一次。(2026-08-20: 我先只补了商店和战斗, 图鉴走的是这里, 差点漏。)
	var b := render_consts(str(edef.get("effectBrief", "")).strip_edges())
	return b if b != "" else equip_full(edef)


## 完整机制说明(图鉴详情 / 点开看全部 用)。
static func equip_full(edef: Dictionary) -> String:
	return render_consts(str(edef.get("effectDesc1", "")))


## 这件装备的【简述】值不值得单独显示一遍。
##
## ★由来(2026-08-31): 用户在图鉴里看到「同一件事写了两遍」—— 简述一行 + 全文一段,
##   而两者几乎是同一句话。渲染层本来就有防重(`_eb != _ef`), 但它只挡【一字不差】,
##   而这些是"差几个字"的, 全都漏过去了。
##
## ★判据用两个【有人话含义】的条件, 不用相似度分数(那个没有干净的分界线):
##     ① 简述**没更短** —— 长度 ≥ 全文的 75%
##     ② 简述**没说新东西** —— 它的内容被全文覆盖 ≥ 90%
##   两个都成立 ⇒ 它不是简述, 是重复。
##   实测(95 件装备的全量剖面): 命中 4 件 —— 黄铜齿轮(15字 vs 15字·完全一样)、
##   幽灵墨鱼、双穿珊瑚刺、辣椒。其余 91 件的简述是真·简述
##   (如霰弹贝古 32 字 vs 108 字), 照常显示两段。
## ★不改数据只改判据: 以后再加装备自动纳入, 不用有人记得去改文案。
static func brief_is_redundant(brief: String, full: String) -> bool:
	var b := _strip_for_cmp(brief)
	var f := _strip_for_cmp(full)
	if b == "" or f == "":
		return true
	if b == f:
		return true
	if float(b.length()) < float(f.length()) * 0.75:
		return false                      # 真的更短 ⇒ 是个有用的简述
	return _covered_frac(b, f) >= 0.90    # 没更短, 那就看它有没有说新东西


## 比较用的规范化: 去掉标记/占位符/空白, 只留可读内容。
static func _strip_for_cmp(t: String) -> String:
	var out := ""
	var skip := 0
	for ch in t:
		if ch == "<" or ch == "{" or ch == "[":
			skip += 1
		elif ch == ">" or ch == "}" or ch == "]":
			skip = maxi(0, skip - 1)
		elif skip == 0 and ch != " " and ch != "
" and ch != "	":
			out += ch
	return out


## b 里有多少内容能在 f 里按顺序找到(最长公共子序列 / b 的长度)。
## ★用子序列而不是子串: 全文常在简述中间插字("普攻" → "携带者的普攻"),
##   子串匹配会因为插了几个字就判成"完全不同"。
static func _covered_frac(b: String, f: String) -> float:
	if b.length() == 0:
		return 1.0
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(f.length() + 1)
	var cur: PackedInt32Array = PackedInt32Array()
	cur.resize(f.length() + 1)
	for i in range(b.length()):
		cur[0] = 0
		for j in range(f.length()):
			if b[i] == f[j]:
				cur[j + 1] = prev[j] + 1
			else:
				cur[j + 1] = maxi(prev[j + 1], cur[j])
		var tmp := prev
		prev = cur
		cur = tmp
	return float(prev[f.length()]) / float(b.length())


static func render_plain(template: String, f: Dictionary, s: Dictionary) -> String:
	_ensure_re()
	var html := render_html(template, f, s)
	var strip := RegEx.create_from_string("<[^>]+>")
	return strip.sub(html, "", true)


## 装备文案按【当前星级】高亮: a/b/c 三元组里, 玩家这一档加粗上色, 另两档变暗。
##
## ★只在【渲染时】变换, 绝不碰 data/phase2-equipment.json 的格式 ——
##   tools/tooltip_number_audit.py 靠 `\d+/\d+/\d+` 这个正则从 effectDesc1 抠三元组去和代码对账,
##   格式一变它就抠不出来 → total 归零 → 打印 ALL OK 但什么都没查(方案书 R1 记过这个静默失效)。
##
## star 取 1/2/3; 传 0 或越界 = 不高亮(图鉴那种没有玩家星级的场合)。
## 三档数值【按星级上色】——★1 白 / ★2 青 / ★3 金, 三档**同样亮**。
##
## ★与 `highlight_star` 的分工: 商店/背包玩家有确定的星级 ⇒ 高亮那一档、压暗另两档;
##   图鉴是**资料页**, 没有"我的星级"这回事 ⇒ 压暗任何一档都是在暗示错误信息。
##   但三档同色平铺又读不出边界(实拍 `20/35/60+0.5/0.8/1.1×攻击力` 像一串乱码),
##   所以改成三色等亮 + 页面上给一行图例。
const STAR_COLORS := ["#ffffff", "#7fe3ff", "#ffd93d"]

static func color_all_stars(desc: String) -> String:
	if desc == "":
		return ""
	var re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)")
	var out := ""
	var pos := 0
	for m in re.search_all(desc):
		out += desc.substr(pos, m.get_start() - pos)
		for i in 3:
			if i > 0:
				out += "[color=#5f7186]/[/color]"
			out += "[color=%s]%s[/color]" % [STAR_COLORS[i], m.get_string(i + 1)]
		pos = m.get_end()
	out += desc.substr(pos)
	return out


## 图例行(与 `color_all_stars` 同一套色), 放在用到三档数值的页面上。
static func star_legend_bbcode() -> String:
	return "[color=%s]★1[/color] [color=#5f7186]/[/color] [color=%s]★2[/color] [color=#5f7186]/[/color] [color=%s]★3[/color]" % [
		STAR_COLORS[0], STAR_COLORS[1], STAR_COLORS[2]]


## ★压暗色 #5a6472 → #7d8ea0(2026-08-14)。
##   由来: 用户「描述那里有一堆乱七八糟的东西」。实拍放大后 `/30/45` 几乎只剩噪点 ——
##   #5a6472 压在商店面板底色 #10202e 上对比度只有 **2.76:1**(WCAG 正文要 4.5:1)。
##   #7d8ea0 是 **4.9:1**, 读得出来又仍然明显暗于高亮档(高亮还额外有 [b] 加粗 + UIPalette.DEF 色)。
static func highlight_star(desc: String, star: int) -> String:
	if desc == "":
		return ""
	if star < 1 or star > 3:
		return desc
	var re := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)/(\\d+(?:\\.\\d+)?)")
	var out := ""
	var pos := 0
	for m in re.search_all(desc):
		out += desc.substr(pos, m.get_start() - pos)
		var parts := [m.get_string(1), m.get_string(2), m.get_string(3)]
		var seg := ""
		for i in 3:
			if i > 0:
				seg += "[color=#7d8ea0]/[/color]"
			if i == star - 1:
				seg += "[b][color=%s]%s[/color][/b]" % [UIPalette.DEF, parts[i]]
			else:
				seg += "[color=#7d8ea0]%s[/color]" % parts[i]
		out += seg
		pos = m.get_end()
	out += desc.substr(pos)
	return out


## ── 两级描述的统一取值口径 (用户需求1: 缩略 / 详细) ──────────────────────
##
## ★为什么要收口: 2026-07-22 实测同一个信息面板里【被动段给详细、技能段给缩略】,
##   而选龟界面的 tooltip 与点开的弹窗是【同一串】(等于只有一级), 图鉴才是真两级。
##   6 处散落的 fallback 链各写各的, 口径必然漂。
##
## ★字段名不统一是历史包袱, 别在这里"顺手统一": 技能是 brief/detail, 被动是 brief/【desc】。
##   passive.desc 这个名字被 3 个工具硬编码(tri_audit / brief_detail_audit / data_integrity),
##   重命名的收益低于成本 —— 所以差异吸收在本函数里, 不外溢。

## 缩略: 给算好的实时值(照 Riot 2020 改版口径 —— 基础提示给结论, 比率藏进扩展提示)
static func brief_of(d: Dictionary) -> String:
	var b := str(d.get("brief", ""))
	if b != "":
		return b
	return str(d.get("detail", d.get("desc", "")))


## 详细: 展开比率与公式。技能取 detail, 被动取 desc, 都没有才退回 brief
static func detail_of(d: Dictionary) -> String:
	var t := str(d.get("detail", ""))
	if t != "":
		return t
	t = str(d.get("desc", ""))
	if t != "":
		return t
	return str(d.get("brief", ""))


## 按模式取: want_detail=true 要详细。详细缺失时【自动退回缩略】而不是显示空白
static func text_of(d: Dictionary, want_detail: bool) -> String:
	if not want_detail:
		return brief_of(d)
	var t := detail_of(d)
	return t if t != "" else brief_of(d)

## class_name → 它的脚本常量表(缓存)。
static var _const_cache: Dictionary = {}


## 读一个代码常量: "VenomDroneSystem.FOG_LIFE" → 6。
##
## ★为什么要有这个(2026-08-20): 玩家文案里 2487 个数字是**手抄代码的**, 只有 220 个是占位符。
##   手抄的每一个在写下那天都是对的, 原件一改就烂, 而且烂了没人知道。
##   已有的 {N:1.5*ATK} 只能算**单位属性**和**本条技能自己的 json 字段**,
##   而 json 字段本身又是代码常量的手抄(实测已有 10 条对不上) ⇒ 差的就是"直接引用代码常量"这一环。
## ★数组按本项目惯例渲染成三档: [3, 5, 8] → "3/5/8"。
## ★取不到时**原样吐回 {C:...}**, 不静默变成 0 —— 静默归零是最难查的一类错。
static func const_of(ref: String) -> String:
	## ★结尾带 % ⇒ 把常量×100 再渲染。代码里大量比例存的是**小数**(0.22), 而文案写**百分比**(22%),
	##   没有这一档的话这些常量全都引用不了 —— 转第一条真文案时就撞上了。
	##   写法: {C:CrystalSystem.BURST_MAXHP_PCT%} → 22
	var as_pct := ref.ends_with("%")
	if as_pct:
		ref = ref.substr(0, ref.length() - 1)
	var dot := ref.rfind(".")
	if dot <= 0:
		return "{C:%s}" % ref
	var cls := ref.substr(0, dot).strip_edges()
	var key := ref.substr(dot + 1).strip_edges()
	if not _const_cache.has(cls):
		var path := ""
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == cls:
				path = str(c.get("path", ""))
				break
		var scr: Script = (load(path) as Script) if path != "" and ResourceLoader.exists(path) else null
		_const_cache[cls] = scr.get_script_constant_map() if scr != null else {}
	var m: Dictionary = _const_cache[cls]
	if not m.has(key):
		return "{C:%s}" % ref
	var v = m[key]
	if as_pct and (v is float or v is int):
		return _fmt_num(float(v) * 100.0)
	if v is Array:
		var parts: PackedStringArray = []
		for x in (v as Array):
			parts.append(_fmt_num(x))
		return "/".join(parts)
	return _fmt_num(v)


## 6.0 → "6"; 0.25 → "0.25" (整数不拖 .0)
static func _fmt_num(v) -> String:
	if v is float and is_equal_approx(v, roundf(float(v))):
		return str(int(roundf(float(v))))
	return str(v)

## 只展开 {C:类名.常量名}, 其它 token 原样留着。
##
## ★为什么要单独有这个(2026-08-20): 一大批消费方拿的是**原始文本**, 不走 render_* ——
##   商店的 `_equip_full_desc` 注释白纸黑字写着"95 件装备的 effectDesc1 全是纯文本"。
##   我一把 092 的文案改成 {C:...}, 商店就会把 `{C:VenomDroneSystem.POISON_STACKS}` 原样显示给玩家
##   (是 verify_shop_layout 的"文字变长要滚动"抓到的)。
## ★{C:...} 不需要单位/技能上下文, 所以可以在任何地方安全展开 —— {N:1.5*ATK} 不行, 那才是
##   那些消费方不敢渲染的原因。⇒ 给它们一条只做常量替换的轻量入口。
static func render_consts(t: String) -> String:
	if not t.contains("{C:"):
		return t
	## 用字符类 [{] [}] 而不是转义 —— GDScript 字符串里 \{ 是**非法转义**, 直接 Parse Error。
	var re := RegEx.create_from_string("[{]C:([^}]+)[}]")
	var out := ""
	var last := 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		out += const_of(m.get_string(1))
		last = m.get_end()
	return out + t.substr(last)
