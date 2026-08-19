extends Node
## verify_codex_desc.gd — 图鉴「描述」整顿 (2026-08-14 用户需求5「图鉴描述需要优化」)
##
## ★实拍出来的四条毛病, 每条一个判据:
##   ① 效果正文字号 14 —— 全项目最小(商店 20 / 背包 18), 而图鉴恰恰是"专门来看资料"的地方
##   ② `+250/+250/+250` 同一个数抄三遍
##   ③ 三档数值同色平铺, `20/35/60+0.5/0.8/1.1×攻击力` 读起来像乱码
##   ④ 技能卡 `clip_contents` + 定高 ⇒ 长简述被【静默切断】, 玩家看不出后面还有内容
##
## ★判据一律量产品自己的账(常量/函数返回值/源码事实), 不数我插的标记。

const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
const SkillTextRef := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 图鉴描述整顿 ===")
	var src := FileAccess.get_file_as_string("res://scripts/scenes/codex/detail_views.gd")
	_ok("★分母: 读得到 detail_views.gd", src.length() > 4000, "%d 字符" % src.length())

	# ── ① 字号 ──────────────────────────────────────────────────────────
	_ok("★★① 装备效果正文字号 ≥ 18(原来 14, 全项目最小)",
		src.find('rt.add_theme_font_size_override("normal_font_size", 19)') >= 0)

	# ── ② 三档相同只写一遍 ────────────────────────────────────────────────
	## ★拿【真实装备】验, 不造假数据: 095 圣光护盾三星都是 +250 最大生命。
	var s95: String = EquipStats.stat_line_all_stars("p2eq_095")
	_ok("★分母: 095 有属性行", s95 != "" and s95 != "无属性加成", "「%s」" % s95)
	_ok("★★② 三档【相同】⇒ 只写一遍(原来 +250/+250/+250)",
		s95.find("/") < 0, "实得「%s」" % s95)
	## 反面: 三档【不同】的必须仍然分档写, 否则就是把信息弄丢了
	var s01: String = EquipStats.stat_line_all_stars("p2eq_001")
	_ok("★★② 反面: 三档不同的仍然分档(001 攻击力 +5/+12/+20)",
		s01.find("/") >= 0, "实得「%s」" % s01)

	# ── ③ 三色等亮 + 图例 ────────────────────────────────────────────────
	var col: String = SkillTextRef.color_all_stars("造成 20/35/60 点伤害")
	var c1: bool = col.find("[color=#ffffff]20[/color]") >= 0
	var c2: bool = col.find("[color=#7fe3ff]35[/color]") >= 0
	var c3: bool = col.find("[color=#ffd93d]60[/color]") >= 0
	_ok("★★★③ 三档各上各的色(★1白 / ★2青 / ★3金)", c1 and c2 and c3,
		"白=%s 青=%s 金=%s" % [str(c1), str(c2), str(c3)])
	## ★关键差别: 图鉴【不许】压暗任何一档 —— 玩家在资料页没有"我的星级",
	##   压暗等于暗示"这档跟你无关"。压暗色 #7d8ea0 是商店/背包 highlight_star 专用。
	_ok("★★★③ 图鉴不压暗任何一档(压暗色一个都不许出现)",
		col.find("#7d8ea0") < 0 and col.find("#5a6472") < 0)
	## 反面自证: highlight_star 确实会压暗 —— 证明上一条不是"两个函数都不压暗"的空检查
	var hl: String = SkillTextRef.highlight_star("造成 20/35/60 点伤害", 1)
	_ok("★★③ 反面分母: highlight_star 确实会压暗(否则上条是空检查)",
		hl.find("#7d8ea0") >= 0)
	var lg: String = SkillTextRef.star_legend_bbcode()
	_ok("★③ 图例三档齐全", lg.find("★1") >= 0 and lg.find("★2") >= 0 and lg.find("★3") >= 0)
	_ok("★★③ 图例与正文【同一套色】(不同色就成了两套读法)",
		lg.find("#ffffff") >= 0 and lg.find("#7fe3ff") >= 0 and lg.find("#ffd93d") >= 0)
	_ok("★③ 详情页真的把图例画出来了(不是只写了函数没人调)",
		src.find("SkillTextRef.star_legend_bbcode()") >= 0)
	_ok("★③ 属性行与效果段走同一个上色函数",
		src.count("SkillTextRef.color_all_stars(") >= 2,
		"调用 %d 处(属性行 + 效果段)" % src.count("SkillTextRef.color_all_stars("))

	# ── ④ 技能卡被切断要有提示 ────────────────────────────────────────────
	## ★判据必须【锚在技能卡这一处】: 全文有两处 `rt.fit_content = false`(另一处在成员清单视图),
	##   只搜这个字符串 ⇒ 把技能卡改回 true 照样绿 —— 我第一版就是这么写的, 反向验证时才发现。
	var i_card: int = src.find("func _render_skill_cards")
	var i_hit: int = src.find("var hit = Control.new()", i_card)
	var card_body: String = src.substr(i_card, maxi(0, i_hit - i_card))
	_ok("★分母: 切得出技能卡这一段源码", i_card > 0 and i_hit > i_card,
		"%d 字符" % card_body.length())
	_ok("★★★④ 技能卡【这一处】fit_content = false",
		card_body.find("rt.fit_content = false") >= 0
		and card_body.find("rt.fit_content = true") < 0)
	## ★这条是本文件最重要的一条: fit_content = true 时控件被撑到内容高度,
	##   `get_content_height() <= size.y` **恒成立** ⇒ "被切了就提示"永远不触发,
	##   而文字照样被卡片边缘切掉 —— 一个不会红的假检查。我第一版就是这么写的, 截图才看出来。
	## ★这条原来搜的是源码里那一行算式 `card_h - 82 - 8 - 18` —— **搜字符串的判据**,
	##   我一改算式(给金属边带让位)它就红, 可版面其实是变好了。
	##   改成量【这段代码真正保证的事】: 正文高度 = 卡高 − 头部 − 提示带 − 边带,
	##   也就是**四项都得扣掉**, 一项都不能少。少扣哪项, 提示就会压到正文上。
	##   (真正的几何验证在 verify_codex_layout 的活场景里, 那边量真实矩形。)
	var i_fit: int = src.find("func _fit_skill_cards")
	var fit_body: String = src.substr(i_fit, 900) if i_fit > 0 else ""
	_ok("★★★④ 卡底留了提示带(正文高度扣掉了头部/提示带/边带三项)",
		i_fit > 0 and fit_body.find("CARD_BODY_TOP") >= 0
		and fit_body.find("CARD_HINT_BAND") >= 0 and fit_body.find("CARD_PAD") >= 0,
		"切出 %d 字符" % fit_body.length())
	_ok("★★④ 被切断时挂「点开看全部」", src.find('l.text = "点开看全部 ▸"') >= 0)
	_ok("★★④ 提示要等一帧再判(刚 add_child 时 content_height = 0)",
		src.find("func _mark_card_clipped") >= 0
		and src.find("await host.get_tree().process_frame") >= 0)
	_ok("★④ 真的在卡片渲染里调了它(不是死函数)",
		src.find("_mark_card_clipped(rt, cx,") >= 0)

	# ── ④b 渲染后不许剩花括号 ────────────────────────────────────────────
	## ★为什么不在 python 侧用正则查: 2026-08-19 我那么干过, 报 {crit*100} 会漏到文面,
	##   **是错的** —— SkillText 的 token 正则第二个分支 `\{([^}]+)\}` 本来就支持
	##   裸表达式。**占位符会不会漏, 只能看渲染之后的产物。**
	var _ph_bad: Array = []
	var _expr_re := RegEx.create_from_string("[A-Z]{2,}[ ]*[:*]")
	var _ph_n := 0
	for _p in DataRegistry.all_pets:
		var _pa: Dictionary = _p.get("passive", {})
		var _tx: Array = []
		for _k in ["brief", "desc", "detail"]:
			if str(_pa.get(_k, "")) != "":
				_tx.append([str(_p.get("id", "")) + ".passive." + _k, str(_pa.get(_k, ""))])
		for _s in _p.get("skillPool", []):
			for _k2 in ["brief", "desc", "detail"]:
				if str(_s.get(_k2, "")) != "":
					_tx.append(["%s/%s.%s" % [_p.get("id", ""), _s.get("name", ""), _k2],
						str(_s.get(_k2, ""))])
		for _row in _tx:
			_ph_n += 1
			var _out := SkillText.render_plain(str(_row[1]), _p, {})
			## ★★判据第一版只查花括号残留 —— **反向验证当场拆穿**: 塞一个
			##   `{N:BADVAR*2}` 进去, 门禁照样绿。实测渲染结果是「BADVAR*2」——
			##   花括号被吃掉了, **原始表达式直接当文字显示给玩家**。
			##   ⇒ 还要查"渲染完还留着表达式长相的东西": 连续大写字母后面跟 : 或 *。
			##   (我们的文案是中文, 正常内容里不会出现这种形状。)
			if _out.find("{") >= 0 or _out.find("}") >= 0 					or _expr_re.search(_out) != null:
				_ph_bad.append("%s → %s" % [str(_row[0]), _out.substr(0, 24)])
	_ok("★分母: 真的渲染了文案(0 段 = 空检查)", _ph_n >= 200, "%d 段" % _ph_n)
	_ok("★★④b 渲染后没有残留花括号(占位符都替换掉了)", _ph_bad.is_empty(),
		"残留: %s" % str(_ph_bad.slice(0, 5)))

	# ── ⑤ 羁绊: 商店有、图鉴原来一个字都不提 ──────────────────────────────
	## ★2026-08-15 判据从"搜两个整句"改成【切出 _show_p2eq 这一段再搜三件事】。
	##   原来搜的是 `host._add_text(20, ty, "羁绊"` 和 `TYPES.get(_tp, {})` 两条整句 ——
	##   同一天把绝对 y 改成顺排(ty→_next_y)、把单类型改成多类型(_tp→tp1)就红了,
	##   而【羁绊阈值照样画得好好的】。整句 grep 守的是"我当时怎么写的", 不是"这件事还在不在"。
	##   切段(锚在 _show_p2eq 里)+ 分三件事查, 才是守住"阈值来自 Phase2Types 且真画了标题"。
	var i_eq: int = src.find("func _show_p2eq")
	var i_end: int = src.find("func _show_consumable", i_eq)
	var eq_body: String = src.substr(i_eq, maxi(0, i_end - i_eq))
	_ok("★分母: 切得出 _show_p2eq 这一段源码", i_eq > 0 and i_end > i_eq,
		"%d 字符" % eq_body.length())
	_ok("★★⑤ 图鉴装备页也说羁绊阈值(与商店同一份 Phase2Types)",
		eq_body.find('"羁绊"') >= 0
		and eq_body.find("host.Phase2Types.TYPES.get(") >= 0
		and eq_body.find('.get("tiers", [])') >= 0)

	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴描述整顿")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
