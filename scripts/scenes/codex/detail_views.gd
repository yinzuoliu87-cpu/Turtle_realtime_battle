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
	var y = 214.0
	host._add_text(20, y, "技能 · %s  (%d 龟能)" % [str(mi["skill_name"]), int(mi["skill_cost"])], 15, "#58d3ff", 0.0, 0.0, true)
	y += 26.0
	y = _minion_body(str(mi["skill_desc"]), y) + 14.0
	for pv in mi.get("passives", []):
		host._add_text(20, y, "被动 · %s" % str(pv["name"]), 15, "#58d3ff", 0.0, 0.0, true)
		y += 26.0
		y = _minion_body(str(pv["desc"]), y) + 12.0

## 一段正文(自动换行), 返回下一段该起的 y.
func _minion_body(txt: String, y: float) -> float:
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, y)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = txt
	host.detail.add_child(rt)
	# fit_content 的真实高度要等一帧才有 → 按字数估行, 够用且不抖(每行约 62 个全角字)
	# ★2026-08-01 修「图鉴里精英小将的描述都挤在一块」(用户报):
	#   这里原本是 host.ceilf(...) —— ceilf 是【全局内建函数】, 不是节点上的方法,
	#   调用直接 SCRIPT ERROR("Nonexistent function 'ceilf' in base Node2D"),
	#   于是下面那句 return 【永远执行不到】→ 每一段正文都拿到同一个 y → 全叠在一起。
	#   来历: 2026-07-26 图鉴拆分那刀把函数搬进本文件时, 机械地给所有调用加了 host. 前缀。
	#   ★同类坑见 memory[[project-god-file-decomposition]] 十九坑 #15(float 内建 floorf)。
	var lines: float = ceilf(float(txt.length()) / 62.0)
	return y + maxf(20.0, lines * 19.0)


func _show_pet(pet: Dictionary) -> void:
	host._clear_detail()
	var rarity: String = pet.get("rarity", "C")
	var rarity_color: String = host.RARITY_COLOR.get(rarity, "#ffffff")
	var ctx = host._ctx_for(pet)
	var divider_y = 195.0

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

	# 9) 被动条框 y213 高50 0x12202a@0.55 + 被动icon 40×40@x50
	var passive: Dictionary = pet.get("passive", {})
	if not passive.is_empty():
		var passive_y = divider_y + 18.0
		# 选中态(被动展开): 边框亮黄 2px@1; 否则蓝 1px@0.5 (1:1 PoC CodexScene.ts:366-393)
		var pbar_stroke: String = "#ffd93d" if host._codex_passive_view else "#58d3ff"
		var pbar_sw: float = 2.0 if host._codex_passive_view else 1.0
		var pbar_sa: float = 1.0 if host._codex_passive_view else 0.5
		host._add_rect(host.DETAIL_W / 2.0, passive_y + 25, host.DETAIL_W - 40, 50, "#12202a", 0.55, pbar_stroke, pbar_sw, pbar_sa)
		var text_x = 30.0
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "":
			if pi_path.ends_with(".png"):
				host._add_image(50, passive_y + 25, "res://assets/sprites/%s" % pi_path, 40, 40)
				text_x = 80.0
			else:
				host._add_text(50, passive_y + 25, pi_path, 32, "#ffffff", 0.5, 0.5)
				text_x = 80.0
		host._add_text(text_x, passive_y + 25, "被动 · %s" % passive.get("name", ""), 20, "#58d3ff", 0.0, 0.5, true)
		# hint: 展开→"收起 ▾"金 / 否则"点击查看 ▸"灰 (1:1 PoC CodexScene.ts:385-388)
		var p_hint: String = "收起 ▾" if host._codex_passive_view else "点击查看 ▸"
		var p_hint_col: String = "#ffd93d" if host._codex_passive_view else "#888888"
		host._add_text(host.DETAIL_W - 30, passive_y + 25, p_hint, 13, p_hint_col, 1.0, 0.5)
		# drill-down: 点被动条 → 内联展开/收起完整 passive desc (1:1 PoC showPetDetail view='passive' toggle, 非弹窗)
		var p_hit = Control.new()
		p_hit.position = Vector2(20, passive_y)
		p_hit.size = Vector2(host.DETAIL_W - 40, 50)
		p_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		p_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref2: Dictionary = pet
		p_hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				host._codex_skill_detail = {}
				host._codex_passive_view = not host._codex_passive_view
				_show_pet(pet_ref2))
		host.detail.add_child(p_hit)

	# 10) 技能卡 — 5卡1行 168×260 gap8 @ skStartX20 skStartY282
	_render_skill_cards(pet, ctx)


