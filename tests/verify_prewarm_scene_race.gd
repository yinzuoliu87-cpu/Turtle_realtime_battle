extends Node
## verify_prewarm_scene_race.gd — 文案常量后台预加载还没编完就进战斗, 战斗必须正常开打(2026-11-11)
##
## 由来: verify_tutorial 37 条「Nonexistent function 'new' in base 'GDScript'」, 11-11 凌晨只把两处类名 .new() 改成按路径 load 压住。
##   11-11 下午查清根因: 商店 / 背包 / 主菜单把文案里 {C:类.常量} 引用的类(EquipSystem、主场景……整批战斗脚本)交给后台线程编
##   (SkillText.prewarm_consts), 这时进战斗又编同一批 ⇒ 引擎把编到一半的半成品交给另一边, 哪个类中招看时序。
##   撤掉修法实测(tests/probes/_probe_prewarm_then_battle): 走 SceneFader 后台加载 306 条 SCRIPT ERROR、场上 0 个单位;
##   主线程直接 load 746 条、战斗时钟停在 0。中招的类每次不同(灵物特效 / 小木斧 / 药水批 / 触手特效…)。
## 判据(真入口 SceneNav.go → SceneFader.go, 进战斗场景):
##   ① 分母: 无头下强开预加载, 后台排上 ≥ 10 个, 发起换场那一刻还有没编完的(否则测的是空场景)
##   ② 过场等了预加载: 排新页面那一刻 prewarm_busy() 为假(SceneFader.last)
##   ③ 战斗正常开打: 换场后战斗时钟在走、场上有活着的单位(SCRIPT ERROR 由 run-tests 的 FATAL 正则判红)
##   ④ 源码顺序: SceneNav.go 无头分支、AbandonedMatch.resume_if_any 换场前 flush_prewarm; SkillText.const_of 现场 load 前 flush
## ★本测试必须单独一个进程: 战斗脚本编过一次就进了缓存, 同进程再测就是空检查。

const BATTLE := "res://scenes/RealtimeBattle3D.tscn"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	Engine.max_fps = 60   # 帧预算按 60fps 算(等后台编译是按真实时间)
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	var tree := get_tree()

	print("=== ④ 源码顺序 ===")
	_check_order("res://scripts/util/scene_nav.gd", "static func go(", "SkillText.flush_prewarm()", "tree.change_scene_to_file.call_deferred(path)",
		"SceneNav.go 无头分支同步换场前 flush_prewarm")
	_check_order("res://scripts/systems/replay/abandoned_match.gd", "static func resume_if_any(", "SkillText.flush_prewarm()", "tree.change_scene_to_file(BATTLE_SCENE)",
		"AbandonedMatch.resume_if_any(启动补打)同步进战斗前 flush_prewarm")
	_check_order("res://scripts/util/skill_text.gd", "static func const_of(", "flush_prewarm()", "load(path)",
		"SkillText.const_of 主线程现场 load 前 flush_prewarm")
	_check_order("res://scripts/util/scene_fader.gd", "func go(", "SkillText.prewarm_busy()", "ResourceLoader.load_threaded_request(path)",
		"SceneFader.go 等预加载编完才排新页面")

	print("=== ①~③ 预加载没编完就走真过场进战斗 ===")
	## 本节点不当 current_scene(换场会把 current_scene 释放掉): 放一个替身
	var stand := Node.new()
	stand.name = "Stand"
	tree.root.add_child(stand)
	tree.current_scene = stand
	await tree.process_frame
	SkillText.prewarm_in_headless = true
	var n := SkillText.prewarm_consts()
	SkillText.prewarm_in_headless = false
	var busy_at_go := SkillText.prewarm_busy()
	_ok("① 分母: 后台排上文案常量脚本 ≥ 10 个, 发起换场时还没编完", n >= 10 and busy_at_go, "排上 %d 个 · 发起时仍在编 %s" % [n, busy_at_go])
	SceneNav.transition_in_headless = true
	SceneNav.go(tree, BATTLE)
	var f: SceneFader = tree.root.get_node_or_null("SceneFader")
	var frames := 0
	while frames < 1500 and (f == null or f.busy or tree.current_scene == stand):
		await tree.process_frame
		frames += 1
	SceneNav.transition_in_headless = false
	var last: Dictionary = f.last if f != null else {}
	_ok("② 过场先等预加载编完再排新页面", not last.is_empty() and not bool(last.get("prewarm_busy_at_request", true)) and bool(last.get("ok", false)),
		"等预加载 %s 毫秒 · 等加载 %s 毫秒 · %d 帧" % [last.get("prewarm_wait_ms", "?"), last.get("wait_load_ms", "?"), frames])
	var bt: Node = tree.current_scene
	var is_battle: bool = bt != null and bt != stand and str(bt.scene_file_path) == BATTLE
	var t_start := float(bt.get("_t")) if is_battle else 0.0
	var k := 0
	while is_battle and k < 600 and float(bt.get("_t")) - t_start < 1.0:
		await tree.process_frame
		k += 1
	var alive := 0
	if is_battle:
		for u in bt.get("_units"):
			if u.get("alive", false):
				alive += 1
	var t_now := float(bt.get("_t")) if is_battle else 0.0
	_ok("③ 进到战斗场景, 战斗时钟在走、场上有活着的单位", is_battle and t_now - t_start >= 1.0 and alive > 0,
		"场景 %s · 战斗 %.2f → %.2f 秒(%d 帧) · 活着 %d" % [str(bt.scene_file_path) if bt != null else "null", t_start, t_now, k, alive])

	print("\n%d 项, 失败 %d" % [_n, _fail])
	if _fail == 0 and _n >= 7:
		print("ALL PASS — 预加载没编完就进战斗, 过场先等它编完, 战斗正常开打")
	else:
		print("FAIL")
	SkillText.flush_prewarm()
	tree.quit()


## 函数体(去注释)里 a 出现在 b 之前, 且两者都在。
func _check_order(path: String, fn_head: String, a: String, b: String, name: String) -> void:
	var src := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	var i0 := src.find(fn_head)
	var body := ""
	if i0 >= 0:
		var i1 := src.find("\nfunc ", i0 + 1)
		var i2 := src.find("\nstatic func ", i0 + 1)
		var end := src.length()
		if i1 >= 0:
			end = mini(end, i1)
		if i2 >= 0:
			end = mini(end, i2)
		for l in src.substr(i0, end - i0).split("\n"):
			var s := str(l)
			var h := s.find("#")
			if h >= 0 and s.substr(0, h).count("\"") % 2 == 0:
				s = s.substr(0, h)
			body += s + "\n"
	var ia := body.find(a)
	var ib := body.find(b)
	_ok("④ " + name, i0 >= 0 and ia >= 0 and ib >= 0 and ia < ib, "%s: %s@%d · %s@%d" % [path.get_file(), a, ia, b, ib])
