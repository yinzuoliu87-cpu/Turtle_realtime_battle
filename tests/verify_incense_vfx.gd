extends Node
## verify_incense_vfx.gd — 093 香火石【演出层】门禁 (2026-08-09 逐件重做)
##
## 结算侧的门禁在 `tests/verify_incense_stone.gd`(充能/刻痕/加成/强化普攻)。
## **这一份只管"看不看得出来"**, 判据全部落在能被量出来的东西上:
##   · 一帧刻多道 ⇒ 演出只放一次(实拍抓到过一帧刻 5 道 ⇒ 5 份完全重叠)
##   · 香台的支数 = 真实剩余强化次数(不是自己数的, 是读 eq_state)
##   · 剪影不撞车(刻痕是横沟 / 香是竖杆 / 火印是八角)
##   · 淡出不许"一出生就掉"(holdfade)
##   · 尺寸在实战镜头下读得出, 又不至于糊住整只龟
##
## ⚠ 全部**同步断言**(CLAUDE.md §3.5): 调完入口下一行就判, 不等任何 tween、不数帧。
##   本层不用 tween —— 生命周期由 `tick(delta)` 自己推, 所以测试可以直接喂 delta。
##
## ★不许恒真: 期望值一律写死字面量, 不去读被测常量当期望;
##   每组带分母(N=0 是空检查不是通过)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_incense_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const IV := preload("res://scripts/scenes/battle/incense_vfx.gd")

## 屏幕标尺: 1280×720 下 1 码 ≈ 这么多屏幕像素(与 verify_vfx_readability 同口径)。
const PX_PER_YARD := 0.69
## 头顶等级徽章的屏幕高度(px)。低于它 = 实战中基本等于不存在。
const BADGE_PX := 16.0

var _n := 0
var _fail := 0
var _s = null
var _inc = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 093 香火石 演出层 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_inc = _s._incense_vfx
	_ok("★分母: 主场景真的持有 IncenseVfx", _inc != null and _inc is IncenseVfx)
	_ok("★分母: 世界节点在(没有它一个特效都建不出来)",
		_s._world != null and is_instance_valid(_s._world))

	await _t_batch()
	await _t_altar_follows_emp()
	await _t_silhouettes()
	await _t_holdfade()
	_t_size()
	await _t_clear()
	_t_wired()
	await _t_batch_via_system()
	_t_panel_readouts()
	_t_stick_spacing()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 093 香火石演出层" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mk_u(x: float, emp: int = 0) -> Dictionary:
	return {"pos": Vector2(x, 400.0), "alive": true, "height": 0.0,
		"eq_state": {"p2eq_093": {"emp": emp}}}


# ─────────────────────────────────────────────────────────────
# ① 一帧刻多道 ⇒ 只放一份演出
#    ★这是实拍抓出来的真 bug: 携带者一次斩击 2 万伤害 ⇒ 结算侧 while 转 5 圈,
#      演出被连调 5 次 ⇒ 同一点摞 5 道刻痕 + 5 条重合飘字。
# ─────────────────────────────────────────────────────────────
func _t_batch() -> void:
	print("── ① 一帧多道合成一次 ──")
	_inc.clear()
	await get_tree().process_frame
	var u: Dictionary = _mk_u(700.0)

	_inc.mark_carved(u, 1, 1)
	var n1: int = _inc.alive_count("tally")
	_ok("① 刻 1 道 ⇒ 1 道凿沟", n1 == 1, "实测 %d" % n1)

	_inc.clear()
	await get_tree().process_frame
	_inc.mark_carved(u, 5, 5)
	var n5: int = _inc.alive_count("tally")
	_ok("① ★一帧刻 5 道 ⇒ 5 道**各占各的位置**(不是 5 份重叠, 也不是只画 1 道)",
		n5 == 5, "实测 %d" % n5)

	# 各占各的位置 = 至少有 5 个互不相同的落点(重叠版这里会全等 ⇒ 只剩 1 个)
	var pts := {}
	for c in _s._world.get_children():
		if c is Node3D and (c as Node).has_meta(IV.META_KEY) \
				and str((c as Node).get_meta(IV.META_KEY)) == "tally":
			pts[Vector2i(int(round((c as Node3D).position.x * 400.0)),
						 int(round((c as Node3D).position.y * 400.0)))] = true
	_ok("① ★★5 道凿沟落在 5 个不同的点上(旧实现全摞在一个点 ⇒ 这里只会数到 1)",
		pts.size() == 5, "不同落点 %d" % pts.size())

	# 一次撑爆也不该无限摆: 上限钳到 5
	_inc.clear()
	await get_tree().process_frame
	_inc.mark_carved(u, 40, 40)
	var nbig: int = _inc.alive_count("tally")
	_ok("① 一帧刻 40 道也只摆 5 道(不炸节点数)", nbig == 5, "实测 %d" % nbig)
	_inc.clear()


