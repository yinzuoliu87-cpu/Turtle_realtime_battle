class_name GadgetSynergySystem
extends RefCounted
## 奇械羁绊【铸币 / 冰封 / 僵硬 / 易碎】（2026-08-03）
##
## 来源：学派「寒霜工坊」（`docs/archive/学派效果-实装规格.md`）+ 类型原生的铸币。
## 类型原生属性是 `mr`（每件 +4/10/16/23 魔法抗性）。
##
## ── 四条的作用域 ─────────────────────────────────────────────────────
## | 铸币 | **队伍**（本场累积，战斗结算时一次性进深海币）|
## | 冰封 | **全队**（每段攻击都掷骰，不要求身上带奇械）  |
## | 僵硬 | **全队**（同上）                              |
## | 易碎 | **全队**（顶档；对被控的敌人增伤）            |
##
## ══════════════════════════════════════════════════════════════════════
##  ★铸币：两处我按事实改了原文，都是【必须改】不是我随手改的
## ══════════════════════════════════════════════════════════════════════
## 原文写「**携带奇械者**每 2.5 秒铸造 1 枚」。按字面实装会炸：
##   · 一场对局跨上路+下路+决胜，2.5 秒一跳能跳 20~40 次；
##   · "携带奇械者"在顶档（10 件）时可能是 4~6 只 ⇒ 单场 80~240 枚。
##   而一整局的基础奖励是 `8 + 命数 + 2×失命 + 6(胜)` ≈ **17~29 枚**（`RealtimeBattle3DScene.gd:7519`）。
##   ⇒ 照字面做 = 奇械一个羁绊顶得上整局收入的 5~10 倍，经济直接失去意义。
##
## 所以定成：**每 2.5 秒【全队】铸 1/2/3/3 枚**（数量就是文案里那个数，不再乘携带人数）
##          **+ 本场硬上限 5 / 9 / 14 / 20 枚**。
## ⚠ 上限这个数我是按"顶档 ≈ 基础奖励的 +70~90%"定的，**是我拍的、没有原始出处**，
##   要调就调 `COIN_CAP`。文案里必须写出上限，否则又是一条骗人的描述。

var battle

const PERIOD := 2.5
## 每 2.5 秒【全队】铸几枚（逐档）
const COIN_PER_TICK := [1, 2, 3, 3]
## 本场累计上限（逐档）。★我拍的数，见文件头。
const COIN_CAP := [5, 9, 14, 20]

## 【冰封】全队攻击的冻结概率（逐档；档1 无）
const FREEZE_CHANCE := [0.0, 0.15, 0.25, 0.40]
const FREEZE_SEC := 1.5
## 同一目标两次被冻的最小间隔（"每 2.5 秒最多被冻 1 次"）
const FREEZE_CD := 2.5
## 解冻后的免疫时长
const FREEZE_IMMUNE := 1.5

## 【僵硬】每段攻击叠 1 层，持续 5 秒（叠加刷新时长），每层 -2% 攻击力，最多 20 层
const STIFF_TIER := 3
const STIFF_SEC := 5.0
const STIFF_PER_STACK := 0.02
const STIFF_MAX := 20
## ⛔【僵硬】跨 5/10/20 层的阈值提示：**用户 2026-08-07 拍板不做，别加回来**
##   （方案书 docs/plans/20260807-表现层方案书.md §5 U4）。曾在 18379ba 实装过一版
##   （`STIFF_VFX_STEPS` + `add_stiff()` 里的三行 + `_expire_stiff()`/`clear()` 里的 `_stiff_vfx` 归零
##   + `SynergyVfx.gadget_stiff_step()`），本次一起拆净 —— 不留空壳。

## 【易碎】顶档：被冻结或眩晕的敌人，受到的伤害 +25%
const BRITTLE_TIER := 4
const BRITTLE_MULT := 1.25

var _t_coin := 0.0
## 本场已铸的深海币（各方各记一份；只有玩家那方会真的进账）
var _coins := {"left": 0, "right": 0}


func _init(b) -> void:
	battle = b


func _side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "奇械")))
	return t


## 本场玩家（left）铸出来的深海币。结算时由 `RealtimeBattle3DScene` 加进奖励。
func minted(side: String = "left") -> int:
	return int(_coins.get(side, 0))


## 装备侧【额外铸币】入口 —— 原为「深渊铸币机 087」用(方案书 2026-08-04 批①)。
## ⚠ 2026-08 现状: p2eq_087 已被整条重做成【盗令潜水钟】(偷训龟大师技能 + 压载舱), 不再铸币,
##   本函数因此**零调用者**(全仓只有这条定义)。留着是因为奇械羁绊的"共用本场上限"口径要靠它;
##   下一件要额外铸币的装备直接调它, 别再自己记一本账。
##
## ★为什么装备要调这里而不是自己记一本账: 规格是"与羁绊【铸币】**共用本场上限**"。
##   自己记账 = 两本账各自封顶 ⇒ 实际上限翻倍, 而且结算时还要有人把两本合起来。
##   `_coins` 是唯一的那本账(`minted()` 是它的唯一出口), 所以装备也写它。
##
## 上限口径(用户 2026-08-04 拍板未决点 U4, 取建议 A):
##   · 没有奇械羁绊时 → 上限 = `solo_cap`(按装备星级 6/10/15, 由调用方传入)
##   · 有奇械羁绊时   → 上限 = max(羁绊档位上限, solo_cap)
## 返回【实际铸进去的枚数】(被上限截断时会小于 n, 到顶时是 0) —— 调用方据此决定要不要飘字。
func mint_extra(side: String, n: int, solo_cap: int) -> int:
	if n <= 0:
		return 0
	var cap: int = solo_cap
	var ti: int = _side_tier(side)
	if ti > 0:
		cap = maxi(cap, COIN_CAP[clampi(ti - 1, 0, 3)])
	var cur: int = int(_coins.get(side, 0))
	if cur >= cap:
		return 0
	var add: int = mini(n, cap - cur)
	_coins[side] = cur + add
	return add


