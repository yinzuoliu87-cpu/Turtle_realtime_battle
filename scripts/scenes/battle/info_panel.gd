class_name InfoPanel
extends RefCounted
## 点龟详情面板 + 左右队头像框栏(等级/属性/状态/技能/装备/宝箱)
## 类内名不变;外部名加 battle.

var battle

## 装备区那几行【局内读数】的 Label 引用(每帧刷 —— 充能/层数一直在动)。
var _info_eq_readouts: Array = []
## 上一次接管过的装备容器实例 id。面板每次打开都会新建容器 ⇒ id 变了就说明是新面板,
## 要用本文件的 `_info_equip_section` 重铺一次(见 _refresh_info_panel 里的说明)。
var _info_eq_box_iid: int = 0

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
	## ★羁绊 chips 挂成这一列的【第一个子节点】(2026-08-12): 天然跟着列的锚点走
	##   (左栏贴左 / 右栏贴右 / 竖直居中), 一个坐标都不用写死。
	##   数据是战斗算好的 `_synergy._by_side[side]`, 建列时它已经有值(apply_all 在建列之前跑)。
	col.add_child(battle._hud.make_synergy_chip_row(side))
	for u in battle._units:
		# ★按【有效阵营】分栏 —— 被驯服归顺我方的龟要出现在【我方】头像栏里。
		#   改前用原 side, 于是归顺的龟逻辑上已经是我方(不打我方/打原队/算我方存活/血条我方色),
		#   头像框却还挂在敌方栏 —— 玩家看到的"阵营"是矛盾的。
		#   ★这一栏是 spawn 时建一次、整局不重建的, 所以还要在归顺那一刻主动重建
		#   (见 trainer_system._tame_try_revive 末尾的 _build_team_panels)。
		if battle._eff_side(u) != side:
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
			# ★★用【有效阵营】—— 这一行是【每帧】跑的, 会把 _make_team_frame 建框时设对的
			#   颜色又刷回原阵营色。实拍抓到: 归顺的石头龟框已经挪进我方栏, 边框却还是敌方红,
			#   左栏里就它一个红框。
			#   ★这是同一形状的第三次(前两次: _dl_side_alive 手写阵营判断、_make_team_column 按原 side)
			#     —— "同一个语义在两处各写各的", 而【每帧重刷的那一处】总是赢。
			var base_accent = Color("#3fa9ff") if battle._eff_side(u) == "left" else Color("#ff5a5a")
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
		battle._info_hp_lbl.text = "生命  %d / %d" % [int(ud.get("hp", 0)), int(ud.get("maxHp", 0))]
	## 资源条(龟能 + 专属) —— 每帧按下标对位改数, 不重建节点。
	## ★条目数会变(储能从 0 变非 0、宝箱开完第 5 箱就没有下一箱了) ⇒ 数量对不上就整块重建,
	##   否则引用错位会把"星能"的数写进"怒气"那条(属性行那边踩过同一个坑, 见下面几行)。
	var _rr: Array = battle._hud._info_res_rows
	var _rb: Array = _resource_bars(ud)
	if _rr.size() != _rb.size():
		battle._hud._show_unit_info_panel(ud)
		return
	for _i in range(_rb.size()):
		var _row: Dictionary = _rr[_i]
		var _d: Dictionary = _rb[_i]
		var _bar = _row.get("bar")
		if _bar != null and is_instance_valid(_bar):
			_bar.max_value = maxf(1.0, float(_d.get("cap", 1.0)))
			_bar.value = clampf(float(_d.get("cur", 0.0)), 0.0, _bar.max_value)
		var _vl = _row.get("val")
		if _vl != null and is_instance_valid(_vl):
			_vl.text = _res_value_text(_d)
		var _hl = _row.get("hint")
		if _hl != null and is_instance_valid(_hl):
			_hl.text = str(_d.get("hint", ""))
	# 属性行
	## ★只比【常驻的主要 8 项】—— 次要 11 项 2026-08-16 搬进了点开的浮层, 不在常驻 Label 里。
	##   拿 19 去比 8 会永远判"行数变了"⇒ 每帧整块重建 ⇒ 面板每帧从屏外重新滑入, 永远到不了位。
	##   实测症状: 面板 x 从 1252 越飘越远到 1304(每次重建都 offset += PW+40 再滑)。
	##   ⚠ 这个 bug 【门禁一条都没红】—— 因为门禁是直接调 _show_unit_info_panel 再同步断言,
	##     不跑"连续多帧刷新"那条路。是截图看不到面板才发现的。
	var rows: Array = _info_stat_rows_main(ud)
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
		## ★头一行是【龟能花费 + 还差几秒】, 每帧重算 —— 与 _panel_skill_entries 建条目时同一个函数,
		##   两处同源(建面板那一刻的文字与刷新后的文字不会是两套)。
		var stxt = _skill_status_line(ud, sdict) + battle._render._render_skill_text(stpl, ud, sdict if sdict is Dictionary else {})
		if slb.text != stxt:
			slb.text = stxt
	# ★状态 chips: 签名变了才整块重建(条目数会变, 改不了单个 Label)
	if battle._info_status_box != null and is_instance_valid(battle._info_status_box):
		var sig = _status_sig_own(ud)
		if sig != battle._info_status_sig:
			battle._info_status_sig = sig
			## ★★必须 remove_child 之后再 queue_free —— queue_free 是【延迟到帧末】的,
			##   光 queue_free 的话旧 chips 这一帧还挂在树上, 于是新旧两组同时渲染
			##   (实测: 熔岩变身后"常态"和"火山形态"两个 chip 一起在, 而且旧的排在前面)。
			##   这和 battle_hud 重建头像栏时踩过的是同一个坑。
			for ch in battle._info_status_box.get_children():
				battle._info_status_box.remove_child(ch)
				ch.queue_free()
			_info_status_chips(battle._info_status_box, ud)
	# ★装备区: 星级/件数变了才重建(财神招财临时升星、宝箱龟开出新装备)
	## ★★2026-08-16: 首建与刷新【走同一个函数】(_info_equip_slots)。
	##   之前是两条路各建各的 —— 首建走 battle._fill_equip_section(只有名字+星级),
	##   刷新走本文件的 _info_equip_section(带充能), 于是开面板后一帧样式会跳一下。
	##   我这轮把首建改成新的三槽后, 刷新那条【还在调旧的】, 直接把新槽覆盖回旧列表 ——
	##   截图当场抓到。⇒ 两条路收成一个函数, 不留第二份。
	if battle._info_equip_box != null and is_instance_valid(battle._info_equip_box):
		var esig = battle._equip_signature(ud)
		var fresh: bool = battle._info_equip_box.get_instance_id() != _info_eq_box_iid
		if fresh or esig != battle._info_equip_sig:
			_info_eq_box_iid = battle._info_equip_box.get_instance_id()
			battle._info_equip_sig = esig
			for ch in battle._info_equip_box.get_children():
				battle._info_equip_box.remove_child(ch)
				ch.queue_free()
			_info_equip_slots(battle._info_equip_box, ud)
		else:
			## 充能/层数每帧都在动 —— 只改文字, 不重建节点。
			for ent2 in _info_eq_readouts:
				var elb = (ent2 as Dictionary).get("lbl", null)
				if elb == null or not is_instance_valid(elb):
					continue
				var etx := _equip_readout_text(ud, str((ent2 as Dictionary).get("eid", "")))
				if elb.text != etx:
					elb.text = etx


# 面板内非按钮控件设 IGNORE → 触摸透传到 ScrollContainer(手机可竖滑·2026-07-18); 关闭按钮(Button)保留可点
#
# ★★2026-08-16 修一个【把交互全部打死】的 bug:
#   这个函数原来"除了 Button 一律 IGNORE"。而 2026-08-16 面板重做之后, 可点的东西
#   【一个 Button 都没有】—— 技能三槽 / 装备三槽 / 更多属性 / 战利品 全是
#   `PanelContainer + gui_input`(为了长得像槽而不是网页按钮)。
#   ⇒ 它们建好时设的 MOUSE_FILTER_STOP 在这里被【无差别抹成 IGNORE】,
#     用户点名要的「这些图标点击出现描述」「装备也是点击出现描述框」是死的:
#     点上去什么都不会发生, 而代码里 _show_detail 写得好好的。
#   ★探针数字: 面板里 266 个 PanelContainer, 可点的(filter=STOP)只有【最外层面板 1 个】。
#   ★这正是 memory fb-verify-must-run-the-real-path 那一条 —— 门禁断言过
#     "_show_detail 存在""点开会显示描述", 但【没有一条走真实点击分派】,
#     所以死路被门禁保护着。
#   ⇒ 判据改成:【自己接了 gui_input 的控件不动它】, 其余照旧透传。
func _info_passthrough(node: Node) -> void:
	for c in node.get_children():
		if c is Button:
			continue
		if c is Control and not (c as Control).gui_input.get_connections().is_empty():
			_info_passthrough(c)   # 它自己要吃点击, 但它的孩子还是要透传
			continue
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_info_passthrough(c)

## 第二行【资源区】—— 把 `_resource_bars()` 那张表画成一排条(2026-08-16)。
##
## 每条两层:
##   上层 = [名] ……… [当前/上限]   ← 名左对齐、数右对齐, 数值成列好比
##   下层 = 一条 8px 的细条 + 右边一句结论("攒满变火山" / "2.3秒后结算: 回血47·伤害47")
## ★结论那句是【条自己带的】, 不套统一模板 —— 泡泡是定时结算型, 永远不会"满了触发",
##   套"满了会…"就是在承诺一件不会发生的事(见 _resource_bars 的注释)。
## ★纯代码画: 深底 + 1px 边 + 填充。不做贴图 —— 条长随面板宽变, 九宫格反而僵,
##   而且用户 2026-08-16 明确"不要复用、不需要海底装饰"。
##
## 返回 [{bar, val_lbl, hint_lbl, name}] 供每帧刷新按下标对位改数, 不重建节点。
## 资源条那一行印什么字 —— 【建的时候和每帧刷新的时候都调这一个】。
##
## ★由来 2026-08-16(实拍抓到): 建条时写的是"无上限就只印数字", 刷新时写的是死的 `%d / %d`
##   ⇒ 面板一开是对的「37」, 下一帧就被刷成「37 / 0」。金币【本来就没有上限】,
##   硬编一个分母 0 出来是骗人(memory fb-hand-rolled-copies-drift: 手抄的副本必然落后)。
##   ⚠ 这是我第二次在同一个面板上踩"建一套/刷一套" —— 装备槽那次也是实拍才发现。
##   ⇒ 这次不是把两边改成一样, 是让两边【只剩一个出处】, 想漂也没得漂。
func _res_value_text(r: Dictionary) -> String:
	var cap: float = float(r.get("cap", 0.0))
	if cap <= 0.0:
		return "%d" % int(r.get("cur", 0.0))
	return "%d / %d" % [int(r.get("cur", 0.0)), int(cap)]


