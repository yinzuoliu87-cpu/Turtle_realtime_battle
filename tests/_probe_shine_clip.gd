extends Node
## _probe_shine_clip.gd — 探针(只读·不进门禁): 货架卡上【斜着画的东西】有没有扫出卡外?
##
## 由来(2026-09-28 实拍): 已拥有那张卡上的「镀层掠光」是 26×245 的 ColorRect, 绕左上角
## 转了 -0.5 rad 再横扫 -40 → SLOT_W+40。Godot 的 Control **默认不裁子节点** ⇒ 那条灰白
## 斜带会画到卡外的空隙上。任何按控件矩形量的门禁都不会响(它既不是文字也不是框)。
##
## ★量的是【裁剪之后真正画出来的那块】: 取 ColorRect 四角的全局坐标(含 rotation),
##   再逐级与每个 `clip_contents` 祖先的矩形求交 —— 这才是屏幕上看得见的范围。
## ★掠光的 x 是 tween 在动的 ⇒ 随便一帧抓到的位置不定。这里**逐个钉死扫描路径上的采样点**
##   再量, 不靠运气撞上最坏的一帧。
##
## 跑法: APPDATA=/c/tmp/shop/ad <godot> --headless --audio-driver Dummy --path . \
##         res://tests/_probe_shine_clip.tscn --quit-after 900

const SHOP := preload("res://scenes/Shop.tscn")
const SLOT_W := 132.0
const SLOT_H := 136.0
## 掠光的扫描路径 -40 → SLOT_W+40, 两端最容易溢出 ⇒ 采样点铺满整条路径。
const SWEEP_X := [-40.0, -30.0, -10.0, 20.0, 66.0, 110.0, 132.0, 152.0, 172.0]

var _over := 0
var _shines := 0


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.meta_deepsea_coins = 9999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.meta_shop_battles = -1
	gs.meta_shop_offer = []
	gs.persistent_bench = []

	var sc = SHOP.instantiate()
	add_child(sc)
	if sc is Control:
		(sc as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(sc as Control).size = Vector2(1280, 720)
	await get_tree().process_frame

	## ★把货架上【每一件】都塞进背包 ⇒ 十张卡全部进入 `owned > 0` 分支。
	##   不这么做的话新档背包是空的, 一道掠光都不会建 —— 探针会变成分母 0 的空检查。
	var off: Array = sc.get("_offer")
	var bench: Array = []
	for e in off:
		if e is Dictionary:
			bench.append({"id": str((e as Dictionary).get("id", "")), "star": 1})
	gs.persistent_bench = bench
	print("  ★分母: 货架 %d 格, 背包塞了 %d 件" % [off.size(), bench.size()])
	sc.call("_rebuild")
	for _i in range(4):
		await get_tree().process_frame

	var cards: Array = []
	## ★必须【递归】找卡 —— `_rebuild()` 末尾的 `UIFrame.attach(self)` 会把所有子节点
	##   收编进一个居中框里, 卡片不再是场景根的直接子节点。只看直接子节点 ⇒ 扫到 0 张
	##   ⇒ 探针变成空检查而照样"0 溢出"(第一版就是这样, 差点报成"已裁住")。
	_collect_cards(sc, cards)
	print("  ★分母: 扫到 %d 张货架卡" % cards.size())

	for card in cards:
		var rots: Array = []
		_collect_rotated(card, rots)
		for cr in rots:
			_shines += 1
			var card_rect := Rect2((card as Control).global_position, (card as Control).size)
			var worst := 0.0
			var worst_at := 0.0
			var worst_rect := Rect2()
			var base_y: float = (cr as Control).position.y
			for sx in SWEEP_X:
				(cr as Control).position = Vector2(sx, base_y)
				# 位置改了要让变换生效 —— global_transform 是即时算的, 不必等帧
				var vis := _visible_aabb(cr as Control)
				var out: float = _outside_amount(vis, card_rect)
				if out > worst:
					worst = out; worst_at = sx; worst_rect = vis
			(cr as Control).position = Vector2(SWEEP_X[0], base_y)
			var tag: String = "%s 下的 %s" % [str(card.name), str(cr.name)]
			if worst > 0.5:
				_over += 1
				print("  [溢出] %s  卡=%.0f..%.0f  最坏在 x=%.0f 时画到 %.0f..%.0f ⇒ 出界 %.1f px"
					% [tag, card_rect.position.x, card_rect.end.x, worst_at,
					   worst_rect.position.x, worst_rect.end.x, worst])
			else:
				print("  [裁住] %s  卡=%.0f..%.0f  整条扫描路径上一像素都没出界" % [
					tag, card_rect.position.x, card_rect.end.x])

	print("")
	print("  斜向元素 %d 个, 其中溢出 %d 个" % [_shines, _over])
	if _shines == 0:
		print("  ★★这是【空检查】—— 一个斜向元素都没找到, 上面的 0 溢出毫无意义")
	get_tree().quit(0)


## 货架卡 = 尺寸恰为 SLOT_W×SLOT_H 的 Panel。递归找, 不假定它挂在哪一层。
func _collect_cards(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Panel and absf((c as Panel).size.x - SLOT_W) < 1.0 and absf((c as Panel).size.y - SLOT_H) < 1.0:
			out.append(c)
		else:
			_collect_cards(c, out)


## 找出这张卡下面所有【转过角度】的 ColorRect(掠光 / 斜纹都是这个形状)。
func _collect_rotated(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ColorRect and absf((c as ColorRect).rotation) > 0.01:
			out.append(c)
		_collect_rotated(c, out)


## 这个控件在屏幕上【真正画出来的那块】: 四角走全局变换(含旋转), 再与每个
## `clip_contents` 祖先求交。没有任何裁剪祖先时 = 旋转后的整块外接矩形。
func _visible_aabb(ct: Control) -> Rect2:
	var xf: Transform2D = ct.get_global_transform()
	var s: Vector2 = ct.size
	var p0: Vector2 = xf * Vector2.ZERO
	var r := Rect2(p0, Vector2.ZERO)
	for v in [Vector2(s.x, 0.0), Vector2(0.0, s.y), s]:
		r = r.expand(xf * v)
	var a: Node = ct.get_parent()
	while a != null:
		if a is Control and (a as Control).clip_contents:
			r = r.intersection(Rect2((a as Control).global_position, (a as Control).size))
		a = a.get_parent()
	return r


## 出界量 = 可见块超出卡片矩形最多的那一边(px)。
func _outside_amount(vis: Rect2, card: Rect2) -> float:
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return 0.0   # 被裁成空 = 什么都没画
	return maxf(maxf(card.position.x - vis.position.x, vis.end.x - card.end.x),
		maxf(card.position.y - vis.position.y, vis.end.y - card.end.y))
