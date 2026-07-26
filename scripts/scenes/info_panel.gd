class_name InfoPanel
extends RefCounted
## 点龟详情面板 + 左右队头像框栏(等级/属性/状态/技能/装备/宝箱)
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _make_team_column(side: String) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.name = "TeamPanel_" + side
	col.add_theme_constant_override("separation", 6)
	# 屏幕边缘竖直居中: 左栏贴左、右栏贴右 (用 anchor preset + 偏移)
	if side == "left":
		col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		col.position = Vector2(10, 0)
		col.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		col.position = Vector2(-10, 0)
		col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	for u in battle._units:
		if str(u.get("side", "")) != side:
			continue
		if u.get("is_summon", false):
			continue   # 召唤体不进框栏 (只主龟)
		var frame = battle._hud._make_team_frame(u)
		col.add_child(frame)
	# 居中: VBox 内容会从 anchor 点往下排; 让它真正竖直居中需把它整体上移半高 → 用 pivot 不便,
	#   改用一个外层 wrapper 也可, 但框少(1-3)时贴边竖直居中已够好 (CENTER_LEFT/RIGHT anchor=屏幕中线).
	return col

# 单个头像框: 头像 + 名 + 等级牌 + 迷你血条; 整框可点 → 弹详情面板.
# ----------------------------------------------------------------------------
#  2) 每帧刷头像框 (HP 条宽 / 死亡变暗 / 选中高亮)
# ----------------------------------------------------------------------------
func _update_team_panels() -> void:
	for u in battle._units:
		var fr = u.get("panel_frame", null)
		if fr == null or not is_instance_valid(fr):
			continue
		var plb = u.get("panel_lv_badge", null)   # 面板等级框也随036临时等级跳
		if plb != null and is_instance_valid(plb) and plb.get_child_count() > 0:
			(plb.get_child(0) as Label).text = str(battle._effective_level(u))
		var fill = u.get("panel_hp_fill", null)
		if fill != null and is_instance_valid(fill):
			var maxhp: float = maxf(1.0, float(u.get("maxHp", 1.0)))
			var ratio: float = clampf(float(u.get("hp", 0.0)) / maxhp, 0.0, 1.0)
			fill.size.x = battle._PANEL_HP_W * ratio
			# 血色随比例 (绿→黄→红)
			if ratio > 0.5:
				fill.color = Color("#4ade80")
			elif ratio > 0.25:
				fill.color = Color("#ffce4d")
			else:
				fill.color = Color("#ff5a5a")
		var alive: bool = bool(u.get("alive", true))
		fr.modulate = Color(1, 1, 1, 1) if alive else Color(0.45, 0.45, 0.5, 0.75)
		# 选中高亮: 边框加粗 + 提亮 (改 stylebox border)
		var sb = u.get("panel_stylebox", null)
		if sb != null and sb is StyleBoxFlat:
			var selected: bool = (battle._selected_unit != null and is_same(u, battle._selected_unit))
			(sb as StyleBoxFlat).set_border_width_all(3 if selected else 2)
			var base_accent = Color("#3fa9ff") if str(u.get("side", "")) == "left" else Color("#ff5a5a")
			(sb as StyleBoxFlat).border_color = (Color("#ffd93d") if selected else base_accent)
		for cb in u.get("panel_charge_bars", []):   # 装备格充能进度条
			var cf = cb.get("fill", null)
			if cf == null or not is_instance_valid(cf): continue
			var cstt = u.get("eq_state", {}).get(str(cb["iid"]), {})
			var cfrac: float = clampf(float(cstt.get(str(cb["key"]), 0.0)) / float(cb["cap"]), 0.0, 1.0)
			cf.size = Vector2(44.0 * cfrac, 4)
		for cl in u.get("panel_count_labels", []):   # 装备格右下角层数徽章
			var clb = cl.get("lbl", null)
			if clb == null or not is_instance_valid(clb): continue
			var lstt = u.get("eq_state", {}).get(str(cl["iid"]), {})
			clb.text = str(int(lstt.get(str(cl["key"]), 0)))
	# ★详情面板的动态部件也在这刷 —— 这里已经是每帧调用、且 battle._selected_unit 可用,
	#   不必另开 Timer(用户 2026-07-21:「面板里所有的数值需要实时变化」)。
	_refresh_info_panel()