## 条的【填充】统一做出液面分层: 主体压暗一档 + 顶部 3px 亮带 = 光打在液面上。
##
## ★为什么抽成函数: v0.19.203 我只给 `_info_bar`(生命/龟能)做了, **漏了资源条**
##   —— 于是同一块面板里, 上面两条有液面、下面泡泡条是纯色平填。
##   写第二遍就会漏第三处, 所以做成唯一出处(memory: 手抄的副本必然落后)。
## ⚠ `StyleBoxFlat` 只有一个 border_color, 做不了"上亮下暗"两色 ⇒ 只做上亮;
##   下方的暗由条框自己那道下沿给。
## ★亮暗从 `col` **算**出来不写死 —— 血条绿/龟能黄/怒气橙/星能紫/储能黄/泡泡蓝
##   六种颜色走同一条路径, 写死等于给其中一种调好、其余全错。
func _bar_fill_skin(sb: StyleBoxFlat, col: Color) -> void:
	sb.bg_color = col.darkened(0.16)
	sb.border_width_top = 3
	sb.border_color = col.lightened(0.22)


func _info_resource_row(parent: Control, r: Dictionary) -> Dictionary:
	## ★inline 形态: 条上压一行数字, 没有名字标签也没有结论行 —— 与血条同构。
	if bool(r.get("inline", false)):
		var hold = Control.new()
		hold.custom_minimum_size = Vector2(0, 22)
		hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(hold)
		## ★框单独一层 NinePatchRect, 进度条【内缩 6px】画在框里面。
		##   第 2 轮实拍: 直接把框当 ProgressBar 的 background, 矩形填充会从胶囊框两端顶出来。
		##   框归框、填充归填充, 才不会打架。
		var ifr := _bar_frame(hold)
		var ipb = ProgressBar.new()
		ipb.set_anchors_preset(Control.PRESET_FULL_RECT)
		ipb.offset_left = 6.0; ipb.offset_right = -6.0
		ipb.offset_top = 5.0; ipb.offset_bottom = -5.0
		ipb.min_value = 0.0; ipb.max_value = maxf(1.0, float(r.get("cap", 1.0)))
		ipb.value = clampf(float(r.get("cur", 0.0)), 0.0, ipb.max_value)
		ipb.show_percentage = false
		var ibg = StyleBoxFlat.new(); ibg.bg_color = Color("#0b1220")
		ibg.set_border_width_all(1); ibg.border_color = Color("#243247"); ibg.set_corner_radius_all(0)
		var ifl = StyleBoxFlat.new(); ifl.bg_color = r.get("color", Color.WHITE); ifl.set_corner_radius_all(0)
		_bar_fill_skin(ifl, r.get("color", Color.WHITE))
		ibg.bg_color = Color(0, 0, 0, 0.55) if ifr != null else ibg.bg_color
		ibg.set_border_width_all(0 if ifr != null else 1)
		ipb.add_theme_stylebox_override("background", ibg)
		ipb.add_theme_stylebox_override("fill", ifl)
		ipb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hold.add_child(ipb)
		var ivl = Label.new()
		ivl.text = _res_value_text(r)
		ivl.set_anchors_preset(Control.PRESET_FULL_RECT)
		ivl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ivl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ivl.add_theme_font_size_override("font_size", UIPalette.F_SUB)
		ivl.add_theme_color_override("font_color", Color("#ffffff"))
		ivl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hold.add_child(ivl)
		return {"bar": ipb, "val": ivl, "hint": null, "name": str(r.get("name", ""))}

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var nm = Label.new(); nm.text = str(r.get("name", ""))
	## ★12 不是 13: 同一条资源行里的【名】与【值】要和龟能条内那份(12)同号 ——
	##   实测面板里「30 / 100」是 13、隔 20 像素的「63 / 115」是 12, 同一类信息两个号。
	nm.add_theme_font_size_override("font_size", UIPalette.F_SUB)
	nm.add_theme_color_override("font_color", r.get("color", Color.WHITE))
	top.add_child(nm)
	var sp = Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var no_cap: bool = float(r.get("cap", 0.0)) <= 0.0   # 没有上限的资源(金币)只显数字, 不画条
	var vl = Label.new()
	vl.text = _res_value_text(r)
	vl.add_theme_font_size_override("font_size", UIPalette.F_SUB)
	vl.add_theme_color_override("font_color", Color("#e8f2ff"))
	top.add_child(vl)

	var bhold = Control.new()
	## ⚠★14 → 20(2026-08-17): 这一行**调了 `_bar_frame`, 但框根本渲染不出来** ——
	##   条框九宫格上下边距 7+7 = 14, 正好等于这里的高度 ⇒ 中段一行不剩, 框被压没。
	##   实拍泡泡龟才看见: 生命/龟能有金属框, 而专属资源条是**裸的色块压黑底**,
	##   正是用户「血条龟能条都跟网页一样」那条抱怨, 只是发生在一行我一直没看见的地方
	##   (它一直没被渲染: 门禁/探针/截图工装三处都喂错了字段名, 这一行从没建出来过)。
	##   ★同一个坑今晚第二次: **九宫格源图的边距之和必须小于目标高度**(头像框那次是 32→56)。
	bhold.custom_minimum_size = Vector2(0, 0 if no_cap else 16)
	bhold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bhold.visible = not no_cap
	box.add_child(bhold)
	var bfr := _bar_frame(bhold)
	var pb = ProgressBar.new()
	pb.visible = not no_cap
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.offset_left = 5.0; pb.offset_right = -5.0
	pb.offset_top = 4.0; pb.offset_bottom = -4.0
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.min_value = 0.0; pb.max_value = maxf(1.0, float(r.get("cap", 1.0)))
	pb.value = clampf(float(r.get("cur", 0.0)), 0.0, pb.max_value)
	pb.show_percentage = false
	var bgsb = StyleBoxFlat.new(); bgsb.bg_color = Color("#0b1220")
	bgsb.set_border_width_all(1); bgsb.border_color = Color("#243247"); bgsb.set_corner_radius_all(0)
	var flsb = StyleBoxFlat.new(); flsb.bg_color = r.get("color", Color.WHITE); flsb.set_corner_radius_all(0)
	_bar_fill_skin(flsb, r.get("color", Color.WHITE))
	bgsb.bg_color = Color(0, 0, 0, 0.55) if bfr != null else bgsb.bg_color
	bgsb.set_border_width_all(0 if bfr != null else 1)
	pb.add_theme_stylebox_override("background", bgsb)
	pb.add_theme_stylebox_override("fill", flsb)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bhold.add_child(pb)

	## hint 为空就不建 —— 建一个空 Label 会白占约 14px, 面板里最缺的就是高度。
	if str(r.get("hint", "")) == "":
		return {"bar": pb, "val": vl, "hint": null, "name": str(r.get("name", ""))}
	var hl = Label.new(); hl.text = str(r.get("hint", ""))
	hl.add_theme_font_size_override("font_size", UIPalette.F_SUB)
	hl.add_theme_color_override("font_color", Color("#8fa2b5"))
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	## ★★不许 clip_text —— 它会把 Label 的【最小宽度压成 1px】, 而这一行里有一个
	##   EXPAND_FILL 的弹簧, 于是结论那句被挤成 1px 宽:【字还在, 但一个像素都看不见】。
	##   实拍量到 `Label [1006,179 1x17] 攒满变火山形态` 才发现 —— 我以为我"把它并进了名字行",
	##   实际是把它挤没了(memory fb-write-without-reader-and-fake-gates: 写了没人读/看不见)。
	hl.clip_text = false
	hl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	## ★★结论那句【跟在名字后面】, 不再独占一行(2026-08-16)。
	##   原来一条资源占三行: 名+值 / 条 / 结论。结论行 17px × 每条资源, 而面板最缺的就是高度
	##   (宝箱龟 657px 塞 628px 的视口)。并进第一行之后一条资源省 17px, 读起来也少一次换行。
	##   ★不是删掉它 —— 「攒满变火山形态」这类是玩家推不出来的机制, 必须留(2026-08-16 的判断没变)。
	top.add_child(hl)
	top.move_child(hl, 1)
	return {"bar": pb, "val": vl, "hint": hl, "name": str(r.get("name", ""))}


# 面板内一条进度条(HP/龟能): 深底+彩色填充+居中文字覆盖
func _info_bar(parent: Control, cur: float, mx: float, fill_col: Color, label: String) -> Array:
	var holder = Control.new()
	holder.custom_minimum_size = Vector2(0, 22)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var hfr := _bar_frame(holder)
	var pb = ProgressBar.new()
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.offset_left = 6.0; pb.offset_right = -6.0
	pb.offset_top = 5.0; pb.offset_bottom = -5.0
	pb.min_value = 0.0; pb.max_value = maxf(1.0, mx); pb.value = clampf(cur, 0.0, mx)
	pb.show_percentage = false
	var bgsb = StyleBoxFlat.new(); bgsb.bg_color = Color("#0b1220"); bgsb.set_corner_radius_all(0)   # 直角(同上)
	bgsb.set_border_width_all(1); bgsb.border_color = Color("#243247")
	var flsb = StyleBoxFlat.new(); flsb.bg_color = fill_col; flsb.set_corner_radius_all(0)
	## ★★2026-08-17 给【填充本身】做出液面分层。
	##   由来: 框换成真凹槽之后再看, 剩下的网页味就在瓤上 —— 填充是**一整块纯色**,
	##   和 `<div style="background:#4caf50">` 一模一样。框对了、瓤没对, 整条还是像进度条。
	##   做法: 主体压暗一档 + 顶部 3px 亮带 = 光打在液面上的样子。
	##   ⚠ `StyleBoxFlat` **只有一个 border_color**, 做不了"上亮下暗"两色 ——
	##     所以只做上亮; 下方的暗是条框自己那道下沿给的(它本来就画在填充下面)。
	##   ★颜色从 `fill_col` 算出来, 不写死: 血条绿/龟能黄/各种资源色都走这一条路径,
	##     写死就等于给其中一种调好、其余全错。
	_bar_fill_skin(flsb, fill_col)
	## ★血条底也走九宫格像素框(用户:「血条，龟能条都跟网页一样」)。
	bgsb.bg_color = Color(0, 0, 0, 0.55) if hfr != null else bgsb.bg_color
	bgsb.set_border_width_all(0 if hfr != null else 1)
	pb.add_theme_stylebox_override("background", bgsb)
	pb.add_theme_stylebox_override("fill", flsb)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pb)
	var lb = Label.new(); lb.text = label; lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", UIPalette.F_SUB); lb.add_theme_color_override("font_color", Color("#ffffff"))
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lb)
	return [pb, lb]   # ★返回 [进度条, 文本] 供每帧刷新(见 _refresh_info_panel)

