class_name EqRelicBatch
extends RefCounted
## eq_relic_batch.gd — 遗物两件新装备的效果本体
## 091 远古龟甲片 · 094 祖龟碑
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数都不许改。
## 演出层放 `scripts/scenes/battle/relic_eq_vfx.gd`(本文件自己 new 出来, 不进共享文件)。
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
## 归你的: **本文件** + `scripts/scenes/battle/relic_eq_vfx.gd` + `tests/verify_eq_relic_batch.gd/.tscn`
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(与批①/批② 同, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**。裸 `randi()`/`randf()` 会破坏确定性 ——
##    `tools/rng_discipline.py` 冻结了裸调用数, `verify_battle_determinism` 同种子比指纹。
##    ⇒ **本文件一处裸随机都没有**(唯一的掷骰在 `battle._resolve_dmg` 内部, 走的就是 `_battle_rng`)。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 处决 / 冰封 / 僵硬)。
##    ⚠ 094 的石雷是【碑自己在打】, 回钩 on-hit 会让碑触发携带者的命中类装备 = 死人还在出装备效果。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 所有"持续 N 秒 / 每 N 秒"
##    存**到期时刻**或**自管累加器**, 不许拿 `_t` 直接和常数比。
##    ⇒ 091 的 0.25 秒、094 的 3 秒、石雷落时、立碑升起, **四处全是自管累加器**,
##      本文件里 `battle._t` 只出现在 `buffs` 的 `until` 字段(那是绝对时刻, 正确用法)。
##
## ══════════════════════════════════════════════════════════════════════
##  本批的分派落点(主会话已接好)
## ══════════════════════════════════════════════════════════════════════
##   091 → `tick_unit`(每 0.25 秒回血, 生命 <25% 时翻 6 倍)
##   094 → `on_death`(立碑) + `tick`(碑的全队光环 + 每 3 秒石雷)
## ★091 已从 EQ_PERIOD 2.5 秒摘掉(节拍从 2.5 秒改成 0.25 秒, 自管累加器更准);
##   094 也摘掉了 —— 它现在是阵亡触发, 不是周期件。
## ★093 香火石【不在本批】—— 它要动 GameState 存档链, 归主会话。本文件不碰 093。
##
## ══════════════════════════════════════════════════════════════════════
##  ⚠ 诚实记录: 规格没写死、由我(实装侧)定的地方
## ══════════════════════════════════════════════════════════════════════
## ① **091 多带同一件取【最高星】, 不叠加。**
##    规格 §0.5 ★091 没提多件。取的是契约 §4 的全表通用口径「同一件装备装多把 →
##    取星级更高的那一件, 不是相加」, 也与 ★094「一只龟装 3 件只立一座碑(取最高星)」同向。
##    另一侧是"三件各回各的"(3★ 三件 = 每秒 108 + 0.6% 最大生命), 与全表口径冲突, 没取。
##
## ② **091 的回血走 `silent = true`。**
##    规格只说"能被治疗削减影响"(已满足: 走标准 `_heal` 通道)。silent 只关**治疗音效**,
##    不关绿字 —— 绿字仍由 `_heal_acc` 合并后弹出(玩家看得见每秒回了多少)。
##    取 silent 是因为这件 **4 跳/秒**, 不静音会把治疗音刷成蜂鸣(同吸血/毒的既有做法)。
##
## ③ **094 的石雷用【立碑者】当伤害来源 `src`。**
##    规格没写"碑的攻击算谁的"。取立碑者是因为:(a) `_apply_damage_from` 需要一个
##    带 `crit`/`armor_pen`/`dmg_dealt` 的 `src`;(b) 结算面板上这段伤害记在
##    "留下碑的那只龟"名下, 因果最清楚。副作用是石雷**吃立碑者的暴击率与魔法穿透**
##    (它已经死了, `alive=false` ⇒ **不会吸血**, 见 `battle_damage.gd:254`)。
##    另一侧是造一个"碑"的合成 src 字典 —— 那会多出一个不在 `_units` 里的假单位, 更脏。
##
## ④ **094 的石雷伤害在【石块落地那一刻】结算, 不在发射那一刻。**
##    落时 T = √(2H/g) = 0.5 秒, 由 `RelicEqVfx.fall_time` 定死。
##    ★这**不违反**「数值测试不许依赖演出 tween」—— 在途表由**本系统自己的 `tick(delta)`**
##      推进(不是 tween、不是 `create_timer`), 而且结算被抽成独立函数 `stele_bolt_land()`,
##      门禁既能直调它验数值、也能同步喂 tick 验端到端。
##    另一侧是"发射即结算、石块只是装饰" —— 那会让伤害数字比石头早半秒跳出来。
##
## ⑤ **094 的碑不是单位, 是本系统对象上的一条记录 + 一组 `_world` 节点。**
##    规格要求"不可选中、敌人打不掉"。做成单位再打 `untargetable` 标记的话, 全工程
##    二十多处选靶/AOE/团灭判定都要各自认这个标记(memory [[fb-hand-rolled-copies-drift]]);
##    做成非单位则**天然**满足 —— 索敌根本看不见它。
##    ★代价: 碑的状态**不能**存在携带者的单位字典里(那个字典换路会被整体丢弃),
##      存在 `_steles` 上, `clear_all()` 清干净。
##
## ⑥ **094 的光环用 `battle._is_ally(立碑者, o)` 判友军, 不是 `side == side`。**
##    驯服(真换队)与赛博侵入(孤军)两种语义只有这个原语办得对。
##
## ⑦ **石雷的目标在【落地那一刻】若已死, 这一发空落(不改打别人)。**
##    规格写的是"向最近的敌人砸下", 目标是发射时选的。
##
## ══════════════════════════════════════════════════════════════════════
##  ⚠ 诚实记录: 我发现但【不能自己改】的两处共享文件问题(见交付报告)
## ══════════════════════════════════════════════════════════════════════
## ·【A】批④ 六个系统的 `clear_all()` **目前没有任何调用者** ——
##   `dual_lane_flow.gd:469` 那个换路撤场循环只列了 spirit/potion/food/bow/venom 五个,
##   批④ 的 `_b4_all()` 不在里面。⇒ 本文件自己加了 `_sweep()` 兜底(每 0.5 秒查一次
##   立碑者还在不在 `battle._units` 里, 不在就自清), 保证"每路一次"这条口径**现在就成立**;
##   但正规的接线仍应由主会话补进 `dual_lane_flow.gd`。
## ·【B】`_eq_tick`(批④ 全局 `tick` 的唯一驱动)挂在 `if not u.get("equips", []).is_empty()`
##   之内 ⇒ 场上**一个带装备的活单位都没有**时, 碑会停摆。实战中双方统领都带装备,
##   触发不到; 但这是真实的耦合, 记在这里。

var battle
## 演出层。★由本类持有而不是挂进 `BattleVfx` —— 契约禁止改 `scripts/scenes/battle/` 的既有文件,
##   而 RelicEqVfx 是我自己新建的那一个。
var vfx: RelicEqVfx

## 094 已经立起来的碑(**全局表**, 不是携带者字典的字段 —— 见文件头诚实记录 ⑤)。
## 每条: {carrier, si, pos, t(石雷累加器), age, n_bolt, h(演出句柄)}
var _steles: Array = []
## 094 在途石雷: {carrier, tgt, si, t, T} —— 由本系统的 `tick()` 推进, 不是 tween。
var _bolts: Array = []
## 换路自愈的自扫节拍(秒)与累加器 —— 见文件头诚实记录【A】。
const SWEEP_IV := 0.5
var _sweep_t := 0.0


func _init(b) -> void:
	battle = b
	vfx = RelicEqVfx.new(b)


## 身上这件装备的【最高星】下标(0/1/2); 没带返回 -1。
## ★契约 §4 全表通用口径:「同一件装备装多把 → 取星级更高的那一件, 不是相加」。
func _best_si(u: Dictionary, iid: String) -> int:
	var best := -1
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == iid:
			best = maxi(best, clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1)
	return best


# ══════════════════════════════════════════════════════════════════
#  §091 远古龟甲片 (遗物·1 费)
#  「携带者每 0.25 秒回复 1/2/3 点 + 0.1/0.15/0.2% 最大生命值。
#    这个效果在生命值低于 25% 时翻 6 倍。」
#  ✅ 用户 2026-08-06 拍板: 严格「低于」25%(不含等于) · 能被【治疗削减】影响。
# ══════════════════════════════════════════════════════════════════

## 回复节拍(秒)。★自管累加器, **不拿 `battle._t` 和常数比**(CLAUDE.md §3.4)。
const SCUTE_IV := 0.25
## 爆发门槛: 生命值**低于** 25%。★严格小于, 不含等于 —— 用户 2026-08-06 原话「低于」。
const SCUTE_LOW_GATE := 0.25
## 爆发倍率: 翻 6 倍。★演出侧的甲片亮度 = √6 倍, 那个 √ 在 `RelicEqVfx.pulse_amp` 里,
##   **6 这个数只有这一份**, 不在演出层抄第二遍。
const SCUTE_LOW_MULT := 6.0
## 一帧最多补几跳。防御性: 正常 `_process` 已把 delta 钳到 0.1(≤1 跳), 这条只在
## 门禁同步喂大 delta / 极端卡帧时起作用, 免得一帧回上百跳。
const SCUTE_CATCHUP_CAP := 8


## 每帧逐单位推进。★守卫是 `_b4_eq`(EquipStatsApply 写)+ 本函数的 `_best_si` ——
##   `_eq_tick` 把它放在 EQ_TICK(2.5 秒)闸【之前】, 所以这里拿得到每帧精度。
func tick_unit(u: Dictionary, delta: float) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var si: int = _best_si(u, "p2eq_091")
	if si < 0:
		return
	var acc: float = float(u.get("_scute_acc", 0.0)) + maxf(delta, 0.0)
	var n := 0
	while acc >= SCUTE_IV and n < SCUTE_CATCHUP_CAP:
		acc -= SCUTE_IV
		n += 1
	u["_scute_acc"] = acc
	for _i in range(n):
		scute_heal_once(u, si)


## 一跳的**请求回复量**(治疗削减/治疗加成之前的量)。
## ★flat + maxHp × pct, 血量低于门槛时整体 ×6。
## ⚠ 装备/龟的 hp 数值已是最终值, **不再乘 HP_MULT**(CLAUDE.md §3.1)——
##   这里的百分比是对 `maxHp` 取的, 也不涉及 HP_MULT。
func scute_amount(u: Dictionary, si: int) -> float:
	var flat: float = [1.0, 2.0, 3.0][clampi(si, 0, 2)]
	var pct: float = [0.001, 0.0015, 0.002][clampi(si, 0, 2)]
	var amt: float = flat + float(u.get("maxHp", 0.0)) * pct
	return amt * scute_mult(u)


## 本跳的倍率: 低于 25% → 6.0, 否则 1.0。**严格小于**(25.0% 整不翻)。
func scute_mult(u: Dictionary) -> float:
	var mx: float = float(u.get("maxHp", 0.0))
	if mx <= 0.0:
		return 1.0
	return SCUTE_LOW_MULT if float(u.get("hp", 0.0)) / mx < SCUTE_LOW_GATE else 1.0


## 结算一跳。返回**实际**回复量(满血=0)。
## ★走标准 `_heal` 通道 ⇒ 天然吃【治疗削减】与【治疗加成】与决胜期 ×50%(用户拍板"能")。
## ★`_scute_n` 是同步的触发证据(供门禁), 不是"看 tween 有没有多一个"那种假断言。
func scute_heal_once(u: Dictionary, si: int) -> float:
	var mult: float = scute_mult(u)
	var amt: float = scute_amount(u, si)
	if amt <= 0.0:
		return 0.0
	var got: float = battle._damage._heal(u, amt, true)
	u["_scute_n"] = int(u.get("_scute_n", 0)) + 1
	u["_scute_last"] = got
	if vfx != null:
		vfx.scute_pulse(u, clampi(si, 0, 2), mult)
	return got


# ══════════════════════════════════════════════════════════════════
#  §094 祖龟碑 (遗物·4 费)
#  「携带者阵亡时, 在原地立起一座祖龟碑(不可选中), 存续到本路结束。
#    碑向全体友军持续提供 +12/22/35% 增伤 与 +18/32/50 双抗,
#    并每 3 秒向最近的敌人砸下一道石雷, 造成 130/260/500 魔法伤害。」
# ══════════════════════════════════════════════════════════════════

## 石雷节拍(秒)。★自管累加器(每座碑一份), 不碰 `battle._t`。
const STELE_BOLT_IV := 3.0
## 一次 tick 最多补几发石雷(同 SCUTE_CATCHUP_CAP 的理由)。
const STELE_CATCHUP_CAP := 4
## 石雷伤害数字的颜色(暖岩)。
const BOLT_COL := Color(0.86, 0.62, 0.36, 1.0)


## 携带者阵亡 → 立碑。
## ★`_eq_on_death` 会按 equips **逐件**调本函数 ⇒ 装 3 件会进来 3 次,
##   所以这里按【立碑者】去重并取最高星(用户口径:「一只龟装 3 件只立一座碑, 取最高星」)。
func on_death(u: Dictionary, eid: String, si: int) -> void:
	if eid != "p2eq_094":
		return
	if not (u is Dictionary) or not u.has("pos"):
		return
	stele_raise(u, clampi(si, 0, 2))


## 碑给全体友军的**增伤**(百分比小数)。
func stele_amp(si: int) -> float:
	return [0.12, 0.22, 0.35][clampi(si, 0, 2)]


## 碑给全体友军的**双抗**(护甲与魔抗各 +N, 固定值)。
func stele_res(si: int) -> float:
	return [18.0, 32.0, 50.0][clampi(si, 0, 2)]


## 一道石雷的**魔法伤害基数**(过 `_resolve_dmg` 前的裸值)。
func stele_bolt_base(si: int) -> float:
	return [130.0, 260.0, 500.0][clampi(si, 0, 2)]


## 立一座碑(或把已有的那座升星)。返回这座碑的记录。
func stele_raise(carrier: Dictionary, si: int) -> Dictionary:
	for st in _steles:
		if is_same(st["carrier"], carrier):       # is_same: 单位字典互引成环, == 会深比较→卡死
			st["si"] = maxi(int(st["si"]), si)
			return st
	var st2 := {
		"carrier": carrier,
		"si": clampi(si, 0, 2),
		"pos": Vector2(carrier["pos"]),           # 原地: 阵亡那一刻的位置, 之后不再跟随
		"t": 0.0,
		"age": 0.0,
		"n_bolt": 0,
		"h": {},
	}
	_steles.append(st2)
	if vfx != null:
		st2["h"] = vfx.raise_stele(st2["pos"], st2["si"])
		vfx.drop_scutes(carrier)                  # 死了就把 091 的甲片环收掉(同一只龟可能两件都带)
	return st2


## 场上有几座碑(门禁/调试用)。
func stele_count() -> int:
	return _steles.size()


# ── 光环 ──────────────────────────────────────────────────────────
#  ★全场生效、**不设半径**(用户拍板: 死在角落就失效的话这件会变成运气件)。
#  ★不同携带者各自立碑, 但光环**不叠加、取最高**(否则三件 = +105% 增伤)。
#  ★「全体友军」**排除龟蛋与训龟大师**(全表通用口径, 用户 2026-08-06 定)。

## 一只单位当前该吃第几星的光环; 没有就是 -1。
func aura_si_for(o: Dictionary) -> int:
	if not (o is Dictionary) or not o.get("alive", false):
		return -1
	if o.get("_isEgg", false) or o.get("is_trainer", false):
		return -1                                  # 排除龟蛋与训龟大师
	var best := -1
	for st in _steles:
		var c = st["carrier"]
		if c is Dictionary and battle._is_ally(c, o):
			best = maxi(best, int(st["si"]))       # 取最高, 不相加
	return best


## 每帧把光环写到全场单位上(幂等 —— 值没变就一行都不动)。
func _aura_tick() -> void:
	var marked: Array = []
	for o in battle._units:
		if not (o is Dictionary):
			continue
		var si: int = aura_si_for(o)
		_aura_write(o, si)
		if si >= 0:
			marked.append(o)
	if vfx != null:
		vfx.set_marks(marked)


## 幂等地把 si 档光环写到 o 上; si < 0 = 撤销。
##
## ★两条通道是**不同**的, 混用就会踩坑:
##   · 增伤 `damage_amp` 是**裸字段**(`_recalc_stats` 不碰它)⇒ 只能按**差量**加减,
##     否则重复施加会一路涨上去。
##   · 双抗 `def`/`mr` **每次 `_recalc_stats` 都会从 `base_* + buffs` 重算**
##     (RealtimeBattle3DScene.gd:6596)⇒ 直接写 `u["def"]` 下一帧就被抹掉,
##     必须走 `buffs` 通道, 并且**只留自己那一条**(重写不 append 第二条, 同 092 的做法)。
func _aura_write(o: Dictionary, si: int) -> void:
	var amp: float = stele_amp(si) if si >= 0 else 0.0
	var res: float = stele_res(si) if si >= 0 else 0.0
	var cur_amp: float = float(o.get("_stele_amp", 0.0))
	var cur_res: float = float(o.get("_stele_res", 0.0))
	if absf(cur_amp - amp) < 1e-9 and absf(cur_res - res) < 1e-9:
		return
	o["damage_amp"] = float(o.get("damage_amp", 0.0)) + (amp - cur_amp)
	o["_stele_amp"] = amp
	var kept: Array = []
	for b in o.get("buffs", []):
		if not bool((b as Dictionary).get("_stele", false)):
			kept.append(b)
	if res > 0.0:
		# ★不设自然到期: 碑存续到本路结束, 由 clear_all / _sweep 撤。给一个远期 until
		#   只是为了不被 `_tick_unit` 的 buff 过期清理顺手删掉(那里判的是 `_t < b.until`)。
		var due: float = float(battle._t) + 86400.0
		kept.append({"stat": "def", "amount": res, "pct": false, "until": due, "_stele": true})
		kept.append({"stat": "mr", "amount": res, "pct": false, "until": due, "_stele": true})
	o["buffs"] = kept
	o["_stele_res"] = res
	battle._recalc_stats(o)


## 把全场的碑光环撤干净(换路 / 撤场)。
func _aura_strip_all() -> void:
	for o in battle._units:
		if o is Dictionary and (o.has("_stele_amp") or o.has("_stele_res")):
			_aura_write(o, -1)
			o.erase("_stele_amp")
			o.erase("_stele_res")


# ── 石雷 ──────────────────────────────────────────────────────────

## 发射一道石雷: 选靶 + 起石块。返回在途记录; 没有可打的敌人时返回 {}。
##
## ★选靶走 `battle._targeting._nearest_enemy_from(carrier, 碑的位置)` ——
##   **不要就地手写**(memory [[fb-hand-rolled-copies-drift]]: 那份排除规则含
##   黑洞期不可选 / 龟蛋围栏 / 训龟大师不被主动索敌, 抄一次就永远落后一次)。
##   用 `_from` 版本是因为**碑的位置不是携带者当前位置** —— 携带者已经死了, 而
##   "最近的敌人"应当以**碑**为原点算。
func stele_fire(st: Dictionary) -> Dictionary:
	var carrier = st.get("carrier", null)
	if not (carrier is Dictionary):
		return {}
	var pos: Vector2 = st["pos"]
	var tgt = battle._targeting._nearest_enemy_from(carrier, pos)
	if tgt == null or not (tgt is Dictionary) or not tgt.get("alive", false):
		return {}
	var si: int = int(st["si"])
	var b := {
		"carrier": carrier, "tgt": tgt, "si": si,
		"t": 0.0, "T": maxf(RelicEqVfx.fall_time(RelicEqVfx.BOLT_H, RelicEqVfx.BOLT_G), 0.001),
		"pos": Vector2(tgt["pos"]),
	}
	_bolts.append(b)
	st["n_bolt"] = int(st.get("n_bolt", 0)) + 1
	if vfx != null:
		vfx.stone_bolt(b["pos"], si)
		## ★碑基石台在"真的发射了一发"这一帧亮一下 —— 演出侧**没有自己的秒表**,
		##   它读不到 3 秒节拍, 只被这一行推。节拍改了演出自动跟着改。
		vfx.stele_flash(st.get("h", null))
	return b


## 石块落地 → 结算。返回**实发伤害**(没打到返回 0)。
## ★把结算从演出里抽出来的那一份(契约 §7 / CLAUDE.md §3.5): 落地时调它, 门禁也直调它。
## ★`from_equip = true`(口径②): 碑是装备打出来的, 不回钩 on-hit / 处决 / 冰封 / 僵硬。
func stele_bolt_land(b: Dictionary) -> int:
	var carrier = b.get("carrier", null)
	var tgt = b.get("tgt", null)
	if not (carrier is Dictionary) or not (tgt is Dictionary) or not tgt.get("alive", false):
		return 0
	var si: int = clampi(int(b.get("si", 0)), 0, 2)
	var dmg: int = battle._resolve_dmg(carrier, stele_bolt_base(si), tgt, true)
	battle._damage._apply_damage_from(carrier, tgt, dmg, BOLT_COL, 0.0, false, true)
	# 同步的落地证据(供门禁)。★不是"看演出多了几个节点"那种假断言 ——
	#   `_kill` 里别的死亡效果也会建节点, 那种断言反向验证时不会红。
	b["landed"] = int(b.get("landed", 0)) + 1
	tgt["_stele_bolt_n"] = int(tgt.get("_stele_bolt_n", 0)) + 1
	return dmg


# ══════════════════════════════════════════════════════════════════
#  §每帧全局推进
# ══════════════════════════════════════════════════════════════════

## 每帧全局推进: 碑升起 / 石雷节拍 / 在途石块 / 全队光环 / 演出。
## ★`EquipSystem._eq_tick` 已用帧号去重, 这里一帧只会被调一次。
func tick(delta: float) -> void:
	var d: float = maxf(delta, 0.0)
	_sweep(d)
	for st in _steles:
		st["age"] = float(st.get("age", 0.0)) + d
		var t: float = float(st.get("t", 0.0)) + d
		var n := 0
		while t >= STELE_BOLT_IV and n < STELE_CATCHUP_CAP:
			t -= STELE_BOLT_IV
			n += 1
		st["t"] = t
		for _i in range(n):
			stele_fire(st)
	var keep: Array = []
	for b in _bolts:
		b["t"] = float(b["t"]) + d
		if float(b["t"]) >= float(b["T"]):
			stele_bolt_land(b)
			continue
		keep.append(b)
	_bolts = keep
	if not _steles.is_empty():
		_aura_tick()
	if vfx != null:
		vfx.tick(d)


## 换路自愈(见文件头诚实记录【A】: 批④ 的 `clear_all` 目前没有调用者)。
## 换路时 `_dl_clear_units` 会 `battle._units.clear()` 再重建一批**全新的**单位字典 ⇒
## 立碑者不再在 `battle._units` 里就是"换路了"的确凿证据。
## ★每 0.5 秒查一次而不是每帧: 这是 O(碑数 × 单位数) 的引用扫描。
func _sweep(delta: float) -> void:
	if _steles.is_empty() and _bolts.is_empty():
		_sweep_t = 0.0
		return
	_sweep_t += delta
	if _sweep_t < SWEEP_IV:
		return
	_sweep_t = 0.0
	for st in _steles:
		if not battle._arr_has_unit(battle._units, st["carrier"]):
			clear_all()
			return


# ══════════════════════════════════════════════════════════════════
#  §未用到的钩子 —— 本批两件都不挂这些, 留空是接口要求, 不是漏实现
# ══════════════════════════════════════════════════════════════════

## 携带者登场(每路开战跑一次)。091/094 都不需要: 091 的累加器懒建、094 是阵亡触发。
func on_spawn(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 携带者普攻发出。本批不用。
func on_basic(_u: Dictionary, _tgt, _eid: String, _si: int) -> void:
	pass


## 携带者命中结算后。本批不用。
func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者受到伤害后(★两条伤害路径都会调, CLAUDE.md §3.3)。本批不用 ——
## 091 的血量门槛是**每帧连续判**的(`scute_mult`), 不是"受伤那一刻判一次",
## 所以挂受伤钩反而会漏掉"被治疗拉回 25% 以上"这一半。
func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者受到法术伤害后。本批不用。
func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 法器法力条集满。本批不用(只有 D 路 088/089/090 用)。
func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


# ══════════════════════════════════════════════════════════════════
#  §撤场
# ══════════════════════════════════════════════════════════════════

## ★换路撤场: 碑清除、在途石雷丢弃、全队光环撤掉、演出节点全 free。
##   漏了就会把上一路的碑(和它的 +35% 增伤 / +50 双抗)带进下一路。
func clear_all() -> void:
	_aura_strip_all()
	_steles.clear()
	_bolts.clear()
	_sweep_t = 0.0
	if vfx != null:
		vfx.clear_all()
