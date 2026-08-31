class_name AxeEvolution
extends RefCounted
## 小木斧的【进化档位表】—— 纯数据, 没有行为 (用户 2026-08-31)
##
## ★这份表是小木斧一切数值的**唯一事实源**。装备属性、召唤物属性、进化阈值、
##   商店售价、斧头配色索引全从这里取; 别在别处再存一份(036 温泉蛋刚踩过
##   "同一个数存两份必漂"的坑, 它有两个写入点)。
##
## ★需求原文(用户 2026-08-31)节选:
##   「小木斧（1费）：为携带者提供20最大生命值，10攻击力，2护甲，2魔抗。
##     会有一个斧头召唤物（初始为木斧）登场，近战，普攻造成1ATK，攻速为0.8每秒。
##     斧头召唤物拥有500+已收集的经验值最大生命值，30+0.05已收集的经验值攻击力，
##     5护甲和5魔抗」
##   「满80经验值进化为石斧，满110铁斧，满130金斧，满160钻石斧，
##     此后积攒400经验值来完成一次最终进化。」
##
## ★已拍板的两条口径:
##   · 未决点 ⑥「已收集的经验值」= **历史累计**(`axe_exp_total`), 不是当前进度条。
##     ⇒ 进度条进化时清零、累计值只增不减; 大轮重置时两个都归零。
##     否则每次进化召唤物反而变弱, 进化成了惩罚。
##   · 未决点 ③ 费用**封顶 5 费** —— 本作出货表 `roll_cost_tier` 只认 1~5。
##     木斧 1 费, 每进化 +1 ⇒ 石2/铁3/金4/钻5, 最终造物**不再 +1**(仍是 5)。

## ── 档位 ──────────────────────────────────────────────────────
## 顺序即进化顺序。`need` = 从**上一档**升到本档需要攒够的进度条(需求给的是每段独立的阈值,
## 不是累计到 160 —— 见方案书「出入」第 6 条)。木斧是起点所以 need = 0。
const STAGES := [
	{"key": "wood",    "name": "木斧",   "need": 0,   "cost": 1},
	{"key": "stone",   "name": "石斧",   "need": 80,  "cost": 2},
	{"key": "iron",    "name": "铁斧",   "need": 110, "cost": 3},
	{"key": "gold",    "name": "金斧",   "need": 130, "cost": 4},
	{"key": "diamond", "name": "钻石斧", "need": 160, "cost": 5},
]
## 四个进化阈值的【扁平投影】—— **只为图鉴文案的数组占位符而存在**
## (`{C:AxeEvolution.STAGE_NEEDS}` 会渲染成 "80/110/130/160"; 占位符没法索引 STAGES 里的字典)。
## ★这是一份镜像, 天生有漂的风险 ⇒ 门禁 verify_axe 逐项比对它与 STAGES[i+1]["need"],
##   改了 STAGES 忘了改这里**当场红**。别把它当第二个事实源用, 代码里一律读 STAGES。
const STAGE_NEEDS := [80, 110, 130, 160]

## 钻石斧之后再攒这么多, 才能做最终进化(四选一)。
const FINAL_NEED := 400

## 四个最终造物。**都是 5 费**(封顶, 未决点 ③)。
const FINALS := [
	{"key": "undead",   "name": "亡灵之斧", "cost": 5},
	{"key": "seraph",   "name": "炽天使",   "cost": 5},
	{"key": "holo",     "name": "全息斧",   "cost": 5},
	{"key": "ember",    "name": "余烬",     "cost": 5},
]

## ── 经验来源(需求字面值) ──────────────────────────────────────
const EXP_ON_BUY := 15          # 在商店里买这件装备
const EXP_ON_MATCH := 10        # 打完一整场对局(未决点 ②: 不论有没有走到决胜)
const EXP_ON_KILL := 2          # 斧头击杀, 或 3 秒内参与击杀
const ASSIST_WINDOW := 3.0      # "参与击杀"的时间窗(秒)

## ── 装备给携带者的属性(需求字面值·不随进化变) ────────────────
const OWNER_HP := 20.0
const OWNER_ATK := 10.0
const OWNER_DEF := 2.0
const OWNER_MR := 2.0

