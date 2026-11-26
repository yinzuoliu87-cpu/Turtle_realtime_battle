extends Node
## DEV 探针 —— 面具 / 长矛 / 筹码三批的伤害有没有「捡上一发的类型」(11-26 夜)
## 由来: 用户 11-26「真伤和物理伤还叠在一起了？你不按规则来的吗？」—— 红脸真伤没声明类型, 捡成物理, 飘字并进普攻那个数字。
## 做法: 开伤害类型哨兵(DMGSENTINEL=1, battle_damage 头注), 裁判入口跑一局面具顶档 + 长矛顶档 + 筹码, 打出哨兵三本账。
const W := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")


static func _eqs(ids: Array) -> Array:
	var o: Array = []
	for i in ids:
		o.append({"id": "p2eq_%03d" % int(i), "star": 2})
	return o


func _ready() -> void:
	OS.set_environment("DMGSENTINEL", "1")
	var gs = get_node_or_null("/root/GameState")
	var w = W.new()
	var a: Dictionary = w._snap(gs, ["stone", "lava", "candy"], [_eqs([129, 127, 135]), _eqs([130, 131, 132]), _eqs([133, 134, 136])], "g_dt_a", "甲", 0)
	var b2: Dictionary = w._snap(gs, ["bubble", "hunter", "ninja"], [_eqs([137, 138, 139]), _eqs([140, 141, 142]), _eqs([143, 144, 156])], "g_dt_b", "乙", 1)
	w.free()
	var cap := {}
	var hook := func(bt) -> void:
		bt.tree_exiting.connect(func() -> void:
			var dm = bt._damage
			cap["tot"] = int(dm._dt_total)
			cap["st"] = (dm._dt_stale as Dictionary).duplicate()
			cap["wo"] = (dm._dt_wrongowner as Dictionary).duplicate()
			cap["un"] = (dm._dt_unmitigated as Dictionary).duplicate())
	var _res: Dictionary = await RefereeRunner.run(self, J.job(a, b2, 7261001), hook, {"keep": true})
	if not cap.has("tot"):
		print("没拿到战斗场景")
	else:
		print("伤害总数 %d" % int(cap["tot"]))
		print("捡来类型(stale) %d 处: %s" % [(cap["st"] as Dictionary).size(), str(cap["st"])])
		print("目标对不上(wrongowner) %d 处: %s" % [(cap["wo"] as Dictionary).size(), str(cap["wo"])])
		print("没算护甲(unmitigated) %d 处: %s" % [(cap["un"] as Dictionary).size(), str(cap["un"]).left(2000)])
	print("PROBE DONE")
	get_tree().quit(0)
