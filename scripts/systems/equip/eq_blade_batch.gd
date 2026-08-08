class_name EqBladeBatch
extends RefCounted
## eq_blade_batch.gd — 盾+剑四件新装备的效果本体
## 081 藤编圆盾 · 082 砗磲护心甲 · 083 潮汐细剑 · 084 手半剑
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数都不许改。
## 演出层放 `scripts/scenes/battle/blade_eq_vfx.gd`(本文件自己 new 出来, 不进共享文件)。
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
## 归你的: **本文件** + `scripts/scenes/battle/blade_eq_vfx.gd` + `tests/verify_eq_blade_batch.gd/.tscn`
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(与批①/批② 同, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**。裸 `randi()`/`randf()` 会破坏确定性 ——
##    `tools/rng_discipline.py` 冻结了裸调用数, `verify_battle_determinism` 同种子比指纹。
##    ★本文件【一个随机都没有】: 四件的效果全是确定性的(充能条/层数/几何扇形/直线波)。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 处决 / 冰封 / 僵硬)。
##    082 的护心反伤尤其要焊 —— 不焊就是"我反伤你、你反伤我"的无限套娃。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 所有"持续 N 秒 / 每 N 秒"
##    存**到期时刻**或**自管累加器**, 不许拿 `_t` 直接和常数比。
##    081 的举盾存 `up_until = _t + 时长`(到期时刻), 084 的十字斩分段存 `t = _t + 延迟`。
##
## ══════════════════════════════════════════════════════════════════════
##  本批的分派落点(主会话已接好, 你只要实现下面这些函数)
## ══════════════════════════════════════════════════════════════════════
##   081 → `on_damaged`(充能条累计) + `tick_unit`(举盾计时)
##   082 → `on_damaged`(护心反伤 + 每 15 次攒一层) + `on_basic`(消耗一层: 回血 + 附带 100% 魔抗魔伤)
##   083 → `on_hit`(连续命中同一目标叠层, 至多 20 层) + `tick_unit`(按已损失生命给攻速)
##   084 → `on_spawn`(判近战/远程走两套) + `tick_unit`(★射程转化【实时】重算)
## ★081 已从 EQ_PERIOD 2.5 秒摘掉 —— 它现在是"挨够伤害才举盾"的充能条, 不是周期件。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★两条伤害路径(CLAUDE.md §3.3) —— 081 与 082 的口径【故意不同】
## ══════════════════════════════════════════════════════════════════════
## 主会话 2026-08-06 补了 `EquipSystem._b4_on_damaged_any`(挂 `_apply_damage` = DoT/真伤路),
## 于是本文件的 `on_damaged` **两条路都会被调到**。用哪条路来的看 `u["_b4_dot"]`:
##   · `true`  = DoT/真伤路(灼烧/中毒/流血/诅咒/真伤)
##   · `false` = 普攻/技能路(`_apply_damage_from`)
## ⚠ **不要拿 `src == null` 判路** —— DoT 也带原始施加者, 判不出来。
##   · **081** 数的是"受到多少伤害量" ⇒ **两条路都收**(用户规格原文就是"受到…的伤害")
##   · **082** 数的是"受到几段攻击" ⇒ **DoT 每跳不算**(用户 2026-08-06 明确拍板) ⇒ `_b4_dot` 直接 return
##
## ⚠ 082 的另外两条口径(同日拍板): 多段攻击每段独立计数; 反伤走 `from_equip = true` 不触发对方反伤。
##
## ══════════════════════════════════════════════════════════════════════
##  ★多件同带一律【取星级更高的那一件】(契约 §4), 不是相加
## ══════════════════════════════════════════════════════════════════════
## 做法: `on_spawn` 只记 `u["_b8X_si"] = maxi(旧, si)`, **所有效果读这个字段而不是钩子传进来的 si**。
## 但钩子是在 `for e in u["equips"]` 里逐件调的 ⇒ 带两把同款会被调两次。
## 去重用**事件序号**, 不是帧号(一帧内可能有多段伤害):
##   · `on_damaged` → `u["_st_taken"]`(两条路都在调钩子【之前】累加, 且单段伤害恒 ≥1 ⇒ 严格递增)
##   · `on_hit`     → `src["_st_dealt"]`(同上, 在 `_eq_on_hit` 之前累加)
##   · `on_basic`   → **按份数取模**(`_nth_copy`): 一次普攻必定连着调 n 次(n = 身上这件的份数),
##     所以"第 0、n、2n… 次"就是每次普攻的第一份。
##     ⚠ 这里**不能用帧号**: `_advance_sim_accum` 一个渲染帧最多跑 **8 个 sim 步**,
##     高攻速单位在卡顿帧里能出手两次 —— 帧号去重会把第二次静默吃掉。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★规格没写死、由我(实装方)定的地方 —— 逐条写清选了哪侧、另一侧是什么
## ══════════════════════════════════════════════════════════════════════
## ① **081 的护盾不设时限**(选: 永久盾 / 另一侧: 传 `dur = 举盾时长`)。
##    规格写"期间获得 60/100/160 护盾值"。限时盾原语到期时执行的是
##    `u["shield"] = 0`(RealtimeBattle3DScene:6781) —— 它清的是**整个护盾池**,
##    会连带抹掉铁壁盾/羁绊/别的装备同时给的盾。为一件 1 费装备引入这种副作用不划算,
##    ⇒ 选**永久盾**(打掉才没)。**代价诚实说**: 没被打掉的话会跨到下一次举盾, 比"期间"略强。
## ② **081 的充能条满了就清零**(选: 归零 / 另一侧: 减去阈值保留溢出)。
##    规格写"举盾结束后**重新**开始计数充能条" ⇒ 归零更贴字面。
## ③ **082 的反伤走 `_resolve_dmg(..., magic=true)`** ⇒ 吃目标魔抗、可暴击。
##    另一侧是"3/5/8 点无视魔抗的固定魔法伤害"。选前者的理由: 契约 §4 全表口径
##    「魔法走魔抗」, 且规格明写"魔法伤害"而不是"真实伤害"。
## ④ **082 的"100% 魔抗"取【当前】魔抗**(含举盾/硬化/羁绊给的), 不是登场快照。
##    规格原文"相当于自身 100% 魔抗", 没写快照; 而 §0.5 的分析表(21→196)算的正是
##    "堆魔抗流"的**当前**魔抗 ⇒ 取当前值才对得上那张表。
## ⑤ **083 的层数上限 20 是硬顶**; 切目标从 1 起算(不是 0)—— 那一下本身就是"命中同一目标"的第一次。
## ⑥ **084 竖斩的扇形张角 = 60°**(规格只给了横斩的 120°, 竖斩只写"同样 250 码剑打一下")。
##    选窄角的理由: 竖劈的横向覆盖天然比横扫窄, 两段角度一样的话"十字"就没有十字感。
##    另一侧是"竖斩也 120°"(那样两段几乎等价, 只是打两遍)。
## ⑦ **084 两道波: 横波半宽 125 码(= 横斩 250 码扫幅的一半)、竖波半宽 45 码**;
##    都沿施法朝向推进 700 码、速度 900 码/秒、波前带 ±60 码, 每个敌人每道波只吃一次。
##    规格只写"直线移动 / 竖方向一道波移动", 没给宽度与速度 ⇒ 这三个数是我定的。
## ⑧ **084 的后撤是瞬移**(选: 瞬移 + 演出补 / 另一侧: 逐帧滑退)。
##    CLAUDE.md §3.5:「一个测数值对不对的用例不该依赖任何动画 tween 跑完」——
##    落点由纯函数 `cross_retreat_dest()` 给出、门禁验几何, 演出只负责好看。
## ⑨ **084 远程侧"有效射程固定 100"的实现是【把射程通道搬进影子字段】**
##    (`range_add`/`range_perm` 清零、`atk_range` 写 100), 而不是"写一个负的 atk_range 去抵消"。
##    好处: `battle._eff_range(u)` 恰好等于 100, 信息面板显示的"射程 100"也不骗人。
##
## ══════════════════════════════════════════════════════════════════════
##  ⚠⚠ 已知缺口(不是"未决点" —— 现状明确, 触发条件明确, 根治位置明确)
##  【084 远程侧: 射程折算对 `atk_range` 的"绝对写入"会漂】
## ══════════════════════════════════════════════════════════════════════
## · **现状**: `_b84_refresh` 每帧把 `atk_range` 相对基线 100 的差当成**增量**折进影子字段:
##     `_b84_nat_range += (atk_range − 100)`, 然后把 `atk_range` 写回 100。
##   全库有 11 处写 `atk_range`, 分两类, 这个口径只对其中一类是对的:
##     ✔ **增量写入**(`atk_range = atk_range + N`): 天使祝福 +25 / 破浪矛 ±50 /
##       无头强化窗口 +60 / 龟蛋加固 maxf(…, 420) —— 这些**完全正确**, 也是绝大多数情形。
##     ✘ **绝对写入**(`atk_range = <常数>`): 形态切换 —— 熔岩 `_volcano` 70 / 退火 400,
##       双头 `two_head` 切远程 400 / 切近战 70, 机甲组装 100, 龟壳 70/600。
## · **什么情况下会漂**: 携带 084 的**远程龟**在战斗中**切形态**。举例:
##     熔岩龟(登场远程 400 ⇒ 走远程分支, 折算基线 nat=400)进火山形态 → 引擎写 `atk_range = 70`
##     ⇒ 本函数读成"增量 −30" ⇒ nat 变 370(应为 70); 退火时引擎写 400 ⇒ 读成"增量 +300"
##     ⇒ nat 变 670(应为 400)。**每切一次形态漂一次, 且是单向累积**。
##     后果: 转化量偏大 ⇒ 生命/攻击/吸血三项偏高(不会崩、不会报错, 只是数值不对)。
##     ★不受影响的: 所有**近战**携带者(走另一条分支)、所有**不切形态**的远程龟(= 28 龟里的绝大多数)。
## · **为什么没选另一侧**: 把绝对写入当成"新的自然射程"会让**增量写入**被整个吞掉
##   (天使 +25 之后 nat 直接变成 125 而不是 475), 那是更常见、更明显的错。
##   两侧都错, 我选了错在罕见路径上。规格(§0.5)没规定这一格。
## · **根治要动哪里**: 给 `atk_range` 的写入加"来源/口径"信息 —— 要么把 11 个写入点分成
##   `set_base_range()` / `add_range()` 两个入口(`RealtimeBattle3DScene.gd`, 共享文件),
##   要么给单位加一个 `atk_range_base` 字段让形态切换只写它。两条都是**共享层改动**,
##   不在本批(批④·B 路)范围内 —— 已写进交付报告转主会话。
##
## ⑩ **084 近战侧的技能替换走引擎真入口**(2026-08-06 主会话已接上两行):
##    `RealtimeBattle3DScene._IMPL_SKILLS` 收录 `"eqCrossSlash"` + `_do_skill` 的 match 分派到
##    本文件的 `cast_cross_slash`。**两行必须成对** —— 只加常量会让引擎选中它而没有分支
##    ⇒ 技能静默变哑(门禁有一条 `wired == dispatched` 焊住)。
##    本文件的 `_hh_self_drive` 因此**已自动让位**(首行判 `_IMPL_SKILLS.has`), 留着是逃生口:
##    万一那两行被谁删掉, 装备退化成自驱而不是彻底哑掉。门禁有一条"连喂 5 帧也不双发"守着。


var battle
var vfx

## 084【后撤十字斩】的技能 type。
## ★引擎那张 `_IMPL_SKILLS` 表与 `_do_skill` 的 match 都在 `RealtimeBattle3DScene.gd`(共享文件, 不许动),
##   所以这个 type 现在**进不了引擎的选技/施放链**: `_pick_ready_skill` 查 `_IMPL_SKILLS` 查不到 → 跳过。
## ⇒ 本文件自己驱动(`_hh_self_drive`), 但**龟能经济仍然全走引擎的真机制**:
##   · 花费走 `u["energy_cost"][HH_SKILL] = 80`, 由 `battle._skill_cost` 读(不是我自己发明一个数)
##   · 充能走 `u["skill_cd"][HH_SKILL]`, 由 `_tick_skill_cd` 每帧扣(含 echarge_perm / 眩晕锁 / 龟能银行)
##   · 冷却重置与全局 GCD 也照引擎的写法(`_skill_cd` / `SKILL_GCD`)
## ★让位闸: 主会话若把 `"eqCrossSlash": true` 加进 `_IMPL_SKILLS`【并且】在 `_do_skill` 里加一条
##   `"eqCrossSlash": _equip_sys._blade_sys.cast_cross_slash(u, tgt)`, 自驱立刻停手(见 `_hh_self_drive` 首行),
##   施放改由引擎的真入口走 —— **两边都调同一个 `cast_cross_slash`**, 不会有第二份实现。
const HH_SKILL := "eqCrossSlash"
const HH_ENERGY := 80.0

## 084 十字斩四段的节拍(秒): ①横斩+②横波 → ③竖斩+④竖波
const CROSS_T1 := 0.25
const CROSS_T3 := 0.60
## 剑波: 推进速度(码/秒) / 最远行程(码) / 波前带半厚(码)
const WAVE_SPD := 900.0
const WAVE_RANGE := 700.0
const WAVE_BAND := 60.0

## 084 在途剑波 [{u, from, dir, half_w, seg, si, trav, hit:[]}]
var _waves: Array = []
## 084 十字斩的分段时刻表 [{u, dir, si, t, seg}] —— 用 battle._t(顿帧/时停跟着停), 不用墙钟
var _pending: Array = []


func _init(b) -> void:
	battle = b
	vfx = BladeEqVfx.new(b)


## 「这一次调用是本次事件的第几份」—— 身上带 n 份同一件装备时, 分派循环会连着调 n 次。
## 返回 true 表示这是**第一份**(第 0、n、2n… 次), 后面 n−1 次直接跳过。
## ★不依赖帧号/时钟, 只依赖"一次事件必定连着调 n 次"这个分派事实 ⇒ 高攻速 + 一帧多 sim 步也不漏。
func _nth_copy(u: Dictionary, eid: String, st: Dictionary) -> bool:
	var n: int = 0
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == eid:
			n += 1
	n = maxi(1, n)
	var c: int = int(st.get("call_n", 0))
	st["call_n"] = (c + 1) % n
	return c % n == 0


# ══════════════════════════════════════════════════════════════════════
#  十个钩子
# ══════════════════════════════════════════════════════════════════════

## 每帧全局推进: 084 的十字斩分段时刻表 + 在途剑波 + 演出
func tick(delta: float) -> void:
	_step_pending()
	_step_waves(delta)
	vfx.tick(delta)


## 每帧逐单位推进(守卫是常驻字段 `_b4_eq`, 在 EQ_TICK 闸之前 ⇒ 每帧精度)
func tick_unit(u: Dictionary, delta: float) -> void:
	if u.has("_b81_si"):
		_t081(u, delta)
	if u.has("_b83_si"):
		_t083(u, delta)
	if u.has("_b84_si"):
		_t084(u, delta)


## 携带者登场(每路开战、全队属性写完之后跑一次)
func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_081": _spawn081(u, si)
		"p2eq_082": _spawn082(u, si)
		"p2eq_083": _spawn083(u, si)
		"p2eq_084": _spawn084(u, si)


## 携带者普攻发出(不算多段)
func on_basic(u: Dictionary, tgt, eid: String, _si: int) -> void:
	if eid == "p2eq_082":
		_basic082(u, tgt)


## 携带者命中结算后
func on_hit(src: Dictionary, tgt: Dictionary, _dmg: float, eid: String, _si: int) -> void:
	if eid == "p2eq_083":
		_hit083(src, tgt)


## 携带者受到伤害后(★两条伤害路径都会调, 用 u["_b4_dot"] 分辨是哪一条)
func on_damaged(u: Dictionary, src, dmg: float, eid: String, _si: int) -> void:
	match eid:
		"p2eq_081": _damaged081(u, dmg)
		"p2eq_082": _damaged082(u, src)


## 携带者受到法术伤害后(本批不用: 081/082 都按"受到伤害/受到一段攻击"算, 不分法术物理)
func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者阵亡: 把还挂着的常驻加成撤干净(不撤的话统计面板/复活类效果会读到幽灵数值)
func on_death(u: Dictionary, eid: String, _si: int) -> void:
	match eid:
		"p2eq_081": _b81_lower(u, false)
		"p2eq_083":
			u["_b83_tgt"] = null
			_b83_reapply(u, 0, int(u.get("_b83_si", 0)))


## 法器法力条集满(本批不用)
func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## ★换路撤场: 在途剑波/分段时刻表里存着【上一路的单位字典】, 不清就是悬空引用 + 上一路的波飞进下一路。
func clear_all() -> void:
	_waves.clear()
	_pending.clear()
	if vfx != null:
		vfx.clear()


# ══════════════════════════════════════════════════════════════════════
#  ★081 藤编圆盾(1 费·盾) — 充能条 → 举盾
#    「每累计受到自身 40/35/30% 最大生命值的伤害后举盾 2.5/3/3.5 秒,
#      期间 +60/100/160 护盾值与 +50/80/140 双抗, 举盾期间受到的伤害不计入充能条,
#      举盾结束后重新开始计数」★举盾【不扣攻速】(用户 2026-08-06 最终拍板)
# ══════════════════════════════════════════════════════════════════════
func _spawn081(u: Dictionary, si: int) -> void:
	u["_b81_si"] = maxi(int(u.get("_b81_si", -1)), si)   # 多件同带取更高星
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	st["charge"] = 0.0
	st["up_until"] = 0.0      # 到期时刻(绝对), 不是"还剩几秒" —— _t 跨路累加(§3.4)
	st["res_given"] = 0.0
	st["raised"] = 0
	st["ev"] = -1
	u["eq_state"]["p2eq_081"] = st


## 充能条累计。★两条伤害路径都收(规格是"受到…的伤害", DoT 也算) ⇒ 不看 `_b4_dot`。
func _damaged081(u: Dictionary, dmg: float) -> void:
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	var ev: int = int(u.get("_st_taken", 0))
	if int(st.get("ev", -1)) == ev:
		return                                   # 同一段伤害被第二把 081 又调了一次
	st["ev"] = ev
	if battle._t < float(st.get("up_until", 0.0)):
		u["eq_state"]["p2eq_081"] = st
		vfx.guard_block(u)                       # ★盾真的吃下了这一下 ⇒ 盾面闪一下(实拍时零反馈)
		return                                   # ★举盾期间受到的伤害【不计入】充能条
	var sx: int = int(u.get("_b81_si", 0))
	var need: float = float(u.get("maxHp", 1.0)) * [0.40, 0.35, 0.30][sx]
	st["charge"] = float(st.get("charge", 0.0)) + maxf(0.0, dmg)
	# ★归一后的百分比: 装备图标框那张表(PANEL_CHARGE)的分母只能是**常量**,
	#   而这件的需求是 maxHp×40/35/30% ⇒ 在这里就把它化成 0~100。
	st["chg_pct"] = clampf(float(st["charge"]) / maxf(1.0, need) * 100.0, 0.0, 100.0)
	u["eq_state"]["p2eq_081"] = st
	if float(st["charge"]) >= need:
		st["charge"] = 0.0                       # 决定②: 满了归零, 不保留溢出
		st["chg_pct"] = 0.0
		u["eq_state"]["p2eq_081"] = st
		_b81_raise(u, sx)


## 举盾。★同步入口, 门禁直接调 —— 不依赖任何演出 tween 跑完(CLAUDE.md §3.5)。
func _b81_raise(u: Dictionary, sx: int) -> void:
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	st["up_until"] = battle._t + [2.5, 3.0, 3.5][sx]
	st["raised"] = int(st.get("raised", 0)) + 1   # 同步触发证据(门禁看它, 不看有没有建节点)
	var res: float = [50.0, 80.0, 140.0][sx]      # 双抗(护甲与魔抗各 +res)
	u["base_def"] = float(u.get("base_def", 0.0)) + res
	u["base_mr"] = float(u.get("base_mr", 0.0)) + res
	st["res_given"] = res
	u["eq_state"]["p2eq_081"] = st
	battle._recalc_stats(u)
	# ★护盾要让盾羁绊 9 档【圣光·强化】认得出是"盾类装备给的" ⇒ 先标 _cur_eq_item(用完还原)
	var prev = battle._cur_eq_item
	battle._cur_eq_item = "p2eq_081"
	battle._damage._grant_shield(u, [60.0, 100.0, 160.0][sx])
	battle._cur_eq_item = prev
	vfx.guard_raise(u)
	# ★★这里【绝不加攻速惩罚】: 用户 2026-08-06 最终拍板"举盾不扣攻速"。
	#   方案书 §0.5 记了这条方向翻转过两次(固定0.5/秒 → 降70% → 不扣), 两版都是"惩罚谁"的结构问题,
	#   不是数值大小问题。门禁 verify_eq_blade_batch 有一条专门验举盾前后 aspd_perm/atk_interval 不变。


## 落盾(到期或阵亡)。★演出节点【无论哪条路都收】—— 阵亡那条不收的话, 盾面会一直挂在
## 死人身上直到换路(演出泄漏)。show_vfx 只控制"落盾的那一下有没有反馈", 不控制清理。
func _b81_lower(u: Dictionary, show_vfx: bool = true) -> void:
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	var res: float = float(st.get("res_given", 0.0))
	st["up_until"] = 0.0
	st["charge"] = 0.0                            # 「举盾结束后重新开始计数充能条」
	st["chg_pct"] = 0.0
	if res > 0.0:
		u["base_def"] = maxf(0.0, float(u.get("base_def", 0.0)) - res)
		u["base_mr"] = maxf(0.0, float(u.get("base_mr", 0.0)) - res)
		st["res_given"] = 0.0
		u["eq_state"]["p2eq_081"] = st
		battle._recalc_stats(u)
	else:
		u["eq_state"]["p2eq_081"] = st
	vfx.guard_lower(u, show_vfx)


func _t081(u: Dictionary, _delta: float) -> void:
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	var uu: float = float(st.get("up_until", 0.0))
	if uu > 0.0 and battle._t >= uu:
		_b81_lower(u)


## 现在是不是举着盾。★纯查询, 门禁与演出都调它(不各自抄一遍判据)。
func b81_guarding(u: Dictionary) -> bool:
	if not (u.get("eq_state", null) is Dictionary):
		return false
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_081", {})
	return battle._t < float(st.get("up_until", 0.0))


# ══════════════════════════════════════════════════════════════════════
#  ★082 砗磲护心甲(2 费·盾) — 【护心反伤】
#    「每受到一段攻击反伤 3/5/8 点魔法伤害给攻击者; 每反伤 15 次攒一层充能;
#      携带者普攻消耗一层, 回复 5/7/10% 最大生命值, 并附带相当于自身 100% 魔抗的魔法伤害」
#    ✅ 用户 2026-08-06:「不算, 独立, 不触发」= DoT 每跳不算 / 多段各段独立 / 反伤不触发对方反伤
# ══════════════════════════════════════════════════════════════════════
const CLAM_PER_CHARGE := 15   # 每反伤 15 次攒一层(规格是单值不是三元组, 不随星级变)
## 082 充能条的颜色(青白) —— 与 081 的藤绿分得开, 同屏两件同带时读得出是哪一条
const CLAM_BAR_COL := Color(0.62, 0.95, 0.90, 0.95)


func _spawn082(u: Dictionary, si: int) -> void:
	u["_b82_si"] = maxi(int(u.get("_b82_si", -1)), si)
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_082", {})
	st["refl_n"] = 0
	st["charges"] = 0
	st["ev"] = -1
	st["call_n"] = 0   # 普攻钩的"第几份"计数(见 _nth_copy)
	u["eq_state"]["p2eq_082"] = st


## 护心反伤。★DoT 每跳【不算】"一段攻击" ⇒ 读 `_b4_dot` 直接 return(用户明确拍板)。
func _damaged082(u: Dictionary, src) -> void:
	if bool(u.get("_b4_dot", false)):
		return                                   # ★DoT/真伤路: 灼烧/中毒/流血每跳都不喂充能
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_082", {})
	var ev: int = int(u.get("_st_taken", 0))
	if int(st.get("ev", -1)) == ev:
		return                                   # 多件同带去重(同一段攻击只反一次)
	st["ev"] = ev
	u["eq_state"]["p2eq_082"] = st
	if not (src is Dictionary) or not src.get("alive", false) or is_same(src, u):
		return                                   # is_same: 单位字典互引成环, == 会深比较→卡死
	var sx: int = int(u.get("_b82_si", 0))
	var d: int = battle._resolve_dmg(u, [3.0, 5.0, 8.0][sx], src, true)   # 魔法 ⇒ 吃对方魔抗
	# ★from_equip = true: 不回钩 on-hit ⇒ **不触发对方的反伤**(用户拍板, 防无限套娃)
	battle._damage._apply_damage_from(u, src, d, Color("#9ff0d8"), 0.0, false, true)
	st["refl_n"] = int(st.get("refl_n", 0)) + 1
	if int(st["refl_n"]) >= CLAM_PER_CHARGE:
		st["refl_n"] = int(st["refl_n"]) - CLAM_PER_CHARGE
		st["charges"] = int(st.get("charges", 0)) + 1
	u["eq_state"]["p2eq_082"] = st
	vfx.clam_reflect(u, src)
	# ★充能进度(refl_n/15)与层数(charges)都已写进 `eq_state`,
	#   由**装备图标框**那套现成机制显示(PANEL_CHARGE / PANEL_COUNT), 不再在头顶另画一套
	#   (用户 2026-08-08:「充能条和层数不要放头顶」)。


## 普攻消耗一层充能: 回复 5/7/10% 最大生命 + 附带 100% 魔抗的魔法伤害。
func _basic082(u: Dictionary, tgt) -> void:
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_082", {})
	if not _nth_copy(u, "p2eq_082", st):
		u["eq_state"]["p2eq_082"] = st
		return                                   # 多件同带: 一次普攻只消耗一层
	if int(st.get("charges", 0)) <= 0:
		u["eq_state"]["p2eq_082"] = st
		return
	st["charges"] = int(st["charges"]) - 1
	st["spent"] = int(st.get("spent", 0)) + 1    # 同步触发证据
	u["eq_state"]["p2eq_082"] = st
	var sx: int = int(u.get("_b82_si", 0))
	var prev = battle._cur_eq_item
	battle._cur_eq_item = "p2eq_082"             # 盾类装备的治疗 → 盾羁绊 9 档转 20% 圣光盾
	battle._damage._heal(u, float(u.get("maxHp", 0.0)) * [0.05, 0.07, 0.10][sx])
	battle._cur_eq_item = prev
	if tgt is Dictionary and (tgt as Dictionary).get("alive", false):
		# ★「相当于自身 100% 魔抗」取【当前】魔抗(含举盾/硬化/羁绊给的) —— 决定④
		var d: int = battle._resolve_dmg(u, float(u.get("mr", 0.0)), tgt, true)
		battle._damage._apply_damage_from(u, tgt, d, Color("#7fe8ff"), 0.0, false, true)
		vfx.clam_burst(u, tgt)


## 当前充能层数 / 累计反伤次数。★纯查询, 门禁用。
func b82_charges(u: Dictionary) -> int:
	return int(((u.get("eq_state", {}) as Dictionary).get("p2eq_082", {}) as Dictionary).get("charges", 0))


func b82_reflects(u: Dictionary) -> int:
	var st: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_082", {})
	return int(st.get("charges", 0)) * CLAM_PER_CHARGE + int(st.get("refl_n", 0))


# ══════════════════════════════════════════════════════════════════════
#  ★083 潮汐细剑(3 费·剑)
#    被动: 每损失 1% 生命值 +0.2/0.3/0.4% 攻击速度
#    主动: 连续命中同一目标叠层(至多 20 层), 每层 +1/1.5/2% 增伤 + 0.5% 生命偷取,
#          切换目标或目标死亡即清空
#    ✅ 用户 2026-08-06:「算, 算, 可以」= 剑羁绊【剑士】的追打【计入】连续命中
# ══════════════════════════════════════════════════════════════════════
const RAPIER_CAP := 20        # 层数硬顶(规格单值)
const RAPIER_LS_PER := 0.005  # 每层 0.5% 生命偷取(★不随星级变, §0.5 明写"满层 10% 吸血, 三档一样")


func _spawn083(u: Dictionary, si: int) -> void:
	u["_b83_si"] = maxi(int(u.get("_b83_si", -1)), si)
	u["_b83_tgt"] = null
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_083", {})
	st["stacks"] = 0
	st["amp_given"] = 0.0
	st["ls_given"] = 0.0
	st["aspd_given"] = 0.0
	st["ev"] = -1
	u["eq_state"]["p2eq_083"] = st


## 连续命中同一目标叠层。
## ★剑士追打天然走这条钩 —— 追打调 `_apply_damage_from`(from_equip 默认 false), 管线内部回钩
##   `_eq_on_hit` ⇒ 本函数照常被调。**不需要在这里认追打**, 也不该认(认了就是手抄副本)。
func _hit083(src: Dictionary, tgt: Dictionary) -> void:
	var st: Dictionary = (src["eq_state"] as Dictionary).get("p2eq_083", {})
	var ev: int = int(src.get("_st_dealt", 0))
	if int(st.get("ev", -1)) == ev:
		return                                   # 多件同带去重
	st["ev"] = ev
	var prev = src.get("_b83_tgt", null)
	var same: bool = prev is Dictionary and is_same(prev, tgt)
	var stacks: int = mini(RAPIER_CAP, (int(st.get("stacks", 0)) if same else 0) + 1)
	st["stacks"] = stacks
	src["eq_state"]["p2eq_083"] = st
	src["_b83_tgt"] = tgt
	_b83_reapply(src, stacks, int(src.get("_b83_si", 0)))
	vfx.rapier_stack(src, stacks)


## 把"层数带来的增伤/吸血"重算一遍(装备 "p2eq_083" 的就近锚点)。
## ★先撤掉本件上一次的贡献再加新的 —— 不撤就是在旧值上叠, 20 层会翻好几倍
##   (SignalWaveSystem._reapply_stack_bonus 是同一个写法, 本项目既有惯例)。
func _b83_reapply(u: Dictionary, stacks: int, sx: int) -> void:
	var st: Dictionary = (u.get("eq_state", {}) as Dictionary).get("p2eq_083", {})
	var old_amp: float = float(st.get("amp_given", 0.0))
	var old_ls: float = float(st.get("ls_given", 0.0))
	u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - old_amp)
	u["lifesteal"] = maxf(0.0, float(u.get("lifesteal", 0.0)) - old_ls)
	var amp: float = [0.01, 0.015, 0.02][sx] * float(stacks)
	var ls: float = RAPIER_LS_PER * float(stacks)
	u["damage_amp"] = float(u.get("damage_amp", 0.0)) + amp
	u["lifesteal"] = float(u.get("lifesteal", 0.0)) + ls
	st["amp_given"] = amp
	st["ls_given"] = ls
	st["stacks"] = stacks
	u["eq_state"]["p2eq_083"] = st


