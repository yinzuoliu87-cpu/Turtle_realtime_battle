extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
var _top_bar = null

## RecordScene — 战绩 (1:1 PoC RecordScene.ts): 总览(总场/胜/负/胜率) + 最近20场.

## 【这一场在哪儿打的】★这张表是**回合制 PoC 的遗产**: 实时版写战绩只写一个 `"实时"`
##   (`RealtimeBattle3DScene.gd:7687` 的 `gs.record_match(..., "实时", ...)`),
##   下面这些键在实时版**一条都命不中**。留着只为老存档里的旧记录不变成空白。
## ★★所以实时版那条**不再显示模式** —— 原来每行右边都写着「实时」:
##   那是个**开发词**(玩家不知道有别的模式), 而且 20 行全是同一个词 = 零信息,
##   正是"日志表格"味的来源。改走 `_report_line()` 的一句人话。
const MODE_LABEL := {"single": "野生", "pve": "野生", "dungeon": "深海闯关", "custom": "切磋",
	"boss": "首领", "boss-pick": "指定首领", "test": "测试"}

const W := 1280.0
const PANEL_W := 760.0

## ══ 战报条的尺寸 ══
##
## ★★2026-09-28 第二轮实拍之后重定(第一轮的毛病是**牌子比内容长太多**):
##   一条战绩里**只有四个事实** —— 胜负 / 自己的阵容 / 打了多久 / 多久之前。
##   查过写入侧 `GameState.record_match()`(`autoload/GameState.gd:1437`) 存的就是
##   `{result, lineup, mode, turn}` 四个键 + 事后补的 `ts`, **没有对手这一维**
##   (没有对手名、没有对手阵容、没有 bot 标记) ⇒ **没有东西可以拿来填那片空白**,
##   而编一句话去填 = 灌水。
## ⇒ 改法是**让留白变成版式**: 牌子不再拉满整栏, 而是**贴着内容收窄 + 居中**。
##   空出来的地方露的是**背景花砖**, 不是一块空金属板 ——
##   空板子在说"这儿本来该有东西", 空背景在说"这是页边距"。
## ★同时把头像从 34 提到 48: 这一屏唯一的游戏美术就是那三只龟,
##   把它放大是**往"游戏味"那头加分**, 不是为了占位。
const ROW_INNER_H := 48.0
const AVATAR_PX := 48.0
const ROW_PAD := 10.0
## 胜负印章的尺寸。★宽 > 40 ⇒ 它**不算**门禁豁免的"角标小签",
##   所以字必须真的稳稳在牌里(见 `_stamp` 的算式)。
const STAMP_W := 52.0
## 【多久之前】和【那一句】各自的定宽。
## ★为什么要钉死: 牌子现在是"贴着内容收窄"的 ⇒ 内容多宽、牌子就多宽。
##   不钉的话「刚刚 · 40 秒拿下」和「3 分钟前 · 还没站稳就倒了」会生出**两种宽度的牌子**,
##   一列下来右边缘参差 = 看着像没对齐。钉死之后整列右边缘是一条直线。
const TIME_W := 56.0
const PHRASE_W := 168.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单 (与图鉴一致)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _ready() -> void:
	_bg()

	# 标题 @ (W/2, 50), 36px #ffd93d stroke #1a1a2e 厚5
	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19)。
	##   原来是「居中大标题 + 左上一个孤零零的圆圈 ←」——
	##   而 146 款触屏游戏的枢纽页里, 返回和页名是**同一条栏里的两个邻居**
	##   (见 `scripts/util/top_bar.gd` 头注的六款实例)。
	_top_bar = TopBar.new(self, {
		## ★★2026-09-28 去掉页名前的 📊(理由与图鉴/背包/设置同, 见 `CodexScene` 那条长注释):
		##   顶栏就是「返回箭头 + 裸页名」, 146 款参考里没有一款给页名挂图标;
		##   而 📊 的字形来自 NotoEmoji, 与这一屏的像素笔触是两套画法。
		"title": "战绩",
		"palette": TopBar.DEEP,
		"width": W,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
	})

	# 总览数据
	var total: int = GameState.battles_total
	var wins: int = GameState.battles_won
	var losses: int = maxi(0, total - wins)
	var rate: int = int(round(float(wins) / total * 100.0)) if total > 0 else 0

	# 主面板 @ (W-PANEL_W)/2, 100, 宽 760
	var panel_x := (W - PANEL_W) / 2.0
	var root := VBoxContainer.new()
	root.position = Vector2(panel_x, 100.0)
	root.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	# ── 总览卡: bg rgba(20,32,40,.82) 边框2px #2e4a5e 圆角12 ──
	var overview := PanelContainer.new()
	var ovsb := StyleBoxFlat.new()
	ovsb.bg_color = Color(20.0 / 255.0, 32.0 / 255.0, 40.0 / 255.0, 0.82)
	ovsb.set_border_width_all(2)
	ovsb.border_color = Color("#2e4a5e")
	ovsb.set_corner_radius_all(12)
	ovsb.content_margin_left = 20; ovsb.content_margin_right = 20
	ovsb.content_margin_top = 16; ovsb.content_margin_bottom = 16
	## 总览卡换金属大框(和背包/图鉴的面板同一张)。冷色底留在 modulate 里 ——
	## 战绩屏整体是冷蓝调, 直接用白 modulate 会跳成暖金。
	var ovtex := UISkin.nine("panel-frame.png", 20, ovsb)
	if ovtex is StyleBoxTexture:
		(ovtex as StyleBoxTexture).modulate_color = Color(0.72, 0.92, 1.12, 1.0)
		(ovtex as StyleBoxTexture).content_margin_left = 20
		(ovtex as StyleBoxTexture).content_margin_right = 20
		(ovtex as StyleBoxTexture).content_margin_top = 16
		(ovtex as StyleBoxTexture).content_margin_bottom = 16
	overview.add_theme_stylebox_override("panel", ovtex)
	overview.custom_minimum_size = Vector2(PANEL_W, 0)
	root.add_child(overview)
	var ovrow := HBoxContainer.new()
	ovrow.add_theme_constant_override("separation", 8)
	overview.add_child(ovrow)
	## ★★2026-09-28 换口语(用户「文字语言也是 ai 味和网页味」):
	##   「总场次」是**后台报表**的词, 「胜/负」是**成绩单**的词。斗龟场里
	##   解说喊的是「出战」「赢」「输」—— 而且和下面每条战报的印章用**同一个字**,
	##   一眼能把总数和明细对上(原来上面写「胜」下面写「胜」还好, 现在统一成「赢」)。
	ovrow.add_child(_stat("出战", str(total), "#ffffff"))
	ovrow.add_child(_stat("赢", str(wins), "#06d6a0"))
	ovrow.add_child(_stat("输", str(losses), "#ff6b6b"))
	ovrow.add_child(_stat("胜率", "%d%%" % rate, "#ffd93d"))

	# 列表标题 "最近对局 (N)" 13px #58d3ff bold
	var n: int = mini(20, GameState.match_history.size())
	var lh := Label.new()
	## ★★2026-09-27 去掉括号计数(后台管理界面的写法)。
	lh.text = "最近对局"
	lh.add_theme_font_size_override("font_size", 13)
	lh.add_theme_color_override("font_color", Color("#58d3ff"))
	## ★★居中(2026-09-28 实拍改的): 战报条改成"贴内容收窄 + 居中"之后,
	##   这个小标题还靠在 760 栏的最左边 ⇒ 它**吊在战报条左边 160px 的空处**,
	##   看着像没对齐。整块列表居中了, 它的标题就得跟着居中。
	lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lh)

	# ── 对局列表 (最多 20), 滚动 ──
	## ★高度 430 → 450: 战报条从 54 长到 68(头像放大), 不补就只剩 5 条露在外面。
	##   450 = 6 条整(6×68 + 5×6 间距 = 438)。★没敢要 470:
	##   实拍量过 root 在 y=100、总览+小标题吃掉 ~140 ⇒ 470 会让列表底边落到 y≈710,
	##   离 720 只剩 10px, 手机底部安全区一压就贴边。450 留 30px。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W, 450)
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if GameState.match_history.is_empty():
		## ★★2026-09-28 换掉「还没有对局记录，去打一场吧！」——
		##   「还没有 X 记录」是**网页空状态**的标准句式(空列表都这么写),
		##   而且它在**说数据库的事**, 不在说斗龟场的事。
		##   改成场子里的说法: 战报是刻在牌子上的, 看台替你记。
		##   ⚠ 这是玩家**第一次点进战绩屏**看到的唯一一句话, 所以要两行:
		##     一行说现状(牌子空着), 一行说该干什么(下去斗一场)。
		var eb := VBoxContainer.new()
		eb.custom_minimum_size = Vector2(PANEL_W, 110)
		eb.alignment = BoxContainer.ALIGNMENT_CENTER
		eb.add_theme_constant_override("separation", 8)
		list.add_child(eb)
		var e1 := Label.new()
		e1.text = "战报牌上还空着"
		e1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e1.add_theme_font_size_override("font_size", 17)
		e1.add_theme_color_override("font_color", Color("#c7b489"))
		eb.add_child(e1)
		var e2 := Label.new()
		e2.text = "下去斗一场，看台自会替你记上第一笔"
		e2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e2.add_theme_font_size_override("font_size", 12)
		e2.add_theme_color_override("font_color", Color("#77889a"))
		eb.add_child(e2)
	else:
		for i in range(n):
			list.add_child(_match_row(GameState.match_history[i]))


