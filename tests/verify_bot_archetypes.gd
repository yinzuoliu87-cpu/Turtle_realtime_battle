extends Node
## verify_bot_archetypes.gd — 14 个机器人流派【真的按各自规则出价】(2026-09-02)
##
## 由来(用户 2026-09-02):「我需要你优化ai策略，别弄蠢ai」「只有6种流派也少了啊」。
## 旧实现四种策略**只作用在「货架 10 格按什么顺序买」一个决策点**, 另外四个
## (留多少币 / 买几次经验 / 刷几次 / 装备先给谁)**全是写死的** ——
## 所以"速升级流""滚雪球流""疯狂刷新流""小将优先流"在旧实现里**根本不可能存在**。
##
## ★这里验的是**纯函数 `CohortSim.buy_score`** —— 不跑整场模拟(几十分钟且带 RNG)。
##   判据是**排序关系**不是绝对分值: 改权重数值不该让门禁红, 改【偏好顺序】才该红。
##   (与 verify_bot_buy_synergy 同一条口径)
##
## ★★每条断言都问同一个问题: **这个流派会不会把"它该要的那件"排在"它不该要的那件"前面。**
##   若某流派的权重全被清零(反向验证), 它的偏好就消失 ⇒ 该条必红。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_bot_archetypes.tscn

