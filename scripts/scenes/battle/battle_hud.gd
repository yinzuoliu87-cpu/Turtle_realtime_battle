class_name BattleHud
extends RefCounted
## 战斗HUD/面板构建与显示: UI层/暂停/日志/统计/编辑笔刷/队伍头像框/胜负横幅/点龟详情面板/触控盘·纯UI
## 类内名不变;外部名加 battle.

# ★结算页「前往商店」(2026-08-03)。抽成常量【不是为了复用】——是为了让门禁能验:
#   按钮回调是个 lambda, 从外面看不见它跳去哪; 路径写错(改名/挪目录)时按钮照样长出来,
#   点下去才发现是空的。常量让门禁能 ResourceLoader.exists() 真去查这个场景在不在。
const SHOP_SCENE := "res://scenes/Shop.tscn"
const SHOP_BTN_TEXT := "前往商店"


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
	# ★左上角那行开发期标题「2.5D 实时战斗 · 3v3(左队 vs 右队)」已删(用户 2026-07-30)。
	#   它是开发期自证用的, 正式对局里没信息量, 而且【正是它把 PK 条限死在 600 宽】——
	#   条要避开它才能不重叠。删掉后条才有空间加宽到格斗游戏那个比例。
	_build_pk_bar()   # 顶部双方总血量 PK 条 (用户2026-07-30 需求1)
	if battle._is_dual_lane_mode():   # 双路 HUD: 当前路 + 双方蛋血
		battle._dl_hud = Label.new()
		battle._dl_hud.add_theme_font_size_override("font_size", 17)
		battle._dl_hud.add_theme_color_override("font_color", Color("#ffe08a"))
		# ★y 44→64: PK 主条占 16..42, 龟蛋副条占 46..60(第三版副条加高到 14 塞蛋图标)
		# ★宽度 700 居中于【真实视口】: 原来写死 x=290(=(1280-700)/2), 手机 1560 宽时左偏 140
		var _vw0: float = float(battle.get_viewport().get_visible_rect().size.x)
		battle._dl_hud.size = Vector2(700, 24)
		battle._dl_hud.position = Vector2(_vw0 * 0.5 - 350.0, 70)
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
	if battle.DEBUG_EDIT:                              # 调试场保留 📜(我自己排查要用·U8: 开发工具不属"局内")
		var log_btn = Button.new()
		log_btn.text = "📜"
		log_btn.size = Vector2(52, 38)
		# ★贴【真实视口】右缘(原写死 1088 = 1280-192, 宽屏上会浮在屏幕中间)
		log_btn.position = Vector2(float(battle.get_viewport().get_visible_rect().size.x) - 192.0, 12)
		log_btn.add_theme_font_size_override("font_size", 20)
		battle._style_hud_btn(log_btn)
		log_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		log_btn.pressed.connect(battle._toggle_log)
		battle._ui_layer.add_child(log_btn)

	# ★★2026-07-31 修「手机上投降键重合在血条上」(用户报)。
	#   原来两个键写死 x=1148 / 1208 —— 而 project.godot 是 stretch/aspect="expand":
	#   【视口尺寸随窗口宽高比变】, 而 PK 条是【顶部居中·宽 960】。
	#   ★2026-08-01 修正这条注释里的模型: 原文写"高固定 720, 宽 = 720×比例" —— 只对了一半。
	#     expand 锁的是【受限的那一轴】: 比 16:9 宽才锁高 720 让宽变大(手机横屏是这种);
	#     比 16:9 窄则【锁宽 1280 让高变大】(iPad 4:3 → 1280×960, 折叠屏 1:1 → 1280×1280)。
	#     所以视口宽【永远 ≥1280】, 下面那句"iPad 4:3 视口只有 960 宽"也是同一个误解 ——
	#     实测(tests/_probe_ui_layout.gd)是 1280×960。按错模型推理会把适配方向做反。
	#   实算重叠量:
	#       16:9  视口 1280 → PK 右缘 1120, 键左缘 1148 → 不重叠(所以我在 PC 上看不出来)
	#     19.5:9 视口 1560 → PK 右缘 1260, 键左缘 1148 → ★重叠 112 px
	#       20:9 视口 1600 → PK 右缘 1280, 键左缘 1148 → ★重叠 132 px
	#   → 改成【按右边缘 + 安全区反算】, 与法术圆盘同一套做法(SafeArea.margins)。
	var _pos: Dictionary = _topright_positions()

	_stats_btn = _mk_icon_btn(ICON_STATS, _pos["stats"], "伤害统计")
	_stats_btn.pressed.connect(battle._on_dmg_stats_toggle)
	battle._ui_layer.add_child(_stats_btn)

	# 🏳 投降: 最右 —— 肌肉记忆上"最右是退出类操作"。
	battle._surrender_btn = _mk_icon_btn(ICON_SURRENDER, _pos["surrender"], "投降认输")
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


## ── PK 条状态(2026-07-30 从主战斗文件搬进来) ──
## ★为什么住这儿: 这些字段【只有本文件用】。原本放在主场景纯粹是我图省事,
##   而主文件有 arch_budget 行数警戒线 —— 加这 20 多行直接把它顶红了(8616>8600)。
##   规则是"先拆出去"不是抬台账, 而这里本来就是它们该在的地方。
var _pk_bar: Control = null
var _stats_btn: Control = null      # 右上"伤害统计"键 —— 存起来是为了 on_viewport_resized 能重摆它
var _pk_fill_l: Control = null             # 我方填充(绿)。★类型是 Control 不是 ColorRect ——
                                           #   主条现在是 TextureRect(竖向渐变·体积感做进斜切四边形里), 副条仍是 ColorRect
var _pk_fill_r: Control = null             # 敌方填充(紫)。同上: 主条 TextureRect / 副条 ColorRect
var _pk_lab_l: Label = null
var _pk_lab_r: Label = null
var _pk_base_l: float = 0.0                # 当前分母(=该侧计数单位 maxHp 之和·含已死)。留给门禁/调试看
var _pk_base_r: float = 0.0
var _pk_w_cur: float = PK_W                # 本次建条时的实际【总宽】(窄屏会小于 PK_W)
## 本次建条时的实际【单段宽】。★★2026-08-01: 原来条内 11 处全在用常量 PK_SEG/PK_W 摆位,
## 而外框已经会随窄屏收缩(见 _build_pk_bar 的 _w) —— 于是【框缩了、内容没缩】:
##   iPad 10 (4:3·视口 960) 外框 680 / 内容 948 → 溢出 268px;  折叠屏 1:1 (720) 溢出 508px。
##   16:9 及更宽的手机恰好都 ≥1280 ⇒ 外框正好等于 PK_W, 所以这个 bug 一直没暴露。
## 现在条内一律用这两个运行时值, 常量只当"上限"。
var _pk_seg_cur: float = PK_SEG
var _pk_lane: String = ""                  # 上一次采样时的路 id —— 换路才把两条拉回 100%(原来按"计数单位数变了"判, 会被中途增减单位误触发)
## (已删 _pk_count —— 原来靠"计数单位数变了"判换路, 会被【任何中途增减计数单位】误触发,
##  表现就是两条莫名满格。改用 _pk_lane 按路 id 判, 见 _pk_refresh。)
var _pk_acc: float = 0.0                   # 采样累加器(0.1s 扫一次 _units, 别每帧扫)
var _pk_target_l: float = 1.0              # 左侧【占自己开场基线】的比例 → 决定蓝段长度
var _pk_target_r: float = 1.0              # 右侧同理 → 红段长度
var _pk_shown_l: float = 1.0               # 逐帧向 target 平滑(群伤瞬间不抽搐)
var _pk_shown_r: float = 1.0
var _pk_trail_l: ColorRect = null          # damage trail 残影: 掉血时旧位置留一段亮色再慢慢收
var _pk_trail_r: ColorRect = null
var _pk_prev_shown_l: float = 1.0          # 上一帧的填充值 —— 用来判"这一帧回血了"(见 PK_GAIN_HOLD)
var _pk_prev_shown_r: float = 1.0
var _pk_gain_l: Control = null             # 回血带节点(画在填充【上面】的独立窄带)
var _pk_gain_r: Control = null
var _pk_gain_vl: float = 1.0               # 回血【低水位】: 上涨时滞后于填充, 两者之差 = 高亮的那一段
var _pk_gain_vr: float = 1.0
var _pk_gain_hold_l: float = 0.0
var _pk_gain_hold_r: float = 0.0
var _pk_trail_vl: float = 1.0
var _pk_trail_vr: float = 1.0
var _pk_egg_row: Control = null            # 副条整行容器(无蛋时隐藏整行)
var _pk_egg_icons: Array = []              # 两端的蛋图标(围栏未破时跟着压暗)
var _pk_egg_l: ColorRect = null            # 副条: 龟蛋 PK(取代原来那行"我方蛋N vs 敌方蛋N"文字)
var _pk_egg_r: ColorRect = null
var _pk_egg_tl: float = 1.0
var _pk_egg_tr: float = 1.0
var _pk_egg_sl: float = 1.0
var _pk_egg_sr: float = 1.0
var _pk_tag_l: PanelContainer = null       # 读数标签底板(百分比+绝对值合成一组)
var _pk_tag_r: PanelContainer = null
var _pk_lab_l2: Label = null               # 绝对血量小字(百分比是主读数)
var _pk_lab_r2: Label = null
var _pk_vs: Control = null                 # 中间 VS 徽标(取代第一版那个会被读错的相对百分比)
var _pk_vs_em: TextureRect = null          # 中央 VS 徽章(像素画·取代原来那个圆角方框)
var _pk_vs_glow: TextureRect = null        # 徽章背后的染色光晕(优势方染色搬到这儿)
var _pk_phase: float = 0.0                 # VS 呼吸相位
var _pk_hit_l: float = 0.0                 # 受伤脉冲(0..1, 按 PK_HIT_DECAY 衰减)
var _pk_hit_r: float = 0.0


