extends Node
## 截图用的 SHOT_POST: 把商店摆成【货架上每一件背包里都已有】的样子。
##
## ★为什么非要它: 镀层掠光只在 `owned > 0` 时才建, 而截图台跑的是全新档(背包空)
##   ⇒ 不种这一步, 截出来的十张卡一道掠光都没有, 而我会把"我没配对环境"读成"这块没问题"。
##
## ★掠光的 x 是循环 tween 在扫的 ⇒ 随便一帧抓到的位置不定, 同一份代码截两次能截出两个样。
##   这里把 `Engine.time_scale` 归零【再】把每条斜向元素按到指定 x, 于是改前/改后两张图
##   量的是同一个位置, 差分只剩"裁没裁"这一件事。
##   SHOT_SHINE_X=172 是扫描路径的右端(最坏处); 不给则默认它。
##
## SHOT_COINS=0 可另外截"买不起"那一态(整卡压暗 + 斜纹)。


static func run(scene: Node) -> void:
	var gs = scene.get_node_or_null("/root/GameState")
	if gs == null:
		return
	if OS.get_environment("SHOT_COINS").is_valid_int():
		gs.meta_deepsea_coins = int(OS.get_environment("SHOT_COINS"))
	var off: Array = scene.get("_offer")
	var bench: Array = []
	for e in off:
		if e is Dictionary:
			bench.append({"id": str((e as Dictionary).get("id", "")), "star": 1})
	gs.persistent_bench = bench
	print("[SHOT] 背包塞了 %d 件(★分母: 0 件 = 一道掠光都不会建, 这张图什么也证明不了)" % bench.size())
	if scene.has_method("_rebuild"):
		scene.call("_rebuild")
	## 冻住时间再钉位置 —— 顺序反了的话 tween 会在后面的等待帧里把它挪走。
	Engine.time_scale = 0.0
	var sx := 172.0
	if OS.get_environment("SHOT_SHINE_X").is_valid_float():
		sx = float(OS.get_environment("SHOT_SHINE_X"))
	var rots: Array = []
	_collect_rotated(scene, rots)
	## ★只钉【掠光】, 不动斜纹: 斜纹是 4 根一组按 46px 排的, 全按到同一个 x 就把"买不起"那
	##   一态的形状毁了。掠光宽 26、斜纹宽 3 ⇒ 按宽度分得开。
	var n := 0
	for cr in rots:
		if (cr as ColorRect).size.x > 10.0:
			(cr as ColorRect).position.x = sx
			n += 1
	print("[SHOT] 钉住 %d 条掠光到 x=%.0f (斜向元素共 %d 个)" % [n, sx, rots.size()])


static func _collect_rotated(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ColorRect and absf((c as ColorRect).rotation) > 0.01:
			out.append(c)
		_collect_rotated(c, out)