func tick(delta: float) -> void:
	_t_coin += delta
	if _t_coin < PERIOD:
		return
	_t_coin -= PERIOD
	for side in ["left", "right"]:
		var s: String = str(side)
		var ti: int = _side_tier(s)
		if ti <= 0:
			continue
		var cap: int = COIN_CAP[clampi(ti - 1, 0, 3)]
		var cur: int = int(_coins.get(s, 0))
		if cur >= cap:
			continue
		_coins[s] = mini(cap, cur + COIN_PER_TICK[clampi(ti - 1, 0, 3)])
	_expire_stiff()


## 每段攻击命中后调（挂 on-hit，与弓箭处决同一个位置）。
## ★"每段攻击"包含技能与装备的每一次命中 —— 不只是普攻。
func on_hit(src, tgt) -> void:
	if not (src is Dictionary) or not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	var ti: int = _side_tier(str(src.get("side", "")))
	if ti <= 0:
		return
	# ── 冰封 ──────────────────────────────────────────────
	var ch: float = FREEZE_CHANCE[clampi(ti - 1, 0, 3)]
	if ch > 0.0 and battle._battle_rng.randf() < ch:
		# 两道闸: 同目标 2.5 秒内只能被冻一次 + 解冻后 1.5 秒免疫
		if battle._t >= float(tgt.get("_gad_freeze_cd", 0.0)) \
				and battle._t >= float(tgt.get("_gad_freeze_immune", 0.0)):
			battle._freeze(tgt, FREEZE_SEC)
			tgt["_gad_freeze_cd"] = battle._t + FREEZE_CD
			tgt["_gad_freeze_immune"] = battle._t + FREEZE_SEC + FREEZE_IMMUNE
			# ★演出(批 B3): `_freeze` 自带的是**所有冻结来源共用**的冰蓝小环(半径 48),
			#   读不出"这是奇械羁绊冻的"。六边霜环是奇械的专属母题。
			#   频率安全: 上面两道闸(同目标 2.5 秒 CD + 解冻后 1.5 秒免疫)已经把它压到全场 ≤1.5 次/秒。
			if battle._vfx != null and battle._vfx._syn != null:
				battle._vfx._syn.gadget_freeze(Vector2(tgt.get("pos", Vector2.ZERO)))
	# ── 僵硬 ──────────────────────────────────────────────
	if ti >= STIFF_TIER:
		add_stiff(tgt, 1)


## 给目标叠 N 层僵硬（刷新时长）。★攻击力的实际扣减在 `_recalc_stats` 里算，
## 这里只写字段 + 触发一次重算 —— 单一写入点，和闪避上限同一条规矩。
func add_stiff(tgt: Dictionary, n: int) -> void:
	tgt["stiff_stacks"] = mini(STIFF_MAX, int(tgt.get("stiff_stacks", 0)) + n)
	tgt["stiff_until"] = battle._t + STIFF_SEC
	battle._recalc_stats(tgt)
	# ⛔ 这里曾经有一段跨阈值提示(5/10/20 层各闪一次六边环) ——
	#   用户 2026-08-07 拍板不做，已拆净，别加回来（见文件头 STIFF 那段注释）。


## 僵硬到期 → 清零并重算。★不做"每帧检查"，跟着 2.5 秒节拍走就够了
##   （5 秒时长 vs 2.5 秒检查 = 最多多留 2.5 秒，代价远小于每帧遍历全场）。
func _expire_stiff() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		if int(u.get("stiff_stacks", 0)) <= 0:
			continue
		if battle._t < float(u.get("stiff_until", 0.0)):
			continue
		u["stiff_stacks"] = 0
		battle._recalc_stats(u)


## 僵硬对攻击力的倍率（挂 `_recalc_stats`）。20 层 = ×0.60。
static func stiff_mult(u: Dictionary) -> float:
	var n: int = int(u.get("stiff_stacks", 0))
	if n <= 0:
		return 1.0
	return maxf(0.0, 1.0 - float(mini(n, STIFF_MAX)) * STIFF_PER_STACK)


## 【易碎】受伤倍率（挂 `_mitigate_incoming` —— 两条伤害路径共用的唯一入口）。
## ★判据是"被冻结或眩晕" ⇒ 就是 `stun_until` 一个字段：`_freeze` 本身就是 `_stun` 加特效环，
##   两者在存储上分不开（同法器净化那条注释）。
func brittle_mult(u) -> float:
	if not (u is Dictionary):
		return 1.0
	if battle._t >= float((u as Dictionary).get("stun_until", 0.0)):
		return 1.0
	# 易碎是【对面】的顶档奇械给的 ⇒ 查的是 u 的敌方
	var foe: String = "right" if str((u as Dictionary).get("side", "")) == "left" else "left"
	if _side_tier(foe) < BRITTLE_TIER:
		return 1.0
	return BRITTLE_MULT


func clear() -> void:
	_t_coin = 0.0
	# ⚠ `_coins` 【不清】—— 铸币是"本场累积"，而本项目一场 = 上路 + 下路 + 决胜。
	#   在换路时清零等于把上路铸的全丢了。结算时由 `_last_reward` 一次性取走。
	for u in battle._units:
		if u is Dictionary:
			u["stiff_stacks"] = 0
			u["_gad_freeze_cd"] = 0.0
			u["_gad_freeze_immune"] = 0.0


## 整场结束（不是换路）：铸币归零，下一局重新开始。
func reset_match() -> void:
	_coins = {"left": 0, "right": 0}
