class_name BattleHud
extends RefCounted
## 战斗HUD/面板构建与显示: UI层/暂停/日志/统计/编辑笔刷/队伍头像框/胜负横幅/点龟详情面板/触控盘·纯UI
## 类内名不变;外部名加 battle.

## 被动技能 id → 圆盘图标。
## ★为什么单列一张: battle.TRAINER_SKILLS 只收【主动技】, 被动的图标一直只存在
##   TrainerConfigScene.SKILLS 里 —— 战斗侧取不到, 于是 get("",{}) 回落成钩锁图标,
##   这就是"选了魔法石局内还是钩锁图标"的根因。门禁 verify_trainer_skills 焊两张表一致。
const PASSIVE_ICONS := {
	"magic_stone": "res://assets/sprites/vfx/magic-stone-icon.png",
}

var battle

func _init(b) -> void:
	battle = b

func _build_ui_layer() -> void:
	battle._ui_layer = CanvasLayer.new()
	battle._ui_layer.name = "UIOverlay"
	if OS.has_environment("VFXISO"): battle._ui_layer.visible = false   # 纯特效隔离: 藏UI层(血条/飘字/头顶)
	battle._ui_layer.layer = 10
	battle.add_child(battle._ui_layer)
	# 屏幕暗角 (vignette): 铺满屏一张 radial 渐变 (中心透明→四角压暗) → 聚焦中心战斗, 收边氛围.
	#   作 battle._ui_layer 首个子 → 在 3D 之上、其余 UI(标题/血条/飘字)之下, 不挡可读性.
	if not OS.has_environment("NOVIG"):
		var vig = ColorRect.new()
		vig.name = "Vignette"
		vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vig.material = battle._make_vignette_material()   # canvas shader: 按 UV 半径算暗角 alpha (RGB 正确, 不露灰)
		battle._ui_layer.add_child(vig)
	var title = Label.new()
	title.text = "2.5D 实时战斗 · 3v3 (左队 vs 右队)"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(24, 16)
	battle._ui_layer.add_child(title)
	_build_pk_bar()   # 顶部双方总血量 PK 条 (用户2026-07-30 需求1)
	if battle._is_dual_lane_mode():   # 双路 HUD: 当前路 + 双方蛋血
		battle._dl_hud = Label.new()
		battle._dl_hud.add_theme_font_size_override("font_size", 17)
		battle._dl_hud.add_theme_color_override("font_color", Color("#ffe08a"))
		# ★y 44→50: PK 条占了 16..42, 给它腾位(用户2026-07-30)
		battle._dl_hud.position = Vector2(340, 50); battle._dl_hud.size = Vector2(700, 24)
		battle._dl_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		battle._ui_layer.add_child(battle._dl_hud)
	_build_topright_btns()   # 📊 统计 + 🏳 投降 (原 ⏸暂停/📜日志 已移除·用户2026-07-30)


## 右上角顶栏按钮.
##
## ★用户 2026-07-30:「战斗日志按钮移除掉，暂停按钮移除掉，局内不再有退出去或暂停的按钮了，
##   新增投降按钮，点击后有确认认输的提示框」。
##   方案书 docs/plans/20260730b-局内HUD改造+大师审核+地图提升.md
##
## 移除的连带影响(不只是"删两个按钮" —— 方案书 §4.2 穷举了 11 处):
##   · "退出去"原本【只存在于暂停面板里】(🏠返回菜单 / ⚔重开) → 一并消失, 逃生口改为投降
##   · _CamInputRelay 是【纯粹为暂停而存在】的 ALWAYS 中继(暂停时根节点 PAUSABLE 收不到
##     _unhandled_input) → 暂停没了它就是死代码, 已删
##   · _toggle_pause 里"清拖动/捏合脏态"那段【不能删只能搬】—— verify_cam_pan 有专门的
##     _test_pause_clears_drag_state 守着它。已搬成 battle._clear_input_dirty(),
##     由投降确认框接管: 弹框遮罩 MOUSE_FILTER_STOP 会吃掉 release, 与暂停打断拖动同形。
##
## 日志(U3): 只删按钮, _log()/_log_panel/_toggle_log 全保留 —— _log() 被战斗各处调用,
##   且 verify_battle_ui B 组守着它。📜 按钮只在调试场(DEBUG_EDIT)下出现, 正式对局没有。
func _build_topright_btns() -> void:
	var _x := 1148.0                                   # 统计按钮补上原日志按钮的位
	if battle.DEBUG_EDIT:                              # 调试场保留 📜(我自己排查要用·U8: 开发工具不属"局内")
		var log_btn = Button.new()
		log_btn.text = "📜"
		log_btn.position = Vector2(1088, 12); log_btn.size = Vector2(52, 38)
		log_btn.add_theme_font_size_override("font_size", 20)
		battle._style_hud_btn(log_btn)
		log_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		log_btn.pressed.connect(battle._toggle_log)
		battle._ui_layer.add_child(log_btn)

	var stats_btn = Button.new()
	stats_btn.text = "📊"
	stats_btn.position = Vector2(_x, 12); stats_btn.size = Vector2(52, 38)
	stats_btn.add_theme_font_size_override("font_size", 20)
	battle._style_hud_btn(stats_btn)
	stats_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	stats_btn.pressed.connect(battle._on_dmg_stats_toggle)
	battle._ui_layer.add_child(stats_btn)

	# 🏳 投降: 放在原暂停位(最右) —— 肌肉记忆上"最右是退出类操作", 也不用重算安全区.
	battle._surrender_btn = Button.new()
	battle._surrender_btn.text = "🏳"
	battle._surrender_btn.position = Vector2(1208, 12); battle._surrender_btn.size = Vector2(52, 38)
	battle._surrender_btn.add_theme_font_size_override("font_size", 20)
	battle._style_hud_btn(battle._surrender_btn)
	battle._surrender_btn.add_theme_color_override("font_color", Color("#ff9a9a"))   # 红字=危险操作
	battle._surrender_btn.tooltip_text = "投降认输"
	battle._surrender_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	battle._surrender_btn.pressed.connect(battle._show_surrender_confirm)
	battle._ui_layer.add_child(battle._surrender_btn)

	_build_surrender_panel()
	_build_log_panel()


