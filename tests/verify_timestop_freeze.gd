extends Node
## verify_timestop_freeze.gd — 059 沙漏【时停期间到底冻没冻】
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：用户 2026-09-14「这个装备我看有很多有问题的地方，**很多特效没有冻结**」
## ══════════════════════════════════════════════════════════════════
## 他是对的，而且能量出来。
##
## **尺子来自参考**（JoJo「ザ・ワールド」15 秒 149 帧，逐帧研究见
## `docs/studies/20260914e-059时停参考逐帧.md`）：定格段的帧间运动量实测 **0.00 ~ 0.81**，
## 而动态段 **1.25 ~ 90.47** —— 定格就是**真的一帧都不动**，不是"大致静止"。
##
## 产品侧的等价物：时停期间 `battle._world` 下**没有任何 Node3D 的 transform / 帧号 / 颜色会变**
## （场上只有携带者能动，而本门禁把携带者配成不出手）。
##
## **探针实测（修之前）**：时停期间 `_world` 里 **56 个节点照常在动**，
## 位移量和时停前一模一样（背景鱼群 Δpos 1.4112 → 1.4188、气泡 1.1063 → 1.1122）。
## 根因不是"漏了某一处"，是**战斗世界侧有 23 处直接用 `create_tween()`**，
## 绕开了 `_reg_tween()` ⇒ 它们从来没进过 `battle._sim_tweens` ⇒ `_ts_begin_freeze()` 找不到它们。
## 主场景 48 行的注释早就写着「依赖 `_reg_tween` 的时停契约(**漏注册=时停静默失效**)」——
## 契约在，但没有任何东西守着它。这个文件就是那个守卫。
##
## ══════════════════════════════════════════════════════════════════
##  ★判据形状（三条，各自配分母）
## ══════════════════════════════════════════════════════════════════
## ① **背景远景**（鱼群/气泡，`FarBackdrop` 子树）时停期间 **0 个节点变化**。
##    分母：时停**之前**同样采样必须有一大把在动 —— 否则是空检查。
## ② **非携带者单位的立绘**时停期间位置/帧号/颜色一个都不变。
##    分母：它在时停前是会动的。
## ③ **解除后必须恢复**：`_end_timestop()` 之后背景重新动起来。
##    ——冻死了也是 bug，只验"冻得住"会放过"再也不动了"。
##
## ★★判据⑥/⑦ 的由来(用户 2026-09-14):「确定所有东西都定住了吗, **像触手, 直升机等等**」
##   —— 他说中了, 而且比①②看到的严重。主场景里那一整块 `if _fight_on:` 的每帧 tick
##   (羁绊周期效果 / `_tentacle_vfx.tick` 触手网格 / `_equip_sys.tick_global` 碑与直升机 /
##   `_spec.tick` 所有人的护盾余额)跑在 `elif in_ts:` 分支【之前】⇒ 时停整块门不住它。
##   探针实测: 非携带者的一笔 1000 余额, **时停前 60 帧掉 10.42、时停中 120 帧掉 20.42**
##   —— 速率一模一样。这是**玩法**不是画面: 20 秒的定格里全场的盾在掉、羁绊计时在走。
##   ★①②③ 全绿也抓不到它: 那三条量的是 `_world` 里**两次快照都在**的节点的 transform,
##     而余额是单位字典里的数、新建/销毁的节点更是压根不在快照的交集里。
##     ⇒ 补两条**量账不量画面**的判据。
##
## ★为什么不判"变化节点数 == 0"：时停**自己的**演出（蓄力沙漏虚影 / 时之主金辉光 / 停摆钟）
##   和**携带者自己**本来就该继续动（它是唯一能动的人）。判据必须刚好卡住"别人不许动"
##   这个形状，宽一格会造假 bug、窄一格会放过真 bug
##   （memory [[fb-judge-must-fit-the-shape]]）。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


## 采样 `_world` 子树里每个 Node3D 的「会动的三个量」: 世界坐标 / 帧号 / 颜色。
func _snap(n: Node, out: Dictionary, path: String) -> void:
	for c in n.get_children():
		var p: String = path + "/" + c.name
		if c is Node3D:
			var rec: Array = [c.global_position, Color(0, 0, 0, 0), 0]
			if c is SpriteBase3D:
				rec[1] = c.modulate
				rec[2] = c.frame
			out[p] = rec
		_snap(c, out, p)


