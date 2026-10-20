extends Node

## verify_tutorial_battle_short.gd — 教程那一把战斗: 两路直接获胜、够短(方案书 docs/plans/20261020-教程重写.md
##   验收清单「教程战斗缩短到必赢且两路结束」)。
##
## ★★规则与正式对局完全一致(用户 10-20): 教程里**不许改任何对局规则**(不补小将这类「教程专用规则」= 教错玩家)。
##   只调教程沙盒里的**开局配置数据**: 教学阵容 `FIXED_TEAM` / 练习对手快照 `make_weak_ghost()`。
##
## 量(全走真入口: 导演 enter → 选龟屏那几行 → next_scene_after → 真战斗场景从开场演出打到结算):
##   ① 多次真跑(3 种选龟顺序 × 2 个种子 = 6 次; 选龟顺序决定谁去下路战场): 每次都是我方赢上路 + 下路(不进终极战场)
##   ② 每次两路开打到打完的游戏秒 ≤ FIGHT_BUDGET_SEC(整条教程 ≤ 3 分钟的战斗份额; 其余是 13 次点按与开场演出)
##   ③ ★★对手每路仍按正式规则补到 3 个单位(统领 + 小将): 场上真数 == 正式规整函数 `_foe_normalize_lane` 的输出
##   ④ ★★静态: 正式的规整 / 对手取阵 / 分路结算函数体里没有任何教程分支(反向: 塞一个 ⇒ 红)
##   分母: 真跑了 N 次 / 每次真进了开打 / 每路场上真有敌方单位

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TB := preload("res://scripts/systems/onboarding/tutorial_buff.gd")
const TD := preload("res://autoload/tutorial_director.gd")
const BK := preload("res://scripts/net/backend.gd")
const SEEDS := [20261020, 777]
## 两路合计的开打时长上限(游戏秒)。整条教程 3 分钟 = 180 秒: 13 次点按(每步读 1.5 秒)约 49 秒 + 两路开场演出约 25 秒
##   (10-20 实录 时间轴.txt) ⇒ 两路真打的份额 ≤ 100 秒。
const FIGHT_BUDGET_SEC := 100.0
const FRAME_CAP := 40000
## 正式规则函数: 体内不许出现教程字样
const RULE_FUNCS := {
	"res://scripts/scenes/RealtimeBattle3DScene.gd": ["_foe_normalize_lane", "_dual_foe_lane"],
	"res://scripts/scenes/battle/dual_lane_flow.gd": ["_dl_flow_check", "_dl_lane_over", "_dl_finish"],
}
const TUT_WORDS := ["tutorial", "Tutorial", "教程", "教学"]

