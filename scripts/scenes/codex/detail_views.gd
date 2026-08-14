class_name CodexDetail
extends RefCounted
const SkillTextRef := preload("res://scripts/util/skill_text.gd")   # 三档数值按★1高亮(与商店/背包同一份)
## 图鉴·右栏详情视图(龟/装备/羁绊(类型)/状态/规则/小将 13渲染函数)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

func _show_minion(kind: String) -> void:
	host._clear_detail()
	var mi: Dictionary = host.MINION_INFO.get(kind, {})
	if mi.is_empty():
		return
	host._add_image(100, 110, "res://assets/sprites/pets/%s" % mi["img"], 170, 170, true)
	var mid_x = 220.0
	host._add_text(mid_x, 30, str(mi["name"]), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(mid_x, 75, "深海小将", 14, "#888888", 0.0, 0.5)
	host._add_text(mid_x + 80, 75, str(mi["role"]), 14, "#58d3ff", 0.0, 0.5, true)
	host._add_text(mid_x, 112, "非统领单位 · 不可选入阵容 · 由系统补位生成", 13, "#7a8a96", 0.0, 0.5)
	host._add_text(mid_x, 140, "生命与攻击随等级 ×1.05 复利成长, 双抗为定值", 13, "#7a8a96", 0.0, 0.5)
	# 属性两列 (Lv1 值)
	var rows = [
		["最大生命值", str(mi["hp"]), "#06d6a0"], ["攻击力", str(mi["atk"]), "#ff9f43"],
		["护甲", str(mi["def"]), "#ffd93d"], ["魔抗", str(mi["mr"]), "#4dabf7"],
		["攻击间隔", "%s 秒" % str(mi["interval"]), "#d6e4f0"], ["攻击距离", str(mi["range"]), "#d6e4f0"],
		["移动速度", str(mi["spd"]), "#d6e4f0"], ["", "", ""],
	]
	for i in range(rows.size()):
		if str(rows[i][0]) == "":
			continue
		var cx: float = 500.0 + float(i % 2) * 200.0
		var cy: float = 30.0 + float(i / 2) * 38.0
		host._add_text(cx, cy, str(rows[i][0]), 13, "#888888", 0.0, 0.5)
		host._add_text(cx + 110.0, cy, str(rows[i][1]), 18, str(rows[i][2]), 0.0, 0.5, true)
	host._add_rect(host.DETAIL_W / 2.0, 195.0, host.DETAIL_W - 40, 1, "#ffd93d", 0.4)
	# 技能 + 被动
	var y = 216.0
	host._add_text(20, y, "技能 · %s  (%d 龟能)" % [str(mi["skill_name"]), int(mi["skill_cost"])], 17, "#58d3ff", 0.0, 0.0, true)
	y += 28.0
	y = _minion_body(str(mi["skill_desc"]), y) + 18.0
	for pv in mi.get("passives", []):
		host._add_text(20, y, "被动 · %s" % str(pv["name"]), 17, "#58d3ff", 0.0, 0.0, true)
		y += 28.0
		y = _minion_body(str(pv["desc"]), y) + 16.0

## 一段正文(自动换行), 返回下一段该起的 y.
func _minion_body(txt: String, y: float) -> float:
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, y)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = txt
	host.detail.add_child(rt)
	# ★2026-08-15 改成【问它自己占多高】, 不再按字数估行。
	#   原来是 `ceilf(txt.length() / 62.0) * 19` —— 62 这个"每行几个全角字"是照 13px 字号拍的,
	#   字号一改(13→16)整套间距就全错; 而且 BBCode 标记也被算进了 length()。
	#   同一个位置 2026-08-01 已经栽过一次(写成 host.ceilf ⇒ SCRIPT ERROR ⇒ return 永不执行 ⇒
	#   每段正文拿到同一个 y、全叠在一起, 用户报「精英小将的描述都挤在一块」)。
	#   get_combined_minimum_size() 是 RichTextLabel(fit_content) 自己算的真实高度, 与字号自洽
	#   —— 同一份写法在 _show_p2eq 已经用了(那边的效果段/羁绊块就是这么顺排的)。
	return y + maxf(20.0, rt.get_combined_minimum_size().y)


