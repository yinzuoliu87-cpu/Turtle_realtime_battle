class_name EqBowBatch
extends RefCounted
## eq_bow_batch.gd — 弓箭四件新装备的效果本体
## 073 藤蔓弓弦 · 074 鲸骨胸甲 · 075 测距绳结 · 076 连发弩机
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数没改。
## 分工与接口 = `docs/plans/20260805-实装契约.md`。演出层在 `scripts/scenes/battle/bow_eq_vfx.gd`。
##
## ══════════════════════════════════════════════════════════════════════
##  分派落点(全部挂在【已有的】钩子上, 没有新增分发口)
## ══════════════════════════════════════════════════════════════════════
##   073 → `_eq_on_basic_attack`(藤蔓箭)      + 周期 0.25s(攻速 buff 到期 + 小球跟随)
##   074 → `_eq_on_basic_attack`(护盾 + 魔伤)
##   075 → 周期 6.0s(箭雨)                     + `_eq_on_hit`(距离增伤)
##   076 → `_eq_on_basic_attack`(每第三下腐蚀) + `_eq_on_cast`(起连射) + 周期 0.25s(逐发射出)
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(契约 §5, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**(073 藤蔓箭选靶 / 076 连射选靶 / 075 落点散布)。
##    裸 `randi()`/`randf()`/`randfn()` 会破坏确定性 —— `tools/rng_discipline.py` 冻结了裸调用数,
##    `verify_battle_determinism` 同种子比指纹, 加一个裸随机两处一起红, 而且看着像别的问题。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 弓箭处决 / 冰封 / 僵硬)。
##    用户对 073/075/076 三件都明确写了"不触发 on-hit", 074 的附带魔伤同口径(契约 §5.7)。
##    ⚠ 076 一次连射最多 42 发 × 每发贯穿数人, 回钩 on-hit 会直接自激炸掉。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 本文件所有"持续 N 秒 / 每 N 秒"
##    都存**到期时刻**或**自管累加器**, 没有一处拿 `_t` 直接和常数比。
##
## ══════════════════════════════════════════════════════════════════════
##  ⚠ 诚实记录: 规格没写死、由我定的两处
## ══════════════════════════════════════════════════════════════════════
## · **075 的距离增伤取【连续】不取【每满 100 码一档】。** 用户原文"目标每距携带者 100 码
##   +3/4/5% 增伤, 不封顶", 两种读法在他给的量级表(400/600/1000/1600 码)上**给出完全一样的数**,
##   分不开。取连续是因为它同样适用于箭雨 —— 箭雨一跳会同时打到十几个距离各异的敌人,
##   分档会在整百码处出现肉眼可见的伤害跳变。差距最多一档(3/4/5%)。
## · **073 的藤蔓箭暴击时照吃全局暴伤倍率。** 用户写的是"可单独暴击 + 暴击转真伤 + 给攻速",
##   没说暴击要不要放大伤害。本项目所有暴击都走 `DamageMath.crit_multiplier`, 这里若不乘,
##   "暴击"就只是一个换伤害类型的开关、不是暴击。取与全项目一致的那一侧。
##   (量级表里的"3★ 每发 45% ATK"是**未暴击**的基线, 与这条不冲突。)

var battle
## 演出层。★由本类持有而不是挂进 `BattleVfx` —— 契约禁止改 `scripts/scenes/battle/*`
##   的既有文件, 而 BowEqVfx 是我自己新建的那一个。
var _vfx: BowEqVfx

## 正在下的箭雨 [{src, si, center, hops_left, t_next}] —— **全局表**, 由 `tick()` 推进。
## ★存在系统上而不是携带者身上: 箭雨放出去之后就与携带者脱钩(携带者中途死了雨照下完)。
var _rains: Array = []
## 正在打的连射 [{src, si, shots_left, t_next}]。同上。
var _volleys: Array = []
## 身上挂着**常驻演出件**(073 小球 / 074 骨甲)的单位。
## ★存单位字典进 Array 是允许的(禁止的是拿它当 **Dictionary 的键** —— CLAUDE.md §3.2);
##   查在不在一律用 `battle._arr_has_unit`, 不用 `in` / `.has()`(那两个走深比较会卡死)。
var _owners: Array = []
## 自扫节拍(秒)与累加器 —— 见 `_sweep` 的注释。
const SWEEP_IV := 0.5
var _sweep_t := 0.0


func _init(b) -> void:
	battle = b
	_vfx = BowEqVfx.new(b)


# ══════════════════════════════════════════════════════════════════
#  §073 藤蔓弓弦 (弓箭·1费)
#  「携带者身上获得一个藤蔓小球。每次普攻时, 小球向随机目标射出藤蔓箭,
#    造成 20/30/45% ATK 物理伤害。藤蔓箭可单独暴击; 暴击时转为真实伤害,
#    同时携带者获得持续 2 秒的 20/25/30% 攻击速度(刷新不叠加)。」
# ══════════════════════════════════════════════════════════════════

## 攻速 buff 的持续秒数(用户原文"持续 2 秒")
const VINE_ASPD_SEC := 2.0


## 每次普攻: 小球射一支藤蔓箭。
## ★目标是**随机敌人**, 用 `battle._battle_rng`(口径①)。
## ★选靶走 `_pick_enemies_of` 而不是 `_enemies_of` —— 前者排除训龟大师(场外监视者)与
##   不可选中单位。手抄一份"随便挑个敌人"就是 memory [[fb-hand-rolled-copies-drift]] 那条坑。
func on_basic_073(u: Dictionary, si: int) -> void:
	_vine_expire(u)                                     # 先结算上一次 buff 到期, 再谈这一次
	if not u.get("alive", false):
		return
	var es: Array = battle._targeting._pick_enemies_of(u)
	if es.is_empty():
		return
	var t: Dictionary = es[battle._battle_rng.randi() % es.size()]
	if not t.get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_073", {})
	var base: float = float(u.get("atk", 0.0)) * [0.20, 0.30, 0.45][si]
	## 藤蔓箭【单独掷一次暴击】, 用的是携带者自己的暴击率(用户拍板)。
	var crit: bool = battle._battle_rng.randf() < minf(float(u.get("crit", 0.0)), 1.0)
	_note_owner(u)
	_vfx.ensure_orb(u)
	_vfx.orb_fire(u, t["pos"], crit)
	if crit:
		## 暴击 → 转【真实伤害】(不吃护甲/减伤) + 全局暴伤倍率(见文件头"诚实记录"第二条)。
		## ★`pre_crit = true`: 不加这个, `_apply_damage_from` 会在真伤段【再掷一次暴击】
		##   (battle_damage.gd:「真伤暴击」那段) ⇒ 一发藤蔓箭掷两次骰, 期望值直接错。
		var dmg: int = maxi(1, int(round(base * DamageMath.crit_multiplier(
			float(u.get("crit", 0.0)), float(u.get("crit_dmg", 1.5))))))
		battle._damage._apply_damage_from(u, t, dmg, Color("#fff2a0"), 0.0, true, true, true)
		_vine_grant_aspd(u, si, stt)
	else:
		var raw: float = base
		battle._damage._apply_damage_from(u, t, battle._phys_after_armor(u, raw, t),
			Color("#8ce860"), 0.0, false, true)
	stt["vine_shots"] = int(stt.get("vine_shots", 0)) + 1   # 同步触发证据(供门禁, 不必等演出)
	u["eq_state"]["p2eq_073"] = stt


## 给携带者上 2 秒攻速 buff。**刷新不叠加**。
##
## ★为什么用 `aspd_perm`(累加通道)而不是 `spd_aspd_mult`(限时槽):
##   限时槽是**全场共用的一个 slot**(冰龟减攻速 / 彩虹冰寒都写它), 我写进去会把别人
##   5 秒的减速时长砍成我的 2 秒。`aspd_perm` 是纯累加, 各家互不覆盖 —— 代价是
##   到期得自己收回来, 所以有 `_vine_expire` —— 每次普攻查一次 + **每帧** `tick()` 查一次
##   (不排 0.25 秒周期口: 那会把用户写死的"2 秒"变成 2~2.25 秒)。
## ★"刷新不叠加"的实现 = **只记一份增量**: 已经挂着就只把到期时刻往后推;
##   多带一件更高星的会把增量升到更高的那个(而不是加两份)。
func _vine_grant_aspd(u: Dictionary, si: int, stt: Dictionary) -> void:
	var want: float = [0.20, 0.25, 0.30][si]
	var given: float = float(stt.get("vine_aspd_given", 0.0))
	if want > given:
		u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + (want - given)
		stt["vine_aspd_given"] = want
	stt["vine_aspd_until"] = battle._t + VINE_ASPD_SEC
	stt["vine_crits"] = int(stt.get("vine_crits", 0)) + 1   # 同步触发证据(供门禁)
	u["eq_state"]["p2eq_073"] = stt


## 攻速 buff 到期 → 把增量原样收回(不是"设回 1.0" —— 别人加的还在里面)。
func _vine_expire(u: Dictionary) -> void:
	var stt: Dictionary = u.get("eq_state", {}).get("p2eq_073", {})
	var given: float = float(stt.get("vine_aspd_given", 0.0))
	if given <= 0.0:
		return
	if battle._t < float(stt.get("vine_aspd_until", 0.0)):
		return
	u["aspd_perm"] = maxf(0.01, float(u.get("aspd_perm", 1.0)) - given)
	stt["vine_aspd_given"] = 0.0
	u["eq_state"]["p2eq_073"] = stt


## 攻速 buff 的到期由**每帧** `tick()` 收(见 `_tick_orbs`), 不占周期口 ——
## 排进 `EQ_IV_BATCH1` 会把"2 秒"的精度降到 0.25 秒(最多多给 12.5%)。


# ══════════════════════════════════════════════════════════════════
#  §074 鲸骨胸甲 (弓箭·1费)
#  「每次普攻使自己获得 2/3/4% 最大生命值护盾; 每次普攻还附带 10/20/30 魔法伤害。」
# ══════════════════════════════════════════════════════════════════

## 每次普攻: 给自己叠护盾 + 给目标补一段魔法伤害。
##
## ★护盾**不设时限**(dur=0 = 永久), 且 2026-08-05 起**没有全局上限**了 ——
##   `_grant_shield` 里那条"封顶 1.5×最大生命"的 `SHIELD_CAP_MULT` 是 2026-06-27
##   搭雏形时随手写下、零注释零测试的遗留值, 用户看到后原话「哪来的上限啊, 不应该有啊」, 已删。
##   ⇒ 本件是真的可以一直叠上去的, 门禁里那条"灌 60 下普攻"验的就是它没有天花板。
## ★附带魔伤**不掷暴击**: 用户写的是固定值 10/20/30, 没说它能暴。这里直接算魔抗减免
##   (同 `battle._phys_after_armor` 对物理的做法), 顺带**不消耗一次 RNG** —— 少一次掷骰
##   就少一处影响确定性指纹的地方。
func on_basic_074(u: Dictionary, tgt, si: int) -> void:
	if not u.get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_074", {})
	var amt: float = float(u.get("maxHp", 0.0)) * [0.02, 0.03, 0.04][si]
	if amt > 0.0:
		battle._damage._grant_shield(u, amt)
		stt["bone_layers"] = int(stt.get("bone_layers", 0)) + 1
		stt["bone_total"] = float(stt.get("bone_total", 0.0)) + amt
	if tgt is Dictionary and (tgt as Dictionary).get("alive", false):
		var flat: float = [10.0, 20.0, 30.0][si]
		battle._damage._apply_damage_from(u, tgt, _magic_after_mr(u, flat, tgt),
			Color("#9be7ff"), 0.0, false, true)
	u["eq_state"]["p2eq_074"] = stt
	## 演出: 甲片数 = 叠了几层(离散可数), 壳半径 = 累计护盾的【立方根】(体积律, 见 BowEqVfx §②)
	_note_owner(u)
	var mx: float = maxf(1.0, float(u.get("maxHp", 1.0)))
	_vfx.plates_refresh(u, float(stt.get("bone_total", 0.0)) / mx, int(stt.get("bone_layers", 0)))


## 只做魔抗减免、不掷暴击 —— `battle._phys_after_armor` 的魔法版。
## ★公式与 `_resolve_dmg` 的魔法分支逐字一致(DamageMath 那两个静态函数是单一事实源),
##   没有在这里抄第二份减伤曲线。
func _magic_after_mr(u: Dictionary, raw: float, tgt: Dictionary) -> int:
	var resist: float = DamageMath.effective_resist(float(tgt.get("mr", 0.0)),
		float(u.get("magic_pen_pct", 0.0)), float(u.get("magic_pen", 0.0)))
	var d: float = raw * DamageMath.resist_multiplier(resist)
	d *= 1.0 + float(u.get("damage_amp", 0.0))
	d *= 1.0 - float(tgt.get("damage_reduction", 0.0))
	return maxi(1, int(round(d)))


# ══════════════════════════════════════════════════════════════════
#  §075 测距绳结 (弓箭·2费)
#  「① 每 6 秒放一轮箭雨: 落点取敌人最密集处, 半径 400 码, 持续 1.5 秒,
#      每 0.25 秒造成 0.25/0.35/0.5 ATK 物理伤害 和 3/4/5 层流血。
#    ② 目标每距携带者 100 码, 携带者对该目标 +3/4/5% 增伤, 不封顶(箭雨自己也吃)。」
# ══════════════════════════════════════════════════════════════════

## 箭雨半径(码) —— 用户原文"半径 400 码"
const RAIN_RADIUS := 400.0
## 每跳间隔(秒)与总跳数: 1.5 秒 ÷ 0.25 = 6 跳(用户原文)
const RAIN_HOP_IV := 0.25
const RAIN_HOPS := 6
## 增伤的距离刻度(码) —— 用户原文"每距离携带者 100 码"
const AMP_PER_PX := 100.0


## 每 6 秒(经 EQ_IV_BATCH1)开一轮箭雨。
## ★落点取**敌人最密集处**(BowEqVfx.densest_point: 最大覆盖 → 覆盖集质心, 纯几何零 RNG)。
func rain_start(u: Dictionary, si: int) -> void:
	if not u.get("alive", false):
		return
	var es: Array = battle._targeting._pick_enemies_of(u)
	if es.is_empty():
		return
	var pts: Array = []
	for o in es:
		if (o as Dictionary).get("alive", false):
			pts.append(o["pos"])
	if pts.is_empty():
		return
	var center: Vector2 = BowEqVfx.densest_point(pts, RAIN_RADIUS)
	_rains.append({"src": u, "si": si, "center": center, "hops_left": RAIN_HOPS, "t_next": 0.0})
	var stt: Dictionary = u["eq_state"].get("p2eq_075", {})
	stt["rain_n"] = int(stt.get("rain_n", 0)) + 1          # 同步触发证据(供门禁)
	u["eq_state"]["p2eq_075"] = stt
	_vfx.rain_marker(center, RAIN_RADIUS, float(RAIN_HOPS) * RAIN_HOP_IV)


## 箭雨的一跳: 落区内每个敌人吃 0.25/0.35/0.5 ATK 物理 + 3/4/5 层流血。
## ★**同步、可直调** —— 门禁不必等任何演出就能量这一跳打了多少(CLAUDE.md §3.5)。
## ★增伤"适用于箭雨自己"(用户拍板): 这里显式乘 `amp_075`, 因为箭雨走 from_equip=true,
##   不会回钩 on-hit ⇒ 拿不到 `_eq_on_hit` 里那条通用增伤。
## 返回本跳命中的敌人数(门禁分母)。
func rain_hop(u: Dictionary, si: int, center: Vector2) -> int:
	var per: float = float(u.get("atk", 0.0)) * [0.25, 0.35, 0.5][si]
	var stacks: int = [3, 4, 5][si]
	var r2: float = RAIN_RADIUS * RAIN_RADIUS
	var n := 0
	for o in battle._targeting._enemies_of(u):
		if not (o as Dictionary).get("alive", false):
			continue
		if (o["pos"] as Vector2).distance_squared_to(center) > r2:
			continue
		n += 1
		var amp: float = 1.0 + amp_075(u, o, si)
		battle._damage._apply_damage_from(u, o, battle._phys_after_armor(u, per * amp, o),
			Color("#b6e86a"), 0.0, false, true)
		battle._damage._apply_dot_stacks(o, "bleed", stacks, u)
	var stt: Dictionary = u["eq_state"].get("p2eq_075", {})
	stt["rain_hops"] = int(stt.get("rain_hops", 0)) + 1
	u["eq_state"]["p2eq_075"] = stt
	_vfx.rain_arrows(center, RAIN_RADIUS, 7)
	return n


## 被动增伤系数(不含 1.0 基数): 距离 / 100 码 × 3/4/5%, **不封顶**。
## ★连续而不是分档 —— 见文件头"诚实记录"第一条。
static func amp_of(dist_px: float, si: int) -> float:
	return maxf(0.0, dist_px) / AMP_PER_PX * [0.03, 0.04, 0.05][si]


func amp_075(u: Dictionary, tgt: Dictionary, si: int) -> float:
	return amp_of((u["pos"] as Vector2).distance_to(tgt["pos"]), si)


## 每次命中(on-hit): 按距离补一段加伤。
## ★走 `battle._equip_sys._eq_bonus_hit` 这个**共用投递口**(契约 §4「必须复用, 不许另造」):
##   它走 `_apply_damage` 那条路 —— 结构上就不回钩 on-hit(比 from_equip 开关更硬),
##   且 `bucket="tru"` 跳过减伤(on-hit 拿到的 dmg 已经是减伤后的数, 再走一遍会被吃第二遍)。
func on_hit_075(src: Dictionary, tgt: Dictionary, dmg: int, si: int) -> void:
	if not tgt.get("alive", false):
		return
	var amp: float = amp_075(src, tgt, si)
	if amp <= 0.0:
		return
	battle._equip_sys._eq_bonus_hit(src, tgt, float(dmg) * amp, Color("#ffd166"))


# ══════════════════════════════════════════════════════════════════
#  §076 连发弩机 (弓箭·4费)
#  「被动(★只在弓箭羁绊激活时): 每第三下普攻给目标施加 1 层【腐蚀】(与羁绊同一套)。
#    主动: 放技能后每 0.25 秒射一箭, 发数 = 技能消耗龟能 ÷ 5;
#          箭 2000 码贯穿, 每发 0.05/0.06/0.08 ATK 物理 + 9/13/16 真实伤害,
#          每穿一人伤害 ×0.75(最低 25%), 每穿一人偷敌 1/1/2 点龟能给自己。」
# ══════════════════════════════════════════════════════════════════

## 被动: 第几下普攻触发
const CORRODE_EVERY := 3
## 主动: 每消耗这么多龟能 → 多射一发(用户原文"每消耗 5 龟能会射出一发")
const ENERGY_PER_SHOT := 5.0
## 主动: 发间隔(秒)。★与演出的 `BowEqVfx.RECOIL_IV` 是同一个数, 门禁 ④ 焊住两者相等。
const VOLLEY_IV := 0.25
## 贯穿射程(码)
const PIERCE_RANGE := 2000.0
## 贯穿判定的走廊半宽(码)
const PIERCE_HALF_W := 44.0
## 1 点龟能 = 多少秒冷却(实时版口径, 见 EquipSystem._eq_grant_energy)
const ENERGY_SEC := 0.075


## 被动: 每第三下普攻叠 1 层腐蚀。★**只在弓箭羁绊激活时才触发**(用户明确拍板) ——
## 这顺带解决了"无羁绊时腐蚀档位为 0、叠了没加成"的问题。
## ★不吃星级: 用户写的是"施加 1 层腐蚀", 三星同值 ⇒ si 用不上(写成 `_si` 消未使用参数警告)。
func on_basic_076(u: Dictionary, tgt, _si: int) -> void:
	var tier: int = int(battle._synergy.tier_for(u, "弓箭"))
	var stt: Dictionary = u["eq_state"].get("p2eq_076", {})
	var n: int = int(stt.get("cross_hits", 0)) + 1
	stt["cross_hits"] = n
	u["eq_state"]["p2eq_076"] = stt
	if tier <= 0:
		return                                          # ★羁绊没激活 ⇒ 连计数都不该兑现
	if n % CORRODE_EVERY != 0:
		return
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	tgt["corrode_stacks"] = mini(BowSynergySystem.CORRODE_MAX, int(tgt.get("corrode_stacks", 0)) + 1)
	## ★取 max 不是直接赋值: 直接赋值会把目标身上羁绊打的更高档位降下去 = 自己削自己队伍。
	tgt["corrode_tier"] = maxi(int(tgt.get("corrode_tier", 0)), tier)
	stt["cross_corrode"] = int(stt.get("cross_corrode", 0)) + 1   # 同步触发证据(供门禁)
	u["eq_state"]["p2eq_076"] = stt


## 本次施放的技能类型。
## ★状态机在前摇走完时把 `pending` 置成 `"K:<stype>"`(RealtimeBattle3DScene:2453),
##   然后才调 `_eq_on_cast` —— 中间没有任何地方改写它。
##   ⚠ 诚实记录: 钩子签名 `_eq_on_cast(u, tgt)` **不带 stype**, 而加一个入参要改主场景
##     (本批不许碰)。读 pending 是当前唯一不动主场景的取法。
func cast_stype(u: Dictionary) -> String:
	var p: String = str(u.get("pending", ""))
	return p.substr(2) if p.begins_with("K:") else ""


## 发数 = 本次技能消耗的龟能 ÷ 5(向下取整)。
## ★消耗**查 `battle._skill_cost(u, stype)`**, 绝不在这里抄一份消耗表 ——
##   抄一次就永远落后一次(memory [[fb-hand-rolled-copies-drift]])。
func shots_for(u: Dictionary, stype: String) -> int:
	if stype == "":
		return 0
	return int(floorf(float(battle._skill_cost(u, stype)) / ENERGY_PER_SHOT))


## 放完技能 → 排一轮连射。
func on_cast_076(u: Dictionary, si: int) -> void:
	var n: int = shots_for(u, cast_stype(u))
	if n <= 0:
		return
	_volleys.append({"src": u, "si": si, "shots_left": n, "t_next": 0.0})
	var stt: Dictionary = u["eq_state"].get("p2eq_076", {})
	stt["volley_planned"] = int(stt.get("volley_planned", 0)) + n   # 同步触发证据(供门禁)
	u["eq_state"]["p2eq_076"] = stt


## 射一发贯穿箭。返回穿过的人数(门禁分母)。
##
## ★衰减用 `BowEqVfx.pierce_mult(k)` —— **伤害与光迹亮度读的是同一个函数**。
##   抄第二遍的话把产品代码改坏、门禁照样绿(memory [[fb-write-without-reader-and-fake-gates]])。
## ★物理段吃护甲、真伤段不吃 —— 用户写的就是"物理伤害 + 真实伤害"两段。
func volley_shot(u: Dictionary, si: int) -> int:
	if not u.get("alive", false):
		return 0
	var es: Array = battle._targeting._pick_enemies_of(u)
	if es.is_empty():
		return 0
	var aim: Dictionary = es[battle._battle_rng.randi() % es.size()]
	var dir: Vector2 = aim["pos"] - u["pos"]
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	## 走廊内、2000 码以内的敌人, **按距离排序** —— "穿过的第 k 个"这个概念得有先后,
	## 靠 `_units` 的数组顺序是不行的(赛博激光那里踩过)。
	var line: Array = []
	for o in battle._targeting._enemies_of(u):
		if not (o as Dictionary).get("alive", false):
			continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = rel.dot(dir)
		if along < 0.0 or along > PIERCE_RANGE:
			continue
		if (rel - dir * along).length() > PIERCE_HALF_W:
			continue
		line.append({"u": o, "d": along})
	line.sort_custom(func(a, b): return float(a["d"]) < float(b["d"]))
	var phys: float = float(u.get("atk", 0.0)) * [0.05, 0.06, 0.08][si]
	var tru: float = [9.0, 13.0, 16.0][si]
	var steal: float = float([1, 1, 2][si])
	var cuts: Array = []
	var stt: Dictionary = u["eq_state"].get("p2eq_076", {})
	for k in range(line.size()):
		var o: Dictionary = line[k]["u"]
		var mult: float = BowEqVfx.pierce_mult(k)
		battle._damage._apply_damage_from(u, o, battle._phys_after_armor(u, phys * mult, o),
			Color("#ffb060"), 0.0, false, true)
		battle._damage._apply_damage_from(u, o, maxi(1, int(round(tru * mult))),
			Color("#ffffff"), 0.0, true, true, true)
		var got: float = drain_energy(o, steal)
		if got > 0.0:
			battle._equip_sys._eq_grant_energy(u, got)
			stt["volley_stolen"] = float(stt.get("volley_stolen", 0.0)) + got
		cuts.append(clampf(float(line[k]["d"]) / PIERCE_RANGE, 0.0, 1.0))
	stt["volley_fired"] = int(stt.get("volley_fired", 0)) + 1
	stt["volley_pierced"] = int(stt.get("volley_pierced", 0)) + line.size()
	u["eq_state"]["p2eq_076"] = stt
	_vfx.pierce_tracer(u["pos"], dir, PIERCE_RANGE, cuts)
	battle._muzzle_flash(u["pos"], dir, Color("#ffcf8a"))
	return line.size()


## 从敌人身上【偷】走 n 点龟能, 返回**真的偷到多少**。
##
## ★实时版没有 `u["energy"]` 这个字段 —— 龟能 = 技能冷却充能, 1 点 = 0.075 秒
##   (见 `EquipSystem._eq_grant_energy`)。所以"扣龟能" = 把秒数**加回**它的剩余冷却。
## ★镜像 `battle._apply_energy_bank`: 那边从【最快就绪】的技开始扣冷却, 这边就从
##   最快就绪的技开始加回去 —— 两边是同一个排序, 不然"给 1 点"和"扣 1 点"不是逆运算。
## ★每个技的剩余冷却封顶在它自己的满冷却 ⇒ 连射不能把敌人的大招无限往后推。
##   偷不动的部分不算偷到(返回值据实), 携带者也就拿不到那一份 —— 不凭空造龟能。
func drain_energy(u: Dictionary, n: float) -> float:
	if n <= 0.0 or not battle._has_energy_system(u):
		return 0.0
	var left: float = n
	var bank: float = float(u.get("energy_bank", 0.0))
	if bank > 0.0:
		var take: float = minf(bank, left)
		u["energy_bank"] = bank - take
		left -= take
	var cds: Dictionary = u.get("skill_cd", {})
	if left <= 0.0 or cds.is_empty():
		return n - left
	var keys: Array = cds.keys()
	keys.sort_custom(func(a, b): return float(cds[a]) < float(cds[b]))
	var sec_left: float = left * ENERGY_SEC
	for k in keys:
		if sec_left <= 0.0:
			break
		var full: float = float(battle._skill_cd(u, str(k)))
		var room: float = maxf(0.0, full - float(cds[k]))
		var add: float = minf(room, sec_left)
		cds[k] = float(cds[k]) + add
		sec_left -= add
	return n - sec_left / ENERGY_SEC


# ══════════════════════════════════════════════════════════════════
#  §每帧节拍 —— 箭雨/连射的推进 + 演出层推进
#  接线: `EquipSystem._eq_tick` 的第一段(按帧号去重, 同 `_sigwave.tick`)。
#  ★不用 tween: 无头 CI 下 create_tween 推进不稳(CLAUDE.md §3.5), 而且走 sim 的 delta
#    才跟时停/换路同步。
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	_vfx.tick(delta)
	_tick_orbs(delta)
	_tick_rains(delta)
	_tick_volleys(delta)
	_sweep(delta)


## 每帧: ① 藤蔓小球的临界阻尼跟随 ② 073 攻速 buff 到期回收。
## 只扫 `_owners`(带 073/074 的那几只), 不扫全场。
## ★buff 到期放这里而不是排 0.25 秒周期: 排周期会把用户写死的"2 秒"变成 2~2.25 秒。
func _tick_orbs(delta: float) -> void:
	for u in _owners:
		if (u as Dictionary).has("_vine_orb"):
			_vfx.orb_tick(u, delta)
		_vine_expire(u)


## 登记一个"身上有常驻演出件"的携带者(幂等)。
func _note_owner(u: Dictionary) -> void:
	if not battle._arr_has_unit(_owners, u):
		_owners.append(u)


## 自扫: 主人**已经不在 `battle._units` 里**(换路重建)或已阵亡 → 撤掉它的常驻演出件。
##
## ★为什么是自扫而不是在 `dual_lane_flow._dl_next_lane` 里加一行 clear:
##   那是 `scripts/scenes/battle/*` 的既有文件, 本批不许碰(契约 §1)。自扫的代价是
##   最多晚 0.5 秒撤场, 换来的是**零外部接线** —— 没人接线就没有"漏接线"这种失败模式。
## ⚠ 换路后旧单位字典仍然活着(被我这张表引着), 所以判据必须是"还在不在 battle._units",
##   不能只判 `alive` —— 上一路打赢的龟 `alive` 还是 true。
func _sweep(delta: float) -> void:
	_sweep_t += delta
	if _sweep_t < SWEEP_IV:
		return
	_sweep_t = 0.0
	var keep: Array = []
	for u in _owners:
		if battle._arr_has_unit(battle._units, u) and (u as Dictionary).get("alive", false):
			keep.append(u)
			continue
		_vfx.detach(u)
	_owners = keep


## 在途的箭雨/连射也一样: 源头离场(换路)就整条作废, 不许打到新一路的单位身上。
func _alive_here(src) -> bool:
	return src is Dictionary and battle._arr_has_unit(battle._units, src)


func _tick_rains(delta: float) -> void:
	if _rains.is_empty():
		return
	var keep: Array = []
	for r in _rains:
		var src: Dictionary = r["src"]
		if not _alive_here(src):
			continue
		r["t_next"] = float(r["t_next"]) - delta
		while float(r["t_next"]) <= 0.0 and int(r["hops_left"]) > 0:
			r["hops_left"] = int(r["hops_left"]) - 1
			r["t_next"] = float(r["t_next"]) + RAIN_HOP_IV
			rain_hop(src, int(r["si"]), r["center"])
		if int(r["hops_left"]) > 0:
			keep.append(r)
	_rains = keep


func _tick_volleys(delta: float) -> void:
	if _volleys.is_empty():
		return
	var keep: Array = []
	for v in _volleys:
		var src: Dictionary = v["src"]
		if not _alive_here(src) or not src.get("alive", false):
			continue                                    # 携带者阵亡/离场 → 连射停(它是"携带者在射箭")
		v["t_next"] = float(v["t_next"]) - delta
		while float(v["t_next"]) <= 0.0 and int(v["shots_left"]) > 0:
			v["shots_left"] = int(v["shots_left"]) - 1
			v["t_next"] = float(v["t_next"]) + VOLLEY_IV
			volley_shot(src, int(v["si"]))
		if int(v["shots_left"]) > 0:
			keep.append(v)
	_volleys = keep


## 换路 / 战斗结束: 在途的箭雨与连射一律作废, 演出节点全撤。
## (常规换路走 `_sweep` 自扫, 本函数是给"想立刻清干净"的调用方留的口 —— 门禁用它。)
func clear() -> void:
	_rains.clear()
	_volleys.clear()
	for u in _owners:
		_vfx.detach(u)
	_owners.clear()
	_vfx.clear()