## 每帧: ① 目标死了就清层 ② 被动攻速跟着当前血量实时走。
func _t083(u: Dictionary, _delta: float) -> void:
	var sx: int = int(u.get("_b83_si", 0))
	var st: Dictionary = (u["eq_state"] as Dictionary).get("p2eq_083", {})
	var t = u.get("_b83_tgt", null)
	if t is Dictionary and not (t as Dictionary).get("alive", false):
		u["_b83_tgt"] = null                     # 「目标死亡也算切换目标」⇒ 清空
		if int(st.get("stacks", 0)) > 0:
			_b83_reapply(u, 0, sx)
	# 被动: 每损失 1% 生命 → +0.2/0.3/0.4% 攻速。走 aspd_perm(项目的永久攻速加法通道)。
	var mx: float = maxf(1.0, float(u.get("maxHp", 1.0)))
	var lost_pct: float = clampf(1.0 - float(u.get("hp", 0.0)) / mx, 0.0, 1.0) * 100.0
	var want: float = lost_pct * [0.2, 0.3, 0.4][sx] / 100.0
	var given: float = float(st.get("aspd_given", 0.0))
	if absf(want - given) > 1e-6:
		u["aspd_perm"] = maxf(0.01, float(u.get("aspd_perm", 1.0)) - given) + want
		st["aspd_given"] = want
		u["eq_state"]["p2eq_083"] = st