func _show_pet(pet: Dictionary) -> void:
	host._clear_detail()
	var rarity: String = pet.get("rarity", "C")
	var rarity_color: String = host.RARITY_COLOR.get(rarity, "#ffffff")
	var ctx = host._ctx_for(pet)
	var divider_y: float = 195.0

	# 1) 立绘 170×170 @(100,110) — 全身 idle 动画 sprite (1:1 PoC showPetDetail:285-296), 非头像
	host._add_pet_portrait(100, 110, pet, 170.0)

	# 2) 名字 (详情) y30 32px #ffd93d bold; 稀有度标签 14px灰 + 值28px彩
	# PoC L301: `Lv ${lv}.  ${pet.name}` (两空格). 图鉴默认等级 1 (getPetLevel 兜底).
	var mid_x = 220.0
	var lv: int = GameState.get_pet_level(str(pet.get("id", "")))
	host._add_text(mid_x, 30, "Lv %d.  %s" % [lv, pet.get("name", "?")], 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(mid_x, 75, "稀有度", 14, "#888888", 0.0, 0.5)
	host._add_text(mid_x + 60, 75, rarity, 28, rarity_color, 0.0, 0.5, true)

	# ★tag 区已删(用户2026-07-23 点5): 守护/元素/物理/法术等 10 种标签全是凑羁绊的, 龟间羁绊已废 → 全去。
	#   腾出的位置给【定位】(用户2026-07-28: 定位是移速/攻速的权威事实源, 玩家该看得到)。
	var _role: String = str(host.TurtleStats.ROLE.get(str(pet.get("id", "")), ""))
	if _role != "":
		host._add_text(mid_x, 112, "定位", 14, "#888888", 0.0, 0.5)
		host._add_text(mid_x + 60, 112, _role, 22, "#9ad0ff", 0.0, 0.5, true)

	# 3) 4 属性条 — statColX500 statRowH42; 方块 sqW5 sqH14 gap2 pitch7
	# m = 稀有度倍率 × 等级加成 (1:1 PoC CodexScene:168 RARITY_MULT×getLevelBonus); rarity_mult 取真值表(原硬编1.5/2.0=bug)
	var m: float = float(DataRegistry.rarity_mult.get(rarity, 1.0)) * (1.0 + (lv - 1) * 0.05)
	# ★移速/攻速(点5): 从 host.TurtleStats.STATS 单一事实源读, 与战斗同口径 ——
	#   移速【不缩放】(定值); 攻速=1/攻击间隔 且【+2%/级】(atk_interval /= 1+0.02*(lv-1), 见战斗 _make_unit); 都不乘 rarity_mult。
	var _tid = str(pet.get("id", ""))
	var _ts: Array = host.TurtleStats.STATS.get(_tid, [])
	var _mspd: int = int(round(float(_ts[1]))) if _ts.size() > 1 else 0
	var _aspd: float = (1.0 / float(_ts[2])) * (1.0 + 0.02 * float(lv - 1)) if _ts.size() > 2 and float(_ts[2]) > 0.0 else 0.0
	var stats = [
		{"key": "hp", "label": "最大生命值", "val": roundi(pet.get("hp", 0) * m), "disp": str(roundi(pet.get("hp", 0) * m)), "color": "#06d6a0", "div": 40.0},
		{"key": "atk", "label": "攻击力", "val": roundi(pet.get("atk", 0) * m), "disp": str(roundi(pet.get("atk", 0) * m)), "color": "#ff9f43", "div": 5.0},
		{"key": "def", "label": "护甲", "val": roundi(pet.get("def", 0) * m), "disp": str(roundi(pet.get("def", 0) * m)), "color": "#ffd93d", "div": 2.5},
		{"key": "mr", "label": "魔抗", "val": roundi(pet.get("mr", pet.get("def", 0)) * m), "disp": str(roundi(pet.get("mr", pet.get("def", 0)) * m)), "color": "#4dabf7", "div": 2.5},
		{"key": "move", "label": "移速", "val": _mspd, "disp": str(_mspd), "color": "#8fd4ff", "div": 15.0},
		{"key": "aspd", "label": "攻击速度", "val": roundi(_aspd * 100.0), "disp": ("%.2f" % _aspd) + " 次/秒", "color": "#ff9ecb", "div": 8.0},
	]
	var stat_col_x = 500.0
	var stat_row_h = 27.0   # ★6 行(加了移速/攻速)压行高, 容进分隔线上方(点5)
	var value_x = 700.0
	var bars_start_x = 716.0
	var sq_w = 5.0; var sq_h = 14.0; var sq_pitch = 7.0
	for i in stats.size():
		var st: Dictionary = stats[i]
		var sy = 22.0 + i * stat_row_h
		var _iconp: String = "res://assets/sprites/stats/%s-icon.png" % st["key"]
		if ResourceLoader.exists(_iconp):   # move/aspd 图标可能未画 → 缺图只显文字, 不崩
			host._add_image(stat_col_x, sy, _iconp, 24, 24)
		host._add_text(stat_col_x + 28, sy, st["label"], 15, "#bbbbbb", 0.0, 0.5)
		host._add_text(value_x, sy, str(st.get("disp", st["val"])), 21, st["color"], 1.0, 0.5, true)
		var count = int(floor(float(st["val"]) / float(st["div"])))
		for k in count:
			var sq_cx = bars_start_x + k * sq_pitch + sq_w / 2.0
			host._add_rect(sq_cx, sy, sq_w, sq_h, st["color"], 1.0)

	# 8) 横分隔线 y195 宽 detailW-40 #ffd93d@0.4 1px
	host._add_rect(host.DETAIL_W / 2.0, divider_y, host.DETAIL_W - 40, 1, "#ffd93d", 0.4)

	# 9) 被动条 y213 高 PASSIVE_BAR_H · 0x12202a@0.55 + 被动icon 40×40@x50
	var passive: Dictionary = pet.get("passive", {})
	var cards_y := divider_y + 87.0   # 无被动的龟(目前 0 只)也走同一个起点, 排版不跳
	if not passive.is_empty():
		var passive_y = divider_y + 18.0
		# 选中态(被动展开): 边框亮黄 2px@1; 否则蓝 1px@0.5 (1:1 PoC CodexScene.ts:366-393)
		var pbar_stroke: String = "#ffd93d" if host._codex_passive_view else "#58d3ff"
		var pbar_sw: float = 2.0 if host._codex_passive_view else 1.0
		var pbar_sa: float = 1.0 if host._codex_passive_view else 0.5
		host._add_rect(host.DETAIL_W / 2.0, passive_y + PASSIVE_BAR_H / 2.0, host.DETAIL_W - 40, PASSIVE_BAR_H,
			"#12202a", 0.55, pbar_stroke, pbar_sw, pbar_sa)
		var mid_y: float = passive_y + PASSIVE_BAR_H / 2.0
		var text_x = 30.0
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "":
			if pi_path.ends_with(".png"):
				host._add_image(50, mid_y, "res://assets/sprites/%s" % pi_path, 40, 40)
				text_x = 80.0
			else:
				host._add_text(50, mid_y, pi_path, 32, "#ffffff", 0.5, 0.5)
				text_x = 80.0
		host._add_text(text_x, mid_y, "被动 · %s" % passive.get("name", ""), 20, "#58d3ff", 0.0, 0.5, true)
		## ★★被动的简述【就画在条上】(2026-08-15, 用户点名的"同一屏两种交互")。
		##   原来这一条只有标题 + 一句「点击查看 ▸」, 而右边四张技能卡是【直接摊开简述】的 ——
		##   同一屏里同一类东西两种读法, 玩家还得先猜出被动是可以点的。
		##   现在与技能卡完全同构: **条上给简述, 点开看全文**。
		##   简述【横着放】(占标题右边那段本来空着的 500px), 所以条高只从 50 涨到 56 ——
		##   技能卡一寸没让。竖着排会吃掉 40px, 那正是卡片最缺的。
		var p_brief: String = str(passive.get("brief", passive.get("desc", "")))
		if p_brief.strip_edges() != "":
			var brt := RichTextLabel.new()
			brt.bbcode_enabled = true
			brt.fit_content = false     # 定高一行 + clip: 撑高就把技能卡挤下去了
			brt.scroll_active = false
			brt.clip_contents = true
			brt.position = Vector2(text_x + 168.0, mid_y - 12.0)
			brt.custom_minimum_size = Vector2(host.DETAIL_W - 40 - (text_x + 168.0) - 96.0, 24.0)
			brt.size = brt.custom_minimum_size
			brt.add_theme_font_size_override("normal_font_size", 15)
			brt.add_theme_color_override("default_color", Color("#aab8c6"))
			brt.text = SkillText.render_bbcode(p_brief, ctx, passive, 15)
			host.detail.add_child(brt)
		# hint: 展开→"收起 ▾"金 / 否则"展开全文 ▸"(与技能卡的"点开看全部 ▸"同一句式)
		var p_hint: String = "收起 ▾" if host._codex_passive_view else "展开全文 ▸"
		var p_hint_col: String = "#ffd93d" if host._codex_passive_view else "#7fb5d8"
		host._add_text(host.DETAIL_W - 30, mid_y, p_hint, 14, p_hint_col, 1.0, 0.5)
		# drill-down: 点被动条 → 内联展开/收起完整 passive desc (1:1 PoC showPetDetail view='passive' toggle, 非弹窗)
		var p_hit = Control.new()
		p_hit.position = Vector2(20, passive_y)
		p_hit.size = Vector2(host.DETAIL_W - 40, PASSIVE_BAR_H)
		p_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		p_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref2: Dictionary = pet
		p_hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_skill_detail = {}
				host._codex_passive_view = not host._codex_passive_view
				_show_pet(pet_ref2))
		host.detail.add_child(p_hit)
		cards_y = passive_y + PASSIVE_BAR_H + 18.0
	## 双形态龟(双头/熔岩)要给形态切换钮留一条带 —— 原来那颗钮写死 y=262, 正好压在被动条上。
	var _melee0 = pet.get("meleeSkills", [])
	var _volc0 = pet.get("volcanoSkills", [])
	if (_melee0 is Array and not (_melee0 as Array).is_empty()) \
			or (_volc0 is Array and not (_volc0 as Array).is_empty()):
		cards_y += 42.0

	# 10) 技能卡 — 4 卡 1 行, 铺满板宽, 每卡高度按自己的正文收(见 _render_skill_cards)
	_render_skill_cards(pet, ctx, cards_y)


