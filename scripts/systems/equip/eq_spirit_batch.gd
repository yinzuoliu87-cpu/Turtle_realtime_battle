class_name EqSpiritBatch
extends RefCounted
## eq_spirit_batch.gd — 【灵物 5 件】用户逐件重做后的效果本体 (2026-08-05)
##   060 磷光水母伞 · 061 钻孔螺 · 062 螳螂虾钳 · 063 白鲸气环 · 064 溺者的浮囊
##
## 规格事实源: docs/plans/20260805-装备逐件重做.md **§0.5 已定稿**
##   —— 那一节是用户逐件亲手写、当场拍板的**决定**, 不是提案。**一个数都不许改。**
##   本文件里每一处数值下面都标了它对应 §0.5 的哪一句。
##
## ⚠ 这五件**都不是新增**, 是把原来 AI 编的效果**整条替换掉**。旧效果与它们的门禁段
##   已一并删除(见交付报告), 具体是:
##     060 旧「闪避→对最近敌 20/35/60 魔法」· 061 旧「闪避→+移速」· 062 旧「雾隐叠闪避」
##     063 旧「致命伤留 1 血 + 不可选中」· 064 旧「友方阵亡召亡魂」
##
## ── 分派落点(全部是**已有**钩子, 没有新增分发口) ────────────────────────
##   060 → EquipSystem._eq_tick 的每帧段(自管两相计时器)  · 演出 SpiritEqVfx.parasol_open
##   061 → EquipSystem._eq_on_hit                          · 演出 SpiritEqVfx.breach_marks
##   062 → EquipSystem._eq_on_dodge(蓄) + _eq_on_hit(放)   · 演出 SpiritEqVfx.cavitation_strike
##   063 → EquipSystem._eq_on_cast(攻速) + _eq_on_hit(环)  · 演出 SpiritEqVfx.bubble_ring
##   064 → EquipSystem._eq_tick 的每帧段(35% 线) + SpecialBalance 回调 · 演出 float_bladder
##
## ── 地雷对照 (CLAUDE.md / 实装契约 §5) ──────────────────────────────────
##   §3.1 装备 hp 数值已是最终值 —— 064 的护盾按 `u["maxHp"]` 算, 不乘 HP_MULT。
##   §3.2 不拿单位字典当 key; 比较一律 `is_same`。
##   §3.3 两条伤害路径 —— 本文件不改伤害流程, 额外伤害段全部 `from_equip = true`(§5.7 防自激)。
##   §3.4 `_t` 跨路累加永不重置 —— 060 的 7 秒/2.5 秒**自己累加 delta**, 一次都没读 `_t` 当起点。
##   §3.7 注释不插行中间。

var battle
var _vfx: SpiritEqVfx = null

## SpiritEqVfx 是全局的(演出层), 而本系统的 tick 是【每单位】被调一次 ⇒
## 不按帧号去重的话, 演出会一帧被推进 N 次(N = 单位数)。同 EquipSystem._sig_tick_fr 的做法。
var _vfx_fr: int = -1


func _init(b) -> void:
	battle = b
	_vfx = SpiritEqVfx.new(b)


func _si(star: int) -> int:
	return clampi(star - 1, 0, 2)


# ══════════════════════════════════════════════════════════════════════════
#  §每帧: 060 的两相计时器 + 064 的 35% 线 + 演出推进
#  ★挂在 EquipSystem._eq_tick 的【EQ_TICK 计时闸之前】(那闸是 2.5 秒一跳,
#    而 060 的相位切换与 064 的血线判定都要每帧精度)。
#  ★守卫是【常驻字段】而不是遍历 equips: 不带这两件的单位这里只多两次 dict.get。
#    常驻字段由 EquipStatsApply._eq_apply_flags 在每一路开战管线里写(换路自动重置)。
# ══════════════════════════════════════════════════════════════════════════
func tick_unit(u: Dictionary, delta: float) -> void:
	var fr: int = Engine.get_process_frames()
	if fr != _vfx_fr:
		_vfx_fr = fr
		_vfx.tick(delta)
	if not u.get("alive", false):
		return
	if int(u.get("_parasol_si", -1)) >= 0:
		_tick_parasol(u, delta)
	if int(u.get("_bladder_si", -1)) >= 0:
		_tick_bladder(u, delta)