const Cohort := preload("res://tests/_cohort.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 从真实装备表里挑一件指定费用/类型的 —— **不自己编 edef**,
## 编出来的假件会让门禁测的是我的假数据而不是产品数据。
func _pick(cost: int, typ: String, exclude: Array) -> Dictionary:
	for e in DataRegistry.phase2_equipment:
		var d: Dictionary = e
		var eid := str(d.get("id", ""))
		if exclude.has(eid):
			continue
		if int(d.get("cost", 0)) != cost:
			continue
		if typ != "" and str(Phase2Types.type_of(eid)) != typ:
			continue
		return d
	return {}


func _ready() -> void:
	await get_tree().process_frame
	if get_node_or_null("/root/DataRegistry") == null:
		print("  [FAIL] 缺 autoload DataRegistry"); get_tree().quit(1); return
	print("=== 机器人流派: 每个都按自己的规则出价 ===")

	# ── ⓪ 分母 ────────────────────────────────────────────────
	_ok("★分母: 流派表读得到且 ≥ 12 个(少了说明表没加载, 下面全是空检查)",
		Cohort.ARCHETYPES.size() >= 12, "实测 %d 个" % Cohort.ARCHETYPES.size())
	_ok("★分母: 装备表读得到(%d 件)" % DataRegistry.phase2_equipment.size(),
		DataRegistry.phase2_equipment.size() > 50)
	var hi: Dictionary = _pick(5, "", [])
	var lo: Dictionary = _pick(1, "", [])
	_ok("★分母: 取到了 5 费件与 1 费件(取不到 = 下面的费用断言恒真)",
		not hi.is_empty() and not lo.is_empty(),
		"5费=%s 1费=%s" % [str(hi.get("id", "无")), str(lo.get("id", "无"))])
	if hi.is_empty() or lo.is_empty():
		_done(); return

	# ── ① 高费流: 5 费 排在 1 费 前 ──────────────────────────
	var w_hi: Dictionary = Cohort.ARCHETYPES["hi_cost"]
	_ok("★★高费流: 5 费件出价 > 1 费件",
		Cohort.buy_score(hi, w_hi, {}, {}, []) > Cohort.buy_score(lo, w_hi, {}, {}, []),
		"5费 %.2f vs 1费 %.2f" % [Cohort.buy_score(hi, w_hi, {}, {}, []),
			Cohort.buy_score(lo, w_hi, {}, {}, [])])

	# ── ② 低费海: 反过来 ─────────────────────────────────────
	var w_lo: Dictionary = Cohort.ARCHETYPES["low_flood"]
	_ok("★★低费海: 1 费件出价 > 5 费件(与高费流【方向相反】—— 只验一边等于没验)",
		Cohort.buy_score(lo, w_lo, {}, {}, []) > Cohort.buy_score(hi, w_lo, {}, {}, []),
		"1费 %.2f vs 5费 %.2f" % [Cohort.buy_score(lo, w_lo, {}, {}, []),
			Cohort.buy_score(hi, w_lo, {}, {}, [])])

	# ── ③ 三合一流: 已有 2 张的同 id 最值钱 ──────────────────
	var w_st: Dictionary = Cohort.ARCHETYPES["star_rush"]
	var a: Dictionary = _pick(2, "", [])
	var b: Dictionary = _pick(2, "", [str(a.get("id", ""))])
	_ok("★分母: 取到两件不同的 2 费件(同费用 ⇒ 费用项不干扰这条)",
		not a.is_empty() and not b.is_empty() and str(a.get("id")) != str(b.get("id")),
		"%s / %s" % [str(a.get("id", "无")), str(b.get("id", "无"))])
	if not a.is_empty() and not b.is_empty():
		var own := {str(a.get("id", "")): 2}      # a 已有 2 张 → 第 3 张直接成 ★3
		_ok("★★三合一流: 已有 2 张的那件 出价 > 没有的那件",
			Cohort.buy_score(a, w_st, own, {}, []) > Cohort.buy_score(b, w_st, own, {}, []),
			"有2张 %.2f vs 没有 %.2f" % [Cohort.buy_score(a, w_st, own, {}, []),
				Cohort.buy_score(b, w_st, own, {}, [])])
		## ★★★这条是「三合一 与 羁绊 冲突」那条轴的判据:
		##   羁绊按 id 去重 ⇒ 重复件对羁绊零贡献 ⇒ 单线流【不该】想要它
		var w_ln: Dictionary = Cohort.ARCHETYPES["line_top"]
		var ta := str(Phase2Types.type_of(str(a.get("id", ""))))
		_ok("★★★单线顶档流对【已有的重复件】不加分(羁绊按 id 去重, 重复件零贡献)",
			Cohort.buy_score(a, w_ln, own, {}, [ta]) <= Cohort.buy_score(b, w_ln, own, {}, [ta]) + 0.001,
			"重复件 %.2f vs 新件 %.2f (锁定类型 %s)"
			% [Cohort.buy_score(a, w_ln, own, {}, [ta]),
				Cohort.buy_score(b, w_ln, own, {}, [ta]), ta])

	# ── ④ 单线顶档: 锁定类型里的新件 排在 别类型前 ───────────
	var w_line: Dictionary = Cohort.ARCHETYPES["line_top"]
	var sword: Dictionary = _pick(2, "剑", [])
	var other: Dictionary = _pick(2, "盾", [])
	_ok("★分母: 取到同费用的【剑】与【盾】各一件",
		not sword.is_empty() and not other.is_empty(),
		"剑=%s 盾=%s" % [str(sword.get("id", "无")), str(other.get("id", "无"))])
	if not sword.is_empty() and not other.is_empty():
		_ok("★★单线顶档(锁剑): 剑 出价 > 盾",
			Cohort.buy_score(sword, w_line, {}, {}, ["剑"])
			> Cohort.buy_score(other, w_line, {}, {}, ["剑"]),
			"剑 %.2f vs 盾 %.2f" % [Cohort.buy_score(sword, w_line, {}, {}, ["剑"]),
				Cohort.buy_score(other, w_line, {}, {}, ["剑"])])
		_ok("★★★锁定换成【盾】时结论反过来(否则只是'剑天生分高', 不是'锁定生效')",
			Cohort.buy_score(other, w_line, {}, {}, ["盾"])
			> Cohort.buy_score(sword, w_line, {}, {}, ["盾"]))

	# ── ⑤ 多羁绊铺开: 离下一档【只差 1 件】的类型优先 ────────
	var w_wide: Dictionary = Cohort.ARCHETYPES["wide_syn"]
	if not sword.is_empty() and not other.is_empty():
		var tiers: Array = (Phase2Types.TYPES.get("剑", {}) as Dictionary).get("tiers", [])
		_ok("★分母: 剑的档位阈值读得到 = %s" % str(tiers), not tiers.is_empty())
		if not tiers.is_empty():
			## 剑已有 (首档−1) 件 ⇒ 再买 1 件就跨档; 盾一件没有 ⇒ 还差整档
			var tc := {"剑": int(tiers[0]) - 1}
			_ok("★★多羁绊铺开: 【差 1 件就跨档】的剑 出价 > 一件都没有的盾",
				Cohort.buy_score(sword, w_wide, {}, tc, [])
				> Cohort.buy_score(other, w_wide, {}, tc, []),
				"剑(差1) %.2f vs 盾(差满档) %.2f"
				% [Cohort.buy_score(sword, w_wide, {}, tc, []),
					Cohort.buy_score(other, w_wide, {}, tc, [])])

	# ── ⑥ 随机对照组: 打分必须【全平】(它是所有分布断言的分母) ─
	var w_rnd: Dictionary = Cohort.ARCHETYPES["random"]
	_ok("★★★随机对照组: 对 5 费与 1 费出价【相同】(不平就不是对照组, 后面的分布对比全废)",
		absf(Cohort.buy_score(hi, w_rnd, {}, {}, []) - Cohort.buy_score(lo, w_rnd, {}, {}, [])) < 1e-6,
		"5费 %.4f vs 1费 %.4f" % [Cohort.buy_score(hi, w_rnd, {}, {}, []),
			Cohort.buy_score(lo, w_rnd, {}, {}, [])])

	# ── ⑦ 经济类流派: 三个写死的口子真的被向量接管了 ─────────
	##   这三项过去写死 ⇒ 这些流派在旧实现里不可能存在。判据落在**流派表本身给了不同的值**,
	##   而消费侧(_shop/_equip)读它们由 ⑧ 的源码守卫保证。
	var fast: Dictionary = Cohort.ARCHETYPES["fast_level"]
	var snow: Dictionary = Cohort.ARCHETYPES["snowball"]
	_ok("★★速升级流 与 滚雪球流 的【买经验上限】方向相反",
		int(fast.get("xp", -1)) > int(snow.get("xp", 99)),
		"速升级 %s / 滚雪球 %s" % [str(fast.get("xp")), str(snow.get("xp"))])
	var mad: Dictionary = Cohort.ARCHETYPES["reroll_mad"]
	var norr: Dictionary = Cohort.ARCHETYPES["no_reroll"]
	_ok("★★疯狂刷新 与 不刷新 的【刷新上限】方向相反",
		int(mad.get("refresh", -1)) > int(norr.get("refresh", 99)),
		"疯狂 %s / 不刷 %s" % [str(mad.get("refresh")), str(norr.get("refresh"))])
	_ok("★★统领梭哈 与 小将优先 的 minion_first 相反",
		int((Cohort.ARCHETYPES["leader_all"] as Dictionary).get("minion_first", -1))
		!= int((Cohort.ARCHETYPES["minion_up"] as Dictionary).get("minion_first", -1)))

	# ── ⑧ 源码守卫: 五个决策点【真的在读向量】 ───────────────
	##   ★没有这条的话, 上面全是"表里写了不同的数", 而消费侧可能照样读写死常量
	##   (memory: 写了没人读 —— 今天已经栽过两次)。
	var src: String = FileAccess.get_file_as_string("res://tests/_cohort.gd")
	_ok("★分母: 读得到 _cohort.gd 源码(%d 字)" % src.length(), src.length() > 5000)
	for pair in [["买什么", "buy_score(offer[a], w, own, tcount, lines)"],
			["留多少币", "w_s.get(\"reserve\""],
			["买几次经验", "w_s.get(\"xp\""],
			["刷几次", "w_s.get(\"refresh\""],
			["主动刷", "w_s.get(\"eager\""],
			["装备先给谁", "get(\"minion_first\", 0)"]]:
		_ok("★★决策点【%s】真的读了策略向量" % str(pair[0]), src.contains(str(pair[1])),
			"源码里找不到 %s —— 表里写了没人读" % str(pair[1]))

	_done()


func _done() -> void:
	print("")
	if _n < 20:
		print("  [FAIL] ★分母: 断言只有 %d 条(<20) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 机器人流派(%d 条)" % _n if _fail == 0 else "FAIL x%d (共 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