# 总览统计块: 数值 30px bold + 标签 12px #9ab
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住。)
	UIFrame.attach(self)
func _stat(label: String, value: String, color: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 30)
	v.add_theme_color_override("font_color", Color(color))
	box.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#99aabb"))
	box.add_child(l)
	return box


## 一条【战报】—— 不是一行日志。
##
## ═══ 2026-09-28 重做的由来 ═══
## 用户:「图鉴，排行榜什么我一点也看不出来游戏的味道，全是 ai 味和网页味，文字语言也是」。
## 战绩屏原来是一条标准的**后台日志行**: `胜 | 头像 | 实时 | 28秒 | 3 分钟前`
##   —— 五个定宽右对齐的栏位, 每栏一个孤零零的值。
## 表格味的三个来源, 逐个拆掉:
##   ① **右对齐的定宽数值栏**(「28秒」「46 宽右对齐」) ⇒ 换成一句话「28 秒拿下」,
##      左对齐、跟在阵容后面, 像解说在说这一场。
##   ② **全 20 行同一个词**的「实时」栏 ⇒ 删掉(见 MODE_LABEL 头注: 那是开发词)。
##   ③ **胜负只靠一个字的颜色** ⇒ 见下面四条形态差异。
##
## ═══ 胜负「一眼分得出」靠的不是红绿 ═══
## ★颜色**不能算一维**: 色盲、缩略图、手机在太阳底下, 红绿都会被抹平。
##   所以赢和输差在**四处形态**上, 任意一处单独看都够用:
##     ① 赢有一块**实心金牌**刻着「赢」(反白暗字); 输只有一个光秃秃的暗字 —— 有牌 / 没牌
##     ② 牌底那块金属板的 modulate: 赢**暖金**(铆钉发亮) / 输**冷灰**(整块压暗)
##     ③ 出战阵容的头像: 赢**全亮** / 输**压暗**(连底色一起暗)
##     ④ 那句话本身: 「28 秒拿下」 / 「撑了 28 秒」
func _match_row(m: Dictionary) -> Control:
	var won: bool = m.get("result", "") == "win"
	var pc := PanelContainer.new()
	## 贴图缺失时的兜底: 直角 + **实心**底(a=1.0) + 只描左边那条胜负色。
	## ★实心 & 只一条边是**故意的** —— 「四边都描边 + 半透底」正是门禁认定的"网页盒",
	##   而那也确实是用户点名的那味。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.098, 0.133, 0.176, 1.0)
	sb.set_corner_radius_all(0)
	sb.border_width_left = 4
	sb.border_color = Color("#ffcf4d") if won else Color("#44566a")
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = ROW_PAD; sb.content_margin_bottom = ROW_PAD
	## ★★换本仓像素皮: 列表行的先例是图鉴(`CodexScene.gd:532` 同一张 `slot-frame.png`,
	##   同一个 margin 12) —— 不另起一套, 免得又多一种长相(memory `fb-hand-rolled-copies-drift`)。
	##   这张 57x57 的板子中心是**平色** #282942(实测 stdev≈1), 四角是金铆钉
	##   ⇒ 横向拉长只是把平色拉长, 铆钉留在角上, 不会出现匹配屏那种"铆钉被拉成细线"。
	## ★胜负走 `modulate_color` 而不是两张图 —— UISkin 铁律②。
	var st := UISkin.nine("slot-frame.png", 12, sb)
	if st is StyleBoxTexture:
		var ts := st as StyleBoxTexture
		ts.modulate_color = Color(1.30, 1.06, 0.60) if won else Color(0.56, 0.63, 0.76)
		## ★内边距 14 > 这张图**画出来的边带**(实测 6px) —— 差一点就会让字骑在铆钉上
		##   (门禁 `verify_ui_consistency` 的 frame 判据量的就是这个, 容差只有 2px)。
		ts.content_margin_left = 14; ts.content_margin_right = 14
		ts.content_margin_top = ROW_PAD; ts.content_margin_bottom = ROW_PAD
	pc.add_theme_stylebox_override("panel", st)
	## ★★**贴着内容收窄 + 居中**, 不再 `EXPAND_FILL` 拉满整栏(2026-09-28 第二轮实拍后改)。
	##   拉满时一条 744 宽的牌子上只有 ~310 的内容, 右边 58% 是**空金属板** ——
	##   空板子读起来是"这儿少了一栏", 而战绩数据里根本没有第五个事实可放
	##   (写入侧只存 result/lineup/mode/turn/ts, 见文件头 ROW_INNER_H 那段)。
	##   收窄之后右边露出来的是**背景花砖** = 页边距, 这才是版式。
	## ★居中(不是左靠): 上面那张总览卡是满宽 760 的, 战报条内缩居中 ⇒
	##   一宽一窄同轴对称; 左靠会在右边留一个偏心的缺口。
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)

	hb.add_child(_stamp(won))

	# 出战的那三只(gap 4)。输了的压暗 —— 形态差异③。
	var avs := HBoxContainer.new()
	avs.add_theme_constant_override("separation", 4)
	hb.add_child(avs)
	for pid in m.get("lineup", []):
		avs.add_child(_avatar(pid, not won))

	## 解说那一句 = 【多久之前】+【这一场怎么打的】, 两段**挨着**、一起左对齐。
	##
	## ★★为什么时间不再是最右边那一栏(实拍之后改的):
	##   原来是 `……阵容 …… 500px 空白 …… 「3 分钟前」` 右对齐定宽 64 ——
	##   **那条右对齐的窄栏正是"日志表格"本身**: 一行里两坨东西各贴一边、中间一片空,
	##   眼睛必须横扫过去对栏位。挪到句子前头就成了一句话:「刚刚 · 28 秒拿下」。
	## ★两个 Label 而不是一个: 时间要更暗更小(它是背景信息, 不是这一场的看点),
	##   一个 Label 只能一个色。挨着放, 读起来仍是一句。
	## ★两段都**定宽**(TIME_W / PHRASE_W): 牌子现在按内容收窄, 不钉宽度的话
	##   「刚刚」的那条会比「3 分钟前」的那条短一截, 整列右边缘参差。
	var phrase := HBoxContainer.new()
	phrase.add_theme_constant_override("separation", 8)
	phrase.custom_minimum_size = Vector2(PHRASE_W, 0)
	hb.add_child(phrase)

	var time_l := Label.new()
	time_l.text = _rel_time(int(m.get("ts", 0)))   # 「刚刚」/「3 分钟前」/「昨天」, 不是时间戳
	time_l.add_theme_font_size_override("font_size", 11)
	time_l.add_theme_color_override("font_color", Color("#9a8f74") if won else Color("#5d6773"))
	time_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_l.custom_minimum_size = Vector2(TIME_W, 0)
	phrase.add_child(time_l)

	var line := Label.new()
	line.text = _report_line(m, won)
	line.add_theme_font_size_override("font_size", 13)
	line.add_theme_color_override("font_color", Color("#ffe3a0") if won else Color("#6f7f8e"))
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phrase.add_child(line)
	return pc


