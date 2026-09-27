extends Node
## verify_save_guard — 「要渲染的调试台不许改写玩家存档」这条闸。
##
## ★★为什么有它（2026-09-19，做截图巡检时撞出来的）：
##   `GameState` 原来只有一道闸 —— headless 下自动 `test_mode = true`。
##   但 **VFXLAB / 评审台 / 调试场 / 截图台全都必须真渲染 ⇒ 全都不是 headless**，
##   那道闸对它们一条都不生效。
##
##   探针 `tests/_probe_save_pollution.gd` 实证（全新空 `user://`）：
##     不带 NO_SAVE → 场景 `_ready` 时刻 `savegame.json` **已经存在** · test_mode=false
##     带  NO_SAVE → 同一时刻 **不存在** · test_mode=true
##   ⇒ 写入发生在 **autoload `_ready` 的 `ensure_season()`** 里，
##     台子自己在 `_ready` 里置 `test_mode` **永远来不及**。
##   存档目录里那两个 `savegame.json.bak-20260710-被测试污染` /
##   `-20260812-被演示污染` 就是这条已经发生过两次的账。
##
## ★判据走的是**产品自己的两个函数**，四种组合逐个喂：
##   `save_guard_reason(is_headless, has_env, scene_override)` 判、`apply_save_guard(...)` 置、
##   `cmdline_scene_override(args, main_scene)` 认命令行。
##   写成参数注入而不是直接读环境，是为了让门禁能喂第四种组合
##   —— 而不是「门禁自己喂那个字段再去测它」那种恒真式。
##
## ★★**显式登记一个缺口，不静默截断**（CLAUDE.md 的规矩⑤）：
##   端到端那一步（**起一个非 headless 的真进程**，看全新 `user://` 里出不出存档）
##   **在 CI 上跑不了** —— CI 是 ubuntu 无显示器，起不来非 headless 的进程，
##   而一旦 headless，第一道闸就先命中了，这一步等于没测。
##   ⇒ 它只能本地跑，跑法写在下面 `E2E_NOTE` 里，结果记在 CHANGELOG。
##   ★第三道闸（命令行给了 dev 场景路径 ⇒ 自动锁）本地端到端已实证：
##     **不带任何环境变量**、只给场景路径 ⇒ test_mode=true、全新 user:// 里存档 0 个。
##   本门禁覆盖到的是：判据表 + 置位真的发生了 + 常量名没漂。
##   **没覆盖到的**：`_ready` 里喂进去的那两个实参表达式本身
##   （把 `OS.has_environment(NO_SAVE_ENV)` 写死成 `false` 这条门禁不会红）。

