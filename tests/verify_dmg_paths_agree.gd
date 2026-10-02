extends Node
## verify_dmg_paths_agree.gd — 两条伤害路【同输入必须同输出】
##
## ══════════════════════════════════════════════════════════════════
##  ★这个文件守的是一整类问题，不是一个 bug
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-04：「自己想想，前面才发现的真实伤害数字是一团乱，应该统一规则的」
##
## CLAUDE.md §3.3 早就写着「两条伤害路，改一条必须两条都改」——
## 但那是**写给人看的纪律**，没有任何门禁会为违反它变红。结果：
##   · 飘字**颜色**：只有 `_apply_damage_from` 按标准表取，另一条用调用点传的 col（v0.19.323 才补）
##   · 飘字**跳法/排行**：同上（v0.19.322 才补）
##   · **统计记账**：`_record_buckets()` 是抽好的共用函数，`_from` 走它，
##     而 `_apply_damage` **自己又写了一遍**，条件还不一样 ← 本文件第一条抓的就是它
##
## ⇒ 判据形状固定：**给两条路喂同一份输入，断言可观察结果相同**。
##   以后每发现一项，往这里加一条，不要再散落到各自的测试里。
##
## ★★不做什么：不断言"两条路调了同一个函数"（那是实现细节，改个写法就红，
##   而且证明不了结果一致）。只断言**外部可观察的结果**。
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