## ── 斧头召唤物 ────────────────────────────────────────────────
## 基础(木斧): 血 500 + 累计经验; 攻 30 + 0.05×累计经验; 双抗 5; 近战 1ATK 0.8 攻速
const MINION_HP_BASE := 500.0
const MINION_HP_PER_EXP := 1.0
const MINION_ATK_BASE := 30.0
const MINION_ATK_PER_EXP := 0.05
## 立绘的【视觉】尺寸参数(battle_spawn 只拿它算 pixel_size, **不管碰撞**, 已核实无第二个消费者)。
## ★由来(2026-09-01 用户抓「方向」时连带量出来的): 原来给的 26 让斧头小将的
##   世界身高只有 0.708 m, 而 28 只龟的中位是 1.40 m ⇒ **它只有龟的一半高**。
##   它是个"拿斧头的小将", 不该比龟矮一半。
##   反解: pixel_size = (TARGET_BODY_H × col/56) / 帧高, 身高 = 内容高 × pixel_size
##   ⇒ 内容 61px / 帧 80px 时, col=48 给出 1.31 m ≈ 龟中位的 94%。
## ★门禁 verify_axe_art 拿【龟身高的真实分布】卡它, 不是拿我拍的数字卡。
const MINION_COL_SIZE := 48.0

const MINION_DEF := 5.0
const MINION_MR := 5.0
const MINION_ASPD := 0.8

## 被动 3/4/5/6 每解锁一条给召唤物的加成(需求: 每条都是同样这四个数)。
const PASSIVE_HP := 50.0
const PASSIVE_ATK := 5.0
const PASSIVE_DEF := 3.0
const PASSIVE_MR := 3.0

## ── 通用主动(所有档位共有) ────────────────────────────────────
const ACTIVE_ENERGY := 140.0     # 龟能消耗
const ACTIVE_HEAL_PCT := 0.05    # 回复 5% 最大生命
const ACTIVE_SHIELD_PCT := 0.05  # 并给自己 5% 最大生命的护盾

## ── 出货概率(四期实现·用户 2026-08-31 拍板) ────────────────────
## 需求原话:「买了木斧并装备木斧, 激活斧头羁绊后, 概率将为 3% 加玩家激活斧头羁绊时
##   在这大轮游戏的局数×0.1%, 最终概率最高为 10%」。
## ★★这三个数是【整个货架至少出一个】的概率(未决点 ⑫, 用户拍板), **不是每一格**。
##   商店 10 格 ⇒ 每格概率要由 `1-(1-q)^格数 = P` 反解: q = 1-(1-P)^(1/格数)。
##   把 3% 直接当每格用是 **10 倍** 的差(封顶时"每次刷新至少见到一把"会从 10% 变成 65%)。
## ★未激活羁绊时**不走这条** —— 仍按 1 费档出货(它本来就是 1 费装备, 天然成立),
##   等级起来后 1 费概率自然衰减, 正是"不玩这流派就越来越少见"。
const SHELF_P_BASE := 0.03        # 刚激活羁绊
const SHELF_P_PER_MATCH := 0.001  # 每多打一局
const SHELF_P_CAP := 0.10         # 封顶


## 激活羁绊后打了 `matches` 局时, **整个货架**至少出一把的概率。
static func shelf_prob(matches: int) -> float:
	return minf(SHELF_P_CAP, SHELF_P_BASE + SHELF_P_PER_MATCH * float(maxi(0, matches)))


## 把"整货架 P"反解成"每格 q": 1-(1-q)^n = P  ⇒  q = 1-(1-P)^(1/n)。
## ★门禁会拿 `1-(1-q)^n` 回代验它等于 P —— 反解写反了(比如直接 P/n)当场红。
static func slot_prob(matches: int, slots: int) -> float:
	var p: float = shelf_prob(matches)
	if slots <= 0:
		return 0.0
	return 1.0 - pow(1.0 - p, 1.0 / float(slots))


## ── 被动 2(木斧就解锁): 普攻窃取目标护盾 ──────────────────────
const SHIELD_STEAL_PCT := 0.10   # 偷 10%, **转成普通护盾**给自己(特殊护盾也转)


## 本档索引 → 这一档的定义。越界钳住(防"最终进化后索引跑出去"把游戏搞崩)。
static func stage(i: int) -> Dictionary:
	return STAGES[clampi(i, 0, STAGES.size() - 1)]


## 从第 `i` 档升到第 `i+1` 档要攒够多少进度。已经是最后一档 → 返回最终进化的 400。
static func need_for_next(i: int) -> int:
	if i + 1 < STAGES.size():
		return int(STAGES[i + 1]["need"])
	return FINAL_NEED


## 召唤物在【历史累计经验 = exp_total】时的最大生命 / 攻击力。
## ★纯函数, 门禁直接调它验数 —— 不必打一场真战斗去撞。
static func minion_hp(exp_total: int, passives_unlocked: int = 0) -> float:
	return MINION_HP_BASE + MINION_HP_PER_EXP * float(exp_total) \
		+ PASSIVE_HP * float(maxi(0, passives_unlocked))


static func minion_atk(exp_total: int, passives_unlocked: int = 0) -> float:
	return MINION_ATK_BASE + MINION_ATK_PER_EXP * float(exp_total) \
		+ PASSIVE_ATK * float(maxi(0, passives_unlocked))


