extends Node
## verify_minion_is_full_turtle.gd — 缩头随从 = 实体完整龟
##
## ══════════════════════════════════════════════════════════════════
##  ★需求原话（判据就照这句写，不是我编的）
## ══════════════════════════════════════════════════════════════════
## 用户 2026-07-17：「**除了血量以外其他东西应该和该龟一模一样**」
##                  「什么被动什么显示和动画都得正常」
##                  「随从我都没看到技能龟能」
## ⇒ 不变量：`_spawn_hiding_minion` 造出来的随从，**键集合 ⊇ 同 id 真龟**（白名单除外）。
##
## ══════════════════════════════════════════════════════════════════
##  ★★这条为什么必须是门禁，而不是一行注释
## ══════════════════════════════════════════════════════════════════
## 2026-09-04 彻查 P2 扫出来的形状：造单位一共**三条路**
##   ① `_make_unit`（107 键）  ② `_spawn_summon`（99 键）  ③ 调试场 `_edit_unit_from_setup`
## 每帧跑的 `_tick_skill_cd` **第一行就直读** `u["skill_cd"]`，唯一挡板是 `_is_passive_pick`：
##
##     func _is_passive_pick(u) -> bool:
##         if u.get("minion_kind", null) != null:
##             return false          # ← 缩头随从从这里**穿过挡板**
##         return u.get("is_summon", false)
##
## 而 `_spawn_summon` 不建 `skill_cd`。今天不崩，只因为 `_spawn_hiding_minion` 里
## **手写补了一行**，注释直说「防 u["skill_cd"][stype] 崩」——
## 说明有人已经撞过这个崩溃，**补在了调用点、没补在挡板，也没留门禁**。
## 再加一个设 `minion_kind` 的召唤物而忘了那行，就当场复发。
##
## ══════════════════════════════════════════════════════════════════
##  ★★★探针实测（写门禁前先量的，不是推理）
## ══════════════════════════════════════════════════════════════════
## 19/19 个龟种的随从，**全部**缺同样 4 个键：
##   `energy_cost` `skill_idx` `contact` `contact_base_scale`
## 逐个查了后果：
##   · `energy_cost` —— `_skill_cost` 缺键时回落 `SkillEnergy.cost_of(type)` 类型兜底。
##     实测 19/19 条**数值恰好相等**，所以今天看不出差别 —— 但那是巧合不是设计。
##     且 `fortune_system.gd:65/82/143` 是**直写** `u["energy_cost"][...]`，
##     随从哪天拿到 2/3 技（`fortuneBuyEquip`）就当场崩。⇒ **已修**：抽出
##     `BattleSpawn.energy_cost_table(d)`，真龟与随从共用，不许各抄一份。
##   · `skill_idx` —— 纯索引，补 0。⇒ 已修。
##   · `contact` / `contact_base_scale` —— **接触核影的 Node**，而它已被关掉
##     （`battle_render.gd:417` `contact.modulate.a = 0.0`「只留影子」）。
##     召唤体走自己的接地 shader 显示路径，本就没有这个 Node。⇒ **白名单，别去补**。
##
## ⇒ 本文件把「随从 ⊇ 真龟（除白名单 2 项）」焊死。白名单只能减不能加。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 允许随从没有的键 —— 每一条都要有理由（见文件头）
const ALLOWED_MISSING := {
	"contact": "接触核影 Node；已被关掉(alpha=0)，召唤体走接地 shader 无此 Node",
	"contact_base_scale": "同上，接触核影的基准缩放",
}

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true     # ★调试台/测试要渲染时不自动置位，会写真存档
	print("=== 缩头随从 = 实体完整龟（用户 2026-07-17）===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var own: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-150, 0))
	_s._units.append(own)

	var pool: Array = _s._hiding_sys._hiding_pool()
	_ok("★分母①: 随从池非空（%d 只 A/B/C 龟）" % pool.size(), pool.size() >= 10,
		"池子空/太小 ⇒ 下面全是空检查")

	# 造到每个龟种各一个（随机 pick，多轮覆盖）
	var byid: Dictionary = {}
	for _i in range(400):
		if byid.size() >= pool.size():
			break
		var before: int = _s._units.size()
		_s._spawn._spawn_hiding_minion(own)
		if _s._units.size() <= before:
			continue
		var m: Dictionary = _s._units[_s._units.size() - 1]
		var mid: String = str(m.get("id", "?"))
		if not byid.has(mid):
			byid[mid] = m
	_ok("★分母②: 造到 %d/%d 个不同龟种的随从" % [byid.size(), pool.size()],
		byid.size() == pool.size(),
		"没造全 ⇒ 漏掉的龟种没被检查")

	# ★分母③ —— 最关键的一条：证明随从**真的穿过挡板**。
	#   若 _is_passive_pick 返回 true，随从压根走不到 _tick_skill_cd，
	#   那么下面所有"键齐全"的断言都是恒真式。
	var sample: Dictionary = byid.values()[0] if byid.size() > 0 else {}
	_ok("★分母③: 随从 `_is_passive_pick` == false（**确实穿过挡板**）",
		byid.size() > 0 and not _s._is_passive_pick(sample),
		"返回 true ⇒ 随从走不到每帧那段代码，下面的断言全是空检查")

	# ── ① 键集合 ⊇ 同 id 真龟 ──
	print("── ① 随从的键 ⊇ 同 id 真龟（白名单除外）──")
	var bad: Array = []
	var checked := 0
	for mid in byid:
		var real: Dictionary = _s._spawn._make_unit(str(mid), "left", c)
		checked += real.size()
		for k in real.keys():
			var ks: String = str(k)
			if ALLOWED_MISSING.has(ks):
				continue
			if not (byid[mid] as Dictionary).has(ks):
				bad.append("%s 缺 %s" % [mid, ks])
	_ok("★分母④: 逐键比对了 %d 次（19 龟种 × 真龟键数）" % checked, checked > 1000,
		"比对次数太少 ⇒ 上面没真跑起来")
	_ok("① 19 个龟种的随从**都没有比真龟少键**", bad.is_empty(),
		"缺 %d 处:\n     %s" % [bad.size(), "\n     ".join(bad)])

	# ── ② 白名单只减不增 ──
	print("── ② 白名单纪律 ──")
	_ok("② 白名单仍是 %d 项（只能减不能加）" % ALLOWED_MISSING.size(),
		ALLOWED_MISSING.size() <= 2,
		"白名单变长了 —— 加豁免前先问「这个键随从真的不需要吗」")

	# ── ③ 技能龟能消耗与真龟一致（energy_cost 缺失的行为后果）──
	print("── ③ 放技花的龟能 == 真龟 ──")
	var nc := 0
	var mism: Array = []
	for mid in byid:
		var real2: Dictionary = _s._spawn._make_unit(str(mid), "left", c)
		for sk in (byid[mid] as Dictionary).get("active_skills", []):
			nc += 1
			var cr: float = _s._skill_cost(real2, str(sk))
			var cm: float = _s._skill_cost(byid[mid], str(sk))
			if not is_equal_approx(cr, cm):
				mism.append("%s/%s 真龟=%.1f 随从=%.1f" % [mid, str(sk), cr, cm])
	_ok("★分母⑤: 比了 %d 条「龟种×技能」的消耗" % nc, nc >= 15,
		"比得太少 ⇒ 随从没解出 active_skills")
	_ok("③ 消耗全部一致", mism.is_empty(), "不一致 %d 条: %s" % [mism.size(), ", ".join(mism)])

	# ── ④ 真跑每帧那段：穿过挡板后 skill_cd 被懒初始化填上 ──
	#    这条不是"没报错就算过"——它断言**冷却表真的被填了**，
	#    证明确实执行到了 `_tick_skill_cd` 里读 u["skill_cd"] 的那几行。
	print("── ④ 真跑 `_tick_skill_cd`（每帧对每个单位都会跑）──")
	var filled := 0
	var has_key := 0
	for mid in byid:
		var m2: Dictionary = byid[mid]
		# ★这里**绝不能**写 `m2["skill_cd"] = {}` —— 门禁自己喂上那个键，
		#   就把「缺键会崩」这条判据变成了恒真式（初版我就是这么写的，
		#   变异掉产品里那行「防崩」代码后 ④ 照样绿）。改成先断言它**自带**。
		if not m2.has("skill_cd"):
			continue
		has_key += 1
		(m2["skill_cd"] as Dictionary).clear()
		_s._tick_skill_cd(m2, 0.016)
		if not (m2["skill_cd"] as Dictionary).is_empty():
			filled += 1
	_ok("★分母⑥: %d/%d 个随从**自带** skill_cd（不是门禁喂的）" % [has_key, byid.size()],
		has_key == byid.size() and byid.size() > 0,
		"缺 skill_cd ⇒ 每帧 `_tick_skill_cd` 第一行就会崩")
	_ok("④ %d/%d 个随从跑完后冷却表被填上（真走到了读 skill_cd 那几行）" % [filled, byid.size()],
		filled == byid.size() and byid.size() > 0,
		"没填上 ⇒ 要么被挡板挡了、要么 active_skills 是空的")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