# 属性格 (图标+值), 放进 GridContainer; icon_tex 非空→用真图标(Phaser stats/*·2026-07-18), 否则留空占位
## ── 详情面板的动态部件引用(每帧刷新用; 面板重建时全部重置) ──
## ★用户 2026-07-21:「面板里所有的数值需要实时变化, 比如血条, 移速攻速, 下面的技能伤害数值」。
##   原实现是【一次性快照, 从不刷新】(源码里作者自己写了这句), 于是开着面板时
##   掉血/加buff/减速 全看不出来。现在把动态部件的节点引用存下来, 每帧改它们的文本/值,
##   而不是整块重建(重建会打断滚动位置 + 每帧分配节点)。
## 属性【主要 8 项】—— 输出 / 暴击 / 生存 / 机动 四对, 每行一对同族。
##
## ★为什么是这 8 项(用户 2026-08-16 定): 玩家心智里的"主要属性"就是输出·生存·机动,
##   不是我一开始按"战斗中会不会变"划的那套(那把增伤/减伤划进了主要, 用户当场否掉)。
## ★印证: assets/sprites/stats/ 里正好有这 8 张图标(atk/aspd/crit/crit-dmg/def/mr/move/range),
##   其中 crit-dmg 一直躺着没接线 —— 美术当初配的就是这一套核心属性。
func _info_stat_rows_main(u: Dictionary) -> Array:
	var sic := "res://assets/sprites/stats/"
	var W := Color("#d6e4f0")
	## ★石头龟叠出来的护甲标在护甲这一行后面 —— 它是【累计增量】不是"攒满触发"型资源。
	var def_now: int = int(u.get("def", 0))
	var def_gain: int = int(round(float(u.get("def", 0.0)) - float(u.get("stone_init_def", u.get("def", 0.0)))))
	var def_txt: String = "护甲 %d" % def_now
	if def_gain > 0:
		def_txt += " (+%d)" % def_gain
	## ★增伤/减伤非 0 时标色 —— 不为 0 就说明此刻正被强化或削弱, 得能一眼扫到。
	var amp: float = float(u.get("damage_amp", 0.0))
	var dr: float = float(u.get("damage_reduction", 0.0))
	return [
		[sic + "atk-icon.png",   "攻击 %d" % int(u.get("atk", 0)),                 Color("#ff9d8a")],
		[sic + "aspd-icon.png",  "攻速 %s 次/秒" % battle._fmt_num(battle.aspd_mult(u) / maxf(0.001, float(u.get("atk_interval", 1.0)))), W],
		[sic + "crit-icon.png",  "暴击 " + _pct(minf(float(u.get("crit", 0.0)), 1.0)), W],
		[sic + "dmg-amp-icon.png", "增伤 " + _pct(amp), Color("#ff7a7a") if amp > 0.0005 else Color("#7a8694")],
		[sic + "def-icon.png",   def_txt,                                          W],
		[sic + "mr-icon.png",    "魔抗 %d" % int(u.get("mr", 0)),                  Color("#9bdcff")],
		[sic + "dmg-red-icon.png", "减伤 " + _pct(dr),  Color("#9bdcff") if dr > 0.0005 else Color("#7a8694")],
		[sic + "range-icon.png", "射程 %d" % int(round(battle._eff_range(u))),     W],
	]

## 属性【次要 11 项】—— 基本是装备/羁绊给的固定值, 开局定了就不动。小字排。
## ★一项都不删(用户 2026-07-21「全都要显示啊」) —— 变的只是字号和分组, 不是可见性。
## ★增伤/减伤非 0 时标色: 不为 0 就说明此刻正被强化或削弱, 得能一眼扫到。
func _info_stat_rows_minor(u: Dictionary) -> Array:
	var sic := "res://assets/sprites/stats/"
	var ls: float = float(u.get("lifesteal", 0.0)) + float(u.get("ls_bonus", 0.0))
	## ★暴伤 = 基础暴伤 + 暴击率溢出 100% 的部分 ×1.5(与 DamageMath.crit_multiplier 同一公式)。
	var crit_over: float = maxf(0.0, float(u.get("crit", 0.0)) - 1.0) * 1.5
	return [
		[sic + "crit-dmg-icon.png", "暴伤 " + _pct_mult(float(u.get("crit_dmg", 1.5)) + crit_over), Color("#ffb37a")],
		[sic + "move-icon.png",     "移速 %d" % int(round(_eff_move_spd(u))),      Color("#d6e4f0")],
		[sic + "lifesteal-icon.png", "吸血 " + _pct(ls),                           Color("#ff8fb0")],
		["", "闪避 " + _pct(float(u.get("dodge_bonus", 0.0))),                     Color("#a0e8ff")],
		["", "治疗强度 " + _pct_mult(1.0 + float(u.get("heal_amp", 0.0))),         Color("#7fe39a")],
		["", "护盾强度 " + _pct_mult(1.0 + float(u.get("shield_amp", 0.0))),       Color("#ffd93d")],
		["", "龟能充能 " + _pct_mult(1.0 + float(u.get("echarge_perm", 0.0))),     Color("#ffce4d")],
		["", "护甲穿透 %d" % int(u.get("armor_pen", 0.0)),                         Color("#ffc48a")],
		["", "魔法穿透 %d" % int(u.get("magic_pen", 0.0)),                         Color("#c9a0ff")],
		["", "反伤 " + _pct(float(u.get("reflect", 0.0))),                         Color("#ff9d8a")],
		["", "韧性 " + _pct(float(u.get("tenacity", 0.0))),                        Color("#d6e4f0")],
	]

## 全部属性行 = 主要 + 次要, 【顺序必须与建面板时创建 Label 的顺序一致】——
## 每帧刷新是按 `_info_stat_labels` 的下标一一对位改文字的, 顺序错位就会张冠李戴。
func _info_stat_rows(u: Dictionary) -> Array:
	var out: Array = _info_stat_rows_main(u)
	out.append_array(_info_stat_rows_minor(u))
	return out


func _eff_move_spd(u: Dictionary) -> float:
	var spd: float = float(u.get("move_spd", 0.0)) * float(u.get("move_perm", 1.0))
	if battle._t < float(u.get("slow_until", 0.0)):
		spd *= float(u.get("slow_mag", 0.6))
	if battle._t < float(u.get("spd_dbf_until", 0.0)):
		spd *= float(u.get("spd_move_mult", 1.0))
	if battle._t < float(u.get("move_buff_until", 0.0)):
		spd *= float(u.get("move_buff_mult", 1.0))
	return spd


## 百分比显示 —— 小数值保留一位。
## ★★用户 2026-08-14 实测:「增伤减伤显示那里不是 0 吗」。
##   这四行原来一律 `%d` + `int(round())` ⇒ **不足 0.5% 的一律显示 0%**。
##   香火石每道刻痕只给携带者 0.3% / 队友 0.1%(减伤更小, 0.15% / 0.05%),
##   ⇒ 攒到 5 道刻痕之前面板全是 0, 玩家以为没生效。
##   **加成是真的在吃的**(`battle_damage._atk_dmg` 里 `base *= 1 + damage_amp`),
##   坏的只是这一行显示。这正是"数值对了但玩家看不见" —— 与没生效在体感上没区别。
## ★为什么不无脑一位小数: 大数值(决胜增伤 60%)写成 "60.0%" 反而啰嗦。
##   分界放在 10%: 小于它保留一位, 大于等于它取整。
func _pct(v: float) -> String:
	var p: float = v * 100.0
	if absf(p) < 10.0 and absf(p) > 0.0:
		return "%.1f%%" % p
	return "%d%%" % int(round(p))


## 乘算类百分比(治疗强度/护盾强度/暴伤/龟能充能)——【基准是 100%】而不是 0。
## ★★不能直接套 `_pct`: 它按【显示出来的数】判要不要留小数, 于是 1.004 → 100.4 → ≥10 → 取整 →
##   "100%", 加成又被抹没了。乘算类要看的是【离基准差多少】, 所以分界落在 (v−1)。
##   (这正是用户 2026-08-14 骂的那个 bug 的第三种长相: 前两次是加算类的 `%d`。)
func _pct_mult(v: float) -> String:
	var d: float = absf(v - 1.0) * 100.0
	if d < 10.0 and d > 0.0:
		return "%.1f%%" % (v * 100.0)
	return "%d%%" % int(round(v * 100.0))


# ============================================================================
#  龟能 / 形态 / 装备读数 —— 2026-08-15「战斗内看不到数值」那一轮补的
# ============================================================================
## ★由来(用户原话):「这些信息我在战斗内完全看不到」「数值什么一点都看不到」。
##   逐个查过熔岩/星际/宝箱之后, 实拍确认的缺口是【三样都有内部数、局内一个都不露】:
##     · 龟能: 条上只写 "龟能 46%", 而技能文案里写的是「(80 龟能)」「(120 龟能)」
##       ⇒ 同一件事两个口径, 46% 和 80 对不上, 玩家没法判断"还差多少能放".
##     · 形态: 实拍熔岩龟【射程 70 / 移速 120】= 已经在火山形态了, 面板零提示;
##       更坑的是火山形态下 `rage` 被复用成倒计时(`rage = 100 × 剩余/总时长`),
##       chip 却仍旧写着「怒气 36」—— 那个 36 的真实含义是"火山还剩 5.4 秒".
##     · 装备充能: 详情面板的装备区只有名字+星级, 充能/层数只在头像下的小格子里,
##       而那里只有一根 4px 的条和一个小数字。


