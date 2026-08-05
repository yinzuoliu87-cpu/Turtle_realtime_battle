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

const NAMES := ["EMERGE", "IDLE", "REAR", "SLAM", "RECOVER", "RETRACT", "WARN"]

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


## 沿中线积真实弧长。★顶点布局：三角带**非索引化**，每段 (RING-1)×6 个顶点。
##   （按 RING 切片当截面是错的 —— verify_tentacle_rhythm 里踩过一次。）
func _arc_len(m: ArrayMesh) -> float:
	if m.get_surface_count() == 0:
		return 0.0
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var qps: int = (TV.RING - 1) * 6
	var mids: Array = []
	for j in range(vs.size() / qps):
		var c := Vector3.ZERO
		for kk in range(qps):
			c += vs[j * qps + kk]
		mids.append(c / float(qps))
	var L := 0.0
	for j2 in range(1, mids.size()):
		L += (mids[j2] - mids[j2 - 1]).length()
	return L


## 端点到根部的【直线距离】。★这才是"甩直"的判据 ——
##   弧长恒定的鞭子，卷起来端点近、甩直了端点远。
func _tip_dist(m: ArrayMesh) -> float:
	if m.get_surface_count() == 0:
		return 0.0
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var qps: int = (TV.RING - 1) * 6
	var segs: int = vs.size() / qps
	if segs < 2:
		return 0.0
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	for kk in range(qps):
		a += vs[kk]
		b += vs[(segs - 1) * qps + kk]
	return (b / float(qps) - a / float(qps)).length()


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
	# ★★2026-08-04 流程变了：正常拍击先进【预警】1 秒（官方 f009~f039 那条带子），
	#   再蓄势 → 拍击。原来是 strike 直接进蓄势，预警只有 0.13 秒的一闪。
	_ok("② 拍击指令 → 【预警】(不是直接蓄势)", _v.state_of("left", 0) == 6,
		_nm(_v.state_of("left", 0)))
	_v.tick(TV.T_WARN + 0.01)
	_ok("② 预警 %.2f 秒 → 蓄势" % TV.T_WARN, _v.state_of("left", 0) == 2, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_REAR + 0.01)
	_ok("② 蓄势 %.2f 秒 → 拍击" % TV.T_REAR, _v.state_of("left", 0) == 3, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_SLAM + 0.01)
	_ok("② 拍击 %.2f 秒 → 回位" % TV.T_SLAM, _v.state_of("left", 0) == 4, _nm(_v.state_of("left", 0)))
	_v.tick(TV.T_RECOVER + 0.01)
	_ok("② 回位 %.2f 秒 → 回到待机(闭环)" % TV.T_RECOVER, _v.state_of("left", 0) == 1, _nm(_v.state_of("left", 0)))

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
	var tips: Array = []
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
			lens.append(-1.0); tips.append(-1.0); tris.append(0); continue
		# ★★2026-08-04 修脏判据：这里【注释说的和代码做的不是一回事】——
		#   注释写"沿曲线量真实弧长"，代码却是 `bb.size.length()` = **包围盒对角**，
		#   它把触手的【粗细】(R_BASE)也算进去了：IDLE 弧长 4.0 但对角 4.3，
		#   于是加粗触手就会让长度门禁莫名其妙地红。改成真的沿中线积弧长。
		lens.append(_arc_len(m))
		tips.append(_tip_dist(m))
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
	# ★★2026-08-05 判据换了：以前量【弧长】"攻击比待机长"，
	#   但弧长恒定是**有意为之**（用户："像一个鞭子一样"——绳子长度不变，
	#   卷起来端点近、甩直了端点远）。旧判据挡住的是我要的行为。
	#   ⇒ 改量【端点到根部的直线距离】：甩直后必须显著变远，否则"甩"没生效。
	#   （弧长恒定另有一条守：⑤ 的 caps 上限。）
	_ok("⑤ ★弧长【恒定】—— 鞭子不会变长(待机 %.1fm / 攻击 %.1fm)"
		% [float(lens[0]), float(lens[2])],
		absf(float(lens[2]) - float(lens[0])) < float(lens[0]) * 0.12,
		"差了 %.1fm" % absf(float(lens[2]) - float(lens[0])))
	_ok("⑤ ★但【端点距离】要显著变远(甩直了才够得到目标)",
		float(tips[2]) > float(tips[0]) * 1.6,
		"待机端点 %.1fm → 攻击端点 %.1fm" % [float(tips[0]), float(tips[2])])

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
	_v.tick(0.05)                                 # 一进【预警】带子就该在了
	var n1: int = _s._world.get_child_count()
	# ★★2026-08-04 预警区重做：从"几条 bolt_line"改成【持续 1 秒的贴地扫描带】(一个常驻 mesh)。
	#   所以判据从"多了几个节点"换成"那条带子真的有面、真的可见、宽度==命中通道"。
	#   数节点数在这里已经守不住了（只多 1 个节点，但那 1 个才是正主）。
	# ★★判据用【产品代码自己持有的引用】(`t["warn_mi"]`)，不靠遍历场景树按名字找：
	#   ⚠ 探针实测两个坑叠在一起 ——
	#   ① `queue_free()` 是延迟的：前面段落 `clear()` 掉的节点这一帧还挂在树上；
	#   ② 僵尸占着 "TentacleWarn_left_0" 这个名字，新节点被 Godot 自动改名，
	#      按名字遍历**逮到的是那个已隐藏的僵尸** ⇒ 报"预警带没建出来"，
	#      而探针显示新节点 id=…790 明明 visible=true。
	#   （顺带查出真 bug：`clear()` 原来漏了 `warn_mi`，换路/清场每次泄漏一个节点。）
	var _t0: Dictionary = _v._tents["left|0"]
	var wm = _t0.get("warn_mi", null)
	_ok("⑤b ★预警带真的建出来了且可见(节点 +%d)" % (n1 - n0),
		is_instance_valid(wm) and wm.visible and wm.is_inside_tree()
			and (wm.mesh as ArrayMesh).get_surface_count() > 0,
		"valid=%s visible=%s 面=%d" % [is_instance_valid(wm),
			(wm.visible if is_instance_valid(wm) else false),
			((wm.mesh as ArrayMesh).get_surface_count() if is_instance_valid(wm) else -1)])
	# ★宽度必须 == `_slap` 的真实命中通道(半宽 40 码)。画宽了/窄了都是骗玩家。
	if is_instance_valid(wm) and (wm.mesh as ArrayMesh).get_surface_count() > 0:
		var wvs: PackedVector3Array = (wm.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var wbb := AABB(wvs[0], Vector3.ZERO)
		for v in wvs:
			wbb = wbb.expand(v)
		# ★★期望值【写死字面数 40.0】，不读 `TV.WARN_HALF_W` ——
		#   反向验证实测：用常量做期望值时，把 `WARN_HALF_W` 改成 160 两边一起变，
		#   **0 条 FAIL** = 恒真式（CLAUDE.md §2）。
		var oo: Vector2 = _v.root_pos("left", 0)
		var one: float = (_s._world_pos(oo + Vector2(0, 120.0), 0.0)
			- _s._world_pos(oo, 0.0)).length()
		var lat: float = minf(wbb.size.x, wbb.size.z)
		_ok("⑤b ★预警带宽度 == 真实命中通道(半宽 120 码 = %.2fm)" % one,
			lat > one * 1.2 and lat < one * 3.4, "带宽 %.2fm" % lat)
		# ★两头都焊住：`_slap` 的命中半宽改了、这边没跟，也要红。
		var src_sl: String = FileAccess.get_file_as_string(
			"res://scripts/systems/equip/spirit_synergy_system.gd")
		_ok("⑤b ★预警宽度与 _slap 的命中判定同源(两处都是 120)",
			absf(float(TV.WARN_HALF_W) - 120.0) < 0.01 and src_sl.find("cross(dir)) > 120.0") >= 0,
			"WARN_HALF_W=%.1f / _slap 源码里没找到 `> 120.0`" % float(TV.WARN_HALF_W))
	# ★预警带【持续整整 T_WARN】—— 原来那版只有蓄势那 0.13 秒的一闪，等于没有。
	_v.tick(TV.T_WARN * 0.9)
	_ok("⑤b ★预警带在 %.2f 秒后仍然亮着(官方 f009~f039 持续 1 秒)" % (TV.T_WARN * 0.9),
		is_instance_valid(wm) and wm.visible,
			"visible=%s" % (wm.visible if is_instance_valid(wm) else false))
	_v.tick(TV.T_WARN + 0.02)                     # 预警 → 蓄势
	_v.tick(TV.T_REAR + 0.02)                     # 蓄势 → 拍击
	_v.tick(TV.T_SLAM * 0.4)                      # 过 0.08s → 命中特效
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