## 返回 (路径前缀含 `pfx` 的) 变化节点数。`pfx` 为空 = 全部。
func _moved(a: Dictionary, b: Dictionary, pfx: String) -> Array:
	var hit: Array = []
	for k in a.keys():
		if not b.has(k) or (pfx != "" and not str(k).begins_with(pfx)):
			continue
		var x: Array = a[k]
		var y: Array = b[k]
		var dp: float = (x[0] as Vector3).distance_to(y[0] as Vector3)
		var c0: Color = x[1]
		var c1: Color = y[1]
		var dc: float = absf(c0.a - c1.a) + absf(c0.r - c1.r) + absf(c0.g - c1.g) + absf(c0.b - c1.b)
		if dp > 0.0005 or dc > 0.002 or int(x[2]) != int(y[2]):
			hit.append(k)
	return hit


## `_world` 子树里**离携带者 far 米以外**的节点数 —— 判据⑦ 用。
## ★快照差(`_moved`)只比两次都在的节点, **新建/销毁的它看不见** ⇒ 必须另外数一次总数。
## ★★为什么要排除携带者周围: 时之主是**唯一能动的人**, 它施法/普攻**本来就该**造出新节点
##   (第一版判据把这些也数进去, 红在 +3 上 —— 那不是缺陷, 是判据比要量的形状宽了一格)。
##   判据要刚好卡住「**别人**的世界不许再生灭」这个形状(memory [[fb-judge-must-fit-the-shape]])。
func _count_far(n: Node, cp: Vector3, far: float) -> int:
	var c := 0
	for ch in n.get_children():
		if not (ch is Node3D) or (ch as Node3D).global_position.distance_to(cp) > far:
			c += 1
		c += _count_far(ch, cp, far)
	return c


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


## 跑 nf 帧, 返回这段时间里 `_world` 下变化的节点(按前缀过滤)。
func _window(nf: int, pfx: String) -> Array:
	var a: Dictionary = {}
	_snap(_s._world, a, "")
	await _wait(nf)
	var b: Dictionary = {}
	_snap(_s._world, b, "")
	return _moved(a, b, pfx)


