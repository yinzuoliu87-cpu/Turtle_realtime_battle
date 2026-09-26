extends Node
## verify_determinism_bisect.gd — ★**一次性测量门禁**：把跨平台分叉定位到【第几步·哪只单位·哪个字段】
##
## ══════════════════════════════════════════════════════════════════════
##  测到哪一步了（每一轮都是实测，不是推测）
## ══════════════════════════════════════════════════════════════════════
## 【第 1 轮】`verify_determinism_cross` 在 CI(ubuntu/glibc) 对本地(Windows/MSVC libm) 的金标：
##   **9 个场景里 8 个逐位相同**，只有「③ 3v3 满装备(每只 3 件 3★)」不同
##   （实得 4d3cb4c2376b18ac / 金标 e2e0a124d2326863）。
##
## 【第 2 轮】把 ③ 二分成 L1(一次只给一只龟她那 3 件) + L2(18 件逐件)，24 条：
##   **23 条全一致**，只有 `L1·只给 basic 带 p2eq_032,p2eq_058,p2eq_073` 分叉
##   （实得 89745f823dedc96b / 金标 cfe984967d6995d2）。
##   ⇒ **单件都不飘，三件同时在场才飘 ⇒ 组合效应。**
##   那三件是: 032 唤灵骨符(开战召一只骷髅)、058 远古炮台(登场召一座炮台)、
##            073 藤蔓弓弦(每次普攻向**随机敌人**射一箭，箭单独判暴击)。
##   两件**往场上加单位**，一件每次普攻**抽随机目标** —— 组合起来单位更多、随机抽取更频繁。
##
## 【第 3 轮 = 本轮】不再猜机制。只跑那一个分叉场景，**逐步打前缀摘要**：
##   第 i 步的摘要 = sha256(第 0..i 步的指纹拼起来)。
##   ⇒ 本地日志与 CI 日志逐行比，**第一处不同的那一行就是首个分叉步**。
##   （memory `fb-probe-before-claiming-rootcause`：推理出的根因不算根因。）
##   下一轮再把那一步附近的**完整指纹**打出来，就能指到具体单位与字段。
##
## ★这一轮 CI **照样是故意红的**（金标只有一条、且刻意填一个不可能相等的值），
##   红是为了让失败日志推到 `ci-logs` 分支 —— 那是拿到 Linux 侧数据的唯一通路
##   （探针 `_probe_*.gd` 不会被 run-tests.sh 自动发现，CI 不跑它）。
##   测完连金标一起删。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_determinism_bisect.tscn --quit-after 40000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")