## 某技能的龟能读数 → [当前点数, 满点数, 还差几秒, 就绪比例 0~1]。
## ★点数口径与战斗完全同源: `battle._skill_cost` 是花费、`battle._skill_cd` 是"充满要几秒"
##   (= 花费 × 0.075), 冷却剩余秒按同一个比例折回点数。不另立公式。
## ══════════════════════════════════════════════════════════════════════
##  资源条 —— 单一事实源 (2026-08-16)
##
##  ★为什么要收成一处: 这些资源现在【同一个东西两套画法】——
##    ①头顶血条上有一套资源条(battle_render.gd:461 那几行镜像字段 _auraEnergy/_lavaRage/
##      _starEnergy/bubbleStore) ②信息面板里另有一套文字 chip。
##    而面板那套还漏了分母: 金币/财宝/储能只印当前值, "财宝 470" 玩家不知道 470 算多还是少。
##
##  ★两类资源不能用同一句模板(踩过的坑):
##    · 阈值型(怒气/星能/储能/财宝) —— "攒满会怎样"
##    · 定时结算型(泡泡) —— 它【永远不会"满了触发"】, 每 5 秒按当前量结算一次。
##      套"满了会…"就是在承诺一件永远不会发生的事。
##
##  返回 [{name, cur, cap, hint, color}]；龟能永远第一条, 专属条有才出现。
##  上限一律取【代码事实】, 不手抄:
##    储能 maxHp×50%(battle_damage:290) · 泡泡 maxHp(battle_damage:242)
##    星能 maxHp×40%(star_system 判定线) · 怒气 battle.RAGE_MAX · 财宝 _CHEST_THRESH[已开数]
func _resource_bars(u: Dictionary) -> Array:
	var out: Array = []
	var mhp: float = maxf(1.0, float(u.get("maxHp", 1.0)))

	# ① 龟能 —— 恒在(有主动技就有), 永远第一条
	var acts: Array = u.get("active_skills", [])
	if not battle._is_passive_pick(u) and acts.size() > 0:
		var es: Array = _energy_state(u, str(acts[0]))
		## ★龟能这条【不带结论文字】(用户 2026-08-16:「龟能那里不需要文字不需要几秒后释放」)。
		##   条本身 + `当前/上限` 已经说完了; 再加一句"6.0 秒后可放"是同一件事说第三遍。
		##   ⚠ 专属资源(怒气/星能/储能/泡泡/财宝)仍然要那句 —— 它们的"满了会怎样"是
		##     玩家推不出来的机制(变身/放强化版/冲击波+护盾), 不是把条再念一遍。
		out.append({
			"name": "龟能", "cur": float(es[0]), "cap": float(es[1]),
			"hint": "", "color": Color("#ffce4d"),
			## ★inline: 数字【压在条里】, 不要名字标签、不要结论那行(用户 2026-08-16)。
			##   和血条同一种长相 —— 血条本来就是"条上压一行 HP 861/1005"。
			##   龟能是最常看的一条, 长得和血条一样才不用二次识别。
			"inline": true,
		})

	# ② 怒气(熔岩) —— 阈值型。★火山形态下 rage 被 _sim_step 复用成倒计时百分比,
	#    那时挂"怒气"是骗人 —— 形态那一行已经说了还剩几秒, 这里让路。
	if float(u.get("rage", 0.0)) > 0.0 and not bool(u.get("volcano", false)):
		out.append({
			"name": "怒气", "cur": float(u.get("rage", 0.0)), "cap": float(battle.RAGE_MAX),
			"hint": "攒满变火山形态", "color": Color("#ff9d5c"),
		})

	# ③ 星能(星际) —— 阈值型
	if float(u.get("star_energy", 0.0)) > 0.0:
		out.append({
			"name": "星能", "cur": float(u.get("star_energy", 0.0)), "cap": maxf(1.0, mhp * STAR_FULL_PCT),
			"hint": "攒满放强化版", "color": Color("#b28bff"),
		})

	# ④ 储能(龟壳) —— 阈值型。释放时清零: 冲击波(储能×40% 物理) + 储能×80% 护盾(5秒流失)
	if float(u.get("store_energy", 0.0)) > 0.0:
		var se: float = float(u.get("store_energy", 0.0))
		out.append({
			"name": "储能", "cur": se, "cap": mhp * 0.50,
			"hint": "释放: 冲击波 %d + 护盾 %d" % [int(se * 0.40), int(se * 0.80)],
			"color": Color("#ffd93d"),
		})

	# ⑤ 泡泡储量 —— ★定时结算型, 不是阈值型。每 5 秒: 回血 10%×储量 + 对最近敌 10%×储量 魔法
	if float(u.get("bubble_store", 0.0)) > 0.0:
		var bs: float = float(u.get("bubble_store", 0.0))
		var nxt: float = maxf(0.0, 5.0 - float(u.get("_bbtimer", 0.0)))
		out.append({
			"name": "泡泡", "cur": bs, "cap": mhp,
			"hint": "%.1f 秒后结算: 回血 %d · 伤害 %d" % [nxt, int(bs * 0.10), int(bs * 0.10)],
			"color": Color("#aef1ff"),
		})

	# ⑥ 金币(财富) —— ★没有上限, 所以 cap = 0 表示【只显数字、不画条】。
	#    硬给它编一个分母就是骗人; 但它必须看得见 —— 用户 2026-08-14「这个金币哪里有显示吗」,
	#    查证当时 info_panel / battle_hud / hp_bar 一处都没显示, 而财富龟普攻带 "gold": 0.02
	#    (每点金币 +2% 攻击加成)、fortuneAllIn 还要判金币数 ⇒ 看不到就没法决策何时梭哈。
	if float(u.get("gold", 0.0)) > 0.0:
		out.append({
			"name": "金币", "cur": float(u.get("gold", 0.0)), "cap": 0.0,
			"hint": "每点 +2% 攻击", "color": Color("#ffd24d"),
		})

	# ⑦ 财宝(宝箱) —— 阈值型。分母 = 下一箱阈值; 开满 5 件就没有下一箱了
	if str(u.get("id", "")) == "chest" and float(u.get("dmg_dealt", 0.0)) > 0.0:
		var opened: int = int(u.get("chest_opened", 0))
		var th: Array = battle._CHEST_THRESH
		if opened < th.size():
			out.append({
				"name": "财宝", "cur": float(u.get("dmg_dealt", 0.0)), "cap": float(th[opened]),
				"hint": "再攒开第 %d 箱" % (opened + 1), "color": Color("#ffcf6b"),
			})
	return out


func _energy_state(u: Dictionary, stype: String) -> Array:
	var cost: float = battle._skill_cost(u, stype)
	var full: float = battle._skill_cd(u, stype)
	var left: float = float((u.get("skill_cd", {}) as Dictionary).get(stype, full))
	var rdy: float = CombatMath.cooldown_ready(left, full)
	return [rdy * cost, cost, maxf(0.0, left), rdy]


## 技能 type → 玩家看得懂的名字(pets.json 技能池; 小将走 MINION_SKILL_DESC 兜底)。
func _skill_name_of(u: Dictionary, stype: String) -> String:
	var pet: Dictionary = DataRegistry.pet_by_id.get(str(u.get("id", "")), {})
	for sk in pet.get("skillPool", []):
		if sk is Dictionary and str((sk as Dictionary).get("type", "")) == stype:
			return str((sk as Dictionary).get("name", stype))
	var md = battle.MINION_SKILL_DESC.get(stype, null)
	if md != null:
		return str((md as Dictionary).get("name", stype))
	return stype


## 龟能条上那行字。★重点是把【点数】露出来 —— 技能文案里写的就是点数。
func _energy_bar_text(u: Dictionary) -> String:
	var acts: Array = u.get("active_skills", [])
	if acts.is_empty():
		return "龟能  这只龟没有主动技"
	var st0 := str(acts[0])
	var es: Array = _energy_state(u, st0)
	var head := "龟能  %d / %d" % [int(es[0]), int(es[1])]
	if battle._t < float(u.get("energy_lock_until", 0.0)):
		return head + "  ·  龟能被锁住 %.1f 秒" % (float(u.get("energy_lock_until", 0.0)) - battle._t)
	if float(es[2]) <= 0.001:
		return head + "  ·  攒满了, 可以放「%s」" % _skill_name_of(u, st0)
	return head + "  ·  还差 %.1f 秒" % float(es[2])


## 技能条目最上面那一行状态字(每帧重算, 见 _refresh_info_panel)。
## ★只给【真的进主动轮转的技】(u.active_skills 里有的)加 —— 被动型技与普攻没有龟能花费,
##   给它们编一个"龟能 0"是假信息。判据取自单位字典里的真实字段, 不是我自己插的标记。
func _skill_status_line(u: Dictionary, sk) -> String:
	if not (sk is Dictionary):
		return ""
	var stype := str((sk as Dictionary).get("type", ""))
	if stype == "":
		return ""
	var acts: Array = u.get("active_skills", [])
	var hit := false
	for a in acts:
		if str(a) == stype:
			hit = true
			break
	if not hit:
		return ""
	var es: Array = _energy_state(u, stype)
	var head := "龟能 %d / %d" % [int(es[0]), int(es[1])]
	if battle._t < float(u.get("energy_lock_until", 0.0)):
		return head + "  ·  龟能被锁住 %.1f 秒\n" % (float(u.get("energy_lock_until", 0.0)) - battle._t)
	if float(es[2]) <= 0.001:
		return head + "  ·  攒满了, 随时能放\n"
	return head + "  ·  还差 %.1f 秒\n" % float(es[2])


## 当前形态 chip → ["文字", "#色"]; 没有形态的龟返回空数组。
## ★只列【真的有两套形态数值】的三只 —— 判据是单位字典里那个驱动战斗的字段本身
##   (lava 的 volcano / two_head 的 two_form / shell 的 shell_stealth), 不是我另存一个标记。
func _form_chip(u: Dictionary) -> Array:
	match str(u.get("id", "")):
		"lava":
			if bool(u.get("volcano", false)):
				var left: float = maxf(0.0, float(u.get("volcano_until", 0.0)) - battle._t)
				return ["火山形态 · 还剩 %.1f 秒" % left, "#ff7a3d"]
			## ★这里【不再写"攒满怒气变火山"】(2026-08-17 实拍): 怒气条自己带着这句
			##   「攒满变火山形态」, 而怒气条【恰好只在非火山形态时出现】—— 也就是说
			##   这个 chip 和那句提示【永远同屏】, 同一件事在一屏上说了两遍。
			##   chip 的职责是"我现在是什么形态", 条的职责是"攒满会怎样", 各说各的。
			return ["熔岩形态", "#9bb0c4"]
		"two_head":
			return ["近战形态 · 锤击", "#ffb37a"] if str(u.get("two_form", "ranged")) == "melee" else ["远程形态 · 灵能弹", "#b28bff"]
		"shell":
			if bool(u.get("shell_stealth", false)):
				return ["潜伏中 · 不会被选为目标", "#8be0c0"]
	return []


## 星能的上限 —— 星际龟满星能(最大生命 40%)才放强化版, 只显数字看不出离满还有多远。
## ★40% 这个系数取自 star_system 里那两处 `star_energy >= u["maxHp"] * 0.40` 判定,
##   verify_info_panel_live 会回读源码对账, 那边改了这里不跟就红。
const STAR_FULL_PCT := 0.40


