extends Node
## verify_fortune_final_carry.gd — 财神龟「招财进宝」的临时装备进度跟进终极战场(2026-10-21 查实的 bug)。
##
## bug: 换路时幸存快照(dual_lane_flow._dl_snapshot_survivors)把临时装备随 equips 带过去了,
##   但「已抽 / 几星 / 当前消耗」没带 ⇒ 终极战场里 buyequip_star 回到 0, 再放技能【又抽一件】,
##   身上两件临时装备, 原来那件也不再升星。
## 判据走真实的快照 → 重建两步(_dl_snapshot_survivors → _spawn_lane_side), 不手搓 spec。
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fail := 0
var _n := 0
func _ok(n, c, d=""):
	_n += 1
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true
	var sc = RTScene.new(); add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	sc.set_process(false); sc.set_physics_process(false)
	sc._t = 10.0
	sc._units.clear()
	var f: Dictionary = sc._spawn._make_unit("fortune", "left", Vector2(400, 400))
	sc._units.append(f)
	# 上路: 首抽 + 升一星 ⇒ 2★
	sc._fortune_sys._sk_fortune_buyequip(f)
	var iid: String = str(f.get("buyequip_id", ""))
	_ok("★分母: 上路首抽拿到一件临时装备", iid != "" and int(f.get("buyequip_star", 0)) == 1, iid)
	sc._fortune_sys._sk_fortune_buyequip(f)
	_ok("★分母: 上路升到 2★", int(f.get("buyequip_star", 0)) == 2)
	var cost_before: float = float(f["energy_cost"].get("fortuneBuyEquip", 0.0))
	# 真实幸存快照 → 终极战场重建
	GameState.dual_survivors = {"left": [], "right": []}
	sc._dl_sys._dl_snapshot_survivors()
	var specs: Array = GameState.dual_survivors.get("left", [])
	_ok("★分母: 财神龟进了幸存名单", specs.size() == 1, str(specs.size()))
	sc._units.clear()
	sc._spawn._spawn_lane_side(specs, "left", 1, Vector2(400, 400))
	var g: Dictionary = {}
	for u in sc._units:
		if str(u.get("id", "")) == "fortune":
			g = u
	_ok("★分母: 终极战场里重建出了财神龟", not g.is_empty())
	if not g.is_empty():
		_ok("★★进度跟过去: 仍是同一件、仍是 2★", str(g.get("buyequip_id", "")) == iid and int(g.get("buyequip_star", 0)) == 2,
			"id=%s star=%d" % [str(g.get("buyequip_id", "")), int(g.get("buyequip_star", 0))])
		_ok("★消耗跟过去(不回到首抽价)", is_equal_approx(float(g["energy_cost"].get("fortuneBuyEquip", 0.0)), cost_before),
			"%.1f vs %.1f" % [float(g["energy_cost"].get("fortuneBuyEquip", 0.0)), cost_before])
		sc._fortune_sys._sk_fortune_buyequip(g)
		_ok("★★终极战场再放: 升到 3★, 不再抽第二件", int(g.get("buyequip_star", 0)) == 3 and str(g.get("buyequip_id", "")) == iid,
			"star=%d id=%s" % [int(g.get("buyequip_star", 0)), str(g.get("buyequip_id", ""))])
	print("")
	print(("ALL PASS — 财神龟临时装备进度跨进终极战场(%d 条)" % _n) if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
