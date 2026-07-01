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
const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 (像素口径, 与 2D 版一致 → 同比例映射到 3D 地面)
# #12 出生站位参数化 (编辑器 Inspector 可调, 别写死): 默认=原值→不改行为; 调它即可挪出生点/拉开间距 不动代码
@export var spawn_edge_margin: float = 150.0    # 龟距战场左右边缘 (越大越靠中)
@export var spawn_front_margin: float = 100.0   # 首龟距战场上边
@export var spawn_row_spacing: float = 160.0    # 三龟纵向间距 (越大越散开)
# 技能放招 = 龟能充能 (用户实测沙蝎): 龟能按固定速率充, 每技有龟能花费, 攒够才放。
#   "冷却"不是独立计时器 = 龟能充满该技花费的时间(花费×0.075秒)。冷却 与 龟能充能 是同一回事。
#   花费/换算/is_active 全在单一事实源 SkillEnergy (战斗/图鉴/选龟共用, 防口径分叉)。
const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")
const SKILL_GCD := 0.4                      # 同龟两次放技最小间隔 (防多技同帧连爆)
# AI 状态机节拍 (Botworld式: 移动/攻击互斥 + 施法锁 + 前摇/后摇; 用户2026-06-28 #5最高优先级)
const ATK_WINDUP := 0.12                    # 普攻前摇(站定蓄力)
const ATK_RECOVER := 0.10                   # 普攻后摇(出手后定身)
const CAST_WINDUP := 0.34                   # 技能前摇(蓄力, 比普攻久 → 有重量感)
const CAST_RECOVER := 0.24                  # 技能后摇
const _BASIC_RARITY_BONUS := {"C": 0.20, "B": 0.23, "A": 0.26, "S": 0.29, "SS": 0.32, "SSS": 0.34}   # 小龟不屈: 按目标稀有度
const SEP_RADIUS := 68.0                    # 单位软分离半径 (像素口径; 防扎堆, 调大点更散)
const HP_MULT := 3.0                       # base↔final比率: 龟/装备hp已写最终值; 仅召唤raw值(×)与装备%回收(maxHp/)用它
const SHIELD_CAP_MULT := 1.5
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类层数 DoT 每秒结算一次
const BUFF_SEC := 5.0                      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const CTRL_SEC := 1.5                      # 眩晕/冻结/嘲讽 默认秒数