# ----------------------------------------------------------------------------
#  3) 详情面板 (居中, detail_panel_frame 斜面边框) — 等级/属性/被动/技能/装备
# ----------------------------------------------------------------------------
## 详情面板动态部件每帧刷新(HP条/龟能条/属性行)。挂在 _update_team_panels 尾部。
## ★只改已存在节点的 text/value, 不重建 —— 重建会打断 ScrollContainer 滚动位置且每帧分配节点。
## ★属性行数会变(某属性从 0 变非 0 时会多出一行), 行数一变就整块重建面板, 否则引用会错位。
func _refresh_info_panel() -> void:
	if battle._info_panel == null or not is_instance_valid(battle._info_panel):
		return
	var u = battle._selected_unit
	if u == null or not (u is Dictionary):
		return
	var ud: Dictionary = u
	# HP 条
	if battle._info_hp_bar != null and is_instance_valid(battle._info_hp_bar):
		var mx: float = maxf(1.0, float(ud.get("maxHp", 1.0)))
		battle._info_hp_bar.max_value = mx
		battle._info_hp_bar.value = clampf(float(ud.get("hp", 0.0)), 0.0, mx)
	if battle._info_hp_lbl != null and is_instance_valid(battle._info_hp_lbl):
		battle._info_hp_lbl.text = "HP  %d / %d" % [int(ud.get("hp", 0)), int(ud.get("maxHp", 0))]
	# 龟能条
	if battle._info_en_bar != null and is_instance_valid(battle._info_en_bar):
		var acts: Array = ud.get("active_skills", [])   # 与建面板处同源(L22405), 不要另造函数
		if not acts.is_empty():
			var st0 = str(acts[0])
			var mxcd = battle._skill_cd(ud, st0)
			var cd = float((ud.get("skill_cd", {}) as Dictionary).get(st0, mxcd))
			var rdy = CombatMath.cooldown_ready(cd, mxcd)
			battle._info_en_bar.value = rdy
			if battle._info_en_lbl != null and is_instance_valid(battle._info_en_lbl):
				battle._info_en_lbl.text = "龟能  %d%%" % int(rdy * 100.0)
	# 属性行
	var rows: Array = _info_stat_rows(ud)
	if rows.size() != battle._info_stat_labels.size():
		# 行数变了(有属性从0变非0) → 引用会错位, 整块重建
		battle._hud._show_unit_info_panel(ud)
		return
	for i in range(rows.size()):
		var lb = battle._info_stat_labels[i]
		if lb == null or not is_instance_valid(lb):
			continue
		var txt = str((rows[i] as Array)[1])
		if lb.text != txt:
			lb.text = txt
	# ★技能/被动描述里的伤害数值也要跟着属性变(用户 2026-07-21:「下面的技能伤害数值」)。
	#   模板里的 {N:0.7*ATK} 按【当前】ATK 重算 —— 吃了增伤/破防 buff 后数字会跟着动。
	if battle._info_passive_lbl != null and is_instance_valid(battle._info_passive_lbl) and battle._info_passive_tpl != "":
		var pv: Dictionary = ud.get("passive", {}) if ud.get("passive", null) is Dictionary else {}
		var ptxt = battle._render._render_skill_text(battle._info_passive_tpl, ud, pv)
		if battle._info_passive_lbl.text != ptxt:
			battle._info_passive_lbl.text = ptxt
	for ent in battle._info_skill_lbls:
		var slb = (ent as Dictionary).get("lbl", null)
		if slb == null or not is_instance_valid(slb):
			continue
		var stpl = str((ent as Dictionary).get("tpl", ""))
		if stpl == "":
			continue
		var sdict = (ent as Dictionary).get("sk", {})
		var stxt = battle._render._render_skill_text(stpl, ud, sdict if sdict is Dictionary else {})
		if slb.text != stxt:
			slb.text = stxt
	# ★状态 chips: 签名变了才整块重建(条目数会变, 改不了单个 Label)
	if battle._info_status_box != null and is_instance_valid(battle._info_status_box):
		var sig = battle._status_signature(ud)
		if sig != battle._info_status_sig:
			battle._info_status_sig = sig
			for ch in battle._info_status_box.get_children():
				ch.queue_free()
			_info_status_chips(battle._info_status_box, ud)
	# ★装备区: 星级/件数变了才重建(财神招财临时升星、宝箱龟开出新装备)
	if battle._info_equip_box != null and is_instance_valid(battle._info_equip_box):
		var esig = battle._equip_signature(ud)
		if esig != battle._info_equip_sig:
			battle._info_equip_sig = esig
			for ch in battle._info_equip_box.get_children():
				ch.queue_free()
			battle._fill_equip_section(battle._info_equip_box, ud)


