extends Node
## _probe_ascend.gd — 天使飞升打包被动实测 (用户 2026-07-28「每次攻击提供5点龟能和1%攻击力」)
##
## 只回答四个问题, 打真数字:
##   ① 选飞升时 _ascend_growth 有没有被绑上? (没绑 = 整条被动死掉, 而且悄无声息)
##   ② 每次普攻命中, base_atk 真的 ×1.01 了吗?
##   ③ 「5点龟能」= 冷却减 5×0.075=0.375 秒 —— 冷却真的在被额外扣吗?
##   ④ 不选飞升的天使【不该】有这个成长 (防止我把它写成了无条件被动)
##
## 跑法: SHIP=1 DL_AUTOFIGHT=1 <godot> --headless --audio-driver Dummy --path . res://tests/_probe_ascend.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SE := preload("res://scripts/systems/skill_energy.gd")
const AS := preload("res://scripts/systems/skills/angel_system.gd")

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 天使飞升打包被动 探针 ===")
	print("  常数: 每命中 +%.0f 龟能(=冷却 -%.3f 秒) / 攻击力 ×%.3f" % [
		AS.ASCEND_ENERGY_PER_HIT, AS.ASCEND_ENERGY_PER_HIT * SE.CD_FACTOR, 1.0 + AS.ASCEND_ATK_PER_HIT])

	# ── 选飞升(idx3) ──
	await _run(gs, 3, true)
	# ── 选平等(idx2): 不该有成长 ──
	await _run(gs, 2, false)

	print("")
	print("  ALL PASS" if _fail == 0 else "  ★ %d 项 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _run(gs, sidx: int, want_growth: bool) -> void:
	_setup(gs, sidx)
	var s = RB.new()
	add_child(s)
	var u := {}
	var w := 0
	while w < 3000 and u.is_empty():
		await get_tree().process_frame
		w += 1
		for x in s._units:
			if str(x.get("id", "")) == "angel" and str(x.get("side", "")) == "left":
				u = x; break
	if u.is_empty():
		print("  [FAIL] 没找到天使"); _fail += 1; s.queue_free(); return

	print("")
	print("  ── 选 skillPool[%d] ──" % sidx)
	var has: bool = bool(u.get("_ascend_growth", false))
	print("     _ascend_growth = %s (期望 %s)" % [has, want_growth])
	_chk("① 打包被动绑定正确", has == want_growth)
	if not want_growth:
		s.queue_free()
		for _i in range(4):
			await get_tree().process_frame
		return

	# ── 手动调 N 次, 隔离出这条被动自己的效果(不受实战随机干扰) ──
	var atk0: float = float(u["base_atk"])
	# ★skill_cd 是【懒初始化】的(_tick_skill_cd 首次跑才建), 而双路要先走完总览/预览才真开打。
	#   在那之前它是空的 —— 直接读会以为"测不了", 那是探针自己的时序问题, 不是产品问题。
	var cds: Dictionary = u.get("skill_cd", {})
	var w2 := 0
	while w2 < 3000 and cds.is_empty():
		await get_tree().process_frame
		w2 += 1
		cds = u.get("skill_cd", {})
	print("     (等了 %d 帧 skill_cd 才建好 —— 双路预演占掉的)" % w2)
	var key := ""
	for k in cds:
		key = str(k); break
	if key == "":
		print("  [FAIL] 等满 3000 帧 skill_cd 仍为空"); _fail += 1; s.queue_free(); return
	cds[key] = 99.0                      # 先把冷却推高, 免得被扣到 0 看不出差
	var cd0: float = float(cds[key])
	var N := 10
	for _i in range(N):
		s._angel_sys._ascend_growth_tick(u)
	var atk1: float = float(u["base_atk"])
	var cd1: float = float(cds[key])
	var want_atk: float = atk0 * pow(1.0 + AS.ASCEND_ATK_PER_HIT, float(N))
	var want_cd: float = cd0 - float(N) * AS.ASCEND_ENERGY_PER_HIT * SE.CD_FACTOR
	print("     调 %d 次后: base_atk %.3f → %.3f (期望 %.3f)" % [N, atk0, atk1, want_atk])
	print("                冷却[%s] %.3f → %.3f (期望 %.3f)" % [key, cd0, cd1, want_cd])
	_chk("② 攻击力每次 ×1.01(乘算叠加)", absf(atk1 - want_atk) < 0.01)
	_chk("③ 冷却每次减 0.375 秒(=5龟能)", absf(cd1 - want_cd) < 0.001)
	print("     → 10 次普攻 = 攻击力 +%.1f%% / 少等 %.2f 秒" % [(atk1 / atk0 - 1.0) * 100.0, cd0 - cd1])

	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _setup(gs, sidx: int) -> void:
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.season_level = 5
	gs.hearts = 8
	gs.season_total_battles = 10
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.season_leaders = ["angel", "basic", "stone"]
	gs.left_team.assign(gs.season_leaders)
	gs.loadouts = {"angel": sidx}
	gs.dual_lineup = {
		"top": [{"kind": "leader", "id": "angel", "slot": 0}, {"kind": "minion", "role": "front"}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "id": "basic", "slot": 1}, {"kind": "leader", "id": "stone", "slot": 2}, {"kind": "minion", "role": "front"}],
	}
	gs.dual_ghost = {
		"schema_ver": 1, "ghost_id": "probe_ascend", "is_bot": false, "bracket": 4,
		"profile": {"name": "探针", "avatar": "angel", "id": "PROBE"},
		"leaders": ["angel", "basic", "stone"],
		"lane_assign": {"top": ["angel"], "bottom": ["basic", "stone"]},
		"minions": {"top": [{"role": "front", "elite": false, "equips": []}, {"role": "front", "elite": false, "equips": []}],
					"bottom": [{"role": "front", "elite": false, "equips": []}]},
		"loadouts": {"angel": sidx}, "equipped": {}, "pet_levels": {},
		"season_total_battles": 10, "season_eggs_killed": 0,
	}
