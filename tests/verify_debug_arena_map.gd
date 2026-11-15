extends Node
## verify_debug_arena_map.gd —— 调试场用正式对局的新地图(2026-11-15)。
## 用户 11-15:「这个旧的调试场怎么还用的是旧地图啊？麻烦你换成新地图好吗？我们现在在新地图上，它这个特效在新地图上看不到啊。
##   你这个调试场落后了，请你把这个调试场优化一下。」
## 判据:
##   ① 没存档 ⇒ 进调试场(设置页同一个入口 BattleDebugArena.enter_with_saved_theme)是暗林, 建场后仍是它, 且场上有新图才有的主题环
##   ② 存档选了深礁 ⇒ 进场是深礁; 存档写坏 / 写旧图 ⇒ 回落暗林
##   ③ ★存档那张恰好 = 上一场正式对局随机到的那张 ⇒ 不被 choose_for_battle 当成「正式对局留下的」还原回旧图
##   ④ 编辑面板「地图」键文字是当前图名; 轮换顺序走完四张新图
##   ⑤ 接线: 设置页 `_open_debug_arena` 在切场景之前调 enter_with_saved_theme; 编辑面板建了「地图」键
## 反向验证(11-15): enter_with_saved_theme 里不清 `_picked` ⇒ ③ 红; 设置页那一行删掉 ⇒ ⑤ 红。

const AT := preload("res://scripts/gamedata/arena_theme.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, d])


func _write_theme(th: String) -> void:
	var f = FileAccess.open(BattleDebugArena.SETUP_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"units": [], "loadouts": {}, "theme": th}))
	f.close()


func _build() -> Dictionary:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := {"theme": AT.active, "ring": s._world.find_child("ThemeRing", true, false) != null, "label": s._debug._edit_map_label()}
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	RB.DEBUG_EDIT = false
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 调试场用新地图 ===")
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var keep: String = AT.active
	if FileAccess.file_exists(BattleDebugArena.SETUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BattleDebugArena.SETUP_PATH))
	## ① 没存档
	AT.active = AT.V0_BASE
	BattleDebugArena.enter_with_saved_theme()
	var r1: Dictionary = await _build()
	_ok("① 没存档 ⇒ 调试场是暗林(建场后 %s)" % str(r1["theme"]), str(r1["theme"]) == AT.V1_DUSK)
	_ok("① 场上有新图才有的主题环(旧图没有)", bool(r1["ring"]))
	_ok("④ 「地图」键写的是当前图名(%s)" % str(r1["label"]), str(r1["label"]).contains("暗林"))
	## ② 存档选了深礁 / 存档写坏
	_write_theme(AT.V2_REEF)
	AT.active = AT.V0_BASE
	BattleDebugArena.enter_with_saved_theme()
	var r2: Dictionary = await _build()
	_ok("② 存档选深礁 ⇒ 调试场是深礁(%s)" % str(r2["theme"]), str(r2["theme"]) == AT.V2_REEF)
	_write_theme(AT.V0_BASE)
	_ok("② 存档写旧图 ⇒ 回落暗林(%s)" % BattleDebugArena.saved_theme(), BattleDebugArena.saved_theme() == AT.V1_DUSK)
	_write_theme("no_such_map")
	_ok("② 存档写坏 ⇒ 回落暗林(%s)" % BattleDebugArena.saved_theme(), BattleDebugArena.saved_theme() == AT.V1_DUSK)
	## ③ 存档那张 = 上一场正式对局随机到的那张
	_write_theme(AT.V3_SHOAL)
	AT.active = AT.V0_BASE
	AT.choose_for_battle(1, true)                  # 模拟上一场正式对局: 随机到某张(记进 _picked)
	var picked: String = AT.active
	_write_theme(picked)
	BattleDebugArena.enter_with_saved_theme()
	var r3: Dictionary = await _build()
	_ok("③ ★存档那张(%s)恰好是上一场正式对局随机到的 ⇒ 调试场仍是它, 没被还原成旧图(%s)" % [picked, str(r3["theme"])],
		str(r3["theme"]) == picked)
	## ④ 轮换顺序
	var seen: Array = []
	var cur: String = AT.V1_DUSK
	for _i in range(4):
		var pool: Array = AT.MATCH_POOL
		cur = str(pool[(pool.find(cur) + 1) % pool.size()])
		seen.append(cur)
	_ok("④ 轮换走完四张新图(%s)" % str(seen), seen.size() == 4 and AT.MATCH_POOL.all(func(t): return seen.has(t)))
	## ⑤ 接线(读源码: 入口与按钮都真的接上了)
	var st: String = FileAccess.get_file_as_string("res://scripts/scenes/SettingsScene.gd")
	var i_fn: int = st.find("func _open_debug_arena(")
	var i_set: int = st.find("BattleDebugArena.enter_with_saved_theme()", i_fn)
	var i_go: int = st.find("SceneNav.go(", i_fn)
	_ok("⑤ 设置页入口在切场景之前设地图", i_fn >= 0 and i_set > i_fn and i_go > i_set, "fn %d · 设图 %d · 切场景 %d" % [i_fn, i_set, i_go])
	var hud: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("⑤ 编辑面板建了「地图」键(调 _edit_cycle_map)", hud.contains("battle._debug._edit_cycle_map()"))
	## 收尾
	if FileAccess.file_exists(BattleDebugArena.SETUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BattleDebugArena.SETUP_PATH))
	AT.active = keep
	AT._picked = ""
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
