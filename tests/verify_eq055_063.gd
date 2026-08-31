extends Node
## verify_eq055_063.gd — 055 靶向器→病毒箭头 / 063 白鲸气环三环伤害改公式 (2026-08-31)
##
## ★需求原文(用户 2026-08-31):
##   「靶向器改名为病毒箭头，重做图标，白鲸气环的三环伤害改为
##     25/40/70+目标2/3/5%最大生命值真实伤害」
##   055 只改**显示名与图**, 效果一字不动(未决点 ④, 我按建议自拍: `HookBombSystem` 类名保留)。
##
## ★★063 的判据必须【拿两种不同的目标 maxHp 各量一次】——
##   只用一种血量的话, 「定额 25 + 2%×1000 = 45」和「定额 45 + 0%」给出同一个数,
##   两种实现分不开, **把百分比那一半整个删掉门禁照样绿**。
##   (036 温泉蛋刚踩过同一个形状; 更早的「多件取最大」也是被测试数据让两种行为同解而成了假门禁。)
##
## ★★另一条容易漏的: 「真实伤害」必须**真的不吃减免**。
##   只验数字大小的话, 拿一个没护甲的假人测, 物理伤害和真实伤害给出同一个数 ——
##   所以这里专门给目标堆满护甲/魔抗/减伤, 再看伤害是不是一点没少。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EqSpiritBatch := preload("res://scripts/systems/equip/eq_spirit_batch.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 造一个目标, 给定 maxHp 与「抗性拉满与否」, 让携带者普攻命中三次 → 回报目标掉了多少血。
## ★走真入口 `_eq_whale_ring(src, tgt, si, basic=true)` 三次, 不是直接调伤害函数 ——
##   否则「满 3 环才引爆」这一段根本没被验到。
func _boom_once(si: int, maxhp: float, tanky: bool) -> float:
	_s._units.clear()
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var src: Dictionary = _s._spawn._make_unit("basic", "left", c + Vector2(-120.0, 0.0))
	var tgt: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(120.0, 0.0))
	_s._units.append(src)
	_s._units.append(tgt)
	tgt["maxHp"] = maxhp
	tgt["hp"] = maxhp
	tgt["shield"] = 0.0
	tgt["whale_rings"] = 0
	if tanky:
		## 真实伤害要"一点都不少" —— 把真正被读的减伤通道全部拉满再打。
		## ★★护甲的字段名是 `def` 不是 `armor`(battle_damage._dot_after_resist:784 /
		##   RealtimeBattle3DScene._resolve_dmg)。我第一版喂的 `armor` / `dr_mult`
		##   **全仓没有任何产品代码读它** ⇒ 那条"是真实伤害"的断言在把 raw 改成 false 之后
		##   照样绿, 反向验证当场抓到「一条都没红 —— 这条门禁是假的」。
		##   (同族 [[fb-gate-subject-never-constructed]]: 判据没错, 被测对象根本没被布置成那样。)
		tgt["def"] = 9999.0
		tgt["mr"] = 9999.0
		tgt["flat_dr"] = 500.0     # 铁壁盾那条: 每段非真实伤害固定减 X 点
		tgt["damage_reduction"] = 0.9
	else:
		tgt["def"] = 0.0
		tgt["mr"] = 0.0
		tgt["flat_dr"] = 0.0
		tgt["damage_reduction"] = 0.0
	## ★★两个【测试自己带进来的】倍率必须摘掉, 否则端到端量到的不是这件装备的数:
	##   ① `src.id == "basic"` 会触发**小龟·不屈**(battle_damage.gd:266 按目标稀有度增伤,
	##      默认 +20%) —— 而合成单位默认就是小龟。探针实测倍率恒定 1.200。
	##   ② 暴击(`crit` 默认 0.25)会再乘 1.5 ⇒ 同一组参数两次跑出 444 / 666 两个值。
	##      **这不是回归, 是测试自己不稳**([[fb-make-assertions-rng-insensitive]]);
	##      我第一版就是拿它去对精确值, 判据必红且红得毫无信息。
	src["id"] = "__ring_probe__"
	src["crit"] = 0.0
	var h0: float = float(tgt["hp"])
	## ★成员名是 `_spirit_sys` 不是 `_spirit` —— 第一版写错, 六次调用全抛
	##   「Invalid access to property」, 伤害全量到 0, 差点当成产品 bug 去查。
	##   (同族: 036 那轮我把 `battle._equip_tick_sys` 写成 `_equip_sys._tick`。)
	var spirit = _s._equip_sys._spirit_sys
	for _i in range(EqSpiritBatch.RING_TRIGGER):
		spirit._eq_whale_ring(src, tgt, si, true)
	_s._damage._heal_flush(tgt)
	return h0 - float(tgt["hp"])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 055 病毒箭头 / 063 白鲸气环三环伤害 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ── 063: 分母 —— 常量表就是需求给的那两组字面值 ──
	var flat: Array = EqSpiritBatch.RING_FLAT
	var pct: Array = EqSpiritBatch.RING_MAXHP_PCT
	_ok("063 ★分母: 常量表 = 定额 %s + 百分比 %s" % [str(flat), str(pct)],
		flat == [25.0, 40.0, 70.0] and pct == [0.02, 0.03, 0.05])

	# ── 063: 纯函数逐星 × 两种目标血量(精确值) ──
	## ★精确值判据落在**纯函数** `_ring_boom_dmg` 上 —— 它就是文案承诺的那个数。
	##   端到端那一层要穿过一堆全局乘数(不屈/暴击/增伤/决胜), 拿它对精确值等于把
	##   一整条伤害管线的所有机制都焊进这条判据里, 以后任何人改增伤都会误伤这里。
	##   (CLAUDE.md §3.5 同一条道理: 要验的数值不该只存在于结算链中间。)
	var pure_ok := true
	var pure_detail: Array = []
	for si in range(3):
		for mh in [1000.0, 6000.0]:
			var t: Dictionary = {"maxHp": mh}
			var pg: float = _s._equip_sys._spirit_sys._ring_boom_dmg(t, si)
			var pw: float = float(flat[si]) + mh * float(pct[si])
			pure_detail.append("%d★/%.0fHP: %.1f" % [si + 1, mh, pg])
			if absf(pg - pw) > 0.01:
				pure_ok = false
	_ok("063 ★★纯函数逐星 × 两种目标血量 = 【定额 + 百分比×目标最大生命】", pure_ok,
		" · ".join(pure_detail))

	# ── 063: 端到端(摘掉不屈与暴击后应当与纯函数一致) ──
	var ok_all := true
	var detail: Array = []
	for si in range(3):
		for mh in [1000.0, 6000.0]:
			var got: float = _boom_once(si, mh, false)
			var want: float = float(flat[si]) + mh * float(pct[si])
			detail.append("%d★/%.0fHP: %.1f(期望 %.1f)" % [si + 1, mh, got, want])
			if absf(got - want) > 1.01:
				ok_all = false
	_ok("063 ★★端到端: 三环引爆真的按这个数掉血(已摘掉小龟不屈与暴击)", ok_all, " · ".join(detail))

	## ★分母的另一半: 两种血量下的伤害必须【不一样】——
	##   一样就说明百分比那半没生效, 而上面那条可能因为凑巧的数字仍然绿。
	var lo: float = _boom_once(2, 1000.0, false)
	var hi: float = _boom_once(2, 6000.0, false)
	_ok("063 ★★目标血量翻 6 倍 → 引爆伤害必须变多(证明百分比那半真的在算)",
		hi > lo + 200.0, "1000HP 掉 %.1f / 6000HP 掉 %.1f" % [lo, hi])

	## ★真实伤害: 把护甲/魔抗/减伤全拉满, 伤害一点都不许少
	var soft: float = _boom_once(2, 6000.0, false)
	var hard: float = _boom_once(2, 6000.0, true)
	## ★★`soft > 0` 这一半【必须在】—— 第一版没有它, 结果六次调用因为成员名写错全部抛异常、
	##   伤害量到 0, 而 "0 一点没少还是 0" 判成了 PASS。**恒真式当判据**, 正是今天反复栽的那个形状。
	_ok("063 ★★是真实伤害: 护甲9999+魔抗9999+减伤拉满后伤害一点没少",
		soft > 1.0 and absf(hard - soft) < 1.01, "无抗 %.1f / 满抗 %.1f" % [soft, hard])

	## ★不满 3 环不许引爆 —— 「满 3 环」这一段自己也要有判据
	_s._units.clear()
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var s2: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-120.0, 0.0))
	var t2: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(120.0, 0.0))
	_s._units.append(s2)
	_s._units.append(t2)
	t2["maxHp"] = 6000.0
	t2["hp"] = 6000.0
	t2["shield"] = 0.0
	t2["whale_rings"] = 0
	for _i in range(EqSpiritBatch.RING_TRIGGER - 1):
		_s._equip_sys._spirit_sys._eq_whale_ring(s2, t2, 2, true)
	_s._damage._heal_flush(t2)
	_ok("063 只叠了 2 环时一点血都不掉(满 3 环才引爆)",
		absf(float(t2["hp"]) - 6000.0) < 0.01, "hp=%.1f 环=%d" % [float(t2["hp"]), int(t2.get("whale_rings", -1))])

	# ── 055: 改名换图, 效果不动 ──
	var e55: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_055", {})
	_ok("055 名字 = 病毒箭头", str(e55.get("name", "")) == "病毒箭头", str(e55.get("name", "")))
	_ok("055 图标换成专属新图且文件在盘上",
		str(e55.get("img", "")) == "equip/virus-arrow.png"
			and ResourceLoader.exists("res://assets/sprites/equip/virus-arrow.png"),
		str(e55.get("img", "")))
	## ★效果一字不动 —— 需求只说改名重做图标。钉死原文里的关键句,
	##   免得以后有人"顺手把文案也改成病毒味的"。
	var d55: String = str(e55.get("effectDesc1", ""))
	_ok("055 ★效果文案一个字没动(只换名换图)",
		d55.find("钩索炸弹") >= 0 and d55.find("HookBombSystem.TRIGGER_DMG") >= 0
			and d55.find("HookBombSystem.BOMB_TICK") >= 0,
		"len=%d" % d55.length())

	# ── 收尾: 分母断言 ──
	if _n < 9:
		print("  [FAIL] ★分母: 断言只有 %d 条(<9)" % _n)
		_fail += 1
	print("ALL PASS — 055/063" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
