extends Node
## verify_title_font.gd — 像素标题字(缝合像素 12px; 2026-10-27 前是方舟像素 12px)用法门禁(2026-10-27)
##
## 由来: 方案书 docs/plans/20261027-UI美术规矩.md(用户 2026-10-26「你为什么比不上商业的美术？」⇒ 标题换像素中文标题字)。
##   §3.2 把页名 / 弹框标题 / 整屏大字从「正文字体放大」换成 `UISkin.title_label`。像素字有三个只在实拍里才看得出的坑:
##   · 只在 12 的整数倍字号上不糊; `title_label` 向下取整 ⇒ 调用点写 30 会悄悄变成 24(撞版式下限, 方案书 R2)
##   · 描边不在像素格上 ⇒ 字边一圈半个源像素的黑边。★Godot 的 outline_size 每边只画约 1/4:
##     2026-10-27 实拍量(tests/_shot_title_font.gd + 逐行扫像素): 72 号 outline 14 → 每边 4~5px、outline 24 → 每边 6px;
##     36 号 outline 7 → 每边 2px、outline 12 → 每边 3px ⇒ 每边一个源像素(字号 / 12) = outline_size 取「字号 / 3」
##   · 标题字缺的字没后备就是豆腐块; iOS 上回退链里有 SystemFont 就刷报错。(原来的方舟像素缺项目文案里约 30 个汉字
##     「奖」「徽」「热」…; 2026-10-27 换成缝合像素后汉字全有, 仍缺「≥」「≈」「✓」与 emoji 这类符号)
## 判据:
##   ① 回退链: title_font() 关抗锯齿; 后备里有 NotoSansSC 与 NotoEmoji(与主题链同), 没有 SystemFont
##   ② 屏幕文案快照里的每个字, 标题字 + 后备都画得出(任何一句文案将来拿去当标题都不缺字);
##      尺子自检: 「≥」确实不在标题字本身里(否则「后备补字」这条量的是空); 「奖」标题字本身就有(换缝合像素就为它)
##   ③ 静态: scripts/ 下每个 `UISkin.title_label(x, N)` 的 N(字面量或同文件常量)都是 12 的倍数;
##      分母: 调用点 ≥ MIN_CALLS, 方案书 §3.2 换过的文件个个都有调用点
##   ④ 实建(无头能建的那几屏): 挂着标题字的标签 —— 字号是 12 的倍数; 有描边的, 描边是「字号 / 3」的整数倍;
##      有落影的, 落影偏移是「字号 / 12」的整数倍; 文字里每个字标题字体本身都有(缺字由平滑的后备字补,
##      混在像素标题里一眼看得出 —— 2026-10-27 实拍糖果罐「奖」, 当时的方舟像素没有; 换缝合像素后糖果罐标题 D11 换上了);
##      分母: EXPECT 里每一句都真的挂着标题字被量到
##   ⑤ 尺子自检: 扫描器 / 实建判据各喂一个坏样本必须判红、好样本必须判过
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_title_font.tscn