## 胜负印章 —— 形态差异①(**有牌 / 没牌**), 颜色只是附带。
##
## ★为什么赢用"实心金牌 + 反白暗字"而不是"金色的字":
##   缩略图/眯眼看的时候, 一个**字的颜色**会糊掉, 而一**块**色不会。
## ★为什么输**不给牌**: 给一块灰牌等于"两块牌, 颜色不同" —— 又退回只靠颜色。
##   没有牌 = 这一行**少一个东西**, 这才是形态。
## ⚠ 不套九宫格签牌(`chip-frame.png` 源图 48x24): 48x34 要把它竖向拉 2 倍,
##   而且门禁量的边带只有 4px, 16px 的字在 34 高里余量只剩 2px —— 卡在容差上。
##   实心块反而是更地道的像素做法(纯色 + 2px 暗斜面), 且**门禁判据上零风险**。
func _stamp(won: bool) -> Control:
	if not won:
		var l := Label.new()
		l.text = "输"
		l.custom_minimum_size = Vector2(STAMP_W, ROW_INNER_H)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color("#5d6c7d"))
		return l
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffcf4d")             # 实心(a=1.0) ⇒ 不是"网页盒"
	sb.set_corner_radius_all(0)                # 直角
	## 2px 的**右下暗边** = 像素 UI 的斜面。只描两条边 ⇒ 同样不落进"四边描边"那一类。
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color("#8a5a10")
	sb.content_margin_left = 0; sb.content_margin_right = 0
	sb.content_margin_top = 0; sb.content_margin_bottom = 0
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(STAMP_W, ROW_INNER_H)
	var l2 := Label.new()
	l2.text = "赢"
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.add_theme_font_size_override("font_size", 18)
	l2.add_theme_color_override("font_color", Color("#3a2400"))   # 反白: 暗字压在金牌上
	pc.add_child(l2)
	return pc