## 一件装备的局内读数(充能 / 层数)。★数据源就是装备图标格用的那两张表
##   (`EquipReadouts.CHARGE` / `.COUNT`) —— 不新开一张表, 也不在别处自造读数条。
## 第五行【装备三槽】—— 72×72 图标横排, 星级角标压右上, 局内读数压图标下沿(2026-08-16)。
##
## ★点整槽 → 在槽下面撑开【有边框的描述框】(与技能栏同一套手风琴, 一次只开一个, 内联不弹层)。
## ★读数走 EquipReadouts.CHARGE / COUNT 那两张表 —— 与装备图标框同一个数据源,
##   不自造条、不放头顶(用户 2026-08-08 的铁律)。
## ★空槽画灰框: 一眼看出"还能装几件", 而不是让人数图标。
## ★槽做 72 是为了触摸: 这个项目实测 44pt = 81 视口像素, 72 仍不达标 ——
##   显式登记为缺口(低频操作, 误触代价只是开错一条描述)。
func _info_equip_slots(vb: VBoxContainer, u: Dictionary) -> void:
	## ★读数 Label 必须登记进 _info_eq_readouts —— 每帧刷新是按这张表【只改文字不重建】的。
	##   不登记的话充能/层数永远停在开面板那一刻(签名只认 id+星级, 充能变了签名不变 ⇒ 不重建)。
	##   这正是"写进去了没人读"的反面: 建了节点却没接上消费者。
	_info_eq_readouts.clear()
	var equips: Array = u.get("equips", [])
	var cap: int = maxi(3, equips.size())
	var wrap = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	vb.add_child(wrap)
	## ★一行小标签「装备：」(用户 2026-08-16:「装备区也没有文字提示？…你写装备：行吗」)。
	##   ⚠ 是【小灰标签】不是金色段标题 —— 段标题正是被删掉的那个网页式 h3。
	var eqt = Label.new(); eqt.text = "装备："
	eqt.add_theme_font_size_override("font_size", UIPalette.F_SUB)
	eqt.add_theme_color_override("font_color", Color("#7f92a5"))
	wrap.add_child(eqt)
	var rowc = HBoxContainer.new()
	rowc.add_theme_constant_override("separation", 8)
	wrap.add_child(rowc)
	for i in range(cap):
		var it = equips[i] if i < equips.size() else null
		var slot = PanelContainer.new()
		var ssb = StyleBoxFlat.new()
		var filled: bool = it is Dictionary
		ssb.bg_color = Color("#121b28") if filled else Color("#0d141d")
		ssb.set_border_width_all(1)
		ssb.border_color = Color("#3a4c60") if filled else Color("#222c38")
		ssb.set_corner_radius_all(0)
		## ⚠★2026-08-17 实拍抓到: 上面 `ssb` 里写的【空/满两种底色+边色】**是死代码** ——
		##   `_nine_box` 只在**贴图不存在时**才回退到 `ssb`, 而 `slot-frame.png` 一直在,
		##   所以那两行 `if filled` 永远没生效。头上注释写着「空槽画灰框, 一眼看出还能装几件」,
		##   实拍出来**空槽和满槽一模一样**。典型的"写进去了没人读", 而且注释还在替它背书。
		##   ⇒ 让它真生效: 九宫格贴图挂上之后, 空槽把整块压暗一档(modulate)。
		var _slot_sb := _nine_box(HUD_TEX + "slot-frame.png", 12, ssb)
		if not filled and _slot_sb is StyleBoxTexture:
			(_slot_sb as StyleBoxTexture).modulate_color = Color(0.55, 0.60, 0.70, 1.0)
		slot.add_theme_stylebox_override("panel", _slot_sb)
		## ★与技能槽同一口径: 正方 88×88, 面板宽度跟着槽走。
		slot.custom_minimum_size = Vector2(88, 88)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if filled else Control.MOUSE_FILTER_IGNORE
		if filled:
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rowc.add_child(slot)
		if not filled:
			continue
		var eid := str((it as Dictionary).get("id", ""))
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		var inner = Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(inner)
		var img := str(edef.get("img", ""))
		var ipath := "res://assets/sprites/%s" % img if img.ends_with(".png") else ""
		if ipath != "" and ResourceLoader.exists(ipath):
			var ir = TextureRect.new()
			ir.texture = load(ipath)
			ir.set_anchors_preset(Control.PRESET_FULL_RECT)
			ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ir.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(ir)
		# 星级角标(右上)
		var st = Label.new()
		st.text = "★".repeat(maxi(1, int((it as Dictionary).get("star", 1))))
		st.add_theme_font_size_override("font_size", UIPalette.F_MICRO)
		st.add_theme_color_override("font_color", Color("#ffd93d"))
		st.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		st.offset_left = -34.0; st.offset_top = 1.0; st.offset_right = -2.0; st.offset_bottom = 13.0
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(st)
		# 局内读数(压图标下沿) —— 与装备图标框同一个数据源
		var ro := _equip_readout_text(u, eid)
		if ro != "":
			var rl = Label.new(); rl.text = ro
			rl.add_theme_font_size_override("font_size", UIPalette.F_MICRO)
			rl.add_theme_color_override("font_color", Color("#ffe9a8"))
			rl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			rl.offset_top = -13.0; rl.offset_bottom = -1.0
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rl.clip_text = true
			rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(rl)
			_info_eq_readouts.append({"lbl": rl, "eid": eid})
		var d_title := "%s %s" % [str(edef.get("name", eid)),
			"★".repeat(maxi(1, int((it as Dictionary).get("star", 1))))]
		var d_body := str(edef.get("effectDesc1", ""))
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_detail(battle._info_panel, "eq:" + eid, d_title, d_body, {}, u))


func _equip_readout_text(u: Dictionary, eid: String) -> String:
	var stt: Dictionary = (u.get("eq_state", {}) as Dictionary).get(eid, {})
	var parts: Array = []
	if EquipReadouts.CHARGE.has(eid):
		var c: Array = EquipReadouts.CHARGE[eid]
		var cap: float = float(c[1])
		var cur: float = clampf(float(stt.get(str(c[0]), 0.0)), 0.0, cap)
		if absf(cap - 100.0) < 0.001:
			parts.append("充能 %d%%" % int(round(cur)))
		else:
			parts.append("充能 %s / %s" % [battle._fmt_num(cur), battle._fmt_num(cap)])
	if EquipReadouts.COUNT.has(eid):
		parts.append("层数 %d" % int(stt.get(str(EquipReadouts.COUNT[eid]), 0)))
	if parts.is_empty():
		return ""
	## ★★两种读数【都有】的那 5 件要走紧凑式(2026-08-17 实拍抓到)。
	##   由来: 093 香火石两张表里都有 ⇒ 拼出「充能 0 / 4000  层数 0」共 17 个字,
	##   而槽只有 88px 宽 ⇒ 被 clip_text 从中间截断, 屏幕上印的是「能 0 / 4000  层数」——
	##   **看着像个 bug, 实际是两条正确的读数挤在一起**。
	##   紧凑式去掉"充能/层数"四个字, 分母大的转成百分比: 「0层 · 0%」最长 8 个字。
	##   (分母 ≤ 20 的保留分数形式 —— 「0层 · 0/3」比「0层 · 0%」告诉你的多。)
	if parts.size() >= 2:
		var cnt: int = int(stt.get(str(EquipReadouts.COUNT[eid]), 0))
		var cc: Array = EquipReadouts.CHARGE[eid]
		var ccap: float = float(cc[1])
		var ccur: float = clampf(float(stt.get(str(cc[0]), 0.0)), 0.0, ccap)
		if ccap <= 20.0:
			return "%d层 · %s/%s" % [cnt, battle._fmt_num(ccur), battle._fmt_num(ccap)]
		return "%d层 · %d%%" % [cnt, int(round(ccur / maxf(1.0, ccap) * 100.0))]
	return "  ".join(parts)


func _info_stat_cell(grid: GridContainer, icon: String, val: String, col: Color = Color("#d6e4f0"), icon_tex: String = "") -> Label:
	var h = HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	if icon_tex != "" and ResourceLoader.exists(icon_tex):
		var it = TextureRect.new(); it.texture = load(icon_tex)
		it.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; it.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		## ★属性图标 20 不是 26(2026-08-16): 属性区是 4 行 × 2 列的密表, 行高由图标决定 ——
		##   26→20 让整块从 110px 收到 86px, 而文字字号一点没动(可读性不变)。
		##   宝箱/熔岩龟正是靠这 24px 才装进视口的。
		it.custom_minimum_size = Vector2(20, 20); it.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(it)
	else:
		var ic = Label.new(); ic.text = icon; ic.add_theme_font_size_override("font_size", 16)
		ic.custom_minimum_size = Vector2(20, 0); ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(ic)
	var c = Label.new(); c.text = val; c.add_theme_font_size_override("font_size", UIPalette.F_BODY)
	c.add_theme_color_override("font_color", col); c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	grid.add_child(h)
	return c   # ★返回文本 Label, 供每帧刷新时改 text(见 _refresh_info_panel)