# ════════════════════════════════════════════════════════════════════════════
#  顶部双方总血量 PK 条 (用户 2026-07-30 需求1 · 方案书 docs/plans/20260730b-*.md)
#
#  「对局内的顶部左右新加一个双方血条的pk，表示双方总血量实时变化」
#
#  ★2026-07-30 第二版(用户逐条审核后重做)。第一版的问题与修法:
#
#  【① 真 bug: 龟蛋一直被算进去了】
#     排除条件写的是 u.get("egg") —— 而单位字典上【没有这个键】, 蛋带的是 _isEgg
#     (battle_spawn.gd:439 写的 u["_isEgg"] = true)。所以"不含龟蛋"根本没生效。
#     后果不只是口径错: 蛋有围栏 +200 双抗、早期几乎不掉血, 占了条里 3300/5900≈56%
#     的【不动的血】—— 条看着迟钝就是这么来的。已改用 _isEgg。
#
#  【② 中间那个百分比会被【读错】】
#     它是 我方/(我方+敌方) 的相对占比 → 开场必然是 50%,
#     用户第一反应就是「为啥一开始血量百分比不都是满的」。
#     语义和"血量百分比"完全不是一回事。用户拍板:「不要，你就弄vs的特效不行吗」
#     → 中间不放任何数字, 改成 VS 徽标 + 特效(优势方染色 + 受伤脉冲 + 呼吸)。
#
#  【③ "看着像从中心开始掉血"】
#     用户:「那不是在中心开始掉血吗，别的游戏咋做的」。
#     格斗游戏(街霸/拳皇)确实是"各自从【内端】往自己那侧退", 但它画的是
#     【两条明显分开、各有边框】的条, 中间隔开一段。我第一版做成了
#     【一条连续长条中间开缝】, 所以读起来像"这条从中间断了"。
#     → 拆成左右两段【各自带边框】+ 中间固定 VS 槽。满血时两段各自顶满自己的框,
#       掉血时该侧从内端往外退, 露出【自己框内】的暗槽 —— 语义就清楚了。
#
#  【④ 缝会透出背景】第一版中间是"空", 沉船/鱼/气泡从缝里穿过去比数字还显眼。
#     → 每段自己有【不透明暗底】, 空掉的部分是槽不是窗。
#
#  【⑤ 掉血没有任何反馈】掉 800 和掉 80 在条上只有位置差别。
#     → 加 damage trail: 掉血时旧位置留一段亮色残影, 再慢速追上来。
#       ★这不是我自造的风格 —— 本项目【单位血条 HpBar 组件本来就有】"受击红trail+白闪",
#       顶部这条没有反而是风格不统一。
#
#  【⑥ 和「我方蛋 N vs 敌方蛋 N」那行撞车】上下两条都是"双方对比", 没有标签区分。
#     用户拍板:「你就下面加个副血条表示龟蛋的」
#     → 蛋改成主条下方一条【细副条】(同样左右分段), dl_hud 文字里的蛋血数字撤掉,
#       只留路名 + 破蛋窗口计时 + 决胜档位。
#
#  ★计入口径(用户逐字「小将和龟统领的」): 主条 = 龟统领 + 小将; 不含龟蛋(有专属副条)、
#    不含训龟大师(500血/1攻/站着不动=噪声)、不含召唤体(与 _check_over 胜负判定同口径)。
#
#  ★每侧按【自己的开场基线】归一化, 每路重算(_t 跨路累加·CLAUDE.md §3.4)。
#  ★不在伤害路径里记账, 改为每 0.1s 扫 _units 求和 → 天然免疫"漏改一条伤害路径"
#    (两条独立路径 _apply_damage / _apply_damage_from·CLAUDE.md §3.3)和
#    "护盾/回血/复活没走伤害钩"两类漏记。
# ════════════════════════════════════════════════════════════════════════════

## ★尺寸参照格斗游戏(街霸/拳皇/Guilty Gear —— 同样是 1v1 双方总量对撞, 最贴这个场景):
##   它们的血条【几乎横跨整屏】(约占屏宽 85~90%)、厚度约占屏高 5~6%。
##   第一版 600/1280 = 47% 宽、26/720 = 3.6% 厚 —— 太小气, 撑不起"主读数"的地位。
##   现在 960/1280 = 75% 宽(右上两个按钮在 1148.., 左右对称留白后到 1120)、32/720 = 4.4% 厚。
const PK_SEG := 440.0        # 单段宽(左/右各一段)
const PK_VS := 68.0          # 中间 VS 槽宽。★80 → 68: 徽章本身会【破框】(比槽宽/条高都大),
                             #   槽只需要给它一个"断口", 留太宽反而像两条中间空了一段。
const PK_W := PK_SEG * 2.0 + PK_VS      # 总宽上限 948(★注释原写"600"是陈的; 窄屏实际宽见 _pk_w_cur)
const PK_H := 32.0           # 主条高
const PK_EGG_H := 15.0       # 副条(龟蛋)高。★要塞得下两端的蛋图标(9×12 太小看不出是蛋)
const PK_EGG_GAP := 4.0      # 主条与副条间距
const PK_Y := 16.0           # 主条顶。占 16..42; 副条 46..55; 双路 HUD 文字下移到 60
const PK_SAMPLE := 0.1       # 扫 _units 的采样间隔(秒)。别每帧扫: 主文件热路径预算 <0.2%
const PK_SMOOTH := 6.0       # 填充平滑速率
const PK_TRAIL_SMOOTH := 2.2 # 残影追赶速率(慢于填充 → 才看得出"刚掉了这一段")。
                             # ★★不要再加"停顿"了: 2026-07-31 试过"掉血后原地停 0.45 秒再收",
                             #   用户看实机后【否掉】——「掉血特效停0.45秒的这个不好, 不如之前的渐退」。
                             #   停顿的观感是一顿一顿的, 不如慢速渐退连贯。这是看过实机的结论, 不是没想到。
                             # ★1.6 太慢: 残影常态很宽, 看起来像"第三种颜色的段"而不是"刚掉的"
const PK_HIT_DECAY := 2.2    # 受伤脉冲衰减速率
const PK_LOW := 0.25         # 低血量阈值: 低于它开始警示闪烁(血条的标准语言)
const PK_LOW_HZ := 3.2       # 警示闪烁频率
const PK_SLANT := 10.0       # 斜切量(px)。整条切成平行四边形 —— 格斗游戏(尤其 Guilty Gear)
                             # 的做法, 给静止的横条一点速度感/对抗感。
## 残影(damage trail)色。★暗砖红, 不是暖白 ——
##   暖白【太亮】: 血量低时残影比血条主体还显眼(连拍 6 帧实拍看出来的)。
##   暗砖红三个好处: ①语义准("刚失去的血"就该是伤口色, 且与本作"红=伤害数字"一致)
##   ②亮度低于填充 → 不抢戏 ③在绿上是互补色、在紫上有明度差, 两种底色都分得开。
##   参照: 街霸的可恢复伤害用黄、怪猎/黑魂用橙红; 白色只是图省事。
## 回血带颜色 = 【该侧本色的提亮版】(用户 2026-07-31:「我方回血用绿色, 敌方回血你得适配个颜色」)。
## ★不写死一个色: 第一版两边都用薄荷绿 —— 我方(绿)那侧还说得过去, 敌方(紫)那侧就是
##   一条绿带糊在紫条上, 既不像"敌方在回血"也和整条配色打架。
##   按本色提亮: 语义天然对(这一侧涨的血)、两边自动适配、以后改队色不用再来改这儿。
## 提亮 0.55 实测: 我方 (74,222,128)→(174,240,198) 亮度差 49; 敌方 (168,85,247)→(216,179,251) 差 71。
const PK_GAIN_LIGHTEN := 0.55
# (原 PK_GAIN_COL 写死的薄荷绿已删 —— 改成按队色提亮, 见 PK_GAIN_LIGHTEN)
                                        #   改前只处理【掉血】: 残影那行 maxf(_pk_shown, …) 把上升
                                        #   那一侧整个吃掉了, 于是治疗/复活/临时血量在 PK 条上【一点反馈都没有】,
                                        #   一大口奶只是让条悄悄变长。这里做残影的镜像: 涨上去的那一段
                                        #   先用薄荷绿高亮 PK_GAIN_HOLD 秒, 再被本色追平。
                                        #   薄荷绿在【绿方和紫方】上都读得出, 且是治疗的通用色。
const PK_GAIN_SMOOTH := 2.4  # 回血带被本色追平的速率(略快于残影 —— 亏血比回血更值得盯)
const PK_GAIN_HOLD := 0.40   # 回血带原地停顿多久才开始被追平。
                             # ★掉血那边的停顿已被用户否掉(见 PK_TRAIL_SMOOTH), 这边【暂时保留】——
                             #   用户只点名了"掉血特效"。回血是瞬间事件(一口奶), 不像掉血那样连绵,
                             #   停顿在这儿更像"闪一下"而不是"卡一下"。要是看着也别扭就一并删掉。
const PK_TRAIL_COL := Color("#b04141")   # ★#8b2f2f 太暗, 压在绿/紫填充边上几乎看不出;
                                        #   提亮到 #b04141 仍是"旧伤"的暗红, 但读得出来了
## 右上按钮区宽度(投降+统计+间距+安全区) —— PK 条要给它让出这么多, 否则窄屏会盖住。
const PK_BTN_ZONE := 140.0
const PK_MIN_W := 420.0      # 条最窄也不小于这个(再窄就读不出双方血量了)

const PK_VS_EMBLEM := "res://assets/sprites/ui/pk-vs-emblem.png"   # 中央 VS 徽章(全新生成)
## 顶栏按钮图标(全新生成·2026-07-30)。★原来是系统 emoji 字符("📊"/"🏳") ——
##   用户问「图标有新弄美术吗」时才对上号: 在像素风游戏里塞两个彩色系统 emoji,
##   字形还随系统字体变, 风格本来就是脱节的。
const ICON_STATS := "res://assets/sprites/ui/hud-stats.png"
const ICON_SURRENDER := "res://assets/sprites/ui/hud-surrender.png"
## ★配色: 我方【绿】/ 敌方【紫】, 不用全项目的"我方蓝/敌方红"(用户 2026-07-30 拍板「只换 PK 条」)。
## 理由(用户先看出来的): 战场背景是【深蓝海底】, 蓝条打在深蓝上对比度天然差 ——
##   实拍里蓝段边框与背景的区分明显不如红段。绿/紫在这个背景上都不撞。
##   顺带解掉一个混淆: 红原本【既是敌方色又是伤害数字色】(#ff4444 物理 / #ff5a5a 装备伤害)。
## ★已知代价(我提出、用户接受): 侧边头像框/单位脚下队色环/召唤物归属色仍是蓝/红,
##   所以"我方"在顶部是绿、在侧边是蓝 —— 敌我识别成了两套编码。要统一得全局换 4 处。
## 绿=生命 这层语义不算冲突: 这条本来就是血条, 单位血条也是绿的。
const PK_BLUE := Color("#4ade80")   # 我方(绿)
const PK_RED := Color("#a855f7")    # 敌方(紫)·比魔法伤害紫字 #c86bff 深一档以作区分
## 副条=蛋壳色。★用【偏暖偏黄】的 #f5d29a 而不是低饱和的 #f2e2c4:
##   围栏未破时要把它压暗一档, 而低饱和色一压暗就直接塌成灰(实拍验证过两轮),
##   暖黄压暗后仍是暖色, 认得出是蛋壳。★不用队色 —— 用户: 原来和主条同色"像装饰下划线"。
const PK_EGG_COL := Color("#f5d29a")