# 28 龟战斗属性 (1:1 复用): id → [melee, move_spd(px/s), atk_interval(s), atk_range(px)]
const STATS := {
	"basic": [true, 105.0, 0.85, 70.0], "stone": [true, 70.0, 1.1, 70.0], "bamboo": [true, 105.0, 0.85, 70.0],
	"angel": [false, 105.0, 0.85, 400.0], "ice": [false, 105.0, 0.85, 400.0], "ninja": [false, 145.0, 0.6, 400.0],
	"two_head": [true, 145.0, 0.85, 70.0], "ghost": [false, 145.0, 0.6, 400.0], "diamond": [true, 70.0, 1.1, 70.0],
	"fortune": [true, 105.0, 0.75, 70.0], "dice": [false, 145.0, 0.6, 400.0], "rainbow": [true, 105.0, 0.7, 70.0],
	"gambler": [false, 145.0, 0.85, 400.0], "hunter": [false, 145.0, 0.6, 400.0], "pirate": [false, 105.0, 0.85, 400.0],
	"candy": [false, 105.0, 0.85, 400.0], "bubble": [false, 70.0, 1.1, 400.0], "line": [false, 145.0, 0.6, 400.0],
	"lightning": [false, 145.0, 0.6, 400.0], "phoenix": [false, 105.0, 0.5, 400.0], "lava": [false, 145.0, 0.7, 400.0],
	"cyber": [false, 105.0, 0.85, 400.0], "crystal": [true, 70.0, 1.1, 70.0], "chest": [true, 105.0, 1.1, 70.0],
	"space": [false, 145.0, 0.85, 400.0], "hiding": [true, 70.0, 1.1, 70.0], "headless": [true, 145.0, 0.85, 70.0],
	"shell": [true, 105.0, 1.1, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 0.85, 70.0]
const REVIEW_DEMO := true                  # 评审期: 战斗=1受审龟 vs 1假人(右不动/不打/不放技/高血沙包); 上线前置 false
const REVIEW_TURTLE := "lava"              # 受审龟 id (评审换龟只改这里)
const REVIEW_SKILL_IDX := -1  # 评审时受审龟放哪个技(skillPool索引); -1=默认
const REVIEW_SHOWCASE := []   # 非空=展示模式: 这些龟一队vs等量假人(一窗连续看多只); 空=单龟评审
const REVIEW_DUMMY := "basic"              # 假人 id (右队沙包)
const REVIEW_DUMMY_HP := 500.0            # 假人固定血量
const REVIEW_DUMMY_COUNT := 3   # 假人数量(单龟评审时); >1=排开
const REVIEW_DUMMY_KILLABLE := false   # true=假人会死(看换目标); false=不死回满沙包(看完整动画)
const REVIEW_DUMMY_ATTACKS := true     # true=假人会还手(看挨打类被动如龟壳储能); 同时受审龟免死看完整循环
const LEFT_DEMO := ["basic", "stone", "lightning"]   # 非评审 demo (REVIEW_DEMO=false 时用)
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

# 普攻表 (1:1 复用): id → [scale, hits]
# 基础技能 (28龟 1:1 照原始 skillPool[0] 公式/类型/机制重对, 2026-06-28).
#   字段: phys/magic/true=×ATK 总倍率(物/魔/真); hits=视觉段; def/mr/hp/selfhp/tcurhp=加成项(进主类型);
#   gold=×ATK×金币(财神); critflat=×暴击率flat(骰子); rider=burn/atkdn/selfdef(附带); mech=ninja/splash(特殊); lightning 走专用函数.
const BASIC_ATK := {
	"basic":    {"phys": 1.0, "hits": 1},
	"stone":    {"phys": 0.7, "def": 1.5, "mr": 0.8, "hits": 1},                    # +护甲魔抗(坦克)
	"bamboo":   {"phys": 0.4, "selfhp": 0.03, "hits": 1},                           # 单段 0.4ATK+3%自身HP(用户2026-06-29)
	"angel":    {"phys": 1.0, "hits": 1},                                          # 远程平A 1.0ATK单段(用户)+审判被动
	"ice":      {"phys": 0.8, "magic": 0.8, "hits": 1, "alt_each": true},           # 单段逐次交替物/魔 0.8ATK(用户2026-06-29)
	"ninja":    {"phys": 0.96, "true": 0.64, "hits": 1},                            # 改远程! 普攻=扔飞镖(1.6含40%真); 冲击转主动技
	"two_head": {"phys": 0.8, "true": 0.8, "hits": 4},                             # 物+真 (原1.0全物 错)
	"ghost":    {"phys": 0.4, "true": 0.9, "hits": 1},                             # 物+真 (原0.65 错)
	"diamond":  {"phys": 0.7, "def": 0.6, "mr": 0.6, "hits": 1},                    # +护甲魔抗
	"fortune":  {"phys": 1.0, "gold": 0.02, "hits": 1},                            # 1下(用户; 回合制原2下)
	"dice":     {"phys": 0.9, "critflat": 55.0, "hits": 3},                         # 90%+5500%暴击率flat
	"rainbow":  {"magic": 1.4, "hits": 2},                                         # 魔法 (原物 错)
	"gambler":  {"phys": 1.35, "hits": 3},                                         # 0.9~1.8随机取中
	"hunter":   {"phys": 1.65, "hits": 3},
	"pirate":   {"phys": 1.4, "hits": 4},
	"candy":    {"phys": 1.1, "selfhp": 0.05, "hits": 1, "rider": "atkdn"},         # +自HP+减攻debuff
	"bubble":   {"phys": 1.5, "hits": 3},
	"line":     {"phys": 1.5, "hits": 3},                                          # 墨迹走被动
	"phoenix":  {"magic": 0.9, "hits": 1, "rider": "burn"},                         # 魔法+灼烧 (原物 错)
	"lava":     {"magic": 0.6, "hp": 0.04, "hits": 1, "rider": "burn", "burnScale": 0.07},   # 熔岩弹: 0.6魔+4%目标HP+0.125ATK灼烧层 (用户2026-06-30)
	"cyber":    {"phys": 0.75, "hp": 0.12, "hits": 5},                             # +12%目标HP
	"crystal":  {"magic": 1.0, "hp": 0.06, "hits": 2},                             # 魔法+6%目标HP (原物 错); 结晶走被动
	"chest":    {"phys": 1.5, "hits": 3},                                          # (原4.5 错→1.5; 原始无公式)
	"space":    {"magic": 1.2, "tcurhp": 0.18, "hits": 3},                          # 魔法+18%目标当前HP (原物 错)
	"hiding":   {"phys": 1.0, "hits": 1, "rider": "selfdef"},                       # +自护甲buff
	"headless": {"phys": 1.3, "hp": 0.08, "hits": 2},                              # +8%目标HP
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
const GROUND_NEAR := Color(0.12, 0.34, 0.38)    # 场地中心地色 (略亮暖青)
const GROUND_FAR := Color(0.016, 0.07, 0.105)   # 远/边缘地色 (深蓝, 融进雾/背景)
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

# ============================================================================
#  运行时状态
# ============================================================================
var _units: Array = []
var _data_by_id: Dictionary = {}
var _skill_meta: Dictionary = {}   # 技能 type → skillPool 条目 {atkScale,hits,pierce,name,icon} (选3 多技能 数据驱动放招)
var _over := false
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

# --- 局内信息 UI (左右队头像框 + 点单位看详情面板; 纯 UI 不动玩法) ---
var _team_panel_left: VBoxContainer = null    # 屏幕左侧头像框栏 (左队主龟)
var _team_panel_right: VBoxContainer = null   # 屏幕右侧头像框栏 (右队主龟)
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
	"chest":     "chest-0",               # 清点财宝 (候选1)
	"space":     "space-0",               # 流星暴击 (候选1)
	"two_head":  "twohead-magicwave",     # 双头 (候选1)
	"lava":      "lava-0",                # 熔岩 (候选1)
	"cyber":     "cyber-0",               # 能量大炮 (候选1)
	"candy":     "candy-hammer",          # 焦糖铠/锤 (候选1)
	"hiding":    "hiding-0",              # 防御 (候选1)
	"shell":     "shell-0",               # 吸收 (候选1)
}
var _skill_vfx_cache: Dictionary = {}     # 贴图名 → Texture2D (避免重复 load)

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
	_sub.msaa_3d = Viewport.MSAA_2X
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
	_cam.position = Vector3(0.0, 15.0, 17.0)
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
	sky_mat.sky_top_color = Color(0.006, 0.018, 0.032)     # 顶部深蓝黑 (水越深越暗, 近黑)
	sky_mat.sky_horizon_color = Color(0.012, 0.038, 0.058) # 水平线带点青 (压暗, 不露灰带)
	sky_mat.ground_bottom_color = Color(0.005, 0.016, 0.03)
	sky_mat.ground_horizon_color = Color(0.012, 0.038, 0.058)
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
	var gw: float = ARENA.size.x * WS + 60.0
	var gh: float = ARENA.size.y * WS + 60.0
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
	float depth_t = smoothstep(0.0, 1.4, d);    // 超出竞技场继续沉暗
	vec3 base = mix(near_col, far_col, depth_t);
	// 焦散 (仅场内明显, 远处随景深淡出)
	float c = caustic(wp * 0.5, TIME * caustic_speed);
	base += c * caustic_strength * (1.0 - smoothstep(0.4, 1.2, d));
	// 边界暗角: 越靠边/越远 → 压暗 (柔和无硬线)
	float vig = 1.0 - vignette * smoothstep(0.5, 1.3, d);
	// 远场强沉黑: 竞技场外 (d>1) 二次压暗到近黑, 防远地/边角被光/雾刷亮成灰带
	float sink = 1.0 - 0.92 * smoothstep(1.0, 2.2, d);
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
	mat.set_shader_parameter("half_arena", half_arena)
	mat.set_shader_parameter("vignette", GROUND_VIGNETTE)
	mat.set_shader_parameter("caustic_strength", CAUSTIC_STRENGTH)
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
	title.text = "2.5D 实时战斗 · 3v3 (左队 vs 右队)   [R 重开 · ESC 返回菜单]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(24, 16)
	_ui_layer.add_child(title)

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
	var left := _resolve_left()
	var right := _resolve_right()
	var _cx := ARENA.position.x + ARENA.size.x * 0.5    # 评审演示: 龟居中拉近(相机框得到)
	var _cy := ARENA.position.y + ARENA.size.y * 0.5
	for i in range(left.size()):
		# XZ 落点: 左队靠左 (ARENA 内), 三龟纵向分布. 与 2D _spawn_teams 同口径像素坐标. 偏移走 @export 参数(#12)
		var pos := Vector2(ARENA.position.x + spawn_edge_margin, ARENA.position.y + spawn_front_margin + i * spawn_row_spacing)
		if REVIEW_DEMO and left.size() == 1:
			pos = Vector2(_cx - 150.0, _cy)
		elif REVIEW_DEMO:
			pos = Vector2(_cx - 200.0, _cy + (float(i) - float(left.size() - 1) / 2.0) * minf(150.0, 520.0 / float(maxi(1, left.size()))))
		var _lu := _make_unit(str(left[i]), "left", pos)
		if REVIEW_DEMO and str(left[i]) == "fortune":
			_lu["gold"] = 0.0   # demo: 财神起手金币(0=看自然攒金币)
		if REVIEW_DEMO and REVIEW_DUMMY_ATTACKS:
			_lu["_review_dummy"] = true   # 假人会还手时受审龟免死(看完整被动循环)
		_units.append(_lu)
	for i in range(right.size()):
		var pos := Vector2(ARENA.end.x - spawn_edge_margin, ARENA.position.y + spawn_front_margin + i * spawn_row_spacing)
		if REVIEW_DEMO and right.size() == 1:
			pos = Vector2(_cx + 150.0, _cy)
		elif REVIEW_DEMO:
			pos = Vector2(_cx + 100.0 + (float(i) - float(right.size() - 1) / 2.0) * 150.0, _cy + 40.0)   # 横排(用户)
		var ru := _make_unit(str(right[i]), "right", pos)
		if REVIEW_DEMO:                          # 假人: 不放技/永不死训练靶; ATTACKS时会还手(动+普攻)
			if not REVIEW_DUMMY_ATTACKS:
				ru["no_basic"] = true
				ru["no_move"] = true
			ru["active_skills"] = []
			ru["maxHp"] = REVIEW_DUMMY_HP
			ru["hp"] = ru["maxHp"]
			if not REVIEW_DUMMY_KILLABLE:
				ru["_review_dummy"] = true       # 不死沙包(受击回满); KILLABLE=会死(看换目标)
		if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示假人: 固定不动/5000血/30双抗/会掉血
			ru["no_basic"] = true; ru["no_move"] = true; ru["active_skills"] = []
			ru["maxHp"] = 5000.0; ru["hp"] = 5000.0
			ru["base_def"] = 30.0; ru["base_mr"] = 30.0; _recalc_stats(ru)
			ru.erase("_review_dummy")
		_units.append(ru)
	_inject_equipment()       # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备) — 须在被动之前
	_apply_spawn_passives()   # 登场被动 (开战即生效: 忍术暴击/怨灵诅咒/冰寒减攻/召唤等)
	_eq_apply_all_stats()     # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)
	_build_team_panels()      # 局内 UI: 左右队头像框栏 (主龟; 召唤体不进) — 须在 equips 注入之后

func _resolve_left() -> Array:
	if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示: 远程携带者(默认hunter)
		return [OS.get_environment("EQDEMO_CARRIER")] if OS.has_environment("EQDEMO_CARRIER") else ["hunter"]
	if REVIEW_DEMO:
		if not REVIEW_SHOWCASE.is_empty():
			return REVIEW_SHOWCASE.duplicate()   # 展示模式: 多只一队
		return [REVIEW_TURTLE]                 # 评审: 只 1 只受审龟
	var ldr := _season_leaders()
	return ldr if ldr.size() >= 1 else LEFT_DEMO.duplicate()

func _resolve_right() -> Array:
	if OS.has_environment("EQDEMO_EQUIP"):   # 装备演示: 1个固定假人
		return ["basic"]
	if REVIEW_DEMO:
		if not REVIEW_SHOWCASE.is_empty():
			var arr: Array = []
			for _i in range(REVIEW_SHOWCASE.size()):
				arr.append(REVIEW_DUMMY)
			return arr   # 展示模式: 等量假人
		var arr2: Array = []
		for _j in range(maxi(1, REVIEW_DUMMY_COUNT)):
			arr2.append(REVIEW_DUMMY)
		return arr2                           # 评审: REVIEW_DUMMY_COUNT 个假人
	# 无赛季阵容(直接进战斗调试) → demo 固定对位.
	if _season_leaders().is_empty():
		return RIGHT_DEMO.duplicate()
	# 有赛季阵容 → 优先用匹配抽到的对手 ghost.leaders (Matchmaking 写 dual_ghost); 没有则随机 bot 兜底.
	var ghost_leaders := _ghost_leaders()
	return ghost_leaders if not ghost_leaders.is_empty() else _random_bot(3)

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
	if REVIEW_DEMO:
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

func _make_unit(id: String, side: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = _data_by_id.get(id, {})
	var st: Array = STATS.get(id, DEFAULT_STAT)
	var hp := float(d.get("hp", 1350))  # hp已是最终值

	# --- 立绘 billboard sprite: 全身图 + idle sprite-sheet 动画 ---
	#   sprite-sheet 切帧用 Sprite3D 原生 hframes/vframes/frame (mesh 自动裁到单帧+正确 UV);
	#   material_override = 接地软渐隐 shader (在单帧 UV 上做底淡, 不重映射 UV).
	var sd: Dictionary = _resolve_pet_sprite(id)
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
		"atk_interval": float(st[2]), "atk_range": float(st[3]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		# 选3 多技能: loadout 的非基础技(physical/magic 是普攻=自动) → 主动技轮转, 龟能满放下一个
		"active_skills": _resolve_active_skills(id, side == "left"), "skill_idx": 0,
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
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"],
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
	# 等级缩放: 主属性 +5%/级, 攻速 +2%/级 (吃等级表见 战斗基础-策划焊死.md §三)
	var _lvl: int = maxi(1, _unit_level(side))
	if _lvl > 1:
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
	return u

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
// 注: sprite-sheet 切帧用 Sprite3D 原生 hframes/vframes/frame (mesh+UV 已裁到单帧),
//     UV 到此已是单帧内 0..1, shader 只在其上做底部软渐隐, 不再重映射 (重映射会与原生裁切叠加成横向拉花).

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
	vec4 c = texture(tex, UV);       // UV = 当前帧内 0..1 (Sprite3D hframes 已裁)
	// UV.y: 0=帧顶, 1=帧底. 底部这段线性渐隐.
	float fade = 1.0;
	if (UV.y > 1.0 - fade_frac) {
		float k = (1.0 - UV.y) / max(fade_frac, 0.0001);  // 渐隐线处=1, 最底=0
		fade = mix(fade_floor, 1.0, clamp(k, 0.0, 1.0));
	}
	ALBEDO = c.rgb * COLOR.rgb;     // COLOR = Sprite3D.modulate (受击闪白 >1 提亮)
	ALPHA = c.a * fade * COLOR.a;
}
"""
	_ground_fade_shader = sh
	return sh

# 给一张立绘 texture 造接地 shader 材质. 切帧由 Sprite3D 原生 hframes 负责, shader 只做底淡 (无帧 uniform).
func _make_grounded_material(tex: Texture2D, _sd: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_ground_fade_shader()
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("fade_frac", GROUND_FADE_FRAC)
	mat.set_shader_parameter("fade_floor", GROUND_FADE_FLOOR)
	return mat

# blob 影贴图: radial 渐变 中心黑→边缘透明 (优化: 中段加点过渡, 边缘更柔不硬切)
# 亮光晕贴图 (命中火花用): 白心→透明 (modulate 上色才会亮; blob 是黑的不能拿来当火花)
func _make_glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1.0))
	grad.add_point(0.4, Color(1, 1, 1, 0.7))
	grad.add_point(0.75, Color(1, 1, 1, 0.18))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 96; gt.height = 96
	return gt

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
	else:
		# 🛠 调试场编辑态: 跳过模拟推进 (单位摆着不打不动), 但下方 transforms/overlay 照常 → 立绘渲染+血条仍刷新.
		if not _over and not _edit_mode:
			_t += delta
			for u in _units.duplicate():
				if not u["alive"]:
					continue
				_tick_unit(u, delta)
			_apply_separation_pass(delta)   # 每帧全单位软分离(攻击/待机也摊开, 根治扎堆遮血条)
			_tick_lava_zones(delta)         # 持续地面区域 (熔岩龟·岩浆池) 周期结算
			_step_projectiles(delta)
			_check_end()
		_juice_decay(delta)        # squash/闪白/挥击 等计时衰减 (冻结期间不衰 → 冲击姿势保持)
		for u in _units:           # 立绘帧动画推进 (idle 循环 / 动作一次), 冻结期不推进保持冲击姿势
			if u["alive"] or u.get("anim_action", "") == "death":
				_advance_anim(u, delta)
	_update_camera_shake(delta)    # 震屏始终推进 (含冻结期)
	_update_world_transforms()
	_update_overlay()

func _tick_unit(u: Dictionary, delta: float) -> void:
	# DoT/buff到期/累积条/周期被动 (1:1 2D _tick_effects)
	_tick_effects(u, delta)
	if not u["alive"]:
		return
	if u.get("_slam", false):   # 火山砸地演出中: 锁AI/移动 (height/pos由slam tween驱动)
		return
	var stunned: bool = _t < u["stun_until"]

	# --- 击飞真物理: vy 受重力, height 积分; 横向同时滑 (XZ 像素坐标方向) ---
	if u["airborne"]:
		u["vy"] += GRAVITY * delta
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
			# Phase4: 落地 → 压扁回弹 + 小尘 + 轻震屏 (重量感)
			u["land_t"] = JUICE_LAND_SEC
			_shake(JUICE_SHAKE_HEAVY)
			_impact_particles(u["pos"], 0.0)
		return   # 击飞中不移动/不攻击 (覆盖正常行为)

	_tick_skill_cd(u, delta)        # 技能冷却始终走时间 (含麻痹/移动/施法中)
	u["atk_cd"] = maxf(0.0, float(u.get("atk_cd", 0.0)) - delta)   # 普攻冷却也始终走 (漏了它→打一下就再不普攻=用户报的"整个没普攻"; 召唤体也安全)
	if int(u.get("allin_coins", 0)) > 0:
		_fortune_allin_channel(u, delta)
		return   # 财神梭哈投币channel: 锁住(不移动/不普攻)
	var tgt = _acquire_target(u)
	if tgt == null:
		u["state"] = "move"
		return
	if stunned:                     # 麻痹: 不移动/不出手 (但冷却已走)
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var dist := to_t.length()
	var rng: float = u["atk_range"]
	var spd: float = u["move_spd"] * (0.6 if _t < u["slow_until"] else 1.0) * (float(u.get("spd_move_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0)

	# ═══ AI 状态机: 移动 ↔ 前摇 → 出手 → 后摇 (移动与攻击/施法互斥 = 施法锁; 根治"边走边放") ═══
	match str(u.get("state", "move")):
		"move":
			var rs := _pick_ready_skill(u)
			if rs != "" and _SELF_CAST_SKILLS.has(rs):
				# 自/友向技: 任意距离即放, 不用靠近敌人 (修: 原所有技都要进射程=护盾贴脸才放的bug)
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
					u["state"] = "windup"; u["state_t"] = ATK_WINDUP
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
					# gambler 多重打击(云顶剑士式): 命中后掷概率, 中→快攻速再打, 没中→正常冷却
					var _hf: float = maxf(1.0, float(u.get("haste_mult", 1.0))) if _t < float(u.get("haste_until", 0.0)) else 1.0   # 临时攻速buff(祝福等)
					u["atk_cd"] = (_gambler_multi_cd(u) if (u["id"] == "gambler" and dist <= rng) else u["atk_interval"]) / maxf(0.1, _hf * (float(u.get("spd_aspd_mult", 1.0)) if _t < float(u.get("spd_dbf_until", 0.0)) else 1.0))
					u["state"] = "recover"; u["state_t"] = ATK_RECOVER
				else:
					var stype := p.substr(2)
					if _cast_skill(u, tgt, stype):
						u["skill_cd"][stype] = _skill_cd(u, stype)
						u["skill_gcd_until"] = _t + SKILL_GCD
						_eq_on_cast(u, tgt)
						if u["id"] == "space" and float(u.get("star_energy", 0.0)) > 0.0:   # 星能: 施法后追加30%储存星能真伤
							_apply_damage_from(u, tgt, int(u["star_energy"] * 0.30), Color("#ffffff"), 0.0, true)
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
	if cds.is_empty():                                   # 懒初始化: 各技起始冷却错峰(别一开局全放)
		for s in u.get("active_skills", []):
			cds[str(s)] = _skill_cd(u, str(s))   # 初始龟能0: 满冷却从0充(用户; 原错峰head-start去掉)
	if _t < float(u.get("stun_until", 0.0)) or u.get("airborne", false) or _t < float(u.get("storm_until", 0.0)):
		return   # 眩晕/击飞/风暴期 → 龟能锁定不充(用户)
	var _ecm: float = maxf(1.0, float(u.get("echarge_mult", 1.0))) if _t < float(u.get("echarge_until", 0.0)) else 1.0   # 龟能充能加速buff(祝福等)
	if _t < float(u.get("spd_dbf_until", 0.0)):
		_ecm *= float(u.get("spd_echarge_mult", 1.0))   # 充能减速debuff(寒冰登场等)
	_ecm = maxf(0.05, _ecm)
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - delta * _ecm)   # 麻痹也走, 只是放不出; ×充能速率

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

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] != u["side"] and o["alive"]:
			out.append(o)
	return out

func _separation(u: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	for o in _units:
		if o == u or not o["alive"]:
			continue
		var d: Vector2 = u["pos"] - o["pos"]
		var l := d.length()
		if l > 0.01 and l < SEP_RADIUS:
			push += d.normalized() * (1.0 - l / SEP_RADIUS)
	return push * 0.9

# ============================================================================
#  普攻 (复用 2D BASIC_ATK 表 + 伤害公式; 远程发 3D 投射物) + 复杂普攻特判 + on-hit 被动
# ============================================================================
# gambler 多重打击(云顶剑士式连击): 普攻命中后掷概率→中则快攻速再打一发(连锁每次概率×0.8递减), 没中→回正常普攻冷却+重置
func _gambler_multi_cd(u: Dictionary) -> float:
	var ch: float = float(u.get("multi_chance", 0.40))
	if randf() < ch:
		u["multi_chance"] = ch * 0.8                  # 递减: 40→32→25.6→…
		return maxf(0.12, u["atk_interval"] * 0.30)   # 快攻速再打 (~3.3×攻速; F5可调)
	u["multi_chance"] = 0.40                          # 没中→重置, 等下一次普攻
	return u["atk_interval"]

func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	_anticipate(u)                  # Phase4: 普攻预备(缩)+挥出(伸) 前后摇形变
	_play_action(u, "attack")       # 有动作帧的龟(basic/ghost/ninja)播普攻动画, 其余靠 juice 形变
	if u["id"] == "lightning":      # 闪电改造: 一道闪电(魔法)+连锁, 叠层走 _on_basic_hit(满8→雷暴)
		_lightning_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	if u["id"] == "shell":          # 龟壳改造: 1ATK单段·物/真逐攻交替 + 主目标120px内其他敌溅射50%(同类型)
		_shell_basic(u, tgt)
		_on_basic_hit(u, tgt)
		return
	var spec: Dictionary = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	if u["id"] == "lava" and u.get("volcano", false):                  # 火山形态: 烈焰重击式平A (单段重击)
		spec = {"magic": 1.6, "hits": 1, "rider": "burn"}
	_do_basic(u, tgt, spec)
	if u["melee"]:
		_on_basic_hit(u, tgt)   # 近战命中即时; 远程→弹道命中时触发(审判等与裁决同帧, 数字按规矩同时跳)
	# (原: 无条件 _on_basic_hit 被动钩子 (竹叶强化/墨迹/结晶/斩杀/审判/多重/彩虹附色 等) — 改 _do_basic 时漏调, 已补

# 数据驱动基础技能: 按 spec 算物/魔/真伤(含加成项)分段打出 + 附带/特殊机制 (1:1 原始 skillPool[0])
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
	# 附带效果
	match str(spec.get("rider", "")):
		"burn":    _apply_dot_stacks(tgt, "burn", (maxi(1, int(round(float(u["atk"]) * float(spec.get("burnScale", 0.0))))) if spec.has("burnScale") else _default_burn_stacks(u)), u)
		"atkdn":   _buff(tgt, "atk", -0.15, true)
		"selfdef": _buff(u, "def", 0.20, true)
	# 特殊机制
	match str(spec.get("mech", "")):
		"ninja":   _ninja_basic_extra(u, tgt)                            # 背后单位 0.8×ATK + 击飞
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

# 忍者冲击: 主目标正后方单位受 0.8×ATK + 主目标击飞
func _ninja_basic_extra(u: Dictionary, tgt: Dictionary) -> void:
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	for o in _enemies_of(u):
		if o == tgt or not o["alive"]:
			continue
		if _on_line(tgt["pos"], dir, o["pos"], 70.0):
			_apply_damage_from(u, o, _mitigate(u, u["atk"] * 0.8, o, false), Color("#ff4444"))
	_knockback(u, tgt, 45.0)

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

# 闪电龟·改造普攻(用户2026-06-28): 一道闪电(魔法 1.15×ATK)命中主目标 → 连锁弧跳最近2敌(每跳×0.6递减);
#   叠层在 _basic_attack 里走 _on_basic_hit(每攻击+1电击层, 满8引爆雷暴). 原始设计=魔法+跳敌+8层雷暴.
const PHX_CONE_HALF_DEG := 35.0     # 凤凰喷火扇形半角(全70°)
const PHX_FLAME_MAG_COEF := 0.2      # 每0.5s tick 魔法系数 ×ATK
const PHX_FLAME_BURN_COEF := 0.05     # 每0.5s tick 灼烧层系数 ×ATK

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

# 喷火伤害结算: 扇形内全部敌人 0.2ATK×(1+攻速) 魔法 + round(0.5ATK) 灼烧层 (用户)
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
	tw.tween_property(fb, "scale", Vector3(1.9, 1.9, 1.9), 0.30)             # 蓄力(火球长大)
	tw.parallel().tween_property(fb, "modulate", Color(1.0, 0.40, 0.12, 1.0), 0.30)
	tw.tween_method(_scald_arc.bind(fb, mouth, tgt_pos), 0.0, 1.0, 0.42)        # 投掷
	tw.tween_callback(_phoenix_scald_hit.bind(u, tgt, fb))

func _phoenix_scald_hit(u: Dictionary, tgt, fb) -> void:
	if is_instance_valid(fb):
		fb.queue_free()
	if tgt == null or not tgt.get("alive", false):
		return
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.5, tgt, true), Color("#4dabf7"))   # 1.5ATK魔法
	_apply_dot_stacks(tgt, "burn", maxi(1, roundi(float(u["atk"]) * 1.0)), u)   # 1ATK灼烧层
	_apply_skill_extras(u, tgt, {"shieldBreak": 0.5, "atkDown": 0.15, "defDown": 0.15, "mrDown": 0.15, "healCut": 0.5})
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
		var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(im.queue_free)

func _lightning_strike(pos2d: Vector2, _col: Color) -> void:   # 天降闪电: 1:1 港回合制 common-lightning-strike 5帧动画(9fps)
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
	spr.pixel_size = 2.6 / float(maxi(1, tex.get_height()))   # 帧高归一到~2.6m
	spr.position = _world_pos(pos2d, 1.25)
	_world.add_child(spr)
	var tw := create_tween()
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
	if magic and str(tgt.get("id", "")) == "crystal":
		base *= 0.8                                          # 水晶共鸣: 受魔法额外-20%
	return maxi(1, int(round(base)))

func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool = false) -> int:
	var base: float = u["atk"] * scale
	if u.get("_vs_fire_bonus", 0.0) > 0.0 and (str(tgt["id"]) == "lava" or str(tgt["id"]) == "phoenix"):
		base *= 1.0 + float(u["_vs_fire_bonus"])   # 寒冰: 对熔岩/凤凰增伤(天生+20%, 选极寒技覆盖+40%)
	return _resolve_dmg(u, base, tgt, magic)

# 立绘前冲 (近战命中视觉) — billboard offset 微推再回 (朝镜头, 不用翻 facing)
func _melee_lunge(u: Dictionary, tgt: Dictionary) -> void:
	var spr: Sprite3D = u["sprite"]
	if not is_instance_valid(spr):
		return
	var base := spr.position
	var dir3 := _world_pos(tgt["pos"], 0.0) - _world_pos(u["pos"], 0.0)
	if dir3.length() < 0.01:
		return
	dir3 = dir3.normalized() * 0.25
	var tw := create_tween()
	tw.tween_property(spr, "position", base + dir3, 0.06)
	tw.tween_property(spr, "position", base, 0.1)

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
	if src is Dictionary and _PROJ_WAVE.get(str(src.get("id", "")), false):
		p.texture = _make_wave_texture(col)
		p.pixel_size = 0.045   # 尖尖波 52×20 → ~2.3×0.9m
		p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	else:
		p.texture = _make_bolt_texture(col)
		p.pixel_size = 0.014
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)   # 从胸口高度出
	p.position = world_from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": col,
		"src": src, "t": 0.0, "dur": clampf(start2d.distance_to(tgt["pos"]) / 700.0, 0.22, 0.7), "basic_onhit": basic_onhit,
	})

func _summon_walking_bear(u: Dictionary, tgt: Dictionary, dmg: int) -> void:   # 玩偶小熊: 携带者身上召出小熊(装备图), 中速走向敌人, 进攻击范围踢飞, 随后消失
	if tgt == null:
		return
	var bear := Sprite3D.new()
	bear.texture = _sheet("res://assets/sprites/equip/dungeon-doll.png")
	bear.pixel_size = 0.0018   # ~1.1m 高小熊 (609px 图)
	bear.offset = Vector2(0.0, 300.0)   # 底部对齐地面 (609图半高)
	bear.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bear.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bear.shaded = false
	bear.transparent = true
	var pos: Vector2 = u["pos"]
	bear.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(bear)
	var spd := 160.0   # 中等步速 px/s (龟约105~145)
	var guard := 0.0
	while is_instance_valid(bear) and tgt != null and tgt.get("alive", false):
		await get_tree().process_frame
		var dt := get_process_delta_time()
		guard += dt
		if guard > 4.0:   # 兜底: 走太久放弃
			break
		var to: Vector2 = tgt["pos"]
		if pos.distance_to(to) <= 60.0:   # 进攻击范围
			break
		pos = pos.move_toward(to, spd * dt)
		bear.position = _world_pos(pos, GROUND_LIFT)
	# 到位: 踢一脚 → 伤害 + 击飞
	if tgt != null and tgt.get("alive", false):
		_apply_damage_from(u, tgt, dmg, Color("#ffb0c8"), 0.0, false, true)
		_knockback(u, tgt, 60.0)
	# 小熊消失 (淡出)
	if is_instance_valid(bear):
		var tw := create_tween()
		tw.tween_property(bear, "modulate:a", 0.0, 0.2)
		tw.tween_callback(bear.queue_free)

func _step_projectiles(delta: float) -> void:
	var keep: Array = []
	for pr in _projectiles:
		var node: Sprite3D = pr["node"]
		if not is_instance_valid(node):
			continue
		pr["t"] += delta
		var tgt: Dictionary = pr["tgt"]
		var to := _world_pos(tgt["pos"], 1.0)
		var frac: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		node.position = pr["from"].lerp(to, frac)
		if frac >= 1.0:
			node.queue_free()
			if tgt["alive"]:
				if pr["src"] != null:
					_apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"])
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

func _make_bolt_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 1.0))
	grad.add_point(0.6, Color(col.r, col.g, col.b, 0.9))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32; gt.height = 32
	return gt

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
	_float_text(u["pos"] + Vector2(randf_range(-26.0, 26.0), -40.0 + randf_range(-10.0, 6.0)), str(dmg), col)   # 抖开: 多段/AOE 出伤飘字不重叠成糊团
	# §AUDIO: 无来源伤害也出命中音 (非暴击); 护盾破→shield-break
	if shield_before > 0.0 and u["shield"] <= 0.0:
		_sfx_shield_break()
	else:
		_sfx_hit(false)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false) -> void:
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	if u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and randf() < u["dodge_bonus"]:
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#a0e8ff"))
		_eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 小龟·不屈: 造成的任何伤害按目标稀有度增伤 (总闸→普攻/技能/真伤/固定伤全覆盖, 只算一次)
	if src.get("id", "") == "basic" and src != u:
		dmg = int(round(float(dmg) * (1.0 + _BASIC_RARITY_BONUS.get(str(u.get("rarity", "C")), 0.20))))
	# 靶向器055: 被标记目标受伤 +20%
	if _t < u.get("eq_marked_until", 0.0):
		dmg = int(dmg * 1.2)
	# 真伤暴击 (全局: "暴击全龟通用"; 真伤照旧无视护甲/减伤, 只加暴击判定) (用户)
	if raw and src is Dictionary and src.has("crit") and src != u:
		var _trc: float = minf(float(src.get("crit", 0.0)), 1.0)
		_last_atk_crit = randf() < _trc
		if _last_atk_crit:
			dmg = int(round(float(dmg) * (float(src.get("crit_dmg", 1.5)) + maxf(0.0, float(src.get("crit", 0.0)) - 1.0) * 1.5)))
	var was_crit := _last_atk_crit          # §AUDIO: 先抓暴击态 (下方 hook 里嵌套 _atk_dmg 会改写它)
	# 受伤被动(结算前改 dmg): 线条·墨迹(每层+5%受伤) / 钻石·结构(受伤减免)
	var _ink := int((u.get("stacks", {}) as Dictionary).get("ink", 0))
	if _ink > 0:
		dmg = int(dmg * (1.0 + 0.05 * _ink))
	if u["id"] == "diamond" and not raw:        # 钻石·结构减伤18%; 真实/穿透(raw)伤害不减 (修: 原来连真伤一起减=bug)
		dmg = int(dmg * 0.82)
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
	u["hp"] = maxf(0.0, u["hp"] - d)
	if u.get("_review_dummy", false): u["hp"] = u["maxHp"]   # 训练靶: 受击即回满, 打不死不结算(看完整)
	# §STATS: 战斗统计 — 输出归攻击者/承受归目标 (用显示数 dmg)
	if src is Dictionary and src.has("side") and src != u:
		src["_st_dealt"] = int(src.get("_st_dealt", 0)) + dmg
	u["_st_taken"] = int(u.get("_st_taken", 0)) + dmg
	# headless 亡灵: 首次濒死→5秒内HP不降到1以下(免死), 5秒后正常死
	if u["id"] == "headless" and u["hp"] <= 0.0 and not u.get("undead_used", false):
		u["undead_used"] = true; u["deathfloor_until"] = _t + 5.0
		_float_text(u["pos"] + Vector2(0, -64), "亡灵!", Color("#9b6bff"))
	if _t < float(u.get("deathfloor_until", 0.0)):
		u["hp"] = maxf(1.0, u["hp"])
	var _dt: String = "true" if raw else _last_dmg_type
	var _ncol: Color = _VC.color_of(_VC.cls_for("damage", _dt, was_crit))   # 飘字按伤害类型统一取色 (物红/魔蓝/真白, 1:1 回合制)
	_float_text(u["pos"], str(dmg), _ncol, was_crit, "damage", _dt)   # 伤害: 爆大pop+抛物弹射(跳的方向/距离随机自带散开)
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
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava":
		src["rage"] = minf(RAGE_MAX, src["rage"] + float(dmg) * 0.10)
	if u["id"] == "lava":
		u["rage"] = minf(RAGE_MAX, u["rage"] + float(dmg) * 0.10)
	# 星能 (星际造伤62%)
	if src["id"] == "space":
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.62)
	# 储能 (龟壳受伤转储能, 上限50%最大HP) — 仅"store"相位累积 ("cd"相位不储)
	if u["id"] == "shell" and u.get("shell_phase", "store") == "store":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
		u["_auraEnergy"] = u["store_energy"]   # 镜像给Hp条储能条显示(1:1回合制字段)
	# 双头坚韧 (常驻被动): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head":
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
func _knockback(by: Dictionary, tgt: Dictionary, _dist: float) -> void:
	if tgt["airborne"]:
		return
	var dir: Vector2 = (tgt["pos"] - by["pos"])
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	tgt["airborne"] = true
	tgt["vy"] = KNOCK_VY
	tgt["vx"] = dir.x * KNOCK_PUSH
	tgt["vz"] = dir.y * KNOCK_PUSH
	# Phase4: 击飞 = 大事件 → 大震屏 + 顿帧 + 起跳火花 (起跳拉长由 _juice_scale_for 读 airborne/vy 自动)
	_shake(JUICE_SHAKE_BIG)
	_add_hitstop(JUICE_HITSTOP_KNOCK)
	_impact_particles(tgt["pos"], tgt.get("height", 0.0))
	# 飞镖056: 任意敌被己方击飞 → 标"靶子", 携带者周期 tick 射镖
	if tgt["side"] != by["side"] and _side_has_equip(by["side"], "p2eq_056"):
		tgt["eq_target_until"] = _t + 99999.0

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

func _kill(u: Dictionary, killer = null) -> void:
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为常驻一次, 1:1 2D
	if not u["reborn_used"] and (u["id"] == "angel" or u["id"] == "phoenix"):
		u["reborn_used"] = true
		var pct: float = (1.0 if u.get("_enh_rebirth", false) else 0.30) if u["id"] == "phoenix" else 0.25
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
	if killer != null and killer.get("alive", false):
		_eq_on_kill(killer, u)             # on-kill: 击杀者装备 (暴君之牙处决回血 等)
	_eq_on_death(u, killer)                # on-death: 阵亡者装备 (复活海螺变虫 / 齿轮折币 / 玩偶熊)
	_on_unit_death(u, killer)
	# 有死亡帧的龟(basic/ghost/ninja)播 death 动画 → 影/环/血条立即淡, 立绘延后淡(让动画演完)
	_play_action(u, "death")
	var has_death_anim: bool = (u.get("anim_action", "") == "death")
	# 影+环+接触影 淡出 (立绘单独处理, 让 death 动画演完再淡)
	for key in ["shadow", "ring", "contact"]:
		var n = u.get(key, null)
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.4)
			tw.tween_callback(n.hide)
	var spr_n = u.get("sprite", null)
	if is_instance_valid(spr_n):
		var stw := create_tween()
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
# 同时跳出的飘字按规矩错开行: 伤害红0/蓝1/白2 紧凑×22(缺色不留空, 220ms窗口); 非伤害到达序堆叠(100ms)
const FLOAT_ROW_GAP := 15.0   # 同帧多数字每排间距(屏幕px); 实时版定值(比回合制22更贴近), 改这里=全局生效
func _float_row_offset(key: String, kind: String, dmg_type: String) -> float:
	if kind == "damage":
		var rank: int = 1 if dmg_type == "magic" else (2 if dmg_type == "true" else 0)
		var w: Dictionary = _float_dmg_window.get(key, {"ranks": [], "t": -9.0})
		if _t - float(w["t"]) > 0.22:
			w = {"ranks": [], "t": -9.0}
		var ranks: Array = w["ranks"]
		if not ranks.has(rank):
			ranks.append(rank)
		w["ranks"] = ranks; w["t"] = _t
		_float_dmg_window[key] = w
		var sr: Array = ranks.duplicate(); sr.sort()
		return float(maxi(0, sr.find(rank))) * FLOAT_ROW_GAP
	var rec: Dictionary = _float_nd_window.get(key, {"t": -9.0, "n": 0})
	if _t - float(rec["t"]) > 0.10:
		rec["n"] = 0
	rec["t"] = _t
	var extra: int = int(rec["n"]); rec["n"] = extra + 1
	_float_nd_window[key] = rec
	return float(extra) * 22.0

# 飘字 (1:1 回合制 _spawn_float_text): kind=damage → 爆大pop(1.6~2.5)+抛物弹射(重力200,朝屏边跳); 否则(heal/shield/label) → pop1.2+缓升50px(sine)1.5s淡出
func _float_text(pos2d: Vector2, text: String, col: Color, is_crit: bool = false, kind: String = "label", dmg_type: String = "physical") -> void:
	if _cam == null:
		return
	var head := _world_pos(pos2d, 2.2)
	if _cam.is_position_behind(head):
		return
	var screen: Vector2 = _cam.unproject_position(head)
	var amount := absi(text.to_int()) if text.is_valid_int() else 0
	var fsize := _float_size(amount, is_crit) if amount > 0 else (22 if is_crit else 18)
	var is_dmg_crit := is_crit and amount > 0 and kind == "damage"
	var fly: Control
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
		box.add_child(_make_num_label(text, col, fsize))
		fly = box
	else:
		fly = _make_num_label(text, col, fsize)
	_ui_layer.add_child(fly)
	# 居中起跳 + pivot 居中 (pop 绕中心, 1:1 PoC origin 0.5)
	var tsz := _float_num_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize)
	var unit_sz := Vector2(20.0 + 1.0 + tsz.x, maxf(20.0, tsz.y)) if is_dmg_crit else tsz
	fly.pivot_offset = unit_sz / 2.0
	var base_pos := screen - unit_sz / 2.0
	base_pos.y -= _float_row_offset("%d_%d" % [roundi(pos2d.x), roundi(pos2d.y)], kind, dmg_type)   # 按类型排行错开(同时跳不糊)
	if kind == "damage":
		# 伤害: 爆大pop(1.6~2.5按量级)→hold→抛物弹射(jump_x朝屏边, 重力200先上后下)→淡出 (1:1 PoC runFloatAnim)
		fly.position = base_pos
		fly.scale = Vector2(0.01, 0.01)
		var hold_scale := 1.0 if is_crit else 0.7
		var pop_size := 1.6 if amount < 20 else (1.8 if amount < 60 else (2.2 if amount < 150 else 2.5))
		var dir := -1.0 if base_pos.x < 640.0 else 1.0
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
	var tw := create_tween()
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
	var tw := create_tween()
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
		var tw := create_tween()
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
	var t := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector3.ONE, SKILL_VFX_GROW_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SKILL_VFX_HOLD_SEC)
	tw.tween_property(spr, "modulate:a", 0.0, SKILL_VFX_FADE_SEC)
	tw.tween_callback(spr.queue_free)

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
	"shield": true, "heal": true, "bambooHeal": true, "angelBless": true,
	"diamondFortify": true, "crystalBarrier": true, "phoenixShield": true,
	"hidingDefend": true, "hunterStealth": true, "twoHeadSwitch": true,
	"lavaSurge": true, "bubbleShield": true, "shellAbsorb": true,
	"fortuneDice": true, "lightningSurgeBuff": true, "chestCount": true,
	"fortuneGainCoins": true, "phoenixPurify": true, "lightningSurge": true, "lightningShield": true, "rainbowReflect": true,
	"rainbowStorm": true,
	"gamblerBet": true, "diceAllIn": true, "stoneTaunt": true,
}

# ═══ 选3 多技能轮转 (用户2026-06-28拍板: 保留选3, 让3技在战斗真生效) ═══
# 被动型技 (开局生效, 不进主动轮转; 在 _apply_spawn_passives 里按是否被选施加)
const PASSIVE_SKILL_TYPES := {"iceBurnImmune": true, "phoenixEnhancedRebirth": true, "lavaEnhancedRage": true, "shellEnhanceAwaken": true}

# loadout(选3) 里所有"非普攻"技 type (physical/magic 是普攻=自动, 排除)
# 4选1: 每龟从 skillPool[1..4] 选【1个】(主动或被动); GameState.loadouts[id]=选中索引(默认1=签名候选).
func _resolve_chosen_index(id: String, use_loadout: bool) -> int:
	if REVIEW_DEMO and id == REVIEW_TURTLE and REVIEW_SKILL_IDX >= 0:
		return REVIEW_SKILL_IDX   # 评审指定技
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
		if id == "ninja" and ty == "ninjaShuriken": ty = "ninjaImpact"
		if ty != "" and ty != "physical" and ty != "magic" and not _IMPL_SKILLS.has(ty) and not PASSIVE_SKILL_TYPES.has(ty):
			idx = 1
	return idx

# 选中的那1个技 type (排除普攻; 供主动/被动判定). 返空 = 没选到有效技.
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
		if id == "ninja" and st == "ninjaShuriken":
			st = "ninjaImpact"        # 忍者改造: 飞镖变普攻 → 主动技改成冲击(冲刺+击飞)
		if not PASSIVE_SKILL_TYPES.has(st):
			out.append(st)
	return out

# 实装了的技能 type 集 (与 _do_skill 的 match 保持同步; 用于轮转跳过未实装的, 不浪费龟能/不空放 juice)
const _IMPL_SKILLS := {
	# 签名招 (既有 _sk_* 实装, 按技能 type 分派)
	"turtleShieldBash": true, "bambooHeal": true, "angelBless": true, "iceFrost": true, "iceFreeze": true,
	"ninjaImpact": true, "ghostStorm": true, "diamondFortify": true, "diceAllIn": true,
	"gamblerBet": true, "hunterStealth": true, "pirateCannonBarrage": true, "bubbleShield": true,
	"lineLink": true, "lightningSurgeBuff": true, "phoenixShield": true, "twoHeadFear": true,
	"fortuneDice": true, "crystalBarrier": true, "chestCount": true, "starMeteor": true,
	"twoHeadSwitch": true, "lavaSurge": true, "cyberBeam": true, "hidingDefend": true, "shellAbsorb": true,
	# 通用 (多龟共享 type)
	"shield": true, "heal": true,
	# 数据驱动伤害技 (系数取自 pets.json detail 公式 {N/M/T:...})
	"basicBarrage": true, "bambooLeaf": true, "bambooSmack": true, "angelEquality": true,
	"iceSpike": true, "ninjaShuriken": true, "ninjaBomb": true, "twoHeadMagicWave": true,
	"ghostTouch": true, "ghostPhantom": true, "diamondCollide": true, "fortuneStrike": true,
	"diceAttack": true, "rainbowStorm": true, "gamblerCards": true, "gamblerDraw": true,
	"hunterShot": true, "hunterBarrage": true, "candyBarrage": true, "lineSketch": true,
	"lightningStrike": true, "lightningBarrage": true, "phoenixBurn": true, "phoenixScald": true,
	"lavaBolt": true, "lavaQuake": true, "crystalSpike": true, "crystalBurst": true,
	"chestStorm": true, "starBeam": true, "soulReap": true, "shellStrike": true,
	# Batch2 特殊技 (召唤/控制/处决/复制/梭哈/虫洞 — bespoke)
	"chestSmash": true, "fortuneAllIn": true, "starWormhole": true, "lineFinish": true,
	"cyberDeploy": true, "bubbleBind": true, "hidingCommand": true, "shellCopy": true,
	"diceFate": true,
	# 后4龟补实装的 4选1
	"fortuneGainCoins": true, "phoenixPurify": true, "lightningSurge": true, "lightningShield": true, "rainbowReflect": true,
}

# 龟能花费表 已移到单一事实源 SkillEnergy (scripts/systems/skill_energy.gd) — 战斗/图鉴/选龟共用
func _skill_cost(u: Dictionary, stype: String) -> float:
	return float(u.get("energy_cost", {}).get(stype, SkillEnergy.cost_of(stype)))   # 数据驱动: 优先该龟该技energyCost, 缺则类型兜底

# 该技充满龟能要多少秒 (= 龟能花费 × 0.075; 即所谓"冷却") — 龟盾~5s · 普通~7s · 弹幕~10s · 大招~13s
func _skill_cd(u: Dictionary, stype: String) -> float:
	return _skill_cost(u, stype) * 0.075   # 充满龟能秒数 = 花费×0.075

# 该单位是否有龟能系统 (=能放主动技; 无主动技=纯平A单位, 装备文案里"无龟能的单位")
func _has_energy_system(u: Dictionary) -> bool:
	return not u.get("active_skills", []).is_empty()

# 给单位"+N点龟能": 实时版龟能=冷却充能同一事实, 折算 N×0.075 秒扣掉所有技能剩余冷却.
func _eq_grant_energy(u: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var cds: Dictionary = u.get("skill_cd", {})
	var sec: float = amount * 0.075
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - sec)

# shellCopy 可复制的技 = 纯敌方向伤害技 (数据驱动那批; 排除变身/召唤/自增益, 否则从龟壳放会污染自身状态)
const _COPYABLE_SKILLS := {
	"basicBarrage": true, "bambooLeaf": true, "bambooSmack": true, "angelEquality": true,
	"iceSpike": true, "ninjaShuriken": true, "ninjaBomb": true, "twoHeadMagicWave": true,
	"ghostTouch": true, "ghostPhantom": true, "diamondCollide": true, "fortuneStrike": true,
	"diceAttack": true, "rainbowStorm": true, "gamblerCards": true, "gamblerDraw": true,
	"hunterShot": true, "hunterBarrage": true, "candyBarrage": true, "lineSketch": true,
	"lightningStrike": true, "lightningBarrage": true, "phoenixBurn": true, "phoenixScald": true,
	"lavaBolt": true, "lavaQuake": true, "crystalSpike": true, "crystalBurst": true,
	"chestStorm": true, "starBeam": true, "soulReap": true, "shellStrike": true, "chestSmash": true,
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

const SEP_PUSH_SPD := 140.0                  # 软分离推开速度 (px/s; 每帧全单位)
func _apply_separation_pass(delta: float) -> void:   # 每帧全单位软分离: 攻击/待机也摊开(不再只move态), 根治扎堆遮血条
	for u in _units:
		if not u["alive"] or u.get("no_move", false) or u.get("airborne", false) or u.get("_slam", false):
			continue
		var push: Vector2 = _separation(u)
		if push.length() > 0.001:
			u["pos"] += push.limit_length(1.0) * SEP_PUSH_SPD * delta
			u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
			u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

# 移动; no_move 召唤体定点不动. 分离已移到 _apply_separation_pass. (状态机仅"move"态调)
func _do_move(u: Dictionary, tgt: Dictionary, dist: float, rng: float, spd: float, delta: float) -> void:
	if u.get("no_move", false):
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var intent := Vector2.ZERO
	if dist > rng:
		intent = to_t.normalized()                           # 追到射程
	elif not u["melee"] and dist < rng * 0.7:
		intent = -to_t.normalized()                          # 远程太近→风筝后撤
	# 分离已移到 _apply_separation_pass (每帧全单位, 不只move态) → 根治攻击/待机扎堆
	if intent.length() > 0.01:
		u["vel"] = intent.limit_length(1.0) * spd            # 合力调速, 力抵消缓停
		u["pos"] += u["vel"] * delta
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

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
	return true

# 技能 type → VFX 贴图名 (pets.json skillPool[].icon "skills/x.png" → "x"); 无则空串(回退签名)
func _skill_vfx_name(stype: String) -> String:
	var icon: String = str((_skill_meta.get(stype, {}) as Dictionary).get("icon", ""))
	return icon.get_file().get_basename() if icon != "" else ""

func _do_skill(u: Dictionary, tgt: Dictionary, stype: String) -> void:
	match stype:
		# ── 各龟签名招 (既有实装, 按 type 分派) ──
		"turtleShieldBash":     _sk_basic_shield(u, tgt)
		"bambooHeal":           _sk_bamboo_heal(u)
		"angelBless":           _sk_angel_bless(u)
		"iceFrost":             _sk_ice_frost(u, tgt)
		"iceFreeze":            _sk_ice_freeze(u, tgt)
		"fortuneGainCoins":     _sk_fortune_coins(u)
		"phoenixPurify":        _sk_phoenix_purify(u)
		"lightningSurge":       _sk_lightning_shock(u)
		"lightningShield":      _sk_lightning_shield(u)
		"rainbowReflect":       _sk_rainbow_reflect(u)
		"ninjaImpact":          _sk_ninja_impact(u, tgt)
		"ghostStorm":           _sk_ghost_soulstorm(u, tgt)
		"diamondFortify":       _sk_diamond_unbreak(u)
		"diceAllIn":            _sk_dice_allin(u)
		"gamblerBet":           _sk_gambler_wild(u, tgt)
		"hunterStealth":        _sk_hunter_hide(u)
		"pirateCannonBarrage":  _sk_pirate_volley(u)
		"bubbleShield":         _sk_bubble_shield(u, tgt)
		"lineLink":             _sk_line_link(u)
		"lightningSurgeBuff":   _sk_lightning_surge(u, tgt)
		"phoenixShield":        _sk_phoenix_lavashield(u)
		"twoHeadFear":          _sk_headless_fear(u, tgt)
		"fortuneDice":          _sk_fortune_dice(u)
		"crystalBarrier":       _sk_crystal_bulwark(u)
		"chestCount":           _sk_chest_inventory(u)
		"starMeteor":           _sk_space_meteor(u)
		"twoHeadSwitch":        _sk_two_head(u, tgt)
		"lavaSurge":            _sk_lava_cast(u, tgt, "B")   # 岩浆涌动 (修: 原走set A=地裂)
		"cyberBeam":            _sk_cyber_cannon(u, tgt)
		"hidingDefend":         _sk_hiding_defend(u)
		"shellAbsorb":          _sk_shell_absorb(u, tgt)
		# ── 通用 (多龟共享 type) ──
		"shield":               _sk_gen_shield(u)
		"heal":                 _sk_gen_heal(u)
		# ── 数据驱动伤害技 (系数取自 detail 公式; N=物理 M=魔法 T=真实) ──
		"basicBarrage":         _sk_dmg(u, tgt, {"phys": 3.1, "hits": 10, "name": "弹幕!", "color": Color("#ff4444")})
		"bambooLeaf":           _sk_dmg(u, tgt, {"phys": 0.63, "hp": 0.18, "hits": 3, "name": "竹叶斩!", "color": Color("#39d353")})
		"bambooSmack":          _sk_dmg(u, tgt, {"phys": 1.0, "hits": 1, "rider": "atkdn", "name": "竹击!", "color": Color("#39d353")})
		"angelEquality":        _sk_dmg(u, tgt, {"phys": 2.0, "true": 0.5, "hits": 2, "name": "平等审判!", "color": Color("#ffe9a8")})
		"iceSpike":             _sk_dmg(u, tgt, {"phys": 0.7, "magic": 0.7, "hits": 6, "rider": "slow", "name": "冰锥!", "color": Color("#9be7ff")})
		"ninjaShuriken":        _sk_dmg(u, tgt, {"phys": 0.96, "true": 0.64, "hits": 1, "name": "飞镖!", "color": Color("#cfd8e8")})
		"ninjaBomb":            _sk_dmg(u, tgt, {"phys": 1.1, "hits": 1, "aoe": true, "name": "烟雾弹!", "color": Color("#b0b0c0")})
		"twoHeadMagicWave":     _sk_dmg(u, tgt, {"phys": 0.8, "true": 0.8, "hits": 4, "name": "魔法波!", "color": Color("#ffffff")})
		"ghostTouch":           _sk_dmg(u, tgt, {"phys": 0.4, "true": 0.9, "hits": 1, "rider": "curse", "name": "幽灵之触!", "color": Color("#c77dff")})
		"ghostPhantom":         _sk_dmg(u, tgt, {"magic": 1.5, "hits": 1, "name": "幻影!", "color": Color("#c77dff")})
		"diamondCollide":       _sk_dmg(u, tgt, {"phys": 0.8, "mr": 0.9, "hits": 1, "rider": "stun", "name": "撞击!", "color": Color("#9bdcff")})
		"fortuneStrike":        _sk_dmg(u, tgt, {"phys": 1.0, "hits": 2, "name": "财运一击!", "color": Color("#ffd93d")})
		"diceAttack":           _sk_dmg(u, tgt, {"phys": 0.9, "hits": 3, "name": "骰子攻击!", "color": Color("#ff4444")})
		"rainbowStorm":         _sk_rainbow_storm(u)
		"gamblerCards":         _sk_dmg(u, tgt, {"phys": 1.35, "hits": 3, "name": "发牌!", "color": Color("#ffd93d")})
		"gamblerDraw":          _sk_gambler_wild(u, tgt)   # 万能牌(默认签名技): 原来错派纯伤害, 改回 _sk_gambler_wild(2段+盾+治疗+减益)
		"hunterShot":           _sk_dmg(u, tgt, {"phys": 1.65, "hits": 3, "name": "精准射击!", "color": Color("#a8ffb0")})
		"hunterBarrage":        _sk_dmg(u, tgt, {"true": 2.4, "hits": 10, "name": "狩猎弹幕!", "color": Color("#a8ffb0")})
		"candyBarrage":         _sk_dmg(u, tgt, {"phys": 1.0, "hits": 4, "aoe": true, "name": "糖果弹幕!", "color": Color("#ff9ed6")})
		"lineSketch":           _sk_dmg(u, tgt, {"phys": 1.5, "hits": 3, "name": "速写!", "color": Color("#dddddd")})
		"lightningStrike":      _sk_dmg(u, tgt, {"magic": 1.15, "hits": 5, "stagger": 0.08, "electric": 1, "splash": 0.25, "name": "闪电打击!", "color": Color("#7ee8ff")})
		"lightningBarrage":     _sk_lightning_barrage(u)
		"phoenixBurn":          _sk_dmg(u, tgt, {"magic": 0.9, "hits": 1, "rider": "burn", "name": "灼焰!", "color": Color("#ff7a3c")})
		"phoenixScald":         _sk_phoenix_scald(u, tgt)
		"lavaBolt":             _lava_bolt(u, tgt)           # 熔岩弹: 0.9魔+8%目标HP+0.67ATK灼烧 (普攻型, 走专用以保灼烧=0.67非通用rider0.5)
		"lavaQuake":            _sk_lava_cast(u, tgt, "A")   # 地裂(默认): 修-原派_sk_dmg带slow→应_lava_quake(全体魔+削魔抗20%)
		"crystalSpike":         _sk_dmg(u, tgt, {"magic": 1.0, "hits": 2, "name": "水晶刺!", "color": Color("#9bdcff")})
		"crystalBurst":         _sk_dmg(u, tgt, {"magic": 0.7, "true": 0.1, "hits": 3, "aoe": true, "name": "水晶爆!", "color": Color("#9bdcff")})
		"chestStorm":           _sk_dmg(u, tgt, {"phys": 1.0, "hits": 5, "aoe": true, "name": "宝箱风暴!", "color": Color("#ffd93d")})
		"starBeam":             _sk_dmg(u, tgt, {"magic": 0.4, "hits": 3, "name": "星光束!", "color": Color("#ffffff")})
		"soulReap":             _sk_dmg(u, tgt, {"phys": 1.1, "hits": 1, "aoe": true, "name": "灵魂收割!", "color": Color("#c77dff")})
		"shellStrike":          _sk_dmg(u, tgt, {"phys": 0.9, "hits": 2, "name": "龟壳猛击!", "color": Color("#cfd8e8")})
		"chestSmash":           _sk_dmg(u, tgt, {"phys": 1.5, "hits": 3, "name": "宝箱猛击!", "color": Color("#ffd93d")})
		# ── Batch2 特殊技 (bespoke) ──
		"fortuneAllIn":         _sk_fortune_allin(u, tgt)
		"starWormhole":         _sk_star_wormhole(u, tgt)
		"lineFinish":           _sk_line_finish(u)
		"cyberDeploy":          _sk_cyber_deploy(u)
		"bubbleBind":           _sk_bubble_bind(u, tgt)
		"hidingCommand":        _sk_hiding_command(u)
		"shellCopy":            _sk_shell_copy(u, tgt)
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

func _sk_stone_armor(u: Dictionary) -> void:                     # 石头龟·岩石护甲 ✅
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.24 + o["maxHp"] * 0.05)

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies := _allies_of(u, false)
	_play_heal_glow(u["pos"])
	if allies.is_empty():
		_heal(u, u["maxHp"] * 0.15)
	else:
		_heal(u, u["maxHp"] * 0.10)
		for o in allies:
			_grant_shield(o, o["maxHp"] * 0.12)
			_play_heal_glow(o["pos"])

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_grant_shield(ally, u["atk"] * 1.2)
	ally["haste_until"] = _t + 5.0; ally["haste_mult"] = 1.3       # +30% 攻速 5秒
	ally["echarge_until"] = _t + 5.0; ally["echarge_mult"] = 1.3   # +30% 龟能充能速度 5秒 (用户: 取消双抗改这个)
	_skill_ring(ally["pos"], Color(1.0, 0.9, 0.5, 0.5), 48.0)   # 祝福: 金色圣光环

func _sk_ice_frost(u: Dictionary, tgt: Dictionary) -> void:      # 寒冰龟·冰霜 ✅ (圆形冰霜场: 5秒/每0.5秒一跳/圈内-25%魔抗)
	var center: Vector2 = u["pos"]
	if tgt != null and tgt.get("alive", false):
		center = tgt["pos"]
	else:
		var es := _enemies_of(u)
		if not es.is_empty(): center = es[0]["pos"]
	var radius := 150.0
	var tw := create_tween()
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
		var twr := create_tween()
		twr.set_parallel(true)
		twr.tween_property(sh, "position", ground, 0.35)
		twr.tween_property(sh, "modulate:a", 0.0, 0.3).set_delay(0.18)
		twr.chain().tween_callback(sh.queue_free)

func _sk_ice_freeze(u: Dictionary, tgt: Dictionary) -> void:    # 寒冰龟·冰封 ✅ (冰锥弹道→命中0.6魔法+冻结1.5s)
	if tgt == null or not tgt.get("alive", false):
		return
	_fire_ice_shard(u, tgt, _atk_dmg(u, 0.6, tgt, true))

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
	p.flip_h = tgt["pos"].x < start2d.x                       # 锥默认朝右, 目标在左则翻
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)
	p.position = world_from
	_world.add_child(p)
	var dur := clampf(start2d.distance_to(tgt["pos"]) / 600.0, 0.35, 0.9)   # 恒速~600px/s, 慢到看得清(原0.2太快)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": Color("#4dabf7"),
		"src": src, "t": 0.0, "dur": dur, "basic_onhit": false, "freeze_on_hit": 1.5,
	})

func _sk_ninja_impact(u: Dictionary, tgt: Dictionary) -> void:   # 忍者龟·冲击 ✅
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	_dash_to(u, tgt, 60.0)
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ff9d5c"))
	_knockback(u, tgt, 50.0)
	for o in _enemies_of(u):
		if o == tgt:
			continue
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#ff9d5c"))

func _sk_ghost_soulstorm(u: Dictionary, tgt: Dictionary) -> void: # 幽灵龟·灵魂风暴 ✅
	var cursed: bool = _has_dot(tgt, "curse")
	if cursed:
		_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt, true), Color("#e0b0ff"))
	else:
		for i in range(2):
			_apply_damage_from(u, tgt, _atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))
		_add_dot(tgt, "curse", tgt["maxHp"] * 0.05, BUFF_SEC)

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧 ✅
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true); _buff(u, "mr", 0.2, true)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷 ✅
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o), Color("#ff4444"), 0.30)

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.65)

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌 ✅
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ff4444"))
	_grant_shield(u, u["atk"] * 0.25)
	_heal(u, u["maxHp"] * 0.05)
	_buff(tgt, "atk", -0.15, true)

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽 ✅
	var tgt = _nearest_enemy(u)
	if tgt != null:
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ff4444"))
	_buff(u, "dodge", 0.25, true)
	_grant_shield(u, u["atk"] * 0.7)   # 0.6→0.7 (恢复文本设计值)

func _sk_pirate_volley(u: Dictionary) -> void:                   # 海盗龟·火炮齐射 ✅
	for o in _enemies_of(u):
		for i in range(6):
			_apply_damage_from(u, o, _atk_dmg(u, 0.17, o) + int(o["maxHp"] * 0.017), Color("#ffd07a"))

func _sk_bubble_shield(u: Dictionary, _tgt: Dictionary) -> void: # 泡泡龟·泡泡盾 ✅(简化:无延迟爆裂)
	var ally = _lowest_hp_ally(u)
	if ally == null: ally = u
	_grant_shield(ally, u["atk"] * 1.8)
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 2.0, o, true), Color("#cdebff"))

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅
	var picked := 0
	for o in _enemies_of(u):
		if picked >= 2: break
		_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#dddddd"))
		_add_stack(o, "ink", 1, 5)
		picked += 1

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
	var tw := create_tween()
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
		var twr := create_tween()
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
		var tw := create_tween()
		tw.tween_property(disc, "modulate:a", 0.0, 0.4)
		tw.chain().tween_callback(disc.queue_free)
	u["storm_disc"] = null

func _sk_fortune_coins(u: Dictionary) -> void:                  # 财神龟·聚财 ✅ (立即+10金币)
	u["gold"] += 10
	_skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.5), 46.0)

func _sk_phoenix_purify(u: Dictionary) -> void:                 # 凤凰龟·火焰净化 ✅ (净化友方+按减益数回血)
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	var n := _cleanse(ally)
	if n > 0:
		_heal(ally, ally["maxHp"] * 0.10 * n)
	_skill_ring(ally["pos"], Color(1.0, 0.7, 0.3, 0.5), 48.0)

func _sk_lightning_shock(u: Dictionary) -> void:               # 闪电龟·感电 ✅ (按电击层每层0.10ATK真伤+清层)
	for o in _enemies_of(u):
		if not o.get("alive", false):
			continue
		var st := _consume_stacks(o, "electric")
		if st > 0:
			_apply_damage_from(u, o, int(u["atk"] * 0.10 * st), Color("#4dabf7"), 0.0, true)
			_skill_ring(o["pos"], Color(0.45, 0.85, 1.0, 0.5), 46.0)

func _sk_lightning_shield(u: Dictionary) -> void:              # 闪电龟·雷盾 ✅ (0.9ATK护盾, 盾在时反击=见_apply_damage_from)
	_grant_shield(u, u["atk"] * 0.9)
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

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 ✅
	_grant_shield(u, u["atk"] * 0.75)
	u["lava_shield_until"] = _t + 5.0          # 5秒内每受一段攻击反击0.14×ATK魔法(见_apply_damage_from)
	_skill_ring(u["pos"], Color(1.0, 0.5, 0.2, 0.5), 50.0)

func _sk_headless_fear(u: Dictionary, tgt: Dictionary) -> void:  # 无头龟·恐吓 ✅
	_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ff4444"))
	_buff(tgt, "atk", -0.20, true)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子 ✅
	u["gold"] += randi_range(3, 8)   # 2~6→3~8 (恢复文本设计值)
	_heal(u, u["maxHp"] * 0.08)
	# (删: "放梭哈后给护盾"=4选1下死逻辑, 不可能同时有骰子+梭哈, 用户指出)

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒 ✅
	_grant_shield(u, u["atk"] * 0.9)
	for o in _allies_of(u):
		_buff(o, "def", 0.15, true); _buff(o, "mr", 0.15, true)

# 宝箱·藏宝图(完整实装): 造成伤害积累财宝值(=dmg_dealt), 过阈值开装备(分层池)+回血, 一场最多5件
func _chest_treasure_tick(u: Dictionary) -> void:
	var opened: int = int(u.get("chest_opened", 0))
	if opened >= 5:
		return
	var thresh: Array = [80.0, 130.0, 240.0, 360.0, 590.0]
	if float(u.get("dmg_dealt", 0.0)) < float(thresh[opened]):
		return
	u["chest_opened"] = opened + 1
	var tier: Array = [[1, 2], [1, 2], [3, 4], [3, 4], [5]][opened]   # 1-2基础/3-4进阶/5传说
	var heal_pct: float = [0.08, 0.08, 0.11, 0.11, 0.15][opened]
	var iid: String = _chest_pick_equip(tier)
	if iid != "":
		if not u.has("equips"): u["equips"] = []
		u["equips"].append({"id": iid, "star": 1})
		if not u.has("eq_state"): u["eq_state"] = {}
		u["eq_state"][iid] = {}
		_eq_apply_one_stats(u, iid, 1)
		var nm: String = str(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("name", iid))
		_float_text(u["pos"] + Vector2(0, -72), "开箱! " + nm, Color("#ffd93d"))
	_heal(u, u["maxHp"] * heal_pct)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.5), 52.0)

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

func _sk_space_meteor(u: Dictionary) -> void:                    # 星际龟·流星暴击 ✅
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#c9b0ff"))
		_buff(o, "mr", -0.2, true)
	if u["star_energy"] >= u["maxHp"] * 0.40:
		var burst: float = u["star_energy"]
		u["star_energy"] = 0.0
		for o in _enemies_of(u):
			_raw_lose(o, burst)
			_float_text(o["pos"] + Vector2(0, -48), str(int(burst)), Color("#ffd0ff"))

func _sk_candy_armor(u: Dictionary) -> void:                     # 糖果龟·焦糖铠 ✅
	_grant_shield(u, u["atk"] * 0.8)
	_heal(u, u["maxHp"] * 0.10)

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

func _sk_two_head(u: Dictionary, tgt: Dictionary) -> void:       # 双头龟 ✅ 选一套+切换形态
	var set_id: String = u.get("two_set", "1")
	u["two_form"] = "ranged" if u.get("two_form", "melee") == "melee" else "melee"
	var to_ranged: bool = u["two_form"] == "ranged"
	_two_head_apply_melee(u, not to_ranged)   # 形态属性增减
	u["melee"] = not to_ranged
	u["atk_range"] = 300.0 if to_ranged else 70.0
	u["atk_interval"] = 1.1 if not to_ranged else 0.8
	if not to_ranged:
		match set_id:
			"1", "3":
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt), Color("#ffb05c"))
				_grant_shield(u, u["atk"] * 0.5)
			"2":
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ffb05c"), 0.35)
	else:
		match set_id:
			"1":
				tgt["shield"] *= 0.5
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt, true), Color("#c0d0ff"))
				_buff(tgt, "atk", -0.20, true)
			"2":
				for i in range(4):
					if not tgt["alive"]: break
					_apply_damage_from(u, tgt, _atk_dmg(u, 0.6, tgt, i % 2 == 0), Color("#c0d0ff"))
			"3":
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true) + int(o["maxHp"] * 0.15), Color("#c0d0ff"))

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

func _lava_bolt(u: Dictionary, tgt: Dictionary) -> void:         # 熔岩弹: 0.6×ATK魔 + 4%目标最大HP + 0.125×ATK灼烧层 (用户2026-06-30)
	if tgt == null or not tgt.get("alive", false):
		return
	var dmg := _atk_dmg(u, 0.6, tgt, true) + int(tgt["maxHp"] * 0.04)
	_apply_damage_from(u, tgt, dmg, Color("#ff7a3c"))
	_apply_dot_stacks(tgt, "burn", maxi(1, int(round(float(u["atk"]) * 0.07))), u)   # 0.125×ATK 灼烧层(层数DoT)
	_skill_ring(tgt["pos"], Color(1.0, 0.48, 0.24, 0.4), 46.0)

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
					o["slow_until"] = maxf(float(o.get("slow_until", 0.0)), _t + 0.6)             # 减速(move ×0.6=减40%, ≥0.6s续)
					_buff(o, "mr", -0.30, true, 0.6)                                              # 魔抗-30% (每跳刷新)
		if _t >= float(z["until"]):
			var disc = z.get("disc", null)
			if disc != null and is_instance_valid(disc):
				var tw := create_tween()
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
	var rot := create_tween().set_loops()                        # 缓旋=熔岩流动(静态图+代码动)
	rot.tween_property(disc, "rotation:y", TAU, 7.0).from(0.0)
	var pt := create_tween()                                     # 淡入 + 5秒缓脉动
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
	var tt := create_tween()
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
	var hit: Dictionary = {}                                       # 已命中敌 (each-once)
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
			hit[o] = true                                         # 命中一次 (字典引用作键, each-once)
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
	var wt := create_tween()
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
	var cg := create_tween()
	cg.tween_property(glow, "modulate:a", 0.9, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.6, 1.6, 1.6), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge := create_tween(); charge.tween_interval(0.5)
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
	var pt := create_tween()
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
	var cg := create_tween()
	cg.tween_property(glow, "modulate:a", 0.92, 0.4).set_trans(Tween.TRANS_QUAD)
	cg.parallel().tween_property(glow, "scale", Vector3(1.8, 1.8, 1.8), 0.5)
	cg.tween_property(glow, "modulate:a", 0.0, 0.15)
	cg.chain().tween_callback(glow.queue_free)
	var charge := create_tween(); charge.tween_interval(0.5)
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
	var td := create_tween()
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
	var t := create_tween()
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
	var up := create_tween(); up.set_parallel(true)
	up.tween_method(func(h): u["height"] = h, 0.0, LAVA_LEAP_H, LAVA_LEAP_UP_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_method(func(p): u["pos"] = p, start, target, LAVA_LEAP_UP_T).set_trans(Tween.TRANS_SINE)
	await up.finished
	# 2) 滞空蓄力 (悬停高处, 火光渐聚, 不直接砸)
	_lava_charge_vfx(u)
	var hover := create_tween()
	hover.tween_interval(LAVA_CHARGE_T)
	await hover.finished
	# 3) 砸地
	var down := create_tween()
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
	var bt := create_tween()
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

func _sk_cyber_cannon(u: Dictionary, tgt: Dictionary) -> void:   # 赛博龟·能量大炮 ⚠
	_dash_to(u, tgt, 80.0)
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#9bf0ff"))
	var drones: int = u["summons"].size()
	if drones > 0:
		_apply_damage_from(u, tgt, int(u["atk"] * 0.1 * drones), Color("#d0ffff"), 0.0, true)

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御 ⚠
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true)

func _sk_shell_absorb(u: Dictionary, tgt: Dictionary) -> void:   # 龟壳·吸收 ⚠
	var steal: float = tgt["maxHp"] * 0.10
	_raw_lose(tgt, steal)
	_heal(u, steal)

func _sk_burst(u: Dictionary, tgt: Dictionary) -> void:          # 兜底重击
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt), Color("#ff9d5c"))
	for o in _enemies_of(u):
		if o != tgt and (o["pos"] - tgt["pos"]).length() <= 110.0:
			_apply_damage_from(u, o, _atk_dmg(u, 1.25, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"], Color(1.0, 0.6, 0.3, 0.5), 110.0)

# ── 选3 多技能: 数据驱动伤害技 + 通用盾/治 (系数取自 pets.json detail 公式) ──
# opts: {phys,magic,true: ×casterATK 的 物理/魔法/真实系数; hp,mr: ×caster maxHp/MR 附加;
#        hits: 视觉段数(伤害总量不变); aoe: 全体敌; rider: 附带(burn/stun/slow/curse/atkdn/mrdn); name,color}
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
	var fixed: Array = _enemies_of(u) if aoe else ([tgt] if tgt != null else [])
	if stagger > 0.0:
		var tw := create_tween()
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
			_apply_damage_from(u, e, dmg, col)
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
		"slow":  e["slow_until"] = maxf(float(e.get("slow_until", 0.0)), _t + _cc_dur(e, BUFF_SEC))
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

# 数据驱动治疗/加固: 每龟读自己 fx (healHp/buffDef/buffMr) + 技能名
func _sk_gen_heal(u: Dictionary) -> void:
	var sk := _cur_skill_data(u, "heal")
	var fx: Dictionary = sk.get("fx", {})
	var nm := str(sk.get("name", "治疗"))
	var heal_hp := float(fx.get("healHp", 0.16))
	var bdef := float(fx.get("buffDef", 0.0))
	var bmr := float(fx.get("buffMr", 0.0))
	var bdur := float(fx.get("buffDur", 5.0))
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	if heal_hp > 0.0:
		_heal(ally, ally["maxHp"] * heal_hp)
	if bdef > 0.0:
		_buff(ally, "def", bdef, true, bdur)
	if bmr > 0.0:
		_buff(ally, "mr", bmr, true, bdur)
	_float_text(ally["pos"] + Vector2(0, -64), nm + "!", Color("#39d353"))

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
		"node": p, "from": world_from, "tgt": tgt, "dmg": _atk_dmg(src, 0.22, tgt, false),
		"col": Color("#ff4444"), "src": src, "t": 0.0, "dur": dur, "basic_onhit": false,
		"coin_true": int(src["atk"] * 0.22),
	})

# 星际·虫洞: 永久+魔法穿透; 沿目标方向直线四段 1.5×ATK×(1+10%×已过秒) 魔法 + 击飞
func _sk_star_wormhole(u: Dictionary, tgt) -> void:
	if tgt == null:
		return
	u["magic_pen"] += 8.0                           # 永久魔穿
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	var mult: float = 1.5 * (1.0 + 0.1 * _t)        # 随战斗时间变强
	for o in _enemies_of(u):
		if o == tgt or _on_line(u["pos"], dir, o["pos"], 70.0):
			for i in range(4):
				if not o["alive"]:
					break
				_apply_damage_from(u, o, _atk_dmg(u, mult / 4.0, o, true), Color("#ffffff"))
			_knockback(u, o, 55.0)
			_skill_ring(o["pos"], Color(0.75, 0.6, 1.0, 0.5), 50.0)

# 线条·收尾: 引爆敌身墨迹(每层额外伤害)然后清空 (lineLink/普攻叠的 ink)
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
	if best_ink > 0:
		_consume_stacks(best, "ink")
	_skill_ring(best["pos"], Color(0.9, 0.9, 0.9, 0.5), 48.0)

# 赛博·部署: 立即放3个浮游炮 (与被动「浮游炮」同型, 上限10)
func _sk_cyber_deploy(u: Dictionary) -> void:
	for i in range(3):
		if u["summons"].size() >= 10:
			break
		var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25, {
			"label": "浮游炮", "col_size": 16.0, "hp_w": 22.0, "melee": false,
			"no_basic": true, "special": "random_hit", "special_cd": 1.6, "special_scale": 0.25,
		})
		if dr != null:
			u["summons"].append(dr)

# 泡泡·束缚: 定身目标 1.5s + 束缚期间每受一段伤害 永久-X护甲/魔抗 (见 _apply_damage_from 钩子)
func _sk_bubble_bind(u: Dictionary, tgt) -> void:
	if tgt == null:
		return
	tgt["stun_until"] = maxf(float(tgt.get("stun_until", 0.0)), _t + _cc_dur(tgt, CTRL_SEC))
	tgt["bind_until"] = _t + CTRL_SEC
	tgt["bind_shred"] = 2.0
	tgt["bind_acc"] = 0.0
	_skill_ring(tgt["pos"], Color(0.5, 0.9, 1.0, 0.5), 50.0)

# 缩头·出击令: 命令本体随从立即额外出手一次
func _sk_hiding_command(u: Dictionary) -> void:
	for o in _units:
		if o.get("summon_owner", null) == u and o.get("alive", false):
			var mt = _nearest_enemy(o)
			if mt != null:
				_melee_lunge(o, mt)
				_apply_damage_from(o, mt, _atk_dmg(o, 1.2, mt), Color("#a8ffb0"))

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
	u["crit_fate_until"] = _t + 5.0
	u["crit_fate_amt"] = add_crit
	u["crit_dmg_fate_amt"] = add_cd
	_float_text(u["pos"] + Vector2(0, -64), "命运骰子! +%d%%暴击" % int(roll * 100), Color("#ffd93d"))

# 龟壳·复制: 随机复制 2 个敌方可用技立即释放 (60%效果简化为全效, 留 batch3)
func _sk_shell_copy(u: Dictionary, tgt) -> void:
	var pool: Array = []
	for o in _enemies_of(u):
		for st in o.get("active_skills", []):
			var s := str(st)
			if _COPYABLE_SKILLS.has(s) and not pool.has(s):
				pool.append(s)
	pool.shuffle()
	for i in range(mini(2, pool.size())):
		_do_skill(u, tgt, str(pool[i]))

# ============================================================================
#  效果积木 (可复用) — 治疗/护盾/控制/buff/DoT/吸血/累积/净化/叠层 (1:1 搬自 2D 版).
#  注: 3D 版血条 overlay 每帧统一刷新, 故去掉 2D 版各处的 _update_bars(u) 调用.
# ============================================================================
func _grant_shield(u: Dictionary, amt: float) -> void:
	if amt <= 0.0: return
	amt *= 1.0 + float(u.get("shield_amp", 0.0))   # 护盾加成(受到方,所有来源)
	var sb: float = u["shield"]
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)
	var got := int(u["shield"] - sb)
	u["_st_shield"] = int(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾
	if got >= 8:                             # #1 护盾飘字 "+N 盾" (浅蓝); 门槛过滤每帧微盾被动防刷屏
		_float_text(u["pos"] + Vector2(0, -52), "+%d 盾" % got, Color("#ffffff"), false, "shield")
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)
	_sfx_shield_gain()                       # §AUDIO: 得盾音 (节流; 群体上盾不刷屏)

# silent=true: 吸血等高频被动回血不出治疗音 (防刷屏), 主动治疗/技能回血出音
func _heal(u: Dictionary, amt: float, silent: bool = false) -> void:
	if amt <= 0.0: return
	amt *= 1.0 + float(u.get("heal_amp", 0.0))   # 治疗加成(受到方,所有来源)
	if _t < float(u.get("heal_reduce_until", 0.0)):
		amt *= maxf(0.0, 1.0 - float(u.get("heal_reduce_pct", 0.0)))   # 治疗削减(凤凰涅槃/烫伤等)
	var hb: float = u["hp"]
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	u["_st_heal"] = int(u.get("_st_heal", 0)) + int(u["hp"] - hb)   # §STATS: 实际回复(超过满血不计)
	_float_text(u["pos"] + Vector2(0, -40), "+" + str(int(amt)), Color("#06d6a0"), false, "heal")
	if not silent:
		_sfx_heal()                          # §AUDIO: 治疗音 (节流)

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
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(sh, "position:y", sh.position.y + (0.9 if big else 0.6), 0.55)
		tw.tween_property(sh, "modulate:a", 0.0, 0.55)
		tw.chain().tween_callback(sh.queue_free)

func _apply_spawn_passives() -> void:
	for u in _units.duplicate():
		match u["id"]:
			"rainbow":
				u["prism_color"] = _juice_rng.randi() % 3   # 开局即给棱镜色(修: 原-1致前6秒普攻无附色)
			"ninja":
				u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["armor_pen"] += 8.0
				_buff(u, "dodge", 0.25, false, 9999.0)
			"ghost":
				for o in _enemies_of(u):
					_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
			"ice":
				u["_vs_fire_bonus"] = 0.2          # 天生: 对熔岩/凤凰 +20%伤害(极寒技选了覆盖成0.4)
				_ice_chill_vfx(u["pos"], true)     # 寒冰自身登场寒爆(大)
				_flash(u, Color(0.6, 0.86, 1.0))   # 自身蓝闪
				for o in _enemies_of(u):
					o["spd_aspd_mult"] = 0.7        # -30% 攻速
					o["spd_echarge_mult"] = 0.7     # -30% 龟能充能速度
					o["spd_move_mult"] = 0.7        # -30% 移速
					o["spd_dbf_until"] = _t + 99999.0   # 登场全场(用户未定时长→默认永久)
					_ice_chill_vfx(o["pos"])        # 敌人寒气蓝环
					_flash(o, Color(0.6, 0.86, 1.0))   # 敌蓝闪
			"headless":
				u["lifesteal"] += 0.22
			"dice":
				u["dice_base_crit"] = u["crit"]; u["dice_base_critdmg"] = u["crit_dmg"]   # 基准(供损血暴击算); 原无条件转护穿=候选强化已锁,去掉
			"pirate":
				var es := _enemies_of(u)
				if not es.is_empty():
					var v = es[randi() % es.size()]
					_raw_lose(v, v["maxHp"] * 0.25)
			"candy":
				var ce := _enemies_of(u)
				if not ce.is_empty():
					var v = ce[randi() % ce.size()]
					var steal: float = minf(v["maxHp"] * 0.25, v["hp"] - 1.0)
					if steal > 0: _raw_lose(v, steal); _heal(u, steal)
				_spawn_summon(u, "candybomb", u["maxHp"] * 0.40, 0.0, {
					"label": "糖果炸弹", "spr_id": "candy-bomb", "col_size": 20.0, "hp_w": 24.0,
					"no_basic": true, "no_move": true, "self_decay": 0.08,
					"death_aoe": 1.5,
				})
			"hiding":
				_spawn_hiding_minion(u)
			"crystal":
				_spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
					"label": "水晶球", "spr_id": "crystal-ball", "col_size": 20.0, "hp_w": 26.0, "melee": false,
					"move_spd": 90.0, "atk_range": 320.0, "no_basic": true,
					"special": "ray", "special_cd": 2.5, "special_scale": 0.5,
				})
			"lava":
				# 强化熔岩之心(4选1被动): 开战即满怒气 → 下一周期tick立即变身火山龟
				if "lavaEnhancedRage" in _chosen_skill_types(u["id"], u["side"] == "left"):
					u["rage"] = RAGE_MAX
			"two_head":
				u["two_set"] = "1"; u["two_form"] = "melee"
				_two_head_apply_melee(u, true)   # 登场=近战形态, 上加成
			"diamond":                                    # 钻石结构: 全队护甲/魔抗加成(简化为开局给队伍+防)
				for o in _allies_of(u):
					_buff(o, "def", 0.25, true, 9999.0)
					_buff(o, "mr", 0.25, true, 9999.0)
	# 4选1 被动技 (选了被动则开局生效, 不进主动轮转): 寒冰免疫灼烧 + 对熔岩/凤凰 +40%
	for u in _units:
		if "iceBurnImmune" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_burnImmune"] = true
			u["_vs_fire_bonus"] = 0.4
		if "phoenixEnhancedRebirth" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["_enh_rebirth"] = true   # 强化涅槃: 复活100%血+永久+20%攻击(见_kill)

func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":
			_add_stack(tgt, "ink", 1, 5)
		"lightning":
			_lightning_electric(u, tgt)   # 普攻主目标叠电击+可引爆(连锁跳由_lightning_hop叠)
		"crystal":
			var cv := _add_stack(tgt, "crystal", 1, 4)
			if cv >= 4:
				_consume_stacks(tgt, "crystal")
				_apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
				_buff(tgt, "mr", -0.2, true)
		"angel":                                          # 审判: 每段攻击额外 +目标当前HP 11% 魔法
			_apply_damage_from(u, tgt, _mitigate(u, tgt["hp"] * 0.11, tgt, true), Color("#9be7ff"), 0.0, false)   # 魔法(吃魔抗+蓝字), 原flat固定值绕魔抗+错色=bug
		# gambler 多重打击改云顶剑士式连击(见状态机 _gambler_multi_cd), 不在这里追加
		"bamboo":                                         # 生长(改造): 蓄力时下一发普攻强化(追加魔法+回血+永久成长)
			if u.get("bamboo_charge", false):
				u["bamboo_charge"] = false
				_apply_damage_from(u, tgt, _mitigate(u, u["atk"] * 0.75 + u["maxHp"] * 0.06, tgt, true), Color("#9be7ff"), 0.0, false)   # 魔法(吃魔抗+蓝字), 原flat固定值=bug
				_flash(tgt, Color(0.5, 1.7, 0.65))   # 充能追击: 敌受击改绿色闪光(生长主题, 用户)
				# 回血+永久成长 延到绿球落到竹叶龟身上才生效 (用户: 到自己身上才吸收)
				_spawn_bamboo_orb(tgt["pos"], u["pos"], func() -> void:
					if not u.get("alive", false):
						return
					_heal(u, u["maxHp"] * 0.06)
					u["base_atk"] *= 1.06; u["maxHp"] *= 1.03; _recalc_stats(u))
		"rainbow":                                        # 棱镜(改造): 普攻附当前颜色效果(红真伤/蓝小盾/绿回血)
			match int(u.get("prism_color", -1)):
				0: _apply_damage_from(u, tgt, int(u["atk"] * 0.25), Color("#ff6b6b"), 0.0, true)   # 红: 额外真伤
				1: _grant_shield(u, u["atk"] * 0.2)                                                # 蓝: 每普攻获小盾
				2: _heal(u, (u["maxHp"] - u["hp"]) * 0.025, true)                                               # 绿: 回2%最大HP
	# 猎人猎杀: 攻击后斩杀<14%HP敌
	if u["id"] == "hunter" and tgt["alive"] and tgt["hp"] < tgt["maxHp"] * 0.14:
		var was_alive: bool = tgt["alive"]
		tgt["hp"] = 0.0
		if was_alive:
			_kill(tgt, u)
	# 无头亡灵: 每损1%HP攻击+1%(上限+100%)
	if u["id"] == "headless":
		var lost_pct: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["atk"] = u["base_atk"] * (1.0 + lost_pct)

func _tick_periodic_passive(u: Dictionary, delta: float) -> void:
	u["_ptimer"] = u.get("_ptimer", 0.0) + delta
	# --- 熔岩变身: 怒气满100 → 变火山15秒 (被动 熔岩之心) ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		_lava_transform(u)
	if u.get("volcano", false) and _t >= float(u.get("volcano_until", 0.0)):
		_lava_revert(u)
	if u["id"] == "chest":
		_chest_treasure_tick(u)
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
			if u["summons"].size() < 10:
				var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25, {
					"label": "浮游炮", "col_size": 16.0, "hp_w": 22.0, "melee": false,
					"move_spd": 110.0, "atk_range": 300.0, "atk_interval": 1.0,
					"no_basic": true, "special": "random_hit", "special_cd": 1.6, "special_scale": 0.25,
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
		if not u.get("awakened2", false) and _t >= 20.0 and "shellEnhanceAwaken" in _chosen_skill_types(u["id"], u["side"] == "left"):
			u["awakened2"] = true
			_shell_apply_awaken(u)   # 强化觉醒(idx4): 开战20秒第二次觉醒(再叠同款)
		# 储能相位机: store(6s 受伤转储能) → 释放(冲击波+护盾) → cd(15s 不储) → store…
		_shell_phase_tick(u, delta)
	# --- 海盗船召唤: 开战~4秒后召唤一次 ---
	if u["id"] == "pirate" and not u.get("ship_summoned", false) and _t >= 4.0:
		u["ship_summoned"] = true
		_spawn_pirate_ship(u)
	# --- 财神聚宝盆: 每3秒 +4~7金币 (用户) ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 3.0:
			u["_goldtimer"] = 0.0; u["gold"] += _juice_rng.randi_range(4, 7)
	# --- 彩虹棱镜: 每2.5s 全队随机增益5s (红攻/蓝防/绿回血) ---
	if u["id"] == "rainbow":
		u["_rbtimer"] = u.get("_rbtimer", 0.0) + delta
		if u["_rbtimer"] >= 6.0:
			u["_rbtimer"] = 0.0
			u["prism_color"] = randi() % 3   # 棱镜(改造): 自身获颜色6秒, 普攻附色(见 _on_basic_hit)
	# --- 泡泡·泡沫: 每2.5s 消耗15%泡泡回血 + 35%泡泡打随机敌 ---
	if u["id"] == "bubble":
		u["_bbtimer"] = u.get("_bbtimer", 0.0) + delta
		if u["_bbtimer"] >= 2.5:
			u["_bbtimer"] = 0.0
			var bs: float = float(u.get("bubble_store", 0.0))
			if bs >= 1.0:
				_heal(u, bs * 0.15, true)
				var bes := _enemies_of(u)
				if not bes.is_empty():
					var bv = bes[randi() % bes.size()]
					_apply_damage_from(u, bv, int(bs * 0.35), Color("#aef1ff"), 0.0, true)
				u["bubble_store"] = bs * 0.50
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
	var ah: float = u["maxHp"] * 0.12; u["maxHp"] += ah; u["hp"] += ah   # +12%最大生命 (反伤无独立stat字段, 略)
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
	var tp := create_tween(); tp.set_parallel(true)
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
		var tw := create_tween()
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
	# 财神聚宝盆: 任意单位阵亡 → 全场存活的财神龟 +9 金币
	for f in _units:
		if f.get("alive", false) and f.get("id") == "fortune" and f != u:
			f["gold"] += 9
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_apply_damage_from(u, o, int(per), Color("#ff8ad8"), 0.0, true, true)
			_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 120.0)
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o["alive"]:
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
	# 海盗掠夺: 死亡钩锁击杀者 25% 最大HP 真伤
	if u["id"] == "pirate" and killer != null and killer["alive"]:
		_raw_lose(killer, killer["maxHp"] * 0.25)

# ============================================================================
#  召唤系统 (3D 化: billboard 立绘/色块 + blob影, 走同一 _tick_unit) — 逻辑 1:1 搬自 2D 版
# ============================================================================
const HIDING_POOL := ["basic", "stone", "bamboo", "ninja", "dice", "rainbow", "hunter", "pirate", "candy", "bubble", "line", "headless"]

func _spawn_hiding_minion(u: Dictionary) -> void:
	var pick: String = HIDING_POOL[randi() % HIDING_POOL.size()]
	var d: Dictionary = _data_by_id.get(pick, {})
	var st: Array = STATS.get(pick, DEFAULT_STAT)
	var _lm: float = _lvl_mult_for(u)                # 固定值召唤吃等级
	var hp: float = float(d.get("hp", 1350)) * 0.40 * _lm  # 召唤=主人最终hp×40% (×等级)
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8 * _lm, {
		"label": "随从", "spr_id": pick, "col_size": 36.0, "hp_w": 30.0,
		"melee": bool(st[0]), "move_spd": float(st[1]), "atk_interval": float(st[2]), "atk_range": float(st[3]),
		"crit": float(d.get("crit", 0.2)),
	})
	if minion != null:
		minion["minion_kind"] = pick
		minion["hiding_protected"] = true

func _spawn_pirate_ship(u: Dictionary) -> void:
	var ship = _spawn_summon(u, "ship", u["maxHp"] * 1.5, u["atk"], {
		"label": "海盗船", "col_size": 38.0, "hp_w": 44.0, "melee": false,
		"move_spd": 70.0, "atk_range": 360.0, "no_basic": true,
		"special": "cannon", "special_cd": 2.0, "special_scale": 0.2,
	})
	if ship != null:
		pass

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
		"bar_root": bar["root"], "hp_bar": bar["hp_bar"], "en_fill": bar["en"],
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
		"ray":
			var t = _nearest_enemy(u)
			if t == null: return
			_bolt_line(u["pos"], t["pos"], Color("#c9b0ff"))
			for i in range(2):
				if not t["alive"]: break
				_apply_damage_from(u, t, _atk_dmg(u, u.get("special_scale", 1.0), t, true), Color("#c9b0ff"), 0.0, true)
			if t["alive"]:
				var cv := _add_stack(t, "crystal", 1, 4)
				if cv >= 4:
					_consume_stacks(t, "crystal")
					_apply_damage_from(u, t, int(t["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
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
		# 朝向跟移动方向 (立绘默认朝左→flip_h=true朝右); 不动则保持上次朝向; 初始左队朝右/右队朝左
		var _px: float = u["pos"].x
		var _dx: float = _px - float(u.get("last_x", _px))
		if absf(_dx) > 0.3:
			u["face_right"] = _dx > 0.0
		u["last_x"] = _px
		spr.flip_h = bool(u.get("face_right", str(u["side"]) == "left"))
		# --- Phase4: squash/stretch 形变 + idle bob 高度微浮 (全从 base 起算, 不累积) ---
		var sq := _juice_scale_for(u)              # (sx, sy) 形变系数 (base=1,1)
		var bob := _juice_bob_for(u)               # idle 呼吸 Y 偏移 (米)
		# 立绘: XZ + Y(高度 + 落地基线抬升 + bob). billboard 自动朝镜头, 不翻 facing.
		spr.position = _world_pos(u["pos"], u["height"] + GROUND_LIFT + bob)
		var bs: Vector3 = u.get("spr_base_scale", Vector3.ONE)
		spr.scale = Vector3(bs.x * sq.x, bs.y * sq.y, bs.z)
		# 受击闪白: modulate 由 base 白 → 过曝白线性插值 (flash_t/JUICE_FLASH_SEC); 死亡淡出走 alpha 不冲突
		var fl: float = clampf(u.get("flash_t", 0.0) / JUICE_FLASH_SEC, 0.0, 1.0)
		spr.modulate = Color.WHITE.lerp(u.get("flash_col", JUICE_FLASH_COLOR), fl)
		# 影/环: 跟 XZ 不跟 Y (贴地), 随高度缩小变淡 (从各自基准 scale 起算, 召唤体影更小)
		var s: float = 1.0 - clampf(u["height"] / 3.0, 0.0, 0.7)
		if is_instance_valid(shadow):
			var base_sc: Vector3 = u.get("shadow_base_scale", SHADOW_BASE)
			shadow.position = _world_pos(u["pos"], 0.02)
			# 影也随 squash 横向张缩 (压扁→影变宽, 拉长→影变窄) 加重量感
			shadow.scale = Vector3(base_sc.x * s * sq.x, base_sc.y * s, base_sc.z * s)
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
	for u in _units:
		if not u["alive"]:
			continue
		if u.get("flash_t", 0.0) > 0.0:  u["flash_t"]  = maxf(0.0, u["flash_t"]  - delta)
		if u.get("hitsq_t", 0.0) > 0.0:  u["hitsq_t"]  = maxf(0.0, u["hitsq_t"]  - delta)
		if u.get("land_t", 0.0) > 0.0:   u["land_t"]   = maxf(0.0, u["land_t"]   - delta)
		if u.get("swing_t", 0.0) > 0.0:  u["swing_t"]  = maxf(0.0, u["swing_t"]  - delta)
		if u.get("windup_t", 0.0) > 0.0: u["windup_t"] = maxf(0.0, u["windup_t"] - delta)

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
	_play_action(u, "hurt")         # 有受击帧的龟播 hurt 动画 (不打断 death/attack)

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
var _spark_tex: GradientTexture2D = null
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
	var tw := create_tween(); tw.set_parallel(true)
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
	var tw2 := create_tween(); tw2.set_parallel(true)
	tw2.tween_property(sp, "scale", Vector3.ONE * 1.1, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(sp, "modulate:a", 0.0, 0.12)
	tw2.chain().tween_callback(sp.queue_free)

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
	var tw := create_tween()
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
	create_tween().tween_interval(1.0).tween_callback(ps.queue_free)

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
	create_tween().tween_interval(1.0).tween_callback(ps.queue_free)

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
		root.position = screen - Vector2(BAR_W * 0.5, 8)   # 居中 (条宽 BAR_W)

# ============================================================================
#  灭队判定 + 结算横幅 (复用 2D _check_end; 赛季结算 Phase 3 接 GameState)
# ============================================================================
func _check_end() -> void:
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"] and not u.get("is_summon", false):   # 召唤体不计入胜负判定
			if u["side"] == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		var won: bool = right_alive == 0
		_settle_season(won)        # 结果喂赛季 (命/币/胜场/XP/ghost), 守卫一次性
		_show_banner(won)

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
	var sub := Label.new()
	sub.text = "[R 再战 · ESC 返回菜单]"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	sub.size = Vector2(1280, 26); sub.position = Vector2(0, 396)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(sub)
	_build_stats_panel()             # #2 战斗统计面板

# #2 伤害统计面板: 结算时显双方各龟 输出/承受/回复/护盾 (统计在 _apply_damage* / _heal / _grant_shield 累计)
func _build_stats_panel() -> void:
	var lefts: Array = []
	var rights: Array = []
	for u in _units:
		if u.get("is_summon", false):
			continue                 # 只统计上场龟, 不含召唤体/中立
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
	cols.add_theme_constant_override("separation", 34)
	vb.add_child(cols)
	cols.add_child(_stats_column("🔵 我方", lefts, Color("#7ec8ff")))
	cols.add_child(_stats_column("🔴 敌方", rights, Color("#ff9a9a")))
	_ui_layer.add_child(panel)
	# 自动居中(下半屏): 等一帧布局算出尺寸后摆位
	panel.position = Vector2(316, 438)
	_center_panel_deferred(panel)

func _center_panel_deferred(panel: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(panel):
		panel.position = Vector2(640.0 - panel.size.x * 0.5, 438.0)

func _stats_column(header: String, units: Array, hc: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	var hdrs := [header, "输出", "承受", "回复", "护盾"]
	for i in range(5):
		var l := Label.new()
		l.text = hdrs[i]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", hc if i == 0 else Color("#8aa0b4"))
		if i == 0:
			l.custom_minimum_size = Vector2(96, 0)
		else:
			l.custom_minimum_size = Vector2(52, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for u in units:
		var dead: bool = not u.get("alive", true)
		var nm := str(u.get("name", u.get("id", "")))
		var cells := [("💀 " if dead else "") + nm, str(int(u.get("_st_dealt", 0))), str(int(u.get("_st_taken", 0))), str(int(u.get("_st_heal", 0))), str(int(u.get("_st_shield", 0)))]
		var rcol := [Color("#e8f0f6"), Color("#ffcf6b"), Color("#ff8f8f"), Color("#7fe39a"), Color("#9fd0ff")]
		for i in range(5):
			var l := Label.new()
			l.text = cells[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Color("#7a8a96") if dead else rcol[i])
			if i == 0:
				l.custom_minimum_size = Vector2(96, 0)
			else:
				l.custom_minimum_size = Vector2(52, 0)
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
func _self_screenshot() -> void:
	var delay := 3.0
	var s := OS.get_environment("SELFSHOT")
	if s.is_valid_float() and s.to_float() > 0.1:
		delay = s.to_float()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := "res://_p2_battle.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
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
	if REVIEW_DEMO:
		return                          # 评审: 受审龟裸装, 看纯内在数值(装备另行评审)
	var gs = get_node_or_null("/root/GameState")
	var pe: Dictionary = {}
	if gs != null and gs.get("persistent_equipped") is Dictionary:
		pe = gs.get("persistent_equipped")
	var use_demo: bool = pe.is_empty()
	for u in _units:
		if u.get("is_summon", false):
			continue
		var key: String = str(u["id"])
		var list: Array = []
		if not use_demo and pe.has(key):
			if u["side"] == "left":
				for it in (pe[key] as Array):
					if it is Dictionary and it.has("id"):
						list.append({"id": str(it["id"]), "star": int(it.get("star", 1))})
		if use_demo and DEMO_EQUIP.has(key):
			list = (DEMO_EQUIP[key] as Array).duplicate(true)
		u["equips"] = list
		if OS.has_environment("EQDEMO_EQUIP") and u["side"] == "left":   # 装备演示: 携带者强制装该件
			list = [{"id": OS.get_environment("EQDEMO_EQUIP"), "star": (int(OS.get_environment("EQDEMO_STAR")) if OS.has_environment("EQDEMO_STAR") else 1)}]
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
	# (装备 _maxEnergy 原给初始龟能; 龟能模型已换逐技固定冷却 → 装备暂未激活, 先跳过此项)
	_recalc_stats(u)
	_eq_apply_flags(u, item_id, star)

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
			stt["baton_charges"] = 3
		"p2eq_047":   # 重击锤: ATK += maxHp×pct (一次性按当前maxHp折算)
			var pct: float = [0.04, 0.06, 0.15][si]
			u["base_atk"] += u["maxHp"] / HP_MULT * pct
			_recalc_stats(u)
		"p2eq_035":   # 黄铜齿轮: 齿轮层
			stt["gears"] = 0
		"p2eq_034":   # 玩偶小熊: 大熊层累计 + 装备是否已销毁(召唤过大熊)
			stt["bear_layers"] = 0
			stt["bear_done"] = false
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag) + 受伤治疗最低血%友军累积充能
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
			stt["anchor_accum"] = 0.0    # 累积治疗, 满100→+1充能
			stt["anchor_charges"] = 0    # 沉锚充能 (施法时消耗)
		"p2eq_036":   # 温泉蛋: 孵化进度 → 满级全队护盾(一次)
			stt["incub"] = 0.0
			stt["incub_given"] = false
			stt["incub_shield"] = [300.0, 400.0, 600.0][si]
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
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = src["eq_state"].get(iid, {})
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌
				var line: float = [0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					tgt["hp"] = 0.0
					if was: _kill(tgt, src)
			"p2eq_002":   # 海带卷刀: 命中→施加流血层 (3★=0.15×atk; 流血本就层数累加=可叠加, DoT模型无需额外上限)
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "bleed", bs, src)
			"p2eq_003":   # 锋利鲨齿: 溅射相邻格
				var frac: float = [0.15, 0.28, 0.50][si]
				for o in _enemies_of(src):
					if o != tgt and (o["pos"] - tgt["pos"]).length() <= 70.0:
						_apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
			"p2eq_005":   # 双生匕首: 概率追击
				if randf() < [0.5, 0.75, 1.0][si]:
					_apply_damage_from(src, tgt, _atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ff4444"), 0.0, false, true)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外灼烧 + 充能
				var burn: int = maxi(1, roundi([5.0, 7.0, 10.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "burn", burn, src)
				_eq_charge(stt, "fire_mana", 1.0, 8.0, func(): _eq_fire_coral_active(src, si))
			"p2eq_009":   # 宽刃弯刀: 充刃能, 满100→直线伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si], 100.0, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖: 充能25, 满100→连锁闪电
				_eq_charge(stt, "thunder", 25.0, 100.0, func(): _eq_chain_lightning(src, si))
			"p2eq_029":   # 冰封水母: 概率额外魔伤+冻结, 冻结→自护盾
				if randf() < [0.20, 0.25, 0.30][si]:
					_apply_damage_from(src, tgt, [10, 15, 25][si], Color("#bfe9ff"), 0.0, false, true)
					_freeze(tgt, CTRL_SEC)
					_grant_shield(src, [20.0, 30.0, 50.0][si])
			"p2eq_055":   # 靶向器: 命中标记目标 (+20% 受伤) 2回合
				tgt["eq_marked_until"] = _t + EQ_TICK * 2.0
			"p2eq_058":   # 穿甲遗弹: 贯穿→身后同列敌
				var frac2: float = [0.25, 0.40, 0.60][si]
				var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
				for o in _enemies_of(src):
					if o != tgt and _on_line(tgt["pos"], dir, o["pos"], 40.0):
						_apply_damage_from(src, o, maxi(1, int(dmg * frac2)), Color("#ffd07a"), 0.0, false, true)
		src["eq_state"][iid] = stt

# 雷电法杖 026: 连锁闪电
func _eq_chain_lightning(src: Dictionary, si: int) -> void:
	var hops: int = [4, 5, 6][si]; var dmg: int = [20, 25, 30][si]
	var hit: Array = []
	var pool := _enemies_of(src)
	if pool.is_empty():
		return
	var cur = pool[randi() % pool.size()]
	var prev: Vector2 = src["pos"]
	for h in range(hops):
		if cur == null:
			break
		hit.append(cur)
		_bolt_line(prev, cur["pos"], Color("#4dabf7"))
		_apply_damage_from(src, cur, dmg, Color("#4dabf7"), 0.0, true, true)
		prev = cur["pos"]
		var nx = null; var bd := INF
		for o in _enemies_of(src):
			if o in hit: continue
			var dd: float = (o["pos"] - cur["pos"]).length_squared()
			if dd < bd: bd = dd; nx = o
		cur = nx

# 宽刃弯刀 009
func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:
	var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	var line_targets: Array = []
	for o in _enemies_of(src):
		if _on_line(src["pos"], dir, o["pos"], 55.0):
			line_targets.append(o)
	var mult: float = ([2.0, 2.5, 3.0][si]) if line_targets.size() <= 1 else 1.0
	for o in line_targets:
		_apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#9bf0ff"), 0.0, true, true)
		_apply_damage_from(src, o, int(_atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#9bf0ff"), 0.0, false, true)
	_bolt_line(src["pos"], tgt["pos"] + dir * 200.0, Color("#9bf0ff"))

# 灼热火珊瑚 023(主动满法力)
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:
	for o in _enemies_of(src):
		_apply_dot_stacks(o, "burn", 60, src)
		_skill_ring(o["pos"], Color(1.0, 0.5, 0.2, 0.5), 44.0)

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
						_raw_lose(src, refl)
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

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_017":   # 不沉之锚: 施法消耗1充能→击飞最前敌+((0.4/0.6/3.0×(def+mr))+15/25/70%目标maxHp)物理+眩晕1.5s
				var ast: Dictionary = u["eq_state"].get("p2eq_017", {})
				if int(ast.get("anchor_charges", 0)) > 0:
					var at = _nearest_enemy(u)
					if at != null:
						ast["anchor_charges"] = int(ast["anchor_charges"]) - 1
						var adm: int = int([0.4, 0.6, 3.0][si] * (u["def"] + u["mr"]) + at["maxHp"] * [0.15, 0.25, 0.70][si])
						_apply_damage_from(u, at, adm, Color("#9be7ff"), 0.0, false, true)
						_knockback(u, at, 60.0); _freeze(at, CTRL_SEC)
						u["eq_state"]["p2eq_017"] = ast
			"p2eq_006":   # 千刃风暴: 一排剑穿过全体敌
				var flat: int = [70, 100, 400][si]; var sc: float = [0.8, 1.3, 4.0][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, sc, o) + flat, Color("#dfe8ff"), 0.0, false, true)
				_skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.5), 120.0)
			"p2eq_007":   # 锈蚀阔剑: 斩最近敌一横排+自护盾
				var dir: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var tot := 0
				for o in _enemies_of(u):
					if _on_line(u["pos"], dir, o["pos"], 55.0):
						var dd: int = _atk_dmg(u, [0.5, 0.8, 1.1][si], o) + [20, 35, 60][si]
						_apply_damage_from(u, o, dd, Color("#ff4444"), 0.0, false, true); tot += dd
				_grant_shield(u, tot * [0.5, 0.75, 1.0][si])
			"p2eq_008":   # 双穿珊瑚刺: 对最远敌
				var far = null; var fd := -1.0
				for o in _enemies_of(u):
					var dd2: float = (o["pos"] - u["pos"]).length_squared()
					if dd2 > fd: fd = dd2; far = o
				if far != null:
					_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ff4444"), 0.0, false, true)
					_apply_damage_from(u, far, int(far["maxHp"] * [0.08, 0.12, 0.18][si]), Color("#bfe9ff"), 0.0, true, true)
			"p2eq_011":   # 饮血护符坠: 连斩随机敌 (衰减)
				var n: int = [5, 6, 8][si]
				var es := _enemies_of(u)
				for k in range(n):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					var decay: float = pow(0.85, k)
					_apply_damage_from(u, o, int((_atk_dmg(u, [0.5, 0.7, 1.0][si], o) + [40, 50, 70][si]) * decay), Color("#ff8aa0"), 0.33, false, true)
			"p2eq_014":   # 深海堡垒甲(主动): 汲取全敌+回血
				var k2: float = [0.8, 1.0, 1.5][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(k2 * (u["def"] + u["mr"])), Color("#bfe9ff"), 0.0, true, true)
					_heal(u, [40, 65, 130][si])
			"p2eq_022":   # 余烬燃油瓶: 对最近敌灼烧(真火)
				var t2 = _nearest_enemy(u)
				if t2 != null:
					var tf: int = maxi(1, roundi([20, 35, 60][si] + [0.10, 0.15, 0.20][si] * u["atk"]))
					_apply_dot_stacks(t2, "burn", tf, u)
					t2["true_fire_until"] = _t + 5.0
			"p2eq_028":   # 冰霜冻露瓶: 对最近敌魔伤+冰寒(减速)
				var t3 = _nearest_enemy(u)
				if t3 != null:
					_apply_damage_from(u, t3, [40, 60, 100][si], Color("#bfe9ff"), 0.0, true, true)
					t3["slow_until"] = _t + EQ_TICK * 3.0
			"p2eq_030":   # 迷你水晶球A: 沿一列水晶光束+叠层引爆
				var t4 = _nearest_enemy(u)
				if t4 != null:
					var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
					for _seg in range([2, 2, 3][si]):
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir2, o["pos"], 50.0):
								_apply_damage_from(u, o, [30, 35, 40][si], Color("#c9b0ff"), 0.0, true, true)
								_eq_crystal_stack(u, o, si)
					_bolt_line(u["pos"], t4["pos"] + dir2 * 200.0, Color("#c9b0ff"))
			"p2eq_031":   # 迷你水晶球B: 对全体敌魔伤+叠层引爆 (3★引爆波及邻格)
				for o in _enemies_of(u):
					_apply_damage_from(u, o, [20, 25, 30][si], Color("#c9b0ff"), 0.0, true, true)
					_eq_crystal_stack(u, o, si, si == 2)
			"p2eq_039":   # 竹制弓箭: 充能内→强化攻击+自回血+永久+maxHP
				var stt2: Dictionary = u["eq_state"].get("p2eq_039", {})
				if int(stt2.get("bamboo_charges", 0)) > 0:
					stt2["bamboo_charges"] = int(stt2["bamboo_charges"]) - 1
					var t5 = _nearest_enemy(u)
					if t5 != null:
						_apply_damage_from(u, t5, [25, 30, 35][si] + int(u["maxHp"] / HP_MULT * 0.20), Color("#a8ffb0"), 0.0, true, true)
					_heal(u, u["maxHp"] * 0.20)
					var grow: float = [90.0, 95.0, 100.0][si] * HP_MULT
					u["maxHp"] += grow; u["hp"] += grow
					u["eq_state"]["p2eq_039"] = stt2
			"p2eq_048":   # 黄铜手铳: 射N发, 每发命中直线首敌
				var dir3: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				for _b in range([4, 5, 6][si]):
					var ft = _eq_first_in_line(u, dir3, 36.0)
					if ft != null:
						_apply_damage_from(u, ft, _atk_dmg(u, [0.5, 0.54, 0.6][si], ft), Color("#ffd07a"), 0.0, false, true)
			"p2eq_049":   # 连发弩: 对较远半数敌连射, 按已损血加伤
				for o in _eq_farthest_enemies(u, true):
					var lost: float = clampf((1.0 - o["hp"] / o["maxHp"]) / 0.3, 0.0, 1.0)
					var sc2: float = lerpf(0.8, 1.3, lost)
					for _r in range([1, 2, 3][si]):
						_apply_damage_from(u, o, _atk_dmg(u, sc2, o), Color("#ffd07a"), 0.0, false, true)
			"p2eq_050":   # 幽灵加特林: N发随机分布+减甲(每目标累计上限, 防实时高频放技削到0; 用户2026-07-01 on-cast节流, 保守可F5调)
				var g_shred: float = [1.0, 2.0, 3.0][si]
				var g_cap: float = [15.0, 25.0, 40.0][si]   # 该效果对单个目标累计减甲上限
				for _g in range([20, 30, 60][si]):
					var es2 := _enemies_of(u)
					if es2.is_empty(): break
					var o = es2[randi() % es2.size()]
					_apply_damage_from(u, o, _atk_dmg(u, [0.1, 0.12, 0.14][si], o), Color("#d0ffff"), 0.0, false, true)
					var g_acc: float = float(o.get("gatling_shred_acc", 0.0))
					if g_acc < g_cap:
						var g_dec: float = minf(g_shred, g_cap - g_acc)
						o["base_def"] = maxf(0.0, o["base_def"] - g_dec); o["gatling_shred_acc"] = g_acc + g_dec; _recalc_stats(o)
			"p2eq_051":   # 激光手枪: 直线首敌+流血, 身后敌受50%伤害+50%流血
				var dir4: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var first = _eq_first_in_line(u, dir4, 50.0)
				if first != null:
					_apply_damage_from(u, first, _atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
					_apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
					for o in _enemies_of(u):
						if o != first and _on_line(first["pos"], dir4, o["pos"], 50.0):
							_apply_damage_from(u, o, _atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
							_apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si] * 0.5)), u)   # 身后50%流血
			"p2eq_053":   # 霰弹贝古: 扇形N发, 被8+发命中→眩晕
				var hitc: Dictionary = {}
				for _s in range([12, 14, 18][si]):
					var es3 := _enemies_of(u)
					if es3.is_empty(): break
					var o = es3[randi() % es3.size()]
					_apply_damage_from(u, o, _atk_dmg(u, 0.22, o), Color("#ffd07a"), 0.0, false, true)
					hitc[o] = int(hitc.get(o, 0)) + 1
				for o in hitc:
					if int(hitc[o]) >= 8: _freeze(o, CTRL_SEC)
			"p2eq_057":   # 狙击长管: 对最低血%敌沿途敌, 击杀则再开
				_eq_sniper(u, si, 0)
			"p2eq_010":   # 激光长刃: 横扫一列, 命中1则竖斩; 回血
				var t6 = _nearest_enemy(u)
				if t6 != null:
					var dir5: Vector2 = (t6["pos"] - u["pos"]).normalized()
					var tot2 := 0; var cnt := 0
					for o in _enemies_of(u):
						if si == 2 or _on_line(u["pos"], dir5, o["pos"], 55.0):
							var dd3: int = _atk_dmg(u, [1.2, 2.5, 5.0][si], o) + [100, 200, 2000][si]
							_apply_damage_from(u, o, dd3, Color("#9bf0ff"), 0.0, false, true); tot2 += dd3; cnt += 1
					if cnt == 1:
						_apply_damage_from(u, t6, _atk_dmg(u, [1.2, 2.5, 5.0][si], t6), Color("#9bf0ff"), 0.0, false, true)
					_heal(u, tot2 * [0.35, 0.8, 1.0][si])

# 水晶叠层 (A/B共用); splash=true(B 3★): 引爆范围扩大50%波及邻格敌
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int, splash: bool = false) -> void:
	var lv := _add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		_consume_stacks(o, "p2crystal")
		var det: int = int(o["maxHp"] * [0.14, 0.17, 0.20][si])
		_apply_damage_from(src, o, det, Color("#c9b0ff"), 0.0, true, true)
		if splash:   # B 3★: 引爆波及邻格敌 (基础邻格~60px, 扩大50%→90px)
			for adj in _enemies_of(src):
				if adj != o and (adj["pos"] - o["pos"]).length() <= 90.0:
					_apply_damage_from(src, adj, int(adj["maxHp"] * [0.14, 0.17, 0.20][si]), Color("#c9b0ff"), 0.0, true, true)

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
	_bolt_line(u["pos"], low["pos"], Color("#ff4444"))
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
			"p2eq_033":   # 复活海螺: 阵亡→原位变小虫 (复用 _spawn_summon, 3D 用色块 block)
				var worm = _spawn_summon(u, "worm", [150.0, 200.0, 300.0][si] * HP_MULT * _lvl_mult_for(u), [20.0, 30.0, 40.0][si] * _lvl_mult_for(u), {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
				if worm != null:
					worm["pos"] = u["pos"]
					if is_instance_valid(worm["sprite"]): worm["sprite"].position = _world_pos(u["pos"], GROUND_LIFT)
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
			"p2eq_035":   # 黄铜齿轮: 死亡→每层折2深海币 (仅玩家左队计入)
				var gears: int = int(stt.get("gears", 0))
				if gears > 0 and u["side"] == "left":
					var gs = get_node_or_null("/root/GameState")
					if gs != null and gs.get("meta_deepsea_coins") != null:
						gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + gears * 2)
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
			"p2eq_044":   # 深海项链: 首次<50%回血
				_heal(u, u["maxHp"] * [0.12, 0.27, 0.40][si]); fired = true
			"p2eq_045":   # 珍珠耳环: 首次<50%回血+发火球
				_heal(u, u["maxHp"] * [0.15, 0.29, 0.65][si])
				var balls: int = [1, 1, 2][si]
				var es := _enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_apply_damage_from(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), Color("#ff7a33"), 0.0, true, true)
					_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
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
			"p2eq_001":   # 锈蚀短剑: 每周期劈砍最近敌
				var t = _nearest_enemy(u)
				if t != null:
					_apply_damage_from(u, t, _atk_dmg(u, [0.6, 0.75, 1.0][si], t) + int([40, 60, 100][si] * u["crit"]), Color("#ff4444"), 0.0, false, true)
			"p2eq_012":   # 龟苓膏块: 每周期自护盾
				_grant_shield(u, [30.0, 40.0, 55.0][si])
			"p2eq_016":   # 铁壁盾: 每周期全队(含自己)护盾
				for o in _allies_of(u):
					_grant_shield(o, [15.0, 20.0, 25.0][si])
			"p2eq_018":   # 守护贝壳: 每周期自回血
				_heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])
			"p2eq_019":   # 海葵药膏: 每周期奶自己+最低血友军
				_heal(u, [30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si])
				var low = _lowest_hp_ally(u)
				if low != null and low != u:
					_heal(low, [30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si])
			"p2eq_020":   # 哑铃: 每周期+锻炼层 + 向最近敌扔哑铃
				var gain: float = [20.0, 25.0, 30.0][si] * HP_MULT
				u["maxHp"] += gain; u["hp"] += gain
				var t2 = _nearest_enemy(u)
				if t2 != null:
					_apply_damage_from(u, t2, int(u["maxHp"] / HP_MULT * [0.05, 0.07, 0.10][si]), Color("#ff4444"), 0.0, false, true)
			"p2eq_021":   # 守护贝母: 每周期连接攻击最高友军→护盾+20龟能+净化1/1/2+伤害转移25/40/60%给携带者
				# 先清掉上周期连接对象的转移标记 (每2.5秒重新连接)
				var prev_link = stt.get("link_target", null)
				if prev_link is Dictionary:
					prev_link.erase("dmg_redirect_to")
				var best = null; var ba := -1.0
				for o in _allies_of(u):
					if o["atk"] > ba: ba = o["atk"]; best = o
				if best != null:
					_grant_shield(best, [40.0, 60.0, 90.0][si])
					_cleanse_n(best, [1, 1, 2][si])   # 净化1/1/2个负面
					if _has_energy_system(best):
						_eq_grant_energy(best, 20.0)   # +20龟能 (实时版=扣冷却)
					# 伤害转移: best 受到的 25/40/60% 入伤转给携带者 u 承担 (维持到下次连接前)
					if best != u:
						best["dmg_redirect_to"] = {"carrier": u, "pct": [0.25, 0.40, 0.60][si], "until": _t + EQ_TICK + 0.1}
					stt["link_target"] = best
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙直线扫射
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 每周期降N道雷各电击随机敌
				for _d in range([1, 2, 3][si]):
					var es := _enemies_of(u)
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_bolt_line(Vector2(o["pos"].x, ARENA.position.y), o["pos"], Color("#4dabf7"))
					_apply_damage_from(u, o, int(u["atk"]), Color("#4dabf7"), 0.0, true, true)
			"p2eq_027":   # 电棍: 每周期电击随机敌+眩晕, 消耗1层
				if int(stt.get("baton_charges", 0)) > 0:
					var es2 := _enemies_of(u)
					if not es2.is_empty():
						stt["baton_charges"] = int(stt["baton_charges"]) - 1
						var o = es2[randi() % es2.size()]
						_apply_damage_from(u, o, [30, 40, 50][si], Color("#4dabf7"), 0.0, true, true)
						_freeze(o, CTRL_SEC)
			"p2eq_035":   # 黄铜齿轮: 每周期+N层
				stt["gears"] = int(stt.get("gears", 0)) + [1, 2, 3][si]
			"p2eq_034":   # 玩偶小熊: 每周期派小熊冲最近敌(伤害+击飞)+1大熊层; 满5/3/1层→销毁装备召唤大熊
				if not bool(stt.get("bear_done", false)):
					var mt = _nearest_enemy(u)   # 优先前排(最近)
					if mt != null:
						var bdm: int = _atk_dmg(u, [1.0, 2.0, 5.0][si], mt) + [100, 210, 1000][si]
						_summon_walking_bear(u, mt, bdm)
						stt["bear_layers"] = int(stt.get("bear_layers", 0)) + 1
						if int(stt["bear_layers"]) >= [5, 3, 1][si]:
							stt["bear_done"] = true
							var bear = _spawn_summon(u, "bear", 250.0 * HP_MULT * _lvl_mult_for(u), 50.0 * _lvl_mult_for(u), {"label": "大熊", "spr_id": "doll-bear", "col_size": 40.0, "hp_w": 30.0})
							if bear != null:
								bear["eq_state"] = {}; bear["equips"] = []
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				stt["incub"] = float(stt.get("incub", 0.0)) + 5.0
				if float(stt["incub"]) >= 100.0 and not bool(stt.get("incub_given", false)):
					stt["incub_given"] = true
					var allies := _allies_of(u)
					var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
					for o in allies:
						_grant_shield(o, per)
			"p2eq_042":   # 涟漪药剂: 每周期全队回已损血 3/6/10%; 3★生命最低友军双倍
				var low042 = null; var lv042 := INF
				if si == 2:
					for o in _allies_of(u):
						var p042: float = o["hp"] / maxf(1.0, o["maxHp"])
						if p042 < lv042: lv042 = p042; low042 = o
				for o in _allies_of(u):
					var pct042: float = [0.03, 0.06, 0.10][si]
					if si == 2 and o == low042:
						pct042 *= 2.0
					_heal(o, (o["maxHp"] - o["hp"]) * pct042)
			"p2eq_043":   # 海浪护符: 每周期+1巨浪层, 满→横排扫敌我
				stt["wave"] = int(stt.get("wave", 0)) + 1
				if int(stt["wave"]) >= [3, 2, 2][si]:
					stt["wave"] = 0
					for o in _allies_of(u):
						_grant_shield(o, [40.0, 95.0, 120.0][si]); o["base_def"] += [2, 3, 5][si]; o["base_mr"] += [2, 3, 5][si]; _recalc_stats(o)
					for o in _enemies_of(u):
						_apply_damage_from(u, o, [60, 110, 200][si], Color("#9be7ff"), 0.0, true, true)
						o["base_def"] = maxf(0.0, o["base_def"] - [2, 3, 5][si]); o["base_mr"] = maxf(0.0, o["base_mr"] - [2, 3, 5][si]); _recalc_stats(o)
			"p2eq_052":   # 左轮: 每周期向随机敌射1发, 子弹0停
				if int(stt.get("revolver_bullets", 0)) > 0:
					var es3 := _enemies_of(u)
					if not es3.is_empty():
						stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
						var o = es3[randi() % es3.size()]
						_fire_bolt_from(u, o, _atk_dmg(u, [3.0, 5.0, 9.0][si], o) + [150, 310, 1200][si], Color("#ffd07a"))
			"p2eq_037":   # 蛋糕蜡烛: 3阶段循环
				var ph: int = int(stt.get("candle", 0))
				stt["candle"] = (ph + 1) % 3
				if ph == 1:   # 微弱: 回血
					_heal(u, [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si])
				elif ph == 2:   # 燃烧: 随机敌横排魔伤+灼烧
					var t3 = _nearest_enemy(u)
					if t3 != null:
						var dir: Vector2 = (t3["pos"] - u["pos"]).normalized()
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir, o["pos"], 55.0):
								_apply_damage_from(u, o, [20, 30, 44][si] + int(u["atk"] * [0.5, 0.7, 1.0][si]), Color("#ff7a33"), 0.0, true, true)
								_apply_dot_stacks(o, "burn", [20, 30, 40][si], u)
			"p2eq_038":   # 信号放大器: 每周期刷新本回合增伤buff
				var lo: Array = [0.10, 0.25, 0.70]; var hi: Array = [0.16, 0.40, 0.80]
				var amp: float = randf_range(lo[si], hi[si])
				_buff(u, "atk", amp, true, EQ_TICK + 0.1)
			"p2eq_040":   # FPGA板: 每周期抽N个状态当回合生效
				for _k in range([1, 2, 4][si]):
					match randi() % 4:
						0: _heal(u, u["maxHp"] * 0.05); u["base_def"] += 2; u["base_mr"] += 2; _recalc_stats(u)
						1: u["base_atk"] += 5; u["lifesteal"] += 0.04; _recalc_stats(u)
						2: _buff(u, "atk", 0.15, true, EQ_TICK + 0.1)
						3: _buff(u, "def", 0.25, true, EQ_TICK + 0.1)
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				for o in _enemies_of(u):
					if _t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						_fire_bolt_from(u, o, _atk_dmg(u, [1.5, 3.0, 9.0][si], o) + [130, 190, 600][si], Color("#ffd07a"))
						_apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * 0.1)), u)
		u["eq_state"][iid] = stt
	# 复活海螺3★ 小虫分裂 (简化: worm 单位每周期空位分裂一只)
	if u.get("worm_split", false) and _count_summons(u["side"], "worm") < 4:
		var nw = _spawn_summon(u, "worm", u["maxHp"], u["atk"], {"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
		if nw != null:
			nw["eq_state"] = {}; nw["equips"] = []; nw["worm_split"] = true

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es := _enemies_of(u)
	if es.is_empty():
		return
	var anchor = es[randi() % es.size()]
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	_bolt_line(u["pos"], anchor["pos"] + dir * 200.0, Color("#ff7a33"))
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [50, 120, 1500][si], Color("#ff7a33"), 0.0, true, true)
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
	for o in _allies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_heal(o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [70, 150, 1000][si])

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

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)

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

	# 整框点击 → 详情面板
	frame.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_unit_info_panel(u))

	# 引用挂在单位字典上, 供 _update_team_panels 每帧刷
	u["panel_frame"] = frame
	u["panel_hp_fill"] = hp_fill
	u["panel_stylebox"] = sb
	return frame

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
	# 关闭 ✕
	var close_btn := Button.new()
	close_btn.text = "✕"
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
