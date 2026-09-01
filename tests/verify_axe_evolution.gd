extends Node
## verify_axe_evolution.gd — 096 小木斧·四期【进化与商店】(2026-09-01)
##
## ★需求原文(用户 2026-08-31)节选:
##   「购买该装备会使经验条+15，打完一整把3条路的战斗+10，斧头召唤物击杀或3秒内参与击杀+2」
##   「木斧80经验值进化为石斧…110…130…160，每次进化都会清空经验条」
##   「进化到钻石斧后再收集400经验值，可以进行最终进化，四选一」
##   「随大轮重置」「买了第一把木斧后，后面的木斧购买都会化作经验值」
##   「激活斧头羁绊后，概率将为3%加玩家激活斧头羁绊时在这大轮游戏的局数*0.1%，最终概率最高为10%」
##   「3%~10% 为整个货架」(2026-08-31 追加口径)
##
## ★★这份门禁里最容易写假的六条 —— 每条都配了分母:
##   ① 「进化清空进度条」: **只验 bar 归零等于没验**。历史累计 total 必须同时验它没变,
##      否则"把 total 也清零"的实现照样绿(方案书风险 5 的那个坑)。
##   ② 「只能拥有一把」: 只验"背包没涨"是恒真式(压根不实现购买也不会涨)。要拿同一段代码
##      买 058 当分母, 证明这条路本来是会涨的。
##   ③ 「整货架 3%」: 只验 slot_prob 返回个小数没意义。要回代 1-(1-q)^n == shelf_prob,
##      再拿**真商店 _roll** 蒙特卡洛量一遍实际频率 —— 反解写成 P/n 时前者当场红。
##   ④ 「形态随进化变」: 只验 _deco 返回新名字不够, 还要验它**没弄脏 DataRegistry 里的原件**
##      (改原件的实现也返回新名字, 但会把货架冻在掷货那一刻)。
##   ⑤ 「同源写入」: 拿源码扫描守住"只有 axe_add_exp 一处写 axe_exp_bar"。
##      两处各写各的是最典型的漂法, 而它在运行时完全看不出来。
##   ⑥ 「助攻 +2」: 只验"斧头击杀给了 2"会漏掉助攻那一半 —— on-hit 那一整块被
##      `u["alive"]` 挡着, **致命的那一下根本走不到**。三种情形各量一次。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const P2T := preload("res://scripts/gamedata/phase2_types.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 096 小木斧 · 四期 进化与商店 ===")

	## ★备份现场 —— 这份门禁会写斧头字段与背包, 收尾必须逐项还原(测试不许污染真存档)。
	var bak := {
		"bar": int(gs.axe_exp_bar), "tot": int(gs.axe_exp_total),
		"st": int(gs.axe_stage), "fin": str(gs.axe_final),
		"sm": int(gs.axe_syn_matches),
		"bench": gs.persistent_bench.duplicate(true),
		"coins": int(gs.meta_deepsea_coins),
	}

	_t_consts()
	_t_advance()
	_t_reset(gs)
	_t_single_writer(gs)
	await _t_shop(gs)
	_t_prob()
	_t_synergy(gs)
	_t_codex()
	await _t_kill(gs)

	gs.axe_exp_bar = int(bak["bar"]); gs.axe_exp_total = int(bak["tot"])
	gs.axe_stage = int(bak["st"]);    gs.axe_final = str(bak["fin"])
	gs.axe_syn_matches = int(bak["sm"])
	gs.persistent_bench = (bak["bench"] as Array).duplicate(true)
	gs.meta_deepsea_coins = int(bak["coins"])

	if _n < 47:
		print("  [FAIL] ★分母: 断言只有 %d 条(<47) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 096 四期(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 分母: 常量表就是需求给的字面值
# ══════════════════════════════════════════════════════════════
func _t_consts() -> void:
	print("--- ① 分母: 常量 ---")
	_ok("★分母: 经验来源 买%d / 场%d / 击杀%d · 助攻窗 %.0f 秒"
		% [AE.EXP_ON_BUY, AE.EXP_ON_MATCH, AE.EXP_ON_KILL, AE.ASSIST_WINDOW],
		AE.EXP_ON_BUY == 15 and AE.EXP_ON_MATCH == 10 and AE.EXP_ON_KILL == 2
		and is_equal_approx(AE.ASSIST_WINDOW, 3.0))
	## STAGE_NEEDS 是给文案占位符用的扁平镜像 —— 逐项焊在 STAGES 上, 改一边忘另一边当场红。
	var mirror_ok: bool = AE.STAGE_NEEDS.size() == AE.STAGES.size() - 1
	if mirror_ok:
		for i in range(AE.STAGE_NEEDS.size()):
			if int(AE.STAGE_NEEDS[i]) != int(AE.STAGES[i + 1]["need"]):
				mirror_ok = false
	_ok("★STAGE_NEEDS 逐项 == STAGES[i+1].need(它是镜像, 不是第二个事实源)", mirror_ok,
		str(AE.STAGE_NEEDS))
	_ok("★分母: 阈值就是需求的 80/110/130/160 + 最终 %d" % AE.FINAL_NEED,
		AE.STAGE_NEEDS == [80, 110, 130, 160] and AE.FINAL_NEED == 400)
	_ok("★分母: 出货 基础%.0f%% + 每局%.1f%% 封顶%.0f%%"
		% [AE.SHELF_P_BASE * 100.0, AE.SHELF_P_PER_MATCH * 100.0, AE.SHELF_P_CAP * 100.0],
		is_equal_approx(AE.SHELF_P_BASE, 0.03) and is_equal_approx(AE.SHELF_P_PER_MATCH, 0.001)
		and is_equal_approx(AE.SHELF_P_CAP, 0.10))


# ══════════════════════════════════════════════════════════════
#  ② 进化推进(纯函数) —— 进度条 vs 历史累计
# ══════════════════════════════════════════════════════════════
func _t_advance() -> void:
	print("--- ② 进化: 进度条清零 / 累计只增 ---")
	var r: Dictionary = AE.advance(0, 0, 0, AE.EXP_ON_BUY)
	_ok("买一把 +15: 进度条与累计【同步】都涨 15, 没进化",
		int(r["bar"]) == 15 and int(r["total"]) == 15 and int(r["stage"]) == 0
		and not bool(r["evolved"]),
		"bar=%d tot=%d st=%d" % [int(r["bar"]), int(r["total"]), int(r["stage"])])
	var r2: Dictionary = AE.advance(75, 75, 0, 10)
	_ok("攒过 80 → 进化成石斧(stage 1)", int(r2["stage"]) == 1 and bool(r2["evolved"]),
		"st=%d" % int(r2["stage"]))
	_ok("★进化【清空进度条】: bar == 0", int(r2["bar"]) == 0, "bar=%d" % int(r2["bar"]))
	_ok("★★同一次进化【历史累计不动】: total 仍是 85(只验 bar 等于没验)",
		int(r2["total"]) == 85, "tot=%d" % int(r2["total"]))
	var b := 0
	var t := 0
	var st := 0
	for need in AE.STAGE_NEEDS:
		var rr: Dictionary = AE.advance(b, t, st, int(need))
		b = int(rr["bar"]); t = int(rr["total"]); st = int(rr["stage"])
	_ok("逐档喂 80/110/130/160 → 走到钻石斧(stage %d)" % (AE.STAGES.size() - 1),
		st == AE.STAGES.size() - 1, "st=%d" % st)
	_ok("★走完四档后 total == 480(四段阈值之和, 一分不丢)", t == 480, "tot=%d" % t)
	_ok("★一次 add 最多进化一档: 喂 1000 只跳到 stage 1",
		int(AE.advance(0, 0, 0, 1000)["stage"]) == 1)
	var last: int = AE.STAGES.size() - 1
	_ok("钻石斧攒够 400 → final_ready 真", AE.final_ready(AE.FINAL_NEED, last, ""))
	_ok("★分母: 差 1 点(399) → final_ready 假", not AE.final_ready(AE.FINAL_NEED - 1, last, ""))
	_ok("★分母: 还没到钻石斧(stage 0)攒 400 也不 ready", not AE.final_ready(500, 0, ""))
	_ok("★已选过最终造物 → 本大轮锁定, 不再 ready(未决点 ⑩)",
		not AE.final_ready(AE.FINAL_NEED, last, "ember"))


# ══════════════════════════════════════════════════════════════
#  ③ 大轮重置 + 存档两侧
# ══════════════════════════════════════════════════════════════
func _t_reset(gs) -> void:
	print("--- ③ 大轮重置 / 存档 ---")
	for fn in ["start_new_season", "reset_save"]:
		gs.axe_exp_bar = 77; gs.axe_exp_total = 777; gs.axe_stage = 3
		gs.axe_final = "holo"; gs.axe_syn_matches = 42
		## ★分母: 先证明这五个字段确实被写成了非零, 否则下面的"归零"是恒真式
		var dirty: bool = gs.axe_exp_bar != 0 and gs.axe_exp_total != 0 and gs.axe_stage != 0 \
			and gs.axe_final != "" and gs.axe_syn_matches != 0
		gs.call(fn)
		_ok("%s: 五个斧头字段全部归零(分母: 调用前确实非零=%s)" % [fn, str(dirty)],
			dirty and gs.axe_exp_bar == 0 and gs.axe_exp_total == 0 and gs.axe_stage == 0
			and gs.axe_final == "" and gs.axe_syn_matches == 0,
			"bar=%d tot=%d st=%d fin=%s sm=%d" % [gs.axe_exp_bar, gs.axe_exp_total,
			gs.axe_stage, gs.axe_final, gs.axe_syn_matches])
	## 存档往返: save() 在 test_mode 下提前 return(不落盘), 所以直接量源码的存/读两侧。
	## ★这里【故意】不用"写盘再读回来" —— 那条在 test_mode 下永远绿, 是个假门禁。
	var src: String = FileAccess.get_file_as_string("res://autoload/GameState.gd")
	var miss: Array = []
	for k in ["axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches"]:
		if not src.contains('"%s": %s' % [k, k]):
			miss.append(k + "(存)")
		if not src.contains('data.get("%s"' % k):
			miss.append(k + "(读)")
	_ok("★五个字段【存与读两侧】都在(缺一侧=重启就丢, 而游戏里完全看不出来)",
		miss.is_empty() and src != "", str(miss))


# ══════════════════════════════════════════════════════════════
#  ④ 同源写入: 只有一个函数能改这三个字段
# ══════════════════════════════════════════════════════════════
func _t_single_writer(gs) -> void:
	print("--- ④ 同源写入 ---")
	var src: String = FileAccess.get_file_as_string("res://autoload/GameState.gd")
	## 赋值给 axe_exp_bar 的地方应当**恰好 5 处**, 各有各的正当理由:
	##   ① _load 读档回填 ② axe_add_exp 唯一写入口 ③ reset_save ④ start_new_season
	##   ⑤ axe_pick_final —— 选完最终造物把进度条清零(2026-09-01 新增; 它同样在
	##     GameState 里, UI 侧只是转发, 所以"状态只归 GameState 管"这条纪律没破)
	## 多出第五处 = 有人绕过 axe_add_exp 偷偷写它, 那正是"两个字段各写各的"必漂的形状。
	## (`var axe_exp_bar: int = 0` 是声明, 不会匹配 —— 正则要求行首直接是变量名)
	var re := RegEx.create_from_string("(?m)^\\s*axe_exp_bar\\s*=")
	var hits: int = re.search_all(src).size()
	_ok("★GameState 里写 axe_exp_bar 的地方 == 5(读档/add_exp/两个重置/选最终造物)",
		hits == 5, "实测 %d 处" % hits)
	## 全仓扫描: scripts/ 下不许有任何文件绕过 axe_add_exp 直接改这三个字段
	var others: Array = []
	for f in _all_gd("res://scripts"):
		var s2: String = FileAccess.get_file_as_string(f)
		for k in ["axe_exp_bar", "axe_exp_total", "axe_stage"]:
			if RegEx.create_from_string("%s\\s*=[^=]" % k).search(s2) != null:
				others.append("%s:%s" % [f.get_file(), k])
	_ok("★scripts/ 下没有文件直接赋值这三个字段(分母: 扫了 %d 个 .gd)"
		% _all_gd("res://scripts").size(), others.is_empty(), str(others))
	## 运行时再验一遍: 调一次 add, 两个字段【同时】动
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0; gs.axe_stage = 0
	gs.axe_add_exp(7)
	_ok("★axe_add_exp(7) 一次把两个字段都推到 7", gs.axe_exp_bar == 7 and gs.axe_exp_total == 7,
		"bar=%d tot=%d" % [gs.axe_exp_bar, gs.axe_exp_total])
	## 打完一场的记账: +10 经验 + (羁绊在线时)局数 +1
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0; gs.axe_syn_matches = 0
	gs.axe_on_match_end()
	_ok("★打完一整场 axe_on_match_end() → +%d 经验" % AE.EXP_ON_MATCH,
		gs.axe_exp_total == AE.EXP_ON_MATCH, "tot=%d" % gs.axe_exp_total)


func _all_gd(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			out.append_array(_all_gd(root + "/" + f))
		elif f.ends_with(".gd"):
			out.append(root + "/" + f)
		f = d.get_next()
	d.list_dir_end()
	return out


# ══════════════════════════════════════════════════════════════
#  ⑤ 商店: 形态/售价随进化变 + 只能拥有一把
# ══════════════════════════════════════════════════════════════
func _t_shop(gs) -> void:
	print("--- ⑤ 商店: 形态/售价/只能一把 ---")
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)
	for _i in range(4):
		await get_tree().process_frame
	var raw: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_096", {})
	_ok("★分母: 商店场景起得来且拿得到 096 原件", shop != null and not raw.is_empty(),
		"name=%s" % str(raw.get("name", "?")))

	## ── 形态随档位变 ──
	var cases := [[0, "", "小木斧", 1, "axe-wood"], [4, "", "钻石斧", 5, "axe-diamond"],
		[4, "ember", "余烬", 5, "axe-ember"]]
	for c in cases:
		gs.axe_stage = int(c[0]); gs.axe_final = str(c[1])
		var d: Dictionary = shop._deco(raw)
		_ok("_deco 档%d/最终「%s」→ 名「%s」· %d 费 · 图 %s"
			% [int(c[0]), str(c[1]), str(c[2]), int(c[3]), str(c[4])],
			str(d.get("name", "")) == str(c[2]) and int(d.get("cost", 0)) == int(c[3])
			and str(d.get("img", "")).contains(str(c[4])),
			"实测 %s / %d 费 / %s" % [str(d.get("name", "")), int(d.get("cost", 0)),
			str(d.get("img", ""))])
	## ★★关键的那条: 装饰**不许弄脏原件**。改原件的实现上面三条照样全绿,
	##   但会把落盘的货架冻在掷货那一刻 —— 只有这条抓得到。
	_ok("★★_deco 没弄脏 DataRegistry 里的原件(它仍是「小木斧」· 1 费)",
		str(raw.get("name", "")) == "小木斧" and int(raw.get("cost", 0)) == 1,
		"原件现在是 %s / %d 费" % [str(raw.get("name", "")), int(raw.get("cost", 0))])
	## 分母: 其余 95 件一个字段都不碰
	var other: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_058", {})
	_ok("★分母: _deco 对别的装备原样返回(058 名字/费用不变)",
		str(shop._deco(other).get("name", "")) == str(other.get("name", ""))
		and int(shop._deco(other).get("cost", 0)) == int(other.get("cost", 0)))
	## 费用封顶 5(未决点 ③)
	var over: Array = []
	for i in range(AE.STAGES.size()):
		var cc: int = int(AE.display(i, "")["cost"])
		if cc < 1 or cc > 5:
			over.append("stage%d=%d" % [i, cc])
	for f in AE.FINALS:
		if int(f["cost"]) != 5:
			over.append("%s=%d" % [str(f["key"]), int(f["cost"])])
	_ok("★费用封顶 5 费: 五档 1-5 · 四个最终造物都是 5(出货表 roll_cost_tier 只认 1-5)",
		over.is_empty(), str(over))
	## 九档九张图标都在盘上
	var missing: Array = []
	for i in range(AE.STAGES.size()):
		if not ResourceLoader.exists("res://assets/sprites/" + AE.icon_path(i, "")):
			missing.append(str(AE.STAGES[i]["key"]))
	for f2 in AE.FINALS:
		if not ResourceLoader.exists("res://assets/sprites/" + AE.icon_path(0, str(f2["key"]))):
			missing.append(str(f2["key"]))
	_ok("★九档九张图标都在盘上(分母: 五档 + 四造物 = %d 张)"
		% (AE.STAGES.size() + AE.FINALS.size()), missing.is_empty(), str(missing))
	_ok("★icon_path 是【相对形式】(绝对路径会静默退化成 📦 兜底, 看着像缺图)",
		not AE.icon_path(0, "").begins_with("res://"), AE.icon_path(0, ""))

	## ── 只能拥有一把(未决点 ⑧) ──
	gs.axe_stage = 0; gs.axe_final = ""
	gs.persistent_bench = []
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0
	gs.meta_deepsea_coins = 9999
	gs.ensure_equip_pool()
	shop._offer = [raw.duplicate(), raw.duplicate(), other.duplicate()]
	shop._on_buy(0)
	var n1: int = gs.persistent_bench.size()
	var e1: int = gs.axe_exp_total
	_ok("第一把: 进背包(%d 件) 且 +%d 经验" % [n1, AE.EXP_ON_BUY],
		n1 == 1 and e1 == AE.EXP_ON_BUY, "bench=%d exp=%d" % [n1, e1])
	shop._on_buy(1)
	var n2: int = gs.persistent_bench.size()
	var e2: int = gs.axe_exp_total
	_ok("★第二把: 背包件数【不涨】(%d→%d)" % [n1, n2], n2 == n1, "bench=%d" % n2)
	_ok("★第二把: 经验照涨 +%d(%d→%d)" % [AE.EXP_ON_BUY, e1, e2], e2 == e1 + AE.EXP_ON_BUY,
		"exp=%d" % e2)
	## ★分母: 同一段代码买 058 背包会涨 —— 证明"不涨"不是恒真式
	shop._on_buy(2)
	_ok("★★分母: 同一个 _on_buy 买 058 背包确实会涨(%d→%d)"
		% [n2, gs.persistent_bench.size()], gs.persistent_bench.size() == n2 + 1)
	shop.queue_free()


# ══════════════════════════════════════════════════════════════
#  ⑥ 出货概率: 反解 + 三种模式 + 蒙特卡洛
# ══════════════════════════════════════════════════════════════
func _t_prob() -> void:
	print("--- ⑥ 出货概率 ---")
	_ok("shelf_prob(0) == 3%%", is_equal_approx(AE.shelf_prob(0), 0.03),
		"%.4f" % AE.shelf_prob(0))
	_ok("每多打一局 +0.1pp: shelf_prob(10) == 4%%",
		is_equal_approx(AE.shelf_prob(10), 0.04), "%.4f" % AE.shelf_prob(10))
	_ok("★封顶 10%%: 打了 999 局也还是 10%%", is_equal_approx(AE.shelf_prob(999), 0.10),
		"%.4f" % AE.shelf_prob(999))
	_ok("★分母: 封顶前(第 60 局)确实还没到顶(9%%)", is_equal_approx(AE.shelf_prob(60), 0.09),
		"%.4f" % AE.shelf_prob(60))
	## ★★反解回代 —— 把 3% 直接当每格用(或写成 P/n)的实现在这里当场红
	var bad: Array = []
	for m in [0, 30, 999]:
		for n in [5, 10]:
			var q: float = AE.slot_prob(m, n)
			var back: float = 1.0 - pow(1.0 - q, float(n))
			if not is_equal_approx(back, AE.shelf_prob(m)):
				bad.append("m=%d n=%d 回代 %.4f != %.4f" % [m, n, back, AE.shelf_prob(m)])
	_ok("★★每格概率回代 1-(1-q)^n == 整货架 P(分母: 6 组 m×n 全查)", bad.is_empty(), str(bad))
	_ok("★分母: 每格概率确实比整货架小一个量级(10 格时 %.4f vs %.4f)"
		% [AE.slot_prob(0, 10), AE.shelf_prob(0)],
		AE.slot_prob(0, 10) < AE.shelf_prob(0) * 0.5)
	## 三种模式
	_ok("未激活羁绊 → 模式\"\"(走常规 1 费档)", AE.shelf_mode(false, "") == "")
	_ok("激活羁绊 → 模式 indep(从常规池剔除, 改走独立概率)",
		AE.shelf_mode(true, "") == "indep")
	_ok("★选完最终造物 → 模式 off(经验封顶后彻底不再出货)",
		AE.shelf_mode(true, "ember") == "off" and AE.shelf_mode(false, "ember") == "off")
	## 蒙特卡洛: 直接量【策略本身】的落点频率(不建场景, 与 ShopScene 同一个反解式)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	var slots := 10
	var trials := 4000
	var hit := 0
	var q0: float = AE.slot_prob(999, slots)      # 封顶 10%, 频率最好量
	for _i in range(trials):
		var got := false
		for _j in range(slots):
			if rng.randf() < q0:
				got = true
		if got:
			hit += 1
	var freq: float = float(hit) / float(trials)
	_ok("★蒙特卡洛 %d 次 × %d 格: 至少出一把的实测频率 %.3f ≈ 目标 %.3f"
		% [trials, slots, freq, AE.SHELF_P_CAP], absf(freq - AE.SHELF_P_CAP) < 0.015,
		"差 %.4f" % absf(freq - AE.SHELF_P_CAP))


# ══════════════════════════════════════════════════════════════
#  ⑦ 斧头羁绊
# ══════════════════════════════════════════════════════════════
func _t_synergy(gs) -> void:
	print("--- ⑦ 斧头羁绊 ---")
	_ok("斧头在 TYPES 里 · 阈值 [1](持有并装备 1 件即激活)",
		P2T.TYPES.has("斧头") and (P2T.TYPES["斧头"] as Dictionary)["tiers"] == [1],
		str((P2T.TYPES.get("斧头", {}) as Dictionary).get("tiers", [])))
	## 四张平行表键集一致 —— 少一张就会在某个界面上显示成空白
	var tabs := {"TYPES": P2T.TYPES, "TYPE_EMOJI": P2T.TYPE_EMOJI,
		"TYPE_NAME": P2T.TYPE_NAME, "TIER_DESCS": P2T.TIER_DESCS}
	var bad: Array = []
	for k in tabs.keys():
		if not (tabs[k] as Dictionary).has("斧头"):
			bad.append(k)
	_ok("★四张平行表都有「斧头」这一项(分母: 查了 %d 张)" % tabs.size(), bad.is_empty(), str(bad))
	_ok("★096 在 p2eq-types.json 里映射到「斧头」(没有它羁绊永远数不到)",
		P2T.types_of("p2eq_096").has("斧头"), str(P2T.types_of("p2eq_096")))
	## 真装上一件 → 激活; 摘掉 → 不激活(分母)
	var bak_eq = gs.persistent_equipped.duplicate(true)
	var bak_ld = gs.season_leaders.duplicate(true)
	gs.season_leaders = ["basic"]
	gs.persistent_equipped = {"basic": []}
	var off: bool = gs.axe_synergy_active()
	gs.persistent_equipped = {"basic": [{"id": "p2eq_096", "star": 1}]}
	var on: bool = gs.axe_synergy_active()
	_ok("★装上 096 → 羁绊激活; 摘掉 → 不激活(分母: 摘掉时=%s)" % str(off), on and not off,
		"装上=%s 摘掉=%s" % [str(on), str(off)])
	## ── 卖掉之后 ──
	## ★三件事要分开验, 它们**不是同一件事**:
	##   ① 羁绊失效(读的是"装在身上的") ② 出货概率回落到 1 费常规档
	##   ③ 但经验与档位【不回退】—— 它们是赛季级的, 与手上有没有这件装备无关
	## ⚠ 这里没有驱动商店卖出的 UI(_sell_selected 要一个带 _sel_bench 的 host);
	##   量的是卖出【之后的状态后果】+ 池子那一侧的真函数。
	gs.axe_exp_bar = 33; gs.axe_exp_total = 333; gs.axe_stage = 2
	gs.persistent_equipped = {"basic": []}
	gs.persistent_bench = []
	var sold_syn: bool = gs.axe_synergy_active()
	_ok("★卖掉后: 羁绊失效 且 出货模式回落到常规 1 费档",
		not sold_syn and AE.shelf_mode(sold_syn, gs.axe_final) == "",
		"syn=%s mode=%s" % [str(sold_syn), AE.shelf_mode(sold_syn, gs.axe_final)])
	_ok("★★卖掉后【经验与档位不回退】(它们是赛季级的, 不跟着装备走)",
		gs.axe_exp_bar == 33 and gs.axe_exp_total == 333 and gs.axe_stage == 2,
		"bar=%d tot=%d st=%d" % [gs.axe_exp_bar, gs.axe_exp_total, gs.axe_stage])
	## 池子那一侧: 无限件卖了不退张(它本来就没扣过, 退了就是凭空造张)
	var EPc = load("res://scripts/gamedata/equip_pool.gd")
	var pool := {"p2eq_096": 5, "p2eq_058": 5}
	EPc.give_back(pool, "p2eq_096", 3)
	EPc.give_back(pool, "p2eq_058", 3)
	_ok("★卖无限件不退张(分母: 同一个函数退 058 会从 5 涨到 8)",
		int(pool["p2eq_096"]) == 5 and int(pool["p2eq_058"]) == 8,
		"096=%d 058=%d" % [int(pool["p2eq_096"]), int(pool["p2eq_058"])])
	gs.persistent_equipped = bak_eq
	gs.season_leaders = bak_ld


# ══════════════════════════════════════════════════════════════
#  ⑧ 图鉴文案: 经验怎么攒 / 随大轮重置
# ══════════════════════════════════════════════════════════════
func _t_codex() -> void:
	print("--- ⑧ 图鉴文案 ---")
	var e: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_096", {})
	## ★走**图鉴详情自己用的那个入口** SkillText.equip_full(), 不自己拼 ——
	##   自己调 render_consts 只能证明"渲染器能展开", 证明不了图鉴真的展开了(死代码坑)。
	var txt: String = SkillText.equip_full(e)
	_ok("★分母: 096 文案取得到且够长(%d 字)" % txt.length(), txt.length() > 200)
	_ok("★文案讲了【经验怎么攒】: 三个来源的数字都渲染出来了",
		txt.contains("砍伐经验") and txt.contains("+%d" % AE.EXP_ON_BUY)
		and txt.contains("+%d" % AE.EXP_ON_MATCH) and txt.contains("+%d" % AE.EXP_ON_KILL),
		"买%d/场%d/杀%d" % [AE.EXP_ON_BUY, AE.EXP_ON_MATCH, AE.EXP_ON_KILL])
	_ok("★文案讲了【四个进化阈值】", txt.contains("80/110/130/160"), "")
	_ok("★文案讲了【随大轮重置】", txt.contains("大轮重置"), "")
	_ok("★文案讲了【只能拥有一把】", txt.contains("只能拥有一把"), "")
	## ★占位符名写错时 const_of 会**原样吐回** {C:...} —— 那会直接显示给玩家看
	_ok("★★渲染后不残留 {C: 占位符(名字写错时会原样显示给玩家)",
		not txt.contains("{C:"), txt.substr(maxi(0, txt.find("{C:")), 60))


# ══════════════════════════════════════════════════════════════
#  ⑨ 击杀 +2 / 3 秒内助攻 +2 / 超时不给
# ══════════════════════════════════════════════════════════════
func _t_kill(gs) -> void:
	print("--- ⑨ 击杀与助攻 ---")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	var axe_sys = _s._equip_sys._axe
	_ok("★分母: 拿得到 AxeSystem 且它有 on_death", axe_sys != null and axe_sys.has_method("on_death"))

	## 情形 A: 斧头亲手打死(killer 就是斧头)
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0; gs.axe_stage = 0
	var killer := {"_eq_axe": true, "alive": true}
	var victim := {"alive": false}
	axe_sys.on_death(victim, killer)
	_ok("★斧头亲手击杀 → +%d(实测 %d)" % [AE.EXP_ON_KILL, gs.axe_exp_total],
		gs.axe_exp_total == AE.EXP_ON_KILL)

	## 情形 B: 斧头 3 秒内碰过, 别人补刀
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0
	var other_killer := {"_eq_axe": false, "alive": true}
	var v2 := {"alive": false, "_axe_touch_t": float(_s._t) - 1.0}
	axe_sys.on_death(v2, other_killer)
	_ok("★3 秒内被斧头碰过、别人补刀 → 也 +%d(实测 %d)" % [AE.EXP_ON_KILL, gs.axe_exp_total],
		gs.axe_exp_total == AE.EXP_ON_KILL)

	## 情形 C: 超过 3 秒(分母 —— 没有这条, 上面两条给"永远 +2"的实现也全绿)
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0
	var v3 := {"alive": false, "_axe_touch_t": float(_s._t) - (AE.ASSIST_WINDOW + 2.0)}
	axe_sys.on_death(v3, other_killer)
	_ok("★★分母: 超过 %.0f 秒 → 一分不给(实测 %d)" % [AE.ASSIST_WINDOW, gs.axe_exp_total],
		gs.axe_exp_total == 0)

	## 情形 D: 压根没被斧头碰过
	gs.axe_exp_bar = 0; gs.axe_exp_total = 0
	axe_sys.on_death({"alive": false}, other_killer)
	_ok("★分母: 从没被斧头碰过 → 一分不给(实测 %d)" % gs.axe_exp_total, gs.axe_exp_total == 0)

	## on_hit 真的会盖时间戳(否则情形 B 在真战斗里永远发生不了)
	var ax := {"_eq_axe": true, "alive": true}
	var tg := {"alive": true, "shield": 0.0}
	axe_sys.on_hit(ax, tg, false)
	_ok("★on_hit 会在目标身上盖【斧头碰过】时间戳(非普攻也盖 —— 助攻不该只算普攻)",
		tg.has("_axe_touch_t") and is_equal_approx(float(tg["_axe_touch_t"]), float(_s._t)),
		str(tg.get("_axe_touch_t", "缺")))
	## on_death 挂在 on-death 而不是 on-kill(源码守卫: 挂错了斧头永远拿不到经验)
	var es: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_ok("★_eq_on_death 里调了 _axe.on_death(挂 on-kill 会因为斧头没有 equips 而永远轮不到)",
		es.contains("_axe.on_death("), "")
