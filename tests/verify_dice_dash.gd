extends Node
## verify_dice_dash.gd — 稳定骰子真冲刺连突不卡死(用户2026-07-13报"碰到地图边界卡死")
##   落点=目标+冲刺方向×overshoot 可能算到场外→被clamp卡边界到不了落点→dice_dash_active永不结束=卡死
##   修: 落点clamp进场内 + 本段冲>1.6s超时强制结算. 本测证边界角落也能正常跑完连突.
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
func _ok(n, c, d=""):
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _run_corner(sc, dpos: Vector2, fpos: Vector2, label: String) -> void:
	sc._units.clear(); sc._t = 5.0
	var dice: Dictionary = sc._make_unit("dice", "left", dpos)
	var foe: Dictionary = sc._make_unit("basic", "right", fpos)
	foe["maxHp"] = 1.0e9; foe["hp"] = 1.0e9   # 打不死→连突跑满所有段
	sc._units.append(dice); sc._units.append(foe)
	sc._sk_dice_flash_strike(dice)
	_ok("[%s] 放技→进入冲刺连突态" % label, dice.get("dice_dash_active", false) == true)
	var steps := 0
	while dice.get("dice_dash_active", false) and steps < 3000:
		sc._t += 0.05
		sc._dice_dash_tick(dice, 0.05)
		steps += 1
	_ok("[%s] ★边界不卡死(连突正常结束)" % label, not dice.get("dice_dash_active", false), "steps=%d" % steps)
	# 位置始终在场内
	var inb: bool = dice["pos"].x >= sc.ARENA.position.x and dice["pos"].x <= sc.ARENA.end.x and dice["pos"].y >= sc.ARENA.position.y and dice["pos"].y <= sc.ARENA.end.y
	_ok("[%s] 骰子龟始终在场内" % label, inb, str(dice["pos"]))

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)

	# 右下角: 冲刺方向朝界外 → 落点被clamp
	_run_corner(sc, Vector2(sc.ARENA.end.x - 120.0, sc.ARENA.end.y - 120.0), Vector2(sc.ARENA.end.x - 30.0, sc.ARENA.end.y - 30.0), "右下角")
	# 左上角
	_run_corner(sc, Vector2(sc.ARENA.position.x + 120.0, sc.ARENA.position.y + 120.0), Vector2(sc.ARENA.position.x + 30.0, sc.ARENA.position.y + 30.0), "左上角")
	# 正常中间(对照)
	_run_corner(sc, Vector2(600.0, 400.0), Vector2(900.0, 400.0), "中间")

	print("")
	print(("ALL PASS — 稳定骰子冲刺连突边界不卡死" if _fail == 0 else "FAIL x%d" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)