const E2E_NOTE := "本地端到端: rm -rf <空目录>; NO_SAVE=1 APPDATA=<空目录> godot --path . " \
	+ "res://tests/_probe_save_pollution.tscn --audio-driver Dummy --position 5000,5000 " \
	+ "⇒ 存档 0 个; 不带 NO_SAVE 的对照组 ⇒ 1 个(这就是分母)"

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	## ★分母：被测对象得真在场。没有这一条，下面全部会因为 gs==null 静默跑不到。
	_ok("① ★分母: GameState autoload 在场", gs != null)
	if gs == null:
		_done()
		return

	## ── ② 判据表：四种组合逐个喂 ──────────────────────────────
	##   ★第四种（不是无头、也没给 NO_SAVE）**必须返回 ""** ——
	##     「挡多了也是错」：真玩家就是这一种，误锁了等于玩家存档再也不保存。
	var DEV := "res://tests/_probe_save_pollution.tscn"
	var cases := [
		[true,  false, "",   "headless", "无头(自动化测试) ⇒ 第一道闸"],
		[true,  true,  DEV,  "headless", "三个都成立 ⇒ 报先命中的那个"],
		[false, true,  "",   "NO_SAVE",  "要渲染的台子显式给了 NO_SAVE ⇒ 第二道闸"],
		[false, false, DEV,  "scene:" + DEV, "★命令行给了 dev 场景 ⇒ 第三道闸(不用任何人记得)"],
		[false, false, "",   "",         "★真玩家在玩 ⇒ 一定不能锁, 否则存档永远不落盘"],
	]
	for c in cases:
		var got: String = gs.save_guard_reason(bool(c[0]), bool(c[1]), str(c[2]))
		_ok("② 判据表 headless=%s env=%s 场景=%s ⇒ %s(%s)" % [str(c[0]), str(c[1]),
			"无" if str(c[2]) == "" else "有", "\"\"" if str(c[3]) == "" else str(c[3]), str(c[4])],
			got == str(c[3]), "实得 %s" % ("\"\"" if got == "" else got))

	## ── ②b 第三道闸自己的判据表: 什么样的命令行算"台子" ──────────
	##   ★★最关键的是**最后一条**: 编辑器 F5 跑的就是主场景, 把它判成台子
	##     等于开发者试玩时存档永远不落盘 ——「挡多了也是错」。
	var MAIN := "res://scenes/MainMenu.tscn"
	var arg_cases := [
		[PackedStringArray([DEV]), DEV, "只给了 dev 场景"],
		[PackedStringArray(["--headless", "--quit-after", "300", DEV]), DEV, "混在别的参数里也认得出"],
		[PackedStringArray([]), "", "没给场景(打包版玩家) ⇒ 不锁"],
		[PackedStringArray(["--fullscreen", "--audio-driver", "Dummy"]), "", "只有普通参数 ⇒ 不锁"],
		[PackedStringArray([MAIN]), "", "★给的就是主场景(编辑器 F5 试玩) ⇒ **不许锁**"],
	]
	for a in arg_cases:
		var got2: String = gs.cmdline_scene_override(a[0] as PackedStringArray, MAIN)
		_ok("②b 命令行判据 %s" % str(a[2]), got2 == str(a[1]),
			"实得 %s" % ("\"\"" if got2 == "" else got2))

	## ── ③ 置位那一步真的发生了（不是只有一个没人调的纯函数）──
	##   ★★钉了产品字段必须还原 —— 本门禁自己是 headless 跑的，
	##     跑完不还原会波及**同一进程里后面的用例**。
	var saved_tm: bool = bool(gs.test_mode)
	gs.test_mode = false
	var r1: String = gs.apply_save_guard(false, true)
	_ok("③ ★apply_save_guard(非无头, 带NO_SAVE) 真把 test_mode 置上了",
		bool(gs.test_mode) == true and r1 == "NO_SAVE", "reason=%s" % r1)

	gs.test_mode = false
	var r2: String = gs.apply_save_guard(false, false)
	_ok("③ ★真玩家那一路**不许**被置上(挡多了也是错)",
		bool(gs.test_mode) == false and r2 == "", "reason=%s" % ("\"\"" if r2 == "" else r2))
	gs.test_mode = saved_tm
	_ok("③ ★分母: 用完已还原 test_mode(否则波及同进程后面的用例)",
		bool(gs.test_mode) == saved_tm, "还原为 %s" % str(saved_tm))

	## ── ④ 常量名没漂：台子传的是字符串 "NO_SAVE"，产品读的是这个常量 ──
	##   两边对不上的话，台子照样会污染存档而这里一条都不红。
	_ok("④ NO_SAVE_ENV 常量 == 台子实际传的环境变量名", str(gs.NO_SAVE_ENV) == "NO_SAVE",
		"实得 %s" % str(gs.NO_SAVE_ENV))

	## ── ⑤ 缺口登记（不是断言通过，是把"没测到什么"打出来）──
	print("  [缺口] 端到端(非 headless 真进程)在 CI 跑不了, 只能本地跑:")
	print("         %s" % E2E_NOTE)
	print("  [缺口] 未覆盖: `_ready` 里喂给 apply_save_guard 的两个实参表达式本身")


	## ══════════════════════════════════════════════════════════════════════
	##  ⑥ ★★★存档写到一半被杀进程 (2026-09-27)
	## ══════════════════════════════════════════════════════════════════════
	## 探针(`tests/_probe_save_torn.gd`)实测原来的行为: 把存档截到 60%(1628→976 字节)
	## 再读 —— 场次/胜场/深海币**一个都没回来**, 而且**一声不吭**, 也没有任何备份。
	## 对测试者就是**一周进度凭空消失**。
	## 根因两条: `save()` 直接覆写(不是原子写); `_load()` 遇到坏 JSON 直接 return。
	## ⇒ 写 `.tmp` → 旧档改名 `.bak` → `.tmp` 改名正式档(改名是原子的);
	##   读档时正式档坏了就回落 `.bak` 并**说出来**。
	print("  ── ⑥ 存档写到一半被杀进程 ──")
	var _tm0: bool = bool(gs.test_mode)
	gs.test_mode = false           ## 本节必须真写盘(跑在独立 APPDATA 里, 碰不到真存档)
	var SP := "user://savegame.json"
	## 存两次: `.bak` 是第二次存档时由旧档改名而来的(真实玩家一周要存几百次)
	gs.season_total_battles = 16
	gs.save()
	gs.season_total_battles = 17
	gs.save()
	_ok("⑥ ★★存完之后 `.tmp` 不许留在盘上(留着 = 下次可能读到半份)",
		not FileAccess.file_exists(SP + ".tmp"))
	_ok("⑥ ★分母: 第二次存档之后 `.bak` 在(不在 = 下面那条是空检查)",
		FileAccess.file_exists(SP + ".bak"))
	var _rf := FileAccess.open(SP, FileAccess.READ)
	var _whole := _rf.get_as_text() if _rf != null else ""
	if _rf != null:
		_rf.close()
	_ok("⑥ ★分母: 正式档本来是完整的", _whole.length() > 200, "%d 字节" % _whole.length())
	var _wf := FileAccess.open(SP, FileAccess.WRITE)
	_wf.store_string(_whole.substr(0, int(_whole.length() * 0.6)))
	_wf.close()
	gs.season_total_battles = -1
	gs._load()
	_ok("⑥ ★★★残档 ⇒ **回落到上一份完整档**(原来是静默当新档开局, 一周进度全丢)",
		int(gs.season_total_battles) == 16, "读回场次 %d" % int(gs.season_total_battles))
	var _da := DirAccess.open("user://")
	if _da != null:
		_da.remove(SP + ".bak")
	gs.season_total_battles = -1
	gs._load()
	_ok("⑥ ★对照: 连备份都没有时**不许**假装读到(那样会把 -1 当成真进度)",
		int(gs.season_total_battles) == -1, "读回场次 %d" % int(gs.season_total_battles))
	gs.test_mode = _tm0

	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 存档保护闸 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 存档保护闸 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