func b83_stacks(u: Dictionary) -> int:
	return int(((u.get("eq_state", {}) as Dictionary).get("p2eq_083", {}) as Dictionary).get("stacks", 0))


# ══════════════════════════════════════════════════════════════════════
#  ★084 手半剑(4 费·剑) — 效果随携带者是近战还是远程而改变
#    近战 → 获得 450 码射程 + 技能换成 80 龟能的【后撤十字斩】
#    远程 → 射程固定 100 码 + 200/400/1000 最大生命 + 登场时攻击力的 10/15/20% + 10/12.5/15% 吸血,
#           且每转化 100 码射程使这些属性 +20%(★实时)
# ══════════════════════════════════════════════════════════════════════
func _spawn084(u: Dictionary, si: int) -> void:
	u["_b84_si"] = maxi(int(u.get("_b84_si", -1)), si)
	var sx: int = int(u["_b84_si"])
	if u.has("_b84_mode"):
		# 多件同带: 形态只装一次, 但**星级要按新的 max 立刻重算一遍** ——
		# 不重算的话"先 1★ 后 3★"这个顺序会停在 1★ 的量, 直到下一帧 tick_unit 才补上。
		# _b84_refresh 是差量施加 ⇒ 重算不会叠成两份。
		if str(u["_b84_mode"]) == "ranged":
			_b84_refresh(u, sx)
		return
	if bool(u.get("melee", false)):
		u["_b84_mode"] = "melee"
		# ★只改射程【数值】, 不改 melee 标记(用户拍板: 改标记会连"近战最小射程钳制"等规则一起变)
		u["atk_range"] = 450.0
		if not u.has("_b84_o_skills"):
			u["_b84_o_skills"] = (u.get("active_skills", []) as Array).duplicate()
		var ec: Dictionary = u.get("energy_cost", {})
		ec[HH_SKILL] = HH_ENERGY                 # 花费走引擎的 _skill_cost 真表, 不自己发明
		u["energy_cost"] = ec
		u["active_skills"] = [HH_SKILL]
		var cds: Dictionary = u.get("skill_cd", {})
		cds.clear()                              # 本体技已被替换 ⇒ 旧技的冷却槽一并清掉
		# 起始冷却照引擎的懒初始化写法: 满冷却 − 装备初始龟能折算
		cds[HH_SKILL] = maxf(0.0, battle._skill_cd(u, HH_SKILL) - float(u.get("init_energy_bonus", 0.0)) * 0.075)
		u["skill_cd"] = cds
	else:
		u["_b84_mode"] = "ranged"
		u["_b84_atk0"] = float(u.get("atk", 0.0))   # ★「登场时的攻击力」是快照
		# ★影子字段从"有效射程恰好 100"的基线起算, 登场时的真实射程由 _b84_refresh 按
		#   【增量】折进来(atk_range−100 / range_add−0 / range_perm−1)。
		#   ⚠ 这里【不要】直接把 atk_range 抄进 _b84_nat_range —— 那样 refresh 会再折一次, 转化量翻倍。
		u["_b84_nat_range"] = 100.0
		u["_b84_nat_add"] = 0.0
		u["_b84_nat_perm"] = 1.0
		u["_b84_hp_given"] = 0.0
		u["_b84_atk_given"] = 0.0
		u["_b84_ls_given"] = 0.0
		_b84_refresh(u, sx)