# ─── 技能卡 (1:1 PoC renderSkillListSection) ───
## 被动条高。原来 50(只放得下标题), 现在条上还要放一行简述 —— 简述横排在标题右边, 只多 6px。
const PASSIVE_BAR_H := 56.0
## 卡片底部那条提示带的高度(平时空着, 正文真被切了才画"点开看全部 ▸")。
const CARD_HINT_BAND := 18.0
## 卡片正文的起始 y(卡内相对) —— 图标 44 + 名字 + 类型 chip 之后。
const CARD_BODY_TOP := 82.0
## 卡片最矮不低于这个(只有两行字的普攻卡也不该缩成一条)。
const CARD_MIN_H := 150.0

## 每张卡收完高度后, 它那条提示带该画在哪个 y(卡内绝对 y)。
## 键是 RichTextLabel 实例 —— _mark_card_clipped 拿它取自己那张卡的真实底边。
## (不是单位字典, 可以安全做键; 见 CLAUDE.md §3.2 说的是战斗单位字典)
var _card_hint_y: Dictionary = {}

## 技能卡的简述被切断时, 在卡片底部那条留白里画一行"点开看全部 ▸"。
##
## ★必须等一帧才问 `get_content_height()` —— 刚 add_child 时还没排版, 拿到 0 ⇒ 永远判"没被切",
##   提示永远不出现(这就是个不会红的假检查)。同 ShopScene._add_scroll_hint 那条。
## ★这里等【两帧】: 第一帧让 _fit_skill_cards 把每张卡收到自己的正文高度(它只等一帧),
##   第二帧才轮到这里判"收完之后还超不超"。少等一帧就会拿收缩前的 size.y 判断 ⇒ 全判成"被切"。
func _mark_card_clipped(rt: RichTextLabel, cx: float, y: float, card_w: float) -> void:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not is_instance_valid(rt) or not is_instance_valid(host) or host.detail == null:
		return
	if rt.get_content_height() <= rt.size.y + 0.5:
		return
	y = float(_card_hint_y.get(rt, y))   # 收缩后各卡底边不同; 没登记就用调用侧给的兜底值
	var l := Label.new()
	l.text = "点开看全部 ▸"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#7fb5d8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(cx + 8, y)
	l.size = Vector2(card_w - 16, 16)
	host.detail.add_child(l)


