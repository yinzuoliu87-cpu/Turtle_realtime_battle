extends Node
## 铁链从手上出(2026-11-11)。用户:「精英小将，你自己不看的吗？他射出这个锁链的时候，请问锁链有…从手上射出来吗？你自己没看吗？」
##   我自己看图时链头明明在拳头下面一截, 说成「已经飞出去一段」放过了 ⇒ 改成门禁量, 不靠眼看。
## 量法: 每帧画面摆好人物图之后(手动发 RenderingServer.frame_pre_draw = 开画前那一刻; 无头不画、引擎不发), 用人物图节点
##   (真显示的位置 / 格号 / 翻转 / 缩放)独立算出这一格拳头(精英 whip)/ 手腕(近战 throw、dive)那个像素在世界里的位置,
##   跟链头精灵上记的这一刻链子手端(meta chain_hand)比, 按人物图像素算距离。
## 站位: 目标在斜下方(最初出错的就是这种 —— 原来手端沿地面朝目标前推, 公告板投到屏幕上不在拳头上)。
## 不用 det 模式: 交互模式下画面按「上一步 ↔ 这一步」插值摆人物图(跟玩家看到的一样), 被拽飞得快时战斗坐标与画面差一截, 正是要量的。
## 变异(证明会红): 手端退回沿地面前推 / 拳头像素表错一格 / 拿掉开画前重摆 ⇒ ★ 那几条红。

const MAX_PX := 2.5

var _fail := 0


