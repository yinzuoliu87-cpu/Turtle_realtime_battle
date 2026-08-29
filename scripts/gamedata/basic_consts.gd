class_name BasicConsts
extends RefCounted
## 小龟(basic)的数值常量表。
##
## ★★为什么单独一个文件(2026-08-22 文案根除)
## 小龟是**唯一没有 `<x>_system.gd` 的龟** —— 它的技能简单, 实现直接写在主场景里
## (`_sk_basic_shield` / `_basic_shield_impact_hit` / `_BASIC_RARITY_BONUS`)。
## 于是它的数值无处安放: 放主场景会顶到架构预算(`tools/arch_budget.py` 冻结在 8958 行),
## 放某个别的龟的 system 里又是张冠李戴。
## ⇒ 按 CLAUDE.md §5 的分工表 ——「纯数据 / 常量表 → `scripts/gamedata/`」—— 落在这里。
## 主场景只把字面量换成引用(净增 0 行), 玩家文案用 `{C:BasicConsts.X}` 直接引用。
##
## ⚠ 本文件**只放常量**, 不放逻辑。要写逻辑就该开 `basic_system.gd` 了。

## ── 被动·不屈: 按【目标稀有度】增伤 ──────────────────────────
## 覆盖普攻/技能/真实伤害/固定伤害, 每次只算一次。
## ★六个稀有度各一个常量而不是一张字典: `{C:}` 占位符读的是**常量**, 读不了字典的某一项,
##   而文案要逐档写出来(C +20%　B +23%　…)。主场景的 `_BASIC_RARITY_BONUS` 引用这六个。
## 无头龟撕咬第二段: 目标最大生命的百分比【魔法】伤害。
## ★2026-08-29 3% → 4.5%: 同时把这一段从"不吃魔抗的定额"改成**真吃魔抗**
##   (`_dot_after_resist`)。实测一场真实对局 387 次挨打的平均魔抗倍率 0.6745
##   ⇒ 0.03 / 0.6745 = 0.0445 ≈ 0.045, **平均强度不变**但从此魔抗能挡它。
##   推导与探针见 `tests/_probe_armor_dist.gd` 与 shell_system.RELEASE_DMG_PCT 头注。
const HEADLESS_BITE_MAXHP := 0.045
## 近战单位的射程被装备拉到这个值以上时, 普攻【改走弹道】(不再瞬发)。
## ★2026-08-29 由来: 手半剑 084 把近战携带者射程改成 450 码却不改 `melee` 标记
##   ⇒ 450 码外挥空气。判据落在"打得这么远就该有飞行物", 与 `melee` 标记解耦 ——
##   不动近战钳制/突进/命中时机那一串老规则, 以后别的装备把近战拉远也自动有弹道。
## ★取 200: 正常近战龟的射程都在 110 以下(turtle_stats ROLE_SPEC 近战最远 ~100),
##   留足余量不误伤; 而 084 的 450 远在其上。
const LONG_MELEE_RANGE := 200.0
const RARITY_AMP_C := 0.20
const RARITY_AMP_B := 0.23
const RARITY_AMP_A := 0.26
const RARITY_AMP_S := 0.29
const RARITY_AMP_SS := 0.32
const RARITY_AMP_SSS := 0.34

## ── 龟盾(已融入被动): 每 N 秒蓄力一次, 强化下一发普攻 ──────────
## 没在主场景 `BASIC_ATK` 表里登记的龟(宝箱/无头/…)走这条默认普攻的系数。
## ★放这里而不是主场景: 纯常量表按 CLAUDE.md §5 归 `scripts/gamedata/`,
##   而且它们的文案里那个「1.0×攻击力」指的正是它, 不该各编各的。
const DEFAULT_BASIC_COEF := 1.0

## 【普攻】真值在主场景普攻表, 那里引用本常量。
const ATTACK_ATK_COEF := 1.0     # 普攻 ×ATK 物理
const SHIELD_CD := 6.0           # 每几秒蓄一次
const SHIELD_ATK_COEF := 1.5     # 额外 ×ATK 物理 (2026-07-29 第四轮: 0.7 → 1.5)
const SHIELD_LOST_PCT := 0.13    # 额外 + 目标【已损生命】× (第四轮: 0.20 → 0.13)
const SHIELD_GAIN_PCT := 0.80    # 自己获得 (上面两段之和) × 的护盾(不限时)
const SHIELD_KNOCK_SEC := 0.55   # 击飞滞空(秒)

## ── 龟派气波(主动) ────────────────────────────────────────
## 【打击】全程定身, 连发若干道气波, 每道随机挑一个存活敌当方向。
## ★定身时长是**推导**: 波数 × 间隔 —— 原来写死 1.65, 改波数就会对不上。
const STRIKE_WAVES := 10          # 发几道
const STRIKE_GAP := 0.15          # 每道间隔(秒)
const STRIKE_COEF := 0.4          # 每道 ×ATK 物理(吃不屈稀有度增伤)
const STRIKE_ROOT_SEC := STRIKE_WAVES * STRIKE_GAP   # 推导: 全程定身时长
const CHI_ATK_COEF := 2.0        # 沿途每敌 ×ATK 物理 (3.5 → 3.0 → 2.0, 第五轮)
const CHI_KNOCK_SEC := 1.5       # 击飞滞空(秒)
const CHI_BUFF_SEC := 3.0        # 施法期自增 buff 的持续(秒)
const CHI_CRIT := 0.25           # 自增暴击率
const CHI_LIFESTEAL := 0.20      # 自增生命偷取
const CHI_ARMOR_PEN_COEF := 0.1  # 自增护甲穿透 = ×ATK
const CHI_DASH_MAX := 300.0      # 发波前智能位移的最远距离(码)
const CHI_DASH_DIRS := 12        # 智能位移采样几个方向(× 3 档距离)
const CHI_DASH_MIN_FOE := 120.0  # 落点距任一敌人近于此就排除(不贴脸·考虑碰撞体积)

## ── 过肩摔(主动) ──────────────────────────────────────────
const SLAM_LAND_BACK := 55.0     # 摔到龟背后多少码
const SLAM_STUN_SEC := 0.5       # 眩晕(秒)
const SLAM_MAIN_ATK := 1.0       # 主目标 ×ATK
const SLAM_MAIN_HP_PER_ATK := 0.002   # 主目标 + ATK × 此值 × 目标最大生命
const SLAM_SPLASH_RADIUS := 350.0     # 落点周围波及半径(码)
const SLAM_SPLASH_ATK := 0.3          # 周围敌人 ×ATK
const SLAM_SPLASH_HP_PER_ATK := 0.0013  # 周围敌人 + ATK × 此值 × 主目标最大生命
