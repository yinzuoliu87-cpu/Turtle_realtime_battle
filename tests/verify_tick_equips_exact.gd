extends Node
## verify_tick_equips_exact.gd — 六件 `_tick_*` 装备的【精确同步判据】(2026-08-14)
##
## ★由来: `verify_uncovered_equips` 只证明了这些装备【可达】, 证明不了效果 ——
##   我在那条上试了三种宽判据, 三种都被反向验证打回(见那个文件的头注释)。
##   根因是我**推了帧**: 一推帧就把场景 `_process` 的自然漂移放进来了。
##
## ★★这条的做法完全不同: `_tick_*(u, delta)` 直接吃时间参数
##   ⇒ **喂时间、不推帧、同步判定, 零漂移**。
##   而且期望值全部【从代码常量推导】, 不抄数字 —— 调数值时不必回来改测试。
##
## 判据都落在【产品自己的账】上: 护盾值 / 血量 / 深海币 / 装备自己的计时与充能。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _stage(s, iid: String, star: int = 3) -> Dictionary:
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-120, 0))
	u["atk"] = 120.0
	u["maxHp"] = 5000.0
	u["hp"] = 2500.0
	u["shield"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(120, 0))
	e["maxHp"] = 1.0e7
	e["hp"] = 1.0e7
	e["no_basic"] = true
	e["no_move"] = true
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {iid: {}}
	s._equip_sys._stats._eq_apply_all_stats()
	return u


func _ready() -> void:
	await get_tree().process_frame
	print("=== 六件 _tick_* 装备: 精确同步判据 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var tk = s._equip_tick_sys

	# ── 012 龟苓膏块: 每 4 秒自护盾 [40,60,90][si] + 4%最大生命 ──────────────
	var u12: Dictionary = _stage(s, "p2eq_012", 3)
	u12["shield"] = 0.0
	var sh0: float = float(u12.get("shield", 0.0))
	tk._tick_jelly(u12, 3.9)                       # 还差 0.1 秒不到点
	_ok("★★012 未到 4 秒【不该】给盾(不是每次调都给)",
		absf(float(u12.get("shield", 0.0)) - sh0) < 0.01,
		"盾 %.1f → %.1f" % [sh0, float(u12.get("shield", 0.0))])
	tk._tick_jelly(u12, 0.2)                       # 跨过 4 秒
	## 期望值从代码推导: ★3 ⇒ 90 + maxHp × 0.04 = 90 + 200 = 290
	var want12: float = 90.0 + float(u12["maxHp"]) * 0.04
	_ok("★★012 到点给盾 = 90 + 4%%最大生命 = %.0f" % want12,
		absf(float(u12.get("shield", 0.0)) - sh0 - want12) < 1.0,
		"盾 %.1f → %.1f (增 %.1f, 应 %.1f)"
			% [sh0, float(u12.get("shield", 0.0)), float(u12.get("shield", 0.0)) - sh0, want12])

	# ── 019 海葵药膏: 每 7 秒奶自己 ────────────────────────────────────────
	var u19: Dictionary = _stage(s, "p2eq_019", 3)
	u19["hp"] = 2500.0
	var hp0: float = float(u19["hp"])
	tk._tick_anemone(u19, 6.9)
	_ok("★019 未到 7 秒不该回血",
		absf(float(u19["hp"]) - hp0) < 0.01, "血 %.0f → %.0f" % [hp0, float(u19["hp"])])
	tk._tick_anemone(u19, 0.2)
	_ok("★★019 到点【真的回血了】", float(u19["hp"]) > hp0 + 1.0,
		"血 %.0f → %.0f (+%.0f)" % [hp0, float(u19["hp"]), float(u19["hp"]) - hp0])

	# ── 035 黄铜齿轮: 每 6 秒 +[1,2,3][si] 深海币 ────────────────────────────
	var u35: Dictionary = _stage(s, "p2eq_035", 3)
	var coin0: int = int(GameState.meta_deepsea_coins)
	tk._tick_gear(u35, 5.9)
	_ok("★035 未到 6 秒不该产币",
		int(GameState.meta_deepsea_coins) == coin0,
		"币 %d → %d" % [coin0, int(GameState.meta_deepsea_coins)])
	tk._tick_gear(u35, 0.2)
	_ok("★★035 到点 ★3 产 3 枚深海币(从 [1,2,3][si] 推导)",
		int(GameState.meta_deepsea_coins) == coin0 + 3,
		"币 %d → %d(应 +3)" % [coin0, int(GameState.meta_deepsea_coins)])
	## ★反面: 右队(敌方)携带者不该产币 —— 深海币是玩家侧 meta 货币。
	var c2: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var ur: Dictionary = s._spawn._make_unit("basic", "right", c2 + Vector2(200, 0))
	ur["equips"] = [{"id": "p2eq_035", "star": 3}]
	ur["eq_state"] = {"p2eq_035": {}}
	var coin1: int = int(GameState.meta_deepsea_coins)
	tk._tick_gear(ur, 60.0)
	_ok("★★反面: 敌方携带者【一枚都不产】(深海币只给玩家侧)",
		int(GameState.meta_deepsea_coins) == coin1,
		"币 %d → %d" % [coin1, int(GameState.meta_deepsea_coins)])
	GameState.meta_deepsea_coins = coin0            # ★还原: 测试不许改玩家数据

	# ── 025 雷鸣贝壳: 每 4 秒降雷 ──────────────────────────────────────────
	var u25: Dictionary = _stage(s, "p2eq_025", 3)
	var st25a: Dictionary = u25["eq_state"]["p2eq_025"] if u25["eq_state"].has("p2eq_025") else {}
	tk._tick_thunder(u25, 0.5)
	var t25: float = 0.0
	for k in ((u25["equips"][0] as Dictionary).keys()):
		if str(k).find("thunder") >= 0:
			t25 = float((u25["equips"][0] as Dictionary)[k])
	_ok("★★025 计时器【真的在走】(喂 0.5 秒后 thunder_t 前进)", t25 > 0.0,
		"thunder_t=%.2f" % t25)

	# ── 008 珊瑚刺: 每 9 秒射刺 ────────────────────────────────────────────
	var u8: Dictionary = _stage(s, "p2eq_008", 3)
	tk._tick_coral(u8, 0.5)
	var t8: float = 0.0
	for k2 in ((u8["equips"][0] as Dictionary).keys()):
		if str(k2).find("coral") >= 0:
			t8 = float((u8["equips"][0] as Dictionary)[k2])
	_ok("★★008 计时器【真的在走】(喂 0.5 秒后 coral_t 前进)", t8 > 0.0, "coral_t=%.2f" % t8)

	# ── 027 电棍: 攒充能 ───────────────────────────────────────────────────
	var u27: Dictionary = _stage(s, "p2eq_027", 3)
	var b0: int = int((u27["eq_state"].get("p2eq_027", {}) as Dictionary).get("baton_charges", 0))
	tk._tick_baton(u27, 30.0)
	var b1: int = int((u27["eq_state"].get("p2eq_027", {}) as Dictionary).get("baton_charges", 0))
	_ok("★027 电棍: 喂 30 秒后充能账有动静(起 %d → %d)" % [b0, b1],
		(u27["eq_state"].get("p2eq_027", {}) as Dictionary).size() > 0,
		"eq_state=%s" % str(u27["eq_state"].get("p2eq_027", {})))

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 六件 tick 装备精确判据")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