# ─── 技能卡 (1:1 PoC renderSkillListSection) ───
## 技能卡的简述被切断时, 在卡片底部那条留白里画一行"点开看全部 ▸"。
##
## ★必须等一帧才问 `get_content_height()` —— 刚 add_child 时还没排版, 拿到 0 ⇒ 永远判"没被切",
##   提示永远不出现(这就是个不会红的假检查)。同 ShopScene._add_scroll_hint 那条。
func _mark_card_clipped(rt: RichTextLabel, cx: float, y: float, card_w: float) -> void:
	await host.get_tree().process_frame
	if not is_instance_valid(rt) or not is_instance_valid(host) or host.detail == null:
		return
	if rt.get_content_height() <= rt.size.y + 0.5:
		return
	var l := Label.new()
	l.text = "点开看全部 ▸"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#7fb5d8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(cx + 8, y)
	l.size = Vector2(card_w - 16, 16)
	host.detail.add_child(l)


func _render_skill_cards(pet: Dictionary, ctx: Dictionary) -> void:
	# 内联技能详情页 (1:1 PoC showPetDetail view={skillIdx} → renderSkillDetailSection): 顶部"← 返回列表" + 完整 host.detail
	if not host._codex_skill_detail.is_empty():
		_render_skill_detail_inline(pet, ctx, host._codex_skill_detail)
		return
	# 内联被动详情 (1:1 PoC showPetDetail view='passive' → renderPassiveDetailSection): 下方区显完整 desc
	if host._codex_passive_view and not (pet.get("passive", {}) as Dictionary).is_empty():
		_render_passive_detail_inline(pet, ctx)
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
	var card_w = 168.0; var card_h = 260.0; var gap = 8.0
	var start_x = 20.0; var start_y = 282.0
	var n: int = mini(skill_pool.size(), 5)
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
		host._add_rect(cx + card_w / 2.0, start_y + card_h / 2.0, card_w, card_h, bg_hex, bg_a, border, border_w, 1.0)
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
		rt.position = Vector2(cx + 8, start_y + 82)
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
	# E1 形态切换钮 (1:1 PoC CodexScene.ts:417-431) — 仅双形态龟显示, 切普通↔形态技能
	if has_form:
		var btn_w = 220.0
		var btn_h = 30.0
		var btn_x = host.DETAIL_W - 20.0 - btn_w / 2.0
		var btn_y = 262.0
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


## 内联技能详情 (1:1 PoC renderSkillDetailSection CodexScene.ts:532-568): 顶"← 返回列表"(蓝) + 标题行(图标+★+名32px+CD) + 完整 host.detail #fff 13px
func _render_skill_detail_inline(pet: Dictionary, ctx: Dictionary, sk: Dictionary) -> void:
	# 返回钮 center(70,296) 100×32, fill #1a2740@0.9 边 #58d3ff 1px@0.6; 文字 14px #58d3ff (PoC L539-549)
	host._add_rect(70, 296, 100, 32, "#1a2740", 0.9, "#58d3ff", 1, 0.6)
	host._add_text(70, 296, "← 返回列表", 14, "#58d3ff", 0.5, 0.5)
	var bhit = Control.new()
	bhit.position = Vector2(20, 280)
	bhit.size = Vector2(100, 32)
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
	title.position = Vector2(160, 283)
	title.custom_minimum_size = Vector2(host.DETAIL_W - 180, 48)
	title.add_theme_font_size_override("normal_font_size", 32)
	title.add_theme_color_override("default_color", Color("#ffffff"))
	title.text = bb
	host.detail.add_child(title)
	# 完整 host.detail (PoC L561-567): (20,340) width detailW-40 13px #fff lineHeight1.5, 限高352滚动
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = true
	rt.position = Vector2(20, 340)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 352)
	rt.size = Vector2(host.DETAIL_W - 40, 352)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = SkillText.render_bbcode(str(sk.get("detail", sk.get("brief", ""))), ctx, sk, 13)
	host.detail.add_child(rt)