## 平行四边形遮罩 shader。
##
## ★为什么要 shader 而不是换节点类型: ColorRect/Panel 都是矩形绘制, Godot 的 Control
##   没有 skew; 换 Polygon2D 又要把整棵 Control 树(锚点/布局)改成 Node2D 手算坐标。
##   给 CanvasItem 挂 material + discard 是改动最小且对齐/锚点全保留的做法。
##
## ★上宽下窄地【整体右移】= 真平行四边形(宽度不变), 不是梯形:
##   顶边 x∈[slant, w], 底边 x∈[0, w-slant]。四条边等长, 两侧同角度。
## ★rsize 必须由调用方喂 —— canvas shader 拿不到 Control 的 rect 尺寸,
##   而填充宽度每帧在变, 不喂就会歪(这是这套写法唯一的坑)。
const PK_SLANT_SHADER := """shader_type canvas_item;
uniform vec2 rsize = vec2(100.0, 20.0);
uniform float slant = 10.0;
void fragment() {
	vec2 pp = UV * rsize;
	float off = slant * (1.0 - pp.y / max(rsize.y, 1.0));
	if (pp.x < off || pp.x > rsize.x - (slant - off)) discard;
}"""

static var _pk_slant_shader: Shader = null
func _pk_slant_mat(size: Vector2) -> ShaderMaterial:
	if _pk_slant_shader == null:
		_pk_slant_shader = Shader.new()
		_pk_slant_shader.code = PK_SLANT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _pk_slant_shader
	m.set_shader_parameter("rsize", size)
	m.set_shader_parameter("slant", PK_SLANT)
	return m


## 更新某节点遮罩用的尺寸(填充宽度每帧在变, 不更新斜边角度就会跟着变形)。
func _pk_slant_size(n: CanvasItem, size: Vector2) -> void:
	if n == null or not is_instance_valid(n):
		return
	var m := n.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("rsize", size)


## 顶栏图标按钮: 统一尺寸/样式 + 居中的像素图标。
## ★图标用 TextureRect 子节点而不是 Button.icon —— Button.icon 会跟着主题缩放/加内边距,
##   像素图标被插值成糊; 自己放一个 NEAREST 的 TextureRect 可控且不糊。
## ★缺图会 push_warning + 退回文字, 不静默(同 TRAINER_SPRITE 的规矩)。
func _mk_icon_btn(icon_path: String, pos: Vector2, tip: String) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(52, 38)
	b.tooltip_text = tip
	battle._style_hud_btn(b)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(icon_path):
		var ic := TextureRect.new()
		ic.texture = load(icon_path)
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE      # ★否则被贴图最小尺寸钳住(VS 徽章踩过)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE        # 点击穿到按钮上
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 9; ic.offset_right = -9
		ic.offset_top = 6; ic.offset_bottom = -6
		b.add_child(ic)
	else:
		push_warning("[HUD] 按钮图标缺失: %s → 退回文字" % icon_path)
		b.text = "?"
	return b


## 建 PK 条。★锚点自适应(顶部居中), 不写死 1280×720 ——
##   2026-07-21 结算横幅就是踩了写死绝对坐标, 手机分辨率不同会跑偏出屏(见 _show_banner 注释)。
func _build_pk_bar() -> void:
	var bar := Control.new()
	bar.name = "PkBar"
	bar.anchor_left = 0.5; bar.anchor_right = 0.5
	bar.anchor_top = 0.0; bar.anchor_bottom = 0.0
	# ★宽度【自适应】: 窄比例(iPad 4:3 → 视口只有 960 宽)下 960 的固定宽会占满全屏、
	#   把右上两个键也盖住。给两侧各留出"按钮区"(2×52 + 间距 + 安全区)后再取较小者。
	var _vpw: float = float(battle.get_viewport().get_visible_rect().size.x)
	var _reserve: float = PK_BTN_ZONE * 2.0
	var _w: float = minf(PK_W, maxf(PK_MIN_W, _vpw - _reserve))
	bar.offset_left = -_w * 0.5; bar.offset_right = _w * 0.5
	_pk_w_cur = _w
	_pk_seg_cur = (_w - PK_VS) * 0.5   # VS 槽宽固定, 剩下的两侧平分
	# ★走安全区: iPhone 横屏的刘海/灵动岛就在顶部, 写死 y=16 会被挡。
	#   项目里训龟大师摇杆和调试笔刷条都用了 SafeArea, 这里同办。
	var _top: float = PK_Y + SafeArea.margins(Vector2(battle.get_viewport().get_visible_rect().size), 0.0).y
	bar.offset_top = _top
	bar.offset_bottom = _top + PK_H + PK_EGG_GAP + PK_EGG_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示, 别吃战场点击
	battle._ui_layer.add_child(bar)
	_pk_bar = bar

	# ── 主条: 左右两段, 各自带边框 + 不透明暗底 ──
	var res: Array = _pk_seg(bar, true, 0.0, PK_H, PK_BLUE)
	_pk_fill_l = res[0]; _pk_trail_l = res[1]; _pk_gain_l = res[2]
	res = _pk_seg(bar, false, 0.0, PK_H, PK_RED)
	_pk_fill_r = res[0]; _pk_trail_r = res[1]; _pk_gain_r = res[2]

	# ── 副条: 龟蛋(细), 同样左右分段 ──
	var ey: float = PK_H + PK_EGG_GAP
	# ★副条整行挂在一个容器上 —— 无蛋时整行隐藏(见 _pk_refresh)
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(row)
	_pk_egg_row = row
	res = _pk_seg(row, true, ey, PK_EGG_H, PK_EGG_COL, false)
	_pk_egg_l = res[0]
	res = _pk_seg(row, false, ey, PK_EGG_H, PK_EGG_COL, false)
	_pk_egg_r = res[0]
	_pk_egg_icon(row, ey)      # 副条行标签: 两端各一个蛋图标

	# ── 读数: 百分比 + 绝对血量【合成一组】, 压在一块深色标签底板上 ──
	# ★为什么要底板(用户 2026-07-30 审核后定): 格斗游戏基本【不在血条上放数字】——
	#   街霸/GG 中间只有条, 名字在条外。而这里屏幕两侧已被头像栏占死(x<160 / x>1120),
	#   条外没空间, 只能条内。条内放数字的真问题不是"压在填充上"(白字+黑描边读得清),
	#   而是【低血量时填充退走, 字就孤零零飘在暗槽上】。加底板后它是一块清晰的"标签",
	#   无论压在填充还是暗槽上都成立, 也顺带解掉"字比血条还宽"的观感。
	# ★两个数字原来隔了半条距离, 看起来不像一组 —— 现在贴在一起。
	_pk_tag_l = _pk_mk_tag(bar, true)
	_pk_tag_r = _pk_mk_tag(bar, false)
	_pk_lab_l = _pk_tag_l.get_meta("pct")
	_pk_lab_l2 = _pk_tag_l.get_meta("abs")
	_pk_lab_r = _pk_tag_r.get_meta("pct")
	_pk_lab_r2 = _pk_tag_r.get_meta("abs")

	_pk_build_vs(bar)

	_pk_lane = ""         # 逼下一次 _pk_refresh 当作换路处理(两条回满)
	_pk_refresh()
	_pk_apply()


