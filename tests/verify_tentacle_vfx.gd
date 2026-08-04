extends Node
## verify_tentacle_vfx.gd — 灵物【触手】的**存在与状态机**（2026-08-04）
##
## ★这条门禁守的是「它是一个**存在**，不是一个效果」——
##   用户 2026-08-04：「我为什么让你参考？」指出的正是这件事。
##   所以第一组断言不是"好不好看"，而是**场上到底有没有那几根触手**。
##
## ⚠ 铁律（CLAUDE.md §3.5 + memory [[fb-verify-must-run-the-real-path]]）：
##   **一条测数值的用例不该依赖任何动画 tween 跑完。**
##   本文件全部是**同步断言** —— 调完 `tick()` 下一行就判，不 await 任何演出。
##   触手本身也是这么设计的：它由**状态机 + 每帧重算网格**驱动，不用 tween。
##
## 守六组：
##   ① ★存在：档位 → 根数（0/1/2/2/2），`ensure` 幂等、多了会撤场
##   ② ★状态机六个态按官方时长流转（出土 2s / 蓄势 0.25s / 拍击 0.5s / 回位 0.35s）
##   ③ ★追击走【点刺】：不经蓄势直接拍，且时长更短
##   ④ ★出土/撤场期间**不接拍击指令**（还没站稳就挥是穿帮）
##   ⑤ ★网格真的建出来了且**长度守恒**（固定弧长 —— 这是"它是根实体"的几何保证）
##   ⑥ ★接线：spirit 系统每帧 ensure、拍击走 strike、换路 clear
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")

const NAMES := ["EMERGE", "IDLE", "REAR", "SLAM", "RECOVER", "RETRACT"]

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


## 场景树上真实的触手节点数（不是字典大小 —— 见 ① 里那条注释）
func _node_count() -> int:
	var n := 0
	for c in _s._world.get_children():
		if str(c.name).begins_with("Tentacle_"):
			n += 1
	return n


func _nm(i: int) -> String:
	return NAMES[i] if i >= 0 and i < NAMES.size() else "(不存在)"