# 当前生效的状态 → chips (只显生效的); 无则"无异常状态"
# 当前生效的状态 → chips (只显生效的); 无则"无异常状态"
## 状态 chips —— ★用真图标, 不用 emoji(2026-08-16)。
##
## ★项目早已定「全去 emoji(根治绿块 + 跨平台一致)」, 而 assets/sprites/status/ 里
##   13 张状态图标【一直躺着没人用】, 和 data/status.json 的 13 条一一对得上。
##   这里是漏网的一处。
## ★资源(怒气/星能/储能/泡泡/财宝/金币)【从状态里摘出去】了 —— 它们归第二行的资源条。
##   资源是"我攒到哪了", 状态是"我正在被怎样", 两回事, 不该在同一排 chip 里平级排列。
## ★带剩余秒数: 有 *_until 的一律显示"还剩几秒", 光写"眩晕"看不出还要晕多久。
func _info_status_chips(vb: VBoxContainer, u: Dictionary) -> void:
	var sic := "res://assets/sprites/status/"
	var chips: Array = []   # [文字, 颜色, 图标路径]
	## ★形态排在最前 —— 它决定这只龟此刻的射程/移速/技能组, 是"当前状态"里最该先看到的一条。
	##   实拍证据: 熔岩龟在火山形态下面板只有射程 70/移速 120 两个数, 没有一个字说它变身了。
	var _fc: Array = _form_chip(u)
	if not _fc.is_empty():
		chips.append([str(_fc[0]), str(_fc[1]), ""])
	## 计时类: 统一带"还剩 N.N 秒"
	var _timed: Array = [
		["stun_until", "眩晕", "#ff8a3d", "stun-icon.png"],
		["slow_until", "减速", "#7fd0ff", "chilled-icon.png"],
		["taunt_until", "嘲讽", "#ff5c8a", "taunt-icon.png"],
		["untargetable_until", "不可选中", "#b28bff", "stealth-icon.png"],
		["heal_reduce_until", "治疗削减", "#ff6b6b", "heal-reduce-icon.png"],
		## ★龟能锁没有专属图标 —— 用 curse-debuff(它就是个 debuff)。缺图标登记在案, 不是漏了。
		["energy_lock_until", "龟能锁", "#ffcf5a", "curse-debuff-icon.png"],
		## ★真火同样没有专属图标 —— 用 burn(它就是火)。
		["true_fire_until", "真火", "#ffffff", "burn-icon.png"],
	]
	for t in _timed:
		var left: float = float(u.get(str(t[0]), 0.0)) - battle._t
		if left > 0.0:
			chips.append(["%s %.1fs" % [str(t[1]), left], str(t[2]), sic + str(t[3])])
	## DoT 层数: 真实层数在 dot_stacks —— 2026-07-22 查过, burn_until 是零处写入的死字段,
	## 所以旧版「灼烧」chip 从来没出现过, 哪怕身上叠了 200 层。
	var _ds: Dictionary = u.get("dot_stacks", {})
	for d in [["burn", "灼烧", "#ff6b3d", "burn-icon.png"],
			["poison", "中毒", "#7ee87e", "poison-icon.png"],
			["bleed", "流血", "#ff6b6b", "bleed-icon.png"]]:
		var n: int = int(_ds.get(str(d[0]), 0))
		if n > 0:
			chips.append(["%s %d 层" % [str(d[1]), n], str(d[2]), sic + str(d[3])])
	if float(u.get("shield", 0.0)) > 0.0:
		chips.append(["护盾 %d" % int(u.get("shield", 0.0)), "#7fe0ff", sic + "shield-icon.png"])
	var flow = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6); flow.add_theme_constant_override("v_separation", 4)
	vb.add_child(flow)
	if chips.is_empty():
		## ★没有状态就【整块不占位】—— 印一行灰字"无异常状态"是在用一行高度说"这里没东西",
		##   而面板里最缺的就是高度。没状态本身就是最清楚的表达。
		flow.visible = false
		vb.visible = false
		return
	vb.visible = true
	flow.visible = true
	for ch in chips:
		var p = PanelContainer.new()
		var sb = StyleBoxFlat.new(); sb.bg_color = Color(str(ch[1])); sb.bg_color.a = 0.20
		## ★直角, 不要圆角(2026-08-17)。这条规矩我在 log 面板上写过 ——「圆角矩形是 CSS 的长相,
		##   用户说的"网页味"里就有这一条」—— 但**漏了状态签**: 面板里别处全换成硬边像素框之后,
		##   只剩这一排小签还是平滑抗锯齿的圆角胶囊, 放大一看和上下格格不入。
		sb.border_color = Color(str(ch[1])); sb.set_border_width_all(1); sb.set_corner_radius_all(0)
		sb.content_margin_left = 6; sb.content_margin_right = 8; sb.content_margin_top = 2; sb.content_margin_bottom = 2
		## ★★2026-08-17 换成九宫格签牌。上面那条注释只解决了"圆角" —— 直角之后它仍然是
		##   【1px 描边的矩形】, 也就是 CSS `border: 1px solid` 的长相。面板里别处都换成
		##   有铆钉/倒角的像素框之后, 只剩这一排签还在用描边, 放大一看还是网页味。
		## ★为什么用 `modulate_color` 而不是各做一张图: 签是**按状态染色**的
		##   (减速蓝 / 护盾青 / 形态灰…), 直接铺一张蓝色贴图会把这套配色信息吃掉。
		##   所以贴图画成【中性灰】(实测平均饱和度 0.206), 再按 ch[1] 整体染色 ——
		##   亮的倒角沿染成该状态的亮色, 暗的中心染成同色的暗底, 一张图管所有状态。
		var _csb := _nine_box(HUD_TEX + "chip-frame.png", 7, sb)
		if _csb is StyleBoxTexture:
			var _ct := _csb as StyleBoxTexture
			_ct.modulate_color = Color(str(ch[1]))
			## 内容边距要大于沿厚(实测沿含铆钉约 4~6px), 否则字压在倒角上 ——
			## 「更多属性」那一行刚栽过一次, 同一个坑不踩第二遍。
			_ct.content_margin_left = 9; _ct.content_margin_right = 9
			_ct.content_margin_top = 3; _ct.content_margin_bottom = 3
		p.add_theme_stylebox_override("panel", _csb)
		## 图标 + 文字并排(形态那条没有图标, 只有文字)
		var hb2 = HBoxContainer.new(); hb2.add_theme_constant_override("separation", 4)
		var _ip: String = str(ch[2]) if ch.size() > 2 else ""
		if _ip != "" and ResourceLoader.exists(_ip):
			var ir = TextureRect.new()
			ir.texture = load(_ip)
			ir.custom_minimum_size = Vector2(16, 16)
			ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ir.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hb2.add_child(ir)
		var l = Label.new(); l.text = str(ch[0]); l.add_theme_font_size_override("font_size", UIPalette.F_SUB)
		l.add_theme_color_override("font_color", Color(str(ch[1])))
		hb2.add_child(l)
		p.add_child(hb2); flow.add_child(p)

## 状态区的重建签名 = 战斗那份(battle._status_signature) + 本文件新加的那几项。
## ★为什么要拼而不是另写一份: chips 是【签名变了才重建】的, 新加的 chip 只要没进签名,
##   它就永远停在开面板那一刻的值 —— "写进去了没人读"的反面, 一样是假功能。
##   拼上去而不是替换, 是为了让 battle._status_signature 继续留在真实调用链上
##   (它有自己的门禁 verify_dot_mitigation; 把它踢出调用链就变成"被门禁保护着的死代码")。
## ★口径: 每一项都取【chip 文字里真的会印出来的那个数】, 不是布尔位 ——
##   怒气 36→37 时 chip 文字会变, 签名也必须跟着变。
func _status_sig_own(u: Dictionary) -> String:
	var vol := 1 if bool(u.get("volcano", false)) else 0
	var vleft := int(maxf(0.0, float(u.get("volcano_until", 0.0)) - battle._t) * 10.0)   # 0.1 秒一档(chip 印一位小数)
	return "%s|%d|%d|%s|%d|%d|%d" % [
		battle._status_signature(u),
		vol, vleft,
		str(u.get("two_form", "")),
		1 if bool(u.get("shell_stealth", false)) else 0,
		int(float(u.get("gold", 0.0))),
		int(float(u.get("dmg_dealt", 0.0))) if str(u.get("id", "")) == "chest" else 0,
	]


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

## 第四行【技能栏】—— 被动 / 普攻 / 携带的那一个主动技, 一行一条(2026-08-16)。
##
## 每行三段: [图标 32] [技能名] [龟能消耗]。
## ★行上【不许有充能条、不许有"就绪"标记】(用户原话:「不需要什么就绪，进度条」)——
##   龟能进度已经在第二行的资源条上了, 技能行再放一遍是同一个数在同一屏说两遍。
## ★点整行 → 在这一行下面撑开一个【有边框的描述框】(用户两次说的都是"描述框");
##   一次只开一个(手风琴), 且【内联撑开不弹浮层】—— 弹层会遮战场, 违反 2026-07-18
##   定的「侧边不遮战场」。
##
## 返回 [{name, cost, icon, desc, tpl, sk}]，顺序固定: 被动 → 普攻 → 主动。
func _skill_bar_entries(u: Dictionary) -> Array:
	var out: Array = []
	var id := str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	var pool: Array = pet.get("skillPool", [])

	# ① 被动
	var passive: Dictionary = u.get("passive", {})
	if passive is Dictionary and not (passive as Dictionary).is_empty():
		var ptpl = battle.SkillText.text_of(passive, battle._skill_detail())
		var pic := ""
		var praw := str(DataRegistry.passive_icons.get(str(passive.get("type", "")), ""))
		if praw.ends_with(".png"):
			pic = "res://assets/sprites/" + praw
		out.append({"name": "被动 · " + str(passive.get("name", "")), "cost": -1.0, "icon": pic,
			"desc": battle._render._render_skill_text(ptpl, u, passive), "tpl": ptpl, "sk": passive,
			"two_level": _has_two_levels(passive)})

	# ② 普攻 = skillPool[0]。★【无条件】取, 不看 type。
	#
	# ★★2026-08-16 修一个"有条件隐藏"的 bug: 原来的判据是
	#     `if t0 == "physical" or t0 == "magic":` —— 只有普攻的 type 恰好是这两个字符串
	#     才建这一槽。而实测【28 只龟里有 17 只不是】(熔岩弹 lavaBolt / 一叶刃 bambooLeaf /
	#     冰锥 iceSpike / 星光弹 starBeam …), 于是六成的龟面板上【普攻那一格直接消失】,
	#     三槽变两槽、右边空一格, 而且不报任何错。实拍熔岩龟才看见。
	#   ⇒ pool[0] 按约定【就是】普攻(28 只无一例外), type 是它的实现细节, 不该拿来当过滤器。
	#     这正是用户 2026-07-21 骂过的那种病: "某些龟身上根本不出现那一行, 你无从知道它存在"。
	if not pool.is_empty() and pool[0] is Dictionary:
		var s0: Dictionary = pool[0]
		var btpl = battle.SkillText.text_of(s0, battle._skill_detail())
		out.append({"name": str(s0.get("name", "普攻")) + " (普攻)", "cost": -1.0,
			"icon": _skill_icon_path(s0),
			"desc": battle._render._render_skill_text(btpl, u, s0), "tpl": btpl, "sk": s0,
			"two_level": _has_two_levels(s0)})

	# ③ 携带的主动技(3选1 选中的那一个; 小将走独立文案表)
	if pool.is_empty():
		for t in u.get("active_skills", []):
			var md = battle.MINION_SKILL_DESC.get(str(t), null)
			if md != null:
				out.append({"name": str(md["name"]), "cost": battle._skill_cost(u, str(t)), "icon": "",
					"desc": str(md["desc"]), "tpl": "", "sk": {}})
	else:
		for t in battle._chosen_skill_types(id, str(u.get("side", "")) == "left"):
			for sk in pool:
				if sk is Dictionary and str(sk.get("type", "")) == str(t):
					var stpl = battle.SkillText.text_of(sk, battle._skill_detail())
					out.append({"name": str(sk.get("name", t)), "cost": battle._skill_cost(u, str(t)),
						"icon": _skill_icon_path(sk),
						"desc": battle._render._render_skill_text(stpl, u, sk), "tpl": stpl, "sk": sk,
						"two_level": _has_two_levels(sk)})
					break
	return out