## 投降确认浮层: 半透明黑幕 + 居中盒(取消 / 确认认输). 默认隐.
##
## ★取代原来的暂停浮层(用户 2026-07-30:「局内不再有退出去或暂停的按钮了，新增投降按钮，
##   点击后有确认认输的提示框」)。原暂停浮层里的 ▶继续/⚔重开/🏠返回菜单 一并移除 ——
##   "退出去"原本【只存在于那个面板里】, 现在唯一的离场路径就是投降。
##
## ★暗幕【必须 STOP】(与原暂停浮层相反): 这个框弹出时战斗【仍在跑】(U6: 不暂停),
##   所以暗幕不吃事件的话点击会穿到战场上去选龟/放技能。
##   代价是 release 事件被暗幕吃掉 → 开框时必须调 _clear_input_dirty(), 见该函数注释。
func _build_surrender_panel() -> void:
	battle._surrender_panel = Control.new()
	battle._surrender_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle._surrender_panel.visible = false
	battle._surrender_panel.process_mode = Node.PROCESS_MODE_ALWAYS   # 将来若有别处暂停, 这框仍要能点
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP               # ★吃掉点击: 战斗没暂停, 不吃就会穿到战场
	battle._surrender_panel.add_child(dim)
	# ★锚点自适应, 不写死 1280×720 —— 手机分辨率不同, 写死会跑偏出屏
	#   (2026-07-21 结算横幅就是踩了这个, 见 _show_banner 注释)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	battle._surrender_panel.add_child(box)
	var title := Label.new()
	title.text = "确认认输？"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("#ffb3b3"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tip := Label.new()
	tip.text = "投降将直接判定本场失败，不可撤销。"
	tip.add_theme_font_size_override("font_size", 19)
	tip.add_theme_color_override("font_color", Color("#cfe6ff"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	var tip2 := Label.new()
	tip2.text = "（确认后进入结算，本场奖励与记录仍会结算）"
	tip2.add_theme_font_size_override("font_size", 15)
	tip2.add_theme_color_override("font_color", Color("#8a93a0"))
	tip2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(battle._make_result_btn("取消", Color("#8a93a0"), Color("#12161f"),
		func() -> void: battle._hide_surrender_confirm()))
	row.add_child(battle._make_result_btn("确认认输", Color("#ff6b6b"), Color("#3a0000"),
		func() -> void: battle._do_surrender()))
	battle._ui_layer.add_child(battle._surrender_panel)


# ════════════════════════════════════════════════════════════════════════════
#  顶部双方总血量 PK 条 (用户 2026-07-30 需求1 · 方案书 docs/plans/20260730b-*.md)
#
#  「对局内的顶部左右新加一个双方血条的pk，表示双方总血量实时变化」
#
#  版式 = 用户拍板的【中央对撞条】: 一条横在顶部中央, 蓝(左队)占左半从左端往中间长、
#    红(右队)占右半从右端往中间长; 中间露出的暗缝 = 双方已损失的总量。
#    (备选"左右分列两条"被否: 两条各自看, 看不出【相对】强弱, PK 就没意义了)
#
#  ★每侧长度按【自己的开场基线】归一化, 不是按"双方当前血之和"的相对比。
#    我第一版就写成了纯相对比(seam = l.hp/(l.hp+r.hp)), 结果 _pk_base_l/r 存了却没人用,
#    而且【双方都剩 10% 血时条看起来和双方满血一模一样】—— 丢掉了"总血量"这个绝对信息,
#    而需求原文是「表示双方【总血量】实时变化」。相对优势改由中间那个百分比读。
#
#  ★计入口径 = 【龟统领 + 小将】(用户逐字「小将和龟统领的」):
#    · 不含龟蛋 —— 它 atk/def/mr 全 0, 是纯血包; 算进去会让"龟死光了条还是满的"
#    · 不含训龟大师 —— 500血/1攻/站着不动, 是噪声
#    · 不含召唤体 —— 与 _check_over 的胜负判定同口径(那里也 skip is_summon)
#
#  ★分母固定为【本路开场基线】, 不用"当前存活单位 maxHp 之和" ——
#    后者会让死一只时分子分母同缩、百分比反而【回升】, 条往回涨, 完全反直觉。
#
#  ★两条独立伤害路径(_apply_damage / _apply_damage_from, CLAUDE.md §3.3)在这里【不需要各改一遍】:
#    本条不在伤害路径里记账, 而是定时扫 _units 求和 —— 天然免疫"漏改一条路径", 也免疫
#    护盾/回血/复活没走伤害钩这类漏记。代价是有 ≤0.1s 的延迟, 对一条 UI 条完全可接受。
# ════════════════════════════════════════════════════════════════════════════

const PK_W := 600.0          # 条宽; 600 而非 680 → 左端 x=340 让开标题文字(24..~324)
const PK_H := 26.0
const PK_Y := 16.0           # 占 16..42; 双路 HUD 已下移到 50
const PK_SAMPLE := 0.1       # 扫 _units 的采样间隔(秒)。别每帧扫: 主文件热路径预算 <0.2%
const PK_SMOOTH := 6.0       # 接缝平滑速率(越大越快跟上); 逐帧插值, 群伤瞬间不抽搐
const PK_BLUE := Color("#3fa9ff")   # 与左队头像框描边同色(info_panel._make_team_frame)
const PK_RED := Color("#ff5a5a")    # 与右队头像框描边同色


## 建 PK 条。★锚点自适应(顶部居中), 不写死 1280×720 ——
##   2026-07-21 结算横幅就是踩了写死绝对坐标, 手机分辨率不同会跑偏出屏(见 _show_banner 注释)。
func _build_pk_bar() -> void:
	var bar := Control.new()
	bar.name = "PkBar"
	bar.anchor_left = 0.5; bar.anchor_right = 0.5
	bar.anchor_top = 0.0; bar.anchor_bottom = 0.0
	bar.offset_left = -PK_W * 0.5; bar.offset_right = PK_W * 0.5
	bar.offset_top = PK_Y; bar.offset_bottom = PK_Y + PK_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示, 别吃战场点击
	battle._ui_layer.add_child(bar)
	battle._pk_bar = bar

	var bg := Panel.new()                            # 底 + 边框
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.88)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.58, 0.75, 0.55)
	sb.set_corner_radius_all(5)
	bg.add_theme_stylebox_override("panel", sb)
	bar.add_child(bg)

	battle._pk_fill_l = ColorRect.new()
	battle._pk_fill_l.color = PK_BLUE
	battle._pk_fill_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle._pk_fill_l.position = Vector2(2, 2)
	bar.add_child(battle._pk_fill_l)

	battle._pk_fill_r = ColorRect.new()
	battle._pk_fill_r.color = PK_RED
	battle._pk_fill_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(battle._pk_fill_r)

	# 数字压在条【内】(左端左对齐 / 右端右对齐 / 中间百分比) —— 放条外要再占一行,
	# 会撞到已经下移的双路 HUD。
	battle._pk_lab_l = _pk_mk_label(HORIZONTAL_ALIGNMENT_LEFT)
	battle._pk_lab_l.offset_left = 8
	bar.add_child(battle._pk_lab_l)
	battle._pk_lab_r = _pk_mk_label(HORIZONTAL_ALIGNMENT_RIGHT)
	battle._pk_lab_r.offset_right = -8
	bar.add_child(battle._pk_lab_r)
	battle._pk_lab_mid = _pk_mk_label(HORIZONTAL_ALIGNMENT_CENTER)
	bar.add_child(battle._pk_lab_mid)

	battle._pk_count = -1        # 逼下一次 _pk_refresh 重算基线
	_pk_refresh()
	_pk_apply(battle._pk_shown_l, battle._pk_shown_r)


func _pk_mk_label(align: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#ffffff"))
	l.add_theme_constant_override("outline_size", 4)          # 描边: 压在蓝/红上要读得清
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


## 这个单位算不算进 PK 条。见本节顶部注释的口径说明。
func _pk_counts(u: Dictionary) -> bool:
	if u.get("egg", false) or u.get("has_egg", false):
		return false
	if u.get("is_trainer", false):
		return false
	if u.get("is_summon", false):
		return false
	return true


## 一侧的 (当前血, 开场基线用的最大生命) 之和。
## ★用【有效阵营】_eff_side —— 赛博侵入后的单位仍按原阵营计, 与 _check_over 一致(见 7349 注释)。
## ★禁止拿单位字典当 key / 用 == 比较(CLAUDE.md §3.2), 这里只读字段, 安全。
func _pk_sum(side: String) -> Vector2:
	var cur := 0.0
	var mx := 0.0
	for u in battle._units:
		if not _pk_counts(u):
			continue
		if battle._eff_side(u) != side:
			continue
		mx += maxf(0.0, float(u.get("maxHp", 0)))
		if u.get("alive", false):
			cur += maxf(0.0, float(u.get("hp", 0)))
	return Vector2(cur, mx)


## 重扫 _units → 更新目标占比与两端数字。每 PK_SAMPLE 秒一次。
##
## ★换路检测: 用"计入 PK 的单位数变了"当信号。为什么可靠 ——
##   单位死亡【不会】从 battle._units 里移除(只把 alive 置 false), 所以一路之内这个数是恒定的;
##   而换路时 _dl_clear_units() 会清空 _units 再重新 spawn(见 dual_lane_flow:719-724), 数必然变。
##   ★不能只在场景初始化时算一次基线 —— 全局时钟 _t 跨上路→下路→决胜一直累加(CLAUDE.md §3.4),
##   任何"按本场"计的东西都得自己存基线, 这里同理。
func _pk_refresh() -> void:
	if battle._pk_bar == null or not is_instance_valid(battle._pk_bar):
		return
	var n := 0
	for u in battle._units:
		if _pk_counts(u):
			n += 1
	var l := _pk_sum("left")
	var r := _pk_sum("right")
	if n != battle._pk_count:                  # 换路(或首次) → 重算固定分母
		battle._pk_count = n
		battle._pk_base_l = l.y
		battle._pk_base_r = r.y
		battle._pk_shown_l = 1.0               # 新一路两边都从满开始, 别从上一路的长度滑过来
		battle._pk_shown_r = 1.0
	# ★分母是【开场基线】而不是"当前存活单位 maxHp 之和" ——
	#   后者会让死一只时分子分母同缩、比例反而【回升】, 条往回涨, 完全反直觉。
	battle._pk_target_l = 0.0 if battle._pk_base_l <= 0.0 else clampf(l.x / battle._pk_base_l, 0.0, 1.0)
	battle._pk_target_r = 0.0 if battle._pk_base_r <= 0.0 else clampf(r.x / battle._pk_base_r, 0.0, 1.0)
	# 数字 = 当前血量绝对值(千分位); 中间 = 相对优势(谁在赢) —— 这一项才是"PK"的读数
	battle._pk_lab_l.text = _pk_num(l.x)
	battle._pk_lab_r.text = _pk_num(r.x)
	var tot: float = l.x + r.x
	var adv: float = 0.5 if tot <= 0.0 else clampf(l.x / tot, 0.0, 1.0)
	var pct: int = int(round(adv * 100.0))
	var arrow := "▲" if pct > 50 else ("▼" if pct < 50 else "＝")
	battle._pk_lab_mid.text = "%s %d%%" % [arrow, pct]
	battle._pk_lab_mid.add_theme_color_override("font_color",
		PK_BLUE if pct > 50 else (PK_RED if pct < 50 else Color("#ffffff")))


## 千分位。1234 → "1,234"
func _pk_num(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


## 把两侧比例画成两段填充: 蓝占左半从左端往中间长, 红占右半从右端往中间长。
## 中间露出的暗缝(底 Panel) = 双方已损失的总量, 缝的中点偏向哪边说明哪边吃亏更多。
func _pk_apply(fl: float, fr: float) -> void:
	if battle._pk_fill_l == null or not is_instance_valid(battle._pk_fill_l):
		return
	var inner: float = maxf(0.0, PK_W - 4.0)      # 减掉 2px 边框×2
	var half: float = inner * 0.5
	var lw: float = clampf(fl, 0.0, 1.0) * half
	var rw: float = clampf(fr, 0.0, 1.0) * half
	var h: float = PK_H - 4.0
	battle._pk_fill_l.position = Vector2(2, 2)
	battle._pk_fill_l.size = Vector2(lw, h)
	battle._pk_fill_r.position = Vector2(2.0 + inner - rw, 2)
	battle._pk_fill_r.size = Vector2(rw, h)


## 每帧驱动: 逐帧平滑两侧长度 + 每 PK_SAMPLE 秒重扫一次 _units。
## 由 battle_render._render_step 调用(渲染路, 不进 sim → 不影响确定性)。
func _pk_tick(delta: float) -> void:
	if battle._pk_bar == null or not is_instance_valid(battle._pk_bar):
		return
	battle._pk_acc += delta
	if battle._pk_acc >= PK_SAMPLE:
		battle._pk_acc = 0.0
		_pk_refresh()
	battle._pk_shown_l = _pk_ease(battle._pk_shown_l, battle._pk_target_l, delta)
	battle._pk_shown_r = _pk_ease(battle._pk_shown_r, battle._pk_target_r, delta)
	_pk_apply(battle._pk_shown_l, battle._pk_shown_r)


## 向目标平滑一步; 收敛就【吸附】—— 否则无限逼近会永远留半像素缝。
func _pk_ease(cur: float, target: float, delta: float) -> float:
	var d: float = target - cur
	if absf(d) < 0.0008:
		return target
	return cur + d * clampf(delta * PK_SMOOTH, 0.0, 1.0)


## HUD 小按钮统一样式: 半透明深底 + 圆角 + hover 高亮.
func _build_log_panel() -> void:
	battle._log_panel = Panel.new()
	battle._log_panel.position = Vector2(24, 300); battle._log_panel.size = Vector2(440, 380)
	battle._log_panel.visible = false
	battle._log_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	psb.border_color = Color(0.4, 0.55, 0.72, 0.5)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	battle._log_panel.add_theme_stylebox_override("panel", psb)
	var vb = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_top = 10; vb.offset_right = -12; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 6)
	battle._log_panel.add_child(vb)
	var hdr = Label.new()
	hdr.text = "📜 战斗日志"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color("#cfe6ff"))
	vb.add_child(hdr)
	battle._log_rt = RichTextLabel.new()
	battle._log_rt.bbcode_enabled = true
	battle._log_rt.scroll_active = true
	battle._log_rt.scroll_following = true
	battle._log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle._log_rt.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(battle._log_rt)
	battle._ui_layer.add_child(battle._log_panel)


## 日志开关: 显/隐面板; 打开时用累积的 _battle_log 重建文本.
func _build_trainer_joystick() -> void:
	if not (SafeArea.is_mobile() or OS.has_environment("TRAINER_JOY")):
		return
	if battle._joystick != null and is_instance_valid(battle._joystick):
		return
	battle._joystick = battle.VirtualJoystick.new()
	var m: Vector4 = SafeArea.margins(Vector2(battle.get_viewport().get_visible_rect().size), 18.0)
	battle._joystick.position = Vector2(m.x, float(battle.get_viewport().get_visible_rect().size.y) - battle.VirtualJoystick.RADIUS * 2.0 - m.w)
	battle._ui_layer.add_child(battle._joystick)


## 双方各 spawn 一个训龟大师(用户2026-07-22 需求3: 己方玩家控制, 对面人机)。
## 站位: 各自基地【后方角落】—— 它射程 2000 够到全场, 不需要靠前; 放角落才像"场外监视者",
## 也不会挤进战线影响分离/避障。
## ★幂等: 已经有了就不重复建 —— _spawn._spawn_teams 与 battle._dl_sys._dl_build_lane_field 都会调, 双路模式下
##   若两边都跑到会 spawn 两个(实测双路走的是后者, 但留这道闸防将来改动)。
func _build_spell_disc() -> void:
	if battle._spell_disc != null and is_instance_valid(battle._spell_disc):
		return
	if battle._ui_layer == null:
		return
	# 圆盘显示【我方大师已装配的技能】图标(缺图→无图标, 不崩)。
	#
	# ★用户 2026-07-28 报「选了魔法石, 局内右边图标不是魔法石」——
	#   根因: 魔法石是【被动】, trainer_active_skill() 返回 "" → sid="" →
	#   TRAINER_SKILLS.get("", {}) 取不到 → 回落默认值 HOOK_ICON, 于是永远显示钩锁。
	#   而 TRAINER_SKILLS 里【根本没有 magic_stone 条目】(它只收主动技),
	#   被动的图标另存在 TrainerConfigScene.SKILLS 里 —— 两张表各存一半, 这本身就是分歧源。
	#   这里按【装配的那个 id】直接取图, 主动被动一视同仁。
	var _act: String = GameState.trainer_active_skill()
	var _pas: String = GameState.trainer_passive_skill()
	var sid: String = battle._valid_active(_act) if _act != "" else ""
	var ipath: String = PASSIVE_ICONS.get(_pas, "") if sid == "" else str(battle.TRAINER_SKILLS.get(sid, {}).get("icon", battle.HOOK_ICON))
	if ipath == "":
		ipath = battle.HOOK_ICON
	var icon: Texture2D = load(ipath) if ResourceLoader.exists(ipath) else null
	battle._spell_disc = battle.SpellDisc.new()
	battle._spell_disc.setup(icon, "Q", Callable(battle._trainer_sys, "_player_cast_hook_auto"), Callable(battle._aim, "_on_spell_aim"))   # 2026-07-26: 修好回调指向真owner(原 Callable(self=BattleHud,…) 指向不存在的方法·移动端圆盘一直没接上)
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var m: Vector4 = SafeArea.margins(vp, 18.0)
	battle._spell_disc.position = Vector2(vp.x - battle.SpellDisc.R * 2.0 - m.z, vp.y - battle.SpellDisc.R * 2.0 - m.w)
	battle._ui_layer.add_child(battle._spell_disc)
	if sid == "" and _pas != "":
		_build_passive_ring(battle._spell_disc)


## 装配的是【被动】时, 圆盘上加一圈持续旋转的紫色符环 —— 表示"被动生效中"。
##
## 由来: 用户 2026-07-28 问"没有循环绕圈的特效"。代码里原本自己写着
## 「R2 再给圆盘加"被动生效中"循环特效」—— 是当时推迟的待办, 不是坏了。
##
## ★被动没有冷却也不能点, 圆盘对它来说本来是【纯状态指示】。转起来是为了让人知道
##   "它在工作", 而不是"这个键是灰的/坏的"。
func _build_passive_ring(disc: Control) -> void:
	var ring := TextureRect.new()
	ring.texture = VfxTex._make_ring_texture(Color("#c86bff"))
	ring.modulate = Color("#c86bff")   # 环贴图是白底, 上色靠 modulate(见 _make_ring_texture 注释)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d: float = battle.SpellDisc.R * 2.3
	ring.size = Vector2(d, d)
	# ★pivot 必须设在中心, 否则 rotation 会绕左上角转 —— 看起来是"在屏幕上画圈跑"而不是"自转"
	ring.pivot_offset = ring.size * 0.5
	ring.position = Vector2(battle.SpellDisc.R, battle.SpellDisc.R) - ring.size * 0.5
	disc.add_child(ring)
	# 无限循环旋转。用 tween 而不是 _process: 这是纯 UI 演出, 不进战斗时钟, 也不受暂停影响。
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation", TAU, 3.2).from(0.0)


## 训龟大师立绘。用户要「像素风的冒险家」, 形象未定 —— 真图放到 battle.TRAINER_SPRITE 即自动生效。
## ★没真图时【退回占位并 push_warning】而不是静默兜底: 占位是小龟, 和冒险家长得完全不一样,
##   悄悄用会让人(包括我自己)以为形象已经做完了。门禁 verify_trainer 也断言这条 warning 存在。
func _show_banner(won: bool) -> void:
	if battle._settled:
		return
	battle._settled = true
	# 结算: 收掉投降确认框并禁用投降按钮(已经结算了, 没什么可投降的); 记一条日志.
	# ★仍然解除 get_tree().paused —— 暂停按钮虽已移除(用户2026-07-30), 但树可能被别处暂停,
	#   结算屏必须能动。这里不假设"没人会暂停"。
	if battle.get_tree().paused:
		battle.get_tree().paused = false
	if battle._surrender_panel != null and is_instance_valid(battle._surrender_panel):
		battle._surrender_panel.visible = false
	if battle._surrender_btn != null and is_instance_valid(battle._surrender_btn):
		battle._surrender_btn.disabled = true
	battle._log("[color=%s]%s[/color]" % ["#ffd93d" if won else "#ff6b6b", "🏆 战斗胜利!" if won else "💀 战斗失败!"])
	# §AUDIO: 结算 — 败方放 defeat 音; BGM 淡出收尾.
	# ⚠缺口(2026-07-21 核实): assets/audio/sfx/ 下【只有 defeat.wav, 没有胜利音】,
	#   所以赢了是静悄悄的。不在这里硬写一个 "victory" —— 文件不存在时 battle._audio_sys._sfx_simple 是
	#   静默失败(不报错、只是没声音), 反而更难发现。等补了音频文件再接。
	if not won:
		battle._audio_sys._sfx_simple("defeat")
	var a = battle._audio_sys._audio()
	if a != null:
		a.stop_bgm()
	var gs = battle.get_node_or_null("/root/GameState")
	var accent = Color("#ffd93d") if won else Color("#ff6b6b")
	# ★2026-07-21 修: 原来这里【全部写死 1280×720 + 绝对 y 坐标】, 只有正好 1280×720 才对,
	#   手机上(分辨率不同)大字会跑偏甚至出屏。改成锚点自适应 —— 任何分辨率都居中。
	#   (用户问「结算的页面你放在屏幕中间了吗」时查出来的: 本路结算幕用 CenterContainer 是对的,
	#    但这个【最终胜负横幅】是另一套写死坐标的代码。)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)                    # 从全透明淡入
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)   # ★锚点铺满, 不写死尺寸
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	battle._ui_layer.add_child(dim)
	var dtw = battle.create_tween()
	dtw.tween_property(dim, "color:a", 0.6, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var big = Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	big.set_anchors_preset(Control.PRESET_CENTER_TOP)  # ★横向锚点居中
	big.anchor_left = 0.0; big.anchor_right = 1.0
	big.offset_left = 0.0; big.offset_right = 0.0
	big.anchor_top = 0.34; big.anchor_bottom = 0.34
	big.offset_top = -40.0; big.offset_bottom = 40.0
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle._ui_layer.add_child(big)
	# 大字入场: 从大缩到正常 + 淡入(原来是瞬间弹出)
	big.scale = Vector2(1.9, 1.9)
	big.pivot_offset = Vector2(big.size.x * 0.5, 40.0)
	big.modulate.a = 0.0
	var btw = battle.create_tween()
	btw.set_parallel(true)
	btw.tween_property(big, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	btw.tween_property(big, "modulate:a", 1.0, 0.30).set_delay(0.12)
	# 双路: 大标题下补「整场比分 X-Y」→ 上下路都输显 0-2 整场失败, 一目了然(用户2026-07-12)
	if battle._is_dual_lane_mode() and gs != null and gs.get("lane_results") is Dictionary and not (gs.get("lane_results") as Dictionary).is_empty():
		var score = Label.new()
		score.text = battle._dl_sys._dl_record_line()
		score.add_theme_font_size_override("font_size", 24)
		score.add_theme_color_override("font_color", Color("#cfe6ff"))
		_banner_anchor_row(score, 0.455, 17.0)   # ★锚点自适应(原 position=(0,316) 写死)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		battle._ui_layer.add_child(score)
		_banner_fade_in(score, 0.34)
	# 奖励/赛季行 (有赛季态才显)
	var info = ""
	if battle._had_season and gs != null:
		if battle._last_was_exhibition:
			info = "表演赛 · +%d 深海币 (已淘汰, 无生命消耗)" % battle._last_reward
		else:
			info = "+%d 深海币    命 %d/8    胜场 %d    Lv.%d" % [battle._last_reward, int(gs.hearts), int(gs.season_wins), int(gs.get("season_level") if gs.get("season_level") != null else 1)]
			if not won:
				info += "    (失一命)"
			if gs.is_eliminated():
				info += "  ·  赛季淘汰!"
	else:
		info = "(练习赛 · 无赛季奖励)"
	var rew = Label.new()
	rew.text = info
	rew.add_theme_font_size_override("font_size", 22)
	rew.add_theme_color_override("font_color", Color("#ffe9a8"))
	_banner_anchor_row(rew, 0.505, 15.0)   # ★锚点自适应(原 position=(0,350) 写死)
	rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle._ui_layer.add_child(rew)
	_banner_fade_in(rew, 0.46)
	# 结束操作按钮化: 只留「返回菜单」(用户2026-07-18"匹配里不应该有再战": 再战=reload重打同对手, roguelike流程不该原地重战→删).
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 28)
	_banner_anchor_row(btn_row, 0.575, 24.0)   # ★锚点自适应(原 position=(0,392) 写死)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	battle._ui_layer.add_child(btn_row)
	# ★教学模式: 结算按钮走导演(战斗1打完→商店, 战斗2打完→结束回菜单), 而不是直接返回菜单。
	var _td = battle.get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():
		# ★文字用 _peek_next【只读】—— 用 next_scene_after 会在【建按钮时】就推进 stage,
		#   导致战斗1一结算 stage 就跳到 shop, 玩家还没点。点了才 next_scene_after 真推进。
		#   (2026-07-23 自动跑一遍抓到: 战斗1→MainMenu、收尾没关沙盒, 就是这个副作用。)
		var _peek: String = _td._peek_next("battle")
		var _label: String = "去商店 逛逛 ▶" if _peek.ends_with("Shop.tscn") else ("完成教学 ✓" if _peek.ends_with("MainMenu.tscn") else "继续 ▶")
		btn_row.add_child(battle._make_result_btn(_label, Color("#ffc23c"), Color("#3a1f00"),
			func() -> void: battle.get_tree().change_scene_to_file(_td.next_scene_after("battle"))))
	else:
		btn_row.add_child(battle._make_result_btn("🏠 返回菜单", Color("#5aa0d8"), Color("#04121e"),
			func() -> void: battle.get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	_banner_fade_in(btn_row, 0.60)
	_build_stats_panel()             # #2 战斗统计面板


## 结算横幅的一行: 横向铺满 + 纵向按【屏幕比例】定位(而不是写死像素 y)。
## ★为什么: 原来全是 position=Vector2(0, 316) 这种绝对坐标 + size=Vector2(1280,...),
##   只有正好 1280×720 才对; 手机分辨率一变, 大字/比分/按钮就会偏甚至跑出屏幕。
##   frac = 该行中心在屏幕高度的比例; half_h = 行高的一半(像素)。
func _banner_anchor_row(c: Control, frac: float, half_h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.anchor_top = frac
	c.anchor_bottom = frac
	c.offset_top = -half_h
	c.offset_bottom = half_h

## 结算横幅元素逐个淡入(原来整块瞬间弹出, 没有节奏)
func _banner_fade_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	var tw = battle.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 结算按钮 (再战/返回菜单) — 圆角实色底 + 深字 + hover/pressed 态.
# ══════════════════════════════════════════════════════════════
# 结算统计表 (1:1 回合制 BattleEndScene._stats_table 7 列样式) — 双队并排, 召唤体单列一行
# ══════════════════════════════════════════════════════════════
func _build_stats_panel() -> void:
	# 结算页要含【前面战场】的总结, 不能只有当前这一路(用户2026-07-19): 已结束的路走 battle._st_lane_hist 快照,
	# 当前路直接读活的 battle._units; 三路以上信息量太大 → 做成分页(默认停在「合计」).
	var pages: Array = []            # [{lane, title, left:[row], right:[row]}]
	for snap in battle._st_lane_hist:
		pages.append({"lane": snap["lane"], "title": battle._LANE_CN.get(snap["lane"], str(snap["lane"])),
			"left": snap["left"], "right": snap["right"]})
	var cur = {"lane": "cur", "title": "", "left": [], "right": []}
	for u in battle._units:
		var sd = str(u.get("side", ""))
		if sd == "left" or sd == "right":
			(cur[sd] as Array).append(battle._st_row(u))
	if not ((cur["left"] as Array).is_empty() and (cur["right"] as Array).is_empty()):
		var cl = str(GameState.current_lane) if GameState != null else ""
		cur["title"] = battle._LANE_CN.get(cl, "本场") if not pages.is_empty() else "本场"
		pages.append(cur)
	if pages.is_empty():
		return
	if pages.size() > 1:             # 只有一路就没有「合计」的必要
		pages.append({"lane": "all", "title": "合计",
			"left": battle._st_merge_all(pages, "left"), "right": battle._st_merge_all(pages, "right")})

	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	sb.border_color = Color(0.3, 0.5, 0.7, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title = Label.new()
	title.text = "⚔ 战斗统计"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# 页体: 每页一个 HBox(我方|敌方), 同时只显一个; 外面套 ScrollContainer —— 合计页行数可能超屏底
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body = Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var bodies: Array = []
	for pg in pages:
		var cols = HBoxContainer.new()
		cols.add_theme_constant_override("separation", 28)
		cols.add_child(battle._stats_column("🔵 我方", pg["left"], Color("#7ec8ff")))
		cols.add_child(battle._stats_column("🔴 敌方", pg["right"], Color("#ff9a9a")))
		cols.visible = false
		body.add_child(cols)
		bodies.append(cols)

	# 页签(单路时不显): 点了切页 + 高亮
	var tab_btns: Array = []
	if pages.size() > 1:
		var tabs = HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 6)
		tabs.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(tabs)
		for i in range(pages.size()):
			var b = Button.new()
			b.text = str(pages[i]["title"])
			b.add_theme_font_size_override("font_size", 14)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var idx = i
			b.pressed.connect(func() -> void: battle._stats_show_page(bodies, tab_btns, idx))
			tabs.add_child(b)
			tab_btns.append(b)
	vb.add_child(scroll)
	battle._stats_show_page(bodies, tab_btns, pages.size() - 1)   # 默认落在最后一页(多路=合计 / 单路=本场)
	battle._ui_layer.add_child(panel)
	panel.position = Vector2(316, 438)
	battle._center_panel_deferred(panel)

func _build_edit_palette() -> void:
	var ids: Array = battle.STATS.keys()
	if not ids.is_empty() and not ids.has(battle._edit_pick_id):
		battle._edit_pick_id = str(ids[0])
	var panel = PanelContainer.new()
	panel.name = "DebugEditPalette"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.13, 0.94)
	sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16; sb.content_margin_right = 16
	sb.content_margin_top = 14; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 52)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	battle._ui_layer.add_child(panel)
	battle._edit_palette = panel

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# 标题栏 + 折叠按钮(用户2026-07-24: 左边大面板要能关) —— 折叠时只留这一行, 释放整个左半场。
	var titlebar = HBoxContainer.new(); titlebar.add_theme_constant_override("separation", 8); vb.add_child(titlebar)
	var title = Label.new()
	title.text = "🛠 调试场"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlebar.add_child(title)
	battle._edit_btn_collapse = battle._debug._edit_mk_btn("⊟ 折叠", func(): battle._debug._edit_toggle_collapse(), 84)
	titlebar.add_child(battle._edit_btn_collapse)
	# 可折叠主体: 后续所有设置行都进 battle._edit_body(把 vb 重指向它)
	# 主体套 ScrollContainer: 内容多(尤其选中单位→Inspector追加行)时不撑出屏外够不到(治与"加装备够不到"同类·2026-07-27)
	var _body_sc = ScrollContainer.new()
	_body_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var _evp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var _em: Vector4 = SafeArea.margins(_evp, 18.0)
	_body_sc.custom_minimum_size = Vector2(0, clampf(_evp.y - _em.y - _em.w - 130.0, 200.0, 640.0))   # 体高上限=可用高−标题/位置留白 → 面板永远在屏内
	vb.add_child(_body_sc)
	battle._edit_body_sc = _body_sc
	battle._edit_body = VBoxContainer.new(); battle._edit_body.add_theme_constant_override("separation", 10); _body_sc.add_child(battle._edit_body)
	vb = battle._edit_body

	# 选龟/选边/小将 → 已移到底部常驻笔刷栏(_build_brush_bar·用户2026-07-24), 这里不再放。
	var row_min = HBoxContainer.new(); row_min.add_theme_constant_override("separation", 8); vb.add_child(row_min)
	battle._edit_btn_energy = battle._debug._edit_mk_btn("满龟能默认:关", func(): battle._debug._edit_toggle_full_energy(), 160)
	row_min.add_child(battle._edit_btn_energy)

	var row_hp = HBoxContainer.new(); row_hp.add_theme_constant_override("separation", 8); vb.add_child(row_hp)
	row_hp.add_child(battle._debug._edit_lbl("假人HP"))
	row_hp.add_child(battle._debug._edit_mk_btn("−", func(): battle._debug._edit_adjust_hp(-100.0), 48))
	battle._edit_lbl_hp = battle._debug._edit_val_lbl(96)
	row_hp.add_child(battle._edit_lbl_hp)
	row_hp.add_child(battle._debug._edit_mk_btn("+", func(): battle._debug._edit_adjust_hp(100.0), 48))
	row_hp.add_child(battle._debug._edit_mk_btn("掉血/不死", func(): battle._debug._edit_toggle_killable(), 130))

	var row_star = HBoxContainer.new(); row_star.add_theme_constant_override("separation", 8); vb.add_child(row_star)
	row_star.add_child(battle._debug._edit_lbl("装备星级"))
	battle._edit_star_btns = []
	for st in [1, 2, 3]:
		var stc: int = st
		var bs = battle._debug._edit_mk_btn("★%d" % stc, func(): battle._debug._edit_set_star(stc), 60)
		battle._edit_star_btns.append(bs)
		row_star.add_child(bs)

	var row_spd = HBoxContainer.new(); row_spd.add_theme_constant_override("separation", 8); vb.add_child(row_spd)
	row_spd.add_child(battle._debug._edit_lbl("倍速"))
	battle._edit_speed_btns = []
	for si in range(battle.EDIT_SPEEDS.size()):
		var sidx: int = si
		var bp = battle._debug._edit_mk_btn("%s×" % battle._fmt_num(float(battle.EDIT_SPEEDS[si])), func(): battle._debug._edit_set_speed(sidx), 60)   # %g Godot不支持→battle._fmt_num(2026-07-26修预存bug)
		battle._edit_speed_btns.append(bp)
		row_spd.add_child(bp)

	var row_ctl = HBoxContainer.new(); row_ctl.add_theme_constant_override("separation", 8); vb.add_child(row_ctl)
	battle._edit_btn_start = battle._debug._edit_mk_btn("▶ 开始", func(): battle._debug._edit_start_battle(), 100)
	row_ctl.add_child(battle._edit_btn_start)
	battle._edit_btn_edit = battle._debug._edit_mk_btn("⏸ 编辑", func(): battle._debug._edit_back_to_edit(), 100)
	battle._edit_btn_edit.disabled = true
	row_ctl.add_child(battle._edit_btn_edit)
	row_ctl.add_child(battle._debug._edit_mk_btn("🔁 再来一把", func(): battle._debug._edit_replay(), 130))

	var row_ctl2 = HBoxContainer.new(); row_ctl2.add_theme_constant_override("separation", 8); vb.add_child(row_ctl2)
	row_ctl2.add_child(battle._debug._edit_mk_btn("清空", func(): battle._debug._edit_clear(), 90))
	row_ctl2.add_child(battle._debug._edit_mk_btn("返回菜单", func(): battle._debug._edit_exit_to_menu(), 120))

	battle._edit_lbl_status = Label.new()
	battle._edit_lbl_status.add_theme_font_size_override("font_size", 15)
	battle._edit_lbl_status.add_theme_color_override("font_color", Color("#ffe9a8"))
	vb.add_child(battle._edit_lbl_status)
	var help = Label.new()
	help.text = "点空地=摆(龟/小将) · 点单位=选中配装 · 拖拽=挪位 · 满龟能开→秒放技看效果"
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color("#7a8a96"))
	vb.add_child(help)

	battle._edit_equip_box = VBoxContainer.new()
	battle._edit_equip_box.add_theme_constant_override("separation", 6)
	vb.add_child(battle._edit_equip_box)

	battle._debug._edit_set_speed(battle._edit_speed_idx)
	battle._debug._edit_load_setup()
	battle._debug._edit_refresh_labels()
	battle._debug._edit_refresh_equip_panel()
	battle._debug._edit_apply_collapse()   # 恢复折叠态(跨编辑/开始/再来 重建持久·用户2026-07-24)

func _build_brush_bar() -> void:
	if battle._edit_brush_bar != null and is_instance_valid(battle._edit_brush_bar):
		battle._edit_brush_bar.queue_free()
	battle._edit_brush_cells = []
	var bar = PanelContainer.new()
	bar.name = "DebugBrushBar"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.055, 0.09, 0.95)
	sb.border_color = Color("#ffd93d"); sb.border_width_top = 2
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var _bsb: float = SafeArea.margins(Vector2(battle.get_viewport().get_visible_rect().size), 10.0).w   # 安全区下边距(手机 home 手势条区·用户2026-07-27:「底部怎么滑·横滑撞手势条」)
	bar.offset_bottom = -_bsb          # 整条抬到安全区内 → 横滑不再撞底部 home 手势条
	bar.offset_top = -94.0 - _bsb      # 顶边随之上移
	battle._ui_layer.add_child(bar)
	battle._edit_brush_bar = bar
	var root = VBoxContainer.new(); root.add_theme_constant_override("separation", 3); bar.add_child(root)
	var line = HBoxContainer.new(); line.add_theme_constant_override("separation", 8); root.add_child(line)
	battle._edit_btn_side = battle._debug._edit_mk_btn("左队(友军)", func(): battle._debug._edit_toggle_side(), 116)
	line.add_child(battle._edit_btn_side)
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 64)
	line.add_child(sc)
	var strip = HBoxContainer.new(); strip.add_theme_constant_override("separation", 5); sc.add_child(strip)
	for id in battle.STATS.keys():
		var iid = str(id)
		if iid == "__minion__" or iid == battle.TRAINER_ID: continue
		strip.add_child(battle._debug._edit_brush_cell(iid, battle.AVATAR_DIR + iid + ".png", str(battle._data_by_id.get(iid, {}).get("name", iid))))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:front", "", "浪板"))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:back", "", "火箭"))
	strip.add_child(battle._debug._edit_brush_cell("__minion__:elite", "", "精英"))
	strip.add_child(battle._debug._edit_brush_cell(battle.TRAINER_ID, battle.TRAINER_SPRITE, "大师"))
	var hint = Label.new()
	hint.text = "← 手指横滑挑龟(共28只+小将+大师) →   点一格选笔刷 → 点战场连点连摆 · 点已摆的龟→出配置面板"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#ffe9a8"))
	root.add_child(hint)
	battle._debug._edit_refresh_brush_highlight()

