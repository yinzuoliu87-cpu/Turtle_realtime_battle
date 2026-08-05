extends Node
## verify_tentacle_continuity.gd — 触手状态边界的【参数连续性】（2026-08-05）
##
## ★★★为什么必须有这条：
##   用户 2026-08-05：「这就是漏洞啊，为什么有漏洞？我让你做了这么多遍了还做不好吗」
##   —— 他发现前摇入口的卷曲量从预警末的 50° 跳回 262°（整条又卷回去再放开）。
##
##   根因**不是**"不够仔细"，是**没有机制**：
##   每改一个状态的姿态曲线，都要手工去接它前后邻居的参数，全靠人记。
##   那次我接了角度（`lerpf(101.0, ANG_REAR[0], r)`），
##   **同一个 return 里的卷曲量那一项忘了改** —— 五个边界 × 三个参数，靠仔细必然会漏。
##   而且当时所有门禁都不守边界连续性，漏了也不会红。
##
## ⇒ 本文件遍历**每一个状态转移**，断言 `_phase_at` 给出的
##   [根部角, 梢端角, 卷曲量] 在边界两侧连续。
##   任何一处以后被改断，这里立刻红。
##
## ★判据是"前一状态跑到时长末"与"后一状态从 0 开始"两组参数的差 ——
##   量的是产品代码真实返回的值，不是我在测试里重算一遍公式。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_continuity.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")

const ST_EMERGE := 0
const ST_IDLE := 1
const ST_REAR := 2
const ST_SLAM := 3
const ST_RECOVER := 4
const ST_WARN := 6
const NAMES := ["出土", "待机", "前摇", "拍击", "收回", "撤场", "预警"]

var _n := 0
var _fail := 0
var _s
var _v


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _phase(t: Dictionary, st: int, ts: float) -> Array:
	t["state"] = st
	t["ts"] = ts
	return _v._phase_at(t, ts)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 状态边界参数连续性 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_v = _s._tentacle_vfx
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.1)
	var t: Dictionary = _v._tents["left|0"]
	t["share"] = 1.0
	t["aim"] = _v.root_pos("left", 0) + Vector2(300.0, 40.0)

	# 每条转移：[前一状态, 它的时长, 后一状态, 说明]
	var edges: Array = [
		[ST_IDLE, 0.0, ST_WARN, "待机 → 预警"],
		[ST_WARN, TV.T_WARN, ST_REAR, "预警 → 前摇"],
		[ST_REAR, TV.T_REAR, ST_SLAM, "前摇 → 拍击"],
		[ST_SLAM, TV.T_SLAM, ST_RECOVER, "拍击 → 收回"],
		[ST_RECOVER, TV.T_RECOVER, ST_IDLE, "收回 → 待机"],
	]
	# 角度阈值宽一点（度）、卷曲量阈值按比例 —— 但都远小于"整条重新卷起来"那种量级
	var lim_ang := 12.0
	var lim_curl := 26.0
	var bad: Array = []
	for e in edges:
		var a: Array = _phase(t, int(e[0]), float(e[1]))
		var b: Array = _phase(t, int(e[2]), 0.0)
		var d0: float = absf(float(a[1]) - float(b[1]))
		var d1: float = absf(float(a[2]) - float(b[2]))
		var d2: float = absf(float(a[3]) - float(b[3]))
		var okk: bool = d0 <= lim_ang and d1 <= lim_ang and d2 <= lim_curl
		_ok("★%s 参数连续" % str(e[3]), okk,
			"根部Δ%.1f° 梢端Δ%.1f° 卷曲Δ%.1f°  (%s末 %.0f/%.0f/%.0f → %s初 %.0f/%.0f/%.0f)"
				% [d0, d1, d2, NAMES[int(e[0])], float(a[1]), float(a[2]), float(a[3]),
					NAMES[int(e[2])], float(b[1]), float(b[2]), float(b[3])])
		if not okk:
			bad.append(str(e[3]))

	# ★分母自证：这条门禁真的能抓到断点 —— 拿一对【本来就该不同】的状态验它不是恒真式
	var x: Array = _phase(t, ST_IDLE, 0.0)
	var y: Array = _phase(t, ST_SLAM, TV.T_SLAM)
	_ok("★自证: 判据能分辨差异(待机初 vs 拍击末 应当明显不同)",
		absf(float(x[2]) - float(y[2])) > lim_ang * 2.0,
		"梢端角 %.0f° vs %.0f°" % [float(x[2]), float(y[2])])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 触手状态边界连续" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
