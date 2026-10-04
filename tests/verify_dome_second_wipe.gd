extends Node
## verify_dome_second_wipe.gd — 任一方团灭, 那一方的罩子(基地穹顶 / 蛋围栏)都要破(用户 2026-10-04 ③)
##
## 用户原话:「3是一方团灭后罩子破裂，如果另一方因为某种原因团灭了那罩子也要破裂」
##
## ★改前探针实测(本文件改前跑的结果, 方案书 docs/plans/20261004-五件新需求.md §8 ③):
##   第一方团灭 ⇒ 状态切 eggwindow, 而 eggwindow 分支只看计时 ⇒ 第二方之后再团灭, 它的
##   `_egg_fence` 一直是 true / 穹顶缩放一直 1.9 / 蛋双抗还多 200 / 单体索敌锁不到它。
##   同帧双灭: `"left" if la == 0 else "right"` 只处理左边 ⇒ 右边同样不破。
##
## 造法(CLAUDE.md §3.5 / 低帧率教训): 走真实建场入口(蛋只有 _dl_build_lane_field 才会生),
##   直接调 _sim_step 一步一推, 不靠帧数等、不靠演出 tween(穹顶 tween 本身是 sim tween, 按 sim 步喂)。
##   判据量的是【产品自己的状态】: 蛋的 `_egg_fence` / 蛋双抗 / 单体索敌名单 / 穹顶节点的缩放 ——
##   不是我插的标记。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_dome_second_wipe.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DT := 1.0 / 60.0