## 第 `i` 档解锁了几条【带属性的】被动。被动 2(木斧)不给属性, 被动 3~6 各给一份
## ⇒ 木斧 0 条、石斧 1 条、铁斧 2 条、金斧 3 条、钻石斧 4 条。
static func passives_at(i: int) -> int:
	return clampi(i, 0, STAGES.size() - 1)


## ── 四期: 进化推进(纯函数) ────────────────────────────────────
## 攒 `n` 点经验之后的新状态。**不碰 GameState** —— 门禁直接调它验数, 不必打一场真对局。
##
## ★两个字段【同源写入】(方案书风险 5): 一次加经验同时算出进度条与历史累计。
##   分成两处各写各的那一刻, 就埋下了"一个数存两份"的坑。
##     · bar   进化时**清空**(需求原话「每次清空进度条」—— 溢出部分丢弃, 不结转)
##     · total **只增不减**, 进化不动它 —— 召唤物的血/攻公式读的是它
## ★一次 add 最多进化一档: 清空之后 bar=0, 再判一次也过不了阈值。
##   (经验单笔最大 +15 而最小阈值 80 ⇒ 实战里根本够不到"一次跨两档")
static func advance(bar: int, total: int, stage_i: int, n: int) -> Dictionary:
	var b: int = maxi(0, bar) + maxi(0, n)
	var t: int = maxi(0, total) + maxi(0, n)
	var s: int = clampi(stage_i, 0, STAGES.size() - 1)
	var ev := false
	if s + 1 < STAGES.size() and b >= int(STAGES[s + 1]["need"]):
		s += 1
		b = 0
		ev = true
	return {"bar": b, "total": t, "stage": s, "evolved": ev}


## 钻石斧之后攒够 400 ⇒ 该弹「四选一」了(未决点 ⑦)。
## `final_key` 非空 = 已经选过, 本大轮锁定 ⇒ 不再 ready。
static func final_ready(bar: int, stage_i: int, final_key: String) -> bool:
	return final_key == "" and stage_i >= STAGES.size() - 1 and bar >= FINAL_NEED


## 当前该显示成什么。商店的【形态与售价随进化变】读的就是它。
## 选完最终造物 ⇒ 显示最终造物(它不再随档位走)。
static func display(stage_i: int, final_key: String) -> Dictionary:
	for f in FINALS:
		if str((f as Dictionary)["key"]) == final_key:
			return {"key": str(f["key"]), "name": str(f["name"]), "cost": int(f["cost"])}
	var st: Dictionary = stage(stage_i)
	return {"key": str(st["key"]), "name": str(st["name"]), "cost": int(st["cost"])}


## 九档九张图标(木/石/铁/金/钻 + 四个最终造物), 与 `display` 的 key 一一对应。
static func icon_path(stage_i: int, final_key: String) -> String:
	## ★返回的是 `img` 字段的**相对形式**(`equip/xxx.png`) —— EquipIcon.make 自己拼
	##   "res://assets/sprites/" 前缀。写成绝对路径会走进 emoji 兜底分支而不是报错,
	##   表现成"图标变成 📦", 看着像缺图。
	return "equip/axe-%s.png" % str(display(stage_i, final_key)["key"])


## ── 四期: 货架策略 ────────────────────────────────────────────
## 返回本次掷货该怎么对待 096:
##   ""      未激活羁绊 → **什么都不做**, 它本来就是 1 费装备, 走常规 1 费档(需求原话)
##   "off"   已选完最终造物 → 彻底不出货(需求原话「经验封顶后不再出货」)
##   "indep" 已激活羁绊 → 从常规池里**剔除**, 改走独立概率(否则两条路会叠加)
static func shelf_mode(syn_active: bool, final_key: String) -> String:
	if final_key != "":
		return "off"
	return "indep" if syn_active else ""


# ════════════════════════════════════════════════════════════════
#  五期: 被动 3~6 的数值(2026-09-01)
#
#  ★解锁档位与 `passives_at()` 一一对应: 石斧(1)开被动3 / 铁斧(2)开4 /
#    金斧(3)开5 / 钻石斧(4)开6。属性(50血/5攻/3甲/3抗)**每条各给一份、可叠加**,
#    已经由 minion_hp/minion_atk 的 `passives_unlocked` 参数算进去了。
# ════════════════════════════════════════════════════════════════

## ── 被动 3(石斧): 每 9 秒一次强化 on-hit ──
const SMASH_IV := 9.0            # 每过这么久, 下一次普攻获得强化
const SMASH_ATK := 0.5           # 额外物理伤害 = 0.5×ATK
const SMASH_KNOCK_VY := 1.0      # 击飞的竖直倍率(走 _knockback 的既有参数)
const SMASH_KNOCK_PUSH := 0.6    # "短暂击退" ⇒ 推力给得比标准击飞小

