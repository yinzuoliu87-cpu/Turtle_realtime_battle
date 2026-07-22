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
const UIPalette = preload("res://scripts/engine/ui_palette.gd")

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
# [pattern, html_replacement]; pattern 是 PCRE2 (支持 lookbehind/lookahead).
const KEYWORD_RULES := [
	["物理伤害", "val-normal"], ["魔法伤害", "val-magic"], ["真实伤害", "val-true"],
	["(?<!\">)真实(?!伤害|<)", "val-true"], ["(?<!\">)物理(?!伤害|<)", "val-normal"],
	["(?<!\">)魔法(?!伤害|<)", "val-magic"], ["防御力加成", "val-def"],
	["(?<!\">)攻击力(?!<)", "val-normal"], ["(?<!\">)护甲穿透(?!<)", "val-def"],
	["(?<!\">)护甲(?!穿透|<)", "val-def"], ["(?<!\">)魔抗(?!<)", "val-magic"],
	["(?<!\">)最大生命值(?!<)", "val-heal"], ["(?<!\">)最大HP(?!<)", "val-heal"],
	["(?<!\">)治疗削减(?!<)", "val-heal-reduce"], ["(?<!\">)灼烧(?!<)", "val-burn"],
	["(?<!\">)生命偷取(?!<)", "val-lifesteal"], ["(?<!\">)眩晕(?!<)", "val-stun"],
	["(?<!\">)诅咒(?!<)", "val-dot"], ["(?<!\">)护盾(?!<)", "val-shield"],
	["(?<!\">)中毒(?!<)", "val-dot"], ["(?<!\">)流血(?!<)", "val-lifesteal"],
	["(?<!\">)冰寒(?!<)", "val-magic"], ["(?<!\">)反伤(?!<)", "val-reflect"],
	["(?<!\">)暴击率(?!<)", "val-crit"], ["(?<!\">)暴击伤害(?!<)", "val-crit-dmg"],
	["(?<!\">)额外伤害(?!<)", "val-extra"],
]


## 安全计算 expr: 用 Expression 把 ATK/atkScale… 替换成真值再算; 失败原样返回. PoC evalSkillExpr.
static func eval_expr(expr: String, vars: Dictionary) -> Variant:
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
		_token_re = RegEx.create_from_string("\\{([NPHSBDMT]):([^}]+)\\}|\\{([^}]+)\\}")
		_span_re = RegEx.create_from_string("<span\\s+(?:class=\"([^\"]+)\"|style=\"color:\\s*(#[0-9a-fA-F]+)[^\"]*\")[^>]*>([^<]*)</span>|([^<]+)")
		for rule in KEYWORD_RULES:
			_keyword_re.append([RegEx.create_from_string(rule[0]), rule[1]])


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
		var val = eval_expr(expr, vars)
		if color != "" and COLOR_CLASS.has(color):
			result += "<span class=\"%s\">%s</span>" % [COLOR_CLASS[color], str(val)]
		else:
			result += str(val)
		last = m.get_end()
	result += template.substr(last)
	# 2) 关键词自动上色
	for kr in _keyword_re:
		var re: RegEx = kr[0]
		var cls: String = kr[1]
		# 提取关键词文本: 用 sub 把每个匹配替换成 span; 匹配文本本身用 $0 (PCRE2 \0)
		result = re.sub(result, "<span class=\"%s\">$0</span>" % cls, true)
	return result


## HTML → BBCode (span → [color]; PoC parseRichText 的 Godot 等价).
static func html_to_bbcode(html: String) -> String:
	_ensure_re()
	var norm := html.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	# <b>/<i> 直转
	norm = norm.replace("<b>", "[b]").replace("</b>", "[/b]").replace("<i>", "[i]").replace("</i>", "[/i]")
	var out := ""
	for m in _span_re.search_all(norm):
		var cls := m.get_string(1)
		var inline := m.get_string(2)
		var inner := m.get_string(3)
		var plain := m.get_string(4)
		if cls != "" and inner != "":
			var hex: String = VAL_HEX.get(cls, "#ffffff")
			out += "[color=%s]%s[/color]" % [hex, inner]
		elif inline != "" and inner != "":
			out += "[color=%s]%s[/color]" % [inline, inner]
		elif plain != "":
			out += plain
	return out


## 便捷: 模板 → BBCode (RichTextLabel 直用).
static func render_bbcode(template: String, f: Dictionary, s: Dictionary) -> String:
	return html_to_bbcode(render_html(template, f, s))


## 便捷: 模板 → 纯文本 (无色, 仅展开数字; Label 用). 去掉所有 <…> 标签.
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
				seg += "[color=#5a6472]/[/color]"
			if i == star - 1:
				seg += "[b][color=%s]%s[/color][/b]" % [UIPalette.DEF, parts[i]]
			else:
				seg += "[color=#5a6472]%s[/color]" % parts[i]
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
