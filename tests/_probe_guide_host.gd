extends Node
## _probe_guide_host.gd — 台账 ⑧ 的探针(不进门禁)。
## 问三件事, 全部要实测数值, 不要推理:
##   ① `attach_guide(self, ...)` 传 RefCounted 到底报什么? 报错文本能不能被 run-tests.sh 的 FATAL 正则抓到?
##   ② 报错之后那一行的【左值】(battle._tutorial) 被写了吗? 后续语句还跑吗?
##   ③ 走【真路径】(教学 match1 + 双路 + 摆位阶段) 时, "place" 那三步引导到底有没有出场?
##      证据只认产品自己的账: 树里 group "tut_overlay" 的节点数 / battle._tutorial / 暗幕可见性。
##
## 跑法:
##   SHIP=1 TURTLE_SUPABASE=" " <godot> --headless --path . res://tests/_probe_guide_host.tscn --quit-after 2000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _sentinel := "未被赋值"


## 复现 dual_lane_flow.gd:405 那一行的形状: host 是 RefCounted, 被调方要 Node。
## 看两件事: 报什么错 / 报错之后同一函数里后面的语句还跑不跑。
func _repro_refcounted_host(td) -> void:
	var host_ref := RefCounted.new()
	var ret = td.attach_guide(host_ref, "battle")
	_sentinel = "赋值成功 ret=%s" % str(ret)
	print("  ★报错之后的语句跑到了(这一行本身就是证据)")


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var td = get_node_or_null("/root/TutorialDirector")
	print("[分母] GameState=%s TutorialDirector=%s" % [str(gs != null), str(td != null)])
	if gs == null or td == null:
		get_tree().quit(1)
		return
	gs.test_mode = true

	# ── ① 最小复现: 直接拿一个 RefCounted 当 host 调 attach_guide ──
	gs.tutorial = true
	gs.tutorial_active = true
	gs.tutorial_stage = "match1"
	gs.tutorial_mandatory = true
	print("--- ① 最小复现 (host = RefCounted) ---")
	print("  is_active=%s  steps_key_for(battle)=%s" % [str(td.is_active()), td.steps_key_for("battle")])
	# ★单独一个函数: 报错会【中止所在函数】, 写在 _ready 里会把后面全部探测掐掉(第一版就这样)
	_repro_refcounted_host(td)
	print("  哨兵(报错后那一行的左值) = %s" % _sentinel)
	print("  树里 tut_overlay 节点数=%d" % get_tree().get_nodes_in_group("tut_overlay").size())

	# ── ①b 对照组: host = 真 Node(证明同一行代码换个 host 就能挂出来) ──
	print("--- ①b 对照组 (host = Node) ---")
	var host_node := Node.new()
	add_child(host_node)
	var ret2 = td.attach_guide(host_node, "battle")
	print("  返回值=%s  tut_overlay 节点数=%d" % [str(ret2), get_tree().get_nodes_in_group("tut_overlay").size()])
	if ret2 != null:
		print("  挂出来的步数=%d  mandatory=%s" % [int(ret2._steps.size()), str(ret2._mandatory)])
		# 数一数那层暗幕(挡点击的那 4 块 ColorRect)
		var nmask := int(ret2._mask.size())
		var vis := 0
		for m in ret2._mask:
			if m.visible:
				vis += 1
		print("  暗幕块数=%d 其中可见=%d  (可见=挡点击生效)" % [nmask, vis])
		ret2.queue_free()
	host_node.queue_free()
	await get_tree().process_frame

	# ── ② 真路径: 教学 match1 + 双路 + 摆位阶段 ──
	print("--- ② 真路径 (教学 match1 双路摆位) ---")
	var lt: Array[String] = []
	for id in td.FIXED_TEAM:
		lt.append(str(id))
	gs.season_leaders = lt.duplicate()
	gs.left_team.assign(lt)
	gs.dual_lineup = {}
	gs.reset_dual_lane()
	td.arm_battle_sandbox()             # 真入口: 写弱 ghost + dual_active
	DualLaneFlow.NO_PRESENT = true      # 跳掉 5+5 秒纯演出(对摆位阶段无影响)
	print("  dual_active=%s ghost_id=%s stage=%s" % [str(gs.dual_active),
		str(gs.dual_ghost.get("ghost_id", "?")), td.stage()])

	var s = RB.new()
	add_child(s)
	var w := 0
	while w < 600 and str(s._dl_state) != "place":
		await get_tree().process_frame
		w += 1
	print("  等了 %d 帧, _dl_state=%s" % [w, str(s._dl_state)])
	print("  _tut_place_shown=%s" % str(s._tut_place_shown))
	print("  battle._tutorial=%s" % str(s._tutorial))
	var ov: Array = get_tree().get_nodes_in_group("tut_overlay")
	print("  ★树里 tut_overlay 节点数=%d  (0 = 那三步引导一个画面都没有)" % ov.size())
	for n in ov:
		print("      %s  parent=%s" % [str(n), str(n.get_parent())])
	# 锚点反查: 产品自己定义的两个高亮锚点解析得出来吗(证明"本来就该传 battle")
	for nm in ["field", "go_button"]:
		var r: Rect2 = s._tutorial_anchor(nm)
		print("  battle._tutorial_anchor(\"%s\") = %s" % [nm, str(r)])
	print("  DualLaneFlow 有 _tutorial_anchor 吗 = %s" % str(s._dl_sys.has_method("_tutorial_anchor")))
	print("  DualLaneFlow 有 add_child 吗 = %s" % str(s._dl_sys.has_method("add_child")))

	s.queue_free()
	await get_tree().process_frame
	print("PROBE DONE")
	get_tree().quit(0)