var _fail := 0
var _n := 0
const MIN_ASSERTS := 40


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	## 导演的出口 `end_tutorial` 会把「不是主菜单」的当前场景换成主菜单 ⇒ 本测试挪到根上常驻,
	##   当前场景换成一个挂着主菜单路径的空节点(出口看到已在主菜单就不换场)。
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	var dummy := Node.new()
	dummy.scene_file_path = "res://scenes/MainMenu.tscn"
	root.add_child(dummy)
	get_tree().current_scene = dummy
	OS.set_environment("FAST_SIM", "1")
	_static_rules()
	var td = get_node("/root/TutorialDirector")
	var team: Array = td.FIXED_TEAM
	var orders: Array = [[0, 1, 2], [1, 2, 0], [2, 0, 1]]
	var runs := 0
	var worst := 0.0
	for o in orders:
		for sd in SEEDS:
			var pick: Array = []
			for i in o:
				pick.append(str(team[int(i)]))
			var r: Dictionary = await _run(td, pick, int(sd))
			if r.is_empty():
				continue
			runs += 1
			worst = maxf(worst, float(r["fight"]))
	await _formal()
	OS.set_environment("FAST_SIM", "")
	OS.set_environment("TURTLE_SEED", "")
	_ok("★分母: 真跑了 %d 次(3 种选龟顺序 × %d 个种子)" % [runs, SEEDS.size()], runs == orders.size() * SEEDS.size())
	print("  最长一次两路开打 %.1f 游戏秒(上限 %.0f)" % [worst, FIGHT_BUDGET_SEC])
	print("  (共 %d 条断言)" % _n)
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少 %d)" % [_n, MIN_ASSERTS])
	print("ALL PASS — 教程战斗: 两路直接获胜 / 够短 / 对手照正式规则补小将" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 一次: 导演进沙盒 → 选龟屏那几行(写 left_team / season_leaders) → 武装教学战斗 → 真战斗打到结算。
func _run(td: Node, pick: Array, sd: int) -> Dictionary:
	var tag := "%s/种子%d" % ["·".join(pick), sd]
	print("  ── %s(下路战场: %s) ──" % [tag, pick[2]])
	td.enter(null)
	var lt: Array[String] = []
	for p in pick:
		lt.append(str(p))
	GameState.left_team = lt
	GameState.left_slots = ["s0", "s1", "s2"] as Array[String]
	GameState.season_leaders = lt.duplicate()
	GameState.reset_dual_lane()
	var nxt: String = td.next_scene_after("team_select")
	_ok("分母 %s: 导演把教学战斗武装好了" % tag, nxt == td.BATTLE and str(GameState.dual_ghost.get("ghost_id", "")) == "tutorial_weak")
	OS.set_environment("TURTLE_SEED", str(sd))
	var s = RB.new()
	add_child(s)
	var fr := 0
	var fight_t := 0.0
	var lane_t0 := -1.0
	var lanes_seen := {}
	var foe_ok := true
	var foe_detail := ""
	var buff_l := 0
	var buff_bad: Array = []
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
		var st := str(s._dl_state)
		var lane := str(GameState.current_lane)
		if st == "fight" and not lanes_seen.has(lane):
			lanes_seen[lane] = true
			lane_t0 = float(s._t)
			## ③ 开打那一刻数场上敌方: 必须 == 正式规整函数对同一份快照的输出
			var want: Array = s._dual_foe_lane(lane)
			var lead := 0
			var mini := 0
			for u in s._units:
				if str(u.get("side", "")) == "right" and bool(u.get("alive", false)) and not bool(u.get("_isEgg", false)) \
						and not bool(u.get("is_summon", false)) and not bool(u.get("is_trainer", false)):
					if bool(u.get("_isMinion", false)):
						mini += 1
					else:
						lead += 1
			var want_lead := 0
			for w in want:
				if str((w as Dictionary).get("kind", "")) == "leader":
					want_lead += 1
			for u in s._units:
				if not bool(u.get("alive", false)) or bool(u.get("is_trainer", false)):
					continue
				var has: bool = bool(u.get(TB.MARK, false))
				if str(u.get("side", "")) == "left":
					buff_l += 1
					if not has or float(u.get("damage_amp", 0.0)) < TD.TUTORIAL_DMG_AMP - 1e-6 or float(u.get("damage_reduction", 0.0)) < TD.TUTORIAL_DR - 1e-6:
						buff_bad.append("%s 我方 %s 没带" % [lane, str(u.get("id", "?"))])
				elif has:
					buff_bad.append("%s 敌方 %s 带了" % [lane, str(u.get("id", "?"))])
			foe_detail += "%s: 场上 统领%d+小将%d / 正式规整 %d 单位(统领%d) · " % [lane, lead, mini, want.size(), want_lead]
			if want.size() != 3 or mini != want.size() - want_lead or lead != want_lead:
				foe_ok = false
		if lane_t0 >= 0.0 and st != "fight" and st != "eggwindow":
			fight_t += float(s._t) - lane_t0
			lane_t0 = -1.0
	if lane_t0 >= 0.0:
		fight_t += float(s._t) - lane_t0
	var res: Dictionary = (GameState.lane_results as Dictionary).duplicate()
	_ok("分母 %s: 真打到了结算(%d 帧)" % [tag, fr], str(s._dl_state) == "done", "state=%s" % str(s._dl_state))
	_ok("分母 %s: 两路都真开打过" % tag, lanes_seen.has("top") and lanes_seen.has("bottom"), str(lanes_seen.keys()))
	_ok("★★%s: 对手每路照正式规则补到 3 单位(统领 + 小将)" % tag, foe_ok and lanes_seen.size() >= 2, foe_detail)
	_ok("★★%s: 教程加成 我方全员带、敌方不带(我方 %d 个)" % [tag, buff_l], buff_bad.is_empty() and buff_l >= 6, str(buff_bad))
	_ok("★★%s: 我方赢上路战场 + 下路战场" % tag, str(res.get("top", "")) == "left" and str(res.get("bottom", "")) == "left", str(res))
	_ok("★★%s: 没进终极战场" % tag, not lanes_seen.has("final") and not res.has("final"), str(res))
	_ok("★%s: 两路开打合计 ≤ %.0f 游戏秒" % [tag, FIGHT_BUDGET_SEC], fight_t > 5.0 and fight_t <= FIGHT_BUDGET_SEC, "%.1f 秒" % fight_t)
	s.queue_free()
	for _i in range(5):
		await get_tree().process_frame
	td.end_tutorial("abandoned")
	return {"fight": fight_t}


## ⑤ 正式对局(导演不在教程中, 普通对手快照): 任何单位都不带教程加成。
func _formal() -> void:
	print("  ── 正式对局 ──")
	var td = get_node("/root/TutorialDirector")
	_ok("分母: 导演不在教程中", not td.is_active() and not TB.active())
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	GameState.left_team.assign(["basic", "stone", "bamboo"])
	GameState.dual_lineup = {}
	GameState.get_dual_lineup()
	GameState.reset_dual_lane()
	GameState.dual_active = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	GameState.dual_ghost = BK.make_bot(4, rng)
	OS.set_environment("TURTLE_SEED", "4242")
	var s = RB.new()
	add_child(s)
	var fr := 0
	while fr < 3000 and str(s._dl_state) != "fight":
		await get_tree().process_frame
		fr += 1
	await get_tree().process_frame
	var n := 0
	var hit: Array = []
	for u in s._units:
		if not bool(u.get("alive", false)):
			continue
		n += 1
		if bool(u.get(TB.MARK, false)):
			hit.append("%s %s" % [str(u.get("side", "")), str(u.get("id", ""))])
	_ok("分母: 正式对局真开打了、场上有单位", str(s._dl_state) == "fight" and n >= 6, "state=%s n=%d" % [str(s._dl_state), n])
	_ok("★★正式对局: 任何单位都不带教程加成", hit.is_empty(), str(hit))
	var en := 0
	for u in s._units:
		if str(u.get("side", "")) == "left" and bool(u.get("alive", false)):
			en += 1
	_ok("★★正式对局: 没有「教程加成」签", s.get_node_or_null(TB.BADGE_NAME) == null and en > 0)
	s.queue_free()
	for _i in range(5):
		await get_tree().process_frame


## ④ 正式规则函数体里没有教程分支。反向: 往任何一个里塞一行 `if TutorialDirector...` ⇒ 红。
func _static_rules() -> void:
	for path in RULE_FUNCS.keys():
		var src := FileAccess.get_file_as_string(path)
		for fn in RULE_FUNCS[path]:
			var body := _func_body(src, str(fn))
			_ok("分母: 找到正式规则函数 %s" % fn, body.length() > 80, "%d 字" % body.length())
			var hit := ""
			for w in TUT_WORDS:
				if body.find(w) >= 0:
					hit = w
			_ok("★★%s 体内没有教程分支" % fn, hit == "", "出现「%s」" % hit)


func _func_body(src: String, fn: String) -> String:
	var i := src.find("\nfunc %s(" % fn)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 6)
	return src.substr(i, (j - i) if j > 0 else -1)
