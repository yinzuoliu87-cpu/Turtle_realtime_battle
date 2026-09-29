extends Node

## verify_tutorial_director.gd — 教学导演状态机 (用户 2026-07-23 阶段 C)
## 流程: 战斗1→商店→背包→图鉴→战斗2→结束回菜单。验阶段推进顺序 + 沙盒收尾。

var _fail: int = 0
var _n: int = 0

## ★★断言条数的【地板】。低于它 = 有协程在半路被掐断 / 静默 abort ⇒ 判红。
##   2026-09-29 反向验证当场撞到: 把修复撤掉后 `td._last_scene_path = ""` 抛
##   "Invalid assignment of property" —— GDScript 里这**不是致命错**, 协程就地返回,
##   `await` 拿到非信号立刻继续 ⇒ 16 条断言【一条没跑】, 而进程 rc=0 还打了 ALL PASS。
##   本仓记过这个形状(fb-null-readback-makes-test-silently-abort), 这里补上分母。
const MIN_ASSERTS := 52

func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", n, ("  "+d) if d!="" else "")
	else: _fail+=1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var td = get_node_or_null("/root/TutorialDirector")
	_ok("TutorialDirector autoload 在", td != null)
	if td == null: _done(); return

	# 开教学: 模拟 _begin_tutorial(从选龟界面起步)
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1_pick"
	GameState.onboarded = false

	# ★沙盒经济: begin_sandbox 快照真【币+背包】并发教学币; 结束(_finish)还原(不给奖励)
	var real_coins: int = 12345
	GameState.meta_deepsea_coins = real_coins
	var real_bench: Array = [{"id": "__probe_item__", "star": 2}]
	GameState.persistent_bench = real_bench.duplicate(true)
	td._econ_snapshot = {}          # 清残留快照, 保证 begin_sandbox 真快照
	td.begin_sandbox()
	_ok("★沙盒发教学币(=TUT_COINS %d)" % td.TUT_COINS, GameState.meta_deepsea_coins == td.TUT_COINS, "实际 %d" % GameState.meta_deepsea_coins)
	## ★2026-08-26 删掉了这里一行 `_ok("★begin_sandbox 幂等(再调不覆盖快照)", true)` ——
	##   它什么都没验, 而**真的幂等检查就在下面三行**(二次调用后比币)。
	##   一个"看着已验、其实是 true"的标签比没有更糟: 它让人以为这块有覆盖。
	var coins_during: int = GameState.meta_deepsea_coins
	td.begin_sandbox()              # 幂等: 第二次不该把"教学币"当真余额存进快照
	_ok("★begin_sandbox 二次调用不改币", GameState.meta_deepsea_coins == coins_during)

	# ★选龟界面确认 → 进战斗1(双路含摆位), 且武装了弱 ghost
	_ok("阶段是 match1_pick(选龟)", td.stage() == "match1_pick", "实际 %s" % td.stage())
	var pick_dest: String = td.next_scene_after("team_select")
	_ok("★选龟确认 → 去战斗", pick_dest.ends_with("RealtimeBattle3D.tscn"), "去了 %s" % pick_dest)
	_ok("★选龟后推进到 match1", td.stage() == "match1", "实际 %s" % td.stage())
	_ok("★进战斗置 dual_active(双路→有摆位阶段)", bool(GameState.dual_active))
	var ghost: Dictionary = GameState.dual_ghost
	var la = ghost.get("lane_assign", {})
	_ok("★弱 ghost 有合法分路(上/下路非空)", la is Dictionary and (la.get("top") is Array) and not (la.get("top") as Array).is_empty() and (la.get("bottom") is Array) and not (la.get("bottom") as Array).is_empty(), str(la))
	_ok("★弱 ghost 无装备(必赢沙包)", (ghost.get("equipped", {}) as Dictionary).is_empty())

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
	# ★★经济还原: 教学花的币/买的装备不留存(用户「不获得任何奖励」)
	_ok("★★结束还原真币(=%d, 教学的20币不留)" % real_coins, GameState.meta_deepsea_coins == real_coins, "实际 %d" % GameState.meta_deepsea_coins)
	_ok("★★结束还原真背包(教学买的不留)", GameState.persistent_bench.size() == real_bench.size() and str((GameState.persistent_bench[0] if GameState.persistent_bench.size()>0 else {}).get("id","")) == "__probe_item__", str(GameState.persistent_bench))
	_ok("★★结束关双路(dual_active=false)", not bool(GameState.dual_active))

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


	## ★★SANDBOX_RESTORE —— 教学沙盒必须把 season_leaders 原样还回去。
	##   2026-09-29 真实 bug: GameState.gd:105 的合约写着「教学期不设 season_leaders」,
	##   而 TeamSelectScene.gd:1346 那行没有任何教学判断、照写不误; _finish() 还原了币和背包,
	##   唯独漏了它 ⇒ 走完教学的人被 _roster_locked 锁死在教学那三只龟上, 换不掉。
	##   ★这条判据在修之前必须是红的 —— 当时三个教学门禁全绿, 没人守着这件事。
	var _td2 = get_node_or_null("/root/TutorialDirector")
	if _td2 != null:
		var _before: Array = ["aaa", "bbb", "ccc"]
		GameState.season_leaders = _before.duplicate()
		GameState.tutorial_active = true
		_td2.begin_sandbox()
		## 模仿教学确认阵容: 走的就是 TeamSelectScene:1346 那行干的事
		GameState.season_leaders = ["basic", "stone", "bamboo"]
		## ★分母: 沙盒期间它确实被改成了别的 —— 否则下面那条是空检查
		_ok("SANDBOX_RESTORE 分母: 沙盒期间 season_leaders 真的被改了",
			GameState.season_leaders != _before, str(GameState.season_leaders))
		_td2._finish()
		_ok("★★SANDBOX_RESTORE: _finish() 把 season_leaders 原样还回去",
			Array(GameState.season_leaders) == _before,
			"期望 %s 实际 %s" % [str(_before), str(GameState.season_leaders)])
	else:
		_ok("SANDBOX_RESTORE 分母: TutorialDirector 在场", false, "拿不到 /root/TutorialDirector")

	## ★★★SANDBOX_ABANDON —— 中途退出教学【不许】吃掉玩家的深海币与三统领。
	##   2026-09-29 真实事故: 主菜单「?」→ begin_sandbox() 把真币存进【内存快照】再发 20 教学币,
	##   而还原【只在 _finish()】(打完第二把)发生 ⇒ **中途退出就永久丢**。
	##   探针实测(tests/_probe_sandbox_abandon.gd): 进教学前盘上 292 → 教学里装一件(会 GameState.save())
	##   → 盘上 20, season_leaders 也被教学那三只覆盖。玩家的 292 币就这么没了。
	##   ★这一节测的是【放弃路径】, 与上面 SANDBOX_RESTORE 那节(走完流程)是两件事。
	await _check_abandon(td)

	_done()


