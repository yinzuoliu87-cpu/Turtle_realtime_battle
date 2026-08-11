extends Node3D
const HpBarScene := preload("res://scripts/scenes/hp_bar.gd")   # 回合制版好看血条 (自定义 _draw, 复用)
const Backend := preload("res://scripts/net/backend.gd")    # 赛季结算上传 ghost (异步PvP池)
## RealtimeBattle3DScene — 2.5D 战斗核心 (Phase 2, 见 docs/design/2.5D战斗架构方案.md §四.2-4)
## 真阵容在 2.5D 里能打: 读 GameState 配队 / demo 兜底 → Sprite3D billboard + blob影 + HP/龟能 overlay.
## 移动·索敌·普攻·分离·龟能·灭队判定 全复用 2D 版 RealtimeBattleScene 的逻辑口径(数值/公式/STATS),
## 只把 pos: Vector2 当 XZ 平面坐标, 另存 height/vy 给击飞真物理(Y 重力抛物). billboard 永远朝镜头.
## ✅ Phase 3: 效果引擎接入 — 28主动技 + 层数DoT(灼烧/中毒/流血) + 召唤体(3D billboard+blob影) + 变身(双头/熔岩/赛博/龟壳)
##    + 登场被动 + on-hit被动 + 周期被动 + 死亡钩子, 全部从 2D 版逐函数照搬(逻辑/数值不变), 只把
##    VFX 触点(_vfx._float_text/_skill_ring/_bolt_line/召唤node/投射物) 换成 3D 等价.
## ⚠ 本轮先不做 59 装备运行时 (留 Phase 3b); _eq_* 钩子在 2D 版有, 这里全部不调用(equips 恒空).
## ⚠ 占位美术: 立绘从 avatars/ 按 id, 地面/影/血条/技能圈占位; 数值是 2D 版草案值, 全待 F5 调手感.
##
## ════════════════════════════════════════════════════════════════════════════
##  📍 导航索引 (2026-07-21 实测生成; 本文件 23k 行 909 个函数, 靠搜函数名前缀跳转)
## ════════════════════════════════════════════════════════════════════════════
##  职责                    函数数   搜这个前缀
##   龟技能实装               90     _sk_          ← 最大簇(3028行)
##   装备触发                 52     _eq_
##   调试场(开发工具)         40     _edit_
##   双路对战流程             36     _dl_
##   周期驱动 tick            32     _tick_
##   出生/召唤                22     _spawn_ / _summon
##   场景/UI 构建             22     _build_
##   伤害/治疗/护盾结算       18     _damage._apply_damage / _damage._heal / _damage._grant_shield / _resolve_
##   每帧刷新                 17     _update_
##   时停系统                 16     _ts_
##   工厂(单位/材质/UI件)     14     _make_
##   熔岩地面区               13     _lava_
##   VFX 工具                 10     _skill_ring / _burst_vfx / _beam_vfx / _vfx._hit_spark …
##   信息面板                 10     _info_ / _panel_ / _refresh_info
##
##  ⚠ 另有 513 个函数(56%)无法归类 —— 全是【单龟专属 VFX 与杂项】, 按龟名搜:
##     _crystal_ / _headless_ / _shell_ / _pirate_ / _elite_ / _phoenix_ / _ice_ / _smolder_ …
##
## ════════════════════════════════════════════════════════════════════════════
##  🔧 为什么这个文件没有被拆小 (2026-07-21 实测, 别再重复评估)
## ════════════════════════════════════════════════════════════════════════════
##  拆过一次: 地图编辑器 → scripts/scenes/map_editor.gd (干净, 7函数/伤害调用0)。
##  其余全部量过, 结论是【不该拆】:
##   · _sk_*(3028行)  搬出去需注入 140 个宿主函数 + 39 个成员变量 = 179 依赖 → 接口比代码还重
##   · _build_*(948)  它【创建】_cam/_ui_layer 等核心节点, 注入不了
##   · _edit_*(513)   _edit_unit_at_screen 不是调试专用(正式对局点龟弹面板在用), 另有24函数要架桥
##   · VFX工具(277)   散在 8 处, 且依赖 _reg_tween 的时停契约(漏注册=时停静默失效)
##                    收益 1.1% / 风险时停失效 → 比例不对
##  真要减体积, 得先把"单龟VFX"与"玩法逻辑"分离(那 513 个函数), 属于重写而非重构。
##  在那之前: 靠上面的导航索引 + 43 个自证测试 + run-tests.sh 门禁 + CLAUDE.md 地雷清单来兜底。

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
## 技能文案模板渲染器(图鉴一直在用, 战斗详情面板此前【没接】)。
## 不接的后果: pets.json 里的 {N:0.7*ATK} / {{ATK}} 这类占位符【原样漏到界面上】,
## 玩家看到的是模板字符串而不是数字(用户 2026-07-21 在面板截图里指出)。
## 接上之后, 技能伤害数值 = 按该龟【当前】属性算出来的真数字, 且能随属性变化实时刷新。
const SkillText := preload("res://scripts/util/skill_text.gd")
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
## 龟蛋相关(用户2026-07-19 调参): 围栏额外双抗 / 决胜期自损间隔与比例
const EGG_FENCE_RES := 200.0    # 围栏未破时蛋额外获得的双抗(原 80)
const EGG_SELFLOSS_IV := 1.0    # 决胜期自损间隔秒(原 2.5)
const EGG_SELFLOSS_PCT := 0.05  # 每次自损占最大生命比例(原 0.25) → 净速率 10%/秒 → 5%/秒
const HP_MULT := 3.0                       # base↔final比率: 龟/装备hp已写最终值; 仅召唤raw值(×)与装备%回收(maxHp/)用它
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类层数 DoT 每秒结算一次
const BUFF_SEC := 5.0                      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const DICE_BLOOD_CRIT := 0.70              # 骰子·赌徒之血: 损30%生命时的满额暴击加成(用户2026-07-28: 0.50→0.70)
const CYBER_LASER_FALLOFF := 0.50          # 赛博贯穿激光: 第一个之后的敌人伤害倍率(用户2026-07-28削弱)
const CTRL_SEC := 1.5                      # 眩晕/冻结/嘲讽 默认秒数

# 28 龟战斗属性 (1:1 复用): id → [melee, move_spd(px/s), atk_interval(s), atk_range(px)]
# ★攻速按定位统一压到 0.6-0.85 次/秒 区间(用户2026-07-18"按定位但只能在0.6到0.85之间定"): 刺客0.85(间隔1.1765)/近战斗士0.8(1.25)/远程射手0.75(1.3333)/法师+辅助0.7(1.4286)/坦克0.6(1.6667); 精英保0.65(硬编码另处). 削弱普攻主导·让技能更吃重.
const STATS := preload("res://scripts/gamedata/turtle_stats.gd").STATS   # ★单一事实源已抽到 turtle_stats.gd(图鉴同源读), 见该文件
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
##    · 编辑器 / F5 / debug 导出  → REVIEW_DEMO_DEFAULT (2026-07-16 起 = false) ← 审龟改用 REVIEW=1
##    · SHIP=1   环境变量         → 强制 false (headless 验证上线语义)
##    · REVIEW=1 环境变量         → 强制 true  (在 release 包里也能开评审场)
const REVIEW_DEMO_DEFAULT := false   # 2026-07-16审龟暂停+iOS测试包(debug构建)需真实对局: debug包不再劫持战斗; 桌面审龟用 REVIEW=1 env照旧

static func _review_demo() -> bool:
	if OS.has_environment("SHIP"):
		return false
	if OS.has_environment("REVIEW"):
		return true
	return REVIEW_DEMO_DEFAULT and OS.is_debug_build()
## 原图朝右的立绘例外表(全局约定=原图朝左, 这些要取反)。
## 键可以是【龟 id】, 也可以是【召唤物 kind】—— 见 _art_faces_right() 为什么要分两种查法。
## 原图【朝右】的立绘 —— 引擎默认认为所有立绘朝左, 这里列例外(会取反 flip_h)。
## __trainer__ 2026-07-23: PixelLab 的 south-east 面就是朝右, 而训龟大师后续的走路/扔石头
##   动作图也全是同一套朝向 —— 与其每张都逐帧镜像(小将那 7 张就是这么交的税), 不如登记例外。
##   ★探针实测(修之前): 我方 face_right=true / art_faces_right=false → flip_h=true → 背对战场。
const ART_FACES_RIGHT := ["hiding", "headless", "mech", "__trainer__"]   # 缩头2026-07-17用户抓 / 无头预检自查颈残端在右 / 机甲2026-07-19用户抓「建模也反了」 / 训龟大师2026-07-23
const REVIEW_TURTLE := "headless"              # 受审龟 id (技能特效验收: 换龟只改这里; 账本见 docs/design/技能特效验收账本.md)
## ⚠ 用的时候一律走 `_review_skill_idx()`, 别直接引用本常量 ——
## 那个函数才会读【调试面板覆盖】和【env REVIEW_SKILL】; 直接用常量的话环境变量对该处失效。
## (2026-07-19 修: 原有 10 处 demo 分支直接用常量, 导致 REVIEW_SKILL=-1 对它们一律无效, 评审场景开不出来。)
const REVIEW_SKILL_IDX := 0   # 评审受审龟放哪个技(skillPool索引): 0=普攻/1-3=候选技/-1=默认轮转(=被动) (26缩头全✅封板2026-07-17→27无头预检中: 0普攻起)
const REVIEW_EQUIP := []   # 调试场给受审龟装这些测试装备(空[]=裸装看纯技能; 非空=看装备显示/效果·用户2026-07-11 #2)
const REVIEW_EQUIP_STAR := 2   # 调试场装备星级(1-3·用户2026-07-11: 装备星级可调)
const REVIEW_SHOWCASE := []   # 非空=展示模式: 这些龟一队vs等量假人(一窗连续看多只); 空=单龟评审
const REVIEW_DUMMY := "basic"              # 假人 id (右队沙包)
const REVIEW_DUMMY_HP := 500.0            # 假人固定血量
const REVIEW_DUMMY_COUNT := 3   # 假人数量(单龟评审时); >1=排开
const REVIEW_DUMMY_KILLABLE := false   # true=假人会死(看换目标); false=不死回满沙包(看完整动画)
const REVIEW_DUMMY_ATTACKS := true     # true=假人会还手(看挨打类被动如龟壳储能); 同时受审龟免死看完整循环

# 🛠 调试面板 运行时覆盖(跨 reload_current_scene 持久·用户2026-07-11「调试场加装备/选星级/选技能」)
static var _dbg_skill := -99            # 覆盖受审技idx(-99=用REVIEW_SKILL_IDX)
static var _dbg_star := 0               # 装备星级(0=用REVIEW_EQUIP_STAR·1-3)
static var _dbg_equip_idx := -1          # 装备: -1=关, >=0=装第N件单装备(_dbg_equip_ids索引·◀▶循环挑·用户2026-07-12)
static var _dbg_turtle := ""             # 受审龟id覆盖("" = 用REVIEW_TURTLE·◀▶循环挑全28龟·用户2026-07-12)
const LEFT_DEMO := ["basic", "stone", "lightning"]   # 非评审 demo (_review_demo()=false 时用)

## 每技【专属演示假人布局】: "受审龟id:skill_idx" → [ {dx,dy}, ... ] (相对受审龟: dx=右方X码, dy=深度Y偏移).
##   缺省(无此键)= REVIEW_DUMMY_COUNT 个横排。★验收账本 docs/design/技能特效验收账本.md 每技记一份。
const REVIEW_DEMO_CFG := {
	"basic:2": [ {"dx": 110.0, "dy": 0.0}, {"dx": 430.0, "dy": -240.0, "fixed": true} ],   # 龟派气波: 1贴脸(正前) + 1远处(偏上·不共线·固定不动) → 触发智能冲刺(冲到能同时打俩)再聚气放波
	"basic:3": [ {"dx": 120.0, "dy": 0.0, "fixed": true}, {"dx": 210.0, "dy": -150.0, "fixed": true}, {"dx": 210.0, "dy": 150.0, "fixed": true} ],   # 过肩摔: 1贴脸(grab目标)+2近flank(固定·看落地250码范围伤)
	"stone:2": [ {"dx": 160.0, "dy": -70.0, "fixed": true}, {"dx": 160.0, "dy": 70.0, "fixed": true}, {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 岩石之躯震击: 前方带状3假人(都在±90带宽内·固定)→看横排扫击命中+击退
	"stone:3": [ {"dx": 260.0, "dy": -150.0}, {"dx": 260.0, "dy": 150.0}, {"dx": 380.0, "dy": 0.0} ],   # 嘲讽: 3假人都在500码嘲讽+400码砸地范围内(不固定→被嘲讽后转头打石头, 3.5s砸地击飞)
	"stone:-1": [ {"dx": 120.0, "dy": -70.0}, {"dx": 120.0, "dy": 70.0}, {"dx": 200.0, "dy": 0.0} ],   # 岩石之躯被动审: 3假人围上来持续打石头→石头堆岩层(体型+2%/层·减伤1%/层·上限30)看变大
	"dice:3": [ {"dx": 320.0, "dy": -260.0, "fixed": true}, {"dx": 700.0, "dy": 220.0, "fixed": true}, {"dx": 1000.0, "dy": -120.0, "fixed": true} ],   # 稳定骰子(刀妹Q): 3假人散开→真冲刺穿过随机敌(落点穿过后方)+挥剑斩(按冲刺左右镜像)·多方向(用户2026-07-13)
	"rainbow:3": [ {"dx": 350.0, "dy": -260.0, "fixed": true}, {"dx": 680.0, "dy": 200.0, "fixed": true}, {"dx": 520.0, "dy": -80.0, "fixed": true} ],   # 反射弹射: 3假人拉开→看棱镜光束在龟与各敌间反射弹跳(治友绿/伤敌全色)
	"bamboo:0": [ {"dx": 100.0, "dy": 0.0} ],   # 竹叶一叶普攻: 单假人贴脸→看近战挥击 + 竹叶生长每6秒强化下一发(绿生命球飞回+成长)
	"bamboo:1": [ {"dx": 130.0, "dy": -70.0}, {"dx": 130.0, "dy": 70.0} ],   # 自然恢复: 2假人围打竹叶→掉血后放自愈(15%maxHp)看回血+治疗辉光(单龟无友军=无团队护盾)
	"bamboo:2": [ {"dx": 130.0, "dy": 60.0, "fixed": true}, {"dx": 520.0, "dy": -120.0, "fixed": true} ],   # 竹击: 近假人拴住竹叶(近战打它) + 远假人(520码·钩最远)→看伸竹藤从远处拽贴身+眩晕冰寒
	"bamboo:3": [ {"dx": 220.0, "dy": -70.0, "fixed": true}, {"dx": 220.0, "dy": 70.0, "fixed": true}, {"dx": 320.0, "dy": 0.0, "fixed": true} ],   # 竹刺阵: 3假人聚一起(都在300码内)→蓄力预警圈→竹刺齐爆+击飞1.5s
	"angel:0": [ {"dx": 220.0, "dy": -240.0, "fixed": true} ],   # 天使普攻: 远程(射程400)·假人放斜上方(非水平)→验尖尖波弹道随方向转(尖端领飞) + 审判蓝字
	"angel:1": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 天使祝福: 单假人(天使打它)·单龟无友军→祝福自己(金圣环+1.2A护盾+50%攻速5秒·2026-07-11删原30%龟能充能)
	"angel:2": [ {"dx": 300.0, "dy": 0.0, "fixed": true, "rarity": "S"} ],   # 天使平等: 单S级假人(触发审判光柱·需A+)→看2道圣光斩弧+从天而降审判光柱+吸血
	"angel:3": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 天使飞升: 单假人(天使打它)→反复放飞升(自增buff)看金光圣环+攻速逐次变快(永久叠加)
	"ice:0": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 寒冰普攻冰刺: 远程(射程400)单假人在射程内→看冰弹弹道+命中冰蓝
	"ice:1": [ {"dx": 260.0, "dy": -60.0, "fixed": true}, {"dx": 260.0, "dy": 60.0, "fixed": true}, {"dx": 350.0, "dy": 0.0, "fixed": true} ],   # 寒冰冰霜: 3假人聚一簇(150码冰霜场覆盖)→看冰霜场环+落冰+圈内-25%魔抗+每0.5s跳伤
	"ice:2": [ {"dx": 220.0, "dy": -240.0, "fixed": true} ],   # 寒冰冰封: 假人放斜上方→验冰锥弹道随方向转(尖端朝目标·不再水平) + 命中0.6魔法+冻结1.5s
	"ice:3": [ {"dx": 200.0, "dy": 0.0, "fixed": true} ],   # 寒冰团队护盾(重设计): 单假人(200码·在250爆炸圈内)·单龟=独狼→自己20%maxHp冰盾·盾破/到期爆250码5A魔法
	"ice:-1": [ {"dx": 250.0, "dy": -120.0}, {"dx": 250.0, "dy": 120.0}, {"dx": 380.0, "dy": 0.0} ],   # 寒冰被动极寒: 3假人→看登场群体寒爆+每敌蓝寒环+全场-30%攻速/移速/充能
	"ninja:0": [ {"dx": 130.0, "dy": 0.0} ],   # 忍者斩击普攻: 近战快攻(interval0.6)单假人→看斩击挥/踏步/2层流血/高暴击
	"ninja:1": [ {"dx": 600.0, "dy": 0.0, "fixed": true} ],   # 忍者手里剑(远程2000码): 假人放600码(出冲击500码范围)→忍者站原地朝远处掷旋转飞镖·看真远程弹道
	"ninja:2": [ {"dx": 170.0, "dy": -75.0, "fixed": true}, {"dx": 250.0, "dy": 0.0, "fixed": true}, {"dx": 170.0, "dy": 75.0, "fixed": true}, {"dx": 650.0, "dy": 0.0, "fixed": true} ],   # 忍者炸弹(400码半径): 前3假人聚一簇居中(落点400码内→受伤)+第4假人远置650码(圈外→不受伤·验半径截断)→看引信炸弹抛向目标→落地爆炸帧动画(贴地不钻地)+400码冲击波环+圈内红字/掉甲
	"ninja:3": [ {"dx": 120.0, "dy": -60.0, "fixed": true}, {"dx": 120.0, "dy": 60.0, "fixed": true}, {"dx": 470.0, "dy": 0.0, "fixed": true} ],   # 忍者背刺: 2近假人(120码)+1远假人(470码=全场最远)→看忍者闪现到最远那只身后+刀光拖影+背刺3段(每300ms一刀斩弧)+留该处追砍(下次最远变成近的2只→再闪回=来回背刺)
	"two_head:0": [ {"dx": 280.0, "dy": 0.0, "fixed": true} ],   # 双头普攻(默认远程形态): 单假人280码→看1.2A灵能弹(紫#c0a0ff弹道); 近战形态0.9A挥砍在换形/技能审时看
	"two_head:1": [ {"dx": 200.0, "dy": -70.0, "fixed": true}, {"dx": 280.0, "dy": 0.0, "fixed": true}, {"dx": 200.0, "dy": 70.0, "fixed": true} ],   # 双头技1(随形态·放完切形态): 3假人聚簇→远程灵能冲击(全体0.85A+15%maxHp蓝)/切近战锤击(单体1.4A橙+盾)交替
	"two_head:2": [ {"dx": 220.0, "dy": -55.0, "fixed": true}, {"dx": 300.0, "dy": 0.0, "fixed": true}, {"dx": 220.0, "dy": 55.0, "fixed": true} ],   # 双头技2(随形态): 远程精神干扰(头顶精神波+紫涟漪+破盾碎裂+裂心标记)/近战吸收(生命虹吸束+微粒回流+回血绿环)交替
	"two_head:3": [ {"dx": 240.0, "dy": -50.0, "fixed": true}, {"dx": 320.0, "dy": 0.0, "fixed": true}, {"dx": 240.0, "dy": 50.0, "fixed": true} ],   # 双头技3融合(登场锁远程形态): 登场合体爆发+持续融合光环→反复放4段弧形魔法波(物理紫/真实白)·受击坚韧微光
	"ghost:0": [ {"dx": 280.0, "dy": 0.0, "fixed": true} ],   # 幽灵普攻幽魂触碰(远程range400): 单假人280码→看0.4A物理(红)+0.9A真实(白)+登场诅咒每秒5%maxHp真伤
	"ghost:1": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 幽灵技1幽冥突袭: 单假人→看幻影+触碰图+抛飞juggle+1.5A魔法+吸血+闪避
	"ghost:2": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 幽灵技2灵魂风暴: 单假人→看ghost-storm风暴图+2段魔法上诅咒(已诅咒→2.5A真伤)
	"diamond:2": [ {"dx": 500.0, "dy": 0.0, "fixed": true} ],   # 钻石滚球: 单假人放远(500码·>200)+固定不动→开场触发200码被动自动免费滚球跨场撞击(用户2026-07-12)
	"gambler:0": [ {"dx": 350.0, "dy": -30.0, "fixed": true} ],   # 赌神卡牌射击: 单假人射程内(350<400)→赌神站原地甩旋转扑克牌+看多重打击被动连锁(40%再打)
	"gambler:1": [ {"dx": 320.0, "dy": -30.0, "fixed": true} ],   # 赌神万能牌: 单假人射程内→丢发光小丑牌+命中金光+减攻红标+自身护盾罩+回血绿
	"gambler:2": [ {"dx": 320.0, "dy": -30.0, "fixed": true} ],   # 赌神赌注: 单假人→牺牲40%血红闪+甩7张牌barrage(错峰·命中才跳伤害)+金光pop
	"gambler:3": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 赌神命运之轮: 单假人→反复放看花色♠♥♦♣老虎机转盘落定+该色大爆+属性飘字
	"hunter:0": [ {"dx": 340.0, "dy": -30.0, "fixed": true} ],   # 猎人射箭: 单假人射程内(340<400)→看箭矢弹道(点先行4帧)命中+目标<50%血追猎+50%攻速
	"hunter:1": [ {"dx": 340.0, "dy": -30.0, "fixed": true} ],   # 猎人精准射击: 单假人→看瞄准蓄力红线+金色狙击曳光+命中毒绿爆+猎杀印记
	"hunter:2": [ {"dx": -165.0, "dy": 20.0}, {"dx": 165.0, "dy": -20.0} ],   # 猎人隐蔽: 双侧melee假人夹击(都<150威胁·不固定→追击)→触发智能翻滚"远离最近近战"分支①·猎人在两假人间左右横跳(方向随最近威胁反转→留在中央开阔区)·看残影拖尾+起落尘+灵巧绿环·下发普攻红色强化数字
	"hunter:3": [ {"dx": 320.0, "dy": -80.0, "fixed": true}, {"dx": 320.0, "dy": 80.0, "fixed": true}, {"dx": 540.0, "dy": 0.0, "fixed": true} ],   # 猎人狩猎弹幕: 3假人散开→看10箭每0.2s一发·随机锁敌·慢速抛物线追踪(箭头随角度上扬/下俯)·命中才跳白色真伤(0.36A/箭·共3.6A)
	"hunter:-1": [ {"dx": 300.0, "dy": -75.0, "fixed": true}, {"dx": 300.0, "dy": 75.0, "fixed": true} ],   # 猎人被动猎杀: 2残血demo靶(_hunt_demo_victim·钉在12%血)→猎人普攻/技能任一伤害都处决(金斩杀爆+处决金字)→窃取(金精华流回猎人+掠夺金字+金光·猎人属性永久累积变强)·不真死循环看
	"pirate:0": [ {"dx": 120.0, "dy": 0.0} ],   # 海盗弯刀普攻: 单假人贴脸→看近战弯刀劈砍(1A物理+自愈0.2A绿字)
	"pirate:1": [ {"dx": 300.0, "dy": -90.0, "fixed": true}, {"dx": 300.0, "dy": 90.0, "fixed": true}, {"dx": 470.0, "dy": 0.0, "fixed": true} ],   # 海盗火炮齐射: 3假人聚目标区(都在800码内)→看海盗船高空驶入+炮弹雨6段落该区+爆炸+命中才跳伤害
	"pirate:2": [ {"dx": 150.0, "dy": -55.0}, {"dx": 150.0, "dy": 55.0} ],   # 海盗朗姆酒: 2近战假人追打站桩海盗(海盗no_basic不自愈不触发假人盾·被打掉血)→放朗姆酒看船扔酒瓶+HoT绿回血顶着伤害回(连续绿字)+暖色酒气护光
	"pirate:3": [ {"dx": 340.0, "dy": -70.0, "fixed": true}, {"dx": 340.0, "dy": 70.0, "fixed": true}, {"dx": 470.0, "dy": 0.0, "fixed": true} ],   # 海盗船: 3假人聚目标区→首发看后方演出船俯冲冲锋撞该区(200码1.0A魔法+击飞2s+大水花)→转变实体海盗船(pirate-ship立绘)留场射击·后续充能满看海盗龟放霰弹(60度扇8颗)
	"pirate:-1": [ {"dx": 130.0, "dy": 0.0}, {"dx": 460.0, "dy": -70.0, "fixed": true} ],   # 海盗被动掠夺: 开场看登场轰击(船发炮弹→随机敌25%maxHp真伤); 近战假人打死海盗→死亡钩索(demo抓最远那只假人展示拉回·甩钩爪+链条猛拉回尸位+25%maxHp真伤·_pdeath_demo不真死循环)
	"candy:0": [ {"dx": 120.0, "dy": 0.0} ],   # 糖果拳普攻: 单假人贴脸→看糖果拳命中糖爆+减攻标
	"candy:1": [ {"dx": 140.0, "dy": 0.0, "fixed": true}, {"dx": 240.0, "dy": 0.0, "fixed": true}, {"dx": 340.0, "dy": 0.0, "fixed": true} ],   # 糖果锤: 3假人一直线(200码内)→看举锤蓄力猛砸+沿线糖爆冲击+均分伤+回血
	"candy:2": [ {"dx": 300.0, "dy": -80.0, "fixed": true}, {"dx": 300.0, "dy": 80.0, "fixed": true}, {"dx": 460.0, "dy": 0.0, "fixed": true} ],   # 糖衣炮弹: 3假人聚敌区→看糖弹从天翻滚落下8跳·落点局部糖爆+敌减速/友糖盾
	"candy:3": [ {"dx": 300.0, "dy": -70.0, "fixed": true}, {"dx": 300.0, "dy": 70.0, "fixed": true} ],   # 糖果炸弹: 开局看糖果炸弹在场(缩小/糖泡)+反复喂养涨大; 炸弹死亡看大糖爆(HP衰减8%/s几秒后死)
	"candy:-1": [ {"dx": 260.0, "dy": 0.0, "fixed": true} ],   # 糖果被动甜蜜掠夺: 1肥假人(高maxHp)→开场看粉色精华从它流向糖果龟(吸25%maxHp回满)
	"bubble:0": [ {"dx": 120.0, "dy": 0.0} ],   # 泡泡攻击普攻: 单假人贴脸→看泡泡三连击命中泡泡爆+泡沫
	"bubble:1": [ {"dx": 200.0, "dy": -60.0}, {"dx": 200.0, "dy": 60.0} ],   # 泡泡盾: 2假人打泡泡龟(单龟=盾套自己)→看泡泡罩跟随4秒+到期爆裂全体敌魔法+泡沫涌
	"bubble:2": [ {"dx": 260.0, "dy": 0.0, "fixed": true} ],   # 泡泡束缚: 单假人→看气泡牢笼罩住3秒(跟随)+定身+每受击减双抗
	"bubble:3": [ {"dx": 330.0, "dy": 0.0, "fixed": true} ],   # 泡泡爆破(马尔扎哈Q): 单中距目标(泡泡龟站桩·预置满泡泡值)→看目标两侧现两门+门间竖起虚空泡沫墙+消耗泡泡值魔法(门/墙清晰展开不挤施法者)
	"bubble:-1": [ {"dx": 150.0, "dy": -55.0}, {"dx": 150.0, "dy": 55.0} ],   # 泡泡被动泡沫: 2假人打泡泡龟(存泡泡值)→每3秒放泡泡弹打最近敌+回血泡泡
	"line:0": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 线条素描普攻: 单假人→看落笔墨线勾+命中墨溅+头顶墨迹层数徽章递增
	"line:1": [ {"dx": 260.0, "dy": -70.0, "fixed": true}, {"dx": 260.0, "dy": 70.0, "fixed": true} ],   # 线条连笔: 最近2假人→看两敌间画墨线连接3秒+各叠墨迹+伤害传导
	"line:2": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 线条画龙点睛: 单假人(线条龟普攻先叠墨迹)→看对最高墨迹敌大终笔墨挥+点睛大墨爆(伤害随层暴涨)
	"line:3": [ {"dx": 220.0, "dy": -70.0, "fixed": true}, {"dx": 220.0, "dy": 70.0, "fixed": true}, {"dx": 560.0, "dy": -20.0, "fixed": true} ],   # 线条墨水炸弹(用户2026-07-15改300码AOE): 2近假人(聚一起)+1远假人(dx560·超300码·屏内可见)→墨弹智能瞄最密集处落点+300码环+只炸圈内2近(远的不吃伤=看范围)
	"line:-1": [ {"dx": 260.0, "dy": 0.0, "fixed": true} ],   # 线条被动墨迹: 单假人→线条龟普攻/技能叠墨迹(头顶徽章)→每受伤额外+5%/层真实伤
	"lightning:0": [ {"dx": 220.0, "dy": 0.0, "fixed": true}, {"dx": 400.0, "dy": -70.0, "fixed": true}, {"dx": 560.0, "dy": 50.0, "fixed": true} ],   # 闪电普攻: 3假人成链→看一道锯齿电弧劈主目标+依次接力连锁2跳(×0.6递减)+各叠电击层徽章
	"lightning:1": [ {"dx": 240.0, "dy": -60.0, "fixed": true}, {"dx": 240.0, "dy": 60.0, "fixed": true} ],   # 涌动: 2假人→看自身涌起电流增伤光环5秒+立即对目标1次真伤电击(期间被动电击真伤+50%)
	"lightning:2": [ {"dx": 200.0, "dy": -120.0, "fixed": true}, {"dx": 200.0, "dy": 120.0, "fixed": true}, {"dx": 340.0, "dy": -55.0, "fixed": true}, {"dx": 340.0, "dy": 55.0, "fixed": true}, {"dx": 290.0, "dy": 0.0, "fixed": true} ],   # 雷暴: 5假人聚拢居中(原推到右边缘→云和落雷被裁)→敌上空生大风暴云→20道天降竖直落雷(闪电龟自有lightning-0/3·非被动落雷)随机轰击+各叠电击层
	"lightning:3": [ {"dx": 150.0, "dy": -70.0}, {"dx": 150.0, "dy": 70.0}, {"dx": 230.0, "dy": 0.0} ],   # 雷盾: 3假人贴近还手→看以雷电包裹自身(脚下电爆环+3道电弧环绕5秒)+护盾在时每挨一段反击0.3A魔法叠电击(2026-08-02 更正: 第四轮已 0.1→0.3, 见 battle_damage.gd:178)
	"lightning:-1": [ {"dx": 180.0, "dy": -60.0}, {"dx": 180.0, "dy": 60.0} ],   # 雷电被动: 2假人贴近→每4秒自动电击随机敌(common落雷)+普攻/电击叠电击层徽章→满8层引爆(清零·区别于雷暴的自有落雷)
	"phoenix:0": [ {"dx": 150.0, "dy": -45.0, "fixed": true}, {"dx": 150.0, "dy": 45.0, "fixed": true} ],   # 灼烧普攻: 2假人在喷火锥前→看持续喷火(70°扇形)+每0.5s伤害+灼烧层
	"phoenix:1": [ {"dx": 140.0, "dy": -70.0}, {"dx": 140.0, "dy": 70.0}, {"dx": 220.0, "dy": 0.0} ],   # 熔岩盾: 3假人贴近还手→看3.5A熔岩护盾4秒+每挨一段反击0.14A魔法
	"phoenix:2": [ {"dx": 330.0, "dy": 0.0, "fixed": true} ],   # 烫伤: 单假人远处→看蓄力投火球(1.5A魔法)+命中爆开+灼烧/破盾/减攻防抗/治疗削减
	"phoenix:3": [ {"dx": 160.0, "dy": -50.0}, {"dx": 160.0, "dy": 50.0} ],   # 强化涅槃(技三): 2假人→看自身烈焰加速火环(+50%攻速+50%移速4秒·喷火随攻速增伤)
	"phoenix:-1": [ {"dx": 160.0, "dy": -55.0}, {"dx": 160.0, "dy": 55.0} ],   # 涅槃被动: 2假人(注: 评审受审龟免死→复活需真死·此处看被动登场态·复活演出需F5真战)
	"lava:0": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 熔岩弹普攻: 单假人射程内→看熔岩弹弹道+命中(0.6A+4%maxHp魔法)+灼烧层
	"lava:1": [ {"dx": 260.0, "dy": -70.0, "fixed": true}, {"dx": 260.0, "dy": 70.0, "fixed": true}, {"dx": 360.0, "dy": 0.0, "fixed": true} ],   # 地裂: 3假人聚拢→敌最密处生成180码岩浆池5秒(池内0.06A魔/0.5s+减速35%+魔抗-30%)
	"lava:2": [ {"dx": 240.0, "dy": -55.0, "fixed": true}, {"dx": 240.0, "dy": 55.0, "fixed": true} ],   # 岩浆涌动: 2假人贴近→蓄力→目标脚下岩浆柱击飞附近(1.5A魔)+自身0.8A永久护盾
	"lava:3": [ {"dx": 200.0, "dy": 0.0, "fixed": true}, {"dx": 400.0, "dy": 0.0, "fixed": true}, {"dx": 600.0, "dy": 0.0, "fixed": true} ],   # 熔岩爆发(普通形态): 3假人一线→智能冲刺+下发熔岩弹贯穿全场(沿途每敌0.6A+4%maxHp+灼烧)
	"lava:-1": [ {"dx": 150.0, "dy": -60.0}, {"dx": 150.0, "dy": 60.0} ],   # 熔岩之心被动: 2假人贴近对打→出伤/承伤各10%转怒气→满100变身火山龟15秒(血量/攻击/护甲/体型全涨)
	"cyber:0": [ {"dx": 200.0, "dy": 0.0, "fixed": true}, {"dx": 370.0, "dy": 0.0, "fixed": true}, {"dx": 540.0, "dy": 0.0, "fixed": true} ],   # 贯穿激光普攻: 3假人一线→激光穿透打一线全体+浮游炮环绕齐射
	"cyber:1": [ {"dx": 260.0, "dy": -45.0, "fixed": true}, {"dx": 430.0, "dy": 0.0, "fixed": true}, {"dx": 600.0, "dy": 45.0, "fixed": true} ],   # 能量大炮(照Lux R): 3假人带宽±70内→蓄力瞄准线→贯屏青蓝巨柱+衰减残光+衍射颗粒
	"cyber:2": [ {"dx": 220.0, "dy": -85.0}, {"dx": 220.0, "dy": 85.0}, {"dx": 320.0, "dy": 0.0} ],   # 侵入: 3假人(不固定)→黑1只故障化标识+倒戈4秒打原队友
	"cyber:3": [ {"dx": 150.0, "dy": -55.0}, {"dx": 150.0, "dy": 55.0} ],   # 智能AI: 2假人贴近→赛博冲刺重定位(kite拉开距离)+充能层
	"cyber:-1": [ {"dx": 130.0, "dy": 0.0} ],   # 浮游炮被动(用户2026-07-16: 固定赛博+1攻击假人看清演出): 炮攒编队→打死→炮群自由飞散(全场随机点)→龙骨炮齐射→机甲5秒组装→循环
	"crystal:0": [ {"dx": 100.0, "dy": 0.0, "fixed": true} ],   # 水晶刺普攻(近战): 单假人贴脸→碎晶突刺+0.6A物+1.5%maxHp魔+叠1结晶(头顶徽章+环绕碎晶)
	"crystal:1": [ {"dx": 130.0, "dy": -60.0}, {"dx": 130.0, "dy": 60.0} ],   # 水晶壁垒(用户2026-07-16改制): 2假人围打→1A+5%maxHp盾(锁龟能)·盾破/到期→700码直线水晶刺(地底段段刺出+2结晶+击飞0.8s+减速50%3s)
	"crystal:2": [ {"dx": 220.0, "dy": -80.0, "fixed": true}, {"dx": 220.0, "dy": 80.0, "fixed": true}, {"dx": 380.0, "dy": 0.0, "fixed": true}, {"dx": 640.0, "dy": 0.0, "fixed": true} ],   # 碎晶爆破(2026-07-15改350码): 3近假人圈内吃3段碎晶坠落+1远假人(640>350)圈外不中=看范围
	"crystal:3": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 水晶球: 登场即召水晶球实体(50%HP/同ATK)每5秒双段光线+主动时本体同步射线·共享结晶层
	"crystal:-1": [ {"dx": 110.0, "dy": -50.0, "fixed": true}, {"dx": 110.0, "dy": 50.0, "fixed": true} ],   # 结晶共鸣被动: 近战贴脸2假人→普攻叠结晶(徽章+环绕碎晶)满5引爆(19%maxHp魔+永久-20%魔抗)+受魔伤减免20%
	"chest:0": [ {"dx": 100.0, "dy": -45.0, "fixed": true}, {"dx": 100.0, "dy": 45.0, "fixed": true} ],   # 宝箱砸击普攻(近战): 2假人贴脸→K'Sante式前方短直线AOE扫击
	"chest:1": [ {"dx": 120.0, "dy": -55.0}, {"dx": 120.0, "dy": 55.0} ],   # 清点财宝(2026-07-16改): 2假人围打(掉血)→回5%HP(每1000财宝治疗+10%)+0.6A盾
	"chest:2": [ {"dx": 200.0, "dy": -90.0, "fixed": true}, {"dx": 200.0, "dy": 90.0, "fixed": true}, {"dx": 340.0, "dy": 0.0, "fixed": true} ],   # 财宝风暴: 3假人聚拢→以目标为心400码金币旋风(14金币升螺旋)+5跳伤害
	"chest:3": [ {"dx": 220.0, "dy": 0.0, "fixed": true}, {"dx": 420.0, "dy": 0.0, "fixed": true}, {"dx": 620.0, "dy": 0.0, "fixed": true} ],   # 财宝炮击(2026-07-15换皮金币洪流): 3假人一线→蓄力0.4s→喷金币+金块洪流·线上各3A物理+击飞击退+命中金币爆
	"chest:-1": [ {"dx": 110.0, "dy": -50.0, "fixed": true}, {"dx": 110.0, "dy": 50.0, "fixed": true} ],   # 藏宝图被动: 贴脸2假人→出伤攒财宝值→开箱(头顶弹战利品图标+金环+回血·基础→进阶→传说一场最多5件)
	"elite:0": [ {"dx": 130.0, "dy": 0.0} ],   # 精英小将(虐杀原形)普攻+旋刃: 1假人→长手刃1A黑红刀光·第5击旋刃360°1.3A+吸血50%
	"elite:1": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 铁锁: 假人300码(在150~350触发带内)→链射顿+眩晕0.4s→拉体落身后1A魔(demo每~4.5s传回再看·范围2026-07-18改150~350)
	"elite:2": [ {"dx": 200.0, "dy": -60.0, "fixed": true}, {"dx": 350.0, "dy": 40.0, "fixed": true}, {"dx": 450.0, "dy": -30.0, "fixed": true} ],   # 铁锤: 3固定假人在锥内→60°500码8波刺浪1.5A+击飞·每第3次跃起700码全域3A+击飞1.2s
	"elite:-1": [ {"dx": 300.0, "dy": 0.0, "fixed": true} ],   # 吞噬+铁链二合一(用户2026-07-16): 假人300码钉18%残血带技能→铁链拉体→砍→吞噬(复活循环)→传回左侧再铁链
	"space:0": [ {"dx": 320.0, "dy": 0.0, "fixed": true} ],   # 星光弹普攻: 单假人射程内→星形弹道+0.9A魔+5%当前HP+星能追加真伤(白字)
	"space:1": [ {"dx": 250.0, "dy": -70.0, "fixed": true}, {"dx": 420.0, "dy": 0.0, "fixed": true}, {"dx": 600.0, "dy": 70.0, "fixed": true} ],   # 虫洞: 3假人沿线→140码/s缓慢黑洞推进+吸经过敌90码+星尘吸入粒子
	"space:2": [ {"dx": 220.0, "dy": -90.0, "fixed": true}, {"dx": 220.0, "dy": 90.0, "fixed": true}, {"dx": 360.0, "dy": 0.0, "fixed": true} ],   # 星波(星能满→彗星): 3假人→环形星波+满能紫环预警1s→流星斜射→尘暴星星闪点冲击环
	"space:3": [ {"dx": 240.0, "dy": -100.0, "fixed": true}, {"dx": 240.0, "dy": 100.0, "fixed": true}, {"dx": 400.0, "dy": 0.0, "fixed": true} ],   # 扭曲空间「奇点」: 3假人散开→吸入1.03s→爆发帧0.8A魔; 星能满=+击飞拽空中0.57s穿奇点镜像落对侧换位(头顶紫螺旋+尾迹+白火花)+吸积盘
	"space:-1": [ {"dx": 300.0, "dy": -50.0, "fixed": true}, {"dx": 300.0, "dy": 50.0, "fixed": true} ],   # 星能被动: 2假人→造伤35%转星能(资源条)+普攻弹道命中帧追加12%当前星能真伤(白字·用户2026-07-16封板)
	"hiding:0": [ {"dx": 110.0, "dy": 0.0, "fixed": true} ],   # 缩壳普攻: 贴脸假人→每击硬化微光+每5层甲片环+0.1A盾
	"hiding:1": [ {"dx": 140.0, "dy": -60.0}, {"dx": 140.0, "dy": 60.0} ],   # 缩头: 假人打缩头(看80%减伤+土棕硬壳罩3秒)+能量束给随从
	"hiding:2": [ {"dx": 140.0, "dy": 0.0} ],   # 防御: 壳青绿护罩4秒呼吸→碎裂+绿光点转血
	"hiding:3": [ {"dx": 220.0, "dy": 0.0, "fixed": true} ],   # 强化随从: 金色注入光束+3金星绕随从升腾
	"hiding:-1": [ {"dx": 240.0, "dy": -80.0}, {"dx": 240.0, "dy": 80.0} ],   # 喊龟被动: 召唤法阵+光柱+星粒; 随从死→遗志金光点回流主人
	"headless:0": [ {"dx": 110.0, "dy": 0.0, "fixed": true} ],   # 撕咬普攻: 1A物理+3%maxHp魔法双数字
	"headless:1": [ {"dx": 150.0, "dy": -70.0, "fixed": true}, {"dx": 150.0, "dy": 70.0, "fixed": true}, {"dx": 320.0, "dy": 0.0, "fixed": true} ],   # 恐吓: 近2只中招(咆哮气爆+三波纹+颤抖标记)·远1只在200码外不中(验范围)
	"headless:2": [ {"dx": 200.0, "dy": -90.0, "fixed": true}, {"dx": 350.0, "dy": 90.0, "fixed": true}, {"dx": 550.0, "dy": 0.0, "fixed": true} ],   # 万千触须: 3假人散开→全场触须8×5爆出+命中大触须钉住+吸血红珠回流
	"headless:3": [ {"dx": 120.0, "dy": 0.0, "fixed": true}, {"dx": 220.0, "dy": -80.0, "fixed": true}, {"dx": 220.0, "dy": 80.0, "fixed": true} ],   # 灵魂打击: 正面小簇→3次强化撕咬(牙齿闭合)→第3下蓄力→镰刀横扫100°锥击退300+诅咒
	"headless:-1": [ {"dx": 130.0, "dy": -60.0}, {"dx": 130.0, "dy": 60.0} ],   # 亡灵被动: 挨打残血加攻·首次濒死金环5秒免死(需假人还手)
	"shell:0": [ {"dx": 110.0, "dy": 0.0, "fixed": true}, {"dx": 190.0, "dy": 70.0, "fixed": true} ],   # 龟壳打击: 物/真逐击交替+副目标120码溅射50%
	"shell:1": [ {"dx": 150.0, "dy": 0.0, "fixed": true} ],   # 吸收: 4红珠鱼贯流向龟壳+maxHp转移
	"shell:2": [ {"dx": 200.0, "dy": -70.0, "fixed": true}, {"dx": 200.0, "dy": 70.0, "fixed": true} ],   # 复制: 两侧镜像残影签名→轮流放2敌技60%
	"shell:3": [ {"dx": 150.0, "dy": 0.0, "fixed": true}, {"dx": 500.0, "dy": 0.0, "fixed": true} ],   # 暗影俯冲: 沿线1近1远→起跳暗焰+冲刺+沿途暗焰痕+落地爆+斑块燃烧区→羽化入隐
	"shell:-1": [ {"dx": 130.0, "dy": -60.0}, {"dx": 130.0, "dy": 60.0} ],   # 气场觉醒/储能: 2假人还手(REVIEW_DUMMY_ATTACKS须true)→受伤储能→空气扭曲起手+黄色远古双层波带+6金星; 第10/20秒觉醒金光
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
	"__trainer__": {"phys": 1.0, "hits": 1},                                       # 训龟大师扔石头: 1.0×ATK, 而它 ATK=1 → 恰好 1 点物理
	"stone":    {"phys": 0.7, "def": 1.5, "mr": 0.8, "hits": 1},                    # +护甲魔抗(坦克)
	"bamboo":   {"phys": 0.4, "selfhp": 0.03, "hits": 1},                           # 单段 0.4ATK+3%自身HP(用户2026-06-29)
	"angel":    {"phys": 1.0, "hits": 1},                                          # 远程平A 1.0ATK单段(用户)+审判被动
	"ice":      {"phys": 1.0, "magic": 1.0, "hits": 1, "alt_each": true},           # 单段逐次交替物/魔 1.0ATK(用户2026-07-28: 0.8→1.0·配冰柱层加强)
	"ninja":    {"phys": 1.0, "hits": 1, "rider": "bleed"},                         # 斩击(封板): 近战1A物理+2层流血; 冲击已转被动auto-dash
	"ghost":    {"phys": 0.5, "true": 0.7, "hits": 1},                             # 物+真 (用户2026-07-28削弱: 0.4物+0.9真 → 0.5物+0.7真)
	"diamond":  {"phys": 0.7, "def": 0.6, "mr": 0.6, "hits": 1},                    # +护甲魔抗
	"fortune":  {"phys": 1.0, "gold": 0.02, "hits": 1},                            # 1下(用户; 回合制原2下)
	"dice":     {"phys": 0.9, "critflat": 55.0, "hits": 1},                         # 90%物理+5500%暴击率flat·单段近战(对齐回合制 diceAttack critBonusMult=55·无实时原话)
	"rainbow":  {"phys": 0.9, "hits": 1},                                          # 单段0.9物理(用户2026-07-02, 原魔法1.4×2)
	"gambler":  {"phys": 1.0, "hits": 1},                                          # 甩扑克牌(封板L296·用户改): 1.0A物理单段(原3段1.35A=旧值)·多重打击被动复放整发普攻(_gambler_sys._gambler_multi_cd)
	"hunter":   {"phys": 1.0, "hits": 1},   # 封板: 普攻1.0A物理(残血追猎+50%攻速在atk_cd处)
	"pirate":   {"phys": 1.0, "hits": 1, "selfheal": 0.2},                          # 弯刀(封板L382·近战): 1.0A物理+自愈0.2A(每击回0.2×ATK生命)·[段数1=单弯刀斩·手感留F5]
	"candy":    {"phys": 1.1, "selfhp": 0.03, "hits": 1, "rider": "atkdn"},         # +自HP+减攻debuff (用户2026-07-28: 0.05→0.03)
	"bubble":   {"phys": 1.5, "hits": 3},
	"line":     {"magic": 1.0, "hits": 1},                                          # 素描:1A魔法单段(叠1墨迹走_on_basic_hit·用户设计)
	"lava":     {"magic": 0.6, "hp": 0.04, "hits": 1, "rider": "burn", "burnScale": 0.07},   # 熔岩弹: 0.6魔+4%目标HP+0.125ATK灼烧层 (用户2026-06-30)
	"crystal":  {"phys": 0.6, "hits": 1},                                          # 水晶刺(封板L559):0.6A物理+1.5%目标maxHp魔法+叠1结晶(魔法段与结晶都走_on_basic_hit·原hp bonus折进物理=类型错)
	"space":    {"magic": 0.9, "tcurhp": 0.05, "hits": 1},                          # 星光弹: 单段0.9A魔法+5%目标当前HP (封板2026-07-07)
	"hiding":   {"phys": 1.0, "hits": 1, "rider": "shrink"},                        # 缩壳: 1A物理+每击+1甲+1抗+0.1A盾(越打越硬)
	# shell 走 _basic_attack 特判 _shell_sys._shell_basic (1ATK单段·物/真逐攻交替 + 120px范围溅射50%); 不进 _do_basic
}
const DEFAULT_BASIC := {"phys": 1.0, "hits": 1}

# ============================================================================
#  2.5D 坐标 / 渲染常量
# ============================================================================
const AVATAR_DIR := "res://assets/sprites/avatars/"   # 头像兜底 (全身图缺失才退回)
# ══ 训龟大师(用户 2026-07-22 需求3) ══ 场外监视者: 不被索敌/不计团灭/万物伤害降为1
const TRAINER_ID := "__trainer__"
const TRAINER_HP := 500.0
const TRAINER_ATK := 1.0
## (原 TRAINER_ATK_MAGIC_STONE := 10.0 已删 —— 用户 2026-07-31 拍板「魔法石不再提供攻击力倍率」,
##  删掉而不是设成 1.0: 零读者的死常量正是本项目栽过的坑。魔法石的收益现在只在
##  trainer_system.MS_HASTE_PER_STACK 那一条线上。)
## 魔法石普攻附带的魔法伤害 = (MS_BASE + MS_PER_LV × 大轮等级) × 目标最大生命
## 魔法石普攻附带的魔法伤害 = 目标最大生命的固定百分比。
## ★2026-07-30 用户拍板削弱:「附带的魔法伤害削弱为常驻2%」——
##   原来是 (2 + 0.1×大轮等级)%(MS_MAXHP_BASE 0.02 + MS_MAXHP_PER_LV 0.001×lv),
##   Lv1 2.1% … Lv10 3.0%。现在【不随大轮等级涨】, 恒 2%。
##   Lv5 2.5%→2.0%(−20%) · Lv10 3.0%→2.0%(−33%)。
##   动机: 同一轮把攻速叠层改成【跨路保留且不封顶】(见 trainer_system MS_TIER_STACKS 头注),
##   攻速上界抬高后, 再叠一个"随等级涨的按最大生命百分比"就双重放大了。
## ★删掉 MS_MAXHP_PER_LV 而不是把它设成 0 —— 零读者的死常量正是本项目栽过的坑
##   (HOOK_VULN_MULT 曾在游戏代码里零读者, 唯一读者是门禁, 于是门禁会把错文案判成正确)。
const MS_MAXHP_PCT := 0.02
const TRAINER_RANGE := 2000.0
const TRAINER_ATK_INTERVAL := 1.5
const TRAINER_MOVE_SPD := 130.0                       # 移速(码/秒), 用户 2026-07-22 拍板
# ★钩锁技能(点3·法术圆盘第一个技能, 用户2026-07-23): 参考 LoL 锤石Q。
const HOOK_RANGE := 600.0        # 射程(码)
const HOOK_CD := 20.0            # 冷却(秒)
const HOOK_CD_MISS := 10.0       # 空放(没钩到人)→只冷却10秒(返还10秒)
const HOOK_STUN := 4.0           # 钩住眩晕(秒, 吃韧性)
# ── 手感(仔细参照 Wild Rift 锤石Q·用户2026-07-24「不太行」返工) ──
const HOOK_WINDUP := 0.35        # 施法前摇: 大师举钩蓄力, 松手/按Q后不立刻丢(锤石Q有前摇, 期间不转身不动)
const HOOK_MISSILE_SPD := 570.0  # 钩子飞行速度(码/秒·用户2026-07-26 再−40%: 950→570·更像可躲skillshot·600码约1.05秒到)
# 拖拽=【一段段的拽】(用户2026-07-26 明确: 每秒拽1下·共4秒·拖4下·每下70码=总280码) —— 非匀速
const HOOK_TUG_DELAY := 0.1      # 钩住后第一下拽的延迟(t≈0.1)
const HOOK_PULL_INTERVAL := 1.0  # 两下拽之间的间隔(每 1.0s 拽一下 → 4秒眩晕内 t≈0.1/1.1/2.1/3.1 共4下)
const HOOK_TUG_DUR := 0.2        # 每一下"拽"的快速位移时长(0.2s猛滑·其余停顿=一下一下拽感)
const HOOK_HIT_R := 70.0         # ★钩头【飞行中】的碰撞半径(码) —— 真 skillshot 靠这个每帧判, 不再出手就锁定
const HOOK_TUG_DIST := 70.0      # 每一下拽把目标朝大师拽近的距离(码·4下×70=280码)
const HOOK_VULN_MULT := 1.25     # 被钩4秒内受到伤害 ×1.25  ★真事实源: _mitigate_incoming 读它(2026-07-30 修好前那里是硬编码 1.25, 本常量【游戏代码零读者】)
const WHISTLE_SHRED_MULT := 0.7   # 口哨②灵体气波削甲: 护甲 ×0.7 (-30%)
const GLACIER_LEN := 500.0       # 冰川长度(码)
const GLACIER_WIDTH := 90.0      # 冰川判定带宽(码·文案没写这一项)
const GLACIER_SEC := 6.0         # 冰川持续(秒)
const GLACIER_VULN_MULT := 1.2   # 站冰川上受到伤害 ×1.2  ★同上: 原来也是硬编码在 _mitigate_incoming, 连常量都没有

# ══ 训龟大师【主动技能】注册表(用户2026-07-23 需求: 装配系统·单主动槽·只用Q) ══
# id → {名/圆盘图标/冷却}。大师单位带 _tr_active(装配的主动 id) + 通用 _active_cd(所有主动共用一个冷却字段)。
# 施放统一走 _trainer_sys._cast_active(u, aim), 按 _tr_active 分派到各技能。圆盘显示已装配技能的图标+冷却。
const TRAINER_SKILLS := {
	"hook":        {"name": "钩锁",   "icon": "res://assets/sprites/vfx/hook-skill-icon.png",   "cd": 20.0, "range": 600.0, "aim": "dir"},
	"fury_potion": {"name": "怒火药水", "icon": "res://assets/sprites/vfx/fury-potion-icon.png",  "cd": 16.0, "range": 700.0, "aim": "point"},
	"whistle":     {"name": "口哨",   "icon": "res://assets/sprites/vfx/whistle-icon.png",      "cd": 14.0, "range": 0.0,   "aim": "none"},
	"glacier":     {"name": "冰川",   "icon": "res://assets/sprites/vfx/glacier-icon.png",      "cd": 17.0, "range": 500.0, "aim": "dir"},
	# ★aim:"target" 是【新增的第四种瞄准模式】(原来只有 dir 方向 / point 落点 / none 无需瞄准)。
	#   用户 2026-07-28:「这个不是直线发射吧，而是像 lol 安妮的 Q 一样弹道锁头」——
	#   即指定一个【敌方单位】, 弹道自动跟到它身上, 不会因为它走开而落空。
	"hunt_order":  {"name": "猎龟令", "icon": "res://assets/sprites/vfx/hunt-order-icon.png",   "cd": 30.0, "range": 600.0, "aim": "target"},
	"tame":        {"name": "驯服",   "icon": "res://assets/sprites/vfx/tame-icon.png",         "cd": 60.0, "range": 600.0, "aim": "target"},
}

# ── 猎龟令(用户 2026-07-28) ──
const HUNT_CD := 30.0
const HUNT_RANGE := 600.0
const HUNT_SEC := 15.0            # 标记持续
const HUNT_TAUNT_R := 400.0       # 以【目标】为圆心的嘲讽半径(圈随目标移动)
const HUNT_VULN := 1.15           # 被标记者受伤 ×1.15
const HUNT_MISSILE_SPD := 1400.0  # 锁头弹道飞行速度(码/秒)

# ── 驯服(用户 2026-07-28) ──
const TAME_CD := 60.0
const TAME_RANGE := 600.0
const TAME_REVIVE_PCT := 0.30     # 死后按 30% 最大生命重生
const TAME_REVIVE_SEC := 2.5      # 重生演出时长(期间无敌不可选中)
const TAME_DECAY_PCT := 0.02      # 归顺后每秒损失 2% 最大生命
const TAME_MISSILE_SPD := 1200.0
const VirtualJoystick := preload("res://scripts/scenes/virtual_joystick.gd")
const SpellDisc := preload("res://scripts/scenes/spell_disc.gd")
const HOOK_ICON := "res://assets/sprites/vfx/hook-skill-icon.png"   # 圆盘技能图标(精修·带链条+青芒宝石); 飞行弹体仍用 trainer-hook.png
## 立绘: 用户要「像素风的冒险家」, 形象未定 —— 有真图就用, 没有则退回占位并 warning。
## ★不做成静默兜底: 占位图和最终形象长得完全不一样, 悄悄用会让人以为已经做完了。
const TRAINER_SPRITE := "res://assets/sprites/pets/trainer.png"

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
	"ninja":  ["pets/animations/ninja/slash.png", 16.0],
	"__minion_elite__": ["pets/animations/elite/attack.png", 12.0],
	"__minion_front__": ["pets/animations/melee/attack.png", 12.0],
}
# 精英小将的 5 个非标准动作 (2026-07-21 PixelLab pro 生成, south-west 朝向 = 原图朝左口径)。
#   不走 _vfx._play_action —— 那个只认 attack/hurt/death 三种; 这些照忍者 dash/backstab 的做法,
#   在技能代码里直接 _elite_sys._elite_anim() 调。action 名会写进 u["anim_action"], 由 _vfx._play_action 顶部的
#   白名单挡住, 播完前不被普攻/受击换掉。
# 近战小将·人体浪板的分段动作(2026-07-22)。时间轴由代码量出, 见 docs/plans/20260722-五需求方案书.md §4:
#   0.00-0.64 蓄力+起跳 → 0.64-1.28 滞空甩索(0.68 射链) → 1.28-1.58 被拉俯冲(双脚前伸)
#   → 1.58-2.41 踩滑(0.833s) → 2.41 侧跳落地
# ★fps 必须让【动画时长 == 代码节拍】, 否则动画先播完 → _render._advance_anim 立刻回 idle,
#   剩下那段时间角色是【站姿】。2026-07-22 实测(用户追问"时间对不上吗"):
#     leap/throw 7fps → 0.57s vs 节拍 0.64s, 各早完 0.07s
#     surf      12fps → 0.33s vs 节拍 0.833s, 【早完 0.50s】—— 踩着敌人滑行的后半程在站着
#   ★surf 曾一度改成"把4帧重复成10帧仍12fps", 被用户质疑「你这么循环, 你自己觉得没问题吗」——
#     确实有问题: 10帧=2.5个循环会【停在半个循环上】; 2.5轮/0.833s≈每秒摆3次, 比走路
#     (11帧@12fps=0.92s一个步循环≈每秒1.1步)还快, 那是抖不是滑; 而且 pro 出的4帧不是为循环
#     设计的, 帧3接帧0没有连续性保证, 循环反而把接缝多暴露两次。
#     改回 4帧@4.8fps: 每帧208ms, 项目现有区间是62-160ms, 略慢但同量级 —— 滑板保持平衡
#     本来就是"摆一个姿势保持住"。
const ACTION_MELEE := {
	"leap":  ["pets/animations/melee/leap.png", 6.25],    # 4帧 / 0.64s(0.00-0.64 蓄力+起跳)
	"throw": ["pets/animations/melee/throw.png", 6.25],   # 4帧 / 0.64s(0.64-1.28 滞空甩索)
	"dive":  ["pets/animations/melee/dive.png", 13.0],    # 4帧 / 0.31s ≈ 节拍 0.30s
	"surf":  ["pets/animations/melee/surf.png", 4.8],     # 4帧 / 0.833s = 每帧208ms(保持平衡姿势, 不是高频抖)
	"land":  ["pets/animations/melee/land.png", 13.0],    # 4帧 / 0.31s ≈ 落地 0.30s
}
# ★fps 让【动画时长 == 技能节拍】。2026-07-22 复查发现精英五段有四段对不上,
#   动画先播完 → _render._advance_anim 立刻回 idle → 剩下那段时间角色是站姿:
#     whirl      0.333s vs 节拍 0.42s  早完 0.09s
#     hammer     0.364s vs 节拍 0.43s  早完 0.07s
#     hammer_big 0.400s vs 节拍 1.47s  【早完 1.07s】= 空中蓄力那 1 秒角色站着悬停
#     consume    0.900s vs 节拍 1.50s  早完 0.60s
#   节拍取自代码真实数字: whirl 的 tween 0.42 / hammer 撞击帧 delay 0.43 /
#   hammer_big 0.35跳起+1.0空中蓄力+0.12下砸 / consume 的 _pending_shots delay 1.5。
#   ★hammer_big 单靠 fps 摊不平(4帧/1.47s = 每帧368ms, 远超项目 62-208ms 区间), 因为它
#     两头是快动作、中间是 1 秒【悬停】。改成按节拍排帧序 0,0,1,1,[2]×12,3,3 = 18帧,
#     即给"空中蓄力"那一帧做 hold —— 这是动画标准手法, 与"重复凑循环"不是一回事。
const ACTION_ELITE := {
	"whirl":      ["pets/animations/elite/whirl.png", 9.52],      # 4帧 / 0.42s
	"hammer":     ["pets/animations/elite/hammer.png", 9.30],     # 4帧 / 0.43s
	"hammer_big": ["pets/animations/elite/hammer_big.png", 12.24],# 18帧 / 1.47s(含1s hold)
	"whip":       ["pets/animations/elite/whip.png", 14.0],       # 7帧 / 0.50s ≈ 节拍 0.48s
	"consume":    ["pets/animations/elite/consume.png", 6.0],     # 9帧 / 1.50s
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
# 走路动画表 (移动时循环播·有 run.png 的龟): ninja/ghost. 停下回 idle.
const ACTION_RUN := {
	"ninja": ["pets/animations/ninja/run.png", 12.0],
	"ghost": ["pets/animations/ghost/run.png", 12.0],
	# ★精英小将(2026-07-21 PixelLab 生成)。键是 __minion_elite__ 不是 __minion__ ——
	#   三种小将共用 id, 用 id 会让普通小将也套精英的帧, 见 _anim_key()。
	"__minion_elite__": ["pets/animations/elite/run.png", 12.0],
	"__minion_front__": ["pets/animations/melee/run.png", 12.0],
	# 训龟大师(2026-07-23): 走路循环。id 是 __trainer__, _anim_key 直接返回 id → 走到这里。
	#   移动由玩家 _trainer_sys._trainer_move_by 驱动, 但立绘照样流经 _render._update_run_anim(在 for u in _units 里),
	#   靠"帧间位移>0.8"自动切走路/停回 idle —— 不用另写触发。
	"__trainer__": ["pets/animations/trainer/run.png", 8.0],
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
# ③ 深海地面 (ground shader): 中心亮→边缘暗蓝的景深渐变 + 焦散 + 边界环
const GROUND_NEAR := Color(0.42, 0.62, 0.55)    # 场地中心地色 (亮暖沙青; 卡通像素鲜活风, 大猫贤者方向)
const GROUND_FAR := Color(0.13, 0.42, 0.48)   # 远/边缘地色 (亮青水; 远处是明亮浅海不是黑洞)
const CAUSTIC_SPEED := 0.35               # 焦散流动速度
# ④ 竞技场边界软环 (地面上一圈柔光 → 给围合感, 替代硬地平线)
const ARENA_RING_COLOR := Color(0.35, 0.62, 0.78)
const ARENA_RING_A := 0.16
# ⑤ 屏幕暗角 (vignette overlay, CanvasLayer 上一张 radial 渐变铺满 → 四角压暗聚焦中心)
const VIGNETTE_A := 0.5

# ============================================================================
#  Phase 4: 商业级打击感 juice 参数 (全 F5 可调) — 见本文件 §JUICE
#  设计: 所有单位视觉态(squash/stretch scale · 受击闪白 modulate · idle bob)统一由
#  _render._update_world_transforms() 每帧从 per-unit juice 字段重建 → 从 base 精确复原, 不用重叠
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
var _dl_present_t := 0.0            # overview/preview/lane_settle 自动计时(实时5秒)
var _dl_overview_shown := false     # 3路总览一场只放一次
var _dl_pending_loser := ""         # lane_settle 待推进的败方
var _dl_present_root: Control = null   # 呈现overlay根节点
const DL_PRESENT_SEC := 5.0
var _st_lane_hist: Array = []   # 已结束战场的统计快照(纯数据行, 不引单位字典): [{lane,left:[row],right:[row]}] — 结算表要含前面战场(用户2026-07-19"只展示了当前战场的总结")
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
var _vfxiso := false                      # 纯特效隔离模式(VFXISO env): 黑底+无地面+藏单位立绘/UI, 只留特效对比参考
var _render := BattleRender.new(self)   # 战斗渲染/动画显示层(每帧插值/世界变换/跑动画/覆盖/dot飘字/相机抖/技能文案·纯视觉不改战斗态)(2026-07-26 抽出)
var _aim := BattleAim.new(self)   # 训龟大师战场瞄准子系统(圆盘/按住Q输入 + 按技能类型指示器·状态仍挂本场景)(2026-07-26 抽出还债)
var _targeting := BattleTargeting.new(self)   # 目标选择/敌我查询(最近敌/获取目标/敌方/友方/可选目标·纯确定性查询无RNG)(2026-07-26 抽出)
var _damage := BattleDamage.new(self)   # 战斗结算: 两伤害路(_apply_damage DoT/真伤 + _apply_damage_from 普攻/技能·§3.3)+治疗/护盾/buff/眩晕/击退/DoT机制(含crit/dodge RNG·确定性核心)(2026-07-26 抽出)
var _ballistics := BattleBallistics.new(self)   # 弹道: 发射(_fire_*各弹种)+逐帧推进(_step_projectiles/_step_pending_shots/_step_homing_arrow)+霰弹弹珠·几何确定性无RNG(2026-07-26 抽出)
var _spawn := BattleSpawn.new(self)   # 单位生成/生命周期: 造单位(_make_unit)+双路/单路布阵spawn+训龟大师+spawn被动+召唤物(summon/藏身小将/海盗船)(2026-07-26 抽出)
var _hud := BattleHud.new(self)   # 战斗HUD/面板构建与显示: UI层/暂停/日志/统计/编辑笔刷/队伍头像框/胜负横幅/点龟详情面板/触控盘·纯UI(2026-07-26 抽出)
var _world: Node3D                        # 3D 内容挂载点 (SubViewport 内)
var _sub: SubViewport
var _projectiles: Array = []              # 飞行中的 3D 投射物 {node, from, to, tgt, dmg, magic, src, t, dur}
var _lava_sys := LavaSystem.new(self)   # 熔岩带/火山系统(2026-07-25 从本文件抽出)
var _smolder_sys := SmolderSystem.new(self)   # 阴燃母火系统(2026-07-25 抽出)
var _dragon_sys := DragonSystem.new(self)   # 龙烈焰系统(2026-07-25 抽出)
var _star_sys := StarSystem.new(self)   # 星龟技能系统(2026-07-25 抽出)
var _phoenix_sys := PhoenixSystem.new(self)   # 凤凰·烈焰扇/灼烧系统(2026-07-25 抽出)
var _headless_sys := HeadlessSystem.new(self)   # 无头骑士·恐惧/镰刀/触须系统(2026-07-25 抽出)
var _glacier_zones: Array = []            # 冰川带(训龟大师·用户2026-07-23) {from, dir, len, width, until, side}: 站带上的敌-40%移速+受伤+20%

# --- 暂停 + 战斗日志 (R2b, 用户 2026-07-11) ---
const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")
var _joystick: Control = null             # 移动端虚拟摇杆(PC 上为 null → 走键盘)
var _spell_disc: SpellDisc = null         # 法术圆盘(点3): 钩锁钮·右下角·显CD; PC按Q, 移动端点它施法
var _disc_aiming: bool = false            # 移动端正按住圆盘拖动瞄准中(Wild Rift 式·用户2026-07-24)
var _disc_aim_dir: Vector2 = Vector2.ZERO # 当前瞄准方向(战场系·单位向量)
var _aim_ind: Dictionary = {}             # R2 瞄准指示器持久节点(band/ring/land/tgt·按技能类型建·瞄准结束清)
var _q_aiming: bool = false               # R2 PC 按住 Q 瞄准中(松开释放·指示器跟随鼠标)
var _tutorial: Node = null                # 新手引导实例(GameState.tutorial 才建); null=不在教程里
var _tut_place_shown: bool = false        # 教学 match1: 摆位引导只挂一次(首路), 别每路都弹
var _surrender_panel: Control = null      # 投降确认浮层(取消/确认认输), 默认隐; 取代原暂停浮层(用户2026-07-30)
var _surrender_btn: Button = null          # 🏳 投降按钮(原 ⏸ 暂停位); 结算后 disabled
var _battle_log: Array = []               # 战斗日志 bbcode 行, 封顶 _LOG_CAP(参 soak 教训防无限增长)
var _log_panel: Control = null            # 日志浮层(可滚动), 默认隐
var _log_rt: RichTextLabel = null         # 日志文本(面板开着才实时追加)
const _LOG_CAP := 200

# --- 战中伤害统计面板 (R2c, 照回合制 DmgStatsPanel 样式: 4Tab×双列×分段条) ---

# --- 局内信息 UI (左右队头像框 + 点单位看详情面板; 纯 UI 不动玩法) ---
var _team_panel_left: VBoxContainer = null    # 屏幕左侧头像框栏 (左队主龟)
var _team_panel_right: VBoxContainer = null   # 屏幕右侧头像框栏 (右队主龟)
## 局内装备格读数(层数徽章 / 充能条)的两张纯数据表 —— 正文在 `scripts/gamedata/equip_readouts.gd`。
## ★新读数往那儿加, **不要在演出层自造头顶条**(用户 2026-08-08 定)。
const PANEL_COUNT := EquipReadouts.COUNT
const PANEL_CHARGE := EquipReadouts.CHARGE
var _selected_unit = null                     # 当前选中(点击)的单位 Dictionary, 高亮其框
var _info_panel: PanelContainer = null        # 详情面板 (居中, 显等级/属性/被动/技能/装备); 重开覆盖

# --- 🛠 调试场 (DEBUG ARENA): 自由摆位编辑模式 (从主菜单进; 默认关, 不影响正常战斗) ---
#   DEBUG_EDIT=true 时 _spawn._spawn_teams 跳过自动出生(空场), 进编辑模式: 点空地摆兵/拖拽挪位/右键删,
#   假人可设血量+不死开关. ▶开始 起战斗(模拟跑), ⏸编辑 回编辑(按摆位重新生成), 清空 全删.
static var DEBUG_EDIT := false            # ← MainMenu 设 true 后 change_scene 进入; 离场重置 false
## ★关训龟大师(2026-07-29 用户「训龟大师没关吗」)。
##   由来: _duel.gd 第20行注释白纸黑字写着「固定条件: …关训龟大师…」, 但代码里【根本没有关它的地方】——
##   _spawn_trainers() 只在 VFXPREVIEW/DEBUG_EDIT 时跳过, 而 _duel.gd 两个都没设。
##   于是【前四轮胜率测试每一场都有两个带钩锁的大师在场】(眩晕4秒 + 受伤+25%)。
##   对称所以不偏向某边, 但绝不中性: 它打断技能、改变站位, 对需要站桩的龟伤害更大 = 结构性偏差。
static var NO_TRAINER := false            # ← 对照实验用: true 则不生成训龟大师
var _edit_mode := false                   # 当前是否在编辑(暂停模拟)态
var _edit_paused_setup: Array = []        # ⏸编辑 重生用的摆位快照 [{id,side,pos,hp,killable}]
var _edit_pick_id := "basic"              # 当前选中要摆的龟 id (◀▶ 循环 STATS keys)
var _edit_pick_side := "left"             # 摆放阵营 left(友军) / right(假人)
var _edit_dummy_hp := 500.0               # 右队假人血量 (−/+ 步进 100)
var _edit_dummy_killable := false         # 右队假人是否会死 (false=不死回满沙包)
var _edit_pick_star := 1                  # 装备星级 1-3 (加装备时用)
var _edit_minion_role := "front"          # 小将笔刷子类: front=近战·浪板 / back=远程·火箭 (用户2026-07-18: 调试场选不到远程火箭→前/后排两个笔刷)
var _edit_full_energy := false            # 满龟能开关: 摆的友军单位开局技能即就绪+快速回充(免死磕攒120龟能才看得到放技)
var _edit_btn_energy: Button = null       # 满龟能开关按钮
var _edit_sel_unit = null                 # 选中的已摆单位(配装/删除)
var _edit_grid_popup: Control = null      # 龟/装备网格弹层
var _edit_equip_box: VBoxContainer = null # 选中单位装备栏容器
var _edit_btn_pick: Button = null
var _edit_btn_side: Button = null
var _edit_star_btns: Array = []
var _edit_speed_btns: Array = []
var _edit_speed_idx := 1                  # 倍速档位(EDIT_SPEEDS索引, 默认1x)
const EDIT_SPEEDS := [0.5, 1.0, 2.0, 4.0]
var _edit_drag_unit = null                # 正在拖拽的单位 (Dictionary 或 null)
var _edit_drag_moved := false             # 本次按下是否真的拖动过 (区分点击放置 vs 拖拽挪位)
var _edit_palette: Control = null         # 编辑面板根 (Control 子控件 mouse_filter=STOP 吃掉自身点击)
var _edit_lbl_hp: Label = null
var _edit_lbl_status: Label = null
var _edit_btn_start: Button = null
# ── 调试场重做(用户2026-07-24: 摆放流程/大师/精英/面板折叠) ──
static var _edit_collapsed := false        # 大设置面板折叠态(静态·跨编辑/开始/再来 重建持久)
var _edit_trainer_active := "hook"         # 摆训龟大师时给它装的主动技(hook/fury_potion/whistle/glacier)
var _edit_brush_bar: PanelContainer = null # 底部常驻笔刷栏(取代模态选龟弹窗)
var _edit_brush_cells: Array = []          # [ [Button, brush_key], … ] 用于高亮当前笔刷
var _edit_body: VBoxContainer = null       # 大面板可折叠的主体(折叠时隐它, 只留标题栏)
var _edit_body_sc: ScrollContainer = null  # 主体外层滚动容器(内容超屏可滚·折叠时隐它·治面板撑出屏外够不到)
var _edit_btn_collapse: Button = null      # 折叠/展开按钮
var _edit_btn_edit: Button = null

# --- Phase 4 juice 全局态 ---
var _hitstop := 0.0                       # 剩余顿帧秒 (>0 时 _process 跳过逻辑推进, 每帧自减 → 精确恢复)
var _follow_vfx: Array = []               # 跟随单位的特效sprite [{spr,unit,h}] — 每帧贴 _world_pos(unit.pos, unit.height+h); sprite被free则自动剔除
var _pending_shots: Array = []            # 依次射出的子弹队列 [{delay, fn:Callable, src}] — 每帧减delay, 到点call(错峰射击: 手铳/加特林/狙击链); src=归属(时停只推进active携带者)
# ═══ 沙漏059 JoJo时停 ═══ 冻结全局_t + 只tick active携带者; 其他单位/弹道/依次射击/tween/粒子 全定格
var _timestop := TimestopSystem.new(self)   # 沙漏时停系统(2026-07-25 从本文件抽出)
var _equip_sys := EquipSystem.new(self)   # 装备效果系统(2026-07-25 抽出·与技能分开)
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")   # 类型羁绊: 阈值/逐档文案/type_of
var _synergy := SynergySystem.new(self)   # ★类型羁绊【战斗侧实装】(2026-08-03 批4-1) —— 在此之前羁绊零效果
var _swordsman := SwordsmanSystem.new(self)   # 剑羁绊【剑士】追打(2026-08-03·取代原设计的"回响")
var _shield_syn := ShieldSynergySystem.new(self)   # 盾羁绊【怒气冲击波/反击/收殓】(2026-08-03)
var _bow_syn := BowSynergySystem.new(self)   # 弓箭羁绊【处决/腐蚀穿透/腐蚀叠层】(2026-08-03)
var _gun_syn := GunSynergySystem.new(self)   # 枪羁绊【三座炮台 + 火控】(2026-08-03)
var _staff_syn := StaffSynergySystem.new(self)   # 法器羁绊【法力条/灵泉/余韵/共鸣】(2026-08-03)
var _potion_syn := PotionSynergySystem.new(self)   # 药水羁绊【猎物/猎获/斩首】(2026-08-03)
var _gadget_syn := GadgetSynergySystem.new(self)   # 奇械羁绊【铸币/冰封/僵硬/易碎】(2026-08-03)
var _food_syn := FoodSynergySystem.new(self)       # 食物羁绊【永久成长/学院】(2026-08-03)
var _spirit_syn := SpiritSynergySystem.new(self)   # 灵物羁绊【触手/闪避追击/亡灵】(2026-08-03)
## ★特殊余额基建(2026-08-05): 独立于 u["shield"] 的第二条余额, 带各自的衰减曲线与破盾回调。
##   由来: 用户重做装备时一口气出现五件都要它(064幽灵/068法力/070灰条/071奶油/072终极),
##   而普通 shield 归零【不通知任何人】。不抽这层就会写出五套互不认识的护盾。
var _spec := SpecialBalance.new(self)
## ★多条血线阈值(2026-08-05): 既有 _eq_check_hp_threshold 是写死一条 50% 线的,
##   而 069 要三道(80/55/30%)、064 要一道(35%)。再往那边塞 hpXX_fired 标记就是灾难。
var _hpl := HpLines.new(self)
var _relic_syn := RelicSynergySystem.new(self)     # 遗物羁绊【生死界/远古之力/龟蛋/觉醒】(2026-08-03)
## 093 香火石的演出层(2026-08-06·批④)。效果本体在 scripts/systems/equip/incense_stone_system.gd,
## 走 EquipSystem 的批④统一路由; 这里只持演出, 与结算完全分开(CLAUDE.md §3.5)。
var _incense_vfx := IncenseVfx.new(self)
## 枪羁绊【金弹】的可辨演出(2026-08-07)。★挂点只有一个: `_queue_shots` 的金弹分支
##   (九把枪的共用出口)。菱形族剪影, 与场上一切圆环/直条弹迹遮住颜色也分得开。
var _gold_vfx := GoldenShotVfx.new(self)
var _tentacle_vfx := TentacleVfx.new(self)         # 灵物【触手拍击】程序化 3D 网格演出(2026-08-04)
## ★"当前正在执行哪件装备的效果" —— 盾羁绊 9 档要判断"这次护盾/治疗是不是盾类装备给的"。
##   护盾/治疗管线本来【不记录来源】, 给每个调用点加参数要碰几十处;
##   而装备效果的分发本来就在几个 `for e in u["equips"]` 循环里, 在那里设一下最省。
##   ⚠ 用完必须清空 —— 留着会让后续非装备来源的护盾被误判成"盾装备给的"。
var _cur_eq_item := ""
var _world_builder := BattleWorldBuilder.new(self)   # 战场世界构建(viewport/tilemap/相机/环境/地面/竞技场/装饰/远景/光柱/气泡/navmesh·开局一次)(2026-07-26 抽出)
var _vfx := BattleVfx.new(self)   # 战斗视觉特效(飘字/命中火花/冲击/挥击juice/技能vfx·纯表现·不改战斗态)(2026-07-26 抽出)
var _review_console := ReviewConsole.new(self)   # 评审台控制台(REVIEW·dev-only: 面板+切龟/切技/切装/星级按钮)(2026-07-25 抽出)
var _info_sys := InfoPanel.new(self)   # 点龟详情面板 + 左右队头像框栏(等级/属性/状态/技能/装备/宝箱)(2026-07-25 抽出)
var _dl_sys := DualLaneFlow.new(self)   # 双路对战流程(呈现总览/放置/逐路推进/破蛋决胜/HUD)(2026-07-25 抽出)
var _debug := BattleDebugArena.new(self)   # 调试场(DEBUG_EDIT: 摆兵/配装/拖拽/满龟能/大师技·dev-only)(2026-07-25 抽出)
var _fortune_sys := FortuneSystem.new(self)   # 财神龟技能系统(2026-07-25 抽出)
var _hunter_sys := HunterSystem.new(self)   # 猎人龟技能系统(2026-07-25 抽出)
var _hiding_sys := HidingSystem.new(self)   # 缩头龟(含随从小将)技能系统(2026-07-25 抽出)
var _elite_sys := EliteSystem.new(self)   # 精英龟技能系统(2026-07-25 抽出)
var _two_head_sys := TwoHeadSystem.new(self)   # 双头龟技能系统(2026-07-25 抽出)
var _candy_sys := CandySystem.new(self)   # 糖果龟技能系统(2026-07-25 抽出)
var _cyber_sys := CyberSystem.new(self)   # 赛博龟技能系统(2026-07-25 抽出)
var _ninja_sys := NinjaSystem.new(self)   # 忍者龟技能系统(2026-07-25 抽出)
var _pirate_sys := PirateSystem.new(self)   # 海盗龟技能系统(2026-07-25 抽出)
var _equip_tick_sys := EquipTickSystem.new(self)   # 装备周期效果tick系统(2026-07-25 抽出)
var _hookbomb_sys := HookBombSystem.new(self)   # 靶向器055 钩索炸弹(2026-08-01 用户整条重做)
var _audio_sys := AudioSystem.new(self)   # 音效系统(2026-07-25 抽出)
var _trainer_sys := TrainerSystem.new(self)   # 训龟大师技能系统(2026-07-25 抽出·与龟技能/装备分开)
var _line_sys := LineSystem.new(self)   # 素描龟技能系统(2026-07-25 抽出)
var _angel_sys := AngelSystem.new(self)   # 天使龟技能系统(2026-07-25 抽出)
var _stone_sys := StoneSystem.new(self)   # 石头龟技能系统(2026-07-25 抽出)
var _shell_sys := ShellSystem.new(self)   # 龟壳龟技能系统(2026-07-25 抽出)
var _ice_sys := IceSystem.new(self)   # 冰龟技能系统(2026-07-25 抽出)
var _dice_sys := DiceSystem.new(self)   # 骰子龟技能系统(2026-07-25 抽出)
var _bamboo_sys := BambooSystem.new(self)   # 竹龟技能系统(2026-07-25 抽出)
var _ghost_sys := GhostSystem.new(self)   # 幽灵龟技能系统(2026-07-25 抽出)
var _crystal_sys := CrystalSystem.new(self)   # 水晶龟技能系统(2026-07-25 抽出)
var _rainbow_sys := RainbowSystem.new(self)   # 彩虹龟技能系统(2026-07-25 抽出)
var _chest_sys := ChestSystem.new(self)   # 宝箱龟技能系统(2026-07-25 抽出)
var _gambler_sys := GamblerSystem.new(self)   # 赌徒龟技能系统(2026-07-25 抽出)
var _lightning_sys := LightningSystem.new(self)   # 闪电龟技能系统(2026-07-25 抽出)
var _rocket_sys := RocketSystem.new(self)   # 小将火箭技能系统(2026-07-25 抽出)
var _bubble_sys := BubbleSystem.new(self)   # 泡泡龟技能系统(2026-07-25 抽出)
var _diamond_sys := DiamondSystem.new(self)   # 钻石龟技能系统(2026-07-25 抽出)
var _world_permanent: Dictionary = {}   # 建场阶段 _world 的常驻子节点(instance_id) —— 换路清场时只清不在此集内的(=特效/单位残留)
var _dmg_stats := DmgStatsPanel.new()   # 战中📊统计浮层(已抽到 scripts/scenes/dmg_stats_panel.gd)
var _sim_tweens: Array = []               # VFX tween注册表(时停暂停非active用; 见 _reg_tween)
var _shake_amp := 0.0                     # 当前震屏幅度 (米); 每帧指数衰减归 0
var _shake_t := 0.0                       # 震屏相位 (驱动伪随机偏移)
var _cam_base := Vector3.ZERO             # 镜头基准位(默认·未缩放); shake 围绕缩放后基准偏移
var _cam_zoom := 1.0                      # 战场缩放(用户2026-07-18): 1=默认·>1拉近放大·<1拉远; PC滚轮/移动双指捏合
const CAM_ZOOM_MIN := 0.72
const CAM_ZOOM_MAX := 2.3
const CAM_TARGET := Vector3(0.0, 0.6, 0.0)   # look_at 目标(缩放=沿视轴向它推拉·方向不变故无需重look_at)
var _cam_zoom_base := Vector3.ZERO        # 缩放后的镜头基准(shake 围绕它·= CAM_TARGET + (_cam_base-CAM_TARGET)/zoom)
var _touch_pts := {}                      # 多点触摸 {index: pos}(移动双指捏合缩放)
var _pinch_prev := -1.0                   # 上帧双指间距(捏合比例基线)
## ── 视角平移(用户 2026-07-21:「手机端触屏拖动来移动摄像机位置, 电脑端就按住推动」) ──
## ★平移量并进 _cam_zoom_base(见 _apply_cam_zoom), 【不能直接写 _cam.position】——
##   _render._update_camera_shake 每帧无条件覆写 position, 直接写会被逐帧抹掉。
var _cam_pan := Vector3.ZERO
var _pan_active := false                  # 正在拖动视角
var _pan_from := Vector2.ZERO             # 按下时的屏幕位置(判定"是拖动还是点选")
var _pan_moved := false                   # 已超过阈值 → 本次抬起不当点选处理
var _touch_seen := false                  # 收到过真触屏事件 → 忽略 emulate_mouse_from_touch 的模拟鼠标平移
const PAN_THRESHOLD := 10.0               # 超过这么多像素才算拖动(以下算点选, 免得点单位变成误拖)
const PAN_LIMIT := 9.0                    # 平移上限(米), 防止把视野拖到看不见战场
var _mech_incoming := {}                  # {side: 到期_t} 赛博机甲组装过渡: 死→机甲spawn空档此侧仍算存活(防提前破蛋·用户2026-07-18)
# ── 卡死猎手(STRESS env·用户2026-07-18「几十把发生一把·你自己找」): 看门狗线程+操作追踪, 主循环冻结时报出最后操作 ──
var _stress := false
var _hb := 0                              # 主循环心跳(每帧+1); 看门狗线程监测, 长时间不变=主线程冻死
var _dbg_op := "-"                        # 最后进入的重操作(冻死时看门狗打出来定位)
var _burst_depth := 0                     # 泡泡/冰霜盾爆裂级联递归深度(死亡链burst→伤害→死→再burst); 超上限截断防卡死(用户2026-07-19卡死猎手抓 bubbleShield)
static var _burst_cap_warned := false     # 深度上限只报一次(避免刷屏)
var _adf_ct := 0                          # 本帧 _damage._apply_damage_from 调用数(每帧重置); 爆炸=死亡链无限级联→截断防卡死
var _dbg_op2 := "-"                        # 更细粒度定位: 最后经手的伤害/死亡单位(冻死时打出)
static var _adf_warned := false
var _wd_thread: Thread = null
static var _stress_n := 0                 # 已跑对局数(跨reload累计)
var _juice_rng := RandomNumberGenerator.new()   # 震屏/粒子专用 rng (演出·永不种子化, 否则回放看着卡)
var _battle_rng := RandomNumberGenerator.new()  # ★sim 专用受控 PRNG (Phase1·大厂做法): 决定战斗结果的随机走它。默认 randomize()=手感与线上一致; TURTLE_SEED 设时确定→可复现/回放
var _cast_tok: int = 0                          # 单调计数·多段技命中去重标记(替 randi() token: 确定性+无碰撞·§3.2 不拿字典做key)
const SIM_DT := 1.0 / 60.0                       # 固定 sim 步长(交互累加器 + 确定性模式共用·≈60fps手感)
var _deterministic := false                      # ★Phase2b: TURTLE_SEED 设时=true → det模式每帧恰1个SIM_DT步(同种子同帧序→可复现回放/验证)
var _sim_accum: float = 0.0                      # ★Phase4切片2: 交互游玩累加器·攒够 SIM_DT 就跑一步 sim(固定步长→帧率无关);余量给切片2b渲染插值
var _render_alpha: float = 0.0                    # ★Phase4切片2b: 渲染插值分数 = _sim_accum/SIM_DT [0,1)。立绘在【上一步 pos↔当前 pos】间 lerp → 消固定步长在高帧率下的卡顿

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
var _last_atk_crit := false               # _atk_dmg 最近一次是否暴击 (供 _damage._apply_damage_from 选暴击音)
var _last_dmg_type := "physical"          # _resolve_dmg 最近一次伤害类型 (physical/magic; 飘字按类型统一取色)
const _VC := preload("res://scripts/systems/visual_constants.gd")   # 飘字配色单一事实源 (1:1 回合制 VisualConstants)

# ============================================================================
#  §SKILLVFX — 技能特效真贴图框架 (替程序圈; 见任务 §2)
#  assets/sprites/skills/<turtle>-<skill>.png = 逐技能特效图 (实测 133 张全是近方形单帧,
#  非 spritesheet) → 框架 = 在 cast/命中点放一个 3D billboard, 一次性"放大→保持→淡出"动画后自销,
#  无需逐帧步进. 有匹配贴图的技能用真 VFX; 没有的保留现有 _skill_ring/飘字 (不强行换).
#  映射 = pets.json skillPool[].icon 的「候选1」(各龟 _trainer_sys._cast_active 实际放的那招), 逐龟人工核对语义.
# ============================================================================
const SKILL_VFX_DIR := "res://assets/sprites/skills/"
const SKILL_VFX_WORLD_H := 2.2            # VFX billboard 目标世界高度 (米) — 单帧图按此归一, 不论原图多大
const SKILL_VFX_GROW_SEC := 0.10          # 放大入场时长
const SKILL_VFX_HOLD_SEC := 0.10          # 满尺寸保持时长
const SKILL_VFX_FADE_SEC := 0.26          # 淡出时长
const SKILL_VFX_START_SCALE := 0.45       # 入场起始相对尺寸 (放大到 1.0)
# 龟 id → 该龟主动技(候选1) 对应贴图名. 来源: pets.json skillPool[0..] icon, 按 _sk_* 语义对到具体那张.
#   注: 程序圈/飘字保留的龟不在此表 (或留空) → _vfx._play_skill_vfx 找不到就静默回退.
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
	_vfxiso = OS.has_environment("VFXISO")
	# 🔬 特效调试台(VFXLAB=1·dev-only·用法见 battle_vfx_lab.gd 文件头)。
	# ★必须在建场之前 —— 它把逐件配置表翻译成 EQDEMO_*/BLACKMAP 等环境变量,
	#   而 _build_environment / _spawn_teams 是【读 env】的, 晚一步就全都读不到。
	if OS.has_environment("VFXLAB"):
		_vfxlab = VfxLabMod.new(self)
		add_child(_vfxlab)
		if not _vfxlab.pre_build():
			# VFXLAB_CASE=list: 只打一份 case 清单就退, 不建场。
			# ★还要 set_process(false) —— quit() 之后本帧还会跑完, 而 _process→_check_end
			#   会看到"左队 0 人存活"去弹胜负横幅, 那时 _ui_layer 根本还没建 → 空指针报错。
			set_process(false)
			return
	_world_builder._build_viewport()
	_world_builder._build_camera()
	_world_builder._build_environment()
	_world_builder._build_ground()
	_snapshot_world_permanent()   # 建场完成→记下常驻节点, 供换路兜底清场
	if OS.has_environment("MAPEDIT"):   # 🖌 地图编辑器模式: 跳过战斗, 只刷tile
		_enter_map_editor()
		if OS.has_environment("SELFSHOT"): _self_screenshot()
		return
	_hud._build_ui_layer()
	# ★PC 板(用户2026-08-01:「pc端要随便拉，支持全屏」): 战斗场景是全项目【唯一不接 size_changed
	#   的场景】—— 主菜单/匹配/选龟都接。不接的后果是拉窗口/切全屏后 HUD 还按进场那一刻的视口摆:
	#   PK 条宽度、右上投降/统计键停在旧位置, 而战场画面已经跟着新视口重画了。
	#   重排逻辑见 battle_hud.on_viewport_resized(PK 条重建 · 右上两键重摆)。
	if not get_viewport().size_changed.is_connected(_hud.on_viewport_resized):
		get_viewport().size_changed.connect(_hud.on_viewport_resized)
	_review_console._build_debug_panel()   # 🛠 调试面板(评审demo·技能/装备/星级·用户2026-07-11)
	if OS.has_environment("STRESS"):   # 卡死猎手: 开局前轮换左队(覆盖全28龟)
		_stress_pre()
	_spawn._spawn_teams()
	if _vfxlab != null:
		_vfxlab.post_spawn()   # 🔬 调试台: 清 UI/铺暗地板/改携带者/摆相机/开拍(单位摆放已由 EQDEMO 那条路走完)
	# 新手引导: ★存成员变量 —— 后面 _hud._show_unit_info_panel 要调 notify() 推进那一步。
	#   match1(第一把): "place"摆位引导延到 _dl_sys._dl_enter_place 才挂(那时才有摆位UI, 文案对得上屏幕);
	#   match2(第二把)/旧路径: 现在就挂"battle"观察引导。
	if GameState.tutorial:
		var _tdg = get_node_or_null("/root/TutorialDirector")
		if _tdg != null and _tdg.is_active():
			if str(_tdg.stage()) != "match1":
				_tutorial = _tdg.attach_guide(self, "battle")
		else:
			_tutorial = TutorialGuide.attach(self, "battle")
	if OS.has_environment("INFO_DEMO"):   # DEV: 自动弹第一只友军的详情面板(截图核对侧边信息面板用·env门控·正常包无)
		var _t2 := get_tree().create_timer(1.6)
		_t2.timeout.connect(func() -> void:
			for _u in _units:
				if _u.get("alive", false) and str(_u.get("side", "")) == "left" and not _u.get("_isEgg", false) and not _u.get("is_summon", false):
					_hud._show_unit_info_panel(_u); break)
	_audit = OS.has_environment("AUDIT")
	if OS.has_environment("STRESS"):   # 卡死猎手: 高速无头循环对局 + 看门狗线程(主循环冻结→打最后操作)
		_stress_start()
	# §AUDIO: 战斗 BGM (淡入, autoload Audio 单例处理循环/音量)
	var _audio := get_node_or_null("/root/Audio")
	if _audio != null:
		_audio.play_bgm("battle")
	# DEV 自截图 (SELFSHOT=<秒>): 等若干帧让战斗跑起来再从主视口存盘
	if OS.has_environment("VFXPREVIEW"):
		_vfx._vfx_preview_start()
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

func _load_tilemap() -> bool:           # 数据驱动: 读 data/maps/arena.json → _tilemap_from_data
	var f := FileAccess.open("res://data/maps/arena.json", FileAccess.READ)
	if f == null: return false
	var data = JSON.parse_string(f.get_as_text()); f.close()
	if data == null or not (data is Dictionary): return false
	var grid = data.get("grid", [])
	if not (grid is Array) or (grid as Array).is_empty(): return false
	_tilemap_from_data(data, grid, data.get("height", []))
	return true

func _tilemap_from_data(meta: Dictionary, grid: Array, height: Array) -> void:   # 从内存数据(重)建tile地面
	for n in _tile_nodes:
		if is_instance_valid(n): n.queue_free()
	_tile_nodes = []
	var tile: float = float(meta.get("tile", 48.0))
	var ox: float = float(meta.get("origin_x", 0.0))
	var oy: float = float(meta.get("origin_y", 0.0))
	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	var tw_m := tile * WS
	var buckets: Dictionary = {}        # type_idx → Array[Transform3D]
	for r in range(mini(h, grid.size())):
		var grow: Array = grid[r]
		var _hrow: Array = height[r] if r < height.size() else []   # 高度数据保留但不应用(去高低差)
		for c in range(mini(w, grow.size())):
			var ti: int = int(grow[c])
			if ti == 4: continue        # void 不渲染
			var hh: float = 0.0         # ★去掉高低差(用户2026-07-15: 石台+0.25/水池-0.30让贴地特效掉到地下→全拍平·类型颜色保留; height数组仍在json里·要恢复改回 float(hrow[c]))
			var px := ox + (float(c) + 0.5) * tile
			var py := oy + (float(r) + 0.5) * tile
			if not buckets.has(ti): buckets[ti] = []
			buckets[ti].append(Transform3D(Basis(), _world_pos(Vector2(px, py), hh - TILE_SINK)))
	for ti in buckets:
		_tilemap_add(buckets[ti], Vector3(maxf(0.02, tw_m - BattleWorldBuilder.TILE_GAP_M), TILE_THICK, maxf(0.02, tw_m - BattleWorldBuilder.TILE_GAP_M)), BattleWorldBuilder.TILE_COLS.get(ti, Color(0.2, 0.2, 0.2)), BattleWorldBuilder.tile_material(ti, WS, _arena_center.x, _arena_center.y))

# ═══ 局内地图刷子编辑器 (MAPEDIT=1 开 · 开发工具不进正式对局 · 纯视觉不改玩法) ═══
## 地砖厚度(米)。★BoxMesh 以 transform 为【几何中心】, 所以砖体占 y∈[-厚/2, +厚/2]。
## 若把 transform 放在 y=0, 上表面就在 +0.075 —— 于是所有 y<0.075 的贴地特效
## (技能环 0.05 / 影子 0.02 / 队色环 0.015 / 泥印 0.03 …共 40+ 处) 全被埋进砖里看不见,
## 这就是用户 2026-07-21 报的「地砖有了高度导致特效被藏到地板下方」。
## 解法: 建砖时统一下沉 TILE_THICK*0.5, 让【上表面落在 y=0】=== 贴地特效的基准面。
## 这样一次修好全部, 不用逐个去抬那 40+ 处的 y 值(逐个抬还会引出穿模)。
var _tile_nodes: Array = []             # 当前tile MultiMesh节点(编辑器重绘时先清)

const TILE_THICK := 0.15
const TILE_SINK := TILE_THICK * 0.5   # 砖心下沉量 → 上表面 y=0

## 障碍物 footprint 外扩余量(像素) = 单位半身宽, 让单位绕行时不会把身子插进礁石。
## ★以前 navmesh 用 +28、放置 clamp 用 +26, 两处口径不一致(没人说得清为什么差 2)。
## 统一到这里。注意它是【叠加在 rx/ry 之上】的, rx 本身必须贴合视觉(见 _world_builder._build_map_props)。
const OBSTACLE_MARGIN := 28.0

## 🖌 地图编辑器已拆到 scripts/scenes/map_editor.gd(2026-07-21)。
## 拆得动的原因: 该簇对伤害管线调用为 0、只读 _cam/_arena_center, 其余状态全是自己的。
## 主场景这边只剩一个实例 + 两个入口(build_ui / paint_at_screen)。
const MapEditorMod := preload("res://scripts/scenes/map_editor.gd")
var _map_editor := false        # ★模式开关(不是编辑器状态) —— 拆分时差点被我连坐删掉
var _map_ed = null              # MapEditor 实例; 不写成 : MapEditor 是因为 class_name 需 --import 注册后才可用

## 🔬 特效调试台(VFXLAB=1·dev-only): 干净黑场 + 可控相机 + 逐件配置 + 定时自截图。
## ★整套逻辑在 scripts/scenes/battle/battle_vfx_lab.gd(不在 _sim_step 调用链上 ⇒ 不进主文件),
##   这里只有【两个钩子】: _ready 建场前 pre_build()、spawn 后 post_spawn()。
## ★它是 Node(不是 RefCounted) —— 相机跟随/压 UI 要每帧做, 让它自己有 _process,
##   这样主文件的 _process 一行都不用加。未开 VFXLAB 时恒为 null, 连实例都不建。
const VfxLabMod := preload("res://scripts/scenes/battle/battle_vfx_lab.gd")
var _vfxlab = null

## 刷格入口: 模块没建好时安全跳过(编辑器未开时 _unhandled_input 也可能走到)
func _map_ed_paint(mpos: Vector2) -> void:
	if _map_ed != null:
		_map_ed.paint_at_screen(mpos)

func _enter_map_editor() -> void:
	_map_editor = true
	set_process(false)          # 编辑器无战斗: 关掉战斗tick(否则碰未建的队伍/UI空节点报错)
	set_physics_process(false)
	var f := FileAccess.open("res://data/maps/arena.json", FileAccess.READ)
	var _meta: Dictionary = {}
	if f != null:
		var data = JSON.parse_string(f.get_as_text()); f.close()
		if data is Dictionary:
			_meta = data
	_map_ed = MapEditorMod.new()
	_map_ed.setup(self, _cam, _arena_center, WS, func(m, g, h): _tilemap_from_data(m, g, h))
	_map_ed.load_data(_meta, _meta.get("grid", []), _meta.get("height", []))
	_map_ed.build_ui()

func _tilemap_add(xforms: Array, box_size: Vector3, col: Color, mat: Material = null) -> void:
	if xforms.is_empty(): return
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new(); box.size = box_size
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	else:
		var sm := StandardMaterial3D.new(); sm.albedo_color = col
		mmi.material_override = sm
	_world.add_child(mmi)
	_tile_nodes.append(mmi)

const MAP_V2 := true   # ★新tile地图转常开(用户2026-07-14"调给我看看"): true=正式对局默认用新暗深海夜色tile地图; false回退旧地面; env(TILEMAP/MAPEDIT)仍可强制
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


## (投降确认浮层的【构建】已搬到 scripts/scenes/battle/battle_hud.gd::_build_surrender_panel ——
##  它只建 Control/ColorRect/Label/Button, 是纯 UI, 本来就该在 HUD 侧;
##  而且主文件有 arch_budget 行数棘轮(欠债只减不增), 往这里加代码=违规。
##  开/收/确认那三个【行为】函数留在本文件, 因为它们要动 _settled/_over/_dl_sys。)

## 清掉拖动/捏合的脏态。
##
## ★这段原来长在 _toggle_pause 里, 是【搬过来的不是新写的】——
##   verify_cam_pan 有一条 _test_pause_clears_drag_state 专门守着它, 所以它有实测价值:
##   若"打断"发生在拖动【中途】, release 事件永远收不到, _pan_active 会带着 true 活到之后,
##   表现为【手指松开了镜头还在跑】。
##
## 原来的"打断"是暂停; 暂停移除后, 新的打断源是**投降确认框的暗幕**(MOUSE_FILTER_STOP
## 会吃掉 release), 完全同形。所以这段逻辑没有随暂停一起消失, 只是换了调用者。
func _clear_input_dirty() -> void:
	_pan_active = false
	_pan_moved = false
	_touch_pts.clear()
	_pinch_prev = -1.0


## 弹出投降确认框。结算后不响应(已经分出胜负了, 没什么可投降的)。
func _show_surrender_confirm() -> void:
	if _settled:
		return
	_clear_input_dirty()      # ★见该函数注释: 暗幕会吃掉 release, 不清就会"松手后镜头还在跑"
	if _surrender_panel != null and is_instance_valid(_surrender_panel):
		_surrender_panel.visible = true


## 收起投降确认框(点"取消"或战斗已结算)。★不做任何结算 —— 取消就是什么都不发生。
func _hide_surrender_confirm() -> void:
	_clear_input_dirty()
	if _surrender_panel != null and is_instance_valid(_surrender_panel):
		_surrender_panel.visible = false


## 确认认输 → 判【整场】负并进结算屏。
##
## ★用户 2026-07-30 拍板"整场负，直接进结算屏"(不是只判本路负, 也不是直接回主菜单):
##   · 只判本路负 = 可以刷掉不利的那一路保留阵容 → 新的策略后门
##   · 直接回主菜单 = 拿不到本场奖励/记录, 也看不到自己输在哪
##
## ★不能只调 _settle_season(false) —— 它只做赛季记账(命/币/胜场/XP/ghost上传), 不显结算屏。
##   正常判负是【三件套】: _over=true → _settle_season(won) → _hud._show_banner(won)
##   (单路见 _check_over: 7353-7357; 双路见 dual_lane_flow._dl_finish: 726-733)。
##   双路还要额外置 _dl_state="done", 所以双路直接走 _dl_finish(false) 复用它, 别自己拼。
func _do_surrender() -> void:
	if _settled or _over:
		return
	_hide_surrender_confirm()
	_log("[color=#ff6b6b]🏳 投降认输 —— 本场判负[/color]")
	if _is_dual_lane_mode():
		_dl_sys._dl_finish(false)      # 双路: 内部会置 _over/_dl_state/喂赛季/显横幅
	else:
		_over = true
		_settle_season(false)
		_hud._show_banner(false)


## 战斗日志浮层: 左下角可滚动富文本. 默认隐; process_mode ALWAYS.
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
			var _pc0 := _log_rt.get_paragraph_count()
			_log_rt.remove_paragraph(0)
			if _log_rt.get_paragraph_count() >= _pc0:   # ★remove_paragraph 偶发不生效(Godot RichTextLabel)→count不降=死循环→break(用户2026-07-18"打斗途中突然死机": 战斗日志刷屏时触发)
				break


func _unit_name(u: Dictionary) -> String:
	return str(u.get("name", u.get("id", "?")))

func _log_side_hex(u: Dictionary) -> String:
	return "#7fe39a" if u.get("side", "") == "left" else "#ff9a9a"

func _skill_disp(stype: String) -> String:
	return str((_skill_meta.get(stype, {}) as Dictionary).get("name", stype))

func _review_turtle() -> String:   # 受审龟: 调试面板 > env REVIEW_TURTLE > const
	if _dbg_turtle != "": return _dbg_turtle
	return OS.get_environment("REVIEW_TURTLE") if OS.has_environment("REVIEW_TURTLE") else REVIEW_TURTLE
func _review_skill_idx() -> int:   # 受审技idx: 调试面板 > env REVIEW_SKILL > const (-1=默认轮转)
	if _dbg_skill != -99: return _dbg_skill
	return int(OS.get_environment("REVIEW_SKILL")) if OS.has_environment("REVIEW_SKILL") else REVIEW_SKILL_IDX
func _resolve_left() -> Array:
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():   # ★新手教学: 固定阵容(用户拍板"固定阵容+弱对手必赢")
		return _td.FIXED_TEAM.duplicate()
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
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():   # ★新手教学: 弱对手(必赢, 让新手两把都稳过)
		return _td.WEAK_FOE.duplicate()
	if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示: 默认2个固定假人(相距500码); EQDEMO_ENEMIES=N 改个数
		# ★个数可调是 VFXLAB 调试台加的: 078 电击连锁要 3 个才看得出跳跃, 089 符纸只要 1 个(多了抢镜)。
		#   缺省仍是 2 ⇒ 老的 EQDEMO 命令行行为一字不变。
		var _en: int = maxi(1, int(OS.get_environment("EQDEMO_ENEMIES"))) if OS.has_environment("EQDEMO_ENEMIES") else 2
		var _el: Array = []
		for _i in range(_en):
			_el.append("basic")
		return _el
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
	var ghost_leaders := _ghost_sys._ghost_leaders()
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

const FAR_TERRAIN_SIZE := Vector2(200.0, 120.0)   # x, z 覆盖范围(米)
const FAR_TERRAIN_CENTER_Z := -30.0               # z 中心 → 覆盖 z∈[-90,+30], 罩住最坏机位的 z=-42.2
const FAR_TERRAIN_SEG := Vector2i(80, 48)         # 网格分段 → 3969 顶点, 对 GPU 是零负担
const FAR_TERRAIN_FLAT_R := 26.0                  # 这个半径内恒平(护住战场里的贴地特效)
const FAR_TERRAIN_RISE_R := 46.0                  # 到这个半径起伏达到满幅


## 到战场中心的水平距离 → 起伏权重 (0=近处恒平, 1=远处满幅)
func _far_terrain_weight(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	return smoothstep(FAR_TERRAIN_FLAT_R, FAR_TERRAIN_RISE_R, d)


## 地形高度场: 三层不同频率的正弦叠加(比纯随机更像地貌) × 距离权重
func _far_terrain_height(x: float, z: float) -> float:
	var w := _far_terrain_weight(x, z)
	if w <= 0.0:
		return 0.0
	var h := 0.0
	h += 1.55 * sin(x * 0.055 + 1.3) * cos(z * 0.048 - 0.7)
	h += 0.70 * sin(x * 0.130 - 2.1) * cos(z * 0.115 + 1.9)
	h += 0.28 * sin(x * 0.290 + 0.4) * cos(z * 0.265 - 2.6)
	return h * w


## 小鱼剪影贴图 (远景只需要轮廓: 椭圆身 + 三角尾).
func _make_fish_texture() -> ImageTexture:
	var w := 22
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# ★头在右、尾在左 = 贴图朝右(与下方 scale.x 逻辑的"默认朝右"一致)。
	#   2026-07-23 用户报「背景的鱼方向反了」: 原来头在左(cx=8)、尾在右(x>=14),
	#   实际是【朝左】的, 而 scale.x 按"默认朝右"翻 → 两个游动方向都变成倒着游。
	var cx := float(w) - 8.0                                     # 身体中心靠右
	var cy := float(h) * 0.5
	var tail_x := 8                                             # 尾根: 靠左
	for x in range(w):
		for y in range(h):
			var inside := false
			var dx := (float(x) - cx) / 7.5
			var dy := (float(y) - cy) / 3.4
			if dx * dx + dy * dy <= 1.0:
				inside = true                                   # 身体
			elif x <= tail_x:
				var span := float(tail_x - x) / 7.0 * 4.6       # 尾: 越往前(左)张得越开
				if absf(float(y) - cy) <= span:
					inside = true
			if inside:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


## 远景鱼群: 若干小群横向漂过, 到边界回卷.
##   ★用【裸 create_tween】驱动, 不进 _sim_tweens ——
##     ①_dl_clear_units() 换路时会把 _sim_tweens 全 kill, 背景鱼会集体停住
##     ②战斗定格(hitstop)不该冻住环境, 环境停了反而穿帮
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

func _tutorial_anchor(anchor: String) -> Rect2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	match anchor:
		"go_button":   # 「开打」钮
			if _dl_go_btn != null and is_instance_valid(_dl_go_btn) and _dl_go_btn.visible:
				return _dl_go_btn.get_global_rect()
		"field":       # 我方半场(左侧) —— 3D 战场无精确 UI 矩形, 用左中区域近似示意
			return Rect2(vp.x * 0.05, vp.y * 0.30, vp.x * 0.45, vp.y * 0.42)
	return Rect2()

# ══════════════════════════════════════════════════════════════
# §SUDDEN 战场决胜机制 (用户2026-07-19「存活40秒后, 治疗效果降低50%, 并每5秒获得25%增伤持续到战场结束」)
#
# 起因: 巡检 243 局发现【双方都带装备时 10.3% 的对局永远打不完】—— 结束条件只有"一方团灭"和"蛋被打碎",
# 没有任何时间兜底; 双方续航一旦盖过对方输出就是死局(实测忍者龟5秒回300血、寒冰龟护盾还在涨)。
#
# ★计时按【战场】各自算, 不能用 _t: _t 在上路→下路→终极之间是累加不重置的(实测上路53s结束、下路接着跑到120s),
#   直接用 _t>=40 会让下路一开场就已经过线。所以 _dl_sys._dl_start_fight 每次开打都重置 _sd_t0。
# ★增伤要在两条伤害路径都乘: _damage._apply_damage 和 _damage._apply_damage_from 是各自独立扣血的, 只改一处会漏掉一半伤害。
# ══════════════════════════════════════════════════════════════
const SD_START := 40.0        # 本战场开打满 40 秒 → 进入决胜
const SD_STEP := 5.0          # 之后每 5 秒一档
const SD_AMP_PER := 0.25      # 每档 +25% 增伤(累计, 持续到本战场结束)
const SD_HEAL_MULT := 0.5     # 决胜期治疗效果 ×50%
var _sd_t0 := 0.0             # 本战场开打时刻
var _sd_stacks := 0           # 已获得的增伤档数(0=未进入决胜)
## 跨路保留的装备层数(竹弓039/哑铃020/温泉蛋036·用户2026-08-01)。键/存取见 dual_lane_flow.EQ_CARRY。
## ★挂在场景实例上 = "只有开新对局才重置" 天然成立(新对局=新场景=新空表), 不要另写清空。
var _eq_carry: Dictionary = {}
var _dbg_salvo_picks: Array = []   # 赛博死亡齐射每门炮实际锁到的目标类别(仅门禁读; 见 cyber_system)

func _sd_amp() -> float:
	return SD_AMP_PER * float(_sd_stacks)

func _sd_heal_mult() -> float:
	return SD_HEAL_MULT if _sd_stacks > 0 else 1.0

func _sd_tick() -> void:
	if _over:
		return
	var el: float = _t - _sd_t0
	if el < SD_START:
		return
	var want: int = 1 + int((el - SD_START) / SD_STEP)   # 40s→1档(+25%), 45s→2档, 50s→3档...
	if want <= _sd_stacks:
		return
	_sd_stacks = want
	if _sd_stacks == 1:
		_announce_sudden()

## 决胜开始: 全场飘字 + 提示(只在第1档播一次, 后续档位靠 HUD 显示数值)
func _announce_sudden() -> void:
	for u in _units:
		if u.get("alive", false) and not u.get("_isEgg", false):
			_vfx._float_text(u["pos"] + Vector2(0, -90), "决胜!", Color("#ff6b6b"))
	_log("⚔ 决胜阶段: 治疗效果 -50%, 每 5 秒全场 +25% 增伤")

func _foe_normalize_lane(raw: Array) -> Array:   # 对手每路规整到"恰好3单位"(用户2026-07-18"每条路都是3个单位·跟玩家一样"): 保留全部统领(≤3), 小将补/裁到 3-统领数(=玩家逻辑). 3统领→0小将 / 空统领→3小将 皆合规
	var leaders: Array = []
	var minions: Array = []
	for s in raw:
		if s is Dictionary and str((s as Dictionary).get("kind", "")) == "leader": leaders.append(s)
		elif s is Dictionary and str((s as Dictionary).get("kind", "")) == "minion": minions.append(s)
	var want: int = clampi(3 - leaders.size(), 0, 3)
	var out: Array = leaders.duplicate()          # 统领全留(含各自equips)
	var added: int = 0
	for m in minions:                             # 优先沿用快照自带小将(role/elite), 多余裁掉
		if added >= want: break
		out.append(m); added += 1
	while added < want:                           # 不足补默认小将(首前排·余后排)
		out.append({"kind": "minion", "role": "front" if added == 0 else "back"}); added += 1
	return out

# 对手当前路阵容: 匹配抽到的 ghost 快照(lane_assign 该路 leaders + 各自 equipped) → 否则 bot. 每路统一经 _foe_normalize_lane 规整到3单位(与玩家同规则).
#   ★对手装备按档位生效: 从 dual_ghost.equipped[pet] 取, 挂到 spec["equips"] → _spawn._spawn_lane_side 转 _dl_equips → _inject_equipment 应用.
func _dual_foe_lane(lane: String) -> Array:
	if GameState != null and GameState.dual_ghost is Dictionary:
		var dg: Dictionary = GameState.dual_ghost
		GameState.foe_loadouts = dg.get("loadouts", {}) if dg.get("loadouts") is Dictionary else {}   # ghost技能选择→敌侧生效(用户2026-07-15)
		# 兼容老结构: dg[lane] 直接是单位规格数组
		if dg.has(lane) and dg[lane] is Array and not (dg[lane] as Array).is_empty():
			return _foe_normalize_lane(dg[lane])
		# ghost/bot 快照: lane_assign[lane]=该路统领; minions[lane]=该路小将配置(role/elite·快照可带·用户2026-07-16分路多变+精英小将); equipped[pet]=装备
		var la = dg.get("lane_assign", {})
		if la is Dictionary and (la as Dictionary).get(lane) is Array:
			var lane_leaders: Array = (la as Dictionary)[lane]
			var gmin = dg.get("minions", {})
			var lane_minions: Array = (gmin as Dictionary).get(lane, []) if gmin is Dictionary else []
			if not lane_leaders.is_empty() or not lane_minions.is_empty():
				var geq: Dictionary = dg.get("equipped", {}) if dg.get("equipped") is Dictionary else {}
				var specs: Array = []
				for pid in lane_leaders:
					var spec: Dictionary = {"kind": "leader", "id": str(pid)}
					if geq.has(str(pid)) and geq[str(pid)] is Array:
						spec["equips"] = (geq[str(pid)] as Array).duplicate(true)   # 对手按档装备
					specs.append(spec)
				for m in lane_minions:                          # 快照自带小将配置(role+elite+装备)·多余normalize裁·不足补
					if m is Dictionary:
						var mspec: Dictionary = {"kind": "minion", "role": str((m as Dictionary).get("role", "front")), "elite": bool((m as Dictionary).get("elite", false))}
						var meq = (m as Dictionary).get("equips", null)   # 对手小将装备(用户2026-07-18)→_spawn_lane_side转_dl_equips注入
						if meq is Array and not (meq as Array).is_empty():
							mspec["equips"] = (meq as Array).duplicate(true)
						specs.append(mspec)
				return _foe_normalize_lane(specs)               # ★每路规整到3单位=minions(3-统领)·与玩家同(用户2026-07-18)
	# 兜底 bot(无快照/冷启动): 每路3单位·上路2统领+1小将 / 下路1统领+2小将(normalize补齐·与玩家默认同·用户2026-07-18)
	var pool := ["stone", "ninja", "ghost", "ice", "diamond", "fortune", "bamboo", "angel"]
	var specs: Array = []
	if lane == "top":
		specs = [{"kind": "leader", "id": pool[0]}, {"kind": "leader", "id": pool[1]}]
	else:
		specs = [{"kind": "leader", "id": pool[3]}]
	# STRESS 下给兜底 bot 也发装备: 原来只有 _stress_pre 给左队发(3龟×3件), 右队全裸 →
	# 压测里【双方都带装备】这条路从没跑到过, 而装备互相作用正是之前那些字典深比较地雷的藏身处;
	# 顺带修掉"1秒团灭对面"导致的一堆无效短局(用户2026-07-19 巡检发现)。
	if _stress:
		var eqids: Array = []
		for e in DataRegistry.phase2_equipment:
			if int((e as Dictionary).get("shopAvailable", 0)) == 1:
				eqids.append(str((e as Dictionary)["id"]))
		if not eqids.is_empty():
			for si in range(specs.size()):
				var el: Array = []
				for j in range(3):
					el.append({"id": str(eqids[(_stress_n * 7 + si * 5 + j + 3) % eqids.size()]), "star": 1 + (_stress_n + si + j) % 3})
				(specs[si] as Dictionary)["equips"] = el
	return _foe_normalize_lane(specs)

# ── 双路流程控制 (P4: 团灭→破蛋10s窗口→结束; P5 升级为 top→bottom→final 分路推进) ──
# 团灭判定排除的【惰性】召唤(否则续着卡死破蛋窗口); 战斗型召唤(大熊/海螺虫/骷髅/小将/机甲/浮游炮)算存活→用户2026-07-11「还在打召唤物别突然弹下一战场」
const _DL_INERT_SUMMON := {"candybomb": true, "crystalball": true}
func _snapshot_world_permanent() -> void:   # 记录建场阶段的 _world 子节点(相机/灯光/地砖/竞技场环等)
	_world_permanent.clear()
	if not is_instance_valid(_world): return
	for c in _world.get_children():
		_world_permanent[c.get_instance_id()] = true

func _sweep_world_vfx() -> String:   # 换路兜底: 清掉所有非常驻的 _world 子节点(遗留特效)
	if not is_instance_valid(_world): return ""
	var freed := 0
	for c in _world.get_children():
		if _world_permanent.has(c.get_instance_id()): continue
		c.queue_free(); freed += 1
	return str(freed)

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

# 等级乘数: 该单位/召唤体所属侧的等级 → 主属性 +5%/级 (与 _spawn._make_unit spawn 缩放同公式).
#   装备 flat 加值 + 固定值召唤体(随从/海螺虫/大熊) 用它"吃等级"; owner 派生召唤体已间接吃, 不用.
func _lvl_mult_for(u: Dictionary) -> float:
	var lvl: int = maxi(1, _unit_level(str(u.get("side", "left"))))
	return UnitScaling.level_multiplier(lvl)

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

## 下一个多段技命中去重 token (单调·确定性·替原 randi())
func _next_cast_tok() -> int:
	_cast_tok += 1
	return _cast_tok

## Phase4切片2b: 每个 sim 步【之前】存 pos/height → 渲染时在 prev↔当前 间按 _render_alpha 插值(消固定步长卡顿)。
func _snapshot_render_prev() -> void:
	for u in _units:
		u["_prev_pos"] = u["pos"]
		u["_prev_height"] = u.get("height", 0.0)

## 按【战斗时钟 _t】等待 secs 秒(Phase2·§3.5): 替 create_timer(走未钳制真实时间·CI/慢机偏)。
## _t 走钳制后 delta → 效果跟随 sim 时间·暂停时正确停;帧上限防 _t 冻结(_kill 后)时死循环。
## 正常 60fps 下 _t≈真实时间 → 手感不变;慢机/CI 下按 sim 时间(这才对)。
func _wait_sim(secs: float) -> void:
	var t_end: float = _t + secs
	var guard: int = 0
	while _t < t_end and guard < 6000 and is_instance_valid(self):
		await get_tree().process_frame
		guard += 1

func _my_trainer():
	for u in _units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left" and u.get("alive", false):
			return u
	return null


## 按方向量移动。抽出来是为了【可测】—— 无头跑不了真键盘/真手指, 但能直接喂向量。
## dir 长度 0..1(摇杆可以是半推), 所以速度是 130 × 拉杆比例。
func _can_place_drag(hit) -> bool:
	return hit != null and str(hit.get("side", "")) == "left" \
		and not hit.get("_isEgg", false) and not hit.get("is_summon", false) \
		and not hit.get("is_trainer", false)

## 训龟大师的移动/攻击 tick 现在该不该跑: 战斗结束/摆位/呈现/编辑期都不跑(用户2026-07-23 点6)。
## ★摆位期投掷石头/被键盘摇杆推动都是 bug —— 移动/攻击是玩法动作, 非战斗期该停。抽成纯函数便于门禁测。
func _cast_fury_potion(trainer: Dictionary, aim: Vector2) -> bool:
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	trainer["_active_cd"] = float(TRAINER_SKILLS["fury_potion"]["cd"])
	var pt: Vector2 = trainer["pos"] + aim.limit_length(700.0)          # 落点(射程700内)
	trainer["_cast_lock_until"] = _t + HOOK_WINDUP                      # 丢药水时短暂站定
	var tt: Dictionary = trainer
	var throw_t: float = HOOK_WINDUP + trainer["pos"].distance_to(pt) / 800.0   # 前摇 + 抛出飞行
	_pending_shots.append({"delay": throw_t, "src": trainer, "fn": func() -> void:
		_trainer_sys._fury_apply_buffs(tt, pt)})                                    # 落地才生效(delta定时·无头也稳)
	_trainer_sys._fury_dramatize(trainer, pt)
	return true

## ★纯效果结算(可测): 落点 300码内【友军】获得 5秒 三 buff。返回受益人数。不建 tween。
func _cast_whistle(trainer: Dictionary, _aim: Vector2) -> bool:
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	trainer["_active_cd"] = float(TRAINER_SKILLS["whistle"]["cd"])
	_trainer_sys._whistle_note(trainer)          # R5 口哨音符前摇(头顶♪冒出上浮)
	match _battle_rng.randi() % 3:
		0: _trainer_sys._whistle_temphp(trainer)
		1: _trainer_sys._whistle_spirit_wave(trainer)
		_: _trainer_sys._whistle_berserk(trainer)
	return true

## 随机一个我方存活单位(非大师非蛋)。
func _random_ally(trainer: Dictionary):
	var side: String = str(trainer.get("side", ""))
	var pool: Array = []
	for o in _units:
		if o.get("alive", false) and not o.get("is_trainer", false) and not o.get("_isEgg", false) and str(o.get("side", "")) == side:
			pool.append(o)
	return pool[_battle_rng.randi() % pool.size()] if not pool.is_empty() else null

## (_apply_temp_maxhp 已搬到 trainer_system —— 它是口哨①的纯效果, 不属于战斗主循环。
##  搬家动机: arch_budget 把本文件冻结在 8600 行, 口哨②加了一行 _tick_wave_flights 调用 → 8601 红;
##  规矩是"往上帝文件加代码=违规, 先拆出去", 所以搬走一个本来就不属于它的函数, 而不是把台账调高。
##  顺带删掉了一句【已过时的旧注释】: 它写着"气波…击飞 + 200物理 + 削甲30%", 而 2026-07-30
##  已改成 100+15%最大生命真实伤害, 且改成命中才结算 —— 而且它挂在 _cast_glacier 头上, 本来就串位了。)
func _cast_glacier(trainer: Dictionary, aim: Vector2) -> bool:
	if float(trainer.get("_active_cd", 0.0)) > 0.0:
		return false
	trainer["_active_cd"] = float(TRAINER_SKILLS["glacier"]["cd"])
	var dir: Vector2 = aim.normalized() if aim.length() > 0.01 else Vector2.RIGHT
	trainer["_cast_lock_until"] = _t + HOOK_WINDUP
	_glacier_zones.append({
		"from": trainer["pos"], "dir": dir, "len": GLACIER_LEN, "width": GLACIER_WIDTH,
		"until": _t + GLACIER_SEC, "side": str(trainer.get("side", "")),
	})
	_trainer_sys._glacier_dramatize(trainer["pos"], dir)
	return true


## 命中演出(2026-07-24 返工·照锤石Q): 前摇蓄力(HOOK_WINDUP·大师站定举钩) → 中速飞行(HOOK_MISSILE_SPD) → 到达。
## 结算不依赖它跑完(_trainer_sys._hook_grab 由 _pending_shots 定时调, 无头也稳)。
func _valid_active(sid) -> String:
	var s := str(sid)
	return s if TRAINER_SKILLS.has(s) else "hook"


## 法术圆盘(点3): 右下角钩锁钮。PC 端主要靠按 Q(朝鼠标), 圆盘作冷却指示; 移动端点它施法(自动瞄最近敌)。
func _make_trainer_placeholder_tex() -> ImageTexture:
	# ★尺寸/比例: 游戏按【帧高】把立绘归一到 TARGET_BODY_H(2米), 所以本体必须【填满整帧】,
	#   否则会被压成细条。初版 24×48 而身子只占中间 14px 宽 → 屏幕上只有 15×44 的一根竖条
	#   (2026-07-22 截图才看出来; 精英小将也踩过同一个坑: "归一按帧高算但本体只占半帧")。
	var w := 34
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var magenta := Color(1.0, 0.0, 0.85, 1.0)
	var black := Color(0.05, 0.05, 0.08, 1.0)
	for y in h:
		for x in w:
			# 粗人形: 上 1/4 是头(窄), 其余是身子(宽)
			# 头(占上 1/4)+ 身子(占满宽) —— 让有效内容铺满整帧
			var inside: bool = (x >= 11 and x < 23 and y < 11) or (x >= 2 and x < 32 and y >= 11)
			if not inside:
				continue
			# 4px 棋盘 → 一眼看出是占位, 不会被误当成正式美术
			img.set_pixel(x, y, magenta if ((x / 4 + y / 4) % 2 == 0) else black)
	return ImageTexture.create_from_image(img)


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
	# ★空 id 单独说清楚 —— 它不是"这只龟的图丢了", 而是【统领槽位没配】:
	#   season_leaders 为空 → GameState.default_dual_lineup() 用空串填 id(GameState.gd:640-648)
	#   → _spawn_lane_side 照样为空 id 建单位 → 空框 + 无名统计行 + 本条 warning。
	#   ★正常玩家碰不到: TeamSelect 的出战按钮在选满 3 只前是 disabled 的
	#     (TeamSelectScene.gd:646「请选择 3 只龟」)。直接加载 RealtimeBattle3D.tscn
	#     (截图/测试路径)才会走到这。
	#   ★故意【不做静默跳过】—— 同 TRAINER_SPRITE 那条规矩: 悄悄兜底会让人以为数据是好的。
	#     真有存档数据出问题时, "空框 + 这条 warning" 比"少两只龟"好排查得多。
	if id == "":
		push_warning("RealtimeBattle3D: ★统领槽位为空(season_leaders 没配够) —— 该位置会出现无名无立绘的空单位。正常流程不会发生(TeamSelect 强制选满 3 只); 直接加载战斗场景时属预期。")
	else:
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
	# 077 铜管手铳的小手枪(2026-08-07): 全表第一个【有真立绘】的装备召唤物。
	# ★为什么单独一支而不是走下面的 `pets/<spr_id>.png` 通用路: 它不是宠物, 没有 pets.json 元数据,
	#   走通用路会被当成静态单图 ⇒ 16 帧的表会显示成"一排小枪"(2026-07-17 竹叶龟踩过同一个坑)。
	# ★帧表是【乒乓】排的(0..8 再 7..1 = 16 帧): PixelLab 出的 idle 末帧与首帧差 323/1600 像素,
	#   直接首尾相接会每轮跳一下; 乒乓让循环天然闭合, 且"悬浮上下"这个动作本来就该来回。
	# ★装备召唤物的本体立绘(「白球家族」)。没有这几条就会掉进最下面的**兜底队色发光球** ——
	#   干净台花名册会打 `spr=✗`, 玩家看到的是"场上多了个不明白点"。
	#   一律 16 帧乒乓排帧(0..8 再 7..1), 见 tests/verify_eq_body_sprites.gd 的 ②。
	const _EQ_BODY_SPR := {
		"pistol": ["vfx/eq-pistol-idle.png", 40],       # 077 铜管手铳
		"coraltower": ["vfx/eq-coraltower-idle.png", 64],  # 079 珊瑚急救塔
	}
	if _EQ_BODY_SPR.has(spr_id):
		var _row: Array = _EQ_BODY_SPR[spr_id]
		var pp: String = SPRITE_DIR + str(_row[0])
		var _fw: int = int(_row[1])
		if ResourceLoader.exists(pp):
			var pt: Texture2D = load(pp)
			if pt != null:
				return _sprite_dict_from(pt, {"frames": 16, "frameW": _fw, "frameH": _fw, "duration": 1280}, true)
	# treasure_golem idle 动画 (宝箱怪有专属帧, frameW/H=74/73, 7帧)
	if spr_id == "treasure-golem" or spr_id == "treasure_golem":
		var anim := SPRITE_DIR + "pets/animations/treasure_golem/idle.png"
		if ResourceLoader.exists(anim):
			var t: Texture2D = load(anim)
			if t != null:
				return _sprite_dict_from(t, {"frames": 8, "frameW": 74, "frameH": 73, "duration": 800}, true)
	# 海盗船(技3实体·封板): 用 skills/pirate-ship.png(与后方演出船同图·转变连贯)
	if spr_id == "pirate-ship":
		var sp := SPRITE_DIR + "skills/pirate-ship.png"
		if not ResourceLoader.exists(sp): sp = SPRITE_DIR + "battle/pirate-ship.png"
		if ResourceLoader.exists(sp):
			var st: Texture2D = load(sp)
			if st != null:
				return _sprite_dict_from(st, null, false)
	# 通用: pets/<spr_id>.png — ★2026-07-17修(用户"召唤的竹叶龟直接是序列图"): pets图多已repack成帧sheet,
	#   有sprite帧元数据(pets.json)→按帧动画切(hframes/idle循环); 无元数据(真·静态单图)→整图显示。修前一律当静态→sheet宠物显示成一排小龟
	var full := SPRITE_DIR + "pets/" + spr_id + ".png"
	if ResourceLoader.exists(full):
		var tex: Texture2D = load(full)
		if tex != null:
			var meta = (_data_by_id.get(spr_id, {}) as Dictionary).get("sprite", null)
			if meta is Dictionary and int((meta as Dictionary).get("frames", 0)) > 1:
				return _sprite_dict_from(tex, meta, true)
			return _sprite_dict_from(tex, null, false)
	return {"tex": null}

func _set_anim_sheet(u: Dictionary, sd: Dictionary, action: String, is_idle: bool) -> void:
	var spr = u.get("sprite", null)
	var mat = u.get("grounded_mat", null)
	if not is_instance_valid(spr) or sd.is_empty() or sd.get("tex", null) == null:
		return
	var tex: Texture2D = sd["tex"]
	# ★★2026-08-07 真根因(前面钳了六处都没治住, 因为**根本不在"谁设了大帧号"**):
	#   Godot 在 `hframes` / `vframes` 的 setter 里会**立即用新乘积校验当前 frame**。
	#   顺序是 hframes → vframes → frame=0 ⇒ **设 vframes 的那一瞬**, frame 还停在旧表的值。
	#   从训龟大师的 4 行表(hframes 7 × vframes 4 = 28, frame 可达 27)切到普通单行表时,
	#   `vframes = 1` 让乘积掉到 7, 而 frame 还是 17 ⇒ 报
	#   `Index p_frame = 17 is out of bounds (vframes*hframes = 7)`。
	#   ⇒ **换表前先把 frame 归零**。这也解释了它为什么是随机的: 只有场上有大师、
	#     且它恰好在高帧号时切表才会撞上。
	spr.frame = 0
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
## 动画查表键 —— 不是 u["id"]。
## ★三种小将(前排近战/后排远程/精英)【共用 id "__minion__"】, 直接拿 id 查 ACTION_* 表,
##   会让普通小将也套用精英的动作帧(它们造型完全不同)。所以精英单独给一个键。
## 加新的"同 id 不同外观"单位时, 在这里分流即可, 不用改各处调用点。
func _anim_key(u: Dictionary) -> String:
	var id := str(u.get("id", ""))
	if id == "__minion__":
		# ★三种小将共用 id, 造型完全不同(精英=紫黑持刃 / 前排=绿色三叉戟 / 后排=远程)。
		#   2026-07-22 加前排后必须一并分流 —— 只分精英的话, 前排的三叉戟帧会套到后排远程身上。
		if u.get("is_elite", false):
			return "__minion_elite__"
		return "__minion_front__" if str(u.get("minion_role", "front")) == "front" else "__minion_back__"
	return id


## 精英小将专属动作: 直接换帧表, 不经 _vfx._play_action (它只认 attack/hurt/death).
##   action 写进 u["anim_action"] → 被 _vfx._play_action 顶部白名单挡住, 播完前不被普攻/受击换掉;
##   _render._advance_anim 走到末帧自动回 idle。
##   ★只对精英小将生效 —— 普通小将共用 "__minion__" id, 不加这道判断会给前后排也套上精英动作。
const ELITE_ACT_BODY_H := 47.0    # 动作帧里角色本体高(px)
const ELITE_ACT_FEET_ROW := 71.0  # 动作帧里脚底所在行

# ★归一表(2026-07-22 泛化): 动画键 → [动作图本体高, 动作图脚底行, idle 图本体高]
#   PixelLab 出的图四周留白很多, 本体只占帧高的一半左右; 而 _set_anim_sheet 的通用归一
#   默认"本体填满整帧" → 不修正的话一播动作角色就缩到 ~56% 并悬空(精英那次用户一眼看出)。
#   ★每套图的数值都不同, 必须实测各自的 bbox, 不能沿用别人的:
#     精英   帧高96 本体47 脚底71 / idle 帧高80 本体71
#     近战   帧高88 本体45 脚底65 / idle 帧高80 本体60
#   加新单位时在这里加一行即可, 不要再复制一份 _elite_sys._elite_fix_norm。
#   门禁 verify_elite_anim 会拿 png 的真实 bbox 跟这张表对账。
const ANIM_NORM := {
	"__minion_elite__": [47.0, 71.0, 71.0],
	"__minion_front__": [45.0, 65.0, 60.0],
}


## 修正 PixelLab 动作帧的归一 —— 不修的话一播动作角色就缩到 ~56% 并悬空。
##   _set_anim_sheet 的通用规则是 pixel_size = TARGET_BODY_H / 帧高, 它默认【本体填满整帧】。
##   idle 图确实如此, 但 PixelLab 输出四周留白很多(精英 47/96=49%, 近战 45/88=51%)
##   → 同样归一到 2m, idle 角色 1.78m 而动作角色只有 0.98m(精英实测), 用户 2026-07-21 一眼看出。
##   ★不能靠放大 png 解决: 71/47 非整数倍, 像素画重采样会糊。改归一系数, 纯数字不动图。
##   ★2026-07-22 泛化成查 ANIM_NORM 表 —— 每套图数值不同, 不能沿用别人的常量。
func _melee_anim(u: Dictionary, action: String) -> void:
	if _anim_key(u) != "__minion_front__" or not u.get("alive", false):
		return
	if not is_instance_valid(u.get("sprite", null)):
		return
	if u.get("anim_action", "") == "death":
		return
	var e = ACTION_MELEE.get(action, null)
	if e == null:
		return
	var asd := _resolve_action(str(e[0]), float(e[1]))
	if asd.is_empty():
		return
	_set_anim_sheet(u, asd, action, false)
	_elite_sys._elite_fix_norm(u, asd)   # 归一查 ANIM_NORM 表, 前排/精英各自一行


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





# 状态条: 复用回合制版 HpBar 组件 (自定义 _draw: 黑边/暗红槽/玻璃高光/逐行渐变填充/护盾段/受击红trail+白闪/刻度).
#   + 左侧等级牌 (棕底金字 Panel, 回合制 turtle-hud 同款) + 下方龟能条 (实时资源, HpBar 不画).
#   level: 玩家龟读 GameState.season_level; 召唤体无牌. 返回各组件引用供 _render._update_overlay 刷新.
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
	# ★确定性模式(TURTLE_SEED 设): 用固定步长 SIM_DT → 同种子+同帧序=可复现回放/验证(不受帧率抖动影响)。
	#   交互游玩(无种子): 钳制真实delta防死亡螺旋(2026-07-18)—— 手感/行为与原来完全一致·零风险。
	var rd: float = minf(delta, 0.1)   # 钳制真实帧delta(防hitch·2026-07-18): 给 INPUT/render; sim 走固定步长累加器
	_trainer_sys._trainer_input_tick(rd)   # INPUT(每帧读一次): 训龟大师 PC键盘/移动端摇杆(用户2026-07-22)
	if _audit and _t >= _audit_next:
		_audit_next = _t + 1.0
		_audit_tick()
	if _stress:                # 卡死猎手: 心跳 + 自动开打(跳摆位) + 一局结束/超时→重开
		_hb += 1
		if _dl_state == "place":
			_dl_sys._dl_start_fight()          # 无头无玩家→自动开打(present阶段自己计时推进)
		if _over or _dl_state == "done" or _t > 240.0:   # 上限 240: 一场三路合法时长可超120s(上路含破蛋窗口+呈现就要60s+)
			_stress_reload(); return
		_dbg_op = "process"
	# ═══ Phase4切片2 累加器: sim 按固定步长 SIM_DT 推进 → 交互游玩帧率无关(根治"逻辑按60fps写死"整类)。 ═══
	# det模式(TURTLE_SEED设): 恰 1 步/帧(帧数固定→可复现·verify_battle_determinism 靠它)。
	# 交互: 攒够 SIM_DT 跑一步·总 sim 时间 = Σ钳制delta(与原一致)·只是粒度变成固定块。余量 _sim_accum 给切片2b渲染插值。
	# ★frozen/in_ts 每步 sim 前重新捕获(顿帧/时停可能跨步变化), sim 与 render 分别用各自最新态。
	if _deterministic:
		var frozen: bool = _hitstop > 0.0
		var in_ts: bool = not _timestop._ts_active.is_empty()
		_sim_step(SIM_DT, frozen, in_ts)
		_render_alpha = 0.0   # det/headless: 无渲染·不插值
	else:
		_advance_sim_accum(rd)   # ★切片2: 交互累加器抽成可测种子(verify_interactive_determinism 直接驱动·证帧率无关)
	# 演出每帧一次(真实时间·立绘动画/相机随真实帧走→平滑)。frozen/in_ts 用 sim 后最新态。
	var r_frozen: bool = _hitstop > 0.0
	var r_in_ts: bool = not _timestop._ts_active.is_empty()
	_render._render_step(rd, r_frozen, r_in_ts)

## Phase4切片2: 交互固定步长累加器。攒够 SIM_DT 就跑一步 sim → 总 sim 时间只取决于 Σ钳制delta,
## 与"帧被切成多大块"无关(60/144/300fps 落到同样的整步序列)→ 交互游玩帧率无关。
## 抽成独立函数是为了让 verify_interactive_determinism 直接驱动(不经真实帧率), 用不同分块喂同样总时长,
## 断言指纹逐字相同——把 v0.15.8「帧率无关」从"靠F5主观感受"变成可反证的门禁。
func _advance_sim_accum(rd: float) -> void:
	_sim_accum += rd
	var steps: int = 0
	while _sim_accum >= SIM_DT and steps < 8:   # 每帧最多8步(大hitch丢余量防雪崩·手感优先于追偿)
		_snapshot_render_prev()   # ★切片2b: 存这步前的 pos/height 供渲染插值(最后一次=渲染要的 prev)
		var frozen: bool = _hitstop > 0.0
		var in_ts: bool = not _timestop._ts_active.is_empty()
		_sim_step(SIM_DT, frozen, in_ts)
		_sim_accum -= SIM_DT
		steps += 1
	_render_alpha = _sim_accum / SIM_DT   # 余量分数 [0,1) → 立绘在 prev↔当前 间 lerp(高帧率零步/帧时 alpha 渐长→平滑推进)

## Phase4: 纯模拟推进(决定战斗结果·可被累加器按固定步长跑 N 次/帧)。frozen/in_ts 由调用方在 sim 前捕获传入。
func _sim_step(dt: float, frozen: bool, in_ts: bool) -> void:
	_adf_ct = 0   # 每帧(每步)重置伤害调用计数(_damage._apply_damage_from 帧内爆炸=死亡链无限级联→自身截断防卡死)
	_cur_eq_item = ""   # ★每帧重置"当前装备效果来源"(同 _adf_ct 的模式) —— 不清会让下一帧
						#   非装备来源的护盾/治疗被误判成"盾装备给的"而白拿 20% 圣光护盾
	_sd_tick()   # §SUDDEN 战场决胜(40s起治疗-50% + 每5s +25%增伤)
	_synergy.tick(dt)   # ★类型羁绊的周期效果(批4-1: 法器潮涌 / 食物盛宴 / 盾圣光) —— 走 dt 不走墙钟
	_swordsman.tick(dt)   # 剑士追打队列(以 5 倍攻速依次打出)
	_shield_syn.tick(dt)  # 圣光护盾装备: 每 3 秒 55 点护盾
	_bow_syn.tick(dt)     # 弓箭顶档【腐蚀叠层】: 每 2.5 秒给全场敌人 +1 层
	_gun_syn.tick(dt)     # 枪羁绊: 第一座炮台轰击 / 第二座能量循环(每 2.5 秒)
	_staff_syn.tick(dt)   # 法器: 法力自然增长 + 灵泉(2.5s) + 共鸣(7.5s)
	_potion_syn.tick(dt)  # 药水: 每 2.5 秒重选猎物(敌方血量最高者)
	_gadget_syn.tick(dt)  # 奇械: 铸币累计 + 僵硬到期清理
	_food_syn.tick(dt)    # 食物: 每 2.5 秒每件食物为携带者永久 +最大生命
	_spirit_syn.tick(dt)  # 灵物: 触手拍击(每 2.5 秒) + 追击次数重置
	_spec.tick(dt)        # ★特殊余额: 线性衰减 + 耗尽回调(自然衰减完也算"被打破")
	_equip_sys.tick_global(dt)   # ★装备的【全局】在途表(弧形波/箭雨/连射 + 批④ 的召唤物·区域·碑)
								 #   —— 与"某只龟身上有没有装备"无关: 携带者死后碑/直升机/炮台还要继续动
	_relic_syn.tick(dt)   # 遗物: 远古之力累积(每 2.5 秒) + 觉醒判定
	_tentacle_vfx.tick(dt)  # 触手拍击: 每帧重算网格(甩动)
	_trainer_sys._tick_trainer_attacks(dt) # 训龟大师普攻: 站定扔石头抛物线弹道(用户2026-07-23)
	_trainer_sys._tick_hunt_taunt(dt)      # 猎龟令: 每帧刷新目标周围 400 码我方友军的嘲讽(圈随目标移动)
	_trainer_sys._tick_tame_decay(dt)      # 驯服: 归顺者每秒损失 2% 最大生命
	_trainer_sys._tick_trainer_ai(dt)      # 敌方(快照)大师 AI: 乱走 + 逮机会甩钩锁(点3·场外援助·用户2026-07-23)
	_trainer_sys._ms_tick_aura(dt)         # 魔法石: 按叠层阈值(10/25/50)建撤大师本体特效 + 推进绕转
	_trainer_sys._tick_wave_flights(dt)     # 口哨②: 灵体气波蓄力/逐帧飞行/每帧碰撞(真 skillshot·命中才结算)
	_trainer_sys._tick_hooks(dt)           # 钩锁: CD 扣减 + 被钩单位每帧朝大师拖(点3)
	# Phase4 顿帧 hit-stop: 计时 >0 时冻结"模拟"给重量感(镜头震屏照常推进·在 _render._render_step)。
	if frozen:
		_hitstop = maxf(0.0, _hitstop - dt)
	elif in_ts:
		# ═══ 沙漏JoJo时停: 冻结全局_t → 全场非active的所有_t计时器暂停; 只tick active携带者 ═══
		_timestop._ts_remaining -= dt
		_timestop._ts_active = _timestop._ts_active.filter(func(x): return x is Dictionary and x.get("alive", false))
		if _timestop._ts_remaining <= 0.0 or _timestop._ts_active.is_empty():
			_timestop._end_timestop()
		else:
			if not _over:
				for u in _timestop._ts_active:
					_timestop._ts_advance_unit_timers(u, dt)   # 先让它自己的状态到期时刻按真实时间走(否则_t冻结→眩晕等永不解除)
					_tick_unit(u, dt)        # active携带者自由行动(移动/普攻/放技/命中即时结算)
				_ballistics._step_projectiles(dt)        # 内部gate: 只推进active的弹道; 其余悬空
				_ballistics._step_pending_shots(dt)      # 内部gate: 只active的依次射击
				_gold_vfx.tick(dt)                       # 金弹演出自推进(不用 tween, §3.5)
				_incense_vfx.tick(dt)                    # 093 香火石演出自推进(同上)
				_check_end()
	else:
		if _dl_sys._dl_is_present():
			_dl_present_t += dt
			if _dl_present_t >= DL_PRESENT_SEC: _dl_sys._dl_present_advance()
		# ★靶向器"抽搐→引爆"的延时【放在 _over 门控之外】推进: 被炸的若是最后一个敌人,
		#   杀掉它战斗就结束(_over=true), 挂在 _pending_shots 里的引爆就永远兑现不了 ——
		#   最高潮那一下的画面会凭空消失(伤害无所谓, 但演出没了)。
		_hookbomb_sys.tick_pending(dt)
		if not _over and not _edit_mode and _dl_state != "place" and not _dl_sys._dl_is_present():
			_t += dt
			_timestop._ts_update_trigger(dt)   # 沙漏: 第10秒触发时停蓄力 → 蓄力满释放
			for u in _units.duplicate():
				if not u["alive"]:
					continue
				_tick_unit(u, dt)
			_apply_separation_pass(dt)   # 每帧全单位软分离(攻击/待机也摊开, 根治扎堆遮血条)
			_lava_sys._tick_lava_zones(dt)         # 持续地面区域 (熔岩龟·岩浆池) 周期结算
			_trainer_sys._tick_glaciers(dt)           # 冰川带(训龟大师): 站带上的敌减速+易伤
			_ballistics._step_projectiles(dt)
			_ballistics._step_pending_shots(dt)
			_gold_vfx.tick(dt)                       # 金弹演出自推进(不用 tween, §3.5)
			_incense_vfx.tick(dt)                    # 093 香火石演出自推进(同上)
			_check_end()

## Phase4: 纯演出(立绘帧动画/相机/overlay·每帧一次)。frozen/in_ts 与 _sim_step 用同一份(sim前捕获)。
const _TS_TIMER_FIELDS := [
	"_anim_lock_until",
	"_mark_until",
	"_ninja_dash_until",
	"bind_until",
	"bubble_shield_until",
	"bulwark_until",
	"candle_hot_until",
	"crit_fate_until",
	"deathfloor_until",
	"diamond_fortify_until",
	"dice_dash_pause_until",
	"echarge_until",
	"energy_lock_until",
	"eq_hot_until",
	"eq_marked_until",
	"eq_target_until",
	"frost_shield_until",
	"gambler_bet_until",
	"gold_shield_until",
	"haste_until",
	"heal_reduce_until",
	"hiding_shield_until",
	"hijack_until",
	"hunt_mark_until",
	"lava_shield_until",
	"phase_until",
	"rock_shield_until",
	"rum_glow_until",
	"rum_until",
	"shield_until",
	"shock_boost_until",
	"signal_until",
	"skill_gcd_until",
	"slow_until",
	"spd_dbf_until",
	"star_lock_until",
	"stone_dr_until",
	"storm_until",
	"stun_until",
	"taunt_until",
	"thunder_shield_until",
	"true_fire_until",
	"untargetable_until",
	"volcano_until",
]

# VFX tween 注册(时停暂停非active产生的用). 见 create_tween→_reg_tween 替换.
func _reg_tween() -> Tween:
	var t := create_tween()
	_sim_tweens.append(t)
	if _sim_tweens.size() > 512:
		_sim_tweens = _sim_tweens.filter(func(x): return x != null and x.is_valid())
	return t

func _tick_unit(u: Dictionary, delta: float) -> void:
	if _stress: _dbg_op = "tick:" + str(u.get("id", "?"))   # 卡死猎手: 追踪当前tick的单位(冻死时定位)
	if _vfxiso and u.has("sprite") and is_instance_valid(u["sprite"]): u["sprite"].visible = false   # 纯特效隔离: 藏单位立绘(只留特效)
	# DoT/buff到期/累积条/周期被动 (1:1 2D _tick_effects)
	_tick_effects(u, delta)
	_update_shield_barrier(u)   # 石头岩石护盾: 持盾常驻六棱屏障(跟随), 盾破/到期碎裂淡出
	_update_diamond_barrier(u)   # 钻石坚不可摧: 持盾常驻青水晶护罩(跟随), 盾破/到期碎裂淡出
	_update_gold_barrier(u)      # 财神金盾: 持盾常驻金色护罩(跟随), 盾破/到期碎裂淡出
	if u.get("id") == "dice": _update_dice_blood_aura(u)   # 骰子赌徒之血: 低血泛血色气焰(暗示暴击拉满·用户2026-07-13)
	if u.get("id") == "rainbow": _update_rainbow_prism_aura(u)   # 彩虹棱镜: 持续显当前色(红/蓝/绿)一眼区分(用户2026-07-13)
	if u.get("_hunt_demo_victim", false) and u.get("alive", false):   # 被动demo靶: 每帧钉12%残血(普通箭伤不累积→恒在斩杀线下供强化箭处决)
		u["hp"] = float(u["maxHp"]) * 0.12
	_layout_head_badges(u)   # 统一头顶信息层(用户2026-07-15): 状态图标行(猎杀等)+叠层计数行(墨迹/电击等), 以头顶为中心对称排·防重叠·随角色不左右偏
	if u.get("id") == "hunter": _update_hunter_passive(u)   # 被动猎杀: 扫场→任一敌<斩杀线→自动射强化箭处决(用户2026-07-14重做·不在中央伤害路径判)
	if u.get("id") == "headless": _update_headless_flame(u)   # 亡灵残血紫焰(越残越浓/2026-07-17)
	if u.get("_bubble_burst_demo", false): u["bubble_store"] = float(u["maxHp"])   # 泡泡爆破demo: 每帧回满泡泡值(反复放爆破看门/墙)
	if OS.has_environment("VFXCAST") and u["id"] == _review_turtle() and u.get("alive", false):   # 纯特效隔离验证(用户2026-07-15): 周期强制放指定演出(VFXISO黑底可选·不强制→验镰刀时留龟立绘看支点)
		u["_vfxcast_t"] = float(u.get("_vfxcast_t", 0.0)) + delta
		if u["_vfxcast_t"] >= (3.0 if OS.get_environment("VFXCAST").begins_with("headless") else 7.0):
			u["_vfxcast_t"] = 0.0
			match OS.get_environment("VFXCAST"):
				"lavawave": _lava_sys._lava_volcano_erupt(u)
				"headless_scythe": _headless_sys._headless_scythe_sweep(u["pos"], Vector2.RIGHT)   # 隔离验证斩击弧光(2026-07-17临时)
				"headless_tendrils": _headless_sys._sk_headless_tendrils(u)
	# 侵入标识(用户2026-07-22 重定: 全身冒红光 + 电流穿身 + 环绕特效; ★血条【依旧是敌方色】不改)
	#   原为红/绿故障闪(2026-07-15), 绿色会让人误以为它变成了我方 —— 现在统一成红。
	if u.get("hijacked", false) and u.get("alive", false):
		var _gspr = u.get("sprite", null)
		if is_instance_valid(_gspr):
			var _pul: float = 0.5 + 0.5 * sin(_t * 11.0)                  # 红光呼吸
			_gspr.modulate = Color(1.0 + 0.55 * _pul, 0.42 + 0.18 * _pul, 0.42 + 0.18 * _pul)
		# 电流穿身: 每 ~0.13s 在身体范围内随机位置炸一道小电弧(不用 tween, 靠 _burst_vfx 自播完自销)
		if _t >= float(u.get("_hj_zap_next", 0.0)):
			u["_hj_zap_next"] = _t + _battle_rng.randf_range(0.09, 0.17)
			var _zp: Vector2 = (u["pos"] as Vector2) + Vector2(randf_range(-16.0, 16.0), randf_range(-20.0, 12.0))
			_burst_vfx("res://assets/sprites/vfx/electric-zap.png", _zp,
				randf_range(20.0, 34.0), float(u.get("height", 0.0)) + randf_range(0.25, 1.05))
	if u.has("_home_pos") and u.get("alive", false) and not u.get("airborne", false) and not u.get("_slam", false):   # fixed评审假人: 被击飞落地后缓步归位(板稳定·_slam定身期不归位→扭曲空间换位落点可保持)
		var _hp2: Vector2 = u["_home_pos"]
		if (u["pos"] as Vector2).distance_to(_hp2) > 4.0:
			u["pos"] = (u["pos"] as Vector2).move_toward(_hp2, 220.0 * delta)
	if u.get("id") == "candy" and not u.get("_sweet_drained", false):   # 甜蜜掠夺: 战斗第8秒触发一次甜蜜吸取(用户2026-07-15改·原登场触发)
		u["_sweet_t"] = float(u.get("_sweet_t", 0.0)) + delta
		if float(u["_sweet_t"]) >= 8.0:
			u["_sweet_drained"] = true
			_candy_sys._candy_sweet_drain(u)
	if u.get("summon_kind", "") == "candybomb" and u.get("alive", false):   # 糖果炸弹: 随血量缩小(融化感)+持续糖泡(用户2026-07-14参照海盗船完整呈现)
		var _cbspr = u.get("sprite", null)
		if is_instance_valid(_cbspr):
			var _cbf: float = 0.6 + 0.55 * clampf(float(u["hp"]) / maxf(1.0, float(u["maxHp"])), 0.0, 1.0)
			_cbspr.scale = Vector3(_cbf, _cbf, _cbf)
		u["_cb_vfx_t"] = float(u.get("_cb_vfx_t", 0.0)) + delta
		if float(u["_cb_vfx_t"]) >= 0.42:
			u["_cb_vfx_t"] = 0.0
			_candy_sys._candy_bomb_bubble(u)
	_update_stun_vfx(u)         # 通用眩晕圈: 眩晕期间头顶火花星绕转(椭圆), 结束即撤
	_update_bamboo_charge_dots(u)   # 竹叶蓄满: 双手两绿点(强化就绪指示)
	_damage._heal_flush(u)   # LoL式治疗累加器: 攒一波回血合并成一个绿字(满血=0)
	if _t < float(u.get("candle_hot_until", 0.0)):   # 蜡烛光圈037: 圈内逐渐回血(HoT)
		_damage._heal(u, float(u.get("candle_hot_rate", 0.0)) * delta, true)
	# 装备救命回血 HoT (044深海项链6秒 / 045珍珠耳环8秒; 用户2026-08-01「改为在N秒内回复X%最大生命值」)。
	# ★用【固定速率×delta】而不是"每帧 maxHp×比例": 携带者在回复期间可能被温泉蛋/升级顶高 maxHp,
	#   按当前 maxHp 现算会让总量随之膨胀 —— 触发瞬间锁死 rate, 总量才等于文案写的那个数。
	# ★死亡即停(方案书 §4·F): 本函数只在 alive 单位上跑, 不需要额外判定。
	if _t < float(u.get("eq_hot_until", 0.0)):
		_damage._heal(u, float(u.get("eq_hot_rate", 0.0)) * delta, true)
	# 靶向器055 钩索炸弹: 挂在宿主身上, 每秒对宿主造成其 maxHp 的 2/4/4% 物理伤害, 直到宿主死亡
	if float(u.get("hookbomb_pct", 0.0)) > 0.0:
		_hookbomb_sys._hb_tick(u, delta)
	if _t < float(u.get("rum_until", 0.0)):   # 海盗朗姆酒: 每秒回4%maxHP(分秒HoT·rum_dps=每秒速率)
		var _rhpb: float = float(u["hp"])
		_damage._heal(u, float(u.get("rum_dps", 0.0)) * delta, true)
		u["_rum_heal_acc"] = float(u.get("_rum_heal_acc", 0.0)) + maxf(0.0, float(u["hp"]) - _rhpb)   # 累积实际回血(满血则0)
		u["_rum_vfx_t"] = float(u.get("_rum_vfx_t", 0.0)) + delta
		while u["_rum_vfx_t"] >= 0.55:   # 每0.55s: 暖酒气泡 + 实际回血绿字(真回了才显·符合数字规矩)
			u["_rum_vfx_t"] -= 0.55
			_pirate_sys._pirate_rum_bubble(u)
			var _rhd: int = int(u.get("_rum_heal_acc", 0.0))
			u["_rum_heal_acc"] = 0.0
			if u.get("alive", false) and _rhd >= 1:
				_vfx._float_text(u["pos"] + Vector2(randf_range(-18.0, 18.0), -48.0), "+" + str(_rhd), Color("#7fe39a"))
	if not u["alive"]:
		return
	if u.get("_skele_pending", false):                    # 032: 登场召唤亡灵骷髅(首帧)
		u["_skele_pending"] = false
		_equip_sys._eq_summon_skeleton(u, int(u.get("_skele_si", 0)))
	if u.get("_turret_pending", false):                   # 058: 登场召唤炮台(首帧)
		u["_turret_pending"] = false
		_equip_sys._eq_summon_turret(u, int(u.get("_turret_si", 0)))
	if u.get("_slam", false):   # 火山砸地演出中: 锁AI/移动 (height/pos由slam tween驱动)
		return
	var stunned: bool = _t < u["stun_until"]

	# --- 击飞真物理: vy 受重力, height 积分; 横向同时滑 (XZ 像素坐标方向) ---
	if u["airborne"]:
		# 飞镖056: 任何单位被击飞→敌侧有飞镖携带者就标"靶子"(用户2026-07-18「很多被击飞没触发」: 原来只在_knockback里标·漏了直接设airborne的技能+已在空中再击飞的·这里按airborne态统一捕获·已标则跳过不重复)
		if _t >= float(u.get("eq_target_until", 0.0)) and not u.get("_isEgg", false):
			var _foe_side: String = "right" if str(u.get("side", "")) == "left" else "left"
			if _side_has_equip(_foe_side, "p2eq_056"):
				u["eq_target_until"] = _t + 99999.0
				_mark_vfx(u, 99999.0, Color("#ffa040"))
		u["vy"] += float(u.get("knock_g", GRAVITY)) * delta   # 每次击飞可覆写重力(解耦滞空时长与抛高·如嘲讽砸地 -13.2); 缺省=GRAVITY
		u["height"] += u["vy"] * delta
		# 横向滑行换算回像素 (vx/vz 是米/s → /WS = 像素/s)
		u["pos"].x += u["vx"] / WS * delta
		u["pos"].y += u["vz"] / WS * delta
		var _kdamp: float = pow(0.9, delta * 60.0)   # ★帧率无关阻尼(2026-07-25): 原每帧×0.9 假设60fps; 高帧率下每秒衰减快数倍→击飞竖直照抛(vy走delta)但横向vx几乎不滑="飞不出去"。按时间衰减·60fps下=0.9原值
		u["vx"] *= _kdamp; u["vz"] *= _kdamp
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		if u["height"] <= 0.0:
			u["height"] = 0.0; u["vy"] = 0.0; u["vx"] = 0.0; u["vz"] = 0.0
			u["airborne"] = false
			u.erase("knock_g")   # 落地 → 清本次击飞的重力覆写(下次默认 GRAVITY)
			# Phase4: 落地 → 压扁回弹 + 小尘 + 轻震屏 (重量感)
			u["land_t"] = JUICE_LAND_SEC
			_shake(JUICE_SHAKE_HEAVY)
			_vfx._impact_particles(u["pos"], 0.0)
			# ★★真实落地事件 → 通知装备系统(090 猛砸靠它结算)。
			#   为什么不能靠倒计时: `_equip_sys.tick_global` 在本函数【上方】无条件执行,
			#   而这段 airborne 积分被 `if frozen / elif in_ts / else` 门控着 ⇒
			#   顿帧/时停期间跳跃冻结、倒计时照跑, 砸落会提前(实测早 3.59 米)。
			#   落地事件是【同一个物理量】的事件, 不存在两个时钟对不上的问题。
			_equip_sys.on_unit_landed(u)
		return   # 击飞中不移动/不攻击 (覆盖正常行为)

	if u.get("roll_active", false):   # 钻石滚球: 蜷球滚动位移态(免疫定身沉默打断·封板) — 在stun检查前, 覆盖正常AI
		_diamond_sys._diamond_roll_tick(u, delta)
		return

	if u.get("dice_dash_active", false):   # 稳定骰子: 真冲刺连突态(逐帧穿刺·刀妹Irelia Q式·覆盖正常AI)
		_dice_sys._dice_dash_tick(u, delta)
		return

	if u.get("hunter_roll_active", false):   # 猎人隐蔽: 平滑翻滚滑行态(逐帧真位移·薇恩Q式·覆盖正常AI·非瞬移·用户2026-07-14)
		_hunter_sys._hunter_roll_tick(u, delta)
		return

	_tick_skill_cd(u, delta)        # 技能冷却(=龟能充能)走时间; ★但眩晕/击飞/风暴期内部直接return→龟能锁定不充(见_tick_skill_cd)
	_tick_bulwark(u)                # 水晶壁垒监视: 盾到期/被打破→直线水晶刺+解锁龟能(用户2026-07-16)
	_tick_elite_whip(u)             # 精英小将铁锁(Whipfist): 索敌150~350码之间→链拉体(CD5s·虐杀原形改造·范围2026-07-18改)
	u["atk_cd"] = maxf(0.0, float(u.get("atk_cd", 0.0)) - delta)   # 普攻冷却也始终走 (漏了它→打一下就再不普攻=用户报的"整个没普攻"; 召唤体也安全)
	if int(u.get("allin_coins", 0)) > 0:
		_fortune_sys._fortune_allin_channel(u, delta)
		return   # 财神梭哈投币channel: 锁住(不移动/不普攻)
	var tgt = _targeting._acquire_target(u)
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
	var rng: float = _eff_range(u)
	var spd: float = u["move_spd"] * float(u.get("move_perm", 1.0)) * (float(u.get("slow_mag", 0.6)) if _t < u["slow_until"] else 1.0) * (float(u.get("spd_move_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0) * (float(u.get("move_buff_mult", 1.0)) if _t < float(u.get("move_buff_until", 0.0)) else 1.0)   # ×移速buff通道(怒火药水等·独立于减速debuff防冲突)

	# ═══ AI 状态机: 移动 ↔ 前摇 → 出手 → 后摇 (移动与攻击/施法互斥 = 施法锁; 根治"边走边放") ═══
	match str(u.get("state", "move")):
		"move":
			var rs := _pick_ready_skill(u)
			if _t < float(u.get("_anim_lock_until", 0.0)):
				pass                                     # 动作锁(背刺等committed动作): 播完前站定不出手/不放技/不移动(用户2026-07-11 动作播完前不打断)
			elif dist <= rng and not u.get("no_basic", false) and u["id"] != "phoenix" and u["atk_cd"] <= 0.0:
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
					_phoenix_sys._phoenix_flame_channel(u, tgt, delta)               # 凤凰: 持续喷火(VFX+每0.5s伤害)
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
					if tgt == null or not tgt.get("alive", false):
						tgt = _targeting._nearest_enemy(u)                  # 前摇期目标死→改打最近敌(不浪费已承诺出手·用户2026-07-12)
					var _fired := false
					if tgt != null and tgt.get("alive", false):
						# 出手承诺: 前摇一旦走完必打出, 不再被射程门丢弃(根治近战被风筝→抬手→目标跑出射程→这一击作废→再追→再空转→伤害完全打不出)
						if u["melee"] and (tgt["pos"] - u["pos"]).length() > rng:
							_melee_lunge(u, tgt)                 # 目标微脱离→踏步补缺口(视觉够到·伤害由_basic_attack保证)
						_basic_attack(u, tgt)
						_fired = true
					# gambler 多重打击(云顶剑士式): 命中后掷概率, 中→快攻速再打, 没中→正常冷却
					var _hf: float = maxf(1.0, float(u.get("haste_mult", 1.0))) if _t < float(u.get("haste_until", 0.0)) else 1.0   # 临时攻速buff(祝福等)
					if u["id"] == "hunter" and tgt != null and tgt.get("alive", false) and float(tgt.get("hp", 0.0)) < float(tgt.get("maxHp", 1.0)) * 0.5:
						_hf *= 1.5   # 猎人残血追猎(封板): 目标<50%生命 → +50%攻速
					u["atk_cd"] = (_gambler_sys._gambler_multi_cd(u) if (u["id"] == "gambler" and _fired) else u["atk_interval"]) / maxf(0.1, _hf * (float(u.get("spd_aspd_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0) * float(u.get("aspd_perm", 1.0)) * _anchor_aspd(u) * float(u.get("_turret_aspd_mult", 1.0)))   # ×永久攻速(贝母021等,本场) ×沉锚充能期+100%攻速 ×058在炮台400码内的攻速加成
					u["state"] = "move"   # LoL忠实: 伤害点后立即自由(可动/被分离=orb walk), 无rooted后摇; 后摇=视觉lunge回收+squash不锁移动; 下次普攻等atk_cd(=1/攻速)
				else:
					var stype := p.substr(2)
					if u["id"] == "two_head" and stype != "twoHeadFusion":   # 双头双生(用户2026-07-11反序): 龟能满→①先切形态+位移(铺垫)→②顿→③再放该形态技(非收尾)
						u["skill_cd"][stype] = _skill_cd(u, stype)
						u["skill_gcd_until"] = _t + SKILL_GCD
						_two_head_sys._two_head_after_cast(u, tgt)                          # ① 切形态+位移(滑扑进/滑退出·含切换攻击)
						var _thd2: float = 0.5 if u["melee"] else 0.45        # ② 顿(位移到位+停顿; 此时melee=切后新形态)
						u["_anim_lock_until"] = _t + _thd2
						_pending_shots.append({"delay": _thd2, "src": u, "fn": _two_head_sys._two_head_deferred_cast.bind(u, tgt, stype)})   # ③ 放该形态技
					elif _cast_skill(u, tgt, stype):
						u["skill_cd"][stype] = _skill_cd(u, stype)
						u["skill_gcd_until"] = _t + SKILL_GCD
						_equip_sys._eq_on_cast(u, tgt)
						if u["id"] == "space" and float(u.get("star_energy", 0.0)) > 0.0:   # 星能: 施法后追加12%当前星能真伤(用户2026-07-16: 30%→12%)
							_damage._apply_damage_from(u, tgt, int(u["star_energy"] * 0.12), Color("#ffffff"), 0.0, true)
						if u["id"] == "shell":                   # 潜影: 自己放技能→破隐(下次普攻附破隐bonus)
							_shell_sys._shell_break_stealth(u)
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
	if _t < float(u.get("diamond_fortify_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0:
		return   # 钻石坚不可摧: 持盾期锁龟能不充能, 盾破/到期即恢复(用户2026-07-12·60龟能改制)
	if _t < float(u.get("gold_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0:
		return   # 财神金盾: 持盾期锁龟能不充能, 盾破/到期即恢复(用户2026-07-12·梭哈后该技变金盾)
	if u.get("_bulwark_armed", false) and _t < float(u.get("bulwark_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0:
		return   # 水晶壁垒: 持盾期锁龟能, 盾破/到期→放直线水晶刺后恢复(用户2026-07-16)
	if _t < float(u.get("hiding_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0:
		return   # 缩头防御特殊盾: 持盾期锁龟能, 盾破/到期即恢复(用户2026-07-17)
	var _ecm: float = maxf(1.0, float(u.get("echarge_mult", 1.0))) if _t < float(u.get("echarge_until", 0.0)) else 1.0   # 龟能充能加速buff —— 目前【无任何来源】: 天使祝福原有的30%龟能充能已于2026-07-11被用户删除, 此读取分支是残留(留作将来接口)
	if _t < float(u.get("spd_dbf_until", 0.0)):
		_ecm *= float(u.get("spd_echarge_mult", 1.0))   # 充能减速debuff(寒冰登场等)
	_ecm = maxf(0.05, _ecm)
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta * _ecm * float(u.get("echarge_perm", 1.0)) * float(u.get("_ts_echarge", 1.0)))   # 麻痹也走, 只是放不出; ×充能速率(含装备永久充能速率echarge_perm) ×沙漏时停期+100%
	if float(u.get("energy_bank", 0.0)) > 0.0:   # 龟能银行(贝母021溢出): 冷却能吸就吸(如刚重置), 吸不下继续留着
		_apply_energy_bank(u)

func _is_hostile(a: Dictionary, b: Dictionary) -> bool:
	if is_same(a, b):
		return false          # is_same: 单位字典互引成环, == 会深比较→卡死(项目铁律)
	if bool(b.get("hijacked", false)):
		return true           # 被侵入者对所有人都是敌人(含侵入它的赛博方)
	if bool(a.get("hijacked", false)):
		return _tamed_side(b) == str(a.get("_hijack_orig_side", ""))   # 它只打原队友
	return _tamed_side(a) != _tamed_side(b)


## 单位的【实际所属阵营】—— 驯服(训龟大师)会让敌方单位真正归顺我方。
##
## ★和 hijacked 是两种不同的语义, 别混:
##   · hijacked(赛博侵入) = 孤军, 对【所有人】都是敌人, 谁也不给它加治疗
##   · tamed_side(驯服)   = 真·换队, 用户 2026-07-28 明确「顺归算我方」
## ★同样【不改写 side】—— 改写 side 会丢掉"它原来是哪边的"这个信息, 而
##   _dl_snapshot_survivors / 击杀归属 / 复活归属都还要用原 side。
##   (赛博侵入那次就是因为改写 side, 把被侵入者变成了赛博方的真友军, 与权威文档相反。)
func _tamed_side(u: Dictionary) -> String:
	var t := str(u.get("tamed_side", ""))
	return t if t != "" else str(u.get("side", ""))


## 双向都不敌对才算友军 → 被侵入者是孤军(谁也不给它加治疗/护盾, 它也不给别人加)
func _is_ally(a: Dictionary, b: Dictionary) -> bool:
	if is_same(a, b):
		return false
	return (not _is_hostile(a, b)) and (not _is_hostile(b, a))


## 胜负/存活数用的"有效阵营" —— 被侵入者仍按原阵营计, 免得把原阵营"抹空"提前判胜负
func _eff_side(u: Dictionary) -> String:
	if u.get("hijacked", false):
		return str(u.get("_hijack_orig_side", u.get("side", "")))
	# ★驯服与侵入在这里【相反】: 被侵入者仍按原阵营计(免得把原阵营抹空提前判胜负),
	#   而被驯服者是【真的换了队】—— 原队就该少这一个人, 这正是这个技能的价值所在。
	return _tamed_side(u)


## 击杀归属改写 —— 被侵入者打死的人, 人头算侵入它的赛博龟(用户2026-07-22)。
##   赛博龟【自己已死也照算】: 侵入是它放的, 战果就是它的。
##   ★_hijack_by 存的是单位字典的【引用值】, 不是 key —— 项目铁律只禁止拿单位字典【做 Dictionary 的键】
##     和用 == 比较, 存引用是既有做法(同 taunt_by)。
func _credit_killer(src):
	if src is Dictionary and src.get("hijacked", false):
		var by = src.get("_hijack_by", null)
		if by is Dictionary:
			return by
	return src


## 侵入环绕特效: 贴地红环跟随本体, 与"电流穿身"(见 _tick_unit 的 hijacked 分支)配套
func _hijack_fx_attach(v: Dictionary) -> void:
	_aura_vfx("res://assets/sprites/vfx/electric-zap.png", v, 46.0, Color(1.0, 0.25, 0.25, 0.55), 5.0, 0.05)
	_skill_ring(v["pos"], Color(1.0, 0.22, 0.22, 0.6), 58.0)


func _tick_effects(u: Dictionary, delta: float) -> void:
	# 信号放大器038: 增伤到期回收(damage_amp 是常驻字段, 需显式撤回本件贡献)
	if float(u.get("signal_amp", 0.0)) > 0.0 and _t >= float(u.get("signal_until", 0.0)):
		u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - float(u["signal_amp"]))
		u["signal_amp"] = 0.0
	# 海胆护盾(013满层): 10秒内线性衰减(用户2026-07-19); 从共享护盾池里逐帧扣回
	var _ush: float = float(u.get("urchin_sh_left", 0.0))
	if _ush > 0.0:
		var _udec: float = minf(float(u.get("urchin_sh_rate", 0.0)) * delta, _ush)
		u["shield"] = maxf(0.0, float(u.get("shield", 0.0)) - _udec)
		u["urchin_sh_left"] = maxf(0.0, _ush - _udec)
	# flat DoT 列表 (诅咒等 = 真伤)
	# ★2026-07-22 改走正规伤害路径。原先走 _raw_lose(8行): 不进统计/不跳飘字/不过任何减伤/
	#   无组装期免疫闸/评审训练靶会被诅咒打死; 且 dps*delta 逐帧连续掉血(血条像漏水)。
	#   现改为【攒够1点才跳一次】, 与层数DOT节奏一致, 飘字也才看得清。
	var keep: Array = []
	for dot in u["dots"]:
		if _t < dot["until"]:
			dot["_acc"] = float(dot.get("_acc", 0.0)) + float(dot["dps"]) * delta
			if float(dot["_acc"]) >= 1.0:
				var _cd_dmg: int = int(floor(float(dot["_acc"])))
				dot["_acc"] = float(dot["_acc"]) - float(_cd_dmg)
				_damage._apply_damage(u, _cd_dmg, Color(UIPalette.TRUE_DMG), dot.get("src", null), "tru", false, true, true)   # col 实际被 dot_accum 按桶色覆盖(tru=白); 这里给白只为不误导
				if not u["alive"]:
					return
			keep.append(dot)
	u["dots"] = keep
	# 诅咒特效(用户2026-07-11): 中咒→头顶挂诅咒骷髅标记(跟随)+ 周期冒黑紫怨气; 咒散→标记消
	var _has_curse := false
	for _cd in u["dots"]:
		if str(_cd["tag"]) == "curse":
			_has_curse = true
			break
	if _has_curse:
		if not is_instance_valid(u.get("_curse_mark", null)):
			_ghost_sys._ghost_curse_mark(u)
		u["curse_vfx_t"] = float(u.get("curse_vfx_t", 0.0)) + delta
		while u["curse_vfx_t"] >= 0.22:
			u["curse_vfx_t"] -= 0.22
			_ghost_sys._ghost_curse_wisp(u["pos"])
	elif is_instance_valid(u.get("_curse_mark", null)):
		u["_curse_mark"].queue_free()
		u["_curse_mark"] = null
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
	# 中毒特效: 持续冒毒绿泡(照灼烧余烬·让"中毒"状态一眼可辨·用户2026-07-14)
	if u["alive"] and int(u.get("dot_stacks", {}).get("poison", 0)) > 0:
		u["poison_vfx_t"] = float(u.get("poison_vfx_t", 0.0)) + delta
		while u["poison_vfx_t"] >= 0.2:
			u["poison_vfx_t"] -= 0.2
			_spawn_poison_bubble(u)
	if u["id"] == "phoenix" and u.get("flame_sector", null) != null and is_instance_valid(u.get("flame_sector")) and _t > float(u.get("flame_sector_t", 0.0)):
		var _fs = u["flame_sector"]   # 停喷≠瞬灭(用户2026-07-15"完整运动"): 追加关样本继续回放→残焰飞到目的地才灭
		if _fs.visible:
			var _hist: Array = u.get("phx_hist", [])
			_hist.append([_t, (float(_hist[-1][1]) if not _hist.is_empty() else 0.0), 0.0])
			while _hist.size() > 90: _hist.pop_front()
			u["phx_hist"] = _hist
			if not _phoenix_sys._phoenix_build_flame_mesh(u):
				_fs.visible = false
				u["phx_hist"] = []
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
		_equip_sys._eq_tick(u, delta)
		_equip_tick_sys._tick_doll(u, delta)
		_equip_tick_sys._tick_rustblade(u, delta)
		_equip_tick_sys._tick_sword_storm(u, delta)
		_equip_tick_sys._tick_broadsword(u, delta)
		_equip_tick_sys._tick_coral(u, delta)          # 双穿珊瑚刺008: 修——之前漏挂dispatch→整个珊瑚刺击效果从未触发(用户2026-07-19发现)
		_equip_tick_sys._tick_laser(u, delta)
		_equip_tick_sys._tick_jelly(u, delta)
		_equip_tick_sys._tick_fortress(u, delta)
		_equip_tick_sys._tick_ironwall(u, delta)
		_equip_tick_sys._tick_shell(u, delta)
		_equip_tick_sys._tick_thunder(u, delta)
		_equip_tick_sys._tick_baton(u, delta)
		_equip_tick_sys._tick_ice_fissure(u, delta)
		_equip_tick_sys._tick_gear(u, delta)
		_equip_sys._tick_eq_turret(u, delta)   # 058炮台: 双抗随携带者存活 + 携带者近身攻速 + 锁定红线
		_equip_sys._tick_eq_intervals(u, delta)
		_equip_tick_sys._tick_anemone(u, delta)
		_equip_tick_sys._tick_dumbbell(u, delta)
		_equip_tick_sys._tick_barnacle(u, delta)
		_equip_tick_sys._tick_anchor(u, delta)      # 017沉锚: 每0.25秒回血(用户2026-08-01, 原挂 on-hurt)
		_equip_tick_sys._tick_targeter(u, delta)    # 055靶向器: 首次累计400伤害→挂钩索炸弹(用户2026-08-01)
		_equip_tick_sys._tick_hotspring(u, delta)   # 036温泉蛋: 携带者每秒回血 5/7/10(用户2026-08-01)

func _separation(u: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	# ★近战修: 对"自己的攻击目标"用缩小的分离半径(射程内), 让近战能贴进去开打; 其余单位照常 SEP_RADIUS 散开.
	var mt = u.get("_sep_target", null)
	var mt_valid: bool = bool(u.get("melee", false)) and mt is Dictionary and (mt as Dictionary).get("alive", false)
	var tgt_radius: float = minf(SEP_RADIUS, _eff_range(u) * 0.85)
	for o in _units:
		if is_same(o, u) or not o["alive"]:
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
func _anchor_aspd(u: Dictionary) -> float:   # 不沉之锚017: 持有沉锚充能期间普攻+100%攻速(用户2026-07-19)
	var ast: Dictionary = u.get("eq_state", {}).get("p2eq_017", {})
	if ast.is_empty():
		return 1.0
	if int(ast.get("anchor_charges", 0)) > 0:
		return 2.0
	# 刚用掉最后一点充能的这一发也算"持有充能"(避免末发掉速)
	return 2.0 if absf(_t - float(u.get("anchor_swing_t", -99.0))) < 0.001 else 1.0

func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	_anticipate(u)                  # Phase4: 普攻预备(缩)+挥出(伸) 前后摇形变
	_vfx._play_action(u, "attack")       # 有动作帧的龟(basic/ghost/ninja)播普攻动画, 其余靠 juice 形变
	_equip_sys._eq_on_basic_attack(u, tgt)   # 普攻计数装备(008每5次普攻射珊瑚刺, 不算多段)
	_swordsman.on_basic_attack(u, tgt)       # 剑士: 排 1/1/2 次追打(★追打自己不走这里, 防自递归与赌神连击互喂)
	if u.get("_eq_turret", false):   # 058炮台: 每次普攻自身永久+护穿+暴击(到本场战斗结束)
		_turret_on_shot(u, tgt)
	if u.get("is_big_bear", false):  # 大熊: 熊掌攒层, 满2层→放冲击波(小菊式)
		_big_bear_attack(u, tgt)
		return
	if u["id"] == "lightning":      # 闪电改造: 一道闪电(魔法)+连锁, 叠层走 _on_basic_hit(满8→雷暴)
		_lightning_sys._lightning_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "shell":          # 龟壳改造: 1ATK单段·物/真逐攻交替 + 主目标120px内其他敌溅射50%(同类型)
		_shell_sys._shell_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "__minion__" and u.get("is_elite", false):   # 精英小将(虐杀原形): 吞噬检查→第5击旋刃→长手刃1A物理
		_elite_sys._elite_basic(u, tgt)
		return
	if u["id"] == "chest":          # 宝箱砸击(封板): K'Sante一段Q式·前方短直线AOE·1A物理(近战扫一小片非单体)
		_chest_sys._chest_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "two_head":       # 双头(封板): 普攻随形态 — 远程1.2A物理(灵能弹)/近战0.9A物理(挥砍)
		var _thsc: float = 0.9 if u["melee"] else 1.2
		_emit_basic(u, tgt, _atk_dmg(u, _thsc, tgt), Color("#c0a0ff"), 0)
		if str(u.get("_th_enh", "")) != "":                      # 双生强化普攻: 搬旧切形态那一下的伤害+效果(就这1下·用户2026-07-11 B案)
			_two_head_sys._two_head_enhanced_basic(u, tgt, str(u["_th_enh"]))
			u["_th_enh"] = ""
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "ghost":          # 幽灵普攻幽魂触碰(封板): 远程灵体触碰·专属幽魂弹道·命中同发0.4A物理(红)+0.9A真实(白)+灵体怨气(用户2026-07-11修:原真实段瞬发/物理段随弹道→不同时跳)
		_ballistics._fire_ghost_wisp(u, tgt)
		return
	if u["id"] == "cyber":          # 贯穿激光(封板): 首个1A物理·后续50%(用户2026-07-28削弱)·穿透飞到射程尽头(射程450)
		var _cdir: Vector2 = tgt["pos"] - u["pos"]
		if _cdir.length() < 1.0: _cdir = Vector2.RIGHT
		_cdir = _cdir.normalized()
		# ★必须按【离赛博的距离】排序才有"穿过的第一个"这个概念 ——
		#   原实现是遍历全体敌人判在不在线上, 命中顺序取决于 _units 的数组顺序, 没有先后可言。
		var _hits: Array = []
		for o in _targeting._enemies_of(u):
			if o.get("alive", false) and _on_line(u["pos"], _cdir, o["pos"], 55.0):
				_hits.append(o)
		_hits.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length() < (b["pos"] - u["pos"]).length())
		for _i2 in range(_hits.size()):
			var o: Dictionary = _hits[_i2]
			var _sc: float = 1.0 if _i2 == 0 else CYBER_LASER_FALLOFF   # 首个满伤, 后续 50%
			_damage._apply_basic_hit_from(u, o, _atk_dmg(u, _sc, o), Color("#9bf0ff"))
			_vfx._hit_spark(o)                                                       # 沿线每个命中点火花(2026-07-15提质)
		_bolt_line(u["pos"], u["pos"] + _cdir * 1300.0, Color(0.85, 1.0, 1.0))     # 白青亮核心线
		_beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + _cdir * 1300.0, 44.0, Color(0.5, 0.9, 1.0, 0.55), 0.22)   # 青色辉光束(细·随核心线衰减)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "headless":       # 撕咬: 1A物理(红) + 3%目标最大生命魔法(蓝·按UI规则); 灵魂强化窗口(用户2026-07-17机制大改): 下3次攻击各额外0.5A魔法+10%当前生命魔法(蓝)+牙齿闭合, 第3下→镰刀横扫
		_damage._apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ff4444"))
		if tgt.get("alive", false): _damage._apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.03), Color("#9bdcff"))   # 3%maxHp魔法(蓝)
		if int(u.get("headless_soul_stacks", 0)) > 0:              # 灵魂强化: 下3次攻击各附加(用户2026-07-17)
			u["headless_soul_stacks"] = int(u["headless_soul_stacks"]) - 1
			if tgt.get("alive", false):
				_damage._apply_damage_from(u, tgt, _atk_dmg(u, 0.5, tgt, true), Color("#9bdcff"))   # 额外0.5A魔法
				_damage._apply_damage_from(u, tgt, int(tgt["hp"] * 0.10), Color("#9bdcff"))          # 额外10%当前生命魔法
				_headless_sys._headless_soul_bite(tgt)                            # 像素牙齿闭合命中特效
			if int(u["headless_soul_stacks"]) <= 0:
				_headless_sys._headless_scythe(u)                                 # 第3下打完→蓄力→镰刀横扫
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "diamond":                                          # 钻石普攻·切割: 水晶斩弧闪现(伤害走下方 _do_basic·BASIC_ATK.diamond=0.7A+0.6甲+0.6抗)
		_diamond_sys._diamond_slash_fx(u, tgt)
	if u["id"] == "fortune":                                        # 财神普攻·金剑打击: 金色斩弧+迸金(伤害走 _do_basic·吃金币加成)
		_fortune_sys._fortune_strike_fx(u, tgt)
	if u["id"] == "pirate":                                         # 海盗普攻·弯刀劈砍: 钢色新月斩弧+命中环(伤害走 _do_basic·1A物理+自愈0.2A)
		_weapon_slash(u["pos"], tgt["pos"], Color(0.88, 0.93, 1.0))
	if u["id"] == "candy":                                          # 糖果普攻·糖果拳: 命中糖爆粉星(伤害走 _do_basic·1.1A+3%maxHp物理+减攻15%)
		var _cdir: Vector2 = (tgt["pos"] - u["pos"]).normalized() if (tgt["pos"] - u["pos"]).length() > 1.0 else Vector2.RIGHT
		_burst_vfx("res://assets/sprites/vfx/candy-burst.png", tgt["pos"] - _cdir * 8.0, 95.0, 0.35)
	if u["id"] == "bubble":                                         # 泡泡普攻·泡泡三连击: 命中泡泡爆+泡沫(伤害走 _do_basic·0.5A×3物理)
		_burst_vfx("res://assets/sprites/skills/bubble-attack.png", tgt["pos"], 80.0, 0.9)
		_bubble_sys._bubble_rise(tgt["pos"] + Vector2(randf_range(-14.0, 14.0), 0.0))
	# 线条普攻·素描: 施法只发墨弹飞(_do_basic远程弹道), 墨线+墨溅改到子弹命中瞬间才显(用户2026-07-15: 原在施法瞬间显=没等子弹到)→见 _on_basic_hit "line" 分支
	if u["id"] == "crystal":   # 水晶刺(近战·2026-07-15提质): 冰蓝碎晶突刺戳向目标
		var _xd: Vector2 = tgt["pos"] - u["pos"]
		if _xd.length() < 1.0: _xd = Vector2.RIGHT
		_xd = _xd.normalized()
		var _xtex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
		if _xtex != null:
			var _xs := Sprite3D.new()
			_xs.texture = _xtex
			_xs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			_xs.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			_xs.axis = Vector3.AXIS_Y
			_xs.pixel_size = (34.0 * WS) / float(maxi(1, _xtex.get_height()))
			_xs.position = _world_pos(u["pos"] + _xd * 30.0, 0.8)
			_xs.rotation = Vector3(0.0, -atan2(_xd.y, _xd.x) - PI * 0.5, 0.0)   # 尖端朝目标
			_world.add_child(_xs)
			var _xt := _reg_tween()
			_xt.tween_property(_xs, "position", _world_pos(u["pos"] + _xd * 62.0, 0.8), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 突刺
			_xt.tween_property(_xs, "modulate:a", 0.0, 0.1)
			_xt.tween_callback(_xs.queue_free)
	var spec: Dictionary = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	if u["id"] == "lava" and u.get("lava_pierce_next", false):         # 技三·穿透普攻: 下一发熔岩弹变贯穿全场
		u["lava_pierce_next"] = false
		_lava_sys._lava_pierce_bolt(u, tgt); _on_basic_hit(u, tgt)
		return
	if u["id"] == "lava" and u.get("volcano", false):                  # 火山形态: 烈焰重击式平A (单段重击; 用户2026-07-15: 1.6A→1A+3%自身maxHp魔法·血越厚锤越疼)
		spec = {"magic": 1.0, "selfhp": 0.03, "hits": 1, "rider": "burn", "burnScale": 0.07}   # 灼烧0.07A/锤(用户2026-07-15·与小形态一致; 原走默认0.67A偏高)
	_do_basic(u, tgt, spec)
	if u["melee"]:
		_on_basic_hit(u, tgt)   # 近战命中即时; 远程→弹道命中时触发(审判等与裁决同帧, 数字按规矩同时跳)
	# (原: 无条件 _on_basic_hit 被动钩子 (竹叶强化/墨迹/结晶/斩杀/审判/多重/彩虹附色 等) — 改 _do_basic 时漏调, 已补

func _big_bear_charge_and_spawn(u: Dictionary, si: int) -> void:   # 满层: 携带者蓄力(金光聚1.2s)→召大熊(与末只小熊错开)
	var glow := Sprite3D.new()
	glow.texture = VfxTex._make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glow.shaded = false; glow.transparent = true
	glow.modulate = Color(1.0, 0.82, 0.4, 0.0); glow.pixel_size = 0.02
	glow.position = _world_pos(u["pos"], 1.2)
	_world.add_child(glow)
	_vfx._float_text(u["pos"] + Vector2(0, -70), "大熊蓄力...", Color("#ffd166"))
	for k in range(7):   # 蓄力: 金块从脚下环绕依次破土冒起(聚土成熊)
		var ca: float = float(k) * TAU / 7.0
		var ctw := _reg_tween()
		ctw.tween_interval(float(k) * 0.14)
		ctw.tween_callback(_gold_chunk_erupt.bind(u["pos"] + Vector2(cos(ca), sin(ca)) * randf_range(40.0, 62.0)))
	var gt := _reg_tween()
	gt.tween_property(glow, "modulate:a", 0.95, 1.0)
	gt.parallel().tween_property(glow, "scale", Vector3(3.2, 3.2, 3.2), 1.2)
	await _wait_sim(1.2)
	if not is_instance_valid(self): return
	if is_instance_valid(glow): glow.queue_free()
	var stt: Dictionary = u.get("eq_state", {}).get("p2eq_034", {})
	stt["bear_done"] = true
	# ★用户 2026-07-30 加强大熊:
	#   · 攻速 0.5 → 0.7 次/秒  → atk_interval = 1/0.7 = 1.4286(原来 2.0)
	#     ★他先问"代码上是不是 0.5, 还是文案不对" —— 实测代码就是 2.0 秒 = 0.5 次/秒, 文案没错。
	#   · 最大生命 650/1100/10000 → 1600/3000/15000
	#   · 双抗 20 → 70(护甲与魔抗各 70)
	#   ★攻击力用户没提 → 不动(70/120/2000)。
	var bear = _spawn._spawn_summon(u, "bear", [1600.0, 3000.0, 15000.0][si], [70.0, 120.0, 2000.0][si], {"label": "大熊", "spr_id": "doll-bear", "col_size": 48.0, "hp_w": 36.0, "melee": true, "atk_interval": 1.0 / 0.7, "atk_range": 70.0})
	if bear != null:
		bear["eq_state"] = {}; bear["equips"] = []
		bear["base_def"] = 70.0; bear["def"] = 70.0
		bear["base_mr"] = 70.0; bear["mr"] = 70.0        # 双抗 20 → 70(用户2026-07-30)
		bear["is_big_bear"] = true; bear["bear_stacks"] = 0; bear["bear_star"] = si
		if OS.has_environment("EQDEMO_FAST"): bear["atk_interval"] = 0.6   # FAST=快速攒层看波
	_skill_ring(u["pos"], Color(1.0, 0.82, 0.4, 0.6), 90.0); _shake(JUICE_SHAKE_BIG)

func _bear_claw_fx(pos2d: Vector2) -> void:   # 熊爪拍击命中: 三道金爪痕(斜)一闪 + 尘爆, 卖出拍击感
	_vfx._impact_particles(pos2d, 0.3)
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

func _thunder_bolt(u: Dictionary) -> void:
	if not u.get("alive", false): return
	var es := _targeting._pick_enemies_of(u)
	if es.is_empty(): return
	var o = es[_battle_rng.randi() % es.size()]
	_lightning_sys._lightning_strike(o["pos"], Color("#8fd4ff"), 4.6)   # 大雷(中心≈2.2=飘字高度)
	var tw := _reg_tween()                             # 伤害在闪电动画中段(~0.25s)跳=落在雷中间
	tw.tween_interval(0.25)
	tw.tween_callback(_thunder_hit.bind(u, o))

func _thunder_hit(u: Dictionary, o: Dictionary) -> void:
	if not (u.get("alive", false) and o.get("alive", false)): return
	_damage._apply_damage_from(u, o, int(u["atk"]), Color("#cfefff"), 0.0, true, true)   # 1×ATK真实伤害(白字,飘在2.2=雷中间)

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

func _unfollow_vfx(spr) -> void:
	for i in range(_follow_vfx.size() - 1, -1, -1):
		if _follow_vfx[i].get("spr", null) == spr:
			_follow_vfx.remove_at(i)

func _ang_in(prev: float, cur: float, t: float) -> bool:
	var _guard := 0                         # 防卡死(用户2026-07-18): prev 若为 inf/极大(角度计算异常)→t<prev恒真=死循环; 64次封顶兜底
	while t < prev and _guard < 64:
		t += TAU
		_guard += 1
	return t > prev and t <= cur

# ── 卡死猎手(STRESS env): 加速无头循环对局 + 看门狗线程 ──
func _stress_pre() -> void:   # STRESS: 开局前轮换左队(全28龟)增加覆盖; _stress_n 在此累加(先于_stress_start)
	_stress_n += 1
	if GameState == null: return
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str((p as Dictionary).get("id", "basic")))
	if ids.size() < 3: return
	var pick: Array = []
	for k in range(3):
		pick.append(str(ids[(_stress_n * 3 + k) % ids.size()]))
	GameState.dual_active = true
	GameState.dual_lineup = {}    # 按新leaders重建左队布阵(get_dual_lineup检测leaders变→自动重建)
	GameState.season_leaders = pick
	# 给左队3龟各随机3件装备(轮换·覆盖装备触发路径=飞镖/齿轮/等复杂effect·卡死高发区)
	var eqids: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			eqids.append(str((e as Dictionary)["id"]))
	var pe := {}
	if eqids.size() > 0:
		for pi in range(pick.size()):
			var el: Array = []
			for j in range(3):
				el.append({"id": str(eqids[(_stress_n * 11 + pi * 3 + j) % eqids.size()]), "star": 1 + (_stress_n + j) % 3})
			pe[str(pick[pi])] = el
	GameState.persistent_equipped = pe

# ══════════════════════════════════════════════════════════════
# §AUDIT 自动巡检 (AUDIT=1) — 每秒采样一次全场, 逮"人眼要打几十局才偶尔撞见一次"的异常.
#
# 卡死猎手(STRESS)只管主循环冻没冻; 这里管【逻辑上说不通的状态】: 血超上限/NaN/负属性/
# 永远浮空/永远眩晕/飞出场外/弹道堆积/特效节点泄漏/单发伤害离谱/整局没参战。
# 每类只留首次样本 + 计数, 不刷屏。配合 STRESS 轮换28龟+注入装备跑多局 = 覆盖面比手打宽得多。
# ══════════════════════════════════════════════════════════════
var _audit := false
var _audit_next := 0.0
var _audit_hits: Dictionary = {}     # key -> {n:int, first:String}


func _audit_flag(key: String, detail: String) -> void:
	var h: Dictionary = _audit_hits.get(key, {"n": 0, "first": ""})
	h["n"] = int(h["n"]) + 1
	if str(h["first"]) == "":
		h["first"] = "battle#%d t=%.1f  %s" % [_stress_n, _t, detail]
	_audit_hits[key] = h

func _audit_tick() -> void:
	for u in _units:
		if not u.get("alive", false):
			continue
		var nm := str(u.get("name", u.get("id", "?")))
		var hp := float(u.get("hp", 0.0))
		var mx := float(u.get("maxHp", 1.0))
		if is_nan(hp) or is_inf(hp) or is_nan(mx) or is_inf(mx):
			_audit_flag("hp_nan", "%s hp=%s maxHp=%s" % [nm, str(hp), str(mx)])
		elif hp > mx + 1.0:
			_audit_flag("hp_over_max", "%s %.0f/%.0f (治疗/加血没夹上限)" % [nm, hp, mx])
		for k in ["atk", "def", "mr"]:
			var v := float(u.get(k, 0.0))
			if v < 0.0 or is_nan(v):
				_audit_flag("stat_negative", "%s %s=%s" % [nm, k, str(v)])
		# 浮空/眩晕卡死: 连续超时长仍未落地/未解控
		if u.get("airborne", false):
			u["_ad_air"] = float(u.get("_ad_air", 0.0)) + 1.0
			if float(u["_ad_air"]) > 6.0:
				_audit_flag("airborne_stuck", "%s 连续浮空 %.0fs" % [nm, float(u["_ad_air"])])
		else:
			u["_ad_air"] = 0.0
		if float(u.get("stun_until", 0.0)) > _t:
			if float(u.get("_ad_stun", 0.0)) <= 0.0:
				u["_ad_stun_n0"] = int(u.get("_stun_n", 0))   # 本段起点的施加次数, 用来算窗口内被上了几次控
			u["_ad_stun"] = float(u.get("_ad_stun", 0.0)) + 1.0
			if float(u["_ad_stun"]) > 10.0:
				# 【观测项, 不是缺陷】用户2026-07-19 拍板不加控制递减(DR) → 控制链锁死是已知且接受的行为。
				# 保留只为看有没有异常长的锁, 不要当 bug 去修。见 docs/design/实时版-系统机制权威.md §8
				_audit_flag("观测:stun_chain", "%s 被控锁 %.0fs(采样) 期间共被上控 %d 次  剩余=%.1f 最后来源=%s 全场来源=%s" % [
					nm, float(u["_ad_stun"]), int(u.get("_stun_n", 0)) - int(u.get("_ad_stun_n0", 0)),
					float(u.get("stun_until", 0.0)) - _t,
					str(u.get("_stun_src", "?")), str(u.get("_stun_chain", {}))])
		else:
			u["_ad_stun"] = 0.0
		# 属性失控: 有些成长类装备(哑铃每8s+最大生命/齿轮/锻炼层)没有上限, 长局里会滚成天文数字.
		# 记下首次采样时的基线, 之后看倍数 —— 这类问题不会报错也不会卡死, 只会让对局变得莫名其妙。
		# 基线必须等单位【稳定】后再采, 否则测的是出生过程不是成长:
		#   赛博机甲有 5 秒组装爬坡(atk 从 0 lerp 到设定值), 期间任何一帧当基线都会算出几倍"增长"。
		#   光加"atk>5"的门槛治不好 —— 爬坡会穿过任意门槛(先后误报过 1→10 和 12→72 两次)。
		#   改为: 连续看到该单位 6 次采样(≈6s, 覆盖组装/召唤的出生动画)之后才取基线。
		u["_ad_seen"] = int(u.get("_ad_seen", 0)) + 1
		if not u.has("_ad_b_hp") and int(u["_ad_seen"]) >= 6 and mx > 50.0 and not u.get("_assembling", false):
			u["_ad_b_hp"] = mx
			u["_ad_b_atk"] = maxf(1.0, float(u.get("atk", 0.0)))
		var b_hp: float = float(u.get("_ad_b_hp", mx))
		var b_atk: float = float(u.get("_ad_b_atk", 1.0))
		if b_hp > 1.0 and mx > b_hp * 5.0:
			_audit_flag("maxhp_runaway", "%s 最大生命 %.0f → %.0f (%.1f×)" % [nm, b_hp, mx, mx / b_hp])
		if b_atk > 1.0 and float(u.get("atk", 0.0)) > b_atk * 5.0:
			_audit_flag("atk_runaway", "%s 攻击 %.0f → %.0f (%.1f×)" % [nm, b_atk, float(u.get("atk", 0.0)), float(u.get("atk", 0.0)) / b_atk])
		if float(u.get("shield", 0.0)) > mx * 3.0:
			_audit_flag("shield_runaway", "%s 护盾 %.0f = %.1f× 最大生命" % [nm, float(u.get("shield", 0.0)), float(u.get("shield", 0.0)) / maxf(1.0, mx)])
		var pos: Vector2 = u.get("pos", Vector2.ZERO)
		if absf(pos.x) > 6000.0 or absf(pos.y) > 6000.0 or is_nan(pos.x) or is_nan(pos.y):
			_audit_flag("out_of_arena", "%s pos=%s" % [nm, str(pos)])
	if _projectiles.size() > 400:
		_audit_flag("projectile_pileup", "弹道数=%d (可能没回收)" % _projectiles.size())
	if is_instance_valid(_world) and _world.get_child_count() > 1200:
		_audit_flag("world_node_leak", "_world 子节点=%d (特效没清)" % _world.get_child_count())

func _audit_report(tag: String) -> void:
	if not _audit:
		return
	if _audit_hits.is_empty():
		print("[AUDIT] %s — 无异常" % tag)
		return
	print("[AUDIT] %s — 命中 %d 类:" % [tag, _audit_hits.size()])
	for k in _audit_hits.keys():
		print("[AUDIT]   %-20s ×%-4d  首次: %s" % [k, int(_audit_hits[k]["n"]), str(_audit_hits[k]["first"])])

func _stress_start() -> void:
	_stress = true
	Engine.max_fps = 0          # 无头解帧率上限→尽快跑; delta仍钳制0.1s(逻辑不炸)
	Engine.time_scale = 5.0     # 5×加速(delta≈0.08·未撞0.1钳制·保持较细粒度)
	print("[STRESS] battle #%d begin  left=%s" % [_stress_n, str(GameState.season_leaders) if GameState != null else "?"])
	_wd_thread = Thread.new()
	_wd_thread.start(_stress_watchdog)

## ★节点被销毁时收掉看门狗线程。
## 原来 `_wd_thread` **只在 `_stress_reload()` 里 join**（一局打完才收），
## 而 `--quit-after` 如果落在【一局中途】，线程从没被 join → `Thread` 析构时它还在跑
## → "A Thread object is being destroyed without its completion having been realized"
## → 退出时 **Segmentation fault**。
## 实测: 一次压测正好停在 `battle #2 begin`（局中）就段错误了，另外三次落在两局之间就干净。
## ⚠ 这条只影响 STRESS 无头压测的【退出阶段】，不影响对局逻辑 —— 但它会让人误判成
##   "我刚改的东西把压测跑崩了"，所以补掉。
func _exit_tree() -> void:
	if _wd_thread != null:
		_stress = false                      # 让 while 循环自己退出(它每秒醒一次)
		if _wd_thread.is_started():
			_wd_thread.wait_to_finish()
		_wd_thread = null


func _stress_watchdog() -> void:   # 独立线程: 主循环>4s无心跳=冻死→打最后操作+崩溃退出(外层读日志FROZEN行定位)
	var last_hb := -1
	var stall := 0
	while _stress:
		OS.delay_msec(1000)
		if _hb == last_hb:
			stall += 1
			if stall >= 4:
				printerr("[STRESS] ★★★ MAIN LOOP FROZEN ★★★ battle#%d  battle_t=%.2f  last_op=%s  op2=%s  adf_ct=%d  burst_depth=%d  units=%d" % [_stress_n, _t, _dbg_op, _dbg_op2, _adf_ct, _burst_depth, _units.size()])
				OS.crash("STRESS frozen op=%s op2=%s adf=%d" % [_dbg_op, _dbg_op2, _adf_ct])
				return
		else:
			stall = 0
			last_hb = _hb

func _stress_reload() -> void:   # 一局结束(或超时)→停看门狗→重开下一局
	if not _stress: return
	_stress = false
	print("[STRESS] battle #%d done  t=%.1f  (over=%s)" % [_stress_n, _t, str(_over)])
	_audit_report("battle#%d" % _stress_n)
	if _wd_thread != null and _wd_thread.is_alive():
		_wd_thread.wait_to_finish()
	_wd_thread = null
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _turret_on_shot(tr: Dictionary, tgt) -> void:   # 058炮台每次普攻: 永久+护穿+2%暴击(到本场战斗结束) + 枪口闪
	var si: int = int(tr.get("_turret_si", 0))
	tr["armor_pen"] = float(tr.get("armor_pen", 0.0)) + [2.0, 2.0, 3.0][si]
	tr["crit"] = minf(1.0, float(tr.get("crit", 0.0)) + 0.02)
	if tgt is Dictionary:
		_muzzle_flash(tr["pos"], (tgt["pos"] - tr["pos"]), Color("#ff6a6a"))
	_skill_ring(tr["pos"], Color(1.0, 0.45, 0.42, 0.45), 34.0)

func _update_turret_line(tr) -> void:   # 058: 炮台↔当前锁定目标的细红线(每帧重绘跟随)
	if not (tr is Dictionary): return
	var im = tr.get("_turret_line", null)
	var target = tr.get("_sep_target", null)
	if not tr.get("alive", false) or not (target is Dictionary) or not target.get("alive", false):
		if is_instance_valid(im): im.visible = false
		return
	if not is_instance_valid(im):
		im = MeshInstance3D.new()
		im.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		mat.vertex_color_use_as_albedo = true
		im.material_override = mat
		_world.add_child(im)
		tr["_turret_line"] = im
	im.visible = true
	var imesh: ImmediateMesh = im.mesh
	var col := Color(1.0, 0.26, 0.26, 0.55 + 0.25 * sin(_t * 7.0))   # 细红线+呼吸
	var a := _world_pos(tr["pos"], 1.35)
	var b := _world_pos(target["pos"], 1.35)
	if (b - a).length() < 0.01: return
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, im.material_override)
	imesh.surface_set_color(col); imesh.surface_add_vertex(a)
	imesh.surface_set_color(col); imesh.surface_add_vertex(b)
	imesh.surface_end()

func _necro_burst(pos2d: Vector2, radius: float) -> void:
	_skill_ring(pos2d, Color(0.4, 1.0, 0.55, 0.7), radius * 0.55)
	_shake(0.08)
	var glow := VfxTex._make_fire_glow_tex()
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
	var tex := VfxTex._make_fire_glow_tex()
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
	var glow := VfxTex._make_fire_glow_tex()
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

const _EQ_CUSTOM_IV := {"p2eq_004": 6.0, "p2eq_048": 8.0, "p2eq_049": 8.0, "p2eq_050": 8.0, "p2eq_051": 8.0, "p2eq_053": 8.0, "p2eq_057": 8.0, "p2eq_022": 8.0, "p2eq_028": 6.0, "p2eq_030": 7.0, "p2eq_031": 8.0, "p2eq_037": 5.0, "p2eq_040": 6.0, "p2eq_042": 8.0, "p2eq_052": 4.0}
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

const SHOTGUN_PELLET_DEG := 2.5   # 霰弹贝古053: 相邻两颗弹珠的固定夹角(度) —— 发数越多扇面自然越宽

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
	rg.texture = VfxTex._make_ring_texture(Color(0.35, 0.85, 1.0, 1.0))
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

func _ebb_tide_fx(u: Dictionary, rising: bool) -> void:   # 041: 涨潮=水纹上涌+青环扩; 退潮=水纹下沉+环收
	var col := Color(0.36, 0.88, 0.82) if rising else Color(0.45, 0.62, 0.72)
	_skill_ring(u["pos"], Color(col.r, col.g, col.b, 0.7), 66.0)
	_splash_ring_bold(u["pos"], col, 120.0)      # 贴地潮环(no_depth_test·不被地板吞)
	var gt := VfxTex._make_fire_glow_tex()
	for k in range(11):
		var m := Sprite3D.new()
		m.texture = gt
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.shaded = false; m.transparent = true
		m.no_depth_test = true; m.render_priority = 4
		m.modulate = Color(col.r, col.g, col.b, 0.0)
		m.pixel_size = (randf_range(20.0, 40.0) * WS) / float(maxi(1, gt.get_height()))
		var ang: float = float(k) * TAU / 11.0 + randf_range(-0.25, 0.25)
		var off: Vector2 = Vector2(cos(ang), sin(ang)) * randf_range(28.0, 62.0)
		var h0: float = 0.08 if rising else 1.9
		var h1: float = 1.9 if rising else 0.08
		m.position = _world_pos(u["pos"] + off, h0)
		_world.add_child(m)
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(m, "modulate:a", 0.95, 0.13).set_delay(float(k) * 0.025)
		tw.tween_property(m, "position", _world_pos(u["pos"] + off, h1), 0.5).set_delay(float(k) * 0.03)
		tw.chain().tween_property(m, "modulate:a", 0.0, 0.22)
		tw.chain().tween_callback(m.queue_free)

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
	_damage._apply_damage_from(u, tgt, _resolve_dmg(u, float(dmg), tgt, false), Color("#c8ccd6"), 0.0, false, true)   # 用户2026-07-19: 原裸值不吃护甲
	_damage._knockback(u, tgt, 0.0, 1.0, 2.0)   # 砸中击退
	_skill_ring(tgt["pos"], Color(0.8, 0.82, 0.9, 0.6), 50.0); _shake(JUICE_SHAKE_HEAVY)

func _fuel_flask_step(pf: float, spr, from2d: Vector2, to2d: Vector2, peak: float) -> void:   # 火瓶飞行帧: 抛物线高度 + 翻滚 + 掉余烬
	if not is_instance_valid(spr): return
	var p2: Vector2 = from2d.lerp(to2d, pf)
	var h: float = lerpf(1.15, 0.55, pf) + peak * 4.0 * pf * (1.0 - pf)   # 4·p·(1-p)=标准抛物, 顶点在中段
	spr.position = _world_pos(p2, h)
	if _cam != null:   # 面向镜头 + 绕视线轴自转(投掷物无固定朝向, 翻滚即可, 不用wisp_dir)
		spr.global_transform.basis = _cam.global_transform.basis * Basis(Vector3(0, 0, 1), -pf * TAU * 2.2)
	if randf() < 0.5: _ember_drop(p2, h)

func _ember_drop(at2d: Vector2, h: float) -> void:   # 火瓶拖尾: 一粒余烬边落边淡
	var m := Sprite3D.new()
	m.texture = VfxTex._make_fire_glow_tex()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.shaded = false; m.transparent = true
	m.modulate = Color(1.0, 0.55, 0.18, 0.8)
	m.pixel_size = (randf_range(7.0, 13.0) * WS) / float(maxi(1, m.texture.get_height()))
	m.position = _world_pos(at2d, h)
	_world.add_child(m)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "position", _world_pos(at2d, maxf(0.06, h - 0.55)), 0.34)
	tw.tween_property(m, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(m.queue_free)

func _fuel_bottle_hit(spr: Sprite3D, u: Dictionary, t: Dictionary, si: int) -> void:
	if is_instance_valid(spr): spr.queue_free()
	if not t.get("alive", false): return
	_damage._apply_damage_from(u, t, [40, 60, 100][si], Color("#ff7a3c"), 0.0, true, true)   # 火瓶直接火伤(命中即出伤+同帧跳数字, 照028同费档)
	var tf: int = maxi(1, roundi([20, 35, 60][si] + [0.10, 0.15, 0.20][si] * u["atk"]))
	_damage._apply_dot_stacks(t, "burn", tf, u)
	t["true_fire_until"] = _t + 5.0
	_fuel_shatter_fx(t["pos"])

func _fuel_shatter_fx(at2d: Vector2) -> void:   # 碎裂: 地面燃烧圈 + 火焰四溅(各自小抛物落地)
	_splash_ring_bold(at2d, Color(1.0, 0.42, 0.10), 92.0)   # 醒目贴地火圈(no_depth_test·不被地板高度吞)
	_skill_ring(at2d, Color(1.0, 0.55, 0.18, 0.65), 58.0)
	_particle_burst(at2d)
	var gt := VfxTex._make_fire_glow_tex()
	for k in range(9):
		var m := Sprite3D.new()
		m.texture = gt
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.shaded = false; m.transparent = true
		m.modulate = Color(1.0, randf_range(0.42, 0.72), 0.14, 0.95)
		m.pixel_size = (randf_range(13.0, 26.0) * WS) / float(maxi(1, gt.get_height()))
		m.position = _world_pos(at2d, 0.3)
		_world.add_child(m)
		var ang: float = float(k) * TAU / 9.0 + randf_range(-0.28, 0.28)
		var dest: Vector2 = at2d + Vector2(cos(ang), sin(ang)) * randf_range(42.0, 98.0)
		var mtw := _reg_tween()
		mtw.tween_method(_fuel_splash_step.bind(m, at2d, dest), 0.0, 1.0, randf_range(0.30, 0.52))
		mtw.tween_callback(m.queue_free)

func _fuel_splash_step(pf: float, m, from2d: Vector2, dest: Vector2) -> void:   # 溅开的火焰: 小抛物飞出+淡出
	if not is_instance_valid(m): return
	m.position = _world_pos(from2d.lerp(dest, pf), 0.22 + 0.85 * pf * (1.0 - pf))
	m.modulate.a = lerpf(0.95, 0.0, pf)

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
	var tex := VfxTex._make_fire_glow_tex()
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

# 钻石坚不可摧: 持盾期常驻青色水晶六棱护罩(跟随单位), 盾破/到期→碎裂淡出. 与锁龟能同判据(diamond_fortify_until + shield>0).
func _update_diamond_barrier(u: Dictionary) -> void:
	var active: bool = _t < float(u.get("diamond_fortify_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0
	var spr = u.get("_dia_barrier_spr", null)
	var valid: bool = spr != null and is_instance_valid(spr)
	if active and not valid:
		var b := Sprite3D.new()
		b.texture = load("res://assets/sprites/vfx/fx-hex-bubble.png")
		b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.shaded = false; b.transparent = true
		b.modulate = Color(0.55, 0.85, 1.0, 0.5)                    # 钻石=青色水晶护罩(石头是金色·色区分)
		var tw := float(maxi(1, int(b.texture.get_width())))
		b.pixel_size = (150.0 * WS) / tw
		b.position = _world_pos(u["pos"], float(u.get("height", 0.0)) + 0.75)
		_world.add_child(b)
		var pt := create_tween().bind_node(b).set_loops()           # 呼吸脉动(绑节点→节点free自停)
		pt.tween_property(b, "modulate:a", 0.30, 0.55).set_trans(Tween.TRANS_SINE)
		pt.tween_property(b, "modulate:a", 0.52, 0.55).set_trans(Tween.TRANS_SINE)
		_follow_vfx.append({"spr": b, "unit": u, "h": 0.75})
		u["_dia_barrier_spr"] = b
		u["_dia_barrier_pulse"] = pt
	elif not active and valid:
		u["_dia_barrier_spr"] = null
		var pulse = u.get("_dia_barrier_pulse", null)               # 先杀脉动循环(否则和淡出抢 modulate:a)
		if pulse != null and is_instance_valid(pulse): pulse.kill()
		u["_dia_barrier_pulse"] = null
		var s2 = spr
		_burst_vfx("res://assets/sprites/vfx/diamond-impact.png", u["pos"], 92.0, float(u.get("height", 0.0)) + 0.5)   # 盾没了→水晶碎裂小爆
		var bt := create_tween(); bt.set_parallel(true)             # 护罩碎裂放大淡出(你就"知道盾消失了/龟能恢复")
		bt.tween_property(s2, "modulate:a", 0.0, 0.2)
		bt.tween_property(s2, "pixel_size", s2.pixel_size * 1.35, 0.2)
		bt.chain().tween_callback(s2.queue_free)

# 财神金盾: 持盾期常驻金色六棱护罩(跟随单位), 盾破/到期→碎裂淡出. 与锁龟能同判据(gold_shield_until + shield>0). 仿钻石护罩·金色区分.
func _update_gold_barrier(u: Dictionary) -> void:
	var active: bool = _t < float(u.get("gold_shield_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0
	var spr = u.get("_gold_barrier_spr", null)
	var valid: bool = spr != null and is_instance_valid(spr)
	if active and not valid:
		var b := Sprite3D.new()
		b.texture = load("res://assets/sprites/vfx/fx-hex-bubble.png")
		b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.shaded = false; b.transparent = true
		b.modulate = Color(1.0, 0.82, 0.28, 0.5)                    # 财神=金色护罩
		var tw := float(maxi(1, int(b.texture.get_width())))
		b.pixel_size = (150.0 * WS) / tw
		b.position = _world_pos(u["pos"], float(u.get("height", 0.0)) + 0.75)
		_world.add_child(b)
		var pt := create_tween().bind_node(b).set_loops()
		pt.tween_property(b, "modulate:a", 0.30, 0.55).set_trans(Tween.TRANS_SINE)
		pt.tween_property(b, "modulate:a", 0.55, 0.55).set_trans(Tween.TRANS_SINE)
		_follow_vfx.append({"spr": b, "unit": u, "h": 0.75})
		u["_gold_barrier_spr"] = b
		u["_gold_barrier_pulse"] = pt
	elif not active and valid:
		u["_gold_barrier_spr"] = null
		var pulse = u.get("_gold_barrier_pulse", null)
		if pulse != null and is_instance_valid(pulse): pulse.kill()
		u["_gold_barrier_pulse"] = null
		var s2 = spr
		_burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", u["pos"], 88.0, float(u.get("height", 0.0)) + 0.5)   # 盾没了→金币爆(你就知道盾消失/龟能恢复)
		var bt := create_tween(); bt.set_parallel(true)
		bt.tween_property(s2, "modulate:a", 0.0, 0.2)
		bt.tween_property(s2, "pixel_size", s2.pixel_size * 1.35, 0.2)
		bt.chain().tween_callback(s2.queue_free)


func _update_stun_vfx(u: Dictionary) -> void:
	var active: bool = _t < float(u.get("stun_until", 0.0))
	var arr: Array = u.get("_stun_spr", [])
	var have: bool = not arr.is_empty() and is_instance_valid(arr[0])
	if active and not have:
		var tex := VfxTex._make_star_texture()
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
		var tex := VfxTex._make_glow_texture()
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

func _mud_mark(pos2d: Vector2) -> void:
	var spr := Sprite3D.new()
	spr.texture = VfxTex._make_disc_texture()
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


func _update_barnacle_line(u: Dictionary, target) -> void:   # 守护贝母021: 携带者↔连接友军的持续绿色绑定线(每帧重绘跟随, 能量脉动α)
	var im = u.get("barnacle_line", null)
	if not (target is Dictionary) or not target.get("alive", false) or is_same(target, u) or not u.get("alive", false):   # is_same: 同上
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

func _weapon_slash(from2d: Vector2, to2d: Vector2, col: Color) -> void:   # 面向镜头的斜砍斩弧(用户选)+命中环
	var arc := Sprite3D.new()
	arc.texture = VfxTex._make_slash_texture(col)
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

var _flyslash_tex: ImageTexture = null

func _weapon_flyslash(src: Dictionary, tgt: Dictionary, dmg: int, col: Color) -> void:   # 锈蚀短剑p2eq_001(射程2000): 朝目标飞的新月剑气→wisp_dir令尖朝目标屏幕方向·命中(frac>=1)才结算伤(用户2026-07-19)
	if tgt == null: return
	if _flyslash_tex == null: _flyslash_tex = VfxTex._make_flyslash_texture(col)
	var start2d: Vector2 = src["pos"]
	_skill_ring(start2d, Color(col.r, col.g, col.b, 0.5), 24.0)   # 起手: 携带者剑处一抹白亮(蓄势)
	var p := Sprite3D.new()
	p.texture = _flyslash_tex
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # wisp_dir: 弹道循环每帧手动 camera_basis×roll → 尖朝目标屏幕方向(billboard会覆盖手动basis, 必须关)
	p.shaded = false; p.transparent = true
	p.modulate = col
	p.pixel_size = 0.055
	p.position = _world_pos(start2d, 1.0)
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": _world_pos(start2d, 1.0), "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 520.0, 0.8, 2.6),   # 飞行速度: 降60%后再减半(用户2026-07-19: /2600→/1040→/520)
		"flyslash": true, "wisp_dir": true, "o2d": start2d,
	})


func _blood_slash(from2d: Vector2, to2d: Vector2, delay: float) -> void:   # 饮血连斩: Undertale式红像素斩击(5帧×100ms)落敌身, 纯视觉
	var off := Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 10.0))
	var spr := Sprite3D.new()
	spr.texture = VfxTex._make_slash_sheet(Color("#ff2233"))
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




var _bladewall_tex: ImageTexture = null

var _shellhalf_tex: ImageTexture = null


var _coralspike_tex: ImageTexture = null

func _coral_burst(pos2d: Vector2) -> void:   # 珊瑚碎裂: 珊瑚橙中心闪 + 碎屑四溅
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
	var h := 0.7
	var core := Sprite3D.new()
	core.texture = _spark_tex
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
	core.modulate = Color(1.0, 0.56, 0.4, 0.95)
	core.position = _world_pos(pos2d, h)
	core.pixel_size = 0.02; core.scale = Vector3.ONE * 0.5
	_world.add_child(core)
	var twc := _reg_tween(); twc.set_parallel(true)
	twc.tween_property(core, "scale", Vector3.ONE * 1.5, 0.16)
	twc.tween_property(core, "modulate:a", 0.0, 0.2)
	twc.chain().tween_callback(core.queue_free)
	for i in range(6):
		var ang: float = TAU * float(i) / 6.0 + randf_range(-0.2, 0.2)
		var drop := Sprite3D.new()
		drop.texture = _spark_tex
		drop.billboard = BaseMaterial3D.BILLBOARD_ENABLED; drop.shaded = false; drop.transparent = true
		drop.modulate = Color(1.0, 0.5 + 0.2 * float(i % 2), 0.36, 0.95)
		drop.position = _world_pos(pos2d, h)
		drop.pixel_size = 0.011; drop.scale = Vector3.ONE * 0.5
		_world.add_child(drop)
		var to: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * randf_range(22.0, 46.0)
		var twd := _reg_tween(); twd.set_parallel(true)
		twd.tween_property(drop, "position", _world_pos(to, h * 0.4), 0.26).set_ease(Tween.EASE_OUT)
		twd.tween_property(drop, "modulate:a", 0.0, 0.26)
		twd.chain().tween_callback(drop.queue_free)

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
	glow.texture = VfxTex._make_fire_glow_tex()
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
	_vfx._impact_particles(origin, 0.0)
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
		for o in _targeting._enemies_of(u):
			if _arr_has_unit(hit_arr, o) or not o.get("alive", false): continue
			var proj: float = (o["pos"] - origin).dot(dir)
			if proj >= -40.0 and proj <= traveled + 30.0 and _on_line(origin, dir, o["pos"], 85.0):
				hit_arr.append(o)
				_damage._apply_damage_from(u, o, dmg, Color("#ffd27a"), 0.0, false, true)
				_damage._knockback(u, o, 0.0, 1.5, 0.0)          # 击飞 ~0.8s (vy×1.5), 无横推(vx/vz=0, 拉回交给_pull_airborne)
				_pull_airborne(o, origin, 70.0, 0.45)    # 拉回70码: 滞空(击飞态)期平滑滑向大熊(留24px不重叠)
				_gold_chunk_erupt(o["pos"])              # 命中点额外炸一簇
	u["_bear_voff"] = Vector3.ZERO
	u["_slam_manual"] = false
	u["no_move"] = false                              # 冲击波结束解锁, 大熊恢复正常走位

# 金币飞向财神 (聚宝盆·单位阵亡时"金币哗啦涌向财神龟"). 纯视觉·无伤害.
func _gold_fly_to(from2d: Vector2, tgt: Dictionary) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var path := "res://assets/sprites/ui/coin.png"
	if not ResourceLoader.exists(path):
		return
	var p := Sprite3D.new()
	p.texture = load(path)
	p.pixel_size = 0.045
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false; p.transparent = true
	p.position = _world_pos(from2d, 1.0)
	_world.add_child(p)
	var to_pos: Vector3 = _world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.6)
	var tw := _reg_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position", to_pos, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "scale", Vector3(0.4, 0.4, 0.4), 0.5).set_delay(0.28)
	tw.tween_property(p, "modulate:a", 0.0, 0.18).set_delay(0.34)
	tw.chain().tween_callback(p.queue_free)

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
		if u["id"] == "ice": _ice_sys._ice_gain_icicle(u)   # 冰柱层(用户2026-07-28): 每段普攻+1·上限20
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
				_damage._apply_damage_from(u, tgt, int(raw_t / half), Color("#ffffff"), 0.0, true)
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
				_damage._apply_damage_from(u, tgt, int(raw_t / vh), Color("#ffffff"), 0.0, true)   # 真实(穿减伤)
	# 普攻自愈 (×ATK·每次普攻一次·海盗弯刀0.2A·silent防高频刷绿字)
	var sh: float = float(spec.get("selfheal", 0.0))
	if sh > 0.0 and u.get("alive", false):
		_damage._heal(u, atk * sh, true)
	# 附带效果
	match str(spec.get("rider", "")):
		"burn":    _damage._apply_dot_stacks(tgt, "burn", (maxi(1, int(round(float(u["atk"]) * float(spec.get("burnScale", 0.0))))) if spec.has("burnScale") else _default_burn_stacks(u)), u)
		"atkdn":   _damage._buff(tgt, "atk", -0.15, true)
		"selfdef": _damage._buff(u, "def", 0.20, true)
		"bleed":   _damage._apply_dot_stacks(tgt, "bleed", (3 if _last_atk_crit else 2), u)   # 忍者斩击: 2层流血(本次暴击→3层·封板·读_resolve_dmg设的_last_atk_crit)
		"shrink":  _hiding_sys._hiding_shell_harden(u)                             # 缩头缩壳: 每击+1甲+1抗(永久)+0.1A盾
	# 特殊机制
	match str(spec.get("mech", "")):
		"splash":  _splash_adjacent(u, tgt, float(spec.get("splash", 0.25)))   # 相邻敌溅射

# 一段普攻伤害落地 (近战直击+前冲 / 远程发弹)
func _emit_basic(u: Dictionary, tgt: Dictionary, dmg: int, col: Color, i: int) -> void:
	if dmg <= 0:
		return
	# 骰子·命运骰子(用户2026-07-28): 释放后【首次攻击】附带50%生命偷取, 打完即消费。
	# ★走 _apply_damage_from 的 extra_ls 参数 —— 那是本项目既有的"本次伤害额外吸血"通道
	#   (孤注一掷的30%吸血就走它)。不要在 _on_basic_hit 里事后按伤害值回血: 那里拿不到本次伤害数,
	#   我第一版就是编了个不存在的 _last_dmg_dealt。
	var _ls: float = 0.0
	if u.get("dice_fate_ls", false):
		_ls = DiceSystem.FATE_LIFESTEAL
		u["dice_fate_ls"] = false
		_vfx._float_text(u["pos"] + Vector2(0, -58), "命运吸血!", Color("#ff6b6b"))
	if u["melee"]:
		_damage._apply_basic_hit_from(u, tgt, dmg, col, _ls)
		if i == 0:
			_vfx._flash(tgt); _melee_lunge(u, tgt)
	else:
		_ballistics._fire_bolt_from(u, tgt, dmg, col, null, true)   # 普攻弹道: 命中时触发on_basic_hit

# 伤害减免+暴击 (与 _atk_dmg 同口径, 但吃"已算好的原始伤害"而非 scale)
func _mitigate(u: Dictionary, raw: float, tgt: Dictionary, magic: bool) -> int:
	return _resolve_dmg(u, raw, tgt, magic)

# 相邻溅射 (龟壳): 主目标附近敌受 frac 溅射; 若无相邻, 不额外 (主伤已结算)
func _splash_adjacent(u: Dictionary, tgt: Dictionary, frac: float) -> void:
	for o in _targeting._enemies_of(u):
		if is_same(o, tgt) or not o["alive"]:
			continue
		if (o["pos"] - tgt["pos"]).length() <= 90.0:
			_damage._apply_basic_hit_from(u, o, _mitigate(u, u["atk"] * 0.6 * frac, o, false), Color("#cfd8e8"))
	# 普攻 on-hit 被动钩子 (墨迹/电击/结晶叠层 + 猎杀斩杀 等)
	_on_basic_hit(u, tgt)

# 龟壳·龟壳打击(用户改造): 1ATK单段, 物理↔真实逐攻交替(本次真→下次物→…), 主目标120px内其他敌溅射50%(同类型)
const SHELL_SPLASH_RADIUS := 120.0
const PHX_CONE_HALF_DEG := 35.0     # 凤凰喷火扇形半角(全70°)
const PHX_FLAME_MAG_COEF := 0.2      # 每0.5s tick 魔法系数 ×ATK
const PHX_FLAME_BURN_COEF := 0.04     # 每0.5s tick 灼烧层系数 ×ATK (用户2026-07-28削弱: 0.07→0.04) ★T3实装默认(从熔岩龟抄来). 用户2026-06-30那句"每次普攻加灼烧层0.07ATK"是【对熔岩龟说的】(上文在谈熔岩攻速0.85), 凤凰这里用户原话写的是"每0.5秒造成？魔法伤害并施加？灼烧层"=没给数 → 见附录A

func _spawn_burn_ember(u: Dictionary) -> void:
	var pos2d: Vector2 = u["pos"] + Vector2(_juice_rng.randf_range(-14.0, 14.0), _juice_rng.randf_range(-4.0, 8.0))
	var spr := Sprite3D.new()
	spr.texture = VfxTex._make_fire_glow_tex()
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

func _spawn_poison_bubble(u: Dictionary) -> void:   # 中毒持续视觉(照灼烧余烬): 毒绿泡边升边胀淡出=一眼可辨"中毒"
	var pos2d: Vector2 = u["pos"] + Vector2(_juice_rng.randf_range(-16.0, 16.0), _juice_rng.randf_range(-2.0, 10.0))
	var spr := Sprite3D.new()
	spr.texture = VfxTex._make_fire_glow_tex()   # 软圆辉光当毒泡
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false; spr.transparent = true
	spr.pixel_size = 0.0068   # 大而明显(用户2026-07-14"毒buff再大一点")
	spr.modulate = Color(0.62, 0.98, 0.18, 0.98)   # 亮毒绿(偏黄绿·刻意区分治疗纯绿)
	spr.scale = Vector3(0.75, 0.75, 0.75)
	var h0: float = 0.4
	spr.position = _world_pos(pos2d, h0)
	_world.add_child(spr)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(spr, "position", _world_pos(pos2d, h0 + 0.85), 0.7)   # 缓升(毒气上飘·升更高)
	tw.tween_property(spr, "scale", Vector3(1.5, 1.5, 1.5), 0.7)            # 边升边胀(大泡)
	tw.tween_property(spr, "modulate", Color(0.45, 0.78, 0.12, 0.0), 0.7)
	tw.chain().tween_callback(spr.queue_free)

const PHX_FLIGHT_T := 0.3   # 火从嘴飞到锥远端的时间(秒): 历史回放窗口(停喷/转向的残焰按此飞完)

func _phx_hist_sample(hist: Array, tq: float) -> Array:   # 采样喷射历史→[角,开](线性插值·lerp_angle)
	if hist.is_empty(): return [0.0, 0.0]
	if tq <= float(hist[0][0]): return [float(hist[0][1]), 0.0]   # 史前=没喷(起喷火锋才会从嘴真实推进到远端·用户2026-07-15"开始喷火同理")
	for k in range(hist.size() - 1, -1, -1):
		if float(hist[k][0]) <= tq:
			if k == hist.size() - 1: return [float(hist[k][1]), float(hist[k][2])]
			var a: Array = hist[k]
			var b: Array = hist[k + 1]
			var f: float = clampf((tq - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0])), 0.0, 1.0)
			return [lerp_angle(float(a[1]), float(b[1]), f), lerpf(float(a[2]), float(b[2]), f)]
	return [float(hist[0][1]), float(hist[0][2])]

func _phx_fan_pt(mouth: Vector2, center_ang: float, half: float, rng: float, r: float, f: float) -> Vector2:   # 扇形上(径向r,角向f)的2D点(环各自的历史中心角→弯流)
	var aa: float = center_ang - half + 2.0 * half * f
	return mouth + Vector2(cos(aa), sin(aa)) * (rng * r)

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
	spr.texture = VfxTex._make_fire_glow_tex()
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

func _barrage_strike(pos2d: Vector2) -> void:   # 雷暴专属落雷(闪电龟自有lightning-0竖直落雷+lightning-3电爆; 用户2026-07-15强调: 区别于被动8层引爆的common-lightning-strike)
	var tex := load("res://assets/sprites/skills/lightning-0.png")
	if tex != null:
		var world_h := 4.4                            # 落雷加高(从高空风暴云延伸下来·2026-07-15)
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.pixel_size = world_h / float(maxi(1, tex.get_height()))
		spr.position = _world_pos(pos2d, world_h * 0.5)   # 中心抬到半高→底部炸裂贴地·顶端够到风暴云
		spr.modulate = Color(0.9, 0.96, 1.0, 0.0)
		_world.add_child(spr)
		var tw := _reg_tween()
		tw.tween_property(spr, "modulate:a", 1.0, 0.04)
		tw.tween_interval(0.05)
		tw.tween_property(spr, "modulate:a", 0.0, 0.18)
		tw.tween_callback(spr.queue_free)
	var btex := load("res://assets/sprites/skills/lightning-3.png")
	if btex != null:
		var burst := Sprite3D.new()
		burst.texture = btex
		burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		burst.shaded = false
		burst.transparent = true
		burst.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		burst.pixel_size = 0.42 / float(maxi(1, btex.get_height()))
		burst.position = _world_pos(pos2d, 0.4)
		burst.modulate = Color(1, 1, 1, 0.0)
		_world.add_child(burst)
		var tb := _reg_tween()
		tb.tween_property(burst, "modulate:a", 1.0, 0.05)
		tb.parallel().tween_property(burst, "scale", Vector3(2.4, 2.4, 2.4), 0.22)
		tb.tween_property(burst, "modulate:a", 0.0, 0.14)
		tb.tween_callback(burst.queue_free)

func _barrage_bolt(u: Dictionary, cloud_h: float) -> void:   # 雷暴单道(用户2026-07-15重做: 水平弧→天降竖直落雷·闪电龟自有素材)
	var es := _targeting._pick_enemies_of(u)
	if es.is_empty():
		return
	var e = es[_juice_rng.randi() % es.size()]
	if not e.get("alive", false):
		return
	_barrage_strike(e["pos"])   # 闪电龟自有lightning-0落雷(非被动的common-lightning-strike)
	_vfx._hit_spark(e)
	_shake(0.028)
	_damage._apply_damage_from(u, e, _atk_dmg(u, 3.0 / 20.0, e, true), Color("#7ee8ff"))
	_add_stack(e, "electric", 1, 8)

func _barrage_cloud_fade(cloud: Sprite3D) -> void:
	if not is_instance_valid(cloud):
		return
	var tw := _reg_tween()
	tw.tween_property(cloud, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cloud.queue_free)


## ★★2026-08-07 修(同族第三处): 这里把外部算好的帧号【原样】写进去,
##   表一换(帧数变少)就越界刷 `Index p_frame = N is out of bounds`。
##   前两处是忍者冲刺(写死 8~10 帧)与玩偶熊换图(用 hframes 判、引擎按 hframes×vframes 校验)。
##   ⇒ 统一按【贴图当下的真实总帧数】钳制。
func _lstrike_frame(spr: Sprite3D, f: int) -> void:
	if is_instance_valid(spr):
		spr.frame = clampi(f, 0, maxi(0, int(spr.hframes) * int(spr.vframes) - 1))

func _resolve_dmg(u: Dictionary, base: float, tgt: Dictionary, magic: bool) -> int:
	_last_dmg_type = "magic" if magic else "physical"   # 记类型供飘字取色
	var eff_crit: float = minf(float(u["crit"]), 1.0)
	_last_atk_crit = _battle_rng.randf() < eff_crit
	if _last_atk_crit:
		base *= DamageMath.crit_multiplier(float(u["crit"]), float(u["crit_dmg"]))   # 暴击率溢出100%每1%→1.5%暴伤
	var resist: float
	if magic:
		resist = DamageMath.effective_resist(float(tgt["mr"]), float(u.get("magic_pen_pct", 0.0)), float(u.get("magic_pen", 0.0)))
	else:
		var tdef: float = float(tgt["def"]) * (WHISTLE_SHRED_MULT if _t < float(tgt.get("def_shred_until", 0.0)) else 1.0)   # 削甲通道(口哨灵体小龟气波 -30%护甲·用户2026-07-23)
		resist = DamageMath.effective_resist(tdef, float(u.get("armor_pen_pct", 0.0)), float(u.get("armor_pen", 0.0)))
	var mult: float = DamageMath.resist_multiplier(resist)
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
	var resist: float = DamageMath.effective_resist(float(tgt["def"]), float(u.get("armor_pen_pct", 0.0)), float(u.get("armor_pen", 0.0)))
	var mult: float = DamageMath.resist_multiplier(resist)
	var d: float = raw * mult
	d *= 1.0 + float(u.get("damage_amp", 0.0))
	d *= 1.0 - float(tgt.get("damage_reduction", 0.0))
	if _t < float(tgt.get("phase_until", 0.0)):
		d *= 0.1                                    # 虚化(幽灵): 受物理-90%
	return maxi(1, int(round(d)))

# 立绘前冲 (近战命中视觉) — billboard offset 微推再回 (朝镜头, 不用翻 facing)
# 近战命中踏步: 朝目标前冲再回. 走渲染追加偏移 _atk_voff(每帧render叠加, 见 _vfx._juice_decay), 不tween spr.position(会被逐帧render覆盖)
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
#  2D 接口对齐: _ballistics._fire_bolt_from(src, tgt, dmg, col, from). src 用于 lifesteal/统计/累积 (可 null).
#  col 用于飘字色 (不再区分 magic bool; 物/法分流由 _atk_dmg 时已算进 dmg).
# ============================================================================

const _PROJ_WAVE := {"angel": true}   # 这些龟普攻弹道用尖尖能量波(程序画), 缺则默认bolt
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
		# ★先归零: 走路循环可能停在第 6 帧, 而踢击表只有 5 帧 ⇒ 设 hframes 那一瞬就越界。
		bear.frame = 0
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
					_last_dmg_type = "physical"   # 小熊走路期全局类型会被别的伤害覆写→结算前复位(飘字色/统计分桶)
					_damage._apply_damage_from(u, tgt, dmg, Color("#ffb0c8"), 0.0, false, true)
					_damage._knockback(u, tgt, 60.0, 1.6, 1.9)   # 踢一脚: 上抛×1.6/横推×1.9
	# 小熊消失 (淡出)
	if is_instance_valid(bear):
		var tw := _reg_tween()
		tw.tween_property(bear, "modulate:a", 0.0, 0.2)
		tw.tween_callback(bear.queue_free)

## ★2026-08-03 加了 `gun_id` —— 枪羁绊【金弹】挂在这里。
##   五把枪(黄铜手铳/激光手枪/加特林/狙击/左轮)的齐射【共用这一个出口】,
##   所以金弹只需要在这里数一次, 不用去改五套各不相同的开火逻辑。
##   金弹规格(类型原生): 每把枪【射满 4/3/2 发】额外射出一发, 效果与原子弹完全相同
##   (伤害/流血/减甲/击杀连锁全继承), 并额外造成 60/80/100% 真实伤害; 金弹本身不计入计数。
##   ⇒ 实现: 复用同一个 fn(所以"效果完全相同"是天然的), 期间把 _golden_pct 标在单位上,
##     伤害管线读它加一段真伤。★不递归: 金弹那一发不再累加计数(下面 _gun_shot_ct 只在正常发数)。
## `muzzle`: 可选的**出膛点回调**(返回 Vector2 场地坐标)。
## ★★2026-08-08: 加这个参数是因为 `src` 一直在扛两个语义 ——
##   **结算归属**(伤害算谁的、金弹计数记谁头上 ⇒ 携带者, 对的) 和
##   **出膛点**(弹从哪儿射出来 ⇒ 应该是真正开火的那个东西, 错的)。
##   一个参数扛两个含义, 必然有一边错; 错的那边让**九把枪的金弹全从携带者身上射出去**。
##   ⇒ 出膛点独立成回调, 不传就退回携带者(他自己开的枪, 本来就该从他身上出)。
##   ⚠ 用回调不用定值: 开火的东西(小手枪/炮台/直升机/浮游炮)**自己会动**,
##     排队时记下的坐标到真正开火那一刻就过期了。
## `delay0`: 整批**统一推迟**多少秒。★用途: 让结算等演出到位 ——
##   080 的炸弹要飞 0.42 秒才落地, 而 `delay = k × interval` 在 count=1 时 k=0 ⇒ 延迟为 0,
##   于是"伤害+爆炸"发生在投弹那一瞬、炸弹还在天上。加这个参数让**落地 = 伤害 = 爆炸**。
func _queue_shots(count: int, interval: float, fn: Callable, src = null, gun_id: String = "",
		muzzle: Callable = Callable(), delay0: float = 0.0) -> void:
	var per := 0
	var gpct := 0.0
	if gun_id != "" and src is Dictionary:
		var tier: int = int(_synergy.tier_for(src, "枪"))
		if tier > 0:
			per = [4, 3, 2][clampi(tier - 1, 0, 2)]
			gpct = [0.60, 0.80, 1.00][clampi(tier - 1, 0, 2)]
	if not (src is Dictionary) or not src.has("_gun_shot_ct"):
		if src is Dictionary:
			src["_gun_shot_ct"] = {}
	for k in range(count):
		_pending_shots.append({"delay": delay0 + float(k) * interval, "fn": fn, "src": src})
		if per <= 0:
			continue
		var ct: Dictionary = src["_gun_shot_ct"]
		ct[gun_id] = int(ct.get(gun_id, 0)) + 1
		if int(ct[gun_id]) < per:
			continue
		ct[gun_id] = 0
		# 金弹紧跟在那一发之后(半个间隔), 复用同一个 fn ⇒ 效果完全继承
		# ★2026-08-07【金弹可辨】: 演出也只挂在这一处 —— 九把枪全从这个出口出去,
		#   往每件装备里各写一份就是"手抄的副本必然落后"。`arm/resolve` 是**快照差分**:
		#   开火前记一遍全场 hp+shield, 开火后掉了的就是这一发打中的 ⇒ 不必往
		#   `battle_damage` 这条最热的共用管线里加钩子。详见 golden_shot_vfx.gd 文件头。
		var gp := gpct
		_pending_shots.append({"delay": delay0 + float(k) * interval + interval * 0.5, "src": src,
			"fn": func() -> void:
				src["_golden_pct"] = gp
				_gold_vfx.arm(src, (muzzle.call() if muzzle.is_valid() else null))
				fn.call()
				_gold_vfx.resolve(gp)
				src["_golden_pct"] = 0.0})

# 枪口闪: 在 pos2d 沿 dir 前方一点爆一小簇火光(胸口高度), 表现开火
func _muzzle_flash(pos2d: Vector2, dir: Vector2, col: Color) -> void:
	var mp: Vector2 = pos2d + dir.normalized() * 26.0
	var sp := Sprite3D.new()
	if _spark_tex == null:
		_spark_tex = VfxTex._make_glow_texture()
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


func _spawn_eq_bolt(src: Dictionary, tgt: Dictionary, dmg: int, tex_path: String, col: Color, spin: bool = false, bleed: int = 0, psize: float = 0.032) -> void:
	if tgt == null: return
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	p.texture = load(tex_path)
	p.pixel_size = psize
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 手动basis: billboard会吃掉roll(001飞斩教训) → 原 billboard+rotation.z 是坏写法
	p.shaded = false; p.transparent = true
	p.modulate = col
	p.position = _world_pos(start2d, 1.0)
	_world.add_child(p)
	var pd: Dictionary = {
		"node": p, "from": _world_pos(start2d, 1.0), "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 520.0, 0.22, 1.1),   # 慢一半(用户"完全看不清")
		"eq_bolt": true, "eq_bleed": bleed,
	}
	if spin:
		pd["card_spin"] = true            # 飞镖056: 面向镜头+绕视线轴自转(方形贴图, 无需朝向修正)
	else:
		pd["wisp_dir"] = true             # 子弹/弩矢: 弹头朝目标屏幕方向(等距下不歪)
		pd["wisp_off"] = PI / 2.0         # bullet/crossbow-bolt 都是横向贴图(+X朝前)
	_projectiles.append(pd)

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



# ============================================================================
#  伤害应用 (1:1 复用 2D: 护盾吸收→HP; 闪避/吸血/统计/累积条/受伤被动; 击杀; 飘字)
# ============================================================================
# 无来源伤害 (DoT 层数结算等)
# ----------------------------------------------------------------------------
#  §MITIGATE — 受害者侧减伤(两条伤害路径共用, 2026-07-22)
#
#  ★为什么抽出来: `_damage._apply_damage`(DoT/真伤) 原本只有 30 行, `_damage._apply_damage_from`(普攻/技能)
#    有 205 行 —— 差的全是减伤与触发链。于是【所有百分比/固定减伤对 DOT 完全无效】:
#    钻石18% / 岩石之躯-30% / 嘲讽减伤 / 铁壁盾016 flat / 靶向器055+20% / 终极暴露蛋×5
#    统统挡不住流血中毒灼烧。玩家侧的感受是"我堆了一身减伤，还是被烧死"。
#    回合制权威 scripts/engine/damage.gd:176-213 的 DOT 是完整吃这些的, 实时版这条链丢了。
#
#  ★只放【受害者侧】的减伤。攻击者侧(暴击/护穿/增伤)不在这里 —— 它们两条路的口径不同:
#    普攻走 _resolve_dmg 预先算好, DOT 走 _damage._dot_after_resist。放进来会重复扣。
# ----------------------------------------------------------------------------
## is_self=true: 自损/自然衰减 —— 不吃【增伤类】修正。
##   ★否则暴露蛋的自损会被它自己的「×5承伤」放大成 25%/秒(设计是 5%/秒),
##     被靶向器标记的召唤物衰减也会平白快 20%。减伤类照吃(它们只会让自损更慢, 无害)。
func _mitigate_incoming(u: Dictionary, dmg: float, raw: bool, is_self: bool = false) -> float:
	var d := dmg
	if not is_self and _t < u.get("eq_marked_until", 0.0):
		d *= 1.2                                     # 靶向器055: 被标记目标受伤 +20%
	if not is_self and int(u.get("corrode_stacks", 0)) > 0:
		d *= BowSynergySystem.vuln_mult(u)           # 弓箭顶档【腐蚀叠层】: 每层受伤 +5%(最多 5 层)
	if not is_self and _t < float(u.get("stun_until", 0.0)):
		d *= _gadget_syn.brittle_mult(u)             # 奇械顶档【易碎】: 被冻结/眩晕的敌人受伤 +25%
	# ★2026-07-30(需求3 大师技能审核抓到的): 这两行原本是【硬编码字面量】1.25 / 1.2,
	#   而 HOOK_VULN_MULT 那个常量【在游戏代码里零读者】—— 它唯一的读者是门禁
	#   verify_trainer_desc, 拿它推出文案该写"+25%"。两个 1.25 只是碰巧相等:
	#   把常量改成 1.5, 门禁会要求文案写"+50%", 改完文案门禁就绿了, 而游戏里仍是 +25%
	#   —— 门禁会把【错误的文案判成正确的】。改成读常量后它才真是事实源。
	#   冰川那条连常量都没有, 一并补上 GLACIER_VULN_MULT(值不变, 纯口径修正)。
	if not is_self and _t < u.get("hook_vuln_until", 0.0):
		d *= HOOK_VULN_MULT                          # ★钩锁(点3): 被钩住4秒内受到伤害 +25%
	if not is_self and _t < u.get("glacier_vuln_until", 0.0):
		d *= GLACIER_VULN_MULT                       # ★冰川: 站冰川上受到伤害 +20%(用户2026-07-23)
	if not is_self and _t < u.get("hunt_until", 0.0):
		d *= HUNT_VULN                               # ★猎龟令: 被标记 15 秒内受到伤害 +15%(用户2026-07-28)
													 #   ——【必须加在这个唯一入口】, 不许在技能里自己乘:
													 #   两条伤害路径(_apply_damage / _apply_damage_from)都过这里,
													 #   在技能里乘只会覆盖其中一条。
	if not is_self and u.get("_egg_final", false):
		d *= 5.0                                     # 终极战场暴露蛋: ×5承伤(快速决胜)
	if u["id"] == "diamond" and not raw:
		d *= 0.82                                    # 钻石·结构减伤18%(真伤/穿透不减)
	if u["id"] == "stone" and u.get("stone_rockbody", false) and not raw:
		d *= (1.0 - 0.01 * float(mini(30, int(u.get("rock_layers", 0)))))   # 岩石之躯: 每层-1%, 上限30%
	if u["id"] == "stone" and _t < float(u.get("stone_dr_until", 0.0)) and not raw:
		d *= (1.0 - clampf(0.5 * float(u["def"]) * 0.01, 0.0, 0.5))         # 嘲讽期 (0.5×护甲)% 减免, 上限50%
	if not raw and float(u.get("flat_dr", 0.0)) > 0.0:
		d = maxf(0.0, d - float(u["flat_dr"]))       # 铁壁盾016: 每段固定减 X 点(护盾前)
	# ★训龟大师: 受到的【所有类型】伤害降为 1(用户2026-07-22 含真实伤害)。
	#   必须放在函数【最末尾】且【不看 raw】—— 上面每一项减伤都写着 `not raw`,
	#   放在中间或加 raw 判断都会让真伤原样打穿。两条伤害路径共用本函数, 所以一处即全覆盖。
	if _t < float(u.get("_tame_invuln_until", 0.0)):
		return 0.0                                   # ★驯服重生演出期(2.5秒)无敌(用户 2026-07-28 B7)
	if u.get("is_trainer", false):
		return minf(d, 1.0)
	# ★"受到的任何攻击(含真实伤害)降为 1" 的通用闸(用户2026-08-01 给亡灵骷髅 032 用)。
	#   与大师同一条口径、同一个位置 —— 放这儿是因为本函数是【两条伤害路径唯一的共用收口】,
	#   在别处拦只会拦住其中一条(CLAUDE.md §3.3 那类"只在某种伤害下出现的诡异行为")。
	#   用 flag 而不是判 id: 骷髅是召唤物, 将来还会有别的"血量即命数"单位。
	if u.get("_dmg_cap_one", false):
		return minf(d, 1.0)
	# ★2026-08-06 泛化成【带值】的封顶: 077 铜管手铳的小手枪要"受到的所有伤害(含真伤)降为 2 点,
	#   携带者阵亡后降为 5 点" —— 布尔版只能降到 1, 而这两个值还会在战斗中变(携带者一死就换)。
	#   ⚠ 为什么必须放在这里而不是让 077 自己在效果里补差额: 本函数是**两条伤害路径唯一的共用收口**
	#   (CLAUDE.md §3.3), 在别处拦就只拦得住其中一条; 而"含真伤"要求它在真伤也走的这条收口上生效。
	#   `_dmg_cap_one` 保留不动 —— 亡灵骷髅 032 用的是它, 语义是"命数式单位", 与带值封顶不是一回事。
	var _capv: float = float(u.get("_dmg_cap_val", 0.0))
	if _capv > 0.0:
		return minf(d, _capv)
	return d


func _redirect_damage(carrier: Dictionary, amt: float, dtype: String) -> void:
	# 守护贝母021 伤害转移: 友军受什么类型就转什么类型(物红/魔蓝/真白), 并在携带者头上跳数字(用户2026-07-19)
	# 注: amt 是友军【已经吃过自己抗性】之后的那一段, 这里不再吃携带者的抗性(否则同一发减两次伤=021凭空变强)。
	#     携带者的护盾照吸(与原_raw_lose行为一致)。
	if amt <= 0.0 or not carrier.get("alive", false):
		return
	if carrier["shield"] > 0.0:
		var ab := minf(carrier["shield"], amt)
		carrier["shield"] -= ab; amt -= ab
	var shown: int = maxi(1, int(round(amt)))
	_vfx._float_text(carrier["pos"] + Vector2(0, -40), str(shown), _VC.color_of(_VC.cls_for("damage", dtype, false)), false, "damage", dtype)
	if amt <= 0.0:
		return
	carrier["hp"] = maxf(0.0, carrier["hp"] - amt)
	if carrier["hp"] <= 0.0 and carrier["alive"]:
		_kill(carrier)
# ★_raw_lose 已删(2026-07-22): 它只有 8 行 —— 不进统计/不跳飘字/不过任何减伤/
#   没有组装期免疫闸/评审训练靶会被它打死。三个调用点(暴露蛋自损 / 糖果龟甜蜜吸取 /
#   召唤物自然衰减)已全部改走正规伤害路径, 用户 2026-07-22 拍板"三处全改, 要进受伤统计"。
#   若要加新的"扣血"逻辑, 用 _damage._apply_damage(..., is_self=true) 或 _damage._apply_damage_from。

func _dash_to(u: Dictionary, tgt: Dictionary, gap: float) -> void:
	var dir: Vector2 = (u["pos"] - tgt["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	u["pos"] = tgt["pos"] + dir * gap
	u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

func _kill(u: Dictionary, killer = null) -> void:
	if u.get("_dead_done", false):
		return   # 死亡已完整处理过→不重入(防死亡链重入无限递归卡死·用户2026-07-19卡死猎手: 053霰弹击杀 egg/minion 冻死)
	# 人头归属改写(用户2026-07-22): 被侵入者打死的人算侵入它的赛博龟, 赛博自己已死也照算。
	#   放在函数最前 → 后面所有用 killer 的地方(击杀数/on-kill装备/日志)一次性全对。
	killer = _credit_killer(killer)
	if u.get("_pdeath_demo", false) and killer is Dictionary and killer.get("alive", false) and not is_same(killer, u):   # 被动死亡钩索demo: 放钩索但不真死→复位血循环看(仅评审)
		var _gtar: Dictionary = killer   # demo: 抓【最远】的敌(展示钩索拉回距离·真实战斗是抓击杀者)
		var _fd := 0.0
		for _go in _targeting._enemies_of(u):
			if _go.get("alive", false):
				var _dd: float = u["pos"].distance_to(_go["pos"])
				if _dd > _fd: _fd = _dd; _gtar = _go
		_pirate_sys._pirate_death_grapple(u, _gtar)
		u["hp"] = float(u["maxHp"]) * 0.4
		return
	if u.get("_cydeath_demo", false):   # 赛博被动demo: 打死→浮游炮汇聚组装机甲演出, 本体复位血循环看(仅评审·场上无demo机甲才再组装防堆积)
		var _have_mech := false
		for _mo in _units:
			if _mo.get("alive", false) and _mo.get("is_summon", false) and str(_mo.get("summon_kind", "")) == "mech" and is_same(_mo.get("summon_owner", null), u):
				_have_mech = true; break
		if not _have_mech:
			_cyber_sys._cyber_assemble_mech(u)
		u["hp"] = float(u["maxHp"]) * 0.6
		return
	# ★驯服重生钩(训龟大师·用户 2026-07-28): 被驯服的敌人死亡时不真死, 以 30% 最大生命
	#   重生并【归顺我方】, 之后每秒损失 2% 最大生命。
	#   放在自带复活钩【之前】—— 驯服是外部强加的效果, 应当优先于目标自己的涅槃/圣光,
	#   否则凤凰被驯服后会先走自己的涅槃、归顺永远轮不上。
	if _trainer_sys._tame_try_revive(u):
		return
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为常驻一次, 1:1 2D
	# ★`get` 不是 `[]` —— 合成单位（门禁里手搓的、召唤物某些路径）不一定带这个键，
	#   直读会抛 `Invalid access to property or key 'reborn_used'`。
	#   ⚠ 这条错**不会让断言变红**（`verify_synergy_rest5` 一直是 ALL PASS），
	#     是 `run-tests.sh` 的致命报错正则把它捞出来的 —— CLAUDE.md §2 说的就是这种：
	#     只看退出码/断言的话，它能一直躺在那儿。
	if not bool(u.get("reborn_used", false)) and ((u["id"] == "angel" and u.get("_angel_revive", false)) or u["id"] == "phoenix" or u.get("_chest_revive", false)):
		u["reborn_used"] = true
		var pct: float = (PhoenixSystem.NIRVANA_ENH_HP_PCT if u.get("_enh_rebirth", false) else PhoenixSystem.NIRVANA_HP_PCT) if u["id"] == "phoenix" else 0.25   # 凤凰60/25%(用户2026-07-28 100/30→) · 天使圣光/宝箱凤凰雕像 25%
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		u["dot_stacks"] = {}
		_audio_sys._sfx_simple("rebirth")              # §AUDIO: 首死复活音 (天使圣光/凤凰涅槃, 低频不节流)
		_vfx._float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧 + 治疗削减5秒
			if u.get("_enh_rebirth", false):
				u["base_atk"] = u["base_atk"] * 1.2; _recalc_stats(u)   # 强化涅槃: 永久+20%攻击
			for o in _targeting._enemies_of(u):
				_damage._apply_dot_stacks(o, "burn", maxi(1, roundi(float(u["atk"]) * PhoenixSystem.NIRVANA_BURN_COEF)), u)   # ★凤凰专用系数, 不走全局 _default_burn_stacks(0.67) —— 那个熔岩龟也在用
				o["heal_reduce_until"] = _t + BUFF_SEC
				o["heal_reduce_pct"] = maxf(float(o.get("heal_reduce_pct", 0.0)), 0.5)
		return
	u["alive"] = false
	u["_dead_done"] = true                       # 标记死亡已处理(防重入·配合顶部 _dead_done 守卫)
	var _phx_fs = u.get("flame_sector", null)   # 凤凰持续喷火扇形(常驻MeshInstance3D·非_follow_vfx管理·死后不再tick)→死亡即清, 否则残留场上(用户2026-07-18"凤凰龟死后留下喷火特效")
	if is_instance_valid(_phx_fs):
		_phx_fs.queue_free()
	u["flame_sector"] = null; u["phx_hist"] = []
	if not u.get("is_summon", false) and not u.get("_isEgg", false):
		_log("[color=#ff9a5a]☠ %s[/color] 被击败" % _unit_name(u))   # 战斗日志: 只记主龟阵亡(召唤体/蛋不刷屏)
		if killer is Dictionary and killer.has("side"):
			killer["_st_kills"] = int(killer.get("_st_kills", 0)) + 1   # §STATS: 击杀数归凶手(击杀主龟才计)
	if u.get("_isEgg", false):   # 龟蛋: 碎裂动画(替代普通死亡淡出), 胜负记账走 _dl_sys._dl_flow_check
		_on_unit_death(u, killer)
		_vfx._play_egg_shatter(u)
		for _ek in ["shadow", "ring", "contact"]:
			var _en = u.get(_ek, null)
			if is_instance_valid(_en):
				var _etw := _reg_tween(); _etw.tween_property(_en, "modulate:a", 0.0, 0.4); _etw.tween_callback(_en.hide)
		return
	if killer != null and killer.get("alive", false):
		_equip_sys._eq_on_kill(killer, u)             # on-kill: 击杀者装备 (暴君之牙处决回血 等)
	_equip_sys._eq_on_death(u, killer)                # on-death: 阵亡者装备 (复活海螺变虫 / 齿轮折币 / 玩偶熊)
	_shield_syn.on_enemy_died(u)                      # 盾羁绊【收殓】: 最近的携带盾者获得死者 30% 最大生命的护盾
	_potion_syn.on_death(u)                           # 药水羁绊【猎获】: 死的是猎物 → 那一方全队攻击力永久 +22/38
	_spirit_syn.on_death(u)                           # 灵物羁绊【亡灵】: 友方阵亡 → 原地召唤亡魂(继承 20/38/65/100%)
	_on_unit_death(u, killer)
	for _egc in _units:   # 温泉蛋(036): 任意单位阵亡→持蛋者加进度(己方死+15/敌死+10)
		if _egc.get("has_egg", false) and _egc.get("alive", false):
			_equip_tick_sys._egg_add_progress(_egc, 15.0 if str(_egc.get("side", "")) == str(u.get("side", "")) else 10.0)
	# 有死亡帧的龟(basic/ghost/ninja)播 death 动画 → 影/环/血条立即淡, 立绘延后淡(让动画演完)
	_vfx._play_action(u, "death")
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
	# ★同 `reborn_used`：合成单位不一定带这个键，直读会抛错。
	#   （7065 行早就写成 `get` 了，这里漏了一处 —— 同一个坑的两半。）
	if is_instance_valid(u.get("bar_root", null)):
		u["bar_root"].visible = false

# (Phase4: 旧 tween 版 _vfx._flash 已移除, 改为状态驱动 _vfx._flash → 见 §JUICE; 与 squash/bob 统一从 base 重建)

# 飘字 (2D 接口对齐): 传像素 XZ 坐标 → 升到头顶世界点 → unproject 到屏幕 → UI overlay 上飘.
#   2D 版传 pos2d=u["pos"]+偏移(px); 这里把 y 偏移(px·往上)换算成 3D 高度抬升, 让"-64"这种头顶字落在头顶.
var _num_font: Font = null                  # #1 飘字像素数字字体 (m6x11, 跟回合制同款厚重描边)
func _make_num_label(text: String, col: Color, fsize: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _vfx._float_num_font())       # 像素厚字
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)           # 8向描边 (回合制同款, 深底浮字更清晰)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l

var _float_dmg_window: Dictionary = {}    # 伤害飘字按类型排行错开 (1:1 回合制 _vfx._float_row_offset)
var _float_nd_window: Dictionary = {}     # 非伤害(治疗/盾)紧凑堆叠
var _float_merge: Dictionary = {}         # 同目标+同类型+同帧伤害合并成一个数(奥恩式: 跳两者之和) key=posx_posy_type→{lbl,amount,t,crit}
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
	tw.tween_method(_bamboo_sys._bamboo_orb_step.bind(orb, from_pos, to_pos, nframes, [0]), 0.0, 1.0, 0.65)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if is_instance_valid(orb): orb.queue_free()
		_spawn_bamboo_burst(to_pos)
		if on_land.is_valid(): on_land.call())   # 绿球落到身上 → 回血+成长(用户: 到自己身上才吸收)

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
	tw.tween_method(_bamboo_sys._bamboo_burst_step.bind(b, nframes), 0.0, 1.0, 0.35)
	tw.tween_callback(b.queue_free)

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
	# ★同族钳制: `frames` 是调用方传的, 与贴图真实帧数无关 ⇒ 再与 hframes×vframes 取小
	t.tween_method(func(fr): spr.frame = clampi(int(fr), 0,
		mini(frames, maxi(1, int(spr.hframes) * int(spr.vframes))) - 1), 0.0, float(frames), dur)
	t.tween_callback(spr.queue_free)

## ── `_skill_ring` 的两条曲线 ────────────────────────────────────────────────
## ★2026-08-07 修的 bug(方案书 docs/plans/20260807-表现层方案书.md §1.3):
##   原来【尺寸和 alpha 走同一条 0.35 秒曲线】—— 环从 40% 扩到 100% 的**同时**
##   alpha 从 1 拉到 0 ⇒ **环放到最大的那一帧正好完全透明**, 肉眼只看得到 40~70% 那一段。
##   用户报的"083 潮汐细剑的叠层环 / 093 香火石 / 081 藤编圆盾 / 目标环都看不出来"根因就是它:
##   **不是做小了, 是画到最显眼的时候被自己抹掉了**。
##   ⇒ 拆成两条曲线: 【先长大(这一整段 alpha 保持峰值) → 长满【之后】才淡出】。
##   ⚠ 它是公共原语, 全仓 60+ 个调用点共用 —— 改的只有【时间轴】,
##     半径/颜色/峰值亮度一个都没动, 所以别的调用者只会"看得见了", 不会变形变色。
const RING_PS0 := 0.4          # 起始尺寸(占目标的比例)。环从这里扩到 100%
const RING_GROW_T := 0.26      # ①扩张段: 这一整段 alpha 保持峰值 ⇒ 长到最大那一帧【最亮】
const RING_FADE_T := 0.22      # ②淡出段: 长满之后才开始淡出(总时长 0.48s, 原来是 0.35s)
## 峰值 modulate alpha。★贴图 `_make_ring_texture` 自带 0.6 的 alpha 剖面且【被缓存、忽略入参】,
##   所以屏幕上的峰值 = 0.6 × 这个数; 入参 `col.a` 一直是没人读的 —— 这次不动它(动了就是全仓变暗)。
const RING_PEAK_A := 1.0

# 技能光圈: 地面上一个躺平的环, 扩散淡出 (2D 接口对齐 _skill_ring(pos, col, radius))
func _skill_ring(pos2d: Vector2, col: Color, radius: float) -> Sprite3D:
	var r := Sprite3D.new()
	r.texture = VfxTex._make_ring_texture(col)
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y          # 躺平贴地
	r.shaded = false
	r.transparent = true
	r.modulate = Color(col.r, col.g, col.b, RING_PEAK_A)
	r.position = _world_pos(pos2d, 0.05)
	# pixel_size 让环直径 ≈ radius(px) × WS(米/px); ring 贴图 96px 宽
	var target_ps: float = (radius * 2.0 * WS) / 96.0
	r.pixel_size = target_ps * RING_PS0
	r.set_meta("ring_target_ps", target_ps)   # 门禁/量尺拿它当分母(不重算一遍曲线)
	_world.add_child(r)
	var tw := _reg_tween()
	tw.set_parallel(true)
	# ①扩张段(0 → RING_GROW_T): 尺寸 40%→100%, 【alpha 同时保持在峰值】。
	#   那条等值的 alpha tween 不是废话 —— 它占住这一段时间, 让下面 chain() 的淡出
	#   真的排在"长满之后"; 少了它, chain() 会紧跟着尺寸那条一起排, 又变回同步淡出。
	tw.tween_property(r, "pixel_size", target_ps, RING_GROW_T) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", RING_PEAK_A, RING_GROW_T)
	# ②淡出段: 长满【之后】才开始, 所以"最大的那一帧"是最亮的一帧。
	tw.chain().tween_property(r, "modulate:a", 0.0, RING_FADE_T)
	tw.chain().tween_callback(r.queue_free)
	r.set_meta("ring_tw", tw)                 # 门禁 custom_step 手推这条 tween(无头 CI 下 tween 自走不稳)
	return r

func _splash_ring_bold(pos2d: Vector2, col: Color, radius: float) -> void:   # 醒目冲击环: 双层贴地环 + no_depth_test(恒画在地板/地形/立绘之上·不被高度吞·用户2026-07-19)
	var target_ps: float = (radius * 2.0 * WS) / 96.0
	for k in range(2):   # k0=主环(实) k1=外环(虚·略慢略大) → 双层更醒目
		var r := Sprite3D.new()
		r.texture = VfxTex._make_ring_texture(col)
		r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		r.axis = Vector3.AXIS_Y          # 躺平贴地
		r.shaded = false; r.transparent = true
		r.no_depth_test = true           # ★关深度测试: 贴地环恒在最上层, 地板/珊瑚高度盖不住
		r.render_priority = 6 + k
		r.modulate = Color(col.r, col.g, col.b, 1.0 if k == 0 else 0.5)
		r.position = _world_pos(pos2d, 0.12)
		r.pixel_size = target_ps * (0.28 if k == 0 else 0.14)
		_world.add_child(r)
		var dur: float = 0.4 + 0.12 * float(k)
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(r, "pixel_size", target_ps * (1.0 if k == 0 else 1.18), dur)
		tw.tween_property(r, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(r.queue_free)

var _venomfang_tex: ImageTexture = null

func _venom_splat(pos2d: Vector2) -> void:   # 蛇女毒液飞溅: 毒绿中心闪 + 紫绿液滴四溅
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
	var h := 0.7
	var core := Sprite3D.new()
	core.texture = _spark_tex
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED; core.shaded = false; core.transparent = true
	core.modulate = Color(0.72, 1.0, 0.36, 0.95)
	core.position = _world_pos(pos2d, h)
	core.pixel_size = 0.02; core.scale = Vector3.ONE * 0.5
	_world.add_child(core)
	var twc := _reg_tween(); twc.set_parallel(true)
	twc.tween_property(core, "scale", Vector3.ONE * 1.6, 0.16)
	twc.tween_property(core, "modulate:a", 0.0, 0.22)
	twc.chain().tween_callback(core.queue_free)
	for i in range(7):
		var ang := TAU * float(i) / 7.0 + randf_range(-0.25, 0.25)
		var drop := Sprite3D.new()
		drop.texture = _spark_tex
		drop.billboard = BaseMaterial3D.BILLBOARD_ENABLED; drop.shaded = false; drop.transparent = true
		drop.modulate = (Color(0.62, 1.0, 0.32, 0.95) if i % 2 == 0 else Color(0.80, 0.40, 1.0, 0.95))
		drop.position = _world_pos(pos2d, h)
		drop.pixel_size = 0.012; drop.scale = Vector3.ONE * 0.5
		_world.add_child(drop)
		var to: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * randf_range(26.0, 54.0)
		var twd := _reg_tween(); twd.set_parallel(true)
		twd.tween_property(drop, "position", _world_pos(to, h * 0.35), 0.28).set_ease(Tween.EASE_OUT)
		twd.tween_property(drop, "modulate:a", 0.0, 0.28)
		twd.chain().tween_callback(drop.queue_free)

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

func _surf_chain_shoot(from2d: Vector2, fromh: float, to2d: Vector2, col: Color) -> void:   # 从小将(空中)射铁链向目标: 端点快速伸长(射出感)→保持→淡出(用户2026-07-18"绳子从小将射向目标")
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.vertex_color_use_as_albedo = true
	im.material_override = mat
	_world.add_child(im)
	var a := _world_pos(from2d, fromh)
	var b := _world_pos(to2d, 0.8)
	var tw := _reg_tween()
	tw.tween_method(func(q: float) -> void:              # 伸长: 端点从小将→目标(射出)
		if not is_instance_valid(im): return
		imesh.clear_surfaces()
		imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		imesh.surface_add_vertex(a)
		imesh.surface_add_vertex(a.lerp(b, q))
		imesh.surface_end()
	, 0.0, 1.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.12)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(im.queue_free)

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

## 通用爆点 VFX。★★2026-08-02 补【横排帧动画识别】(用户:「龟蛋碎裂…那几个贴图还是啥序列图应该用错了」):
##   `_fly_vfx` 一直会按 nf=宽/高 自动识别横排帧, 而本函数【不识别】—— 于是横条序列图丢进来
##   会被当成一张画, 5 帧【并排同时显示】、横着摊开。实拍受害两处:
##     · boom-wave-anim.png (480×96 = 5 帧) —— 破蛋冲击波, 破一次蛋出现 5 个并排爆炸
##     · electric-zap.png   (480×96 = 5 帧) —— 赛博侵入的电流
##   两处都不是"调用方写错了", 是【同类助手函数行为不一致】造成的陷阱: 同样传一张横条图,
##   _fly_vfx 对、_burst_vfx 错, 调用方没理由知道这个区别。所以修在【助手函数】里, 不是修调用点。
func _burst_vfx(path: String, pos2d: Vector2, size_px: float, height: float = 0.4) -> void:
	var t: Texture2D = load(path)
	if t == null: return
	var b := Sprite3D.new()
	b.texture = t
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED; b.shaded = false; b.transparent = true
	# ★与 _fly_vfx 同一条判据: 宽是高的整数倍(≥2) → 横排帧动画
	var fh: int = maxi(1, t.get_height())
	var nf: int = 1
	if t.get_width() > fh and t.get_width() % fh == 0:
		nf = t.get_width() / fh
	if nf > 1:
		b.hframes = nf
		b.frame = 0
	b.pixel_size = (size_px * WS) / float(fh)
	b.position = _world_pos(pos2d, height)
	_world.add_child(b)
	var tw := _reg_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.12).from(Vector3.ONE * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if nf > 1:
		# 帧在"起势+停留"这 0.26 秒里播完(与原来的节奏一致, 只是现在真的在播)
		tw.parallel().tween_method(func(fv: float) -> void:
			if is_instance_valid(b):
				b.frame = clampi(int(fv), 0, mini(nf, maxi(1, int(b.hframes) * int(b.vframes))) - 1)
		, 0.0, float(nf), 0.26)
	tw.tween_interval(0.14)
	tw.tween_property(b, "modulate:a", 0.0, 0.3)
	tw.tween_callback(b.queue_free)

# 通用飞行VFX: 贴图从A飞到B (自动识别横排帧动画 nf=宽/高) → 到点自销. delay=起飞延迟(连珠错峰用).

## ★★2026-08-07: 与 battle_render.gd 同一族的钳制 —— `n` 是**调用方传的帧数**,
##   和贴图真实帧数无关。传 18 而贴图只有 7 帧时 `mini(n-1, ...)` 会给出 17 ⇒ 越界。
##   冒烟随机报的 `Index p_frame = 17 is out of bounds (vframes*hframes = 7)` 就是这里。
##   ⇒ 一律再与**精灵自己的 hframes × vframes** 取小。引擎校验的是这个乘积, 不是 hframes。
func _anim_vfx_frame(fv: float, spr, n: int) -> void:
	if is_instance_valid(spr):
		var real: int = maxi(1, int(spr.hframes) * int(spr.vframes))
		spr.frame = clampi(int(fv), 0, mini(n, real) - 1)
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

## R2-3 训龟大师增益/减益脚下光环(薄封装·复用 fx-glow-ring·守 _world 空→数值测试不依赖演出)。
##   跟随单位、dur 秒后淡出(_aura_vfx 已挂 _follow_vfx)。怒火/临时血/狂暴/冰川寒气 都用它。
func _buff_aura(u: Dictionary, col: Color, dur: float, radius_px: float = 52.0) -> void:
	if _world == null or u == null:
		return
	_aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, radius_px, col, dur)

## R2-3 身体自发光(加性 glow billboard·罩住身体·跟随·dur 秒淡出)。怒火"身体发纯红光"用它。
## ★对准身体中段: 跟随高度 h=1.0(= u.height+1.0·见 _world_pos(pos,height+1.0)"取身体中段")。
func _body_glow(u: Dictionary, col: Color, dur: float, size_px: float = 84.0) -> void:
	if _world == null or u == null:
		return
	var g := _glow_bb(u["pos"], float(u.get("height", 0.0)) + 1.0, size_px, Color(col.r, col.g, col.b, 0.0))   # 身体中段·透明淡入
	_follow_vfx.append({"spr": g, "unit": u, "h": 1.0})                          # h=1.0 → 每帧贴身体中段
	var mat := g.material_override as StandardMaterial3D
	var tw := _reg_tween()
	tw.tween_property(mat, "albedo_color", col, 0.22)
	tw.tween_interval(maxf(0.05, dur - 0.55))
	tw.tween_property(mat, "albedo_color", Color(col.r, col.g, col.b, 0.0), 0.33)
	tw.tween_callback(g.queue_free)

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



# ── ⚡ 气波「全套」特效辅助 (加性发光 billboard + 蓝色能量火星) ──────────────
#    Sprite3D 加性 + hframes 有坑, 故发光单独用 QuadMesh+加性材质 billboard 叠上去.
func _glow_bb(pos2d: Vector2, h: float, size_px: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size_px * WS, size_px * WS)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = VfxTex._make_glow_texture()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD          # ★加性发光 (自发光·照亮感)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED    # 永远面向相机
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = _world_pos(pos2d, h)
	_world.add_child(mi)
	return mi

# ★立牌朝相机 + 尖头指向「屏幕上的行进方向」— 任意360°尖头都精准(仿Botworld弹道)
#    面向相机→有体积不像贴图; 屏幕内旋转→尖头跟着飞行方向转(斜/上下都对).
func _orient_billboard_dir(node: Node3D, travel_world: Vector3) -> void:
	if _cam == null or not is_instance_valid(_cam): return
	var p: Vector3 = node.global_position
	var to_cam: Vector3 = _cam.global_position - p
	if to_cam.length() < 0.001: return
	to_cam = to_cam.normalized()
	if travel_world.length() < 0.001: return
	var tw: Vector3 = travel_world.normalized()
	var s0: Vector2 = _cam.unproject_position(p)
	var s1: Vector2 = _cam.unproject_position(p + tw)
	var scr: Vector2 = s1 - s0
	if scr.length() < 0.001: return
	var ang: float = atan2(scr.y, scr.x)   # 屏幕行进角(y向下)
	var zx: Vector3 = to_cam                # 法线朝相机→面向相机
	var xx: Vector3 = Vector3.UP.cross(zx)
	if xx.length() < 0.001: xx = Vector3.RIGHT
	xx = xx.normalized()
	var yx: Vector3 = zx.cross(xx).normalized()
	var b: Basis = Basis(xx, yx, zx).rotated(zx, -ang)   # 绕视轴旋转→尖头(local+X)对准屏幕行进方向
	node.global_transform = Transform3D(b, p)

# 蓝色能量火星 (一次性爆·自销) — 仿 _vfx._impact_particles 但蓝+加性
func _chi_embers(pos2d: Vector2, h: float, amount: int = 10) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = 0.45
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 75.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -6.0, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.72, 0.32, 1.0)   # 暖橙火星(配火球序列图)
	ps.process_material = mat
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(1.0, 0.75, 0.40, 1.0)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = _world_pos(pos2d, h)
	_world.add_child(ps)
	var tw := _reg_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(ps.queue_free)
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
	# ══ 2026-08-01 补: 这四个【效果完全不碰敌人】, 却因为没登记而被要求贴到 70 码才放 ══
	#   一个纯自身增益要求"离敌人 70 码以内"显然是错的 —— 它们和护盾/治疗是同一类。
	"diceFate": true,          # 命运骰子: 纯自身改暴击/暴伤(_sk_dice_fate 全程只写 u 自己)
	"pirateRum": true,         # 朗姆酒: 纯自身 HoT 回血 + 加护甲魔抗
	"diamondPowerball": true,  # 钻石滚球: 进入自身滚球位移态(roll_active)
	"shellCopy": true,         # 复制: 遍历全场敌复制技能名, 与距离无关
}

# 远程敌向技的专属放技射程(码): 有这条的技能"够得着就放"·不被近战射程卡着(用户2026-07-11: 手里剑是远程技·改2000)
const _SKILL_CAST_RANGE := {"ninjaShuriken": 2000.0, "ninjaBomb": 2000.0, "ninjaBackstab": 2000.0, "lineInkBomb": 2000.0, "eliteHammer": 500.0, "minionBodysurf": 2000.0, "minionRocket": 2000.0, "chestStorm": 2000.0,
	"fortuneAllIn": 2000.0,   # 财神·梭哈(用户 2026-07-31): 原来回落到攻击射程 70 → 得贴脸才撒币
	"basicSlam": 150.0,       # 小龟·过肩摔(用户 2026-07-31): 擒抱技, 给一点起手余量而不是必须贴到 70
	# ══ 2026-08-01 一次性补齐(用户:「很多角色的技能为啥一定要贴脸才去放？有很大问题」) ══
	#   排查发现: 87 个实装技能里【只有 8 个】登记过专属放技射程, 其余全部回落到该龟的攻击射程,
	#   近战龟就是 70 码 —— 于是"火炮齐射""财宝炮击""龟派气波"这种明摆着的远程技也得贴脸才放。
	#   ★下面每个数字都【取自该技能自己的实现】(逐个查过), 不是拍的; 依据写在各行后面。
	#   唯一例外是 crystalBall, 代码里没有任何距离限制 —— 那个是拍的, 已注明。
	"bambooSmack": 2000.0,          # 竹击: 实现是遍历全场敌【钩最远那个】→ 全场技
	"bambooSpikes": 300.0,          # 竹刺阵: distance_to(c) <= 300.0
	"basicBarrage": 420.0,          # 打击: 每波沿方向飞 end_pos = pos + dir*420(打到人就停)
	"basicChiWave": 2000.0,         # 龟派气波: 实现注释「穿透全场」, 落点判定 95 码
	"candyBarrage": 600.0,          # 糖衣炮弹: _skill_ring(center, …, 600.0) 笼罩区
	"candyHammer": 200.0,           # 糖果锤: 直线宽 70、长 200
	"chestCannon": 2000.0,          # 财宝炮击: _on_line 无长度上限 = 全场直线激光
	"crystalBall": 600.0,           # ★水晶球: 代码里【没有】距离限制, 600 是拍的(法师射线)
	"crystalBurst": 350.0,          # 碎晶爆破: CRYSTAL_BURST_RADIUS = 350
	"diamondSmash": 400.0,          # 钻石冲撞: _dash_to 冲过去撞 → 给冲刺距离
	"diceAllIn": 300.0,             # 孤注一掷: 前方 120°/300 码扇形
	"diceFlashStrike": 2000.0,      # 稳定骰子: _dice_pick_strike_target 里写着「射程2000」
	"headlessFear": 200.0,          # 恐吓: distance_to(cx) > 200.0 跳过
	"headlessTendrils": 1500.0,     # 万千触须: 实现里写着「射程1500码」
	"pirateCannonBarrage": 2000.0,  # 火炮齐射: 从【船上】齐射, 落点 250 码环
	"pirateShipPassive": 400.0,     # 海盗船: 后续霰弹实现注释「射程400」
	"rockShockwave": 820.0,         # 磐石之躯: 岩脊 reach = 820.0
	"shellShadow": 620.0}           # 暗影: distance_to(start) > 620.0 跳过   # chestStorm=宝箱龟财宝风暴(用户2026-07-19: 射程改2000)   # 墨水炸弹/精英铁锤/小将浪板+火箭 各自射程(用户2026-07-18: 小将两技射程2000)
func _skill_cast_range(u: Dictionary, stype: String) -> float:
	if _SELF_CAST_SKILLS.has(stype): return 99999.0                       # 自/友向: 任意距离即放
	return float(_SKILL_CAST_RANGE.get(stype, _eff_range(u)))  # 远程敌向技用专属射程; 否则=攻击射程(近战贴身放·含装备射程%)

# ═══ 选3 多技能轮转 (用户2026-06-28拍板: 保留选3, 让3技在战斗真生效) ═══
# 被动型技 (开局生效, 不进主动轮转; 在 _spawn._apply_spawn_passives 里按是否被选施加)
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
	elif not use_loadout and GameState.foe_loadouts.has(id):   # 敌侧: ghost快照的技能选择(用户2026-07-15 ghost带技能)
		var flo = GameState.foe_loadouts[id]
		if flo is int or flo is float:
			idx = int(flo)
	if idx < 1 or idx >= pool.size():
		idx = 1 if pool.size() > 1 else 0
	# 锁默认(Q2): 选中候选若未实装(放不出)→回落默认签名技 idx1, 防选了没主动技. (4选1候选大实装前)
	if idx >= 1 and idx < pool.size():
		var ty := str((pool[idx] as Dictionary).get("type", ""))
		if ty != "" and ty != "physical" and ty != "magic" and not _IMPL_SKILLS.has(ty) and not PASSIVE_SKILL_TYPES.has(ty):
			idx = 1
	return idx

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
	"eliteHammer": true,   # 精英小将·铁锤(虐杀原形改造2026-07-16)
	"minionBodysurf": true, "minionRocket": true,   # 近战小将·人体浪板 / 远程小将·追踪火箭筒(用户2026-07-18)
	# ★装备换来的技能(2026-08-06·批④): 084 手半剑【近战携带】时把携带者的技能整个换成
	#   80 龟能的【后撤十字斩】。这一行与下面 `_do_skill` 的分支**必须成对存在** ——
	#   只加这一行会让引擎选中它、而 `_do_skill` 没分支 ⇒ 技能静默变哑(不报错、只是永远不发)。
	"eqCrossSlash": true,
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
		# ★★2026-08-01 修「金盾实战永远放不出来」(用户:「放金盾的条件到底是什么」)。
		#   fortuneAllIn 这一技【用过之后会变成金盾】(见 _do_skill 的 allin_used 分派),
		#   而这里原来把它【整个排除出选技】→ 金盾根本进不到"被选中"这一步。
		#   我 2026-07-31 修的是下面 _cast_skill 里的早退, 那是【更靠后的一层】——
		#   门禁直接调 _cast_skill 所以绿, 实战走 _pick_ready_skill 所以坏。同一个 bug 修了两层才对。
		#   现在只在【用过 且 没金币】时跳过(放出来也是 0 盾, 白花龟能)。与 _cast_skill 的闸同口径。
		if st == "fortuneAllIn" and u.get("allin_used", false) and int(u.get("gold", 0)) <= 0:
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
		if not u["alive"] or u.get("no_move", false) or u.get("airborne", false) or u.get("_slam", false) or u.get("roll_active", false) or u.get("hunter_roll_active", false):
			continue
		# ★用户2026-07-11「近战靠近后应停止移动、定身攻击、收手, 别一直挤」:
		#   已进攻击射程(交战)的近战 → 完全不被分离推 → 贴脸定身开打(根治"打起来一直挤")。
		var _mt = u.get("_sep_target")
		if bool(u.get("melee", false)) and _mt is Dictionary and (_mt as Dictionary).get("alive", false) and u["pos"].distance_to((_mt as Dictionary)["pos"]) <= _eff_range(u) + 10.0:
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
			if is_same(o, u) or not o.get("alive", false) or str(o.get("side", "")) != str(u.get("side", "")):
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
	# 梭哈一场限一次·用过后该技变「金盾」(80龟能·护盾=金币数·持盾锁龟能·用户2026-07-12)。
	# ★★这里原本写的是 `return int(u.get("gold",0)) > 0` —— 本意是"0 金币不空放"的【前置检查】,
	#   却写成了 return, 于是 allin_used 之后【整个 _do_skill 都跑不到】, 金盾从来没生效过;
	#   更糟的是它返回 true, 调用方照样扣冷却 → 80 龟能白花。
	#   用户 2026-07-31:「财神龟的金盾压根没生效吗」「实战里面金盾就是没生效」——
	#   探针实证: 走 _cast_skill 护盾=0/gold_shield_until=0, 直接调 _sk_fortune_goldshield 则 40/4.37。
	#   现在只在【不满足前置】时 return false, 满足就落到下面正常施放。
	if stype == "fortuneAllIn" and u.get("allin_used", false) and int(u.get("gold", 0)) <= 0:
		return false
	_anticipate(u)                  # 放大招前预备(缩)→挥出(伸) 形变
	_shake(JUICE_SHAKE_HEAVY)       # 大招释放 = 轻震屏
	# 施法技能不用飘空图标 (用户定): 技能视觉靠各自 _skill_ring/投射物/形变, 不浮贴图 billboard
	# (原通用 _vfx._play_skill_vfx 飘空贴图已禁用 — 一张图标浮半空不贴 2.5D)
	_do_skill(u, tgt, stype)
	_log("[color=%s]✦ %s[/color] 施放 [color=#ffe08a]%s[/color]" % [_log_side_hex(u), _unit_name(u), _skill_disp(stype)])
	return true


func _do_skill(u: Dictionary, tgt: Dictionary, stype: String) -> void:
	if _stress: _dbg_op = "skill:" + stype + ":" + str(u.get("id", "?"))   # 卡死猎手: 追踪当前放的技(冻死时定位)
	match stype:
		# ★装备换来的技能(084 手半剑·近战携带)。与 `_IMPL_SKILLS` 里那一行成对, 见那边的注释。
		"eqCrossSlash":         _equip_sys._blade_sys.cast_cross_slash(u, tgt)
		# ── 各龟签名招 (既有实装, 按 type 分派) ──
		"bambooHeal":           _bamboo_sys._sk_bamboo_heal(u)
		"angelBless":           _angel_sys._sk_angel_bless(u)
		"angelAscend":          _angel_sys._sk_angel_ascend(u)
		"iceFrost":             _ice_sys._sk_ice_frost(u, tgt)
		"iceFreeze":            _ice_sys._sk_ice_freeze(u, tgt)
		"commonTeamShield":     _ice_sys._sk_ice_team_shield(u)
		"fortuneBuyEquip":      _fortune_sys._sk_fortune_buyequip(u)
		"lightningShield":      _lightning_sys._sk_lightning_shield(u)
		"rainbowReflect":       _rainbow_sys._sk_rainbow_reflect(u)
		"ninjaBackstab":        _ninja_sys._sk_ninja_backstab(u, tgt)
		"ghostStorm":           _ghost_sys._sk_ghost_soulstorm(u, tgt)
		"ghostPhase":           _ghost_sys._sk_ghost_phase(u, tgt)
		"diamondFortify":       _diamond_sys._sk_diamond_unbreak(u)
		"diceAllIn":            _dice_sys._sk_dice_allin(u)
		"diceFlashStrike":      _dice_sys._sk_dice_flash_strike(u)
		"gamblerBet":           _gambler_sys._sk_gambler_bet(u, tgt)
		"gamblerFateWheel":     _gambler_sys._sk_gambler_fate_wheel(u)
		"hunterStealth":        _hunter_sys._sk_hunter_hide(u)
		"pirateCannonBarrage":  _pirate_sys._sk_pirate_volley(u, tgt)
		"pirateRum":            _pirate_sys._sk_pirate_rum(u)
		"pirateShipPassive":    _pirate_sys._sk_pirate_ship(u, tgt)
		"bubbleShield":         _bubble_sys._sk_bubble_shield(u, tgt)
		"lineLink":             _line_sys._sk_line_link(u)
		"lightningSurgeBuff":   _lightning_sys._sk_lightning_surge(u, tgt)
		"phoenixShield":        _phoenix_sys._sk_phoenix_lavashield(u)
		"phoenixEnhancedRebirth": _phoenix_sys._sk_phoenix_haste(u)
		"headlessFear":         _headless_sys._sk_headless_fear(u, tgt)
		"fortuneDice":          _fortune_sys._sk_fortune_dice(u)
		"crystalBarrier":       _crystal_sys._sk_crystal_bulwark(u)
		"chestCount":           _chest_sys._sk_chest_inventory(u)
		"eliteHammer":          _elite_sys._sk_elite_hammer(u, tgt)
		"minionBodysurf":       _hiding_sys._sk_minion_bodysurf(u, tgt)
		"minionRocket":         _hiding_sys._sk_minion_rocket(u, tgt)
		"starWave":             _star_sys._sk_star_wave(u)
		"twoHeadStrike":        _two_head_sys._sk_two_head_strike(u, tgt)
		"twoHeadDisrupt":       _two_head_sys._sk_two_head_disrupt(u, tgt)
		"twoHeadFusion":        _two_head_sys._sk_two_head_fusion(u, tgt)
		"lavaSurge":            _lava_sys._sk_lava_cast(u, tgt, "B")   # 岩浆涌动 (修: 原走set A=地裂)
		"lavaErupt":            _lava_sys._sk_lava_erupt(u, tgt)       # 技三: 智能冲刺+穿透普攻 / 火山暴走
		"cyberBeam":            _cyber_sys._sk_cyber_cannon(u, tgt)
		"hidingDefend":         _hiding_sys._sk_hiding_defend(u)
		"shellAbsorb":          _shell_sys._sk_shell_absorb(u, tgt)
		# ── 通用 (多龟共享 type) ──
		"shield":               _rainbow_sys._sk_rainbow_shield(u)   # 彩虹龟·棱镜护盾: 原路由到通用_sk_gen_shield(无时长·无棱镜特效), 2026-07-13写好的专用版从未被调用(用户2026-07-19"接")
		"stoneRockShield":      _stone_sys._sk_stone_rock_shield(u)
		"rockShockwave":        _stone_sys._sk_rock_shockwave(u)
		"stoneTaunt":           _stone_sys._sk_stone_taunt(u)
		# ── 数据驱动伤害技 (系数取自 detail 公式; N=物理 M=魔法 T=真实) ──
		"basicBarrage":         _sk_basic_strike(u, tgt)
		"basicChiWave":         _sk_basic_chiwave(u, tgt)
		"basicSlam":            _sk_basic_slam(u, tgt)
		"bambooSmack":          _bamboo_sys._sk_bamboo_smack(u, tgt)
		"bambooSpikes":         _bamboo_sys._sk_bamboo_spikes(u, tgt)
		"angelEquality":        _angel_sys._sk_angel_equality(u, tgt)
		"ninjaShuriken":        _ninja_sys._sk_ninja_shuriken(u, tgt)
		"ninjaBomb":            _ninja_sys._sk_ninja_bomb(u, tgt)
		"ghostPhantom":         _ghost_sys._sk_ghost_phantom(u, tgt)
		"diamondPowerball":     _diamond_sys._sk_diamond_powerball(u, tgt)
		"diamondSmash":         _diamond_sys._sk_diamond_smash(u, tgt)
		"rainbowStorm":         _rainbow_sys._sk_rainbow_storm(u)
		"gamblerDraw":          _gambler_sys._sk_gambler_wild(u, tgt)   # 万能牌(默认签名技): 原来错派纯伤害, 改回 _gambler_sys._sk_gambler_wild(2段+盾+治疗+减益)
		"hunterShot":           _hunter_sys._sk_hunter_shot(u, tgt)
		"hunterBarrage":        _hunter_sys._sk_hunter_barrage(u, tgt)
		"candyBarrage":         _candy_sys._sk_candy_barrage(u, tgt)
		"candyHammer":          _candy_sys._sk_candy_hammer(u, tgt)
		"candyBomb":            _candy_sys._sk_candy_bomb_feed(u)
		"lightningBarrage":     _lightning_sys._sk_lightning_barrage(u)
		"phoenixScald":         _phoenix_sys._sk_phoenix_scald(u, tgt)
		"lavaQuake":            _lava_sys._sk_lava_cast(u, tgt, "A")   # 地裂(默认): 修-原派_sk_dmg带slow→应_lava_quake(全体魔+削魔抗20%)
		"crystalBurst":         _crystal_sys._sk_crystal_burst(u, tgt)
		"crystalBall":          _crystal_sys._sk_crystal_orb(u, tgt)
		"chestStorm":           _chest_sys._sk_chest_storm(u, tgt)
		"headlessTendrils":     _headless_sys._sk_headless_tendrils(u, tgt)
		"headlessSoulStrike":   _headless_sys._sk_headless_soul_charge(u)
		"chestCannon":          _chest_sys._sk_chest_cannon(u, tgt)
		# ── Batch2 特殊技 (bespoke) ──
		"fortuneAllIn":         (_fortune_sys._sk_fortune_goldshield(u) if u.get("allin_used", false) else _fortune_sys._sk_fortune_allin(u, tgt))
		"starWormhole":         _star_sys._sk_star_wormhole(u, tgt)
		"starGravityWarp":      _star_sys._sk_star_gravity_warp(u)
		"lineFinish":           _line_sys._sk_line_finish(u)
		"lineInkBomb":          _line_sys._sk_line_ink_bomb(u)
		"cyberHijack":          _cyber_sys._sk_cyber_hijack(u)
		"cyberSmartAI":         _cyber_sys._sk_cyber_smart(u)
		"bubbleBind":           _bubble_sys._sk_bubble_bind(u, tgt)
		"bubbleBurst":          _bubble_sys._sk_bubble_burst(u, tgt)
		"hidingShrink":         _hiding_sys._sk_hiding_shrink(u)
		"hidingBuffSummon":     _hiding_sys._sk_hiding_buff(u)
		"shellCopy":            _shell_sys._sk_shell_copy(u, tgt)
		"shellShadow":          _shell_sys._sk_shell_shadow_dive(u, tgt)
		"diceFate":             _dice_sys._sk_dice_fate(u)

func _sk_basic_shield(u: Dictionary, tgt: Dictionary) -> void:   # 小龟·龟盾: 金弧劈砍→挥到位(0.25s)爆裂+命中(1:1 PoC时序/帧率·用户2026-07-11)
	var to_r: bool = tgt["pos"].x >= u["pos"].x
	var toward: Vector2 = u["pos"] - tgt["pos"]
	var arc_off: Vector2 = (toward.normalized() if toward.length() > 1.0 else Vector2.LEFT) * 42.0
	_vfx._play_anim_vfx("res://assets/sprites/vfx/basic-shieldbash-arc.png", tgt["pos"] + arc_off, 150.0, 16.67, 1.25, not to_r)
	_anticipate(u)
	_pending_shots.append({"delay": 0.25, "src": u, "fn": _basic_shield_impact_hit.bind(u, tgt)})

func _basic_shield_impact_hit(u: Dictionary, tgt) -> void:
	if not u.get("alive", false): return
	if not (tgt is Dictionary) or not tgt.get("alive", false): tgt = _targeting._nearest_enemy(u)
	if tgt == null: return
	# 龟盾强化普攻(用户2026-07-29 第四轮): 0.7A + 20%已损 → 1.5A + 13%已损。
	# ★不是单纯削弱, 是把重心从"敌人已损生命"挪到"自己的攻击力":
	#   敌 90%血 47→72(更强) / 50%血 122→121(持平) / 10%血 198→170(更弱) —— 削掉滚雪球, 前期更稳。
	var lost: float = (tgt["maxHp"] - tgt["hp"]) * 0.13
	var raw: float = u["atk"] * 1.5
	var dmg := _atk_dmg(u, 1.5, tgt) + int(lost)
	_damage._apply_damage_from(u, tgt, dmg, Color("#ff4444"))
	_damage._grant_shield(u, (raw + lost) * 0.80)
	_damage._knockback(u, tgt, 60.0)
	_vfx._play_anim_vfx("res://assets/sprites/vfx/basic-shieldbash-impact.png", tgt["pos"], 130.0, 20.0, 1.05)
	_skill_ring(u["pos"], Color(1.0, 0.9, 0.45, 0.5), 50.0)
	_shake(0.1)
func _basic_first_blocker(u: Dictionary, dir: Vector2):          # 可被挡直线弹道: 返回dir方向路径上第一个"敌/蛋"(障碍穿过·我方不挡·走_enemies_of天然含蛋不含友)
	var best = null
	var bestd: float = INF
	for o in _targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = rel.dot(dir)
		if along < 0.0: continue
		if (rel - dir * along).length() > 55.0: continue
		if along < bestd: bestd = along; best = o
	return best

func _sk_basic_strike(u: Dictionary, _tgt = null) -> void:      # 小龟·打击(封板·10波序列驱动·80龟能): 全程定身·10波每0.15s·每波随机挑1存活敌当方向·气波可被挡(命中路径第一敌/蛋)·每波0.4A(吃不屈)·[慢飞弹道视觉留F5]
	_damage._stun(u, 1.65, "_sk_basic_strike", true)   # 全程定身(10波×0.15s)
	for i in range(10):
		var fn := func():
			var es: Array = _targeting._targetable_enemies(u)   # ★方向只从可主动锁的敌里挑(排围栏未破的蛋); 穿过打到蛋仍算(_basic_first_blocker)
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
						_damage._apply_damage_from(u, _h, _atk_dmg(u, 0.4, _h), Color("#ff4444"))
					, "src": u})
		_pending_shots.append({"delay": float(i) * 0.15, "fn": fn, "src": u})

# 气波从 from2d 打向 tgt 时能命中几个敌 (带宽80·射程900) — 供智能位移冲刺评估
func _chiwave_hits_from(u: Dictionary, from2d: Vector2, tgt: Dictionary) -> int:
	var d: Vector2 = tgt["pos"] - from2d
	if d.length() < 1.0: return 0
	d = d.normalized()
	var n := 0
	for o in _targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if o["pos"].distance_to(from2d) > 900.0: continue
		if _on_line(from2d, d, o["pos"], 80.0): n += 1
	return n

# 候选落点是否贴脸(离任一敌 < min_gap) — 用户"不是贴人家脸上·要考虑碰撞体积"
func _too_close_to_enemy(u: Dictionary, p: Vector2, min_gap: float) -> bool:
	for o in _targeting._enemies_of(u):
		if o.get("alive", false) and o["pos"].distance_to(p) < min_gap: return true
	return false

func _sk_basic_chiwave(u: Dictionary, tgt) -> void:            # 小龟·龟派气波(100龟能): 先自增buff(暴击25%/吸血20%/护穿0.1A·3秒·第六轮删暴伤)→朝当前目标发穿透气波(带宽80·打沿途所有敌+蛋)每命中2.0A物理+击飞1.5s+击退200 [智能位移留F5]
	if tgt == null: tgt = _targeting._nearest_enemy(u)
	if tgt == null: return
	var ap: float = u["atk"] * 0.1
	# ★用户2026-07-30 第六轮: 【删掉暴伤 +20%】, 吸血 10%→20%。
	#   为什么这么改有效: 暴伤是【乘算】, 会放大它自己刚上的暴击(期望倍数 1.125→1.350),
	#   等于自己吃自己的加成 —— 而吸血只让它更耐久, 不进伤害乘法链。
	#   我此前两轮把系数从 3.5A 砍到 2.0A(−43%), 胜率反而 88.0→92.8% —— 证明砍系数没用,
	#   它的强度在【穿透全场 + 1.5秒群体击飞 + 自增buff + 智能位移】这套组合上。
	u["crit"] = float(u["crit"]) + 0.25
	u["lifesteal"] = float(u["lifesteal"]) + 0.20
	u["armor_pen"] = float(u.get("armor_pen", 0.0)) + ap
	var uu: Dictionary = u
	_pending_shots.append({"delay": 3.0, "fn": func():          # 3秒后撤销自增buff
		uu["crit"] = float(uu["crit"]) - 0.25
		uu["lifesteal"] = float(uu["lifesteal"]) - 0.20
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
	_damage._stun(u, 0.6, "_sk_basic_chiwave", true)   # 掌心聚气 0.6s 定身(生成动画期间)
	var start2: Vector2 = u["pos"]
	var uu2: Dictionary = u
	# ── 生成动画(掌心聚气): 回合制提取 chiwave-spawn 6帧×0.1s=0.6s 播一遍 ──
	var sp := Sprite3D.new()
	sp.texture = load("res://assets/sprites/vfx/chiwave-spawn.png")
	sp.hframes = 6; sp.frame = 0
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true   # 生成也billboard立牌(与飞行一致·用户2026-07-13)
	sp.pixel_size = (130.0 * WS) / 128.0
	sp.position = _world_pos(start2, 0.9)   # 立在掌心高度(与飞行同高)
	_world.add_child(sp)
	# ⚡聚气: 掌心加性暖光由小涨大 (蓄力感)
	var cg := _glow_bb(start2, 0.9, 60.0, Color(0.70, 0.44, 0.16, 0.0))
	var cgt := _reg_tween(); cgt.set_parallel(true)
	cgt.tween_property(cg, "scale", Vector3.ONE * 2.2, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cgt.tween_property(cg, "material_override:albedo_color", Color(0.80, 0.50, 0.20, 0.88), 0.5)
	cgt.chain().tween_callback(cg.queue_free)
	var stw := _reg_tween()
	stw.tween_method(func(fv: float) -> void: sp.frame = mini(5, int(fv)), 0.0, 6.0, 0.6)   # 6帧播一遍 0→5
	stw.tween_callback(sp.queue_free)
	# ── 0.6s聚气后 → 发射飞行波(chiwave-fly 6帧循环·恒速300码/秒·伤害随球扫过结算) ──
	_pending_shots.append({"delay": 0.6, "fn": func() -> void:
		if not uu2.get("alive", false): return
		var launch: Vector2 = uu2["pos"]
		var FLY_H := 0.9   # ★立牌高度: 火球在空中飞(约单位身体高·非贴地)
		var ball := Sprite3D.new()
		ball.texture = load("res://assets/sprites/vfx/chiwave-fly.png")
		ball.hframes = 6; ball.frame = 0
		ball.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		ball.billboard = BaseMaterial3D.BILLBOARD_DISABLED; ball.shaded = false; ball.transparent = true   # 手动定向:面向相机+尖头朝行进方向(用户2026-07-13·四面八方尖头都精准)
		ball.flip_h = false
		ball.pixel_size = (170.0 * WS) / 128.0
		ball.position = _world_pos(launch, FLY_H)   # 立在空中(非贴地)
		_world.add_child(ball)
		_orient_billboard_dir(ball, Vector3(dir.x, 0.0, dir.y))   # 初始定向(尖头对准行进方向)
		# ── ⚡全套增强: 加性发光晕 + 热核 + 发射震屏 + 火星 ──
		var glow := _glow_bb(launch, FLY_H, 260.0, Color(0.62, 0.38, 0.12, 0.80))   # 暖金橙晕(halo)
		var core := _glow_bb(launch, FLY_H, 70.0, Color(0.90, 0.58, 0.22, 0.85))    # 热核
		_shake(JUICE_SHAKE_HEAVY)
		_chi_embers(launch, FLY_H, 12)
		var _last_trail := [0.0]   # 拖尾里程 (数组封装以在闭包内可变)
		var hit2: Array = []   # Array(.has 走 ==) 防拿单位字典当 Dict key 的 recursive_hash 崩(2026-07-10教训)
		var step2 := func(d: float) -> void:
			var c: Vector2 = launch + dir * d
			if is_instance_valid(ball):
				ball.position = _world_pos(c, FLY_H)
				ball.frame = int(d / 30.0) % 6                     # 飞行帧循环: 每30码换帧(≈0.1s @300码/秒)
				_orient_billboard_dir(ball, Vector3(dir.x, 0.0, dir.y))   # 每帧定向: 面向相机+尖头朝行进方向
			var cw: Vector3 = _world_pos(c, FLY_H)   # 晕/核心跟火球同高(空中)
			if is_instance_valid(glow):
				glow.position = cw
				glow.scale = Vector3.ONE * (1.0 + 0.12 * sin(d * 0.08))   # 呼吸脉动
			if is_instance_valid(core):
				core.position = cw
			if d - _last_trail[0] >= 45.0:                          # ── 拖尾残影 (加性·淡出缩小) ──
				_last_trail[0] = d
				var af := _glow_bb(c, FLY_H, 150.0, Color(0.55, 0.32, 0.10, 0.40))
				var atw := _reg_tween(); atw.set_parallel(true)
				atw.tween_property(af, "scale", Vector3.ONE * 0.3, 0.32)
				atw.tween_property(af, "material_override:albedo_color", Color(0.55, 0.32, 0.10, 0.0), 0.32)
				atw.chain().tween_callback(af.queue_free)
				_chi_embers(c, FLY_H, 4)                             # 沿途火星
			for o in _targeting._enemies_of(uu2):
				if not o.get("alive", false) or _arr_has_unit(hit2, o): continue
				if not _on_line(launch, dir, o["pos"], 80.0): continue
				if o["pos"].distance_to(c) > 95.0: continue
				hit2.append(o)
				_damage._apply_damage_from(uu2, o, _atk_dmg(uu2, 2.0, o), Color("#7fd0ff"))   # 气波 3.5→3.0→2.0A(用户2026-07-29 第五轮)
				_damage._knockback(uu2, o, 200.0, 2.752, 2.0)              # 击飞1.5s+击退200
				# ── ⚡命中: 爆闪 + 震屏 + 火星 ──
				var bg := _glow_bb(o["pos"], FLY_H, 220.0, Color(0.95, 0.62, 0.26, 0.92))
				var btw3 := _reg_tween(); btw3.set_parallel(true)
				btw3.tween_property(bg, "scale", Vector3.ONE * 1.8, 0.22)
				btw3.tween_property(bg, "material_override:albedo_color", Color(0.95, 0.62, 0.26, 0.0), 0.22)
				btw3.chain().tween_callback(bg.queue_free)
				_chi_embers(o["pos"], FLY_H, 14)
				_shake(JUICE_SHAKE_BIG)
		var btw := _reg_tween()
		btw.tween_method(step2, 0.0, 900.0, 3.0).set_trans(Tween.TRANS_LINEAR)
		btw.tween_callback(func() -> void:
			if is_instance_valid(ball): ball.queue_free()
			if is_instance_valid(glow): glow.queue_free()
			if is_instance_valid(core): core.queue_free())
		, "src": u})

func _sk_basic_slam(u: Dictionary, tgt) -> void:  # 小龟·过肩摔(#7重做·Sett R式完整编排): 擒抱→跳空→与敌反转180°→坠落→落地范围伤+尘爆; 蛋免控只吃原地伤
	if tgt == null: tgt = _targeting._nearest_enemy(u)
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
		_damage._apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt) + int(u["atk"] * 0.002 * tmax), Color("#ff9d5c"))   # 过肩摔主目标(用户2026-07-29 第五轮): 0.7A+23%最大生命 → 1.0A + 0.2%×ATK×最大生命
	for o in _targeting._enemies_of(u):
		if is_same(o, tgt) or not o.get("alive", false): continue
		if o["pos"].distance_to(tgt["pos"]) <= 350.0:   # 范围 350码(用户2026-07-11: 250→350)
			_damage._apply_damage_from(u, o, _atk_dmg(u, 0.3, o) + int(u["atk"] * 0.0013 * tmax), Color("#ff9d5c"))   # 过肩摔周围(用户2026-07-29 第五轮): 0.2A+18% → 0.3A + 0.13%×ATK×主目标最大生命

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
		_damage._stun(tgt, 0.5, "_basic_slam_run")   # 砸地眩晕0.5s
		_vfx._flash(tgt)
	_slam_apply_damage(u, tgt, tmax)
	_shake(JUICE_SHAKE_BIG)                        # 大砸=大震屏(用户2026-07-11: 表现大范围砸击)
	_hitstop = maxf(_hitstop, 0.1)                 # 顿帧(重量感)
	_vfx._impact_particles(land, 0.0)                   # 落地碎屑迸发
	_burst_vfx("res://assets/sprites/vfx/dust-impact.png", land, 520.0, 0.6)      # 落地大尘爆
	_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", land, 680.0, 0.14)   # 范围冲击环(=350码伤害圈)
	_burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", land, 940.0, 0.32)   # 二道扩散环(大·慢)→强调大范围砸击
	u["_slam"] = false
	tgt["_slam"] = false
	tgt["no_move"] = false

const DIAMOND_ROLL_MAX_SPD := 280.0   # 钻石滚球满速(封板"移速0起4s加速到满速"·具体值手感留F5)

const DIAMOND_SMASH_CHARGE := 0.5       # 冲撞短暂蓄力时长(用户2026-07-12)
const DIAMOND_SMASH_KNOCK_VY := 0.55    # 一点点击飞(小抬·vy_mult)
const DIAMOND_SMASH_PUSH := 9.25         # 击退~300码(push_mult·headless探针tune@60fps)
const DICE_STRIKE_GAP := 0.09
const DICE_DASH_SPD := 1200.0   # 稳定骰子真冲刺速度(用户2026-07-13: 1200·距离越远越久)
const DICE_DASH_PAUSE := 0.2    # 冲到一个目标后停顿(顿一下再冲下一个·用户2026-07-13)
const DICE_DASH_OVERSHOOT := 120.0   # 落点=穿过目标再往前120码(用户2026-07-13: 对单个目标可左右反复穿刺)
func _update_dice_blood_aura(u: Dictionary) -> void:
	var lost: float = clampf(1.0 - float(u["hp"]) / maxf(1.0, float(u["maxHp"])), 0.0, 1.0)
	var inten: float = minf(lost / 0.30, 1.0)   # 0..1 (损30%满)
	var spr = u.get("_dice_blood_spr", null)
	var valid: bool = spr != null and is_instance_valid(spr)
	if inten > 0.03 and u.get("alive", false):
		if not valid:
			spr = Sprite3D.new()
			var gtex: Texture2D = VfxTex._make_glow_texture()
			spr.texture = gtex
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.shaded = false; spr.transparent = true
			spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			spr.pixel_size = (170.0 * WS) / float(maxi(1, int(gtex.get_height())))
			_world.add_child(spr)
			_follow_vfx.append({"spr": spr, "unit": u, "h": 0.35})
			u["_dice_blood_spr"] = spr
		var pulse: float = 0.6 + 0.4 * sin(_t * 7.0)
		spr.modulate = Color(1.0, 0.12, 0.10, (0.10 + 0.42 * inten) * pulse)   # 血红·随损血+脉动
	elif valid:
		u["_dice_blood_spr"] = null
		spr.queue_free()

# 彩虹棱镜光环: 持续显当前棱镜色(红真伤/蓝盾/绿回血)一眼区分·跟随+脉动 (用户2026-07-13"明显红蓝绿区分")
const _PRISM_COLS := [Color(1.0, 0.22, 0.20), Color(0.25, 0.55, 1.0), Color(0.28, 1.0, 0.42)]   # 0红 1蓝 2绿
func _update_rainbow_prism_aura(u: Dictionary) -> void:
	var spr = u.get("_prism_aura_spr", null)
	var valid: bool = spr != null and is_instance_valid(spr)
	if not u.get("alive", false):
		if valid:
			u["_prism_aura_spr"] = null
			spr.queue_free()
		return
	if not valid:
		spr = Sprite3D.new()
		var gtex: Texture2D = VfxTex._make_glow_texture()
		spr.texture = gtex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false; spr.transparent = true
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		spr.pixel_size = (190.0 * WS) / float(maxi(1, int(gtex.get_height())))
		_world.add_child(spr)
		_follow_vfx.append({"spr": spr, "unit": u, "h": 0.28})
		u["_prism_aura_spr"] = spr
	var pc: int = int(u.get("prism_color", -1))
	var col: Color = _PRISM_COLS[pc] if pc >= 0 and pc < 3 else Color(1, 1, 1)
	var pulse: float = 0.78 + 0.22 * sin(_t * 5.0)
	spr.modulate = Color(col.r, col.g, col.b, 0.72 * pulse)

const _PRISM_RAINBOW := [Color(1, 0.35, 0.35), Color(1, 0.7, 0.25), Color(1, 0.95, 0.35), Color(0.35, 1, 0.5), Color(0.35, 0.65, 1), Color(0.7, 0.45, 1)]
const HUNTER_ROLL_SPD := 1050.0   # 隐蔽平滑翻滚速度 px/s (250码约0.24s·薇恩Q式快滚·非瞬移)

const HEAD_STACK_DY := -34.0      # 叠层计数行 Y(血条正上方)
const HEAD_STATUS_DY := -74.0     # 状态图标行 Y(叠层行上方)
## ★★★2026-08-05【扩容前先量，量出一个本来就存在的问题】
##   用户 2026-08-04：「头顶徽章加就行」。但直接把 CAP 从 4 调到 6 是不行的 ——
##   实测：**相邻单位在屏幕上只隔 64.7 px**（分离半径 92 码），
##   而 4 项 × 间距 40 的一行已经宽 **154 px** = 单位间距的 2.4 倍
##   ⇒ **现在 4 项就已经在跟邻居的徽章互相覆盖**，6 项(234px)只会更糟。
##   ⇒ 改成【紧凑网格】：3 列 × 2 行，把行宽压到 80px（接近 64.7 的单位间距），
##     同时容量从 4 提到 6。
const HEAD_ITEM_STEP := 27.0      # 网格列距
const HEAD_ROW_STEP := 28.0       # 网格行距
const HEAD_COLS := 3              # 每行列数
const HEAD_ROW_CAP := 6           # 最多项数(3 列 × 2 行)
const HEAD_ITEM_SZ := 24.0        # 网格里每项的边长(原来 32~44 摆不下)·★24 而不是 26: 弹入过冲峰值 1.12 倍 → 26.9px, 必须仍 < 列距 27
const HEAD_POP_T := 0.20          # 徽章出现的弹入时长(秒)
const HEAD_POP_BACK := 1.70158    # 弹入回弹系数(标准 easeOutBack)·峰值约 1.099 倍 → 24*1.099=26.4 < 列距 27

func _layout_head_badges(u: Dictionary) -> void:
	var st: Dictionary = u.get("stacks", {})
	var stacks: Array = []            # 叠层计数(图标+数字)·可扩展: 未来 rock/rage 在此追加
	var ne := int(st.get("electric", 0))
	if ne > 0: stacks.append({"icon": "res://assets/sprites/passive/lightning-storm-icon.png", "tint": Color(1.0, 0.92, 0.4), "n": ne, "sz": 34.0})
	var ni := int(st.get("ink", 0))
	if ni > 0: stacks.append({"icon": "res://assets/sprites/passive/ink-mark-icon.png", "tint": Color(0.75, 0.72, 0.85), "n": ni, "sz": 34.0})
	var nai := int(u.get("cyber_ai_charge", 0))
	if nai > 0: stacks.append({"icon": "res://assets/sprites/vfx/hijack-chip.png", "tint": Color(0.55, 0.95, 1.0), "n": nai, "sz": 32.0})   # 智能AI充能层(青调芯片·2026-07-15)
	var ncr := int(st.get("crystal", 0))
	if ncr > 0: stacks.append({"icon": "res://assets/sprites/vfx/crystal-shard.png", "tint": Color(0.75, 0.92, 1.0), "n": ncr, "sz": 32.0})   # 结晶印记层(冰蓝碎晶·满5引爆·2026-07-15)
	var status: Array = []            # 状态图标(纯图标·瞬时态)·可扩展: 未来 stun/taunt/silence/curse 在此追加
	if _t < float(u.get("hunt_mark_until", 0.0)): status.append({"icon": "res://assets/sprites/vfx/hunter-mark.png", "tint": Color(1, 1, 1), "n": 0, "sz": 44.0})
	if u.get("hijacked", false): status.append({"icon": "res://assets/sprites/vfx/hijack-chip.png", "tint": Color(1, 1, 1), "n": 0, "sz": 34.0})   # 被侵入: 芯片图标(2026-07-15)
	var vis: bool = u.get("alive", false) and _cam != null
	var anchor := Vector2.ZERO
	if vis:
		var head := _world_pos(u["pos"], float(u.get("height", 0.0)) + float(u.get("bar_head_h", 2.4)))   # 锚血条同一世界点→整层随角色·大单位自动抬
		if _cam.is_position_behind(head): vis = false
		else: anchor = _cam.unproject_position(head)
	_layout_head_row(u, "_hbrow_stack", stacks, anchor, HEAD_STACK_DY, vis, false)
	# ★状态行的 Y 必须【跟着叠层行的实际高度走】，不能写死 —— 叠层行改成网格后会向上长：
	#   3 项以内还是 1 行(底 -34)，4 项起变 2 行(顶跑到 -62)，而状态行钉在 -74、
	#   图标 26px 高 ⇒ 两行**重叠 12px**。改成按叠层行真实行数下推。
	var st_rows: int = int(ceil(float(mini(stacks.size(), HEAD_ROW_CAP)) / float(HEAD_COLS)))
	var status_dy: float = HEAD_STATUS_DY - float(maxi(st_rows - 1, 0)) * HEAD_ROW_STEP
	_layout_head_row(u, "_hbrow_status", status, anchor, status_dy, vis, true)

func _layout_head_row(u: Dictionary, store: String, items: Array, anchor: Vector2, dy: float, vis: bool, pulse: bool) -> void:
	var pool: Array = u.get(store, [])
	var count: int = mini(items.size(), HEAD_ROW_CAP)
	while pool.size() < count:
		var nb := _make_head_badge()
		if _ui_layer != null: _ui_layer.add_child(nb)
		pool.append(nb)
	while pool.size() > count:
		var ob = pool.pop_back()
		if is_instance_valid(ob): ob.queue_free()
	u[store] = pool
	if count == 0 or not vis:
		for b in pool:
			if is_instance_valid(b): b.visible = false
		return
	# ★网格：每行最多 HEAD_COLS 列，整体仍以头顶为中心
	var rows: int = int(ceil(float(count) / float(HEAD_COLS)))
	var pa: float = (0.55 + 0.45 * sin(_t * 5.0)) if pulse else 1.0
	for i in range(count):
		var b = pool[i]
		if not is_instance_valid(b): continue
		var it: Dictionary = items[i]
		# ★尺寸统一到网格边长 —— 原来每项自带 32~44，网格里摆不下也不齐
		var sz: float = HEAD_ITEM_SZ
		var icon := b.get_node("icon") as TextureRect
		icon.custom_minimum_size = Vector2(sz, sz); icon.size = Vector2(sz, sz)
		var path: String = str(it.get("icon", ""))
		if str(b.get_meta("cur", "")) != path:      # 图标变了才reload
			icon.texture = load(path)
			b.set_meta("cur", path)
		icon.modulate = it.get("tint", Color(1, 1, 1))
		var lbl := b.get_node("num") as Label
		var nn: int = int(it.get("n", 0))
		lbl.text = str(nn) if nn > 0 else ""
		lbl.position = Vector2(sz - 15.0, sz - 20.0)   # 数字挂图标右下角(叠加数样式)→图标+数字紧凑居中一体·不外扩偏心
		b.visible = true
		b.modulate.a = pa
		# 网格坐标：本行的列数可能少于 HEAD_COLS（最后一行），要按本行自己居中
		var ri: int = i / HEAD_COLS
		var ci: int = i % HEAD_COLS
		var row_n: int = mini(count - ri * HEAD_COLS, HEAD_COLS)
		var row_w: float = float(row_n - 1) * HEAD_ITEM_STEP
		var rx: float = anchor.x - row_w * 0.5
		# 多行时整体上移，让网格仍以原来那条基线为底
		var ry: float = anchor.y + dy - float(rows - 1 - ri) * HEAD_ROW_STEP
		b.position = Vector2(rx + float(ci) * HEAD_ITEM_STEP - sz * 0.5, ry)
		# ★出现时弹一下(用户 2026-08-04 问「你觉得怎么动」)
		#   刻意【不用 tween】: 徽章每帧重排、还会被回收复用, tween 会和重排打架、
		#   且 CLAUDE.md §3.5 记着无头 CI 下 tween 推进不稳。用纯函数按时间算缩放, 可即时判定。
		#   判据是【这一格换了内容】(图标或数字变了) —— 复用同一个节点显示新东西也算"出现"。
		var sig: String = path + "|" + lbl.text
		if str(b.get_meta("sig", "")) != sig:
			b.set_meta("sig", sig)
			b.set_meta("pop_t0", _t)
		var pk: float = clampf((_t - float(b.get_meta("pop_t0", -9.0))) / HEAD_POP_T, 0.0, 1.0)
		# 0→1 的回弹(标准 easeOutBack): 从 0 涨上去、冲过 1 再落回。
		# ★别用 `lerp(0.4,1,pk) + sin(pk*PI)*k` —— 那个**根本不过冲**:
		#   sin 的峰在 pk=0.5, 而那时基底才 0.7, 合起来 0.86 < 1, 白写。
		var q: float = pk - 1.0
		var scl: float = 1.0 if pk >= 1.0 else 1.0 + (HEAD_POP_BACK + 1.0) * q * q * q + HEAD_POP_BACK * q * q
		b.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
		b.scale = Vector2(scl, scl)

func _make_head_badge() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE                # 图标原图365~500px, 必设IGNORE_SIZE否则按原始巨大尺寸渲染
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	var lbl := Label.new()
	lbl.name = "num"
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)
	return root

func _free_head_badges(u: Dictionary) -> void:   # 单位死亡/清场时释放头顶徽章池
	for store in ["_hbrow_stack", "_hbrow_status"]:
		for b in u.get(store, []):
			if is_instance_valid(b): b.queue_free()
		u[store] = []

const HUNTER_ARROW_SPD := 330.0   # 狩猎弹幕追踪箭飞行速度 px/s (慢速·看清抛物线弧·用户2026-07-14)

func _is_untargetable(o: Dictionary) -> bool:
	return _t < float(o.get("untargetable_until", 0.0)) or o.get("_assembling", false)

func _update_hunter_passive(u: Dictionary) -> void:   # 被动猎杀(重做·用户2026-07-14): 每帧扫场→任一敌<斩杀线(蛋免疫)且无强化箭在飞→猎人自动射强化箭→命中处决
	if not u.get("alive", false): return
	if _t - float(u.get("_hunt_scan_t", -1.0)) < 0.1: return   # 节流0.1s
	u["_hunt_scan_t"] = _t
	for o in _targeting._pick_enemies_of(u):
		if not o.get("alive", false): continue
		if o.get("egg", false) or o.get("_eggImmune", false) or _is_untargetable(o) or o.get("eq_exec_immune", false): continue   # 免疫处决: 蛋(免控/斩)/不沉之锚(免斩杀)/不可选(含机甲组装期·见 _is_untargetable)
		if float(o.get("deathfloor_until", 0.0)) > _t and not o.get("_hunt_demo_victim", false): continue   # 临时免死(亡灵等)→不射(免死期间免疫处决·到期再处决)
		if o.get("_hunt_exec_pending", false): continue        # 已有强化箭在飞向它(不重复射)
		var thr: float = 0.24 if _t < float(o.get("hunt_mark_until", 0.0)) else 0.14   # 猎杀印记期间抬到24%
		if float(o["hp"]) < float(o["maxHp"]) * thr:
			o["_hunt_exec_pending"] = true
			_ballistics._fire_hunter_exec_arrow(u, o)

const INK_LINK_SEC := 3.0
const INK_LINK_TRANSFER := 0.30
var _ink_links: Array = []          # [{a,b,until,spr}]
var _ink_link_busy: bool = false    # 防传导/同步递归

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

func _storm_particles(center: Vector2, radius: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = 240
	ps.lifetime = 1.3
	ps.one_shot = false
	ps.local_coords = false
	ps.position = _world_pos(center, 0.1)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius * WS, 0.05, radius * WS)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0, -0.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.3, 0.3))
	grad.add_point(0.2, Color(1, 0.7, 0.2))
	grad.add_point(0.4, Color(1, 0.95, 0.35))
	grad.add_point(0.6, Color(0.35, 1, 0.5))
	grad.add_point(0.8, Color(0.35, 0.65, 1))
	grad.set_color(1, Color(0.75, 0.45, 1))
	var gtex := GradientTexture1D.new(); gtex.gradient = grad
	pm.color_ramp = gtex
	ps.process_material = pm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm := QuadMesh.new(); qm.size = Vector2(0.15, 0.15); qm.material = dm
	ps.draw_pass_1 = qm
	_world.add_child(ps)
	return ps

func _storm_shred(o: Dictionary) -> void:
	var t: Texture2D = load("res://assets/sprites/vfx/rainbow-shred.png")
	if t == null: return
	var s := Sprite3D.new()
	s.texture = t
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = (85.0 * WS) / 96.0
	s.position = _world_pos(o["pos"], float(o.get("height", 0.0)) + 0.45)
	s.scale = Vector3.ONE * 0.5
	_world.add_child(s)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * 1.35, 0.32)
	tw.tween_property(s, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(s.queue_free)

func _reflect_pop(pos2d: Vector2, h: float, col: Color) -> void:
	var g := _glow_bb(pos2d, h + 0.4, 115.0, col)
	var tw := _reg_tween(); tw.set_parallel(true)
	tw.tween_property(g, "scale", Vector3.ONE * 1.7, 0.45)
	tw.tween_property(g, "material_override:albedo_color", Color(col.r, col.g, col.b, 0.0), 0.45)
	tw.chain().tween_callback(g.queue_free)

func _shock_dmg(u: Dictionary) -> int:   # 被动电击真伤 1.0×ATK(用户2026-07-28: 0.82→1.0·自发与满层引爆共用本函数); 涌动期间×(1+50%)
	var b: float = 1.0 + (float(u.get("shock_boost_pct", 0.0)) if _t < float(u.get("shock_boost_until", 0.0)) else 0.0)
	return int(u["atk"] * 1.0 * b)

func _scythe_face_screen(scythe: Sprite3D, center: Vector2, aim: Vector2, theta: float) -> void:   # 镰刀朝向·手动basis=面朝相机+刀锋对齐地面径向(用户2026-07-17): billboard会吞掉node旋转→改手动: 法线朝相机(正面可读), 局部up=柄尾→地面径向投影到⊥相机平面(刀锋随θ在屏幕内转=挥砍·且与地面扇形咬合)
	if not is_instance_valid(scythe) or _cam == null: return
	var grip := _world_pos(center, 0.5)
	var tip := _world_pos(center + aim.rotated(theta) * 200.0, 0.06)
	var to_cam := (_cam.global_position - grip).normalized()
	var up := (tip - grip)                                     # 期望刀锋朝向(柄尾→地面径向)
	up = up - to_cam * up.dot(to_cam)                          # 投影到⊥相机平面(仍正面朝相机)
	if up.length() < 0.02: up = Vector3.UP
	up = up.normalized()
	var xaxis := up.cross(to_cam).normalized()
	scythe.basis = Basis(xaxis, up, to_cam)                    # 列: x宽 / y刀锋朝向 / z法线朝相机
	scythe.position = grip

func _update_headless_flame(u: Dictionary) -> void:            # 亡灵残血: 越残血龟身紫焰越浓(线性/对应+1%攻/1%损血越残越猛/2026-07-17)
	if u.get("_undead_demo", false) and u.get("undead_used", false) and _t > float(u.get("deathfloor_until", 0.0)):   # demo循环: 免死窗过→回满+清标记→可再触发
		u["hp"] = float(u["maxHp"]); u["undead_used"] = false; u["deathfloor_until"] = 0.0
	var lost: float = 1.0 - clampf(float(u.get("hp", 1.0)) / maxf(1.0, float(u.get("maxHp", 1.0))), 0.0, 1.0)
	var spr = u.get("_undead_flame", null)
	if lost < 0.12:                                            # 血够高->无焰(清)
		if spr is Sprite3D and is_instance_valid(spr): (spr as Sprite3D).queue_free()
		u["_undead_flame"] = null
		return
	if not (spr is Sprite3D and is_instance_valid(spr)):       # 首次跌破->建常驻焰(跟随)
		var fl := Sprite3D.new()
		fl.texture = VfxTex._make_fire_glow_tex()
		fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fl.shaded = false; fl.transparent = true
		fl.modulate = Color(0.6, 0.2, 1.0, 0.0)
		_world.add_child(fl)
		_follow_vfx.append({"spr": fl, "unit": u, "h": 0.85})
		u["_undead_flame"] = fl
		spr = fl
	var s3: Sprite3D = spr
	var lvl: float = clampf((lost - 0.12) / 0.88, 0.0, 1.0)    # 12%->100%损血 映射0-1
	s3.pixel_size = ((44.0 + 66.0 * lvl) * WS) / 128.0         # 越残越大
	s3.modulate.a = 0.25 + 0.5 * lvl                          # 越残越浓
	s3.modulate.r = 0.6 + 0.4 * lvl; s3.modulate.b = 1.0 - 0.4 * lvl   # 越残越偏红(暴怒)

func _tick_bulwark(u: Dictionary) -> void:   # 壁垒监视: 盾到期或被打破→罩碎+朝目标放直线水晶刺(用户2026-07-16)
	if not u.get("_bulwark_armed", false): return
	if _t < float(u.get("bulwark_until", 0.0)) and float(u.get("shield", 0.0)) > 0.0: return
	u["_bulwark_armed"] = false
	u["bulwark_until"] = 0.0
	var dome = u.get("_bulwark_dome", null)
	if is_instance_valid(dome):                                  # 罩提前碎(盾破时)
		_unfollow_vfx(dome)
		var bt := _reg_tween()
		bt.tween_property(dome, "modulate:a", 0.0, 0.15)
		bt.tween_callback(func() -> void:
			if is_instance_valid(dome): dome.queue_free())
	u["_bulwark_dome"] = null
	if u.get("alive", false):
		_crystal_sys._crystal_spike_line(u)

const SPIKE_LINE_RANGE := 700.0   # 壁垒水晶刺直线长度(用户2026-07-16定)
const SPIKE_WAVE_TIME := 0.6      # 波头跑完700码用时(小菊逐帧z07-z12: ~900码/s推进·破碎消散; 取1170码/s游戏手感)
const CRYSTAL_BURST_RADIUS := 350.0   # 碎晶爆破范围(用户2026-07-15: 全体→目标周围350码·同墨水炸弹先例)
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

## 战利品描述(信息面板用) —— 逐条对着 _chest_sys._chest_apply_treasure 的【实际代码】写, 改效果时这里必须同步.
const _CHEST_TREASURE_DESC := {
	"dagger": "攻击力 +25%",
	"wood_shield": "护甲与魔抗 +20%",
	"rum": "每 10 秒回复 8% 最大生命",
	"blood_dice": "暴击率 +35%",
	"chain": "砸击的范围与射程 ×2",
	"stone": "砸击额外 +100% 护甲与 +100% 魔抗",
	"long_sword": "攻击力 +45%",
	"bloodblade": "吸血 +25%",
	"flint": "普攻命中施加灼烧",
	"gem_armor": "护甲与魔抗 +25%, 最大生命 +60",
	"poison": "普攻命中使目标受到的治疗 -50%, 持续 5 秒",
	"phoenix_statue": "首次死亡以 25% 最大生命复活",
	"crown": "攻击力 +40%, 暴击 +40%, 暴击伤害 +25%, 吸血提升",
	"thunder": "命中叠金色闪电, 满 5 层引爆 1.0×ATK 真实伤害",
	"starlight": "自身造成的所有伤害转为真实伤害",
}
const _CHEST_THRESH := [1000.0, 2500.0, 4500.0, 7000.0, 12000.0]   # 大轮制开箱阈值(与 _chest_sys._chest_treasure_tick 同源)

func _tick_elite_whip(u: Dictionary) -> void:                    # 被动2·铁锁(Whipfist Longshot·CD5s用户拍板): 索敌 150~350码之间→链射→顿+目标眩晕0.4s→拉体落身后+1A魔法(用户2026-07-18: 触发范围>350改为150~350码之间)
	if not (u.get("is_elite", false) and u.get("alive", false)): return
	if u.get("_slam", false) or u.get("airborne", false): return
	if _t < float(u.get("_whip_cd", 0.0)) or _t < float(u.get("stun_until", 0.0)): return
	var tgt = _targeting._acquire_target(u)
	if tgt == null or not tgt.get("alive", false): return
	var d: float = (tgt["pos"] as Vector2).distance_to(u["pos"])
	if d >= 150.0 and d <= 350.0 and _elite_sys._elite_try_consume(u, tgt):
		u["_whip_cd"] = _t + 5.0   # 吞噬取代本次铁锁(用户2026-07-19: 铁链也能触发吞噬)
		return
	if d < 150.0 or d > 350.0:
		if _review_demo() and _review_turtle() == "elite" and (_review_skill_idx() == 1 or _review_skill_idx() == -1) and _t >= float(u.get("_whipdemo_next", 1.0e9)):
			u["_whipdemo_next"] = 1.0e9                           # demo: 拉体完成后~4.5s传回左侧再看一次铁锁
			_elite_sys._elite_mist(u["pos"] as Vector2, 0.6, 3)
			u["pos"] = Vector2(ARENA.position.x + 130.0, ARENA.position.y + ARENA.size.y * 0.5)
			_elite_sys._elite_mist(u["pos"] as Vector2, 0.6, 3)
		return
	u["_whip_cd"] = _t + 5.0
	u["_whipdemo_next"] = _t + 4.5
	u["_slam"] = true
	_elite_sys._elite_anim(u, "whip")   # 甩臂动作 (挂在真链射这句, 不能挂函数头 —— 那里每帧都跑)
	var uu := u
	var tref: Dictionary = tgt
	var from5: Vector2 = u["pos"]
	var to5: Vector2 = tgt["pos"]
	_elite_sys._elite_mist(from5 + (to5 - from5).normalized() * 24.0, 0.8, 3)   # 手臂黑雾幻化
	_bolt_line(from5, to5, Color(0.55, 0.1, 0.12, 0.9))
	var ctex: Texture2D = load("res://assets/sprites/vfx/bio-chain.png")
	if ctex != null:                                              # 链节依次伸出(快)
		var links: int = clampi(int(d / 55.0), 5, 14)
		for i in range(links):
			var lp: Vector2 = from5.lerp(to5, float(i + 1) / float(links))
			var lk := Sprite3D.new()
			lk.texture = ctex
			lk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lk.shaded = false; lk.transparent = true
			lk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			lk.pixel_size = (20.0 * WS) / float(maxi(1, ctex.get_height()))
			lk.position = _world_pos(lp, 0.8)
			lk.rotation.z = atan2(-(to5 - from5).y, (to5 - from5).x)
			lk.modulate = Color(1, 1, 1, 0.0)
			_world.add_child(lk)
			var lt := _reg_tween()
			lt.tween_interval(0.01 * float(i))
			lt.tween_property(lk, "modulate:a", 1.0, 0.03)
			lt.tween_interval(0.3)
			lt.tween_property(lk, "modulate:a", 0.0, 0.1)
			lt.tween_callback(lk.queue_free)
	_pending_shots.append({"delay": 0.14, "fn": func() -> void:   # 命中: 顿一下+目标眩晕0.4s
		if not tref.get("alive", false) or not uu.get("alive", false):
			uu["_slam"] = false
			return
		_damage._stun(tref, 0.4, "_tick_elite_whip", true)
		_vfx._flash(tref, Color(1.35, 1.2, 1.2))
		_vfx._hit_spark(tref)
	, "src": u})
	_pending_shots.append({"delay": 0.3, "fn": func() -> void:    # 拉体: 0.18s冲到目标身后
		if not uu.get("alive", false): return
		if not tref.get("alive", false):
			uu["_slam"] = false
			return
		var tp: Vector2 = tref["pos"]
		var dirp: Vector2 = tp - (uu["pos"] as Vector2)
		dirp = dirp.normalized() if dirp.length() > 1.0 else Vector2.RIGHT
		var dest: Vector2 = tp + dirp * 46.0
		dest.x = clampf(dest.x, ARENA.position.x + 30.0, ARENA.end.x - 30.0)
		dest.y = clampf(dest.y, ARENA.position.y + 20.0, ARENA.end.y - 20.0)
		var fromp: Vector2 = uu["pos"]
		_beam_vfx("res://assets/sprites/vfx/fx-trail.png", fromp, dest, 40.0, Color(0.45, 0.08, 0.1, 0.6), 0.25)
		var pt5 := _reg_tween()
		pt5.tween_method(func(q: float) -> void:
			if uu.get("alive", false): uu["pos"] = fromp.lerp(dest, q)
		, 0.0, 1.0, 0.18)
		pt5.tween_callback(func() -> void:
			uu["_slam"] = false
			if tref.get("alive", false) and uu.get("alive", false):
				_damage._apply_damage_from(uu, tref, _atk_dmg(uu, 2.0, tref, true), Color("#9bdcff"))   # 铁锁2A魔法(蓝字·用户2026-07-18: 1A→2A)
				_elite_sys._elite_mist(uu["pos"], 0.6, 3)
				var dv2: Vector2 = (tref["pos"] as Vector2) - (uu["pos"] as Vector2)
				_elite_sys._elite_slash_arc(tref["pos"], dv2.normalized() if dv2.length() > 1.0 else Vector2.RIGHT))
	, "src": u})

func _screen_flash_light() -> void:                              # 全屏轻白闪一拍(彗星撞击帧·0.06s淡入0.12s淡出·layer60盖UI下方一点)
	var cl := CanvasLayer.new()
	cl.layer = 55
	var rect := ColorRect.new()
	rect.color = Color(1.0, 0.98, 0.95, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rect)
	add_child(cl)
	var tw := _reg_tween()
	tw.tween_property(rect, "color:a", 0.28, 0.06)
	tw.tween_property(rect, "color:a", 0.0, 0.12)
	tw.tween_callback(cl.queue_free)
func _slam_debris(at2d: Vector2) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 16; ps.lifetime = 0.6; ps.one_shot = true; ps.explosiveness = 1.0; ps.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0); mat.spread = 60.0
	mat.initial_velocity_min = 4.0; mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -18.0, 0)
	mat.scale_min = 0.6; mat.scale_max = 1.7
	mat.color = Color(0.52, 0.44, 0.36, 1.0)
	ps.process_material = mat
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.52, 0.44, 0.36, 1.0)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var qm := QuadMesh.new(); qm.size = Vector2(0.14, 0.14); qm.material = dm
	ps.draw_pass_1 = qm
	ps.position = _world_pos(at2d, 0.12)
	_world.add_child(ps)
	ps.emitting = true
	var ftw := _reg_tween(); ftw.tween_interval(0.75); ftw.tween_callback(ps.queue_free)

func _absorb_mote_step(pf: float, mote, from2d: Vector2, to2d: Vector2) -> void:
	if not is_instance_valid(mote):
		return
	mote.position = _world_pos(from2d.lerp(to2d, pf), lerpf(1.0, 1.25, pf))

func _knock_up(o: Dictionary, center: Vector2, vy: float) -> void:
	if o == null or not o.get("alive", false) or o.get("airborne", false) or o.get("_knock_immune", false):   # 免击飞(017不沉之锚): 直接设airborne会绕过_knockback的守卫(用户2026-07-19"修吧")
		return
	var dir: Vector2 = (o["pos"] - center)
	dir = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	o["airborne"] = true
	o["vy"] = vy
	o["vx"] = dir.x * KNOCK_PUSH * 0.7
	o["vz"] = dir.y * KNOCK_PUSH * 0.7

func _densest_enemy_point(u: Dictionary, radius: float) -> Vector2:   # 敌最密集处(邻居最多的敌位置)
	var es: Array = []
	for e in _targeting._pick_enemies_of(u):
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





func _px_ground_sprite(tex: Texture2D, pos2d: Vector2, size_px: float, col: Color, h: float = 0.04) -> Sprite3D:   # 贴地NEAREST像素sprite(躺平)
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED; s.axis = Vector3.AXIS_Y
	s.shaded = false; s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = (size_px * WS) / float(maxi(1, tex.get_height()))
	s.position = _world_pos(pos2d, h)
	_world.add_child(s)
	return s

const NINJA_BOMB_RADIUS := 400.0
func _sk_dmg(u: Dictionary, tgt, opts: Dictionary) -> void:
	var col: Color = opts.get("color", Color("#ffd07a"))
	var aoe: bool = opts.get("aoe", false)
	var random_aoe: bool = opts.get("randomAoe", false)            # 每段随机1敌(雷暴式)
	var stagger: float = float(opts.get("stagger", 0.0))          # >0=逐段错峰(秒), 不糊
	var cap: int = 24 if stagger > 0.0 else 8
	var vh: int = clampi(int(opts.get("hits", 1)), 1, cap)
	# 段前一次性: 减益(破盾/各down/治疗削减) + rider + 贴地环
	var deb_targets: Array = _targeting._enemies_of(u) if (aoe or random_aoe) else ([tgt] if tgt != null else [])
	for e in deb_targets:
		if e == null or not e.get("alive", false):
			continue
		_apply_skill_extras(u, e, opts)
		_apply_rider(u, e, str(opts.get("rider", "")))
		_skill_ring(e["pos"], Color(col.r, col.g, col.b, 0.4), 46.0)
	if float(opts.get("selfDodge", 0.0)) > 0.0:   # 技能给施法者闪避buff(如ghost幽冥突袭25%)
		_damage._buff(u, "dodge", float(opts["selfDodge"]), true, float(opts.get("selfDodgeDur", BUFF_SEC)))
	var fixed: Array = _targeting._enemies_of(u) if aoe else ([tgt] if tgt != null else [])
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
		var es := _targeting._pick_enemies_of(u)
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
			_damage._apply_damage_from(u, e, dmg, col, ls)
			var spl: float = float(opts.get("splash", 0.0))   # 溅射到次要目标(闪电打击25%)
			if spl > 0.0:
				for o in _targeting._enemies_of(u):
					if not is_same(o, e) and o.get("alive", false):
						_damage._apply_damage_from(u, o, int(dmg * spl), col)
						break
		if tru > 0.0:
			_damage._apply_damage_from(u, e, int(u["atk"] * tru / vh), col, 0.0, true)
		if elec > 0:
			_add_stack(e, "electric", elec, 8)

# 技能附带减益(数据化 opts): 破盾%/攻防魔抗down%/治疗削减%
func _apply_skill_extras(u: Dictionary, e: Dictionary, opts: Dictionary) -> void:
	var sb: float = float(opts.get("shieldBreak", 0.0))
	if sb > 0.0 and float(e.get("shield", 0.0)) > 0.0:
		e["shield"] = float(e["shield"]) * (1.0 - sb)
	var ad: float = float(opts.get("atkDown", 0.0))
	if ad > 0.0:
		_damage._buff(e, "atk", -ad, true)
	var dd: float = float(opts.get("defDown", 0.0))
	if dd > 0.0:
		_damage._buff(e, "def", -dd, true)
	var md: float = float(opts.get("mrDown", 0.0))
	if md > 0.0:
		_damage._buff(e, "mr", -md, true)
	var hc: float = float(opts.get("healCut", 0.0))
	if hc > 0.0:
		e["heal_reduce_until"] = _t + float(opts.get("healCutDur", BUFF_SEC))
		e["heal_reduce_pct"] = maxf(float(e.get("heal_reduce_pct", 0.0)), hc)

func _apply_rider(u: Dictionary, e: Dictionary, rider: String) -> void:
	if rider == "" or e == null or not e.get("alive", false):
		return
	match rider:
		"burn":  _damage._apply_dot_stacks(e, "burn", maxi(1, roundi(u["atk"] * 0.5)), u)
		"stun":  _damage._stun(e, CTRL_SEC, "_cc_apply")
		"slow":  e["slow_until"] = maxf(float(e.get("slow_until", 0.0)), _t + _cc_dur(e, BUFF_SEC)); e["slow_mag"] = 0.6
		"curse": _damage._add_curse(e, BUFF_SEC, u)
		"atkdn": _damage._buff(e, "atk", -0.15, true)
		"mrdn":  _damage._buff(e, "mr", -0.20, true)



# ── Batch2 特殊技 (bespoke; 按 pets.json brief/detail 实装) ──

func _throw_gold_coin(src: Dictionary, tgt: Dictionary) -> void:
	var start2d: Vector2 = src["pos"]
	var p := Sprite3D.new()
	var tex := "res://assets/sprites/ui/coin.png"
	if ResourceLoader.exists(tex):
		p.texture = load(tex)
		p.pixel_size = 0.05
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		p.texture = VfxTex._make_bolt_texture(Color(1.0, 0.84, 0.2))
		p.pixel_size = 0.014
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)
	p.position = world_from
	_world.add_child(p)
	var dur := clampf(start2d.distance_to(tgt["pos"]) / 650.0, 0.18, 0.6)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": _atk_dmg(src, 0.30, tgt, false),
		"col": Color("#ff4444"), "src": src, "t": 0.0, "dur": dur, "basic_onhit": false,
		"coin_true": int(src["atk"] * 0.30),   # 梭哈每枚 0.18+0.18 → 0.3+0.3(用户2026-07-29 第五轮)
		# ★这一改顺带修掉一个隐藏缺陷: 财神普攻 = 1.0A + 2%×ATK×金币数, 而梭哈【清空金币】。
		#   每枚金币"留着"值 0.66 伤害/秒(持续到死); 旧值 17.1 点一次性 → 打平需剩余 25.7 秒,
		#   而它只活 33 秒 → t=7.3 秒后放梭哈还不如留着普攻。改到 0.3+0.3(28.4点)后打平点 42.9 秒 > 33, 任何时候放都划算。
	})

const INK_BOMB_RADIUS := 300.0                                  # 墨水炸弹AOE半径(用户2026-07-15: 原全体→落点300码范围内)
var _copy_fx_mult: float = 1.0

func _urchin_shield_fx(u: Dictionary) -> void:   # 海胆护盾(013满层): 紫刺放射+紫环+紫字, 与普通金盾区分(用户2026-07-19"特殊颜色")
	var col := Color(0.80, 0.32, 0.94)   # 海胆紫
	_splash_ring_bold(u["pos"], Color(col.r, col.g, col.b, 0.9), 130.0)
	_vfx._float_text(u["pos"] + Vector2(0, -72), "海胆盾", col, false, "shield")
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
	for i in range(12):   # 放射紫刺(海胆感)
		var ang: float = TAU * float(i) / 12.0
		var sp := Sprite3D.new()
		sp.texture = _spark_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.modulate = Color(col.r, col.g, col.b, 0.95)
		sp.position = _world_pos(u["pos"], 0.9)
		sp.pixel_size = 0.011
		_world.add_child(sp)
		var to: Vector2 = u["pos"] + Vector2(cos(ang), sin(ang)) * 64.0
		var tw := _reg_tween(); tw.set_parallel(true)
		tw.tween_property(sp, "position", _world_pos(to, 0.9), 0.26).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "modulate:a", 0.0, 0.30)
		tw.chain().tween_callback(sp.queue_free)

func _egg_level_up_vfx(u: Dictionary, total_lvl: int) -> void:   # 温泉蛋升级: 金光柱升腾 + 脚下金块 + "LV UP LvN"
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.4, 0.65), 56.0)
	_vfx._float_text(u["pos"] + Vector2(0, -74), "LV UP  Lv%d" % total_lvl, Color("#ffe08a"))
	_shake(0.05)
	var glow := VfxTex._make_fire_glow_tex()
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




func _cc_dur(u: Dictionary, sec: float) -> float:
	return sec * (1.0 - clampf(float(u.get("tenacity", 0.0)), 0.0, 0.9))

func _freeze(u: Dictionary, sec: float = CTRL_SEC) -> void:
	_damage._stun(u, sec, "_freeze")
	_skill_ring(u["pos"], Color(0.6, 0.9, 1.0, 0.6), 48.0)

func _taunt(by: Dictionary, targets: Array, sec: float = BUFF_SEC) -> void:
	for o in targets:
		o["taunt_until"] = _t + sec
		o["taunt_by"] = by

## 闪避硬上限 75%。★★出处不是我拍的 —— 规格里早就写了, 只是【从没实装】:
##   · docs/specs/类型效果-实装规格.md:134「灵物类装备额外提供 5%/10% 闪避率(宠物闪避率上限 75%)」
##   · phase2_types.gd:97 灵物档位文案同样写着「上限 75%」
##   又一例写了没人读(同 apply_team_start 零调用)。2026-08-02 补上实装。
## 想改这个数只改这里 —— 它是 dodge_bonus 的唯一钳制点。
const DODGE_CAP := 0.75

## 血祭节流: 只有【损失百分比的整数位】变了才重算。
## ★为什么要节流: 血祭随当前血量连续变化, 而 _recalc_stats 是每次挨打都调就太贵了。
##   血量只有 100 个整数桶 ⇒ 每只龟每场最多重算 100 次, 而误差被锁在 1% 生命以内
##   (即最多 0.1/0.3/0.5% 攻击力的偏差, 肉眼与数值上都无意义)。
##   ⚠ 没有血祭的单位【一次都不会重算】—— 这条 if 是热路径的守门员, 别去掉。
func _blood_rite_refresh(u: Dictionary) -> void:
	if float(u.get("_blood_rite", 0.0)) <= 0.0 or float(u.get("maxHp", 0.0)) <= 0.0:
		return
	var bucket: int = int((1.0 - float(u.get("hp", 0.0)) / float(u["maxHp"])) * 100.0)
	if int(u.get("_blood_rite_bucket", -999)) == bucket:
		return
	u["_blood_rite_bucket"] = bucket
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
	# ★剑【血祭】(羁绊·用户 2026-08-03 定): 本体每损失 1% 生命 → +0.1/0.3/0.5% 攻击力。
	#   · 按【本体自己】的血量, 不是全队平均 —— 残血反打这件事要发生在那只残血的龟身上, 玩家看得见因果。
	#   · 是【百分比】不是固定值: 剩 1% 血时 +9.9/29.7/49.5% 攻击力。
	#     (原方案书那版是固定 +0.6/1.0/1.5 攻击力/1%, 满损失 = +148 固定攻 ≈ ×4.7, 量级失控。)
	#   · 乘在 base_atk 上、和 buff 的百分比同区 —— 不是独立乘区, 避免 R8 那种"多个乘区连乘"。
	if float(u.get("_blood_rite", 0.0)) > 0.0 and float(u.get("maxHp", 0.0)) > 0.0:
		var lost_pct: float = clampf(1.0 - float(u.get("hp", 0.0)) / float(u["maxHp"]), 0.0, 1.0) * 100.0
		u["atk"] += u["base_atk"] * lost_pct * float(u["_blood_rite"]) / 100.0
	# ★遗物【生死界】(羁绊·2026-08-03): 血量 >50% 时 +3/5/8/12% 攻击力。
	#   与血祭同一个乘区(都乘在 base_atk 上), 不是独立乘区 —— 避免 R8 那种"多个乘区连乘"。
	u["atk"] *= RelicSynergySystem.atk_mult(u)
	# ★奇械【僵硬】(羁绊·2026-08-03): 每层 -2% 攻击力, 最多 20 层(= ×0.60)。
	#   ⚠ 放在【这个唯一写入点】—— 在各处攻击计算里自己乘必然漏掉一半路径。
	u["atk"] *= GadgetSynergySystem.stiff_mult(u)
	# ★★2026-08-06 加【削甲/削抗】通道 `def_shred` / `mr_shred`(089 蚀月符纸「每秒削减 1 魔抗」)。
	#   背景: `DamageMath.resist_multiplier` 对**负**抗性是增伤(`1+|r|/(|r|+40)`, 上限 2.0),
	#   `damage_math.gd:28` 注明这是**有意设计** —— 而这两行的 `maxf(0.0, …)` 把负值抹平了,
	#   于是"削穿之后开始增伤"这条机制**在这里被静默吃掉**。
	#   ★为什么是"钳完再减"而不是"去掉钳":
	#     钳是为了拦住百分比 debuff 把抗性算成负数(冰寒减攻那一类, 它们不该变增伤)。
	#     去掉钳会让那些一起变成增伤 = 改掉已上线机制。所以只给【显式削减】开一条口子:
	#     谁写了 `mr_shred` 谁才拿得到负抗性, 别的路径行为一个字节都没变。
	#   ⚠ 削减量是**单位字段** ⇒ 换路整体重建单位时自动清零(= 用户定的「削掉的魔抗本路不恢复、换路重置」)。
	u["def"] = maxf(0.0, u["base_def"] * (1.0 + acc["def"][0]) + acc["def"][1]) - float(u.get("def_shred", 0.0))
	u["mr"]  = maxf(0.0, u["base_mr"]  * (1.0 + acc["mr"][0])  + acc["mr"][1]) - float(u.get("mr_shred", 0.0))
	# ★★闪避上限(2026-08-02 用户问「每个角色我记得有闪避上限做了吗」——答: 没有, 现在加)。
	#   判定是 `randf() < dodge_bonus`(battle_damage.gd:71), randf 取值 [0,1)
	#   ⇒ dodge_bonus ≥ 1.0 就是【永远打不中】。
	#   ★这不是接通用 dodgePct 才有的风险, 探针实测【今天就已经是 bug】:
	#     单只装备上限 3 件, 带 2 件 3★ 幽灵墨鱼(各 50%) → dodge_bonus = 1.00 = 100% 免疫。
	#   上限加在这个【唯一写入点】, 不是加在判定处 —— 这样属性面板显示的也是真实生效值, 不骗人。
	u["dodge_bonus"] = minf(dodge, DODGE_CAP)
	# ★遗物【生死界】另一半: 血量 <50% 时生命偷取【翻倍】(原文括号里那串 10/20/40/64
	#   四个档四种倍率、既不是翻倍也没规律, 见 relic_synergy_system.gd 文件头)。
	u["ls_bonus"] = ls + RelicSynergySystem.lifesteal_bonus(u)

# flat DoT (诅咒等). dps=每秒落血; 真伤穿护盾. 灼烧/中毒/流血改走 _damage._apply_dot_stacks 层数模型.
func _add_dot(u: Dictionary, tag: String, dps: float, sec: float, src = null) -> void:
	# src: 施加者。原先不存 → 诅咒伤害永远无主(不进统计、不吃施加者穿甲)。2026-07-22 补。
	u["dots"].append({"tag": tag, "dps": dps, "until": _t + sec, "src": src, "_acc": 0.0})

func _default_burn_stacks(attacker: Dictionary) -> int:
	return maxi(1, roundi(float(attacker.get("atk", 0.0)) * 0.67))

func _has_dot(u: Dictionary, tag: String) -> bool:
	if tag == "burn" or tag == "poison" or tag == "bleed":
		return int(u.get("dot_stacks", {}).get(tag, 0)) > 0
	for d in u["dots"]:
		if d["tag"] == tag and _t < d["until"]:
			return true
	return false

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
				new_val = CombatMath.decay_stacks(stacks)   # 衰减80%(用户)
				if _t < u.get("true_fire_until", 0.0):
					_damage._apply_damage(u, dmg, Color("#ffffff"), u.get("dot_src", {}).get("burn", null), "tru", false, true)   # 真火: 灼烧转真伤(原走_raw_lose→无飘字无统计·用户2026-07-19)
				else:
					_damage._apply_damage(u, _damage._dot_after_resist(u, float(dmg), true, u.get("dot_src", {}).get("burn", null)), Color("#4dabf7"), u.get("dot_src", {}).get("burn", null), "mag", false, true)   # 灼烧=魔法伤害·吃魔抗
			"poison":
				dmg = stacks
				new_val = CombatMath.decay_stacks(stacks)   # 衰减80%(用户)
				_damage._apply_damage(u, _damage._dot_after_resist(u, float(dmg), true, u.get("dot_src", {}).get("poison", null)), Color("#7ee87e"), u.get("dot_src", {}).get("poison", null), "mag", false, true)   # 中毒=魔法伤害·吃魔抗
			"bleed":
				dmg = stacks
				new_val = CombatMath.decay_stacks(stacks)   # 衰减80%(用户)
				_damage._apply_damage(u, _damage._dot_after_resist(u, float(dmg), false, u.get("dot_src", {}).get("bleed", null)), Color("#ff6b6b"), u.get("dot_src", {}).get("bleed", null), "phy", false, true)   # 流血=物理伤害·吃护甲
		ds[type] = maxi(0, new_val)
		if ds[type] <= 0:
			ds.erase(type)
		if not u["alive"]:
			return

func _add_stack(u: Dictionary, tag: String, n: int, cap: int) -> int:
	var cur: int = u["stacks"].get(tag, 0) + n
	cur = mini(cur, cap)
	u["stacks"][tag] = cur
	if tag == "ink" and not _ink_link_busy:                       # 连笔·墨迹同步: 一方获墨迹另一方同步(附录B-05)
		var _p: Dictionary = _line_sys._ink_link_partner(u)
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

func _arr_has_unit(arr: Array, x) -> bool:   # ★引用判重: Array 的 has()/in 对 Dictionary 是【深比较】, 单位字典互引成环 → 卡死(同053)
	for it in arr:
		if is_same(it, x): return true
	return false

func _arr_erase_unit(arr: Array, x) -> void:   # ★引用删除: Array.erase() 同样靠深比较定位元素
	for i in range(arr.size()):
		if is_same(arr[i], x):
			arr.remove_at(i)
			return

func _lowest_hp_pct_ally(u: Dictionary):   # 生命【百分比】最低的友军(含自己) — 装备文案说的是百分比, _lowest_hp_ally 是绝对值语义
	var best = null; var bv := INF
	for o in _targeting._allies_of(u):
		var pct: float = CombatMath.hp_frac(float(o["hp"]), float(o["maxHp"]))
		if pct < bv:
			bv = pct; best = o
	return best

func _lowest_hp_ally(u: Dictionary):
	var best = null; var bv := INF
	for o in _targeting._allies_of(u):
		if o["hp"] < bv:
			bv = o["hp"]; best = o
	return best

func _is_passive_pick(u: Dictionary) -> bool:
	if u.get("minion_kind", null) != null:
		return false   # 缩头随从=实体完整龟, 自己充能放技(用户2026-07-17"没看到随从放技能他的龟能条呢"; 修前所有召唤体一律不充能=随从技能从未真通)
	return u.get("is_summon", false)

func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":
			_bolt_line(u["pos"], tgt["pos"], Color(0.3, 0.22, 0.4, 0.85))                     # 落笔墨线(命中瞬间才显·用户2026-07-15)
			_burst_vfx("res://assets/sprites/vfx/ink-splat.png", tgt["pos"], 72.0, 0.5)       # 命中墨溅(与子弹命中同步·原在施法瞬间=没等子弹到)
			_add_stack(tgt, "ink", 1, _line_sys._ink_cap(u))
		"lightning":
			_lightning_sys._lightning_electric(u, tgt)   # 普攻主目标叠电击+可引爆(连锁跳由_lightning_hop叠)
		"crystal":
			_damage._apply_damage_from(u, tgt, _mitigate(u, tgt["maxHp"] * 0.015, tgt, true), Color("#9bdcff"), 0.0, false)   # 水晶刺附1.5%目标最大生命魔法(吃魔抗·封板L559·原折进物理=类型错)
			_crystal_sys._crystal_stack(u, tgt, 1)   # 普攻叠1层结晶(满5引爆·封板)·与水晶球共享层数走同一helper(引爆改吃魔抗)
		"angel":                                          # 审判: 每段攻击额外 +目标当前HP 8% 魔法(2026-07-22订正: 注释原写11%, 代码一直是 0.08)
			_damage._apply_damage_from(u, tgt, _mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 魔法(吃魔抗+蓝字), 原flat固定值绕魔抗+错色=bug
			if u.get("_ascend_growth", false):
				_angel_sys._ascend_growth_tick(u)   # 飞升打包被动(用户2026-07-28): 每次攻击 +5龟能 +1%攻击力·持续到战斗结束
		# gambler 多重打击改云顶剑士式连击(见状态机 _gambler_sys._gambler_multi_cd), 不在这里追加
		"bamboo":                                         # 生长(改造): 蓄力时下一发普攻强化(追加魔法+回血+永久成长)
			if u.get("bamboo_charge", false):
				u["bamboo_charge"] = false
				_damage._apply_damage_from(u, tgt, _mitigate(u, u["atk"] * (1.0 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.75) + u["maxHp"] * (0.13 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.08), tgt, true), Color("#9be7ff"), 0.0, false)   # 追击魔法·选竹击=强化生长(1.0A+13%maxHp)否则基础(0.75A+8%maxHp)·用户核对JS bambooCharged
				_melee_lunge(u, tgt, 0.66)                                     # 不灭之握式: 强化发踏步加倍(0.30→0.66)明显扑上去
				_hitstop = maxf(_hitstop, 0.06)                                # 顿帧=命中厚重感
				_shake(0.06)
				_vfx._impact_particles(tgt["pos"], float(tgt.get("height", 0.0)))   # 命中碎屑迸发
				_vfx._flash(tgt, Color(0.5, 1.7, 0.65))                             # 敌绿闪(生长主题)
				_bamboo_sys._bamboo_hit_splash(tgt)                                        # 命中: 敌人身上爆一下大淡绿命中特效(≈上半身大小·用户2026-07-11); 施法者tell=双手绿点(蓄满期), 不在命中闪
				# 回血+永久成长 延到绿球落到竹叶龟身上才生效 (用户: 到自己身上才吸收)
				_spawn_bamboo_orb(tgt["pos"], u["pos"], func() -> void:
					if not u.get("alive", false):
						return
					_damage._heal(u, u["maxHp"] * (0.12 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.08))
					var _gr := (1.05 if "bambooSmack" in _chosen_skill_types(u["id"], u["side"] == "left") else 0.60); u["maxHp"] += u["base_atk"] * _gr; u["hp"] += u["base_atk"] * _gr; _recalc_stats(u); _vfx._flash(u, Color(0.5, 1.7, 0.65)))   # 永久+maxHp=系数×ATK + 吸收瞬间竹叶龟再绿闪(得到生命·不灭之握=绿闪非环)
		"rainbow":                                        # 棱镜(改造): 普攻附当前颜色效果(红真伤/蓝小盾/绿回血)
			match int(u.get("prism_color", -1)):
				0: _damage._apply_damage_from(u, tgt, int(u["atk"] * 0.25), Color("#ff6b6b"), 0.0, true)   # 红: 额外真伤
				1: _damage._grant_shield(u, u["atk"] * 0.2, 4.0)                                           # 蓝: 每普攻获小盾(通用护盾4秒·封板L74"基础龟被动蓄力普攻的护盾也4秒")
				2: _damage._heal(u, (u["maxHp"] - u["hp"]) * 0.025, true)                                               # 绿: 回2%最大HP
			# 棱镜命中: 喷当前色(每次普攻都带色·醒目·用户2026-07-13)
			var _rb_hc: Color = _PRISM_COLS[int(u.get("prism_color", -1))] if int(u.get("prism_color", -1)) >= 0 else Color(1, 1, 1)
			var _rb_hb := _glow_bb(tgt["pos"], float(tgt.get("height", 0.0)) + 0.35, 135.0, Color(_rb_hc.r, _rb_hc.g, _rb_hc.b, 0.95))
			var _rb_ht := _reg_tween(); _rb_ht.set_parallel(true)
			_rb_ht.tween_property(_rb_hb, "scale", Vector3.ONE * 1.7, 0.24)
			_rb_ht.tween_property(_rb_hb, "material_override:albedo_color", Color(_rb_hc.r, _rb_hc.g, _rb_hc.b, 0.0), 0.24)
			_rb_ht.chain().tween_callback(_rb_hb.queue_free)
			_vfx._flash(tgt, Color(_rb_hc.r + 0.5, _rb_hc.g + 0.5, _rb_hc.b + 0.5))
	# 猎人猎杀已移到 _damage._apply_damage_from 中央伤害路径(封板: 普攻/技能/装备任一伤害都处决<斩杀线)
	# 猎人·隐蔽翻滚强化: 下次普攻附带0.9A物理(吃吸血), 用后即清
	if u["id"] == "hunter" and u.get("hunter_roll_buff", false):
		u["hunter_roll_buff"] = false
		if tgt.get("alive", false):
			_damage._apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ff4444"))   # 物理红(翻滚强化+0.9A物理·飘字色规范)
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
		_bubble_sys._bubble_shield_burst(u)
	# --- 冰霜团队护盾: 到期 或 被打破(盾清零) → 250码内敌 boom×ATK 魔法(用户2026-07-11) ---
	var _fsu: float = float(u.get("frost_shield_until", 0.0))
	if _fsu > 0.0 and (_t >= _fsu or float(u.get("shield", 0.0)) <= 0.0):
		_ice_sys._frost_shield_burst(u)
	# --- 赛博侵入: 5秒到期→归队(清 hijacked·数据链断) ---
	#   ★2026-07-22 起 side 全程没被改过, 所以这里【不需要还原 side】。
	#     也正因如此, "死在侵入期→还原逻辑永不跑(死人不 tick)→尸体永久留在赛博阵营"
	#     这个老问题不复存在。
	if u.get("hijacked", false) and _t >= float(u.get("hijack_until", 0.0)):
		u["hijacked"] = false
		u["_hijack_by"] = null
		u["taunt_until"] = 0.0; u["taunt_by"] = null   # 归队时清嘲讽: 否则带着对"新队友"的嘲讽回去会锁错目标
		var _hspr = u.get("sprite", null)
		if is_instance_valid(_hspr): _hspr.modulate = Color(1, 1, 1)   # 还原红光染色
		_vfx._float_text(u["pos"] + Vector2(0, -48), "归队", Color("#8a93a0"))
	# --- 龟壳·潜影(暗影主被动·选中暗影才有): 6秒未受伤→进入隐身 ---
	if u["id"] == "shell" and not u.get("shell_stealth", false) and _t - float(u.get("shell_last_dmg_t", 0.0)) >= 6.0 and "shellShadow" in _chosen_skill_types(u["id"], u["side"] == "left"):
		_shell_sys._shell_enter_stealth(u)
	# --- 小龟·不屈(龟盾融入被动): 每6秒强化下次普攻(在_on_basic_hit消费=0.7A+20%已损+击飞+盾) ---
	if u["id"] == "basic":
		u["basic_enh_t"] = float(u.get("basic_enh_t", 0.0)) + delta
		if float(u["basic_enh_t"]) >= 6.0:
			u["basic_enh_t"] = 0.0
			u["basic_enh_ready"] = true
	# --- 熔岩变身: 怒气满100 → 变火山15秒 (被动 熔岩之心) ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		_lava_sys._lava_transform(u)
	if u["id"] == "lava" and u.get("volcano", false):             # 火山期: 怒气条=形态倒计时·15秒匀速流失到0(用户2026-07-15)
		u["rage"] = RAGE_MAX * clampf((float(u.get("volcano_until", 0.0)) - _t) / maxf(0.1, float(u.get("_volcano_dur", 15.0))), 0.0, 1.0)
	if u.get("volcano", false) and _t >= float(u.get("volcano_until", 0.0)):
		_lava_sys._lava_revert(u)
	if u["id"] == "chest":
		_chest_sys._chest_treasure_tick(u)
	# --- 忍者·冲击(亚索E式被动auto-dash): 290码内有"可冲"敌(不在其10s冷却)且距上次冲刺≥0.4s → 自动朝最近敌冲刺斩(用户2026-07-06"半径500码，最近敌人") ---
	if u["id"] == "ninja" and u.get("alive", false) and _t >= float(u.get("stun_until", 0.0)):
		if _t - float(u.get("_ninja_last_dash", -99.0)) >= 0.4 and not u.get("_ninja_gliding", false):
			var _nbest = null
			var _nbd := 290.0   # 被动冲击触发射程(用户2026-07-11: 500→290码; <冲刺距离300→冲刺会略穿过目标)
			for o in _targeting._pick_enemies_of(u):
				if not o.get("alive", false): continue
				if _t < float(o.get("_ninja_dash_until", 0.0)): continue
				var _ndd: float = u["pos"].distance_to(o["pos"])
				if _ndd <= _nbd: _nbd = _ndd; _nbest = o
			if _nbest != null: _ninja_sys._ninja_dash(u, _nbest)
	# 亡灵怒(补实装 2026-07-19 用户拍板): 无头龟每损失 1% 最大生命 → 攻击力 +1%, 最高 +100%。
	# 文案(pets.json headless.passive)与权威文档都写了这条, 但代码里【从来没有实现过】——
	# 只有 _update_headless_flame 的函数头注释提了句"对应+1%攻/1%损血", 函数体却只改紫焰特效。
	# 写法照骰子龟「赌徒之血」同型: 登场存基准 → 每帧按【当前损血】重算(不累积, 回血会降回去)。
	if u["id"] == "headless":
		var _hb: float = float(u.get("headless_base_atk", 0.0))
		if _hb > 0.0:
			var _hlost: float = clampf(1.0 - float(u["hp"]) / maxf(1.0, float(u["maxHp"])), 0.0, 1.0)
			var _want: float = _hb * (1.0 + _hlost)
			if not is_equal_approx(float(u.get("base_atk", 0.0)), _want):
				u["base_atk"] = _want
				_recalc_stats(u)

	if u["id"] == "dice":   # 赌徒之血: 按已损血加暴击(损30%满+70%·用户2026-07-28 50→70); 暴击率>100%部分每1%→1.5%暴伤
		var _lost: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["crit"] = float(u.get("dice_base_crit", u["crit"])) + minf(_lost / 0.30, 1.0) * DICE_BLOOD_CRIT
		# (暴击率>100%转暴伤由 _resolve_dmg 全局处理, 这里只设暴击率)
	# --- 赛博浮游炮(用户2026-07-15重构: 非实体·纯视觉跟随+攻击动作·不可被选中/打死): 每2秒+1 上限20 (用户2026-07-28削弱: 原每3秒+2) ---
	if u["id"] == "cyber":
		if u["_ptimer"] >= 2.0:
			u["_ptimer"] = 0.0
			u["drone_n"] = mini(20, int(u.get("drone_n", 0)) + 1)
		_tick_cyber_drones(u, delta)
		if not u.get("_slam", false) and "cyberSmartAI" in _chosen_skill_types(u["id"], u["side"] == "left"):   # 常驻走位闪避(用户2026-07-16: 被动冲刺是消耗充能层数的): 敌贴近130码+有层数→消耗1层自动躲避冲刺(冷却2.5s)
			var _ne5 = _targeting._nearest_enemy(u)
			if _ne5 != null and int(u.get("cyber_ai_charge", 0)) > 0 and (u["pos"] as Vector2).distance_to(_ne5["pos"]) < 130.0 and _t >= float(u.get("_ai_dodge_cd", 0.0)):
				u["_ai_dodge_cd"] = _t + 2.5
				u["cyber_ai_charge"] = int(u["cyber_ai_charge"]) - 1
				_cyber_sys._cyber_smart_dash(u)
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
		# 觉醒按【本龟入场后】计时, 非全局_t(用户2026-07-18修bug): _t跨双路半场累加不重置→下半场入场的龟壳_t已>20会秒觉醒; 入场首tick记基准
		if not u.has("_awaken_t0"): u["_awaken_t0"] = _t
		var _adt: float = _t - float(u["_awaken_t0"])
		if not u.get("awakened", false) and _adt >= 10.0:
			u["awakened"] = true
			_shell_sys._shell_apply_awaken(u)   # 入场10秒觉醒 (+金光爆发特效)
		if not u.get("awakened2", false) and _adt >= 20.0:
			u["awakened2"] = true
			_shell_sys._shell_apply_awaken(u)   # 入场20秒第二次觉醒(封板: 强化觉醒已并入被动·自动触发·不再gate选中)
		# 储能相位机: store(6s 受伤转储能) → 释放(冲击波+护盾) → cd(15s 不储) → store…
		_shell_sys._shell_phase_tick(u, delta)
	# 海盗船(实体)已改为 技能三 pirateShipPassive 首次充能满召唤(_pirate_sys._sk_pirate_ship·选中才召·封板L378"火炮/朗姆的船=纯装饰演出"); 原无条件4s自动召唤删除
	# --- 宝箱藏宝图·朗姆酒战利品: 每10秒回8%最大生命(封板L592·flag由开箱设) ---
	if u["id"] == "chest" and (u.get("chest_treasures", {}) as Dictionary).has("rum"):
		u["chest_rum_t"] = float(u.get("chest_rum_t", 0.0)) + delta
		if u["chest_rum_t"] >= 10.0:
			u["chest_rum_t"] = 0.0; _damage._heal(u, u["maxHp"] * 0.08)
	# --- 钻石滚球被动(封板): 选滚球 且 100码内无敌 → 免费自动滚(不耗龟能不充能)撞向最近·0.8s防抖内CD ---
	if u["id"] == "diamond" and not u.get("roll_active", false) and _t > float(u.get("roll_free_cd", 0.0)) and "diamondPowerball" in _chosen_skill_types(u["id"], u["side"] == "left"):
		var _dne = _targeting._nearest_enemy(u)
		if _dne != null and _dne["pos"].distance_to(u["pos"]) > 200.0:   # 200码内无敌=最近敌>200码(用户2026-07-12: 100→200)
			u["roll_active"] = true; u["roll_start"] = _t; u["roll_free_cd"] = _t + 0.8
	# --- 财神聚宝盆: 每3秒 +4~7金币 (用户) ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 3.0:
			u["_goldtimer"] = 0.0; u["gold"] += _juice_rng.randi_range(4, 7)
			for _gk in range(2):   # 聚宝盆冒金币: 脚下叮当迸2金块(设计"每隔几秒叮当冒金币")
				_gold_chunk_erupt(u["pos"] + Vector2(randf_range(-24.0, 24.0), randf_range(6.0, 18.0)))
	# --- 线条墨迹(用户2026-07-28): 自身实时获得 =(0.5×攻击力)% 攻速 ---
	if u["id"] == "line":
		_line_sys._line_aspd_convert(u)
	# --- 彩虹棱镜(封板L267): 每6秒随机红/蓝/绿·普攻附对应效果(红+0.25A真伤/蓝+0.2A盾4s/绿回2.5%已损·见_on_basic_hit) ---
	if u["id"] == "rainbow":
		_rainbow_sys._rainbow_prism_convert(u)   # 棱镜转化(实时·每帧): 10%最大生命→攻击力, 0.3×攻击力%→攻速
		u["_rbtimer"] = u.get("_rbtimer", 0.0) + delta
		if u["_rbtimer"] >= 6.0:
			u["_rbtimer"] = 0.0
			u["prism_color"] = _battle_rng.randi() % 3   # 棱镜(改造): 自身获颜色6秒, 普攻附色(见 _on_basic_hit)
			var _pcc: Color = _PRISM_COLS[int(u["prism_color"])]   # 换色瞬间闪新色(醒目提示切色)
			_vfx._flash(u, Color(_pcc.r + 0.4, _pcc.g + 0.4, _pcc.b + 0.4))
		if u["id"] == "rainbow" and u.get("_enh_prism", false):   # 强化棱镜(选反射打包): 每5秒抽1色(橙吸血/黄灼烧/青冰寒/紫诅咒)
			u["_epTimer"] = float(u.get("_epTimer", 0.0)) + delta
			if u["_epTimer"] >= 5.0:
				u["_epTimer"] = 0.0
				_rainbow_sys._rainbow_enh_prism_proc(u)
	# --- 泡泡·泡沫: 每5秒→泡泡值10%化魔法打最近敌 + 治疗自己10%泡泡值 (共消耗20%泡泡值·用户2026-07-15改3→5秒) ---
	if u["id"] == "bubble":
		u["_bbtimer"] = u.get("_bbtimer", 0.0) + delta
		if u["_bbtimer"] >= 5.0:                       # 用户2026-07-15: 3→5秒
			u["_bbtimer"] = 0.0
			var bs: float = float(u.get("bubble_store", 0.0))
			if bs >= 1.0:
				_damage._heal(u, bs * 0.10, true)              # 修: 15%→10%(封板)
				for _bh in range(2): _bubble_sys._bubble_rise(u["pos"])   # 泡沫被动proc: 自身回血泡泡(用户2026-07-14)
				var bt = _targeting._nearest_enemy(u)             # 修: 随机敌→最近敌(封板)
				if bt != null:
					_damage._apply_damage_from(u, bt, int(_mitigate(u, bs * 0.10, bt, true)), Color("#aef1ff"))   # 修: 35%真伤→10%化魔法(吃魔抗·封板)
					_fly_vfx("res://assets/sprites/skills/bubble-1.png", u["pos"], bt["pos"], 46.0, 0.34, 1.0)   # 泡泡弹飞向最近敌
					_bubble_sys._bubble_rise(bt["pos"]); _bubble_sys._bubble_rise(bt["pos"])   # 命中泡沫破
				u["bubble_store"] = bs * 0.80          # 修: 消耗50%→共消耗20%(10%伤+10%治·封板)
	# --- 闪电·雷电: 每4s 自动电击随机敌 (真伤) (用户) ---
	if u["id"] == "lightning":
		u["_ltimer"] = u.get("_ltimer", 0.0) + delta
		if u["_ltimer"] >= 4.0:
			u["_ltimer"] = 0.0
			var le := _targeting._pick_enemies_of(u)
			if not le.is_empty():
				var lv2 = le[_battle_rng.randi() % le.size()]
				_damage._apply_damage_from(u, lv2, _shock_dmg(u), Color("#4dabf7"), 0.0, true)
				_lightning_sys._lightning_strike(lv2["pos"], Color("#aef0ff"))   # 天降闪电(自动电击)

# ============================================================================
#  龟壳·气场觉醒 储能相位机 (用户改造): store 6s → 释放(缓慢冲击波+衰减护盾) → cd 15s → 循环
# ============================================================================
const SHELL_STORE_SEC := 6.0          # 储能相位时长 (受伤转储能)
const SHELL_CD_SEC := 15.0            # 冷却相位时长 (不储能)
const SHELL_SW_RADIUS := 520.0        # 冲击波最大半径 (px)
const SHELL_SW_SEC := 1.8             # 冲击波扩张时长
const SHELL_SHIELD_SEC := 5.0         # 护盾流失时长

func _on_unit_death(u: Dictionary, killer) -> void:
	_free_head_badges(u)   # 死亡即释放头顶信息层(叠层/状态徽章池·防残留)
	# 泡泡盾: 挂盾对象阵亡(=盾随之破) → 爆裂对施法者全体敌2.0A魔法(封板L435·防对象死丢爆裂)
	if float(u.get("bubble_shield_until", 0.0)) > 0.0:
		_bubble_sys._bubble_shield_burst(u)
	# 冰霜团队护盾: 持盾者阵亡(=盾随之破) → 250码内敌 boom×ATK 魔法(用户2026-07-11)
	if float(u.get("frost_shield_until", 0.0)) > 0.0:
		_ice_sys._frost_shield_burst(u)
	# 财神聚宝盆: 任意单位阵亡 → 全场存活的财神龟 +9 金币 (设计"金币哗啦涌向财神龟")
	for f in _units:
		if f.get("alive", false) and f.get("id") == "fortune" and not is_same(f, u):
			f["gold"] += 9
			for _ck in range(3):
				_gold_fly_to(u["pos"] + Vector2(randf_range(-16.0, 16.0), randf_range(-10.0, 10.0)), f)
	# 海盗掠夺(被动·原版·死亡钩索): 【海盗龟自己阵亡】的瞬间 → 钩锁【击杀它的那个单位】·拉近至90码 + 25%击杀者最大生命【真实伤害】
	#   ★2026-07-10 修真bug: 原实装写成「任意敌人阵亡 → 存活海盗龟钩索【最近敌】」, 触发条件与目标都与原版不符。
	#   依据: 回合制原版逐字(pets.json passive.desc)「死亡时钩锁击杀者，同样造成25%最大生命值真实伤害」
	#         + 用户〖#15〗「掠夺我是说被动的【原版】海盗被动」+ 用户〖2026-07-10〗「死亡的伤害值同上」。
	if u.get("id", "") == "pirate" and not u.get("is_summon", false) and killer is Dictionary and killer.get("alive", false) and not is_same(killer, u):
		_pirate_sys._pirate_death_grapple(u, killer)                         # 死亡钩索: 甩钩爪(带链)抓击杀者→拉回尸位90码+25%击杀者maxHp真伤
	# 缩头随从先死 → 主人永久继承"强化随从"增益(可多次随从累积·把力量传给主人)
	if u.get("minion_kind", null) != null:
		var _hm = u.get("summon_owner", null)
		if _hm != null and _hm.get("alive", false) and str(_hm.get("id", "")) == "hiding":
			_hiding_sys._hiding_apply_buff(_hm, -1.0)
			_hiding_sys._hiding_legacy_vfx(u["pos"], _hm)                    # 遗志: 金光点从随从尸位飞回主人入体(2026-07-17)
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _targeting._enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_damage._apply_damage_from(u, o, _resolve_dmg(u, per, o, true), Color("#ff8ad8"), 0.0, false, true)   # 魔法伤(蓝字·吃魔抗·封板"魔法"·用户2026-07-15纠错·原raw=true真伤=错)
		if u.get("summon_kind", "") == "candybomb":   # 糖果炸弹死亡: 大糖爆+震屏+糖泡四溅(用户2026-07-14参照海盗船完整呈现)
			_burst_vfx("res://assets/sprites/vfx/candy-burst.png", u["pos"], 340.0, 0.4)
			_shake(JUICE_SHAKE_HEAVY)
			for _cb in range(10): _candy_sys._candy_bomb_bubble(u)
		_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 130.0)
	# 靶向器055: 带弹宿主死亡 → 朝所有敌方发钩 → 眩晕0.5s → 拉向携带者 → 聚拢一次爆炸(用户2026-08-01)。
	# ★放在这里(与骷髅爆炸同一段死亡结算)而不是塞进演出 tween 里 —— 见 hookbomb_system.gd 文件头。
	_hookbomb_sys._hb_on_death(u)
	if u.get("boom_pct_true", 0.0) > 0.0:                 # 032骷髅死亡: 200码内敌各受其%最大生命真伤
		var _br: float = float(u.get("boom_radius", 200.0))
		for _bo in _targeting._enemies_of(u):
			if _bo.get("alive", false) and (_bo["pos"] - u["pos"]).length() <= _br:
				_damage._apply_damage_from(u, _bo, int(float(_bo["maxHp"]) * float(u["boom_pct_true"])), Color("#8affa0"), 0.0, true, true)
		_necro_burst(u["pos"], _br)
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and is_same(o.get("summon_owner", null), u) and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				_hide_summon_nodes(o)
	# (删死亡同步·用户2026-07-16反转07-11拍板: 水晶球不随主人阵亡, 继续战斗)
	# 赛博龟阵亡 → 浮游炮组装成机甲
	if u["id"] == "cyber":
		_cyber_sys._cyber_assemble_mech(u)
	# (删: 原"死亡给对面财神+2金币"=不在规格的stray bug; 数据是每2.5s+2深海币meta, 非死亡金币)
	# 猎人猎杀: 击杀者是猎人 → 窃取属性+叠吸血(含金色精华VFX)
	if killer != null and killer.get("alive", false) and killer.get("id", "") == "hunter":
		_hunter_sys._hunter_apply_steal(killer, u)
	# 幽灵强化怨灵: 死亡时再诅咒全体敌一次
	if u["id"] == "ghost":
		var _ce: Array = _targeting._enemies_of(u)   # 死亡诅咒: 全体→随机1个(用户2026-07-28削弱)
		if not _ce.is_empty(): _damage._add_curse(_ce[_battle_rng.randi() % _ce.size()], BUFF_SEC, u)
	# 海盗掠夺被动已按封板L354/382删除(掠夺去掉→海盗龟无被动·场外船是共用演出载体·待用户确认是否补新被动)

# ============================================================================
#  召唤系统 (3D 化: billboard 立绘/色块 + blob影, 走同一 _tick_unit) — 逻辑 1:1 搬自 2D 版
# ============================================================================
# 缩头随从候选池。★2026-07-11 用户拍板:「缩头乌龟只能召唤A及以下的」「确保涵盖所有A，B，C的」
#   → 不再手挑名单, 改为【运行时从稀有度动态生成】: 全部 A/B/C 稀有度的龟 (当前 19 只), 天然排除 S/SS/SSS。
#   这样以后加龟或改稀有度也永远覆盖全 A/B/C, 不会漏也不会混进高稀有度。守卫: tests/verify_hiding_pool.gd。
#   下面的常量只作【数据缺失时的兜底名单】(全是 A/B/C, 不含 headless)。
const HIDING_POOL := ["basic", "stone", "bamboo", "ninja", "dice", "rainbow", "hunter", "pirate", "candy", "bubble", "line"]

func _face_screen_dir(node: Node3D, world_from2d: Vector2, world_to2d: Vector2) -> void:   # 立牌朝相机+屏幕内指向 from→to 方向(钩爪尖朝行进)
	if _cam == null: return
	var d: Vector2 = _cam.unproject_position(_world_pos(world_to2d, 1.0)) - _cam.unproject_position(_world_pos(world_from2d, 1.0))
	if d.length() < 1.0: return
	var tf: Transform3D = node.global_transform
	tf.basis = _cam.global_transform.basis * Basis(Vector3(0, 0, 1), atan2(-d.y, d.x) - PI / 2.0)
	node.global_transform = tf

func _tick_cyber_drones(u: Dictionary, delta: float) -> void:   # 浮游炮纯视觉系统(用户2026-07-15: 非实体·环绕跟飞+攻击动作·数量只是计数)
	var arr: Array = u.get("_drones", [])
	var want: int = int(u.get("drone_n", 0)) if u.get("alive", false) else 0
	var dtex: Texture2D = load("res://assets/sprites/vfx/cyber-drone.png")
	while arr.size() < want:                                      # 新炮淡入
		var s := Sprite3D.new()
		s.texture = dtex
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false; s.transparent = true
		s.pixel_size = (26.0 * WS) / float(maxi(1, dtex.get_height()))
		s.modulate = Color(1, 1, 1, 0.0)
		s.position = _world_pos(u["pos"], 1.5)
		_world.add_child(s)
		var ft := _reg_tween(); ft.tween_property(s, "modulate:a", 1.0, 0.3)
		arr.append({"spr": s, "fire_t": 1.6 * randf(), "ph": randf() * TAU})
	while arr.size() > want:
		var od: Dictionary = arr.pop_back()
		if is_instance_valid(od.get("spr")): (od["spr"] as Sprite3D).queue_free()
	u["_drones"] = arr
	if arr.is_empty(): return
	var base_a: float = _t * 0.55                                 # 编队缓慢公转
	var n: int = arr.size()
	for i in range(n):
		var d: Dictionary = arr[i]
		var spr = d["spr"]
		if not is_instance_valid(spr): continue
		var ring: int = i % 2                                     # 双环编队(内48px/外76px交错)
		var r_px: float = 48.0 + 28.0 * float(ring)
		var aa: float = base_a * (1.0 if ring == 0 else -0.8) + TAU * float(i) / float(maxi(1, n))
		var off: Vector2 = Vector2(cos(aa), sin(aa)) * r_px
		var hh: float = 1.35 + 0.25 * float(ring) + sin(_t * 2.2 + float(d["ph"])) * 0.1   # 悬浮上下浮动
		spr.position = spr.position.lerp(_world_pos(u["pos"] + off, hh), clampf(delta * 6.0, 0.0, 1.0))
		spr.flip_h = off.x < 0.0
		d["fire_t"] = float(d["fire_t"]) - delta                  # 各自1.6秒射击(错峰)
		if d["fire_t"] <= 0.0:
			d["fire_t"] = 1.6 + randf() * 0.2
			var es := _targeting._pick_enemies_of(u)
			var tgt = null
			if not es.is_empty(): tgt = es[_juice_rng.randi() % es.size()]
			if tgt != null and tgt.get("alive", false):
				var mz := Sprite3D.new()                          # 攻击动作: 炮口青闪+后坐脉冲
				mz.texture = VfxTex._make_fire_glow_tex()
				mz.billboard = BaseMaterial3D.BILLBOARD_ENABLED; mz.shaded = false; mz.transparent = true
				mz.pixel_size = 0.006
				mz.modulate = Color(0.5, 0.95, 1.0, 0.9)
				mz.position = spr.position
				_world.add_child(mz)
				var mt := _reg_tween(); mt.tween_property(mz, "modulate:a", 0.0, 0.12); mt.tween_callback(mz.queue_free)
				var rc := _reg_tween(); rc.tween_property(spr, "scale", Vector3(0.82, 0.82, 0.82), 0.05); rc.tween_property(spr, "scale", Vector3.ONE, 0.1)
				var p := Sprite3D.new()                           # 小而淡的青色弹(用户Q14: 防20炮糊屏)
				p.texture = VfxTex._make_bolt_texture(Color(0.55, 0.95, 1.0))
				p.billboard = BaseMaterial3D.BILLBOARD_ENABLED; p.shaded = false; p.transparent = true
				p.pixel_size = 0.008
				p.modulate = Color(1, 1, 1, 0.65)
				p.position = spr.position
				_world.add_child(p)
				var dmg: int = _resolve_dmg(u, u["atk"] * 0.25 * 0.12, tgt, false)   # 12%×炮攻(25%A)物理
				_projectiles.append({"node": p, "from": p.position, "tgt": tgt, "dmg": maxi(1, dmg), "col": Color("#9fe8ff"),
					"src": u, "t": 0.0, "dur": clampf((u["pos"] - tgt["pos"]).length() / 900.0, 0.15, 0.5),
					"basic_onhit": false, "oriented": false, "card_spin": false, "dtype": "physical", "drone_shot": true})

func _art_faces_right(u: Dictionary) -> bool:
	if ART_FACES_RIGHT.has(str(u.get("id", ""))):
		return true
	return u.get("is_summon", false) and ART_FACES_RIGHT.has(str(u.get("summon_kind", "")))

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
		u["_decay_acc"] = float(u.get("_decay_acc", 0.0)) + u["maxHp"] * u["self_decay"] * delta
		if float(u["_decay_acc"]) >= 1.0:
			var _dv: int = int(floor(float(u["_decay_acc"])))
			u["_decay_acc"] = float(u["_decay_acc"]) - float(_dv)
			_damage._apply_damage(u, _dv, Color("#c8b0ff"), null, "tru", true)
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
				var nw = _spawn._spawn_summon(u, "worm", u["maxHp"], u["atk"], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
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
			var es := _targeting._pick_enemies_of(u)
			if es.is_empty(): return
			var o = es[_battle_rng.randi() % es.size()]
			_ballistics._fire_bolt_from(u, o, _atk_dmg(u, u.get("special_scale", 0.2), o), Color("#ffb05c"))
			_skill_ring(o["pos"], Color(1.0, 0.6, 0.2, 0.45), 40.0)
		"ship_shot":                                          # 海盗船普攻: 射最近敌0.4A(封板L379·攻速0.8由special_cd驱动)
			var st = _targeting._nearest_enemy(u)
			if st == null: return
			_muzzle_flash(u["pos"], (st["pos"] - u["pos"]).normalized(), Color("#ffd9a0"))
			_ballistics._fire_bolt_from(u, st, _atk_dmg(u, u.get("special_scale", 0.4), st), Color("#e8c07a"))
		"ray":                                            # 水晶球射线(2026-07-16重做): 蓄力聚能→两段厚冰蓝光束·伤害不变(2段×0.5A魔法+2层结晶)
			var t = _targeting._nearest_enemy(u)
			if t == null: return
			_crystal_sys._crystal_ray_vfx(u, t, func(sr: Dictionary, tr: Dictionary, last: bool) -> void:
				_damage._apply_damage_from(sr, tr, _atk_dmg(sr, sr.get("special_scale", 1.0), tr, true), Color("#9bdcff"), 0.0, true)
				if last: _crystal_sys._crystal_stack(sr, tr, 2))   # 与本体共享满5引爆(引爆改吃魔抗)
		"random_hit":
			var es2 := _targeting._pick_enemies_of(u)
			if es2.is_empty(): return
			var o2 = es2[_battle_rng.randi() % es2.size()]
			_ballistics._fire_bolt_from(u, o2, _atk_dmg(u, u.get("special_scale", 0.25), o2), Color("#9bf0ff"))
		"mech_blast":
			var low = null; var lv := INF
			for o in _targeting._pick_enemies_of(u):
				if o["hp"] < lv: lv = o["hp"]; low = o
			if low == null: return
			_bolt_line(u["pos"], low["pos"], Color("#9bf0ff"))
			for i in range(2):
				if not low["alive"]: break
				_damage._apply_damage_from(u, low, _atk_dmg(u, u.get("special_scale", 1.5) * 0.5, low), Color("#9bf0ff"))


func _apply_cam_zoom() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	_cam_zoom = clampf(_cam_zoom, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
	# ★缩放锚点要跟着平移走(CAM_TARGET + _cam_pan) —— 否则拉近后平移到边角再缩放,
	#   视野会被"吸"回战场原点, 手感很怪(用户 2026-07-21 要的视角移动)。
	var anchor: Vector3 = CAM_TARGET + _cam_pan
	_cam_zoom_base = anchor + (_cam_base - CAM_TARGET) / _cam_zoom
	if _shake_amp <= 0.0001:
		_cam.position = _cam_zoom_base   # 不在震屏中→立即应用(震屏中由 _render._update_camera_shake 每帧应用)

## 按屏幕拖动量平移视角。dx/dy = 本次鼠标/手指的屏幕位移(像素)。
## 相机 look_at 后 basis 固定, 所以直接用 basis 的右向量 + 地面上的"屏幕上方"向量组合。
## 缩放时位移量要 / _cam_zoom 才有一致手感(拉近时同样的手指位移应该走更少的世界距离)。
func _cam_pan_by(dx: float, dy: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var b := _cam.global_transform.basis
	var right: Vector3 = b.x                                  # 屏幕右
	var fwd: Vector3 = -b.z                                   # 相机朝向
	var ground_up: Vector3 = Vector3(fwd.x, 0.0, fwd.z)       # 投到地面 = 屏幕"上方"
	if ground_up.length() < 0.001:
		ground_up = Vector3(0.0, 0.0, -1.0)
	ground_up = ground_up.normalized()
	right = Vector3(right.x, 0.0, right.z).normalized()
	# 屏幕位移 → 世界位移(拖动方向 = 内容跟手, 所以取负)
	var k: float = 0.021 / maxf(0.2, _cam_zoom)
	_cam_pan -= right * (dx * k)
	_cam_pan += ground_up * (dy * k)
	# clamp 到方形范围, 防止拖到看不见战场
	_cam_pan.x = clampf(_cam_pan.x, -PAN_LIMIT, PAN_LIMIT)
	_cam_pan.z = clampf(_cam_pan.z, -PAN_LIMIT, PAN_LIMIT)
	_cam_pan.y = 0.0
	_apply_cam_zoom()   # 平移并进 _cam_zoom_base, 由它统一落到 _cam.position

## 视角复位(双击/换路时用)
func _cam_pan_reset() -> void:
	_cam_pan = Vector3.ZERO
	_apply_cam_zoom()


func _pinch_dist() -> float:
	if _touch_pts.size() < 2:
		return -1.0
	var ks: Array = _touch_pts.keys()
	return (_touch_pts[ks[0]] as Vector2).distance_to(_touch_pts[ks[1]] as Vector2)

func _shake(amp: float) -> void:
	if amp <= 0.0:
		return
	_shake_amp = minf(JUICE_SHAKE_MAX, maxf(_shake_amp, amp))
	_shake_t = 0.0

# 触发顿帧: 取较大值 (短事件不覆盖更长的卡顿)
func _add_hitstop(sec: float) -> void:
	if sec > _hitstop:
		_hitstop = sec

# 受击闪白 + 轻压扁 (Phase4 替代旧 _vfx._flash; 状态驱动, 不叠 tween)
# 虚化残影: 复制本体当前帧→渐隐(青紫)·移动时成拖尾(用户2026-07-11)
func _spawn_phase_afterimage(spr) -> void:
	if not is_instance_valid(spr):
		return
	var ai := Sprite3D.new()
	ai.texture = spr.texture
	ai.frame = 0                      # ★先归零再改帧网格(同族)
	ai.hframes = spr.hframes
	ai.vframes = spr.vframes
	ai.frame = clampi(int(spr.frame), 0, maxi(0, int(ai.hframes) * int(ai.vframes) - 1))
	ai.pixel_size = spr.pixel_size
	ai.billboard = spr.billboard
	ai.flip_h = spr.flip_h
	ai.shaded = false
	ai.transparent = true
	ai.texture_filter = spr.texture_filter
	ai.global_position = spr.global_position
	ai.scale = spr.scale
	ai.modulate = Color(0.55, 0.45, 1.0, 0.5)
	_world.add_child(ai)
	var tw := _reg_tween()
	tw.tween_property(ai, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ai.queue_free)

var _hitring_tex: ImageTexture = null
var _spark_tex: ImageTexture = null   # #6修: 命中辉光改 Image 真圆(原 GradientTexture2D 露方角)
var _reticle_tex: ImageTexture = null     # 瞄准准星(圆环+四刻线) — 瞄准镜054一瞬瞄准闪专用
var _bracket_tex: ImageTexture = null      # 目标锁定角标([ ]四角方括号) — 持续标记专用(靶向器055/飞镖056), 跟054准星区分
var _pellet_tex: ImageTexture = null       # 小圆铅丸(霰弹弹珠) — 真圆非方角
func _reticle_flash(tgt: Dictionary, col: Color) -> void:
	if tgt == null: return
	if _reticle_tex == null: _reticle_tex = VfxTex._make_reticle_texture(Color(1, 1, 1, 1))
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
	if _bracket_tex == null: _bracket_tex = VfxTex._make_target_bracket_texture(Color(1, 1, 1, 1))
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
	var tex := VfxTex._make_fire_glow_tex()   # ② 上半身绿辉光overlay(裹住脉动)
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
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
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
		r.texture = VfxTex._make_ring_texture(Color(0.45, 1.0, 0.55, 1.0))
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
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
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

func _spawn_fireball(src: Dictionary, tgt: Dictionary, dmg: int, burn: int) -> void:
	if tgt == null: return
	var g := VfxTex._make_fire_glow_tex()
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
func _spawn_bamboo_arrow(src: Dictionary, tgt: Dictionary, dmg: int, grow: float = 0.0) -> void:
	if tgt == null: return
	var p := Sprite3D.new()
	p.texture = load("res://assets/sprites/vfx/bamboo-arrow.png")
	p.pixel_size = 0.03
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # wisp_dir手动basis(箭头朝目标屏幕方向); 原 billboard+rotation.z 是坏写法(001飞斩教训)
	p.shaded = false; p.transparent = true
	var from := _world_pos(src["pos"], 1.0)
	p.position = from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": from, "tgt": tgt, "dmg": dmg, "col": Color("#a8ffb0"),
		"src": src, "t": 0.0, "dur": clampf(src["pos"].distance_to(tgt["pos"]) / 850.0, 0.14, 0.5),
		"bamboo": true, "wisp_dir": true, "wisp_off": PI / 2.0, "bamboo_grow": grow,   # bamboo-arrow.png 是96x24横向贴图(+X朝前)
	})

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
	var tex := VfxTex._make_fire_glow_tex()
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
	if _spark_tex == null: _spark_tex = VfxTex._make_glow_texture()
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

func _make_glow_quad(size_m: float) -> QuadMesh:
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD            # 加色叠加 → 重叠处更亮 (火焰/能量发光)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = VfxTex._make_fire_glow_tex()
	dm.vertex_color_use_as_albedo = true                    # 让 color_ramp 给每颗粒子上色
	dm.albedo_color = Color(1, 1, 1, 1)
	var qm := QuadMesh.new()
	qm.size = Vector2(size_m, size_m)
	qm.material = dm
	return qm

func _check_end() -> void:
	if OS.has_environment("VFXPREVIEW"): return   # 预览模式不判胜负
	if _is_dual_lane_mode():
		_dl_sys._dl_flow_check()
		return
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u.get("is_trainer", false):
			continue   # 训龟大师不计胜负(同 _dl_sys._dl_side_alive; 漏这条会导致"打不死它→永远不结束")
		if u["alive"] and not u.get("is_summon", false):   # 召唤体不计入胜负判定
			# ★用有效阵营: 被侵入者仍按【原阵营】计。否则侵入掉对方最后一只 →
			#   right_alive==0 → 单路/评审模式【瞬间判胜】(双路的 _dl_sys._dl_side_alive 早已这么做, 这里一直漏着)
			if _eff_side(u) == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		var won: bool = right_alive == 0
		_settle_season(won)        # 结果喂赛季 (命/币/胜场/XP/ghost), 守卫一次性
		_hud._show_banner(won)

# 赛季结算 (1:1 搬自 2D RealtimeBattleScene._settle_season): 闭环把胜负喂回 GameState 养成
func _settle_season(won: bool) -> void:
	var gs = get_node_or_null("/root/GameState")
	# ★新手教程沙盒(用户2026-07-23:「不获得任何奖励」): 直接不喂赛季。
	#   放最前面 —— 下方所有 season_total_battles++/coins+= 都在这行之后, 一个都到不了。
	if gs != null and bool(gs.get("tutorial_active")):
		_had_season = false
		return
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
		_last_reward = 8 + int(gs.hearts) + 2 * lost_hearts + (6 if won else 0)   # ★深海币砍到约1/3(用户2026-07-18"太多要减"): 原25+2命+5失命+15胜≈胜60/负45→一场买20件毫无取舍; 新≈满命胜22/负17·残命胜29·一场买5-7件(逆风补偿保留·糖果罐大奖不动)
		gs.season_total_battles += 1
		gs.add_season_xp(2)                          # 每场 +2 大轮经验
		gs.candy_jar_add(1 if won else 4)            # 糖果罐(选糖果龟当统领才有): 赢+1输+4封顶30(封板L392·逆风快攒)
		if won:
			gs.season_wins += 1
			gs.season_eggs_killed += 1
			if gs.get("left_team") is Array and (gs.left_team as Array).is_empty():
				var _ldr: Array = gs.get("season_leaders")
				gs.left_team.assign(_ldr.slice(0, 3))
			var _gid := "g_%d" % int(gs.season_id)   # ★稳定id(用户2026-07-18"同一对手连续2把匹配到"): 原带_t战斗秒数→每场upload都是新id但同阵→池里同队堆几十个id→排除最近3个没用. 改按大轮id稳定=同一玩家阵容恒为1个ghost_id, 配pool_add去重→排除最近3场真生效
			var _av := str(gs.season_leaders[0]) if (gs.season_leaders as Array).size() > 0 else "basic"
			Backend.upload_ghost(Backend.build_ghost_snapshot(_gid, {"name": "玩家阵容", "avatar": _av, "id": _gid}))
	# 奇械羁绊【铸币】: 本场累积的深海币(有硬上限, 见 gadget_synergy_system.gd)一次性进账。
	# ★加在 `_last_reward` 上而不是直接加 meta —— 结算屏显示的就是 _last_reward,
	#   直接加 meta 会出现"钱多了但结算屏没说是哪来的", 玩家看不到因果。
	var _minted: int = _gadget_syn.minted("left")
	if _minted > 0:
		_last_reward += _minted
	_gadget_syn.reset_match()
	_food_syn.reset_match()      # 食物成长: 以【场】重置(用户 2026-08-04) —— 跨路保留, 换场清零
	_potion_syn.reset_match()    # 药水战利品: 同上
	_relic_syn.reset_match()     # 遗物远古之力: 同上
	gs.meta_deepsea_coins += _last_reward
	# #7 战绩同步: 实时战斗原来不写战绩 → RecordScene 永远空。这里补记本场(总场/胜计数 + match_history 一条)。
	gs.battles_total += 1
	if won:
		gs.battles_won += 1
	gs.record_match("win" if won else "lose", _resolve_left(), "实时", int(_t))
	if not gs.match_history.is_empty():
		gs.match_history[0]["ts"] = int(Time.get_unix_time_from_system())   # 相对时间戳 (RecordScene _rel_time 用)
	gs.save()

## ★装备给的【永久射程%】取值口 (2026-08-03 批2·方案书 D7)。
## 为什么不直接把倍率乘进 u["atk_range"]:
##   atk_range 全库有 11 个写入点(双生/熔岩/机甲的形态切换、无头强化窗口、破浪矛 ±50 …),
##   每一次形态切换都会把 atk_range 整个覆盖掉 —— 就地乘进去的加成会被【静默抹掉】,
##   而且升星/换路重建单位时会【重复乘】。所以基础值仍归 atk_range, 加成走独立的 range_perm,
##   在【判定的那一刻】才相乘。同理移速走 move_perm(既有的 move_buff_mult 是限时通道, 装备要永久)。
## ★2026-08-05 加 flat 通道 `range_add`(码), 与 `range_perm`(倍率) 并存 ——
##   用户给 065 鲨肝油 写的是"提供 50 射程"这样的**绝对值**, 而原来只有百分比字段。
##   顺序是【先加后乘】: 基础 + 加成码数, 再整体乘百分比。理由同上面那段注释 ——
##   两条都不能就地写进 atk_range(会被形态切换覆盖、被换路重建重复累加)。
##   ⚠ flat 对近战收益远大于远程: 近战基础 70(战斗里抬到 >=100), 远程 400~450,
##     所以 +50 码 = 近战约 +50% / 远程约 +12%。这是有意的, 不是没注意到。
func _eff_range(u: Dictionary) -> float:
	return (float(u.get("atk_range", 70.0)) + float(u.get("range_add", 0.0))) * float(u.get("range_perm", 1.0))


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

# #2 伤害统计面板: 结算时显双方各龟 输出/承受/回复/护盾 (统计在 _damage._apply_damage* / _damage._heal / _damage._grant_shield 累计)
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
		if _eff_side(u) == side:
			out.append(u)
	return out





## 一行统计快照 = 纯标量 plain dict, 键名与 _stats_column 读的完全一致 → 快照行可直接喂给同一个渲染函数.
## 【不存单位字典本身】: 单位字典互相引用会成环, 留着既漏内存又踩深比较坑(见 _arr_has_unit 注释).
## 显示名兜底: name 是【空串】时 Dictionary.get 照样返回空串(不走默认值) → 统计表出空白行.
## 冷启动/兜底阵容的 spec 可能没 id, 于是 name/id 双空; 真实对局玩家选过龟不会走到这.
func _st_name(u: Dictionary) -> String:
	var n := str(u.get("name", ""))
	if n != "": return n
	n = str(u.get("id", ""))
	return n if n != "" else "未知龟"

func _st_row(u: Dictionary) -> Dictionary:
	return {
		"name": _st_name(u), "is_summon": bool(u.get("is_summon", false)),
		"rarity": str(u.get("rarity", "C")), "alive": bool(u.get("alive", true)),
		"hp": maxf(0.0, float(u.get("hp", 0))), "maxHp": float(u.get("maxHp", 0)),
		"_st_dealt": int(u.get("_st_dealt", 0)), "_st_taken": int(u.get("_st_taken", 0)),
		"_st_heal": int(u.get("_st_heal", 0)), "_st_crit": int(u.get("_st_crit", 0)),
		"_st_kills": int(u.get("_st_kills", 0)),
	}

## 本路打完 → 把当前 _units 的统计冻成快照存进 _st_lane_hist(供结算表翻页看前面战场).
func _st_snapshot_lane(lane: String) -> void:
	if lane == "" or lane == "done":
		return
	var snap := {"lane": lane, "left": [], "right": []}
	for u in _units:
		var sd := str(u.get("side", ""))
		if sd == "left" or sd == "right":
			(snap[sd] as Array).append(_st_row(u))
	_st_lane_hist.append(snap)

## 合计页: 按 (阵营, 名字, 该路内同名第几个) 归并求和 —— 同名小将不会挤成一行, 跨路的"同一只"能对上.
## 剩余血量取【最后出现的那一路】的值(累加没意义).
func _st_merge_all(pages: Array, side: String) -> Array:
	var order: Array = []            # 保序: 先出现的排前面
	var acc: Dictionary = {}         # key(String) -> row
	for pg in pages:
		var seen: Dictionary = {}    # 本路内同名计数
		for r in (pg[side] as Array):
			var nm: String = str(r["name"])
			var n: int = int(seen.get(nm, 0)); seen[nm] = n + 1
			var key := "%s#%d" % [nm, n]
			if not acc.has(key):
				acc[key] = _st_row(r); order.append(key)   # _st_row 对 plain row 幂等 = 拷贝
			else:
				var a: Dictionary = acc[key]
				for f in ["_st_dealt", "_st_taken", "_st_heal", "_st_crit", "_st_kills"]:
					a[f] = int(a[f]) + int(r[f])
				a["alive"] = r["alive"]; a["hp"] = r["hp"]; a["maxHp"] = r["maxHp"]   # 血量取最后一路
	var out: Array = []
	for k in order:
		out.append(acc[k])
	return out

## 📊 战中统计面板开关 (1:1 回合制 _on_dmg_stats_toggle)
func _on_dmg_stats_toggle() -> void:
	_dmg_stats.setup(_ui_layer, _stat_units)
	_dmg_stats.toggle()




const _LANE_CN := {"top": "上路", "bottom": "下路", "final": "终极"}

## 切页: 只显第 idx 页, 页体高度按当前页自适应(Control 不会自己撑高 → 手动扛 min height).
func _stats_show_page(bodies: Array, btns: Array, idx: int) -> void:
	for i in range(bodies.size()):
		(bodies[i] as Control).visible = (i == idx)
	for i in range(btns.size()):
		(btns[i] as Button).add_theme_color_override("font_color", Color("#ffd93d") if i == idx else Color("#8b949e"))
	_stats_fit_body(bodies, idx)

## 切页后重排: Control 不会被子节点撑高 → 手动把 body 顶到本页尺寸, 再把 scroll 夹到「屏底剩余高度」以内.
func _stats_fit_body(bodies: Array, idx: int) -> void:
	await get_tree().process_frame
	if idx < 0 or idx >= bodies.size(): return
	var c: Control = bodies[idx]
	if not is_instance_valid(c) or not is_instance_valid(c.get_parent()): return
	var body: Control = c.get_parent()
	body.custom_minimum_size = c.size
	var scroll := body.get_parent()
	if not (scroll is ScrollContainer): return
	# ★★2026-08-02 结算页改成【居中卡片】后, 这里【绝不能再给面板设绝对坐标】——
	#   旧版末尾会调 _center_stats_panel(panel) 把面板摆到写死的 y, 而它现在是
	#   VBoxContainer 的子节点 ⇒ 两套定位打架, 实拍表现是【「返回主菜单」按钮画在表格中间】。
	#   位置一律交给容器算, 这里只负责"页体多高、滚动区裁到多高"。
	# 可用高 = 视口高 − 卡片其余部分(标题54+副标题20+数据块50+按钮46+间距/内边距 ≈ 320)
	var avail: float = maxf(120.0, get_viewport().get_visible_rect().size.y - 320.0)
	(scroll as ScrollContainer).custom_minimum_size = Vector2(c.size.x, minf(c.size.y, avail))

## 结算表的一队一列 —— 实现搬到 battle_hud.gd(纯 UI 表格构建, 属 HUD 层)。
## ★搬的理由不是好看: 留在这里会把上帝文件顶破 arch_budget(8600 行)。
func _stats_column(header: String, units: Array, hc: Color) -> Control:
	return _hud._stats_column(header, units, hc)


## 相机输入(滚轮缩放 / 双指捏合 / 拖动平移)。
##
## 历史(留着, 因为它解释了为什么这段是【独立函数】而不是内联在 _unhandled_input 里):
##   抽出来原本是为了"暂停中也能拖镜头" —— 根节点 process_mode=INHERIT 跟 root 的 PAUSABLE 走,
##   暂停时 can_process()=false, _unhandled_input 压根不被调用。这是测试人员 2026-07-22 说的
##   "点暂停后鼠标无法拖动"的真根因(2×2 探针实测: 单改暂停幕 mouse_filter 无效,
##   process_mode 是唯一阻断点)。当时用一个 ALWAYS 的 _CamInputRelay 转发进来。
##   2026-07-30 暂停按钮按用户要求移除, 那个中继随之删掉 —— 但本函数保持独立,
##   ★若将来又加回任何暂停机制, 只要把中继加回来指向这里即可, 不用重新拆。
## 返回 true = 事件已被相机消费, 调用方不要再往下走。
func _cam_handle_input(event: InputEvent) -> bool:
	# ── 战场缩放(用户2026-07-18): PC滚轮 / 移动双指捏合 · 各模式通用, 最先处理 ──
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom *= 1.10; _apply_cam_zoom(); return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom /= 1.10; _apply_cam_zoom(); return true
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_pts[event.index] = event.position
			if _touch_pts.size() == 1:
				_pan_from = event.position    # 单指按下 → 记起点(供拖动/点选判定)
				_pan_moved = false
		else:
			_touch_pts.erase(event.index)
			if _pan_moved:
				_pan_moved = false
				_pinch_prev = _pinch_dist()
				return true                        # 刚才是拖视角, 松手不当点选
		_pinch_prev = _pinch_dist()          # 手指数变化→重置捏合基线
		# ★捏合抬指后必须重置平移起点, 否则: 捏合期间 _pan_from 还是最初落指点(距离远大于阈值),
		#   抬起一根手指的瞬间 _touch_pts 降到 1 → 平移分支立刻判定"已超阈值" →
		#   剩下那根手指的移动被当成拖视角直接接管。要求重新落指才允许平移。
		if _touch_pts.size() == 1:
			for _k in _touch_pts:
				_pan_from = _touch_pts[_k]
			_pan_moved = false
		if _touch_pts.size() >= 2: return true    # 双指=缩放态, 不放行到点选(防捏合误开面板)
	elif event is InputEventScreenDrag:
		_touch_pts[event.index] = event.position
		if _touch_pts.size() >= 2:
			var d := _pinch_dist()
			if _pinch_prev > 0.0 and d > 0.0:
				_cam_zoom *= d / _pinch_prev; _apply_cam_zoom()
			_pinch_prev = d
			return true
	# ── 视角平移(用户 2026-07-21:「手机端触屏拖动移动摄像机, 电脑端按住推动」) ──
	#   ★必须插在【捏合之后、地图编辑器/放置阶段之前】: 插太前会抢掉捏合缩放,
	#     插太后收不到事件(那些分支都 return)。
	#   ★与点选共存的关键: 按下先记起点, 位移超过 PAN_THRESHOLD 才算拖动;
	#     没超阈值的抬起仍按点选处理(否则每次拖屏都会误开/误关详情面板)。
	# ★放置阶段正在拖龟摆位 → 镜头【完全让路】(用户 2026-07-22:「开局拖动是什么情况」)。
	#   机制: 按下时相机与放置逻辑各记各的状态; 鼠标一移超 PAN_THRESHOLD, 相机块就 _cam_pan_by()
	#   并【return true】→ _unhandled_input 当场返回 → 放置逻辑再也收不到后续 motion
	#   → 龟停在半路、镜头却跑了。所以只要 _edit_drag_unit 在手, 这里就直接放弃本事件。
	if _edit_drag_unit != null and _dl_state == "place":
		return false
	if not _map_editor:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pan_active = true; _pan_from = event.position; _pan_moved = false
			else:
				_pan_active = false
				if _pan_moved:
					_pan_moved = false
					return true      # 这是一次拖动, 不当点选(不开/关面板)
		# ★同时看 button_mask 与 _touch_seen:
		#   ① 只看 _pan_active 的话, release 一旦落在任何 MOUSE_FILTER_STOP 控件上(详情面板/头像卡/
		#      暂停幕/结算幕)就被 GUI 吃掉、永远到不了这里 → _pan_active 永久卡 true →
		#      之后不按任何键、纯移鼠标镜头也一直跟着跑。放置阶段的拖拽早就做了这层兜底, 平移漏了。
		#   ② emulate_mouse_from_touch 默认开 → 单指拖同时产生 ScreenDrag 和模拟 MouseMotion,
		#      两条分支各跑一次 _cam_pan_by → 手机上平移速度是设计值的 2 倍
		#      (InventoryScene.gd:639 记过这个坑, 平移这次又踩)。收到过真触屏就不再认模拟鼠标。
		elif event is InputEventMouseMotion and _pan_active and _touch_pts.size() < 2 and not _touch_seen and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if not _pan_moved and event.position.distance_to(_pan_from) > PAN_THRESHOLD:
				_pan_moved = true
			if _pan_moved:
				_cam_pan_by(event.relative.x, event.relative.y)
				return true
		elif event is InputEventScreenDrag and _touch_pts.size() == 1:
			_touch_seen = true   # 真触屏 → 之后忽略模拟鼠标的平移(防 2× 速度)
			# 手机单指拖 = 移动视角(双指已在上面被捏合缩放接走)
			if not _pan_moved and event.position.distance_to(_pan_from) > PAN_THRESHOLD:
				_pan_moved = true
			if _pan_moved:
				_cam_pan_by(event.relative.x, event.relative.y)
				return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _cam_handle_input(event):
		return
	if _map_editor:   # 🖌 编辑器: 左键点/拖刷格(UI按钮的点击被按钮消费不会到这)
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_map_ed_paint(event.position)
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_map_ed_paint(event.position)
		return
	if event is InputEventKey and event.keycode == KEY_Q and not event.echo:
		if event.pressed:
			_aim._begin_q_aim()     # 按住 Q → 进入瞄准(指示器跟随鼠标·仅有主动技时·用户2026-07-26)
		else:
			_aim._end_q_aim_and_cast()   # 松开 Q → 朝鼠标方向释放
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			if _info_panel != null and is_instance_valid(_info_panel):
				_hud._close_info_panel()   # 详情面板开着 → ESC 先关面板 (不退场)
				return
			DEBUG_EDIT = false   # 离场重置, 不影响下次正常战斗
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return
	# 双路场内放置阶段: 拖我方(left)非蛋单位到位 (clamp 我方半场+避障); 「开打」钮在 GUI 层.
	if _dl_state == "place" and _is_dual_lane_mode():
		# ★放置阶段也要能点空白关面板 —— 否则这阶段开了详情面板就只剩 ESC 能关
		#   (用户 2026-07-21 要「点空白就退出」, 这条早退曾把它挡掉)。
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and _info_panel != null and is_instance_valid(_info_panel):
			var _pp: Vector2 = get_viewport().get_mouse_position() if get_viewport() != null else event.position
			if _edit_unit_at_screen(_pp) == null:
				_hud._close_info_panel()
		_dl_sys._dl_handle_place_input(event)
		return
	# 普通战斗模式: 点战场单位 (立绘头顶 unproject 命中) → 弹详情面板; 框上的点击由框自己的 gui_input 接.
	if not DEBUG_EDIT or not _edit_mode:
		# ★开/关面板必须在【抬起】判定, 而不是按下 —— 按下那一刻无法知道用户接下来是点还是拖。
		#   旧实现在 press 就开面板, 而 _pan_moved 的阈值 gate 只在 release 分支起作用,
		#   等于 gate 形同虚设: 从单位附近起手拖视角 → 面板瞬间弹出; 从空白起手拖 → 面板被关掉。
		#   单位命中半径 64px, 战场上几乎找不到"安全起手点" —— 这就是测试人员说的"放大和拖动冲突"。
		#   ★_pan_moved 由上面的平移分支在超过 PAN_THRESHOLD 时置位; 它在 release 分支被读完即清,
		#     所以这里要在【那之前】判断 —— 平移分支的 release 已经 return 掉了拖动情形, 能走到这里的
		#     必然是"没超过阈值"的抬起, 即真正的点选。
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _touch_pts.size() < 2:
			# ★命中用 get_mouse_position()(与龟爪光标同源=手指位置), 不用 event.position:
			#   安卓触摸时 event.position 会偏到龟爪【中心】(比爪尖/手指低约半个光标)→点不准(用户2026-07-11 #6)。桌面两者相等, 无影响。
			var _cpos: Vector2 = get_viewport().get_mouse_position() if get_viewport() != null else event.position
			var hit = _edit_unit_at_screen(_cpos)   # 复用既有 unproject 命中 (dist<64px, 取最近)
			if hit != null:
				_hud._show_unit_info_panel(hit)          # 点到单位→开/切详情
			elif _info_panel != null and is_instance_valid(_info_panel):
				_hud._close_info_panel()                 # 点空白→关(侧边版无backdrop)
		return
	# 🛠 调试场: 鼠标在战场(非面板)上 → 摆位/拖拽/删除. 面板按钮 mouse_filter=STOP 已在 GUI 层吃掉,
	#   故到 _unhandled_input 的鼠标事件 = 点在战场空白处 (安全当作摆位操作).
	if event is InputEventMouseButton:
		_debug._edit_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_debug._edit_handle_mouse_motion(event)

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
			# SHOT_PROBE=1: 每张连拍旁边打一行【游戏时钟】——
			# 做"时间对齐对比图"时，必须知道两张相邻截图之间真的隔了多少【游戏】秒。
			# `create_timer` 走的是未钳制的真实时间(CLAUDE.md §3.5)，靠它推时间轴会错。
			if OS.has_environment("SHOT_PROBE"):
				print("[shot] i=%d t=%.4f %s" % [i, _t, _tentacle_vfx.probe()])
			await get_tree().create_timer(step).timeout
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out)
	get_tree().quit()

# ============================================================================
#  装备实时实装 (59件 p2eq_*) — 1:1 搬自 2D 版 RealtimeBattleScene.gd (docs/design/装备实时实装规格.md)
#  数据驱动: 逐星属性复用 EquipStats.STATS; 事件钩子 on-hit/on-cast/on-target/on-dodge/on-kill/on-death/HP阈值 + 周期 tick(2.5s).
#  2.5D 适配: 逻辑/数值全照搬; VFX/坐标触点用 Phase3 的 3D 等价 (_vfx._float_text/_skill_ring/_bolt_line/_ballistics._fire_bolt_from/_spawn._spawn_summon).
#  分类标注: ✅完整 / ⚠改造(节拍·时长·站位) / 🚧TODO(简化) — 与 2D 版一致.
# ============================================================================
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")   # 装备逐星属性(2026-07-23 从回合制 phase2_equip_runtime 抽出的纯数据)
const EQ_TICK := 2.5            # 装备周期触发 = 1回合 ≈ 2.5 秒 (规格)

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
	if DEBUG_EDIT:                              # 调试场自由摆位: 单位带 _edit_equips(装备笔刷) → 应用, 无则裸装
		for _eu in _units:
			var _el: Array = _eu.get("_edit_equips", [])
			if _el is Array and not _el.is_empty():
				_eu["equips"] = _el.duplicate(true)
				for _e in _el:
					if _eu.get("eq_state") is Dictionary: _eu["eq_state"][str(_e.get("id", ""))] = {}
			else:
				_eu["equips"] = []
		return
	if _review_demo() and not _is_dual_lane_mode() and not OS.has_environment("EQDEMO_EQUIP") and (_dbg_equip_idx >= 0 or not REVIEW_EQUIP.is_empty()):
		# 调试场加装备(调试面板"装备开" 或 REVIEW_EQUIP非空·用户2026-07-11 #2): 给受审龟装 → 看装备显示(左右头像框)+效果
		var _eqs: Array = REVIEW_EQUIP
		if _eqs.is_empty():
			var _ids := _review_console._dbg_equip_ids()
			_eqs = [_ids[_dbg_equip_idx]] if (_dbg_equip_idx >= 0 and _dbg_equip_idx < _ids.size()) else []
		var _star: int = _dbg_star if _dbg_star > 0 else REVIEW_EQUIP_STAR
		for _ru in _units:
			if str(_ru.get("side","")) == "left" and str(_ru.get("id","")) == _review_turtle():
				var _rl: Array = []
				for _eid in _eqs:
					_rl.append({"id": str(_eid), "star": _star})
					_ru["eq_state"][str(_eid)] = {}
				_ru["equips"] = _rl
				break
		return
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
		# ★★这两处是【第 9 / 第 10 个】重建装备 dict 的点(前 8 个在 GameState 里)。
		#   093 香火石的香火充能 `chg` 跟着装备实例走、要跨对局保留 ⇒ 这里也必须带过去,
		#   否则"背包里是 20/4000"进了战斗就变成 0/4000, 而且不报错、没人会发现。
		#   取值走 GameState.eq_chg(非香火石恒为 0), 不手写字段名。
		if u.has("_dl_equips") and u["_dl_equips"] is Array and not (u["_dl_equips"] as Array).is_empty():
			for it in (u["_dl_equips"] as Array):   # 双路: leader/小将局外配的装(dual_lineup)优先 — 小将id共享__minion__, 只能走这里
				if it is Dictionary and it.has("id"):
					list.append({"id": str(it["id"]), "star": int(it.get("star", 1)), "chg": (gs.eq_chg(it) if gs != null else 0)})
		elif not use_demo and pe.has(key):
			if u["side"] == "left":
				for it in (pe[key] as Array):
					if it is Dictionary and it.has("id"):
						list.append({"id": str(it["id"]), "star": int(it.get("star", 1)), "chg": (gs.eq_chg(it) if gs != null else 0)})
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
			# ★EQDEMO_EQUIP2 = 再塞一件【不同 id】的装备(VFXLAB 调试台加的)。
			#   EQDEMO_COUNT 塞的是同一个 id, 而羁绊档位【按 id 去重】(synergy_system._calc_tiers)
			#   ⇒ 塞 9 件同款仍然只算 1 件、法器档位恒为 0、法力条一点都不涨。
			#   088/089/090 三件法器全靠法力条触发 ⇒ 没有这一行就永远看不到效果, 而且不报错。
			# ★2026-08-07 改成【逗号分隔的多件】: 枪羁绊 1 档要 **3 件不同 id**(法器只要 2 件),
			#   只塞一件 eq2 永远够不到枪档 ⇒ 金弹一发都出不来, 而且不报错。
			#   单件写法 `EQDEMO_EQUIP2=p2eq_089` 照旧生效(split 后就是一个元素)。
			if OS.has_environment("EQDEMO_EQUIP2"):
				for _e2 in OS.get_environment("EQDEMO_EQUIP2").split(","):
					if str(_e2).strip_edges() != "":
						list.append({"id": str(_e2).strip_edges(), "star": _est})
			u["equips"] = list
		for e in list:
			u["eq_state"][str(e["id"])] = {}

func _side_has_equip(side: String, item_id: String) -> bool:
	for o in _units:
		if _eff_side(o) == side and o["alive"]:
			for e in o.get("equips", []):
				if str(e["id"]) == item_id:
					return true
	return false

func _count_summons(side: String, kind: String) -> int:
	var c := 0
	for o in _units:
		if o.get("is_summon", false) and _eff_side(o) == side and o["alive"] and str(o.get("summon_kind", "")) == kind:
			c += 1
	return c

# 充能助手: 累加 amt, 达 cap → 清零(保留溢出)并触发 on_full.
func _cyeq_n(n: int) -> int:   # 装备叠层数: 浮游炮触发→减半(下限1); 本体触发→原值
	return (maxi(1, roundi(float(n) * 0.5)) if _equip_sys._eq_drone_halve else n)

func _chain_segment(u: Dictionary, from2d: Vector2, tgt: Dictionary, dmg: int) -> void:
	if not tgt.get("alive", false):
		return
	_chain_arc(from2d, tgt["pos"])
	_chain_zap(tgt["pos"])
	_damage._apply_damage_from(u, tgt, _resolve_dmg(u, float(dmg), tgt, true), Color("#7ecbff"), 0.0, false, true)   # 魔法伤害(过魔抗+吃魔穿)

# 蓄电前摇: 携带者身上聚一颗青电球(加速涨大变亮)+电环, ~0.4s 后射出连锁
func _chain_windup(u: Dictionary, si: int) -> void:
	var tex := VfxTex._make_fire_glow_tex()
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
	tf.tween_callback(_equip_sys._eq_chain_lightning.bind(u, si))

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
## ★★2026-08-07: 这里原来**完全不钳位**(`spr.frame = f`, f 由调用方给) ——
##   冒烟随机报的 `Index p_frame = 17 is out of bounds (vframes*hframes = 7)` 第三条就在这。
##   同族第 6 处了(v0.19.37 三处 + battle_render 两处 + 这里), 共同的形状都是
##   **"帧号来自别处、钳位却按别处的帧数(或干脆不钳)"**。
##   ⇒ 统一判据: 钳位只认**精灵自己的 hframes × vframes**(引擎校验的就是这个乘积)。
func _set_sprite_frame(spr: Sprite3D, f: int) -> void:
	if is_instance_valid(spr):
		spr.frame = clampi(f, 0, maxi(0, int(spr.hframes) * int(spr.vframes) - 1))



func _laser_blade_sweep(u: Dictionary, origin: Vector2, dir: Vector2, rng: float, half_deg: float) -> void:   # 120°扇形扫过·贴地(用户2026-07-12: 顶点在攻击者/朝目标/半径=射程, 正好盖120°伤害区)
	var base_ang: float = atan2(dir.y, dir.x)
	var tex: Texture2D = load("res://assets/sprites/vfx/laser-slash-anim.png")
	if tex == null: return
	var fh: int = maxi(1, int(tex.get_height()))          # 96 (方帧)
	var nfr: int = maxi(1, int(tex.get_width() / fh))     # 5
	var MAXR: float = 53.0                                 # 扇半径在纹理里的像素(顶点x≈1→maxR)
	var spr := Sprite3D.new()
	spr.texture = tex; spr.hframes = nfr; spr.frame = 0
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED; spr.axis = Vector3.AXIS_Y   # 贴地
	spr.shaded = false; spr.transparent = true
	spr.pixel_size = (rng * WS) / MAXR                     # maxR像素 = rng码(半径随射程)
	spr.rotation = Vector3(0.0, -base_ang, 0.0)            # 朝目标
	var center_off: float = (float(fh) * 0.5 - 1.0) / MAXR * rng   # 精灵中心相对顶点的码偏移
	spr.position = _world_pos(origin + dir * center_off, 0.1)
	_world.add_child(spr)
	var tw := _reg_tween()
	tw.tween_method(_laser_fan_frame.bind(spr, nfr), 0.0, float(nfr), float(nfr) / 24.0)
	tw.tween_callback(spr.queue_free)

func _laser_fan_frame(fr: float, spr: Sprite3D, nfr: int) -> void:
	# ★同族钳制: nfr 来自调用方, 与贴图真实帧数无关
	if is_instance_valid(spr):
		spr.frame = clampi(int(fr), 0, mini(nfr, maxi(1, int(spr.hframes) * int(spr.vframes))) - 1)

func _sniper_charge_fx(u: Dictionary, tgt: Dictionary) -> void:   # 蓄力1秒: 细红瞄准线由暗渐亮 + 枪口聚能球胀大 + 目标身上三道收缩锁定环
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	_laser_beam(u["pos"], tgt["pos"] + dir * 90.0, Color(1.0, 0.22, 0.26, 0.34), 0.025, 1.0, 1.0)   # 细红瞄准线(持续1秒)
	# 枪口聚能球: 由小变大再爆开
	var tex := VfxTex._make_fire_glow_tex()
	var tw0: float = float(maxi(1, int(tex.get_width())))
	var orb := Sprite3D.new()
	orb.texture = tex
	orb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	orb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	orb.shaded = false; orb.transparent = true
	orb.no_depth_test = true; orb.render_priority = 5
	orb.modulate = Color(1.0, 0.35, 0.32, 0.0)
	orb.pixel_size = (10.0 * WS) / tw0
	orb.position = _world_pos(u["pos"] + dir * 26.0, 1.05)
	_world.add_child(orb)
	var ot := _reg_tween(); ot.set_parallel(true)
	ot.tween_property(orb, "pixel_size", (60.0 * WS) / tw0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ot.tween_property(orb, "modulate:a", 0.95, 0.8)
	ot.chain().tween_property(orb, "modulate:a", 0.0, 0.12)
	ot.chain().tween_callback(orb.queue_free)
	# 目标身上三道收缩锁定环(每0.3秒一道, 越来越小=锁定收紧)
	for k in range(3):
		var rt := _reg_tween()
		rt.tween_interval(float(k) * 0.3)
		rt.tween_callback(_skill_ring.bind(tgt["pos"], Color(1.0, 0.3, 0.3, 0.5 + 0.15 * float(k)), 92.0 - 26.0 * float(k)))

func _windup_spark(pos2d: Vector2, ang: float) -> void:
	var tex := VfxTex._make_fire_glow_tex()
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
		tw.tween_method(_dragon_sys._dragon_fly_step.bind(d, start2d, end2d), 0.0, 1.0, dur)
		tw.tween_callback(d.queue_free)
		var tf := _reg_tween()                       # 振翅: 乒乓循环5帧(~4次/秒)
		tf.tween_method(_dragon_sys._dragon_flap_frame.bind(d), 0.0, 32.0 * dur, dur)
	var burn: Texture2D = load("res://assets/sprites/vfx/dragon-flame.png")
	var perp: Vector2 = (end2d - start2d).orthogonal().normalized()
	for i in range(1, 19):                           # 燃烧带: 沿线真像素火, 大小/横向随机=有机火带(非机械等距), 龙飞到才点燃
		var f: float = float(i) / 19.0
		var jit: Vector2 = perp * randf_range(-28.0, 28.0)
		_delayed_ground_fire(start2d.lerp(end2d, f) + jit, burn, randf_range(74.0, 128.0), f * dur * 0.9)
	_dragon_sys._dragon_mouth_jet(start2d, end2d, dur)           # 龙嘴喷火(从嘴喷向地面)

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


# ============================================================================
#  局内信息 UI — 左右队头像框栏 + 点单位看详情面板 (纯 UI, 不动玩法)
#    1) _hud._build_team_panels: 左右两竖栏 (主龟; 召唤体不进), 每框=头像+名+等级牌+迷你血条, 可点
#    2) _info_sys._update_team_panels: 每帧刷 HP 条宽 / 死亡变暗 / 选中高亮
#    3) _hud._show_unit_info_panel: 居中详情面板 (detail_panel_frame 斜面边框), 显等级/属性/被动/技能/装备
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
func _equip_cost_color(c: int) -> Color:   # 局内装备框色: 按费用(稀有度字段已废弃·与旧稀有度严格1:1→颜色不变·用户2026-07-19)
	match c:
		2: return Color("#4ade80")
		3: return Color("#60a5fa")
		4: return Color("#c084fc")
		5: return Color("#fbbf24")
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

func _refresh_panel_equips(u: Dictionary) -> void:
	var row = u.get("panel_eq_row", null)
	if row == null or not is_instance_valid(row):
		return
	for c in (row as Node).get_children():
		row.remove_child(c)   # 立即移出(别等queue_free到帧末→避免新旧图标重叠一帧)
		c.queue_free()
	u["panel_charge_bars"] = []
	u["panel_count_labels"] = []
	var equips: Array = u.get("equips", [])
	for _ei in range(mini(4, equips.size())):
		row.add_child(_make_panel_equip_slot(u, str((equips[_ei] as Dictionary).get("id", ""))))

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
	bsb.border_color = _equip_cost_color(int(edef.get("cost", 1)))
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
		cb_fill.color = (Color(str(cfg[2])) if cfg.size() > 2 else Color("#5ad2ff"))   # 可选第3项=自定义条色(023法力=火橙)
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

var _info_stat_labels: Array = []      # 属性行的文本 Label(顺序与 _info_sys._info_stat_rows 一一对应)
var _info_stat_grid: GridContainer = null
var _info_hp_bar: ProgressBar = null
var _info_hp_lbl: Label = null
var _info_en_bar: ProgressBar = null
var _info_en_lbl: Label = null
var _info_stat_n: int = -1             # 上次的属性行数; 变了就得重建(有属性从0变非0)
## 技能/被动描述里的伤害数值也要跟着属性实时变(用户 2026-07-21:「下面的技能伤害数值」)。
## 存"模板原文 + 对应 Label + 技能字典", 每帧用当前属性重渲染。
var _info_passive_lbl: Label = null
var _info_passive_tpl: String = ""
var _info_skill_lbls: Array = []       # [{lbl: Label, tpl: String, sk: Dictionary}, ...]
var _info_status_box: VBoxContainer = null   # 状态 chips 容器(条目数会变→整块重建)
var _info_status_sig := ""                   # 上次的状态签名; 没变就不重建(省每帧分配节点)
var _info_equip_box: VBoxContainer = null    # 装备区容器(星级/件数会变→整块重建)
var _info_equip_sig := ""

## 装备区: 件数 + 各件 id/星 的签名, 变了才重建(财神招财临时升星/宝箱龟开出新装备都会变)
func _equip_signature(u: Dictionary) -> String:
	var s := ""
	for e in u.get("equips", []):
		s += "%s:%d," % [str((e as Dictionary).get("id", "")), int((e as Dictionary).get("star", 1))]
	return s

func _fill_equip_section(box: VBoxContainer, u: Dictionary) -> void:
	var equips: Array = u.get("equips", [])
	_add_section_title(box, "装备 (%d)" % equips.size())
	if equips.is_empty():
		_add_body_text(box, "无装备", Color("#7a8694"))
	else:
		for e in equips:
			_add_equip_row(box, str(e.get("id", "")), int(e.get("star", 1)))

## 状态签名: 把当前所有状态压成一个字符串, 变了才重建 chips。
## ★不能每帧无脑重建 —— 那会每帧 queue_free + new 一堆节点, 还会让 UI 闪。
func _status_signature(u: Dictionary) -> String:
	return "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
		1 if _t < float(u.get("stun_until", 0.0)) else 0,
		1 if _t < float(u.get("slow_until", 0.0)) else 0,
		1 if _t < float(u.get("taunt_until", 0.0)) else 0,
		1 if _t < float(u.get("untargetable_until", 0.0)) else 0,
		1 if _t < float(u.get("heal_reduce_until", 0.0)) else 0,
		1 if _t < float(u.get("energy_lock_until", 0.0)) else 0,
		int(u.get("shield", 0.0)),
		int(u.get("rage", 0.0)),
		int(u.get("star_energy", 0.0)),
		int(u.get("store_energy", 0.0)),
		# ★原为 dot_burn_stacks —— 全项目零处写入的死字段, 等于这一位恒为 0,
		#   层数怎么变签名都不变 → 面板不刷新。改读真实的 dot_stacks 三种。
		int((u.get("dot_stacks", {}) as Dictionary).get("burn", 0)),
		int((u.get("dot_stacks", {}) as Dictionary).get("poison", 0)),
		int((u.get("dot_stacks", {}) as Dictionary).get("bleed", 0)),
	]

## 把技能/被动文案模板按【单位当前属性】渲染成人读文本。
## pets.json 里写的是 {N:0.7*ATK} / {{ATK}} 这类占位符, 不渲染就【原样漏到界面】。
## 图鉴一直走 SkillText, 战斗详情面板此前漏接 —— 这就是用户在面板上看到 {N:0.7*ATK} 的原因。
func _is_chest_turtle(u: Dictionary) -> bool:
	return str(u.get("id", "")) == "chest"

## 宝箱龟信息区: 财宝值 + 到下一个宝箱的进度 + 已开出的 N 件战利品(图标/名/描述).
## 财宝值取法必须和 _chest_sys._chest_treasure_tick 一致 —— 我方真实对局走 GameState(跨战场大轮累积),
## demo/敌侧走本单位 dmg_dealt(单场旧制); 两边取错会显示成完全不同的数。
func _fill_chest_section(sec: VBoxContainer, u: Dictionary) -> void:
	for c in sec.get_children():
		if c is Timer:
			continue                    # 留着自己的刷新定时器, 别把脚下的梯子拆了
		sec.remove_child(c)
		c.queue_free()
	var vb := sec
	var season_mode: bool = (not _review_demo()) and str(u.get("side", "")) == "left" and GameState != null and not u.get("is_summon", false)
	var tv: float = float(GameState.chest_treasure_value) if season_mode else float(u.get("dmg_dealt", 0.0))
	var opened: int = (GameState.chest_treasures_won as Array).size() if season_mode else int(u.get("chest_opened", 0))
	_add_section_title(vb, "藏宝图 · 财宝值")
	if opened >= 5:
		_info_sys._info_bar(vb, 1.0, 1.0, Color("#ffd93d"), "财宝 %d  ·  宝箱已开满 (5/5)" % int(tv))
	else:
		var need: float = float(_CHEST_THRESH[opened]) if season_mode else 0.0
		if season_mode:
			var prev: float = float(_CHEST_THRESH[opened - 1]) if opened > 0 else 0.0
			_info_sys._info_bar(vb, clampf(tv - prev, 0.0, maxf(1.0, need - prev)), maxf(1.0, need - prev), Color("#ffd93d"),
				"财宝 %d / %d  ·  下一个宝箱 (%d/5)" % [int(tv), int(need), opened + 1])
		else:
			_info_sys._info_bar(vb, 1.0, 1.0, Color("#ffd93d"), "财宝 %d  ·  已开 %d/5 (单场制)" % [int(tv), opened])
	# 已开出的战利品: 面板显【本单位身上生效的那些】(chest_treasures), 跨场常驻的也已注入到单位上
	var owned: Dictionary = u.get("chest_treasures", {})
	_add_section_title(vb, "  已获战利品 (%d)" % owned.size(), Color("#ffd93d"), 14)
	if owned.is_empty():
		_add_body_text(vb, "尚未开出", Color("#7a8694"))
		return
	for tid in owned.keys():
		_chest_sys._chest_loot_row(vb, str(tid))

## 一件战利品: 金框图标 + 名 + 效果描述 (样式对齐 _add_equip_row)
const MINION_SKILL_DESC := {
	"minionBodysurf": {
		"name": "人体浪板",
		"desc": "高跳回复 2×攻击力 生命 → 射出铁链定身 → 拉向目标 → 接触造成目标 10% 最大生命的物理伤害 → 踩着滑行(对被踩者持续 2×攻击力物理, 沿途 1.5×攻击力并击退) → 跳下。射程 2000 · 120 龟能",
	},
	"minionRocket": {
		"name": "追踪火箭筒",
		"desc": "蓄力 1.5 秒(枪口聚能) → 发射慢速追踪导弹(带尾焰) → 命中核爆: 400 码范围 4×攻击力物理伤害, 并施加 4 秒 50% 治疗削减。射程 2000 · 120 龟能",
	},
	"eliteHammer": {
		"name": "精英铁锤",
		"desc": "精英小将专属: 抡锤砸地, 范围击飞并造成物理伤害。射程 500 · 100 龟能",
	},
}

func _skill_detail() -> bool:
	return GameState != null and bool(GameState.get("skill_text_detail"))


## 面板顶部的「简明 / 详细」切换。切完【整块重建】面板 ——
## 详细文案长度差很多, 只换文字会让布局错位。
func _add_detail_toggle(vb: VBoxContainer, u: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(row)
	var btn := Button.new()
	var on := _skill_detail()
	btn.text = "详细 ▾" if on else "简明 ▸"
	btn.tooltip_text = "切换技能说明: 简明只给算好的数值, 详细展开公式与比率"
	btn.add_theme_font_size_override("font_size", 13)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void:
		if GameState != null:
			GameState.skill_text_detail = not _skill_detail()
		# 重开同一只龟的面板 = 整块按新模式重建
		var keep = _selected_unit
		_hud._close_info_panel()
		if keep is Dictionary and (keep as Dictionary).get("alive", false):
			_hud._show_unit_info_panel(keep))
	row.add_child(btn)


## 装备行: 图标 + 名 + ★×star + 效果 稀有度色描边图标框.
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
	isb.border_color = _equip_cost_color(int(edef.get("cost", 1)))
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
	title.add_theme_color_override("font_color", _equip_cost_color(int(edef.get("cost", 1))))
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

func _add_body_text(parent: VBoxContainer, text: String, col: Color = Color("#c2d0de")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	parent.add_child(l)
	return l   # ★返回 Label 供每帧重渲染技能伤害数值

# 攻速等小数: 去多余 0 (0.850000 → 0.85)
func _fmt_num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

# （已删 class _CamInputRelay ——它是【纯粹为暂停而存在】的 PROCESS_MODE_ALWAYS 中继:
#   主场景 INHERIT→PAUSABLE, get_tree().paused 时 _unhandled_input 根本不被调用,
#   所以当年挂了它让"暂停中也能拖镜头"(测试人员 2026-07-22:「点暂停键鼠标似乎也无法拖动」)。
#   2026-07-30 暂停按钮按用户要求移除后, 局内不再有进入 paused 的路径 → 它成了死代码。
#   ★如果将来又加回任何"暂停"机制, 这个中继要一起加回来, 否则那个 bug 会原样复现。）