# ══════════════════════════════════════════════════════════════════════════
#  §060 磷光水母伞 (灵物 · 1 费) —— 用户 §0.5 定稿
#
#  「每 7 秒触发一次: 打开伞, 自身 + 200 码内的队友获得 11/22/35% 伤害减免
#    与 15% 闪避率(固定值, 不随星级变), 持续 2.5 秒; 效果**结束时**携带者回复
#    50/80/130 生命; **然后才**重新开始那 7 秒计时。」
#
#  ⇒ 完整循环 = 2.5 + 7 = 9.5 秒, 减伤覆盖率 26.3%(**不是** 2.5/7)。
#  ★计时是【自管的】: 效果结束才起算下一轮 —— 不能挂现成的 2.5 秒统一节拍。
#  ★减伤是【加法】叠加(用户 §0.5 通用口径), 不是取较大值。
# ══════════════════════════════════════════════════════════════════════════

## 收拢期(秒) —— 效果结束之后才开始数
const PARASOL_IDLE := 7.0
## 张开期(秒)
const PARASOL_OPEN := 2.5
## 庇护半径(码)
const PARASOL_RADIUS := 200.0
## 闪避率 **固定 15%**, 不随星级变(用户明确)
const PARASOL_DODGE := 0.15
## 加在 buffs 上的那条闪避带这个标记, 收伞时按标记精确摘掉。
## ★为什么不用 `_buff(..., 2.5)` 让引擎自己过期: 那条到期时刻走 `battle._t`,
##   而本件的相位走自累加的 delta —— 两把尺子会错开, 出现"伞收了闪避还在"。
##   写进同一个 `u["buffs"]` 通道(= `_recalc_stats` 唯一读的地方), 只是多带一个来源标记。
const PARASOL_BUFF_SRC := "p2eq_060"


func _tick_parasol(u: Dictionary, delta: float) -> void:
	var si: int = int(u["_parasol_si"])
	var stt: Dictionary = u["eq_state"].get("p2eq_060", {})
	var t: float = float(stt.get("pa_t", 0.0)) + delta
	var open: bool = bool(stt.get("pa_open", false))
	if not open:
		if t >= PARASOL_IDLE:
			t = 0.0
			open = true
			_parasol_open(u, si, stt)
	else:
		if t >= PARASOL_OPEN:
			t = 0.0
			open = false
			_parasol_close(u, si, stt)
	stt["pa_t"] = t
	stt["pa_open"] = open
	u["eq_state"]["p2eq_060"] = stt


## 伞打开: 自身 + 200 码内队友拿 11/22/35% 减伤 + 15% 闪避
func _parasol_open(u: Dictionary, si: int, stt: Dictionary) -> void:
	var dr: float = [0.11, 0.22, 0.35][si]
	var got: Array = []
	for o in battle._targeting._allies_of(u, true):
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		if float((o["pos"] as Vector2).distance_to(u["pos"])) > PARASOL_RADIUS:
			continue
		o["damage_reduction"] = float(o.get("damage_reduction", 0.0)) + dr
		(o["buffs"] as Array).append({
			"stat": "dodge", "amount": PARASOL_DODGE, "pct": false,
			"until": battle._t + 1.0e9, "src_eq": PARASOL_BUFF_SRC,
		})
		battle._recalc_stats(o)
		got.append(o)
	## ★存的是【单位数组】不是 Dictionary 的键(CLAUDE.md §3.2), 收伞时按 is_same 找回来。
	stt["pa_units"] = got
	stt["pa_dr"] = dr
	## covered 传给演出: 被罩队友每人头顶一簇环绕磷光点(谁在伞下一眼可读)。
	## ★携带者自己不传 —— 它头顶已经有整把伞了, 再加光点是重复读数。
	var others: Array = []
	for o in got:
		if not is_same(o, u):
			others.append(o)
	_vfx.parasol_open(u["pos"], Color(0.55, 0.95, 1.0, 0.9), PARASOL_RADIUS, PARASOL_OPEN, others)