# 面板内非按钮控件设 IGNORE → 触摸透传到 ScrollContainer(手机可竖滑·2026-07-18); 关闭按钮(Button)保留可点
func _info_passthrough(node: Node) -> void:
	for c in node.get_children():
		if c is Button:
			continue
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_info_passthrough(c)

# 面板内一条进度条(HP/龟能): 深底+彩色填充+居中文字覆盖
# 面板内一条进度条(HP/龟能): 深底+彩色填充+居中文字覆盖
func _info_bar(parent: Control, cur: float, mx: float, fill_col: Color, label: String) -> Array:
	var holder = Control.new()
	holder.custom_minimum_size = Vector2(0, 22)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var pb = ProgressBar.new()
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.min_value = 0.0; pb.max_value = maxf(1.0, mx); pb.value = clampf(cur, 0.0, mx)
	pb.show_percentage = false
	var bgsb = StyleBoxFlat.new(); bgsb.bg_color = Color("#0b1220"); bgsb.set_corner_radius_all(5)
	bgsb.set_border_width_all(1); bgsb.border_color = Color("#243247")
	var flsb = StyleBoxFlat.new(); flsb.bg_color = fill_col; flsb.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bgsb)
	pb.add_theme_stylebox_override("fill", flsb)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pb)
	var lb = Label.new(); lb.text = label; lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 12); lb.add_theme_color_override("font_color", Color("#ffffff"))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lb)
	return [pb, lb]   # ★返回 [进度条, 文本] 供每帧刷新(见 _refresh_info_panel)

# 属性格 (图标+值), 放进 GridContainer; icon_tex 非空→用真图标(Phaser stats/*·2026-07-18), 否则留空占位
## ── 详情面板的动态部件引用(每帧刷新用; 面板重建时全部重置) ──
## ★用户 2026-07-21:「面板里所有的数值需要实时变化, 比如血条, 移速攻速, 下面的技能伤害数值」。
##   原实现是【一次性快照, 从不刷新】(源码里作者自己写了这句), 于是开着面板时
##   掉血/加buff/减速 全看不出来。现在把动态部件的节点引用存下来, 每帧改它们的文本/值,
##   而不是整块重建(重建会打断滚动位置 + 每帧分配节点)。
func _info_stat_rows(u: Dictionary) -> Array:
	var sic = "res://assets/sprites/stats/"   # 统一到唯一一套属性图标(32px·用户2026-07-24: 战斗内也用这套, 删了旧的 ui/stats/ 64px 异画风)
	var W = Color("#d6e4f0")
	var rows: Array = [
		[sic + "atk-icon.png",      "攻击 %d" % int(u.get("atk", 0)),                                Color("#ff9d8a")],
		[sic + "def-icon.png",      "护甲 %d" % int(u.get("def", 0)),                                W],
		[sic + "mr-icon.png",       "魔抗 %d" % int(u.get("mr", 0)),                                 Color("#9bdcff")],
		[sic + "crit-icon.png",     "暴击 %d%%" % int(float(u.get("crit", 0.0)) * 100.0),            W],
		[sic + "aspd-icon.png",     "攻速 %ss" % battle._fmt_num(float(u.get("atk_interval", 0.0))),        W],
		[sic + "range-icon.png",    "射程 %d" % int(u.get("atk_range", 0)),                          W],
		[sic + "move-icon.png",     "移速 %d" % int(u.get("move_spd", 0)),                           W],
	]
	# ── 用户 2026-07-21 要求补的「更多属性」 ──
	# ★★全部【恒显示】(用户第二轮明确:「全都要显示啊」)。原来做成"有值才显示",
	#   结果没装备的龟根本看不到治疗强度/护盾强度/闪避这几行。
	# ★★口径修正: 治疗强度/护盾强度是【乘算】的 —— 实装是 amt *= (1 + heal_amp),
	#   所以【基准是 100%】而不是 0。原来显示成 "+0%" 属于口径错误(用户指出:「不是100%吗」)。
	#   同理 暴伤基准 150%(crit_dmg 默认 1.5)、龟能充能基准 100%。
	#   而闪避/吸血/穿透/反伤/韧性/减伤/增伤 是【加算】的, 基准就是 0。
	var ls: float = float(u.get("lifesteal", 0.0)) + float(u.get("ls_bonus", 0.0))
	rows.append([sic + "lifesteal-icon.png", "吸血 %d%%" % int(round(ls * 100.0)), Color("#ff8fb0")])
	rows.append(["", "闪避 %d%%" % int(round(float(u.get("dodge_bonus", 0.0)) * 100.0)), Color("#a0e8ff")])
	# 乘算类: 显示最终倍率(100% = 没有加成)
	rows.append(["", "治疗强度 %d%%" % int(round((1.0 + float(u.get("heal_amp", 0.0))) * 100.0)), Color("#7fe39a")])
	rows.append(["", "护盾强度 %d%%" % int(round((1.0 + float(u.get("shield_amp", 0.0))) * 100.0)), Color("#ffd93d")])
	rows.append(["", "暴伤 %d%%" % int(round(float(u.get("crit_dmg", 1.5)) * 100.0)), Color("#ffb37a")])
	rows.append(["", "龟能充能 %d%%" % int(round((1.0 + float(u.get("echarge_perm", 0.0))) * 100.0)), Color("#ffce4d")])
	# 加算类: 基准 0
	rows.append(["", "护甲穿透 %d" % int(u.get("armor_pen", 0.0)), Color("#ffc48a")])
	rows.append(["", "魔法穿透 %d" % int(u.get("magic_pen", 0.0)), Color("#c9a0ff")])
	rows.append(["", "反伤 %d%%" % int(round(float(u.get("reflect", 0.0)) * 100.0)), Color("#ff9d8a")])
	rows.append(["", "韧性 %d%%" % int(round(float(u.get("tenacity", 0.0)) * 100.0)), Color("#d6e4f0")])
	rows.append(["", "减伤 %d%%" % int(round(float(u.get("damage_reduction", 0.0)) * 100.0)), Color("#9bdcff")])
	rows.append(["", "增伤 %d%%" % int(round(float(u.get("damage_amp", 0.0)) * 100.0)), Color("#ff7a7a")])
	return rows