# ─────────────────────────────────────────────────────────────
# ② 香台【读 emp】, 不自己数
#    ★"必须与物理事件同帧的演出不能有自己的秒表" —— 这里的可执行版本是:
#      我在测试里**只改 eq_state**、一次都不调演出入口, 台上的支数必须跟着变。
# ─────────────────────────────────────────────────────────────
func _t_altar_follows_emp() -> void:
	print("── ② 香台支数 = 剩余强化次数 ──")
	_inc.clear()
	await get_tree().process_frame
	var u: Dictionary = _mk_u(700.0, 4)
	_inc.empower_burst(u)
	_ok("② ★分母: 香台建出来了(1 座)", _inc.alive_count("altar") == 1,
		"实测 %d" % _inc.alive_count("altar"))
	_inc.tick(0.30)     # 入场 0.22 秒, 推过去
	_ok("② 就绪时点着 4 支", _inc.lit_sticks_of(u) == 4, "实测 %d" % _inc.lit_sticks_of(u))

	# ★只改结算侧的数, 不碰演出。支数必须跟着掉。
	u["eq_state"]["p2eq_093"]["emp"] = 2
	_inc.tick(0.25)
	_ok("② ★★只把 emp 改成 2(没调任何演出入口) ⇒ 台上只剩 2 支",
		_inc.lit_sticks_of(u) == 2, "实测 %d" % _inc.lit_sticks_of(u))

	u["eq_state"]["p2eq_093"]["emp"] = 0
	_inc.tick(0.25)
	_ok("② emp 归零 ⇒ 一支不剩", _inc.lit_sticks_of(u) == 0,
		"实测 %d" % _inc.lit_sticks_of(u))
	_inc.tick(0.40)     # 收尾 0.30 秒
	_ok("② ★用完之后香台自己退场(不留常驻节点)", _inc.alive_count("altar") == 0,
		"实测 %d 座" % _inc.alive_count("altar"))

	# 携带者倒下也要退场 —— 否则死人头上一直飘着一排香
	_inc.clear()
	await get_tree().process_frame
	var v: Dictionary = _mk_u(760.0, 4)
	_inc.empower_burst(v)
	_inc.tick(0.30)
	_ok("② ★分母: 第二座香台也建起来了", _inc.alive_count("altar") == 1)
	v["alive"] = false
	_inc.tick(0.45)
	_ok("② 携带者倒下 ⇒ 香台退场", _inc.alive_count("altar") == 0,
		"实测 %d 座" % _inc.alive_count("altar"))

	# 重复就绪不叠两座
	_inc.clear()
	await get_tree().process_frame
	var w: Dictionary = _mk_u(800.0, 4)
	_inc.empower_burst(w)
	_inc.empower_burst(w)
	_ok("② 同一只龟连着就绪两次: 只有 1 座香台(不叠)", _inc.alive_count("altar") == 1,
		"实测 %d 座" % _inc.alive_count("altar"))
	_inc.clear()