## 建一段(带边框 + 暗底 + 残影 + 填充)。→ [填充, 残影]
## left=true 时填充贴【外侧左端】往右长(空槽露在靠中间那侧); false 时贴外侧右端往左长。
func _pk_seg(bar: Control, left: bool, y: float, h: float, col: Color, gloss_on: bool = true) -> Array:
	var x0: float = 0.0 if left else (_pk_seg_cur + PK_VS)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2(x0, y)
	frame.size = Vector2(_pk_seg_cur, h)
	var sb := StyleBoxFlat.new()
	# ★真不透明(1.0 不是 0.95): 0.95 仍透 5%, 放大截图里暗槽还能看到背景游过去的鱼。
	#   空掉的部分要是【槽】不是【窗】。
	sb.bg_color = Color(0.05, 0.07, 0.11, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = col.lerp(Color(0.10, 0.13, 0.19), 0.45)
	# ★不要圆角: 斜切端和圆角是两种【互斥】的造型语言, 同时用必然打架 ——
	#   圆角+描边被斜切 shader 一刀切掉角后会留下残留像素(实拍里左端那个"灰三角脏点")。
	#   去掉后斜边成为端部唯一造型, 脏点自然消失, 也更硬朗、更贴格斗游戏那套。
	sb.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", sb)
	frame.material = _pk_slant_mat(Vector2(_pk_seg_cur, h))
	bar.add_child(frame)
	# 残影(damage trail): 压在填充【下面】, 掉血时旧位置留一段亮色再慢慢收
	var trail := ColorRect.new()
	trail.color = PK_TRAIL_COL
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.material = _pk_slant_mat(Vector2(_pk_seg_cur, h))
	bar.add_child(trail)
	# ★★体积感做进【填充本身】的竖向渐变, 不再叠一块白方块。
	#
	#   由来(用户 2026-07-31:「为什么血条上半部分有个白色的长方形？跟现在的切面不合适啊」):
	#   原来是给 fill 加了个白色 ColorRect 子节点盖住上半 46%。而【Godot 里子 CanvasItem
	#   不继承父节点的 ShaderMaterial】—— frame/trail/fill 三层都挂了斜切 shader,
	#   唯独那块高光没有 → 它是整条上唯一一块【直角矩形】, 端部直边就露在斜边外面。
	#
	#   现在: fill 换成 TextureRect + 竖向 GradientTexture2D(上浅下深),
	#   渐变是【同一块四边形的贴图】→ 被同一个斜切 shader 一起切, 永远不可能对不上。
	#   ★副条(gloss_on=false)仍用纯色: 13px 的细条上渐变看不出来, 平涂更干净。
	var fill: Control
	if gloss_on:
		var tr2 := TextureRect.new()
		tr2.texture = _pk_grad_tex(col)
		tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE     # 忽略贴图原尺寸, 完全按 size 拉伸
		tr2.stretch_mode = TextureRect.STRETCH_SCALE
		fill = tr2
	else:
		var cr := ColorRect.new()
		cr.color = col
		fill = cr
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.material = _pk_slant_mat(Vector2(_pk_seg_cur, h))
	bar.add_child(fill)
	# 回血带(heal gain): 画在填充【上面】的一条独立窄带, 只覆盖 [低水位, 当前值] 这一段。
	# ★第一版是"填充只画到低水位, 让底下的绿露出来" —— 结果【填充节点的宽度不再等于显示血量】,
	#   门禁①(量 fill.size.x 判"都剩10%时更短")当场被测糊: 满血 433.2 vs 都剩10% 433.2。
	#   条的长度是 HUD 最基本的语义, 不该为了一个特效被偷换。改成盖在上面的独立带,
	#   fill 永远等于当前值, 谁读它都不会被骗。
	var gain := ColorRect.new()
	gain.color = col.lightened(PK_GAIN_LIGHTEN)   # 见 PK_GAIN_LIGHTEN: 按本侧队色提亮
	gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gain.material = _pk_slant_mat(Vector2(_pk_seg_cur, h))
	bar.add_child(gain)
	return [fill, trail, gain]


## 填充用的竖向渐变: 上浅下深, 幅度小(只做体积感, 不改变本色)。
## ★上端提亮 0.22、下端压暗 0.10 —— 这个幅度约等于原来那块 alpha 0.16 白方块的观感,
##   但它是【贴图】, 会跟着斜切 shader 一起被切。
func _pk_grad_tex(col: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.22))
	g.set_color(1, col.darkened(0.10))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 64
	t.fill_from = Vector2(0.0, 0.0)      # 竖向: 上 → 下
	t.fill_to = Vector2(0.0, 1.0)
	return t


## 副条行标签: 两端各一个蛋图标(用户 2026-07-30:「换成蛋壳色 + 两端加蛋图标」)。
## ★放在各段【外端之内】而不是条外 —— 放条外会顶出总宽, 左端只差 16px 就撞到标题文字。
##   放外端还有个好处: 副条是从内端往外退的, 所以图标始终压在【还剩的那截】上, 不会悬空。
## ★图标自带 1px 深色描边, 所以压在同为蛋壳色的填充上仍读得出。
func _pk_egg_icon(bar: Control, ey: float) -> void:
	var tex := VfxTex._make_egg_icon_texture()
	if tex == null:
		return
	for left in [true, false]:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var x: float = 4.0 + PK_SLANT if left else (_pk_w_cur - 15.0 - PK_SLANT)   # ★避开斜边(用运行时宽)
		ic.position = Vector2(x, ey + 1.0)
		ic.size = Vector2(11.0, 14.0)
		bar.add_child(ic)
		_pk_egg_icons.append(ic)


## 读数标签: 深色底板 + [百分比大字][绝对血量小字] 紧挨成一组。
## 底板宽度随内容自适应(HBox), 贴自己那一侧的外端(内缩一个斜切量, 否则被斜边切掉)。
func _pk_mk_tag(bar: Control, left: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ★★去掉深色底板(用户 2026-07-31:「那个数字你办法，别这么放」)。
	#   原来是块 alpha 0.62 的深色板压在条上 —— 它把血条【左端连同斜边一起盖住】,
	#   看起来像贴了张标签而不是条的一部分。
	#   现在: 只留字, 靠字自己的 4px 黑描边在填充上读(_pk_mk_label 已有描边),
	#   条从头到尾不被打断。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)                  # 全透明: 不再有底板
	sb.content_margin_left = 2; sb.content_margin_right = 2
	sb.content_margin_top = 0; sb.content_margin_bottom = 0
	sb.set_corner_radius_all(0)
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ★间距 6 → 10: 去掉底板后两个数字失去了"同一块板上"的归属感, 挨太近会读成一个数
	#   ("91%2,792")。拉开一点, 它们就是【主 + 副】两个信息。
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	# ★层级: 百分比是主角(19号·纯白), 绝对血量是配角(12号·半透)。
	#   原来 18/13 且配角 0.70 不透明 —— 两者体量太接近, 眼睛不知道先看哪个。
	var pct := _pk_mk_label(HORIZONTAL_ALIGNMENT_LEFT, 19)
	var abs_l := _pk_mk_label(HORIZONTAL_ALIGNMENT_LEFT, 12)
	# ★配角 = 【小 + 淡】, 不能靠"加粗描边"来降级 —— 12px 像素字配 3px 黑描边, 描边占了
	#   字身 1/4, 0.55 的白被黑边挤成一坨灰; 抓图实测 "2,049" 的千分位逗号直接糊没了,
	#   四个数字读成一个色块 = 配角信息【完全失效】。描边 2 + 0.76 白: 仍明显轻于纯白主角,
	#   但每一位数(含逗号)都数得出来。
	abs_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.76))
	abs_l.add_theme_constant_override("outline_size", 2)
	if left:
		hb.add_child(pct); hb.add_child(abs_l)     # 左段: 百分比在外(左)
	else:
		hb.add_child(abs_l); hb.add_child(pct)     # 右段镜像
	pc.set_meta("pct", pct)
	pc.set_meta("abs", abs_l)
	bar.add_child(pc)
	pc.position = Vector2(6.0 + PK_SLANT, 3.0) if left else Vector2(0.0, 3.0)
	return pc


func _pk_mk_label(align: int, fs: int = 15) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color("#ffffff"))
	l.add_theme_constant_override("outline_size", 4)          # 描边: 压在蓝/红上要读得清
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


## 中间 VS 徽标(取代第一版那个会被读错的百分比)。
## 三种动态, 都不用 tween(免生命周期/跨路被 kill 的问题), 全在 _pk_tick 里按相位算:
##   ① 呼吸: 常态轻微缩放脉动, 让它"活着"
##   ② 优势方染色: 底片颜色在蓝↔红之间按优势插值 → 不用数字也读得出谁占优
##   ③ 受伤脉冲: 任一方掉血 → 亮度闪一下
func _pk_build_vs(bar: Control) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = Vector2(_pk_seg_cur, 0.0)
	holder.size = Vector2(PK_VS, PK_H)
	holder.pivot_offset = Vector2(PK_VS * 0.5, PK_H * 0.5)
	bar.add_child(holder)
	_pk_vs = holder
	# ── 背后光晕: 优势方染色搬到这儿(原来染的是方框底片, 太闷) ──
	var gl := TextureRect.new()
	gl.texture = VfxTex._make_glow_texture()
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gl.stretch_mode = TextureRect.STRETCH_SCALE
	# ★2.1×2.6 太大: 实拍里它不是"徽章背后一点光", 而是中间一大团雾,
	#   把两侧血条的内端都染了色、盖住了。收到 1.35×1.7 才是"衬托徽章"而不是"糊住中段"。
	gl.size = Vector2(PK_VS * 1.35, PK_H * 1.7)
	gl.position = Vector2(PK_VS * 0.5, PK_H * 0.5) - gl.size * 0.5
	holder.add_child(gl)
	_pk_vs_glow = gl
	# ── 徽章: 像素画 VS(全新生成·assets/sprites/ui/pk-vs-emblem.png) ──
	# ★这里给贴图不违反"血条不上美术素材"那条: 我反对的是给【可伸缩的条】上 9-slice
	#   (斜切端和平铺天然冲突), 而 VS 是【固定尺寸的单点元素】, 没有伸缩问题,
	#   它又是整条的视觉焦点, 值得特殊对待(用户 2026-07-30:「不要这框呢，或者设计好点的」)。
	var em := TextureRect.new()
	if ResourceLoader.exists(PK_VS_EMBLEM):
		em.texture = load(PK_VS_EMBLEM)
	else:
		push_warning("[PK] VS 徽章素材缺失: %s" % PK_VS_EMBLEM)
	em.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# ★必须 EXPAND_IGNORE_SIZE: TextureRect 默认 EXPAND_KEEP_SIZE, 最小尺寸被【贴图本身】
	#   顶住(这张 76×56), 我下面设的 size 会被无声地钳上去 —— 等于设了个寂寞。
	#   (是门禁反向验证时发现的: "徽章高度超出条高"那条断言把高度改成 PK_H 也不红,
	#    因为贴图 56 > 32 恒成立 —— 恒真式。)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# ★故意【超出条高】: 格斗游戏的中央徽章都是破出血条框的, 这样它才是焦点而不是条的一格
	# ★槽收窄后徽章反而要【更大】: 破框幅度 = 焦点强度。
	#   宽 PK_VS+16(左右各溢出 8px 压住两条内端的斜边) · 高 PK_H+16(仍不压到副条: 副条从 y=36 起)
	em.size = Vector2(PK_VS + 16.0, PK_H + 16.0)
	em.position = Vector2(PK_VS * 0.5, PK_H * 0.5) - em.size * 0.5
	holder.add_child(em)
	_pk_vs_em = em


## 这个单位算不算进【主条】。见本节顶部注释的口径说明。
## ★用 _isEgg 不是 egg —— 单位字典上没有 egg 这个键(见顶部注释①那个 bug)。
func _pk_counts(u: Dictionary) -> bool:
	if u.get("_isEgg", false) or u.get("_eggImmune", false):
		return false
	if u.get("is_trainer", false):
		return false
	if u.get("is_summon", false):
		return false
	return true


