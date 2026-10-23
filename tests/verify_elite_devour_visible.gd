extends Node
## verify_elite_devour_visible.gd — 精英「吞噬」的染黑 / 缩小玩家真的看得见(2026-10-23)
##
## 由来: 吞噬演出原来在 sim tween 里直接改目标立绘的 modulate / scale, 而渲染步(battle_render._update_world_transforms)
##   每帧按单位字段重写立绘 ⇒ 真实客户端里**从来看不见**; 只在录流的奇数步漏出过中间值(那次 verify_stream_seek 红的根源之一)。
##   用户 2026-10-23「肯定要修啊」。改成 sim 写单位字段 `_devour_k`, 渲染步按它画; 直播流靠 stream_recorder.UKEYS 带过去。
## 判据(量的是渲染步**画完之后**立绘的样子, 不是我写进去的字段):
##   ① 分母: 吞噬真的触发了、目标立绘在场、吞噬前是原色原大小
##   ② 吞噬进行到一半(按 sim 步推演出 tween), 跑一遍渲染步 ⇒ 立绘明显变暗、变小
##   ③ 演出被打断(精英先死)那条路 ⇒ 字段归零, 渲染步画回原色原大小
##   ④ 直播流的单位字段名单里有 `_devour_k`(手机端同一个渲染步才画得出来)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_elite_devour_visible.tscn

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SR := preload("res://scripts/systems/stream/stream_recorder.gd")
var _n := 0
var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


## 按 sim 步推进 sec 秒: 演出 tween 与延时回调都按固定步喂(与战斗场同一条路)
func _advance(scene, sec: float) -> void:
	var dt := 0.02
	var k := int(round(sec / dt))
	for _i in range(k):
		scene._t += dt
		scene._step_sim_tweens(dt)
		scene._ballistics._step_pending_shots(dt)


func _pair(scene) -> Array:
	var elite: Dictionary = scene._spawn._make_unit("__minion__", "left", Vector2(0, 0),
		{"minion": true, "role": "front", "elite": true, "level": 1})
	var prey: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(60, 0))
	prey["maxHp"] = 1000.0
	prey["hp"] = 50.0                       # 5% 血, 低于 15% 吞噬线
	scene._units.clear()
	scene._units.append(elite)
	scene._units.append(prey)
	return [elite, prey]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 精英「吞噬」染黑 / 缩小看得见 ===")
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene._t = 100.0

	var ps: Array = _pair(scene)
	var elite: Dictionary = ps[0]
	var prey: Dictionary = ps[1]
	var spr = prey.get("sprite", null)
	_ok("① 分母: 目标立绘在场", is_instance_valid(spr))
	if not is_instance_valid(spr):
		get_tree().quit(1)
		return
	scene._render._update_world_transforms()
	var c0: Color = (spr as Sprite3D).modulate
	var s0: float = (spr as Sprite3D).scale.x
	_ok("① 吞噬前: 原色(亮度 ≥ 0.95)", c0.r >= 0.95 and c0.g >= 0.95, str(c0))

	var fired: bool = scene._elite_sys._elite_try_consume(elite, prey)
	_ok("① ★分母: 濒死目标触发吞噬", fired)
	_advance(scene, 0.72)                   # tween 1.45 秒的一半
	_ok("① 分母: 吞噬到一半目标还活着(被吃之前)", bool(prey.get("alive", false)))
	scene._render._update_world_transforms()
	var c1: Color = (spr as Sprite3D).modulate
	var s1: float = (spr as Sprite3D).scale.x
	_ok("★★② 渲染步画完: 目标明显变暗(亮度 %.2f → %.2f)" % [c0.r, c1.r], c1.r <= c0.r * 0.75, str(c1))
	_ok("★★② 渲染步画完: 目标明显变小(%.3f → %.3f)" % [s0, s1], s1 <= s0 * 0.9)
	## 再跑一遍渲染步, 值不许被「每帧重写」盖回去(这正是原来看不见的原因)
	scene._render._update_world_transforms()
	_ok("★② 连跑两帧渲染步, 变暗变小仍在(没被每帧重写盖掉)", (spr as Sprite3D).modulate.r <= c0.r * 0.75 and (spr as Sprite3D).scale.x <= s0 * 0.9)

	## ③ 打断: 精英先死 ⇒ 放开目标, 字段归零, 画回原样
	var ps2: Array = _pair(scene)
	var elite2: Dictionary = ps2[0]
	var prey2: Dictionary = ps2[1]
	var spr2 = prey2.get("sprite", null)
	scene._render._update_world_transforms()
	var s20: float = (spr2 as Sprite3D).scale.x if is_instance_valid(spr2) else -1.0
	scene._elite_sys._elite_try_consume(elite2, prey2)
	_advance(scene, 0.72)
	elite2["alive"] = false
	_advance(scene, 1.0)
	scene._render._update_world_transforms()
	_ok("③ 分母: 被打断的目标活着、吞噬标记已撤", bool(prey2.get("alive", false)) and not bool(prey2.get("_consuming", true)))
	_ok("★③ 被打断 ⇒ 画回原色原大小", is_instance_valid(spr2) and (spr2 as Sprite3D).modulate.r >= 0.95
		and absf((spr2 as Sprite3D).scale.x - s20) < 0.001, "k=%s" % str(prey2.get("_devour_k", "无")))

	_ok("★④ 直播流单位字段名单里有 _devour_k(手机端同一个渲染步才画得出来)", SR.UKEYS.has("_devour_k"))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 精英吞噬看得见" if _fail == 0 and _n >= 10 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