## ★远程侧的【实时】射程转化(装备 "p2eq_084" 的就近锚点)。
## 用户原话:「如果携带者在战斗中获得了射程, 也要被及时转化掉并获得属性」⇒ 不能登场快照。
## 每帧跑: 把任何新到的射程折进影子字段 → 有效射程回到 100 → 按转化量重算三项属性(差量施加)。
func _b84_refresh(u: Dictionary, sx: int) -> void:
	# ① 把三条射程通道上【新出现的】部分折进影子字段, 再把通道清回"有效射程 = 100"的状态
	u["_b84_nat_add"] = float(u.get("_b84_nat_add", 0.0)) + float(u.get("range_add", 0.0))
	u["range_add"] = 0.0
	u["_b84_nat_perm"] = float(u.get("_b84_nat_perm", 1.0)) + (float(u.get("range_perm", 1.0)) - 1.0)
	u["range_perm"] = 1.0
	u["_b84_nat_range"] = float(u.get("_b84_nat_range", 70.0)) + (float(u.get("atk_range", 100.0)) - 100.0)
	u["atk_range"] = 100.0
	# ② 转化量 = max(0, 自然有效射程 − 100); 每 100 码 +20%
	var nat: float = (float(u["_b84_nat_range"]) + float(u["_b84_nat_add"])) * float(u["_b84_nat_perm"])
	var conv: float = maxf(0.0, nat - 100.0)
	u["_b84_conv"] = conv
	u["_b84_mult"] = 1.0 + 0.20 * (conv / 100.0)
	var mult: float = float(u["_b84_mult"])
	# ③ 三项属性按差量施加(镜像撤旧, 不在旧值上叠)。★装备 hp 已是最终值, 不乘 HP_MULT(§3.1)
	var want_hp: float = [200.0, 400.0, 1000.0][sx] * mult
	var want_atk: float = float(u.get("_b84_atk0", 0.0)) * [0.10, 0.15, 0.20][sx] * mult
	var want_ls: float = [0.10, 0.125, 0.15][sx] * mult
	var dirty: bool = false
	var dhp: float = want_hp - float(u.get("_b84_hp_given", 0.0))
	if absf(dhp) > 0.001:
		u["maxHp"] = maxf(1.0, float(u.get("maxHp", 1.0)) + dhp)
		u["hp"] = maxf(1.0, minf(float(u["maxHp"]), float(u.get("hp", 1.0)) + dhp))
		u["_b84_hp_given"] = want_hp
		dirty = true
	var datk: float = want_atk - float(u.get("_b84_atk_given", 0.0))
	if absf(datk) > 0.001:
		u["base_atk"] = maxf(0.0, float(u.get("base_atk", 0.0)) + datk)
		u["_b84_atk_given"] = want_atk
		dirty = true
	var dls: float = want_ls - float(u.get("_b84_ls_given", 0.0))
	if absf(dls) > 1e-6:
		u["lifesteal"] = maxf(0.0, float(u.get("lifesteal", 0.0)) + dls)
		u["_b84_ls_given"] = want_ls
		dirty = true
	if dirty:
		battle._recalc_stats(u)


