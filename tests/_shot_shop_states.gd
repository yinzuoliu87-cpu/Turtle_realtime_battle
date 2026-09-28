extends Node
## 截图用的 SHOT_POST: 把商店摆成【点过才出现】的那几态。门禁扫静止态扫不到它们,
## 而上一轮正是在四个屏上都栽在这一类("只看了没点过的样子")。
##
## SHOT_STATE=
##   nostat  货架第 0 格换成一件【一条属性都没有】的装备并选中
##           —— 实测 96 件的 stat_lines 【无一为空】, 所以这一支平时打不到;
##              不硬造就永远拍不到"这件不加属性，只有效果"到底长什么样。
##   poor    深海币归零 ⇒ 十张卡全走"买不起"(整卡压暗 + 斜纹), 并选中第 0 格
##           看详情面板底部那颗按钮变成「还差 N 枚深海币」
##   sel     正常选中第 0 格(详情面板常驻态)
##   tri     三态同框: 卖掉两格(已买) + 币压到 2(贵的买不起、便宜的买得起)
##           —— 「一眼分得出」只能在同一张图里比, 分三张各截一张是比不出来的。


static func run(scene: Node) -> void:
	var st := OS.get_environment("SHOT_STATE")
	var gs = scene.get_node_or_null("/root/GameState")
	match st:
		"nostat":
			var off: Array = scene.get("_offer")
			if off.size() > 0:
				## id 不在 EquipStats.STATS 里 ⇒ stat_lines() 返回空 ⇒ 走那一支。
				off[0] = {
					"id": "p2eq_probe_nostat", "name": "无属性样件", "cost": 3,
					"type": "弓箭",
					"effectDesc1": "只有效果、没有任何属性加成的一件样品(探针造的, 不在真数据里)。",
				}
			scene.set("_sel", 0)
		"tri":
			var off2: Array = scene.get("_offer")
			for k in [2, 7]:
				if k < off2.size():
					off2[k] = null          # 已买 ⇒ 空货位(有框、里面什么都没有)
			## ★必须【强制】塞几件贵的: 1 级货架的出货概率是 1 费 100%,
			##   十格全是 1 费 ⇒ 币压到 2 也没有一格是买不起的 ⇒ 这张图只拍得到两态。
			##   (第一版就是这样, 差点当成"三态都在了"。)
			var rich: Dictionary = {}
			for e in DataRegistry.phase2_equipment:
				if e is Dictionary and int((e as Dictionary).get("cost", 0)) >= 4:
					rich = e
					break
			for k2 in [3, 4, 8, 9]:
				if k2 < off2.size() and not rich.is_empty():
					off2[k2] = rich
			print("[SHOT] tri: 塞了 4 格贵货 %s(cost %d)" % [str(rich.get("name", "?")), int(rich.get("cost", 0))])
			gs.meta_deepsea_coins = 2       # 1~2 费买得起, 4~5 费买不起
			scene.set("_sel", 0)
		"popbench":
			## 底部两颗按钮点开的弹层 —— 静止态门禁**一个像素都扫不到**它们。
			var off3: Array = scene.get("_offer")
			var bench: Array = []
			for e3 in off3:
				if e3 is Dictionary:
					bench.append({"id": str((e3 as Dictionary).get("id", "")), "star": 1})
			gs.persistent_bench = bench
			if scene.has_method("_rebuild"):
				scene.call("_rebuild")
			scene.call("_open_bottom_popup", "bench")
			print("[SHOT] 弹层 bench, 背包 %d 件" % bench.size())
			return
		"poplineup":
			gs.persistent_bench = []
			if scene.has_method("_rebuild"):
				scene.call("_rebuild")
			scene.call("_open_bottom_popup", "lineup")
			print("[SHOT] 弹层 lineup(空阵容 ⇒ 看空态那句话)")
			return
		"poor":
			gs.meta_deepsea_coins = 0
			scene.set("_sel", 0)
		_:
			scene.set("_sel", 0)
	print("[SHOT] state=%s  币=%d" % [st, int(gs.meta_deepsea_coins)])
	if scene.has_method("_rebuild"):
		scene.call("_rebuild")