# ─────────────────────────────────────────────────────────────
# ③ 剪影不撞车 + 演出在头顶以上
# ─────────────────────────────────────────────────────────────
func _t_silhouettes() -> void:
	print("── ③ 剪影 ──")
	# 刻痕: 横沟。★上一版是竖直亮条, zoom 6 实拍读成了"四支没点着的香" —— 同件两个入口撞剪影。
	var ti: Image = IV.tally_tex().get_image()
	_ok("③ ★刻痕是【横】的 (%dx%d, 宽 > 高×2)" % [ti.get_width(), ti.get_height()],
		ti.get_width() > ti.get_height() * 2)
	# 两端要收尖: 中列的厚度必须明显大于靠边那一列(是"划痕"不是"一根等宽的棍")
	var mid_t: int = _col_thick(ti, ti.get_width() / 2)
	var edge_t: int = _col_thick(ti, int(float(ti.get_width()) * 0.08))
	_ok("③ 刻痕两端收尖(中段 %d px vs 近端 %d px, 至少差一倍)" % [mid_t, edge_t],
		mid_t >= 6 and edge_t * 2 <= mid_t)

	# 香: 竖的(贴图高 > 宽)
	## ★2026-08-09 这两张已从静图升级成 **9 帧横向精灵条** ⇒ 剪影必须量**单帧**,
	##   拿整条宽度量会把"竖的香"读成"横的条"(实测 288×64 ⇒ 这条当场红过)。
	var si: Image = IV.stick_tex().get_image()
	var siw: int = si.get_width() / IV.STICK_FRAMES
	_ok("③ 香是【竖】的 (单帧 %dx%d, 高 > 宽)" % [siw, si.get_height()],
		si.get_height() > siw)
	_ok("③ ★香是逐帧动画(9 帧, 火头跳 + 青烟飘) —— 不是一张死图",
		IV.STICK_FRAMES > 1 and si.get_width() == siw * IV.STICK_FRAMES,
		"帧数=%d 整条宽=%d" % [IV.STICK_FRAMES, si.get_width()])
	# 火印: 近似方(八角勋章), 与横沟/竖香都不同族
	var zi: Image = IV.seal_tex().get_image()
	var ziw: int = zi.get_width() / IV.SEAL_FRAMES
	_ok("③ ★火印是逐帧动画(9 帧, 火焰炸开) —— 不是一张死图",
		IV.SEAL_FRAMES > 1 and zi.get_width() == ziw * IV.SEAL_FRAMES,
		"帧数=%d 整条宽=%d" % [IV.SEAL_FRAMES, zi.get_width()])
	_ok("③ 火印近似方形 (单帧 %dx%d)" % [ziw, zi.get_height()],
		absf(float(ziw) - float(zi.get_height())) <= 4.0)

	# 素材必须真有内容(空图/全透明会让上面几条变成"量了个寂寞")
	_ok("③ ★分母: 香的素材非空 (不透明像素 %d)" % _opaque(si), _opaque(si) > 150)
	_ok("③ ★分母: 火印素材非空 (不透明像素 %d)" % _opaque(zi), _opaque(zi) > 600)

	# 位置: 三样都在头顶以上(脚下那一层被龟身/影子/飘字占满了)
	_inc.clear()
	await get_tree().process_frame
	var u: Dictionary = _mk_u(700.0, 4)
	var ground_y: float = _s._world_pos(u["pos"], 0.0).y
	_inc.empower_burst(u)
	_inc.mark_carved(u, 3, 3)
	var min_y := 1.0e9
	var cnt := 0
	for c in _s._world.get_children():
		if not (c is Node3D) or not (c as Node).has_meta(IV.META_KEY):
			continue
		var k: String = str((c as Node).get_meta(IV.META_KEY))
		if k != "altar" and k != "tally":
			continue
		cnt += 1
		min_y = minf(min_y, (c as Node3D).position.y)
	_ok("③ ★分母: 真的量到了节点 (%d 个)" % cnt, cnt >= 4)
	_ok("③ 香台与刻痕全在头顶以上 (最低 y=%.2f > 地面 %.2f + 1.0)" % [min_y, ground_y],
		min_y > ground_y + 1.0)
	_inc.clear()


# ─────────────────────────────────────────────────────────────
# ④ 淡出病: 短命特效不许一出生就掉
# ─────────────────────────────────────────────────────────────
func _t_holdfade() -> void:
	print("── ④ 不许一出生就淡出 ──")
	_inc.clear()
	await get_tree().process_frame
	var u: Dictionary = _mk_u(700.0)
	var tgt: Dictionary = {"pos": Vector2(760.0, 400.0), "alive": true, "height": 0.0}
	_inc.empower_hit(u, tgt)
	# 火印活 0.42 秒。推到四成寿命(0.17 秒)时必须还在满亮 —— 线性淡出这时已经掉到 0.6
	_inc.tick(0.17)
	var a40: float = _first_alpha("seal")
	_ok("④ ★火印到四成寿命仍是满亮 (alpha=%.2f ≥ 0.98)" % a40, a40 >= 0.98)
	_inc.tick(0.20)     # 累计 0.37 / 0.42 ≈ 88%%
	var a88: float = _first_alpha("seal")
	_ok("④ 到近九成寿命已经在落了 (alpha=%.2f < 0.7) —— 也不是【从不淡出】" % a88,
		a88 >= 0.0 and a88 < 0.7)

	_inc.clear()
	await get_tree().process_frame
	_inc.mark_carved(u, 1, 1)
	_inc.tick(0.25)     # 刻痕活 0.60 秒 ⇒ 四成出头
	var t42: float = _first_alpha("tally")
	_ok("④ ★刻痕到四成寿命仍是满亮 (alpha=%.2f ≥ 0.98)" % t42, t42 >= 0.98)
	_inc.clear()
	await get_tree().process_frame