func _t084(u: Dictionary, delta: float) -> void:
	var sx: int = int(u.get("_b84_si", 0))
	if str(u.get("_b84_mode", "")) == "ranged":
		_b84_refresh(u, sx)                      # ★实时: 每帧重算, 不是登场快照
	else:
		_hh_self_drive(u, delta)


## 近战侧的技能自驱。★让位闸在第一行 —— 主会话把 HH_SKILL 接进 `_IMPL_SKILLS` + `_do_skill` 之后,
##   引擎自己会选技/施放, 这里立刻停手, 不会双发。
func _hh_self_drive(u: Dictionary, _delta: float) -> void:
	if battle._IMPL_SKILLS.has(HH_SKILL):
		return
	if not u.get("alive", false):
		return
	var cds: Dictionary = u.get("skill_cd", {})
	if not cds.has(HH_SKILL) or float(cds[HH_SKILL]) > 0.0:
		return                                   # 龟能没满(冷却由引擎 _tick_skill_cd 扣, 不是我自己扣)
	if battle._t < float(u.get("skill_gcd_until", 0.0)):
		return
	if battle._t < float(u.get("stun_until", 0.0)) or u.get("airborne", false):
		return
	var tgt = battle._targeting._nearest_enemy(u)
	if tgt == null or not (tgt as Dictionary).get("alive", false):
		return
	if ((tgt as Dictionary)["pos"] - u["pos"]).length() > battle._eff_range(u):
		return
	cds[HH_SKILL] = battle._skill_cd(u, HH_SKILL)
	u["skill_gcd_until"] = battle._t + battle.SKILL_GCD
	cast_cross_slash(u, tgt)