# ----------------------------------------------------------------------------
#  1) 左右队头像框栏
# ----------------------------------------------------------------------------
func _build_team_panels() -> void:
	if battle._ui_layer == null:
		return
	# 旧栏清掉 (重生/重开安全)
	if battle._team_panel_left != null and is_instance_valid(battle._team_panel_left):
		battle._team_panel_left.queue_free()
	if battle._team_panel_right != null and is_instance_valid(battle._team_panel_right):
		battle._team_panel_right.queue_free()
	battle._team_panel_left = battle._info_sys._make_team_column("left")
	battle._team_panel_right = battle._info_sys._make_team_column("right")
	battle._ui_layer.add_child(battle._team_panel_left)
	battle._ui_layer.add_child(battle._team_panel_right)

func _make_team_frame(u: Dictionary) -> Control:
	var side = str(u.get("side", "left"))
	var accent = Color("#3fa9ff") if side == "left" else Color("#ff5a5a")
	var frame = PanelContainer.new()
	frame.name = "Frame_" + str(u.get("id", ""))
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#12161f")
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(124, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击 (别穿到战场)
	frame.tooltip_text = "%s · 点击看详情" % str(u.get("name", u.get("id", "")))

	var main_col = VBoxContainer.new()   # 头像行 + 装备格行
	main_col.add_theme_constant_override("separation", 5)
	main_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(main_col)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_col.add_child(row)

	# 头像 (44x44)
	var portrait = TextureRect.new()
	portrait.texture = battle._unit_portrait_texture(u)
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	# 右侧: 名 + 等级牌 (一行) + 迷你血条
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(top)
	var lv_badge = battle._make_mini_lv_badge(int(u.get("level", 1)))
	if lv_badge != null:
		top.add_child(lv_badge)
	u["panel_lv_badge"] = lv_badge
	var nm = Label.new()
	nm.text = str(u.get("name", u.get("id", "")))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nm)

	# 迷你血条 (ColorRect bg + fill)
	var hp_bg = ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.custom_minimum_size = Vector2(battle._PANEL_HP_W, 5)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_bg)
	var hp_fill = ColorRect.new()
	hp_fill.color = Color("#4ade80")
	hp_fill.position = Vector2(0, 0)
	hp_fill.size = Vector2(battle._PANEL_HP_W, 5)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(hp_fill)
	# 头像下方: 至多4个装备格 (图标 + 充能类装备的充能进度条). 常建空行+存引用 → 招财进宝运行时抽装备可刷新(battle._refresh_panel_equips)
	var eq_row = HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 4)
	eq_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eq_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_col.add_child(eq_row)
	u["panel_eq_row"] = eq_row
	battle._refresh_panel_equips(u)

	# 整框点击 → 详情面板
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_unit_info_panel(u))

	# 引用挂在单位字典上, 供 battle._info_sys._update_team_panels 每帧刷
	u["panel_frame"] = frame
	u["panel_hp_fill"] = hp_fill
	u["panel_stylebox"] = sb
	return frame