## 伞收拢: 摘掉减伤/闪避, 携带者回复 50/80/130 生命
func _parasol_close(u: Dictionary, si: int, stt: Dictionary) -> void:
	var dr: float = float(stt.get("pa_dr", 0.0))
	for o in stt.get("pa_units", []):
		if not (o is Dictionary):
			continue
		o["damage_reduction"] = maxf(0.0, float(o.get("damage_reduction", 0.0)) - dr)
		var bl: Array = o.get("buffs", [])
		for i in range(bl.size() - 1, -1, -1):
			var b = bl[i]
			if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == PARASOL_BUFF_SRC:
				bl.remove_at(i)
				break
		battle._recalc_stats(o)
	stt["pa_units"] = []
	stt["pa_dr"] = 0.0
	if u.get("alive", false):
		## 回血的演出因果: 伞的磷光收束成光流回到身体, 然后数字才落(不是凭空飘个数)。
		_vfx.parasol_heal(u)
		battle._damage._heal(u, [50.0, 80.0, 130.0][si])


## 【闪避触发】伞的 15% 闪避真的挡下一击时: 被攻击者身上闪一记迷你伞快速开合的残影 ——
## 「伞替你挡了一下」。闪避从纯数值变成看得见的时刻(丙层, 用户 2026-08-11 拍板)。
## ★挂在 EquipSystem._eq_on_dodge(每次闪避都走的唯一入口), 只对带伞 buff 的单位生效。
## ★0.25s 每单位节流: 高攻速敌人连闪会刷屏。
func on_parasol_dodge(u: Dictionary) -> void:
	var has_buff := false
	for b in u.get("buffs", []):
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == PARASOL_BUFF_SRC:
			has_buff = true
			break
	if not has_buff:
		return
	if battle._t - float(u.get("_pflash_t", -10.0)) < 0.25:
		return
	u["_pflash_t"] = battle._t
	_vfx.parasol_dodge_flash(u)


# ══════════════════════════════════════════════════════════════════════════
#  §061 钻孔螺 (灵物 · 2 费) —— 用户 §0.5 定稿(= 用户范例「装备3」)
#
#  「每次普攻命中触发 on-hit: 额外造成**目标最大生命 2/2.5/3%** 的魔法伤害,
#    并叠 **1/1/2 层【破损】**(单目标上限 20 层)。
#    目标**已有 20 层破损**时, 这个 on-hit **转为真实伤害**。」
#
#  ✅ 用户拍板「不要调, 就名字给一个吧」⇒ 以下全部维持:
#     · 破损在 1~19 层**没有任何作用**(纯计数器) —— 已告知用户, 用户不改
#     · **不衰减** / 多携带者**共享层数**(同【腐蚀】) / 转真伤**只作用于本件的 on-hit**
# ══════════════════════════════════════════════════════════════════════════

## 单目标破损上限(用户定稿 20 层)
const BREACH_CAP := 20


## 当前破损层数(门禁与演出共用这一个读法)
func breach_of(tgt: Dictionary) -> int:
	return int(tgt.get("breach_stacks", 0))


func _eq_drill_snail(src: Dictionary, tgt: Dictionary, si: int, basic: bool = false) -> void:
	## ★规格「每次普攻命中」(§0.5) —— 技能/浮游炮/演出伤害不触发(2026-08-11 用户报修)。
	if not basic:
		return
	if not tgt.get("alive", false) or float(tgt.get("maxHp", 0.0)) <= 0.0:
		return
	## ★先判"这一击之前"是不是已经 20 层 —— 本次施加的层数不算进这一发的转真伤判定。
	##   写反了的话第 19 层那一发就会提前变真伤(1/1/2 的 2 层刚好跨过去)。
	var was_full: bool = breach_of(tgt) >= BREACH_CAP
	var amount: float = float(tgt["maxHp"]) * [0.02, 0.025, 0.03][si]
	if was_full:
		## 满层 ⇒ 转真实伤害(raw = true), 不吃魔抗
		battle._damage._apply_damage_from(src, tgt, maxi(1, int(round(amount))),
			Color("#ffffff"), 0.0, true, true)
	else:
		battle._damage._apply_damage_from(src, tgt,
			battle._resolve_dmg(src, amount, tgt, true), Color("#8fe3ff"), 0.0, false, true)
	tgt["breach_stacks"] = mini(BREACH_CAP, breach_of(tgt) + [1, 1, 2][si])
	# 演出: 持久裂纹覆盖层(层数读数, Paris 律驱动, 满 20 白热) + 每击钻入闪/壳屑
	_vfx.breach_overlay(tgt, breach_of(tgt))
	_vfx.drill_flash(tgt["pos"])