## ★★【后撤十字斩】唯一入口 —— 自驱与(将来的)`_do_skill` 分支都调它, 只有这一份实现。
## 后撤 150 码 → 0.25 秒后横斩 + 横波 → 0.60 秒后竖斩 + 竖波。
func cast_cross_slash(u: Dictionary, tgt) -> void:
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	var sx: int = int(u.get("_b84_si", 0))
	var dest: Vector2 = cross_retreat_dest(u, tgt)
	u["pos"] = dest
	if u.has("_home_pos"):
		u["_home_pos"] = dest                    # ★只在【本来就有】时才写, 绝不凭空创建(评审假人归位坑)
	var dir: Vector2 = (tgt as Dictionary)["pos"] - dest
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	u["_b84_casts"] = int(u.get("_b84_casts", 0)) + 1   # 同步触发证据
	u["face_right"] = dir.x > 0.0
	vfx.cross_retreat(u, dest, dir)
	_pending.append({"u": u, "dir": dir, "si": sx, "t": battle._t + CROSS_T1, "seg": 1})
	_pending.append({"u": u, "dir": dir, "si": sx, "t": battle._t + CROSS_T3, "seg": 3})


## 后撤落点(纯几何, 门禁验这个而不是等 tween 跑到)。背对目标退 150 码, 钳在场地内。
func cross_retreat_dest(u: Dictionary, tgt: Dictionary) -> Vector2:
	var away: Vector2 = u["pos"] - tgt["pos"]
	away = away.normalized() if away.length() > 0.01 else Vector2.LEFT
	var p: Vector2 = u["pos"] + away * 150.0
	p.x = clampf(p.x, battle.ARENA.position.x, battle.ARENA.end.x)
	p.y = clampf(p.y, battle.ARENA.position.y, battle.ARENA.end.y)
	return p