var _n := 0
var _fail := 0
var s = null
var gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	gs.season_level = 5
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	print("=== 任一方团灭 ⇒ 那一方罩子破 ===")
	s = RB.new()
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	s._deterministic = true      # ★每帧恰一步(就算 _process 插进来也只是确定的一步)
	s.set_process(false)          # 由本测试一步一步喂 sim, 不让帧率掺进来

	# ── 场景 A: 左方被正常打光(_kill) ⇒ 左破; 右方活着 ⇒ 右不破(分母) ──
	await _fresh("A")
	_ok("A0 ★分母: 两方穹顶节点都真的存在", s._base_domes.size() == 2
		and is_instance_valid(s._base_domes.get("left", null)) and is_instance_valid(s._base_domes.get("right", null)),
		"domes=%s" % str(s._base_domes.keys()))
	_ok("A0 ★分母: 开打时两方罩子都在(蛋围栏 true / 穹顶 1.9 / 单体锁不到蛋)",
		_intact("left") and _intact("right"), _desc())
	_wipe("left", "kill")
	_steps(60)
	_ok("A1 左方团灭(_kill) ⇒ 左罩破", _broken("left"), _desc())
	_ok("A2 ★右方没团灭 ⇒ 右罩不破(分母: 右存活 %d)" % s._dl_sys._dl_side_alive("right"),
		_intact("right") and s._dl_sys._dl_side_alive("right") > 0, _desc())
	_ok("A3 状态进 eggwindow, 败方记的是左", s._dl_state == "eggwindow" and s._dl_wiped_side == "left",
		"state=%s wiped=%s" % [s._dl_state, s._dl_wiped_side])

	# ── 场景 B: 左方先团灭, 进 eggwindow 之后右方被 DoT/真伤(_apply_damage)打光 ⇒ 右也破 ──
	await _fresh("B")
	_wipe("left", "kill")
	_steps(5)
	var egg_r: Dictionary = _egg("right")
	var def_r0: float = float(egg_r.get("def", 0.0))
	var mr_r0: float = float(egg_r.get("mr", 0.0))
	_ok("B0 ★前提: 已在 eggwindow 且右罩还在(否则后面是空检查)",
		s._dl_state == "eggwindow" and _intact("right"), _desc())
	_wipe("right", "dot")
	_steps(60)
	_ok("B1 ★★进 eggwindow 之后右方被 DoT 团灭 ⇒ 右罩也破", _broken("right"), _desc())
	_ok("B2 ★右蛋双抗只降一次(恰好 -EGG_FENCE_RES, 再推 60 步也不再降)",
		is_equal_approx(def_r0 - float(egg_r["def"]), s.EGG_FENCE_RES) and is_equal_approx(mr_r0 - float(egg_r["mr"]), s.EGG_FENCE_RES),
		"def %.0f→%.0f mr %.0f→%.0f" % [def_r0, float(egg_r["def"]), mr_r0, float(egg_r["mr"])])
	_ok("B3 败方仍是第一个团灭的左方(第二方破罩不改本路胜负)", s._dl_wiped_side == "left", s._dl_wiped_side)
	_ok("B4 上路不是定局路 ⇒ 第二方也不挂 ×5 承伤 / 自损(与第一方同口径)", not bool(egg_r.get("_egg_final", false)) and not bool(_egg("left").get("_egg_final", false)))
	_steps(60)
	_ok("B5 ★幂等: 再推 60 步双抗不再降", is_equal_approx(def_r0 - float(egg_r["def"]), s.EGG_FENCE_RES),
		"def=%.0f" % float(egg_r["def"]))
	s._dl_sys._dl_drop_fence("right")   # 直接再调一次破罩入口(别的调用方将来也可能调它)
	_ok("B6 ★幂等: 破罩入口被重复调用也不再扣双抗", is_equal_approx(def_r0 - float(egg_r["def"]), s.EGG_FENCE_RES),
		"def=%.0f" % float(egg_r["def"]))

	# ── 场景 C: 右方先被打光, 左方因「反伤/同归于尽」(带来源的 _apply_damage_from, 来源已死)团灭 ⇒ 左也破 ──
	await _fresh("C")
	_wipe("right", "kill")
	_steps(60)
	_ok("C0 ★前提: 右先团灭、左罩还在", _broken("right") and _intact("left"), _desc())
	_wipe("left", "from_dead_src")
	_steps(60)
	_ok("C1 ★★右先灭后左方被(已死来源的)反伤打光 ⇒ 左罩也破", _broken("left"), _desc())

	# ── 场景 D: 同一步双方都团灭 ⇒ 两个罩子都破 ──
	await _fresh("D")
	_wipe("left", "kill")
	_wipe("right", "kill")
	_steps(60)
	_ok("D1 ★★同一步双灭 ⇒ 左罩破", _broken("left"), _desc())
	_ok("D2 ★★同一步双灭 ⇒ 右罩也破", _broken("right"), _desc())

	# ── 场景 E: 最后一个存活的是战斗型召唤物, 它死在 eggwindow 里 ⇒ 那方罩子破 ──
	await _fresh("E")
	_wipe("left", "kill")
	_steps(5)
	var last: Dictionary = {}
	for u in s._units:
		if u.get("alive", false) and str(s._eff_side(u)) == "right" and not u.get("_isEgg", false) and not u.get("is_trainer", false):
			if last.is_empty():
				last = u
			else:
				s._kill(u)
	last["is_summon"] = true
	last["summon_kind"] = "verify_battle_summon"     # 非惰性召唤 ⇒ _dl_side_alive 照算存活
	_steps(5)
	_ok("E0 ★前提: 右方只剩一只战斗型召唤物, 它仍算存活 ⇒ 右罩还在",
		s._dl_sys._dl_side_alive("right") == 1 and _intact("right"), _desc())
	s._kill(last)
	_steps(60)
	_ok("E1 ★最后一只召唤物死 ⇒ 右罩破", _broken("right"), _desc())

	# ── 场景 G: 终极路(定局路) —— 第二方的蛋同样挂 ×5 承伤 + 自损(用户 2026-10-04 拍板 U3-1「要吃」) ──
	await _fresh("G", "final")
	_wipe("left", "kill")
	_steps(5)
	_ok("G0 ★前提: 终极路第一方(左)团灭 ⇒ 左蛋挂定局 buff、右蛋还没挂",
		bool(_egg("left").get("_egg_final", false)) and not bool(_egg("right").get("_egg_final", false)), _desc())
	_wipe("right", "dot")
	_steps(3)
	_ok("G1 ★★终极路第二方(右)也团灭 ⇒ 右蛋也挂 ×5 承伤 + 自损计时", bool(_egg("right").get("_egg_final", false))
		and float(_egg("right").get("_egg_selfloss_next", 1.0e18)) < 1.0e17, _desc())
	_ok("G2 败方仍记先团灭的左方", s._dl_wiped_side == "left", s._dl_wiped_side)

	# ── 场景 F: 换路(重新建场)后罩子复原, 幂等记账不串到下一路 ──
	await _fresh("F")
	_ok("F1 ★换场后两方罩子复原(上一场破过的不残留)", _intact("left") and _intact("right"), _desc())
	_wipe("right", "dot")
	_steps(60)
	_ok("F2 换场后再团灭照样破(幂等记账已清)", _broken("right") and _intact("left"), _desc())

	_done()


