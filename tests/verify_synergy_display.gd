extends Node
## verify_synergy_display.gd — 羁绊显示：出战选人页 + 战斗内（2026-08-12）
##
## 方案书 [docs/plans/20260812-羁绊显示.md]。用户：「这两个的话你自己构思一版然后做一版吧」。
##
## ★这里守的是**别的门禁守不住的三件事**：
##   ① **出战页那块显示有没有人调** —— 它的函数与版面槽从 2026-06-23 起就在，
##      只是调用被注释掉了，整整一年半没人发现（"函数存在"守不住"还有没有人调"，
##      memory [[fb-verify-must-run-the-real-path]]）。
##   ② **三处口径是同一份** —— 商店总览条 / 出战页 chips 都走 `GameState.synergy_rows()`，
##      战斗内 chips 走 `_synergy._by_side`。就地手抄一份必然漂
##      （memory [[fb-hand-rolled-copies-drift]]）。
##   ③ **战斗内 chips 的档位逐个对得上** `_by_side` —— 不是"有就行"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_display.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 羁绊显示: 出战页 + 战斗内 ===")

	# ══ ① 出战页: 那块显示【真的有人调】═══════════════════════════════════
	#   ★这一条是本文件的核心。2026-06-23 那次把调用注释掉时写的是"改用 10 类型装备羁绊系统",
	#     但只做了前半句(删), 后半句(接新的)没做 ⇒ 函数在、版面槽在、就是没人调。
	#     "断言函数存在"守不住这个形状, 只能断言【调用点不是注释】。
	var src_ts: String = FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd")
	var called := false
	for ln in src_ts.split("\n"):
		var t: String = (ln as String).strip_edges()
		if t.begins_with("#"):
			continue                       # 注释掉的调用不算数 —— 正是它坑了一年半
		if t.begins_with("func "):
			continue                       # ★函数【定义】那行也含这个名字。第一版漏了这一条,
									   #   反向验证(把调用注释回去)竟然不红 —— 判据形同虚设。
		if t.find("_build_synergy_region()") >= 0:
			called = true
	_ok("① ★出战页的羁绊区【有真调用】(不是被注释掉的那种)", called)
	_ok("① 出战页 chips 走 GameState.synergy_rows()(与商店同一份, 不就地手写)",
		src_ts.find("GameState.synergy_rows()") >= 0)
	_ok("① 换阵容会刷新(_refresh_after_team 与 _refresh_all 两条路都挂了)",
		src_ts.count("_refresh_synergy_chips()") >= 3,
		"实得 %d 处(建 1 + 刷新 2)" % src_ts.count("_refresh_synergy_chips()"))
	var src_shop: String = FileAccess.get_file_as_string("res://scripts/scenes/ShopScene.gd")
	_ok("① ★商店也改用同一份(抽走之后没留一份手抄的在原地)",
		src_shop.find("GameState.synergy_rows()") >= 0
			and src_shop.find('rows.append({"t": t2') < 0)

	# ══ ② synergy_rows 的算法本身 ═════════════════════════════════════════
	#   口径: 只数【装在身上】的 + 按装备 id 去重; need = 距下一档还差几件。
	var ids: Array = GameState.lineup_leader_ids()
	_ok("② ★分母: 阵容里有龟(没有的话下面全是空检查)", not ids.is_empty(),
		"阵容 %d 只" % ids.size())
	if not ids.is_empty():
		GameState.test_mode = true            # ★演示数据绝不许落盘(2026-08-12 污染存档的教训)
		var pid := str(ids[0])
		var saved = GameState.persistent_equipped.get(pid, null)
		# 枪 4 件(首档 3 ⇒ 一档, 距二档差 2) + 同一件重复 2 次(去重后仍算 1)
		GameState.persistent_equipped[pid] = [
			{"id": "p2eq_048", "star": 1}, {"id": "p2eq_050", "star": 1},
			{"id": "p2eq_051", "star": 1}, {"id": "p2eq_052", "star": 1},
			{"id": "p2eq_048", "star": 1},                      # 重复 id: 不该多算
			## ★别拿 p2eq_049 当枪 —— 它是【弓箭】(连发弩)。第一版就这么写的, 门禁当场报
			##   "枪=3 不是 4" 把我的测试数据抓了出来。装备属于哪个类型一律查 data/p2eq-types.json。
		]
		var rows: Array = GameState.synergy_rows()
		var gun := {}
		for r in rows:
			if str(r["t"]) == "枪":
				gun = r
		_ok("② 枪 = 4 件(重复 id 去重后不是 5)", int(gun.get("n", -1)) == 4,
			"实得 %s" % str(gun.get("n", "无")))
		_ok("② 枪已激活到 1 档(首档阈值 3)", int(gun.get("tier", -1)) == 1,
			"实得 %s" % str(gun.get("tier", "无")))
		var tiers_g: Array = (Phase2Types.TYPES["枪"] as Dictionary).get("tiers", [])
		var want_need: int = int(tiers_g[1]) - 4
		_ok("② 距下一档差 %d 件(= 二档阈值 %d − 4)" % [want_need, int(tiers_g[1])],
			int(gun.get("need", -999)) == want_need, "实得 %s" % str(gun.get("need", "无")))
		# 排序: 已激活的排在未激活的前面
		GameState.persistent_equipped[pid].append({"id": "p2eq_049", "star": 1})   # 弓箭 1 件: 未激活, 用来验排序
		var rows2: Array = GameState.synergy_rows()
		_ok("② ★排序: 已激活的排在最前(玩家先看到自己成了什么)",
			rows2.size() >= 2 and int(rows2[0]["tier"]) >= int(rows2[1]["tier"]),
			"前两行 tier = %d / %d" % [int(rows2[0]["tier"]), int(rows2[1]["tier"])])
		if saved == null:
			GameState.persistent_equipped.erase(pid)
		else:
			GameState.persistent_equipped[pid] = saved

	# ══ ③ 战斗内 chips ════════════════════════════════════════════════════
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_s._synergy._by_side = {"left": {"枪": 3, "盾": 1, "食物": 0}, "right": {"法器": 2}}
	var row_l: Control = _s._hud.make_synergy_chip_row("left")
	var row_r: Control = _s._hud.make_synergy_chip_row("right")
	_ok("③ ★我方 chip 数 = 档位>0 的类型数(食物 0 档不该出现)",
		row_l.get_child_count() == 2, "实得 %d 个" % row_l.get_child_count())
	var texts: Array = []
	for c in row_l.get_children():
		texts.append(str((c as Label).text))
	_ok("③ ★档位数字逐个对得上 _by_side(不是'有就行')",
		texts.has("%s3" % Phase2Types.emoji_of("枪")) and texts.has("%s1" % Phase2Types.emoji_of("盾")),
		str(texts))
	_ok("③ 敌方那列读的是 _by_side['right'](不是把我方抄一遍)",
		row_r.get_child_count() == 1
			and str((row_r.get_child(0) as Label).text) == "%s2" % Phase2Types.emoji_of("法器"),
		"实得 %d 个: %s" % [row_r.get_child_count(),
			(str((row_r.get_child(0) as Label).text) if row_r.get_child_count() > 0 else "无")])
	# ★时序(方案书 R4): apply_all 必须在建列之前, 否则建列时读到空 _by_side ⇒ 永远空行
	var src_spawn: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_spawn.gd")
	var i_apply: int = src_spawn.find("_synergy.apply_all()")
	var i_panel: int = src_spawn.find("_build_team_panels()")
	_ok("③ ★时序: spawn 里 apply_all 在 _build_team_panels【之前】(反了就永远是空行)",
		i_apply > 0 and i_panel > i_apply, "apply_all@%d  panels@%d" % [i_apply, i_panel])
	var src_dl: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var j_apply: int = src_dl.find("_synergy.apply_all()")
	var j_panel: int = src_dl.find("_build_team_panels()")
	_ok("③ ★双路换路也是同一顺序", j_apply > 0 and j_panel > j_apply,
		"apply_all@%d  panels@%d" % [j_apply, j_panel])
	row_l.queue_free()
	row_r.queue_free()

	# ══ ④ 换路必须重算档位(2026-08-12 修的真 bug) ═════════════════════════
	#   `apply_all()` 只在 `_by_side` 为空时才算(守卫是给 VFXLAB 注入档位留的),
	#   而换路那段此前**没 clear 过 _synergy**(这个类当时根本没有 clear 方法)
	#   ⇒ 探针实测: 上路 3 枪 / 下路 3 盾, 换路后下路仍是 {"枪":1} —— 带着盾拿不到盾羁绊,
	#     反而白拿一个自己没有的枪羁绊。**每一局的下路与决胜都在这么跑。**
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var g1: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-120, 0))
	g1["equips"] = [{"id": "p2eq_048", "star": 1}, {"id": "p2eq_050", "star": 1},
		{"id": "p2eq_051", "star": 1}]                       # 3 枪
	g1["eq_state"] = {}
	_s._units.clear()
	_s._units.append(g1)
	_s._synergy.clear()
	_s._synergy.apply_all()
	var lane1: Dictionary = (_s._synergy._by_side["left"] as Dictionary).duplicate()
	_ok("④ ★分母: 第一路(3 枪)确实算出了枪羁绊", int(lane1.get("枪", 0)) >= 1, str(lane1))
	var g2: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-120, 0))
	g2["equips"] = [{"id": "p2eq_014", "star": 1}, {"id": "p2eq_015", "star": 1},
		{"id": "p2eq_016", "star": 1}]                       # 换成 3 盾
	g2["eq_state"] = {}
	_s._units.clear()
	_s._units.append(g2)
	_s._synergy.clear()                                      # ← 换路那行
	_s._synergy.apply_all()
	var lane2: Dictionary = (_s._synergy._by_side["left"] as Dictionary)
	_ok("④ ★换路后按【新阵容】重算: 有盾羁绊", int(lane2.get("盾", 0)) >= 1, str(lane2))
	_ok("④ ★★上一路的枪羁绊不许留下(这就是那个 bug 的样子)",
		int(lane2.get("枪", 0)) == 0, "实得 枪=%d" % int(lane2.get("枪", 0)))
	# 源码: 换路那条路真的会 clear(光有 clear 方法没人调 = 没修)
	_ok("④ ★换路代码里 clear() 排在 apply_all() 之前(顺序反了等于没清)",
		src_dl.find("_synergy.clear()") > 0
			and src_dl.find("_synergy.clear()") < src_dl.find("_synergy.apply_all()"))

	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 羁绊显示" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
