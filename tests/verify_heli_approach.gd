extends Node
## verify_heli_approach.gd — 080 直升机【不许瞬移】
##
## ══════════════════════════════════════════════════════════════════════════
##  由来: 用户 2026-08-07 看干净台第一句「直升机小了，你用瞬移了？」
## ══════════════════════════════════════════════════════════════════════════
## **是的, 原来就是一行瞬移**: `_heli_begin_bomb` 里 `h["pos"] = Vector2(h["lane_a"])`
## 把直升机**直接挪到航线起点**。航线长 800 码, 起点离它当前位置最远就是这个量级,
## 这一跳在场上非常显眼 —— 而 `verify_eq_gun_batch` 全绿, 因为那份门禁验的是
## 「航线长不长、覆盖几个敌人、每枚炸弹落点对不对」。**没有一条问过"它是怎么到那儿的"。**
##
## ── 判据 ──
## ① `_heli_begin_bomb` 之后状态是 **approach** 而不是直接 bomb, 且**位置没变**
## ② `_heli_approach` 每帧位移 ≈ HELI_APPROACH_SPD × delta(**这就是"在飞"的定义**)
## ③ 飞到位才转 bomb
## ④ **兜底超时存在**: 起点若在飞不到的地方(障碍/场外), 不能永远卡在 approach
## ⑤ 龟能满时 approach 状态**不会**被重新指派航线(否则会原地抖)
##
## ⚠ 期望值写字面量; 速度那条用**两个不同 delta** 各验一次(帧率无关)。
## ⚠ 全同步: 直接调 `_heli_approach(h, delta)` 喂 delta, 不等任何演出(CLAUDE.md §3.5)。

