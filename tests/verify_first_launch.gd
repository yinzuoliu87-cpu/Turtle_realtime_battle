extends Node

## verify_first_launch.gd — 首启流程 v4(2026-10-21, 方案书 docs/plans/20261020-教程重写.md §v4)
##
## 用户 2026-10-21:「第一次打开你得介绍这个游戏，然后问玩家要不要新手教程吧」。
##   要教程: 介绍 → 问 → 第一战 …… → 起名 → 主菜单(首次只亮「开始战斗」, 按场次逐个点亮)
##   不要:   介绍 → 问 → 起名 → 主菜单(照现在的解锁规则)
## 量(真主菜单 / 真首启那一屏 / 真存档文件):
##   ① 顺序: 新号进主菜单 ⇒ 主菜单一个入口都没建、整屏藏着就换到首启那一屏(不压在主菜单上); 第一页是介绍, 不是问
##   ② 介绍内容: 页数 × 每页秒数 ≤ 20 秒; 每页一句、字数上限、无口语 / 禁用词; 必讲的五件事都讲到
##      (龟队 / 两个战场 + 终极战场 / 碎蛋 / 商店装备 / 每周赛程); 每页背景是真实游戏画面的独立新图(不同文件、不同内容), 只有这一屏用
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
const BANNED := ["啦", "吧", "呢", "哦", "咱", "我教你", "试试", "就行", "搞", "热身", "练练", "!", "！", "你", "等会儿", "开打",
	"；", "——", "…", "对方", "照常", "结算", "实时", "改为"]
## 每页一句的字数上限(Snap / 皇室战争一屏 3~12 词; 我们最长那句「赢两个战场获胜，1 : 1 进入终极战场」)
const MAX_CHARS := 18

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
	var total: float = float(pages.size()) * FLS.PAGE_SEC
	_ok("★分母: 介绍有 2 页以上", pages.size() >= 2, "%d 页" % pages.size())
	_ok("★★整段演示 ≤ 20 秒(用户: 2~4 屏或 ≤20 秒可跳过演示)", total <= 20.0, "%d 页 × %.1f 秒 = %.1f 秒" % [pages.size(), FLS.PAGE_SEC, total])
	_ok("★第一页标题「欢迎来到斗龟场」(用户 10-07 要留)", str(pages[0]["title"]) == "欢迎来到斗龟场")
	var all := ""
	var hashes := {}
	var paths := {}
	for i in range(pages.size()):
		var t := str(pages[i]["text"])
		all += t + "|"
		var tag := "第 %d 页「%s」" % [i + 1, t]
		_ok("%s 一句(无换行、无句号拼第二句)" % tag, t != "" and not t.contains("\n") and t.count("。") == 0)
		var nch: int = t.replace(" ", "").length()   # 字数不算空格(比分写「1 : 1」, 空格是版式不是字)
		_ok("%s ≤ %d 字" % [tag, MAX_CHARS], nch <= MAX_CHARS, "%d 字" % nch)
		var bad: Array = []
		for w in BANNED:
			if t.contains(str(w)) or str(pages[i]["title"]).contains(str(w)):
				bad.append(str(w))
		_ok("%s 无口语 / 禁用词" % tag, bad.is_empty(), str(bad))
		if i > 0:
			_ok("%s 没有第二个标题(每屏一句)" % tag, str(pages[i]["title"]) == "")
		var p := str(pages[i]["img"])
		_ok("%s 背景在 assets/sprites/intro/(介绍专用的新图)" % tag, p.begins_with("res://assets/sprites/intro/"), p)
		var tex = load(p) if ResourceLoader.exists(p) else null
		_ok("%s 背景图载得到且够大(真实画面截图, 不是占位)" % tag, tex is Texture2D and (tex as Texture2D).get_width() >= 1280,
			"%s" % (str((tex as Texture2D).get_size()) if tex is Texture2D else "null"))
		var raw := FileAccess.get_file_as_bytes(p)
		var h := raw.hex_encode().sha256_text() if raw.size() > 0 else ""
		hashes[h] = true
		paths[p] = true
	_ok("★每页背景各是一张(文件不同、内容不同)", hashes.size() == pages.size() and paths.size() == pages.size(),
		"%d 页 / %d 种内容" % [pages.size(), hashes.size()])
	## 必讲的五件事(用户 10-21 列的): 组龟队 / 三路(赢两个战场 · 1:1 终极战场) / 碎蛋 / 商店买装备装到龟身上 / 每周赛程
	for need in [["龟队", "组龟队"], ["两个战场", "赢两路获胜"], ["终极战场", "1:1 进终极战场"], ["蛋", "碎蛋直接获胜"],
			["商店", "商店"], ["装备", "装备"], ["龟身上", "装到龟身上"], ["每周", "每周赛程"]]:
		_ok("★介绍讲到: %s" % need[1], all.contains(str(need[0])))
	## 周赛程三个名字读产品自己的赛制名(不手抄另一份)
	for ph in [P2C.PHASE_RANKED, P2C.PHASE_GAUNTLET, P2C.PHASE_FINALS]:
		_ok("周赛程那一句里有「%s」(= PHASE_LABEL)" % str(P2C.PHASE_LABEL[ph]), all.contains(str(P2C.PHASE_LABEL[ph])))
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
	_ok("★★不点也一页一页走完(顺序 0..N-1)", seen == range(FLS.PAGES.size()), str(seen))
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
	_ok("★点一下 ⇒ 下一页", int(fl2.page_index()) == 1, "page=%d" % int(fl2.page_index()))
	(fl2.find_child(FLS.N_SKIP, true, false) as Button).emit_signal("pressed")
	await _frames(1)
	_ok("★右上「跳过」⇒ 直接问", fl2.is_asking() and fl2.get_node_or_null("TutorialChoice") != null)
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
		await _drop_current()


# ═══════════════════════════════ ⑧ 源码顺序 ═══════════════════════════════

func _source_order() -> void:
	var src := FileAccess.get_file_as_string("res://autoload/tutorial_director.gd")
	var f := src.substr(src.find("func end_tutorial("))
	f = f.substr(0, f.find("\nfunc ", 10))
	var i_save := f.find("GameState.save()")
	var i_nov := f.find("GameState.novice_menu = true")
	_ok("★★novice_menu 在 end_tutorial 的 save() 之后才置位(完成 == 跳过逐字节)", i_save > 0 and i_nov > i_save, "save@%d novice@%d" % [i_save, i_nov])