## 把技能栏画出来: 一行一条 + 点行撑开【有边框的描述框】(手风琴, 一次只开一个)。
## ★不弹浮层 —— 描述框就在被点那一行下面把后面的内容往下推(守「侧边不遮战场」)。
## ★行上没有充能条、没有"就绪"标记(用户原话:「不需要什么就绪，进度条」)。
func _info_skill_bar(vb: VBoxContainer, u: Dictionary) -> void:
	## 技能区 = 【三个图标横排】(用户 2026-08-16「三个图标横着弄啊」): 被动 / 普攻 / 携带的那一个主动技。
	##
	## ★与装备三槽【同构】—— 同样是 72×72 槽 + 读数压图标上 + 点开描述框。
	##   同一个面板里两种"可点的东西"长成一样, 玩家只需要学一次。
	## ★点的就是【图标本身】(用户 #11「这些图标点击出现描述」)。
	##   我上一版做成整行可点是擅自扩大了范围 —— 现在图标就是命中区。
	## ★图标下给一行小字名字: 光看图标认不出是哪个技能, 而名字是扫一眼就要的。
	## ★龟能消耗压在图标下沿(只有主动技有) —— 与装备的充能读数同一个位置语言。
	var entries: Array = _skill_bar_entries(u)
	if entries.is_empty():
		return
	var wrap = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	vb.add_child(wrap)
	var rowc = HBoxContainer.new()
	rowc.add_theme_constant_override("separation", 8)
	wrap.add_child(rowc)
	var holder = VBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	wrap.add_child(holder)
	var boxes: Array = []
	battle._info_skill_lbls.clear()

	for e in entries:
		var ent: Dictionary = e
		var cell = VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		## ★槽是【正方】的 —— 图标本来就是方的, 拉成扁矩形只是为了填宽面板, 本末倒置。
		##   正确做法是【面板跟着槽走】: 3×88 + 2×8 = 280, 加左右边距 32 ⇒ 面板 312。
		##   88 也过了本项目的触摸线(44pt = 81 视口像素)。
		rowc.add_child(cell)

		var slot = PanelContainer.new()
		var ssb = StyleBoxFlat.new()
		ssb.bg_color = Color("#121b28")
		## ★被动槽用【紫边】与另两个区分 —— 被动是"一直生效"、普攻和技能是"要放出来的",
		##   两回事。光看图标认不出来, 而技能栏三个槽长得一模一样。
		var is_passive: bool = str(ent.get("name", "")).begins_with("被动 · ")
		ssb.set_border_width_all(1)
		ssb.border_color = Color("#8b6ec7") if is_passive else Color("#3a4c60")
		ssb.set_corner_radius_all(0)
		slot.add_theme_stylebox_override("panel", _nine_box(HUD_TEX + "slot-frame.png", 12, ssb))
		## ★被动槽染紫 —— 换成贴图槽框后, 我设在 StyleBoxFlat 上的紫色描边【失效了】
		##   (贴图不吃 border_color), 三个槽变得一模一样。这是我上一轮自己改出来的回归。
		##   用 self_modulate 给整张框上色, 保留铆钉与内沿的明暗关系。
		if is_passive:
			slot.self_modulate = Color(0.86, 0.72, 1.15)
		slot.custom_minimum_size = Vector2(88, 88)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.add_child(slot)
		var inner = Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(inner)
		var ip := str(ent.get("icon", ""))
		if ip != "" and ResourceLoader.exists(ip):
			var ir = TextureRect.new()
			ir.texture = load(ip)
			ir.set_anchors_preset(Control.PRESET_FULL_RECT)
			ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ir.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(ir)
		## 龟能消耗压图标下沿(只有主动技有; 被动/普攻不占龟能就不画)
		var cost: float = float(ent.get("cost", -1.0))
		if cost >= 0.0:
			var cl = Label.new(); cl.text = "%d" % int(cost)
			cl.add_theme_font_size_override("font_size", UIPalette.F_SUB)
			cl.add_theme_color_override("font_color", Color("#ffce4d"))
			cl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			cl.offset_top = -14.0; cl.offset_bottom = -1.0
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner.add_child(cl)
		## 图标下一行小字名字 —— 光看图标认不出是哪个技能
		## ★槽下【两行】: 上行是角色(被动/普攻/技能), 下行是名字。
		##   用户 2026-08-16:「哪个是被动，哪个是普通攻击，哪个是技能你不写吗」——
		##   光有图标和名字, 玩家不知道这三个的性质不同(一个一直生效、一个不耗龟能、一个要攒)。
		var role := "技能"
		if str(ent.get("name", "")).begins_with("被动 · "):
			role = "被动"
		elif str(ent.get("name", "")).find("(普攻)") >= 0:
			role = "普攻"
		var rl2 = Label.new(); rl2.text = role
		rl2.add_theme_font_size_override("font_size", UIPalette.F_MICRO)
		rl2.add_theme_color_override("font_color",
			Color("#b79bf0") if role == "被动" else (Color("#9fb6c9") if role == "普攻" else Color("#ffce4d")))
		rl2.custom_minimum_size = Vector2(88, 0)
		rl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(rl2)
		var nl = Label.new()
		nl.text = str(ent.get("name", "")).replace("被动 · ", "").replace(" (普攻)", "")
		nl.add_theme_font_size_override("font_size", UIPalette.F_SUB)
		nl.add_theme_color_override("font_color", Color("#dbe9f7"))
		nl.custom_minimum_size = Vector2(88, 0)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nl)

		var cur_sk: Dictionary = ent.get("sk", {})
		var d_title := str(ent.get("name", ""))
		var d_body := str(ent.get("desc", ""))
		var d_key := "sk:" + d_title
		battle._info_skill_lbls.append({"lbl": null, "tpl": str(ent.get("tpl", "")), "sk": cur_sk})
		slot.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_show_detail(battle._info_panel, d_key, d_title, d_body, cur_sk, u))


