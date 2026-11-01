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
##   ⑤ ★固定网格(整局一份、不重建) + 攻击长度固定 + 拍下那一下弧长不变（2026-10-31 重做后改量着色器拿到的控制点）
##   ⑥ ★接线：spirit 系统每帧 ensure、拍击走 strike、换路 clear
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_tentacle_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const TV := preload("res://scripts/systems/equip/tentacle_vfx.gd")
const G := preload("res://tests/_tentacle_geo.gd")

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

	# ══ ⑤ 固定网格 + 攻击长度固定 ═══════════════════════════════
	# ★★2026-10-31 灵物触手重做(方案书 docs/plans/20261031d-灵物触手重做.md): 外观换成「一份开局建好的固定网格 +
	#   顶点着色器沿 24 个控制点弯曲」。原来这一组量的是每帧重建的扁带网格(SEG × (RING-1) 段的顶点、包围盒),
	#   那套几何整个没了 ⇒ 改量**着色器拿到的控制点**(材质 uniform = GPU 弯曲用的那一份, 见 tests/_tentacle_geo.gd)。
	#   姿态一律走真路径(strike → tick 推状态机), 不再手改 state / ts。
	_v.clear()
	_v.ensure("left", 1)
	## ★逐步推(1/60 秒一步)到待机再站 1 秒: 一次 tick(2.1) 会让出土动画一帧都没画, 待机从「出土第 0 帧」(露出 0)起混
	G.until_state(_v, "left", 0, 1)
	G.step(_v, 60)
	var mi5: MeshInstance3D = G.node_of(_v, "left", 0)
	_ok("⑤ ★分母: 触手节点在、材质是着色器材质", mi5 != null and G.mat_of(mi5) != null)
	if mi5 != null and G.mat_of(mi5) != null:
		var r3: Vector3 = mi5.position
		var p_idle: PackedVector3Array = G.world_pts(mi5)
		var m_idle = mi5.mesh
		_v.strike("left", 0, _v.root_pos("left", 0) + Vector2(400.0, 0.0), 1.0)
		G.until_state(_v, "left", 0, 2)           # 前摇
		var m_rear = mi5.mesh
		G.until_state(_v, "left", 0, 3)           # 拍击
		## 悬停末(砸下前最后一帧) 与 贴地后 0.05 秒
		var hang_n: int = int(floor((TV.T_TOUCH - TV.SNAP_T) / G.SIM_DT))
		G.step(_v, maxi(0, hang_n - 1))
		var p_hang: PackedVector3Array = G.world_pts(mi5)
		G.step(_v, int(ceil(TV.SNAP_T / G.SIM_DT)) + 3)
		var p_slam: PackedVector3Array = G.world_pts(mi5)
		var m_slam = mi5.mesh
		var a_idle: float = G.arc(p_idle)
		var a_hang: float = G.arc(p_hang)
		var a_slam: float = G.arc(p_slam)
		var tip_idle: float = (p_idle[p_idle.size() - 1] - r3).length() if not p_idle.is_empty() else 0.0
		var tip_slam: float = (p_slam[p_slam.size() - 1] - r3).length() if not p_slam.is_empty() else 0.0
		print("     控制点 %d 个 · 弧长 待机 %.2f / 悬停末 %.2f / 贴地 %.2f 米(攻击长度 %.1f) · 端点距根 待机 %.2f → 贴地 %.2f" % [
			p_idle.size(), a_idle, a_hang, a_slam, TV.ATTACK_LEN, tip_idle, tip_slam])
		_ok("⑤ ★三个姿态的控制点个数相同且够画一根(≥ 8; 着色器 ctrl_pts[N])",
			p_idle.size() >= 8 and p_hang.size() == p_idle.size() and p_slam.size() == p_idle.size(), "%d/%d/%d" % [p_idle.size(), p_hang.size(), p_slam.size()])
		var tri_n: int = (m_idle as ArrayMesh).surface_get_array_index_len(0) / 3 if m_idle is ArrayMesh else 0
		_ok("⑤ ★固定网格: 待机 / 前摇 / 拍击是【同一份】网格对象(= 全部触手共用的那份, %d 个三角形), 不随姿态重建" % tri_n,
			m_idle != null and is_same(m_idle, m_rear) and is_same(m_rear, m_slam) and is_same(m_idle, TentacleMeshVfx.shared_mesh()) and tri_n > 1000)
		## 攻击长度固定(用户 08-04: 有固定范围才有安全距离)—— 上限沿用旧门禁: ATTACK_LEN × 1.1, 再留 6% 量法余量
		##   (10-31 用户否了第一版, 第一路以旧版中心线为起点恢复 ⇒ 尺子回到旧版验收过的那一把)
		_ok("⑤ ★攻击长度是【固定】的 ≤ %.2f 米(贴地时弧长 %.2f)" % [TV.ATTACK_LEN * 1.1 * 1.06, a_slam], a_slam > 1.0 and a_slam <= TV.ATTACK_LEN * 1.1 * 1.06)
		## 拍下去弧长基本不变(用户 08-05「戳出去」= 拍击中途变长)—— 容差沿用旧门禁「弧长恒定」的 12%
		_ok("⑤ ★拍下那一下弧长不变(悬停末 %.2f → 贴地 %.2f, 差 ≤ 12%%) —— 不许「戳出去」" % [a_hang, a_slam],
			absf(a_slam - a_hang) <= a_hang * 0.12 and a_hang > 1.0)
		## 2026-11-01 用户「初始状态下…太弯了，得把它搞直一点」⇒ 待机拉直, 端点距根本来就远了(实测 6.60 米), 倍数 1.6 → 1.25
		_ok("⑤ ★端点距离甩直了显著变远(待机 %.2f → 贴地 %.2f 米, ≥ 1.25 倍)" % [tip_idle, tip_slam],
			tip_slam > tip_idle * 1.25 and tip_slam > 2.0)

	# ★★攻击长度【不随目标距离变】—— 用户 2026-08-04 点名纠正的（我中途做过一版
	#   "按到目标的实际距离伸长"，那样就没有"安全距离"这条规则了）。
	var lens_by_dist: Array = []
	## ★两次从同一个战斗时钟起跑: 待机摆动与链式模拟有历史, 时钟不同 ⇒ 出手时的样子不同(那不是「长度随目标变」)
	var t_run: float = float(_s._t)
	for far in [400.0, 1400.0]:
		_s._t = t_run
		_v.clear(); _v.ensure("left", 1); _v.tick(2.1)
		var mif: MeshInstance3D = G.node_of(_v, "left", 0)
		_v.strike("left", 0, _v.root_pos("left", 0) + Vector2(far, 0.0), 1.0)
		G.until_state(_v, "left", 0, 3)
		G.step(_v, int(ceil(TV.T_TOUCH / G.SIM_DT)) + 3)
		var pf: PackedVector3Array = G.world_pts(mif) if mif != null else PackedVector3Array()
		lens_by_dist.append((pf[pf.size() - 1] - mif.position).length() if pf.size() > 0 else -1.0)
	_ok("★攻击长度固定: 目标 400 码 vs 1400 码，触手伸出去一样远(%.2f vs %.2f 米)"
		% [float(lens_by_dist[0]), float(lens_by_dist[1])],
		float(lens_by_dist[0]) > 1.0 and absf(float(lens_by_dist[0]) - float(lens_by_dist[1])) < 0.05, str(lens_by_dist))

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
		# ★★ 2026-08-10 从【grep 源码找字面量】改成【比两个常量】：
		#   原来找的是 `cross(dir)) > 120.0` 这串源码文本 —— 半宽一提成常量就拓空了，
		#   而行为完全没变。这正是 CLAUDE.md §2 记的那类「审计器读源码找数值，
		#   函数一搬家就误报」。现在直接比两边的常量，重构不会误报、改值照样会红。
		#   ⚠ 期望值仍然**写死 120.0**（不是拿一个常量比另一个）——
		#     两边一起改成 160 时必须也能拓到，否则又是恒真式。
		var SSS := preload("res://scripts/systems/equip/spirit_synergy_system.gd")
		_ok("⑤b ★预警宽度与 _slap 的命中判定同源(两处都是 120)",
			absf(float(TV.WARN_HALF_W) - 120.0) < 0.01
				and absf(float(SSS.HIT_HALF_W) - 120.0) < 0.01
				and absf(float(TV.WARN_HALF_W) - float(SSS.HIT_HALF_W)) < 0.01,
			"WARN_HALF_W=%.1f / HIT_HALF_W=%.1f" % [float(TV.WARN_HALF_W), float(SSS.HIT_HALF_W)])
	# ★预警带【持续整整 T_WARN】—— 原来那版只有蓄势那 0.13 秒的一闪，等于没有。
	_v.tick(TV.T_WARN * 0.9)
	_ok("⑤b ★预警带在 %.2f 秒后仍然亮着(官方 f009~f039 持续 1 秒)" % (TV.T_WARN * 0.9),
		is_instance_valid(wm) and wm.visible,
			"visible=%s" % (wm.visible if is_instance_valid(wm) else false))
	_v.tick(TV.T_WARN + 0.02)                     # 预警 → 蓄势
	_v.tick(TV.T_REAR + 0.02)                     # 蓄势 → 拍击
	## ★★2026-08-21 用户拍板「肯定是落地伤害」⇒ 爆闪/伤害都挪到了 `T_TOUCH`(梢端真落地),
	##   不再是 ST_SLAM 第 0 帧(那一刻梢端还在 y=9.18 半空 = 人没到、地先炸)。
	##   ⚠ 这里原来写死 `T_SLAM * 0.4`(=0.20s) 并注"过 0.08s" —— 两个数都过时了,
	##     改成**从 T_TOUCH 推导**, 以后动画再改也不会因为写死而误判。
	## ★先证明【半空的时候不许炸】—— 只断言"炸过"守不住"炸得对时候"。
	_v.tick(TV.T_TOUCH * 0.5)
	var n_mid: int = _s._world.get_child_count()
	_ok("⑤b ★梢端还在半空时【不许】出命中特效(用户: 落地才算命中)", n_mid - n1 <= 0,
		"提前多了 %d 个节点" % (n_mid - n1))
	_v.tick(TV.T_TOUCH * 0.5 + 0.03)              # 越过 T_TOUCH → 落地 → 命中特效
	var n2: int = _s._world.get_child_count()
	## ★★2026-10-31 重做: 命中演出至少有贴地爆闪 + 粒子(≥ 3 个节点); 着色器里的本体白闪 / 拍痕(有的话)只打印 ——
	##   第一版删了「直线命中范围」bolt_line 与几圈环(方案书 §5 U7), 第一路恢复旧版时可能再改, 节点数只守下限。
	var mi_b: MeshInstance3D = G.node_of(_v, "left", 0)
	print("     命中那一刻: 新节点 %d 个 · 本体白闪 %s · 拍痕 %s" % [n2 - n1, str(G.uni(mi_b, "flash")) if mi_b != null else "-",
		str(G.uni(mi_b, "trail")) if mi_b != null else "-"])
	_ok("⑤b ★命中特效真的建出节点(贴地爆闪 + 粒子 …, +%d ≥ 3)" % (n2 - n1), n2 - n1 >= 3)

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