# ─────────────────────────────────────────────────────────────
# ⑤ 尺寸: 实战镜头(1280×720)下读得出, 又不糊住整只龟
#    ★龟立绘实测约 44×47 码。旧版单支香 76 码高 = 比龟还高 1.6 倍。
# ─────────────────────────────────────────────────────────────
func _t_size() -> void:
	print("── ⑤ 尺寸 ──")
	var stick_h_yd: float = IV.STICK_W_PX * IV.STICK_TEX_ASPECT
	var stick_h_px: float = stick_h_yd * PX_PER_YARD
	_ok("⑤ 单支香 %.0f 码 / %.0f 屏幕 px: ≥ 徽章 16px 且 ≤ 龟身高(47 码)"
		% [stick_h_yd, stick_h_px],
		stick_h_px >= BADGE_PX and stick_h_yd <= 47.0)
	var seal_px: float = IV.SEAL_D * PX_PER_YARD
	_ok("⑤ 火印 %.0f 码 / %.0f 屏幕 px: ≥ 徽章 16px 且 ≤ 龟身宽的 1.5 倍(66 码)"
		% [IV.SEAL_D, seal_px], seal_px >= BADGE_PX and IV.SEAL_D <= 66.0)
	_ok("⑤ 火印是【盖章】: 起手比落定大(倍率 %.2f > 1.2)" % IV.SEAL_K0, IV.SEAL_K0 > 1.2)
	# 刻痕落点必须高过香台顶, 否则两个入口挤在一起(zoom 6 实拍抓到过)
	var altar_top: float = IV.HEAD_Y + IV.STICK_RISE_M \
		+ IV.STICK_W_PX * IV.STICK_TEX_ASPECT * 0.5 * 0.024
	_ok("⑤ ★刻痕落点 %.2f m 高过香台顶 %.2f m(两个入口不挤在一块)"
		% [IV.TALLY_Y, altar_top], IV.TALLY_Y > altar_top)


# ─────────────────────────────────────────────────────────────
# ⑥ 撤场: 一次性的与常驻的都要拔干净
# ─────────────────────────────────────────────────────────────
func _t_clear() -> void:
	print("── ⑥ 撤场 ──")
	_inc.clear()
	await get_tree().process_frame
	var u: Dictionary = _mk_u(700.0, 4)
	var tgt: Dictionary = {"pos": Vector2(760.0, 400.0), "alive": true, "height": 0.0}
	_inc.empower_burst(u)
	_inc.mark_carved(u, 3, 3)
	_inc.empower_hit(u, tgt)
	var before: int = _inc.alive_count()
	_ok("⑥ ★分母: 撤之前场上真的有东西 (%d 个)" % before, before >= 8)
	var pulled: int = _inc.clear()
	_ok("⑥ clear() 报告拔了 %d 个" % pulled, pulled == before)
	_ok("⑥ 撤干净(剩 %d)" % _inc.alive_count(), _inc.alive_count() == 0)
	_ok("⑥ 常驻香台也撤了(剩 %d 座)" % _inc.alive_count("altar"),
		_inc.alive_count("altar") == 0)


