class_name EqGadgetBatch
extends RefCounted
## eq_gadget_batch.gd — 奇械三件新装备的效果本体
## 085 压电陶瓷片 · 086 六分仪浮游炮 · 087 盗令潜水钟
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数都不许改。
## 演出层放 `scripts/scenes/battle/gadget_eq_vfx.gd`(本文件自己 new 出来, 不进共享文件)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★本文件是【本批唯一归你的产品代码】—— 共享文件一律不要动
## ══════════════════════════════════════════════════════════════════════
## 已由主会话预接线、**不要改**:
##   · `scripts/systems/equip/equip_system.gd`      (声明/构造/tick/全部钩子派发)
##   · `scripts/systems/equip/equip_stats_apply.gd` (常驻字段/登场标记)
##   · `scripts/gamedata/equip_stats.gd`            (STATS 三星属性)
##   · `data/phase2-equipment.json`                 (名字/属性镜像/文案)
##   · `scripts/scenes/battle/dual_lane_flow.gd`    (换路调 clear_all)
## 归你的: **本文件** + `scripts/scenes/battle/gadget_eq_vfx.gd` + `tests/verify_eq_gadget_batch.gd/.tscn`
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(与批①/批② 同, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**。裸 `randi()`/`randf()` 会破坏确定性 ——
##    `tools/rng_discipline.py` 冻结了裸调用数, `verify_battle_determinism` 同种子比指纹。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 处决 / 冰封 / 僵硬)。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 所有"持续 N 秒 / 每 N 秒"
##    存**到期时刻**或**自管累加器**, 不许拿 `_t` 直接和常数比。
##
## ══════════════════════════════════════════════════════════════════════
##  本批的分派落点
## ══════════════════════════════════════════════════════════════════════
##   085 → `on_damaged` + `tick_unit`(受伤转龟能, 每秒有上限) —— 见下面【自决 ①】
##   086 → `tick_unit`(每 3 秒生一个浮游炮/最多 6 个 + 每炮每 2 秒打随机敌人 + 终极射线)
##          + `tick`(演出推进 + 孤儿节点自扫)
##   087 → `tick_unit`(效果一: 每 15/10/4 秒偷一个大师技能; 效果二: 压载舱每 2 秒抽水)
##          + `on_damaged`(即时刷新压载层数; 灌水本身由 `battle._spec` 在两条伤害路径上完成)
##
## ══════════════════════════════════════════════════════════════════════
##  ★★【诚实记录】规格没写死、由我定的地方 —— 选了哪一侧 / 另一侧是什么
## ══════════════════════════════════════════════════════════════════════
## ① **085 的记账用"游标差分"而不是"把 dmg 直接累加"。**
##    历史(留着, 因为它解释了为什么要做成幂等): 我实装时查到 `_eq_on_target`
##    (= on_damaged 的宿主)**只挂在 `_apply_damage_from`(普攻/技能)上**, DoT/真伤那条路
##    根本不调它 —— 而规格明写 DoT 每跳要算。**主会话 2026-08-06 已补上窄口**
##    `EquipSystem._b4_on_damaged_any`(从 `_apply_damage` 调, `_b4_eq` 守门),
##    所以现在 `on_damaged` 两条路都会被调到, 本件不需要任何过滤。
##    · **仍然选游标差分的理由**: `piezo_settle(u)` 拿 `u["_st_taken"]` 当账本
##      (它在**两条路上都是**"减伤后、扣盾前"的名义伤害, `battle_damage.gd:47` 与 :188
##      ⇒ 「护盾挡掉的算」「DoT 每跳算」同时满足), 转完把游标推到当前值 ⇒ **幂等**。
##      幂等买到两件事: ㈠ 同一只龟装两把 085 时 `on_damaged` 会被调两次, 直接累加 dmg
##      就会**转两倍**; ㈡ 将来若有第三条伤害路/第二处派发接上来, 也不会静默翻倍。
##    · **另一侧**(在 `on_damaged` 里直接 `energy += dmg * rate`)更短, 但上面两条都守不住。
##    · ⚠ 代价(诚实记录): `tick_unit` 也调 `piezo_settle` 兜底 ⇒ 就算主会话那行窄口被删掉,
##      下一帧也会补上。**所以门禁验 DoT 时是"打完伤害【同帧同步】断言龟能已经涨"**
##      (不 await 任何一帧), 这样窄口一断就红; 另外还有一条源码断言直接查
##      `battle_damage.gd` 里有没有 `_b4_on_damaged_any(u, src, dmg)` 这行。
## ② **085 的"每秒"是滑动到期时刻**(`win_end = _t + 1`), 不是墙钟整秒格。
##    另一侧(整秒格)会让"第 0.99 秒挨一顿 + 第 1.01 秒挨一顿"两秒各自封顶 = 同一波打两倍。
## ③ **086 的浮游炮不是可被攻击的召唤物。** 规格没给它生命/护甲 ⇒ 做成
##    「携带者身上的逻辑挂件 + 演出节点」。另一侧(走 `_spawn_summon`)会凭空多出
##    6 个可被 AOE 清掉的单位, 那是规格里没有的强度变量(而且会把敌人的选靶全吸过去)。
## ④ **086 每门炮的 2 秒是各自独立计时**(从它被生成那一刻起), 不是全体同拍。
##    ⇒ 满编时射击是均匀铺开的而不是每 2 秒齐射 6 发。规格写的是"浮游炮每 2 秒攻击一次"
##    (主语是单门炮), 且成型曲线表里 3 门 = 1.5 次/秒 也是按"各自 0.5 次/秒"算的。
## ⑤ **086 的终极射线条数 = 当时在场的浮游炮数**(不是恒 6)。规格的"6 条合计"表
##    明写是"满编后"的口径。计数器**触发后归零**(规格写"每当…后"= 循环, 周期表也印证)。
## ⑥ **086 的终极射线走 `_resolve_dmg(magic)` ⇒ 吃目标魔抗**(契约 §4「魔法走魔抗」)。
##    另一侧是真伤(不吃魔抗), 规格写的是"魔法伤害" ⇒ 按魔法。
## ⑦ **087 的水柱伤害按【魔法】结算。** 规格只写"等量的水柱伤害", 没给类型。
##    选魔法的理由: 它不是武器打击、也不该吃携带者的护甲穿透; 契约 §4 只有物理/魔法/真伤
##    三种, 真伤(不吃任何抗性)对一件 5 费坦克件太强。**"等量"指的是抽水量作为基数**,
##    落地伤害仍过魔抗。另一侧 = 真伤(字面"等量")。
## ⑧ **087 只有 `_cast_active` 真的返回 true 才算"偷过"。** 规格写"偷取**且释放**过后
##    不再偷取" ⇒ 空放(驯服/猎龟令找不到合法目标)不消耗名额, 下个周期还会再抽到它。
##    另一侧 = 出手即消耗名额(那样 1★ 可能白白浪费掉最贵的那一招)。
## ⑨ **087 施法时把携带者的 `_active_cd` 清零**, 并临时写 `_tr_active` 再还原。
##    六个主动技**共用同一个 `_active_cd` 字段**(RealtimeBattle3DScene.gd:355 注释),
##    不清零的话 3★ 4 秒一次会被上一招 20~60 秒的冷却直接顶掉 —— 而规格里
##    「间隔」就是这台机器自己的节拍, 大师原冷却不该再管一遍(每招本来也只偷一次)。
## ⑩ **087 压载舱在特殊余额里 `order = -10`(最先扛)。** 规格写"受到的伤害**先**灌进舱里"。
##    (普通 `u["shield"]` 仍在所有特殊余额之前 —— 那是 `SpecialBalance` 焊死的顺序, 不归我管。)
## ⑪ **087 的舱容按第一次 tick 时的 `maxHp` 算**, 不在 `on_spawn` 算。
##    因为 `battle._synergy.apply_all()`(羁绊改最大生命)排在 `_b4_on_spawn_all` **之后**
##    (dual_lane_flow.gd), on_spawn 读到的还不是最终值。
## ⑫ **087 的压载层数 = floor(舱内水 / (10% 最大生命))**, 上限 15 层 —— 规格写
##    "每存有 10% 最大生命"⇒ 取整而不是线性插值(15 层 × 10% = 150% 正好是 3★ 满舱)。
## ⑬ **"最远的敌人"走标准层 `battle._targeting._farthest_enemy(u)`, 本文件不自己写。**
##    实装时 `battle._targeting` 只有 `_nearest_*`, 我先在本文件手写了一份并报了上去;
##    主会话 2026-08-06 已把它**收编进标准层**(闸门与 `_nearest_enemy` 逐条一致:
##    黑洞 `untargetable_until` / 龟蛋围栏 `_egg_fence` / 训龟大师不被主动索敌),
##    本文件那份**已删除**。memory [[fb-hand-rolled-copies-drift]]: 就地手写选靶
##    = 抄一次永远落后一次, 以后给 `_nearest_enemy` 加的闸门不会同步到副本上。
##    ★门禁 ⓪ 有一条源码断言焊住这件事: 本文件**不许**再出现 `func _farthest_enemy`。
## ⑭ **`clear_all()` 之外还留了一层自扫兜底。** 换路撤场已由主会话接好
##    (`dual_lane_flow.gd` 里 `for _b4ref in battle._equip_sys._b4_all(): _b4ref.clear_all()`)。
##    但**换路不是演出节点变孤儿的唯一途径** —— 携带者中途阵亡/被驯服换边/被替换掉时
##    没有任何人调 clear_all, 而浮游炮是挂在 `battle._world` 上的(`_dl_clear_units` 只 free
##    单位自己的 sprite/bar, 动不到 `_world` 的子节点)。所以照 EqBowBatch 的既有做法
##    在 `tick()` 里每 0.5 秒自扫一次: 主人已不在 `battle._units` 里或已阵亡就撤演出。

const PIEZO := "p2eq_085"
const SEXT := "p2eq_086"
const DIVE := "p2eq_087"

## 087 压载舱在 SpecialBalance 里的 key 与吸收顺序(见自决 ⑩)。
const DIVE_BALLAST_KEY := "p2eq_087_ballast"
const DIVE_BALLAST_ORDER := -10

## 087 偷技能的候选池 —— **排序固定**才能让"播种 RNG 抽出来的序列"可复现。
## 内容与 `RealtimeBattle3DScene.TRAINER_SKILLS` 的 6 个 key 一致(门禁会逐个比对, 少一个就红)。
const DIVE_SKILLS: Array = ["fury_potion", "glacier", "hook", "hunt_order", "tame", "whistle"]

var battle
var vfx


func _init(b) -> void:
	battle = b
	vfx = GadgetEqVfx.new(b)


## 这只龟身上这件装备的最高星级(0/1/2); 没带返回 -1。
## ★`tick_unit` 只拿得到 (u, delta), 星级要自己查 —— 顺手实现了契约 §4
##   「同一件装备装多把 ⇒ 取星级更高的那一件」。
func _star_of(u: Dictionary, eid: String) -> int:
	var best: int = -1
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == eid:
			best = maxi(best, clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1)
	return best


func _stt(u: Dictionary, eid: String) -> Dictionary:
	if not (u.get("eq_state", null) is Dictionary):
		u["eq_state"] = {}
	var d = u["eq_state"].get(eid, null)
	if not (d is Dictionary):
		d = {}
		u["eq_state"][eid] = d
	return d


## 播种 RNG 抽数组里的一个(空数组返回 null)。★绝不用裸 randi()。
func _pick_rng(arr: Array):
	if arr.is_empty():
		return null
	return arr[battle._battle_rng.randi() % arr.size()]


# ══════════════════════════════════════════════════════════════════
#  §十个钩子
# ══════════════════════════════════════════════════════════════════

## 每帧全局推进: 演出 + 孤儿节点自扫(见自决 ⑭)
func tick(delta: float) -> void:
	vfx.tick(delta)
	_sweep_t += delta
	if _sweep_t >= 0.5:
		_sweep_t = 0.0
		_sweep_orphans()


## 每帧逐单位推进
func tick_unit(u: Dictionary, delta: float) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var s85: int = _star_of(u, PIEZO)
	if s85 >= 0:
		piezo_settle(u)
	var s86: int = _star_of(u, SEXT)
	if s86 >= 0:
		_tick_sextant(u, delta, s86)
	var s87: int = _star_of(u, DIVE)
	if s87 >= 0:
		_tick_dive(u, delta, s87)


## 携带者登场(每路开战跑一次)
func on_spawn(u: Dictionary, eid: String, _si: int) -> void:
	if eid == PIEZO:
		## ★把游标对齐到"现在已经挨过多少" —— 不对齐的话开场第一次结算会把
		##   登场前(上一路残留/摆位期)的承伤一次性全转成龟能。
		var st: Dictionary = _stt(u, PIEZO)
		st["seen"] = float(u.get("_st_taken", 0))
		st["used"] = 0.0
		st["win_end"] = 0.0
	elif eid == SEXT:
		var st6: Dictionary = _stt(u, SEXT)
		st6["gen_t"] = 0.0
		st6["shots"] = 0
		st6["drones"] = []
	elif eid == DIVE:
		var st7: Dictionary = _stt(u, DIVE)
		st7["steal_t"] = 0.0
		st7["stolen"] = []
		st7["pump_t"] = 0.0
		st7["cap"] = 0.0


## 携带者普攻发出(本批不用)
func on_basic(_u: Dictionary, _tgt, _eid: String, _si: int) -> void:
	pass


## 携带者命中结算后(本批不用)
func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者受到伤害后(★这条钩只挂在普攻/技能那条路上, 见自决 ①)
func on_damaged(u: Dictionary, _src, _dmg: float, eid: String, _si: int) -> void:
	if eid == PIEZO:
		piezo_settle(u)
	elif eid == DIVE:
		## 挨打即刷层数: 水位是在 `battle._spec.absorb` 里变的(伤害管线中央),
		## 这里只是把"水位 → 移速/护甲"这一步提前到当帧, 不然要等下一帧 tick 才看得见。
		_dive_sync_stacks(u, _star_of(u, DIVE))


## 携带者受到法术伤害后(本批不用: 085 吃的是【所有】伤害, 账在 piezo_settle)
func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者阵亡
func on_death(u: Dictionary, eid: String, _si: int) -> void:
	if eid == SEXT or eid == DIVE:
		vfx.detach(u)


## 法器法力条集满(本批不用)
func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## ★换路撤场: 清掉演出节点与自扫名册。
func clear_all() -> void:
	for o in _carriers:
		if o is Dictionary:
			vfx.detach(o)
	_carriers.clear()
	vfx.clear()
	_sweep_t = 0.0


# ══════════════════════════════════════════════════════════════════
#  §自扫兜底(见自决 ⑭) —— clear_all 没人调时也不会把演出带进下一路
# ══════════════════════════════════════════════════════════════════

var _sweep_t: float = 0.0
## ★存的是【单位字典数组】, **不是** Dictionary 的键(CLAUDE.md §3.2 递归哈希会卡死)。
var _carriers: Array = []


func _remember(u: Dictionary) -> void:
	if not battle._arr_has_unit(_carriers, u):
		_carriers.append(u)


func _sweep_orphans() -> int:
	var keep: Array = []
	var gone: int = 0
	for o in _carriers:
		if o is Dictionary and battle._arr_has_unit(battle._units, o) and o.get("alive", false):
			keep.append(o)
		else:
			if o is Dictionary:
				vfx.detach(o)
			gone += 1
	_carriers = keep
	return gone


# ══════════════════════════════════════════════════════════════════
#  §085 压电陶瓷片(1 费) —— 受到的伤害 5/9/15% 转成龟能, 每秒上限 20/40/60
# ══════════════════════════════════════════════════════════════════

## 把"还没结算的承伤"转成龟能, 返回**本次真的转了多少**。
##
## ★**幂等**: 转完就把游标 `seen` 推到当前 `_st_taken` ⇒ 连调两次第二次必然返回 0。
##   这就是它能同时挂 `on_damaged`(普攻/技能路·当帧)与 `tick_unit`(兜 DoT 路)而不重复计的原因。
## ★账本用 `u["_st_taken"]`: 它在**两条伤害路径上都是**"减伤后 / 扣盾前"的名义伤害
##   ⇒ 「护盾挡掉的算」「DoT 每跳算」两条规格口径**同时**满足, 不用改共享文件。
## ⚠ 与 082 的口径【故意不同】: 082 数"受到几段攻击"(DoT 不算), 本件数"受到多少伤害量"(DoT 算)。
func piezo_settle(u: Dictionary) -> float:
	var si: int = _star_of(u, "p2eq_085")
	if si < 0 or not u.get("alive", false):
		return 0.0
	var rate: float = [0.05, 0.09, 0.15][si]      # 受到的伤害 5/9/15% 转化为龟能
	var cap: float = [20.0, 40.0, 60.0][si]       # 每秒转化的上限 20/40/60 龟能
	var st: Dictionary = _stt(u, "p2eq_085")
	var taken: float = float(u.get("_st_taken", 0))
	var seen: float = float(st.get("seen", 0.0))
	if taken < seen:
		st["seen"] = taken      # 账本被外部重置过(换路/结算) ⇒ 重新对齐, 不倒扣
		return 0.0
	var fresh: float = taken - seen
	st["seen"] = taken
	if fresh <= 0.0:
		return 0.0
	## 每秒配额: 存【到期时刻】而不是拿 _t 跟常数比(CLAUDE.md §3.4)
	if battle._t >= float(st.get("win_end", 0.0)):
		st["win_end"] = battle._t + 1.0
		st["used"] = 0.0
	var give: float = minf(fresh * rate, maxf(0.0, cap - float(st.get("used", 0.0))))
	if give <= 0.0:
		return 0.0
	st["used"] = float(st.get("used", 0.0)) + give
	battle._equip_sys._eq_grant_energy(u, give)
	u["_piezo_last"] = give                                    # 同步触发证据(门禁断言用)
	u["_piezo_total"] = float(u.get("_piezo_total", 0.0)) + give
	vfx.piezo_spark(u, give)
	return give


# ══════════════════════════════════════════════════════════════════
#  §086 六分仪浮游炮(5 费)
# ══════════════════════════════════════════════════════════════════

const SEXT_GEN_IV := 3.0        ## 每 3 秒生成一门
const SEXT_CAP := 6             ## 最多 6 门
const SEXT_FIRE_IV := 2.0       ## 每门炮每 2 秒攻击一次
const SEXT_ORBIT_R := 74.0      ## 环绕半径(码)
const SEXT_ORBIT_W := 1.05      ## 环绕角速度(弧度/秒)
## 终极射线**贯穿**多远(码) —— 赛博龟阵亡齐射是 1300, 同口径
const SEXT_RAY_LEN := 1300.0
## 判"在不在这条线上"的半宽(码) —— 赛博龟用 40
const SEXT_RAY_HALF_W := 40.0


func _tick_sextant(u: Dictionary, delta: float, si: int) -> void:
	var st: Dictionary = _stt(u, "p2eq_086")
	var atk_mult: float = [0.3, 0.4, 0.5][si]            # 每炮伤害 = 携带者 0.3/0.4/0.5 ATK
	var mr_per: float = [10.0, 15.0, 20.0][si]           # 每门炮给携带者 10/15/20 魔抗
	var need: int = [40, 30, 20][si]                     # 累计 40/30/20 次攻击 → 终极射线
	var drones: Array = st.get("drones", [])
	# ── 生成: 每 3 秒一门, 满 6 门就停 ──
	if drones.size() < SEXT_CAP:
		var g: float = float(st.get("gen_t", 0.0)) + delta
		while g >= SEXT_GEN_IV and drones.size() < SEXT_CAP:
			g -= SEXT_GEN_IV
			# ★★2026-08-08 `ft` 初值改成**随机错峰**(照赛博龟 `fire_t = 1.6 * randf()`)。
			#   原来六门都是 0.0 ⇒ **同时到点、同时开火**, 读成"一个整体在放", 而不是六门各打各的。
			#   ⚠ 用 `_battle_rng` 不用 `_juice_rng`: `ft` 决定**伤害在哪一帧落**, 属于对局逻辑,
			#     走演出 rng 会破坏确定性(rng_discipline 门禁盯着这条)。
			drones.append({"ang": TAU * float(drones.size()) / float(SEXT_CAP),
				"ft": battle._battle_rng.randf() * SEXT_FIRE_IV,
				"sx": 0.0, "sy": 0.0, "scat": 0.0})
			_remember(u)
		st["gen_t"] = g
	st["drones"] = drones
	u["_sext_n"] = drones.size()                          # 同步证据
	_sext_apply_mr(u, drones.size(), mr_per)
	# ── 环绕 + 开火 ──
	var fired: int = 0
	# ★带下标遍历: 要把"开火的是第几门炮"传给演出层, 弹才能从**那门炮**出膛(照赛博龟)
	for di in range(drones.size()):
		var d: Dictionary = drones[di]
		d["ang"] = float(d["ang"]) + SEXT_ORBIT_W * delta
		if float(d.get("scat", 0.0)) > 0.0:
			d["scat"] = maxf(0.0, float(d["scat"]) - delta)   # 终极演出期间飞散在外, 不开火
			d["fe"] = float(d.get("fe", 0.0)) + delta          # 飞散行程(错峰: 各自的延迟与时长)
			continue
		d["ft"] = float(d.get("ft", 0.0)) + delta
		if float(d["ft"]) >= SEXT_FIRE_IV:
			d["ft"] = float(d["ft"]) - SEXT_FIRE_IV
			if sext_fire_one(u, atk_mult, di):
				fired += 1
	if fired > 0:
		st["shots"] = int(st.get("shots", 0)) + fired
		u["_sext_shots"] = int(st["shots"])               # 同步证据
		if int(st["shots"]) >= need:
			st["shots"] = 0
			u["_sext_shots"] = 0
			sext_ultimate(u, si)
	vfx.sextant_sync(u, drones, SEXT_ORBIT_R)


## 一门炮打一次随机敌人。返回是否真的打出去了。
## ★随机走 `battle._battle_rng`(焊死口径 ①), 伤害 `from_equip=true`(焊死口径 ②)。
func sext_fire_one(u: Dictionary, atk_mult: float, di: int = -1) -> bool:
	var tgt = _pick_rng(battle._targeting._pick_enemies_of(u))
	if tgt == null:
		return false
	# ★★2026-08-08 照赛博龟被动: 弹从**那门炮**出膛(不是从携带者身上), 且伤害等弹飞到。
	#   `di` 由调用方给 —— 哪门炮的计时器到点就是哪门在打。
	var vt: Dictionary = tgt
	var fly: float = clampf((Vector2(tgt["pos"]) - Vector2(u["pos"])).length()
		/ GadgetEqVfx.SHOT_BOLT_SPD, 0.12, 0.5)
	battle._queue_shots(1, 0.0, func() -> void:
		if not vt.get("alive", false):
			return
		var dm: int = battle._resolve_dmg(u, float(u.get("atk", 0.0)) * atk_mult, vt, false)
		battle._damage._apply_damage_from(u, vt, dm, Color(0.72, 0.86, 1.0), 0.0, false, true),
		u, "", Callable(), fly)
	vfx.sextant_shot(u, tgt, di)
	return true


## 【终极射线·纯结算】所有浮游炮飞散到战场随机点, 各朝一个随机目标发一条紫色射线。
## 返回真的打出了几条。★演出由 `vfx` 播, 结算**不依赖任何 tween 跑完**(CLAUDE.md §3.5)。
func sext_ultimate(u: Dictionary, si: int) -> int:
	var st: Dictionary = _stt(u, "p2eq_086")
	var ray: float = [200.0, 350.0, 1000.0][si]           # 每条终极射线 200/350/1000 魔法伤害
	var drones: Array = st.get("drones", [])
	var n: int = 0
	var beams: Array = []
	for d in drones:
		var sp: Vector2 = Vector2(
			battle._battle_rng.randf_range(battle.ARENA.position.x, battle.ARENA.end.x),
			battle._battle_rng.randf_range(battle.ARENA.position.y, battle.ARENA.end.y))
		d["sx"] = sp.x
		d["sy"] = sp.y
		# ★★2026-08-08【错峰飞散】照赛博龟: 起飞**间隔** randf()*0.35、飞行**时长** 0.6~1.2 各不相同
		#   ⇒ 六门不是"同一帧瞬移到位", 而是一个个错开飞出去。
		#   起点记它当时的环绕位(_px/_py 由演出层每帧回填) —— 没有起点就没法插值。
		d["fd"] = battle._battle_rng.randf() * GadgetEqVfx.SEXT_SCATTER_LAG
		d["fdur"] = GadgetEqVfx.SEXT_SCATTER_MIN 			+ battle._battle_rng.randf() * (GadgetEqVfx.SEXT_SCATTER_MAX - GadgetEqVfx.SEXT_SCATTER_MIN)
		d["fe"] = 0.0
		d["ox"] = float(d.get("_px", float(u["pos"].x)))
		d["oy"] = float(d.get("_py", float(u["pos"].y)))
		# 回程也错峰: 各自的起飞延迟与飞行时长
		d["bd"] = battle._battle_rng.randf() * GadgetEqVfx.SEXT_BACK_LAG
		d["bdur"] = GadgetEqVfx.SEXT_BACK_MIN 			+ battle._battle_rng.randf() * (GadgetEqVfx.SEXT_BACK_MAX - GadgetEqVfx.SEXT_BACK_MIN)
		# ★`scat` 要盖到**回程走完**为止, 否则一归零就又瞬移回轨道(用户点名的那条)
		d["scat"] = GadgetEqVfx.SEXT_FIRE_DELAY + GadgetEqVfx.RAY_LIFE 			+ float(d["bd"]) + float(d["bdur"])
		var tgt = _pick_rng(battle._targeting._pick_enemies_of(u))
		if tgt == null:
			continue
		# ★★2026-08-08【贯穿】用户:「是不是穿透」—— 赛博龟阵亡齐射的激光是**贯穿**的:
		#   `endp = dpos + ldir * 1300`(射出去而不是射到目标就停) + **线上所有敌人各吃一次**。
		#   本件旧版是"射到目标就停、只结算那一个"。⇒ 照它改。
		#   ⚠ 这是**强度变化**(线上多个敌人时伤害翻倍), 规格原文只写了"朝一个随机目标发一条
		#     射线, 每条造成 200/350/1000" —— 没写贯穿也没写不贯穿。要退回只打首目标说一声。
		var ldir: Vector2 = (Vector2(tgt["pos"]) - sp)
		ldir = ldir.normalized() if ldir.length() > 1.0 else Vector2.RIGHT
		var endp: Vector2 = sp + ldir * SEXT_RAY_LEN
		# ★★2026-08-08【时序合一 + 照赛博龟的编排】用户:「参考下赛博龟被动的攻击方式和技能演出」。
		#   赛博龟阵亡齐射是完整的七段: 错峰飞散 → 炮身发亮 → **口部聚能光球膨胀 0.45 秒**
		#   → 光球消失 + **炮体后坐再回位**(Gaster Blaster 标志) → **双层光束**(厚白核心 + 青晕
		#   外束, 外束略久 = 收细消散感) → 震屏 → 线上每个目标命中火花。
		#   本件旧版是"光束凭空出现再淡出", 七段一段都没有, 伤害也在开火那一帧就落。
		#   ⇒ 伤害推迟到**光束真的射出去**那一刻(SEXT_CHARGE 秒后), 与演出对齐。
		var org: Vector2 = sp
		var dr: Vector2 = ldir
		battle._queue_shots(1, 0.0, func() -> void:
			# 贯穿: 线上**所有**敌人各吃一次(照赛博龟那条 `_on_line(dpos, ldir, pos, 40)`)
			for o in battle._targeting._enemies_of(u):
				if not o.get("alive", false):
					continue
				if not battle._on_line(org, dr, Vector2(o["pos"]), SEXT_RAY_HALF_W):
					continue
				var dm: int = battle._resolve_dmg(u, ray, o, true)
				battle._damage._apply_damage_from(u, o, dm, GadgetEqVfx.RAY_COLOR, 0.0, false, true)
				vfx.sextant_ray_hit(Vector2(o["pos"])),
			u, "", Callable(), GadgetEqVfx.SEXT_FIRE_DELAY)
		beams.append([sp, endp])
		n += 1
	u["_sext_ults"] = int(u.get("_sext_ults", 0)) + 1     # 同步证据: 终极放了几轮
	u["_sext_rays"] = n                                   # 同步证据: 这一轮几条射线
	# ① 飞散走完再蓄力(赛博龟: 0.75 秒开始亮/聚能), ② 1.35 秒发射 —— 与上面那段伤害同一个延时
	battle._queue_shots(1, 0.0, func() -> void: vfx.sextant_charge(u, beams),
		u, "", Callable(), GadgetEqVfx.SEXT_FIRE_DELAY - GadgetEqVfx.SEXT_CHARGE)
	battle._queue_shots(1, 0.0, func() -> void: vfx.sextant_ultimate(u, beams),
		u, "", Callable(), GadgetEqVfx.SEXT_FIRE_DELAY)
	return n


## 魔抗被动: 只留一条本件自己的 flat 加成, 门数变了就重写(不 append 第二条)。
func _sext_apply_mr(u: Dictionary, n: int, per: float) -> void:
	var want: float = per * float(n)
	if absf(want - float(u.get("_sext_mr", -1.0))) < 0.001:
		return
	u["_sext_mr"] = want
	var bl: Array = u.get("buffs", [])
	for i in range(bl.size() - 1, -1, -1):
		var b = bl[i]
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == "p2eq_086":
			bl.remove_at(i)
	if want > 0.0:
		bl.append({"stat": "mr", "amount": want, "pct": false,
			"until": battle._t + 1.0e9, "src_eq": "p2eq_086"})
	battle._recalc_stats(u)


# ══════════════════════════════════════════════════════════════════
#  §087 盗令潜水钟(5 费)
# ══════════════════════════════════════════════════════════════════

const DIVE_PUMP_IV := 2.0       ## 每 2 秒抽一次
const DIVE_PUMP_FRAC := 0.10    ## 每次抽舱内的 10%
const DIVE_STACK_FRAC := 0.10   ## 每 10% 最大生命的水 = 1 层
const DIVE_STACK_CAP := 15      ## 最多 15 层
const DIVE_MOVE_PER := 0.03     ## 每层 +3% 移速
const DIVE_DEF_PER := 3.0       ## 每层 +3 护甲


func _tick_dive(u: Dictionary, delta: float, si: int) -> void:
	var st: Dictionary = _stt(u, "p2eq_087")
	var steal_iv: float = [15.0, 10.0, 4.0][si]          # 每 15/10/4 秒偷一个大师主动技
	var cap_frac: float = [0.6, 0.9, 1.5][si]            # 压载舱容量 = 最大生命的 60/90/150%
	# ── 舱容: 第一次 tick 才算(羁绊改最大生命排在 on_spawn 之后, 见自决 ⑪) ──
	if float(st.get("cap", 0.0)) <= 0.0:
		st["cap"] = float(u.get("maxHp", 0.0)) * cap_frac
		battle._spec.grant(u, DIVE_BALLAST_KEY, float(st["cap"]),
			{"order": DIVE_BALLAST_ORDER})
		_remember(u)
	# ── 效果一: 偷技能 ──
	var stolen: Array = st.get("stolen", [])
	if stolen.size() < DIVE_SKILLS.size():
		var t: float = float(st.get("steal_t", 0.0)) + delta
		if t >= steal_iv:
			t = 0.0
			dive_steal_once(u, st)
			stolen = st.get("stolen", [])
		st["steal_t"] = t
	# ── 效果二: 压载舱每 2 秒抽水 ──
	var p: float = float(st.get("pump_t", 0.0)) + delta
	if p >= DIVE_PUMP_IV:
		p -= DIVE_PUMP_IV
		dive_pump(u)
	st["pump_t"] = p
	_dive_sync_stacks(u, si)
	vfx.dive_gauge(u, dive_water(u), float(st.get("cap", 0.0)))


## 舱内现有多少水 = 舱容 − 剩余可灌量。★剩余可灌量就是 SpecialBalance 里那条余额。
func dive_water(u: Dictionary) -> float:
	var st: Dictionary = _stt(u, "p2eq_087")
	var cap: float = float(st.get("cap", 0.0))
	if cap <= 0.0:
		return 0.0
	return clampf(cap - battle._spec.val(u, DIVE_BALLAST_KEY), 0.0, cap)


## 【纯结算】抽水: 舱内 10% 还成生命 + 朝**最远的敌人**喷等量水柱。返回抽了多少。
func dive_pump(u: Dictionary) -> float:
	var st: Dictionary = _stt(u, "p2eq_087")
	var water: float = dive_water(u)
	var amt: float = water * DIVE_PUMP_FRAC
	if amt <= 0.0:
		return 0.0
	battle._damage._heal(u, amt)
	battle._spec.grant(u, DIVE_BALLAST_KEY, amt, {"order": DIVE_BALLAST_ORDER})   # 水抽走 ⇒ 舱又空出这么多
	u["_dive_pumped"] = amt                                # 同步证据
	u["_dive_pumped_total"] = float(u.get("_dive_pumped_total", 0.0)) + amt
	var tgt = battle._targeting._farthest_enemy(u)
	if tgt != null:
		var dm: int = battle._resolve_dmg(u, amt, tgt, true)
		battle._damage._apply_damage_from(u, tgt, dm, GadgetEqVfx.JET_COLOR, 0.0, false, true)
		u["_dive_jet_dmg"] = dm
		vfx.dive_jet(u, tgt, amt)
	_dive_sync_stacks(u, _star_of(u, DIVE))
	st["pump_t"] = float(st.get("pump_t", 0.0))
	return amt


## 【纯查询】现在该有几层(舱内每 10% 最大生命 1 层, 上限 15)。
func dive_stacks(u: Dictionary) -> int:
	var mh: float = float(u.get("maxHp", 0.0))
	if mh <= 0.0:
		return 0
	return clampi(int(floor(dive_water(u) / (mh * DIVE_STACK_FRAC))), 0, DIVE_STACK_CAP)


## 层数 → 真实属性(移速走 move_perm 乘法永久通道, 护甲走 buffs 的 flat 区)。
## ★`_dive_mp0` 记的是"没有压载加成时的 move_perm", 每次从它重算, 不做增量(不会浮点漂移)。
func _dive_sync_stacks(u: Dictionary, si: int) -> void:
	if si < 0:
		return
	var n: int = dive_stacks(u)
	if int(u.get("_dive_stk", -1)) == n:
		return
	u["_dive_stk"] = n
	if not u.has("_dive_mp0"):
		u["_dive_mp0"] = float(u.get("move_perm", 1.0))
	u["move_perm"] = float(u["_dive_mp0"]) * (1.0 + DIVE_MOVE_PER * float(n))
	var bl: Array = u.get("buffs", [])
	for i in range(bl.size() - 1, -1, -1):
		var b = bl[i]
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == "p2eq_087":
			bl.remove_at(i)
	if n > 0:
		bl.append({"stat": "def", "amount": DIVE_DEF_PER * float(n), "pct": false,
			"until": battle._t + 1.0e9, "src_eq": "p2eq_087"})
	battle._recalc_stats(u)


## 偷一个还没偷过的大师主动技并**走真入口**释放。返回被偷的技能 id(没成功返回 "")。
##
## ★★**必须走 `battle._trainer_sys._cast_active`** —— 不自己复制一份施法逻辑
##   (memory [[fb-hand-rolled-copies-drift]] / [[fb-verify-must-run-the-real-path]]:
##   「断言函数存在」守不住「还有没有人调它」, 手抄的副本必然落后)。
## ★自动瞄准: dir/point 朝敌人最密集处, target 取最近的敌人, none 直接放(用户 2026-08-06)。
## ★只有 `_cast_active` 返回 true 才计入"已偷"(自决 ⑧)。
func dive_steal_once(u: Dictionary, st: Dictionary) -> String:
	var stolen: Array = st.get("stolen", [])
	var pool: Array = []
	for sid in DIVE_SKILLS:
		if not stolen.has(sid):
			pool.append(sid)
	if pool.is_empty():
		return ""
	var pick: String = str(_pick_rng(pool))
	var aim: Vector2 = _dive_aim_for(u, pick)
	var prev_act = u.get("_tr_active", null)
	var prev_cd: float = float(u.get("_active_cd", 0.0))
	u["_tr_active"] = pick
	u["_active_cd"] = 0.0                    # 六招共用一个冷却字段, 不清零会被上一招顶掉(自决 ⑨)
	var ok: bool = bool(battle._trainer_sys._cast_active(u, aim))
	## ★"施放成功/被拒"是这条路的验收要求(不打印就会把"没施放"当成"看不见"去查,
	##   memory [[fb-verify-must-run-the-real-path]])。但**加一个每携带者的行数帽** ——
	##   成功最多 6 次, 而"被拒"在场上一个可选中敌人都没有时会每个周期重来一次
	##   (3★ 每 4 秒一行), STRESS/AUDIT 跑几十只带这件的龟就会把日志刷爆。
	var said: int = int(u.get("_dive_log_n", 0))
	if said < 24:
		u["_dive_log_n"] = said + 1
		print("[087 盗令潜水钟] %s 偷【%s】→ %s%s" % [str(u.get("name", u.get("id", "?"))),
			pick, "施放成功" if ok else "★被拒(未施放)",
			"  (本携带者日志到此为止)" if said == 23 else ""])
	if prev_act == null:
		u.erase("_tr_active")
	else:
		u["_tr_active"] = prev_act
	if not ok:
		u["_active_cd"] = prev_cd
		return ""
	stolen.append(pick)
	st["stolen"] = stolen
	u["_dive_last_steal"] = pick                           # 同步证据
	u["_dive_steal_n"] = stolen.size()
	vfx.dive_steal(u)
	return pick


## 自动瞄准向量(相对携带者的偏移), 按 `TRAINER_SKILLS[sid].aim` 分三种。
func _dive_aim_for(u: Dictionary, sid: String) -> Vector2:
	var mode: String = str(battle.TRAINER_SKILLS.get(sid, {}).get("aim", "none"))
	match mode:
		"target":
			var t = battle._targeting._nearest_enemy(u)
			return (t["pos"] - u["pos"]) if t != null else Vector2.ZERO
		"dir", "point":
			return battle._densest_enemy_point(u, 300.0) - u["pos"]
	return Vector2.ZERO