## 一侧【主条】的 (当前血, 分母用的最大生命) 之和。
## ★分母项含【已死单位】—— 死人不许改分母, 否则分子分母同缩、比例反而回升, 条往回涨。
## ★分母按【原 side】、分子按【_eff_side】—— 见函数体里那段, 这是"归顺不让条跳"的关键。
func _pk_sum(side: String) -> Vector2:
	var cur := 0.0
	var mx := 0.0
	for u in battle._units:
		if not _pk_counts(u):
			continue
		# ★★分母按【原阵容 side】、分子按【现在为谁而战 _eff_side】—— 两者【故意不同】。
		#
		#   由来(用户 2026-07-30「怎么有时候莫名增加或减少」): 原来两者都用 _eff_side,
		#   于是驯服归顺时那只龟【整只】从敌方的分子分母里消失、又整只出现在我方 ——
		#   实测敌方 0.630 → 1.000(+0.370)、我方 0.993 → 0.811(−0.182), 两条同时硬跳,
		#   而且方向还反了(我方"多了个帮手"条却掉下来 = 被那只残血龟稀释)。
		#
		#   现在: 分母 = 双方【带进这一路的阵容】的最大生命之和(归顺不改它);
		#         分子 = 当前【为该方而战】的存活血量。
		#   → 归顺 = 血量搬边、分母不动 → 我方涨 / 敌方跌, 方向都对, 幅度就是那只龟的血占比。
		#   → 临时血 +700 会同时抬这只龟【原方】的分母与分子, 幅度小(实测 +0.023)。
		#   → 死亡只减分子不减分母(已死单位仍计入 mx), 条只降不升。
		var born: String = str(u.get("side", ""))
		if born == side:
			mx += maxf(0.0, float(u.get("maxHp", 0)))
		if battle._eff_side(u) == side and u.get("alive", false):
			cur += maxf(0.0, float(u.get("hp", 0)))
	return Vector2(cur, mx)


## 一侧【龟蛋】的 (当前血, 最大生命)。蛋按 egg_side_lr 归属, 不走 _eff_side。
## ★蛋的 hp 是【跨路累积受损值】而 maxHp 保持原始满血(见 battle_spawn 蛋段注释),
##   所以这里直接用 hp/maxHp 就是"蛋还剩多少", 不需要自己存基线。
func _pk_egg_sum(side: String) -> Vector2:
	var cur := 0.0
	var mx := 0.0
	for u in battle._units:
		if not u.get("_isEgg", false):
			continue
		if str(u.get("egg_side_lr", "")) != side:
			continue
		mx += maxf(0.0, float(u.get("maxHp", 0)))
		cur += maxf(0.0, float(u.get("hp", 0)))
	return Vector2(cur, mx)


## 重扫 _units → 更新两条的目标比例与主条两端数字。每 PK_SAMPLE 秒一次。
##
## ★换路检测: 用"计入主条的单位数变了"当信号。为什么可靠 ——
##   单位死亡【不会】从 battle._units 里移除(只把 alive 置 false), 所以一路之内这个数恒定;
##   换路时 _dl_clear_units() 清空 _units 再重新 spawn(dual_lane_flow:719-724), 数必然变。
##   ★不能只在场景初始化时算一次基线 —— _t 跨上路→下路→决胜累加(CLAUDE.md §3.4)。
func _pk_refresh() -> void:
	if _pk_bar == null or not is_instance_valid(_pk_bar):
		return
	var l := _pk_sum("left")
	var r := _pk_sum("right")
	# ★★2026-07-30 修「条会莫名增减」(用户报)。改了两处, 各解一个跳变源:
	#
	# ①【分母改成"活的总量"】(原来是开场冻结的 _pk_base_l/r)。
	#    冻结分母下, 任何"分子变了而分母没变"的事件都会让条【瞬跳】:
	#      · 驯服归顺 —— 那只龟的血整只从敌方分子搬到我方分子, 两边基线都不动 → 两条同时跳
	#      · 口哨①临时血 +700 —— 我方分子凭空 +700(甚至顶到 100% 被截断)
	#      · 驯服重生 30% 最大生命 —— 分子凭空回血
	#    改成活分母后, 这些事件【分子分母一起动】, 比例连续。
	#    ★原注释担心的"死人改分母 → 条往回涨"【不成立】: _pk_sum 的 mx 本来就
	#      把已死单位算进去(见那边注释), 所以死亡不会缩分母。冻结对死亡是多余的。
	#
	# ②【重置改成按"路 id"】(原来是按"计数单位数 n 变了")。
	#    按 n 判等于说"场上计数单位数一变就把两条拉回 100%" —— 换路当然会变,
	#    但【任何中途增减计数单位】也会触发, 表现就是条莫名满格。改成只认换路。
	var lane: String = str(GameState.current_lane) if GameState != null and GameState.current_lane != null else "top"
	if lane == "":
		lane = "top"     # ★空串归一成 "top" —— 否则 _pk_lane 的哨兵值 "" 会跟它相等, 逼不出重置
	if lane != _pk_lane:                # 换路(或首次) → 两条回满
		_pk_lane = lane
		_pk_shown_l = 1.0
		_pk_shown_r = 1.0
		_pk_trail_vl = 1.0
		_pk_trail_vr = 1.0
		_pk_gain_vl = 1.0
		_pk_gain_vr = 1.0
		_pk_egg_sl = 1.0
		_pk_egg_sr = 1.0
	_pk_base_l = l.y                    # 留着给门禁/调试看当前分母
	_pk_base_r = r.y
	_pk_target_l = 0.0 if l.y <= 0.0 else clampf(l.x / l.y, 0.0, 1.0)
	_pk_target_r = 0.0 if r.y <= 0.0 else clampf(r.x / r.y, 0.0, 1.0)
	_pk_lab_l.text = "%d%%" % int(round(_pk_target_l * 100.0))
	_pk_lab_r.text = "%d%%" % int(round(_pk_target_r * 100.0))
	_pk_lab_l2.text = _pk_num(l.x)
	_pk_lab_r2.text = _pk_num(r.x)
	# 右侧标签宽度随内容变 → 每次刷新后重新贴右端(内缩一个斜切量)
	if _pk_tag_r != null and is_instance_valid(_pk_tag_r):
		_pk_tag_r.position.x = _pk_w_cur - _pk_tag_r.size.x - 6.0 - PK_SLANT
	# ── 副条: 龟蛋 ──
	var el := _pk_egg_sum("left")
	var er := _pk_egg_sum("right")
	_pk_egg_tl = 0.0 if el.y <= 0.0 else clampf(el.x / el.y, 0.0, 1.0)
	_pk_egg_tr = 0.0 if er.y <= 0.0 else clampf(er.x / er.y, 0.0, 1.0)
	# ★没有蛋的模式(单路/评审/决胜战场)整场都不会有蛋 → 整行【隐藏】。
	#   原来留着两条空槽挂在那儿是纯噪声。不怕"布局跳": 有没有蛋是【整路】固定的,
	#   不会打到一半才变。
	var has_egg: bool = (el.y > 0.0 or er.y > 0.0)
	if _pk_egg_row != null and is_instance_valid(_pk_egg_row):
		_pk_egg_row.visible = has_egg
	# ★围栏未破 → 副条压暗: 此时蛋【打不到】(battle_targeting 里单体+AoE 都不锁它),
	#   副条会一直满着不动。压暗就把"现在还打不到蛋"这个状态说出来了, 破栏后恢复全亮
	#   —— 副条从"静止的装饰"变成有信息量的状态指示。
	var fenced := false
	for u in battle._units:
		if u.get("_isEgg", false) and u.get("_egg_fence", false):
			fenced = true
			break
	# ★压暗要【调暗颜色】不能用 alpha ——
	#   半透的米黄压在深色背景上会被背景拉成【灰管子】(0.38 时最明显, 0.62 仍偏灰):
	#   看不出蛋壳色, 也读不出"暂时打不到"。改成把 modulate 的 RGB 压到 0.58、alpha 保持 1.0,
	#   壳色的色相就还在, 只是暗一档。
	var k: float = 0.58 if fenced else 1.0
	var mod := Color(k, k, k, 1.0)
	if _pk_egg_l != null and is_instance_valid(_pk_egg_l):
		_pk_egg_l.modulate = mod
		_pk_egg_r.modulate = mod
	for ic in _pk_egg_icons:
		if is_instance_valid(ic):
			ic.modulate = mod


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


## 把当前显示值画成两段的填充宽度(含残影)。
## ★左段贴【外侧左端】往右长, 右段贴【外侧右端】往左长 —— 掉血时从【内端】(靠中间那侧)
##   往外退, 露出自己框内的暗槽。这是格斗游戏的读法; 第一版是"一条长条中间开缝",
##   会被读成"从中心掉血"(用户 2026-07-30 指出)。
func _pk_apply() -> void:
	if _pk_fill_l == null or not is_instance_valid(_pk_fill_l):
		return
	var inner: float = _pk_seg_cur - 4.0   # 减掉 2px 边框×2 (★运行时段宽, 窄屏才不会溢出)
	var h: float = PK_H - 4.0
	# ★三层宽度: 残影 ≥ 当前值 ≥ 低水位。
	#   掉血时 低水位=当前值 → 回血带宽度为 0(完全看不见), 露出的是残影;
	#   回血时 残影=当前值 → 残影宽度为 0, 露出的是回血带。两者天然互斥, 不会同时出现。
	_pk_put(_pk_trail_l, true, _pk_trail_vl, inner, h, 2.0)
	_pk_put(_pk_fill_l, true, _pk_shown_l, inner, h, 2.0)
	_pk_put_band(_pk_gain_l, true, _pk_gain_vl, _pk_shown_l, inner, h, 2.0)
	_pk_put(_pk_trail_r, false, _pk_trail_vr, inner, h, 2.0)
	_pk_put(_pk_fill_r, false, _pk_shown_r, inner, h, 2.0)
	_pk_put_band(_pk_gain_r, false, _pk_gain_vr, _pk_shown_r, inner, h, 2.0)
	var eh: float = PK_EGG_H - 4.0
	var ey: float = PK_H + PK_EGG_GAP + 2.0
	_pk_put(_pk_egg_l, true, _pk_egg_sl, inner, eh, ey)
	_pk_put(_pk_egg_r, false, _pk_egg_sr, inner, eh, ey)


