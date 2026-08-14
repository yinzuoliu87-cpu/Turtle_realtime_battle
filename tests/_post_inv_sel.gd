extends Node
## 截图用: 背包页【选中一格】—— 底部操作条只在选中后才画, 不种这一步永远截到空态,
## 然后我会把"我没配对环境"报成"这块没做"(CLAUDE.md 里点名过的坑)。
##
##   SHOT_INV_SEL=N   选背包第 N 件(数据下标, 糖果罐不占号)
##   SHOT_INV_JAR=1   改成选中糖果罐(看"打碎"那条操作栏)


static func run(scene: Node) -> void:
	if OS.has_environment("SHOT_INV_JAR"):
		scene.set("_sel_jar", true)
		scene.set("_sel_bench", -1)
	else:
		var idx := 0
		if OS.get_environment("SHOT_INV_SEL").is_valid_int():
			idx = int(OS.get_environment("SHOT_INV_SEL"))
		scene.set("_sel_bench", idx)
		scene.set("_sel_jar", false)
	if scene.has_method("_rebuild"):
		scene.call("_rebuild")
	## SHOT_INV_DETAIL=1: 再把【详情】弹框打开(装备全文 + 属性加成那一屏)
	if OS.has_environment("SHOT_INV_DETAIL"):
		var bench: Array = GameState.persistent_bench
		var i: int = int(scene.get("_sel_bench"))
		if i >= 0 and i < bench.size():
			scene.call("_show_equip_detail", bench[i])
