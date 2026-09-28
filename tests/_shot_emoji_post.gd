extends Node
## DEV 实拍钩子: 把「换掉 emoji 的那几处」催到看得见的状态再截。
## 配 `tests/_shot_scene.gd` 用:
##   SHOT_SCENE=res://scenes/Inventory.tscn SHOT_POST=res://tests/_shot_emoji_post.gd \
##   SHOT_STATE=jar SHOT_WAIT=420 <godot> --path . res://tests/_shot_scene.tscn
##
## ★为什么要它: 要看的那几处**静止页上不在**(糖果罐操作栏要先选中那张卡、
##   撮合的「已匹配」那一屏是 2.2 秒后才建的)。没有这个钩子就只能截到空态,
##   然后我会把"我没配对环境"报成"这块做好了"。
## ★`SHOT_STATE` 选要哪一态, 缺省就截静止页。


static func run(scene: Node) -> void:
	var state := OS.get_environment("SHOT_STATE")
	var src := ""
	if scene.get_script() != null:
		src = str(scene.get_script().resource_path)

	if src.ends_with("InventoryScene.gd"):
		match state:
			"jar":                       # 糖果罐操作栏(打碎那一条)
				scene.set("_sel_jar", true)
				scene.set("_sel_bench", -1)
				scene.call("_rebuild")
			"sell":                      # 选中一件装备 ⇒ 底栏「卖出 +N ◎」
				scene.set("_sel_jar", false)
				scene.set("_sel_bench", 0)
				scene.call("_rebuild")
			_:
				pass
	elif src.ends_with("CodexScene.gd"):
		## `SHOT_STATE=pets` 或 `SHOT_STATE=pets:6`(冒号后是要选中的第几条)。
		## ★要看「换形态」那颗钮就得选到双形态龟(双头/熔岩), 选第 0 条永远看不到它。
		var tab := state if state != "" else "pets"
		var idx := 0
		if tab.find(":") >= 0:
			var bits := tab.split(":")
			tab = str(bits[0])
			idx = int(str(bits[1]))
		scene.call("_switch_tab", tab)
		if int(scene.get("_items").size()) > idx:
			scene.call("_select", idx)
	elif src.ends_with("MatchmakingScene.gd"):
		## ★先把自动跳转的闸拉下来(它自己有三道 `_cancelled` 闸), 否则 2.2 秒后
		##   整个窗口会切进战斗场, 截到的是战斗而不是撮合。
		scene.set("_cancelled", true)
		await scene.get_tree().process_frame
		await scene.get_tree().process_frame
		var opp = GameState.dual_opponent
		if opp is Dictionary and not (opp as Dictionary).is_empty():
			scene.call("_build_vs", opp)
	elif src.ends_with("SettingsScene.gd"):
		if state == "reset":
			scene.call("_ask_reset")