## 放一条【区间带】: 只覆盖 [a, b] 这一段(a<b), 用于回血带。a>=b 时宽度为 0(等于隐形)。
## ★左段从外侧左端往右长, 所以区间 [a,b] 的左沿在 a; 右段镜像, 左沿在 (1-b)。
func _pk_put_band(cr: Control, left: bool, a: float, b: float, inner: float, h: float, y: float) -> void:
	if cr == null or not is_instance_valid(cr):
		return
	a = clampf(a, 0.0, 1.0)
	b = clampf(b, 0.0, 1.0)
	var w: float = maxf(0.0, (b - a) * inner)
	if left:
		cr.position = Vector2(2.0 + a * inner, y)
	else:
		cr.position = Vector2(_pk_seg_cur + PK_VS + 2.0 + (inner - b * inner), y)
	cr.size = Vector2(w, h)
	_pk_slant_size(cr, cr.size)


## 放一条填充。left=true 贴外侧左端; false 贴外侧右端。
## ★参数类型 Control 而不是 ColorRect —— 主条填充现在是 TextureRect(竖向渐变), 副条仍是 ColorRect。
func _pk_put(cr: Control, left: bool, frac: float, inner: float, h: float, y: float) -> void:
	if cr == null or not is_instance_valid(cr):
		return
	var w: float = clampf(frac, 0.0, 1.0) * inner
	if left:
		cr.position = Vector2(2.0, y)
	else:
		cr.position = Vector2(_pk_seg_cur + PK_VS + 2.0 + (inner - w), y)
	cr.size = Vector2(w, h)
	_pk_slant_size(cr, cr.size)     # ★宽度变了要重喂, 否则斜边角度跟着宽度变形


## 每帧驱动: 平滑两条填充 + 残影追赶 + VS 徽标三种动态 + 每 PK_SAMPLE 秒重扫 _units。
## 由 battle_render._render_step 调用(渲染路, 不进 sim → 不影响确定性)。
func _pk_tick(delta: float) -> void:
	if _pk_bar == null or not is_instance_valid(_pk_bar):
		return
	_pk_acc += delta
	if _pk_acc >= PK_SAMPLE:
		_pk_acc = 0.0
		_pk_refresh()
	# 主条填充 + 残影。掉血瞬间: 填充先退, 残影留在原位再慢慢追 → 看得出"刚掉了这一段"
	var pl: float = _pk_shown_l
	var pr: float = _pk_shown_r
	_pk_shown_l = _pk_ease(_pk_shown_l, _pk_target_l, delta)
	_pk_shown_r = _pk_ease(_pk_shown_r, _pk_target_r, delta)
	if _pk_shown_l < pl - 0.0001:
		_pk_hit_l = 1.0                   # 左方掉血 → 触发脉冲
	if _pk_shown_r < pr - 0.0001:
		_pk_hit_r = 1.0
	# ★★残影就是【平滑渐退】, 不做停顿。
	#   我一度加过"掉血后原地停 0.45 秒再收"(出发点: 小额掉血会被瞬间追上),
	#   用户看实机后否掉 ——「掉血特效停0.45秒的这个不好, 不如之前的渐退」。整段已删。
	# ★★回血带的上涨触发必须和掉血触发【并排】写在这儿 —— 不能挪到下面。
	#   下面两行会把 _pk_prev_shown 刷成当前值, 之后再判 `shown > prev` 就【永远不成立】,
	#   停顿一次都触发不了 → 回血带被瞬间追平 = 等于没做。
	#   我第一版就写在下面, 门禁「停顿期内低水位原地不动」当场抓到(停顿中 0.2397 vs 停顿前 0.2199)。
	if _pk_shown_l > _pk_prev_shown_l + 0.0005:
		_pk_gain_hold_l = PK_GAIN_HOLD
	if _pk_shown_r > _pk_prev_shown_r + 0.0005:
		_pk_gain_hold_r = PK_GAIN_HOLD
	_pk_prev_shown_l = _pk_shown_l
	_pk_prev_shown_r = _pk_shown_r
	_pk_trail_vl = maxf(_pk_shown_l,
		_pk_lerp_to(_pk_trail_vl, _pk_shown_l, delta * PK_TRAIL_SMOOTH))
	_pk_trail_vr = maxf(_pk_shown_r,
		_pk_lerp_to(_pk_trail_vr, _pk_shown_r, delta * PK_TRAIL_SMOOTH))
	# ★回血带 = 残影的【镜像】。低水位用 minf(当前值, …) 夹住: 掉血时它跟着当前值瞬间下来
	#   (回血带宽度归零), 只有【涨】的时候才滞后 → 露出刚回的那一段。
	#   触发同样必须是"填充这一帧上升了"(跟上一帧比), 不能写成"低水位低于填充" ——
	#   后者在整个追平过程中一直成立, 停顿被每帧刷新 → 回血带永远不收。(残影那条栽过, 见上。)
	_pk_gain_hold_l = maxf(0.0, _pk_gain_hold_l - delta)
	_pk_gain_hold_r = maxf(0.0, _pk_gain_hold_r - delta)
	# (原来这儿还有一行"停顿期也把低水位夹到 <= 填充"。反向验证证明它【冗余】——
	#  删掉后门禁照样全绿: 下面 lerp 那两行自带 minf 已经夹住了; 而停顿期内即使
	#  低水位高于填充, _pk_put_band 的 maxf(0, b-a) 也会把带子宽度算成 0 = 隐形。
	#  验证不到的代码不留 —— 留着就是"看起来在防什么但其实没人证明过"。)
	if _pk_gain_hold_l <= 0.0:
		_pk_gain_vl = minf(_pk_shown_l,
			_pk_lerp_to(_pk_gain_vl, _pk_shown_l, delta * PK_GAIN_SMOOTH))
	if _pk_gain_hold_r <= 0.0:
		_pk_gain_vr = minf(_pk_shown_r,
			_pk_lerp_to(_pk_gain_vr, _pk_shown_r, delta * PK_GAIN_SMOOTH))
	_pk_egg_sl = _pk_ease(_pk_egg_sl, _pk_egg_tl, delta)
	_pk_egg_sr = _pk_ease(_pk_egg_sr, _pk_egg_tr, delta)
	_pk_apply()
	# 脉冲衰减
	_pk_hit_l = maxf(0.0, _pk_hit_l - delta * PK_HIT_DECAY)
	_pk_hit_r = maxf(0.0, _pk_hit_r - delta * PK_HIT_DECAY)
	_pk_low_tick()
	_pk_vs_tick(delta)


## 低血量警示: 低于 PK_LOW 时该侧填充开始明暗闪烁, 越低闪得越狠。
## ★为什么要有: 第一版 5% 和 95% 除了【长度】没有任何区别 —— 而血条的标准语言
##   就是"快没了要喊一声"。闪烁用相位算(不用 tween), 结算后停(和 VS 呼吸同理)。
func _pk_low_tick() -> void:
	if _pk_fill_l == null or not is_instance_valid(_pk_fill_l):
		return
	_pk_fill_l.modulate = _pk_low_mod(_pk_shown_l)
	_pk_fill_r.modulate = _pk_low_mod(_pk_shown_r)


func _pk_low_mod(frac: float) -> Color:
	if battle._settled or frac >= PK_LOW or frac <= 0.0:
		return Color.WHITE
	# 越接近 0 闪得越狠(幅度 0.18 → 0.42)
	var sev: float = 1.0 - clampf(frac / PK_LOW, 0.0, 1.0)
	var amp: float = lerpf(0.18, 0.42, sev)
	var k: float = 1.0 + sin(_pk_phase * TAU * PK_LOW_HZ) * amp
	return Color(k, k, k, 1.0)


## VS 徽标: ①呼吸 ②优势方染色 ③受伤脉冲。全按相位算, 不用 tween。
func _pk_vs_tick(delta: float) -> void:
	if _pk_vs == null or not is_instance_valid(_pk_vs):
		return
	# ★结算后停掉呼吸: _pk_tick 走的是渲染路, 结算屏上它照跑 —— 那个 VS 会在结果画面上
	#   一直一呼一吸, 很吵。停在中性尺寸(而不是停在某个呼吸相位上)。
	if battle._settled:
		_pk_vs.scale = Vector2.ONE
		if _pk_vs_glow != null and is_instance_valid(_pk_vs_glow):
			_pk_vs_glow.modulate = Color(1, 1, 1, 0.0)
		return
	_pk_phase = fmod(_pk_phase + delta, 1000.0)
	var hit: float = maxf(_pk_hit_l, _pk_hit_r)
	# ① 呼吸(±3%) + ③ 受伤时徽章弹一下
	var sc: float = 1.0 + sin(_pk_phase * 2.4) * 0.03 + hit * 0.16
	_pk_vs.scale = Vector2(sc, sc)
	# ② 优势方染色 —— 染【光晕】不是染方框(方框已删)。
	#   染色系数 ×1.4: 差 0.36 就吃满, 优势明显时一眼读得出偏哪边。
	var adv: float = clampf(0.5 + (_pk_shown_l - _pk_shown_r) * 1.4, 0.0, 1.0)
	var tint: Color = PK_RED.lerp(PK_BLUE, adv)
	if _pk_vs_glow != null and is_instance_valid(_pk_vs_glow):
		# 光晕强度: 常态随呼吸微动; 掉血时炸亮一下
		var amp: float = 0.20 + sin(_pk_phase * 2.4) * 0.04 + hit * 0.45   # ★基础强度也收一档
		_pk_vs_glow.modulate = Color(tint.r, tint.g, tint.b, clampf(amp, 0.0, 1.0))
		var gs: float = 1.0 + hit * 0.35
		_pk_vs_glow.scale = Vector2(gs, gs)
		_pk_vs_glow.pivot_offset = _pk_vs_glow.size * 0.5


## 向目标平滑一步; 收敛就【吸附】—— 否则无限逼近会永远留半像素缝。
func _pk_ease(cur: float, target: float, delta: float) -> float:
	var d: float = target - cur
	if absf(d) < 0.0008:
		return target
	return cur + d * clampf(delta * PK_SMOOTH, 0.0, 1.0)