## 分段时刻表推进(用 battle._t —— 顿帧/时停时演出与结算一起停)。
func _step_pending() -> void:
	if _pending.is_empty():
		return
	var keep: Array = []
	for p in _pending:
		if battle._t < float(p["t"]):
			keep.append(p)
			continue
		var u: Dictionary = p["u"]
		if not u.get("alive", false):
			continue
		var seg: int = int(p["seg"])
		var dir: Vector2 = p["dir"]
		var sx: int = int(p["si"])
		cross_slash_hit(u, dir, sx, seg)
		_waves.append({
			"u": u, "from": u["pos"], "dir": dir, "si": sx,
			"seg": seg + 1, "half_w": (125.0 if seg == 1 else 45.0),
			"trav": 0.0, "hit": [],
		})
		vfx.cross_wave(u, u["pos"], dir, seg + 1)
	_pending = keep


## ①横斩(250 码 120° 扇形) / ③竖斩(250 码 60° 扇形)。返回命中数(同步证据, 门禁直接调)。
## (装备 "p2eq_084" —— tooltip_number_audit 的就近锚点)
func cross_slash_hit(u: Dictionary, dir: Vector2, sx: int, seg: int) -> int:
	var half: float = (1.0471975512 if seg == 1 else 0.5235987756)   # 120°/2 与 60°/2, 弧度字面量
	var flat: float = ([40.0, 70.0, 130.0][sx] if seg == 1 else [50.0, 85.0, 160.0][sx])
	var sc: float = ([0.6, 0.9, 1.4][sx] if seg == 1 else [0.7, 1.1, 1.7][sx])
	var n: int = 0
	for o in battle._targeting._enemies_of(u):
		if not (o is Dictionary) or not (o as Dictionary).get("alive", false):
			continue
		var rel: Vector2 = (o as Dictionary)["pos"] - u["pos"]
		if rel.length() > 250.0:
			continue
		if rel.length() > 0.01 and absf(rel.angle_to(dir)) > half:
			continue
		var d: int = battle._resolve_dmg(u, flat + float(u.get("atk", 0.0)) * sc, o, false)
		battle._damage._apply_damage_from(u, o, d, Color("#dbe9ff"), 0.0, false, true)
		n += 1
	vfx.cross_slash(u, dir, seg)
	return n