## 走真实建场入口开一场新的(蛋只有这条路才会生)
func _fresh(tag: String, lane: String = "top") -> void:
	gs.current_lane = lane
	gs.lane_results = {}
	s._over = false
	s._dl_sys._dl_clear_units()
	## ★清场与建场之间必须隔一帧 —— `_dl_clear_units` 的兜底扫 `_sweep_world_vfx` 会 queue_free
	##   上一路的 MapProps(它建在 _snapshot_world_permanent 之后, 不算常驻), 而 queue_free 要到帧末才生效;
	##   同一帧里建场会看到「MapProps 还在」只复位不重建 ⇒ 帧末穹顶连同 MapProps 一起没了。
	##   真对局的换路中间隔着预览呈现, 不会撞上(DL_AUTOFIGHT 压测路径会撞, 见方案书 §8 ③ 旁注)。
	await get_tree().process_frame
	s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	s._dl_sys._dl_start_fight()
	_steps(2)
	print("  -- 场景 %s: 单位 %d 个" % [tag, s._units.size()])


func _steps(k: int) -> void:
	for _i in range(k):
		s._sim_step(DT, false, false)


func _egg(side: String) -> Dictionary:
	for u in s._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == side:
			return u
	return {}


## 用指定死法把一方打光(蛋/大师不动)
func _wipe(side: String, how: String) -> void:
	var foe_src: Dictionary = {}
	for u in s._units:
		if str(s._eff_side(u)) != side and not u.get("_isEgg", false) and not u.get("is_trainer", false):
			foe_src = u
			break
	for u in s._units:
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(s._eff_side(u)) != side:
			continue
		u["shield"] = 0.0
		match how:
			"kill":
				s._kill(u)
			"dot":
				s._damage._apply_damage(u, int(u["hp"]) + 99999, Color.WHITE, null, "tru", false)
			"from_dead_src":
				if not foe_src.is_empty():
					foe_src["alive"] = false   # 来源已经先死(同归于尽 / 反伤)
				s._damage._apply_damage_from(foe_src, u, int(u["hp"]) + 99999, Color.WHITE, 0.0, true)
		if u.get("alive", false):
			s._kill(u)   # 复活/免伤类兜底: 这里测的是「团灭之后」, 不是谁能扛住


## 罩子破 = 产品自己的三样状态: 蛋围栏 false + 单体索敌锁得到蛋 + 穹顶塌缩(sim tween 按 sim 步喂)
func _broken(side: String) -> bool:
	var e: Dictionary = _egg(side)
	if e.is_empty():
		return false
	var other: String = "right" if side == "left" else "left"
	var lockable: bool = false
	for o in s._targeting._pick_enemies_of_side(other):
		if is_same(o, e):
			lockable = true
	var d = s._base_domes.get(side, null)
	var shrunk: bool = is_instance_valid(d) and (d as Node3D).scale.x < 0.5
	return (not bool(e.get("_egg_fence", true))) and lockable and shrunk


func _intact(side: String) -> bool:
	var e: Dictionary = _egg(side)
	if e.is_empty():
		return false
	var d = s._base_domes.get(side, null)
	return bool(e.get("_egg_fence", false)) and is_instance_valid(d) and (d as Node3D).scale.x > 1.5


func _desc() -> String:
	var out := []
	for side in ["left", "right"]:
		var e: Dictionary = _egg(side)
		var d = s._base_domes.get(side, null)
		out.append("%s: 存活=%d 围栏=%s 双抗=%.0f/%.0f 穹顶=%.2f" % [side, s._dl_sys._dl_side_alive(side),
			str(e.get("_egg_fence", "无蛋")), float(e.get("def", -1)), float(e.get("mr", -1)),
			((d as Node3D).scale.x if is_instance_valid(d) else -1.0)])
	return " | ".join(out) + " | state=" + str(s._dl_state)


func _done() -> void:
	print("")
	print("断言 %d 条" % _n)
	if _fail == 0 and _n >= 23:   # 分母: 23 条断言一条不能少(少了=半路中止)
		print("ALL PASS — 任一方团灭(打光/DoT/反伤/同帧双灭/召唤物最后死) ⇒ 那一方罩子破; 没团灭不破")
	else:
		print("FAIL x%d (断言 %d)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