## 造一个干净的合成单位（不拿随机 spawn 的真单位 —— memory [[fb-ci-vs-local-divergence]]：
## 队伍未播种 RNG、敌带盾/flat_dr，会让精确数值断言在 CI 上偶发红）。
func _mk(side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, at)
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["active_skills"] = []
	u["maxHp"] = 999999.0
	u["hp"] = 999999.0
	u["shield"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["deathfloor_until"] = 999999.0
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 两条伤害路: 同输入同输出 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5

	# ══════════════════════════════════════════════════════════════
	#  ① 统计记账：攻击者【死了之后】造成的伤害，两条路都该算给他
	# ══════════════════════════════════════════════════════════════
	## 真实场景：A 给 B 上了灼烧，A 死了，灼烧继续跳。
	##   走 `_apply_damage_from` → `_record_buckets`：条件是 `src.has("side")` ⇒ **记**
	##   走 `_apply_damage` 自己写的那份：条件是 `src.get("alive")` ⇒ **不记**
	## ⇒ 同样一份伤害，算不算进"造成"，取决于走哪条路。
	##   用户 2026-07-19 报过「统计面板感觉很多伤害没统计」，那次只修了一半。
	print("── ① 施加者已阵亡时的【造成】记账 ──")
	var dead_src: Dictionary = _mk("left", c + Vector2(-260, 0))
	var v1: Dictionary = _mk("right", c + Vector2(60, -70))
	var v2: Dictionary = _mk("right", c + Vector2(60, 70))
	dead_src["alive"] = false          # ★施加者已死，但字典还在（DoT 来源就是这个状态）
	dead_src["_st_dealt"] = 0
	await get_tree().process_frame

	## ⚠ 判据**不能比两条路的绝对数值**（同 §② 的坑，我在这条上犯了第二次）：
	##   `_from` 走完整结算会吃稀有度加成等乘子，100 进 120 出 —— 那是对的。
	##   要断言的是「**记账这件事发不发生**」，以及「记的数 == 自己造成的数」。
	var hpv1: float = float(v1["hp"]); var d0: int = int(dead_src.get("_st_dealt", 0))
	_s._damage._apply_damage(v1, 100, Color("#ffffff"), dead_src, "tru")
	var after_a: int = int(dead_src.get("_st_dealt", 0)) - d0
	var made_a: int = int(round(hpv1 - float(v1["hp"])))

	var hpv2: float = float(v2["hp"]); var d1: int = int(dead_src.get("_st_dealt", 0))
	_s._damage._apply_damage_from(dead_src, v2, 100, Color("#ffffff"), 0.0, true)
	var after_b: int = int(dead_src.get("_st_dealt", 0)) - d1
	var made_b: int = int(round(hpv2 - float(v2["hp"])))

	_ok("★分母: 两条路都真的打出了伤害(A=%d B=%d)" % [made_a, made_b],
		made_a > 0 and made_b > 0, "有 0 ⇒ 下面是空检查")
	_ok("①a 施加者已阵亡时，`_apply_damage` 也把【造成】记给他(记 %d)" % after_a,
		after_a > 0,
		"记 0 ⇒ 施加者死后 DoT 的伤害不算给他，而另一条路照算 —— 同一份伤害按路径分裂")
	_ok("①b 两条路各自: 记的账 == 自己造成的伤害(A %d==%d · B %d==%d)"
		% [after_a, made_a, after_b, made_b],
		after_a == made_a and after_b == made_b,
		"记账与实际造成对不上")

	# ══════════════════════════════════════════════════════════════
	#  ② 记的账 == 这条路实际扣掉的血（两条路各自内部自洽）
	# ══════════════════════════════════════════════════════════════
	## ⚠ **不能比两条路的绝对数值** —— 我第一版就是这么写的，红了才发现判据错：
	##   `_apply_damage_from` 走完整结算（稀有度加成 `_BASIC_RARITY_BONUS` 默认 +20%、
	##   决胜增伤、暴击），`_apply_damage` 是定额（DoT/真伤专用）。
	##   100 点喂进去，一条扣 100、一条扣 120 —— **那是对的**，不是 bug。
	##   把正确的差异当 bug 修，正是 memory [[fb-judge-must-fit-the-shape]] 那条。
	## ⇒ 判据改成「记的账 == 这条路自己实际扣掉的血」，对两条路都成立，
	##   且它才是"统计面板显示的数对不对"的真定义。
	print("── ② 记账 == 实际扣血（各路自洽）──")
	var live_src: Dictionary = _mk("left", c + Vector2(-200, 0))
	var t1: Dictionary = _mk("right", c + Vector2(140, -70))
	var t2: Dictionary = _mk("right", c + Vector2(140, 70))
	await get_tree().process_frame

	var hp_a0: float = float(t1["hp"]); var ta0: int = int(t1.get("_st_taken", 0))
	_s._damage._apply_damage(t1, 100, Color("#ffffff"), live_src, "tru")
	var lost_a: int = int(round(hp_a0 - float(t1["hp"])))
	var rec_a: int = int(t1.get("_st_taken", 0)) - ta0

	var hp_b0: float = float(t2["hp"]); var tb0: int = int(t2.get("_st_taken", 0))
	_s._damage._apply_damage_from(live_src, t2, 100, Color("#ffffff"), 0.0, true)
	var lost_b: int = int(round(hp_b0 - float(t2["hp"])))
	var rec_b: int = int(t2.get("_st_taken", 0)) - tb0

	_ok("★分母: 两条路都真的扣了血(A=%d B=%d)" % [lost_a, lost_b],
		lost_a > 0 and lost_b > 0, "有 0 ⇒ 下面是空检查")
	_ok("②a `_apply_damage`: 记的账 %d == 实际扣血 %d" % [rec_a, lost_a], rec_a == lost_a,
		"记账与实际扣血对不上 ⇒ 统计面板的数是错的")
	_ok("②b `_apply_damage_from`: 记的账 %d == 实际扣血 %d" % [rec_b, lost_b], rec_b == lost_b,
		"同上")

	# ══════════════════════════════════════════════════════════════
	#  ③ 分类型分桶：真伤都必须进 tru 桶（比"进没进"，不比数值）
	# ══════════════════════════════════════════════════════════════
	print("── ③ 真伤都进 tru 桶 ──")
	var b1: int = int((t1.get("_st_taken_by_type", {}) as Dictionary).get("tru", 0))
	var b2: int = int((t2.get("_st_taken_by_type", {}) as Dictionary).get("tru", 0))
	_ok("★分母: 至少一边进了 tru 桶(A=%d B=%d)" % [b1, b2], b1 > 0 or b2 > 0,
		"都 0 ⇒ 分桶压根没记")
	_ok("③a `_apply_damage` 的真伤进了 tru 桶(%d)" % b1, b1 == rec_a,
		"没进或数目对不上 ⇒ 伤害类型统计漏了这条路")
	_ok("③b `_apply_damage_from` 的真伤进了 tru 桶(%d)" % b2, b2 == rec_b, "同上")

	# ══════════════════════════════════════════════════════════════
	#  ④ A-3 受害者侧减伤：同一发名义伤害，两条路必须算出同一个扣血
	# ══════════════════════════════════════════════════════════════
	## 【由来】方案书 `20260904b-全项目代码彻查.md` 的验收项 **A-3**
	##   「两条伤害路：护甲/魔抗结算走同一个收口」长期挂着 ⏳，
	##   而同一份文档的结论段里又写着「A-3 已有三只眼哨兵 ⇒ 查过但不用改」。
	##   —— 登记与结论对不上（memory `fb-registered-todos-rot`）。
	## 查下来**收口确实是真的**（两条路都调 `battle._mitigate_incoming`），
	##   但**没有任何判据量它**：谁把其中一条改成自己算，门禁一条都不会红。
	##
	## ★判据形状照本文件的规矩：**不断言"调了同一个函数"**（那是实现细节），
	##   只断言**外部可观察的结果** —— 同一个带减伤/增伤状态的受害者、同一个名义伤害，
	##   两条路扣掉的血必须一样多。
	## ★★配分母：减伤必须**真的起作用**（扣血 != 名义值）。
	##   否则两条路都原样扣，这条会为了完全错误的理由变绿。
	print("── ④ A-3 受害者侧减伤: 两条路同输入同扣血 ──")
	var m1 := _mk("ally", c + Vector2(260, 60))
	var m2 := _mk("ally", c + Vector2(300, 60))
	var msrc := _mk("enemy", c + Vector2(340, 60))
	## 挂两种受害者侧状态: 靶向器(增伤) + 钩索易伤。两条路都该吃到。
	for m in [m1, m2]:
		m["eq_marked_until"] = _s._t + 30.0
		m["hook_vuln_until"] = _s._t + 30.0
	var NOM := 1000
	var h1: float = float(m1["hp"])
	var h2: float = float(m2["hp"])
	_s._damage._apply_damage(m1, NOM, Color.WHITE, msrc, "phy")
	_s._damage._apply_damage_from(msrc, m2, NOM, Color.WHITE)
	var l1: int = int(round(h1 - float(m1["hp"])))
	var l2: int = int(round(h2 - float(m2["hp"])))
	print("  [分母] 名义 %d → _apply_damage 扣 %d · _apply_damage_from 扣 %d" % [NOM, l1, l2])
	_ok("★分母: 两条路都真的扣了血(A=%d B=%d)" % [l1, l2], l1 > 0 and l2 > 0,
		"有一条是 0 ⇒ 下面那条是空检查")
	_ok("★分母: 受害者侧状态【真的改变了伤害】(名义 %d vs 实扣 %d)" % [NOM, l1], l1 != NOM,
		"扣的正好是名义值 ⇒ 减伤没生效, 两条路'一致'没有意义")
	_ok("④ A-3 同一发名义伤害, 两条路扣血相同(A=%d B=%d)" % [l1, l2], l1 == l2,
		"两条路各算各的受害者减伤 ⇒ 同一个状态在不同伤害类型下表现不同(CLAUDE.md §3.3)")

	# ══════════════════════════════════════════════════════════════
	#  ⑤ A-2 暴击口径：两条路【本就该不同】—— 把这句话变成判据
	# ══════════════════════════════════════════════════════════════
	## 方案书 `20260904b` 的 A-2 写的是「暴击判定口径相同(**或确认本就该不同并写明**)」。
	## 代码里确实写明了(`battle_damage.gd`「was_crit 恒 false: 这条路是 DoT/真伤,
	## 本就不暴击」)—— 但那是**注释**, 谁把 DoT 改成会暴击, 门禁一条都不会红。
	## ⇒ 判成正面判据, 两个方向都断言: 只断言「DoT 不暴击」的话,
	##   暴击整个坏掉(两条都不暴击)也会绿。
	##
	## ★★判据量的是**扣血**, 不是 `_st_crit` 那个计数器。
	##   第一版读了 `_st_crit` —— 它由全局 `battle._last_atk_crit` 驱动, 而那个标志是
	##   **上游 `_resolve_dmg` 设的**; 测试直接调 `_apply_damage_from` 绕过了它,
	##   于是读到的是**上一次活动的残留** ⇒ 同一份代码三次红一次绿。
	##   (memory `fb-gate-must-measure-requirement-not-my-hook`: 判据要量产品自己的账。)
	## ★暴击在这条路上只在 `raw and not pre_crit` 时掷(普通伤害的暴击在上游算过了),
	##   所以攻击路这一发必须走 raw=true, DoT 那一发用 bucket="tru" 对齐同一语义。
	print("── ⑤ A-2 暴击: 攻击路会暴, DoT 路不暴(本就该不同) ──")
	var ca := _mk("ally", c + Vector2(260, 150))
	var cb := _mk("ally", c + Vector2(300, 150))
	var csrc := _mk("enemy", c + Vector2(340, 150))
	csrc["crit"] = 1.0          # 100% 暴击率 ⇒ 必暴, 与随机无关
	csrc["crit_dmg"] = 2.0
	var NOM2 := 500
	var ha: float = float(ca["hp"])
	var hb: float = float(cb["hp"])
	_s._damage._apply_damage_from(csrc, ca, NOM2, Color.WHITE, 0.0, true)   # raw=true
	_s._damage._apply_damage(cb, NOM2, Color.WHITE, csrc, "tru")
	var la: int = int(round(ha - float(ca["hp"])))
	var lb: int = int(round(hb - float(cb["hp"])))
	print("  [分母] 名义 %d · 100%% 暴击率 · 暴伤 ×2 → 攻击路扣 %d · DoT 路扣 %d" % [NOM2, la, lb])
	_ok("★分母: 两条路都真的扣了血(A=%d B=%d)" % [la, lb], la > 0 and lb > 0,
		"有一条是 0 ⇒ 下面是空检查")
	_ok("⑤ A-2 攻击路吃到暴击(扣 %d > DoT 的 %d)" % [la, lb], la > lb,
		"攻击路没暴 ⇒ 暴击机制坏了, 而不是'两条一致'")
	_ok("⑤b A-2 DoT 路一次都不暴 —— 攻击路正好是它的 2 倍(暴伤 ×2)", la == lb * 2,
		"%d vs %d×2=%d ⇒ DoT 也在暴击 或 攻击路暴伤口径变了" % [la, lb, lb * 2])

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