func _render_skill_cards(pet: Dictionary, ctx: Dictionary, cards_y: float) -> void:
	_card_hint_y.clear()
	# 内联技能详情页 (1:1 PoC showPetDetail view={skillIdx} → renderSkillDetailSection): 顶部"← 返回列表" + 完整 host.detail
	if not host._codex_skill_detail.is_empty():
		_render_skill_detail_inline(pet, ctx, host._codex_skill_detail, cards_y)
		return
	# 内联被动详情 (1:1 PoC showPetDetail view='passive' → renderPassiveDetailSection): 下方区显完整 desc
	if host._codex_passive_view and not (pet.get("passive", {}) as Dictionary).is_empty():
		_render_passive_detail_inline(pet, ctx, cards_y)
		return
	# E1 双形态 (PoC CodexScene.ts:401-405): 近战(meleeSkills 双头) / 火山(volcanoSkills 熔岩)
	var melee = pet.get("meleeSkills", [])
	var volcano = pet.get("volcanoSkills", [])
	var is_melee_form: bool = melee is Array and not (melee as Array).is_empty()
	var form_skills: Array = (melee if is_melee_form else (volcano if volcano is Array else [])) as Array
	var has_form: bool = not form_skills.is_empty()
	var skill_pool = form_skills if (host._codex_form_view and has_form) else pet.get("skillPool", [])
	if not (skill_pool is Array):
		return
	var default_idxs = pet.get("defaultSkills", [0, 1, 2])
	var gap = 8.0
	var start_x = 20.0
	var start_y: float = cards_y
	var n: int = mini(skill_pool.size(), 5)
	## ★卡片【铺满板宽】(2026-08-15)。原来写死 168 宽: 28 只龟每只都是 4 个技能,
	##   4×168 + 3×8 = 696 画在 900 宽的板子上 ⇒ 右边【死空 184px, 整整一张卡的宽度】,
	##   而卡里的字同时又窄到放不下(实拍 4 张里 3 张被切)。宽度按卡数分, 空白清零、每行多 3 个字。
	var card_w: float = (host.DETAIL_W - 2.0 * start_x - float(n - 1) * gap) / float(n)
	## 卡片最高不超过详情框剩下的高度 —— 超了就得滚动才能看完一行卡, 比截断更难用。
	var card_max_h: float = maxf(CARD_MIN_H, host.DETAIL_MAX_H - start_y - 14.0)
	var card_h: float = card_max_h
	var parts: Array = []   # 每张卡的 {panel, rt, hit}, 建完统一按各自正文收高
	for i in n:
		var sk: Dictionary = skill_pool[i]
		if sk.is_empty():
			continue
		var cx: float = start_x + i * (card_w + gap)
		var is_default: bool = i in default_idxs
		# ★2026-07-10 去掉「idx3需Lv4 / idx4需Lv7」等级解锁 (回合制PoC残留, 与3选1冲突; 详见 TeamSelectScene._available_skill_indices)
		var is_locked: bool = false
		# 卡背/边框: 锁=暗灰#6b7686 / 默认技能=绿#06d6a0 / 普通=蓝#4a93d6
		var border: String = "#6b7686" if is_locked else ("#06d6a0" if is_default else "#4a93d6")
		var border_w: float = 2.5 if (is_default and not is_locked) else 2.0
		var bg_hex: String = "#141d2a" if is_locked else "#18283c"
		var bg_a: float = 0.7 if is_locked else 0.92
		var card_panel: Panel = host._add_rect(cx + card_w / 2.0, start_y + card_h / 2.0, card_w, card_h, bg_hex, bg_a, border, border_w, 1.0)
		# 图标 38×38 (skills/<icon>.png), "+" 强化角标
		var icon: String = sk.get("icon", "")
		var enhances: bool = sk.get("enhancesPassive", false)
		var icon_src: String = ""
		if icon != "" and icon.ends_with(".png"):
			icon_src = icon
		elif enhances and not pet.get("passive", {}).is_empty():
			var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
			if pic.ends_with(".png"):
				icon_src = pic
		var name_x: float = cx + 8
		if icon_src != "":
			# PoC skillIconHtml: 图标带金框 socket (深底+金边1.5px radius8); 原裸图无框 (用户报"很多地方技能都没有框")
			var sock = Panel.new()
			var sock_sb = StyleBoxFlat.new()
			sock_sb.bg_color = Color(0.04, 0.06, 0.09, 0.7)
			sock_sb.border_color = Color(1.0, 0.851, 0.4, 0.5)   # PoC border rgba(255,217,102,.5)
			sock_sb.set_border_width_all(2)
			sock_sb.set_corner_radius_all(8)
			sock.add_theme_stylebox_override("panel", sock_sb)
			sock.position = Vector2(cx + 8 + 19 - 22, start_y + 8 + 19 - 22)
			sock.custom_minimum_size = Vector2(44, 44); sock.size = Vector2(44, 44)
			host.detail.add_child(sock)
			host._add_image(cx + 8 + 19, start_y + 8 + 19, "res://assets/sprites/%s" % icon_src, 38, 38)
			name_x = cx + 61
			if enhances or sk.get("iconPlus", false):
				host._add_text(cx + 8 + 38 - 6, start_y + 8 - 2, "+", 15, "#06d6a0", 0.5, 0.5, true)
		# 名字 16px (锁=灰)
		var nlbl = host._add_text(name_x, start_y + 18, sk.get("name", "?"), 16, ("#bbbbbb" if is_locked else "#ffd93d"), 0.0, 0.5, true)
		nlbl.custom_minimum_size = Vector2(card_w - (name_x - cx) - 8, 0)
		# 类型 chip 行 (锁→Lv.N解锁 / 否则 基础/主动CDn/被动)
		var chip_text = ""
		var chip_color = "#58d3ff"
		if is_locked:
			chip_text = "🔒"; chip_color = "#ff8888"
		else:
			# 龟能口径 (无"冷却/CD"): 普攻=不花龟能 / 主动=显龟能花费(与战斗同源) / 被动
			match host._skill_role(str(pet.get("id", "")), sk, i):
				"passive": chip_text = "被动"; chip_color = "#c77dff"
				"basic": chip_text = "基础 · 普攻"; chip_color = "#58d3ff"
				_: chip_text = "3选1候选 · 龟能%d" % host._skill_energy(sk); chip_color = "#06d6a0"
		host._add_text(cx + 8, start_y + 60, chip_text, 13, chip_color, 0.0, 0.0)
		# 简述 — 富文本 BBCode, 多行 clamp
		var brief = SkillText.render_bbcode(str(sk.get("brief", "")), ctx, sk, 13)
		var rt = RichTextLabel.new()
		rt.bbcode_enabled = true
		## ★fit_content 必须是 false: 它会把控件撑到内容高度, 于是
		##   `get_content_height() <= size.y` **恒成立** —— 我加的"被切了就提示"永远不触发,
		##   而文字照样被卡片边缘切掉。这就是个不会红的假检查(等一帧也救不了)。
		rt.fit_content = false
		rt.scroll_active = false
		rt.position = Vector2(cx + 8, start_y + CARD_BODY_TOP)
		## ★底部再留 18px(2026-08-14, 用户「图鉴描述需要优化」):
		##   卡片 `clip_contents = true` + 定高 ⇒ 长简述被**静默切断**, 实拍「过肩摔」停在
		##   "施法期间小龟露体（不可" 就没了, 玩家看不出后面还有内容, 也不知道点卡片能看全。
		##   这条带子平时是空的, 真被切了才画一行"点开看全部"。
		var rt_h: float = card_h - 82 - 8 - 18
		rt.custom_minimum_size = Vector2(card_w - 16, rt_h)
		rt.size = Vector2(card_w - 16, rt_h)
		rt.clip_contents = true
		rt.add_theme_font_size_override("normal_font_size", 13)
		rt.add_theme_color_override("default_color", Color("#aaaaaa"))
		rt.text = brief
		host.detail.add_child(rt)
		_mark_card_clipped(rt, cx, start_y + card_h - 22.0, card_w)
		# drill-down: 点技能卡 → 内联换页显示完整 host.detail (1:1 PoC showPetDetail view={skillIdx}→renderSkillDetailSection)
		var hit = Control.new()
		hit.position = Vector2(cx, start_y)
		hit.size = Vector2(card_w, card_h)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sk_ref: Dictionary = sk
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_skill_detail = sk_ref
				_show_pet(pet))
		host.detail.add_child(hit)
		parts.append({"panel": card_panel, "rt": rt, "hit": hit})
	_fit_skill_cards(parts, start_y, card_max_h)
	# E1 形态切换钮 (1:1 PoC CodexScene.ts:417-431) — 仅双形态龟显示, 切普通↔形态技能
	if has_form:
		## ★钮的尺寸/位置都改了(2026-08-15):
		##   · 220×30 = 7.3:1 的又扁又宽片(用户刚为商店的扁按钮发过火) → 196×34。
		##   · 原来写死 btn_y=262, 而被动条占 213~263 ⇒ 【钮压在被动条上】, 双形态那两只
		##     (双头龟/熔岩龟)一直是这么画的。现在钉在卡片上沿那条空带里(_show_pet 为它留了 42px)。
		var btn_w = 196.0
		var btn_h = 34.0
		var btn_x = host.DETAIL_W - 20.0 - btn_w / 2.0
		var btn_y = start_y - 22.0
		var label: String
		if is_melee_form:
			label = "🏹 查看 远程形态技能" if host._codex_form_view else "⚔️ 查看 近战形态技能"
		else:
			label = "🐢 查看 普通形态技能" if host._codex_form_view else "🌋 查看 火山形态技能"
		var bg_hex = "#3a1810" if host._codex_form_view else "#2a1430"
		var border_hex = "#58d3ff" if host._codex_form_view else "#ff7043"
		var txt_hex = "#9fd8ff" if host._codex_form_view else "#ffae80"
		host._add_rect(btn_x, btn_y, btn_w, btn_h, bg_hex, 0.92, border_hex, 2.0, 1.0)
		host._add_text(btn_x, btn_y, label, 14, txt_hex, 0.5, 0.5, true)
		var hitb = Control.new()
		hitb.position = Vector2(btn_x - btn_w / 2.0, btn_y - btn_h / 2.0)
		hitb.size = Vector2(btn_w, btn_h)
		hitb.mouse_filter = Control.MOUSE_FILTER_STOP
		hitb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref: Dictionary = pet
		hitb.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_form_view = not host._codex_form_view
				_show_pet(pet_ref))
		host.detail.add_child(hitb)