## 这一场的**一句话**。形态差异④ —— 赢和输连句式都不一样。
##
## ★数字还在(玩家要知道打了多久), 但它长在句子里而不是一个右对齐的栏位里。
## ★实时版只会写 `mode == "实时"`(见 MODE_LABEL 头注), 所以那条是主路径;
##   `else` 那支只伺候老存档里回合制留下的记录。
func _report_line(m: Dictionary, won: bool) -> String:
	var mode := str(m.get("mode", ""))
	var n := int(m.get("turn", 0))
	if mode == "实时" or mode == "":
		if n <= 0:
			return "一照面就拿下" if won else "还没站稳就倒了"
		return ("%d 秒拿下" % n) if won else ("撑了 %d 秒" % n)
	var where := str(MODE_LABEL.get(mode, mode))
	return "%s · 打了 %d 回合" % [where, n]


## 出战的一只。`dim` = 这一场输了 ⇒ 连底色一起压暗(形态差异③)。
func _avatar(pid: String, dim: bool = false) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#070d16") if dim else Color("#0a1422")
	## ★直角 + 纯色块, **不套九宫格金属框** —— 理由 2026-09-28 换过一次, 记清楚:
	##   旧理由(34x34 低于 `UISkin.MIN_FRAME_PX` 40)随头像放大到 48 已经**不成立**了,
	##   而 `detail_views.gd:385` 的 44x44 插槽正是套 `slot-frame` 的先例。
	##   ⇒ 真正拦住它的是**素材**: 量过 30 张头像, 最窄的一张(`angel.png` 218x150)
	##     **四边一格透明都没有**(alpha 包围盒顶满整图)。套框之后 6px 的边带
	##     会直接压在龟脸上 —— 门禁 `verify_ui_consistency` 的 frame 判据当场会红,
	##     而且那不是误报, 实拍也确实糊。★不是"小于阈值", 是"这批图没留边"。
	## ★底色 a=1.0、只有 1px 边 —— 不是"网页盒"。
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = Color("#2a3946") if dim else Color("#6a5a34")
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(AVATAR_PX, AVATAR_PX)
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(AVATAR_PX, AVATAR_PX)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if dim:
		tex.modulate = Color(0.46, 0.52, 0.60)
	var path := "res://assets/sprites/avatars/%s.png" % pid
	if ResourceLoader.exists(path):
		tex.texture = load(path)
	pc.add_child(tex)
	return pc


