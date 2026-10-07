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
}
## 每屏进来时的教程阶段(背包的「完成教程」钮只在教程里建)
const STAGE := {"team_select": "match1_pick", "shop": "shop", "inventory": "inventory"}


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
				## highlight(挖洞)与 point(手势指针)两种锚点都要解析得出
				for fld in ["highlight", "point"]:
					var hl := str((st as Dictionary).get(fld, ""))
					if hl != "" and not (hl in names):
						names.append(hl)
		out[key] = names
	return out


func _ready() -> void:
	await get_tree().process_frame
	# 教学态: 商店要 tutorial_active 才开店; 背包/选龟要 season_leaders 才建阵容
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1_pick"
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
		GameState.tutorial_stage = str(STAGE[key])
		if key == "team_select":
			GameState.season_leaders = []
			GameState.left_team = []
		else:
			GameState.season_leaders = lt.duplicate()
			GameState.left_team = lt.duplicate()
		if key == "inventory":
			GameState.persistent_bench = [{"id": "p2eq_001", "star": 1}]   # 「点击一件装备」的指针要有一件可指
		var scn = load(CONTROL_SCENES[key])
		var inst = scn.instantiate()
		add_child(inst)
		# ★锚点只认【真看得见】的控件(TutorialGuide.vis_rect: 入场淡入完才算) ⇒ 轮询到解析得出, 上限 90 帧
		for _i in range(90):
			await get_tree().process_frame
			var all_ok := true
			for nm0 in names:
				var r0: Rect2 = inst.call("_tutorial_anchor", nm0) if inst.has_method("_tutorial_anchor") else Rect2()
				if r0.size.x <= 0.0:
					all_ok = false
			if all_ok:
				break
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

	# ② 战斗(摆位 / 结算)的锚点: 3D 运行态才有 ⇒ 这里断言源码【定义了】, 真解析由 verify_tutorial GUIDE_HOST /
	#    verify_tutorial_flow_v2 在真战斗场里量。
	var bsrc: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var dsrc: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var hsrc: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("battle 定义 _tutorial_anchor 且有 field / go_button 分支",
		bsrc.contains("func _tutorial_anchor") and bsrc.contains("\"field\"") and bsrc.contains("\"go_button\""))
	_ok("dual_lane_flow 有 my_unit 锚点(手势指针指一只我方龟)", dsrc.contains("func _tut_anchor") and dsrc.contains("\"my_unit\""))
	_ok("battle_hud 结算有 settle_shop 锚点", hsrc.contains("\"settle_shop\""))
	var place_names: Array = hl.get("place", [])
	_ok("★place 步声明了 field / my_unit / go_button", ("field" in place_names) and ("my_unit" in place_names)
		and ("go_button" in place_names), str(place_names))
	_ok("★settle 步声明了 settle_shop", "settle_shop" in (hl.get("settle", []) as Array))

	GameState.tutorial_active = false; GameState.tutorial_stage = ""
	print("ALL PASS — 新手引导高亮锚点" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