## ★每张卡收到【自己那段正文】的高度(2026-08-15, 用户点名"短的留大片空白、长的被切")。
##
## 改前实测(小龟 4 张卡, 卡内余白): 普攻卡 138px 全空, 另外两张反而【溢出 22 / 42px 被切掉】——
## 一排等高卡片, 高度是照最长的那条定的, 于是最短的那张空掉一半、最长的那张还是不够。
##
## ★必须等一帧才量: RichTextLabel 刚 add_child 时没排版, get_content_height() 返回 0
##   ⇒ 每张卡都会被收成最矮的 CARD_MIN_H(而且不报错)。这跟 _mark_card_clipped 是同一个坑。
## ★只等【一帧】: _mark_card_clipped 等两帧, 靠这个差值保证"先收高、再判还超不超"的顺序。
func _fit_skill_cards(parts: Array, top: float, max_h: float) -> void:
	await host.get_tree().process_frame
	if not is_instance_valid(host) or host.detail == null:
		return
	for p in parts:
		var panel: Panel = p["panel"]
		var rt: RichTextLabel = p["rt"]
		var hit: Control = p["hit"]
		if not (is_instance_valid(panel) and is_instance_valid(rt) and is_instance_valid(hit)):
			continue
		var want: float = clampf(CARD_BODY_TOP + rt.get_content_height() + 8.0 + CARD_HINT_BAND,
			CARD_MIN_H, max_h)
		panel.position.y = top
		panel.custom_minimum_size.y = want
		panel.size.y = want
		hit.size.y = want
		rt.custom_minimum_size.y = want - CARD_BODY_TOP - 8.0 - CARD_HINT_BAND
		rt.size.y = rt.custom_minimum_size.y
		# 提示带跟着这张卡自己的底边走 —— 各卡高度不同, 不能再用一个统一的 y
		_card_hint_y[rt] = top + want - 22.0


## 内联技能详情 (1:1 PoC renderSkillDetailSection CodexScene.ts:532-568): 顶"← 返回列表"(蓝) + 标题行(图标+★+名32px+CD) + 完整 host.detail #fff 13px
func _render_skill_detail_inline(pet: Dictionary, ctx: Dictionary, sk: Dictionary, top: float) -> void:
	# 返回钮 100×34, fill #1a2740@0.9 边 #58d3ff 1px@0.6; 文字 14px #58d3ff (PoC L539-549)
	host._add_rect(70, top + 17.0, 100, 34, "#1a2740", 0.9, "#58d3ff", 1, 0.6)
	host._add_text(70, top + 17.0, "← 返回列表", 14, "#58d3ff", 0.5, 0.5)
	var bhit = Control.new()
	bhit.position = Vector2(20, top)
	bhit.size = Vector2(100, 34)
	bhit.mouse_filter = Control.MOUSE_FILTER_STOP
	bhit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bhit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			host._codex_skill_detail = {}
			_show_pet(pet))   # host._codex_form_view 保留 → 返回到形态/普通列表 (PoC isForm?'form-list':'skill-list')
	host.detail.add_child(bhit)
	# 标题行 (PoC L552-558 addDomHTML(160,283) origin(0,0)): 图标40 inline + ★(默认绿) + 名32px#ffd93d + CD chip 20px#06d6a0
	# 默认技能判定: 形态视图不算默认 (PoC isDefault = !isForm && defaultSkills.includes(idx))
	var is_default = false
	if not host._codex_form_view:
		var sp = pet.get("skillPool", [])
		if sp is Array:
			var dfs = pet.get("defaultSkills", [0, 1, 2])
			is_default = (sp as Array).find(sk) in dfs
	# 图标解析同技能卡 (1:1 PoC skillIconHtml): 有png用; 否则 enhancesPassive→取被动图标
	var icon: String = str(sk.get("icon", ""))
	var icon_src: String = ""
	if icon.ends_with(".png"):
		icon_src = icon
	elif sk.get("enhancesPassive", false) and not (pet.get("passive", {}) as Dictionary).is_empty():
		var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
		if pic.ends_with(".png"):
			icon_src = pic
	var sp_role: Array = pet.get("skillPool", []) if pet.get("skillPool") is Array else []
	var role_d: String = host._skill_role(str(pet.get("id", "")), sk, sp_role.find(sk))
	var bb = ""
	if icon_src != "":
		bb += "[img=40x40]res://assets/sprites/%s[/img] " % icon_src
	if is_default:
		bb += "[color=#06d6a0][font_size=28]★[/font_size][/color] "
	bb += "[color=#ffd93d][font_size=32]%s[/font_size][/color]" % str(sk.get("name", "?"))
	if role_d == "active":   # 龟能口径: 主动技显龟能花费 (无"CD"); 攒满龟能自动施放
		bb += "　[color=#06d6a0][font_size=20]龟能%d[/font_size][/color]" % host._skill_energy(sk)
	var title = RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 内联图标像素锐利
	title.position = Vector2(160, top + 3.0)
	title.custom_minimum_size = Vector2(host.DETAIL_W - 180, 48)
	title.add_theme_font_size_override("normal_font_size", 32)
	title.add_theme_color_override("default_color", Color("#ffffff"))
	title.text = bb
	host.detail.add_child(title)
	## 完整正文。★字号 13 → 17: 这是"点开技能看全部"的落地页, 全项目最小的字放在这里最没道理
	##   (同一屏的装备效果正文是 19)。★fit_content 撑高 + 外层详情自己会滚(2026-08-03),
	##   不再自己开 scroll_active —— 框里套框的滚动条玩家根本发现不了。
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(20, top + 58.0)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = SkillText.render_bbcode(str(sk.get("detail", sk.get("brief", ""))), ctx, sk, 17)
	host.detail.add_child(rt)