## 战绩条目的「多久之前」。
##
## ★★2026-09-17 修一个一直没人发现的单位错配: 写入侧存的是【秒】
##   (`RealtimeBattle3DScene.gd:7582` 的 `int(Time.get_unix_time_from_system())`),
##   而这里原来拿【毫秒】去减它(`* 1000.0`) ⇒ 差值恒等于"当前毫秒数"本身,
##   **刚打完的一局会显示「20691 天前」**。玩家存档里 50 条战绩的 ts 全是秒, 实测确认。
## ★所以修的是【读取侧】不是写入侧 —— 改写入侧会让已存的记录全部作废。
## ★阈值也跟着从毫秒改回秒(60 / 3600 / 86400), 只改分子不改分母同样是错的。
## ⚠ 设备时钟往回调会让 d 为负 ⇒ 落到「刚刚」。这是有意的兜底(总比显示负数好);
##   真正的时钟问题在方案书 §8 E1(赛程周界必须由服务端定)。
## ★★2026-09-28 补「昨天」「前天」。玩家嘴里没有「1 天前」「2 天前」这种说法 ——
##   那是**日志的算法**在说话(把秒数除以 86400 再念出来)。
## ⚠ 只补这两档, **上下都不许动**: 门禁 `tests/verify_record_reltime.gd` 逐字断言了
##   「刚刚」/「1 分钟前」/「5 分钟前」/「2 小时前」/「3 天前」/空串 六个串。
##   3 天那条正好压在新加的边界上 —— `d >= 259200` 才落到 `%d 天前`,
##   而测试喂的 `ts - 3*86400` 算出来 d 必 ≥ 259200(now ≥ ts), 所以仍是「3 天前」。
func _rel_time(ts: int) -> String:
	if ts <= 0:
		return ""
	var d := int(Time.get_unix_time_from_system()) - ts
	if d < 60:
		return "刚刚"
	if d < 3600:
		return "%d 分钟前" % int(d / 60.0)
	if d < 86400:
		return "%d 小时前" % int(d / 3600.0)
	if d < 172800:
		return "昨天"
	if d < 259200:
		return "前天"
	return "%d 天前" % int(d / 86400.0)


