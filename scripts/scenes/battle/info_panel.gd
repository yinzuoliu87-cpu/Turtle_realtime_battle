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
		battle._info_hp_lbl.text = "HP  %d / %d" % [int(ud.get("hp", 0)), int(ud.get("maxHp", 0))]
	# 龟能条
	if battle._info_en_bar != null and is_instance_valid(battle._info_en_bar):
		var acts: Array = ud.get("active_skills", [])   # 与建面板处同源(L22405), 不要另造函数
		if not acts.is_empty():
			battle._info_en_bar.value = float(_energy_state(ud, str(acts[0]))[3])
			## ★改印【点数】不再印百分比(2026-08-15): 技能文案里写的是「(80 龟能)」,
			##   条上却写 "46%" —— 同一件事两个口径, 玩家对不上。见 _energy_bar_text 的说明。
			if battle._info_en_lbl != null and is_instance_valid(battle._info_en_lbl):
				battle._info_en_lbl.text = _energy_bar_text(ud)
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
	## ★★接管说明(2026-08-15): 面板【首建】时 battle_hud 调的是 battle._fill_equip_section,
	##   那一版只有"名字+星级"、没有充能/层数。装备容器是每次开面板新建的,
	##   所以拿容器实例 id 变没变当"这是个新面板"的判据, 新面板就用本文件的
	##   _info_equip_section 重铺一次(多铺这一次的代价 = 开面板后一帧, 面板本身滑入要 0.22 秒)。
	##   ⚠ 同时把 battle._info_equip_sig 写成当前签名, 否则下面那条旧分支会跟我抢着重建。
	if battle._info_equip_box != null and is_instance_valid(battle._info_equip_box):
		var esig = battle._equip_signature(ud)
		var fresh: bool = battle._info_equip_box.get_instance_id() != _info_eq_box_iid
		if fresh or esig != battle._info_equip_sig:
			_info_eq_box_iid = battle._info_equip_box.get_instance_id()
			battle._info_equip_sig = esig
			for ch in battle._info_equip_box.get_children():
				battle._info_equip_box.remove_child(ch)
				ch.queue_free()
			_info_equip_section(battle._info_equip_box, ud)
		else:
			## 充能/层数每帧都在动 —— 只改文字, 不重建节点。
			for ent2 in _info_eq_readouts:
				var elb = (ent2 as Dictionary).get("lbl", null)
				if elb == null or not is_instance_valid(elb):
					continue
				var etx := "    " + _equip_readout_text(ud, str((ent2 as Dictionary).get("eid", "")))
				if elb.text != etx:
					elb.text = etx


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
		## ★★用户 2026-08-14 实测「为什么会看到暴击率 124%」。
		##   内部计算是对的: `_resolve_dmg` 把有效暴击率钳到 100%,
		##   **溢出的每 1% 按 `DamageMath.crit_multiplier` 转成 1.5% 暴伤**。
		##   但面板原来把 `crit` 原样 ×100 显示 ⇒ 玩家看到"暴击率 124%",
		##   而那作为【概率】是没有意义的数字。
		##   ⇒ 暴击这一行钳到 100%; 溢出的部分并进【暴伤】那一行(见下), 与实战一致。
		[sic + "crit-icon.png",     "暴击 " + _pct(minf(float(u.get("crit", 0.0)), 1.0)),             W],
		## ★★☆攻速要显【次/秒】, 不是【秒】(2026-08-10 修)。
		##   原来写的是 `atk_interval` —— 那是**攻击间隔**, 却标着"攻速":
		##   数字越大反而越慢, 玩家会**整个读反**。
		##   而且图鉴那边一直是 "0.94 次/秒" ⇒ 同一个属性两处两个口径。
		##   (用户 2026-08-10:「应该是多少下每秒」)
		[sic + "aspd-icon.png",     "攻速 %s 次/秒" % battle._fmt_num(battle.aspd_mult(u) / maxf(0.001, float(u.get("atk_interval", 1.0)))), W],
		## ★★射程/移速要显【实战真正用的那个数】, 不是基础字段(2026-08-15)。
		##   原来直接印 `atk_range` / `move_spd`:
		##     · 射程漏掉了 `range_add`(装备加射程)与 `range_perm`(永久倍率) —— 战斗判定走的是
		##       `battle._eff_range()`, 面板与判定两个数;
		##     · 移速漏掉了减速/加速 —— 被冰冻减速时面板照旧印 110, 而龟实际只走 66。
		##   ⇒ 用户看到的"数值看不到"里, 有一部分其实是"数值不对"。
		[sic + "range-icon.png",    "射程 %d" % int(round(battle._eff_range(u))),                    W],
		[sic + "move-icon.png",     "移速 %d" % int(round(_eff_move_spd(u))),                        W],
	]
	# ── 用户 2026-07-21 要求补的「更多属性」 ──
	# ★★全部【恒显示】(用户第二轮明确:「全都要显示啊」)。原来做成"有值才显示",
	#   结果没装备的龟根本看不到治疗强度/护盾强度/闪避这几行。
	# ★★口径修正: 治疗强度/护盾强度是【乘算】的 —— 实装是 amt *= (1 + heal_amp),
	#   所以【基准是 100%】而不是 0。原来显示成 "+0%" 属于口径错误(用户指出:「不是100%吗」)。
	#   同理 暴伤基准 150%(crit_dmg 默认 1.5)、龟能充能基准 100%。
	#   而闪避/吸血/穿透/反伤/韧性/减伤/增伤 是【加算】的, 基准就是 0。
	## ★★这六行原来全是 `%d` + `int(round())` —— 和用户 2026-08-14 骂过的增伤/减伤是**同一个 bug**,
	##   当时只改了下面四行, 这六行漏了。不足 0.5% 一律显示成 0/100%:
	##   吸血 0.4%(海带卷刀单星)、闪避 0.3%、治疗强度 100.4%… 玩家看到 0 就以为没生效。
	##   全部改走 `_pct()`(小于 10% 保留一位小数)。
	var ls: float = float(u.get("lifesteal", 0.0)) + float(u.get("ls_bonus", 0.0))
	rows.append([sic + "lifesteal-icon.png", "吸血 " + _pct(ls), Color("#ff8fb0")])
	rows.append(["", "闪避 " + _pct(float(u.get("dodge_bonus", 0.0))), Color("#a0e8ff")])
	# 乘算类: 显示最终倍率(100% = 没有加成) —— 走 _pct_mult, 见那个函数的说明
	rows.append(["", "治疗强度 " + _pct_mult(1.0 + float(u.get("heal_amp", 0.0))), Color("#7fe39a")])
	rows.append(["", "护盾强度 " + _pct_mult(1.0 + float(u.get("shield_amp", 0.0))), Color("#ffd93d")])
	## ★暴伤 = 基础暴伤 + 暴击率溢出 100% 的部分 ×1.5(与 `DamageMath.crit_multiplier` 同一公式,
	##   不另抄一份 —— 手抄的副本必然落后)。这样"124% 暴击"在面板上读作
	##   "暴击 100% · 暴伤 186%", 玩家看到的就是实战真正生效的两个数。
	var _crit_over: float = maxf(0.0, float(u.get("crit", 0.0)) - 1.0) * 1.5
	rows.append(["", "暴伤 " + _pct_mult(float(u.get("crit_dmg", 1.5)) + _crit_over), Color("#ffb37a")])
	rows.append(["", "龟能充能 " + _pct_mult(1.0 + float(u.get("echarge_perm", 0.0))), Color("#ffce4d")])
	# 加算类: 基准 0
	rows.append(["", "护甲穿透 %d" % int(u.get("armor_pen", 0.0)), Color("#ffc48a")])
	rows.append(["", "魔法穿透 %d" % int(u.get("magic_pen", 0.0)), Color("#c9a0ff")])
	rows.append(["", "反伤 " + _pct(float(u.get("reflect", 0.0))), Color("#ff9d8a")])
	rows.append(["", "韧性 " + _pct(float(u.get("tenacity", 0.0))), Color("#d6e4f0")])
	rows.append(["", "减伤 " + _pct(float(u.get("damage_reduction", 0.0))), Color("#9bdcff")])
	rows.append(["", "增伤 " + _pct(float(u.get("damage_amp", 0.0))), Color("#ff7a7a")])
	return rows