const FRAMES := 600
## ★只跑分叉的那一只(basic 带三件)，其余五只全裸 —— 与第 2 轮 L1 那一条**逐字相同**的摆位。
const WHO := "basic"

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## ★与 `verify_determinism_cross._fp()` 逐字同一个口径。
func _fp(scene) -> String:
	var parts: Array = []
	var i := 0
	for u in scene._units:
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.1f:%.2f:%d:%.4f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x),
			float((u.get("pos", Vector2()) as Vector2).y),
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)),
			float(u.get("gold", 0.0)),
			float(u.get("energy", 0.0)),
			int(u.get("prism_color", -1)),
			float(u.get("crit", 0.0))])
		i += 1
	return "|".join(parts)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	## 摆位从共用表里取 —— 不手抄(抄了就可能量的不是同一局)
	var base: Array = []
	for sc in SC.all():
		if str((sc as Dictionary)["tag"]).begins_with("③"):
			base = (sc as Dictionary)["pairs"] as Array
			break
	_ok("★分母: 从共用表取到场景 ③ 的 6 只单位", base.size() == 6, "%d 只" % base.size())
	if base.size() != 6:
		get_tree().quit(1)
		return

	var pairs: Array = []
	var eqs_of_who: Array = []
	for p0 in base:
		var p: Array = (p0 as Array).duplicate(true)
		if str(p[0]) == WHO:
			eqs_of_who = (p[4] as Array).duplicate()
		else:
			p[4] = []
		pairs.append(p)
	_ok("★分母: %s 身上确实还带着那 3 件(%s)" % [WHO, ",".join(PackedStringArray(eqs_of_who))],
		eqs_of_who.size() == 3, str(eqs_of_who))

	RB.DEBUG_EDIT = true
	OS.set_environment("TURTLE_SEED", "424242")
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p2 in pairs:
		var u: Dictionary = s._debug._edit_place_unit(str(p2[0]), str(p2[1]),
			Vector2(float(p2[2]), float(p2[3])))
		if (p2[4] as Array).size() > 0:
			var el: Array = []
			for e in (p2[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
	s._debug._edit_start_battle()

	## ★逐步前缀摘要: 第 i 行 = sha256(第 0..i 步的指纹)。
	##   本地日志与 CI 日志**逐行比**, 第一处不同的那一行就是首个分叉步。
	##   为什么是前缀而不是每步单独摘要: 单步摘要在分叉之后每一步都不同, 噪声一大片;
	##   前缀摘要在分叉之前逐行相同、分叉之后全部不同 ⇒ 分界线只有一条, 一眼看得出。
	var lines: Array = []
	var uniq := {}
	var n_units_at := {}
	var raw0: Array = []
	for i in range(FRAMES):
		await get_tree().process_frame
		var f := _fp(s)
		uniq[f] = true
		## ★指纹先存下来, 前缀摘要在循环外连着算一遍(见下面) ——
		##   在循环里算会变成 O(n²) 次拼接, 而结果一模一样。
		lines.append(f)
		n_units_at[i] = s._units.size()
		## ★第 0 步再多打几个**不在指纹里**的原始属性 —— 指纹只有 9 个字段,
		##   而分叉可能在 maxHp/攻/攻速/护甲 上(它们会通过伤害间接进指纹)。
		if i == 0:
			for u3 in s._units:
				raw0.append("RAW %-14s %-6s maxHp=%.4f atk=%.4f aspd=%.4f armor=%.4f mr=%.4f rng=%.4f crit=%.4f hp=%.4f" % [
					str(u3.get("id", "?")), str(u3.get("side", "?")),
					float(u3.get("maxHp", 0.0)), float(u3.get("atk", 0.0)),
					float(u3.get("atk_interval", 0.0)), float(u3.get("armor", 0.0)),
					float(u3.get("mr", 0.0)), float(u3.get("range", 0.0)),
					float(u3.get("crit", 0.0)), float(u3.get("hp", 0.0))])

	var taken := 0.0
	for u2 in s._units:
		taken += float(u2.get("_st_taken", 0.0))
	var n_units: int = s._units.size()
	s.queue_free()
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")

	_ok("★分母: 这一局真的在推进(不同指纹 %d 个 > 1, 累计承伤 %.0f > 0)"
		% [uniq.size(), taken], uniq.size() > 1 and taken > 0.0)
	_ok("★分母: 场上确实多出了召唤物(末态 %d 只 > 6)" % n_units, n_units > 6, "%d 只" % n_units)

	## ★★★第 4 轮: 第 3 轮实测**首个分叉步 = 0** —— 第一步就不一样, 所以不是浮点累积漂移,
	##   而是**初始状态**就不同(两边都是 8 只单位, 召唤物都在场)。
	##   ⇒ 本轮只打第 0~2 步的**完整指纹**逐段, 一眼看出是哪只单位的哪个字段。
	## ⚠ CI 的失败日志会被**截断**(第 3 轮 600 行只回来 389 行) ⇒ 本轮**只打少量行**。
	print("")
	print("── 第 0 步的原始属性(不在指纹里的那些) ──")
	for r0 in raw0:
		print(str(r0))
	print("")
	## ★★★第 4 轮(按【步号】重新对齐后)实测: **首个分叉步 = 271**, 前 270 步逐位相同。
	##   ⚠ 第 3 轮我报的"第 0 步就分叉"是**我比错了**: CI 的失败日志从后面截断
	##   (600 行只回来 389 行, 步号 211..599), 而我按**行号**对齐 ⇒ 拿本地第 0 步
	##   比了 CI 的第 211 步。判据没错, 对齐错了。⇒ 改成按步号取交集再比。
	## 271 步 ÷ 60 ≈ 4.5 游戏秒。本轮打第 269~272 步的完整指纹, 指到具体单位与字段。
	print("── 第 269~272 步的完整指纹, 逐段一行 ──")
	for i2 in range(269, mini(273, lines.size())):
		var segs: PackedStringArray = str(lines[i2]).split("|")
		for k in range(segs.size()):
			print("SEG %d %02d %s" % [i2, k, segs[k]])

	## ★故意判红: 红才会把日志推到 ci-logs, 那是拿 Linux 侧数据的唯一通路。
	_ok("★★★(测量用·故意红) 上面那 %d 行 PFX 就是本轮要的数据" % lines.size(), false,
		"本地与 CI 的 PFX 逐行比, 第一处不同的那一行 = 首个分叉步")

	print("")
	print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1)