## 技能字典 → 图标绝对路径; 没配图标返回 ""。
## ★实测 112 条技能里 110 条有真图标(98%), 缺的两条: 凤凰「强化涅槃」、熔岩「熔岩爆发」。
## 九宫格像素框 —— 有贴图就用, 没有退回给定的 StyleBoxFlat。
##
## ★这三张是【新生成的】(PixelLab, 2026-08-16), 不复用商店那套, 也不带海底母题:
##   深蓝金属 + 青色内沿 + 四角铜铆钉。用户逐条要求过「不要复用」「不需要海底」
##   「没任何游戏味道」「血条龟能条都跟网页一样」。
## ★退回分支不是摆设: 贴图没导入时 ResourceLoader.exists 是 false(踩过 —— 新 PNG 没
##   .import 文件, 运行时读不到, 框就是没换上, 而且一句报错都没有)。
## 面板里的【可点入口条】: 一行标题 + 右侧 ›, 点开走同一个详情浮层。
##
## ★只此一份。面板里"内容太多、点开看"的地方有三处(更多属性 / 宝箱战利品 / 以后还会有),
##   原来「更多属性」是就地手写的一段 —— 再写第二段就是 memory
##   fb-hand-rolled-copies-drift 说的"手抄一次永远落后一次"。
## ★高度固定(约 32px)与内容多少无关 —— 这正是把它做成入口条的理由:
##   宝箱战利品原来铺 0~5 行、每行 46px, 是面板里唯一【高度无界】的一段。
func _info_more_row(parent: VBoxContainer, title: String, body: String,
		key: String, u: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#121b28")
	sb.set_border_width_all(1); sb.border_color = Color("#22303f"); sb.set_corner_radius_all(0)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	## ★九宫格自带的内容边距会盖掉上面 fallback 的 4/4 —— 实拍两条入口都是 46px 高,
	##   而它们只装一行 14px 的字。九宫格取回来之后【显式压回去】。
	## ★2026-08-17 从条框换成**槽框**。两个理由, 第二个才是根本的:
	##   ① 技术: 新条框只有 24px 高, 而这里的边距写的是 12 ⇒ 12+12=24 = 整张图,
	##      中段一行都不剩, 四角被硬拉 —— 实拍是一条又黑又厚的空条。
	##   ② 语义: 这一行是**可点的入口**, 和技能/装备槽同类, 本来就该用槽框。
	##      条框中间那道凹槽的含义是"这里要填一个量" —— 套在可点行上就被读成"没填的进度条"。
	##      (图换成真凹槽之后这个错配才显形; 旧的圆角胶囊糊在那儿反而看不出来。)
	var _rsb := _nine_box(HUD_TEX + "slot-frame.png", 12, sb)
	if _rsb is StyleBoxTexture:
		var _rt := _rsb as StyleBoxTexture
		## ★左右 16 不是 10(2026-08-17): 换成槽框后框比原来厚, 10 让左侧那道青内沿
		##   直接压在「更」字上(实拍 5 倍放大才看见)。边距要大于框自己的厚度。
		_rt.content_margin_left = 16; _rt.content_margin_right = 16
		## ★上下 6 不是 2 —— 我为了抠高度压到 2, 结果这条【可点】的入口只有 26px 高 = 14pt,
		##   而触控目标下限是 44pt(本项目 1pt = 1.846px ⇒ 44pt = 81px)。压到点不准就是本末倒置。
		##   现在 34px = 18.4pt: 仍低于 44pt, 但这一条是【整幅宽 280px】的长条, 横向很好命中。
		##   ⚠ 这个差距是【登记在案的已知缺口】, 由 verify_info_panel_fits 的断言看着,
		##     不是"我没想到"(CLAUDE.md: 缺口显式登记成断言, 不许静默截断)。
		_rt.content_margin_top = 6; _rt.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", _rsb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(row)
	var hb := HBoxContainer.new()
	row.add_child(hb)
	var l := Label.new(); l.text = title
	l.add_theme_font_size_override("font_size", UIPalette.F_BODY)
	l.add_theme_color_override("font_color", Color("#9fb6c9"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(l)
	var a := Label.new(); a.text = "›"
	a.add_theme_font_size_override("font_size", UIPalette.F_BODY)
	a.add_theme_color_override("font_color", Color("#5f7186"))
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(a)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(battle._info_panel, key, title, body, {}, u))
	return row


func _nine_box(tex_path: String, margin: int, fallback: StyleBox) -> StyleBox:
	if not ResourceLoader.exists(tex_path):
		return fallback
	var st := StyleBoxTexture.new()
	st.texture = load(tex_path)
	st.set_texture_margin_all(margin)
	return st


const HUD_TEX := "res://assets/sprites/battlehud/"


## 在给定容器里铺一层条框(九宫格)。没贴图返回 null, 调用方退回纯色底。
func _bar_frame(holder: Control) -> NinePatchRect:
	var p := HUD_TEX + "bar-frame.png"
	if not ResourceLoader.exists(p):
		return null
	var np := NinePatchRect.new()
	np.texture = load(p)
	## ★2026-08-17 换图后重量的边距。旧图 281x29 是个**圆角胶囊**(用户原话:
	##   「血条，龟能条都跟网页一样」—— 说的就是它: CSS border-radius 进度条的长相)。
	##   新图 96x32: 四角 45° 斜切(金属倒角, 不是网页圆角) + 真黑深槽 + 上沿高光。
	##   边距是**量出来的**不是拍的: 黑槽范围 x 8..87 / y 8..22 ⇒ 框厚 左右8 上8 下9,
	##   各留 2~3px 余量把斜切角整个盖进四角块, 否则拉伸时角会被拉花。
	np.patch_margin_left = 11; np.patch_margin_right = 11
	## ★★上下 6 不是 7(2026-08-17): 条框上下沿**实测只有 5px 厚**, 7 是多给的,
	##   而边距每多 1px, 资源条就要多长 2px 才画得出框 —— 宝箱龟的余量只剩 4px,
	##   而 CI 在 Linux 上字体度量不同, 4px 足以让门禁**只在 CI 上红**。
	##   6 = 5 + 1px 保险, 既盖得住沿又不白吃高度。
	np.patch_margin_top = 6; np.patch_margin_bottom = 6
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(np)
	return np


## 详情浮层 —— 点图标/点槽后【浮在信息面板自己身上】显示描述(2026-08-16)。
##
## ★为什么不是内联撑开: 撑开必然把后面的内容往下顶 ⇒ 面板超高 ⇒ 要上下滑动。
##   用户 2026-08-16:「不要向下撑开, 不希望有要上下滑动的」。
##   而且他 #21 的原话本来就是「点击图片【出现面板】后可以有按钮切换」—— 是"出现面板"。
## ★浮层只盖【信息面板自己】, 不盖战场 —— 守 2026-07-18「侧边不遮战场」。
## ★字号自适应: 放不下就 13→12→11 缩一档, 而不是开滚动条(同上, 不许滑)。
##
## 每个面板只有一个浮层, 内容按需替换 —— 天然就是"一次只开一个"。
## 给按钮套上面板自己的金属皮(2026-08-17)。
##
## ★由来: 描述浮层里的「✕」和「详细 ▾」是 **Godot 默认主题的按钮** —— 圆角 3、纯色、无框,
##   是整个面板里最"没游戏味"的两个元素。实拍 3 倍放大才看清。
## ★★它们**逃过了那条网页盒门禁**: 判据先查 `has_theme_stylebox_override`,
##   而默认主题不是 override ⇒ 根本没被扫到。**判据看不见的地方就是它的盲区** ——
##   今晚第四次栽在"判据没错、被测对象不在场"上, 这次是"被测对象在判据的视野外"。
## ★用签牌贴图而不是新做一张: 签牌本来就是"凸起的金属牌", 正是按钮该有的样子;
##   而且它是今晚为这个面板做的, 不是跨屏拿别处的素材来顶。
##   三个状态靠 modulate 区分(常态/悬停亮一档/按下暗一档), 一张图管三态。
func _btn_skin(b: Button, tint: Color) -> void:
	var tex := HUD_TEX + "chip-frame.png"
	if not ResourceLoader.exists(tex):
		return
	var t: Texture2D = load(tex)
	for st in [["normal", 1.0], ["hover", 1.25], ["pressed", 0.72], ["focus", 1.0], ["disabled", 0.55]]:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.set_texture_margin_all(7)
		sb.modulate_color = Color(tint.r * float(st[1]), tint.g * float(st[1]), tint.b * float(st[1]), 1.0)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 3; sb.content_margin_bottom = 3
		b.add_theme_stylebox_override(str(st[0]), sb)


func _detail_overlay(host_panel: Control) -> Control:
	var ov = host_panel.get_node_or_null("DetailOverlay")
	if ov != null:
		return ov
	## ★★两层结构, 不是一层(2026-08-17 实拍才发现)。
	##   ⚠ 宿主是 `PanelContainer` —— **容器会强行把子节点拉满自己的内容区**,
	##     anchors / offsets 【全部失效】。原来这里写的 `offset_top = -300`(想要 300px 高)
	##     一个像素都没生效: 实拍浮层从面板顶铺到面板底(约 640px), 而内容只占顶部 20%,
	##     下面是一大片带边框的空白, 看着像没做完。
	##   ⇒ 外层 `ov` 做成【透明的普通 Control】(它被容器拉满, 无所谓, 反正看不见),
	##     真正带框的 `Box` 挂在外层里 —— 外层不是容器, 于是 anchors/offsets 才说了算,
	##     高度在 _show_detail 里按【内容实际最小高】现算(见那边)。
	ov = Control.new()
	ov.name = "DetailOverlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP    # 吃掉点击, 不穿到下面的图标
	ov.visible = false
	host_panel.add_child(ov)
	var box = PanelContainer.new()
	box.name = "Box"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#0b1220")
	sb.set_border_width_all(2); sb.border_color = Color("#3a5470"); sb.set_corner_radius_all(0)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	## ★上面 `sb` 的 `content_margin 12/12/10/10` **只在兜底支生效**(贴图缺失时,
	##   那时边框只有 2px, 12/10 正合适)。挂上九宫格后实际生效的是纹理边距 **20/20/20/20**
	##   —— 而这是**对的**: 面板框的框艺术本身约 14px 厚, 20 只留 6px 余量;
	##   真按 12 走文字会压在框上。(2026-08-17 实测确认, 别当成"没同步"去改。)
	box.add_theme_stylebox_override("panel", _nine_box(HUD_TEX + "panel-frame.png", 20, sb))
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 0.0; box.offset_right = 0.0
	box.offset_top = -300.0; box.offset_bottom = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.add_child(box)
	var vb = VBoxContainer.new()
	vb.name = "Body"
	vb.add_theme_constant_override("separation", 6)
	box.add_child(vb)
	return ov


## 把浮层内容换成这一条, 并显示出来。再点同一个图标就收起(toggle)。
func _show_detail(host_panel: Control, key: String, title: String, body: String,
		sk: Dictionary, unit: Dictionary) -> void:
	var ov := _detail_overlay(host_panel)
	if ov.visible and str(ov.get_meta("key", "")) == key:
		ov.visible = false                          # 再点一次 = 收起
		return
	ov.set_meta("key", key)
	var vb: VBoxContainer = ov.get_node("Box/Body")
	for ch in vb.get_children():
		vb.remove_child(ch); ch.queue_free()
	var hb = HBoxContainer.new(); vb.add_child(hb)
	var ttl = Label.new(); ttl.text = title
	ttl.add_theme_font_size_override("font_size", 15)
	ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ttl)
	var cb = Button.new(); cb.text = "✕"
	cb.add_theme_font_size_override("font_size", UIPalette.F_BODY)
	_btn_skin(cb, Color("#8fa4bb"))
	cb.focus_mode = Control.FOCUS_NONE
	cb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cb.pressed.connect(func() -> void: ov.visible = false)
	hb.add_child(cb)
	var dt = RichTextLabel.new()
	dt.bbcode_enabled = true; dt.fit_content = true; dt.scroll_active = false
	dt.add_theme_font_size_override("normal_font_size", 13)
	dt.add_theme_color_override("default_color", Color("#c3d3e3"))
	dt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dt.text = body
	vb.add_child(dt)
	## 两级切换: 只在【真有两级】的条目上出现(140 条里只有 28 条)
	if not sk.is_empty() and _has_two_levels(sk):
		var brow = HBoxContainer.new()
		brow.alignment = BoxContainer.ALIGNMENT_END
		vb.add_child(brow)
		var tb = Button.new()
		tb.text = "简明 ▸" if battle._skill_detail() else "详细 ▾"
		tb.tooltip_text = "简明只给算好的数值; 详细展开公式与比率"
		tb.add_theme_font_size_override("font_size", UIPalette.F_SUB)
		tb.focus_mode = Control.FOCUS_NONE
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_btn_skin(tb, Color("#c2a35e"))   # 金调: 它是"看更多"的正向操作, 与灰调的关闭区分
		brow.add_child(tb)
		tb.pressed.connect(func() -> void:
			if GameState != null:
				GameState.skill_text_detail = not battle._skill_detail()
			var ntpl = battle.SkillText.text_of(sk, battle._skill_detail())
			dt.text = battle._render._render_skill_text(ntpl, unit, sk)
			tb.text = "简明 ▸" if battle._skill_detail() else "详细 ▾"
			_fit_detail_box(ov))
	ov.visible = true
	_fit_detail_box(ov)


## 把描述框的高度收到【内容实际需要的那么高】, 不许铺满整个面板。
##
## ★由来 2026-08-17(实拍): 描述框原来是 PanelContainer 的直接子节点, 而
##   **容器会强行把子节点拉满** ⇒ 写好的 `offset_top = -300` 一个像素都没生效,
##   浮层从面板顶铺到底(约 640px), 内容只占顶部 20%, 下面一大片带边框的空白。
## ★高度要【等一帧再量】—— RichTextLabel 的 fit_content 高度要排版完才算得出来,
##   建完当帧量到的是 0。所以这里 await 一帧再收。
func _fit_detail_box(ov: Control) -> void:
	var box: Control = ov.get_node_or_null("Box")
	if box == null:
		return
	await ov.get_tree().process_frame
	if not is_instance_valid(box) or not is_instance_valid(ov):
		return
	var want: float = box.get_combined_minimum_size().y
	## 内容太长时封顶(不许超过宿主面板的 70%), 太短时给个下限免得框比标题还矮。
	var cap: float = maxf(120.0, ov.size.y * 0.7)
	box.offset_top = -clampf(want, 90.0, cap)


## 这条技能/被动【真的有两级文案】吗?
##
## ★实测: 技能+被动共 140 条, 只有 **28 条**配了第二级(全是被动: 不屈/坚壁/生长/审判…),
##   其余 112 条 desc 是空的 —— 对它们点"详细"什么都不会变。
##   ⇒ 切换按钮【只在真有两级的条目上出现】。一个点了没反应的按钮比没有按钮更糟:
##     玩家会以为是卡了, 或者以为自己没看懂。
func _has_two_levels(sk: Dictionary) -> bool:
	var b := str(sk.get("brief", "")).strip_edges()
	var d := str(sk.get("desc", "")).strip_edges()
	return d != "" and d != b


func _skill_icon_path(sk: Dictionary) -> String:
	var ic := str(sk.get("icon", ""))
	if ic.ends_with(".png"):
		var p := "res://assets/sprites/" + ic
		if ResourceLoader.exists(p):
			return p
	return ""


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
				## ★首行补【龟能花费 + 还差几秒】—— 与每帧刷新走同一个 _skill_status_line,
				##   建面板那一刻与刷新之后不会是两套文字。
				out.append({"name": str(sk.get("name", t)),
							"desc": _skill_status_line(u, sk) + battle._render._render_skill_text(_stpl, u, sk),
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