func _info_stat_cell(grid: GridContainer, icon: String, val: String, col: Color = Color("#d6e4f0"), icon_tex: String = "") -> Label:
	var h = HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	if icon_tex != "" and ResourceLoader.exists(icon_tex):
		var it = TextureRect.new(); it.texture = load(icon_tex)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		it.custom_minimum_size = Vector2(26, 26); it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(it)
	else:
		var ic = Label.new(); ic.text = icon; ic.add_theme_font_size_override("font_size", 16)
		ic.custom_minimum_size = Vector2(26, 0); ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(ic)
	var c = Label.new(); c.text = val; c.add_theme_font_size_override("font_size", 14)
	c.add_theme_color_override("font_color", col); c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	grid.add_child(h)
	return c   # ★返回文本 Label, 供每帧刷新时改 text(见 _refresh_info_panel)

# 当前生效的状态 → chips (只显生效的); 无则"无异常状态"
# 当前生效的状态 → chips (只显生效的); 无则"无异常状态"
func _info_status_chips(vb: VBoxContainer, u: Dictionary) -> void:
	var chips: Array = []
	if battle._t < float(u.get("stun_until", 0.0)): chips.append(["😵 眩晕", "#ff8a3d"])
	# ★2026-07-22 修: 原先读 burn_until —— 那是【零处写入的死字段】(全项目只有初始化和这里读),
	#   所以「🔥 灼烧」chip 从来没出现过, 哪怕身上叠了 200 层。真实层数在 dot_stacks。
	#   顺带补上中毒/流血 —— 它们连 chip 都没有过。
	var _ds: Dictionary = u.get("dot_stacks", {})
	var _bn: int = int(_ds.get("burn", 0))
	var _po: int = int(_ds.get("poison", 0))
	var _bl: int = int(_ds.get("bleed", 0))
	if _bn > 0: chips.append(["🔥 灼烧 %d" % _bn, "#ff6b3d"])
	if _po > 0: chips.append(["🧪 中毒 %d" % _po, "#7ee87e"])
	if _bl > 0: chips.append(["🩸 流血 %d" % _bl, "#ff6b6b"])
	if battle._t < float(u.get("true_fire_until", 0.0)): chips.append(["🔥 真火", "#ffffff"])
	if battle._t < float(u.get("slow_until", 0.0)): chips.append(["🐌 减速", "#7fd0ff"])
	if battle._t < float(u.get("taunt_until", 0.0)): chips.append(["😡 嘲讽", "#ff5c8a"])
	if battle._t < float(u.get("untargetable_until", 0.0)): chips.append(["🌀 隐身/不可选", "#b28bff"])
	if battle._t < float(u.get("heal_reduce_until", 0.0)): chips.append(["💔 治疗削减", "#ff6b6b"])
	if battle._t < float(u.get("energy_lock_until", 0.0)): chips.append(["🔒 龟能锁", "#ffcf5a"])
	if float(u.get("shield", 0.0)) > 0.0: chips.append(["🛡 护盾 %d" % int(u.get("shield", 0.0)), "#7fe0ff"])
	if float(u.get("rage", 0.0)) > 0.0: chips.append(["😤 怒气 %d" % int(u.get("rage", 0.0)), "#ff9d5c"])
	if float(u.get("star_energy", 0.0)) > 0.0: chips.append(["⭐ 星能 %d" % int(u.get("star_energy", 0.0)), "#b28bff"])
	if float(u.get("store_energy", 0.0)) > 0.0: chips.append(["🟡 储能 %d" % int(u.get("store_energy", 0.0)), "#ffd93d"])
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6); flow.add_theme_constant_override("v_separation", 4)
	vb.add_child(flow)
	if chips.is_empty():
		var e = Label.new(); e.text = "无异常状态"
		e.add_theme_font_size_override("font_size", 13); e.add_theme_color_override("font_color", Color("#7a8694"))
		flow.add_child(e)
		return
	for ch in chips:
		var p = PanelContainer.new()
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(str(ch[1])); sb.bg_color.a = 0.20
		sb.border_color = Color(str(ch[1])); sb.set_border_width_all(1); sb.set_corner_radius_all(6)
		sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 2; sb.content_margin_bottom = 2
		p.add_theme_stylebox_override("panel", sb)
		var l = Label.new(); l.text = str(ch[0]); l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(str(ch[1])))
		p.add_child(l); flow.add_child(p)