# ─────────────────────────────────────────────────────────────
# ⑦ 接线: 演出真的被人调(源码级) —— 没人调就永远不动而且不报错
# ─────────────────────────────────────────────────────────────
func _t_wired() -> void:
	print("── ⑦ 接线 ──")
	var main: String = _read("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var sys: String = _read("res://scripts/systems/equip/incense_stone_system.gd")
	_ok("⑦ ★分母: 两份源码都读得到 (%d / %d 字符)" % [main.length(), sys.length()],
		main.length() > 10000 and sys.length() > 3000)
	_ok("⑦ 主循环每帧推演出 (_incense_vfx.tick()", main.contains("_incense_vfx.tick("))
	_ok("⑦ 结算侧调 empower_burst", sys.contains("_incense_vfx.empower_burst("))
	_ok("⑦ 结算侧调 empower_hit", sys.contains("_incense_vfx.empower_hit("))
	_ok("⑦ ★结算侧把【这一帧刻了几道】传给演出(mark_carved 的第 3 个实参)",
		sys.contains("mark_carved(u, int(_marks.get(side, 0)), gained)"))
	_ok("⑦ ★换路撤场也撤演出(clear_all 里调 _incense_vfx.clear())",
		_fn_body(sys, "func clear_all()").contains("_incense_vfx.clear()"))
	# 一帧只结算一次: while 里不许再直接调演出/结算
	var tb: String = _fn_body(sys, "func tick_unit(")
	_ok("⑦ ★★tick_unit 的 while 里不再逐道调 _on_mark_scored(只累加 gained)",
		tb.contains("gained += 1") and not tb.contains("_on_mark_scored(u, side)"),
		"tick_unit 体 %d 字符" % tb.length())


# ─────────────────────────────────────────────────────────────
# ⑧ ★★走【真入口】: 结算侧一帧刻 5 道 ⇒ 演出只放一次
#
#   ⚠ 这一节是【反向验证补出来的】。第一版门禁的 ① 只调演出层 `mark_carved(u, 5, 5)`,
#     于是我把结算侧改坏成"逐道调 _on_mark_scored(u, side, 1) 五次"时, **门禁纹丝不动** ——
#     因为那条路根本没被测到(memory: 断言函数存在守不住还有没有人按对的方式调它)。
#   ⇒ 这里从 `tick_unit` 灌真伤害进去, 只数**屏幕上落点的个数**:
#     · 批量对 ⇒ 一次 gained=5 ⇒ 5 道分别落在 5 个不同的点
#     · 退回逐道 ⇒ 五次 gained=1 ⇒ 每次都摆在第 0 道的位置 ⇒ **5 道全摞成 1 个点**
# ─────────────────────────────────────────────────────────────
func _t_batch_via_system() -> void:
	print("── ⑧ 走真入口(tick_unit): 一帧 5 道只放一次演出 ──")
	_inc.clear()
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.incense_marks = 0
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("fortune", "left", c)
	u["equips"] = [{"id": "p2eq_093", "star": 1, "chg": 0}]
	u["eq_state"] = {}
	u["buffs"] = []
	_s._units.append(u)
	_s._equip_sys._incense.on_spawn(u, "p2eq_093", 0)
	# 5 道的量: 每道 4000 点伤害(规格原文, 写死字面量不读被测常量)
	u["_st_dealt"] = 4000 * 5
	_s._equip_sys._incense.tick_unit(u, 0.016)
	var marks: int = _s._equip_sys._incense.marks_of("left")
	_ok("⑧ ★分母: 结算侧真的一帧刻了 5 道 (marks=%d)" % marks, marks == 5)
	var n: int = _inc.alive_count("tally")
	_ok("⑧ 屏幕上 5 道凿沟", n == 5, "实测 %d" % n)
	var pts := {}
	for ch in _s._world.get_children():
		if ch is Node3D and (ch as Node).has_meta(IV.META_KEY) \
				and str((ch as Node).get_meta(IV.META_KEY)) == "tally":
			pts[Vector2i(int(round((ch as Node3D).position.x * 400.0)),
						 int(round((ch as Node3D).position.y * 400.0)))] = true
	_ok("⑧ ★★5 道落在 5 个不同的点(逐道调的旧写法在这里只会数到 1)",
		pts.size() == 5, "不同落点 %d" % pts.size())
	_s._units.clear()
	_inc.clear()
	await get_tree().process_frame


# ── 工具 ──────────────────────────────────────────────────────
func _first_alpha(kind: String) -> float:
	for c in _s._world.get_children():
		if c is Sprite3D and (c as Node).has_meta(IV.META_KEY) \
				and str((c as Node).get_meta(IV.META_KEY)) == kind:
			return float((c as Sprite3D).modulate.a)
	return -1.0


## 某一列上不透明像素的个数(px)。
func _col_thick(img: Image, x: int) -> int:
	var n := 0
	for y in range(img.get_height()):
		if img.get_pixel(x, y).a > 0.08:
			n += 1
	return n


func _opaque(img: Image) -> int:
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.08:
				n += 1
	return n


## ⑨ 两个读数必须**有 UI 出口**(装备图标框), 不许只写进 eq_state 没人读。
## ★2026-08-09 主会话补: 093 攒的是"每 4000 伤害刻一道痕 / 最多 300 道",
##   这两个数在局内**曾经完全看不到**(装备格全空) —— 玩家不知道自己攒到哪。
##   用户 2026-08-08 定的规矩: 充能条与层数一律进装备图标框, 不许自造头顶条。
## ⚠ 这条守的是**接线本身**: 只写 `stt["marks"]` 而没人读, 等于没做。
func _t_panel_readouts() -> void:
	var pc: Dictionary = _s.PANEL_COUNT
	var pg: Dictionary = _s.PANEL_CHARGE
	_ok("⑨ 分母: 两张读数表都拿到了", pc.size() > 0 and pg.size() > 0,
		"COUNT=%d CHARGE=%d" % [pc.size(), pg.size()])
	_ok("⑨ ★刻痕数进了装备格层数徽章(PANEL_COUNT)",
		str(pc.get("p2eq_093", "")) == "marks", "字段=%s" % str(pc.get("p2eq_093", "<无>")))
	var cg: Array = pg.get("p2eq_093", [])
	_ok("⑨ ★充能条进了装备格(PANEL_CHARGE)", cg.size() >= 2, "%s" % str(cg))
	_ok("⑨ 充能条读的是 chg, 满值 = PER_MARK(4000) 且与系统常量焊死",
		cg.size() >= 2 and str(cg[0]) == "chg"
			and absf(float(cg[1]) - float(IncenseStoneSystem.PER_MARK)) < 1e-6,
		"%s / 满值 %s vs PER_MARK %.0f" % [str(cg[0]) if cg.size() > 0 else "?",
			str(cg[1]) if cg.size() > 1 else "?", float(IncenseStoneSystem.PER_MARK)])


## ⑩ 相邻两支香的间距必须 **> 单支宽度**。
## ★2026-08-09 用户:「飘起来的烟有在对应香台吗」—— 当时没有。根因是纯几何:
##   单帧 32x64 ⇒ 世界宽 STICK_W_PX、高 = 宽 x STICK_TEX_ASPECT。旧值 宽 20 / 间距 12
##   ⇒ **相邻两支的精灵互相重叠 8 码**, 各自的烟糊成一条横带, 读成"飘在上面的宽带"
##   而不是"每支香各自冒烟"。这条不等式一破, 烟就又连片。
func _t_stick_spacing() -> void:
	_ok("⑩ ★相邻两支香的间距 > 单支宽度(否则各自的烟会糊成一条横带)",
		IV.STICK_GAP_PX > IV.STICK_W_PX,
		"间距 %.1f vs 宽度 %.1f 码" % [IV.STICK_GAP_PX, IV.STICK_W_PX])
	## 香的世界高 = 宽 x 贴图长宽比; 贴图里**上半截是烟**, 所以香身本体比这个数矮。
	## 仍要有个上限: 整只龟立绘约 44 码, 香连烟不该超过它太多。
	var stick_h: float = IV.STICK_W_PX * IV.STICK_TEX_ASPECT
	_ok("⑩ 香(连烟)的高度 ≤ 龟立绘的 1.3 倍", stick_h <= 44.0 * 1.3,
		"%.1f 码 vs 上限 %.1f" % [stick_h, 44.0 * 1.3])
	_ok("⑩ 分母: 贴图长宽比与实际素材一致",
		absf(float(IV.stick_tex().get_width()) / float(IV.STICK_FRAMES)
			* IV.STICK_TEX_ASPECT - float(IV.stick_tex().get_height())) < 0.01,
		"单帧 %dx%d, ASPECT=%.2f" % [IV.stick_tex().get_width() / IV.STICK_FRAMES,
			IV.stick_tex().get_height(), IV.STICK_TEX_ASPECT])


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


## 取某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)