# 重建头像下装备格 (从 u["equips"] 取, 至多4格). spawn时建 + 招财进宝运行时抽/升装备后调 → 图标即时显进左右信息框(用户2026-07-12).
func _close_info_panel() -> void:
	if battle._info_panel != null and is_instance_valid(battle._info_panel):
		var _bg = battle._info_panel.get_parent()   # 老版本有全屏灰底backdrop→连父free; 新侧边版面板直接挂_ui_layer(无backdrop)→只free面板
		(_bg if _bg != null and _bg is ColorRect else battle._info_panel).queue_free()
	battle._info_panel = null
	battle._selected_unit = null

func _show_unit_info_panel(u: Dictionary) -> void:
	# 引导第 2 步等的就是"玩家点开了详情面板"这个动作(advanceOn: info_panel_opened)。
	if battle._tutorial != null and is_instance_valid(battle._tutorial):
		battle._tutorial.notify("info_panel_opened")
	_close_info_panel()
	battle._selected_unit = u
	if battle._ui_layer == null:
		return
	var id = str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	var is_left = str(u.get("side", "")) == "left"
	var side_col = Color("#4ade80") if is_left else Color("#ff6b6b")

	# ── 侧边面板(右锚·不遮全场·无backdrop·用户2026-07-18「侧边不遮战场」) ──
	var PW = 400.0
	var panel = PanelContainer.new()
	panel.name = "InfoPanel"
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.086, 0.13, 0.96)
	psb.set_border_width_all(2); psb.border_color = Color("#ffd93d")   # 金框(与主菜单一致)
	psb.set_corner_radius_all(14)
	psb.content_margin_left = 16; psb.content_margin_right = 16
	psb.content_margin_top = 14; psb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", psb)
	panel.anchor_left = 1.0; panel.anchor_right = 1.0; panel.anchor_top = 0.0; panel.anchor_bottom = 1.0
	panel.offset_left = -(PW + 16.0); panel.offset_right = -16.0
	panel.offset_top = 56.0; panel.offset_bottom = -16.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉面板内点击(不穿到战场·点空白才关)
	battle._ui_layer.add_child(panel)
	battle._info_panel = panel

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# 头部: 头像 + 名 + 阵营/稀有度/Lv + ✖
	var head = HBoxContainer.new(); head.add_theme_constant_override("separation", 10); vb.add_child(head)
	var big = TextureRect.new()
	big.texture = battle._unit_portrait_texture(u)
	big.custom_minimum_size = Vector2(64, 64)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(big)
	var hi = VBoxContainer.new(); hi.add_theme_constant_override("separation", 2)
	hi.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hi)
	var nm = Label.new(); nm.text = str(u.get("name", id)); nm.add_theme_font_size_override("font_size", 21)
	var rar = str(pet.get("rarity", u.get("rarity", "C")))
	nm.add_theme_color_override("font_color", battle._pet_rarity_color(rar)); hi.add_child(nm)
	var sub = Label.new()
	sub.text = "%s · %s · Lv %d" % ["友军" if is_left else "敌方", rar, int(u.get("level", 1))]
	sub.add_theme_font_size_override("font_size", 13); sub.add_theme_color_override("font_color", side_col); hi.add_child(sub)
	# ★不再放 ✖ 按钮(用户 2026-07-21:「点空白处就直接退出信息面板, 不要那个×」)。
	#   关闭走两条: ①点面板外空白(_unhandled_input) ②ESC。面板本身 MOUSE_FILTER_STOP,
	#   所以点在面板【内】不会误关。

	# HP 条(阵营色)
	var _hpref: Array = battle._info_sys._info_bar(vb, float(u.get("hp", 0.0)), float(u.get("maxHp", 1.0)), side_col, "HP  %d / %d" % [int(u.get("hp", 0)), int(u.get("maxHp", 0))])
	battle._info_hp_bar = _hpref[0]; battle._info_hp_lbl = _hpref[1]
	# 龟能条(有主动技才显): 主技充能% = 1 − 剩余冷却/满冷却
	var acts: Array = u.get("active_skills", [])
	if not battle._is_passive_pick(u) and acts.size() > 0:
		var st0 = str(acts[0])
		var mxcd = battle._skill_cd(u, st0)
		var cd = float((u.get("skill_cd", {}) as Dictionary).get(st0, mxcd))
		var rdy = CombatMath.cooldown_ready(cd, mxcd)
		var _enref: Array = battle._info_sys._info_bar(vb, rdy, 1.0, Color("#ffce4d"), "龟能  %d%%" % int(rdy * 100.0))
		battle._info_en_bar = _enref[0]; battle._info_en_lbl = _enref[1]

	battle._add_panel_sep(vb)

	# 属性格 (2列·图标)
	var grid = GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", 5)
	vb.add_child(grid)
	# ★属性行走 battle._info_sys._info_stat_rows() 单一事实源(建面板与每帧刷新同源, 不会漂移)。
	#   图标: 8项有真图标, 其余留空占位 —— 本项目已「全去emoji(根治绿块+跨平台一致)」。
	battle._info_stat_labels.clear()
	for row in battle._info_sys._info_stat_rows(u):
		var lb = battle._info_sys._info_stat_cell(grid, "", str(row[1]), row[2], str(row[0]))
		battle._info_stat_labels.append(lb)
	battle._info_stat_grid = grid

	battle._add_panel_sep(vb)

	# 当前状态 chips
	battle._add_section_title(vb, "当前状态")
	# ★状态 chips 也要实时(用户「面板里所有的数值需要实时变化」) —— 护盾/灼烧/眩晕
	#   在战斗中变得最频繁, 原来却是开面板那一刻建一次就再也不动。
	#   chips 【条目数会变】(状态来了又走), 只能整块重建, 所以单独存容器 + 节流重建。
	battle._info_status_box = VBoxContainer.new()
	battle._info_status_box.add_theme_constant_override("separation", 4)
	vb.add_child(battle._info_status_box)
	battle._info_sys._info_status_chips(battle._info_status_box, u)
	battle._info_status_sig = battle._status_signature(u)

	# 被动
	var passive: Dictionary = u.get("passive", {})
	if passive is Dictionary and not (passive as Dictionary).is_empty():
		battle._add_panel_sep(vb)
		battle._add_section_title(vb, "被动 · " + str(passive.get("name", "")))
		# ★走模板渲染: 把 {N:0.7*ATK} 这类占位符按【本龟当前属性】算成真数字
		# ★统一口径: 原来这里【写死取 desc(详细)】而技能段写死取 brief(缩略),
		#   同一个面板里两种口径 —— 现在都听 battle._skill_detail() 的。
		var _ptpl = battle.SkillText.text_of(passive, battle._skill_detail())
		var pdesc = battle._render._render_skill_text(_ptpl, u, passive)
		if pdesc != "":
			battle._info_passive_lbl = battle._add_body_text(vb, pdesc)
			battle._info_passive_tpl = _ptpl

	# 宝箱龟专属: 财宝值进度 + 已开出的战利品(用户2026-07-19"信息面板得显示当前累计的财宝值/当前抽取的装备和图标/专属装备的描述")
	if battle._is_chest_turtle(u):
		battle._add_panel_sep(vb)
		battle._info_sys._info_chest_section(vb, u)

	# 技能
	var skills = battle._info_sys._panel_skill_entries(u)
	if not skills.is_empty():
		battle._add_panel_sep(vb)
		battle._add_section_title(vb, "技能")
		# ★简明/详细开关(用户需求1 两级描述)。放在技能段上方 —— 它同时管被动段与技能段,
		#   但被动段在上面已经画完了, 放这里是为了【靠近文字最多的地方】, 手够得着。
		battle._add_detail_toggle(vb, u)
		battle._info_skill_lbls.clear()
		for sk in skills:
			battle._add_section_title(vb, "  " + str(sk["name"]), Color("#9fd0ff"), 14)
			if str(sk["desc"]) != "":
				var slb = battle._add_body_text(vb, str(sk["desc"]))
				# 存"模板原文+Label+技能字典" → 每帧按当前属性重渲染伤害数值
				battle._info_skill_lbls.append({"lbl": slb, "tpl": str(sk.get("tpl", "")), "sk": sk.get("sk", {})})

	# 装备 —— ★也纳入实时(用户「面板里所有的数值需要实时变化」, 我不该给它开例外)。
	#   战斗中装备会变: 财神招财临时升星、宝箱龟开出新装备。条目数/星级都会变 → 整块重建, 签名节流。
	battle._add_panel_sep(vb)
	var equips: Array = u.get("equips", [])
	battle._info_equip_box = VBoxContainer.new()
	battle._info_equip_box.add_theme_constant_override("separation", 4)
	vb.add_child(battle._info_equip_box)
	battle._fill_equip_section(battle._info_equip_box, u)
	battle._info_equip_sig = battle._equip_signature(u)

	battle._info_sys._info_passthrough(vb)   # 面板内非按钮控件透传触摸→ScrollContainer可滑(手机·用户2026-07-18「列表滑动考虑手机端」)

	# 从右滑入
	panel.offset_left += PW + 40.0; panel.offset_right += PW + 40.0
	var tw = battle._reg_tween()
	tw.tween_property(panel, "offset_left", -(PW + 16.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panel, "offset_right", -16.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 是不是宝箱龟(藏宝图被动会往 chest_treasures 里塞东西; 用 id 判定最稳)
