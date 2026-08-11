extends Node
## verify_cake_box_form.gd — 072 铁皮蛋糕盒【化身礼盒要真的换立绘】(2026-08-11)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-08-11「换」——「化身蛋糕礼盒」要真换立绘, 不是只加个标记
## ══════════════════════════════════════════════════════════════════
## 改之前 `_box_enter()` 改的全是**属性**(射程改近战、关本体普攻、换技能),
## 视觉上只有一次性的 `box_close_fx` ⇒ **属性变了、长相还是龟**,
## 玩家不知道自己已经"化身蛋糕礼盒"。
##
## ★为什么换的是 `idle_sd` 而不是直接设 `spr.texture`:
##   `battle_render` 每帧会用 `u["idle_sd"]` 把立绘还原到 idle(动作播完就回 idle),
##   直接改贴图下一帧就被抹掉 —— **换源头才能持久**。这条门禁焊的就是这一点。
##
## ★断言的是**真实节点的 texture**, 不是"我设过一个字段"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_cake_box_form.tscn --quit-after 1500

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BOX_TEX := "res://assets/sprites/vfx/eq072-cake-box.png"

var _s
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 072 铁皮蛋糕盒: 化身礼盒要真换立绘 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	_ok("★分母: 礼盒立绘素材在位", ResourceLoader.exists(BOX_TEX), BOX_TEX)

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c)
	u["alive"] = true
	u["hp"] = 3000.0
	u["maxHp"] = 3000.0
	u["equips"] = [{"id": "p2eq_072", "star": 3}]
	u["eq_state"] = {}
	_s._units.append(u)
	await get_tree().process_frame

	var spr: Sprite3D = u.get("sprite", null)
	_ok("★分母: 单位有立绘节点", is_instance_valid(spr))
	if not is_instance_valid(spr):
		print("FAIL x1"); get_tree().quit(1); return
	var tex0: Texture2D = spr.texture
	_ok("★分母: 变身前有一张原立绘", tex0 != null,
		"原图 %s" % (tex0.resource_path if tex0 != null else "<null>"))

	# ── ① 进礼盒形态 ⇒ 立绘必须真的换成礼盒 ─────────────────────
	var fb = _s._equip_sys._food_sys
	fb._box_enter(u, 2, u["eq_state"].get("p2eq_072", {}))
	await get_tree().process_frame
	var tex1: Texture2D = (u.get("sprite") as Sprite3D).texture
	_ok("① ★★进礼盒形态后, 立绘【真的】换成了礼盒图",
		tex1 != null and str(tex1.resource_path).find("eq072-cake-box") >= 0,
		"实得 %s" % (tex1.resource_path if tex1 != null else "<null>"))
	_ok("① ★换的是 `idle_sd` 源头(不是只改一帧贴图) —— 否则渲染层下一帧就抹掉了",
		(u.get("idle_sd", {}) as Dictionary).get("tex", null) == tex1)

	# ── ② 出盒 ⇒ 必须换回原立绘 ────────────────────────────────
	fb._box_unbox(u, "damage")
	await get_tree().process_frame
	var tex2: Texture2D = (u.get("sprite") as Sprite3D).texture
	_ok("② ★★出盒后换回原立绘(漏了就会\"盾早破了人还是个盒子\")",
		tex2 == tex0,
		"原 %s / 现 %s" % [(tex0.resource_path if tex0 else "?"), (tex2.resource_path if tex2 else "?")])
	_ok("② `idle_sd` 也还原了(不然下一次动作播完又变回盒子)",
		(u.get("idle_sd", {}) as Dictionary).get("tex", null) == tex0)

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 072 礼盒形态换立绘" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
