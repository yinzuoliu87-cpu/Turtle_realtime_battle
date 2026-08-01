extends Node
## 赛博龟死亡齐射不得【主动锁】训龟大师 —— 用户 2026-08-02:
##   「赛博龟被动浮球跑在死亡时射击为什么会锁训龟大师？」
##
## 项目规矩(用户 2026-07-22/23): 训龟大师【不被主动索敌】, 但【照吃 AOE 波及】。
## 原因: 赛博死亡齐射当初就地手写了一段选靶循环, 只判 敌对/存活/龟蛋围栏,
##   漏了 is_trainer 和 untargetable_until。★根因是"手写选靶"这件事本身 ——
##   排除规则会随需求增加, 抄一次就永远落后一次。
##
## ★本用例走【真入口】(_cyber_assemble_mech), 不是去断言 _nearest_enemy_from 存在 ——
##   "断言函数存在" 守不住 "还有没有人调它"(memory: fb-verify-must-run-the-real-path)。
##   判据是齐射时记下的同步证据 battle._dbg_salvo_picks(每门炮实际锁到谁)。
var _n := 0
var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond: _fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])

func _ready() -> void:
	await get_tree().process_frame
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for i in range(40):
		await get_tree().process_frame

	# ── 干净合成单位(memory: fb-ci-vs-local-divergence —— 拿随机 spawn 单位测精确值会 CI 偶发红)
	s._units.clear()
	var ctr: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var cyber := _mk(s, "left", ctr + Vector2(-40, 0), false)
	cyber["drone_n"] = 3
	cyber["_drones"] = []
	for k in range(3):
		var sp := Sprite3D.new()
		s._world.add_child(sp)
		cyber["_drones"].append({"spr": sp})
	# 大师【就在最近处】; 真正的龟放远一倍 —— 漏排除的实现必然锁大师
	var master := _mk(s, "right", ctr + Vector2(0, 0), true)
	var real_foe := _mk(s, "right", ctr + Vector2(460, 0), false)
	s._units.append_array([cyber, master, real_foe])
	_ok("★分母: 大师(%.0f 码)确实比真敌(%.0f 码)近" % [
		cyber["pos"].distance_to(master["pos"]), cyber["pos"].distance_to(real_foe["pos"])],
		cyber["pos"].distance_to(master["pos"]) < cyber["pos"].distance_to(real_foe["pos"]))

	# ── ① 选靶层
	var pick = s._targeting._nearest_enemy_from(cyber, cyber["pos"])
	_ok("① _nearest_enemy_from 跳过训龟大师(返回真敌)",
		pick != null and not pick.get("is_trainer", false),
		"锁到 %s" % ("大师" if (pick != null and pick.get("is_trainer", false)) else ("真敌" if pick != null else "null")))

	# ── ② 真入口: 跑一次死亡齐射, 看每门炮实际锁了谁
	s._dbg_salvo_picks.clear()
	s._cyber_sys._cyber_assemble_mech(cyber)
	var w := 0
	while w < 900 and s._dbg_salvo_picks.is_empty():
		await get_tree().process_frame     # 墙钟无关: 齐射走 _pending_shots(sim 驱动)
		w += 1
	var picks: Array = s._dbg_salvo_picks
	var n_tr := 0
	for x in picks:
		if str(x) == "trainer": n_tr += 1
	_ok("★分母: 齐射真的选了靶(N>0, 不是空检查)", picks.size() > 0, "N=%d 门炮选靶" % picks.size())
	_ok("② ★真入口(_cyber_assemble_mech): 没有任何一门炮锁到训龟大师",
		n_tr == 0, "%d/%d 门锁了大师" % [n_tr, picks.size()])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 赛博死亡齐射不锁大师" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

## ★用 battle._spawn._make_unit 造单位, 不要手糊字典 —— 手糊的缺字段, sim 每帧刷 SCRIPT ERROR
##   (第一版实测 589 条致命报错; 门禁的致命正则正是干这个的)。
func _mk(s, side: String, pos: Vector2, trainer: bool) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit("green", side, pos)
	u["maxHp"] = 3000.0; u["hp"] = 3000.0
	u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["_home_pos"] = pos
	if trainer:
		u["is_trainer"] = true
	return u
