extends Node

## verify_first_launch.gd — 首启流程 v4(2026-10-21, 方案书 docs/plans/20261020-教程重写.md §v4)
##
## 用户 2026-10-21:「第一次打开你得介绍这个游戏，然后问玩家要不要新手教程吧」。
##   要教程: 介绍 → 问 → 第一战 …… → 起名 → 主菜单(首次只亮「开始战斗」, 按场次逐个点亮)
##   不要:   介绍 → 问 → 起名 → 主菜单(照现在的解锁规则)
## 量(真主菜单 / 真首启那一屏 / 真存档文件):
##   ① 顺序: 新号进主菜单 ⇒ 主菜单一个入口都没建、整屏藏着就换到首启那一屏(不压在主菜单上); 第一页是介绍, 不是问
##   ② 介绍内容(用户 2026-10-21 再改: 只 1 屏 + 问教程): 恰 1 页; 标题「欢迎来到斗龟场」; 那一句逐字 == 用户定稿原句(去掉与标题重复的半句);
##      无口语 / 禁用词; 背景是真实游戏画面的新图; 起名背景固定是赛程那张(不是第 1 张, 那张挂着拍摄账号的名字)
##   ⑨ 赛程挪到教程最后: 教程结束(走完 / 跳过)第一次进主菜单 ⇒ 打开本周赛程页一次, 页上一句赛季说明(用户定稿原句);
##      关掉 ⇒ 页收起、回到主菜单、「开始战斗」可点; 再进主菜单不再弹; 教程沙盒里的主菜单不弹
##   ③ 节奏: 不点也会一页一页走完(按游戏秒喂), 走完 ⇒ 问; 点一下 = 下一页; 右上「跳过」⇒ 直接问
##   ④ 版面(两种比例): 「跳过」在右上、吃 44pt 触摸线、在屏内; 那一句在屏内、不压「跳过」
##   ⑤ 不要教程: 「跳过」⇒ 存档只差 onboarded(起名之前) ⇒ 同一屏出起名框(预填名字); 名字不合规 ⇒ 报错不走;
##      合规 ⇒ 名字落盘、进主菜单、novice_menu=false(照现有解锁规则)
##   ⑥ 新手逐个点亮(novice_menu=true): 0 场只亮「开始战斗」(背包 / 商店 / 图鉴 / 排行榜 / 训龟大师都锁, 底边有原因);
##      点锁着的不换场; 1 场 ⇒ 背包亮; 2 场 ⇒ 全亮; 「开始战斗」被它自己的门拦着时不加新手锁(不许整屏没有能点的)
##   ⑦ 起名只问新玩家: 已看过教程(「?」重玩)/ 已有名字 ⇒ 出口直接回主菜单
##   ⑧ 源码: novice_menu 在 end_tutorial 的 save() 之后才置位(完成 == 跳过逐字节由 verify_tutorial_skip 守)