## 中途离开教学的三条路都得把真经济还回来: 看门狗(退回主菜单) / 崩溃兜底(残留) / 幂等。
func _check_abandon(td) -> void:
	var real_coins: int = 292
	var real_leaders: Array = ["candy", "ghost", "pirate"]
	var real_bench: Array = [{"id": "__real_gear__", "star": 3}]

	# ── 摊平成"刚点进教学那一刻"
	GameState.test_mode = true                 # 存档保护: 本节一个字都不往玩家存档写
	GameState.meta_deepsea_coins = real_coins
	GameState.season_leaders = real_leaders.duplicate()
	GameState.persistent_bench = real_bench.duplicate(true)
	GameState.tutorial_active = true
	GameState.tutorial_stage = "match1_pick"
	td._econ_snapshot = {}
	## ★分母0: 看门狗的状态位在场。★★用 get/set 而不是 `td._last_scene_path = ...`:
	##   成员不存在时直接赋值会抛错并让这条协程【就地返回】—— 后面 16 条断言一条都不跑,
	##   而进程照样 rc=0 + ALL PASS(反向验证时当场撞到)。get/set 拿不到就是一条红, 不会中断。
	_ok("SANDBOX_ABANDON 分母0: 看门狗的状态位在场(_last_scene_path)",
		td.get("_last_scene_path") != null, "拿到的是 %s" % str(td.get("_last_scene_path")))
	td.set("_last_scene_path", "")
	td.begin_sandbox()
	GameState.season_leaders = ["basic", "stone", "bamboo"]   # TeamSelectScene:1346 确认阵容干的事

	## ★分母: 沙盒期间这两样【真的被改过】。不成立的话"还原正确"可能只是没人动过它
	##   —— 本仓栽过这个形状(判据没错但被测对象不在场)。
	_ok("SANDBOX_ABANDON 分母①: 沙盒期间深海币真被改了(%d → %d)"
		% [real_coins, int(GameState.meta_deepsea_coins)],
		int(GameState.meta_deepsea_coins) == int(td.TUT_COINS) and int(td.TUT_COINS) != real_coins,
		"实际 %d" % int(GameState.meta_deepsea_coins))
	_ok("SANDBOX_ABANDON 分母②: 沙盒期间 season_leaders 真被改了",
		Array(GameState.season_leaders) != real_leaders, str(GameState.season_leaders))

	# ── 真走一遍「中途离开」: 让看门狗从【真的 current_scene】上看见那个跃迁。
	#   ★为什么不 change_scene_to_file: 那会把测试自己(它就是 current_scene)free 掉,
	#     后面的断言一条都跑不到, 而进程照样 rc=0 —— 本仓记过的"静默少跑断言却照样 ALL PASS"。
	#     这里动的是 SceneTree 自己的 current_scene, 看门狗读的仍是它那一条真路径, 不是我插的标记。
	var keep: Node = get_tree().current_scene
	var in_tut: Node = _fake_scene("res://scenes/Inventory.tscn")
	var menu: Node = _fake_scene("res://scenes/MainMenu.tscn")
	var blank: Node = _fake_scene("")          # 换场那一瞬间 current_scene 是 null ⇒ 路径为空

	## ★反向误伤: begin_sandbox() 就是在主菜单上调的 —— 这时候【还没走出去】, 不许还。
	##   还了的话教学一开场花的就是玩家的真钱, 比原 bug 更糟。
	get_tree().current_scene = menu
	await get_tree().process_frame
	_ok("SANDBOX_ABANDON: 刚武装、还站在主菜单上时【不还】(教学得先花得到那 20 币)",
		int(GameState.meta_deepsea_coins) == int(td.TUT_COINS),
		"实测 %d" % int(GameState.meta_deepsea_coins))

	get_tree().current_scene = in_tut
	await get_tree().process_frame
	_ok("SANDBOX_ABANDON 分母③: 看门狗真看见人在教学里那一屏(背包)",
		str(td.get("_last_scene_path")).ends_with("Inventory.tscn"),
		"记到的是 %s" % str(td.get("_last_scene_path")))
	_ok("SANDBOX_ABANDON 分母④: 还没离开时【没有】提前还(币仍是教学的 %d)" % int(td.TUT_COINS),
		int(GameState.meta_deepsea_coins) == int(td.TUT_COINS), "实际 %d" % int(GameState.meta_deepsea_coins))

	## ★★换场的那一瞬间 `current_scene` 是 null(路径为空)。这一步【必须被忽略】——
	##   第一版拿"上一屏非空"当"来过别处"的证据, 而空这一下正好把证据抹掉 ⇒
	##   真按 ESC 回主菜单时币没还(实测 tests/_probe_real_abandon.gd 抓到的)。
	##   ⚠ 只拿"直接改 current_scene"测【测不出来】, 所以这一步得自己造出来。
	get_tree().current_scene = blank
	await get_tree().process_frame
	_ok("SANDBOX_ABANDON 分母③b: 换场瞬间那次空路径被忽略(没被记成「上一屏」)",
		str(td.get("_last_scene_path")).ends_with("Inventory.tscn"),
		"记到的是 %s" % str(td.get("_last_scene_path")))

	get_tree().current_scene = menu            # ← 背包 ESC / 返回键 / 战斗退出, 最后都是这一步
	await get_tree().process_frame
	get_tree().current_scene = keep            # 还给测试自己, 免得退出时 free 到假场景
	print("  [实测] 中途退回主菜单后: coins=%d leaders=%s bench=%s"
		% [int(GameState.meta_deepsea_coins), str(GameState.season_leaders), str(GameState.persistent_bench)])
	_ok("★★★SANDBOX_ABANDON: 中途退回主菜单 → 深海币原样还回来(=%d)" % real_coins,
		int(GameState.meta_deepsea_coins) == real_coins, "实测 %d" % int(GameState.meta_deepsea_coins))
	_ok("★★★SANDBOX_ABANDON: 中途退回主菜单 → season_leaders 原样还回来",
		Array(GameState.season_leaders) == real_leaders,
		"期望 %s 实际 %s" % [str(real_leaders), str(GameState.season_leaders)])
	_ok("★★SANDBOX_ABANDON: 中途退回主菜单 → 背包原样还回来",
		GameState.persistent_bench.size() == 1 and str((GameState.persistent_bench[0] as Dictionary).get("id", "")) == "__real_gear__",
		str(GameState.persistent_bench))
	_ok("★SANDBOX_ABANDON: 还完就把沙盒卸了(快照清空 → 不会还第二遍)", td._econ_snapshot.is_empty())
	in_tut.queue_free()
	menu.queue_free()
	blank.queue_free()

	# ── 崩溃 / 强杀 兜底: 进沙盒时快照就落了盘, 下次启动发现残留 ⇒ 还原。
	#   (进程被杀时看门狗与 _finish 一行都跑不到, 而教学里商店/背包早把 20 币存进盘了。)
	## ★同上: 先证明这套东西在场, 再用。不在场就是一条红, 而不是把后面的断言吞掉。
	if not (td.has_method("restore_residue_if_any") and td.has_method("_write_residue")
			and td.has_method("_clear_residue") and td.get("_residue_path") != null):
		_ok("SANDBOX_ABANDON 崩溃兜底: 残留那一套(落盘/还原/清理)在场", false,
			"TutorialDirector 上没有 restore_residue_if_any/_write_residue/_clear_residue/_residue_path")
		GameState.test_mode = true
		return
	_ok("SANDBOX_ABANDON 分母⑤: 残留路径默认就是产品那条(不是测试注入的)",
		str(td._residue_path) == str(td.SANDBOX_RESIDUE), "默认是 %s" % str(td._residue_path))
	td._residue_path = "user://__gate_sandbox_residue.dat"   # ★绝不碰玩家 user:// 里那一份
	td._clear_residue()
	td._econ_snapshot = {}
	td.set("_last_scene_path", "")
	GameState.meta_deepsea_coins = real_coins
	GameState.season_leaders = real_leaders.duplicate()
	GameState.persistent_bench = real_bench.duplicate(true)
	GameState.test_mode = false                # ★临时开闸: 要验的正是"存档真会被写时才落残留"
	td.begin_sandbox()
	GameState.test_mode = true                 # 立刻关回去(下面的 save() 又是空转)
	_ok("SANDBOX_ABANDON 分母⑥: 进沙盒当场就把快照落了盘", FileAccess.file_exists(td._residue_path),
		"路径 %s" % str(td._residue_path))
	## 模拟"进程被杀": 内存里的快照跟着进程一起没了, 留在盘上的只有沙盒值
	td._econ_snapshot = {}
	GameState.season_leaders = ["basic", "stone", "bamboo"]
	_ok("SANDBOX_ABANDON 分母⑦: 重开那一刻手上是沙盒值(币 %d / 教学阵容)" % int(td.TUT_COINS),
		int(GameState.meta_deepsea_coins) == int(td.TUT_COINS) and Array(GameState.season_leaders) != real_leaders)
	var did: bool = td.restore_residue_if_any()
	_ok("★★SANDBOX_ABANDON 崩溃兜底: 下次启动发现残留 → 真还了东西", did)
	_ok("★★SANDBOX_ABANDON 崩溃兜底: 币还回来了(=%d)" % real_coins,
		int(GameState.meta_deepsea_coins) == real_coins, "实测 %d" % int(GameState.meta_deepsea_coins))
	_ok("★★SANDBOX_ABANDON 崩溃兜底: season_leaders 还回来了",
		Array(GameState.season_leaders) == real_leaders, str(GameState.season_leaders))
	_ok("★SANDBOX_ABANDON 残留还完就删(不会每次启动都还一遍)",
		not FileAccess.file_exists(td._residue_path))
	_ok("★SANDBOX_ABANDON 幂等: 没残留时再调, 一个字都不动",
		td.restore_residue_if_any() == false)

	# 收尾: 清掉注入的残留路径与文件
	td._clear_residue()
	td._residue_path = td.SANDBOX_RESIDUE
	GameState.test_mode = true


## 造一个"当前场景": 看门狗读的就是 current_scene.scene_file_path, 有这条真路径就够。
## ★不真 load 那两屏 —— 一屏要几十帧建树, 而这里验的是"从哪走到哪", 与屏里画了什么无关。
func _fake_scene(path: String) -> Node:
	var n := Node.new()
	## ★名字不能是空串(Node.set_name 会报 `Condition "p_name.is_empty()" is true`,
	##   而那条正好在 run-tests.sh 的致命正则里 ⇒ 整条门禁判红)。空路径那个替身也得有名字。
	n.name = path.get_file().get_basename() if path != "" else "Blank"
	n.scene_file_path = path
	get_tree().root.add_child(n)
	return n

func _done() -> void:
	# 复原
	GameState.tutorial_active = false; GameState.tutorial_stage = ""
	if _n < MIN_ASSERTS:
		_fail += 1
		print("  [FAIL] ★★断言只跑了 %d 条(至少该有 %d) —— 有东西在半路被掐断了, 别当绿灯" % [_n, MIN_ASSERTS])
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 教学导演状态机" if _fail==0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail==0 else 1)