## 内联被动详情 (1:1 PoC renderPassiveDetailSection CodexScene.ts:572-582): 完整 desc 占下方区 (20,290) 13px #fff 限高402滚动
func _render_passive_detail_inline(pet: Dictionary, ctx: Dictionary) -> void:
	var passive: Dictionary = pet.get("passive", {})
	if passive.is_empty():
		return
	var full_desc: String = str(passive.get("desc", passive.get("brief", "")))
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = true
	rt.position = Vector2(20, 290)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 402)
	rt.size = Vector2(host.DETAIL_W - 40, 402)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = SkillText.render_bbcode(full_desc, ctx, passive, 13)
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
	# 名 30px 黄 + 费用/稀有度副标
	host._add_text(130, 30, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	host._add_text(130, 66, "费用 %d" % cost, 14, ccol, 0.0, 0.5, true)
	# 类型行: 真类型(12种·p2eq-types.json)。旧 series/category 字段已废弃删除(用户2026-07-19)
	var _tp: String = host.Phase2Types.type_of(str(eq.get("id", "")))
	var type_str: String = ("%s %s" % [host.Phase2Types.emoji_of(_tp), host.Phase2Types.display_name(_tp)]) if _tp != "" else "—"
	host._add_text(130, 92, type_str, 13, "#888888", 0.0, 0.5)
	# ★2026-08-03 批1: 原来这里还有一行 y=116 的「学派: …」。学派系统已删(D1) ⇒ 整行删除。
	#   ⚠ 这块排版是【绝对 y 坐标】, 光删行会在 y=92(类型) 与 y=158("属性"标题)之间留 24px 空白,
	#   而【没有任何门禁抓得到】(verify_codex_browse 只走 Tab、不量间距 —— 方案书 R5)。
	#   ⇒ 下方各块统一上移 24px: 属性 158→134 / 值 184→160 / 后续块同理(见下)。

	# 属性 —— 取自 host.EquipStats.STATS(战斗实装的同一张表), 不再打印 data 里手写的 baseStats1。
	# baseStats1 只是 STATS 的人工镜像, 无机制保证一致; 走这里则图鉴与实装天然同源。
	host._add_text(20, 134, "属性", 14, "#58d3ff", 0.0, 0.0, true)
	var _eid: String = str(eq.get("id", ""))
	var _stat_str: String = host.EquipStats.stat_line_all_stars(_eid)
	## ★属性行也走三色分档 —— 与下面「效果」里的三档同一套配色, 否则同一屏两种读法。
	##   原来是纯 Label(单色 #ffd93d), `+5/+10/+20` 三档挤成一串。
	var srt := RichTextLabel.new()
	srt.bbcode_enabled = true; srt.fit_content = true; srt.scroll_active = false
	srt.position = Vector2(20, 154)
	srt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	srt.add_theme_font_size_override("normal_font_size", 17)
	srt.text = SkillTextRef.color_all_stars(_stat_str)
	host.detail.add_child(srt)

	# 效果 (effectDesc1 = 1星基础 / effectDesc3 = 3星升级)
	host._add_text(20, 200, "效果", 14, "#58d3ff", 0.0, 0.0, true)   # ★上移 24: 学派行删除(见上)
	var bb = str(eq.get("effectDesc1", ""))
	var d3: String = str(eq.get("effectDesc3", ""))
	if d3.strip_edges() != "":
		bb += "\n\n[color=%s][b]%s[/b][/color]" % [rcol, d3]
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 224)   # ★上移 24: 同上
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
	## ── 羁绊(类型阈值) ────────────────────────────────────────────────
	## ★图鉴原来【一个字都不提羁绊】, 而羁绊是这件装备最重要的搭配信息。
	##   商店详情里有(右上角小签), 图鉴反而没有 —— 同一份信息两个界面不一致。
	var _next_y := 224.0 + rt.get_combined_minimum_size().y + 20.0
	if has_tiers:
		var lg := RichTextLabel.new()
		lg.bbcode_enabled = true; lg.fit_content = true; lg.scroll_active = false
		lg.position = Vector2(20, _next_y)
		lg.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
		lg.add_theme_font_size_override("normal_font_size", 15)
		lg.text = "数值分档: " + SkillTextRef.star_legend_bbcode()
		host.detail.add_child(lg)
		_next_y += 30.0
	if _tp != "":
		var tiers: Array = (host.Phase2Types.TYPES.get(_tp, {}) as Dictionary).get("tiers", [])
		if not tiers.is_empty():
			var ty := _next_y + 12.0
			host._add_text(20, ty, "羁绊", 14, "#58d3ff", 0.0, 0.0, true)
			var ps: PackedStringArray = []
			for t in tiers:
				ps.append(str(int(t)))
			host._add_text(20, ty + 26.0, "%s %s —— 队伍装满 %s 件同类型即激活对应档位" % [
				host.Phase2Types.emoji_of(_tp), host.Phase2Types.display_name(_tp),
				"/".join(ps)], 17, "#9fb6c9", 0.0, 0.0, true)


# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
func _show_consumable(eq: Dictionary) -> void:
	host._clear_detail()
	var icon: String = str(eq.get("icon", ""))
	if icon.ends_with(".png"):
		host._add_image(90, 90, "res://assets/sprites/%s" % icon, 120, 120, true)
	host._add_text(180, 30, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	host._add_text(180, 68, "消耗品", 13, "#06d6a0", 0.0, 0.5, true)
	# 作用目标 (ally=友方 / enemy=敌方)
	var tgt: String = str(eq.get("target", ""))
	var tgt_label: String = str({"ally": "作用于友方", "enemy": "作用于敌方"}.get(tgt, ""))
	if tgt_label != "":
		host._add_text(240, 68, tgt_label, 13, "#888888", 0.0, 0.5)
	host._add_text(180, 110, "描述", 14, "#58d3ff", 0.0, 0.5, true)
	var desc = SkillText.render_bbcode(str(eq.get("desc", "")), {"atk": 0, "def": 0, "mr": 0, "maxHp": 0}, {}, 13)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(180, 132)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 200, 0)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
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
	var style: Dictionary = host.TYPE_STYLE.get(tname, {})
	var color: String = str(style.get("color", "#4cc9f0"))
	var emoji: String = str(style.get("emoji", "🔗"))
	var tiers: Array = def.get("tiers", [])
	var members: Array = _type_members(tname)   # [{id,name,emoji}], 该类型全部装备

	# 头图区: 无 tag PNG → 类型色框 + emoji 徽章
	host._add_rect(60, 70, 90, 90, "#12202a", 0.55, color, 2.0, 0.9)
	host._add_text(60, 70, emoji, 44, color, 0.5, 0.5, true)
	# 名 32px 类型色 + 副标(全称) + 档阈值 / 成员件数
	host._add_text(130, 36, tname, 32, color, 0.0, 0.5, true)
	host._add_text(130, 72, "羁绊 · %s" % host.Phase2Types.display_name(tname), 14, "#888888", 0.0, 0.5)
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	# ★顶档 == 该类型【最终】件数是有意设计(方案书 D5)。批 3 加完 35 件之前顶档够不到,
	#   这里如实显示"现有 N 件", 玩家自己看得出还差几件, 不写"不可达"这种开发者口吻的字。
	host._add_text(130, 98, "激活 %s 件   ·   现有装备 %d 件" % [thresh, members.size()], 14, color, 0.0, 0.5, true)

	# 逐档效果文案 (事实源 Phase2Types.TIER_DESCS, 与背包羁绊面板同一份)
	host._add_text(20, 150, "羁绊效果", 14, "#58d3ff", 0.0, 0.0, true)
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
	rt.fit_content = false   # 固定 260px 框 + 超长滚动, 不撑高(防压到下方成员清单 y446)
	rt.scroll_active = true
	rt.position = Vector2(20, 174)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 260)
	rt.size = Vector2(host.DETAIL_W - 40, 260)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.add_theme_constant_override("line_separation", 4)
	rt.text = bb.strip_edges()
	host.detail.add_child(rt)

	# 成员装备清单 (从 p2eq-types.json 反查). 3 列流式网格。
	var list_y := 446.0
	host._add_text(20, list_y, "该类型装备 (%d):" % members.size(), 14, "#58d3ff", 0.0, 0.0, true)
	var cols := 3
	var col_w: float = (host.DETAIL_W - 40.0) / float(cols)
	for i in range(members.size()):
		var m: Dictionary = members[i]
		var col: int = i % cols
		var row: int = int(i / cols)
		var mx: float = 24.0 + col * col_w
		var my: float = list_y + 28.0 + row * 24.0
		host._add_text(mx, my, "%s %s" % [str(m.get("emoji", "📦")), str(m.get("name", "?"))], 13, "#cdd6e0", 0.0, 0.0)