var _n := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 080 直升机不许瞬移 ===")
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(s)
	for i in range(20):
		await get_tree().process_frame
	var gun = s._equip_sys._gun_sys if s._equip_sys != null else null
	_ok("★分母: 拿到 080 的效果层", gun != null)
	if gun == null:
		_done(); return

	# ── 合成一架直升机: 起点离航线起点 700 码(接近整条航线的长度)
	var start := Vector2(300.0, 400.0)
	var lane_a := Vector2(1000.0, 400.0)
	var h: Dictionary = {
		"owner": {"side": "left", "pos": start, "alive": true},
		"pos": start, "lane_a": lane_a, "lane_b": lane_a + Vector2(800.0, 0.0),
		"state": "approach", "rotor": 0.0, "energy": 0.0, "appr_t": 0.0,
	}

	# ② 每帧位移 = 速度 × delta(两个 delta 各验一次 ⇒ 帧率无关)
	for dt in [0.016, 0.05]:
		var before: Vector2 = Vector2(h["pos"])
		gun._heli_approach(h, dt)
		var moved: float = (Vector2(h["pos"]) - before).length()
		var want: float = 620.0 * dt        # ★字面量: 与 HELI_APPROACH_SPD 同值但不引用它
		_ok("② delta=%.3f 时位移 = 速度×delta(±2%%)" % dt,
			absf(moved - want) <= want * 0.02, "实测 %.2f 码 / 期望 %.2f 码" % [moved, want])
		_ok("② delta=%.3f 时仍在 approach(没到就不该转 bomb)" % dt,
			str(h["state"]) == "approach", str(h["state"]))

	# ★分母: 它真的在朝航线起点飞(而不是随便动)
	var d0: float = (lane_a - start).length()
	var d1: float = (lane_a - Vector2(h["pos"])).length()
	_ok("★分母: 离航线起点更近了", d1 < d0, "%.1f → %.1f 码" % [d0, d1])

	# ③ 飞到位才转 bomb —— 一路喂到它到位
	var guard := 0
	while str(h["state"]) == "approach" and guard < 400:
		gun._heli_approach(h, 0.02)
		guard += 1
	_ok("③ 最终转入 bomb", str(h["state"]) == "bomb", "用了 %d 帧 = %.2f 秒" % [guard, guard * 0.02])
	_ok("③ 到位时正好落在航线起点", Vector2(h["pos"]).distance_to(lane_a) < 1.0,
		"距起点 %.2f 码" % Vector2(h["pos"]).distance_to(lane_a))
	# 700 码 ÷ 620 码/秒 ≈ 1.13 秒。这条同时守住"没有偷偷瞬移"(瞬移会让帧数 ≈ 1)
	_ok("③ 用的时间 ≈ 距离÷速度(不是一步到位)", guard >= 40 and guard <= 90,
		"%d 帧(期望 40~90)" % guard)

	# ④ 兜底超时: 起点设在永远飞不到的地方(每帧把它推回去)
	var h2: Dictionary = {
		"owner": {"side": "left", "pos": start, "alive": true},
		"pos": start, "lane_a": Vector2(99999.0, 400.0), "lane_b": Vector2(99999.0, 400.0),
		"state": "approach", "rotor": 0.0, "energy": 0.0, "appr_t": 0.0,
	}
	var g2 := 0
	while str(h2["state"]) == "approach" and g2 < 1000:
		gun._heli_approach(h2, 0.02)
		g2 += 1
	_ok("④ 飞不到时有兜底超时(不会永远卡在 approach)", str(h2["state"]) == "bomb",
		"%d 帧 = %.2f 秒" % [g2, g2 * 0.02])

	# ── ⑥ **就近进场**: 两个端点里必须选离直升机近的那个当起点
	#    由来: 用户 2026-08-07「这种情况为什么不从右往左？不智能吗」——
	#    原来起点写死成 `中心 − 方向×半长`, 而方向只由"哪条带覆盖敌人最多"决定,
	#    **跟直升机在哪边毫无关系** ⇒ 它经常绕到远端再飞回来。
	#    航线是双向对称的带, 从哪头进结算完全一样, 所以这纯粹是"看着傻不傻"的问题。
	for side in [-1.0, 1.0]:
		var hx: Dictionary = {
			"owner": {"side": "left", "pos": Vector2(0.0, 0.0), "alive": true},
			"pos": Vector2(600.0 * side, 400.0), "state": "patrol",
			"rotor": 0.0, "energy": 0.0,
		}
		gun._helis.clear()
		gun._helis.append(hx)
		# 造两个敌人, 让最优航线是水平的
		var e_a: Dictionary = {"pos": Vector2(-200.0, 400.0), "alive": true, "side": "right"}
		var e_b: Dictionary = {"pos": Vector2(200.0, 400.0), "alive": true, "side": "right"}
		s._units.append(e_a)
		s._units.append(e_b)
		gun._heli_begin_bomb(hx)
		var la: Vector2 = Vector2(hx.get("lane_a", Vector2.ZERO))
		var lb: Vector2 = Vector2(hx.get("lane_b", Vector2.ZERO))
		var d_a: float = Vector2(hx["pos"]).distance_to(la)
		var d_b: float = Vector2(hx["pos"]).distance_to(lb)
		_ok("⑥ 直升机在 x=%.0f 时, 起点取【近端】" % (600.0 * side), d_a <= d_b,
			"到起点 %.0f 码 / 到终点 %.0f 码" % [d_a, d_b])
		s._units.erase(e_a)
		s._units.erase(e_b)
	gun._helis.clear()

	# ① 结构: 开轰炸时不许直接写 pos = lane_a
	var src := FileAccess.get_file_as_string("res://scripts/systems/equip/eq_gun_batch.gd")
	_ok("★分母: 读到了源码", src.length() > 1000, "%d 字符" % src.length())
	var i_begin: int = src.find("func _heli_begin_bomb")
	var i_end: int = src.find("func ", i_begin + 10)
	var body: String = src.substr(i_begin, maxi(0, i_end - i_begin))
	_ok("① _heli_begin_bomb 里没有【直接把 pos 挪到航线起点】那一行",
		not body.contains("h[\"pos\"] = Vector2(h[\"lane_a\"])"),
		"函数体 %d 字符" % body.length())
	_ok("① 它把状态置为 approach", body.contains("\"approach\""))

	_done()


func _ok(name: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  — " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  — " + extra) if extra != "" else ""])


func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS (%d/%d)" % [_n, _n])
		get_tree().quit(0)
	else:
		print("FAIL x%d (共 %d 条)" % [_fail, _n])
		get_tree().quit(1)