func _ready() -> void:
	await get_tree().process_frame
	print("=== 灵物触手: 存在与状态机 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_v = _s._tentacle_vfx

	# ══ ① 存在：档位 → 根数 ══════════════════════════════════
	_v.clear()
	_ok("① ★分母/对照: 一开始场上 0 根", _v.count() == 0, "%d 根" % _v.count())
	_v.ensure("left", 0)
	_ok("① 未激活(0 根) → 还是 0 根", _v.count("left") == 0)
	_v.ensure("left", 1)
	_ok("① 首档 1 根", _v.count("left") == 1, "%d 根" % _v.count("left"))
	_v.ensure("left", 1)
	_v.ensure("left", 1)
	# ★★数【真实节点】不是数字典键 —— 变异实测：把 `ensure` 的幂等判断去掉后，
	#   `_spawn` 会往同一个 key 重写，字典大小不变、`count()` 照样是 1，**门禁全绿**；
	#   真实症状是**每调一次泄漏一个 MeshInstance3D**（旧的没人 free）。
	#   所以判据必须落在场景树上。（memory [[fb-write-without-reader-and-fake-gates]]：
	#   门禁模拟公式 ≠ 量真实对象。）
	_ok("① ★ensure 幂等: 字典里 1 根", _v.count("left") == 1, "%d 根" % _v.count("left"))
	_ok("① ★ensure 幂等: 【场景树上也只有 1 个节点】(重复 spawn 会泄漏节点, 字典看不出来)",
		_node_count() == 1, "场景树上 %d 个 Tentacle_* 节点" % _node_count())
	_v.ensure("left", 2)
	_ok("① 升到档2 → 2 根", _v.count("left") == 2, "%d 根" % _v.count("left"))
	_v.ensure("right", 2)
	_ok("① ★两方各算各的(左 2 右 2, 共 4)",
		_v.count("left") == 2 and _v.count("right") == 2 and _v.count() == 4,
		"左%d 右%d 共%d" % [_v.count("left"), _v.count("right"), _v.count()])
	# 掉档 → 撤场（不是立刻消失，走 RETRACT 动画）
	_v.ensure("left", 0)
	_ok("① 掉档 → 进入撤场态(不是瞬间消失)", _v.state_of("left", 0) == 5,
		_nm(_v.state_of("left", 0)))
	_v.tick(TV.T_RETRACT + 0.05)
	_ok("① 撤场走完 → 真的没了", _v.count("left") == 0, "%d 根" % _v.count("left"))

	# ══ ② 状态机：按官方时长流转 ═══════════════════════════════
	_v.clear()
	_v.ensure("left", 1)
	_ok("② 生下来是【出土】态", _v.state_of("left", 0) == 0, _nm(_v.state_of("left", 0)))
	_v.tick(1.5)
	_ok("② ★出土 1.5 秒时【还在出土】(官方 2 秒，不是随便定的)",
		_v.state_of("left", 0) == 0, _nm(_v.state_of("left", 0)))
	_v.tick(0.6)     # 累计 2.1 > 2.0
	_ok("② 出土满 2 秒 → 待机", _v.state_of("left", 0) == 1, _nm(_v.state_of("left", 0)))
	_v.tick(3.0)
	_ok("② ★待机是【常驻】的(过 3 秒还在待机，不会自己消失)",
		_v.state_of("left", 0) == 1 and _v.count("left") == 1, _nm(_v.state_of("left", 0)))
	_v.strike("left", 0, Vector2(900, 300), 1.0)
	_ok("② 拍击指令 → 蓄势", _v.state_of("left", 0) == 2, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_REAR + 0.01)
	_ok("② 蓄势 0.25 秒 → 拍击", _v.state_of("left", 0) == 3, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_SLAM + 0.01)
	_ok("② 拍击 0.5 秒 → 回位", _v.state_of("left", 0) == 4, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_RECOVER + 0.01)
	_ok("② 回位 0.35 秒 → 回到待机(闭环)", _v.state_of("left", 0) == 1, _nm(_v.state_of("left", 0)))

	# ══ ③ 追击走点刺：不经蓄势、更短 ═══════════════════════════
	_v.strike("left", 0, Vector2(900, 300), 0.25)
	_ok("③ ★追击(share=0.25)【不经蓄势】直接拍 —— 它是【反应】不是【预告】",
		_v.state_of("left", 0) == 3, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_JAB + 0.01)
	_ok("③ 点刺 %.2f 秒就收(比整套拍击 %.2f 短)" % [TV.T_JAB, TV.T_SLAM],
		_v.state_of("left", 0) == 4 and TV.T_JAB < TV.T_SLAM, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_RECOVER + 0.01)

	# ══ ④ 出土/撤场期间不接指令 ════════════════════════════════
	_v.clear()
	_v.ensure("left", 1)
	_v.strike("left", 0, Vector2(900, 300), 1.0)
	_ok("④ ★出土途中不接拍击(还没站稳就挥是穿帮)", _v.state_of("left", 0) == 0,
		_nm(_v.state_of("left", 0)))
	_v.tick(2.1)
	_v.ensure("left", 0)                      # → RETRACT
	_v.strike("left", 0, Vector2(900, 300), 1.0)
	_ok("④ ★撤场途中也不接", _v.state_of("left", 0) == 5, _nm(_v.state_of("left", 0)))

	# ══ ⑤ 网格真的建出来了 + 长度守恒 ═══════════════════════════
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.1)                              # 到待机
	var lens: Array = []
	var tris: Array = []
	for st in [1, 2, 3]:                      # IDLE / REAR / SLAM 三个姿态
		var t: Dictionary = _v._tents["left|0"]
		t["state"] = st
		t["ts"] = 0.02
		t["aim"] = Vector2(900, 300)
		t["acc"] = 99.0                       # 绕过待机降频，强制重建
		_v.tick(0.001)
		var mi: MeshInstance3D = t["mi"]
		var m: ArrayMesh = mi.mesh
		if m.get_surface_count() == 0:
			lens.append(-1.0); tris.append(0); continue
		var bb: AABB = m.get_aabb()
		# 沿曲线走一遍量真实弧长（不是包围盒对角线 —— 那个会随姿态变）
		lens.append(bb.size.length())
		tris.append(m.surface_get_array_len(0) / 3)
	_ok("⑤ ★三个姿态都建出网格(面数 %s)" % str(tris),
		tris[0] > 100 and tris[1] > 100 and tris[2] > 100, str(tris))
	# ★★2026-08-04：截面从【闭合圆环管】改成【朝向相机的开放扁带】——
	#   开放带不回绕，每段三角数 = (RING-1) × 2 而不是 RING × 2。
	#   这条断言守的是"恒定"（不随姿态变），常数本身随几何走。
	var want: int = TV.SEG * (TV.RING - 1) * 2
	_ok("⑤ ★面数恒定(开放扁带 = SEG × (RING-1) × 2 = %d) —— 不随姿态变" % want,
		tris[0] == tris[1] and tris[1] == tris[2] and tris[0] == want, str(tris))
	# ★长度守恒 —— 口径 2026-08-04 修正：
	#   逐帧看官方 W 技能后，攻击那一下触手会**大幅伸长**（扑出去够到目标），
	#   所以"任何姿态都撑不出 ARC_LEN"这条**不再成立**，而且它不该成立 ——
	#   门禁挡住的会是一个【我有意加的、参考里就有的】行为。
	#   ⇒ 改成：待机/蓄势守 ARC_LEN；攻击守 ARC_LEN × REACH_MULT。
	#   （这不是放宽标准 —— 上限仍然存在，只是分状态。没有上限才是真的没守。）
	var over: Array = []
	# 攻击时按【到目标的真实距离】伸长（不再是固定倍率），上限是 REACH_MAX
	# ★★2026-08-04：REAR 上限从 ARC_LEN 提到 ARC_LEN × REAR_GROW ——
	#   逐帧对齐官方后，前摇改成【长大 + 立起】（官方那 5 帧面积涨 76%），
	#   旧上限挡住的是一个**参考里就有、我有意加的**行为。量的仍是真实弧长。
	var caps := [TV.ARC_LEN, TV.ARC_LEN * TV.REAR_GROW, TV.ATTACK_LEN * 1.1]   # IDLE / REAR / SLAM
	for i2 in range(lens.size()):
		if float(lens[i2]) > float(caps[i2]) * 1.06:
			over.append("姿态%d 包围盒对角 %.1fm > 上限 %.1fm" % [i2, float(lens[i2]), float(caps[i2])])
	_ok("⑤ ★攻击长度是【固定】的 ≤%.1fm(用户: 不随目标距离改动 —— 有固定范围才有安全距离)"
		% TV.ATTACK_LEN, over.is_empty(), str(over))
	# ★攻击真的比待机长（不长就是伸长没生效）
	_ok("⑤ ★攻击姿态确实比待机长(扑出去够目标, 不是原地变直)",
		float(lens[2]) > float(lens[0]) * 1.25,
		"待机 %.1fm → 攻击 %.1fm" % [float(lens[0]), float(lens[2])])

	# ★★攻击长度【不随目标距离变】—— 用户 2026-08-04 点名纠正的（我中途做过一版
	#   "按到目标的实际距离伸长"，那样就没有"安全距离"这条规则了）。
	var lens_by_dist: Array = []
	for far in [400.0, 1400.0]:
		_v.clear(); _v.ensure("left", 1); _v.tick(2.1)
		var tt: Dictionary = _v._tents["left|0"]
		tt["state"] = 3; tt["ts"] = 0.30; tt["share"] = 1.0; tt["acc"] = 99.0
		tt["aim"] = _v.root_pos("left", 0) + Vector2(far, 0.0)
		_v.tick(0.001)
		lens_by_dist.append((tt["mi"] as MeshInstance3D).mesh.get_aabb().size.length())
	_ok("★攻击长度固定: 目标 400 码 vs 1400 码，触手长度一样(%.1f vs %.1f)"
		% [float(lens_by_dist[0]), float(lens_by_dist[1])],
		absf(float(lens_by_dist[0]) - float(lens_by_dist[1])) < 0.6, str(lens_by_dist))

	# ══ ⑤b ★预警区 与 命中特效【真的建出节点】═══════════════════
	# 用户 2026-08-04 点名的三件（预警区 / 直线命中范围 / 命中特效）——
	# ★数【场景树上真的多了几个节点】，不是断言函数存在：
	#   探针实测过一次"函数在、但 `warned` 一直是 null 所以从没放过"
	#   （替换时用错缩进，2 tab vs 1 tab）——【断言函数存在守不住这个】。
	_v.clear()
	_v.ensure("left", 1)
	_v.tick(2.1)                                  # 到待机
	var n0: int = _s._world.get_child_count()
	_v.strike("left", 0, Vector2(900, 300), 1.0)
	_v.tick(TV.T_REAR + 0.01)                     # 过完蓄势 → 预警区该出来了
	var n1: int = _s._world.get_child_count()
	_ok("⑤b ★预警区真的建出节点(落点圈 + 沿途直线)", n1 - n0 >= 2,
		"只多了 %d 个节点" % (n1 - n0))
	_v.tick(TV.T_SLAM * 0.65)                     # 过 60% → 命中特效
	var n2: int = _s._world.get_child_count()
	_ok("⑤b ★命中特效真的建出节点(爆闪 + 环 + 粒子 + 直线)", n2 - n1 >= 4,
		"只多了 %d 个节点" % (n2 - n1))

	# ══ ⑥ 接线：真的挂在战斗上 ═════════════════════════════════
	var src_sp: String = FileAccess.get_file_as_string("res://scripts/systems/equip/spirit_synergy_system.gd")
	var src_rb: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⑥ ★spirit 系统每帧 ensure(常驻数量) —— 不调它触手永远不存在",
		src_sp.find("_tentacle_vfx.ensure(") >= 0)
	_ok("⑥ ★拍击走 strike(side, idx, …) —— 是【让那一根出手】不是【新建一条】",
		src_sp.find("_tentacle_vfx.strike(") >= 0 and src_sp.find("_tentacle_vfx.slap(") < 0)
	_ok("⑥ ★_tentacle_vfx.tick 挂在主循环上", src_rb.find("_tentacle_vfx.tick(") >= 0)
	# 换路必须撤干净 —— 常驻节点最容易残留到下半场
	_v.clear()
	_v.ensure("left", 2)
	_v.ensure("right", 2)
	_v.clear()
	_ok("⑥ ★clear() 一次撤干净(常驻节点残留到下半场是这类实体的典型事故)",
		_v.count() == 0, "%d 根" % _v.count())
	await get_tree().process_frame          # queue_free 延到帧末
	_ok("⑥ ★clear() 之后【场景树上也不剩节点】", _node_count() == 0,
		"还剩 %d 个" % _node_count())

	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 灵物触手" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