## 圆形按钮的自绘登记表(见下面 `_paint_round_btn` 的病历)。
var _draw_btns: Array = []


## 按下标重绘一个圆形按钮。★只接受 int 下标 —— 闭包不许捕获节点。
func _paint_round_btn(i: int) -> void:
	if i < 0 or i >= _draw_btns.size():
		return
	var d: Dictionary = _draw_btns[i]
	var n = d.get("n", null)
	if n == null or not is_instance_valid(n):
		return
	var c0: float = float(d["c0"])
	var r: float = float(d["r"])
	(n as Control).draw_circle(Vector2(c0, c0), r, Color(0, 0, 0, 0.55))
	(n as Control).draw_arc(Vector2(c0, c0), r - 1.0, 0, TAU, 32,
		(d["stroke"] as Dictionary)["c"], 2.0)


func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	f.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
	return f


func _stroked_label(t: String, size: int, color: String, stroke: String, thick: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	if thick > 0 and stroke != "":
		l.add_theme_constant_override("outline_size", thick)
		l.add_theme_color_override("font_outline_color", Color(stroke))
	return l




func _bg() -> void:
	# PoC (index.html menu-bg-active): RecordScene 套主菜单 tile bg = menu-bg-tile.png 平铺 (512px repeat)
	#   over 深绿底 #1a3a2a, 上叠暗渐变 ::after rgba(8,12,20,.15→.40). 不是 menu-bg.png 废墟图!
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)   # #1a3a2a 深绿底
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		# PoC CSS background-size:512px → 把 tile 缩到 512² 再平铺
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 漂移 -512→0 / 25s linear 循环 (1:1 PoC menuBgDrift index.html:79/90) — 原静态不动是bug
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := tile.create_tween().set_loops()
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	# ::after 暗渐变遮罩 (顶 alpha.15 → 底 .40)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.15),
		Color(0.031, 0.047, 0.078, 0.25),
		Color(0.031, 0.047, 0.078, 0.40),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)