## 内联被动详情 (1:1 PoC renderPassiveDetailSection CodexScene.ts:572-582): 完整 desc 占下方区
func _render_passive_detail_inline(pet: Dictionary, ctx: Dictionary, top: float) -> void:
	var passive: Dictionary = pet.get("passive", {})
	if passive.is_empty():
		return
	var full_desc: String = str(passive.get("desc", passive.get("brief", "")))
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(20, top)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = SkillText.render_bbcode(full_desc, ctx, passive, 17)
	host.detail.add_child(rt)


# ─── 其余 tab 详情 (沿用同详情容器, 数据 1:1) ───
# 装备详情: 消耗品(all_equipment, 有 category=consumable+desc) 与 p2eq(phase2_equipment, 有 cost) 两种数据形态。
# ─── 其余 tab 详情 (沿用同详情容器, 数据 1:1) ───
# 装备详情: 消耗品(all_equipment, 有 category=consumable+desc) 与 p2eq(phase2_equipment, 有 cost) 两种数据形态。
func _show_equip(eq: Dictionary) -> void:
	if eq.get("category", "") == "consumable":
		_show_consumable(eq)
	else:
		_show_p2eq(eq)


# ── p2eq 装备详情 (data/phase2-equipment.json 字段) ──
#   头图: PNG 图标(img·2026-07-18装备图标)→无 img 才 emoji 徽章兜底。名 + 费用 + 类型(p2eq-types) + 类型(p2eq-types) + 属性(EquipStats.STATS) + 效果(effectDesc1/3)。
# ── p2eq 装备详情 (data/phase2-equipment.json 字段) ──
#   头图: PNG 图标(img·2026-07-18装备图标)→无 img 才 emoji 徽章兜底。名 + 费用 + 类型(p2eq-types) + 类型(p2eq-types) + 属性(EquipStats.STATS) + 效果(effectDesc1/3)。
func _show_p2eq(eq: Dictionary) -> void:
	host._clear_detail()
	var cost: int = int(eq.get("cost", 0))
	var ccol: String = host.COST_COLOR.get(cost, "#4cc9f0")
	var rcol: String = ccol
	var emoji: String = str(eq.get("emoji", "📦"))
	# 头图区: PNG 图标(新版 img·2026-07-18装备图标)→无则 emoji 徽章框兜底 (中心锚 @(60,70))
	var img: String = str(eq.get("img", ""))
	var ipath: String = "res://assets/sprites/%s" % img if img.ends_with(".png") else ""
	host._add_rect(60, 70, 90, 90, "#12202a", 0.55, rcol, 2.0, 0.9)
	if ipath != "" and ResourceLoader.exists(ipath):
		host._add_image(60, 70, ipath, 78, 78, true)
	else:
		host._add_text(60, 70, emoji, 44, rcol, 0.5, 0.5, true)
	# 名 30px 黄 + 副标(费用 · 类型)
	host._add_text(130, 34, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	# 类型: 真类型(11种·p2eq-types.json)。旧 series/category 字段已废弃删除(用户2026-07-19)
	## ★取【全部】类型: p2eq_093 香火石有两个羁绊(遗物 + 香火, 用户 2026-08-13 拍板),
	##   而 type_of 只给第一个 ⇒ 详情页从来没提过它还吃香火羁绊。
	var _tps: Array = host.Phase2Types.types_of(str(eq.get("id", "")))
	var _tp: String = str(_tps[0]) if not _tps.is_empty() else ""
	## ★2026-08-15 副标【一行说完费用+类型】(原来费用一行、类型又一行, 而类型那一行
	##   跟页底的羁绊块把同一个类型名写了两遍 —— 用户点名「有没有说两遍的信息」)。
	## ★羁绊名【只写它本身】("剑"), 不用 Phase2Types.display_name —— 那个返回
	##   「剑系」「弓箭·神射手」这类游戏里根本不存在的花名(用户 2026-08-14 已让商店删过一次,
	##   见 ShopScene.gd:799 的同款注释)。
	## ★费用 0 = 盾羁绊赠送的圣光护盾, 它不上商店所以没有费用; 写"费用 0"读起来像"免费"。
	##   左栏分组标题早就写的是"羁绊赠送"(list_builder.gd:178), 详情跟着对齐。
	var sub: String = ("羁绊赠送" if cost <= 0 else "费用 %d" % cost)
	for tp0 in _tps:
		sub += "   ·   %s %s" % [host._type_emoji(str(tp0)), str(tp0)]
	host._add_text(130, 74, sub, 17, ccol, 0.0, 0.5, true)

	## ── 以下各块【按实测高度顺排】(2026-08-15) ────────────────────────────
	## 原来是一串写死的绝对 y(134/154/200/224…): 上面任何一块长了就压住下一块、短了就留洞。
	## 2026-08-03 删「学派」那一行时就踩过 —— 删完留了 24px 空洞, 只能手工把下面每块都减 24,
	## 而【没有任何门禁抓得到】(见当时的注释)。现在每块画完问它自己占了多高, 下一块接着画。
	const HEAD_SIZE := 17     # 小标题(原来 14 —— 比它自己的正文 19 还小一大截)
	const BLOCK_GAP := 22.0
	var y := 130.0

	# 属性 —— 取自 host.EquipStats.STATS(战斗实装的同一张表), 不再打印 data 里手写的 baseStats1。
	# baseStats1 只是 STATS 的人工镜像, 无机制保证一致; 走这里则图鉴与实装天然同源。
	host._add_text(20, y, "属性", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
	y += 26.0
	var _eid: String = str(eq.get("id", ""))
	var _stat_str: String = host.EquipStats.stat_line_all_stars(_eid)
	## ★属性行也走三色分档 —— 与下面「效果」里的三档同一套配色, 否则同一屏两种读法。
	##   原来是纯 Label(单色 #ffd93d), `+5/+10/+20` 三档挤成一串。
	var srt := RichTextLabel.new()
	srt.bbcode_enabled = true; srt.fit_content = true; srt.scroll_active = false
	srt.position = Vector2(20, y)
	srt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	srt.add_theme_font_size_override("normal_font_size", 17)
	srt.text = SkillTextRef.color_all_stars(_stat_str)
	host.detail.add_child(srt)
	y += maxf(24.0, srt.get_combined_minimum_size().y) + BLOCK_GAP

	# 效果 (effectDesc1 = 1星基础 / effectDesc3 = 3星升级)
	host._add_text(20, y, "效果", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
	y += 26.0
	var bb = str(eq.get("effectDesc1", ""))
	var d3: String = str(eq.get("effectDesc3", ""))
	if d3.strip_edges() != "":
		bb += "\n\n[color=%s][b]%s[/b][/color]" % [rcol, d3]
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, y)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	## ★字号 14 → 19(2026-08-14, 用户「图鉴描述需要优化」)。
	##   实拍: 图鉴的效果正文是全项目【最小】的一处 —— 商店 20 / 背包 18 / 图鉴 14,
	##   而图鉴恰恰是"专门来看资料"的地方。同一屏右侧还空着 ~60%, 小字纯属没道理。
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.add_theme_constant_override("line_separation", 6)
	## ★三档数值【三色等亮】—— 图鉴是资料页, 玩家在这里没有"我的星级",
	##   用 highlight_star 压暗另两档等于暗示错误信息; 但三档同色平铺又读不出边界。
	##   ⇒ color_all_stars(★1白/★2青/★3金) + 下面一行图例。
	var has_tiers: bool = bb.find("/") >= 0
	rt.text = SkillTextRef.color_all_stars(bb) if has_tiers else bb
	host.detail.add_child(rt)
	var _next_y := y + maxf(24.0, rt.get_combined_minimum_size().y) + BLOCK_GAP
	## ── 羁绊(类型阈值) ────────────────────────────────────────────────
	## ★图鉴原来【一个字都不提羁绊】, 而羁绊是这件装备最重要的搭配信息。
	##   商店详情里有(右上角小签), 图鉴反而没有 —— 同一份信息两个界面不一致。
	if has_tiers:
		var lg := RichTextLabel.new()
		lg.bbcode_enabled = true; lg.fit_content = true; lg.scroll_active = false
		lg.position = Vector2(20, _next_y)
		lg.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
		lg.add_theme_font_size_override("normal_font_size", 16)
		lg.text = "数值分档: " + SkillTextRef.star_legend_bbcode()
		host.detail.add_child(lg)
		_next_y += 34.0
	if not _tps.is_empty():
		host._add_text(20, _next_y, "羁绊", HEAD_SIZE, "#58d3ff", 0.0, 0.0, true)
		var ty := _next_y + 26.0
		for tp1 in _tps:
			var tiers: Array = (host.Phase2Types.TYPES.get(str(tp1), {}) as Dictionary).get("tiers", [])
			if tiers.is_empty():
				continue
			var ps: PackedStringArray = []
			for t in tiers:
				ps.append(str(int(t)))
			## ★类型的图标不在这里【再画一遍】—— 头顶副标已经写了「🗡️ 剑」。
			##   原文是「🗡️ 剑系 —— 队伍装满 3/6/9 件同类型即激活对应档位」, 同一屏两遍, 还带花名。
			##   两个羁绊的装备(香火石)才写类型名区分, 单羁绊的只写阈值。
			var line: String = ("%s: " % str(tp1)) if _tps.size() > 1 else ""
			## 只有一档的类型(香火)不能写"依次激活各档位" —— 它压根没有第二档。
			line += ("队伍里装满 %s 件同类型装备即激活" % ps[0]) if ps.size() == 1 \
				else ("队伍里装满 %s 件同类型装备, 依次激活各档位效果" % "/".join(ps))
			host._add_text(20, ty, line, 17, "#9fb6c9", 0.0, 0.0, true)
			ty += 26.0


# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
func _show_consumable(eq: Dictionary) -> void:
	host._clear_detail()
	var icon: String = str(eq.get("icon", ""))
	if icon.ends_with(".png"):
		host._add_image(90, 90, "res://assets/sprites/%s" % icon, 120, 120, true)
	host._add_text(180, 34, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	# 副标一行说完【消耗品 + 作用目标】(原来是两个 Label 硬摆在 x=180 和 x=240, 名字一长就撞)
	var tgt: String = str(eq.get("target", ""))
	var tgt_label: String = str({"ally": "作用于友方", "enemy": "作用于敌方"}.get(tgt, ""))
	host._add_text(180, 72, "消耗品" + ("   ·   " + tgt_label if tgt_label != "" else ""),
		16, "#06d6a0", 0.0, 0.5, true)
	host._add_text(20, 150, "描述", 17, "#58d3ff", 0.0, 0.0, true)
	var desc = SkillText.render_bbcode(str(eq.get("desc", "")), {"atk": 0, "def": 0, "mr": 0, "maxHp": 0}, {}, 17)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	## ★正文挪到整幅宽(20)、不再缩在图右边那 720px 里 —— 图只有 120 高, 正文从它下面走。
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = desc
	host.detail.add_child(rt)


# ─── 类型羁绊详情 (2026-08-03 批1 取代学派详情) — 名 + 档阈值 + 成员装备 + 逐档效果文案 ───
#   数据: 类型定义 host.Phase2Types.TYPES(阈值) / 逐档文案 Phase2Types.TIER_DESCS / 成员装备 p2eq-types.json。
#   ★逐档文案【不再在图鉴里手抄一份】: 旧版 CodexScene.SCHOOL_EFFECTS 与 phase2_schools.gd 是两份
#   互相矛盾的口径(一份写"每2.5秒"、一份写"每回合开始")且都自称权威。现在只有 TIER_DESCS 一份。
#   排版骨架 1:1 沿用旧 _show_school, 只换数据源。
func _show_type(item: Dictionary) -> void:
	host._clear_detail()
	var tname: String = str(item.get("_type", ""))
	var def: Dictionary = host.Phase2Types.TYPES.get(tname, {})
	# 类型的色/图标只走 host 那一对取值函数 —— 三处各自 `TYPE_STYLE.get(...)` 加各自的兜底,
	# 正是「香火在羁绊页是 🔗、在装备页是 🗡️」那种两处默认值不一样的来源。
	var color: String = host._type_color(tname)
	var emoji: String = host._type_emoji(tname)
	var tiers: Array = def.get("tiers", [])
	var members: Array = _type_members(tname)   # [{id,name,emoji}], 该类型全部装备

	# 头图区: 无 tag PNG → 类型色框 + emoji 徽章
	host._add_rect(60, 70, 90, 90, "#12202a", 0.55, color, 2.0, 0.9)
	host._add_text(60, 70, emoji, 44, color, 0.5, 0.5, true)
	# 名 32px 类型色 + 副标 + 档阈值 / 成员件数
	host._add_text(130, 36, tname, 32, color, 0.0, 0.5, true)
	## ★副标不写 display_name —— 那返回「剑系」「弓箭·神射手」这类游戏里不存在的花名(用户 2026-08-14)。
	##   而且大标题已经写了类型名, 副标再写一遍就是同一屏说两遍。这里只说它【是什么】。
	host._add_text(130, 72, "装备类型羁绊", 15, "#888888", 0.0, 0.5)
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	# ★顶档 == 该类型【最终】件数是有意设计(方案书 D5)。批 3 加完 35 件之前顶档够不到,
	#   这里如实显示"现有 N 件", 玩家自己看得出还差几件, 不写"不可达"这种开发者口吻的字。
	host._add_text(130, 100, "激活 %s 件   ·   现有装备 %d 件" % [thresh, members.size()], 16, color, 0.0, 0.5, true)

	# 逐档效果文案 (事实源 Phase2Types.TIER_DESCS, 与背包羁绊面板同一份)
	host._add_text(20, 150, "羁绊效果", 17, "#58d3ff", 0.0, 0.0, true)
	var descs: Array = host.Phase2Types.TIER_DESCS.get(tname, [])
	var bb := ""
	for i in range(descs.size()):
		var txt: String = str(descs[i])
		if txt.strip_edges() == "":
			continue
		var th: int = int(tiers[i]) if i < tiers.size() else 0
		bb += ("" if bb == "" else "\n\n") + "[color=%s][b]%d 件[/b][/color]  %s" % [color, th, txt]
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	## ★2026-08-15 改回撑高 + 让【外层详情】滚。原来是"固定 260px 框 + 框内自己滚":
	##   · 短的类型(剑 3 档)内容只有 ~150px ⇒ 框里空 110px, 而下面的成员清单又写死在 y=446,
	##     两处死空白叠一块;
	##   · 长的类型(弓箭/奇械 4 档)内容 300+px ⇒ 藏进一个【框中框】的滚动条里 ——
	##     详情面板本身已经是 ScrollContainer, 套两层滚动玩家根本发现不了里面还有内容。
	rt.fit_content = true
	rt.scroll_active = false
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.add_theme_constant_override("line_separation", 5)
	rt.text = bb.strip_edges()
	host.detail.add_child(rt)

	# 成员装备清单 (从 p2eq-types.json 反查). 3 列流式网格, 接着上面的效果文案往下排(不再写死 y=446)。
	var list_y: float = 176.0 + maxf(24.0, rt.get_combined_minimum_size().y) + 26.0
	host._add_text(20, list_y, "该类型装备 (%d)" % members.size(), 17, "#58d3ff", 0.0, 0.0, true)
	var cols := 3
	var col_w: float = (host.DETAIL_W - 40.0) / float(cols)
	for i in range(members.size()):
		var m: Dictionary = members[i]
		var col: int = i % cols
		var row: int = int(i / cols)
		var mx: float = 24.0 + col * col_w
		var my: float = list_y + 30.0 + row * 26.0
		host._add_text(mx, my, "%s %s" % [str(m.get("emoji", "📦")), str(m.get("name", "?"))], 15, "#cdd6e0", 0.0, 0.0)


## 某类型的成员装备 [{id,name,emoji}], 反查 p2eq-types.json(经 host.Phase2Types.type_of)。
## 按 p2eq id 升序(= phase2_equipment 声明序), 与设计表一致。
func _type_members(tname: String) -> Array:
	var out: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var eid: String = str(eq.get("id", ""))
		## ★用 types_of 不是 type_of(2026-08-15)。type_of 只返回【第一个】类型,
		##   而 p2eq_093 香火石登记的是两个(遗物 + 香火, 用户 2026-08-13 拍板)
		##   ⇒ 香火那一页实拍是「该类型装备 (0)」, 一件都列不出来, 看着像功能没做完。
		if host.Phase2Types.types_of(eid).has(tname):
			out.append({"id": eid, "name": str(eq.get("name", eid)), "emoji": str(eq.get("emoji", "📦"))})
	return out



func _show_status(st: Dictionary) -> void:
	host._clear_detail()
	var icon_key: String = st.get("iconKey", "")
	host._add_image(70, 70, "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", ""), 100, 100, true)
	var cat_label = {"dot": "DoT 持续伤害", "cc": "CC 控制", "buff": "增益", "debuff": "减益"}
	host._add_text(140, 38, st.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(140, 78, cat_label.get(st.get("category", ""), st.get("category", "")), 15, "#58d3ff", 0.0, 0.5, true)
	host._add_text(20, 150, "说明", 17, "#58d3ff", 0.0, 0.0, true)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 176)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = str(st.get("desc", ""))
	host.detail.add_child(rt)
	var formula: String = st.get("formula", "")
	if formula != "":
		## ★"生效公式"接着说明往下排。原来写死 y=240/264 —— 说明只要长过 64px 就会被公式压住,
		##   而 13 个状态里最长的那条正文改成 17px 之后就正好跨过这条线。
		var fy: float = 176.0 + maxf(24.0, rt.get_combined_minimum_size().y) + 26.0
		host._add_text(20, fy, "生效公式", 17, "#58d3ff", 0.0, 0.0, true)
		host._add_text(20, fy + 28.0, formula, 17, "#ffd93d", 0.0, 0.0, true)


func _show_rule(r: Dictionary) -> void:
	host._clear_detail()
	var icon: String = r.get("icon", "")
	if icon != "":
		host._add_image(64, 78, "res://assets/sprites/%s" % icon, 92, 92, true)
	host._add_text(130, 40, r.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(130, 78, "战斗规则", 15, "#888888", 0.0, 0.5)
	host._add_text(20, 160, "效果", 17, "#58d3ff", 0.0, 0.0, true)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 188)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_constant_override("line_separation", 5)
	rt.add_theme_color_override("default_color", Color("#e8f2ff"))
	rt.text = str(r.get("desc", ""))
	host.detail.add_child(rt)

