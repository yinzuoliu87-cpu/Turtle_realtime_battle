extends Node

## verify_tutorial_director.gd — 教学导演状态机 (用户 2026-07-23 阶段 C)
## 流程: 战斗1→商店→背包→图鉴→战斗2→结束回菜单。验阶段推进顺序 + 沙盒收尾。

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  "+d) if d!="" else "")
	else: _fail+=1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	_ok("TutorialDirector autoload 在", td != null)
	if td == null: _done(); return

	# 开教学: 模拟 _begin_tutorial
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1"
	GameState.onboarded = false

	# ★走完整链, 每一步断言下一站对
	var chain = [
		["battle", "match1", "Shop.tscn", "shop"],       # 战斗1打完→商店
		["shop", "shop", "Inventory.tscn", "inventory"], # 商店→背包
		["inventory", "inventory", "Codex.tscn", "codex"],# 背包→图鉴
		["codex", "codex", "RealtimeBattle3D.tscn", "match2"],# 图鉴→战斗2
	]
	for step in chain:
		var here: String = step[0]
		var expect_stage: String = step[1]
		var expect_dest: String = step[2]
		var next_stage: String = step[3]
		_ok("阶段是 %s" % expect_stage, td.stage() == expect_stage, "实际 %s" % td.stage())
		var dest: String = td.next_scene_after(here)
		print("  [实测] %s(%s) → %s ; 推进到 %s" % [here, expect_stage, dest, td.stage()])
		_ok("★%s 完成 → 去 %s" % [here, expect_dest], dest.ends_with(expect_dest), "去了 %s" % dest)
		_ok("★推进到阶段 %s" % next_stage, td.stage() == next_stage)

	# 战斗2打完 → 结束
	_ok("战斗2 阶段", td.stage() == "match2")
	var final_dest: String = td.next_scene_after("battle")
	print("  [实测] 战斗2打完 → %s ; onboarded=%s tutorial_active=%s" % [final_dest, GameState.onboarded, GameState.tutorial_active])
	_ok("★战斗2 打完 → 回主菜单", final_dest.ends_with("MainMenu.tscn"))
	_ok("★★教学结束置 onboarded=true(不再触发)", GameState.onboarded == true)
	_ok("★★教学结束关沙盒(tutorial_active=false)", GameState.tutorial_active == false)

	# ★attach_next_button 不能有副作用: 建按钮时 stage 不能变(2026-07-23 bug: 建按钮时
	#   调了 next_scene_after 推进了 stage → 战斗1直接→MainMenu、收尾没关沙盒)。
	GameState.tutorial_active = true
	GameState.tutorial_stage = "shop"
	var host := Control.new(); add_child(host)
	var stage_before: String = td.stage()
	td.attach_next_button(host, "shop")
	print("  [实测] attach_next_button 前 stage=%s, 后 stage=%s" % [stage_before, td.stage()])
	_ok("★★建'下一站'按钮【不改 stage】(否则流程会串)", td.stage() == stage_before,
		"stage 从 %s 变成了 %s" % [stage_before, td.stage()])
	host.queue_free()

	# 固定阵容 + 弱对手
	_ok("★固定阵容非空(用户: 固定阵容)", td.FIXED_TEAM.size() >= 1)
	_ok("★弱对手比玩家少(必赢)", td.WEAK_FOE.size() < td.FIXED_TEAM.size(), "%d vs %d" % [td.WEAK_FOE.size(), td.FIXED_TEAM.size()])

	_done()

func _done() -> void:
	# 复原
	GameState.tutorial_active = false; GameState.tutorial_stage = ""
	print("ALL PASS — 教学导演状态机" if _fail==0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail==0 else 1)