# ══════════════════════════════════════════════════════════════════════════
#  §062 螳螂虾钳 (灵物 · 2 费) —— 用户 §0.5 定稿(三条口径用户已确认)
#
#  「**闪避掉一次攻击后**, 强化自己的**下一次普攻**: 额外造成
#    **0.7/1/1.5 ATK + 目标最大生命 6/8/13%** 的**物理伤害**,
#    并回复**这次普攻造成伤害的 40%** 生命。强化普攻有 **2 秒 CD**。」
#
#  ✅ 三条口径(用户 2026-08-05「62 按你的理解是这样的, 用方案书锁好, 保留所有细节」):
#     ① 40% 回血按【整次强化普攻打出的总伤害】算 —— 含普攻本体 + 额外那段。
#     ② **2 秒 CD 卡的是【触发】** —— 放出一次强化普攻之后, 2 秒内闪避成功**不再蓄下一发**。
#        ★不是"照常蓄、只是打不出来"(那等于没有 CD)。
#     ③ 额外那段物理伤害**不再触发 on-hit**(`from_equip = true`), 防与 061 破损 / 剑士追打自激。
# ══════════════════════════════════════════════════════════════════════════

## 强化普攻的内置冷却(秒)
const MANTIS_CD := 2.0
## 回血占【整次强化普攻总伤害】的比例
const MANTIS_LEECH := 0.40