const MENU := "res://scenes/MainMenu.tscn"
const FL := "res://scenes/FirstLaunch.tscn"
const FLS := preload("res://scripts/scenes/FirstLaunchScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const NM := preload("res://scripts/systems/onboarding/novice_menu.gd")
const SAVE := "user://savegame.json"
## 口语词(verify_tutorial_choice 同一张) + 文案门禁 copy_lol_style_lint 的禁用词里与这几句相关的几个
## ★「你」2026-10-21 移出: 用户定稿原句「在这里，你将组建……」就用「你」(教程战斗 C1「你的龟」同样), 是书面第二人称不是口语。
const BANNED := ["啦", "吧", "呢", "哦", "咱", "我教你", "试试", "就行", "搞", "热身", "练练", "!", "！", "等会儿", "开打",
	"；", "——", "…", "对方", "照常", "结算", "实时", "改为"]
## 用户 2026-10-21 定稿原句(「欢迎来到斗龟场！在这里，……」): 标题已是「欢迎来到斗龟场」, 那一句是后半。★逐字, 不许改。
const MANDATED_TITLE := "欢迎来到斗龟场"
const MANDATED_TEXT := "在这里，你将组建一支由 3 只龟组成的队伍，为它们搭配装备、安排站位，与其他玩家的队伍自动对战。"
const MANDATED_WEEK := "斗龟场每周是一个赛季：周二到周五是积分赛，周六是闯关赛，周日是决赛日，争夺本周冠军。每到周一，所有人从同一起点重新开始。"
const FT := preload("res://scripts/systems/onboarding/first_tips.gd")

var _fail := 0
var _n := 0
const MIN_ASSERTS := 60


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	OS.set_environment("ONBOARD", "")
	var ovr0: int = P2C.now_override_ts
	P2C.now_override_ts = _ts_on(2)       # 周二: 积分赛日, 「开始战斗」开着
	_static_content()
	await _order_and_pages()
	await _layout(Vector2i(1280, 720))
	await _layout(Vector2i(1560, 720))
	await _skip_path()
	await _novice_menu()
	await _naming_only_for_new()
	await _week_not_in_tutorial()
	_source_order()
	P2C.now_override_ts = ovr0
	GameState.test_mode = true
	print("  (共 %d 条断言 · 跑了 %d 帧)" % [_n, Engine.get_process_frames()])
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d) —— 有协程被半路掐断" % [_n, MIN_ASSERTS])
	print("ALL PASS — 首启流程 v4: 介绍 → 问 → (教程) → 起名 → 主菜单逐个点亮" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _ts_on(iso_dow: int) -> int:
	var now := int(Time.get_unix_time_from_system())
	var anchor: int = P2C.week_anchor_utc(now)
	return anchor + (iso_dow - 1) * 86400 + 12 * 3600


func _fresh(onboarded: bool) -> void:
	GameState.reset_save()
	GameState.onboarded = onboarded
	GameState.nickname = ""
	GameState.novice_menu = false
	GameState.tutorial_active = false
	GameState.first_tips_seen = {}         # reset_save 不清它(账号侧首次提示); 每段从「都没看过」起
	GameState.battles_total = 0
	GameState.season_total_battles = 0
	GameState.hearts = P2C.HEARTS_MAX


func _cur() -> Node:
	return get_tree().current_scene


func _drop_current() -> void:
	var cs := _cur()
	if cs != null and cs != self:
		get_tree().current_scene = null
		cs.queue_free()
		await _frames(2)


## 把一个场景实例当成 current_scene 挂上(模拟换场), 返回它。
func _mount(path: String) -> Node:
	await _drop_current()
	var n: Node = load(path).instantiate()
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	await _frames(2)
	return n


# ═══════════════════════════════ ② 介绍内容(静态) ═══════════════════════════════

func _static_content() -> void:
	print("  ── ② 介绍内容 ──")
	var pages: Array = FLS.PAGES
	_ok("★★介绍恰 1 屏(用户 10-21: 只 1 屏介绍, 然后问教程)", pages.size() == 1, "%d 页" % pages.size())
	if pages.is_empty():
		return
	_ok("★停留 ≤ 20 秒(可跳过演示上限)", float(pages.size()) * FLS.PAGE_SEC <= 20.0, "%.1f 秒" % (float(pages.size()) * FLS.PAGE_SEC))
	_ok("★标题「欢迎来到斗龟场」(用户 10-07 要留)", str(pages[0]["title"]) == MANDATED_TITLE, str(pages[0]["title"]))
	_ok("★★那一句逐字 == 用户 10-21 定稿原句", str(pages[0]["text"]) == MANDATED_TEXT, str(pages[0]["text"]))
	_ok("★标题 + 那一句 = 定稿全句(「欢迎来到斗龟场！」+ 后半)", "%s！%s" % [str(pages[0]["title"]), str(pages[0]["text"])]
		== "欢迎来到斗龟场！在这里，你将组建一支由 3 只龟组成的队伍，为它们搭配装备、安排站位，与其他玩家的队伍自动对战。")
	var bad: Array = []
	for w in BANNED:
		if str(pages[0]["text"]).contains(str(w)) or str(pages[0]["title"]).contains(str(w)):
			bad.append(str(w))
	_ok("那一屏无口语 / 禁用词", bad.is_empty(), str(bad))
	for i in range(pages.size()):
		var p := str(pages[i]["img"])
		_ok("第 %d 屏背景在 assets/sprites/intro/(介绍专用的新图)" % (i + 1), p.begins_with("res://assets/sprites/intro/"), p)
		var tex = load(p) if ResourceLoader.exists(p) else null
		_ok("第 %d 屏背景图载得到且够大(真实画面截图, 不是占位)" % (i + 1), tex is Texture2D and (tex as Texture2D).get_width() >= 1280,
			"%s" % (str((tex as Texture2D).get_size()) if tex is Texture2D else "null"))
	var nb = load(FLS.NAME_BG) if ResourceLoader.exists(FLS.NAME_BG) else null
	_ok("★起名背景固定是赛程那张(intro-5-week), 载得到", FLS.NAME_BG.ends_with("intro-5-week.jpg") and nb is Texture2D)
	_ok("★起名背景不是第 1 屏那张(那张挂着拍摄账号的名字)", FLS.NAME_BG != str(pages[0]["img"]))
	## 赛季说明那一句(赛程挪到教程最后): 逐字 == 定稿; 里面的赛制名 = PHASE_LABEL; 星期 = phase_of_weekday
	_ok("★★赛程说明逐字 == 用户 10-21 定稿原句", FT.text_for(FT.FIRST_WEEK) == MANDATED_WEEK, FT.text_for(FT.FIRST_WEEK))
	for ph in [P2C.PHASE_RANKED, P2C.PHASE_GAUNTLET, P2C.PHASE_FINALS]:
		_ok("赛程说明里有「%s」(= PHASE_LABEL)" % str(P2C.PHASE_LABEL[ph]), MANDATED_WEEK.contains(str(P2C.PHASE_LABEL[ph])))
	_ok("★赛程说明的星期与代码一致(周一休赛 / 周二~五积分赛 / 周六闯关赛 / 周日决赛日)",
		P2C.phase_of_weekday(1) == P2C.PHASE_REST and P2C.phase_of_weekday(2) == P2C.PHASE_RANKED and P2C.phase_of_weekday(5) == P2C.PHASE_RANKED
		and P2C.phase_of_weekday(6) == P2C.PHASE_GAUNTLET and P2C.phase_of_weekday(7) == P2C.PHASE_FINALS)
	## 介绍图只在这一屏用(不复用到别处, 也没借别处的图)
	var hits := _grep_refs("assets/sprites/intro/")
	_ok("★介绍图只被首启那一屏引用", hits.size() == 1 and str(hits[0]).ends_with("FirstLaunchScene.gd"), str(hits))


func _grep_refs(needle: String) -> Array:
	var out: Array = []
	for dir in ["res://scripts", "res://autoload", "res://scenes"]:
		_walk(dir, needle, out)
	return out


func _walk(dir: String, needle: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			var p := dir.path_join(f)
			if FileAccess.get_file_as_string(p).contains(needle):
				out.append(p)
	for sub in d.get_directories():
		_walk(dir.path_join(sub), needle, out)


# ═══════════════════════════════ ① 顺序 + ③ 节奏 ═══════════════════════════════

func _order_and_pages() -> void:
	print("  ── ① 顺序 / ③ 节奏 ──")
	GameState.test_mode = true
	_fresh(false)
	await _drop_current()
	var m: Node = load(MENU).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	var built_entries := false
	var shown := false
	for _i in range(60):
		if is_instance_valid(m):
			if m.get("page_box") != null:
				built_entries = true
			if m.visible:
				shown = true
		var cs := _cur()
		if cs != null and str(cs.scene_file_path) == FL:
			break
		await get_tree().process_frame
	var fl := _cur()
	_ok("★★新号进主菜单 ⇒ 换到首启那一屏", fl != null and str(fl.scene_file_path) == FL, str(fl.scene_file_path) if fl != null else "null")
	_ok("★★换场前主菜单一个入口都没建(不压在主菜单上)", not built_entries)
	_ok("★换场前主菜单整屏藏着(不闪一帧主菜单)", not shown)
	if fl == null or str(fl.scene_file_path) != FL:
		return
	_ok("★第一眼是介绍第 1 页, 不是问", int(fl.page_index()) == 0 and not fl.is_asking() and fl.get_node_or_null("TutorialChoice") == null)
	_ok("第 1 页标题 / 那一句在屏上", _label_text(fl, FLS.N_TITLE) == "欢迎来到斗龟场" and _label_text(fl, FLS.N_CAPTION) == str(FLS.PAGES[0]["text"]))
	## 不点: 按游戏秒一步一步喂(不靠机器快慢)
	fl.set_process(false)
	var seen: Array = [int(fl.page_index())]
	var t := 0.0
	while t < 30.0 and not fl.is_asking():
		fl._process(0.1)
		t += 0.1
		if int(fl.page_index()) != int(seen[-1]):
			seen.append(int(fl.page_index()))
	_ok("★★不点也会走完(只 1 屏)", seen == [0], str(seen))
	_ok("★★走完 ⇒ 问「开始教程 / 跳过」", fl.is_asking() and fl.get_node_or_null("TutorialChoice") != null)
	_ok("★走完用时 ≤ 20 游戏秒", t <= 20.0 + 0.11, "%.1f 秒" % t)
	_ok("问的时候「跳过」(介绍)与那一句收起", not (fl.find_child(FLS.N_SKIP, true, false) as Control).visible and not _label_visible(fl, FLS.N_CAPTION))
	## 点一下 = 下一页 / 右上「跳过」= 直接问
	var fl2: Node = await _mount(FL)
	fl2.set_process(false)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	fl2._gui_input(ev)
	await _frames(1)
	_ok("★点一下 ⇒ 问(只 1 屏)", fl2.is_asking() and fl2.get_node_or_null("TutorialChoice") != null, "page=%d" % int(fl2.page_index()))
	var fl3: Node = await _mount(FL)
	fl3.set_process(false)
	(fl3.find_child(FLS.N_SKIP, true, false) as Button).emit_signal("pressed")
	await _frames(1)
	_ok("★右上「跳过」⇒ 直接问", fl3.is_asking() and fl3.get_node_or_null("TutorialChoice") != null)
	await _drop_current()


func _label_text(root: Node, nm: String) -> String:
	var l := root.find_child(nm, true, false) as Label
	return l.text if l != null else ""


func _label_visible(root: Node, nm: String) -> bool:
	var l := root.find_child(nm, true, false) as Label
	return l != null and l.is_visible_in_tree()


# ═══════════════════════════════ ④ 版面 ═══════════════════════════════

func _layout(sz: Vector2i) -> void:
	print("  ── ④ 版面 %dx%d ──" % [sz.x, sz.y])
	get_tree().root.size = sz
	await _frames(2)
	var fl: Node = await _mount(FL)
	fl.set_process(false)
	await _frames(2)
	var vp := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
	for i in range(FLS.PAGES.size()):
		if i > 0:
			fl.advance()
			fl._process(1.0)     # 淡入走完
			await _frames(1)
		var sk := (fl.find_child(FLS.N_SKIP, true, false) as Control).get_global_rect()
		var cap := (fl.find_child(FLS.N_CAPTION, true, false) as Control).get_parent() as Control
		var cr := cap.get_global_rect()
		var tag := "[%dx%d 第 %d 页]" % [sz.x, sz.y, i + 1]
		_ok("%s「跳过」在屏内、右上、≥ 81 高(44pt)" % tag, vp.encloses(sk) and sk.get_center().x > vp.size.x * 0.75
			and sk.get_center().y < vp.size.y * 0.25 and sk.size.y >= 81.0, str(sk))
		_ok("%s 那一句在屏内、不压「跳过」、不顶满屏宽" % tag, vp.encloses(cr) and not cr.intersects(sk) and cr.size.x < vp.size.x - 32.0, str(cr))
		var capl := fl.find_child(FLS.N_CAPTION, true, false) as Label
		_ok("★%s 那一句折成两行(限宽折行, 不是一长条也不是三行)" % tag, capl != null and capl.get_line_count() == 2, "%d 行" % (capl.get_line_count() if capl != null else -1))
		if i == 0:
			var tr := (fl.find_child(FLS.N_TITLE, true, false) as Control).get_global_rect()
			_ok("%s 标题在屏内、不压那一句" % tag, vp.encloses(tr) and not tr.intersects(cr), str(tr))
	await _drop_current()
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)


# ═══════════════════════════════ ⑤ 不要教程 ═══════════════════════════════

func _skip_path() -> void:
	print("  ── ⑤ 不要教程: 跳过 → 起名 → 主菜单 ──")
	_fresh(false)
	GameState.test_mode = false            # 量真存档文件(run-tests 每测试一份独立 user://)
	GameState.save()
	GameState._load()
	GameState.save()
	var a := FileAccess.get_file_as_bytes(SAVE)
	_ok("分母: 存档写出来了", a.size() > 200)
	var fl: Node = await _mount(FL)
	fl.skip_intro()
	await _frames(1)
	var ch: Node = fl.get_node_or_null("TutorialChoice")
	_ok("分母: 选择框在", ch != null)
	if ch == null:
		GameState.test_mode = true
		return
	(ch.find_child("SkipTutorial", true, false) as Button).emit_signal("pressed")
	await _frames(3)
	var want := a.get_string_from_utf8().replace("\"onboarded\": false", "\"onboarded\": true")
	_ok("★★「跳过」⇒ 存档只差 onboarded(起名之前, 一个别的字节都没写)", FileAccess.get_file_as_bytes(SAVE).get_string_from_utf8() == want)
	_ok("★★「跳过」⇒ 同一屏出起名框(起名 → 主菜单)", _cur() == fl and fl.is_naming() and fl.find_child(FLS.N_NAME_BOX, true, false) != null)
	var ed := fl.find_child(FLS.N_NAME_EDIT, true, false) as LineEdit
	_ok("★起名框预填了名字(Snap 04:37 那样)", ed != null and P2C.nickname_valid(ed.text), ed.text if ed != null else "")
	var ok_btn := fl.find_child(FLS.N_NAME_OK, true, false) as Control
	_ok("「确认」吃 44pt 触摸线", ok_btn != null and ok_btn.get_global_rect().size.y >= 81.0)
	var err: String = fl.confirm_name("")
	await _frames(2)
	_ok("★名字为空 ⇒ 报错、不走", err != "" and _cur() == fl and _label_text(fl, FLS.N_NAME_STATUS) == err, err)
	var nm: String = P2C.nickname_suggest("")
	err = fl.confirm_name(nm)
	var mm: Node = null
	for _i in range(60):
		await get_tree().process_frame
		mm = _cur()
		if mm != null and str(mm.scene_file_path) == MENU:
			break
	_ok("★★合规名字 ⇒ 进主菜单", err == "" and mm != null and str(mm.scene_file_path) == MENU, err)
	var js = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_ok("★★名字写进账号存档(盘上)", js is Dictionary and str(js.get("nickname", "")) == P2C.nickname_clean(nm), str(js.get("nickname", "")) if js is Dictionary else "?")
	_ok("★不要教程 ⇒ novice_menu=false(照现在的解锁规则)", js is Dictionary and not bool(js.get("novice_menu", true)))
	await _frames(40)
	if mm != null and is_instance_valid(mm):
		_ok("★不要教程 ⇒ 主菜单只有商店自己的锁(没有新手锁)", _novice_reasons(mm).is_empty(), str(_novice_reasons(mm)))
		_ok("主菜单不再进首启", str(_cur().scene_file_path) == MENU)
		await _week_once(mm, "跳过教程")
	GameState.test_mode = true
	await _drop_current()


## 主菜单上贴着的锁原因(入口名 → 原因), 商店那句「首战后解锁」也算 —— 调用方自己挑。
func _reasons(mm: Node) -> Dictionary:
	var out := {}
	for l in mm.find_children("LockReason", "Label", true, false):
		var holder: Node = (l as Node).get_parent()
		var name_txt := ""
		for c in holder.get_children():
			if c is Label and c != l:
				name_txt = (c as Label).text
				break
		out[name_txt] = (l as Label).text
	return out


func _novice_reasons(mm: Node) -> Dictionary:
	var r := _reasons(mm)
	r.erase("商店")
	return r


# ═══════════════════════════════ ⑥ 新手逐个点亮 ═══════════════════════════════

func _novice_menu() -> void:
	print("  ── ⑥ 新手逐个点亮(novice_menu) ──")
	GameState.test_mode = true
	_fresh(true)
	GameState.novice_menu = true
	var m := await _menu_child()
	var r := _reasons(m)
	print("    [0 场] 锁: %s" % str(r))
	for e in ["背包", "商店", "图鉴", "排行榜", "训龟大师"]:
		_ok("★★0 场: 「%s」锁着、底边有原因" % e, r.has(e) and str(r[e]) != "", str(r.get(e, "")))
	_ok("★★0 场: 只亮「开始战斗」", not bool(m.get("_hero_locked")))
	_ok("0 场: 原因文案 = 首战后解锁 / 2 场后解锁", str(r.get("背包", "")) == NM.reason_text(1) and str(r.get("图鉴", "")) == NM.reason_text(2))
	## 点锁着的背包: 不换场(飘原因)
	var cur0 := _cur()
	var sq := m.find_child("Sq_背包", true, false)
	var b: Button = sq.find_children("*", "Button", true, false)[0] if sq != null else null
	if b != null:
		b.emit_signal("pressed")
	await _frames(3)
	_ok("★点锁着的「背包」⇒ 不换场", b != null and is_instance_valid(m) and _cur() == cur0)
	m.queue_free()
	await _frames(2)
	## 1 场: 背包亮(商店照它自己的规矩: 本大轮首战后)
	GameState.battles_total = 1
	GameState.season_total_battles = 1
	m = await _menu_child()
	r = _reasons(m)
	print("    [1 场] 锁: %s" % str(r))
	_ok("★1 场 ⇒ 背包 / 商店亮", not r.has("背包") and not r.has("商店"), str(r))
	_ok("★1 场 ⇒ 图鉴 / 排行榜 / 训龟大师仍锁(2 场后解锁)", str(r.get("图鉴", "")) == NM.reason_text(2) and r.has("排行榜") and r.has("训龟大师"), str(r))
	m.queue_free()
	await _frames(2)
	GameState.battles_total = 2
	m = await _menu_child()
	r = _reasons(m)
	_ok("★2 场 ⇒ 全亮", r.is_empty(), str(r))
	m.queue_free()
	await _frames(2)
	## 「开始战斗」被它自己的门拦着(出局)⇒ 不加新手锁
	GameState.battles_total = 0
	GameState.season_total_battles = 0
	GameState.hearts = 0
	m = await _menu_child()
	r = _novice_reasons(m)
	_ok("★分母: 出局 ⇒「开始战斗」锁着", bool(m.get("_hero_locked")))
	_ok("★★「开始战斗」锁着时不加新手锁(不许整屏没有能点的)", r.is_empty(), str(r))
	m.queue_free()
	await _frames(2)
	## 跳过教程的号(novice_menu=false)0 场: 只有商店那条既有的锁
	_fresh(true)
	m = await _menu_child()
	_ok("★novice_menu=false ⇒ 0 场也没有新手锁", _novice_reasons(m).is_empty(), str(_novice_reasons(m)))
	m.queue_free()
	await _frames(2)


func _menu_child() -> Node:
	var m: Node = load(MENU).instantiate()
	add_child(m)
	await _frames(40)
	return m


# ═══════════════════════════════ ⑦ 起名只问新玩家 ═══════════════════════════════

func _naming_only_for_new() -> void:
	print("  ── ⑦ 起名只问新玩家 ──")
	var td = get_node("/root/TutorialDirector")
	GameState.test_mode = true
	for c in [["新号没名字", false, "", FL], ["已看过教程(「?」重玩)", true, "", MENU], ["已有名字", false, "龟龟队长", MENU]]:
		_fresh(bool(c[1]))
		GameState.nickname = str(c[2])
		td.enter(null)
		var fake := Node.new()
		fake.scene_file_path = "res://scenes/Inventory.tscn"
		await _drop_current()
		get_tree().root.add_child(fake)
		get_tree().current_scene = fake
		td.end_tutorial("completed")
		var got := ""
		for _i in range(60):
			await get_tree().process_frame
			var cs := _cur()
			if cs != null and cs != fake and str(cs.scene_file_path) != "":
				got = str(cs.scene_file_path)
				break
		_ok("★%s ⇒ 完成教程后去 %s" % [c[0], str(c[3]).get_file()], got == str(c[3]), got)
		if got == FL:
			_ok("  且直接是起名框", _cur().is_naming())
			_ok("★走完教程的新号 ⇒ novice_menu=true(内存, 随起名那一次存档落盘)", bool(GameState.novice_menu))
			var bg := _cur().get("_bg_a") as TextureRect
			_ok("★走完教程来起名: 背景是赛程那张(NAME_BG)", bg != null and bg.texture != null and bg.texture.resource_path == FLS.NAME_BG,
				bg.texture.resource_path if bg != null and bg.texture != null else "null")
			var err: String = _cur().confirm_name(P2C.nickname_suggest(""))
			var mm: Node = null
			for _j in range(60):
				await get_tree().process_frame
				mm = _cur()
				if mm != null and str(mm.scene_file_path) == MENU:
					break
			_ok("分母: 起名后进了主菜单", err == "" and mm != null and str(mm.scene_file_path) == MENU, err)
			if mm != null and str(mm.scene_file_path) == MENU:
				await _frames(40)
				await _week_once(mm, "走完教程")
		await _drop_current()


# ═══════════════════════════════ ⑨ 赛程挪到教程最后 ═══════════════════════════════

func _week_text(mm: Node) -> String:
	var l := mm.find_child("WeekIntroText", true, false) as Label
	return l.text if l != null and l.is_visible_in_tree() else ""


## mm = 教程结束(走完 / 跳过)后第一次落到的真主菜单(当前场景)。
func _week_once(mm: Node, tag: String) -> void:
	var pop := mm.find_child("WeekPopup", true, false) as Control
	if pop == null:
		pop = mm.get("_week_pop") as Control
	_ok("★★%s ⇒ 第一次进主菜单就打开本周赛程页" % tag, pop != null and pop.is_visible_in_tree())
	_ok("★★%s ⇒ 页上那一句 == 用户定稿原句" % tag, _week_text(mm) == MANDATED_WEEK, _week_text(mm))
	var cap := mm.find_child("WeekIntroCaption", true, false) as Control
	var lab := mm.find_child("WeekIntroText", true, false) as Label
	_ok("%s: 说明折两行、放在顶栏里(不压四张卡)" % tag, cap != null and lab != null and lab.get_line_count() == 2
		and cap.position.y >= 0.0 and cap.position.y + cap.size.y <= float(mm.WEEK_BAR_H), str(Rect2(cap.position, cap.size)) if cap != null else "null")
	if lab != null and lab.get_line_count() == 2:
		## 第一行恰好到第一个句号(赛制一行, 周一重开一行): 第二行 == 「每到周一……」
		var first_line_w: float = lab.get_theme_font("font").get_string_size(lab.text.substr(0, lab.text.find("。") + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, lab.get_theme_font_size("font_size")).x
		_ok("%s: 说明在句号处折行(第一句一整行)" % tag, first_line_w <= lab.size.x and first_line_w + 40.0 > lab.size.x, "第一句宽 %.0f / 行宽 %.0f" % [first_line_w, lab.size.x])
	if cap != null:
		var title := mm.find_child("WeekPopupTitle", true, false) as Control
		## 页名标签框比字宽(360), 量字本身占的那一段
		var tl := title as Label
		var tw: float = tl.get_theme_font("font").get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tl.get_theme_font_size("font_size")).x if tl != null else 0.0
		var title_ink := Rect2(tl.get_global_rect().position, Vector2(tw + 16.0, tl.size.y)) if tl != null else Rect2()
		_ok("%s: 说明不压页名「本周赛程」(字 + 描边)" % tag, tl != null and tw > 0.0 and not cap.get_global_rect().intersects(title_ink), "说明 %s / 页名字 %s" % [str(cap.get_global_rect()), str(title_ink)])
	_ok("%s: 记成看过(first_tips_seen)" % tag, bool(GameState.first_tips_seen.get(FT.FIRST_WEEK, false)))
	_ok("%s: 弹着赛程时不同时出「开始战斗」那条提示(一次一件事)" % tag, mm.get_node_or_null(FT.NODE_NAME) == null)
	## 关掉(左上返回键那一个函数)⇒ 回到主菜单
	mm._close_week_popup()
	await _frames(3)
	_ok("★★%s: 关掉 ⇒ 页收起、说明收起" % tag, pop != null and not pop.is_visible_in_tree() and mm.find_child("WeekIntroCaption", true, false) == null)
	var hero: Control = mm.get("_hero_btn")
	_ok("★%s: 关掉后「开始战斗」在、没被盖住(压暗块收起)" % tag, hero != null and hero.is_visible_in_tree()
		and not (mm.get("_week_dim") as Control).is_visible_in_tree())
	_ok("%s: 关掉后才出「开始战斗」那条首次提示" % tag, mm.get_node_or_null(FT.NODE_NAME) != null)
	## 再进主菜单: 不再弹
	var m2: Node = await _mount(MENU)
	await _frames(40)
	var pop2 := m2.get("_week_pop") as Control
	_ok("★★%s: 再进主菜单不再弹赛程页(每个账号一次)" % tag, pop2 != null and not pop2.is_visible_in_tree() and _week_text(m2) == "")


## 教程沙盒里(tutorial_active)当前场景是主菜单 ⇒ 不弹。
func _week_not_in_tutorial() -> void:
	print("  ── ⑨ 教程沙盒里不弹赛程 ──")
	GameState.test_mode = true
	_fresh(true)
	GameState.first_tips_seen = {}
	GameState.tutorial_active = true
	var m: Node = await _mount(MENU)
	await _frames(40)
	var pop := m.get("_week_pop") as Control
	_ok("分母: 赛程页建出来了", pop != null)
	_ok("★★教程中(沙盒)的主菜单不弹赛程页", pop != null and not pop.is_visible_in_tree() and _week_text(m) == "")
	_ok("★教程中不记成看过", not bool(GameState.first_tips_seen.get(FT.FIRST_WEEK, false)))
	GameState.tutorial_active = false
	await _drop_current()
	## 反面对照: 同样的号出了沙盒(0 场、没看过)⇒ 弹(证明上面那条不是因为别的原因没弹)
	var m2: Node = await _mount(MENU)
	await _frames(40)
	_ok("★对照: 出了沙盒同一个号 ⇒ 弹", _week_text(m2) == MANDATED_WEEK)
	await _drop_current()
	## 老号(累计打过)升级上来 ⇒ 不补弹
	_fresh(true)
	GameState.battles_total = 3
	var m3: Node = await _mount(MENU)
	await _frames(40)
	_ok("★老号(累计 3 场)不补弹赛程页", _week_text(m3) == "" and not bool(GameState.first_tips_seen.get(FT.FIRST_WEEK, false)))
	await _drop_current()


# ═══════════════════════════════ ⑧ 源码顺序 ═══════════════════════════════

func _source_order() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/tutorial_director.gd")
	var f := src.substr(src.find("func end_tutorial("))
	f = f.substr(0, f.find("\nfunc ", 10))
	var i_save := f.find("GameState.save()")
	var i_nov := f.find("GameState.novice_menu = true")
	_ok("★★novice_menu 在 end_tutorial 的 save() 之后才置位(完成 == 跳过逐字节)", i_save > 0 and i_nov > i_save, "save@%d novice@%d" % [i_save, i_nov])
