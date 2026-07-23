extends Node

## verify_tutorial_anchors.gd — 新手引导高亮锚点 (用户 2026-07-23 教学阶段 D)
##
## 验: tutorial-steps.json 里每个 highlight 名, 对应场景的 _tutorial_anchor() 都能解析出【非零 Rect2】。
## 否则暗幕会挖个空洞(或退回无高亮) → "手把手圈出该点哪"落空。
## ★分母: 带 highlight 的步数必须 > 0(否则等于没做高亮, 空检查冒充通过)。
##
## battle 的 place 锚点(field/go_button)靠 3D 场景+摆位运行态才有, 不在此实例化(太重),
## 由窗口版 _tutorial_playthrough 视觉覆盖; 这里只断言 battle 脚本【定义了】该方法 + field 公式非零。

const STEPS_PATH := "res://data/tutorial-steps.json"

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)


# scene 标识 → (场景路径, 该 key 用到的 highlight 名集合)。key 见 TutorialDirector.steps_key_for。
const CONTROL_SCENES := {
	"team_select": "res://scenes/TeamSelect.tscn",
	"shop": "res://scenes/Shop.tscn",
	"inventory": "res://scenes/Inventory.tscn",
	"codex": "res://scenes/Codex.tscn",
}


func _collect_highlights() -> Dictionary:
	# key → [highlight 名...] (去重)
	var raw := FileAccess.get_file_as_string(STEPS_PATH)
	var parsed = JSON.parse_string(raw)
	var out := {}
	if not (parsed is Dictionary):
		return out
	for key in parsed.keys():
		if str(key).begins_with("_"):
			continue   # _note/_schema/_anchors 元字段
		var steps = parsed[key]
		if not (steps is Array):
			continue
		var names: Array = []
		for st in steps:
			if st is Dictionary:
				var hl := str((st as Dictionary).get("highlight", ""))
				if hl != "" and not (hl in names):
					names.append(hl)
		out[key] = names
	return out


func _ready() -> void:
	await get_tree().process_frame
	# 教学态: 商店要 tutorial_active 才开店; 背包/选龟要 season_leaders 才建阵容
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1_pick"
	GameState.tutorial_mandatory = true
	var lt: Array[String] = ["basic", "stone", "bamboo"]
	GameState.season_leaders = lt.duplicate()
	GameState.left_team = lt.duplicate()
	GameState.dual_lineup = {}
	GameState.meta_deepsea_coins = 20

	var hl := _collect_highlights()

	# ★分母: 带 highlight 的步一共多少
	var total := 0
	for k in hl:
		total += (hl[k] as Array).size()
	print("  [分母] tutorial-steps.json 里 highlight 锚点共 %d 个: %s" % [total, hl])
	_ok("★分母>0(真做了高亮, 不是空检查)", total > 0, "total=%d" % total)

	# ① 四个 Control 场景: 每个声明的 highlight 名都能解析出非零 Rect2
	for key in CONTROL_SCENES:
		var names: Array = hl.get(key, [])
		if names.is_empty():
			continue
		var scn = load(CONTROL_SCENES[key])
		var inst = scn.instantiate()
		add_child(inst)
		# 等几帧让 Control 布局完成(get_global_rect 才有真尺寸)
		for _i in range(4):
			await get_tree().process_frame
		var has_fn: bool = inst.has_method("_tutorial_anchor")
		_ok("[%s] 实现了 _tutorial_anchor" % key, has_fn)
		if has_fn:
			for nm in names:
				var r: Rect2 = inst.call("_tutorial_anchor", nm)
				var okr: bool = r.size.x > 0.0 and r.size.y > 0.0
				_ok("★[%s] 锚点 '%s' 解析出非零矩形" % [key, nm], okr, str(r))
			# 反向: 不存在的锚点名 → 空 Rect2(不能乱返回一个把全屏挡死)
			var bad: Rect2 = inst.call("_tutorial_anchor", "__不存在__")
			_ok("[%s] 未知锚点返回空矩形(不挖空洞)" % key, bad.size == Vector2.ZERO, str(bad))
		inst.queue_free()
		await get_tree().process_frame

	# ② battle 的 place 锚点: 脚本定义了方法(3D 运行态锚点靠 playthrough 覆盖)
	var bscript = load("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var src: String = ""
	if bscript is GDScript:
		src = (bscript as GDScript).source_code
	_ok("battle 脚本定义 _tutorial_anchor", src.contains("func _tutorial_anchor"))
	_ok("battle 有 field 锚点分支", src.contains("\"field\""))
	_ok("battle 有 go_button 锚点分支", src.contains("\"go_button\""))
	# place 步在 json 里也得声明了这俩(否则锚点没人用)
	var place_names: Array = hl.get("place", [])
	_ok("★place 步声明了 field/go_button 高亮", ("field" in place_names) and ("go_button" in place_names), str(place_names))

	GameState.tutorial_active = false; GameState.tutorial_stage = ""
	print("ALL PASS — 新手引导高亮锚点" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