## 闪避成功 → 蓄一发。★CD 内直接 return 且**不置 ready**(口径②)。
func _eq_mantis_ready(u: Dictionary, _si: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_062", {})
	if battle._t < float(stt.get("emp_cd_until", 0.0)):
		u["eq_state"]["p2eq_062"] = stt
		return
	stt["emp_ready"] = true
	u["eq_state"]["p2eq_062"] = stt


## 普攻命中 → 若已蓄好, 打出强化段并回血。
## ★消费点放 on-hit, 与 015 荆棘海胆的「强化下一次普攻」同一个惯例。
## ⚠ **诚实记录(与用户原话的一处偏差)**: 用户写的是"强化下一次**普攻**", 而 `_eq_on_hit`
##   会被携带者打出的**任意一段非装备伤害**调到(技能也算) ⇒ 这一发有可能被技能吃掉。
##   为什么不挂 `_eq_on_basic_attack`(那才是"只有普攻"的钩子):
##     ① 它在 `_basic_attack` 的**开头**触发, 那时这一击的伤害还没算出来,
##        而口径① 要求按"整次普攻打出的总伤害"回 40% —— 拿不到 dmg 就做不出来;
##     ② 远程普攻的伤害落在**后面的帧**(弹道飞完才结算), 想靠"同帧"把两者对起来
##        会让所有远程携带者永远触发不了。
##   ⇒ 取与 015 一致的既有惯例。要改成严格"只有普攻", 得先给伤害管线传一个"这一段是普攻"
##      的标记(那是 battle_damage.gd 的中央签名, 本批不许动)。
func _eq_mantis_strike(src: Dictionary, tgt: Dictionary, dmg: int, si: int, basic: bool = false) -> void:
	## ★规格「强化下一次普攻」(§0.5) —— 只在普攻命中时放强化(2026-08-11 用户报修)。
	if not basic:
		return
	var stt: Dictionary = src["eq_state"].get("p2eq_062", {})
	if not bool(stt.get("emp_ready", false)) or not tgt.get("alive", false):
		src["eq_state"]["p2eq_062"] = stt
		return
	stt["emp_ready"] = false
	stt["emp_cd_until"] = battle._t + MANTIS_CD
	src["eq_state"]["p2eq_062"] = stt
	var base: float = float(src.get("atk", 0.0)) * [0.7, 1.0, 1.5][si] \
		+ float(tgt.get("maxHp", 0.0)) * [0.06, 0.08, 0.13][si]
	## 物理伤害 ⇒ 吃护甲(不是真伤); from_equip 防自激(口径③)
	var extra: int = battle._resolve_dmg(src, base, tgt, false)
	battle._damage._apply_damage_from(src, tgt, extra, Color("#ffd27a"), 0.0, false, true)
	## 口径①: 40% 按【普攻本体 + 额外段】的总伤害算
	battle._damage._heal(src, float(dmg + extra) * MANTIS_LEECH)
	src["_mantis_n"] = int(src.get("_mantis_n", 0)) + 1
	_vfx.cavitation_strike(tgt["pos"], Color(1.0, 0.85, 0.45, 0.95))


# ══════════════════════════════════════════════════════════════════════════
#  §063 白鲸气环 (灵物 · 3 费) —— 用户 §0.5 定稿
#
#  「① 释放技能后获得 **30/60/100% 攻速**, 持续 **本次技能消耗的龟能 × 0.03** 秒。
#    ② 携带者的普攻会对敌人施加一个【环】; 敌人身上有 **3 个环**时环被引爆,
#       该敌人受到 **25/40/70 真实伤害**。」
#
#  ★覆盖率恒定 40%, 与龟无关 —— 不是调出来的, 是 0.03 这个系数自带的性质:
#    充满龟能要 `消耗 × 0.075` 秒(RealtimeBattle3DScene._skill_cd),
#    而加成持续 `消耗 × 0.03` ⇒ 0.03 ÷ 0.075 = **40%**。贵技能挂得久、也更久才能再放。
#  ✅ 三条默认口径(用户「锁好」时未反对): 【环】不衰减 / 多携带者共享同一目标身上的环 /
#     引爆的真实伤害不再触发 on-hit。
# ══════════════════════════════════════════════════════════════════════════

## 持续时间 = 本次技能消耗龟能 × 这个系数(用户原话)
const RING_SEC_PER_ENERGY := 0.03
## 引爆需要的环数
const RING_TRIGGER := 3


## 从 `u["pending"]` 取本次施放的技能类型。
## ★状态机在前摇结束时把 `pending` 置成 `"K:<stype>"`(RealtimeBattle3DScene:2403/2409),
##   然后才调 `_eq_on_cast` —— 这一段之间没有任何地方改写 pending, 所以它就是"本次这一技"。
##   ⚠ 诚实记录: 钩子签名 `_eq_on_cast(u, tgt)` **不带 stype**, 而给它加一个参数要动
##     RealtimeBattle3DScene(本批不许碰)。读 pending 是当前唯一不改主场景的取法。
func cast_stype(u: Dictionary) -> String:
	var p: String = str(u.get("pending", ""))
	return p.substr(2) if p.begins_with("K:") else ""


func _eq_whale_haste(u: Dictionary, si: int) -> void:
	var stype: String = cast_stype(u)
	if stype == "":
		return
	var cost: float = float(battle._skill_cost(u, stype))
	var sec: float = cost * RING_SEC_PER_ENERGY
	if sec <= 0.0:
		return
	var want: float = 1.0 + [0.30, 0.60, 1.00][si]
	## ★`haste_mult`/`haste_until` 是【单槽·限时】攻速通道(祝福等也写它) ⇒ 直接赋值会互相盖。
	##   取"倍率更大的那个 + 到期更晚的那个", 既不吞别人的强 buff, 也不被别人吞掉。
	var live: bool = battle._t < float(u.get("haste_until", 0.0))
	if not live or want >= float(u.get("haste_mult", 1.0)):
		u["haste_mult"] = want
	u["haste_until"] = maxf(float(u.get("haste_until", 0.0)), battle._t + sec)
	u["_whale_cast_n"] = int(u.get("_whale_cast_n", 0)) + 1


## 普攻命中 → 挂一个环; 满 3 个引爆 25/40/70 真伤并清零。
## ⚠ 同 062 的诚实记录: 挂的是 `_eq_on_hit`, 所以携带者的**技能伤害也会挂环**。
##   原因同上(管线没有"这一段是普攻"的标记), 且与 061 破损、083 潮汐细剑同口径。
func _eq_whale_ring(src: Dictionary, tgt: Dictionary, si: int, basic: bool = false) -> void:
	## ★规格「携带者的普攻施加环」(§0.5) —— 技能不施环(2026-08-11 用户报修)。
	if not basic:
		return
	if not tgt.get("alive", false):
		return
	var n: int = int(tgt.get("whale_rings", 0)) + 1
	if n >= RING_TRIGGER:
		tgt["whale_rings"] = 0
		battle._damage._apply_damage_from(src, tgt, maxi(1, int(round([25.0, 40.0, 70.0][si]))),
			Color("#ffffff"), 0.0, true, true)
		tgt["_ring_boom_n"] = int(tgt.get("_ring_boom_n", 0)) + 1
		battle._skill_ring(tgt["pos"], Color(0.26, 0.70, 1.00, 0.75), 58.0)   # ★颜色推深(见下)
	else:
		tgt["whale_rings"] = n
		## ★★ 063 的两个环颜色从 (0.72~0.75, 0.93~0.95, 1.0) 推深到 (0.26~0.28, 0.70~0.72, 1.0)。
		##   原色饱和度只有 0.28 ⇒ 对黑底就是白。A/B 实测(2026-08-11):
		##   063 自己画的 31252 个像素里 **76% 低饱和** —— 整个读成白。
		##   (095 的结论: 亮度靠 alpha 给, 不能靠把颜色推淡。)
		_vfx.bubble_ring(tgt["pos"], Color(0.28, 0.72, 1.00, 0.8), n - 1)


# ══════════════════════════════════════════════════════════════════════════
#  §064 溺者的浮囊 (灵物 · 4 费) —— 用户 §0.5 定稿
#
#  「携带者**首次**生命值降低到 **35%** 以下时, 获得 **50/80/160% 最大生命值**的
#    【幽灵护盾】。这个特殊护盾会在 **20 秒**内慢慢衰减。持有该特殊护盾时会获得
#    **15% 闪避率**和 **30/60/120 双抗**(护甲 + 魔抗)。
#    该特殊护盾**被打破时会爆炸**, 使 **300 码内**的敌人被施加 **4 秒的诅咒效果**。」
#
#  ✅ 用户拍板的四条口径(2026-08-05「衰减也算, 线性, 每路, 行」):
#     ① **自然衰减到 0 也算"被打破"** ⇒ 只要护盾触发过, 爆炸**必定发生**。
#     ② **线性衰减** —— 每秒掉总量的 1/20。
#     ③ **「首次」= 每路一次**(换路重置)。
#     ④ 名字 **溺者的浮囊**; 原名「深渊招魂螺」作废, 新设计里没有亡魂。
#
#  ★衰减与吸收**不自己实现**: 走共用基建 SpecialBalance(battle._spec), 契约 §2。
#    `on_break` 的 reason 是 "damage"(被打光) 还是 "decay"(自然衰减完) **都要炸** ⇒ 不判 reason。
#  ★【诅咒】是**已有机制**, 走 battle._damage._add_curse(按秒不按层, 每秒 5% 最大生命真伤)。
# ══════════════════════════════════════════════════════════════════════════

## SpecialBalance 里这条余额的 key
const GHOST_KEY := "p2eq_064_ghost"
## 触发血线(用户: 首次降到 35% 以下)
const GHOST_HP_LINE := 0.35
## 线性衰减总时长(秒)
const GHOST_DECAY := 20.0
## 持有期间的闪避率(固定值)
const GHOST_DODGE := 0.15
## 爆炸半径(码)
const GHOST_BURST_R := 300.0
## 诅咒时长(秒) —— 4 秒 × 每秒 5% 最大生命 = 目标最大生命的 20% 真伤
const GHOST_CURSE_SEC := 4.0
## 幽灵护盾的闪避 buff 来源标记(同 060 的做法, 破盾时按标记精确摘掉)
const GHOST_BUFF_SRC := "p2eq_064"


## 每帧: 只做"首次跌破 35%"这一件事。★每路一次靠 `eq_state`(换路整体重建)。
## ⚠ 诚实记录: 契约 §3 说主会话会提供 `battle._equip_sys.hp_line(...)` 通用阈值线,
##   但我实现到这里时它**还不存在**; 而本件本来就要一个每帧钩(与 060 共用),
##   所以就地判了。若将来统一到 hp_line, 把这四行换成一次注册即可, 行为完全相同。
func _tick_bladder(u: Dictionary, _delta: float) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_064", {})
	if not bool(stt.get("ghost_fired", false)):
		if float(u.get("maxHp", 0.0)) > 0.0 and float(u["hp"]) < float(u["maxHp"]) * GHOST_HP_LINE:
			stt["ghost_fired"] = true
			u["eq_state"]["p2eq_064"] = stt
			_ghost_grant(u, int(u["_bladder_si"]))
			return
	u["eq_state"]["p2eq_064"] = stt
	## 浮囊演出跟着真实余额瘪下去 —— 演出不自己算衰减(两套真相会打架)
	var h = stt.get("ghost_vfx", null)
	if h is Dictionary and not (h as Dictionary).is_empty():
		var v: float = battle._spec.val(u, GHOST_KEY)
		var m: float = maxf(float(stt.get("ghost_max", 1.0)), 0.001)
		_vfx.set_bladder_frac(h, v / m)


func _ghost_grant(u: Dictionary, si: int) -> void:
	var amt: float = float(u["maxHp"]) * [0.50, 0.80, 1.60][si]
	var res: float = [30.0, 60.0, 120.0][si]
	var stt: Dictionary = u["eq_state"].get("p2eq_064", {})
	stt["ghost_max"] = amt
	stt["ghost_res"] = res
	u["eq_state"]["p2eq_064"] = stt
	## 双抗走 base_def/base_mr(= _recalc_stats 的唯一入料口), 闪避走 buffs 通道
	u["base_def"] = float(u.get("base_def", 0.0)) + res
	u["base_mr"] = float(u.get("base_mr", 0.0)) + res
	(u["buffs"] as Array).append({
		"stat": "dodge", "amount": GHOST_DODGE, "pct": false,
		"until": battle._t + 1.0e9, "src_eq": GHOST_BUFF_SRC,
	})
	battle._recalc_stats(u)
	battle._spec.grant(u, GHOST_KEY, amt, {
		"decay_sec": GHOST_DECAY,
		"on_break": func(uu, _k, _reason): _ghost_break(uu, si),
	})
	stt = u["eq_state"].get("p2eq_064", {})
	## ★★颜色从 (0.72, 0.86, 1.00) 推深到 (0.30, 0.62, 1.00)。
	##   原色饱和度只有 0.28 —— **对黑底来说就是白**。A/B 实测(2026-08-11):
	##   即使改成只画正面, 它自己画的像素里仍有 **42% 低饱和**。
	##   095 那一轮的结论: **亮度要靠 alpha 给, 不能靠把颜色推淡** ——
	##   半透明的近白在黑底上合成出来就是灰/白。
	stt["ghost_vfx"] = _vfx.float_bladder(u["pos"], Color(0.30, 0.62, 1.00, 0.85))   # ★颜色推深: 见下
	u["eq_state"]["p2eq_064"] = stt


## 破盾(被打光 **或** 自然衰减完 —— 两种都炸)
func _ghost_break(u: Dictionary, _star_i: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_064", {})
	var res: float = float(stt.get("ghost_res", 0.0))
	u["base_def"] = maxf(0.0, float(u.get("base_def", 0.0)) - res)
	u["base_mr"] = maxf(0.0, float(u.get("base_mr", 0.0)) - res)
	var bl: Array = u.get("buffs", [])
	for i in range(bl.size() - 1, -1, -1):
		var b = bl[i]
		if b is Dictionary and str((b as Dictionary).get("src_eq", "")) == GHOST_BUFF_SRC:
			bl.remove_at(i)
			break
	battle._recalc_stats(u)
	var h = stt.get("ghost_vfx", null)
	if h is Dictionary:
		_vfx.drop(h)
	stt["ghost_vfx"] = null
	stt["ghost_res"] = 0.0
	u["eq_state"]["p2eq_064"] = stt
	var n := 0
	for o in battle._targeting._enemies_of(u):
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		if float((o["pos"] as Vector2).distance_to(u["pos"])) > GHOST_BURST_R:
			continue
		battle._damage._add_curse(o, GHOST_CURSE_SEC, u)
		n += 1
	u["_ghost_burst_n"] = int(u.get("_ghost_burst_n", 0)) + 1
	u["_ghost_cursed_n"] = int(u.get("_ghost_cursed_n", 0)) + n
	_vfx.bladder_burst(u["pos"], Color(0.72, 0.62, 1.0, 0.9), GHOST_BURST_R)