const SC := preload("res://scripts/scenes/stage_ceremony.gd")
const WCC := preload("res://scripts/scenes/week_close_card.gd")
const ACCT_DEL := preload("res://scripts/scenes/settings/account_delete_dialog.gd")
const BLP := preload("res://scripts/scenes/settings/blocklist_panel.gd")
const SELFCHECK := preload("res://scripts/scenes/settings/selfcheck_panel.gd")
const FB_PANEL := preload("res://scripts/scenes/feedback_panel.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

const SNAP_GD := "res://tests/golden/gd_text_snapshot.txt"
const SKIP_CODES := [0xFE0F, 0xFE0E, 0x200D, 0x200B]
## 方案书 §3.2 换过标题字的文件(分母: 改动真的落地了, 每个文件至少一处调用)
const FILES := [
	"res://scripts/util/top_bar.gd",
	"res://scripts/scenes/MainMenuScene.gd",
	"res://scripts/scenes/battle/settle_screen.gd",
	"res://scripts/scenes/battle/replay_controls.gd",
	"res://scripts/scenes/battle/dual_lane_flow.gd",
	"res://scripts/scenes/battle/topbar_status.gd",
	"res://scripts/scenes/FirstLaunchScene.gd",
	"res://scripts/scenes/tutorial_choice.gd",
	"res://scripts/scenes/version_wall.gd",
	"res://scripts/scenes/MatchmakingScene.gd",
	"res://scripts/scenes/shop/axe_evo_show.gd",
	"res://scripts/scenes/SettingsScene.gd",
	"res://scripts/scenes/settings/account_delete_dialog.gd",
	"res://scripts/scenes/settings/blocklist_panel.gd",
	"res://scripts/scenes/settings/selfcheck_panel.gd",
	"res://scripts/scenes/feedback_panel.gd",
	"res://scripts/scenes/InventoryScene.gd",
	"res://scripts/scenes/inventory/formation_editor.gd",
	"res://scripts/scenes/inventory/candy_jar.gd",
	"res://scripts/scenes/stage_ceremony.gd",
	"res://scripts/scenes/week_close_card.gd",
]
const MIN_CALLS := 30
## ④ 实建时必须挂着标题字被量到的文字
const EXPECT := ["设置", "本周赛程", "积分赛", "闯关赛", "决赛日", "新手教程", "需要更新", "晋级闯关赛！", "积分赛战绩",
	"存档冲突", "重置存档？", "修改昵称", "删除账号", "黑名单", "设备自检", "问题反馈",
	"阵容说明", "站位", "糖果罐 · 第 7 档奖励", "欢迎来到斗龟场", "输入昵称"]

var _n := 0
var _fail := 0
var _tf: FontFile = null
var _call_re := RegEx.create_from_string("UISkin\\.title_label\\(\\s*[^,]+?\\s*,\\s*([^)]+?)\\s*\\)")
var _const_re := RegEx.create_from_string("^const\\s+([A-Z_][A-Z0-9_]*)\\s*(?::\\s*int\\s*)?:?=\\s*(\\d+)\\b")


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	GameState.test_mode = true                 # 实建会开设置页 / 背包, 不许写真存档
	_tf = UISkin.title_font()
	_chain()
	_coverage()
	_static_scan()
	await _runtime()
	_self_check()
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 像素标题字: 回退链 / 12 的倍数 / 描边落在像素格上" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ═══════════════════════════════ ① 回退链 ═══════════════════════════════

func _chain() -> void:
	_ok("★分母: 标题字体载得到", _tf != null)
	if _tf == null:
		return
	_ok("① 标题字关抗锯齿 / 关子像素定位(像素字不糊)", _tf.antialiasing == TextServer.FONT_ANTIALIASING_NONE
		and _tf.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED)
	var names: Array = []
	var sys := 0
	for fb in _tf.fallbacks:
		if fb is SystemFont:
			sys += 1
		elif fb is FontFile:
			names.append(str((fb as FontFile).resource_path.get_file()))
	_ok("① 后备里有 NotoSansSC 与 NotoEmoji", "NotoSansSC-Regular.otf" in names and "NotoEmoji-Regular.ttf" in names, str(names))
	_ok("① 后备里没有 SystemFont(iOS 取不到系统字体, 只会刷 FreeType 报错)", sys == 0, "%d 个" % sys)


# ═══════════════════════════════ ② 缺字有人补 ═══════════════════════════════

## ★`Font.has_char` 连后备一起查(引擎 `Font::_update_rids_fb` 把后备的 RID 都收进来)——
##   第一版拿它判「标题字(当时是方舟像素)自己有没有」, 量出 1385 / 1387 种「自己有」, 「奖」也判成自己有, 尺子自检当场红。
##   ⇒ 「自己有」走 TextServer 只问第 0 个 RID(字体本身); 「画得出」才用 has_char(= 渲染时真实走的整条链)。
func _own(c: int) -> bool:
	var rids: Array = _tf.get_rids()
	return not rids.is_empty() and TextServerManager.get_primary_interface().font_has_char(rids[0], c)


func _covered(c: int) -> bool:
	if c < 0x20 or c in SKIP_CODES:
		return true
	return _tf.has_char(c)


## 符号区(杂项符号 / 装饰符号 U+2600–27BF, 如 ✗ ✓ ★): 标题不放这类字(2026-09-28 起标题里的 emoji / 装饰符都撤了),
##   它们由主题链里的 m6x11 画; 标题链不为它们再挂一个非整数倍的像素字。只打印, 不判红。
func _symbol(c: int) -> bool:
	return c >= 0x2600 and c <= 0x27BF


func _coverage() -> void:
	if _tf == null:
		return
	var chars := {}
	for line in FileAccess.get_file_as_string(SNAP_GD).split("\n"):
		var parts := line.split("|", true, 2)
		if parts.size() == 3:
			for ch in parts[2].replace("\\n", "\n"):
				chars[ch.unicode_at(0)] = true
	_ok("★分母: 屏幕文案快照 ≥ 1000 种字", chars.size() >= 1000, "%d 种" % chars.size())
	var own := 0
	var miss: Array = []
	var sym: Array = []
	var by_fb: Array = []
	for c in chars.keys():
		if _own(int(c)):
			own += 1
		elif not _covered(int(c)):
			(sym if _symbol(int(c)) else miss).append(String.chr(int(c)))
		elif int(c) >= 0x3400:
			by_fb.append(String.chr(int(c)))
	print("    [覆盖] 标题字自己有 %d / %d 种; 靠后备画的 U+3400 以上(汉字 / emoji) %d 个: %s" % [own, chars.size(), by_fb.size(), "".join(by_fb.slice(0, 40))])
	if not sym.is_empty():
		print("    [符号区·不判] 标题链画不出、由主题链 m6x11 画的符号: %s" % "".join(sym))
	_ok("② ★屏幕文案里每个字(符号区除外), 标题字 + 后备都画得出", miss.is_empty(), "缺 %d: %s" % [miss.size(), "".join(miss.slice(0, 20))])
	## 「≥」在屏幕文案里出现过(快照里有), 缝合像素本身没有, 由 NotoSansSC 补(2026-10-27 fontTools 实测)。
	var ge: int = "≥".unicode_at(0)
	_ok("② 尺子自检: 「≥」不在标题字本身里(后备补字这条不是空检查)、但整条链画得出", not _own(ge) and _covered(ge))
	_ok("② 尺子自检: 「赛」标题字本身就有(「自己有」这把尺子不是恒假)", _own("赛".unicode_at(0)))
	_ok("② 「奖」标题字本身就有(方舟像素没有它, 2026-10-27 为此换成缝合像素; 糖果罐标题 D11 靠它)", _own("奖".unicode_at(0)))
	_ok("② 尺子自检: 未分配码位 U+0378 判成缺", not _covered(0x0378))


# ═══════════════════════════════ ③ 静态: 字号写 12 的倍数 ═══════════════════════════════

## 同文件的整数常量表(const NAME := 36 / const NAME: int = 36)
func _consts(src: String) -> Dictionary:
	var out := {}
	for line in src.split("\n"):
		var m := _const_re.search(line.strip_edges())
		if m != null:
			out[m.get_string(1)] = int(m.get_string(2))
	return out


## 一行里的 title_label 调用: 返回 [调用数, 坏的说明列表]
func scan_line(line: String, consts: Dictionary) -> Array:
	var bad: Array = []
	var n := 0
	for m in _call_re.search_all(line):
		n += 1
		var arg := m.get_string(1).strip_edges()
		var v := -1
		if arg.is_valid_int():
			v = int(arg)
		elif consts.has(arg):
			v = int(consts[arg])
		if v < 0:
			bad.append("「%s」既不是字面量也不是同文件常量(读不出字号)" % arg)
		elif v % 12 != 0 or v <= 0:
			bad.append("「%s」= %d 不是 12 的倍数(会被悄悄取整成 %d)" % [arg, v, (v / 12) * 12])
	return [n, bad]


func _gd_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_gd_files(dir.path_join(sub), out)


func _static_scan() -> void:
	var files: Array = []
	_gd_files("res://scripts", files)
	_ok("★分母: scripts/ 下扫到 ≥ 100 个 .gd", files.size() >= 100, "%d 个" % files.size())
	var total := 0
	var per_file := {}
	var bad_all: Array = []
	for p in files:
		var src := FileAccess.get_file_as_string(p)
		if not src.contains("title_label("):
			continue
		var consts := _consts(src)
		var ln := 0
		for line in src.split("\n"):
			ln += 1
			if line.strip_edges().begins_with("#"):
				continue
			var r: Array = scan_line(line, consts)
			if int(r[0]) == 0:
				continue
			total += int(r[0])
			per_file[p] = int(per_file.get(p, 0)) + int(r[0])
			for b in r[1]:
				bad_all.append("%s:%d %s" % [str(p).trim_prefix("res://"), ln, b])
	print("    [静态] title_label 调用 %d 处 / %d 个文件" % [total, per_file.size()])
	for b in bad_all:
		print("    [坏] " + str(b))
	_ok("★分母: title_label 调用点 ≥ %d" % MIN_CALLS, total >= MIN_CALLS, "%d 处" % total)
	_ok("③ ★每个 title_label 的字号都显式写成 12 的倍数(不靠它向下取整)", bad_all.is_empty(), "%d 处" % bad_all.size())
	var missing_files: Array = []
	for f in FILES:
		if not per_file.has(f):
			missing_files.append(str(f).get_file())
	_ok("③ 方案书 §3.2 换过的 %d 个文件个个都有调用点" % FILES.size(), missing_files.is_empty(), str(missing_files))


# ═══════════════════════════════ ④ 实建 ═══════════════════════════════

## 挂着标题字的标签违反了哪条(空串 = 没毛病)。
func bad_label(l: Label) -> String:
	var fs: int = l.get_theme_font_size("font_size")
	if fs <= 0 or fs % 12 != 0:
		return "字号 %d 不是 12 的倍数" % fs
	## ★标题里的字标题字体本身得有: 缺的字由平滑的 NotoSansSC 补, 混在像素标题里一眼看得出
	##   (2026-10-27 实拍: 糖果罐「第 N 档奖励」的「奖」方舟像素没有 —— 那一条因此先没换;
	##   同日换成缝合像素后「奖」本身就有, D11 换上标题字, 见方案书 §8-4)。
	var lack := ""
	for ch in l.text:
		var c: int = ch.unicode_at(0)
		if c > 0x20 and not _own(c):
			lack += ch
	if lack != "":
		return "「%s」标题字体本身没有(会由平滑的后备字补, 混在像素标题里)" % lack
	var ol: int = l.get_theme_constant("outline_size")
	if ol > 0 and ol % (fs / 3) != 0:
		return "%d 号描边 %d 不是 %d 的倍数(每边一个源像素 = 字号/12, outline_size 每边约画 1/4)" % [fs, ol, fs / 3]
	if l.get_theme_color("font_shadow_color").a > 0.0:
		var px: int = fs / 12
		var sx: int = l.get_theme_constant("shadow_offset_x")
		var sy: int = l.get_theme_constant("shadow_offset_y")
		if sx % px != 0 or sy % px != 0:
			return "%d 号落影偏移 (%d, %d) 不是 %d 的倍数" % [fs, sx, sy, px]
	return ""


func _collect(n: Node, out: Array) -> void:
	if n is Label and (n as Label).get_theme_font("font") == _tf:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


var _seen := {}          # 文字 → true(挂着标题字被量到的)
var _bad: Array = []
var _labels := 0
var _ids := {}


func _measure(root: Node, tag: String) -> void:
	var ls: Array = []
	_collect(root, ls)
	for l in ls:
		var lb := l as Label
		if _ids.has(lb.get_instance_id()):
			continue                     # 同一屏量两次(设置页先量重置框再量其余)只算一次
		_ids[lb.get_instance_id()] = true
		_labels += 1
		_seen[lb.text] = true
		var why := bad_label(lb)
		if why != "":
			_bad.append("%s「%s」%s" % [tag, lb.text, why])


func _runtime() -> void:
	if _tf == null:
		return
	## 设置页: 顶栏页名 + 八个弹框
	var s: Node = load("res://scenes/Settings.tscn").instantiate()
	add_child(s)
	await _frames(10)
	## 「重置存档？」与「存档冲突」共用一个 _confirm_layer(开着一个, 另一个直接 return) ⇒ 先量一个、关掉再开另一个
	s._ask_reset()
	await _frames(2)
	_measure(s, "[设置·重置]")
	s._confirm_layer.free()
	s._confirm_layer = null
	s._open_conflict_dialog()
	s._open_rename_dialog()
	ACCT_DEL.open(s, "player@example.com", func() -> void: pass)
	BLP.open(s)
	SELFCHECK.open(s)
	FB_PANEL.open(s)
	await _frames(4)
	_measure(s, "[设置]")
	s.queue_free()
	await _frames(2)
	## 主菜单: 本周赛程页(页名 + 四张阶段卡)
	var mm: Node = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await _frames(10)
	mm._open_week_popup()
	await _frames(2)
	_measure(mm, "[本周赛程]")
	mm.queue_free()
	await _frames(2)
	## 背包: 阵容说明 / 站位 / 糖果罐奖励
	var inv: Node = load("res://scenes/Inventory.tscn").instantiate()
	add_child(inv)
	await _frames(10)
	inv._show_lineup_help()
	inv._formation.open()
	inv._inv_jar._show_jar_reward({"tier": 7, "coins": 120, "xp": 30, "levelers": 1, "equips": []})
	await _frames(4)
	_measure(inv, "[背包]")
	inv.queue_free()
	await _frames(2)
	## 首启: 第一页大标题 + 起名框
	var fl: Node = load("res://scenes/FirstLaunch.tscn").instantiate()
	add_child(fl)
	await _frames(10)
	_measure(fl, "[首启]")
	fl.open_naming()
	await _frames(4)
	_measure(fl, "[起名]")
	fl.queue_free()
	await _frames(2)
	## 散件: 教程选择框 / 版本墙 / 晋级仪式 / 收盘缎带
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	TutorialChoice.open(host, true)
	var vw := VersionWall.new()
	host.add_child(vw)
	SC.play(host, P2.PHASE_RANKED, P2.PHASE_GAUNTLET, "晋级闯关赛！", "", true, func() -> void: pass)
	WCC.open(host, WCC.spec(WCC.KIND_RANKED_IN, GameState, int(Time.get_unix_time_from_system())), func() -> void: pass)
	await _frames(4)
	_measure(host, "[散件]")
	host.queue_free()
	await _frames(2)

	print("    [实建] 挂着标题字的标签 %d 个" % _labels)
	for b in _bad:
		print("    [坏] " + str(b))
	_ok("★分母: 实建量到 ≥ 20 个挂着标题字的标签", _labels >= 20, "%d 个" % _labels)
	var lost: Array = []
	for t in EXPECT:
		if not _seen.has(t):
			lost.append(t)
	_ok("④ ★分母: 这些标题都真的挂着标题字被量到 —— %s" % "、".join(EXPECT), lost.is_empty(), "没量到: %s" % str(lost))
	_ok("④ ★挂着标题字的标签: 字号 12 的倍数 / 描边 = 字号/3 的倍数 / 落影 = 字号/12 的倍数", _bad.is_empty(), "%d 个" % _bad.size())


# ═══════════════════════════════ ⑤ 尺子自检 ═══════════════════════════════

func _self_check() -> void:
	var r1: Array = scan_line("\tUISkin.title_label(t, 30)", {})
	var r2: Array = scan_line("\tUISkin.title_label(t, F_X)", {"F_X": 40})
	var r3: Array = scan_line("\tUISkin.title_label(t, F_Y)", {})
	var r4: Array = scan_line("\tUISkin.title_label(t, 36); UISkin.title_label(u, F_Z)", {"F_Z": 84})
	_ok("⑤ 尺子自检: 扫描器把 30 / 常量 40 / 读不出的常量判红, 把 36 / 常量 84 判过",
		(r1[1] as Array).size() == 1 and (r2[1] as Array).size() == 1 and (r3[1] as Array).size() == 1
		and int(r4[0]) == 2 and (r4[1] as Array).is_empty())
	var l := Label.new()
	l.text = "样本"
	UISkin.title_label(l, 36)
	var good := bad_label(l) == ""
	l.add_theme_constant_override("outline_size", 7)
	var bad_ol := bad_label(l) != ""
	l.add_theme_constant_override("outline_size", 12)
	var good_ol := bad_label(l) == ""
	l.add_theme_font_size_override("font_size", 30)
	var bad_fs := bad_label(l) != ""
	l.add_theme_font_size_override("font_size", 36)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	var bad_sh := bad_label(l) != ""
	l.add_theme_constant_override("shadow_offset_y", 3)
	var good_sh := bad_label(l) == ""
	l.text = "积分 ≥ 100"
	var bad_lack := bad_label(l) != ""
	l.text = "第 7 档奖励"
	var good_jiang := bad_label(l) == ""
	l.free()
	_ok("⑤ 尺子自检: 实建判据把 30 号 / 36 号描边 7 / 36 号落影 4 / 含「≥」判红, 把 36 号描边 12 / 落影 3 / 含「奖」判过",
		good and bad_ol and good_ol and bad_fs and bad_sh and good_sh and bad_lack and good_jiang,
		"good=%s bad_ol=%s good_ol=%s bad_fs=%s bad_sh=%s good_sh=%s bad_lack=%s good_jiang=%s" % [good, bad_ol, good_ol, bad_fs, bad_sh, good_sh, bad_lack, good_jiang])