## 某类型的成员装备 [{id,name,emoji}], 反查 p2eq-types.json(经 host.Phase2Types.type_of)。
## 按 p2eq id 升序(= phase2_equipment 声明序), 与设计表一致。
func _type_members(tname: String) -> Array:
	var out: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var eid: String = str(eq.get("id", ""))
		if host.Phase2Types.type_of(eid) == tname:
			out.append({"id": eid, "name": str(eq.get("name", eid)), "emoji": str(eq.get("emoji", "📦"))})
	return out



func _show_status(st: Dictionary) -> void:
	host._clear_detail()
	var icon_key: String = st.get("iconKey", "")
	host._add_image(70, 70, "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", ""), 100, 100, true)
	var cat_label = {"dot": "DoT 持续伤害", "cc": "CC 控制", "buff": "增益", "debuff": "减益"}
	host._add_text(140, 38, st.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(140, 78, cat_label.get(st.get("category", ""), st.get("category", "")), 14, "#58d3ff", 0.0, 0.5, true)
	host._add_text(20, 150, "说明", 14, "#58d3ff", 0.0, 0.0, true)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 174)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = str(st.get("desc", ""))
	host.detail.add_child(rt)
	var formula: String = st.get("formula", "")
	if formula != "":
		# "生效公式" header @240 (PoC CodexScene.ts:813-816: 14px#58d3ff bold)
		host._add_text(20, 240, "生效公式", 14, "#58d3ff", 0.0, 0.0, true)
		host._add_text(20, 264, formula, 14, "#ffd93d", 0.0, 0.0, true)


func _show_rule(r: Dictionary) -> void:
	host._clear_detail()
	var icon: String = r.get("icon", "")
	if icon != "":
		host._add_image(64, 78, "res://assets/sprites/%s" % icon, 92, 92, true)
	host._add_text(130, 40, r.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	host._add_text(130, 78, "战斗规则", 14, "#888888", 0.0, 0.5)
	host._add_text(20, 160, "效果", 15, "#58d3ff", 0.0, 0.0, true)
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 186)
	rt.custom_minimum_size = Vector2(host.DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = str(r.get("desc", ""))
	host.detail.add_child(rt)

