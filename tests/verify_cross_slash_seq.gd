extends Node
## verify_cross_slash_seq.gd — 十字斩的【完整时序】：后撤 → 蓄力 → 横斩 → 竖斩 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-29 逐段点名核对：
##   「释放技能首先是向后退对吧？**这个你怎么实现**，然后是蓄力，**你做了吗**，
##     然后砍第一刀？**你全部做了吗**」
##
## 查下来三段里只做了一段半：
##   · **后撤**：位置是 `u["pos"] = dest` **瞬移**，演出只有落点一个尘环；
##     而 `cross_retreat` 的头注写着「起点留一道残影」—— **代码里根本没有残影**
##     （注释在替一个不存在的实现背书）
##   · **蓄力**：**完全没有**。落地到第一刀之间的 0.25 秒是全空的
##   · **第一刀**：有
##
## ⇒ 补：后撤沿路铺拖影（结算位置仍瞬移，几何不动）+ 那 0.25 秒补剑气收拢与预备形变。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么
## ══════════════════════════════════════════════════════════════════════
## ★判据落在**产品自己建出来的节点**（`blade_eq_vfx` 的 `_fx` 队列 / `_world` 的子节点），
##   不是"我插的标记被设过" (memory [[fb-gate-must-measure-requirement-not-my-hook]])。
## ★**逐段分别断言**：后撤、蓄力、第一刀各自都要有东西 ——
##   只断言"整招放出来了"守不住"中间少了一拍"，那正是用户问出来的病。
## ★每段配分母。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_cross_slash_seq.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EqBladeBatch := preload("res://scripts/systems/equip/eq_blade_batch.gd")
const BladeEqVfx := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## `blade_eq_vfx._fx` 里某一类短命特效当前有几个。
## ★读的是产品自己的队列 —— 演出真的建了节点才会有条目。
func _fx_count(kind: String) -> int:
	var n := 0
	for f in _s._equip_sys._blade_sys.vfx._fx:
		if str((f as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 十字斩时序: 后撤 → 蓄力 → 横斩 → 竖斩 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── 分母：时序常量还是那三个数 ──
	_ok("★分母: 后撤 150 码 / 第一刀 0.25 秒 / 第二刀 0.60 秒",
		absf(EqBladeBatch.HH_BACKSTEP - 150.0) < 0.001
			and absf(EqBladeBatch.CROSS_T1 - 0.25) < 0.001
			and absf(EqBladeBatch.CROSS_T3 - 0.60) < 0.001,
		"退%.0f 码 / T1=%.2f / T3=%.2f"
			% [EqBladeBatch.HH_BACKSTEP, EqBladeBatch.CROSS_T1, EqBladeBatch.CROSS_T3])

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-200, 0))
	u["no_move"] = true
	u["no_basic"] = true
	## ★设 base_atk 再 _recalc_stats —— 直接写 u["atk"] 会被产品按 base_atk 重算回去
	##   (探针假象, 已在 _probe_copy_residue 头注记过一次: atk 120→44)
	u["base_atk"] = 100.0
	## ★★摆位很讲究: 后撤是**远离目标** 150 码, 而斩击只有 250 码
	##   ⇒ 起手距离必须 ≤ 100 码, 退完才还在斩击范围内。
	##   我第一版摆 380 码(以为退完变 230), **方向想反了** —— 退完是 530 码,
	##   实测只结算 2/4 段(只有两道剑波打中, 两刀全空)。取 80 码 ⇒ 退完 230 码。
	var tgt: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-200 + 80, 0))
	tgt["maxHp"] = 1.0e8
	tgt["hp"] = 1.0e8
	tgt["no_basic"] = true
	tgt["no_move"] = true
	_s._units.clear()
	_s._units.append(u)
	_s._units.append(tgt)
	_s._over = false
	_s._recalc_stats(u)
	_s._equip_sys._blade_sys._spawn084(u, 2)
	## ★关暴击 —— `_resolve_dmg` 每段都掷暴击, 不关的话合计每次都不一样
	##   (实测两次跑出 462 / 565)。要验"四段合计"就得先把随机项按住。
	u["crit"] = 0.0
	_ok("★分母: 攻击力真的是 100(手写 atk 会被 _recalc_stats 重算回去)",
		absf(float(u.get("atk", 0.0)) - 100.0) < 0.51, "atk=%.1f" % float(u.get("atk", 0.0)))
	_ok("★分母: 进了近战形态(不然放不出十字斩)", str(u.get("_b84_mode", "")) == "melee")

	var p0: Vector2 = u["pos"]
	var d0: float = (p0 - (tgt["pos"] as Vector2)).length()

	# ══ ① 后撤 ══
	_s._equip_sys._blade_sys.cast_cross_slash(u, tgt)
	## ★★★核心: 后撤必须是【真的滑过去】, 不是瞬移。
	##   用户 2026-08-29 追问「**你还是瞬移吗**」—— 原来是。
	##   判据: 刚放完技能的那一刻, 龟**还在起跳点附近**(位移 < 全程的一半);
	##   而全程走完之后才到落点。一步到位的话第一条当场红。
	var d_now: float = ((u["pos"] as Vector2) - p0).length()
	_ok("★★★① 后撤是【滑过去】不是瞬移: 刚放完时还没走完",
		d_now < EqBladeBatch.HH_BACKSTEP * 0.5,
		"刚放完已位移 %.1f 码 / 全程 %.0f 码(瞬移的话这里就是 150)"
			% [d_now, EqBladeBatch.HH_BACKSTEP])
	## 滑行途中: 必须真的处在【起跳点与落点之间】, 而且位移单调增加
	var mid_seen := false
	var last_d: float = d_now
	var mono := true
	var tr := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tr < 1500:
		var dd: float = ((u["pos"] as Vector2) - p0).length()
		if dd + 0.01 < last_d:
			mono = false                      # 往回缩了 = 被别的系统拽着, 不是干净的后跃
		last_d = dd
		if dd > EqBladeBatch.HH_BACKSTEP * 0.25 and dd < EqBladeBatch.HH_BACKSTEP * 0.85:
			mid_seen = true                   # 抓到过"在半路上"的那一帧
		if dd >= EqBladeBatch.HH_BACKSTEP - 0.5:
			break
		await get_tree().process_frame
	_ok("★★★① 滑行途中真的出现在【半路上】(瞬移抓不到这一帧)", mid_seen,
		"整段没抓到 25%~85% 之间的位置")
	_ok("★① 位移一路单调向后(没被移动系统拽回去)", mono, "中途出现过回缩")

	var p1: Vector2 = u["pos"]
	var d1: float = (p1 - (tgt["pos"] as Vector2)).length()
	_ok("★★① 后撤: 最终正好退了 150 码(背对目标)",
		absf((d1 - d0) - EqBladeBatch.HH_BACKSTEP) < 1.0,
		"离目标 %.0f → %.0f 码" % [d0, d1])
	## ★分母: 滑行必须在第一刀【之前】走完 —— 否则斩击的圆心会漂到半路上
	_ok("★★① 分母: 滑行(%.2f 秒)早于第一刀(%.2f 秒) ⇒ 斩击圆心仍是落点"
			% [EqBladeBatch.RETREAT_SEC, EqBladeBatch.CROSS_T1],
		EqBladeBatch.RETREAT_SEC < EqBladeBatch.CROSS_T1)
	_ok("★① 滑完解掉了施法锁(_slam), 不会卡住不动", not bool(u.get("_slam", false)))
	## ★★后撤【演出】: 沿路的拖影。修前这里是 0(注释说有残影, 代码里没有)。
	var ghosts: int = _fx_count("fade")
	_ok("★★① 后撤演出: 沿路铺了拖影(修前是 0 —— 注释说有残影而代码里没有)",
		ghosts >= 3, "fade 类特效 %d 个(期望 ≥3)" % ghosts)

	# ══ ② 蓄力（后撤落地 → 第一刀之间那 0.25 秒）══
	var motes: int = _fx_count("suck")
	_ok("★★② 蓄力: 剑气在收拢(修前那 0.25 秒是全空的)",
		motes >= 4, "suck 类特效 %d 个(期望 ≥4)" % motes)
	## 分母: 蓄力必须在【第一刀之前】就存在, 不能是砍完才补
	_ok("★★② 分母: 蓄力发生在第一刀【之前】(此刻还没有任何刀光)",
		_fx_count("holdfade") == 0,
		"此刻 holdfade(刀光) %d 个" % _fx_count("holdfade"))

	# ══ ③④ 四段依次落地 ══
	## ★★不能用【写死的墙钟窗口】: CROSS_T1/T3 是**游戏秒**, 而无头下游戏钟与墙钟不同步
	##   (CLAUDE.md §3.5: 战斗时钟走钳制后的 delta) ⇒ 固定 700ms 有时够有时不够,
	##   第一版就因此偶发红("目标掉了 0")。改成**轮询到事件发生**(§3.5.1 的办法),
	##   上限防死循环。
	## ★★这条门禁守的是【时序完整】, 不是【数值精确】——
	##   精确数值由 `verify_eq_blade_batch` 用干净夹具焊着(横斩 270 / 横波 175 / …)。
	##   这里再去对总额, 就会被夹具细节缠住: 我第一版拿 `basic` 龟当施法者,
	##   触发了**小龟·不屈的稀有度增伤**、又叠上目标护甲, 总额怎么算都对不上
	##   (实测稳定 377 而不是 1084)。判据没问对问题(memory [[fb-judge-must-fit-the-shape]])。
	##   ⇒ 改成数【四次独立的掉血事件】—— 那才是"分四段依次落地"的直接证据。
	var hp0: float = float(tgt["hp"])
	var saw_slash := false
	var saw_wave := false
	var hits: Array = []                        # 每次掉血记一笔(这一下掉了多少)
	var last_hp: float = hp0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		if _fx_count("holdfade") > 0:
			saw_slash = true
		if _fx_count("wave") > 0:
			saw_wave = true
		var now: float = float(tgt["hp"])
		if now < last_hp - 0.5:
			hits.append(last_hp - now)
			last_hp = now
		if hits.size() >= 4 and saw_slash and saw_wave:
			break
		await get_tree().process_frame
	var total: float = hp0 - float(tgt["hp"])
	_ok("★★③ 第一刀: 出了刀光", saw_slash, "整段没见到 holdfade(刀光)特效")
	_ok("★★③ 第一刀: 真的打到了伤害", hits.size() >= 1 and float(hits[0]) > 1.0,
		"第一次掉血 %.0f" % (float(hits[0]) if hits.size() >= 1 else 0.0))
	_ok("★★④ 剑波: 真的飞出去了", saw_wave, "整段没见到 wave 类特效")
	## ★★核心: 四段【依次】落地 —— 四次独立的掉血事件, 不是一次全给
	_ok("★★④ 四段依次落地(数到 %d 次独立掉血, 期望 4)" % hits.size(),
		hits.size() == 4, "每次: %s · 合计 %.0f" % [str(hits.map(func(x): return int(x))), total])
	_ok("★分母: 合计 %.0f > 0 且第一下只占一部分 ⇒ 真的分了段" % total,
		total > 1.0 and hits.size() >= 2 and float(hits[0]) < total * 0.7)

	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 17:
		print("  [FAIL] ★分母: 断言只有 %d 条(<17) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 十字斩时序" if _fail == 0 else "FAIL x%d — 十字斩时序" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