## 实战移速 —— 战斗里龟【真正走多快】。
## ★这是 `RealtimeBattle3DScene._sim_step` 那条移动公式的镜像
##   (源码里 `var spd: float = u["move_spd"] * move_perm * 减速 * spd_move_mult * move_buff_mult`)。
## ★手抄的副本必然落后 ⇒ `verify_info_panel_live` 把 sim 那一行里出现的乘数字段名【逐个】
##   和本函数对账: sim 那边以后再加一档乘数而这里没跟, 门禁直接红。
##   (不能直接调 sim 那条 —— 它写死在每帧移动分支的中段, 没有函数出口; 加出口要动主战斗文件。)
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
			return ["熔岩形态 · 攒满怒气变火山", "#9bb0c4"]
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
	return "  ".join(parts)


## 装备区 —— 在原来的「图标+名+星级」下面补一行【局内读数】。
## ★用户 2026-08-08 的铁律是"充能条和层数不要放头顶, 在装备图标框里", 说的是**别在龟头顶
##   另画一套条**。这里是玩家主动点开的详情面板, 且读的就是图标框那两张表的同一个字段,
##   一根新条都没建, 只是把那个数字用文字写清楚。
func _info_equip_section(box: VBoxContainer, u: Dictionary) -> void:
	_info_eq_readouts.clear()
	var equips: Array = u.get("equips", [])
	battle._add_section_title(box, "装备 (%d)" % equips.size())
	if equips.is_empty():
		battle._add_body_text(box, "无装备", Color("#7a8694"))
		return
	for e in equips:
		var eid := str((e as Dictionary).get("id", ""))
		battle._add_equip_row(box, eid, int((e as Dictionary).get("star", 1)))
		var rd := _equip_readout_text(u, eid)
		if rd != "":
			_info_eq_readouts.append({"lbl": battle._add_body_text(box, "    " + rd, Color("#ffd27a")), "eid": eid})


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
	## ★形态排在最前 —— 它决定这只龟此刻的射程/移速/技能组, 是"当前状态"里最该先看到的一条。
	##   实拍证据: 熔岩龟在火山形态下面板只有射程 70/移速 120 两个数, 没有任何一个字说它变身了。
	var _fc: Array = _form_chip(u)
	if not _fc.is_empty(): chips.append(_fc)
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
	## ★怒气要带分母。满 100 变身火山(battle.RAGE_MAX), 只印一个 36 玩家不知道离变身还有多远。
	##   ★★火山形态下 `rage` 被 _sim_step 复用成【倒计时百分比】(rage = 100 × 剩余/总时长),
	##     那时再挂"怒气"就是骗人 —— 剩余时间已经由上面的形态 chip 说清楚了, 这里让路。
	if float(u.get("rage", 0.0)) > 0.0 and not bool(u.get("volcano", false)):
		chips.append(["😤 怒气 %d / %d" % [int(u.get("rage", 0.0)), int(battle.RAGE_MAX)], "#ff9d5c"])
	## ★星能上限 = 最大生命 40%(star_system 里 `star_energy >= u["maxHp"] * 0.40` 那两处判定),
	##   攒满才放强化版技能。原来只印当前值, 看不出离强化还有多远。
	if float(u.get("star_energy", 0.0)) > 0.0:
		var _sf: float = maxf(1.0, float(u.get("maxHp", 1.0)) * STAR_FULL_PCT)
		var _se: float = float(u.get("star_energy", 0.0))
		chips.append([("⭐ 星能 %d / %d" % [int(_se), int(_sf)]) + ("  攒满了" if _se >= _sf else ""), "#b28bff"])
	## ★★用户 2026-08-14:「这个金币哪里有显示吗」——查证: 局内金币 `u["gold"]`
	##   在 info_panel / battle_hud / hp_bar **一处都没有显示**。
	##   而它是有用的: 财富龟普攻带 `"gold": 0.02`(每点金币 +2% 攻击加成)、
	##   `fortuneAllIn` 还要判金币数 ⇒ 玩家看不到自己攒了多少, 也就无法决策什么时候梭哈。
	##   (局外【深海币】是有显示的: 背包页与主菜单; 缺的只有局内这个。)
	if float(u.get("gold", 0.0)) > 0.0: chips.append(["🪙 金币 %d" % int(u.get("gold", 0.0)), "#ffd24d"])
	## 宝箱龟的【财宝值】同理 —— 它驱动开箱与"清点财宝"的治疗加成, 之前也看不到。
	if float(u.get("dmg_dealt", 0.0)) > 0.0 and str(u.get("id", "")) == "chest":
		chips.append(["💰 财宝 %d" % int(u.get("dmg_dealt", 0.0)), "#ffcf6b"])
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