## ── 被动 4(铁斧): 每第 2 次普攻竖劈 ──
const CLEAVE_MAXHP_PCT := 0.05   # 额外 5% 目标最大生命【真实伤害】
const CLEAVE_BLEED := 10         # 并施加 10 层流血

## ── 被动 5(金斧): 每第 1 次普攻 180° 横扫 + 效率层 ──
## ★被动4「每第二次竖劈」+ 被动5「每第一次横扫」合起来 = 横扫/竖劈**交替**
##   (方案书出入第 8 条)。所以两条共用一个"第几次普攻"的计数器, 奇数横扫偶数竖劈。
const SWEEP_ARC_DEG := 180.0     # 横扫的扇形角度
const EFF_DUR := 5.0             # 效率层持续 5 秒, 每次叠加**刷新**整条时长
const EFF_ASPD := 0.04           # 一层 +4% 攻击速度
const EFF_MOVE := 0.02           # 一层 +2% 移动速度

## ── 被动 6(钻石斧): 治疗时进入 4 秒蓄力, 完毕猛砸 ──
const CHARGE_TIME := 4.0         # 共蓄力 4 秒
const CHARGE_STEP := 0.5         # 每 0.5 秒
const CHARGE_H_PER_STEP := 100.0 # 梯形的【高】增加 100 码 ⇒ 满蓄 800 码
const CHARGE_DR := 0.70          # 蓄力期间 70% 减伤
const SLAM_ATK := 4.0            # 砸下时每个敌人吃 4×ATK 物理
const SLAM_STUN := 3.0           # 并眩晕 3 秒(外加高高击飞)
## ★梯形的两条底边宽度**需求没给**, 由我自拍(方案书未决点 ⑬):
##   近边取召唤物碰撞直径的两倍(它就站在梯形的窄头), 远边取近边的 3 倍
##   ⇒ 满蓄时是一个 300 宽、800 长、张口 900 的扇形块, 与 180° 横扫的观感连得上。
const TRAPEZOID_NEAR_W := 300.0
const TRAPEZOID_FAR_W := 900.0


## 蓄了 `elapsed` 秒时梯形的【高】。★按 0.5 秒一格【向下取整】——
## 需求写的是"每蓄力 0.5 秒使高增加 100 码", 是阶梯不是连续增长;
## 写成 `elapsed/0.5*100` 的连续版在 0.4 秒时就有 80 码, 那是另一条曲线。
static func charge_height(elapsed: float) -> float:
	var e: float = clampf(elapsed, 0.0, CHARGE_TIME)
	return floorf(e / CHARGE_STEP) * CHARGE_H_PER_STEP


## 点 `p` 在不在以 `origin` 为窄头、朝 `dir` 展开、高 `h` 的等腰梯形里。
##
## ★这是本作**没有过**的形状(现有范围判定只有圆与直线带), 所以写成纯几何函数
##   让门禁直接喂坐标验 —— 不必打一场真战斗去撞(CLAUDE.md §3.5)。
## 判据: 把 p 投到 dir 上得到纵深 t(必须落在 [0,h]), 再看它到中轴的横向距离
##   是否小于该纵深处的半宽(近半宽到远半宽之间线性插值)。
static func in_trapezoid(origin: Vector2, dir: Vector2, h: float, p: Vector2) -> bool:
	if h <= 0.0:
		return false
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		return false
	var rel: Vector2 = p - origin
	var t: float = rel.dot(d)                     # 纵深
	if t < 0.0 or t > h:
		return false
	var lat: float = absf(rel.dot(Vector2(-d.y, d.x)))   # 到中轴的横向距离
	## ★半宽按【满蓄高】插值, 不是按当前高 —— 否则梯形长大的时候会跟着"变胖",
	##   而需求只说高在长、没说宽在长。
	var full_h: float = CHARGE_TIME / CHARGE_STEP * CHARGE_H_PER_STEP
	var k: float = clampf(t / maxf(1.0, full_h), 0.0, 1.0)
	var half_w: float = lerpf(TRAPEZOID_NEAR_W, TRAPEZOID_FAR_W, k) * 0.5
	return lat <= half_w


## 效率层给的攻速 / 移速倍率(纯函数, 门禁直接喂层数验)。
static func eff_aspd_mult(stacks: int) -> float:
	return 1.0 + EFF_ASPD * float(maxi(0, stacks))


static func eff_move_mult(stacks: int) -> float:
	return 1.0 + EFF_MOVE * float(maxi(0, stacks))
