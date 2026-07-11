extends Node3D
const HpBarScene := preload("res://scripts/scenes/hp_bar.gd")   # 回合制版好看血条 (自定义 _draw, 复用)
const Backend := preload("res://scripts/engine/backend.gd")    # 赛季结算上传 ghost (异步PvP池)
## RealtimeBattle3DScene — 2.5D 战斗核心 (Phase 2, 见 docs/design/2.5D战斗架构方案.md §四.2-4)
## 真阵容在 2.5D 里能打: 读 GameState 配队 / demo 兜底 → Sprite3D billboard + blob影 + HP/龟能 overlay.
## 移动·索敌·普攻·分离·龟能·灭队判定 全复用 2D 版 RealtimeBattleScene 的逻辑口径(数值/公式/STATS),
## 只把 pos: Vector2 当 XZ 平面坐标, 另存 height/vy 给击飞真物理(Y 重力抛物). billboard 永远朝镜头.
## ✅ Phase 3: 效果引擎接入 — 28主动技 + 层数DoT(灼烧/中毒/流血) + 召唤体(3D billboard+blob影) + 变身(双头/熔岩/赛博/龟壳)
##    + 登场被动 + on-hit被动 + 周期被动 + 死亡钩子, 全部从 2D 版逐函数照搬(逻辑/数值不变), 只把
##    VFX 触点(_float_text/_skill_ring/_bolt_line/召唤node/投射物) 换成 3D 等价.
## ⚠ 本轮先不做 59 装备运行时 (留 Phase 3b); _eq_* 钩子在 2D 版有, 这里全部不调用(equips 恒空).
## ⚠ 占位美术: 立绘从 avatars/ 按 id, 地面/影/血条/技能圈占位; 数值是 2D 版草案值, 全待 F5 调手感.

# ============================================================================
#  逻辑常量 (1:1 复用 RealtimeBattleScene 口径)
# ============================================================================
const ARENA := Rect2(70, 110, 1596, 728)   # 战场边界 (像素口径). 双路放大版 1.4×(1140×520→1596×728, 用户2026-07-05): 给障碍/绕行留空间, 相机同比拉远. _arena_center/地面/环/clamp 全按 ARENA 自适应.
# #12 出生站位参数化 (编辑器 Inspector 可调, 别写死): 默认=原值→不改行为; 调它即可挪出生点/拉开间距 不动代码
@export var spawn_edge_margin: float = 150.0    # 龟距战场左右边缘 (越大越靠中)
@export var spawn_front_margin: float = 100.0   # 首龟距战场上边
@export var spawn_row_spacing: float = 160.0    # 三龟纵向间距 (越大越散开)
# 技能放招 = 龟能充能 (用户实测沙蝎): 龟能按固定速率充, 每技有龟能花费, 攒够才放。
#   "冷却"不是独立计时器 = 龟能充满该技花费的时间(花费×0.075秒)。冷却 与 龟能充能 是同一回事。
#   花费/换算/is_active 全在单一事实源 SkillEnergy (战斗/图鉴/选龟共用, 防口径分叉)。
const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")
const SKILL_GCD := 0.4                      # 同龟两次放技最小间隔 (防多技同帧连爆)
# AI 状态机节拍 (Botworld式: 移动/攻击互斥 + 施法锁 + 前摇; 用户2026-06-28 #5最高优先级)
# LoL式普攻(官方Attack_speed/Basic_attack wiki, 完整模型):
#  总攻击时间=1/攻速; 前摇windup=总时间×windupPercent(默认~0.3), 随攻速缩放, 前摇内定身承诺;
#  伤害点后"commands may be freely input without penalty"=立即自由可动(orb walk), 无定身后摇锁!
#  剩余时间(总−前摇≈70%,也随攻速)=后摇动画+冷却, 期间能动; 下次普攻等atk_cd=1/攻速.
const ATK_WINDUP_PCT := 0.30                # 前摇占攻击周期比例 (LoL默认windup percent≈30%, 随攻速缩放)
const ATK_WINDUP_MIN := 0.12               # 前摇下限(极快攻速也留可读蓄力)
const ATK_WINDUP_MAX := 0.40               # 前摇上限(极慢攻速不呆太久)
# 后摇: 忠实LoL=伤害点后立即自由(可动/被分离), 无rooted后摇态; 后摇=视觉lunge回收+squash(不锁移动). 故普攻出手后直接回move.
const ATK_LUNGE_PCT := 0.22                # 近战命中踏步(前冲再回)时长=攻击周期比例(随攻速缩放, 同前摇思路)
const ATK_LUNGE_MIN := 0.10
const ATK_LUNGE_MAX := 0.30
const ATK_LUNGE_AMP := 0.30                # 近战踏步幅度(米)
const MELEE_ATK_RANGE_MIN := 100.0         # 近战最小攻击射程(用户2026-07-11: 原70→贴脸重叠·站位=射程×0.85, 100→站位85不挤; SEP_RADIUS 92 是站位上限)
const CAST_WINDUP := 0.34                   # 技能前摇(蓄力, 比普攻久 → 有重量感)
const CAST_RECOVER := 0.24                  # 技能后摇
const _BASIC_RARITY_BONUS := {"C": 0.20, "B": 0.23, "A": 0.26, "S": 0.29, "SS": 0.32, "SSS": 0.34}   # 小龟不屈: 按目标稀有度
const SEP_RADIUS := 92.0                    # 单位软分离半径 (像素口径; 防扎堆, 调大点更散) — 调宽让近战围目标散开成环不叠成一坨(>血条宽66→血条留出间隙)
const HP_MULT := 3.0                       # base↔final比率: 龟/装备hp已写最终值; 仅召唤raw值(×)与装备%回收(maxHp/)用它
const SHIELD_CAP_MULT := 1.5
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类层数 DoT 每秒结算一次
const BUFF_SEC := 5.0                      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const CTRL_SEC := 1.5                      # 眩晕/冻结/嘲讽 默认秒数

# 28 龟战斗属性 (1:1 复用): id → [melee, move_spd(px/s), atk_interval(s), atk_range(px)]
const STATS := {
	"basic": [true, 105.0, 0.85, 70.0], "stone": [true, 70.0, 1.6667, 70.0], "bamboo": [true, 105.0, 0.85, 70.0],
	"angel": [false, 105.0, 0.85, 400.0], "ice": [false, 105.0, 0.85, 400.0], "ninja": [true, 145.0, 0.6, 70.0],
	"two_head": [false, 145.0, 0.85, 400.0], "ghost": [false, 145.0, 0.6, 400.0], "diamond": [true, 70.0, 1.1, 70.0],
	"fortune": [true, 105.0, 0.75, 70.0], "dice": [true, 145.0, 0.6, 70.0], "rainbow": [true, 105.0, 0.7, 70.0],
	"gambler": [false, 145.0, 0.85, 400.0], "hunter": [false, 145.0, 0.7, 400.0], "pirate": [true, 105.0, 0.85, 70.0],
	"candy": [true, 105.0, 0.85, 70.0], "bubble": [false, 70.0, 1.1, 400.0], "line": [false, 145.0, 0.6, 400.0],
	"lightning": [false, 145.0, 0.6, 400.0], "phoenix": [false, 105.0, 0.7, 400.0], "lava": [false, 145.0, 0.7, 400.0],
	"cyber": [false, 105.0, 0.85, 450.0], "crystal": [true, 70.0, 1.1, 70.0], "chest": [true, 105.0, 1.1, 70.0],
	"space": [false, 145.0, 0.85, 400.0], "hiding": [true, 70.0, 1.1, 70.0], "headless": [true, 145.0, 0.85, 70.0],
	"shell": [true, 105.0, 1.1, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 0.85, 70.0]
## 评审期开关: 战斗 = 1受审龟 vs 假人沙包 (看单龟完整循环)。
## ⚠ 它【不只影响评审场】——`_unit_level()` 里 `if _review_demo(): return 1`,
##    所以它为 true 时【真实对局里全体单位也被强制 Lv1, 赛季等级完全不生效】。
##
## ★★2026-07-10 修真bug: 旧实现是 `REVIEW_DEMO_DEFAULT and not OS.has_environment("SHIP")`。
##    `OS.has_environment` 是【运行时】求值 —— 玩家的手机/浏览器里根本没有 SHIP 这个环境变量,
##    所以【导出的 APK / Web 包里 REVIEW_DEMO 恒为 true】: 玩家打的是沙包假人, 赛季等级不生效。
##    `SHIP=1 bash build-web.sh` 只影响【导出那台机器的进程环境】, 对导出后的游戏毫无作用。
##    (我此前把"上线必须 SHIP=1 构建"写进了文档与 memory, 是错的。)
##
## 现在的真值规则 (与主菜单调试场入口 `OS.is_debug_build()` 同一套口径):
##    · release 导出包            → false (真实对局/真实等级)          ← 玩家拿到的
##    · 编辑器 / F5 / debug 导出  → REVIEW_DEMO_DEFAULT (评审期 = true) ← 你审龟用的
##    · SHIP=1   环境变量         → 强制 false (headless 验证上线语义)
##    · REVIEW=1 环境变量         → 强制 true  (在 release 包里也能开评审场)
const REVIEW_DEMO_DEFAULT := true

static func _review_demo() -> bool:
	if OS.has_environment("SHIP"):
		return false
	if OS.has_environment("REVIEW"):
		return true
	return REVIEW_DEMO_DEFAULT and OS.is_debug_build()
const REVIEW_TURTLE := "ninja"             # 受审龟 id (技能特效验收: 换龟只改这里; 账本见 docs/design/技能特效验收账本.md)
const REVIEW_SKILL_IDX := 2   # 评审受审龟放哪个技(skillPool索引): 0=普攻/1-3=候选技/-1=默认轮转
const REVIEW_SHOWCASE := []   # 非空=展示模式: 这些龟一队vs等量假人(一窗连续看多只); 空=单龟评审
const REVIEW_DUMMY := "basic"              # 假人 id (右队沙包)
const REVIEW_DUMMY_HP := 500.0            # 假人固定血量
const REVIEW_DUMMY_COUNT := 3   # 假人数量(单龟评审时); >1=排开
const REVIEW_DUMMY_KILLABLE := false   # true=假人会死(看换目标); false=不死回满沙包(看完整动画)
const REVIEW_DUMMY_ATTACKS := true     # true=假人会还手(看挨打类被动如龟壳储能); 同时受审龟免死看完整循环
const LEFT_DEMO := ["basic", "stone", "lightning"]   # 非评审 demo (_review_demo()=false 时用)

## 每技【专属演示假人布局】: "受审龟id:skill_idx" → [ {dx,dy}, ... ] (相对受审龟: dx=右方X码, dy=深度Y偏移).
##   缺省(无此键)= REVIEW_DUMMY_COUNT 个横排。★验收账本 docs/design/技能特效验收账本.md 每技记一份。
const REVIEW_DEMO_CFG := {
	"basic:2": [ {"dx": 110.0, "dy": 0.0}, {"dx": 430.0, "dy": -240.0, "fixed": true} ],   # 龟派气波: 1贴脸(正前) + 1远处(偏上·不共线·固定不动) → 触发智能冲刺(冲到能同时打俩)再聚气放波
	"basic:3": [ {"dx": 120.0, "dy": 0.0, "fixed": true}, {"dx": 210.0, "dy": -150.0, "fixed": true}, {"dx": 210.0, "dy": 150.0, "fixed": true} ],   # 过肩摔: 1贴脸(grab目标)+2近flank(固定·看落地250码范围伤)
	"stone:2": [ {"dx": 160.0, "dy": -70.0, "fixed": true}, {"dx": 160.0, "dy": 70.0, "fixed": true}, {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 岩石之躯震击: 前方带状3假人(都在±90带宽内·固定)→看横排扫击命中+击退
	"stone:3": [ {"dx": 260.0, "dy": -150.0}, {"dx": 260.0, "dy": 150.0}, {"dx": 380.0, "dy": 0.0} ],   # 嘲讽: 3假人都在500码嘲讽+400码砸地范围内(不固定→被嘲讽后转头打石头, 3.5s砸地击飞)
	"stone:-1": [ {"dx": 120.0, "dy": -70.0}, {"dx": 120.0, "dy": 70.0}, {"dx": 200.0, "dy": 0.0} ],   # 岩石之躯被动审: 3假人围上来持续打石头→石头堆岩层(体型+2%/层·减伤1%/层·上限30)看变大
	"bamboo:0": [ {"dx": 100.0, "dy": 0.0} ],   # 竹叶一叶普攻: 单假人贴脸→看近战挥击 + 竹叶生长每6秒强化下一发(绿生命球飞回+成长)
	"bamboo:1": [ {"dx": 130.0, "dy": -70.0}, {"dx": 130.0, "dy": 70.0} ],   # 自然恢复: 2假人围打竹叶→掉血后放自愈(15%maxHp)看回血+治疗辉光(单龟无友军=无团队护盾)
	"bamboo:2": [ {"dx": 130.0, "dy": 60.0, "fixed": true}, {"dx": 520.0, "dy": -120.0, "fixed": true} ],   # 竹击: 近假人拴住竹叶(近战打它) + 远假人(520码·钩最远)→看伸竹藤从远处拽贴身+眩晕冰寒
	"bamboo:3": [ {"dx": 220.0, "dy": -70.0, "fixed": true}, {"dx": 220.0, "dy": 70.0, "fixed": true}, {"dx": 320.0, "dy": 0.0, "fixed": true} ],   # 竹刺阵: 3假人聚一起(都在300码内)→蓄力预警圈→竹刺齐爆+击飞1.5s
	"angel:0": [ {"dx": 220.0, "dy": -240.0, "fixed": true} ],   # 天使普攻: 远程(射程400)·假人放斜上方(非水平)→验尖尖波弹道随方向转(尖端领飞) + 审判蓝字
	"angel:1": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 天使祝福: 单假人(天使打它)·单龟无友军→祝福自己(金圣环+1.2A护盾+30%攻速+30%龟能充能5秒)
	"angel:2": [ {"dx": 300.0, "dy": 0.0, "fixed": true, "rarity": "S"} ],   # 天使平等: 单S级假人(触发审判光柱·需A+)→看2道圣光斩弧+从天而降审判光柱+吸血
	"angel:3": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 天使飞升: 单假人(天使打它)→反复放飞升(自增buff)看金光圣环+攻速逐次变快(永久叠加)
	"ice:0": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 寒冰普攻冰刺: 远程(射程400)单假人在射程内→看冰弹弹道+命中冰蓝
	"ice:1": [ {"dx": 260.0, "dy": -60.0, "fixed": true}, {"dx": 260.0, "dy": 60.0, "fixed": true}, {"dx": 350.0, "dy": 0.0, "fixed": true} ],   # 寒冰冰霜: 3假人聚一簇(150码冰霜场覆盖)→看冰霜场环+落冰+圈内-25%魔抗+每0.5s跳伤
	"ice:2": [ {"dx": 220.0, "dy": -240.0, "fixed": true} ],   # 寒冰冰封: 假人放斜上方→验冰锥弹道随方向转(尖端朝目标·不再水平) + 命中0.6魔法+冻结1.5s
	"ice:3": [ {"dx": 200.0, "dy": 0.0, "fixed": true} ],   # 寒冰团队护盾(重设计): 单假人(200码·在250爆炸圈内)·单龟=独狼→自己20%maxHp冰盾·盾破/到期爆250码5A魔法
	"ice:-1": [ {"dx": 250.0, "dy": -120.0}, {"dx": 250.0, "dy": 120.0}, {"dx": 380.0, "dy": 0.0} ],   # 寒冰被动极寒: 3假人→看登场群体寒爆+每敌蓝寒环+全场-30%攻速/移速/充能
	"ninja:0": [ {"dx": 130.0, "dy": 0.0} ],   # 忍者斩击普攻: 近战快攻(interval0.6)单假人→看斩击挥/踏步/2层流血/高暴击
	"ninja:1": [ {"dx": 600.0, "dy": 0.0, "fixed": true} ],   # 忍者手里剑(远程2000码): 假人放600码(出冲击500码范围)→忍者站原地朝远处掷旋转飞镖·看真远程弹道
	"ninja:2": [ {"dx": 340.0, "dy": -90.0, "fixed": true}, {"dx": 420.0, "dy": 0.0, "fixed": true}, {"dx": 340.0, "dy": 90.0, "fixed": true} ],   # 忍者炸弹(AOE): 3假人聚一簇→看点燃引信炸弹抛物线飞向敌群质心→落地爆炸帧动画+全体1.1A物理红字+每敌-25%护甲环
}
func _review_dummy_layout() -> Array:   # 当前受审技的假人布局(空=用默认横排)
	if not _review_demo():
		return []
	return REVIEW_DEMO_CFG.get("%s:%d" % [_review_turtle(), _review_skill_idx()], [])
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

# 普攻表 (1:1 复用): id → [scale, hits]
# 基础技能 (28龟 1:1 照原始 skillPool[0] 公式/类型/机制重对, 2026-06-28).
#   字段: phys/magic/true=×ATK 总倍率(物/魔/真); hits=视觉段; def/mr/hp/selfhp/tcurhp=加成项(进主类型);
#   gold=×ATK×金币(财神); critflat=×暴击率flat(骰子); selfheal=×ATK每击自愈(海盗弯刀); rider=burn/atkdn/selfdef/bleed/shrink(附带); mech=ninja/splash(特殊); lightning 走专用函数.
const BASIC_ATK := {
	"basic":    {"phys": 1.0, "hits": 1},
	"stone":    {"phys": 0.7, "def": 1.5, "mr": 0.8, "hits": 1},                    # +护甲魔抗(坦克)
	"bamboo":   {"phys": 0.4, "selfhp": 0.03, "hits": 1},                           # 单段 0.4ATK+3%自身HP(用户2026-06-29)
	"angel":    {"phys": 1.0, "hits": 1},                                          # 远程平A 1.0ATK单段(用户)+审判被动
	"ice":      {"phys": 0.8, "magic": 0.8, "hits": 1, "alt_each": true},           # 单段逐次交替物/魔 0.8ATK(用户2026-06-29)
	"ninja":    {"phys": 1.0, "hits": 1, "rider": "bleed"},                         # 斩击(封板): 近战1A物理+2层流血; 冲击已转被动auto-dash
	"ghost":    {"phys": 0.4, "true": 0.9, "hits": 1},                             # 物+真 (原0.65 错)
	"diamond":  {"phys": 0.7, "def": 0.6, "mr": 0.6, "hits": 1},                    # +护甲魔抗
	"fortune":  {"phys": 1.0, "gold": 0.02, "hits": 1},                            # 1下(用户; 回合制原2下)
	"dice":     {"phys": 0.9, "critflat": 55.0, "hits": 1},                         # 90%物理+5500%暴击率flat·单段近战(对齐回合制 diceAttack critBonusMult=55·无实时原话)
	"rainbow":  {"phys": 0.9, "hits": 1},                                          # 单段0.9物理(用户2026-07-02, 原魔法1.4×2)
	"gambler":  {"phys": 1.0, "hits": 1},                                          # 甩扑克牌(封板L296·用户改): 1.0A物理单段(原3段1.35A=旧值)·多重打击被动复放整发普攻(_gambler_multi_cd)
	"hunter":   {"phys": 1.0, "hits": 1},   # 封板: 普攻1.0A物理(残血追猎+50%攻速在atk_cd处)
	"pirate":   {"phys": 1.0, "hits": 1, "selfheal": 0.2},                          # 弯刀(封板L382·近战): 1.0A物理+自愈0.2A(每击回0.2×ATK生命)·[段数1=单弯刀斩·手感留F5]
	"candy":    {"phys": 1.1, "selfhp": 0.05, "hits": 1, "rider": "atkdn"},         # +自HP+减攻debuff
	"bubble":   {"phys": 1.5, "hits": 3},
	"line":     {"magic": 1.0, "hits": 1},                                          # 素描:1A魔法单段(叠1墨迹走_on_basic_hit·用户设计)
	"lava":     {"magic": 0.6, "hp": 0.04, "hits": 1, "rider": "burn", "burnScale": 0.07},   # 熔岩弹: 0.6魔+4%目标HP+0.125ATK灼烧层 (用户2026-06-30)
	"crystal":  {"phys": 0.6, "hits": 1},                                          # 水晶刺(封板L559):0.6A物理+1.5%目标maxHp魔法+叠1结晶(魔法段与结晶都走_on_basic_hit·原hp bonus折进物理=类型错)
	"space":    {"magic": 0.9, "tcurhp": 0.05, "hits": 1},                          # 星光弹: 单段0.9A魔法+5%目标当前HP (封板2026-07-07)
	"hiding":   {"phys": 1.0, "hits": 1, "rider": "shrink"},                        # 缩壳: 1A物理+每击+1甲+1抗+0.1A盾(越打越硬)
	# shell 走 _basic_attack 特判 _shell_basic (1ATK单段·物/真逐攻交替 + 120px范围溅射50%); 不进 _do_basic
}
const DEFAULT_BASIC := {"phys": 1.0, "hits": 1}

# ============================================================================
#  2.5D 坐标 / 渲染常量
# ============================================================================
const AVATAR_DIR := "res://assets/sprites/avatars/"   # 头像兜底 (全身图缺失才退回)
const SPRITE_DIR := "res://assets/sprites/"           # pets.json img 相对此根
const TARGET_BODY_H := 2.0                 # 立绘目标世界高度 (米) — 龟 ≈ 2.0m (用户2026-06-29: 原2.3大了点)
const WS := 0.024                         # 像素 → 米 比例 (ARENA 1140×520 px → ≈27×12.5 米地面)
const PIXEL_SIZE := 0.012                 # (旧) 头像兜底像素→米; 全身图改按帧高归一到 TARGET_BODY_H

# 动作动画表 (1:1 复用回合制 BattleScene _ACTION_ATTACK/_ACTION_HURT/_ACTION_DEATH).
#   只有 basic/ghost/ninja/treasure_golem 有真动作帧 (其余龟靠 idle + juice 形变).
#   值 = [相对路径, 每秒帧率] (帧尺寸 = 图高=方帧; hframes = 宽/帧高). 播一次后回 idle.
const ACTION_ATTACK := {
	"basic":  ["pets/animations/basic/attack.png", 14.0],
	"ghost":  ["pets/animations/ghost/attack.png", 14.0],
	"ninja":  ["pets/animations/ninja/throw.png", 16.0],
}
const ACTION_HURT := {
	"basic":  ["pets/animations/basic/hurt.png", 16.0],
	"ghost":  ["pets/animations/ghost/hurt.png", 16.0],
	"ninja":  ["pets/animations/ninja/hurt.png", 16.0],
}
const ACTION_DEATH := {
	"basic":  ["pets/animations/basic/death.png", 12.0],
	"ghost":  ["pets/animations/ghost/death.png", 12.0],
	"ninja":  ["pets/animations/ninja/death.png", 11.0],
}
# GROUND_LIFT: 立绘落地基线 — 现在配合"底部 alpha 软渐隐 shader"故意略低(让软淡的脚部轻插进地面盖住交界),
#   不再靠抬高去躲硬切. 见 §GROUNDING.
const GROUND_LIFT := 0.06                  # 略沉 → 软淡脚部融进地面 (原 0.35 是为躲硬切的权宜, 已被 shader 根治)
const SHADOW_BASE := Vector3(2.05, 1.0, 1.0)
const SHADOW_BASE_A := 0.62
const GRAVITY := -22.0                     # 击飞重力 (m/s^2)
const KNOCK_VY := 6.0                      # 击飞竖直初速 (m/s) — 真抛物抬起再砸地
const KNOCK_PUSH := 5.5                    # 击飞横向初速 (米/s, 远离施法者)
const LAVA_LEAP_H := 5.5                    # 火山砸地: 跃升高度 (用户: 更高)
const LAVA_LEAP_UP_T := 0.5                 # 跃升+飞向落点 耗时
const LAVA_CHARGE_T := 1.0                  # 滞空蓄力时长 (悬停高处蓄力,不直接砸; 预警可见)
const LAVA_SLAM_T := 0.16                   # 砸地俯冲耗时
const LAVA_SLAM_RADIUS := 400.0             # 砸地冲击半径(px) (用户: ×2)
const LAVA_SLAM_KNOCK_VY := 9.5             # 砸地击飞竖直初速(~0.86s滞空+更高, 加里奥式夸张击飞)

# ============================================================================
#  §GROUNDING + 氛围 — 2.5D 视觉代码级 polish 参数 (全 F5 可调, 纯程序无外部素材)
#  设计目标: ① billboard 不再"纸板硬切"地面 → 立绘底部 UV alpha 软渐隐 shader 融进地;
#            ② 深海景深 (远暗/远蓝) + 程序焦散 + 边界暗角, 给纵深与竞技场围合感;
#            ③ 受光/雾/色调统一冷蓝绿深海调. 风格无关 (对任何最终美术都有益).
# ----------------------------------------------------------------------------
# ① 立绘底部软渐隐 (sprite shader): 图底部这一段 UV 高度内 alpha 线性衰减到 0 → 脚融进地面.
const GROUND_FADE_FRAC := 0.16            # 从底起算渐隐区占图高比例 (越大融得越多)
const GROUND_FADE_FLOOR := 0.04           # 接地处残留 alpha 下限 (0=完全透明, 略>0 防"悬空感")
# ② 接触软影 — 紧贴脚下的深核影 (盖住立绘/地面交界, 加强"踩在地上"判定)
const CONTACT_BASE := Vector3(1.15, 1.0, 1.0)   # 接触核影基准缩放 (比外圈 blob 小且更实)
const CONTACT_BASE_A := 0.5
# ③ 深海地面 (ground shader): 中心亮→边缘暗蓝的景深渐变 + 焦散 + 边界环
const GROUND_NEAR := Color(0.42, 0.62, 0.55)    # 场地中心地色 (亮暖沙青; 卡通像素鲜活风, 大猫贤者方向)
const GROUND_FAR := Color(0.13, 0.42, 0.48)   # 远/边缘地色 (亮青水; 远处是明亮浅海不是黑洞)
const GROUND_VIGNETTE := 0.62             # 边界暗角强度 (0..1; 越大边缘越快沉黑)
const CAUSTIC_STRENGTH := 0.10            # 程序焦散光纹强度 (深海水面投影感; 0=关)
const CAUSTIC_SPEED := 0.35               # 焦散流动速度
# ④ 竞技场边界软环 (地面上一圈柔光 → 给围合感, 替代硬地平线)
const ARENA_RING_COLOR := Color(0.35, 0.62, 0.78)
const ARENA_RING_A := 0.16
# ⑤ 屏幕暗角 (vignette overlay, CanvasLayer 上一张 radial 渐变铺满 → 四角压暗聚焦中心)
const VIGNETTE_A := 0.5

# ============================================================================
#  Phase 4: 商业级打击感 juice 参数 (全 F5 可调) — 见本文件 §JUICE
#  设计: 所有单位视觉态(squash/stretch scale · 受击闪白 modulate · idle bob)统一由
#  _update_world_transforms() 每帧从 per-unit juice 字段重建 → 从 base 精确复原, 不用重叠
#  tween, 杜绝累积漂移/视觉残留 (回归高发区铁律: 共享视觉态别叠 tween, restore 到 base).
# ============================================================================
# ① squash & stretch (billboard scale; base=(1,1,1), 各相位叠乘后归一)
const JUICE_STRETCH_UP := Vector2(0.78, 1.32)     # 击飞起跳: x 收 y 拉 (拉长)
const JUICE_SQUASH_LAND := Vector2(1.30, 0.70)    # 落地: x 张 y 压 (压扁)
const JUICE_LAND_SEC := 0.20                       # 落地压扁回弹时长
const JUICE_HIT_SQUASH := Vector2(1.14, 0.86)     # 受击瞬间轻压扁
const JUICE_HIT_SQUASH_SEC := 0.16                 # 受击压扁回弹时长
const JUICE_WINDUP_SCALE := 0.88                   # 出招预备: 整体微缩 (anticipation)
const JUICE_WINDUP_SEC := 0.10                     # 预备时长
const JUICE_SWING_SCALE := 1.16                    # 出招挥出: 整体微伸 (follow-through)
const JUICE_SWING_SEC := 0.14                      # 挥出回弹时长
# ② 受击闪白 hit-flash (Sprite3D modulate 瞬白 → 淡回)
const JUICE_FLASH_COLOR := Color(2.4, 2.4, 2.4)    # 过曝白 (>1 提亮; shaded=false 下生效)
const JUICE_FLASH_SEC := 0.11                      # 闪白淡回时长
# ③ 顿帧 hit-stop (极短跳过 _tick 推进, 不碰 Engine.time_scale — 用计时恢复)
const JUICE_HITSTOP_HEAVY := 0.055                 # 大招/暴击命中卡顿
const JUICE_HITSTOP_KNOCK := 0.060                 # 击飞卡顿
const JUICE_HITSTOP_LIGHT := 0.0                   # 轻击不卡 (留旋钮; >0 才触发)
const JUICE_HITSTOP_DMG_GATE := 60.0               # 单段伤害 ≥ 此值才算"重击"触发顿帧/闪白增强
# ④ 震屏 screen shake (Camera3D 衰减随机偏移; 强度分级)
const JUICE_SHAKE_DECAY := 9.0                     # 衰减速率 (越大越快归位)
const JUICE_SHAKE_FREQ := 32.0                     # 抖动频率 (Hz 近似)
const JUICE_SHAKE_LIGHT := 0.0                     # 普通命中 = 不抖
const JUICE_SHAKE_HEAVY := 0.10                    # 暴击/技能重击
const JUICE_SHAKE_BIG := 0.22                      # 大招/击飞 (米, 镜头偏移幅度)
const JUICE_SHAKE_MAX := 0.30                      # 幅度上限 (多事件叠加封顶)
# ⑤ idle 呼吸 bob (待机立绘极轻上下浮; 移动/击飞不 bob)
const JUICE_BOB_AMP := 0.035                       # 浮动幅度 (米)
const JUICE_BOB_SPEED := 2.2                       # 浮动角速度
# ⑥ 冲击粒子 (命中点 GPUParticles3D 火花, 一次性自销)
const JUICE_PARTICLE_MIN_DMG := 60.0               # 仅重击/暴击/大招命中迸火花 (省开销)

# 世界中心: ARENA 像素中心映射到原点 → 单位世界坐标 = (pos - center) * WS
var _arena_center := ARENA.position + ARENA.size * 0.5
# 地图障碍物 (布局B: 中央大礁+两侧错位墙) — footprint 椭圆 {c,rx,ry} 给 navmesh 挖洞+放置避让; 只挡移动
var _obstacles: Array = []
var _base_domes: Dictionary = {}   # {side_lr: Sprite3D} 基地穹顶围栏(加性发光罩蛋), 团灭掉栏时淡出
# navmesh 2D 避障 (NavigationServer2D, ARENA像素空间同坐标; 障碍挖洞→单位沿路点绕行; 兜底无路径直奔)
var _nav_map: RID
var _nav_region: RID
var _nav_ready := false

# ============================================================================
#  运行时状态
# ============================================================================
var _units: Array = []
var _data_by_id: Dictionary = {}
var _skill_meta: Dictionary = {}   # 技能 type → skillPool 条目 {atkScale,hits,pierce,name,icon} (选3 多技能 数据驱动放招)
var _over := false
# 双路流程态 (P4/P5): fight=混战 / eggwindow=团灭后破蛋窗口 / done=整场结束
var _dl_state := ""
var _dl_window_until := 0.0
var _dl_wiped_side := ""    # 被团灭方(其蛋暴露): "left"/"right"
var _dl_hud: Label = null   # 双路 HUD: 当前路 + 双方蛋血
var _dl_go_btn: Button = null      # 场内放置阶段「开打」钮
var _dl_place_hint: Label = null   # 放置阶段提示(拖我方单位到位→开打)
var _t := 0.0
var _settled := false                       # 结果只喂赛季一次的守卫
var _had_season := false                     # 本局有赛季态(玩家配了season_leaders); demo=false→不喂只显横幅
var _last_reward := 0                         # 本局给的深海币 (结算显示)
var _last_was_exhibition := false             # 进场已0命=表演赛(无stake)

var _cam: Camera3D
var _ui_layer: CanvasLayer                # 血条/龟能 overlay + 标题 + 结算 (贴在 3D 之上)
var _world: Node3D                        # 3D 内容挂载点 (SubViewport 内)
var _sub: SubViewport
var _projectiles: Array = []              # 飞行中的 3D 投射物 {node, from, to, tgt, dmg, magic, src, t, dur}
var _lava_zones: Array = []               # 持续地面区域 (熔岩龟·岩浆池等) {center, radius, until, next_tick, src, disc}

# --- 暂停 + 战斗日志 (R2b, 用户 2026-07-11) ---
var _pause_panel: Control = null          # 暂停浮层(继续/重开/返回菜单), 默认隐; process_mode ALWAYS 保证暂停中可交互
var _pause_btn: Button = null
var _battle_log: Array = []               # 战斗日志 bbcode 行, 封顶 _LOG_CAP(参 soak 教训防无限增长)
var _log_panel: Control = null            # 日志浮层(可滚动), 默认隐
var _log_rt: RichTextLabel = null         # 日志文本(面板开着才实时追加)
const _LOG_CAP := 200

# --- 战中伤害统计面板 (R2c, 照回合制 DmgStatsPanel 样式: 4Tab×双列×分段条) ---
var _dmg_stats_panel: Control = null      # 战中统计浮层(📊 切), 默认隐
var _dmg_stats_cols: Array = []           # [左队 rows VBox, 右队 rows VBox]
var _dmg_stats_tab: String = "dealt"      # 当前 Tab: dealt/taken/heal/shield
var _dmg_tab_btns: Array = []             # [{btn, key}] 供 active 高亮
# 分段条配色 (1:1 回合制 _ds_parts, alpha 同): 物理红 / 法术蓝 / 真实+DoT 白 / 治疗绿 / 护盾青
const _DS_COL_PHY := Color(1, 0.267, 0.267, 0.6)
const _DS_COL_MAG := Color(0.302, 0.671, 0.969, 0.6)
const _DS_COL_TRU := Color(1, 1, 1, 0.6)
const _DS_COL_HEAL := Color(0.024, 0.839, 0.627, 0.65)
const _DS_COL_SHIELD := Color(0.345, 0.827, 1, 0.6)
const _DS_TABS := [["dealt", "⚔ 造成"], ["taken", "🛡 承受"], ["heal", "💚 治疗"], ["shield", "🔵 护盾"]]

# --- 局内信息 UI (左右队头像框 + 点单位看详情面板; 纯 UI 不动玩法) ---
var _team_panel_left: VBoxContainer = null    # 屏幕左侧头像框栏 (左队主龟)
var _team_panel_right: VBoxContainer = null   # 屏幕右侧头像框栏 (右队主龟)
const PANEL_COUNT := {   # 头像下装备格右下角层数徽章: id → eq_state层数/计数字段 (刷新.get兜底0)
	"p2eq_034": "bear_layers",      # 大熊层
	"p2eq_013": "harden_stacks", "p2eq_014": "harden_stacks",   # 硬化层(0-20)
	"p2eq_024": "dragon_stacks",   # 吐息层(0-3)
	"p2eq_035": "gears",           # 齿轮层
	"p2eq_052": "revolver_bullets", "p2eq_027": "baton_charges", "p2eq_039": "bamboo_charges",   # 子弹/电击/生长充能
	"p2eq_019": "anemone_layers",  # 海葵层
	"p2eq_020": "exercise",       # 哑铃锻炼层(局内, 每场重置)
	"p2eq_043": "wave",            # 巨浪层(0-3)
	"p2eq_017": "anchor_charges",  # 沉锚就绪充能数(另有anchor_accum攒治疗条)
	"p2eq_036": "egg_levels",      # 温泉蛋临时等级(0-3; 另有incub充能条)
}
const PANEL_CHARGE := {   # 局内头像下装备格的充能进度条: id → [充能字段, 满值]
	"p2eq_009": ["blade_energy", 100.0], "p2eq_026": ["thunder", 100.0],
	"p2eq_023": ["fire_mana", 8.0], "p2eq_017": ["anchor_accum", 100.0], "p2eq_036": ["incub", 100.0],
}
var _selected_unit = null                     # 当前选中(点击)的单位 Dictionary, 高亮其框
var _info_panel: PanelContainer = null        # 详情面板 (居中, 显等级/属性/被动/技能/装备); 重开覆盖

# --- 🛠 调试场 (DEBUG ARENA): 自由摆位编辑模式 (从主菜单进; 默认关, 不影响正常战斗) ---
#   DEBUG_EDIT=true 时 _spawn_teams 跳过自动出生(空场), 进编辑模式: 点空地摆兵/拖拽挪位/右键删,
#   假人可设血量+不死开关. ▶开始 起战斗(模拟跑), ⏸编辑 回编辑(按摆位重新生成), 清空 全删.
static var DEBUG_EDIT := false            # ← MainMenu 设 true 后 change_scene 进入; 离场重置 false
var _edit_mode := false                   # 当前是否在编辑(暂停模拟)态
var _edit_paused_setup: Array = []        # ⏸编辑 重生用的摆位快照 [{id,side,pos,hp,killable}]
var _edit_pick_id := "basic"              # 当前选中要摆的龟 id (◀▶ 循环 STATS keys)
var _edit_pick_side := "left"             # 摆放阵营 left(友军) / right(假人)
var _edit_dummy_hp := 500.0               # 右队假人血量 (−/+ 步进 100)
var _edit_dummy_killable := false         # 右队假人是否会死 (false=不死回满沙包)
var _edit_drag_unit = null                # 正在拖拽的单位 (Dictionary 或 null)
var _edit_drag_moved := false             # 本次按下是否真的拖动过 (区分点击放置 vs 拖拽挪位)
var _edit_palette: Control = null         # 编辑面板根 (Control 子控件 mouse_filter=STOP 吃掉自身点击)
var _edit_lbl_pick: Label = null
var _edit_lbl_hp: Label = null
var _edit_lbl_status: Label = null
var _edit_btn_start: Button = null
var _edit_btn_edit: Button = null

# --- Phase 4 juice 全局态 ---
var _hitstop := 0.0                       # 剩余顿帧秒 (>0 时 _process 跳过逻辑推进, 每帧自减 → 精确恢复)
var _follow_vfx: Array = []               # 跟随单位的特效sprite [{spr,unit,h}] — 每帧贴 _world_pos(unit.pos, unit.height+h); sprite被free则自动剔除
var _pending_shots: Array = []            # 依次射出的子弹队列 [{delay, fn:Callable, src}] — 每帧减delay, 到点call(错峰射击: 手铳/加特林/狙击链); src=归属(时停只推进active携带者)
# ═══ 沙漏059 JoJo时停 ═══ 冻结全局_t + 只tick active携带者; 其他单位/弹道/依次射击/tween/粒子 全定格
var _ts_active: Array = []                # 当前能自由行动的active携带者(空=无时停; 可多个=全场最高星沙漏者敌我并存)
var _ts_remaining := 0.0                  # 时停剩余真实秒
var _ts_charging := false                 # 蓄力中(1s, 世界仍正常)
var _ts_charge_t := 0.0
var _ts_charge_casters: Array = []
var _ts_fired := false                    # 一场一次
var _ts_maxstar := 0                      # 生效沙漏星级(定时长4/10/30)
var _sim_tweens: Array = []               # VFX tween注册表(时停暂停非active用; 见 _reg_tween)
var _ts_frozen_tweens: Array = []         # 时停期间被暂停的tween(结束resume)
var _ts_frozen_particles: Array = []      # 时停期间被暂停的GPUParticles3D(speed_scale归零, 结束还原)
var _ts_overlay: CanvasLayer = null       # 时停灰世界叠加层(压暗褪色从携带者扩散; layer5=在UI下→只灰3D世界, 数字/血条保彩)
var _ts_rect: ColorRect = null
var _ts_flash_overlay: CanvasLayer = null # 反色闪叠加层(layer60=在UI上→含全屏UI一起反色)
var _ts_flash_rect: ColorRect = null
var _ts_clock: TextureRect = null         # 时停停摆钟(叠加层顶, 不被褪色)
var _ts_glow_sprs: Array = []             # 携带者"时之主"金辉光sprite(结束移除)
var _shake_amp := 0.0                     # 当前震屏幅度 (米); 每帧指数衰减归 0
var _shake_t := 0.0                       # 震屏相位 (驱动伪随机偏移)
var _cam_base := Vector3.ZERO             # 镜头基准位 (shake 围绕它偏移, 衰减后精确归位)
var _juice_rng := RandomNumberGenerator.new()   # 震屏/粒子专用 rng

# --- §GROUNDING: 立绘底部软渐隐 shader (一份 Shader 共享, 每龟一份 ShaderMaterial 因 texture 不同) ---
var _ground_fade_shader: Shader = null

# ============================================================================
#  §AUDIO — 战斗音效接入 (autoload Audio.gd; SFX/BGM 白捡, 见任务 §1)
#  防刷屏: 高频命中音 (普攻多段/AOE 全体) 极易塞爆混音器 → 同名 SFX 设最小间隔节流,
#  到时才放 (pitch/volume 抖动由 Audio.play_sfx 自带, 听感仍有差). 治疗/护盾/暴击同理。
# ============================================================================
const SFX_HIT_MIN_GAP := 0.045            # 命中音最小间隔 (s) — <45ms 内的连段只响一次, 防多段平A/AOE刷屏
const SFX_AUX_MIN_GAP := 0.06             # 治疗/护盾音最小间隔
var _last_hit_sfx_t := -1.0               # 上次命中音时刻 (节流基准)
var _last_crit_sfx_t := -1.0
var _last_heal_sfx_t := -1.0
var _last_shieldgain_sfx_t := -1.0
var _last_shieldbreak_sfx_t := -1.0
var _last_atk_crit := false               # _atk_dmg 最近一次是否暴击 (供 _apply_damage_from 选暴击音)
var _last_dmg_type := "physical"          # _resolve_dmg 最近一次伤害类型 (physical/magic; 飘字按类型统一取色)
const _VC := preload("res://scripts/systems/visual_constants.gd")   # 飘字配色单一事实源 (1:1 回合制 VisualConstants)

# ============================================================================
#  §SKILLVFX — 技能特效真贴图框架 (替程序圈; 见任务 §2)
#  assets/sprites/skills/<turtle>-<skill>.png = 逐技能特效图 (实测 133 张全是近方形单帧,
#  非 spritesheet) → 框架 = 在 cast/命中点放一个 3D billboard, 一次性"放大→保持→淡出"动画后自销,
#  无需逐帧步进. 有匹配贴图的技能用真 VFX; 没有的保留现有 _skill_ring/飘字 (不强行换).
#  映射 = pets.json skillPool[].icon 的「候选1」(各龟 _cast_active 实际放的那招), 逐龟人工核对语义.
# ============================================================================
const SKILL_VFX_DIR := "res://assets/sprites/skills/"
const SKILL_VFX_WORLD_H := 2.2            # VFX billboard 目标世界高度 (米) — 单帧图按此归一, 不论原图多大
const SKILL_VFX_GROW_SEC := 0.10          # 放大入场时长
const SKILL_VFX_HOLD_SEC := 0.10          # 满尺寸保持时长
const SKILL_VFX_FADE_SEC := 0.26          # 淡出时长
const SKILL_VFX_START_SCALE := 0.45       # 入场起始相对尺寸 (放大到 1.0)
# 龟 id → 该龟主动技(候选1) 对应贴图名. 来源: pets.json skillPool[0..] icon, 按 _sk_* 语义对到具体那张.
#   注: 程序圈/飘字保留的龟不在此表 (或留空) → _play_skill_vfx 找不到就静默回退.
const SKILL_VFX_MAP := {
	"basic":     "basic-shield",          # 龟盾
	"stone":     "stone-rockarmor",       # 岩石护甲
	"bamboo":    "bamboo-heal",           # 自然恢复
	"angel":     "angel-bless",           # 祝福
	"ice":       "ice-frost",             # 冰霜
	"ninja":     "ninja-impact",          # 冲击
	"ghost":     "ghost-storm",           # 灵魂风暴
	"diamond":   "diamond-fortify",       # 坚不可摧 (强化/护盾系)
	"dice":      "dice-allin",            # 孤注一掷
	"rainbow":   "rainbow-prismshield",   # 棱镜护盾
	"gambler":   "gambler-wildcard",      # 万能牌
	"hunter":    "hunter-stealth",        # 隐蔽
	"pirate":    "pirate-cannon",         # 火炮齐射
	"bubble":    "bubble-1",              # 泡泡盾 (bubble-1=泡泡盾贴图)
	"line":      "line-1",                # 连笔 (候选1)
	"lightning": "lightning-0",           # 涌动 (候选1)
	"phoenix":   "phoenix-0",             # 熔岩盾 (候选1)
	"headless":  "headless-0",            # 恐吓 (候选1)
	"fortune":   "fortune-dice",          # 骰子+金币
	"crystal":   "crystal-0",             # 水晶壁垒 (候选1)
	"chest":     "chest-0",               # 宝箱砸击 普攻图标
	"space":     "space-0",               # 星光弹 普攻图标
	"two_head":  "twohead-magicwave",     # 双头 (候选1)
	"lava":      "lava-0",                # 熔岩 (候选1)
	"cyber":     "cyber-0",               # 能量大炮 (候选1)
	"candy":     "candy-hammer",          # 焦糖铠/锤 (候选1)
	"hiding":    "hiding-0",              # 防御 (候选1)
	"shell":     "shell-0",               # 吸收 (候选1)
}
var _skill_vfx_cache: Dictionary = {}     # 贴图名 → Texture2D (避免重复 load)

# ★黑屏排查: 是否移动端(Android/iOS/Web-mobile) → 走不读屏幕纹理的安全路径
static func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

## ★C1 黑屏排查: 安卓切后台/锁屏/来电 → GL context 丢失, 回来可能黑屏。
##   全项目原本【无任何生命周期处理】。这里在【恢复/重新获得焦点】时强制 SubViewport 重绘一帧, 把画面拉回来。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _sub != null and is_instance_valid(_sub):
			# 逼一次强制重绘(UPDATE_ONCE→回 ALWAYS), 并让整个画布重画
			_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
			await get_tree().process_frame
			if is_instance_valid(_sub):
				_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	_load_pets()
	_build_viewport()
	_build_camera()
	_build_environment()
	_build_ground()
	_build_ui_layer()
	_spawn_teams()
	# §AUDIO: 战斗 BGM (淡入, autoload Audio 单例处理循环/音量)
	var _audio := get_node_or_null("/root/Audio")
	if _audio != null:
		_audio.play_bgm("battle")
	# DEV 自截图 (SELFSHOT=<秒>): 等若干帧让战斗跑起来再从主视口存盘
	if OS.has_environment("VFXPREVIEW"):
		_vfx_preview_start()
	if OS.has_environment("SELFSHOT"):
		_self_screenshot()

func _load_pets() -> void:
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	if f == null:
		push_warning("RealtimeBattle3D: pets.json 打不开")
		return
	var arr = JSON.parse_string(f.get_as_text())
	if arr is Array:
		for p in arr:
			if p is Dictionary and p.has("id"):
				_data_by_id[str(p["id"])] = p
				for sk in p.get("skillPool", []):
					if sk is Dictionary and sk.has("type") and not _skill_meta.has(str(sk["type"])):
						_skill_meta[str(sk["type"])] = sk

# ----------------------------------------------------------------------------
#  SubViewport 合成: 3D 渲进它 → SubViewportContainer 贴满屏; 2D UI 叠上面.
#  (GL Compatibility 下主窗口截图丢直接渲染的 3D → SubViewport 截图可靠; unproject 1:1 可用)
# ----------------------------------------------------------------------------
func _build_viewport() -> void:
	var vp_size := Vector2i(1280, 720)
	if get_viewport() != null:
		var s := get_viewport().get_visible_rect().size
		if s.x > 1 and s.y > 1:
			vp_size = Vector2i(s)
	var container := SubViewportContainer.new()
	container.name = "ViewportContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "WorldLayer"
	bg_layer.layer = 0
	add_child(bg_layer)
	bg_layer.add_child(container)
	_sub = SubViewport.new()
	_sub.name = "World3D"
	_sub.size = vp_size
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.handle_input_locally = false
	# ★A4 黑屏排查: 移动端 SubViewport + MSAA 在部分安卓 GPU 上有问题 → 移动端默认关 MSAA。桌面保留 2X。
	_sub.msaa_3d = Viewport.MSAA_DISABLED if _is_mobile() else Viewport.MSAA_2X
	# 低画质模式(设置里的开关·持久化): 关抗锯齿 + 3D 渲染分辨率 ×0.75 (UI 层不受影响, 仍是原生分辨率)
	if GameState != null and GameState.perf_lite:
		_sub.msaa_3d = Viewport.MSAA_DISABLED
		_sub.scaling_3d_scale = 0.75
	container.add_child(_sub)
	_world = Node3D.new()
	_world.name = "World"
	_sub.add_child(_world)

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0
	# 场地上方偏后俯视下来 (3/4). 抬高+拉远以容纳 ~27×12.5 米全场.
	_cam.position = Vector3(0.0, 18.9, 25.5)   # 放大1.4×后同比拉远(0,13.5,18.2→×1.4), 角度不变框住更大场地
	_world.add_child(_cam)
	_cam.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
	_cam_base = _cam.position               # Phase4: 震屏围绕此基准偏移, 衰减后精确归位
	_juice_rng.randomize()

func _build_environment() -> void:
	# 主光 (顶光偏前侧): 暖白, 给立绘/地面立体受光. shaded=false 立绘不吃光, 但地面/影/召唤体吃 → 仍出体积感.
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	light.light_energy = 1.15
	light.light_color = Color(1.0, 0.96, 0.86)
	_world.add_child(light)
	# 补光 (深海冷蓝, 从对侧低角打来): 给阴影面注入海水冷色, 避免死黑, 加层次.
	var fill := DirectionalLight3D.new()
	fill.name = "FillCold"
	fill.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.42, 0.66, 0.85)
	_world.add_child(fill)

	var env := Environment.new()
	# 背景: 由亮到暗的深海立式渐变 (天空 SkyMaterial 程序生成, 无外部图) → 远处不再是单色硬墙.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.26, 0.36)      # 顶部亮蓝绿 (阳光浅海, 卡通鲜活)
	sky_mat.sky_horizon_color = Color(0.14, 0.42, 0.48)  # 水平线亮青 (背景是明亮海水不是黑幕)
	sky_mat.ground_bottom_color = Color(0.1, 0.32, 0.4)
	sky_mat.ground_horizon_color = Color(0.14, 0.42, 0.48)
	sky_mat.sky_energy_multiplier = 0.7
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 环境光: 取自天空 + 冷蓝, 让立绘背景与角色统一在深海调里.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.40, 0.58, 0.70)
	env.ambient_light_energy = 0.85
	# 深海雾: 远处沉入蓝黑给纵深 (Compatibility 下 fog 为 per-pixel 简化雾, 仍能拉出远近层次).
	#   雾色压得很暗 (近背景色), 能量低 → 远处沉黑而非提亮成灰 (避免远地/边缘被雾刷亮成灰带).
	env.fog_enabled = true
	env.fog_light_color = Color(0.018, 0.055, 0.085)
	env.fog_light_energy = 0.4
	env.fog_sun_scatter = 0.0
	env.fog_density = 0.022
	# 色调 + 微调: filmic tonemap 给"正经游戏"质感, 略提对比/降饱和到冷调.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.96
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var plane := PlaneMesh.new()
	# 地面铺很大 (远超竞技场+视野) → 填满下半屏, 远处自然沉黑融进背景, 没有硬地平线边/亮角.
	var gw: float = ARENA.size.x * WS * 2.4 + 200.0   # 地面大幅外扩→海床往远处continue填满画面, 不再硬切黑(用户: 四周漆黑像浮虚空)
	var gh: float = ARENA.size.y * WS * 2.4 + 200.0
	plane.size = Vector2(gw, gh)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	mi.mesh = plane
	# 半竞技场尺寸 (米) — shader 据此算"中心→边缘"景深暗角 + 竞技场软环.
	var half_arena := Vector2(ARENA.size.x * WS * 0.5, ARENA.size.y * WS * 0.5)
	mi.material_override = _make_ground_material(half_arena)
	_world.add_child(mi)
	# 竞技场边界软环 (地面上躺平一圈柔光) — 给围合感, 弱化"空旷无边"
	_build_arena_ring(half_arena)

# 深海地面 ShaderMaterial (纯程序, 无外部图):
#  · 景深渐变: 世界 XZ 离场地中心越远 → 由 GROUND_NEAR 暗蓝过渡到 GROUND_FAR (远处变暗变蓝).
#  · 程序焦散: 两层流动 sin 噪声叠加 → 深海水面投影光纹 (随 TIME 漂动).
#  · 受光: 吃 DirectionalLight (法线朝上) → 主光暖/补光冷, 出立体微差.
func _make_ground_material(half_arena: Vector2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert;
uniform vec3 near_col : source_color;
uniform vec3 far_col : source_color;
uniform sampler2D seabed_tex : source_color, filter_linear, repeat_disable;  // 深海礁盘海床贴图(整块拉伸: 亮心贴合竞技场, 边缘礁石融进暗场)
uniform float seabed_amt = 0.85; // 海床贴图占比 (剩余为程序近色底)
uniform vec2 half_arena;          // 竞技场半尺寸 (米)
uniform float vignette = 0.62;    // 边界暗角强度
uniform float caustic_strength = 0.10;
uniform float caustic_speed = 0.35;
uniform float roughness_v = 0.92;

varying vec3 world_pos;           // 顶点世界坐标 (给 fragment 算景深/焦散)

float caustic(vec2 p, float t) {
	// 两层错相流动光纹 (深海焦散近似)
	float a = sin(p.x * 1.7 + t) + sin(p.y * 1.9 - t * 0.8);
	float b = sin((p.x + p.y) * 1.3 + t * 1.3) + sin((p.x - p.y) * 1.1 - t);
	float v = (a + b) * 0.25 + 0.5;            // ~0..1
	v = pow(clamp(v, 0.0, 1.0), 3.0);          // 收窄成亮纹
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = world_pos.xz;
	// 离场地中心的归一化距离 (椭圆: 按竞技场宽高各自归一)
	vec2 n = wp / max(half_arena, vec2(0.001));
	float d = length(n);                        // 0=中心, 1=竞技场边
	float depth_t = smoothstep(0.35, 1.85, d);  // 场内保持亮(能看清海床), 出场才渐沉暗
	// 海床贴图整块拉伸(竞技场归一坐标 n∈[-1,1] → uv[0,1]); 边缘 clamp, 场外靠 sink 沉黑
	vec2 uv = clamp(n * 0.5 + 0.5, 0.0, 1.0);
	vec3 seabed = texture(seabed_tex, uv).rgb * 1.05;   // 亮沙珊瑚地板(本身已亮, 不再×1.75爆)
	vec3 near_base = mix(near_col, seabed, seabed_amt);
	vec3 base = mix(near_base, far_col, depth_t);
	// 焦散 (仅场内明显, 远处随景深淡出) — 加强水面光纹
	float c = caustic(wp * 0.5, TIME * caustic_speed);
	base += c * caustic_strength * (1.0 - smoothstep(0.4, 1.3, d));
	// 边界暗角: 越靠边/越远 → 压暗 (柔和无硬线)
	float vig = 1.0 - vignette * smoothstep(0.62, 1.4, d);
	// 远场强沉黑: 竞技场外 (d>1) 二次压暗到近黑, 防远地/边角被光/雾刷亮成灰带
	float sink = 1.0 - 0.32 * smoothstep(1.1, 3.8, d);   // 卡通亮场: 远处只轻微渐暗成亮青水, 不沉黑
	ALBEDO = base * vig * sink;
	// 远处提高 roughness 并削弱镜面/受光感 (grazing 角不反白)
	ROUGHNESS = roughness_v;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("near_col", GROUND_NEAR)
	mat.set_shader_parameter("far_col", GROUND_FAR)
	var _seabed: Texture2D = load("res://assets/sprites/map/floor_bright.png") if ResourceLoader.exists("res://assets/sprites/map/floor_bright.png") else null
	if _seabed != null:
		mat.set_shader_parameter("seabed_tex", _seabed)
		mat.set_shader_parameter("seabed_amt", 0.85)
	else:
		mat.set_shader_parameter("seabed_amt", 0.0)
	mat.set_shader_parameter("half_arena", half_arena)
	mat.set_shader_parameter("vignette", 0.22)          # 卡通亮场: 暗角很轻(不压黑)
	mat.set_shader_parameter("caustic_strength", 0.17)  # 加强水面焦散光纹(原CAUSTIC_STRENGTH)
	mat.set_shader_parameter("caustic_speed", CAUSTIC_SPEED)
	return mat

# 竞技场边界软环: 一张躺平的环形渐变贴图 (中空, 边亮) 盖在地面上, 标出竞技场范围.
func _build_arena_ring(half_arena: Vector2) -> void:
	var ring := Sprite3D.new()
	ring.name = "ArenaRing"
	ring.texture = _make_arena_ring_texture()
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ring.axis = Vector3.AXIS_Y
	ring.shaded = false
	ring.transparent = true
	ring.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	ring.modulate = Color(ARENA_RING_COLOR.r, ARENA_RING_COLOR.g, ARENA_RING_COLOR.b, ARENA_RING_A)
	ring.position = Vector3(0.0, 0.012, 0.0)
	# 贴图 256px → pixel_size 让环外径 ≈ 竞技场对角略大
	var span: float = maxf(half_arena.x, half_arena.y) * 2.2
	ring.pixel_size = span / 256.0
	_world.add_child(ring)

# 环贴图: 中空软环 (radial: 内透明→环带亮→外淡出)
func _make_arena_ring_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.74, Color(1, 1, 1, 0.0))
	grad.add_point(0.86, Color(1, 1, 1, 1.0))
	grad.add_point(0.93, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256; gt.height = 256
	return gt

# 屏幕暗角材质 (canvas_item shader): 按屏幕 UV 半径平滑压暗四角. 用 shader 算 → alpha/RGB 精确,
#   不像 GradientTexture2D 经 TextureRect 那样把透明区露成灰. center 全透, 0.65 半径外渐暗到角最暗.
func _make_vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 dark_col : source_color = vec4(0.008, 0.022, 0.035, 1.0);
uniform float inner = 0.72;   // 此半径内全透 (略放大 → 中心战斗区更敞亮)
uniform float outer = 1.18;   // 到此半径达最大暗
uniform float max_a = 0.82;   // 角最大不透明度
void fragment() {
	vec2 d = UV - vec2(0.5);
	d.x *= 1.78;                       // 16:9 长宽比校正 → 暗角接近圆/椭圆贴合画面
	float r = length(d) / 0.92;        // 归一: ~1 在画面角
	float a = smoothstep(inner, outer, r) * max_a;
	COLOR = vec4(dark_col.rgb, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("max_a", clampf(VIGNETTE_A + 0.35, 0.0, 1.0))
	return mat

func _build_ui_layer() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UIOverlay"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	# 屏幕暗角 (vignette): 铺满屏一张 radial 渐变 (中心透明→四角压暗) → 聚焦中心战斗, 收边氛围.
	#   作 _ui_layer 首个子 → 在 3D 之上、其余 UI(标题/血条/飘字)之下, 不挡可读性.
	if not OS.has_environment("NOVIG"):
		var vig := ColorRect.new()
		vig.name = "Vignette"
		vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vig.material = _make_vignette_material()   # canvas shader: 按 UV 半径算暗角 alpha (RGB 正确, 不露灰)
		_ui_layer.add_child(vig)
	var title := Label.new()
	title.text = "2.5D 实时战斗 · 3v3 (左队 vs 右队)"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(24, 16)
	_ui_layer.add_child(title)
	if _is_dual_lane_mode():   # 双路 HUD: 当前路 + 双方蛋血
		_dl_hud = Label.new()
		_dl_hud.add_theme_font_size_override("font_size", 17)
		_dl_hud.add_theme_color_override("font_color", Color("#ffe08a"))
		_dl_hud.position = Vector2(340, 44); _dl_hud.size = Vector2(700, 24)
		_dl_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ui_layer.add_child(_dl_hud)
	_build_pause_log_ui()   # ⏸ 暂停 + 📜 日志 按钮/面板 (R2b)


## ⏸ 暂停 + 📜 日志 顶栏按钮 + 两个默认隐藏面板. 按钮/面板 process_mode=ALWAYS → 暂停中仍可操作.
func _build_pause_log_ui() -> void:
	_pause_btn = Button.new()
	_pause_btn.text = "⏸"
	_pause_btn.position = Vector2(1208, 12); _pause_btn.size = Vector2(52, 38)
	_pause_btn.add_theme_font_size_override("font_size", 22)
	_style_hud_btn(_pause_btn)
	_pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_btn.pressed.connect(_toggle_pause)
	_ui_layer.add_child(_pause_btn)

	var log_btn := Button.new()
	log_btn.text = "📜"
	log_btn.position = Vector2(1148, 12); log_btn.size = Vector2(52, 38)
	log_btn.add_theme_font_size_override("font_size", 20)
	_style_hud_btn(log_btn)
	log_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	log_btn.pressed.connect(_toggle_log)
	_ui_layer.add_child(log_btn)

	var stats_btn := Button.new()
	stats_btn.text = "📊"
	stats_btn.position = Vector2(1088, 12); stats_btn.size = Vector2(52, 38)
	stats_btn.add_theme_font_size_override("font_size", 20)
	_style_hud_btn(stats_btn)
	stats_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	stats_btn.pressed.connect(_on_dmg_stats_toggle)
	_ui_layer.add_child(stats_btn)

	_build_pause_panel()
	_build_log_panel()


## HUD 小按钮统一样式: 半透明深底 + 圆角 + hover 高亮.
func _style_hud_btn(b: Button) -> void:
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", Color("#dfeaf5"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.86)
	sb.border_color = Color(0.4, 0.55, 0.72, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(0.14, 0.19, 0.27, 0.94)
	sbh.border_color = Color("#ffd86b")
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 暂停浮层: 半透明黑幕 + 居中盒(继续/重开/返回菜单). 默认隐; process_mode ALWAYS(暂停中可点).
func _build_pause_panel() -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.size = Vector2(1280, 720)
	_pause_panel.visible = false
	_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击(别穿到战斗)
	_pause_panel.add_child(dim)
	var title := Label.new()
	title.text = "⏸ 已暂停"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("#ffe9a8"))
	title.size = Vector2(1280, 70); title.position = Vector2(0, 236)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_panel.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(0, 340); row.size = Vector2(1280, 50)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(row)
	row.add_child(_make_result_btn("▶ 继续", Color("#7fe39a"), Color("#06301a"),
		func() -> void: _toggle_pause()))
	row.add_child(_make_result_btn("⚔ 重开", Color("#ffd93d"), Color("#3a2a00"),
		func() -> void: get_tree().paused = false; get_tree().reload_current_scene()))
	row.add_child(_make_result_btn("🏠 返回菜单", Color("#5aa0d8"), Color("#04121e"),
		func() -> void: get_tree().paused = false; get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	_ui_layer.add_child(_pause_panel)


## 暂停开关: 切 get_tree().paused + 显/隐暂停浮层. 结算后不响应.
func _toggle_pause() -> void:
	if _settled:
		return
	var p: bool = not get_tree().paused
	get_tree().paused = p
	if _pause_panel != null and is_instance_valid(_pause_panel):
		_pause_panel.visible = p


## 战斗日志浮层: 左下角可滚动富文本. 默认隐; process_mode ALWAYS.
func _build_log_panel() -> void:
	_log_panel = Panel.new()
	_log_panel.position = Vector2(24, 300); _log_panel.size = Vector2(440, 380)
	_log_panel.visible = false
	_log_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	psb.border_color = Color(0.4, 0.55, 0.72, 0.5)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	_log_panel.add_theme_stylebox_override("panel", psb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_top = 10; vb.offset_right = -12; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 6)
	_log_panel.add_child(vb)
	var hdr := Label.new()
	hdr.text = "📜 战斗日志"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color("#cfe6ff"))
	vb.add_child(hdr)
	_log_rt = RichTextLabel.new()
	_log_rt.bbcode_enabled = true
	_log_rt.scroll_active = true
	_log_rt.scroll_following = true
	_log_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_rt.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(_log_rt)
	_ui_layer.add_child(_log_panel)


## 日志开关: 显/隐面板; 打开时用累积的 _battle_log 重建文本.
func _toggle_log() -> void:
	if _log_panel == null or not is_instance_valid(_log_panel):
		return
	_log_panel.visible = not _log_panel.visible
	if _log_panel.visible and _log_rt != null:
		_log_rt.clear()
		for line in _battle_log:
			_log_rt.append_text(str(line) + "\n")


## 追加一条战斗日志(bbcode). 封顶 _LOG_CAP 防无限增长; 面板开着才实时刷.
func _log(bbcode: String) -> void:
	_battle_log.append(bbcode)
	if _battle_log.size() > _LOG_CAP:
		_battle_log.remove_at(0)
	if _log_panel != null and is_instance_valid(_log_panel) and _log_panel.visible and _log_rt != null:
		_log_rt.append_text(bbcode + "\n")
		while _log_rt.get_paragraph_count() > _LOG_CAP:
			_log_rt.remove_paragraph(0)


func _unit_name(u: Dictionary) -> String:
	return str(u.get("name", u.get("id", "?")))

func _log_side_hex(u: Dictionary) -> String:
	return "#7fe39a" if u.get("side", "") == "left" else "#ff9a9a"

func _skill_disp(stype: String) -> String:
	return str((_skill_meta.get(stype, {}) as Dictionary).get("name", stype))

# ============================================================================
#  阵容 spawn — 读 GameState.season_leaders, 没有就 demo (1:1 复用 2D 解析)
# ============================================================================
func _spawn_teams() -> void:
	# 🛠 调试场: 空场进编辑模式 (不自动出生; 用户点击摆位). 默认关 → 走正常 spawn.
	if DEBUG_EDIT:
		_edit_mode = true
		_build_edit_palette()
		_edit_set_status("编辑模式: 点空地摆兵 · 拖拽挪位 · 右键删")
		return
	if _is_dual_lane_mode():   # 双路: 读 dual_lineup 当前路 spawn 我方 leaders+小将 + 对手, 绕过评审/EQDEMO
		if GameState != null:   # 新一局(进场): 重置分路/蛋/幸存/结果 (dual_lineup/season_leaders 保留)
			GameState.current_lane = "top"
			if GameState.egg_hp is Dictionary:
				GameState.egg_hp = {"left": 0.0, "right": 0.0}
			if GameState.dual_survivors is Dictionary:
				GameState.dual_survivors = {"left": [], "right": []}
			GameState.lane_results = {}
		_spawn_dual_lane()
		return
	var left := _resolve_left()
	var right := _resolve_right()
	var _cx := ARENA.position.x + ARENA.size.x * 0.5    # 评审演示: 龟居中拉近(相机框得到)
	var _cy := ARENA.position.y + ARENA.size.y * 0.5
	for i in range(left.size()):
		# XZ 落点: 左队靠左 (ARENA 内), 三龟纵向分布. 与 2D _spawn_teams 同口径像素坐标. 偏移走 @export 参数(#12)
		var pos := Vector2(ARENA.position.x + spawn_edge_margin, ARENA.position.y + spawn_front_margin + i * spawn_row_spacing)
		if _review_demo() and left.size() == 1:
			pos = Vector2(_cx - 150.0, _cy)
		elif _review_demo():
			pos = Vector2(_cx - 200.0, _cy + (float(i) - float(left.size() - 1) / 2.0) * minf(150.0, 520.0 / float(maxi(1, left.size()))))
		if OS.has_environment("EQDEMO_EQUIP") and left.size() > 1:
			pos = Vector2(_cx - 250.0 + float(i) * 175.0, _cy)   # 携带者+友方假人 排在水平掠射线上(看火柱扫到友军回血)
		var _lu := _make_unit(str(left[i]), "left", pos)
		if _review_demo() and str(left[i]) == "fortune":
			_lu["gold"] = 0.0   # demo: 财神起手金币(0=看自然攒金币)
		if _review_demo() and REVIEW_DUMMY_ATTACKS:
			_lu["_review_dummy"] = true   # 假人会还手时受审龟免死(看完整被动循环)
		if _review_demo() and i == 0 and _review_skill_idx() >= 1:
			_lu["echarge_perm"] = 5.0   # 评审某技: 受审龟龟能充能×5 → 高频放该技看清特效(演示用·非实战平衡·如手里剑95龟能实战约7~15s一发太稀)
		if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示
			if i == 0:   # === 携带者(持受审装备) ===
				_lu["_eqdemo_carrier"] = true
				if OS.has_environment("EQDEMO_ENEMY_ATTACKS"):
					_lu["deathfloor_until"] = 999999.0   # 挨打/叠层/反伤类: 真实血量+血锁不死(看层数/反伤/充能, HP非重点)
				elif OS.has_environment("EQDEMO_HURT"):
					_lu["hp"] = _lu["maxHp"] * clampf(float(OS.get_environment("EQDEMO_HURT")), 0.05, 1.0)   # 回血/自愈类: 真实血量起手受伤(静养看自回填血, 无敌人不锁血)
				else:
					_lu["deathfloor_until"] = 999999.0; _lu.erase("_review_dummy")   # 观察/召唤/自发/周期buff类: 真实血量(%maxHP伤害/回血不失真)+血锁不死站桩(观察模式无敌人打它)
				if OS.has_environment("EQDEMO_CAST_ONLY"):   # demo: 站桩只放技(看远程on_cast弹道从原地飞出, 不近身)
					_lu["no_move"] = true; _lu["no_basic"] = true; _lu["move_spd"] = 0.0
					_lu["active_skills"] = [OS.get_environment("EQDEMO_SKILL")] if OS.has_environment("EQDEMO_SKILL") else _lu["active_skills"]
				elif not OS.has_environment("EQDEMO_ATTACKER"):   # 默认: 站桩不攻击(召唤/自发/周期件); ATTACKER=普攻+技能
					_lu["no_move"] = true; _lu["no_basic"] = true; _lu["active_skills"] = []; _lu["move_spd"] = 0.0
				elif OS.has_environment("EQDEMO_SKILL"):
					_lu["active_skills"] = [OS.get_environment("EQDEMO_SKILL")]
			else:   # === 友方假人(EQDEMO_ALLIES; 团队增益/治疗类看队友受益) ===
				_lu["no_move"] = true; _lu["no_basic"] = true; _lu["active_skills"] = []; _lu["move_spd"] = 0.0
				_lu["maxHp"] = 4000.0; _lu["hp"] = 1600.0   # 起手40%血→看治疗/护盾刷到队友
		_units.append(_lu)
	var _rlay := _review_dummy_layout()   # 专属演示布局(相对受审龟 _cx-150)
	for i in range(right.size()):
		var pos := Vector2(ARENA.end.x - spawn_edge_margin, ARENA.position.y + spawn_front_margin + i * spawn_row_spacing)
		if not _rlay.is_empty() and i < _rlay.size():
			var _d: Dictionary = _rlay[i]
			pos = Vector2(_cx - 150.0 + float(_d.get("dx", 150.0)), _cy + float(_d.get("dy", 0.0)))
		elif _review_demo() and right.size() == 1:
			pos = Vector2(_cx + 150.0, _cy)
		elif _review_demo():
			pos = Vector2(_cx + 100.0 + (float(i) - float(right.size() - 1) / 2.0) * 150.0, _cy + 40.0)   # 横排(用户)
		if OS.has_environment("EQDEMO_EQUIP"):
			var _d1: float = float(OS.get_environment("EQDEMO_ENEMY1")) if OS.has_environment("EQDEMO_ENEMY1") else 210.0
			var _gap: float = float(OS.get_environment("EQDEMO_GAP")) if OS.has_environment("EQDEMO_GAP") else 500.0
			pos = Vector2(_cx - 150.0 + _d1 + float(i) * _gap, _cy + (float(OS.get_environment("EQDEMO_ENEMY_Y")) if OS.has_environment("EQDEMO_ENEMY_Y") else 0.0))   # 装备演示: 敌1距携带者_d1码, 两敌相距_gap; ENEMY_Y=深度偏移(测浪覆盖)
		var ru := _make_unit(str(right[i]), "right", pos)
		if _review_demo():                          # 假人: 不放技/永不死训练靶; ATTACKS时会还手(动+普攻)
			if not REVIEW_DUMMY_ATTACKS:
				ru["no_basic"] = true
				ru["no_move"] = true
			ru["active_skills"] = []
			ru["maxHp"] = REVIEW_DUMMY_HP
			ru["hp"] = ru["maxHp"]
			if not REVIEW_DUMMY_KILLABLE:
				ru["_review_dummy"] = true       # 不死沙包(受击回满); KILLABLE=会死(看换目标)
		if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示假人: 固定不动/5000血/30双抗/会掉血
			if OS.has_environment("EQDEMO_ENEMY_ATTACKS"):
				ru["no_basic"] = false; ru["no_move"] = false   # 敌逼近+普攻打携带者(演受伤/挨打类件)
			else:
				ru["no_basic"] = true; ru["no_move"] = true
			ru["active_skills"] = []
			var _dhp: float = float(OS.get_environment("EQDEMO_DUMMYHP")) if OS.has_environment("EQDEMO_DUMMYHP") else 5000.0
			ru["maxHp"] = _dhp; ru["hp"] = _dhp
			ru["base_def"] = 30.0; ru["base_mr"] = 30.0; _recalc_stats(ru)
			ru.erase("_review_dummy")
		if not _rlay.is_empty() and i < _rlay.size() and bool((_rlay[i] as Dictionary).get("fixed", false)):
			ru["no_move"] = true; ru["no_basic"] = true   # 演示专属: 该假人固定不动(如龟派气波远处靶)
		if not _rlay.is_empty() and i < _rlay.size() and (_rlay[i] as Dictionary).has("rarity"):
			ru["rarity"] = str((_rlay[i] as Dictionary)["rarity"])   # 演示专属: 指定假人稀有度(如平等审判光柱需A+目标)
		_units.append(ru)
	_inject_equipment()       # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备) — 须在被动之前
	_apply_spawn_passives()   # 登场被动 (开战即生效: 忍术暴击/怨灵诅咒/冰寒减攻/召唤等)
	_eq_apply_all_stats()     # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)
	if OS.has_environment("EQDEMO_FORCE_HP50"):   # demo: 强制携带者<50%触发救命类(044/045), 便于验证特效
		for _fu in _units:
			if _fu["side"] == "left" and not _fu.get("equips", []).is_empty():
				_fu["hp"] = _fu["maxHp"] * 0.4
				_eq_check_hp_threshold(_fu)
	_build_team_panels()      # 局内 UI: 左右队头像框栏 (主龟; 召唤体不进) — 须在 equips 注入之后

func _review_turtle() -> String:   # 受审龟: env REVIEW_TURTLE 覆盖 const (评审任意龟)
	return OS.get_environment("REVIEW_TURTLE") if OS.has_environment("REVIEW_TURTLE") else REVIEW_TURTLE
func _review_skill_idx() -> int:   # 受审技idx: env REVIEW_SKILL 覆盖 const (-1=默认轮转)
	return int(OS.get_environment("REVIEW_SKILL")) if OS.has_environment("REVIEW_SKILL") else REVIEW_SKILL_IDX
func _resolve_left() -> Array:
	if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示: 远程携带者(默认hunter)
		var lst: Array = [OS.get_environment("EQDEMO_CARRIER") if OS.has_environment("EQDEMO_CARRIER") else "basic"]
		var na: int = int(OS.get_environment("EQDEMO_ALLIES")) if OS.has_environment("EQDEMO_ALLIES") else 0
		for _a in range(na): lst.append("basic")   # 友方假人(团队增益类演示用)
		return lst
	if _review_demo():
		if not REVIEW_SHOWCASE.is_empty():
			return REVIEW_SHOWCASE.duplicate()   # 展示模式: 多只一队
		return [_review_turtle()]                 # 评审: 只 1 只受审龟(env可覆盖)
	var ldr := _season_leaders()
	return ldr if ldr.size() >= 1 else LEFT_DEMO.duplicate()

func _resolve_right() -> Array:
	if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示: 2个固定假人(相距500码)
		return ["basic", "basic"]
	if _review_demo():
		if not REVIEW_SHOWCASE.is_empty():
			var arr: Array = []
			for _i in range(REVIEW_SHOWCASE.size()):
				arr.append(REVIEW_DUMMY)
			return arr   # 展示模式: 等量假人
		var arr2: Array = []
		var _lay := _review_dummy_layout()   # 专属布局优先(如龟派气波1贴脸+1远), 否则 REVIEW_DUMMY_COUNT 横排
		var _dn: int = _lay.size() if not _lay.is_empty() else maxi(1, REVIEW_DUMMY_COUNT)
		for _j in range(_dn):
			arr2.append(REVIEW_DUMMY)
		return arr2
	# 无赛季阵容(直接进战斗调试) → demo 固定对位.
	if _season_leaders().is_empty():
		return RIGHT_DEMO.duplicate()
	# 有赛季阵容 → 优先用匹配抽到的对手 ghost.leaders (Matchmaking 写 dual_ghost); 没有则随机 bot 兜底.
	var ghost_leaders := _ghost_leaders()
	return ghost_leaders if not ghost_leaders.is_empty() else _random_bot(3)

# ============================================================================
#  双路战斗 (P3): 读 dual_lineup 当前路 spawn 我方 leaders+小将 + 对手(ghost/bot). 场内放置(P2)/蛋+围栏(P4)/半场流程(P5) 后续.
# ============================================================================
func _is_dual_lane_mode() -> bool:
	return OS.has_environment("DUALLANE") or bool(GameState.get("dual_active") if GameState != null else false)

# 地图 billboard (礁石/墙/穹顶): pixel_size 归一到 world_h 米, 脚底贴地(offset半帧); additive=发光罩(蛋穹顶).
func _map_billboard(path: String, pos2d: Vector2, world_h: float, additive: bool = false) -> Sprite3D:
	var spr := Sprite3D.new()
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		return spr
	spr.texture = tex
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.shaded = false
	spr.transparent = true
	var fh: int = maxi(1, tex.get_height())
	spr.pixel_size = world_h / float(fh)
	if additive:   # 穹顶围栏: 加性发光(暗底自然透), billboard 走 material
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.material_override = m
		spr.position = _world_pos(pos2d, world_h * 0.42)   # 抬到蛋中部罩住
	else:          # 实体礁石/墙: 脚底贴地, 面向相机
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.offset = Vector2(0.0, fh * 0.5)
		spr.position = _world_pos(pos2d, GROUND_LIFT)
	return spr

# 建地图道具(布局B): 中央大礁+上下错位墙+两端基地穹顶围栏. 幂等(已建则跳过, 跨路复用同一张图).
func _build_map_props() -> void:
	if _world.has_node("MapProps"):
		_reset_domes()   # 障碍静态复用, 但每路重置基地围栏(恢复罩住)
		return
	var root := Node3D.new(); root.name = "MapProps"; _world.add_child(root)
	var c := _arena_center
	_obstacles = [
		{"c": c, "rx": 168.0, "ry": 96.0, "img": "reef_big", "h": 2.7},                 # 中央大礁
		{"c": c + Vector2(-235.0, -198.0), "rx": 104.0, "ry": 40.0, "img": "reef_wall", "h": 1.5},  # 上墙(左偏)
		{"c": c + Vector2(235.0, 198.0), "rx": 104.0, "ry": 40.0, "img": "reef_wall", "h": 1.5},     # 下墙(右偏)
	]
	for ob in _obstacles:
		root.add_child(_map_billboard("res://assets/sprites/map/%s.png" % str(ob["img"]), ob["c"], float(ob["h"])))
	# 基地穹顶围栏(加性发光, 罩蛋) — 两端基地
	for pair in [["left", ARENA.position.x + 70.0], ["right", ARENA.end.x - 70.0]]:
		var dome := _map_billboard("res://assets/sprites/map/base_dome.png", Vector2(float(pair[1]), c.y), 3.0, true)
		dome.scale = Vector3(1.9, 1.9, 1.9)   # 罩大盖住蛋
		root.add_child(dome)
		_base_domes[str(pair[0])] = dome
	_build_decorations(root)   # 珊瑚/海草/礁石 铺边框住战场+填空地(纯装饰无footprint)
	_build_lightshafts(root)   # 水面光柱(加性发光, 深海氛围)
	_build_bubbles(root)       # 漂浮气泡颗粒

# 装饰景物: 珊瑚/海草/礁石 沿上下边框+四角+基地周围铺 (纯装饰, 无导航footprint, 不挡移动). 固定布局(可复现).
func _build_decorations(root: Node3D) -> void:
	var A := ARENA
	var top: float = A.position.y + 46.0
	var bot: float = A.end.y - 40.0
	var cx: float = _arena_center.x
	var decos := [
		[A.position.x+190, top+8, "deco_kelp", 2.4, 1.0], [A.position.x+430, top+34, "deco_coral_pink", 1.9, 1.1],
		[cx-300, top, "deco_rocks", 1.2, 1.0], [cx-40, top+22, "deco_coral_orange", 1.7, 1.0],
		[cx+300, top, "deco_kelp", 2.2, 0.9], [A.end.x-430, top+30, "deco_coral_pink", 1.8, 1.0], [A.end.x-190, top+6, "deco_rocks", 1.3, 1.1],
		[A.position.x+320, bot, "deco_coral_orange", 1.8, 1.15], [cx-380, bot-12, "deco_rocks", 1.2, 1.0],
		[cx-70, bot, "deco_kelp", 2.3, 1.0], [cx+300, bot-16, "deco_coral_pink", 1.9, 1.0], [A.end.x-350, bot, "deco_kelp", 2.2, 0.95],
		[A.position.x+165, _arena_center.y-165, "deco_coral_orange", 1.5, 0.9], [A.position.x+165, _arena_center.y+165, "deco_coral_pink", 1.6, 0.9],
		[A.end.x-165, _arena_center.y-165, "deco_coral_pink", 1.6, 0.9], [A.end.x-165, _arena_center.y+165, "deco_coral_orange", 1.5, 0.9],
	]
	for de in decos:
		var spr := _map_billboard("res://assets/sprites/map/%s.png" % str(de[2]), Vector2(float(de[0]), float(de[1])), float(de[3]))
		spr.scale = Vector3(float(de[4]), float(de[4]), float(de[4]))
		spr.modulate = Color(0.92, 0.96, 1.0)   # 卡通亮场: 珊瑚恢复鲜艳(不再压暗); 亮场里彩珊瑚本该艳
		root.add_child(spr)

# 水面光柱: 几道加性发光的柔和光束(billboard竖条), 打进深海竞技场 → 氛围/纵深.
func _build_lightshafts(root: Node3D) -> void:
	var tex := _make_lightshaft_texture()
	var cx: float = _arena_center.x
	var shafts := [[cx-520.0, 0.26], [cx-150.0, 0.34], [cx+250.0, 0.24], [cx+560.0, 0.3]]
	for sh in shafts:
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex
		spr.material_override = m
		spr.pixel_size = 9.0 / float(tex.get_height())   # 光柱高 ≈9米
		spr.modulate = Color(1, 1, 1, float(sh[1]))
		spr.position = _world_pos(Vector2(float(sh[0]), _arena_center.y), 4.2)
		root.add_child(spr)

func _make_lightshaft_texture() -> ImageTexture:
	var w := 40; var h := 200
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var vy: float = float(y) / float(h)                 # 0=顶(亮) 1=底(淡)
		var vfall: float = (1.0 - vy) * (1.0 - vy)
		for x in range(w):
			var hx: float = absf(float(x) / float(w - 1) * 2.0 - 1.0)
			var hfall: float = 1.0 - smoothstep(0.15, 1.0, hx)
			img.set_pixel(x, y, Color(0.62, 0.86, 1.0, vfall * hfall))
	return ImageTexture.create_from_image(img)

# 漂浮气泡颗粒: CPUParticles3D 缓缓上升的小圆点, 满场飘 → 深海有生气.
func _build_bubbles(root: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(ARENA.size.x * WS * 0.5, 0.3, ARENA.size.y * WS * 0.5)
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0, 0.28, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.55
	p.scale_amount_min = 0.018
	p.scale_amount_max = 0.05
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX   # 普通alpha混合(非加性实心球)→ 真气泡(透明+亮环+高光点)
	bm.albedo_texture = _make_bubble_texture()
	bm.albedo_color = Color(1, 1, 1, 0.55)
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm := QuadMesh.new(); qm.size = Vector2(1.0, 1.0)
	p.mesh = qm
	p.material_override = bm
	p.position = _world_pos(_arena_center, 0.2)
	root.add_child(p)

# 气泡贴图: 透明中空 + 亮环(泡壁) + 左上高光点 → 像真气泡不是实心发光球.
func _make_bubble_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var cc: float = (s - 1) * 0.5
	for y in range(s):
		for x in range(s):
			var r: float = sqrt(pow((x - cc) / cc, 2.0) + pow((y - cc) / cc, 2.0))
			var rim: float = smoothstep(0.55, 0.86, r) * (1.0 - smoothstep(0.9, 1.03, r))   # 泡壁亮环
			var fill: float = (1.0 - smoothstep(0.0, 0.95, r)) * 0.08                        # 极淡内填
			var hr: float = sqrt(pow((x - cc * 0.62) / (cc * 0.3), 2.0) + pow((y - cc * 0.6) / (cc * 0.3), 2.0))
			var hl: float = (1.0 - smoothstep(0.0, 1.0, hr)) * 0.85                          # 左上高光点
			var a: float = clampf(maxf(maxf(rim * 0.85, fill), hl), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.82, 0.93, 1.0, a))
	return ImageTexture.create_from_image(img)

# 每路重置基地围栏(恢复显示+满尺寸) — 障碍复用但围栏每路重新罩住.
func _reset_domes() -> void:
	for side in _base_domes:
		var d = _base_domes[side]
		if is_instance_valid(d):
			d.visible = true
			d.scale = Vector3(1.9, 1.9, 1.9)

# 椭圆近似成多边形点串 (footprint 挖洞用).
func _ellipse_pts(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

# 建 2D navmesh: 外边界=ARENA内缩(单位半径), 挖洞=障碍footprint+margin. 幂等. 只挡移动.
func _build_navmesh() -> void:
	if _nav_ready:
		return
	if _obstacles.is_empty():
		return
	_nav_map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(_nav_map, 1.0)
	NavigationServer2D.map_set_active(_nav_map, true)
	_nav_region = NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(_nav_region, _nav_map)
	NavigationServer2D.region_set_enabled(_nav_region, true)
	var poly := NavigationPolygon.new()
	poly.cell_size = 1.0
	var src := NavigationMeshSourceGeometryData2D.new()
	var m: float = 24.0   # 边界内缩(单位半径), 别贴墙
	src.add_traversable_outline(PackedVector2Array([
		ARENA.position + Vector2(m, m),
		Vector2(ARENA.end.x - m, ARENA.position.y + m),
		ARENA.end - Vector2(m, m),
		Vector2(ARENA.position.x + m, ARENA.end.y - m),
	]))
	for ob in _obstacles:   # 障碍挖洞: footprint椭圆 + 单位半径margin(留出绕行间隙)
		src.add_obstruction_outline(_ellipse_pts(ob["c"], float(ob["rx"]) + 28.0, float(ob["ry"]) + 28.0, 14))
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	NavigationServer2D.region_set_navigation_polygon(_nav_region, poly)
	NavigationServer2D.map_force_update(_nav_map)
	_nav_ready = true

# 返回单位朝目标该走的方向: 有navmesh→沿路点绕障; 否则/无路径→直奔(straight). 路径每单位缓存~0.4s.
func _nav_dir(u: Dictionary, tgt_pos: Vector2, straight: Vector2) -> Vector2:
	if not _nav_ready:
		return straight
	var now: float = _t
	var need := false
	var cached: PackedVector2Array = u.get("_nav_path", PackedVector2Array())
	if cached.size() < 2:
		need = true
	elif now >= float(u.get("_nav_repath_t", 0.0)):
		need = true
	elif (Vector2(u.get("_nav_tgt", tgt_pos)) - tgt_pos).length() > 70.0:
		need = true
	if need:
		cached = NavigationServer2D.map_get_path(_nav_map, u["pos"], tgt_pos, true)
		u["_nav_path"] = cached
		u["_nav_tgt"] = tgt_pos
		u["_nav_repath_t"] = now + 0.4
		u["_nav_wp"] = 1
	if cached.size() < 2:
		return straight
	var wp: int = int(u.get("_nav_wp", 1))
	while wp < cached.size() - 1 and (cached[wp] - u["pos"]).length() < 42.0:
		wp += 1
	u["_nav_wp"] = wp
	wp = clampi(wp, 1, cached.size() - 1)
	var to_wp: Vector2 = cached[wp] - u["pos"]
	if to_wp.length() < 1.0:
		return straight
	return to_wp.normalized()

# ── 场内放置阶段 (每战场开打前: 拖我方单位到你半场任意位置) ──
func _dl_enter_place() -> void:
	if OS.has_environment("DL_AUTOFIGHT"):   # 测试开关: 跳过放置直接开打 (headless 跑通整局流程用)
		_dl_start_fight()
		return
	_edit_drag_unit = null
	if not is_instance_valid(_dl_go_btn):
		_dl_go_btn = Button.new()
		_dl_go_btn.text = "▶  开  打"
		_dl_go_btn.add_theme_font_size_override("font_size", 28)
		_dl_go_btn.custom_minimum_size = Vector2(220, 62)
		_dl_go_btn.pressed.connect(_dl_start_fight)
		if _ui_layer != null:
			_ui_layer.add_child(_dl_go_btn)
	if not is_instance_valid(_dl_place_hint):
		_dl_place_hint = Label.new()
		_dl_place_hint.add_theme_font_size_override("font_size", 16)
		_dl_place_hint.add_theme_color_override("font_color", Color("#ffd93d"))
		_dl_place_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _ui_layer != null:
			_ui_layer.add_child(_dl_place_hint)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_dl_go_btn.position = Vector2(vp.x * 0.5 - 110.0, vp.y - 100.0)
	_dl_place_hint.position = Vector2(vp.x * 0.5 - 230.0, vp.y - 136.0)
	_dl_place_hint.size = Vector2(460, 24)
	_dl_place_hint.text = "【放置】拖我方单位到你半场(左侧)任意位置 → 点「开打」"
	_dl_go_btn.visible = true
	_dl_place_hint.visible = true

func _dl_start_fight() -> void:
	_edit_drag_unit = null
	_dl_state = "fight"
	if is_instance_valid(_dl_go_btn): _dl_go_btn.visible = false
	if is_instance_valid(_dl_place_hint): _dl_place_hint.visible = false

func _dl_handle_place_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit = _edit_unit_at_screen(event.position)   # 只拖我方(left)非蛋非召唤
			if hit != null and str(hit.get("side", "")) == "left" and not hit.get("_isEgg", false) and not hit.get("is_summon", false):
				_edit_drag_unit = hit
			else:
				_edit_drag_unit = null
		else:
			_edit_drag_unit = null
	elif event is InputEventMouseMotion and _edit_drag_unit != null:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_edit_drag_unit = null
			return
		_edit_drag_unit["pos"] = _dl_clamp_place(_screen_to_field(event.position))

func _dl_clamp_place(fp: Vector2) -> Vector2:
	fp.x = clampf(fp.x, ARENA.position.x + 60.0, _arena_center.x - 120.0)   # 只在我方半场(不越中线)
	fp.y = clampf(fp.y, ARENA.position.y + 60.0, ARENA.end.y - 60.0)
	for ob in _obstacles:   # 避开障碍footprint(椭圆内→推到边)
		var c: Vector2 = ob["c"]
		var rx: float = float(ob["rx"]) + 26.0
		var ry: float = float(ob["ry"]) + 26.0
		var d: Vector2 = fp - c
		var e: float = Vector2(d.x / rx, d.y / ry).length()
		if e < 1.0 and e > 0.01:
			fp = c + d / e
	return fp

func _spawn_dual_lane() -> void:
	var lane: String = str(GameState.current_lane) if GameState != null and GameState.current_lane != null else "top"
	if lane == "" or lane == "done":
		lane = "top"
	var lvl: int = 1
	if GameState != null and GameState.season_level != null:
		lvl = maxi(1, int(GameState.season_level))
	var _cx := ARENA.position.x + ARENA.size.x * 0.5
	var _cy := ARENA.position.y + ARENA.size.y * 0.5
	var mine: Array
	var foe: Array
	if lane == "final":   # 终极: 上下路幸存(含小将, 带30%回血)对决
		mine = _dl_survivor_specs("left")
		foe = _dl_survivor_specs("right")
	else:
		mine = GameState.get_dual_lineup().get(lane, [])
		foe = _dual_foe_lane(lane)
	_spawn_lane_side(mine, "left", lvl, Vector2(_cx - 420.0, _cy))
	_spawn_lane_side(foe, "right", lvl, Vector2(_cx + 420.0, _cy))
	# 两端基地各 spawn 一颗蛋(围栏罩住). egg_hp 跨路累积(缺则按平均等级初始化).
	_dl_ensure_egg_hp(lvl)
	_units.append(_make_unit("__egg__", "left", Vector2(ARENA.position.x + 70.0, _cy), {"egg": true, "egg_side": "left", "hp": _dl_egg_hp("left")}))
	_units.append(_make_unit("__egg__", "right", Vector2(ARENA.end.x - 70.0, _cy), {"egg": true, "egg_side": "right", "hp": _dl_egg_hp("right")}))
	_build_map_props()   # 地图障碍(中央大礁+两侧墙)+基地穹顶围栏(幂等, 跨路复用)
	_build_navmesh()     # 2D navmesh 避障(幂等; 障碍挖洞→单位绕行)
	# 装备+登场被动管线(评审流程走的 756-758, 双路早退绕过了→这里补上): leader读persistent_equipped+dual_lineup, 小将读dual_lineup._dl_equips, 双方leader上登场被动
	_inject_equipment()
	_apply_spawn_passives()
	_eq_apply_all_stats()
	_dl_state = "place"   # 先进场内放置阶段(拖我方单位到位)→点「开打」才 fight
	_dl_enter_place()

func _dl_ensure_egg_hp(lvl: int) -> void:   # egg_hp 缺则按 2000+100×平均等级 初始化(两侧)
	if GameState == null:
		return
	if not (GameState.egg_hp is Dictionary):
		return
	for s in ["left", "right"]:
		if float(GameState.egg_hp.get(s, 0.0)) <= 0.0:
			GameState.egg_hp[s] = 2000.0 + 100.0 * float(lvl)

func _dl_egg_hp(side_lr: String) -> float:
	if GameState != null and GameState.egg_hp is Dictionary:
		return maxf(1.0, float(GameState.egg_hp.get(side_lr, 2100.0)))
	return 2100.0

# spawn 一路一侧: leaders 用 _make_unit(id); 小将用 minion spec; 0统领路首个小将=精英. 纵向排开.
func _spawn_lane_side(units: Array, side: String, lvl: int, base: Vector2) -> void:
	var lead_n := 0
	for u in units:
		if u is Dictionary and str(u.get("kind", "")) == "leader":
			lead_n += 1
	var minion_seen := 0
	var n: int = units.size()
	for i in range(n):
		var u: Dictionary = units[i] if units[i] is Dictionary else {}
		var pos := base + Vector2(0.0, (float(i) - float(n - 1) / 2.0) * 154.0)
		var made: Dictionary
		if str(u.get("kind", "")) == "leader":
			made = _make_unit(str(u.get("id", "basic")), side, pos)
		else:
			var elite: bool = (lead_n == 0 and minion_seen == 0)
			minion_seen += 1
			var mlv: int = lvl
			if side == "left": mlv += int(u.get("temp_lv", 0))   # 临时等级器用在小将身上(糖果罐战利品·记在阵容格子上)
			made = _make_unit("__minion__", side, pos, {"minion": true, "role": str(u.get("role", "front")), "elite": elite, "level": mlv})
		if u.has("hp_frac"):   # 幸存带血进终极
			made["hp"] = maxf(1.0, made["maxHp"] * clampf(float(u["hp_frac"]), 0.05, 1.0))
		if u.has("equips") and u["equips"] is Array and not (u["equips"] as Array).is_empty():
			made["_dl_equips"] = (u["equips"] as Array).duplicate(true)   # 局外dual_lineup配的装(leader/小将), _inject_equipment 优先用
		_units.append(made)

# 终极战场我方/敌方阵容 = 上下路累加的幸存(含小将+30%回血). 缺则兜底.
func _dl_survivor_specs(side_lr: String) -> Array:
	if GameState != null and GameState.dual_survivors is Dictionary:
		var s: Array = GameState.dual_survivors.get(side_lr, [])
		if not s.is_empty():
			return s
	return [{"kind": "leader", "id": "basic"}]   # 兜底(理论不会到)

# 对手当前路阵容: 匹配抽到的 ghost 快照(lane_assign 该路 leaders + 各自 equipped) → 否则 bot(2龟+1前排小将).
#   ★对手装备按档位生效: 从 dual_ghost.equipped[pet] 取, 挂到 spec["equips"] → _spawn_lane_side 转 _dl_equips → _inject_equipment 应用.
func _dual_foe_lane(lane: String) -> Array:
	if GameState != null and GameState.dual_ghost is Dictionary:
		var dg: Dictionary = GameState.dual_ghost
		# 兼容老结构: dg[lane] 直接是单位规格数组
		if dg.has(lane) and dg[lane] is Array and not (dg[lane] as Array).is_empty():
			return dg[lane]
		# ghost/bot 快照: lane_assign[lane] = 该路 pet_id 列表; equipped[pet] = 该龟装备
		var la = dg.get("lane_assign", {})
		if la is Dictionary and (la as Dictionary).get(lane) is Array and not ((la as Dictionary)[lane] as Array).is_empty():
			var geq: Dictionary = dg.get("equipped", {}) if dg.get("equipped") is Dictionary else {}
			var specs: Array = []
			for pid in (la as Dictionary)[lane]:
				var spec: Dictionary = {"kind": "leader", "id": str(pid)}
				if geq.has(str(pid)) and geq[str(pid)] is Array:
					spec["equips"] = (geq[str(pid)] as Array).duplicate(true)   # 对手按档装备
				specs.append(spec)
			specs.append({"kind": "minion", "role": "front"})   # 每路补1前排小将(同 bot 结构)
			return specs
	# 兜底 bot(无快照/冷启动)
	var pool := ["stone", "ninja", "ghost", "ice", "diamond", "fortune", "bamboo", "angel"]
	var off: int = 0 if lane == "top" else 3
	return [
		{"kind": "leader", "id": pool[off % pool.size()]},
		{"kind": "leader", "id": pool[(off + 1) % pool.size()]},
		{"kind": "minion", "role": "front"},
	]

# ── 双路流程控制 (P4: 团灭→破蛋10s窗口→结束; P5 升级为 top→bottom→final 分路推进) ──
func _dl_side_alive(side: String) -> int:   # 一侧存活非蛋非召唤单位数
	var n := 0
	for u in _units:
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_summon", false):
			continue
		# 赛博侵入被黑单位: 按【原阵营】计存活数(临时倒戈不算赛博方·也别把原阵营"抹空"→防提前判胜负)
		var _eff_side: String = str(u.get("_hijack_orig_side", u.get("side", ""))) if u.get("hijacked", false) else str(u.get("side", ""))
		if _eff_side == side:
			n += 1
	return n

func _dl_drop_fence(side_lr: String) -> void:   # 该方蛋围栏消失(可被自由索敌); 终极路暴露蛋挂 ×5承伤+自损
	var is_final: bool = GameState != null and str(GameState.current_lane) == "final"
	for u in _units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == side_lr:
			u["_egg_fence"] = false
			if is_final:
				u["_egg_final"] = true                # ×5承伤(见 _apply_damage_from)
				u["_egg_selfloss_next"] = _t + 2.5    # 每2.5s自损25%maxHp
	var dome = _base_domes.get(side_lr, null)   # 围栏消失: 穹顶塌缩淡出(蛋暴露)
	if is_instance_valid(dome):
		_reg_tween().tween_property(dome, "scale", Vector3(0.02, 0.02, 0.02), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

func _dl_flow_check() -> void:
	if _over or _dl_state == "done":
		return
	# 终极暴露蛋自损 25%maxHp / 2.5s
	for u in _units:
		if u.get("_egg_final", false) and u.get("alive", false) and _t >= float(u.get("_egg_selfloss_next", 1.0e18)):
			u["_egg_selfloss_next"] = _t + 2.5
			_raw_lose(u, u["maxHp"] * 0.25)
	# 蛋血同步回 GameState + 蛋破判负(谁蛋先破谁输)
	for u in _units:
		if u.get("_isEgg", false):
			var es := str(u.get("egg_side_lr", "left"))
			if GameState != null and GameState.egg_hp is Dictionary:
				GameState.egg_hp[es] = maxf(0.0, float(u["hp"]))
			if not u.get("alive", true):
				_dl_finish(es == "right")   # 右蛋破→我方(左)赢
				return
	var la := _dl_side_alive("left")
	var ra := _dl_side_alive("right")
	if _dl_state == "fight":
		if la == 0 or ra == 0:
			_dl_wiped_side = "left" if la == 0 else "right"
			_dl_drop_fence(_dl_wiped_side)
			var is_final: bool = GameState != null and str(GameState.current_lane) == "final"
			_dl_window_until = (1.0e18 if is_final else _t + 10.0)   # 终极无时限(打爆蛋为止), 非终极10s
			_dl_state = "eggwindow"
			if OS.has_environment("XDBG"): print("XDBG_DL wiped=", _dl_wiped_side, " t=", _t, " → eggwindow(10s)")
	elif _dl_state == "eggwindow":
		if _t >= _dl_window_until:
			_dl_lane_over(_dl_wiped_side)   # 窗口到期: 被团灭方输本路

# P5: 本路结束 → 记录胜方 + 幸存snapshot(30%回血,供终极) + 推进 top→bottom→final/done
func _dl_lane_over(loser_side: String) -> void:
	if _over:
		return
	var winner_lr := "right" if loser_side == "left" else "left"
	var lane := str(GameState.current_lane) if GameState != null else "top"
	_dl_snapshot_survivors()          # 上下路幸存(含小将)累加, 回30%血 → 终极战场用
	if GameState != null:
		GameState.record_lane_result(winner_lr)   # 内部推进 current_lane (top→bottom→final→done)
	var next_lane := str(GameState.current_lane) if GameState != null else "done"
	if OS.has_environment("XDBG"): print("XDBG_DL lane '", lane, "' over, winner=", winner_lr, " → next=", next_lane)
	# 整场结束? (done, 或 2-0 横扫无需终极)
	if next_lane == "done":
		_dl_finish(_dl_overall_won())
		return
	if next_lane == "final" and GameState != null and not GameState.dual_lane_needs_final():
		_dl_finish(_dl_overall_won())   # 2-0 横扫
		return
	_dl_next_lane()                   # 清场重开下一路(bottom/final)

func _dl_overall_won() -> bool:
	if GameState == null:
		return false
	return str(GameState.dual_lane_winner()) == "left"

# 幸存快照: 上下路存活的 leaders+小将(非蛋非召唤) 回30%已损血, 累加进 dual_survivors(供终极)
func _dl_snapshot_survivors() -> void:
	if GameState == null or not (GameState.dual_survivors is Dictionary):
		return
	for side in ["left", "right"]:
		var cur: Array = GameState.dual_survivors.get(side, [])
		for u in _units:
			if not u.get("alive", false) or str(u.get("side", "")) != side:
				continue
			if u.get("_isEgg", false) or u.get("is_summon", false):
				continue
			var healed: float = minf(u["maxHp"], u["hp"] + (u["maxHp"] - u["hp"]) * 0.30)
			var spec := {"hp_frac": clampf(healed / maxf(1.0, u["maxHp"]), 0.05, 1.0)}
			if u.get("_isMinion", false):
				spec["kind"] = "minion"; spec["role"] = str(u.get("minion_role", "front")); spec["elite"] = bool(u.get("is_elite", false))
			else:
				spec["kind"] = "leader"; spec["id"] = str(u.get("id", "basic"))
			cur.append(spec)
		GameState.dual_survivors[side] = cur

# 清当前路所有单位/弹道/特效节点 → 供重开下一路
func _dl_clear_units() -> void:
	for u in _units:
		for k in ["sprite", "shadow", "contact", "ring"]:
			var n = u.get(k, null)
			if is_instance_valid(n):
				n.queue_free()
		var br = u.get("bar_root", null)
		if is_instance_valid(br):
			br.queue_free()
	_units.clear()
	for pr in _projectiles:
		var pn = pr.get("node", null)
		if is_instance_valid(pn):
			pn.queue_free()
	_projectiles.clear()
	_pending_shots.clear()
	for f in _follow_vfx:
		var fs = f.get("spr", null)
		if is_instance_valid(fs):
			fs.queue_free()
	_follow_vfx.clear()

func _dl_next_lane() -> void:
	_dl_clear_units()
	_over = false
	_dl_state = ""
	_dl_wiped_side = ""
	_spawn_dual_lane()   # 读推进后的 current_lane; final 从幸存 spawn

func _dl_finish(won: bool) -> void:
	if _over:
		return
	if OS.has_environment("XDBG"): print("XDBG_DL finish won=", won, " t=", _t, " egg_hp=", (GameState.egg_hp if GameState != null else {}))
	_over = true
	_dl_state = "done"
	_settle_gears()        # ★#1修: 双路(正常对局)结束此前只弹横幅, 从不结算 → 无币/经验/命/战绩/ghost。补齐同非双路路径。
	_settle_season(won)    # 结果喂赛季(命/币/胜场/XP/糖果罐/ghost上传), 守卫一次性
	_show_banner(won)

func _dl_update_hud() -> void:   # 双路 HUD: 当前路 + 双方蛋血 + 破蛋窗口计时
	var lane := str(GameState.current_lane) if GameState != null else "top"
	var lane_cn: String = {"top": "上半场", "bottom": "下半场", "final": "终极战场", "done": "结算"}.get(lane, lane)
	var lhp := 0
	var rhp := 0
	for u in _units:
		if u.get("_isEgg", false):
			if str(u.get("egg_side_lr", "")) == "left":
				lhp = int(u["hp"])
			else:
				rhp = int(u["hp"])
	var st := ""
	if _dl_state == "eggwindow":
		var rem := _dl_window_until - _t
		st = ("  ·  破蛋窗口 %.0fs" % maxf(0.0, rem)) if rem < 1.0e17 else "  ·  破蛋(决胜)"
	_dl_hud.text = "【%s】   我方蛋 %d   vs   敌方蛋 %d%s" % [lane_cn, lhp, rhp, st]

## 匹配对手快照的首领 id (Matchmaking 写 GameState.dual_ghost). 过滤到 STATS 已知龟, 上限 3.
func _ghost_leaders() -> Array:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var dg = gs.get("dual_ghost")
	if not (dg is Dictionary):
		return []
	var ldr = (dg as Dictionary).get("leaders", [])
	if not (ldr is Array):
		return []
	var out: Array = []
	for x in ldr:
		if STATS.has(str(x)):
			out.append(str(x))
		if out.size() >= 3:
			break
	return out

func _season_leaders() -> Array:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var ldr = gs.get("season_leaders")
	if not (ldr is Array):
		return []
	var out: Array = []
	for x in ldr:
		if STATS.has(str(x)):
			out.append(str(x))
		if out.size() >= 3:
			break
	return out

# 单位等级 (血条左侧牌): 玩家队(left)读 GameState.season_level; bot 队随机 1-5 (展示用). 0=不显牌.
func _unit_level(side: String) -> int:
	var _gsd = get_node_or_null("/root/GameState")
	if _gsd != null:
		var _dl = _gsd.get("debug_level")
		if _dl != null and int(_dl) > 0:
			return int(_dl)                  # 调试器: 强制全体等级(两队同档)
	if _review_demo():
		return 1                             # 评审默认 Lv1(看 base 数值); 调试器设 debug_level 可 override
	if side == "left":
		var gs = get_node_or_null("/root/GameState")
		if gs != null:
			var lv = gs.get("season_level")
			if lv != null:
				return maxi(1, int(lv))
		return 1
	# 右队 bot: 给个合理等级 (与玩家相近), 演示血条牌不空
	var gs2 = get_node_or_null("/root/GameState")
	var base := 1
	if gs2 != null and gs2.get("season_level") != null:
		base = maxi(1, int(gs2.get("season_level")))
	return base

# 等级乘数: 该单位/召唤体所属侧的等级 → 主属性 +5%/级 (与 _make_unit spawn 缩放同公式).
#   装备 flat 加值 + 固定值召唤体(随从/海螺虫/大熊) 用它"吃等级"; owner 派生召唤体已间接吃, 不用.
func _lvl_mult_for(u: Dictionary) -> float:
	var lvl: int = maxi(1, _unit_level(str(u.get("side", "left"))))
	return 1.0 + 0.05 * float(lvl - 1)

func _random_bot(n: int) -> Array:
	var pool: Array = STATS.keys()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array = []
	for i in range(mini(n, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

# ----------------------------------------------------------------------------
#  像素 XZ 坐标 → 3D 世界坐标 (height=Y). center 居中 + WS 缩放.
# ----------------------------------------------------------------------------
func _world_pos(pos: Vector2, height: float) -> Vector3:
	return Vector3((pos.x - _arena_center.x) * WS, height, (pos.y - _arena_center.y) * WS)

func _make_unit(id: String, side: String, pos: Vector2, spec: Dictionary = {}) -> Dictionary:
	var is_minion: bool = bool(spec.get("minion", false))
	var is_egg: bool = bool(spec.get("egg", false))
	var d: Dictionary
	var st: Array
	var sd: Dictionary
	if is_minion:   # 深海小将: 非龟, 自带立绘/数值(750血·45攻·双抗7 ×1.05^级; 前排挥砍范围70/后排射击400), 无技能被动
		var _mf: bool = str(spec.get("role", "front")) == "front"
		var _me: bool = bool(spec.get("elite", false))
		var _mm: float = pow(1.05, maxf(0.0, float(int(spec.get("level", 1)) - 1)))
		d = {"name": ("精英小将" if _me else "小将"), "rarity": "C", "crit": 0.0,
			"hp": 250.0 * _mm * 3.0, "atk": 30.0 * _mm * (1.4 if _mf else 1.5), "def": 7.0, "mr": 7.0}
		st = [_mf, 105.0, 0.85, (70.0 if _mf else 400.0)]
		sd = _minion_sprite_dict(_me, not _mf)
	elif is_egg:   # 龟蛋: 纯血包 fighter(atk/def/mr=0), 不动不攻击, 免控/斩/嘲讽, 走完整伤害管线; 围栏未破不可主动索敌(AoE穿栏)
		d = {"name": "龟蛋", "rarity": "SSS", "crit": 0.0, "hp": maxf(1.0, float(spec.get("hp", 2100))), "atk": 0.0, "def": 0.0, "mr": 0.0}
		st = [true, 0.0, 99.0, 0.0]
		sd = _egg_sprite_dict()
	else:
		d = _data_by_id.get(id, {})
		st = STATS.get(id, DEFAULT_STAT)
		sd = _resolve_pet_sprite(id)
	var hp := float(d.get("hp", 1350))  # hp已是最终值
	# --- 立绘 billboard sprite: 全身图 + idle sprite-sheet 动画 (接地软渐隐 shader 在单帧 UV 上做底淡) ---
	var tex: Texture2D = sd["tex"]
	var frame_h: int = int(sd.get("frame_h", 64))
	# pixel_size: 让单帧高度 = TARGET_BODY_H 米 (全身图归一, 不论 64px 还是 500px 都同样大小)
	var px: float = (TARGET_BODY_H / float(maxi(1, frame_h))) if tex != null else PIXEL_SIZE
	var spr := Sprite3D.new()
	spr.name = "Unit_" + id
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = px
	spr.shaded = false
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var grounded_mat: ShaderMaterial = null
	if tex != null:
		spr.hframes = int(sd.get("hframes", 1))
		spr.vframes = int(sd.get("vframes", 1))
		spr.frame = 0
		spr.offset = Vector2(0.0, frame_h * 0.5)             # 脚底贴地: 单帧上抬半帧高
		grounded_mat = _make_grounded_material(tex, sd)      # 接地软渐隐 (单帧 UV 上做底淡)
		spr.material_override = grounded_mat
	spr.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(spr)

	# --- blob 暗影 (外圈柔影, 跟 XZ 不跟 Y) ---
	var shadow := Sprite3D.new()
	shadow.name = "Shadow_" + id
	shadow.texture = _make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.01
	shadow.shaded = false
	shadow.transparent = true
	shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	shadow.modulate = Color(1, 1, 1, SHADOW_BASE_A)
	shadow.scale = SHADOW_BASE
	shadow.position = _world_pos(pos, 0.02)
	_world.add_child(shadow)

	# --- 接触核影 (脚下深实小影, 盖立绘/地面交界 → 锚定"踩在地上", §GROUNDING 接地三件套之一) ---
	var contact := Sprite3D.new()
	contact.name = "Contact_" + id
	contact.texture = _make_contact_texture()
	contact.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	contact.axis = Vector3.AXIS_Y
	contact.pixel_size = 0.012
	contact.shaded = false
	contact.transparent = true
	contact.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	contact.modulate = Color(1, 1, 1, 0.0)   # 隐藏接触波纹(用户"只留影子")
	contact.scale = CONTACT_BASE
	contact.position = _world_pos(pos, 0.028)
	_world.add_child(contact)

	# --- 队伍底色环 (脚下, 区分敌我) ---
	var ring := Sprite3D.new()
	ring.texture = _make_ring_texture(Color("#3fa9ff") if side == "left" else Color("#ff5a5a"))
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ring.axis = Vector3.AXIS_Y
	ring.pixel_size = 0.011
	ring.shaded = false
	ring.transparent = true
	ring.modulate = Color(1, 1, 1, 0.0)   # 隐藏队色环(_make_ring_texture忽略色=白; 用户"只留影子")
	ring.position = _world_pos(pos, 0.015)
	_world.add_child(ring)

	# --- HP / 龟能 overlay (CanvasLayer 上, 每帧 unproject 定位) ---
	var bar := _make_status_bar(side, _unit_level(side))
	_ui_layer.add_child(bar["root"])

	var u := {
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")), "side": side, "passive": d.get("passive", {}),
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"base_atk": float(d.get("atk", 40)), "base_def": float(d.get("def", 12)), "base_mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "lifesteal": 0.0,
		"armor_pen": 0.0, "armor_pen_pct": 0.0, "magic_pen": 0.0, "magic_pen_pct": 0.0,
		"heal_amp": 0.0, "shield_amp": 0.0, "damage_reduction": 0.0, "damage_amp": 0.0, "reflect": 0.0, "tenacity": 0.0,
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": (maxf(float(st[3]), MELEE_ATK_RANGE_MIN) if bool(st[0]) else float(st[3])),   # 近战射程抬到≥100(用户: 修贴脸重叠·远程不动)
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		# 选3 多技能: loadout 的非基础技(physical/magic 是普攻=自动) → 主动技轮转, 龟能满放下一个
		"active_skills": ([] if (is_minion or is_egg) else _resolve_active_skills(id, side == "left")), "skill_idx": 0,
		"skill_cd": {}, "skill_gcd_until": 0.0,   # 逐技各自冷却剩余秒(懒填) + 同龟连放最小间隔
		# 永久护盾 / 控制 / 旧式灼烧(保留兼容) ----
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		# 层数式 DoT (灼烧/中毒/流血, 1:1 dot.gd 层数衰减模型) ----
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0,
		# 效果积木状态 ----
		"buffs": [], "dots": [],
		"taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0,
		"summons": [],
		# 装备 (Phase 3b: 恒空, 不触发钩子) ----
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": ring, "shadow_base_scale": SHADOW_BASE,
		"contact": contact, "contact_base_scale": CONTACT_BASE,
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"], "level_badge": bar.get("level_badge", null),
		"spr_base_offy": spr.offset.y,
		# 立绘动画态 (idle sprite-sheet 循环 + attack/hurt/death 动作覆盖一次) ----
		"grounded_mat": grounded_mat,       # 接地 shader 材质 (设 frame uniform 切帧)
		"idle_sd": sd,                      # idle 帧字典 {tex,frames,fps,frame_h,hframes,vframes}
		"idle_px": px,                      # idle 全身图 pixel_size (动作切回时复原)
		"idle_offy": (frame_h * 0.5) if tex != null else 0.0,
		"anim_t": 0.0,                      # 当前动画累计时间 (驱动帧)
		"anim_sd": sd,                      # 当前正播的帧字典 (idle 或动作)
		"anim_action": "",                  # 非空=正在播动作 (attack/hurt/death), 播完回 idle
		# Phase4 juice 态 (每帧从这些字段重建 scale/modulate/bob, 不叠 tween → 精确复原) ----
		"spr_base_scale": spr.scale,        # billboard 基准 scale (复原锚点; Sprite3D 默认 (1,1,1))
		"flash_t": 0.0,                     # 受击闪白剩余秒 (>0 提白, 线性淡回)
		"hitsq_t": 0.0,                    # 受击压扁剩余秒
		"land_t": 0.0,                     # 落地压扁剩余秒
		"swing_t": 0.0,                    # 出招挥出(伸)剩余秒
		"windup_t": 0.0,                   # 出招预备(缩)剩余秒
		"bob_phase": randf() * TAU,        # idle bob 起始相位 (错峰, 不齐刷)
	}
	# 等级缩放: 主属性 +5%/级, 攻速 +2%/级 (吃等级表见 战斗基础-策划焊死.md §三). 小将自带×1.05缩放, 跳过龟式缩放.
	var _lvl: int = maxi(1, _unit_level(side))
	if side == "left" and not is_minion and not is_egg and GameState != null:   # 临时等级器(糖果罐战利品·封板L402): 玩家方该龟本大轮永久+N级(切轮重置)
		_lvl += GameState.temp_level_bonus(id)
	if _lvl > 1 and not is_minion and not is_egg:
		var _m: float = 1.0 + 0.05 * float(_lvl - 1)
		u["maxHp"] *= _m; u["hp"] = u["maxHp"]
		u["atk"] *= _m; u["base_atk"] *= _m
		u["def"] *= _m; u["base_def"] *= _m
		u["mr"] *= _m; u["base_mr"] *= _m
		u["atk_interval"] /= (1.0 + 0.02 * float(_lvl - 1))   # 攻速+2%/级 → 间隔变短
	var _ec := {}                                    # 数据驱动龟能: 该龟各技 type→energyCost
	for _sk in d.get("skillPool", []):
		var _e = _sk.get("energyCost", null)
		if _e != null:
			_ec[str(_sk.get("type", ""))] = float(_e)
	u["energy_cost"] = _ec
	u["level"] = _lvl
	if is_minion:
		u["_isMinion"] = true
		u["minion_role"] = str(spec.get("role", "front"))
		u["is_elite"] = bool(spec.get("elite", false))
	if is_egg:
		u["_isEgg"] = true
		u["_eggImmune"] = true          # 免控/斩/嘲讽
		u["_egg_fence"] = true           # 围栏未破: 不可主动索敌(AoE穿栏)
		u["egg_side_lr"] = str(spec.get("egg_side", "left"))   # 该蛋归属方(left/right), 写回 GameState.egg_hp
		u["no_move"] = true; u["no_basic"] = true
	return u

# 小将立绘字典 (静态单帧: minion.png 前排 / minion-back.png 后排 / minion-elite.png 精英)
func _minion_sprite_dict(is_elite: bool, is_back: bool) -> Dictionary:
	var img: String = "pets/minion-elite.png" if is_elite else ("pets/minion-back.png" if is_back else "pets/minion.png")
	var path: String = SPRITE_DIR + img
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var th: int = tex.get_height() if tex != null else 64
	return {"tex": tex, "frames": 1, "fps": 1.0, "frame_h": th, "hframes": 1, "vframes": 1, "loop": false}

# 龟蛋立绘字典 (pets/egg.png = 单蛋 3帧 idle 动画横排 79×80, 修: 原当 frames:1 显成"3蛋并排")
func _egg_sprite_dict() -> Dictionary:
	var path: String = SPRITE_DIR + "pets/egg.png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var th: int = tex.get_height() if tex != null else 80
	return {"tex": tex, "frames": 3, "fps": 4.0, "frame_h": th, "hframes": 3, "vframes": 1, "loop": true}

# ----------------------------------------------------------------------------
#  立绘解析 (id → 全身图 + sprite-sheet 元数据). 数据来源: pets.json `img`(相对 res://assets/sprites/)
#  + `sprite`{frames,frameW,frameH,duration}. 1:1 复用回合制 BattleScene 取图口径.
#  返回 {tex, frames, fps, frame_h, hframes, vframes, loop}. 缺 sprite → 静态全身图 (frames=1).
#  全身图缺 → 退回 avatars/<id>.png 头像 (占位). 都缺 → tex=null (上层报 warning).
# ----------------------------------------------------------------------------
func _resolve_pet_sprite(id: String) -> Dictionary:
	var d: Dictionary = _data_by_id.get(id, {})
	var img := str(d.get("img", ""))
	var meta = d.get("sprite", null)
	# ① pets.json img 全身图 (优先, 全 28 龟都有)
	if img != "":
		var full := SPRITE_DIR + img
		if ResourceLoader.exists(full):
			var tex: Texture2D = load(full)
			if tex != null:
				return _sprite_dict_from(tex, meta, true)
	# ② 退回头像 (占位)
	var av := AVATAR_DIR + id + ".png"
	if ResourceLoader.exists(av):
		push_warning("RealtimeBattle3D: %s 无全身图, 退回头像 (占位)" % id)
		return _sprite_dict_from(load(av), null, true)
	push_warning("RealtimeBattle3D: 立绘缺失 %s (占位空)" % id)
	return {"tex": null, "frames": 1, "fps": 8.0, "frame_h": 64, "hframes": 1, "vframes": 1, "loop": true}

# 由 texture + sprite 元数据算帧布局/帧率 (1:1 回合制: declared 帧丢最后一帧, fps=max(4,round(frames*1000/max(200,dur)))).
#   meta 缺 → 整图当单帧静态. drop_last=注册龟丢末帧 (与回合制 BootScene 一致).
func _sprite_dict_from(tex: Texture2D, meta, drop_last: bool) -> Dictionary:
	var tw := tex.get_width()
	var th := tex.get_height()
	if meta is Dictionary and (meta as Dictionary).has("frameW"):
		var m: Dictionary = meta
		var fw: int = maxi(1, int(m.get("frameW", tw)))
		var fh: int = maxi(1, int(m.get("frameH", th)))
		var hframes: int = maxi(1, int(floor(float(tw) / float(fw))))
		var vframes: int = maxi(1, int(floor(float(th) / float(fh))))
		var frame_total: int = hframes * vframes
		var declared: int = int(m.get("frames", frame_total))
		var frames: int = maxi(1, mini(declared, frame_total - 1)) if drop_last else maxi(1, mini(declared, frame_total))
		var dur_ms: float = float(m.get("duration", 800))
		var fps: float = maxf(4.0, roundf(float(frames) * 1000.0 / maxf(200.0, dur_ms)))
		return {"tex": tex, "frames": frames, "fps": fps, "frame_h": fh, "hframes": hframes, "vframes": vframes, "loop": true}
	# 单帧静态全身图
	return {"tex": tex, "frames": 1, "fps": 8.0, "frame_h": th, "hframes": 1, "vframes": 1, "loop": true}

# 动作动画表项 (attack/hurt/death) → 帧字典. frame_size = 图高 (方帧); hframes = 宽/帧高. 播一次不循环.
func _resolve_action(rel: String, fps: float) -> Dictionary:
	var full := SPRITE_DIR + rel
	if not ResourceLoader.exists(full):
		return {}
	var tex: Texture2D = load(full)
	if tex == null:
		return {}
	var tw := tex.get_width()
	var th := tex.get_height()
	var fh := th
	var hframes: int = maxi(1, int(floor(float(tw) / float(fh))))
	return {"tex": tex, "frames": hframes, "fps": fps, "frame_h": fh, "hframes": hframes, "vframes": 1, "loop": false}

# 召唤体立绘解析: spr_id (如 candy-bomb/conch-worm/doll-bear/mech/minion/treasure-golem) → pets/<spr_id>.png.
#   treasure_golem 有 idle 动画帧 → 用 sheet; 其余多为静态全身图. 缺 → tex=null (上层退色块).
func _resolve_summon_sprite(spr_id: String) -> Dictionary:
	if spr_id == "":
		return {"tex": null}
	# 大熊(玩偶小熊034): 用7帧走路当动画idle → 活的会走的大熊
	if spr_id == "doll-bear":
		var banim := SPRITE_DIR + "vfx/bear-walk.png"
		if ResourceLoader.exists(banim):
			var bt: Texture2D = load(banim)
			if bt != null:
				return _sprite_dict_from(bt, {"frames": 7, "frameW": 96, "frameH": 96, "duration": 720}, true)
	# treasure_golem idle 动画 (宝箱怪有专属帧, frameW/H=74/73, 7帧)
	if spr_id == "treasure-golem" or spr_id == "treasure_golem":
		var anim := SPRITE_DIR + "pets/animations/treasure_golem/idle.png"
		if ResourceLoader.exists(anim):
			var t: Texture2D = load(anim)
			if t != null:
				return _sprite_dict_from(t, {"frames": 8, "frameW": 74, "frameH": 73, "duration": 800}, true)
	# 通用: pets/<spr_id>.png 静态全身图
	var full := SPRITE_DIR + "pets/" + spr_id + ".png"
	if ResourceLoader.exists(full):
		var tex: Texture2D = load(full)
		if tex != null:
			return _sprite_dict_from(tex, null, false)
	return {"tex": null}

# ----------------------------------------------------------------------------
#  立绘动画驱动: 每帧推进 idle 循环 / 动作一次. 设 Sprite3D.frame 切帧 (原生裁帧).
#  idle: frame = int(t*fps) % frames (循环). 动作: 播到末帧后回 idle (清 anim_action).
# ----------------------------------------------------------------------------
func _advance_anim(u: Dictionary, delta: float) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var sd: Dictionary = u.get("anim_sd", {})
	var frames: int = int(sd.get("frames", 1))
	var fps: float = float(sd.get("fps", 8.0))
	if frames <= 1 or fps <= 0.0:
		spr.frame = 0
		return
	u["anim_t"] = float(u.get("anim_t", 0.0)) + delta
	var idx := int(u["anim_t"] * fps)
	if u.get("anim_action", "") != "":
		# 动作播一次: 到末帧 → 回 idle
		if idx >= frames:
			_set_anim_sheet(u, u.get("idle_sd", {}), "", true)
			return
	else:
		idx = idx % frames   # idle 循环
	spr.frame = clampi(idx, 0, frames - 1)

# 切换当前播放的帧表 (idle 或动作): 换 texture + Sprite3D.hframes/vframes/frame + 复位计时/pixel_size/offset.
#   is_idle=true 时复原 idle 的 px/offy; 动作图帧高可能不同, 按其帧高重算归一.
func _set_anim_sheet(u: Dictionary, sd: Dictionary, action: String, is_idle: bool) -> void:
	var spr = u.get("sprite", null)
	var mat = u.get("grounded_mat", null)
	if not is_instance_valid(spr) or sd.is_empty() or sd.get("tex", null) == null:
		return
	var tex: Texture2D = sd["tex"]
	spr.texture = tex
	spr.hframes = int(sd.get("hframes", 1))
	spr.vframes = int(sd.get("vframes", 1))
	spr.frame = 0
	if mat != null and mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("tex", tex)
	var frame_h: int = int(sd.get("frame_h", 64))
	if is_idle:
		spr.pixel_size = float(u.get("idle_px", PIXEL_SIZE))
		spr.offset = Vector2(0.0, float(u.get("idle_offy", frame_h * 0.5)))
	else:
		# 动作帧高可能 != idle (basic idle 64 / attack 120): 按动作帧高归一到同样世界高度, 脚底对齐
		spr.pixel_size = TARGET_BODY_H / float(maxi(1, frame_h))
		spr.offset = Vector2(0.0, frame_h * 0.5)
	u["anim_sd"] = sd
	u["anim_action"] = action
	u["anim_t"] = 0.0

# 触发动作动画 (attack/hurt/death). 无对应帧表的龟静默忽略 (靠 idle+juice 形变). death 播完不回 idle.
func _play_action(u: Dictionary, kind: String) -> void:
	if u == null or not is_instance_valid(u.get("sprite", null)):
		return
	# death 优先级最高; 已在播 death 不打断
	if u.get("anim_action", "") == "death":
		return
	var id := str(u.get("id", ""))
	var table: Dictionary
	match kind:
		"attack": table = ACTION_ATTACK
		"hurt":   table = ACTION_HURT
		"death":  table = ACTION_DEATH
		_:        return
	if not table.has(id):
		return
	# hurt 不打断正在播的 attack (避免普攻动作被打断闪烁); attack 不打断 hurt 中
	if kind != "death" and u.get("anim_action", "") in ["attack", "hurt"]:
		if kind == "hurt" and u.get("anim_action", "") == "hurt":
			pass   # 刷新 hurt
		elif kind != u.get("anim_action", ""):
			return
	var entry: Array = table[id]
	var asd := _resolve_action(str(entry[0]), float(entry[1]))
	if asd.is_empty():
		return
	_set_anim_sheet(u, asd, kind, false)

# ----------------------------------------------------------------------------
#  §GROUNDING — 立绘底部软渐隐 ShaderMaterial (根治"纸板硬切地面").
#  原理: 立绘 = 朝镜头的竖面 billboard, 底边是张不透明硬线 → 撞俯视地面像被刀切.
#    本 shader 让图底部 GROUND_FADE_FRAC 这段 UV 高度内 alpha 线性衰减到 GROUND_FADE_FLOOR,
#    脚部柔和淡入地面; 配合 GROUND_LIFT 略沉 + 接触核影盖交界 → 自然"站在地上".
#  render_mode depth_prepass_alpha: alpha 测深度预通道 → 立绘彼此/与地面正确排序 (替代
#    原 ALPHA_CUT_DISCARD 的硬切, 既不闪烁又保软边). vertex() 重建 upright billboard (朝相机不翻 Y).
#  material_override 接管 Sprite3D 渲染 → 闪白(flash)经 Sprite3D.modulate→COLOR 仍生效.
# ----------------------------------------------------------------------------
func _get_ground_fade_shader() -> Shader:
	if _ground_fade_shader != null:
		return _ground_fade_shader
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float fade_frac = 0.16;   // 从底起算渐隐区占图高比例
uniform float fade_floor = 0.04;  // 接地处残留 alpha 下限
uniform float vframes = 1.0;      // ★sprite-sheet 的行数 (网格图必须传, 否则底淡算错)
// 切帧由 Sprite3D 原生 hframes/vframes/frame 负责: 它把 mesh 的 UV 设成【该帧在整张图里的子矩形】,
// 所以这里 texture(tex, UV) 直接采到当前帧。UV 是【全图坐标】, 不是帧内 0..1 ——
// ★2026-07-10 订正: 旧注释写"UV 到此已是单帧内 0..1"是错的; 单行横条(vframes=1)时 UV.y 恰好等于帧内 y,
//   所以一直没暴露。改成网格(vframes>1)后必须用 fract(UV.y*vframes) 取行内局部 y, 否则只有最后一行会渐隐。

void vertex() {
	// upright billboard: 取相机右/上/前向量重建朝向, 保留 MODEL 缩放 (squash/stretch 仍生效).
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= scl.x;
	MODELVIEW_MATRIX[1] *= scl.y;
	MODELVIEW_MATRIX[2] *= scl.z;
}

void fragment() {
	vec4 c = texture(tex, UV);       // UV = 该帧在整张图里的子矩形坐标 (Sprite3D 原生裁帧)
	// 帧内局部 y: 0=帧顶, 1=帧底。网格图(vframes>1)要把全图 UV.y 折算回行内。
	float ly = (vframes <= 1.0) ? UV.y : fract(UV.y * vframes);
	float fade = 1.0;
	if (ly > 1.0 - fade_frac) {
		float k = (1.0 - ly) / max(fade_frac, 0.0001);  // 渐隐线处=1, 最底=0
		fade = mix(fade_floor, 1.0, clamp(k, 0.0, 1.0));
	}
	ALBEDO = c.rgb * COLOR.rgb;     // COLOR = Sprite3D.modulate (受击闪白 >1 提亮)
	ALPHA = c.a * fade * COLOR.a;
}
"""
	_ground_fade_shader = sh
	return sh

# 给一张立绘 texture 造接地 shader 材质. 切帧由 Sprite3D 原生 hframes/vframes 负责; shader 只做底淡, 需要行数(vframes)才能取行内局部 y.
func _make_grounded_material(tex: Texture2D, _sd: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_ground_fade_shader()
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("fade_frac", GROUND_FADE_FRAC)
	mat.set_shader_parameter("fade_floor", GROUND_FADE_FLOOR)
	mat.set_shader_parameter("vframes", float(maxi(1, int(_sd.get("vframes", 1)))))   # ★网格图必须传行数
	return mat

# blob 影贴图: radial 渐变 中心黑→边缘透明 (优化: 中段加点过渡, 边缘更柔不硬切)
# 亮光晕贴图 (命中火花用): 白心→透明 (modulate 上色才会亮; blob 是黑的不能拿来当火花)
## ★#6修: 命中辉光/子弹用 GradientTexture2D radial 会露方角(角落 alpha≠0) → 改 Image 逐像素真圆(角=0).
func _make_glow_texture() -> ImageTexture:
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c   # 0中心 → 1边缘
			var a := 0.0
			if d < 0.4:
				a = lerp(1.0, 0.7, d / 0.4)
			elif d < 0.75:
				a = lerp(0.7, 0.18, (d - 0.4) / 0.35)
			elif d < 1.0:
				a = lerp(0.18, 0.0, (d - 0.75) / 0.25)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

var _blob_tex_cache: ImageTexture = null
func _make_blob_texture() -> ImageTexture:   # Image真圆软影(角alpha=0不显方块, 替FILL_RADIAL方角bug); 黑底,modulate控浓度,缓存
	if _blob_tex_cache != null:
		return _blob_tex_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = 0.58 * pow(1.0 - d, 1.25)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_blob_tex_cache = ImageTexture.create_from_image(img)
	return _blob_tex_cache

# 接触核影贴图: 比 blob 更小更实的深核 (紧贴脚下盖立绘/地面交界 → 强化接地)
func _make_contact_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.85))
	grad.add_point(0.5, Color(0, 0, 0, 0.6))
	grad.add_point(0.85, Color(0, 0, 0, 0.12))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 96; gt.height = 96
	return gt

# 队伍环贴图: 队色 radial 软环 (占位; 商业版换贴图)
var _ring_tex_cache: ImageTexture = null
var _bolt_tex_cache: Dictionary = {}   # #6修: 子弹贴图按颜色缓存(Image 真圆, 避免每发 CPU 逐像素)
func _make_ring_texture(_col: Color) -> ImageTexture:   # Image逐像素真圆环(角alpha=0不显方块); 白底,_skill_ring用modulate上色; 缓存(每次画太费)
	if _ring_tex_cache != null:
		return _ring_tex_cache
	var N := 96
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = clampf(1.0 - absf(d - 0.82) / 0.18, 0.0, 1.0) * 0.6
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_ring_tex_cache = ImageTexture.create_from_image(img)
	return _ring_tex_cache

# 状态条: 复用回合制版 HpBar 组件 (自定义 _draw: 黑边/暗红槽/玻璃高光/逐行渐变填充/护盾段/受击红trail+白闪/刻度).
#   + 左侧等级牌 (棕底金字 Panel, 回合制 turtle-hud 同款) + 下方龟能条 (实时资源, HpBar 不画).
#   level: 玩家龟读 GameState.season_level; 召唤体无牌. 返回各组件引用供 _update_overlay 刷新.
const BAR_W := 66.0      # HpBar 宽 (实时缩小, 用户; turtle-hud原88)
const BAR_H := 4.0       # HpBar 高 (实时缩小)
func _make_status_bar(side: String, level: int = 0) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(BAR_W, 22)
	root.size = Vector2(BAR_W, 22)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- 等级牌 (棕底金字, 在血条左侧) ---
	var lv_badge: Panel = null
	if level > 0:
		var badge_fs := 8
		var bw := 13.0
		var bh := 11.0
		lv_badge = Panel.new()
		var lv_sb := StyleBoxFlat.new()
		lv_sb.bg_color = Color("#161019")              # 深暗底 (HUD暗)
		lv_sb.set_border_width_all(1)
		lv_sb.border_color = Color("#ffce4d")          # 金边
		lv_sb.set_corner_radius_all(3)                 # 圆角(设计)
		lv_sb.shadow_size = 2
		lv_sb.shadow_color = Color(0, 0, 0, 0.5)
		lv_sb.shadow_offset = Vector2(0, 1)
		lv_badge.add_theme_stylebox_override("panel", lv_sb)
		lv_badge.custom_minimum_size = Vector2(bw, bh)
		lv_badge.size = Vector2(bw, bh)
		lv_badge.position = Vector2(-(bw + 3.0), (8.0 + BAR_H * 0.5) - bh * 0.5)   # 垂直对齐HP条中线
		lv_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lv_lbl := Label.new()
		lv_lbl.text = "%d" % level
		lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lv_lbl.add_theme_font_size_override("font_size", badge_fs)
		lv_lbl.add_theme_color_override("font_color", Color("#ffd93d"))   # 金字
		lv_badge.add_child(lv_lbl)
		root.add_child(lv_badge)
	# --- HpBar 组件 (Node2D, 自定义 _draw) ---
	var hp_bar: HpBar = HpBarScene.new()
	hp_bar.setup(side == "left", false)
	hp_bar.bar_w = BAR_W   # 实时缩小血条 (覆盖 turtle-hud 硬编码 88/5)
	hp_bar.bar_h = BAR_H
	hp_bar.position = Vector2(0, 8)   # 在 root 内下移, 给上方留头 (shadow/border 在 -border)
	root.add_child(hp_bar)
	# --- 龟能条 (实时资源, 在 HP 条下方; HpBar 不画) ---
	var en_y := 8.0 + BAR_H + 3.0
	var en_bg := ColorRect.new()
	en_bg.color = Color(0, 0, 0, 0.55); en_bg.position = Vector2(0, en_y); en_bg.size = Vector2(BAR_W, 3)
	en_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(en_bg)
	var en_fill := ColorRect.new()
	en_fill.color = Color("#48c9ff"); en_fill.position = Vector2(0, en_y); en_fill.size = Vector2(0, 3)
	en_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(en_fill)
	return {"root": root, "hp_bar": hp_bar, "en": en_fill, "level_badge": lv_badge}

# ============================================================================
#  主循环 (移动 / 索敌 / 普攻 / 龟能 / 击飞物理 — 复用 2D 口径)
# ============================================================================
func _process(delta: float) -> void:
	# Phase4 顿帧 hit-stop: 计时 >0 时冻结"模拟"(逻辑推进 + juice 视觉态衰减)给重量感,
	# 但镜头震屏照常推进(冻结期间的抖动正是冲击力来源). 不碰 Engine.time_scale → 计时归零即恢复,
	# 永不卡死 (即使触发函数早退, 下一帧 delta 也会把 _hitstop 减到 0).
	var frozen := _hitstop > 0.0
	if frozen:
		_hitstop = maxf(0.0, _hitstop - delta)
	elif not _ts_active.is_empty():
		# ═══ 沙漏JoJo时停: 冻结全局_t → 全场非active的所有_t计时器暂停(金风暴/海浪/DoT无缝续); 只tick active携带者(冷却/龟能delta制照走) ═══
		_ts_remaining -= delta
		_ts_active = _ts_active.filter(func(x): return x is Dictionary and x.get("alive", false))
		if _ts_remaining <= 0.0 or _ts_active.is_empty():
			_end_timestop()
		else:
			if not _over:
				for u in _ts_active:
					_tick_unit(u, delta)        # active携带者自由行动(移动/普攻/放技/命中即时结算)
				_step_projectiles(delta)        # 内部gate: 只推进active的弹道; 其余悬空
				_step_pending_shots(delta)      # 内部gate: 只active的依次射击
				_check_end()
		_juice_decay(delta)                    # 内部gate: 只衰减active的juice(非active冲击姿势定格)
		for u in _ts_active:                    # 只推进active立绘帧动画(非active定格)
			if u.get("alive", false):
				if u.get("is_big_bear", false):
					_tick_bear_anim(u, delta)
				else:
					_advance_anim(u, delta)
		_ts_tick_visual(delta)                 # 时停视觉维持(钟表脉动/暗角等)
	else:
		# 🛠 调试场编辑态 / 双路场内放置态: 跳过模拟推进 (单位摆着不打不动), 但下方 transforms/overlay 照常 → 立绘渲染+血条仍刷新.
		if not _over and not _edit_mode and _dl_state != "place":
			_t += delta
			_ts_update_trigger(delta)   # 沙漏: 第10秒触发时停蓄力 → 蓄力满释放
			for u in _units.duplicate():
				if not u["alive"]:
					continue
				_tick_unit(u, delta)
			_apply_separation_pass(delta)   # 每帧全单位软分离(攻击/待机也摊开, 根治扎堆遮血条)
			_tick_lava_zones(delta)         # 持续地面区域 (熔岩龟·岩浆池) 周期结算
			_step_projectiles(delta)
			_step_pending_shots(delta)
			_check_end()
		_juice_decay(delta)        # squash/闪白/挥击 等计时衰减 (冻结期间不衰 → 冲击姿势保持)
		for u in _units:           # 立绘帧动画推进 (idle 循环 / 动作一次), 冻结期不推进保持冲击姿势
			if u["alive"] or u.get("anim_action", "") == "death":
				if u.get("is_big_bear", false):
					_tick_bear_anim(u, delta)   # 大熊: 状态机(走路/停顿/熊爪拍/砸地)
				else:
					_advance_anim(u, delta)
	_update_camera_shake(delta)    # 震屏始终推进 (含冻结期)
	_update_world_transforms()
	_tick_follow_vfx()             # 跟随特效(冰块等)贴目标最新世界坐标(含击飞height)
	_tick_ink_links()              # 线条·连笔连接线跟随双方脚底(到期/死亡断链)
	_update_overlay()

# ═══════════════════════════════════════════════════════════════════
#  沙漏059 JoJo时停 — 触发/蓄力/冻结/恢复/视觉 (登场10s → 蓄力1s → 时停4/10/30s, 一场一次)
# ═══════════════════════════════════════════════════════════════════
func _unit_hourglass_star(u: Dictionary) -> int:   # 该单位所装沙漏最高星(0=无)
	var best := 0
	for e in u.get("equips", []):
		if str(e.get("id", "")) == "p2eq_059":
			best = maxi(best, int(e.get("star", 1)))
	return best

func _ts_update_trigger(delta: float) -> void:   # (仅正常态调)第10秒触发蓄力 → 蓄力满释放
	if _ts_charging:
		_ts_charge_t -= delta
		if _ts_charge_t <= 0.0:
			_ts_charging = false
			_ts_fire()
		return
	if _ts_fired or not _ts_active.is_empty() or _t < 10.0:
		return
	var maxstar := 0
	for u in _units:
		if u.get("alive", false):
			maxstar = maxi(maxstar, _unit_hourglass_star(u))
	if maxstar <= 0:
		return
	var casters: Array = []
	for u in _units:
		if u.get("alive", false) and _unit_hourglass_star(u) == maxstar:
			casters.append(u)   # 最高星沙漏者(敌我皆算, 低星作废)
	if casters.is_empty():
		return
	_ts_fired = true
	_ts_maxstar = maxstar
	_ts_charging = true
	_ts_charge_t = 1.0
	_ts_charge_casters = casters
	for c in casters:
		_ts_charge_vfx(c)

func _ts_fire() -> void:
	var casters: Array = _ts_charge_casters.filter(func(x): return x is Dictionary and x.get("alive", false))
	_ts_charge_casters = []
	if casters.is_empty():
		return
	_ts_active = casters
	_ts_remaining = [4.0, 10.0, 30.0][clampi(_ts_maxstar, 1, 3) - 1]
	_ts_begin_freeze()
	_ts_visual_start()

func _end_timestop() -> void:
	_ts_resume_freeze()
	_ts_visual_end()
	_ts_active = []
	_ts_remaining = 0.0

# VFX tween 注册(时停暂停非active产生的用). 见 create_tween→_reg_tween 替换.
func _reg_tween() -> Tween:
	var t := create_tween()
	_sim_tweens.append(t)
	if _sim_tweens.size() > 512:
		_sim_tweens = _sim_tweens.filter(func(x): return x != null and x.is_valid())
	return t

func _ts_begin_freeze() -> void:   # 暂停时停开始时在跑的所有VFX tween + 粒子(active之后新建的不在此列→照跑)
	_ts_frozen_tweens = []
	for t in _sim_tweens:
		if t != null and t.is_valid() and t.is_running():
			t.pause()
			_ts_frozen_tweens.append(t)
	_ts_frozen_particles = []
	_ts_freeze_particles_in(_world)

func _ts_freeze_particles_in(n: Node) -> void:
	for c in n.get_children():
		if c is GPUParticles3D and c.speed_scale > 0.0:
			c.set_meta("_ts_spd", c.speed_scale)
			c.speed_scale = 0.0
			_ts_frozen_particles.append(c)
		if c.get_child_count() > 0:
			_ts_freeze_particles_in(c)

func _ts_resume_freeze() -> void:
	for t in _ts_frozen_tweens:
		if t != null and t.is_valid():
			t.play()
	_ts_frozen_tweens = []
	for p in _ts_frozen_particles:
		if is_instance_valid(p):
			p.speed_scale = float(p.get_meta("_ts_spd", 1.0))
	_ts_frozen_particles = []

func _ts_ensure_overlay() -> void:
	if _ts_overlay != null and is_instance_valid(_ts_overlay):
		return
	var vp := get_viewport().get_visible_rect().size
	# --- 灰世界层(layer5, 在UI层10之下 → 只灰3D世界, 数字/血条保彩上浮) ---
	_ts_overlay = CanvasLayer.new()
	_ts_overlay.layer = 5
	add_child(_ts_overlay)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()   # 压暗褪色从center按radius扩散→昏暗冷灰; 但携带者(casters)周围留彩色泡(时之主保持彩色)
	# ★2026-07-11 黑屏排查 A1: hint_screen_texture(读屏幕纹理) 在 gl_compatibility 移动端会导致【整屏黑】。
	#   → 移动端用【不读屏】的等效 shader(半透明冷灰覆盖+径向扩散+携带者彩色泡), 桌面保留原读屏版(带真灰度)。
	#   两版 uniform 完全相同(amount/radius/aspect/casters/caster_n) → _ts_tick_visual 的 set 逻辑不用改。
	if _is_mobile():
		sh.code = "shader_type canvas_item;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nvoid fragment(){\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat mask = 1.0 - smoothstep(radius-0.12, radius, length(d));\n\tfloat a = amount * mask;\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\ta *= (1.0 - keep);\n\tCOLOR = vec4(0.04, 0.04, 0.08, a * 0.82);\n}"
	else:
		sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nvoid fragment(){\n\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat mask = 1.0 - smoothstep(radius-0.12, radius, length(d));\n\tfloat a = amount * mask;\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\ta *= (1.0 - keep);\n\tfloat g = dot(c, vec3(0.299,0.587,0.114));\n\tvec3 dim = vec3(g*0.56, g*0.56, g*0.64);\n\tCOLOR = vec4(mix(c, dim, a), 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", 0.0)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))
	mat.set_shader_parameter("casters", PackedVector2Array())
	mat.set_shader_parameter("caster_n", 0)
	rect.material = mat
	_ts_overlay.add_child(rect)
	_ts_rect = rect
	# --- 反色闪层(layer60, 在UI层之上 → 反色含全屏UI) ---
	_ts_flash_overlay = CanvasLayer.new()
	_ts_flash_overlay.layer = 60
	add_child(_ts_flash_overlay)
	var frect := ColorRect.new()
	frect.set_anchors_preset(Control.PRESET_FULL_RECT)
	frect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsh := Shader.new()
	# ★A1: 移动端不读屏 → 反色改成白闪(uniform invert 不变, _ts 逻辑不用改); 桌面保留真反色
	if _is_mobile():
		fsh.code = "shader_type canvas_item;\nuniform float invert : hint_range(0.0,1.0) = 0.0;\nvoid fragment(){\n\tCOLOR = vec4(1.0, 1.0, 1.0, invert * 0.6);\n}"
	else:
		fsh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float invert : hint_range(0.0,1.0) = 0.0;\nvoid fragment(){\n\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n\tCOLOR = vec4(mix(c, vec3(1.0)-c, invert), 1.0);\n}"
	var fmat := ShaderMaterial.new()
	fmat.shader = fsh
	fmat.set_shader_parameter("invert", 0.0)
	frect.material = fmat
	_ts_flash_overlay.add_child(frect)
	_ts_flash_rect = frect

func _ts_casters_screen_uv() -> Vector2:   # active携带者质心的屏幕UV(扩散中心)
	if _cam == null or _ts_active.is_empty():
		return Vector2(0.5, 0.5)
	var acc := Vector2.ZERO; var n := 0
	for c in _ts_active:
		var head: Vector3 = _world_pos(c["pos"], 1.0)
		if not _cam.is_position_behind(head):
			acc += _cam.unproject_position(head); n += 1
	if n == 0:
		return Vector2(0.5, 0.5)
	var vp := get_viewport().get_visible_rect().size
	return (acc / float(n)) / Vector2(maxf(1.0, vp.x), maxf(1.0, vp.y))

# 释放: ①反色闪 ②压暗褪色从携带者扩散(昏暗冷灰) ③钟+携带者金辉光 (忠实DIO "時よ止まれ")
func _ts_visual_start() -> void:
	_ts_ensure_overlay()
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	mat.set_shader_parameter("center", _ts_casters_screen_uv())
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("amount", 0.0)
	fmat.set_shader_parameter("invert", 0.0)
	var fl := create_tween()   # ①反色闪(负片一下, 含全屏UI)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.0, 0.92, 0.05)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.92, 0.0, 0.13)
	var sp := create_tween(); sp.set_parallel(true)   # ②压暗褪色从携带者铺开
	sp.tween_method(func(v: float): mat.set_shader_parameter("radius", v), 0.0, 2.1, 0.5).set_ease(Tween.EASE_OUT)
	sp.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.5)
	for c in _ts_active:
		_ts_shock_ring(c["pos"])       # 中心能量涟漪波
		_ts_caster_glow(c)             # ③携带者"时之主"金辉光
	_ts_spawn_clock()                  # 停摆钟浮现

func _ts_visual_end() -> void:   # 解除: 反色再闪 + 回色(时间恢复流动)
	_ts_clear_visual_nodes()
	if _ts_rect == null or not is_instance_valid(_ts_rect):
		return
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	var fl := create_tween()
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.0, 0.7, 0.04)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.7, 0.0, 0.1)
	var tw := create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.35)

func _ts_tick_visual(_delta: float) -> void:   # 每帧喂携带者屏幕位置给灰shader → 彩色泡跟随移动的时之主
	if _ts_rect == null or not is_instance_valid(_ts_rect) or _cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var arr := PackedVector2Array()
	for c in _ts_active:
		if arr.size() >= 4:
			break
		var head: Vector3 = _world_pos(c["pos"], 1.0)
		if not _cam.is_position_behind(head):
			var sp := _cam.unproject_position(head)
			arr.append(Vector2(sp.x / maxf(1.0, vp.x), sp.y / maxf(1.0, vp.y)))
	var mat: ShaderMaterial = _ts_rect.material
	mat.set_shader_parameter("casters", arr)
	mat.set_shader_parameter("caster_n", arr.size())

# 中心能量涟漪: 一圈青白波从pos扩散(时停释放冲击波)
func _ts_shock_ring(pos2d: Vector2) -> void:
	var r := Sprite3D.new()
	var tex := _make_fire_glow_tex()
	r.texture = tex
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.modulate = Color(0.7, 0.92, 1.0, 0.0)
	r.pixel_size = (60.0 * WS) / float(maxi(1, tex.get_width()))
	r.position = _world_pos(pos2d, 1.0)
	_world.add_child(r)
	var tw := create_tween(); tw.set_parallel(true)   # 视觉波不冻结
	tw.tween_property(r, "modulate:a", 0.85, 0.12)
	tw.tween_property(r, "pixel_size", (900.0 * WS) / float(maxi(1, tex.get_width())), 0.55).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(r, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(r.queue_free)

# 携带者金辉光: 身后金色发光球, 跟随+脉动 (时之主)
func _ts_caster_glow(c: Dictionary) -> void:
	var g := Sprite3D.new()
	var tex := _make_fire_glow_tex()
	g.texture = tex
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.render_priority = -1
	g.modulate = Color(1.0, 0.82, 0.32, 0.0)
	g.pixel_size = (150.0 * WS) / float(maxi(1, tex.get_width()))
	g.position = _world_pos(c["pos"], 1.0)
	_world.add_child(g)
	_follow_vfx.append({"spr": g, "unit": c, "h": 1.0})
	_ts_glow_sprs.append(g)
	var tw := create_tween().bind_node(g).set_loops()   # 脉动(不冻结→时之主持续发光)  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	tw.tween_property(g, "modulate:a", 0.7, 0.6).from(0.35)
	tw.tween_property(g, "modulate:a", 0.35, 0.6)

# 停摆钟: 叠加层顶(不被褪色), 半透明浮于屏幕中心, 缓慢脉动
func _ts_spawn_clock() -> void:
	if _ts_overlay == null or not is_instance_valid(_ts_overlay):
		return
	var clk := TextureRect.new()
	clk.texture = load("res://assets/sprites/vfx/ts-clock.png")
	clk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	var sz := 230.0
	clk.size = Vector2(sz, sz)
	clk.position = Vector2(vp.x * 0.5 - sz * 0.5, vp.y * 0.05)   # 屏幕中心偏上
	clk.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
	clk.modulate = Color(1, 1, 1, 0.0)
	_ts_overlay.add_child(clk)
	_ts_clock = clk
	var tw := create_tween().bind_node(clk).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	tw.tween_property(clk, "modulate:a", 0.30, 0.9).from(0.10)
	tw.tween_property(clk, "modulate:a", 0.15, 0.9)

func _ts_clear_visual_nodes() -> void:
	for g in _ts_glow_sprs:
		if is_instance_valid(g):
			g.queue_free()
	_ts_glow_sprs = []
	if _ts_clock != null and is_instance_valid(_ts_clock):
		var clk := _ts_clock
		var tw := create_tween()
		tw.tween_property(clk, "modulate:a", 0.0, 0.25)
		tw.tween_callback(clk.queue_free)
	_ts_clock = null

# 蓄力(1s): 携带者头顶沙漏虚影浮现+微升 + 金沙粒从四周螺旋汇入 + 脚下金环
func _ts_charge_vfx(c: Dictionary) -> void:
	_skill_ring(c["pos"], Color(1.0, 0.85, 0.35, 0.85), 100.0)
	# 沙漏虚影
	var hg := Sprite3D.new()
	hg.texture = load("res://assets/sprites/vfx/ts-hourglass.png")
	hg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hg.shaded = false; hg.transparent = true
	hg.modulate = Color(1.0, 0.92, 0.6, 0.0)
	hg.pixel_size = (54.0 * WS) / float(maxi(1, hg.texture.get_height()))
	hg.position = _world_pos(c["pos"], 2.4)
	_world.add_child(hg)
	var tw := create_tween(); tw.set_parallel(true)
	tw.tween_property(hg, "modulate:a", 0.95, 0.4)
	tw.tween_property(hg, "position", _world_pos(c["pos"], 3.0), 1.0).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(hg, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hg.queue_free)
	# 金沙粒螺旋汇入(圆粒: 用_make_fire_glow_tex真圆, 非_make_glow_texture方角GradientTexture2D)
	var ptex := _make_fire_glow_tex()
	for k in range(10):
		var sp := Sprite3D.new()
		sp.texture = ptex
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.modulate = Color(1.0, 0.82, 0.32, 0.9)
		sp.pixel_size = 0.42 / float(maxi(1, ptex.get_width()))
		var ang := TAU * float(k) / 10.0
		var off := Vector2(cos(ang), sin(ang)) * 130.0
		sp.position = _world_pos(c["pos"] + off, 1.4)
		_world.add_child(sp)
		var stw := create_tween(); stw.set_parallel(true)
		stw.tween_property(sp, "position", _world_pos(c["pos"], 1.6), 0.9).set_ease(Tween.EASE_IN)
		stw.tween_property(sp, "modulate:a", 0.0, 0.9)
		stw.chain().tween_callback(sp.queue_free)

# 跟随单位的特效: 每帧把 sprite 贴到目标最新世界坐标(含击飞抬升). sprite 被 queue_free 后自动从列表剔除.
func _tick_follow_vfx() -> void:
	for i in range(_follow_vfx.size() - 1, -1, -1):
		var f: Dictionary = _follow_vfx[i]
		var spr = f["spr"]
		if not is_instance_valid(spr):
			_follow_vfx.remove_at(i)
			continue
		var u: Dictionary = f["unit"]
		if not u.get("alive", true):                # 目标已死 → 跟随特效随之消失
			spr.queue_free()
			_follow_vfx.remove_at(i)
			if f.get("mark", false): u["_mark_spr"] = null
			continue
		if f.get("mark", false) and _t > float(u.get("_mark_until", 0.0)):   # 锁定标记到期 → 移除
			spr.queue_free()
			_follow_vfx.remove_at(i)
			u["_mark_spr"] = null
			continue
		var base: Vector3 = _world_pos(u["pos"], float(u.get("height", 0.0)) + float(f["h"]))
		if f.has("orbit_r"):                         # 绕身环绕(水晶叠层)
			var ang: float = float(f["orbit_a"]) + _t * float(f["orbit_spd"])
			base += Vector3(cos(ang) * float(f["orbit_r"]), 0.0, sin(ang) * float(f["orbit_r"]))
		spr.position = base

func _tick_unit(u: Dictionary, delta: float) -> void:
	# DoT/buff到期/累积条/周期被动 (1:1 2D _tick_effects)
	_tick_effects(u, delta)
	_update_shield_barrier(u)   # 石头岩石护盾: 持盾常驻六棱屏障(跟随), 盾破/到期碎裂淡出
	_update_stun_vfx(u)         # 通用眩晕圈: 眩晕期间头顶火花星绕转(椭圆), 结束即撤
	_update_bamboo_charge_dots(u)   # 竹叶蓄满: 双手两绿点(强化就绪指示)
	_heal_flush(u)   # LoL式治疗累加器: 攒一波回血合并成一个绿字(满血=0)
	if _t < float(u.get("candle_hot_until", 0.0)):   # 蜡烛光圈037: 圈内逐渐回血(HoT)
		_heal(u, float(u.get("candle_hot_rate", 0.0)) * delta, true)
	if _t < float(u.get("rum_until", 0.0)):   # 海盗朗姆酒: 每秒回4%maxHP(分秒HoT·rum_dps=每秒速率)
		_heal(u, float(u.get("rum_dps", 0.0)) * delta, true)
	if not u["alive"]:
		return
	if u.get("_skele_pending", false):                    # 032: 登场召唤亡灵骷髅(首帧)
		u["_skele_pending"] = false
		_eq_summon_skeleton(u, int(u.get("_skele_si", 0)))
	if u.get("_slam", false):   # 火山砸地演出中: 锁AI/移动 (height/pos由slam tween驱动)
		return
	var stunned: bool = _t < u["stun_until"]

	# --- 击飞真物理: vy 受重力, height 积分; 横向同时滑 (XZ 像素坐标方向) ---
	if u["airborne"]:
		u["vy"] += float(u.get("knock_g", GRAVITY)) * delta   # 每次击飞可覆写重力(解耦滞空时长与抛高·如嘲讽砸地 -13.2); 缺省=GRAVITY
		u["height"] += u["vy"] * delta
		# 横向滑行换算回像素 (vx/vz 是米/s → /WS = 像素/s)
		u["pos"].x += u["vx"] / WS * delta
		u["pos"].y += u["vz"] / WS * delta
		u["vx"] *= 0.9; u["vz"] *= 0.9
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		if u["height"] <= 0.0:
			u["height"] = 0.0; u["vy"] = 0.0; u["vx"] = 0.0; u["vz"] = 0.0
			u["airborne"] = false
			u.erase("knock_g")   # 落地 → 清本次击飞的重力覆写(下次默认 GRAVITY)
			# Phase4: 落地 → 压扁回弹 + 小尘 + 轻震屏 (重量感)
			u["land_t"] = JUICE_LAND_SEC
			_shake(JUICE_SHAKE_HEAVY)
			_impact_particles(u["pos"], 0.0)
		return   # 击飞中不移动/不攻击 (覆盖正常行为)

	if u.get("roll_active", false):   # 钻石滚球: 蜷球滚动位移态(免疫定身沉默打断·封板) — 在stun检查前, 覆盖正常AI
		_diamond_roll_tick(u, delta)
		return

	_tick_skill_cd(u, delta)        # 技能冷却(=龟能充能)走时间; ★但眩晕/击飞/风暴期内部直接return→龟能锁定不充(见_tick_skill_cd)
	u["atk_cd"] = maxf(0.0, float(u.get("atk_cd", 0.0)) - delta)   # 普攻冷却也始终走 (漏了它→打一下就再不普攻=用户报的"整个没普攻"; 召唤体也安全)
	if int(u.get("allin_coins", 0)) > 0:
		_fortune_allin_channel(u, delta)
		return   # 财神梭哈投币channel: 锁住(不移动/不普攻)
	var tgt = _acquire_target(u)
	if tgt == null:
		u["_has_target"] = false
		u["_sep_target"] = null
		u["state"] = "move"
		return
	u["_has_target"] = true
	u["_sep_target"] = tgt   # ★近战修: 供 _separation 对"自己的攻击目标"缩小分离半径(否则 SEP_RADIUS92 > 近战射程70 → 永远贴不进射程)
	var _fdx: float = tgt["pos"].x - u["pos"].x   # 朝向跟战斗目标(非移动方向): 交战/风筝/走位都稳定朝敌, 根治近战分离回推"转身"
	if absf(_fdx) > 8.0:                            # 死区: 目标明显在某侧才转向(贴脸x≈时保持上次朝向不抖翻)
		u["face_right"] = _fdx > 0.0
	if stunned:                     # 麻痹: 不移动/不出手 (但冷却已走)
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var dist := to_t.length()
	var rng: float = u["atk_range"]
	var spd: float = u["move_spd"] * (float(u.get("slow_mag", 0.6)) if _t < u["slow_until"] else 1.0) * (float(u.get("spd_move_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0)

	# ═══ AI 状态机: 移动 ↔ 前摇 → 出手 → 后摇 (移动与攻击/施法互斥 = 施法锁; 根治"边走边放") ═══
	match str(u.get("state", "move")):
		"move":
			var rs := _pick_ready_skill(u)
			if dist <= rng and not u.get("no_basic", false) and u["id"] != "phoenix" and u["atk_cd"] <= 0.0:
				u["pending"] = "B"                       # 普攻优先: 在射程且普攻就绪→先普攻, 技能塞进普攻冷却空档(不打断攻击流·用户2026-07-11)
				u["state"] = "windup"
				u["state_t"] = clampf(float(u["atk_interval"]) * ATK_WINDUP_PCT, ATK_WINDUP_MIN, ATK_WINDUP_MAX)
			elif rs != "" and dist <= _skill_cast_range(u, str(rs)):
				# 就绪技放技: 自/友向任意距离; 远程敌向技(如手里剑2000码)够得着就放·不被近战射程卡; 普通敌向技=进攻击射程放(用户2026-07-11)
				u["pending"] = "K:" + rs
				u["state"] = "windup"; u["state_t"] = CAST_WINDUP
				_anticipate(u)
			elif dist <= rng and not u.get("no_basic", false):
				# 进入射程 → 敌向就绪技优先, 否则普攻, 都没好原地待命
				if rs != "":
					u["pending"] = "K:" + rs
					u["state"] = "windup"; u["state_t"] = CAST_WINDUP
					_anticipate(u)                       # 蓄力形变(前摇)
				elif u["id"] == "phoenix":
					_phoenix_flame_channel(u, tgt, delta)               # 凤凰: 持续喷火(VFX+每0.5s伤害)
					if not u["melee"] and dist < rng * 0.7:
						_do_move(u, tgt, dist, rng, spd * 0.5, delta)   # 边喷边走位(kite); 喷火时移速×0.5(寻敌时正常速)(用户)
				elif u["atk_cd"] <= 0.0:
					u["pending"] = "B"
					u["state"] = "windup"
					u["state_t"] = clampf(float(u["atk_interval"]) * ATK_WINDUP_PCT, ATK_WINDUP_MIN, ATK_WINDUP_MAX)   # 前摇=攻击周期30%(随攻速缩放); 出手juice由_basic_attack触发
				elif not u["melee"] and dist < rng * 0.7:
					_do_move(u, tgt, dist, rng, spd, delta)   # 远程风筝
			else:
				_do_move(u, tgt, dist, rng, spd, delta)  # 不在射程 → 移动
		"windup":
			u["state_t"] = float(u["state_t"]) - delta   # 前摇: 站定不动(施法锁)
			if u["state_t"] <= 0.0:
				var p := str(u.get("pending", "B"))
				if p == "B":
					if dist <= rng:
						_basic_attack(u, tgt)
						if u["id"] == "space" and tgt.get("alive", false) and float(u.get("star_energy", 0.0)) > 0.0:   # 星能: 普攻也算施法·附带追加30%储存星能真伤(封板)
							_apply_damage_from(u, tgt, int(u["star_energy"] * 0.30), Color("#ffffff"), 0.0, true)
					# gambler 多重打击(云顶剑士式): 命中后掷概率, 中→快攻速再打, 没中→正常冷却
					var _hf: float = maxf(1.0, float(u.get("haste_mult", 1.0))) if _t < float(u.get("haste_until", 0.0)) else 1.0   # 临时攻速buff(祝福等)
					if u["id"] == "hunter" and tgt != null and tgt.get("alive", false) and float(tgt.get("hp", 0.0)) < float(tgt.get("maxHp", 1.0)) * 0.5:
						_hf *= 1.5   # 猎人残血追猎(封板): 目标<50%生命 → +50%攻速
					u["atk_cd"] = (_gambler_multi_cd(u) if (u["id"] == "gambler" and dist <= rng) else u["atk_interval"]) / maxf(0.1, _hf * (float(u.get("spd_aspd_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0) * float(u.get("aspd_perm", 1.0)))   # ×永久攻速(贝母021等,本场)
					u["state"] = "move"   # LoL忠实: 伤害点后立即自由(可动/被分离=orb walk), 无rooted后摇; 后摇=视觉lunge回收+squash不锁移动; 下次普攻等atk_cd(=1/攻速)
				else:
					var stype := p.substr(2)
					if _cast_skill(u, tgt, stype):
						u["skill_cd"][stype] = _skill_cd(u, stype)
						u["skill_gcd_until"] = _t + SKILL_GCD
						_eq_on_cast(u, tgt)
						if u["id"] == "space" and float(u.get("star_energy", 0.0)) > 0.0:   # 星能: 施法后追加30%储存星能真伤
							_apply_damage_from(u, tgt, int(u["star_energy"] * 0.30), Color("#ffffff"), 0.0, true)
						if u["id"] == "two_head" and stype != "twoHeadFusion":   # 双生: 放完技能一/二→自动切形态+切换攻击+位移
							_two_head_after_cast(u, tgt)
						if u["id"] == "shell":                   # 潜影: 自己放技能→破隐(下次普攻附破隐bonus)
							_shell_break_stealth(u)
					else:
						u["skill_cd"][stype] = _skill_cd(u, stype)
					u["state"] = "recover"; u["state_t"] = CAST_RECOVER
		"recover":
			u["state_t"] = float(u["state_t"]) - delta   # 后摇: 站定不动一小会 → 动作自然
			if u["state_t"] <= 0.0:
				u["state"] = "move"

# 龟能回满 → 放主动 (麻痹时不回, 体现控制价值; 召唤体/被动选项 永不放主动)
# 逐技冷却走时间 (与放招解耦: 放招由状态机在前摇结束时触发, 见 _tick_unit)
func _tick_skill_cd(u: Dictionary, delta: float) -> void:
	if _is_passive_pick(u):
		return
	var cds: Dictionary = u["skill_cd"]
	if cds.is_empty():                                   # 懒初始化: 各技起始冷却
		var _ie: float = float(u.get("init_energy_bonus", 0.0)) * 0.075   # 装备初始龟能→开局减冷却
		for s in u.get("active_skills", []):
			cds[str(s)] = maxf(0.0, _skill_cd(u, str(s)) - _ie)   # 初始龟能: 满冷却 - 初始龟能折算
	if _t < float(u.get("stun_until", 0.0)) or u.get("airborne", false) or _t < float(u.get("storm_until", 0.0)) or _t < float(u.get("energy_lock_until", 0.0)):
		return   # 眩晕/击飞/风暴/显式龟能锁 → 龟能锁定不充(用户)
	if _t < float(u.get("rock_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0:
		return   # 石头岩石护盾: 持盾期锁龟能不充能, 盾破/到期即恢复(用户2026-07-11) → 屏障消失=你就知道盾没了
	var _ecm: float = maxf(1.0, float(u.get("echarge_mult", 1.0))) if _t < float(u.get("echarge_until", 0.0)) else 1.0   # 龟能充能加速buff(祝福等)
	if _t < float(u.get("spd_dbf_until", 0.0)):
		_ecm *= float(u.get("spd_echarge_mult", 1.0))   # 充能减速debuff(寒冰登场等)
	_ecm = maxf(0.05, _ecm)
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta * _ecm * float(u.get("echarge_perm", 1.0)))   # 麻痹也走, 只是放不出; ×充能速率(含装备永久充能速率echarge_perm)
	if float(u.get("energy_bank", 0.0)) > 0.0:   # 龟能银行(贝母021溢出): 冷却能吸就吸(如刚重置), 吸不下继续留着
		_apply_energy_bank(u)

# --- 索敌: 被嘲讽则强制打嘲讽来源, 否则最近敌 (跳过 untargetable / 缩头护身随从) ---
func _acquire_target(u: Dictionary):
	if _t < u["taunt_until"] and u["taunt_by"] != null and u["taunt_by"]["alive"]:
		return u["taunt_by"]
	return _nearest_enemy(u)

func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d := INF
	for o in _units:
		if o["side"] == u["side"] or not o["alive"]:
			continue
		if _t < o["untargetable_until"]:   # 黑洞 → 不可被选
			continue
		if o.get("_egg_fence", false):   # 龟蛋围栏未破 → 不可被主动索敌(但AoE/增益穿栏, 走_enemies_of不受此限)
			continue
		if o.get("hiding_protected", false):   # 缩头随从: 本体存活时不可被敌单体选中
			var ow = o.get("summon_owner", null)
			if ow != null and ow.get("alive", false):
				continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

# 每单位每帧: DoT 落血 / buff 到期清理 / 层数DoT结算 / 召唤体周期特殊技 / 周期被动 (1:1 2D _tick_effects)
func _tick_effects(u: Dictionary, delta: float) -> void:
	# 旧式灼烧 (兼容 burn_until/burn_dps)
	if _t < u["burn_until"] and u["burn_dps"] > 0.0:
		_raw_lose(u, u["burn_dps"] * delta)
		if not u["alive"]:
			return
	# flat DoT 列表 (诅咒等, raw=真伤穿护盾)
	var keep: Array = []
	for dot in u["dots"]:
		if _t < dot["until"]:
			_raw_lose(u, dot["dps"] * delta)
			if not u["alive"]:
				return
			keep.append(dot)
	u["dots"] = keep
	# 层数式 DoT (灼烧/中毒/流血): 每 STACK_DOT_TICK(1秒) 结算一次出伤+衰减
	u["_dottimer"] = u.get("_dottimer", 0.0) + delta
	while u["_dottimer"] >= STACK_DOT_TICK:
		u["_dottimer"] -= STACK_DOT_TICK
		_tick_dot_stacks(u)
	# 灼烧特效(自设计): 燃烧中窜升腾小火苗
	if u["alive"] and int(u.get("dot_stacks", {}).get("burn", 0)) > 0:
		u["burn_vfx_t"] = float(u.get("burn_vfx_t", 0.0)) + delta
		while u["burn_vfx_t"] >= 0.15:
			u["burn_vfx_t"] -= 0.15
			_spawn_burn_ember(u)
	if u["id"] == "phoenix" and u.get("flame_sector", null) != null and is_instance_valid(u.get("flame_sector")) and _t > float(u.get("flame_sector_t", 0.0)):
		u["flame_sector"].visible = false
		if not u["alive"]:
			return
	# buff 到期 → 重算属性
	var changed := false
	var kept_buffs: Array = []
	for b in u["buffs"]:
		if _t < b["until"]:
			kept_buffs.append(b)
		else:
			changed = true
	if changed:
		u["buffs"] = kept_buffs
		_recalc_stats(u)
	# 命运骰子(diceFate): 临时暴击/暴伤增益到期 → 还原 (crit 不走 _recalc_stats, 单独计时)
	if u.get("crit_fate_until", 0.0) > 0.0 and _t >= u["crit_fate_until"]:
		u["crit"] -= u.get("crit_fate_amt", 0.0)
		u["crit_dmg"] -= u.get("crit_dmg_fate_amt", 0.0)
		u["crit_fate_until"] = 0.0; u["crit_fate_amt"] = 0.0; u["crit_dmg_fate_amt"] = 0.0
	# 召唤体周期特殊技 + 自损
	if u.get("is_summon", false):
		_tick_summon_special(u, delta)
		if not u["alive"]:
			return
	# 周期被动 (龟自身计时器)
	_tick_periodic_passive(u, delta)
	# 装备周期 tick (每 2.5 秒, EQ_TICK) — A类回合节拍效果
	if not u.get("equips", []).is_empty():
		_eq_tick(u, delta)
		_tick_doll(u, delta)
		_tick_rustblade(u, delta)
		_tick_sword_storm(u, delta)
		_tick_broadsword(u, delta)
		_tick_laser(u, delta)
		_tick_jelly(u, delta)
		_tick_fortress(u, delta)
		_tick_ironwall(u, delta)
		_tick_shell(u, delta)
		_tick_thunder(u, delta)
		_tick_baton(u, delta)
		_tick_ice_fissure(u, delta)
		_tick_gear(u, delta)
		_tick_eq_intervals(u, delta)
		_tick_anemone(u, delta)
		_tick_dumbbell(u, delta)
		_tick_barnacle(u, delta)

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] != u["side"] and o["alive"]:
			out.append(o)
	return out

func _separation(u: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	# ★近战修: 对"自己的攻击目标"用缩小的分离半径(射程内), 让近战能贴进去开打; 其余单位照常 SEP_RADIUS 散开.
	var mt = u.get("_sep_target", null)
	var mt_valid: bool = bool(u.get("melee", false)) and mt is Dictionary and (mt as Dictionary).get("alive", false)
	var tgt_radius: float = minf(SEP_RADIUS, float(u.get("atk_range", 70.0)) * 0.85)
	for o in _units:
		if o == u or not o["alive"]:
			continue
		var d: Vector2 = u["pos"] - o["pos"]
		var l := d.length()
		var radius: float = SEP_RADIUS
		if mt_valid and is_same(o, mt):
			radius = tgt_radius
		if l > 0.01 and l < radius:
			push += d.normalized() * (1.0 - l / radius)
	return push * 0.9

# ============================================================================
#  普攻 (复用 2D BASIC_ATK 表 + 伤害公式; 远程发 3D 投射物) + 复杂普攻特判 + on-hit 被动
# ============================================================================
# gambler 多重打击(云顶剑士式连击): 普攻命中后掷概率→中则快攻速再打一发(连锁每次概率×0.8递减), 没中→回正常普攻冷却+重置
func _gambler_multi_cd(u: Dictionary) -> float:
	var base_ch: float = float(u.get("multi_base", 0.40))     # 命运之轮选中→0.60; 否则0.40
	if _t < float(u.get("gambler_bet_until", 0.0)):
		base_ch += 0.20                                       # 赌注放技→3秒内临时+20%(封顶示例0.80)
	var ch: float = float(u.get("multi_chance", base_ch))
	if randf() < ch:
		u["multi_chance"] = ch * 0.8                  # 递减: 每次连锁×0.8
		return maxf(0.12, u["atk_interval"] * 0.30)   # 快攻速再打 (~3.3×攻速; F5可调)
	u["multi_chance"] = base_ch                       # 没中→重置回基础(含命运之轮0.60/赌注+0.20), 等下一次普攻
	return u["atk_interval"]

func _eq_on_basic_attack(u: Dictionary, tgt = null) -> void:   # 每普攻(不算多段): 008珊瑚刺计数 / 017不沉之锚普攻消耗充能锚击
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) == "p2eq_017":   # 不沉之锚: 每次普攻消耗1沉锚充能→击飞最前敌+眩晕(用户2026-07-02)
			var ast: Dictionary = u["eq_state"].get("p2eq_017", {})
			if int(ast.get("anchor_charges", 0)) > 0:
				var at = _nearest_enemy(u)
				if at != null:
					var si17: int = _eq_si(int(e.get("star", 1)))
					ast["anchor_charges"] = int(ast["anchor_charges"]) - 1
					var adm: int = int([0.4, 0.6, 3.0][si17] * (u["def"] + u["mr"]) + at["maxHp"] * [0.06, 0.15, 0.70][si17])
					_apply_damage_from(u, at, adm, Color("#9be7ff"), 0.0, false, true)
					_knockback(u, at, 60.0); _freeze(at, CTRL_SEC)
					_skill_ring(at["pos"], Color(0.6, 0.85, 1.0, 0.6), 60.0)
					u["eq_state"]["p2eq_017"] = ast
		if str(e["id"]) == "p2eq_027" and tgt != null and tgt is Dictionary and tgt.get("alive", false):   # 电棍: 就绪→本次普攻消耗1层附魔法伤+眩晕(用户2026-07-03)
			var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
			if bst.get("baton_ready", false) and int(bst.get("baton_charges", 0)) > 0:
				var si27: int = _eq_si(int(e.get("star", 1)))
				bst["baton_charges"] = int(bst["baton_charges"]) - 1
				bst["baton_ready"] = false; bst["baton_cd"] = 0.0
				u["eq_state"]["p2eq_027"] = bst
				_apply_damage_from(u, tgt, _resolve_dmg(u, float([30, 40, 50][si27]), tgt, true), Color("#7ecbff"), 0.0, false, true)
				_freeze(tgt)
				_chain_zap(tgt["pos"])
		if str(e["id"]) != "p2eq_008": continue
		e["coral_cnt"] = int(e.get("coral_cnt", 0)) + 1
		if int(e["coral_cnt"]) >= 5:
			e["coral_cnt"] = 0
			var far = null; var fd := -1.0
			for o in _enemies_of(u):
				var d: float = (o["pos"] - u["pos"]).length_squared()
				if d > fd: fd = d; far = o
			if far != null: _eq_coral_spike(u, far, _eq_si(int(e.get("star", 1))))

func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	_anticipate(u)                  # Phase4: 普攻预备(缩)+挥出(伸) 前后摇形变
	_play_action(u, "attack")       # 有动作帧的龟(basic/ghost/ninja)播普攻动画, 其余靠 juice 形变
	_eq_on_basic_attack(u, tgt)   # 普攻计数装备(008每5次普攻射珊瑚刺, 不算多段)
	if u.get("is_big_bear", false):  # 大熊: 熊掌攒层, 满2层→放冲击波(小菊式)
		_big_bear_attack(u, tgt)
		return
	if u["id"] == "lightning":      # 闪电改造: 一道闪电(魔法)+连锁, 叠层走 _on_basic_hit(满8→雷暴)
		_lightning_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "shell":          # 龟壳改造: 1ATK单段·物/真逐攻交替 + 主目标120px内其他敌溅射50%(同类型)
		_shell_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "chest":          # 宝箱砸击(封板): K'Sante一段Q式·前方短直线AOE·1A物理(近战扫一小片非单体)
		_chest_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "two_head":       # 双头(封板): 普攻随形态 — 远程1.2A物理(灵能弹)/近战0.9A物理(挥砍)
		var _thsc: float = 0.9 if u["melee"] else 1.2
		_emit_basic(u, tgt, _atk_dmg(u, _thsc, tgt), Color("#c0a0ff"), 0)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "cyber":          # 贯穿激光(封板): 1A物理·穿透目标飞到射程尽头·打穿一线所有敌(射程450)
		var _cdir: Vector2 = tgt["pos"] - u["pos"]
		if _cdir.length() < 1.0: _cdir = Vector2.RIGHT
		_cdir = _cdir.normalized()
		for o in _enemies_of(u):
			if o.get("alive", false) and _on_line(u["pos"], _cdir, o["pos"], 55.0):
				_apply_damage_from(u, o, _atk_dmg(u, 1.0, o), Color("#9bf0ff"))
		_bolt_line(u["pos"], u["pos"] + _cdir * 1300.0, Color(0.6, 0.94, 1.0))
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "headless":       # 撕咬(封板): 1A物理 + 3%目标最大生命魔法; 灵魂打击充能满→附0.9A物理+20%当前生命魔法
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#c77dff"))
		if tgt.get("alive", false): _apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.03), Color("#c77dff"))   # 3%maxHp魔法
		if u.get("headless_soul_buff", false):                     # 灵魂打击: 满能→下次普攻附加(单体)
			u["headless_soul_buff"] = false
			if tgt.get("alive", false):
				_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#9b3bff"))
				_apply_damage_from(u, tgt, int(tgt["hp"] * 0.20), Color("#9b3bff"))   # 20%目标当前生命魔法
				_float_text(u["pos"] + Vector2(0, -60), "灵魂打击!", Color("#9b3bff"))
		_on_basic_hit(u, tgt)
		return
	var spec: Dictionary = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	if u["id"] == "lava" and u.get("lava_pierce_next", false):         # 技三·穿透普攻: 下一发熔岩弹变贯穿全场
		u["lava_pierce_next"] = false
		_lava_pierce_bolt(u, tgt); _on_basic_hit(u, tgt)
		return
	if u["id"] == "lava" and u.get("volcano", false):                  # 火山形态: 烈焰重击式平A (单段重击)
		spec = {"magic": 1.6, "hits": 1, "rider": "burn"}
	_do_basic(u, tgt, spec)
	if u["melee"]:
		_on_basic_hit(u, tgt)   # 近战命中即时; 远程→弹道命中时触发(审判等与裁决同帧, 数字按规矩同时跳)
	# (原: 无条件 _on_basic_hit 被动钩子 (竹叶强化/墨迹/结晶/斩杀/审判/多重/彩虹附色 等) — 改 _do_basic 时漏调, 已补

# 数据驱动基础技能: 按 spec 算物/魔/真伤(含加成项)分段打出 + 附带/特殊机制 (1:1 原始 skillPool[0])
func _tick_doll(u: Dictionary, delta: float) -> void:   # 玩偶小熊: 每4s派小熊+攒层; 满层→蓄力→召大熊(不与末只小熊同帧)
	var es: Dictionary = u.get("eq_state", {})
	if not es.has("p2eq_034"): return
	var stt: Dictionary = es["p2eq_034"]
	if bool(stt.get("bear_done", false)) or bool(stt.get("bear_charging", false)): return
	var si: int = int(stt.get("doll_si", 0))
	var _iv: float = 1.0 if OS.has_environment("EQDEMO_FAST") else 4.0   # FAST=快速看波
	stt["doll_t"] = float(stt.get("doll_t", 0.0)) + delta
	if float(stt["doll_t"]) < _iv: return
	stt["doll_t"] = 0.0
	var mt = _nearest_enemy(u)
	if mt == null: return
	var bdm: int = _atk_dmg(u, [1.0, 2.0, 5.0][si], mt) + [100, 210, 1000][si]
	_summon_walking_bear(u, mt, bdm)
	stt["bear_layers"] = int(stt.get("bear_layers", 0)) + 1
	var _cap: int = 1 if OS.has_environment("EQDEMO_FAST") else [5, 3, 1][si]
	if int(stt["bear_layers"]) >= _cap:
		stt["bear_charging"] = true
		_big_bear_charge_and_spawn(u, si)

func _big_bear_charge_and_spawn(u: Dictionary, si: int) -> void:   # 满层: 携带者蓄力(金光聚1.2s)→召大熊(与末只小熊错开)
	var glow := Sprite3D.new()
	glow.texture = _make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
	glow.modulate = Color(1.0, 0.82, 0.4, 0.0); glow.pixel_size = 0.02
	glow.position = _world_pos(u["pos"], 1.2)
	_world.add_child(glow)
	_float_text(u["pos"] + Vector2(0, -70), "大熊蓄力...", Color("#ffd166"))
	for k in range(7):   # 蓄力: 金块从脚下环绕依次破土冒起(聚土成熊)
		var ca: float = float(k) * TAU / 7.0
		var ctw := _reg_tween()
		ctw.tween_interval(float(k) * 0.14)
		ctw.tween_callback(_gold_chunk_erupt.bind(u["pos"] + Vector2(cos(ca), sin(ca)) * randf_range(40.0, 62.0)))
	var gt := _reg_tween()
	gt.tween_property(glow, "modulate:a", 0.95, 1.0)
	gt.parallel().tween_property(glow, "scale", Vector3(3.2, 3.2, 3.2), 1.2)
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(self): return
	if is_instance_valid(glow): glow.queue_free()
	var stt: Dictionary = u.get("eq_state", {}).get("p2eq_034", {})
	stt["bear_done"] = true
	var bear = _spawn_summon(u, "bear", [650.0, 1100.0, 10000.0][si], [70.0, 120.0, 2000.0][si], {"label": "大熊", "spr_id": "doll-bear", "col_size": 48.0, "hp_w": 36.0, "melee": true, "atk_interval": 2.0, "atk_range": 70.0})
	if bear != null:
		bear["eq_state"] = {}; bear["equips"] = []
		bear["base_def"] = 20.0; bear["def"] = 20.0; bear["base_mr"] = 20.0; bear["mr"] = 20.0
		bear["is_big_bear"] = true; bear["bear_stacks"] = 0; bear["bear_star"] = si
		if OS.has_environment("EQDEMO_FAST"): bear["atk_interval"] = 0.6   # FAST=快速攒层看波
	_skill_ring(u["pos"], Color(1.0, 0.82, 0.4, 0.6), 90.0); _shake(JUICE_SHAKE_BIG)

func _bear_claw_fx(pos2d: Vector2) -> void:   # 熊爪拍击命中: 三道金爪痕(斜)一闪 + 尘爆, 卖出拍击感
	_impact_particles(pos2d, 0.3)
	for k in range(3):
		var off: Vector2 = Vector2(float(k - 1) * 15.0, float(k - 1) * -6.0)   # 三痕平行错开
		var a: Vector2 = pos2d + off + Vector2(-22.0, 16.0)
		var b: Vector2 = pos2d + off + Vector2(22.0, -16.0)
		var im := MeshInstance3D.new()
		var imesh := ImmediateMesh.new(); im.mesh = imesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		imesh.surface_set_color(Color(1.0, 0.92, 0.55, 0.95)); imesh.surface_add_vertex(_world_pos(a, 1.0))
		imesh.surface_set_color(Color(1.0, 0.8, 0.35, 0.2)); imesh.surface_add_vertex(_world_pos(b, 1.0))
		imesh.surface_end()
		_world.add_child(im)
		var tw := _reg_tween()
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
		tw.tween_callback(im.queue_free)

func _set_bear_sheet(spr: Sprite3D, kind: String) -> void:   # 换大熊动画帧表(走路/拍击/砸地; 每帧96px, hframes按宽度算)
	var path := "res://assets/sprites/vfx/bear-walk.png"
	if kind == "attack": path = "res://assets/sprites/vfx/bear-attack.png"
	elif kind == "slam": path = "res://assets/sprites/vfx/bear-slam.png"
	var tex: Texture2D = load(path)
	if tex == null: return
	spr.texture = tex
	spr.hframes = maxi(1, int(round(float(tex.get_width()) / 96.0)))
	spr.frame = 0

func _tick_bear_anim(u: Dictionary, delta: float) -> void:   # 大熊状态机: 移动→走路循环 / 停下→顿住 / 拍击→熊爪 / 冲击波→举手砸地
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr): return
	var ne = _nearest_enemy(u)                     # 朝向最近敌(熊默认朝左→敌在右则flip朝右; 迟滞防抖)
	if ne != null and absf(float(ne["pos"].x) - float(u["pos"].x)) > 40.0:
		spr.flip_h = float(ne["pos"].x) > float(u["pos"].x)
	u["bear_anim_t"] = float(u.get("bear_anim_t", 0.0)) + delta
	var anim := str(u.get("bear_anim", "walk"))
	var voff := Vector3.ZERO
	var ldir: Vector3 = u.get("_bear_ldir", Vector3.ZERO)
	if anim == "attack" or anim == "slam":
		if str(u.get("_bear_sheet", "")) != anim:
			_set_bear_sheet(spr, anim); u["_bear_sheet"] = anim; u["bear_anim_t"] = 0.0
		var per: float = 0.07 if anim == "attack" else 0.085
		var total: float = per * float(maxi(1, int(spr.hframes)))
		var prog: float = clampf(float(u["bear_anim_t"]) / maxf(0.01, total), 0.0, 1.0)
		var f: int = int(float(u["bear_anim_t"]) / per)
		if f >= int(spr.hframes):
			if u.get("_slam_manual", false):
				spr.frame = int(spr.hframes) - 1   # 手控砸地: 定住末帧(等波传完, 不回走路循环=修漂移)
			else:
				u["bear_anim"] = "walk"          # 播完回走路/待机
		else:
			spr.frame = f
		if anim == "attack":
			voff = ldir * (sin(prog * PI) * 0.55)          # 前扑扑击(前冲再回)
			voff.y += sin(prog * PI) * 0.14                # 略抬(挥爪)
		# slam 的位移由 _bear_shockwave 手控(_slam_manual), 这里只推进帧
	else:   # walk / idle: 移动→循环走路, 停下→站立顿住(frame0)
		if str(u.get("_bear_sheet", "")) != "walk":
			_set_bear_sheet(spr, "walk"); u["_bear_sheet"] = "walk"
		var pv: Vector2 = u.get("_bear_pp", u["pos"])
		var moving: bool = (u["pos"] - pv).length() > 0.6
		u["_bear_pp"] = u["pos"]
		if moving:
			spr.frame = int(float(u["bear_anim_t"]) * 9.0) % maxi(1, int(spr.hframes))
		else:
			spr.frame = 0
	if not u.get("_slam_manual", false):   # 砸地手控voff期间不覆盖
		u["_bear_voff"] = voff

func _big_bear_attack(u: Dictionary, tgt: Dictionary) -> void:   # 大熊: <2层→熊掌(前摇抬爪→挥击命中跳数字→后摇收手); 满2层→放冲击波
	var si: int = int(u.get("bear_star", 0))
	var d2: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	u["_bear_ldir"] = (_world_pos(u["pos"] + d2 * 10.0, 0.0) - _world_pos(u["pos"], 0.0)).normalized()   # 扑击/砸地世界朝向
	if int(u.get("bear_stacks", 0)) >= 2:
		_bear_shockwave(u, tgt, si)
		u["bear_stacks"] = 0
		u["atk_range"] = 70.0                       # 冲击波后回近战射程
	else:
		u["bear_anim"] = "attack"; u["bear_anim_t"] = 0.0   # 前摇抬爪→挥击→后摇收手(voff驱动)
		var total: float = 0.07 * 7.0
		var tw := _reg_tween()
		tw.tween_interval(total * 0.45)             # 命中延到挥击接触帧(非攻击一开始)
		tw.tween_callback(_bear_paw_hit.bind(u, tgt))
		u["bear_stacks"] = int(u.get("bear_stacks", 0)) + 1
		if int(u["bear_stacks"]) >= 2:
			u["atk_range"] = 600.0                   # 下次冲击波: 射程600码(进程即放,不贴脸)

func _bear_paw_hit(u: Dictionary, tgt) -> void:   # 熊掌挥击接触瞬间: 此刻才伤害+跳数字+金爪痕
	if not u.get("alive", false) or tgt == null or not tgt.get("alive", false): return
	_do_basic(u, tgt, {"phys": 1.0, "hits": 1})  # 熊掌: 1×ATK 物理
	if u.get("melee", false): _on_basic_hit(u, tgt)
	_bear_claw_fx(tgt["pos"])                    # 金爪三痕+尘

func _tick_fortress(u: Dictionary, delta: float) -> void:   # 深海堡垒甲p2eq_014: 硬化满20层后每8秒汲取全体敌(魔伤0.8/1.0/1.5×(护甲+魔抗))+每敌回血; 满层瞬间立即首次; 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_014": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_014", {})
		if int(stt.get("harden_stacks", 0)) < 20:
			e["fortress_t"] = 8.0   # 未叠满→预置8(叠满瞬间立即首次汲取)
			continue
		e["fortress_t"] = float(e.get("fortress_t", 0.0)) + delta
		if float(e["fortress_t"]) < 8.0: continue
		e["fortress_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		var k2: float = [0.8, 1.0, 1.5][si]
		for o in _enemies_of(u):
			_bolt_line(o["pos"], u["pos"], Color("#bfe9ff"))
			_apply_damage_from(u, o, int(k2 * (u["def"] + u["mr"])), Color("#bfe9ff"), 0.0, true, true)
			_heal(u, [40, 65, 130][si])

func _tick_ironwall(u: Dictionary, delta: float) -> void:   # 铁壁盾p2eq_016: 每5秒为全队(含自己)护盾15/20/25(用户2026-07-02, 原走2.5s周期); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_016": continue
		e["ironwall_t"] = float(e.get("ironwall_t", 0.0)) + delta
		if float(e["ironwall_t"]) < 5.0: continue
		e["ironwall_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		for o in _allies_of(u):
			_grant_shield(o, [15.0, 20.0, 25.0][si])

func _tick_thunder(u: Dictionary, delta: float) -> void:   # 雷鸣贝壳p2eq_025: 每4秒降N道大雷(道间错峰0.3s), 各劈随机敌1×ATK真伤(伤害在闪电中段跳); 每件独立(用户2026-07-02: 原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_025": continue
		e["thunder_t"] = float(e.get("thunder_t", 0.0)) + delta
		if float(e["thunder_t"]) < 4.0: continue
		e["thunder_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		for d in range([1, 2, 3][si]):                # 道间错峰
			var tw := _reg_tween()
			tw.tween_interval(float(d) * 0.3)
			tw.tween_callback(_thunder_bolt.bind(u))

func _thunder_bolt(u: Dictionary) -> void:
	if not u.get("alive", false): return
	var es := _enemies_of(u)
	if es.is_empty(): return
	var o = es[randi() % es.size()]
	_lightning_strike(o["pos"], Color("#8fd4ff"), 4.6)   # 大雷(中心≈2.2=飘字高度)
	var tw := _reg_tween()                             # 伤害在闪电动画中段(~0.25s)跳=落在雷中间
	tw.tween_interval(0.25)
	tw.tween_callback(_thunder_hit.bind(u, o))

func _thunder_hit(u: Dictionary, o: Dictionary) -> void:
	if not (u.get("alive", false) and o.get("alive", false)): return
	_apply_damage_from(u, o, int(u["atk"]), Color("#cfefff"), 0.0, true, true)   # 1×ATK真实伤害(白字,飘在2.2=雷中间)

# 029 冰封水母(布隆大招式): 每12秒→自身上盾→砸地→朝最近敌生成冰道(500x90)→命中魔法伤+击飞0.6s+冰封2.5s
func _tick_ice_fissure(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_029": continue
		e["fissure_t"] = float(e.get("fissure_t", 0.0)) + delta
		if float(e["fissure_t"]) < 12.0: continue
		e["fissure_t"] = 0.0
		_eq_ice_fissure(u, _eq_si(int(e.get("star", 1))))

func _eq_ice_fissure(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	_grant_shield(u, [100.0, 160.0, 250.0][si])   # 释放即上盾一次
	_shield_bubble(u)
	var t = _nearest_enemy(u)
	if t == null:
		return
	var dir: Vector2 = (t["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_anticipate(u)                                 # 蓄力砸地
	var tw := _reg_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(_ice_fissure_go.bind(u, si, u["pos"], dir))

func _ice_fissure_go(u: Dictionary, si: int, start: Vector2, dir: Vector2) -> void:
	_shake(0.14)
	_ice_burst(start)                              # 砸地冰爆
	var reach: float = 500.0
	var width: float = 90.0
	var fdur: float = 0.9
	_ice_fissure_vfx(start, dir, reach, fdur)      # 冰道: 一排冰刺racing forward
	for o in _enemies_of(u):
		var along: float = (o["pos"] - start).dot(dir)
		if along < 0.0 or along > reach:
			continue
		if not _on_line(start, dir, o["pos"], width):
			continue
		var d: float = clampf(along / reach, 0.0, 1.0) * fdur
		var tw := _reg_tween()
		tw.tween_interval(d)                       # 冰道推进到该敌才结算
		tw.tween_callback(_ice_fissure_hit.bind(u, o, si))

func _ice_fissure_hit(u: Dictionary, o: Dictionary, si: int) -> void:
	if not o.get("alive", false):
		return
	_apply_damage_from(u, o, _resolve_dmg(u, float([25, 40, 60][si]), o, true), Color("#bfe9ff"), 0.0, false, true)   # 魔法伤
	if not o.get("airborne", false):
		o["airborne"] = true; o["vy"] = 6.6; o["vx"] = 0.0; o["vz"] = 0.0   # 竖直击飞~0.6s(2*6.6/22)
	var fz: float = [1.0, 1.8, 2.5][si]   # freeze dur per star (user 2026-07-03)
	_freeze(o, fz)
	_frozen_encase(o, fz)                         # 冰封特效持续fzs
	_ice_burst(o["pos"])

func _ice_fissure_vfx(start: Vector2, dir: Vector2, reach: float, fdur: float) -> void:
	# 布隆式: 地面裂开→冰脊/冰墙密排erupt(中脊高两侧矮)+平铺冰原+寒雾; 留存~2.8s后按生成序从头到尾消退
	var perp: Vector2 = dir.orthogonal()
	var field_life: float = 2.8
	var field := load("res://assets/sprites/vfx/ice-field.png")
	var n: int = 26                                          # 密排冰刺=连成冰墙(非稀疏一排)
	for i in range(1, n + 1):
		var f: float = float(i) / float(n)
		var lat: float = randf_range(-46.0, 46.0)
		var hs: float = lerpf(1.4, 0.68, absf(lat) / 46.0) * randf_range(0.82, 1.15)   # 中脊高两侧矮
		var pos: Vector2 = start + dir * (reach * f) + perp * lat
		var tw := _reg_tween()
		tw.tween_interval(f * fdur)
		tw.tween_callback(_spawn_ice_spike.bind(pos, hs, field_life))
	var m: int = 13
	for i in range(1, m + 1):
		var f: float = float(i) / float(m)
		var pos: Vector2 = start + dir * (reach * f)
		var tf := _reg_tween()
		tf.tween_interval(f * fdur)
		tf.tween_callback(_ice_field_patch.bind(field, pos, dir, field_life))
		var tm := _reg_tween()
		tm.tween_interval(f * fdur)
		tm.tween_callback(_frost_mist.bind(pos + perp * randf_range(-42.0, 42.0)))

func _spawn_ice_spike(pos2d: Vector2, hscale: float, linger: float) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-spike-vfx.png")
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(1, 1, 1, 0)
	spr.pixel_size = (1.7 * hscale) / float(maxi(1, int(tex.get_height())))
	var world_h: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = _world_pos(pos2d, world_h * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.6, 0.0)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 0.95, 0.1)
	tw.chain().tween_interval(linger)                        # 冰墙留存
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.35)  # 按生成序消退(前面先erupt→先消退)
	tw.chain().tween_callback(spr.queue_free)

func _spawn_bamboo_spike(pos2d: Vector2, hscale: float, linger: float) -> void:   # 竹刺破土冒起(绿·仿 _spawn_ice_spike)
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-spike-vfx.png")
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.28, 0.82, 0.34, 0.0)   # 竹绿(起始透明)
	spr.pixel_size = (1.9 * hscale) / float(maxi(1, int(tex.get_height())))
	var world_h: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = _world_pos(pos2d, world_h * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.6, 0.0)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 0.95, 0.09)
	tw.chain().tween_interval(linger)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(spr.queue_free)

func _ice_field_patch(tex: Texture2D, pos2d: Vector2, dir: Vector2, life: float) -> void:
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.axis = Vector3.AXIS_Y                                # 躺平贴地=冰原
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.72, 0.88, 1.0, 0.0)
	spr.rotation.y = -atan2(dir.y, dir.x)
	spr.pixel_size = (155.0 * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(pos2d, 0.04)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_property(spr, "modulate:a", 0.55, 0.12)
	tw.tween_interval(life)
	tw.tween_property(spr, "modulate:a", 0.0, 0.4)
	tw.tween_callback(spr.queue_free)

func _frost_mist(pos2d: Vector2) -> void:
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.72, 0.9, 1.0, 0.5)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(55.0, 92.0) * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(pos2d, 0.5)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", _world_pos(pos2d, 1.15), 0.7)
	tw.tween_property(spr, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(spr.queue_free)


# ============================================================================
#  迷你水晶球 030/031 (可视叠层+引爆) + 亡灵骷髅 032 + 复活海螺变形 033
# ============================================================================

# 水晶碎片火花: 弹出+缓旋+淡出 (光束/引爆/扫射点缀)
# 030 单段水晶光束结算: 从携带者当前位置沿 dir 无限直线, 全线敌魔法伤+1层水晶
func _crystal_line_seg(u: Dictionary, si: int, dir: Vector2) -> void:
	if not u.get("alive", false): return
	var origin: Vector2 = u["pos"]
	_crystal_beam(origin, origin + dir * 1500.0, Color("#c9b0ff"))
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if _on_line(origin, dir, o["pos"], 55.0):
			_apply_damage_from(u, o, _resolve_dmg(u, float([30, 35, 40][si]), o, true), Color("#bfa8ff"), 0.0, false, true)
			_eq_crystal_stack(u, o, si)

func _crystal_spark(pos2d: Vector2, h: float = 0.9) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (26.0 * WS) / float(maxi(1, int(tex.get_height())))
	spr.position = _world_pos(pos2d, h)
	spr.modulate = Color(1, 1, 1, 0)
	spr.rotation.z = randf_range(-0.4, 0.4)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_property(spr, "modulate:a", 1.0, 0.07)
	tw.tween_interval(0.1)
	tw.tween_property(spr, "modulate:a", 0.0, 0.28)
	tw.tween_callback(spr.queue_free)
	var tw2 := _reg_tween()
	tw2.tween_property(spr, "rotation:z", spr.rotation.z + 0.8, 0.45)

# 水晶光束: 亮白核 + 紫辉 + 沿线水晶碎片 (030 直线用)
func _crystal_beam(a2d: Vector2, b2d: Vector2, col: Color) -> void:
	_bolt_line(a2d, b2d, Color(1.0, 0.95, 1.0, 0.95))
	_bolt_line(a2d, b2d, col)
	var n: int = clampi(int((b2d - a2d).length() / 60.0), 1, 20)
	for i in range(1, n + 1):
		_crystal_spark(a2d.lerp(b2d, float(i) / float(n + 1)))

# 可视水晶叠层: 敌身周围绕 n 颗水晶碎片 (n=当前层数, 0=清除)
func _crystal_stack_set(o: Dictionary, n: int) -> void:
	var arr: Array = o.get("_xtal_shards", [])
	while arr.size() > n:
		var s = arr.pop_back()
		if is_instance_valid(s):
			_unfollow_vfx(s)
			s.queue_free()
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	while arr.size() < n and tex != null:
		var idx: int = arr.size()
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.pixel_size = (22.0 * WS) / float(maxi(1, int(tex.get_height())))
		spr.modulate = Color(1, 1, 1, 0)
		_world.add_child(spr)
		_follow_vfx.append({"spr": spr, "unit": o, "h": 1.5, "orbit_r": 0.34, "orbit_a": float(idx) * TAU / 3.0, "orbit_spd": 2.6})
		var tw := _reg_tween()
		tw.tween_property(spr, "modulate:a", 0.95, 0.15)
		arr.append(spr)
	o["_xtal_shards"] = arr

func _unfollow_vfx(spr) -> void:
	for i in range(_follow_vfx.size() - 1, -1, -1):
		if _follow_vfx[i].get("spr", null) == spr:
			_follow_vfx.remove_at(i)

# 水晶引爆: 紫辉爆闪 + 环 + 碎片四射
func _crystal_detonate(pos2d: Vector2) -> void:
	_shake(0.1)                                              # 引爆=大事件, 加大震屏
	_skill_ring(pos2d, Color(0.9, 0.72, 1.0, 0.88), 26.0)   # 内爆环
	_skill_ring(pos2d, Color(0.68, 0.5, 1.0, 0.45), 74.0)   # 冲击波外环
	var glow := _make_fire_glow_tex()
	# 中心白紫爆闪(更亮更大)
	var fl := Sprite3D.new()
	fl.texture = glow
	fl.modulate = Color(0.96, 0.86, 1.0, 0.98)
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.transparent = true
	fl.pixel_size = (34.0 * WS) / float(maxi(1, glow.get_width()))
	fl.position = _world_pos(pos2d, 0.9)
	_world.add_child(fl)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "pixel_size", (130.0 * WS) / float(maxi(1, glow.get_width())), 0.28)
	tw.tween_property(fl, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(fl.queue_free)
	# 碎晶四射(11片环形爆开)
	for k in range(11):
		var a: float = k * TAU / 11.0 + randf_range(-0.2, 0.2)
		_crystal_spark(pos2d + Vector2(cos(a), sin(a)) * randf_range(22.0, 58.0))

# 031: 水晶射线360度扫一圈(1.5s), 射线扫到敌人即结算魔法伤+叠层
func _eq_crystal_sweep(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var center: Vector2 = u["pos"]
	var reach: float = 1000.0
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # 加色发光(水晶能量)
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.set_meta("mat", mat)
	_world.add_child(im)
	var start_a: float = randf() * TAU
	var state: Dictionary = {"prev": start_a}
	_crystal_spark(center, 1.1)
	var tw := _reg_tween()
	# 先慢后快再慢(ease-in-out): 匀速被否, 甩动有加速度
	tw.tween_method(_crystal_sweep_step.bind(u, si, reach, state, im, imesh, mat), start_a, start_a + TAU, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(im.queue_free)

func _crystal_sweep_step(ang: float, u: Dictionary, si: int, reach: float, state: Dictionary, im: MeshInstance3D, imesh: ImmediateMesh, mat: StandardMaterial3D) -> void:
	if not is_instance_valid(im): return
	var center: Vector2 = u["pos"]   # 跟随携带者当前位置(非施法点定死)
	var col := Color("#c9b0ff")
	var dir2: Vector2 = Vector2(cos(ang), sin(ang))
	var perp: Vector2 = dir2.orthogonal()
	var tip2: Vector2 = center + dir2 * reach
	imesh.clear_surfaces()
	# 水晶射线本体: 根部宽→尖端细的发光光束(加色), 是"一道会转的射线"非扇面
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var cb := Color(col.r, col.g, col.b, 0.5)    # 根部亮
	var ct := Color(col.r, col.g, col.b, 0.06)   # 尖端淡
	var vA: Vector3 = _world_pos(center + perp * 8.0, 1.0)
	var vB: Vector3 = _world_pos(center - perp * 8.0, 1.0)
	var vD: Vector3 = _world_pos(tip2 + perp * 2.5, 1.0)
	var vE: Vector3 = _world_pos(tip2 - perp * 2.5, 1.0)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vA)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vB)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vD)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vB)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vE)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vD)
	imesh.surface_end()
	# 亮白核线(脆生生一道射线中轴)
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imesh.surface_set_color(Color(1, 0.97, 1, 1.0)); imesh.surface_add_vertex(_world_pos(center, 1.0))
	imesh.surface_set_color(Color(col.r, col.g, col.b, 0.22)); imesh.surface_add_vertex(_world_pos(tip2, 1.0))
	imesh.surface_end()
	# 沿射线拖水晶碎片(节流每3步)
	state["spk"] = int(state.get("spk", 0)) + 1
	if int(state["spk"]) % 3 == 0:
		_crystal_spark(center + dir2 * (reach * 0.4))
	if u.get("alive", false):        # 携带者死亡后仅转完视觉, 不再从尸体结算伤害
		var prev: float = float(state["prev"])
		for o in _enemies_of(u):
			if not o.get("alive", false): continue
			var ea: float = atan2(float(o["pos"].y) - center.y, float(o["pos"].x) - center.x)
			if _ang_in(prev, ang, ea):
				_apply_damage_from(u, o, _resolve_dmg(u, float([60, 130, 700][si]), o, true), Color("#bfa8ff"), 0.0, false, true)
				var steal: float = maxf(0.0, float(o["mr"])) * [0.10, 0.15, 0.50][si]   # 偷取目标10/15/50%当前魔抗(真偷取:目标-X携带者+X, 永久到战场结束)
				if steal > 0.01:
					o["base_mr"] = float(o["base_mr"]) - steal; o["mr"] = float(o["mr"]) - steal
					u["base_mr"] = float(u["base_mr"]) + steal; u["mr"] = float(u["mr"]) + steal
					var samt: int = int(round(steal))
					if samt >= 1:
						_float_text(o["pos"] + Vector2(randf_range(-10.0, 10.0), -46.0), "魔抗-%d" % samt, Color("#c9b0ff"))
				_eq_crystal_stack(u, o, si)
				_crystal_spark(o["pos"])
	state["prev"] = ang

func _ang_in(prev: float, cur: float, t: float) -> bool:
	while t < prev:
		t += TAU
	return t > prev and t <= cur

# 032: 登场召唤亡灵骷髅 (双抗20000近乎免疫, 存活15s自灭, 死亡200码内%最大生命真伤)
func _eq_summon_skeleton(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var sk = _spawn_summon(u, "skeleton", [19.0, 21.0, 25.0][si] * HP_MULT, [3.0, 5.0, 8.0][si], {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / 1.2, "atk_range": 70.0, "melee": true, "move_spd": 130.0})
	if sk == null: return
	sk["base_def"] = 20000.0; sk["base_mr"] = 20000.0; sk["def"] = 20000.0; sk["mr"] = 20000.0
	sk["summon_life"] = 15.0
	sk["boom_pct_true"] = [0.08, 0.13, 0.20][si]
	sk["boom_radius"] = 200.0
	_skill_ring(sk["pos"], Color(0.4, 1.0, 0.55, 0.6), 40.0)
	for k in range(5):
		_bone_speck(sk["pos"] + Vector2(randf_range(-24, 24), randf_range(-24, 24)))
	if is_instance_valid(sk["sprite"]):
		var base_sc: Vector3 = sk["sprite"].scale
		sk["sprite"].scale = Vector3(base_sc.x, 0.05, base_sc.z)
		var tw := _reg_tween()
		tw.tween_property(sk["sprite"], "scale", base_sc, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# 亡灵爆: 绿冲击环 + 绿辉爆闪 + 骨渣四射 (骷髅自灭/被杀 + 海螺变形共用基元)
func _necro_burst(pos2d: Vector2, radius: float) -> void:
	_skill_ring(pos2d, Color(0.4, 1.0, 0.55, 0.7), radius * 0.55)
	_shake(0.08)
	var glow := _make_fire_glow_tex()
	var fl := Sprite3D.new()
	fl.texture = glow
	fl.modulate = Color(0.45, 1.0, 0.55, 0.8)
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.transparent = true
	fl.pixel_size = (50.0 * WS) / float(maxi(1, glow.get_width()))
	fl.position = _world_pos(pos2d, 0.8)
	_world.add_child(fl)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "pixel_size", (radius * 1.3 * WS) / float(maxi(1, glow.get_width())), 0.32)
	tw.tween_property(fl, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(fl.queue_free)
	for k in range(7):
		var a := k * TAU / 7.0
		_bone_speck(pos2d + Vector2(cos(a), sin(a)) * randf_range(25.0, radius * 0.5))

func _bone_speck(pos2d: Vector2) -> void:
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.85, 1.0, 0.8, 0.9)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(10.0, 18.0) * WS) / float(maxi(1, tex.get_width()))
	spr.position = _world_pos(pos2d, 0.4)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", _world_pos(pos2d, 1.0), 0.42)
	tw.tween_property(spr, "modulate:a", 0.0, 0.42)
	tw.chain().tween_callback(spr.queue_free)

# 033: 海螺阵亡→变小虫 变形演出 (青绿亡灵光爆 + 骨渣)
func _conch_transform(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(0.4, 1.0, 0.7, 0.7), 46.0)
	_shake(0.06)
	var glow := _make_fire_glow_tex()
	var col := Sprite3D.new()
	col.texture = glow
	col.modulate = Color(0.4, 1.0, 0.7, 0.85)
	col.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	col.shaded = false
	col.transparent = true
	col.pixel_size = (55.0 * WS) / float(maxi(1, glow.get_width()))
	col.position = _world_pos(pos2d, 0.7)
	_world.add_child(col)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(col, "position", _world_pos(pos2d, 1.5), 0.45)
	tw.tween_property(col, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(col.queue_free)
	for k in range(6):
		_bone_speck(pos2d + Vector2(randf_range(-30, 30), randf_range(-30, 30)))

const _EQ_CUSTOM_IV := {"p2eq_037": 5.0, "p2eq_038": 6.0, "p2eq_040": 6.0, "p2eq_042": 8.0, "p2eq_052": 4.0}
func _tick_eq_intervals(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		var iid: String = str(e["id"])
		var iv: float = float(_EQ_CUSTOM_IV.get(iid, 0.0))
		if iv <= 0.0: continue
		var si: int = _eq_si(int(e.get("star", 1)))
		if iid == "p2eq_037": _ensure_candle(u)   # 蜡烛从开局就悬在头顶(不等首次tick)
		var stt: Dictionary = u["eq_state"].get(iid, {})
		stt["iv_t"] = float(stt.get("iv_t", 0.0)) + delta
		if float(stt["iv_t"]) >= iv:
			stt["iv_t"] = float(stt["iv_t"]) - iv
			match iid:
				"p2eq_037": _eq_candle_tick(u, si, stt)
				"p2eq_038": _eq_signal_tick(u, si)
				"p2eq_040": _eq_fpga_tick(u, si)
				"p2eq_042": _eq_ripple_tick(u, si)
				"p2eq_052": _eq_revolver_tick(u, si, stt)
		u["eq_state"][iid] = stt

# 涟漪回血特效(AI生成动画): 青绿涟漪水波躺平贴地, 帧播一次扩散淡出. 用于涟漪药剂042每个受益友军
func _ripple_heal_vfx(pos2d: Vector2, size_px: float) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/ripple-heal-anim.png")
	var fh: int = maxi(1, tex.get_height())
	var nf: int = maxi(1, int(tex.get_width() / fh))
	var r := Sprite3D.new()
	r.texture = tex
	r.hframes = nf
	r.frame = 0
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y
	r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	r.shaded = false; r.transparent = true
	r.modulate = Color(1, 1, 1, 0.95)
	r.position = _world_pos(pos2d, 0.06)
	r.pixel_size = (size_px * 2.0 * WS) / float(fh)
	_world.add_child(r)
	var tw := _reg_tween(); tw.set_parallel(true)
	if nf > 1:
		tw.tween_property(r, "frame", nf - 1, 0.55)
	tw.tween_property(r, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.queue_free)

func _eq_ripple_tick(u: Dictionary, si: int) -> void:
	var low042 = null; var lv042 := INF
	if si == 2:
		for o in _allies_of(u):
			var p042: float = o["hp"] / maxf(1.0, o["maxHp"])
			if p042 < lv042: lv042 = p042; low042 = o
	for o in _allies_of(u):
		var pct042: float = [0.03, 0.06, 0.10][si]
		if si == 2 and o == low042: pct042 *= 2.0
		var amt42: float = (o["maxHp"] - o["hp"]) * pct042
		if amt42 >= 1.0:
			_heal(o, amt42)
			_ripple_heal_vfx(o["pos"], 105.0)   # AI生成涟漪回血动画

func _eq_revolver_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	if int(stt.get("revolver_bullets", 0)) > 0:
		var es3 := _enemies_of(u)
		if not es3.is_empty():
			stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
			var o = es3[randi() % es3.size()]
			_muzzle_flash(u["pos"], (o["pos"] - u["pos"]), Color("#ffe08a"))
			_spawn_eq_bolt(u, o, _atk_dmg(u, [3.0, 5.0, 9.0][si], o) + [150, 310, 1200][si], "res://assets/sprites/vfx/bullet.png", Color("#ffe6a8"), false, 0, 0.034)   # 左轮重弹(真子弹, 大一号)

# 蛋糕蜡烛037: 头顶悬浮真蜡烛精灵(带火苗辉光), 随相位 熄灭/微弱/燃烧 亮暗变化; 持续存在直到携带者死
func _ensure_candle(u: Dictionary) -> void:
	var ex = u.get("_candle_spr", null)
	if ex != null and is_instance_valid(ex): return
	var c := Sprite3D.new()
	if ResourceLoader.exists("res://assets/sprites/vfx/candle-flame.png"):
		var tx: Texture2D = load("res://assets/sprites/vfx/candle-flame.png")
		c.texture = tx
		c.hframes = maxi(1, int(round(float(tx.get_width()) / 64.0)))
		u["_candle_frames"] = c.hframes
	else:
		c.texture = load("res://assets/sprites/vfx/candle-lit.png")
		u["_candle_frames"] = 1
	c.pixel_size = 1.25 / 96.0
	c.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	c.shaded = false; c.transparent = true
	_world.add_child(c)
	u["_candle_spr"] = c
	_follow_vfx.append({"spr": c, "unit": u, "h": 3.05})
	if int(u["_candle_frames"]) > 1:   # 火苗帧表: 循环播放(蜡烛自带跳动火苗)
		var at := _reg_tween().bind_node(c).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
		at.tween_property(c, "frame", int(u["_candle_frames"]) - 1, 0.45).from(0)

func _eq_candle_tick(u: Dictionary, si: int, stt: Dictionary) -> void:
	_ensure_candle(u)
	var c = u.get("_candle_spr", null)
	var ph: int = int(stt.get("candle", 0))
	stt["candle"] = (ph + 1) % 3
	if ph == 0:   # 熄灭: 蜡烛变暗(火苗弱下去, 无效果)
		if c != null and is_instance_valid(c):
			_reg_tween().tween_property(c, "modulate", Color(0.5, 0.5, 0.58, 1.0), 0.35)
	elif ph == 1:   # 微弱: 蜡烛点亮 + 250码光圈 + 圈内友军5s逐渐回血
		if c != null and is_instance_valid(c):
			_reg_tween().tween_property(c, "modulate", Color(1, 1, 1, 1), 0.35)
		var hv37: float = [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si]
		_heal_circle_vfx(u["pos"], 250.0, 5.0)   # AI生成回血阵动画
		u["candle_hot_rate"] = hv37 / 5.0
		u["candle_hot_until"] = _t + 5.0
		for a37 in _allies_of(u, false):
			if a37["pos"].distance_to(u["pos"]) <= 250.0:
				a37["candle_hot_rate"] = (hv37 * 0.5) / 5.0
				a37["candle_hot_until"] = _t + 5.0
	elif ph == 2:   # 燃烧: 火苗爆燃(蜡烛过亮+弹一下) + 原地爆炸, 499码内敌各受魔法伤+灼烧
		if c != null and is_instance_valid(c):
			var ct := _reg_tween(); ct.set_parallel(true)
			ct.tween_property(c, "modulate", Color(1.4, 1.15, 0.85, 1.0), 0.12)
			ct.tween_property(c, "scale", Vector3.ONE * 1.3, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			ct.chain().tween_property(c, "scale", Vector3.ONE, 0.25)
		_boom_wave(u["pos"], 260.0)   # AI生成爆炸波动画(原地大爆炸)
		_shake(0.06)
		var dmg37: float = float([20, 30, 44][si]) + u["atk"] * [0.5, 0.7, 1.0][si]
		for o in _enemies_of(u):
			if o["pos"].distance_to(u["pos"]) <= 499.0:
				_apply_damage_from(u, o, _resolve_dmg(u, dmg37, o, true), Color("#ffb066"), 0.0, false, true)   # 魔法伤(蓝字), 非真伤
				_apply_dot_stacks(o, "burn", [20, 30, 40][si], u)
				_boom_wave(o["pos"], 110.0)   # 每个被波及敌小爆

# 蜡烛光圈(037微弱): 250码暖金贴地光环, 缓慢淡出标示回血区
func _candle_circle(pos2d: Vector2, radius_px: float, dur: float) -> void:
	var r := Sprite3D.new()
	r.texture = _make_ring_texture(Color(1.0, 0.85, 0.5, 1.0))
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y
	r.shaded = false; r.transparent = true
	r.modulate = Color(1.0, 0.82, 0.45, 0.0)
	r.position = _world_pos(pos2d, 0.05)
	r.pixel_size = (radius_px * 2.0 * WS) / 96.0
	_world.add_child(r)
	var tw := _reg_tween()
	tw.tween_property(r, "modulate:a", 0.55, 0.4)
	tw.tween_property(r, "modulate:a", 0.12, dur * 0.6)
	tw.tween_property(r, "modulate:a", 0.0, dur * 0.4)
	tw.tween_callback(r.queue_free)

# 回血阵(AI生成动画): 绿金魔法治疗阵躺平贴地, 帧循环脉动, 淡入维持淡出. 用于蜡烛微弱/大回复
func _heal_circle_vfx(pos2d: Vector2, radius_px: float, dur: float) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/heal-circle-anim.png")
	var fh: int = maxi(1, tex.get_height())
	var nf: int = maxi(1, int(tex.get_width() / fh))
	var r := Sprite3D.new()
	r.texture = tex
	r.hframes = nf
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y
	r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	r.shaded = false; r.transparent = true
	r.modulate = Color(1, 1, 1, 0)
	r.position = _world_pos(pos2d, 0.06)
	r.pixel_size = (radius_px * 2.0 * WS) / float(fh)
	_world.add_child(r)
	if nf > 1:
		var at := _reg_tween().bind_node(r).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
		at.tween_property(r, "frame", nf - 1, 0.5).from(0)
	var tw := _reg_tween()
	tw.tween_property(r, "modulate:a", 0.95, 0.4)
	tw.tween_property(r, "modulate:a", 0.55, dur * 0.6)
	tw.tween_property(r, "modulate:a", 0.0, dur * 0.4)
	tw.tween_callback(r.queue_free)

# 爆炸波(AI生成动画): 卡通爆炸帧表播一次, billboard, 抖屏. size_px=爆炸直径
func _boom_wave(pos2d: Vector2, size_px: float, h: float = 0.8) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/boom-wave-anim.png")
	var fh: int = maxi(1, tex.get_height())
	var nf: int = maxi(1, int(tex.get_width() / fh))
	var b := Sprite3D.new()
	b.texture = tex
	b.hframes = nf
	b.frame = 0
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.shaded = false; b.transparent = true
	b.pixel_size = (size_px * WS) / float(fh)
	b.position = _world_pos(pos2d, h)
	_world.add_child(b)
	var tw := _reg_tween()
	if nf > 1:
		tw.tween_property(b, "frame", nf - 1, 0.36)
	else:
		tw.tween_interval(0.36)
	tw.tween_callback(b.queue_free)

func _eq_signal_tick(u: Dictionary, si: int) -> void:
	var lo: Array = [0.10, 0.25, 0.70]; var hi: Array = [0.16, 0.40, 0.80]
	var amp: float = randf_range(lo[si], hi[si])
	var found38 := false
	for b in u["buffs"]:
		if str(b.get("tag", "")) == "signal":
			b["amount"] = maxf(float(b["amount"]), amp); b["until"] = _t + 3.5; found38 = true; amp = float(b["amount"]); break
	if not found38:
		u["buffs"].append({"stat": "atk", "amount": amp, "pct": true, "until": _t + 3.5, "tag": "signal"})
	_recalc_stats(u)
	_signal_pulse(u["pos"])
	_float_text(u["pos"] + Vector2(0, -58), "增伤+%d%%" % int(amp * 100.0), Color("#ffcf5a"))

# 信号脉冲(038): 头顶弹出青蓝 signal-wave 广播图标(升起放大淡出, 2个错峰=脉冲广播) + 脚下青光环
func _signal_pulse(pos2d: Vector2) -> void:
	var sw_tex: Texture2D = load("res://assets/sprites/vfx/signal-wave.png")
	for k in range(2):
		var sw := Sprite3D.new()
		sw.texture = sw_tex
		sw.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sw.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sw.shaded = false; sw.transparent = true
		sw.modulate = Color(1, 1, 1, 0.95)
		sw.pixel_size = 0.8 / 96.0
		sw.position = _world_pos(pos2d, 2.45)
		_world.add_child(sw)
		var d: float = float(k) * 0.16
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(sw, "position", _world_pos(pos2d, 3.35), 0.6).set_delay(d).set_ease(Tween.EASE_OUT)
		tw.tween_property(sw, "pixel_size", 1.7 / 96.0, 0.6).set_delay(d).set_ease(Tween.EASE_OUT)
		tw.tween_property(sw, "modulate:a", 0.0, 0.6).set_delay(d).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(sw.queue_free)
	# 脚下青蓝广播环(与图标呼应)
	var rg := Sprite3D.new()
	rg.texture = _make_ring_texture(Color(0.35, 0.85, 1.0, 1.0))
	rg.billboard = BaseMaterial3D.BILLBOARD_DISABLED; rg.axis = Vector3.AXIS_Y
	rg.shaded = false; rg.transparent = true
	rg.modulate = Color(0.4, 0.88, 1.0, 0.85)
	rg.position = _world_pos(pos2d, 0.06)
	rg.pixel_size = 0.01
	_world.add_child(rg)
	var tw2 := _reg_tween(); tw2.set_parallel(true)
	tw2.tween_property(rg, "pixel_size", 0.055, 0.5).set_ease(Tween.EASE_OUT)
	tw2.tween_property(rg, "modulate:a", 0.0, 0.5)
	tw2.chain().tween_callback(rg.queue_free)

func _eq_fpga_tick(u: Dictionary, si: int) -> void:
	_skill_ring(u["pos"], Color(0.4, 0.9, 1.0, 0.42), 46.0)
	var codes := ["00", "01", "10", "11"]
	var ccols := [Color("#7ad0ff"), Color("#a0ff8a"), Color("#ffd05a"), Color("#ff8ad0")]
	var n: int = [1, 2, 4][si]
	for k in range(n):
		var pick: int = randi() % 4
		var xoff: float = (float(k) - float(n - 1) / 2.0) * 34.0
		_float_text(u["pos"] + Vector2(xoff, -72.0), codes[pick], ccols[pick])   # 二进制码头顶跳
		match pick:
			0: _heal(u, u["maxHp"] * 0.05); u["base_def"] += 2; u["base_mr"] += 2; _recalc_stats(u)
			1: u["base_atk"] += 5; u["lifesteal"] += 0.04; _recalc_stats(u)
			2: _buff(u, "atk", 0.15, true, 3.5)
			3: _buff(u, "def", 0.25, true, 3.5)


func _tick_gear(u: Dictionary, delta: float) -> void:   # 黄铜齿轮035: 每6秒+1/2/3齿轮层(战斗结束结算折币, 死亡不销毁)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_035": continue
		var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_035", {})
		stt["gear_t"] = float(stt.get("gear_t", 0.0)) + delta
		if float(stt["gear_t"]) >= 6.0:
			stt["gear_t"] = float(stt["gear_t"]) - 6.0
			stt["gears"] = int(stt.get("gears", 0)) + [1, 2, 3][si]
		u["eq_state"]["p2eq_035"] = stt

func _tick_shell(u: Dictionary, delta: float) -> void:   # 守护贝壳p2eq_018: 每8秒自回(30/45/60+5/9/15%maxHP)生命(受治疗增幅); 每件独立(用户2026-07-02, 原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_018": continue
		e["shell_t"] = float(e.get("shell_t", 0.0)) + delta
		if float(e["shell_t"]) < 8.0: continue
		e["shell_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		_heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])

func _tick_anemone(u: Dictionary, delta: float) -> void:   # 海葵药膏p2eq_019: 每7秒奶自己+最低血友军(30/45/60+12/14/18%目标已损血)×海葵增幅; 累计200/180/150治疗+1海葵层(治疗&盾强度+8/9/10%/层); 每件独立(用户2026-07-02,原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_019": continue
		e["anemone_t"] = float(e.get("anemone_t", 0.0)) + delta
		if float(e["anemone_t"]) < 7.0: continue
		e["anemone_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_019", {})
		var amp19: float = 1.0 + float(int(stt.get("anemone_layers", 0))) * [0.08, 0.09, 0.10][si]
		var h1: float = ([30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si]) * amp19
		_heal(u, h1)
		var prov19: float = h1
		var low = _lowest_hp_ally(u)
		if low != null and low != u:
			var h2: float = ([30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si]) * amp19
			_heal(low, h2); prov19 += h2
		stt["anemone_heal"] = float(stt.get("anemone_heal", 0.0)) + prov19
		var thr19: float = [200.0, 180.0, 150.0][si]
		while float(stt["anemone_heal"]) >= thr19:
			stt["anemone_heal"] = float(stt["anemone_heal"]) - thr19
			stt["anemone_layers"] = int(stt.get("anemone_layers", 0)) + 1
			_skill_ring(u["pos"], Color(0.55, 0.9, 0.7, 0.5), 44.0)
		u["eq_state"]["p2eq_019"] = stt

func _tick_dumbbell(u: Dictionary, delta: float) -> void:   # 哑铃p2eq_020: 每10秒一套(原地锻炼锁攻锁充能→+锻炼层→蓄力掷哑铃击退); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_020": continue
		e["dumbbell_t"] = float(e.get("dumbbell_t", 0.0)) + delta
		if float(e["dumbbell_t"]) < 10.0: continue
		e["dumbbell_t"] = 0.0
		if u.get("_slam", false): continue   # 正在别的channel中→跳过本次
		_eq_dumbbell_routine(u, _eq_si(int(e.get("star", 1))))

func _eq_dumbbell_routine(u: Dictionary, si: int) -> void:   # 原地锻炼(锁攻+锁充能)→+锻炼层(maxHp,局内每场重置)→蓄力→掷哑铃击退
	if not u.get("alive", false): return
	u["_slam"] = true   # 锁AI/普攻/移动/龟能充能(都在_tick_unit早返回前)
	for _b in range(3):   # 锻炼动作: 3下蹲起形变
		if not u.get("alive", false): u["_slam"] = false; return
		_anticipate(u)
		await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self): return
	var stt: Dictionary = u["eq_state"].get("p2eq_020", {})   # 锻炼层(eq_state局内计数, 每场战斗重置)
	stt["exercise"] = int(stt.get("exercise", 0)) + 1
	u["eq_state"]["p2eq_020"] = stt
	var gain: float = [20.0, 25.0, 30.0][si] * HP_MULT
	u["maxHp"] += gain; u["hp"] += gain
	_skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.42), 48.0)   # 锻炼强化光
	_anticipate(u); _shake(JUICE_SHAKE_HEAVY)   # 蓄力
	await get_tree().create_timer(0.35).timeout
	u["_slam"] = false
	if not u.get("alive", false): return
	var t = _nearest_enemy(u)
	if t == null: return
	var dmg: int = maxi(1, int(u["maxHp"] / HP_MULT * [0.05, 0.07, 0.10][si]))
	_throw_dumbbell(u, t, dmg)

func _throw_dumbbell(u: Dictionary, tgt: Dictionary, dmg: int) -> void:   # 钢灰哑铃飞向目标→砸中伤害+击退
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/sprites/equip/dungeon-dumbbell.png")   # 真哑铃图(020图标)作弹道
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素感
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; spr.shaded = false; spr.transparent = true
	spr.pixel_size = (48.0 * WS) / float(maxi(1, spr.texture.get_width()))   # 场地约48px宽
	spr.position = _world_pos(u["pos"], 1.1)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_property(spr, "position", _world_pos(tgt["pos"], 1.0), 0.3)
	tw.tween_callback(_dumbbell_hit.bind(spr, u, tgt, dmg))

func _dumbbell_hit(spr: Sprite3D, u: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if is_instance_valid(spr): spr.queue_free()
	if not tgt.get("alive", false): return
	_apply_damage_from(u, tgt, dmg, Color("#c8ccd6"), 0.0, false, true)
	_knockback(u, tgt, 0.0, 1.0, 2.0)   # 砸中击退
	_skill_ring(tgt["pos"], Color(0.8, 0.82, 0.9, 0.6), 50.0); _shake(JUICE_SHAKE_HEAVY)

func _eq_fuel_throw(u: Dictionary, si: int) -> void:   # 余烬燃油瓶022: 施法后短蓄力→投掷火瓶到最近敌→命中施灼烧层+真火5秒
	if not u.get("alive", false): return
	if _nearest_enemy(u) == null: return
	_anticipate(u)   # 短蓄力
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self) or not u.get("alive", false): return
	var t = _nearest_enemy(u)
	if t == null: return
	var spr := Sprite3D.new()
	spr.texture = _make_fire_glow_tex()
	spr.modulate = Color(1.0, 0.62, 0.22); spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; spr.shaded = false; spr.transparent = true
	spr.pixel_size = 0.02
	spr.position = _world_pos(u["pos"], 1.15)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_property(spr, "position", _world_pos(t["pos"], 1.0), 0.32)
	tw.tween_callback(_fuel_bottle_hit.bind(spr, u, t, si))

func _fuel_bottle_hit(spr: Sprite3D, u: Dictionary, t: Dictionary, si: int) -> void:
	if is_instance_valid(spr): spr.queue_free()
	if not t.get("alive", false): return
	_apply_damage_from(u, t, [40, 60, 100][si], Color("#ff7a3c"), 0.0, true, true)   # 火瓶直接火伤(命中即出伤+同帧跳数字, 照028同费档)
	var tf: int = maxi(1, roundi([20, 35, 60][si] + [0.10, 0.15, 0.20][si] * u["atk"]))
	_apply_dot_stacks(t, "burn", tf, u)
	t["true_fire_until"] = _t + 5.0
	_skill_ring(t["pos"], Color(1.0, 0.5, 0.15, 0.6), 56.0); _particle_burst(t["pos"])   # 火瓶碎裂+点燃火环

# 027 电棍: 每3s就绪→下次普攻消耗1层(附魔法伤+眩晕); 就绪时身上冒电光
func _tick_baton(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_027": continue
		var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
		if int(bst.get("baton_charges", 0)) <= 0:
			bst["baton_ready"] = false; u["eq_state"]["p2eq_027"] = bst; continue
		if not bst.get("baton_ready", false):
			bst["baton_cd"] = float(bst.get("baton_cd", 0.0)) + delta
			if float(bst["baton_cd"]) >= 3.0:
				bst["baton_ready"] = true
		else:
			bst["baton_spark_t"] = float(bst.get("baton_spark_t", 0.0)) + delta
			if float(bst["baton_spark_t"]) >= 0.16:
				bst["baton_spark_t"] = 0.0
				_baton_spark(u)
		u["eq_state"]["p2eq_027"] = bst

func _baton_spark(u: Dictionary) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/electric-zap.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = randi() % 5
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(0.6, 0.9, 1.0, 0.85)
	var fw: float = float(maxi(1, int(tex.get_width()))) / 5.0
	spr.pixel_size = (42.0 * WS) / fw
	spr.position = _world_pos(u["pos"] + Vector2(randf_range(-14.0, 14.0), randf_range(-12.0, 12.0)), randf_range(0.45, 1.1))
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_property(spr, "modulate:a", 0.0, 0.2)
	t.tween_callback(spr.queue_free)

# 028 冰霜冻露瓶: 蓄力→抛物线缓慢扔冰瓶→砸敌魔法伤+冰寒+冰爆
func _eq_ice_throw(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	if _nearest_enemy(u) == null: return
	_anticipate(u)
	var tw := _reg_tween()
	tw.tween_interval(0.32)
	tw.tween_callback(_ice_throw_go.bind(u, si))

func _ice_throw_go(u: Dictionary, si: int) -> void:
	if not u.get("alive", false): return
	var t = _nearest_enemy(u)
	if t == null: return
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-bottle.png")
	var spr := Sprite3D.new()
	if tex != null:
		spr.texture = tex
		spr.pixel_size = (46.0 * WS) / float(maxi(1, int(tex.get_width())))
	else:
		spr.texture = _make_fire_glow_tex()
		spr.modulate = Color(0.6, 0.85, 1.0)
		spr.pixel_size = 0.02
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var from2d: Vector2 = u["pos"]
	spr.position = _world_pos(from2d, 1.1)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_method(_ice_bottle_arc.bind(spr, from2d, t["pos"]), 0.0, 1.0, 0.6)
	tw.tween_callback(_ice_bottle_hit.bind(spr, u, t, si))

func _ice_bottle_arc(pf: float, spr: Sprite3D, from2d: Vector2, to2d: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = _world_pos(from2d.lerp(to2d, pf), 1.0 + sin(pf * PI) * 2.4)

func _ice_bottle_hit(spr: Sprite3D, u: Dictionary, t: Dictionary, si: int) -> void:
	if is_instance_valid(spr): spr.queue_free()
	if not t.get("alive", false): return
	_apply_damage_from(u, t, _resolve_dmg(u, float([40, 60, 100][si]), t, true), Color("#bfe9ff"), 0.0, false, true)
	t["spd_move_mult"] = 0.8; t["spd_aspd_mult"] = 0.9; t["spd_dbf_until"] = _t + 5.0
	_ice_burst(t["pos"])
	_frost_puff(t["pos"])
	_shake(0.06)
	_knockback(u, t, 16.0)
	_skill_ring(t["pos"], Color(0.7, 0.9, 1.0, 0.55), 62.0)

func _ice_burst(pos2d: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/ice-shatter.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.no_depth_test = true
	var fw: float = float(maxi(1, int(tex.get_width()))) / 5.0
	spr.pixel_size = (115.0 * WS) / fw
	spr.position = _world_pos(pos2d, 0.95)
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_method(_zap_frame.bind(spr), 0.0, 5.0, 0.34)
	t.tween_callback(spr.queue_free)

func _frost_puff(pos2d: Vector2) -> void:
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.62, 0.82, 1.0, 0.5)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (78.0 * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(pos2d, 0.72)
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_interval(0.35)
	t.tween_property(spr, "modulate:a", 0.0, 0.5)
	t.tween_callback(spr.queue_free)

# 029 冰封水母: 冰封目标 + 护盾泡
func _frozen_encase(o: Dictionary, dur: float = 1.5) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/frozen-encase.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (112.0 * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(o["pos"], float(o.get("height", 0.0)) + 0.78)
	spr.modulate = Color(1, 1, 1, 0)
	_world.add_child(spr)
	_follow_vfx.append({"spr": spr, "unit": o, "h": 0.78})   # 冰块跟着目标走(含击飞抬升)
	var t := _reg_tween()
	t.tween_property(spr, "modulate:a", 0.96, 0.1)
	t.tween_interval(maxf(0.1, dur - 0.35))
	t.tween_property(spr, "modulate:a", 0.0, 0.25)
	t.tween_callback(spr.queue_free)

func _shield_bubble(u: Dictionary) -> void:
	var tex := _make_fire_glow_tex()
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(0.55, 0.82, 1.0, 0.55)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (55.0 * WS) / tw_w
	spr.position = _world_pos(u["pos"], 0.7)
	_world.add_child(spr)
	var t := _reg_tween()
	t.set_parallel(true)
	t.tween_property(spr, "pixel_size", (105.0 * WS) / tw_w, 0.35)
	t.tween_property(spr, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(spr.queue_free)

# 石头岩石护盾: 持盾期间常驻 LoL Barrier 式金色六棱护罩(跟随单位), 盾破/到期→碎裂淡出.
# 每帧从 _tick_unit 调; 靠 rock_shield_until + shield>0 判活(与锁龟能同一判据).
func _update_shield_barrier(u: Dictionary) -> void:
	var active: bool = _t < float(u.get("rock_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0
	var spr = u.get("_barrier_spr", null)
	var valid: bool = spr != null and is_instance_valid(spr)
	if active and not valid:
		var b := Sprite3D.new()
		b.texture = load("res://assets/sprites/vfx/fx-hex-bubble.png")
		b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.shaded = false; b.transparent = true
		b.modulate = Color(1.0, 0.86, 0.34, 0.5)                    # LoL Barrier 金色六棱护罩
		var tw := float(maxi(1, int(b.texture.get_width())))
		b.pixel_size = (150.0 * WS) / tw
		b.position = _world_pos(u["pos"], float(u.get("height", 0.0)) + 0.75)
		_world.add_child(b)
		var pt := create_tween().bind_node(b).set_loops()           # 呼吸脉动(绑节点→节点free自停)
		pt.tween_property(b, "modulate:a", 0.30, 0.55).set_trans(Tween.TRANS_SINE)
		pt.tween_property(b, "modulate:a", 0.52, 0.55).set_trans(Tween.TRANS_SINE)
		_follow_vfx.append({"spr": b, "unit": u, "h": 0.75})
		u["_barrier_spr"] = b
		u["_barrier_pulse"] = pt
	elif not active and valid:
		u["_barrier_spr"] = null
		var pulse = u.get("_barrier_pulse", null)                   # 先杀脉动循环(否则和淡出抢 modulate:a)
		if pulse != null and is_instance_valid(pulse): pulse.kill()
		u["_barrier_pulse"] = null
		var s2 = spr
		var bt := create_tween(); bt.set_parallel(true)             # 盾没了→护罩碎裂放大淡出(你就"知道盾消失了")
		bt.tween_property(s2, "modulate:a", 0.0, 0.2)
		bt.tween_property(s2, "pixel_size", s2.pixel_size * 1.35, 0.2)
		bt.chain().tween_callback(s2.queue_free)

var _star_tex_cache: ImageTexture = null
func _make_star_texture() -> ImageTexture:   # 4尖火花星(眩晕圈用·黄白·中心亮+四轴尖); 缓存
	if _star_tex_cache != null:
		return _star_tex_cache
	var N := 48
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var dx: float = float(x) - c
			var dy: float = float(y) - c
			var ax: float = absf(dx) / c
			var ay: float = absf(dy) / c
			var r: float = sqrt(dx * dx + dy * dy) / c
			var hspk: float = maxf(0.0, 1.0 - ay / 0.18) * maxf(0.0, 1.0 - ax)   # 水平尖
			var vspk: float = maxf(0.0, 1.0 - ax / 0.18) * maxf(0.0, 1.0 - ay)   # 垂直尖
			var core: float = maxf(0.0, 1.0 - r * 2.6)                            # 中心亮核
			var a: float = clampf(maxf(core, maxf(hspk, vspk)), 0.0, 1.0)
			if a <= 0.02: continue
			img.set_pixel(x, y, Color(1.0, 0.94, 0.5, a))
	_star_tex_cache = ImageTexture.create_from_image(img)
	return _star_tex_cache

# 通用眩晕圈: 单位眩晕期间头顶 3 颗火花星水平绕转(镜头俯角自然渲成椭圆); 眩晕结束/死亡即撤.
# 每帧从 _tick_unit 调, 门=_t<stun_until → 任何来源的眩晕都自动带这圈(用户2026-07-11「做个眩晕通用特效」).
func _update_stun_vfx(u: Dictionary) -> void:
	var active: bool = _t < float(u.get("stun_until", 0.0))
	var arr: Array = u.get("_stun_spr", [])
	var have: bool = not arr.is_empty() and is_instance_valid(arr[0])
	if active and not have:
		var tex := _make_star_texture()
		var tw := float(maxi(1, int(tex.get_width())))
		var stars: Array = []
		var n := 3
		for i in range(n):
			var s := Sprite3D.new()
			s.texture = tex
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false; s.transparent = true
			s.modulate = Color(1.0, 0.95, 0.55, 0.96)
			s.pixel_size = (34.0 * WS) / tw
			s.position = _world_pos(u["pos"], float(u.get("height", 0.0)) + 1.6)
			_world.add_child(s)
			_follow_vfx.append({"spr": s, "unit": u, "h": 1.6, "orbit_r": 0.34, "orbit_a": float(i) * TAU / float(n), "orbit_spd": 5.2})
			stars.append(s)
		u["_stun_spr"] = stars
	elif not active and have:
		for s in arr:
			if is_instance_valid(s):
				var ss = s
				var t := _reg_tween()
				t.tween_property(ss, "modulate:a", 0.0, 0.14)
				t.chain().tween_callback(ss.queue_free)
		u["_stun_spr"] = []

# 竹叶·蓄满强化指示: bamboo_charge 期间双手各一个绿点(跟随·放出即散). 每帧 _tick_unit 调.
func _update_bamboo_charge_dots(u: Dictionary) -> void:
	var active: bool = u["id"] == "bamboo" and u.get("bamboo_charge", false)
	var arr: Array = u.get("_bamboo_dots", [])
	var have: bool = not arr.is_empty() and is_instance_valid(arr[0])
	if active and not have:
		var tex := _make_glow_texture()
		var tw := float(maxi(1, int(tex.get_width())))
		var dots: Array = []
		for a in [0.0, PI]:   # 右手(+X) / 左手(-X) 两侧, orbit_spd=0=固定横偏
			var s := Sprite3D.new()
			s.texture = tex
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.shaded = false; s.transparent = true
			s.modulate = Color(0.45, 1.0, 0.5, 0.95)   # 绿点
			s.pixel_size = (24.0 * WS) / tw
			s.position = _world_pos(u["pos"], float(u.get("height", 0.0)) + 0.55)
			_world.add_child(s)
			_follow_vfx.append({"spr": s, "unit": u, "h": 0.55, "orbit_r": 0.26, "orbit_a": a, "orbit_spd": 0.0})
			dots.append(s)
		u["_bamboo_dots"] = dots
	elif not active and have:
		for s in arr:
			if is_instance_valid(s):
				var ss = s
				var t := _reg_tween(); t.set_parallel(true)
				t.tween_property(ss, "modulate:a", 0.0, 0.12)                  # 放出→散
				t.tween_property(ss, "pixel_size", ss.pixel_size * 1.9, 0.12)
				t.chain().tween_callback(ss.queue_free)
		u["_bamboo_dots"] = []

# 竹叶强化命中: 敌人身上爆一下大淡绿命中特效(≈上半身大小·一下即散·用户2026-07-11).
func _bamboo_hit_splash(tgt: Dictionary) -> void:
	var tex := _make_glow_texture()
	var tw := float(maxi(1, int(tex.get_width())))
	var big: float = (170.0 * WS) / tw          # "很大"≈上半身大小(可调)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(0.6, 1.0, 0.62, 0.0)    # 淡绿
	sp.pixel_size = big * 0.55
	sp.position = _world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.5)
	_world.add_child(sp)
	var t := _reg_tween(); t.set_parallel(true)
	t.tween_property(sp, "pixel_size", big, 0.09).set_ease(Tween.EASE_OUT)   # 爆开
	t.tween_property(sp, "modulate:a", 0.9, 0.05)
	t.chain().tween_property(sp, "modulate:a", 0.0, 0.2)                     # 即散
	t.chain().tween_callback(sp.queue_free)

# 全局: 被减速单位行走留短暂泥印(棕色泥渍, 贴地)
func _mud_mark(pos2d: Vector2) -> void:
	var spr := Sprite3D.new()
	spr.texture = _make_disc_texture()
	spr.modulate = Color(0.28, 0.2, 0.11, 0.62)
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.axis = Vector3.AXIS_Y
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(42.0, 58.0) * WS) / 96.0
	spr.position = _world_pos(pos2d + Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 8.0)), 0.03)
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_interval(0.6)
	t.tween_property(spr, "modulate:a", 0.0, 0.5)
	t.tween_callback(spr.queue_free)


func _tick_barnacle(u: Dictionary, delta: float) -> void:   # 守护贝母p2eq_021: 持续绿色绑定线连全队最高攻友军; 每5秒重连并为自己+该友军 +10龟能+10%攻速(叠加/本场/每场重置); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_021": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_021", {})
		e["barnacle_t"] = float(e.get("barnacle_t", 0.0)) + delta
		if stt.get("link_target", null) == null or float(e["barnacle_t"]) >= 5.0:   # 首次立即连 + 每5秒重连+给buff
			if float(e["barnacle_t"]) >= 5.0: e["barnacle_t"] = 0.0
			var si: int = _eq_si(int(e.get("star", 1)))
			var prev = stt.get("link_target", null)   # 重连前清上个连接对象的伤害转移标记
			if prev is Dictionary: prev.erase("dmg_redirect_to")
			var best = null; var ba := -1.0
			for o in _allies_of(u):
				if o == u: continue
				if float(o["atk"]) > ba: ba = float(o["atk"]); best = o
			stt["link_target"] = best
			u["eq_state"]["p2eq_021"] = stt
			var benef: Array = [u]
			if best != null: benef.append(best)
			for o in benef:
				if _has_energy_system(o): _eq_grant_energy(o, 10.0)   # +10龟能(减冷却)
				o["aspd_perm"] = float(o.get("aspd_perm", 1.0)) + 0.10   # +10%攻速(永久本场,叠加)
				_skill_ring(o["pos"], Color(0.55, 1.0, 0.78, 0.5), 44.0)
			if best != null:   # 连接友军: 盾 + 伤害转移(25/40/60%受伤转给携带者); 不净化(用户)
				_grant_shield(best, [40.0, 60.0, 90.0][si])
				best["dmg_redirect_to"] = {"carrier": u, "pct": [0.25, 0.40, 0.60][si], "until": _t + 5.5}
		_update_barnacle_line(u, stt.get("link_target", null))   # 每帧: 持续绿色绑定线(跟随移动/能量脉动)
		break   # 只处理一件(共享绑定线)

func _update_barnacle_line(u: Dictionary, target) -> void:   # 守护贝母021: 携带者↔连接友军的持续绿色绑定线(每帧重绘跟随, 能量脉动α)
	var im = u.get("barnacle_line", null)
	if not (target is Dictionary) or not target.get("alive", false) or target == u or not u.get("alive", false):
		if is_instance_valid(im): im.visible = false
		return
	if not is_instance_valid(im):
		im = MeshInstance3D.new()
		im.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true   # 绑定线画在最上层(不被龟立绘遮挡)
		mat.vertex_color_use_as_albedo = true   # 顶点色驱动(照可显的_bolt_line)
		im.material_override = mat
		_world.add_child(im)
		u["barnacle_line"] = im
	im.visible = true
	var imesh: ImmediateMesh = im.mesh
	var col := Color(0.5, 1.0, 0.7, 0.82 + 0.18 * sin(_t * 6.0))   # 能量脉动
	var a := _world_pos(u["pos"], 2.05)
	var b := _world_pos(target["pos"], 2.05)
	var d: Vector3 = b - a
	if d.length() < 0.01: return
	var perp: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * 0.11   # 飘带横向半宽
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, im.material_override)   # 绑定飘带(5平行线, 用能显的LINES)
	var pu: Vector3 = perp.normalized()
	for _off in [-0.1, -0.05, 0.0, 0.05, 0.1]:   # 5条平行绿线=粗绑定飘带(用能显的PRIMITIVE_LINES)
		imesh.surface_set_color(col); imesh.surface_add_vertex(a + pu * _off)
		imesh.surface_set_color(col); imesh.surface_add_vertex(b + pu * _off)
	imesh.surface_end()

func _tick_jelly(u: Dictionary, delta: float) -> void:   # 龟苓膏块p2eq_012: 每4s自护盾(用户2026-07-02, 原走2.5s周期); 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_012": continue
		e["jelly_t"] = float(e.get("jelly_t", 0.0)) + delta
		if float(e["jelly_t"]) < 4.0: continue
		e["jelly_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		_grant_shield(u, [30.0, 40.0, 55.0][si])

func _tick_rustblade(u: Dictionary, delta: float) -> void:   # 锈蚀短剑p2eq_001: 每3s就绪, 射程(=携带者射程)内有敌即斜砍; 每件独立(多件各自触发)
	if u.get("equips", []).is_empty(): return
	var t = null; var got := false; var rng: float = float(u.get("atk_range", 70.0))
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_001": continue
		e["rust_t"] = float(e.get("rust_t", 0.0)) + delta   # 计时存装备条目→每副本独立就绪
		if float(e["rust_t"]) < 3.0: continue               # 该件未就绪(每3s就绪一次)
		if not got:                                          # 目标懒求(多件共用同一最近敌)
			t = _nearest_enemy(u); got = true
		if t == null or (t["pos"] - u["pos"]).length() > rng: continue   # 射程内无敌→保持就绪等待
		e["rust_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		_weapon_slash(u["pos"], t["pos"], Color("#ffd27a"))
		_apply_damage_from(u, t, _atk_dmg(u, [0.6, 0.75, 1.0][si], t) + int([40, 60, 100][si] * u["crit"]), Color("#ff4444"), 0.0, false, true)

func _make_slash_texture(col: Color) -> ImageTexture:   # 斜劈斩弧: 一段新月弧(左上→右下), 亮核软边
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(S) * 0.5; var cy := float(S) * 0.5
	var R := float(S) * 0.42; var thick := float(S) * 0.1
	for y in range(S):
		for x in range(S):
			var dx := float(x) - cx; var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - R) > thick: continue
			var a := atan2(dy, dx)                       # 只画一段弧 (斜劈: -150°→30°, 左上→右下)
			if a < deg_to_rad(-150.0) or a > deg_to_rad(30.0): continue
			var edge := 1.0 - absf(d - R) / thick
			var taper := sin(PI * clampf((a - deg_to_rad(-150.0)) / deg_to_rad(180.0), 0.0, 1.0))   # 两端尖
			var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.4, 0.0, 1.0) * 0.75)
			c.a = edge * edge * taper
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _weapon_slash(from2d: Vector2, to2d: Vector2, col: Color) -> void:   # 面向镜头的斜砍斩弧(用户选)+命中环
	var arc := Sprite3D.new()
	arc.texture = _make_slash_texture(col)
	arc.billboard = BaseMaterial3D.BILLBOARD_ENABLED; arc.shaded = false; arc.transparent = true
	arc.pixel_size = 0.05
	arc.flip_h = (to2d.x < from2d.x)                     # 敌在左→翻转斜向(朝敌人那侧劈)
	arc.position = _world_pos(to2d, 1.0)                 # 落在敌身上, 略抬高
	arc.modulate = Color(col.r, col.g, col.b, 0.0)
	arc.scale = Vector3(0.5, 0.5, 0.5)
	_world.add_child(arc)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(arc, "modulate:a", 0.95, 0.05)
	tw.tween_property(arc, "scale", Vector3(1.25, 1.25, 1.25), 0.14)   # 快速挥出(扫)
	tw.chain().tween_property(arc, "modulate:a", 0.0, 0.13)
	tw.chain().tween_callback(arc.queue_free)
	_skill_ring(to2d, Color(col.r, col.g, col.b, 0.6), 42.0)

var _slash_sheet_cache: ImageTexture = null
func _make_slash_sheet(col: Color) -> ImageTexture:   # Undertale式红色像素斩击 5帧(斜向弧: 白热芯+红光, 生成→峰值→断裂消散); NEAREST放大=像素感; 缓存
	if _slash_sheet_cache != null:
		return _slash_sheet_cache
	var FN := 5; var FW := 44
	var img := Image.create(FW * FN, FW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var env := [0.6, 1.0, 1.0, 0.6, 0.28]   # 每帧亮度包络(生成→峰→消散)
	for f in range(FN):
		var ox := f * FW
		var tt := float(f) / float(FN - 1)
		var br: float = env[f]
		for y in range(FW):
			for x in range(FW):
				var nx := float(x) / float(FW - 1)
				var ny := float(y) / float(FW - 1)
				var along := clampf((nx - ny + 1.0) * 0.5, 0.0, 1.0)   # 沿反对角线位置
				if along < 0.07 or along > 0.93: continue   # 两端截断
				if f == 0 and along > 0.72: continue   # 第0帧: 斩弧刚划入前段
				if tt > 0.5 and sin(along * 33.0 + float(f) * 3.1) > lerpf(1.2, -0.15, (tt - 0.5) / 0.5): continue   # 后段断裂缺口
				var bow := 0.17 * sin(PI * along)   # sabre弧弯
				var d := (nx + ny - 1.0) * 0.70710678 - bow   # 到斩弧带状距离
				var taper := pow(sin(PI * along), 0.5)   # 中间段更饱满(broader plateau)
				var th := 0.092 * (0.34 + 1.05 * taper)   # 中间更粗两端尖(叶形斩弧)
				var ad := absf(d)
				if ad > th: continue
				var e := (1.0 - ad / th) * br
				var core := 1.0 - clampf(ad / (th * 0.42), 0.0, 1.0)   # 白热芯(放大)
				img.set_pixel(ox + x, y, Color(lerpf(col.r, 1.0, core), lerpf(col.g, 1.0, core), lerpf(col.b, 1.0, core), clampf(e, 0.0, 1.0)))
	_slash_sheet_cache = ImageTexture.create_from_image(img)
	return _slash_sheet_cache

func _blood_slash(from2d: Vector2, to2d: Vector2, delay: float) -> void:   # 饮血连斩: Undertale式红像素斩击(5帧×100ms)落敌身, 纯视觉
	var off := Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 10.0))
	var spr := Sprite3D.new()
	spr.texture = _make_slash_sheet(Color("#ff2233"))
	spr.hframes = 5; spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素感(不做线性模糊)
	spr.flip_h = (randf() < 0.5); spr.flip_v = (randf() < 0.4)   # 翻转=乱斩不同向
	var fw: float = float(spr.texture.get_width()) / 5.0
	spr.pixel_size = (95.0 * WS) / fw   # 斩击约95px宽
	spr.position = _world_pos(to2d + off, 1.0)
	spr.modulate = Color(1, 1, 1, 0)   # delay前隐藏
	_world.add_child(spr)
	var tw := _reg_tween()
	if delay > 0.0: tw.tween_interval(delay)
	tw.tween_callback(spr.set_modulate.bind(Color(1, 1, 1, 1)))
	tw.tween_method(func(fr): spr.frame = clampi(int(fr), 0, 4), 0.0, 5.0, 0.5)   # 5帧×100ms=0.5s
	tw.tween_callback(spr.queue_free)

func _pull_airborne(o: Dictionary, origin: Vector2, dist: float, dur: float) -> void:   # 击飞态平滑拉向origin(拉dist码, 留24px不重叠); vx/vz须为0(靠此改pos, 非物理横滑)
	if not o.get("alive", false): return
	var to_o: Vector2 = origin - o["pos"]
	var d0: float = to_o.length()
	if d0 < 1.0: return
	var pull: float = minf(dist, maxf(0.0, d0 - 24.0))   # 别拉进熊身(留24px)
	if pull <= 0.5: return
	var start: Vector2 = o["pos"]
	var target: Vector2 = start + (to_o / d0) * pull
	var el := 0.0
	while el < dur and o.get("alive", false) and bool(o.get("airborne", false)):
		await get_tree().process_frame
		el += get_process_delta_time()
		var k: float = clampf(el / dur, 0.0, 1.0)
		k = 1.0 - (1.0 - k) * (1.0 - k)   # ease-out(先快后缓)
		o["pos"] = start.lerp(target, k)

func _make_sword_texture(col: Color) -> ImageTexture:   # 剑刃(尖指+X): 柄→刃身→尖
	var W := 56; var H := 14
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var halfw: float = (1.0 - fx) / 0.15 * 4.0 if fx > 0.85 else (4.0 if fx > 0.2 else 2.0)
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= halfw:
				var edge := 1.0 - dy / maxf(0.6, halfw)
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.5, 0.0, 1.0) * 0.85)
				c.a = clampf(edge + 0.35, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_qi_texture(col: Color) -> ImageTexture:   # 竖剑气: 竖向弯月能量刃(前凸/两端尖/亮核软光)
	var W := 34; var H := 88
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(H):
		var fy := float(y) / float(H - 1)
		var taper := sin(PI * fy)
		var cx := float(W) * 0.38 + 7.0 * sin(PI * fy)
		var thick := 5.0 * taper + 1.0
		for x in range(W):
			var dx := absf(float(x) - cx)
			if dx <= thick:
				var edge := 1.0 - dx / thick
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.6, 0.0, 1.0) * 0.8)
				c.a = edge * edge * (0.35 + 0.65 * taper)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_vblade_texture(col: Color) -> ImageTexture:   # 竖剑刃(尖朝上): 尖→刃身→柄
	var W := 18; var H := 76
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(W - 1) / 2.0
	for y in range(H):
		var fy := float(y) / float(H - 1)
		var halfw: float = fy / 0.12 * 5.0 if fy < 0.12 else (5.0 if fy < 0.8 else 2.5)
		for x in range(W):
			var dx := absf(float(x) - cx)
			if dx <= halfw:
				var edge := 1.0 - dx / maxf(0.6, halfw)
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.5, 0.0, 1.0) * 0.85)
				c.a = clampf(edge + 0.35, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _eq_broadsword(u: Dictionary, si: int) -> void:   # 锈蚀阔剑(用户改造): 蓄力→高举阔剑→向下斩击(旋转挥砍)→竖剑气缓移600码穿敌 伤害即给盾
	var flat: int = [20, 35, 60][si]
	var sc: float = [0.5, 0.8, 1.1][si]
	var shp: float = [0.5, 0.75, 1.0][si]
	var t = _nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	_anticipate(u); _shake(JUICE_SHAKE_HEAVY)
	var front: Vector2 = u["pos"] + dir * 55.0
	var sword := Sprite3D.new()   # 阔剑: 非billboard→可旋转挥砍; 面镜头倾角+柄底为轴
	sword.texture = _make_vblade_texture(Color(0.92, 0.94, 1.0))
	sword.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sword.shaded = false; sword.transparent = true
	sword.pixel_size = 0.015   # 缩到龟大小(用户)
	sword.offset = Vector2(0, 38)   # 柄底(纹理底)对齐原点→绕柄挥砍
	sword.modulate = Color(0.92, 0.94, 1.0, 0.0)
	sword.position = _world_pos(front, 0.6)
	sword.rotation = Vector3(-0.6, 0.0, 1.15)   # x=面镜头, z=上扬蓄势
	sword.scale = Vector3(0.5, 0.5, 0.5)
	_world.add_child(sword)
	var gt := _reg_tween(); gt.set_parallel(true)
	gt.tween_property(sword, "modulate:a", 1.0, 0.28)
	gt.tween_property(sword, "scale", Vector3(1.5, 1.5, 1.5), 0.4)
	await get_tree().create_timer(0.6).timeout
	if not u.get("alive", false):
		if is_instance_valid(sword): sword.queue_free()
		return
	var dt := _reg_tween()   # 向下斩击: z从上扬1.15挥到下劈-1.35 (快, 回弹)
	dt.tween_property(sword, "rotation:z", -1.35, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await dt.finished
	_shake(JUICE_SHAKE_HEAVY); _skill_ring(front, Color(0.7, 0.85, 1.0, 0.6), 82.0)
	if is_instance_valid(sword):
		var sf := _reg_tween(); sf.tween_property(sword, "modulate:a", 0.0, 0.16); sf.tween_callback(sword.queue_free)
	var qi := Sprite3D.new()   # 竖剑气(弯月能量刃, 短, 坐地)
	qi.texture = _make_qi_texture(Color(0.7, 0.86, 1.0))
	qi.billboard = BaseMaterial3D.BILLBOARD_ENABLED; qi.shaded = false; qi.transparent = true
	qi.pixel_size = 0.03
	qi.scale = Vector3(1.3, 0.6, 1.0)
	qi.modulate = Color(0.72, 0.88, 1.0, 0.95)
	_world.add_child(qi)
	var reach := 600.0
	var traveled := 0.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(qi) and is_instance_valid(self):
		await get_tree().process_frame
		traveled += 250.0 * get_process_delta_time()
		qi.position = _world_pos(front + dir * traveled, 0.9)
		for o in _enemies_of(u):
			if o in hit or not o.get("alive", false): continue
			if (o["pos"] - front).dot(dir) <= traveled and _on_line(front, dir, o["pos"], 85.0):
				hit.append(o)
				var dd: int = _atk_dmg(u, sc, o) + flat
				_apply_damage_from(u, o, dd, Color("#dfe8ff"), 0.0, false, true)
				_grant_shield(u, dd * shp)   # 造成伤害即给盾(用户: 每命中一个就给)
	if is_instance_valid(qi):
		var ft := _reg_tween(); ft.tween_property(qi, "modulate:a", 0.0, 0.2); ft.tween_callback(qi.queue_free)

func _eq_coral_spike(u: Dictionary, far: Dictionary, si: int) -> void:   # 珊瑚刺弹体→最远敌, 到达: 物理+%maxHP魔法(错峰显示)
	var start: Vector2 = u["pos"]
	var d: Vector2 = far["pos"] - start
	var dist: float = d.length()
	if dist < 1.0: return
	var dir: Vector2 = d / dist
	var sp := Sprite3D.new()
	sp.texture = _make_sword_texture(Color(1.0, 0.5, 0.42))   # 珊瑚色刺
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sp.axis = Vector3.AXIS_Y
	sp.shaded = false; sp.transparent = true; sp.pixel_size = 0.035
	sp.rotation = Vector3(0.0, -atan2(dir.y, dir.x), 0.0)   # 刺尖指向目标
	sp.position = _world_pos(start, 0.7)
	_world.add_child(sp)
	var traveled: float = 0.0
	while traveled < dist and is_instance_valid(sp) and is_instance_valid(self):
		await get_tree().process_frame
		traveled += 850.0 * get_process_delta_time()
		sp.position = _world_pos(start + dir * minf(traveled, dist), 0.7)
	if is_instance_valid(sp): sp.queue_free()
	if not far.get("alive", false): return
	_skill_ring(far["pos"], Color(1.0, 0.5, 0.4, 0.5), 40.0)
	_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ff6b5b"), 0.0, false, true)   # 物理(红, 高度rank0下)
	var mrm: float = 40.0 / (40.0 + maxf(0.0, float(far["mr"])))   # 魔抗减免K=40; 魔法段同帧跳→_float_row_offset自动错行(不叠, 无延时)
	_last_dmg_type = "magic"
	_apply_damage_from(u, far, maxi(1, int(far["maxHp"] * [0.08, 0.12, 0.18][si] * mrm)), Color("#bfe9ff"), 0.0, false, true)   # %maxHP魔法(蓝,rank1上)

func _tick_coral(u: Dictionary, delta: float) -> void:   # 双穿珊瑚刺p2eq_008: 每6秒对最远敌(用户); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_008": continue
		e["coral_t"] = float(e.get("coral_t", 0.0)) + delta
		if float(e["coral_t"]) < 6.0: continue
		var far = null; var fd := -1.0
		for o in _enemies_of(u):
			var dd2: float = (o["pos"] - u["pos"]).length_squared()
			if dd2 > fd: fd = dd2; far = o
		if far == null: continue
		e["coral_t"] = 0.0
		var si: int = _eq_si(int(e.get("star", 1)))
		_bolt_line(u["pos"], far["pos"], Color("#ff8f66"))
		_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ff4444"), 0.0, false, true)
		_apply_damage_from(u, far, int(far["maxHp"] * [0.08, 0.12, 0.18][si]), Color("#bfe9ff"), 0.0, true, true)

func _tick_broadsword(u: Dictionary, delta: float) -> void:   # 锈蚀阔剑p2eq_007: 每6秒触发(用户); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_007": continue
		e["bsw_t"] = float(e.get("bsw_t", 0.0)) + delta
		if float(e["bsw_t"]) < 6.0: continue
		if _nearest_enemy(u) == null: continue
		e["bsw_t"] = 0.0
		_eq_broadsword(u, _eq_si(int(e.get("star", 1))))

func _tick_sword_storm(u: Dictionary, delta: float) -> void:   # 千刃风暴p2eq_006: 每7秒触发(用户); 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_006": continue
		e["storm_t"] = float(e.get("storm_t", 0.0)) + delta
		if float(e["storm_t"]) < 7.0: continue
		if _nearest_enemy(u) == null: continue
		e["storm_t"] = 0.0
		_eq_sword_storm(u, _eq_si(int(e.get("star", 1))))

func _eq_sword_storm(u: Dictionary, si: int) -> void:   # 千刃风暴(用户改造): 蓄力→身后召一排剑→剑阵前移穿过全体敌
	var flat: int = [70, 100, 400][si]
	var sc: float = [0.8, 1.3, 4.0][si]
	var t = _nearest_enemy(u)
	var dir: Vector2 = ((t["pos"] - u["pos"]).normalized() if t != null else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var ang: float = -atan2(dir.y, dir.x)
	_anticipate(u); _shake(JUICE_SHAKE_HEAVY)
	var glow := Sprite3D.new()
	glow.texture = _make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
	glow.modulate = Color(0.7, 0.82, 1.0, 0.0); glow.pixel_size = 0.02
	glow.position = _world_pos(u["pos"] - dir * 100.0, 1.0)
	_world.add_child(glow)
	var gt := _reg_tween()
	gt.tween_property(glow, "modulate:a", 0.85, 0.4)
	gt.parallel().tween_property(glow, "scale", Vector3(2.8, 2.8, 2.8), 0.45)
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(glow): glow.queue_free()
	if not u.get("alive", false): return
	var n := 7
	var swords: Array = []
	for k in range(n):   # 生成剑: 身后错峰淡入+放大(先横排, 垂直行进)
		var off: float = (float(k) - float(n - 1) / 2.0) * 85.0
		var sp := Sprite3D.new()
		sp.texture = _make_sword_texture(Color(0.85, 0.9, 1.0))
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sp.axis = Vector3.AXIS_Y
		sp.shaded = false; sp.transparent = true; sp.pixel_size = 0.07
		sp.rotation = Vector3(0.0, ang + PI / 2.0, 0.0)
		sp.position = _world_pos(u["pos"] - dir * 130.0 + perp * off, 0.4)
		sp.modulate = Color(0.85, 0.9, 1.0, 0.0)
		sp.scale = Vector3(0.3, 0.3, 0.3)
		_world.add_child(sp)
		var st := _reg_tween(); st.set_parallel(true)
		st.tween_property(sp, "modulate:a", 0.95, 0.2).set_delay(float(k) * 0.03)
		st.tween_property(sp, "scale", Vector3.ONE, 0.25).set_delay(float(k) * 0.03)
		swords.append(sp)
	await get_tree().create_timer(0.42).timeout   # 等一排剑生成完
	if not u.get("alive", false): return
	for spr in swords:   # 调转方向: 一排剑同时旋转对准行进方向(带回弹)
		if is_instance_valid(spr):
			_reg_tween().tween_property(spr, "rotation:y", ang, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.34).timeout
	if not u.get("alive", false): return
	_shake(JUICE_SHAKE_HEAVY)
	var reach := 1050.0
	var traveled := 0.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(self):
		await get_tree().process_frame
		traveled += 650.0 * get_process_delta_time()   # 剑速(用户:慢点)
		var front_along: float = -130.0 + traveled
		for i in range(swords.size()):
			var sp = swords[i]
			if is_instance_valid(sp):
				var off2: float = (float(i) - float(n - 1) / 2.0) * 85.0
				sp.position = _world_pos(u["pos"] + dir * front_along + perp * off2, 0.4)
		for o in _enemies_of(u):
			if o in hit or not o.get("alive", false): continue
			if (o["pos"] - u["pos"]).dot(dir) <= front_along:
				hit.append(o)
				_apply_damage_from(u, o, _atk_dmg(u, sc, o) + flat, Color("#dfe8ff"), 0.0, false, true)
				_skill_ring(o["pos"], Color(0.82, 0.9, 1.0, 0.5), 44.0)
	for sp2 in swords:
		if is_instance_valid(sp2):
			var ft := _reg_tween()
			ft.tween_property(sp2, "modulate:a", 0.0, 0.14)
			ft.tween_callback(sp2.queue_free)

func _bear_shockwave(u: Dictionary, tgt: Dictionary, _si: int) -> void:   # 大熊冲击波(小菊式): 蓄力→直线移动波, 1.5ATK物理+击飞0.8s+拉回70码
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	var origin: Vector2 = u["pos"]
	# 砸地位移全程手控(帧驱动voff关掉): 起身高举后仰 → 猛砸下 → 复位
	u["bear_anim"] = "slam"; u["bear_anim_t"] = 0.0
	u["_slam_manual"] = true
	u["no_move"] = true                               # 冲击波全程大熊锁死原地(不再被AI往敌人走=修"漂移循环走")
	var ldir: Vector3 = u.get("_bear_ldir", Vector3.ZERO)
	_shake(JUICE_SHAKE_HEAVY)
	var glow := Sprite3D.new()
	glow.texture = _make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
	glow.modulate = Color(1.0, 0.82, 0.4, 0.0); glow.pixel_size = 0.012
	glow.position = _world_pos(origin, 0.35)
	_world.add_child(glow)
	var gt := _reg_tween()
	gt.tween_property(glow, "modulate:a", 0.5, 0.4)
	gt.parallel().tween_property(glow, "scale", Vector3(1.4, 1.4, 1.4), 0.4)
	# 前摇: 起身高高举起(加速t²)+后仰 (0.4s)
	var rt := 0.0
	while rt < 0.4 and u.get("alive", false):
		await get_tree().process_frame
		rt += get_process_delta_time()
		var a: float = rt / 0.4
		u["_bear_voff"] = Vector3(0.0, a * a * 0.95, 0.0)   # 起身: 直上举高(无横移=不左右滑)
	if is_instance_valid(glow): glow.queue_free()
	if not u.get("alive", false):
		u["_slam_manual"] = false; u["no_move"] = false; u["_bear_voff"] = Vector3.ZERO; return
	# 猛砸下: 从高处加速砸到地下 (0.12s)
	var st := 0.0
	while st < 0.12 and u.get("alive", false):
		await get_tree().process_frame
		st += get_process_delta_time()
		var b: float = st / 0.12
		u["_bear_voff"] = Vector3(0.0, lerpf(0.95, -0.22, b), 0.0)   # 猛砸下: 直下(无横移=不左右滑)
	# === 砸地瞬间: 落地压扁 + 大震屏 + 顿帧 + 尘环, 冲击波起 ===
	u["_bear_voff"] = Vector3(0.0, -0.22, 0.0)
	u["land_t"] = JUICE_LAND_SEC
	_shake(JUICE_SHAKE_BIG); _hitstop = maxf(_hitstop, 0.05)
	_impact_particles(origin, 0.0)
	_skill_ring(origin, Color(1.0, 0.85, 0.4, 0.7), 96.0)
	# 释放: 冲击波沿 dir 前进, 沿途暖金块一簇簇破土冒起(小菊式地面喷涌), 波前首经过即命中; 熊起身复位
	var dmg: int = _atk_dmg(u, 1.5, tgt)
	var perp: Vector2 = dir.orthogonal()
	var reach := 600.0   # 射程边界 600码 (用户)
	var traveled := 0.0
	var last_chunk := -20.0
	var hit_arr: Array = []
	var rec := 0.0
	while traveled < reach and is_instance_valid(self):
		await get_tree().process_frame
		var fdt: float = get_process_delta_time()
		traveled += 500.0 * fdt   # 波速 500px/s (用户: 慢点)
		rec += fdt
		u["_bear_voff"] = Vector3(0.0, lerpf(-0.22, 0.0, clampf(rec / 0.3, 0.0, 1.0)), 0.0)   # 起身复位
		while last_chunk < traveled:                    # 沿途金块依次冒起(每40码一簇+横向散)
			last_chunk += 40.0
			var cp: Vector2 = origin + dir * last_chunk
			_gold_chunk_erupt(cp + perp * randf_range(-26.0, 26.0))
			if randf() < 0.6:
				_gold_chunk_erupt(cp + perp * randf_range(-55.0, 55.0))
		for o in _enemies_of(u):
			if o in hit_arr or not o.get("alive", false): continue
			var proj: float = (o["pos"] - origin).dot(dir)
			if proj >= -40.0 and proj <= traveled + 30.0 and _on_line(origin, dir, o["pos"], 85.0):
				hit_arr.append(o)
				_apply_damage_from(u, o, dmg, Color("#ffd27a"), 0.0, false, true)
				_knockback(u, o, 0.0, 1.5, 0.0)          # 击飞 ~0.8s (vy×1.5), 无横推(vx/vz=0, 拉回交给_pull_airborne)
				_pull_airborne(o, origin, 70.0, 0.45)    # 拉回70码: 滞空(击飞态)期平滑滑向大熊(留24px不重叠)
				_gold_chunk_erupt(o["pos"])              # 命中点额外炸一簇
	u["_bear_voff"] = Vector3.ZERO
	u["_slam_manual"] = false
	u["no_move"] = false                              # 冲击波结束解锁, 大熊恢复正常走位

func _gold_chunk_erupt(pos2d: Vector2) -> void:   # 金块破土冒起(暖金)→短留→碎
	var tex: Texture2D = load("res://assets/sprites/vfx/gold-chunk.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(1, 1, 1, 0)
	var sc: float = randf_range(0.75, 1.2)
	spr.pixel_size = (1.3 * sc) / float(maxi(1, int(tex.get_height())))
	var wh: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = _world_pos(pos2d, wh * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.55, 0.0)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(0.18)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(spr.queue_free)

func _do_basic(u: Dictionary, tgt: Dictionary, spec: Dictionary) -> void:
	var atk: float = u["atk"]
	# 三类原始伤害(未减) = ×ATK 总倍率
	var raw_p: float = float(spec.get("phys", 0.0)) * atk
	var raw_m: float = float(spec.get("magic", 0.0)) * atk
	var raw_t: float = float(spec.get("true", 0.0)) * atk
	# 加成项 (进主类型): 护甲/魔抗/目标HP/自HP/目标当前HP/金币/暴击flat
	var bonus: float = float(spec.get("def", 0.0)) * u["def"] + float(spec.get("mr", 0.0)) * u["mr"]
	bonus += float(spec.get("hp", 0.0)) * tgt["maxHp"] + float(spec.get("selfhp", 0.0)) * u["maxHp"] + float(spec.get("tcurhp", 0.0)) * tgt["hp"]
	bonus += float(spec.get("gold", 0.0)) * atk * u.get("gold", 0.0) + float(spec.get("critflat", 0.0)) * u["crit"]
	if raw_p > 0.0:
		raw_p += bonus
	else:
		raw_m += bonus
	var col: Color = Color("#4dabf7") if (raw_m > raw_p) else Color("#ff4444")
	var vh: int = clampi(int(spec.get("hits", 1)), 1, 6)
	if spec.get("alt_each", false) and raw_p > 0.0 and raw_m > 0.0:
		# 逐次攻击交替类型(单段): 本次物理→下次魔法→… (寒冰冰锥, 用户)
		var use_magic: bool = bool(u.get("basic_alt", false))
		u["basic_alt"] = not use_magic
		if use_magic:
			_emit_basic(u, tgt, _mitigate(u, raw_m, tgt, true), Color("#4dabf7"), 0)
		else:
			_emit_basic(u, tgt, _mitigate(u, raw_p, tgt, false), Color("#ff4444"), 0)
	elif spec.get("alt", false) and raw_p > 0.0 and (raw_m > 0.0 or raw_t > 0.0):
		# 交替: 偶段物理, 奇段(魔法或真实) — 各类型在各自半数段摊 (寒冰物/魔, 龟壳物/真)
		var half: int = maxi(1, vh / 2)
		var alt_magic: bool = raw_m > 0.0
		for i in range(vh):
			if not tgt["alive"]:
				break
			if i % 2 == 0:
				_emit_basic(u, tgt, _mitigate(u, raw_p / half, tgt, false), Color("#ff4444"), i)
			elif alt_magic:
				_emit_basic(u, tgt, _mitigate(u, raw_m / half, tgt, true), Color("#4dabf7"), i)
			else:
				_apply_damage_from(u, tgt, int(raw_t / half), Color("#ffffff"), 0.0, true)
	else:
		for i in range(vh):
			if not tgt["alive"]:
				break
			var dmg := 0
			if raw_p > 0.0:
				dmg += _mitigate(u, raw_p / vh, tgt, false)
			if raw_m > 0.0:
				dmg += _mitigate(u, raw_m / vh, tgt, true)
			_emit_basic(u, tgt, dmg, col, i)
			if raw_t > 0.0:
				_apply_damage_from(u, tgt, int(raw_t / vh), Color("#ffffff"), 0.0, true)   # 真实(穿减伤)
	# 普攻自愈 (×ATK·每次普攻一次·海盗弯刀0.2A·silent防高频刷绿字)
	var sh: float = float(spec.get("selfheal", 0.0))
	if sh > 0.0 and u.get("alive", false):
		_heal(u, atk * sh, true)
	# 附带效果
	match str(spec.get("rider", "")):
		"burn":    _apply_dot_stacks(tgt, "burn", (maxi(1, int(round(float(u["atk"]) * float(spec.get("burnScale", 0.0))))) if spec.has("burnScale") else _default_burn_stacks(u)), u)
		"atkdn":   _buff(tgt, "atk", -0.15, true)
		"selfdef": _buff(u, "def", 0.20, true)
		"bleed":   _apply_dot_stacks(tgt, "bleed", (3 if _last_atk_crit else 2), u)   # 忍者斩击: 2层流血(本次暴击→3层·封板·读_resolve_dmg设的_last_atk_crit)
		"shrink":  _hiding_shell_harden(u)                             # 缩头缩壳: 每击+1甲+1抗(永久)+0.1A盾
	# 特殊机制
	match str(spec.get("mech", "")):
		"splash":  _splash_adjacent(u, tgt, float(spec.get("splash", 0.25)))   # 相邻敌溅射

# 一段普攻伤害落地 (近战直击+前冲 / 远程发弹)
func _emit_basic(u: Dictionary, tgt: Dictionary, dmg: int, col: Color, i: int) -> void:
	if dmg <= 0:
		return
	if u["melee"]:
		_apply_damage_from(u, tgt, dmg, col)
		if i == 0:
			_flash(tgt); _melee_lunge(u, tgt)
	else:
		_fire_bolt_from(u, tgt, dmg, col, null, true)   # 普攻弹道: 命中时触发on_basic_hit

# 伤害减免+暴击 (与 _atk_dmg 同口径, 但吃"已算好的原始伤害"而非 scale)
func _mitigate(u: Dictionary, raw: float, tgt: Dictionary, magic: bool) -> int:
	return _resolve_dmg(u, raw, tgt, magic)

# 相邻溅射 (龟壳): 主目标附近敌受 frac 溅射; 若无相邻, 不额外 (主伤已结算)
func _splash_adjacent(u: Dictionary, tgt: Dictionary, frac: float) -> void:
	for o in _enemies_of(u):
		if o == tgt or not o["alive"]:
			continue
		if (o["pos"] - tgt["pos"]).length() <= 90.0:
			_apply_damage_from(u, o, _mitigate(u, u["atk"] * 0.6 * frac, o, false), Color("#cfd8e8"))
	# 普攻 on-hit 被动钩子 (墨迹/电击/结晶叠层 + 猎杀斩杀 等)
	_on_basic_hit(u, tgt)

# 龟壳·龟壳打击(用户改造): 1ATK单段, 物理↔真实逐攻交替(本次真→下次物→…), 主目标120px内其他敌溅射50%(同类型)
const SHELL_SPLASH_RADIUS := 120.0
func _shell_basic(u: Dictionary, tgt: Dictionary) -> void:
	_shell_break_stealth(u)                                     # 自己普攻→破隐(设shell_stealth_broke)
	if u.get("shell_stealth_broke", false):                    # 破隐后第一发普攻: +1A魔法 + 0.5A毒层 + 3秒50%治疗削减
		u["shell_stealth_broke"] = false
		_apply_damage_from(u, tgt, int(u["atk"] * 1.0), Color("#9b3bff"))
		_apply_dot_stacks(tgt, "poison", maxi(1, int(round(u["atk"] * 0.5))), u)
		tgt["heal_reduce_until"] = _t + 3.0
		tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), 0.5)
		_float_text(u["pos"] + Vector2(0, -58), "破隐!", Color("#9b3bff"))
	u["basic_alt"] = not u.get("basic_alt", false)
	var is_true: bool = bool(u["basic_alt"])
	# 主目标命中
	if is_true:
		_apply_damage_from(u, tgt, int(u["atk"] * 1.0), Color("#ffffff"), 0.0, true)   # 真实(穿减伤)
	else:
		_apply_damage_from(u, tgt, _resolve_dmg(u, u["atk"] * 1.0, tgt, false), Color("#ff4444"))
	# 近战打击感: 闪白 + 前冲 (同 _emit_basic 近战分支)
	_flash(tgt); _melee_lunge(u, tgt)
	# 范围溅射: 主目标120px内其他敌 50%(同类型)
	for e in _enemies_of(u):
		if e == tgt or not e.get("alive", false):
			continue
		if (e["pos"] - tgt["pos"]).length() <= SHELL_SPLASH_RADIUS:
			if is_true:
				_apply_damage_from(u, e, int(u["atk"] * 0.5), Color("#ffffff"), 0.0, true)
			else:
				_apply_damage_from(u, e, _resolve_dmg(u, u["atk"] * 0.5, e, false), Color("#ff4444"))

# 闪电龟·改造普攻(用户2026-06-28逐字"得改造，是一次攻击一道，并有连锁闪电和叠被动"):
#   一道闪电(魔法 0.6×ATK)命中主目标 → 依次接力连锁2跳(每跳260码内最近敌, 伤害×0.6递减 → 0.36A/0.216A)。
#   ★注意: 回合制「闪电打击」的 atkScale=1.15 是【5段总和】, 不是实时单道系数。旧注释写 1.15×ATK 与实装(0.6)不符, 2026-07-10 已订正。
#   0.6 / ×0.6 / 260码 均为实装默认值(用户未指定) → 见权威文档 附录A 调参表。
#   叠层在 _basic_attack 里走 _on_basic_hit(每攻击+1电击层, 满8引爆雷暴). 原始设计=魔法+跳敌+8层雷暴.
const PHX_CONE_HALF_DEG := 35.0     # 凤凰喷火扇形半角(全70°)
const PHX_FLAME_MAG_COEF := 0.2      # 每0.5s tick 魔法系数 ×ATK
const PHX_FLAME_BURN_COEF := 0.07     # 每0.5s tick 灼烧层系数 ×ATK ★T3实装默认(从熔岩龟抄来). 用户2026-06-30那句"每次普攻加灼烧层0.07ATK"是【对熔岩龟说的】(上文在谈熔岩攻速0.85), 凤凰这里用户原话写的是"每0.5秒造成？魔法伤害并施加？灼烧层"=没给数 → 见附录A

# 凤凰持续喷火 channel (Botworld Flamer式: 一直喷不脉冲; 每0.5s结算伤害; 边喷边kite; 放技能由状态机打断)
func _phoenix_flame_channel(u: Dictionary, tgt: Dictionary, delta: float) -> void:
	u["flip_h"] = tgt["pos"].x < u["pos"].x          # 朝向目标
	_phoenix_sector_indicator(u, tgt)
	u["phx_spawn_t"] = float(u.get("phx_spawn_t", 0.0)) + delta
	while u["phx_spawn_t"] >= 0.0055:                  # 持续喷火苗 ~50颗/秒(连续火流)
		u["phx_spawn_t"] -= 0.02
		_phoenix_flame_puff(u, tgt)
	u["phx_burn_t"] = float(u.get("phx_burn_t", 0.0)) + delta
	while u["phx_burn_t"] >= 0.5:                    # 每0.5s 伤害结算
		u["phx_burn_t"] -= 0.5
		_phoenix_flame_cone(u, tgt)

# 喷火伤害结算: 扇形内全部敌人 0.2ATK×(1+攻速) 魔法 + round(0.07ATK) 灼烧层 (用户2026-06-30)
func _phoenix_flame_cone(u: Dictionary, tgt: Dictionary) -> void:
	var atk: float = u["atk"]
	var aspd: float = 1.0 / maxf(0.05, float(u.get("atk_interval", 0.5)))   # 攻速=1/间隔
	var mag: float = PHX_FLAME_MAG_COEF * atk * (1.0 + aspd)
	var burn_stacks: int = maxi(1, roundi(atk * PHX_FLAME_BURN_COEF))
	var origin: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - origin
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var rng: float = float(u.get("atk_range", 400.0))
	var half_cos: float = cos(deg_to_rad(PHX_CONE_HALF_DEG))
	for e in _enemies_of(u):
		if not e.get("alive", false):
			continue
		var to_e: Vector2 = e["pos"] - origin
		var d: float = to_e.length()
		if d > rng or d < 1.0:
			continue
		if dir.dot(to_e / d) < half_cos:
			continue
		_apply_damage_from(u, e, _resolve_dmg(u, mag, e, true), Color("#4dabf7"))
		_apply_dot_stacks(e, "burn", burn_stacks, u)
		_flash(e, Color("#ff8a3a"))

# 单颗喷火苗: 嘴部喷出→沿锥角向外冲(火舌位移感), 软发光blob叠成顺滑火流, 黄白→橙→红透+边冲边长大
func _phoenix_flame_puff(u: Dictionary, tgt: Dictionary) -> void:
	var origin: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - origin
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var rng: float = float(u.get("atk_range", 400.0))
	var base_ang: float = dir.angle()
	var half: float = deg_to_rad(PHX_CONE_HALF_DEG)
	var ang: float = base_ang + _juice_rng.randf_range(-half, half) * 1.0
	var travel: float = _juice_rng.randf_range(rng * 0.45, rng * 1.0)
	var mouth: Vector2 = origin + Vector2(cos(base_ang), sin(base_ang)) * 20.0
	var endp: Vector2 = origin + Vector2(cos(ang), sin(ang)) * travel
	var spr := Sprite3D.new()
	spr.texture = _make_fire_glow_tex()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = 0.014
	spr.modulate = Color(1.0, 0.97, 0.78, 1.0)
	spr.scale = Vector3(0.5, 0.5, 0.5)
	spr.position = _world_pos(mouth, 1.0)
	_world.add_child(spr)
	var life: float = _juice_rng.randf_range(0.28, 0.42)
	var hend: float = 1.0 + _juice_rng.randf_range(0.0, 0.45)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", _world_pos(endp, hend), life)
	tw.tween_property(spr, "scale", Vector3(2.3, 2.3, 2.3), life)
	tw.tween_property(spr, "modulate", Color(0.92, 0.22, 0.05, 0.0), life)
	tw.chain().tween_callback(spr.queue_free)

# 灼烧特效 (自设计, 不用回合制): 燃烧单位身上窜升腾软光小火苗 (黄→红透+缩, 边燃边升)
func _spawn_burn_ember(u: Dictionary) -> void:
	var pos2d: Vector2 = u["pos"] + Vector2(_juice_rng.randf_range(-14.0, 14.0), _juice_rng.randf_range(-4.0, 8.0))
	var spr := Sprite3D.new()
	spr.texture = _make_fire_glow_tex()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = 0.0046
	spr.modulate = Color(1.0, 0.72, 0.3, 0.88)
	spr.scale = Vector3(0.7, 0.7, 0.7)
	var h0: float = 0.3
	spr.position = _world_pos(pos2d, h0)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", _world_pos(pos2d, h0 + 0.75), 0.46)
	tw.tween_property(spr, "scale", Vector3(0.3, 0.3, 0.3), 0.46)
	tw.tween_property(spr, "modulate", Color(0.9, 0.25, 0.05, 0.0), 0.46)
	tw.chain().tween_callback(spr.queue_free)

# 喷火扇形AOE指示: 贴地 淡橙填充 + 亮橙边轮廓 (边界明确, 跟伤害扇形一致); 持续刷新跟目标, 停喷由_tick_effects隐藏
func _phoenix_sector_indicator(u: Dictionary, tgt: Dictionary) -> void:
	var sect = u.get("flame_sector", null)
	if sect == null or not is_instance_valid(sect):
		sect = MeshInstance3D.new()
		sect.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sect.material_override = mat
		_world.add_child(sect)
		u["flame_sector"] = sect
	sect.visible = true
	u["flame_sector_t"] = _t + 0.12
	var origin: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - origin
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var base_ang: float = dir.angle()
	var half: float = deg_to_rad(PHX_CONE_HALF_DEG)
	var rng: float = float(u.get("atk_range", 400.0))
	var im: ImmediateMesh = sect.mesh
	im.clear_surfaces()
	var N := 14
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(N):
		var a0: float = base_ang - half + (2.0 * half) * float(i) / float(N)
		var a1: float = base_ang - half + (2.0 * half) * float(i + 1) / float(N)
		var p0: Vector2 = origin + Vector2(cos(a0), sin(a0)) * rng
		var p1: Vector2 = origin + Vector2(cos(a1), sin(a1)) * rng
		im.surface_set_color(Color(1.0, 0.42, 0.12, 0.16))
		im.surface_add_vertex(_world_pos(origin, 0.05))
		im.surface_set_color(Color(1.0, 0.32, 0.06, 0.04))
		im.surface_add_vertex(_world_pos(p0, 0.05))
		im.surface_set_color(Color(1.0, 0.32, 0.06, 0.04))
		im.surface_add_vertex(_world_pos(p1, 0.05))
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_set_color(Color(1.0, 0.66, 0.22, 0.7))
	im.surface_add_vertex(_world_pos(origin, 0.06))
	for i in range(N + 1):
		var a: float = base_ang - half + (2.0 * half) * float(i) / float(N)
		im.surface_add_vertex(_world_pos(origin + Vector2(cos(a), sin(a)) * rng, 0.06))
	im.surface_add_vertex(_world_pos(origin, 0.06))
	im.surface_end()

# 凤凰·烫伤 ✅: 蓄力投掷火球(1.5ATK魔法+1ATK灼烧+破盾/减攻防抗/治疗削减), 命中爆开 (用户)
func _sk_phoenix_scald(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0:
		dir = Vector2(1, 0)
	dir = dir.normalized()
	var mouth: Vector2 = u["pos"] + dir * 18.0
	var fb := Sprite3D.new()
	fb.texture = _make_fire_glow_tex()
	fb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fb.shaded = false
	fb.transparent = true
	fb.pixel_size = 0.011
	fb.modulate = Color(1.0, 0.85, 0.45, 0.95)
	fb.scale = Vector3(0.4, 0.4, 0.4)
	fb.position = _world_pos(mouth, 1.05)
	_world.add_child(fb)
	var tgt_pos: Vector2 = tgt["pos"]
	var tw := _reg_tween()
	tw.tween_property(fb, "scale", Vector3(1.9, 1.9, 1.9), 0.30)             # 蓄力(火球长大)
	tw.parallel().tween_property(fb, "modulate", Color(1.0, 0.40, 0.12, 1.0), 0.30)
	tw.tween_method(_scald_arc.bind(fb, mouth, tgt_pos), 0.0, 1.0, 0.42)        # 投掷
	tw.tween_callback(_phoenix_scald_hit.bind(u, tgt, fb))

func _phoenix_scald_hit(u: Dictionary, tgt, fb) -> void:
	if is_instance_valid(fb):
		fb.queue_free()
	if tgt == null or not tgt.get("alive", false):
		return
	# 封板: 火球命中先破50%护盾(破盾碎裂)→再落1.5A魔法穿透→灼烧+攻防抗各-15%+治疗削减
	_apply_skill_extras(u, tgt, {"shieldBreak": 0.5, "atkDown": 0.15, "defDown": 0.15, "mrDown": 0.15, "healCut": 0.5})
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.5, tgt, true), Color("#4dabf7"))   # 1.5ATK魔法(打已破的盾, 更多穿透到血)
	_apply_dot_stacks(tgt, "burn", maxi(1, roundi(float(u["atk"]) * 1.0)), u)   # 1ATK灼烧层
	_flash(tgt, Color("#ff8a3a"))
	_phoenix_flame_burst(tgt["pos"])

# 火焰爆发: 命中点炸开一圈软光火苗 + 亮环
func _phoenix_flame_burst(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(1.0, 0.55, 0.2, 0.7), 52.0)
	for i in range(12):
		var ang: float = TAU * float(i) / 12.0 + _juice_rng.randf_range(-0.2, 0.2)
		var d: float = _juice_rng.randf_range(10.0, 46.0)
		var p: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * d
		var spr := Sprite3D.new()
		spr.texture = _make_fire_glow_tex()
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.pixel_size = 0.009
		spr.modulate = Color(1.0, 0.8, 0.4, 0.95)
		spr.scale = Vector3(0.5, 0.5, 0.5)
		spr.position = _world_pos(pos2d, 0.7)
		_world.add_child(spr)
		var tw := _reg_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "position", _world_pos(p, 0.9 + _juice_rng.randf_range(0.0, 0.4)), 0.34)
		tw.tween_property(spr, "scale", Vector3(1.3, 1.3, 1.3), 0.34)
		tw.tween_property(spr, "modulate", Color(0.9, 0.25, 0.05, 0.0), 0.34)
		tw.chain().tween_callback(spr.queue_free)

# 火球抛物线飞行 (t:0→1; 高度 lerp + sin峰=抛起弧线) + 火焰拖尾
func _scald_arc(t: float, fb, p0: Vector2, p1: Vector2) -> void:
	if not is_instance_valid(fb):
		return
	var p: Vector2 = p0.lerp(p1, t)
	var h: float = lerpf(1.05, 0.6, t) + 1.5 * sin(PI * t)   # 抛物线峰高~2.3m
	fb.position = _world_pos(p, h)
	if _juice_rng.randf() < 0.7:
		_scald_trail(p, h)

func _scald_trail(pos2d: Vector2, h: float) -> void:
	var spr := Sprite3D.new()
	spr.texture = _make_fire_glow_tex()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = 0.006
	spr.modulate = Color(1.0, 0.48, 0.14, 0.7)
	spr.scale = Vector3(0.85, 0.85, 0.85)
	spr.position = _world_pos(pos2d, h)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector3(0.3, 0.3, 0.3), 0.26)
	tw.tween_property(spr, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(spr.queue_free)

func _lightning_basic(u: Dictionary, tgt: Dictionary) -> void:
	# 建链(顺序最近未连): 打1 → 1找最近2 → 2找最近3, 最多连锁2跳
	var chain: Array = [tgt]
	var prev: Dictionary = tgt
	for _i in range(2):
		var nxt = null
		var bestd := 260.0                       # 连锁射程上限(像素)
		for o in _enemies_of(u):
			if (o in chain) or not o["alive"]:
				continue
			var dd: float = (o["pos"] - prev["pos"]).length()
			if dd < bestd:
				bestd = dd; nxt = o
		if nxt == null:
			break
		chain.append(nxt); prev = nxt
	# 顺序错峰劈: 彩虹→1, 1→2, 2→3, 每跳隔0.07s(看得见跳跃) + 锯齿电弧
	var tw := _reg_tween()
	var from_pos: Vector2 = u["pos"]
	var fr := 1.0
	for i in range(chain.size()):
		tw.tween_callback(_lightning_hop.bind(u, from_pos, chain[i], fr, i))
		tw.tween_interval(0.07)
		from_pos = chain[i]["pos"]
		fr *= 0.6

func _lightning_electric(u: Dictionary, target: Dictionary) -> void:   # 叠1层电击; 满8引爆(天降+清零)
	var lv := _add_stack(target, "electric", 1, 8)
	if lv >= 8:
		_consume_stacks(target, "electric")
		_apply_damage_from(u, target, _shock_dmg(u), Color("#4dabf7"), 0.0, true)
		_lightning_strike(target["pos"], Color("#cdfaff"))
		_skill_ring(target["pos"], Color(0.72, 0.95, 1.0, 0.75), 76.0)
		_bolt_line(u["pos"], target["pos"], Color("#dffaff"))
		_shake(JUICE_SHAKE_LIGHT)

func _lightning_hop(u: Dictionary, from_pos: Vector2, target: Dictionary, fr: float, hop_i: int) -> void:
	if not target.get("alive", false):
		return
	_lightning_arc(from_pos, target["pos"], Color("#aef0ff"))   # 锯齿电弧
	_apply_damage_from(u, target, _atk_dmg(u, 0.6 * fr, target, true), Color("#4dabf7"))
	_hit_spark(target)
	if hop_i > 0:
		_lightning_electric(u, target)   # 连锁每跳也叠电击层(主目标由_on_basic_hit叠, 避免重复)

func _sk_lightning_barrage(u: Dictionary) -> void:             # 闪电龟·雷暴 ✅ (头顶生风暴云→20道极快锯齿电弧劈随机敌, 用户自画)
	var cloud_h := 2.9
	var cloud := Sprite3D.new()
	var ctex := load("res://assets/sprites/skills/lightning-2.png")
	if ctex != null:
		cloud.texture = ctex
		cloud.pixel_size = 2.2 / float(maxi(1, ctex.get_height()))
	cloud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cloud.shaded = false
	cloud.transparent = true
	cloud.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cloud.position = _world_pos(u["pos"], cloud_h)
	_world.add_child(cloud)
	var tw := _reg_tween()
	for i in range(20):                            # 20道极快电(每0.06s)
		tw.tween_callback(_barrage_bolt.bind(u, cloud_h))
		tw.tween_interval(0.06)
	tw.tween_callback(_barrage_cloud_fade.bind(cloud))

func _barrage_bolt(u: Dictionary, cloud_h: float) -> void:
	var es := _enemies_of(u)
	if es.is_empty():
		return
	var e = es[_juice_rng.randi() % es.size()]
	if not e.get("alive", false):
		return
	_lightning_bolt_3d(u["pos"], cloud_h, e["pos"], 0.6, Color("#aef0ff"))
	_apply_damage_from(u, e, _atk_dmg(u, 2.2 / 20.0, e, true), Color("#7ee8ff"))
	_add_stack(e, "electric", 1, 8)

func _barrage_cloud_fade(cloud: Sprite3D) -> void:
	if not is_instance_valid(cloud):
		return
	var tw := _reg_tween()
	tw.tween_property(cloud, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cloud.queue_free)

func _lightning_bolt_3d(from2d: Vector2, from_h: float, to2d: Vector2, to_h: float, col: Color) -> void:   # 锯齿3D电弧(从云劈向敌)
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = col
	imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var n := 7
	for i in range(n + 1):
		var t := float(i) / float(n)
		var p2 := from2d.lerp(to2d, t)
		var hh: float = lerpf(from_h, to_h, t)
		if i > 0 and i < n:
			p2 += Vector2(_juice_rng.randf_range(-12.0, 12.0), _juice_rng.randf_range(-12.0, 12.0))
		imesh.surface_set_color(col)
		imesh.surface_add_vertex(_world_pos(p2, hh))
	imesh.surface_end()
	_world.add_child(im)
	var tw := _reg_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(im.queue_free)

func _lightning_strike(pos2d: Vector2, _col: Color, world_h: float = 2.6) -> void:   # 天降闪电 common-lightning-strike 5帧(9fps); world_h=雷高度(越大雷越大, 中心≈world_h*0.478); 4.6时中心≈2.2=飘字高度→伤害跳在雷中间
	var tex := load("res://assets/sprites/vfx/common-lightning-strike.png")
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = world_h / float(maxi(1, tex.get_height()))
	spr.position = _world_pos(pos2d, world_h * 0.478)
	_world.add_child(spr)
	var tw := _reg_tween()
	for f in range(5):                              # 5帧 9fps(~0.06s/帧)
		tw.tween_callback(_lstrike_frame.bind(spr, f))
		tw.tween_interval(1.0 / 9.0)   # 9fps = 回合制 common-lightning-strike 同播放时长(5帧0.556s)
	tw.tween_callback(spr.queue_free)

func _lstrike_frame(spr: Sprite3D, f: int) -> void:
	if is_instance_valid(spr):
		spr.frame = f

func _lightning_arc(a2d: Vector2, b2d: Vector2, col: Color) -> void:   # 锯齿状电弧(zigzag折线, 像真闪电劈过去)
	var n := 6
	var perp := (b2d - a2d).orthogonal().normalized()
	var prev := a2d
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var mid := a2d.lerp(b2d, t)
		if i < n:
			mid += perp * _juice_rng.randf_range(-16.0, 16.0)
		_bolt_line(prev, mid, col)
		prev = mid

# 伤害公式 (1:1 复用 2D _atk_dmg): base×scale ×暴击 ×(100/(100+resist-pierce))
# 伤害核心: 暴击(封顶100%溢出转暴伤×1.5) → 有效护甲/魔抗(先%后flat,可负) → 减伤倍率(K=40,负防增伤) → 增伤/减伤
func _resolve_dmg(u: Dictionary, base: float, tgt: Dictionary, magic: bool) -> int:
	_last_dmg_type = "magic" if magic else "physical"   # 记类型供飘字取色
	var eff_crit: float = minf(float(u["crit"]), 1.0)
	_last_atk_crit = randf() < eff_crit
	if _last_atk_crit:
		base *= float(u["crit_dmg"]) + maxf(0.0, float(u["crit"]) - 1.0) * 1.5   # 暴击率溢出100%每1%→1.5%暴伤
	var resist: float
	if magic:
		resist = float(tgt["mr"]) * (1.0 - float(u.get("magic_pen_pct", 0.0))) - float(u.get("magic_pen", 0.0))
	else:
		resist = float(tgt["def"]) * (1.0 - float(u.get("armor_pen_pct", 0.0))) - float(u.get("armor_pen", 0.0))
	var mult: float = (1.0 - resist / (resist + 40.0)) if resist >= 0.0 else (1.0 + absf(resist) / (absf(resist) + 40.0))
	base *= mult
	base *= 1.0 + float(u.get("damage_amp", 0.0))          # 攻击者增伤%
	base *= 1.0 - float(tgt.get("damage_reduction", 0.0))  # 受害者减伤%(真伤不走此函数)
	if not magic and _t < float(tgt.get("phase_until", 0.0)):
		base *= 0.1                                          # 虚化(幽灵): 受物理伤害-90% (真伤/魔法不减)
	if magic and str(tgt.get("id", "")) == "crystal":
		base *= 0.8                                          # 水晶共鸣: 受魔法额外-20%
	return maxi(1, int(round(base)))

func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool = false) -> int:
	var base: float = u["atk"] * scale
	if u.get("_vs_fire_bonus", 0.0) > 0.0 and (str(tgt["id"]) == "lava" or str(tgt["id"]) == "phoenix"):
		base *= 1.0 + float(u["_vs_fire_bonus"])   # 寒冰: 对熔岩/凤凰增伤(天生+20%, 选极寒技覆盖+40%)
	return _resolve_dmg(u, base, tgt, magic)

# 只做物理减免(减甲/增伤/减伤/虚化), 不掷暴击 — 供已在上游算过暴击的伤害段(手里剑物理段)复用 _resolve_dmg 的减甲公式而不二次暴击
func _phys_after_armor(u: Dictionary, raw: float, tgt: Dictionary) -> int:
	var resist: float = float(tgt["def"]) * (1.0 - float(u.get("armor_pen_pct", 0.0))) - float(u.get("armor_pen", 0.0))
	var mult: float = (1.0 - resist / (resist + 40.0)) if resist >= 0.0 else (1.0 + absf(resist) / (absf(resist) + 40.0))
	var d: float = raw * mult
	d *= 1.0 + float(u.get("damage_amp", 0.0))
	d *= 1.0 - float(tgt.get("damage_reduction", 0.0))
	if _t < float(tgt.get("phase_until", 0.0)):
		d *= 0.1                                    # 虚化(幽灵): 受物理-90%
	return maxi(1, int(round(d)))

# 立绘前冲 (近战命中视觉) — billboard offset 微推再回 (朝镜头, 不用翻 facing)
# 近战命中踏步: 朝目标前冲再回. 走渲染追加偏移 _atk_voff(每帧render叠加, 见 _juice_decay), 不tween spr.position(会被逐帧render覆盖)
func _melee_lunge(u: Dictionary, tgt: Dictionary, amp: float = ATK_LUNGE_AMP) -> void:
	if tgt == null:
		return
	var d: Vector2 = tgt["pos"] - u["pos"]
	if d.length() < 0.01:
		return
	var dn := d.normalized()
	u["_lunge_dir"] = Vector3(dn.x, 0.0, dn.y)   # 2D方向→世界XZ(2D-x→世界x, 2D-y→世界z)
	var _ldur: float = clampf(float(u.get("atk_interval", 0.5)) * ATK_LUNGE_PCT, ATK_LUNGE_MIN, ATK_LUNGE_MAX)   # 踏步时长随攻速(快攻速踏步短, 同前摇)
	u["_lunge_t"] = _ldur
	u["_lunge_dur"] = _ldur
	u["_lunge_amp"] = amp   # 踏步幅度(默认ATK_LUNGE_AMP; 竹叶强化发传更大→不灭之握式前冲)

# ============================================================================
#  3D 投射物 (远程普攻/技能): 小 billboard 球从攻击者飞向目标, 到达落伤.
#  2D 接口对齐: _fire_bolt_from(src, tgt, dmg, col, from). src 用于 lifesteal/统计/累积 (可 null).
#  col 用于飘字色 (不再区分 magic bool; 物/法分流由 _atk_dmg 时已算进 dmg).
# ============================================================================
func _fire_bolt(from: Vector2, tgt: Dictionary, dmg: int, col: Color) -> void:
	_fire_bolt_from(null, tgt, dmg, col, from)

const _PROJ_WAVE := {"angel": true}   # 这些龟普攻弹道用尖尖能量波(程序画), 缺则默认bolt
func _fire_bolt_from(src, tgt: Dictionary, dmg: int, col: Color, from = null, basic_onhit: bool = false) -> void:
	var start2d: Vector2 = from if from != null else (src["pos"] if src != null else tgt["pos"])
	var p := Sprite3D.new()
	var oriented := false
	if src is Dictionary and _PROJ_WAVE.get(str(src.get("id", "")), false):
		p.texture = _make_wave_texture(col)
		p.pixel_size = 0.045   # 尖尖波 52×20 → ~2.3×0.9m
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		oriented = true        # 尖尖波有朝向→贴XZ绕Y转向行进方向(否则billboard永远面镜头指右, 斜射/上下射方向错)
	else:
		p.texture = _make_bolt_texture(col)
		p.pixel_size = 0.014
	if oriented:
		p.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		p.axis = Vector3.AXIS_Y
	else:
		p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)   # 从胸口高度出
	p.position = world_from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 700.0, 0.22, 0.7), "basic_onhit": basic_onhit,
		"oriented": oriented, "dtype": _last_dmg_type,
	})

func _summon_walking_bear(u: Dictionary, tgt: Dictionary, dmg: int) -> void:   # 玩偶小熊仔: 召出走路动画小熊→走向敌→踢击动画(伤+击飞)→消失
	if tgt == null:
		return
	var bear := Sprite3D.new()
	bear.texture = load("res://assets/sprites/vfx/teddy-walk.png")   # 7帧玩偶泰迪走路(独立小熊仔,非大熊图)
	bear.hframes = 7
	bear.frame = 0
	bear.pixel_size = 1.0 / 80.0   # ~1.0m 高玩偶小熊仔 (小于2m龟, 比大熊小)
	bear.offset = Vector2(0.0, 40.0)   # 底部对齐地面 (80帧半高)
	bear.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bear.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bear.shaded = false
	bear.transparent = true
	var pos: Vector2 = u["pos"]
	bear.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(bear)
	var spd := 160.0   # 中等步速 px/s (龟约105~145)
	var guard := 0.0
	var wt := 0.0
	while is_instance_valid(bear) and tgt != null and tgt.get("alive", false):
		await get_tree().process_frame
		var dt := get_process_delta_time()
		guard += dt; wt += dt
		bear.frame = int(wt * 10.0) % 7             # 走路循环 10fps
		bear.flip_h = float(tgt["pos"].x) > pos.x   # 面向目标(默认朝左→敌在右则flip朝右)
		if guard > 4.0:   # 兜底: 走太久放弃
			break
		var to: Vector2 = tgt["pos"]
		if pos.distance_to(to) <= 60.0:   # 进攻击范围
			break
		pos = pos.move_toward(to, spd * dt)
		bear.position = _world_pos(pos, GROUND_LIFT)
	# 到位: 播踢击动画 (5帧), 第3帧接触→伤害+击飞
	if tgt != null and tgt.get("alive", false) and is_instance_valid(bear):
		bear.texture = load("res://assets/sprites/vfx/teddy-kick.png")   # 玩偶泰迪踢击(5帧)
		bear.hframes = 5
		bear.frame = 0
		var kt := 0.0
		var hit := false
		while kt < 0.34 and is_instance_valid(bear):
			await get_tree().process_frame
			kt += get_process_delta_time()
			bear.frame = mini(4, int(kt / 0.06))
			if not hit and bear.frame >= 3:
				hit = true
				if tgt.get("alive", false):
					_apply_damage_from(u, tgt, dmg, Color("#ffb0c8"), 0.0, false, true)
					_knockback(u, tgt, 60.0, 1.6, 1.9)   # 踢一脚: 上抛×1.6/横推×1.9
	# 小熊消失 (淡出)
	if is_instance_valid(bear):
		var tw := _reg_tween()
		tw.tween_property(bear, "modulate:a", 0.0, 0.2)
		tw.tween_callback(bear.queue_free)

func _step_projectiles(delta: float) -> void:
	var ts_on: bool = not _ts_active.is_empty()
	var keep: Array = []
	for pr in _projectiles:
		var node: Sprite3D = pr["node"]
		if not is_instance_valid(node):
			continue
		if ts_on and not _ts_active.has(pr.get("src")):
			keep.append(pr); continue   # 时停: 非active携带者的弹道悬空定格(不推进)
		pr["t"] += delta
		var tgt: Dictionary = pr["tgt"]
		var to := _world_pos(tgt["pos"], 1.0)
		var frac: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		node.position = pr["from"].lerp(to, frac)
		if pr.has("arc"):
			node.position.y += float(pr["arc"]) * sin(PI * frac)   # 抛物线拱起(火球等)
		if pr.get("oriented", false):                              # 尖尖波: 绕Y转向行进方向(尖端领着飞)
			var d3: Vector3 = to - node.position
			if d3.length() > 0.05:
				node.rotation.y = -atan2(d3.z, d3.x)
		if pr.get("shuriken_anim", false):                         # 手里剑: 4帧忍者飞镖旋转动画
			node.frame = int(pr["t"] * 18.0) % 4
		if frac >= 1.0:
			node.queue_free()
			if tgt["alive"]:
				if pr.has("dtype"): _last_dmg_type = str(pr["dtype"])   # ★弹道命中: 还原发射时捕获的伤害类型(飞行期全局可能被别的伤害覆写→飘字色错·用户2026-07-11)
				if pr.get("fireball", false):   # 抛物线火球045: 落点火爆+魔法伤(蓝字)+灼烧
					_apply_damage_from(pr["src"], tgt, _resolve_dmg(pr["src"], float(pr["dmg"]), tgt, true), pr["col"], 0.0, false, true)
					if pr.get("fire_burst", 0) > 0:
						_apply_dot_stacks(tgt, "burn", int(pr["fire_burst"]), pr["src"])
					_fire_explosion(tgt["pos"])
				elif pr.get("bamboo", false):   # 竹枝箭039: 命中魔法伤(蓝字)+冒绿生命球飞回携带者
					_apply_damage_from(pr["src"], tgt, _resolve_dmg(pr["src"], float(pr["dmg"]), tgt, true), pr["col"], 0.0, false, true)
					_spawn_bamboo_orb(tgt["pos"], pr["src"]["pos"])
					_hit_spark(tgt)
				elif pr.get("shuriken_hit", false):   # 手里剑: 物理段(红·减甲)+暴击时真伤段(白·穿甲)→同发跳两数字(飘字系统按类型自动错开行·不合并)
					_last_atk_crit = bool(pr.get("is_crit", false))   # 两段都按暴击显示(大字+暴击图标)
					_last_dmg_type = "physical"
					_apply_damage_from(pr["src"], tgt, _phys_after_armor(pr["src"], float(pr["nj_phys"]), tgt), Color("#ff4444"), 0.0, false)   # 物理段(红)
					if float(pr.get("nj_true", 0.0)) >= 1.0 and tgt.get("alive", false):
						_last_atk_crit = bool(pr.get("is_crit", false))   # 物理段hook可能改写→真伤段前重置
						_apply_damage_from(pr["src"], tgt, int(round(float(pr["nj_true"]))), Color("#ffffff"), 0.0, true, false, true)   # 真伤段(白·pre_crit=已含暴击不再二次掷)
				elif pr.get("eq_bolt", false):   # 装备弹道(弩矢/飞镖等): 记为装备物理伤, 命中溅火花
					_apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"], float(pr.get("eq_ls", 0.0)), false, true)
					if pr.get("eq_bleed", 0) > 0:
						_apply_dot_stacks(tgt, "bleed", int(pr["eq_bleed"]), pr["src"])
					_hit_spark(tgt)
				elif pr["src"] != null:
					_apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"], 0.0, pr.get("raw", false))   # raw=手里剑暴击转真伤等
				else:
					_apply_damage(tgt, pr["dmg"], pr["col"])
				_flash(tgt)
				if pr.get("basic_onhit", false) and pr["src"] != null:
					_on_basic_hit(pr["src"], tgt)   # 远程普攻附带(审判等)弹道命中时触发→与裁决同帧跳数字
				if pr.get("freeze_on_hit", 0.0) > 0.0:
					_freeze(tgt, pr["freeze_on_hit"])   # 冰封: 弹道命中→冻结
				if pr.get("coin_true", 0) > 0:
					_apply_damage_from(pr["src"], tgt, int(pr["coin_true"]), Color("#fff0a0"), 0.0, true)   # 金币真实那半
			continue
		keep.append(pr)
	_projectiles = keep

# 依次射出的子弹: 每帧减 delay, 到点 call 回调(回调内部再选目标+射线+伤害, 死亡守卫在回调里判)
func _step_pending_shots(delta: float) -> void:
	var ts_on: bool = not _ts_active.is_empty()
	for i in range(_pending_shots.size() - 1, -1, -1):
		var s: Dictionary = _pending_shots[i]
		if ts_on and not _ts_active.has(s.get("src")):
			continue   # 时停: 非active携带者的依次射击冻结
		s["delay"] = float(s["delay"]) - delta
		if float(s["delay"]) <= 0.0:
			_pending_shots.remove_at(i)
			var fn = s["fn"]
			if fn is Callable and fn.is_valid():
				fn.call()

# 排队 count 发子弹, 每发间隔 interval 秒, 逐发 call fn (fn 内部自选目标, 支持死亡守卫)
func _queue_shots(count: int, interval: float, fn: Callable, src = null) -> void:
	for k in range(count):
		_pending_shots.append({"delay": float(k) * interval, "fn": fn, "src": src})

# 枪口闪: 在 pos2d 沿 dir 前方一点爆一小簇火光(胸口高度), 表现开火
func _muzzle_flash(pos2d: Vector2, dir: Vector2, col: Color) -> void:
	var mp: Vector2 = pos2d + dir.normalized() * 26.0
	var sp := Sprite3D.new()
	if _spark_tex == null:
		_spark_tex = _make_glow_texture()
	sp.texture = _spark_tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(col.r, col.g, col.b, 0.95)
	sp.position = _world_pos(mp, 1.0)
	sp.pixel_size = 0.016
	sp.scale = Vector3.ONE * 0.4
	_world.add_child(sp)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(sp, "scale", Vector3.ONE * 1.05, 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.09)
	tw.chain().tween_callback(sp.queue_free)

# 霰弹弹珠: 一颗小铅丸从muzzle沿扇形方向喷出+淡出(霰弹散射, 一次喷一片)
func _make_pellet_texture() -> ImageTexture:   # 小圆金属铅丸: 亮心+硬边圆
	var S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(S - 1) / 2.0
	for y in range(S):
		for x in range(S):
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d <= c - 0.5:
				var t := d / c
				var a := 1.0 if t < 0.82 else clampf((1.0 - t) / 0.18, 0.0, 1.0)
				var br := clampf(1.25 - t * 0.85, 0.45, 1.0)
				img.set_pixel(x, y, Color(1.0 * br, 0.9 * br, 0.5 * br, a))
	return ImageTexture.create_from_image(img)

func _shotgun_pellet(from2d: Vector2, to2d: Vector2, col: Color) -> void:
	if _pellet_tex == null: _pellet_tex = _make_pellet_texture()
	var sp := Sprite3D.new()
	sp.texture = _pellet_tex
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.modulate = col
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = 0.02
	var perp := (to2d - from2d).orthogonal().normalized() if (to2d - from2d).length() > 1.0 else Vector2.UP
	sp.position = _world_pos(from2d + perp * randf_range(-18.0, 18.0), 1.0)
	_world.add_child(sp)
	var tw := _reg_tween()   # 顺序: 全程满alpha飞行 → 命中处才快速淡出(修"路中间淡化"用户2026-07-04)
	tw.tween_property(sp, "position", _world_pos(to2d, 1.0), 0.42).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.1)
	tw.tween_callback(sp.queue_free)

# 装备弹道(弩矢/飞镖等真实贴图投射物): 朝向随飞行方向(2.5D近似 z-roll), 命中记装备物理伤. eq_bleed=命中附加流血层
func _spawn_eq_bolt(src: Dictionary, tgt: Dictionary, dmg: int, tex_path: String, col: Color, spin: bool = false, bleed: int = 0, psize: float = 0.032) -> void:
	if tgt == null: return
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	p.texture = load(tex_path)
	p.pixel_size = psize
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false; p.transparent = true
	p.modulate = col
	var dir2d: Vector2 = (tgt["pos"] - start2d)
	if not spin:
		p.rotation.z = atan2(-dir2d.y * 0.55, dir2d.x)   # 朝向随方向(俯视前缩近似)
	p.position = _world_pos(start2d, 1.0)
	_world.add_child(p)
	if spin:   # 飞镖: 旋转飞行
		var sw := _reg_tween().bind_node(p).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
		sw.tween_property(p, "rotation:z", TAU, 0.18).from(0.0)
	_projectiles.append({
		"node": p, "from": _world_pos(start2d, 1.0), "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 520.0, 0.22, 1.1),   # 慢一半(用户"完全看不清")
		"eq_bolt": true, "eq_bleed": bleed,
	})

# 激光束: a→b 一道立起来的发光带(叠加混合), 快速淡出. 用于激光手枪/狙击曳光
func _laser_beam(a2d: Vector2, b2d: Vector2, col: Color, half_w: float = 0.16, dur: float = 0.2, h: float = 1.0) -> void:
	# 立起的加法混合三角带(a→b), 顶点色驱动 albedo + 淡出(与 _bolt_line 同一顶点色渲染路径)
	var wa := _world_pos(a2d, h)
	var wb := _world_pos(b2d, h)
	var up := Vector3(0.0, half_w, 0.0)
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	for v in [wa - up, wa + up, wb + up, wa - up, wb + up, wb - up]:
		imesh.surface_set_color(col); imesh.surface_add_vertex(v)
	imesh.surface_end()
	_world.add_child(im)
	var tw := _reg_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_callback(im.queue_free)

# 尖尖能量波弹道贴图 (程序画: 透镜状两端尖, 白核+col边, 按伤害色上色)
func _make_wave_texture(col: Color) -> ImageTexture:
	var W := 52
	var H := 20
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var half := (float(H) / 2.0 - 0.5) * sin(PI * fx)   # 透镜: 两端尖中间宽
		if half < 0.4:
			continue
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= half:
				var edge := 1.0 - dy / half
				var c := col.lerp(Color(1, 1, 1), clampf(edge * 1.4, 0.0, 1.0) * 0.75)   # 核心偏白
				c.a = edge * edge   # 软边
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

## ★#6修: 子弹从 GradientTexture2D(radial 露方角) → Image 逐像素真圆(角 alpha=0). 按颜色缓存.
func _make_bolt_texture(col: Color) -> ImageTexture:
	var key := "%d" % col.to_rgba32()
	if _bolt_tex_cache.has(key):
		return _bolt_tex_cache[key]
	var N := 32
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 0.6:
				a = lerp(1.0, 0.9, d / 0.6)
			elif d < 1.0:
				a = lerp(0.9, 0.0, (d - 0.6) / 0.4)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var tex := ImageTexture.create_from_image(img)
	_bolt_tex_cache[key] = tex
	return tex

# ============================================================================
#  伤害应用 (1:1 复用 2D: 护盾吸收→HP; 闪避/吸血/统计/累积条/受伤被动; 击杀; 飘字)
# ============================================================================
# 无来源伤害 (DoT 层数结算等)
func _apply_damage(u: Dictionary, dmg: int, col: Color) -> void:
	var d := float(dmg)
	var shield_before: float = u["shield"]
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg   # §STATS: 无来源伤害(DoT等)只计承受
	_st_add_type(u, "_st_taken_by_type", "dot", dmg)    # 无来源=DoT 桶(分段条 真实+DoT 白)
	_float_text(u["pos"] + Vector2(randf_range(-26.0, 26.0), -40.0 + randf_range(-10.0, 6.0)), str(dmg), col)   # 抖开: 多段/AOE 出伤飘字不重叠成糊团
	# §AUDIO: 无来源伤害也出命中音 (非暴击); 护盾破→shield-break
	if shield_before > 0.0 and u["shield"] <= 0.0:
		_sfx_shield_break()
	else:
		_sfx_hit(false)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false, pre_crit: bool = false) -> void:
	# pre_crit=true: 该 raw 段的暴击已在上游算进 dmg(如手里剑真伤段=暴击总伤的一部分)→ 此处不再掷真伤暴击(防二次暴击)
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	if u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and randf() < u["dodge_bonus"]:
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#a0e8ff"))
		_eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 小龟·不屈: 造成的任何伤害按目标稀有度增伤 (总闸→普攻/技能/真伤/固定伤全覆盖, 只算一次)
	if src.get("id", "") == "basic" and src != u:
		dmg = int(round(float(dmg) * (1.0 + _BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	# 伤害输出乘数 (龟壳复制60%等; 默认1.0=不变): 缩放src本次造成的即时伤害
	if src.get("dmg_out_mult", 1.0) != 1.0:
		dmg = int(round(float(dmg) * float(src.get("dmg_out_mult", 1.0))))
	# 星辉战利品(宝箱传说): 所有伤害转真实=跳过减伤(钻石18%/岩层/铁壁flat) — 完整"绕护甲"局限留F5(伤害多已由_atk_dmg预减)
	if src.get("chest_starlight", false):
		raw = true
	# 靶向器055: 被标记目标受伤 +20%
	if _t < u.get("eq_marked_until", 0.0):
		dmg = int(dmg * 1.2)
	if u.get("_egg_final", false):   # 终极战场暴露蛋: ×5承伤(快速决胜)
		dmg = int(dmg * 5.0)
	# 真伤暴击 (全局: "暴击全龟通用"; 真伤照旧无视护甲/减伤, 只加暴击判定) (用户)
	if raw and not pre_crit and src is Dictionary and src.has("crit") and src != u:
		var _trc: float = minf(float(src.get("crit", 0.0)), 1.0)
		_last_atk_crit = randf() < _trc
		if _last_atk_crit:
			dmg = int(round(float(dmg) * (float(src.get("crit_dmg", 1.5)) + maxf(0.0, float(src.get("crit", 0.0)) - 1.0) * 1.5)))
	var was_crit := _last_atk_crit          # §AUDIO: 先抓暴击态 (下方 hook 里嵌套 _atk_dmg 会改写它)
	# 受伤被动(结算前改 dmg): 线条·墨迹(每层额外5%真实伤害·穿减伤穿盾) / 钻石·结构(受伤减免)
	var _ink := int((u.get("stacks", {}) as Dictionary).get("ink", 0))
	var _ink_true: float = 0.0
	if _ink > 0:
		_ink_true = float(dmg) * 0.05 * float(_ink)   # 墨迹: 原伤害之外·每层额外承受5%【真实伤害】(穿减伤穿盾·满10层=50%·用户2026-07-10纠正: 非×1.05增伤)
	if u["id"] == "diamond" and not raw:        # 钻石·结构减伤18%; 真实/穿透(raw)伤害不减 (修: 原来连真伤一起减=bug)
		dmg = int(dmg * 0.82)
	if u["id"] == "stone" and u.get("stone_rockbody", false) and not raw:   # 岩石之躯被动: 每岩层-1%受伤(上限30层=30%·真伤/穿透不减·封板)
		dmg = int(dmg * (1.0 - 0.01 * float(mini(30, int(u.get("rock_layers", 0))))))
	if u["id"] == "stone" and _t < float(u.get("stone_dr_until", 0.0)) and not raw:   # 嘲讽·(0.5×护甲)%伤害减免(用户#8·嘲讽4秒内·真伤/穿透不减·上限50%)
		dmg = int(dmg * (1.0 - clampf(0.5 * float(u["def"]) * 0.01, 0.0, 0.5)))
	var d := float(dmg)
	# 铁壁盾016: 每段非真实伤害固定减 X 点 (flat, 护盾前)
	if not raw and float(u.get("flat_dr", 0.0)) > 0.0:
		d = maxf(0.0, d - float(u["flat_dr"]))
	# 守护贝母021: 该单位被指向为"伤害转移", 把一部分入伤转给携带者承担 (护盾前分流, 剩余部分仍走本体护盾/血)
	var _rd = u.get("dmg_redirect_to", null)
	if _rd is Dictionary and _t < float(_rd.get("until", 0.0)):
		var carrier = _rd.get("carrier", null)
		if carrier is Dictionary and carrier.get("alive", false) and carrier != u and d > 0.0:
			var moved: float = d * float(_rd.get("pct", 0.0))
			if moved >= 1.0:
				d -= moved
				_raw_lose(carrier, moved)
	var shield_before: float = u["shield"]
	if not raw and u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	if not raw and d > 0.0 and float(u.get("_auraShieldVal", 0.0)) > 0.0:   # aura储能盾(金)单独吸收
		var ab_a := minf(float(u["_auraShieldVal"]), d)
		u["_auraShieldVal"] = float(u["_auraShieldVal"]) - ab_a; d -= ab_a
	if _ink_true > 0.0: d += _ink_true   # 墨迹真伤: 穿减伤穿盾, 直接进扣血并计入跳字
	u["hp"] = maxf(0.0, u["hp"] - d)
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	if not from_equip and d > 0.0: _ink_link_transfer(u, d)   # 连笔: 受伤30%以真实伤害传导给连接对象(附录B-05)
	# §STATS: 战斗统计 — 输出归攻击者/承受归目标 (用显示数 dmg); 按伤害类型分桶(战中分段条用) + 暴击计数
	var _bkt: String = ("tru" if raw else ("mag" if _last_dmg_type == "magic" else "phy"))   # 伤害分桶=真实类型(_last_dmg_type/raw), 非col: col是主题色·大量物理攻击传偏蓝色(忍者冲击#9fe8ff/#cfd8e8等)→原按col.b>col.r误判成法术=统计条+飘字全蓝(用户2026-07-11抓出)
	if src is Dictionary and src.has("side") and src != u:
		src["_st_dealt"] = int(src.get("_st_dealt", 0)) + dmg
		_st_add_type(src, "_st_dealt_by_type", _bkt, dmg)
		if was_crit:
			src["_st_crit"] = int(src.get("_st_crit", 0)) + 1
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg
	_st_add_type(u, "_st_taken_by_type", _bkt, dmg)
	# headless 亡灵: 首次濒死→5秒内HP不降到1以下(免死), 5秒后正常死
	if u["id"] == "headless" and u["hp"] <= 0.0 and not u.get("undead_used", false):
		u["undead_used"] = true; u["deathfloor_until"] = _t + 5.0
		_float_text(u["pos"] + Vector2(0, -64), "亡灵!", Color("#9b6bff"))
	if _t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = maxf(1.0, u["hp"])
	var _dt: String = "true" if raw else _last_dmg_type   # 飘字类型=真实伤害类型(_resolve_dmg设的_last_dmg_type·即时伤害对); 远程弹道在飞时会被别的伤害覆写→弹道在_step_projectiles命中前用捕获的pr.dtype还原(见那里)
	var _ncol: Color = _VC.color_of(_VC.cls_for("damage", _dt, was_crit))   # 飘字按伤害类型统一取色 (物红/魔蓝/真白, 1:1 回合制)
	var _jdir: float = 0.0
	if src is Dictionary and src != u and src.has("pos"):
		_jdir = 1.0 if float(src["pos"].x) < float(u["pos"].x) else -1.0   # 来源在左→数字往右跳, 反之往左(用户规则)
	_float_text(u["pos"], str(dmg), _ncol, was_crit, "damage", _dt, _jdir)   # 伤害: 朝远离来源方向弹射
	# 泡泡束缚(bubbleBind): 束缚期间每受一段伤害 → 永久 -X 护甲/魔抗 (单次累计上限各30)
	if _t < u.get("bind_until", 0.0):
		var _sx: float = float(u.get("bind_shred", 0.0))
		var _bacc: float = float(u.get("bind_acc", 0.0))
		if _sx > 0.0 and _bacc < 30.0:
			var _dec: float = minf(_sx, 30.0 - _bacc)
			u["base_def"] = maxf(0.0, u["base_def"] - _dec)
			u["base_mr"] = maxf(0.0, u["base_mr"] - _dec)
			u["bind_acc"] = _bacc + _dec
			_recalc_stats(u)
	# 泡泡·泡沫: 受伤的100%存为泡泡值(上限maxHp) → 周期消耗(见 _tick_periodic_passive)
	if u["id"] == "bubble":
		u["bubble_store"] = minf(u["maxHp"], float(u.get("bubble_store", 0.0)) + d)
	# 反伤(通用): 受击反弹 reflect% × 受到伤害 给攻击者(真实伤害); from_equip守卫防循环; stone坚壁随防御涨(被动)
	var _refl_pct: float = float(u.get("reflect", 0.0))
	if u["id"] == "stone": _refl_pct += 0.05 + (u["def"] + u["mr"] * 0.5) * 0.01
	if u["id"] == "stone" and u.get("stone_rockbody", false) and not from_equip and dmg > 0 and int(u.get("rock_layers", 0)) < 30:
		u["rock_layers"] = int(u.get("rock_layers", 0)) + 1   # 岩层(岩石之躯被动·选此才有): 每受伤+1层上限30
		u["size_mult"] = 1.0 + 0.02 * float(u["rock_layers"])   # +2%体型/层(回合制 rockShockwave.rockSizePctPerLayer=2·满30层=+60%)
	if _refl_pct > 0.0 and src != u and src.get("alive", false) and not from_equip and dmg > 0:
		var _refl := int(dmg * _refl_pct)
		if _refl > 0:
			_apply_damage_from(u, src, _refl, Color("#c9a36b"), 0.0, true, true)
	# 凤凰熔岩盾: 5秒内对每段攻击反击 0.14×ATK 魔法 (from_equip守卫防循环)
	if u["id"] == "phoenix" and _t < float(u.get("lava_shield_until", 0.0)) and src != u and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, _atk_dmg(u, 0.14, src, true), Color("#ff7a3c"), 0.0, false, true)
	# 闪电雷盾: 盾在时对每段攻击反击 0.1×ATK 魔法 + 给攻击者叠1层电击
	if u["id"] == "lightning" and _t < float(u.get("thunder_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0 and src != u and src.get("alive", false) and not from_equip and dmg > 0:
		_apply_damage_from(u, src, _atk_dmg(u, 0.1, src, true), Color("#4dabf7"), 0.0, false, true)
		_add_stack(src, "electric", 1, 8)
	# §AUDIO: 命中音 (暴击→hit-crit / 否则→hit-physical, 节流防多段刷屏); 护盾刚被打没→shield-break.
	if shield_before > 0.0 and u["shield"] <= 0.0 and not raw:
		u["shield_until"] = 0.0   # 盾被打空→清限时标记(防陈旧到期误清后续永久盾)
		_sfx_shield_break()
	else:
		_sfx_hit(was_crit)
	# Phase4 打击感: 受击闪白+轻压扁(每段直接命中); 顿帧/震屏/火花按伤害分级(auto: ≥gate=重击).
	_flash(u)
	_impact(u, dmg, "auto")
	# 来源累积 ----
	src["dmg_dealt"] += float(dmg)
	# 吸血 (lifesteal 基础 + buff + 技能 extra) — silent: 高频回血不刷治疗音
	var ls: float = src.get("lifesteal", 0.0) + src.get("ls_bonus", 0.0) + extra_ls
	if ls > 0.0 and src["alive"]:
		_heal(src, float(dmg) * ls, true)
	# 猎人猎杀(封板·任一伤害都处决): src=猎人 → 生命<斩杀线(默认14%·猎杀印记期间抬到24%)即处决; 窃取14%属性+叠吸血走 _kill→on-kill 钩子
	if src.get("id", "") == "hunter" and u.get("alive", false) and u != src:
		var _hthr: float = 0.24 if _t < float(u.get("hunt_mark_until", 0.0)) else 0.14
		if u["hp"] < u["maxHp"] * _hthr:
			u["hp"] = 0.0
			_float_text(u["pos"] + Vector2(0, -40), "处决!", Color("#ffd700"))
			_kill(u, src)
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava":
		src["rage"] = minf(RAGE_MAX, src["rage"] + float(dmg) * 0.10)
	if u["id"] == "lava":
		u["rage"] = minf(RAGE_MAX, u["rage"] + float(dmg) * 0.10)
	if src is Dictionary and src.get("has_egg", false) and src.get("alive", false):   # 温泉蛋(036): 造成伤害×0.1进度
		_egg_add_progress(src, float(dmg) * 0.1)
	if u.get("has_egg", false):   # 温泉蛋(036): 承受伤害×0.1进度
		_egg_add_progress(u, float(dmg) * 0.1)
	# 星能 (星际造伤62%)
	if src["id"] == "space":
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.62)
	# 储能 (龟壳受伤转储能, 上限50%最大HP) — 仅"store"相位累积 ("cd"相位不储)
	if u["id"] == "shell" and u.get("shell_phase", "store") == "store":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
		u["_auraEnergy"] = u["store_energy"]   # 镜像给Hp条储能条显示(1:1回合制字段)
	if u["id"] == "shell" and float(dmg) > 0.0:
		u["shell_last_dmg_t"] = _t                 # 潜影(暗影被动): 记最后受伤时间(6秒无伤→隐身). AOE命中也计→不误进隐身(设计: AOE吃伤但不破隐, 未说进隐身; 计伤保守=受伤即重置)
	# 双头坚韧 (融合打包被动·选中融合才有): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head" and u.get("two_fused", false):
		var th: int = int(u.get("two_tough", 0))
		if th < 20:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; _recalc_stats(u)
	# (反伤已合并到上方通用块, 删除重复的第二处石头反伤)
	# 装备事件钩子 (on-hit 攻击方 / on-target 防守方 / HP阈值) — 装备自身造的段不再回钩
	if not from_equip:
		if src["alive"] and u["alive"]:
			_eq_on_hit(src, u, dmg)        # on-hit: 攻击者装备 (流血/灼烧/连锁/追击/穿透/标记 等)
		if u["alive"]:
			_eq_on_target(u, src, dmg)     # on-target: 防守者装备 (硬化层/冰封反制 等)
		# 宝箱藏宝图 on-hit 战利品 (火石灼烧/毒箭治疗削减/雷刃金闪电引爆·此块已在not from_equip内→天然防循环)
		var _cht = src.get("chest_treasures", null)
		if _cht is Dictionary and src != u and u.get("alive", false):
			if _cht.has("flint"):    # 火石: 命中→灼烧层=round(0.67×ATK)
				_apply_dot_stacks(u, "burn", maxi(1, roundi(float(src["atk"]) * 0.67)), src)
			if _cht.has("poison"):   # 毒箭: 命中→治疗削减-50%·5秒
				u["heal_reduce_until"] = maxf(float(u.get("heal_reduce_until", 0.0)), _t + 5.0)
				u["heal_reduce_pct"] = maxf(float(u.get("heal_reduce_pct", 0.0)), 0.5)
			if _cht.has("thunder"):  # 雷刃: 命中叠金闪电·满5→引爆1.0A真伤(from_equip=true防循环)
				var _tl := _add_stack(u, "chest_thunder", 1, 5)
				if _tl >= 5:
					_consume_stacks(u, "chest_thunder")
					_apply_damage_from(src, u, maxi(1, int(float(src["atk"]))), Color("#ffe94d"), 0.0, true, true)
					_skill_ring(u["pos"], Color(1.0, 0.92, 0.3, 0.6), 40.0)
	if u["alive"]:
		_eq_check_hp_threshold(u)          # HP阈值: 首次<50% (深海项链/珍珠耳环)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u, src)

# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
func _raw_lose(u: Dictionary, amt: float) -> void:
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], amt)
		u["shield"] -= ab; amt -= ab
	u["hp"] = maxf(0.0, u["hp"] - amt)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 击飞 (真物理): 给 vy 初速 + 横向远离施法者 → tick 重力抛物 (3D 真抛物, 替代 2D 滑行+假抬升)
func _knockback(by: Dictionary, tgt: Dictionary, _dist: float, vy_mult: float = 1.0, push_mult: float = 1.0) -> void:
	if tgt["airborne"]:
		return
	var dir: Vector2 = (tgt["pos"] - by["pos"])
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	tgt["airborne"] = true
	tgt["vy"] = KNOCK_VY * vy_mult
	tgt["vx"] = dir.x * KNOCK_PUSH * push_mult
	tgt["vz"] = dir.y * KNOCK_PUSH * push_mult
	# Phase4: 击飞 = 大事件 → 大震屏 + 顿帧 + 起跳火花 (起跳拉长由 _juice_scale_for 读 airborne/vy 自动)
	_shake(JUICE_SHAKE_BIG)
	_add_hitstop(JUICE_HITSTOP_KNOCK)
	_impact_particles(tgt["pos"], tgt.get("height", 0.0))
	# 飞镖056: 任意敌被己方击飞 → 标"靶子", 携带者周期 tick 射镖
	if tgt["side"] != by["side"] and _side_has_equip(by["side"], "p2eq_056"):
		tgt["eq_target_until"] = _t + 99999.0
		_mark_vfx(tgt, 99999.0, Color("#ffa040"))

# 拉近: 把 tgt 拉到 by 面前 to_dist 处 (XZ 平面改 pos)
func _pull(by: Dictionary, tgt: Dictionary, to_dist: float) -> void:
	var dir: Vector2 = (tgt["pos"] - by["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	tgt["pos"] = by["pos"] + dir * to_dist
	tgt["pos"].x = clampf(tgt["pos"].x, ARENA.position.x, ARENA.end.x)
	tgt["pos"].y = clampf(tgt["pos"].y, ARENA.position.y, ARENA.end.y)

# 突进: 把 u 瞬移到 tgt 旁 gap 处 (近战切入; XZ 平面改 pos)
func _dash_to(u: Dictionary, tgt: Dictionary, gap: float) -> void:
	var dir: Vector2 = (u["pos"] - tgt["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	u["pos"] = tgt["pos"] + dir * gap
	u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

# 龟蛋碎裂死亡: 裂纹帧(瞬)→碎壳爆开(放大+淡出)+白闪+震屏. 帧缺→只淡出.
func _play_egg_shatter(u: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var crack: Texture2D = load("res://assets/sprites/map/egg_crack.png") if ResourceLoader.exists("res://assets/sprites/map/egg_crack.png") else null
	var shards: Texture2D = load("res://assets/sprites/map/egg_shards.png") if ResourceLoader.exists("res://assets/sprites/map/egg_shards.png") else null
	_flash(u, Color(1, 1, 1))
	_shake(JUICE_SHAKE_BIG)
	if crack != null:
		spr.texture = crack; spr.hframes = 1; spr.vframes = 1; spr.frame = 0
		spr.material_override = null
		spr.pixel_size = TARGET_BODY_H / float(maxi(1, crack.get_height()))
		spr.offset = Vector2(0.0, crack.get_height() * 0.5)
	var tw := _reg_tween()
	tw.tween_interval(0.12)
	if shards != null:
		tw.tween_callback(func():
			if is_instance_valid(spr):
				spr.texture = shards
				spr.pixel_size = (TARGET_BODY_H * 1.25) / float(maxi(1, shards.get_height()))
				spr.offset = Vector2(0.0, shards.get_height() * 0.5))
	tw.tween_property(spr, "scale", spr.scale * 1.7, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.55)
	tw.tween_callback(spr.hide)

func _kill(u: Dictionary, killer = null) -> void:
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为常驻一次, 1:1 2D
	if not u["reborn_used"] and ((u["id"] == "angel" and u.get("_angel_revive", false)) or u["id"] == "phoenix" or u.get("_chest_revive", false)):
		u["reborn_used"] = true
		var pct: float = (1.0 if u.get("_enh_rebirth", false) else 0.30) if u["id"] == "phoenix" else 0.25   # 凤凰100/30% · 天使圣光/宝箱凤凰雕像 25%
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		u["dot_stacks"] = {}
		_sfx_simple("rebirth")              # §AUDIO: 首死复活音 (天使圣光/凤凰涅槃, 低频不节流)
		_float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧 + 治疗削减5秒
			if u.get("_enh_rebirth", false):
				u["base_atk"] = u["base_atk"] * 1.2; _recalc_stats(u)   # 强化涅槃: 永久+20%攻击
			for o in _enemies_of(u):
				_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
				o["heal_reduce_until"] = _t + BUFF_SEC
				o["heal_reduce_pct"] = maxf(float(o.get("heal_reduce_pct", 0.0)), 0.5)
		return
	u["alive"] = false
	if not u.get("is_summon", false) and not u.get("_isEgg", false):
		_log("[color=#ff9a5a]☠ %s[/color] 被击败" % _unit_name(u))   # 战斗日志: 只记主龟阵亡(召唤体/蛋不刷屏)
		if killer is Dictionary and killer.has("side"):
			killer["_st_kills"] = int(killer.get("_st_kills", 0)) + 1   # §STATS: 击杀数归凶手(击杀主龟才计)
	if u.get("_isEgg", false):   # 龟蛋: 碎裂动画(替代普通死亡淡出), 胜负记账走 _dl_flow_check
		_on_unit_death(u, killer)
		_play_egg_shatter(u)
		for _ek in ["shadow", "ring", "contact"]:
			var _en = u.get(_ek, null)
			if is_instance_valid(_en):
				var _etw := _reg_tween(); _etw.tween_property(_en, "modulate:a", 0.0, 0.4); _etw.tween_callback(_en.hide)
		return
	if killer != null and killer.get("alive", false):
		_eq_on_kill(killer, u)             # on-kill: 击杀者装备 (暴君之牙处决回血 等)
	_eq_on_death(u, killer)                # on-death: 阵亡者装备 (复活海螺变虫 / 齿轮折币 / 玩偶熊)
	_on_unit_death(u, killer)
	for _egc in _units:   # 温泉蛋(036): 任意单位阵亡→持蛋者加进度(己方死+15/敌死+10)
		if _egc.get("has_egg", false) and _egc.get("alive", false):
			_egg_add_progress(_egc, 15.0 if str(_egc.get("side", "")) == str(u.get("side", "")) else 10.0)
	# 有死亡帧的龟(basic/ghost/ninja)播 death 动画 → 影/环/血条立即淡, 立绘延后淡(让动画演完)
	_play_action(u, "death")
	var has_death_anim: bool = (u.get("anim_action", "") == "death")
	# 影+环+接触影 淡出 (立绘单独处理, 让 death 动画演完再淡)
	for key in ["shadow", "ring", "contact"]:
		var n = u.get(key, null)
		if is_instance_valid(n):
			var tw := _reg_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.4)
			tw.tween_callback(n.hide)
	var spr_n = u.get("sprite", null)
	if is_instance_valid(spr_n):
		var stw := _reg_tween()
		if has_death_anim:
			stw.tween_interval(0.55)        # 等 death 帧演完 (~7-13帧 @11-12fps) 再淡出
		stw.tween_property(spr_n, "modulate:a", 0.0, 0.4)
		stw.tween_callback(spr_n.hide)
	if is_instance_valid(u["bar_root"]):
		u["bar_root"].visible = false

# (Phase4: 旧 tween 版 _flash 已移除, 改为状态驱动 _flash → 见 §JUICE; 与 squash/bob 统一从 base 重建)

# 飘字 (2D 接口对齐): 传像素 XZ 坐标 → 升到头顶世界点 → unproject 到屏幕 → UI overlay 上飘.
#   2D 版传 pos2d=u["pos"]+偏移(px); 这里把 y 偏移(px·往上)换算成 3D 高度抬升, 让"-64"这种头顶字落在头顶.
var _num_font: Font = null                  # #1 飘字像素数字字体 (m6x11, 跟回合制同款厚重描边)
func _float_num_font() -> Font:
	if _num_font == null:
		_num_font = load("res://assets/fonts/m6x11.ttf")
	return _num_font

# #1 字号按伤害量级缩放 (暴击×1.2) — 1:1 回合制 VisualConstants.size_by_amount
func _float_size(amount: int, is_crit: bool) -> int:
	var s: float
	if amount < 20:
		s = 20.0
	elif amount < 60:
		s = 20.0 + (float(amount - 20) / 40.0) * 4.0
	elif amount < 400:
		s = 24.0 + (float(amount - 60) / 340.0) * 11.0
	else:
		s = 35.0
	if is_crit:
		s *= 1.2
	return roundi(s)

func _make_num_label(text: String, col: Color, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _float_num_font())       # 像素厚字
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)           # 8向描边 (回合制同款, 深底浮字更清晰)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l

var _float_dmg_window: Dictionary = {}    # 伤害飘字按类型排行错开 (1:1 回合制 _float_row_offset)
var _float_nd_window: Dictionary = {}     # 非伤害(治疗/盾)紧凑堆叠
var _float_merge: Dictionary = {}         # 同目标+同类型+同帧伤害合并成一个数(奥恩式: 跳两者之和) key=posx_posy_type→{lbl,amount,t,crit}
# 同时跳出的飘字按规矩错开行: 伤害红0/蓝1/白2 紧凑×22(缺色不留空, 220ms窗口); 非伤害到达序堆叠(100ms)
const FLOAT_ROW_GAP := 15.0   # 同帧多数字每排间距(屏幕px); 实时版定值(比回合制22更贴近), 改这里=全局生效
func _float_row_offset(key: String, kind: String, dmg_type: String, fsize: float = 18.0) -> float:
	if kind == "damage":
		var rank: int = 0 if dmg_type == "physical" else (1 if dmg_type == "magic" else 2)   # 下→上: 物理0/魔法1/真实2 (白上蓝中红下)
		var w: Dictionary = _float_dmg_window.get(key, {"sizes": {}, "t": -9.0})
		if _t - float(w["t"]) > 0.22:
			w = {"sizes": {}, "t": -9.0}
		var sizes: Dictionary = w["sizes"]
		sizes[rank] = fsize   # 本数字字号(供上方行按下方各行高度累加错开)
		w["sizes"] = sizes; w["t"] = _t
		_float_dmg_window[key] = w
		var off: float = 0.0   # 贴近: 累加下方已present各行高度×系数 → 随伤害大小缩放, 贴近不重合
		for r in sizes:
			if int(r) < rank: off += float(sizes[r]) * 0.62
		return off
	var rec: Dictionary = _float_nd_window.get(key, {"t": -9.0, "n": 0})
	if _t - float(rec["t"]) > 0.10:
		rec["n"] = 0
	rec["t"] = _t
	var extra: int = int(rec["n"]); rec["n"] = extra + 1
	_float_nd_window[key] = rec
	return float(extra) * 22.0

# 飘字 (1:1 回合制 _spawn_float_text): kind=damage → 爆大pop(1.6~2.5)+抛物弹射(重力200,朝屏边跳); 否则(heal/shield/label) → pop1.2+缓升50px(sine)1.5s淡出
func _float_text(pos2d: Vector2, text: String, col: Color, is_crit: bool = false, kind: String = "label", dmg_type: String = "physical", jump_dir: float = 0.0) -> void:
	if _cam == null:
		return
	var head := _world_pos(pos2d, 2.2)
	if _cam.is_position_behind(head):
		return
	var screen: Vector2 = _cam.unproject_position(head)
	var amount := absi(text.to_int()) if text.is_valid_int() else 0
	var fsize := _float_size(amount, is_crit) if amount > 0 else (22 if is_crit else 18)
	var is_dmg_crit := is_crit and amount > 0 and kind == "damage"
	# 奥恩式合并: 同目标+同类型+同帧的伤害 → 累加到已在跳的那个数字(跳两者之和), 不新建
	var _mk := ""
	if kind == "damage" and amount > 0:
		_mk = "%d_%d_%s" % [roundi(pos2d.x), roundi(pos2d.y), dmg_type]
		var _m: Dictionary = _float_merge.get(_mk, {})
		if not _m.is_empty() and _t - float(_m.get("t", -9.0)) < 0.04 and is_instance_valid(_m.get("lbl", null)):
			var _na: int = int(_m["amount"]) + amount
			_m["amount"] = _na; _m["t"] = _t
			var _l: Label = _m["lbl"]
			_l.text = str(_na)
			_l.add_theme_font_size_override("font_size", _float_size(_na, bool(_m.get("crit", false))))
			_float_merge[_mk] = _m
			return
	var fly: Control
	var num_lbl: Label = null
	if is_dmg_crit:
		# 暴击伤害: 数字前嵌 crit 图标 (1:1 回合制 .floating-num crit 内嵌 20×20)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/sprites/stats/crit-dmg-icon.png")
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 忽略贴图原尺寸→缩到20 (缺它则700px原图撑爆)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		num_lbl = _make_num_label(text, col, fsize)
		box.add_child(num_lbl)
		fly = box
	else:
		num_lbl = _make_num_label(text, col, fsize)
		fly = num_lbl
	_ui_layer.add_child(fly)
	if _mk != "" and num_lbl != null:   # 注册本帧该目标该类型的数字, 供同帧后续伤害合并
		_float_merge[_mk] = {"lbl": num_lbl, "amount": amount, "t": _t, "crit": is_dmg_crit}
	# 居中起跳 + pivot 居中 (pop 绕中心, 1:1 PoC origin 0.5)
	var tsz := _float_num_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize)
	var unit_sz := Vector2(20.0 + 1.0 + tsz.x, maxf(20.0, tsz.y)) if is_dmg_crit else tsz
	fly.pivot_offset = unit_sz / 2.0
	var base_pos := screen - unit_sz / 2.0
	base_pos.y -= _float_row_offset("%d_%d" % [roundi(pos2d.x), roundi(pos2d.y)], kind, dmg_type, float(fsize))   # 按类型排行错开(白上红下, 贴近随大小缩放)
	if kind == "damage":
		# 伤害: 爆大pop(1.6~2.5按量级)→hold→抛物弹射(jump_x朝屏边, 重力200先上后下)→淡出 (1:1 PoC runFloatAnim)
		fly.position = base_pos
		fly.scale = Vector2(0.01, 0.01)
		var hold_scale := 1.0 if is_crit else 0.7
		var pop_size := 1.6 if amount < 20 else (1.8 if amount < 60 else (2.2 if amount < 150 else 2.5))
		var dir := (jump_dir if absf(jump_dir) > 0.5 else (-1.0 if base_pos.x < 640.0 else 1.0))   # 用户规则: 数字朝远离来源方向跳(来源左→往右/来源右→往左); 无来源朝屏边
		var jump_x := dir * (12.0 + randf() * 14.0)
		var jump_y := (-(10.0 + randf() * 8.0)) if is_crit else (-(22.0 + randf() * 10.0))
		var hold_end := 0.4 if is_crit else 0.15
		var total_dur := hold_end + 0.65
		var fade_start := hold_end + 0.3
		var tw := create_tween()
		tw.tween_method(_dmg_float_step.bind(fly, base_pos, jump_x, jump_y, hold_end, hold_scale, pop_size, total_dur, fade_start), 0.0, total_dur, total_dur)
		tw.tween_callback(fly.queue_free)
	else:
		# 治疗/护盾/名: pop1.2 → 缓升50px(sine) → 1.5s淡出 (1:1 PoC label路径)
		var lsy := base_pos.y - 15.0
		fly.position = Vector2(base_pos.x, lsy)
		fly.scale = Vector2.ONE
		var pop := create_tween()
		pop.tween_property(fly, "scale", Vector2(1.2, 1.2), 0.1)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(fly, "position:y", lsy - 50.0, 1.5).set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(fly, "modulate:a", 0.0, 1.5).set_delay(0.1)
		tw.chain().tween_callback(fly.queue_free)

# 伤害飘字每帧: pop→hold→抛物弹射 (1:1 PoC ticker). el=已过秒数; node_fl=飞行单元(label或含图标HBox)
func _dmg_float_step(el: float, node_fl: Control, base: Vector2, jump_x: float, jump_y: float, hold_end: float, hold_scale: float, pop_size: float, total_dur: float, fade_start: float) -> void:
	if not is_instance_valid(node_fl):
		return
	var sc: float
	if el < 0.05:
		sc = (el / 0.05) * pop_size
	elif el < 0.15:
		sc = pop_size - (pop_size - hold_scale) * ((el - 0.05) / 0.10)
	else:
		sc = hold_scale
	var flight: float = maxf(0.0, el - hold_end)
	var px: float = jump_x * flight * 2.0
	var py: float = jump_y * flight * 2.0 + 0.5 * 200.0 * flight * flight   # 重力 200
	node_fl.scale = Vector2(sc, sc)
	node_fl.position = base + Vector2(px, py)
	node_fl.modulate.a = 1.0 if el < fade_start else maxf(0.0, 1.0 - (el - fade_start) / (total_dur - fade_start))

# ── 竹叶生命球 (1:1 回合制 _spawn_bamboo_orb 港到2.5D): 绿球从目标抛物线(3D高度弧)飞回竹叶龟 + 绿拖尾 + 落点爆 ──
func _spawn_bamboo_orb(from_pos: Vector2, to_pos: Vector2, on_land: Callable = Callable()) -> void:
	var orb_path := "res://assets/sprites/vfx/bamboo-charge-orb.png"
	if not ResourceLoader.exists(orb_path):
		return
	var tex: Texture2D = load(orb_path)
	var fh: int = maxi(1, tex.get_height())
	var nframes: int = maxi(1, int(tex.get_width() / fh))
	var orb := Sprite3D.new()
	orb.texture = tex
	orb.hframes = nframes
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orb.shaded = false
	orb.transparent = true
	orb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	orb.pixel_size = 0.85 / float(fh)
	orb.position = _world_pos(from_pos, 1.0)
	_world.add_child(orb)
	var tw := create_tween()
	tw.tween_method(_bamboo_orb_step.bind(orb, from_pos, to_pos, nframes, [0]), 0.0, 1.0, 0.65)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(orb): orb.queue_free()
		_spawn_bamboo_burst(to_pos)
		if on_land.is_valid(): on_land.call())   # 绿球落到身上 → 回血+成长(用户: 到自己身上才吸收)

func _bamboo_orb_step(t: float, orb: Sprite3D, from_pos: Vector2, to_pos: Vector2, nframes: int, trail: Array) -> void:
	if not is_instance_valid(orb):
		return
	var base: Vector2 = from_pos.lerp(to_pos, t)
	var h: float = 1.0 + 1.5 * 4.0 * t * (1.0 - t)   # 抛物高度弧 (峰+1.5m)
	orb.position = _world_pos(base, h)
	if nframes > 1:
		orb.frame = int(t * float(nframes) * 2.0) % nframes
	if t > 0.05 and t < 0.93:
		var seg: int = int(t / 0.046)
		if seg > int(trail[0]):
			trail[0] = seg
			_bamboo_trail_dot(base, h)

func _bamboo_trail_dot(pos2d: Vector2, h: float) -> void:
	var dot := Sprite3D.new()
	dot.texture = _make_glow_texture()
	dot.modulate = Color(0.49, 1.0, 0.7, 0.7)   # #7dffb3 绿
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.shaded = false
	dot.transparent = true
	dot.pixel_size = 0.006
	dot.position = _world_pos(pos2d, h)
	_world.add_child(dot)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(dot, "modulate:a", 0.0, 0.42)
	tw.tween_property(dot, "scale", Vector3.ONE * 0.3, 0.42)
	tw.chain().tween_callback(dot.queue_free)

func _spawn_bamboo_burst(pos2d: Vector2) -> void:
	var bpath := "res://assets/sprites/vfx/bamboo-charge-burst.png"
	if not ResourceLoader.exists(bpath):
		return
	var tex: Texture2D = load(bpath)
	var fh: int = maxi(1, tex.get_height())
	var nframes: int = maxi(1, int(tex.get_width() / fh))
	var b := Sprite3D.new()
	b.texture = tex
	b.hframes = nframes
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.shaded = false
	b.transparent = true
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.pixel_size = 1.3 / float(fh)
	b.position = _world_pos(pos2d, 1.0)
	_world.add_child(b)
	var tw := _reg_tween()
	tw.tween_method(_bamboo_burst_step.bind(b, nframes), 0.0, 1.0, 0.35)
	tw.tween_callback(b.queue_free)

func _bamboo_burst_step(t: float, b: Sprite3D, nframes: int) -> void:
	if not is_instance_valid(b):
		return
	if nframes > 1:
		b.frame = mini(nframes - 1, int(t * float(nframes)))
	b.modulate.a = 1.0 - maxf(0.0, (t - 0.6) / 0.4)

# 治疗绿光 (港回合制 _play_heal_glow): 绿光球从身体升起淡出 + 绿脉冲贴地环
func _play_heal_glow(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(0.36, 0.92, 0.5, 0.5), 48.0)   # 绿脉冲环
	for i in range(6):
		var g := Sprite3D.new()
		g.texture = _make_glow_texture()
		g.modulate = Color(0.36, 0.92, 0.5, 0.85)   # #5cea80 治疗绿
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		g.shaded = false
		g.transparent = true
		g.pixel_size = 0.009
		g.position = _world_pos(pos2d, 0.2) + Vector3(randf_range(-0.45, 0.45), 0.0, randf_range(-0.2, 0.2))
		_world.add_child(g)
		var tw := _reg_tween()
		tw.set_parallel(true)
		tw.tween_property(g, "position:y", g.position.y + 1.6, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "modulate:a", 0.0, 0.7).set_delay(0.1)
		tw.chain().tween_callback(g.queue_free)

# ── 通用: 2D序列帧特效 贴 billboard 在2.5D场景逐帧播 (AI产出的序列帧丢进来即可, 零3D建模) ──
var _sheet_cache := {}
func _sheet(path: String) -> Texture2D:
	if not _sheet_cache.has(path):
		_sheet_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _sheet_cache[path]

func play_sheet_vfx(pos2d: Vector2, sheet: Texture2D, frames: int, world_px: float = 150.0, dur: float = 0.45, h: float = 0.7) -> void:
	if sheet == null:
		return
	var spr := Sprite3D.new()
	spr.texture = sheet
	spr.hframes = frames                              # 横排N帧
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 永远朝相机 → 2D图"立"在3D场景里
	spr.shaded = false
	spr.transparent = true
	var fw: float = float(sheet.get_width()) / float(maxi(1, frames))   # 单帧宽
	spr.pixel_size = (world_px * WS) / fw             # 让特效在场地约 world_px 像素宽
	spr.position = _world_pos(pos2d, h)
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_method(func(fr): spr.frame = clampi(int(fr), 0, frames - 1), 0.0, float(frames), dur)   # 逐帧推进
	t.tween_callback(spr.queue_free)

# 技能光圈: 地面上一个躺平的环, 扩散淡出 (2D 接口对齐 _skill_ring(pos, col, radius))
func _skill_ring(pos2d: Vector2, col: Color, radius: float) -> void:
	var r := Sprite3D.new()
	r.texture = _make_ring_texture(col)
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y          # 躺平贴地
	r.shaded = false
	r.transparent = true
	r.modulate = Color(col.r, col.g, col.b, 1.0)
	r.position = _world_pos(pos2d, 0.05)
	# pixel_size 让环直径 ≈ radius(px) × WS(米/px); ring 贴图 96px 宽
	var target_ps: float = (radius * 2.0 * WS) / 96.0
	r.pixel_size = target_ps * 0.4
	_world.add_child(r)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", target_ps, 0.35)
	tw.tween_property(r, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(r.queue_free)

# 射线: 两点间一条 3D 直线 (水晶球/机甲激光), 快速淡出 (tween 整体 modulate alpha)
func _bolt_line(a2d: Vector2, b2d: Vector2, col: Color) -> void:
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imesh.surface_set_color(col)
	imesh.surface_add_vertex(_world_pos(a2d, 1.0))
	imesh.surface_set_color(col)
	imesh.surface_add_vertex(_world_pos(b2d, 1.0))
	imesh.surface_end()
	_world.add_child(im)
	var tw := _reg_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(im.queue_free)

# ============================================================================
#  §AUDIO 辅助 — 节流封装 (防高频命中音刷屏). 拿不到 Audio autoload 时静默 no-op.
# ============================================================================
func _audio() -> Node:
	return get_node_or_null("/root/Audio")

# 命中音 (普攻/技能/装备直接伤害): 暴击→hit-crit, 否则→hit-physical. 同名音 SFX_HIT_MIN_GAP 内只响一次.
func _sfx_hit(crit: bool) -> void:
	var a := _audio()
	if a == null:
		return
	if crit:
		if _t - _last_crit_sfx_t < SFX_HIT_MIN_GAP:
			return
		_last_crit_sfx_t = _t
		a.play_sfx("hit-crit", 1.0, 1.0, 0.03)
	else:
		if _t - _last_hit_sfx_t < SFX_HIT_MIN_GAP:
			return
		_last_hit_sfx_t = _t
		a.play_sfx("hit-physical", 0.85, 1.0, 0.08)   # pitch/vol 抖动由 Audio 自带 → 连段听感有差

func _sfx_heal() -> void:
	var a := _audio()
	if a == null: return
	if _t - _last_heal_sfx_t < SFX_AUX_MIN_GAP: return
	_last_heal_sfx_t = _t
	a.play_sfx("heal", 1.0, 1.0, 0.04)

func _sfx_shield_gain() -> void:
	var a := _audio()
	if a == null: return
	if _t - _last_shieldgain_sfx_t < SFX_AUX_MIN_GAP: return
	_last_shieldgain_sfx_t = _t
	a.play_sfx("shield-gain", 0.9, 1.0, 0.05)

func _sfx_shield_break() -> void:
	var a := _audio()
	if a == null: return
	if _t - _last_shieldbreak_sfx_t < SFX_AUX_MIN_GAP: return
	_last_shieldbreak_sfx_t = _t
	a.play_sfx("shield-break", 1.0, 1.0, 0.06)

func _sfx_simple(name: String) -> void:    # 复活/失败 等低频事件, 不节流
	var a := _audio()
	if a != null:
		a.play_sfx(name)

# ============================================================================
#  §SKILLVFX 框架 — 技能特效真贴图 (替程序圈). 有匹配贴图才放, 没有静默回退现有程序圈/飘字.
#  _play_skill_vfx(skill_key, pos2d, [height]) → 在该点放一个朝镜头的 billboard:
#    单帧贴图按 SKILL_VFX_WORLD_H 归一 → 一次性 "放大入场 → 保持 → 淡出" tween 后 queue_free.
#  (133 张技能图实测全单帧近方形, 非 spritesheet → 不需逐帧步进; 真要逐帧也能扩 hframes.)
# ============================================================================
func _skill_vfx_tex(name: String) -> Texture2D:
	if name == "":
		return null
	if _skill_vfx_cache.has(name):
		return _skill_vfx_cache[name]
	var path := SKILL_VFX_DIR + name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_skill_vfx_cache[name] = tex          # 缓存 null 也存 (避免反复 exists 探测)
	return tex

# skill_key: 优先按龟 id 查 SKILL_VFX_MAP; 也可直接传贴图名 (装备/特殊技直指定). 找不到 → no-op (保留程序圈).
func _play_skill_vfx(skill_key: String, pos2d: Vector2, height: float = 1.2) -> void:
	if _cam == null:
		return
	var name: String = SKILL_VFX_MAP.get(skill_key, skill_key)
	var tex := _skill_vfx_tex(name)
	if tex == null:
		return                            # 无匹配贴图: 静默回退 (调用点已有 _skill_ring/飘字)
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# 单帧图按 SKILL_VFX_WORLD_H 归一: pixel_size = 目标世界高 / 图高 px
	var th: int = maxi(1, tex.get_height())
	spr.pixel_size = SKILL_VFX_WORLD_H / float(th)
	spr.position = _world_pos(pos2d, height)
	spr.scale = Vector3.ONE * SKILL_VFX_START_SCALE
	_world.add_child(spr)
	# 一次性: 放大入场 → 保持 → 淡出 → 自销 (播一遍消失)
	var tw := _reg_tween()
	tw.tween_property(spr, "scale", Vector3.ONE, SKILL_VFX_GROW_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SKILL_VFX_HOLD_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, SKILL_VFX_FADE_SEC)
	tw.tween_callback(spr.queue_free)

# 通用命中爆发VFX: 单帧burst贴图在pos放大入场→保持→淡出→自销 (A组爆发/溅射类共用)
func _burst_vfx(path: String, pos2d: Vector2, size_px: float, height: float = 0.4) -> void:
	var t: Texture2D = load(path)
	if t == null: return
	var b := Sprite3D.new()
	b.texture = t
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED; b.shaded = false; b.transparent = true
	b.pixel_size = (size_px * WS) / float(maxi(1, t.get_height()))
	b.position = _world_pos(pos2d, height)
	_world.add_child(b)
	var tw := _reg_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.12).from(Vector3.ONE * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.14)
	tw.tween_property(b, "modulate:a", 0.0, 0.3)
	tw.tween_callback(b.queue_free)

# 通用飞行VFX: 贴图从A飞到B (自动识别横排帧动画 nf=宽/高) → 到点自销. delay=起飞延迟(连珠错峰用).
func _fly_vfx(path: String, from2d: Vector2, to2d: Vector2, size_px: float, dur: float, height: float = 1.0, delay: float = 0.0) -> void:
	var t: Texture2D = load(path)
	if t == null: return
	var fh: int = maxi(1, t.get_height())
	var nf: int = maxi(1, int(t.get_width() / fh))
	var spawn := func() -> void:
		var s := Sprite3D.new()
		s.texture = t
		s.hframes = nf
		s.frame = 0
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false; s.transparent = true
		s.pixel_size = (size_px * WS) / float(fh)
		s.position = _world_pos(from2d, height)
		_world.add_child(s)
		var tw2 := _reg_tween()
		tw2.tween_property(s, "position", _world_pos(to2d, height), dur).set_trans(Tween.TRANS_LINEAR)
		if nf > 1:
			tw2.parallel().tween_property(s, "frame", nf - 1, dur)
		tw2.tween_callback(s.queue_free)
	var tw0 := _reg_tween()
	tw0.tween_interval(maxf(0.001, delay))
	tw0.tween_callback(spawn)

# 通用光环VFX(C组半透明): 贴地半透明环罩住单位·跟随单位·淡入→保持→淡出 (仿 _shield_dome/_skill_ring). color含alpha=峰值透明度.
func _aura_vfx(path: String, u: Dictionary, radius_px: float, color: Color, dur: float, height: float = 0.06) -> void:
	var t: Texture2D = load(path)
	if t == null or u == null: return
	var s := Sprite3D.new()
	s.texture = t
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y                       # 躺平贴地
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s.modulate = Color(color.r, color.g, color.b, 0.0)
	s.pixel_size = (radius_px * 2.0 * WS) / float(maxi(1, t.get_height()))
	s.position = _world_pos(u["pos"], height)
	_world.add_child(s)
	_follow_vfx.append({"spr": s, "unit": u, "h": height})
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", color.a, 0.14)
	tw.tween_property(s, "scale", Vector3.ONE, 0.20).from(Vector3.ONE * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(maxf(0.05, dur - 0.5))
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(s.queue_free)

# 通用光束VFX(C组半透明): 贴地长条纹理从A拉到B (激光/索线/拖影/残影). width_px=束宽.
func _beam_vfx(path: String, from2d: Vector2, to2d: Vector2, width_px: float, color: Color, dur: float, height: float = 0.5) -> void:
	var t: Texture2D = load(path)
	if t == null: return
	var wf: Vector3 = _world_pos(from2d, height)
	var wt: Vector3 = _world_pos(to2d, height)
	var seg: Vector3 = wt - wf
	var L: float = seg.length()
	if L < 0.01: return
	var th: int = maxi(1, t.get_height())
	var tw_px: int = maxi(1, t.get_width())
	var ps: float = (width_px * WS) / float(th)
	var s := Sprite3D.new()
	s.texture = t
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s.modulate = Color(color.r, color.g, color.b, 0.0)
	s.pixel_size = ps
	s.position = wf + seg * 0.5
	s.rotation.y = -atan2(seg.z, seg.x)
	s.scale = Vector3(L / maxf(0.001, float(tw_px) * ps), 1.0, 1.0)
	_world.add_child(s)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(s, "modulate:a", color.a, 0.06)
	tw.chain().tween_interval(maxf(0.02, dur - 0.26))
	tw.chain().tween_property(s, "modulate:a", 0.0, 0.20)
	tw.chain().tween_callback(s.queue_free)



# ============================================================================
#  主动技注册表 (28 龟 · 各取规格里的「候选1」) — 逐函数 1:1 搬自 2D 版.
#  完整实装 = ✅ / 简化 = ⚠, 见每条注释. (装备 on-cast 钩子 Phase 3b, 这里不调)
# ============================================================================
# 单体进攻型大招: VFX 落在目标身上 (命中点); 其余(自/队增益·全体)落在施法者身上.
const _SKILL_VFX_ON_TARGET := {
	"ninja": true, "ghost": true, "gambler": true, "headless": true,
	"lightning": true, "two_head": true, "cyber": true,
}
# 自带程序化 VFX 的技能: 跳过通用飘空 billboard (该技在自己函数里画贴地环/击飞等, 更贴 2.5D)
const _SKILL_SELF_VFX := {
	"turtleShieldBash": true,
}
# 自/友向技(护盾/治疗/增益/变身): 不针对敌人, 任意距离即放(不用靠近敌人); 其余(敌向/普攻)要进射程
const _SELF_CAST_SKILLS := {
	"shield": true, "heal": true, "bambooHeal": true, "angelBless": true, "commonTeamShield": true,
	"diamondFortify": true, "crystalBarrier": true, "phoenixShield": true,
	"hidingDefend": true, "hunterStealth": true, "headlessSoulStrike": true, "candyBomb": true, "hidingShrink": true, "hidingBuffSummon": true,
	"cyberHijack": true, "cyberSmartAI": true,
	"lavaSurge": true, "bubbleShield": true, "shellAbsorb": true,
	"fortuneDice": true, "lightningSurgeBuff": true, "chestCount": true,
	"fortuneBuyEquip": true, "phoenixPurify": true, "lightningSurge": true, "lightningShield": true, "rainbowReflect": true,
	"rainbowStorm": true,
	"gamblerBet": true, "stoneTaunt": true, "stoneRockShield": true,
}

# 远程敌向技的专属放技射程(码): 有这条的技能"够得着就放"·不被近战射程卡着(用户2026-07-11: 手里剑是远程技·改2000)
const _SKILL_CAST_RANGE := {"ninjaShuriken": 2000.0}
func _skill_cast_range(u: Dictionary, stype: String) -> float:
	if _SELF_CAST_SKILLS.has(stype): return 99999.0                       # 自/友向: 任意距离即放
	return float(_SKILL_CAST_RANGE.get(stype, u.get("atk_range", 70.0)))  # 远程敌向技用专属射程; 否则=攻击射程(近战贴身放)

# ═══ 选3 多技能轮转 (用户2026-06-28拍板: 保留选3, 让3技在战斗真生效) ═══
# 被动型技 (开局生效, 不进主动轮转; 在 _apply_spawn_passives 里按是否被选施加)
const PASSIVE_SKILL_TYPES := {"iceBurnImmune": true, "shellEnhanceAwaken": true}   # 2026-07-10: lavaEnhancedRage 已废弃(lava技三改 lavaErupt 主动), 其登场 gate 已删; phoenixEnhancedRebirth 仍在用(凤凰技三)

# loadout(选3) 里所有"非普攻"技 type (physical/magic 是普攻=自动, 排除)
# 4选1: 每龟从 skillPool[1..4] 选【1个】(主动或被动); GameState.loadouts[id]=选中索引(默认1=签名候选).
func _resolve_chosen_index(id: String, use_loadout: bool) -> int:
	if _review_demo() and id == _review_turtle() and _review_skill_idx() >= 0:
		return _review_skill_idx()   # 评审指定技(env可覆盖)
	var d: Dictionary = _data_by_id.get(id, {})
	var pool: Array = d.get("skillPool", [])
	var idx := 1                                          # 默认 skillPool[1] (各龟签名候选)
	if use_loadout and GameState.loadouts.has(id):
		var lo = GameState.loadouts[id]
		if lo is int or lo is float:
			idx = int(lo)
		elif lo is Array and not (lo as Array).is_empty():   # 兼容旧"选3"数组: 取首个非普攻索引
			for v in lo:
				if int(v) >= 1:
					idx = int(v); break
	if idx < 1 or idx >= pool.size():
		idx = 1 if pool.size() > 1 else 0
	# 锁默认(Q2): 选中候选若未实装(放不出)→回落默认签名技 idx1, 防选了没主动技. (4选1候选大实装前)
	if idx >= 1 and idx < pool.size():
		var ty := str((pool[idx] as Dictionary).get("type", ""))
		if ty != "" and ty != "physical" and ty != "magic" and not _IMPL_SKILLS.has(ty) and not PASSIVE_SKILL_TYPES.has(ty):
			idx = 1
	return idx

# 选中的那1个技 type (排除普攻; 供主动/被动判定). 返空 = 没选到有效技.
# 墨迹上限: 选「墨水炸弹」→ 全来源上限提到10层(满10层=50%真伤); 否则7层 (用户2026-07-10)
func _ink_cap(src: Dictionary) -> int:
	if src == null: return 7
	return 10 if "lineInkBomb" in _chosen_skill_types(str(src.get("id", "")), src.get("side", "") == "left") else 7

func _chosen_skill_types(id: String, use_loadout: bool) -> Array:
	var d: Dictionary = _data_by_id.get(id, {})
	var pool: Array = d.get("skillPool", [])
	var idx := _resolve_chosen_index(id, use_loadout)
	if idx < 0 or idx >= pool.size():
		return []
	var t := str((pool[idx] as Dictionary).get("type", ""))
	if t == "" or t == "physical" or t == "magic":
		return []
	return [t]

# 进主动轮转的技 (= 选中非普攻技 减去 被动型)
func _resolve_active_skills(id: String, use_loadout: bool) -> Array:
	var out: Array = []
	for t in _chosen_skill_types(id, use_loadout):
		var st := str(t)
		if not PASSIVE_SKILL_TYPES.has(st):
			out.append(st)
	return out

# 实装了的技能 type 集 (与 _do_skill 的 match 保持同步; 用于轮转跳过未实装的, 不浪费龟能/不空放 juice)
const _IMPL_SKILLS := {
	# 签名招 (既有 _sk_* 实装, 按技能 type 分派)
	"bambooHeal": true, "angelBless": true, "angelAscend": true, "stoneRockShield": true, "rockShockwave": true, "stoneTaunt": true, "iceFrost": true, "iceFreeze": true,
	"ninjaBackstab": true, "ghostStorm": true, "ghostPhase": true, "diamondFortify": true, "diceAllIn": true, "diceFlashStrike": true, "commonTeamShield": true,
	"gamblerBet": true, "hunterStealth": true, "pirateCannonBarrage": true, "pirateRum": true, "pirateShipPassive": true, "bubbleShield": true,
	"lineLink": true, "lightningSurgeBuff": true, "phoenixShield": true, "phoenixEnhancedRebirth": true, "headlessFear": true,
	"fortuneDice": true, "crystalBarrier": true, "chestCount": true, "starWave": true,
	"twoHeadStrike": true, "twoHeadDisrupt": true, "twoHeadFusion": true, "lavaSurge": true, "cyberBeam": true, "hidingDefend": true, "shellAbsorb": true,
	# 通用 (多龟共享 type)
	"shield": true, # 数据驱动伤害技 (系数取自 pets.json detail 公式 {N/M/T:...})
	"basicBarrage": true, "basicChiWave": true, "basicSlam": true, "bambooSmack": true, "bambooSpikes": true, "angelEquality": true,
	"ninjaShuriken": true, "ninjaBomb": true, "ghostPhantom": true, "diamondPowerball": true, "diamondSmash": true, "rainbowStorm": true, "gamblerDraw": true, "gamblerFateWheel": true,
	"hunterShot": true, "hunterBarrage": true, "candyBarrage": true, "candyHammer": true, "candyBomb": true, "lightningBarrage": true, "phoenixScald": true,
	"lavaQuake": true, "lavaErupt": true, "crystalBurst": true, "crystalBall": true,
	"chestStorm": true, "headlessTendrils": true, "headlessSoulStrike": true, # Batch2 特殊技 (召唤/控制/处决/复制/梭哈/虫洞 — bespoke)
	"chestCannon": true, "fortuneAllIn": true, "starWormhole": true, "starGravityWarp": true, "lineFinish": true, "lineInkBomb": true,
	"cyberHijack": true, "cyberSmartAI": true, "bubbleBind": true, "bubbleBurst": true, "hidingShrink": true, "hidingBuffSummon": true, "shellCopy": true, "shellShadow": true,
	"diceFate": true,
	# 后4龟补实装的 4选1
	"fortuneBuyEquip": true, "lightningShield": true, "rainbowReflect": true,
}

# 龟能花费表 已移到单一事实源 SkillEnergy (scripts/systems/skill_energy.gd) — 战斗/图鉴/选龟共用
func _skill_cost(u: Dictionary, stype: String) -> float:
	if stype == "lavaErupt" and u.get("volcano", false):
		return 120.0   # 熔岩技三·火山形态版=暴走·龟能单独120(用户2026-07-09"要单独"·熔岩形态智能冲刺仍80)
	return float(u.get("energy_cost", {}).get(stype, SkillEnergy.cost_of(stype)))   # 数据驱动: 优先该龟该技energyCost, 缺则类型兜底

# 该技充满龟能要多少秒 (= 龟能花费 × 0.075; 即所谓"冷却") — 龟盾~5s · 普通~7s · 弹幕~10s · 大招~13s
func _skill_cd(u: Dictionary, stype: String) -> float:
	return _skill_cost(u, stype) * 0.075   # 充满龟能秒数 = 花费×0.075

# 该单位是否有龟能系统 (=能放主动技; 无主动技=纯平A单位, 装备文案里"无龟能的单位")
func _has_energy_system(u: Dictionary) -> bool:
	return not u.get("active_skills", []).is_empty()

# 给单位"+N点龟能": 实时版龟能=冷却充能同一事实, 折算 N×0.075 秒扣掉所有技能剩余冷却.
func _eq_grant_energy(u: Dictionary, amount: float) -> void:   # 给龟能=存"龟能银行"(溢出留到下次不浪费, 用户: 贝母021)
	if amount <= 0.0:
		return
	u["energy_bank"] = float(u.get("energy_bank", 0.0)) + amount
	_apply_energy_bank(u)

func _apply_energy_bank(u: Dictionary) -> void:   # 龟能银行用于减冷却(优先最快就绪技); 冷却吸不下的溢出留在银行(不浪费/放到下次冷却重置后再充)
	var cds: Dictionary = u.get("skill_cd", {})
	if cds.is_empty():
		return
	var bank_sec: float = float(u.get("energy_bank", 0.0)) * 0.075
	if bank_sec <= 0.0:
		return
	var keys: Array = cds.keys()
	keys.sort_custom(func(a, b): return float(cds[a]) < float(cds[b]))
	for k in keys:
		if bank_sec <= 0.0: break
		var reduce: float = minf(float(cds[k]), bank_sec)
		cds[k] = float(cds[k]) - reduce
		bank_sec -= reduce
	u["energy_bank"] = bank_sec / 0.075   # 剩余溢出留着

# shellCopy 可复制的技 = 纯敌方向伤害技 (数据驱动那批; 排除变身/召唤/自增益, 否则从龟壳放会污染自身状态)
const _COPYABLE_SKILLS := {
	"basicBarrage": true, "basicChiWave": true, "basicSlam": true, "bambooLeaf": true, "bambooSmack": true, "bambooSpikes": true, "angelEquality": true,
	"iceSpike": true, "ninjaShuriken": true, "ninjaBomb": true, "twoHeadMagicWave": true,
	"ghostTouch": true, "ghostPhantom": true, "diamondPowerball": true, "diamondSmash": true, "fortuneStrike": true,
	"diceAttack": true, "rainbowStorm": true, "gamblerCards": true, "gamblerDraw": true, "gamblerFateWheel": true,
	"hunterShot": true, "hunterBarrage": true, "candyBarrage": true, "candyHammer": true, "candyBomb": true, "lineSketch": true,
	"lightningStrike": true, "lightningBarrage": true, "phoenixBurn": true, "phoenixScald": true,
	"lavaBolt": true, "lavaQuake": true, "lavaErupt": true, "crystalSpike": true, "crystalBurst": true, "crystalBall": true,
	"chestStorm": true, "starBeam": true, "headlessTendrils": true, "headlessSoulStrike": true, "shellStrike": true, "chestCannon": true,
}

# 逐技独立冷却: 放【冷却好了的、可放的、强度最高的】那个 (大招好了优先放, 小技填空档) — 各技各自节奏.
# 挑一个【冷却好了的、可放的、强度最高的】技 type, 没有则返 "" (状态机用: 决定要不要进施法前摇).
func _pick_ready_skill(u: Dictionary) -> String:
	if _t < float(u.get("skill_gcd_until", 0.0)):
		return ""
	var cds: Dictionary = u.get("skill_cd", {})   # 召唤体无 skill_cd → 空, 无主动技返 ""(防崩)
	var best := ""
	var best_cost := -1.0
	for s in u.get("active_skills", []):
		var st := str(s)
		if not _IMPL_SKILLS.has(st):
			continue
		if st == "fortuneAllIn" and u.get("allin_used", false):
			continue
		if float(cds.get(st, 0.0)) > 0.0:
			continue
		var c := _skill_cost(u, st)
		if c > best_cost:
			best_cost = c; best = st
	return best

const SEP_PUSH_SPD := 168.0                  # 软分离推开速度 (px/s; 每帧全单位) — 调快点更快散开不糊一起
func _apply_separation_pass(delta: float) -> void:   # 每帧全单位软分离: 摊开防扎堆遮血条; 但已交战的近战定身不推(见下)
	for u in _units:
		if not u["alive"] or u.get("no_move", false) or u.get("airborne", false) or u.get("_slam", false) or u.get("roll_active", false):
			continue
		# ★用户2026-07-11「近战靠近后应停止移动、定身攻击、收手, 别一直挤」:
		#   已进攻击射程(交战)的近战 → 完全不被分离推 → 贴脸定身开打(根治"打起来一直挤")。
		var _mt = u.get("_sep_target")
		if bool(u.get("melee", false)) and _mt is Dictionary and (_mt as Dictionary).get("alive", false) and u["pos"].distance_to((_mt as Dictionary)["pos"]) <= float(u.get("atk_range", 70.0)) + 10.0:
			continue
		var _st := str(u.get("state", "move"))
		var _sepmul: float = 0.4 if _st == "windup" else 1.0   # 前摇大体钉住(不挤着冲)但给40%分离→防完全叠一起; 后摇(orb-walk自由)/移动=全分离
		var push: Vector2 = _separation(u)
		if push.length() > 0.001:
			u["pos"] += push.limit_length(1.0) * SEP_PUSH_SPD * _sepmul * delta
			u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
			u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

# 移动; no_move 召唤体定点不动. 分离已移到 _apply_separation_pass. (状态机仅"move"态调)
func _do_move(u: Dictionary, tgt: Dictionary, dist: float, rng: float, spd: float, delta: float) -> void:
	if u.get("no_move", false):
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var intent := Vector2.ZERO
	if dist > rng:
		var straight: Vector2 = to_t / maxf(0.001, dist)
		var dir: Vector2 = _nav_dir(u, tgt["pos"], straight)  # navmesh 绕障(无路径退回直奔)
		intent = dir                                          # 追到射程
		for o in _units:   # 绕行避挤: 正前方窄道有同队友军挡路→切向绕开(不再直挤成一团/根治"第二个挤第一个不绕路")
			if o == u or not o.get("alive", false) or str(o.get("side", "")) != str(u.get("side", "")):
				continue
			var rel: Vector2 = o["pos"] - u["pos"]
			var ahead: float = rel.dot(dir)                       # 在我前方(朝目标)多远
			if ahead <= 5.0 or ahead > 95.0:
				continue
			var side: float = rel.dot(Vector2(-dir.y, dir.x))     # 横向偏移(是否在正前窄道)
			if absf(side) > 52.0:
				continue
			var tang: Vector2 = Vector2(-dir.y, dir.x)
			if side > 0.0:
				tang = -tang                                      # 往挡路友军的反侧绕
			intent = (dir + tang * 1.5).normalized()
			break
	elif not u["melee"] and dist < rng * 0.7:
		intent = -to_t.normalized()                          # 远程太近→风筝后撤
	# 分离已移到 _apply_separation_pass (每帧全单位, 不只move态) → 根治攻击/待机扎堆
	if intent.length() > 0.01:
		u["vel"] = intent.limit_length(1.0) * spd            # 合力调速, 力抵消缓停
		u["pos"] += u["vel"] * delta
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		var _slowed: bool = _t < float(u.get("slow_until", 0.0)) or (_t < float(u.get("spd_dbf_until", 0.0)) and float(u.get("spd_move_mult", 1.0)) < 0.99)
		if _slowed:   # 全局: 被减速单位行走留短暂泥印(非脚印, 节流)
			u["_mud_t"] = float(u.get("_mud_t", 0.0)) + delta
			if float(u["_mud_t"]) >= 0.16:
				u["_mud_t"] = 0.0
				_mud_mark(u["pos"])

# 放单个技 (按 type): 实装→juice+VFX+效果 返 true; 未实装→返 false (轮转跳过, 不空放).
func _cast_skill(u: Dictionary, tgt: Dictionary, stype: String) -> bool:
	if not _IMPL_SKILLS.has(stype):
		return false
	if stype == "fortuneAllIn" and u.get("allin_used", false):
		return false                                  # 梭哈一场限一次, 用过则轮转跳过不空放
	_anticipate(u)                  # 放大招前预备(缩)→挥出(伸) 形变
	_shake(JUICE_SHAKE_HEAVY)       # 大招释放 = 轻震屏
	# 施法技能不用飘空图标 (用户定): 技能视觉靠各自 _skill_ring/投射物/形变, 不浮贴图 billboard
	# (原通用 _play_skill_vfx 飘空贴图已禁用 — 一张图标浮半空不贴 2.5D)
	_do_skill(u, tgt, stype)
	_log("[color=%s]✦ %s[/color] 施放 [color=#ffe08a]%s[/color]" % [_log_side_hex(u), _unit_name(u), _skill_disp(stype)])
	return true

# 技能 type → VFX 贴图名 (pets.json skillPool[].icon "skills/x.png" → "x"); 无则空串(回退签名)
func _skill_vfx_name(stype: String) -> String:
	var icon: String = str((_skill_meta.get(stype, {}) as Dictionary).get("icon", ""))
	return icon.get_file().get_basename() if icon != "" else ""

func _do_skill(u: Dictionary, tgt: Dictionary, stype: String) -> void:
	match stype:
		# ── 各龟签名招 (既有实装, 按 type 分派) ──
		"bambooHeal":           _sk_bamboo_heal(u)
		"angelBless":           _sk_angel_bless(u)
		"angelAscend":          _sk_angel_ascend(u)
		"iceFrost":             _sk_ice_frost(u, tgt)
		"iceFreeze":            _sk_ice_freeze(u, tgt)
		"commonTeamShield":     _sk_ice_team_shield(u)
		"fortuneBuyEquip":      _sk_fortune_buyequip(u)
		"lightningShield":      _sk_lightning_shield(u)
		"rainbowReflect":       _sk_rainbow_reflect(u)
		"ninjaBackstab":        _sk_ninja_backstab(u, tgt)
		"ghostStorm":           _sk_ghost_soulstorm(u, tgt)
		"ghostPhase":           _sk_ghost_phase(u, tgt)
		"diamondFortify":       _sk_diamond_unbreak(u)
		"diceAllIn":            _sk_dice_allin(u)
		"diceFlashStrike":      _sk_dice_flash_strike(u)
		"gamblerBet":           _sk_gambler_bet(u, tgt)
		"gamblerFateWheel":     _sk_gambler_fate_wheel(u)
		"hunterStealth":        _sk_hunter_hide(u)
		"pirateCannonBarrage":  _sk_pirate_volley(u, tgt)
		"pirateRum":            _sk_pirate_rum(u)
		"pirateShipPassive":    _sk_pirate_ship(u, tgt)
		"bubbleShield":         _sk_bubble_shield(u, tgt)
		"lineLink":             _sk_line_link(u)
		"lightningSurgeBuff":   _sk_lightning_surge(u, tgt)
		"phoenixShield":        _sk_phoenix_lavashield(u)
		"phoenixEnhancedRebirth": _sk_phoenix_haste(u)
		"headlessFear":         _sk_headless_fear(u, tgt)
		"fortuneDice":          _sk_fortune_dice(u)
		"crystalBarrier":       _sk_crystal_bulwark(u)
		"chestCount":           _sk_chest_inventory(u)
		"starWave":             _sk_star_wave(u)
		"twoHeadStrike":        _sk_two_head_strike(u, tgt)
		"twoHeadDisrupt":       _sk_two_head_disrupt(u, tgt)
		"twoHeadFusion":        _sk_two_head_fusion(u, tgt)
		"lavaSurge":            _sk_lava_cast(u, tgt, "B")   # 岩浆涌动 (修: 原走set A=地裂)
		"lavaErupt":            _sk_lava_erupt(u, tgt)       # 技三: 智能冲刺+穿透普攻 / 火山暴走
		"cyberBeam":            _sk_cyber_cannon(u, tgt)
		"hidingDefend":         _sk_hiding_defend(u)
		"shellAbsorb":          _sk_shell_absorb(u, tgt)
		# ── 通用 (多龟共享 type) ──
		"shield":               _sk_gen_shield(u)
		"stoneRockShield":      _sk_stone_rock_shield(u)
		"rockShockwave":        _sk_rock_shockwave(u)
		"stoneTaunt":           _sk_stone_taunt(u)
		# ── 数据驱动伤害技 (系数取自 detail 公式; N=物理 M=魔法 T=真实) ──
		"basicBarrage":         _sk_basic_strike(u, tgt)
		"basicChiWave":         _sk_basic_chiwave(u, tgt)
		"basicSlam":            _sk_basic_slam(u, tgt)
		"bambooSmack":          _sk_bamboo_smack(u, tgt)
		"bambooSpikes":         _sk_bamboo_spikes(u, tgt)
		"angelEquality":        _sk_angel_equality(u, tgt)
		"ninjaShuriken":        _sk_ninja_shuriken(u, tgt)
		"ninjaBomb":            _sk_ninja_bomb(u, tgt)
		"ghostPhantom":         _sk_dmg(u, tgt, {"magic": 1.5, "hits": 1, "lifesteal": 0.8, "selfDodge": 0.25, "selfDodgeDur": 4.0, "name": "幻影!", "color": Color("#c77dff")})   # 闪避4秒(用户2026-07-09·回合制"2回合")
		"diamondPowerball":     _sk_diamond_powerball(u, tgt)
		"diamondSmash":         _sk_diamond_smash(u, tgt)
		"rainbowStorm":         _sk_rainbow_storm(u)
		"gamblerDraw":          _sk_gambler_wild(u, tgt)   # 万能牌(默认签名技): 原来错派纯伤害, 改回 _sk_gambler_wild(2段+盾+治疗+减益)
		"hunterShot":           _sk_hunter_shot(u, tgt)
		"hunterBarrage":        _sk_hunter_barrage(u, tgt)
		"candyBarrage":         _sk_candy_barrage(u, tgt)
		"candyHammer":          _sk_candy_hammer(u, tgt)
		"candyBomb":            _sk_candy_bomb_feed(u)
		"lightningBarrage":     _sk_lightning_barrage(u)
		"phoenixScald":         _sk_phoenix_scald(u, tgt)
		"lavaQuake":            _sk_lava_cast(u, tgt, "A")   # 地裂(默认): 修-原派_sk_dmg带slow→应_lava_quake(全体魔+削魔抗20%)
		"crystalBurst":         _sk_crystal_burst(u, tgt)
		"crystalBall":          _sk_crystal_orb(u, tgt)
		"chestStorm":           _sk_chest_storm(u, tgt)
		"headlessTendrils":     _sk_headless_tendrils(u, tgt)
		"headlessSoulStrike":   _sk_headless_soul_charge(u)
		"chestCannon":          _sk_chest_cannon(u, tgt)
		# ── Batch2 特殊技 (bespoke) ──
		"fortuneAllIn":         _sk_fortune_allin(u, tgt)
		"starWormhole":         _sk_star_wormhole(u, tgt)
		"starGravityWarp":      _sk_star_gravity_warp(u)
		"lineFinish":           _sk_line_finish(u)
		"lineInkBomb":          _sk_line_ink_bomb(u)
		"cyberHijack":          _sk_cyber_hijack(u)
		"cyberSmartAI":         _sk_cyber_smart(u)
		"bubbleBind":           _sk_bubble_bind(u, tgt)
		"bubbleBurst":          _sk_bubble_burst(u, tgt)
		"hidingShrink":         _sk_hiding_shrink(u)
		"hidingBuffSummon":     _sk_hiding_buff(u)
		"shellCopy":            _sk_shell_copy(u, tgt)
		"shellShadow":          _sk_shell_shadow_dive(u, tgt)
		"diceFate":             _sk_dice_fate(u)

func _sk_basic_shield(u: Dictionary, tgt: Dictionary) -> void:   # 小龟·龟盾 ✅
	var lost: float = (tgt["maxHp"] - tgt["hp"]) * 0.20
	var raw: float = u["atk"] * 0.7
	var dmg := _atk_dmg(u, 0.7, tgt) + int(lost)
	_apply_damage_from(u, tgt, dmg, Color("#ff4444"))
	_grant_shield(u, (raw + lost) * 0.80)
	_knockback(u, tgt, 60.0)                                       # 击飞+击退 (3D真物理: vy抬起+横推+重力砸地)
	# 程序化 VFX (贴 2.5D, 不用回合制序列帧): 盾砸地贴地金色冲击波 + 小龟获盾金环
	_skill_ring(tgt["pos"], Color(1.0, 0.85, 0.2, 0.6), 72.0)      # 目标: 盾砸地 贴地冲击波
	_skill_ring(u["pos"], Color(1.0, 0.9, 0.45, 0.45), 48.0)       # 小龟: 获盾 身下金环

## 可【主动锁定】的敌人 (排除: 围栏未破的蛋 / 黑洞不可选 / 缩头随从被保护) — 主动瞄准类用.
##   ★用户2026-07-11: 被围栏围住的蛋不能被主动锁(气波别瞄它); 但 AoE穿透/路径命中 仍能打到蛋(受伤可以, 走 _enemies_of/_basic_first_blocker 不受此限)。
func _targetable_enemies(u: Dictionary) -> Array:
	var out: Array = []
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o.get("_egg_fence", false): continue
		if _t < float(o.get("untargetable_until", 0.0)): continue
		if o.get("hiding_protected", false):
			var ow = o.get("summon_owner", null)
			if ow != null and ow.get("alive", false): continue
		out.append(o)
	return out

func _basic_first_blocker(u: Dictionary, dir: Vector2):          # 可被挡直线弹道: 返回dir方向路径上第一个"敌/蛋"(障碍穿过·我方不挡·走_enemies_of天然含蛋不含友)
	var best = null
	var bestd: float = INF
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = rel.dot(dir)
		if along < 0.0: continue
		if (rel - dir * along).length() > 55.0: continue
		if along < bestd: bestd = along; best = o
	return best

func _sk_basic_strike(u: Dictionary, _tgt = null) -> void:      # 小龟·打击(封板·10波序列驱动·80龟能): 全程定身·10波每0.15s·每波随机挑1存活敌当方向·气波可被挡(命中路径第一敌/蛋)·每波0.4A(吃不屈)·[慢飞弹道视觉留F5]
	u["stun_until"] = maxf(float(u.get("stun_until", 0.0)), _t + 1.65)   # 全程定身(10波×0.15s)
	for i in range(10):
		var fn := func():
			var es: Array = _targetable_enemies(u)   # ★方向只从可主动锁的敌里挑(排围栏未破的蛋); 穿过打到蛋仍算(_basic_first_blocker)
			var dir: Vector2 = Vector2.RIGHT
			if not es.is_empty():
				var dt = es[i % es.size()]                       # 随机分布(轮询近似)挑1存活敌当方向
				var dd: Vector2 = dt["pos"] - u["pos"]
				if dd.length() > 1.0: dir = dd.normalized()
			var hit = _basic_first_blocker(u, dir)               # 命中路径第一个敌/蛋(可被挡)
			var end_pos: Vector2 = u["pos"] + dir * 420.0
			if hit != null:
				end_pos = hit["pos"]                              # 打到人就停在人身上(不穿透飞满420码)
			var flight: float = clampf(u["pos"].distance_to(end_pos) / 380.0, 0.12, 1.2)   # 恒速~380码/秒(满420码≈1.1s·慢)
			_fly_vfx("res://assets/sprites/vfx/qibo-ball.png", u["pos"], end_pos, 52.0, flight, 1.0)   # 打击气波弹
			if hit != null:                                      # ★伤害同步到气波【视觉命中】(不再放技瞬间掉血·用户2026-07-11)
				var _h: Dictionary = hit
				_pending_shots.append({"delay": flight, "fn": func() -> void:
					if _h.get("alive", false):
						_apply_damage_from(u, _h, _atk_dmg(u, 0.4, _h), Color("#ff4444"))
					, "src": u})
		_pending_shots.append({"delay": float(i) * 0.15, "fn": fn, "src": u})

# 气波从 from2d 打向 tgt 时能命中几个敌 (带宽80·射程900) — 供智能位移冲刺评估
func _chiwave_hits_from(u: Dictionary, from2d: Vector2, tgt: Dictionary) -> int:
	var d: Vector2 = tgt["pos"] - from2d
	if d.length() < 1.0: return 0
	d = d.normalized()
	var n := 0
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(from2d) > 900.0: continue
		if _on_line(from2d, d, o["pos"], 80.0): n += 1
	return n

# 候选落点是否贴脸(离任一敌 < min_gap) — 用户"不是贴人家脸上·要考虑碰撞体积"
func _too_close_to_enemy(u: Dictionary, p: Vector2, min_gap: float) -> bool:
	for o in _enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(p) < min_gap: return true
	return false

func _sk_basic_chiwave(u: Dictionary, tgt) -> void:            # 小龟·龟派气波(封板·100龟能): 先自增buff(暴击25%/暴伤20%/吸血10%/护穿0.1A·3秒)→朝当前目标发穿透气波(带宽80·打沿途所有敌+蛋)每命中3.5A物理+击飞1.5s+击退200 [智能位移留F5]
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var ap: float = u["atk"] * 0.1
	u["crit"] = float(u["crit"]) + 0.25
	u["crit_dmg"] = float(u["crit_dmg"]) + 0.20
	u["lifesteal"] = float(u["lifesteal"]) + 0.10
	u["armor_pen"] = float(u.get("armor_pen", 0.0)) + ap
	var uu: Dictionary = u
	_pending_shots.append({"delay": 3.0, "fn": func():          # 3秒后撤销自增buff
		uu["crit"] = float(uu["crit"]) - 0.25
		uu["crit_dmg"] = float(uu["crit_dmg"]) - 0.20
		uu["lifesteal"] = float(uu["lifesteal"]) - 0.10
		uu["armor_pen"] = float(uu.get("armor_pen", 0.0)) - ap, "src": u})
	# 蓄力时的智能位移冲刺 ≤300码 (用户2026-07-05"小龟可以选择一次300码内的位移冲刺·奔向能打到更多人的位置·但不是贴人家脸上·要考虑碰撞体积")
	var _bp: Vector2 = u["pos"]
	var _bn: int = _chiwave_hits_from(u, u["pos"], tgt)
	for _a in range(12):                                        # 12方向 × 3档距离 采样
		var _ad: Vector2 = Vector2(cos(float(_a) * TAU / 12.0), sin(float(_a) * TAU / 12.0))
		for _r in [120.0, 210.0, 300.0]:
			var _cand: Vector2 = u["pos"] + _ad * _r
			if _too_close_to_enemy(u, _cand, 120.0): continue   # 不贴脸(碰撞体积)
			var _cn: int = _chiwave_hits_from(u, _cand, tgt)
			if _cn > _bn:
				_bn = _cn; _bp = _cand
	if _bp != u["pos"]:                                         # 能打到更多人才冲
		_beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], _bp, 52.0, Color(0.6, 0.92, 1.0, 0.6), 0.30)   # 冲刺拖影
		var _ds: Vector2 = u["pos"]
		var _ddur: float = clampf(_ds.distance_to(_bp) / 900.0, 0.10, 0.35)   # ★冲刺=滑行非瞬移(用户2026-07-11)·~900码/秒
		u["no_move"] = true; u["no_basic"] = true
		var _del: float = 0.0
		while _del < _ddur and u.get("alive", false) and is_inside_tree():
			await get_tree().process_frame
			_del += get_process_delta_time()
			u["pos"] = _ds.lerp(_bp, clampf(_del / _ddur, 0.0, 1.0))
		u["pos"] = _bp
		u["no_move"] = false; u["no_basic"] = false
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	u["stun_until"] = maxf(float(u.get("stun_until", 0.0)), _t + 0.6)   # 掌心聚气 0.6s 定身(生成动画期间)
	var start2: Vector2 = u["pos"]
	var uu2: Dictionary = u
	# ── 生成动画(掌心聚气): 回合制提取 chiwave-spawn 6帧×0.1s=0.6s 播一遍 ──
	var sp := Sprite3D.new()
	sp.texture = load("res://assets/sprites/vfx/chiwave-spawn.png")
	sp.hframes = 6; sp.frame = 0
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED; sp.axis = Vector3.AXIS_Y; sp.rotation.y = -atan2(dir.y, dir.x); sp.shaded = false; sp.transparent = true   # 生成也躺平+转向(与飞行一致·用户2026-07-11)
	sp.pixel_size = (130.0 * WS) / 128.0
	sp.position = _world_pos(start2, 0.25)   # 贴地(与飞行同高)
	_world.add_child(sp)
	var stw := _reg_tween()
	stw.tween_method(func(fv: float) -> void: sp.frame = mini(5, int(fv)), 0.0, 6.0, 0.6)   # 6帧播一遍 0→5
	stw.tween_callback(sp.queue_free)
	# ── 0.6s聚气后 → 发射飞行波(chiwave-fly 6帧循环·恒速300码/秒·伤害随球扫过结算) ──
	_pending_shots.append({"delay": 0.6, "fn": func() -> void:
		if not uu2.get("alive", false): return
		var launch: Vector2 = uu2["pos"]
		var ball := Sprite3D.new()
		ball.texture = load("res://assets/sprites/vfx/chiwave-fly.png")
		ball.hframes = 6; ball.frame = 0
		ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		ball.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ball.axis = Vector3.AXIS_Y; ball.rotation.y = -atan2(dir.y, dir.x); ball.shaded = false; ball.transparent = true   # ★躺平贴地+转向行进方向(用户2026-07-11); 头尾反了→rotation加PI
		ball.flip_h = false   # 方向靠 rotation.y(躺平), 不 flip
		ball.pixel_size = (150.0 * WS) / 128.0
		ball.position = _world_pos(launch, 0.25)   # 贴地低空(躺平)
		_world.add_child(ball)
		var hit2: Array = []   # Array(.has 走 ==) 防拿单位字典当 Dict key 的 recursive_hash 崩(2026-07-10教训)
		var step2 := func(d: float) -> void:
			var c: Vector2 = launch + dir * d
			if is_instance_valid(ball):
				ball.position = _world_pos(c, 0.25)
				ball.frame = int(d / 30.0) % 6                     # 飞行帧循环: 每30码换帧(≈0.1s @300码/秒)
			for o in _enemies_of(uu2):
				if not o.get("alive", false) or hit2.has(o): continue
				if not _on_line(launch, dir, o["pos"], 80.0): continue
				if o["pos"].distance_to(c) > 95.0: continue
				hit2.append(o)
				_apply_damage_from(uu2, o, _atk_dmg(uu2, 3.5, o), Color("#7fd0ff"))
				_knockback(uu2, o, 200.0, 2.752, 2.0)              # 击飞1.5s+击退200
		var btw := _reg_tween()
		btw.tween_method(step2, 0.0, 900.0, 3.0).set_trans(Tween.TRANS_LINEAR)
		btw.tween_callback(ball.queue_free)
		, "src": u})

func _sk_basic_slam(u: Dictionary, tgt) -> void:  # 小龟·过肩摔(#7重做·Sett R式完整编排): 擒抱→跳空→与敌反转180°→坠落→落地范围伤+尘爆; 蛋免控只吃原地伤
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var tmax: float = float(tgt["maxHp"])
	if tgt.get("_eggImmune", false):   # 蛋: 不擒抱/不挑空, 只吃原地范围伤
		_slam_apply_damage(u, tgt, tmax)
		_burst_vfx("res://assets/sprites/vfx/dust-impact.png", tgt["pos"], 190.0, 0.35)
		_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", tgt["pos"], 250.0, 0.06)
		return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var u_start: Vector2 = u["pos"]
	var land: Vector2 = u_start - dir * 55.0    # 落点=龟背后~55码(过肩摔到身后)
	land.x = clampf(land.x, ARENA.position.x + 20.0, ARENA.end.x - 20.0)
	land.y = clampf(land.y, ARENA.position.y + 20.0, ARENA.end.y - 20.0)
	_basic_slam_run(u, tgt, dir, u_start, land, tmax)   # async 编排(fire-and-forget)

## 过肩摔伤害结算(主目标 0.7A+26%maxHp / 周围250码 0.2A+19%主maxHp) — 落地时调.
func _slam_apply_damage(u: Dictionary, tgt: Dictionary, tmax: float) -> void:
	if tgt.get("alive", false):
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.7, tgt) + int(tmax * 0.26), Color("#ff9d5c"))
	for o in _enemies_of(u):
		if o == tgt or not o.get("alive", false): continue
		if o["pos"].distance_to(tgt["pos"]) <= 350.0:   # 范围 350码(用户2026-07-11: 250→350)
			_apply_damage_from(u, o, _atk_dmg(u, 0.2, o) + int(tmax * 0.19), Color("#ff9d5c"))

## 过肩摔完整编排(#7·用户2026-07-11): 擒抱→双方跳空(_slam_voff)→空中反转180°(flip_v)→坠落→落地范围伤+大尘爆+震屏. 双方 _slam 冻结.
func _basic_slam_run(u: Dictionary, tgt: Dictionary, dir: Vector2, u_start: Vector2, land: Vector2, tmax: float) -> void:
	var uspr = u.get("sprite", null)
	var tspr = tgt.get("sprite", null)
	u["_slam"] = true
	tgt["_slam"] = true
	tgt["no_move"] = true
	var e_start: Vector2 = tgt["pos"]
	var T_GRAB := 0.15
	var T_AIR := 0.5   # 更慢(用户2026-07-11)
	var T_FALL := 0.32
	var total := T_GRAB + T_AIR + T_FALL
	var el := 0.0
	var flipped := false
	var p := 0.0
	while el < total and u.get("alive", false) and tgt.get("alive", false) and is_inside_tree():
		await get_tree().process_frame
		el += get_process_delta_time()
		if el < T_GRAB:                                     # ① 擒住: 敌拉到龟身前
			p = el / T_GRAB
			tgt["pos"] = e_start.lerp(u_start, p)
		elif el < T_GRAB + T_AIR:                           # ② 跳空 + 抡向落点 + 空中反转
			p = (el - T_GRAB) / T_AIR
			var hy := sin(p * PI * 0.5)                     # ease 上升到 apex
			tgt["_slam_voff"] = Vector3(0.0, 5.4 * hy, 0.0)
			u["_slam_voff"] = Vector3(0.0, 4.0 * hy, 0.0)
			tgt["pos"] = u_start.lerp(land, p)              # 敌被抡向落点
			u["pos"] = u_start - dir * (18.0 * sin(p * PI)) # 龟小后仰再回
			if p > 0.45 and not flipped:                    # 空中反转180°(billboard→flip_v 上下颠倒)
				flipped = true
				if is_instance_valid(uspr): uspr.flip_v = true
				if is_instance_valid(tspr): tspr.flip_v = true
		else:                                               # ③ 坠落: 猛砸下
			p = (el - T_GRAB - T_AIR) / T_FALL
			var fall := 1.0 - p
			tgt["_slam_voff"] = Vector3(0.0, 5.4 * fall, 0.0)
			u["_slam_voff"] = Vector3(0.0, 4.0 * fall, 0.0)
			tgt["pos"] = land
			u["pos"] = land + dir * 45.0
	# ④ 落地结算: 复位翻转/偏移 + 眩晕 + 范围伤 + 大尘爆 + 震屏
	if is_instance_valid(uspr): uspr.flip_v = false
	if is_instance_valid(tspr): tspr.flip_v = false
	u["_slam_voff"] = Vector3.ZERO
	tgt["_slam_voff"] = Vector3.ZERO
	u["pos"] = land + dir * 45.0
	if tgt.get("alive", false):
		tgt["pos"] = land
		tgt["stun_until"] = maxf(float(tgt.get("stun_until", 0.0)), _t + _cc_dur(tgt, 0.5))   # 砸地眩晕0.5s
		_flash(tgt)
	_slam_apply_damage(u, tgt, tmax)
	_shake(JUICE_SHAKE_BIG)                        # 大砸=大震屏(用户2026-07-11: 表现大范围砸击)
	_hitstop = maxf(_hitstop, 0.1)                 # 顿帧(重量感)
	_impact_particles(land, 0.0)                   # 落地碎屑迸发
	_burst_vfx("res://assets/sprites/vfx/dust-impact.png", land, 520.0, 0.6)      # 落地大尘爆
	_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", land, 680.0, 0.14)   # 范围冲击环(=350码伤害圈)
	_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", land, 940.0, 0.32)   # 二道扩散环(大·慢)→强调大范围砸击
	u["_slam"] = false
	tgt["_slam"] = false
	tgt["no_move"] = false

func _sk_stone_rock_shield(u: Dictionary) -> void:               # 石头龟·岩石护盾(用户设计: 合并岩石护甲+磐石·100龟能): 全队盾0.2A+5%maxHp + 自身双抗+20%5秒
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 1.0 + u["maxHp"] * 0.06, 4.0)   # 全队盾=1×石头ATK+6%【石头龟】最大生命(用户2026-07-11: 0.2A+5%→1A+6%)·每友军等量·4秒
		o["rock_shield_until"] = _t + 4.0                          # 标记"石头岩石护盾"来源: LoL式六棱屏障VFX + 锁龟能(持盾期不充能), 盾破/到期即释放(用户2026-07-11)
		_skill_ring(o["pos"], Color(0.79, 0.64, 0.42, 0.45), 46.0)
	_buff(u, "def", 0.2, true, 5.0)   # 自身护甲+20%(pct·5秒)
	_buff(u, "mr", 0.2, true, 5.0)    # 自身魔抗+20%

func _sk_rock_shockwave(u: Dictionary) -> void:                  # 石头龟·岩石之躯 主动: 前方带状(±90)岩脊向前破土推进, (0.5DEF+0.5MR)×(1+4%岩层)物理 + 1%×层眩晕1.5s + 击退60; 伤害随波前经过逐个同步(用户2026-07-11补VFX·原=只1个130px环)
	var tgt = _acquire_target(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var layers: int = int(u.get("rock_layers", 0))
	var origin: Vector2 = u["pos"]
	var uu := u
	var windup := 0.16                                       # 起手踏地时长
	var wave_spd := 900.0                                    # 岩脊波前推进速度(码/秒)
	# ── 起手: 石头抬身猛踏(_slam_voff 抬→砸) ──
	var smt := _reg_tween()
	smt.tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.0, 0.55, 0.1).set_ease(Tween.EASE_OUT)
	smt.chain().tween_method(func(v: float): uu["_slam_voff"] = Vector3(0.0, v, 0.0), 0.55, 0.0, 0.06).set_ease(Tween.EASE_IN)
	smt.chain().tween_callback(func(): uu["_slam_voff"] = Vector3.ZERO)
	# ── 踏地瞬间(windup 后): 震屏+顿帧+脚下碎石+起手环 ──
	var wf := func() -> void:
		_shake(JUICE_SHAKE_HEAVY); _hitstop = maxf(_hitstop, 0.05)
		_impact_particles(origin, 0.0)
		_burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", origin, 210.0, 0.06)
		_skill_ring(origin, Color(0.79, 0.64, 0.42, 0.6), 120.0)
	_pending_shots.append({"delay": windup, "src": u, "fn": wf})
	# ── 岩脊沿 dir 向前破土推进(铺满带宽·波前渐进) ──
	var reach := 820.0
	var step := 44.0
	var d := 34.0
	while d < reach:
		var cp: Vector2 = origin + dir * d
		var dl: float = windup + d / wave_spd
		var pa: Vector2 = cp + perp * randf_range(-32.0, 32.0)
		var fa := func() -> void: _rock_chunk_erupt(pa)
		_pending_shots.append({"delay": dl, "src": u, "fn": fa})
		if randf() < 0.7:
			var pb: Vector2 = cp + perp * randf_range(-86.0, 86.0)
			var fb := func() -> void: _rock_chunk_erupt(pb)
			_pending_shots.append({"delay": dl, "src": u, "fn": fb})
		d += step
	# ── 伤害: 前方带状(几何不变)·随波前经过逐个同步结算 ──
	var dmgv: int = int((u["def"] * 0.5 + u["mr"] * 0.5) * (1.0 + 0.04 * layers))
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - origin
		if rel.dot(dir) <= 0.0: continue                     # 只前方
		if absf(rel.dot(perp)) > 90.0: continue              # 带宽~180
		var oo = o
		var hit_delay: float = windup + maxf(0.0, rel.dot(dir)) / wave_spd
		var hf := func() -> void:
			if not oo.get("alive", false): return
			_apply_damage_from(uu, oo, dmgv, Color("#c8a878"))
			oo["stun_until"] = maxf(float(oo.get("stun_until", 0.0)), _t + _cc_dur(oo, 2.0))   # 命中即眩晕2秒(用户2026-07-11: 除击退外必附2s眩晕·原1%×层概率改必中·头顶通用眩晕圈由_update_stun_vfx画)
			_knockback(uu, oo, 60.0)
			_rock_chunk_erupt(oo["pos"])                     # 命中点额外破土
			_flash(oo)
		_pending_shots.append({"delay": hit_delay, "src": u, "fn": hf})

func _rock_chunk_erupt(pos2d: Vector2) -> void:   # 岩石破土冒起(石棕灰)→短留→碎(仿 _gold_chunk_erupt·换石色)
	var tex: Texture2D = load("res://assets/sprites/vfx/gold-chunk.png")
	if tex == null: return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.modulate = Color(randf_range(0.5, 0.62), randf_range(0.44, 0.54), randf_range(0.36, 0.44), 0.0)   # 石棕灰·起始透明
	var sc: float = randf_range(0.8, 1.35)
	spr.pixel_size = (1.5 * sc) / float(maxi(1, int(tex.get_height())))
	var wh: float = float(tex.get_height()) * spr.pixel_size
	var base_pos: Vector3 = _world_pos(pos2d, wh * 0.42)
	spr.position = base_pos - Vector3(0.0, 0.55, 0.0)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", base_pos, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 破土弹出
	tw.tween_property(spr, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(0.16)
	tw.chain().tween_property(spr, "modulate:a", 0.0, 0.24)
	tw.chain().tween_callback(spr.queue_free)

func _sk_stone_taunt(u: Dictionary) -> void:                    # 石头龟·嘲讽(用户设计·120龟能): 500码敌4秒硬嘲讽 + 自身1A永久盾 + 0.5×护甲减伤4秒 + 将结束砸地(400码1A魔法+击飞2s)
	var victims: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(u["pos"]) <= 500.0:
			victims.append(o)
	_taunt(u, victims, 4.0)
	_grant_shield(u, u["atk"] * 1.0)          # 1A永久盾(dur=0·不随嘲讽消失)
	u["stone_dr_until"] = _t + 4.0            # 0.5×护甲%减伤4秒
	u["energy_lock_until"] = _t + 3.5        # 砸击(3.5s)之后龟能才重新充能(用户#8"砸击后龟能才重新充能")
	_aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 500.0, Color(0.86, 0.68, 0.42, 0.42), 4.0)   # 500码仇恨光环(嘲讽4秒·贴地跟随·用户#8)
	var uu := u
	var slam := func() -> void:                # 蓄力3.5s→砸地(在4秒嘲讽内·K'Sante Q3式)
		if not uu.get("alive", false): return
		_burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", uu["pos"], 220.0)   # 砸地岩石冲击(用户2026-07-06"像地面猛砸")
		for o in _enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(uu["pos"]) <= 400.0:
				_apply_damage_from(uu, o, _atk_dmg(uu, 1.0, o, true), Color("#c8a878"))
				if not o.get("airborne", false):
						_knockback(uu, o, 80.0, 3.6111)   # 击飞【1.2秒·峰高6.5】(用户2026-07-11) — vy=6.0×3.6111=21.667
						o["knock_g"] = -36.111            # 配重力-36.111→ 滞空=2×21.667/36.111=1.2s·峰高=21.667²/(2×36.111)=6.5(解耦时长与抛高)
		_shake(0.06)
	_pending_shots.append({"delay": 3.5, "fn": slam, "src": u})

func _sk_bamboo_smack(u: Dictionary, tgt) -> void:              # 竹叶龟·竹击(用户封板·120龟能): 钩全场最远敌·1.0A物理·眩晕0.5s·拉贴身·冰寒4秒(-20%攻/-20%移速); 蛋免控只吃伤
	var far = null
	var far_d := -1.0
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var d: float = o["pos"].distance_to(u["pos"])
		if d > far_d:
			far_d = d; far = o
	if far == null: return
	var far_pos0: Vector2 = far["pos"]                          # 拉近前的原位(画竹藤用)
	_bolt_line(u["pos"], far_pos0, Color(0.22, 0.83, 0.33))     # 伸出竹藤(用户2026-07-06"伸出一条竹藤·打最远的敌人")
	_burst_vfx("res://assets/sprites/vfx/bamboo-vine.png", far_pos0, 120.0, 1.0)   # 藤钩勾住
	_apply_damage_from(u, far, _atk_dmg(u, 1.0, far), Color("#39d353"))
	if not far.get("_eggImmune", false):                        # 蛋/免控只吃伤
		far["stun_until"] = maxf(float(far.get("stun_until", 0.0)), _t + _cc_dur(far, 0.5))
		_buff(far, "atk", -0.20, true, 4.0)                     # 冰寒-20%攻4秒
		far["spd_move_mult"] = 0.8; far["spd_dbf_until"] = _t + 4.0   # 冰寒-20%移速4秒
		_hitstop = maxf(_hitstop, 0.05)                          # 抓住瞬间小顿(用户2026-07-11: 拽住得顿一下)
		var ff = far
		var uu := u
		var pull_fn := func() -> void:                           # 顿0.2s后再拽贴身
			if not ff.get("alive", false): return
			var pd: Vector2 = ff["pos"] - uu["pos"]
			if pd.length() > 1.0:
				ff["pos"] = uu["pos"] + pd.normalized() * 60.0     # 竹藤拽到贴身
			_bolt_line(uu["pos"], ff["pos"], Color(0.22, 0.83, 0.33))   # 收藤(收线感)
			_impact_particles(ff["pos"], float(ff.get("height", 0.0)))
			_skill_ring(uu["pos"], Color(0.22, 0.83, 0.33, 0.4), 54.0)   # 拉到脸上落点环
		_pending_shots.append({"delay": 0.2, "src": u, "fn": pull_fn})

func _sk_bamboo_spikes(u: Dictionary, tgt) -> void:            # 竹叶龟·竹刺阵(用户封板·130龟能·科加斯Q式): 当前目标为心300码·蓄力0.6s→竹刺·90%A+15%maxHp物理·击飞1.5s
	if tgt == null: return
	var c: Vector2 = tgt["pos"]
	var uu := u
	var spikes := func() -> void:
		if not uu.get("alive", false): return
		for i in range(14):   # 竹刺齐爆: 300码圈内铺一片从地冒起的绿竹刺(科加斯Q式·用户2026-07-11「要补刺」)
			var ang: float = TAU * float(i) / 14.0 + randf() * 0.45
			var rr: float = sqrt(randf()) * 285.0
			_spawn_bamboo_spike(c + Vector2(cos(ang), sin(ang)) * rr, randf_range(0.85, 1.3), 0.5)
		for o in _enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(c) <= 300.0:
				_apply_damage_from(uu, o, _atk_dmg(uu, 0.9, o) + int(uu["maxHp"] * 0.15), Color("#39d353"))
				_spawn_bamboo_spike(o["pos"], 1.5, 0.5)   # 命中点更粗一根竹刺
				if not o.get("_eggImmune", false):
					_knockback(uu, o, 70.0, 2.75)                # 击飞【1.5秒】(用户#12"击飞1.5秒"·滞空=2×(6.0×2.75)/22=1.5s·原vy_mult=1.5只给0.82s)
		_shake(0.06)
		_hitstop = maxf(_hitstop, 0.05)
	_skill_ring(c, Color(0.22, 0.83, 0.33, 0.4), 300.0)         # 蓄力预警圈
	_pending_shots.append({"delay": 0.6, "fn": spikes, "src": u})

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies := _allies_of(u, false)
	_play_heal_glow(u["pos"])
	if allies.is_empty():
		_heal(u, u["maxHp"] * 0.15)
	else:
		_heal(u, u["maxHp"] * 0.10)
		for o in allies:
			_grant_shield(o, o["maxHp"] * 0.12, 4.0)   # 竹叶自然恢复·友军护盾(通用护盾4秒·封板L74)·[原注释误标"寒冰团队护盾"→那是ice commonTeamShield另有其函]
			_play_heal_glow(o["pos"])

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_grant_shield(ally, u["atk"] * 1.2, 5.0)   # 天使祝福护盾5秒(封板L145·与攻速/龟能buff同步)
	ally["haste_until"] = _t + 5.0; ally["haste_mult"] = 1.5       # +50% 攻速 5秒(用户2026-07-11: 30%→50%)
	_skill_ring(ally["pos"], Color(1.0, 0.9, 0.5, 0.5), 48.0)   # 祝福: 金色圣光环 (用户2026-07-11: 取消原龟能充能+30%buff)

func _sk_ice_frost(u: Dictionary, tgt: Dictionary) -> void:      # 寒冰龟·冰霜 ✅ (圆形冰霜场: 5秒/每0.5秒一跳/圈内-25%魔抗)
	var center: Vector2 = u["pos"]
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	else:
		var es := _enemies_of(u)
		if not es.is_empty(): center = es[0]["pos"]
	var radius := 150.0
	var tw := _reg_tween()
	for i in range(10):   # 5秒 / 每0.5秒 = 10跳
		tw.tween_callback(_ice_frost_tick.bind(u, center, radius))
		tw.tween_interval(0.5)

func _ice_frost_tick(u: Dictionary, center: Vector2, radius: float) -> void:
	_ice_frost_rain(center, radius)
	for o in _enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			_buff(o, "mr", -0.25, true, 0.65)   # 圈内 -25%魔抗(刷新, 略>0.5s跳间隔)
			_apply_damage_from(u, o, _atk_dmg(u, 0.18, o, true), Color("#bfe9ff"))

func _ice_frost_rain(center: Vector2, radius: float) -> void:    # 冰霜场视觉: 范围环 + 几片落冰
	_skill_ring(center, Color(0.55, 0.85, 1.0, 0.4), radius)
	var tex := "res://assets/sprites/skills/ice-spike.png"
	var has_tex := ResourceLoader.exists(tex)
	for i in range(5):
		var off := Vector2(_juice_rng.randf_range(-radius, radius), _juice_rng.randf_range(-radius, radius))
		if off.length() > radius:
			continue
		var sh := Sprite3D.new()
		if has_tex:
			sh.texture = load(tex)
			sh.pixel_size = 0.016
			sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			sh.texture = _make_bolt_texture(Color(0.6, 0.85, 1.0))
			sh.pixel_size = 0.01
		sh.modulate = Color(0.7, 0.9, 1.0, 0.95)
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		var ground := _world_pos(center + off, 0.05)
		sh.position = ground + Vector3(0.0, 2.2, 0.0)
		_world.add_child(sh)
		var twr := _reg_tween()
		twr.set_parallel(true)
		twr.tween_property(sh, "position", ground, 0.35)
		twr.tween_property(sh, "modulate:a", 0.0, 0.3).set_delay(0.18)
		twr.chain().tween_callback(sh.queue_free)

func _sk_ice_freeze(u: Dictionary, tgt: Dictionary) -> void:    # 寒冰龟·冰封 ✅ (冰锥弹道→命中0.6魔法+冻结1.5s)
	if tgt == null or not tgt.get("alive", false):
		return
	_fire_ice_shard(u, tgt, _atk_dmg(u, 0.6, tgt, true))

func _sk_ice_team_shield(u: Dictionary) -> void:               # 寒冰龟·团队护盾(用户2026-07-11重设计·120龟能): 全体友军5%施法者maxHp冰霜盾4秒·盾破/到期爆炸250码1×ATK魔法; 独狼(无其他友军)盾×4·爆炸5×ATK
	var others := _allies_of(u, false)                         # 不含自己
	var solo: bool = others.is_empty()
	var shield_amt: float = u["maxHp"] * (0.20 if solo else 0.05)   # 5%施法者maxHp; 独狼×4=20%
	var boom_mult: float = 5.0 if solo else 1.0                     # 爆炸1×ATK; 独狼5×ATK
	for o in _allies_of(u):                                    # 含自己=全体友军
		_frost_shield_burst(o)                                 # 若已挂上一发未爆→先结算(防覆盖丢爆裂)
		_grant_shield(o, shield_amt, 4.0)                      # 冰霜盾·4秒
		o["frost_shield_until"] = _t + 4.0                     # 爆裂追踪(独立通用shield_until): 到期/盾清零/持盾者死 任一→爆
		o["frost_shield_src"] = u
		o["frost_shield_boom"] = boom_mult
		_aura_vfx("res://assets/sprites/vfx/fx-hex-bubble.png", o, 62.0, Color(0.68, 0.9, 1.0, 0.62), 4.0, 0.9)   # 六棱冰晶护盾泡(4秒·罩住友军)

# 冰霜护盾爆裂: 到期/被打破(盾清零)/持盾者死 触发 → 持盾者250码内敌 boom×ATK 魔法 + 冰爆冲击环
func _frost_shield_burst(ally: Dictionary) -> void:
	if float(ally.get("frost_shield_until", 0.0)) <= 0.0:
		return
	ally["frost_shield_until"] = 0.0
	var src = ally.get("frost_shield_src", null)
	var boom: float = float(ally.get("frost_shield_boom", 1.0))
	ally.erase("frost_shield_src")
	if src is Dictionary:
		var c: Vector2 = ally["pos"]
		for o in _enemies_of(src):
			if o.get("alive", false) and o["pos"].distance_to(c) <= 250.0:
				_apply_damage_from(src, o, _atk_dmg(src, boom, o, true), Color("#bfe9ff"))   # boom×ATK 魔法(1或5)
		_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", c, 520.0, 0.14)   # 冰爆冲击环(≈250码半径)
		_skill_ring(c, Color(0.68, 0.9, 1.0, 0.6), 250.0)
		_impact_particles(c, 0.0); _shake(0.05)

# 水平冰锥贴图(程序画: 后宽前尖朝右, 冰蓝+白核; 修竖冰柱方向错)
func _make_ice_cone_texture() -> ImageTexture:
	var W := 56
	var H := 22
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var half := (float(H) / 2.0 - 0.5) * (1.0 - fx * fx)   # 后宽前尖(锥)
		if half < 0.4:
			continue
		for y in range(H):
			var dy := absf(float(y) - cy)
			if dy <= half:
				var edge := 1.0 - dy / half
				var c := Color(0.45, 0.78, 1.0).lerp(Color(0.92, 0.98, 1.0), clampf(edge * 1.3, 0.0, 1.0) * 0.8)
				c.a = clampf(edge * 1.2, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _fire_ice_shard(src: Dictionary, tgt: Dictionary, dmg: int) -> void:   # 冰锥弹道(水平朝目标, 命中魔伤+冻结1.5s)
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	p.texture = _make_ice_cone_texture()
	p.pixel_size = 0.04
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED           # 冰锥有朝向→贴XZ绕Y转向目标(不再永远水平指右/左·斜射方向对·用户2026-07-11)
	p.axis = Vector3.AXIS_Y
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)
	p.position = world_from
	_world.add_child(p)
	var dur := clampf(start2d.distance_to(tgt["pos"]) / 600.0, 0.35, 0.9)   # 恒速~600px/s, 慢到看得清(原0.2太快)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": Color("#4dabf7"),
		"src": src, "t": 0.0, "dur": dur, "basic_onhit": false, "freeze_on_hit": 1.5, "oriented": true, "dtype": _last_dmg_type,
	})

func _ninja_dash(u: Dictionary, target: Dictionary) -> void:    # 被动·冲击(亚索E式): 朝最近敌固定位移450码·主目标1.3A/路径其余0.8A物理+击飞0.8s·每敌10s冷却·无伤害递增
	# 〖用户2026-07-06〗"450码固定距离，最近，所以理想的效果就是他会连着滑几下，不用加递增"; 伤害取回合制 ninjaImpact(atkScale=1.3 / behindScale=0.8)
	u["_ninja_last_dash"] = _t
	var start: Vector2 = u["pos"]
	var dir: Vector2 = target["pos"] - start
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	# ★#5修〖用户2026-07-11〗: 亚索 E 式【滑行穿过】(非瞬移), 滑速 600 码/秒. 450 码固定路径不变.
	var endp: Vector2 = start + dir * 300.0                     # 冲刺距离 300码(用户2026-07-11: 450→300)
	endp.x = clampf(endp.x, ARENA.position.x, ARENA.end.x)
	endp.y = clampf(endp.y, ARENA.position.y, ARENA.end.y)
	# 路径上的敌 (按沿路投影排序 → 滑到谁割谁)
	var hits: Array = []
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if not _on_line(start, dir, o["pos"], 62.0): continue
		var proj: float = (o["pos"] - start).dot(dir)
		if proj < 0.0 or proj > 300.0: continue
		hits.append({"o": o, "proj": proj, "done": false})
	hits.sort_custom(func(a, b): return float(a["proj"]) < float(b["proj"]))
	_bolt_line(start, endp, Color(0.7, 0.95, 1.0, 0.5))         # 冲刺残影(淡)
	_ninja_glide(u, start, endp, dir, target, hits)            # 滑行(async, fire-and-forget)

## 忍者冲击滑行 (亚索 E 式 · 600 码/秒 · 穿过路径敌逐个割). no_move 期间分离跳过, 每帧直接推 pos.
func _ninja_glide(u: Dictionary, start: Vector2, endp: Vector2, dir: Vector2, target: Dictionary, hits: Array) -> void:
	var total: float = start.distance_to(endp)
	if total < 1.0:
		return
	var was_nm: bool = bool(u.get("no_move", false))
	var was_nb: bool = bool(u.get("no_basic", false))
	u["no_move"] = true
	u["no_basic"] = true
	var traveled := 0.0
	# ★冲击特效(用户2026-07-11): 角色前方一道疾风拖影伴随滑行(fx-trail·贴地朝行进方向·每帧跟随身前)
	var lead := Sprite3D.new()
	lead.texture = load("res://assets/sprites/vfx/fx-trail.png")
	lead.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	lead.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lead.axis = Vector3.AXIS_Y
	lead.shaded = false; lead.transparent = true
	lead.modulate = Color(0.72, 0.95, 1.0, 0.9)                # 疾风蓝白
	var _lt := float(maxi(1, int(lead.texture.get_width())))
	lead.pixel_size = (160.0 * WS) / _lt
	lead.rotation.y = -atan2(dir.y, dir.x)                      # 朝行进方向
	lead.position = _world_pos(start + dir * 60.0, 1.0)
	_world.add_child(lead)
	while traveled < total and u.get("alive", false) and is_inside_tree():
		await get_tree().process_frame
		traveled = minf(total, traveled + 600.0 * get_process_delta_time())   # 恒速 600 码/秒
		u["pos"] = start + dir * traveled
		if is_instance_valid(lead): lead.position = _world_pos(u["pos"] + dir * 60.0, 1.0)   # 拖影跟在身前
		for h in hits:
			if not h["done"] and traveled >= float(h["proj"]):
				h["done"] = true
				var o: Dictionary = h["o"]
				if o.get("alive", false):
					_apply_damage_from(u, o, _atk_dmg(u, 1.3 if o == target else 0.8, o), Color("#9fe8ff"))
					_knockback(u, o, 40.0, 1.468, 1.0)          # 击飞 0.8s 滞空
					o["_ninja_dash_until"] = _t + 10.0          # 每敌被冲后 10s 冷却
					_burst_vfx("res://assets/sprites/vfx/ninja-slash.png", o["pos"], 88.0, 1.0)
	u["pos"] = endp
	u["no_move"] = was_nm
	u["no_basic"] = was_nb
	if is_instance_valid(lead):                                # 冲刺结束→拖影淡出
		var _lw := _reg_tween()
		_lw.tween_property(lead, "modulate:a", 0.0, 0.14)
		_lw.tween_callback(lead.queue_free)
	_burst_vfx("res://assets/sprites/vfx/ninja-slash.png", u["pos"], 98.0, 1.0)   # 落点疾风斩弧

func _sk_ninja_backstab(u: Dictionary, tgt: Dictionary) -> void: # 技二·背刺(封板): +5穿甲5秒→闪现到最远敌(后排C)身后→连刺3段共2.0A物理→留原地追砍
	var far = null
	var fd := -1.0
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var dd: float = u["pos"].distance_to(o["pos"])
		if dd > fd: fd = dd; far = o
	if far == null: far = tgt
	if far == null: return
	u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 5.0        # +5穿甲(5秒后撤销)
	var uu: Dictionary = u
	_pending_shots.append({"delay": 5.0, "fn": func(): uu["armor_pen"] = float(uu.get("armor_pen", 0.0)) - 5.0, "src": u})
	_dash_to(u, far, -70.0)                                     # 闪现到最远敌身后
	for i in range(3):
		if not far.get("alive", false): break
		_apply_damage_from(u, far, _atk_dmg(u, 0.6667, far), Color("#cfd8e8"))
	_beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], far["pos"], 34.0, Color(0.8, 0.9, 1.0, 0.55), 0.30)   # 烟遁刀光拖影
	_burst_vfx("res://assets/sprites/vfx/ninja-slash.png", far["pos"], 92.0, 1.0)   # 背刺斩弧

func _sk_ninja_shuriken(u: Dictionary, tgt) -> void:           # 技·手里剑(封板·远程·1:1回合制_ninja_shuriken): 掷旋转飞镖·命中1.6A物理; 暴击(按忍者暴击率)=暴击总伤拆两段→红物理(吃减甲)+白真伤(穿甲·占(40+2%/级)%), 同一发跳两个数字
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var base_dmg: float = float(u["atk"]) * 1.6               # 1.6A 基础(未减甲/未暴击)
	var is_crit: bool = randf() < minf(float(u.get("crit", 0.0)), 1.0)   # 暴击=忍者自身暴击率(非固定概率)
	var phys_raw: float = base_dmg                            # 非暴击: 全物理一发
	var true_raw: float = 0.0
	if is_crit:
		var crit_mult: float = float(u.get("crit_dmg", 1.5)) + maxf(0.0, float(u.get("crit", 0.0)) - 1.0) * 1.5   # 暴击倍率(溢出100%每1%→1.5%·同_resolve_dmg)
		var crit_total: float = round(base_dmg * crit_mult)  # 暴击总伤(已乘暴击倍率)
		var lv: int = int(u.get("level", 1))
		true_raw = round(crit_total * minf(100.0, 40.0 + 2.0 * float(lv)) / 100.0)   # 其中(40+2%/级)%(封顶100%)→真实伤害(穿甲)
		phys_raw = maxf(0.0, crit_total - true_raw)           # 余下→物理(吃减甲)
	_fire_shuriken(u, tgt, phys_raw, true_raw, is_crit)

func _fire_shuriken(src: Dictionary, tgt: Dictionary, phys_raw: float, true_raw: float, is_crit: bool) -> void:   # 旋转飞镖弹道(4帧自旋): 命中→物理段(红·减甲)+可选真伤段(白·穿甲)·暴击金染
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	p.texture = load("res://assets/sprites/vfx/ninja-shuriken.png")
	p.hframes = 4                                              # 512×128 = 4帧忍者飞镖(旋转)
	p.frame = 0
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED             # 面镜头·靠帧旋转不靠转node
	p.shaded = false; p.transparent = true
	p.modulate = (Color(1.0, 0.86, 0.4, 1.0) if is_crit else Color(1, 1, 1, 1))   # 暴击金染 / 普通原色
	p.pixel_size = (58.0 * WS) / 128.0
	var world_from := _world_pos(start2d, 1.0)
	p.position = world_from
	_world.add_child(p)
	var dur := clampf(start2d.distance_to(tgt["pos"]) / 850.0, 0.12, 0.5)   # 快镖
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "src": src, "t": 0.0, "dur": dur,
		"shuriken_hit": true, "shuriken_anim": true,
		"nj_phys": phys_raw, "nj_true": true_raw, "is_crit": is_crit,
	})

func _sk_ghost_soulstorm(u: Dictionary, tgt: Dictionary) -> void: # 幽灵龟·灵魂风暴 ✅
	var cursed: bool = _has_dot(tgt, "curse")
	if cursed:
		_apply_damage_from(u, tgt, int(u["atk"] * 2.5), Color("#e0b0ff"), 0.0, true)   # 有诅咒→2.5A真伤(处决感·用户2026-07-09"打有诅咒是真伤")
	else:
		for i in range(2):
			_apply_damage_from(u, tgt, _atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))   # 无诅咒→2段共2.5A魔法(用户2026-07-09"打无诅咒目标是魔法")
		_add_dot(tgt, "curse", tgt["maxHp"] * 0.05, BUFF_SEC)

func _sk_ghost_phase(u: Dictionary, tgt: Dictionary) -> void:    # 幽灵龟·虚化 (用户2026-07-08): 虚化4秒受物理伤害-90% + 对目标2段共1.2A真伤
	u["phase_until"] = _t + 4.0
	for i in range(2):
		_apply_damage_from(u, tgt, int(u["atk"] * 0.6), Color("#c77dff"), 0.0, true)   # 真实(穿减伤)
	_aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 78.0, Color(0.78, 0.49, 1.0, 0.55), 4.0)   # 虚化紫环(虚化4秒·跟随)

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧(封板): 20%最大生命护盾(4秒·限时盾原语)+护甲/魔抗各+20%攻击力(flat·5秒)
	_grant_shield(u, u["maxHp"] * 0.20, 4.0)
	_buff(u, "def", u["atk"] * 0.2, false, 5.0)
	_buff(u, "mr", u["atk"] * 0.2, false, 5.0)

const DIAMOND_ROLL_MAX_SPD := 280.0   # 钻石滚球满速(封板"移速0起4s加速到满速"·具体值手感留F5)

func _sk_diamond_powerball(u: Dictionary, tgt) -> void:          # 钻石龟·钻石滚球(封板·龙龟Q Powerball·100龟能): 进入蜷球滚动位移态(移速0起4s加速满速·朝最近敌·免疫定身沉默打断)·撞击120码AOE(护甲/魔抗/2%maxHp按速插值)+击飞1s+眩晕0.5~3s
	if _nearest_enemy(u) == null:
		return
	u["roll_active"] = true
	u["roll_start"] = _t
	_skill_ring(u["pos"], Color(0.6, 0.86, 1.0, 0.5), 44.0)

# 滚球位移tick(每帧·在_tick_unit免CC段调): 0→满速4s加速·朝最近敌滚·进120码撞击结算
func _diamond_roll_tick(u: Dictionary, delta: float) -> void:
	var sf: float = clampf((_t - float(u.get("roll_start", _t))) / 4.0, 0.0, 1.0)   # 0→满速4秒线性加速
	var tgt = _nearest_enemy(u)
	if tgt == null or _t > float(u.get("roll_start", _t)) + 6.0:   # 无敌可撞/超时6s→退出滚动
		u["roll_active"] = false; u["state"] = "move"
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	if to_t.length() <= 120.0:                                     # 进入120码→撞击结算
		_diamond_roll_impact(u, tgt["pos"], sf)
		u["roll_active"] = false; u["state"] = "move"
		return
	var roll_spd: float = DIAMOND_ROLL_MAX_SPD * (0.1 + 0.9 * sf)  # 0.1起步(避免完全不动)→满速
	u["pos"] += to_t.normalized() * roll_spd * delta
	u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
	u["face_right"] = to_t.x > 0.0
	if int(_t * 30.0) % 2 == 0:                                    # 速度线拖尾(越快越猛·美术L231)
		_skill_ring(u["pos"], Color(0.6, 0.86, 1.0, 0.2 + 0.35 * sf), 28.0 + 22.0 * sf)

func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(cp) > 120.0: continue             # 撞击点120码小AOE
		var dmg: int = int(u["def"] * (0.1 + 0.9 * sf) + u["mr"] * (0.1 + 0.9 * sf) + o["maxHp"] * (0.02 + 0.18 * sf))   # 按速插值(封板: 0速0.1甲0.1抗2%→满速1.0甲1.0抗20%)
		_apply_damage_from(u, o, dmg, Color("#9bdcff"))
		_knockback(u, o, 50.0, 1.8, 1.0)                          # 击飞1秒(vy高)
		_freeze(o, 0.5 + 2.5 * sf)                                # 眩晕0.5~3s(随速插值·满速3s)
	_skill_ring(cp, Color(0.6, 0.86, 1.0, 0.6), 120.0)
	_shake(JUICE_SHAKE_HEAVY if sf > 0.6 else JUICE_SHAKE_LIGHT)  # 满速更炸(封板美术L231)

func _sk_diamond_smash(u: Dictionary, tgt) -> void:             # 钻石龟·钻石冲撞(封板): 100%护甲+100%魔抗+10%攻击力物理+9层流血 (强化钻石结构打包被动在登场gate)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	_dash_to(u, tgt, 45.0)
	var dmg: int = int(u["def"] + u["mr"] + u["atk"] * 0.1)
	_apply_damage_from(u, tgt, dmg, Color("#9bdcff"))
	_apply_dot_stacks(tgt, "bleed", 9, u)                       # 9层流血
	_skill_ring(tgt["pos"], Color(0.7, 0.9, 1.0, 0.5), 48.0)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷(用户设计: 前方120°/300码镰刀扇形斩·1.2A物理+30%吸血)
	var tgt = _nearest_enemy(u)
	var dir: Vector2 = (Vector2.RIGHT if tgt == null else (tgt["pos"] - u["pos"]))
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var half_cos: float = cos(deg_to_rad(60.0))                  # 半角60°=全120°
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var to_o: Vector2 = o["pos"] - u["pos"]
		var d: float = to_o.length()
		if d > 300.0 or d < 1.0: continue
		if dir.dot(to_o / d) < half_cos: continue
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o), Color("#ff4444"), 0.30)
	_skill_ring(u["pos"], Color(1.0, 0.3, 0.3, 0.45), 60.0)

# 骰子龟·稳定骰子(刀妹Q式·〖#4"刀妹Q式·你仔细设计"〗; 数值取回合制 diceFlashStrike: baseHits=4 / perHitScale=0.9 / falloffPct=10)
#   掷骰 1-6 → 冲刺 (4 + 点数) 次; 首段 0.9×ATK 物理(吃暴击), 之后每段递减 10% (0.9 × 0.9^i)
#   每刺间隔 DICE_STRIKE_GAP 秒【分帧铺开】(原来全部在同一帧解算 → 视觉糊成一坨/飘字堆叠)
const DICE_STRIKE_GAP := 0.09
func _sk_dice_flash_strike(u: Dictionary) -> void:
	var pips: int = randi_range(1, 6)
	var count: int = 4 + pips
	_float_text(u["pos"] + Vector2(0, -64), "稳定骰子! %d点→%d刺" % [pips, count], Color("#ffd93d"))
	var uu: Dictionary = u
	for i in range(count):
		var scale_i: float = 0.9 * pow(0.9, float(i))           # 每段递减10%(回合制 falloffPct=10)
		var fn := func():
			if not uu.get("alive", false): return
			var tgt = _dice_pick_strike_target(uu)
			if tgt == null: return                              # 全灭 → 该刺空过(后续同样空过)
			_dash_to(uu, tgt, 60.0)                             # 短冲贴身
			_apply_damage_from(uu, tgt, _atk_dmg(uu, scale_i, tgt), Color("#ff4444"))
			_melee_lunge(uu, tgt)
		if i == 0: fn.call()                                    # 首刺立刻(放技手感)
		else: _pending_shots.append({"delay": float(i) * DICE_STRIKE_GAP, "fn": fn, "src": u})

func _dice_pick_strike_target(u: Dictionary):                   # 最近·残血优先
	var best = null
	var best_score := INF
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var score: float = o["pos"].distance_to(u["pos"]) + float(o["hp"]) * 0.1
		if score < best_score:
			best_score = score; best = o
	return best

func _rainbow_enh_prism_proc(u: Dictionary) -> void:            # 强化棱镜4色(用户设计·每5秒抽1): 橙全体友军+10%吸血5s / 黄随机敌灼烧0.67A / 青随机敌冰寒5s / 紫随机敌诅咒5s
	var c: int = randi() % 4
	var es: Array = _enemies_of(u)
	match c:
		0:
			for o in _allies_of(u):
				_buff(o, "lifesteal", 0.1, false, 5.0)
			_float_text(u["pos"] + Vector2(0, -60), "橙·全体吸血", Color("#ff9d3c"))
		1:
			if not es.is_empty():
				var t = es[randi() % es.size()]
				_apply_dot_stacks(t, "burn", maxi(1, int(round(float(u["atk"]) * 0.67))), u)
		2:
			if not es.is_empty():
				var t2 = es[randi() % es.size()]
				t2["spd_aspd_mult"] = 0.7; t2["spd_dbf_until"] = _t + 5.0   # 冰寒-30%攻速5秒
		3:
			if not es.is_empty():
				var t3 = es[randi() % es.size()]
				_add_dot(t3, "curse", t3["maxHp"] * 0.05, 5.0)             # 诅咒每秒5%maxHp真伤5秒
	_skill_ring(u["pos"], Color(0.8, 0.6, 1.0, 0.4), 48.0)

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.65, 4.0)   # 彩虹棱镜护盾(通用护盾4秒·封板L268)

func _sk_gambler_bet(u: Dictionary, tgt: Dictionary) -> void:    # 赌神龟·赌注(用户封板·100龟能): 需当前生命>40%; 消耗当前生命40%→7段物理砸目标(共≈0.4×当前生命); 施放3秒多重概率+20%
	if tgt == null or not tgt.get("alive", false): return
	if u["hp"] <= u["maxHp"] * 0.40: return                      # 需当前生命>40%才放
	var cost: float = u["hp"] * 0.40
	u["hp"] = maxf(1.0, u["hp"] - cost)
	var per: int = maxi(1, int(cost / 7.0))
	for i in range(7):
		_apply_damage_from(u, tgt, per, Color("#ffd93d"), 0.0, true)   # 7段物理(总≈消耗生命·穿减伤)
	u["gambler_bet_until"] = _t + 3.0                           # 3秒多重概率+20%(见_gambler_multi_cd·回补钩)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.55), 54.0)

func _sk_gambler_fate_wheel(u: Dictionary) -> void:             # 赌神龟·命运之轮(用户封板·80龟能): 抽1花色永久加属性(♠攻+5&血+30/♥护甲魔抗+2/♦暴击+8%&护穿+2/♣吸血+4%)·跨场累积=存GameState.gambler_wheel_stacks(本大轮累积·切轮重置·方案B·用户2026-07-09)
	var _suit := randi() % 4
	if u.get("side", "") == "left":   # 跨场累积: 只玩家赌神写入本大轮累积(敌/ghost镜像不写·切轮reset)
		var _sk: String = ["spade", "heart", "diamond", "club"][_suit]
		GameState.gambler_wheel_stacks[_sk] = int(GameState.gambler_wheel_stacks.get(_sk, 0)) + 1
	match _suit:
		0:
			u["base_atk"] = float(u["base_atk"]) + 5.0; u["maxHp"] += 30.0; u["hp"] += 30.0
			_float_text(u["pos"] + Vector2(0, -64), "♠ 攻+5 血+30", Color("#ffd93d"))
		1:
			u["base_def"] = float(u["base_def"]) + 2.0; u["base_mr"] = float(u["base_mr"]) + 2.0
			_float_text(u["pos"] + Vector2(0, -64), "♥ 护甲+2 魔抗+2", Color("#ffd93d"))
		2:
			u["crit"] = float(u["crit"]) + 0.08; u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 2.0
			_float_text(u["pos"] + Vector2(0, -64), "♦ 暴击+8% 护穿+2", Color("#ffd93d"))
		_:
			_buff(u, "lifesteal", 0.04, false, 9999.0)
			_float_text(u["pos"] + Vector2(0, -64), "♣ 吸血+4%", Color("#ffd93d"))
	_recalc_stats(u)
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.3, 0.6), 58.0)

func _gambler_apply_wheel_stacks(u: Dictionary) -> void:   # 命运之轮跨场累积(方案B): 登场套用GameState本大轮已抽花色(切轮重置)·只玩家赌神调用
	var ws: Dictionary = GameState.gambler_wheel_stacks
	if ws.is_empty(): return
	for i in range(int(ws.get("spade", 0))):
		u["base_atk"] = float(u["base_atk"]) + 5.0; u["maxHp"] += 30.0; u["hp"] += 30.0
	for i in range(int(ws.get("heart", 0))):
		u["base_def"] = float(u["base_def"]) + 2.0; u["base_mr"] = float(u["base_mr"]) + 2.0
	for i in range(int(ws.get("diamond", 0))):
		u["crit"] = float(u["crit"]) + 0.08; u["armor_pen"] = float(u.get("armor_pen", 0.0)) + 2.0
	for i in range(int(ws.get("club", 0))):
		_buff(u, "lifesteal", 0.04, false, 9999.0)
	_recalc_stats(u)

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌: 丢1张牌=1段1.0A物理(用户2026-07-09"只造成1段伤害")+自身0.25A护盾+回5%maxHp+目标攻-15%
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ff4444"))
	_grant_shield(u, u["atk"] * 0.25)
	_heal(u, u["maxHp"] * 0.05)
	_buff(tgt, "atk", -0.15, true)

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽(封板·薇恩Q Tumble·80龟能): 智能翻滚~250码→下次普攻附带0.9A物理(吃吸血)+25%闪避+0.7A护盾
	var dir := Vector2.RIGHT
	var nm = null
	var nmd := 150.0
	for o in _enemies_of(u):                                     # ① 近战/刺客贴近(<150码)→朝远离最近近战威胁滚(拉距保远程)
		if o.get("alive", false) and o.get("melee", false):
			var dd: float = u["pos"].distance_to(o["pos"])
			if dd < nmd: nmd = dd; nm = o
	if nm != null:
		dir = (u["pos"] - nm["pos"]).normalized()
	elif u["hp"] < u["maxHp"] * 0.35:                           # ② 残血→朝敌质心反向撤退
		var cen := Vector2.ZERO
		var cn := 0
		for o in _enemies_of(u):
			if o.get("alive", false): cen += o["pos"]; cn += 1
		if cn > 0: cen /= float(cn); dir = (u["pos"] - cen).normalized()
	else:                                                       # ③ 安全→朝当前目标最佳射程滚(目标<14%凑近确保处决,否则拉开保持射程)
		var tg = _nearest_enemy(u)
		if tg != null:
			if float(tg["hp"]) < float(tg["maxHp"]) * 0.14: dir = (tg["pos"] - u["pos"]).normalized()
			else: dir = (u["pos"] - tg["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var dest: Vector2 = u["pos"] + dir.normalized() * 250.0
	dest.x = clampf(dest.x, ARENA.position.x, ARENA.end.x)
	dest.y = clampf(dest.y, ARENA.position.y, ARENA.end.y)
	_beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], dest, 46.0, Color(0.7, 1.0, 0.75, 0.6), 0.32)   # 灵巧侧翻残影(薇恩Q式拖影)
	u["pos"] = dest
	u["hunter_roll_buff"] = true                                # 下次普攻附带0.9A物理(吃吸血)
	_buff(u, "dodge", 0.25, true, 5.0)                          # 25%闪避5秒
	_grant_shield(u, u["atk"] * 0.7)                            # 0.7A护盾

func _sk_hunter_shot(u: Dictionary, tgt) -> void:              # 猎人龟·精准射击(封板·90龟能·射箭+毒箭+猎杀印记三合一): 狙2.0A物理+中毒5s+治疗削减50%5s+猎杀印记5s(<24%处决)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.0, tgt), Color("#a8ffb0"))
	_apply_dot_stacks(tgt, "poison", maxi(1, int(round(u["atk"] * 0.5))), u)   # 中毒(5s每秒魔法·走毒层数DoT)
	tgt["heal_reduce_until"] = _t + 5.0                         # 治疗削减50%·5秒
	tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), 0.5)
	tgt["hunt_mark_until"] = _t + 5.0                           # 猎杀印记5秒: 期间目标<24%即处决(中央伤害路径读)
	_float_text(tgt["pos"] + Vector2(0, -56), "猎杀印记", Color("#ffd700"))

func _sk_hunter_barrage(u: Dictionary, _tgt) -> void:          # 猎人龟·狩猎弹幕(封板·100龟能): 10绿箭·智能优先锁残血为方向·每箭可被挡直线弹道(命中路径第一敌/蛋·障碍穿·我方不挡·复用小龟_basic_first_blocker)·0.3A真实(共3A)·每箭<14%即处决
	for i in range(10):
		var aim = null                                          # 智能优先锁残血: 选最低血存活敌当方向(残血死→箭自然移向次残血=散射感)
		var lo := INF
		for o in _enemies_of(u):
			if o.get("alive", false) and float(o["hp"]) < lo: lo = float(o["hp"]); aim = o
		if aim == null: break
		var dir: Vector2 = aim["pos"] - u["pos"]
		if dir.length() < 1.0: dir = Vector2.RIGHT
		dir = dir.normalized()
		var hit = _basic_first_blocker(u, dir)                  # 可被挡: 命中路径第一个敌/蛋(挡在残血目标前的敌先吃)
		if hit != null:
			_apply_damage_from(u, hit, int(u["atk"] * 0.3), Color("#a8ffb0"), 0.0, true)   # 0.3A真实(处决由中央路径判)
		_fly_vfx("res://assets/sprites/vfx/hunter-arrow.png", u["pos"], u["pos"] + dir * 520.0, 72.0, 0.26, 1.0, float(i) * 0.055)   # 绿箭飞行(连珠速射·每箭错峰·接现有hunter-arrow素材·0额度)

func _sk_pirate_rum(u: Dictionary) -> void:                     # 海盗龟·朗姆酒(用户封板·120龟能): 每秒回4%maxHP×6秒 + 0.5A护甲6秒
	u["rum_until"] = _t + 6.0; u["rum_dps"] = u["maxHp"] * 0.04   # 每秒回4%maxHP×6秒(分秒HoT·在per-frame _heal(rum_dps×delta)结算·封板保真)
	var _rum_dr: float = u["atk"] * 0.15                          # 回合制 pirate·heal: defUpAtkPct={pct:15,turns:3} → 实时 +15%×ATK 双抗·6秒(同HoT窗)
	_buff(u, "def", _rum_dr, false, 6.0); _buff(u, "mr", _rum_dr, false, 6.0)
	_buff(u, "def", u["atk"] * 0.5, false, 6.0)                  # +0.5×攻击力护甲(flat·6秒)
	_skill_ring(u["pos"], Color(0.82, 0.5, 0.2, 0.5), 48.0)

func _sk_pirate_volley(u: Dictionary, tgt) -> void:              # 海盗龟·火炮齐射 ✅
	# 〖用户2026-07-07〗"海盗龟先制定目标，然后海盗船高高发射炮弹，对目标800码范围发射6次造成伤害"
	# 每发 = 0.17×ATK + 1.7%目标最大生命 (回合制 pirateCannonBarrage: hits=6/atkScale=0.17/hpPct=1.7) → 6发共 1.02A + 10.2%maxHp
	if tgt == null or not tgt.get("alive", false): return
	var c: Vector2 = tgt["pos"]
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(c) > 800.0: continue             # 以【目标】为心·800码圈内(非全体敌)
		for i in range(6):
			_apply_damage_from(u, o, _atk_dmg(u, 0.17, o) + int(o["maxHp"] * 0.017), Color("#ffd07a"))

func _sk_bubble_shield(u: Dictionary, _tgt: Dictionary) -> void: # 泡泡龟·泡泡盾(封板L435·80龟能): 给最脆友军1.8A泡泡盾(4秒)·到期/被打破/挂盾对象死→爆裂对施法者全体敌2.0A魔法
	var ally = _lowest_hp_ally(u)
	if ally == null: ally = u
	_bubble_shield_burst(ally)                       # 若该对象已挂着上一发泡泡盾未爆→先结算(防覆盖丢爆裂)
	_grant_shield(ally, u["atk"] * 1.8, 4.0)         # 1.8A泡泡盾·4秒限时(通用护盾原语)
	ally["bubble_shield_until"] = _t + 4.0           # 泡泡爆裂追踪(独立于通用shield_until): 到期/盾清零/对象死 任一→爆裂
	ally["bubble_shield_src"] = u
	_skill_ring(ally["pos"], Color(0.7, 0.9, 1.0, 0.55), 46.0)

# 泡泡盾爆裂: 到期/被打破/挂盾对象死 触发 → 对施法者(src)全体敌2.0A魔法 + 泡沫冲击波 (封板L435·防静默过期丢爆裂)
func _bubble_shield_burst(ally: Dictionary) -> void:
	if float(ally.get("bubble_shield_until", 0.0)) <= 0.0:
		return
	ally["bubble_shield_until"] = 0.0
	var src = ally.get("bubble_shield_src", null)
	ally.erase("bubble_shield_src")
	if src is Dictionary:
		for o in _enemies_of(src):
			if o.get("alive", false):
				_apply_damage_from(src, o, _atk_dmg(src, 2.0, o, true), Color("#cdebff"))
		_skill_ring(ally["pos"], Color(0.75, 0.92, 1.0, 0.6), 90.0)   # 泡沫破裂冲击波(全体敌)

func _sk_bubble_burst(u: Dictionary, tgt) -> void:              # 泡泡龟·泡泡爆破(马尔扎哈Q式·用户设计): 消耗当前泡泡值40%→目标两侧泡沫门·门间敌每个受=消耗泡泡值魔法+0.8A物理(无沉默)
	if tgt == null or not tgt.get("alive", false): return
	var consumed: float = float(u.get("bubble_store", 0.0)) * 0.40   # 修: 原读"bubble"(从不设=恒0→爆破无泡泡伤害bug)→"bubble_store"(受伤累积的真泡泡值·同被动/累积口径)
	u["bubble_store"] = maxf(0.0, float(u.get("bubble_store", 0.0)) - consumed)
	var c: Vector2 = tgt["pos"]
	for o in _enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(c) <= 200.0:   # 门间~200码带(两侧传送门美术TODO)
			_apply_damage_from(u, o, int(_mitigate(u, consumed, o, true)) + _atk_dmg(u, 0.8, o), Color("#cdebff"))   # 消耗泡泡值魔法(吃魔抗)+0.8A物理(封板L437)
	_skill_ring(c, Color(0.5, 0.9, 1.0, 0.55), 200.0)

# ============================================================================
#  线条龟·连笔 (回合制 lineLink: atkScale=0.8 / duration=3 / transferPct=30 — 附录B-05 补做)
#  画线连接 2 名敌人 3 秒: ①各受 0.8×ATK  ②各叠 1 层墨迹  ③连接期内一方受到伤害的 30%
#  以【真实伤害】传导给另一方(速写融入被动→墨迹系伤害为真实, 用户#1)  ④一方获墨迹另一方同步。
#  连接线特效跟随双方脚底(用户#6"连接两目标脚底的线特效")。
# ============================================================================
const INK_LINK_SEC := 3.0
const INK_LINK_TRANSFER := 0.30
var _ink_links: Array = []          # [{a,b,until,spr}]
var _ink_link_busy: bool = false    # 防传导/同步递归

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅(连接+传导+同步已补·附录B-05)
	var foes: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false): foes.append(o)
	if foes.is_empty(): return
	foes.sort_custom(func(x, y): return u["pos"].distance_squared_to(x["pos"]) < u["pos"].distance_squared_to(y["pos"]))
	var picks: Array = foes.slice(0, mini(2, foes.size()))
	for o in picks:
		_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#dddddd"))
		_add_stack(o, "ink", 1, _ink_cap(u))
	if picks.size() < 2: return                                  # 只有1个敌人 → 无链路可连
	_make_ink_link(picks[0], picks[1], u)

func _make_ink_link(a: Dictionary, b: Dictionary, caster: Dictionary) -> void:
	_drop_ink_link_of(a); _drop_ink_link_of(b)                   # 一只龟同时只挂一条链路(重连覆盖)
	var t: Texture2D = load("res://assets/sprites/vfx/fx-trail.png")
	var spr: Sprite3D = null
	if t != null:
		spr = Sprite3D.new()
		spr.texture = t
		spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		spr.axis = Vector3.AXIS_Y
		spr.modulate = Color(0.15, 0.15, 0.18, 0.85)             # 墨线(近黑)
		spr.pixel_size = 0.01
		spr.no_depth_test = true
		add_child(spr)
	_ink_links.append({"a": a, "b": b, "until": _t + INK_LINK_SEC, "spr": spr, "caster": caster})

func _drop_ink_link_of(u: Dictionary) -> void:
	for i in range(_ink_links.size() - 1, -1, -1):
		var L: Dictionary = _ink_links[i]
		if L["a"] == u or L["b"] == u:
			if is_instance_valid(L["spr"]): L["spr"].queue_free()
			_ink_links.remove_at(i)

# 返回 u 所在的有效链路 {a,b,caster,until,spr}; 无 → 空字典 (不返 null: GDScript静态分析对"可能为null再下标"报Parse Error)
func _ink_link_of(u: Dictionary) -> Dictionary:
	for L in _ink_links:
		if _t >= float(L["until"]): continue
		if L["a"] == u and L["b"].get("alive", false): return L
		if L["b"] == u and L["a"].get("alive", false): return L
	return {}

func _ink_link_partner(u: Dictionary) -> Dictionary:             # 连接对象(仍在有效期且活着); 无 → 空字典
	var L: Dictionary = _ink_link_of(u)
	if L.is_empty(): return {}
	return L["b"] if L["a"] == u else L["a"]

func _tick_ink_links() -> void:                                  # 每帧: 线跟着两只龟脚底走; 到期/死亡→断
	for i in range(_ink_links.size() - 1, -1, -1):
		var L: Dictionary = _ink_links[i]
		var a: Dictionary = L["a"]; var b: Dictionary = L["b"]
		if _t >= float(L["until"]) or not a.get("alive", false) or not b.get("alive", false):
			if is_instance_valid(L["spr"]): L["spr"].queue_free()
			_ink_links.remove_at(i); continue
		var spr = L["spr"]
		if not is_instance_valid(spr): continue
		var wf: Vector3 = _world_pos(a["pos"], 0.06)             # 贴地(脚底)
		var wt: Vector3 = _world_pos(b["pos"], 0.06)
		var seg: Vector3 = wt - wf
		var Lg: float = seg.length()
		if Lg < 0.01: continue
		var th: int = maxi(1, spr.texture.get_height())
		var tw_px: int = maxi(1, spr.texture.get_width())
		spr.pixel_size = (10.0 * WS) / float(th)                 # 线宽10码
		spr.position = wf + seg * 0.5
		spr.rotation = Vector3.ZERO
		spr.rotation.y = -atan2(seg.z, seg.x)
		spr.scale = Vector3(Lg / (float(tw_px) * spr.pixel_size), 1.0, 1.0)

func _ink_link_transfer(u: Dictionary, taken: float) -> void:    # 受伤30%以真实伤害传导给连接对象
	if _ink_link_busy or taken <= 0.0: return
	var L: Dictionary = _ink_link_of(u)
	if L.is_empty(): return
	var p: Dictionary = L["b"] if L["a"] == u else L["a"]
	var amt := int(taken * INK_LINK_TRANSFER)
	if amt <= 0: return
	# src = 施法的线条龟(不是受伤的那只敌人!) — 否则敌人"打了队友"会吃到吸血并被记进输出统计
	var sc: Dictionary = L["caster"] if L["caster"].get("alive", false) else u
	_ink_link_busy = true
	_apply_damage_from(sc, p, amt, Color("#b0b0c8"), 0.0, true, true)   # raw=真实(墨迹系·速写融入被动) / from_equip=true 防反伤·叠层循环
	_ink_link_busy = false

var _disc_tex_cache: ImageTexture = null
func _make_disc_texture() -> ImageTexture:   # Image真圆(角alpha=0); 白底modulate上色; 缓存
	if _disc_tex_cache != null:
		return _disc_tex_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c   # 0=心 1=边
			var a := 0.0
			if d < 1.0:
				a = (1.0 - d) * 0.55                              # 软径向衰减, 边=0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_disc_tex_cache = ImageTexture.create_from_image(img)
	return _disc_tex_cache

var _fire_glow_cache: ImageTexture = null
func _make_fire_glow_tex() -> ImageTexture:   # Image真圆软发光(亮核软边, 角alpha=0不显方块); 火焰blob用, 缓存
	if _fire_glow_cache != null:
		return _fire_glow_cache
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N - 1) / 2.0
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := 0.0
			if d < 1.0:
				a = pow(1.0 - d, 1.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_fire_glow_cache = ImageTexture.create_from_image(img)
	return _fire_glow_cache

func _sk_rainbow_storm(u: Dictionary) -> void:                  # 彩虹龟·全色风暴 ✅ (自身处圆形风暴区4秒/每0.5秒/圈内-20%护甲魔抗; 期间锁龟能/不被控打断)
	u["storm_until"] = _t + 4.0                 # 风暴4秒期间龟能锁定(用户)
	var center: Vector2 = u["pos"]              # 固定施法点
	var radius := 140.0
	var disc := Sprite3D.new()                  # 贴地圆形风暴区(软圆盘)
	disc.texture = _make_disc_texture()
	disc.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	disc.axis = Vector3.AXIS_Y                  # 躺平贴地
	disc.shaded = false
	disc.transparent = true
	disc.modulate = Color(1.0, 0.5, 0.8, 0.4)
	disc.position = _world_pos(center, 0.04)
	disc.pixel_size = (radius * 2.0 * WS) / 128.0
	_world.add_child(disc)
	u["storm_disc"] = disc
	var tw := _reg_tween()
	for i in range(8):   # 4秒 / 每0.5秒 = 8跳
		tw.tween_callback(_rainbow_storm_tick.bind(u, center, radius, i))
		tw.tween_interval(0.5)
	tw.tween_callback(_rainbow_storm_end.bind(u))

func _rainbow_storm_tick(u: Dictionary, center: Vector2, radius: float, ti: int) -> void:
	if not u.get("alive", false):
		return
	var cols := [Color(1, 0.35, 0.4), Color(1, 0.65, 0.3), Color(1, 0.95, 0.4), Color(0.45, 1, 0.5), Color(0.4, 0.7, 1), Color(0.75, 0.5, 1)]
	var disc = u.get("storm_disc", null)
	if disc != null and is_instance_valid(disc):
		var c: Color = cols[ti % cols.size()]
		disc.modulate = Color(c.r, c.g, c.b, 0.42)   # 七彩色循环
	for k in range(6):   # 旋转七彩粒子(沿圆弧切向→风暴swirl), 基角每跳推进
		var ang := TAU * float(k) / 6.0 + float(ti) * 0.55
		var off := Vector2(cos(ang), sin(ang)) * (radius * 0.82)
		var sh := Sprite3D.new()
		sh.texture = _make_disc_texture()   # 用缓存Image圆(不显方块), modulate上色
		sh.modulate = cols[(ti + k) % cols.size()]
		sh.pixel_size = 0.004
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		sh.position = _world_pos(center + off, 0.45)
		_world.add_child(sh)
		var ang2 := ang + 0.9
		var off2 := Vector2(cos(ang2), sin(ang2)) * (radius * 0.82)
		var twr := _reg_tween()
		twr.set_parallel(true)
		twr.tween_property(sh, "position", _world_pos(center + off2, 0.78), 0.5)
		twr.tween_property(sh, "modulate:a", 0.0, 0.5)
		twr.chain().tween_callback(sh.queue_free)
	for o in _enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			_buff(o, "def", -0.20, true, 0.65)   # 圈内-20%护甲
			_buff(o, "mr", -0.20, true, 0.65)    # 圈内-20%魔抗
			_apply_damage_from(u, o, _atk_dmg(u, 0.1, o, true), Color("#ff8ad8"))
			_apply_damage_from(u, o, int(u["atk"] * 0.05), Color("#fff0a0"), 0.0, true)   # 8跳共0.8魔+0.4真=原值

func _rainbow_storm_end(u: Dictionary) -> void:
	var disc = u.get("storm_disc", null)
	if disc != null and is_instance_valid(disc):
		var tw := _reg_tween()
		tw.tween_property(disc, "modulate:a", 0.0, 0.4)
		tw.chain().tween_callback(disc.queue_free)
	u["storm_disc"] = null

func _sk_fortune_coins(u: Dictionary) -> void:                  # 财神龟·聚财 (旧·已从3选1移除·留死函数无害)
	u["gold"] += 10
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.5), 46.0)

func _sk_fortune_buyequip(u: Dictionary) -> void:              # 财神龟·招财进宝(封板·60龟能起): 首抽1件1/2/3费临时装备(1★·战后消失不占槽)→消耗变160/240/460; 后续释放升1星(精确数值delta) → 3★后消耗回60且每次释放回复1×ATK生命
	var star: int = int(u.get("buyequip_star", 0))
	if star == 0:                                               # 首抽临时装备
		var iid: String = _chest_pick_equip([1, 2, 3])
		if iid == "": return
		if not u.has("equips"): u["equips"] = []
		u["equips"].append({"id": iid, "star": 1})
		_eq_apply_one_stats(u, iid, 1)
		u["buyequip_id"] = iid; u["buyequip_star"] = 1
		var tier: int = int(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("cost", 1))
		u["energy_cost"]["fortuneBuyEquip"] = 60.0 + [100.0, 180.0, 400.0][clampi(tier - 1, 0, 2)]   # 消耗随抽到费拉长
		_float_text(u["pos"] + Vector2(0, -72), "招财! " + str(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("name", iid)), Color("#ffd93d"))
	elif star >= 3:                                             # 3★满: 回复1×ATK生命
		_heal(u, u["atk"])
		_float_text(u["pos"] + Vector2(0, -72), "招财·满! 回血", Color("#ffd93d"))
	else:                                                       # 升星: 应用精确数值delta(旧星→新星) + 同步equips条目星级
		var iid2: String = str(u.get("buyequip_id", ""))
		_eq_star_delta_stats(u, iid2, star, star + 1)          # 精确升星: 加(新星-旧星)属性差量(flag类缩放留F5)
		for e in u.get("equips", []):                          # 同步equips条目(战后清理/信息面板显示星级一致)
			if str(e.get("id", "")) == iid2:
				e["star"] = star + 1
				break
		u["buyequip_star"] = star + 1
		if star + 1 >= 3: u["energy_cost"]["fortuneBuyEquip"] = 60.0   # 满星→价回60
		_float_text(u["pos"] + Vector2(0, -72), "招财·升星 %d★" % (star + 1), Color("#ffd93d"))
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.6), 56.0)

func _sk_lightning_shield(u: Dictionary) -> void:              # 闪电龟·雷盾 (用户2026-07-07: 3ATK护盾5秒, 盾在时反击0.1A魔法叠电击=见_apply_damage_from)
	_grant_shield(u, u["atk"] * 3.0, 5.0)   # 雷盾5秒(与反击窗口thunder_shield_until同步·封板)
	u["thunder_shield_until"] = _t + 5.0
	_skill_ring(u["pos"], Color(0.45, 0.85, 1.0, 0.5), 50.0)

func _sk_rainbow_reflect(u: Dictionary) -> void:               # 彩虹龟·反射 ✅ (敌我交替弹射: 治友0.5ATK/伤敌0.5ATK魔法)
	var allies := _allies_of(u)
	var enemies := _enemies_of(u)
	for i in range(6):
		if i % 2 == 0:
			if not allies.is_empty():
				var a = allies[(i / 2) % allies.size()]
				_heal(a, u["atk"] * 0.5)
				_skill_ring(a["pos"], Color(0.7, 0.9, 1.0, 0.5), 40.0)
		else:
			if not enemies.is_empty():
				var e = enemies[(i / 2) % enemies.size()]
				if e.get("alive", false):
					_apply_damage_from(u, e, _atk_dmg(u, 0.5, e, true), Color("#ff8ad8"))

func _shock_dmg(u: Dictionary) -> int:   # 被动电击真伤 0.82×ATK; 涌动期间×(1+50%)
	var b: float = 1.0 + (float(u.get("shock_boost_pct", 0.0)) if _t < float(u.get("shock_boost_until", 0.0)) else 0.0)
	return int(u["atk"] * 0.82 * b)

func _sk_lightning_surge(u: Dictionary, tgt: Dictionary) -> void: # 闪电龟·涌动 ✅
	if tgt != null and tgt.get("alive", false):
		_apply_damage_from(u, tgt, int(u["atk"] * 1.23), Color("#4dabf7"), 0.0, true)   # 立即1次被动电击=真实(原误为魔法)
	u["shock_boost_until"] = _t + 5.0      # 5秒内被动电击真伤+50%(窄化; 原误为通用+50%攻击+stray层)
	u["shock_boost_pct"] = 0.5
	_skill_ring(u["pos"], Color(0.45, 0.85, 1.0, 0.5), 52.0)

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 (用户2026-07-07: 3.5A护盾4秒+反击0.14A魔法)
	_grant_shield(u, u["atk"] * 3.5, 4.0)   # 凤凰熔岩盾4秒(与反击窗口lava_shield_until同步·封板)
	u["lava_shield_until"] = _t + 4.0          # 4秒内每受一段攻击反击0.14×ATK魔法(见_apply_damage_from)
	_skill_ring(u["pos"], Color(1.0, 0.5, 0.2, 0.5), 50.0)

func _sk_phoenix_haste(u: Dictionary) -> void:                   # 凤凰龟·技三主动 (用户2026-07-07: 自身+50%攻速+50%移速4秒·配合喷火随攻速增伤; 强化涅槃被动在spawn施加)
	u["haste_mult"] = 1.5; u["haste_until"] = _t + 4.0          # +50%攻速(复用祝福haste机制)
	u["spd_move_mult"] = 1.5; u["spd_dbf_until"] = _t + 4.0     # +50%移速(复用spd_move_mult机制)
	_aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 84.0, Color(1.0, 0.55, 0.15, 0.6), 4.0)   # 烈焰加速火环(强化涅槃+50%攻速移速4秒)

func _sk_angel_ascend(u: Dictionary) -> void:                   # 天使龟·飞升 (用户2026-07-06: +20%攻速+25码射程·到战斗结束·可叠加无上限; 移速2026-07-11改+5%)
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) * 1.2       # +20%攻速(永久·叠加)
	u["move_spd"] = float(u["move_spd"]) * 1.05                 # +5%移速(永久·叠加·用户2026-07-11: 10%→5%)
	u["atk_range"] = float(u["atk_range"]) + 25.0              # +25码射程(永久·叠加)
	_aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 88.0, Color(1.0, 0.92, 0.55, 0.62), 2.4)   # 金光飞升圣环(施法瞬间圣环渐亮)

# 天使龟·平等 ✅ (封板2026-07-06 选A远程投射·60龟能): 站原地射2道圣光斩弧共200%物理·带10%施法吸血; 目标A级及以上追加从天而降审判光柱=(50%ATK+目标已损生命10%)真伤·无视双抗·同10%吸血
func _sk_angel_equality(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	_flash(u, Color(1.0, 0.92, 0.6))                            # 举裁蓄力·自身泛淡金吸血光
	var order := {"C": 0, "B": 1, "A": 2, "S": 3, "SS": 4, "SSS": 5}
	# 4道圣光斩弧(远程投射·站原地不突进): 各50%ATK物理·共200%(2ATK)·带10%施法吸血(用户2026-07-11:2道100%→4道50%)
	for i in range(4):
		_pending_shots.append({"delay": 0.10 * float(i), "src": u, "fn": func():
			if tgt == null or not tgt.get("alive", false): return
			_bolt_line(u["pos"], tgt["pos"], Color(1.0, 0.92, 0.66))      # 金白斩弧曳光
			_skill_ring(tgt["pos"], Color(1.0, 0.9, 0.6, 0.5), 44.0)
			_apply_damage_from(u, tgt, _atk_dmg(u, 0.5, tgt, false), Color("#ffe9a8"), 0.10)   # 100%物理·10%吸血
			_apply_damage_from(u, tgt, _mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 审判(每段攻击命中都吃·独立结算不触发其他被动·用户2026-07-10"每次攻击都要吃")
		})
	# A级及以上→第3段从天而降审判光柱: (50%ATK + 目标已损生命10%)真伤·无视双抗·同10%吸血
	if int(order.get(str(tgt.get("rarity", "C")), 0)) >= 2:
		_pending_shots.append({"delay": 0.42, "src": u, "fn": func():
			if tgt == null or not tgt.get("alive", false): return
			_angel_judgment_pillar(tgt["pos"])
			var lost: float = maxf(0.0, float(tgt["maxHp"]) - float(tgt["hp"]))
			var tru: int = maxi(1, int(float(u["atk"]) * 0.5 + lost * 0.10))
			_apply_damage_from(u, tgt, tru, Color(1.0, 0.96, 0.76), 0.10, true)   # 真伤无视双抗·10%吸血
			_apply_damage_from(u, tgt, _mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 光柱也带审判(用户2026-07-11:附带被动·10%当前HP)
			_flash(tgt, Color(1.0, 0.96, 0.76))
		})

# 天使审判光柱: 从天而降金白光束(强闪骤降) + 命中金环 (平等第3段·A级以上)
func _angel_judgment_pillar(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(1.0, 0.9, 0.5, 0.85), 70.0)
	var pil := Sprite3D.new()
	pil.texture = _make_fire_glow_tex()
	pil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pil.shaded = false; pil.transparent = true
	pil.pixel_size = 0.013
	pil.modulate = Color(1.0, 0.96, 0.7, 0.0)
	pil.scale = Vector3(0.5, 3.0, 1.0)
	pil.position = _world_pos(pos2d, 2.4)                       # 高空起
	_world.add_child(pil)
	var tp := _reg_tween(); tp.set_parallel(true)
	tp.tween_property(pil, "modulate:a", 0.95, 0.08)           # 骤降强闪
	tp.tween_property(pil, "position", _world_pos(pos2d, 0.7), 0.14)
	tp.chain().tween_property(pil, "modulate:a", 0.0, 0.22)
	tp.chain().tween_callback(pil.queue_free)

func _sk_headless_fear(u: Dictionary, _tgt = null) -> void:      # 无头·恐吓(封板·110龟能): 半径200码内所有敌 定身+缴械+锁技3秒(stun_until·龟能照充满也不放·蛋免控·无伤害)
	var cx: Vector2 = u["pos"]
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(cx) > 200.0: continue
		if o.get("_eggImmune", false): continue
		o["stun_until"] = maxf(float(o.get("stun_until", 0.0)), _t + _cc_dur(o, 3.0))
		_float_text(o["pos"] + Vector2(0, -48), "恐吓", Color("#9b3bff"))
	_skill_ring(cx, Color(0.6, 0.2, 0.7, 0.5), 200.0)

func _sk_headless_tendrils(u: Dictionary, _tgt = null) -> void:  # 无头·万千触须(封板·160龟能·虐杀原形): 全场无差别触须·伸(穿过)→停→收(脱离)约4s·自身也硬控·本次+22%吸血
	u["stun_until"] = maxf(float(u.get("stun_until", 0.0)), _t + 4.0)   # 自身硬控全程(施法动作·亡灵拉全场自己也搭进去)
	var center: Vector2 = u["pos"]
	var pass_fn := func():                                      # 伸/穿过(≈0.3s铺满): 无差别 敌1A+眩晕 / 友0.5A+眩晕(刷新不叠)
		for o in _units:
			if not o.get("alive", false) or o == u: continue
			var sc: float = 1.0 if o["side"] != u["side"] else 0.5
			_apply_damage_from(u, o, _atk_dmg(u, sc, o), Color("#9b3bff"), 0.22)
			if not o.get("_eggImmune", false):
				o["stun_until"] = maxf(float(o.get("stun_until", 0.0)), _t + 2.7)   # 眩晕持续到脱离
				o["_tendril_stun"] = true
		_skill_ring(center, Color(0.42, 0.16, 0.62, 0.5), 720.0)
	_pending_shots.append({"delay": 0.3, "fn": pass_fn, "src": u})
	var detach_fn := func():                                    # 收/脱离(≈3.0s): 无差别 敌1.5A / 友0.5A + 回复行动(解眩晕)
		for o in _units:
			if not o.get("alive", false) or o == u: continue
			var sc: float = 1.5 if o["side"] != u["side"] else 0.5
			_apply_damage_from(u, o, _atk_dmg(u, sc, o), Color("#ff3b6b"), 0.22)
			if o.get("_tendril_stun", false):
				o["_tendril_stun"] = false
				o["stun_until"] = _t   # 解眩晕→回复行动
		_skill_ring(center, Color(1.0, 0.24, 0.42, 0.5), 720.0)
	_pending_shots.append({"delay": 3.0, "fn": detach_fn, "src": u})

func _sk_headless_soul_charge(u: Dictionary) -> void:           # 无头·灵魂打击(封板·80龟能·充能强化普攻): 满能→下次普攻附0.9A物理+20%当前生命魔法(在_basic_attack消费)·触发后龟能清零重充
	u["headless_soul_buff"] = true
	_float_text(u["pos"] + Vector2(0, -56), "灵魂蓄力", Color("#9b3bff"))
	_skill_ring(u["pos"], Color(0.6, 0.23, 0.7, 0.5), 44.0)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子 ✅
	u["gold"] += randi_range(3, 8)   # 2~6→3~8 (恢复文本设计值)
	_heal(u, u["maxHp"] * 0.08)
	# (删: "放梭哈后给护盾"=4选1下死逻辑, 不可能同时有骰子+梭哈, 用户指出)

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒(用户封板: 1.5A护盾+全体友军护甲魔抗+15%·4秒)
	_grant_shield(u, u["atk"] * 1.5, 4.0)                        # 4秒限时(封板L562·通用护盾4s全局L74·此前"既有盾改4秒"漏补)
	for o in _allies_of(u):
		_buff(o, "def", 0.15, true, 4.0); _buff(o, "mr", 0.15, true, 4.0)

# 水晶结晶叠层+满5引爆 (普攻/水晶球ray/本体主动共享·同一目标"crystal"层→天然共享层数): 叠n层(上限5)·满5→清零+19%目标最大生命魔法(吃魔抗·封板)+削魔抗-20%+紫辉爆
func _crystal_stack(src: Dictionary, tgt: Dictionary, n: int) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var cv := _add_stack(tgt, "crystal", n, 5)
	if cv >= 5:
		_consume_stacks(tgt, "crystal")
		_apply_damage_from(src, tgt, _mitigate(src, tgt["maxHp"] * 0.19, tgt, true), Color("#c9b0ff"), 0.0, false)   # 引爆19%最大生命魔法(吃魔抗·封板·原flat绕魔抗=bug)
		_buff(tgt, "mr", -0.2, true)
		_crystal_detonate(tgt["pos"])

# 水晶龟·碎晶爆破(封板L566·100龟能): 对全体敌3段共0.7A魔法+0.1A真实 + 每段叠1层结晶=全体各叠3层(满5引爆·与普攻/水晶球共享层数)
func _sk_crystal_burst(u: Dictionary, tgt) -> void:
	_sk_dmg(u, tgt, {"magic": 0.7, "true": 0.1, "hits": 3, "aoe": true, "name": "水晶爆!", "color": Color("#9bdcff")})
	for o in _enemies_of(u):
		if o.get("alive", false):
			_crystal_stack(u, o, 3)   # 每段叠1层×3段=各叠3层(封板L566·原_sk_dmg漏叠结晶)

# 水晶龟·水晶球 本体主动(封板L571·70龟能): 朝目标射一道水晶光线=2段共1.0A魔法 + 叠2层结晶(与水晶球随从共享满5引爆)·水晶球随从在spawn gate召唤
func _sk_crystal_orb(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	_bolt_line(u["pos"], tgt["pos"], Color("#c9b0ff"))
	_crystal_beam(u["pos"], tgt["pos"], Color("#c9b0ff"))
	for i in range(2):                                           # 2段共1.0A魔法(每段0.5A·raw避免二次减免)
		if not tgt.get("alive", false): break
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.5, tgt, true), Color("#c9b0ff"), 0.0, true)
	_crystal_stack(u, tgt, 2)                                   # 叠2层结晶(封板)

# 宝箱藏宝图·15件专属战利品池 (封板L592-594·效果取自Phaser chest.js实时适配): 基础/进阶/传说三档
const _CHEST_TREASURE_POOL := {
	"basic":  ["dagger", "wood_shield", "rum", "blood_dice", "chain", "stone"],
	"adv":    ["long_sword", "bloodblade", "flint", "gem_armor", "poison", "phoenix_statue"],
	"legend": ["crown", "thunder", "starlight"],
}
const _CHEST_TREASURE_NAME := {
	"dagger": "短刃", "wood_shield": "木盾", "rum": "朗姆酒", "blood_dice": "血筛子", "chain": "锁链", "stone": "石头",
	"long_sword": "长剑", "bloodblade": "嗜血之刃", "flint": "火石", "gem_armor": "宝石甲", "poison": "毒箭", "phoenix_statue": "凤凰雕像",
	"crown": "王冠", "thunder": "雷刃", "starlight": "星辉",
}

# 宝箱·藏宝图(封板L590-594·完整15件专属池): 造成伤害积累财宝值(=dmg_dealt), 过阈值开专属战利品(分档池·不重复)+回血, 一场最多5件
func _chest_treasure_tick(u: Dictionary) -> void:
	var opened: int = int(u.get("chest_opened", 0))
	if opened >= 5:
		return
	var lvl_mult: float = 1.0 + 0.03 * float(maxi(0, int(u.get("level", 1)) - 1))   # 阈值随等级+3%/级(封板)
	var thresh: Array = [80.0, 130.0, 240.0, 360.0, 590.0]
	if float(u.get("dmg_dealt", 0.0)) < float(thresh[opened]) * lvl_mult:
		return
	u["chest_opened"] = opened + 1
	var group: String = ["basic", "basic", "adv", "adv", "legend"][opened]   # 第1-2箱基础/3-4进阶/5传说
	var heal_pct: float = [0.08, 0.08, 0.11, 0.11, 0.15][opened]
	var tid: String = _chest_pick_treasure(u, group)
	if tid != "":
		_chest_apply_treasure(u, tid)
		if u.get("chest_greed", false): _chest_greed_apply(u, 1)   # 贪婪: 新开1件→+4%攻+7%最大生命
		_float_text(u["pos"] + Vector2(0, -72), "开箱! " + str(_CHEST_TREASURE_NAME.get(tid, tid)), Color("#ffd93d"))
	_heal(u, u["maxHp"] * heal_pct)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.5), 52.0)

func _chest_pick_treasure(u: Dictionary, group: String) -> String:   # 该档随机1件(不重复)·档抽光→退回全池任意未拥有
	var owned: Dictionary = u.get("chest_treasures", {})
	var avail: Array = []
	for tid in _CHEST_TREASURE_POOL.get(group, []):
		if not owned.has(tid): avail.append(tid)
	if avail.is_empty():
		for g in ["basic", "adv", "legend"]:
			for tid in _CHEST_TREASURE_POOL[g]:
				if not owned.has(tid): avail.append(tid)
	if avail.is_empty(): return ""
	return str(avail[randi() % avail.size()])

func _chest_apply_treasure(u: Dictionary, tid: String) -> void:   # 逐件bespoke效果(属性即时应用·机制类置flag由钩子读)
	if not u.has("chest_treasures"): u["chest_treasures"] = {}
	u["chest_treasures"][tid] = true
	match tid:
		"dagger":         _buff(u, "atk", 0.25, true, 99999.0)                                              # 短刃: +25%攻
		"wood_shield":    _buff(u, "def", 0.20, true, 99999.0); _buff(u, "mr", 0.20, true, 99999.0)          # 木盾: +20%双抗
		"rum":            u["chest_rum_t"] = 0.0                                                             # 朗姆酒: 每10秒回8%maxHp(周期tick读flag)
		"blood_dice":     u["crit"] = float(u.get("crit", 0.0)) + 0.35                                       # 血筛子: +35%暴击
		"chain":          u["chest_aoe_mult"] = 2.0                                                          # 锁链: 砸击AOE距离/射程翻倍(_chest_basic钩子)
		"stone":          u["chest_rock_bonus"] = float(u.get("chest_rock_bonus", 0.0)) + 1.0                # 石头: 砸击额外+100%护甲+100%魔抗(_chest_basic钩子)
		"long_sword":     _buff(u, "atk", 0.45, true, 99999.0)                                               # 长剑: +45%攻
		"bloodblade":     u["lifesteal"] = float(u.get("lifesteal", 0.0)) + 0.25                             # 嗜血之刃: +25%吸血
		"flint":          pass                                                                               # 火石: 命中→灼烧(_apply_damage_from钩子·防循环)
		"gem_armor":      _buff(u, "def", 0.25, true, 99999.0); _buff(u, "mr", 0.25, true, 99999.0); u["maxHp"] += 60.0; u["hp"] += 60.0   # 宝石甲: +25%双抗+60血
		"poison":         pass                                                                               # 毒箭: 命中→治疗削减-50%5秒(_apply_damage_from钩子·防循环)
		"phoenix_statue": u["_chest_revive"] = true                                                          # 凤凰雕像: 首死25%最大生命复活(_kill钩子)
		"crown":          _buff(u, "atk", 0.40, true, 99999.0); u["crit"] = float(u.get("crit", 0.0)) + 0.40; u["crit_dmg"] = float(u.get("crit_dmg", 1.5)) + 0.25; u["lifesteal"] = float(u.get("lifesteal", 0.0)) + 0.15   # 王冠: +40攻/+40暴/+25爆伤/+15吸血
		"thunder":        pass                                                                               # 雷刃: 命中叠金闪电满5引爆1.0A真伤(_apply_damage_from钩子·防循环)
		"starlight":      u["chest_starlight"] = true                                                        # 星辉: 所有伤害转真实(_apply_damage_from raw钩子·armor全绕层过局限留F5)

func _chest_pick_equip(costs: Array) -> String:
	var pool: Array = []
	for eq in DataRegistry.phase2_equipment:
		if int(eq.get("cost", 0)) in costs:
			pool.append(str(eq.get("id", "")))
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

func _sk_chest_inventory(u: Dictionary) -> void:                 # 宝箱龟·清点财宝 ✅
	var bonus: float = 1.0 + 0.14 * floorf(u["dmg_dealt"] / 100.0)   # 每100财宝值(=造成伤害)技能强度+14%
	_heal(u, u["maxHp"] * 0.05 * bonus)
	_grant_shield(u, u["atk"] * 0.6 * bonus)

func _chest_basic(u: Dictionary, tgt: Dictionary) -> void:       # 普攻·宝箱砸击(封板): K'Sante一段Q式·朝目标前方短直线AOE·各1A物理(近战扫一小片非单体)
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var aoe_mult: float = float(u.get("chest_aoe_mult", 1.0))       # 锁链loot将来翻倍AOE距离/射程钩子(=1未装)
	var reach: float = 170.0 * aoe_mult
	var halfw: float = 62.0 * aoe_mult
	var rock: float = float(u.get("chest_rock_bonus", 0.0))         # 石头loot将来额外+100%护甲+100%魔抗钩子(=0未装)
	var bonus: int = int((u["def"] + u["mr"]) * rock)
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = rel.dot(dir)
		if along < -18.0 or along > reach: continue
		if (rel - dir * along).length() > halfw: continue
		_apply_damage_from(u, o, _atk_dmg(u, 1.0, o) + bonus, Color("#ffd93d"))
	_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * reach, 96.0, Color(1.0, 0.85, 0.25, 0.7), 0.26)   # 短直线冲击(用户#3"参考lol ksante一段Q")
	_burst_vfx("res://assets/sprites/vfx/treasure-slam.png", u["pos"] + dir * (reach * 0.55), 150.0)   # 砸点金光爆(用户#3"参考lol ksante一段Q·aoe短直线")

func _sk_chest_cannon(u: Dictionary, tgt) -> void:              # 技三·财宝炮击(封板·120龟能): 蓄力→朝一条直线发长激光→线上所有敌各3A物理+击飞+击退 (贪婪打包被动在登场gate)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if not _on_line(u["pos"], dir, o["pos"], 58.0): continue
		_apply_damage_from(u, o, _atk_dmg(u, 3.0, o), Color("#ffe066"))
		_knockback(u, o, 60.0, 1.2, 1.4)                            # 击飞+击退
	_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * 1300.0, 132.0, Color(1.0, 0.9, 0.3, 0.85), 0.55)   # 财宝炮击长激光(用户07-07"对一条直线·类似手枪长激光")

func _sk_chest_storm(u: Dictionary, tgt) -> void:              # 技二·财宝风暴(封板·100龟能): 以当前目标为心400码圆形风暴·持续2.5s每0.5s一跳(5跳)·圈内敌各0.2A物理(共1.0A)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var center: Vector2 = tgt["pos"]
	for i in range(5):
		var fn := func():
			for o in _enemies_of(u):
				if o.get("alive", false) and o["pos"].distance_to(center) <= 400.0:
					_apply_damage_from(u, o, _atk_dmg(u, 0.2, o), Color("#ffd93d"))
			_skill_ring(center, Color(1.0, 0.82, 0.2, 0.4), 400.0)
		_pending_shots.append({"delay": float(i) * 0.5, "fn": fn, "src": u})

func _chest_greed_apply(u: Dictionary, n: int) -> void:        # 贪婪(技三打包被动): 每携带1件装备永久+4%攻+7%最大生命 (单位=登场base快照·不复利)
	if n <= 0: return
	u["base_atk"] = float(u["base_atk"]) + float(u.get("chest_greed_atk_unit", 0.0)) * n
	var hb: float = float(u.get("chest_greed_hp_unit", 0.0)) * n
	u["maxHp"] = float(u["maxHp"]) + hb
	u["hp"] = float(u["hp"]) + hb
	_recalc_stats(u)

func _sk_star_gravity_warp(u: Dictionary) -> void:             # 星际龟·扭曲空间(用户封板·120龟能·吃星能): 普通=敌阵中心500码全体0.8A魔法; 星能满=同上+把500码内敌拖拽拉向中心(发条R集火)+消耗全部星能
	var es: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false): es.append(o)
	if es.is_empty(): return
	var center := Vector2.ZERO
	for o in es: center += o["pos"]
	center /= float(es.size())
	var charged: bool = float(u.get("star_energy", 0.0)) >= u["maxHp"] * 0.40   # 星能满
	for o in es:
		if o["pos"].distance_to(center) <= 500.0:
			_apply_damage_from(u, o, _atk_dmg(u, 0.8, o, true), Color("#b09bff"))
			if charged and not o.get("_eggImmune", false):                      # 强化: 拖拽拉向中心集火
				var dir: Vector2 = (center - o["pos"])
				if dir.length() > 1.0:
					o["pos"] += dir.normalized() * minf(dir.length() * 0.6, 200.0)
	if charged:
		u["star_energy"] = 0.0                                                  # 星能满强化→消耗全部
	_burst_vfx("res://assets/sprites/vfx/fx-black-hole.png", center, 260.0, 0.12)   # 引力黑洞=黑色椭圆(用户2026-05-29"黑洞状态下用黑色椭圆代替那个位置")
	_skill_ring(center, Color(0.7, 0.6, 1.0, 0.42), 500.0)   # 500码拖拽范围环(发条R式)

func _sk_star_wave(u: Dictionary) -> void:                       # 星际龟·星波(封板2026-07-07·100龟能·吃星能): 普通=自身为心环形星波扩散·经过敌1.0A魔法; 星能满强化=环形波+召唤巨彗星砸敌阵中心额外1.5A魔法(龙王R天崩地裂式)+消耗全部星能; 不减速不击飞
	var charged: bool = float(u.get("star_energy", 0.0)) >= u["maxHp"] * 0.40
	var es: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false): es.append(o)
	for o in es:                                                 # 环形星波·扩散经过全体敌
		_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#c9b0ff"))
	_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", u["pos"], 520.0, 0.08)   # 环形星波扩散(用户#3"由龟中心释放环形波")
	if charged and not es.is_empty():                            # 强化: 巨彗星砸敌阵中心+大冲击波额外1.5A
		var center := Vector2.ZERO
		for o in es: center += o["pos"]
		center /= float(es.size())
		for o in es:
			if o.get("alive", false) and o["pos"].distance_to(center) <= 400.0:
				_apply_damage_from(u, o, _atk_dmg(u, 1.5, o, true), Color("#ffd0ff"))
		_burst_vfx("res://assets/sprites/vfx/comet-impact.png", center, 280.0, 1.6)   # 巨彗星砸下(用户#3"召唤巨大彗星飞向战场·爆炸释放大冲击波"·龙王R式)
		_skill_ring(center, Color(1.0, 0.85, 1.0, 0.6), 400.0)   # 大冲击波
		u["star_energy"] = 0.0                                   # 星能满强化→消耗全部星能

func _sk_candy_hammer(u: Dictionary, tgt) -> void:              # 糖果龟·技能一糖果锤(封板·80龟能): 猛砸直线200码·总(1.8A+12%自maxHp)物理由命中敌均分·回血造成伤害40%
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var hits: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false) and _on_line(u["pos"], dir, o["pos"], 70.0) and o["pos"].distance_to(u["pos"]) <= 200.0:
			hits.append(o)
	if hits.is_empty(): hits.append(tgt)
	var total_raw: float = u["atk"] * 1.8 + u["maxHp"] * 0.12
	var per_raw: float = total_raw / float(hits.size())          # 命中敌均分总量
	var dealt: int = 0
	for o in hits:
		var d: int = _mitigate(u, per_raw, o, false)             # 物理减伤
		_apply_damage_from(u, o, d, Color("#ff9ed6"))
		dealt += d
	_heal(u, float(dealt) * 0.40)                                # 回血造成伤害40%
	_bolt_line(u["pos"], u["pos"] + dir * 200.0, Color(1.0, 0.62, 0.84, 0.5))   # 直线糖爆冲击(淡)
	_burst_vfx("res://assets/sprites/vfx/candy-burst.png", u["pos"] + dir * 110.0, 170.0)   # 糖爆(用户2026-07-07"蓄力举起糖果锤猛砸直线200码")

func _sk_candy_barrage(u: Dictionary, tgt) -> void:            # 糖果龟·技能二糖衣炮弹(封板·120龟能·船长R式): 敌最密集600码降炮弹雨2.5→4秒每0.5s一跳共8跳·友2%maxHp盾/敌0.2A+2%maxHp魔法+减速20%
	var es: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false): es.append(o)
	var center: Vector2 = tgt["pos"] if tgt != null else u["pos"]
	if not es.is_empty():
		var c := Vector2.ZERO
		for o in es: c += o["pos"]
		center = c / float(es.size())                            # 单位最密集区域(简化=敌质心)
	for i in range(8):
		var fn := func():
			for o in _units:
				if not o.get("alive", false): continue
				if o["pos"].distance_to(center) > 600.0: continue
				if o["side"] == u["side"]:
					_grant_shield(o, u["maxHp"] * 0.02, 2.0)     # 友军每跳2%maxHp护盾(限时盾)
				else:
					_apply_damage_from(u, o, int(u["atk"] * 0.2 + u["maxHp"] * 0.02), Color("#ff9ed6"))   # 敌0.2A+2%maxHp魔法
					o["spd_move_mult"] = 0.8
					o["spd_dbf_until"] = _t + 0.5                # 减速20%(每次受击刷新0.5s)
			_skill_ring(center, Color(1.0, 0.62, 0.84, 0.4), 600.0)
		_pending_shots.append({"delay": float(i) * 0.5, "fn": fn, "src": u})

func _sk_candy_bomb_feed(u: Dictionary) -> void:               # 糖果龟·技能三糖果炸弹(封板·喂续命): 炸弹活→上限+25%糖果龟maxHp+治疗10%(喂); 炸弹亡→召新HP=20%糖果龟maxHp (登场召唤+死亡爆炸在spawn/summon)
	var bomb = null
	for o in _units:
		if o.get("is_summon", false) and o.get("summon_owner", null) == u and o.get("summon_kind", "") == "candybomb" and o.get("alive", false):
			bomb = o; break
	if bomb != null:
		bomb["maxHp"] = float(bomb["maxHp"]) + u["maxHp"] * 0.25   # 上限+25%糖果龟maxHp
		bomb["hp"] = minf(float(bomb["maxHp"]), float(bomb["hp"]) + u["maxHp"] * 0.10)   # 治疗10%(喂续命)
		_float_text(bomb["pos"] + Vector2(0, -40), "喂!", Color("#ff9ed6"))
	else:
		_spawn_summon(u, "candybomb", u["maxHp"] * 0.20, 0.0, {   # 炸弹阵亡→召新(HP=20%糖果龟maxHp)
			"label": "糖果炸弹", "spr_id": "candy-bomb", "col_size": 20.0, "hp_w": 24.0,
			"no_basic": true, "no_move": true, "self_decay": 0.08, "death_aoe": 1.5,
		})

# 双头龟·选一套 (demo 默认套1). 每次攒满龟能 → 切形态 + 放新形态这套招.
# 双头·双生(改造): 切近战形态加成(maxHp+150%ATK·护甲+25%ATK·魔抗+25%ATK·攻-30%ATK·+110%ATK盾), 切远程撤销
func _two_head_apply_melee(u: Dictionary, on: bool) -> void:
	var buffed: bool = u.get("two_melee_buffed", false)
	if on and not buffed:
		var a: float = u["base_atk"]
		u["two_melee_buffed"] = true
		u["_th_hp"] = a * 1.5; u["_th_def"] = a * 0.25; u["_th_mr"] = a * 0.25; u["_th_atk"] = a * 0.30
		u["maxHp"] += u["_th_hp"]; u["hp"] += u["_th_hp"]
		u["base_def"] += u["_th_def"]; u["base_mr"] += u["_th_mr"]
		u["base_atk"] = maxf(1.0, u["base_atk"] - u["_th_atk"])
		_recalc_stats(u); _grant_shield(u, a * 1.1)
	elif not on and buffed:
		u["two_melee_buffed"] = false
		u["maxHp"] = maxf(1.0, u["maxHp"] - float(u.get("_th_hp", 0.0)))
		u["hp"] = minf(u["hp"], u["maxHp"])
		u["base_def"] = maxf(0.0, u["base_def"] - float(u.get("_th_def", 0.0)))
		u["base_mr"] = maxf(0.0, u["base_mr"] - float(u.get("_th_mr", 0.0)))
		u["base_atk"] += float(u.get("_th_atk", 0.0))
		_recalc_stats(u)

func _sk_two_head_strike(u: Dictionary, tgt) -> void:            # 双头·技能一 form-variant(封板): 远程=灵能冲击(全体0.85A+15%maxHp物理) / 近战=锤击(1.4A物理+获造成伤害50%护盾4秒)
	if u["melee"]:
		if tgt == null: tgt = _nearest_enemy(u)
		if tgt == null: return
		var dmg: int = _atk_dmg(u, 1.4, tgt)
		_apply_damage_from(u, tgt, dmg, Color("#ffb05c"))
		_grant_shield(u, dmg * 0.5, 4.0)                        # 获造成伤害50%护盾(4秒·限时盾)
	else:
		for o in _enemies_of(u):
			if not o.get("alive", false): continue
			_apply_damage_from(u, o, _atk_dmg(u, 0.85, o) + int(o["maxHp"] * 0.15), Color("#c0d0ff"))

func _sk_two_head_disrupt(u: Dictionary, tgt) -> void:           # 双头·技能二 form-variant(封板): 远程=精神干扰(1.0A魔法+治疗削减50%5s+破盾50%) / 近战=吸收(0.6A+8%maxHp物理+回血40%A+18%已损)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	if u["melee"]:
		var dmg: int = _atk_dmg(u, 0.6, tgt) + int(tgt["maxHp"] * 0.08)
		_apply_damage_from(u, tgt, dmg, Color("#c0d0ff"))
		_heal(u, u["atk"] * 0.4 + (u["maxHp"] - u["hp"]) * 0.18)   # 回血40%攻击力+18%已损生命
	else:
		if float(tgt.get("shield", 0.0)) > 0.0: tgt["shield"] = float(tgt["shield"]) * 0.5   # 破盾50%
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt, true), Color("#c0d0ff"))
		tgt["heal_reduce_until"] = _t + 5.0
		tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), 0.5)             # 治疗削减50%5秒

func _sk_two_head_fusion(u: Dictionary, tgt) -> void:            # 双头·技能三融合(封板): 主动魔法波(4段·物理80%+真实80%共1.6A); 锁形态/坚韧/合体近战属性在登场gate
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	for i in range(4):
		if not tgt.get("alive", false): break
		if i % 2 == 0: _apply_damage_from(u, tgt, _atk_dmg(u, 0.4, tgt), Color("#ffffff"))          # 物理
		else:          _apply_damage_from(u, tgt, int(u["atk"] * 0.4), Color("#ffffff"), 0.0, true) # 真实
	_skill_ring(tgt["pos"], Color(0.75, 0.6, 1.0, 0.5), 48.0)

func _two_head_after_cast(u: Dictionary, tgt) -> void:          # 被动·双生(封板): 放完技能一/二→自动切形态+属性互换+切换攻击+位移 (融合不调用)
	var to_ranged: bool = u["melee"]                            # 当前近战→切远程; 当前远程→切近战
	u["two_form"] = "ranged" if to_ranged else "melee"
	_two_head_apply_melee(u, not to_ranged)                     # 近战属性delta on/off(既有函数·存_th_*可逆)
	u["melee"] = not to_ranged
	u["atk_range"] = 400.0 if to_ranged else 70.0
	var et = _nearest_enemy(u)
	if to_ranged:                                               # 切远程: 位移350远离+目标1.4A物理+破甲-25%4秒
		if et != null:
			var away: Vector2 = (u["pos"] - et["pos"]).normalized()
			if away.length() < 0.1: away = Vector2.RIGHT
			var dest: Vector2 = u["pos"] + away * 350.0
			dest.x = clampf(dest.x, ARENA.position.x, ARENA.end.x)
			dest.y = clampf(dest.y, ARENA.position.y, ARENA.end.y)
			u["pos"] = dest
			_apply_damage_from(u, et, _atk_dmg(u, 1.4, et), Color("#c0d0ff"))
			_buff(et, "def", -0.25, true, 4.0)                 # 破甲-25%护甲4秒
	else:                                                      # 切近战: 跃扑目标+落地0.6A魔法+获通用护盾1.1A(4秒)
		if et != null:
			_dash_to(u, et, 50.0)
			_apply_damage_from(u, et, _atk_dmg(u, 0.6, et, true), Color("#ffb05c"))
		_grant_shield(u, u["atk"] * 1.1, 4.0)

# 熔岩龟·选一套 (demo 默认套A). 龟能满→放【当前形态】(小/火山)这套对应招. 攒怒变身在 _tick_periodic_passive.
func _sk_lava_cast(u: Dictionary, tgt: Dictionary, set_id: String = "A") -> void:   # 熔岩龟·按选中技分派(A地裂/B岩浆涌动/C喷射)×形态变体
	var volcano: bool = u.get("volcano", false)
	match set_id:
		"A":
			if volcano: _lava_volcano_erupt(u)
			else:       _lava_quake(u)
		"B":
			if volcano: _lava_flame_strike(u, tgt)
			else:       _lava_magma_surge(u, tgt)
		_:
			_lava_quake(u)

# 通用·击飞: 把 o 从 center 上抛+外推 (1:1 _lava_slam_impact 的击飞段, 抽公共)
func _knock_up(o: Dictionary, center: Vector2, vy: float) -> void:
	if o == null or not o.get("alive", false) or o.get("airborne", false):
		return
	var dir: Vector2 = (o["pos"] - center)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	o["airborne"] = true
	o["vy"] = vy
	o["vx"] = dir.x * KNOCK_PUSH * 0.7
	o["vz"] = dir.y * KNOCK_PUSH * 0.7

# ───────── 熔岩龟·持续地面区域系统 (岩浆池) ─────────
func _tick_lava_zones(_delta: float) -> void:   # 每帧: 周期结算池内敌 + 到期清理 (_process 内调)
	if _lava_zones.is_empty():
		return
	var keep: Array = []
	for z in _lava_zones:
		if _t >= float(z["next_tick"]):
			z["next_tick"] = float(z["next_tick"]) + 0.5
			var src: Dictionary = z["src"]
			if src != null and src.get("alive", false):
				var c: Vector2 = z["center"]
				var r: float = float(z["radius"])
				for o in _enemies_of(src):
					if not o.get("alive", false):
						continue
					if o["pos"].distance_to(c) > r:
						continue
					_apply_damage_from(src, o, _atk_dmg(src, 0.06, o, true), Color("#ff7a33"))   # 0.06×ATK魔/0.5s
					o["slow_until"] = maxf(float(o.get("slow_until", 0.0)), _t + 0.6); o["slow_mag"] = 0.65   # 地裂减速35%(move×0.65·用户2026-07-09"35"·≥0.6s续)
					_buff(o, "mr", -0.30, true, 0.6)                                              # 魔抗-30% (每跳刷新)
		if _t >= float(z["until"]):
			var disc = z.get("disc", null)
			if disc != null and is_instance_valid(disc):
				var tw := _reg_tween()
				tw.tween_property(disc, "modulate:a", 0.0, 0.35)
				tw.chain().tween_callback(disc.queue_free)
		else:
			keep.append(z)
	_lava_zones = keep

func _lava_quake(u: Dictionary) -> void:                         # 小·岩浆池: 敌最密处生成5秒岩浆池, 每0.5s池内敌 0.06ATK魔+减速35%+魔抗-30%
	var center: Vector2 = _densest_enemy_point(u, 180.0)
	var radius := 180.0
	var disc := Sprite3D.new()                                   # 持续贴地橙红岩浆盘
	disc.texture = _sheet("res://assets/sprites/vfx/fx_lava_pool.png")   # AI生成熔岩池贴图
	disc.billboard = BaseMaterial3D.BILLBOARD_DISABLED; disc.axis = Vector3.AXIS_Y   # 躺平贴地
	disc.shaded = false; disc.transparent = true
	disc.modulate = Color(1.0, 1.0, 1.0, 0.0)
	disc.pixel_size = (radius * 2.0 * WS) / 768.0
	disc.position = _world_pos(center, 0.035)
	_world.add_child(disc)
	var rot := _reg_tween().bind_node(disc).set_loops()        # 缓旋=熔岩流动(静态图+代码动)  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	rot.tween_property(disc, "rotation:y", TAU, 7.0).from(0.0)
	var pt := _reg_tween()                                     # 淡入 + 5秒缓脉动
	pt.tween_property(disc, "modulate:a", 0.92, 0.25)
	for i in range(10):                                          # 5s / 0.5s = 10 次脉动
		pt.tween_property(disc, "modulate:a", 0.7, 0.25)
		pt.tween_property(disc, "modulate:a", 0.92, 0.25)
	_lava_zones.append({
		"center": center, "radius": radius, "until": _t + 5.0,
		"next_tick": _t + 0.5, "src": u, "disc": disc,
	})
	_skill_ring(center, Color(1.0, 0.45, 0.15, 0.5), radius)

func _lava_volcano_erupt(u: Dictionary) -> void:                 # 火山·火山爆发: 娜美R式 一道熔岩浪横扫全场 — 超长矩形预警 → 岩浆浪墙从远端推到近端 (波前每过一敌 命中1次: 击退+5段0.5ATK魔+灼烧+回血12%)
	var dir: Vector2 = _densest_enemy_point(u, 400.0) - u["pos"]
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	var half_len := 600.0                                          # 半长: 浪覆盖以龟为中心 ±600px (全场长 1200px)
	var half_w := 80.0
	var origin: Vector2 = u["pos"]
	var ang := -atan2(dir.y, dir.x)                               # 世界Y旋转 (屏y→世界z 反号)
	var perp_axis := Vector2(-dir.y, dir.x)
	_anticipate(u); _shake(JUICE_SHAKE_HEAVY)
	# 1) 超长红矩形预警 (拉长 blob 沿 dir, ~0.6s, 横跨全场)
	var full_len := half_len * 2.0
	var tel := Sprite3D.new()
	tel.texture = _make_blob_texture()
	tel.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tel.axis = Vector3.AXIS_Y
	tel.shaded = false; tel.transparent = true
	tel.modulate = Color(1.0, 0.15, 0.05, 0.0)
	tel.position = _world_pos(origin, 0.03)                       # 中心=龟身 (浪以龟为中心向两端展开)
	tel.pixel_size = (full_len * WS) / 128.0
	tel.scale = Vector3(1.0, 1.0, (half_w * 2.0) / full_len)      # 沿 dir 长, 横向窄
	tel.rotation = Vector3(0.0, ang, 0.0)                        # 朝向 dir
	_world.add_child(tel)
	var tt := _reg_tween()
	tt.tween_property(tel, "modulate:a", 0.42, 0.18)
	tt.tween_interval(0.42)
	await tt.finished
	# 2) 岩浆浪墙 (GPUParticles3D): 宽墙面垂直于行进方向, 沿行进方向薄; 整堵墙从远端 origin+dir*half_len 推到近端 origin-dir*half_len (~0.7s)
	var wave := GPUParticles3D.new()
	wave.amount = 220
	wave.lifetime = 0.4                                           # 短拖尾 (~0.4s)
	wave.one_shot = false
	wave.explosiveness = 0.0                                      # 持续发射 (墙体连续, 非一次爆)
	wave.local_coords = false                                     # 世界坐标: 发射后粒子留在原地 → 形成拖尾, 不随墙体平移
	wave.preprocess = 0.1                                         # 预热: 出现即是完整墙体非空
	var wmat := ParticleProcessMaterial.new()
	wmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	wmat.emission_box_extents = Vector3(0.12, 0.06, (half_w * WS))   # 沿行进(本地x)薄, 垂直行进(本地z)宽=墙面; 旋转后对齐 dir
	wmat.direction = Vector3(0, 1, 0)                            # 主要向上喷 (火浪向上翻腾)
	wmat.spread = 32.0
	wmat.flatness = 0.0
	wmat.initial_velocity_min = 1.6
	wmat.initial_velocity_max = 4.2
	wmat.gravity = Vector3(0, -4.5, 0)                          # 下坠 → 翻卷的浪头
	wmat.scale_min = 0.7
	wmat.scale_max = 1.7
	# 颜色: 白热核 → 亮橙 → 暗红 → 透明 (火/岩浆)
	var wgrad := Gradient.new()
	wgrad.set_offset(0, 0.0); wgrad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))    # 白热
	wgrad.add_point(0.3, Color(1.0, 0.6, 0.18, 1.0))                            # 亮橙
	wgrad.add_point(0.7, Color(0.95, 0.24, 0.05, 0.85))                         # 暗红
	wgrad.set_offset(wgrad.get_point_count() - 1, 1.0)
	wgrad.set_color(wgrad.get_point_count() - 1, Color(0.45, 0.04, 0.0, 0.0))   # 透明熄灭
	var wramp := GradientTexture1D.new()
	wramp.gradient = wgrad
	wmat.color_ramp = wramp
	wave.process_material = wmat
	wave.draw_pass_1 = _make_glow_quad(0.6)
	wave.rotation = Vector3(0.0, ang, 0.0)                       # 旋转发射盒+墙面对齐 dir
	var far: Vector2 = origin + dir * half_len                    # 远端 (场外那头)
	wave.position = _world_pos(far, 0.12)                         # 起步: 远端, 略离地
	_world.add_child(wave)
	wave.emitting = true
	tel.modulate.a = 0.42
	# 3) 波前沿线推进 + 逐帧命中判定 (tween_method 推 front-distance d: 0→full_len, 0.7s)
	var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。                                       # 已命中敌 (each-once)
	var step := func(d: float) -> void:
		var front: Vector2 = far - dir * d                        # 当前波前位置 (从远端向近端推进)
		if is_instance_valid(wave):
			wave.position = _world_pos(front, 0.12)
		if is_instance_valid(tel):
			tel.modulate.a = lerpf(0.42, 0.12, clampf(d / full_len, 0.0, 1.0))
		var front_proj: float = front.dot(dir)                    # 波前沿 dir 的投影
		for o in _enemies_of(u):
			if not o.get("alive", false):
				continue
			if hit.has(o):
				continue
			var rel: Vector2 = o["pos"] - origin
			var perp: float = absf(rel.dot(perp_axis))
			if perp >= half_w:
				continue                                          # 不在浪宽内
			if o["pos"].dot(dir) > front_proj:
				continue                                          # 波前尚未扫到
			hit.append(o)                                         # 命中一次 (each-once; 用 Array 不用 Dictionary-key, 见下方注释)
			if not o.get("airborne", false):                      # 击退 (沿 dir 推 + 小竖速)
				o["airborne"] = true
				o["vy"] = 4.0
				o["vx"] = dir.x * KNOCK_PUSH
				o["vz"] = dir.y * KNOCK_PUSH
			for i in range(5):
				if not o["alive"]: break
				_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true), Color("#ff7a33"))
			if o["alive"]:
				_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
			_heal(u, u["maxHp"] * 0.12)
	_shake(JUICE_SHAKE_BIG)
	var travel := 0.7
	var wt := _reg_tween()
	wt.tween_method(step, 0.0, full_len, travel).set_trans(Tween.TRANS_SINE)
	wt.parallel().tween_property(tel, "modulate:a", 0.0, travel)   # 预警随浪推进淡出
	# 浪到端 → 停发射, 等拖尾消散, 清理 (用计时器避免 IntervalTweener 链式坑)
	await wt.finished
	if is_instance_valid(tel):
		tel.queue_free()
	if is_instance_valid(wave):
		wave.emitting = false
		await get_tree().create_timer(wave.lifetime + 0.1).timeout
		if is_instance_valid(wave):
			wave.queue_free()

func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 蓄力 → 目标脚下岩浆柱击飞 (1.5ATK魔 + 0.8ATK永久护盾)
	if tgt == null or not tgt.get("alive", false):
		return
	u["_slam"] = true
	_anticipate(u)
	var center: Vector2 = tgt["pos"]
	# 1) 蓄力 ~0.5s: 熔岩身上聚火光
	var glow := Sprite3D.new()
	glow.texture = _make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false; glow.transparent = true
	glow.pixel_size = 0.012
	glow.modulate = Color(1.0, 0.5, 0.15, 0.0)
	glow.scale = Vector3(0.5, 0.5, 0.5)
	glow.position = _world_pos(u["pos"], 0.4)
	_world.add_child(glow)
	var cg := _reg_tween()
	cg.tween_property(glow, "modulate:a", 0.9, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.6, 1.6, 1.6), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge := _reg_tween(); charge.tween_interval(0.5)
	await charge.finished
	# 目标可能中途死亡 → 在原落点继续演出/给盾, 不强求命中
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	# 2) 目标脚下岩浆柱拔起 (~0.22s) — AI生成熔岩柱贴图 (单帧 Sprite3D, tween 演出)
	var pillar_tex: Texture2D = _sheet("res://assets/sprites/vfx/fx_lava_pillar.png")
	var pillar := Sprite3D.new()
	pillar.texture = pillar_tex
	pillar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pillar.shaded = false; pillar.transparent = true
	pillar.modulate = Color(1.0, 1.0, 1.0, 0.0)
	# 让柱约 180px 高 (按贴图实际高度归一)
	var pillar_h: float = float(pillar_tex.get_height()) if pillar_tex != null else 768.0
	pillar.pixel_size = (180.0 * WS) / pillar_h
	pillar.scale = Vector3(0.3, 0.3, 0.3)
	pillar.position = _world_pos(center, 0.05)            # 起步低位 (略埋地)
	_world.add_child(pillar)
	var pt := _reg_tween()
	pt.set_parallel(true)                                  # 升起 + 放大 + 渐显
	pt.tween_property(pillar, "scale", Vector3(1.0, 1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.tween_property(pillar, "position", _world_pos(center, 0.9), 0.22)
	pt.tween_property(pillar, "modulate:a", 1.0, 0.22)
	pt.chain().tween_interval(0.18)                        # 停顿
	pt.chain().tween_property(pillar, "modulate:a", 0.0, 0.18)
	pt.chain().tween_callback(pillar.queue_free)
	# 3) 击飞 目标 + 120px 内敌, 给目标伤害, 给自身护盾
	_shake(JUICE_SHAKE_BIG); _add_hitstop(JUICE_HITSTOP_KNOCK)
	_skill_ring(center, Color(1.0, 0.5, 0.18, 0.7), 120.0)
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(center) > 120.0: continue
		_knock_up(o, center, 9.0)
	if tgt != null and tgt.get("alive", false):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.5, tgt, true), Color("#ff9d5c"))
	_grant_shield(u, u["atk"] * 0.8)
	u["_slam"] = false

func _lava_flame_strike(u: Dictionary, tgt: Dictionary) -> void: # 火山·重击: 蓄力猛砸击飞 1.3ATK+8%自身maxHP物理 + 20%吸血
	if tgt == null or not tgt.get("alive", false):
		return
	u["_slam"] = true
	_anticipate(u)
	var dir: Vector2 = (tgt["pos"] - u["pos"])
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	# 1) 蓄力 ~0.5s: 身上聚火光
	var glow := Sprite3D.new()
	glow.texture = _make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false; glow.transparent = true
	glow.pixel_size = 0.013
	glow.modulate = Color(1.0, 0.45, 0.12, 0.0)
	glow.scale = Vector3(0.5, 0.5, 0.5)
	glow.position = _world_pos(u["pos"], 0.4)
	_world.add_child(glow)
	var cg := _reg_tween()
	cg.tween_property(glow, "modulate:a", 0.92, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.8, 1.8, 1.8), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge := _reg_tween(); charge.tween_interval(0.5)
	await charge.finished
	# 2) 猛砸: 击飞目标 + 震屏顿帧 + (已正确的)伤害
	_shake(JUICE_SHAKE_BIG); _add_hitstop(JUICE_HITSTOP_KNOCK)
	if tgt != null and tgt.get("alive", false):
		_flash(u, Color(1.6, 0.7, 0.3))
		_skill_ring(tgt["pos"], Color(1.0, 0.4, 0.1, 0.7), 90.0)
		_impact_particles(tgt["pos"], 0.0)
		_lava_burst_vfx(tgt["pos"])                  # AI生成爆裂火球
		_knock_up(tgt, tgt["pos"] - dir * 10.0, 9.0)
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt) + int(u["maxHp"] * 0.08), Color("#ff7a33"), 0.20)
	u["_slam"] = false


# 熔岩之心·变身火山龟: 全属性提升(数据驱动 passive transform*) + 持续N秒 + 变身瞬间全体爆发灼烧吸血. 怒气清空.
func _lava_transform(u: Dictionary) -> void:
	if u.get("volcano", false):
		return
	var p: Dictionary = u.get("passive", {}) if u.get("passive", null) is Dictionary else {}
	var dur: float = float(p.get("transformDuration", 15))
	var hp_scale: float = float(p.get("transformHpScale", 2.5))
	var atk_scale: float = float(p.get("transformAtkScale", 0.2))
	var def_scale: float = float(p.get("transformDefScale", 0.2))
	var mr_scale: float = float(p.get("transformMrScale", 0.2))
	var base_atk: float = float(u["base_atk"])                    # 加成基准=攻击力(变身前)
	u["rage"] = 0.0
	u["volcano"] = true
	u["volcano_until"] = _t + dur
	u["melee"] = true; u["atk_range"] = 70.0; u["move_spd"] = 175.0   # 火山形态=近战冲脸
	# 属性提升 (1:1 pets.json: +ATK*2.5 最大HP / +ATK*0.2 攻防魔抗 flat); 用 buff(到期自动撤) + 直接加血上限(到期revert)
	_buff(u, "atk", base_atk * atk_scale, false, dur)
	_buff(u, "def", base_atk * def_scale, false, dur)
	_buff(u, "mr",  base_atk * mr_scale,  false, dur)
	var hp_gain: float = base_atk * hp_scale
	u["_volcano_hp_gain"] = hp_gain
	u["maxHp"] += hp_gain; u["hp"] += hp_gain
	# 变身演出: 加里奥R式 跃升 → 敌最密处大圈预警 → 砸地击飞范围内全部敌 + 入场爆发AOE (异步)
	_lava_volcano_slam(u)

func _lava_revert(u: Dictionary) -> void:                        # 火山形态结束 → 变回小形态 (撤回血上限, 属性buff自然到期)
	u["volcano"] = false
	u["melee"] = false; u["atk_range"] = 400.0; u["move_spd"] = 145.0   # 变回远程 (STATS lava range=400)
	var hp_gain: float = float(u.get("_volcano_hp_gain", 0.0))
	if hp_gain > 0.0:
		u["maxHp"] = maxf(1.0, u["maxHp"] - hp_gain)
		u["hp"] = minf(u["hp"], u["maxHp"])
	u["_volcano_hp_gain"] = 0.0

func _lava_ult_revert(u: Dictionary) -> void:                   # 火山暴走5秒结束→撤回+20%maxHp
	if not u.get("alive", false): return
	var g: float = float(u.get("_lava_ult_hp", 0.0))
	if g <= 0.0: return
	u["maxHp"] = maxf(1.0, u["maxHp"] - g)
	u["hp"] = minf(u["hp"], u["maxHp"])
	u["_lava_ult_hp"] = 0.0

func _sk_lava_erupt(u: Dictionary, tgt) -> void:                # 熔岩龟·技三(用户设计): 火山形态=暴走(+20%maxHp5s+30%攻速+30%移速) / 普通形态=智能冲刺(保命撤/追击贴)+下发普攻穿透
	if u.get("volcano", false):
		var gain: float = u["maxHp"] * 0.20
		u["_lava_ult_hp"] = float(u.get("_lava_ult_hp", 0.0)) + gain
		u["maxHp"] += gain; u["hp"] += gain
		u["haste_mult"] = 1.3; u["haste_until"] = _t + 5.0        # +30%攻速
		u["spd_move_mult"] = 1.3; u["spd_dbf_until"] = _t + 5.0   # +30%移速
		var tw := _reg_tween()
		tw.tween_interval(5.0)
		tw.tween_callback(_lava_ult_revert.bind(u))
		_skill_ring(u["pos"], Color(1.0, 0.4, 0.1, 0.6), 62.0); _flash(u, Color(1.6, 0.9, 0.4))
		return
	var danger: bool = u["hp"] < u["maxHp"] * 0.35
	if not danger:
		for e in _enemies_of(u):
			if e.get("alive", false) and e.get("melee", false) and (e["pos"] - u["pos"]).length() < 110.0:
				danger = true; break
	if danger:                                                   # 保命: 背离最近威胁撤220码
		var threat = _nearest_enemy(u)
		var d: Vector2 = ((u["pos"] - threat["pos"]).normalized() if threat != null else Vector2.RIGHT)
		if d.length() < 0.1: d = Vector2.RIGHT
		u["pos"] += d * 220.0
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
	elif tgt != null and tgt.get("alive", false):               # 追击: 冲贴目标
		_dash_to(u, tgt, 80.0)
	u["atk_cd"] = 0.0                                            # 重置下次普攻(立刻可放)
	u["lava_pierce_next"] = true                                # 下一发熔岩弹变穿透
	_skill_ring(u["pos"], Color(1.0, 0.45, 0.15, 0.6), 54.0); _flash(u, Color(1.6, 0.9, 0.4))

func _lava_pierce_bolt(u: Dictionary, tgt) -> void:             # 熔岩·穿透普攻: 贯穿全场岩浆光矢+沿途0.6A【魔法】+4%目标maxHp+0.07A灼烧层 (★旧注释写"真伤"与代码不符, 2026-07-10订正)
	var dir: Vector2 = ((tgt["pos"] - u["pos"]).normalized() if (tgt != null) else Vector2.RIGHT)
	if dir.length() < 0.1: dir = Vector2.RIGHT
	_bolt_line(u["pos"], u["pos"] + dir * 2000.0, Color(1.0, 0.5, 0.2, 0.95))
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if o == tgt or _on_line(u["pos"], dir, o["pos"], 70.0):
			_apply_damage_from(u, o, _atk_dmg(u, 0.6, o, true) + int(o["maxHp"] * 0.04), Color("#ff7a3c"))
			_apply_dot_stacks(o, "burn", maxi(1, int(round(float(u["atk"]) * 0.07))), u)

func _densest_enemy_point(u: Dictionary, radius: float) -> Vector2:   # 敌最密集处(邻居最多的敌位置)
	var es: Array = []
	for e in _enemies_of(u):
		if e.get("alive", false): es.append(e)
	if es.is_empty(): return u["pos"]
	var best: Vector2 = es[0]["pos"]
	var best_n: int = -1
	for e in es:
		var n: int = 0
		for o in es:
			if (o["pos"] - e["pos"]).length() <= radius: n += 1
		if n > best_n: best_n = n; best = e["pos"]
	return best

func _lava_slam_telegraph(pos2d: Vector2, radius: float, dur: float) -> void:   # 落点大圈预警(滞空可见, 临砸最亮)
	var disc := Sprite3D.new()
	disc.texture = _make_blob_texture()
	disc.billboard = BaseMaterial3D.BILLBOARD_DISABLED; disc.axis = Vector3.AXIS_Y
	disc.shaded = false; disc.transparent = true
	disc.modulate = Color(1.0, 0.18, 0.06, 0.0)
	disc.pixel_size = (radius * 2.0 * WS) / 128.0
	disc.position = _world_pos(pos2d, 0.03)
	_world.add_child(disc)
	var ring := Sprite3D.new()
	ring.texture = _make_ring_texture(Color(1.0, 0.3, 0.12, 1.0))
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ring.axis = Vector3.AXIS_Y
	ring.shaded = false; ring.transparent = true
	ring.modulate = Color(1.0, 0.35, 0.14, 0.0)
	ring.pixel_size = (radius * 2.0 * WS) / 96.0
	ring.position = _world_pos(pos2d, 0.045)
	_world.add_child(ring)
	var td := _reg_tween()
	td.tween_property(ring, "modulate:a", 0.75, 0.15)
	td.parallel().tween_property(disc, "modulate:a", 0.3, 0.15)
	td.tween_interval(maxf(0.1, dur - 0.4))
	td.tween_property(ring, "modulate:a", 1.0, 0.13)
	td.parallel().tween_property(disc, "modulate:a", 0.5, 0.13)
	td.tween_callback(ring.queue_free)
	td.parallel().tween_callback(disc.queue_free)

func _lava_charge_vfx(u: Dictionary) -> void:   # 滞空蓄力: 火山龟身上聚火光 (越蓄越盛, 临砸最亮)
	var g := Sprite3D.new()
	g.texture = _make_fire_glow_tex()
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.pixel_size = 0.015
	g.modulate = Color(1.0, 0.5, 0.15, 0.0)
	g.scale = Vector3(0.5, 0.5, 0.5)
	g.position = _world_pos(u["pos"], LAVA_LEAP_H + 0.3)
	_world.add_child(g)
	var t := _reg_tween()
	t.tween_property(g, "modulate:a", 0.92, LAVA_CHARGE_T * 0.8).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(g, "scale", Vector3(1.9, 1.9, 1.9), LAVA_CHARGE_T)
	t.tween_property(g, "modulate:a", 0.0, LAVA_SLAM_T + 0.05)
	t.tween_callback(g.queue_free)

func _lava_volcano_slam(u: Dictionary) -> void:   # 加里奥R式: 高跃升+飞落点 → 滞空蓄力(预警) → 砸地击飞+爆发
	u["_slam"] = true
	var start: Vector2 = u["pos"]
	var target: Vector2 = _densest_enemy_point(u, LAVA_SLAM_RADIUS)
	_anticipate(u); _shake(JUICE_SHAKE_HEAVY)
	_lava_slam_telegraph(target, LAVA_SLAM_RADIUS, LAVA_LEAP_UP_T + LAVA_CHARGE_T + LAVA_SLAM_T)
	# 1) 高跃升 + 同时飞向落点
	var up := _reg_tween(); up.set_parallel(true)
	up.tween_method(func(h): u["height"] = h, 0.0, LAVA_LEAP_H, LAVA_LEAP_UP_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_method(func(p): u["pos"] = p, start, target, LAVA_LEAP_UP_T).set_trans(Tween.TRANS_SINE)
	await up.finished
	# 2) 滞空蓄力 (悬停高处, 火光渐聚, 不直接砸)
	_lava_charge_vfx(u)
	var hover := _reg_tween()
	hover.tween_interval(LAVA_CHARGE_T)
	await hover.finished
	# 3) 砸地
	var down := _reg_tween()
	down.tween_method(func(h): u["height"] = h, LAVA_LEAP_H, 0.0, LAVA_SLAM_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await down.finished
	u["pos"] = target; u["height"] = 0.0
	_lava_slam_impact(u, target)
	u["_slam"] = false

# 爆裂火球: AI生成熔岩爆发贴图 (单帧 Sprite3D, scale 0.4→1.5 + alpha 1→0 绽放). 接地火球冲击
func _lava_burst_vfx(pos2d: Vector2) -> void:
	var burst_tex: Texture2D = _sheet("res://assets/sprites/vfx/fx_lava_burst.png")
	var burst := Sprite3D.new()
	burst.texture = burst_tex
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	burst.shaded = false; burst.transparent = true
	burst.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var burst_h: float = float(burst_tex.get_height()) if burst_tex != null else 768.0
	burst.pixel_size = (200.0 * WS) / burst_h        # 约 200px 直径基准 (scale 缩放)
	burst.scale = Vector3(0.4, 0.4, 0.4)
	burst.position = _world_pos(pos2d, 0.7)
	_world.add_child(burst)
	var bt := _reg_tween()
	bt.set_parallel(true)
	bt.tween_property(burst, "scale", Vector3(1.5, 1.5, 1.5), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(burst, "modulate:a", 0.0, 0.4)
	bt.chain().tween_callback(burst.queue_free)

func _lava_slam_impact(u: Dictionary, center: Vector2) -> void:   # 落地: 击飞范围内全部敌 + 入场爆发AOE
	_shake(JUICE_SHAKE_BIG); _add_hitstop(JUICE_HITSTOP_KNOCK)
	_skill_ring(center, Color(1.0, 0.4, 0.1, 0.7), LAVA_SLAM_RADIUS)
	_skill_ring(center, Color(1.0, 0.72, 0.32, 0.7), LAVA_SLAM_RADIUS * 0.6)
	_flash(u, Color(1.6, 0.7, 0.3))
	_impact_particles(center, 0.0)
	_lava_burst_vfx(center)                           # AI生成爆裂火球
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		if (o["pos"] - center).length() > LAVA_SLAM_RADIUS: continue
		if not o.get("airborne", false):
			var dir: Vector2 = (o["pos"] - center)
			dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
			o["airborne"] = true
			o["vy"] = LAVA_SLAM_KNOCK_VY
			o["vx"] = dir.x * KNOCK_PUSH * 0.7
			o["vz"] = dir.y * KNOCK_PUSH * 0.7
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o, true), Color("#ff7a33"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
		_heal(u, (o["maxHp"] - o["hp"]) * 0.08)

func _sk_cyber_cannon(u: Dictionary, tgt) -> void:              # 赛博龟·能量大炮(用户#15: 对一条直线蓄力后发长激光能量射线·线上敌各1A物理+0.1A×浮游炮数真伤·炮越多越猛)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var drones: int = u["summons"].size()
	var uu := u
	var fire := func() -> void:                                 # 蓄力后·直线长激光能量射线(用户#15·非贴身跃击)
		if not uu.get("alive", false): return
		for o in _enemies_of(uu):
			if not o.get("alive", false): continue
			if not _on_line(uu["pos"], dir, o["pos"], 70.0): continue    # 直线判定带宽±70码
			if o["pos"].distance_to(uu["pos"]) > 900.0: continue
			_apply_damage_from(uu, o, _atk_dmg(uu, 1.0, o), Color("#9bf0ff"))                          # 1A物理
			if drones > 0:
				_apply_damage_from(uu, o, int(uu["atk"] * 0.1 * drones), Color("#d0ffff"), 0.0, true)  # 0.1A×浮游炮数真伤
		_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], uu["pos"] + dir * 900.0, 126.0, Color(0.6, 0.94, 1.0, 0.9), 0.5)   # 能量大炮长激光(用户07-07"对一条直线蓄力后发出长的激光似的能量射线")
		_skill_ring(uu["pos"] + dir * 200.0, Color(0.6, 0.94, 1.0, 0.5), 46.0)
	_muzzle_flash(u["pos"], dir, Color("#9bf0ff"))             # 蓄力枪口闪
	_pending_shots.append({"delay": 0.25, "fn": fire, "src": u})   # 蓄力0.25s→发射直线长激光

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御(封板·100龟能): 缩壳20%maxHp盾(4秒)+护甲+20%(5秒)·到期剩余盾20%转生命
	_grant_shield(u, u["maxHp"] * 0.20, 4.0)
	_buff(u, "def", 0.2, true, 5.0)
	var uu: Dictionary = u
	_pending_shots.append({"delay": 3.95, "fn": func(): _heal(uu, float(uu.get("shield", 0.0)) * 0.20), "src": u})   # 到期前读剩余盾×20%转生命

func _hiding_minion_of(u: Dictionary):                          # 取该缩头龟的存活随从(A方案完整龟)
	var result = null
	for o in _units:
		if o.get("is_summon", false) and o.get("summon_owner", null) == u and o.get("minion_kind", null) != null and o.get("alive", false):
			result = o
			break
	return result

func _hiding_apply_buff(o: Dictionary, dur: float) -> void:     # 强化随从增益(dur秒·dur<=0=永久·供随从死亡继承给主人): 攻/甲/抗+10%·吸血+10%·暴击+20%
	var d: float = dur if dur > 0.0 else 9999.0
	_buff(o, "atk", 0.10, true, d)
	_buff(o, "def", 0.10, true, d)
	_buff(o, "mr", 0.10, true, d)
	_buff(o, "lifesteal", 0.10, false, d)
	o["crit"] = float(o.get("crit", 0.0)) + 0.20
	if dur > 0.0:
		var oo: Dictionary = o
		_pending_shots.append({"delay": dur, "fn": func(): oo["crit"] = float(oo.get("crit", 0.0)) - 0.20, "src": o})
	_skill_ring(o["pos"], Color(0.9, 0.7, 0.3, 0.5), 44.0)

func _sk_hiding_shrink(u: Dictionary) -> void:                  # 缩头(封板·100龟能): 立即给随从+50%技能龟能 + 自身缩头3秒(80%减伤·不能攻击/移动·★龟能条锁定=设stun_until→_tick_skill_cd遇stun直接return不充能·对用户#1"且锁龟能条")
	var m = _hiding_minion_of(u)
	if m != null:
		var cost: float = 95.0
		var acts: Array = m.get("active_skills", [])
		if not acts.is_empty(): cost = SkillEnergy.cost_of(str(acts[0]))
		m["energy"] = float(m.get("energy", 0.0)) + cost * 0.5   # 给随从+50%技能龟能(加速放技)
		_skill_ring(m["pos"], Color(0.6, 0.9, 1.0, 0.5), 44.0)
	u["stun_until"] = maxf(float(u.get("stun_until", 0.0)), _t + 3.0)   # 缩头3秒: 不能攻击/移动(定身)
	u["damage_reduction"] = 0.80                                # 80%减伤
	var uu: Dictionary = u
	_pending_shots.append({"delay": 3.0, "fn": func(): uu["damage_reduction"] = 0.0, "src": u})
	_skill_ring(u["pos"], Color(0.55, 0.5, 0.4, 0.6), 50.0)

func _sk_hiding_buff(u: Dictionary) -> void:                    # 强化随从(封板·80龟能): 随从注入力量5秒(攻/甲/抗+10%·吸血+10%·暴击+20%)
	var m = _hiding_minion_of(u)
	if m != null: _hiding_apply_buff(m, 5.0)

func _hiding_shell_harden(u: Dictionary) -> void:              # 缩壳(普攻rider): 每次普攻+1护甲+1魔抗(永久累积)+0.1A护盾
	u["base_def"] = float(u["base_def"]) + 1.0
	u["base_mr"] = float(u["base_mr"]) + 1.0
	_recalc_stats(u)
	_grant_shield(u, u["atk"] * 0.1)

func _sk_shell_absorb(u: Dictionary, tgt) -> void:              # 龟壳·吸收(封板): 偷目标10%最大生命→转移(目标maxHp&当前同步减·龟壳maxHp&当前同步增)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var steal: float = tgt["maxHp"] * 0.10
	tgt["maxHp"] = maxf(1.0, float(tgt["maxHp"]) - steal)
	tgt["hp"] = minf(float(tgt["hp"]), float(tgt["maxHp"]))     # 目标maxHp+当前同步减
	u["maxHp"] = float(u["maxHp"]) + steal
	u["hp"] = float(u["hp"]) + steal                            # 龟壳maxHp+当前同步增
	_float_text(tgt["pos"] + Vector2(0, -40), "吸收!", Color("#cfd8e8"))
	_float_text(u["pos"] + Vector2(0, -52), "+%d" % int(steal), Color("#7fe3a0"))

func _shell_enter_stealth(u: Dictionary) -> void:              # 潜影: 进入隐身(不可被选+半透明); 只有龟壳自己放技能/普攻破隐(AOE不破)
	if u.get("shell_stealth", false): return
	u["shell_stealth"] = true
	u["untargetable_until"] = _t + 999.0
	var spr = u.get("sprite", null)
	if is_instance_valid(spr): spr.modulate.a = 0.4
	_skill_ring(u["pos"], Color(0.4, 0.2, 0.55, 0.5), 46.0)

func _shell_break_stealth(u: Dictionary) -> void:              # 破隐(自己放技能/普攻触发): 清隐身 + 标记破隐首发普攻bonus
	if not u.get("shell_stealth", false): return
	u["shell_stealth"] = false
	u["untargetable_until"] = 0.0
	u["shell_stealth_broke"] = true                            # 破隐后第一发普攻附加(在_shell_basic消费)
	var spr = u.get("sprite", null)
	if is_instance_valid(spr): spr.modulate.a = 1.0

func _sk_shell_shadow_dive(u: Dictionary, tgt) -> void:        # 龟壳·暗影俯冲(封板·130龟能·Corki库奇式): 俯冲600码→落地2.5A魔法+击退+路径敌→暗影燃烧区150码5s(每0.5s 0.1A灼烧层+减速20%)→进入隐身
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var start: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - start
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var dest: Vector2 = start + dir * 600.0
	dest.x = clampf(dest.x, ARENA.position.x, ARENA.end.x)
	dest.y = clampf(dest.y, ARENA.position.y, ARENA.end.y)
	for o in _enemies_of(u):                                    # 落地+路径敌: 2.5A魔法+击退
		if not o.get("alive", false): continue
		if not _on_line(start, dir, o["pos"], 75.0): continue
		if o["pos"].distance_to(start) > 620.0: continue
		_apply_damage_from(u, o, _atk_dmg(u, 2.5, o, true), Color("#9b3bff"))
		_knockback(u, o, 60.0, 1.0, 1.4)
	u["pos"] = dest
	var zc: Vector2 = dest
	for i in range(10):                                         # 暗影燃烧区150码·5秒·每0.5秒结算
		var fn := func():
			for o in _enemies_of(u):
				if o.get("alive", false) and o["pos"].distance_to(zc) <= 150.0:
					_apply_dot_stacks(o, "burn", maxi(1, int(round(u["atk"] * 0.1))), u)   # 0.1A灼烧层
					o["spd_move_mult"] = 0.8
					o["spd_dbf_until"] = _t + 0.5              # 减速20%(0.5s)
			_skill_ring(zc, Color(0.5, 0.15, 0.6, 0.4), 150.0)
		_pending_shots.append({"delay": float(i) * 0.5, "fn": fn, "src": u})
	_beam_vfx("res://assets/sprites/vfx/fx-trail.png", start, dest, 60.0, Color(0.62, 0.22, 0.72, 0.7), 0.34)   # 暗影猛扑拖影(用户07-08"俯冲参考lol库奇旧版W")
	_shell_enter_stealth(u)                                     # 俯冲后进入隐身

func _sk_burst(u: Dictionary, tgt: Dictionary) -> void:          # 兜底重击
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt), Color("#ff9d5c"))
	for o in _enemies_of(u):
		if o != tgt and (o["pos"] - tgt["pos"]).length() <= 110.0:
			_apply_damage_from(u, o, _atk_dmg(u, 1.25, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"], Color(1.0, 0.6, 0.3, 0.5), 110.0)

# ── 选3 多技能: 数据驱动伤害技 + 通用盾/治 (系数取自 pets.json detail 公式) ──
# opts: {phys,magic,true: ×casterATK 的 物理/魔法/真实系数; hp,mr: ×caster maxHp/MR 附加;
#        hits: 视觉段数(伤害总量不变); aoe: 全体敌; rider: 附带(burn/stun/slow/curse/atkdn/mrdn); name,color}
# 忍者·炸弹 (AOE·1:1 回合制 ninjaBomb): 抛掷点燃引信的炸弹到敌群质心→落地爆炸→全体敌方 1.1×ATK 物理 + -25%护甲(5秒)
#   机制沿用 _sk_dmg(在爆炸落地时结算·数值/减益完全不变), 仅把原来的"灰环占位"换成真·炸弹抛掷+爆炸帧动画(ninja-bomb.png 12帧)
func _sk_ninja_bomb(u: Dictionary, tgt) -> void:
	var opts := {"phys": 1.1, "hits": 1, "aoe": true, "defDown": 0.25, "color": Color("#ff9a3c")}
	var es: Array = _enemies_of(u)
	if es.is_empty():
		return
	var center := Vector2.ZERO
	for e in es:
		center += e["pos"]
	center /= float(es.size())               # 落点 = 敌群质心 (AOE·炸弹落敌群中间; 伤害仍打全体不受落点限制)
	_anticipate(u)                            # 短蓄力(掏炸弹)
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/sprites/vfx/ninja-bomb.png")
	spr.hframes = 12                          # 768×64 = 12帧(圆炸弹0-4→引信5-6→streak7→爆闪8→火球9→烟10-11)
	spr.frame = 6                             # 点燃引信的炸弹
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (46.0 * WS) / 64.0
	spr.position = _world_pos(u["pos"], 1.15)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_method(_bomb_arc.bind(spr, u["pos"], center), 0.0, 1.0, 0.42)   # 抛物线飞向敌群
	tw.tween_callback(_bomb_explode.bind(spr, u, center, opts))

func _bomb_arc(pf: float, spr: Sprite3D, from2d: Vector2, to2d: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = _world_pos(from2d.lerp(to2d, pf), 1.1 + sin(pf * PI) * 2.6)   # 拱起飞行
		spr.frame = 6 + (int(_t * 14.0) % 2)   # 引信闪烁(6/7帧)

func _bomb_boom_frame(fv: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		spr.frame = clampi(int(fv), 8, 11)     # 爆炸→火球→烟(8→11)

func _bomb_explode(spr: Sprite3D, u: Dictionary, at2d: Vector2, opts: Dictionary) -> void:
	if is_instance_valid(spr):
		spr.frame = 8
		spr.position = _world_pos(at2d, 0.75)
		spr.pixel_size = (88.0 * WS) / 64.0    # 爆炸放大
		var et := _reg_tween()
		et.tween_method(_bomb_boom_frame.bind(spr), 8.0, 11.99, 0.5)
		et.tween_callback(spr.queue_free)
	_shake(0.12)
	_skill_ring(at2d, Color(1.0, 0.5, 0.15, 0.7), 74.0)   # 落点爆炸火环
	_sk_dmg(u, null, opts)                     # 落地结算: 全体敌 1.1A物理 + -25%护甲5s (数值/减益同原实现·不变)

func _sk_dmg(u: Dictionary, tgt, opts: Dictionary) -> void:
	var col: Color = opts.get("color", Color("#ffd07a"))
	var aoe: bool = opts.get("aoe", false)
	var random_aoe: bool = opts.get("randomAoe", false)            # 每段随机1敌(雷暴式)
	var stagger: float = float(opts.get("stagger", 0.0))          # >0=逐段错峰(秒), 不糊
	var cap: int = 24 if stagger > 0.0 else 8
	var vh: int = clampi(int(opts.get("hits", 1)), 1, cap)
	# 段前一次性: 减益(破盾/各down/治疗削减) + rider + 贴地环
	var deb_targets: Array = _enemies_of(u) if (aoe or random_aoe) else ([tgt] if tgt != null else [])
	for e in deb_targets:
		if e == null or not e.get("alive", false):
			continue
		_apply_skill_extras(u, e, opts)
		_apply_rider(u, e, str(opts.get("rider", "")))
		_skill_ring(e["pos"], Color(col.r, col.g, col.b, 0.4), 46.0)
	if float(opts.get("selfDodge", 0.0)) > 0.0:   # 技能给施法者闪避buff(如ghost幽冥突袭25%)
		_buff(u, "dodge", float(opts["selfDodge"]), true, float(opts.get("selfDodgeDur", BUFF_SEC)))
	var fixed: Array = _enemies_of(u) if aoe else ([tgt] if tgt != null else [])
	if stagger > 0.0:
		var tw := _reg_tween()
		for i in range(vh):
			tw.tween_callback(_sk_dmg_wave.bind(u, opts, vh, col, random_aoe, fixed))
			tw.tween_interval(stagger)
	else:
		for i in range(vh):
			_sk_dmg_wave(u, opts, vh, col, random_aoe, fixed)

# 一段伤害(供 _sk_dmg 即时/错峰共用): random_aoe→1随机敌, 否则打 fixed 列表
func _sk_dmg_wave(u: Dictionary, opts: Dictionary, vh: int, col: Color, random_aoe: bool, fixed: Array) -> void:
	var ws: Array
	if random_aoe:
		var es := _enemies_of(u)
		if es.is_empty():
			return
		ws = [es[_juice_rng.randi() % es.size()]]
	else:
		ws = fixed
	var phys: float = float(opts.get("phys", 0.0))
	var magic: float = float(opts.get("magic", 0.0))
	var tru: float = float(opts.get("true", 0.0))
	var hp_flat: float = float(opts.get("hp", 0.0)) * u["maxHp"]
	var mr_flat: float = float(opts.get("mr", 0.0)) * u["mr"]
	var elec: int = int(opts.get("electric", 0))
	var ls: float = float(opts.get("lifesteal", 0.0))   # 技能吸血(如ghost幽冥突袭80%)
	for e in ws:
		if e == null or not e.get("alive", false):
			continue
		var dmg := 0
		if phys > 0.0:
			dmg += _atk_dmg(u, phys / vh, e, false)
		if magic > 0.0:
			dmg += _atk_dmg(u, magic / vh, e, true)
		dmg += int((hp_flat + mr_flat) / vh)
		if dmg > 0:
			_apply_damage_from(u, e, dmg, col, ls)
			var spl: float = float(opts.get("splash", 0.0))   # 溅射到次要目标(闪电打击25%)
			if spl > 0.0:
				for o in _enemies_of(u):
					if o != e and o.get("alive", false):
						_apply_damage_from(u, o, int(dmg * spl), col)
						break
		if tru > 0.0:
			_apply_damage_from(u, e, int(u["atk"] * tru / vh), col, 0.0, true)
		if elec > 0:
			_add_stack(e, "electric", elec, 8)

# 技能附带减益(数据化 opts): 破盾%/攻防魔抗down%/治疗削减%
func _apply_skill_extras(u: Dictionary, e: Dictionary, opts: Dictionary) -> void:
	var sb: float = float(opts.get("shieldBreak", 0.0))
	if sb > 0.0 and float(e.get("shield", 0.0)) > 0.0:
		e["shield"] = float(e["shield"]) * (1.0 - sb)
	var ad: float = float(opts.get("atkDown", 0.0))
	if ad > 0.0:
		_buff(e, "atk", -ad, true)
	var dd: float = float(opts.get("defDown", 0.0))
	if dd > 0.0:
		_buff(e, "def", -dd, true)
	var md: float = float(opts.get("mrDown", 0.0))
	if md > 0.0:
		_buff(e, "mr", -md, true)
	var hc: float = float(opts.get("healCut", 0.0))
	if hc > 0.0:
		e["heal_reduce_until"] = _t + float(opts.get("healCutDur", BUFF_SEC))
		e["heal_reduce_pct"] = maxf(float(e.get("heal_reduce_pct", 0.0)), hc)

func _apply_rider(u: Dictionary, e: Dictionary, rider: String) -> void:
	if rider == "" or e == null or not e.get("alive", false):
		return
	match rider:
		"burn":  _apply_dot_stacks(e, "burn", maxi(1, roundi(u["atk"] * 0.5)), u)
		"stun":  e["stun_until"] = maxf(float(e.get("stun_until", 0.0)), _t + _cc_dur(e, CTRL_SEC))
		"slow":  e["slow_until"] = maxf(float(e.get("slow_until", 0.0)), _t + _cc_dur(e, BUFF_SEC)); e["slow_mag"] = 0.6
		"curse": _add_dot(e, "curse", e["maxHp"] * 0.05, BUFF_SEC)
		"atkdn": _buff(e, "atk", -0.15, true)
		"mrdn":  _buff(e, "mr", -0.20, true)

# 通用护盾 (stone/rainbow/candy 的 shield 技): 全队上盾
# 当前技能数据条目 (按 type 在该龟 skillPool 找; 数据驱动读 fx/name/energyCost)
func _cur_skill_data(u: Dictionary, stype: String) -> Dictionary:
	var d: Dictionary = _data_by_id.get(str(u["id"]), {})
	for sk in d.get("skillPool", []):
		if str(sk.get("type", "")) == stype:
			return sk
	return {}

# 数据驱动护盾: 每龟读自己 fx (shieldAtk/shieldHp/healHp) + 技能名 (不再跑通用硬编码)
func _sk_gen_shield(u: Dictionary) -> void:
	var sk := _cur_skill_data(u, "shield")
	var fx: Dictionary = sk.get("fx", {})
	var sa := float(fx.get("shieldAtk", 0.3))
	var sh := float(fx.get("shieldHp", 0.0))
	var heal_hp := float(fx.get("healHp", 0.0))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * sa + o["maxHp"] * sh)
		if heal_hp > 0.0:
			_heal(o, o["maxHp"] * heal_hp)
		_skill_ring(o["pos"], Color(0.6, 0.86, 1.0, 0.45), 46.0)   # 护盾贴地环 (替代飘空图标)

# ── Batch2 特殊技 (bespoke; 按 pets.json brief/detail 实装) ──

# 财神·梭哈: 一场限一次, 消耗全部金币, 每枚 0.18×ATK物理 + 0.18×ATK真实 (cd999)
func _sk_fortune_allin(u: Dictionary, tgt) -> void:                 # 财神龟·梭哈 ✅ (蓄力→持续投金币, 目标死换下个)
	if tgt == null or u.get("allin_used", false):
		return
	u["allin_used"] = true
	var coins: int = int(u["gold"])
	u["gold"] = 0.0
	if coins <= 0:
		return
	u["allin_coins"] = coins              # 待投金币数 = 全部金币
	u["allin_throw_t"] = 0.6              # 蓄力(首投前)
	u["allin_target"] = tgt
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.65), 66.0)   # 蓄力金环
	_flash(u, Color(1.5, 1.3, 0.6))

# 梭哈 channel: 蓄力后每隔投币间隔朝目标投1金币(0.18ATK物+0.18ATK真), 目标死换最近敌; 投完结束; 眩晕/击飞期暂停
func _fortune_allin_channel(u: Dictionary, delta: float) -> void:
	if _t < float(u.get("stun_until", 0.0)):
		return
	u["allin_throw_t"] = float(u.get("allin_throw_t", 0.0)) - delta
	if u["allin_throw_t"] > 0.0:
		return
	var tgt = u.get("allin_target", null)
	if tgt == null or not tgt.get("alive", false):
		tgt = _nearest_enemy(u)
		u["allin_target"] = tgt
	if tgt == null:
		u["allin_coins"] = 0
		return
	_throw_gold_coin(u, tgt)
	u["allin_coins"] = int(u["allin_coins"]) - 1
	u["allin_throw_t"] = 0.11
	if int(u["allin_coins"]) <= 0:
		u["allin_target"] = null

# 投1枚金币弹道 (命中→0.18ATK物理+0.18ATK真实)
func _throw_gold_coin(src: Dictionary, tgt: Dictionary) -> void:
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	var tex := "res://assets/sprites/ui/coin.png"
	if ResourceLoader.exists(tex):
		p.texture = load(tex)
		p.pixel_size = 0.05
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		p.texture = _make_bolt_texture(Color(1.0, 0.84, 0.2))
		p.pixel_size = 0.014
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)
	p.position = world_from
	_world.add_child(p)
	var dur := clampf(start2d.distance_to(tgt["pos"]) / 650.0, 0.18, 0.6)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": _atk_dmg(src, 0.18, tgt, false),
		"col": Color("#ff4444"), "src": src, "t": 0.0, "dur": dur, "basic_onhit": false,
		"coin_true": int(src["atk"] * 0.18),
	})

# 星际·虫洞(用户2026-07-09重做): 短暂蓄力→发射缓慢移动虫洞沿目标方向直线→吸经过敌90码+1段1.5A×(1+5%秒)魔法(每敌一次)
func _sk_star_wormhole(u: Dictionary, tgt) -> void:                # 星际龟·虫洞(用户2026-07-09重设计): 短暂蓄力→发射1个缓慢移动的虫洞沿目标方向直线飞→吸经过敌90码(拉向虫洞)+造成1段=1.5A×(1+5%每秒)魔法(每敌一次)
	if tgt == null: tgt = _nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var start: Vector2 = u["pos"]
	var mult: float = 1.5 * (1.0 + 0.05 * _t)                       # 1段伤害=1.5A×(1+5%每秒)·发射时刻定格
	var uu := u
	_anticipate(u)                                                  # 短暂蓄力前摇
	var fire := func() -> void:                                     # 蓄力后发射缓慢移动虫洞
		if not uu.get("alive", false): return
		var hole := Sprite3D.new()                                  # 虫洞视觉(fx-vortex真旋涡·PIL程序化半透明螺旋+暗心)
		hole.texture = load("res://assets/sprites/vfx/fx-vortex.png")   # 真旋涡(PIL程序化半透明螺旋+暗心)
		hole.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hole.shaded = false; hole.transparent = true
		hole.modulate = Color(1.0, 1.0, 1.0, 0.95)   # 贴图自带紫色·不再染色
		hole.pixel_size = (240.0 * WS) / 128.0   # 旋涡直径≈240码(影响半径120)
		hole.position = _world_pos(start, 0.4)
		_world.add_child(hole)
		var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。
		var radius := 120.0                                         # 虫洞影响半径(F5可调)
		var step := func(d: float) -> void:
			var c: Vector2 = start + dir * d                        # 虫洞当前位置
			if is_instance_valid(hole): hole.position = _world_pos(c, 0.4)
			for o in _enemies_of(uu):
				if not o.get("alive", false) or hit.has(o): continue
				if o["pos"].distance_to(c) > radius: continue
				hit.append(o)
				if not o.get("_eggImmune", false):                  # 吸敌90码(拉向虫洞·不是推开)
					var pull: Vector2 = c - o["pos"]
					if pull.length() > 1.0: o["pos"] += pull.normalized() * 90.0
				_apply_damage_from(uu, o, _atk_dmg(uu, mult, o, true), Color("#c9a0ff"))   # 1段魔法
				_skill_ring(o["pos"], Color(0.75, 0.6, 1.0, 0.6), 50.0)
		var tw := _reg_tween()
		tw.tween_method(step, 0.0, 1400.0, 1.6).set_trans(Tween.TRANS_LINEAR)   # 缓慢移动~1.6s跨1400码
		tw.chain().tween_callback(hole.queue_free)
	_pending_shots.append({"delay": 0.3, "fn": fire, "src": u})     # 蓄力0.3s→发射
func _sk_line_ink_bomb(u: Dictionary) -> void:                  # 线条龟·墨水炸弹(用户设计·120龟能): 全体敌4段共1A魔法+各叠4墨迹(打包被动=墨迹上限提到10·叠满10层+50%真实受伤)
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		for i in range(4):
			_apply_damage_from(u, o, _atk_dmg(u, 0.25, o, true), Color("#c9b0ff"))
		_add_stack(o, "ink", 4, _ink_cap(u))
		_burst_vfx("res://assets/sprites/vfx/ink-splat.png", o["pos"], 110.0, 0.9)   # 每敌身上墨溅
	_burst_vfx("res://assets/sprites/vfx/ink-splat.png", u["pos"], 190.0, 0.5)   # 墨爆溅全场(中心大溅)
	_skill_ring(u["pos"], Color(0.55, 0.4, 0.75, 0.4), 200.0)   # 墨爆环(淡)

# 线条·收尾·画龙点睛: 对墨迹最多敌 (0.7+0.45×层数)×ATK物理 (用户封板L466: 不消耗墨迹)
func _sk_line_finish(u: Dictionary) -> void:
	var best = null
	var best_ink := -1
	for o in _enemies_of(u):
		var ink := int((o.get("stacks", {}) as Dictionary).get("ink", 0))
		if ink > best_ink:
			best_ink = ink
			best = o
	if best == null:
		best = _nearest_enemy(u)
		best_ink = 0
	if best == null:
		return
	var scale: float = 0.7 + 0.45 * maxi(0, best_ink)   # 基础0.7+每层墨迹0.45×ATK (恢复文本设计值, 原0.8/0.35)
	_apply_damage_from(u, best, _atk_dmg(u, scale, best), Color("#eeeeee"))
	_skill_ring(best["pos"], Color(0.9, 0.9, 0.9, 0.5), 48.0)   # 画龙点睛不消耗墨迹(用户封板L466·原_consume_stacks已删)

# 赛博·部署: 立即放3个浮游炮 (与被动「浮游炮」同型, 上限10)
func _sk_cyber_hijack(u: Dictionary) -> void:                   # 赛博龟·侵入(封板·120龟能·Botworld黑客): 黑1随机敌4秒倒戈(side改赛博方·标hijacked→打原队友+被原队友打·不算存活数·击杀归赛博·蛋免控·可黑多个)
	var es: Array = []
	for o in _enemies_of(u):
		if o.get("alive", false) and not o.get("_eggImmune", false) and not o.get("hijacked", false):
			es.append(o)
	if es.is_empty(): return
	var v: Dictionary = es[randi() % es.size()]
	v["_hijack_orig_side"] = str(v["side"])
	v["side"] = str(u["side"])                                  # 倒戈: side→赛博方(它索敌打原队友·原队友side差也打它)
	v["hijacked"] = true
	v["hijack_until"] = _t + 4.0
	v["taunt_until"] = 0.0; v["taunt_by"] = null               # 清嘲讽残留(防倒戈期错误锁定)
	v["stun_until"] = 0.0                                       # 解控(立即可倒戈行动)
	_float_text(v["pos"] + Vector2(0, -56), "侵入!", Color("#3fffd0"))
	_skill_ring(v["pos"], Color(0.25, 1.0, 0.82, 0.5), 52.0)
	_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], v["pos"], 30.0, Color(0.25, 1.0, 0.82, 0.75), 0.6)   # 侵入数据链(用户07-07仅给"参考Botworld黑客机器人"·具体视觉无原话)

func _sk_cyber_smart(u: Dictionary) -> void:                   # 赛博龟·智能AI(封板·40龟能·充能型): +1充能→冲刺重定位(kite拉到理想射程·躲贴身); 常驻走位+登场+20%移速 [完整行动脑(躲大招/对齐激光)留F5]
	u["cyber_ai_charge"] = int(u.get("cyber_ai_charge", 0)) + 1
	var ne = _nearest_enemy(u)
	if ne != null:
		var away: Vector2 = u["pos"] - ne["pos"]
		if away.length() < 1.0: away = Vector2.RIGHT
		away = away.normalized()
		var dest: Vector2 = ne["pos"] + away * 380.0            # 拉到理想输出距离(射程450内不贴脸)
		dest.x = clampf(dest.x, ARENA.position.x, ARENA.end.x)
		dest.y = clampf(dest.y, ARENA.position.y, ARENA.end.y)
		_beam_vfx("res://assets/sprites/vfx/fx-trail.png", u["pos"], dest, 44.0, Color(0.3, 0.9, 1.0, 0.6), 0.28)   # 智能AI冲刺残影(用户07-07仅给"走位躲技能"行为·视觉无原话)
		u["pos"] = dest
	_skill_ring(u["pos"], Color(0.3, 0.9, 1.0, 0.5), 46.0)

# 泡泡·束缚: 定身目标 1.5s + 束缚期间每受一段伤害 永久-X护甲/魔抗 (见 _apply_damage_from 钩子)
func _sk_bubble_bind(u: Dictionary, tgt) -> void:
	if tgt == null:
		return
	tgt["stun_until"] = maxf(float(tgt.get("stun_until", 0.0)), _t + _cc_dur(tgt, 3.0))   # 泡泡束缚定身3秒(用户设计·原CTRL_SEC=1.5)
	tgt["bind_until"] = _t + 3.0
	tgt["bind_shred"] = 1.0 if int(u.get("level", 1)) <= 5 else 2.0   # 减甲量按等级(detail: 1-5级=1/6-10级=2)
	tgt["bind_acc"] = 0.0
	_skill_ring(tgt["pos"], Color(0.5, 0.9, 1.0, 0.5), 50.0)

# 骰子·命运骰子: 随机 +40%~130% 暴击5秒; 超100%部分每1%→1.5%暴伤 (crit 单独计时还原)
func _sk_dice_fate(u: Dictionary) -> void:
	if u.get("crit_fate_until", 0.0) > _t:           # 撤销未到期旧增益, 防叠加
		u["crit"] -= u.get("crit_fate_amt", 0.0)
		u["crit_dmg"] -= u.get("crit_dmg_fate_amt", 0.0)
	var roll: float = randf_range(0.4, 1.3)
	var over: float = maxf(0.0, (u["crit"] + roll) - 1.0)   # 暴击封顶100%, 超出转暴伤
	var add_crit: float = roll - over
	var add_cd: float = over * 1.5
	u["crit"] += add_crit
	u["crit_dmg"] += add_cd
	u["crit_fate_until"] = _t + 999.0   # 持续到下次放技能(开头撤旧增益自然重掷·用户设计)
	u["crit_fate_amt"] = add_crit
	u["crit_dmg_fate_amt"] = add_cd
	_float_text(u["pos"] + Vector2(0, -64), "命运骰子! +%d%%暴击" % int(roll * 100), Color("#ffd93d"))

# 龟壳·复制: 随机复制 2 个敌方可用技立即释放 (60%效果简化为全效, 留 batch3)
# 龟壳复制期的"非伤害"效果乘数(护盾/治疗/DoT). 伤害走 src["dmg_out_mult"]. 两者都只覆盖【同步段】:
# 被复制技能里延迟触发的子效果(tween/_pending_shots)仍按全效结算 → 见 附录B-07。
var _copy_fx_mult: float = 1.0

func _sk_shell_copy(u: Dictionary, tgt) -> void:               # 龟壳·复制(封板·130龟能): 复制2敌方可用技(_COPYABLE白名单)·轮流依次释放(不同帧糊); 60%效果=伤害(dmg_out_mult)+护盾/治疗/DoT(_copy_fx_mult)
	var pool: Array = []
	for o in _enemies_of(u):
		for st in o.get("active_skills", []):
			var s := str(st)
			if _COPYABLE_SKILLS.has(s) and not pool.has(s):
				pool.append(s)
	pool.shuffle()
	if pool.size() >= 1:
		u["dmg_out_mult"] = 0.6                                # 60%效果(封板)·即时伤害经_apply_damage_from乘数
		_copy_fx_mult = 0.6                                    # 60%效果·护盾/治疗/DoT
		_do_skill(u, tgt, str(pool[0]))                        # 第1个立即
		_copy_fx_mult = 1.0
		u["dmg_out_mult"] = 1.0
	if pool.size() >= 2:                                       # 第2个错峰0.6s(轮流依次·不同时糊帧)
		var p1: String = str(pool[1])
		var uu: Dictionary = u
		var fn := func():
			uu["dmg_out_mult"] = 0.6
			_copy_fx_mult = 0.6
			_do_skill(uu, _nearest_enemy(uu), p1)
			_copy_fx_mult = 1.0
			uu["dmg_out_mult"] = 1.0
		_pending_shots.append({"delay": 0.6, "fn": fn, "src": u})

# ============================================================================
#  效果积木 (可复用) — 治疗/护盾/控制/buff/DoT/吸血/累积/净化/叠层 (1:1 搬自 2D 版).
#  注: 3D 版血条 overlay 每帧统一刷新, 故去掉 2D 版各处的 _update_bars(u) 调用.
# ============================================================================
func _grant_shield(u: Dictionary, amt: float, dur: float = 0.0) -> void:
	if amt <= 0.0: return
	amt *= _copy_fx_mult                          # 龟壳复制期: 护盾也按60%(封板"以60%效果释放")
	amt *= 1.0 + float(u.get("shield_amp", 0.0))   # 护盾加成(受到方,所有来源)
	var sb: float = u["shield"]
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)
	if dur > 0.0:
		u["shield_until"] = maxf(float(u.get("shield_until", 0.0)), _t + dur)   # 限时盾原语(封板通用护盾=4秒): 记到期(多源取更晚); dur=0=永久(不设→_tick不过期·shell/嘲讽/既有盾全默认永久不变)
	var got := int(u["shield"] - sb)
	u["_st_shield"] = int(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾
	if got >= 8:                             # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏
		_float_text(u["pos"] + Vector2(0, -52), "+%d 盾" % got, Color("#ffffff"), false, "shield")
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)
	_sfx_shield_gain()                       # §AUDIO: 得盾音 (节流; 群体上盾不刷屏)

func _egg_level_up_vfx(u: Dictionary, total_lvl: int) -> void:   # 温泉蛋升级: 金光柱升腾 + 脚下金块 + "LV UP LvN"
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.4, 0.65), 56.0)
	_float_text(u["pos"] + Vector2(0, -74), "LV UP  Lv%d" % total_lvl, Color("#ffe08a"))
	_shake(0.05)
	var glow := _make_fire_glow_tex()
	var col := Sprite3D.new()
	col.texture = glow
	col.modulate = Color(1.0, 0.86, 0.42, 0.9)
	col.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	col.shaded = false; col.transparent = true
	col.pixel_size = (50.0 * WS) / float(maxi(1, glow.get_width()))
	col.position = _world_pos(u["pos"], 0.4)
	_world.add_child(col)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(col, "position", _world_pos(u["pos"], 1.7), 0.5)
	tw.tween_property(col, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(col.queue_free)
	for k in range(5):   # 脚下金块环绕冒起
		var a: float = float(k) * TAU / 5.0
		_gold_chunk_erupt(u["pos"] + Vector2(cos(a), sin(a)) * randf_range(34.0, 50.0))

# 统领显示等级 = 基础等级 + 温泉蛋036临时孵化等级(egg_levels), 用于等级框实时跳字
func _effective_level(u: Dictionary) -> int:
	var lv: int = int(u.get("level", 1))
	var st = u.get("eq_state", {}).get("p2eq_036", {})
	return lv + int(st.get("egg_levels", 0))

func _egg_add_progress(u: Dictionary, amt: float) -> void:   # 温泉蛋(036): 累积孵化进度→每100+1临时等级(线性+5%基础+攻速2%/级,同统领,上限+3)→孵满(+3)全队均摊护盾一次
	if amt <= 0.0 or not u.get("has_egg", false) or not u.get("alive", false): return
	var stt: Dictionary = u["eq_state"].get("p2eq_036", {})
	stt["incub"] = float(stt.get("incub", 0.0)) + amt
	while float(stt["incub"]) >= 100.0 and int(stt.get("egg_levels", 0)) < 3:
		stt["incub"] = float(stt["incub"]) - 100.0
		if not stt.has("ref_atk"):   # 首次升级锁基准 → 线性+5%/级(同统领 1+0.05×级, 非复利)
			stt["ref_atk"] = u["base_atk"]; stt["ref_def"] = u["base_def"]; stt["ref_mr"] = u["base_mr"]
			stt["ref_hp"] = u["maxHp"]; stt["ref_iv"] = float(u.get("atk_interval", 1.0))
		stt["egg_levels"] = int(stt.get("egg_levels", 0)) + 1
		var el: int = int(stt["egg_levels"])
		u["base_atk"] += float(stt["ref_atk"]) * 0.05          # 线性+5%基础属性/级
		u["base_def"] += float(stt["ref_def"]) * 0.05
		u["base_mr"] += float(stt["ref_mr"]) * 0.05
		var hpg: float = float(stt["ref_hp"]) * 0.05; u["maxHp"] += hpg; u["hp"] += hpg
		u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + 0.02 * float(el)))   # 攻速+2%/级(同统领)
		_recalc_stats(u)
		_egg_level_up_vfx(u, int(u.get("level", 1)) + el)      # 升级特效(金光柱+LV UP)
		if int(stt["egg_levels"]) >= 3 and not bool(stt.get("incub_given", false)):
			stt["incub_given"] = true
			var allies := _allies_of(u)
			var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
			for o in allies: _grant_shield(o, per)
			_particle_burst(u["pos"])
	if int(stt.get("egg_levels", 0)) >= 3: stt["incub"] = minf(float(stt["incub"]), 100.0)
	u["eq_state"]["p2eq_036"] = stt

# silent=true: 吸血等高频被动回血不出治疗音 (防刷屏), 主动治疗/技能回血出音
func _heal(u: Dictionary, amt: float, silent: bool = false) -> void:
	if amt <= 0.0: return
	amt *= _copy_fx_mult                        # 龟壳复制期: 治疗也按60%
	amt *= 1.0 + float(u.get("heal_amp", 0.0))   # 治疗加成(受到方,所有来源)
	if _t < float(u.get("heal_reduce_until", 0.0)):
		amt *= maxf(0.0, 1.0 - float(u.get("heal_reduce_pct", 0.0)))   # 治疗削减(凤凰涅槃/烫伤等)
	var hb: float = u["hp"]
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	u["_st_heal"] = int(u.get("_st_heal", 0)) + int(u["hp"] - hb)   # §STATS: 实际回复(超过满血不计)
	var _osc: float = float(u.get("overheal2shield_cap", 0.0))   # 饮血护符坠(011): 溢出治疗(超过满血部分)转血护盾, 累积上限
	if _osc > 0.0:
		var _ovf: float = amt - float(u["hp"] - hb)   # 请求治疗量 - 实际回复 = 溢出
		if _ovf > 0.0 and u["shield"] < _osc:
			u["shield"] = minf(_osc, u["shield"] + _ovf)   # 静默累积(吸血高频不刷飘字), 由携带者护盾条显示
	var _act: float = float(u["hp"] - hb)   # 实际回血(满血=0, 超出满血/转盾部分不计入绿字)
	if _act > 0.0:                          # LoL式治疗累加器: 高频/多段/多源回血攒进累加, 短窗后合并成一个绿字(见_heal_flush)
		u["_heal_acc"] = float(u.get("_heal_acc", 0.0)) + _act
		u["_heal_acc_t"] = _t
		if float(u.get("_heal_acc_start", 0.0)) <= 0.0:
			u["_heal_acc_start"] = _t
	if not silent:
		_sfx_heal()                          # §AUDIO: 治疗音 (节流)

func _heal_flush(u: Dictionary) -> void:   # LoL式: 治疗累加器→静默0.15s(一波打完)或攒够0.6s→合并弹一个绿字(=实际回血)
	var acc: float = float(u.get("_heal_acc", 0.0))
	if acc <= 0.0:
		return
	if _t - float(u.get("_heal_acc_t", 0.0)) >= 0.15 or _t - float(u.get("_heal_acc_start", 0.0)) >= 0.6:
		if int(round(acc)) >= 1:
			_float_text(u["pos"] + Vector2(0, -40), "+" + str(int(round(acc))), Color("#06d6a0"), false, "heal")
		u["_heal_acc"] = 0.0
		u["_heal_acc_start"] = 0.0

# 韧性: CC实际时长 = 基础 ×(1-韧性), 最多减90%
func _cc_dur(u: Dictionary, sec: float) -> float:
	return sec * (1.0 - clampf(float(u.get("tenacity", 0.0)), 0.0, 0.9))

func _freeze(u: Dictionary, sec: float = CTRL_SEC) -> void:
	u["stun_until"] = maxf(u["stun_until"], _t + _cc_dur(u, sec))
	_skill_ring(u["pos"], Color(0.6, 0.9, 1.0, 0.6), 48.0)

func _taunt(by: Dictionary, targets: Array, sec: float = BUFF_SEC) -> void:
	for o in targets:
		o["taunt_until"] = _t + sec
		o["taunt_by"] = by

func _buff(u: Dictionary, stat: String, amount: float, pct: bool, sec: float = BUFF_SEC) -> void:
	u["buffs"].append({"stat": stat, "amount": amount, "pct": pct, "until": _t + sec})
	_recalc_stats(u)

func _recalc_stats(u: Dictionary) -> void:
	var acc := {"atk": [0.0, 0.0], "def": [0.0, 0.0], "mr": [0.0, 0.0]}
	var dodge := 0.0
	var ls := 0.0
	for b in u["buffs"]:
		var s: String = b["stat"]
		if s == "dodge":
			dodge += b["amount"]; continue
		if s == "lifesteal":
			ls += b["amount"]; continue
		if not acc.has(s):
			continue
		if b["pct"]:
			acc[s][0] += b["amount"]
		else:
			acc[s][1] += b["amount"]
	u["atk"] = maxf(0.0, u["base_atk"] * (1.0 + acc["atk"][0]) + acc["atk"][1])
	if float(u.get("hammer_pct", 0.0)) > 0.0:
		u["atk"] += u["maxHp"] / HP_MULT * float(u["hammer_pct"])   # 重击锤(047): ATK随maxHp动态成长
	u["def"] = maxf(0.0, u["base_def"] * (1.0 + acc["def"][0]) + acc["def"][1])
	u["mr"]  = maxf(0.0, u["base_mr"]  * (1.0 + acc["mr"][0])  + acc["mr"][1])
	u["dodge_bonus"] = dodge
	u["ls_bonus"] = ls

# flat DoT (诅咒等). dps=每秒落血; 真伤穿护盾. 灼烧/中毒/流血改走 _apply_dot_stacks 层数模型.
func _add_dot(u: Dictionary, tag: String, dps: float, sec: float) -> void:
	u["dots"].append({"tag": tag, "dps": dps, "until": _t + sec})

# 层数式 DoT 施加 (1:1 dot.gd apply_stacks). type∈[burn,poison,bleed]; 多次施加→累加层数. burn 检免疫.
func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if u == null or not u.get("alive", false) or stacks <= 0:
		return
	if _copy_fx_mult != 1.0:
		stacks = maxi(1, roundi(float(stacks) * _copy_fx_mult))   # 龟壳复制期: DoT层数也按60%
	if type == "burn":
		if u.get("_burnImmune", false):
			return
		var passive = u.get("passive", null)
		if passive is Dictionary and passive.get("burnImmune", false):
			return
	var ds: Dictionary = u["dot_stacks"]
	ds[type] = int(ds.get(type, 0)) + stacks
	if src != null:
		u["dot_src"][type] = src

# 灼烧默认层数 = max(1, round(attacker.atk × 0.67))  (1:1 dot.gd default_burn_stacks)
func _default_burn_stacks(attacker: Dictionary) -> int:
	return maxi(1, roundi(float(attacker.get("atk", 0.0)) * 0.67))

func _has_dot(u: Dictionary, tag: String) -> bool:
	if tag == "burn" or tag == "poison" or tag == "bleed":
		return int(u.get("dot_stacks", {}).get(tag, 0)) > 0
	for d in u["dots"]:
		if d["tag"] == tag and _t < d["until"]:
			return true
	return false

# 层数 DoT 每秒结算 (1:1 dot.gd tick). 固定顺序 burn→poison→bleed; 出伤后层数衰减, ≤0 移除.
func _tick_dot_stacks(u: Dictionary) -> void:
	var ds: Dictionary = u.get("dot_stacks", {})
	if ds.is_empty():
		return
	var max_hp: float = u["maxHp"]
	for type in ["burn", "poison", "bleed"]:
		var stacks: int = int(ds.get(type, 0))
		if stacks <= 0:
			continue
		var dmg: int = 0
		var new_val: int = 0
		match type:
			"burn":
				dmg = stacks + roundi(max_hp * stacks * 0.001)
				new_val = floori(stacks * 0.8)   # 衰减80%(用户)
				if _t < u.get("true_fire_until", 0.0):
					_raw_lose(u, float(dmg))
				else:
					_apply_damage(u, dmg, Color("#4dabf7"))   # 灼烧魔蓝(用户)
			"poison":
				dmg = stacks
				new_val = floori(stacks * 0.8)   # 衰减80%(用户)
				_apply_damage(u, dmg, Color("#7ee87e"))
			"bleed":
				dmg = stacks
				new_val = floori(stacks * 0.8)   # 衰减80%(用户)
				_apply_damage(u, dmg, Color("#ff6b6b"))
		ds[type] = maxi(0, new_val)
		if ds[type] <= 0:
			ds.erase(type)
		if not u["alive"]:
			return

func _cleanse(u: Dictionary) -> int:
	var n: int = u["dots"].size()
	u["dots"] = []
	for type in ["burn", "poison", "bleed"]:
		if int(u.get("dot_stacks", {}).get(type, 0)) > 0:
			n += 1
			u["dot_stacks"][type] = 0
	var kept: Array = []
	for b in u["buffs"]:
		if b["amount"] < 0.0:
			n += 1
		else:
			kept.append(b)
	u["buffs"] = kept
	u["slow_until"] = 0.0
	_recalc_stats(u)
	return n

# 计数净化: 至多移除 n 个负面 (dot类/负面buff/减速/眩晕 各算1个); 返回实际移除数.
func _cleanse_n(u: Dictionary, n: int) -> int:
	var removed := 0
	for type in ["burn", "poison", "bleed"]:
		if removed >= n: break
		if int(u.get("dot_stacks", {}).get(type, 0)) > 0:
			u["dot_stacks"][type] = 0; removed += 1
	if removed < n and not u["dots"].is_empty():
		u["dots"].pop_back(); removed += 1
	if removed < n:
		var kept: Array = []
		for b in u["buffs"]:
			if b["amount"] < 0.0 and removed < n:
				removed += 1
			else:
				kept.append(b)
		u["buffs"] = kept
		_recalc_stats(u)
	if removed < n and _t < float(u.get("slow_until", 0.0)):
		u["slow_until"] = 0.0; removed += 1
	if removed < n and _t < float(u.get("stun_until", 0.0)):
		u["stun_until"] = 0.0; removed += 1
	return removed

func _add_stack(u: Dictionary, tag: String, n: int, cap: int) -> int:
	var cur: int = u["stacks"].get(tag, 0) + n
	cur = mini(cur, cap)
	u["stacks"][tag] = cur
	if tag == "ink" and not _ink_link_busy:                       # 连笔·墨迹同步: 一方获墨迹另一方同步(附录B-05)
		var _p: Dictionary = _ink_link_partner(u)
		if not _p.is_empty():
			_ink_link_busy = true
			_add_stack(_p, "ink", n, cap)
			_ink_link_busy = false
	return cur

func _consume_stacks(u: Dictionary, tag: String) -> int:
	var c: int = u["stacks"].get(tag, 0)
	u["stacks"][tag] = 0
	return c

# 直线判定: p 是否在 origin 出发 dir 方向的一条宽 width 直线带上 (前方)
func _on_line(origin: Vector2, dir: Vector2, p: Vector2, width: float) -> bool:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(dir)
	if along < 0.0: return false
	var perp: float = (rel - dir * along).length()
	return perp <= width

func _lowest_hp_ally(u: Dictionary):
	var best = null; var bv := INF
	for o in _allies_of(u):
		if o["hp"] < bv:
			bv = o["hp"]; best = o
	return best

func _allies_of(u: Dictionary, include_self: bool = true) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] == u["side"] and o["alive"] and (include_self or o != u):
			out.append(o)
	return out

# ============================================================================
#  被动系统: 登场被动 / on-hit / 周期被动 (1:1 搬自 2D 版)
# ============================================================================
# 召唤体永远主动平A不放技能; 选被动的龟(暂无)也不放. demo 默认全选主动.
func _is_passive_pick(u: Dictionary) -> bool:
	return u.get("is_summon", false)

# 寒冰登场寒气特效: 蓝霜地环×2 + 上升冰晶 (敌人小, 寒冰自身big)
func _ice_chill_vfx(pos2d: Vector2, big: bool = false) -> void:
	var r: float = 84.0 if big else 52.0
	_skill_ring(pos2d, Color(0.55, 0.85, 1.0, 0.95), r)         # 外层寒环
	_skill_ring(pos2d, Color(0.85, 0.96, 1.0, 0.55), r * 0.5)  # 内层亮霜
	var n: int = 8 if big else 5
	var tex := "res://assets/sprites/skills/ice-spike.png"
	var has_tex := ResourceLoader.exists(tex)
	for i in range(n):
		var sh := Sprite3D.new()
		if has_tex:
			sh.texture = load(tex)
			sh.pixel_size = 0.02 if big else 0.013
			sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			sh.texture = _make_bolt_texture(Color(0.6, 0.85, 1.0))
			sh.pixel_size = 0.01
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.shaded = false
		sh.transparent = true
		sh.modulate = Color(0.62, 0.86, 1.0, 0.95)
		var ang := TAU * float(i) / float(n)
		var off := Vector2(cos(ang), sin(ang)) * (r * 0.45)
		sh.position = _world_pos(pos2d + off, 0.35)
		_world.add_child(sh)
		var tw := _reg_tween()
		tw.set_parallel(true)
		tw.tween_property(sh, "position:y", sh.position.y + (0.9 if big else 0.6), 0.55)
		tw.tween_property(sh, "modulate:a", 0.0, 0.55)
		tw.chain().tween_callback(sh.queue_free)

func _apply_spawn_passives() -> void:
	for u in _units.duplicate():
		match u["id"]:
			"rainbow":
				u["prism_color"] = _juice_rng.randi() % 3   # 开局即给棱镜色(修: 原-1致前6秒普攻无附色)
			"stone":
				if "rockShockwave" in _chosen_skill_types(u["id"], u["side"] == "left") or (_review_demo() and u["id"] == _review_turtle()):
					u["stone_rockbody"] = true   # 岩石之躯(实战: 选rockShockwave技2才有·打包被动); 特效验收时给受审石头强制开→单独看被动体型增长
			"ninja":
				u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["armor_pen"] += 8.0   # 忍术(基础被动)
				if "ninjaShuriken" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 忍者足(技三打包·选中才有): +25%闪避+40%暴击
					_buff(u, "dodge", 0.25, false, 9999.0); u["crit"] += 0.40
			"ghost":
				for o in _enemies_of(u):
					_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
			"ice":
				u["_vs_fire_bonus"] = 0.2          # 寒域: 对熔岩/凤凰 +20%伤害
				u["_burnImmune"] = true            # 极寒(用户设计L162: 改常驻被动): 免疫灼烧
				_ice_chill_vfx(u["pos"], true)     # 寒冰自身登场寒爆(大)
				_flash(u, Color(0.6, 0.86, 1.0))   # 自身蓝闪
				for o in _enemies_of(u):
					o["spd_aspd_mult"] = 0.7        # -30% 攻速
					o["spd_echarge_mult"] = 0.7     # -30% 龟能充能速度
					o["spd_move_mult"] = 0.7        # -30% 移速
					o["spd_dbf_until"] = _t + 12.0   # 登场全场敌减速【12秒】(用户2026-07-11: 原永久改12秒)
					_ice_chill_vfx(o["pos"])        # 敌人寒气蓝环
					_flash(o, Color(0.6, 0.86, 1.0))   # 敌蓝闪
			"headless":
				u["lifesteal"] += 0.22
			"dice":
				u["dice_base_crit"] = u["crit"]; u["dice_base_critdmg"] = u["crit_dmg"]   # 基准(供损血暴击算)
				if "diceFlashStrike" in _chosen_skill_types(u["id"], u["side"] == "left"):
					u["armor_pen"] += u["base_def"] + u["base_mr"]   # 真正的赌徒(打包稳定骰子): 登场双抗全转等量护穿(纯物理)
					u["base_def"] = 0.0; u["base_mr"] = 0.0; _recalc_stats(u)
			"gambler":
				if "gamblerFateWheel" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 命运之轮(技三打包被动·选中才有)·用户2026-07-09重设计
					u["hp"] = maxf(1.0, u["hp"] - u["maxHp"] * 0.30)   # 登场损30%当前血(=30%maxHp·上限不变)
					u["multi_base"] = 0.60                              # 永久基础多重概率40%→60%(与赌注+20%叠加可到80%)
					_float_text(u["pos"] + Vector2(0, -64), "命运之轮 -30%HP", Color("#ff5566"))
					if u["side"] == "left": _gambler_apply_wheel_stacks(u)   # 跨场累积: 登场套用本大轮已抽花色(切轮重置·方案B·只玩家)
			"pirate":
				var es := _enemies_of(u)
				if not es.is_empty():
					var v = es[randi() % es.size()]
					_apply_damage_from(u, v, int(float(v["maxHp"]) * 0.25), Color("#ffd07a"), 0.0, true); _burst_vfx("res://assets/sprites/vfx/cannon-blast.png", v["pos"], 150.0, 1.0)   # 掠夺·登场轰击1敌 = 25%目标最大生命【真实伤害】(用户2026-07-10订死)
			"candy":
				var ce := _enemies_of(u)
				if not ce.is_empty():
					var fat = ce[0]                              # 甜蜜吸取(封板): 对最肥敌(最大生命最高)吸取25%maxHp→全回复(不杀·留1)
					for e in ce:
						if float(e["maxHp"]) > float(fat["maxHp"]): fat = e
					var steal: float = minf(fat["maxHp"] * 0.25, fat["hp"] - 1.0)
					if steal > 0: _raw_lose(fat, steal); _heal(u, steal)
				# 【用户2026纠错】普攻自愈=我自造的(原话普攻只有1.1A+5%maxHp+攻击-15%·无自愈)→删除; 自我回血在焦糖铠/甜蜜吸取
				if "candyBomb" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 糖果炸弹(技三·选中才召): HP=50%糖果龟maxHp·每秒衰减8%·死亡爆炸150%
					_spawn_summon(u, "candybomb", u["maxHp"] * 0.50, 0.0, {
						"label": "糖果炸弹", "spr_id": "candy-bomb", "col_size": 20.0, "hp_w": 24.0,
						"no_basic": true, "no_move": true, "self_decay": 0.08,
						"death_aoe": 1.5,
					})
			"chest":
				if "chestCannon" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 贪婪(技三打包被动)选中才有
					u["chest_greed"] = true
					u["chest_greed_atk_unit"] = u["base_atk"] * 0.04
					u["chest_greed_hp_unit"] = u["maxHp"] * 0.07
					_chest_greed_apply(u, (u.get("equips", []) as Array).size())   # 登场先按已带装备数结算
			"hiding":
				_spawn_hiding_minion(u)
			"cyber":
				if "cyberSmartAI" in _chosen_skill_types(u["id"], u["side"] == "left"):
					u["move_spd"] = float(u.get("move_spd", 105.0)) * 1.2   # 智能AI(技三·选中): 登场+20%移速(常驻走位)
					u["cyber_ai_charge"] = 3   # 用户2026-07-07逐字"赛博龟登场时拥有3层充能" (此前漏做, 从0起算)
					# ⚠ 充能的【消耗方式与收益】用户从未定义 → 现仅作计数(_sk_cyber_smart 每次释放+1), 不猜、不自造。
			"crystal":
				if "crystalBall" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 水晶球(技三·选中才召): 登场召唤实体水晶球
					_spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
						"label": "水晶球", "spr_id": "crystal-ball", "col_size": 20.0, "hp_w": 26.0, "melee": false,
						"move_spd": 90.0, "atk_range": 320.0, "no_basic": true,
						"special": "ray", "special_cd": 5.0, "special_scale": 0.5,   # 攻速0.2≈5s一发(封板)·每发2段共1.0A魔法
					})
			"two_head":
				u["two_form"] = "ranged"; u["melee"] = false; u["atk_range"] = 400.0   # 双生: 远程起手
				if "twoHeadFusion" in _chosen_skill_types(u["id"], u["side"] == "left"):
					u["two_fused"] = true                          # 融合: 锁形态(保持远程)+坚韧+合体近战属性
					_two_head_apply_melee(u, true)
			"diamond":                                    # 钻石结构(封板): 全队护甲/魔抗加成+50%(简化=开局全队+50%pct); 选钻石冲撞→强化结构(自身额外+100%·"受击再减20甲10抗"近似折进护甲留F5)
				for o in _allies_of(u):
					_buff(o, "def", 0.5, true, 9999.0)
					_buff(o, "mr", 0.5, true, 9999.0)
				if "diamondSmash" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 强化钻石结构(技三打包·选中才有): 自身护甲/魔抗额外+100%
					_buff(u, "def", 1.0, true, 9999.0)
					_buff(u, "mr", 1.0, true, 9999.0)
	# 选中被动技开局生效 (不进主动轮转): 凤凰强化涅槃 等 (寒冰极寒已改常驻被动, 见上ice分支)
	for u in _units:
		if "phoenixEnhancedRebirth" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_enh_rebirth"] = true   # 强化涅槃: 复活100%血+永久+20%攻击(见_kill)
		if "angelBless" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_angel_revive"] = true  # 天使祝福绑定: 选祝福→自身首死25%复活(见_kill)
		if "rainbowReflect" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_enh_prism"] = true      # 彩虹反射打包强化棱镜4色(每5s抽色·见_tick_periodic)

func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":
			_add_stack(tgt, "ink", 1, _ink_cap(u))
		"lightning":
			_lightning_electric(u, tgt)   # 普攻主目标叠电击+可引爆(连锁跳由_lightning_hop叠)
		"crystal":
			_apply_damage_from(u, tgt, _mitigate(u, tgt["maxHp"] * 0.015, tgt, true), Color("#9bdcff"), 0.0, false)   # 水晶刺附1.5%目标最大生命魔法(吃魔抗·封板L559·原折进物理=类型错)
			_crystal_stack(u, tgt, 1)   # 普攻叠1层结晶(满5引爆·封板)·与水晶球共享层数走同一helper(引爆改吃魔抗)
		"angel":                                          # 审判: 每段攻击额外 +目标当前HP 11% 魔法
			_apply_damage_from(u, tgt, _mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 魔法(吃魔抗+蓝字), 原flat固定值绕魔抗+错色=bug
		# gambler 多重打击改云顶剑士式连击(见状态机 _gambler_multi_cd), 不在这里追加
		"bamboo":                                         # 生长(改造): 蓄力时下一发普攻强化(追加魔法+回血+永久成长)
			if u.get("bamboo_charge", false):
				u["bamboo_charge"] = false
				_apply_damage_from(u, tgt, _mitigate(u, u["atk"] * (1.0 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.75) + u["maxHp"] * (0.13 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.08), tgt, true), Color("#9be7ff"), 0.0, false)   # 追击魔法·选竹击=强化生长(1.0A+13%maxHp)否则基础(0.75A+8%maxHp)·用户核对JS bambooCharged
				_melee_lunge(u, tgt, 0.66)                                     # 不灭之握式: 强化发踏步加倍(0.30→0.66)明显扑上去
				_hitstop = maxf(_hitstop, 0.06)                                # 顿帧=命中厚重感
				_shake(0.06)
				_impact_particles(tgt["pos"], float(tgt.get("height", 0.0)))   # 命中碎屑迸发
				_flash(tgt, Color(0.5, 1.7, 0.65))                             # 敌绿闪(生长主题)
				_bamboo_hit_splash(tgt)                                        # 命中: 敌人身上爆一下大淡绿命中特效(≈上半身大小·用户2026-07-11); 施法者tell=双手绿点(蓄满期), 不在命中闪
				# 回血+永久成长 延到绿球落到竹叶龟身上才生效 (用户: 到自己身上才吸收)
				_spawn_bamboo_orb(tgt["pos"], u["pos"], func() -> void:
					if not u.get("alive", false):
						return
					_heal(u, u["maxHp"] * (0.12 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.08))
					var _gr := (1.05 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.60); u["maxHp"] += u["base_atk"] * _gr; u["hp"] += u["base_atk"] * _gr; _recalc_stats(u); _flash(u, Color(0.5, 1.7, 0.65)))   # 永久+maxHp=系数×ATK + 吸收瞬间竹叶龟再绿闪(得到生命·不灭之握=绿闪非环)
		"rainbow":                                        # 棱镜(改造): 普攻附当前颜色效果(红真伤/蓝小盾/绿回血)
			match int(u.get("prism_color", -1)):
				0: _apply_damage_from(u, tgt, int(u["atk"] * 0.25), Color("#ff6b6b"), 0.0, true)   # 红: 额外真伤
				1: _grant_shield(u, u["atk"] * 0.2, 4.0)                                           # 蓝: 每普攻获小盾(通用护盾4秒·封板L74"基础龟被动蓄力普攻的护盾也4秒")
				2: _heal(u, (u["maxHp"] - u["hp"]) * 0.025, true)                                               # 绿: 回2%最大HP
	# 猎人猎杀已移到 _apply_damage_from 中央伤害路径(封板: 普攻/技能/装备任一伤害都处决<斩杀线)
	# 猎人·隐蔽翻滚强化: 下次普攻附带0.9A物理(吃吸血), 用后即清
	if u["id"] == "hunter" and u.get("hunter_roll_buff", false):
		u["hunter_roll_buff"] = false
		if tgt.get("alive", false):
			_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#a8ffb0"))
	# 小龟·不屈(龟盾融入): 每6秒强化普攻 → 附0.7A+20%已损物理+击飞+盾(复用_sk_basic_shield)
	if u["id"] == "basic" and u.get("basic_enh_ready", false):
		u["basic_enh_ready"] = false
		if tgt.get("alive", false):
			_sk_basic_shield(u, tgt)
	# 无头亡灵: 每损1%HP攻击+1%(上限+100%)
	if u["id"] == "headless":
		var lost_pct: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["atk"] = u["base_atk"] * (1.0 + lost_pct)

func _tick_periodic_passive(u: Dictionary, delta: float) -> void:
	u["_ptimer"] = u.get("_ptimer", 0.0) + delta
	# --- 限时护盾原语: 到期清盾 (dur>0的盾; shield_until=0=永久不过期) ---
	var _shu: float = float(u.get("shield_until", 0.0))
	if _shu > 0.0 and _t >= _shu:
		if float(u.get("shield", 0.0)) > 0.0: u["shield"] = 0.0
		u["shield_until"] = 0.0
	# --- 泡泡盾: 到期 或 被打破(盾清零) → 爆裂对施法者全体敌2.0A魔法 (封板L435·防静默过期丢爆裂) ---
	var _bbu: float = float(u.get("bubble_shield_until", 0.0))
	if _bbu > 0.0 and (_t >= _bbu or float(u.get("shield", 0.0)) <= 0.0):
		_bubble_shield_burst(u)
	# --- 冰霜团队护盾: 到期 或 被打破(盾清零) → 250码内敌 boom×ATK 魔法(用户2026-07-11) ---
	var _fsu: float = float(u.get("frost_shield_until", 0.0))
	if _fsu > 0.0 and (_t >= _fsu or float(u.get("shield", 0.0)) <= 0.0):
		_frost_shield_burst(u)
	# --- 赛博侵入: 被黑单位4秒到期→归队(side还原·清hijacked·数据链断) ---
	if u.get("hijacked", false) and _t >= float(u.get("hijack_until", 0.0)):
		u["side"] = str(u.get("_hijack_orig_side", u["side"]))
		u["hijacked"] = false
		_float_text(u["pos"] + Vector2(0, -48), "归队", Color("#8a93a0"))
	# --- 龟壳·潜影(暗影主被动·选中暗影才有): 6秒未受伤→进入隐身 ---
	if u["id"] == "shell" and not u.get("shell_stealth", false) and _t - float(u.get("shell_last_dmg_t", 0.0)) >= 6.0 and "shellShadow" in _chosen_skill_types(u["id"], u["side"] == "left"):
		_shell_enter_stealth(u)
	# --- 小龟·不屈(龟盾融入被动): 每6秒强化下次普攻(在_on_basic_hit消费=0.7A+20%已损+击飞+盾) ---
	if u["id"] == "basic":
		u["basic_enh_t"] = float(u.get("basic_enh_t", 0.0)) + delta
		if float(u["basic_enh_t"]) >= 6.0:
			u["basic_enh_t"] = 0.0
			u["basic_enh_ready"] = true
	# --- 熔岩变身: 怒气满100 → 变火山15秒 (被动 熔岩之心) ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		_lava_transform(u)
	if u.get("volcano", false) and _t >= float(u.get("volcano_until", 0.0)):
		_lava_revert(u)
	if u["id"] == "chest":
		_chest_treasure_tick(u)
	# --- 忍者·冲击(亚索E式被动auto-dash): 500码内有"可冲"敌(不在其10s冷却)且距上次冲刺≥0.4s → 自动朝最近敌冲刺斩(用户2026-07-06"半径500码，最近敌人") ---
	if u["id"] == "ninja" and u.get("alive", false) and _t >= float(u.get("stun_until", 0.0)):
		if _t - float(u.get("_ninja_last_dash", -99.0)) >= 0.4:
			var _nbest = null
			var _nbd := 500.0
			for o in _enemies_of(u):
				if not o.get("alive", false): continue
				if _t < float(o.get("_ninja_dash_until", 0.0)): continue
				var _ndd: float = u["pos"].distance_to(o["pos"])
				if _ndd <= _nbd: _nbd = _ndd; _nbest = o
			if _nbest != null: _ninja_dash(u, _nbest)
	if u["id"] == "dice":   # 赌徒之血: 按已损血加暴击(损30%满+50%); 暴击率>100%部分每1%→1.5%暴伤
		var _lost: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["crit"] = float(u.get("dice_base_crit", u["crit"])) + minf(_lost / 0.30, 1.0) * 0.50
		# (暴击率>100%转暴伤由 _resolve_dmg 全局处理, 这里只设暴击率)
	# --- 赛博浮游炮: 每周期生成1 (上限10) ---
	if u["id"] == "cyber":
		if u["_ptimer"] >= 3.0:
			u["_ptimer"] = 0.0
			var live: Array = []
			for d in u["summons"]:
				if d is Dictionary and d.get("alive", false): live.append(d)
			u["summons"] = live
			for _dk in range(2):                                # 封板: 每周期生成2炮(强化浮游炮并入被动·上限20)
				if u["summons"].size() >= 20: break
				var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25, {
					"label": "浮游炮", "col_size": 16.0, "hp_w": 22.0, "melee": false,
					"move_spd": 110.0, "atk_range": 300.0, "atk_interval": 1.0,
					"no_basic": true, "special": "random_hit", "special_cd": 1.6, "special_scale": 0.12,
				})
				if dr != null: u["summons"].append(dr)
	# --- 石头坚壁: 每2.5秒永久+开局护甲/6, 上限=开局护甲×2(+100%); 反伤随护甲涨 ---
	elif u["id"] == "stone":
		if not u.has("stone_init_def"):
			u["stone_init_def"] = u["base_def"]            # 记开局护甲(含等级缩放)
		if u["_ptimer"] >= 2.5:
			u["_ptimer"] = 0.0
			var _cap: float = u["stone_init_def"] * 2.0
			if u["base_def"] < _cap:
				u["base_def"] = minf(_cap, u["base_def"] + u["stone_init_def"] / 6.0)
				_recalc_stats(u)
				_skill_ring(u["pos"], Color(0.79, 0.64, 0.42, 0.4), 42.0)   # 视觉: 硬化贴地褐环 (不飘名字文字)
	# --- 竹叶生长: 每N秒充能 → 永久+ATK/HP ---
	elif u["id"] == "bamboo":
		if u["_ptimer"] >= 6.0 and not u.get("bamboo_charge", false):
			u["_ptimer"] = 0.0
			u["bamboo_charge"] = true
	# --- 龟壳气场觉醒 + 储能消耗周期 ---
	elif u["id"] == "shell":
		if not u.get("awakened", false) and _t >= 10.0:
			u["awakened"] = true
			_shell_apply_awaken(u)   # 开战10秒觉醒 (+金光爆发特效)
		if not u.get("awakened2", false) and _t >= 20.0:
			u["awakened2"] = true
			_shell_apply_awaken(u)   # 开战20秒第二次觉醒(封板: 强化觉醒已并入被动·自动触发·不再gate选中)
		# 储能相位机: store(6s 受伤转储能) → 释放(冲击波+护盾) → cd(15s 不储) → store…
		_shell_phase_tick(u, delta)
	# 海盗船(实体)已改为 技能三 pirateShipPassive 首次充能满召唤(_sk_pirate_ship·选中才召·封板L378"火炮/朗姆的船=纯装饰演出"); 原无条件4s自动召唤删除
	# --- 宝箱藏宝图·朗姆酒战利品: 每10秒回8%最大生命(封板L592·flag由开箱设) ---
	if u["id"] == "chest" and (u.get("chest_treasures", {}) as Dictionary).has("rum"):
		u["chest_rum_t"] = float(u.get("chest_rum_t", 0.0)) + delta
		if u["chest_rum_t"] >= 10.0:
			u["chest_rum_t"] = 0.0; _heal(u, u["maxHp"] * 0.08)
	# --- 钻石滚球被动(封板): 选滚球 且 100码内无敌 → 免费自动滚(不耗龟能不充能)撞向最近·0.8s防抖内CD ---
	if u["id"] == "diamond" and not u.get("roll_active", false) and _t > float(u.get("roll_free_cd", 0.0)) and "diamondPowerball" in _chosen_skill_types(u["id"], u["side"] == "left"):
		var _dne = _nearest_enemy(u)
		if _dne != null and _dne["pos"].distance_to(u["pos"]) > 100.0:   # 100码内无敌=最近敌>100码
			u["roll_active"] = true; u["roll_start"] = _t; u["roll_free_cd"] = _t + 0.8
	# --- 财神聚宝盆: 每3秒 +4~7金币 (用户) ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 3.0:
			u["_goldtimer"] = 0.0; u["gold"] += _juice_rng.randi_range(4, 7)
	# --- 彩虹棱镜(封板L267): 每6秒随机红/蓝/绿·普攻附对应效果(红+0.25A真伤/蓝+0.2A盾4s/绿回2.5%已损·见_on_basic_hit) ---
	if u["id"] == "rainbow":
		u["_rbtimer"] = u.get("_rbtimer", 0.0) + delta
		if u["_rbtimer"] >= 6.0:
			u["_rbtimer"] = 0.0
			u["prism_color"] = randi() % 3   # 棱镜(改造): 自身获颜色6秒, 普攻附色(见 _on_basic_hit)
		if u["id"] == "rainbow" and u.get("_enh_prism", false):   # 强化棱镜(选反射打包): 每5秒抽1色(橙吸血/黄灼烧/青冰寒/紫诅咒)
			u["_epTimer"] = float(u.get("_epTimer", 0.0)) + delta
			if u["_epTimer"] >= 5.0:
				u["_epTimer"] = 0.0
				_rainbow_enh_prism_proc(u)
	# --- 泡泡·泡沫(封板L428): 每3秒→泡泡值10%化魔法打最近敌 + 治疗自己10%泡泡值 (共消耗20%泡泡值) ---
	if u["id"] == "bubble":
		u["_bbtimer"] = u.get("_bbtimer", 0.0) + delta
		if u["_bbtimer"] >= 3.0:                       # 修: 2.5→3秒(封板)
			u["_bbtimer"] = 0.0
			var bs: float = float(u.get("bubble_store", 0.0))
			if bs >= 1.0:
				_heal(u, bs * 0.10, true)              # 修: 15%→10%(封板)
				var bt = _nearest_enemy(u)             # 修: 随机敌→最近敌(封板)
				if bt != null:
					_apply_damage_from(u, bt, int(_mitigate(u, bs * 0.10, bt, true)), Color("#aef1ff"))   # 修: 35%真伤→10%化魔法(吃魔抗·封板)
				u["bubble_store"] = bs * 0.80          # 修: 消耗50%→共消耗20%(10%伤+10%治·封板)
	# --- 闪电·雷电: 每4s 自动电击随机敌 (真伤) (用户) ---
	if u["id"] == "lightning":
		u["_ltimer"] = u.get("_ltimer", 0.0) + delta
		if u["_ltimer"] >= 4.0:
			u["_ltimer"] = 0.0
			var le := _enemies_of(u)
			if not le.is_empty():
				var lv2 = le[randi() % le.size()]
				_apply_damage_from(u, lv2, _shock_dmg(u), Color("#4dabf7"), 0.0, true)
				_lightning_strike(lv2["pos"], Color("#aef0ff"))   # 天降闪电(自动电击)

# ============================================================================
#  龟壳·气场觉醒 储能相位机 (用户改造): store 6s → 释放(缓慢冲击波+衰减护盾) → cd 15s → 循环
# ============================================================================
const SHELL_STORE_SEC := 6.0          # 储能相位时长 (受伤转储能)
const SHELL_CD_SEC := 15.0            # 冷却相位时长 (不储能)
const SHELL_SW_RADIUS := 520.0        # 冲击波最大半径 (px)
const SHELL_SW_SEC := 1.8             # 冲击波扩张时长
const SHELL_SHIELD_SEC := 5.0         # 护盾流失时长

func _shell_apply_awaken(u: Dictionary) -> void:   # 气场觉醒一次(六属性+12%/暴击+25%) + 金光爆发特效
	_buff(u, "atk", 0.12, true, 9999.0); _buff(u, "def", 0.12, true, 9999.0); _buff(u, "mr", 0.12, true, 9999.0)
	_buff(u, "lifesteal", 0.12, true, 9999.0)   # +12%吸血
	var ah: float = u["maxHp"] * 0.12; u["maxHp"] += ah; u["hp"] += ah   # +12%最大生命
	u["reflect"] = float(u.get("reflect", 0.0)) + 0.12   # 反伤+12% (回合制 auraAwaken.reflectPct=12; reflect是通用字段·受伤端_apply_damage_from已有反弹钩)
	u["crit"] += 0.25; _recalc_stats(u)
	_shell_awaken_vfx(u)

func _shell_awaken_vfx(u: Dictionary) -> void:   # 觉醒金光爆发: 震屏+微顿帧 + 强金闪 + 双金环 + 金光柱 + 金光上腾 + "觉醒"飘字
	_shake(JUICE_SHAKE_HEAVY)
	_hitstop = maxf(_hitstop, 0.06)
	_flash(u, Color(1.0, 0.92, 0.55))
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.28, 0.9), 132.0)   # 外金环
	_skill_ring(u["pos"], Color(1.0, 0.95, 0.6, 0.9), 76.0)     # 内亮环
	_float_text(u["pos"] + Vector2(0, -88), "觉醒", Color(1.0, 0.86, 0.25))
	# 金光柱: 竖直上冲一束 (醒目, 不怕被伤害数字盖)
	var pil := Sprite3D.new()
	pil.texture = _make_fire_glow_tex()
	pil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pil.shaded = false; pil.transparent = true
	pil.pixel_size = 0.013
	pil.modulate = Color(1.0, 0.9, 0.45, 0.0)
	pil.scale = Vector3(0.55, 2.6, 1.0)
	pil.position = _world_pos(u["pos"], 0.7)
	_world.add_child(pil)
	var tp := _reg_tween(); tp.set_parallel(true)
	tp.tween_property(pil, "modulate:a", 0.9, 0.1)
	tp.tween_property(pil, "position", _world_pos(u["pos"], 1.6), 0.55)
	tp.chain().tween_property(pil, "modulate:a", 0.0, 0.28)
	tp.chain().tween_callback(pil.queue_free)
	# 金光上腾粒子 (更多更大)
	for i in range(14):
		var ang: float = TAU * float(i) / 14.0 + _juice_rng.randf_range(-0.2, 0.2)
		var dd: float = _juice_rng.randf_range(10.0, 50.0)
		var p: Vector2 = u["pos"] + Vector2(cos(ang), sin(ang)) * dd
		var spr := Sprite3D.new()
		spr.texture = _make_fire_glow_tex()
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.pixel_size = 0.008
		spr.modulate = Color(1.0, 0.9, 0.45, 0.95)
		spr.scale = Vector3(0.6, 0.6, 0.6)
		spr.position = _world_pos(p, 0.5)
		_world.add_child(spr)
		var tw := _reg_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "position", _world_pos(p, 1.95 + _juice_rng.randf_range(0.0, 0.6)), 0.6)
		tw.tween_property(spr, "scale", Vector3(1.3, 1.3, 1.3), 0.6)
		tw.tween_property(spr, "modulate", Color(1.0, 0.72, 0.2, 0.0), 0.6)
		tw.chain().tween_callback(spr.queue_free)

func _shell_phase_tick(u: Dictionary, delta: float) -> void:
	# 护盾线性流失 (每帧扣, 不低于0) — 与相位独立, 始终推进
	if float(u.get("shell_shield_decay_rate", 0.0)) > 0.0 and float(u.get("_auraShieldVal", 0.0)) > 0.0:
		u["_auraShieldVal"] = maxf(0.0, float(u["_auraShieldVal"]) - float(u["shell_shield_decay_rate"]) * delta)
		if u["_auraShieldVal"] <= 0.0:
			u["shell_shield_decay_rate"] = 0.0
	# 冲击波扩张 + 逐敌一次性命中 (始终推进, 与相位独立)
	if u.get("shell_sw", null) != null:
		_shell_shockwave_tick(u, delta)
	# 相位推进
	var phase: String = u.get("shell_phase", "store")
	u["shell_timer"] = float(u.get("shell_timer", 0.0)) + delta
	if phase == "store":
		if u["shell_timer"] >= SHELL_STORE_SEC:
			u["shell_timer"] = 0.0
			u["shell_phase"] = "cd"
			_shell_release(u)
	else:  # "cd"
		if u["shell_timer"] >= SHELL_CD_SEC:
			u["shell_timer"] = 0.0
			u["shell_phase"] = "store"

# 释放: 捕获储能→清零→发缓慢冲击波(逐敌×40%物理)+ 获80%储能护盾(5秒流失)
func _shell_release(u: Dictionary) -> void:
	var se: float = float(u.get("store_energy", 0.0))
	u["store_energy"] = 0.0
	u["_auraEnergy"] = 0.0
	if se < 1.0:
		return
	# 1) 缓慢移动冲击波 (Image环贴图, 半径0→520px / 1.8s; 每敌只命中一次)
	_shell_spawn_shockwave(u, int(se * 0.40))
	# 2) 衰减护盾 = 80%储能, 5秒线性流失到0
	var amt: float = se * 0.80
	u["_auraShieldVal"] = float(u.get("_auraShieldVal", 0.0)) + amt   # 金色储能护盾(特殊色, 1:1回合制aura盾)
	u["shell_shield_decay_rate"] = amt / SHELL_SHIELD_SEC   # 每秒扣量 (按授予值算, 5秒清)

# 冲击波节点 (Image环贴图躺平贴地; 绝不用 GradientTexture2D FILL_RADIAL → 会画方角)
func _shell_spawn_shockwave(u: Dictionary, dmg: int) -> void:
	var spr := Sprite3D.new()
	spr.texture = _make_ring_texture(Color(1.0, 0.84, 0.22, 1.0))
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.axis = Vector3.AXIS_Y                       # 躺平贴地
	spr.shaded = false
	spr.transparent = true
	spr.modulate = Color(1.0, 0.84, 0.22, 1.0)       # 黄色能量波(用户); alpha 起始满, 扩张中淡出
	spr.pixel_size = 0.0001                          # 起始 ~0 (扩张到 520px 直径)
	spr.position = _world_pos(u["pos"], 0.05)
	_world.add_child(spr)
	# 状态: 中心/当前半径/已命中集合(逐敌一次)/伤害/节点
	u["shell_sw"] = {
		"node": spr,
		"center": u["pos"],
		"t": 0.0,
		"radius": 0.0,
		"hit": {},          # 用 get_instance_id() 当键, 每敌只算一次
		"dmg": dmg,
	}

# 冲击波每帧推进: 半径 0→520 / 1.8s; ring 直径=2×radius; 距中心被环刚扫过的敌人吃一次伤害
func _shell_shockwave_tick(u: Dictionary, delta: float) -> void:
	var sw: Dictionary = u["shell_sw"]
	var spr = sw.get("node", null)
	sw["t"] = float(sw["t"]) + delta
	var frac: float = clampf(float(sw["t"]) / SHELL_SW_SEC, 0.0, 1.0)
	var r: float = SHELL_SW_RADIUS * frac
	sw["radius"] = r
	# 视觉: ring 贴图 96px 宽 → pixel_size 让直径 = 2r(px)×WS(米/px)
	if spr != null and is_instance_valid(spr):
		spr.pixel_size = maxf(0.0001, (r * 2.0 * WS) / 96.0)
		spr.modulate.a = 1.0 - frac * 0.55           # 边扩边淡 (终态 ~0.45, 保持可见到末尾)
	# 命中: 距中心 <= 当前半径 且未命中过的敌人 (环刚扫过) 各吃一次
	var center: Vector2 = sw["center"]
	var hit: Dictionary = sw["hit"]
	var dmg: int = int(sw["dmg"])
	if dmg > 0:
		for e in _enemies_of(u):
			var spr_e = e.get("sprite", null)        # 用立绘节点实例id当唯一键(每单位唯一; dict不能取instance_id)
			if spr_e == null or not is_instance_valid(spr_e):
				continue
			var eid: int = spr_e.get_instance_id()
			if hit.has(eid):
				continue
			if (e["pos"] - center).length() <= r:
				hit[eid] = true
				_apply_damage_from(u, e, dmg, Color("#b0ffe0"))
	# 结束: 清理节点+状态
	if frac >= 1.0:
		if spr != null and is_instance_valid(spr):
			spr.queue_free()
		u["shell_sw"] = null

# ============================================================================
#  死亡钩子 (1:1 搬自 2D 版 _on_unit_death; 装备 on-kill/on-death Phase 3b 不调)
# ============================================================================
func _on_unit_death(u: Dictionary, killer) -> void:
	# 泡泡盾: 挂盾对象阵亡(=盾随之破) → 爆裂对施法者全体敌2.0A魔法(封板L435·防对象死丢爆裂)
	if float(u.get("bubble_shield_until", 0.0)) > 0.0:
		_bubble_shield_burst(u)
	# 冰霜团队护盾: 持盾者阵亡(=盾随之破) → 250码内敌 boom×ATK 魔法(用户2026-07-11)
	if float(u.get("frost_shield_until", 0.0)) > 0.0:
		_frost_shield_burst(u)
	# 财神聚宝盆: 任意单位阵亡 → 全场存活的财神龟 +9 金币
	for f in _units:
		if f.get("alive", false) and f.get("id") == "fortune" and f != u:
			f["gold"] += 9
	# 海盗掠夺(被动·原版·死亡钩索): 【海盗龟自己阵亡】的瞬间 → 钩锁【击杀它的那个单位】·拉近至90码 + 25%击杀者最大生命【真实伤害】
	#   ★2026-07-10 修真bug: 原实装写成「任意敌人阵亡 → 存活海盗龟钩索【最近敌】」, 触发条件与目标都与原版不符。
	#   依据: 回合制原版逐字(pets.json passive.desc)「死亡时钩锁击杀者，同样造成25%最大生命值真实伤害」
	#         + 用户〖#15〗「掠夺我是说被动的【原版】海盗被动」+ 用户〖2026-07-10〗「死亡的伤害值同上」。
	if u.get("id", "") == "pirate" and not u.get("is_summon", false) and killer is Dictionary and killer.get("alive", false) and killer != u:
		var _pk: Dictionary = u                                  # 钩索从海盗龟的尸位甩出
		var _pt: Dictionary = killer                             # 目标 = 击杀者
		var _pd: Vector2 = _pk["pos"] - _pt["pos"]
		var _pt0: Vector2 = _pt["pos"]                          # 抓取点(拉近前·索线要画到这)
		_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", _pk["pos"], _pt0, 26.0, Color(1.0, 0.85, 0.4, 0.85), 0.35)   # 死亡钩索索线(甩出抓住)
		if _pd.length() > 90.0:
			_pt["pos"] = _pk["pos"] - _pd.normalized() * 90.0    # 把击杀者拉到海盗尸位 90 码处
		_apply_damage_from(_pk, _pt, int(float(_pt["maxHp"]) * 0.25), Color("#ffd07a"), 0.0, true)   # 25%【击杀者】最大生命·真实伤害
		_burst_vfx("res://assets/sprites/vfx/cannon-blast.png", _pt["pos"], 90.0, 1.0)
	# 缩头随从先死 → 主人永久继承"强化随从"增益(可多次随从累积·把力量传给主人)
	if u.get("minion_kind", null) != null:
		var _hm = u.get("summon_owner", null)
		if _hm != null and _hm.get("alive", false) and str(_hm.get("id", "")) == "hiding":
			_hiding_apply_buff(_hm, -1.0)
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_apply_damage_from(u, o, int(per), Color("#ff8ad8"), 0.0, true, true)
			_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 120.0)
	if u.get("boom_pct_true", 0.0) > 0.0:                 # 032骷髅死亡: 200码内敌各受其%最大生命真伤
		var _br: float = float(u.get("boom_radius", 200.0))
		for _bo in _enemies_of(u):
			if _bo.get("alive", false) and (_bo["pos"] - u["pos"]).length() <= _br:
				_apply_damage_from(u, _bo, int(float(_bo["maxHp"]) * float(u["boom_pct_true"])), Color("#8affa0"), 0.0, true, true)
		_necro_burst(u["pos"], _br)
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				_hide_summon_nodes(o)
	# ★2026-07-11 用户拍板「要加死亡同步」: 水晶龟阵亡 → 水晶球随从一同消失 (仿缩头; 原本水晶球会继续战斗)
	if u["id"] == "crystal":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o.get("summon_kind", "") == "crystalball" and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				_hide_summon_nodes(o)
	# 赛博龟阵亡 → 浮游炮组装成机甲
	if u["id"] == "cyber":
		_cyber_assemble_mech(u)
	# (删: 原"死亡给对面财神+2金币"=不在规格的stray bug; 数据是每2.5s+2深海币meta, 非死亡金币)
	# 猎人猎杀: 击杀者是猎人 → 窃取属性+叠吸血
	if killer != null and killer["alive"] and killer["id"] == "hunter":
		killer["base_atk"] += u["base_atk"] * 0.14
		killer["base_def"] += u["base_def"] * 0.14   # 窃取(补): 护甲/魔抗/最大生命也偷14%
		killer["base_mr"] += u["base_mr"] * 0.14
		var _hs: float = u["maxHp"] * 0.14
		killer["maxHp"] += _hs; killer["hp"] += _hs
		killer["lifesteal"] += 0.08
		_recalc_stats(killer)
	# 幽灵强化怨灵: 死亡时再诅咒全体敌一次
	if u["id"] == "ghost":
		for o in _enemies_of(u):
			_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
	# 海盗掠夺被动已按封板L354/382删除(掠夺去掉→海盗龟无被动·场外船是共用演出载体·待用户确认是否补新被动)

# ============================================================================
#  召唤系统 (3D 化: billboard 立绘/色块 + blob影, 走同一 _tick_unit) — 逻辑 1:1 搬自 2D 版
# ============================================================================
# 缩头随从候选池。★2026-07-11 用户拍板:「缩头乌龟只能召唤A及以下的」「确保涵盖所有A，B，C的」
#   → 不再手挑名单, 改为【运行时从稀有度动态生成】: 全部 A/B/C 稀有度的龟 (当前 19 只), 天然排除 S/SS/SSS。
#   这样以后加龟或改稀有度也永远覆盖全 A/B/C, 不会漏也不会混进高稀有度。守卫: tests/verify_hiding_pool.gd。
#   下面的常量只作【数据缺失时的兜底名单】(全是 A/B/C, 不含 headless)。
const HIDING_POOL := ["basic", "stone", "bamboo", "ninja", "dice", "rainbow", "hunter", "pirate", "candy", "bubble", "line"]

# 返回当前所有 A/B/C 稀有度的龟 id (缩头召唤池)。数据缺失时退回 HIDING_POOL 兜底。
func _hiding_pool() -> Array:
	var out: Array = []
	for id in _data_by_id:
		var r := str((_data_by_id[id] as Dictionary).get("rarity", ""))
		if r == "A" or r == "B" or r == "C":
			out.append(str(id))
	return out if not out.is_empty() else HIDING_POOL

func _spawn_hiding_minion(u: Dictionary) -> void:
	var pool: Array = _hiding_pool()
	var pick: String = pool[randi() % pool.size()]
	var d: Dictionary = _data_by_id.get(pick, {})
	var st: Array = STATS.get(pick, DEFAULT_STAT)
	var _lm: float = _lvl_mult_for(u)                # 固定值召唤吃等级
	# ★2026-07-10订正: 旧注释写"召唤=主人最终hp×40%"是错的。d = 【被召唤那只龟】的数据 → HP/ATK 都按【它自己】的基础值算。
	#   HP = 该龟 hp × 40% (×等级);  ATK = 该龟 atk × 80% (×等级);  def/mr/crit 照该龟原值 (见下)。
	var hp: float = float(d.get("hp", 1350)) * 0.40 * _lm
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8 * _lm, {
		"label": "随从", "spr_id": pick, "col_size": 36.0, "hp_w": 30.0,
		"melee": bool(st[0]), "move_spd": float(st[1]), "atk_interval": float(st[2]), "atk_range": float(st[3]),
		"crit": float(d.get("crit", 0.2)),
	})
	if minion != null:
		minion["minion_kind"] = pick
		minion["hiding_protected"] = true
		# A方案·完整乌龟随从: 真·某龟种(id-keyed普攻/被动/技能触发) + 带自己技能/龟能/AI
		minion["id"] = pick
		minion["rarity"] = str(d.get("rarity", "C"))
		minion["base_def"] = float(d.get("def", 10)) * _lm; minion["def"] = minion["base_def"]   # 属性正常(补def/mr·原召唤=0)
		minion["base_mr"] = float(d.get("mr", 10)) * _lm; minion["mr"] = minion["base_mr"]
		minion["crit_dmg"] = 1.5
		minion["level"] = int(u.get("level", 1))
		minion["active_skills"] = _resolve_active_skills(pick, false)   # 带自己技能(默认3选1·resolve为1个active)
		minion["skill_cd"] = {}                                         # 施法需(防u["skill_cd"][stype]崩)
		minion["skill_gcd_until"] = 0.0
		_recalc_stats(minion)

# 海盗船·技能三(封板L379): 首次充能满召唤实体船→冲锋撞目标(第一敌200码1.0A魔法+击飞2秒)→留场; 船=HP1.5×/ATK1.0×/无双抗/攻速0.8射程300/普攻射最近敌0.4A
func _sk_pirate_ship(u: Dictionary, tgt) -> void:
	if not u.get("ship_summoned", false):
		u["ship_summoned"] = true
		_spawn_pirate_ship(u, tgt)                          # 首次: 召唤船+冲锋撞
	else:
		_pirate_shotgun(u, tgt)                             # 后续: 海盗龟放霰弹

# 海盗龟·霰弹(封板L361·选海盗船后续充能满): 朝目标60度扇面喷8颗弹丸·每颗命中方向第一敌0.5A物理+40码击退·射程400
func _pirate_shotgun(u: Dictionary, tgt) -> void:
	var aim = tgt if (tgt != null and tgt.get("alive", false)) else _nearest_enemy(u)
	if aim == null:
		return
	var base_dir: Vector2 = aim["pos"] - u["pos"]
	if base_dir.length() < 1.0:
		base_dir = Vector2.RIGHT
	base_dir = base_dir.normalized()
	_muzzle_flash(u["pos"], base_dir, Color("#ffd9a0"))
	_skill_ring(u["pos"] + base_dir * 22.0, Color(1.0, 0.82, 0.4, 0.7), 26.0)
	var half: float = deg_to_rad(30.0)                      # 60度扇面=±30度
	for i in range(8):
		var frac: float = (float(i) / 7.0) * 2.0 - 1.0      # -1..1 均分
		var d: Vector2 = base_dir.rotated(half * frac)
		_shotgun_pellet(u["pos"], u["pos"] + d * 400.0, Color(1.0, 0.86, 0.5, 0.95))   # 弹丸VFX(射程400)
		var hit = _basic_first_blocker(u, d)                # 该方向路径第一敌(含蛋·障碍穿我方不挡)
		if hit != null and hit["pos"].distance_to(u["pos"]) <= 400.0:
			_apply_damage_from(u, hit, _atk_dmg(u, 0.5, hit), Color("#ffd07a"))   # 0.5A物理
			var pd: Vector2 = (hit["pos"] - u["pos"]).normalized()               # 40码轻击退(不用_knockback避免8连击飞震屏)
			hit["pos"] += pd * 40.0
			hit["pos"].x = clampf(hit["pos"].x, ARENA.position.x, ARENA.end.x)
			hit["pos"].y = clampf(hit["pos"].y, ARENA.position.y, ARENA.end.y)
			_hit_spark(hit)

func _spawn_pirate_ship(u: Dictionary, tgt = null) -> void:
	var ship = _spawn_summon(u, "ship", u["maxHp"] * 1.5, u["atk"], {
		"label": "海盗船", "col_size": 38.0, "hp_w": 44.0, "melee": false,
		"move_spd": 120.0, "atk_range": 300.0, "no_basic": true,                # 射程300(封板)
		"special": "ship_shot", "special_cd": 1.25, "special_scale": 0.4,       # 攻速0.8≈1.25s/发·普攻射最近敌0.4A(封板L379)
	})
	if ship == null:
		return
	# 登场冲锋直撞目标: 冲到目标→第一个敌200码1.0A魔法+击飞2秒(封板)
	var aim = tgt if (tgt != null and tgt.get("alive", false)) else _nearest_enemy(u)
	if aim == null:
		return
	ship["pos"] = u["pos"]
	_dash_to(ship, aim, 40.0)                               # 冲锋切入
	for e in _enemies_of(ship):
		if not e.get("alive", false): continue
		if e["pos"].distance_to(aim["pos"]) > 200.0: continue
		_apply_damage_from(ship, e, _atk_dmg(ship, 1.0, e, true), Color("#e8c07a"), 0.0, true)   # 1.0A魔法
		_knockback(ship, e, 40.0, 3.667, 1.0)                                   # 击飞2.0秒滞空(vy_mult=3.667·用户2026-07-07"2秒击飞"·原1.0只有0.55秒)
		e["stun_until"] = maxf(float(e.get("stun_until", 0.0)), _t + _cc_dur(e, 2.0))            # 击飞2秒
	_skill_ring(aim["pos"], Color(0.9, 0.7, 0.4, 0.6), 200.0)
	_shake(JUICE_SHAKE_HEAVY)

# 赛博龟阵亡 → 浮游炮全部组装成机甲 (独立单位)
func _cyber_assemble_mech(u: Dictionary) -> void:
	var drones: Array = []
	for o in _units:
		if o.get("is_summon", false) and o["alive"] and o.get("summon_owner", null) == u and o.get("summon_kind", "") == "drone":
			drones.append(o)
	if drones.is_empty():
		return
	var n: int = drones.size()
	var mech_hp: float = u["maxHp"] * 0.5 + 200.0 * HP_MULT * n
	var mech_atk: float = u["base_atk"] * (0.6 + 0.25 * n)
	for d in drones:
		mech_hp += d["hp"]
		d["alive"] = false
		_hide_summon_nodes(d)
	var mech = _spawn_summon(u, "mech", mech_hp, mech_atk, {
		"label": "机甲", "spr_id": "mech", "col_size": 40.0, "hp_w": 46.0, "melee": false,
		"move_spd": 130.0, "atk_interval": 1.0, "atk_range": 320.0,
		"special": "mech_blast", "special_cd": 2.5, "special_scale": 1.5,
	})
	if mech != null:
		mech["pos"] = u["pos"]
		_skill_ring(u["pos"], Color(0.5, 0.9, 1.0, 0.6), 80.0)

# 召唤独立单位 — 3D 版: billboard 立绘(有 spr_id) 或彩色 billboard + blob影 + 血条 overlay. 走同一 tick.
func _spawn_summon(owner: Dictionary, kind: String, hp: float, atk: float, behavior: Dictionary = {}):
	var pos: Vector2 = owner["pos"] + Vector2(randf_range(-40, 40), randf_range(30, 60))
	pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)
	pos.y = clampf(pos.y, ARENA.position.y, ARENA.end.y)
	var col := Color("#3fa9ff") if owner["side"] == "left" else Color("#ff5a5a")
	var spr_id: String = str(behavior.get("spr_id", ""))
	var col_size: float = float(behavior.get("col_size", 22.0))

	# --- 立绘/色块 billboard ---
	var spr := Sprite3D.new()
	spr.name = "Summon_" + kind
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var su_sd: Dictionary = _resolve_summon_sprite(spr_id)
	var tex: Texture2D = su_sd.get("tex", null)
	var su_grounded: ShaderMaterial = null
	if tex != null:
		var fh: int = int(su_sd.get("frame_h", tex.get_height()))
		# 召唤体按 col_size 缩放 (相对全身龟略小): 帧高归一到 ~col_size*WS 的世界高
		spr.texture = tex
		spr.hframes = int(su_sd.get("hframes", 1))
		spr.vframes = int(su_sd.get("vframes", 1))
		spr.frame = 0
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED    # 接地 shader 自管 alpha (软渐隐), 不硬切
		spr.pixel_size = (TARGET_BODY_H * (col_size / 56.0)) / float(maxi(1, fh))
		spr.offset = Vector2(0.0, fh * 0.5)
		su_grounded = _make_grounded_material(tex, su_sd)   # §GROUNDING 软渐隐 (动画召唤体)
		spr.material_override = su_grounded
	else:
		spr.texture = _make_fire_glow_tex()                  # 无专属立绘: 软发光球(队色)替硬色块 — 不留 ColorRect 占位感
		spr.modulate = Color(col.r, col.g, col.b, 0.95)
		spr.pixel_size = (col_size * 1.4 * WS) / 96.0
		spr.offset = Vector2(0.0, 30.0)
	spr.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(spr)

	# --- blob 暗影 ---
	var shadow := Sprite3D.new()
	shadow.texture = _make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.008
	shadow.shaded = false
	shadow.transparent = true
	shadow.modulate = Color(1, 1, 1, SHADOW_BASE_A)
	shadow.scale = SHADOW_BASE * 0.6
	shadow.position = _world_pos(pos, 0.02)
	_world.add_child(shadow)

	# --- HP overlay (召唤体只有血条, 无等级牌) ---
	var bar := _make_status_bar(owner["side"], 0)
	bar["en"].visible = false
	_ui_layer.add_child(bar["root"])

	var hp_w: float = float(behavior.get("hp_w", 28.0))
	var su := {
		"id": "_summon_" + kind, "name": str(behavior.get("label", kind)), "rarity": "C", "side": owner["side"],
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": atk, "def": 0.0, "mr": 0.0, "base_atk": atk, "base_def": 0.0, "base_mr": 0.0,
		"crit": float(behavior.get("crit", 0.0)), "crit_dmg": 1.5, "lifesteal": 0.0,
		"armor_pen": 0.0, "armor_pen_pct": 0.0, "magic_pen": 0.0, "magic_pen_pct": 0.0,
		"heal_amp": 0.0, "shield_amp": 0.0, "damage_reduction": 0.0, "damage_amp": 0.0, "reflect": 0.0, "tenacity": 0.0,
		"melee": bool(behavior.get("melee", kind != "drone")),
		"move_spd": float(behavior.get("move_spd", 0.0 if behavior.get("no_move", false) else 120.0)),
		"atk_interval": float(behavior.get("atk_interval", 1.2)),
		"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else 70.0)),
		"atk_cd": 0.0, "energy": 0.0, "alive": true, "is_summon": true,
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0,
		"buffs": [], "dots": [], "taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0, "summons": [],
		# 召唤 AI 行为字段 ----
		"summon_kind": kind, "summon_owner": owner, "hp_w": hp_w,
		"no_basic": bool(behavior.get("no_basic", false)),
		"no_move": bool(behavior.get("no_move", false)),
		"summon_special": str(behavior.get("special", "")),
		"special_cd": float(behavior.get("special_cd", 0.0)),
		"special_timer": 0.0,
		"special_scale": float(behavior.get("special_scale", 1.0)),
		"death_aoe": float(behavior.get("death_aoe", 0.0)),
		"self_decay": float(behavior.get("self_decay", 0.0)),
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": null, "shadow_base_scale": SHADOW_BASE * 0.6,
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"], "level_badge": bar.get("level_badge", null),
		"spr_base_offy": spr.offset.y,
		# 立绘动画态 (召唤体若有 sheet 也循环 idle) ----
		"grounded_mat": su_grounded,
		"idle_sd": su_sd, "idle_px": spr.pixel_size, "idle_offy": spr.offset.y,
		"anim_t": 0.0, "anim_sd": su_sd, "anim_action": "",
		# Phase4 juice 态 (召唤体同享 squash/闪白/bob) ----
		"spr_base_scale": spr.scale,
		"flash_t": 0.0, "hitsq_t": 0.0, "land_t": 0.0, "swing_t": 0.0, "windup_t": 0.0,
		"bob_phase": randf() * TAU,
	}
	_units.append(su)
	return su

func _hide_summon_nodes(u: Dictionary) -> void:
	for key in ["sprite", "shadow", "ring"]:
		var n = u.get(key, null)
		if is_instance_valid(n):
			n.hide()
	if is_instance_valid(u.get("bar_root", null)):
		u["bar_root"].visible = false

# 召唤体周期特殊技 + 自损 (1:1 搬自 2D 版)
func _tick_summon_special(u: Dictionary, delta: float) -> void:
	if u.get("self_decay", 0.0) > 0.0:
		_raw_lose(u, u["maxHp"] * u["self_decay"] * delta)
		if not u["alive"]:
			return
	if u.get("summon_life", 0.0) > 0.0:                   # 032骷髅: 存活到期→自灭(触发死亡爆炸)
		u["summon_life"] = float(u["summon_life"]) - delta
		if u["summon_life"] <= 0.0:
			u["summon_life"] = 0.0
			_kill(u, null)
			return
	if u.get("worm_split", false):                        # 033复活海螺3★: 小虫每2.5s在空位分裂一只(自身周期, 非携带者eq_tick)
		u["worm_split_t"] = float(u.get("worm_split_t", 0.0)) + delta
		if u["worm_split_t"] >= 2.5:
			if _count_summons(u["side"], "worm") < 4:
				u["worm_split_t"] = 0.0
				var nw = _spawn_summon(u, "worm", u["maxHp"], u["atk"], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
				if nw != null:
					nw["eq_state"] = {}; nw["equips"] = []; nw["worm_split"] = true; nw["atk_interval"] = 1.0 / 0.65
					_conch_transform(nw["pos"])
			else:
				u["worm_split_t"] = 2.5                    # 满4只: 等空位再分裂
	var special: String = u.get("summon_special", "")
	if special == "" or u.get("special_cd", 0.0) <= 0.0:
		return
	u["special_timer"] = u.get("special_timer", 0.0) + delta
	if u["special_timer"] < u["special_cd"]:
		return
	u["special_timer"] = 0.0
	var owner = u.get("summon_owner", u)
	if owner == null or not owner.get("alive", false):
		owner = u
	match special:
		"cannon":
			var es := _enemies_of(u)
			if es.is_empty(): return
			var o = es[randi() % es.size()]
			_fire_bolt_from(u, o, _atk_dmg(u, u.get("special_scale", 0.2), o), Color("#ffb05c"))
			_skill_ring(o["pos"], Color(1.0, 0.6, 0.2, 0.45), 40.0)
		"ship_shot":                                          # 海盗船普攻: 射最近敌0.4A(封板L379·攻速0.8由special_cd驱动)
			var st = _nearest_enemy(u)
			if st == null: return
			_muzzle_flash(u["pos"], (st["pos"] - u["pos"]).normalized(), Color("#ffd9a0"))
			_fire_bolt_from(u, st, _atk_dmg(u, u.get("special_scale", 0.4), st), Color("#e8c07a"))
		"ray":
			var t = _nearest_enemy(u)
			if t == null: return
			_bolt_line(u["pos"], t["pos"], Color("#c9b0ff"))
			for i in range(2):
				if not t["alive"]: break
				_apply_damage_from(u, t, _atk_dmg(u, u.get("special_scale", 1.0), t, true), Color("#c9b0ff"), 0.0, true)
			_crystal_stack(u, t, 2)   # 水晶球每发叠2层结晶(封板)·与本体共享满5引爆(引爆改吃魔抗)
		"random_hit":
			var es2 := _enemies_of(u)
			if es2.is_empty(): return
			var o2 = es2[randi() % es2.size()]
			_fire_bolt_from(u, o2, _atk_dmg(u, u.get("special_scale", 0.25), o2), Color("#9bf0ff"))
		"mech_blast":
			var low = null; var lv := INF
			for o in _enemies_of(u):
				if o["hp"] < lv: lv = o["hp"]; low = o
			if low == null: return
			_bolt_line(u["pos"], low["pos"], Color("#9bf0ff"))
			for i in range(2):
				if not low["alive"]: break
				_apply_damage_from(u, low, _atk_dmg(u, u.get("special_scale", 1.5) * 0.5, low), Color("#9bf0ff"))

# 纯色块贴图 (召唤体占位, 无立绘时)
func _make_block_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, col)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64; gt.height = 64
	return gt

# ============================================================================
#  每帧: 3D 节点世界坐标更新 (XZ + 高度) + 影/环随高缩放淡 + Phase4 squash/闪白/bob
# ============================================================================
func _update_world_transforms() -> void:
	for u in _units:
		if not u["alive"]:
			continue
		var spr: Sprite3D = u["sprite"]
		var shadow: Sprite3D = u["shadow"]
		var ring: Sprite3D = u["ring"]
		if not is_instance_valid(spr):
			continue
		# 朝向: 有战斗目标→由_tick_unit锁定朝敌(死区防抖); 无目标→才随移动方向(立绘默认朝左→flip_h=true朝右); 初始左队朝右/右队朝左
		var _px: float = u["pos"].x
		var _dx: float = _px - float(u.get("last_x", _px))
		if not bool(u.get("_has_target", false)) and absf(_dx) > 0.3:
			u["face_right"] = _dx > 0.0
		u["last_x"] = _px
		spr.flip_h = bool(u.get("face_right", str(u["side"]) == "left"))
		# --- Phase4: squash/stretch 形变 + idle bob 高度微浮 (全从 base 起算, 不累积) ---
		var sq := _juice_scale_for(u)              # (sx, sy) 形变系数 (base=1,1)
		var bob := _juice_bob_for(u)               # idle 呼吸 Y 偏移 (米)
		# 立绘: XZ + Y(高度 + 落地基线抬升 + bob). billboard 自动朝镜头, 不翻 facing.
		spr.position = _world_pos(u["pos"], u["height"] + GROUND_LIFT + bob) + u.get("_bear_voff", Vector3.ZERO) + u.get("_atk_voff", Vector3.ZERO) + u.get("_slam_voff", Vector3.ZERO)   # 大熊扑击/砸地 + 近战踏步lunge + 过肩摔起跳(#7)
		var bs: Vector3 = u.get("spr_base_scale", Vector3.ONE)
		var gm: float = float(u.get("size_mult", 1.0))   # 体型倍率(石头岩层+2%/层); 从base起算不累积
		spr.scale = Vector3(bs.x * sq.x * gm, bs.y * sq.y * gm, bs.z)
		# 受击闪白: modulate 由 base 白 → 过曝白线性插值 (flash_t/JUICE_FLASH_SEC); 死亡淡出走 alpha 不冲突
		var fl: float = clampf(u.get("flash_t", 0.0) / JUICE_FLASH_SEC, 0.0, 1.0)
		spr.modulate = Color.WHITE.lerp(u.get("flash_col", JUICE_FLASH_COLOR), fl)
		# 影/环: 跟 XZ 不跟 Y (贴地), 随高度缩小变淡 (从各自基准 scale 起算, 召唤体影更小)
		var s: float = 1.0 - clampf(u["height"] / 3.0, 0.0, 0.7)
		if is_instance_valid(shadow):
			var base_sc: Vector3 = u.get("shadow_base_scale", SHADOW_BASE)
			shadow.position = _world_pos(u["pos"], 0.02)
			# 影也随 squash 横向张缩 (压扁→影变宽, 拉长→影变窄) 加重量感
			shadow.scale = Vector3(base_sc.x * s * sq.x * gm, base_sc.y * s * gm, base_sc.z * s)   # 影随体型一起涨
			shadow.modulate.a = SHADOW_BASE_A * s
		# 接触核影: 紧贴脚下, 离地越高越快淡出(腾空=脚离地, 核影该消失) → 强化"踩地"
		var contact = u.get("contact", null)
		if is_instance_valid(contact):
			var cbase: Vector3 = u.get("contact_base_scale", CONTACT_BASE)
			var cs: float = 1.0 - clampf(u["height"] / 1.2, 0.0, 1.0)   # 比外影更快随高度收
			contact.position = _world_pos(u["pos"], 0.028)
			contact.scale = Vector3(cbase.x * cs * sq.x, cbase.y * cs, cbase.z * cs)
			contact.modulate.a = 0.0   # 隐藏接触核影(用户"只留影子")
		if is_instance_valid(ring):
			ring.position = _world_pos(u["pos"], 0.015)

# ============================================================================
#  §JUICE — Phase4 商业级打击感 (squash&stretch / 闪白 / 顿帧 / 震屏 / idle bob / 粒子)
#  统一态机: 触发函数只置"剩余秒"字段, 每帧 _juice_decay 自减, 视觉由 _juice_scale_for/
#  _juice_bob_for + _update_world_transforms 重建 → 复原干净(scale/modulate 都回 base, 无漂移).
# ============================================================================

# 每帧衰减各单位 juice 计时 (hit-stop 冻结期不调 → 冲击姿势保持)
func _juice_decay(delta: float) -> void:
	var ts_on: bool = not _ts_active.is_empty()
	for u in _units:
		if not u["alive"]:
			continue
		if ts_on and not _ts_active.has(u):
			continue   # 时停: 非active的juice计时不衰 → 冲击/挥击姿势定格
		if u.get("flash_t", 0.0) > 0.0:  u["flash_t"]  = maxf(0.0, u["flash_t"]  - delta)
		if u.get("hitsq_t", 0.0) > 0.0:  u["hitsq_t"]  = maxf(0.0, u["hitsq_t"]  - delta)
		if u.get("land_t", 0.0) > 0.0:   u["land_t"]   = maxf(0.0, u["land_t"]   - delta)
		if u.get("swing_t", 0.0) > 0.0:  u["swing_t"]  = maxf(0.0, u["swing_t"]  - delta)
		if u.get("windup_t", 0.0) > 0.0: u["windup_t"] = maxf(0.0, u["windup_t"] - delta)
		# 近战踏步: _lunge_t 递减 → _atk_voff = 方向×sin(0→π)幅度(前冲再回), render叠加
		if u.get("_lunge_t", 0.0) > 0.0:
			u["_lunge_t"] = maxf(0.0, u["_lunge_t"] - delta)
			var _ld: float = maxf(0.001, float(u.get("_lunge_dur", ATK_LUNGE_MIN)))
			var _lp: float = 1.0 - float(u["_lunge_t"]) / _ld   # 0→1
			u["_atk_voff"] = u.get("_lunge_dir", Vector3.ZERO) * (sin(_lp * PI) * float(u.get("_lunge_amp", ATK_LUNGE_AMP)))
			if u["_lunge_t"] <= 0.0: u["_lunge_amp"] = ATK_LUNGE_AMP   # 踏步结束→幅度复位(强化发的加大踏步用完即还原)
		elif u.get("_atk_voff", Vector3.ZERO) != Vector3.ZERO:
			u["_atk_voff"] = Vector3.ZERO

# 合成形变系数 (x,y): 优先级 起跳拉长 > 落地压扁 > 受击压扁 > 出招预备(缩)/挥出(伸).
# 各相位用 ease 衰减到 (1,1), 互不累积 — 取主导相位 + 出招缩放叠乘.
func _juice_scale_for(u: Dictionary) -> Vector2:
	var sx := 1.0
	var sy := 1.0
	# 击飞中: 起跳上行拉长, 下落渐回 (随竖速 vy 符号/大小)
	if u.get("airborne", false):
		var vy: float = u.get("vy", 0.0)
		var k: float = clampf(absf(vy) / KNOCK_VY, 0.0, 1.0)
		if vy > 0.0:    # 上升: 拉长
			sx = lerpf(1.0, JUICE_STRETCH_UP.x, k)
			sy = lerpf(1.0, JUICE_STRETCH_UP.y, k)
		else:           # 下落: 轻微拉长(惯性), 落地瞬间由 land_t 接管压扁
			sx = lerpf(1.0, lerpf(1.0, JUICE_STRETCH_UP.x, 0.5), k)
			sy = lerpf(1.0, lerpf(1.0, JUICE_STRETCH_UP.y, 0.5), k)
		return Vector2(sx, sy)
	# 落地压扁 (ease-out 回弹)
	var lt: float = u.get("land_t", 0.0)
	if lt > 0.0:
		var f: float = lt / JUICE_LAND_SEC          # 1→0
		var e: float = f * f                          # ease (回弹快)
		sx = lerpf(1.0, JUICE_SQUASH_LAND.x, e)
		sy = lerpf(1.0, JUICE_SQUASH_LAND.y, e)
		return Vector2(sx, sy)
	# 受击压扁
	var ht: float = u.get("hitsq_t", 0.0)
	if ht > 0.0:
		var f2: float = ht / JUICE_HIT_SQUASH_SEC
		var e2: float = f2 * f2
		sx = lerpf(1.0, JUICE_HIT_SQUASH.x, e2)
		sy = lerpf(1.0, JUICE_HIT_SQUASH.y, e2)
	# 出招: 预备(整体缩) → 挥出(整体伸), 顺序非叠加 (windup 在前, 结束后 swing 接管)
	var wt: float = u.get("windup_t", 0.0)
	var st: float = u.get("swing_t", 0.0)
	if wt > 0.0:
		var fw: float = wt / JUICE_WINDUP_SEC        # 1→0
		var m: float = lerpf(1.0, JUICE_WINDUP_SCALE, fw)
		sx *= m; sy *= m
	elif st > 0.0:
		var fs: float = clampf(st / JUICE_SWING_SEC, 0.0, 1.0)   # swing 段 (windup 已耗尽)
		var m2: float = lerpf(1.0, JUICE_SWING_SCALE, fs)
		sx *= m2; sy *= m2
	return Vector2(sx, sy)

# idle 呼吸 bob: 仅待机时(不击飞/不快移/无 juice 相位) 立绘极轻上下浮
func _juice_bob_for(u: Dictionary) -> float:
	if u.get("airborne", false):
		return 0.0
	# 移动中不 bob (vel 速度阈值: 像素/s)
	var v: Vector2 = u.get("vel", Vector2.ZERO)
	if v.length() > 6.0:
		return 0.0
	# 出招/受击/落地相位中不 bob (避免叠加抖)
	if u.get("land_t", 0.0) > 0.0 or u.get("hitsq_t", 0.0) > 0.0 or u.get("swing_t", 0.0) > 0.0 or u.get("windup_t", 0.0) > 0.0:
		return 0.0
	var ph: float = u.get("bob_phase", 0.0) + _t * JUICE_BOB_SPEED
	return sin(ph) * JUICE_BOB_AMP

# 震屏每帧推进: 衰减幅度 + 伪随机偏移镜头, 归零时精确复位到 _cam_base
func _update_camera_shake(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	if _shake_amp <= 0.0001:
		_shake_amp = 0.0
		_cam.position = _cam_base
		return
	_shake_t += delta
	_shake_amp = _shake_amp * exp(-JUICE_SHAKE_DECAY * delta)   # 指数衰减
	# 伪随机偏移 (sin/cos 不同频 → 不规则); 横/竖各一份, 不动深度 z
	var ox: float = sin(_shake_t * JUICE_SHAKE_FREQ * TAU) * _shake_amp
	var oy: float = cos(_shake_t * JUICE_SHAKE_FREQ * 0.81 * TAU + 1.3) * _shake_amp
	_cam.position = _cam_base + Vector3(ox, oy, 0.0)

# 触发震屏: 取较大幅度叠加(封顶), 重置相位让新事件抖得明显
func _shake(amp: float) -> void:
	if amp <= 0.0:
		return
	_shake_amp = minf(JUICE_SHAKE_MAX, maxf(_shake_amp, amp))
	_shake_t = 0.0

# 触发顿帧: 取较大值 (短事件不覆盖更长的卡顿)
func _add_hitstop(sec: float) -> void:
	if sec > _hitstop:
		_hitstop = sec

# 受击闪白 + 轻压扁 (Phase4 替代旧 _flash; 状态驱动, 不叠 tween)
func _flash(u: Dictionary, col: Color = JUICE_FLASH_COLOR) -> void:
	if u == null or not u.get("alive", false):
		return
	u["flash_t"] = JUICE_FLASH_SEC
	u["flash_col"] = col            # 受击闪光色 (默认过曝白; 可传绿等特殊色)
	u["hitsq_t"] = JUICE_HIT_SQUASH_SEC
	# ★E1 黑屏排查(用户2026-07-11「按理压根不该用受伤动画」): 实时高频命中下, 受击帧动画会反复打断
	#   idle/攻击动画 → 动画状态抖动。改为只保留闪白+压扁(juice), 不再切 hurt 动画帧。
	# _play_action(u, "hurt")   # 已停用: 受击 flinch 动画在实时战斗里反复冲突

# 命中重量分级: 单段伤害(或暴击/大招标志)决定 闪白/顿帧/震屏/粒子 强度.
# heavy=技能/暴击命中级; big=大招/击飞级. light(普攻小段)只闪白不顿帧不抖.
func _impact(tgt: Dictionary, dmg: int, level: String = "auto", at_pos = null) -> void:
	if tgt == null:
		return
	var lvl := level
	if lvl == "auto":
		lvl = "heavy" if float(dmg) >= JUICE_HITSTOP_DMG_GATE else "light"
	match lvl:
		"big":
			_add_hitstop(JUICE_HITSTOP_HEAVY)
			_shake(JUICE_SHAKE_BIG)
		"heavy":
			_add_hitstop(JUICE_HITSTOP_HEAVY)
			_shake(JUICE_SHAKE_HEAVY)
		_:   # light
			if JUICE_HITSTOP_LIGHT > 0.0: _add_hitstop(JUICE_HITSTOP_LIGHT)
			if JUICE_SHAKE_LIGHT > 0.0:   _shake(JUICE_SHAKE_LIGHT)
	# 命中特效 (Botworld式: 普攻不打断敌人, 反馈全靠特效) — 每次命中迸 Hit Spark + Impact Ring
	_hit_spark(tgt, at_pos)
	# 冲击粒子: 只在重击/大招迸火花
	if (lvl == "heavy" or lvl == "big") and float(dmg) >= JUICE_PARTICLE_MIN_DMG:
		var p2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
		_impact_particles(p2d, tgt.get("height", 0.0))

# Hit Spark(亮星) + Impact Ring(快环): 朝镜头 billboard, ~0.14s pop→淡; 同目标50ms节流防多段刷爆
var _hitring_tex: ImageTexture = null
var _spark_tex: ImageTexture = null   # #6修: 命中辉光改 Image 真圆(原 GradientTexture2D 露方角)
var _reticle_tex: ImageTexture = null     # 瞄准准星(圆环+四刻线) — 瞄准镜054一瞬瞄准闪专用
var _bracket_tex: ImageTexture = null      # 目标锁定角标([ ]四角方括号) — 持续标记专用(靶向器055/飞镖056), 跟054准星区分
var _pellet_tex: ImageTexture = null       # 小圆铅丸(霰弹弹珠) — 真圆非方角
func _hit_spark(tgt, at_pos = null) -> void:
	if tgt == null or _t < float(tgt.get("_spark_t", 0.0)):
		return
	tgt["_spark_t"] = _t + 0.05
	var pos2d: Vector2 = at_pos if at_pos != null else tgt.get("pos", Vector2.ZERO)
	var h: float = float(tgt.get("height", 0.0)) + 0.6
	if _hitring_tex == null:
		_hitring_tex = _make_ring_texture(Color(1, 1, 1, 1))
	var r := Sprite3D.new()
	r.texture = _hitring_tex
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.modulate = Color(1.0, 0.96, 0.8, 0.95)
	r.position = _world_pos(pos2d, h)
	r.pixel_size = 0.006
	_world.add_child(r)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", 0.018, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(r.queue_free)
	if _spark_tex == null:
		_spark_tex = _make_glow_texture()
	var sp := Sprite3D.new()
	sp.texture = _spark_tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(1.0, 1.0, 0.85, 0.9)
	sp.position = _world_pos(pos2d, h)
	sp.pixel_size = 0.012
	sp.scale = Vector3.ONE * 0.5
	_world.add_child(sp)
	var tw2 := _reg_tween(); tw2.set_parallel(true)
	tw2.tween_property(sp, "scale", Vector3.ONE * 1.1, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(sp, "modulate:a", 0.0, 0.12)
	tw2.chain().tween_callback(sp.queue_free)

# 瞄准/锁定框贴图: 圆环 + 上下左右四刻线(跨圈), 中心留空(不挡脸)
func _make_reticle_texture(col: Color) -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(S - 1) / 2.0
	var R := c - 5.0
	for y in range(S):
		for x in range(S):
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if absf(d - R) < 1.8:
				a = 1.0                                                      # 外圈
			if absf(dx) < 1.6 and absf(absf(dy) - R) < 6.0:
				a = maxf(a, 1.0)                                             # 上下竖刻线
			if absf(dy) < 1.6 and absf(absf(dx) - R) < 6.0:
				a = maxf(a, 1.0)                                             # 左右横刻线
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

# 目标锁定角标([ ]四角方括号) — 持续标记(靶向器055/飞镖056)专用, 视觉区别于054十字准星圆环
func _make_target_bracket_texture(col: Color) -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lo := 9.0
	var hi := float(S) - 9.0
	var arm := 16.0     # 每角短臂长
	var th := 2.4       # 半线宽
	for y in range(S):
		for x in range(S):
			var fx := float(x); var fy := float(y)
			var on := false
			for cx in [lo, hi]:
				for cy in [lo, hi]:
					var hx0: float = cx if cx == lo else cx - arm
					var hx1: float = cx + arm if cx == lo else cx
					if absf(fy - cy) < th and fx >= hx0 - th and fx <= hx1 + th:
						on = true              # 横臂
					var vy0: float = cy if cy == lo else cy - arm
					var vy1: float = cy + arm if cy == lo else cy
					if absf(fx - cx) < th and fy >= vy0 - th and fy <= vy1 + th:
						on = true              # 竖臂
			if on:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))
	return ImageTexture.create_from_image(img)

# 一瞬锁定框: 从大缩到目标身上再淡出(瞄准镜"必中"命中反馈)
func _reticle_flash(tgt: Dictionary, col: Color) -> void:
	if tgt == null: return
	if _reticle_tex == null: _reticle_tex = _make_reticle_texture(Color(1, 1, 1, 1))
	var r := Sprite3D.new()
	r.texture = _reticle_tex
	r.modulate = Color(col.r, col.g, col.b, 0.0)
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.pixel_size = 0.032
	r.position = _world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.9)
	_world.add_child(r)
	var tw := _reg_tween(); tw.set_parallel(true)   # 淡入+缩到目标(并行0.14) → 停留0.24锁定感 → 淡出0.14, 共~0.52s(用户2026-07-04要0.5s)
	tw.tween_property(r, "modulate:a", 0.95, 0.06)
	tw.tween_property(r, "pixel_size", 0.016, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.24)
	tw.chain().tween_property(r, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(r.queue_free)

# 持续锁定标记: 贴在目标身上脉动的锁定框, 到 _mark_until 自动消失(靶向器5s/飞镖靶子). 去重: 已有则延长
func _mark_vfx(tgt: Dictionary, dur: float, col: Color) -> void:
	if tgt == null: return
	tgt["_mark_until"] = _t + dur
	var ex = tgt.get("_mark_spr", null)
	if ex != null and is_instance_valid(ex):
		return
	if _bracket_tex == null: _bracket_tex = _make_target_bracket_texture(Color(1, 1, 1, 1))
	var r := Sprite3D.new()
	r.texture = _bracket_tex
	r.modulate = Color(col.r, col.g, col.b, 0.85)
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.pixel_size = 0.02
	r.position = _world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.9)
	_world.add_child(r)
	tgt["_mark_spr"] = r
	_follow_vfx.append({"spr": r, "unit": tgt, "h": 0.9, "mark": true})
	var pt := _reg_tween().bind_node(r).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	pt.tween_property(r, "modulate:a", 0.35, 0.5).from(0.85)
	pt.tween_property(r, "modulate:a", 0.85, 0.5)

# 治疗迸发: 绿治疗环扩散 + 几粒上升绿光 (救命回血044/045/竹弓039/大回复用). scale 越大越盛
func _heal_burst(u: Dictionary, scale: float = 1.0) -> void:
	if u == null: return
	_skill_ring(u["pos"], Color(0.45, 1.0, 0.55, 0.6), 58.0 * scale)
	if _spark_tex == null: _spark_tex = _make_glow_texture()
	for k in range(int(4 * scale) + 2):
		var sp := Sprite3D.new()
		sp.texture = _spark_tex
		sp.modulate = Color(0.5, 1.0, 0.62, 0.9)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.009
		var off := Vector2(randf_range(-28.0, 28.0), 0.0)
		sp.position = _world_pos(u["pos"] + off, 0.2)
		_world.add_child(sp)
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(sp, "position", _world_pos(u["pos"] + off, 1.5 + randf_range(0.0, 0.5)), 0.6)
		tw.tween_property(sp, "modulate:a", 0.0, 0.6)
		tw.chain().tween_callback(sp.queue_free)

# 上半身绿光脉动(深海项链044救命回血, 用户: 就龟上半身一个绿光动画): 龟身染绿脉动2下 + 绿辉裹上半身 + 几缕上升绿光
func _heal_body_glow(u: Dictionary) -> void:
	if u == null: return
	var spr = u.get("sprite", null)   # ① 龟精灵本体染绿脉动2下(最直接的"龟身绿光")
	if spr != null and is_instance_valid(spr):
		var basem: Color = spr.modulate
		var mt := _reg_tween()
		mt.tween_property(spr, "modulate", Color(0.5, 1.55, 0.65, basem.a), 0.14)
		mt.tween_property(spr, "modulate", basem, 0.2)
		mt.tween_property(spr, "modulate", Color(0.5, 1.55, 0.65, basem.a), 0.14)
		mt.tween_property(spr, "modulate", basem, 0.34)
	var tex := _make_fire_glow_tex()   # ② 上半身绿辉光overlay(裹住脉动)
	var g := Sprite3D.new()
	g.texture = tex
	g.modulate = Color(0.45, 1.0, 0.55, 0.0)
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.render_priority = 8
	g.pixel_size = 2.0 / float(maxi(1, tex.get_width()))   # ~2m裹上半身
	g.position = _world_pos(u["pos"], 1.2)
	_world.add_child(g)
	_follow_vfx.append({"spr": g, "unit": u, "h": 1.2})
	var tw := _reg_tween()
	tw.tween_property(g, "modulate:a", 0.95, 0.15)
	tw.tween_property(g, "modulate:a", 0.5, 0.22)
	tw.tween_property(g, "modulate:a", 0.95, 0.22)
	tw.tween_property(g, "modulate:a", 0.0, 0.4)
	tw.tween_callback(g.queue_free)
	if _spark_tex == null: _spark_tex = _make_glow_texture()
	for k in range(4):
		var sp := Sprite3D.new()
		sp.texture = _spark_tex
		sp.modulate = Color(0.55, 1.0, 0.6, 0.9)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.008
		var off := Vector2(randf_range(-26.0, 26.0), 0.0)
		sp.position = _world_pos(u["pos"] + off, 0.5)
		_world.add_child(sp)
		var tw2 := _reg_tween(); tw2.set_parallel(true)
		tw2.tween_property(sp, "position", _world_pos(u["pos"] + off, 1.9 + randf_range(0.0, 0.4)), 0.75)
		tw2.tween_property(sp, "modulate:a", 0.0, 0.75)
		tw2.chain().tween_callback(sp.queue_free)

# 绿光上浮(珍珠耳环045救命回血, 用户: 另做一个绿光不复用): 绿光环从脚下升起穿过龟身上浮 + 绿光粒上升 + 脚下绿环(区别于044龟身染绿)
func _heal_ascend(u: Dictionary) -> void:
	if u == null: return
	_skill_ring(u["pos"], Color(0.4, 1.0, 0.5, 0.6), 56.0)   # 脚下绿光环
	for k in range(3):   # 3道绿光环从脚下升到头顶上方(错峰)
		var r := Sprite3D.new()
		r.texture = _make_ring_texture(Color(0.45, 1.0, 0.55, 1.0))
		r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		r.shaded = false; r.transparent = true
		r.modulate = Color(0.45, 1.0, 0.55, 0.9)
		r.pixel_size = 0.011
		r.position = _world_pos(u["pos"], 0.2)
		_world.add_child(r)
		var d: float = float(k) * 0.13
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(r, "position", _world_pos(u["pos"], 2.9), 0.7).set_delay(d).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "pixel_size", 0.03, 0.7).set_delay(d)
		tw.tween_property(r, "modulate:a", 0.0, 0.7).set_delay(d)
		tw.chain().tween_callback(r.queue_free)
	if _spark_tex == null: _spark_tex = _make_glow_texture()
	for k in range(7):   # 绿光粒上升
		var sp := Sprite3D.new()
		sp.texture = _spark_tex
		sp.modulate = Color(0.55, 1.0, 0.6, 0.95)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.009
		var off := Vector2(randf_range(-30.0, 30.0), 0.0)
		sp.position = _world_pos(u["pos"] + off, 0.3)
		_world.add_child(sp)
		var tw2 := _reg_tween(); tw2.set_parallel(true)
		tw2.tween_property(sp, "position", _world_pos(u["pos"] + off, 2.6 + randf_range(0.0, 0.5)), 0.8)
		tw2.tween_property(sp, "modulate:a", 0.0, 0.8)
		tw2.chain().tween_callback(sp.queue_free)

# 能量护盾罩(幽灵墨鱼046闪避得盾, 用户: 做一个护盾特效): 青蓝护盾罩snap形成罩住龟身+微闪+淡出, 跟龟走
func _shield_dome(u: Dictionary) -> void:
	if u == null: return
	var sd := Sprite3D.new()
	sd.texture = load("res://assets/sprites/vfx/shield-dome.png")
	sd.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sd.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sd.shaded = false; sd.transparent = true
	sd.modulate = Color(1, 1, 1, 0)
	sd.pixel_size = 2.7 / 96.0   # ~2.7m罩住龟
	sd.position = _world_pos(u["pos"], 1.0)
	_world.add_child(sd)
	_follow_vfx.append({"spr": sd, "unit": u, "h": 1.0})
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(sd, "modulate:a", 0.72, 0.08)
	tw.tween_property(sd, "scale", Vector3.ONE, 0.14).from(Vector3.ONE * 1.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(sd, "modulate:a", 0.42, 0.16)
	tw.chain().tween_property(sd, "modulate:a", 0.0, 0.36)
	tw.chain().tween_callback(sd.queue_free)

# 火爆: 落点火色环 + 膨胀火球辉光(火球落地/灼烧爆点)
func _fire_explosion(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(1.0, 0.5, 0.15, 0.7), 55.0)
	var g := _make_fire_glow_tex()
	var sp := Sprite3D.new()
	sp.texture = g
	sp.modulate = Color(1.0, 0.72, 0.32, 0.95)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.pixel_size = (28.0 * WS) / float(maxi(1, g.get_width()))
	sp.position = _world_pos(pos2d, 0.6)
	_world.add_child(sp)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(sp, "pixel_size", sp.pixel_size * 2.2, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(sp.queue_free)

# 抛物线火球(珍珠耳环045): 火辉光从 src 抛向 tgt, 落点火爆+灼烧+真伤(橙). burn=灼烧层
func _spawn_fireball(src: Dictionary, tgt: Dictionary, dmg: int, burn: int) -> void:
	if tgt == null: return
	var g := _make_fire_glow_tex()
	var p := Sprite3D.new()
	p.texture = g
	p.modulate = Color(1.0, 0.66, 0.26, 0.96)
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false; p.transparent = true
	p.pixel_size = (24.0 * WS) / float(maxi(1, g.get_width()))
	var from := _world_pos(src["pos"], 1.0)
	p.position = from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": from, "tgt": tgt, "dmg": dmg, "col": Color("#ff7a33"),
		"src": src, "t": 0.0, "dur": clampf(src["pos"].distance_to(tgt["pos"]) / 600.0, 0.35, 0.7),
		"arc": 2.2, "fireball": true, "fire_burst": burn,
	})

# 竹枝箭(竹弓039): bamboo-arrow 飞向敌, 命中真伤(绿)+冒绿生命球飞回携带者(竹叶龟式)
func _spawn_bamboo_arrow(src: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if tgt == null: return
	var p := Sprite3D.new()
	p.texture = load("res://assets/sprites/vfx/bamboo-arrow.png")
	p.pixel_size = 0.03
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false; p.transparent = true
	var dir2d: Vector2 = tgt["pos"] - src["pos"]
	p.rotation.z = atan2(-dir2d.y * 0.55, dir2d.x)
	var from := _world_pos(src["pos"], 1.0)
	p.position = from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": from, "tgt": tgt, "dmg": dmg, "col": Color("#a8ffb0"),
		"src": src, "t": 0.0, "dur": clampf(src["pos"].distance_to(tgt["pos"]) / 850.0, 0.14, 0.5),
		"bamboo": true,
	})

# 娜美式潮浪(海浪护符043): 朝敌人2D方向的对角潮浪 — 从敌人反方向(身后)400码涌起 → 沿"朝敌人"方向慢速推过全场 → 连续宽浪墙(垂直于行进方向铺开)翻涌 → 命中击飞(用户2026-07-04: 全场横扫+2D对角朝敌)
func _eq_water_wave(u: Dictionary, si: int) -> void:
	var enemies := _enemies_of(u)
	var allies := _allies_of(u)
	var ec: Vector2 = u["pos"] + Vector2(500.0, 0.0)   # 敌人质心(默认右)
	if not enemies.is_empty():
		ec = Vector2.ZERO
		for e in enemies: ec += e["pos"]
		ec /= float(enemies.size())
	var dvec: Vector2 = ec - u["pos"]
	var dir: Vector2 = Vector2.RIGHT if dvec.length() < 1.0 else dvec.normalized()   # 浪行进方向=朝敌人(2D可对角)
	var perp: Vector2 = Vector2(-dir.y, dir.x)          # 浪墙铺开方向(垂直于行进)
	var startc: Vector2 = u["pos"] - dir * 400.0        # 敌人反方向(身后)400码涌起
	var maxfwd: float = 0.0; var pmin: float = INF; var pmax: float = -INF
	for o in allies + enemies:
		maxfwd = maxf(maxfwd, (o["pos"] - startc).dot(dir))       # 沿行进方向最远单位
		var pp: float = (o["pos"] - u["pos"]).dot(perp)           # 沿浪墙方向的跨度
		pmin = minf(pmin, pp); pmax = maxf(pmax, pp)
	if pmin > pmax: pmin = -150.0; pmax = 150.0
	var tdist: float = maxfwd + 320.0                   # 推过最远单位再多320
	var windup: float = 0.5
	var travel: float = 2.0                             # 慢速(用户)
	_anticipate(u)
	_water_charge_windup(u, windup)
	_spawn_tidal_wave(startc, dir, perp, pmin - 75.0, pmax + 75.0, tdist, windup, travel)
	for o in allies:
		var oo: Dictionary = o
		var fwd: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d: float = windup + fwd / tdist * travel
		var fn := func():
			if not oo.get("alive", false): return
			_grant_shield(oo, [40.0, 95.0, 120.0][si])
			oo["base_def"] += [2, 3, 5][si]; oo["base_mr"] += [2, 3, 5][si]; _recalc_stats(oo)
			_water_splash(oo["pos"], true)
		_pending_shots.append({"delay": d, "fn": fn, "src": u})
	for o in enemies:
		var oo2: Dictionary = o
		var fwd2: float = clampf((o["pos"] - startc).dot(dir), 0.0, tdist)
		var d2: float = windup + fwd2 / tdist * travel
		var fn2 := func():
			if not oo2.get("alive", false): return
			_apply_damage_from(u, oo2, _resolve_dmg(u, float([60, 110, 200][si]), oo2, true), Color("#9be7ff"), 0.0, false, true)   # 魔法伤(蓝字)
			oo2["base_def"] = maxf(0.0, oo2["base_def"] - [2, 3, 5][si]); oo2["base_mr"] = maxf(0.0, oo2["base_mr"] - [2, 3, 5][si]); _recalc_stats(oo2)
			_water_splash(oo2["pos"], false)
			_knock_up(oo2, oo2["pos"] - dir * 60.0, 6.5)   # 娜美式击飞: 顺浪方向往前推(非直上)
			_hit_spark(oo2)
		_pending_shots.append({"delay": d2, "fn": fn2, "src": u})

# 潮浪墙: 沿perp(垂直行进)铺一排大浪crest拼成连续宽墙, 整墙从startc沿dir推进tdist; 翻涌帧循环
func _spawn_tidal_wave(startc: Vector2, dir: Vector2, perp: Vector2, p0: float, p1: float, tdist: float, windup: float, travel: float) -> void:
	var use_anim: bool = ResourceLoader.exists("res://assets/sprites/vfx/tidal-wave-anim.png")
	var tex: Texture2D = load("res://assets/sprites/vfx/tidal-wave-anim.png") if use_anim else load("res://assets/sprites/vfx/tidal-wave.png")
	var fh: int = maxi(1, tex.get_height())
	var nf: int = maxi(1, int(tex.get_width() / fh)) if use_anim else 1
	var flip: bool = dir.x > 0.0   # 浪头朝行进方向(水平分量)卷
	var ncrest: int = clampi(int((p1 - p0) / 72.0) + 1, 4, 16)
	for k in range(ncrest):
		var pp: float = lerpf(p0, p1, float(k) / float(maxi(1, ncrest - 1)))
		var cstart: Vector2 = startc + perp * pp        # 该crest沿perp铺开
		var cend: Vector2 = cstart + dir * tdist        # 沿dir推进终点
		var p := Sprite3D.new()
		p.texture = tex
		if use_anim: p.hframes = nf
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		p.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		p.shaded = false; p.transparent = true
		p.pixel_size = 3.4 / float(fh)
		p.flip_h = flip
		p.modulate = Color(1, 1, 1, 0)
		p.position = _world_pos(cstart, 1.45)
		_world.add_child(p)
		if use_anim and nf > 1:
			var at := _reg_tween().bind_node(p).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
			at.tween_property(p, "frame", nf - 1, 0.45).from(0)
		var tw := _reg_tween()
		tw.tween_property(p, "modulate:a", 0.95, windup * 0.8)
		tw.tween_property(p, "position", _world_pos(cend, 1.45), travel).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "modulate:a", 0.0, 0.25)
		tw.tween_callback(p.queue_free)

# 蓄浪前摇: 携带者身前蓝光汇聚膨胀(施法预备)
func _water_charge_windup(u: Dictionary, dur: float) -> void:
	var g := Sprite3D.new()
	var tex := _make_fire_glow_tex()
	g.texture = tex
	g.modulate = Color(0.4, 0.75, 1.0, 0.0)
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.pixel_size = (34.0 * WS) / float(maxi(1, tex.get_width()))
	g.position = _world_pos(u["pos"], 1.0)
	_world.add_child(g)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(g, "modulate:a", 0.9, dur * 0.7)
	tw.tween_property(g, "pixel_size", (78.0 * WS) / float(maxi(1, tex.get_width())), dur)
	tw.chain().tween_property(g, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(g.queue_free)

# 浪打中单位的水花: 蓝水环 + 上溅几滴
func _water_splash(pos2d: Vector2, ally: bool) -> void:
	_skill_ring(pos2d, Color(0.5, 0.92, 1.0, 0.7) if ally else Color(0.4, 0.8, 1.0, 0.75), 48.0)
	if _spark_tex == null: _spark_tex = _make_glow_texture()
	for k in range(4):
		var dp := Sprite3D.new()
		dp.texture = _spark_tex
		dp.modulate = Color(0.6, 0.9, 1.0, 0.9)
		dp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dp.shaded = false; dp.transparent = true
		dp.pixel_size = 0.006
		dp.position = _world_pos(pos2d, 0.4)
		_world.add_child(dp)
		var off := Vector2(randf_range(-26.0, 26.0), 0.0)
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(dp, "position", _world_pos(pos2d + off, 1.3 + randf_range(0.0, 0.4)), 0.4)
		tw.tween_property(dp, "modulate:a", 0.0, 0.4)
		tw.chain().tween_callback(dp.queue_free)

# 出招预备(缩)+挥出(伸): 主动技/普攻前摇后摇 (anticipation + follow-through)
func _anticipate(u: Dictionary) -> void:
	if u == null or not u.get("alive", false):
		return
	u["windup_t"] = JUICE_WINDUP_SEC
	u["swing_t"] = JUICE_WINDUP_SEC + JUICE_SWING_SEC   # 预备结束后挥出仍有效 (decay 先过 windup 段再进 swing 段)

# 冲击火花粒子: 命中点一撮 3D 火花, GPUParticles3D 一次性 emit → 计时自销 (占位红橙火花)
func _impact_particles(pos2d: Vector2, height: float) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 10
	ps.lifetime = 0.35
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(1.0, 0.8, 0.35, 1.0)
	ps.process_material = mat
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.85, 0.4, 1.0)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = _world_pos(pos2d, height + 1.0)
	_world.add_child(ps)
	ps.emitting = true
	# 一次性: lifetime + 余量后自销 (不靠 one_shot finished 信号, 计时更稳)
	var tw := _reg_tween()
	tw.tween_interval(ps.lifetime + 0.15)
	tw.tween_callback(ps.queue_free)

# ============================================================================
#  §VFX-DEMO — GPUParticles3D 动态特效验证 (证明 2.5D 引擎能做"活"的粒子, 非静态图滑动)
#  两个 GPU 粒子函数: 火焰爆发 (球向上抛, 重力回落, 白热→橙→红→透) + 能量冲击波 (环向外扩散).
#  全程 GPU 模拟 (每颗独立速度/重力/缩放/颜色随生命渐变), 加色发光叠加, billboard 永远朝镜头.
# ============================================================================

# 火焰爆发: 球形原点喷出 70 颗火苗, 初速向上+扩散, 重力回落形成蘑菇状火球; 颜色随生命白热→橙→红→透明.
func _particle_burst(pos2d: Vector2) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 90
	ps.lifetime = 0.75
	ps.one_shot = true
	ps.explosiveness = 0.92          # 几乎同时迸发 (爆炸感)
	ps.local_coords = false          # 世界坐标: 粒子脱离发射器后继续抛飞
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.flatness = 0.0
	mat.initial_velocity_min = 2.8
	mat.initial_velocity_max = 6.5
	mat.gravity = Vector3(0, -7.5, 0)
	mat.scale_min = 0.45
	mat.scale_max = 1.15
	# 颜色渐变: 白热核 → 亮橙 → 暗红 → 透明 (alpha 末尾归 0, 火焰熄灭感)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0); grad.set_color(0, Color(1.0, 0.97, 0.85, 1.0))   # 白热
	grad.add_point(0.25, Color(1.0, 0.72, 0.25, 1.0))                          # 亮橙
	grad.add_point(0.6, Color(0.95, 0.28, 0.06, 0.85))                         # 暗红
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.05, 0.0, 0.0))     # 透明熄灭
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	ps.process_material = mat
	ps.draw_pass_1 = _make_glow_quad(0.5)
	ps.position = _world_pos(pos2d, 0.4)
	_world.add_child(ps)
	ps.emitting = true
	var _pt := _reg_tween(); _pt.tween_interval(1.0); _pt.tween_callback(ps.queue_free)   # 拆开(tween_interval返回IntervalTweener不能再链)

# 能量冲击波: 环形发射 100 颗, 径向向外飞 (radial_velocity 从中心向外) + 微上抬, 短命 → 一圈外扩光环.
func _particle_wave(pos2d: Vector2) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 120
	ps.lifetime = 0.55
	ps.one_shot = true
	ps.explosiveness = 0.95          # 整圈同时炸开
	ps.local_coords = true           # 局部坐标: radial_velocity 以发射器(环心)为枢轴向外
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)    # 环躺平在 XZ 地面
	mat.emission_ring_radius = 0.35
	mat.emission_ring_inner_radius = 0.2
	mat.emission_ring_height = 0.05
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.flatness = 0.0
	mat.initial_velocity_min = 0.4               # 几乎不靠 direction; 主要靠径向速度向外
	mat.initial_velocity_max = 1.2
	mat.radial_velocity_min = 6.0                # ← 关键: 从环心向外冲 (冲击波扩散)
	mat.radial_velocity_max = 9.0
	mat.gravity = Vector3(0, 1.5, 0)             # 轻微上飘 (不下坠, 能量上升感)
	mat.scale_min = 0.35
	mat.scale_max = 0.85
	# 颜色渐变: 青白 → 青蓝 (能量主色, 与火焰橙形成对比) → 暗蓝 → 透明 (末尾 alpha=0)
	var grad := Gradient.new()
	grad.set_offset(0, 0.0); grad.set_color(0, Color(0.9, 1.0, 1.0, 1.0))      # 青白核
	grad.add_point(0.45, Color(0.3, 0.9, 1.0, 0.95))                           # 青蓝 (主色, 拉长占比)
	grad.add_point(0.75, Color(0.15, 0.55, 1.0, 0.6))                          # 暗蓝
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0.1, 0.2, 0.6, 0.0))      # 透明
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	ps.process_material = mat
	ps.draw_pass_1 = _make_glow_quad(0.4)
	ps.position = _world_pos(pos2d, 0.25)
	_world.add_child(ps)
	ps.emitting = true
	var _pt := _reg_tween(); _pt.tween_interval(1.0); _pt.tween_callback(ps.queue_free)   # 拆开(tween_interval返回IntervalTweener不能再链)

# 共用: 加色发光 billboard quad (软圆 glow 贴图 + 颜色按 color_ramp 着色); size 为米.
func _make_glow_quad(size_m: float) -> QuadMesh:
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD            # 加色叠加 → 重叠处更亮 (火焰/能量发光)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = _make_fire_glow_tex()
	dm.vertex_color_use_as_albedo = true                    # 让 color_ramp 给每颗粒子上色
	dm.albedo_color = Color(1, 1, 1, 1)
	var qm := QuadMesh.new()
	qm.size = Vector2(size_m, size_m)
	qm.material = dm
	return qm

# 血条/龟能 overlay: 每帧 unproject 单位头顶 → 屏幕像素 (跟随)
func _update_overlay() -> void:
	if _cam == null:
		return
	if _dl_hud != null and is_instance_valid(_dl_hud):
		_dl_update_hud()
	_update_team_panels()   # 头像框栏: 每帧刷 HP 条 / 死亡变暗 / 选中高亮
	for u in _units:
		var root: Control = u["bar_root"]
		if not is_instance_valid(root):
			continue
		if not u["alive"]:
			root.visible = false
			continue
		# HpBar 组件刷新 (HP/护盾/受击红trail+白闪/刻度全自带, 1:1 回合制血条).
		#   update_state 读 u 的 maxHp/hp/shield 字段; 召唤体也是同 HpBar (无护盾段则自然不画).
		var hb = u.get("hp_bar", null)
		if hb != null and is_instance_valid(hb):
			u["_auraEnergy"] = u.get("store_energy", 0.0)   # 镜像→Hp条资源条(储能/怒气/星能/泡泡, 字段对齐回合制端口)
			u["_lavaRage"] = u.get("rage", 0.0)
			u["_starEnergy"] = u.get("star_energy", 0.0)
			u["bubbleStore"] = u.get("bubble_store", 0.0)
			u["_stoneDefGained"] = float(u.get("base_def", 0.0)) - float(u.get("stone_init_def", u.get("base_def", 0.0)))
			u["_initDef"] = float(u.get("stone_init_def", u.get("base_def", 0.0)))
			hb.update_state(u)
			var lvb = u.get("level_badge", null)   # 036温泉蛋临时升级→等级框数字实时跳
			if lvb != null and is_instance_valid(lvb) and lvb.get_child_count() > 0:
				(lvb.get_child(0) as Label).text = str(_effective_level(u))
		# 龟能条 (实时资源; 召唤体的 en_fill 已 hide)
		var enf = u.get("en_fill", null)
		if enf != null and is_instance_valid(enf) and enf.visible:
			# 进度 = 最快要冷却好的那个技的进度 (1 - 剩余/总; 即"下一招"的充能条)
			var prog := 0.0
			var cds3: Dictionary = u.get("skill_cd", {})
			for s in u.get("active_skills", []):
				var st := str(s)
				if not _IMPL_SKILLS.has(st):
					continue
				var base := _skill_cd(u, st)
				var p := 1.0 - clampf(float(cds3.get(st, base)) / maxf(0.1, base), 0.0, 1.0)
				if p > prog:
					prog = p
			enf.size.x = BAR_W * prog
		# 头顶世界坐标 → 屏幕
		var head := _world_pos(u["pos"], u["height"] + 2.4)
		if _cam.is_position_behind(head):
			root.visible = false
			continue
		root.visible = true
		var screen: Vector2 = _cam.unproject_position(head)
		var _bx: float = BAR_W * 0.5
		if u.get("_isEgg", false):
			_bx -= 8.0   # 蛋: 补偿等级牌左突(bw13+3的一半), 让"牌+血条"整体居中在蛋上(条本身仍对准蛋心)
		root.position = screen - Vector2(_bx, 8)   # 居中 (条宽 BAR_W)

# ============================================================================
#  灭队判定 + 结算横幅 (复用 2D _check_end; 赛季结算 Phase 3 接 GameState)
# ============================================================================
func _check_end() -> void:
	if OS.has_environment("VFXPREVIEW"): return   # 预览模式不判胜负
	if _is_dual_lane_mode():
		_dl_flow_check()
		return
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"] and not u.get("is_summon", false):   # 召唤体不计入胜负判定
			if u["side"] == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		var won: bool = right_alive == 0
		_settle_gears()            # 黄铜齿轮035: 战斗结束→左队每层齿轮折2深海币(死不销毁)
		_settle_season(won)        # 结果喂赛季 (命/币/胜场/XP/ghost), 守卫一次性
		_show_banner(won)

func _settle_gears() -> void:   # 黄铜齿轮035: 战斗结束结算, 左队所有单位齿轮层×2深海币
	var gs = get_node_or_null("/root/GameState")
	if gs == null or gs.get("meta_deepsea_coins") == null: return
	var total := 0
	for u in _units:
		if str(u.get("side", "")) == "left":
			total += int((u.get("eq_state", {}) as Dictionary).get("p2eq_035", {}).get("gears", 0))
	if total > 0:
		gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + total * 2)

# 赛季结算 (1:1 搬自 2D RealtimeBattleScene._settle_season): 闭环把胜负喂回 GameState 养成
func _settle_season(won: bool) -> void:
	var gs = get_node_or_null("/root/GameState")
	# demo / 无赛季态: 玩家没配 season_leaders → 不喂赛季 (只显横幅)
	_had_season = gs != null and (gs.get("season_leaders") is Array) and (gs.get("season_leaders") as Array).size() >= 1
	if not _had_season:
		return
	if gs.has_method("ensure_season"):
		gs.ensure_season()
	_last_was_exhibition = gs.is_eliminated()        # 进场前已0命 = 表演赛 (无 stake)
	if _last_was_exhibition:
		_last_reward = 5                             # 表演赛: 少量练手币, 不掉命/不计战/不上榜
	else:
		if not won:
			gs.lose_heart()                          # 输 → 失一颗心 (0命=淘汰)
		var lost_hearts: int = maxi(0, 8 - int(gs.hearts))
		_last_reward = 25 + 2 * int(gs.hearts) + 5 * lost_hearts + (15 if won else 0)
		gs.season_total_battles += 1
		gs.add_season_xp(2)                          # 每场 +2 大轮经验
		gs.candy_jar_add(1 if won else 4)            # 糖果罐(选糖果龟当统领才有): 赢+1输+4封顶30(封板L392·逆风快攒)
		if won:
			gs.season_wins += 1
			gs.season_eggs_killed += 1
			if gs.get("left_team") is Array and (gs.left_team as Array).is_empty():
				var _ldr: Array = gs.get("season_leaders")
				gs.left_team.assign(_ldr.slice(0, 3))
			var _gid := "g_%d_%d" % [int(gs.season_id), int(_t * 1000.0)]
			var _av := str(gs.season_leaders[0]) if (gs.season_leaders as Array).size() > 0 else "basic"
			Backend.upload_ghost(Backend.build_ghost_snapshot(_gid, {"name": "玩家阵容", "avatar": _av, "id": _gid}))
	gs.meta_deepsea_coins += _last_reward
	# #7 战绩同步: 实时战斗原来不写战绩 → RecordScene 永远空。这里补记本场(总场/胜计数 + match_history 一条)。
	gs.battles_total += 1
	if won:
		gs.battles_won += 1
	gs.record_match("win" if won else "lose", _resolve_left(), "实时", int(_t))
	if not gs.match_history.is_empty():
		gs.match_history[0]["ts"] = int(Time.get_unix_time_from_system())   # 相对时间戳 (RecordScene _rel_time 用)
	gs.save()

func _show_banner(won: bool) -> void:
	if _settled:
		return
	_settled = true
	# 结算: 解除暂停态并禁用暂停按钮(结果屏不可暂停); 记一条日志.
	if get_tree().paused:
		get_tree().paused = false
	if _pause_panel != null and is_instance_valid(_pause_panel):
		_pause_panel.visible = false
	if _pause_btn != null and is_instance_valid(_pause_btn):
		_pause_btn.disabled = true
	_log("[color=%s]%s[/color]" % ["#ffd93d" if won else "#ff6b6b", "🏆 战斗胜利!" if won else "💀 战斗失败!"])
	# §AUDIO: 结算 — 败方放 defeat 音; BGM 淡出收尾.
	if not won:
		_sfx_simple("defeat")
	var a := _audio()
	if a != null:
		a.stop_bgm()
	var gs = get_node_or_null("/root/GameState")
	var accent := Color("#ffd93d") if won else Color("#ff6b6b")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6); dim.size = Vector2(1280, 720)
	_ui_layer.add_child(dim)
	var big := Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	big.size = Vector2(1280, 80); big.position = Vector2(0, 250)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(big)
	# 奖励/赛季行 (有赛季态才显)
	var info := ""
	if _had_season and gs != null:
		if _last_was_exhibition:
			info = "表演赛 · +%d 深海币 (已淘汰, 无生命消耗)" % _last_reward
		else:
			info = "+%d 深海币    命 %d/8    胜场 %d    Lv.%d" % [_last_reward, int(gs.hearts), int(gs.season_wins), int(gs.get("season_level") if gs.get("season_level") != null else 1)]
			if not won:
				info += "    (失一命)"
			if gs.is_eliminated():
				info += "  ·  赛季淘汰!"
	else:
		info = "(练习赛 · 无赛季奖励)"
	var rew := Label.new()
	rew.text = info
	rew.add_theme_font_size_override("font_size", 22)
	rew.add_theme_color_override("font_color", Color("#ffe9a8"))
	rew.size = Vector2(1280, 30); rew.position = Vector2(0, 350)
	rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(rew)
	# 结束操作按钮化 (用户 2026-07-11「不要点R/ESC, 要按钮」): 再战 / 返回菜单 两个 Button.
	#   键盘 R/ESC 仍在 _unhandled_input 里作桌面快捷保留, 但不再显示文案(手机无键盘, 按钮为主).
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 28)
	btn_row.position = Vector2(0, 392)
	btn_row.size = Vector2(1280, 48)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui_layer.add_child(btn_row)
	btn_row.add_child(_make_result_btn("⚔ 再战", Color("#ffd93d"), Color("#3a2a00"),
		func() -> void: get_tree().reload_current_scene()))
	btn_row.add_child(_make_result_btn("🏠 返回菜单", Color("#5aa0d8"), Color("#04121e"),
		func() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	_build_stats_panel()             # #2 战斗统计面板


## 结算按钮 (再战/返回菜单) — 圆角实色底 + 深字 + hover/pressed 态.
func _make_result_btn(txt: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(190, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = bg.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = bg.darkened(0.12)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b

# #2 伤害统计面板: 结算时显双方各龟 输出/承受/回复/护盾 (统计在 _apply_damage* / _heal / _grant_shield 累计)
# ══════════════════════════════════════════════════════════════
# §STATS 类型分桶辅助 + 战中伤害统计面板 (R2c, 1:1 回合制 DmgStatsPanel/battle_stats 样式)
# ══════════════════════════════════════════════════════════════
func _dmg_bucket(raw: bool, col: Color) -> String:
	if raw:
		return "tru"                              # 真实伤害(无视护甲) → 白桶(与 DoT 合并)
	return "mag" if col.b > col.r else "phy"      # 蓝主导=法术(#4dabf7) / 否则物理(#ff4444)

func _st_add_type(u: Dictionary, key: String, bucket: String, amt: int) -> void:
	var d: Dictionary = u.get(key, {})
	d[bucket] = int(d.get(bucket, 0)) + amt
	u[key] = d

## 某方(left/right)全部单位 (含召唤体单列一行, 排除中立=side 非 left/right).
func _stat_units(side: String) -> Array:
	var out: Array = []
	for u in _units:
		if u.get("side", "") == side:
			out.append(u)
	return out

## 当前 Tab 的标量值 (排序/显示)
func _ds_val(u: Dictionary, tab: String) -> int:
	match tab:
		"dealt": return int(u.get("_st_dealt", 0))
		"taken": return int(u.get("_st_taken", 0))
		"heal": return int(u.get("_st_heal", 0))
		"shield": return int(u.get("_st_shield", 0))
	return 0

## 当前 Tab 的分段条 [[值,色],...] (1:1 回合制 _ds_parts): 造成/承受按类型三段, 治疗/护盾单段.
func _ds_parts(u: Dictionary, tab: String) -> Array:
	if tab == "dealt" or tab == "taken":
		var bt: Dictionary = u.get("_st_dealt_by_type" if tab == "dealt" else "_st_taken_by_type", {})
		return [
			[int(bt.get("phy", 0)), _DS_COL_PHY],
			[int(bt.get("mag", 0)), _DS_COL_MAG],
			[int(bt.get("tru", 0)) + int(bt.get("dot", 0)), _DS_COL_TRU],
		]
	elif tab == "heal":
		return [[int(u.get("_st_heal", 0)), _DS_COL_HEAL]]
	return [[int(u.get("_st_shield", 0)), _DS_COL_SHIELD]]

## stacked bar (1:1 回合制 _make_ds_bar): 高12/圆角4/裁切; 空轨 rgba(1,1,1,.05); 段按值 stretch_ratio; 余量透明露空轨.
func _make_ds_bar(parts: Array, col_max: int) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(0, 12)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(1, 1, 1, 0.05)
	wsb.set_corner_radius_all(4)
	wrap.add_theme_stylebox_override("panel", wsb)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 0)
	var used := 0
	for part in parts:
		var v: int = int(part[0])
		if v <= 0:
			continue
		var seg := ColorRect.new()
		seg.color = part[1]
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = float(v)
		hb.add_child(seg)
		used += v
	var rem: int = maxi(0, col_max - used)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = maxf(0.0001, float(rem))
	hb.add_child(spacer)
	wrap.add_child(hb)
	return wrap

## 一行 (1:1 回合制 _make_ds_row): 名(左绿/右红, 召唤体缩进)+值 / 下方分段条; 阵亡整行半透.
func _make_ds_row(u: Dictionary, side: String, col_max: int) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	if not bool(u.get("alive", true)):
		row.modulate.a = 0.4
	var top := HBoxContainer.new()
	var nm := Label.new()
	nm.text = ("↳ " if u.get("is_summon", false) else "") + str(u.get("name", u.get("id", "")))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color("#06d6a0") if side == "left" else Color("#ff6b6b"))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var val := Label.new()
	val.text = str(_ds_val(u, _dmg_stats_tab))
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color("#e6edf3"))
	top.add_child(val)
	row.add_child(top)
	row.add_child(_make_ds_bar(_ds_parts(u, _dmg_stats_tab), col_max))
	return row

## 📊 战中统计面板开关 (1:1 回合制 _on_dmg_stats_toggle)
func _on_dmg_stats_toggle() -> void:
	if _dmg_stats_panel == null:
		_build_dmg_stats_panel()
	_dmg_stats_panel.visible = not _dmg_stats_panel.visible
	if _dmg_stats_panel.visible:
		_render_dmg_stats()

## 战中统计面板骨架 (1:1 回合制 DmgStatsPanel): 暗底+金棕边 / 4Tab / 双列 rows / 0.4s 自刷.
func _build_dmg_stats_panel() -> void:
	_dmg_stats_panel = Panel.new()
	_dmg_stats_panel.position = Vector2(12, 56); _dmg_stats_panel.size = Vector2(540, 430)
	_dmg_stats_panel.visible = false
	_dmg_stats_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.075, 0.11, 0.97)
	psb.border_color = Color("#6b5430")
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	_dmg_stats_panel.add_theme_stylebox_override("panel", psb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14; vb.offset_top = 12; vb.offset_right = -14; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 8)
	_dmg_stats_panel.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	_dmg_tab_btns = []
	for pair in _DS_TABS:
		var b := Button.new()
		b.text = pair[1]
		b.add_theme_font_size_override("font_size", 15)
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var key: String = pair[0]
		b.pressed.connect(func() -> void: _dmg_stats_tab = key; _render_dmg_stats())
		tabs.add_child(b)
		_dmg_tab_btns.append({"btn": b, "key": key})
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	_dmg_stats_cols = []
	for side_label in [["我方", "left"], ["敌方", "right"]]:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 4)
		var hdr := Label.new()
		hdr.text = side_label[0]
		hdr.add_theme_font_size_override("font_size", 15)
		hdr.add_theme_color_override("font_color", Color("#06d6a0") if side_label[1] == "left" else Color("#ff6b6b"))
		colv.add_child(hdr)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		colv.add_child(rows)
		cols.add_child(colv)
		_dmg_stats_cols.append(rows)
	_ui_layer.add_child(_dmg_stats_panel)
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	t.timeout.connect(func() -> void:
		if _dmg_stats_panel != null and _dmg_stats_panel.visible:
			_render_dmg_stats())
	_dmg_stats_panel.add_child(t)

## 重建两列 rows (1:1 回合制 _render_dmg_stats): 各列按当前 Tab 值降序; Tab active 高亮.
func _render_dmg_stats() -> void:
	if _dmg_stats_cols.size() < 2:
		return
	for tb in _dmg_tab_btns:
		var active: bool = tb["key"] == _dmg_stats_tab
		(tb["btn"] as Button).add_theme_color_override("font_color", Color("#ffffff") if active else Color("#8b949e"))
	var sides := ["left", "right"]
	for ci in range(2):
		var side: String = sides[ci]
		var rows_vb: VBoxContainer = _dmg_stats_cols[ci]
		for c in rows_vb.get_children():
			rows_vb.remove_child(c)
			c.queue_free()
		var list: Array = _stat_units(side)
		var tab := _dmg_stats_tab
		list.sort_custom(func(a, b): return _ds_val(a, tab) > _ds_val(b, tab))
		var col_max := 1
		for u in list:
			col_max = maxi(col_max, _ds_val(u, tab))
		for u in list:
			rows_vb.add_child(_make_ds_row(u, side, col_max))


# ══════════════════════════════════════════════════════════════
# 结算统计表 (1:1 回合制 BattleEndScene._stats_table 7 列样式) — 双队并排, 召唤体单列一行
# ══════════════════════════════════════════════════════════════
func _build_stats_panel() -> void:
	var lefts: Array = []
	var rights: Array = []
	for u in _units:                              # 含召唤体(单列一行), 排除中立(side 非 left/right)
		if u.get("side") == "left":
			lefts.append(u)
		elif u.get("side") == "right":
			rights.append(u)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	sb.border_color = Color(0.3, 0.5, 0.7, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18; sb.content_margin_right = 18
	sb.content_margin_top = 12; sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "⚔ 战斗统计"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	vb.add_child(cols)
	cols.add_child(_stats_column("🔵 我方", lefts, Color("#7ec8ff")))
	cols.add_child(_stats_column("🔴 敌方", rights, Color("#ff9a9a")))
	_ui_layer.add_child(panel)
	panel.position = Vector2(316, 438)
	_center_panel_deferred(panel)

func _center_panel_deferred(panel: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.position = Vector2(640.0 - panel.size.x * 0.5, 438.0)

## 一队 7 列表 (1:1 回合制 _stats_table): 龟/出伤/受伤/治疗/暴击/击杀/剩余; 金表头 / 稀有度点 / 存活白·阵亡灰(阵亡).
func _stats_column(header: String, units: Array, hc: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	var hdrs := [header, "出伤", "受伤", "治疗", "暴击", "击杀", "剩余"]
	for i in range(7):
		var l := Label.new()
		l.text = hdrs[i]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", hc if i == 0 else Color("#ffd93d"))   # 金表头(回合制)
		if i == 0:
			l.custom_minimum_size = Vector2(126, 0)
		else:
			l.custom_minimum_size = Vector2(44, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for u in units:
		var dead: bool = not u.get("alive", true)
		var is_sm: bool = u.get("is_summon", false)
		# col0: 稀有度色点 + 名(阵亡后缀)
		var name_cell := HBoxContainer.new()
		name_cell.add_theme_constant_override("separation", 5)
		name_cell.custom_minimum_size = Vector2(126, 0)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color("#7a8a96") if is_sm else _pet_rarity_color(str(u.get("rarity", "C")))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_cell.add_child(dot)
		var nml := Label.new()
		nml.text = ("↳ " if is_sm else "") + str(u.get("name", u.get("id", ""))) + ("(阵亡)" if dead else "")
		nml.add_theme_font_size_override("font_size", 13)
		nml.add_theme_color_override("font_color", Color("#888888") if dead else (Color("#cdd9c2") if is_sm else Color("#ffffff")))
		name_cell.add_child(nml)
		grid.add_child(name_cell)
		var rem := "%d/%d" % [int(maxf(0.0, float(u.get("hp", 0)))), int(u.get("maxHp", 0))]
		var vals := [str(int(u.get("_st_dealt", 0))), str(int(u.get("_st_taken", 0))), str(int(u.get("_st_heal", 0))), str(int(u.get("_st_crit", 0))), str(int(u.get("_st_kills", 0))), rem]
		for i in range(6):
			var l := Label.new()
			l.text = vals[i]
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color("#888888") if dead else Color("#e8f0f6"))
			l.custom_minimum_size = Vector2(44, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
	return grid

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			if _info_panel != null and is_instance_valid(_info_panel):
				_close_info_panel()   # 详情面板开着 → ESC 先关面板 (不退场)
				return
			DEBUG_EDIT = false   # 离场重置, 不影响下次正常战斗
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	# 双路场内放置阶段: 拖我方(left)非蛋单位到位 (clamp 我方半场+避障); 「开打」钮在 GUI 层.
	if _dl_state == "place" and _is_dual_lane_mode():
		_dl_handle_place_input(event)
		return
	# 普通战斗模式: 点战场单位 (立绘头顶 unproject 命中) → 弹详情面板; 框上的点击由框自己的 gui_input 接.
	if not DEBUG_EDIT or not _edit_mode:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hit = _edit_unit_at_screen(event.position)   # 复用既有 unproject 命中 (dist<64px, 取最近)
			if hit != null:
				_show_unit_info_panel(hit)
		return
	# 🛠 调试场: 鼠标在战场(非面板)上 → 摆位/拖拽/删除. 面板按钮 mouse_filter=STOP 已在 GUI 层吃掉,
	#   故到 _unhandled_input 的鼠标事件 = 点在战场空白处 (安全当作摆位操作).
	if event is InputEventMouseButton:
		_edit_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_edit_handle_mouse_motion(event)

# ============================================================================
#  🛠 调试场 (DEBUG ARENA) — 自由摆位编辑器 (默认关; DEBUG_EDIT 开)
# ============================================================================
# 屏幕坐标 → 战场像素坐标 (反投影到 y=0 地面). _world_pos 的逆: 命中地面后换算回 ARENA 像素口径.
func _screen_to_field(screen: Vector2) -> Vector2:
	if _cam == null:
		return _arena_center
	var o := _cam.project_ray_origin(screen)
	var n := _cam.project_ray_normal(screen)
	if absf(n.y) < 0.00001:
		return _arena_center
	var t := -o.y / n.y
	var g := o + n * t
	return Vector2(g.x / WS + _arena_center.x, g.z / WS + _arena_center.y)

# 屏幕点命中哪个单位 (按头顶世界坐标 unproject 后的屏幕距离, <半径 px 算命中; 取最近).
func _edit_unit_at_screen(screen: Vector2):
	var best = null
	var best_d := 64.0   # 命中半径 (px)
	for u in _units:
		if not u.get("alive", true):
			continue
		var head := _world_pos(u["pos"], u["height"] + 1.0)   # 取身体中段
		if _cam.is_position_behind(head):
			continue
		var sp := _cam.unproject_position(head)
		var d := sp.distance_to(screen)
		if d < best_d:
			best_d = d
			best = u
	return best

func _edit_handle_mouse_button(ev: InputEventMouseButton) -> void:
	var screen := ev.position
	if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		# 右键删除最近单位
		var hit = _edit_unit_at_screen(screen)
		if hit != null:
			_edit_delete_unit(hit)
			_edit_set_status("删除了 1 个单位 (剩 %d)" % _units.size())
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		# 按下: 若命中已有单位 → 准备拖拽; 否则记录, 松手时摆放.
		_edit_drag_moved = false
		_edit_drag_unit = _edit_unit_at_screen(screen)
	else:
		# 松手: 拖拽了 → 已实时挪好, 不再摆放; 否则点空地 → 摆放新单位.
		if _edit_drag_unit != null:
			if not _edit_drag_moved:
				pass   # 单击已有单位(没拖动): 不操作 (避免误删/误叠)
		else:
			var fp := _screen_to_field(screen)
			fp.x = clampf(fp.x, ARENA.position.x, ARENA.end.x)
			fp.y = clampf(fp.y, ARENA.position.y, ARENA.end.y)
			_edit_place_unit(_edit_pick_id, _edit_pick_side, fp)
		_edit_drag_unit = null
		_edit_drag_moved = false

func _edit_handle_mouse_motion(ev: InputEventMouseMotion) -> void:
	if _edit_drag_unit == null:
		return
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_edit_drag_unit = null
		return
	_edit_drag_moved = true
	var fp := _screen_to_field(ev.position)
	fp.x = clampf(fp.x, ARENA.position.x, ARENA.end.x)
	fp.y = clampf(fp.y, ARENA.position.y, ARENA.end.y)
	_edit_drag_unit["pos"] = fp   # transforms/overlay 下一帧自动跟到新位置

# 摆放一个单位: 复用 _make_unit, 右队按调试场设置改成假人 (不动/不打/可设血/可不死).
func _edit_place_unit(id: String, side: String, pos: Vector2) -> Dictionary:
	var u := _make_unit(id, side, pos)
	if side == "right":
		u["no_basic"] = true
		u["no_move"] = true
		u["active_skills"] = []
		u["maxHp"] = _edit_dummy_hp
		u["hp"] = u["maxHp"]
		if not _edit_dummy_killable:
			u["_review_dummy"] = true   # 不死沙包(受击回满)
	_units.append(u)
	_edit_set_status("摆放 %s (%s) · 共 %d 单位" % [id, ("友军" if side == "left" else "假人"), _units.size()])
	return u

# 释放一个单位的全部 3D 节点 + 血条 overlay, 并从 _units 移除.
func _edit_free_unit_nodes(u: Dictionary) -> void:
	for k in ["sprite", "shadow", "ring", "contact"]:
		var n = u.get(k, null)
		if is_instance_valid(n):
			n.queue_free()
	var br = u.get("bar_root", null)
	if is_instance_valid(br):
		br.queue_free()
	# 召唤体/投射物 这里不处理 (编辑态不会产生)

func _edit_delete_unit(u: Dictionary) -> void:
	_edit_free_unit_nodes(u)
	_units.erase(u)

func _edit_clear() -> void:
	for u in _units.duplicate():
		_edit_free_unit_nodes(u)
	_units.clear()
	_projectiles.clear()
	for z in _lava_zones:                       # 清岩浆池(避免编辑重开残留)
		var d = z.get("disc", null)
		if d != null and is_instance_valid(d):
			d.queue_free()
	_lava_zones.clear()
	_edit_set_status("已清空")

# ▶开始: 把当前摆位生效为战斗. 为干净起见 (避免重复 _inject/_apply 叠加), 先快照摆位, 再做开战准备.
#   注: 编辑态摆放时已逐个 _make_unit, 但还没跑过 _inject_equipment/_apply_spawn_passives/_eq_apply_all_stats,
#   所以这里补跑一次即可 (开战准备), 之后退出编辑态 → 模拟开始推进.
func _edit_start_battle() -> void:
	if _units.is_empty():
		_edit_set_status("场上没有单位, 先摆几个再开始")
		return
	# 快照当前摆位 (⏸编辑 用它重新生成一份干净的)
	_edit_snapshot_setup()
	_inject_equipment()
	_apply_spawn_passives()
	_eq_apply_all_stats()
	_edit_mode = false
	_over = false
	if _edit_btn_start != null: _edit_btn_start.disabled = true
	if _edit_btn_edit != null: _edit_btn_edit.disabled = false
	_edit_set_status("战斗中 ... (点 ⏸编辑 暂停回摆位)")

# ⏸编辑: 暂停回编辑态. 按开战前的摆位快照重新生成一份干净单位 (避免战斗中状态/护盾/DoT 残留).
func _edit_back_to_edit() -> void:
	_edit_clear()
	for s in _edit_paused_setup:
		var u := _make_unit(str(s["id"]), str(s["side"]), s["pos"])
		if str(s["side"]) == "right":
			u["no_basic"] = true
			u["no_move"] = true
			u["active_skills"] = []
			u["maxHp"] = float(s.get("hp", _edit_dummy_hp))
			u["hp"] = u["maxHp"]
			if not bool(s.get("killable", false)):
				u["_review_dummy"] = true
		_units.append(u)
	_edit_mode = true
	_over = false
	if _edit_btn_start != null: _edit_btn_start.disabled = false
	if _edit_btn_edit != null: _edit_btn_edit.disabled = true
	_edit_set_status("已回编辑模式 (按摆位重新生成)")

func _edit_snapshot_setup() -> void:
	_edit_paused_setup.clear()
	for u in _units:
		_edit_paused_setup.append({
			"id": str(u["id"]),
			"side": str(u["side"]),
			"pos": Vector2(u["pos"]),
			"hp": float(u.get("maxHp", 500.0)),
			"killable": not bool(u.get("_review_dummy", false)) if str(u["side"]) == "right" else true,
		})

# ----------------------------------------------------------------------------
#  编辑面板 (代码构建, 无 .tscn). 子控件 mouse_filter=STOP → GUI 层吃掉点击, 不误摆到 UI 上.
# ----------------------------------------------------------------------------
func _build_edit_palette() -> void:
	var ids: Array = STATS.keys()
	if not ids.is_empty() and not ids.has(_edit_pick_id):
		_edit_pick_id = str(ids[0])
	var panel := PanelContainer.new()
	panel.name = "DebugEditPalette"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.13, 0.92)
	sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 10; sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板区域吃掉点击, 不穿透到战场摆位
	_ui_layer.add_child(panel)
	_edit_palette = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "🛠 调试场 · 编辑"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffd93d"))
	vb.add_child(title)

	# --- 龟选择 (◀ id ▶) ---
	var row_pick := HBoxContainer.new()
	row_pick.add_theme_constant_override("separation", 6)
	vb.add_child(row_pick)
	row_pick.add_child(_edit_mk_btn("◀", func(): _edit_cycle_pick(-1), 34))
	_edit_lbl_pick = Label.new()
	_edit_lbl_pick.custom_minimum_size = Vector2(120, 0)
	_edit_lbl_pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_lbl_pick.add_theme_font_size_override("font_size", 15)
	_edit_lbl_pick.add_theme_color_override("font_color", Color("#cfe6ff"))
	row_pick.add_child(_edit_lbl_pick)
	row_pick.add_child(_edit_mk_btn("▶", func(): _edit_cycle_pick(1), 34))

	# --- 阵营 (左队/右队) ---
	var row_side := HBoxContainer.new()
	row_side.add_theme_constant_override("separation", 6)
	vb.add_child(row_side)
	var lbl_side := Label.new(); lbl_side.text = "阵营:"
	lbl_side.add_theme_font_size_override("font_size", 14)
	lbl_side.add_theme_color_override("font_color", Color("#9fb6c8"))
	row_side.add_child(lbl_side)
	row_side.add_child(_edit_mk_btn("切换 (左队/右队)", func(): _edit_toggle_side(), 150))

	# --- 假人血量 (−/+) + 不死开关 ---
	var row_hp := HBoxContainer.new()
	row_hp.add_theme_constant_override("separation", 6)
	vb.add_child(row_hp)
	var lbl_hp_t := Label.new(); lbl_hp_t.text = "假人HP:"
	lbl_hp_t.add_theme_font_size_override("font_size", 14)
	lbl_hp_t.add_theme_color_override("font_color", Color("#9fb6c8"))
	row_hp.add_child(lbl_hp_t)
	row_hp.add_child(_edit_mk_btn("−", func(): _edit_adjust_hp(-100.0), 34))
	_edit_lbl_hp = Label.new()
	_edit_lbl_hp.custom_minimum_size = Vector2(60, 0)
	_edit_lbl_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_lbl_hp.add_theme_font_size_override("font_size", 14)
	_edit_lbl_hp.add_theme_color_override("font_color", Color("#cfe6ff"))
	row_hp.add_child(_edit_lbl_hp)
	row_hp.add_child(_edit_mk_btn("+", func(): _edit_adjust_hp(100.0), 34))
	row_hp.add_child(_edit_mk_btn("掉血/不死", func(): _edit_toggle_killable(), 96))

	# --- 控制 (开始 / 编辑 / 清空 / 返回) ---
	var row_ctl := HBoxContainer.new()
	row_ctl.add_theme_constant_override("separation", 6)
	vb.add_child(row_ctl)
	_edit_btn_start = _edit_mk_btn("▶ 开始", func(): _edit_start_battle(), 80)
	row_ctl.add_child(_edit_btn_start)
	_edit_btn_edit = _edit_mk_btn("⏸ 编辑", func(): _edit_back_to_edit(), 80)
	_edit_btn_edit.disabled = true
	row_ctl.add_child(_edit_btn_edit)
	row_ctl.add_child(_edit_mk_btn("清空", func(): _edit_clear(), 64))
	row_ctl.add_child(_edit_mk_btn("返回菜单", func(): _edit_exit_to_menu(), 90))

	# --- 状态行 + 操作提示 ---
	_edit_lbl_status = Label.new()
	_edit_lbl_status.add_theme_font_size_override("font_size", 13)
	_edit_lbl_status.add_theme_color_override("font_color", Color("#ffe9a8"))
	vb.add_child(_edit_lbl_status)
	var help := Label.new()
	help.text = "左键空地=摆放 · 拖拽单位=挪位 · 右键=删除"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color("#7a8a96"))
	vb.add_child(help)

	_edit_refresh_labels()

func _edit_mk_btn(label: String, cb: Callable, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 14)
	b.mouse_filter = Control.MOUSE_FILTER_STOP   # 按钮吃掉自身点击 (不穿透摆位)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _edit_cycle_pick(dir: int) -> void:
	var ids: Array = STATS.keys()
	if ids.is_empty():
		return
	var idx := ids.find(_edit_pick_id)
	if idx < 0:
		idx = 0
	idx = (idx + dir + ids.size()) % ids.size()
	_edit_pick_id = str(ids[idx])
	_edit_refresh_labels()

func _edit_toggle_side() -> void:
	_edit_pick_side = "right" if _edit_pick_side == "left" else "left"
	_edit_refresh_labels()

func _edit_adjust_hp(d: float) -> void:
	_edit_dummy_hp = maxf(100.0, _edit_dummy_hp + d)
	_edit_refresh_labels()

func _edit_toggle_killable() -> void:
	_edit_dummy_killable = not _edit_dummy_killable
	_edit_refresh_labels()

func _edit_refresh_labels() -> void:
	var ids: Array = STATS.keys()
	var idx := maxi(0, ids.find(_edit_pick_id))
	if _edit_lbl_pick != null:
		var nm := str(_data_by_id.get(_edit_pick_id, {}).get("name", _edit_pick_id))
		var side_t := "友军" if _edit_pick_side == "left" else "假人"
		_edit_lbl_pick.text = "%s (%d/%d) · %s" % [nm, idx + 1, ids.size(), side_t]
	if _edit_lbl_hp != null:
		var kt := "会死" if _edit_dummy_killable else "不死"
		_edit_lbl_hp.text = "%d (%s)" % [int(_edit_dummy_hp), kt]

func _edit_set_status(s: String) -> void:
	if _edit_lbl_status != null:
		_edit_lbl_status.text = s

func _edit_exit_to_menu() -> void:
	DEBUG_EDIT = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
#  DEV 自截图 (SELFSHOT=<秒>): 等战斗跑起来 + frame_post_draw 保证入帧缓冲
# ============================================================================
#  Smolder ULT fire-wave: mother dragon looms + sweeping dragonfire wave (center hottest). VFXPREVIEW=smolder.
# ============================================================================
func _vfx_smolder(origin: Vector2, dir: Vector2, si: int = 1) -> void:
	dir = dir.normalized()
	var reach: float = 620.0
	_smolder_mother(origin, dir)
	var t := _reg_tween()
	t.tween_interval(0.5)
	t.tween_callback(_smolder_erupt.bind(origin, dir, reach, si))

func _smolder_mother(origin: Vector2, dir: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/dragon-mother.png")
	if tex == null:
		return
	var d := Sprite3D.new()
	d.texture = tex
	d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	d.shaded = false
	d.transparent = true
	d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	d.flip_h = (dir.x < 0.0)
	d.pixel_size = (300.0 * WS) / float(maxi(1, int(tex.get_width())))
	var far: Vector2 = origin - dir * 260.0
	var behind: Vector2 = origin - dir * 150.0
	d.position = _world_pos(far, 3.0)
	d.modulate = Color(1, 1, 1, 0)
	_world.add_child(d)
	var tw := _reg_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_method(_smolder_mom_fly.bind(d, far, behind), 0.0, 1.0, 0.5)
	tw.tween_interval(0.7)
	tw.tween_property(d, "modulate:a", 0.0, 0.35)
	tw.tween_callback(d.queue_free)

func _smolder_mom_fly(p: float, d: Sprite3D, a: Vector2, b: Vector2) -> void:
	if is_instance_valid(d):
		d.position = _world_pos(a.lerp(b, p), 3.0 - p * 0.7)

func _smolder_erupt(origin: Vector2, dir: Vector2, reach: float, si: int) -> void:
	_shake(0.12)
	_smolder_flash()
	_smolder_burst(origin, dir)
	_smolder_fire_wave(origin, dir, reach, si)
	_smolder_ground_embers(origin, dir, reach)

func _smolder_burst(origin: Vector2, dir: Vector2) -> void:   # 喷发瞬间嘴部大亮团(扩张淡出)
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.9, 0.65, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	spr.pixel_size = (90.0 * WS) / tw_w
	spr.position = _world_pos(origin + dir * 45.0, 1.45)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "pixel_size", (260.0 * WS) / tw_w, 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_flash() -> void:
	if _ui_layer == null or not is_instance_valid(_ui_layer):
		return
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.85, 0.6, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(rect)
	var tw := _reg_tween()
	tw.tween_property(rect, "color:a", 0.3, 0.05)
	tw.tween_property(rect, "color:a", 0.0, 0.28)
	tw.tween_callback(rect.queue_free)

func _smolder_fire_wave(origin: Vector2, dir: Vector2, reach: float, si: int) -> void:
	var perp: Vector2 = dir.orthogonal()
	var waves: int = 26
	var dur: float = 0.62
	for w in range(waves):
		var wt: float = (float(w) / float(waves)) * dur
		for k in range(5):                              # 每波5团=更密实的火墙
			var lateral: float = randf_range(-1.0, 1.0)
			var voff: float = randf_range(-0.1, 1.25)   # 垂直体积: 火焰堆成一堵墙(非一条线)
			var tw := _reg_tween()
			tw.tween_interval(wt)
			tw.tween_callback(_smolder_spawn_blob.bind(origin, dir, perp, lateral, voff, reach))
	for c in range(3):                                  # 亮脊: 3个白热核错峰沿中线冲(中心最烫)
		var tc := _reg_tween()
		tc.tween_interval(float(c) * 0.12)
		tc.tween_callback(_smolder_spawn_core.bind(origin, dir, reach))

func _smolder_spawn_blob(origin: Vector2, dir: Vector2, perp: Vector2, lateral: float, voff: float, reach: float) -> void:
	var tex := _make_fire_glow_tex()
	var travel: float = randf_range(0.42, 0.6)
	var endp: Vector2 = origin + dir * (reach * randf_range(0.7, 1.05)) + perp * (lateral * reach * 0.26)
	var spr := Sprite3D.new()
	spr.texture = tex
	var heat: float = 1.0 - absf(lateral) * 0.8
	spr.modulate = Color(1.0, 0.28 + heat * 0.6, 0.04 + heat * 0.42, 0.92)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (randf_range(72.0, 140.0) * WS) / float(maxi(1, int(tex.get_width())))
	var h: float = 1.05 + voff
	spr.position = _world_pos(origin, h)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_smolder_blob_fly.bind(spr, origin, endp, h), 0.0, 1.0, travel)
	tw.tween_property(spr, "modulate:a", 0.0, travel)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_blob_fly(p: float, spr: Sprite3D, a: Vector2, b: Vector2, h: float) -> void:
	if is_instance_valid(spr):
		spr.position = _world_pos(a.lerp(b, p), h + sin(p * PI) * 0.22)

func _smolder_spawn_core(origin: Vector2, dir: Vector2, reach: float) -> void:
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.95, 0.7, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (175.0 * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(origin, 1.25)
	_world.add_child(spr)
	var endp: Vector2 = origin + dir * (reach * 0.92)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_smolder_blob_fly.bind(spr, origin, endp, 1.3), 0.0, 1.0, 0.6)
	tw.tween_property(spr, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(spr.queue_free)

func _smolder_ground_embers(origin: Vector2, dir: Vector2, reach: float) -> void:
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	for i in range(1, 9):
		var f: float = float(i) / 9.0
		var pos: Vector2 = origin + dir * (reach * f)
		var tw := _reg_tween()
		tw.tween_interval(f * 0.5)
		tw.tween_callback(_smolder_ember_at.bind(pos, burn))

func _smolder_ember_at(pos2d: Vector2, burn: Texture2D) -> void:
	if burn == null:
		return
	play_sheet_vfx(pos2d, burn, 8, 95.0, 1.1, 0.12)

func _vfx_preview_start() -> void:   # VFX预览: 清单位/放大相机/场地中心反复放特效 (自截图迭代用)
	for u in _units:
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp): sp.queue_free()
	_units = []
	if _team_panel_left != null and is_instance_valid(_team_panel_left): _team_panel_left.queue_free()
	if _team_panel_right != null and is_instance_valid(_team_panel_right): _team_panel_right.queue_free()
	_cam.fov = float(OS.get_environment("VFXPREVIEW_FOV")) if OS.has_environment("VFXPREVIEW_FOV") else 26.0
	_vfx_preview_loop()

func _vfx_preview_loop() -> void:
	var eff: String = OS.get_environment("VFXPREVIEW")
	var si: int = (int(OS.get_environment("VFXPREVIEW_STAR")) - 1) if OS.has_environment("VFXPREVIEW_STAR") else 1
	var period: float = float(OS.get_environment("VFXPREVIEW_PERIOD")) if OS.has_environment("VFXPREVIEW_PERIOD") else 1.2
	await get_tree().create_timer(0.4).timeout
	while is_instance_valid(self):
		var origin: Vector2 = _arena_center
		var dir: Vector2 = Vector2.RIGHT
		var fu: Dictionary = {"pos": origin, "alive": true, "id": "basic", "side": "left", "atk_range": 350.0, "equips": [], "def": 30.0, "mr": 30.0, "atk": 100.0, "crit": 0.25, "crit_dmg": 1.5, "lifesteal": 0.0, "armor_pen": 0.0, "energy_cost": {}}
		match eff:
			"laser_sweep": _laser_blade_sweep(fu, origin, dir, 350.0, 60.0)
			"laser_chop": _eq_laser_chop(fu, {"pos": origin + dir * 300.0, "alive": true}, si, 180.0)
			"moon": _eq_wide_blade(fu, {"pos": origin + dir * 650.0, "alive": true}, si)
			"slash": _blood_slash(origin - dir * 60.0, origin, 0.0)
			"smolder": _vfx_smolder(origin, dir, si)
			"qibo": _sk_basic_chiwave(fu, {"pos": origin + dir * 600.0, "alive": true, "id": "dummy", "def": 30.0, "mr": 30.0, "maxHp": 5000.0, "hp": 5000.0})
			"stone_slam": _burst_vfx("res://assets/sprites/vfx/stone-slam-impact.png", origin, 220.0)
			"ninja_slash": _burst_vfx("res://assets/sprites/vfx/ninja-slash.png", origin, 98.0, 1.0)
			"beam": _beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", origin, origin + dir * 700.0, 126.0, Color(0.6, 0.94, 1.0, 0.9), 1.6)
			"aura": _aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", fu, 300.0, Color(0.86, 0.68, 0.42, 0.5), 1.8)
			"vortex": _burst_vfx("res://assets/sprites/vfx/fx-vortex.png", origin, 240.0, 0.6)
			"blackhole": _burst_vfx("res://assets/sprites/vfx/fx-black-hole.png", origin, 260.0, 0.12)
			"hexbubble": _aura_vfx("res://assets/sprites/vfx/fx-hex-bubble.png", fu, 62.0, Color(0.68, 0.9, 1.0, 0.62), 1.8, 0.9)
			_: _laser_blade_sweep(fu, origin, dir, 350.0, 60.0)
		await get_tree().create_timer(period).timeout
func _self_screenshot() -> void:
	var delay := 3.0
	var s := OS.get_environment("SELFSHOT")
	if s.is_valid_float() and s.to_float() > 0.1:
		delay = s.to_float()
	await get_tree().create_timer(delay).timeout
	var out := "res://_p2_battle.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	# 连拍模式(SHOT_BURST=N + SHOT_STEP=秒): 抓瞬时特效(火龙飞行/闪电劈), 存 out_0.png.._N.png
	if OS.has_environment("SHOT_BURST"):
		var n: int = maxi(1, int(OS.get_environment("SHOT_BURST")))
		var step: float = float(OS.get_environment("SHOT_STEP")) if OS.has_environment("SHOT_STEP") else 0.09
		var base := out.trim_suffix(".png")
		for i in range(n):
			await RenderingServer.frame_post_draw
			var im: Image = get_viewport().get_texture().get_image()
			im.save_png("%s_%d.png" % [base, i])
			await get_tree().create_timer(step).timeout
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	get_tree().quit()

# ============================================================================
#  装备实时实装 (59件 p2eq_*) — 1:1 搬自 2D 版 RealtimeBattleScene.gd (docs/design/装备实时实装规格.md)
#  数据驱动: 逐星属性复用 P2RT.STATS; 事件钩子 on-hit/on-cast/on-target/on-dodge/on-kill/on-death/HP阈值 + 周期 tick(2.5s).
#  2.5D 适配: 逻辑/数值全照搬; VFX/坐标触点用 Phase3 的 3D 等价 (_float_text/_skill_ring/_bolt_line/_fire_bolt_from/_spawn_summon).
#  分类标注: ✅完整 / ⚠改造(节拍·时长·站位) / 🚧TODO(简化) — 与 2D 版一致.
# ============================================================================
const P2RT := preload("res://scripts/engine/phase2_equip_runtime.gd")
const EQ_TICK := 2.5            # 装备周期触发 = 1回合 ≈ 2.5 秒 (规格)
const EQ_BLEED_SEC := 5.0       # 流血/灼烧 DoT 持续秒 (待F5)
const EQ_BURN_SEC := 5.0

# demo 测试装备 (persistent_equipped 空时): 给每龟塞2-3件有视觉效果的件, 验证效果真触发. (与 2D 版 DEMO_EQUIP 一致)
const DEMO_EQUIP := {
	"stone":     [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_013", "star": 2}],          # 铁壁盾(周期全队护盾)+炙烤海胆(受击硬化)
	"basic":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_005", "star": 2}, {"id": "p2eq_023", "star": 2}],  # 海带卷刀(流血)+双生匕首(追击)+灼热火珊瑚(灼烧)
	"lightning": [{"id": "p2eq_026", "star": 2}, {"id": "p2eq_004", "star": 2}],          # 雷电法杖(连锁闪电)+暴君之牙(处决)
	"diamond":   [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_046", "star": 2}],          # 铁壁盾(周期护盾)+幽灵墨鱼(闪避护盾)
	"ninja":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_054", "star": 1}, {"id": "p2eq_058", "star": 2}],  # 流血+瞄准镜(必中)+穿甲遗弹(贯穿)
	"ghost":     [{"id": "p2eq_023", "star": 3}, {"id": "p2eq_026", "star": 1}],          # 灼热火珊瑚(灼烧)+雷电法杖(连锁)
}

# 装备注入: 玩家队(left)读 persistent_equipped; demo 阵容兜底塞测试装备.
func _inject_equipment() -> void:
	if _review_demo() and not OS.has_environment("EQDEMO_EQUIP") and not _is_dual_lane_mode():
		return                          # 评审: 受审龟裸装, 看纯内在数值 (装备演示 EQDEMO / 双路对局 例外, 要装上)
	var gs = get_node_or_null("/root/GameState")
	var pe: Dictionary = {}
	if gs != null and gs.get("persistent_equipped") is Dictionary:
		pe = gs.get("persistent_equipped")
	var use_demo: bool = pe.is_empty() and not _is_dual_lane_mode()   # 双路: 玩家没配装就裸装, 不塞测试装备
	for u in _units:
		if u.get("is_summon", false):
			continue
		var key: String = str(u["id"])
		var list: Array = []
		if u.has("_dl_equips") and u["_dl_equips"] is Array and not (u["_dl_equips"] as Array).is_empty():
			for it in (u["_dl_equips"] as Array):   # 双路: leader/小将局外配的装(dual_lineup)优先 — 小将id共享__minion__, 只能走这里
				if it is Dictionary and it.has("id"):
					list.append({"id": str(it["id"]), "star": int(it.get("star", 1))})
		elif not use_demo and pe.has(key):
			if u["side"] == "left":
				for it in (pe[key] as Array):
					if it is Dictionary and it.has("id"):
						list.append({"id": str(it["id"]), "star": int(it.get("star", 1))})
		if use_demo and DEMO_EQUIP.has(key):
			list = (DEMO_EQUIP[key] as Array).duplicate(true)
		u["equips"] = list
		if OS.has_environment("EQDEMO_EQUIP") and not u.get("_eqdemo_carrier", false):
			u["equips"] = []   # EQDEMO 非携带者(友方假人+敌方假人)一律裸装, 中立不干扰观察
		if OS.has_environment("EQDEMO_EQUIP") and u.get("_eqdemo_carrier", false):   # 装备演示: 只携带者强制装该件(友方假人不装)
			var _est: int = (int(OS.get_environment("EQDEMO_STAR")) if OS.has_environment("EQDEMO_STAR") else 2)
			var _ecnt: int = maxi(1, int(OS.get_environment("EQDEMO_COUNT"))) if OS.has_environment("EQDEMO_COUNT") else 1   # 多件同款演示
			list = []
			for _ci in range(_ecnt):
				list.append({"id": OS.get_environment("EQDEMO_EQUIP"), "star": _est})
			u["equips"] = list
		for e in list:
			u["eq_state"][str(e["id"])] = {}

# 开战: 全装备纯属性 + 永久 flag 加到携带者 (在 spawn 被动之后, 让属性叠上不被覆盖).
func _eq_apply_all_stats() -> void:
	for u in _units:
		for e in u.get("equips", []):
			_eq_apply_one_stats(u, str(e["id"]), int(e.get("star", 1)))

# 单件逐星属性 → 实时单位字段 (复用 P2RT.STATS; 字段口径换到实时引擎).
func _eq_apply_one_stats(u: Dictionary, item_id: String, star: int) -> void:
	var arr: Array = P2RT.STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		_eq_apply_flags(u, item_id, star)
		return
	var st: Dictionary = arr[i]
	if st.has("atk"):
		u["base_atk"] += float(st["atk"])
	if st.has("hp"):
		var add: float = float(st["hp"])  # 装备hp已是最终值
		u["maxHp"] += add; u["hp"] += add
	if st.has("crit"):
		u["crit"] += float(st["crit"])
	if st.has("armorPen"):
		u["armor_pen"] += float(st["armorPen"])
	if st.has("magicPen"):
		u["magic_pen"] += float(st["magicPen"])
	if st.has("_lifestealPct"):
		u["lifesteal"] += float(st["_lifestealPct"]) / 100.0
	if st.has("def"):
		u["base_def"] += float(st["def"])
	if st.has("mr"):
		u["base_mr"] += float(st["mr"])
	if st.has("critDmg"):
		u["crit_dmg"] += float(st["critDmg"])
	if st.has("_maxEnergy"):   # 初始龟能: 开局减该技冷却(init_energy_bonus懒初始化时折算, 多件叠加)
		u["init_energy_bonus"] = float(u.get("init_energy_bonus", 0.0)) + float(st["_maxEnergy"])
	if st.has("_echargePct"):   # 龟能充能速率% → echarge_perm 永久倍率(多件叠加)
		u["echarge_perm"] = float(u.get("echarge_perm", 1.0)) + float(st["_echargePct"]) / 100.0
	_recalc_stats(u)
	_eq_apply_flags(u, item_id, star)

# 财神招财临时装备升星: STATS[item]每星是绝对值→只加(新星-旧星)数值差量(不重跑_eq_apply_flags,避免dodge/harden/on-hit等flag类重复叠加·flag类逐星缩放留F5)
func _eq_star_delta_stats(u: Dictionary, item_id: String, from_star: int, to_star: int) -> void:
	var arr: Array = P2RT.STATS.get(item_id, [])
	var fi: int = clampi(from_star, 1, 3) - 1
	var ti: int = clampi(to_star, 1, 3) - 1
	if fi < 0 or ti < 0 or fi >= arr.size() or ti >= arr.size():
		return
	var a: Dictionary = arr[fi]
	var b: Dictionary = arr[ti]
	u["base_atk"] += float(b.get("atk", 0.0)) - float(a.get("atk", 0.0))
	var hp_d: float = float(b.get("hp", 0.0)) - float(a.get("hp", 0.0))   # 装备hp已是最终值
	u["maxHp"] += hp_d; u["hp"] += hp_d
	u["crit"] += float(b.get("crit", 0.0)) - float(a.get("crit", 0.0))
	u["armor_pen"] += float(b.get("armorPen", 0.0)) - float(a.get("armorPen", 0.0))
	u["magic_pen"] += float(b.get("magicPen", 0.0)) - float(a.get("magicPen", 0.0))
	u["lifesteal"] += (float(b.get("_lifestealPct", 0.0)) - float(a.get("_lifestealPct", 0.0))) / 100.0
	u["base_def"] += float(b.get("def", 0.0)) - float(a.get("def", 0.0))
	u["base_mr"] += float(b.get("mr", 0.0)) - float(a.get("mr", 0.0))
	u["crit_dmg"] += float(b.get("critDmg", 0.0)) - float(a.get("critDmg", 0.0))
	u["init_energy_bonus"] = float(u.get("init_energy_bonus", 0.0)) + float(b.get("_maxEnergy", 0.0)) - float(a.get("_maxEnergy", 0.0))
	u["echarge_perm"] = float(u.get("echarge_perm", 1.0)) + (float(b.get("_echargePct", 0.0)) - float(a.get("_echargePct", 0.0))) / 100.0
	_recalc_stats(u)

# 永久 flag / 初始充能 (受击/闪避/必中类被动开关 + 充能计数器初值).
func _eq_apply_flags(u: Dictionary, item_id: String, star: int) -> void:
	var si: int = clampi(star, 1, 3) - 1
	var stt: Dictionary = u["eq_state"].get(item_id, {})
	match item_id:
		"p2eq_046":   # 幽灵墨鱼: 永久闪避 buff (复用 dodge 系统)
			_buff(u, "dodge", [0.15, 0.25, 0.50][si], false, 99999.0)
			stt["ghost_shield"] = [30.0, 50.0, 120.0][si]
		"p2eq_054":   # 瞄准镜: 必中 (无视目标闪避)
			u["eq_cannot_be_dodged"] = true
		"p2eq_013", "p2eq_014":   # 炙烤海胆 / 深海堡垒甲: 受击硬化层 +def/mr (cap20)
			stt["harden_inc"] = [1.0, 1.5, 2.0][si]
			stt["harden_stacks"] = 0
			stt["harden_shield"] = (50.0 if item_id == "p2eq_013" else 0.0) if si == 0 else ([60.0, 80.0][si - 1] if item_id == "p2eq_013" else 0.0)
			stt["harden_given"] = false
		"p2eq_015":   # 荆棘海胆: 反伤转真伤+施流血
			stt["reflect_pct"] = [10.0, 17.0, 25.0][si] / 100.0
			stt["reflect_bleed"] = [2.0, 2.5, 3.0][si]
		"p2eq_016":   # 铁壁盾: 每段非真实伤害固定减 2/4/6 (flat_dr, 叠加多件取和)
			u["flat_dr"] = float(u.get("flat_dr", 0.0)) + [2.0, 4.0, 6.0][si]
		"p2eq_024":   # 龙蛋: 装备即3层吐息
			stt["dragon_stacks"] = 3
		"p2eq_039":   # 竹制弓箭: 生长充能数 (3★=3次)
			stt["bamboo_charges"] = [1, 1, 3][si]
		"p2eq_052":   # 左轮: 6发子弹
			stt["revolver_bullets"] = 6
		"p2eq_027":   # 电棍: 3层电击
			stt["baton_charges"] = [3, 4, 5][si]
		"p2eq_032":   # 唤灵骨符: 登场召唤亡灵骷髅 (延到首帧spawn, 避免开战setup中append _units)
			u["_skele_pending"] = true
			u["_skele_si"] = si
		"p2eq_047":   # 重击锤: ATK += maxHp×pct (一次性按当前maxHp折算)
			u["hammer_pct"] = float(u.get("hammer_pct", 0.0)) + [0.04, 0.06, 0.15][si]   # 重击锤: 随maxHp动态(在_recalc_stats累加), 多件叠加
			_recalc_stats(u)
		"p2eq_035":   # 黄铜齿轮: 齿轮层
			stt["gears"] = 0
		"p2eq_034":   # 玩偶小熊: 大熊层 + 已销毁标记 + 每4s派小熊计时 + 蓄力标记
			stt["bear_layers"] = 0
			stt["bear_done"] = false
			stt["doll_si"] = si
			stt["doll_t"] = 0.0
			stt["bear_charging"] = false
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag) + 受伤治疗最低血%友军累积充能
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
			stt["anchor_accum"] = 0.0    # 累积治疗, 满100→+1充能
			stt["anchor_charges"] = 0    # 沉锚充能 (施法时消耗)
		"p2eq_011":   # 饮血护符坠: 溢出治疗转血护盾 (累积上限200/350/500, 多件取最大上限)
			u["overheal2shield_cap"] = maxf(float(u.get("overheal2shield_cap", 0.0)), [200.0, 350.0, 500.0][si])
		"p2eq_036":   # 温泉蛋: 孵化进度 → 满级全队护盾(一次)
			stt["incub"] = 0.0
			stt["incub_given"] = false
			stt["egg_levels"] = 0
			stt["incub_shield"] = [300.0, 400.0, 600.0][si]
			u["has_egg"] = true
	u["eq_state"][item_id] = stt

# ── 工具 ──
func _eq_si(star: int) -> int:
	return clampi(star, 1, 3) - 1

func _eq_first_in_line(u: Dictionary, dir: Vector2, width: float):
	var best = null; var bd := INF
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], width):
			var dd: float = (o["pos"] - u["pos"]).length_squared()
			if dd < bd: bd = dd; best = o
	return best

func _eq_farthest_enemies(u: Dictionary, half: bool) -> Array:
	var es := _enemies_of(u)
	es.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() > (b["pos"] - u["pos"]).length_squared())
	if half:
		return es.slice(0, maxi(1, es.size() / 2))
	return es

# 某一方是否有存活单位携带某装备 (飞镖靶子标记用)
func _side_has_equip(side: String, item_id: String) -> bool:
	for o in _units:
		if o["side"] == side and o["alive"]:
			for e in o.get("equips", []):
				if str(e["id"]) == item_id:
					return true
	return false

func _count_summons(side: String, kind: String) -> int:
	var c := 0
	for o in _units:
		if o.get("is_summon", false) and o["side"] == side and o["alive"] and str(o.get("summon_kind", "")) == kind:
			c += 1
	return c

# 充能助手: 累加 amt, 达 cap → 清零(保留溢出)并触发 on_full.
func _eq_charge(stt: Dictionary, key: String, amt: float, cap: float, on_full: Callable) -> void:
	var v: float = float(stt.get(key, 0.0)) + amt
	if v >= cap:
		stt[key] = v - cap
		on_full.call()
	else:
		stt[key] = v

# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
func _eq_on_hit(src: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if src.get("equips", []).is_empty():
		return
	# AoE 判定(启发式): 同帧内 src 命中≥2个不同目标 → 范围技能 (供 002 等"范围减半"用; 首个目标算单体)
	var _fr: int = Engine.get_process_frames()
	if int(src.get("_onhit_fr", -1)) != _fr:
		src["_onhit_fr"] = _fr; src["_onhit_tgts"] = []
	var _otl: Array = src["_onhit_tgts"]
	if not (tgt in _otl): _otl.append(tgt)
	var is_aoe: bool = _otl.size() >= 2
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = src["eq_state"].get(iid, {})
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌
				var line: float = [0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					_float_text(tgt["pos"], "-999999", _VC.color_of(_VC.cls_for("damage", "true", true)), true, "damage", "true")   # 处决=固定跳-999999真伤大字(实际伤害=剩余血, 用户)
					tgt["hp"] = 0.0
					if was: _kill(tgt, src)
			"p2eq_002":   # 海带卷刀: 命中→施加流血层 (范围技能触发减半; 3★流血层数天然可叠)
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"] * (0.5 if is_aoe else 1.0)))
				_apply_dot_stacks(tgt, "bleed", bs, src)
			"p2eq_003":   # 锋利鲨齿: 溅射150码内相邻敌 + 圈圈扩散(用户)
				var frac: float = [0.15, 0.28, 0.50][si]
				_skill_ring(tgt["pos"], Color(1.0, 0.82, 0.42, 0.75), 150.0)   # 溅射圈扩散(贴地环从命中点扩到150码)
				for o in _enemies_of(src):
					if o != tgt and (o["pos"] - tgt["pos"]).length() <= 150.0:
						_apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
			"p2eq_005":   # 双生匕首: 命中概率追加一刀双生刺击
				if randf() < [0.5, 0.75, 1.0][si]:
					_apply_damage_from(src, tgt, _atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ff4444"), 0.0, false, true)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外灼烧 + 充能
				var burn: int = maxi(1, roundi([2.0, 5.0, 8.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "burn", burn, src)
				_eq_charge(stt, "fire_mana", 1.0, 8.0, func(): _eq_fire_coral_active(src, si))
			"p2eq_009":   # 宽刃弯刀: 充刃能, 满100→直线伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si], 100.0, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖: 充能25, 满100→连锁闪电
				_eq_charge(stt, "thunder", 25.0, 100.0, func(): _chain_windup(src, si))
			"p2eq_029":   # 冰封水母: 概率额外魔伤+冻结, 冻结→自护盾
					pass
			"p2eq_054":   # 瞄准镜: 必中→命中时目标身上一瞬锁定框(表现无视闪避)
				_reticle_flash(tgt, Color("#ff6a5a"))
			"p2eq_055":   # 靶向器: 命中标记目标 (+20% 受伤) 2回合
				tgt["eq_marked_until"] = _t + 5.0
				_mark_vfx(tgt, 5.0, Color("#ff4d4d"))
			"p2eq_058":   # 穿甲遗弹: 贯穿→身后同列敌
				var frac2: float = [0.25, 0.40, 0.60][si]
				var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
				var _pd: float = 1.5 if OS.has_environment("XDBG") else 0.22
				for o in _enemies_of(src):
					if o != tgt and _on_line(tgt["pos"], dir, o["pos"], 40.0):
						var _pt: Vector2 = o["pos"] + dir * 45.0
						_laser_beam(tgt["pos"], _pt, Color(1.0, 0.78, 0.34, 0.82), 0.13, _pd, 1.0)          # 粗金穿透辉
						_laser_beam(tgt["pos"], _pt, Color(1.0, 0.96, 0.8, 0.95), 0.05, _pd * 0.85, 1.02)     # 白热贯穿核
						_apply_damage_from(src, o, maxi(1, int(dmg * frac2)), Color("#ffd07a"), 0.0, false, true)
						_hit_spark(o)
		src["eq_state"][iid] = stt

# 雷电法杖 026: 连锁闪电
func _eq_chain_lightning(u: Dictionary, si: int) -> void:
	var enemies := _enemies_of(u)
	if enemies.is_empty():
		return
	var hops: int = [4, 5, 6][si]
	var dmg: int = [40, 60, 90][si]
	# 目标序列: 首个随机, 之后每跳=离当前最近(优先未命中; 无未命中则跳已命中, 排除刚打的→两目标间来回弹)
	var seq: Array = []
	var hit: Array = []  # ★2026-07-10 闪退真因: 不能拿【单位字典】当 Dictionary 的 key —— Godot 会对 key 求哈希, 单位字典里有 summons/summon_owner 等互相引用的结构 → recursive_hash 无限递归 → 每次查表刷一条 ERROR: Max recursion reached。改用 Array(.has 走 == 不哈希)。
	var first = enemies[randi() % enemies.size()]
	seq.append(first); hit.append(first)
	var cur = first
	for h in range(hops - 1):
		var cpos: Vector2 = cur["pos"]
		var best_new = null; var bd_new := INF
		var best_any = null; var bd_any := INF
		for o in enemies:
			if o == cur:
				continue
			var d: float = o["pos"].distance_squared_to(cpos)
			if d < bd_any: bd_any = d; best_any = o
			if not hit.has(o) and d < bd_new: bd_new = d; best_new = o
		var nxt = best_new if best_new != null else best_any
		if nxt == null:
			break
		seq.append(nxt); hit.append(nxt); cur = nxt
	# 逐跳错峰(0.12s): 画锯齿弧+命中爆闪+魔法伤害
	var prev_pos: Vector2 = u["pos"]
	for i in range(seq.size()):
		var tgt = seq[i]
		var tw := _reg_tween()
		tw.tween_interval(float(i) * 0.2)
		tw.tween_callback(_chain_segment.bind(u, prev_pos, tgt, dmg))
		prev_pos = tgt["pos"]

func _chain_segment(u: Dictionary, from2d: Vector2, tgt: Dictionary, dmg: int) -> void:
	if not tgt.get("alive", false):
		return
	_chain_arc(from2d, tgt["pos"])
	_chain_zap(tgt["pos"])
	_apply_damage_from(u, tgt, _resolve_dmg(u, float(dmg), tgt, true), Color("#7ecbff"), 0.0, false, true)   # 魔法伤害(过魔抗+吃魔穿)

# 蓄电前摇: 携带者身上聚一颗青电球(加速涨大变亮)+电环, ~0.4s 后射出连锁
func _chain_windup(u: Dictionary, si: int) -> void:
	var tex := _make_fire_glow_tex()
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	var orb := Sprite3D.new()
	orb.texture = tex
	orb.modulate = Color(0.5, 0.85, 1.0, 0.0)
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orb.shaded = false
	orb.transparent = true
	orb.pixel_size = (18.0 * WS) / tw_w
	orb.position = _world_pos(u["pos"], 1.15)
	_world.add_child(orb)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "pixel_size", (95.0 * WS) / tw_w, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(orb, "modulate:a", 1.0, 0.36)
	tw.chain().tween_callback(orb.queue_free)
	_skill_ring(u["pos"], Color(0.4, 0.8, 1.0, 0.5), 60.0)
	var tf := _reg_tween()
	tf.tween_interval(0.4)
	tf.tween_callback(_eq_chain_lightning.bind(u, si))

# 锯齿闪电弧: PixelLab chain-bolt 贴图, 定向拉伸连 a→b(面朝相机), 闪一下淡出
func _chain_arc(a2d: Vector2, b2d: Vector2) -> void:
	if _cam == null:
		return
	var tex: Texture2D = load("res://assets/sprites/vfx/chain-bolt.png")
	if tex == null:
		return
	var a3: Vector3 = _world_pos(a2d, 0.95)
	var b3: Vector3 = _world_pos(b2d, 0.95)
	var mid: Vector3 = (a3 + b3) * 0.5
	var seg: Vector3 = b3 - a3
	var dist: float = seg.length()
	if dist < 0.05:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.no_depth_test = true
	var thickness: float = 0.46                       # 固定厚度(不随长度变粗)
	spr.pixel_size = thickness / float(maxi(1, int(tex.get_height())))
	var base_w: float = float(maxi(1, int(tex.get_width()))) * spr.pixel_size
	var xn: Vector3 = seg.normalized()
	var zn: Vector3 = (_cam.global_position - mid).normalized()
	var yn: Vector3 = zn.cross(xn).normalized()
	zn = xn.cross(yn).normalized()
	var basis := Basis.IDENTITY
	basis.x = xn * (dist / maxf(0.01, base_w))        # X拉伸=宽度到dist, 厚度固定→细锯齿
	basis.y = yn
	basis.z = zn
	_world.add_child(spr)
	spr.global_transform = Transform3D(basis, mid)
	var t := _reg_tween()
	t.tween_interval(0.07)
	t.tween_property(spr, "modulate:a", 0.0, 0.14)
	t.tween_callback(spr.queue_free)

# 电击命中爆闪: PixelLab electric-zap 贴图, 放大淡出
func _chain_zap(pos2d: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/electric-zap.png")
	if tex == null:
		return
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.hframes = 5
	spr.frame = 0
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.no_depth_test = true
	var fw: float = float(maxi(1, int(tex.get_width()))) / 5.0
	spr.pixel_size = (125.0 * WS) / fw
	spr.position = _world_pos(pos2d, 0.95)
	_world.add_child(spr)
	var t := _reg_tween()
	t.tween_method(_zap_frame.bind(spr), 0.0, 5.0, 0.3)
	t.tween_callback(spr.queue_free)

func _zap_frame(fr: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		spr.frame = clampi(int(fr), 0, 4)

# 宽刃弯刀 009
func _set_sprite_frame(spr: Sprite3D, f: int) -> void:
	if is_instance_valid(spr): spr.frame = f

func _make_moon_sheet(col: Color) -> ImageTexture:   # 弯月黄色闪电斩 5帧(与预警扇区同几何: 顶点左中/环650码带/±30度; 锯齿闪电; 生成→峰值→消散)
	var FW := 128; var FN := 5
	var img := Image.create(FW * FN, FW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(FW) * 0.5
	var half := deg_to_rad(30.0)
	var midr := 0.81   # 650/800 环中心
	for f in range(FN):
		var t := float(f) / float(FN - 1)
		var bright: float = (minf(t / 0.32, 1.0)) if t <= 0.5 else (maxf(0.0, 1.0 - (t - 0.5) / 0.5))
		var ht := 0.03 + 0.075 * sin(PI * clampf(t, 0.0, 1.0))   # 带半厚(fraction)
		var ox := f * FW
		for y in range(FW):
			for x in range(FW):
				var dx := float(x); var dy := float(y) - cy
				var dist := sqrt(dx * dx + dy * dy) / float(FW - 1)
				var a := atan2(dy, dx)
				if absf(a) > half: continue
				var jag := sin(a * 10.0 + t * 6.0) * 0.02 + sin(a * 27.0 + float(f)) * 0.012   # 闪电锯齿
				var dd := absf(dist - (midr + jag))
				if dd > ht: continue
				if t > 0.55 and sin(a * 16.0 + float(f) * 2.3) > lerpf(1.1, -0.3, (t - 0.55) / 0.45): continue
				var e := (1.0 - dd / ht) * bright
				if e <= 0.02: continue
				var c := col.lerp(Color(1, 1, 1), clampf(e * 1.4, 0.0, 1.0) * 0.78)
				c.a = clampf(e * e + 0.08 * bright, 0.0, 1.0)
				img.set_pixel(ox + x, y, c)
	return ImageTexture.create_from_image(img)
func _make_sector_tex(col: Color) -> ImageTexture:   # 环形扇区(顶点在左中, 沿+X扇开; 环500~800=inner0.625, 60度): 预警用
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(S) / 2.0
	var half := deg_to_rad(30.0)
	for y in range(S):
		for x in range(S):
			var dx := float(x)
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy) / float(S - 1)
			if dist < 0.625 or dist > 1.0: continue
			var a := atan2(dy, dx)
			if absf(a) > half: continue
			var er := minf((dist - 0.625) / 0.09, (1.0 - dist) / 0.09)
			var ea := (half - absf(a)) / deg_to_rad(9.0)
			var e := clampf(minf(minf(er, ea), 1.0), 0.0, 1.0)
			var c := col; c.a = col.a * (0.3 + 0.7 * e)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_moon_tex(col: Color) -> ImageTexture:   # 弯月刃(凸面朝+X): 大圆减偏移圆, 亮核软光, 像素感
	var S := 96
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ocx := float(S) * 0.36; var ocy := float(S) * 0.5; var oR := float(S) * 0.44
	var ccx := float(S) * 0.14; var ccy := float(S) * 0.5; var cR := float(S) * 0.45
	for y in range(S):
		for x in range(S):
			var od := sqrt(pow(float(x) - ocx, 2.0) + pow(float(y) - ocy, 2.0))
			var cd := sqrt(pow(float(x) - ccx, 2.0) + pow(float(y) - ccy, 2.0))
			if od > oR or cd < cR: continue
			var e := minf((oR - od) / 5.0, (cd - cR) / 5.0)
			e = clampf(e, 0.0, 1.0)
			var c := col.lerp(Color(1, 1, 1), clampf(e * 1.5, 0.0, 1.0) * 0.7)
			c.a = clampf(e + 0.25, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
func _make_fan_tex(col: Color, half_deg: float) -> ImageTexture:   # 扇形(顶点左中/满半径/±half_deg): 激光长刃扇形斩
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(S) * 0.5; var half := deg_to_rad(half_deg)
	for y in range(S):
		for x in range(S):
			var dx := float(x); var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy) / float(S - 1)
			if dist > 1.0: continue
			var a := atan2(dy, dx)
			if absf(a) > half: continue
			var e := clampf(minf(minf((1.0 - dist) / 0.16, (half - absf(a)) / deg_to_rad(12.0)), 1.0), 0.0, 1.0)
			var c := col; c.a = col.a * (0.22 + 0.78 * e)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _laser_blade_sweep(u: Dictionary, origin: Vector2, dir: Vector2, rng: float, half_deg: float) -> void:   # 红激光长刃: 扇区红光晕 + 厚白热刃平滑扫过
	var base_ang: float = atan2(dir.y, dir.x)
	var glow := Sprite3D.new()   # 扫过区域红光晕(整片扇形发光)
	glow.texture = _make_fan_tex(Color(1.0, 0.14, 0.18, 1.0), half_deg)
	glow.billboard = BaseMaterial3D.BILLBOARD_DISABLED; glow.axis = Vector3.AXIS_Y
	glow.shaded = false; glow.transparent = true
	glow.pixel_size = rng * WS / 128.0
	glow.rotation = Vector3(0.0, -base_ang, 0.0)
	glow.position = _world_pos(origin + dir * (rng * 0.5), 0.09)
	glow.modulate = Color(1.0, 0.3, 0.3, 0.0)
	_world.add_child(glow)
	var gt := _reg_tween()
	gt.tween_property(glow, "modulate:a", 0.5, 0.09)
	gt.tween_property(glow, "modulate:a", 0.0, 0.2)
	gt.tween_callback(glow.queue_free)
	var blade := Sprite3D.new()   # 厚白热激光长刃(扫过)
	blade.texture = _make_laser_beam_tex(Color(1.0, 0.16, 0.2))
	blade.billboard = BaseMaterial3D.BILLBOARD_DISABLED; blade.axis = Vector3.AXIS_Y
	blade.shaded = false; blade.transparent = true
	blade.pixel_size = rng * WS / 100.0
	blade.scale = Vector3(1.0, 3.6, 1.0)
	_world.add_child(blade)
	var swp := _reg_tween()
	swp.tween_method(_laser_blade_step.bind(blade, origin, base_ang, rng, half_deg), 0.0, 1.0, 0.16).set_trans(Tween.TRANS_SINE)
	swp.tween_callback(blade.queue_free)

func _laser_blade_step(fr: float, blade: Sprite3D, origin: Vector2, base_ang: float, rng: float, half_deg: float) -> void:
	if not is_instance_valid(blade): return
	var a: float = base_ang + deg_to_rad(lerpf(-half_deg, half_deg, fr))
	var bd := Vector2(cos(a), sin(a))
	blade.rotation = Vector3(0.0, -a, 0.0)
	blade.position = _world_pos(origin + bd * (rng * 0.5), 0.16)
	var tr := Sprite3D.new()   # 淡拖尾
	tr.texture = blade.texture
	tr.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tr.axis = Vector3.AXIS_Y
	tr.shaded = false; tr.transparent = true
	tr.pixel_size = blade.pixel_size; tr.scale = blade.scale
	tr.rotation = blade.rotation; tr.position = blade.position
	tr.modulate = Color(1.0, 0.35, 0.38, 0.26)
	_world.add_child(tr)
	var tt := _reg_tween(); tt.tween_property(tr, "modulate:a", 0.0, 0.12); tt.tween_callback(tr.queue_free)

func _make_laser_slash_sheet(col: Color) -> ImageTexture:   # 激光斩弧6帧(尼拉式: 前缘白热扫过+后方拖尾smear; 生成→扫→峰→碎→散)
	var FW := 128; var FN := 6
	var img := Image.create(FW * FN, FW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(FW) * 0.5; var cy := float(FW) * 0.5; var R := float(FW) * 0.4
	for f in range(FN):
		var t := float(f) / float(FN - 1)
		var lead := deg_to_rad(lerpf(-80.0, 80.0, clampf(t * 1.35, 0.0, 1.0)))   # 前缘角扫过去
		var span := deg_to_rad(lerpf(35.0, 100.0, clampf(t * 1.25, 0.0, 1.0)))   # 拖尾角长
		var bright: float = (minf(t / 0.28, 1.0)) if t <= 0.55 else (maxf(0.0, 1.0 - (t - 0.55) / 0.45))
		var thick := float(FW) * (0.018 + 0.06 * sin(PI * clampf(t, 0.0, 1.0)))
		var ox := f * FW
		for y in range(FW):
			for x in range(FW):
				var dx := float(x) - cx; var dy := float(y) - cy
				var d := sqrt(dx * dx + dy * dy)
				var a := atan2(dy, dx)
				var behind := lead - a
				if behind < 0.0 or behind > span: continue
				var jag := sin(a * 13.0 + t * 5.0) * 2.2
				var dd := absf(d - (R + jag))
				if dd > thick: continue
				if t > 0.6 and sin(a * 17.0 + float(f) * 2.1) > lerpf(1.15, -0.2, (t - 0.6) / 0.4): continue
				var lead_b := 1.0 - clampf(behind / span, 0.0, 1.0)
				var edge := 1.0 - dd / thick
				var inten := edge * bright * (0.3 + 0.7 * lead_b)
				if inten <= 0.02: continue
				var whiteness := clampf(edge * 1.6, 0.0, 1.0) * (0.45 + 0.55 * lead_b)
				var c := col.lerp(Color(1, 1, 1), whiteness)
				c.a = clampf(inten * 1.05, 0.0, 1.0)
				img.set_pixel(ox + x, y, c)
	return ImageTexture.create_from_image(img)
func _make_laser_vblade_tex(col: Color) -> ImageTexture:   # 竖激光刃(白热芯+红光晕/尖顶): 尖朝上
	var W := 22; var H := 92
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(W - 1) / 2.0
	for y in range(H):
		var fy := float(y) / float(H - 1)
		var tap := (fy / 0.14) if fy < 0.14 else (1.0 if fy < 0.9 else (1.0 - fy) / 0.1)   # 尖顶+底收
		tap = clampf(tap, 0.0, 1.0)
		if tap <= 0.02: continue
		for x in range(W):
			var dx := absf(float(x) - cx) / (float(W) * 0.5)
			var core := clampf(1.0 - dx * 3.0, 0.0, 1.0)
			var glow := clampf(1.0 - dx, 0.0, 1.0)
			var c := Color(1, 1, 1).lerp(col, 1.0 - core)
			c.a = clampf((core + glow * 0.55) * tap, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
func _make_laser_beam_tex(col: Color) -> ImageTexture:   # 激光束(白热核+色光晕/两端尖), 沿+X
	var W := 100; var H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(H - 1) / 2.0
	for x in range(W):
		var fx := float(x) / float(W - 1)
		var taper := sin(PI * fx)
		if taper <= 0.02: continue
		for y in range(H):
			var dy := absf(float(y) - cy) / (float(H) * 0.5)
			var core := clampf(1.0 - dy * 3.2, 0.0, 1.0)
			var glow := clampf(1.0 - dy, 0.0, 1.0)
			var c := Color(1, 1, 1).lerp(col, 1.0 - core)
			c.a = clampf((core + glow * 0.55) * taper, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _laser_fan_sweep(origin: Vector2, dir: Vector2, rng: float, half_deg: float) -> void:   # 红激光扇形斩: 一排白热激光束错峰扫过弧
	var base_ang: float = atan2(dir.y, dir.x)
	var n := 9
	for i in range(n):
		var frac: float = float(i) / float(n - 1)
		var a: float = base_ang + deg_to_rad(lerpf(-half_deg, half_deg, frac))
		var bdir := Vector2(cos(a), sin(a))
		var beam := Sprite3D.new()
		beam.texture = _make_laser_beam_tex(Color(1.0, 0.2, 0.24))
		beam.billboard = BaseMaterial3D.BILLBOARD_DISABLED; beam.axis = Vector3.AXIS_Y
		beam.shaded = false; beam.transparent = true
		beam.pixel_size = rng * WS / 100.0
		beam.rotation = Vector3(0.0, -a, 0.0)
		beam.position = _world_pos(origin + bdir * (rng * 0.5), 0.14)
		beam.modulate = Color(1.0, 0.35, 0.35, 0.0)
		_world.add_child(beam)
		var bt := _reg_tween()
		bt.tween_interval(frac * 0.12)
		bt.tween_property(beam, "modulate:a", 0.98, 0.03)
		bt.tween_property(beam, "modulate:a", 0.0, 0.15)
		bt.tween_callback(beam.queue_free)
func _tick_laser(u: Dictionary, delta: float) -> void:   # 激光长刃p2eq_010: 独立计时器(按携带者攻速)每次扇形斩(用户)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_010": continue
		e["laser_t"] = float(e.get("laser_t", 0.0)) + delta
		if float(e["laser_t"]) < maxf(0.3, float(u.get("atk_interval", 1.0))): continue
		var t = _nearest_enemy(u)
		if t == null: continue
		e["laser_t"] = 0.0
		_eq_laser_sweep(u, t, _eq_si(int(e.get("star", 1))))

func _eq_laser_sweep(u: Dictionary, tgt: Dictionary, si: int) -> void:   # 扇形斩(120度/半径=射程,3★2×/朝目标)+回血; 只命中1→蓄力→竖劈冲击波
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var ang: float = -atan2(dir.y, dir.x)
	var base_rng: float = float(u.get("atk_range", 70.0))
	var rng: float = base_rng * (2.0 if si == 2 else 1.0)
	_anticipate(u)   # 预备
	_laser_blade_sweep(u, u["pos"], dir, rng, 60.0)   # 笔直红激光长刃平滑扫过扇形(带拖尾)
	_shake(JUICE_SHAKE_HEAVY)
	var cos60: float = cos(deg_to_rad(60.0))
	var hits: Array = []
	for o in _enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var d: float = rel.length()
		if d > rng: continue
		if dir.dot(rel / maxf(1.0, d)) < cos60: continue
		hits.append(o)
	var tot: int = 0
	for o in hits:
		var dd: int = _atk_dmg(u, [0.6, 1.0, 8.0][si], o) + [15, 32, 200][si]
		_apply_damage_from(u, o, dd, Color("#9bf0ff"), 0.0, false, true)
		tot += dd
	if tot > 0: _heal(u, tot * [0.35, 0.8, 1.0][si])
	if hits.size() == 1:
		var glow := Sprite3D.new()
		glow.texture = _make_fire_glow_tex()
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
		glow.modulate = Color(1.0, 0.28, 0.3, 0.0); glow.pixel_size = 0.02
		glow.position = _world_pos(u["pos"], 1.0)
		_world.add_child(glow)
		var gt := _reg_tween(); gt.tween_property(glow, "modulate:a", 0.9, 0.2); gt.parallel().tween_property(glow, "scale", Vector3(2.2, 2.2, 2.2), 0.2)
		var tele := Sprite3D.new()   # 蓄力预警线(细红激光, 指示竖劈路径)
		tele.texture = _make_laser_beam_tex(Color(1.0, 0.25, 0.28))
		tele.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tele.axis = Vector3.AXIS_Y
		tele.shaded = false; tele.transparent = true
		tele.pixel_size = (base_rng * 2.0) * WS / 100.0
		tele.rotation = Vector3(0.0, ang, 0.0)
		tele.position = _world_pos(u["pos"] + dir * base_rng, 0.1)
		tele.scale = Vector3(1.0, 0.35, 1.0); tele.modulate = Color(1.0, 0.3, 0.3, 0.0)
		_reg_tween().tween_property(tele, "modulate:a", 0.5, 0.18)
		await get_tree().create_timer(0.2).timeout
		if is_instance_valid(tele):
			var telf := _reg_tween()
			telf.tween_property(tele, "modulate:a", 0.0, 0.1)
			telf.tween_callback(tele.queue_free)
		if is_instance_valid(glow): glow.queue_free()
		if not u.get("alive", false): return
		_eq_laser_chop(u, hits[0], si, base_rng)

func _eq_laser_chop(u: Dictionary, tgt: Dictionary, si: int, base_range: float) -> void:   # 竖劈冲击波(同斩击伤害/宽80/移动2×射程/短暂击飞0.1s)
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var origin: Vector2 = u["pos"]
	var reach: float = base_range * 2.0
	_shake(JUICE_SHAKE_BIG)
	var wave := Sprite3D.new()
	wave.texture = _make_laser_vblade_tex(Color(1.0, 0.18, 0.22))   # 白热芯竖激光刃
	wave.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wave.shaded = false; wave.transparent = true
	wave.pixel_size = 0.06; wave.scale = Vector3(1.5, 2.4, 1.0)
	wave.modulate = Color(1.0, 0.28, 0.3, 0.95)
	_world.add_child(wave)
	var traveled: float = 0.0
	var last_tr: float = -100.0
	var hit: Array = []
	while traveled < reach and is_instance_valid(wave) and is_instance_valid(self):
		await get_tree().process_frame
		traveled += 550.0 * get_process_delta_time()
		wave.position = _world_pos(origin + dir * traveled, 0.9)
		if traveled - last_tr >= 45.0:   # 剑气拖尾: 每隔45码留一道淡残影(在刃后, 不糊白热芯)
			last_tr = traveled
			var tr := Sprite3D.new()
			tr.texture = wave.texture
			tr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; tr.shaded = false; tr.transparent = true
			tr.pixel_size = wave.pixel_size; tr.scale = wave.scale * 0.9
			tr.position = wave.position; tr.modulate = Color(1.0, 0.35, 0.4, 0.3)
			_world.add_child(tr)
			var tt := _reg_tween(); tt.tween_property(tr, "modulate:a", 0.0, 0.22); tt.tween_callback(tr.queue_free)
		for o in _enemies_of(u):
			if o in hit or not o.get("alive", false): continue
			if (o["pos"] - origin).dot(dir) <= traveled and _on_line(origin, dir, o["pos"], 80.0):
				hit.append(o)
				_apply_damage_from(u, o, _atk_dmg(u, [0.6, 1.0, 8.0][si], o) + [15, 32, 200][si], Color("#9bf0ff"), 0.0, false, true)
				_knockback(u, o, 0.0, 0.2, 0.0)
	if is_instance_valid(wave):
		var wf := _reg_tween(); wf.tween_property(wave, "modulate:a", 0.0, 0.15); wf.tween_callback(wave.queue_free)

func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:   # 宽刃弯刀(用户改造·剑魔Q式): 预警环形扇区(500~800码60度)→黄色月光斩→伤害
	var cen := Vector2.ZERO; var ec := 0   # 方向朝敌方整体(质心), 角度对携带者稳定(用户)
	for _o in _enemies_of(src):
		if _o.get("alive", false): cen += _o["pos"]; ec += 1
	if ec > 0: cen /= float(ec)
	var dir: Vector2 = (cen - src["pos"]).normalized() if ec > 0 else (tgt["pos"] - src["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	var ang: float = -atan2(dir.y, dir.x)
	var tel := Sprite3D.new()   # 1) 预警扇区(脉动黄)
	tel.texture = _make_sector_tex(Color(1.0, 0.78, 0.2, 1.0))
	tel.billboard = BaseMaterial3D.BILLBOARD_DISABLED; tel.axis = Vector3.AXIS_Y
	tel.shaded = false; tel.transparent = true
	tel.pixel_size = 0.15   # 128px=800码
	tel.rotation = Vector3(0.0, ang, 0.0)
	tel.position = _world_pos(src["pos"] + dir * 400.0, 0.08)
	tel.modulate = Color(1.0, 0.78, 0.2, 0.0)
	_world.add_child(tel)
	var tt := _reg_tween()
	tt.tween_property(tel, "modulate:a", 0.5, 0.12)
	for _p in range(2):
		tt.tween_property(tel, "modulate:a", 0.28, 0.14)
		tt.tween_property(tel, "modulate:a", 0.6, 0.14)
	await get_tree().create_timer(0.56).timeout
	if not src.get("alive", false):
		if is_instance_valid(tel): tel.queue_free()
		return
	if is_instance_valid(tel):
		var tf := _reg_tween(); tf.tween_property(tel, "modulate:a", 0.0, 0.12); tf.tween_callback(tel.queue_free)
	_shake(JUICE_SHAKE_HEAVY)   # 2) 黄色月光斩(弯月闪电 5帧逐帧, 放大, 用户)
	var moon := Sprite3D.new()
	moon.texture = _make_moon_sheet(Color(1.0, 0.88, 0.25))
	moon.hframes = 5; moon.frame = 0
	moon.billboard = BaseMaterial3D.BILLBOARD_DISABLED; moon.axis = Vector3.AXIS_Y
	moon.shaded = false; moon.transparent = true
	moon.pixel_size = 0.15   # 128px=800码, 与预警扇区同尺寸
	moon.rotation = Vector3(0.0, ang, 0.0)
	moon.position = _world_pos(src["pos"] + dir * 400.0, 0.12)   # apex在携带者, 与预警扇区同位置→斩击必在区内
	_world.add_child(moon)
	var mf := _reg_tween()   # 逐帧播 5帧
	for _fi in range(5):
		mf.tween_callback(_set_sprite_frame.bind(moon, _fi))
		mf.tween_interval(0.11)   # 放慢帧速(用户)
	mf.tween_callback(moon.queue_free)
	var cos30: float = cos(deg_to_rad(30.0))   # 3) 伤害(斩击命中扇区内敌)
	var hits: Array = []
	for o in _enemies_of(src):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - src["pos"]
		var dist: float = rel.length()
		if dist < 500.0 or dist > 800.0: continue
		if dir.dot(rel / maxf(1.0, dist)) < cos30: continue
		hits.append(o)
	var mult: float = ([2.0, 2.5, 3.0][si]) if hits.size() <= 1 else 1.0
	for o in hits:   # 同帧两段同时结算: 物理(红)+真实(白); 飘字各自随机抛物散开(不叠, 无延时)
		_apply_damage_from(src, o, int(_atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#ff5a5a"), 0.0, false, true)
		_apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#ffffff"), 0.0, true, true)
# 灼热火珊瑚 023(主动满法力)
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:   # 灼热火珊瑚023主动: 蓄力→挥出60°扇形火焰波(缓移550码,边挥边扩)→接触敌施60灼烧
	if not src.get("alive", false): return
	var es := _enemies_of(src)
	var dir := Vector2.RIGHT
	if not es.is_empty():
		var cen := Vector2.ZERO
		for o in es: cen += o["pos"]
		dir = (cen / float(es.size()) - src["pos"]).normalized()
	_anticipate(src); _shake(JUICE_SHAKE_HEAVY)   # 蓄力
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(self) or not src.get("alive", false): return
	var origin: Vector2 = src["pos"]
	var wave := Sprite3D.new()   # 橙火弯月波(躺平朝dir, 边挥边扩)
	wave.texture = _make_qi_texture(Color(1.0, 0.5, 0.15))
	wave.billboard = BaseMaterial3D.BILLBOARD_DISABLED; wave.axis = Vector3.AXIS_Y; wave.shaded = false; wave.transparent = true
	wave.pixel_size = 0.06; wave.rotation.y = -atan2(dir.y, dir.x); wave.modulate = Color(1.0, 0.58, 0.22)   # 橙火色
	wave.position = _world_pos(origin, 0.4)
	_world.add_child(wave)
	var hit: Array = []
	var traveled := 0.0
	var half := deg_to_rad(30.0)   # 60°扇形半角
	while traveled < 550.0 and is_instance_valid(wave) and is_instance_valid(self):
		await get_tree().process_frame
		traveled += 320.0 * get_process_delta_time()   # 缓慢外移
		wave.position = _world_pos(origin + dir * traveled, 0.4)
		wave.scale = Vector3(2.2 + traveled / 550.0 * 4.5, 3.2, 1.0)   # 边挥边扩
		for o in _enemies_of(src):
			if o in hit: continue
			var rel: Vector2 = o["pos"] - origin
			if rel.dot(dir) <= 0.0: continue
			if absf(rel.angle_to(dir)) > half: continue   # 60°扇形内
			if absf(rel.length() - traveled) > 65.0: continue   # 波前带
			hit.append(o)
			_apply_dot_stacks(o, "burn", 60, src)
			_skill_ring(o["pos"], Color(1.0, 0.5, 0.2, 0.6), 46.0)
	if is_instance_valid(wave):
		var tw := _reg_tween(); tw.tween_property(wave, "modulate:a", 0.0, 0.2); tw.tween_callback(wave.queue_free)

# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
func _eq_on_target(u: Dictionary, src: Dictionary, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_013", "p2eq_014":   # 受击硬化: +def/mr (cap20层); 013满层给护盾
				var cur: int = int(stt.get("harden_stacks", 0))
				if cur < 20:
					cur += 1
					var inc: float = float(stt.get("harden_inc", 1.0))
					u["base_def"] += inc; u["base_mr"] += inc
					_recalc_stats(u)
					stt["harden_stacks"] = cur
					if cur >= 20 and not bool(stt.get("harden_given", false)):
						if float(stt.get("harden_shield", 0.0)) > 0.0:
							_grant_shield(u, float(stt["harden_shield"]))
						# 013 3★: 叠满硬化层→把累积的护甲魔抗(20层×inc)分给全队 (一次)
						if iid == "p2eq_013" and si == 2:
							var acc: float = 20.0 * inc   # 3★ inc=2.0 → 40护甲+40魔抗
							for o in _allies_of(u):
								if o == u: continue
								o["base_def"] += acc; o["base_mr"] += acc; _recalc_stats(o)
						stt["harden_given"] = true
			"p2eq_015":   # 荆棘海胆: 反伤真伤 + 施流血给攻击者
				if src.get("alive", false) and src["side"] != u["side"]:
					var refl: float = float(dmg) * float(stt.get("reflect_pct", 0.10))
					if refl >= 1.0:
						_apply_damage_from(u, src, int(refl), Color("#c9a36b"), 0.0, true, true)   # 反伤=真实伤害跳白字(原_raw_lose静默不跳数字=bug); from_equip防循环
					_apply_dot_stacks(src, "bleed", maxi(1, roundi(float(stt.get("reflect_bleed", 2.0)))), u)
			"p2eq_017":   # 不沉之锚: 每次受伤→治疗生命%最低友军 (1/2/15%自身maxHp), 累积满100→+1沉锚充能
				var heal_amt: float = u["maxHp"] * [0.01, 0.02, 0.15][si]
				# 生命百分比最低的友军 (含自己)
				var low = null; var lv := INF
				for o in _allies_of(u):
					var p: float = o["hp"] / maxf(1.0, o["maxHp"])
					if p < lv: lv = p; low = o
				if low != null:
					_heal(low, heal_amt)
				var acc: float = float(stt.get("anchor_accum", 0.0)) + heal_amt
				while acc >= 100.0:
					acc -= 100.0
					stt["anchor_charges"] = int(stt.get("anchor_charges", 0)) + 1
				stt["anchor_accum"] = acc
		u["eq_state"][iid] = stt

# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
func _eq_on_dodge(u: Dictionary) -> void:
	for e in u.get("equips", []):
		if str(e["id"]) == "p2eq_046":   # 幽灵墨鱼: 闪避→永久护盾
			var stt: Dictionary = u["eq_state"].get("p2eq_046", {})
			_grant_shield(u, float(stt.get("ghost_shield", 30.0)))
			_shield_dome(u)   # 专属护盾罩(不复用faint _shield_bubble)

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_bloodletting(u: Dictionary, si: int) -> void:   # 饮血护符坠(011): 一段一段连斩(每刀~0.11s顺序打出,各命中随机敌,衰减0.85^k); 吸血溢出转盾结尾汇总
	var n: int = [5, 6, 8][si]
	var sh0: float = u["shield"]
	for k in range(n):
		if not u.get("alive", false): break
		var es := _enemies_of(u)
		if es.is_empty(): break
		var o = es[randi() % es.size()]
		var decay: float = pow(0.85, k)
		_blood_slash(u["pos"], o["pos"], 0.0)   # 这一刀立即砍
		_apply_damage_from(u, o, int((_atk_dmg(u, [0.5, 0.7, 1.0][si], o) + [40, 50, 70][si]) * decay), Color("#ff8aa0"), 0.33, false, true)
		await get_tree().create_timer(0.3).timeout   # 一段一段: 每0.3s一刀
	if not is_instance_valid(self): return
	var shg: int = int(u["shield"] - sh0)   # 连斩吸血溢出转的盾, 结尾汇总一次
	if shg > 0: _float_text(u["pos"] + Vector2(28, -46), "护盾+" + str(shg), Color("#8ad7ff"), false, "shield")

func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_027":   # 电棍: 施法后电击随机敌+眩晕, 消耗1层电荷(用户描述)
				pass
			"p2eq_017":   # 不沉之锚: 锚击移到_eq_on_basic_attack(普攻消耗1充能, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_006":   # 千刃风暴: 移到每7秒 _tick_sword_storm(用户); on_cast不处理
				pass
			"p2eq_007":   # 锈蚀阔剑: 移到每6秒 _tick_broadsword(用户); on_cast不处理
				pass
			"p2eq_008":   # 双穿珊瑚刺: 移到每6秒 _tick_coral(用户); on_cast不处理
				pass
			"p2eq_011":   # 饮血护符坠: 一段一段顺序连斩(async, 每刀~0.11s), 见 _eq_bloodletting
				_eq_bloodletting(u, si)
			"p2eq_014":   # 深海堡垒甲: 汲取移到 _tick_fortress(硬化满20层后每8秒汲取, 用户2026-07-02); on_cast不处理
				pass
			"p2eq_022":   # 余烬燃油瓶: 蓄力→投掷火瓶→命中灼烧+真火 (_eq_fuel_throw)
				_eq_fuel_throw(u, si)
			"p2eq_028":   # 冰霜冻露瓶: 对最近敌魔伤+冰寒(减速)
				_eq_ice_throw(u, si)
			"p2eq_030":   # 迷你水晶球A: 朝目标无限直线连发2/2/3段水晶光束(错峰), 每段全线敌魔法伤+1层水晶
				var t4 = _nearest_enemy(u)
				if t4 != null:
					var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
					if dir2 == Vector2.ZERO: dir2 = Vector2.RIGHT
					for _seg in range([2, 2, 3][si]):
						var twc := _reg_tween()
						twc.tween_interval(float(_seg) * 0.2)   # 施加水晶间隔0.2s(用户)
						twc.tween_callback(_crystal_line_seg.bind(u, si, dir2))
			"p2eq_031":   # 迷你水晶球B: 施法→水晶射线360度扫一圈(1.5s), 扫到即魔法伤+1层水晶(3★引爆波及邻格)
				_eq_crystal_sweep(u, si)
			"p2eq_039":   # 竹制弓箭: 充能内→强化攻击+自回血+永久+maxHP
				var stt2: Dictionary = u["eq_state"].get("p2eq_039", {})
				if int(stt2.get("bamboo_charges", 0)) > 0:
					stt2["bamboo_charges"] = int(stt2["bamboo_charges"]) - 1
					var t5 = _nearest_enemy(u)
					if t5 != null:
						_spawn_bamboo_arrow(u, t5, [25, 30, 35][si] + int(u["maxHp"] / HP_MULT * 0.20))
					_heal(u, u["maxHp"] * 0.20)
					_heal_burst(u, 1.0)
					var grow: float = [90.0, 95.0, 100.0][si] * HP_MULT
					u["maxHp"] += grow; u["hp"] += grow
					u["eq_state"]["p2eq_039"] = stt2
			"p2eq_048":   # 黄铜手铳: 依次射N发, 每发命中直线首敌(错峰: 枪口闪+曳光+火花)
				var dir48: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var mul48: float = [0.5, 0.54, 0.6][si]
				var fire48 := func():
					if not u.get("alive", false): return
					var ft48 = _eq_first_in_line(u, dir48, 36.0)
					if ft48 == null: return
					_muzzle_flash(u["pos"], dir48, Color("#ffe08a"))
					_spawn_eq_bolt(u, ft48, _atk_dmg(u, mul48, ft48), "res://assets/sprites/vfx/bullet.png", Color("#fff0b0"), false, 0, 0.026)   # 真子弹依次飞出(命中结算伤+火花)
				_queue_shots([4, 5, 6][si], 0.08, fire48, u)
			"p2eq_049":   # 连发弩: 朝最远敌方向依次射N发, 首敌命中(可被前排挡), 按已损血加伤; 弩矢弹道
				var far49 := _eq_farthest_enemies(u, false)
				if not far49.is_empty():
					var dir49: Vector2 = (far49[0]["pos"] - u["pos"]).normalized()
					var fire49 := func():
						if not u.get("alive", false): return
						var ft49 = _eq_first_in_line(u, dir49, 42.0)
						if ft49 == null: return
						var lost49: float = clampf((1.0 - ft49["hp"] / ft49["maxHp"]) / 0.3, 0.0, 1.0)
						_muzzle_flash(u["pos"], dir49, Color("#d8f0a8"))
						_spawn_eq_bolt(u, ft49, _atk_dmg(u, lerpf(0.8, 1.3, lost49), ft49), "res://assets/sprites/vfx/crossbow-bolt.png", Color("#eaffd0"))
					_queue_shots([1, 2, 3][si], 0.12, fire49, u)
			"p2eq_050":   # 幽灵加特林: 依次快射N发随机分布+减甲(累计上限; 枪口连闪+曳光雨)
				var g_shred: float = [1.0, 2.0, 3.0][si]
				var g_cap: float = [15.0, 25.0, 40.0][si]   # 该效果对单个目标累计减甲上限
				var g_mul: float = [0.1, 0.12, 0.14][si]
				var fire50 := func():
					if not u.get("alive", false): return
					var es50 := _enemies_of(u)
					if es50.is_empty(): return
					var o50 = es50[randi() % es50.size()]
					_muzzle_flash(u["pos"], (o50["pos"] - u["pos"]), Color("#d0ffff"))
					_spawn_eq_bolt(u, o50, _atk_dmg(u, g_mul, o50), "res://assets/sprites/vfx/bullet.png", Color("#d0ffff"), false, 0, 0.02)   # 真青幽灵弹依次快射(命中结算伤+火花)
					var g_acc: float = float(o50.get("gatling_shred_acc", 0.0))
					if g_acc < g_cap:
						var g_dec: float = minf(g_shred, g_cap - g_acc)
						o50["base_def"] = maxf(0.0, o50["base_def"] - g_dec); o50["gatling_shred_acc"] = g_acc + g_dec; _recalc_stats(o50)
				_queue_shots([20, 30, 60][si], 0.03, fire50, u)
			"p2eq_051":   # 激光手枪: 穿透红激光(白核+红辉)一横排首敌满伤+流血, 身后敌半伤半流血
				var dir4: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var first = _eq_first_in_line(u, dir4, 50.0)
				if first != null:
					var endp51: Vector2 = first["pos"] + dir4 * 340.0
					_muzzle_flash(u["pos"], dir4, Color("#ff5a72"))
					_laser_beam(u["pos"], endp51, Color(1.0, 0.24, 0.36, 0.85), 0.22, 0.22)   # 红辉(宽)
					_laser_beam(u["pos"], endp51, Color(1.0, 0.92, 0.94, 0.95), 0.07, 0.14)   # 白核(细)
					_apply_damage_from(u, first, _atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
					_apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
					_hit_spark(first)
					for o in _enemies_of(u):
						if o != first and _on_line(first["pos"], dir4, o["pos"], 50.0):
							_apply_damage_from(u, o, _atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
							_apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si] * 0.5)), u)   # 身后50%流血
			"p2eq_053":   # 霰弹贝古: 枪口大闪→40°扇形弹珠齐射, 被8+发命中→眩晕
				var dir53: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				_muzzle_flash(u["pos"], dir53, Color("#ffe0a0"))
				_skill_ring(u["pos"] + dir53 * 22.0, Color(1.0, 0.85, 0.4, 0.7), 26.0)
				var hitc: Dictionary = {}
				for _s in range([12, 14, 18][si]):
					var es3 := _enemies_of(u)
					if es3.is_empty(): break
					var o = es3[randi() % es3.size()]
					var spr53: Vector2 = dir53.rotated(randf_range(-0.35, 0.35)) * 260.0
					_shotgun_pellet(u["pos"], u["pos"] + spr53, Color(1.0, 0.86, 0.5, 0.95))   # 小铅丸喷出
					_apply_damage_from(u, o, _atk_dmg(u, 0.22, o), Color("#ffd07a"), 0.0, false, true)
					hitc[o] = int(hitc.get(o, 0)) + 1
				for o in hitc:
					if int(hitc[o]) >= 8: _freeze(o, CTRL_SEC)
			"p2eq_057":   # 狙击长管: 对最低血%敌沿途敌, 击杀则再开
				_eq_sniper(u, si, 0)
			"p2eq_010":   # 激光长刃: 移到独立计时器 _tick_laser(第二普攻扇形斩); on_cast不处理
				pass

# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv := _add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		_consume_stacks(o, "p2crystal")
		_crystal_stack_set(o, 0)
		_crystal_detonate(o["pos"])
		_apply_damage_from(src, o, _resolve_dmg(src, float(o["maxHp"]) * [0.14, 0.17, 0.20][si], o, true), Color("#bfa8ff"), 0.0, false, true)
	else:
		_crystal_stack_set(o, lv)   # 更新可视层数

# 狙击长管 057: 递归开枪
func _eq_sniper(u: Dictionary, si: int, depth: int) -> void:
	if depth >= 12:
		return
	var low = null; var lv := INF
	for o in _enemies_of(u):
		var p: float = o["hp"] / o["maxHp"]
		if p < lv: lv = p; low = o
	if low == null:
		return
	var dir: Vector2 = (low["pos"] - u["pos"]).normalized()
	_muzzle_flash(u["pos"], dir, Color("#ff5a5a"))
	var _snd: float = 1.5 if OS.has_environment("XDBG") else 0.28
	var _tip: Vector2 = low["pos"] + dir * 150.0
	_laser_beam(u["pos"], _tip, Color(1.0, 0.24, 0.28, 0.82), 0.17, _snd, 1.0)          # 粗红外辉(醒目狙击曳光)
	_laser_beam(u["pos"], _tip, Color(1.0, 0.92, 0.86, 0.96), 0.06, _snd * 0.85, 1.02)   # 白热细核(高速弹道感)
	_hit_spark(low)
	var killed := false
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			_apply_damage_from(u, o, _atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ff4444"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper(u, si, depth + 1)

# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, _victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		if str(e["id"]) == "p2eq_004":   # 暴君之牙: 处决后回20龟能 (无龟能单位改回40血)
			if _has_energy_system(killer):
				_eq_grant_energy(killer, 20.0)
			else:
				_heal(killer, 40.0)

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 (+ 左轮052 敌亡补弹)
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_033":   # 复活海螺: 彻底阵亡→原位变形成小虫(通用打法/攻速0.65) + 亡灵变形演出
				_conch_transform(u["pos"])
				var worm = _spawn_summon(u, "worm", [400.0, 900.0, 5000.0][si], [30.0, 55.0, 200.0][si], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})   # 小虫只有星级无等级(去_lvl_mult), 数值即实际
				if worm != null:
					worm["pos"] = u["pos"]
					worm["atk_interval"] = 1.0 / 0.65
					if is_instance_valid(worm["sprite"]):
						worm["sprite"].position = _world_pos(u["pos"], GROUND_LIFT)
						var wsc: Vector3 = worm["sprite"].scale
						worm["sprite"].scale = Vector3.ZERO
						var wtw := _reg_tween()
						wtw.tween_interval(0.12)
						wtw.tween_property(worm["sprite"], "scale", wsc, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
			"p2eq_035":   # 黄铜齿轮: 死亡不销毁不结算(改战斗结束 _settle_gears 统一折币)
				pass
	# 左轮052: 任何敌人阵亡 → 对方(u的敌方)持左轮的存活单位 +1发子弹 (上限6)
	for o in _units:
		if o["alive"] and o["side"] != u["side"]:
			for e2 in o.get("equips", []):
				if str(e2["id"]) == "p2eq_052":
					var rst: Dictionary = o["eq_state"].get("p2eq_052", {})
					rst["revolver_bullets"] = mini(6, int(rst.get("revolver_bullets", 0)) + 1)
					o["eq_state"]["p2eq_052"] = rst

# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
func _eq_check_hp_threshold(u: Dictionary) -> void:
	if u.get("hp50_fired", false) or u["hp"] > u["maxHp"] * 0.5 or not u["alive"]:
		return
	var fired := false
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_044":   # 深海项链: 首次<50%救命回血(龟上半身绿光脉动, 用户: 简单绿光即可, 不复用037魔法阵)
				_heal(u, u["maxHp"] * [0.12, 0.27, 0.40][si]); fired = true
				_heal_body_glow(u)
			"p2eq_045":   # 珍珠耳环: 首次<50%救命回血(龟身绿光)+抛物线火球
				_heal(u, u["maxHp"] * [0.15, 0.29, 0.65][si])
				_heal_ascend(u)   # 绿光环上浮(045专属, 不复用044)
				var balls: int = [1, 1, 2][si]
				var es := _enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_spawn_fireball(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), [30, 70, 150][si])
					_skill_ring(o["pos"], Color(1.0, 0.45, 0.12, 0.6), 50.0)   # 火球爆裂环
				fired = true
	if fired:
		u["hp50_fired"] = true

# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
func _eq_tick(u: Dictionary, delta: float) -> void:
	u["eq_timer"] = u.get("eq_timer", 0.0) + delta
	if u["eq_timer"] < EQ_TICK:
		return
	u["eq_timer"] = 0.0
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_001":   # 锈蚀短剑: 移到每帧 _tick_rustblade (每3s就绪 + 100码射程内有敌即劈); 周期tick不处理
				pass
			"p2eq_012":   # 龟苓膏块: 移到 _tick_jelly (每4s, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_016":   # 铁壁盾: 全队盾移到 _tick_ironwall(每5秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_018":   # 守护贝壳: 自回血移到 _tick_shell(每8秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_019":   # 海葵药膏: 移到 _tick_anemone(每7秒, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_020":   # 哑铃: 移到 _tick_dumbbell(每10秒编排:锻炼锁攻锁充能→掷哑铃击退, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_021":   # 守护贝母: 移到 _tick_barnacle(每5秒连接→自己+最高攻友军 +10龟能+10%攻速本场, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙直线扫射
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 移到每帧 _tick_thunder(每4秒/道间错峰/大雷/伤害在雷中段跳, 用户2026-07-02); 周期tick不处理
				pass
			"p2eq_027":   # 电棍: 移到on_cast(施法后电击, 用户描述); 周期tick不处理
				pass
			"p2eq_035":   # 黄铜齿轮: 齿轮层改每6s(_tick_gear), 周期tick不处理
				pass
			"p2eq_034":   # 玩偶小熊: 移到每帧 _tick_doll(4s派小熊 + 满层蓄力召大熊); 周期tick不处理
				pass
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				_egg_add_progress(u, 5.0)   # 每周期+5 (其余源: 敌死+10/己死+15/造成×0.1/承受×0.1)
			"p2eq_042":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_043":   # 海浪护符: 每周期+1巨浪层, 满→横排扫敌我
				stt["wave"] = int(stt.get("wave", 0)) + 1
				if int(stt["wave"]) >= [3, 2, 2][si]:
					stt["wave"] = 0
					_eq_water_wave(u, si)
			"p2eq_052":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_037":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_038":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_040":   # 移到 _tick_eq_intervals(自定义间隔)
				pass
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				if OS.has_environment("EQDEMO_EQUIP") and str(OS.get_environment("EQDEMO_EQUIP")) == "p2eq_056":   # demo: 无击飞源→强制标靶看飞镖volley
					for _e in _enemies_of(u):
						if _e.get("alive", false):
							_mark_vfx(_e, 5.0, Color("#ffa040")); _e["eq_target_until"] = _t + 5.0
				for o in _enemies_of(u):
					if _t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						o["_mark_until"] = _t   # 靶子锁定框消失
						_spawn_eq_bolt(u, o, _atk_dmg(u, [1.5, 3.0, 9.0][si], o) + [130, 190, 600][si], "res://assets/sprites/vfx/dart.png", Color("#ffe0b0"), true, maxi(1, roundi(u["atk"] * 0.1)))
		u["eq_state"][iid] = stt

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
# 024 喷火龙(定稿场景): 龙低空沿"敌方质心方向的线"掠射, 边飞边点燃 burn-loop 真像素火燃烧带, 命中敌=fx_explosion金爆+着火+魔伤, 掠过友=绿治疗环
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es := _enemies_of(u)
	if es.is_empty():
		return
	var cen := Vector2.ZERO
	for o in es:
		cen += o["pos"]
	cen /= float(es.size())
	var anchor = es[0]                               # 瞄最靠质心的敌人=保证龙穿过它(不是瞄质心从两敌之间缝里穿)
	var abest := INF
	for o in es:
		var dd: float = o["pos"].distance_squared_to(cen)
		if dd < abest:
			abest = dd; anchor = o
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var start: Vector2 = u["pos"]
	var reach: float = 340.0                         # 飞到最远敌人身后(真穿过去), 不再固定760码够不着
	for o in es:
		reach = maxf(reach, (o["pos"] - start).dot(dir) + 260.0)
	var end: Vector2 = start + dir * reach
	var total: float = maxf(1.0, start.distance_to(end))
	var dur: float = clampf(reach / 480.0, 1.6, 2.6)  # 按距离定时长=恒定速度
	_anticipate(u)
	_dragon_windup(start)                            # 前摇: 召唤点聚火蓄能(~0.55s)再爆发出龙(修"一下冒出来")
	var twd := _reg_tween()
	twd.tween_interval(0.55)
	twd.tween_callback(_dragon_unleash.bind(u, si, start, end, dir, total, dur))

# 蓄力后爆发: 召唤火爆+震屏+预警线+放龙+结算(同线敌=魔法伤+灼烧, 同线友=回血)
func _dragon_unleash(u: Dictionary, si: int, start: Vector2, end: Vector2, dir: Vector2, total: float, dur: float) -> void:
	_dragon_summon_burst(start)
	_shake(0.12)
	_spawn_fire_dragon(start, end, dur)
	var expl: Texture2D = load("res://assets/sprites/vfx/fx_explosion.png")
	var burn_tex: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	# 火柱扫到谁那一刻才对谁结算(非召唤即一次性算完): 延时=火柱沿线到达该单位的时间
	for o in _enemies_of(u):
		if _on_line(start, dir, o["pos"], 88.0):
			var d_e: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			var twe := _reg_tween()
			twe.tween_interval(d_e)
			twe.tween_callback(_dragon_hit_enemy.bind(u, o, si, expl, burn_tex))
	for o in _allies_of(u):
		if _on_line(start, dir, o["pos"], 88.0):
			var d_a: float = clampf((o["pos"] - start).dot(dir) / total, 0.0, 1.0) * dur
			var twa := _reg_tween()
			twa.tween_interval(d_a)
			twa.tween_callback(_dragon_heal_ally.bind(u, o, si))

# 火柱扫到敌人那一刻: 魔法伤害+灼烧+金爆+着火 (同步, 数字跟火柱一起)
func _dragon_hit_enemy(u: Dictionary, o: Dictionary, si: int, expl: Texture2D, burn: Texture2D) -> void:
	if not o.get("alive", false):
		return
	var base_e: float = u["atk"] * [0.7, 1.0, 2.0][si] + float([50, 120, 1500][si])
	_apply_damage_from(u, o, _resolve_dmg(u, base_e, o, true), Color("#c86bff"), 0.0, false, true)   # 魔法伤害
	_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
	if expl != null:
		play_sheet_vfx(o["pos"], expl, 8, 150.0, 0.5, 0.7)
	_ground_fire(o["pos"], burn, 82.0)

# 火柱扫到友军那一刻: 回血+绿治疗环
func _dragon_heal_ally(u: Dictionary, o: Dictionary, si: int) -> void:
	if not o.get("alive", false):
		return
	_heal(o, u["atk"] * [0.7, 1.0, 2.0][si] + float([70, 150, 1000][si]))
	_skill_ring(o["pos"], Color(0.45, 1.0, 0.55, 0.55), 46.0)

# 前摇: 召唤点火球聚大变亮 + 火花从外向内收束 + 脉动环 (蓄力感)
func _dragon_windup(pos2d: Vector2) -> void:
	var tex := _make_fire_glow_tex()
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	var orb := Sprite3D.new()
	orb.texture = tex
	orb.modulate = Color(1.0, 0.62, 0.22, 0.0)
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orb.shaded = false
	orb.transparent = true
	orb.pixel_size = (26.0 * WS) / tw_w
	orb.position = _world_pos(pos2d, 1.3)
	_world.add_child(orb)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "pixel_size", (155.0 * WS) / tw_w, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(orb, "modulate:a", 1.0, 0.5)
	tw.chain().tween_callback(orb.queue_free)
	for k in range(8):
		_windup_spark(pos2d, TAU * float(k) / 8.0)
	_skill_ring(pos2d, Color(1.0, 0.5, 0.2, 0.55), 66.0)

func _windup_spark(pos2d: Vector2, ang: float) -> void:
	var tex := _make_fire_glow_tex()
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.78, 0.4, 0.95)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (24.0 * WS) / tw_w
	var from: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * 135.0
	spr.position = _world_pos(from, 1.3)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_spark_converge.bind(spr, from, pos2d), 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(spr, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(spr.queue_free)

func _spark_converge(t: float, spr: Sprite3D, from: Vector2, to: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = _world_pos(from.lerp(to, t), 1.3)

# 龙贴图(dragon-fire.png)低空沿线掠射 + burn-loop 真像素火燃烧带(龙飞到才点燃, 各烧一会再灭)
func _spawn_fire_dragon(start2d: Vector2, end2d: Vector2, dur: float) -> void:
	var dragon_tex: Texture2D = load("res://assets/sprites/vfx/dragon-fly.png")   # PixelLab 5帧振翅
	if dragon_tex != null:
		var d := Sprite3D.new()
		d.texture = dragon_tex
		d.hframes = 5
		d.frame = 0
		d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		d.shaded = false
		d.transparent = true
		d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		d.flip_h = (end2d.x < start2d.x)               # 素材朝右; 往左飞则翻转
		d.pixel_size = (215.0 * WS) / (float(maxi(1, int(dragon_tex.get_width()))) / 5.0)
		d.position = _world_pos(start2d, 2.9)          # 龙在天上(高空)
		_world.add_child(d)
		d.modulate = Color(1, 1, 1, 0)                 # 从召唤火里淡入现身
		var tfade := _reg_tween()
		tfade.tween_property(d, "modulate:a", 1.0, 0.22)
		var tw := _reg_tween()
		tw.tween_method(_dragon_fly_step.bind(d, start2d, end2d), 0.0, 1.0, dur)
		tw.tween_callback(d.queue_free)
		var tf := _reg_tween()                       # 振翅: 乒乓循环5帧(~4次/秒)
		tf.tween_method(_dragon_flap_frame.bind(d), 0.0, 32.0 * dur, dur)
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	var perp: Vector2 = (end2d - start2d).orthogonal().normalized()
	for i in range(1, 19):                           # 燃烧带: 沿线真像素火, 大小/横向随机=有机火带(非机械等距), 龙飞到才点燃
		var f: float = float(i) / 19.0
		var jit: Vector2 = perp * randf_range(-28.0, 28.0)
		_delayed_ground_fire(start2d.lerp(end2d, f) + jit, burn, randf_range(74.0, 128.0), f * dur * 0.9)
	_dragon_mouth_jet(start2d, end2d, dur)           # 龙嘴喷火(从嘴喷向地面)

func _dragon_fly_step(p: float, spr: Sprite3D, start2d: Vector2, end2d: Vector2) -> void:
	if is_instance_valid(spr):
		spr.position = _world_pos(start2d.lerp(end2d, p), lerpf(2.9, 3.5, clampf(p * 2.5, 0.0, 1.0)) + sin(p * PI) * 0.18)

func _dragon_flap_frame(v: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		var seq := [0, 1, 2, 3, 4, 3, 2, 1]           # 乒乓: 翅上→下→上
		spr.frame = seq[int(v) % 8]

# 召唤火爆: 携带者处火环扩散+火焰爆闪+火花, 龙从中现身(修"凭空出现啥也没有")
func _dragon_summon_burst(pos2d: Vector2) -> void:
	_skill_ring(pos2d, Color(1.0, 0.55, 0.2, 0.75), 105.0)
	_skill_ring(pos2d, Color(1.0, 0.85, 0.45, 0.6), 64.0)
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.8, 0.45, 1.0)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	var tw_w: float = float(maxi(1, int(tex.get_width())))
	spr.pixel_size = (80.0 * WS) / tw_w
	spr.position = _world_pos(pos2d, 1.1)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "pixel_size", (255.0 * WS) / tw_w, 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(spr.queue_free)
	_impact_particles(pos2d, 1.0)

# 龙嘴喷火: 沿飞行线, 从龙嘴(前方)持续喷真像素火落向地面 = "喷火"读感
func _dragon_mouth_jet(start2d: Vector2, end2d: Vector2, dur: float) -> void:
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	if burn == null:
		return
	var n := 30
	for i in range(n):
		var p: float = float(i) / float(n)
		var col_pos: Vector2 = start2d.lerp(end2d, p)               # 火柱落点=龙嘴正下方(在掠射线上)
		var top_h: float = lerpf(2.9, 3.5, clampf(p * 2.5, 0.0, 1.0)) + 0.25   # 火柱顶=龙嘴高度
		var tw := _reg_tween()
		tw.tween_interval(p * dur * 0.95)
		tw.tween_callback(_spawn_fire_pillar.bind(burn, col_pos, top_h))

# 一根竖直火柱: 从地面到龙嘴, 同一x竖向叠火焰(=直的), 底大顶小, 短暂显现再淡
func _spawn_fire_pillar(burn: Texture2D, pos2d: Vector2, top_h: float) -> void:
	if burn == null:
		return
	var seg := 5
	for k in range(seg):
		var frac: float = float(k) / float(seg - 1)
		_spawn_pillar_flame(burn, pos2d, lerpf(0.55, top_h, frac), frac)

func _spawn_pillar_flame(burn: Texture2D, pos2d: Vector2, h: float, frac: float) -> void:
	var spr := Sprite3D.new()
	spr.texture = burn
	spr.hframes = 8
	spr.frame = randi() % 8
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var fw: float = float(burn.get_width()) / 8.0
	spr.pixel_size = (lerpf(98.0, 56.0, frac) * WS) / fw          # 底大顶小=火柱形
	spr.position = _world_pos(pos2d, h)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_method(_burn_frame.bind(spr), 0.0, 16.0, 0.32)
	tw.tween_property(spr, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(spr.queue_free)

# 真像素火(burn-loop 8帧)在地面点燃, 循环烧一会再淡灭 (敌着火/燃烧带共用)
func _delayed_ground_fire(pos2d: Vector2, burn: Texture2D, size_px: float, delay: float) -> void:
	if burn == null:
		return
	if delay <= 0.0:
		_ground_fire(pos2d, burn, size_px)
		return
	var tw := _reg_tween()
	tw.tween_interval(delay)
	tw.tween_callback(_ground_fire.bind(pos2d, burn, size_px))

func _ground_fire(pos2d: Vector2, burn: Texture2D, size_px: float) -> void:
	if burn == null:
		return
	var life: float = randf_range(0.7, 1.0)
	var spr := Sprite3D.new()
	spr.texture = burn
	spr.hframes = 8
	spr.frame = randi() % 8
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var fw: float = float(burn.get_width()) / 8.0
	spr.pixel_size = (size_px * WS) / fw
	spr.position = _world_pos(pos2d, size_px * WS * 0.4)
	_world.add_child(spr)
	var loops: int = maxi(2, int(life / 0.42))
	var tw := _reg_tween()
	tw.tween_method(_burn_frame.bind(spr), 0.0, float(8 * loops), life)
	var tf := _reg_tween()
	tf.tween_interval(life * 0.55)
	tf.tween_property(spr, "modulate:a", 0.0, life * 0.45)
	tf.tween_callback(spr.queue_free)

func _burn_frame(fr: float, spr: Sprite3D) -> void:
	if is_instance_valid(spr):
		spr.frame = int(fr) % 8

func _dragon_trail_puff(pos2d: Vector2, height: float, size_px: float, delay: float) -> void:
	var tw := _reg_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(_spawn_dragon_puff.bind(pos2d, height, size_px))

func _spawn_dragon_puff(pos2d: Vector2, height: float, size_px: float) -> void:
	var tex := _make_fire_glow_tex()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.modulate = Color(1.0, 0.5, 0.12, 0.92)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = (size_px * WS) / float(maxi(1, int(tex.get_width())))
	spr.position = _world_pos(pos2d, height)
	_world.add_child(spr)
	var t := _reg_tween()
	t.set_parallel(true)
	t.tween_property(spr, "modulate:a", 0.0, 0.42)
	t.tween_property(spr, "pixel_size", spr.pixel_size * 0.5, 0.42)
	t.chain().tween_callback(spr.queue_free)

# 延时播序列帧特效(火龙飞到目标那刻才炸)
func _delayed_sheet_vfx(pos2d: Vector2, sheet: Texture2D, frames: int, delay: float) -> void:
	if sheet == null:
		return
	if delay <= 0.0:
		play_sheet_vfx(pos2d, sheet, frames, 150.0, 0.5, 0.7)
		return
	var tw := _reg_tween()
	tw.tween_interval(delay)
	tw.tween_callback(play_sheet_vfx.bind(pos2d, sheet, frames, 120.0, 0.45, 0.7))

func _delayed_heal_glint(pos2d: Vector2, delay: float) -> void:
	if delay <= 0.0:
		_skill_ring(pos2d, Color(0.45, 1.0, 0.55, 0.55), 46.0)
		return
	var tw := _reg_tween()
	tw.tween_interval(delay)
	tw.tween_callback(_skill_ring.bind(pos2d, Color(0.45, 1.0, 0.55, 0.55), 46.0))

# ============================================================================
#  局内信息 UI — 左右队头像框栏 + 点单位看详情面板 (纯 UI, 不动玩法)
#    1) _build_team_panels: 左右两竖栏 (主龟; 召唤体不进), 每框=头像+名+等级牌+迷你血条, 可点
#    2) _update_team_panels: 每帧刷 HP 条宽 / 死亡变暗 / 选中高亮
#    3) _show_unit_info_panel: 居中详情面板 (detail_panel_frame 斜面边框), 显等级/属性/被动/技能/装备
# ============================================================================
const DetailPanelFrame := preload("res://scripts/scenes/detail_panel_frame.gd")
const _PANEL_HP_W := 80.0    # 框内迷你血条宽

# 立绘稀有度 (字母码 C/B/A/S/SS/SSS) → 描边色
func _pet_rarity_color(r: String) -> Color:
	match r:
		"B": return Color("#4ade80")
		"A": return Color("#60a5fa")
		"S": return Color("#c084fc")
		"SS", "SSS": return Color("#fbbf24")
		_: return Color("#9aa6b3")   # C / 未知

# 装备稀有度 (中文 普通/精良/稀有/史诗/传说) → 描边色 (与 ShopScene 一致)
func _equip_rarity_color(r: String) -> Color:
	match r:
		"精良": return Color("#4ade80")
		"稀有": return Color("#60a5fa")
		"史诗": return Color("#c084fc")
		"传说": return Color("#fbbf24")
		_: return Color("#8a96a3")

# 去 HTML 标签 (数据里 brief/desc 含 <span ...>...</span>) → 纯文本. 顺手把 \n 保留.
func _strip_html(s: String) -> String:
	if s == "":
		return ""
	var re := RegEx.new()
	re.compile("<[^>]*>")
	var out := re.sub(s, "", true)
	out = out.replace("&nbsp;", " ").replace("&amp;", "&")
	return out.strip_edges()

# 单位静态头像贴图: 优先 avatars/<id>.png (方头像); 没有则取立绘 sprite-sheet 首帧 (AtlasTexture 裁第一帧).
func _unit_portrait_texture(u: Dictionary) -> Texture2D:
	var id := str(u.get("id", ""))
	var av := AVATAR_DIR + id + ".png"
	if ResourceLoader.exists(av):
		var t: Texture2D = load(av)
		if t != null:
			return t
	# 退回立绘首帧 (sprite-sheet → AtlasTexture 裁单帧, 单帧图直接用)
	var sd: Dictionary = u.get("idle_sd", {})
	var tex = sd.get("tex", null)
	if tex == null:
		return null
	var hf: int = int(sd.get("hframes", 1))
	var vf: int = int(sd.get("vframes", 1))
	if hf <= 1 and vf <= 1:
		return tex
	var fw: int = int(tex.get_width() / maxi(1, hf))
	var fh: int = int(tex.get_height() / maxi(1, vf))
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, fw, fh)
	return at

# ----------------------------------------------------------------------------
#  1) 左右队头像框栏
# ----------------------------------------------------------------------------
func _build_team_panels() -> void:
	if _ui_layer == null:
		return
	# 旧栏清掉 (重生/重开安全)
	if _team_panel_left != null and is_instance_valid(_team_panel_left):
		_team_panel_left.queue_free()
	if _team_panel_right != null and is_instance_valid(_team_panel_right):
		_team_panel_right.queue_free()
	_team_panel_left = _make_team_column("left")
	_team_panel_right = _make_team_column("right")
	_ui_layer.add_child(_team_panel_left)
	_ui_layer.add_child(_team_panel_right)

func _make_team_column(side: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "TeamPanel_" + side
	col.add_theme_constant_override("separation", 6)
	# 屏幕边缘竖直居中: 左栏贴左、右栏贴右 (用 anchor preset + 偏移)
	if side == "left":
		col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		col.position = Vector2(10, 0)
		col.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		col.position = Vector2(-10, 0)
		col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	for u in _units:
		if str(u.get("side", "")) != side:
			continue
		if u.get("is_summon", false):
			continue   # 召唤体不进框栏 (只主龟)
		var frame := _make_team_frame(u)
		col.add_child(frame)
	# 居中: VBox 内容会从 anchor 点往下排; 让它真正竖直居中需把它整体上移半高 → 用 pivot 不便,
	#   改用一个外层 wrapper 也可, 但框少(1-3)时贴边竖直居中已够好 (CENTER_LEFT/RIGHT anchor=屏幕中线).
	return col

# 单个头像框: 头像 + 名 + 等级牌 + 迷你血条; 整框可点 → 弹详情面板.
func _make_team_frame(u: Dictionary) -> Control:
	var side := str(u.get("side", "left"))
	var accent := Color("#3fa9ff") if side == "left" else Color("#ff5a5a")
	var frame := PanelContainer.new()
	frame.name = "Frame_" + str(u.get("id", ""))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#12161f")
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(124, 0)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉点击 (别穿到战场)
	frame.tooltip_text = "%s · 点击看详情" % str(u.get("name", u.get("id", "")))

	var main_col := VBoxContainer.new()   # 头像行 + 装备格行
	main_col.add_theme_constant_override("separation", 5)
	main_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(main_col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_col.add_child(row)

	# 头像 (44x44)
	var portrait := TextureRect.new()
	portrait.texture = _unit_portrait_texture(u)
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	# 右侧: 名 + 等级牌 (一行) + 迷你血条
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(top)
	var lv_badge := _make_mini_lv_badge(int(u.get("level", 1)))
	if lv_badge != null:
		top.add_child(lv_badge)
	u["panel_lv_badge"] = lv_badge
	var nm := Label.new()
	nm.text = str(u.get("name", u.get("id", "")))
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#e8f2ff"))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nm)

	# 迷你血条 (ColorRect bg + fill)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.custom_minimum_size = Vector2(_PANEL_HP_W, 5)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#4ade80")
	hp_fill.position = Vector2(0, 0)
	hp_fill.size = Vector2(_PANEL_HP_W, 5)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bg.add_child(hp_fill)
	# 头像下方: 至多4个装备格 (图标 + 充能类装备的充能进度条)
	u["panel_charge_bars"] = []
	u["panel_count_labels"] = []
	var equips: Array = u.get("equips", [])
	if not equips.is_empty():
		var eq_row := HBoxContainer.new()
		eq_row.add_theme_constant_override("separation", 4)
		eq_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eq_row.alignment = BoxContainer.ALIGNMENT_CENTER
		main_col.add_child(eq_row)
		for _ei in range(mini(4, equips.size())):
			eq_row.add_child(_make_panel_equip_slot(u, str((equips[_ei] as Dictionary).get("id", ""))))

	# 整框点击 → 详情面板
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_unit_info_panel(u))

	# 引用挂在单位字典上, 供 _update_team_panels 每帧刷
	u["panel_frame"] = frame
	u["panel_hp_fill"] = hp_fill
	u["panel_stylebox"] = sb
	return frame

func _make_panel_equip_slot(u: Dictionary, eid: String) -> Control:   # 头像下装备格: 图标(稀有度描边)+充能条/层数徽章
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 1)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Control.new()
	box.custom_minimum_size = Vector2(44, 44)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(box)
	var bgp := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#0c141c"); bsb.set_border_width_all(1)
	bsb.border_color = _equip_rarity_color(str(edef.get("rarity", "普通")))
	bsb.set_corner_radius_all(3)
	bgp.add_theme_stylebox_override("panel", bsb)
	bgp.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bgp)
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new()
		ic.texture = load("res://assets/sprites/" + img)
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)   # 居中填框(用户: 图片放正中间)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
	else:
		var em := Label.new()
		em.text = str(edef.get("emoji", "?"))
		em.set_anchors_preset(Control.PRESET_FULL_RECT)
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		em.add_theme_font_size_override("font_size", 12)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(em)
	if PANEL_COUNT.has(eid):   # 层数徽章: 纯数字(重描边, 无底框)锚右下角, 不与图标重叠 (用户)
		var cnt := Label.new()
		cnt.text = "0"
		cnt.anchor_left = 1.0; cnt.anchor_top = 1.0; cnt.anchor_right = 1.0; cnt.anchor_bottom = 1.0
		cnt.offset_left = -18.0; cnt.offset_top = -18.0; cnt.offset_right = -1.0; cnt.offset_bottom = -1.0
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cnt.add_theme_font_size_override("font_size", 15)
		cnt.add_theme_color_override("font_color", Color("#ffe36b"))
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
		cnt.add_theme_constant_override("outline_size", 5)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cnt)
		(u["panel_count_labels"] as Array).append({"lbl": cnt, "iid": eid, "key": PANEL_COUNT[eid]})
	if PANEL_CHARGE.has(eid):   # 充能进度条: 宽刃弯刀等
		var cfg: Array = PANEL_CHARGE[eid]
		var cb_bg := ColorRect.new()
		cb_bg.color = Color(0, 0, 0, 0.6)
		cb_bg.custom_minimum_size = Vector2(44, 4)
		cb_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cb_bg)
		var cb_fill := ColorRect.new()
		cb_fill.color = Color("#5ad2ff")
		cb_fill.size = Vector2(0, 3)
		cb_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cb_bg.add_child(cb_fill)
		(u["panel_charge_bars"] as Array).append({"fill": cb_fill, "iid": eid, "key": cfg[0], "cap": cfg[1]})
	return slot

func _make_mini_lv_badge(level: int) -> Panel:
	if level <= 0:
		return null
	var badge := Panel.new()
	var lv_sb := StyleBoxFlat.new()
	lv_sb.bg_color = Color("#161019")
	lv_sb.set_border_width_all(1)
	lv_sb.border_color = Color("#ffce4d")
	lv_sb.set_corner_radius_all(3)
	badge.add_theme_stylebox_override("panel", lv_sb)
	badge.custom_minimum_size = Vector2(20, 14)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = "%d" % level
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color("#ffd93d"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge

# ----------------------------------------------------------------------------
#  2) 每帧刷头像框 (HP 条宽 / 死亡变暗 / 选中高亮)
# ----------------------------------------------------------------------------
func _update_team_panels() -> void:
	for u in _units:
		var fr = u.get("panel_frame", null)
		if fr == null or not is_instance_valid(fr):
			continue
		var plb = u.get("panel_lv_badge", null)   # 面板等级框也随036临时等级跳
		if plb != null and is_instance_valid(plb) and plb.get_child_count() > 0:
			(plb.get_child(0) as Label).text = str(_effective_level(u))
		var fill = u.get("panel_hp_fill", null)
		if fill != null and is_instance_valid(fill):
			var maxhp: float = maxf(1.0, float(u.get("maxHp", 1.0)))
			var ratio: float = clampf(float(u.get("hp", 0.0)) / maxhp, 0.0, 1.0)
			fill.size.x = _PANEL_HP_W * ratio
			# 血色随比例 (绿→黄→红)
			if ratio > 0.5:
				fill.color = Color("#4ade80")
			elif ratio > 0.25:
				fill.color = Color("#ffce4d")
			else:
				fill.color = Color("#ff5a5a")
		var alive: bool = bool(u.get("alive", true))
		fr.modulate = Color(1, 1, 1, 1) if alive else Color(0.45, 0.45, 0.5, 0.75)
		# 选中高亮: 边框加粗 + 提亮 (改 stylebox border)
		var sb = u.get("panel_stylebox", null)
		if sb != null and sb is StyleBoxFlat:
			var selected: bool = (_selected_unit != null and u == _selected_unit)
			(sb as StyleBoxFlat).set_border_width_all(3 if selected else 2)
			var base_accent := Color("#3fa9ff") if str(u.get("side", "")) == "left" else Color("#ff5a5a")
			(sb as StyleBoxFlat).border_color = (Color("#ffd93d") if selected else base_accent)
		for cb in u.get("panel_charge_bars", []):   # 装备格充能进度条
			var cf = cb.get("fill", null)
			if cf == null or not is_instance_valid(cf): continue
			var cstt = u.get("eq_state", {}).get(str(cb["iid"]), {})
			var cfrac: float = clampf(float(cstt.get(str(cb["key"]), 0.0)) / float(cb["cap"]), 0.0, 1.0)
			cf.size = Vector2(44.0 * cfrac, 4)
		for cl in u.get("panel_count_labels", []):   # 装备格右下角层数徽章
			var clb = cl.get("lbl", null)
			if clb == null or not is_instance_valid(clb): continue
			var lstt = u.get("eq_state", {}).get(str(cl["iid"]), {})
			clb.text = str(int(lstt.get(str(cl["key"]), 0)))

# ----------------------------------------------------------------------------
#  3) 详情面板 (居中, detail_panel_frame 斜面边框) — 等级/属性/被动/技能/装备
# ----------------------------------------------------------------------------
func _close_info_panel() -> void:
	if _info_panel != null and is_instance_valid(_info_panel):
		_info_panel.queue_free()
	_info_panel = null
	_selected_unit = null

func _show_unit_info_panel(u: Dictionary) -> void:
	_close_info_panel()
	_selected_unit = u
	if _ui_layer == null:
		return
	var id := str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})

	# 背景遮罩 (点空白处关) — 铺满屏
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_info_panel())
	_ui_layer.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("#101622")
	psb.set_border_width_all(2)
	psb.border_color = Color("#2a3650")
	psb.set_corner_radius_all(14)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16; psb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", psb)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 吃掉面板内点击 (别穿到 backdrop)
	backdrop.add_child(panel)
	# detail_panel_frame 斜面边框 overlay (full-rect, mouse ignore)
	var bevel := DetailPanelFrame.new()
	bevel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bevel)
	_info_panel = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	# --- 头部: 大头像 + 名 + 稀有度 + 等级 + 关闭按钮 ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var big := TextureRect.new()
	big.texture = _unit_portrait_texture(u)
	big.custom_minimum_size = Vector2(72, 72)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(big)
	var head_info := VBoxContainer.new()
	head_info.add_theme_constant_override("separation", 3)
	head_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_info)
	var name_lbl := Label.new()
	name_lbl.text = str(u.get("name", id))
	name_lbl.add_theme_font_size_override("font_size", 22)
	var rar := str(pet.get("rarity", u.get("rarity", "C")))
	name_lbl.add_theme_color_override("font_color", _pet_rarity_color(rar))
	head_info.add_child(name_lbl)
	var sub := Label.new()
	sub.text = "稀有度 %s    Lv %d" % [rar, int(u.get("level", 1))]
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	head_info.add_child(sub)
	# 关闭 ✖ (原 ✕ U+2715 打包字体链无字形 → 换 ✖ U+2716, Noto Emoji 有)
	var close_btn := Button.new()
	close_btn.text = "✖"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(_close_info_panel)
	head.add_child(close_btn)

	_add_panel_sep(vb)

	# --- 属性栏 ---
	var stat_lbl := Label.new()
	stat_lbl.text = "HP %d/%d   ATK %d   防 %d   抗 %d\n暴击 %d%%   攻速 %ss   射程 %d" % [
		int(u.get("hp", 0)), int(u.get("maxHp", 0)), int(u.get("atk", 0)),
		int(u.get("def", 0)), int(u.get("mr", 0)), int(float(u.get("crit", 0.0)) * 100.0),
		_fmt_num(float(u.get("atk_interval", 0.0))), int(u.get("atk_range", 0))]
	stat_lbl.add_theme_font_size_override("font_size", 14)
	stat_lbl.add_theme_color_override("font_color", Color("#d6e4f0"))
	vb.add_child(stat_lbl)

	_add_panel_sep(vb)

	# --- 被动 ---
	var passive: Dictionary = u.get("passive", {})
	if passive is Dictionary and not (passive as Dictionary).is_empty():
		_add_section_title(vb, "被动 · " + str(passive.get("name", "")))
		var pdesc := _strip_html(str(passive.get("desc", passive.get("brief", ""))))
		if pdesc != "":
			_add_body_text(vb, pdesc)

	# --- 已选技能 ---
	var skills := _panel_skill_entries(u)
	if not skills.is_empty():
		_add_section_title(vb, "技能")
		for sk in skills:
			_add_section_title(vb, "  " + str(sk["name"]), Color("#9fd0ff"), 14)
			if str(sk["desc"]) != "":
				_add_body_text(vb, str(sk["desc"]))

	# --- 装备 ---
	var equips: Array = u.get("equips", [])
	_add_section_title(vb, "装备 (%d)" % equips.size())
	if equips.is_empty():
		_add_body_text(vb, "无装备", Color("#7a8694"))
	else:
		for e in equips:
			_add_equip_row(vb, str(e.get("id", "")), int(e.get("star", 1)))

# 技能条目 [{name, desc}]: 取该龟已选的主动技 (走 _chosen_skill_types) + 普攻名 (skillPool[0]).
func _panel_skill_entries(u: Dictionary) -> Array:
	var id := str(u.get("id", ""))
	var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
	var pool: Array = pet.get("skillPool", [])
	var out: Array = []
	var chosen: Array = _chosen_skill_types(id, str(u.get("side", "")) == "left")
	# 已选主动技 (按 type 在 pool 里找名/描述)
	for t in chosen:
		for sk in pool:
			if sk is Dictionary and str(sk.get("type", "")) == str(t):
				out.append({"name": str(sk.get("name", t)), "desc": _strip_html(str(sk.get("brief", sk.get("detail", ""))))})
				break
	# 普攻 (skillPool[0] 一般是 physical/magic) — 补一条让面板不空
	if not pool.is_empty() and pool[0] is Dictionary:
		var s0: Dictionary = pool[0]
		var t0 := str(s0.get("type", ""))
		if t0 == "physical" or t0 == "magic":
			out.append({"name": str(s0.get("name", "普攻")) + " (普攻)", "desc": _strip_html(str(s0.get("brief", "")))})
	return out

# 装备行: 图标 + 名 + ★×star + 效果 (effectDesc1, strip html). 稀有度色描边图标框.
func _add_equip_row(parent: VBoxContainer, eid: String, star: int) -> void:
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	# 图标框
	var icon_box := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color("#0c141c")
	isb.set_border_width_all(2)
	isb.border_color = _equip_rarity_color(str(edef.get("rarity", "普通")))
	isb.set_corner_radius_all(5)
	icon_box.add_theme_stylebox_override("panel", isb)
	icon_box.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon_box)
	var img := str(edef.get("img", ""))
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new()
		ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_box.add_child(ic)
	else:
		var em := Label.new()
		em.text = str(edef.get("emoji", "?"))
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_box.add_child(em)
	# 文本: 名 ★×star + 效果
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 1)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tcol)
	var title := Label.new()
	var stars := ""
	for _i in range(clampi(star, 1, 3)):
		stars += "★"
	title.text = "%s  %s" % [str(edef.get("name", eid)), stars]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", _equip_rarity_color(str(edef.get("rarity", "普通"))))
	tcol.add_child(title)
	var eff := _strip_html(str(edef.get("effectDesc1", "")))
	if eff != "":
		var el := Label.new()
		el.text = eff
		el.add_theme_font_size_override("font_size", 11)
		el.add_theme_color_override("font_color", Color("#aab8c6"))
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.custom_minimum_size = Vector2(300, 0)
		tcol.add_child(el)

# 小工具: 分隔线 / 小标题 / 正文 / 数字格式
func _add_panel_sep(parent: VBoxContainer) -> void:
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)

func _add_section_title(parent: VBoxContainer, text: String, col: Color = Color("#ffce4d"), fs: int = 15) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)

func _add_body_text(parent: VBoxContainer, text: String, col: Color = Color("#c2d0de")) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	parent.add_child(l)

# 攻速等小数: 去多余 0 (0.850000 → 0.85)
func _fmt_num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s