func _chk(name: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


## 人物图节点上第 (art.x, art.y) 个像素在世界里的位置 —— 只读节点(画面真摆的), 不读单位战斗坐标
func _art_world(s, spr: Sprite3D, art: Vector2) -> Vector3:
	var fw: float = float(spr.texture.get_width()) / float(maxi(1, spr.hframes))
	var fh: float = float(spr.texture.get_height()) / float(maxi(1, spr.vframes))
	var lx: float = (art.x - fw * 0.5) * (-1.0 if spr.flip_h else 1.0) + spr.offset.x
	var ly: float = spr.offset.y + fh * 0.5 - art.y
	var cb: Basis = s._cam.global_transform.basis
	return spr.global_position + (cb.x.normalized() * lx * spr.scale.x + cb.y.normalized() * ly * spr.scale.y) * spr.pixel_size


func _chain_hand(s):
	for c in s._world.get_children():
		if is_instance_valid(c) and c is Sprite3D and (c as Sprite3D).visible and c.has_meta("chain_hand"):
			return c.get_meta("chain_hand")
	return null


## 量一段: 每帧(art_fn 返回这一格该贴的像素, 没有 ⇒ 这一帧不量)
func _measure(s, u: Dictionary, art_fn: Callable, busy_fn: Callable, cap: int) -> Dictionary:
	var worst := 0.0
	var n := 0
	var n_moving := 0
	var p0: Vector2 = u["pos"]
	var w := 0
	while w < cap and bool(busy_fn.call()):
		await get_tree().process_frame
		RenderingServer.frame_pre_draw.emit()
		w += 1
		var spr = u.get("sprite", null)
		if not is_instance_valid(spr):
			continue
		var art = art_fn.call(spr)
		var hand = _chain_hand(s)
		if art == null or hand == null:
			continue
		var d: float = ((hand as Vector3) - _art_world(s, spr, art)).length() / maxf(1e-6, (spr as Sprite3D).pixel_size)
		worst = maxf(worst, d)
		n += 1
		if (u["pos"] as Vector2).distance_to(p0) > 20.0:
			n_moving += 1
	return {"worst": worst, "n": n, "moving": n_moving}


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for _i in range(6):
		await get_tree().process_frame
	s._deterministic = false
	print("=== 铁链从手上出(11-11) ===")

	## ① 精英小将·铁锁: 真单位进场, 嘲讽锁靶; 目标在右下方 280 码
	var e: Dictionary = s._spawn._make_unit("__minion__", "left", Vector2(400, 260), {"minion": true, "elite": true, "level": 1})
	var f: Dictionary = s._spawn._make_unit("stone", "right", Vector2(640, 380), {})
	f["maxHp"] = 50000.0; f["hp"] = 50000.0
	f["move_spd"] = 0.0; f["no_move"] = true
	s._units.append(e); s._units.append(f)
	e["_whip_cd"] = 0.0; e["stun_until"] = 0.0; e["_slam"] = false
	e["taunt_until"] = float(s._t) + 100.0; e["taunt_by"] = f
	e["untargetable_until"] = float(s._t) + 100.0
	for _i in range(3):
		await get_tree().process_frame
	s._tick_elite_whip(e)
	_chk("① 分母: 铁锁确实射出", bool(e.get("_slam", false)))
	var whip_art := func(spr) -> Variant:
		if str(e.get("anim_action", "")) != "whip":
			return null
		return EliteSystem.WHIP_FIST_ART[clampi((spr as Sprite3D).frame, 0, EliteSystem.WHIP_FIST_ART.size() - 1)]
	var m1: Dictionary = await _measure(s, e, whip_art, func() -> bool: return bool(e.get("_slam", false)), 900)
	print("  ① 精英铁锁: 量了 %d 帧(被拽着飞的 %d 帧), 链子手端离拳头最远 %.2f 像素" % [m1["n"], m1["moving"], m1["worst"]])
	_chk("① 分母: 量到 ≥ 20 帧, 其中被拽着飞的 ≥ 5 帧", int(m1["n"]) >= 20 and int(m1["moving"]) >= 5, "%d / %d" % [m1["n"], m1["moving"]])
	_chk("① ★每一帧链子手端都在拳头上(≤ %.1f 像素)" % MAX_PX, float(m1["worst"]) <= MAX_PX, "%.2f 像素" % float(m1["worst"]))

	## ② 近战小将·人体浪板: 出链(throw)贴手腕, 俯冲(dive)手腕随身体前倾
	var mn: Dictionary = s._spawn._make_unit("__minion__", "left", Vector2(360, 440), {"minion": true, "level": 1})
	var foe: Dictionary = s._spawn._make_unit("stone", "right", Vector2(860, 520), {})
	foe["maxHp"] = 50000.0; foe["hp"] = 50000.0
	foe["move_spd"] = 0.0; foe["no_move"] = true
	s._units.append(mn); s._units.append(foe)
	s._hiding_sys._sk_minion_bodysurf(mn, foe)
	var surf_art := func(spr) -> Variant:
		var act := str(mn.get("anim_action", ""))
		if act == "throw":
			return HidingSystem.SURF_WRIST_ART_THROW
		if act == "dive":
			return HidingSystem.SURF_WRIST_ART_DIVE[clampi((spr as Sprite3D).frame, 0, HidingSystem.SURF_WRIST_ART_DIVE.size() - 1)]
		return null
	var m2: Dictionary = await _measure(s, mn, surf_art, func() -> bool: return bool(mn.get("_slam", false)) and str(mn.get("anim_action", "")) != "surf", 900)
	print("  ② 近战浪板: 量了 %d 帧(飞的 %d 帧), 链子手端离手腕最远 %.2f 像素" % [m2["n"], m2["moving"], m2["worst"]])
	_chk("② 分母: 量到 ≥ 15 帧, 其中俯冲飞的 ≥ 5 帧", int(m2["n"]) >= 15 and int(m2["moving"]) >= 5, "%d / %d" % [m2["n"], m2["moving"]])
	_chk("② ★每一帧链子手端都在手腕上(≤ %.1f 像素)" % MAX_PX, float(m2["worst"]) <= MAX_PX, "%.2f 像素" % float(m2["worst"]))

	print("ALL PASS" if _fail == 0 else "FAILED %d" % _fail)
	await get_tree().process_frame
	get_tree().quit(1 if _fail > 0 else 0)