func _mk(id: String, side: String, dx: float, star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + Vector2(dx, 0))
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	if star > 0:
		u["equips"] = [{"id": "p2eq_059", "star": star}]
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 059 沙漏: 时停期间世界到底冻没冻 ===")
	print("   尺子: 参考里定格段帧间运动 0.00~0.81 / 动态段 1.25~90.47 ⇒ 定格 = 一帧都不动")
	_s = RB.new()
	add_child(_s)
	await _wait(40)

	_s._units.clear()
	## ★沙漏到手动触发那一刻才装上 —— 负载下时停前窗口会越过天然触发点 10 秒(同 global_freeze 头注)。
	var carrier: Dictionary = _mk("fortune", "left", -200.0, 0)
	var other: Dictionary = _mk("stone", "right", 260.0, 0)       # 不带沙漏的那个: 它必须被冻住
	await _wait(30)
	var other_path: String = "/" + str(other["sprite"].name) if other.get("sprite", null) != null else ""

	## ★★把用户点名的那两样**真的摆到场上**: 触手(灵物羁绊) + 直升机(080)。
	##   不摆就只能拿余额当代理量 —— 那是「量我顺手能量的, 不是量需求点名的」。
	## ★★触手要**活得住**: `_spirit_syn.tick` 每帧按灵物羁绊档位 `ensure(side, n)` ——
	##   档位 0 就当场把它收回去。第一版只 `ensure_forced` 一次, 采样时触手早没了,
	##   判据⑧ 读到前后都是「不存在」⇒ 两边相等就"通过" = **恒真式**。
	##   是分母⑥ 抓到的(它验的是"时停前那个钟会走")。
	##   注入档位用台子那套既有做法(`synergy_system` 头注: VFXLAB 靠手写 `_by_side` 注入)。
	(_s._synergy._by_side as Dictionary)["right"] = {"灵物": 1}
	_s._tentacle_vfx.ensure_forced("right", 2)
	var gun = _s._equip_sys._gun_sys
	gun._spawn_heli(other, 2, 300.0)
	await _wait(10)

	## 给【非携带者】种一笔会线性衰减的余额(幽灵护盾/奶油护盾就是这么存的) —— 判据⑥ 的被测对象。
	_s._spec.grant(other, "probe_decay", 1000.0, {"decay_sec": 40.0})
	var sv0: float = float(_s._spec.val(other, "probe_decay"))

	var tk: String = "right|0"
	var tents: Dictionary = _s._tentacle_vfx._tents
	var helis: Array = gun._helis
	_ok("★分母⑤: 触手(%d 根)与直升机(%d 架)真的在场上" % [tents.size(), helis.size()],
		tents.has(tk) and helis.size() >= 1,
		"被测对象不在场 ⇒ 判据⑧⑨ 恒真, 什么都没验到")
	var tts0: float = float((tents.get(tk, {}) as Dictionary).get("ts", -1.0))
	var hp0: Vector2 = (helis[0] as Dictionary).get("pos", Vector2.ZERO) if helis.size() > 0 else Vector2.ZERO

	# ── ① 分母: 时停【之前】世界在动 ──
	var pre: Array = await _window(90, "")
	var pre_bg: Array = pre.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("★分母①: 时停【之前】_world 里 %d 个节点在动(其中背景远景 %d 个)" % [pre.size(), pre_bg.size()],
		pre_bg.size() >= 20,
		"背景远景一个都不动 ⇒ 下面「冻住了」是空检查, 不是产品的功劳")
	## ★分母②必须验「它在时停【之前】是会动的」, 光验"节点在场"守不住 ——
	##   那只龟配了 no_move/no_basic, 若它本来就一动不动, 判据② 就是恒真式。
	var pre_other: Array = pre.filter(func(k): return str(k) == other_path)
	_ok("★分母②: 非携带者那只的立绘(%s)在时停【之前】是会动的" % other_path,
		other_path != "" and not pre_other.is_empty(),
		"它本来就不动 ⇒ 判据②「时停期间它不动」是恒真式, 什么都没验到")

	# ── ② 真入口触发时停 ──
	var ts = _s._timestop
	_ok("★分母⑧: 手动触发之前时停【没有】自己放过(_ts_fired=%s)" % str(ts._ts_fired),
		not bool(ts._ts_fired), "天然触发先放了 ⇒ 时停前的分母全是在时停里量的")
	carrier["equips"] = [{"id": "p2eq_059", "star": 3}]   # 3★ ⇒ 定格 20 秒, 到这一刻才装上
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	## ── ⑫ 蓄力段: 人物身上冒金火气 → 最后 0.17 秒胸口亮光点 → 释放时火收掉、光点爆开 ──
	## 用户 2026-09-14「**直接是人物冒战斗特效** … 从人物中间爆开, 中间是什么颜色特效」;
	## 参考 clip.mp4 10.00~10.80 秒金火包身、10.83~10.97 秒胸口白金光点(逐帧见 20260914g 第五版一节)。
	## ★判据量产品自己建出来的节点(贴图路径 + 在不在树里), 贴图没 import 时 texture 为 null ⇒ 当场红。
	var auras0: Array = (ts._ts_aura_sprs as Array).duplicate()
	var a_tex: String = ""
	if auras0.size() > 0 and is_instance_valid(auras0[0]) and (auras0[0] as Sprite3D).texture != null:
		a_tex = str((auras0[0] as Sprite3D).texture.resource_path)
	_ok("⑫a 蓄力一开始携带者身上就冒金火气(%d 个 · 贴图 %s)" % [auras0.size(), a_tex.get_file()],
		auras0.size() == 1 and a_tex.ends_with("ts-aura.png") and (auras0[0] as Node).is_inside_tree(),
		"没冒 / 贴图没 import ⇒ 第一步「人物冒战斗特效」看不到")
	## ⑫d 火画在龟【身后】: 实心火必须先于携带者立绘画, 龟挡在火前面(参考 DIO 身体挡在火前)。
	##   ★由来: 第五版前两稿把身体挖空, 实拍(录屏 #308~#337)是「龟左右各立一根金柱子」。
	##   ★分母: 立绘材质必须真的走透明管线 —— 若是不透明管线, 渲染优先级根本不参与排序, 判据就是恒真式。
	var c_spr = carrier.get("sprite", null)
	var c_mat: ShaderMaterial = (c_spr as Sprite3D).material_override as ShaderMaterial if c_spr is Sprite3D else null
	var c_code: String = str(c_mat.shader.code) if c_mat != null and c_mat.shader != null else ""
	_ok("★分母⑫d: 携带者立绘走透明管线(depth_prepass_alpha), 渲染优先级才参与排序",
		c_code.contains("depth_prepass_alpha"), "立绘不是透明管线 ⇒ ⑫d 量不到先后")
	var a_pri: int = (auras0[0] as Sprite3D).render_priority if auras0.size() > 0 and is_instance_valid(auras0[0]) else 999
	var c_pri: int = c_mat.render_priority if c_mat != null else -999
	_ok("⑫d 金火气画在龟身后: 火的渲染优先级 %d < 立绘 %d" % [a_pri, c_pri],
		a_pri < c_pri, "火排在立绘之后画 ⇒ 实心火把龟整只盖没(那正是时之砂替掉白球的原因)")
	## ★★必须推到【蓄力中段】再判: 第一次调 `_ts_update_trigger` 只负责「开始蓄力」, 推光点那行根本没跑 ——
	##   只在那一刻判「光点没亮」是恒真式(2026-09-15 反向验证 Z21: 删掉 LEAD 闸照样绿)。
	ts._ts_update_trigger(0.3)
	_ok("★分母⑫: 推了 0.3 秒之后还在蓄力、剩余 %.2f 秒 > 光点提前量 0.17 秒" % float(ts._ts_charge_t),
		bool(ts._ts_charging) and float(ts._ts_charge_t) > 0.17, "不在蓄力中段 ⇒ ⑫b 量不到「提前亮」")
	_ok("⑫b 蓄力中段胸口光点【还没】亮(参考: 光点只在释放前 0.17 秒)(%d 个)" % (ts._ts_core_sprs as Array).size(),
		(ts._ts_core_sprs as Array).is_empty(), "光点一开始就亮 ⇒ 没有「最后一下从胸口爆开」的节奏")
	ts._ts_update_trigger(10.0)
	var auras_gone: bool = true
	for a in auras0:
		if is_instance_valid(a) and not (a as Node).is_queued_for_deletion():
			auras_gone = false
	_ok("⑫c 释放那一刻金火气收掉、胸口光点在场(火剩 %d · 光点 %d)" % [(ts._ts_aura_sprs as Array).size(), (ts._ts_core_sprs as Array).size()],
		auras_gone and (ts._ts_aura_sprs as Array).is_empty() and (ts._ts_core_sprs as Array).size() == 1,
		"火没收 ⇒ 20 秒定格里一团火冻在龟身上; 光点不在 ⇒ 「从人物中间爆开」没有起点")
	var tts1: float = float((tents.get(tk, {}) as Dictionary).get("ts", -1.0))
	var hp1: Vector2 = (helis[0] as Dictionary).get("pos", Vector2.ZERO) if helis.size() > 0 else Vector2.ZERO
	_ok("★分母⑥: 触手的内部钟在时停【之前】是会走的(%.3f → %.3f)" % [tts0, tts1],
		(tts1 - tts0) > 0.001, "它本来就不走 ⇒ 判据⑧ 是恒真式")
	_ok("★分母⑦: 直升机在时停【之前】是会飞的(移了 %.2f 码)" % hp0.distance_to(hp1),
		hp0.distance_to(hp1) > 0.5, "它本来就不飞 ⇒ 判据⑨ 是恒真式")
	var sv1: float = float(_s._spec.val(other, "probe_decay"))
	_ok("★分母④: 那笔余额在时停【之前】是会掉的(%.1f → %.1f)" % [sv0, sv1],
		(sv0 - sv1) > 0.5,
		"它本来就不掉 ⇒ 判据⑥「时停期间不掉」是恒真式")
	_ok("★分母③: 时停真的进了(active=%d, 剩 %.1f 秒)"
		% [(ts._ts_active as Array).size(), float(ts._ts_remaining)],
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 5.0,
		"没进时停 ⇒ 下面全是空检查")
	## ── ⑩ 释放演出的接线: 真入口在推钟, 且每一段喂进 shader 的量 == 纯函数 `ts_wave_at` 的量 ──
	## GPU 上画没画出来无头量不了(实拍逐帧记在研究文档里), 这里守两件事:
	##   ① 钟是 `_render_step → _ts_tick_visual` 在推(不是我在测试里推) ② 五段每段的量都真的喂进去了。
	var wmat: ShaderMaterial = ts._ts_rect.material if ts._ts_rect != null else null
	var TSS = ts.get_script()
	var wt0: float = float(ts._ts_wave_t)
	await _wait(6)
	_ok("⑩a 释放演出的钟由真入口推着走(_ts_wave_t %.4f → %.4f)" % [wt0, float(ts._ts_wave_t)],
		float(ts._ts_wave_t) > wt0, "钟不走 ⇒ 环永远停在出发点, 后面几段一段都放不出来")
	var ph_mid: Dictionary = {}
	var ph_first: Dictionary = {}
	var tq := 0.0
	while tq < 4.0:
		var pq: String = str(TSS.ts_wave_at(tq)["phase"])
		if not ph_first.has(pq):
			ph_first[pq] = tq
		ph_mid[pq] = (float(ph_first[pq]) + tq) * 0.5
		tq += 0.005
	var feed_bad: Array = []
	var PAIRS: Array = [["wave_r", "r"], ["wave_a", "a"], ["warp", "warp"], ["amount", "grey"],
		["violet", "violet"], ["hue_flip", "flip"], ["zoom_blur", "zoom"], ["core_flash", "flash"]]
	for pn in ["out", "violet", "flip", "in", "flash"]:
		if not ph_mid.has(pn) or wmat == null:
			feed_bad.append(pn + ":缺段")
			continue
		ts._ts_wave_step(float(ph_mid[pn]))
		var wq: Dictionary = TSS.ts_wave_at(float(ph_mid[pn]))
		for pr in PAIRS:
			## ★null 安全: 从没被设过的 uniform 读回来是 null, float(null) 会让整个测试静默中止
			##   (2026-09-15 反向验证 Z23 就是这么「没打出结果」的) ⇒ null 当 -999, 必然对不上
			var pv = wmat.get_shader_parameter(pr[0])
			var fv: float = -999.0 if pv == null else float(pv)
			if absf(fv - float(wq[pr[1]])) > 0.0001:
				feed_bad.append("%s.%s" % [pn, pr[0]])
	_ok("⑩b 五段(出去/染紫/翻转/收回/白光)每段 8 个量都喂进了 shader(对不上 %d 处 %s)" % [feed_bad.size(), str(feed_bad.slice(0, 4))],
		feed_bad.is_empty() and ph_mid.size() >= 6, "纯函数算对了但没喂 ⇒ 画面上那一段不存在")
	## 跳到整段放完 —— 后面的冻结判据要在「定格后的静止世界」里量
	ts._ts_wave_t = float(TSS.TS_WAVE_TOTAL) + 0.05
	await _wait(3)
	_ok("⑩c 整段放完后胸口光点收干净(剩 %d 个)" % (ts._ts_core_sprs as Array).size(),
		(ts._ts_core_sprs as Array).is_empty(), "光点没收 ⇒ 20 秒定格里胸口一直挂着一团光")
	await _wait(40)   # 让入停那一下的演出跑完 —— 它本来就不该冻

	## ── ⑬ 五段时间线(纯函数)。★期望值写死成参考帧数 ÷ 30, 不读被测常量 ──
	## 参考 clip.mp4 11.00~12.47 秒逐帧: 环出画面 3 帧 / 出去+染紫到翻转开始 #001→#017 = 0.53 秒 /
	## 翻转 #017~#029 = 13 帧 / 收回 #030→#034 每帧收 ≈0.11 屏高(≈3.4 屏高/秒) / 白光 #035~#044 = 10 帧。
	var rows: Array = []
	var seq: Array = []
	var tr := 0.0
	while tr < 4.0:
		var wr: Dictionary = TSS.ts_wave_at(tr)
		rows.append([tr, wr])
		if seq.is_empty() or str(seq[-1]) != str(wr["phase"]):
			seq.append(str(wr["phase"]))
		tr += 0.005
	_ok("⑬a 段序 = 出去 → 染紫 → 色相翻转 → 收回 → 白光 → 定格(实测 %s)" % str(seq),
		seq == ["out", "violet", "flip", "in", "flash", "done"], "段序不对 ⇒ 不是参考那个过程")
	var span: Dictionary = {}
	for rw in rows:
		var pk: String = str(rw[1]["phase"])
		if not span.has(pk):
			span[pk] = [float(rw[0]), float(rw[0])]
		span[pk][1] = float(rw[0])
	var d_out: float = float(span.get("out", [0, -1])[1]) - float(span.get("out", [0, 0])[0]) + 0.005
	var d_vio: float = float(span.get("violet", [0, -1])[1]) - float(span.get("violet", [0, 0])[0]) + 0.005
	var d_flip: float = float(span.get("flip", [0, -1])[1]) - float(span.get("flip", [0, 0])[0]) + 0.005
	var d_fl: float = float(span.get("flash", [0, -1])[1]) - float(span.get("flash", [0, 0])[0]) + 0.005
	var r_out_end: float = 0.0
	var r_at_010: float = 0.0
	var mono_out: bool = true
	var mono_in: bool = true
	var r_in_first: float = -1.0
	var r_in_last: float = -1.0
	var t_in_10: float = -1.0
	var t_in_05: float = -1.0
	var flag_bad: Array = []
	var prev_r: float = -1.0
	var prev_ph: String = ""
	for rw in rows:
		var t_: float = float(rw[0])
		var w_: Dictionary = rw[1]
		var p_: String = str(w_["phase"])
		var r_: float = float(w_["r"])
		if p_ == "out":
			if prev_ph == "out" and r_ < prev_r - 0.0001:
				mono_out = false
			r_out_end = r_
			if t_ <= 0.10 + 0.0001:
				r_at_010 = r_
		if p_ == "in":
			if r_in_first < 0.0:
				r_in_first = r_
			if prev_ph == "in" and r_ > prev_r + 0.0001:
				mono_in = false
			r_in_last = r_
			if t_in_10 < 0.0 and r_ <= 1.0:
				t_in_10 = t_
			if t_in_05 < 0.0 and r_ <= 0.5:
				t_in_05 = t_
		var want: Dictionary = {}
		match p_:
			"out": want = {"violet": 1.0, "flip": 0.0, "grey": 0.0, "a": 1.0}
			"violet": want = {"violet": 1.0, "flip": 0.0, "grey": 0.0, "a": 0.0}
			"flip": want = {"violet": 0.0, "flip": 1.0, "grey": 0.0, "a": 0.0}
			"in": want = {"violet": 0.0, "flip": 1.0, "grey": 1.0, "a": 1.0, "warp": 1.0}
			"flash": want = {"violet": 0.0, "flip": 0.0, "grey": 1.0, "a": 0.0}
			"done": want = {"violet": 0.0, "flip": 0.0, "grey": 1.0, "a": 0.0, "warp": 0.0, "zoom": 0.0, "flash": 0.0}
		for wk in want.keys():
			if absf(float(w_[wk]) - float(want[wk])) > 0.0001:
				flag_bad.append("%s@%.3f.%s" % [p_, t_, wk])
		prev_r = r_
		prev_ph = p_
	_ok("⑬b 出去【一道】环先快后慢冲出屏: 0.10 秒时半径 %.2f(参考那一刻已到画面边 0.88) · 出去结束 %.2f(屏角最远 2.04) · 单调=%s · 用时 %.3f 秒"
		% [r_at_010, r_out_end, str(mono_out), d_out],
		r_at_010 >= 0.88 and r_out_end >= 2.04 and mono_out and d_out <= 0.30, "")
	## ⑬h 出去那一道环【在画面里露几帧】—— 30fps 取样(用户看的录屏就是 30fps)。
	##   参考 #001 半宽 0.76 / #002 0.88 / #003 同一张, #004 出屏 ⇒ 露 3 帧。
	##   ★由来: 第五版第一次实录, 环只露 1 帧就出屏, 读成一闪 —— ⑬b 的「0.10 秒时 ≥ 0.88」照样绿(半径大过头也算过)。
	var vis_frames: int = 0
	for kf in range(0, 12):
		var wf: Dictionary = TSS.ts_wave_at(float(kf) / 30.0)
		if str(wf["phase"]) == "out" and float(wf["r"]) > 0.2 and float(wf["r"]) <= 0.90:
			vis_frames += 1
	_ok("⑬h 出去的环在画面里露 %d 帧(30fps · 参考 #001~#003 = 3 帧, 少于 3 帧读成一闪)" % vis_frames,
		vis_frames >= 3, "环一出来就出屏 ⇒ 看不出「从人物中心往全图散开」")
	_ok("⑬c 出去 + 染紫 = %.3f 秒(参考 #001→#017 = 0.53 秒 ±0.05)" % (d_out + d_vio),
		absf(d_out + d_vio - 0.53) <= 0.05, "")
	_ok("⑬d 色相翻转 %.3f 秒(参考 #017~#029 = 0.43 秒 ±0.04)" % d_flip, absf(d_flip - 0.43) <= 0.04, "")
	var spd_in: float = (0.5 / maxf(0.001, t_in_05 - t_in_10)) if t_in_10 >= 0.0 and t_in_05 > t_in_10 else -1.0
	_ok("⑬e 收回从屏外(%.2f)一路收到人物(%.2f) · 单调=%s · 中段速度 %.2f 屏高/秒(参考 ≈3.4, 容 2.5~4.5)"
		% [r_in_first, r_in_last, str(mono_in), spd_in],
		r_in_first >= 2.04 and r_in_last <= 0.05 and mono_in and spd_in >= 2.5 and spd_in <= 4.5, "")
	_ok("⑬f 中心白光 %.3f 秒(参考 #035~#044 = 0.33 秒 ±0.04)" % d_fl, absf(d_fl - 0.33) <= 0.04, "")
	_ok("⑬g 每段该开的开、该关的关(%d 个采样点, 违反 %d 处 %s)" % [rows.size(), flag_bad.size(), str(flag_bad.slice(0, 4))],
		flag_bad.is_empty() and rows.size() > 500, "例: 收回段环外没变灰 / 定格后翻转色没关")
	## ── ⑭ shader 本体: 色相翻转必须【亮度不动】, 环是【一道】 ──
	## 实测参考 #015 vs #020: 亮度相关 +0.89、色度相关转负 ⇒ 不是 RGB 全反(那样亮度相关为负)。
	## 2y - c 的亮度 = 2y - y = y ⇒ 亮度严格不变; 1 - c 的亮度 = 1 - y ⇒ 亮暗整个倒过来。
	var sh_code: String = str(wmat.shader.code) if wmat != null and wmat.shader != null else ""
	_ok("⑭a 色相翻转用的是【保亮度】的 2y - c(不是 RGB 全反 1 - c)",
		sh_code.contains("vec3(2.0 * y) - c") and not sh_code.contains("vec3(1.0) - c"), "")
	_ok("⑭b 波环只有【一道】(三个参考样本出去/收回都是一道; 不许回到 3 道同心环)",
		sh_code.contains("float ring = clamp(max(core, halo)") and not sh_code.contains("float(k) * 0.17"), "")

	# ── ③ 判据: 时停期间, 背景一个都不许动 ──
	var dur: Array = await _window(90, "")
	var dur_bg: Array = dur.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("① 时停期间【背景远景】0 个节点在动(实测 %d 个, 时停前是 %d 个)"
		% [dur_bg.size(), pre_bg.size()],
		dur_bg.is_empty(),
		"这些还在动: %s" % str(dur_bg.slice(0, 6)))

	var dur_other: Array = dur.filter(func(k): return str(k) == other_path)
	_ok("② 时停期间【非携带者那只的立绘】一动不动(位置/帧号/颜色)",
		dur_other.is_empty(),
		"它变了 —— 只有携带者能动, 别人必须定格")

	print("     [探针] 时停期间仍在动的全部节点(应当只剩时停自己的演出 + 携带者自己): %s"
		% str(dur.slice(0, 8)))

	# ── ⑥ 判据: 全场性的每帧 tick 必须被时停门住(量账, 不量画面) ──
	## 拿 `_spec` 的线性衰减当尺子: 它是 `if _fight_on:` 那一块里最容易量的一条,
	## 而那一块整块共命运 —— 它冻住了, 触手/直升机/羁绊计时就都冻住了。
	var dv0: float = float(_s._spec.val(other, "probe_decay"))
	await _wait(120)
	var dv1: float = float(_s._spec.val(other, "probe_decay"))
	_ok("⑥ 时停期间【非携带者的护盾余额】一点都不掉(%.2f → %.2f)" % [dv0, dv1],
		absf(dv0 - dv1) < 0.01,
		"掉了 %.2f —— `if _fight_on:` 那一整块(触手/直升机/羁绊/余额)没被时停门住" % (dv0 - dv1))

	# ── ⑧⑨ 判据: **直接量用户点名的那两样**, 不拿余额当代理 ──
	## 用户 2026-09-14:「确定所有东西都定住了吗, **像触手, 直升机等等**」。
	## v0.19.382 我量的是护盾余额(同一块 tick, 共命运) —— 结构上说得通, 但那是**推断**。
	## 需求点名了谁就拿谁验(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
	var tt_a: float = float((tents.get(tk, {}) as Dictionary).get("ts", -1.0))
	var hpa: Vector2 = (helis[0] as Dictionary).get("pos", Vector2.ZERO) if helis.size() > 0 else Vector2.ZERO
	await _wait(120)
	var tt_b: float = float((tents.get(tk, {}) as Dictionary).get("ts", -1.0))
	var hpb: Vector2 = (helis[0] as Dictionary).get("pos", Vector2.ZERO) if helis.size() > 0 else Vector2.ZERO
	_ok("⑧ 时停期间【触手】的内部钟一动不动(%.3f → %.3f)" % [tt_a, tt_b],
		absf(tt_b - tt_a) < 0.001,
		"走了 %.3f 秒 —— 触手在定格的世界里照样甩" % (tt_b - tt_a))
	_ok("⑨ 时停期间【直升机】一码都不飞(移了 %.2f 码)" % hpa.distance_to(hpb),
		hpa.distance_to(hpb) < 0.01,
		"它还在飞 —— `tick_global` 的注释写着「碑/直升机/炮台还要继续动」, 时停必须门住它")

	# ── ⑦ 判据: 入停演出跑完之后, 世界里不许再有节点生灭 ──
	## ★要先等入停那一下自己跑完(蓄力的 10 颗金沙 + 涟漪 + 金环共 11 个会在头 1 秒内收掉),
	##   它们是**时停自己的演出**, 本来就不该冻。不等就会把它们算成"世界还在动"。
	var cp: Vector3 = _s._world_pos(carrier["pos"], 0.8)
	var nc0: int = _count_far(_s._world, cp, 3.0)
	await _wait(120)
	var nc1: int = _count_far(_s._world, cp, 3.0)
	_ok("⑦ 时停期间【携带者 3 米以外】的节点数不再生灭(%d → %d)" % [nc0, nc1],
		absi(nc1 - nc0) <= 1,
		"变了 %+d —— 还有东西在建/销毁(①②③ 的快照差看不见这一类)" % (nc1 - nc0))

	## ⑪ 放完之后 20 秒定格里: 环/扭曲/染紫/翻转/拖影/白光全归零, 只剩灰世界 —— 任何一个留着就是全屏一直花着
	var left_on: Array = []
	for pn2 in ["wave_a", "warp", "violet", "hue_flip", "zoom_blur", "core_flash"]:
		var pv2 = wmat.get_shader_parameter(pn2) if wmat != null else null
		if pv2 == null or float(pv2) > 0.001:
			left_on.append("%s=%s" % [pn2, str(pv2)])
	var amt_v = wmat.get_shader_parameter("amount") if wmat != null else null
	_ok("⑪ 释放演出放完后环/扭曲/染紫/翻转/拖影/白光全归零、灰世界满值(还开着 %s · amount=%s)" % [str(left_on), str(amt_v)],
		wmat != null and left_on.is_empty() and amt_v != null and float(amt_v) > 0.99,
		"放完还留着 ⇒ 20 秒定格里全屏一直是花的/糊的")

	# ── ④ 判据: 灰世界要**一直**灰到解除, 不能灰一下就没了 ──
	## ★★量这条时我自己先栽了一次: VFXLAB 的拍点排在**游戏钟**上, 而时停期间游戏钟是**冻结**的
	##   ⇒ 目标 11.6 / 12.5 / 14.0 三个拍点全部落在 t=11.00 同一个点上, 再往后的拍点
	##   (17/21/26)其实已经是**时停结束之后**了。我照着那组数差点写下"灰世界只持续 1 秒"。
	##   ⇒ 验持续性不能按游戏钟采样, 直接读产品自己的 shader 参数。
	##   (memory [[fb-second-clock-drops-events]]: 两条钟必然丢事件)
	var rect = ts._ts_rect
	var amt_hold: float = -1.0
	var amt_min: float = 999.0
	if rect != null and is_instance_valid(rect) and rect.material != null:
		for _k in range(6):                       # 跨 6 个采样窗口(真实时间), 期间不许掉下去
			await _wait(20)
			amt_hold = float(rect.material.get_shader_parameter("amount"))
			amt_min = minf(amt_min, amt_hold)
	_ok("④ 压暗褪色在整段时停里**一直**满值(6 次采样最小 %.2f)" % amt_min,
		amt_min > 0.95,
		"灰世界中途掉下去了 —— 20 秒的时停只灰开头几帧等于没做")

	# ── ⑤ 判据: 解除后必须恢复 —— 冻死了也是 bug ──
	ts._end_timestop()
	await _wait(20)
	var post: Array = await _window(90, "")
	var post_bg: Array = post.filter(func(k): return str(k).begins_with("/FarBackdrop"))
	_ok("⑤ 解除时停后【背景远景】重新动起来(实测 %d 个, 时停前 %d 个)"
		% [post_bg.size(), pre_bg.size()],
		post_bg.size() >= maxi(20, pre_bg.size() / 2),
		"只验「冻得住」会放过「再也不动了」—— _ts_resume_freeze 必须把 tween play 回来")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
