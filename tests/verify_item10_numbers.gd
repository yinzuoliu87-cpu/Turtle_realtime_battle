extends Node
## verify_item10_numbers.gd —— 玩家看到的数要等于实际生效的数(2026-10-11 全项目通读第十条)
##   ① 龟壳「储能」资源条的释放提示: 冲击波/护盾 = 储能 × ShellSystem 常量(原来写死 0.40, 常量早改成 0.60)
##   其余小项各自一节。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const InfoPanel := preload("res://scripts/scenes/battle/info_panel.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 通读第十条: 看到的数 = 生效的数 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	# ── ① 龟壳储能释放提示 ──
	var ip = InfoPanel.new(_s)
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c)
	sh["store_energy"] = 100.0
	var hint := ""
	for r in ip._resource_bars(sh):
		if str((r as Dictionary).get("name", "")) == "储能":
			hint = str((r as Dictionary).get("hint", ""))
	_ok("★① 分母: 储能资源条在", hint != "", hint)
	var want_dmg: int = int(100.0 * ShellSystem.RELEASE_DMG_PCT)
	var want_sh: int = int(100.0 * ShellSystem.RELEASE_SHIELD_PCT)
	_ok("★★① 冲击波数 = 储能 × RELEASE_DMG_PCT(%d)" % want_dmg, hint.contains("冲击波 %d" % want_dmg), hint)
	_ok("★① 护盾数 = 储能 × RELEASE_SHIELD_PCT(%d)" % want_sh, hint.contains("护盾 %d" % want_sh), hint)

	# ── ② 选龟界面的等级 = 实战等级(赛季等级 + 临时等级器), 不读养龟站等级(真玩家恒为 1) ──
	var keep_lv: int = GameState.season_level
	var keep_dbg: int = GameState.debug_level
	GameState.debug_level = 0
	GameState.season_level = 6
	_ok("★★② battle_level_for 跟赛季等级走(赛季 6 ⇒ ≥6)", GameState.battle_level_for("basic") >= 6,
		"%d" % GameState.battle_level_for("basic"))
	for f in ["detail_panel", "pet_grid", "skill_picker"]:
		var src := FileAccess.get_file_as_string("res://scripts/scenes/team_select/%s.gd" % f)
		_ok("★★② 选龟 %s 不再读 get_pet_level(养龟站等级, 真玩家恒为 1)" % f,
			src.length() > 100 and not src.contains("GameState.get_pet_level(") and src.contains("battle_level_for("))
	GameState.season_level = keep_lv
	GameState.debug_level = keep_dbg

	# ── ③ 装备小卡标题写「本局」⇒ 数字要是【本局】(已打完的路 + 当前这一路), 不是只有当前这一路 ──
	##   单位字典每换一路重建, `_st_eq` 一路一份; 打完的路在 `_st_lane_hist`(结算页「合计」也是这么加的)。
	var uq: Dictionary = _s._spawn._make_unit("basic", "left", c)
	uq["_st_eq"] = {"p2eq_088": {"heal": 50.0}}
	var keep_hist: Array = _s._st_lane_hist.duplicate()
	_s._st_lane_hist = [{"lane": "top", "left": [{"id": str(uq["id"]), "_st_eq|p2eq_088|heal": 30}], "right": []}]
	var ip3 = InfoPanel.new(_s)
	var txt: String = ip3.eq_stats_text_live(uq, "p2eq_088") if ip3.has_method("eq_stats_text_live") else InfoPanel.eq_stats_text(uq, "p2eq_088")
	_ok("★★③ 上一路回了 30、这一路回了 50 ⇒ 小卡「本局」写 80", txt.contains("80"), txt.replace("
", " / "))
	_s._st_lane_hist = keep_hist

	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