## 残影专用: 只朝目标靠近(不吸附), 由调用方用 maxf 保证不低于填充。
func _pk_lerp_to(cur: float, target: float, k: float) -> float:
	return cur + (target - cur) * clampf(k, 0.0, 1.0)


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
	# ★能不能拖动瞄准由技能的 aim 字段决定(唯一判定在 BattleAim._aim_type_of)。
	#   口哨 aim="none" → 圆盘退化成纯点击键: 按下不出方向轮盘, 松手即放。
	#   用户 2026-07-30:「3种情况都是点击就放, 不应该有拖动」
	battle._spell_disc.set_aimable(
		sid != "" and str(battle.TRAINER_SKILLS.get(sid, {}).get("aim", "none")) != "none")
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
	# ═══════════════════════════════════════════════════════════════════════
	# ★★2026-08-02 整页重做(用户:「整个结算页也需要重做, UI什么的, 文字都非常口语化,
	#   玩家压根不知道在说什么」)。
	#
	# 旧版的两个毛病:
	#   ① 文案: `+12 深海币    命 5/8    胜场 3    Lv.4` —— 四项用【空格】挤成一行、
	#      没有标签层级、"命"是口语; 还有 `(练习赛 · 无赛季奖励)` `(失一命)` `去商店 逛逛`
	#      这类括号口语, 读起来像开发者备注不像游戏界面。
	#   ② 布局: 标题/比分/奖励/按钮/统计表【五行各自按屏高比例硬摆】(0.34/0.455/0.505/0.575/0.61),
	#      行距靠手调, 换个分辨率就得重调; 而且【按钮排在数据表上面】, 阅读顺序是反的。
	#
	# 现在: 整页是【一张居中的卡片】(CenterContainer + VBoxContainer) ——
	#   结果标题 → 一句后果说明 → 战果比分 → 数据块 → 战斗数据表 → 主按钮。
	#   垂直居中由容器算, 不再有一个比例常量; 任何分辨率自动成立(iPad 的 1280×960 也是)。
	# ═══════════════════════════════════════════════════════════════════════
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)                    # 从全透明淡入
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)   # ★锚点铺满, 不写死尺寸
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	battle._ui_layer.add_child(dim)
	var dtw = battle.create_tween()
	dtw.tween_property(dim, "color:a", 0.72, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 自己不吃点击, 让按钮收到(见 ui_frame 的同款教训)
	battle._ui_layer.add_child(center)
	# ★整张卡有自己的底: 不然标题/后果/数据块是【浮在战场上的散件】, 和下面那块有边框的
	#   数据表分成两坨。一个底把它们收成一张"结算单"。
	var shell := PanelContainer.new()
	var shell_sb := StyleBoxFlat.new()
	shell_sb.bg_color = Color(0.035, 0.055, 0.085, 0.90)
	shell_sb.border_color = Color(0.28, 0.44, 0.62, 0.50)
	shell_sb.set_border_width_all(2)
	shell_sb.set_corner_radius_all(14)
	shell_sb.content_margin_left = 34; shell_sb.content_margin_right = 34
	shell_sb.content_margin_top = 22; shell_sb.content_margin_bottom = 24
	shell.add_theme_stylebox_override("panel", shell_sb)
	center.add_child(shell)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 12)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(card)

	# ── ① 结果标题
	var big = Label.new()
	big.text = ("胜利" if won else "失败")
	big.add_theme_font_size_override("font_size", 54)
	big.add_theme_color_override("font_color", accent)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(big)
	big.pivot_offset = Vector2(big.size.x * 0.5, 30.0)
	big.scale = Vector2(1.7, 1.7)
	big.modulate.a = 0.0
	var btw = battle.create_tween()
	btw.set_parallel(true)
	btw.tween_property(big, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.12)
	btw.tween_property(big, "modulate:a", 1.0, 0.30).set_delay(0.12)

	# ── ② 一句【后果说明】: 玩家最想知道的是"这一场对我意味着什么"
	var sub := Label.new()
	sub.text = _result_subtitle(won, gs)
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color("#93a4b8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(sub)
	_banner_fade_in(sub, 0.26)

	# ── ③ 战果比分(双路才有)
	if battle._is_dual_lane_mode() and gs != null and gs.get("lane_results") is Dictionary and not (gs.get("lane_results") as Dictionary).is_empty():
		var score = Label.new()
		score.text = battle._dl_sys._dl_record_line()
		score.add_theme_font_size_override("font_size", 22)
		score.add_theme_color_override("font_color", Color("#cfe6ff"))
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(score)
		_banner_fade_in(score, 0.34)

	# ── ④ 数据块: 标签(小字灰) + 数值(大字亮), 一项一块, 不再用空格挤成一行
	var chips := _build_reward_chips(gs)
	if chips != null:
		card.add_child(chips)
		_banner_fade_in(chips, 0.42)

	# ── ⑤ 战斗数据表
	var stats := _build_stats_panel()
	if stats != null:
		card.add_child(stats)
		_banner_fade_in(stats, 0.50)

	# ── ⑥ 主按钮(★排在数据【下面】—— 旧版排在上面, 阅读顺序是反的)
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 28)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(btn_row)
	# ★教学模式: 结算按钮走导演(战斗1打完→商店, 战斗2打完→结束回菜单), 而不是直接返回菜单。
	var _td = battle.get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():
		# ★文字用 _peek_next【只读】—— 用 next_scene_after 会在【建按钮时】就推进 stage,
		#   导致战斗1一结算 stage 就跳到 shop, 玩家还没点。点了才 next_scene_after 真推进。
		var _peek: String = _td._peek_next("battle")
		var _label: String = "前往商店" if _peek.ends_with("Shop.tscn") else ("完成新手教学" if _peek.ends_with("MainMenu.tscn") else "继续")
		btn_row.add_child(battle._make_result_btn(_label, Color("#ffc23c"), Color("#3a1f00"),
			func() -> void: battle.get_tree().change_scene_to_file(_td.next_scene_after("battle"))))
	else:
		# ★★2026-08-02 补【前往商店】主按钮。
		#   自走棋的核心节奏是「打 → 买 → 再打」, 而原来结算页【只有返回主菜单】——
		#   玩家得自己想起来去商店、再自己回主菜单点开始战斗, 循环是断的。
		#   ★有意思的是【教学模式早就有正确做法】(上面那个分支会给"前往商店"),
		#     只是正式对局没用上。这里把它变成常规流程。
		#   ⚠ 赛季淘汰时【商店是锁的】(GameState.is_eliminated() → 锁匹配+商店,
		#     见 MainMenuScene.gd:169/739/770, 用户 2026-07-24 拍板"淘汰锁定"),
		#     所以淘汰后不给这个按钮 —— 否则点进去是个锁死的页面。
		var _gs2 = battle.get_node_or_null("/root/GameState")
		var _elim: bool = _gs2 != null and _gs2.is_eliminated()
		if not _elim:
			btn_row.add_child(battle._make_result_btn(SHOP_BTN_TEXT, Color("#ffc23c"), Color("#3a1f00"),
				func() -> void: battle.get_tree().change_scene_to_file(SHOP_SCENE)))
		btn_row.add_child(battle._make_result_btn("返回主菜单", Color("#5aa0d8"), Color("#04121e"),
			func() -> void: battle.get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	_banner_fade_in(btn_row, 0.58)


## 结果标题下面那一句 —— 说【这一场对玩家意味着什么】, 而不是罗列数字。
## 旧版把它和奖励数字塞在同一行、还用括号写成 "(练习赛 · 无赛季奖励)" "(失一命)"。
func _result_subtitle(won: bool, gs) -> String:
	if not battle._had_season or gs == null:
		return "练习赛 · 不计入赛季进度"
	if gs.is_eliminated():
		return "生命已耗尽 · 本赛季结束"
	if battle._last_was_exhibition:
		return "表演赛 · 不消耗生命"
	return "赛季胜场 +1" if won else "消耗 1 点生命"


## 数据块一排: 每块 = 标签(小字灰) + 数值(大字亮)。练习赛没有赛季数据 → 返回 null 不占位。
func _build_reward_chips(gs) -> Control:
	if not battle._had_season or gs == null:
		return null
	var lv: int = int(gs.get("season_level")) if gs.get("season_level") != null else 1
	var items: Array = [["深海币", "+%d" % battle._last_reward, Color("#ffd93d")]]
	if not battle._last_was_exhibition:
		items.append(["剩余生命", "%d / 8" % int(gs.hearts), Color("#ff8a8a") if int(gs.hearts) <= 2 else Color("#e8f0f6")])
	items.append(["赛季胜场", "%d" % int(gs.season_wins), Color("#e8f0f6")])
	items.append(["赛季等级", "Lv.%d" % lv, Color("#e8f0f6")])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for it in items:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		var cap := Label.new()
		cap.text = str(it[0])
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", Color("#7d8b9c"))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(cap)
		var val := Label.new()
		val.text = str(it[1])
		val.add_theme_font_size_override("font_size", 24)
		val.add_theme_color_override("font_color", it[2])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(val)
		row.add_child(col)
	return row


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
## ★★2026-08-02 修(用户:「战斗结束后的总结画面，手机上ui偏移还是没解决吗」):
##   原来是 `Vector2(640.0 - panel.size.x*0.5, 438.0)` —— 640 是【写死的 1280 的一半】,
##   438 是【写死的像素 y】。探针实测 1560×720 手机视口下面板中心仍停在 x=640,
##   而真中心是 780 ⇒ 整块结算表【左偏 140 像素】。
##   (2026-07-21 修过一次结算 UI, 修的是【胜负横幅】那套 —— 横幅改成锚点了, 这块没在里面。
##    "同一屏两套定位代码, 只修了看得见的那套" 是这个 bug 能活到今天的原因。)
## ★y 同样改成【按屏幕高度的比例】(438/720 = 0.6083), 否则 iPad 的 960 高视口上表会浮在上半屏。
##   仍然不做"放不下就上顶": 那会盖住上方的「返回菜单」钮; 放不下由页体内部滚动兜(见 _stats_fit_body)。
## 一队 5 列表: 龟 / 造成伤害 / 承受伤害 / 治疗量 / 击杀; 金表头 / 稀有度点 / 存活白·阵亡灰(阵亡).
func _stats_column(header: String, units: Array, hc: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	# ★★2026-08-02 用户定: 去掉「暴击」与「剩余血量」, 保留「承受伤害」。
	#   「受伤」本来就是承受伤害(_st_taken 在两条伤害路径里累加的都是实扣血量),
	#   只是名字容易读成"受伤状态" —— 改名【承伤】, 不是新增一列。
	#   ★数据字段 _st_crit 保留(battle_damage 仍在累加、_st_merge_all 仍在合并),
	#     只是不再显示 —— 删字段会连带动到战中统计面板与合计页, 收益为零。
	# ★★表头用【全称】(用户 2026-08-02:「文字都非常口语化, 玩家压根不知道在说什么」)。
	#   "出伤/承伤" 是开发者行话缩写, 玩家看不懂; 列宽相应放宽。
	var hdrs := [header, "造成伤害", "承受伤害", "治疗量", "击杀"]
	for i in range(5):
		var l := Label.new()
		l.text = hdrs[i]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", hc if i == 0 else Color("#ffd93d"))   # 金表头(回合制)
		if i == 0:
			l.custom_minimum_size = Vector2(126, 0)
		else:
			l.custom_minimum_size = Vector2(72, 0)   # ★容得下"造成伤害"四字表头 + 五位数值
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	# ★★MVP: 本队【造成伤害最高】的那只(不含召唤体)。一张全是数字的表, 玩家扫一眼
	#   得不出任何结论; 标出"这场谁扛的"才让数据变成信息。
	var mvp_dmg: int = 0
	var mvp_name: String = ""
	for u in units:
		if u.get("is_summon", false):
			continue
		var d: int = int(u.get("_st_dealt", 0))
		if d > mvp_dmg:
			mvp_dmg = d; mvp_name = battle._st_name(u)
	for u in units:
		var dead: bool = not u.get("alive", true)
		var is_sm: bool = u.get("is_summon", false)
		var is_mvp: bool = mvp_dmg > 0 and not is_sm and battle._st_name(u) == mvp_name
		# col0: 稀有度色点 + 名(阵亡后缀)
		var name_cell := HBoxContainer.new()
		name_cell.add_theme_constant_override("separation", 5)
		name_cell.custom_minimum_size = Vector2(126, 0)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color("#7a8a96") if is_sm else battle._pet_rarity_color(str(u.get("rarity", "C")))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_cell.add_child(dot)
		var nml := Label.new()
		nml.text = ("↳ " if is_sm else "") + battle._st_name(u) + ("  阵亡" if dead else "")
		nml.add_theme_font_size_override("font_size", 13)
		nml.add_theme_color_override("font_color", Color("#888888") if dead else (Color("#cdd9c2") if is_sm else Color("#ffffff")))
		name_cell.add_child(nml)
		if is_mvp:
			var tag := Label.new()
			tag.text = "MVP"
			tag.add_theme_font_size_override("font_size", 10)
			tag.add_theme_color_override("font_color", Color("#ffd93d"))
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			name_cell.add_child(tag)
		grid.add_child(name_cell)
		var vals := [str(int(u.get("_st_dealt", 0))), str(int(u.get("_st_taken", 0))), str(int(u.get("_st_heal", 0))), str(int(u.get("_st_kills", 0)))]
		for i in range(4):
			var l := Label.new()
			l.text = vals[i]
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color("#888888") if dead else (Color("#ffd93d") if is_mvp else Color("#e8f0f6")))
			l.custom_minimum_size = Vector2(72, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
	return grid

## 返回战斗数据表面板(调用方决定放哪)。★2026-08-02 改成返回值 ——
## 旧版自己 add_child 到 _ui_layer 再摆绝对坐标, 结算页因此必须用比例硬摆五行。
## 现在它是结算卡片里的一个子节点, 位置由容器算。
func _build_stats_panel() -> Control:
	# 结算页要含【前面战场】的总结, 不能只有当前这一路(用户2026-07-19): 已结束的路走 battle._st_lane_hist 快照,
	# 当前路直接读活的 battle._units; 三路以上信息量太大 → 做成分页(默认停在「合计」).
	var pages: Array = []            # [{lane, title, left:[row], right:[row]}]
	for snap in battle._st_lane_hist:
		pages.append({"lane": snap["lane"], "title": battle._LANE_CN.get(snap["lane"], str(snap["lane"])),
			"left": snap["left"], "right": snap["right"]})
	var cur = {"lane": "cur", "title": "", "left": [], "right": []}
	for u in battle._units:
		# ★同上: 按【有效阵营】归栏 —— 归顺的龟在打原队, 战绩该记在我方这一列。
		#   (这是"同一语义两处各写各的"的第四处。全工程判敌我一律走 battle._eff_side。)
		var sd = battle._eff_side(u)
		if sd == "left" or sd == "right":
			(cur[sd] as Array).append(battle._st_row(u))
	if not ((cur["left"] as Array).is_empty() and (cur["right"] as Array).is_empty()):
		var cl = str(GameState.current_lane) if GameState != null else ""
		cur["title"] = battle._LANE_CN.get(cl, "本场") if not pages.is_empty() else "本场"
		pages.append(cur)
	if pages.is_empty():
		return null
	if pages.size() > 1:             # 只有一路就没有「合计」的必要
		pages.append({"lane": "all", "title": "合计",
			"left": battle._st_merge_all(pages, "left"), "right": battle._st_merge_all(pages, "right")})

	var panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	# ★它现在嵌在结算卡里 —— 再来一圈 2px 亮边就是"框中框"。改成淡底 + 极细边做分区。
	sb.bg_color = Color(0.09, 0.13, 0.19, 0.55)
	sb.border_color = Color(0.30, 0.48, 0.66, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title = Label.new()
	title.text = "战斗数据"
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
		cols.add_child(_stats_column("我方", pg["left"], Color("#7ec8ff")))
		# ★竖分隔: 两队并排时数字会连成一片, 分不清左边最后一列和右边第一列
		var sep := ColorRect.new()
		sep.color = Color(0.30, 0.48, 0.66, 0.30)
		sep.custom_minimum_size = Vector2(1, 0)
		sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cols.add_child(sep)
		cols.add_child(_stats_column("对方", pg["right"], Color("#ff9a9a")))
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
	return panel

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
	# ★栏高必须【跟着内容走】, 不能写死 94 (2026-08-03 门禁探针查出来的):
	#   内容(按钮行 64 + 提示行 + 上下 margin)最小高实测 97 > 94 —— PanelContainer 会守住自己的
	#   最小高、【向下】撑破底部锚点(实测栏底 1273 而不是 1270), 于是上面那句"抬进安全区"
	#   抬了个寂寞, 手机 home 手势条照样压着最后 3px。取 max 让底边严格落在安全区内。
	bar.offset_top = -maxf(94.0, bar.get_combined_minimum_size().y) - _bsb
	battle._debug._edit_refresh_brush_highlight()

# ----------------------------------------------------------------------------
#  1) 左右队头像框栏
# ----------------------------------------------------------------------------
func _build_team_panels() -> void:
	if battle._ui_layer == null:
		return
	# 旧栏清掉 (重生/重开安全)
	# ★必须 remove_child 之后再 queue_free —— queue_free 是【延迟到帧末】的:
	#   光 queue_free 的话, 旧栏这一帧还挂在树上, 于是
	#   ① 名字 "TeamPanel_left" 还被占着 → 新栏被 Godot 自动改名(实测变成 @VBoxContainer@566),
	#      任何按名字找它的地方都失效;
	#   ② 旧栏那一帧照样渲染 → 画面上会闪一下【两栏重叠】。
	#   (2026-07-31 加驯服归顺时重建头像栏才暴露出来 —— 以前只在换路时调, 一帧的重影看不见。)
	for _old in [battle._team_panel_left, battle._team_panel_right]:
		if _old != null and is_instance_valid(_old):
			if _old.get_parent() != null:
				_old.get_parent().remove_child(_old)
			_old.queue_free()
	battle._team_panel_left = battle._info_sys._make_team_column("left")
	battle._team_panel_right = battle._info_sys._make_team_column("right")
	battle._ui_layer.add_child(battle._team_panel_left)
	battle._ui_layer.add_child(battle._team_panel_right)

func _make_team_frame(u: Dictionary) -> Control:
	var side = battle._eff_side(u)   # ★有效阵营(驯服归顺的龟按新阵营配色), 不是原 side
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


# ============================================================================
#  窗口尺寸变化时重排 (用户 2026-08-01:「pc端要随便拉，支持全屏」)
# ============================================================================
## 战斗场景是全项目【唯一不接 size_changed 的场景】(主菜单/匹配/选龟都接)。
## 后果: PC 上拉窗口或切全屏后, HUD 还按【进场那一刻】的视口摆 —— PK 条宽度和右上两个键
## 停在旧位置, 而战场画面已经跟着新视口重画了。
##
## ★PK 条【重建】: 它的宽度/安全区逻辑全写在 _build_pk_bar 里, 另写一套"resize 时怎么挪"
##   等于同一份布局知识存两处, 迟早对不上。它有单一根节点 _pk_bar, 重建干净。
## ★右上两键【只重摆不重建】: _build_topright_btns 末尾还会建【投降确认框和日志面板】,
##   整个重建会把那两个面板再建一份(我第一版就是这么写的)。摆位算式抽成 _topright_positions(),
##   建的时候和重摆的时候读同一处, 不会分叉。
func on_viewport_resized() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	if is_instance_valid(_pk_bar):
		var par := (_pk_bar as Node).get_parent()
		if par != null:
			par.remove_child(_pk_bar)
		(_pk_bar as Node).queue_free()
		_pk_bar = null
		_build_pk_bar()
	var pos: Dictionary = _topright_positions()
	if is_instance_valid(_stats_btn):
		(_stats_btn as Control).position = pos["stats"]
	if is_instance_valid(battle._surrender_btn):
		(battle._surrender_btn as Control).position = pos["surrender"]


## 右上角两个键的摆位(按右边缘 + 安全区反算)。★建与重摆共用这一处, 别在两边各算一遍。
func _topright_positions() -> Dictionary:
	var vp: Vector2 = Vector2(battle.get_viewport().get_visible_rect().size)
	var m: Vector4 = SafeArea.margins(vp, 12.0)
	var bw := 52.0
	var sur_x: float = vp.x - bw - m.z          # 最右 = 投降
	var sta_x: float = sur_x - bw - 8.0         # 其左 = 统计
	return {"surrender": Vector2(sur_x, m.y), "stats": Vector2(sta_x, m.y)}