## ②横波 / ④竖波: 沿施法朝向直线推进、贯穿(每个敌人每道波只吃一次)。
## (装备 "p2eq_084" —— tooltip_number_audit 的就近锚点)
func _step_waves(delta: float) -> void:
	if _waves.is_empty():
		return
	var keep: Array = []
	for w in _waves:
		var u: Dictionary = w["u"]
		var seg: int = int(w["seg"])
		var sx: int = int(w["si"])
		w["trav"] = float(w["trav"]) + WAVE_SPD * delta
		var trav: float = float(w["trav"])
		if u.get("alive", false):
			var flat: float = ([25.0, 45.0, 85.0][sx] if seg == 2 else [30.0, 55.0, 100.0][sx])
			var sc: float = ([0.4, 0.6, 0.9][sx] if seg == 2 else [0.5, 0.7, 1.1][sx])
			var dir: Vector2 = w["dir"]
			var org: Vector2 = w["from"]
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			for o in battle._targeting._enemies_of(u):
				if not (o is Dictionary) or not (o as Dictionary).get("alive", false):
					continue
				if battle._arr_has_unit(w["hit"], o):
					continue                     # ★引用判重: in/has() 对单位字典是深比较→卡死
				var rel: Vector2 = (o as Dictionary)["pos"] - org
				if absf(rel.dot(dir) - trav) > WAVE_BAND:
					continue
				if absf(rel.dot(perp)) > float(w["half_w"]):
					continue
				(w["hit"] as Array).append(o)
				var d: int = battle._resolve_dmg(u, flat + float(u.get("atk", 0.0)) * sc, o, false)
				battle._damage._apply_damage_from(u, o, d, Color("#bcd8ff"), 0.0, false, true)
		if trav < WAVE_RANGE:
			keep.append(w)
	_waves = keep


## 在途剑波条数(同步证据, 门禁用)。
func b84_waves() -> int:
	return _waves.size()


## 十字斩还有几段没结算(同步证据, 门禁用)。
func b84_pending() -> int:
	return _pending.size()