func _info_chest_section(vb: VBoxContainer, u: Dictionary) -> void:
	# 财宝值随时在变(开箱随时发生), 冻在开面板那一刻的数字没意义, 所以本块自挂 0.5s 定时重建。
	# 注: 2026-07-21 起面板的 HP条/龟能条/属性行已改为每帧刷新(见 _refresh_info_panel),
	#     本块因为要【整块重建】(条目数会变)才单独用定时器, 不并进那条每帧路径。
	var sec = VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(sec)
	battle._fill_chest_section(sec, u)
	var t = Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停时也刷(面板本来就能在暂停下看)
	t.timeout.connect(func() -> void:
		if is_instance_valid(sec):
			battle._fill_chest_section(sec, u))
	sec.add_child(t)

func _panel_skill_entries(u: Dictionary) -> Array:
	var id = str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	var pool: Array = pet.get("skillPool", [])
	var out: Array = []
	# ★小将走独立文案表(pets.json 里没有 __minion__)
	if pool.is_empty():
		for t in u.get("active_skills", []):
			var md = battle.MINION_SKILL_DESC.get(str(t), null)
			if md != null:
				out.append({"name": str(md["name"]), "desc": str(md["desc"])})
		if not out.is_empty():
			return out
	var chosen: Array = battle._chosen_skill_types(id, str(u.get("side", "")) == "left")
	# 已选主动技 (按 type 在 pool 里找名/描述)
	for t in chosen:
		for sk in pool:
			if sk is Dictionary and str(sk.get("type", "")) == str(t):
				var _stpl = battle.SkillText.text_of(sk, battle._skill_detail())
				out.append({"name": str(sk.get("name", t)),
							"desc": battle._render._render_skill_text(_stpl, u, sk),
							"tpl": _stpl, "sk": sk})
				break
	# 普攻 (skillPool[0] 一般是 physical/magic) — 补一条让面板不空
	if not pool.is_empty() and pool[0] is Dictionary:
		var s0: Dictionary = pool[0]
		var t0 = str(s0.get("type", ""))
		if t0 == "physical" or t0 == "magic":
			var _btpl = battle.SkillText.text_of(s0, battle._skill_detail())
			out.append({"name": str(s0.get("name", "普攻")) + " (普攻)",
						"desc": battle._render._render_skill_text(_btpl, u, s0),
						"tpl": _btpl, "sk": s0})
	return out

## 当前是否看详细。存 GameState → 跨场景记住(用户拍板"面板级开关, 选择记住")。
